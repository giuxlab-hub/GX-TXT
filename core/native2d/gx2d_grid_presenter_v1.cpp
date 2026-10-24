/* SPDX-License-Identifier: GPL-3.0-or-later
 * Retained CORE Cairo grid/axes item, using the public Tk custom-item contract.
 * No geometry lives here: gx2d generates grid and device positions; public axis
 * owners supply every tick, unit and label. One item sits below scientific Tk
 * items. Pixmaps and glyph coverage belong to this object's Tk lifetime.
 */
#include "gx2d_grid_presenter_v1.h"
#include "gx2d_presentation_batch.h"
#include <tk.h>
#include <cairo.h>
#include <cairo-xlib.h>
#include <X11/Xutil.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <sstream>
#include <set>
#include <string>
#include <vector>
namespace {
struct Error {};
struct Obj {
 Tcl_Obj *p;explicit Obj(Tcl_Obj *v):p(v){Tcl_IncrRefCount(p);}Obj(const Obj &v):Obj(v.p){}~Obj(){Tcl_DecrRefCount(p);}Obj &operator=(const Obj &)=delete;
};
Obj str(const char *s){return Obj(Tcl_NewStringObj(s,-1));}
void fail(Tcl_Interp *ip,const char *s){Tcl_SetObjResult(ip,Tcl_NewStringObj(s,-1));throw Error{};}
Tcl_Obj *get(Tcl_Interp *ip,Tcl_Obj *o,const char *key){auto k=str(key);Tcl_Obj *v=nullptr;if(Tcl_DictObjGet(ip,o,k.p,&v)!=TCL_OK)throw Error{};if(!v)fail(ip,"Native grid presentation field is missing");return v;}
void put(Tcl_Obj *o,const char *k,Tcl_Obj *v){auto key=str(k);Tcl_DictObjPut(nullptr,o,key.p,v);}
std::vector<Tcl_Obj *> list(Tcl_Interp *ip,Tcl_Obj *o){int n;Tcl_Obj **v;if(Tcl_ListObjGetElements(ip,o,&n,&v)!=TCL_OK)throw Error{};return {v,v+n};}
double number(Tcl_Interp *ip,Tcl_Obj *o){double n;if(Tcl_GetDoubleFromObj(ip,o,&n)!=TCL_OK||!std::isfinite(n))fail(ip,"Native grid requires finite presentation coordinates");return n;}
std::string text(Tcl_Interp *ip,Tcl_Obj *o){int n;const char *s=Tcl_GetStringFromObj(o,&n);Tcl_DString d;Tcl_DStringInit(&d);auto enc=Tcl_GetEncoding(ip,"utf-8");Tcl_UtfToExternalDString(enc,s,n,&d);std::string result(Tcl_DStringValue(&d),Tcl_DStringLength(&d));Tcl_DStringFree(&d);Tcl_FreeEncoding(enc);return result;}
Obj call(Tcl_Interp *ip,std::vector<Tcl_Obj *> v){if(Tcl_EvalObjv(ip,(int)v.size(),v.data(),TCL_EVAL_GLOBAL)!=TCL_OK)throw Error{};return Obj(Tcl_GetObjResult(ip));}
struct Grid;
struct Item {Tk_Item header;Grid *owner;};
struct Glyph {
 std::vector<uint32_t> pixels;cairo_surface_t *surface=nullptr;int width=0,height=0,dx=0,dy=0;
 ~Glyph(){if(surface)cairo_surface_destroy(surface);}
};
struct Stroke {double ax,ay,bx,by,width;std::string color;int dash=0;};
struct Label {std::string value,anchor;Tcl_Obj *source;double x,y,angle;};
struct ControlItem {int id=0;uint64_t frame=0;std::vector<double> xy;std::string fill,outline;};
struct Grid {
 Tcl_Interp *ip;Tk_Window win;Display *display;Tk_Canvas canvas=nullptr;Item *item=nullptr;Tcl_Command command=nullptr;
 std::string name,path,lastKey,fontKey;Pixmap front=None;int width=0,height=0,density=-1;bool dirty=true;
 uint64_t updates=0,renders=0,cacheHits=0,frame=0,controlUpdates=0;std::map<std::pair<gx2d_id,size_t>,ControlItem> controls;std::map<std::string,std::unique_ptr<Glyph>> glyphs;
 std::unique_ptr<Obj> data,lines,positions;std::vector<Stroke> strokes;
 Grid(Tcl_Interp *i,Tk_Window w,std::string p):ip(i),win(w),display(Tk_Display(w)),path(std::move(p)){}
 Obj canvasCall(std::initializer_list<Tcl_Obj *> a){auto c=str(path.c_str());std::vector<Tcl_Obj *> v{c.p};v.insert(v.end(),a);return call(ip,v);}
 void ensureItem();
 void redraw(){if(item)Tk_CanvasEventuallyRedraw(canvas,0,0,item->header.x2,item->header.y2);}
 void clearPixmap(){if(front!=None){Tk_FreePixmap(Tk_Display(win),front);front=None;}}
 ~Grid();
};
int objectCommand(ClientData,Tcl_Interp *,int,Tcl_Obj *const []);
Tk_CustomOption tagsOption={Tk_CanvasTagsParseProc,Tk_CanvasTagsPrintProc,nullptr};
Tk_ConfigSpec specs[]={{TK_CONFIG_CUSTOM,"-tags",nullptr,nullptr,nullptr,0,TK_CONFIG_NULL_OK,&tagsOption},{TK_CONFIG_END,nullptr,nullptr,nullptr,nullptr,0,0,nullptr}};
int itemConfig(Tcl_Interp *ip,Tk_Canvas canvas,Tk_Item *base,int n,Tcl_Obj *const v[],int){
 if(n%2){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native grid item supports -tags only; use presenter configuration",-1));return TCL_ERROR;}
 for(int i=0;i<n;i+=2){if(std::string(Tcl_GetString(v[i]))!="-tags" || Tk_CanvasTagsParseProc(nullptr,ip,Tk_CanvasTkwin(canvas),Tcl_GetString(v[i+1]),(char *)base,0)!=TCL_OK)return TCL_ERROR;}
 return TCL_OK;
}
int itemCreate(Tcl_Interp *ip,Tk_Canvas canvas,Tk_Item *base,int n,Tcl_Obj *const v[]){
 auto item=(Item *)base;item->owner=nullptr;Tcl_CmdInfo info;
 if(n!=1||!Tcl_GetCommandInfo(ip,Tcl_GetString(v[0]),&info)||info.objProc!=objectCommand){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native grid item requires its CORE presenter owner",-1));return TCL_ERROR;}
 auto g=(Grid *)info.objClientData;if(g->item){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native grid already has an item",-1));return TCL_ERROR;}
 item->owner=g;g->canvas=canvas;g->item=item;base->x1=0;base->y1=0;base->x2=std::max(1,g->width);base->y2=std::max(1,g->height);base->state=TK_STATE_DISABLED;
 return Tk_CanvasTagsParseProc(nullptr,ip,Tk_CanvasTkwin(canvas),"native_grid_presenter",(char *)base,0);
}
int itemCoords(Tcl_Interp *ip,Tk_Canvas,Tk_Item *base,int n,Tcl_Obj *const []){
 if(n){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native grid positions belong to the scene/presenter update",-1));return TCL_ERROR;}
 Tcl_Obj *v[]={Tcl_NewIntObj(base->x1),Tcl_NewIntObj(base->y1),Tcl_NewIntObj(base->x2),Tcl_NewIntObj(base->y2)};Tcl_SetObjResult(ip,Tcl_NewListObj(4,v));return TCL_OK;
}
void itemDelete(Tk_Canvas,Tk_Item *base,Display *){auto i=(Item *)base;if(i->owner)i->owner->item=nullptr;i->owner=nullptr;}
void itemDisplay(Tk_Canvas canvas,Tk_Item *base,Display *d,Drawable target,int x,int y,int w,int h){
 auto g=((Item *)base)->owner;if(!g||g->front==None)return;
 int sx=std::max(x,0),sy=std::max(y,0),right=std::min(x+w,g->width),bottom=std::min(y+h,g->height);if(right<=sx||bottom<=sy)return;
 short ox,oy;Tk_CanvasDrawableCoords(canvas,0,0,&ox,&oy);GC gc=Tk_GetGC(g->win,0,nullptr);
 XCopyArea(d,g->front,target,gc,sx,sy,(unsigned)(right-sx),(unsigned)(bottom-sy),ox+sx,oy+sy);Tk_FreeGC(d,gc);
}
double itemPoint(Tk_Canvas,Tk_Item *,double *){return 1e36;}
int itemArea(Tk_Canvas,Tk_Item *,double *){return -1;}
void itemScale(Tk_Canvas,Tk_Item *,double,double,double,double){}
void itemTranslate(Tk_Canvas,Tk_Item *,double,double){}
Tk_ItemType itemType={"gx2dgrid",sizeof(Item),itemCreate,specs,itemConfig,itemCoords,itemDelete,itemDisplay,TK_CONFIG_OBJS,itemPoint,itemArea,nullptr,itemScale,itemTranslate,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,0,nullptr,nullptr};
void Grid::ensureItem(){
 if(item)return;
 if(!controls.empty()){auto erase=str("delete"),owned=str("native_batch_item");canvasCall({erase.p,owned.p});controls.clear();}
 auto create=str("create"),kind=str("gx2dgrid"),handle=str(name.c_str());canvasCall({create.p,kind.p,handle.p});
}
void ownerEvent(ClientData value,XEvent *e){auto g=(Grid *)value;if(e->type==DestroyNotify){g->win=nullptr;if(g->command)Tcl_DeleteCommandFromToken(g->ip,g->command);}}
Grid::~Grid(){
 if(win && !Tcl_InterpDeleted(ip)){auto erase=str("delete"),owned=str("native_batch_item");try{canvasCall({erase.p,owned.p});}catch(const Error &){Tcl_ResetResult(ip);}}
 if(win){Tk_DeleteEventHandler(win,StructureNotifyMask,ownerEvent,this);if(item){auto id=Obj(Tcl_NewIntObj(item->header.id));item->owner=nullptr;item=nullptr;if(!Tcl_InterpDeleted(ip)){auto del=str("delete");try{canvasCall({del.p,id.p});}catch(const Error &){Tcl_ResetResult(ip);}}}}
 // Tk's Display outlives the widget during DestroyNotify; stored pixmap uses it.
 if(front!=None)Tk_FreePixmap(display,front);
}
void objectDeleted(ClientData value){auto g=(Grid *)value;g->command=nullptr;delete g;}
void rgb(cairo_t *cr,const std::string &hex){unsigned r=0,g=0,b=0;if(hex.size()==7)sscanf(hex.c_str()+1,"%02x%02x%02x",&r,&g,&b);cairo_set_source_rgb(cr,r/255.,g/255.,b/255.);}
std::string composite(gx2d_color c,const std::string &bg){unsigned r=255,g=255,b=255;sscanf(bg.c_str()+1,"%02x%02x%02x",&r,&g,&b);auto blend=[&](double value,unsigned under){return (unsigned)std::lround(std::lround(value*255)*c.alpha+under*(1-c.alpha));};char out[8];snprintf(out,sizeof out,"#%02x%02x%02x",blend(c.red,r),blend(c.green,g),blend(c.blue,b));return out;}
Glyph &glyph(Grid *g,Tcl_Obj *label,const std::string &anchor,double angle,Tcl_Obj *font,Tcl_Obj *rgba){
 auto a=str(anchor.c_str());auto rotation=Obj(Tcl_NewDoubleObj(angle));std::string key=g->fontKey+Tcl_GetString(label)+"/"+anchor+std::to_string(angle)+Tcl_GetString(rgba);
 auto found=g->glyphs.find(key);if(found!=g->glyphs.end())return *found->second;
 if(g->glyphs.size()>=256)g->glyphs.clear();
 auto image=str("image"),create=str("create"),photo=str("photo"),erase=str("delete");auto handle=call(g->ip,{image.p,create.p,photo.p});auto textCommand=str("::gx::native2d::text_photo");
 std::unique_ptr<Glyph> result(new Glyph);
 try {
  auto receipt=call(g->ip,{textCommand.p,handle.p,font,label,a.p,rotation.p,rgba});auto offset=list(g->ip,get(g->ip,receipt.p,"offset"));result->dx=(int)number(g->ip,offset[0]);result->dy=(int)number(g->ip,offset[1]);
  auto p=Tk_FindPhoto(g->ip,Tcl_GetString(handle.p));Tk_PhotoImageBlock block;if(!p||!Tk_PhotoGetImage(p,&block))fail(g->ip,"Native grid text coverage is unavailable");
  result->width=block.width;result->height=block.height;result->pixels.resize((size_t)block.width*block.height);
  for(int y=0;y<block.height;++y)for(int x=0;x<block.width;++x){auto src=block.pixelPtr+y*block.pitch+x*block.pixelSize;unsigned alpha=src[block.offset[3]];result->pixels[(size_t)y*block.width+x]=(alpha<<24)|((src[block.offset[0]]*alpha/255)<<16)|((src[block.offset[1]]*alpha/255)<<8)|(src[block.offset[2]]*alpha/255);}
  result->surface=cairo_image_surface_create_for_data((unsigned char *)result->pixels.data(),CAIRO_FORMAT_ARGB32,result->width,result->height,result->width*4);
  call(g->ip,{image.p,erase.p,handle.p});
 }catch(...){try{call(g->ip,{image.p,erase.p,handle.p});}catch(...){ }throw;}
 auto ptr=result.get();g->glyphs.emplace(std::move(key),std::move(result));return *ptr;
}
std::string nativeKey(const gx2d_scene *scene){
 gx2d_view_state s{};gx2d_view v{};gx2d_view_state_get(scene,&s);gx2d_view_get(scene,&v);std::ostringstream o;o<<std::hexfloat;
 auto add=[&](double n){o<<'/'<<n;};for(double n:{v.width,v.height,v.left,v.top,v.right,v.bottom,v.world.x0,v.world.y0,v.world.x1,v.world.y1})add(n);
 auto &g=s.grid;for(double n:{g.origin.x,g.origin.y,g.spacing_x,g.spacing_y,g.angle,g.major_width,g.minor_width,g.axes_width})add(n);
 for(auto c:{g.minor_color,g.major_color,g.axes_color})for(double n:{c.red,c.green,c.blue,c.alpha})add(n);
 o<<g.enabled<<g.visible<<g.snap_enabled<<g.major_visible<<g.minor_visible<<g.axes_visible<<'/'<<g.major_interval<<'/'<<g.minor_style<<'/'<<g.major_style<<'/'<<g.axes_style<<'/'<<s.coordinate_mode;
 auto &p=s.polar;for(double n:{p.origin.x,p.origin.y,p.theta_zero,p.radius_min,p.radius_max,p.angle_min,p.angle_span,p.radial_spacing,p.angular_spacing})add(n);o<<'/'<<p.clockwise<<p.degrees<<'/'<<p.radial_major_interval<<'/'<<p.angular_major_interval;
 return o.str();
}
void update(Grid *g,const gx2d_scene *scene,Tcl_Obj *data){
 gx2d_view v{};gx2d_grid grid{};if(gx2d_view_get(scene,&v)!=GX2D_OK||gx2d_grid_get(scene,&grid)!=GX2D_OK)fail(g->ip,"Native grid scene is unavailable");
 int width=(int)v.width,height=(int)v.height;if(width<1||height<1||width>16384||height>16384||(int64_t)width*height>32000000)fail(g->ip,"Native grid dimensions exceed presentation capacity");
 int density;if(Tcl_GetBooleanFromObj(g->ip,get(g->ip,data,"adaptive_density"),&density)!=TCL_OK)throw Error{};if(g->density>=0)density=g->density;
 std::string key=nativeKey(scene)+Tcl_GetString(data)+std::to_string(density);++g->updates;g->ensureItem();if(!g->dirty&&key==g->lastKey){++g->cacheHits;return;}
 auto plans=get(g->ip,data,"plans");auto font=get(g->ip,data,"font");auto signature=get(g->ip,data,"font_signature");std::string fontKey=Tcl_GetString(signature);if(fontKey!=g->fontKey){g->glyphs.clear();g->fontKey=fontKey;}
 std::string bg=Tcl_GetString(get(g->ip,data,"background")),ink=Tcl_GetString(get(g->ip,data,"text_color"));auto rgba=get(g->ip,data,"text_rgba");
 std::vector<Label> labels;std::vector<Stroke> strokes;
 if(gx2d_grid_presentation(g->ip,scene,density?16:0)!=TCL_OK)throw Error{};Obj lines(Tcl_GetObjResult(g->ip));
 for(auto line:list(g->ip,lines.p)){auto p=list(g->ip,line);int kind=(int)number(g->ip,p[4]);gx2d_color c=kind==0?grid.minor_color:kind==1?grid.major_color:grid.axes_color;double w=kind==0?grid.minor_width:kind==1?grid.major_width:grid.axes_width;int dash=kind==0?grid.minor_style:kind==1?grid.major_style:grid.axes_style;gx2d_point a,b;int shown;
  auto code=gx2d_viewport_clip_segment(scene,{number(g->ip,p[0]),number(g->ip,p[1])},{number(g->ip,p[2]),number(g->ip,p[3])},w/2,&a,&b,&shown);if(code!=GX2D_OK)fail(g->ip,gx2d_status_text(code));if(shown)strokes.push_back({a.x,a.y,b.x,b.y,w,composite(c,bg),dash});
 }
 for(const char *axis:{"x","y"}){
  auto plan=get(g->ip,plans,axis);auto ticks=list(g->ip,get(g->ip,plan,"ticks"));if(ticks.size()>64)fail(g->ip,"Native axis supports at most64ticks");
  for(auto tick:ticks){double value=number(g->ip,get(g->ip,tick,"value"));auto label=get(g->ip,tick,"label");if(Tcl_GetCharLength(label)>256)fail(g->ip,"Native grid label exceeds256characters");gx2d_point p;bool x=axis[0]=='x';auto code=gx2d_world_to_device(scene,x?gx2d_point{value,v.world.y0}:gx2d_point{v.world.x0,value},&p);if(code!=GX2D_OK)fail(g->ip,gx2d_status_text(code));double right=v.width-v.right,bottom=v.height-v.bottom;
   if(grid.visible)strokes.push_back(x?Stroke{p.x,v.top,p.x,bottom,1,"#d8e1e9",3}:Stroke{v.left,p.y,right,p.y,1,"#d8e1e9",3});
   strokes.push_back(x?Stroke{p.x,bottom,p.x,bottom+4,1,ink,0}:Stroke{v.left-4,p.y,v.left,p.y,1,ink,0});
   labels.push_back({text(g->ip,label),x?"center":"e",label,x?p.x:v.left-7,x?bottom+15:p.y,0});
  }
  auto title=get(g->ip,plan,"label");bool x=axis[0]=='x';labels.push_back({text(g->ip,title),"center",title,x?(v.left+v.width-v.right)/2:13,x?v.height-14:(v.top+v.height-v.bottom)/2,x?0.:90.});
 }
 // Build a complete back buffer; failed updates leave the previous front intact.
 Tk_MakeWindowExist(g->win);Display *display=Tk_Display(g->win);Pixmap back=Tk_GetPixmap(display,Tk_WindowId(g->win),width,height,Tk_Depth(g->win));
 cairo_surface_t *surface=cairo_xlib_surface_create(display,back,Tk_Visual(g->win),width,height);cairo_t *cr=cairo_create(surface);
 try {
  rgb(cr,bg);cairo_paint(cr);cairo_set_antialias(cr,CAIRO_ANTIALIAS_NONE);
  rgb(cr,"#9babbc");cairo_set_line_width(cr,1);cairo_rectangle(cr,v.left+.5,v.top+.5,v.width-v.left-v.right,v.height-v.top-v.bottom);cairo_stroke(cr);
  for(auto &s:strokes){rgb(cr,s.color);cairo_set_line_width(cr,s.width);double d[2];int count=0;if(s.dash==1){d[0]=6;d[1]=3;count=2;}if(s.dash==2){d[0]=1;d[1]=3;count=2;}if(s.dash==3){d[0]=2;d[1]=4;count=2;}cairo_set_dash(cr,d,count,0);double offset=std::fmod(std::round(s.width),2)==1?.5:0;cairo_move_to(cr,std::round(s.ax)+offset,std::round(s.ay)+offset);cairo_line_to(cr,std::round(s.bx)+offset,std::round(s.by)+offset);cairo_stroke(cr);}
  Obj positions(Tcl_NewListObj(0,nullptr));
  for(auto &l:labels){auto &mask=glyph(g,l.source,l.anchor,l.angle,font,rgba);double x=std::round(l.x)+mask.dx,y=std::round(l.y)+mask.dy;cairo_set_source_surface(cr,mask.surface,x,y);cairo_paint(cr);Tcl_Obj *xy[]={Tcl_NewDoubleObj(l.x),Tcl_NewDoubleObj(l.y)};Tcl_Obj *entry=Tcl_NewDictObj();put(entry,"label",l.source);put(entry,"at",Tcl_NewListObj(2,xy));put(entry,"angle",Tcl_NewDoubleObj(l.angle));put(entry,"anchor",Tcl_NewStringObj(l.anchor.c_str(),-1));Tcl_ListObjAppendElement(g->ip,positions.p,entry);}
  if(cairo_status(cr)!=CAIRO_STATUS_SUCCESS)fail(g->ip,cairo_status_to_string(cairo_status(cr)));cairo_destroy(cr);cr=nullptr;cairo_surface_flush(surface);cairo_surface_destroy(surface);surface=nullptr;
  g->clearPixmap();g->front=back;back=None;g->width=width;g->height=height;g->data.reset(new Obj(data));g->lines.reset(new Obj(lines));g->positions.reset(new Obj(positions));g->strokes=std::move(strokes);g->lastKey=std::move(key);g->dirty=false;++g->renders;g->item->header.x2=width;g->item->header.y2=height;g->redraw();
 }catch(...){if(cr)cairo_destroy(cr);if(surface)cairo_surface_destroy(surface);if(back!=None)Tk_FreePixmap(display,back);throw;}
}
Obj describe(Grid *g){
 Obj d(Tcl_NewDictObj());put(d.p,"renderer",Tcl_NewStringObj("Native2D.Cairo.RetainedCanvasGrid",-1));put(d.p,"updates",Tcl_NewWideIntObj(g->updates));put(d.p,"renders",Tcl_NewWideIntObj(g->renders));put(d.p,"cache_hits",Tcl_NewWideIntObj(g->cacheHits));put(d.p,"glyphs",Tcl_NewIntObj((int)g->glyphs.size()));put(d.p,"item",Tcl_NewIntObj(g->item?g->item->header.id:0));put(d.p,"dirty",Tcl_NewBooleanObj(g->dirty));put(d.p,"adaptive_density",Tcl_NewIntObj(g->density));put(d.p,"retained_controls",Tcl_NewIntObj((int)g->controls.size()));put(d.p,"control_updates",Tcl_NewWideIntObj(g->controlUpdates));
 if(g->data){put(d.p,"presentation",g->data->p);put(d.p,"grid_lines",g->lines->p);put(d.p,"label_positions",g->positions->p);}return d;
}
int objectCommand(ClientData value,Tcl_Interp *ip,int n,Tcl_Obj *const v[]){
 auto g=(Grid *)value;
 try {
  if(n<2)fail(ip,"Grid presenter needs begin|configure|invalidate|describe|position|destroy");std::string op=Tcl_GetString(v[1]);
  if(op=="destroy"&&n==2){Tcl_DeleteCommandFromToken(ip,g->command);return TCL_OK;}
  if(op=="describe"&&n==2){auto d=describe(g);Tcl_SetObjResult(ip,d.p);return TCL_OK;}
  if(op=="invalidate"&&n==2){g->dirty=true;return TCL_OK;}
  if(op=="configure"&&n==3){auto mode=Tcl_GetString(v[2]);if(std::string(mode)=="global")g->density=-1;else {int x;if(Tcl_GetBooleanFromObj(ip,v[2],&x)!=TCL_OK)throw Error{};g->density=x;}g->dirty=true;return TCL_OK;}
  if(op=="begin"&&n==2){g->ensureItem();auto erase=str("delete"),transient=str("!native_grid_presenter&&!native_batch_item");++g->frame;g->canvasCall({erase.p,transient.p});Tcl_SetObjResult(ip,Tcl_NewIntObj(g->item->header.id));return TCL_OK;}
  if(op=="end"&&n==2){auto erase=str("delete");for(auto i=g->controls.begin();i!=g->controls.end();){if(i->second.frame!=g->frame){auto id=Obj(Tcl_NewIntObj(i->second.id));g->canvasCall({erase.p,id.p});i=g->controls.erase(i);}else ++i;}return TCL_OK;}
  if(op=="position"&&n==3){auto widget=str(g->path.c_str()),coords=str("coords");auto records=list(ip,v[2]);if(records.size()>65536)fail(ip,"Native positioning batch exceeds capacity");for(auto record:records){auto row=list(ip,record);if(row.size()!=2)fail(ip,"Position batch expects {item coordinate_list} records");int id;if(Tcl_GetIntFromObj(ip,row[0],&id)!=TCL_OK||id<=0||(g->item&&id==g->item->header.id))fail(ip,"Position batch needs a scientific Tk item ID");auto values=list(ip,row[1]);if(values.size()%2)fail(ip,"Positions need XY pairs");for(auto x:values)number(ip,x);}for(auto record:records){auto row=list(ip,record);auto values=list(ip,row[1]);std::vector<Tcl_Obj *> cmd{widget.p,coords.p,row[0]};cmd.insert(cmd.end(),values.begin(),values.end());call(ip,cmd);}Tcl_ResetResult(ip);return TCL_OK;}
  fail(ip,"Invalid grid presenter operation/arguments");
 }catch(const Error &){return TCL_ERROR;}catch(const std::bad_alloc &){Tcl_SetObjResult(ip,Tcl_NewStringObj("Grid presenter allocation failed",-1));return TCL_ERROR;}
 return TCL_ERROR;
}
int create(ClientData,Tcl_Interp *ip,int n,Tcl_Obj *const v[]){
 try {
  if(n!=2)fail(ip,"Usage: native grid_presenter canvas");Tk_Window main=Tk_MainWindow(ip);if(!main)fail(ip,"Native grid presenter requires Tk");auto win=Tk_NameToWindow(ip,Tcl_GetString(v[1]),main);if(!win)throw Error{};
  if(std::string(Tk_Class(win))!="Canvas")fail(ip,"Native grid presenter needs an existing Canvas");static bool registered=false;if(!registered){Tk_CreateItemType(&itemType);registered=true;}
  static uint64_t serial=0;auto g=new Grid(ip,win,Tcl_GetString(v[1]));g->name="::gx::native2d::gridPresenter"+std::to_string(++serial);g->command=Tcl_CreateObjCommand(ip,g->name.c_str(),objectCommand,g,objectDeleted);Tk_CreateEventHandler(win,StructureNotifyMask,ownerEvent,g);
  try {g->ensureItem();}catch(...){Tcl_DeleteCommandFromToken(ip,g->command);throw;}
  Tcl_SetObjResult(ip,Tcl_NewStringObj(g->name.c_str(),-1));return TCL_OK;
 }catch(const Error &){return TCL_ERROR;}catch(const std::bad_alloc &){Tcl_SetObjResult(ip,Tcl_NewStringObj("Grid presenter allocation failed",-1));return TCL_ERROR;}
}
}
extern "C" int gx2d_grid_presenter_v1_init(Tcl_Interp *ip){Tcl_CreateObjCommand(ip,"::gx::native2d::grid_presenter",create,nullptr,nullptr);return TCL_OK;}
extern "C" int gx2d_grid_presenter_v1_update(Tcl_Interp *ip,const gx2d_scene *scene,Tcl_Obj *handle,Tcl_Obj *data){
 try {Tcl_CmdInfo info;if(!Tcl_GetCommandInfo(ip,Tcl_GetString(handle),&info)||info.objProc!=objectCommand)fail(ip,"Native grid presenter owner is unavailable");update((Grid *)info.objClientData,scene,data);Tcl_ResetResult(ip);return TCL_OK;}catch(const Error &){return TCL_ERROR;}catch(const std::bad_alloc &){Tcl_SetObjResult(ip,Tcl_NewStringObj("Grid presenter allocation failed",-1));return TCL_ERROR;}
}

extern "C" int gx2d_grid_presenter_v1_controls(Tcl_Interp *ip,const gx2d_scene *scene,Tcl_Obj *handle,gx2d_id object,Tcl_Obj *selected,Tcl_Obj *color){
 try {
  Tcl_CmdInfo info;if(!Tcl_GetCommandInfo(ip,Tcl_GetString(handle),&info)||info.objProc!=objectCommand)fail(ip,"Native control presenter is unavailable");auto g=(Grid *)info.objClientData;g->ensureItem();
  std::set<size_t> chosen;for(auto value:list(ip,selected)){Tcl_WideInt n;if(Tcl_GetWideIntFromObj(ip,value,&n)!=TCL_OK||n<0)fail(ip,"Selected controls need nonnegative indices");chosen.insert((size_t)n);}
  size_t count=0;auto code=gx2d_sketch_controls(scene,object,nullptr,0,&count);if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));if(count>65536)fail(ip,"Native controls exceed presentation capacity");std::vector<gx2d_control> controls(count);code=gx2d_sketch_controls(scene,object,controls.data(),count,&count);if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));gx2d_view view;gx2d_view_get(scene,&view);
  auto coords=str("coords"),config=str("itemconfigure"),fillOption=str("-fill"),outlineOption=str("-outline"),erase=str("delete");
  std::string group="native_control_"+std::to_string(object);auto groupObj=str(group.c_str());
  for(auto &control:controls){gx2d_point p;code=gx2d_world_to_device(scene,control.point,&p);if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));std::vector<double> xy{std::max(p.x-5,view.left+1),std::max(p.y-5,view.top+1),std::min(p.x+5,view.width-view.right-1),std::min(p.y+5,view.height-view.bottom-1)};
   auto key=std::make_pair(object,control.reference.index);auto existing=g->controls.find(key);
   if(xy[0]>xy[2]||xy[1]>xy[3]){if(existing!=g->controls.end()){auto id=Obj(Tcl_NewIntObj(existing->second.id));g->canvasCall({erase.p,id.p});g->controls.erase(existing);}continue;}
   auto &item=g->controls[key];bool fresh=item.id==0;auto fill=str(chosen.count(control.reference.index)?"#ffbd3a":"white");
   if(fresh){auto create=str("create"),rect=str("rectangle"),tags=str("-tags"),widthOption=str("-width");Obj tagList(Tcl_NewListObj(0,nullptr));for(const char *t:{"primitive_handle","native_batch_item",group.c_str()})Tcl_ListObjAppendElement(ip,tagList.p,Tcl_NewStringObj(t,-1));auto width=Obj(Tcl_NewIntObj(2));std::vector<Obj> positions;for(double x:xy)positions.emplace_back(Tcl_NewDoubleObj(x));auto id=g->canvasCall({create.p,rect.p,positions[0].p,positions[1].p,positions[2].p,positions[3].p,fillOption.p,fill.p,outlineOption.p,color,widthOption.p,width.p,tags.p,tagList.p});if(Tcl_GetIntFromObj(ip,id.p,&item.id)!=TCL_OK)throw Error{};
   }else{
    Obj id(Tcl_NewIntObj(item.id));
    if(item.xy!=xy){std::vector<Obj> positions;for(double x:xy)positions.emplace_back(Tcl_NewDoubleObj(x));g->canvasCall({coords.p,id.p,positions[0].p,positions[1].p,positions[2].p,positions[3].p});++g->controlUpdates;}
    if(item.fill!=Tcl_GetString(fill.p)||item.outline!=Tcl_GetString(color))g->canvasCall({config.p,id.p,fillOption.p,fill.p,outlineOption.p,color});
   }
   item.xy=xy;item.fill=Tcl_GetString(fill.p);item.outline=Tcl_GetString(color);item.frame=g->frame;
  }
  auto raise=str("raise");g->canvasCall({raise.p,groupObj.p});Tcl_ResetResult(ip);return TCL_OK;
 }catch(const Error &){return TCL_ERROR;}catch(const std::bad_alloc &){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native control batch allocation failed",-1));return TCL_ERROR;}
}
