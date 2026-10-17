/* Native2D device presentation host. The grid and Plot projection consume one
 * clipped native painter and one Tk lifetime, never per-cell Tk resources. */
#include "gx2d_surface.h"
#include <tk.h>
#include <cairo.h>
#include <cairo-xlib.h>
#include <cairo-pdf.h>
#include <cairo-svg.h>
#include <X11/keysym.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace {
Tcl_Obj *str(const char *s) { return Tcl_NewStringObj(s,-1); }
Tcl_Obj *get(Tcl_Interp *ip,Tcl_Obj *d,const char *k) { Tcl_Obj *v=nullptr; Tcl_DictObjGet(ip,d,str(k),&v);return v; }
void put(Tcl_Obj *d,const char *k,Tcl_Obj *v) { Tcl_DictObjPut(nullptr,d,str(k),v); }
int error(Tcl_Interp *ip,const char *s) {Tcl_SetObjResult(ip,str(s));return TCL_ERROR;}
double number(Tcl_Interp *ip,Tcl_Obj *d,const char *key,double fallback) { auto v=get(ip,d,key);double x;return v&&Tcl_GetDoubleFromObj(ip,v,&x)==TCL_OK?x:fallback; }
std::string text(Tcl_Interp *ip,Tcl_Obj *d,const char *key,const char *fallback="") {auto v=get(ip,d,key);if(!v)return fallback;Tcl_DString bytes;Tcl_DStringInit(&bytes);Tcl_Encoding utf=Tcl_GetEncoding(ip,"utf-8");int length;const char *value=Tcl_GetStringFromObj(v,&length);Tcl_UtfToExternalDString(utf,value,length,&bytes);std::string result(Tcl_DStringValue(&bytes),Tcl_DStringLength(&bytes));Tcl_DStringFree(&bytes);Tcl_FreeEncoding(utf);return result;}
struct Cell {std::string value,kind;};
struct Host {
 Tcl_Interp *ip;Tk_Window win;Tcl_Command command=nullptr;bool grid=false,pending=false,drawing=false,dead=false,dirtyDuringDraw=false;
 uint64_t generation=1,revision=0,draws=0,fetches=0,coalesced=0;
 int rows=1000000,columns=702,rh=25,cw=110,head=27,gutter=56,fontSize=13,previousWidth=0,previousHeight=0;
 int64_t sx=0,sy=0;int ar=1,ac=1,br=1,bc=1;const char *phase="programmatic";bool reference=false;int refR1=1,refR2=1,refC1=1,refC2=1;bool dragging=false,filling=false;int resizing=0,resizeStartX=0,resizeStartWidth=0;
 Tcl_Obj *fetch=nullptr,*notify=nullptr,*xscroll=nullptr,*yscroll=nullptr,*primitives=nullptr;
 std::map<std::pair<int,int>,Cell> cells;
 std::map<int,int> columnWidths;std::map<int,std::string> columnLabels;
 std::vector<int> hiddenRows;
 int columnWidth(int c)const{auto it=columnWidths.find(c);return it==columnWidths.end()?cw:it->second;}
 int64_t columnLeft(int c)const{int64_t x=(int64_t)(c-1)*cw;for(auto p:columnWidths){if(p.first>=c)break;x+=p.second-cw;}return x;}
 int64_t totalWidth()const{return columnLeft(columns+1);}
 int columnAt(int64_t x)const{int lo=1,hi=columns;while(lo<hi){int mid=(lo+hi+1)/2;if(columnLeft(mid)<=x)lo=mid;else hi=mid-1;}return lo;}
 int visibleRows()const{return rows-(int)hiddenRows.size();}
 int rowIndex(int r)const{return r-1-(int)(std::lower_bound(hiddenRows.begin(),hiddenRows.end(),r)-hiddenRows.begin());}
 int64_t rowTop(int r)const{return (int64_t)rowIndex(r)*rh;}
 int rowAt(int ordinal)const{int lo=1,hi=rows;ordinal=std::max(0,std::min(visibleRows()-1,ordinal));while(lo<hi){int mid=(lo+hi)/2;int count=mid-(int)(std::upper_bound(hiddenRows.begin(),hiddenRows.end(),mid)-hiddenRows.begin());if(count>ordinal)hi=mid;else lo=mid+1;}return lo;}
 std::string font="sans",background="#ffffff",lastError;
 int width() const{return win?Tk_Width(win):1;} int height()const{return win?Tk_Height(win):1;}
 int bodyw()const{return std::max(1,width()-gutter);} int bodyh()const{return std::max(1,height()-head);}
 void clamp(){sx=std::max<int64_t>(0,std::min<int64_t>(sx,std::max<int64_t>(0,totalWidth()-bodyw())));sy=std::max<int64_t>(0,std::min<int64_t>(sy,std::max<int64_t>(0,(int64_t)visibleRows()*rh-bodyh())));}
};
void display(ClientData data);
void schedule(Host *h){if(h->dead)return;if(h->drawing){h->dirtyDuringDraw=true;++h->coalesced;return;}if(h->pending){++h->coalesced;return;}h->pending=true;Tcl_DoWhenIdle(display,h);}
void refset(Tcl_Obj *&dst,Tcl_Obj *src){if(src)Tcl_IncrRefCount(src);if(dst)Tcl_DecrRefCount(dst);dst=src;}
bool call(Host *h,Tcl_Obj *prefix,const std::vector<Tcl_Obj*>&args,Tcl_Obj **result=nullptr){
 if(!prefix||h->dead)return true;int n;Tcl_Obj **v;if(Tcl_ListObjGetElements(h->ip,prefix,&n,&v)!=TCL_OK)return false;
 std::vector<Tcl_Obj*> cmd(v,v+n);cmd.insert(cmd.end(),args.begin(),args.end());for(auto p:cmd)Tcl_IncrRefCount(p);
 int code=Tcl_EvalObjv(h->ip,(int)cmd.size(),cmd.data(),TCL_EVAL_GLOBAL);
 if(code==TCL_OK&&result){*result=Tcl_GetObjResult(h->ip);Tcl_IncrRefCount(*result);}if(code!=TCL_OK)h->lastError=Tcl_GetStringResult(h->ip);
 for(auto p:cmd)Tcl_DecrRefCount(p);return code==TCL_OK;
}
Tcl_Obj *range(Host *h){
 Tcl_Obj *d=Tcl_NewDictObj(),*rowIds=Tcl_NewListObj(0,nullptr);
 int first=(int)(h->sy/h->rh),last=std::min(h->visibleRows()-1,1+(int)((h->sy+h->bodyh())/h->rh));
 for(int i=first;i<=last;++i)Tcl_ListObjAppendElement(nullptr,rowIds,Tcl_NewIntObj(h->rowAt(i)));
 put(d,"first_row",Tcl_NewIntObj(h->rowAt(first)));put(d,"last_row",Tcl_NewIntObj(h->rowAt(last)));put(d,"row_ids",rowIds);
 put(d,"first_column",Tcl_NewIntObj(h->columnAt(h->sx)));put(d,"last_column",Tcl_NewIntObj(std::min(h->columns,h->columnAt(h->sx+h->bodyw())+1)));
 put(d,"generation",Tcl_NewWideIntObj(h->generation));put(d,"revision",Tcl_NewWideIntObj(h->revision));return d;
}
void notify(Host *h,const char *action){Tcl_Obj *d=Tcl_NewDictObj();put(d,"action",str(action));put(d,"phase",str(h->phase));put(d,"row",Tcl_NewIntObj(h->ar));put(d,"column",Tcl_NewIntObj(h->ac));put(d,"anchor_row",Tcl_NewIntObj(h->br));put(d,"anchor_column",Tcl_NewIntObj(h->bc));put(d,"generation",Tcl_NewWideIntObj(h->generation));put(d,"revision",Tcl_NewWideIntObj(h->revision));if(h->resizing){put(d,"column",Tcl_NewIntObj(h->resizing));put(d,"width",Tcl_NewIntObj(h->columnWidth(h->resizing)));}call(h,h->notify,{str(Tk_PathName(h->win)),d});}
void see(Host *h,int r,int c){int64_t x=h->columnLeft(c),y=h->rowTop(r);if(x<h->sx)h->sx=x;else if(x+h->columnWidth(c)>h->sx+h->bodyw())h->sx=x+h->columnWidth(c)-h->bodyw();if(y<h->sy)h->sy=y;else if(y+h->rh>h->sy+h->bodyh())h->sy=y+h->rh-h->bodyh();h->clamp();schedule(h);}
bool color(Host *h,cairo_t *cr,const std::string &s,double alpha=1){if(s.empty()||s=="none")return false;if(s.size()==7&&s[0]=='#'){
 char *end=nullptr;unsigned long rgb=strtoul(s.c_str()+1,&end,16);
 if(end&&*end=='\0'){cairo_set_source_rgba(cr,((rgb>>16)&255)/255.,((rgb>>8)&255)/255.,(rgb&255)/255.,alpha);return true;}
 }
 if(!h->win){std::map<std::string,std::string> basic={{"white","#ffffff"},{"black","#000000"},{"red","#ff0000"},{"green","#008000"},{"blue","#0000ff"},{"gray","#808080"},{"grey","#808080"},{"yellow","#ffff00"},{"orange","#ffa500"}};auto it=basic.find(s);return it!=basic.end()?color(h,cr,it->second,alpha):false;}
 XColor *c=Tk_GetColor(h->ip,h->win,Tk_GetUid(s.c_str()));if(!c){Tcl_ResetResult(h->ip);return false;}cairo_set_source_rgba(cr,c->red/65535.,c->green/65535.,c->blue/65535.,alpha);Tk_FreeColor(c);return true;}
void label(Host *h,cairo_t *cr,double x,double y,const std::string &s,const std::string &ink,double maxWidth=1e9,bool center=false){
 cairo_save(cr);cairo_rectangle(cr,x, y, std::max(0.,maxWidth),h->rh);cairo_clip(cr);color(h,cr,ink);cairo_select_font_face(cr,h->font.c_str(),CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_NORMAL);cairo_set_font_size(cr,h->fontSize);cairo_text_extents_t ex;cairo_text_extents(cr,s.c_str(),&ex);if(center)x+=std::max(0.,(maxWidth-ex.x_advance)/2);cairo_move_to(cr,x,y+(h->rh-h->fontSize)/2.+h->fontSize-2);cairo_show_text(cr,s.c_str());cairo_restore(cr);
}
std::string column(int n){std::string s;while(n){--n;s.insert(s.begin(),char('A'+n%26));n/=26;}return s;}
bool loadCells(Host *h,Tcl_Obj *dict){std::map<std::pair<int,int>,Cell> next;Tcl_DictSearch search;Tcl_Obj *k,*v;int done;
 if(Tcl_DictObjFirst(h->ip,dict,&search,&k,&v,&done)!=TCL_OK)return false;
 for(;!done;Tcl_DictObjNext(&search,&k,&v,&done)){int n;Tcl_Obj **pair;if(Tcl_ListObjGetElements(h->ip,k,&n,&pair)!=TCL_OK||n!=2){Tcl_DictObjDone(&search);return false;}int r,c;if(Tcl_GetIntFromObj(h->ip,pair[0],&r)!=TCL_OK||Tcl_GetIntFromObj(h->ip,pair[1],&c)!=TCL_OK||r<1||r>h->rows||c<1||c>h->columns){Tcl_DictObjDone(&search);return false;}next[{r,c}]={text(h->ip,v,"text"),text(h->ip,v,"kind")};if(next.size()>20000){Tcl_DictObjDone(&search);return false;}}
 Tcl_DictObjDone(&search);h->cells.swap(next);return true;
}
void paintGrid(Host *h,cairo_t *cr){
 int o0=(int)(h->sy/h->rh),o1=std::min(h->visibleRows()-1,1+(int)((h->sy+h->bodyh())/h->rh));
 int c0=h->columnAt(h->sx),c1=std::min(h->columns,h->columnAt(h->sx+h->bodyw())+1);
 cairo_save(cr);cairo_rectangle(cr,h->gutter,h->head,h->bodyw(),h->bodyh());cairo_clip(cr);
 int loR=std::min(h->ar,h->br),hiR=std::max(h->ar,h->br),loC=std::min(h->ac,h->bc),hiC=std::max(h->ac,h->bc);
 for(int o=o0;o<=o1;++o){int r=h->rowAt(o);for(int c=c0;c<=c1;++c){
  double x=h->gutter+h->columnLeft(c)-h->sx,y=h->head+(int64_t)o*h->rh-h->sy;int width=h->columnWidth(c);
  if(h->reference&&r>=h->refR1&&r<=h->refR2&&c>=h->refC1&&c<=h->refC2){color(h,cr,"#e7f4dd");cairo_rectangle(cr,x,y,width,h->rh);cairo_fill(cr);}
  if(r>=loR&&r<=hiR&&c>=loC&&c<=hiC){color(h,cr,"#e8f2ff");cairo_rectangle(cr,x,y,width,h->rh);cairo_fill(cr);}
  auto it=h->cells.find({r,c});if(it!=h->cells.end())label(h,cr,x+5,y,it->second.value,it->second.kind=="error"?"#b32323":"#233746",width-9);
 }}
 color(h,cr,"#dbe3ea");cairo_set_line_width(cr,1);
 for(int o=o0;o<=o1+1;++o){double y=h->head+(int64_t)o*h->rh-h->sy+.5;cairo_move_to(cr,h->gutter,y);cairo_line_to(cr,h->width(),y);}
 for(int c=c0;c<=c1+1;++c){double x=h->gutter+h->columnLeft(c)-h->sx+.5;cairo_move_to(cr,x,h->head);cairo_line_to(cr,x,h->height());}cairo_stroke(cr);
 if(!std::binary_search(h->hiddenRows.begin(),h->hiddenRows.end(),h->ar)){
  color(h,cr,"#2175bd");cairo_set_line_width(cr,2);double ax=h->gutter+h->columnLeft(h->ac)-h->sx,ay=h->head+h->rowTop(h->ar)-h->sy;int width=h->columnWidth(h->ac);
  cairo_rectangle(cr,ax+1,ay+1,width-2,h->rh-2);cairo_stroke(cr);cairo_rectangle(cr,ax+width-5,ay+h->rh-5,5,5);cairo_fill(cr);
 }
 cairo_restore(cr);color(h,cr,"#f0f4f8");cairo_rectangle(cr,0,0,h->width(),h->head);cairo_rectangle(cr,0,0,h->gutter,h->height());cairo_fill(cr);
 cairo_save(cr);cairo_rectangle(cr,h->gutter,0,h->bodyw(),h->head);cairo_clip(cr);
 for(int c=c0;c<=c1;++c)label(h,cr,h->gutter+h->columnLeft(c)-h->sx,1,h->columnLabels.count(c)?h->columnLabels[c]:column(c),"#28475e",h->columnWidth(c),true);cairo_restore(cr);
 cairo_save(cr);cairo_rectangle(cr,0,h->head,h->gutter,h->bodyh());cairo_clip(cr);
 for(int o=o0;o<=o1;++o)label(h,cr,0,h->head+(int64_t)o*h->rh-h->sy,std::to_string(h->rowAt(o)),"#28475e",h->gutter-3,true);cairo_restore(cr);
}
/* The same native device primitive contract is used by Plot v4 and the grid.
 * Surface primitives are presentation only; scientific point identities stay
 * in the producing Native2D model, never inferred from display reduction. */
void paintPrimitives(Host *h,cairo_t *cr){if(!h->primitives)return;int n;Tcl_Obj **items;if(Tcl_ListObjGetElements(h->ip,h->primitives,&n,&items)!=TCL_OK)return;for(int i=0;i<n;++i){auto d=items[i];auto cv=get(h->ip,d,"coords");int m;Tcl_Obj **v;if(!cv||Tcl_ListObjGetElements(h->ip,cv,&m,&v)!=TCL_OK||m<2)continue;std::vector<double> xy;bool ok=true;for(int j=0;j<m;++j){double a;if(Tcl_GetDoubleFromObj(h->ip,v[j],&a)!=TCL_OK||!std::isfinite(a)){ok=false;break;}xy.push_back(a);}if(!ok)continue;cairo_save(cr);auto clip=get(h->ip,d,"clip");if(clip){int z;Tcl_Obj **p;if(Tcl_ListObjGetElements(h->ip,clip,&z,&p)==TCL_OK&&z==4){double q[4];bool good=true;for(int k=0;k<4;++k)good=good&&Tcl_GetDoubleFromObj(h->ip,p[k],q+k)==TCL_OK;if(good){cairo_rectangle(cr,q[0],q[1],q[2]-q[0],q[3]-q[1]);cairo_clip(cr);}}}
 auto type=text(h->ip,d,"type");double alpha=std::max(0.,std::min(1.,number(h->ip,d,"opacity",1)));auto fill=text(h->ip,d,"fill"),stroke=text(h->ip,d,"stroke","#233746");cairo_set_line_width(cr,std::max(.1,number(h->ip,d,"width",1)));auto dash=get(h->ip,d,"dash");if(dash){int z;Tcl_Obj **p;if(Tcl_ListObjGetElements(h->ip,dash,&z,&p)==TCL_OK&&z<=32){std::vector<double>a;for(int k=0;k<z;++k){double x;if(Tcl_GetDoubleFromObj(h->ip,p[k],&x)==TCL_OK&&x>0)a.push_back(x);}if(!a.empty())cairo_set_dash(cr,a.data(),a.size(),0);}}
 if(type=="text"){color(h,cr,fill.empty()?stroke:fill,alpha);cairo_select_font_face(cr,text(h->ip,d,"font_family","sans").c_str(),CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_NORMAL);cairo_set_font_size(cr,number(h->ip,d,"font_size",h->fontSize));std::string s=text(h->ip,d,"text");cairo_text_extents_t ex;cairo_text_extents(cr,s.c_str(),&ex);cairo_translate(cr,xy[0],xy[1]);cairo_rotate(cr,-number(h->ip,d,"angle",0)*acos(-1)/180);auto anchor=text(h->ip,d,"anchor","center");double tx=anchor=="nw"?0:-ex.x_advance/2,ty=anchor=="nw"?-ex.y_bearing:-ex.y_bearing/2;cairo_move_to(cr,tx,ty);cairo_show_text(cr,s.c_str());}
 else {if((type=="rectangle"||type=="oval")&&m>=4){if(type=="rectangle")cairo_rectangle(cr,xy[0],xy[1],xy[2]-xy[0],xy[3]-xy[1]);else {cairo_save(cr);cairo_translate(cr,(xy[0]+xy[2])/2,(xy[1]+xy[3])/2);cairo_scale(cr,std::max(.0001,std::abs(xy[2]-xy[0])/2),std::max(.0001,std::abs(xy[3]-xy[1])/2));cairo_arc(cr,0,0,1,0,2*acos(-1));cairo_restore(cr);}}else{cairo_move_to(cr,xy[0],xy[1]);for(int j=2;j+1<m;j+=2)cairo_line_to(cr,xy[j],xy[j+1]);if(type=="polygon")cairo_close_path(cr);}if(color(h,cr,fill,alpha))cairo_fill_preserve(cr);if(color(h,cr,stroke,alpha))cairo_stroke(cr);else cairo_new_path(cr);}cairo_restore(cr);
}}
int validatePrimitives(Tcl_Interp *ip,Tcl_Obj *primitives){
 int count;Tcl_Obj **items;
 if(Tcl_ListObjGetElements(ip,primitives,&count,&items)!=TCL_OK||count>200000)return error(ip,"Native display list exceeds bounded presentation capacity");
 size_t coordinates=0;
 for(int i=0;i<count;++i){
  auto d=items[i];int fields;if(Tcl_DictObjSize(ip,d,&fields)!=TCL_OK)return TCL_ERROR;
  auto type=text(ip,d,"type");if(type!="line"&&type!="polyline"&&type!="polygon"&&type!="rectangle"&&type!="oval"&&type!="text")return error(ip,"Unknown native device primitive type");
  auto points=get(ip,d,"coords");int n;Tcl_Obj **v;
  if(!points||Tcl_ListObjGetElements(ip,points,&n,&v)!=TCL_OK||n<2||n%2)return error(ip,"Native primitive requires finite XY coordinate pairs");
  if(((type=="rectangle"||type=="oval")&&n!=4)||(type=="text"&&n!=2)||(type=="polygon"&&n<6))return error(ip,"Native primitive coordinate shape is invalid");
  coordinates+=n;if(coordinates>4000000)return error(ip,"Native display coordinates exceed bounded capacity");
  for(int k=0;k<n;++k){double value;if(Tcl_GetDoubleFromObj(ip,v[k],&value)!=TCL_OK||!std::isfinite(value))return error(ip,"Native primitive coordinates must be finite");}
  for(const char *key:{"width","opacity","angle","font_size"}){auto value=get(ip,d,key);double x;if(value&&(Tcl_GetDoubleFromObj(ip,value,&x)!=TCL_OK||!std::isfinite(x)))return error(ip,"Native primitive style requires finite numbers");if(value&&((std::string(key)=="opacity"&&(x<0||x>1))||(std::string(key)=="width"&&x<0)||(std::string(key)=="font_size"&&(x<1||x>256))))return error(ip,"Native primitive style is outside supported bounds");}
  auto clip=get(ip,d,"clip");if(clip){int n;Tcl_Obj **v;if(Tcl_ListObjGetElements(ip,clip,&n,&v)!=TCL_OK||n!=4)return error(ip,"Native clip requires four finite bounds");for(int k=0;k<4;++k){double x;if(Tcl_GetDoubleFromObj(ip,v[k],&x)!=TCL_OK||!std::isfinite(x))return error(ip,"Native clip bounds must be finite");}}
 }
 return TCL_OK;
}
int exportPrimitives(Host *h,const char *path,int width,int height){
 if(width<1||height<1||width>16384||height>16384||(int64_t)width*height>100000000)return error(h->ip,"Native export dimensions exceed supported bounds");
 std::string name=path;auto dot=name.find_last_of('.');std::string kind=dot==std::string::npos?"":name.substr(dot+1);
 cairo_surface_t *surface=nullptr;
 if(kind=="png")surface=cairo_image_surface_create(CAIRO_FORMAT_ARGB32,width,height);
 else if(kind=="pdf")surface=cairo_pdf_surface_create(path,width,height);
 else if(kind=="svg")surface=cairo_svg_surface_create(path,width,height);
 else return error(h->ip,"Native export supports PNG, PDF and SVG");
 if(cairo_surface_status(surface)!=CAIRO_STATUS_SUCCESS){auto status=cairo_surface_status(surface);cairo_surface_destroy(surface);return error(h->ip,cairo_status_to_string(status));}
 cairo_t *cr=cairo_create(surface);color(h,cr,h->background);cairo_paint(cr);paintPrimitives(h,cr);cairo_destroy(cr);
 cairo_status_t status=kind=="png"?cairo_surface_write_to_png(surface,path):CAIRO_STATUS_SUCCESS;
 cairo_surface_finish(surface);if(status==CAIRO_STATUS_SUCCESS)status=cairo_surface_status(surface);cairo_surface_destroy(surface);
 if(status!=CAIRO_STATUS_SUCCESS)return error(h->ip,cairo_status_to_string(status));
 Tcl_Obj *receipt=Tcl_NewDictObj();put(receipt,"path",str(path));put(receipt,"width",Tcl_NewIntObj(width));put(receipt,"height",Tcl_NewIntObj(height));put(receipt,"renderer",str("Native2D.C++.Cairo"));put(receipt,"format",str(kind.c_str()));Tcl_SetObjResult(h->ip,receipt);return TCL_OK;
}
int render(ClientData,Tcl_Interp *ip,int n,Tcl_Obj *const v[]){
 int w,z,count;if(n!=5||Tcl_GetIntFromObj(ip,v[2],&w)!=TCL_OK||Tcl_GetIntFromObj(ip,v[3],&z)!=TCL_OK||Tcl_ListObjLength(ip,v[4],&count)!=TCL_OK)return error(ip,"Usage: native render path width height primitiveList");
 if(validatePrimitives(ip,v[4])!=TCL_OK)return TCL_ERROR;
 Host host;host.ip=ip;host.win=nullptr;host.primitives=v[4];return exportPrimitives(&host,Tcl_GetString(v[1]),w,z);
}
void display(ClientData data){auto h=(Host*)data;h->pending=false;if(h->dead||!h->win||!Tk_IsMapped(h->win))return;Tcl_Preserve(h);h->drawing=true;h->clamp();uint64_t gen=h->generation,rev=h->revision;
 if(h->grid&&h->fetch){Tcl_Obj *reply=nullptr;++h->fetches;if(call(h,h->fetch,{str(Tk_PathName(h->win)),range(h)},&reply)&&reply){if(!h->dead&&h->generation==gen&&h->revision==rev&&!loadCells(h,reply))h->lastError="Invalid bounded grid cell reply";Tcl_DecrRefCount(reply);}}
 if(!h->dead&&h->win&&Tk_IsMapped(h->win)){int w=h->width(),z=h->height();Pixmap pix=Tk_GetPixmap(Tk_Display(h->win),Tk_WindowId(h->win),w,z,Tk_Depth(h->win));cairo_surface_t *surface=cairo_xlib_surface_create(Tk_Display(h->win),pix,Tk_Visual(h->win),w,z);cairo_t *cr=cairo_create(surface);color(h,cr,h->background);cairo_paint(cr);if(h->grid)paintGrid(h,cr);else paintPrimitives(h,cr);cairo_destroy(cr);cairo_surface_destroy(surface);GC gc=Tk_GetGC(h->win,0,nullptr);XCopyArea(Tk_Display(h->win),pix,Tk_WindowId(h->win),gc,0,0,w,z,0,0);Tk_FreeGC(Tk_Display(h->win),gc);Tk_FreePixmap(Tk_Display(h->win),pix);++h->draws;
  if(h->grid){call(h,h->xscroll,{Tcl_NewDoubleObj(double(h->sx)/h->totalWidth()),Tcl_NewDoubleObj(std::min(1.,double(h->sx+h->bodyw())/h->totalWidth()))});if(!h->dead)call(h,h->yscroll,{Tcl_NewDoubleObj(double(h->sy)/((int64_t)h->visibleRows()*h->rh)),Tcl_NewDoubleObj(std::min(1.,double(h->sy+h->bodyh())/((int64_t)h->visibleRows()*h->rh)))});}}
 h->drawing=false;if(h->dirtyDuringDraw&&!h->dead){h->dirtyDuringDraw=false;schedule(h);}Tcl_Release(h);
}
void release(char *ptr){auto h=(Host*)ptr;for(auto p:{h->fetch,h->notify,h->xscroll,h->yscroll,h->primitives})if(p)Tcl_DecrRefCount(p);delete h;}
void deleted(ClientData data){auto h=(Host*)data;h->command=nullptr;if(h->win)Tk_DestroyWindow(h->win);}
void event(ClientData data,XEvent *e){auto h=(Host*)data;if(e->type==DestroyNotify){h->dead=true;h->win=nullptr;if(h->pending)Tcl_CancelIdleCall(display,h);if(h->command){Tcl_DeleteCommandFromToken(h->ip,h->command);h->command=nullptr;}Tcl_EventuallyFree(h,release);return;}Tcl_Preserve(h);
 if(e->type==Expose||e->type==ConfigureNotify){
  if(e->type==ConfigureNotify){
   if(h->previousWidth>0&&h->sx+std::max(1,h->previousWidth-h->gutter)>=h->totalWidth())h->sx=h->totalWidth()-h->bodyw();
   if(h->previousHeight>0&&h->sy+std::max(1,h->previousHeight-h->head)>=(int64_t)h->visibleRows()*h->rh)h->sy=(int64_t)h->visibleRows()*h->rh-h->bodyh();
   h->previousWidth=h->width();h->previousHeight=h->height();
  }
  h->clamp();schedule(h);
 }else if(h->grid){
 if(e->type==ButtonPress&&(e->xbutton.button==4||e->xbutton.button==5)){int direction=e->xbutton.button==4?-1:1;if(e->xbutton.state&ShiftMask)h->sx+=(int64_t)direction*h->cw*3;else h->sy+=(int64_t)direction*h->rh*3;h->clamp();schedule(h);}
 else if(e->type==ButtonPress&&e->xbutton.button==1){h->phase="press";
  Tcl_Obj *focusArgs[2]={str("focus"),str(Tk_PathName(h->win))};for(auto a:focusArgs)Tcl_IncrRefCount(a);Tcl_EvalObjv(h->ip,2,focusArgs,TCL_EVAL_GLOBAL);for(auto a:focusArgs)Tcl_DecrRefCount(a);
  int c=h->columnAt(e->xbutton.x-h->gutter+h->sx),r=h->rowAt((e->xbutton.y-h->head+h->sy)/h->rh);
  int64_t right=h->gutter+h->columnLeft(c+1)-h->sx;int64_t left=h->gutter+h->columnLeft(c)-h->sx;if(c>1&&std::abs(e->xbutton.x-left)<=5){--c;right=left;}
  if(e->xbutton.y<h->head&&e->xbutton.x>=h->gutter&&std::abs(e->xbutton.x-right)<=5){h->resizing=c;h->resizeStartX=e->xbutton.x;h->resizeStartWidth=h->columnWidth(c);}
  else{
   int64_t ax=h->gutter+h->columnLeft(h->ac+1)-h->sx,ay=h->head+h->rowTop(h->ar)+h->rh-h->sy;
   h->filling=e->xbutton.x>=ax-6&&e->xbutton.x<=ax+2&&e->xbutton.y>=ay-6&&e->xbutton.y<=ay+2;
   if(h->filling){h->br=h->ar;h->bc=h->ac;}else{if(!(e->xbutton.state&ShiftMask)){h->br=r;h->bc=c;}h->ar=r;h->ac=c;notify(h,e->xbutton.y<h->head?"column":e->xbutton.x<h->gutter?"row":"select");}
   h->dragging=true;
  }
  schedule(h);
 }
 else if(e->type==MotionNotify&&h->resizing){h->columnWidths[h->resizing]=std::max(35,std::min(2000,h->resizeStartWidth+e->xmotion.x-h->resizeStartX));h->clamp();schedule(h);}
 else if(e->type==MotionNotify&&h->dragging){h->phase="drag";
  if(e->xmotion.x<h->gutter)h->sx-=h->cw;else if(e->xmotion.x>h->width())h->sx+=h->cw;if(e->xmotion.y<h->head)h->sy-=h->rh;else if(e->xmotion.y>h->height())h->sy+=h->rh;h->clamp();
  h->ac=h->columnAt(e->xmotion.x-h->gutter+h->sx);h->ar=h->rowAt((e->xmotion.y-h->head+h->sy)/h->rh);notify(h,"select");schedule(h);
 }
 else if(e->type==ButtonRelease&&e->xbutton.button==1){h->phase="release";bool selected=h->dragging&&!h->filling;h->dragging=false;if(h->resizing){notify(h,"resize");h->resizing=0;}if(h->filling){h->filling=false;notify(h,"fill");}else if(selected)notify(h,"select");}

 else if(e->type==KeyPress){h->phase="key";KeySym key=XLookupKeysym(&e->xkey,0);bool shift=e->xkey.state&ShiftMask,ctrl=e->xkey.state&ControlMask;bool move=true;int r=h->ar,c=h->ac;switch(key){case XK_Left:c=ctrl?1:c-1;break;case XK_Right:c=ctrl?h->columns:c+1;break;case XK_Up:r=ctrl?h->rowAt(0):h->rowAt(h->rowIndex(r)-1);break;case XK_Down:r=ctrl?h->rowAt(h->visibleRows()-1):h->rowAt(h->rowIndex(r)+1);break;case XK_Tab:c+=shift?-1:1;break;case XK_Return:r=h->rowAt(h->rowIndex(r)+(shift?-1:1));break;case XK_Page_Up:r=h->rowAt(h->rowIndex(r)-std::max(1,h->bodyh()/h->rh));break;case XK_Page_Down:r=h->rowAt(h->rowIndex(r)+std::max(1,h->bodyh()/h->rh));break;case XK_Home:c=1;if(ctrl)r=1;break;case XK_End:c=h->columns;if(ctrl)r=h->rows;break;case XK_F2:notify(h,"edit");move=false;break;default:move=false;break;}if(move){h->ar=std::max(1,std::min(h->rows,r));h->ac=std::max(1,std::min(h->columns,c));if(!shift||key==XK_Tab){h->br=h->ar;h->bc=h->ac;}see(h,h->ar,h->ac);notify(h,"select");}}}
 Tcl_Release(h);
}
int command(ClientData data,Tcl_Interp *ip,int n,Tcl_Obj *const v[]){auto h=(Host*)data;if(n<2)return error(ip,"Native2D widget requires an operation");std::string op=Tcl_GetString(v[1]);
 if(op=="configure"){if((n-2)%2)return error(ip,"Expected option/value pairs");for(int i=2;i<n;i+=2){std::string k=Tcl_GetString(v[i]);int z;Tcl_WideInt wide;if(k=="-hiddenrows"){
 std::vector<int> hidden;int count;Tcl_Obj **items;if(Tcl_ListObjGetElements(ip,v[i+1],&count,&items)!=TCL_OK||count>20000)return error(ip,"Hidden row presentation exceeds its 20000-row filter bound");
 for(int j=0;j<count;++j){int row;if(Tcl_GetIntFromObj(ip,items[j],&row)!=TCL_OK||row<1||row>h->rows)return error(ip,"Hidden row is outside grid bounds");hidden.push_back(row);}std::sort(hidden.begin(),hidden.end());hidden.erase(std::unique(hidden.begin(),hidden.end()),hidden.end());if((int)hidden.size()>=h->rows)return error(ip,"Grid requires at least one visible row");h->hiddenRows.swap(hidden);
 }else if(k=="-columnlabels"){
 std::map<int,std::string> labels;Tcl_DictSearch search;Tcl_Obj *key,*val;int done;if(Tcl_DictObjFirst(ip,v[i+1],&search,&key,&val,&done)!=TCL_OK)return TCL_ERROR;
 for(;!done;Tcl_DictObjNext(&search,&key,&val,&done)){int c;if(Tcl_GetIntFromObj(ip,key,&c)!=TCL_OK||c<1||c>h->columns){Tcl_DictObjDone(&search);return error(ip,"Invalid column label identity");}labels[c]=Tcl_GetString(val);}Tcl_DictObjDone(&search);h->columnLabels.swap(labels);
 }else if(k=="-columnwidths"){
 std::map<int,int> widths;Tcl_DictSearch search;Tcl_Obj *key,*val;int done;if(Tcl_DictObjFirst(ip,v[i+1],&search,&key,&val,&done)!=TCL_OK)return TCL_ERROR;
 for(;!done;Tcl_DictObjNext(&search,&key,&val,&done)){int c,w;if(Tcl_GetIntFromObj(ip,key,&c)!=TCL_OK||Tcl_GetIntFromObj(ip,val,&w)!=TCL_OK||c<1||c>h->columns||w<35||w>2000){Tcl_DictObjDone(&search);return error(ip,"Invalid column width presentation");}widths[c]=w;}Tcl_DictObjDone(&search);h->columnWidths.swap(widths);
 }else if(k=="-fetchcommand")refset(h->fetch,v[i+1]);else if(k=="-command")refset(h->notify,v[i+1]);else if(k=="-xscrollcommand")refset(h->xscroll,v[i+1]);else if(k=="-yscrollcommand")refset(h->yscroll,v[i+1]);else if(k=="-generation"||k=="-revision"){if(Tcl_GetWideIntFromObj(ip,v[i+1],&wide)!=TCL_OK||wide<0)return error(ip,"Invalid grid epoch");if(k=="-generation"){h->generation=wide;h->cells.clear();}else {if(h->revision!=(uint64_t)wide)h->cells.clear();h->revision=wide;}}else if(k=="-background")h->background=Tcl_GetString(v[i+1]);else if(k=="-fontfamily")h->font=Tcl_GetString(v[i+1]);else if(k=="-rows"||k=="-columns"||k=="-rowheight"||k=="-columnwidth"||k=="-fontsize"){if(Tcl_GetIntFromObj(ip,v[i+1],&z)!=TCL_OK)return TCL_ERROR;if(k=="-rows"&&z>=1&&z<=1000000)h->rows=z;else if(k=="-columns"&&z>=1&&z<=702)h->columns=z;else if(k=="-rowheight"&&z>=16&&z<=200)h->rh=z;else if(k=="-columnwidth"&&z>=35&&z<=2000)h->cw=z;else if(k=="-fontsize"&&z>=6&&z<=72){h->fontSize=z;h->head=std::max(27,z+8);h->gutter=std::max(56,z*5);}else return error(ip,"Grid option is outside supported bounds");}else return error(ip,"Unknown Native2D widget option");}h->clamp();schedule(h);return TCL_OK;}
 if(op=="draw"){if(n!=3)return error(ip,"Usage: surface draw primitiveList");int z;if(validatePrimitives(ip,v[2])!=TCL_OK)return TCL_ERROR;refset(h->primitives,v[2]);schedule(h);return TCL_OK;}
 if(op=="invalidate"){schedule(h);return TCL_OK;}
 if(op=="reference"){
  if(n==2){h->reference=false;schedule(h);return TCL_OK;}
  int r1,c1,r2,c2;if(n!=6||Tcl_GetIntFromObj(ip,v[2],&r1)!=TCL_OK||Tcl_GetIntFromObj(ip,v[3],&c1)!=TCL_OK||Tcl_GetIntFromObj(ip,v[4],&r2)!=TCL_OK||Tcl_GetIntFromObj(ip,v[5],&c2)!=TCL_OK||r1<1||r2<1||r1>h->rows||r2>h->rows||c1<1||c2<1||c1>h->columns||c2>h->columns)return error(ip,"Reference highlight is outside grid bounds");
  h->reference=true;h->refR1=std::min(r1,r2);h->refR2=std::max(r1,r2);h->refC1=std::min(c1,c2);h->refC2=std::max(c1,c2);schedule(h);return TCL_OK;
 }
 if(op=="export"){int w,z;if(n!=5||Tcl_GetIntFromObj(ip,v[3],&w)!=TCL_OK||Tcl_GetIntFromObj(ip,v[4],&z)!=TCL_OK)return error(ip,"Usage: surface export path width height");if(h->grid)return error(ip,"Grid exports use the authoritative Workbook publication owner");return exportPrimitives(h,Tcl_GetString(v[2]),w,z);}
 if(op=="viewport"||op=="receipt"){auto d=range(h);put(d,"x",Tcl_NewWideIntObj(h->sx));put(d,"y",Tcl_NewWideIntObj(h->sy));put(d,"rows",Tcl_NewIntObj(h->rows));put(d,"columns",Tcl_NewIntObj(h->columns));put(d,"draws",Tcl_NewWideIntObj(h->draws));put(d,"fetches",Tcl_NewWideIntObj(h->fetches));put(d,"coalesced",Tcl_NewWideIntObj(h->coalesced));put(d,"retained_cells",Tcl_NewIntObj(h->cells.size()));put(d,"row_header_width",Tcl_NewIntObj(h->gutter));put(d,"header_height",Tcl_NewIntObj(h->head));put(d,"width",Tcl_NewIntObj(h->width()));put(d,"height",Tcl_NewIntObj(h->height()));put(d,"native",str("Native2D.C++.Cairo.Tk"));put(d,"error",str(h->lastError.c_str()));Tcl_SetObjResult(ip,d);return TCL_OK;}
 if(op=="xview"||op=="yview"){bool x=op=="xview";int64_t &pos=x?h->sx:h->sy;int64_t total=x?h->totalWidth():(int64_t)h->visibleRows()*h->rh;int visible=x?h->bodyw():h->bodyh();if(n==2){Tcl_Obj *a[2]={Tcl_NewDoubleObj(double(pos)/total),Tcl_NewDoubleObj(std::min(1.,double(pos+visible)/total))};Tcl_SetObjResult(ip,Tcl_NewListObj(2,a));return TCL_OK;}if(n==4&&std::string(Tcl_GetString(v[2]))=="moveto"){double f;if(Tcl_GetDoubleFromObj(ip,v[3],&f)!=TCL_OK||!std::isfinite(f))return error(ip,"Invalid scroll fraction");pos=(int64_t)(std::max(0.,std::min(1.,f))*total);}else if(n==5&&std::string(Tcl_GetString(v[2]))=="scroll"){Tcl_WideInt count;if(Tcl_GetWideIntFromObj(ip,v[3],&count)!=TCL_OK)return TCL_ERROR;int step=std::string(Tcl_GetString(v[4]))=="pages"?visible:(x?h->cw:h->rh);long double next=(long double)pos+(long double)count*step;pos=(int64_t)std::max<long double>(0,std::min<long double>(total,next));}else return error(ip,"Usage: widget xview|yview moveto fraction | scroll count units|pages");h->clamp();schedule(h);return TCL_OK;}
 if(op=="hit"){int x,y;if(n!=4||Tcl_GetIntFromObj(ip,v[2],&x)!=TCL_OK||Tcl_GetIntFromObj(ip,v[3],&y)!=TCL_OK)return TCL_ERROR;if(x<h->gutter||y<h->head||x>=h->width()||y>=h->height())return TCL_OK;Tcl_Obj *a[2]={Tcl_NewIntObj(h->rowAt((y-h->head+h->sy)/h->rh)),Tcl_NewIntObj(h->columnAt(x-h->gutter+h->sx))};Tcl_SetObjResult(ip,Tcl_NewListObj(2,a));return TCL_OK;}
 if(op=="select"||op=="see"||op=="bbox"){int r,c;if(n<4||Tcl_GetIntFromObj(ip,v[2],&r)!=TCL_OK||Tcl_GetIntFromObj(ip,v[3],&c)!=TCL_OK||r<1||r>h->rows||c<1||c>h->columns)return error(ip,"Cell is outside native grid bounds");if(op=="see")see(h,r,c);else if(op=="bbox"){Tcl_Obj *a[4]={Tcl_NewWideIntObj(h->gutter+h->columnLeft(c)-h->sx),Tcl_NewWideIntObj(h->head+h->rowTop(r)-h->sy),Tcl_NewIntObj(h->columnWidth(c)),Tcl_NewIntObj(h->rh)};Tcl_SetObjResult(ip,Tcl_NewListObj(4,a));}else{int br=r,bc=c;if(n!=4&&n!=6)return error(ip,"Usage: grid select row column ?anchorRow anchorColumn?");if(n==6&&(Tcl_GetIntFromObj(ip,v[4],&br)!=TCL_OK||Tcl_GetIntFromObj(ip,v[5],&bc)!=TCL_OK||br<1||br>h->rows||bc<1||bc>h->columns))return error(ip,"Selection is outside bounds");h->ar=r;h->ac=c;h->br=br;h->bc=bc;schedule(h);}return TCL_OK;}
 return error(ip,"Unknown Native2D widget operation");
}
int create(ClientData data,Tcl_Interp *ip,int n,Tcl_Obj *const v[]){if(n<2)return error(ip,"Usage: native surface|grid widgetPath ?options?");Tk_Window main=Tk_MainWindow(ip);if(!main)return error(ip,"Native2D presentation requires a live Tk interpreter");Tk_Window win=Tk_CreateWindowFromPath(ip,main,Tcl_GetString(v[1]),nullptr);if(!win)return TCL_ERROR;auto h=new Host;h->ip=ip;h->win=win;h->grid=data!=nullptr;Tk_SetClass(win,h->grid?"GXNativeGrid":"GXNativeSurface");Tk_GeometryRequest(win,600,350);Tk_CreateEventHandler(win,ExposureMask|StructureNotifyMask|ButtonPressMask|ButtonReleaseMask|PointerMotionMask|KeyPressMask,event,h);h->command=Tcl_CreateObjCommand(ip,Tk_PathName(win),command,h,deleted);if(n>2){std::vector<Tcl_Obj*> args={v[1],str("configure")};args.insert(args.end(),v+2,v+n);if(command(h,ip,args.size(),args.data())!=TCL_OK){Tk_DestroyWindow(win);return TCL_ERROR;}}Tcl_SetObjResult(ip,v[1]);return TCL_OK;}
}
extern "C" int gx2d_surface_init(Tcl_Interp *ip){Tcl_CreateNamespace(ip,"::gx::native2d",nullptr,nullptr);Tcl_CreateObjCommand(ip,"::gx::native2d::surface",create,nullptr,nullptr);Tcl_CreateObjCommand(ip,"::gx::native2d::grid",create,(ClientData)1,nullptr);Tcl_CreateObjCommand(ip,"::gx::native2d::render",render,nullptr,nullptr);return TCL_OK;}
