// SPDX-License-Identifier: GPL-3.0-or-later
// Shared isolated host marshaling. Scientific operations use public GX3DE APIs.
// OCCT writers emit progress/statistics on stdout. Keep those diagnostics on
// stderr: stdout belongs exclusively to the isolated host's reply protocol.
class CadDiagnosticOutput {
    int saved;
public:
    CadDiagnosticOutput() {
        std::cout.flush();std::fflush(stdout);
#ifdef _WIN32
        saved=_dup(_fileno(stdout));
        if(saved<0||_dup2(_fileno(stderr),_fileno(stdout))<0)throw std::runtime_error("Cannot isolate CAD diagnostics from worker replies");
#else
        saved=dup(STDOUT_FILENO);
        if(saved<0||dup2(STDERR_FILENO,STDOUT_FILENO)<0)throw std::runtime_error("Cannot isolate CAD diagnostics from worker replies");
#endif
    }
    ~CadDiagnosticOutput() {
        std::cout.flush();std::fflush(stdout);
#ifdef _WIN32
        _dup2(saved,_fileno(stdout));_close(saved);
#else
        dup2(saved,STDOUT_FILENO);::close(saved);
#endif
    }
};
std::vector<Tcl_Obj*> cadList(Tcl_Interp* ip,Tcl_Obj* value) {
    int n=0;Tcl_Obj** items=nullptr;
    if(!value||Tcl_ListObjGetElements(ip,value,&n,&items)!=TCL_OK)throw std::runtime_error("Invalid Native3D argument list");
    return std::vector<Tcl_Obj*>(items,items+n);
}
gx3de_vec3 cadVector(Tcl_Interp* ip,Tcl_Obj* value,const char* label) {
    auto entries=cadList(ip,value);
    if(entries.size()==1)return vec(str(value),label);
    if(entries.size()!=3)throw std::runtime_error(std::string(label)+" needs three finite components");
    return {number(str(entries[0]),label),number(str(entries[1]),label),number(str(entries[2]),label)};
}
double cadDoubleLE(std::ifstream& input) {
    unsigned char bytes[8];input.read(reinterpret_cast<char*>(bytes),8);
    if(!input)throw std::runtime_error("Incomplete owned Native3D profile coordinates");
    uint64_t bits=0;for(unsigned i=0;i<8;++i)bits|=uint64_t(bytes[i])<<(8*i);
    double out;std::memcpy(&out,&bits,8);
    if(!std::isfinite(out))throw std::runtime_error("Native3D profile coordinates must be finite");
    return out;
}
gx3de_object* cadObject(State& state,const std::string& id) {
    auto found=state.cadObjects.find(id);
    if(found==state.cadObjects.end())throw std::runtime_error("Unknown or stale Native3D object token");
    return found->second;
}
gx3de_profile* cadProfile(State& state,const std::string& id) {
    auto found=state.cadProfiles.find(id);
    if(found==state.cadProfiles.end())throw std::runtime_error("Unknown or stale Native3D profile token");
    return found->second;
}
Tcl_Obj* cadProfileInfo(Tcl_Interp* ip,gx3de_profile* profile,const std::string& id) {
    uint64_t count=0,total=0;check(gx3de_profile_contour_count(profile,&count),"read captured profile contours");
    for(uint64_t i=0;i<count;++i){gx3de_contour_info info{};info.struct_size=sizeof info;check(gx3de_profile_contour_info(profile,i,&info),"read profile contour size");total+=info.point_count;}
    gx3de_vec3 origin,normal,u;check(gx3de_profile_frame_get(profile,&origin,&normal,&u),"read captured profile frame");
    Tcl_Obj* out=Tcl_NewDictObj();Tcl_Obj* frame=Tcl_NewDictObj();put(ip,frame,"origin",vecObj(origin));put(ip,frame,"normal",vecObj(normal));put(ip,frame,"u_axis",vecObj(u));
    put(ip,out,"profile_token",Tcl_NewStringObj(id.c_str(),-1));put(ip,out,"input_points",Tcl_NewWideIntObj(total));put(ip,out,"contour_count",Tcl_NewWideIntObj(count));put(ip,out,"captured_plane",frame);return out;
}
void cadWriteDoubleLE(std::ofstream& output,double value) {
    if(!std::isfinite(value))throw std::runtime_error("Profile export coordinate is not finite");
    uint64_t bits;std::memcpy(&bits,&value,8);unsigned char bytes[8];for(unsigned i=0;i<8;++i)bytes[i]=static_cast<unsigned char>(bits>>(8*i));
    output.write(reinterpret_cast<const char*>(bytes),8);if(!output)throw std::runtime_error("Cannot stage complete profile coordinates");
}
gx3de_anchor* cadAnchor(Tcl_Interp* ip,State& state,gx3de_object* moving,Tcl_Obj* descriptor) {
    std::string kind=field(ip,descriptor,"kind");gx3de_anchor* anchor=nullptr;
    if(kind=="moving_point")check(gx3de_anchor_object_point(moving,cadVector(ip,get(ip,descriptor,"point"),"local point"),&anchor),"create local anchor");
    else if(kind=="world_point")check(gx3de_anchor_free(state.cadScene,cadVector(ip,get(ip,descriptor,"point"),"world point"),&anchor),"create fixed world anchor");
    else if(kind=="line")check(gx3de_anchor_line(state.cadScene,cadVector(ip,get(ip,descriptor,"point"),"line point"),cadVector(ip,get(ip,descriptor,"direction"),"line direction"),&anchor),"create line anchor");
    else {
        gx3de_object* object=get(ip,descriptor,"object_token")?cadObject(state,field(ip,descriptor,"object_token")):moving;
        if(kind=="object_point")check(gx3de_anchor_object_point(object,cadVector(ip,get(ip,descriptor,"point"),"object point"),&anchor),"create object point anchor");
        else if(kind=="object_axis")check(gx3de_anchor_object_axis(object,cadVector(ip,get(ip,descriptor,"point"),"axis point"),cadVector(ip,get(ip,descriptor,"direction"),"axis direction"),&anchor),"create object axis anchor");
        else if(kind=="mesh_vertex")check(gx3de_anchor_object_vertex(object,integer(field(ip,descriptor,"index"),"vertex index"),&anchor),"create persistent mesh vertex anchor");
        else if(kind=="brep_vertex")check(gx3de_anchor_brep_vertex(object,integer(field(ip,descriptor,"index"),"B-Rep vertex index"),&anchor),"create B-Rep vertex anchor");
        else if(kind=="brep_edge")check(gx3de_anchor_brep_edge(object,integer(field(ip,descriptor,"index"),"B-Rep edge index"),number(field(ip,descriptor,"parameter"),"edge parameter"),&anchor),"create B-Rep edge anchor");
        else if(kind=="brep_face")check(gx3de_anchor_brep_face(object,integer(field(ip,descriptor,"index"),"B-Rep face index"),number(field(ip,descriptor,"u"),"face U"),number(field(ip,descriptor,"v"),"face V"),&anchor),"create B-Rep face anchor");
        else throw std::runtime_error("Choose a supported persistent point, axis, line or B-Rep anchor");
    }
    return anchor;
}
Tcl_Obj* cadObjectInfo(Tcl_Interp* ip,State& state,const std::string& id) {
    auto* object=cadObject(state,id);Tcl_Obj* out=Tcl_NewDictObj();
    put(ip,out,"object_token",Tcl_NewStringObj(id.c_str(),-1));
    put(ip,out,"kind",Tcl_NewStringObj(state.cadKinds.at(id).c_str(),-1));
    uint32_t role=0;check(gx3de_object_geometry_role_get(object,&role),"read scientific geometry role");
    put(ip,out,"geometry_role",Tcl_NewStringObj(role==GX3DE_GEOMETRY_REFERENCE?"reference":role==GX3DE_GEOMETRY_CONSTRUCTION?"construction":"regular",-1));
    char fingerprint[65];check(gx3de_object_geometry_fingerprint(object,fingerprint),"read immutable geometry fingerprint");
    put(ip,out,"geometry_sha256",Tcl_NewStringObj(fingerprint,-1));
    gx3de_mat4 matrix;check(gx3de_object_get_transform(object,&matrix),"read object transform");put(ip,out,"transform",matrixObj(matrix));
    check(gx3de_object_world_transform_get(object,&matrix),"read complete world placement");put(ip,out,"world_transform",matrixObj(matrix));
    gx3de_bounds bounds;check(gx3de_object_bounds(object,1,&bounds),"read complete geometry bounds");
    put(ip,out,"bounds_min",vecObj(bounds.min));put(ip,out,"bounds_max",vecObj(bounds.max));
    if(state.cadKinds.at(id)=="brep") {
        gx3de_brep_diagnostics d{};d.struct_size=sizeof d;check(gx3de_brep_diagnose(object,&d),"diagnose B-Rep");
        gx3de_brep_validation v{};v.struct_size=sizeof v;check(gx3de_brep_validate(object,&v),"validate B-Rep");
        put(ip,out,"surface_area",Tcl_NewDoubleObj(d.surface_area));put(ip,out,"volume",Tcl_NewDoubleObj(d.enclosed_volume));
        put(ip,out,"volume_defined",Tcl_NewIntObj(d.volume_defined));put(ip,out,"topology_valid",Tcl_NewIntObj(v.topology_valid));
        put(ip,out,"closed",Tcl_NewIntObj(v.closed_oriented_solids));put(ip,out,"solids",Tcl_NewWideIntObj(v.solids));
    } else if(state.cadKinds.at(id)=="scientific") {
        gx3de_scientific_info d{};d.struct_size=sizeof d;check(gx3de_scientific_info_get(object,&d),"scientific inventory");
        put(ip,out,"point_count",Tcl_NewWideIntObj(d.point_count));put(ip,out,"cell_count",Tcl_NewWideIntObj(d.cell_count));put(ip,out,"array_count",Tcl_NewWideIntObj(d.array_count));
    } else if(state.cadKinds.at(id)=="mesh") {
        gx3de_mesh_diagnostics d{};d.struct_size=sizeof d;
        check(gx3de_mesh_diagnose_world(object,&d),"diagnose complete world-space mesh");
        put(ip,out,"surface_area",Tcl_NewDoubleObj(d.surface_area));put(ip,out,"volume",Tcl_NewDoubleObj(d.enclosed_volume));
        put(ip,out,"volume_defined",Tcl_NewIntObj(d.volume_defined));put(ip,out,"closed",Tcl_NewIntObj(d.closed_manifold));
        put(ip,out,"boundary_edges",Tcl_NewWideIntObj(d.boundary_edges));put(ip,out,"nonmanifold_edges",Tcl_NewWideIntObj(d.nonmanifold_edges));
        put(ip,out,"orientation_conflicts",Tcl_NewWideIntObj(d.orientation_conflicts));put(ip,out,"components",Tcl_NewWideIntObj(d.disconnected_components));
    }
    return out;
}
std::string cadRetain(State& state,gx3de_object* object,const std::string& kind) {
    std::string id=state.cadPrefix+"object-"+std::to_string(++state.cadSerial);
    state.cadObjects.emplace(id,object);state.cadKinds.emplace(id,kind);return id;
}
int cadGroupCall(Tcl_Interp* ip,State& state,const std::string& action,Tcl_Obj* request) {
    gx3de_group* pending=nullptr;std::vector<gx3de_object*> created;std::vector<std::string> retained;
    std::string groupId;
    try {
        if(action=="group_delete") {
            std::string id=field(ip,request,"group_token");auto found=state.cadGroups.find(id);
            if(found==state.cadGroups.end())throw std::runtime_error("Unknown or stale Native3D group token");
            check(gx3de_group_destroy(found->second),"release retained group");state.cadGroups.erase(found);
            for(const auto& member:state.cadGroupMembers.at(id)){auto object=state.cadObjects.find(member);if(object!=state.cadObjects.end()){gx3de_object_destroy(object->second);state.cadObjects.erase(object);state.cadKinds.erase(member);}}
            state.cadGroupMembers.erase(id);Tcl_SetObjResult(ip,Tcl_NewStringObj("deleted",-1));return TCL_OK;
        }
        std::vector<std::string> kinds;
        if(action=="group_copy") {
            auto inputs=cadList(ip,get(ip,request,"object_tokens"));if(inputs.empty()||inputs.size()>4096)throw std::runtime_error("Group copy needs 1..4096 explicit objects");
            std::vector<gx3de_object*> originals;originals.reserve(inputs.size());kinds.reserve(inputs.size());created.reserve(inputs.size());retained.reserve(inputs.size());
            for(auto* input:inputs){std::string id=str(input);originals.push_back(cadObject(state,id));kinds.push_back(state.cadKinds.at(id));}
            check(gx3de_group_create(state.cadScene,&pending),"create retained copied group");
            for(auto* original:originals){gx3de_object* copy=nullptr;check(gx3de_object_duplicate(original,&copy),"copy grouped source geometry");created.push_back(copy);check(gx3de_group_add(pending,copy),"attach copied object preserving world placement");}
        } else if(action=="group_duplicate") {
            std::string id=field(ip,request,"group_token");auto found=state.cadGroups.find(id);
            if(found==state.cadGroups.end())throw std::runtime_error("Unknown or stale Native3D group token");
            const auto& members=state.cadGroupMembers.at(id);
            kinds.reserve(members.size());created.reserve(members.size());retained.reserve(members.size());
            for(const auto& member:members){cadObject(state,member);kinds.push_back(state.cadKinds.at(member));}
            check(gx3de_group_duplicate(found->second,&pending),"atomically duplicate complete group subtree");
            uint64_t count=0;check(gx3de_group_member_count(pending,&count),"read duplicated group members");
            for(uint64_t i=0;i<count;++i){gx3de_object* object=nullptr;check(gx3de_group_member_get(pending,i,&object),"read duplicated member");created.push_back(object);}
            if(count!=kinds.size())throw std::runtime_error("Retained group member structure changed");
        } else throw std::runtime_error("Unknown retained group operation");
        if(get(ip,request,"matrix")){
            auto values=cadList(ip,get(ip,request,"matrix"));if(values.size()!=16)throw std::runtime_error("Group transform needs 16 finite coefficients");
            gx3de_mat4 matrix;for(size_t i=0;i<16;++i)matrix.m[i]=number(str(values[i]),"group transform");
            check(gx3de_group_set_transform(pending,&matrix),"transform copied group atomically");
        }
        std::string operation=field(ip,request,"transform_action");
        if(operation=="translate")check(gx3de_group_translate(pending,cadVector(ip,get(ip,request,"delta"),"group translation"),1),"translate copied group atomically");
        else if(operation=="rotate")check(gx3de_group_rotate(pending,cadVector(ip,get(ip,request,"axis"),"group axis"),number(field(ip,request,"radians"),"group angle"),cadVector(ip,get(ip,request,"pivot"),"group pivot"),1),"rotate copied group atomically");
        else if(operation=="scale")check(gx3de_group_scale(pending,cadVector(ip,get(ip,request,"factors"),"group factors"),cadVector(ip,get(ip,request,"pivot"),"group pivot"),1),"scale copied group atomically");
        else if(!operation.empty())throw std::runtime_error("Choose group Translate, Rotate or Scale");
        Tcl_Obj* result=Tcl_NewDictObj();Tcl_Obj* members=Tcl_NewListObj(0,nullptr);
        for(size_t i=0;i<created.size();++i){std::string id=cadRetain(state,created[i],kinds[i]);retained.push_back(id);Tcl_ListObjAppendElement(ip,members,cadObjectInfo(ip,state,id));}
        gx3de_bounds bounds;check(gx3de_group_bounds(pending,&bounds),"read complete copied group bounds");
        groupId=state.cadPrefix+"group-"+std::to_string(++state.cadSerial);
        state.cadGroups.emplace(groupId,pending);state.cadGroupMembers.emplace(groupId,retained);pending=nullptr;
        put(ip,result,"group_token",Tcl_NewStringObj(groupId.c_str(),-1));put(ip,result,"members",members);
        put(ip,result,"bounds_min",vecObj(bounds.min));put(ip,result,"bounds_max",vecObj(bounds.max));Tcl_SetObjResult(ip,result);return TCL_OK;
    } catch(const std::exception& e) {
        if(!groupId.empty()){state.cadGroups.erase(groupId);state.cadGroupMembers.erase(groupId);}
        for(const auto& id:retained){state.cadObjects.erase(id);state.cadKinds.erase(id);}
        if(pending)gx3de_group_destroy(pending);
        for(auto* object:created)gx3de_object_destroy(object);
        error(ip,e);return TCL_ERROR;
    }
}

#include "native3d_numerical_tcl_v1.inc"

int cadCall(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]) {
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"owner_scope action request");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);gx3de_object* pending=nullptr;
    std::string retained;
    gx3de_plane* plane=nullptr;gx3de_profile* profile=nullptr;
    gx3de_step_document* step=nullptr;
    gx3de_section* section=nullptr;
    std::vector<gx3de_anchor*> anchors;
    std::vector<gx3de_constraint*> constraints;
    std::vector<gx3de_plane*> constraintPlanes;
    gx3de_constraint_system_result solved{};
    gx3de_measurement* measurement=nullptr;
    try {
        CadDiagnosticOutput diagnosticOutput;
        std::string scope=str(args[1]),action=str(args[2]);Tcl_Obj* request=args[3];
        if(scope.empty())throw std::runtime_error("Native3D requires an explicit document lifetime scope");
        if(action=="open") {
            if(state.cadScene&&state.cadScope!=scope)throw std::runtime_error("Another Native3D document is active; close its scope first");
            if(!state.cadScene) {
                check(gx3de_engine_create(&state.cadEngine),"create retained Native3D engine");
                check(gx3de_scene_create(state.cadEngine,&state.cadScene),"create retained Native3D scene");state.cadScope=scope;
            }
            Tcl_Obj* reply=Tcl_NewDictObj();put(ip,reply,"status",Tcl_NewStringObj("open",-1));
            put(ip,reply,"object_count",Tcl_NewWideIntObj(state.cadObjects.size()));
            put(ip,reply,"profile_count",Tcl_NewWideIntObj(state.cadProfiles.size()));Tcl_SetObjResult(ip,reply);return TCL_OK;
        }
        if(!state.cadScene||state.cadScope!=scope)throw std::runtime_error("Native3D document scope is closed or stale");
        if(action=="close") {state.clearCad();Tcl_SetObjResult(ip,Tcl_NewStringObj("closed",-1));return TCL_OK;}
        if(action=="group_copy"||action=="group_duplicate"||action=="group_delete")return cadGroupCall(ip,state,action,request);
        if(action=="geometry_role") {
            auto* object=cadObject(state,field(ip,request,"object_token"));
            if(get(ip,request,"role")) {
                const std::map<std::string,uint32_t> roles{{"regular",GX3DE_GEOMETRY_REGULAR},{"construction",GX3DE_GEOMETRY_CONSTRUCTION},{"reference",GX3DE_GEOMETRY_REFERENCE}};
                auto value=roles.find(field(ip,request,"role"));
                if(value==roles.end())throw std::runtime_error("Geometry role must be regular, construction or reference");
                check(gx3de_object_geometry_role_set(object,value->second),"set scientific geometry role");
            }
            Tcl_SetObjResult(ip,cadObjectInfo(ip,state,field(ip,request,"object_token")));return TCL_OK;
        }
        if(action=="compare_geometry") {
            gx3de_geometry_comparison_spec spec{};spec.struct_size=sizeof(spec);
            auto requestedBudget=integer(field(ip,request,"sample_budget"),"Scientific sample budget");
            if(requestedBudget<6||requestedBudget>4096)throw std::runtime_error("Scientific sample budget must be6..4096");
            spec.sample_budget=static_cast<uint32_t>(requestedBudget);
            spec.tessellation.struct_size=sizeof(spec.tessellation);
            spec.tessellation.linear_deflection=number(field(ip,request,"linear_deflection"),"Tessellation linear deflection");
            spec.tessellation.angular_deflection=number(field(ip,request,"angular_deflection"),"Tessellation angular deflection");
            spec.tessellation.weld_tolerance=number(field(ip,request,"weld_tolerance"),"Tessellation weld tolerance");
            spec.tessellation.max_triangles=integer(field(ip,request,"max_triangles"),"Tessellation triangle budget");
            spec.tessellation.max_output_bytes=integer(field(ip,request,"max_output_bytes"),"Scientific mesh byte budget");
            gx3de_geometry_comparison value{};value.struct_size=sizeof(value);uint64_t count=0;
            std::vector<gx3de_geometry_deviation> rows(2*spec.sample_budget);
            check(gx3de_compare_geometry(cadObject(state,field(ip,request,"base")),cadObject(state,field(ip,request,"tool")),&spec,&value,rows.data(),rows.size(),&count),"compare complete scientific surfaces");
            Tcl_Obj* result=Tcl_NewDictObj();Tcl_Obj* values=Tcl_NewListObj(0,nullptr);
            for(uint64_t i=0;i<count;++i) {Tcl_Obj* row=Tcl_NewDictObj();put(ip,row,"direction",Tcl_NewWideIntObj(rows[i].direction));put(ip,row,"source_vertex",Tcl_NewWideIntObj(rows[i].source_vertex));put(ip,row,"source",vecObj(rows[i].source));put(ip,row,"projected",vecObj(rows[i].projected));put(ip,row,"distance",Tcl_NewDoubleObj(rows[i].distance));Tcl_ListObjAppendElement(ip,values,row);}
            put(ip,result,"rows",values);
            for(auto item:std::initializer_list<std::pair<const char*,double>>{{"reference_rms",value.reference_rms},{"reference_mean",value.reference_mean},{"reference_max",value.reference_max},{"symmetric_rms",value.symmetric_rms},{"hausdorff_sampled",value.hausdorff_sampled},{"closest_sampled",value.closest_sampled},{"area_difference",value.area_difference},{"volume_difference",value.volume_difference}})put(ip,result,item.first,Tcl_NewDoubleObj(item.second));
            for(auto item:std::initializer_list<std::pair<const char*,uint64_t>>{{"reference_vertices",value.reference_vertices},{"target_vertices",value.target_vertices},{"reference_samples",value.reference_samples},{"target_samples",value.target_samples},{"volume_defined",value.volume_defined},{"reference_tessellated",value.reference_tessellated},{"target_tessellated",value.target_tessellated}})put(ip,result,item.first,Tcl_NewWideIntObj(item.second));
            put(ip,result,"closest_source",vecObj(value.closest_source));put(ip,result,"closest_target",vecObj(value.closest_target));put(ip,result,"bounds_min_difference",vecObj(value.bounds_min_difference));put(ip,result,"bounds_max_difference",vecObj(value.bounds_max_difference));
            put(ip,result,"sampling_policy",Tcl_NewStringObj("deterministic_vertex_stride_both_directions",-1));
            put(ip,result,"projection_policy",Tcl_NewStringObj("closest_point_on_complete_target_triangles",-1));
            put(ip,result,"extrema_policy",Tcl_NewStringObj("sampled_bounds_no_continuous_surface_guarantee",-1));
            Tcl_Obj* policy=Tcl_NewDictObj();
            for(const char* key:{"sample_budget","linear_deflection","angular_deflection","weld_tolerance","max_triangles","max_output_bytes"})put(ip,policy,key,get(ip,request,key));
            put(ip,result,"tessellation",policy);Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="anchor_describe") {
            gx3de_object* moving=get(ip,request,"object_token")?cadObject(state,field(ip,request,"object_token")):nullptr;
            auto* anchor=cadAnchor(ip,state,moving,get(ip,request,"anchor"));anchors.push_back(anchor);
            gx3de_vec3 point;check(gx3de_anchor_position(anchor,&point),"read persistent anchor position");
            gx3de_anchor_kind kind;check(gx3de_anchor_get_kind(anchor,&kind),"read anchor kind");
            Tcl_Obj* result=Tcl_NewDictObj();put(ip,result,"kind",Tcl_NewWideIntObj(kind));put(ip,result,"world_point",vecObj(point));
            gx3de_vec3 direction;
            auto normal=gx3de_anchor_normal(anchor,&direction);put(ip,result,"has_normal",Tcl_NewIntObj(normal==GX3DE_OK));if(normal==GX3DE_OK)put(ip,result,"normal",vecObj(direction));
            auto tangent=gx3de_anchor_tangent(anchor,&direction);put(ip,result,"has_tangent",Tcl_NewIntObj(tangent==GX3DE_OK));if(tangent==GX3DE_OK)put(ip,result,"tangent",vecObj(direction));
            gx3de_anchor_destroy(anchor);Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="measure") {
            const std::map<std::string,uint32_t> kinds{{"distance",GX3DE_DISTANCE},{"delta_x",GX3DE_DELTA_X},{"delta_y",GX3DE_DELTA_Y},{"delta_z",GX3DE_DELTA_Z},{"angle",GX3DE_ANGLE_THREE_POINTS},{"distance_on_plane",GX3DE_DISTANCE_ON_PLANE},{"point_line_distance",GX3DE_POINT_LINE_DISTANCE},{"point_plane_distance",GX3DE_POINT_PLANE_DISTANCE},{"line_line_angle",GX3DE_LINE_LINE_ANGLE},{"line_plane_angle",GX3DE_LINE_PLANE_ANGLE},{"plane_plane_angle",GX3DE_PLANE_PLANE_ANGLE},{"point_surface_distance",GX3DE_POINT_SURFACE_DISTANCE}};
            auto kind=kinds.find(field(ip,request,"kind"));if(kind==kinds.end())throw std::runtime_error("Choose a supported Native3D measurement kind");
            gx3de_measure_spec spec{};spec.struct_size=sizeof spec;spec.kind=kind->second;
            gx3de_object* moving=get(ip,request,"object_token")?cadObject(state,field(ip,request,"object_token")):nullptr;
            if(get(ip,request,"anchors")){auto inputs=cadList(ip,get(ip,request,"anchors"));if(inputs.size()>4)throw std::runtime_error("Measurements support at most four typed anchors");anchors.reserve(4);
                for(size_t i=0;i<inputs.size();++i){auto* anchor=cadAnchor(ip,state,moving,inputs[i]);anchors.push_back(anchor);spec.anchors[i]=anchor;}}
            constraintPlanes.reserve(2);
            for(size_t i=0;i<2;++i){auto* frame=get(ip,request,i==0?"plane":"plane2");if(!frame)continue;gx3de_plane* captured=nullptr;
                check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"plane origin"),cadVector(ip,get(ip,frame,"normal"),"plane normal"),cadVector(ip,get(ip,frame,"u_axis"),"plane U axis"),&captured),"create measurement plane");constraintPlanes.push_back(captured);spec.planes[i]=captured;}
            if(get(ip,request,"surface_object_token"))spec.surface_object=cadObject(state,field(ip,request,"surface_object_token"));
            check(gx3de_measure_create_ex(state.cadScene,&spec,&measurement),"create typed Native3D measurement");
            gx3de_measure_value value{};value.struct_size=sizeof value;check(gx3de_measure_evaluate(measurement,&value),"evaluate complete geometry measurement");
            Tcl_Obj* result=Tcl_NewDictObj();put(ip,result,"kind",Tcl_NewStringObj(kind->first.c_str(),-1));put(ip,result,"value",Tcl_NewDoubleObj(value.value));put(ip,result,"unit_known",Tcl_NewIntObj(value.unit_known));
            gx3de_measure_destroy(measurement);measurement=nullptr;for(auto* anchor:anchors)gx3de_anchor_destroy(anchor);for(auto* captured:constraintPlanes)gx3de_plane_destroy(captured);
            Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="profile_view_export") {
            check(gx3de_profile_write_vtp(cadProfile(state,field(ip,request,"profile_token")),field(ip,request,"path").c_str()),"stage complete captured profile lines");
            Tcl_SetObjResult(ip,Tcl_NewStringObj("staged",-1));return TCL_OK;
        }
        if(action=="profile_export") {
            auto* source=cadProfile(state,field(ip,request,"profile_token"));
            std::string directory=field(ip,request,"directory");if(!std::filesystem::is_directory(std::filesystem::u8path(directory)))throw std::runtime_error("Profile export needs an owned temporary directory");
            Tcl_Obj* result=cadProfileInfo(ip,source,field(ip,request,"profile_token"));Tcl_Obj* contours=Tcl_NewListObj(0,nullptr);
            uint64_t count=0,total=0;check(gx3de_profile_contour_count(source,&count),"read complete contours");
            if(count>4096)throw std::runtime_error("Profile export exceeds its contour budget");
            for(uint64_t i=0;i<count;++i) {
                gx3de_contour_info info{};info.struct_size=sizeof info;check(gx3de_profile_contour_info(source,i,&info),"read complete contour");
                if(info.point_count>1000000||total>1000000-info.point_count)throw std::runtime_error("Profile export exceeds its full-point budget");
                total+=info.point_count;
                auto path=std::filesystem::u8path(directory)/("contour-"+std::to_string(i)+".xy");
                if(std::filesystem::exists(path))throw std::runtime_error("Owned profile export target already exists");
                std::ofstream file(path,std::ios::binary);if(!file)throw std::runtime_error("Cannot create complete profile export");
                for(uint64_t j=0;j<info.point_count;++j){double u,v;check(gx3de_profile_point2(source,i,j,&u,&v),"read exact contour point");cadWriteDoubleLE(file,u);cadWriteDoubleLE(file,v);}
                file.close();if(!file)throw std::runtime_error("Profile export finalization failed");
                Tcl_Obj* contour=Tcl_NewDictObj();put(ip,contour,"xy_file",Tcl_NewStringObj(path.u8string().c_str(),-1));put(ip,contour,"point_count",Tcl_NewWideIntObj(info.point_count));put(ip,contour,"closed",Tcl_NewIntObj(info.closed));Tcl_ListObjAppendElement(ip,contours,contour);
            }
            put(ip,result,"contours",contours);Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="logical_id") {
            auto association=field(ip,request,"association");if(association!="point"&&association!="cell")throw std::runtime_error("Logical identity requires point or cell association");
            uint64_t value=0;check(gx3de_scientific_logical_id(cadObject(state,field(ip,request,"object_token")),association=="point"?GX3DE_SCI_ASSOC_POINT:GX3DE_SCI_ASSOC_CELL,integer(field(ip,request,"index"),"element index"),&value),"read durable scientific identity");
            auto* result=Tcl_NewDictObj();put(ip,result,"logical_id",Tcl_NewWideIntObj(value));Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="plane_frame") {
            auto* frame=get(ip,request,"plane");
            check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"origin"),cadVector(ip,get(ip,frame,"normal"),"normal"),cadVector(ip,get(ip,frame,"u_axis"),"U"),&plane),"validate physical frame");
            gx3de_vec3 origin,n,u,v;check(gx3de_plane_get(plane,&origin,&n,&u),"normalized frame");gx3de_vec3 vpoint;check(gx3de_plane_world(plane,{0,1,0},&vpoint),"V axis");v={vpoint.x-origin.x,vpoint.y-origin.y,vpoint.z-origin.z};
            auto* result=Tcl_NewDictObj();put(ip,result,"origin",vecObj(origin));put(ip,result,"normal",vecObj(n));put(ip,result,"u_axis",vecObj(u));put(ip,result,"v_axis",vecObj(v));
            if(get(ip,request,"points")){auto* mapped=Tcl_NewListObj(0,nullptr);auto mode=field(ip,request,"direction");for(auto* input:cadList(ip,get(ip,request,"points"))){gx3de_vec3 q,p=cadVector(ip,input,"mapping point");if(mode=="to_world")check(gx3de_plane_world(plane,p,&q),"plane to world");else if(mode=="to_plane")check(gx3de_plane_coordinates(plane,p,&q),"world to plane");else if(mode=="project_vector")check(gx3de_plane_project_vector(plane,p,&q),"project vector");else if(mode=="project_point")check(gx3de_plane_project_point(plane,p,&q),"project point");else throw std::runtime_error("Unknown frame direction");Tcl_ListObjAppendElement(ip,mapped,vecObj(q));}put(ip,result,"points",mapped);}
            gx3de_plane_destroy(plane);plane=nullptr;Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="projection_profile") {
            auto* frame=get(ip,request,"plane");check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"origin"),cadVector(ip,get(ip,frame,"normal"),"normal"),cadVector(ip,get(ip,frame,"u_axis"),"U"),&plane),"projection frame");
            auto* source=cadObject(state,field(ip,request,"object_token"));
            if(state.cadKinds.at(field(ip,request,"object_token"))=="scientific"){check(gx3de_scientific_triangle_mesh_create(source,1000000,134217728,&pending),"explicit surface boundary extraction");source=pending;}
            gx3de_mesh_loops* loops=nullptr;check(gx3de_mesh_loops_create(source,&loops),"extract source surface boundaries");
            try {
                uint64_t count=0;check(gx3de_mesh_loops_count(loops,&count),"boundary count");if(count>4096)throw std::runtime_error("Projection boundary contour budget exceeds 4096");if(!count)throw std::runtime_error("Boundary projection needs 1..4096 actual source boundary contours; closed solids need a selected curve or another explicit projection policy");
                std::vector<std::vector<gx3de_point2>> points(count);std::vector<gx3de_profile_contour_spec> specs(count);
                for(uint64_t i=0;i<count;++i){uint64_t vertexCount=0;check(gx3de_mesh_loops_size(loops,i,&vertexCount),"source boundary");
                    for(uint64_t j=0;j<vertexCount;++j){uint32_t sourceIndex;gx3de_vec3 p,q;check(gx3de_mesh_loops_vertex(loops,i,j,&sourceIndex,&p),"boundary source vertex");check(gx3de_plane_coordinates(plane,p,&q),"orthogonal boundary projection");points[i].push_back({q.x,q.y});}
                    specs[i].struct_size=sizeof specs[i];specs[i].points=points[i].data();specs[i].point_count=points[i].size();specs[i].closed=1;
                }
                check(gx3de_profile_create_contours(state.cadScene,plane,specs.data(),specs.size(),number(field(ip,request,"tolerance"),"projection tolerance"),&profile),"validate projected source boundary contours");
            }catch(...){gx3de_mesh_loops_destroy(loops);throw;}
            gx3de_mesh_loops_destroy(loops);if(pending){gx3de_object_destroy(pending);pending=nullptr;}gx3de_plane_destroy(plane);plane=nullptr;
            std::string id=state.cadPrefix+"profile-"+std::to_string(++state.cadSerial);auto* result=cadProfileInfo(ip,profile,id);state.cadProfiles.emplace(id,profile);profile=nullptr;
            put(ip,result,"policy",Tcl_NewStringObj("orthogonal_source_boundary_no_depth_reconstruction",-1));Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="profile_rescale"||action=="section_profile") {
            if(action=="profile_rescale")check(gx3de_profile_rescale(cadProfile(state,field(ip,request,"profile_token")),number(field(ip,request,"factor"),"unit rescale"),&profile),"rescale immutable captured profile");
            else {
                Tcl_Obj* frame=get(ip,request,"plane");
                check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"section plane origin"),cadVector(ip,get(ip,frame,"normal"),"section plane normal"),cadVector(ip,get(ip,frame,"u_axis"),"section U axis"),&plane),"create captured section plane");
                auto* source=cadObject(state,field(ip,request,"object_token"));
                if(state.cadKinds.at(field(ip,request,"object_token"))=="scientific"){check(gx3de_scientific_triangle_mesh_create(source,1000000,134217728,&pending),"temporary complete surface for section; source arrays preserved");source=pending;}
                check(gx3de_section_create(source,plane,&section),"section complete source geometry");
                check(gx3de_profile_create(section,number(field(ip,request,"tolerance"),"section tolerance"),&profile),"chain exact section contours");
                check(gx3de_section_destroy(section),"release source section cache");section=nullptr;
                if(pending){gx3de_object_destroy(pending);pending=nullptr;}
                check(gx3de_plane_destroy(plane),"release section plane");plane=nullptr;
            }
            std::string id=state.cadPrefix+"profile-"+std::to_string(++state.cadSerial);
            Tcl_Obj* result=cadProfileInfo(ip,profile,id);state.cadProfiles.emplace(id,profile);profile=nullptr;Tcl_SetObjResult(ip,result);return TCL_OK;
        }
        if(action=="profile") {
            auto contours=cadList(ip,get(ip,request,"contours"));
            if(contours.empty()||contours.size()>4096)throw std::runtime_error("Native3D profile requires 1..4096 contours");
            std::vector<std::vector<gx3de_point2>> points(contours.size());std::vector<gx3de_profile_contour_spec> specs(contours.size());uint64_t total=0;
            for(size_t i=0;i<contours.size();++i) {
                uint64_t count=integer(field(ip,contours[i],"point_count"),"profile points");
                if(count<2||count>1000000||total>1000000-count)throw std::runtime_error("Native3D profiles support 2..1000000 complete input points");
                total+=count;std::ifstream input(field(ip,contours[i],"xy_file"),std::ios::binary);
                if(!input)throw std::runtime_error("Cannot open owned Native3D profile input");
                std::string gapFile=field(ip,contours[i],"gap_file");std::ifstream gaps;
                if(!gapFile.empty()){gaps.open(gapFile,std::ios::binary);if(!gaps)throw std::runtime_error("Cannot open owned Native3D gap input");}
                points[i].reserve(count);
                for(uint64_t j=0;j<count;++j) {
                    double x=cadDoubleLE(input),y=cadDoubleLE(input);points[i].push_back({x,y});
                    if(gaps.is_open()){char gap;gaps.get(gap);if(!gaps||gap<0||gap>1||(j>0&&gap))throw std::runtime_error("Profile contains missing-pair gaps; split it into explicit contours");}
                }
                if(input.peek()!=std::char_traits<char>::eof()||(gaps.is_open()&&gaps.peek()!=std::char_traits<char>::eof()))throw std::runtime_error("Owned Native3D profile input shape changed");
                int closed=0;
                if(!get(ip,contours[i],"closed")||Tcl_GetBooleanFromObj(ip,get(ip,contours[i],"closed"),&closed)!=TCL_OK)throw std::runtime_error("Profile closure must be an explicit boolean");
                specs[i].struct_size=sizeof specs[i];specs[i].points=points[i].data();specs[i].point_count=count;specs[i].closed=closed?1u:0u;
            }
            Tcl_Obj* frame=get(ip,request,"plane");
            check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"plane origin"),cadVector(ip,get(ip,frame,"normal"),"plane normal"),cadVector(ip,get(ip,frame,"u_axis"),"plane U axis"),&plane),"create captured working plane");
            check(gx3de_profile_create_contours(state.cadScene,plane,specs.data(),specs.size(),number(field(ip,request,"tolerance"),"join tolerance"),&profile),"validate ordered contours");
            check(gx3de_plane_destroy(plane),"release captured input plane");plane=nullptr;
            std::string id=state.cadPrefix+"profile-"+std::to_string(++state.cadSerial);
            state.cadProfiles.emplace(id,profile);profile=nullptr;
            Tcl_Obj* reply=Tcl_NewDictObj();put(ip,reply,"profile_token",Tcl_NewStringObj(id.c_str(),-1));put(ip,reply,"input_points",Tcl_NewWideIntObj(total));
            put(ip,reply,"contour_count",Tcl_NewWideIntObj(contours.size()));Tcl_SetObjResult(ip,reply);return TCL_OK;
        }
        if(action=="profile_delete") {
            std::string id=field(ip,request,"profile_token");auto found=state.cadProfiles.find(id);
            if(found==state.cadProfiles.end())throw std::runtime_error("Unknown or stale Native3D profile token");
            check(gx3de_profile_destroy(found->second),"delete retained profile");state.cadProfiles.erase(found);
            Tcl_SetObjResult(ip,Tcl_NewStringObj("deleted",-1));return TCL_OK;
        }
        std::string kind="brep";
        if(action=="indexed_mesh"||action=="polydata"||action=="masked_surface"||action=="sweep") {
            pending=cadNumerical(ip,state,action,request);kind="scientific";
        } else if(action=="load_scientific") {
            std::string path=field(ip,request,"path");gx3de_scientific_import_spec spec{};spec.struct_size=sizeof spec;spec.path_utf8=path.c_str();spec.format=GX3DE_SCIENTIFIC_VTP;
            check(gx3de_scientific_import(state.cadScene,&spec,&pending),"restore lossless scientific PolyData");kind="scientific";
        } else if(action=="project") {
            auto* frame=get(ip,request,"plane");check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"origin"),cadVector(ip,get(ip,frame,"normal"),"normal"),cadVector(ip,get(ip,frame,"u_axis"),"U"),&plane),"projection frame");
            std::string id=field(ip,request,"object_token");kind=state.cadKinds.at(id);
            check(gx3de_object_project(cadObject(state,id),plane,nullptr,&pending),"orthogonal projection (CAD requires explicit tessellation first)");gx3de_plane_destroy(plane);plane=nullptr;
        } else if(action=="load_step"||action=="restore_step") {
            std::string path=field(ip,request,"path");
            double scale=number(field(ip,request,"millimeters_per_working_unit"),"STEP unit scale");
            if(scale<=0)throw std::runtime_error("STEP unit scale must be positive");
            gx3de_step_import_spec spec{};spec.struct_size=sizeof spec;spec.path_utf8=path.c_str();
            spec.max_source_bytes=268435456;spec.max_nodes=100000;
            check(gx3de_step_open(state.cadEngine,&spec,&step),"restore exact STEP resource");
            gx3de_step_summary summary{};summary.struct_size=sizeof summary;
            check(gx3de_step_summary_get(step,&summary),"read saved STEP structure");
            if(action=="restore_step") {
                // An exported Document object can legitimately contain several
                // disconnected solids. Rehydrate its complete immutable shape;
                // do not fuse parts or reinterpret them as new Document IDs.
                check(gx3de_step_compound_create(state.cadScene,step,&pending),"restore complete saved B-Rep compound");
            } else {
                uint64_t selected=UINT64_MAX;
                for(uint64_t i=0;i<summary.nodes;++i) {
                    gx3de_step_node node{};node.struct_size=sizeof node;
                    check(gx3de_step_node_get(step,i,&node),"read saved STEP occurrence");
                    if(node.kind==GX3DE_STEP_PART_OCCURRENCE) {
                        if(selected!=UINT64_MAX)throw std::runtime_error("A saved object resource must contain exactly one STEP occurrence; import assemblies as separate objects");
                        selected=i;
                    }
                }
                if(selected==UINT64_MAX)throw std::runtime_error("Saved STEP resource contains no solid occurrence");
                check(gx3de_step_instance_create(state.cadScene,step,selected,&pending),"restore authoritative B-Rep");
            }
            gx3de_mat4 matrix;check(gx3de_object_get_transform(pending,&matrix),"read saved STEP placement");
            // STEP input is normalized to millimetres. Scale both geometry and
            // translated occurrence placement into the document's working unit.
            for(size_t column=0;column<4;++column)for(size_t row=0;row<3;++row)matrix.m[column*4+row]/=scale;
            check(gx3de_object_set_transform(pending,&matrix),"restore explicit working units");
            gx3de_object* normalized=nullptr;
            check(gx3de_object_bake_transform(pending,&normalized),"normalize STEP coordinates into the asserted working unit");
            gx3de_object_destroy(pending);pending=normalized;
            check(gx3de_step_close(step),"release STEP import owner");step=nullptr;
        } else if(action=="load_mesh") {
            std::string path=field(ip,request,"path"),format=field(ip,request,"format");kind="mesh";
            if(format=="stl"||format=="obj") {
                gx3de_mesh_import_spec spec{};spec.struct_size=sizeof spec;spec.path_utf8=path.c_str();
                spec.format=format=="stl"?GX3DE_IMPORT_STL:GX3DE_IMPORT_OBJ;
                check(gx3de_object_import_mesh(state.cadScene,&spec,&pending),"restore complete mesh resource");
            } else if(format=="vtp") {
                gx3de_scientific_import_spec spec{};spec.struct_size=sizeof spec;spec.path_utf8=path.c_str();spec.format=GX3DE_SCIENTIFIC_VTP;
                check(gx3de_scientific_import(state.cadScene,&spec,&pending),"restore complete polydata resource");
                gx3de_object* mesh=nullptr;
                auto converted=gx3de_scientific_triangle_mesh_create(pending,1000000,134217728,&mesh);
                gx3de_object_destroy(pending);pending=mesh;
                check(converted,"convert complete VTP surface to triangle mesh (requires pure surface cells; fields remain in source resource)");
            } else throw std::runtime_error("Mesh resources support STL, OBJ or VTP");
        } else if(action=="extrude") {
            auto found=state.cadProfiles.find(field(ip,request,"profile_token"));
            if(found==state.cadProfiles.end())throw std::runtime_error("Unknown or stale Native3D profile token");
            check(gx3de_profile_extrude(found->second,number(field(ip,request,"distance"),"signed extrusion distance"),&pending),"extrude captured profile");
        } else if(action=="box") {
            check(gx3de_object_create_brep_box(state.cadScene,cadVector(ip,get(ip,request,"lengths"),"box dimensions"),&pending),"create analytical box");
        } else if(action=="cylinder") {
            check(gx3de_object_create_brep_cylinder(state.cadScene,number(field(ip,request,"radius"),"radius"),number(field(ip,request,"height"),"height"),&pending),"create analytical cylinder");
        } else if(action=="boolean") {
            std::string mode=field(ip,request,"mode");gx3de_boolean_kind operation;
            if(mode=="join")operation=GX3DE_BOOLEAN_UNION;else if(mode=="cut")operation=GX3DE_BOOLEAN_DIFFERENCE;else if(mode=="intersect")operation=GX3DE_BOOLEAN_INTERSECTION;else throw std::runtime_error("Choose Join, Cut or Intersect");
            check(gx3de_brep_boolean(cadObject(state,field(ip,request,"base")),cadObject(state,field(ip,request,"tool")),operation,&pending),"source-preserving Boolean");
        } else if(action=="duplicate") {
            std::string source=field(ip,request,"object_token");auto* object=cadObject(state,source);kind=state.cadKinds.at(source);
            check(gx3de_object_duplicate(object,&pending),"duplicate retained geometry");
        } else if(action=="mesh") {
            gx3de_brep_mesh_spec spec{};spec.struct_size=sizeof spec;spec.linear_deflection=number(field(ip,request,"linear_deflection"),"linear deflection");
            spec.angular_deflection=number(field(ip,request,"angular_deflection"),"angular deflection");spec.weld_tolerance=number(field(ip,request,"weld_tolerance"),"weld tolerance");
            spec.max_triangles=integer(field(ip,request,"max_triangles"),"triangle budget");spec.max_output_bytes=integer(field(ip,request,"max_output_bytes"),"output budget");
            auto id=field(ip,request,"object_token");
            if(state.cadKinds.at(id)=="scientific")check(gx3de_scientific_triangle_mesh_create(cadObject(state,id),spec.max_triangles,spec.max_output_bytes,&pending),"derive explicit scientific diagnostic surface; original attributes preserved on source");
            else check(gx3de_object_brep_mesh_create_world(cadObject(state,id),&spec,&pending),"derive complete mesh with working-unit world tolerances");kind="mesh";
        } else if(action=="align_three_points"||action=="constraint_solve") {
            std::string id=field(ip,request,"object_token");auto* source=cadObject(state,id);kind=state.cadKinds.at(id);
            check(gx3de_object_duplicate(source,&pending),"copy geometry before alignment or constraints");
            if(action=="align_three_points") {
                auto local=cadList(ip,get(ip,request,"local_points")),target=cadList(ip,get(ip,request,"world_points"));
                if(local.size()!=3||target.size()!=3)throw std::runtime_error("Alignment needs three local source points and three congruent world target points");
                anchors.reserve(6);gx3de_alignment_spec spec{};spec.struct_size=sizeof spec;spec.moving_object=pending;spec.tolerance=number(field(ip,request,"tolerance"),"alignment tolerance");
                for(size_t i=0;i<3;++i){gx3de_anchor* a=nullptr;check(gx3de_anchor_object_point(pending,cadVector(ip,local[i],"local anchor"),&a),"create local alignment anchor");anchors.push_back(a);spec.moving_points[i]=a;
                    a=nullptr;check(gx3de_anchor_free(state.cadScene,cadVector(ip,target[i],"world target"),&a),"create world alignment target");anchors.push_back(a);spec.target_points[i]=a;}
                check(gx3de_object_align_three_points(&spec),"rigid alignment by three point pairs");
            } else {
                auto inputs=cadList(ip,get(ip,request,"constraints"));if(inputs.empty()||inputs.size()>256)throw std::runtime_error("Choose 1..256 explicit constraints");
                constraints.reserve(inputs.size());anchors.reserve(inputs.size()*4);constraintPlanes.reserve(inputs.size());
                for(auto* input:inputs){gx3de_constraint_spec spec{};spec.struct_size=sizeof spec;spec.moving_object=pending;
                    std::string mode=field(ip,input,"kind");
                    if(mode=="fixed") {
                        spec.kind=GX3DE_CONSTRAINT_FIXED;spec.tolerance=number(field(ip,input,"tolerance"),"fixed tolerance");
                        gx3de_mat4 proposed;check(gx3de_object_get_transform(pending,&proposed),"read proposed placement");
                        if(get(ip,input,"matrix")){auto values=cadList(ip,get(ip,input,"matrix"));if(values.size()!=16)throw std::runtime_error("Fixed placement needs 16 coefficients");gx3de_mat4 fixed;
                            for(size_t i=0;i<16;++i)fixed.m[i]=number(str(values[i]),"fixed matrix");
                            check(gx3de_object_set_transform(pending,&fixed),"restore fixed placement before constraint capture");}
                        gx3de_constraint* constraint=nullptr;check(gx3de_constraint_create(state.cadScene,&spec,&constraint),"create fixed placement constraint");constraints.push_back(constraint);
                        check(gx3de_object_set_transform(pending,&proposed),"restore proposed placement for constraint evaluation");continue;
                    }
                    const std::map<std::string,uint32_t> extended{{"angle_lines",GX3DE_CONSTRAINT_ANGLE_LINES},{"parallel_lines",GX3DE_CONSTRAINT_PARALLEL_LINES},{"perpendicular_lines",GX3DE_CONSTRAINT_PERPENDICULAR_LINES},{"point_on_line",GX3DE_CONSTRAINT_POINT_ON_LINE},{"point_on_surface",GX3DE_CONSTRAINT_POINT_ON_SURFACE},{"aligned_axes",GX3DE_CONSTRAINT_ALIGNED_AXES}};
                    auto extendedKind=extended.find(mode);
                    if(extendedKind!=extended.end()){
                        gx3de_constraint_spec_ex ext{};ext.struct_size=sizeof ext;ext.kind=extendedKind->second;ext.moving_object=pending;ext.tolerance=number(field(ip,input,"tolerance"),"constraint tolerance");ext.target=mode=="angle_lines"?number(field(ip,input,"target"),"angle radians"):0;
                        auto specs=cadList(ip,get(ip,input,"anchors"));if(specs.empty()||specs.size()>4)throw std::runtime_error("Extended constraints require 1..4 typed anchors");
                        for(size_t i=0;i<specs.size();++i){auto* anchor=cadAnchor(ip,state,pending,specs[i]);anchors.push_back(anchor);ext.anchors[i]=anchor;}
                        if(mode=="point_on_surface")ext.surface_object=cadObject(state,field(ip,input,"surface_object_token"));
                        gx3de_constraint* constraint=nullptr;check(gx3de_constraint_create_ex(state.cadScene,&ext,&constraint),"create extended public constraint");constraints.push_back(constraint);continue;
                    }
                    if(mode=="coincident")spec.kind=GX3DE_CONSTRAINT_COINCIDENT;else if(mode=="distance")spec.kind=GX3DE_CONSTRAINT_DISTANCE;else if(mode=="point_on_plane")spec.kind=GX3DE_CONSTRAINT_POINT_ON_PLANE;else throw std::runtime_error("Choose a supported CORE constraint kind");
                    spec.tolerance=number(field(ip,input,"tolerance"),"constraint tolerance");spec.target=mode=="distance"?number(field(ip,input,"target"),"target distance"):0;
                    gx3de_anchor* a=nullptr;check(gx3de_anchor_object_point(pending,cadVector(ip,get(ip,input,"local_point"),"local constraint point"),&a),"create constrained local anchor");anchors.push_back(a);spec.a=a;
                    if(mode=="point_on_plane") {
                        Tcl_Obj* frame=get(ip,input,"plane");gx3de_plane* captured=nullptr;
                        check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"plane origin"),cadVector(ip,get(ip,frame,"normal"),"plane normal"),cadVector(ip,get(ip,frame,"u_axis"),"plane U axis"),&captured),"create constraint plane");constraintPlanes.push_back(captured);spec.plane=captured;
                    } else {a=nullptr;check(gx3de_anchor_free(state.cadScene,cadVector(ip,get(ip,input,"world_point"),"world constraint target"),&a),"create target anchor");anchors.push_back(a);spec.b=a;}
                    gx3de_constraint* constraint=nullptr;check(gx3de_constraint_create(state.cadScene,&spec,&constraint),"create explicit geometric constraint");constraints.push_back(constraint);
                }
                solved.struct_size=sizeof solved;check(gx3de_constraint_system_solve(state.cadScene,constraints.data(),constraints.size(),16,&solved),"atomically solve the complete constraint set");
                if((solved.status!=GX3DE_CONSTRAINT_SATISFIED&&solved.status!=GX3DE_CONSTRAINT_UNDERDETERMINED)||solved.satisfied_count!=constraints.size())throw std::runtime_error("Constraint set is incompatible or cannot satisfy every requested target; source geometry was preserved");
            }
        } else if(action=="rescale_coordinates") {
            std::string id=field(ip,request,"object_token");kind=state.cadKinds.at(id);
            check(gx3de_object_rescale_coordinates(cadObject(state,id),number(field(ip,request,"factor"),"coordinate unit factor"),&pending),"convert local coordinates preserving physical placement semantics");
        } else if(action=="translate"||action=="rotate"||action=="scale"||action=="reset_transform") {
            std::string id=field(ip,request,"object_token");kind=state.cadKinds.at(id);
            check(gx3de_object_duplicate(cadObject(state,id),&pending),"snapshot source placement");
            if(action=="translate")check(gx3de_object_translate(pending,cadVector(ip,get(ip,request,"delta"),"translation"),1),"translate derived object");
            else if(action=="rotate")check(gx3de_object_rotate(pending,cadVector(ip,get(ip,request,"axis"),"rotation axis"),number(field(ip,request,"radians"),"angle"),cadVector(ip,get(ip,request,"pivot"),"pivot"),1),"rotate derived object");
            else if(action=="scale")check(gx3de_object_scale(pending,cadVector(ip,get(ip,request,"factors"),"scale factors"),cadVector(ip,get(ip,request,"pivot"),"pivot"),1),"scale derived object");
            else check(gx3de_object_reset_transform(pending),"reset derived placement");
        } else if(action=="mesh_append"||action=="mesh_merge"||action=="mesh_stitch"||action=="mesh_bridge") {
            auto* a=cadObject(state,field(ip,request,"base"));auto* b=cadObject(state,field(ip,request,"tool"));kind="mesh";
            if(action=="mesh_append")check(gx3de_mesh_append(a,b,&pending),"append complete meshes (not Boolean union)");
            else if(action=="mesh_merge")check(gx3de_mesh_merge(a,b,number(field(ip,request,"tolerance"),"world weld tolerance"),&pending),"merge complete meshes (not Boolean union)");
            else if(action=="mesh_stitch")check(gx3de_mesh_stitch(a,b,number(field(ip,request,"tolerance"),"world stitch tolerance"),&pending),"stitch compatible complete mesh boundaries");
            else check(gx3de_mesh_bridge(a,b,number(field(ip,request,"tolerance"),"world maximum bridge gap"),&pending),"bridge unique compatible complete mesh boundaries");
        } else if(action=="mesh_heal_seam"||action=="mesh_lod") {
            auto* source=cadObject(state,field(ip,request,"object_token"));kind="mesh";
            if(action=="mesh_heal_seam")check(gx3de_mesh_heal_seam(source,number(field(ip,request,"tolerance"),"world maximum seam gap"),&pending),"heal exactly two compatible open boundaries");
            else {
                const std::map<std::string,gx3de_mesh_lod_level> levels{{"preview",GX3DE_LOD_PREVIEW},{"low",GX3DE_LOD_LOW},{"medium",GX3DE_LOD_MEDIUM},{"high",GX3DE_LOD_HIGH},{"full",GX3DE_LOD_FULL}};
                auto level=levels.find(field(ip,request,"level"));if(level==levels.end())throw std::runtime_error("Choose preview, low, medium, high or full LOD");
                check(gx3de_mesh_lod(source,level->second,&pending),"derive explicit topology-preserving reduced mesh");
            }
        } else if(action=="mesh_boundaries") {
            auto* source=cadObject(state,field(ip,request,"object_token"));
            uint64_t maximum=integer(field(ip,request,"max_items"),"boundary item budget"),vertices=integer(field(ip,request,"max_vertices"),"boundary vertex budget");
            if(!maximum||maximum>4096||!vertices||vertices>65536)throw std::runtime_error("Boundary inspection requires 1..4096 items and 1..65536 vertices");
            uint64_t edges=0;auto counted=gx3de_mesh_boundary_edges(source,nullptr,0,&edges);if(counted!=GX3DE_OK&&counted!=GX3DE_RANGE)check(counted,"count complete boundary edges");
            uint64_t copied=std::min(edges,maximum);std::vector<uint32_t> pairs(copied*2);
            check(gx3de_mesh_boundary_edges_range(source,0,copied,pairs.data(),copied,&copied,&edges),"inspect bounded boundary edge page");
            Tcl_Obj* out=Tcl_NewDictObj();Tcl_Obj* edgeList=Tcl_NewListObj(0,nullptr);Tcl_Obj* loopList=Tcl_NewListObj(0,nullptr);
            for(uint64_t i=0;i<copied;++i){Tcl_Obj* pair=Tcl_NewListObj(0,nullptr);for(size_t j=0;j<2;++j)Tcl_ListObjAppendElement(ip,pair,Tcl_NewWideIntObj(pairs[2*i+j]));Tcl_ListObjAppendElement(ip,edgeList,pair);}
            gx3de_mesh_loops* loops=nullptr;check(gx3de_mesh_loops_create(source,&loops),"capture complete world boundary loops");
            try {
                uint64_t count=0,total=0;check(gx3de_mesh_loops_count(loops,&count),"count complete boundary loops");
                for(uint64_t i=0;i<std::min(count,maximum);++i){uint64_t n=0;check(gx3de_mesh_loops_size(loops,i,&n),"read complete loop size");Tcl_Obj* loop=Tcl_NewDictObj();Tcl_Obj* points=Tcl_NewListObj(0,nullptr);Tcl_Obj* ids=Tcl_NewListObj(0,nullptr);
                    uint64_t take=std::min(n,vertices-total);for(uint64_t j=0;j<take;++j){uint32_t index;gx3de_vec3 point;check(gx3de_mesh_loops_vertex(loops,i,j,&index,&point),"read captured world boundary vertex");Tcl_ListObjAppendElement(ip,ids,Tcl_NewWideIntObj(index));Tcl_ListObjAppendElement(ip,points,vecObj(point));}
                    total+=take;put(ip,loop,"loop_index",Tcl_NewWideIntObj(i));put(ip,loop,"vertex_count",Tcl_NewWideIntObj(n));put(ip,loop,"source_indices",ids);put(ip,loop,"world_points",points);put(ip,loop,"truncated",Tcl_NewIntObj(take<n));Tcl_ListObjAppendElement(ip,loopList,loop);}
                put(ip,out,"loop_count",Tcl_NewWideIntObj(count));put(ip,out,"loops_truncated",Tcl_NewIntObj(count>maximum));
            } catch(...){gx3de_mesh_loops_destroy(loops);throw;}
            check(gx3de_mesh_loops_destroy(loops),"release captured boundary loops");put(ip,out,"edge_count",Tcl_NewWideIntObj(edges));put(ip,out,"edges",edgeList);put(ip,out,"edges_truncated",Tcl_NewIntObj(edges>copied));put(ip,out,"loops",loopList);Tcl_SetObjResult(ip,out);return TCL_OK;
        } else if(action=="mesh_intersection_pairs") {
            auto* source=cadObject(state,field(ip,request,"object_token"));uint64_t maximum=integer(field(ip,request,"max_items"),"intersection item budget");
            if(!maximum||maximum>4096)throw std::runtime_error("Intersection inspection requires 1..4096 items");
            std::vector<gx3de_mesh_intersection_pair> pairs(maximum);for(auto& pair:pairs)pair.struct_size=sizeof pair;
            uint64_t required=0;auto result=gx3de_mesh_intersection_pairs(source,number(field(ip,request,"tolerance"),"world intersection tolerance"),pairs.data(),maximum,&required);
            if(result!=GX3DE_OK&&result!=GX3DE_RANGE)check(result,"inspect complete mesh intersections");
            Tcl_Obj* out=Tcl_NewDictObj();Tcl_Obj* entries=Tcl_NewListObj(0,nullptr);
            for(uint64_t i=0;i<std::min(required,maximum);++i){Tcl_Obj* pair=Tcl_NewDictObj();put(ip,pair,"triangle_a",Tcl_NewWideIntObj(pairs[i].triangle_a));put(ip,pair,"triangle_b",Tcl_NewWideIntObj(pairs[i].triangle_b));put(ip,pair,"witness",vecObj(pairs[i].world_witness));Tcl_ListObjAppendElement(ip,entries,pair);}
            put(ip,out,"intersecting_pairs",Tcl_NewWideIntObj(required));put(ip,out,"pairs",entries);put(ip,out,"truncated",Tcl_NewIntObj(required>maximum));Tcl_SetObjResult(ip,out);return TCL_OK;
        } else if(action=="clean"||action=="weld"||action=="orient"||action=="heal") {
            auto* source=cadObject(state,field(ip,request,"object_token"));kind=state.cadKinds.at(field(ip,request,"object_token"));
            if(action=="clean")check(gx3de_mesh_clean_duplicates(source,&pending),"clean duplicate mesh faces");
            else if(action=="weld")check(gx3de_mesh_weld(source,number(field(ip,request,"tolerance"),"weld tolerance"),&pending),"weld complete mesh");
            else if(action=="orient")check(gx3de_mesh_orient_normals(source,&pending),"orient complete mesh normals");
            else check(gx3de_brep_heal(source,number(field(ip,request,"tolerance"),"healing tolerance"),&pending),"heal exact B-Rep");
        } else if(action=="clip"||action=="clip_cap") {
            auto* source=cadObject(state,field(ip,request,"object_token"));kind=state.cadKinds.at(field(ip,request,"object_token"));
            Tcl_Obj* frame=get(ip,request,"plane");
            check(gx3de_plane_create(state.cadScene,cadVector(ip,get(ip,frame,"origin"),"plane origin"),cadVector(ip,get(ip,frame,"normal"),"plane normal"),cadVector(ip,get(ip,frame,"u_axis"),"plane U axis"),&plane),"create captured clipping plane");
            int positive=0;if(!get(ip,request,"keep_positive")||Tcl_GetBooleanFromObj(ip,get(ip,request,"keep_positive"),&positive)!=TCL_OK)throw std::runtime_error("Choose an explicit clipping side");
            if(kind=="brep")check(gx3de_brep_clip(source,plane,positive,&pending),"clip exact solid");
            else if(action=="clip_cap")check(gx3de_mesh_clip_capped(source,plane,positive,number(field(ip,request,"tolerance"),"cap tolerance"),&pending),"clip and cap complete mesh");
            else check(gx3de_mesh_clip(source,plane,positive,&pending),"clip complete mesh");
            check(gx3de_plane_destroy(plane),"release clipping plane");plane=nullptr;
        } else if(action=="self_intersections") {
            uint64_t count=0;check(gx3de_mesh_self_intersections(cadObject(state,field(ip,request,"object_token")),number(field(ip,request,"tolerance"),"intersection tolerance"),&count),"check complete mesh intersections");
            Tcl_Obj* out=Tcl_NewDictObj();put(ip,out,"intersecting_pairs",Tcl_NewWideIntObj(count));Tcl_SetObjResult(ip,out);return TCL_OK;
        } else if(action=="describe") {Tcl_SetObjResult(ip,cadObjectInfo(ip,state,field(ip,request,"object_token")));return TCL_OK;
        } else if(action=="delete") {
            std::string id=field(ip,request,"object_token");check(gx3de_object_destroy(cadObject(state,id)),"delete retained geometry");state.cadObjects.erase(id);state.cadKinds.erase(id);
            Tcl_SetObjResult(ip,Tcl_NewStringObj("deleted",-1));return TCL_OK;
        } else if(action=="transform") {
            auto values=cadList(ip,get(ip,request,"matrix"));if(values.size()!=16)throw std::runtime_error("Native3D transform needs 16 finite matrix coefficients");
            gx3de_mat4 matrix;for(size_t i=0;i<16;++i)matrix.m[i]=number(str(values[i]),"transform coefficient");
            std::string id=field(ip,request,"object_token");auto* source=cadObject(state,id);kind=state.cadKinds.at(id);
            if(field(ip,request,"mode")=="relative_world") {
                gx3de_mat4 original,composed{};check(gx3de_object_world_transform_get(source,&original),"read source world placement");
                for(size_t c=0;c<4;++c)for(size_t r=0;r<4;++r)for(size_t k=0;k<4;++k)composed.m[c*4+r]+=matrix.m[k*4+r]*original.m[c*4+k];
                matrix=composed;
            } else if(!field(ip,request,"mode").empty()&&field(ip,request,"mode")!="absolute")throw std::runtime_error("Transform mode must be absolute or relative_world");
            check(gx3de_object_duplicate(source,&pending),"snapshot source geometry before transformation");
            check(gx3de_object_set_transform(pending,&matrix),"set derived object transform");
        } else if(action=="export"||action=="export_local") {
            auto* object=cadObject(state,field(ip,request,"object_token"));std::string format=field(ip,request,"format"),path=field(ip,request,"path");
            if(action=="export_local") {
                check(gx3de_object_duplicate(object,&pending),"copy immutable local geometry for persistence");
                gx3de_mat4 identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
                check(gx3de_object_set_transform(pending,&identity),"export local geometry independently of placement");object=pending;
            }
            if(format=="step")check(gx3de_brep_write_step(object,path.c_str(),number(field(ip,request,"millimeters_per_working_unit"),"STEP unit scale")),"stage exact STEP");
            else if(format=="vtp"&&state.cadKinds.at(field(ip,request,"object_token"))=="scientific")check(gx3de_scientific_write_vtp(object,path.c_str()),"stage lossless scientific PolyData");
            else if(format=="stl"||format=="vtp")check(gx3de_mesh_write_file(object,format=="stl"?1u:2u,path.c_str()),"stage complete mesh");
            else throw std::runtime_error("Native3D staged export supports STEP, STL or VTP");
            if(pending){gx3de_object_destroy(pending);pending=nullptr;}
            Tcl_SetObjResult(ip,Tcl_NewStringObj("staged",-1));return TCL_OK;
        } else throw std::runtime_error("Unknown Native3D geometry operation");
        if((action=="load_step"||action=="restore_step"||action=="load_mesh")&&get(ip,request,"matrix")) {
            auto values=cadList(ip,get(ip,request,"matrix"));if(values.size()!=16)throw std::runtime_error("Saved placement needs 16 finite coefficients");
            gx3de_mat4 matrix;for(size_t i=0;i<16;++i)matrix.m[i]=number(str(values[i]),"saved placement");
            check(gx3de_object_set_transform(pending,&matrix),"restore editable local placement");
        }
        if(get(ip,request,"object_token")) {
            uint32_t role=0;check(gx3de_object_geometry_role_get(cadObject(state,field(ip,request,"object_token")),&role),"read derived geometry role");
            check(gx3de_object_geometry_role_set(pending,role),"preserve derived geometry role");
        }
        retained=cadRetain(state,pending,kind);pending=nullptr;
        Tcl_Obj* result=cadObjectInfo(ip,state,retained);
        if(action=="constraint_solve"){put(ip,result,"constraint_status",Tcl_NewWideIntObj(solved.status));put(ip,result,"maximum_residual",Tcl_NewDoubleObj(solved.maximum_residual));put(ip,result,"satisfied_count",Tcl_NewWideIntObj(solved.satisfied_count));}
        for(auto* constraint:constraints)gx3de_constraint_destroy(constraint);
        for(auto* anchor:anchors)gx3de_anchor_destroy(anchor);
        for(auto* captured:constraintPlanes)gx3de_plane_destroy(captured);
        Tcl_SetObjResult(ip,result);return TCL_OK;
    } catch(const std::exception& e) {
        if(measurement)gx3de_measure_destroy(measurement);
        for(auto* constraint:constraints)gx3de_constraint_destroy(constraint);
        for(auto* anchor:anchors)gx3de_anchor_destroy(anchor);
        for(auto* captured:constraintPlanes)gx3de_plane_destroy(captured);
        if(!retained.empty()){gx3de_object_destroy(state.cadObjects.at(retained));state.cadObjects.erase(retained);state.cadKinds.erase(retained);}
        if(pending)gx3de_object_destroy(pending);
        if(profile)gx3de_profile_destroy(profile);
        if(plane)gx3de_plane_destroy(plane);
        if(step)gx3de_step_close(step);
        if(section)gx3de_section_destroy(section);
        error(ip,e);return TCL_ERROR;
    }
}

// Each retained document scene has an independent kernel/handle namespace.
// The renderer remains a separate cache. A staged history scene can coexist
// with the active scene until the authoritative document transaction commits.
int cadDispatch(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]) {
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"owner_scope action request");return TCL_ERROR;}
    auto& host=*static_cast<State*>(data);
    std::string scope=str(args[1]),action=str(args[2]);bool created=false;
    try {
        if(scope.empty())throw std::runtime_error("Native3D requires an explicit document lifetime scope");
        auto found=host.cadScopes.find(scope);
        if(action=="open"&&found==host.cadScopes.end()) {
            if(host.cadScopes.size()>=64)throw std::runtime_error("Native3D retained scene budget exceeded; close unused scopes");
            auto owned=std::make_unique<State>();owned->cadPrefix+=scope+"-";
            found=host.cadScopes.emplace(scope,std::move(owned)).first;created=true;
        }
        if(found==host.cadScopes.end())throw std::runtime_error("Native3D document scope is closed or stale");
        int result=cadCall(found->second.get(),ip,argc,args);
        if((action=="close"&&result==TCL_OK)||(created&&result!=TCL_OK))host.cadScopes.erase(found);
        return result;
    } catch(const std::exception& e) {
        if(created)host.cadScopes.erase(scope);
        error(ip,e);return TCL_ERROR;
    }
}
