/* SPDX-License-Identifier: GPL-3.0-or-later
 * Existing published-Dataset raster overlay collection, without a private
 * reader, calibration policy, predicate implementation or numeric comparator.
 */
#include "gx2d_preview_overlay_v1.h"
#include <cmath>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
namespace {
struct Obj {
    Tcl_Obj *p;
    explicit Obj(Tcl_Obj *v):p(v){Tcl_IncrRefCount(p);}
    Obj(const Obj &v):Obj(v.p){}
    Obj(Obj &&v) noexcept:p(v.p){v.p=nullptr;}
    ~Obj(){if(p)Tcl_DecrRefCount(p);}
    Obj &operator=(const Obj&)=delete;
};
std::string text(Tcl_Obj *v){int n;const char *p=Tcl_GetStringFromObj(v,&n);return {p,static_cast<size_t>(n)};}
Tcl_Obj *get(Tcl_Interp *ip,Tcl_Obj *d,const char *name){
    Obj key(Tcl_NewStringObj(name,-1));Tcl_Obj *v=nullptr;
    if(Tcl_DictObjGet(ip,d,key.p,&v)!=TCL_OK||!v)throw std::runtime_error(std::string("Missing overlay field: ")+name);
    return v;
}
void put(Tcl_Obj *d,const char *name,Tcl_Obj *v){Obj key(Tcl_NewStringObj(name,-1));Tcl_DictObjPut(nullptr,d,key.p,v);}
std::vector<Tcl_Obj*> list(Tcl_Interp *ip,Tcl_Obj *v){int n;Tcl_Obj **p;if(Tcl_ListObjGetElements(ip,v,&n,&p)!=TCL_OK)throw std::runtime_error("Invalid overlay list");return n?std::vector<Tcl_Obj*>(p,p+n):std::vector<Tcl_Obj*>{};}
Obj call(Tcl_Interp *ip,std::vector<Tcl_Obj*> args){
    if(Tcl_EvalObjv(ip,static_cast<int>(args.size()),args.data(),TCL_EVAL_GLOBAL)!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(ip));
    return Obj(Tcl_GetObjResult(ip));
}
struct Curve {Obj identity,label,points;size_t count=0;Curve(Tcl_Obj *i,Tcl_Obj *l):identity(i),label(l),points(Tcl_NewListObj(0,nullptr)){} };
struct Collector {
    Obj columns;bool raster,failed=false,finished=false,busy=false;size_t count=0,bytes=0,cacheBytes=0;
    std::vector<Obj> filters;std::vector<std::unordered_map<std::string,bool>> predicateCache;
    std::unordered_map<std::string,bool> integerCache;
    std::unordered_map<std::string,size_t> identities;std::vector<Curve> curves;
    std::unordered_map<std::string,Obj> seen;
    Collector(Tcl_Interp *ip,Tcl_Obj *c,Tcl_Obj *r,Tcl_Obj *f):columns(c){
        int enabled;if(Tcl_GetBooleanFromObj(ip,r,&enabled)!=TCL_OK)throw std::runtime_error("Invalid raster availability");raster=enabled!=0;
        for(auto *v:list(ip,f))filters.emplace_back(v);
        predicateCache.resize(filters.size());
        for(const char *role:{"curve_key","curve_name","point_order"})get(ip,columns.p,role);
        if(raster){get(ip,columns.p,"raster_x");get(ip,columns.p,"raster_y");}
    }
    void retain(size_t n){if(n>67108864-bytes)throw std::runtime_error("Source overlay retained token payload exceeds64MiB");bytes+=n;}
    bool matches(Tcl_Interp *ip,size_t i,Tcl_Obj *cell){
        std::string key=text(cell);auto &cache=predicateCache[i];auto found=cache.find(key);if(found!=cache.end())return found->second;
        Obj command(Tcl_NewStringObj("::GX::GraphSelectionAPIv1::_matchesFilter",-1));
        Obj answer=call(ip,{command.p,cell,filters[i].p});int accepted;
        if(Tcl_GetBooleanFromObj(ip,answer.p,&accepted)!=TCL_OK)throw std::runtime_error("Invalid overlay predicate result");
        if(key.size()+1<=2097152-cacheBytes){cacheBytes+=key.size()+1;cache.emplace(std::move(key),accepted!=0);}
        return accepted!=0;
    }
    void validateOrder(Tcl_Interp *ip,Tcl_Obj *order){
        std::string key=text(order);auto found=integerCache.find(key);
        if(found!=integerCache.end())return;
        Obj command(Tcl_NewStringObj("::string",-1)),is(Tcl_NewStringObj("is",-1)),type(Tcl_NewStringObj("entier",-1)),strict(Tcl_NewStringObj("-strict",-1));
        Obj answer=call(ip,{command.p,is.p,type.p,strict.p,order});int valid;
        if(Tcl_GetBooleanFromObj(ip,answer.p,&valid)!=TCL_OK||!valid)throw std::runtime_error("Invalid published within-curve point identity");
        if(key.size()+1<=2097152-cacheBytes){cacheBytes+=key.size()+1;integerCache.emplace(std::move(key),true);}
    }
    void push(Tcl_Interp *ip,Tcl_Obj *values,Tcl_Obj *rowCount){
        int rows;if(Tcl_GetIntFromObj(ip,rowCount,&rows)!=TCL_OK||rows<0||rows>2048)throw std::runtime_error("Overlay chunk row count is outside0..2048");
        std::unordered_map<std::string,std::vector<Tcl_Obj*>> projected;
        auto project=[&](Tcl_Obj *vid){std::string id=text(vid);if(projected.count(id))return;Obj key(Tcl_NewStringObj(id.data(),static_cast<int>(id.size())));Tcl_Obj *v=nullptr;
            if(Tcl_DictObjGet(ip,values,key.p,&v)!=TCL_OK||!v)throw std::runtime_error("Missing overlay projected variable");
            auto cells=list(ip,v);if(cells.size()!=static_cast<size_t>(rows))throw std::runtime_error("Overlay projected column count mismatch");projected.emplace(std::move(id),std::move(cells));};
        for(const char *role:{"curve_key","curve_name","point_order"})project(get(ip,columns.p,role));
        if(raster){project(get(ip,columns.p,"raster_x"));project(get(ip,columns.p,"raster_y"));}
        for(const auto &filter:filters)project(get(ip,filter.p,"filter_variable_id"));
        const auto &curveValues=projected.at(text(get(ip,columns.p,"curve_key")));
        const auto &labelValues=projected.at(text(get(ip,columns.p,"curve_name")));
        const auto &orderValues=projected.at(text(get(ip,columns.p,"point_order")));
        const auto *rasterX=raster?&projected.at(text(get(ip,columns.p,"raster_x"))):nullptr;
        const auto *rasterY=raster?&projected.at(text(get(ip,columns.p,"raster_y"))):nullptr;
        std::vector<const std::vector<Tcl_Obj*>*> filterValues;
        for(const auto &filter:filters)filterValues.push_back(&projected.at(text(get(ip,filter.p,"filter_variable_id"))));
        for(int i=0;i<rows;++i){
            bool accepted=true;for(size_t j=0;j<filters.size();++j){if(!matches(ip,j,(*filterValues[j])[static_cast<size_t>(i)])){accepted=false;break;}}
            if(!accepted)continue;
            Tcl_Obj *curve=curveValues[static_cast<size_t>(i)],*order=orderValues[static_cast<size_t>(i)];validateOrder(ip,order);
            std::string curveKey=text(curve);auto found=identities.find(curveKey);size_t index;
            if(found==identities.end()){retain(curveKey.size()+text(labelValues[static_cast<size_t>(i)]).size());index=curves.size();identities.emplace(std::move(curveKey),index);curves.emplace_back(curve,labelValues[static_cast<size_t>(i)]);}else index=found->second;
            Tcl_Obj *identityValues[]={curve,order};Obj identity(Tcl_NewListObj(2,identityValues));
            Tcl_Obj *pointValues[]={order,raster?(*rasterX)[static_cast<size_t>(i)]:nullptr,raster?(*rasterY)[static_cast<size_t>(i)]:nullptr};
            Obj point(Tcl_NewListObj(raster?3:1,pointValues));
            if(raster)for(int axis=1;axis<3;++axis){double v;if(Tcl_GetDoubleFromObj(ip,pointValues[axis],&v)!=TCL_OK||!std::isfinite(v))throw std::runtime_error("Nonfinite source raster coordinate");}
            std::string key=text(identity.p);auto previous=seen.find(key);
            if(previous!=seen.end()){if(text(previous->second.p)!=text(point.p))throw std::runtime_error("Calibration realizations disagree on source raster identity");continue;}
            if(count>=65536)throw std::runtime_error("Source overlay exceeds 65536 unique points; canonical data remain complete");
            retain(key.size()+text(point.p).size());seen.emplace(std::move(key),point);++count;
            auto &data=curves[index];++data.count;if(raster)Tcl_ListObjAppendElement(ip,data.points.p,point.p);
        }
    }
    Obj finish(Tcl_Interp *ip){
        Obj result(Tcl_NewDictObj()),items(Tcl_NewDictObj());
        for(auto &curve:curves){
            Obj command(Tcl_NewStringObj("::lsort",-1)),integer(Tcl_NewStringObj("-integer",-1)),option(Tcl_NewStringObj("-index",-1)),index(Tcl_NewIntObj(0));
            Obj points=call(ip,{command.p,integer.p,option.p,index.p,curve.points.p});
            Obj data(Tcl_NewDictObj());put(data.p,"label",curve.label.p);put(data.p,"points",points.p);put(data.p,"unique_points",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(curve.count)));
            Tcl_DictObjPut(ip,items.p,curve.identity.p,data.p);
        }
        put(result.p,"curves",items.p);put(result.p,"unique_point_count",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(count)));finished=true;return result;
    }
};
struct State {uint64_t serial=0;std::unordered_map<std::string,std::shared_ptr<Collector>> entries;};
void dispose(ClientData data,Tcl_Interp *){delete static_cast<State*>(data);}
struct Busy {Collector &c;explicit Busy(Collector &v):c(v){if(c.busy)throw std::runtime_error("Overlay collector is busy");if(c.failed||c.finished)throw std::runtime_error("Overlay collector is no longer ingesting");c.busy=true;}~Busy(){c.busy=false;}};
int command(ClientData data,Tcl_Interp *ip,int objc,Tcl_Obj *const objv[]){
    auto *state=static_cast<State*>(data);
    try{
        if(objc<2)throw std::runtime_error("Overlay requires begin/push/finish/destroy");
        std::string op=text(objv[1]);
        if(op=="begin"){
            if(objc!=5)throw std::runtime_error("Overlay begin columns raster filters");
            if(state->entries.size()>=4)throw std::runtime_error("Too many overlay collectors");
            auto collector=std::make_shared<Collector>(ip,objv[2],objv[3],objv[4]);std::string id="overlay-"+std::to_string(++state->serial);state->entries.emplace(id,std::move(collector));Tcl_SetObjResult(ip,Tcl_NewStringObj(id.data(),static_cast<int>(id.size())));return TCL_OK;
        }
        if(objc<3)throw std::runtime_error("Overlay requires a collector");
        auto found=state->entries.find(text(objv[2]));
        if(found==state->entries.end())throw std::runtime_error("Unknown overlay collector");
        auto collector=found->second;
        if(op=="destroy"){if(objc!=3)throw std::runtime_error("Overlay destroy collector");if(collector->busy)throw std::runtime_error("Overlay collector is busy");state->entries.erase(found);Tcl_ResetResult(ip);return TCL_OK;}
        Busy busy(*collector);
        try{
            if(op=="push"&&objc==5){collector->push(ip,objv[3],objv[4]);Tcl_ResetResult(ip);return TCL_OK;}
            if(op=="finish"&&objc==3){Obj result=collector->finish(ip);Tcl_SetObjResult(ip,result.p);return TCL_OK;}
            throw std::runtime_error("Invalid overlay operation/arguments");
        }catch(...){collector->failed=true;throw;}
    }catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
    catch(...){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native overlay preparation failed",-1));return TCL_ERROR;}
}
}
extern "C" int gx2d_preview_overlay_v1_init(Tcl_Interp *ip){
    if(Tcl_GetAssocData(ip,"gx2d.preview.overlay.v1",nullptr))return TCL_OK;
    if(!Tcl_FindNamespace(ip,"::gx::native2d",nullptr,0)&&!Tcl_CreateNamespace(ip,"::gx::native2d",nullptr,nullptr))return TCL_ERROR;
    auto *state=new State;Tcl_SetAssocData(ip,"gx2d.preview.overlay.v1",dispose,state);
    Tcl_CreateObjCommand(ip,"::gx::native2d::_preview_overlay",command,state,nullptr);return TCL_OK;
}
