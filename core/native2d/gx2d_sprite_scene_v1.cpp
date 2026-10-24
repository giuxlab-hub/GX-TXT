/* SPDX-License-Identifier: GPL-3.0-or-later
 * Retained presentation sprites. Scientific geometry, snapping and transactions
 * remain in gx2d.c. The public Tk Canvas custom item API owns composition with
 * the existing grid and GUI overlays; Cairo paints into Tk's current drawable.
 */
#include "gx2d_sprite_scene_v1.h"
#include <tk.h>
#include <cairo.h>
#include <cairo-xlib.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <string>
#include <vector>
namespace {
struct Error {};
struct Obj {
 Tcl_Obj *p; explicit Obj(Tcl_Obj *v):p(v){Tcl_IncrRefCount(p);}
 ~Obj(){Tcl_DecrRefCount(p);} Obj(const Obj &)=delete;
};
void fail(Tcl_Interp *ip,const char *msg){Tcl_SetObjResult(ip,Tcl_NewStringObj(msg,-1));throw Error{};}
Tcl_Obj *field(Tcl_Interp *ip,Tcl_Obj *dict,const char *key,bool required=false){
 Obj k(Tcl_NewStringObj(key,-1));Tcl_Obj *v=nullptr;
 if(Tcl_DictObjGet(ip,dict,k.p,&v)!=TCL_OK)throw Error{};
 if(required&&!v)fail(ip,"Missing required sprite field");return v;
}
std::vector<Tcl_Obj *> values(Tcl_Interp *ip,Tcl_Obj *o){int n;Tcl_Obj **p;if(Tcl_ListObjGetElements(ip,o,&n,&p)!=TCL_OK)throw Error{};return {p,p+n};}
double num(Tcl_Interp *ip,Tcl_Obj *o){double x;if(Tcl_GetDoubleFromObj(ip,o,&x)!=TCL_OK||!std::isfinite(x)||std::abs(x)>1e12)fail(ip,"Sprite coordinates must be finite and bounded by1e12");return x;}
void put(Tcl_Obj *d,const char *k,Tcl_Obj *v){Obj key(Tcl_NewStringObj(k,-1));Tcl_DictObjPut(nullptr,d,key.p,v);}
struct Point {double x=0,y=0;};
Point point(Tcl_Interp *ip,Tcl_Obj *o){auto a=values(ip,o);if(a.size()!=2)fail(ip,"Sprite point needs two coordinates");return {num(ip,a[0]),num(ip,a[1])};}
Tcl_Obj *pair(Point p){Tcl_Obj *v[]={Tcl_NewDoubleObj(p.x),Tcl_NewDoubleObj(p.y)};return Tcl_NewListObj(2,v);}
struct Bounds {
 double x0=1e30,y0=1e30,x1=-1e30,y1=-1e30;
 void add(Point p){x0=std::min(x0,p.x);y0=std::min(y0,p.y);x1=std::max(x1,p.x);y1=std::max(y1,p.y);}
 bool valid()const{return x0<=x1&&y0<=y1;}
 bool touches(const Bounds &b)const{return valid()&&b.valid()&&x1>=b.x0&&y1>=b.y0&&x0<=b.x1&&y0<=b.y1;}
};
struct Color {double r=0,g=0,b=0,a=1;bool enabled=true;};
struct Primitive {std::string kind="line";std::vector<Point> points;Color stroke,fill{0,0,0,0,false};double width=1;std::vector<double> dash;};
struct Anchor {Point position,direction{1,0};};
struct Sprite {
 std::string id,signature;std::vector<Primitive> geometry;std::map<std::string,Anchor> anchors;
 Point position,pivot,scale{1,1};double angle=0,z=0;bool visible=true;uint64_t order=0,frame=0;
 Bounds bounds;
 Point transform(Point p)const {double a=angle*3.14159265358979323846/180,c=cos(a),s=sin(a);p.x=(p.x-pivot.x)*scale.x;p.y=(p.y-pivot.y)*scale.y;return {position.x+pivot.x+c*p.x-s*p.y,position.y+pivot.y+s*p.x+c*p.y};}
 void measure(){
  bounds=Bounds{};if(!visible)return;
  double pad=0;
  for(auto &g:geometry){
   pad=std::max(pad,g.width/2+1);
   if(g.kind=="ellipse"){
    Point a=g.points[0],b=g.points[1],mid{(a.x+b.x)/2,(a.y+b.y)/2};Point c=transform(mid),u=transform({b.x,mid.y}),v=transform({mid.x,b.y});
    double rx=hypot(u.x-c.x,v.x-c.x),ry=hypot(u.y-c.y,v.y-c.y);bounds.add({c.x-rx,c.y-ry});bounds.add({c.x+rx,c.y+ry});
   }else if(g.kind=="rectangle"){
    auto a=g.points[0],b=g.points[1];for(Point p:{a,Point{a.x,b.y},b,Point{b.x,a.y}})bounds.add(transform(p));
   }else for(auto p:g.points)bounds.add(transform(p));
  }
  if(bounds.valid()){bounds.x0-=pad;bounds.y0-=pad;bounds.x1+=pad;bounds.y1+=pad;}
 }
};
struct Scene;
struct Item {Tk_Item header;Scene *owner;};
struct Scene {
 Tcl_Interp *ip;Tk_Window win;Tk_Canvas canvas=nullptr;Item *item=nullptr;Tcl_Command command=nullptr;
 std::map<std::string,Color> colors;
 std::string name,path;std::map<std::string,Sprite> sprites;std::vector<Sprite *> sorted;bool orderDirty=true;
 uint64_t serial=0,frame=0,updates=0,changes=0,paints=0,painted=0,rasterUpdates=0;Bounds clip,dirty;bool clipped=false;
 cairo_surface_t *raster=nullptr;int rasterWidth=0,rasterHeight=0;
 Scene(Tcl_Interp *i,Tk_Window w,std::string p):ip(i),win(w),path(std::move(p)){}
 void ensure();void redraw(Bounds b){if(b.valid()){dirty.add({b.x0,b.y0});dirty.add({b.x1,b.y1});}if(item&&b.valid())Tk_CanvasEventuallyRedraw(canvas,(int)floor(std::clamp(b.x0,-1e7,1e7)),(int)floor(std::clamp(b.y0,-1e7,1e7)),(int)ceil(std::clamp(b.x1,-1e7,1e7)),(int)ceil(std::clamp(b.y1,-1e7,1e7)));}
 void all(){if(item)redraw({(double)item->header.x1,(double)item->header.y1,(double)item->header.x2,(double)item->header.y2});}
 void sort(){if(!orderDirty)return;sorted.clear();for(auto &p:sprites)sorted.push_back(&p.second);std::sort(sorted.begin(),sorted.end(),[](auto a,auto b){return a->z==b->z?a->order<b->order:a->z<b->z;});orderDirty=false;}
 ~Scene();
};
int command(ClientData,Tcl_Interp *,int,Tcl_Obj *const []);
Tk_CustomOption tags={Tk_CanvasTagsParseProc,Tk_CanvasTagsPrintProc,nullptr};
Tk_ConfigSpec specs[]={{TK_CONFIG_CUSTOM,"-tags",nullptr,nullptr,nullptr,0,TK_CONFIG_NULL_OK,&tags},{TK_CONFIG_END,nullptr,nullptr,nullptr,nullptr,0,0,nullptr}};
int configure(Tcl_Interp *ip,Tk_Canvas canvas,Tk_Item *base,int n,Tcl_Obj *const v[],int){
 if(n%2){Tcl_SetObjResult(ip,Tcl_NewStringObj("Sprite item supports -tags only",-1));return TCL_ERROR;}for(int i=0;i<n;i+=2){if(std::string(Tcl_GetString(v[i]))!="-tags")return TCL_ERROR;if(Tk_CanvasTagsParseProc(nullptr,ip,Tk_CanvasTkwin(canvas),Tcl_GetString(v[i+1]),(char *)base,0)!=TCL_OK)return TCL_ERROR;}return TCL_OK;
}
int createItem(Tcl_Interp *ip,Tk_Canvas canvas,Tk_Item *base,int n,Tcl_Obj *const v[]){
 auto item=(Item *)base;item->owner=nullptr;Tcl_CmdInfo info;
 if(n!=1||!Tcl_GetCommandInfo(ip,Tcl_GetString(v[0]),&info)||info.objProc!=command){Tcl_SetObjResult(ip,Tcl_NewStringObj("Sprite item needs its native scene owner",-1));return TCL_ERROR;}
 auto s=(Scene *)info.objClientData;if(s->item)return TCL_ERROR;
 s->canvas=canvas;s->item=item;item->owner=s;base->state=TK_STATE_DISABLED;
 base->x1=base->y1=0;base->x2=std::max(1,Tk_Width(s->win));base->y2=std::max(1,Tk_Height(s->win));
 return Tk_CanvasTagsParseProc(nullptr,ip,s->win,"native_sprite_scene",(char *)base,0);
}
int coordinates(Tcl_Interp *ip,Tk_Canvas,Tk_Item *b,int n,Tcl_Obj *const []){if(n){Tcl_SetObjResult(ip,Tcl_NewStringObj("Use the sprite scene API for positioning",-1));return TCL_ERROR;}Tcl_Obj *a[]={Tcl_NewIntObj(b->x1),Tcl_NewIntObj(b->y1),Tcl_NewIntObj(b->x2),Tcl_NewIntObj(b->y2)};Tcl_SetObjResult(ip,Tcl_NewListObj(4,a));return TCL_OK;}
void deleteItem(Tk_Canvas,Tk_Item *b,Display *){auto item=(Item *)b;if(item->owner)item->owner->item=nullptr;item->owner=nullptr;}
void source(cairo_t *cr,Color c){cairo_set_source_rgba(cr,c.r,c.g,c.b,c.a);}
void primitivePath(cairo_t *cr,const Sprite &s,const Primitive &g){
 cairo_new_path(cr);
 auto line=[&](Point p,bool first=false){p=s.transform(p);if(first)cairo_move_to(cr,p.x,p.y);else cairo_line_to(cr,p.x,p.y);};
 if(g.kind=="rectangle"){auto a=g.points[0],b=g.points[1];line(a,true);line({b.x,a.y});line(b);line({a.x,b.y});cairo_close_path(cr);
 }else if(g.kind=="ellipse"){
  // Construct an exact transformed ellipse, then restore the CTM so stroke
  // widths remain device-pixel presentation widths like the previous Tk path.
  auto a=g.points[0],b=g.points[1];cairo_save(cr);cairo_translate(cr,s.position.x+s.pivot.x,s.position.y+s.pivot.y);cairo_rotate(cr,s.angle*3.14159265358979323846/180);cairo_scale(cr,s.scale.x,s.scale.y);cairo_translate(cr,-s.pivot.x+(a.x+b.x)/2,-s.pivot.y+(a.y+b.y)/2);cairo_scale(cr,std::abs(b.x-a.x)/2,std::abs(b.y-a.y)/2);cairo_arc(cr,0,0,1,0,2*3.14159265358979323846);cairo_restore(cr);
 }else {bool first=true;for(auto p:g.points){line(p,first);first=false;}if(g.kind=="polygon")cairo_close_path(cr);}
}
void paintPrimitive(cairo_t *cr,const Sprite &s,const Primitive &g){
 primitivePath(cr,s,g);
 if(g.fill.enabled){source(cr,g.fill);cairo_fill_preserve(cr);}
 if(g.stroke.enabled&&g.width>0){source(cr,g.stroke);cairo_set_line_width(cr,g.width);cairo_set_line_cap(cr,CAIRO_LINE_CAP_BUTT);cairo_set_line_join(cr,CAIRO_LINE_JOIN_ROUND);cairo_set_dash(cr,g.dash.data(),(int)g.dash.size(),0);cairo_stroke(cr);}else cairo_new_path(cr);
}
void displayItem(Tk_Canvas canvas,Tk_Item *base,Display *display,Drawable drawable,int x,int y,int width,int height){
 auto s=((Item *)base)->owner;if(!s||!s->win)return;
 int cw=std::max(1,Tk_Width(s->win)),ch=std::max(1,Tk_Height(s->win));
 // Raster bounds are finite and display-owned; failed allocations never enter
 // a Tcl callback from Tk's display procedure.
 if(cw>16384||ch>16384||(int64_t)cw*ch>32000000)return;
 if(!s->raster||cw!=s->rasterWidth||ch!=s->rasterHeight){
  if(s->raster)cairo_surface_destroy(s->raster);
  s->raster=cairo_image_surface_create(CAIRO_FORMAT_ARGB32,cw,ch);s->rasterWidth=cw;s->rasterHeight=ch;s->dirty={0,0,(double)cw,(double)ch};
 }
 if(cairo_surface_status(s->raster)!=CAIRO_STATUS_SUCCESS)return;
 if(s->dirty.valid()){
  cairo_t *cr=cairo_create(s->raster);
  Bounds dirty{std::max(0.,floor(s->dirty.x0)-1),std::max(0.,floor(s->dirty.y0)-1),std::min((double)cw,ceil(s->dirty.x1)+1),std::min((double)ch,ceil(s->dirty.y1)+1)};
  cairo_rectangle(cr,dirty.x0,dirty.y0,std::max(0.,dirty.x1-dirty.x0),std::max(0.,dirty.y1-dirty.y0));cairo_clip(cr);
  cairo_set_operator(cr,CAIRO_OPERATOR_CLEAR);cairo_paint(cr);cairo_set_operator(cr,CAIRO_OPERATOR_OVER);
  if(s->clipped){cairo_rectangle(cr,s->clip.x0,s->clip.y0,s->clip.x1-s->clip.x0,s->clip.y1-s->clip.y0);cairo_clip(cr);}
  s->sort();for(auto p:s->sorted){if(!p->visible||!p->bounds.touches(dirty)||(s->clipped&&!p->bounds.touches(s->clip)))continue;for(auto &g:p->geometry)paintPrimitive(cr,*p,g);++s->painted;}
  cairo_destroy(cr);cairo_surface_flush(s->raster);s->dirty=Bounds{};++s->rasterUpdates;
 }
 short dx,dy;Tk_CanvasDrawableCoords(canvas,0,0,&dx,&dy);
 cairo_surface_t *surface=cairo_xlib_surface_create(display,drawable,Tk_Visual(s->win),cw,ch);
 cairo_t *cr=cairo_create(surface);cairo_translate(cr,dx,dy);cairo_rectangle(cr,x,y,width,height);cairo_clip(cr);cairo_set_source_surface(cr,s->raster,0,0);cairo_paint(cr);++s->paints;
 cairo_destroy(cr);cairo_surface_flush(surface);cairo_surface_destroy(surface);
}
double distanceItem(Tk_Canvas,Tk_Item *,double *){return 1e36;}
int areaItem(Tk_Canvas,Tk_Item *,double *){return -1;}
void scaleItem(Tk_Canvas,Tk_Item *,double,double,double,double){}
void translateItem(Tk_Canvas,Tk_Item *,double,double){}
Tk_ItemType itemType={"gx2dsprites",sizeof(Item),createItem,specs,configure,coordinates,deleteItem,displayItem,TK_CONFIG_OBJS,distanceItem,areaItem,nullptr,scaleItem,translateItem,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,0,nullptr,nullptr};
void eval(Scene *s,std::vector<Tcl_Obj *> a){if(Tcl_EvalObjv(s->ip,(int)a.size(),a.data(),TCL_EVAL_GLOBAL)!=TCL_OK)throw Error{};}
void Scene::ensure(){
 if(item)return;Obj widget(Tcl_NewStringObj(path.c_str(),-1)),create(Tcl_NewStringObj("create",-1)),kind(Tcl_NewStringObj("gx2dsprites",-1)),handle(Tcl_NewStringObj(name.c_str(),-1));eval(this,{widget.p,create.p,kind.p,handle.p});all();
}
void ownerEvent(ClientData value,XEvent *e){auto s=(Scene *)value;if(e->type==DestroyNotify){s->win=nullptr;if(s->command)Tcl_DeleteCommandFromToken(s->ip,s->command);}else if(e->type==ConfigureNotify&&s->item){s->item->header.x2=std::max(1,e->xconfigure.width);s->item->header.y2=std::max(1,e->xconfigure.height);s->all();}}
Scene::~Scene(){
 if(raster)cairo_surface_destroy(raster);
 int id=0;if(item){id=item->header.id;item->owner=nullptr;item=nullptr;}
 if(win){Tk_DeleteEventHandler(win,StructureNotifyMask,ownerEvent,this);if(id&&!Tcl_InterpDeleted(ip)){Obj w(Tcl_NewStringObj(path.c_str(),-1)),d(Tcl_NewStringObj("delete",-1)),i(Tcl_NewIntObj(id));try{eval(this,{w.p,d.p,i.p});}catch(...){Tcl_ResetResult(ip);}}}
}
void deleted(ClientData value){auto s=(Scene *)value;s->command=nullptr;delete s;}
Color color(Scene *s,Tcl_Obj *value){
 std::string hex=Tcl_GetString(value);if(hex.empty())return {0,0,0,0,false};
 auto found=s->colors.find(hex);if(found!=s->colors.end())return found->second;
 auto c=Tk_GetColor(s->ip,s->win,Tk_GetUid(hex.c_str()));if(!c)throw Error{};
 Color result{c->red/65535.,c->green/65535.,c->blue/65535.,1,true};Tk_FreeColor(c);if(s->colors.size()>=256)s->colors.clear();s->colors.emplace(hex,result);return result;
}
Sprite parse(Scene *s,Tcl_Obj *spec,Sprite prior){
 auto ip=s->ip;int size;if(Tcl_DictObjSize(ip,spec,&size)!=TCL_OK)throw Error{};
 Tcl_DictSearch search;Tcl_Obj *k,*v;int done;
 if(Tcl_DictObjFirst(ip,spec,&search,&k,&v,&done)!=TCL_OK)throw Error{};
 bool invalid=false;while(!done){std::string key=Tcl_GetString(k);if(key!="id"&&key!="geometry"&&key!="anchors"&&key!="position"&&key!="pivot"&&key!="scale"&&key!="angle"&&key!="z"&&key!="visible")invalid=true;Tcl_DictObjNext(&search,&k,&v,&done);}Tcl_DictObjDone(&search);if(invalid)fail(ip,"Unknown sprite field");
 prior.id=Tcl_GetString(field(ip,spec,"id",true));if(prior.id.empty()||prior.id.size()>256)fail(ip,"Sprite identity needs1..256bytes");
 for(auto key:{"position","pivot","scale"})if(auto o=field(ip,spec,key)){auto p=point(ip,o);if(std::string(key)=="position")prior.position=p;else if(std::string(key)=="pivot")prior.pivot=p;else {if(std::abs(p.x)<1e-12||std::abs(p.y)<1e-12)fail(ip,"Sprite scale must be nonsingular");prior.scale=p;}}
 if(auto o=field(ip,spec,"angle"))prior.angle=num(ip,o);
 if(auto o=field(ip,spec,"z"))prior.z=num(ip,o);
 if(auto o=field(ip,spec,"visible")){int b;if(Tcl_GetBooleanFromObj(ip,o,&b)!=TCL_OK)throw Error{};prior.visible=b;}
 if(auto o=field(ip,spec,"geometry")){
  prior.geometry.clear();auto primitives=values(ip,o);if(primitives.size()>65536)fail(ip,"Too many sprite primitives");size_t count=0;
  for(auto p:primitives){Primitive g;g.kind=Tcl_GetString(field(ip,p,"kind",true));if(g.kind!="line"&&g.kind!="polygon"&&g.kind!="rectangle"&&g.kind!="ellipse")fail(ip,"Unknown sprite primitive");
   auto points=values(ip,field(ip,p,"points",true));if(points.size()<2||(g.kind=="polygon"&&points.size()<3)||((g.kind=="ellipse"||g.kind=="rectangle")&&points.size()!=2))fail(ip,"Invalid sprite primitive coordinates");count+=points.size();if(count>262144)fail(ip,"Sprite geometry capacity exceeded");
   for(auto xy:points)g.points.push_back(point(ip,xy));if((g.kind=="ellipse")&&(g.points[0].x==g.points[1].x||g.points[0].y==g.points[1].y))fail(ip,"Ellipse needs nonzero dimensions");
   if(auto f=field(ip,p,"stroke"))g.stroke=color(s,f);if(auto f=field(ip,p,"fill"))g.fill=color(s,f);if(auto f=field(ip,p,"width")){g.width=num(ip,f);if(g.width<0||g.width>256)fail(ip,"Sprite width must be0..256pixels");}
   if(auto f=field(ip,p,"dash")){auto d=values(ip,f);if(d.size()>16)fail(ip,"Sprite dash capacity exceeded");for(auto n:d){double value=num(ip,n);if(value<=0)fail(ip,"Sprite dashes must be positive");g.dash.push_back(value);}}
   prior.geometry.push_back(std::move(g));
  }
 }
 if(auto o=field(ip,spec,"anchors")){
  prior.anchors.clear();int n;if(Tcl_DictObjSize(ip,o,&n)!=TCL_OK)throw Error{};if(n>1024)fail(ip,"Sprite anchor capacity exceeded");
  Tcl_DictSearch it;if(Tcl_DictObjFirst(ip,o,&it,&k,&v,&done)!=TCL_OK)throw Error{};
  try{while(!done){std::string name=Tcl_GetString(k);if(name.empty()||name.size()>256)fail(ip,"Invalid anchor name");Anchor a;a.position=point(ip,field(ip,v,"position",true));if(auto d=field(ip,v,"direction"))a.direction=point(ip,d);if(hypot(a.direction.x,a.direction.y)<1e-12)fail(ip,"Anchor direction cannot be zero");prior.anchors.emplace(name,a);Tcl_DictObjNext(&it,&k,&v,&done);}}catch(...){Tcl_DictObjDone(&it);throw;}Tcl_DictObjDone(&it);
 }
 prior.measure();return prior;
}
Tcl_Obj *describeSprite(const Sprite &s){
 auto o=Tcl_NewDictObj();put(o,"id",Tcl_NewStringObj(s.id.c_str(),-1));put(o,"position",pair(s.position));put(o,"pivot",pair(s.pivot));put(o,"scale",pair(s.scale));put(o,"angle",Tcl_NewDoubleObj(s.angle));put(o,"z",Tcl_NewDoubleObj(s.z));put(o,"visible",Tcl_NewBooleanObj(s.visible));put(o,"primitives",Tcl_NewWideIntObj(s.geometry.size()));
 Tcl_Obj *a[]={Tcl_NewDoubleObj(s.bounds.x0),Tcl_NewDoubleObj(s.bounds.y0),Tcl_NewDoubleObj(s.bounds.x1),Tcl_NewDoubleObj(s.bounds.y1)};put(o,"bounds",s.bounds.valid()?Tcl_NewListObj(4,a):Tcl_NewListObj(0,nullptr));return o;
}
bool hit(const Sprite &s,Point p,double tolerance){
 Bounds box{p.x-tolerance,p.y-tolerance,p.x+tolerance,p.y+tolerance};if(!s.visible||!s.bounds.touches(box))return false;
 cairo_surface_t *surface=cairo_recording_surface_create(CAIRO_CONTENT_COLOR_ALPHA,nullptr);cairo_t *cr=cairo_create(surface);bool found=false;
 for(auto &g:s.geometry){primitivePath(cr,s,g);if(g.fill.enabled&&cairo_in_fill(cr,p.x,p.y)){found=true;break;}
  cairo_set_line_width(cr,g.width+2*tolerance);cairo_set_line_join(cr,CAIRO_LINE_JOIN_ROUND);cairo_set_line_cap(cr,CAIRO_LINE_CAP_BUTT);
  if(g.stroke.enabled&&cairo_in_stroke(cr,p.x,p.y)){found=true;break;}
 }
 cairo_destroy(cr);cairo_surface_destroy(surface);return found;
}
int command(ClientData value,Tcl_Interp *ip,int n,Tcl_Obj *const a[]){
 auto s=(Scene *)value;
 try{
  if(n<2)fail(ip,"Sprite scene operation required");std::string op=Tcl_GetString(a[1]);
  if(op=="destroy"&&n==2){Tcl_DeleteCommandFromToken(ip,s->command);return TCL_OK;}
  s->ensure();
  if(op=="batch"&&n==3){
   auto rows=values(ip,a[2]);if(rows.size()>65536)fail(ip,"Sprite batch capacity exceeded");
   std::map<std::string,Sprite> parsed;uint64_t serial=s->serial;size_t total=0;
   for(auto row:rows){std::string id=Tcl_GetString(field(ip,row,"id",true));if(parsed.count(id))fail(ip,"Duplicate sprite identity in batch");auto old=s->sprites.find(id);Sprite prior;if(old!=s->sprites.end())prior=old->second;else prior.order=++serial;
    std::string signature=Tcl_GetString(row);if(prior.signature!=signature){prior=parse(s,row,std::move(prior));prior.signature=std::move(signature);}prior.frame=s->frame;for(auto &g:prior.geometry)total+=g.points.size();if(total>2000000)fail(ip,"Sprite batch exceeds2million points");parsed.emplace(id,std::move(prior));
   }
   size_t retainedPoints=total,retainedCount=parsed.size();
   for(auto &old:s->sprites)if(!parsed.count(old.first)){++retainedCount;for(auto &g:old.second.geometry)retainedPoints+=g.points.size();}
   if(retainedCount>65536||retainedPoints>2000000)fail(ip,"Sprite scene capacity exceeded");
   for(auto &p:parsed){auto old=s->sprites.find(p.first);bool changed=old==s->sprites.end()||old->second.signature!=p.second.signature;
    if(changed){if(old!=s->sprites.end())s->redraw(old->second.bounds);s->redraw(p.second.bounds);s->sprites[p.first]=std::move(p.second);s->orderDirty=true;++s->changes;}else old->second.frame=s->frame;
   }s->serial=serial;++s->updates;Tcl_ResetResult(ip);return TCL_OK;
  }
  if(op=="begin"&&(n==2||n==3)){
   if(n==3){auto b=values(ip,a[2]);if(b.size()!=4)fail(ip,"Sprite clip needs4coordinates");Bounds clip{num(ip,b[0]),num(ip,b[1]),num(ip,b[2]),num(ip,b[3])};if(!clip.valid())fail(ip,"Invalid sprite clip");if(!s->clipped||clip.x0!=s->clip.x0||clip.y0!=s->clip.y0||clip.x1!=s->clip.x1||clip.y1!=s->clip.y1){s->clip=clip;s->clipped=true;s->all();}}
   ++s->frame;s->item->header.x2=std::max(1,Tk_Width(s->win));s->item->header.y2=std::max(1,Tk_Height(s->win));return TCL_OK;
  }
  if(op=="end"&&n==2){for(auto i=s->sprites.begin();i!=s->sprites.end();){if(i->second.frame!=s->frame){s->redraw(i->second.bounds);i=s->sprites.erase(i);s->orderDirty=true;}else ++i;}return TCL_OK;}
  if(op=="remove"&&n==3){auto ids=values(ip,a[2]);for(auto id:ids){auto i=s->sprites.find(Tcl_GetString(id));if(i!=s->sprites.end()){s->redraw(i->second.bounds);s->sprites.erase(i);s->orderDirty=true;}}return TCL_OK;}
  if(op=="describe"&&(n==2||n==3)){
   if(n==3){auto i=s->sprites.find(Tcl_GetString(a[2]));if(i==s->sprites.end())fail(ip,"Unknown sprite");Tcl_SetObjResult(ip,describeSprite(i->second));return TCL_OK;}
   Obj out(Tcl_NewDictObj());put(out.p,"api_id",Tcl_NewStringObj("NATIVE2D_SPRITE_SCENE_API_v1",-1));put(out.p,"item",Tcl_NewIntObj(s->item->header.id));put(out.p,"sprites",Tcl_NewWideIntObj(s->sprites.size()));put(out.p,"updates",Tcl_NewWideIntObj(s->updates));put(out.p,"changes",Tcl_NewWideIntObj(s->changes));put(out.p,"paints",Tcl_NewWideIntObj(s->paints));put(out.p,"painted_sprites",Tcl_NewWideIntObj(s->painted));put(out.p,"raster_updates",Tcl_NewWideIntObj(s->rasterUpdates));Tcl_SetObjResult(ip,out.p);return TCL_OK;
  }
  if(op=="anchor"&&n==4){auto i=s->sprites.find(Tcl_GetString(a[2]));if(i==s->sprites.end())fail(ip,"Unknown sprite");auto &p=i->second;auto f=p.anchors.find(Tcl_GetString(a[3]));if(f==p.anchors.end())fail(ip,"Unknown sprite anchor");auto v=p.transform(f->second.position);double angle=p.angle*3.14159265358979323846/180,dx=f->second.direction.x*p.scale.x,dy=f->second.direction.y*p.scale.y;Point d{cos(angle)*dx-sin(angle)*dy,sin(angle)*dx+cos(angle)*dy};double length=hypot(d.x,d.y);Obj out(Tcl_NewDictObj());put(out.p,"position",pair(v));put(out.p,"direction",pair({d.x/length,d.y/length}));Tcl_SetObjResult(ip,out.p);return TCL_OK;}
  if(op=="hit"&&(n==3||n==4)){auto p=point(ip,a[2]);double tolerance=n==4?num(ip,a[3]):0;if(tolerance<0||tolerance>256)fail(ip,"Hit tolerance must be0..256");Obj out(Tcl_NewListObj(0,nullptr));if(!s->clipped||(p.x>=s->clip.x0&&p.x<=s->clip.x1&&p.y>=s->clip.y0&&p.y<=s->clip.y1)){s->sort();for(auto i=s->sorted.rbegin();i!=s->sorted.rend();++i)if(hit(**i,p,tolerance))Tcl_ListObjAppendElement(ip,out.p,Tcl_NewStringObj((*i)->id.c_str(),-1));}Tcl_SetObjResult(ip,out.p);return TCL_OK;}
  fail(ip,"Invalid sprite scene operation or arguments");
 }catch(const Error &){return TCL_ERROR;}catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
 return TCL_ERROR;
}
int createScene(ClientData,Tcl_Interp *ip,int n,Tcl_Obj *const a[]){
 try{if(n!=2)fail(ip,"Usage: native sprite_scene canvas");auto main=Tk_MainWindow(ip);if(!main)fail(ip,"Sprite scene requires Tk");auto win=Tk_NameToWindow(ip,Tcl_GetString(a[1]),main);if(!win)throw Error{};if(std::string(Tk_Class(win))!="Canvas")fail(ip,"Sprite scene requires an existing Canvas");static bool registered=false;if(!registered){Tk_CreateItemType(&itemType);registered=true;}static uint64_t serial=0;
  auto s=new Scene(ip,win,Tcl_GetString(a[1]));s->name="::gx::native2d::spriteScene"+std::to_string(++serial);s->command=Tcl_CreateObjCommand(ip,s->name.c_str(),command,s,deleted);Tk_CreateEventHandler(win,StructureNotifyMask,ownerEvent,s);try{s->ensure();}catch(...){Tcl_DeleteCommandFromToken(ip,s->command);throw;}Tcl_SetObjResult(ip,Tcl_NewStringObj(s->name.c_str(),-1));return TCL_OK;
 }catch(const Error &){return TCL_ERROR;}catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
}
}
extern "C" int gx2d_sprite_scene_v1_init(Tcl_Interp *ip){Tcl_CreateObjCommand(ip,"::gx::native2d::sprite_scene",createScene,nullptr,nullptr);return TCL_OK;}

extern "C" int gx2d_sprite_scene_v1_controls(Tcl_Interp *ip,const gx2d_scene *scene,gx2d_id object,Tcl_Obj *selected,Tcl_Obj *color){
 try{
  auto indices=values(ip,selected);std::vector<size_t> chosen;for(auto o:indices){Tcl_WideInt n;if(Tcl_GetWideIntFromObj(ip,o,&n)!=TCL_OK||n<0)fail(ip,"Invalid selected control index");chosen.push_back((size_t)n);}
  size_t count=0;auto status=gx2d_sketch_controls(scene,object,nullptr,0,&count);if(status!=GX2D_OK)fail(ip,gx2d_status_text(status));if(count>65536)fail(ip,"Control capacity exceeded");
  std::vector<gx2d_control> controls(count);status=gx2d_sketch_controls(scene,object,controls.data(),count,&count);if(status!=GX2D_OK)fail(ip,gx2d_status_text(status));Obj out(Tcl_NewListObj(0,nullptr));
  for(auto &control:controls){gx2d_point p;status=gx2d_world_to_device(scene,control.point,&p);if(status!=GX2D_OK)fail(ip,gx2d_status_text(status));auto record=Tcl_NewDictObj();put(record,"kind",Tcl_NewStringObj("rectangle",-1));Tcl_Obj *xy[]={pair({p.x-5,p.y-5}),pair({p.x+5,p.y+5})};put(record,"points",Tcl_NewListObj(2,xy));put(record,"stroke",color);put(record,"fill",Tcl_NewStringObj(std::find(chosen.begin(),chosen.end(),control.reference.index)!=chosen.end()?"#ffbd3a":"white",-1));put(record,"width",Tcl_NewIntObj(2));Tcl_ListObjAppendElement(ip,out.p,record);}
  Tcl_SetObjResult(ip,out.p);return TCL_OK;
 }catch(const Error &){return TCL_ERROR;}catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
}
