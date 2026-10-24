/* SPDX-License-Identifier: GPL-3.0-or-later
 * Shared Native2D presentation batching. Geometry and clipping remain owned by
 * gx2d; Tk commands are the supported widget boundary (no private Tk structs).
 * No retained scene/widget cache: every pass reads current geometry and bounds.
 */
#include "gx2d_presentation_batch.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <new>
#include <string>
#include <unordered_set>
#include <vector>
namespace {
struct Failure {};
struct Obj {
    Tcl_Obj *p;
    explicit Obj(Tcl_Obj *value):p(value){Tcl_IncrRefCount(p);}
    Obj(const Obj &o):Obj(o.p){}
    ~Obj(){Tcl_DecrRefCount(p);}
    Obj &operator=(const Obj &)=delete;
};
Obj str(const char *s){return Obj(Tcl_NewStringObj(s,-1));}
Obj num(double n){return Obj(Tcl_NewDoubleObj(n));}
void fail(Tcl_Interp *ip,const char *message){Tcl_SetObjResult(ip,Tcl_NewStringObj(message,-1));throw Failure{};}
std::vector<Tcl_Obj *> elements(Tcl_Interp *ip,Tcl_Obj *o){int n;Tcl_Obj **v;if(Tcl_ListObjGetElements(ip,o,&n,&v)!=TCL_OK)throw Failure{};return {v,v+n};}
double number(Tcl_Interp *ip,Tcl_Obj *o){double n;if(Tcl_GetDoubleFromObj(ip,o,&n)!=TCL_OK)throw Failure{};return n;}
std::vector<double> numbers(Tcl_Interp *ip,Tcl_Obj *o){std::vector<double> result;for(auto v:elements(ip,o))result.push_back(number(ip,v));return result;}
struct Canvas {
    Tcl_Interp *ip;Tcl_Obj *name;
    Obj find=str("find"),withtag=str("withtag"),all=str("all"),bbox=str("bbox"),type=str("type"),coords=str("coords"),itemcget=str("itemcget"),width=str("-width"),erase=str("delete"),gettags=str("gettags"),create=str("create"),line=str("line"),tags=str("-tags");
    Obj call(const std::vector<Tcl_Obj *> &args){std::vector<Tcl_Obj *> cmd{name};cmd.insert(cmd.end(),args.begin(),args.end());if(Tcl_EvalObjv(ip,(int)cmd.size(),cmd.data(),TCL_EVAL_GLOBAL)!=TCL_OK)throw Failure{};return Obj(Tcl_GetObjResult(ip));}
    Obj call(std::initializer_list<Tcl_Obj *> args){return call(std::vector<Tcl_Obj *>(args));}
    void setcoords(Tcl_Obj *item,const std::vector<double> &v){std::vector<Obj> keep;keep.reserve(v.size());std::vector<Tcl_Obj *> args{coords.p,item};for(double d:v){keep.emplace_back(Tcl_NewDoubleObj(d));args.push_back(keep.back().p);}call(args);}
};
int memory(Tcl_Interp *ip){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native2D presentation allocation failed",-1));return TCL_ERROR;}
}
extern "C" int gx2d_grid_presentation(Tcl_Interp *ip,const gx2d_scene *scene,double spacing){
    try {
        std::array<gx2d_grid_segment,2048> lines;size_t n=0;
        auto code=gx2d_grid_render(scene,lines.data(),lines.size(),&n);
        if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));
        std::vector<double> coordinates[3][2];bool suppressed[3][2]={{false,false},{false,false},{false,false}};
        if(spacing>0){
            for(size_t i=0;i<n;++i){auto &l=lines[i];if(l.classification==2)continue;int axis=std::fabs(l.a.x-l.b.x)<.5?0:1;coordinates[l.classification][axis].push_back(axis?l.a.y:l.a.x);}
            for(int kind=0;kind<2;++kind)for(int axis=0;axis<2;++axis){auto &v=coordinates[kind][axis];std::sort(v.begin(),v.end());v.erase(std::unique(v.begin(),v.end()),v.end());for(size_t i=1;i<v.size();++i)if(v[i]-v[i-1]<spacing){suppressed[kind][axis]=true;break;}}
        }
        Obj result(Tcl_NewListObj(0,nullptr));
        for(size_t i=0;i<n;++i){auto &l=lines[i];int axis=std::fabs(l.a.x-l.b.x)<.5?0:1;if(suppressed[l.classification][axis])continue;
            Tcl_Obj *v[]={Tcl_NewDoubleObj(l.a.x),Tcl_NewDoubleObj(l.a.y),Tcl_NewDoubleObj(l.b.x),Tcl_NewDoubleObj(l.b.y),Tcl_NewIntObj(l.classification)};
            Tcl_ListObjAppendElement(ip,result.p,Tcl_NewListObj(5,v));
        }
        Tcl_SetObjResult(ip,result.p);return TCL_OK;
    }catch(const Failure &){return TCL_ERROR;}catch(const std::bad_alloc &){return memory(ip);}
}
extern "C" int gx2d_canvas_clip(Tcl_Interp *ip,const gx2d_scene *scene,Tcl_Obj *canvas,Tcl_Obj *protectedTags,Tcl_Obj *photos,Tcl_Obj *items){
    try {
        gx2d_view view;auto code=gx2d_view_get(scene,&view);if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));
        double left=view.left,top=view.top,right=view.width-view.right,bottom=view.height-view.bottom;
        Canvas c{ip,canvas};std::unordered_set<std::string> excluded;
        // Standard tags are selected once by Tk. Special/numeric tag strings
        // need literal membership, since Tk's search grammar has other meanings.
        std::unordered_set<std::string> literalTags;
        for(auto tag:elements(ip,protectedTags)){
            std::string name=Tcl_GetString(tag);
            bool simple=!name.empty()&&(std::isalpha((unsigned char)name[0])||name[0]=='_')&&name!="all"&&name!="current";
            for(char ch:name)if(!std::isalnum((unsigned char)ch)&&ch!='_'&&ch!='.'&&ch!=':'&&ch!='-')simple=false;
            if(!simple){literalTags.insert(name);continue;}
            auto found=c.call({c.find.p,c.withtag.p,tag});
            for(auto id:elements(ip,found.p))excluded.emplace(Tcl_GetString(id));
        }
        Obj found(items?items:c.call({c.find.p,c.all.p}).p);
        for(auto item:elements(ip,found.p)){
            if(excluded.count(Tcl_GetString(item)))continue;
            if(!literalTags.empty()){
                auto tags=c.call({c.gettags.p,item});bool skip=false;
                for(auto tag:elements(ip,tags.p))if(literalTags.count(Tcl_GetString(tag))){skip=true;break;}
                if(skip)continue;
            }
            auto box=c.call({c.bbox.p,item});auto b=numbers(ip,box.p);
            // A conservative Tk bbox entirely inside the viewport needs no
            // clipping. This removes repeated type/tag/style/coordinate queries
            // for unchanged visible markers and curves, including later passes.
            if(b.size()==4&&b[0]>=left&&b[1]>=top&&b[2]<=right&&b[3]<=bottom)continue;
            auto type=c.call({c.type.p,item});std::string kind=Tcl_GetString(type.p);
            if(kind=="line"){
                auto coords=c.call({c.coords.p,item});auto xy=numbers(ip,coords.p);auto w=c.call({c.itemcget.p,item,c.width.p});double inset=number(ip,w.p)/2;
                std::vector<std::vector<double>> paths;std::vector<double> path;gx2d_point previous{};bool connected=false;
                for(size_t j=2;j+1<xy.size();j+=2){gx2d_point a,bp;int shown;
                    code=gx2d_viewport_clip_segment(scene,{xy[j-2],xy[j-1]},{xy[j],xy[j+1]},inset,&a,&bp,&shown);if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));
                    if(shown){if(!connected||std::fabs(a.x-previous.x)>1e-7||std::fabs(a.y-previous.y)>1e-7){if(connected)paths.push_back(path);path={a.x,a.y};}path.push_back(bp.x);path.push_back(bp.y);previous=bp;connected=true;}
                    else if(connected){paths.push_back(path);path.clear();connected=false;}
                }
                if(connected)paths.push_back(path);
                if(paths.size()==1){if(paths[0]!=xy)c.setcoords(item,paths[0]);}
                else if(paths.empty()){c.call({c.erase.p,item});}
                else {
                    // Read presentation attributes only when splitting actually
                    // needs replacement items; the common one-path case doesn't.
                    auto tags=c.call({c.gettags.p,item});std::vector<Obj> keep;keep.reserve(18);std::vector<Tcl_Obj *> options;
                    for(const char *key:{"-fill","-width","-dash","-capstyle","-joinstyle","-stipple","-arrow","-arrowshape","-state"}){
                        keep.emplace_back(Tcl_NewStringObj(key,-1));auto value=c.call({c.itemcget.p,item,keep.back().p});options.push_back(keep.back().p);keep.push_back(value);options.push_back(keep.back().p);
                    }
                    c.call({c.erase.p,item});
                    for(auto &p:paths){std::vector<Obj> values;values.reserve(p.size());std::vector<Tcl_Obj *> args{c.create.p,c.line.p};for(double d:p){values.emplace_back(Tcl_NewDoubleObj(d));args.push_back(values.back().p);}args.insert(args.end(),options.begin(),options.end());args.push_back(c.tags.p);args.push_back(tags.p);c.call(args);}
                }
            }else if(kind=="rectangle"){
                auto coords=c.call({c.coords.p,item});auto xy=numbers(ip,coords.p);if(xy.size()!=4)continue;
                auto w=c.call({c.itemcget.p,item,c.width.p});double inset=number(ip,w.p)/2;
                std::vector<double> clipped{std::max(xy[0],left+inset),std::max(xy[1],top+inset),std::min(xy[2],right-inset),std::min(xy[3],bottom-inset)};
                if(clipped[0]>clipped[2]||clipped[1]>clipped[3])c.call({c.erase.p,item});else if(clipped!=xy)c.setcoords(item,clipped);
            }else{
                bool managed=false;
                if(kind=="image"){
                    auto key=str("-image");auto photo=c.call({c.itemcget.p,item,key.p});Tcl_Obj *id=nullptr;
                    if(Tcl_DictObjGet(ip,photos,photo.p,&id)!=TCL_OK)throw Failure{};
                    managed=id&&std::string(Tcl_GetString(id))==Tcl_GetString(item);
                }
                if(kind=="oval"||kind=="polygon"||kind=="text"||managed){if(b.size()!=4||b[0]<left||b[1]<top||b[2]>right||b[3]>bottom)c.call({c.erase.p,item});}
            }
        }
        Tcl_ResetResult(ip);return TCL_OK;
    }catch(const Failure &){return TCL_ERROR;}catch(const std::bad_alloc &){return memory(ip);}
}
