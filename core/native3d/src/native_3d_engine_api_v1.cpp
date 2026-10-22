// SPDX-License-Identifier: GPL-3.0-or-later
#include "native_3d_engine_api_v1.h"
#include "../../../plugins/modules/math.numeric/api/c/gxtxt_numeric_reductions_v1.h"
#include "native_3d_scientific_figure_api_v1.h"
#include <vtkCubeAxesActor.h>
#include <vtkGL2PSExporter.h>
#include <vtkStringArray.h>
#include <vtkAxesActor.h>
#include <vtkCaptionActor2D.h>
#include <vtkScalarBarActor.h>
#include <vtkTextActor.h>
#include <vtkTextProperty.h>
#include "native_3d_field_api_v1.h"
#include "native_3d_animation_api_v1.h"
#include "animation_lifecycle.hpp"
#include "mesh_prep_backend.hpp"
#include "mesh_bridge_backend.hpp"
#include "mesh_import_backend.hpp"
#include "mesh_lod_backend.hpp"
#include "mesh_repeat_backend.hpp"
#include "repeat_disk_cache_backend.hpp"
#include "mesh_self_intersection_backend.hpp"
#include "mesh_cap_backend.hpp"
#include "mesh_disk_cache_backend.hpp"
#include "step_mesh_backend.hpp"
#include "native_3d_d3d11_probe.hpp"
#include "profile_backend.hpp"
#include "scientific_backend.hpp"
#include "vtk_mesh_backend.hpp"
#include <vtkCell.h>
#include <vtkCellArray.h>
#include <vtkDataArray.h>
#include <vtkDoubleArray.h>
#include <vtkDataSet.h>
#include <vtkFieldData.h>
#include <vtkFollower.h>
#include <vtkFloatArray.h>
#include <vtkImageData.h>
#include <vtkJPEGReader.h>
#include <vtkMatrix3x3.h>
#include <vtkMatrix4x4.h>
#include <vtkPointData.h>
#include <vtkPointLocator.h>
#include <vtkPlane.h>
#include <vtkCellData.h>
#include <vtkCellType.h>
#include <vtkUnstructuredGrid.h>
#include <vtkVersion.h>
#include <vtkActor.h>
#include <vtkCubeSource.h>
#include <vtkArrowSource.h>
#include <vtkCamera.h>
#include <vtkColorTransferFunction.h>
#include <vtkCellPicker.h>
#include <vtkGeometryFilter.h>
#include <vtkGlyph3DMapper.h>
#include <vtkImageData.h>
#include <vtkLookupTable.h>
#include <vtkLight.h>
#include <vtkMapper.h>
#include <vtkNew.h>
#include <vtkPNGWriter.h>
#include <vtkSTLWriter.h>
#include <vtkXMLPolyDataWriter.h>
#include <vtkPNGReader.h>
#include <vtkPiecewiseFunction.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <vtkPolyDataMapper.h>
#include <vtkPolyDataNormals.h>
#include <vtkProperty.h>
#include <vtkRenderWindow.h>
#include <vtkRenderer.h>
#include <vtkRendererCollection.h>
#include <vtkOpenGLRenderer.h>
#include <vtkOpenGLRenderWindow.h>
#include <vtkOpenGLFramebufferObject.h>
#include <vtkOpenGLRenderPass.h>
#include <vtkInformation.h>
#include <vtkLightsPass.h>
#include <vtkCameraPass.h>
#include <vtkShadowMapPass.h>
#include <vtkShadowMapBakerPass.h>
#include <vtkShaderProgram.h>
#include <vtkOpaquePass.h>
#include <vtkRenderState.h>
#include <vtkSphereSource.h>
#include <vtkSmartVolumeMapper.h>
#include <vtkTriangle.h>
#include <vtkTriangleFilter.h>
#include <vtkTexture.h>
#include <vtkTextureObject.h>
#include <vtkTubeFilter.h>
#include <vtkUnsignedCharArray.h>
#include <vtkVertexGlyphFilter.h>
#include <vtkVectorText.h>
#include <vtkVolume.h>
#include <vtkVolumeProperty.h>
#include <vtkWindowToImageFilter.h>
#include <vtk_glew.h>
#ifdef GX3DE_WITH_OCCT
#include "occt_brep_backend.hpp"
#include "occt_step_backend.hpp"
#include <TopoDS_Shape.hxx>
#include <Standard_Version.hxx>
#endif
#include <openssl/evp.h>
#include <algorithm>
#include <atomic>
#include <array>
#include <chrono>
#include <cstdio>
#include <cmath>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <queue>
#include <memory>
#include <map>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#endif

static bool finite(gx3de_vec3 a) { return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z); }
static gx3de_vec3 add(gx3de_vec3 a,gx3de_vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
static gx3de_vec3 sub(gx3de_vec3 a,gx3de_vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
static gx3de_vec3 mul(gx3de_vec3 a,double s) { return {a.x*s,a.y*s,a.z*s}; }
static double dot(gx3de_vec3 a,gx3de_vec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
static gx3de_vec3 cross(gx3de_vec3 a,gx3de_vec3 b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
static double length(gx3de_vec3 a) { return std::sqrt(dot(a,a)); }
static gx3de_mat4 identity() { gx3de_mat4 m{}; for(int i=0;i<4;++i)m.m[5*i]=1; return m; }
static gx3de_mat4 product(const gx3de_mat4& a,const gx3de_mat4& b) {
    gx3de_mat4 c{}; for(int col=0;col<4;++col)for(int row=0;row<4;++row)
        for(int k=0;k<4;++k)c.m[col*4+row]+=a.m[k*4+row]*b.m[col*4+k]; return c;
}
static gx3de_vec3 apply(const gx3de_mat4& m,gx3de_vec3 p) { return {m.m[0]*p.x+m.m[4]*p.y+m.m[8]*p.z+m.m[12],m.m[1]*p.x+m.m[5]*p.y+m.m[9]*p.z+m.m[13],m.m[2]*p.x+m.m[6]*p.y+m.m[10]*p.z+m.m[14]}; }
static gx3de_mat4 translation(gx3de_vec3 d) { auto m=identity();m.m[12]=d.x;m.m[13]=d.y;m.m[14]=d.z;return m; }
static bool affine(const gx3de_mat4& m) { for(double v:m.m)if(!std::isfinite(v))return false;return m.m[3]==0&&m.m[7]==0&&m.m[11]==0&&m.m[15]==1; }
static bool inverse_affine(const gx3de_mat4& m,gx3de_mat4& out) {
    if(!affine(m))return false;double a=m.m[0],b=m.m[4],c=m.m[8],d=m.m[1],e=m.m[5],f=m.m[9],g=m.m[2],h=m.m[6],i=m.m[10];
    double det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g);double scale=std::max({std::abs(a),std::abs(b),std::abs(c),std::abs(d),std::abs(e),std::abs(f),std::abs(g),std::abs(h),std::abs(i)});
    if(!(scale>0)||!std::isfinite(det)||std::abs(det)<=1e-14*scale*scale*scale)return false;
    out=identity();out.m[0]=(e*i-f*h)/det;out.m[4]=(c*h-b*i)/det;out.m[8]=(b*f-c*e)/det;
    out.m[1]=(f*g-d*i)/det;out.m[5]=(a*i-c*g)/det;out.m[9]=(c*d-a*f)/det;
    out.m[2]=(d*h-e*g)/det;out.m[6]=(b*g-a*h)/det;out.m[10]=(a*e-b*d)/det;
    auto offset=apply(out,{-m.m[12],-m.m[13],-m.m[14]});out.m[12]=offset.x;out.m[13]=offset.y;out.m[14]=offset.z;return affine(out);
}
static bool transform_normal(const gx3de_mat4& m,gx3de_vec3 local,gx3de_vec3& out) {
    gx3de_mat4 inverse;if(!inverse_affine(m,inverse))return false;
    auto n=gx3de_vec3{inverse.m[0]*local.x+inverse.m[1]*local.y+inverse.m[2]*local.z,
                      inverse.m[4]*local.x+inverse.m[5]*local.y+inverse.m[6]*local.z,
                      inverse.m[8]*local.x+inverse.m[9]*local.y+inverse.m[10]*local.z};
    double magnitude=length(n);if(!(magnitude>1e-15)||!std::isfinite(magnitude))return false;
    out=mul(n,1/magnitude);return true;
}
static bool similarity_transform(const gx3de_mat4& m) {auto x=gx3de_vec3{m.m[0],m.m[1],m.m[2]},y=gx3de_vec3{m.m[4],m.m[5],m.m[6]},z=gx3de_vec3{m.m[8],m.m[9],m.m[10]};double a=dot(x,x),b=dot(y,y),c=dot(z,z),scale=std::max({a,b,c});return scale>0&&std::isfinite(scale)&&std::abs(a-b)<=1e-12*scale&&std::abs(a-c)<=1e-12*scale&&std::abs(dot(x,y))<=1e-12*scale&&std::abs(dot(x,z))<=1e-12*scale&&std::abs(dot(y,z))<=1e-12*scale;}
template<class T> static bool erase_ptr(std::vector<T*>& v,T* p) { auto it=std::find(v.begin(),v.end(),p);if(it==v.end())return false;v.erase(it);return true; }
template<class T> static gx3de_result retain(std::vector<T*>& list,T* value,T** out) {
    if(!value)return GX3DE_OUT_OF_MEMORY;
    try {list.push_back(value);*out=value;return GX3DE_OK;}
    catch(const std::bad_alloc&) {delete value;return GX3DE_OUT_OF_MEMORY;}
}
using Mesh = gx3de_backend::MeshData;
struct gx3de_engine { std::vector<gx3de_scene*> scenes; std::vector<gx3de_target*> targets;std::vector<gx3de_step_document*> step_documents;std::vector<gx3de_job*> jobs;std::vector<gx3de_texture*> textures; gx3de_graphics_policy graphics{sizeof(gx3de_graphics_policy),GX3DE_GRAPHICS_AUTO,GX3DE_LOD_FULL,0,GX3DE_LOD_MEDIUM,0,1,GX3DE_SHADOW_FULL,4000000,0,4096ull*1048576,8192ull*1048576,{sizeof(gx3de_render_quality),0,GX3DE_TRANSPARENCY_DEPTH_PEEL,0,{}},{}}; bool graphics_configured=false; std::string cache_namespace="default",disk_cache_root,scientific_disk_root;std::unordered_map<std::string,std::weak_ptr<const Mesh>> mesh_cache;std::unordered_map<std::string,std::weak_ptr<const gx3de_backend::ScientificData>> scientific_cache;uint64_t cache_hits=0,cache_misses=0,disk_hits=0,disk_misses=0,disk_invalid=0,disk_store_failures=0,scientific_disk_hits=0,scientific_disk_misses=0,scientific_disk_invalid=0,scientific_disk_store_failures=0,repeat_disk_hits=0,repeat_disk_misses=0,repeat_disk_invalid=0,repeat_disk_store_failures=0; };
struct gx3de_scene { gx3de_engine* engine; std::vector<gx3de_object*> objects;std::vector<gx3de_particle_cloud*> particle_clouds;std::vector<gx3de_scientific_light*> scientific_lights;std::vector<gx3de_group*> groups;std::vector<gx3de_plane*> planes;std::vector<gx3de_anchor*> anchors;std::vector<gx3de_measurement*> measurements;std::vector<gx3de_section*> sections;std::vector<gx3de_profile*> profiles;std::vector<gx3de_marker*> markers;std::vector<gx3de_mesh_loops*> mesh_loops;std::vector<gx3de_repeat_result*> repeats;std::vector<gx3de_constraint*> constraints;std::vector<gx3de_view*> views; bool shadows_enabled=false; };
struct gx3de_object { gx3de_scene* scene;std::shared_ptr<const Mesh> mesh;gx3de_mat4 transform;gx3de_object* parent=nullptr;bool visible=true;std::string fingerprint,source_sha256,derivation_fingerprint;std::shared_ptr<const gx3de_backend::ScientificData> scientific;double opacity=1.0,scientific_transmittance=-1.0;gx3de_scientific_field_roles field_roles{sizeof(gx3de_scientific_field_roles),0,-1,-1,-1,0,{}};
gx3de_scientific_presentation presentation{sizeof(gx3de_scientific_presentation),GX3DE_COLORMAP_VIRIDIS,0,1,0,0,0,0,2000,{}};
gx3de_field_volume_style volume_style{sizeof(gx3de_field_volume_style),0,0,1.0,0,0,{},{}};
int64_t opacity_array=-1,color_array=-1;
gx3de_object_style style{sizeof(gx3de_object_style),GX3DE_DISPLAY_SURFACE,{0.75,0.80,0.86},1.0,7.0,0,1,{}};
std::vector<gx3de_planar_texture*> planar_textures;
std::vector<gx3de_curved_texture*> curved_textures;
uint32_t geometry_role=GX3DE_GEOMETRY_REGULAR;
bool casts_shadows=true,receives_shadows=true;
gx3de_object* projection_source=nullptr;gx3de_plane* projection_plane=nullptr;
gx3de_brep_mesh_spec projection_tessellation{};bool projection_uses_tessellation=false;
#ifdef GX3DE_WITH_OCCT
std::shared_ptr<gx3de_backend::BrepShape> brep;
#endif
};
struct gx3de_particle_cloud {gx3de_scene* scene;std::vector<gx3de_particle> particles;
    gx3de_particle_cloud_style style{};gx3de_mat4 transform{};bool visible=true;
    uint64_t revision=1;vtkSmartPointer<vtkPolyData> geometry;};
struct gx3de_scientific_light {gx3de_scene* scene;gx3de_scientific_light_spec spec{};};
struct gx3de_texture_image {vtkSmartPointer<vtkImageData> pixels;uint32_t width=0,height=0,channels=0;};
struct gx3de_texture {gx3de_engine* engine;std::shared_ptr<gx3de_texture_image> image;};
struct gx3de_planar_texture {gx3de_object* object;std::shared_ptr<gx3de_texture_image> image;
    gx3de_planar_texture_spec spec{};vtkSmartPointer<vtkPolyData> patch;
    bool gizmo_visible=false;double gizmo_offset=0;};
struct CurvedFace {uint64_t id;gx3de_vec3 normal,point[3];double x[3],y[3];};
struct gx3de_curved_texture {gx3de_object* object;std::shared_ptr<gx3de_texture_image> image;
    gx3de_curved_texture_spec spec{};vtkSmartPointer<vtkPolyData> patch;
    std::vector<CurvedFace> chart;std::vector<gx3de_segment3> boundary,seams;
    gx3de_curved_texture_status status{};
    bool gizmo_visible=false;double gizmo_offset=0;};
struct gx3de_group {gx3de_scene* scene;gx3de_object* node;};
struct gx3de_plane { gx3de_scene* scene;gx3de_vec3 origin,n,u,v; };
struct gx3de_anchor { gx3de_scene* scene;gx3de_object* object=nullptr;uint64_t vertex=0;gx3de_vec3 free_point{};gx3de_anchor_kind kind=GX3DE_ANCHOR_FREE;gx3de_vec3 local_point{},local_direction{};uint32_t vertex_b=0;uint64_t triangle=0;double u=0,v=0; };
struct gx3de_measurement { gx3de_scene* scene;gx3de_measure_kind kind;gx3de_anchor *a,*b,*c;gx3de_plane* plane;gx3de_anchor* d=nullptr;gx3de_plane* plane2=nullptr;gx3de_object* surface=nullptr;
    gx3de_measurement_style style{sizeof(gx3de_measurement_style),0,1,0,{1.0,0.82,0.15},8.0,2.0,{}};};
struct gx3de_section { gx3de_scene* scene;std::vector<gx3de_segment3> segments;gx3de_vec3 origin,u,v;gx3de_object* source=nullptr;gx3de_plane* plane=nullptr;
    gx3de_curve_style style{sizeof(gx3de_curve_style),0,{0.22,0.90,0.90},2.0,1.0,{}};};
struct gx3de_profile {gx3de_scene* scene;std::vector<gx3de_backend::ProfileContour> contours;gx3de_vec3 origin,u,v;gx3de_section* source=nullptr;double join_tolerance=0;
    gx3de_curve_style style{sizeof(gx3de_curve_style),0,{1.0,0.58,0.15},2.0,1.0,{}};};
struct gx3de_marker {gx3de_scene* scene;gx3de_view* view;gx3de_anchor* anchor;gx3de_marker_style style;};
struct gx3de_mesh_loops {gx3de_scene* scene;std::vector<std::vector<uint32_t>> loops;std::vector<gx3de_vec3> world_vertices;};
struct gx3de_repeat_result {gx3de_scene* scene;gx3de_backend::RepeatResult data;gx3de_mat4 source_world;std::string source_sha256,fingerprint;bool visible;double opacity;gx3de_object* source=nullptr;bool presentation_enabled=false;};
struct gx3de_step_document {gx3de_engine* engine;std::string source_sha256;
#ifdef GX3DE_WITH_OCCT
    std::shared_ptr<gx3de_backend::StepDocument> native;
    std::vector<std::shared_ptr<gx3de_backend::BrepShape>> prototype_shapes;
    std::map<std::tuple<uint64_t,double,double,double,uint64_t,uint64_t>,std::shared_ptr<const Mesh>> prototype_meshes;
#endif
};
struct gx3de_job {gx3de_engine* engine=nullptr;gx3de_scene* scene=nullptr;std::string path;uint32_t format=0;uint64_t max_source_bytes=0,max_memory_bytes=0,max_nodes=0;
    std::thread worker;std::atomic<bool> cancel{false};std::mutex mutex;std::condition_variable condition;
    gx3de_job_state state=GX3DE_JOB_READY;gx3de_job_event events[16]{};uint32_t event_count=0,event_read=0;
    Mesh mesh;std::string source_hash,failure;uint64_t progress_permille=0;bool taken=false;
    uint32_t kind=1,lod_level=0;std::shared_ptr<const Mesh> source_mesh;
#ifdef GX3DE_WITH_OCCT
    std::shared_ptr<gx3de_backend::StepDocument> step_native;
    std::shared_ptr<const gx3de_backend::BrepShape> brep_source;
    gx3de_brep_mesh_spec brep_mesh_spec{};
    std::string derivation_fingerprint;
#endif
    gx3de_mat4 source_transform{};bool source_visible=true;double source_opacity=1.0;
    gx3de_object_style source_style{};
};
struct gx3de_constraint { gx3de_scene* scene;gx3de_constraint_spec spec;gx3de_mat4 fixed_transform;gx3de_constraint_spec_ex extended_spec{};bool extended=false; };
struct gx3de_render_prop {vtkSmartPointer<vtkActor> actor;gx3de_object* object;uint32_t geometry_kind;gx3de_mat4 pose;gx3de_gizmo* gizmo=nullptr;uint32_t gizmo_handle=0;bool derived_lod=false;};
struct gx3de_render_viewport {gx3de_viewport* viewport;vtkSmartPointer<vtkRenderer> renderer;vtkSmartPointer<vtkRenderer> navcube_renderer;vtkSmartPointer<vtkRenderer> orientation_renderer;vtkSmartPointer<vtkRenderer> figure_renderer;vtkSmartPointer<vtkCubeAxesActor> scientific_axes;std::vector<vtkSmartPointer<vtkActor>> navcube_actors;std::vector<gx3de_render_prop> props;std::vector<std::pair<vtkSmartPointer<vtkActor>,gx3de_object*>> texture_actors;std::vector<vtkSmartPointer<vtkActor>> overlay_actors;std::vector<std::pair<vtkSmartPointer<vtkVolume>,gx3de_object*>> volumes;};
struct gx3de_target { gx3de_engine* engine;uint32_t width,height;std::vector<gx3de_viewport*> viewports;uint32_t native_kind=0;uint64_t native_id=0;uint32_t logical_width=0,logical_height=0,backend_preference=0;gx3de_render_quality quality{sizeof(gx3de_render_quality),0,GX3DE_TRANSPARENCY_DEPTH_PEEL,0,{}};uint32_t interaction_active=0;bool quality_explicit=false;std::unordered_map<std::string,std::shared_ptr<const Mesh>> display_lod_cache;vtkSmartPointer<vtkRenderWindow> window;std::vector<gx3de_render_viewport> rendered;std::vector<uint8_t> rgba;std::string diagnostic,render_key;std::thread::id render_owner=std::this_thread::get_id();uint64_t completed_frames=0,geometry_rebuild_frames=0,geometry_reuse_frames=0;uint64_t gpu_budget_bytes=0,gpu_estimated_bytes=0,gpu_last_rejected_bytes=0;std::shared_ptr<void> d3d_state; };
struct gx3de_view { gx3de_scene* scene;gx3de_camera camera{};double orthographic_height=0;gx3de_plane* working_plane=nullptr;gx3de_anchor* selection=nullptr;std::array<gx3de_view_clip_plane,GX3DE_MAX_VIEW_CLIP_PLANES> clips{};gx3de_view_interaction interaction{};std::vector<gx3de_viewport*> viewports;
    gx3de_scientific_figure figure{};
    std::array<std::vector<std::string>,3> figure_axis_labels;
    std::map<std::string,double> figure_style;
    uint32_t shadow_light_mask=15;
    std::array<gx3de_positional_light,4> positional_lights{};
    std::vector<gx3de_gizmo*> gizmos;
    std::vector<gx3de_view_manipulation*> plane_manipulations;
    gx3de_view_axes axes{sizeof(gx3de_view_axes),0,0,0,nullptr,nullptr,72.0,{}};
    gx3de_view_background background{sizeof(gx3de_view_background),0,{0.08,0.10,0.14},{0.08,0.10,0.14},{}};
    gx3de_checkerboard_background checkerboard{sizeof(gx3de_checkerboard_background),0,32,0,{0.13,0.16,0.20},{0.20,0.23,0.28},{}};
    gx3de_navcube_state navcube{sizeof(gx3de_navcube_state),0,GX3DE_NAVCUBE_TOP_RIGHT,128,16,0,0,0,{}};
    gx3de_orientation_indicator orientation{sizeof(gx3de_orientation_indicator),0,GX3DE_NAVCUBE_BOTTOM_LEFT,96,16,0,{}};
    gx3de_view_lighting lighting{sizeof(gx3de_view_lighting),1,0.22,0.78,0.16,2,0,
        {{{-1,-1,-1},{1,1,1},0.9},{{1,0.5,-0.4},{1,1,1},0.45}}, {}};
    gx3de_view_clip_box clip_box{sizeof(gx3de_view_clip_box),0,{},{}};
};
struct gx3de_gizmo {gx3de_view* view;gx3de_gizmo_spec spec{};uint32_t hover=0,active=0;
    gx3de_mat4 initial_local{},initial_world{};gx3de_vec3 pivot{},basis[3]{},start_point{};
    gx3de_vec3 drag_normal{},translation_world{};double angle=0;
    std::vector<std::pair<gx3de_object*,gx3de_mat4>> initial_scene_poses;};
struct gx3de_viewport { gx3de_target* target;gx3de_view* view;uint32_t x,y,width,height; };
struct gx3de_view_manipulation {gx3de_viewport* viewport;uint32_t target,slot,action,handle,start_x,start_y;
    gx3de_plane* plane=nullptr;gx3de_vec3 origin{},normal{},u{},forward{};
    gx3de_view_clip_plane clip{};gx3de_view_clip_box box{};};
static gx3de_mat4 world(const gx3de_object* object) { return object->parent?product(world(object->parent),object->transform):object->transform; }
static Mesh placed_mesh(const gx3de_object* object) {Mesh result=*object->mesh;auto m=world(object);for(auto& vertex:result.vertices)vertex=apply(m,vertex);return result;}
struct gx3de_beam_exit {double distance,transmittance;};
static bool scientific_light_valid(const gx3de_scientific_light_spec* s){
    if(!s||s->struct_size<sizeof(*s)||s->enabled>1||s->shadows_enabled>1||s->beam_visible>1||
       !finite(s->position)||!finite(s->direction)||length(s->direction)<1e-12)return false;
    const double values[]={s->wavelength_nm,s->intensity,s->cone_angle_degrees,s->beam_range,
        s->attenuation_constant,s->attenuation_linear,s->attenuation_quadratic,
        s->falloff_exponent,s->beam_radius};
    for(double value:values)if(!std::isfinite(value))return false;
    return s->wavelength_nm>=100&&s->wavelength_nm<=1e6&&s->intensity>=0&&s->intensity<=100&&
        s->cone_angle_degrees>=1&&s->cone_angle_degrees<=85&&s->beam_range>0&&s->beam_range<=1e6&&
        s->attenuation_constant>=0&&s->attenuation_linear>=0&&s->attenuation_quadratic>=0&&
        s->attenuation_constant+s->attenuation_linear+s->attenuation_quadratic>0&&
        s->falloff_exponent>=0&&s->falloff_exponent<=128&&s->beam_radius>0&&s->beam_radius<=1000;
}
static gx3de_rgb scientific_light_rgb(double wavelength){
    if(wavelength<380||wavelength>780)return {0,0,0};
    double r=0,g=0,b=0;
    if(wavelength<440){r=(440-wavelength)/60;b=1;}
    else if(wavelength<490){g=(wavelength-440)/50;b=1;}
    else if(wavelength<510){g=1;b=(510-wavelength)/20;}
    else if(wavelength<580){r=(wavelength-510)/70;g=1;}
    else if(wavelength<645){r=1;g=(645-wavelength)/65;}
    else r=1;
    const double edge=wavelength<420?.3+.7*(wavelength-380)/40:
        wavelength>700?.3+.7*(780-wavelength)/80:1;
    return {std::pow(r*edge,.8),std::pow(g*edge,.8),std::pow(b*edge,.8)};
}
static bool scientific_ray_triangle(gx3de_vec3 origin,gx3de_vec3 direction,
    gx3de_vec3 a,gx3de_vec3 b,gx3de_vec3 c,double max_distance,double& t){
    const auto edge1=sub(b,a),edge2=sub(c,a),p=cross(direction,edge2);
    const double determinant=dot(edge1,p);
    if(std::abs(determinant)<1e-13)return false;
    const double inv=1.0/determinant;const auto offset=sub(origin,a);
    const double u=dot(offset,p)*inv;if(u<-1e-9||u>1+1e-9)return false;
    const auto q=cross(offset,edge1);const double v=dot(direction,q)*inv;
    if(v<-1e-9||u+v>1+1e-9)return false;
    t=dot(edge2,q)*inv;return t>1e-8&&t<max_distance;
}
/* Pair deduplicated intersections of closed opt-in mesh bodies. Open meshes
 * with unmatched crossings do not produce a transmission event. */
static std::vector<gx3de_beam_exit> scientific_beam_exits(const gx3de_scientific_light* light){
    std::vector<gx3de_beam_exit> exits;const auto& s=light->spec;
    for(const auto* object:light->scene->objects){
        if(!object->visible||!object->mesh||object->scientific_transmittance<0)continue;
        std::vector<double> hits;const auto& mesh=*object->mesh;const auto transform=world(object);
        for(size_t i=0;i+2<mesh.triangles.size();i+=3){
            const auto a=apply(transform,mesh.vertices[mesh.triangles[i]]);
            const auto b=apply(transform,mesh.vertices[mesh.triangles[i+1]]);
            const auto c=apply(transform,mesh.vertices[mesh.triangles[i+2]]);
            double t=0;if(scientific_ray_triangle(s.position,s.direction,a,b,c,s.beam_range,t))hits.push_back(t);
        }
        std::sort(hits.begin(),hits.end());std::vector<double> unique;
        const double epsilon=std::max(1e-7,s.beam_range*1e-8);
        for(double t:hits)if(unique.empty()||t-unique.back()>epsilon)unique.push_back(t);
        for(size_t i=1;i<unique.size();i+=2)
            exits.push_back({unique[i],object->scientific_transmittance});
    }
    std::sort(exits.begin(),exits.end(),[](const auto& a,const auto& b){return a.distance<b.distance;});
    return exits;
}
static double scientific_geometric_factor(const gx3de_scientific_light_spec& s,double distance){
    const double denom=s.attenuation_constant+s.attenuation_linear*distance+
        s.attenuation_quadratic*distance*distance;
    return denom>0?1.0/denom:0.0;
}
static void remove_viewport(gx3de_viewport* p) {
    auto& manipulations=p->view->plane_manipulations;
    for(size_t i=0;i<manipulations.size();){if(manipulations[i]->viewport==p)
        gx3de_view_manipulation_end(manipulations[i],0);else ++i;}
    erase_ptr(p->target->viewports,p);erase_ptr(p->view->viewports,p);delete p; }
static void remove_view(gx3de_view* p) { while(!p->viewports.empty())remove_viewport(p->viewports.back());
    for(auto* gizmo:p->gizmos){if(gizmo->active)gx3de_gizmo_end(gizmo,0);delete gizmo;}
    for(size_t i=0;i<p->scene->markers.size();)if(p->scene->markers[i]->view==p){delete p->scene->markers[i];p->scene->markers.erase(p->scene->markers.begin()+i);}else ++i;
    erase_ptr(p->scene->views,p);delete p; }
static void remove_target(gx3de_target* p) { while(!p->viewports.empty())remove_viewport(p->viewports.back());erase_ptr(p->engine->targets,p);delete p; }
static void remove_job(gx3de_job* job) {job->cancel.store(true);if(job->worker.joinable())job->worker.join();erase_ptr(job->engine->jobs,job);delete job;}
static void remove_scene(gx3de_scene* s) {
    for(size_t i=0;i<s->engine->jobs.size();){auto job=s->engine->jobs[i];if(job->scene==s)remove_job(job);else ++i;}
    gx3de_animation_scene_cleanup(s);
    while(!s->views.empty())remove_view(s->views.back());
    for(auto p:s->constraints)delete p;for(auto p:s->repeats)delete p;for(auto p:s->mesh_loops)delete p;for(auto p:s->markers)delete p;for(auto p:s->profiles)delete p;for(auto p:s->sections)delete p;
    for(auto p:s->groups)delete p;
    for(auto p:s->measurements)delete p;for(auto p:s->anchors)delete p;
    for(auto p:s->planes)delete p;
    for(auto p:s->particle_clouds)delete p;
    for(auto p:s->scientific_lights)delete p;
    for(auto p:s->objects){for(auto* texture:p->planar_textures)delete texture;
        for(auto* texture:p->curved_textures)delete texture;delete p;}
    erase_ptr(s->engine->scenes,s);delete s;
}
static bool valid_utf8(const char* s,size_t max_bytes=255) {
    if(!s)return false;size_t n=std::strlen(s);if(n==0||n>max_bytes)return false;
    for(size_t i=0;i<n;){unsigned char c=static_cast<unsigned char>(s[i]);size_t count=0;
        if(c<0x80){if(c<0x20)return false;++i;continue;}
        if(c>=0xc2&&c<=0xdf)count=2;else if(c>=0xe0&&c<=0xef)count=3;else if(c>=0xf0&&c<=0xf4)count=4;else return false;
        if(i+count>n)return false;for(size_t j=1;j<count;++j)if((static_cast<unsigned char>(s[i+j])&0xc0)!=0x80)return false;
        unsigned char d=static_cast<unsigned char>(s[i+1]);if((c==0xe0&&d<0xa0)||(c==0xed&&d>=0xa0)||(c==0xf0&&d<0x90)||(c==0xf4&&d>=0x90))return false;i+=count;
    }return true;
}
static std::string sha256_source_file(const std::filesystem::path& path) {
    std::ifstream input(path,std::ios::binary);if(!input)return {};
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)return {};
    std::array<char,65536> buffer{};
    while(input){input.read(buffer.data(),buffer.size());auto n=input.gcount();if(n>0&&EVP_DigestUpdate(ctx.get(),buffer.data(),size_t(n))!=1)return {};}
    if(!input.eof())return {};
    unsigned char digest[32];unsigned int n=0;if(EVP_DigestFinal_ex(ctx.get(),digest,&n)!=1||n!=32)return {};
    static constexpr char hex[]="0123456789abcdef";std::string result(64,'0');
    for(size_t i=0;i<32;++i){result[2*i]=hex[digest[i]>>4];result[2*i+1]=hex[digest[i]&15];}return result;
}
static bool digest_u64(EVP_MD_CTX* ctx,uint64_t value) {unsigned char b[8];for(int i=0;i<8;++i)b[i]=static_cast<unsigned char>(value>>(8*i));return EVP_DigestUpdate(ctx,b,8)==1;}
static std::string fingerprint(const Mesh& mesh,const std::string& space) {
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(),EVP_MD_CTX_free);if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)return {};
    static constexpr char tag[]="GX3DE_MESH_v1";if(EVP_DigestUpdate(ctx.get(),tag,sizeof(tag))!=1||!digest_u64(ctx.get(),space.size())||EVP_DigestUpdate(ctx.get(),space.data(),space.size())!=1)return {};
    if(!digest_u64(ctx.get(),mesh.vertices.size())||!digest_u64(ctx.get(),mesh.triangles.size()))return {};
    for(auto p:mesh.vertices)for(double value:{p.x,p.y,p.z}){uint64_t bits;std::memcpy(&bits,&value,8);if(!digest_u64(ctx.get(),bits))return {};}
    for(auto index:mesh.triangles)if(!digest_u64(ctx.get(),index))return {};
    unsigned char digest[EVP_MAX_MD_SIZE];unsigned int digest_size=0;if(EVP_DigestFinal_ex(ctx.get(),digest,&digest_size)!=1||digest_size!=32)return {};
    static constexpr char hex[]="0123456789abcdef";std::string out(64,'0');
    for(size_t i=0;i<32;++i){out[i*2]=hex[digest[i]>>4];out[i*2+1]=hex[digest[i]&15];}return out;
}
static std::string repeat_fingerprint(const std::string& source,uint64_t triangle) {
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)return {};
    static constexpr char tag[]="GX3DE_MESH_REPEATS_v1|legacy-24-rotations|exact-point-connectivity";
    if(EVP_DigestUpdate(ctx.get(),tag,sizeof(tag))!=1||
       EVP_DigestUpdate(ctx.get(),source.data(),source.size())!=1||
       !digest_u64(ctx.get(),triangle))return {};
    unsigned char digest[32];unsigned int n=0;
    if(EVP_DigestFinal_ex(ctx.get(),digest,&n)!=1||n!=32)return {};
    static constexpr char hex[]="0123456789abcdef";std::string out(64,'0');
    for(size_t i=0;i<32;++i){out[i*2]=hex[digest[i]>>4];out[i*2+1]=hex[digest[i]&15];}
    return out;
}
static std::string projection_fingerprint(const gx3de_object* source,const gx3de_plane* plane) {
    std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)return {};
    static constexpr char tag[]="GX3DE_SCIENTIFIC_PROJECTION_v1";
    if(EVP_DigestUpdate(ctx.get(),tag,sizeof(tag))!=1||
       EVP_DigestUpdate(ctx.get(),source->fingerprint.data(),source->fingerprint.size())!=1)return {};
    const auto pose=world(source);
    for(double value:pose.m){uint64_t bits;std::memcpy(&bits,&value,8);if(!digest_u64(ctx.get(),bits))return {};}
    for(auto value:{plane->origin.x,plane->origin.y,plane->origin.z,
                    plane->n.x,plane->n.y,plane->n.z}){
        uint64_t bits;std::memcpy(&bits,&value,8);if(!digest_u64(ctx.get(),bits))return {};}
    unsigned char digest[32];unsigned int n=0;
    if(EVP_DigestFinal_ex(ctx.get(),digest,&n)!=1||n!=32)return {};
    static constexpr char hex[]="0123456789abcdef";std::string out(64,'0');
    for(size_t i=0;i<32;++i){out[2*i]=hex[digest[i]>>4];out[2*i+1]=hex[digest[i]&15];}
    return out;
}
static gx3de_result retain_mesh(gx3de_scene* s,Mesh&& source,gx3de_object** out) {
    try {auto* engine=s->engine;auto key=fingerprint(source,engine->cache_namespace);if(key.empty())return GX3DE_OUT_OF_MEMORY;std::shared_ptr<const Mesh> mesh;
        auto it=engine->mesh_cache.find(key);if(it!=engine->mesh_cache.end())mesh=it->second.lock();
        if(mesh)++engine->cache_hits;else {mesh=std::make_shared<Mesh>(std::move(source));engine->mesh_cache[key]=mesh;++engine->cache_misses;}
        auto o=new gx3de_object{s,std::move(mesh),identity()};o->fingerprint=key;return retain(s->objects,o,out);}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
static gx3de_result retain_scientific(gx3de_scene* s,gx3de_backend::ScientificData&& source,gx3de_object** out) {
    try {
        if(source.fingerprint_sha256_hex.size()!=64)return GX3DE_DEGENERATE;
        auto* engine=s->engine;
        const std::string cache_key=engine->cache_namespace+"|scientific|"+source.fingerprint_sha256_hex;
        std::shared_ptr<const gx3de_backend::ScientificData> data;
        auto it=engine->scientific_cache.find(cache_key);
        if(it!=engine->scientific_cache.end())data=it->second.lock();
        if(!data){data=std::make_shared<gx3de_backend::ScientificData>(std::move(source));
            engine->scientific_cache[cache_key]=data;}
        auto o=new gx3de_object{s,nullptr,identity()};
        o->fingerprint=data->fingerprint_sha256_hex;
        o->source_sha256=data->source_sha256_hex;
        o->scientific=std::move(data);
        return retain(s->objects,o,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
static void job_event_locked(gx3de_job* job,gx3de_job_state state,uint64_t progress_permille) {
    job->state=state;job->progress_permille=progress_permille;
    if(job->event_count<16){uint64_t sequence=job->event_count+1;
        job->events[job->event_count]={sizeof(gx3de_job_event),uint32_t(state),sequence,progress_permille,{}};++job->event_count;}
    job->condition.notify_all();
}
static bool import_cancelled(void* user) {return static_cast<gx3de_job*>(user)->cancel.load();}
static void import_progress(void* user,uint64_t progress_permille) {
    auto* job=static_cast<gx3de_job*>(user);
    std::lock_guard<std::mutex> lock(job->mutex);
    if(job->state==GX3DE_JOB_RUNNING&&!job->cancel.load()&&progress_permille>job->progress_permille)
        job_event_locked(job,GX3DE_JOB_RUNNING,progress_permille);
}
extern "C" {
gx3de_result gx3de_get_info(gx3de_info* p) { if(!p||p->struct_size<sizeof(gx3de_info))return GX3DE_RANGE;*p={sizeof(gx3de_info),GX3DE_ABI_VERSION,GX3DE_CAP_SCENE|GX3DE_CAP_MESH|GX3DE_CAP_PLANE|GX3DE_CAP_MEASUREMENT|GX3DE_CAP_HEADLESS_TARGET|GX3DE_CAP_HIERARCHY|GX3DE_CAP_MESH_DIAGNOSTICS|GX3DE_CAP_MESH_APPEND|GX3DE_CAP_MESH_SECTION|GX3DE_CAP_MESH_PREP|GX3DE_CAP_CONSTRAINT_BASIC|GX3DE_CAP_CACHE_FINGERPRINT|GX3DE_CAP_EXTENDED_ANCHOR|GX3DE_CAP_EXTENDED_MEASUREMENT|GX3DE_CAP_MESH_CLIP|GX3DE_CAP_MESH_CAPPED_CLIP|GX3DE_CAP_MESH_BOUNDARY|GX3DE_CAP_GROUP|GX3DE_CAP_CHAINED_PROFILE|GX3DE_CAP_MESH_IMPORT|GX3DE_CAP_MESH_PREVIEW|GX3DE_CAP_MESH_MEMORY_BUDGET|GX3DE_CAP_MESH_LOD|GX3DE_CAP_MESH_REPEATS|GX3DE_CAP_MESH_LOOPS|GX3DE_CAP_MESH_STITCH|GX3DE_CAP_MESH_ORIENT|GX3DE_CAP_MESH_SELF_INTERSECTION|GX3DE_CAP_RIGID_ALIGNMENT|GX3DE_CAP_ASYNC_MESH_IMPORT|GX3DE_CAP_EXTENDED_CONSTRAINTS
    |GX3DE_CAP_SCIENTIFIC_DATA|GX3DE_CAP_SCIENTIFIC_XML_IMPORT|GX3DE_CAP_SCIENTIFIC_ISOSURFACE|GX3DE_CAP_SCIENTIFIC_POLYDATA_CREATE|GX3DE_CAP_SCIENTIFIC_VECTOR_SAMPLING|GX3DE_CAP_SCIENTIFIC_IMAGE_CREATE|GX3DE_CAP_SCIENTIFIC_UNSTRUCTURED_CREATE|GX3DE_CAP_VIEW_LOCAL_STATE|GX3DE_CAP_MESH_INTERSECTION_PAIRS|GX3DE_CAP_JOB_PROGRESS|GX3DE_CAP_CONSTRAINT_SYSTEM|GX3DE_CAP_LINE_OBJECT_ANCHORS|GX3DE_CAP_ASYNC_MESH_LOD|GX3DE_CAP_MESH_BRIDGE|GX3DE_CAP_PIXEL_RENDER|GX3DE_CAP_RENDER_PICK|GX3DE_CAP_NATIVE_WINDOW_TARGET|GX3DE_CAP_SCIENTIFIC_PRESENTATION|GX3DE_CAP_VIEW_PRESENTATION
#ifndef _WIN32
    |GX3DE_CAP_PERSISTENT_MESH_CACHE|GX3DE_CAP_PERSISTENT_SCIENTIFIC_CACHE|GX3DE_CAP_PERSISTENT_REPEAT_CACHE
#endif
#ifdef GX3DE_WITH_OCCT
    |GX3DE_CAP_BREP|GX3DE_CAP_BREP_CLIP|GX3DE_CAP_BREP_ANCHOR|GX3DE_CAP_STEP_XDE_STRUCTURE|GX3DE_CAP_BREP_VALIDATION|GX3DE_CAP_STEP_PROTOTYPE_MESH|GX3DE_CAP_BREP_HEAL|GX3DE_CAP_BREP_FINGERPRINT|GX3DE_CAP_BREP_CURVE_QUERY|GX3DE_CAP_ASYNC_STEP_IMPORT|GX3DE_CAP_BREP_MESH_CONVERSION
#endif
    ,{GX3DE_CAP2_RENDER_MARKERS|GX3DE_CAP2_TRANSFORM_GIZMO|GX3DE_CAP2_TARGET_RESIZE|GX3DE_CAP2_CAMERA_NAVIGATION|GX3DE_CAP2_RENDER_QUALITY|GX3DE_CAP2_RENDERER_DIAGNOSTICS|GX3DE_CAP2_CAPABILITY_GROUPS|GX3DE_CAP2_GRAPHICS_POLICY|GX3DE_CAP2_PLANAR_TEXTURE|GX3DE_CAP2_SHADOWS|GX3DE_CAP2_PLANAR_GIZMO|GX3DE_CAP2_PLANAR_MANIPULATION|GX3DE_CAP2_NAVIGATION_CUBE|GX3DE_CAP2_CHECKERBOARD_BACKGROUND|GX3DE_CAP2_CURVED_TEXTURE|GX3DE_CAP2_SHADOW_POLICY|GX3DE_CAP2_PARTICLE_CLOUD|GX3DE_CAP2_POSITIONAL_LIGHT|GX3DE_CAP2_SCIENTIFIC_DIRECT_COLOR|GX3DE_CAP2_SCIENTIFIC_LIGHT_SOURCES|GX3DE_CAP2_INPUT_PROFILE|GX3DE_CAP2_GEOMETRY_EXPORT
#ifdef GX3DE_WITH_OCCT
    |GX3DE_CAP2_PROFILE_EXTRUDE
#endif
    ,0,0,0}};return GX3DE_OK; }
gx3de_result gx3de_get_capabilities(uint32_t group,gx3de_capability_set* out) {
    if(!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(group<GX3DE_API_GROUP_CORE||group>GX3DE_API_GROUP_FIELD)return GX3DE_INVALID_ARGUMENT;
    *out={};out->struct_size=sizeof(*out);out->api_group=group;out->word_count=4;
    if(group==GX3DE_API_GROUP_CORE){gx3de_info info{sizeof(info)};auto rc=gx3de_get_info(&info);
        if(rc!=GX3DE_OK)return rc;out->api_version=GX3DE_ABI_VERSION;
        out->words[0]=info.capabilities;out->words[1]=info.reserved[0];}
    else if(group==GX3DE_API_GROUP_RENDERER){out->api_version=1;
        out->words[0]=GX3DE_CAP_PIXEL_RENDER|GX3DE_CAP_RENDER_PICK|
            GX3DE_CAP_NATIVE_WINDOW_TARGET|GX3DE_CAP_VIEW_PRESENTATION;
        out->words[1]=GX3DE_CAP2_RENDER_MARKERS|GX3DE_CAP2_TRANSFORM_GIZMO|
            GX3DE_CAP2_TARGET_RESIZE|GX3DE_CAP2_CAMERA_NAVIGATION|
            GX3DE_CAP2_RENDER_QUALITY|GX3DE_CAP2_RENDERER_DIAGNOSTICS|
            GX3DE_CAP2_GRAPHICS_POLICY|GX3DE_CAP2_PLANAR_TEXTURE|
            GX3DE_CAP2_SHADOWS|GX3DE_CAP2_PLANAR_GIZMO|
            GX3DE_CAP2_PLANAR_MANIPULATION|GX3DE_CAP2_NAVIGATION_CUBE|
            GX3DE_CAP2_CHECKERBOARD_BACKGROUND|GX3DE_CAP2_CURVED_TEXTURE|
            GX3DE_CAP2_SHADOW_POLICY|GX3DE_CAP2_PARTICLE_CLOUD|
            GX3DE_CAP2_POSITIONAL_LIGHT|GX3DE_CAP2_SCIENTIFIC_DIRECT_COLOR|
            GX3DE_CAP2_SCIENTIFIC_LIGHT_SOURCES;}
    else if(group==GX3DE_API_GROUP_ANIMATION){out->api_version=GX3DE_ANIMATION_API_VERSION;
        out->words[0]=GX3DE_ANIM_CAP_TIMELINE|GX3DE_ANIM_CAP_LAZY_FRAMES|
            GX3DE_ANIM_CAP_PNG_SEQUENCE|GX3DE_ANIM_CAP_MULTILAYER|
            GX3DE_ANIM_CAP_DERIVED_FIELD;}
    else if(group==GX3DE_API_GROUP_FIELD){out->api_version=GX3DE_FIELD_API_VERSION;
        out->words[0]=GX3DE_FIELD_CAP_LINES|GX3DE_FIELD_CAP_SLICE|
            GX3DE_FIELD_CAP_VOLUME_TRANSFER|GX3DE_FIELD_CAP_PATHLINES|
            GX3DE_FIELD_CAP_UNSTRUCTURED;}
    return GX3DE_OK;
}
const char* gx3de_result_name(gx3de_result r) { static const char* names[]={"OK","INVALID_ARGUMENT","OUT_OF_MEMORY","NOT_FOUND","UNSUPPORTED","RANGE","WRONG_OWNER","DEGENERATE"};return unsigned(r)<8?names[r]:"UNKNOWN"; }
gx3de_result gx3de_engine_create(gx3de_engine** out) { if(!out)return GX3DE_INVALID_ARGUMENT;*out=new(std::nothrow) gx3de_engine;return *out?GX3DE_OK:GX3DE_OUT_OF_MEMORY; }
void gx3de_engine_destroy(gx3de_engine* e) { if(!e)return;while(!e->jobs.empty())remove_job(e->jobs.back());while(!e->targets.empty())remove_target(e->targets.back());while(!e->scenes.empty())remove_scene(e->scenes.back());for(auto doc:e->step_documents)delete doc;for(auto texture:e->textures)delete texture;delete e; }
gx3de_result gx3de_engine_set_cache_namespace(gx3de_engine* e,const char* name) {if(!e||!valid_utf8(name))return GX3DE_INVALID_ARGUMENT;try{e->cache_namespace=name;e->mesh_cache.clear();e->scientific_cache.clear();e->cache_hits=e->cache_misses=0;return GX3DE_OK;}catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}}
gx3de_result gx3de_engine_cache_stats(gx3de_engine* e,gx3de_cache_stats* out) {if(!e||!out||out->struct_size<sizeof(gx3de_cache_stats))return GX3DE_INVALID_ARGUMENT;*out={sizeof(gx3de_cache_stats),0,e->mesh_cache.size(),e->cache_hits,e->cache_misses,{}};return GX3DE_OK;}
gx3de_result gx3de_engine_set_mesh_cache_root(gx3de_engine* e,const char* path) {
    if(!e)return GX3DE_INVALID_ARGUMENT;if(path&&!valid_utf8(path,4096))return GX3DE_INVALID_ARGUMENT;
#ifdef _WIN32
    if(path)return GX3DE_UNSUPPORTED;
#endif
    try {e->disk_cache_root=path?path:"";e->disk_hits=e->disk_misses=e->disk_invalid=e->disk_store_failures=0;
        e->repeat_disk_hits=e->repeat_disk_misses=e->repeat_disk_invalid=e->repeat_disk_store_failures=0;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_engine_disk_cache_stats(gx3de_engine* e,gx3de_disk_cache_stats* out) {
    if(!e||!out||out->struct_size<sizeof(gx3de_disk_cache_stats))return GX3DE_INVALID_ARGUMENT;
    *out={sizeof(gx3de_disk_cache_stats),uint32_t(!e->disk_cache_root.empty()),e->disk_hits,e->disk_misses,e->disk_invalid,e->disk_store_failures,{}};return GX3DE_OK;
}
gx3de_result gx3de_engine_repeat_cache_stats(gx3de_engine* e,gx3de_disk_cache_stats* out) {
    if(!e||!out||out->struct_size<sizeof(gx3de_disk_cache_stats))return GX3DE_INVALID_ARGUMENT;
    *out={sizeof(gx3de_disk_cache_stats),uint32_t(!e->disk_cache_root.empty()),
        e->repeat_disk_hits,e->repeat_disk_misses,e->repeat_disk_invalid,e->repeat_disk_store_failures,{}};
    return GX3DE_OK;
}
gx3de_result gx3de_engine_set_scientific_cache_root(gx3de_engine* e,const char* path) {
    if(!e)return GX3DE_INVALID_ARGUMENT;if(path&&!valid_utf8(path,4096))return GX3DE_INVALID_ARGUMENT;
#ifdef _WIN32
    if(path)return GX3DE_UNSUPPORTED;
#endif
    try {e->scientific_disk_root=path?path:"";
        e->scientific_disk_hits=e->scientific_disk_misses=e->scientific_disk_invalid=e->scientific_disk_store_failures=0;
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_engine_scientific_cache_stats(gx3de_engine* e,gx3de_disk_cache_stats* out) {
    if(!e||!out||out->struct_size<sizeof(gx3de_disk_cache_stats))return GX3DE_INVALID_ARGUMENT;
    *out={sizeof(gx3de_disk_cache_stats),uint32_t(!e->scientific_disk_root.empty()),
          e->scientific_disk_hits,e->scientific_disk_misses,e->scientific_disk_invalid,
          e->scientific_disk_store_failures,{}};return GX3DE_OK;
}
gx3de_result gx3de_scene_create(gx3de_engine* e,gx3de_scene** out) { if(!e||!out)return GX3DE_INVALID_ARGUMENT;auto s=new(std::nothrow) gx3de_scene{};if(!s)return GX3DE_OUT_OF_MEMORY;s->engine=e;return retain(e->scenes,s,out); }
gx3de_result gx3de_scene_destroy(gx3de_scene* s) { if(!s)return GX3DE_INVALID_ARGUMENT;remove_scene(s);return GX3DE_OK; }
gx3de_result gx3de_scientific_light_create(gx3de_scene* scene,
    const gx3de_scientific_light_spec* spec,gx3de_scientific_light** out){
    if(!scene||!out||!scientific_light_valid(spec))return GX3DE_INVALID_ARGUMENT;
    if(scene->scientific_lights.size()>=32)return GX3DE_RANGE;
    auto* light=new(std::nothrow) gx3de_scientific_light{scene,{}};
    if(!light)return GX3DE_OUT_OF_MEMORY;
    light->spec=*spec;light->spec.struct_size=sizeof(*spec);
    light->spec.direction=mul(spec->direction,1.0/length(spec->direction));
    return retain(scene->scientific_lights,light,out);
}
gx3de_result gx3de_scientific_light_set(gx3de_scientific_light* light,
    const gx3de_scientific_light_spec* spec){
    if(!light||!scientific_light_valid(spec))return GX3DE_INVALID_ARGUMENT;
    light->spec=*spec;light->spec.struct_size=sizeof(*spec);
    light->spec.direction=mul(spec->direction,1.0/length(spec->direction));return GX3DE_OK;
}
gx3de_result gx3de_scientific_light_get(gx3de_scientific_light* light,
    gx3de_scientific_light_spec* spec){
    if(!light||!spec||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    *spec=light->spec;return GX3DE_OK;
}
gx3de_result gx3de_scientific_light_destroy(gx3de_scientific_light* light){
    if(!light)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(light->scene->scientific_lights,light);delete light;return GX3DE_OK;
}
gx3de_result gx3de_scientific_light_count(gx3de_scene* scene,uint32_t* count){
    if(!scene||!count)return GX3DE_INVALID_ARGUMENT;
    *count=static_cast<uint32_t>(scene->scientific_lights.size());return GX3DE_OK;
}
gx3de_result gx3de_scientific_light_frequency_hz(gx3de_scientific_light* light,double* frequency){
    if(!light||!frequency)return GX3DE_INVALID_ARGUMENT;
    *frequency=299792458.0/(light->spec.wavelength_nm*1e-9);return GX3DE_OK;
}
gx3de_result gx3de_scientific_light_display_rgb(gx3de_scientific_light* light,gx3de_rgb* rgb){
    if(!light||!rgb)return GX3DE_INVALID_ARGUMENT;
    *rgb=scientific_light_rgb(light->spec.wavelength_nm);return GX3DE_OK;
}
gx3de_result gx3de_scientific_light_beam_sample(gx3de_scientific_light* light,double distance,
    gx3de_scientific_beam_sample* sample){
    if(!light||!sample||sample->struct_size<sizeof(*sample)||!std::isfinite(distance)||
       distance<0||distance>light->spec.beam_range)return GX3DE_INVALID_ARGUMENT;
    const auto& s=light->spec;double optical=1;uint32_t traversals=0;
    try{for(const auto& event:scientific_beam_exits(light))if(event.distance<=distance){
        optical*=event.transmittance;++traversals;}}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
    *sample={sizeof(*sample),traversals,add(s.position,mul(s.direction,distance)),distance,
        scientific_geometric_factor(s,distance),optical,
        (s.enabled?s.intensity:0)*scientific_geometric_factor(s,distance)*optical,{}};
    return GX3DE_OK;
}
static bool cloud_color(gx3de_rgb c){return std::isfinite(c.r)&&std::isfinite(c.g)&&std::isfinite(c.b)&&
    c.r>=0&&c.r<=1&&c.g>=0&&c.g<=1&&c.b>=0&&c.b<=1;}
static bool cloud_style_valid(const gx3de_particle_cloud_style* s){return s&&s->struct_size>=sizeof(*s)&&
    std::isfinite(s->radius)&&s->radius>0&&s->radius<=100000&&cloud_color(s->color)&&
    std::isfinite(s->opacity)&&s->opacity>=0&&s->opacity<=1;}
static bool cloud_particles_valid(const gx3de_particle* p,uint64_t n){
    if(n>100000||(n&&!p))return false;
    for(uint64_t i=0;i<n;++i){const auto& a=p[i];
        if(!finite(a.position)||(a.flags&~(GX3DE_PARTICLE_RADIUS|GX3DE_PARTICLE_COLOR))||
           ((a.flags&GX3DE_PARTICLE_RADIUS)&&(!std::isfinite(a.radius)||a.radius<=0||a.radius>100000))||
           ((a.flags&GX3DE_PARTICLE_COLOR)&&!cloud_color(a.color)))return false;}
    return true;
}
gx3de_result gx3de_particle_cloud_create(gx3de_scene* s,const gx3de_particle_cloud_style* style,
    const gx3de_particle* particles,uint64_t count,gx3de_particle_cloud** out){
    if(!s||!out||!cloud_style_valid(style)||!cloud_particles_valid(particles,count))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;auto* c=new(std::nothrow) gx3de_particle_cloud{};if(!c)return GX3DE_OUT_OF_MEMORY;
    c->scene=s;c->style=*style;c->style.struct_size=sizeof(*style);c->transform=identity();
    try{if(count)c->particles.assign(particles,particles+count);return retain(s->particle_clouds,c,out);}
    catch(const std::bad_alloc&){delete c;return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_particle_cloud_destroy(gx3de_particle_cloud* c){if(!c)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(c->scene->particle_clouds,c);delete c;return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_particles_set(gx3de_particle_cloud* c,const gx3de_particle* p,uint64_t n){
    if(!c||!cloud_particles_valid(p,n))return GX3DE_INVALID_ARGUMENT;
    try{std::vector<gx3de_particle> replacement;if(n)replacement.assign(p,p+n);
        c->particles.swap(replacement);c->geometry=nullptr;++c->revision;return GX3DE_OK;}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_particle_cloud_count_get(gx3de_particle_cloud* c,uint64_t* n){
    if(!c||!n)return GX3DE_INVALID_ARGUMENT;*n=c->particles.size();return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_style_set(gx3de_particle_cloud* c,const gx3de_particle_cloud_style* s){
    if(!c||!cloud_style_valid(s))return GX3DE_INVALID_ARGUMENT;c->style=*s;c->style.struct_size=sizeof(*s);
    c->geometry=nullptr;++c->revision;return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_style_get(gx3de_particle_cloud* c,gx3de_particle_cloud_style* s){
    if(!c||!s||s->struct_size<sizeof(*s))return GX3DE_INVALID_ARGUMENT;*s=c->style;return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_transform_set(gx3de_particle_cloud* c,const gx3de_mat4* m){
    if(!c||!m||!affine(*m))return GX3DE_INVALID_ARGUMENT;c->transform=*m;return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_transform_get(gx3de_particle_cloud* c,gx3de_mat4* m){
    if(!c||!m)return GX3DE_INVALID_ARGUMENT;*m=c->transform;return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_visible_set(gx3de_particle_cloud* c,uint32_t v){
    if(!c||v>1)return GX3DE_INVALID_ARGUMENT;c->visible=v!=0;return GX3DE_OK;}
gx3de_result gx3de_particle_cloud_visible_get(gx3de_particle_cloud* c,uint32_t* v){
    if(!c||!v)return GX3DE_INVALID_ARGUMENT;*v=c->visible;return GX3DE_OK;}
gx3de_result gx3de_group_create(gx3de_scene* s,gx3de_group** out) {if(!s||!out)return GX3DE_INVALID_ARGUMENT;auto node=new(std::nothrow) gx3de_object{s,nullptr,identity()};if(!node)return GX3DE_OUT_OF_MEMORY;gx3de_object* retained=nullptr;auto r=retain(s->objects,node,&retained);if(r!=GX3DE_OK)return r;
    auto group=new(std::nothrow) gx3de_group{s,node};r=retain(s->groups,group,out);if(r!=GX3DE_OK)gx3de_object_destroy(node);return r;}
gx3de_result gx3de_group_destroy(gx3de_group* g) {if(!g)return GX3DE_INVALID_ARGUMENT;erase_ptr(g->scene->groups,g);gx3de_object_destroy(g->node);delete g;return GX3DE_OK;}
gx3de_result gx3de_group_add(gx3de_group* g,gx3de_object* o) {if(!g||!o)return GX3DE_INVALID_ARGUMENT;if(g->scene!=o->scene)return GX3DE_WRONG_OWNER;if(o==g->node)return GX3DE_INVALID_ARGUMENT;for(auto p=g->node;p;p=p->parent)if(p==o)return GX3DE_INVALID_ARGUMENT;
    gx3de_mat4 inverse;if(!inverse_affine(world(g->node),inverse))return GX3DE_DEGENERATE;auto pose=world(o);o->parent=g->node;o->transform=product(inverse,pose);return GX3DE_OK;}
gx3de_result gx3de_group_remove(gx3de_group* g,gx3de_object* o) {if(!g||!o)return GX3DE_INVALID_ARGUMENT;if(g->scene!=o->scene)return GX3DE_WRONG_OWNER;if(o->parent!=g->node)return GX3DE_NOT_FOUND;o->transform=world(o);o->parent=nullptr;return GX3DE_OK;}
gx3de_result gx3de_group_set_transform(gx3de_group* g,const gx3de_mat4* m) {if(!g)return GX3DE_INVALID_ARGUMENT;return gx3de_object_set_transform(g->node,m);}
gx3de_result gx3de_group_get_transform(gx3de_group* g,gx3de_mat4* m) {if(!g)return GX3DE_INVALID_ARGUMENT;return gx3de_object_get_transform(g->node,m);}
gx3de_result gx3de_group_translate(gx3de_group* g,gx3de_vec3 delta,uint32_t world_space) {if(!g)return GX3DE_INVALID_ARGUMENT;return gx3de_object_translate(g->node,delta,world_space);}
gx3de_result gx3de_group_rotate(gx3de_group* g,gx3de_vec3 axis,double radians,gx3de_vec3 pivot,uint32_t world_space) {if(!g)return GX3DE_INVALID_ARGUMENT;return gx3de_object_rotate(g->node,axis,radians,pivot,world_space);}
gx3de_result gx3de_group_scale(gx3de_group* g,gx3de_vec3 factors,gx3de_vec3 pivot,uint32_t world_space) {if(!g)return GX3DE_INVALID_ARGUMENT;return gx3de_object_scale(g->node,factors,pivot,world_space);}
gx3de_result gx3de_group_bounds(gx3de_group* g,gx3de_bounds* out) {if(!g||!out)return GX3DE_INVALID_ARGUMENT;bool any=false;gx3de_bounds total{};for(auto o:g->scene->objects)if(o!=g->node){bool inside=false;for(auto p=o->parent;p;p=p->parent)if(p==g->node){inside=true;break;}if(!inside)continue;gx3de_bounds b;if(gx3de_object_bounds(o,1,&b)!=GX3DE_OK)continue;if(!any){total=b;any=true;}else{total.min={std::min(total.min.x,b.min.x),std::min(total.min.y,b.min.y),std::min(total.min.z,b.min.z)};total.max={std::max(total.max.x,b.max.x),std::max(total.max.y,b.max.y),std::max(total.max.z,b.max.z)};}}if(!any)return GX3DE_NOT_FOUND;*out=total;return GX3DE_OK;}
gx3de_result gx3de_object_create_mesh(gx3de_scene* s,const gx3de_vec3* vertices,uint64_t nv,const uint32_t* triangles,uint64_t nt,gx3de_object** out) {
    if(!s||!out||!vertices||!triangles||nv==0||nt==0)return GX3DE_INVALID_ARGUMENT;
    if(nv>UINT32_MAX||nt>SIZE_MAX/3||nv>SIZE_MAX/sizeof(gx3de_vec3))return GX3DE_RANGE;
    for(uint64_t i=0;i<nv;++i)if(!finite(vertices[i]))return GX3DE_INVALID_ARGUMENT;
    for(uint64_t i=0;i<nt*3;++i)if(triangles[i]>=nv)return GX3DE_RANGE;
    try {Mesh mesh;mesh.vertices.assign(vertices,vertices+nv);mesh.triangles.assign(triangles,triangles+nt*3);return retain_mesh(s,std::move(mesh),out); }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_import_mesh(gx3de_scene* s,const gx3de_mesh_import_spec* spec,gx3de_object** out) {
    if(!s||!spec||!out||spec->struct_size<sizeof(gx3de_mesh_import_spec)||
       (spec->format!=GX3DE_IMPORT_OBJ&&spec->format!=GX3DE_IMPORT_STL)||
       !valid_utf8(spec->path_utf8,4096))return GX3DE_INVALID_ARGUMENT;
    try {Mesh imported;std::string source_hash,error;auto* engine=s->engine;
        auto preflight=gx3de_backend::mesh_source_preflight(spec->path_utf8,
            static_cast<gx3de_backend::MeshImportFormat>(spec->format),
            spec->max_source_bytes,spec->max_memory_bytes,true,error);
        if(preflight==gx3de_backend::MeshSourceStatus::NotFound)return GX3DE_NOT_FOUND;
        if(preflight==gx3de_backend::MeshSourceStatus::Range)return GX3DE_RANGE;
        if(preflight!=gx3de_backend::MeshSourceStatus::Ok)return GX3DE_DEGENERATE;
        const bool disk=!engine->disk_cache_root.empty();
        gx3de_backend::MeshDiskCacheKey key;
        uint64_t source_bytes=0;
        if(disk){std::error_code ec;auto path=std::filesystem::u8path(spec->path_utf8);
            if(!std::filesystem::is_regular_file(path,ec)||ec)return GX3DE_NOT_FOUND;
            source_bytes=std::filesystem::file_size(path,ec);uint64_t limit=spec->max_source_bytes?spec->max_source_bytes:256ull*1024*1024;
            if(ec||source_bytes==0||source_bytes>limit)return GX3DE_RANGE;
            source_hash=sha256_source_file(path);if(source_hash.empty())return GX3DE_DEGENERATE;
            key={engine->cache_namespace,source_hash,spec->format,std::string("gx3de-mesh-import-v1|vtk-")+vtkVersion::GetVTKVersion()};
            auto state=gx3de_backend::mesh_disk_cache_load(engine->disk_cache_root.c_str(),key,imported,error);
            if(state==gx3de_backend::MeshDiskCacheLoad::Hit){
                auto after=sha256_source_file(path);auto final_bytes=std::filesystem::file_size(path,ec);
                if(ec||after!=source_hash||final_bytes!=source_bytes)return GX3DE_DEGENERATE;
                ++engine->disk_hits;auto r=retain_mesh(s,std::move(imported),out);
                if(r==GX3DE_OK)(*out)->source_sha256=source_hash;return r;
            }
            if(state==gx3de_backend::MeshDiskCacheLoad::Unsafe||state==gx3de_backend::MeshDiskCacheLoad::IoError)return GX3DE_DEGENERATE;
            if(state==gx3de_backend::MeshDiskCacheLoad::Invalid)++engine->disk_invalid;else ++engine->disk_misses;
        }
        if(!gx3de_backend::import_mesh_file(spec->path_utf8,static_cast<gx3de_backend::MeshImportFormat>(spec->format),spec->max_source_bytes,spec->max_memory_bytes,imported,source_hash,error))return GX3DE_DEGENERATE;
        if(disk){if(source_hash!=key.source_sha256_hex)return GX3DE_DEGENERATE;
            if(!gx3de_backend::mesh_disk_cache_store(engine->disk_cache_root.c_str(),key,imported,error))++engine->disk_store_failures;}
        auto r=retain_mesh(s,std::move(imported),out);if(r==GX3DE_OK)(*out)->source_sha256=std::move(source_hash);return r;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_object_import_mesh_preview(gx3de_scene* scene,const gx3de_mesh_import_spec* spec,gx3de_object** out){
    if(!scene||!spec||!out||spec->struct_size<sizeof(gx3de_mesh_import_spec)||
       (spec->format!=GX3DE_IMPORT_OBJ&&spec->format!=GX3DE_IMPORT_STL)||
       !valid_utf8(spec->path_utf8,4096))return GX3DE_INVALID_ARGUMENT;
    try{
        std::string hash,error;
        auto preflight=gx3de_backend::mesh_source_preflight(spec->path_utf8,
            static_cast<gx3de_backend::MeshImportFormat>(spec->format),
            spec->max_source_bytes,spec->max_memory_bytes,false,error);
        if(preflight==gx3de_backend::MeshSourceStatus::NotFound)return GX3DE_NOT_FOUND;
        if(preflight==gx3de_backend::MeshSourceStatus::Range)return GX3DE_RANGE;
        if(preflight!=gx3de_backend::MeshSourceStatus::Ok)return GX3DE_DEGENERATE;
        Mesh preview;
        auto status=gx3de_backend::preview_mesh_file(spec->path_utf8,
            static_cast<gx3de_backend::MeshImportFormat>(spec->format),
            spec->max_source_bytes,spec->max_memory_bytes,preview,hash,error);
        if(status==gx3de_backend::MeshPreviewStatus::Unsupported)return GX3DE_UNSUPPORTED;
        if(status!=gx3de_backend::MeshPreviewStatus::Success)return GX3DE_DEGENERATE;
        auto result=retain_mesh(scene,std::move(preview),out);
        if(result==GX3DE_OK)(*out)->source_sha256=std::move(hash);
        return result;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_lod(gx3de_object* source,gx3de_mesh_lod_level level,gx3de_object** out) {
    if(!source||!out||level<GX3DE_LOD_PREVIEW||level>GX3DE_LOD_FULL)
        return GX3DE_INVALID_ARGUMENT;
    if(!source->mesh)return GX3DE_UNSUPPORTED;
    if(level==GX3DE_LOD_FULL)return gx3de_object_duplicate(source,out);
    try {
        Mesh derived;std::string error;auto* engine=source->scene->engine;
        const bool disk=!engine->disk_cache_root.empty();
        gx3de_backend::MeshDiskCacheKey key{};
        bool hit=false;
        if(disk){
            key={engine->cache_namespace,source->fingerprint,3,
                std::string("gx3de-mesh-lod-v1|level-")+std::to_string(uint32_t(level))+"|vtk-"+vtkVersion::GetVTKVersion()};
            auto state=gx3de_backend::mesh_disk_cache_load(engine->disk_cache_root.c_str(),key,derived,error);
            if(state==gx3de_backend::MeshDiskCacheLoad::Hit){++engine->disk_hits;hit=true;}
            else if(state==gx3de_backend::MeshDiskCacheLoad::Invalid)++engine->disk_invalid;
            else if(state==gx3de_backend::MeshDiskCacheLoad::Miss)++engine->disk_misses;
            else return GX3DE_DEGENERATE;
        }
        if(!hit){
            if(!gx3de_backend::mesh_lod(*source->mesh,uint32_t(level),derived,error))return GX3DE_DEGENERATE;
            if(disk&&!gx3de_backend::mesh_disk_cache_store(engine->disk_cache_root.c_str(),key,derived,error))
                ++engine->disk_store_failures;
        }
        auto result=retain_mesh(source->scene,std::move(derived),out);
        if(result==GX3DE_OK){
            (*out)->transform=world(source);
            (*out)->source_sha256=source->source_sha256;
            (*out)->visible=source->visible;
            (*out)->opacity=source->opacity;
            (*out)->style=source->style;
        }
        return result;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_repeats_discover(gx3de_object* source,uint64_t selected,gx3de_repeat_result** out) {
    if(!source||!out)return GX3DE_INVALID_ARGUMENT;
    if(!source->mesh)return GX3DE_UNSUPPORTED;
    if(selected>=source->mesh->triangles.size()/3)return GX3DE_RANGE;
    try {
        gx3de_backend::RepeatResult data;std::string error;
        auto* engine=source->scene->engine;
        auto operation=repeat_fingerprint(source->fingerprint,selected);
        if(operation.empty())return GX3DE_DEGENERATE;
        bool hit=false;
        const bool disk=!engine->disk_cache_root.empty();
        if(disk){
            auto state=gx3de_backend::repeat_disk_cache_load(engine->disk_cache_root.c_str(),
                engine->cache_namespace,operation,source->fingerprint,selected,data,error);
            if(state==gx3de_backend::MeshDiskCacheLoad::Hit){++engine->repeat_disk_hits;hit=true;}
            else if(state==gx3de_backend::MeshDiskCacheLoad::Invalid)++engine->repeat_disk_invalid;
            else if(state==gx3de_backend::MeshDiskCacheLoad::Miss)++engine->repeat_disk_misses;
            else return GX3DE_DEGENERATE;
        }
        if(!hit){
            if(!gx3de_backend::discover_repeats(*source->mesh,selected,data,error))
                return GX3DE_DEGENERATE;
            if(disk&&!gx3de_backend::repeat_disk_cache_store(engine->disk_cache_root.c_str(),
               engine->cache_namespace,operation,source->fingerprint,data,error))
                ++engine->repeat_disk_store_failures;
        }
        auto result=new gx3de_repeat_result{source->scene,std::move(data),world(source),
            source->source_sha256,std::move(operation),
            source->visible,source->opacity,source,false};
        if(result->fingerprint.empty()){delete result;return GX3DE_DEGENERATE;}
        return retain(source->scene->repeats,result,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_repeats_info(gx3de_repeat_result* result,gx3de_repeat_info* out) {
    if(!result||!out||out->struct_size<sizeof(gx3de_repeat_info))return GX3DE_INVALID_ARGUMENT;
    gx3de_repeat_info info{};info.struct_size=sizeof(info);
    info.source_triangle=result->data.source_triangle;
    info.triangles_per_component=result->data.source_triangles;
    info.match_count=result->data.matches.size();
    info.remainder_triangles=result->data.remainder.triangles.size()/3;
    info.tolerance=result->data.tolerance;
    std::memcpy(info.fingerprint_sha256,result->fingerprint.c_str(),65);
    *out=info;return GX3DE_OK;
}
gx3de_result gx3de_mesh_repeats_placement(gx3de_repeat_result* result,uint64_t index,gx3de_mat4* out) {
    if(!result||!out)return GX3DE_INVALID_ARGUMENT;
    if(index>=result->data.matches.size())return GX3DE_RANGE;
    const auto& match=result->data.matches[size_t(index)];
    auto placement=identity();
    for(int row=0;row<3;++row)for(int column=0;column<3;++column)
        placement.m[column*4+row]=match.rotation[row][column];
    for(int axis=0;axis<3;++axis)placement.m[12+axis]=match.center[axis];
    *out=product(result->source_world,placement);return GX3DE_OK;
}
gx3de_result gx3de_mesh_repeats_prototype(gx3de_repeat_result* result,gx3de_object** out) {
    if(!result||!out)return GX3DE_INVALID_ARGUMENT;
    try {
        Mesh copy=result->data.prototype;
        auto status=retain_mesh(result->scene,std::move(copy),out);
        if(status==GX3DE_OK){(*out)->source_sha256=result->source_sha256;
            (*out)->visible=result->visible;(*out)->opacity=result->opacity;}
        return status;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_repeats_remainder(gx3de_repeat_result* result,gx3de_object** out) {
    if(!result||!out)return GX3DE_INVALID_ARGUMENT;
    if(result->data.remainder.triangles.empty())return GX3DE_NOT_FOUND;
    try {
        Mesh copy=result->data.remainder;
        auto status=retain_mesh(result->scene,std::move(copy),out);
        if(status==GX3DE_OK){(*out)->transform=result->source_world;
            (*out)->source_sha256=result->source_sha256;
            (*out)->visible=result->visible;(*out)->opacity=result->opacity;}
        return status;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_repeats_presentation_set(gx3de_repeat_result* result,uint32_t enabled) {
    if(!result||enabled>1)return GX3DE_INVALID_ARGUMENT;
    if(enabled&&!result->source)return GX3DE_NOT_FOUND;
    result->presentation_enabled=enabled!=0;return GX3DE_OK;
}
gx3de_result gx3de_mesh_repeats_presentation_get(gx3de_repeat_result* result,uint32_t* enabled) {
    if(!result||!enabled)return GX3DE_INVALID_ARGUMENT;
    *enabled=result->presentation_enabled;return GX3DE_OK;
}
gx3de_result gx3de_mesh_repeats_destroy(gx3de_repeat_result* result) {
    if(!result)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(result->scene->repeats,result);delete result;return GX3DE_OK;
}
gx3de_result gx3de_object_source_sha256(gx3de_object* o,char out[65]) {
    if(!o||!out)return GX3DE_INVALID_ARGUMENT;if(o->source_sha256.empty())return GX3DE_NOT_FOUND;
    std::memcpy(out,o->source_sha256.c_str(),65);return GX3DE_OK;
}
static uint64_t scientific_numeric_array_count(vtkFieldData* fields) {
    uint64_t count=0;
    for(int i=0;i<fields->GetNumberOfArrays();++i)if(fields->GetArray(i))++count;
    return count;
}
static vtkDataArray* scientific_array_by_index(const gx3de_backend::ScientificData& data,
                                                uint64_t index,uint32_t* association=nullptr) {
    auto* points=data.dataset->GetPointData();auto* cells=data.dataset->GetCellData();
    const auto point_count=scientific_numeric_array_count(points);
    if(index<point_count){if(association)*association=GX3DE_SCI_ASSOC_POINT;
        return gx3de_backend::scientific_array_at(data,GX3DE_SCI_ASSOC_POINT,index);}
    index-=point_count;
    if(index>=scientific_numeric_array_count(cells))return nullptr;
    if(association)*association=GX3DE_SCI_ASSOC_CELL;
    return gx3de_backend::scientific_array_at(data,GX3DE_SCI_ASSOC_CELL,index);
}
static uint32_t navcube_synced(const gx3de_view* view);
#include "native_3d_planar_texture_impl.inc"
#include "native_3d_curved_texture_impl.inc"
#include "native_3d_shadow_impl.inc"
static void figure_rect(const gx3de_view*,double&,double&,double&,double&,uint32_t);
static double scientific_style(const gx3de_view*,const char*,double);
// VTK 9.3 measures a picker's fractional tolerance at the near/far ray
// midpoint. Express the radius in focal-plane viewport pixels instead, so a
// distant clipping plane cannot turn an isolated handle into another axis.
static double viewport_pick_tolerance(const gx3de_viewport* vp,double pixels) {
    const auto& camera=vp->view->camera;
    double tolerance=pixels/std::hypot(double(vp->width),double(vp->height));
    if(!camera.orthographic){
        const double midpoint=camera.near_clip*.5+camera.far_clip*.5;
        tolerance*=length(sub(camera.position,camera.target))/midpoint;
    }
    return tolerance;
}
#include "native_3d_renderer_impl.inc"
#include "native_3d_backend_impl.inc"
#include "native_3d_gizmo_impl.inc"
#include "native_3d_plane_manip_impl.inc"
static uint32_t scientific_cell_type(int vtk_type) {
    switch(vtk_type){
    case VTK_VERTEX:return GX3DE_SCI_CELL_VERTEX;
    case VTK_LINE:return GX3DE_SCI_CELL_LINE;
    case VTK_POLY_LINE:return GX3DE_SCI_CELL_POLYLINE;
    case VTK_TRIANGLE:return GX3DE_SCI_CELL_TRIANGLE;
    case VTK_POLYGON:return GX3DE_SCI_CELL_POLYGON;
    case VTK_TETRA:return GX3DE_SCI_CELL_TETRA;
    case VTK_HEXAHEDRON:return GX3DE_SCI_CELL_HEXAHEDRON;
    default:return GX3DE_SCI_CELL_OTHER;
    }
}
gx3de_result gx3de_scientific_import(gx3de_scene* scene,const gx3de_scientific_import_spec* spec,gx3de_object** out) {
    if(!scene||!spec||!out||spec->struct_size<sizeof(*spec)||
       (spec->format!=GX3DE_SCIENTIFIC_VTP&&spec->format!=GX3DE_SCIENTIFIC_VTU&&
        spec->format!=GX3DE_SCIENTIFIC_VTI)||!valid_utf8(spec->path_utf8,4096))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    try {
        std::error_code ec;const auto path=std::filesystem::u8path(spec->path_utf8);
        if(!std::filesystem::is_regular_file(path,ec)||ec)return GX3DE_NOT_FOUND;
        const auto bytes=std::filesystem::file_size(path,ec);
        const uint64_t limit=spec->max_source_bytes?spec->max_source_bytes:256ull*1024*1024;
        if(ec||bytes==0||bytes>limit)return GX3DE_RANGE;
        gx3de_backend::ScientificData imported;std::string error;
        if(!gx3de_backend::import_scientific_file(spec->path_utf8,
            static_cast<gx3de_backend::ScientificFormat>(spec->format),
            spec->max_source_bytes,imported,error))
            return error=="scientific XML exceeds 256 MiB decoded-data budget"?
                GX3DE_RANGE:GX3DE_DEGENERATE;
        return retain_scientific(scene,std::move(imported),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
     catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_scientific_create_polydata(gx3de_scene* scene,const gx3de_scientific_polydata_spec* spec,gx3de_object** out) {
    if(!scene||!spec||!out||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    try {gx3de_backend::ScientificData data;std::string error;
        if(!gx3de_backend::create_scientific_polydata(*spec,data,error))return GX3DE_INVALID_ARGUMENT;
        return retain_scientific(scene,std::move(data),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_scientific_triangle_mesh_create(gx3de_object* source,uint64_t max_triangles,uint64_t max_bytes,gx3de_object** out) {
    if(!source||!out||!max_triangles||!max_bytes)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;if(!source->scientific)return GX3DE_UNSUPPORTED;
    auto* poly=vtkPolyData::SafeDownCast(source->scientific->dataset);
    if(!poly||poly->GetNumberOfVerts()||poly->GetNumberOfLines())return GX3DE_UNSUPPORTED;
    if(poly->GetNumberOfPoints()<3||poly->GetNumberOfPolys()+poly->GetNumberOfStrips()==0)return GX3DE_DEGENERATE;
    try {
        auto placement=world(source);for(double value:placement.m)if(!std::isfinite(value))return GX3DE_RANGE;
        auto source_hash=source->scientific->source_sha256_hex;
        vtkNew<vtkTriangleFilter> triangulate;triangulate->SetInputData(poly);
        triangulate->PassLinesOff();triangulate->PassVertsOff();triangulate->Update();
        auto* triangles=triangulate->GetOutput();auto nv=triangles->GetNumberOfPoints(),nf=triangles->GetNumberOfPolys();
        if(nv<3||nf<1)return GX3DE_DEGENERATE;
        if(uint64_t(nv)>UINT32_MAX||uint64_t(nf)>max_triangles||uint64_t(nf)>SIZE_MAX/(3*sizeof(uint32_t)))return GX3DE_RANGE;
        const uint64_t vertex_bytes=uint64_t(nv)*sizeof(gx3de_vec3),face_bytes=uint64_t(nf)*3*sizeof(uint32_t);
        if(vertex_bytes>max_bytes||face_bytes>max_bytes-vertex_bytes)return GX3DE_RANGE;
        Mesh mesh;mesh.vertices.reserve(size_t(nv));mesh.triangles.reserve(size_t(nf)*3);
        for(vtkIdType i=0;i<nv;++i){double p[3];triangles->GetPoint(i,p);gx3de_vec3 v{p[0],p[1],p[2]};if(!finite(v))return GX3DE_DEGENERATE;mesh.vertices.push_back(v);}
        vtkIdType n=0;const vtkIdType* ids=nullptr;auto* cells=triangles->GetPolys();cells->InitTraversal();
        while(cells->GetNextCell(n,ids)){
            if(n!=3)return GX3DE_DEGENERATE;
            for(int k=0;k<3;++k){if(ids[k]<0||ids[k]>=nv)return GX3DE_DEGENERATE;mesh.triangles.push_back(uint32_t(ids[k]));}
        }
        if(mesh.triangles.size()!=uint64_t(nf)*3)return GX3DE_DEGENERATE;
        for(size_t i=0;i<mesh.triangles.size();i+=3){
            auto a=mesh.vertices[mesh.triangles[i]],b=mesh.vertices[mesh.triangles[i+1]],c=mesh.vertices[mesh.triangles[i+2]];
            const double twice_area=length(cross(sub(b,a),sub(c,a)));
            if(!std::isfinite(twice_area))return GX3DE_RANGE;
            if(twice_area==0)return GX3DE_DEGENERATE;
        }
        auto result=retain_mesh(source->scene,std::move(mesh),out);
        if(result==GX3DE_OK){(*out)->transform=placement;(*out)->source_sha256=std::move(source_hash);}
        return result;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
     catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_scientific_create_image(gx3de_scene* scene,const gx3de_scientific_image_spec* spec,gx3de_object** out) {
    if(!scene||!spec||!out||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    try {gx3de_backend::ScientificData data;std::string error;
        if(!gx3de_backend::create_scientific_image(*spec,data,error))return GX3DE_INVALID_ARGUMENT;
        return retain_scientific(scene,std::move(data),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_scientific_create_unstructured(gx3de_scene* scene,const gx3de_scientific_unstructured_spec* spec,gx3de_object** out) {
    if(!scene||!spec||!out||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    try {gx3de_backend::ScientificData data;std::string error;
        if(!gx3de_backend::create_scientific_unstructured(*spec,data,error))return GX3DE_INVALID_ARGUMENT;
        return retain_scientific(scene,std::move(data),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_scientific_info_get(gx3de_object* object,gx3de_scientific_info* out) {
    if(!object||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto& data=*object->scientific;
    gx3de_scientific_info result{};result.struct_size=sizeof(result);
    result.kind=static_cast<uint32_t>(data.format);
    result.point_count=static_cast<uint64_t>(data.dataset->GetNumberOfPoints());
    result.cell_count=static_cast<uint64_t>(data.dataset->GetNumberOfCells());
    result.array_count=scientific_numeric_array_count(data.dataset->GetPointData())+
                       scientific_numeric_array_count(data.dataset->GetCellData());
    result.derived=data.derived?1u:0u;result.isovalue=data.isovalue;
    if(data.selected_scalar.size()>=sizeof(result.selected_scalar_utf8))return GX3DE_RANGE;
    std::memcpy(result.selected_scalar_utf8,data.selected_scalar.c_str(),data.selected_scalar.size()+1);
    if(auto* grid=vtkImageData::SafeDownCast(data.dataset)){
        int dimensions[3];grid->GetDimensions(dimensions);
        for(int i=0;i<3;++i)result.grid_dimensions[i]=static_cast<uint32_t>(dimensions[i]);
    }
    *out=result;return GX3DE_OK;
}
gx3de_result gx3de_scientific_grid_info_get(gx3de_object* object,gx3de_scientific_grid_info* out) {
    if(!object||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto* grid=vtkImageData::SafeDownCast(object->scientific->dataset);
    if(!grid)return GX3DE_UNSUPPORTED;
    gx3de_scientific_grid_info result{};result.struct_size=sizeof(result);
    const int* extent=grid->GetExtent();const double* origin=grid->GetOrigin();const double* spacing=grid->GetSpacing();
    for(int i=0;i<6;++i)result.extent[i]=extent[i];
    result.origin={origin[0],origin[1],origin[2]};result.spacing={spacing[0],spacing[1],spacing[2]};
    auto* direction=grid->GetDirectionMatrix();
    for(int row=0;row<3;++row)for(int col=0;col<3;++col)
        result.direction[row*3+col]=direction->GetElement(row,col);
    *out=result;return GX3DE_OK;
}
gx3de_result gx3de_scientific_point(gx3de_object* object,uint64_t index,uint32_t world_space,gx3de_vec3* out) {
    if(!object||!out||world_space>1)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto* data=object->scientific->dataset.GetPointer();
    if(index>=static_cast<uint64_t>(data->GetNumberOfPoints()))return GX3DE_RANGE;
    double p[3];data->GetPoint(static_cast<vtkIdType>(index),p);
    gx3de_vec3 value{p[0],p[1],p[2]};*out=world_space?apply(world(object),value):value;
    return GX3DE_OK;
}
gx3de_result gx3de_scientific_cell_info_get(gx3de_object* object,uint64_t index,gx3de_scientific_cell_info* out) {
    if(!object||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto* data=object->scientific->dataset.GetPointer();
    if(index>=static_cast<uint64_t>(data->GetNumberOfCells()))return GX3DE_RANGE;
    auto* cell=data->GetCell(static_cast<vtkIdType>(index));if(!cell)return GX3DE_DEGENERATE;
    *out={sizeof(*out),scientific_cell_type(cell->GetCellType()),
          static_cast<uint64_t>(cell->GetNumberOfPoints()),{}};
    return GX3DE_OK;
}
gx3de_result gx3de_scientific_cell_point_id(gx3de_object* object,uint64_t cell_index,uint64_t position,uint64_t* point_id) {
    if(!object||!point_id)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto* data=object->scientific->dataset.GetPointer();
    if(cell_index>=static_cast<uint64_t>(data->GetNumberOfCells()))return GX3DE_RANGE;
    auto* cell=data->GetCell(static_cast<vtkIdType>(cell_index));if(!cell)return GX3DE_DEGENERATE;
    if(position>=static_cast<uint64_t>(cell->GetNumberOfPoints()))return GX3DE_RANGE;
    *point_id=static_cast<uint64_t>(cell->GetPointId(static_cast<vtkIdType>(position)));
    return GX3DE_OK;
}
gx3de_result gx3de_scientific_array_info_get(gx3de_object* object,uint64_t index,gx3de_scientific_array_info* out) {
    if(!object||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    uint32_t association=0;auto* array=scientific_array_by_index(*object->scientific,index,&association);
    if(!array)return GX3DE_RANGE;
    gx3de_scientific_array_info result{};result.struct_size=sizeof(result);
    result.association=association;result.components=static_cast<uint32_t>(array->GetNumberOfComponents());
    result.classification=result.components==1?GX3DE_SCI_ARRAY_SCALAR:
                          result.components==3?GX3DE_SCI_ARRAY_VECTOR3:GX3DE_SCI_ARRAY_OTHER;
    result.tuple_count=static_cast<uint64_t>(array->GetNumberOfTuples());
    const char* name=array->GetName();if(name){const size_t length=std::strlen(name);
        if(length>=sizeof(result.name_utf8))return GX3DE_RANGE;
        std::memcpy(result.name_utf8,name,length+1);}
    *out=result;return GX3DE_OK;
}
gx3de_result gx3de_scientific_array_find(gx3de_object* object,uint32_t association,const char* name_utf8,uint64_t* index) {
    if(!object||!index||!valid_utf8(name_utf8)||
       (association!=GX3DE_SCI_ASSOC_POINT&&association!=GX3DE_SCI_ASSOC_CELL))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto* dataset=object->scientific->dataset.GetPointer();
    auto* attributes=association==GX3DE_SCI_ASSOC_POINT?static_cast<vtkFieldData*>(dataset->GetPointData()):
                       static_cast<vtkFieldData*>(dataset->GetCellData());
    const uint64_t offset=association==GX3DE_SCI_ASSOC_CELL?
        scientific_numeric_array_count(dataset->GetPointData()):0;
    uint64_t ordinal=0;
    for(int i=0;i<attributes->GetNumberOfArrays();++i){auto* array=attributes->GetArray(i);
        if(!array)continue;
        if(array&&array->GetName()&&std::strcmp(array->GetName(),name_utf8)==0){
            *index=offset+ordinal;return GX3DE_OK;}
        ++ordinal;}
    return GX3DE_NOT_FOUND;
}
gx3de_result gx3de_scientific_array_values(gx3de_object* object,uint64_t index,uint64_t first_tuple,uint64_t tuple_count,
                                             double* out_values,uint64_t value_capacity,uint64_t* required_values) {
    if(!object||!required_values||(!out_values&&value_capacity))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    auto* array=scientific_array_by_index(*object->scientific,index);
    if(!array)return GX3DE_RANGE;
    const uint64_t total=static_cast<uint64_t>(array->GetNumberOfTuples());
    const uint64_t components=static_cast<uint64_t>(array->GetNumberOfComponents());
    if(first_tuple>total||tuple_count>total-first_tuple||tuple_count>UINT64_MAX/components)return GX3DE_RANGE;
    const uint64_t needed=tuple_count*components;*required_values=needed;
    if(value_capacity<needed)return GX3DE_RANGE;
    for(uint64_t i=0;i<tuple_count;++i)for(uint64_t c=0;c<components;++c)
        out_values[i*components+c]=array->GetComponent(static_cast<vtkIdType>(first_tuple+i),static_cast<int>(c));
    return GX3DE_OK;
}
gx3de_result gx3de_scientific_field_roles_set(gx3de_object* object,const gx3de_scientific_field_roles* roles) {
    if(!object||!roles||roles->struct_size<sizeof(*roles)||!std::isfinite(roles->tube_radius)||roles->tube_radius<0)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    const int64_t ids[3]={roles->scalar_array,roles->vector_array,roles->radius_array};
    for(int k=0;k<3;++k){if(ids[k]<-1)return GX3DE_INVALID_ARGUMENT;if(ids[k]<0)continue;
        uint32_t association=0;auto* array=scientific_array_by_index(*object->scientific,static_cast<uint64_t>(ids[k]),&association);
        if(!array||array->GetNumberOfComponents()!=(k==1?3:1)||
           (k>0&&association!=GX3DE_SCI_ASSOC_POINT))return GX3DE_INVALID_ARGUMENT;
        if(k==2)for(vtkIdType i=0;i<array->GetNumberOfTuples();++i)
            if(array->GetComponent(i,0)<0)return GX3DE_INVALID_ARGUMENT;
    }
    if(roles->tube_radius>0){bool has_line=false;auto* dataset=object->scientific->dataset.GetPointer();
        for(vtkIdType i=0;i<dataset->GetNumberOfCells();++i){const int type=dataset->GetCellType(i);
            if(type==VTK_LINE||type==VTK_POLY_LINE){has_line=true;break;}}
        if(!has_line)return GX3DE_INVALID_ARGUMENT;
    }
    object->field_roles=*roles;return GX3DE_OK;
}
gx3de_result gx3de_scientific_field_roles_get(gx3de_object* object,gx3de_scientific_field_roles* out) {
    if(!object||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;*out=object->field_roles;return GX3DE_OK;
}
gx3de_result gx3de_scientific_presentation_set(gx3de_object* object,const gx3de_scientific_presentation* spec) {
    if(!object||!spec||spec->struct_size<sizeof(*spec)||
       spec->colormap<GX3DE_COLORMAP_VIRIDIS||spec->colormap>GX3DE_COLORMAP_GRAYSCALE||
       spec->use_scalar_range>1||spec->sphere_glyphs>1||spec->show_vectors>1||
       spec->max_vector_glyphs>20000||
       (spec->use_scalar_range&&(!std::isfinite(spec->scalar_min)||!std::isfinite(spec->scalar_max)||
       spec->scalar_min>=spec->scalar_max)))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    object->presentation=*spec;object->presentation.struct_size=sizeof(*spec);return GX3DE_OK;
}
gx3de_result gx3de_scientific_presentation_get(gx3de_object* object,gx3de_scientific_presentation* out) {
    if(!object||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    *out=object->presentation;return GX3DE_OK;
}
gx3de_result gx3de_field_volume_style_set(gx3de_object* object,
                                            const gx3de_field_volume_style* style) {
    if(!object||!style||style->struct_size<sizeof(*style)||style->enabled>1)
        return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific||!vtkImageData::SafeDownCast(object->scientific->dataset))
        return GX3DE_UNSUPPORTED;
    gx3de_field_volume_style normalized{};normalized.struct_size=sizeof(normalized);
    normalized.enabled=style->enabled;
    if(style->enabled){
        if(!std::isfinite(style->sample_distance)||style->sample_distance<=0||
           style->transfer_count<2||style->transfer_count>GX3DE_MAX_FIELD_TRANSFER_POINTS)
            return GX3DE_INVALID_ARGUMENT;
        uint32_t association=0;
        auto* array=scientific_array_by_index(*object->scientific,style->scalar_array,&association);
        if(!array||association!=GX3DE_SCI_ASSOC_POINT||array->GetNumberOfComponents()!=1||
           array->GetNumberOfTuples()!=object->scientific->dataset->GetNumberOfPoints())
            return GX3DE_INVALID_ARGUMENT;
        if(object->scientific->dataset->GetNumberOfPoints()>4000000)
            return GX3DE_RANGE;
        double previous=-std::numeric_limits<double>::infinity();
        for(uint32_t i=0;i<style->transfer_count;++i){const auto& p=style->transfer[i];
            if(!std::isfinite(p.scalar)||p.scalar<=previous||
               !std::isfinite(p.red)||p.red<0||p.red>1||
               !std::isfinite(p.green)||p.green<0||p.green>1||
               !std::isfinite(p.blue)||p.blue<0||p.blue>1||
               !std::isfinite(p.opacity)||p.opacity<0||p.opacity>1)
                return GX3DE_INVALID_ARGUMENT;
            previous=p.scalar;normalized.transfer[i]=p;
        }
        normalized.scalar_array=style->scalar_array;
        normalized.sample_distance=style->sample_distance;
        normalized.transfer_count=style->transfer_count;
    }
    object->volume_style=normalized;
    return GX3DE_OK;
}
gx3de_result gx3de_field_volume_style_get(gx3de_object* object,
                                            gx3de_field_volume_style* style) {
    if(!object||!style||style->struct_size<sizeof(*style))return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific||!vtkImageData::SafeDownCast(object->scientific->dataset))
        return GX3DE_UNSUPPORTED;
    *style=object->volume_style;
    return GX3DE_OK;
}
gx3de_result gx3de_scientific_opacity_array_set(gx3de_object* object,int64_t index) {
    if(!object||index<-1)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    if(index>=0){uint32_t association=0;
        auto* array=scientific_array_by_index(*object->scientific,
                                              static_cast<uint64_t>(index),&association);
        if(!array||association!=GX3DE_SCI_ASSOC_POINT||array->GetNumberOfComponents()!=1)
            return GX3DE_INVALID_ARGUMENT;
        for(vtkIdType i=0;i<array->GetNumberOfTuples();++i){const double value=array->GetComponent(i,0);
            if(!std::isfinite(value)||value<0||value>1)return GX3DE_INVALID_ARGUMENT;}}
    object->opacity_array=index;return GX3DE_OK;
}
gx3de_result gx3de_scientific_opacity_array_get(gx3de_object* object,int64_t* index) {
    if(!object||!index)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    *index=object->opacity_array;return GX3DE_OK;
}
gx3de_result gx3de_scientific_color_array_set(gx3de_object* object,int64_t index) {
    if(!object||index<-1)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    if(index>=0){uint32_t association=0;
        auto* array=scientific_array_by_index(*object->scientific,
            static_cast<uint64_t>(index),&association);
        if(!array||(association!=GX3DE_SCI_ASSOC_POINT&&association!=GX3DE_SCI_ASSOC_CELL)||
           (array->GetNumberOfComponents()!=3&&array->GetNumberOfComponents()!=4)||
           array->GetNumberOfTuples()!=(association==GX3DE_SCI_ASSOC_POINT?object->scientific->dataset->GetNumberOfPoints():object->scientific->dataset->GetNumberOfCells()))
            return GX3DE_INVALID_ARGUMENT;
        for(vtkIdType i=0;i<array->GetNumberOfTuples();++i)
            for(int j=0;j<array->GetNumberOfComponents();++j){
                const double v=array->GetComponent(i,j);
                if(!std::isfinite(v)||v<0||v>1)return GX3DE_INVALID_ARGUMENT;}}
    object->color_array=index;return GX3DE_OK;
}
gx3de_result gx3de_scientific_color_array_get(gx3de_object* object,int64_t* index) {
    if(!object||!index)return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    *index=object->color_array;return GX3DE_OK;
}
gx3de_result gx3de_scientific_vector_samples(gx3de_object* object,uint64_t vector_array,
    uint64_t max_samples,uint32_t world_space,gx3de_scientific_vector_sample* samples,
    uint64_t capacity,uint64_t* required_samples) {
    if(!object||!required_samples||!max_samples||world_space>1||(!samples&&capacity))
        return GX3DE_INVALID_ARGUMENT;
    if(!object->scientific)return GX3DE_UNSUPPORTED;
    uint32_t association=0;
    auto* array=scientific_array_by_index(*object->scientific,vector_array,&association);
    if(!array)return GX3DE_RANGE;
    if(association!=GX3DE_SCI_ASSOC_POINT||array->GetNumberOfComponents()!=3)
        return GX3DE_INVALID_ARGUMENT;
    auto* dataset=object->scientific->dataset.GetPointer();
    const uint64_t points=static_cast<uint64_t>(dataset->GetNumberOfPoints());
    const uint64_t stride=points?1+(points-1)/max_samples:1;
    const uint64_t count=points?1+(points-1)/stride:0;
    *required_samples=count;
    if(capacity<count)return GX3DE_RANGE;
    if(!count)return GX3DE_OK;
    if(!samples)return GX3DE_INVALID_ARGUMENT;
    for(uint64_t i=0;i<count;++i)
        if(samples[i].struct_size<sizeof(gx3de_scientific_vector_sample))return GX3DE_INVALID_ARGUMENT;
    const auto matrix=world_space?world(object):identity();
    /* Validate every transformed tuple before publishing any output. */
    for(uint64_t i=0;i<count;++i){
        const vtkIdType id=static_cast<vtkIdType>(i*stride);
        double xyz[3]{};dataset->GetPoint(id,xyz);
        gx3de_vec3 point{xyz[0],xyz[1],xyz[2]};
        gx3de_vec3 vector{array->GetComponent(id,0),array->GetComponent(id,1),array->GetComponent(id,2)};
        point=apply(matrix,point);
        vector={matrix.m[0]*vector.x+matrix.m[4]*vector.y+matrix.m[8]*vector.z,
                matrix.m[1]*vector.x+matrix.m[5]*vector.y+matrix.m[9]*vector.z,
                matrix.m[2]*vector.x+matrix.m[6]*vector.y+matrix.m[10]*vector.z};
        if(!finite(point)||!finite(vector))return GX3DE_DEGENERATE;
    }
    for(uint64_t i=0;i<count;++i){
        const vtkIdType id=static_cast<vtkIdType>(i*stride);
        double xyz[3]{};dataset->GetPoint(id,xyz);
        gx3de_vec3 point{xyz[0],xyz[1],xyz[2]};
        gx3de_vec3 vector{array->GetComponent(id,0),array->GetComponent(id,1),array->GetComponent(id,2)};
        samples[i]={sizeof(gx3de_scientific_vector_sample),0,static_cast<uint64_t>(id),
                    apply(matrix,point),
                    {matrix.m[0]*vector.x+matrix.m[4]*vector.y+matrix.m[8]*vector.z,
                     matrix.m[1]*vector.x+matrix.m[5]*vector.y+matrix.m[9]*vector.z,
                     matrix.m[2]*vector.x+matrix.m[6]*vector.y+matrix.m[10]*vector.z},{}};
    }
    return GX3DE_OK;
}
gx3de_result gx3de_scientific_isosurfaces(gx3de_object* grid,const char* scalar_name_utf8,const double* values,uint32_t count,gx3de_object** out_objects) {
    if(!grid||!out_objects||!values||count<1||count>32||!valid_utf8(scalar_name_utf8))return GX3DE_INVALID_ARGUMENT;
    for(uint32_t i=0;i<count;++i)if(!std::isfinite(values[i]))return GX3DE_INVALID_ARGUMENT;
    if(!grid->scientific||(grid->scientific->format!=gx3de_backend::ScientificFormat::Vti&&
        grid->scientific->format!=gx3de_backend::ScientificFormat::InMemoryImage))return GX3DE_UNSUPPORTED;
    auto* scalar=gx3de_backend::scientific_array(*grid->scientific,GX3DE_SCI_ASSOC_POINT,scalar_name_utf8);
    if(!scalar)return GX3DE_NOT_FOUND;
    if(scalar->GetNumberOfComponents()!=1)return GX3DE_INVALID_ARGUMENT;
    try {std::vector<gx3de_backend::ScientificData> derived;derived.reserve(count);
        auto* engine=grid->scene->engine;
        for(uint32_t i=0;i<count;++i){
            gx3de_backend::ScientificData surface;
            std::string error;
            bool cached=false;
            gx3de_backend::ScientificDiskCacheKey key;
            if(!engine->scientific_disk_root.empty()){
                key={engine->cache_namespace,gx3de_backend::scientific_contour_fingerprint(
                    *grid->scientific,scalar_name_utf8,values[i])};
                std::string xml;
                auto state=gx3de_backend::scientific_disk_cache_load(
                    engine->scientific_disk_root.c_str(),key,xml,error);
                if(state==gx3de_backend::MeshDiskCacheLoad::Hit){
                    if(gx3de_backend::scientific_surface_from_xml(xml,*grid->scientific,
                        scalar_name_utf8,values[i],surface,error)){
                        ++engine->scientific_disk_hits;cached=true;
                    }else ++engine->scientific_disk_invalid;
                }else if(state==gx3de_backend::MeshDiskCacheLoad::Miss)
                    ++engine->scientific_disk_misses;
                else if(state==gx3de_backend::MeshDiskCacheLoad::Invalid)
                    ++engine->scientific_disk_invalid;
                else return GX3DE_DEGENERATE;
            }
            if(!cached){
                std::vector<gx3de_backend::ScientificData> one;
                if(!gx3de_backend::contour_isovalues(*grid->scientific,scalar_name_utf8,
                    {values[i]},one,error)||one.size()!=1)return GX3DE_DEGENERATE;
                surface=std::move(one[0]);
                if(!engine->scientific_disk_root.empty()&&surface.dataset->GetNumberOfCells()){
                    std::string xml;
                    if(!gx3de_backend::scientific_surface_to_xml(surface,xml,error)||
                       !gx3de_backend::scientific_disk_cache_store(
                           engine->scientific_disk_root.c_str(),key,xml,error))
                        ++engine->scientific_disk_store_failures;
                }
            }
            derived.push_back(std::move(surface));
        }
        std::vector<gx3de_object*> created(count,nullptr);
        for(uint32_t i=0;i<count;++i){if(derived[i].dataset->GetNumberOfCells()==0)continue;
            auto result=retain_scientific(grid->scene,std::move(derived[i]),&created[i]);
            if(result!=GX3DE_OK){for(auto* object:created)if(object)gx3de_object_destroy(object);
                return result;}
            created[i]->transform=world(grid);
        }
        for(uint32_t i=0;i<count;++i)out_objects[i]=created[i];
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_job_prepare_mesh_import(gx3de_scene* scene,const gx3de_mesh_import_spec* spec,gx3de_job** out) {
    if(!scene||!spec||!out||spec->struct_size<sizeof(gx3de_mesh_import_spec)||
       (spec->format!=GX3DE_IMPORT_OBJ&&spec->format!=GX3DE_IMPORT_STL)||!valid_utf8(spec->path_utf8,4096))return GX3DE_INVALID_ARGUMENT;
    try {auto job=new gx3de_job{};job->engine=scene->engine;job->scene=scene;job->path=spec->path_utf8;job->format=spec->format;job->max_source_bytes=spec->max_source_bytes;job->max_memory_bytes=spec->max_memory_bytes;
        job_event_locked(job,GX3DE_JOB_READY,0);return retain(scene->engine->jobs,job,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_job_prepare_mesh_lod(gx3de_object* source,gx3de_mesh_lod_level level,gx3de_job** out) {
    if(!source||!out||level<GX3DE_LOD_PREVIEW||level>GX3DE_LOD_FULL)return GX3DE_INVALID_ARGUMENT;
    if(!source->mesh)return GX3DE_UNSUPPORTED;
    try {
        auto job=new gx3de_job{};job->engine=source->scene->engine;job->scene=source->scene;job->kind=2;job->lod_level=uint32_t(level);
        job->source_mesh=source->mesh;job->source_hash=source->source_sha256;
        job->source_transform=world(source);job->source_visible=source->visible;job->source_opacity=source->opacity;job->source_style=source->style;
        job_event_locked(job,GX3DE_JOB_READY,0);
        return retain(source->scene->engine->jobs,job,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_job_prepare_step_import(gx3de_engine* engine,const gx3de_step_import_spec* spec,gx3de_job** out) {
    if(!engine||!spec||!out||spec->struct_size<sizeof(gx3de_step_import_spec)||!valid_utf8(spec->path_utf8,4096))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    try {std::unique_ptr<gx3de_job> job(new gx3de_job{});job->engine=engine;job->kind=3;job->path=spec->path_utf8;
        job->max_source_bytes=spec->max_source_bytes;job->max_nodes=spec->max_nodes;
        job_event_locked(job.get(),GX3DE_JOB_READY,0);return retain(engine->jobs,job.release(),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_job_prepare_brep_mesh(gx3de_object* source,
    const gx3de_brep_mesh_spec* spec,gx3de_job** out) {
    if(!source||!spec||!out||spec->struct_size<sizeof(gx3de_brep_mesh_spec)||
       !std::isfinite(spec->linear_deflection)||spec->linear_deflection<=0||
       !std::isfinite(spec->angular_deflection)||spec->angular_deflection<=0||
       spec->angular_deflection>3.141592653589793||
       !std::isfinite(spec->weld_tolerance)||spec->weld_tolerance<0||
       !spec->max_triangles||!spec->max_output_bytes)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!source->brep)return GX3DE_UNSUPPORTED;
    try {
        std::string fingerprint,error;
        if(!gx3de_backend::shape_fingerprint(*source->brep,
            source->scene->engine->cache_namespace,fingerprint,error))
            return error.find("256 MiB")!=std::string::npos?GX3DE_RANGE:GX3DE_DEGENERATE;
        std::unique_ptr<gx3de_job> job(new gx3de_job{});
        job->engine=source->scene->engine;job->scene=source->scene;job->kind=4;
        job->brep_source=source->brep;job->brep_mesh_spec=*spec;
        job->derivation_fingerprint=std::move(fingerprint);
        job->source_hash=source->source_sha256;
        job->source_transform=world(source);job->source_visible=source->visible;
        job->source_opacity=source->opacity;job->source_style=source->style;
        job_event_locked(job.get(),GX3DE_JOB_READY,0);
        return retain(source->scene->engine->jobs,job.release(),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_job_start(gx3de_job* job) {
    if(!job)return GX3DE_INVALID_ARGUMENT;
    {std::lock_guard<std::mutex> lock(job->mutex);if(job->state!=GX3DE_JOB_READY)return GX3DE_INVALID_ARGUMENT;job_event_locked(job,GX3DE_JOB_RUNNING,0);}
    try {job->worker=std::thread([job]{Mesh imported;std::string hash,error;bool ok=false;
            try {
                if(job->kind==1)
                    ok=gx3de_backend::import_mesh_file(job->path.c_str(),static_cast<gx3de_backend::MeshImportFormat>(job->format),job->max_source_bytes,job->max_memory_bytes,imported,hash,error,import_cancelled,job,import_progress,job);
                else if(job->kind==2&&!job->cancel.load()){
                    import_progress(job,450);
                    ok=gx3de_backend::mesh_lod(*job->source_mesh,job->lod_level,imported,error);
                    if(ok)import_progress(job,900);
                }
#ifdef GX3DE_WITH_OCCT
                else if(job->kind==3&&!job->cancel.load()){
                    std::error_code ec;auto source=std::filesystem::u8path(job->path);
                    if(!std::filesystem::is_regular_file(source,ec)||ec)error="STEP source not found";
                    else {
                        uint64_t bytes=std::filesystem::file_size(source,ec),limit=job->max_source_bytes?job->max_source_bytes:256ull*1024*1024;
                        if(ec||bytes==0||bytes>limit)error="STEP source size exceeds limit or is empty";
                        else if(!job->cancel.load()){
                            import_progress(job,100);hash=sha256_source_file(source);
                            if(hash.empty())error="STEP source fingerprint failed";
                            else if(!job->cancel.load()){
                                import_progress(job,200);
                                gx3de_backend::StepImportOptions options;
                                options.max_nodes=job->max_nodes?job->max_nodes:100000;
                                options.cancelled=[job]{return job->cancel.load();};
                                std::shared_ptr<gx3de_backend::StepDocument> native;
                                if(gx3de_backend::step_read(source.string(),options,native,error)&&!job->cancel.load()){
                                    import_progress(job,900);
                                    auto after=sha256_source_file(source);auto final_bytes=std::filesystem::file_size(source,ec);
                                    if(ec||final_bytes!=bytes||after!=hash)error="STEP source changed during import";
                                    else if(!job->cancel.load()){job->step_native=std::move(native);ok=true;}
                                }
                            }
                        }
                    }
                }
                else if(job->kind==4&&!job->cancel.load()){
                    import_progress(job,100);
                    const auto& spec=job->brep_mesh_spec;
                    ok=gx3de_backend::tessellate_brep(*job->brep_source,
                        spec.linear_deflection,spec.angular_deflection,
                        spec.weld_tolerance,spec.max_triangles,spec.max_output_bytes,
                        imported,error);
                    if(ok&&!job->cancel.load())import_progress(job,900);
                }
#endif
            }catch(const std::bad_alloc&){error="STEP job allocation failed";}
            catch(const std::exception& ex){error=ex.what();}
            std::lock_guard<std::mutex> lock(job->mutex);
            if(job->cancel.load())job_event_locked(job,GX3DE_JOB_CANCELED,job->progress_permille);
            else if(ok){if(job->kind==3)job->source_hash=std::move(hash);else {job->mesh=std::move(imported);if(job->kind==1)job->source_hash=std::move(hash);}job_event_locked(job,GX3DE_JOB_COMPLETED,1000);}
            else {job->failure=std::move(error);job_event_locked(job,GX3DE_JOB_FAILED,job->progress_permille);}
        });return GX3DE_OK;
    }catch(const std::exception&){std::lock_guard<std::mutex> lock(job->mutex);job->failure="unable to start job worker";job_event_locked(job,GX3DE_JOB_FAILED,job->progress_permille);return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_job_cancel(gx3de_job* job) {
    if(!job)return GX3DE_INVALID_ARGUMENT;job->cancel.store(true);
    std::lock_guard<std::mutex> lock(job->mutex);if(job->state==GX3DE_JOB_READY)job_event_locked(job,GX3DE_JOB_CANCELED,job->progress_permille);return GX3DE_OK;
}
gx3de_result gx3de_job_poll(gx3de_job* job,gx3de_job_state* out) {
    if(!job||!out)return GX3DE_INVALID_ARGUMENT;std::lock_guard<std::mutex> lock(job->mutex);*out=job->state;return GX3DE_OK;
}
gx3de_result gx3de_job_wait(gx3de_job* job,uint64_t timeout_ms,gx3de_job_state* out) {
    if(!job||!out)return GX3DE_INVALID_ARGUMENT;std::unique_lock<std::mutex> lock(job->mutex);
    if(job->state==GX3DE_JOB_READY){*out=job->state;return GX3DE_OK;}
    auto done=[&]{return job->state==GX3DE_JOB_COMPLETED||job->state==GX3DE_JOB_CANCELED||job->state==GX3DE_JOB_FAILED;};
    if(timeout_ms==UINT64_MAX)job->condition.wait(lock,done);
    else job->condition.wait_for(lock,std::chrono::milliseconds(std::min<uint64_t>(timeout_ms,INT64_MAX)),done);
    *out=job->state;return GX3DE_OK;
}
gx3de_result gx3de_job_next_event(gx3de_job* job,gx3de_job_event* out) {
    if(!job||!out||out->struct_size<sizeof(gx3de_job_event))return GX3DE_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(job->mutex);if(job->event_read==job->event_count)return GX3DE_NOT_FOUND;
    *out=job->events[job->event_read++];return GX3DE_OK;
}
gx3de_result gx3de_job_progress(gx3de_job* job,uint64_t* progress_permille) {
    if(!job||!progress_permille)return GX3DE_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(job->mutex);*progress_permille=job->progress_permille;return GX3DE_OK;
}
gx3de_result gx3de_job_failure_text(gx3de_job* job,char* buffer,uint64_t capacity,uint64_t* required_bytes) {
    if(!job||!required_bytes||(!buffer&&capacity))return GX3DE_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(job->mutex);
    if(job->state!=GX3DE_JOB_FAILED)return GX3DE_NOT_FOUND;
    *required_bytes=job->failure.size()+1;
    if(capacity<*required_bytes)return GX3DE_RANGE;
    std::memcpy(buffer,job->failure.c_str(),size_t(*required_bytes));return GX3DE_OK;
}
gx3de_result gx3de_job_take_mesh(gx3de_job* job,gx3de_object** out) {
    if(!job||!out)return GX3DE_INVALID_ARGUMENT;if(job->kind==3)return GX3DE_UNSUPPORTED;Mesh copy;std::string hash;
    {std::lock_guard<std::mutex> lock(job->mutex);if(job->state==GX3DE_JOB_FAILED)return GX3DE_DEGENERATE;
        if(job->state!=GX3DE_JOB_COMPLETED||job->taken)return GX3DE_NOT_FOUND;
        try {copy=job->mesh;hash=job->source_hash;}catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}}
    auto result=retain_mesh(job->scene,std::move(copy),out);
    if(result==GX3DE_OK){
        (*out)->source_sha256=std::move(hash);
        if(job->kind==2||job->kind==4){(*out)->transform=job->source_transform;(*out)->visible=job->source_visible;(*out)->opacity=job->source_opacity;}
        if(job->kind==2||job->kind==4)(*out)->style=job->source_style;
#ifdef GX3DE_WITH_OCCT
        if(job->kind==4)(*out)->derivation_fingerprint=job->derivation_fingerprint;
#endif
        std::lock_guard<std::mutex> lock(job->mutex);job->taken=true;
    }
    return result;
}
gx3de_result gx3de_job_take_step(gx3de_job* job,gx3de_step_document** out) {
    if(!job||!out)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(job->kind!=3)return GX3DE_UNSUPPORTED;
    std::lock_guard<std::mutex> lock(job->mutex);
    if(job->state==GX3DE_JOB_FAILED)return GX3DE_DEGENERATE;
    if(job->state!=GX3DE_JOB_COMPLETED||job->taken)return GX3DE_NOT_FOUND;
    try {
        std::unique_ptr<gx3de_step_document> doc(new gx3de_step_document{});doc->engine=job->engine;doc->source_sha256=job->source_hash;
        doc->native=job->step_native;
        doc->prototype_shapes.resize(gx3de_backend::step_prototypes(*doc->native).size());
        auto result=retain(job->engine->step_documents,doc.release(),out);
        if(result==GX3DE_OK)job->taken=true;
        return result;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_job_destroy(gx3de_job* job) {if(!job)return GX3DE_INVALID_ARGUMENT;remove_job(job);return GX3DE_OK;}
gx3de_result gx3de_step_open(gx3de_engine* engine,const gx3de_step_import_spec* spec,gx3de_step_document** out) {
    if(!engine||!spec||!out||spec->struct_size<sizeof(gx3de_step_import_spec)||!valid_utf8(spec->path_utf8,4096))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    try {std::error_code ec;auto source=std::filesystem::u8path(spec->path_utf8);
        if(!std::filesystem::is_regular_file(source,ec)||ec)return GX3DE_NOT_FOUND;
        uint64_t bytes=std::filesystem::file_size(source,ec),limit=spec->max_source_bytes?spec->max_source_bytes:256ull*1024*1024;
        if(ec||bytes==0||bytes>limit)return GX3DE_RANGE;
        auto before=sha256_source_file(source);if(before.empty())return GX3DE_DEGENERATE;
        gx3de_backend::StepImportOptions options;options.max_nodes=spec->max_nodes?spec->max_nodes:100000;
        std::shared_ptr<gx3de_backend::StepDocument> native;std::string error;
        if(!gx3de_backend::step_read(source.string(),options,native,error))return GX3DE_DEGENERATE;
        auto after=sha256_source_file(source);auto final_size=std::filesystem::file_size(source,ec);
        if(ec||final_size!=bytes||after!=before)return GX3DE_DEGENERATE;
        auto doc=new gx3de_step_document{};doc->engine=engine;doc->source_sha256=std::move(before);doc->native=std::move(native);
        doc->prototype_shapes.resize(gx3de_backend::step_prototypes(*doc->native).size());
        return retain(engine->step_documents,doc,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}catch(const std::exception&){return GX3DE_DEGENERATE;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_summary_get(gx3de_step_document* doc,gx3de_step_summary* out) {
    if(!doc||!out||out->struct_size<sizeof(gx3de_step_summary))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    auto stats=gx3de_backend::step_stats(*doc->native);auto nodes=gx3de_backend::step_nodes(*doc->native).size();
    *out={sizeof(gx3de_step_summary),0,stats.root_count,nodes,stats.assembly_nodes,stats.reference_nodes,stats.part_occurrences,stats.unique_parts,{}};return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_node_get(gx3de_step_document* doc,uint64_t index,gx3de_step_node* out) {
    if(!doc||!out||out->struct_size<sizeof(gx3de_step_node))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    const auto& nodes=gx3de_backend::step_nodes(*doc->native);if(index>=nodes.size())return GX3DE_RANGE;
    const auto& node=nodes[size_t(index)];*out={sizeof(gx3de_step_node),uint32_t(node.kind),node.parent_index,node.prototype_index,uint32_t(node.is_reference),0,node.local_transform,node.world_transform,{}};return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_text_get(gx3de_step_document* doc,uint32_t field,uint64_t index,char* buffer,uint64_t capacity,uint64_t* required) {
    if(!doc||!required||(!buffer&&capacity))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    const std::string* value=nullptr;const auto& nodes=gx3de_backend::step_nodes(*doc->native);
    const auto& prototypes=gx3de_backend::step_prototypes(*doc->native);
    if(field>=GX3DE_STEP_NODE_ID&&field<=GX3DE_STEP_DEFINITION_ID){if(index>=nodes.size())return GX3DE_RANGE;
        const auto& node=nodes[size_t(index)];value=field==GX3DE_STEP_NODE_ID?&node.id:field==GX3DE_STEP_NODE_NAME?&node.name:&node.definition_id;
    }else if(field==GX3DE_STEP_PROTOTYPE_ID||field==GX3DE_STEP_PROTOTYPE_NAME){if(index>=prototypes.size())return GX3DE_RANGE;
        const auto& prototype=prototypes[size_t(index)];value=field==GX3DE_STEP_PROTOTYPE_ID?&prototype.id:&prototype.name;
    }else return GX3DE_INVALID_ARGUMENT;
    *required=value->size()+1;if(capacity<*required)return GX3DE_RANGE;
    std::memcpy(buffer,value->c_str(),size_t(*required));return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_source_sha256(gx3de_step_document* doc,char out[65]) {
    if(!doc||!out)return GX3DE_INVALID_ARGUMENT;
    std::memcpy(out,doc->source_sha256.c_str(),65);return GX3DE_OK;
}
gx3de_result gx3de_step_instance_create(gx3de_scene* scene,gx3de_step_document* doc,uint64_t node_index,gx3de_object** out) {
    if(!scene||!doc||!out)return GX3DE_INVALID_ARGUMENT;if(scene->engine!=doc->engine)return GX3DE_WRONG_OWNER;
#ifdef GX3DE_WITH_OCCT
    const auto& nodes=gx3de_backend::step_nodes(*doc->native);if(node_index>=nodes.size())return GX3DE_RANGE;
    const auto& node=nodes[size_t(node_index)];if(node.kind!=gx3de_backend::StepNodeKind::part||node.prototype_index>=doc->prototype_shapes.size())return GX3DE_UNSUPPORTED;
    try {auto& shape=doc->prototype_shapes[size_t(node.prototype_index)];if(!shape){TopoDS_Shape native;std::string error;
            if(!gx3de_backend::step_prototype_shape(*doc->native,node.prototype_index,native)||!gx3de_backend::adopt_step_shape(native,shape,error))return GX3DE_DEGENERATE;}
        auto o=new gx3de_object{scene,nullptr,node.world_transform};o->brep=shape;o->source_sha256=doc->source_sha256;
        return retain(scene->objects,o,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_compound_create(gx3de_scene* scene,gx3de_step_document* doc,gx3de_object** out) {
    if(!scene||!doc||!out)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(scene->engine!=doc->engine)return GX3DE_WRONG_OWNER;
#ifdef GX3DE_WITH_OCCT
    try {
        std::vector<std::shared_ptr<gx3de_backend::BrepShape>> parts;
        std::string error;
        for(const auto& node:gx3de_backend::step_nodes(*doc->native)) {
            if(node.kind!=gx3de_backend::StepNodeKind::part)continue;
            if(node.prototype_index>=doc->prototype_shapes.size())return GX3DE_DEGENERATE;
            auto& shape=doc->prototype_shapes[size_t(node.prototype_index)];
            if(!shape) {
                TopoDS_Shape native;
                if(!gx3de_backend::step_prototype_shape(*doc->native,node.prototype_index,native)||
                   !gx3de_backend::adopt_step_shape(native,shape,error))return GX3DE_DEGENERATE;
            }
            std::shared_ptr<gx3de_backend::BrepShape> placed;
            if(!gx3de_backend::transformed(*shape,node.world_transform,placed,error))return GX3DE_DEGENERATE;
            parts.push_back(std::move(placed));
        }
        std::shared_ptr<gx3de_backend::BrepShape> compound;
        if(!gx3de_backend::compound_shapes(parts,compound,error))return GX3DE_DEGENERATE;
        auto* object=new gx3de_object{scene,nullptr,identity()};
        object->brep=std::move(compound);object->source_sha256=doc->source_sha256;
        return retain(scene->objects,object,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_instance_mesh_create(gx3de_scene* scene,gx3de_step_document* doc,
    uint64_t node_index,const gx3de_step_mesh_spec* spec,gx3de_object** out) {
    if(!scene||!doc||!spec||!out||spec->struct_size<sizeof(gx3de_step_mesh_spec))return GX3DE_INVALID_ARGUMENT;
    if(scene->engine!=doc->engine)return GX3DE_WRONG_OWNER;
    if(!std::isfinite(spec->linear_deflection)||spec->linear_deflection<=0||
       !std::isfinite(spec->angular_deflection)||spec->angular_deflection<=0||spec->angular_deflection>3.141592653589793||
       !std::isfinite(spec->weld_tolerance)||spec->weld_tolerance<0||
       !spec->max_triangles||!spec->max_output_bytes)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    const auto& nodes=gx3de_backend::step_nodes(*doc->native);
    if(node_index>=nodes.size())return GX3DE_RANGE;
    const auto& node=nodes[size_t(node_index)];
    if(node.kind!=gx3de_backend::StepNodeKind::part||node.prototype_index>=doc->prototype_shapes.size())return GX3DE_UNSUPPORTED;
    try {
        const auto cache_key=std::make_tuple(node.prototype_index,spec->linear_deflection,
            spec->angular_deflection,spec->weld_tolerance,spec->max_triangles,spec->max_output_bytes);
        auto found=doc->prototype_meshes.find(cache_key);
        std::shared_ptr<const Mesh> mesh;
        if(found!=doc->prototype_meshes.end())mesh=found->second;
        else {
            auto* engine=scene->engine;
            gx3de_backend::MeshDiskCacheKey disk_key{};
            Mesh generated;std::string error;bool disk_hit=false;
            if(!engine->disk_cache_root.empty()){
                auto bits=[](double value){uint64_t raw;std::memcpy(&raw,&value,8);return std::to_string(raw);};
                const std::string version="gx3de-stepmesh-v1|occt-"+std::to_string(OCC_VERSION_HEX)+"|"+
                    std::to_string(node.prototype_index)+"|"+bits(spec->linear_deflection)+"|"+
                    bits(spec->angular_deflection)+"|"+bits(spec->weld_tolerance)+"|"+
                    std::to_string(spec->max_triangles)+"|"+std::to_string(spec->max_output_bytes);
                disk_key={engine->cache_namespace,doc->source_sha256,4,version};
                auto status=gx3de_backend::mesh_disk_cache_load(engine->disk_cache_root.c_str(),
                    disk_key,generated,error,spec->max_output_bytes);
                if(status==gx3de_backend::MeshDiskCacheLoad::Hit){++engine->disk_hits;disk_hit=true;}
                else if(status==gx3de_backend::MeshDiskCacheLoad::Invalid)++engine->disk_invalid;
                else if(status==gx3de_backend::MeshDiskCacheLoad::Miss)++engine->disk_misses;
                else return GX3DE_DEGENERATE;
            }
            if(!disk_hit){
                TopoDS_Shape native;
                if(!gx3de_backend::step_prototype_shape(*doc->native,node.prototype_index,native))return GX3DE_DEGENERATE;
                if(!gx3de_backend::tessellate_step_prototype(native,spec->linear_deflection,
                    spec->angular_deflection,spec->weld_tolerance,spec->max_triangles,
                    spec->max_output_bytes,generated,error))
                    return error.find("budget")!=std::string::npos?GX3DE_RANGE:GX3DE_DEGENERATE;
                if(!engine->disk_cache_root.empty()&&
                   !gx3de_backend::mesh_disk_cache_store(engine->disk_cache_root.c_str(),
                       disk_key,generated,error,spec->max_output_bytes))++engine->disk_store_failures;
            }
            if(generated.triangles.size()/3>spec->max_triangles)return GX3DE_RANGE;
            mesh=std::make_shared<Mesh>(std::move(generated));
            doc->prototype_meshes.emplace(cache_key,mesh);
        }
        auto fp=fingerprint(*mesh,scene->engine->cache_namespace);
        if(fp.empty())return GX3DE_OUT_OF_MEMORY;
        auto* engine=scene->engine;
        auto existing=engine->mesh_cache.find(fp);
        if(existing!=engine->mesh_cache.end()){
            if(auto shared=existing->second.lock()){mesh=std::move(shared);++engine->cache_hits;}
            else {engine->mesh_cache[fp]=mesh;++engine->cache_misses;}
        }else {engine->mesh_cache.emplace(fp,mesh);++engine->cache_misses;}
        auto object=new gx3de_object{scene,mesh,node.world_transform};
        object->fingerprint=std::move(fp);object->source_sha256=doc->source_sha256;
        return retain(scene->objects,object,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_step_close(gx3de_step_document* doc) {if(!doc)return GX3DE_INVALID_ARGUMENT;erase_ptr(doc->engine->step_documents,doc);delete doc;return GX3DE_OK;}
gx3de_result gx3de_object_brep_mesh_create(gx3de_object* source,
    const gx3de_brep_mesh_spec* spec,gx3de_object** out) {
    if(!source||!spec||!out||spec->struct_size<sizeof(gx3de_brep_mesh_spec)||
       !std::isfinite(spec->linear_deflection)||spec->linear_deflection<=0||
       !std::isfinite(spec->angular_deflection)||spec->angular_deflection<=0||
       spec->angular_deflection>3.141592653589793||
       !std::isfinite(spec->weld_tolerance)||spec->weld_tolerance<0||
       !spec->max_triangles||!spec->max_output_bytes)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!source->brep)return GX3DE_UNSUPPORTED;
    try {
        auto* engine=source->scene->engine;
        std::string source_fp,error;
        if(!gx3de_backend::shape_fingerprint(*source->brep,engine->cache_namespace,
                                             source_fp,error))
            return error.find("256 MiB")!=std::string::npos?GX3DE_RANGE:GX3DE_DEGENERATE;
        auto bits=[](double value){uint64_t raw;std::memcpy(&raw,&value,8);return std::to_string(raw);};
        const std::string version="gx3de-brepmesh-v1|occt-"+std::to_string(OCC_VERSION_HEX)+"|"+
            bits(spec->linear_deflection)+"|"+bits(spec->angular_deflection)+"|"+
            bits(spec->weld_tolerance)+"|"+std::to_string(spec->max_triangles)+"|"+
            std::to_string(spec->max_output_bytes);
        gx3de_backend::MeshDiskCacheKey key{engine->cache_namespace,source_fp,5,version};
        Mesh generated;bool disk_hit=false;
        if(!engine->disk_cache_root.empty()){
            auto status=gx3de_backend::mesh_disk_cache_load(engine->disk_cache_root.c_str(),
                key,generated,error,spec->max_output_bytes);
            if(status==gx3de_backend::MeshDiskCacheLoad::Hit){++engine->disk_hits;disk_hit=true;}
            else if(status==gx3de_backend::MeshDiskCacheLoad::Invalid)++engine->disk_invalid;
            else if(status==gx3de_backend::MeshDiskCacheLoad::Miss)++engine->disk_misses;
            else return GX3DE_DEGENERATE;
        }
        if(!disk_hit){
            if(!gx3de_backend::tessellate_brep(*source->brep,spec->linear_deflection,
                spec->angular_deflection,spec->weld_tolerance,spec->max_triangles,
                spec->max_output_bytes,generated,error))
                return error.find("budget")!=std::string::npos?GX3DE_RANGE:GX3DE_DEGENERATE;
            if(!engine->disk_cache_root.empty()&&
               !gx3de_backend::mesh_disk_cache_store(engine->disk_cache_root.c_str(),
                   key,generated,error,spec->max_output_bytes))++engine->disk_store_failures;
        }
        if(generated.triangles.size()/3>spec->max_triangles||
           generated.vertices.size()*sizeof(gx3de_vec3)+
           generated.triangles.size()*sizeof(uint32_t)>spec->max_output_bytes)return GX3DE_RANGE;
        auto fp=fingerprint(generated,engine->cache_namespace);
        if(fp.empty())return GX3DE_OUT_OF_MEMORY;
        std::shared_ptr<const Mesh> mesh=std::make_shared<Mesh>(std::move(generated));
        auto existing=engine->mesh_cache.find(fp);
        if(existing!=engine->mesh_cache.end()){
            if(auto shared=existing->second.lock()){mesh=std::move(shared);++engine->cache_hits;}
            else {engine->mesh_cache[fp]=mesh;++engine->cache_misses;}
        }else {engine->mesh_cache.emplace(fp,mesh);++engine->cache_misses;}
        auto* object=new gx3de_object(*source);
        object->mesh=std::move(mesh);object->brep.reset();
        object->transform=world(source);object->parent=nullptr;
        object->fingerprint=std::move(fp);
        object->derivation_fingerprint=std::move(source_fp);
        return retain(source->scene->objects,object,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_object_derivation_fingerprint(gx3de_object* object,char out[65]) {
    if(!object||!out)return GX3DE_INVALID_ARGUMENT;
    if(object->derivation_fingerprint.size()!=64)return GX3DE_NOT_FOUND;
    std::memcpy(out,object->derivation_fingerprint.c_str(),65);return GX3DE_OK;
}
gx3de_result gx3de_object_brep_mesh_create_world(gx3de_object* source,const gx3de_brep_mesh_spec* spec,gx3de_object** out) {
    if(!source||!spec||!out)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(!source->planar_textures.empty()||!source->curved_textures.empty())return GX3DE_UNSUPPORTED;
#ifdef GX3DE_WITH_OCCT
    if(!source->brep)return GX3DE_UNSUPPORTED;
    try {
        std::shared_ptr<gx3de_backend::BrepShape> shape;std::string error;
        if(!gx3de_backend::transformed(*source->brep,world(source),shape,error))return GX3DE_DEGENERATE;
        gx3de_object working=*source;working.brep=std::move(shape);working.transform=identity();working.parent=nullptr;
        return gx3de_object_brep_mesh_create(&working,spec,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_object_duplicate(gx3de_object* src,gx3de_object** out) {
    if(!src||!out)return GX3DE_INVALID_ARGUMENT;
    gx3de_object* copy=nullptr;
    try {
        copy=new gx3de_object(*src);copy->transform=world(src);copy->parent=nullptr;
        copy->planar_textures.clear();
        copy->curved_textures.clear();
        for(auto* assignment:src->planar_textures){
            auto* cloned=new gx3de_planar_texture(*assignment);cloned->object=copy;
            try{copy->planar_textures.push_back(cloned);}catch(...){delete cloned;throw;}
        }
        for(auto* assignment:src->curved_textures){
            auto* cloned=new gx3de_curved_texture(*assignment);cloned->object=copy;
            try{copy->curved_textures.push_back(cloned);}catch(...){delete cloned;throw;}
        }
        src->scene->objects.push_back(copy);*out=copy;return GX3DE_OK;
    }catch(const std::bad_alloc&){
        if(copy){for(auto* assignment:copy->planar_textures)delete assignment;
            for(auto* assignment:copy->curved_textures)delete assignment;delete copy;}
        return GX3DE_OUT_OF_MEMORY;
    }
}
gx3de_result gx3de_object_bake_transform(gx3de_object* source,gx3de_object** out) {
    if(!source||!out)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(!source->planar_textures.empty()||!source->curved_textures.empty())return GX3DE_UNSUPPORTED;
    gx3de_object* copy=nullptr;
    try {
        std::shared_ptr<const Mesh> mesh;std::string digest;
#ifdef GX3DE_WITH_OCCT
        std::shared_ptr<gx3de_backend::BrepShape> shape;
        if(source->brep){std::string error;if(!gx3de_backend::transformed(*source->brep,world(source),shape,error))return GX3DE_DEGENERATE;}
        else
#endif
        if(source->mesh){auto placed=placed_mesh(source);digest=fingerprint(placed,source->scene->engine->cache_namespace);if(digest.empty())return GX3DE_OUT_OF_MEMORY;mesh=std::make_shared<Mesh>(std::move(placed));}
        else return GX3DE_UNSUPPORTED;
        auto code=gx3de_object_duplicate(source,&copy);if(code!=GX3DE_OK)return code;
        copy->transform=identity();copy->parent=nullptr;copy->projection_source=nullptr;copy->projection_plane=nullptr;
        if(mesh){copy->mesh=std::move(mesh);copy->fingerprint=std::move(digest);}
#ifdef GX3DE_WITH_OCCT
        if(shape)copy->brep=std::move(shape);
#endif
        *out=copy;return GX3DE_OK;
    }catch(const std::bad_alloc&){if(copy)gx3de_object_destroy(copy);return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_rescale_coordinates(gx3de_object* source,double factor,gx3de_object** out) {
    if(!source||!out||!std::isfinite(factor)||factor<=0)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;auto placement=world(source);
    for(size_t i=12;i<15;++i){placement.m[i]*=factor;if(!std::isfinite(placement.m[i]))return GX3DE_RANGE;}
    try {
        gx3de_object local=*source;local.parent=nullptr;local.transform=identity();local.transform.m[0]=local.transform.m[5]=local.transform.m[10]=factor;
        gx3de_object* result=nullptr;auto code=gx3de_object_bake_transform(&local,&result);if(code!=GX3DE_OK)return code;
        code=gx3de_object_set_transform(result,&placement);if(code!=GX3DE_OK){gx3de_object_destroy(result);return code;}
        *out=result;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_group_member_count(gx3de_group* group,uint64_t* out) {
    if(!group||!out)return GX3DE_INVALID_ARGUMENT;
    *out=0;for(auto* object:group->scene->objects)if(object->parent==group->node)++*out;
    return GX3DE_OK;
}
gx3de_result gx3de_group_member_get(gx3de_group* group,uint64_t index,gx3de_object** out) {
    if(!group||!out)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;for(auto* object:group->scene->objects)if(object->parent==group->node){if(index==0){*out=object;return GX3DE_OK;}--index;}
    return GX3DE_RANGE;
}
gx3de_result gx3de_group_duplicate(gx3de_group* source,gx3de_group** out) {
    if(!source||!out)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    std::vector<gx3de_object*> created;
    std::vector<gx3de_group*> groups;
    auto rollback=[&](){for(auto it=groups.rbegin();it!=groups.rend();++it){erase_ptr(source->scene->groups,*it);delete *it;}
        for(auto it=created.rbegin();it!=created.rend();++it)gx3de_object_destroy(*it);};
    try {
        std::vector<std::pair<uint64_t,gx3de_object*>> originals{{0,source->node}};
        std::unordered_set<gx3de_object*> groupNodes;
        for(auto* group:source->scene->groups)groupNodes.insert(group->node);
        for(auto* object:source->scene->objects)if(object!=source->node){uint64_t depth=0;bool inside=false;
            for(auto* parent=object->parent;parent;parent=parent->parent){if(++depth>256)return GX3DE_RANGE;if(parent==source->node){inside=true;break;}}
            if(inside)originals.push_back({depth,object});
        }
        if(originals.size()>100000)return GX3DE_RANGE;
        std::stable_sort(originals.begin(),originals.end(),[](const auto& a,const auto& b){return a.first<b.first;});
        created.reserve(originals.size());groups.reserve(originals.size());
        std::unordered_map<gx3de_object*,gx3de_object*> copies;copies.reserve(originals.size());
        gx3de_group* root=nullptr;
        for(const auto& entry:originals){auto* original=entry.second;gx3de_object* copy=nullptr;
            auto code=gx3de_object_duplicate(original,&copy);if(code!=GX3DE_OK){rollback();return code;}
            created.push_back(copy);
            if(original!=source->node){copy->parent=copies.at(original->parent);copy->transform=original->transform;}
            copies.emplace(original,copy);
            if(groupNodes.count(original)){auto* group=new gx3de_group{source->scene,copy};
                try{source->scene->groups.push_back(group);}catch(...){delete group;throw;}
                groups.push_back(group);if(original==source->node)root=group;
            }
        }
        *out=root;return GX3DE_OK;
    }catch(const std::bad_alloc&){rollback();return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_destroy(gx3de_object* o) {
    if(!o)return GX3DE_INVALID_ARGUMENT;
    for(auto* view:o->scene->views)for(auto* gizmo:view->gizmos)
        if(gizmo->spec.object==o&&gizmo->active)gx3de_gizmo_end(gizmo,0);
    for(auto child:o->scene->objects)if(child->parent==o){child->transform=world(child);child->parent=nullptr;}
    for(auto a:o->scene->anchors)if(a->object==o){
        gx3de_anchor_position(a,&a->free_point);
        if(a->kind==GX3DE_ANCHOR_OBJECT_AXIS){
            gx3de_vec3 direction{};
            if(gx3de_anchor_tangent(a,&direction)==GX3DE_OK){a->local_direction=direction;a->kind=GX3DE_ANCHOR_LINE;}
            else a->kind=GX3DE_ANCHOR_FREE;
        }else a->kind=GX3DE_ANCHOR_FREE;
        a->object=nullptr;
    }
    for(auto c:o->scene->constraints){if(c->spec.moving_object==o)c->spec.moving_object=nullptr;if(c->extended_spec.moving_object==o)c->extended_spec.moving_object=nullptr;if(c->extended_spec.surface_object==o)c->extended_spec.surface_object=nullptr;}
    for(auto m:o->scene->measurements)if(m->surface==o)m->surface=nullptr;
    for(auto r:o->scene->repeats)if(r->source==o){r->source=nullptr;r->presentation_enabled=false;}
    for(auto other:o->scene->objects)if(other->projection_source==o)other->projection_source=nullptr;
    for(auto section:o->scene->sections)if(section->source==o)section->source=nullptr;
    for(auto* view:o->scene->views){if(view->axes.local_object==o){view->axes.local_object=nullptr;view->axes.show_local=0;}
        for(auto* gizmo:view->gizmos)if(gizmo->spec.object==o){
            gizmo->spec.object=nullptr;gizmo->spec.visible=0;}}
    for(auto* assignment:o->planar_textures)delete assignment;
    for(auto* assignment:o->curved_textures)delete assignment;
    erase_ptr(o->scene->objects,o);delete o;return GX3DE_OK;
}
gx3de_result gx3de_object_set_parent(gx3de_object* o,gx3de_object* p) { if(!o)return GX3DE_INVALID_ARGUMENT;if(p&&p->scene!=o->scene)return GX3DE_WRONG_OWNER;for(auto q=p;q;q=q->parent)if(q==o)return GX3DE_INVALID_ARGUMENT;o->parent=p;return GX3DE_OK; }
gx3de_result gx3de_object_set_visible(gx3de_object* o,uint32_t v) { if(!o||v>1)return GX3DE_INVALID_ARGUMENT;o->visible=v;return GX3DE_OK; }
gx3de_result gx3de_object_get_visible(gx3de_object* o,uint32_t* v) { if(!o||!v)return GX3DE_INVALID_ARGUMENT;*v=o->visible;return GX3DE_OK; }
gx3de_result gx3de_object_geometry_role_set(gx3de_object* object,uint32_t role) {
    if(!object||role>GX3DE_GEOMETRY_REFERENCE)return GX3DE_INVALID_ARGUMENT;
    object->geometry_role=role;return GX3DE_OK;
}
gx3de_result gx3de_object_geometry_role_get(gx3de_object* object,uint32_t* role) {
    if(!object||!role)return GX3DE_INVALID_ARGUMENT;
    *role=object->geometry_role;return GX3DE_OK;
}
gx3de_result gx3de_object_set_opacity(gx3de_object* o,double value) {if(!o||!std::isfinite(value)||value<0||value>1)return GX3DE_INVALID_ARGUMENT;o->opacity=value;return GX3DE_OK;}
gx3de_result gx3de_object_get_opacity(gx3de_object* o,double* value) {if(!o||!value)return GX3DE_INVALID_ARGUMENT;*value=o->opacity;return GX3DE_OK;}
gx3de_result gx3de_object_scientific_transmittance_set(gx3de_object* object,double value){
    if(!object||!std::isfinite(value)||(value!=-1&&(value<0||value>1)))
        return GX3DE_INVALID_ARGUMENT;
    if(!object->mesh)return GX3DE_UNSUPPORTED;
    object->scientific_transmittance=value;return GX3DE_OK;
}
gx3de_result gx3de_object_scientific_transmittance_get(gx3de_object* object,double* value){
    if(!object||!value)return GX3DE_INVALID_ARGUMENT;
    if(!object->mesh)return GX3DE_UNSUPPORTED;
    *value=object->scientific_transmittance;return GX3DE_OK;
}
gx3de_result gx3de_object_style_set(gx3de_object* o,const gx3de_object_style* s) {
    if(!o||!s||s->struct_size<sizeof(*s)||s->mode<GX3DE_DISPLAY_SURFACE||
       s->mode>GX3DE_DISPLAY_POINTS||!renderer_valid_rgb(s->color)||
       !std::isfinite(s->line_width)||s->line_width<=0||s->line_width>64||
       !std::isfinite(s->point_size)||s->point_size<=0||s->point_size>128||
       s->backface_culling>1||s->scalar_coloring>1)return GX3DE_INVALID_ARGUMENT;
    o->style=*s;o->style.struct_size=sizeof(*s);return GX3DE_OK;
}
gx3de_result gx3de_object_style_get(gx3de_object* o,gx3de_object_style* s) {
    if(!o||!s||s->struct_size<sizeof(*s))return GX3DE_INVALID_ARGUMENT;
    *s=o->style;return GX3DE_OK;
}
gx3de_result gx3de_object_set_transform(gx3de_object* o,const gx3de_mat4* m) { if(!o||!m||!affine(*m))return GX3DE_INVALID_ARGUMENT;o->transform=*m;return GX3DE_OK; }
gx3de_result gx3de_object_get_transform(gx3de_object* o,gx3de_mat4* m) { if(!o||!m)return GX3DE_INVALID_ARGUMENT;*m=o->transform;return GX3DE_OK; }
gx3de_result gx3de_object_scene_get(gx3de_object* o,gx3de_scene** scene) {
    if(!o||!scene)return GX3DE_INVALID_ARGUMENT;
    *scene=o->scene;return GX3DE_OK;
}
gx3de_result gx3de_object_world_transform_get(gx3de_object* o,gx3de_mat4* matrix) {
    if(!o||!matrix)return GX3DE_INVALID_ARGUMENT;
    *matrix=world(o);return GX3DE_OK;
}
gx3de_result gx3de_object_reset_transform(gx3de_object* o) { if(!o)return GX3DE_INVALID_ARGUMENT;o->transform=identity();return GX3DE_OK; }
static gx3de_result compose(gx3de_object* o,const gx3de_mat4& m,uint32_t w) { if(!o||w>1)return GX3DE_INVALID_ARGUMENT;
    if(!w){o->transform=product(o->transform,m);return GX3DE_OK;}
    auto desired=product(m,world(o));if(!o->parent){o->transform=desired;return GX3DE_OK;}
    gx3de_mat4 inverse;if(!inverse_affine(world(o->parent),inverse))return GX3DE_DEGENERATE;o->transform=product(inverse,desired);return GX3DE_OK; }
gx3de_result gx3de_object_translate(gx3de_object* o,gx3de_vec3 d,uint32_t w) { return finite(d)?compose(o,translation(d),w):GX3DE_INVALID_ARGUMENT; }
gx3de_result gx3de_object_rotate(gx3de_object* o,gx3de_vec3 axis,double radians,gx3de_vec3 pivot,uint32_t w) {
    double n=length(axis);if(!finite(axis)||!finite(pivot)||!std::isfinite(radians)||n<1e-12)return GX3DE_DEGENERATE;
    axis=mul(axis,1/n);double c=std::cos(radians),s=std::sin(radians),t=1-c,x=axis.x,y=axis.y,z=axis.z;
    auto m=identity();m.m[0]=t*x*x+c;m.m[4]=t*x*y-s*z;m.m[8]=t*x*z+s*y;
    m.m[1]=t*x*y+s*z;m.m[5]=t*y*y+c;m.m[9]=t*y*z-s*x;
    m.m[2]=t*x*z-s*y;m.m[6]=t*y*z+s*x;m.m[10]=t*z*z+c;
    return compose(o,product(product(translation(pivot),m),translation(mul(pivot,-1))),w);
}
gx3de_result gx3de_object_scale(gx3de_object* o,gx3de_vec3 f,gx3de_vec3 pivot,uint32_t w) { if(!finite(f)||!finite(pivot)||f.x==0||f.y==0||f.z==0)return GX3DE_DEGENERATE;auto m=identity();m.m[0]=f.x;m.m[5]=f.y;m.m[10]=f.z;return compose(o,product(product(translation(pivot),m),translation(mul(pivot,-1))),w); }
gx3de_result gx3de_object_align_three_points(const gx3de_alignment_spec* spec) {
    if(!spec||spec->struct_size<sizeof(gx3de_alignment_spec)||!spec->moving_object||
       !std::isfinite(spec->tolerance)||spec->tolerance<=0)return GX3DE_INVALID_ARGUMENT;
    auto moving=spec->moving_object;gx3de_vec3 source[3],target[3];
    for(int i=0;i<3;++i){auto a=spec->moving_points[i],b=spec->target_points[i];
        if(!a||!b||a->object!=moving)return GX3DE_INVALID_ARGUMENT;
        if(a->scene!=moving->scene||b->scene!=moving->scene)return GX3DE_WRONG_OWNER;
        for(auto parent=b->object;parent;parent=parent->parent)if(parent==moving)return GX3DE_INVALID_ARGUMENT;
        if(gx3de_anchor_position(a,&source[i])!=GX3DE_OK||gx3de_anchor_position(b,&target[i])!=GX3DE_OK)return GX3DE_NOT_FOUND;
    }
    for(int i=0;i<3;++i)for(int j=i+1;j<3;++j)
        if(std::abs(length(sub(source[i],source[j]))-length(sub(target[i],target[j])))>spec->tolerance)return GX3DE_DEGENERATE;
    auto basis=[&](const gx3de_vec3 p[3],gx3de_vec3 axes[3])->bool{
        auto x=sub(p[1],p[0]);double len=length(x);if(len<=spec->tolerance)return false;axes[0]=mul(x,1/len);
        auto z=cross(axes[0],sub(p[2],p[0]));len=length(z);if(len<=spec->tolerance)return false;
        axes[2]=mul(z,1/len);axes[1]=cross(axes[2],axes[0]);return true;};
    gx3de_vec3 from[3],to[3];if(!basis(source,from)||!basis(target,to))return GX3DE_DEGENERATE;
    auto delta=identity();
    auto coord=[](gx3de_vec3 p,int axis){return axis==0?p.x:axis==1?p.y:p.z;};
    for(int column=0;column<3;++column)for(int row=0;row<3;++row){
        double src[]={coord(from[0],column),coord(from[1],column),coord(from[2],column)};
        double dst[]={coord(to[0],row),coord(to[1],row),coord(to[2],row)};
        delta.m[column*4+row]=src[0]*dst[0]+src[1]*dst[1]+src[2]*dst[2];
    }
    auto mapped=apply(delta,source[0]);auto shift=sub(target[0],mapped);
    delta.m[12]=shift.x;delta.m[13]=shift.y;delta.m[14]=shift.z;
    auto desired=product(delta,world(moving));gx3de_mat4 proposed=desired;
    if(moving->parent){gx3de_mat4 inverse;if(!inverse_affine(world(moving->parent),inverse))return GX3DE_DEGENERATE;proposed=product(inverse,desired);}
    auto prior=moving->transform;moving->transform=proposed;
    for(int i=0;i<3;++i){gx3de_vec3 actual;if(gx3de_anchor_position(spec->moving_points[i],&actual)!=GX3DE_OK||length(sub(actual,target[i]))>spec->tolerance){moving->transform=prior;return GX3DE_DEGENERATE;}}
    return GX3DE_OK;
}
gx3de_result gx3de_object_bounds(gx3de_object* o,uint32_t w,gx3de_bounds* out) { if(!o||!out||w>1)return GX3DE_INVALID_ARGUMENT;auto m=w?world(o):identity();gx3de_vec3 lo{},hi{};
    if(o->mesh){lo=apply(m,o->mesh->vertices[0]);hi=lo;for(auto v:o->mesh->vertices){v=apply(m,v);lo={std::min(lo.x,v.x),std::min(lo.y,v.y),std::min(lo.z,v.z)};hi={std::max(hi.x,v.x),std::max(hi.y,v.y),std::max(hi.z,v.z)};}}
    else if(o->scientific){auto* data=o->scientific->dataset.GetPointer();if(data->GetNumberOfPoints()==0)return GX3DE_NOT_FOUND;
        double p[3];data->GetPoint(0,p);lo=hi=apply(m,{p[0],p[1],p[2]});
        for(vtkIdType i=1;i<data->GetNumberOfPoints();++i){data->GetPoint(i,p);auto v=apply(m,{p[0],p[1],p[2]});
            lo={std::min(lo.x,v.x),std::min(lo.y,v.y),std::min(lo.z,v.z)};
            hi={std::max(hi.x,v.x),std::max(hi.y,v.y),std::max(hi.z,v.z)};}}
#ifdef GX3DE_WITH_OCCT
    else if(o->brep){std::shared_ptr<gx3de_backend::BrepShape> placed;std::string error;if(!gx3de_backend::transformed(*o->brep,m,placed,error))return GX3DE_DEGENERATE;gx3de_bounds actual;if(!gx3de_backend::bounds(*placed,actual))return GX3DE_DEGENERATE;lo=actual.min;hi=actual.max;}
#endif
    else return GX3DE_UNSUPPORTED;*out={lo,hi};return GX3DE_OK; }
gx3de_result gx3de_object_counts(gx3de_object* o,uint64_t* nv,uint64_t* nt) { if(!o||!nv||!nt)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;*nv=o->mesh->vertices.size();*nt=o->mesh->triangles.size()/3;return GX3DE_OK; }
gx3de_result gx3de_object_vertex(gx3de_object* o,uint64_t i,uint32_t w,gx3de_vec3* out) { if(!o||!out||w>1)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;if(i>=o->mesh->vertices.size())return GX3DE_RANGE;*out=w?apply(world(o),o->mesh->vertices[i]):o->mesh->vertices[i];return GX3DE_OK; }
gx3de_result gx3de_mesh_diagnose(gx3de_object* o,gx3de_mesh_diagnostics* out) {
    if(!o||!out||out->struct_size<sizeof(gx3de_mesh_diagnostics))return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {
        struct Edge { uint32_t count=0,forward=0; };
        std::unordered_map<uint64_t,Edge> edges;std::vector<uint32_t> parents(o->mesh->vertices.size());
        for(uint32_t i=0;i<parents.size();++i)parents[i]=i;
        auto root=[&](uint32_t i){while(parents[i]!=i){parents[i]=parents[parents[i]];i=parents[i];}return i;};
        double area=0,volume=0;const auto& idx=o->mesh->triangles;const auto& v=o->mesh->vertices;
        for(size_t i=0;i<idx.size();i+=3){
            uint32_t a=idx[i],b=idx[i+1],c=idx[i+2];
            parents[root(b)]=root(a);parents[root(c)]=root(a);
            auto ab=sub(v[b],v[a]),ac=sub(v[c],v[a]);area+=length(cross(ab,ac))*0.5;
            volume+=dot(v[a],cross(v[b],v[c]))/6.0;
            uint32_t face[3]={a,b,c};for(int j=0;j<3;++j){uint32_t first=face[j],second=face[(j+1)%3];uint32_t lo=std::min(first,second),hi=std::max(first,second);auto& edge=edges[(uint64_t(lo)<<32)|hi];++edge.count;if(first==lo)++edge.forward;}
        }
        uint64_t boundary=0,nonmanifold=0,orientation=0;for(const auto& kv:edges){auto e=kv.second;if(e.count==1)++boundary;else if(e.count>2)++nonmanifold;else if(e.forward!=1)++orientation;}
        std::unordered_set<uint32_t> components;for(auto i:idx)components.insert(root(i));
        const bool closed=boundary==0&&nonmanifold==0&&orientation==0;
        const bool volume_defined=closed&&components.size()==1;
        *out={sizeof(gx3de_mesh_diagnostics),uint32_t(closed),boundary,nonmanifold,orientation,components.size(),area,volume_defined?std::abs(volume):0.0,uint32_t(volume_defined),0,{}};
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_diagnose_world(gx3de_object* o,gx3de_mesh_diagnostics* out) {
    if(!o||!out||out->struct_size<sizeof(gx3de_mesh_diagnostics))return GX3DE_INVALID_ARGUMENT;
    if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {
        gx3de_object placed=*o;
        placed.mesh=std::make_shared<Mesh>(placed_mesh(o));
        return gx3de_mesh_diagnose(&placed,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
static std::vector<uint64_t> mesh_boundary_keys(const gx3de_object* o) {
    std::unordered_map<uint64_t,uint32_t> counts;const auto& faces=o->mesh->triangles;
    for(size_t i=0;i<faces.size();i+=3)for(int k=0;k<3;++k){uint32_t a=faces[i+k],b=faces[i+(k+1)%3];uint64_t key=(uint64_t(std::min(a,b))<<32)|std::max(a,b);++counts[key];}
    std::vector<uint64_t> edges;for(auto [key,count]:counts)if(count==1)edges.push_back(key);std::sort(edges.begin(),edges.end());return edges;
}
gx3de_result gx3de_mesh_boundary_edges(gx3de_object* o,uint32_t* pairs,uint64_t capacity,uint64_t* required) {
    if(!o||!required||(!pairs&&capacity))return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {auto edges=mesh_boundary_keys(o);*required=edges.size();
        if(capacity<edges.size())return GX3DE_RANGE;
        for(size_t i=0;i<edges.size();++i){pairs[i*2]=uint32_t(edges[i]>>32);pairs[i*2+1]=uint32_t(edges[i]);}return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_boundary_edges_range(gx3de_object* o,uint64_t start,uint64_t count,uint32_t* pairs,uint64_t capacity,uint64_t* copied,uint64_t* total) {
    if(!o||!copied||!total||count>65536||capacity<count||(!pairs&&count))return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {auto edges=mesh_boundary_keys(o);if(start>edges.size())return GX3DE_RANGE;
        uint64_t take=std::min(count,uint64_t(edges.size())-start);
        for(uint64_t i=0;i<take;++i){pairs[i*2]=uint32_t(edges[start+i]>>32);pairs[i*2+1]=uint32_t(edges[start+i]);}
        *copied=take;*total=edges.size();return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_loops_create(gx3de_object* o,gx3de_mesh_loops** out) {
    if(!o||!out)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {std::vector<std::vector<uint32_t>> loops;std::string error;
        if(!gx3de_backend::boundary_loops(*o->mesh,loops,error))return GX3DE_DEGENERATE;
        std::vector<gx3de_vec3> captured;captured.reserve(o->mesh->vertices.size());auto m=world(o);
        for(auto vertex:o->mesh->vertices)captured.push_back(apply(m,vertex));
        auto result=new gx3de_mesh_loops{o->scene,std::move(loops),std::move(captured)};
        return retain(o->scene->mesh_loops,result,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_loops_count(gx3de_mesh_loops* loops,uint64_t* out) {if(!loops||!out)return GX3DE_INVALID_ARGUMENT;*out=loops->loops.size();return GX3DE_OK;}
gx3de_result gx3de_mesh_loops_size(gx3de_mesh_loops* loops,uint64_t i,uint64_t* out) {if(!loops||!out)return GX3DE_INVALID_ARGUMENT;if(i>=loops->loops.size())return GX3DE_RANGE;*out=loops->loops[i].size();return GX3DE_OK;}
gx3de_result gx3de_mesh_loops_vertex(gx3de_mesh_loops* loops,uint64_t i,uint64_t j,uint32_t* index,gx3de_vec3* point) {if(!loops||!index||!point)return GX3DE_INVALID_ARGUMENT;if(i>=loops->loops.size()||j>=loops->loops[i].size())return GX3DE_RANGE;*index=loops->loops[i][j];*point=loops->world_vertices[*index];return GX3DE_OK;}
gx3de_result gx3de_mesh_loops_destroy(gx3de_mesh_loops* loops) {if(!loops)return GX3DE_INVALID_ARGUMENT;erase_ptr(loops->scene->mesh_loops,loops);delete loops;return GX3DE_OK;}
gx3de_result gx3de_mesh_append(gx3de_object* a,gx3de_object* b,gx3de_object** out) {
    if(!a||!b||!out)return GX3DE_INVALID_ARGUMENT;if(a->scene!=b->scene)return GX3DE_WRONG_OWNER;if(!a->mesh||!b->mesh)return GX3DE_UNSUPPORTED;
    if(a->mesh->vertices.size()+b->mesh->vertices.size()>UINT32_MAX)return GX3DE_RANGE;
    try {auto mesh=std::make_shared<Mesh>();mesh->vertices.reserve(a->mesh->vertices.size()+b->mesh->vertices.size());mesh->triangles.reserve(a->mesh->triangles.size()+b->mesh->triangles.size());
        for(auto v:a->mesh->vertices)mesh->vertices.push_back(apply(world(a),v));for(auto v:b->mesh->vertices)mesh->vertices.push_back(apply(world(b),v));
        mesh->triangles=a->mesh->triangles;uint32_t offset=uint32_t(a->mesh->vertices.size());for(auto i:b->mesh->triangles)mesh->triangles.push_back(i+offset);
        return retain_mesh(a->scene,std::move(*mesh),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_weld(gx3de_object* o,double tolerance,gx3de_object** out) {
    if(!o||!out||!std::isfinite(tolerance)||tolerance<0)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    Mesh prepared;std::string error;if(!gx3de_backend::weld_mesh(*o->mesh,tolerance,prepared,error))return GX3DE_DEGENERATE;
    if(prepared.triangles.empty())return GX3DE_DEGENERATE;auto r=retain_mesh(o->scene,std::move(prepared),out);if(r==GX3DE_OK)(*out)->transform=world(o);return r;
}
gx3de_result gx3de_mesh_merge(gx3de_object* a,gx3de_object* b,double tolerance,gx3de_object** out) {
    if(!std::isfinite(tolerance)||tolerance<0||!out)return GX3DE_INVALID_ARGUMENT;
    gx3de_object* joined=nullptr;auto r=gx3de_mesh_append(a,b,&joined);if(r!=GX3DE_OK)return r;
    r=gx3de_mesh_weld(joined,tolerance,out);gx3de_object_destroy(joined);return r;
}
gx3de_result gx3de_mesh_stitch(gx3de_object* a,gx3de_object* b,double tolerance,gx3de_object** out) {
    if(!a||!b||!out||!std::isfinite(tolerance)||tolerance<0)return GX3DE_INVALID_ARGUMENT;
    if(a->scene!=b->scene)return GX3DE_WRONG_OWNER;if(!a->mesh||!b->mesh)return GX3DE_UNSUPPORTED;
    try {Mesh result;std::string error;
        if(!gx3de_backend::stitch_boundaries(placed_mesh(a),placed_mesh(b),tolerance,result,error))return GX3DE_DEGENERATE;
        return retain_mesh(a->scene,std::move(result),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_bridge(gx3de_object* a,gx3de_object* b,double max_gap,gx3de_object** out) {
    if(!a||!b||!out||!std::isfinite(max_gap)||max_gap<=0)return GX3DE_INVALID_ARGUMENT;
    if(a->scene!=b->scene)return GX3DE_WRONG_OWNER;if(!a->mesh||!b->mesh)return GX3DE_UNSUPPORTED;
    try {Mesh result;std::string error;
        if(!gx3de_backend::bridge_two_meshes(placed_mesh(a),placed_mesh(b),max_gap,result,error))return GX3DE_DEGENERATE;
        return retain_mesh(a->scene,std::move(result),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_heal_seam(gx3de_object* source,double max_gap,gx3de_object** out) {
    if(!source||!out||!std::isfinite(max_gap)||max_gap<=0)return GX3DE_INVALID_ARGUMENT;
    if(!source->mesh)return GX3DE_UNSUPPORTED;
    try {Mesh result;std::string error;
        if(!gx3de_backend::heal_one_mesh_seam(placed_mesh(source),max_gap,result,error))return GX3DE_DEGENERATE;
        return retain_mesh(source->scene,std::move(result),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_orient_normals(gx3de_object* o,gx3de_object** out) {
    if(!o||!out)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    Mesh result;std::string error;
    if(!gx3de_backend::orient_normals(*o->mesh,result,error))return GX3DE_DEGENERATE;
    auto r=retain_mesh(o->scene,std::move(result),out);if(r==GX3DE_OK)(*out)->transform=world(o);return r;
}
gx3de_result gx3de_mesh_self_intersections(gx3de_object* o,double tolerance,uint64_t* count) {
    if(!o||!count||!std::isfinite(tolerance)||tolerance<0)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {std::string error;uint64_t found=0;
        if(!gx3de_backend::mesh_self_intersections(placed_mesh(o),tolerance,found,error))return GX3DE_DEGENERATE;
        *count=found;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_intersection_pairs(gx3de_object* o,double tolerance,
        gx3de_mesh_intersection_pair* pairs,uint64_t capacity,uint64_t* required) {
    if(!o||!required||!std::isfinite(tolerance)||tolerance<0||capacity>1000000||
       (capacity&&!pairs))return GX3DE_INVALID_ARGUMENT;
    if(!o->mesh)return GX3DE_UNSUPPORTED;
    for(uint64_t i=0;i<capacity;++i)
        if(pairs[i].struct_size<sizeof(gx3de_mesh_intersection_pair))return GX3DE_RANGE;
    try {
        std::vector<gx3de_backend::MeshIntersectionHit> found;
        std::string error;uint64_t total=0;
        if(!gx3de_backend::mesh_self_intersection_details(placed_mesh(o),tolerance,
                capacity,found,total,error))return GX3DE_DEGENERATE;
        for(size_t i=0;i<found.size();++i)
            pairs[i]={sizeof(gx3de_mesh_intersection_pair),0,found[i].triangle_a,
                      found[i].triangle_b,found[i].witness,{}};
        *required=total;
        return total>capacity?GX3DE_RANGE:GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_clean_duplicates(gx3de_object* o,gx3de_object** out) {return gx3de_mesh_weld(o,0.0,out);}
gx3de_result gx3de_object_project_mesh(gx3de_object* o,gx3de_plane* plane,gx3de_object** out) {
    if(!o||!plane||!out)return GX3DE_INVALID_ARGUMENT;if(o->scene!=plane->scene)return GX3DE_WRONG_OWNER;if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {Mesh projected;projected.vertices.reserve(o->mesh->vertices.size());projected.triangles=o->mesh->triangles;
        for(auto p:o->mesh->vertices){p=apply(world(o),p);projected.vertices.push_back(sub(p,mul(plane->n,dot(sub(p,plane->origin),plane->n))));}
        auto status=retain_mesh(o->scene,std::move(projected),out);
        if(status==GX3DE_OK){(*out)->projection_source=o;(*out)->projection_plane=plane;
            (*out)->source_sha256=o->source_sha256;}
        return status;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_project(gx3de_object* source,gx3de_plane* plane,
    const gx3de_brep_mesh_spec* tessellation,gx3de_object** out) {
    if(!source||!plane||!out)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(source->scene!=plane->scene)return GX3DE_WRONG_OWNER;
    if(source->mesh)return tessellation?GX3DE_INVALID_ARGUMENT:
        gx3de_object_project_mesh(source,plane,out);
#ifdef GX3DE_WITH_OCCT
    if(source->brep){
        if(!tessellation)return GX3DE_INVALID_ARGUMENT;
        gx3de_object* temporary=nullptr;
        auto rc=gx3de_object_brep_mesh_create(source,tessellation,&temporary);
        if(rc!=GX3DE_OK)return rc;
        rc=gx3de_object_project_mesh(temporary,plane,out);
        if(rc==GX3DE_OK){(*out)->projection_source=source;
            (*out)->source_sha256=source->source_sha256;
            (*out)->projection_tessellation=*tessellation;
            (*out)->projection_uses_tessellation=true;}
        gx3de_object_destroy(temporary);
        return rc;
    }
#endif
    if(!source->scientific)return GX3DE_UNSUPPORTED;
    if(tessellation)return GX3DE_INVALID_ARGUMENT;
    try {
        vtkNew<vtkGeometryFilter> surface;
        surface->SetInputData(source->scientific->dataset);
        surface->Update();
        auto* input=surface->GetOutput();
        if(!input||input->GetNumberOfPoints()<1)return GX3DE_NOT_FOUND;
        if(input->GetNumberOfPoints()>1000000)return GX3DE_RANGE;
        vtkNew<vtkPolyData> projected;
        projected->ShallowCopy(input);
        vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
        points->SetNumberOfPoints(input->GetNumberOfPoints());
        const auto pose=world(source);
        for(vtkIdType i=0;i<input->GetNumberOfPoints();++i){
            double xyz[3];input->GetPoint(i,xyz);
            const auto p=apply(pose,{xyz[0],xyz[1],xyz[2]});
            const auto q=sub(p,mul(plane->n,dot(sub(p,plane->origin),plane->n)));
            points->SetPoint(i,q.x,q.y,q.z);
        }
        projected->SetPoints(points);
        gx3de_backend::ScientificData data{};
        data.dataset=projected;
        data.format=gx3de_backend::ScientificFormat::InMemoryPolydata;
        data.source_sha256_hex=source->source_sha256;
        data.fingerprint_sha256_hex=projection_fingerprint(source,plane);
        if(data.fingerprint_sha256_hex.size()!=64)return GX3DE_OUT_OF_MEMORY;
        auto rc=retain_scientific(source->scene,std::move(data),out);
        if(rc==GX3DE_OK){
            (*out)->projection_source=source;(*out)->projection_plane=plane;
            (*out)->field_roles=source->field_roles;
            (*out)->presentation=source->presentation;
            (*out)->style=source->style;
            (*out)->opacity=source->opacity;
        }
        return rc;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_projection_source(gx3de_object* projection,
    gx3de_object** source,gx3de_plane** plane) {
    if(!projection||!source||!plane)return GX3DE_INVALID_ARGUMENT;
    if(!projection->projection_source||!projection->projection_plane)return GX3DE_NOT_FOUND;
    *source=projection->projection_source;*plane=projection->projection_plane;return GX3DE_OK;
}
gx3de_result gx3de_object_projection_refresh(gx3de_object* projection) {
    if(!projection)return GX3DE_INVALID_ARGUMENT;
    if(!projection->projection_source||!projection->projection_plane)return GX3DE_NOT_FOUND;
    gx3de_object* fresh=nullptr;
    auto result=gx3de_object_project(projection->projection_source,
        projection->projection_plane,projection->projection_uses_tessellation?
            &projection->projection_tessellation:nullptr,&fresh);
    if(result!=GX3DE_OK)return result;
    projection->mesh=fresh->mesh;projection->fingerprint=fresh->fingerprint;
    projection->scientific=fresh->scientific;
    projection->source_sha256=fresh->source_sha256;
    gx3de_object_destroy(fresh);return GX3DE_OK;
}
gx3de_result gx3de_mesh_clip(gx3de_object* o,gx3de_plane* plane,uint32_t keep_positive,gx3de_object** out) {
    if(!o||!plane||!out||keep_positive>1)return GX3DE_INVALID_ARGUMENT;
    if(o->scene!=plane->scene)return GX3DE_WRONG_OWNER;
    if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {
        std::vector<gx3de_vec3> placed;placed.reserve(o->mesh->vertices.size());
        for(auto vertex:o->mesh->vertices)placed.push_back(apply(world(o),vertex));
        Mesh clipped;std::string error;
        if(!gx3de_backend::vtk_clip_mesh(placed,o->mesh->triangles,plane->origin,plane->n,keep_positive!=0,clipped,error))return GX3DE_DEGENERATE;
        if(clipped.triangles.empty())return GX3DE_NOT_FOUND;
        return retain_mesh(o->scene,std::move(clipped),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_mesh_clip_capped(gx3de_object* o,gx3de_plane* plane,uint32_t keep_positive,double tolerance,gx3de_object** out) {
    if(!o||!plane||!out||keep_positive>1||!std::isfinite(tolerance)||tolerance<=0)return GX3DE_INVALID_ARGUMENT;
    if(o->scene!=plane->scene)return GX3DE_WRONG_OWNER;
    if(!o->mesh)return GX3DE_UNSUPPORTED;
    try {
        Mesh placed;placed.vertices.reserve(o->mesh->vertices.size());
        for(auto vertex:o->mesh->vertices)placed.vertices.push_back(apply(world(o),vertex));
        placed.triangles=o->mesh->triangles;
        Mesh clipped;std::string error;
        auto result=gx3de_backend::capped_clip_mesh(placed,plane->origin,plane->n,plane->u,plane->v,
                                                    keep_positive!=0,tolerance,clipped,error);
        if(result!=GX3DE_OK)return result;
        return retain_mesh(o->scene,std::move(clipped),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_geometry_fingerprint(gx3de_object* o,char out[65]) {
    if(!o||!out)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(o->brep){std::string digest,error;
        if(!gx3de_backend::shape_fingerprint(*o->brep,o->scene->engine->cache_namespace,digest,error))
            return error=="B-Rep serialization exceeded 256 MiB"?GX3DE_RANGE:GX3DE_DEGENERATE;
        std::memcpy(out,digest.c_str(),65);return GX3DE_OK;}
#endif
    if(!o->mesh&&!o->scientific)return GX3DE_UNSUPPORTED;
    if(o->fingerprint.size()!=64)return GX3DE_DEGENERATE;
    std::memcpy(out,o->fingerprint.c_str(),65);return GX3DE_OK;
}
gx3de_result gx3de_object_create_brep_box(gx3de_scene* s,gx3de_vec3 lengths,gx3de_object** out) {
    if(!s||!out||!finite(lengths)||lengths.x<=0||lengths.y<=0||lengths.z<=0)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    try {std::shared_ptr<gx3de_backend::BrepShape> shape;std::string error;if(!gx3de_backend::create_box(lengths.x,lengths.y,lengths.z,shape,error))return GX3DE_DEGENERATE;
        auto o=new gx3de_object{s,nullptr,identity()};o->brep=std::move(shape);return retain(s->objects,o,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_object_create_brep_cylinder(gx3de_scene* s,double radius,double height,gx3de_object** out) {
    if(!s||!out||!std::isfinite(radius)||!std::isfinite(height)||radius<=0||height<=0)
        return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    try {std::shared_ptr<gx3de_backend::BrepShape> shape;std::string error;
        if(!gx3de_backend::create_cylinder(radius,height,shape,error))return GX3DE_DEGENERATE;
        auto o=new gx3de_object{s,nullptr,identity()};o->brep=std::move(shape);
        return retain(s->objects,o,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_boolean(gx3de_object* a,gx3de_object* b,gx3de_boolean_kind kind,gx3de_object** out) {
    if(!a||!b||!out||kind<GX3DE_BOOLEAN_UNION||kind>GX3DE_BOOLEAN_DIFFERENCE)return GX3DE_INVALID_ARGUMENT;if(a->scene!=b->scene)return GX3DE_WRONG_OWNER;
#ifdef GX3DE_WITH_OCCT
    if(!a->brep||!b->brep)return GX3DE_UNSUPPORTED;
    try {std::string error;std::shared_ptr<gx3de_backend::BrepShape> wa,wb,result;
        if(!similarity_transform(world(a))||!similarity_transform(world(b)))return GX3DE_UNSUPPORTED;
        if(!gx3de_backend::transformed(*a->brep,world(a),wa,error)||!gx3de_backend::transformed(*b->brep,world(b),wb,error))return GX3DE_DEGENERATE;
        if(!gx3de_backend::boolean_op(*wa,*wb,int(kind),result,error))return GX3DE_DEGENERATE;
        auto o=new gx3de_object{a->scene,nullptr,identity()};o->brep=std::move(result);return retain(a->scene->objects,o,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_diagnose(gx3de_object* o,gx3de_brep_diagnostics* out) {
    if(!o||!out||out->struct_size<sizeof(gx3de_brep_diagnostics))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;std::shared_ptr<gx3de_backend::BrepShape> shape;std::string error;
    if(!gx3de_backend::transformed(*o->brep,world(o),shape,error))return GX3DE_DEGENERATE;
    double area,volume;if(!gx3de_backend::properties(*shape,area,volume))return GX3DE_DEGENERATE;
    *out={sizeof(gx3de_brep_diagnostics),uint32_t(std::isfinite(volume)),area,std::isfinite(volume)?std::abs(volume):0.0,{}};return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_validate(gx3de_object* o,gx3de_brep_validation* out) {
    if(!o||!out||out->struct_size<sizeof(gx3de_brep_validation))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;
    gx3de_backend::BrepValidation result{};std::string error;
    if(!gx3de_backend::validate(*o->brep,result,error))return GX3DE_DEGENERATE;
    *out={sizeof(gx3de_brep_validation),uint32_t(result.topology_valid),
          uint32_t(result.closed_oriented_solids),0,result.solids,result.shells,
          result.faces,{}};
    return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_heal(gx3de_object* o,double tolerance,gx3de_object** out) {
    if(!o||!out||!std::isfinite(tolerance)||tolerance<=0)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;
    try {std::shared_ptr<gx3de_backend::BrepShape> healed;std::string error;
        if(!gx3de_backend::heal_solid(*o->brep,tolerance,healed,error))return GX3DE_UNSUPPORTED;
        auto* created=new gx3de_object{o->scene,nullptr,world(o)};
        created->brep=std::move(healed);created->source_sha256=o->source_sha256;
        return retain(o->scene->objects,created,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_clip(gx3de_object* o,gx3de_plane* p,uint32_t positive,gx3de_object** out) {
    if(!o||!p||!out||positive>1)return GX3DE_INVALID_ARGUMENT;if(o->scene!=p->scene)return GX3DE_WRONG_OWNER;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;if(!similarity_transform(world(o)))return GX3DE_UNSUPPORTED;
    try {std::shared_ptr<gx3de_backend::BrepShape> placed,result;std::string error;
        if(!gx3de_backend::transformed(*o->brep,world(o),placed,error))return GX3DE_DEGENERATE;
        if(!gx3de_backend::clip_halfspace(*placed,p->origin,p->n,positive!=0,result,error))return GX3DE_DEGENERATE;
        if(!result)return GX3DE_NOT_FOUND;
        auto created=new gx3de_object{o->scene,nullptr,identity()};created->brep=std::move(result);
        return retain(o->scene->objects,created,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_topology_counts(gx3de_object* o,gx3de_brep_topology* out) {
    if(!o||!out||out->struct_size<sizeof(gx3de_brep_topology))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;gx3de_backend::BrepTopologyCounts counts{};
    if(!gx3de_backend::topology_counts(*o->brep,counts))return GX3DE_DEGENERATE;
    *out={sizeof(gx3de_brep_topology),0,counts.vertices,counts.edges,counts.faces,{}};return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_edge_geometry_get(gx3de_object* o,uint64_t index,double tolerance,gx3de_brep_edge_geometry* out) {
    if(!o||!out||out->struct_size<sizeof(*out)||!std::isfinite(tolerance)||tolerance<=0)
        return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;
    gx3de_backend::BrepTopologyCounts counts{};
    if(!gx3de_backend::topology_counts(*o->brep,counts))return GX3DE_DEGENERATE;
    if(index>=counts.edges)return GX3DE_RANGE;
    gx3de_brep_edge_geometry result{};std::string error;
    if(!gx3de_backend::edge_geometry(*o->brep,index+1,tolerance,result,error))
        return GX3DE_DEGENERATE;
    *out=result;return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_face_geometry_get(gx3de_object* o,uint64_t index,gx3de_brep_face_geometry* out) {
    if(!o||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;
    gx3de_backend::BrepTopologyCounts counts{};
    if(!gx3de_backend::topology_counts(*o->brep,counts))return GX3DE_DEGENERATE;
    if(index>=counts.faces)return GX3DE_RANGE;
    gx3de_brep_face_geometry result{};std::string error;
    if(!gx3de_backend::face_geometry(*o->brep,index+1,result,error))
        return GX3DE_DEGENERATE;
    *out=result;return GX3DE_OK;
#else
    return GX3DE_UNSUPPORTED;
#endif
}
static gx3de_result plane_make(gx3de_scene* s,gx3de_vec3 origin,gx3de_vec3 n,gx3de_vec3 u,gx3de_plane** out) { if(!s||!out||!finite(origin)||!finite(n)||!finite(u))return GX3DE_INVALID_ARGUMENT;double nl=length(n);if(nl<1e-12)return GX3DE_DEGENERATE;n=mul(n,1/nl);u=sub(u,mul(n,dot(u,n)));double ul=length(u);if(ul<1e-12)return GX3DE_DEGENERATE;u=mul(u,1/ul);auto p=new(std::nothrow) gx3de_plane{s,origin,n,u,cross(n,u)};return retain(s->planes,p,out); }
gx3de_result gx3de_plane_create(gx3de_scene* s,gx3de_vec3 origin,gx3de_vec3 n,gx3de_vec3 u,gx3de_plane** out) { return plane_make(s,origin,n,u,out); }
gx3de_result gx3de_plane_from_points(gx3de_scene* s,gx3de_vec3 a,gx3de_vec3 b,gx3de_vec3 c,gx3de_plane** out) { return plane_make(s,a,cross(sub(b,a),sub(c,a)),sub(b,a),out); }
gx3de_result gx3de_plane_create_preset(gx3de_scene* s,gx3de_plane_preset preset,gx3de_vec3 origin,gx3de_plane** out) {
    switch(preset){case GX3DE_PLANE_XY:return plane_make(s,origin,{0,0,1},{1,0,0},out);
    case GX3DE_PLANE_XZ:return plane_make(s,origin,{0,-1,0},{1,0,0},out);
    case GX3DE_PLANE_YZ:return plane_make(s,origin,{1,0,0},{0,1,0},out);
    default:return GX3DE_INVALID_ARGUMENT;}
}
gx3de_result gx3de_plane_destroy(gx3de_plane* p) { if(!p)return GX3DE_INVALID_ARGUMENT;
    for(auto v:p->scene->views){
        for(size_t i=0;i<v->plane_manipulations.size();)if(v->plane_manipulations[i]->plane==p)
            gx3de_view_manipulation_end(v->plane_manipulations[i],0);else ++i;
        if(v->working_plane==p)v->working_plane=nullptr;}
    for(auto m:p->scene->measurements){if(m->plane==p)m->plane=nullptr;if(m->plane2==p)m->plane2=nullptr;}
    for(auto c:p->scene->constraints)if(c->spec.plane==p)c->spec.plane=nullptr;
    for(auto s:p->scene->sections)if(s->plane==p)s->plane=nullptr;
    for(auto o:p->scene->objects)if(o->projection_plane==p)o->projection_plane=nullptr;
    erase_ptr(p->scene->planes,p);delete p;return GX3DE_OK; }
gx3de_result gx3de_plane_get(gx3de_plane* p,gx3de_vec3* origin,gx3de_vec3* normal,gx3de_vec3* u_axis){
    if(!p||!origin||!normal||!u_axis)return GX3DE_INVALID_ARGUMENT;
    *origin=p->origin;*normal=p->n;*u_axis=p->u;return GX3DE_OK;}
gx3de_result gx3de_plane_set(gx3de_plane* p,gx3de_vec3 origin,gx3de_vec3 normal,gx3de_vec3 u_axis){
    if(!p||!finite(origin)||!finite(normal)||!finite(u_axis))return GX3DE_INVALID_ARGUMENT;
    double nl=length(normal);if(nl<1e-12)return GX3DE_DEGENERATE;
    normal=mul(normal,1/nl);u_axis=sub(u_axis,mul(normal,dot(u_axis,normal)));
    double ul=length(u_axis);if(ul<1e-12)return GX3DE_DEGENERATE;
    u_axis=mul(u_axis,1/ul);
    p->origin=origin;p->n=normal;p->u=u_axis;p->v=cross(normal,u_axis);
    return GX3DE_OK;}
gx3de_result gx3de_plane_coordinates(gx3de_plane* p,gx3de_vec3 w,gx3de_vec3* out) { if(!p||!out||!finite(w))return GX3DE_INVALID_ARGUMENT;auto d=sub(w,p->origin);*out={dot(d,p->u),dot(d,p->v),dot(d,p->n)};return GX3DE_OK; }
gx3de_result gx3de_plane_world(gx3de_plane* p,gx3de_vec3 uvw,gx3de_vec3* out) { if(!p||!out||!finite(uvw))return GX3DE_INVALID_ARGUMENT;*out=add(p->origin,add(mul(p->u,uvw.x),add(mul(p->v,uvw.y),mul(p->n,uvw.z))));return GX3DE_OK; }
gx3de_result gx3de_plane_project_point(gx3de_plane* p,gx3de_vec3 a,gx3de_vec3* out) { if(!p||!out||!finite(a))return GX3DE_INVALID_ARGUMENT;*out=sub(a,mul(p->n,dot(sub(a,p->origin),p->n)));return GX3DE_OK; }
gx3de_result gx3de_plane_project_vector(gx3de_plane* p,gx3de_vec3 a,gx3de_vec3* out) { if(!p||!out||!finite(a))return GX3DE_INVALID_ARGUMENT;*out=sub(a,mul(p->n,dot(a,p->n)));return GX3DE_OK; }
gx3de_result gx3de_section_create(gx3de_object* o,gx3de_plane* p,gx3de_section** out) {
    if(!o||!p||!out)return GX3DE_INVALID_ARGUMENT;if(o->scene!=p->scene)return GX3DE_WRONG_OWNER;
    try {std::vector<gx3de_segment3> segments;std::string error;
        if(o->mesh){std::vector<gx3de_vec3> points;points.reserve(o->mesh->vertices.size());for(auto v:o->mesh->vertices)points.push_back(apply(world(o),v));
            std::vector<gx3de_backend::Segment> found;if(!gx3de_backend::vtk_section(points,o->mesh->triangles,p->origin,p->n,found,error))return GX3DE_DEGENERATE;
            segments.reserve(found.size());for(auto seg:found)segments.push_back({seg.a,seg.b});}
#ifdef GX3DE_WITH_OCCT
        else if(o->brep){std::shared_ptr<gx3de_backend::BrepShape> shape;if(!gx3de_backend::transformed(*o->brep,world(o),shape,error))return GX3DE_DEGENERATE;
            std::vector<gx3de_backend::BrepSegment> found;if(!gx3de_backend::section(*shape,p->origin,p->n,found,error))return GX3DE_DEGENERATE;
            segments.reserve(found.size());for(auto seg:found)segments.push_back({seg.a,seg.b});}
#endif
        else return GX3DE_UNSUPPORTED;
        auto section=new gx3de_section{o->scene,std::move(segments),p->origin,p->u,p->v};
        section->source=o;section->plane=p;return retain(o->scene->sections,section,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_section_count(gx3de_section* s,uint64_t* out) {if(!s||!out)return GX3DE_INVALID_ARGUMENT;*out=s->segments.size();return GX3DE_OK;}
gx3de_result gx3de_section_segment(gx3de_section* s,uint64_t i,gx3de_segment3* out) {if(!s||!out)return GX3DE_INVALID_ARGUMENT;if(i>=s->segments.size())return GX3DE_RANGE;*out=s->segments[i];return GX3DE_OK;}
gx3de_result gx3de_section_profile_segment(gx3de_section* s,uint64_t i,gx3de_segment2* out) {if(!s||!out)return GX3DE_INVALID_ARGUMENT;if(i>=s->segments.size())return GX3DE_RANGE;auto seg=s->segments[i];auto a=sub(seg.a,s->origin),b=sub(seg.b,s->origin);*out={dot(a,s->u),dot(a,s->v),dot(b,s->u),dot(b,s->v)};return GX3DE_OK;}
gx3de_result gx3de_section_destroy(gx3de_section* s) {if(!s)return GX3DE_INVALID_ARGUMENT;
    for(auto p:s->scene->profiles)if(p->source==s)p->source=nullptr;
    erase_ptr(s->scene->sections,s);delete s;return GX3DE_OK;}
gx3de_result gx3de_section_source(gx3de_section* s,gx3de_object** object,gx3de_plane** plane) {
    if(!s||!object||!plane)return GX3DE_INVALID_ARGUMENT;
    if(!s->source||!s->plane)return GX3DE_NOT_FOUND;
    *object=s->source;*plane=s->plane;return GX3DE_OK;
}
gx3de_result gx3de_section_refresh(gx3de_section* s) {
    if(!s)return GX3DE_INVALID_ARGUMENT;
    if(!s->source||!s->plane)return GX3DE_NOT_FOUND;
    gx3de_section* fresh=nullptr;auto rc=gx3de_section_create(s->source,s->plane,&fresh);
    if(rc!=GX3DE_OK)return rc;
    s->segments.swap(fresh->segments);s->origin=fresh->origin;s->u=fresh->u;s->v=fresh->v;
    gx3de_section_destroy(fresh);return GX3DE_OK;
}
static bool renderer_valid_curve_style(const gx3de_curve_style* s) {
    return s&&s->struct_size>=sizeof(*s)&&s->visible<=1&&renderer_valid_rgb(s->color)&&
        std::isfinite(s->line_width)&&s->line_width>0&&s->line_width<=64&&
        std::isfinite(s->opacity)&&s->opacity>=0&&s->opacity<=1;
}
gx3de_result gx3de_section_style_set(gx3de_section* s,const gx3de_curve_style* style) {
    if(!s||!renderer_valid_curve_style(style))return GX3DE_INVALID_ARGUMENT;
    s->style=*style;s->style.struct_size=sizeof(*style);return GX3DE_OK;
}
gx3de_result gx3de_section_style_get(gx3de_section* s,gx3de_curve_style* style) {
    if(!s||!style||style->struct_size<sizeof(*style))return GX3DE_INVALID_ARGUMENT;
    *style=s->style;return GX3DE_OK;
}
gx3de_result gx3de_profile_create(gx3de_section* s,double tolerance,gx3de_profile** out) {
    if(!s||!out||!std::isfinite(tolerance)||tolerance<=0)return GX3DE_INVALID_ARGUMENT;
    try {std::vector<gx3de_backend::ProfileContour> contours;std::string error;
        if(!gx3de_backend::chain_section(s->segments,s->origin,s->u,s->v,tolerance,contours,error))return GX3DE_DEGENERATE;
        auto p=new gx3de_profile{s->scene,std::move(contours),s->origin,s->u,s->v};
        p->source=s;p->join_tolerance=tolerance;return retain(s->scene->profiles,p,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_profile_create_contours(gx3de_scene* scene,gx3de_plane* plane,const gx3de_profile_contour_spec* inputs,uint64_t count,double tolerance,gx3de_profile** out){
    if(!scene||!plane||!inputs||!out||!count||count>4096||!std::isfinite(tolerance)||tolerance<=0)return GX3DE_INVALID_ARGUMENT;
    if(plane->scene!=scene)return GX3DE_WRONG_OWNER;
    try {
        std::vector<gx3de_backend::ProfileContour> contours;std::string error;
        if(!gx3de_backend::input_contours(inputs,count,plane->origin,plane->u,plane->v,tolerance,contours,error))return GX3DE_DEGENERATE;
        auto profile=new gx3de_profile{scene,std::move(contours),plane->origin,plane->u,plane->v};
        profile->join_tolerance=tolerance;return retain(scene->profiles,profile,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_profile_frame_get(gx3de_profile* profile,gx3de_vec3* origin,gx3de_vec3* normal,gx3de_vec3* u_axis){
    if(!profile||!origin||!normal||!u_axis)return GX3DE_INVALID_ARGUMENT;
    *origin=profile->origin;*normal=cross(profile->u,profile->v);*u_axis=profile->u;return GX3DE_OK;
}
gx3de_result gx3de_profile_rescale(gx3de_profile* source,double factor,gx3de_profile** out){
    if(!source||!out||!std::isfinite(factor)||factor<=0)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(!finite(mul(source->origin,factor))||!std::isfinite(source->join_tolerance*factor)||source->join_tolerance*factor<=0)return GX3DE_RANGE;
    for(const auto& contour:source->contours){if(!std::isfinite(contour.length*factor)||!std::isfinite(contour.area*factor*factor))return GX3DE_RANGE;
        for(auto point:contour.points)if(!finite(mul(point,factor)))return GX3DE_RANGE;}
    try {
        std::unique_ptr<gx3de_profile> profile(new gx3de_profile(*source));profile->source=nullptr;profile->origin=mul(profile->origin,factor);profile->join_tolerance*=factor;
        for(auto& contour:profile->contours){contour.length*=factor;contour.area*=factor*factor;for(auto& point:contour.points)point=mul(point,factor);}
        return retain(source->scene->profiles,profile.release(),out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_profile_write_vtp(gx3de_profile* profile,const char* path){
    if(!profile||!path||!*path)return GX3DE_INVALID_ARGUMENT;
    try {
        std::error_code error;if(std::filesystem::exists(std::filesystem::u8path(path),error)||error)return GX3DE_INVALID_ARGUMENT;
        uint64_t total=0;for(const auto& contour:profile->contours){if(contour.points.size()<2||contour.points.size()>1000000||total>1000000-contour.points.size())return GX3DE_RANGE;total+=contour.points.size();}
        if(profile->contours.size()>4096||total==0)return GX3DE_RANGE;
        vtkNew<vtkPoints> points;points->SetDataTypeToDouble();vtkNew<vtkCellArray> lines;
        for(const auto& contour:profile->contours){std::vector<vtkIdType> indices;indices.reserve(contour.points.size()+1);
            for(auto point:contour.points){if(!finite(point))return GX3DE_DEGENERATE;indices.push_back(points->InsertNextPoint(point.x,point.y,point.z));}
            if(contour.closed)indices.push_back(indices.front());lines->InsertNextCell(static_cast<vtkIdType>(indices.size()),indices.data());
        }
        vtkNew<vtkPolyData> data;data->SetPoints(points);data->SetLines(lines);
        vtkNew<vtkDoubleArray> logical;logical->SetName("logical_cell_id");logical->SetNumberOfComponents(1);for(size_t i=0;i<profile->contours.size();++i)logical->InsertNextValue(double(i));data->GetCellData()->AddArray(logical);
        vtkNew<vtkXMLPolyDataWriter> writer;writer->SetDataModeToAppended();writer->SetFileName(path);writer->SetInputData(data);
        if(!writer->Write()||writer->GetErrorCode())return GX3DE_DEGENERATE;
        if(!std::filesystem::is_regular_file(std::filesystem::u8path(path),error)||error||std::filesystem::file_size(std::filesystem::u8path(path),error)==0||error)return GX3DE_DEGENERATE;
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_profile_extrude(gx3de_profile* profile,double height,gx3de_object** out){
    if(!profile||!out||!std::isfinite(height)||height==0)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    try {
        std::shared_ptr<gx3de_backend::BrepShape> shape;std::string error;
        if(!gx3de_backend::extrude_profile(profile->contours,profile->origin,profile->u,profile->v,height,shape,error))return GX3DE_DEGENERATE;
        auto object=new gx3de_object{profile->scene,nullptr,identity()};object->brep=std::move(shape);
        return retain(profile->scene->objects,object,out);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_brep_write_step(gx3de_object* object,const char* path,double millimeters_per_unit){
    if(!object||!path||!*path||!std::isfinite(millimeters_per_unit)||millimeters_per_unit<=0)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!object->brep)return GX3DE_UNSUPPORTED;
    try {
        std::error_code ec;if(std::filesystem::exists(std::filesystem::u8path(path),ec)||ec)return GX3DE_INVALID_ARGUMENT;
        std::shared_ptr<gx3de_backend::BrepShape> shape;std::string error;
        if(!gx3de_backend::transformed(*object->brep,world(object),shape,error)||!gx3de_backend::write_step(*shape,path,millimeters_per_unit,error))return GX3DE_DEGENERATE;
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
     catch(const std::exception&){return GX3DE_DEGENERATE;}
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_scientific_write_vtp(gx3de_object* object,const char* path){
 if(!object||!path||!*path)return GX3DE_INVALID_ARGUMENT;
 if(!object->scientific)return GX3DE_UNSUPPORTED;
 auto* original=vtkPolyData::SafeDownCast(object->scientific->dataset);if(!original)return GX3DE_UNSUPPORTED;
 try {
  std::error_code ec;if(std::filesystem::exists(std::filesystem::u8path(path),ec)||ec)return GX3DE_INVALID_ARGUMENT;
  vtkNew<vtkPolyData> data;data->DeepCopy(original);vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
  auto transform=world(object);for(vtkIdType i=0;i<original->GetNumberOfPoints();++i){double p[3];original->GetPoint(i,p);auto q=apply(transform,{p[0],p[1],p[2]});if(!finite(q))return GX3DE_DEGENERATE;points->InsertNextPoint(q.x,q.y,q.z);}data->SetPoints(points);
  vtkNew<vtkXMLPolyDataWriter> writer;writer->SetDataModeToAppended();writer->SetFileName(path);writer->SetInputData(data);
  if(!writer->Write()||writer->GetErrorCode()){std::filesystem::remove(std::filesystem::u8path(path),ec);return GX3DE_DEGENERATE;}return GX3DE_OK;
 }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_mesh_write_file(gx3de_object* object,uint32_t format,const char* path){
    if(!object||!path||!*path||(format!=1&&format!=2))return GX3DE_INVALID_ARGUMENT;
    if(!object->mesh)return GX3DE_UNSUPPORTED;
    try {
        std::error_code ec;if(std::filesystem::exists(std::filesystem::u8path(path),ec)||ec)return GX3DE_INVALID_ARGUMENT;
        auto mesh=placed_mesh(object);
        vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
        for(auto p:mesh.vertices){if(!finite(p))return GX3DE_DEGENERATE;points->InsertNextPoint(p.x,p.y,p.z);}
        vtkNew<vtkCellArray> cells;
        for(size_t i=0;i<mesh.triangles.size();i+=3){vtkIdType indices[3]={mesh.triangles[i],mesh.triangles[i+1],mesh.triangles[i+2]};cells->InsertNextCell(3,indices);}
        vtkNew<vtkPolyData> data;data->SetPoints(points);data->SetPolys(cells);
        if(format==1){vtkNew<vtkSTLWriter> writer;writer->SetFileTypeToBinary();writer->SetFileName(path);writer->SetInputData(data);writer->Write();if(writer->GetErrorCode())return GX3DE_DEGENERATE;}
        else {vtkNew<vtkXMLPolyDataWriter> writer;writer->SetDataModeToAppended();writer->SetFileName(path);writer->SetInputData(data);if(!writer->Write()||writer->GetErrorCode())return GX3DE_DEGENERATE;}
        if(!std::filesystem::is_regular_file(std::filesystem::u8path(path),ec)||ec||std::filesystem::file_size(std::filesystem::u8path(path),ec)==0||ec)return GX3DE_DEGENERATE;
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
     catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_profile_contour_count(gx3de_profile* p,uint64_t* out) {if(!p||!out)return GX3DE_INVALID_ARGUMENT;*out=p->contours.size();return GX3DE_OK;}
gx3de_result gx3de_profile_contour_info(gx3de_profile* p,uint64_t i,gx3de_contour_info* out) {if(!p||!out||out->struct_size<sizeof(gx3de_contour_info))return GX3DE_INVALID_ARGUMENT;if(i>=p->contours.size())return GX3DE_RANGE;auto& c=p->contours[i];*out={sizeof(gx3de_contour_info),uint32_t(c.closed),c.points.size(),c.length,c.area,{}};return GX3DE_OK;}
gx3de_result gx3de_profile_point3(gx3de_profile* p,uint64_t i,uint64_t j,gx3de_vec3* out) {if(!p||!out)return GX3DE_INVALID_ARGUMENT;if(i>=p->contours.size()||j>=p->contours[i].points.size())return GX3DE_RANGE;*out=p->contours[i].points[j];return GX3DE_OK;}
gx3de_result gx3de_profile_point2(gx3de_profile* p,uint64_t i,uint64_t j,double* u,double* v) {if(!p||!u||!v)return GX3DE_INVALID_ARGUMENT;if(i>=p->contours.size()||j>=p->contours[i].points.size())return GX3DE_RANGE;auto q=sub(p->contours[i].points[j],p->origin);*u=dot(q,p->u);*v=dot(q,p->v);return GX3DE_OK;}
gx3de_result gx3de_profile_destroy(gx3de_profile* p) {if(!p)return GX3DE_INVALID_ARGUMENT;erase_ptr(p->scene->profiles,p);delete p;return GX3DE_OK;}
gx3de_result gx3de_profile_source(gx3de_profile* p,gx3de_section** section) {
    if(!p||!section)return GX3DE_INVALID_ARGUMENT;
    if(!p->source)return GX3DE_NOT_FOUND;*section=p->source;return GX3DE_OK;
}
gx3de_result gx3de_profile_refresh(gx3de_profile* p) {
    if(!p)return GX3DE_INVALID_ARGUMENT;
    if(!p->source)return GX3DE_NOT_FOUND;
    gx3de_profile* fresh=nullptr;auto rc=gx3de_profile_create(p->source,p->join_tolerance,&fresh);
    if(rc!=GX3DE_OK)return rc;
    p->contours.swap(fresh->contours);p->origin=fresh->origin;p->u=fresh->u;p->v=fresh->v;
    gx3de_profile_destroy(fresh);return GX3DE_OK;
}
gx3de_result gx3de_profile_style_set(gx3de_profile* p,const gx3de_curve_style* style) {
    if(!p||!renderer_valid_curve_style(style))return GX3DE_INVALID_ARGUMENT;
    p->style=*style;p->style.struct_size=sizeof(*style);return GX3DE_OK;
}
gx3de_result gx3de_profile_style_get(gx3de_profile* p,gx3de_curve_style* style) {
    if(!p||!style||style->struct_size<sizeof(*style))return GX3DE_INVALID_ARGUMENT;
    *style=p->style;return GX3DE_OK;
}
gx3de_result gx3de_anchor_brep_vertex(gx3de_object* o,uint64_t index,gx3de_anchor** out) {
    if(!o||!out)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;gx3de_backend::BrepTopologyCounts counts{};
    if(!gx3de_backend::topology_counts(*o->brep,counts))return GX3DE_DEGENERATE;if(index>=counts.vertices)return GX3DE_RANGE;
    gx3de_vec3 point;std::string error;if(!gx3de_backend::vertex_anchor(*o->brep,index+1,point,error))return GX3DE_DEGENERATE;
    auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_BREP_VERTEX;a->triangle=index;return retain(o->scene->anchors,a,out);
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_anchor_brep_edge(gx3de_object* o,uint64_t index,double t,gx3de_anchor** out) {
    if(!o||!out||!std::isfinite(t)||t<0||t>1)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;gx3de_backend::BrepTopologyCounts counts{};
    if(!gx3de_backend::topology_counts(*o->brep,counts))return GX3DE_DEGENERATE;if(index>=counts.edges)return GX3DE_RANGE;
    gx3de_vec3 point,tangent;std::string error;if(!gx3de_backend::edge_anchor(*o->brep,index+1,t,point,tangent,error))return GX3DE_DEGENERATE;
    auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_BREP_EDGE;a->triangle=index;a->u=t;return retain(o->scene->anchors,a,out);
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_anchor_brep_face(gx3de_object* o,uint64_t index,double u,double v,gx3de_anchor** out) {
    if(!o||!out||!std::isfinite(u)||!std::isfinite(v)||u<0||u>1||v<0||v>1)return GX3DE_INVALID_ARGUMENT;
#ifdef GX3DE_WITH_OCCT
    if(!o->brep)return GX3DE_UNSUPPORTED;gx3de_backend::BrepTopologyCounts counts{};
    if(!gx3de_backend::topology_counts(*o->brep,counts))return GX3DE_DEGENERATE;if(index>=counts.faces)return GX3DE_RANGE;
    gx3de_backend::BrepFaceAnchor point;std::string error;if(!gx3de_backend::face_anchor(*o->brep,index+1,u,v,point,error))return GX3DE_DEGENERATE;
    auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_BREP_FACE;a->triangle=index;a->u=u;a->v=v;return retain(o->scene->anchors,a,out);
#else
    return GX3DE_UNSUPPORTED;
#endif
}
gx3de_result gx3de_anchor_free(gx3de_scene* s,gx3de_vec3 p,gx3de_anchor** out) { if(!s||!out||!finite(p))return GX3DE_INVALID_ARGUMENT;auto a=new(std::nothrow) gx3de_anchor{s,nullptr,0,p};return retain(s->anchors,a,out); }
gx3de_result gx3de_anchor_line(gx3de_scene* s,gx3de_vec3 point,gx3de_vec3 direction,gx3de_anchor** out) {
    if(!s||!out||!finite(point)||!finite(direction))return GX3DE_INVALID_ARGUMENT;
    double magnitude=length(direction);if(!(magnitude>1e-15))return GX3DE_DEGENERATE;
    auto a=new(std::nothrow) gx3de_anchor{s,nullptr,0,point};if(!a)return GX3DE_OUT_OF_MEMORY;
    a->kind=GX3DE_ANCHOR_LINE;a->local_direction=mul(direction,1/magnitude);return retain(s->anchors,a,out);
}
gx3de_result gx3de_anchor_object_axis(gx3de_object* o,gx3de_vec3 point,gx3de_vec3 direction,gx3de_anchor** out) {
    if(!o||!out||!finite(point)||!finite(direction))return GX3DE_INVALID_ARGUMENT;
    double magnitude=length(direction);if(!(magnitude>1e-15))return GX3DE_DEGENERATE;
    auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;
    a->kind=GX3DE_ANCHOR_OBJECT_AXIS;a->local_point=point;a->local_direction=mul(direction,1/magnitude);
    return retain(o->scene->anchors,a,out);
}
gx3de_result gx3de_anchor_object_reference(gx3de_object* o,gx3de_anchor** out) {
    if(!o||!out)return GX3DE_INVALID_ARGUMENT;
    auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;
    a->kind=GX3DE_ANCHOR_OBJECT_REFERENCE;return retain(o->scene->anchors,a,out);
}
gx3de_result gx3de_anchor_object_vertex(gx3de_object* o,uint64_t i,gx3de_anchor** out) { if(!o||!out)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;if(i>=o->mesh->vertices.size())return GX3DE_RANGE;auto a=new(std::nothrow) gx3de_anchor{o->scene,o,i,{}};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_VERTEX;return retain(o->scene->anchors,a,out); }
gx3de_result gx3de_anchor_object_point(gx3de_object* o,gx3de_vec3 local,gx3de_anchor** out) {if(!o||!out||!finite(local))return GX3DE_INVALID_ARGUMENT;auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_OBJECT_POINT;a->local_point=local;return retain(o->scene->anchors,a,out);}
gx3de_result gx3de_anchor_object_edge(gx3de_object* o,uint32_t i,uint32_t j,double t,gx3de_anchor** out) {if(!o||!out||!std::isfinite(t)||t<0||t>1)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;if(i==j||i>=o->mesh->vertices.size()||j>=o->mesh->vertices.size())return GX3DE_RANGE;
    bool found=false;const auto& triangles=o->mesh->triangles;for(size_t k=0;k<triangles.size();k+=3){uint32_t f[3]={triangles[k],triangles[k+1],triangles[k+2]};for(int z=0;z<3;++z)if((f[z]==i&&f[(z+1)%3]==j)||(f[z]==j&&f[(z+1)%3]==i)){found=true;break;}if(found)break;}if(!found)return GX3DE_NOT_FOUND;
    auto a=new(std::nothrow) gx3de_anchor{o->scene,o,i,{}};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_EDGE;a->vertex_b=j;a->u=t;return retain(o->scene->anchors,a,out);}
gx3de_result gx3de_anchor_object_face(gx3de_object* o,uint64_t triangle,double u,double v,gx3de_anchor** out) {if(!o||!out||!std::isfinite(u)||!std::isfinite(v)||u<0||v<0||u+v>1)return GX3DE_INVALID_ARGUMENT;if(!o->mesh)return GX3DE_UNSUPPORTED;if(triangle>=o->mesh->triangles.size()/3)return GX3DE_RANGE;auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_FACE;a->triangle=triangle;a->u=u;a->v=v;return retain(o->scene->anchors,a,out);}
gx3de_result gx3de_anchor_object_center(gx3de_object* o,gx3de_anchor** out) {if(!o||!out)return GX3DE_INVALID_ARGUMENT;gx3de_bounds b;auto r=gx3de_object_bounds(o,0,&b);if(r!=GX3DE_OK)return r;auto a=new(std::nothrow) gx3de_anchor{o->scene,o};if(!a)return GX3DE_OUT_OF_MEMORY;a->kind=GX3DE_ANCHOR_CENTER;a->local_point=mul(add(b.min,b.max),0.5);return retain(o->scene->anchors,a,out);}
gx3de_result gx3de_anchor_get_kind(gx3de_anchor* a,gx3de_anchor_kind* out) {if(!a||!out)return GX3DE_INVALID_ARGUMENT;*out=a->kind;return GX3DE_OK;}
gx3de_result gx3de_anchor_position(gx3de_anchor* a,gx3de_vec3* out) { if(!a||!out)return GX3DE_INVALID_ARGUMENT;if(!a->object){*out=a->free_point;return GX3DE_OK;}gx3de_vec3 local{};
    switch(a->kind){case GX3DE_ANCHOR_VERTEX:local=a->object->mesh->vertices[a->vertex];break;
    case GX3DE_ANCHOR_EDGE:{auto p=a->object->mesh->vertices[a->vertex],q=a->object->mesh->vertices[a->vertex_b];local=add(mul(p,1-a->u),mul(q,a->u));break;}
    case GX3DE_ANCHOR_FACE:{const auto& mesh=*a->object->mesh;size_t k=a->triangle*3;local=add(mul(mesh.vertices[mesh.triangles[k]],1-a->u-a->v),add(mul(mesh.vertices[mesh.triangles[k+1]],a->u),mul(mesh.vertices[mesh.triangles[k+2]],a->v)));break;}
#ifdef GX3DE_WITH_OCCT
    case GX3DE_ANCHOR_BREP_VERTEX:{std::string error;if(!a->object->brep||!gx3de_backend::vertex_anchor(*a->object->brep,a->triangle+1,local,error))return GX3DE_NOT_FOUND;break;}
    case GX3DE_ANCHOR_BREP_EDGE:{gx3de_vec3 tangent;std::string error;if(!a->object->brep||!gx3de_backend::edge_anchor(*a->object->brep,a->triangle+1,a->u,local,tangent,error))return GX3DE_NOT_FOUND;break;}
    case GX3DE_ANCHOR_BREP_FACE:{gx3de_backend::BrepFaceAnchor face;std::string error;if(!a->object->brep||!gx3de_backend::face_anchor(*a->object->brep,a->triangle+1,a->u,a->v,face,error))return GX3DE_NOT_FOUND;local=face.point;break;}
#endif
    default:local=a->local_point;break;}*out=apply(world(a->object),local);return GX3DE_OK;}
gx3de_result gx3de_anchor_normal(gx3de_anchor* a,gx3de_vec3* out) {
    if(!a||!out)return GX3DE_INVALID_ARGUMENT;if(!a->object)return GX3DE_UNSUPPORTED;
    if(a->kind==GX3DE_ANCHOR_FACE&&a->object->mesh){const auto& mesh=*a->object->mesh;size_t k=a->triangle*3;auto m=world(a->object);auto p=apply(m,mesh.vertices[mesh.triangles[k]]),q=apply(m,mesh.vertices[mesh.triangles[k+1]]),r=apply(m,mesh.vertices[mesh.triangles[k+2]]);auto n=cross(sub(q,p),sub(r,p));double len=length(n);if(len<1e-12)return GX3DE_DEGENERATE;*out=mul(n,1/len);return GX3DE_OK;}
#ifdef GX3DE_WITH_OCCT
    if(a->kind==GX3DE_ANCHOR_BREP_FACE&&a->object->brep){gx3de_backend::BrepFaceAnchor face;std::string error;
        if(!gx3de_backend::face_anchor(*a->object->brep,a->triangle+1,a->u,a->v,face,error))return GX3DE_NOT_FOUND;
        return transform_normal(world(a->object),face.normal,*out)?GX3DE_OK:GX3DE_DEGENERATE;}
#endif
    return GX3DE_UNSUPPORTED;
}
gx3de_result gx3de_anchor_tangent(gx3de_anchor* a,gx3de_vec3* out) {
    if(!a||!out)return GX3DE_INVALID_ARGUMENT;
    if(a->kind==GX3DE_ANCHOR_LINE){*out=a->local_direction;return GX3DE_OK;}
    if(a->kind==GX3DE_ANCHOR_OBJECT_AXIS&&a->object){
        const auto m=world(a->object);
        const auto d=a->local_direction;
        gx3de_vec3 transformed{m.m[0]*d.x+m.m[4]*d.y+m.m[8]*d.z,
            m.m[1]*d.x+m.m[5]*d.y+m.m[9]*d.z,m.m[2]*d.x+m.m[6]*d.y+m.m[10]*d.z};
        double magnitude=length(transformed);if(!(magnitude>1e-15)||!std::isfinite(magnitude))return GX3DE_DEGENERATE;
        *out=mul(transformed,1/magnitude);return GX3DE_OK;
    }
#ifdef GX3DE_WITH_OCCT
    if(a->kind==GX3DE_ANCHOR_BREP_EDGE&&a->object&&a->object->brep){gx3de_vec3 p,t;std::string error;
        if(!gx3de_backend::edge_anchor(*a->object->brep,a->triangle+1,a->u,p,t,error))return GX3DE_NOT_FOUND;
        auto m=world(a->object);gx3de_vec3 transformed{m.m[0]*t.x+m.m[4]*t.y+m.m[8]*t.z,m.m[1]*t.x+m.m[5]*t.y+m.m[9]*t.z,m.m[2]*t.x+m.m[6]*t.y+m.m[10]*t.z};
        double magnitude=length(transformed);if(!(magnitude>1e-15))return GX3DE_DEGENERATE;*out=mul(transformed,1/magnitude);return GX3DE_OK;}
#endif
    return GX3DE_UNSUPPORTED;
}
gx3de_result gx3de_anchor_destroy(gx3de_anchor* a) { if(!a)return GX3DE_INVALID_ARGUMENT;for(auto m:a->scene->measurements){if(m->a==a)m->a=nullptr;if(m->b==a)m->b=nullptr;if(m->c==a)m->c=nullptr;if(m->d==a)m->d=nullptr;}for(auto c:a->scene->constraints){if(c->spec.a==a)c->spec.a=nullptr;if(c->spec.b==a)c->spec.b=nullptr;for(auto& anchor:c->extended_spec.anchors)if(anchor==a)anchor=nullptr;}for(auto marker:a->scene->markers)if(marker->anchor==a)marker->anchor=nullptr;for(auto v:a->scene->views){if(v->selection==a)v->selection=nullptr;if(v->axes.reference_axis==a){v->axes.reference_axis=nullptr;v->axes.show_reference=0;}for(auto* gizmo:v->gizmos)if(gizmo->spec.anchor==a){gizmo->spec.anchor=nullptr;gizmo->spec.pivot_mode=GX3DE_GIZMO_PIVOT_OBJECT;}}erase_ptr(a->scene->anchors,a);delete a;return GX3DE_OK; }
static bool renderer_valid_marker_style(const gx3de_marker_style* s) {
    return s&&s->struct_size>=sizeof(*s)&&s->visible<=1&&
        s->kind>=GX3DE_MARKER_POINT&&s->kind<=GX3DE_MARKER_TANGENT&&
        s->highlighted<=1&&renderer_valid_rgb(s->color)&&
        std::isfinite(s->size_pixels)&&s->size_pixels>=1&&s->size_pixels<=128&&
        std::isfinite(s->line_width)&&s->line_width>0&&s->line_width<=64;
}
gx3de_result gx3de_marker_create_scene(gx3de_scene* scene,gx3de_anchor* anchor,
    const gx3de_marker_style* style,gx3de_marker** out) {
    if(!scene||!anchor||!out)return GX3DE_INVALID_ARGUMENT;
    if(anchor->scene!=scene)return GX3DE_WRONG_OWNER;
    const gx3de_marker_style fallback{sizeof(gx3de_marker_style),1,GX3DE_MARKER_POINT,0,
        {1.0,0.86,0.12},8.0,2.0,{}};
    if(!style)style=&fallback;
    if(!renderer_valid_marker_style(style))return GX3DE_INVALID_ARGUMENT;
    auto* marker=new(std::nothrow) gx3de_marker{scene,nullptr,anchor,*style};
    return retain(scene->markers,marker,out);
}
gx3de_result gx3de_marker_create_view(gx3de_view* view,gx3de_anchor* anchor,
    const gx3de_marker_style* style,gx3de_marker** out) {
    if(!view)return GX3DE_INVALID_ARGUMENT;
    auto rc=gx3de_marker_create_scene(view->scene,anchor,style,out);
    if(rc==GX3DE_OK)(*out)->view=view;return rc;
}
gx3de_result gx3de_marker_style_set(gx3de_marker* marker,const gx3de_marker_style* style) {
    if(!marker||!renderer_valid_marker_style(style))return GX3DE_INVALID_ARGUMENT;
    marker->style=*style;marker->style.struct_size=sizeof(*style);return GX3DE_OK;
}
gx3de_result gx3de_marker_style_get(gx3de_marker* marker,gx3de_marker_style* style) {
    if(!marker||!style||style->struct_size<sizeof(*style))return GX3DE_INVALID_ARGUMENT;
    *style=marker->style;return GX3DE_OK;
}
gx3de_result gx3de_marker_destroy(gx3de_marker* marker) {
    if(!marker)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(marker->scene->markers,marker);delete marker;return GX3DE_OK;
}
gx3de_result gx3de_measure_create(gx3de_scene* s,gx3de_measure_kind k,gx3de_anchor* a,gx3de_anchor* b,gx3de_anchor* c,gx3de_plane* p,gx3de_measurement** out) {
    if(!s||!out||!a||!b||a->scene!=s||b->scene!=s||k<GX3DE_DISTANCE||k>GX3DE_DISTANCE_ON_PLANE)return GX3DE_INVALID_ARGUMENT;
    if((k==GX3DE_ANGLE_THREE_POINTS&&(!c||c->scene!=s))||(k==GX3DE_DISTANCE_ON_PLANE&&(!p||p->scene!=s)))return GX3DE_INVALID_ARGUMENT;
    auto m=new(std::nothrow) gx3de_measurement{s,k,a,b,c,p};return retain(s->measurements,m,out);
}
gx3de_result gx3de_measure_create_ex(gx3de_scene* s,const gx3de_measure_spec* spec,gx3de_measurement** out) {
    if(!s||!spec||!out||spec->struct_size<sizeof(gx3de_measure_spec)||spec->kind<GX3DE_DISTANCE||spec->kind>GX3DE_POINT_SURFACE_DISTANCE)return GX3DE_INVALID_ARGUMENT;
    for(auto a:spec->anchors)if(a&&a->scene!=s)return GX3DE_WRONG_OWNER;for(auto p:spec->planes)if(p&&p->scene!=s)return GX3DE_WRONG_OWNER;
    if(spec->surface_object&&spec->surface_object->scene!=s)return GX3DE_WRONG_OWNER;
    auto a=spec->anchors[0],b=spec->anchors[1],c=spec->anchors[2],d=spec->anchors[3];auto p=spec->planes[0],q=spec->planes[1];
    bool valid=false;switch(spec->kind){case GX3DE_DISTANCE:case GX3DE_DELTA_X:case GX3DE_DELTA_Y:case GX3DE_DELTA_Z:valid=a&&b;break;
        case GX3DE_ANGLE_THREE_POINTS:case GX3DE_POINT_LINE_DISTANCE:valid=a&&b&&c;break;
        case GX3DE_DISTANCE_ON_PLANE:valid=a&&b&&p;break;case GX3DE_POINT_PLANE_DISTANCE:valid=a&&p;break;
        case GX3DE_LINE_LINE_ANGLE:valid=a&&b&&c&&d;break;case GX3DE_LINE_PLANE_ANGLE:valid=a&&b&&p;break;
        case GX3DE_PLANE_PLANE_ANGLE:valid=p&&q;break;case GX3DE_POINT_SURFACE_DISTANCE:valid=a&&spec->surface_object&&spec->surface_object->mesh;break;default:break;}
    if(!valid)return GX3DE_INVALID_ARGUMENT;auto m=new(std::nothrow) gx3de_measurement{s,static_cast<gx3de_measure_kind>(spec->kind),a,b,c,p,d,q,spec->surface_object};return retain(s->measurements,m,out);
}
gx3de_result gx3de_measure_get_spec(gx3de_measurement* m,gx3de_measure_spec* out) {if(!m||!out||out->struct_size<sizeof(gx3de_measure_spec))return GX3DE_INVALID_ARGUMENT;*out={sizeof(gx3de_measure_spec),uint32_t(m->kind),{m->a,m->b,m->c,m->d},{m->plane,m->plane2},m->surface,{}};return GX3DE_OK;}
gx3de_result gx3de_measure_evaluate(gx3de_measurement* m,gx3de_measure_value* out) {
    if(!m||!out||out->struct_size<sizeof(gx3de_measure_value))return GX3DE_INVALID_ARGUMENT;
    gx3de_vec3 a{},b{},c{},d{};if(m->a)gx3de_anchor_position(m->a,&a);if(m->b)gx3de_anchor_position(m->b,&b);if(m->c)gx3de_anchor_position(m->c,&c);if(m->d)gx3de_anchor_position(m->d,&d);
    double value=0,den=0;auto ab=sub(b,a);
    switch(m->kind){case GX3DE_DISTANCE:case GX3DE_DELTA_X:case GX3DE_DELTA_Y:case GX3DE_DELTA_Z:
        if(!m->a||!m->b)return GX3DE_NOT_FOUND;
        value=m->kind==GX3DE_DISTANCE?length(ab):m->kind==GX3DE_DELTA_X?ab.x:m->kind==GX3DE_DELTA_Y?ab.y:ab.z;break;
    case GX3DE_DISTANCE_ON_PLANE:if(!m->a||!m->b||!m->plane)return GX3DE_NOT_FOUND;value=length(sub(ab,mul(m->plane->n,dot(ab,m->plane->n))));break;
    case GX3DE_ANGLE_THREE_POINTS:if(!m->a||!m->b||!m->c)return GX3DE_NOT_FOUND;{auto u=sub(a,b),v=sub(c,b);den=length(u)*length(v);if(den<1e-12)return GX3DE_DEGENERATE;value=std::acos(std::clamp(dot(u,v)/den,-1.0,1.0));}break;
    case GX3DE_POINT_LINE_DISTANCE:if(!m->a||!m->b||!m->c)return GX3DE_NOT_FOUND;{auto line=sub(c,b);den=length(line);if(den<1e-12)return GX3DE_DEGENERATE;value=length(cross(sub(a,b),line))/den;}break;
    case GX3DE_POINT_PLANE_DISTANCE:if(!m->a||!m->plane)return GX3DE_NOT_FOUND;value=std::abs(dot(sub(a,m->plane->origin),m->plane->n));break;
    case GX3DE_LINE_LINE_ANGLE:if(!m->a||!m->b||!m->c||!m->d)return GX3DE_NOT_FOUND;{auto line2=sub(d,c);den=length(ab)*length(line2);if(den<1e-12)return GX3DE_DEGENERATE;value=std::acos(std::clamp(std::abs(dot(ab,line2)/den),0.0,1.0));}break;
    case GX3DE_LINE_PLANE_ANGLE:if(!m->a||!m->b||!m->plane)return GX3DE_NOT_FOUND;den=length(ab);if(den<1e-12)return GX3DE_DEGENERATE;value=std::asin(std::clamp(std::abs(dot(ab,m->plane->n)/den),0.0,1.0));break;
    case GX3DE_PLANE_PLANE_ANGLE:if(!m->plane||!m->plane2)return GX3DE_NOT_FOUND;value=std::acos(std::clamp(std::abs(dot(m->plane->n,m->plane2->n)),0.0,1.0));break;
    case GX3DE_POINT_SURFACE_DISTANCE:if(!m->a||!m->surface)return GX3DE_NOT_FOUND;if(!m->surface->mesh)return GX3DE_UNSUPPORTED;
        try {std::vector<gx3de_vec3> points;points.reserve(m->surface->mesh->vertices.size());for(auto p:m->surface->mesh->vertices)points.push_back(apply(world(m->surface),p));
            std::string error;if(!gx3de_backend::vtk_point_surface_distance(points,m->surface->mesh->triangles,a,value,error))return GX3DE_DEGENERATE;}
        catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}break;
    default:return GX3DE_UNSUPPORTED;}
    *out={sizeof(gx3de_measure_value),uint32_t(m->kind),value,0,0,{}};return GX3DE_OK;
}
gx3de_result gx3de_measure_destroy(gx3de_measurement* m) { if(!m)return GX3DE_INVALID_ARGUMENT;erase_ptr(m->scene->measurements,m);delete m;return GX3DE_OK; }
gx3de_result gx3de_measurement_style_set(gx3de_measurement* m,const gx3de_measurement_style* s) {
    if(!m||!s||s->struct_size<sizeof(*s)||s->visible>1||s->show_value>1||
       !renderer_valid_rgb(s->color)||!std::isfinite(s->marker_size_pixels)||
       s->marker_size_pixels<1||s->marker_size_pixels>128||
       !std::isfinite(s->line_width)||s->line_width<=0||s->line_width>64)
        return GX3DE_INVALID_ARGUMENT;
    m->style=*s;m->style.struct_size=sizeof(*s);return GX3DE_OK;
}
gx3de_result gx3de_measurement_style_get(gx3de_measurement* m,gx3de_measurement_style* s) {
    if(!m||!s||s->struct_size<sizeof(*s))return GX3DE_INVALID_ARGUMENT;
    *s=m->style;return GX3DE_OK;
}
gx3de_result gx3de_constraint_create_ex(gx3de_scene* scene,const gx3de_constraint_spec_ex* spec,gx3de_constraint** out) {
    if(!scene||!spec||!out||spec->struct_size<sizeof(gx3de_constraint_spec_ex)||
       spec->kind<GX3DE_CONSTRAINT_ANGLE_LINES||spec->kind>GX3DE_CONSTRAINT_ALIGNED_AXES||
       !spec->moving_object||!std::isfinite(spec->target)||!std::isfinite(spec->tolerance)||spec->tolerance<=0)return GX3DE_INVALID_ARGUMENT;
    if(spec->moving_object->scene!=scene)return GX3DE_WRONG_OWNER;
    for(auto a:spec->anchors)if(a&&a->scene!=scene)return GX3DE_WRONG_OWNER;
    if(spec->surface_object&&spec->surface_object->scene!=scene)return GX3DE_WRONG_OWNER;
    auto moving=spec->moving_object;
    if(!spec->anchors[0]||spec->anchors[0]->object!=moving)return GX3DE_INVALID_ARGUMENT;
    if(spec->kind==GX3DE_CONSTRAINT_POINT_ON_SURFACE){
        if(!spec->surface_object||!spec->surface_object->mesh)return GX3DE_INVALID_ARGUMENT;
        for(auto p=spec->surface_object;p;p=p->parent)if(p==moving)return GX3DE_INVALID_ARGUMENT;
    }else if(spec->kind==GX3DE_CONSTRAINT_POINT_ON_LINE){
        if(!spec->anchors[1]||!spec->anchors[2])return GX3DE_INVALID_ARGUMENT;
        for(int i=1;i<=2;++i)for(auto p=spec->anchors[i]->object;p;p=p->parent)if(p==moving)return GX3DE_INVALID_ARGUMENT;
    }else {
        if(!spec->anchors[1]||!spec->anchors[2]||!spec->anchors[3]||spec->anchors[1]->object!=moving)return GX3DE_INVALID_ARGUMENT;
        for(int i=2;i<=3;++i)for(auto p=spec->anchors[i]->object;p;p=p->parent)if(p==moving)return GX3DE_INVALID_ARGUMENT;
        if(spec->kind==GX3DE_CONSTRAINT_ANGLE_LINES&&(spec->target<0||spec->target>std::acos(-1.0)/2))return GX3DE_INVALID_ARGUMENT;
    }
    auto base=gx3de_constraint_spec{};base.struct_size=sizeof(base);base.kind=spec->kind;base.moving_object=moving;base.tolerance=spec->tolerance;
    auto result=new(std::nothrow) gx3de_constraint{scene,base,moving->transform};if(!result)return GX3DE_OUT_OF_MEMORY;
    result->extended=true;result->extended_spec=*spec;return retain(scene->constraints,result,out);
}
gx3de_result gx3de_constraint_create(gx3de_scene* s,const gx3de_constraint_spec* spec,gx3de_constraint** out) {
    if(!s||!spec||!out||spec->struct_size<sizeof(gx3de_constraint_spec)||spec->kind<GX3DE_CONSTRAINT_FIXED||spec->kind>GX3DE_CONSTRAINT_POINT_ON_PLANE||!spec->moving_object||!std::isfinite(spec->target)||!std::isfinite(spec->tolerance)||spec->tolerance<=0)return GX3DE_INVALID_ARGUMENT;
    if(spec->moving_object->scene!=s)return GX3DE_WRONG_OWNER;
    if(spec->a&&spec->a->scene!=s)return GX3DE_WRONG_OWNER;if(spec->b&&spec->b->scene!=s)return GX3DE_WRONG_OWNER;if(spec->plane&&spec->plane->scene!=s)return GX3DE_WRONG_OWNER;
    if(spec->kind!=GX3DE_CONSTRAINT_FIXED){if(!spec->a||spec->a->object!=spec->moving_object)return GX3DE_INVALID_ARGUMENT;
        if(spec->kind==GX3DE_CONSTRAINT_POINT_ON_PLANE){if(!spec->plane)return GX3DE_INVALID_ARGUMENT;}
        else {if(!spec->b||spec->b==spec->a)return GX3DE_INVALID_ARGUMENT;for(auto p=spec->b->object;p;p=p->parent)if(p==spec->moving_object)return GX3DE_INVALID_ARGUMENT;}
        if(spec->kind==GX3DE_CONSTRAINT_DISTANCE&&spec->target<0)return GX3DE_INVALID_ARGUMENT;}
    auto c=new(std::nothrow) gx3de_constraint{s,*spec,spec->moving_object->transform};return retain(s->constraints,c,out);
}
gx3de_result gx3de_constraint_evaluate(gx3de_constraint* c,gx3de_constraint_value* out) {
    if(!c||!out||out->struct_size<sizeof(gx3de_constraint_value))return GX3DE_INVALID_ARGUMENT;if(!c->spec.moving_object)return GX3DE_NOT_FOUND;
    if(c->extended){auto& spec=c->extended_spec;if(!spec.moving_object)return GX3DE_NOT_FOUND;
        gx3de_vec3 p[4]{};for(int i=0;i<4;++i)if(spec.anchors[i]){auto r=gx3de_anchor_position(spec.anchors[i],&p[i]);if(r!=GX3DE_OK)return r;}
        double residual=0;
        if(spec.kind==GX3DE_CONSTRAINT_POINT_ON_SURFACE){if(!spec.anchors[0]||!spec.surface_object)return GX3DE_NOT_FOUND;
            if(!spec.surface_object->mesh)return GX3DE_UNSUPPORTED;
            try {auto surface=placed_mesh(spec.surface_object);std::string error;
                if(!gx3de_backend::vtk_point_surface_distance(surface.vertices,surface.triangles,p[0],residual,error))return GX3DE_DEGENERATE;
            }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
        }else if(spec.kind==GX3DE_CONSTRAINT_POINT_ON_LINE){if(!spec.anchors[0]||!spec.anchors[1]||!spec.anchors[2])return GX3DE_NOT_FOUND;
            auto line=sub(p[2],p[1]);double length_line=length(line);if(length_line<1e-12)return GX3DE_DEGENERATE;
            residual=length(cross(sub(p[0],p[1]),line))/length_line;
        }else {for(auto anchor:spec.anchors)if(!anchor)return GX3DE_NOT_FOUND;
            auto source=sub(p[1],p[0]),target=sub(p[3],p[2]);double denominator=length(source)*length(target);
            if(denominator<1e-12)return GX3DE_DEGENERATE;
            double angle=std::acos(std::clamp(std::abs(dot(source,target)/denominator),0.0,1.0));
            if(spec.kind==GX3DE_CONSTRAINT_PARALLEL_LINES)residual=angle;
            else if(spec.kind==GX3DE_CONSTRAINT_PERPENDICULAR_LINES)residual=std::abs(std::acos(-1.0)/2-angle);
            else if(spec.kind==GX3DE_CONSTRAINT_ANGLE_LINES)residual=std::abs(angle-spec.target);
            else {auto unit=mul(target,1/length(target));residual=std::max(angle,length(cross(sub(p[0],p[2]),unit)));}
        }
        *out={sizeof(gx3de_constraint_value),uint32_t(residual<=spec.tolerance?GX3DE_CONSTRAINT_SATISFIED:GX3DE_CONSTRAINT_VIOLATED),residual,spec.tolerance,{}};return GX3DE_OK;
    }
    double residual=0;auto spec=c->spec;
    if(spec.kind==GX3DE_CONSTRAINT_FIXED){for(int i=0;i<16;++i)residual=std::max(residual,std::abs(spec.moving_object->transform.m[i]-c->fixed_transform.m[i]));}
    else {if(!spec.a)return GX3DE_NOT_FOUND;gx3de_vec3 a,b;gx3de_anchor_position(spec.a,&a);
        if(spec.kind==GX3DE_CONSTRAINT_POINT_ON_PLANE){if(!spec.plane)return GX3DE_NOT_FOUND;residual=std::abs(dot(sub(a,spec.plane->origin),spec.plane->n));}
        else {if(!spec.b)return GX3DE_NOT_FOUND;gx3de_anchor_position(spec.b,&b);residual=spec.kind==GX3DE_CONSTRAINT_COINCIDENT?length(sub(a,b)):std::abs(length(sub(a,b))-spec.target);}}
    *out={sizeof(gx3de_constraint_value),uint32_t(residual<=spec.tolerance?GX3DE_CONSTRAINT_SATISFIED:GX3DE_CONSTRAINT_VIOLATED),residual,spec.tolerance,{}};return GX3DE_OK;
}
gx3de_result gx3de_constraint_solve(gx3de_constraint* c,gx3de_constraint_value* out) {
    if(!c||!out||out->struct_size<sizeof(gx3de_constraint_value))return GX3DE_INVALID_ARGUMENT;if(!c->spec.moving_object)return GX3DE_NOT_FOUND;
    auto* moving=c->spec.moving_object;auto prior=moving->transform;auto spec=c->spec;
    if(c->extended){auto& ext=c->extended_spec;
        gx3de_vec3 p[4]{};for(int i=0;i<4;++i){if(!ext.anchors[i])continue;auto r=gx3de_anchor_position(ext.anchors[i],&p[i]);if(r!=GX3DE_OK)return r;}
        gx3de_result result=GX3DE_OK;
        if(ext.kind==GX3DE_CONSTRAINT_POINT_ON_SURFACE){
            if(!ext.anchors[0]||!ext.surface_object)return GX3DE_NOT_FOUND;
            if(!ext.surface_object->mesh)return GX3DE_UNSUPPORTED;
            try {auto surface=placed_mesh(ext.surface_object);std::string error;
                gx3de_vec3 nearest{};double distance=0;
                if(!gx3de_backend::vtk_point_surface_distance(surface.vertices,surface.triangles,
                        p[0],distance,error,&nearest))return GX3DE_DEGENERATE;
                result=gx3de_object_translate(moving,sub(nearest,p[0]),1);
            }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
        }else if(ext.kind==GX3DE_CONSTRAINT_POINT_ON_LINE){if(!ext.anchors[0]||!ext.anchors[1]||!ext.anchors[2])return GX3DE_NOT_FOUND;
            auto direction=sub(p[2],p[1]);double squared=dot(direction,direction);if(squared<1e-24)return GX3DE_DEGENERATE;
            auto closest=add(p[1],mul(direction,dot(sub(p[0],p[1]),direction)/squared));
            result=gx3de_object_translate(moving,sub(closest,p[0]),1);
        }else {for(auto anchor:ext.anchors)if(!anchor)return GX3DE_NOT_FOUND;
            auto from=sub(p[1],p[0]),to=sub(p[3],p[2]);double lf=length(from),lt=length(to);if(lf<1e-12||lt<1e-12)return GX3DE_DEGENERATE;
            from=mul(from,1/lf);to=mul(to,1/lt);if(dot(from,to)<0)to=mul(to,-1);
            gx3de_vec3 desired=to;
            if(ext.kind==GX3DE_CONSTRAINT_PERPENDICULAR_LINES||ext.kind==GX3DE_CONSTRAINT_ANGLE_LINES){
                auto perp=sub(from,mul(to,dot(from,to)));double lp=length(perp);
                if(lp<1e-12){perp=cross(to,std::abs(to.x)<0.9?gx3de_vec3{1,0,0}:gx3de_vec3{0,1,0});lp=length(perp);}
                perp=mul(perp,1/lp);double angle=ext.kind==GX3DE_CONSTRAINT_PERPENDICULAR_LINES?std::acos(-1.0)/2:ext.target;
                desired=add(mul(to,std::cos(angle)),mul(perp,std::sin(angle)));
            }
            auto axis=cross(from,desired);double sine=length(axis);
            if(sine>1e-12)result=gx3de_object_rotate(moving,axis,std::atan2(sine,std::clamp(dot(from,desired),-1.0,1.0)),p[0],1);
            if(result==GX3DE_OK&&ext.kind==GX3DE_CONSTRAINT_ALIGNED_AXES){
                gx3de_vec3 current;result=gx3de_anchor_position(ext.anchors[0],&current);
                if(result==GX3DE_OK){auto fixed_direction=sub(p[3],p[2]);double squared=dot(fixed_direction,fixed_direction);
                    auto closest=add(p[2],mul(fixed_direction,dot(sub(current,p[2]),fixed_direction)/squared));
                    result=gx3de_object_translate(moving,sub(closest,current),1);}
            }
        }
        if(result!=GX3DE_OK){moving->transform=prior;return result;}
        gx3de_constraint_value evaluated{sizeof(gx3de_constraint_value)};result=gx3de_constraint_evaluate(c,&evaluated);
        if(result!=GX3DE_OK||evaluated.status!=GX3DE_CONSTRAINT_SATISFIED){moving->transform=prior;
            if(result==GX3DE_OK)*out=evaluated;return result;}
        auto proposed=moving->transform;
        for(auto other:c->scene->constraints)if(other!=c&&other->spec.moving_object==moving){
            gx3de_constraint_value before{sizeof(gx3de_constraint_value)},after{sizeof(gx3de_constraint_value)};
            moving->transform=prior;auto rb=gx3de_constraint_evaluate(other,&before);moving->transform=proposed;
            auto ra=gx3de_constraint_evaluate(other,&after);
            if(rb==GX3DE_OK&&ra==GX3DE_OK&&before.status==GX3DE_CONSTRAINT_SATISFIED&&after.status==GX3DE_CONSTRAINT_VIOLATED){
                moving->transform=prior;*out={sizeof(gx3de_constraint_value),GX3DE_CONSTRAINT_OVERCONSTRAINED,after.residual,ext.tolerance,{}};return GX3DE_OK;}
        }
        *out=evaluated;out->status=GX3DE_CONSTRAINT_UNDERDETERMINED;return GX3DE_OK;
    }
    if(spec.kind==GX3DE_CONSTRAINT_FIXED)moving->transform=c->fixed_transform;
    else {if(moving->parent)return GX3DE_UNSUPPORTED;if(!spec.a)return GX3DE_NOT_FOUND;gx3de_vec3 a,b{},delta{};gx3de_anchor_position(spec.a,&a);
        if(spec.kind==GX3DE_CONSTRAINT_POINT_ON_PLANE){if(!spec.plane)return GX3DE_NOT_FOUND;delta=mul(spec.plane->n,-dot(sub(a,spec.plane->origin),spec.plane->n));}
        else {if(!spec.b)return GX3DE_NOT_FOUND;gx3de_anchor_position(spec.b,&b);
            if(spec.kind==GX3DE_CONSTRAINT_COINCIDENT)delta=sub(b,a);
            else {auto radial=sub(a,b);double distance=length(radial);if(distance<1e-12&&spec.target>spec.tolerance){*out={sizeof(gx3de_constraint_value),GX3DE_CONSTRAINT_UNDERDETERMINED,spec.target,spec.tolerance,{}};return GX3DE_OK;}if(distance>0)delta=mul(radial,(spec.target-distance)/distance);}}
        moving->transform=product(translation(delta),prior);}
    gx3de_constraint_value evaluated{sizeof(gx3de_constraint_value)};auto r=gx3de_constraint_evaluate(c,&evaluated);if(r!=GX3DE_OK){moving->transform=prior;return r;}
    if(evaluated.status!=GX3DE_CONSTRAINT_SATISFIED){moving->transform=prior;*out=evaluated;return GX3DE_OK;}
    auto proposed=moving->transform;
    for(auto other:c->scene->constraints)if(other!=c&&other->spec.moving_object==moving){gx3de_constraint_value previous{sizeof(gx3de_constraint_value)},now{sizeof(gx3de_constraint_value)};
        moving->transform=prior;auto before=gx3de_constraint_evaluate(other,&previous);moving->transform=proposed;
        auto after=gx3de_constraint_evaluate(other,&now);
        if(before==GX3DE_OK&&after==GX3DE_OK&&previous.status==GX3DE_CONSTRAINT_SATISFIED&&now.status==GX3DE_CONSTRAINT_VIOLATED){moving->transform=prior;*out={sizeof(gx3de_constraint_value),GX3DE_CONSTRAINT_OVERCONSTRAINED,now.residual,spec.tolerance,{}};return GX3DE_OK;}}
    *out=evaluated;if(spec.kind!=GX3DE_CONSTRAINT_FIXED)out->status=GX3DE_CONSTRAINT_UNDERDETERMINED;return GX3DE_OK;
}
gx3de_result gx3de_constraint_system_solve(gx3de_scene* scene,
        gx3de_constraint* const* constraints,uint64_t count,uint32_t max_passes,
        gx3de_constraint_system_result* out) {
    if(!scene||!constraints||count==0||count>256||!out||
       out->struct_size<sizeof(gx3de_constraint_system_result)||max_passes>128)
        return GX3DE_INVALID_ARGUMENT;
    if(max_passes==0)max_passes=16;
    try {
        std::vector<gx3de_object*> objects;
        std::vector<gx3de_mat4> original;
        std::unordered_set<gx3de_constraint*> selected;
        for(uint64_t i=0;i<count;++i){
            auto* c=constraints[i];
            if(!c)return GX3DE_INVALID_ARGUMENT;
            if(c->scene!=scene)return GX3DE_WRONG_OWNER;
            if(!selected.insert(c).second)return GX3DE_INVALID_ARGUMENT;
            auto* moving=c->spec.moving_object;
            if(!moving)return GX3DE_NOT_FOUND;
            if(std::find(objects.begin(),objects.end(),moving)==objects.end()){
                objects.push_back(moving);original.push_back(moving->transform);
            }
            gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
            auto r=gx3de_constraint_evaluate(c,&value);
            if(r!=GX3DE_OK)return r;
        }
        auto restore=[&](){for(size_t i=0;i<objects.size();++i)objects[i]->transform=original[i];};
        auto report=[&](uint32_t status,uint32_t passes,bool commit)->gx3de_result{
            uint64_t satisfied=0;double maximum=0;
            for(uint64_t i=0;i<count;++i){
                gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
                if(gx3de_constraint_evaluate(constraints[i],&value)==GX3DE_OK){
                    if(value.status==GX3DE_CONSTRAINT_SATISFIED)++satisfied;
                    maximum=std::max(maximum,value.residual);
                }
            }
            if(!commit)restore();
            *out={sizeof(gx3de_constraint_system_result),status,count,satisfied,
                  static_cast<uint64_t>(objects.size()),passes,0,maximum,{}};
            return GX3DE_OK;
        };
        // A selected parent/child pair would make the local transforms coupled.
        // A system solve changes each selected object's pose independently.
        for(auto* object:objects)for(auto* parent=object->parent;parent;parent=parent->parent)
            if(std::find(objects.begin(),objects.end(),parent)!=objects.end())
                return report(GX3DE_CONSTRAINT_UNSUPPORTED,0,false);
        std::vector<gx3de_constraint*> protected_constraints;
        for(auto* c:scene->constraints)if(!selected.count(c)&&
                std::find(objects.begin(),objects.end(),c->spec.moving_object)!=objects.end()){
            gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
            if(gx3de_constraint_evaluate(c,&value)==GX3DE_OK&&
               value.status==GX3DE_CONSTRAINT_SATISFIED)protected_constraints.push_back(c);
        }
        bool underdetermined_stall=false;
        for(uint32_t pass=1;pass<=max_passes;++pass){
            std::unordered_set<gx3de_constraint*> grouped;
            for(auto* moving:objects){
                std::vector<gx3de_constraint*> coincidences;
                bool fixed=false;
                for(uint64_t i=0;i<count;++i)if(constraints[i]->spec.moving_object==moving){
                    if(constraints[i]->spec.kind==GX3DE_CONSTRAINT_FIXED)fixed=true;
                    if(constraints[i]->spec.kind==GX3DE_CONSTRAINT_COINCIDENT)
                        coincidences.push_back(constraints[i]);
                }
                if(fixed||coincidences.size()<2)continue;
                for(auto* c:coincidences)grouped.insert(c);
                auto* first=coincidences[0];
                gx3de_vec3 source0{},target0{};
                if(gx3de_anchor_position(first->spec.a,&source0)!=GX3DE_OK||
                   gx3de_anchor_position(first->spec.b,&target0)!=GX3DE_OK){restore();return GX3DE_NOT_FOUND;}
                size_t second=coincidences.size(),third=coincidences.size();
                gx3de_vec3 source1{},target1{},source2{},target2{};
                for(size_t i=1;i<coincidences.size();++i){
                    gx3de_vec3 s{},t{};auto* c=coincidences[i];
                    if(gx3de_anchor_position(c->spec.a,&s)!=GX3DE_OK||
                       gx3de_anchor_position(c->spec.b,&t)!=GX3DE_OK){restore();return GX3DE_NOT_FOUND;}
                    if(length(sub(s,source0))>1e-10&&second==coincidences.size()){
                        second=i;source1=s;target1=t;
                    }else if(second!=coincidences.size()&&third==coincidences.size()&&
                             length(cross(sub(source1,source0),sub(s,source0)))>1e-10){
                        third=i;source2=s;target2=t;
                    }
                }
                gx3de_result result=GX3DE_OK;
                if(third!=coincidences.size()){
                    gx3de_alignment_spec alignment{};alignment.struct_size=sizeof alignment;
                    alignment.moving_object=moving;
                    gx3de_constraint* chosen[]={first,coincidences[second],coincidences[third]};
                    for(int i=0;i<3;++i){alignment.moving_points[i]=chosen[i]->spec.a;
                        alignment.target_points[i]=chosen[i]->spec.b;}
                    alignment.tolerance=std::max({chosen[0]->spec.tolerance,
                        chosen[1]->spec.tolerance,chosen[2]->spec.tolerance});
                    result=gx3de_object_align_three_points(&alignment);
                }else if(second!=coincidences.size()){
                    auto from=sub(source1,source0),to=sub(target1,target0);
                    const double from_length=length(from),to_length=length(to);
                    const double tolerance=std::max(first->spec.tolerance,
                        coincidences[second]->spec.tolerance);
                    if(std::abs(from_length-to_length)>tolerance||to_length<=1e-10)
                        return report(GX3DE_CONSTRAINT_OVERCONSTRAINED,pass,false);
                    from=mul(from,1/from_length);to=mul(to,1/to_length);
                    auto axis=cross(from,to);double sine=length(axis);
                    double angle=std::atan2(sine,std::clamp(dot(from,to),-1.0,1.0));
                    if(sine<=1e-12&&dot(from,to)<0){
                        axis=cross(from,std::abs(from.x)<.9?gx3de_vec3{1,0,0}:gx3de_vec3{0,1,0});
                        sine=length(axis);angle=std::acos(-1.0);
                    }
                    if(sine>1e-12)
                        result=gx3de_object_rotate(moving,axis,angle,source0,1);
                    if(result==GX3DE_OK){gx3de_vec3 current{};
                        result=gx3de_anchor_position(first->spec.a,&current);
                        if(result==GX3DE_OK)result=gx3de_object_translate(moving,sub(target0,current),1);}
                }else result=gx3de_object_translate(moving,sub(target0,source0),1);
                if(result!=GX3DE_OK)return report(result==GX3DE_UNSUPPORTED?
                    GX3DE_CONSTRAINT_UNSUPPORTED:GX3DE_CONSTRAINT_OVERCONSTRAINED,pass,false);
                for(auto* c:coincidences){gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
                    if(gx3de_constraint_evaluate(c,&value)!=GX3DE_OK||
                       value.status!=GX3DE_CONSTRAINT_SATISFIED)
                        return report(GX3DE_CONSTRAINT_OVERCONSTRAINED,pass,false);}
            }
            for(uint64_t i=0;i<count;++i){auto* c=constraints[i];if(grouped.count(c))continue;
                gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
                auto r=gx3de_constraint_evaluate(c,&value);
                if(r!=GX3DE_OK){restore();return r;}
                if(value.status==GX3DE_CONSTRAINT_SATISFIED)continue;
                r=gx3de_constraint_solve(c,&value);
                if(r==GX3DE_UNSUPPORTED)return report(GX3DE_CONSTRAINT_UNSUPPORTED,pass,false);
                if(r!=GX3DE_OK){restore();return r;}
                if(value.status==GX3DE_CONSTRAINT_OVERCONSTRAINED)
                    return report(GX3DE_CONSTRAINT_OVERCONSTRAINED,pass,false);
                if(value.status==GX3DE_CONSTRAINT_UNDERDETERMINED){
                    gx3de_constraint_value after{sizeof(gx3de_constraint_value)};
                    if(gx3de_constraint_evaluate(c,&after)==GX3DE_OK&&
                       after.status!=GX3DE_CONSTRAINT_SATISFIED)underdetermined_stall=true;
                }
            }
            bool all=true;
            for(uint64_t i=0;i<count;++i){gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
                auto r=gx3de_constraint_evaluate(constraints[i],&value);
                if(r!=GX3DE_OK){restore();return r;}
                if(value.status!=GX3DE_CONSTRAINT_SATISFIED)all=false;
            }
            if(!all)continue;
            for(auto* c:protected_constraints){gx3de_constraint_value value{sizeof(gx3de_constraint_value)};
                if(gx3de_constraint_evaluate(c,&value)!=GX3DE_OK||
                   value.status!=GX3DE_CONSTRAINT_SATISFIED)
                    return report(GX3DE_CONSTRAINT_OVERCONSTRAINED,pass,false);
            }
            bool determined=true;
            for(auto* moving:objects){bool fixed=false;
                std::vector<gx3de_vec3> coincidence_points;
                for(uint64_t i=0;i<count;++i)if(constraints[i]->spec.moving_object==moving){
                    fixed|=constraints[i]->spec.kind==GX3DE_CONSTRAINT_FIXED;
                    if(constraints[i]->spec.kind==GX3DE_CONSTRAINT_COINCIDENT){
                        gx3de_vec3 point{};
                        if(gx3de_anchor_position(constraints[i]->spec.a,&point)==GX3DE_OK)
                            coincidence_points.push_back(point);
                    }
                }
                bool noncollinear=false;
                for(size_t i=0;i<coincidence_points.size()&&!noncollinear;++i)
                    for(size_t j=i+1;j<coincidence_points.size()&&!noncollinear;++j)
                        for(size_t k=j+1;k<coincidence_points.size();++k)
                            if(length(cross(sub(coincidence_points[j],coincidence_points[i]),
                                             sub(coincidence_points[k],coincidence_points[i])))>1e-10){
                                noncollinear=true;break;
                            }
                if(!fixed&&!noncollinear)determined=false;
            }
            return report(determined?GX3DE_CONSTRAINT_SATISFIED:
                          GX3DE_CONSTRAINT_UNDERDETERMINED,pass,true);
        }
        return report(underdetermined_stall?GX3DE_CONSTRAINT_UNDERDETERMINED:
                      GX3DE_CONSTRAINT_UNSUPPORTED,max_passes,false);
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_constraint_destroy(gx3de_constraint* c) {if(!c)return GX3DE_INVALID_ARGUMENT;erase_ptr(c->scene->constraints,c);delete c;return GX3DE_OK;}
gx3de_result gx3de_target_create_headless(gx3de_engine* e,uint32_t w,uint32_t h,gx3de_target** out) {
    if(!e||!out||!w||!h)return GX3DE_INVALID_ARGUMENT;
    if(w>16384||h>16384||uint64_t(w)*h*4>256ull*1024*1024)return GX3DE_RANGE;
    auto p=new(std::nothrow) gx3de_target{e,w,h,{}};
    if(p){p->quality=e->graphics.quality;p->gpu_budget_bytes=e->graphics.gpu_budget_bytes;
        p->interaction_active=e->graphics.interaction_active;}
    return retain(e->targets,p,out);
}
gx3de_result gx3de_target_create_native(gx3de_engine* e,uint32_t kind,uint64_t native_id,
                                         uint32_t w,uint32_t h,gx3de_target** out) {
    if(!e||!out||!native_id||!w||!h)return GX3DE_INVALID_ARGUMENT;
#ifdef _WIN32
    if(kind!=GX3DE_NATIVE_WINDOW_WIN32)return GX3DE_UNSUPPORTED;
#else
    if(kind!=GX3DE_NATIVE_WINDOW_X11)return GX3DE_UNSUPPORTED;
#endif
    auto rc=gx3de_target_create_headless(e,w,h,out);if(rc==GX3DE_OK){(*out)->native_kind=kind;
        (*out)->native_id=native_id;}return rc;
}
gx3de_result gx3de_target_destroy(gx3de_target* t) { if(!t)return GX3DE_INVALID_ARGUMENT;remove_target(t);return GX3DE_OK; }
gx3de_result gx3de_target_resize(gx3de_target* t,uint32_t w,uint32_t h,uint32_t logical_w,uint32_t logical_h) {
    if(!t||!w||!h||!logical_w||!logical_h)return GX3DE_INVALID_ARGUMENT;
    if(w>16384||h>16384||uint64_t(w)*h*4>256ull*1024*1024)return GX3DE_RANGE;
    for(const auto* vp:t->viewports)
        if(uint64_t(vp->x)+vp->width>w||uint64_t(vp->y)+vp->height>h)return GX3DE_RANGE;
    t->width=w;t->height=h;t->logical_width=logical_w;t->logical_height=logical_h;
    t->rgba.clear();return GX3DE_OK;
}
gx3de_result gx3de_target_geometry_get(gx3de_target* t,gx3de_target_geometry* out) {
    if(!t||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    const auto lw=t->logical_width?t->logical_width:t->width;
    const auto lh=t->logical_height?t->logical_height:t->height;
    *out={sizeof(*out),t->width,t->height,lw,lh,double(t->width)/lw,double(t->height)/lh,{}};
    return GX3DE_OK;
}
gx3de_result gx3de_target_render_quality_set(gx3de_target* t,const gx3de_render_quality* q) {
    if(!t||!q||q->struct_size<sizeof(*q))return GX3DE_INVALID_ARGUMENT;
    if(q->msaa_samples!=0&&q->msaa_samples!=2&&q->msaa_samples!=4&&q->msaa_samples!=8)
        return GX3DE_INVALID_ARGUMENT;
    if(q->transparency_mode!=GX3DE_TRANSPARENCY_DEPTH_PEEL&&
       q->transparency_mode!=GX3DE_TRANSPARENCY_ALPHA_FALLBACK)return GX3DE_INVALID_ARGUMENT;
    if(t->backend_preference==GX3DE_RENDER_BACKEND_D3D11&&
       (q->msaa_samples!=0||q->transparency_mode==GX3DE_TRANSPARENCY_DEPTH_PEEL))
        return GX3DE_UNSUPPORTED;
    t->quality=*q;t->quality.struct_size=sizeof(*q);t->quality_explicit=true;
    t->rgba.clear();return GX3DE_OK;
}
gx3de_result gx3de_target_render_quality_get(gx3de_target* t,gx3de_render_quality* q) {
    if(!t||!q||q->struct_size<sizeof(*q))return GX3DE_INVALID_ARGUMENT;
    *q=t->quality;return GX3DE_OK;
}
gx3de_result gx3de_engine_graphics_policy_set(gx3de_engine* e,const gx3de_graphics_policy* p) {
    if(!e||!p||p->struct_size<sizeof(*p)||p->quality.struct_size<sizeof(gx3de_render_quality)||
       p->execution>GX3DE_GRAPHICS_SOFTWARE||p->normal_lod<GX3DE_LOD_PREVIEW||
       p->normal_lod>GX3DE_LOD_FULL||p->interaction_lod<GX3DE_LOD_PREVIEW||
       p->interaction_lod>GX3DE_LOD_HIGH||p->interaction_lod_enabled>1||
       p->interaction_active>1||p->export_supersampling<1||p->export_supersampling>4||
       p->shadow_policy>GX3DE_SHADOW_FULL||
       p->display_triangle_budget<1000||p->display_triangle_budget>4000000||
       p->gpu_budget_bytes>16ull*1024*1024*1024||
       p->worker_rss_budget_bytes<128ull*1048576||p->worker_rss_budget_bytes>65536ull*1048576||
       p->worker_address_space_budget_bytes<512ull*1048576||
       p->worker_address_space_budget_bytes>65536ull*1048576||
       (p->quality.msaa_samples!=0&&p->quality.msaa_samples!=2&&
        p->quality.msaa_samples!=4&&p->quality.msaa_samples!=8)||
       (p->quality.transparency_mode!=GX3DE_TRANSPARENCY_DEPTH_PEEL&&
        p->quality.transparency_mode!=GX3DE_TRANSPARENCY_ALPHA_FALLBACK))
        return GX3DE_INVALID_ARGUMENT;
    for(auto* target:e->targets)if(target->backend_preference==GX3DE_RENDER_BACKEND_D3D11&&
        (p->quality.msaa_samples!=0||
         p->quality.transparency_mode==GX3DE_TRANSPARENCY_DEPTH_PEEL||
         p->execution==GX3DE_GRAPHICS_SOFTWARE))return GX3DE_UNSUPPORTED;
    e->graphics=*p;e->graphics.struct_size=sizeof(*p);e->graphics_configured=true;
    e->graphics.quality.struct_size=sizeof(gx3de_render_quality);
    for(auto* target:e->targets){target->quality=e->graphics.quality;
        target->quality_explicit=false;
        target->gpu_budget_bytes=e->graphics.gpu_budget_bytes;
        target->interaction_active=e->graphics.interaction_active;
        target->rgba.clear();target->render_key.clear();}
    return GX3DE_OK;
}
gx3de_result gx3de_engine_graphics_policy_get(gx3de_engine* e,gx3de_graphics_policy* p) {
    if(!e||!p||p->struct_size<sizeof(*p))return GX3DE_INVALID_ARGUMENT;
    *p=e->graphics;return GX3DE_OK;
}
gx3de_result gx3de_target_graphics_policy_get(gx3de_target* t,gx3de_graphics_policy* p) {
    if(!t||!p||p->struct_size<sizeof(*p))return GX3DE_INVALID_ARGUMENT;
    *p=t->engine->graphics;p->quality=t->quality;p->gpu_budget_bytes=t->gpu_budget_bytes;
    p->interaction_active=t->interaction_active;return GX3DE_OK;
}
gx3de_result gx3de_target_interaction_set(gx3de_target* t,uint32_t active) {
    if(!t||active>1)return GX3DE_INVALID_ARGUMENT;
    t->interaction_active=active;
    return GX3DE_OK;
}
gx3de_result gx3de_target_render_stats_get(gx3de_target* t,gx3de_render_stats* out) {
    if(!t||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    *out={sizeof(*out),0,t->completed_frames,t->geometry_rebuild_frames,
          t->geometry_reuse_frames,{}};
    return GX3DE_OK;
}
gx3de_result gx3de_target_gpu_budget_set(gx3de_target* t,uint64_t bytes){
    if(!t||bytes>16ull*1024*1024*1024)return GX3DE_INVALID_ARGUMENT;
    t->gpu_budget_bytes=bytes;return GX3DE_OK;
}
gx3de_result gx3de_target_render_resource_info_get(gx3de_target* t,
    gx3de_render_resource_info* out){
    if(!t||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    *out={sizeof(*out),t->gpu_estimated_bytes?GX3DE_RESOURCE_ESTIMATED:GX3DE_RESOURCE_UNAVAILABLE,
          GX3DE_RESOURCE_UNAVAILABLE,uint32_t(t->gpu_budget_bytes!=0),t->gpu_budget_bytes,
          t->gpu_estimated_bytes,0,t->gpu_last_rejected_bytes,{}};
    return GX3DE_OK;
}
gx3de_result gx3de_target_object_presentation_set(gx3de_target* t,gx3de_object* o,const gx3de_object_style* style,uint32_t visible,double opacity) {
    if(!t||!o||!style||style->struct_size<sizeof(*style)||visible>1||!std::isfinite(opacity)||opacity<0||opacity>1)return GX3DE_INVALID_ARGUMENT;
    if(t->backend_preference==GX3DE_RENDER_BACKEND_D3D11||!t->window||t->rendered.empty()||t->render_key!=renderer_static_state_key(t))return GX3DE_UNSUPPORTED;
    if(!o->planar_textures.empty()||!o->scene->repeats.empty()||style->mode!=o->style.mode||style->scalar_coloring!=o->style.scalar_coloring||style->backface_culling!=o->style.backface_culling)return GX3DE_UNSUPPORTED;
    bool owned=false;for(auto& rv:t->rendered)if(rv.viewport->view->scene==o->scene)owned=true;if(!owned)return GX3DE_WRONG_OWNER;
    auto oldStyle=o->style;auto oldVisible=o->visible;auto oldOpacity=o->opacity;
    auto rc=gx3de_object_style_set(o,style);if(rc!=GX3DE_OK)return rc;o->visible=visible;o->opacity=opacity;
    try {
        std::vector<gx3de_render_viewport> prepared;
        for(auto& rv:t->rendered)if(rv.viewport->view->scene==o->scene){
            gx3de_render_viewport stage{};stage.viewport=rv.viewport;stage.renderer=vtkSmartPointer<vtkRenderer>::New();
            if(o->scientific&&visible&&opacity>0){uint64_t triangles=0;rc=renderer_add_scientific(stage,o,triangles,t->engine->graphics.display_triangle_budget);if(rc!=GX3DE_OK||!stage.volumes.empty())throw std::runtime_error("Unsupported selective scientific presentation");}
            prepared.push_back(std::move(stage));
        }
        size_t i=0;for(auto& rv:t->rendered)if(rv.viewport->view->scene==o->scene){auto& stage=prepared[i++];
            if(o->scientific){for(auto& prop:rv.props)if(prop.object==o)rv.renderer->RemoveActor(prop.actor);rv.props.erase(std::remove_if(rv.props.begin(),rv.props.end(),[&](const gx3de_render_prop& p){return p.object==o;}),rv.props.end());for(auto& prop:stage.props){rv.renderer->AddActor(prop.actor);rv.props.push_back(prop);}}
            else {bool found=false;for(auto& prop:rv.props)if(prop.object==o){found=true;renderer_apply_style(prop.actor,o,rv.viewport->view);prop.actor->SetVisibility(visible&&opacity>0);}if(!found)throw std::runtime_error("Hidden geometry has no retained presentation");}
        }
        t->render_key=renderer_static_state_key(t);return GX3DE_OK;
    }catch(...){o->style=oldStyle;o->visible=oldVisible;o->opacity=oldOpacity;t->render_key.clear();return GX3DE_UNSUPPORTED;}
}
gx3de_result gx3de_target_render(gx3de_target* t) {
    auto rc=renderer_rebuild(t);
    if(rc!=GX3DE_OK)return rc;
    gx3de_renderer_device_info device{};device.struct_size=sizeof(device);
    rc=gx3de_target_renderer_info(t,&device);
    if(rc!=GX3DE_OK)return rc;
    const auto requested=t->engine->graphics.execution;
    if((requested==GX3DE_GRAPHICS_HARDWARE&&device.execution!=GX3DE_RENDER_EXECUTION_HARDWARE)||
       (requested==GX3DE_GRAPHICS_SOFTWARE&&device.execution!=GX3DE_RENDER_EXECUTION_SOFTWARE)) {
        t->rgba.clear();t->diagnostic=requested==GX3DE_GRAPHICS_HARDWARE?
            "hardware rendering was required but the active device is not hardware: ":
            "software rendering was required but the active device is not software: ";
        t->diagnostic+=device.adapter;
        return GX3DE_UNSUPPORTED;
    }
    return GX3DE_OK;
}
gx3de_result gx3de_target_render_diagnostics(gx3de_target* t,char* buffer,uint64_t capacity,
                                              uint64_t* required) {
    if(!t||!required||(!buffer&&capacity))return GX3DE_INVALID_ARGUMENT;
    *required=t->diagnostic.size()+1;
    if(capacity==0)return GX3DE_OK;
    if(capacity<*required)return GX3DE_RANGE;
    std::memcpy(buffer,t->diagnostic.c_str(),size_t(*required));return GX3DE_OK;
}
gx3de_result gx3de_target_read_rgba(gx3de_target* t,uint8_t* pixels,uint64_t capacity,
                                     uint64_t* required) {
    if(!t||!required||(!pixels&&capacity))return GX3DE_INVALID_ARGUMENT;
    if(t->rgba.empty()){*required=0;return GX3DE_NOT_FOUND;}
    *required=t->rgba.size();if(capacity==0)return GX3DE_OK;
    if(capacity<t->rgba.size())return GX3DE_RANGE;
    std::memcpy(pixels,t->rgba.data(),t->rgba.size());return GX3DE_OK;
}
gx3de_result gx3de_target_write_png(gx3de_target* t,const char* path) {
    if(!t||!valid_utf8(path,4096)||!path[0])return GX3DE_INVALID_ARGUMENT;
    if(t->rgba.empty())return GX3DE_NOT_FOUND;
    try{
        vtkNew<vtkImageData> image;image->SetDimensions(int(t->width),int(t->height),1);
        image->AllocateScalars(VTK_UNSIGNED_CHAR,4);
        const size_t stride=size_t(t->width)*4;
        for(uint32_t y=0;y<t->height;++y)std::memcpy(image->GetScalarPointer(0,int(y),0),
            t->rgba.data()+size_t(t->height-1-y)*stride,stride);
        vtkNew<vtkPNGWriter> writer;writer->SetInputData(image);writer->WriteToMemoryOn();writer->Write();
        vtkUnsignedCharArray* bytes=writer->GetResult();if(!bytes||bytes->GetNumberOfValues()<24)return GX3DE_DEGENERATE;
        const auto output=std::filesystem::u8path(path);
        const auto temp=output.string()+".gx3de-"+
            std::to_string(std::chrono::steady_clock::now().time_since_epoch().count())+".tmp";
        {std::ofstream stream(temp,std::ios::binary|std::ios::trunc);
            if(!stream)return GX3DE_NOT_FOUND;
            stream.write(reinterpret_cast<const char*>(bytes->GetPointer(0)),bytes->GetNumberOfValues());
            if(!stream){stream.close();std::error_code ignored;std::filesystem::remove(temp,ignored);
                return GX3DE_DEGENERATE;}}
        std::error_code ec;std::filesystem::rename(temp,output,ec);
        if(ec){std::filesystem::remove(temp,ec);return GX3DE_DEGENERATE;}
        return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;
    }catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_target_write_vector(gx3de_target* t,const char* path,const char* format) {
    if(!t||!t->window||!valid_utf8(path,4096)||!path[0]||!format)return GX3DE_INVALID_ARGUMENT;
    const std::string f(format);if(f!="svg"&&f!="pdf")return GX3DE_INVALID_ARGUMENT;
    try {const auto output=std::filesystem::u8path(path);
        const auto prefix=output.string()+".native-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
        vtkNew<vtkGL2PSExporter> writer;writer->SetRenderWindow(t->window);writer->SetFilePrefix(prefix.c_str());
        if(f=="svg")writer->SetFileFormatToSVG();else writer->SetFileFormatToPDF();
        writer->CompressOff();writer->Write3DPropsAsRasterImageOff();writer->SetSortToBSP();writer->SilentOn();writer->Write();
        const auto staged=prefix+"."+f;std::error_code ec;
        if(!std::filesystem::is_regular_file(staged)||std::filesystem::file_size(staged)<100)return GX3DE_DEGENERATE;
        std::filesystem::rename(staged,output,ec);return ec?GX3DE_DEGENERATE:GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}catch(const std::exception&){return GX3DE_DEGENERATE;}
}
gx3de_result gx3de_view_render_rgba(gx3de_view* view,uint32_t width,uint32_t height,
                                     uint8_t* pixels,uint64_t capacity,uint64_t* required) {
    if(!view||!required||(!pixels&&capacity)||!width||!height)return GX3DE_INVALID_ARGUMENT;
    if(width>16384||height>16384||uint64_t(width)*height*4>256ull*1024*1024)return GX3DE_RANGE;
    *required=uint64_t(width)*height*4;if(capacity==0)return GX3DE_OK;
    if(capacity<*required)return GX3DE_RANGE;
    gx3de_target* target=nullptr;gx3de_viewport* viewport=nullptr;
    auto rc=gx3de_target_create_headless(view->scene->engine,width,height,&target);
    if(rc!=GX3DE_OK)return rc;
    rc=gx3de_viewport_create(target,view,0,0,width,height,&viewport);
    if(rc==GX3DE_OK)rc=gx3de_target_render(target);
    if(rc==GX3DE_OK)rc=gx3de_target_read_rgba(target,pixels,capacity,required);
    gx3de_target_destroy(target);return rc;
}
gx3de_result gx3de_view_write_png(gx3de_view* view,uint32_t width,uint32_t height,
                                   const char* path) {
    if(!view||!path||!width||!height)return GX3DE_INVALID_ARGUMENT;
    gx3de_target* target=nullptr;gx3de_viewport* viewport=nullptr;
    auto rc=gx3de_target_create_headless(view->scene->engine,width,height,&target);
    if(rc!=GX3DE_OK)return rc;
    rc=gx3de_viewport_create(target,view,0,0,width,height,&viewport);
    if(rc==GX3DE_OK)rc=gx3de_target_render(target);
    if(rc==GX3DE_OK)rc=gx3de_target_write_png(target,path);
    gx3de_target_destroy(target);return rc;
}
gx3de_result gx3de_view_write_png_supersampled(gx3de_view* view,uint32_t width,
    uint32_t height,uint32_t factor,const char* path) {
    if(!view||!path||!width||!height||factor<1||factor>4)return GX3DE_INVALID_ARGUMENT;
    if(factor==1)return gx3de_view_write_png(view,width,height,path);
    uint64_t required=0;
    auto rc=gx3de_view_render_rgba_supersampled(view,width,height,factor,nullptr,0,&required);
    if(rc!=GX3DE_OK)return rc;
    gx3de_target* target=nullptr;
    rc=gx3de_target_create_headless(view->scene->engine,width,height,&target);
    if(rc!=GX3DE_OK)return rc;
    try {
        target->rgba.resize(static_cast<size_t>(required));
        rc=gx3de_view_render_rgba_supersampled(view,width,height,factor,
            target->rgba.data(),required,&required);
        if(rc==GX3DE_OK)rc=gx3de_target_write_png(target,path);
    }catch(const std::bad_alloc&){rc=GX3DE_OUT_OF_MEMORY;}
    gx3de_target_destroy(target);return rc;
}
gx3de_result gx3de_view_create(gx3de_scene* s,gx3de_view** out) { if(!s||!out)return GX3DE_INVALID_ARGUMENT;auto v=new(std::nothrow) gx3de_view{};if(!v)return GX3DE_OUT_OF_MEMORY;v->scene=s;v->camera={sizeof(gx3de_camera),0,{0,0,5},{0,0,0},{0,1,0},0.01,10000,45,{}};return retain(s->views,v,out); }
gx3de_result gx3de_view_scene_get(gx3de_view* v,gx3de_scene** scene) {
    if(!v||!scene)return GX3DE_INVALID_ARGUMENT;
    *scene=v->scene;return GX3DE_OK;
}
gx3de_result gx3de_view_destroy(gx3de_view* v) { if(!v)return GX3DE_INVALID_ARGUMENT;remove_view(v);return GX3DE_OK; }
gx3de_result gx3de_view_set_camera(gx3de_view* v,const gx3de_camera* c) { if(!v||!c||c->struct_size<sizeof(gx3de_camera)||c->orthographic>1||!finite(c->position)||!finite(c->target)||!finite(c->up)||!std::isfinite(c->near_clip)||!std::isfinite(c->far_clip)||!std::isfinite(c->vertical_fov_degrees)||c->near_clip<=0||c->far_clip<=c->near_clip||c->vertical_fov_degrees<=0||c->vertical_fov_degrees>=180||length(sub(c->position,c->target))<1e-12||length(cross(sub(c->target,c->position),c->up))<1e-12)return GX3DE_INVALID_ARGUMENT;v->camera=*c;v->navcube.active_region=0;return GX3DE_OK; }
gx3de_result gx3de_view_get_camera(gx3de_view* v,gx3de_camera* c) { if(!v||!c||c->struct_size<sizeof(gx3de_camera))return GX3DE_INVALID_ARGUMENT;*c=v->camera;return GX3DE_OK; }
gx3de_result gx3de_view_camera_preset(gx3de_view* v,uint32_t preset,gx3de_object* fit) {
    if(!v||preset<GX3DE_CAMERA_FRONT||preset>GX3DE_CAMERA_FIT_SELECTION)return GX3DE_INVALID_ARGUMENT;
    if(fit&&fit->scene!=v->scene)return GX3DE_WRONG_OWNER;
    gx3de_camera camera=v->camera;
    gx3de_vec3 direction=mul(sub(camera.position,camera.target),
                             1.0/length(sub(camera.position,camera.target)));
    gx3de_vec3 up={0,0,1};
    switch(preset){
    case GX3DE_CAMERA_FRONT:direction={0,-1,0};break;
    case GX3DE_CAMERA_BACK:direction={0,1,0};break;
    case GX3DE_CAMERA_LEFT:direction={-1,0,0};break;
    case GX3DE_CAMERA_RIGHT:direction={1,0,0};break;
    case GX3DE_CAMERA_TOP:direction={0,0,1};up={0,1,0};break;
    case GX3DE_CAMERA_BOTTOM:direction={0,0,-1};up={0,1,0};break;
    case GX3DE_CAMERA_ISOMETRIC:direction=mul(gx3de_vec3{1,-1,1},1.0/std::sqrt(3.0));camera.orthographic=0;break;
    default:up=camera.up;break;}
    gx3de_bounds bounds{};bool any=false;
    if(preset==GX3DE_CAMERA_FIT_OBJECT){if(!fit)return GX3DE_INVALID_ARGUMENT;
        if(gx3de_object_bounds(fit,1,&bounds)!=GX3DE_OK)return GX3DE_NOT_FOUND;any=true;}
    else if(preset==GX3DE_CAMERA_FIT_SCENE||preset==GX3DE_CAMERA_FIT_SELECTION){
        for(auto* o:v->scene->objects)if(o->visible){gx3de_bounds b{};
            if(gx3de_object_bounds(o,1,&b)!=GX3DE_OK)continue;
            if(!any){bounds=b;any=true;}else{
                bounds.min={std::min(bounds.min.x,b.min.x),std::min(bounds.min.y,b.min.y),
                            std::min(bounds.min.z,b.min.z)};
                bounds.max={std::max(bounds.max.x,b.max.x),std::max(bounds.max.y,b.max.y),
                            std::max(bounds.max.z,b.max.z)};}}}
    gx3de_vec3 center=camera.target;
    if(preset==GX3DE_CAMERA_FIT_SELECTION){if(!v->selection)return GX3DE_NOT_FOUND;
        if(gx3de_anchor_position(v->selection,&center)!=GX3DE_OK)return GX3DE_NOT_FOUND;}
    else if(preset==GX3DE_CAMERA_FIT_SCENE||preset==GX3DE_CAMERA_FIT_OBJECT){
        if(!any)return GX3DE_NOT_FOUND;
        center=mul(add(bounds.min,bounds.max),0.5);}
    double distance=length(sub(camera.position,camera.target));
    if(any){const double span=std::max(length(sub(bounds.max,bounds.min)),1e-6);
        distance=std::max(span*0.75/std::tan(camera.vertical_fov_degrees*3.141592653589793/360.0),
                          span*1.2);}
    camera.target=center;camera.position=add(center,mul(direction,distance));camera.up=up;
    if(any){
        // Fit the depth range to the same bounding sphere used for framing.
        // Retaining the default 0.01..10000 range discards depth precision
        // on small meshes and makes nearby triangles visibly fight.
        const double radius=0.5*length(sub(bounds.max,bounds.min));
        const double extent=std::max(radius*1.5,1e-6);
        camera.near_clip=std::max(1e-6,distance-extent);
        camera.far_clip=std::max(camera.near_clip+1e-6,distance+extent);
    }
    return gx3de_view_set_camera(v,&camera);
}
static gx3de_vec3 camera_rotate(gx3de_vec3 point,gx3de_vec3 axis,double radians) {
    axis=mul(axis,1.0/length(axis));
    return add(add(mul(point,std::cos(radians)),mul(cross(axis,point),std::sin(radians))),
               mul(axis,dot(axis,point)*(1.0-std::cos(radians))));
}
gx3de_result gx3de_view_camera_roll(gx3de_view* v,double radians) {
    if(!v||!std::isfinite(radians))return GX3DE_INVALID_ARGUMENT;
    auto c=v->camera;c.up=camera_rotate(c.up,sub(c.target,c.position),radians);
    return gx3de_view_set_camera(v,&c);
}
gx3de_result gx3de_view_scientific_figure_set(gx3de_view* v,const gx3de_scientific_figure* f) {
    if(!v||!f||f->struct_size<sizeof(*f)||f->enabled>1||f->axes_grid_visible>1||f->colorbar_visible>1)return GX3DE_INVALID_ARGUMENT;
    if(f->enabled){
        if(!finite(f->world_bounds.min)||!finite(f->world_bounds.max))return GX3DE_INVALID_ARGUMENT;
        const double lo[]={f->world_bounds.min.x,f->world_bounds.min.y,f->world_bounds.min.z};
        const double hi[]={f->world_bounds.max.x,f->world_bounds.max.y,f->world_bounds.max.z};
        for(int i=0;i<3;++i)if(!(lo[i]<hi[i])||!std::isfinite(f->axis_min[i])||!std::isfinite(f->axis_max[i])||!(f->axis_min[i]<f->axis_max[i])||!std::memchr(f->axis_labels_utf8[i],0,256))return GX3DE_INVALID_ARGUMENT;
        if(!std::memchr(f->title_utf8,0,1024)||!std::memchr(f->legend_utf8,0,1024)||!std::memchr(f->scalar_label_utf8,0,256))return GX3DE_INVALID_ARGUMENT;
        if(f->colorbar_visible){
            if(f->palette_count<2||f->palette_count>256||!std::isfinite(f->scalar_min)||!std::isfinite(f->scalar_max)||!(f->scalar_min<f->scalar_max))return GX3DE_INVALID_ARGUMENT;
            for(uint32_t i=0;i<f->palette_count;++i)if(!renderer_valid_rgb(f->palette[i]))return GX3DE_INVALID_ARGUMENT;
        }
    }
    v->figure=*f;return GX3DE_OK;
}
gx3de_result gx3de_view_scientific_style_set(gx3de_view*v,const char*key,double value) {
 if(!v||!key||!std::isfinite(value))return GX3DE_INVALID_ARGUMENT;
 static const std::set<std::string> allowed={"font_size","axis_label_font_size","title_font_size","legend_font_size","legend_x","legend_y","legend_alignment","legend_background","legend_border","legend_background_r","legend_background_g","legend_background_b","legend_border_r","legend_border_g","legend_border_b","margin_left","margin_right","margin_top","margin_bottom","xgrid","ygrid","zgrid","grid_r","grid_g","grid_b"};
 if(!allowed.count(key))return GX3DE_INVALID_ARGUMENT;
 v->figure_style[key]=value;return GX3DE_OK;
}
static double scientific_style(const gx3de_view*v,const char*key,double fallback){auto found=v->figure_style.find(key);return found==v->figure_style.end()?fallback:found->second;}
gx3de_result gx3de_view_scientific_axis_labels_set(gx3de_view*v,uint32_t axis,const char*const*labels,uint32_t count) {
 if(!v||axis>2||count>64||(!labels&&count))return GX3DE_INVALID_ARGUMENT;
 std::vector<std::string> next;for(uint32_t i=0;i<count;++i){if(!valid_utf8(labels[i],128))return GX3DE_INVALID_ARGUMENT;next.emplace_back(labels[i]);}
 v->figure_axis_labels[axis]=std::move(next);return GX3DE_OK;
}
gx3de_result gx3de_view_scientific_figure_get(gx3de_view* v,gx3de_scientific_figure* f) {
    if(!v||!f||f->struct_size<sizeof(*f))return GX3DE_INVALID_ARGUMENT;
    *f=v->figure;f->struct_size=sizeof(*f);return GX3DE_OK;
}
static void figure_rect(const gx3de_view* v,double& x,double& y,double& w,double& h,uint32_t pixelsHigh) {
    x=0;y=0;w=1;h=1;
    if(v->figure.enabled){
        const double scale=std::max(.8,std::min(1.0,double(pixelsHigh)/640));
        const double axisFont=scientific_style(v,"axis_label_font_size",14*scale);
        const double titleFont=scientific_style(v,"title_font_size",18*scale);
        const double legendFont=v->figure.legend_utf8[0]?scientific_style(v,"legend_font_size",12*scale):0;
        // Reserve real text space in automatic layout. Explicit scientific
        // margins remain authoritative; pan and both projection directions use
        // this exact same rectangle as the native rendering viewport.
        const double top=std::max(.14,std::min(.30,(5*axisFont+titleFont+legendFont+16)/std::max(1u,pixelsHigh)));
        const double bottom=std::max(.13,std::min(.25,(3*axisFont+16)/std::max(1u,pixelsHigh)));
        x=scientific_style(v,"margin_left",.09);y=scientific_style(v,"margin_bottom",bottom);
        w=1-x-scientific_style(v,"margin_right",v->figure.colorbar_visible?.23:.11);
        h=1-y-scientific_style(v,"margin_top",top);
    }
}
static double camera_ortho_height(const gx3de_view* v) {
    return v->orthographic_height>0?v->orthographic_height:
        2*length(sub(v->camera.position,v->camera.target))*
        std::tan(v->camera.vertical_fov_degrees*3.141592653589793/360.0);
}
gx3de_result gx3de_view_orthographic_height_set(gx3de_view* v,double height) {
    if(!v||!std::isfinite(height)||height<=0)return GX3DE_INVALID_ARGUMENT;
    v->orthographic_height=height;return GX3DE_OK;
}
gx3de_result gx3de_view_orthographic_height_get(gx3de_view* v,double* height) {
    if(!v||!height)return GX3DE_INVALID_ARGUMENT;
    *height=camera_ortho_height(v);return GX3DE_OK;
}
gx3de_result gx3de_view_camera_orbit(gx3de_view* v,double yaw,double pitch,const gx3de_vec3* pivot) {
    if(!v||!std::isfinite(yaw)||!std::isfinite(pitch)||
       (pivot&&!finite(*pivot)))return GX3DE_INVALID_ARGUMENT;
    auto c=v->camera;const auto center=pivot?*pivot:c.target;
    auto forward=mul(sub(c.target,c.position),1.0/length(sub(c.target,c.position)));
    auto right=cross(forward,c.up);right=mul(right,1.0/length(right));
    const auto up=mul(cross(right,forward),1.0/length(cross(right,forward)));
    auto offset=sub(c.position,center),target_offset=sub(c.target,center);
    offset=camera_rotate(offset,up,yaw);target_offset=camera_rotate(target_offset,up,yaw);
    right=camera_rotate(right,up,yaw);
    offset=camera_rotate(offset,right,pitch);target_offset=camera_rotate(target_offset,right,pitch);
    c.position=add(center,offset);c.target=add(center,target_offset);
    c.up=camera_rotate(camera_rotate(up,up,yaw),right,pitch);
    return gx3de_view_set_camera(v,&c);
}
gx3de_result gx3de_view_camera_pan(gx3de_viewport* vp,double dx,double dy) {
    if(!vp||!std::isfinite(dx)||!std::isfinite(dy))return GX3DE_INVALID_ARGUMENT;
    auto c=vp->view->camera;const auto forward=mul(sub(c.target,c.position),
        1.0/length(sub(c.target,c.position)));
    auto right=cross(forward,c.up);right=mul(right,1.0/length(right));
    auto up=cross(right,forward);
    const double height=c.orthographic?camera_ortho_height(vp->view):
        2*length(sub(c.position,c.target))*
        std::tan(c.vertical_fov_degrees*3.141592653589793/360.0);
    double sx,sy,sw,sh;figure_rect(vp->view,sx,sy,sw,sh,vp->height);
    const auto move=add(mul(right,-dx*height/(vp->height*sh)),mul(up,dy*height/(vp->height*sh)));
    c.position=add(c.position,move);c.target=add(c.target,move);
    return gx3de_view_set_camera(vp->view,&c);
}
gx3de_result gx3de_view_camera_dolly(gx3de_view* v,double factor) {
    if(!v||!std::isfinite(factor)||factor<=0)return GX3DE_INVALID_ARGUMENT;
    auto c=v->camera;c.position=add(c.target,mul(sub(c.position,c.target),1.0/factor));
    return gx3de_view_set_camera(v,&c);
}
gx3de_result gx3de_view_camera_zoom(gx3de_view* v,double factor) {
    if(!v||!std::isfinite(factor)||factor<=0)return GX3DE_INVALID_ARGUMENT;
    if(v->camera.orthographic){const double height=camera_ortho_height(v)/factor;
        if(!std::isfinite(height)||height<=1e-12)return GX3DE_RANGE;
        v->orthographic_height=height;return GX3DE_OK;}
    auto c=v->camera;const double fov=c.vertical_fov_degrees/factor;
    if(!std::isfinite(fov)||fov<=0.01||fov>=179)return GX3DE_RANGE;
    c.vertical_fov_degrees=fov;return gx3de_view_set_camera(v,&c);
}
gx3de_result gx3de_viewport_world_to_screen(gx3de_viewport* vp,gx3de_vec3 world,
                                             double* x,double* y,double* depth) {
    if(!vp||!x||!y||!depth||!finite(world))return GX3DE_INVALID_ARGUMENT;
    const auto& c=vp->view->camera;
    const auto forward=mul(sub(c.target,c.position),1.0/length(sub(c.target,c.position)));
    auto right=cross(forward,c.up);right=mul(right,1.0/length(right));
    const auto up=cross(right,forward),delta=sub(world,c.position);
    const double z=dot(delta,forward);if(z<=0)return GX3DE_RANGE;
    const double half_height=c.orthographic?camera_ortho_height(vp->view)*0.5:
        z*std::tan(c.vertical_fov_degrees*3.141592653589793/360.0);
    double sx,sy,sw,sh;figure_rect(vp->view,sx,sy,sw,sh,vp->height);
    const double width=vp->width*sw,height=vp->height*sh;
    const double half_width=half_height*width/height;
    *x=sx*vp->width+(dot(delta,right)/half_width+1.0)*width*0.5-0.5;
    *y=(1-sy-sh)*vp->height+(1.0-dot(delta,up)/half_height)*height*0.5-0.5;
    *depth=z;return GX3DE_OK;
}
gx3de_result gx3de_viewport_screen_to_world(gx3de_viewport* vp,double x,double y,double depth,
                                             gx3de_vec3* world_point) {
    if(!vp||!world_point||!std::isfinite(x)||!std::isfinite(y)||
       !std::isfinite(depth)||depth<=0)return GX3DE_INVALID_ARGUMENT;
    const auto& c=vp->view->camera;
    const auto forward=mul(sub(c.target,c.position),1.0/length(sub(c.target,c.position)));
    auto right=cross(forward,c.up);right=mul(right,1.0/length(right));
    const auto up=cross(right,forward);
    const double half_height=c.orthographic?camera_ortho_height(vp->view)*0.5:
        depth*std::tan(c.vertical_fov_degrees*3.141592653589793/360.0);
    double sx,sy,sw,sh;figure_rect(vp->view,sx,sy,sw,sh,vp->height);
    const double width=vp->width*sw,height=vp->height*sh;
    const double nx=(2*(x-sx*vp->width+0.5)/width-1)*half_height*width/height;
    const double ny=(1-2*(y-(1-sy-sh)*vp->height+0.5)/height)*half_height;
    *world_point=add(c.position,add(mul(forward,depth),add(mul(right,nx),mul(up,ny))));
    return GX3DE_OK;
}
gx3de_result gx3de_view_background_set(gx3de_view* v,const gx3de_view_background* b) {
    if(!v||!b||b->struct_size<sizeof(*b)||b->gradient>1||
       !renderer_valid_rgb(b->top)||!renderer_valid_rgb(b->bottom))return GX3DE_INVALID_ARGUMENT;
    v->background=*b;v->background.struct_size=sizeof(*b);return GX3DE_OK;
}
gx3de_result gx3de_view_background_get(gx3de_view* v,gx3de_view_background* b) {
    if(!v||!b||b->struct_size<sizeof(*b))return GX3DE_INVALID_ARGUMENT;*b=v->background;return GX3DE_OK;
}
static bool navcube_valid_region(uint32_t region) {return region<=27&&region!=14;}
static gx3de_vec3 navcube_direction(uint32_t region) {
    const int code=int(region)-1;
    return {double(code/9-1),double(code/3%3-1),double(code%3-1)};
}
static uint32_t navcube_synced(const gx3de_view* v) {
    auto d=sub(v->camera.position,v->camera.target);d=mul(d,1.0/length(d));
    double best=-2;uint32_t region=0;
    for(uint32_t i=1;i<=27;++i)if(navcube_valid_region(i)){
        auto c=navcube_direction(i);if(length(c)<0.5)continue;
        const double score=dot(d,mul(c,1.0/length(c)));
        if(score>best){best=score;region=i;}}
    return region;
}
gx3de_result gx3de_view_checkerboard_set(gx3de_view* v,const gx3de_checkerboard_background* b) {
    if(!v||!b||b->struct_size<sizeof(*b)||b->enabled>1||
       b->checker_pixels<4||b->checker_pixels>512||
       !renderer_valid_rgb(b->first)||!renderer_valid_rgb(b->second))return GX3DE_INVALID_ARGUMENT;
    v->checkerboard=*b;v->checkerboard.struct_size=sizeof(*b);
    for(auto* vp:v->viewports)vp->target->render_key.clear();
    return GX3DE_OK;
}
gx3de_result gx3de_view_checkerboard_get(gx3de_view* v,gx3de_checkerboard_background* b) {
    if(!v||!b||b->struct_size<sizeof(*b))return GX3DE_INVALID_ARGUMENT;
    *b=v->checkerboard;return GX3DE_OK;
}
gx3de_result gx3de_view_navcube_set(gx3de_view* v,const gx3de_navcube_state* s) {
    if(!v||!s||s->struct_size<sizeof(*s)||s->visible>1||s->corner>3||
       s->size_pixels<64||s->size_pixels>512||s->margin_pixels>512||
       !navcube_valid_region(s->hover_region)||
       !navcube_valid_region(s->active_region))return GX3DE_INVALID_ARGUMENT;
    v->navcube=*s;v->navcube.struct_size=sizeof(*s);
    v->navcube.synced_region=navcube_synced(v);
    return GX3DE_OK;
}
gx3de_result gx3de_view_orientation_indicator_set(gx3de_view* v,const gx3de_orientation_indicator* s) {
    if(!v||!s||s->struct_size<sizeof(*s)||s->visible>1||s->corner>3||
       s->size_pixels<48||s->size_pixels>256||s->margin_pixels>128)return GX3DE_INVALID_ARGUMENT;
    v->orientation=*s;v->orientation.struct_size=sizeof(*s);return GX3DE_OK;
}
gx3de_result gx3de_view_orientation_indicator_get(gx3de_view* v,gx3de_orientation_indicator* s) {
    if(!v||!s||s->struct_size<sizeof(*s))return GX3DE_INVALID_ARGUMENT;
    *s=v->orientation;return GX3DE_OK;
}
gx3de_result gx3de_view_navcube_get(gx3de_view* v,gx3de_navcube_state* s) {
    if(!v||!s||s->struct_size<sizeof(*s))return GX3DE_INVALID_ARGUMENT;
    *s=v->navcube;s->synced_region=navcube_synced(v);return GX3DE_OK;
}
gx3de_result gx3de_view_navcube_hover_set(gx3de_view* v,uint32_t region) {
    if(!v||!navcube_valid_region(region))return GX3DE_INVALID_ARGUMENT;
    v->navcube.hover_region=region;return GX3DE_OK;
}
gx3de_result gx3de_view_navcube_select(gx3de_view* v,uint32_t region) {
    if(!v||!region||!navcube_valid_region(region))return GX3DE_INVALID_ARGUMENT;
    auto direction=navcube_direction(region);
    direction=mul(direction,1.0/length(direction));
    auto camera=v->camera;
    const double distance=length(sub(camera.position,camera.target));
    camera.position=add(camera.target,mul(direction,distance));
    camera.up=std::abs(direction.z)>.99?gx3de_vec3{0,1,0}:gx3de_vec3{0,0,1};
    auto rc=gx3de_view_set_camera(v,&camera);
    if(rc==GX3DE_OK){v->navcube.active_region=region;v->navcube.synced_region=region;}
    return rc;
}
gx3de_result gx3de_viewport_navcube_pick(gx3de_viewport* vp,uint32_t x,uint32_t y,uint32_t* region) {
    if(!vp||!region)return GX3DE_INVALID_ARGUMENT;
    *region=0;const auto& s=vp->view->navcube;
    if(!s.visible||x>=vp->width||y>=vp->height)return GX3DE_OK;
    const double size=std::min({double(s.size_pixels),double(vp->width)-2*s.margin_pixels,
                                double(vp->height)-2*s.margin_pixels});
    if(size<=0)return GX3DE_OK;
    const double left=(s.corner&1u)?vp->width-s.margin_pixels-size:s.margin_pixels;
    const double top=(s.corner&2u)?vp->height-s.margin_pixels-size:s.margin_pixels;
    if(x<left||x>=left+size||y<top||y>=top+size)return GX3DE_OK;
    const auto& c=vp->view->camera;
    auto eye=sub(c.position,c.target);eye=mul(eye,1.0/length(eye));
    auto forward=mul(eye,-1);auto right=cross(forward,c.up);
    right=mul(right,1.0/length(right));auto up=cross(right,forward);
    const double scale=std::tan(35.0*3.141592653589793/360.0);
    const double nx=(2.0*(x-left+0.5)/size-1.0)*scale;
    const double ny=(1.0-2.0*(y-top+0.5)/size)*scale;
    auto ray=add(forward,add(mul(right,nx),mul(up,ny)));
    auto origin=mul(eye,5.0);double best=1e10;
    for(int sx=-1;sx<=1;++sx)for(int sy=-1;sy<=1;++sy)
        for(int sz=-1;sz<=1;++sz){
            if(!sx&&!sy&&!sz)continue;
            const int signs[3]={sx,sy,sz};double lo=0,hi=1e10;
            for(int axis=0;axis<3;++axis){
                const int sign=signs[axis];
                const double center=sign*.79,half=sign?.20:.58;
                const double o=axis==0?origin.x:axis==1?origin.y:origin.z;
                const double d=axis==0?ray.x:axis==1?ray.y:ray.z;
                if(std::abs(d)<1e-12){
                    if(o<center-half||o>center+half){lo=1;hi=0;break;}
                    continue;
                }
                double a=(center-half-o)/d,b=(center+half-o)/d;
                if(a>b)std::swap(a,b);
                lo=std::max(lo,a);hi=std::min(hi,b);
                if(lo>hi)break;
            }
            if(lo<=hi&&lo<best){
                best=lo;*region=uint32_t(1+9*(sx+1)+3*(sy+1)+(sz+1));
            }
        }
    return GX3DE_OK;
}
gx3de_result gx3de_viewport_navcube_click(gx3de_viewport* vp,uint32_t x,uint32_t y,uint32_t* region) {
    uint32_t selected=0;auto rc=gx3de_viewport_navcube_pick(vp,x,y,&selected);
    if(rc!=GX3DE_OK)return rc;if(region)*region=selected;
    return selected?gx3de_view_navcube_select(vp->view,selected):GX3DE_OK;
}
gx3de_result gx3de_view_lighting_set(gx3de_view* v,const gx3de_view_lighting* l) {
    if(!v||!l||l->struct_size<sizeof(*l)||l->enabled>1||l->light_count>4||
       !std::isfinite(l->ambient)||l->ambient<0||l->ambient>1||
       !std::isfinite(l->diffuse)||l->diffuse<0||l->diffuse>1||
       !std::isfinite(l->specular)||l->specular<0||l->specular>1)return GX3DE_INVALID_ARGUMENT;
    for(uint32_t i=0;i<l->light_count;++i){const auto& light=l->lights[i];
        if(!finite(light.direction)||length(light.direction)<1e-12||
           !renderer_valid_rgb(light.color)||!std::isfinite(light.intensity)||
           light.intensity<0||light.intensity>10)return GX3DE_INVALID_ARGUMENT;}
    v->lighting=*l;v->lighting.struct_size=sizeof(*l);return GX3DE_OK;
}
gx3de_result gx3de_view_lighting_get(gx3de_view* v,gx3de_view_lighting* l) {
    if(!v||!l||l->struct_size<sizeof(*l))return GX3DE_INVALID_ARGUMENT;*l=v->lighting;return GX3DE_OK;
}
gx3de_result gx3de_view_positional_light_set(gx3de_view* v,uint32_t slot,const gx3de_positional_light* l){
    if(!v||slot>=4||!l||l->struct_size<sizeof(*l)||l->enabled>1||
       (l->enabled&&(!finite(l->position)||!cloud_color(l->color)||
        !std::isfinite(l->intensity)||l->intensity<0||l->intensity>10||
        !std::isfinite(l->attenuation_constant)||l->attenuation_constant<0||
        !std::isfinite(l->attenuation_linear)||l->attenuation_linear<0||
        !std::isfinite(l->attenuation_quadratic)||l->attenuation_quadratic<0||
        l->attenuation_constant+l->attenuation_linear+l->attenuation_quadratic<=0)))
        return GX3DE_INVALID_ARGUMENT;
    v->positional_lights[slot]=*l;v->positional_lights[slot].struct_size=sizeof(*l);return GX3DE_OK;
}
gx3de_result gx3de_view_positional_light_get(gx3de_view* v,uint32_t slot,gx3de_positional_light* l){
    if(!v||slot>=4||!l||l->struct_size<sizeof(*l))return GX3DE_INVALID_ARGUMENT;
    *l=v->positional_lights[slot];return GX3DE_OK;
}
gx3de_result gx3de_view_lighting_preset(gx3de_view* v,uint32_t preset) {
    if(!v||preset<GX3DE_LIGHT_SCIENTIFIC_NEUTRAL||preset>GX3DE_LIGHT_FLAT_UNLIT)
        return GX3DE_INVALID_ARGUMENT;
    gx3de_view_lighting l{};l.struct_size=sizeof(l);l.enabled=preset!=GX3DE_LIGHT_FLAT_UNLIT;
    l.light_count=l.enabled?2:0;
    switch(preset){
    case GX3DE_LIGHT_SCIENTIFIC_NEUTRAL:l.ambient=.28;l.diffuse=.72;l.specular=.12;break;
    case GX3DE_LIGHT_HIGH_CONTRAST:l.ambient=.10;l.diffuse=.90;l.specular=.48;break;
    case GX3DE_LIGHT_SOFT_DIFFUSE:l.ambient=.42;l.diffuse=.58;l.specular=.04;break;
    default:l.ambient=1;l.diffuse=0;l.specular=0;break;
    }
    l.lights[0]={{-.4,-.5,-1},{1,1,1},1};
    l.lights[1]={{.7,.2,-.6},{.82,.88,1},preset==GX3DE_LIGHT_HIGH_CONTRAST?.20:.46};
    return gx3de_view_lighting_set(v,&l);
}
gx3de_result gx3de_image_output_info_get(gx3de_image_output_info* out) {
    if(!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    gx3de_image_output_info info{};info.struct_size=sizeof(info);
    info.component_count=4;info.bits_per_component=8;
    info.alpha_convention=GX3DE_ALPHA_STRAIGHT;
    info.transfer=GX3DE_IMAGE_TRANSFER_SRGB;
    info.png_transfer=GX3DE_IMAGE_TRANSFER_SRGB;
    info.png_color_tag=GX3DE_PNG_COLOR_UNTAGGED;
    std::memcpy(info.component_order,"RGBA",5);
    *out=info;return GX3DE_OK;
}
gx3de_result gx3de_view_clip_box_set(gx3de_view* v,const gx3de_view_clip_box* box) {
    if(!v||!box||box->struct_size<sizeof(*box)||box->enabled>1)return GX3DE_INVALID_ARGUMENT;
    if(box->enabled&&(!finite(box->world_bounds.min)||!finite(box->world_bounds.max)||
       box->world_bounds.min.x>=box->world_bounds.max.x||
       box->world_bounds.min.y>=box->world_bounds.max.y||
       box->world_bounds.min.z>=box->world_bounds.max.z))return GX3DE_INVALID_ARGUMENT;
    v->clip_box=*box;v->clip_box.struct_size=sizeof(*box);return GX3DE_OK;
}
gx3de_result gx3de_view_clip_box_get(gx3de_view* v,gx3de_view_clip_box* box) {
    if(!v||!box||box->struct_size<sizeof(*box))return GX3DE_INVALID_ARGUMENT;
    *box=v->clip_box;return GX3DE_OK;
}
gx3de_result gx3de_view_set_working_plane(gx3de_view* v,gx3de_plane* p) { if(!v)return GX3DE_INVALID_ARGUMENT;if(p&&p->scene!=v->scene)return GX3DE_WRONG_OWNER;v->working_plane=p;return GX3DE_OK; }
gx3de_result gx3de_view_get_working_plane(gx3de_view* v,gx3de_plane** p) { if(!v||!p)return GX3DE_INVALID_ARGUMENT;*p=v->working_plane;return GX3DE_OK; }
gx3de_result gx3de_view_set_selection(gx3de_view* v,gx3de_anchor* a) { if(!v)return GX3DE_INVALID_ARGUMENT;if(a&&a->scene!=v->scene)return GX3DE_WRONG_OWNER;v->selection=a;return GX3DE_OK; }
gx3de_result gx3de_view_get_selection(gx3de_view* v,gx3de_anchor** a) { if(!v||!a)return GX3DE_INVALID_ARGUMENT;*a=v->selection;return GX3DE_OK; }
gx3de_result gx3de_view_clip_plane_set(gx3de_view* v,uint32_t slot,const gx3de_view_clip_plane* clip) {
    if(!v||!clip||clip->struct_size<sizeof(gx3de_view_clip_plane))return GX3DE_INVALID_ARGUMENT;
    if(slot>=GX3DE_MAX_VIEW_CLIP_PLANES)return GX3DE_RANGE;
    if(clip->enabled>1||clip->keep_positive>1)return GX3DE_INVALID_ARGUMENT;
    if(!clip->enabled){v->clips[slot]={sizeof(gx3de_view_clip_plane),0,{},{},0,0,{}};return GX3DE_OK;}
    if(!finite(clip->origin)||!finite(clip->normal))return GX3DE_INVALID_ARGUMENT;
    double magnitude=length(clip->normal);if(!(magnitude>1e-15)||!std::isfinite(magnitude))return GX3DE_DEGENERATE;
    v->clips[slot]={sizeof(gx3de_view_clip_plane),1,clip->origin,mul(clip->normal,1/magnitude),clip->keep_positive,0,{}};
    return GX3DE_OK;
}
gx3de_result gx3de_view_clip_plane_get(gx3de_view* v,uint32_t slot,gx3de_view_clip_plane* clip) {
    if(!v||!clip||clip->struct_size<sizeof(gx3de_view_clip_plane))return GX3DE_INVALID_ARGUMENT;
    if(slot>=GX3DE_MAX_VIEW_CLIP_PLANES)return GX3DE_RANGE;
    *clip=v->clips[slot];clip->struct_size=sizeof(gx3de_view_clip_plane);return GX3DE_OK;
}
gx3de_result gx3de_view_interaction_set(gx3de_view* v,const gx3de_view_interaction* interaction) {
    if(!v||!interaction||interaction->struct_size<sizeof(gx3de_view_interaction))return GX3DE_INVALID_ARGUMENT;
    if(interaction->mode>GX3DE_INTERACTION_DRAG)return GX3DE_INVALID_ARGUMENT;
    if(interaction->mode!=GX3DE_INTERACTION_NONE&&(!finite(interaction->start_world)||!finite(interaction->current_world)))return GX3DE_INVALID_ARGUMENT;
    v->interaction={sizeof(gx3de_view_interaction),interaction->mode,interaction->mode?interaction->start_world:gx3de_vec3{},interaction->mode?interaction->current_world:gx3de_vec3{},interaction->mode?interaction->pointer_id:0,{}};
    return GX3DE_OK;
}
gx3de_result gx3de_view_interaction_get(gx3de_view* v,gx3de_view_interaction* interaction) {
    if(!v||!interaction||interaction->struct_size<sizeof(gx3de_view_interaction))return GX3DE_INVALID_ARGUMENT;
    *interaction=v->interaction;interaction->struct_size=sizeof(gx3de_view_interaction);return GX3DE_OK;
}
gx3de_result gx3de_viewport_create(gx3de_target* t,gx3de_view* v,uint32_t x,uint32_t y,uint32_t w,uint32_t h,gx3de_viewport** out) { if(!t||!v||!out||!w||!h)return GX3DE_INVALID_ARGUMENT;if(t->engine!=v->scene->engine)return GX3DE_WRONG_OWNER;if(uint64_t(x)+w>t->width||uint64_t(y)+h>t->height)return GX3DE_RANGE;auto p=new(std::nothrow) gx3de_viewport{t,v,x,y,w,h};if(!p)return GX3DE_OUT_OF_MEMORY;try {t->viewports.push_back(p);v->viewports.push_back(p);*out=p;return GX3DE_OK;}catch(const std::bad_alloc&){erase_ptr(t->viewports,p);delete p;return GX3DE_OUT_OF_MEMORY;} }
gx3de_result gx3de_viewport_destroy(gx3de_viewport* p) { if(!p)return GX3DE_INVALID_ARGUMENT;remove_viewport(p);return GX3DE_OK; }
gx3de_result gx3de_viewport_size(gx3de_viewport* p,uint32_t* x,uint32_t* y,uint32_t* w,uint32_t* h) { if(!p||!x||!y||!w||!h)return GX3DE_INVALID_ARGUMENT;*x=p->x;*y=p->y;*w=p->width;*h=p->height;return GX3DE_OK; }
gx3de_result gx3de_viewport_rect_set(gx3de_viewport* p,uint32_t x,uint32_t y,uint32_t w,uint32_t h) {
    if(!p||!w||!h)return GX3DE_INVALID_ARGUMENT;
    if(uint64_t(x)+w>p->target->width||uint64_t(y)+h>p->target->height)return GX3DE_RANGE;
    p->x=x;p->y=y;p->width=w;p->height=h;p->target->rgba.clear();return GX3DE_OK;
}
static gx3de_result pick_volume_data(gx3de_viewport* vp,const gx3de_render_viewport& rv,
                                     uint32_t x,uint32_t y,gx3de_pick_hit* out) {
    gx3de_ray ray{sizeof(gx3de_ray)};
    auto result=gx3de_viewport_ray(vp,x,y,&ray);if(result!=GX3DE_OK)return result;
    double closest=std::numeric_limits<double>::infinity();gx3de_pick_hit selected{};
    for(const auto& entry:rv.volumes){auto* object=entry.second;
        if(!object||!object->scientific||!object->visible)continue;
        auto* image=vtkImageData::SafeDownCast(object->scientific->dataset);
        if(!image)continue;
        auto* scalar=scientific_array_by_index(*object->scientific,object->volume_style.scalar_array);
        if(!scalar)continue;
        gx3de_mat4 inverse{};if(!inverse_affine(world(object),inverse))continue;
        const auto origin=apply(inverse,ray.origin);
        const auto next=apply(inverse,add(ray.origin,ray.direction));
        const auto direction=sub(next,origin);
        double bounds[6];image->GetBounds(bounds);
        double start=std::max(0.0,vp->view->camera.near_clip);
        double end=vp->view->camera.far_clip;
        const double coordinates[3]={origin.x,origin.y,origin.z};
        const double directions[3]={direction.x,direction.y,direction.z};
        bool intersects=true;
        for(int axis=0;axis<3;++axis){const double low=bounds[2*axis],high=bounds[2*axis+1];
            if(std::abs(directions[axis])<1e-15){
                if(coordinates[axis]<low||coordinates[axis]>high)intersects=false;
            }else{double a=(low-coordinates[axis])/directions[axis];
                double b=(high-coordinates[axis])/directions[axis];if(a>b)std::swap(a,b);
                start=std::max(start,a);end=std::min(end,b);}
        }
        if(!intersects||end<start||start>=closest)continue;
        const double step=std::max(object->volume_style.sample_distance,(end-start)/4096.0);
        for(double t=start;t<=end&&t<closest;t+=step){
            const auto local=add(origin,mul(direction,t));
            const auto world_point=add(ray.origin,mul(ray.direction,t));
            const auto& box=vp->view->clip_box;
            if(box.enabled&&(world_point.x<box.world_bounds.min.x||
               world_point.x>box.world_bounds.max.x||world_point.y<box.world_bounds.min.y||
               world_point.y>box.world_bounds.max.y||world_point.z<box.world_bounds.min.z||
               world_point.z>box.world_bounds.max.z))continue;
            bool clipped=false;for(const auto& plane:vp->view->clips)if(plane.enabled){
                const double side=dot(sub(world_point,plane.origin),plane.normal);
                if((plane.keep_positive&&side<0)||(!plane.keep_positive&&side>0)){
                    clipped=true;break;}}
            if(clipped)continue;
            double xyz[3]={local.x,local.y,local.z};
            const auto index=image->FindPoint(xyz);if(index<0)continue;
            const double value=scalar->GetComponent(index,0);
            double alpha=0;
            const auto& style=object->volume_style;
            for(uint32_t i=1;i<style.transfer_count;++i){
                const auto& lo=style.transfer[i-1];const auto& hi=style.transfer[i];
                if(value<lo.scalar)break;
                if(value<=hi.scalar){const double mix=(value-lo.scalar)/(hi.scalar-lo.scalar);
                    alpha=lo.opacity+(hi.opacity-lo.opacity)*mix;break;}
                alpha=hi.opacity;
            }
            if(alpha*object->opacity<0.04)continue;
            selected={sizeof(gx3de_pick_hit),GX3DE_PICK_SCIENTIFIC,object,
                UINT64_MAX,UINT64_MAX,world_point,local,{0,0,0},0,0,0,0,0,0,0,{}};
            closest=t;break;
        }
    }
    if(!std::isfinite(closest))return GX3DE_NOT_FOUND;
    *out=selected;return GX3DE_OK;
}
gx3de_result gx3de_viewport_pick(gx3de_viewport* vp,uint32_t x,uint32_t y,gx3de_pick_hit* out) {
    if(!vp||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(x>=vp->width||y>=vp->height)return GX3DE_RANGE;
    auto rc=gx3de_target_render(vp->target);if(rc!=GX3DE_OK)return rc;
    auto it=std::find_if(vp->target->rendered.begin(),vp->target->rendered.end(),
                         [vp](const gx3de_render_viewport& rv){return rv.viewport==vp;});
    if(it==vp->target->rendered.end())return GX3DE_NOT_FOUND;
    vtkNew<vtkCellPicker> picker;
    // VTK 9.3 measures this fraction at the midpoint of the near/far ray,
    // rather than at the scientific focal plane. A fixed .001 therefore
    // grows to several model units with a distant far clip and can accept a
    // triangle-plane extension outside the actual object. Keep the admission
    // radius at .75 viewport pixels at the focal plane, independent of clip
    // depth. This changes picking only, not geometry, camera or rendering.
    picker->SetTolerance(viewport_pick_tolerance(vp,.75));
    picker->PickFromListOn();for(const auto& prop:it->props)picker->AddPickList(prop.actor);
    const int px=int(vp->x+x),py=int(vp->target->height-1-(vp->y+y));
    if(!picker->Pick(px,py,0,it->renderer))return pick_volume_data(vp,*it,x,y,out);
    auto* actor=picker->GetActor();if(!actor)return pick_volume_data(vp,*it,x,y,out);
    auto prop=std::find_if(it->props.begin(),it->props.end(),
        [actor](const gx3de_render_prop& p){return p.actor==actor;});
    if(prop==it->props.end()||!prop->object||prop->gizmo)return GX3DE_NOT_FOUND;
    double* xyz=picker->GetPickPosition();gx3de_vec3 point{xyz[0],xyz[1],xyz[2]};
    gx3de_mat4 inverse{};const auto local_pose=prop->geometry_kind==GX3DE_PICK_SCIENTIFIC?
        world(prop->object):prop->pose;
    if(!inverse_affine(local_pose,inverse))return GX3DE_DEGENERATE;
    auto local=apply(inverse,point);
    double* n=picker->GetPickNormal();gx3de_vec3 normal{n[0],n[1],n[2]};
    const double norm=length(normal);const bool have_normal=std::isfinite(norm)&&norm>1e-12;
    if(have_normal)normal=mul(normal,1.0/norm);else normal={};
    const auto cell=picker->GetCellId(),vertex=picker->GetPointId();
    uint64_t point_index=vertex<0?UINT64_MAX:static_cast<uint64_t>(vertex);
    if(prop->geometry_kind==GX3DE_PICK_SCIENTIFIC){point_index=UINT64_MAX;
        auto* data=prop->object->scientific->dataset.GetPointer();
        if(data&&data->GetNumberOfPoints()>0&&data->GetNumberOfPoints()<=1000000){
            vtkNew<vtkPointLocator> locator;locator->SetDataSet(data);locator->BuildLocator();
            double query[3]={local.x,local.y,local.z};
            const vtkIdType nearest=locator->FindClosestPoint(query);
            if(nearest>=0){double xyz[3];data->GetPoint(nearest,xyz);
                const auto source_world=apply(world(prop->object),gx3de_vec3{xyz[0],xyz[1],xyz[2]});
                double radius=renderer_pixel_world(vp,point,
                    std::max(6.0,prop->object->style.point_size))*2.0;
                const auto role=prop->object->field_roles.radius_array;
                if(role>=0){auto* array=scientific_array_by_index(*prop->object->scientific,
                    static_cast<uint64_t>(role),nullptr);
                    if(array&&nearest<array->GetNumberOfTuples())
                        radius=std::max(radius,array->GetComponent(nearest,0)*1.2);}
                if(length(sub(source_world,point))<=radius)point_index=static_cast<uint64_t>(nearest);}}}
    gx3de_pick_hit hit{sizeof(*out),prop->geometry_kind,prop->object,
        cell<0||prop->derived_lod?UINT64_MAX:static_cast<uint64_t>(cell),
        prop->derived_lod?UINT64_MAX:point_index,
        point,local,normal,static_cast<uint32_t>(have_normal),0,0,0,0,0,0,{}};
#ifdef GX3DE_WITH_OCCT
    if(prop->geometry_kind==GX3DE_PICK_BREP_DISPLAY&&prop->object->brep){
        uint64_t face=0;double u=0,v=0;std::string error;
        if(gx3de_backend::closest_face_fraction(*prop->object->brep,local,0.1,
                                                 face,u,v,error)){
            hit.topology_index=face;hit.topology_u=u;hit.topology_v=v;
            hit.has_topology=1;}}
#endif
    *out=hit;
    return GX3DE_OK;
}
gx3de_result gx3de_pick_make_anchor(gx3de_viewport* vp,const gx3de_pick_hit* hit,
                                     gx3de_anchor** out) {
    if(!vp||!hit||!out||hit->struct_size<sizeof(*hit)||!hit->object||
       !finite(hit->local_point))return GX3DE_INVALID_ARGUMENT;
    auto* scene=vp->view->scene;
    if(std::find(scene->objects.begin(),scene->objects.end(),hit->object)==scene->objects.end())
        return GX3DE_WRONG_OWNER;
    auto* object=hit->object;
    if(hit->geometry_kind==GX3DE_PICK_REPEAT)
        return gx3de_anchor_free(scene,hit->world_point,out); /* captured occurrence */
    if(hit->geometry_kind==GX3DE_PICK_SCIENTIFIC&&object->scientific&&
       hit->point_index!=UINT64_MAX){gx3de_vec3 exact{};
        if(gx3de_scientific_point(object,hit->point_index,0,&exact)==GX3DE_OK)
            return gx3de_anchor_object_point(object,exact,out);}
#ifdef GX3DE_WITH_OCCT
    if(hit->geometry_kind==GX3DE_PICK_BREP_DISPLAY&&object->brep&&hit->has_topology){
        auto rc=gx3de_anchor_brep_face(object,hit->topology_index,
                                      hit->topology_u,hit->topology_v,out);
        if(rc==GX3DE_OK)return rc;
    }
#endif
    if(hit->geometry_kind==GX3DE_PICK_MESH&&object->mesh&&
       hit->cell_index<object->mesh->triangles.size()/3){
        const auto& m=*object->mesh;const size_t index=size_t(hit->cell_index)*3;
        const auto a=m.vertices[m.triangles[index]],b=m.vertices[m.triangles[index+1]],
                   c=m.vertices[m.triangles[index+2]];
        const auto v0=sub(b,a),v1=sub(c,a),v2=sub(hit->local_point,a);
        const double d00=dot(v0,v0),d01=dot(v0,v1),d11=dot(v1,v1),
                     d20=dot(v2,v0),d21=dot(v2,v1),denom=d00*d11-d01*d01;
        if(std::isfinite(denom)&&std::abs(denom)>1e-20){
            const double u=(d11*d20-d01*d21)/denom,v=(d00*d21-d01*d20)/denom;
            if(u>=-1e-5&&v>=-1e-5&&u+v<=1+1e-5)
                return gx3de_anchor_object_face(object,hit->cell_index,
                    std::clamp(u,0.0,1.0),std::clamp(v,0.0,1.0-std::clamp(u,0.0,1.0)),out);
        }
    }
    return gx3de_anchor_object_point(object,hit->local_point,out);
}
}
#include "native_3d_comparison_v1.inc"
