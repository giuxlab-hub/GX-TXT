// SPDX-License-Identifier: GPL-3.0-or-later
#include <tcl.h>
#include <algorithm>
#include <memory>
#include <vector>
#include "gx3de_projection_snapshot_v1.h"
namespace {
using namespace gx3de_projection_v1;
struct ObjectGuard {Tcl_Obj* p;explicit ObjectGuard(Tcl_Obj* v):p(v){Tcl_IncrRefCount(p);}~ObjectGuard(){Tcl_DecrRefCount(p);}};
std::string text(Tcl_Obj* value){int bytes=0;const auto* data=Tcl_GetStringFromObj(value,&bytes);return std::string(data,static_cast<size_t>(bytes));}
Tcl_Obj* field(Tcl_Interp* ip,Tcl_Obj* dictionary,const char* key,bool required=true){
    Tcl_Obj* value=nullptr;auto* name=Tcl_NewStringObj(key,-1);Tcl_IncrRefCount(name);
    const int code=Tcl_DictObjGet(ip,dictionary,name,&value);Tcl_DecrRefCount(name);
    if(code!=TCL_OK)throw std::runtime_error("Expected a projection dictionary");
    if(!value&&required)throw std::runtime_error(std::string("Missing projection field: ")+key);
    return value;
}
void put(Tcl_Interp* ip,Tcl_Obj* d,const char* key,Tcl_Obj* value){Tcl_DictObjPut(ip,d,Tcl_NewStringObj(key,-1),value);}
double number(Tcl_Interp* ip,Tcl_Obj* value){double result=0;if(!value||Tcl_GetDoubleFromObj(ip,value,&result)!=TCL_OK||!std::isfinite(result))throw std::runtime_error("Projection coordinates must be finite numbers");return result;}
uint64_t integer(Tcl_Interp* ip,Tcl_Obj* value){Tcl_WideInt n=0;if(Tcl_GetWideIntFromObj(ip,value,&n)!=TCL_OK||n<0)throw std::runtime_error("Projection dimensions/revisions must be nonnegative integers");return static_cast<uint64_t>(n);}
Vec vector(Tcl_Interp* ip,Tcl_Obj* value){int n=0;Tcl_Obj** items=nullptr;if(!value||Tcl_ListObjGetElements(ip,value,&n,&items)!=TCL_OK||n!=3)throw std::runtime_error("Projection vectors require three coordinates");return {number(ip,items[0]),number(ip,items[1]),number(ip,items[2])};}
Tcl_Obj* vectorObject(Vec v){Tcl_Obj* items[]={Tcl_NewDoubleObj(v.x),Tcl_NewDoubleObj(v.y),Tcl_NewDoubleObj(v.z)};return Tcl_NewListObj(3,items);}
Snapshot parseSnapshot(Tcl_Interp* ip,Tcl_Obj* value){
    if(std::string(Tcl_GetString(field(ip,value,"schema")))!="gxtxt.native3d.projection.v1")throw std::runtime_error("Unknown native projection snapshot schema");
    Snapshot s;s.frameId=text(field(ip,value,"frame_id"));s.revision=integer(ip,field(ip,value,"revision"));
    auto w=integer(ip,field(ip,value,"width")),h=integer(ip,field(ip,value,"height"));if(w>16384||h>16384)throw std::runtime_error("Projection viewport exceeds bounds");s.width=static_cast<uint32_t>(w);s.height=static_cast<uint32_t>(h);
    int ortho=0;if(Tcl_GetBooleanFromObj(ip,field(ip,value,"orthographic"),&ortho)!=TCL_OK)throw std::runtime_error("Projection orthographic state must be boolean");s.orthographic=ortho;
    s.camera=vector(ip,field(ip,value,"camera_origin"));s.origin1=vector(ip,field(ip,value,"depth1_origin"));s.dx1=vector(ip,field(ip,value,"depth1_dx"));s.dy1=vector(ip,field(ip,value,"depth1_dy"));s.origin2=vector(ip,field(ip,value,"depth2_origin"));s.dx2=vector(ip,field(ip,value,"depth2_dx"));s.dy2=vector(ip,field(ip,value,"depth2_dy"));return s;
}
Plane parsePlane(Tcl_Interp* ip,Tcl_Obj* value){return {vector(ip,field(ip,value,"origin")),vector(ip,field(ip,value,"u_axis")),vector(ip,field(ip,value,"v_axis")),vector(ip,field(ip,value,"normal"))};}
void expected(Tcl_Interp* ip,const Snapshot& s,Tcl_Obj* value){
    Tcl_DictSearch search;Tcl_Obj *key,*item;int done;
    if(Tcl_DictObjFirst(ip,value,&search,&key,&item,&done)!=TCL_OK)throw std::runtime_error("Expected frame guard dictionary");
    try {for(;!done;Tcl_DictObjNext(&search,&key,&item,&done)){
        std::string name=Tcl_GetString(key);bool equal=false;
        if(name=="frame_id")equal=s.frameId==text(item);
        else if(name=="revision")equal=s.revision==integer(ip,item);
        else if(name=="width")equal=s.width==integer(ip,item);
        else if(name=="height")equal=s.height==integer(ip,item);
        else throw std::runtime_error("Unknown projection frame guard");
        if(!equal)throw std::runtime_error("STALE_PROJECTION: frame identity or dimensions changed");
    }}catch(...){Tcl_DictObjDone(&search);throw;}Tcl_DictObjDone(&search);
}
int failure(Tcl_Interp* ip,const std::exception& e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));Tcl_SetErrorCode(ip,"GX","NATIVE3D",std::string(e.what()).find("STALE_PROJECTION:")==0?"STALE_PROJECTION":"PROJECTION_ARGUMENT",nullptr);return TCL_ERROR;}
void dispose(ClientData data){delete static_cast<Mapping*>(data);}
int instance(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
    auto& mapping=*static_cast<Mapping*>(data);const auto& s=mapping.snapshot();
    try {
        if(argc<2)throw std::runtime_error("Use info, map, scale or dispose");
        std::string operation=Tcl_GetString(args[1]);
        if(operation=="dispose"&&argc==2){Tcl_DeleteCommand(ip,Tcl_GetString(args[0]));return TCL_OK;}
        auto* result=Tcl_NewDictObj();ObjectGuard resultOwner(result);
        put(ip,result,"frame_id",Tcl_NewStringObj(s.frameId.c_str(),-1));put(ip,result,"revision",Tcl_NewWideIntObj(s.revision));put(ip,result,"width",Tcl_NewIntObj(s.width));put(ip,result,"height",Tcl_NewIntObj(s.height));
        if(operation=="info"&&argc==2){put(ip,result,"orthographic",Tcl_NewBooleanObj(s.orthographic));auto* plane=Tcl_NewDictObj();const auto& p=mapping.plane();put(ip,plane,"origin",vectorObject(p.origin));put(ip,plane,"u_axis",vectorObject(p.u));put(ip,plane,"v_axis",vectorObject(p.v));put(ip,plane,"normal",vectorObject(p.normal));put(ip,result,"plane",plane);Tcl_SetObjResult(ip,result);return TCL_OK;}
        if(operation=="scale"&&argc>=2&&argc<=4){
            std::array<double,4> rectangle{0,0,double(s.width-1),double(s.height-1)};
            if(argc>=3){int n=0;Tcl_Obj** values=nullptr;if(Tcl_ListObjGetElements(ip,args[2],&n,&values)!=TCL_OK||n!=4)throw std::runtime_error("Scale requires screen bounds xmin ymin xmax ymax");for(int i=0;i<4;++i)rectangle[i]=number(ip,values[i]);}
            if(rectangle[0]>=rectangle[2]||rectangle[1]>=rectangle[3])throw std::runtime_error("Scale screen bounds must have positive area");
            if(argc==4)expected(ip,s,args[3]);
            auto scale=mapping.scale(rectangle);
            put(ip,result,"valid",Tcl_NewBooleanObj(scale.valid));put(ip,result,"reason",Tcl_NewStringObj(scale.reason,-1));put(ip,result,"maximum_pixels_per_unit",Tcl_NewDoubleObj(scale.valid?scale.maximumPixelsPerUnit:0));put(ip,result,"minimum_forward_depth",Tcl_NewDoubleObj(scale.valid?scale.minimumDepth:0));put(ip,result,"domain",Tcl_NewStringObj("visible_convex_plane_quad",-1));
            auto* polygon=Tcl_NewListObj(0,nullptr);auto* bounds=Tcl_NewListObj(0,nullptr);
            if(scale.valid){for(const auto& p:scale.polygon){Tcl_Obj* xy[]={Tcl_NewDoubleObj(p.x),Tcl_NewDoubleObj(p.y)};Tcl_ListObjAppendElement(ip,polygon,Tcl_NewListObj(2,xy));}for(double value:scale.bounds)Tcl_ListObjAppendElement(ip,bounds,Tcl_NewDoubleObj(value));}
            put(ip,result,"local_polygon",polygon);put(ip,result,"local_bounds",bounds);Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(operation!="map"||(argc!=4&&argc!=5))throw std::runtime_error("Use map to_screen|to_plane pointRows ?expectedFrame?");
        std::string direction=Tcl_GetString(args[2]);if(direction!="to_screen"&&direction!="to_plane")throw std::runtime_error("Unknown planar projection direction");
        if(argc==5)expected(ip,s,args[4]);
        int count=0;Tcl_Obj** rows=nullptr;if(Tcl_ListObjGetElements(ip,args[3],&count,&rows)!=TCL_OK||count>262144)throw std::runtime_error("Projection batches require at most262144 points");
        std::vector<std::array<double,2>> input;input.reserve(count);
        for(int i=0;i<count;++i){int n=0;Tcl_Obj** xy=nullptr;if(Tcl_ListObjGetElements(ip,rows[i],&n,&xy)!=TCL_OK||n!=2)throw std::runtime_error("Planar and screen points require two coordinates");input.push_back({number(ip,xy[0]),number(ip,xy[1])});}
        auto* points=Tcl_NewListObj(0,nullptr);auto* valid=Tcl_NewListObj(0,nullptr);auto* depths=Tcl_NewListObj(0,nullptr);auto* reasons=Tcl_NewListObj(0,nullptr);auto* outside=Tcl_NewListObj(0,nullptr);
        for(auto xy:input){auto p=direction=="to_screen"?mapping.project(xy[0],xy[1]):mapping.unproject(xy[0],xy[1]);Tcl_Obj* point=Tcl_NewListObj(0,nullptr);if(p.valid){Tcl_ListObjAppendElement(ip,point,Tcl_NewDoubleObj(p.x));Tcl_ListObjAppendElement(ip,point,Tcl_NewDoubleObj(p.y));}
            Tcl_ListObjAppendElement(ip,points,point);Tcl_ListObjAppendElement(ip,valid,Tcl_NewBooleanObj(p.valid));Tcl_ListObjAppendElement(ip,depths,Tcl_NewDoubleObj(std::isfinite(p.depth)?p.depth:0));Tcl_ListObjAppendElement(ip,reasons,Tcl_NewStringObj(p.reason,-1));
            const auto screen=direction=="to_screen"?std::array<double,2>{p.x,p.y}:xy;Tcl_ListObjAppendElement(ip,outside,Tcl_NewBooleanObj(screen[0]<0||screen[1]<0||screen[0]>=s.width||screen[1]>=s.height));}
        put(ip,result,"points",points);put(ip,result,"valid",valid);put(ip,result,"depth",depths);put(ip,result,"reason",reasons);put(ip,result,"outside",outside);Tcl_SetObjResult(ip,result);return TCL_OK;
    }catch(const std::exception& e){return failure(ip,e);}
}
int create(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
    try {
        if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"snapshot normalizedPlane");return TCL_ERROR;}
        auto mapping=std::make_unique<Mapping>(parseSnapshot(ip,args[1]),parsePlane(ip,args[2]));
        const auto serial=++*static_cast<uint64_t*>(data);const auto name="::GX3DEProjection::mapping"+std::to_string(serial);
        Tcl_CreateObjCommand(ip,name.c_str(),instance,mapping.release(),dispose);Tcl_SetObjResult(ip,Tcl_NewStringObj(name.c_str(),-1));return TCL_OK;
    }catch(const std::exception& e){return failure(ip,e);}
}
void release(ClientData data,Tcl_Interp*){delete static_cast<uint64_t*>(data);}
}
extern "C" int Gx3deprojection_Init(Tcl_Interp* ip){
    if(Tcl_InitStubs(ip,"8.6",0)==nullptr)return TCL_ERROR;
    if(Tcl_IsSafe(ip)){Tcl_SetObjResult(ip,Tcl_NewStringObj("Native projection mapping is a trusted CORE host facility",-1));return TCL_ERROR;}
    Tcl_CreateNamespace(ip,"::GX3DEProjection",nullptr,nullptr);auto* serial=new uint64_t(0);Tcl_SetAssocData(ip,"GX3DEProjection",release,serial);
    Tcl_CreateObjCommand(ip,"::GX3DEProjection::create",create,serial,nullptr);Tcl_PkgProvide(ip,"Gx3deprojection","1.0");return TCL_OK;
}
