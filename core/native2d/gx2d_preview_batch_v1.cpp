/* SPDX-License-Identifier: GPL-3.0-or-later
 * Internal one-projection Curve Source preparation. Canonical access, identity
 * validation, predicates and coordinate presentation retain their public owners.
 */
#include "gx2d_preview_batch_v1.h"
#include "gx2d.h"
#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <exception>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
namespace {
int fail(Tcl_Interp *ip,const char *message) {Tcl_SetObjResult(ip,Tcl_NewStringObj(message,-1));return TCL_ERROR;}
#include "gx2d_tcl_columns.h"
struct Obj {
    Tcl_Obj *p;
    explicit Obj(Tcl_Obj *v):p(v){Tcl_IncrRefCount(p);}
    Obj(const Obj &o):Obj(o.p){}
    Obj(Obj &&o) noexcept:p(o.p){o.p=nullptr;}
    ~Obj(){if(p)Tcl_DecrRefCount(p);}
    Obj &operator=(const Obj &)=delete;
};
std::string text(Tcl_Obj *v) {int n;const char *p=Tcl_GetStringFromObj(v,&n);return std::string(p,static_cast<size_t>(n));}
Tcl_Obj *get(Tcl_Interp *ip,Tcl_Obj *d,const char *key) {
    Tcl_Obj *v=nullptr;if(column_field(ip,d,key,&v)!=TCL_OK||!v)throw std::runtime_error(std::string("Missing batch field: ")+key);return v;
}
void put(Tcl_Obj *d,const char *key,Tcl_Obj *v){Tcl_DictObjPut(nullptr,d,Tcl_NewStringObj(key,-1),v);}
Tcl_WideInt integer(Tcl_Interp *ip,Tcl_Obj *d,const char *key,Tcl_WideInt lo,Tcl_WideInt hi){
    Tcl_WideInt v;if(Tcl_GetWideIntFromObj(ip,get(ip,d,key),&v)!=TCL_OK||v<lo||v>hi)throw std::runtime_error(std::string("Invalid batch ")+key);return v;
}
std::vector<Tcl_Obj*> list(Tcl_Interp *ip,Tcl_Obj *v){int n;Tcl_Obj **p;if(Tcl_ListObjGetElements(ip,v,&n,&p)!=TCL_OK)throw std::runtime_error("Invalid batch list");if(!n)return {};return {p,p+n};}
Obj invoke(Tcl_Interp *ip,const char *command,Tcl_Obj *a,Tcl_Obj *b){
    Obj name(Tcl_NewStringObj(command,-1));Tcl_Obj *v[]={name.p,a,b};
    if(Tcl_EvalObjv(ip,3,v,TCL_EVAL_GLOBAL)!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(ip));
    return Obj(Tcl_GetObjResult(ip));
}
// Decode canonical typed scalar cells without converting integer identities to
// binary64. This is marshalling of an admitted block, never storage access.
Obj scalar(Tcl_Interp *ip,const numeric_column &c,size_t index){
    if(c.values)return Obj(c.values[index]);
    if(c.kind==4)return Obj(Tcl_NewIntObj(c.bytes[index]?1:0));
    if(c.kind==5||c.kind==6){
        uint64_t bits=0;for(size_t j=0;j<c.width;++j)bits|=uint64_t(c.bytes[index*c.width+(c.big?c.width-j-1:j)])<<(8*j);
        std::string word;
        if(c.kind==5)word=std::to_string(bits);
        else{if(c.width<8&&(bits&(UINT64_C(1)<<(8*c.width-1))))bits|=UINT64_MAX<<(8*c.width);int64_t value;std::memcpy(&value,&bits,8);word=std::to_string(value);}
        return Obj(Tcl_NewStringObj(word.data(),static_cast<int>(word.size())));
    }
    double value;if(numeric_column_value(ip,&c,index,&value)!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(ip));
    return Obj(std::isnan(value)?Tcl_NewStringObj("NaN",-1):Tcl_NewDoubleObj(value));
}
struct Projected {std::vector<Tcl_Obj*> cells;std::vector<Obj> owned;};
struct Spec {std::string id,dtype;explicit Spec(Tcl_Interp *ip,Tcl_Obj *d):id(text(get(ip,d,"variable_id"))),dtype(text(get(ip,d,"dtype"))){} };
struct Row {gx2d_point point;uint64_t source,order,continuity;};
struct Group {Obj key;std::vector<Row> rows;explicit Group(Tcl_Obj *v):key(v){} };
struct Batch {
    std::string x,y;std::vector<Spec> groups;std::unique_ptr<Spec> order,continuity;
    std::vector<Obj> filters;std::vector<std::string> filterIds;
    std::vector<std::unordered_map<std::string,bool>> filterCache;
    std::unordered_map<std::string,Obj> canonicalCache;
    std::unordered_map<std::string,size_t> lookup;std::vector<Group> partitions;
    uint64_t offset=0;size_t selected=0,cacheBytes=0,validatorCalls=0,filterCalls=0,capacityRows=0;
    size_t start,count,budget,aggregate,maxSeries;bool unlimited=false,finished=false,failed=false,busy=false;
    explicit Batch(Tcl_Interp *ip,Tcl_Obj *config):x(text(get(ip,config,"x_variable_id"))),y(text(get(ip,config,"y_variable_id"))){
        for(auto *v:list(ip,get(ip,config,"groups")))groups.emplace_back(ip,v);
        if(groups.size()>16)throw std::runtime_error("Batch has more than16 grouping variables");
        for(auto *v:list(ip,get(ip,config,"filters"))){filters.emplace_back(v);filterIds.push_back(text(get(ip,v,"filter_variable_id")));}
        if(filters.size()>64)throw std::runtime_error("Batch has more than64 filters");
        filterCache.resize(filters.size());
        auto *o=get(ip,config,"order");if(Tcl_GetCharLength(o))order=std::make_unique<Spec>(ip,o);
        if(order&&order->dtype=="string")throw std::runtime_error("Native batch currently requires a numeric ordering variable");
        auto *c=get(ip,config,"continuity");if(Tcl_GetCharLength(c))continuity=std::make_unique<Spec>(ip,c);
        start=static_cast<size_t>(integer(ip,config,"start",0,2000000));
        auto n=integer(ip,config,"count",-1,2000000);unlimited=n<0;count=unlimited?0:static_cast<size_t>(n);
        budget=static_cast<size_t>(integer(ip,config,"display_budget",6,4096));
        aggregate=static_cast<size_t>(integer(ip,config,"total_display_points",6,100000));
        maxSeries=static_cast<size_t>(integer(ip,config,"max_series",1,512));
    }
    Obj canonical(Tcl_Interp *ip,const Spec &spec,Tcl_Obj *value){
        if(spec.dtype=="string")return Obj(value);
        std::string key=spec.dtype;key+='\0';key+=text(value);
        auto it=canonicalCache.find(key);if(it!=canonicalCache.end())return it->second;
        Obj dtype(Tcl_NewStringObj(spec.dtype.data(),static_cast<int>(spec.dtype.size())));
        Obj result=invoke(ip,"::GX::graphSeriesCanonicalMember",dtype.p,value);++validatorCalls;
        size_t bytes=key.size()+text(result.p).size();
        if(cacheBytes+bytes<=2097152){cacheBytes+=bytes;canonicalCache.emplace(std::move(key),result);}
        return result;
    }
    bool matches(Tcl_Interp *ip,size_t index,Tcl_Obj *value){
        std::string key=text(value);auto &cache=filterCache[index];auto it=cache.find(key);if(it!=cache.end())return it->second;
        Obj result=invoke(ip,"::GX::GraphSelectionAPIv1::_matchesFilter",value,filters[index].p);++filterCalls;
        int accepted;if(Tcl_GetBooleanFromObj(ip,result.p,&accepted)!=TCL_OK)throw std::runtime_error("Invalid owner predicate result");
        if(cacheBytes+key.size()+1<=2097152){cacheBytes+=key.size()+1;cache.emplace(std::move(key),accepted!=0);}
        return accepted!=0;
    }
    uint64_t key(Tcl_Interp *ip,const Spec &spec,Tcl_Obj *value){
        Obj normalized=canonical(ip,spec,value);std::string word=text(normalized.p);uint64_t bits;
        if(spec.dtype.compare(0,4,"uint")==0||spec.dtype=="bool"){
            auto r=std::from_chars(word.data(),word.data()+word.size(),bits);
            if(r.ec!=std::errc()||r.ptr!=word.data()+word.size())throw std::runtime_error("Invalid exact unsigned batch key");return bits;
        }
        if(spec.dtype.compare(0,3,"int")==0){int64_t v;auto r=std::from_chars(word.data(),word.data()+word.size(),v);
            if(r.ec!=std::errc()||r.ptr!=word.data()+word.size())throw std::runtime_error("Invalid exact signed batch key");return static_cast<uint64_t>(v)^(UINT64_C(1)<<63);}
        double v;if(Tcl_GetDoubleFromObj(ip,normalized.p,&v)!=TCL_OK||!std::isfinite(v))throw std::runtime_error("Batch ordering needs finite values");
        std::memcpy(&bits,&v,8);return bits;
    }
    void push(Tcl_Interp *ip,Tcl_Obj *columns){
        if(failed)throw std::runtime_error("Native batch failed; destroy and reopen it");
        if(finished)throw std::runtime_error("Batch is already finished");
        numeric_column xc,yc;if(numeric_column_read(ip,get(ip,columns,x.c_str()),&xc)!=TCL_OK||numeric_column_read(ip,get(ip,columns,y.c_str()),&yc)!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(ip));
        if(xc.count>4096||xc.count!=yc.count||offset>uint64_t(INT64_MAX)-xc.count)throw std::runtime_error("Batch XY chunk count mismatch");
        std::unordered_map<std::string,Projected> values;
        auto project=[&](const std::string &id){
            if(values.count(id))return;
            numeric_column c;if(numeric_column_read(ip,get(ip,columns,id.c_str()),&c)!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(ip));
            if(c.count!=xc.count)throw std::runtime_error("Batch projection count mismatch");
            Projected p;p.cells.reserve(c.count);
            if(!c.values)p.owned.reserve(c.count);
            for(size_t j=0;j<c.count;++j){if(c.values)p.cells.push_back(c.values[j]);else{p.owned.push_back(scalar(ip,c,j));p.cells.push_back(p.owned.back().p);}}
            values.emplace(id,std::move(p));
        };
        for(const auto &g:groups)project(g.id);for(const auto &id:filterIds)project(id);if(order)project(order->id);if(continuity)project(continuity->id);
        for(size_t i=0;i<xc.count;++i){
            bool accepted=true;for(size_t j=0;j<filters.size();++j)if(!matches(ip,j,values.at(filterIds[j]).cells[i])){accepted=false;break;}if(!accepted)continue;
            Obj groupKey(Tcl_NewListObj(0,nullptr));
            for(const auto &g:groups){
                Obj item=canonical(ip,g,values.at(g.id).cells[i]);
                double value;const bool zero=g.dtype.compare(0,5,"float")==0&&Tcl_GetDoubleFromObj(ip,item.p,&value)==TCL_OK&&value==0;
                // Predicate numeric equality treats both signed zeros alike.
                Tcl_ListObjAppendElement(ip,groupKey.p,zero?Tcl_NewIntObj(0):item.p);
            }
            std::string encoded=text(groupKey.p);if(encoded.size()>4096)throw std::runtime_error("Grouping identity tuple exceeds4096 bytes");auto found=lookup.find(encoded);size_t index;
            if(found==lookup.end()){
                if(partitions.size()>=maxSeries)throw std::runtime_error("Visible series exceed the bounded batch limit; narrow filters");
                index=partitions.size();lookup.emplace(std::move(encoded),index);partitions.emplace_back(groupKey.p);
            }else index=found->second;
            if(selected>=2000000)throw std::runtime_error("Native batch exceeds2000000 selected rows; narrow source range or filters");
            Row row{};row.source=offset+i;
            if(numeric_column_value(ip,&xc,i,&row.point.x)!=TCL_OK||numeric_column_value(ip,&yc,i,&row.point.y)!=TCL_OK)throw std::runtime_error(Tcl_GetStringResult(ip));
            if(order)row.order=key(ip,*order,values.at(order->id).cells[i]);
            if(continuity){Obj c=canonical(ip,*continuity,values.at(continuity->id).cells[i]);std::string word=text(c.p);auto r=std::from_chars(word.data(),word.data()+word.size(),row.continuity);if(r.ec!=std::errc()||r.ptr!=word.data()+word.size())throw std::runtime_error("Continuity row identity must be nonnegative integer");}
            auto &rows=partitions[index].rows;
            if(rows.size()==rows.capacity()){
                const size_t next=std::min(size_t(2000000),std::max(size_t(1024),2*rows.capacity()));
                const size_t extra=next-rows.capacity();
                if(capacityRows+extra>4000000)throw std::runtime_error("Native batch row capacity budget exceeded");
                rows.reserve(next);capacityRows+=extra;
            }
            rows.push_back(row);++selected;
        }
        offset+=xc.count;
    }
    Obj finish(Tcl_Interp *ip){
        if(failed)throw std::runtime_error("Native batch failed; destroy and reopen it");
        if(finished)throw std::runtime_error("Batch is already finished");finished=true;
        if(partitions.empty())throw std::runtime_error("No rows match the selected filters");
        size_t per=std::min(budget,aggregate/partitions.size());if(per<6)throw std::runtime_error("Aggregate display budget cannot admit all visible series");
        Obj result(Tcl_NewListObj(0,nullptr));
        for(auto &group:partitions){
            auto &rows=group.rows;
            if(order){const bool floating=order->dtype.compare(0,5,"float")==0;std::sort(rows.begin(),rows.end(),[floating](const Row &a,const Row &b){if(floating){double x,y;std::memcpy(&x,&a.order,8);std::memcpy(&y,&b.order,8);if(x!=y)return x<y;}else if(a.order!=b.order)return a.order<b.order;return a.source<b.source;});}
            if(start>=rows.size())throw std::runtime_error("Curve Source batch range needs at least one row in every group");
            if(!unlimited&&count>rows.size()-start)throw std::runtime_error("Curve Source batch count exceeds its selected source window");
            size_t n=unlimited?rows.size()-start:count;if(!n)throw std::runtime_error("Curve Source batch range needs at least one row");
            std::unique_ptr<gx2d_display_accumulator,decltype(&gx2d_display_destroy)> accumulator(gx2d_display_begin(n,per,0),gx2d_display_destroy);
            if(!accumulator)throw std::runtime_error("Cannot allocate bounded native display accumulator");
            for(size_t j=0;j<n;++j){const auto &row=rows[start+j];if(continuity&&j&&(rows[start+j-1].continuity==UINT64_MAX||row.continuity!=rows[start+j-1].continuity+1))gx2d_display_mark_break(accumulator.get());auto code=gx2d_display_push_rows(accumulator.get(),j,&row.point,&row.source,1);if(code!=GX2D_OK)throw std::runtime_error(gx2d_status_text(code));}
            std::vector<gx2d_point> points(per);std::vector<uint64_t> sourceRows(per);std::vector<size_t> cuts(per);size_t actual,finite,breaks;gx2d_rect bounds;
            auto code=gx2d_display_result(accumulator.get(),points.data(),sourceRows.data(),per,&actual,&finite,&bounds);if(code==GX2D_NOT_FOUND)throw std::runtime_error("No finite X/Y pairs in a visible Curve Source group");if(code!=GX2D_OK)throw std::runtime_error(gx2d_status_text(code));
            if(gx2d_display_breaks(accumulator.get(),cuts.data(),per,&breaks)!=GX2D_OK)throw std::runtime_error("Cannot finish native batch continuity");
            Obj item(Tcl_NewDictObj()),xy(Tcl_NewListObj(0,nullptr)),mapping(Tcl_NewListObj(0,nullptr)),gaps(Tcl_NewListObj(0,nullptr));
            for(size_t j=0;j<actual;++j){Tcl_Obj *pair[]={Tcl_NewDoubleObj(points[j].x),Tcl_NewDoubleObj(points[j].y)};Tcl_ListObjAppendElement(ip,xy.p,Tcl_NewListObj(2,pair));Tcl_ListObjAppendElement(ip,mapping.p,Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(sourceRows[j])));}
            for(size_t j=0;j<breaks;++j)Tcl_ListObjAppendElement(ip,gaps.p,Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(cuts[j])));
            Tcl_Obj *box[]={Tcl_NewDoubleObj(bounds.x0),Tcl_NewDoubleObj(bounds.y0),Tcl_NewDoubleObj(bounds.x1),Tcl_NewDoubleObj(bounds.y1)};
            put(item.p,"group_key",group.key.p);put(item.p,"points",xy.p);put(item.p,"source_rows",mapping.p);put(item.p,"breaks",gaps.p);put(item.p,"full_bounds",Tcl_NewListObj(4,box));
            put(item.p,"row_count",Tcl_NewWideIntObj(n));put(item.p,"finite_rows",Tcl_NewWideIntObj(finite));put(item.p,"display_rows",Tcl_NewWideIntObj(actual));put(item.p,"display_budget",Tcl_NewWideIntObj(per));
            Tcl_ListObjAppendElement(ip,result.p,item.p);
        }
        return result;
    }
};
struct State {uint64_t serial=0;std::unordered_map<std::string,std::shared_ptr<Batch>> batches;};
int command(ClientData data,Tcl_Interp *ip,int objc,Tcl_Obj *const objv[]){
    auto &state=*static_cast<State*>(data);std::shared_ptr<Batch> active;
    try{
        if(objc<2)throw std::runtime_error("Expected native batch operation");std::string op=text(objv[1]);
        if(op=="begin"&&objc==3){if(state.batches.size()>=4)throw std::runtime_error("Native batch instance limit reached");auto batch=std::make_shared<Batch>(ip,objv[2]);std::string token="preview-batch#"+std::to_string(++state.serial);state.batches.emplace(token,std::move(batch));Tcl_SetObjResult(ip,Tcl_NewStringObj(token.c_str(),-1));return TCL_OK;}
        if(objc<3)throw std::runtime_error("Native batch needs owned token");auto found=state.batches.find(text(objv[2]));if(found==state.batches.end())throw std::runtime_error("Unknown or closed native batch");
        active=found->second;auto &batch=*active;
        if(batch.busy&&op!="inspect")return fail(ip,"Native batch is busy; reentrant mutation is forbidden");
        if(op=="destroy"&&objc==3){state.batches.erase(found);Tcl_ResetResult(ip);return TCL_OK;}
        if(op=="inspect"&&objc==3){Obj result(Tcl_NewDictObj());put(result.p,"input_rows",Tcl_NewWideIntObj(batch.offset));put(result.p,"selected_rows",Tcl_NewWideIntObj(batch.selected));put(result.p,"retained_row_capacity",Tcl_NewWideIntObj(batch.capacityRows));put(result.p,"series",Tcl_NewWideIntObj(batch.partitions.size()));put(result.p,"identity_validator_calls",Tcl_NewWideIntObj(batch.validatorCalls));put(result.p,"predicate_validator_calls",Tcl_NewWideIntObj(batch.filterCalls));put(result.p,"validation_cache_bytes",Tcl_NewWideIntObj(batch.cacheBytes));Tcl_SetObjResult(ip,result.p);return TCL_OK;}
        struct Busy {Batch &batch;explicit Busy(Batch &b):batch(b){batch.busy=true;}~Busy(){batch.busy=false;}} busy(batch);
        if(op=="push"&&objc==4){batch.push(ip,objv[3]);Tcl_ResetResult(ip);return TCL_OK;}
        if(op=="finish"&&objc==3){Obj result=batch.finish(ip);Tcl_SetObjResult(ip,result.p);return TCL_OK;}
        throw std::runtime_error("Unknown native batch operation or argument count");
    }catch(const std::exception &e){if(active)active->failed=true;return fail(ip,e.what());}
}
void dispose(ClientData data){delete static_cast<State*>(data);}
}
extern "C" int gx2d_preview_batch_v1_init(Tcl_Interp *ip){
    if(!Tcl_FindNamespace(ip,"::gx::native2d",nullptr,0)&&!Tcl_CreateNamespace(ip,"::gx::native2d",nullptr,nullptr))return TCL_ERROR;
    Tcl_CreateObjCommand(ip,"::gx::native2d::_preview_batch",command,new State,dispose);return TCL_OK;
}
