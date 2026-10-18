// SPDX-License-Identifier: GPL-3.0-or-later
// Application bridge: Viewer Provider dictionaries -> public GX3DE C ABI.
#include <tcl.h>
#include "native_3d_engine_api_v1.h"
#include "native_3d_scientific_figure_api_v1.h"
#include "native_3d_field_api_v1.h"
#include "native_3d_animation_api_v1.h"
#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <iostream>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif
#include <fstream>
#include <filesystem>
#include <limits>
#include <memory>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {
void check(gx3de_result r, const char *operation) {
    if (r != GX3DE_OK) throw std::runtime_error(std::string(operation)+": "+gx3de_result_name(r));
}
void checkRender(gx3de_target *target,gx3de_result result,const char *operation) {
    if(result==GX3DE_OK)return;
    char detail[1024]{};uint64_t needed=0;
    if(target)gx3de_target_render_diagnostics(target,detail,sizeof detail,&needed);
    throw std::runtime_error(std::string(operation)+": "+gx3de_result_name(result)+
        (detail[0]?std::string("; ")+detail:std::string()));
}
Tcl_Obj *get(Tcl_Interp *ip, Tcl_Obj *dict, const char *key) {
    Tcl_Obj *value=nullptr;
    Tcl_Obj *keyObject=Tcl_NewStringObj(key,-1);
    Tcl_IncrRefCount(keyObject);
    int result=Tcl_DictObjGet(ip,dict,keyObject,&value);
    Tcl_DecrRefCount(keyObject);
    if (result!=TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
    return value;
}
std::string str(Tcl_Obj *object) { return object ? Tcl_GetString(object) : ""; }
std::string field(Tcl_Interp *ip,Tcl_Obj *dict,const char *key) { return str(get(ip,dict,key)); }
double number(const std::string &s,const char *name) {
    if (s.empty()) throw std::runtime_error(std::string("Missing ")+name);
    size_t used=0; double n=std::stod(s,&used);
    if (used!=s.size() || !std::isfinite(n)) throw std::runtime_error(std::string("Invalid ")+name);
    return n;
}
uint64_t integer(const std::string &s,const char *name) {
    if (s.empty()) throw std::runtime_error(std::string("Missing ")+name);
    size_t used=0; auto n=std::stoull(s,&used);
    if (used!=s.size()) throw std::runtime_error(std::string("Invalid ")+name);
    return n;
}
bool yes(const std::string &s) { return s=="1" || s=="true"; }
std::vector<std::string> split(const std::string &s,char delimiter) {
    std::vector<std::string> out; size_t start=0;
    while (true) {
        size_t stop=s.find(delimiter,start);
        out.push_back(s.substr(start,stop-start));
        if (stop==std::string::npos) return out;
        start=stop+1;
    }
}
gx3de_vec3 vec(const std::string &s,const char *name) {
    auto parts=split(s,';');if (parts.size()!=3) throw std::runtime_error(std::string(name)+" must have three components");
    return {number(parts[0],name),number(parts[1],name),number(parts[2],name)};
}
gx3de_rgb rgb(const std::string &s,const char *name) {
    gx3de_vec3 v=vec(s,name);return {v.x,v.y,v.z};
}
void put(Tcl_Interp *ip,Tcl_Obj *dict,const char *key,Tcl_Obj *value) {
    if (Tcl_DictObjPut(ip,dict,Tcl_NewStringObj(key,-1),value)!=TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
}
Tcl_Obj *vecObj(gx3de_vec3 v) {
    Tcl_Obj *list=Tcl_NewListObj(0,nullptr);
    Tcl_ListObjAppendElement(nullptr,list,Tcl_NewDoubleObj(v.x));
    Tcl_ListObjAppendElement(nullptr,list,Tcl_NewDoubleObj(v.y));
    Tcl_ListObjAppendElement(nullptr,list,Tcl_NewDoubleObj(v.z));
    return list;
}
Tcl_Obj *matrixObj(const gx3de_mat4 &matrix) {
    Tcl_Obj *list=Tcl_NewListObj(0,nullptr);
    for(double value:matrix.m)Tcl_ListObjAppendElement(nullptr,list,Tcl_NewDoubleObj(value));
    return list;
}
struct State;
struct FrameSource {State* state=nullptr;Tcl_Interp* interp=nullptr;Tcl_Obj* layer=nullptr;
                    std::string layerId;};
struct State {
    std::map<std::string,std::unique_ptr<State>> cadScopes;
    gx3de_engine *cadEngine=nullptr;
    gx3de_scene *cadScene=nullptr;
    std::string cadScope;
    uint64_t cadSerial=0;
    std::string cadPrefix="native3d#"+std::to_string(std::chrono::system_clock::now().time_since_epoch().count())+"-";
    std::map<std::string,gx3de_object*> cadObjects;
    std::map<std::string,std::string> cadKinds;
    std::map<std::string,gx3de_profile*> cadProfiles;
    std::map<std::string,gx3de_group*> cadGroups;
    std::map<std::string,std::vector<std::string>> cadGroupMembers;
    gx3de_engine *engine=nullptr;
    gx3de_scene *scene=nullptr;
    gx3de_view *view=nullptr;
    gx3de_target *target=nullptr;
    gx3de_viewport *viewport=nullptr;
    gx3de_gizmo *gizmo=nullptr;
    gx3de_view_manipulation *planeManip=nullptr;
    uint32_t planeManipTarget=0,planeManipSlot=0;
    gx3de_animation *timeline=nullptr;
    gx3de_object *gizmoObject=nullptr;
    std::string gizmoLayer;
    std::vector<std::pair<gx3de_object*,std::string>> objects;
    std::vector<std::unique_ptr<FrameSource>> frameSources;
    std::vector<std::pair<std::string,gx3de_animation_layer*>> timelineLayers;
    std::vector<std::pair<std::string,gx3de_anchor*>> annotationAnchors;
    bool autoFitted=false;
    void clearRender() {
        if(planeManip) {gx3de_view_manipulation_end(planeManip,0);planeManip=nullptr;}
        if(gizmo) {gx3de_gizmo_destroy(gizmo);gizmo=nullptr;gizmoObject=nullptr;gizmoLayer.clear();}
        if(timeline) {gx3de_animation_destroy(timeline);timeline=nullptr;}
        for(auto& source:frameSources)if(source->layer)Tcl_DecrRefCount(source->layer);
        frameSources.clear();timelineLayers.clear();
        objects.clear();
        annotationAnchors.clear();
        autoFitted=false;
        if (target) {gx3de_target_destroy(target);target=nullptr;viewport=nullptr;}
        if (scene) {gx3de_scene_destroy(scene);scene=nullptr;view=nullptr;}
        if (engine) {gx3de_engine_destroy(engine);engine=nullptr;}
    }
    void clearCad() {
        cadScopes.clear();
        for(auto& entry:cadProfiles)gx3de_profile_destroy(entry.second);
        cadProfiles.clear();cadGroups.clear();cadGroupMembers.clear();cadObjects.clear();cadKinds.clear();cadScope.clear();
        if(cadScene){gx3de_scene_destroy(cadScene);cadScene=nullptr;}
        if(cadEngine){gx3de_engine_destroy(cadEngine);cadEngine=nullptr;}
    }
    void clear(){clearRender();clearCad();}
    ~State(){clear();}
    void add(Tcl_Interp *ip,gx3de_object *object,const std::string &id,Tcl_Obj *layer,bool visible,double opacity) {
        check(gx3de_object_set_visible(object,visible?1u:0u),"set visibility");
        check(gx3de_object_set_opacity(object,opacity),"set opacity");
        gx3de_object_style style{};style.struct_size=sizeof style;
        std::string mode=field(ip,layer,"representation");
        if(mode=="surface")style.mode=GX3DE_DISPLAY_SURFACE;
        else if(mode=="wireframe")style.mode=GX3DE_DISPLAY_WIREFRAME;
        else if(mode=="surface_edges")style.mode=GX3DE_DISPLAY_SURFACE_EDGES;
        else if(mode=="points")style.mode=GX3DE_DISPLAY_POINTS;
        else throw std::runtime_error("Unsupported object representation: "+mode);
        style.color=rgb(field(ip,layer,"base_color"),"base color");
        style.line_width=number(field(ip,layer,"line_width"),"line width");
        style.point_size=number(field(ip,layer,"point_size"),"point size");
        style.backface_culling=yes(field(ip,layer,"backface_culling"));
        style.scalar_coloring=yes(field(ip,layer,"scalar_coloring"))||!field(ip,layer,"scalar_array").empty();
        check(gx3de_object_style_set(object,&style),"set object style");
        std::string transform=field(ip,layer,"local_transform");
        if(!transform.empty()) {
            auto values=split(transform,';');if(values.size()!=16)throw std::runtime_error("Local transform needs 16 values");
            gx3de_mat4 matrix{};for(size_t i=0;i<16;++i)matrix.m[i]=number(values[i],"local transform");
            check(gx3de_object_set_transform(object,&matrix),"set persisted object transform");
        }
        if(auto descriptor=get(ip,layer,"texture")) {
            if(!str(descriptor).empty() && uint64_t(std::count_if(objects.begin(),objects.end(),[&](const auto& entry){return entry.second==id;}))==integer(field(ip,descriptor,"occurrence_index"),"texture source occurrence")) {
                gx3de_texture *texture=nullptr;
                check(gx3de_texture_load_file(engine,field(ip,descriptor,"source_path").c_str(),&texture),"load owned RGBA texture");
                try {
                    gx3de_texture_info info{};info.struct_size=sizeof info;check(gx3de_texture_info_get(texture,&info),"inspect RGBA texture");
                    if(info.channels!=4)throw std::runtime_error("Managed texture must retain actual RGBA channels");
                    gx3de_planar_texture_spec spec{};spec.struct_size=sizeof spec;
                    spec.source_triangle=integer(field(ip,descriptor,"source_triangle"),"source triangle");
                    spec.local_anchor=vec(field(ip,descriptor,"local_anchor"),"object-local texture anchor");
                    spec.anchor_u=number(field(ip,descriptor,"anchor_u"),"texture U anchor");spec.anchor_v=number(field(ip,descriptor,"anchor_v"),"texture V anchor");
                    spec.width=number(field(ip,descriptor,"width"),"physical texture width");spec.height=number(field(ip,descriptor,"height"),"physical texture height");
                    spec.rotation_radians=number(field(ip,descriptor,"rotation_radians"),"texture rotation");
                    spec.flip_u=yes(field(ip,descriptor,"flip_u"));spec.flip_v=yes(field(ip,descriptor,"flip_v"));
                    gx3de_planar_texture *assignment=nullptr;
                    check(gx3de_object_planar_texture_add(object,texture,&spec,&assignment),"assign existing native planar texture");
                } catch(...) {gx3de_texture_destroy(texture);throw;}
                check(gx3de_texture_destroy(texture),"release texture loader handle");
            }
        }
        objects.emplace_back(object,id);
    }
};
void applyPresentation(Tcl_Interp *ip,gx3de_object *object,Tcl_Obj *layer,bool hasVectors) {
    gx3de_scientific_presentation presentation{};presentation.struct_size=sizeof presentation;
    std::string map=field(ip,layer,"colormap");
    if(map==""||map=="viridis")presentation.colormap=GX3DE_COLORMAP_VIRIDIS;
    else if(map=="cool_warm")presentation.colormap=GX3DE_COLORMAP_COOL_WARM;
    else if(map=="grayscale")presentation.colormap=GX3DE_COLORMAP_GRAYSCALE;
    else throw std::runtime_error("Unsupported colormap: "+map);
    std::string range=field(ip,layer,"scalar_range");
    if(!range.empty()) {
        auto parts=split(range,';');if(parts.size()!=2)throw std::runtime_error("Invalid scalar range");
        presentation.scalar_min=number(parts[0],"scalar minimum");presentation.scalar_max=number(parts[1],"scalar maximum");presentation.use_scalar_range=1;
    }
    presentation.sphere_glyphs=field(ip,layer,"kind")=="points"||field(ip,layer,"representation")=="points";
    // Ordinary scientific scatter can request native point rendering, avoiding
    // sphere tessellation. Existing structural/mesh defaults remain unchanged.
    if(field(ip,layer,"sphere_glyphs")=="0")presentation.sphere_glyphs=0;
    presentation.show_vectors=hasVectors?1u:0u;
    presentation.max_vector_glyphs=2000;
    check(gx3de_scientific_presentation_set(object,&presentation),"set scientific presentation");
}
std::vector<std::string> csvRecord(const std::string &line,char delimiter) {
    std::vector<std::string> out; std::string item;bool quoted=false;
    for(size_t i=0;i<line.size();++i) {
        char ch=line[i];
        if (quoted) {if(ch=='"') {if(i+1<line.size()&&line[i+1]=='"'){item+='"';++i;}else quoted=false;}else item+=ch;}
        else if(ch==delimiter){out.push_back(item);item.clear();}
        else if(ch=='"'&&item.empty()) quoted=true;
        else item+=ch;
    }
    if(quoted) throw std::runtime_error("Unterminated CSV quotation");
    out.push_back(item);return out;
}
char csvDelimiter(const std::string &line) {
    char best=',';size_t count=0;
    for(char c:{',',';','\t'}) {auto fields=csvRecord(line,c);if(fields.size()>count){best=c;count=fields.size();}}
    return best;
}
size_t column(Tcl_Interp *ip,Tcl_Obj *layer,const char *key,const std::vector<std::string> &header,bool required) {
    std::string value=field(ip,layer,key);
    if(value.empty()) {if(required) throw std::runtime_error(std::string("Missing Dataset ")+key);return SIZE_MAX;}
    if(std::all_of(value.begin(),value.end(),[](unsigned char c){return std::isdigit(c)!=0;})) {
        uint64_t index=integer(value,key);if(index>=header.size()) throw std::runtime_error("Dataset column outside CSV header");return static_cast<size_t>(index);
    }
    auto it=std::find(header.begin(),header.end(),value);
    if(it==header.end()) throw std::runtime_error(std::string("Dataset column missing: ")+value);
    return static_cast<size_t>(it-header.begin());
}
gx3de_object *datasetObject(Tcl_Interp *ip,gx3de_scene *scene,Tcl_Obj *layer,
                            gx3de_animation *timeline=nullptr) {
    std::string path=field(ip,layer,"dataset_path");
    std::ifstream in(path);if(!in) throw std::runtime_error("Cannot open Dataset CSV: "+path);
    std::string line;if(!std::getline(in,line)) throw std::runtime_error("Dataset CSV is empty");
    char delimiter=csvDelimiter(line);auto header=csvRecord(line,delimiter);
    size_t ix=column(ip,layer,"x_column",header,true),iy=column(ip,layer,"y_column",header,true),iz=column(ip,layer,"z_column",header,true);
    size_t is=column(ip,layer,"scalar_column",header,false);
    size_t ir=column(ip,layer,"radius_column",header,false);
    size_t io=column(ip,layer,"opacity_column",header,false);
    std::vector<size_t> vectors;
    std::string vectorColumns=field(ip,layer,"vector_columns");
    if(!vectorColumns.empty()) {
        auto parts=split(vectorColumns,';');if(parts.size()!=3) throw std::runtime_error("Vector attribute needs three columns");
        for(auto &part:parts){auto idx=integer(part,"vector column");if(idx>=header.size())throw std::runtime_error("Vector column outside CSV header");vectors.push_back(static_cast<size_t>(idx));}
    }
    std::vector<gx3de_vec3> points;std::vector<double> scalar,vector,radius,opacityValues;
    size_t bytes=0;size_t row=1;
    while(std::getline(in,line)) {
        ++row;bytes+=line.size()+1;
        if(timeline&&(row%1024)==0){uint32_t cancelled=0;
            check(gx3de_animation_cancel_requested(timeline,&cancelled),"check timeline cancellation");
            if(cancelled)throw std::runtime_error("Timeline frame loading cancelled");}
        if(bytes>256u*1024u*1024u || points.size()>=1000000u) throw std::runtime_error("Dataset display budget exceeded (256 MiB or 1,000,000 points)");
        if(line.empty()) continue;
        auto values=csvRecord(line,delimiter);
        if(values.size()!=header.size()) throw std::runtime_error("Dataset CSV column count differs on row "+std::to_string(row));
        points.push_back({number(values[ix],"X"),number(values[iy],"Y"),number(values[iz],"Z")});
        if(is!=SIZE_MAX) scalar.push_back(number(values[is],"scalar"));
        if(ir!=SIZE_MAX) radius.push_back(number(values[ir],"radius"));
        if(io!=SIZE_MAX) opacityValues.push_back(number(values[io],"point opacity"));
        for(size_t columnId:vectors) vector.push_back(number(values[columnId],"vector"));
    }
    if(points.empty()) throw std::runtime_error("Dataset has no 3D points");
    std::vector<gx3de_scientific_cell_input> cells;
    std::vector<uint64_t> ids(points.size());for(size_t i=0;i<ids.size();++i)ids[i]=i;
    bool trajectory=field(ip,layer,"kind")=="trajectory";
    if(trajectory) {
        gx3de_scientific_cell_input cell{};cell.struct_size=sizeof cell;cell.type=GX3DE_SCI_CELL_POLYLINE;cell.point_ids=ids.data();cell.point_count=ids.size();cells.push_back(cell);
    } else {
        cells.reserve(points.size());
        for(size_t i=0;i<points.size();++i){gx3de_scientific_cell_input cell{};cell.struct_size=sizeof cell;cell.type=GX3DE_SCI_CELL_VERTEX;cell.point_ids=&ids[i];cell.point_count=1;cells.push_back(cell);}
    }
    std::vector<gx3de_scientific_array_input> arrays;
    if(!scalar.empty()) {gx3de_scientific_array_input a{};a.struct_size=sizeof a;a.association=GX3DE_SCI_ASSOC_POINT;a.components=1;a.name_utf8="Selected scalar";a.values=scalar.data();a.tuple_count=points.size();arrays.push_back(a);}
    if(!vector.empty()) {gx3de_scientific_array_input a{};a.struct_size=sizeof a;a.association=GX3DE_SCI_ASSOC_POINT;a.components=3;a.name_utf8="Selected vector";a.values=vector.data();a.tuple_count=points.size();arrays.push_back(a);}
    int64_t radiusIndex=-1;
    if(!radius.empty()) {radiusIndex=static_cast<int64_t>(arrays.size());gx3de_scientific_array_input a{};a.struct_size=sizeof a;a.association=GX3DE_SCI_ASSOC_POINT;a.components=1;a.name_utf8="Selected radius";a.values=radius.data();a.tuple_count=points.size();arrays.push_back(a);}
    int64_t opacityIndex=-1;
    if(!opacityValues.empty()) {opacityIndex=static_cast<int64_t>(arrays.size());gx3de_scientific_array_input a{};a.struct_size=sizeof a;a.association=GX3DE_SCI_ASSOC_POINT;a.components=1;a.name_utf8="Selected opacity";a.values=opacityValues.data();a.tuple_count=points.size();arrays.push_back(a);}
    gx3de_scientific_polydata_spec spec{};spec.struct_size=sizeof spec;spec.points=points.data();spec.point_count=points.size();spec.cells=cells.data();spec.cell_count=cells.size();spec.arrays=arrays.data();spec.array_count=arrays.size();
    gx3de_object *object=nullptr;check(gx3de_scientific_create_polydata(scene,&spec,&object),"create Dataset 3D layer");
    gx3de_scientific_field_roles roles{};roles.struct_size=sizeof roles;roles.scalar_array=scalar.empty()?-1:0;roles.vector_array=vector.empty()?-1:(scalar.empty()?0:1);roles.radius_array=radiusIndex;roles.tube_radius=number(field(ip,layer,"tube_radius"),"tube radius");
    check(gx3de_scientific_field_roles_set(object,&roles),"set Dataset field roles");
    if(opacityIndex>=0)check(gx3de_scientific_opacity_array_set(object,opacityIndex),"set Dataset point opacity");
    applyPresentation(ip,object,layer,!vector.empty());
    return object;
}
void applyScientificRoles(Tcl_Interp *ip,gx3de_object *object,Tcl_Obj *layer) {
    gx3de_scientific_field_roles roles{};roles.struct_size=sizeof roles;
    roles.scalar_array=roles.vector_array=roles.radius_array=-1;
    for(auto entry:std::array<std::pair<const char*,int64_t*>,3>{{{"scalar_array",&roles.scalar_array},{"vector_array",&roles.vector_array},{"radius_array",&roles.radius_array}}}) {
        std::string name=field(ip,layer,entry.first);
        if(name.empty()) continue;
        uint64_t index=0;
        gx3de_result result=gx3de_scientific_array_find(object,GX3DE_SCI_ASSOC_POINT,name.c_str(),&index);
        if(result==GX3DE_NOT_FOUND) result=gx3de_scientific_array_find(object,GX3DE_SCI_ASSOC_CELL,name.c_str(),&index);
        check(result,"find scientific array");
        *entry.second=static_cast<int64_t>(index);
    }
    roles.tube_radius=number(field(ip,layer,"tube_radius"),"tube radius");
    check(gx3de_scientific_field_roles_set(object,&roles),"set scientific field roles");
    std::string opacityName=field(ip,layer,"opacity_array");
    if(!opacityName.empty()) {
        uint64_t index=0;
        check(gx3de_scientific_array_find(object,GX3DE_SCI_ASSOC_POINT,opacityName.c_str(),&index),"find point opacity array");
        check(gx3de_scientific_opacity_array_set(object,static_cast<int64_t>(index)),"set point opacity array");
    }
    std::string colorName=field(ip,layer,"color_array");
    if(!colorName.empty()) {
        uint64_t index=0;auto found=gx3de_scientific_array_find(object,GX3DE_SCI_ASSOC_POINT,colorName.c_str(),&index);
        if(found==GX3DE_NOT_FOUND)found=gx3de_scientific_array_find(object,GX3DE_SCI_ASSOC_CELL,colorName.c_str(),&index);
        check(found,"find direct RGB array");
        check(gx3de_scientific_color_array_set(object,static_cast<int64_t>(index)),"set direct RGB array");
    }
    applyPresentation(ip,object,layer,roles.vector_array>=0);
}
void importArtifact(Tcl_Interp *ip,State &state,const std::string &id,Tcl_Obj *layer,bool visible,double opacity,bool preview) {
    std::string path=field(ip,layer,"absolute_path"),format=field(ip,layer,"format");
    if(format=="obj"||format=="stl") {
        gx3de_mesh_import_spec spec{};spec.struct_size=sizeof spec;spec.format=format=="obj"?GX3DE_IMPORT_OBJ:GX3DE_IMPORT_STL;spec.path_utf8=path.c_str();
        gx3de_object *object=nullptr;
        gx3de_result imported=preview?gx3de_object_import_mesh_preview(state.scene,&spec,&object):
            gx3de_object_import_mesh(state.scene,&spec,&object);
        if(preview&&imported==GX3DE_UNSUPPORTED) {
            imported=gx3de_object_import_mesh(state.scene,&spec,&object);
        }
        check(imported,preview?"import mesh preview":"import mesh");
        state.add(ip,object,id,layer,visible,opacity);return;
    }
    if(format=="vtp"||format=="vtu"||format=="vti") {
        gx3de_scientific_import_spec spec{};spec.struct_size=sizeof spec;spec.format=format=="vtp"?GX3DE_SCIENTIFIC_VTP:(format=="vtu"?GX3DE_SCIENTIFIC_VTU:GX3DE_SCIENTIFIC_VTI);spec.path_utf8=path.c_str();
        gx3de_object *object=nullptr;check(gx3de_scientific_import(state.scene,&spec,&object),"import scientific artifact");
        if(field(ip,layer,"kind")=="isosurface") {
            auto parts=split(field(ip,layer,"isovalues"),';');std::vector<double> levels;for(auto &part:parts)levels.push_back(number(part,"isovalue"));
            std::vector<gx3de_object*> surfaces(levels.size(),nullptr);
            auto scalar=field(ip,layer,"scalar_array");
            check(gx3de_scientific_isosurfaces(object,scalar.c_str(),levels.data(),static_cast<uint32_t>(levels.size()),surfaces.data()),"derive isosurfaces");
            check(gx3de_object_destroy(object),"release source grid");
            for(auto *surface:surfaces) if(surface)state.add(ip,surface,id,layer,visible,opacity);
        } else {
            applyScientificRoles(ip,object,layer);
            if(field(ip,layer,"kind")=="volume") {
                uint64_t scalar=0;
                const auto name=field(ip,layer,"scalar_array");
                check(gx3de_scientific_array_find(object,GX3DE_SCI_ASSOC_POINT,
                    name.c_str(),&scalar),"find volume scalar");
                gx3de_field_volume_style volume{};volume.struct_size=sizeof volume;
                volume.enabled=1;volume.scalar_array=scalar;
                volume.sample_distance=number(field(ip,layer,"volume_sample_distance"),
                    "volume sample distance");
                auto points=split(field(ip,layer,"volume_transfer"),';');
                if(points.size()<2||points.size()>GX3DE_MAX_FIELD_TRANSFER_POINTS)
                    throw std::runtime_error("Volume transfer requires 2..16 points");
                volume.transfer_count=static_cast<uint32_t>(points.size());
                for(size_t i=0;i<points.size();++i){auto values=split(points[i],',');
                    if(values.size()!=5)throw std::runtime_error("Volume transfer point needs scalar,R,G,B,opacity");
                    volume.transfer[i]={number(values[0],"transfer scalar"),
                        number(values[1],"transfer red"),number(values[2],"transfer green"),
                        number(values[3],"transfer blue"),number(values[4],"transfer opacity")};
                }
                check(gx3de_field_volume_style_set(object,&volume),"set volume transfer");
            }
            state.add(ip,object,id,layer,visible,opacity);
        }
        return;
    }
    if(format=="step"||format=="stp") {
        gx3de_step_import_spec spec{};spec.struct_size=sizeof spec;spec.path_utf8=path.c_str();gx3de_step_document *document=nullptr;
        check(gx3de_step_open(state.engine,&spec,&document),"open STEP/XDE");
        try {
            gx3de_step_summary summary{};summary.struct_size=sizeof summary;check(gx3de_step_summary_get(document,&summary),"STEP summary");
            if(!field(ip,layer,"local_transform").empty()) {
                uint64_t occurrences=0;
                for(uint64_t i=0;i<summary.nodes;++i) {
                    gx3de_step_node node{};node.struct_size=sizeof node;check(gx3de_step_node_get(document,i,&node),"STEP node");
                    if(node.kind==GX3DE_STEP_PART_OCCURRENCE)++occurrences;
                }
                if(occurrences>1)throw std::runtime_error("A layer transform cannot represent multiple STEP occurrences; use a single-occurrence layer");
            }
            gx3de_step_mesh_spec mesh{};mesh.struct_size=sizeof mesh;
            mesh.linear_deflection=preview?0.7:0.15;mesh.angular_deflection=preview?1.2:0.5;
            mesh.weld_tolerance=1e-8;mesh.max_triangles=preview?100000:1000000;
            mesh.max_output_bytes=preview?32u*1024u*1024u:128u*1024u*1024u;
            for(uint64_t i=0;i<summary.nodes;++i) {
                gx3de_step_node node{};node.struct_size=sizeof node;check(gx3de_step_node_get(document,i,&node),"STEP node");
                if(node.kind!=GX3DE_STEP_PART_OCCURRENCE) continue;
                gx3de_object *object=nullptr;check(gx3de_step_instance_mesh_create(state.scene,document,i,&mesh,&object),"STEP occurrence mesh");state.add(ip,object,id,layer,visible,opacity);
            }
            check(gx3de_step_close(document),"close STEP/XDE");
        } catch(...) {gx3de_step_close(document);throw;}
        return;
    }
    throw std::runtime_error("Unsupported artifact format: "+format);
}
std::vector<Tcl_Obj*> listItems(Tcl_Interp* ip,Tcl_Obj* list){
    int count=0;Tcl_Obj** items=nullptr;
    if(!list||Tcl_ListObjGetElements(ip,list,&count,&items)!=TCL_OK)
        throw std::runtime_error("Invalid native animation list");
    return {items,items+count};
}
std::vector<std::string> timelineFrameIds(Tcl_Interp* ip,Tcl_Obj* view){
    std::vector<std::string> ids;
    for(auto* timeline:listItems(ip,get(ip,view,"timeline_definitions")))
        for(auto* track:listItems(ip,get(ip,timeline,"tracks")))
            for(auto* frame:listItems(ip,get(ip,track,"frames")))if(!str(frame).empty())ids.push_back(str(frame));
    return ids;
}
gx3de_object* objectByLayer(State& state,const std::string& id){
    gx3de_object* object=nullptr;
    for(const auto& entry:state.objects)if(entry.second==id){
        if(object)throw std::runtime_error("Field source must identify one object: "+id);
        object=entry.first;}
    if(!object)throw std::runtime_error("Field source layer is missing: "+id);
    return object;
}
gx3de_result loadTimelineFrame(gx3de_scene* scene,uint64_t frame,double time,void* user,gx3de_object** out){
    (void)scene;(void)frame;(void)time;
    auto* source=static_cast<FrameSource*>(user);auto& state=*source->state;
    *out=nullptr;size_t previous=state.objects.size();
    try{
        uint32_t cancelled=0;
        check(gx3de_animation_cancel_requested(state.timeline,&cancelled),"check timeline cancellation");
        if(cancelled)return GX3DE_UNSUPPORTED;
        Tcl_Obj* layer=source->layer;
        if(field(source->interp,layer,"source_mode")=="dataset"){
            gx3de_object* object=datasetObject(source->interp,state.scene,layer,state.timeline);
            state.add(source->interp,object,source->layerId,layer,true,
                      number(field(source->interp,layer,"opacity"),"timeline opacity"));
        }else importArtifact(source->interp,state,source->layerId,layer,true,
                            number(field(source->interp,layer,"opacity"),"timeline opacity"),false);
        check(gx3de_animation_cancel_requested(state.timeline,&cancelled),"check timeline cancellation");
        if(cancelled)throw std::runtime_error("Timeline frame loading cancelled");
        if(state.objects.size()!=previous+1)throw std::runtime_error("Timeline frame must create one object");
        *out=state.objects.back().first;state.objects.pop_back();return GX3DE_OK;
    }catch(const std::exception&){
        while(state.objects.size()>previous){auto* object=state.objects.back().first;
            state.objects.pop_back();gx3de_object_destroy(object);}
        return GX3DE_DEGENERATE;
    }
}
void refreshTimelineObjects(State& state){
    for(const auto& named:state.timelineLayers)
        state.objects.erase(std::remove_if(state.objects.begin(),state.objects.end(),
            [&](const auto& item){return item.second==named.first;}),state.objects.end());
    for(const auto& named:state.timelineLayers){gx3de_object* object=nullptr;
        if(gx3de_animation_layer_active_object_get(named.second,&object)==GX3DE_OK)
            state.objects.emplace_back(object,named.first);}
}
gx3de_animation_layer* timelineLayer(State& state,const std::string& id){
    for(const auto& entry:state.timelineLayers)if(entry.first==id)return entry.second;
    throw std::runtime_error("Timeline track is missing: "+id);
}
std::vector<gx3de_vec3> fieldSeeds(Tcl_Interp* ip,Tcl_Obj* definition){
    std::vector<gx3de_vec3> seeds;
    for(auto* item:listItems(ip,get(ip,definition,"seed_points")))
        seeds.push_back(vec(str(item),"field seed"));
    return seeds;
}
gx3de_field_line_spec lineSpec(Tcl_Interp* ip,Tcl_Obj* d,const std::vector<gx3de_vec3>& seeds){
    gx3de_field_line_spec spec{};spec.struct_size=sizeof(spec);
    std::string kind=field(ip,d,"seed_kind"),direction=field(ip,d,"direction");
    spec.seed_kind=kind=="line"?GX3DE_FIELD_SEED_LINE:(kind=="plane"?GX3DE_FIELD_SEED_PLANE:GX3DE_FIELD_SEED_POINTS);
    spec.seed_points=seeds.data();spec.seed_count=seeds.size();
    if(spec.seed_kind!=GX3DE_FIELD_SEED_POINTS){
        spec.seed_origin=vec(field(ip,d,"seed_origin"),"seed origin");
        spec.seed_u=vec(field(ip,d,"seed_u"),"seed U");
        spec.seed_u_count=static_cast<uint32_t>(integer(field(ip,d,"seed_u_count"),"seed U count"));
        if(spec.seed_kind==GX3DE_FIELD_SEED_PLANE){spec.seed_v=vec(field(ip,d,"seed_v"),"seed V");
            spec.seed_v_count=static_cast<uint32_t>(integer(field(ip,d,"seed_v_count"),"seed V count"));}
    }
    spec.direction=direction=="backward"?GX3DE_FIELD_BACKWARD:
        (direction=="both"?GX3DE_FIELD_BOTH:GX3DE_FIELD_FORWARD);
    spec.vector_array=integer(field(ip,d,"vector_array_index"),"vector array index");
    std::string scalar=field(ip,d,"scalar_array_index");
    spec.scalar_array=scalar.empty()?-1:static_cast<int64_t>(integer(scalar,"scalar array index"));
    spec.step_size=number(field(ip,d,"step_size"),"field step size");
    spec.min_vector_magnitude=number(field(ip,d,"min_magnitude"),"field minimum magnitude");
    spec.tube_radius=number(field(ip,d,"tube_radius"),"field tube radius");
    spec.max_steps_per_direction=integer(field(ip,d,"max_steps"),"field max steps");
    spec.max_output_points=integer(field(ip,d,"max_points"),"field max points");
    spec.max_memory_bytes=integer(field(ip,d,"max_memory_bytes"),"field max memory");
    return spec;
}
void sceneTimeline(Tcl_Interp* ip,State& state,Tcl_Obj* scene,Tcl_Obj* view){
    auto* layers=get(ip,scene,"layers");
    std::string active=field(ip,view,"active_timeline_id");
    Tcl_Obj* selected=nullptr;
    for(auto* t:listItems(ip,get(ip,view,"timeline_definitions")))
        if(field(ip,t,"id")==active)selected=t;
    if(!active.empty()&&!selected)throw std::runtime_error("Active timeline is missing: "+active);
    if(selected){
        check(gx3de_animation_create(state.scene,field(ip,selected,"unit").c_str(),&state.timeline),"create timeline");
        auto times=listItems(ip,get(ip,selected,"times"));
        for(auto* t:times)check(gx3de_animation_time_add(state.timeline,number(str(t),"frame time"),nullptr),"add time frame");
        for(auto* track:listItems(ip,get(ip,selected,"tracks"))){
            std::string id=field(ip,track,"id");gx3de_animation_layer* animationLayer=nullptr;
            check(gx3de_animation_layer_create(state.timeline,id.c_str(),&animationLayer),"create timeline track");
            state.timelineLayers.emplace_back(id,animationLayer);
            auto frames=listItems(ip,get(ip,track,"frames"));
            if(frames.size()!=times.size())throw std::runtime_error("Timeline track/time mismatch");
            for(size_t index=0;index<frames.size();++index){std::string layerId=str(frames[index]);
                if(layerId.empty())continue;
                Tcl_Obj* layer=get(ip,layers,layerId.c_str());
                if(!layer)throw std::runtime_error("Timeline frame layer is missing: "+layerId);
                auto source=std::make_unique<FrameSource>();source->state=&state;source->interp=ip;
                source->layer=layer;source->layerId=layerId;Tcl_IncrRefCount(layer);
                check(gx3de_animation_layer_frame_set(animationLayer,index,nullptr,loadTimelineFrame,source.get()),
                      "bind timeline frame");
                state.frameSources.push_back(std::move(source));
            }
        }
        check(gx3de_animation_set_resident_limit(state.timeline,64),"set timeline resident budget");
        check(gx3de_animation_set_memory_limit(state.timeline,256ull*1024*1024),"set timeline memory budget");
        std::string loop=field(ip,selected,"loop");
        check(gx3de_animation_mode_set(state.timeline,GX3DE_ANIM_NEAREST,
            loop=="loop"?GX3DE_ANIM_LOOP:(loop=="ping_pong"?GX3DE_ANIM_PING_PONG:GX3DE_ANIM_ONCE),
            number(field(ip,selected,"rate"),"playback rate")),"set timeline mode");
        check(gx3de_animation_playback_range_set(state.timeline,
            integer(field(ip,selected,"range_first"),"range first"),
            integer(field(ip,selected,"range_last"),"range last")),"set timeline range");
    }
    for(auto* definition:listItems(ip,get(ip,view,"field_definitions"))){
        std::string id=field(ip,definition,"id"),kind=field(ip,definition,"kind");
        std::string timelineId=field(ip,definition,"timeline_id");
        if(!timelineId.empty()&&timelineId!=active)continue;
        if(kind=="lines"){
            auto seeds=fieldSeeds(ip,definition);auto spec=lineSpec(ip,definition,seeds);
            if(!timelineId.empty()){
                auto* source=timelineLayer(state,field(ip,definition,"source_track"));
                gx3de_animation_layer* derived=nullptr;
                check(gx3de_animation_layer_create(state.timeline,id.c_str(),&derived),"create animated field lines");
                check(gx3de_animation_layer_bind_lines(derived,source,&spec),"bind animated field lines");
                state.timelineLayers.emplace_back(id,derived);
            }else{spec.field=objectByLayer(state,field(ip,definition,"source_layer"));
                gx3de_object* object=nullptr;gx3de_field_line_info info{};info.struct_size=sizeof(info);
                check(gx3de_field_lines_create(state.scene,&spec,&object,&info),"create field lines");
                state.objects.emplace_back(object,id);}
        }else if(kind=="slice"){
            gx3de_field_slice_spec spec{};spec.struct_size=sizeof(spec);
            spec.scalar_array=integer(field(ip,definition,"scalar_array_index"),"slice scalar index");
            spec.origin=vec(field(ip,definition,"origin"),"slice origin");
            spec.u_step=vec(field(ip,definition,"u_step"),"slice U step");
            spec.v_step=vec(field(ip,definition,"v_step"),"slice V step");
            spec.u_count=static_cast<uint32_t>(integer(field(ip,definition,"u_count"),"slice U count"));
            spec.v_count=static_cast<uint32_t>(integer(field(ip,definition,"v_count"),"slice V count"));
            spec.max_memory_bytes=integer(field(ip,definition,"max_memory_bytes"),"slice memory");
            if(!timelineId.empty()){
                auto* source=timelineLayer(state,field(ip,definition,"source_track"));
                gx3de_animation_layer* derived=nullptr;
                check(gx3de_animation_layer_create(state.timeline,id.c_str(),&derived),"create animated slice");
                check(gx3de_animation_layer_bind_slice(derived,source,&spec),"bind animated slice");
                state.timelineLayers.emplace_back(id,derived);
            }else{spec.field=objectByLayer(state,field(ip,definition,"source_layer"));
                gx3de_object* object=nullptr;check(gx3de_field_slice_create(state.scene,&spec,&object),"create slice");
                state.objects.emplace_back(object,id);}
        }else if(kind=="isosurface"){
            std::string name=field(ip,definition,"scalar_name");
            double value=number(field(ip,definition,"value"),"isovalue");
            if(!timelineId.empty()){
                auto* source=timelineLayer(state,field(ip,definition,"source_track"));
                gx3de_animation_layer* derived=nullptr;
                check(gx3de_animation_layer_create(state.timeline,id.c_str(),&derived),"create animated isosurface");
                check(gx3de_animation_layer_bind_isosurface(derived,source,name.c_str(),value),"bind animated isosurface");
                state.timelineLayers.emplace_back(id,derived);
            }else{auto* source=objectByLayer(state,field(ip,definition,"source_layer"));
                gx3de_object* object=nullptr;check(gx3de_scientific_isosurfaces(source,name.c_str(),&value,1,&object),"create isosurface");
                if(object)state.objects.emplace_back(object,id);}
        }else if(kind=="pathlines"){
            if(!selected||timelineId.empty())throw std::runtime_error("Pathlines require an active timeline");
            auto* source=timelineLayer(state,field(ip,definition,"source_track"));
            auto seeds=fieldSeeds(ip,definition);
            gx3de_field_pathline_spec spec{};spec.struct_size=sizeof(spec);
            spec.seed_points=seeds.data();spec.seed_count=seeds.size();
            spec.vector_array=integer(field(ip,definition,"vector_array_index"),"pathline vector index");
            std::string scalar=field(ip,definition,"scalar_array_index");
            spec.scalar_array=scalar.empty()?-1:static_cast<int64_t>(integer(scalar,"pathline scalar index"));
            spec.time_step=number(field(ip,definition,"time_step"),"pathline time step");
            spec.min_vector_magnitude=number(field(ip,definition,"min_magnitude"),"pathline min magnitude");
            spec.tube_radius=number(field(ip,definition,"tube_radius"),"pathline tube radius");
            spec.max_steps_per_seed=integer(field(ip,definition,"max_steps"),"pathline max steps");
            spec.max_output_points=integer(field(ip,definition,"max_points"),"pathline max points");
            spec.max_memory_bytes=integer(field(ip,definition,"max_memory_bytes"),"pathline memory");
            gx3de_animation_layer* derived=nullptr;
            check(gx3de_animation_layer_create(state.timeline,id.c_str(),&derived),"create animated pathlines");
            check(gx3de_animation_layer_bind_pathlines(derived,source,&spec),"bind animated pathlines");
            state.timelineLayers.emplace_back(id,derived);
        }
    }
    if(selected){
        check(gx3de_animation_seek_time(state.timeline,number(field(ip,selected,"current_time"),"current time")),"seek timeline");
        const std::string savedState=field(ip,selected,"state");
        if(savedState=="paused")check(gx3de_animation_pause(state.timeline),"restore paused timeline");
        else if(savedState=="playing")check(gx3de_animation_play(state.timeline),"restore playing timeline");
        else if(savedState!="stopped")throw std::runtime_error("Invalid stored timeline state");
        refreshTimelineObjects(state);
    }
}
struct Layer {std::string id;Tcl_Obj *value;int64_t order;};
void sceneAnnotations(Tcl_Interp *ip,State &state,Tcl_Obj *view) {
    Tcl_Obj *definitions=get(ip,view,"marker_definitions");
    int count=0;Tcl_Obj **items=nullptr;
    if(Tcl_ListObjGetElements(ip,definitions,&count,&items)!=TCL_OK)throw std::runtime_error("Invalid scene marker list");
    state.annotationAnchors.reserve(static_cast<size_t>(count));
    for(int i=0;i<count;++i) {
        auto *entry=items[i];std::string id=field(ip,entry,"id"),layer=field(ip,entry,"layer_id");
        uint64_t occurrence=integer(field(ip,entry,"occurrence_index"),"marker occurrence");
        gx3de_object *object=nullptr;
        for(const auto &candidate:state.objects)if(candidate.second==layer) {
            if(occurrence==0) {object=candidate.first;break;}--occurrence;
        }
        if(!object)throw std::runtime_error("Marker source occurrence is missing: "+id);
        gx3de_anchor *anchor=nullptr;
        check(gx3de_anchor_object_point(object,vec(field(ip,entry,"local_point"),"marker local point"),&anchor),"create marker anchor");
        gx3de_marker_style style{};style.struct_size=sizeof style;
        style.visible=yes(field(ip,entry,"visible"));
        std::string kind=field(ip,entry,"kind");
        style.kind=kind=="cross"?GX3DE_MARKER_CROSS:kind=="normal"?GX3DE_MARKER_NORMAL:
            kind=="tangent"?GX3DE_MARKER_TANGENT:GX3DE_MARKER_POINT;
        style.color=rgb(field(ip,entry,"color"),"marker color");
        style.size_pixels=number(field(ip,entry,"size_pixels"),"marker size");style.line_width=2;
        gx3de_marker *marker=nullptr;check(gx3de_marker_create_scene(state.scene,anchor,&style,&marker),"create scene marker");
        state.annotationAnchors.emplace_back(id,anchor);
    }
    definitions=get(ip,view,"measurement_definitions");
    if(Tcl_ListObjGetElements(ip,definitions,&count,&items)!=TCL_OK)throw std::runtime_error("Invalid scene measurement list");
    auto lookup=[&](const std::string &id)->gx3de_anchor* {
        auto it=std::find_if(state.annotationAnchors.begin(),state.annotationAnchors.end(),[&](const auto &a){return a.first==id;});
        if(it==state.annotationAnchors.end())throw std::runtime_error("Measurement marker missing: "+id);
        return it->second;
    };
    for(int i=0;i<count;++i) {
        auto *entry=items[i];std::string kind=field(ip,entry,"kind");
        gx3de_measure_kind measureKind=kind=="distance"?GX3DE_DISTANCE:kind=="delta_x"?GX3DE_DELTA_X:
            kind=="delta_y"?GX3DE_DELTA_Y:kind=="delta_z"?GX3DE_DELTA_Z:GX3DE_ANGLE_THREE_POINTS;
        gx3de_anchor *a=lookup(field(ip,entry,"marker_a")),*b=lookup(field(ip,entry,"marker_b"));
        gx3de_anchor *c=kind=="angle"?lookup(field(ip,entry,"marker_c")):nullptr;
        gx3de_measurement *measurement=nullptr;
        check(gx3de_measure_create(state.scene,measureKind,a,b,c,nullptr,&measurement),"create scene measurement");
        gx3de_measurement_style style{};style.struct_size=sizeof style;
        style.visible=yes(field(ip,entry,"visible"));style.show_value=yes(field(ip,entry,"show_value"));
        style.color=rgb(field(ip,entry,"color"),"measurement color");
        style.marker_size_pixels=number(field(ip,entry,"size_pixels"),"measurement marker size");
        style.line_width=number(field(ip,entry,"line_width"),"measurement line width");
        check(gx3de_measurement_style_set(measurement,&style),"set scene measurement style");
    }
}
void sceneCurves(Tcl_Interp *ip,State &state,Tcl_Obj *view) {
    Tcl_Obj *definitions=get(ip,view,"curve_definitions");int count=0;Tcl_Obj **items=nullptr;
    if(Tcl_ListObjGetElements(ip,definitions,&count,&items)!=TCL_OK)throw std::runtime_error("Invalid scene curve list");
    for(int i=0;i<count;++i) {
        Tcl_Obj *entry=items[i];std::string id=field(ip,entry,"id"),layer=field(ip,entry,"source_layer");
        uint64_t occurrence=integer(field(ip,entry,"occurrence_index"),"curve occurrence");
        gx3de_object *source=nullptr;
        for(const auto &candidate:state.objects)if(candidate.second==layer){if(occurrence==0){source=candidate.first;break;}--occurrence;}
        if(!source)throw std::runtime_error("Curve source occurrence is missing: "+id);
        gx3de_plane *plane=nullptr;
        check(gx3de_plane_create(state.scene,vec(field(ip,entry,"origin"),"curve plane origin"),
            vec(field(ip,entry,"normal"),"curve plane normal"),vec(field(ip,entry,"u_axis"),"curve plane U"),&plane),"create curve plane");
        gx3de_curve_style style{};style.struct_size=sizeof style;style.visible=yes(field(ip,entry,"visible"));
        style.color=rgb(field(ip,entry,"color"),"curve color");
        style.line_width=number(field(ip,entry,"line_width"),"curve line width");
        style.opacity=number(field(ip,entry,"opacity"),"curve opacity");
        std::string kind=field(ip,entry,"kind");
        if(kind=="section"||kind=="profile") {
            gx3de_section *section=nullptr;check(gx3de_section_create(source,plane,&section),"create section");
            gx3de_curve_style sectionStyle=style;
            if(kind=="profile")sectionStyle.visible=0;
            check(gx3de_section_style_set(section,&sectionStyle),"set section style");
            if(kind=="profile") {
                gx3de_profile *profile=nullptr;
                check(gx3de_profile_create(section,number(field(ip,entry,"join_tolerance"),"profile tolerance"),&profile),"create profile");
                check(gx3de_profile_style_set(profile,&style),"set profile style");
            }
        } else if(kind=="projection") {
            gx3de_brep_mesh_spec tessellation{};tessellation.struct_size=sizeof tessellation;
            tessellation.linear_deflection=0.15;tessellation.angular_deflection=0.5;
            tessellation.weld_tolerance=1e-8;tessellation.max_triangles=1000000;
            tessellation.max_output_bytes=128u*1024u*1024u;
            uint64_t vertices=0,triangles=0;
            gx3de_scientific_info scientific{};scientific.struct_size=sizeof scientific;
            const bool mesh=gx3de_object_counts(source,&vertices,&triangles)==GX3DE_OK;
            const bool data=gx3de_scientific_info_get(source,&scientific)==GX3DE_OK;
            gx3de_object *projection=nullptr;
            check(gx3de_object_project(source,plane,mesh||data?nullptr:&tessellation,&projection),"create projection");
            check(gx3de_object_set_visible(projection,style.visible),"set projection visibility");
            check(gx3de_object_set_opacity(projection,style.opacity),"set projection opacity");
            gx3de_object_style objectStyle{};objectStyle.struct_size=sizeof objectStyle;
            objectStyle.mode=GX3DE_DISPLAY_WIREFRAME;objectStyle.color=style.color;
            objectStyle.line_width=style.line_width;objectStyle.point_size=4;
            check(gx3de_object_style_set(projection,&objectStyle),"set projection style");
            state.objects.emplace_back(projection,id);
        } else throw std::runtime_error("Unknown derived curve kind: "+kind);
    }
}
// Explicit durable identity focus. Cell-center marker is presentation only;
// the source scientific object, connectivity and arrays remain untouched.
void logicalFocus(Tcl_Interp* ip,State& state,Tcl_Obj* reference) {
    auto layer=field(ip,reference,"layer_id"),association=field(ip,reference,"association");
    if(association!="cell"&&association!="point")throw std::runtime_error("Logical focus requires point or cell association");
    uint64_t wanted=integer(field(ip,reference,"logical_id"),"logical identity");
    for(auto& entry:state.objects)if(entry.second==layer){
        gx3de_scientific_info info{};info.struct_size=sizeof info;
        if(gx3de_scientific_info_get(entry.first,&info)!=GX3DE_OK)continue;
        uint64_t count=association=="cell"?info.cell_count:info.point_count;
        for(uint64_t i=0;i<count;++i){uint64_t logical=0;
            if(gx3de_scientific_logical_id(entry.first,association=="cell"?GX3DE_SCI_ASSOC_CELL:GX3DE_SCI_ASSOC_POINT,i,&logical)!=GX3DE_OK||logical!=wanted)continue;
            gx3de_vec3 center{0,0,0};
            if(association=="point")check(gx3de_scientific_point(entry.first,i,0,&center),"logical point focus");
            else {gx3de_scientific_cell_info cell{};cell.struct_size=sizeof cell;check(gx3de_scientific_cell_info_get(entry.first,i,&cell),"logical cell focus");
                for(uint64_t j=0;j<cell.point_count;++j){uint64_t id;gx3de_vec3 p;check(gx3de_scientific_cell_point_id(entry.first,i,j,&id),"cell vertex identity");check(gx3de_scientific_point(entry.first,id,0,&p),"cell vertex");center.x+=p.x/cell.point_count;center.y+=p.y/cell.point_count;center.z+=p.z/cell.point_count;}}
            gx3de_anchor* anchor=nullptr;check(gx3de_anchor_object_point(entry.first,center,&anchor),"logical feature anchor");check(gx3de_view_set_selection(state.view,anchor),"logical feature focus");return;
        }
    }
    throw std::runtime_error("Logical focus refers to an absent scientific identity");
}
void fillScene(Tcl_Interp *ip,State &state,Tcl_Obj *scene,bool preview) {
    Tcl_Obj *layers=get(ip,scene,"layers"),*view=get(ip,scene,"view");
    if(!layers||!view) throw std::runtime_error("Viewer scene is incomplete");
    std::vector<Layer> ordered;Tcl_DictSearch search;Tcl_Obj *key=nullptr,*value=nullptr;int done=0;
    if(Tcl_DictObjFirst(ip,layers,&search,&key,&value,&done)!=TCL_OK)throw std::runtime_error("Invalid Viewer layers");
    while(!done) {ordered.push_back({str(key),value,std::stoll(field(ip,value,"layer_order"))});Tcl_DictObjNext(&search,&key,&value,&done);}Tcl_DictObjDone(&search);
    std::sort(ordered.begin(),ordered.end(),[](const Layer &a,const Layer &b){return a.order<b.order||(a.order==b.order&&a.id<b.id);});
    const auto animatedFrames=timelineFrameIds(ip,view);
    for(const auto &layer:ordered) {
        if(std::find(animatedFrames.begin(),animatedFrames.end(),layer.id)!=animatedFrames.end())continue;
        bool visible=yes(field(ip,layer.value,"visible"));double opacity=number(field(ip,layer.value,"opacity"),"opacity");
        try {
            if(field(ip,layer.value,"source_mode")=="dataset") {gx3de_object *object=datasetObject(ip,state.scene,layer.value);state.add(ip,object,layer.id,layer.value,visible,opacity);}
            else if(field(ip,layer.value,"source_mode")=="memory_geometry") {
                // Display-only geometry enters the same public native mesh ABI.
                // It has no Dataset identity, path, publication or CAD authority.
                Tcl_Obj *vertices=get(ip,layer.value,"vertices"),*triangles=get(ip,layer.value,"triangles");
                int nv=0,nt=0;Tcl_Obj **vv=nullptr,**tt=nullptr;
                if(!vertices||!triangles||Tcl_ListObjGetElements(ip,vertices,&nv,&vv)!=TCL_OK||
                   Tcl_ListObjGetElements(ip,triangles,&nt,&tt)!=TCL_OK||nv<3||nv>10000||nt<1||nt>20000)
                    throw std::runtime_error("RAM geometry requires 3..10000 vertices and 1..20000 triangles");
                std::vector<gx3de_vec3> points;std::vector<uint32_t> indices;
                for(int i=0;i<nv;++i) {
                    int n=0;Tcl_Obj **xyz=nullptr;
                    if(Tcl_ListObjGetElements(ip,vv[i],&n,&xyz)!=TCL_OK||n!=3)throw std::runtime_error("RAM vertex requires XYZ");
                    points.push_back({number(str(xyz[0]),"X"),number(str(xyz[1]),"Y"),number(str(xyz[2]),"Z")});
                }
                for(int i=0;i<nt;++i) {
                    int n=0;Tcl_Obj **ids=nullptr;
                    if(Tcl_ListObjGetElements(ip,tt[i],&n,&ids)!=TCL_OK||n!=3)throw std::runtime_error("RAM triangle requires three indices");
                    for(int j=0;j<3;++j) {auto id=integer(str(ids[j]),"RAM triangle index");
                        if(id>=static_cast<uint64_t>(nv))throw std::runtime_error("RAM triangle index outside vertices");
                        indices.push_back(static_cast<uint32_t>(id));}
                }
                gx3de_object *object=nullptr;
                check(gx3de_object_create_mesh(state.scene,points.data(),points.size(),indices.data(),nt,&object),"create RAM display mesh");
                state.add(ip,object,layer.id,layer.value,visible,opacity);
            } else importArtifact(ip,state,layer.id,layer.value,visible,opacity,preview&&field(ip,layer.value,"texture").empty());
        } catch(const std::exception &e) {
            std::string source=field(ip,layer.value,"source_mode")=="artifact"?field(ip,layer.value,"resource_path"):field(ip,layer.value,"dataset_id");
            throw std::runtime_error("3D layer "+layer.id+" ("+source+"): "+e.what());
        }
    }
    gx3de_camera camera{};camera.struct_size=sizeof camera;check(gx3de_view_get_camera(state.view,&camera),"read camera");
    camera.position=vec(field(ip,view,"camera_position"),"camera position");camera.target=vec(field(ip,view,"camera_target"),"camera target");camera.up=vec(field(ip,view,"camera_up"),"camera up");camera.orthographic=field(ip,view,"projection")=="orthographic";
    if(camera.position.x==0&&camera.position.y==0&&camera.position.z==1&&
       camera.target.x==0&&camera.target.y==0&&camera.target.z==0&&!state.objects.empty()) {
        gx3de_bounds all{};bool have=false;
        for(const auto &entry:state.objects) {
            uint32_t visible=0;if(gx3de_object_get_visible(entry.first,&visible)!=GX3DE_OK||!visible)continue;
            gx3de_bounds one{};if(gx3de_object_bounds(entry.first,1,&one)!=GX3DE_OK)continue;
            if(!have){all=one;have=true;}
            else {all.min.x=std::min(all.min.x,one.min.x);all.min.y=std::min(all.min.y,one.min.y);all.min.z=std::min(all.min.z,one.min.z);
                  all.max.x=std::max(all.max.x,one.max.x);all.max.y=std::max(all.max.y,one.max.y);all.max.z=std::max(all.max.z,one.max.z);}
        }
        if(have) {
            camera.target={(all.min.x+all.max.x)/2,(all.min.y+all.max.y)/2,(all.min.z+all.max.z)/2};
            double dx=all.max.x-all.min.x,dy=all.max.y-all.min.y,dz=all.max.z-all.min.z;
            double radius=std::max(1.0,std::sqrt(dx*dx+dy*dy+dz*dz));
            camera.position={camera.target.x+radius*1.5,camera.target.y+radius*1.5,camera.target.z+radius*1.5};
            camera.up={0,0,1};camera.near_clip=std::max(0.001,radius*0.01);camera.far_clip=std::max(1000.0,radius*10);
            state.autoFitted=true;
        }
    }
    if(!field(ip,view,"vertical_fov_degrees").empty())camera.vertical_fov_degrees=number(field(ip,view,"vertical_fov_degrees"),"camera FOV");
    if(!field(ip,view,"near_clip").empty()&&number(field(ip,view,"near_clip"),"near clip")>0)camera.near_clip=number(field(ip,view,"near_clip"),"near clip");
    if(!field(ip,view,"far_clip").empty()&&number(field(ip,view,"far_clip"),"far clip")>0)camera.far_clip=number(field(ip,view,"far_clip"),"far clip");
    check(gx3de_view_set_camera(state.view,&camera),"set camera");
    if(!field(ip,view,"orthographic_height").empty()&&number(field(ip,view,"orthographic_height"),"orthographic height")>0)check(gx3de_view_orthographic_height_set(state.view,number(field(ip,view,"orthographic_height"),"orthographic height")),"physical orthographic height");
    gx3de_view_axes axes{};axes.struct_size=sizeof axes;
    axes.show_world=yes(field(ip,view,"axes_world"));
    axes.size_pixels=number(field(ip,view,"axes_size_pixels"),"axes size");
    std::string localAxes=field(ip,view,"axes_local_layer");
    if(!localAxes.empty()) {
        auto found=std::find_if(state.objects.begin(),state.objects.end(),[&](const auto &item){return item.second==localAxes;});
        if(found==state.objects.end())throw std::runtime_error("Local axes layer is missing: "+localAxes);
        axes.show_local=1;axes.local_object=found->first;
    }
    check(gx3de_view_axes_set(state.view,&axes),"set coordinate axes");
    gx3de_orientation_indicator indicator{};indicator.struct_size=sizeof indicator;
    check(gx3de_view_orientation_indicator_get(state.view,&indicator),"get orientation indicator");
    indicator.visible=yes(field(ip,view,"orientation_indicator_visible"));
    check(gx3de_view_orientation_indicator_set(state.view,&indicator),"set orientation indicator");
    gx3de_view_background background{};background.struct_size=sizeof background;
    background.gradient=yes(field(ip,view,"background_gradient"));
    background.top=rgb(field(ip,view,"background_rgb"),"background RGB");
    background.bottom=rgb(field(ip,view,"background_bottom_rgb"),"background bottom RGB");
    check(gx3de_view_background_set(state.view,&background),"set view background");
    gx3de_view_lighting lighting{};lighting.struct_size=sizeof lighting;
    lighting.enabled=yes(field(ip,view,"lighting"));
    lighting.ambient=number(field(ip,view,"lighting_ambient"),"lighting ambient");
    lighting.diffuse=number(field(ip,view,"lighting_diffuse"),"lighting diffuse");
    lighting.specular=number(field(ip,view,"lighting_specular"),"lighting specular");
    lighting.light_count=1;
    lighting.lights[0].direction=vec(field(ip,view,"lighting_direction"),"light direction");
    lighting.lights[0].color=rgb(field(ip,view,"lighting_color"),"light color");
    lighting.lights[0].intensity=number(field(ip,view,"lighting_intensity"),"light intensity");
    std::string lightsText=field(ip,view,"lighting_lights");
    if(!lightsText.empty()) {
        auto lights=split(lightsText,';');if(lights.size()>4)throw std::runtime_error("At most four lights are supported");
        lighting.light_count=static_cast<uint32_t>(lights.size());
        for(size_t i=0;i<lights.size();++i) {
            auto value=split(lights[i],',');if(value.size()!=7)throw std::runtime_error("Directional light needs seven values");
            lighting.lights[i].direction={number(value[0],"light dx"),number(value[1],"light dy"),number(value[2],"light dz")};
            lighting.lights[i].color={number(value[3],"light red"),number(value[4],"light green"),number(value[5],"light blue")};
            lighting.lights[i].intensity=number(value[6],"light intensity");
        }
    }
    check(gx3de_view_lighting_set(state.view,&lighting),"set view lighting");
    std::string boxText=field(ip,view,"clip_box");
    if(!boxText.empty()) {
        auto parts=split(boxText,';');if(parts.size()!=6)throw std::runtime_error("Clip box requires six values");
        gx3de_view_clip_box box{};box.struct_size=sizeof box;box.enabled=1;
        box.world_bounds.min={number(parts[0],"clip min X"),number(parts[1],"clip min Y"),number(parts[2],"clip min Z")};
        box.world_bounds.max={number(parts[3],"clip max X"),number(parts[4],"clip max Y"),number(parts[5],"clip max Z")};
        check(gx3de_view_clip_box_set(state.view,&box),"set clipping box");
    }
    std::string clips=field(ip,view,"clipping_planes");uint32_t slot=0;
    if(!clips.empty()) for(const auto &clipText:split(clips,';')) {
        if(slot>=GX3DE_MAX_VIEW_CLIP_PLANES)throw std::runtime_error("Too many clipping planes");
        auto p=split(clipText,',');if(p.size()!=4)throw std::runtime_error("Invalid clipping plane");
        double nx=number(p[0],"clip nx"),ny=number(p[1],"clip ny"),nz=number(p[2],"clip nz"),d=number(p[3],"clip d");
        double n2=nx*nx+ny*ny+nz*nz;if(n2<=0)throw std::runtime_error("Zero clipping normal");
        gx3de_view_clip_plane clip{};clip.struct_size=sizeof clip;clip.enabled=1;clip.keep_positive=1;clip.normal={nx,ny,nz};clip.origin={-d*nx/n2,-d*ny/n2,-d*nz/n2};
        check(gx3de_view_clip_plane_set(state.view,slot++,&clip),"set clipping plane");
    }
    if(yes(field(ip,view,"working_plane_visible"))) {
        auto origin=vec(field(ip,view,"working_plane_origin"),"working plane origin");
        auto normal=vec(field(ip,view,"working_plane_normal"),"working plane normal");
        auto u=vec(field(ip,view,"working_plane_u_axis"),"working plane U");
        gx3de_plane *plane=nullptr;check(gx3de_plane_create(state.scene,origin,normal,u,&plane),"create working plane");
        check(gx3de_view_set_working_plane(state.view,plane),"set working plane");
    }
    sceneTimeline(ip,state,scene,view);
    sceneAnnotations(ip,state,view);
    std::string referenceMarker=field(ip,view,"axes_reference_marker");
    if(!referenceMarker.empty()) {
        auto found=std::find_if(state.annotationAnchors.begin(),state.annotationAnchors.end(),
            [&](const auto &item){return item.first==referenceMarker;});
        if(found==state.annotationAnchors.end())throw std::runtime_error("Reference axes marker is missing: "+referenceMarker);
        axes.show_reference=1;axes.reference_axis=found->second;
        check(gx3de_view_axes_set(state.view,&axes),"set reference axes");
    }
    sceneCurves(ip,state,view);
}
void error(Tcl_Interp *ip,const std::exception &e) {Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));}
uint32_t graphicsLod(const std::string& value) {
    if(value=="Preview")return GX3DE_LOD_PREVIEW;
    if(value=="Low")return GX3DE_LOD_LOW;
    if(value=="Medium")return GX3DE_LOD_MEDIUM;
    if(value=="High")return GX3DE_LOD_HIGH;
    if(value=="Full")return GX3DE_LOD_FULL;
    throw std::runtime_error("Invalid graphics LOD: "+value);
}
void applyGraphicsPolicy(Tcl_Interp* ip,gx3de_engine* engine,Tcl_Obj* settings) {
    if(!settings)return;
    gx3de_graphics_policy policy{};policy.struct_size=sizeof policy;
    check(gx3de_engine_graphics_policy_get(engine,&policy),"read graphics policy");
    const auto execution=field(ip,settings,"execution");
    if(execution=="Auto")policy.execution=GX3DE_GRAPHICS_AUTO;
    else if(execution=="Hardware")policy.execution=GX3DE_GRAPHICS_HARDWARE;
    else if(execution=="Software")policy.execution=GX3DE_GRAPHICS_SOFTWARE;
    else throw std::runtime_error("Invalid graphics execution mode");
    policy.normal_lod=graphicsLod(field(ip,settings,"normal_quality"));
    policy.interaction_lod_enabled=field(ip,settings,"interaction_lod")=="On";
    policy.interaction_lod=graphicsLod(field(ip,settings,"interaction_quality"));
    const auto msaa=field(ip,settings,"msaa");
    if(msaa=="Off")policy.quality.msaa_samples=0;
    else if(msaa=="2x")policy.quality.msaa_samples=2;
    else if(msaa=="4x")policy.quality.msaa_samples=4;
    else if(msaa=="8x")policy.quality.msaa_samples=8;
    else throw std::runtime_error("Invalid MSAA setting");
    const auto transparency=field(ip,settings,"transparency");
    if(transparency=="Standard")policy.quality.transparency_mode=GX3DE_TRANSPARENCY_ALPHA_FALLBACK;
    else if(transparency=="Depth peeling")policy.quality.transparency_mode=GX3DE_TRANSPARENCY_DEPTH_PEEL;
    else throw std::runtime_error("Invalid transparency setting");
    const auto shadows=field(ip,settings,"shadow_rendering");
    if(shadows=="Off")policy.shadow_policy=GX3DE_SHADOW_OFF;
    else if(shadows=="Opaque objects only")policy.shadow_policy=GX3DE_SHADOW_OPAQUE_ONLY;
    else if(shadows=="Opaque and translucent objects")policy.shadow_policy=GX3DE_SHADOW_FULL;
    else throw std::runtime_error("Invalid shadow rendering setting");
    policy.export_supersampling=static_cast<uint32_t>(integer(field(ip,settings,"export_supersampling"),"export supersampling"));
    policy.display_triangle_budget=integer(field(ip,settings,"display_triangle_budget"),"display triangle budget");
    policy.gpu_budget_bytes=integer(field(ip,settings,"gpu_budget_bytes"),"GPU resource budget");
    policy.worker_rss_budget_bytes=integer(field(ip,settings,"worker_rss_budget_mib"),"worker RSS budget")*1048576;
    policy.worker_address_space_budget_bytes=integer(field(ip,settings,"worker_address_space_budget_mib"),"worker address-space budget")*1048576;
    check(gx3de_engine_graphics_policy_set(engine,&policy),"apply graphics policy");
}
void putRendererInfo(Tcl_Interp* ip,Tcl_Obj* result,gx3de_target* target) {
    gx3de_renderer_device_info device{};device.struct_size=sizeof device;
    check(gx3de_target_renderer_info(target,&device),"query renderer device");
    put(ip,result,"backend",Tcl_NewStringObj(device.backend==GX3DE_RENDER_BACKEND_D3D11?"D3D11":"OpenGL",-1));
    put(ip,result,"execution",Tcl_NewStringObj(device.execution==GX3DE_RENDER_EXECUTION_HARDWARE?"Hardware":
        (device.execution==GX3DE_RENDER_EXECUTION_SOFTWARE?"Software":"Unknown"),-1));
    put(ip,result,"device",Tcl_NewStringObj(device.adapter,-1));
    put(ip,result,"driver",Tcl_NewStringObj(device.driver,-1));
    put(ip,result,"fallback_reason",Tcl_NewStringObj(device.fallback_reason,-1));
}
#include "native3d_scientific_figure_tcl_v1.inc"
int render(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=6){Tcl_WrongNumArgs(ip,1,args,"scene png width height preview|full");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);state.clearRender();
    try {
        std::string path=str(args[2]);uint64_t width=integer(str(args[3]),"width"),height=integer(str(args[4]),"height");
        if(width<16||height<16||width>4096||height>4096)throw std::runtime_error("Viewport must be 16..4096 pixels per side");
        check(gx3de_engine_create(&state.engine),"create engine");
        applyGraphicsPolicy(ip,state.engine,get(ip,args[1],"graphics_policy"));
        check(gx3de_scene_create(state.engine,&state.scene),"create scene");
        std::string cacheNamespace=field(ip,args[1],"session_namespace");
        if(!cacheNamespace.empty())check(gx3de_engine_set_cache_namespace(state.engine,cacheNamespace.c_str()),"set Session cache namespace");
        std::string cacheRoot=field(ip,args[1],"cache_root");
        if(!cacheRoot.empty()) {
            check(gx3de_engine_set_mesh_cache_root(state.engine,cacheRoot.c_str()),"set mesh cache root");
            check(gx3de_engine_set_scientific_cache_root(state.engine,cacheRoot.c_str()),"set scientific cache root");
        }
        check(gx3de_view_create(state.scene,&state.view),"create view");
        gx3de_navcube_state cube{};cube.struct_size=sizeof cube;
        check(gx3de_view_navcube_get(state.view,&cube),"query Navigation Cube");
        cube.visible=str(args[5])=="compact"||field(ip,get(ip,args[1],"view"),"navigation_cube_visible")=="0"?0:1;cube.corner=GX3DE_NAVCUBE_TOP_RIGHT;
        // Preview presentation only; use the proven Native cube and hit regions.
        if(str(args[5])=="preview") {cube.size_pixels=80;cube.margin_pixels=40;}
        check(gx3de_view_navcube_set(state.view,&cube),"show Navigation Cube");
        check(gx3de_target_create_headless(state.engine,static_cast<uint32_t>(width),static_cast<uint32_t>(height),&state.target),"create pixel target");
        check(gx3de_viewport_create(state.target,state.view,0,0,static_cast<uint32_t>(width),static_cast<uint32_t>(height),&state.viewport),"create viewport");
        std::string stage=str(args[5]);if(stage!="preview"&&stage!="full"&&stage!="compact")throw std::runtime_error("Invalid render stage");
        fillScene(ip,state,args[1],stage=="preview");
        if(get(ip,args[1],"logical_focus"))logicalFocus(ip,state,get(ip,args[1],"logical_focus"));
        scientificFigure(ip,state,get(ip,args[1],"scientific_figure"));
        checkRender(state.target,gx3de_target_render(state.target),"render scene");check(gx3de_target_write_png(state.target,path.c_str()),"write PNG");
        Tcl_Obj *result=Tcl_NewDictObj();put(ip,result,"object_count",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(state.objects.size())));put(ip,result,"path",Tcl_NewStringObj(path.c_str(),-1));
        put(ip,result,"auto_fitted",Tcl_NewIntObj(state.autoFitted?1:0));
        put(ip,result,"stage",Tcl_NewStringObj(stage.c_str(),-1));
        put(ip,result,"navcube_size_pixels",Tcl_NewIntObj(cube.size_pixels));
        put(ip,result,"navcube_margin_pixels",Tcl_NewIntObj(cube.margin_pixels));
        gx3de_render_resource_info resource{};resource.struct_size=sizeof resource;
        check(gx3de_target_render_resource_info_get(state.target,&resource),"query renderer resources");
        put(ip,result,"gpu_estimated_bytes",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(resource.gpu_estimated_bytes)));
        put(ip,result,"gpu_budget_bytes",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(resource.gpu_budget_bytes)));
        put(ip,result,"gpu_accounting",Tcl_NewStringObj(resource.gpu_accounting==GX3DE_RESOURCE_ESTIMATED?"estimated":"unavailable",-1));
        put(ip,result,"gpu_measured_accounting",Tcl_NewStringObj(resource.measured_accounting==GX3DE_RESOURCE_MEASURED?"measured":"unavailable",-1));
        put(ip,result,"gpu_measured_bytes",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(resource.gpu_measured_bytes)));
        putRendererInfo(ip,result,state.target);
        {
            gx3de_camera camera{};camera.struct_size=sizeof camera;check(gx3de_view_get_camera(state.view,&camera),"query fitted camera");
            put(ip,result,"camera_position",vecObj(camera.position));put(ip,result,"camera_target",vecObj(camera.target));put(ip,result,"camera_up",vecObj(camera.up));
            put(ip,result,"projection",Tcl_NewStringObj(camera.orthographic?"orthographic":"perspective",-1));
            put(ip,result,"vertical_fov_degrees",Tcl_NewDoubleObj(camera.vertical_fov_degrees));
            put(ip,result,"near_clip",Tcl_NewDoubleObj(camera.near_clip));put(ip,result,"far_clip",Tcl_NewDoubleObj(camera.far_clip));
        }
        Tcl_Obj *summaries=Tcl_NewListObj(0,nullptr);
        for(const auto &entry:state.objects) {
            Tcl_Obj *item=Tcl_NewDictObj();
            put(ip,item,"layer",Tcl_NewStringObj(entry.second.c_str(),-1));
            gx3de_bounds bounds{};
            if(gx3de_object_bounds(entry.first,1,&bounds)==GX3DE_OK) {
                put(ip,item,"bounds_min",vecObj(bounds.min));put(ip,item,"bounds_max",vecObj(bounds.max));
            }
            uint64_t vertices=0,triangles=0;
            if(gx3de_object_counts(entry.first,&vertices,&triangles)==GX3DE_OK) {
                put(ip,item,"vertices",Tcl_NewWideIntObj(vertices));put(ip,item,"triangles",Tcl_NewWideIntObj(triangles));
            }
            gx3de_scientific_info sci{};sci.struct_size=sizeof sci;
            if(gx3de_scientific_info_get(entry.first,&sci)==GX3DE_OK) {
                put(ip,item,"points",Tcl_NewWideIntObj(sci.point_count));put(ip,item,"cells",Tcl_NewWideIntObj(sci.cell_count));
                Tcl_Obj *arrays=Tcl_NewListObj(0,nullptr);
                for(uint64_t i=0;i<sci.array_count;++i) {
                    gx3de_scientific_array_info a{};a.struct_size=sizeof a;
                    check(gx3de_scientific_array_info_get(entry.first,i,&a),"inspect field array");
                    Tcl_Obj *array=Tcl_NewDictObj();
                    put(ip,array,"name",Tcl_NewStringObj(a.name_utf8,-1));
                    put(ip,array,"components",Tcl_NewIntObj(a.components));
                    put(ip,array,"association",Tcl_NewIntObj(a.association));
                    put(ip,array,"tuples",Tcl_NewWideIntObj(a.tuple_count));
                    Tcl_ListObjAppendElement(ip,arrays,array);
                }
                put(ip,item,"arrays",arrays);
            }
            Tcl_ListObjAppendElement(ip,summaries,item);
        }
        put(ip,result,"geometry",summaries);
        Tcl_SetObjResult(ip,result);return TCL_OK;
    } catch(const std::exception &e) {state.clearRender();error(ip,e);return TCL_ERROR;}
}
int capabilities(ClientData,Tcl_Interp*ip,int argc,Tcl_Obj*const args[]){
    if(argc!=1){Tcl_WrongNumArgs(ip,1,args,"");return TCL_ERROR;}
    Tcl_SetObjResult(ip,Tcl_NewStringObj("managed_planar_texture",-1));return TCL_OK;
}
int graphicsProbe(ClientData,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]) {
    if(argc!=2){Tcl_WrongNumArgs(ip,1,args,"graphics policy");return TCL_ERROR;}
    gx3de_engine* engine=nullptr;gx3de_scene* scene=nullptr;gx3de_view* view=nullptr;
    gx3de_target* target=nullptr;gx3de_viewport* viewport=nullptr;
    try {
        check(gx3de_engine_create(&engine),"create graphics probe engine");
        applyGraphicsPolicy(ip,engine,args[1]);
        check(gx3de_scene_create(engine,&scene),"create graphics probe scene");
        check(gx3de_view_create(scene,&view),"create graphics probe view");
        check(gx3de_target_create_headless(engine,64,64,&target),"create graphics probe target");
        check(gx3de_viewport_create(target,view,0,0,64,64,&viewport),"create graphics probe viewport");
        checkRender(target,gx3de_target_render(target),"check Native 3D renderer");
        Tcl_Obj* result=Tcl_NewDictObj();putRendererInfo(ip,result,target);
        gx3de_render_resource_info resource{};resource.struct_size=sizeof resource;
        check(gx3de_target_render_resource_info_get(target,&resource),"query graphics probe resources");
        put(ip,result,"gpu_accounting",Tcl_NewStringObj(resource.gpu_accounting==GX3DE_RESOURCE_ESTIMATED?"estimated":"unavailable",-1));
        put(ip,result,"gpu_measured_accounting",Tcl_NewStringObj(resource.measured_accounting==GX3DE_RESOURCE_MEASURED?"measured":"unavailable",-1));
        put(ip,result,"gpu_estimated_bytes",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(resource.gpu_estimated_bytes)));
        put(ip,result,"gpu_measured_bytes",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(resource.gpu_measured_bytes)));
        put(ip,result,"gpu_budget_bytes",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(resource.gpu_budget_bytes)));
        gx3de_engine_destroy(engine);Tcl_SetObjResult(ip,result);return TCL_OK;
    }catch(const std::exception& e){if(engine)gx3de_engine_destroy(engine);error(ip,e);return TCL_ERROR;}
}
int presentationUpdate(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
 if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"layer fields png");return TCL_ERROR;}
 auto& state=*static_cast<State*>(data);
 struct Saved {gx3de_object* object;gx3de_object_style style;uint32_t visible;double opacity;};std::vector<Saved> saved;
 try {
  if(!state.view||!state.target)throw std::runtime_error("Render before updating presentation");
  auto id=str(args[1]);auto* fields=args[2];
  for(auto& item:state.objects)if(item.second==id){Saved previous{};previous.object=item.first;previous.style.struct_size=sizeof previous.style;check(gx3de_object_style_get(item.first,&previous.style),"capture style");check(gx3de_object_get_visible(item.first,&previous.visible),"capture visibility");check(gx3de_object_get_opacity(item.first,&previous.opacity),"capture opacity");saved.push_back(previous);}
  if(saved.empty())throw std::runtime_error("Layer is stale or unavailable");
  for(auto& previous:saved){auto style=previous.style;
   if(get(ip,fields,"base_color"))style.color=rgb(field(ip,fields,"base_color"),"base color");
   if(get(ip,fields,"line_width"))style.line_width=number(field(ip,fields,"line_width"),"line width");
   if(get(ip,fields,"point_size"))style.point_size=number(field(ip,fields,"point_size"),"point size");
   auto visible=get(ip,fields,"visible")?uint32_t(yes(field(ip,fields,"visible"))):previous.visible;
   auto opacity=get(ip,fields,"opacity")?number(field(ip,fields,"opacity"),"opacity"):previous.opacity;
   check(gx3de_target_object_presentation_set(state.target,previous.object,&style,visible,opacity),"selective object presentation");
  }
  checkRender(state.target,gx3de_target_render(state.target),"render selective presentation");check(gx3de_target_write_png(state.target,str(args[3]).c_str()),"write selective presentation");
  auto* result=Tcl_NewDictObj();put(ip,result,"updated_objects",Tcl_NewWideIntObj(saved.size()));put(ip,result,"geometry_rebuilt",Tcl_NewIntObj(0));Tcl_SetObjResult(ip,result);return TCL_OK;
 }catch(const std::exception& e){for(auto& previous:saved){gx3de_object_style_set(previous.object,&previous.style);gx3de_object_set_visible(previous.object,previous.visible);gx3de_object_set_opacity(previous.object,previous.opacity);}error(ip,e);return TCL_ERROR;}
}

int focusLogical(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]) {
 if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"reference PNG");return TCL_ERROR;}
 auto& state=*static_cast<State*>(data);
 try {if(!state.view||!state.target)throw std::runtime_error("Render before logical focus");logicalFocus(ip,state,args[1]);checkRender(state.target,gx3de_target_render(state.target),"render logical focus");check(gx3de_target_write_png(state.target,str(args[2]).c_str()),"write logical focus");Tcl_SetObjResult(ip,args[1]);return TCL_OK;}catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
int textureAnchor(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=6){Tcl_WrongNumArgs(ip,1,args,"x y verified_managed_png width height");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);gx3de_texture *texture=nullptr;gx3de_planar_texture *assignment=nullptr;
    try {
        if(!state.viewport)throw std::runtime_error("Render the actual source geometry before choosing a texture anchor");
        gx3de_pick_hit hit{};hit.struct_size=sizeof hit;
        check(gx3de_viewport_pick(state.viewport,static_cast<uint32_t>(integer(str(args[1]),"x")),static_cast<uint32_t>(integer(str(args[2]),"y")),&hit),"pick texture source face");
        auto found=std::find_if(state.objects.begin(),state.objects.end(),[&](const auto &item){return item.first==hit.object;});
        if(found==state.objects.end())throw std::runtime_error("Picked geometry has no retained layer identity");
        check(gx3de_texture_load_file(state.engine,str(args[3]).c_str(),&texture),"inspect managed anchor image");
        gx3de_planar_texture_spec spec{};spec.struct_size=sizeof spec;spec.width=number(str(args[4]),"texture width");spec.height=number(str(args[5]),"texture height");spec.anchor_u=spec.anchor_v=.5;
        check(gx3de_object_planar_texture_add_from_pick(texture,&hit,&spec,&assignment),"resolve actual source triangle from picked surface");
        check(gx3de_planar_texture_get(assignment,&spec),"read stable source texture anchor");
        Tcl_Obj *reply=Tcl_NewDictObj();put(ip,reply,"layer_id",Tcl_NewStringObj(found->second.c_str(),-1));
        uint64_t occurrence=0;for(auto it=state.objects.begin();it!=found;++it)if(it->second==found->second)++occurrence;
        put(ip,reply,"occurrence_index",Tcl_NewWideIntObj(occurrence));put(ip,reply,"source_triangle",Tcl_NewWideIntObj(spec.source_triangle));put(ip,reply,"local_anchor",vecObj(spec.local_anchor));
        check(gx3de_planar_texture_destroy(assignment),"release temporary anchor resolver");assignment=nullptr;
        check(gx3de_texture_destroy(texture),"release temporary anchor image");texture=nullptr;Tcl_SetObjResult(ip,reply);return TCL_OK;
    }catch(const std::exception &e){if(assignment)gx3de_planar_texture_destroy(assignment);if(texture)gx3de_texture_destroy(texture);error(ip,e);return TCL_ERROR;}
}
int pick(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"x y");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.viewport)throw std::runtime_error("Render a scene before picking");
        uint64_t x=integer(str(args[1]),"x"),y=integer(str(args[2]),"y");
        gx3de_pick_hit hit{};hit.struct_size=sizeof hit;
        gx3de_result result=gx3de_viewport_pick(state.viewport,static_cast<uint32_t>(x),static_cast<uint32_t>(y),&hit);
        Tcl_Obj *reply=Tcl_NewDictObj();
        if(result==GX3DE_NOT_FOUND) {put(ip,reply,"hit",Tcl_NewIntObj(0));Tcl_SetObjResult(ip,reply);return TCL_OK;}
        check(result,"pick viewport");
        put(ip,reply,"hit",Tcl_NewIntObj(1));
        auto found=std::find_if(state.objects.begin(),state.objects.end(),[&](const auto &item){return item.first==hit.object;});
        put(ip,reply,"layer_id",Tcl_NewStringObj(found==state.objects.end()?"":found->second.c_str(),-1));
        uint64_t occurrence=0;
        if(found!=state.objects.end())for(auto it=state.objects.begin();it!=found;++it)if(it->second==found->second)++occurrence;
        put(ip,reply,"occurrence_index",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(occurrence)));
        put(ip,reply,"world_point",vecObj(hit.world_point));put(ip,reply,"local_point",vecObj(hit.local_point));
        put(ip,reply,"world_normal",vecObj(hit.world_normal));
        put(ip,reply,"cell_index",Tcl_NewWideIntObj(hit.cell_index==UINT64_MAX?-1:static_cast<Tcl_WideInt>(hit.cell_index)));
        put(ip,reply,"point_index",Tcl_NewWideIntObj(hit.point_index==UINT64_MAX?-1:static_cast<Tcl_WideInt>(hit.point_index)));
        uint64_t logical=0;
        if(hit.cell_index!=UINT64_MAX&&gx3de_scientific_logical_id(hit.object,GX3DE_SCI_ASSOC_CELL,hit.cell_index,&logical)==GX3DE_OK)put(ip,reply,"logical_cell_id",Tcl_NewWideIntObj(logical));
        if(hit.point_index!=UINT64_MAX&&gx3de_scientific_logical_id(hit.object,GX3DE_SCI_ASSOC_POINT,hit.point_index,&logical)==GX3DE_OK)put(ip,reply,"logical_point_id",Tcl_NewWideIntObj(logical));
        gx3de_anchor *anchor=nullptr;check(gx3de_pick_make_anchor(state.viewport,&hit,&anchor),"create selection anchor");
        check(gx3de_view_set_selection(state.view,anchor),"set view selection");
        // The scene owns anchors. The view holds this pointer until the next
        // render resets the scene; destroying it here would clear selection.
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int preset(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=6){Tcl_WrongNumArgs(ip,1,args,"preset layer_id png width height");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.view||!state.target)throw std::runtime_error("Render a scene before changing camera preset");
        std::string name=str(args[1]);
        const std::pair<const char*,uint32_t> presets[]={
            {"front",GX3DE_CAMERA_FRONT},{"back",GX3DE_CAMERA_BACK},{"left",GX3DE_CAMERA_LEFT},
            {"right",GX3DE_CAMERA_RIGHT},{"top",GX3DE_CAMERA_TOP},{"bottom",GX3DE_CAMERA_BOTTOM},
            {"isometric",GX3DE_CAMERA_ISOMETRIC},{"fit_scene",GX3DE_CAMERA_FIT_SCENE},
            {"fit_object",GX3DE_CAMERA_FIT_OBJECT},{"fit_selection",GX3DE_CAMERA_FIT_SELECTION}};
        uint32_t selected=0;for(auto &p:presets)if(name==p.first)selected=p.second;
        if(!selected)throw std::runtime_error("Unknown camera preset: "+name);
        gx3de_object *object=nullptr;
        if(selected==GX3DE_CAMERA_FIT_OBJECT) {
            std::string layerId=str(args[2]);
            auto it=std::find_if(state.objects.begin(),state.objects.end(),[&](const auto &item){return item.second==layerId;});
            if(it==state.objects.end())throw std::runtime_error("Fit object layer is missing: "+layerId);
            object=it->first;
        }
        check(gx3de_view_camera_preset(state.view,selected,object),"camera preset");
        checkRender(state.target,gx3de_target_render(state.target),"render camera preset");
        std::string path=str(args[3]);check(gx3de_target_write_png(state.target,path.c_str()),"write preset PNG");
        gx3de_camera camera{};camera.struct_size=sizeof camera;check(gx3de_view_get_camera(state.view,&camera),"query preset camera");
        Tcl_Obj *result=Tcl_NewDictObj();
        put(ip,result,"camera_position",vecObj(camera.position));put(ip,result,"camera_target",vecObj(camera.target));put(ip,result,"camera_up",vecObj(camera.up));
        put(ip,result,"projection",Tcl_NewStringObj(camera.orthographic?"orthographic":"perspective",-1));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int cameraRestore(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"camera png");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.view||!state.target)throw std::runtime_error("Render before restoring camera");
        gx3de_camera camera{};camera.struct_size=sizeof camera;
        camera.position=vec(field(ip,args[1],"camera_position"),"camera position");
        camera.target=vec(field(ip,args[1],"camera_target"),"camera target");
        camera.up=vec(field(ip,args[1],"camera_up"),"camera up");
        camera.orthographic=field(ip,args[1],"projection")=="orthographic";
        camera.vertical_fov_degrees=number(field(ip,args[1],"vertical_fov_degrees"),"camera FOV");
        camera.near_clip=number(field(ip,args[1],"near_clip"),"near clip");
        camera.far_clip=number(field(ip,args[1],"far_clip"),"far clip");
        check(gx3de_view_set_camera(state.view,&camera),"restore camera");
        checkRender(state.target,gx3de_target_render(state.target),"render restored camera");
        check(gx3de_target_write_png(state.target,str(args[2]).c_str()),"write restored camera PNG");
        Tcl_SetObjResult(ip,args[1]);return TCL_OK;
    } catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
}
int navcubePick(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"x y");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.viewport)throw std::runtime_error("Render a scene before using the Navigation Cube");
        uint32_t region=0;
        check(gx3de_viewport_navcube_pick(state.viewport,
            static_cast<uint32_t>(integer(str(args[1]),"x")),
            static_cast<uint32_t>(integer(str(args[2]),"y")),&region),"pick Navigation Cube");
        Tcl_SetObjResult(ip,Tcl_NewIntObj(static_cast<int>(region)));return TCL_OK;
    }catch(const std::exception &e){error(ip,e);return TCL_ERROR;}
}
int navcubeClick(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"x y png");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.viewport||!state.view||!state.target)
            throw std::runtime_error("Render a scene before using the Navigation Cube");
        uint32_t region=0;
        check(gx3de_viewport_navcube_click(state.viewport,
            static_cast<uint32_t>(integer(str(args[1]),"x")),
            static_cast<uint32_t>(integer(str(args[2]),"y")),&region),"select Navigation Cube region");
        if(!region)throw std::runtime_error("Navigation Cube click missed");
        checkRender(state.target,gx3de_target_render(state.target),"render Navigation Cube orientation");
        check(gx3de_target_write_png(state.target,str(args[3]).c_str()),"write Navigation Cube PNG");
        gx3de_camera camera{};camera.struct_size=sizeof camera;
        check(gx3de_view_get_camera(state.view,&camera),"query Navigation Cube camera");
        Tcl_Obj *result=Tcl_NewDictObj();
        put(ip,result,"region",Tcl_NewIntObj(static_cast<int>(region)));
        put(ip,result,"camera_position",vecObj(camera.position));
        put(ip,result,"camera_target",vecObj(camera.target));
        put(ip,result,"camera_up",vecObj(camera.up));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }catch(const std::exception &e){error(ip,e);return TCL_ERROR;}
}
int navigate(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=5){Tcl_WrongNumArgs(ip,1,args,"orbit|pan|zoom delta_x delta_y png");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.view||!state.viewport||!state.target)
            throw std::runtime_error("Render a scene before camera navigation");
        const std::string mode=str(args[1]);
        const double x=number(str(args[2]),"camera navigation delta x");
        const double y=number(str(args[3]),"camera navigation delta y");
        if(mode=="orbit")check(gx3de_view_camera_orbit(state.view,x*0.005,y*0.005,nullptr),"orbit camera");
        else if(mode=="roll")check(gx3de_view_camera_roll(state.view,x*0.005),"roll camera");
        else if(mode=="pan")check(gx3de_view_camera_pan(state.viewport,x,y),"pan camera");
        else if(mode=="zoom")check(gx3de_view_camera_dolly(state.view,std::exp(0.12*x)),"dolly camera");
        else throw std::runtime_error("Unknown camera navigation mode: "+mode);
        checkRender(state.target,gx3de_target_render(state.target),"render navigated camera");
        const std::string path=str(args[4]);
        check(gx3de_target_write_png(state.target,path.c_str()),"write navigated camera PNG");
        gx3de_camera camera{};camera.struct_size=sizeof camera;
        check(gx3de_view_get_camera(state.view,&camera),"query navigated camera");
        Tcl_Obj *result=Tcl_NewDictObj();
        put(ip,result,"camera_position",vecObj(camera.position));
        put(ip,result,"camera_target",vecObj(camera.target));
        put(ip,result,"camera_up",vecObj(camera.up));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int gizmoSelect(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=8){Tcl_WrongNumArgs(ip,1,args,"layer_id world|local families pivot_xyz pivot_marker size_pixels png");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.view||!state.target)throw std::runtime_error("Render a scene before selecting a manipulator");
        std::string layer=str(args[1]),space=str(args[2]);
        gx3de_object *object=nullptr;uint32_t matches=0;
        for(const auto &item:state.objects)if(item.second==layer){object=item.first;++matches;}
        if(matches!=1)throw std::runtime_error(matches?"Manipulator requires a single object occurrence in its layer":"Manipulator layer is missing");
        if(space!="world"&&space!="local")throw std::runtime_error("Manipulator space must be world or local");
        if(state.gizmo){check(gx3de_gizmo_destroy(state.gizmo),"destroy previous manipulator");state.gizmo=nullptr;}
        gx3de_gizmo_spec spec{};spec.struct_size=sizeof spec;spec.object=object;spec.visible=1;
        spec.space=space=="local"?GX3DE_GIZMO_SPACE_LOCAL:GX3DE_GIZMO_SPACE_WORLD;
        spec.families=0;
        for(const auto &family:split(str(args[3]),',')) {
            if(family=="axis")spec.families|=GX3DE_GIZMO_FAMILY_AXIS;
            else if(family=="plane")spec.families|=GX3DE_GIZMO_FAMILY_PLANE;
            else if(family=="free")spec.families|=GX3DE_GIZMO_FAMILY_FREE;
            else if(family=="rotate")spec.families|=GX3DE_GIZMO_FAMILY_ROTATE;
            else throw std::runtime_error("Unknown manipulator family: "+family);
        }
        if(!spec.families)throw std::runtime_error("Select at least one manipulator family");
        spec.pivot_mode=GX3DE_GIZMO_PIVOT_OBJECT;
        std::string pivot=str(args[4]),marker=str(args[5]);
        if(!pivot.empty()&&!marker.empty())throw std::runtime_error("Choose either an explicit pivot or a marker pivot");
        if(!pivot.empty()) {spec.pivot_mode=GX3DE_GIZMO_PIVOT_EXPLICIT;spec.world_pivot=vec(pivot,"manipulator pivot");}
        if(!marker.empty()) {
            auto found=std::find_if(state.annotationAnchors.begin(),state.annotationAnchors.end(),
                [&](const auto &item){return item.first==marker;});
            if(found==state.annotationAnchors.end())throw std::runtime_error("Manipulator pivot marker is missing: "+marker);
            spec.pivot_mode=GX3DE_GIZMO_PIVOT_ANCHOR;spec.anchor=found->second;
        }
        spec.size_pixels=number(str(args[6]),"manipulator size");spec.preview_only=0;
        check(gx3de_gizmo_create(state.view,&spec,&state.gizmo),"create object manipulator");
        state.gizmoObject=object;state.gizmoLayer=layer;
        checkRender(state.target,gx3de_target_render(state.target),"render manipulator");
        check(gx3de_target_write_png(state.target,str(args[7]).c_str()),"write manipulator PNG");
        Tcl_Obj *reply=Tcl_NewDictObj();put(ip,reply,"layer_id",Tcl_NewStringObj(layer.c_str(),-1));
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int gizmoPick(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"x y");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.gizmo||!state.viewport)throw std::runtime_error("Select a manipulator first");
        uint32_t x=static_cast<uint32_t>(integer(str(args[1]),"x"));
        uint32_t y=static_cast<uint32_t>(integer(str(args[2]),"y"));
        gx3de_gizmo *hit=nullptr;uint32_t handle=0;
        gx3de_result result=gx3de_gizmo_pick(state.viewport,x,y,&hit,&handle);
        if(result!=GX3DE_NOT_FOUND)check(result,"inspect manipulator handle");
        Tcl_SetObjResult(ip,Tcl_NewIntObj(result==GX3DE_NOT_FOUND||hit!=state.gizmo?0:static_cast<int>(handle)));
        return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int gizmoBegin(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"x y");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.gizmo||!state.viewport)throw std::runtime_error("Select a manipulator first");
        uint32_t x=static_cast<uint32_t>(integer(str(args[1]),"x"));
        uint32_t y=static_cast<uint32_t>(integer(str(args[2]),"y"));
        gx3de_gizmo *hit=nullptr;uint32_t handle=0;
        gx3de_result result=gx3de_gizmo_pick(state.viewport,x,y,&hit,&handle);
        if(result==GX3DE_NOT_FOUND){Tcl_SetObjResult(ip,Tcl_NewIntObj(0));return TCL_OK;}
        check(result,"pick manipulator handle");
        if(hit!=state.gizmo){Tcl_SetObjResult(ip,Tcl_NewIntObj(0));return TCL_OK;}
        check(gx3de_gizmo_begin_screen(state.gizmo,state.viewport,handle,x,y),"begin manipulator drag");
        check(gx3de_target_interaction_set(state.target,1),"activate interaction LOD");
        Tcl_SetObjResult(ip,Tcl_NewIntObj(static_cast<int>(handle)));return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int gizmoUpdate(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"x y png");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.gizmo||!state.viewport)throw std::runtime_error("Select a manipulator first");
        uint32_t x=static_cast<uint32_t>(integer(str(args[1]),"x"));
        uint32_t y=static_cast<uint32_t>(integer(str(args[2]),"y"));
        gx3de_gizmo_result moved{};moved.struct_size=sizeof moved;
        check(gx3de_gizmo_update_screen(state.gizmo,state.viewport,x,y,&moved),"update manipulator drag");
        checkRender(state.target,gx3de_target_render(state.target),"render manipulator drag");
        check(gx3de_target_write_png(state.target,str(args[3]).c_str()),"write manipulator drag PNG");
        Tcl_Obj *reply=Tcl_NewDictObj();put(ip,reply,"handle",Tcl_NewIntObj(static_cast<int>(moved.active_handle)));
        put(ip,reply,"matrix",matrixObj(moved.proposed_local_transform));
        put(ip,reply,"translation_world",vecObj(moved.translation_world));
        put(ip,reply,"angle_radians",Tcl_NewDoubleObj(moved.angle_radians));
        put(ip,reply,"constraint_status",Tcl_NewIntObj(static_cast<int>(moved.constraint_status)));
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int gizmoEnd(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=2){Tcl_WrongNumArgs(ip,1,args,"accept");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.gizmo||!state.gizmoObject)throw std::runtime_error("Select a manipulator first");
        bool accept=yes(str(args[1]));
        check(gx3de_gizmo_end(state.gizmo,accept?1u:0u),"finish manipulator drag");
        check(gx3de_target_interaction_set(state.target,0),"restore normal LOD");
        gx3de_mat4 matrix{};check(gx3de_object_get_transform(state.gizmoObject,&matrix),"read manipulated transform");
        Tcl_Obj *reply=Tcl_NewDictObj();put(ip,reply,"layer_id",Tcl_NewStringObj(state.gizmoLayer.c_str(),-1));
        put(ip,reply,"matrix",matrixObj(matrix));
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int exportPng(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=4&&argc!=5){Tcl_WrongNumArgs(ip,1,args,"path width height ?graphics_policy?");return TCL_ERROR;}
    auto &state=*static_cast<State*>(data);
    try {
        if(!state.view)throw std::runtime_error("Render a scene before exporting an image");
        uint64_t width=integer(str(args[2]),"export width"),height=integer(str(args[3]),"export height");
        if(width<16||height<16||width>4096||height>4096)throw std::runtime_error("Export size must be 16..4096 pixels per side");
        if(argc==5)applyGraphicsPolicy(ip,state.engine,args[4]);
        gx3de_graphics_policy policy{};policy.struct_size=sizeof policy;
        check(gx3de_engine_graphics_policy_get(state.engine,&policy),"read export graphics policy");
        check(gx3de_view_write_png_supersampled(state.view,static_cast<uint32_t>(width),static_cast<uint32_t>(height),policy.export_supersampling,str(args[1]).c_str()),"export explicit-resolution PNG");
        Tcl_SetObjResult(ip,Tcl_NewStringObj(str(args[1]).c_str(),-1));return TCL_OK;
    } catch(const std::exception &e) {error(ip,e);return TCL_ERROR;}
}
int planeBegin(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
    if(argc!=7){Tcl_WrongNumArgs(ip,1,args,"target action handle slot x y");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try{
        if(!state.viewport)throw std::runtime_error("Render a scene before plane manipulation");
        if(state.planeManip)throw std::runtime_error("A plane drag is already active");
        const std::string target=str(args[1]),action=str(args[2]),handle=str(args[3]);
        const std::pair<const char*,uint32_t> targets[]={{"working",GX3DE_MANIP_WORKING_PLANE},
            {"clip",GX3DE_MANIP_CLIP_PLANE},{"box",GX3DE_MANIP_CLIP_BOX}};
        const std::pair<const char*,uint32_t> handles[]={{"free",GX3DE_MANIP_FREE},
            {"x",GX3DE_MANIP_X},{"y",GX3DE_MANIP_Y},{"z",GX3DE_MANIP_Z},
            {"min_x",GX3DE_MANIP_BOX_MIN_X},{"min_y",GX3DE_MANIP_BOX_MIN_Y},
            {"min_z",GX3DE_MANIP_BOX_MIN_Z},{"max_x",GX3DE_MANIP_BOX_MAX_X},
            {"max_y",GX3DE_MANIP_BOX_MAX_Y},{"max_z",GX3DE_MANIP_BOX_MAX_Z}};
        uint32_t t=0,h=UINT32_MAX;
        for(const auto& p:targets)if(target==p.first)t=p.second;
        for(const auto& p:handles)if(handle==p.first)h=p.second;
        if(!t||h==UINT32_MAX||!(action=="translate"||action=="rotate"))
            throw std::runtime_error("Invalid plane manipulation selection");
        uint32_t slot=static_cast<uint32_t>(integer(str(args[4]),"clip plane slot"));
        check(gx3de_view_manipulation_begin(state.viewport,t,slot,
            action=="translate"?GX3DE_MANIP_TRANSLATE:GX3DE_MANIP_ROTATE,h,
            static_cast<uint32_t>(integer(str(args[5]),"x")),
            static_cast<uint32_t>(integer(str(args[6]),"y")),&state.planeManip),"begin plane manipulation");
        state.planeManipTarget=t;state.planeManipSlot=slot;
        Tcl_SetObjResult(ip,Tcl_NewIntObj(1));return TCL_OK;
    }catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
int planeUpdate(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"x y PNG");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try{
        if(!state.planeManip||!state.target)throw std::runtime_error("Begin a plane drag first");
        gx3de_view_manipulation_result result{};result.struct_size=sizeof(result);
        check(gx3de_view_manipulation_update(state.planeManip,
            static_cast<uint32_t>(integer(str(args[1]),"x")),
            static_cast<uint32_t>(integer(str(args[2]),"y")),&result),"update plane drag");
        checkRender(state.target,gx3de_target_render(state.target),"render plane drag");
        check(gx3de_target_write_png(state.target,str(args[3]).c_str()),"write plane drag PNG");
        Tcl_Obj* reply=Tcl_NewDictObj();put(ip,reply,"origin",vecObj(result.origin));
        put(ip,reply,"normal",vecObj(result.normal));
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    }catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
int planeEnd(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
    if(argc!=2){Tcl_WrongNumArgs(ip,1,args,"accept");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try{
        if(!state.planeManip)throw std::runtime_error("Begin a plane drag first");
        const uint32_t target=state.planeManipTarget,slot=state.planeManipSlot;
        const uint32_t accept=yes(str(args[1]))?1u:0u;
        auto* manipulation=state.planeManip;state.planeManip=nullptr;
        check(gx3de_view_manipulation_end(manipulation,accept),"finish plane drag");
        Tcl_Obj* reply=Tcl_NewDictObj();
        if(target==GX3DE_MANIP_WORKING_PLANE){
            gx3de_plane* plane=nullptr;check(gx3de_view_get_working_plane(state.view,&plane),"get working plane");
            gx3de_vec3 origin{},normal{},u{};check(gx3de_plane_get(plane,&origin,&normal,&u),"get plane frame");
            put(ip,reply,"origin",vecObj(origin));put(ip,reply,"normal",vecObj(normal));
            put(ip,reply,"u_axis",vecObj(u));
        }else if(target==GX3DE_MANIP_CLIP_PLANE){
            gx3de_view_clip_plane clip{};clip.struct_size=sizeof(clip);
            check(gx3de_view_clip_plane_get(state.view,slot,&clip),"get clip plane");
            put(ip,reply,"slot",Tcl_NewWideIntObj(slot));
            Tcl_Obj* equation=Tcl_NewListObj(0,nullptr);
            for(double value:{clip.normal.x,clip.normal.y,clip.normal.z,
                    -(clip.normal.x*clip.origin.x+clip.normal.y*clip.origin.y+clip.normal.z*clip.origin.z)})
                Tcl_ListObjAppendElement(ip,equation,Tcl_NewDoubleObj(value));
            put(ip,reply,"equation",equation);
        }else{
            gx3de_view_clip_box box{};box.struct_size=sizeof(box);
            check(gx3de_view_clip_box_get(state.view,&box),"get clip box");
            Tcl_Obj* bounds=Tcl_NewListObj(0,nullptr);
            for(double value:{box.world_bounds.min.x,box.world_bounds.min.y,box.world_bounds.min.z,
                    box.world_bounds.max.x,box.world_bounds.max.y,box.world_bounds.max.z})
                Tcl_ListObjAppendElement(ip,bounds,Tcl_NewDoubleObj(value));
            put(ip,reply,"bounds",bounds);
        }
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    }catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
int timelineControl(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]){
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"action value png");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try{
        if(!state.timeline||!state.target)throw std::runtime_error("Create a timeline first");
        if(state.gizmo){check(gx3de_gizmo_destroy(state.gizmo),"clear timeline manipulator");
            state.gizmo=nullptr;state.gizmoObject=nullptr;state.gizmoLayer.clear();}
        std::string action=str(args[1]),value=str(args[2]),path=str(args[3]);
        gx3de_result rc=GX3DE_INVALID_ARGUMENT;
        if(action=="seek_frame")rc=gx3de_animation_seek_frame(state.timeline,integer(value,"frame"));
        else if(action=="seek_time")rc=gx3de_animation_seek_time(state.timeline,number(value,"time"));
        else if(action=="play")rc=gx3de_animation_play(state.timeline);
        else if(action=="pause")rc=gx3de_animation_pause(state.timeline);
        else if(action=="stop")rc=gx3de_animation_stop(state.timeline);
        else if(action=="step")rc=gx3de_animation_step(state.timeline,value=="-1"?-1:1);
        else if(action=="advance")rc=gx3de_animation_advance(state.timeline,number(value,"elapsed seconds"));
        else throw std::runtime_error("Unknown timeline action");
        check(rc,"control timeline");refreshTimelineObjects(state);
        checkRender(state.target,gx3de_target_render(state.target),"render timeline");
        check(gx3de_target_write_png(state.target,path.c_str()),"write timeline PNG");
        gx3de_animation_info info{};info.struct_size=sizeof(info);
        check(gx3de_animation_info_get(state.timeline,&info),"query timeline");
        Tcl_Obj* reply=Tcl_NewDictObj();
        put(ip,reply,"current_frame",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(info.current_frame)));
        put(ip,reply,"current_time",Tcl_NewDoubleObj(info.current_time));
        put(ip,reply,"state",Tcl_NewStringObj(info.state==GX3DE_ANIM_PLAYING?"playing":
            (info.state==GX3DE_ANIM_PAUSED?"paused":"stopped"),-1));
        put(ip,reply,"resident_frames",Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(info.resident_frames)));
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    }catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
#include "native3d_workbench_tcl_v1.inc"
int exportVector(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj*const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"path svg|pdf");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try {if(!state.target)throw std::runtime_error("Render a scene before vector export");
        check(gx3de_target_write_vector(state.target,str(args[1]).c_str(),str(args[2]).c_str()),"export native vector figure");
        Tcl_SetObjResult(ip,args[1]);return TCL_OK;
    }catch(const std::exception&e){error(ip,e);return TCL_ERROR;}
}
int close(ClientData data,Tcl_Interp *ip,int argc,Tcl_Obj *const args[]) {
    if(argc!=1){Tcl_WrongNumArgs(ip,1,args,"");return TCL_ERROR;}
    static_cast<State*>(data)->clear();return TCL_OK;
}
void release(ClientData data,Tcl_Interp*) {delete static_cast<State*>(data);}
} // namespace

extern "C" int Gx3deviewer_Init(Tcl_Interp *ip) {
    if(Tcl_InitStubs(ip,"8.6",0)==nullptr)return TCL_ERROR;
    auto *state=new State();
    Tcl_SetAssocData(ip,"GX3DEViewer",release,state);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::presentation",presentationUpdate,state,nullptr);
    Tcl_CreateNamespace(ip,"::GX3DEViewer",nullptr,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::capabilities",capabilities,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::texture_anchor",textureAnchor,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::render",render,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::cad",cadDispatch,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::graphics_probe",graphicsProbe,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::pick",pick,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::focus_logical",focusLogical,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::preset",preset,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::camera",cameraRestore,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::viewport",viewportResize,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::scientific_axes",scientificAxes,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::navcube_pick",navcubePick,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::navcube_click",navcubeClick,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::navigate",navigate,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::gizmo_select",gizmoSelect,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::gizmo_pick",gizmoPick,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::gizmo_begin",gizmoBegin,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::gizmo_update",gizmoUpdate,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::gizmo_end",gizmoEnd,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::export_png",exportPng,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::export_vector",exportVector,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::timeline",timelineControl,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::plane_begin",planeBegin,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::plane_update",planeUpdate,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::plane_end",planeEnd,state,nullptr);
    Tcl_CreateObjCommand(ip,"::GX3DEViewer::close",close,state,nullptr);
    Tcl_PkgProvide(ip,"Gx3deviewer","0.1.0");return TCL_OK;
}
