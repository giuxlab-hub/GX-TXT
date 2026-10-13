// SPDX-License-Identifier: GPL-3.0-or-later
// Object-local, source-mesh planar texture assignments. Included inside the
// public API translation unit after the opaque handle definitions.
namespace {
struct PlanarUvVertex { gx3de_vec3 point;double u,v; };
static uint64_t planar_edge(uint32_t a,uint32_t b) {
    if(a>b)std::swap(a,b);
    return (uint64_t(a)<<32)|b;
}
static bool planar_inside(gx3de_vec3 p,gx3de_vec3 a,gx3de_vec3 b,gx3de_vec3 c,
                          gx3de_vec3 n,double tolerance) {
    if(std::abs(dot(sub(p,a),n))>tolerance)return false;
    auto e0=sub(b,a),e1=sub(c,a),e2=sub(p,a);
    const double d00=dot(e0,e0),d01=dot(e0,e1),d11=dot(e1,e1);
    const double d20=dot(e2,e0),d21=dot(e2,e1),den=d00*d11-d01*d01;
    if(!(den>0))return false;
    const double u=(d11*d20-d01*d21)/den,v=(d00*d21-d01*d20)/den;
    return u>=-1e-6&&v>=-1e-6&&u+v<=1.000001;
}
static PlanarUvVertex planar_lerp(const PlanarUvVertex& a,const PlanarUvVertex& b,
                                  double t) {
    return {add(a.point,mul(sub(b.point,a.point),t)),a.u+(b.u-a.u)*t,
            a.v+(b.v-a.v)*t};
}
static std::vector<PlanarUvVertex> planar_clip(const std::vector<PlanarUvVertex>& input,
                                               int axis,double bound,bool greater) {
    std::vector<PlanarUvVertex> result;
    if(input.empty())return result;
    auto coord=[axis](const PlanarUvVertex& v){return axis==0?v.u:v.v;};
    auto inside=[&](const PlanarUvVertex& v){return greater?coord(v)>=bound:coord(v)<=bound;};
    auto previous=input.back();bool was_inside=inside(previous);
    for(const auto& current:input){const bool is_inside=inside(current);
        if(is_inside!=was_inside){
            const double t=(bound-coord(previous))/(coord(current)-coord(previous));
            result.push_back(planar_lerp(previous,current,std::clamp(t,0.0,1.0)));
        }
        if(is_inside)result.push_back(current);
        previous=current;was_inside=is_inside;
    }
    return result;
}
static gx3de_result planar_build_patch(const Mesh& mesh,const gx3de_planar_texture_spec& spec,
                                       vtkSmartPointer<vtkPolyData>& output,
                                       double* gizmo_offset) {
    const uint64_t triangle_count=mesh.triangles.size()/3;
    if(spec.source_triangle>=triangle_count)return GX3DE_RANGE;
    auto vertex=[&](uint64_t face,int corner)->gx3de_vec3{
        return mesh.vertices[mesh.triangles[3*face+corner]];};
    const auto a=vertex(spec.source_triangle,0),b=vertex(spec.source_triangle,1),
               c=vertex(spec.source_triangle,2);
    auto n=cross(sub(b,a),sub(c,a));const double normal_length=length(n);
    if(!(normal_length>1e-12))return GX3DE_DEGENERATE;
    n=mul(n,1.0/normal_length);
    gx3de_vec3 min=a,max=a;
    for(auto p:mesh.vertices){min.x=std::min(min.x,p.x);min.y=std::min(min.y,p.y);
        min.z=std::min(min.z,p.z);max.x=std::max(max.x,p.x);
        max.y=std::max(max.y,p.y);max.z=std::max(max.z,p.z);}
    const double diagonal=length(sub(max,min));
    const double tolerance=std::max(1e-7,diagonal*1e-5);
    if(std::abs(dot(sub(spec.local_anchor,a),n))>tolerance)return GX3DE_INVALID_ARGUMENT;
    std::vector<uint8_t> eligible(triangle_count,0);
    std::unordered_map<uint64_t,std::vector<uint64_t>> edges;
    for(uint64_t face=0;face<triangle_count;++face){
        const auto p=vertex(face,0),q=vertex(face,1),r=vertex(face,2);
        auto candidate=cross(sub(q,p),sub(r,p));const double magnitude=length(candidate);
        if(!(magnitude>1e-12)||dot(candidate,n)<magnitude*0.9999||
           std::abs(dot(sub(p,a),n))>tolerance||
           std::abs(dot(sub(q,a),n))>tolerance||
           std::abs(dot(sub(r,a),n))>tolerance)continue;
        eligible[face]=1;
        for(int j=0;j<3;++j)
            edges[planar_edge(mesh.triangles[face*3+j],
                              mesh.triangles[face*3+(j+1)%3])].push_back(face);
    }
    std::vector<uint64_t> region{spec.source_triangle};
    std::vector<uint8_t> seen(triangle_count,0);seen[spec.source_triangle]=1;
    for(size_t head=0;head<region.size();++head){const auto face=region[head];
        for(int j=0;j<3;++j){const auto edge=planar_edge(mesh.triangles[face*3+j],
                                              mesh.triangles[face*3+(j+1)%3]);
            for(auto next:edges[edge])if(eligible[next]&&!seen[next]){
                seen[next]=1;region.push_back(next);}}
    }
    bool anchor_on_region=false;
    for(auto face:region)if(planar_inside(spec.local_anchor,vertex(face,0),
            vertex(face,1),vertex(face,2),n,tolerance)){
        anchor_on_region=true;break;}
    if(!anchor_on_region)return GX3DE_INVALID_ARGUMENT;
    // Project the object-local +X axis onto the chosen plane; +Y is used if
    // the plane is nearly perpendicular to X. V follows the face winding.
    gx3de_vec3 u_axis=sub({1,0,0},mul(n,n.x));
    if(length(u_axis)<0.1)u_axis=sub({0,1,0},mul(n,n.y));
    u_axis=mul(u_axis,1.0/length(u_axis));
    const auto v_axis=cross(n,u_axis);
    const double cosine=std::cos(spec.rotation_radians),sine=std::sin(spec.rotation_radians);
    vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
    vtkNew<vtkCellArray> faces;
    vtkNew<vtkFloatArray> tcoords;tcoords->SetName("TextureCoordinates");
    tcoords->SetNumberOfComponents(2);
    vtkNew<vtkFloatArray> normals;normals->SetNumberOfComponents(3);
    const double offset=std::max(1e-7,diagonal*2e-5);
    if(gizmo_offset)*gizmo_offset=std::max(1e-6,diagonal*7e-5);
    for(auto face:region){
        std::vector<PlanarUvVertex> polygon;polygon.reserve(3);
        for(int j=0;j<3;++j){const auto p=vertex(face,j);
            const auto relative=sub(p,spec.local_anchor);
            const double x=dot(relative,u_axis),y=dot(relative,v_axis);
            polygon.push_back({p,spec.anchor_u+(cosine*x+sine*y)/spec.width,
                                 spec.anchor_v+(-sine*x+cosine*y)/spec.height});}
        polygon=planar_clip(polygon,0,0,true);
        polygon=planar_clip(polygon,0,1,false);
        polygon=planar_clip(polygon,1,0,true);
        polygon=planar_clip(polygon,1,1,false);
        if(polygon.size()<3)continue;
        for(size_t j=1;j+1<polygon.size();++j){
            const PlanarUvVertex tri[3]={polygon[0],polygon[j],polygon[j+1]};
            if(length(cross(sub(tri[1].point,tri[0].point),
                            sub(tri[2].point,tri[0].point)))<1e-12)continue;
            vtkIdType ids[3];
            for(int k=0;k<3;++k){const auto shifted=add(tri[k].point,mul(n,offset));
                ids[k]=points->InsertNextPoint(shifted.x,shifted.y,shifted.z);
                normals->InsertNextTuple3(n.x,n.y,n.z);
                tcoords->InsertNextTuple2(spec.flip_u?1.0-tri[k].u:tri[k].u,
                                           spec.flip_v?1.0-tri[k].v:tri[k].v);}
            faces->InsertNextCell(3,ids);
        }
    }
    if(faces->GetNumberOfCells()==0)return GX3DE_NOT_FOUND;
    auto patch=vtkSmartPointer<vtkPolyData>::New();patch->SetPoints(points);
    patch->SetPolys(faces);patch->GetPointData()->SetTCoords(tcoords);
    patch->GetPointData()->SetNormals(normals);
    output=patch;return GX3DE_OK;
}
static bool planar_valid_spec(const gx3de_planar_texture_spec* spec) {
    return spec&&spec->struct_size>=sizeof(*spec)&&finite(spec->local_anchor)&&
        std::isfinite(spec->anchor_u)&&std::isfinite(spec->anchor_v)&&
        spec->anchor_u>=0&&spec->anchor_u<=1&&spec->anchor_v>=0&&spec->anchor_v<=1&&
        std::isfinite(spec->width)&&std::isfinite(spec->height)&&
        spec->width>0&&spec->height>0&&
        std::isfinite(spec->rotation_radians)&&spec->flip_u<=1&&spec->flip_v<=1;
}
}
gx3de_result gx3de_texture_load_file(gx3de_engine* engine,const char* path,
                                      gx3de_texture** out) {
    if(!engine||!out||!valid_utf8(path,4096))return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    try {
        if(!std::filesystem::is_regular_file(path))return GX3DE_NOT_FOUND;
        if(std::filesystem::file_size(path)>128ull*1024*1024)return GX3DE_RANGE;
        std::ifstream file(path,std::ios::binary);unsigned char magic[8]{};
        file.read(reinterpret_cast<char*>(magic),sizeof(magic));
        vtkSmartPointer<vtkImageData> image=vtkSmartPointer<vtkImageData>::New();
        if(std::memcmp(magic,"\x89PNG\r\n\x1a\n",8)==0){
            vtkNew<vtkPNGReader> reader;reader->SetFileName(path);reader->Update();
            image->DeepCopy(reader->GetOutput());
        }else if(magic[0]==0xff&&magic[1]==0xd8){
            vtkNew<vtkJPEGReader> reader;reader->SetFileName(path);reader->Update();
            image->DeepCopy(reader->GetOutput());
        }else return GX3DE_UNSUPPORTED;
        int dimensions[3]{};image->GetDimensions(dimensions);
        auto* scalars=image->GetPointData()->GetScalars();
        const int channels=scalars?scalars->GetNumberOfComponents():0;
        if(dimensions[0]<1||dimensions[1]<1||dimensions[0]>8192||dimensions[1]>8192||
           channels<1||channels>4||
           uint64_t(dimensions[0])*dimensions[1]*channels>256ull*1024*1024)
            return GX3DE_RANGE;
        auto payload=std::make_shared<gx3de_texture_image>();
        payload->pixels=image;payload->width=dimensions[0];
        payload->height=dimensions[1];payload->channels=channels;
        auto texture=std::make_unique<gx3de_texture>();texture->engine=engine;
        texture->image=std::move(payload);
        engine->textures.push_back(texture.get());*out=texture.release();return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
    catch(const std::filesystem::filesystem_error&){return GX3DE_NOT_FOUND;}
}
gx3de_result gx3de_texture_info_get(gx3de_texture* texture,gx3de_texture_info* out) {
    if(!texture||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    *out={sizeof(*out),texture->image->width,texture->image->height,
          texture->image->channels,{}};return GX3DE_OK;
}
gx3de_result gx3de_texture_destroy(gx3de_texture* texture) {
    if(!texture)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(texture->engine->textures,texture);delete texture;return GX3DE_OK;
}
gx3de_result gx3de_object_planar_texture_add(gx3de_object* object,gx3de_texture* texture,
                      const gx3de_planar_texture_spec* spec,gx3de_planar_texture** out) {
    if(!object||!object->mesh||!texture||!out||!planar_valid_spec(spec))
        return GX3DE_INVALID_ARGUMENT;
    if(object->scene->engine!=texture->engine)return GX3DE_WRONG_OWNER;
    *out=nullptr;
    try {
        vtkSmartPointer<vtkPolyData> patch;
        double gizmo_offset=0;
        auto result=planar_build_patch(*object->mesh,*spec,patch,&gizmo_offset);
        if(result!=GX3DE_OK)return result;
        auto assignment=std::make_unique<gx3de_planar_texture>();
        assignment->object=object;assignment->image=texture->image;
        assignment->spec=*spec;assignment->patch=patch;
        assignment->gizmo_offset=gizmo_offset;
        object->planar_textures.push_back(assignment.get());
        *out=assignment.release();return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_planar_texture_add_from_pick(gx3de_texture* texture,
        const gx3de_pick_hit* hit,const gx3de_planar_texture_spec* placement,
        gx3de_planar_texture** out) {
    if(!texture||!hit||hit->struct_size<sizeof(*hit)||!hit->object||
       hit->geometry_kind!=GX3DE_PICK_MESH||!hit->has_surface_normal||
       !finite(hit->local_point)||!finite(hit->world_normal)||
       !planar_valid_spec(placement)||!out)return GX3DE_INVALID_ARGUMENT;
    auto* object=hit->object;
    if(!object->mesh)return GX3DE_UNSUPPORTED;
    if(object->scene->engine!=texture->engine)return GX3DE_WRONG_OWNER;
    const auto& mesh=*object->mesh;
    gx3de_bounds bounds{};
    if(gx3de_object_bounds(object,0,&bounds)!=GX3DE_OK)return GX3DE_DEGENERATE;
    const double tolerance=std::max(1e-7,length(sub(bounds.max,bounds.min))*1e-5);
    uint64_t chosen=UINT64_MAX;double best=-1;
    const auto pose=world(object);
    for(uint64_t face=0;face<mesh.triangles.size()/3;++face){
        const auto a=mesh.vertices[mesh.triangles[3*face]],
                   b=mesh.vertices[mesh.triangles[3*face+1]],
                   c=mesh.vertices[mesh.triangles[3*face+2]];
        auto local_normal=cross(sub(b,a),sub(c,a));
        const double magnitude=length(local_normal);
        if(!(magnitude>1e-12))continue;
        local_normal=mul(local_normal,1.0/magnitude);
        if(!planar_inside(hit->local_point,a,b,c,local_normal,tolerance))continue;
        gx3de_vec3 world_normal{};
        if(!transform_normal(pose,local_normal,world_normal))return GX3DE_DEGENERATE;
        const double score=dot(world_normal,hit->world_normal);
        if(score>best){best=score;chosen=face;}
    }
    if(chosen==UINT64_MAX||best<0.8)return GX3DE_NOT_FOUND;
    auto spec=*placement;spec.source_triangle=chosen;spec.local_anchor=hit->local_point;
    return gx3de_object_planar_texture_add(object,texture,&spec,out);
}
gx3de_result gx3de_planar_texture_update(gx3de_planar_texture* assignment,
                                            const gx3de_planar_texture_spec* spec) {
    if(!assignment||!planar_valid_spec(spec))return GX3DE_INVALID_ARGUMENT;
    try {
        vtkSmartPointer<vtkPolyData> patch;
        double gizmo_offset=0;
        auto result=planar_build_patch(*assignment->object->mesh,*spec,patch,&gizmo_offset);
        if(result!=GX3DE_OK)return result;
        assignment->spec=*spec;assignment->patch=patch;
        assignment->gizmo_offset=gizmo_offset;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_planar_texture_get(gx3de_planar_texture* assignment,
                                         gx3de_planar_texture_spec* out) {
    if(!assignment||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    *out=assignment->spec;return GX3DE_OK;
}
static bool planar_gizmo_frame(const gx3de_planar_texture* assignment,
                               gx3de_vec3& anchor,gx3de_vec3& u,gx3de_vec3& v,
                               gx3de_vec3& normal) {
    if(!assignment||!assignment->object||!assignment->object->mesh)return false;
    const auto& mesh=*assignment->object->mesh;
    const auto face=assignment->spec.source_triangle;
    if(face>=mesh.triangles.size()/3)return false;
    const auto a=mesh.vertices[mesh.triangles[3*face]],
               b=mesh.vertices[mesh.triangles[3*face+1]],
               c=mesh.vertices[mesh.triangles[3*face+2]];
    normal=cross(sub(b,a),sub(c,a));
    if(length(normal)<1e-12)return false;
    normal=mul(normal,1.0/length(normal));
    u=sub({1,0,0},mul(normal,normal.x));
    if(length(u)<0.1)u=sub({0,1,0},mul(normal,normal.y));
    u=mul(u,1.0/length(u));v=cross(normal,u);
    const double co=std::cos(assignment->spec.rotation_radians),
                 si=std::sin(assignment->spec.rotation_radians);
    const auto rotated_u=add(mul(u,co),mul(v,si));
    v=add(mul(u,-si),mul(v,co));u=rotated_u;
    anchor=assignment->spec.local_anchor;return true;
}
static bool planar_gizmo_local_handle(const gx3de_planar_texture* assignment,
                                      uint32_t handle,gx3de_vec3& point) {
    gx3de_vec3 anchor,u,v,n;
    if(!planar_gizmo_frame(assignment,anchor,u,v,n))return false;
    const auto& s=assignment->spec;
    double x=0,y=0;
    switch(handle){
    case GX3DE_PLANAR_HANDLE_ANCHOR:break;
    case GX3DE_PLANAR_HANDLE_CORNER_00:x=-s.anchor_u;y=-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_CORNER_10:x=1-s.anchor_u;y=-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_CORNER_11:x=1-s.anchor_u;y=1-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_CORNER_01:x=-s.anchor_u;y=1-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_WIDTH:x=1-s.anchor_u;y=.5-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_HEIGHT:x=.5-s.anchor_u;y=1-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_ROTATION:x=.5-s.anchor_u;y=1.22-s.anchor_v;break;
    default:return false;
    }
    point=add(add(add(anchor,mul(u,x*s.width)),mul(v,y*s.height)),
              mul(n,assignment->gizmo_offset));
    return true;
}
gx3de_result gx3de_planar_texture_move(gx3de_planar_texture* a,gx3de_vec3 anchor) {
    if(!a||!finite(anchor))return GX3DE_INVALID_ARGUMENT;
    auto spec=a->spec;spec.local_anchor=anchor;return gx3de_planar_texture_update(a,&spec);
}
gx3de_result gx3de_planar_texture_rotate(gx3de_planar_texture* a,double radians) {
    if(!a||!std::isfinite(radians))return GX3DE_INVALID_ARGUMENT;
    auto spec=a->spec;spec.rotation_radians=radians;
    return gx3de_planar_texture_update(a,&spec);
}
gx3de_result gx3de_planar_texture_resize(gx3de_planar_texture* a,uint32_t mode,
                                           double width,double height) {
    if(!a||!std::isfinite(width)||width<=0||
       (mode!=GX3DE_PLANAR_RESIZE_PROPORTIONAL&&mode!=GX3DE_PLANAR_RESIZE_STRETCH)||
       (mode==GX3DE_PLANAR_RESIZE_STRETCH&&(!std::isfinite(height)||height<=0)))
        return GX3DE_INVALID_ARGUMENT;
    auto spec=a->spec;spec.height=mode==GX3DE_PLANAR_RESIZE_PROPORTIONAL?
        spec.height*(width/spec.width):height;spec.width=width;
    return gx3de_planar_texture_update(a,&spec);
}
gx3de_result gx3de_planar_texture_gizmo_visible_set(gx3de_planar_texture* a,uint32_t visible) {
    if(!a||visible>1)return GX3DE_INVALID_ARGUMENT;a->gizmo_visible=visible!=0;return GX3DE_OK;
}
gx3de_result gx3de_planar_texture_gizmo_visible_get(gx3de_planar_texture* a,uint32_t* visible) {
    if(!a||!visible)return GX3DE_INVALID_ARGUMENT;*visible=a->gizmo_visible;return GX3DE_OK;
}
gx3de_result gx3de_planar_texture_gizmo_handle_world(gx3de_planar_texture* a,
                                                       uint32_t handle,gx3de_vec3* point) {
    if(!a||!point)return GX3DE_INVALID_ARGUMENT;
    gx3de_vec3 local{};if(!planar_gizmo_local_handle(a,handle,local))return GX3DE_INVALID_ARGUMENT;
    *point=apply(world(a->object),local);return GX3DE_OK;
}
gx3de_result gx3de_planar_texture_gizmo_pick(gx3de_viewport* vp,gx3de_planar_texture* a,
                                               double x,double y,double radius,uint32_t* handle) {
    if(!vp||!a||!handle||!std::isfinite(x)||!std::isfinite(y)||
       !std::isfinite(radius)||radius<=0)return GX3DE_INVALID_ARGUMENT;
    *handle=0;if(!a->gizmo_visible||a->object->scene!=vp->view->scene)return GX3DE_NOT_FOUND;
    double best=radius*radius;
    for(uint32_t h=GX3DE_PLANAR_HANDLE_ANCHOR;h<=GX3DE_PLANAR_HANDLE_ROTATION;++h){
        gx3de_vec3 p{};double sx,sy,depth;
        if(gx3de_planar_texture_gizmo_handle_world(a,h,&p)!=GX3DE_OK||
           gx3de_viewport_world_to_screen(vp,p,&sx,&sy,&depth)!=GX3DE_OK)continue;
        const double d=(sx-x)*(sx-x)+(sy-y)*(sy-y);
        if(d<=best){best=d;*handle=h;}
    }
    return *handle?GX3DE_OK:GX3DE_NOT_FOUND;
}
gx3de_result gx3de_planar_texture_destroy(gx3de_planar_texture* assignment) {
    if(!assignment)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(assignment->object->planar_textures,assignment);
    delete assignment;return GX3DE_OK;
}
