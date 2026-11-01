/* SPDX-License-Identifier: GPL-3.0-or-later
 * GUI-host CAD context over existing authoritative Native2D C operations.
 * No mathematical geometry, scientific object registry or competing transaction
 * engine. Scene leases, one native semantic selection set, explicit plan/apply
 * admission boundary, and deterministic commit/cancel are the responsibilities.
 */
#include "gx2d_cad_controller_v1.h"
#include <algorithm>
#include <cmath>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>
namespace {
struct Error {};
struct Obj {Tcl_Obj *p;explicit Obj(Tcl_Obj *v):p(v){Tcl_IncrRefCount(p);}~Obj(){Tcl_DecrRefCount(p);}Obj(const Obj &v):Obj(v.p){}Obj &operator=(const Obj &)=delete;};
Obj word(const char *s){return Obj(Tcl_NewStringObj(s,-1));}
void fail(Tcl_Interp *ip,const char *s){Tcl_SetObjResult(ip,Tcl_NewStringObj(s,-1));throw Error{};}
void status(Tcl_Interp *ip,gx2d_status code){if(code!=GX2D_OK)fail(ip,gx2d_status_text(code));}
std::vector<Tcl_Obj *> list(Tcl_Interp *ip,Tcl_Obj *o){int n;Tcl_Obj **v;if(Tcl_ListObjGetElements(ip,o,&n,&v)!=TCL_OK)throw Error{};return {v,v+n};}
Tcl_Obj *get(Tcl_Interp *ip,Tcl_Obj *d,const char *k){auto key=word(k);Tcl_Obj *v;if(Tcl_DictObjGet(ip,d,key.p,&v)!=TCL_OK||!v)fail(ip,"Missing CAD field");return v;}
void put(Tcl_Obj *d,const char *k,Tcl_Obj *v){auto key=word(k);Tcl_DictObjPut(nullptr,d,key.p,v);}
uint64_t integer(Tcl_Interp *ip,Tcl_Obj *o){Tcl_WideInt n;if(Tcl_GetWideIntFromObj(ip,o,&n)!=TCL_OK||n<0)fail(ip,"Expected nonnegative native identity/index");return (uint64_t)n;}
double number(Tcl_Interp *ip,Tcl_Obj *o){double n;if(Tcl_GetDoubleFromObj(ip,o,&n)!=TCL_OK||!std::isfinite(n))fail(ip,"Expected finite CAD coordinate");return n;}
gx2d_point point(Tcl_Interp *ip,Tcl_Obj *o){auto p=list(ip,o);if(p.size()!=2)fail(ip,"Expected a CAD XY point");return {number(ip,p[0]),number(ip,p[1])};}
Tcl_Obj *xy(gx2d_point p){Tcl_Obj *v[]={Tcl_NewDoubleObj(p.x),Tcl_NewDoubleObj(p.y)};return Tcl_NewListObj(2,v);}
struct Cad {
 Tcl_Interp *ip;gx2d_sprite_source_v1 *source;uint64_t sceneId;gx2d_id selection=0;bool ownsSelection=false,gesture=false,nativeDrag=false,pointsGesture=false;
 Tcl_ObjCmdProc *backend;ClientData backendData;Tcl_Command command=nullptr;std::string name,handle;std::unique_ptr<Obj> start,targets,proposal,oldPivot,oldGizmo;gx2d_point pointStart{},pointPivot{};
 gx2d_scene *scientific(){auto s=gx2d_sprite_source_v1_scene(source);if(!s)fail(ip,"CAD scientific scene has closed");return s;}
 Obj call(const char *op,const std::vector<Tcl_Obj *> &args={}){scientific();auto c=word("::gx::native2d::core"),operation=word(op);Obj scene(Tcl_NewWideIntObj(sceneId));std::vector<Tcl_Obj *> values{c.p,operation.p,scene.p};values.insert(values.end(),args.begin(),args.end());Tcl_ResetResult(ip);if(backend(backendData,ip,(int)values.size(),values.data())!=TCL_OK)throw Error{};return Obj(Tcl_GetObjResult(ip));}
 void checkSelection(){if(selection){size_t count;auto code=gx2d_selection_set_get(scientific(),selection,nullptr,0,&count);if(code==GX2D_NOT_FOUND){selection=0;ownsSelection=false;}else status(ip,code);}}
 Obj members(){checkSelection();if(!selection){Obj out(Tcl_NewDictObj());put(out.p,"id",Tcl_NewWideIntObj(0));put(out.p,"members",Tcl_NewListObj(0,nullptr));return out;}Obj id(Tcl_NewWideIntObj(selection));return call("selection_set_get",{id.p});}
 Obj reference(Tcl_Obj *object,Tcl_Obj *kind,Tcl_Obj *index){auto k=std::string(Tcl_GetString(kind));uint64_t n=integer(ip,index);if(k=="segment"&&n<1000000000ULL)return call("interaction_reference",{object,kind,index});if(k=="object"){auto entity=word("object");Obj zero(Tcl_NewIntObj(0));return call("interaction_reference",{object,entity.p,zero.p});}return call("interaction_reference_index",{object,index});}
 void cancel(){if(!gesture)return;if(source&&gx2d_sprite_source_v1_scene(source)){
  if(nativeDrag){int active;status(ip,gx2d_drag_is_active(scientific(),&active));if(active)status(ip,gx2d_drag_cancel(scientific()));}
  else if(oldPivot&&oldGizmo){auto mode=get(ip,oldPivot->p,"mode");if(std::string(Tcl_GetString(mode))=="custom")call("pivot",{mode,get(ip,oldPivot->p,"point")});else call("pivot",{mode});call("gizmo",{oldGizmo->p});}
 }gesture=nativeDrag=pointsGesture=false;proposal.reset();}
 ~Cad(){try{cancel();if(source&&gx2d_sprite_source_v1_scene(source)&&selection&&ownsSelection)gx2d_selection_set_delete(scientific(),selection);}catch(...){Tcl_ResetResult(ip);}if(source)gx2d_sprite_source_v1_unlisten(source,this);}
};
void closed(void *value){auto c=(Cad *)value;auto source=c->source;c->source=nullptr;c->selection=0;c->ownsSelection=false;c->gesture=c->nativeDrag=false;c->proposal.reset();gx2d_sprite_source_v1_unlisten(source,c);}
void deleted(ClientData p){delete (Cad *)p;}
Obj snapshot(Cad *c){
 auto ip=c->ip;auto observed=c->members();Obj out(Tcl_DuplicateObj(observed.p));Obj references(Tcl_NewListObj(0,nullptr)),objects(Tcl_NewListObj(0,nullptr));std::set<gx2d_id> ids;
 for(auto member:list(ip,get(ip,out.p,"members"))){if(!integer(ip,get(ip,member,"valid")))continue;auto native=get(ip,member,"id"),kind=get(ip,member,"kind"),index=get(ip,member,"index");std::string k=Tcl_GetString(kind);
  if(k=="fragment"){auto f=c->call("fragment_get",{native});ids.insert(integer(ip,get(ip,f.p,"parent")));continue;}
  gx2d_style style;status(ip,gx2d_get_style(c->scientific(),integer(ip,native),&style));if(k!="object"&&(!style.visible||!style.selectable))continue;
  ids.insert(integer(ip,native));auto reference=c->reference(native,kind,index);Obj copy(Tcl_DuplicateObj(reference.p));put(copy.p,"semantic_kind",kind);Tcl_ListObjAppendElement(ip,references.p,copy.p);
 }
 for(auto id:ids)Tcl_ListObjAppendElement(ip,objects.p,Tcl_NewWideIntObj(id));put(out.p,"references",references.p);put(out.p,"objects",objects.p);return out;
}
int dispatch(ClientData data,Tcl_Interp *ip,int n,Tcl_Obj *const a[]){
 auto c=(Cad *)data;
 try {
  if(n==2&&std::string(Tcl_GetString(a[1]))=="dispose"){Tcl_DeleteCommandFromToken(ip,c->command);return TCL_OK;}
  if(n==2&&std::string(Tcl_GetString(a[1]))=="state"){Obj out(Tcl_NewDictObj());put(out.p,"api_id",Tcl_NewStringObj("NATIVE2D_API_v1",-1));put(out.p,"alive",Tcl_NewBooleanObj(c->source&&gx2d_sprite_source_v1_scene(c->source)));put(out.p,"scene",Tcl_NewWideIntObj(c->sceneId));put(out.p,"selection",Tcl_NewWideIntObj(c->selection));put(out.p,"gesture",Tcl_NewBooleanObj(c->gesture));put(out.p,"native_drag",Tcl_NewBooleanObj(c->nativeDrag));Tcl_SetObjResult(ip,out.p);return TCL_OK;}
  c->scientific();if(n<3)fail(ip,"CAD needs selection, object, component, relationship, control or gesture operation");std::string family=Tcl_GetString(a[1]),op=Tcl_GetString(a[2]);std::unique_ptr<Obj> result;
  auto run=[&](const char *name,int first=3){std::vector<Tcl_Obj *> args(a+first,a+n);result.reset(new Obj(c->call(name,args)));};
  if(family=="selection"){
   if(op=="get"&&n==3)result.reset(new Obj(c->members()));
   else if(op=="snapshot"&&n==3)result.reset(new Obj(snapshot(c)));
   else if(op=="adopt"&&n==4){auto selected=integer(ip,a[3]);if(selected!=c->selection){if(c->selection&&c->ownsSelection)gx2d_selection_set_delete(c->scientific(),c->selection);c->selection=selected;c->ownsSelection=false;}c->checkSelection();}
   else if((op=="apply"||op=="restore")&&(n==4||n==5)){c->checkSelection();Obj id(Tcl_NewWideIntObj(c->selection));auto mode=word(n==5?Tcl_GetString(a[4]):"replace");bool wasEmpty=!c->selection;auto r=c->call(op=="apply"?"selection_set_apply":"selection_set_restore",{id.p,a[3],mode.p});c->selection=integer(ip,r.p);if(wasEmpty&&c->selection)c->ownsSelection=true;result.reset(new Obj(r));}
   else if(op=="reference"&&n==6)result.reset(new Obj(c->reference(a[3],a[4],a[5])));
   else if(op=="pick"&&(n==6||n==7)){auto member=c->call("selection_pick",{a[3],a[4],a[5],n==7?a[6]:word("detail").p});int size;if(Tcl_DictObjSize(ip,member.p,&size)!=TCL_OK)throw Error{};if(size){auto ref=c->reference(get(ip,member.p,"id"),get(ip,member.p,"kind"),get(ip,member.p,"index"));result.reset(new Obj(Tcl_DuplicateObj(ref.p)));put(result->p,"semantic_kind",get(ip,member.p,"kind"));}else result.reset(new Obj(Tcl_NewDictObj()));}
   else if(op=="region"&&(n==6||n==7))run("selection_region");
   else fail(ip,"Invalid CAD selection operation");
  } else if(family=="object"){
   static const std::map<std::string,const char *> operations{{"create","sketch_create"},{"definition","sketch_definition"},{"controls","interaction_controls"},{"bounds","bounds"},{"style","object_style"},{"delete","delete"},{"transform","affine"},{"join","composition_create"},{"separate","composition_explode"},{"split_path","path_split"},{"split_composition","composition_split"},{"retarget","composition_retarget"},{"direction","direction_marker"}};
   auto found=operations.find(op);if(found==operations.end())fail(ip,"Invalid CAD object operation");run(found->second);
  } else if(family=="component"){
   if(op=="hit"&&n==6){auto p=point(ip,a[4]);double tolerance=number(ip,a[5]);Obj out(Tcl_NewListObj(0,nullptr));bool found=false;
    for(auto object:list(ip,a[3])){auto id=integer(ip,object);gx2d_style style;status(ip,gx2d_get_style(c->scientific(),id,&style));if(!style.visible)continue;if(style.layer){gx2d_layer_style layer;status(ip,gx2d_get_layer(c->scientific(),style.layer,&layer));if(!layer.visible)continue;}gx2d_sketch_definition definition{};if(gx2d_sketch_get_definition(c->scientific(),id,&definition)!=GX2D_OK||(definition.family!=GX2D_SKETCH_COMPOUND&&definition.family!=GX2D_SKETCH_COMPOSITE_PATH))continue;
     size_t count;status(ip,gx2d_composition_states(c->scientific(),id,nullptr,0,&count));std::vector<gx2d_part_state> parts(count);status(ip,gx2d_composition_states(c->scientific(),id,parts.data(),count,&count));for(auto &part:parts){if(!part.direction.visible)continue;int hit;status(ip,gx2d_part_direction_hit(c->scientific(),id,part.part_id,p,tolerance,&hit));if(hit){Tcl_ListObjAppendElement(ip,out.p,object);Tcl_ListObjAppendElement(ip,out.p,Tcl_NewWideIntObj(part.part_id));found=true;break;}}if(found)break;
    }result.reset(new Obj(out));
   }else{static const std::map<std::string,const char *> operations{{"list","composition_states"},{"pick","part_pick"},{"direction","part_direction"},{"place","part_marker_place"},{"render","part_render"},{"marker","part_marker_render"}};auto found=operations.find(op);if(found==operations.end())fail(ip,"Invalid CAD component operation");run(found->second);}
  } else if(family=="relationship"){
   static const std::map<std::string,const char *> operations{{"options","interaction_constraints"},{"apply","interaction_constraint_apply"},{"create","constraint_create"},{"get","constraint_get"},{"list","constraint_list"},{"update","constraint_update"},{"enable","constraint_enable"},{"remove","constraint_delete"},{"join","constraint_join"},{"dimension_infer","sketch_dimension_infer"},{"dimension_preview","sketch_dimension_preview"},{"dimension_apply","sketch_dimension_apply"},{"dimension_geometry","sketch_dimension_geometry"},{"state","sketch_relationship"},{"location","interaction_constraint_location"}};auto found=operations.find(op);if(found==operations.end())fail(ip,"Invalid CAD relationship operation");run(found->second);
  } else if(family=="control"){
   static const std::map<std::string,const char *> operations{{"inspect","interaction_controls"},{"resolve","interaction_resolve"},{"preview","interaction_edit_definition"},{"edit","interaction_edit"},{"point_index","interaction_point_index"}};auto found=operations.find(op);if(found==operations.end())fail(ip,"Invalid CAD control operation");run(found->second);
  } else if(family=="gesture"){
   if(op=="cancel"&&n==3)c->cancel();
   else if((op=="begin"&&n==6)||(op=="begin_points"&&n==5)){
    if(c->gesture)fail(ip,"Finish or cancel this CAD gesture first");int active;status(ip,gx2d_drag_is_active(c->scientific(),&active));if(active)fail(ip,"Another native drag owns the scientific scene");
    c->pointsGesture=op=="begin_points";c->handle=c->pointsGesture?"points":Tcl_GetString(a[3]);
    if(!c->pointsGesture&&c->handle!="x"&&c->handle!="y"&&c->handle!="free"&&c->handle!="rotate"&&c->handle!="pivot"&&c->handle!="mirror_a"&&c->handle!="mirror_b")fail(ip,"Unsupported CAD gizmo handle");
    c->start.reset(new Obj(a[c->pointsGesture?3:4]));point(ip,c->start->p);c->proposal.reset();
    c->oldPivot.reset(new Obj(c->call("pivot")));c->oldGizmo.reset(new Obj(c->call("gizmo")));
    if(c->pointsGesture){c->pointPivot=point(ip,a[4]);auto p=c->call("world",{a[3]});c->pointStart=point(ip,p.p);}
    else {list(ip,a[5]);c->targets.reset(new Obj(a[5]));}
    c->nativeDrag=c->pointsGesture||(c->handle!="pivot"&&c->handle!="mirror_a"&&c->handle!="mirror_b");if(c->nativeDrag)status(ip,gx2d_drag_begin(c->scientific()));c->gesture=true;
   }else if(op=="plan"&&(n==4||n==5)){
    if(!c->gesture)fail(ip,"Begin a CAD gesture first");point(ip,a[3]);Obj delta(Tcl_NewDictObj());
    if(c->pointsGesture){auto p=c->call("world",{a[3]});auto now=point(ip,p.p);put(delta.p,"pivot",xy(c->pointPivot));put(delta.p,"translation",xy({now.x-c->pointStart.x,now.y-c->pointStart.y}));}
    else {auto handle=word(c->handle.c_str());auto computed=c->call("gizmo_parameters",{handle.p,c->start->p,a[3]});// Reuse the established C adapter result schema.
     for(auto key:{"pivot","translation","world_point","radians"})put(delta.p,key,get(ip,computed.p,key));}
    if(c->pointsGesture||c->handle=="x"||c->handle=="y"||c->handle=="free"){
     auto pivot=get(ip,delta.p,"pivot");Obj translation(get(ip,delta.p,"translation"));gx2d_grid grid;status(ip,gx2d_grid_get(c->scientific(),&grid));if(grid.enabled&&grid.snap_enabled){Obj axes(Tcl_NewIntObj(3));auto snapped=c->call("grid_snap_delta",{pivot,translation.p,axes.p});put(delta.p,"translation",snapped.p);}
     int objectSnap=0;if(n==5&&Tcl_GetBooleanFromObj(ip,a[4],&objectSnap)!=TCL_OK)throw Error{};
     if(objectSnap&&!c->pointsGesture){auto h=word(c->handle.c_str());Obj radius(Tcl_NewDoubleObj(8)),endpoints(Tcl_NewBooleanObj(0));auto snapped=c->call("gizmo_snap_translation",{h.p,pivot,get(ip,delta.p,"translation"),radius.p,c->targets->p,endpoints.p});if(integer(ip,get(ip,snapped.p,"snapped"))){put(delta.p,"translation",get(ip,snapped.p,"translation"));put(delta.p,"snap_target",get(ip,snapped.p,"target"));}}
    }
    c->proposal.reset(new Obj(delta));result.reset(new Obj(delta));
   }else if(op=="apply"&&n==3){
    if(!c->gesture||!c->proposal)fail(ip,"Plan a current CAD gesture before apply");auto d=c->proposal->p;
    if(c->handle=="pivot"){auto mode=word("custom");c->call("pivot",{mode.p,get(ip,d,"world_point")});}
    else if(c->handle=="mirror_a"||c->handle=="mirror_b"){Obj spec(Tcl_NewDictObj());put(spec.p,c->handle.c_str(),get(ip,d,"world_point"));c->call("gizmo",{spec.p});}
    else if(c->handle=="rotate")status(ip,gx2d_drag_rotate(c->scientific(),point(ip,get(ip,d,"pivot")),number(ip,get(ip,d,"radians"))));
    else {auto p=point(ip,get(ip,d,"translation"));status(ip,gx2d_drag_translate(c->scientific(),p.x,p.y));}
   }else if(op=="commit"&&n==3){
    if(!c->gesture)fail(ip,"No owned CAD gesture");if(c->nativeDrag){auto code=gx2d_drag_commit(c->scientific());if(code!=GX2D_OK){c->cancel();status(ip,code);}}c->gesture=c->nativeDrag=c->pointsGesture=false;c->proposal.reset();
   }else fail(ip,"Invalid CAD gesture operation");
  }else fail(ip,"Unknown CAD operation family");
  if(result)Tcl_SetObjResult(ip,result->p);else Tcl_ResetResult(ip);return TCL_OK;
 }catch(const Error &){return TCL_ERROR;}catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
}
}
extern "C" int gx2d_cad_controller_v1_create(Tcl_Interp *ip,gx2d_sprite_source_v1 *source,uint64_t scene,gx2d_id selection,Tcl_ObjCmdProc *backend,ClientData backendData){
 try{static uint64_t serial=0;auto c=new Cad{ip,source,scene,selection,false,false,false,false,backend,backendData};c->name="::gx::native2d::cad"+std::to_string(++serial);gx2d_sprite_source_v1_listen(source,c,closed);c->command=Tcl_CreateObjCommand(ip,c->name.c_str(),dispatch,c,deleted);Tcl_SetObjResult(ip,Tcl_NewStringObj(c->name.c_str(),-1));return TCL_OK;}catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
}
