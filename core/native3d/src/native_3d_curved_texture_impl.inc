// SPDX-License-Identifier: GPL-3.0-or-later
// Surface-conforming image assignment. Each triangle is unfolded across a
// shared mesh edge from the picked seed. The rendered geometry stays on the mesh.
namespace {
static bool curved_valid(const gx3de_curved_texture_spec* s) {
    return s&&s->struct_size>=sizeof(*s)&&finite(s->local_anchor)&&
        std::isfinite(s->anchor_u)&&s->anchor_u>=0&&s->anchor_u<=1&&
        std::isfinite(s->anchor_v)&&s->anchor_v>=0&&s->anchor_v<=1&&
        std::isfinite(s->width)&&s->width>0&&std::isfinite(s->height)&&s->height>0&&
        std::isfinite(s->rotation_radians)&&std::isfinite(s->max_distance)&&s->max_distance>0&&
        std::isfinite(s->max_edge_angle_radians)&&s->max_edge_angle_radians>0&&
        s->max_edge_angle_radians<=3.141592653589793&&
        std::isfinite(s->max_seed_angle_radians)&&s->max_seed_angle_radians>0&&
        s->max_seed_angle_radians<=3.141592653589793&&s->flip_u<=1&&s->flip_v<=1;
}
static gx3de_result curved_build(const Mesh& mesh,const gx3de_curved_texture_spec& s,
    vtkSmartPointer<vtkPolyData>& patch,std::vector<CurvedFace>& chart,
    std::vector<gx3de_segment3>& boundary,std::vector<gx3de_segment3>& seams,
    gx3de_curved_texture_status& status,double& gizmo_offset) {
    const size_t count=mesh.triangles.size()/3;
    if(s.source_triangle>=count)return GX3DE_RANGE;
    auto vertex=[&](size_t f,int j){return mesh.vertices[mesh.triangles[3*f+j]];};
    auto a=vertex(s.source_triangle,0),b=vertex(s.source_triangle,1),
         c=vertex(s.source_triangle,2);
    auto seed=cross(sub(b,a),sub(c,a));
    if(length(seed)<1e-12)return GX3DE_DEGENERATE;
    seed=mul(seed,1.0/length(seed));
    gx3de_vec3 mn=a,mx=a;
    for(const auto& p:mesh.vertices){mn.x=std::min(mn.x,p.x);mn.y=std::min(mn.y,p.y);
        mn.z=std::min(mn.z,p.z);mx.x=std::max(mx.x,p.x);mx.y=std::max(mx.y,p.y);
        mx.z=std::max(mx.z,p.z);}
    const double diagonal=length(sub(mx,mn));
    const double tolerance=std::max(1e-7,diagonal*1e-5);
    if(!planar_inside(s.local_anchor,a,b,c,seed,tolerance))
        return GX3DE_INVALID_ARGUMENT;
    gx3de_vec3 u=sub({1,0,0},mul(seed,seed.x));
    if(length(u)<0.1)u=sub({0,1,0},mul(seed,seed.y));
    u=mul(u,1.0/length(u));const auto v=cross(seed,u);
    std::unordered_map<uint64_t,std::vector<uint32_t>> edges;
    edges.reserve(count*2);
    for(uint32_t f=0;f<count;++f)
        for(int j=0;j<3;++j)edges[planar_edge(mesh.triangles[3*f+j],
            mesh.triangles[3*f+(j+1)%3])].push_back(f);
    std::vector<gx3de_vec3> normals(count);
    for(size_t f=0;f<count;++f){auto n=cross(sub(vertex(f,1),vertex(f,0)),
        sub(vertex(f,2),vertex(f,0)));if(length(n)>1e-12)normals[f]=mul(n,1.0/length(n));}
    const double edge_cos=std::cos(s.max_edge_angle_radians);
    const double seed_cos=std::cos(s.max_seed_angle_radians);
    const double extent=std::hypot(s.width,s.height)*1.5;
    const double chart_tolerance=std::max(1e-6,diagonal*1e-5);
    status={};status.struct_size=sizeof(status);
    chart.clear();boundary.clear();seams.clear();
    std::vector<CurvedFace> faces(count);
    std::vector<double> distance(count,std::numeric_limits<double>::infinity());
    std::vector<uint8_t> settled(count,0);
    using Visit=std::pair<double,uint32_t>;
    std::priority_queue<Visit,std::vector<Visit>,std::greater<Visit>> frontier;
    auto& first=faces[s.source_triangle];first.id=s.source_triangle;first.normal=seed;
    for(int j=0;j<3;++j){first.point[j]=vertex(s.source_triangle,j);
        auto d=sub(first.point[j],s.local_anchor);
        first.x[j]=dot(d,u);first.y[j]=dot(d,v);}
    distance[s.source_triangle]=0;frontier.push({0,uint32_t(s.source_triangle)});
    std::vector<uint32_t> region;
    while(!frontier.empty()){
        const auto [cost,f]=frontier.top();frontier.pop();
        if(settled[f]||cost>distance[f])continue;
        settled[f]=1;region.push_back(f);
        const auto& parent=faces[f];
        for(int j=0;j<3;++j){
            const auto id0=mesh.triangles[3*f+j],id1=mesh.triangles[3*f+(j+1)%3];
            const auto key=planar_edge(id0,id1);
            const auto& adjacent=edges[key];
            if(adjacent.size()==1){++status.open_edges;status.flags|=GX3DE_CURVED_WRAP_OPEN_BOUNDARY;continue;}
            if(adjacent.size()!=2){++status.nonmanifold_edges;status.flags|=GX3DE_CURVED_WRAP_NONMANIFOLD;continue;}
            const auto next=adjacent[0]==f?adjacent[1]:adjacent[0];
            if(settled[next])continue;
            if(dot(normals[f],normals[next])<edge_cos||dot(seed,normals[next])<seed_cos){
                ++status.angle_stops;status.flags|=GX3DE_CURVED_WRAP_ANGLE_LIMIT;continue;}
            const auto center=[](const CurvedFace& face){return mul(add(add(face.point[0],face.point[1]),face.point[2]),1.0/3.0);};
            CurvedFace candidate{};candidate.id=next;candidate.normal=normals[next];
            int shared[2]={-1,-1},third=-1;
            for(int k=0;k<3;++k){const auto id=mesh.triangles[3*next+k];
                candidate.point[k]=vertex(next,k);
                if(id==id0)shared[0]=k;else if(id==id1)shared[1]=k;else third=k;}
            if(shared[0]<0||shared[1]<0||third<0)continue;
            int p0=-1,p1=-1,pt=-1;
            for(int k=0;k<3;++k){const auto id=mesh.triangles[3*f+k];
                if(id==id0)p0=k;else if(id==id1)p1=k;else pt=k;}
            if(p0<0||p1<0||pt<0)continue;
            candidate.x[shared[0]]=parent.x[p0];candidate.y[shared[0]]=parent.y[p0];
            candidate.x[shared[1]]=parent.x[p1];candidate.y[shared[1]]=parent.y[p1];
            const double ex=parent.x[p1]-parent.x[p0],ey=parent.y[p1]-parent.y[p0];
            const double edge_length=std::hypot(ex,ey);
            if(edge_length<1e-12)continue;
            const double r0=length(sub(candidate.point[third],candidate.point[shared[0]]));
            const double r1=length(sub(candidate.point[third],candidate.point[shared[1]]));
            const double along=(r0*r0-r1*r1+edge_length*edge_length)/(2*edge_length);
            const double height2=r0*r0-along*along;
            if(height2<-chart_tolerance*chart_tolerance)continue;
            const double height=std::sqrt(std::max(0.0,height2));
            const double parent_side=ex*(parent.y[pt]-parent.y[p0])-ey*(parent.x[pt]-parent.x[p0]);
            const double side=parent_side>=0?-1.0:1.0;
            candidate.x[third]=parent.x[p0]+(along*ex-side*height*ey)/edge_length;
            candidate.y[third]=parent.y[p0]+(along*ey+side*height*ex)/edge_length;
            const double next_cost=cost+length(sub(center(parent),center(candidate)));
            if(next_cost>s.max_distance+chart_tolerance){
                ++status.distance_stops;status.flags|=GX3DE_CURVED_WRAP_DISTANCE_LIMIT;continue;}
            double cx=0,cy=0;
            for(int k=0;k<3;++k){cx+=candidate.x[k]/3;cy+=candidate.y[k]/3;}
            if(std::hypot(cx,cy)>extent+chart_tolerance){
                ++status.chart_stops;status.flags|=GX3DE_CURVED_WRAP_CHART_LIMIT;continue;}
            if(next_cost<distance[next]){distance[next]=next_cost;faces[next]=candidate;
                frontier.push({next_cost,next});}
        }
    }
    status.chart_triangles=region.size();
    vtkNew<vtkPoints> points;points->SetDataTypeToDouble();
    vtkNew<vtkCellArray> cells;vtkNew<vtkFloatArray> uv;
    uv->SetName("TextureCoordinates");uv->SetNumberOfComponents(2);
    vtkNew<vtkFloatArray> out_normals;out_normals->SetNumberOfComponents(3);
    const double offset=std::max(1e-7,diagonal*2e-5);
    gizmo_offset=std::max(1e-6,diagonal*7e-5);
    const double co=std::cos(s.rotation_radians),si=std::sin(s.rotation_radians);
    std::map<std::array<long long,6>,std::pair<unsigned,gx3de_segment3>> perimeter;
    const double quantize=std::max(1e-7,diagonal*1e-7);
    std::vector<uint8_t> mapped(count,0);
    for(auto f:region){
        CurvedFace cf=faces[f];
        std::vector<PlanarUvVertex> polygon;polygon.reserve(3);
        for(int j=0;j<3;++j){
            auto p=cf.point[j];
            polygon.push_back({p,s.anchor_u+(co*cf.x[j]+si*cf.y[j])/s.width,
                s.anchor_v+(-si*cf.x[j]+co*cf.y[j])/s.height});
        }
        chart.push_back(cf);
        polygon=planar_clip(polygon,0,0,true);
        polygon=planar_clip(polygon,0,1,false);
        polygon=planar_clip(polygon,1,0,true);
        polygon=planar_clip(polygon,1,1,false);
        if(polygon.size()<3)continue;
        mapped[f]=1;
        ++status.rendered_triangles;
        for(size_t j=0;j<polygon.size();++j){
            auto p=polygon[j].point,q=polygon[(j+1)%polygon.size()].point;
            std::array<long long,3> kp={llround(p.x/quantize),llround(p.y/quantize),
                                        llround(p.z/quantize)};
            std::array<long long,3> kq={llround(q.x/quantize),llround(q.y/quantize),
                                        llround(q.z/quantize)};
            if(kq<kp)std::swap(kp,kq);
            std::array<long long,6> key{kp[0],kp[1],kp[2],kq[0],kq[1],kq[2]};
            auto& edge=perimeter[key];
            ++edge.first;
            edge.second={add(p,mul(cf.normal,gizmo_offset)),
                         add(q,mul(cf.normal,gizmo_offset))};
        }
        for(size_t j=1;j+1<polygon.size();++j){
            const PlanarUvVertex tri[3]={polygon[0],polygon[j],polygon[j+1]};
            if(length(cross(sub(tri[1].point,tri[0].point),
                            sub(tri[2].point,tri[0].point)))<1e-12)continue;
            vtkIdType ids[3];
            for(int k=0;k<3;++k){auto p=add(tri[k].point,mul(cf.normal,offset));
                ids[k]=points->InsertNextPoint(p.x,p.y,p.z);
                out_normals->InsertNextTuple3(cf.normal.x,cf.normal.y,cf.normal.z);
                uv->InsertNextTuple2(s.flip_u?1-tri[k].u:tri[k].u,
                                     s.flip_v?1-tri[k].v:tri[k].v);}
            cells->InsertNextCell(3,ids);
        }
    }
    // Compare settled charts along non-tree edges. The transported tree stays
    // continuous; disagreeing cycle edges are the explicit wrap seams.
    for(auto f:region)for(int j=0;j<3;++j){
        const auto id0=mesh.triangles[3*f+j],id1=mesh.triangles[3*f+(j+1)%3];
        const auto& adjacent=edges[planar_edge(id0,id1)];
        if(adjacent.size()!=2)continue;
        const auto other=adjacent[0]==f?adjacent[1]:adjacent[0];
        if(other<=f||!mapped[f]||!mapped[other])continue;
        double difference=0;
        for(auto id:{id0,id1}){
            int i=-1,k=-1;
            for(int n=0;n<3;++n){if(mesh.triangles[3*f+n]==id)i=n;
                if(mesh.triangles[3*other+n]==id)k=n;}
            if(i>=0&&k>=0)difference=std::max(difference,std::hypot(
                faces[f].x[i]-faces[other].x[k],faces[f].y[i]-faces[other].y[k]));
        }
        if(difference>chart_tolerance){
            ++status.seam_edges;status.flags|=GX3DE_CURVED_WRAP_SEAM;
            seams.push_back({vertex(f,j),vertex(f,(j+1)%3)});
        }
    }
    for(const auto& edge:perimeter)if(edge.second.first==1)
        boundary.push_back(edge.second.second);
    if(cells->GetNumberOfCells()==0)return GX3DE_NOT_FOUND;
    auto result=vtkSmartPointer<vtkPolyData>::New();result->SetPoints(points);
    result->SetPolys(cells);result->GetPointData()->SetTCoords(uv);
    result->GetPointData()->SetNormals(out_normals);patch=result;
    return GX3DE_OK;
}
static bool curved_local_at(const gx3de_curved_texture* assignment,
                            double x,double y,gx3de_vec3& result);
}
gx3de_result gx3de_object_curved_texture_add(gx3de_object* object,gx3de_texture* texture,
    const gx3de_curved_texture_spec* spec,gx3de_curved_texture** out) {
    if(!object||!object->mesh||!texture||!out||!curved_valid(spec))
        return GX3DE_INVALID_ARGUMENT;
    if(object->scene->engine!=texture->engine)return GX3DE_WRONG_OWNER;
    *out=nullptr;
    try{
        auto assignment=std::make_unique<gx3de_curved_texture>();
        assignment->object=object;assignment->image=texture->image;
        auto rc=curved_build(*object->mesh,*spec,assignment->patch,assignment->chart,
                             assignment->boundary,assignment->seams,
                             assignment->status,assignment->gizmo_offset);
        if(rc!=GX3DE_OK)return rc;
        assignment->spec=*spec;
        object->curved_textures.push_back(assignment.get());
        *out=assignment.release();return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_object_curved_texture_add_from_pick(gx3de_texture* texture,
    const gx3de_pick_hit* hit,const gx3de_curved_texture_spec* placement,
    gx3de_curved_texture** out) {
    if(!texture||!hit||hit->struct_size<sizeof(*hit)||!hit->object||
       hit->geometry_kind!=GX3DE_PICK_MESH||!hit->has_surface_normal||
       !finite(hit->local_point)||!finite(hit->world_normal)||
       !curved_valid(placement)||!out)return GX3DE_INVALID_ARGUMENT;
    auto* object=hit->object;
    if(!object->mesh)return GX3DE_UNSUPPORTED;
    if(object->scene->engine!=texture->engine)return GX3DE_WRONG_OWNER;
    const auto& mesh=*object->mesh;gx3de_bounds bounds{};
    if(gx3de_object_bounds(object,0,&bounds)!=GX3DE_OK)return GX3DE_DEGENERATE;
    const double tolerance=std::max(1e-7,length(sub(bounds.max,bounds.min))*1e-5);
    uint64_t chosen=UINT64_MAX;double best=-1;const auto pose=world(object);
    for(uint64_t f=0;f<mesh.triangles.size()/3;++f){
        auto a=mesh.vertices[mesh.triangles[3*f]],b=mesh.vertices[mesh.triangles[3*f+1]],
             c=mesh.vertices[mesh.triangles[3*f+2]];
        auto n=cross(sub(b,a),sub(c,a));if(length(n)<1e-12)continue;
        n=mul(n,1.0/length(n));
        if(!planar_inside(hit->local_point,a,b,c,n,tolerance))continue;
        gx3de_vec3 wn{};if(!transform_normal(pose,n,wn))return GX3DE_DEGENERATE;
        double score=dot(wn,hit->world_normal);
        if(score>best){best=score;chosen=f;}
    }
    if(chosen==UINT64_MAX||best<0.8)return GX3DE_NOT_FOUND;
    auto spec=*placement;spec.source_triangle=chosen;spec.local_anchor=hit->local_point;
    return gx3de_object_curved_texture_add(object,texture,&spec,out);
}
gx3de_result gx3de_curved_texture_update(gx3de_curved_texture* assignment,
    const gx3de_curved_texture_spec* spec) {
    if(!assignment||!curved_valid(spec))return GX3DE_INVALID_ARGUMENT;
    try{
        vtkSmartPointer<vtkPolyData> patch;std::vector<CurvedFace> chart;
        std::vector<gx3de_segment3> boundary,seams;double offset=0;
        gx3de_curved_texture_status status{};
        auto rc=curved_build(*assignment->object->mesh,*spec,patch,chart,boundary,
                             seams,status,offset);
        if(rc!=GX3DE_OK)return rc;
        assignment->spec=*spec;assignment->patch=patch;
        assignment->chart=std::move(chart);assignment->boundary=std::move(boundary);
        assignment->seams=std::move(seams);assignment->status=status;
        assignment->gizmo_offset=offset;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
gx3de_result gx3de_curved_texture_get(gx3de_curved_texture* a,gx3de_curved_texture_spec* out){
    if(!a||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    *out=a->spec;return GX3DE_OK;
}
gx3de_result gx3de_curved_texture_move(gx3de_curved_texture* a,gx3de_vec3 point){
    if(!a||!finite(point))return GX3DE_INVALID_ARGUMENT;
    auto s=a->spec;
    // The new point must lie on the currently selected connected chart.
    uint64_t face=UINT64_MAX;double best=1e100;
    for(const auto& f:a->chart)if(planar_inside(point,f.point[0],f.point[1],f.point[2],
                                                f.normal,a->gizmo_offset)){
        const double d=length(sub(point,f.point[0]));
        if(d<best){best=d;face=f.id;}
    }
    if(face==UINT64_MAX)return GX3DE_NOT_FOUND;
    s.source_triangle=face;s.local_anchor=point;
    return gx3de_curved_texture_update(a,&s);
}
gx3de_result gx3de_curved_texture_rotate(gx3de_curved_texture* a,double radians){
    if(!a||!std::isfinite(radians))return GX3DE_INVALID_ARGUMENT;
    auto s=a->spec;s.rotation_radians=radians;return gx3de_curved_texture_update(a,&s);
}
gx3de_result gx3de_curved_texture_resize(gx3de_curved_texture* a,uint32_t mode,
                                          double width,double height){
    if(!a||!std::isfinite(width)||width<=0||
       (mode!=GX3DE_PLANAR_RESIZE_PROPORTIONAL&&mode!=GX3DE_PLANAR_RESIZE_STRETCH)||
       (mode==GX3DE_PLANAR_RESIZE_STRETCH&&(!std::isfinite(height)||height<=0)))
        return GX3DE_INVALID_ARGUMENT;
    auto s=a->spec;s.height=mode==GX3DE_PLANAR_RESIZE_PROPORTIONAL?
        s.height*width/s.width:height;s.width=width;
    return gx3de_curved_texture_update(a,&s);
}
gx3de_result gx3de_curved_texture_gizmo_visible_set(gx3de_curved_texture* a,uint32_t visible){
    if(!a||visible>1)return GX3DE_INVALID_ARGUMENT;a->gizmo_visible=visible;return GX3DE_OK;
}
gx3de_result gx3de_curved_texture_gizmo_visible_get(gx3de_curved_texture* a,uint32_t* visible){
    if(!a||!visible)return GX3DE_INVALID_ARGUMENT;*visible=a->gizmo_visible;return GX3DE_OK;
}
namespace {
static bool curved_local_at(const gx3de_curved_texture* a,double x,double y,
                            gx3de_vec3& result){
    double best=1e100;bool found=false;
    for(const auto& f:a->chart){
        double x0=f.x[0],y0=f.y[0],x1=f.x[1],y1=f.y[1],x2=f.x[2],y2=f.y[2];
        double den=(y1-y2)*(x0-x2)+(x2-x1)*(y0-y2);
        if(std::abs(den)<1e-12)continue;
        double l0=((y1-y2)*(x-x2)+(x2-x1)*(y-y2))/den;
        double l1=((y2-y0)*(x-x2)+(x0-x2)*(y-y2))/den,l2=1-l0-l1;
        double distance=0;
        if(l0<-1e-7||l1<-1e-7||l2<-1e-7){
            distance=1e100;
            const double xx[3]={x0,x1,x2},yy[3]={y0,y1,y2};
            for(int edge=0;edge<3;++edge){
                const int next=(edge+1)%3;
                const double dx=xx[next]-xx[edge],dy=yy[next]-yy[edge];
                const double size=dx*dx+dy*dy;
                if(size<1e-14)continue;
                const double t=std::clamp(((x-xx[edge])*dx+(y-yy[edge])*dy)/size,
                                          0.0,1.0);
                const double px=xx[edge]+t*dx,py=yy[edge]+t*dy;
                const double d=(x-px)*(x-px)+(y-py)*(y-py);
                if(d<distance){distance=d;l0=l1=l2=0;
                    if(edge==0){l0=1-t;l1=t;}
                    else if(edge==1){l1=1-t;l2=t;}
                    else {l2=1-t;l0=t;}}
            }
        }
        if(distance>=best)continue;
        result=add(add(mul(f.point[0],l0),mul(f.point[1],l1)),mul(f.point[2],l2));
        result=add(result,mul(f.normal,a->gizmo_offset));best=distance;found=true;
    }
    return found;
}
}
gx3de_result gx3de_curved_texture_gizmo_handle_world(gx3de_curved_texture* a,
    uint32_t handle,gx3de_vec3* point){
    if(!a||!point)return GX3DE_INVALID_ARGUMENT;
    const auto& s=a->spec;double q=0,r=0;
    switch(handle){
    case GX3DE_PLANAR_HANDLE_ANCHOR:break;
    case GX3DE_PLANAR_HANDLE_CORNER_00:q=-s.anchor_u;r=-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_CORNER_10:q=1-s.anchor_u;r=-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_CORNER_11:q=1-s.anchor_u;r=1-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_CORNER_01:q=-s.anchor_u;r=1-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_WIDTH:q=1-s.anchor_u;r=.5-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_HEIGHT:q=.5-s.anchor_u;r=1-s.anchor_v;break;
    case GX3DE_PLANAR_HANDLE_ROTATION:q=.5-s.anchor_u;r=1.22-s.anchor_v;break;
    default:return GX3DE_INVALID_ARGUMENT;
    }
    double co=std::cos(s.rotation_radians),si=std::sin(s.rotation_radians);
    double x=co*q*s.width-si*r*s.height,y=si*q*s.width+co*r*s.height;
    gx3de_vec3 local{};
    if(!curved_local_at(a,x,y,local))return GX3DE_NOT_FOUND;
    if(handle==GX3DE_PLANAR_HANDLE_ROTATION){
        // A rotation control may sit beyond a bounded or open surface patch.
        // Keep the image on the mesh, but place this editing control at its
        // requested tangent-chart location so it cannot collapse onto the
        // height handle at a surface boundary.
        const auto& mesh=*a->object->mesh;
        const auto f=s.source_triangle;
        auto p0=mesh.vertices[mesh.triangles[3*f]],
             p1=mesh.vertices[mesh.triangles[3*f+1]],
             p2=mesh.vertices[mesh.triangles[3*f+2]];
        auto n=cross(sub(p1,p0),sub(p2,p0));n=mul(n,1.0/length(n));
        auto u=sub({1,0,0},mul(n,n.x));
        if(length(u)<.1)u=sub({0,1,0},mul(n,n.y));
        u=mul(u,1.0/length(u));const auto v=cross(n,u);
        const auto d=sub(local,s.local_anchor);
        local=add(local,add(mul(u,x-dot(d,u)),mul(v,y-dot(d,v))));
    }
    *point=apply(world(a->object),local);return GX3DE_OK;
}
gx3de_result gx3de_curved_texture_gizmo_pick(gx3de_viewport* vp,gx3de_curved_texture* a,
    double x,double y,double radius,uint32_t* handle){
    if(!vp||!a||!handle||!std::isfinite(x)||!std::isfinite(y)||
       !std::isfinite(radius)||radius<=0)return GX3DE_INVALID_ARGUMENT;
    *handle=0;if(!a->gizmo_visible||a->object->scene!=vp->view->scene)return GX3DE_NOT_FOUND;
    double best=radius*radius;
    for(uint32_t h=1;h<=8;++h){gx3de_vec3 p{};double sx,sy,depth;
        if(gx3de_curved_texture_gizmo_handle_world(a,h,&p)!=GX3DE_OK||
           gx3de_viewport_world_to_screen(vp,p,&sx,&sy,&depth)!=GX3DE_OK)continue;
        double d=(sx-x)*(sx-x)+(sy-y)*(sy-y);if(d<=best){best=d;*handle=h;}
    }
    return *handle?GX3DE_OK:GX3DE_NOT_FOUND;
}
gx3de_result gx3de_curved_texture_footprint_get(gx3de_curved_texture* a,
    gx3de_segment3* segments,uint64_t capacity,uint64_t* count){
    if(!a||!count||(!segments&&capacity))return GX3DE_INVALID_ARGUMENT;
    *count=a->boundary.size();if(capacity<a->boundary.size())return GX3DE_RANGE;
    if(segments)std::copy(a->boundary.begin(),a->boundary.end(),segments);
    return GX3DE_OK;
}
gx3de_result gx3de_curved_texture_status_get(gx3de_curved_texture* a,
    gx3de_curved_texture_status* out){
    if(!a||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    *out=a->status;return GX3DE_OK;
}
gx3de_result gx3de_curved_texture_seams_get(gx3de_curved_texture* a,
    gx3de_segment3* segments,uint64_t capacity,uint64_t* count){
    if(!a||!count||(!segments&&capacity))return GX3DE_INVALID_ARGUMENT;
    *count=a->seams.size();if(capacity<a->seams.size())return GX3DE_RANGE;
    if(segments)std::copy(a->seams.begin(),a->seams.end(),segments);
    return GX3DE_OK;
}
gx3de_result gx3de_curved_texture_destroy(gx3de_curved_texture* a){
    if(!a)return GX3DE_INVALID_ARGUMENT;
    erase_ptr(a->object->curved_textures,a);delete a;return GX3DE_OK;
}
