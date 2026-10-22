// SPDX-License-Identifier: GPL-3.0-or-later
// The ray drag solver is independent of VTK; only gizmo_pick uses rendered props.
static bool gizmo_ray_valid(const gx3de_ray* ray) {
    return ray&&ray->struct_size>=sizeof(gx3de_ray)&&finite(ray->origin)&&
        finite(ray->direction)&&length(ray->direction)>1e-12;
}
static gx3de_vec3 gizmo_unit(gx3de_vec3 value) {
    const double n=length(value);return n>1e-12?mul(value,1.0/n):gx3de_vec3{};
}
static uint32_t gizmo_family(uint32_t handle) {
    if(handle>=1&&handle<=3)return GX3DE_GIZMO_FAMILY_AXIS;
    if(handle>=4&&handle<=6)return GX3DE_GIZMO_FAMILY_PLANE;
    if(handle==7)return GX3DE_GIZMO_FAMILY_FREE;
    if(handle>=8&&handle<=10)return GX3DE_GIZMO_FAMILY_ROTATE;
    return 0;
}
static bool gizmo_ray_plane(const gx3de_ray* ray,gx3de_vec3 pivot,
                            gx3de_vec3 normal,gx3de_vec3& point) {
    const double denominator=dot(ray->direction,normal);
    if(std::abs(denominator)<1e-10*length(ray->direction))return false;
    const double distance=dot(sub(pivot,ray->origin),normal)/denominator;
    if(!std::isfinite(distance)||distance<0)return false;
    point=add(ray->origin,mul(ray->direction,distance));return finite(point);
}
static bool gizmo_pivot(const gx3de_gizmo* gizmo,gx3de_vec3& out) {
    const auto& s=gizmo->spec;
    if(s.pivot_mode==GX3DE_GIZMO_PIVOT_EXPLICIT){out=s.world_pivot;return finite(out);}
    if(s.pivot_mode==GX3DE_GIZMO_PIVOT_ANCHOR)
        return s.anchor&&gx3de_anchor_position(s.anchor,&out)==GX3DE_OK;
    if(!s.object)return false;
    out=apply(world(s.object),{0,0,0});return finite(out);
}
static bool gizmo_spec_valid(const gx3de_view* view,const gx3de_gizmo_spec* spec) {
    if(!spec||spec->struct_size<sizeof(*spec)||spec->visible>1||spec->preview_only>1||
       (spec->space!=GX3DE_GIZMO_SPACE_WORLD&&spec->space!=GX3DE_GIZMO_SPACE_LOCAL)||
       !spec->families||(spec->families&~15u)||!spec->object||
       spec->object->scene!=view->scene||spec->pivot_mode<GX3DE_GIZMO_PIVOT_OBJECT||
       spec->pivot_mode>GX3DE_GIZMO_PIVOT_ANCHOR||!finite(spec->world_pivot)||
       !std::isfinite(spec->size_pixels)||spec->size_pixels<12||spec->size_pixels>512)return false;
    if(spec->pivot_mode==GX3DE_GIZMO_PIVOT_ANCHOR&&
       (!spec->anchor||spec->anchor->scene!=view->scene))return false;
    if(spec->anchor&&spec->anchor->scene!=view->scene)return false;
    return true;
}
gx3de_result gx3de_view_axes_set(gx3de_view* view,const gx3de_view_axes* axes) {
    if(!view||!axes||axes->struct_size<sizeof(*axes)||axes->show_world>1||
       axes->show_local>1||axes->show_reference>1||!std::isfinite(axes->size_pixels)||
       axes->size_pixels<12||axes->size_pixels>512)return GX3DE_INVALID_ARGUMENT;
    if(axes->local_object&&axes->local_object->scene!=view->scene)return GX3DE_WRONG_OWNER;
    if(axes->reference_axis&&axes->reference_axis->scene!=view->scene)return GX3DE_WRONG_OWNER;
    if(axes->show_local&&!axes->local_object)return GX3DE_INVALID_ARGUMENT;
    if(axes->show_reference&&!axes->reference_axis)return GX3DE_INVALID_ARGUMENT;
    view->axes=*axes;view->axes.struct_size=sizeof(*axes);return GX3DE_OK;
}
gx3de_result gx3de_view_axes_get(gx3de_view* view,gx3de_view_axes* axes) {
    if(!view||!axes||axes->struct_size<sizeof(*axes))return GX3DE_INVALID_ARGUMENT;
    *axes=view->axes;return GX3DE_OK;
}
gx3de_result gx3de_gizmo_create(gx3de_view* view,const gx3de_gizmo_spec* spec,
                                  gx3de_gizmo** out) {
    if(!view||!out)return GX3DE_INVALID_ARGUMENT;
    if(spec&&spec->struct_size>=sizeof(*spec)&&
       ((spec->object&&spec->object->scene!=view->scene)||
        (spec->anchor&&spec->anchor->scene!=view->scene)))return GX3DE_WRONG_OWNER;
    if(!gizmo_spec_valid(view,spec))return GX3DE_INVALID_ARGUMENT;
    auto* gizmo=new(std::nothrow) gx3de_gizmo{};if(!gizmo)return GX3DE_OUT_OF_MEMORY;
    gizmo->view=view;gizmo->spec=*spec;gizmo->spec.struct_size=sizeof(*spec);
    return retain(view->gizmos,gizmo,out);
}
gx3de_result gx3de_gizmo_destroy(gx3de_gizmo* gizmo) {
    if(!gizmo)return GX3DE_INVALID_ARGUMENT;
    if(gizmo->active)gx3de_gizmo_end(gizmo,0);
    erase_ptr(gizmo->view->gizmos,gizmo);delete gizmo;return GX3DE_OK;
}
gx3de_result gx3de_gizmo_set(gx3de_gizmo* gizmo,const gx3de_gizmo_spec* spec) {
    if(!gizmo)return GX3DE_INVALID_ARGUMENT;
    if(gizmo->active)return GX3DE_UNSUPPORTED;
    if(spec&&spec->struct_size>=sizeof(*spec)&&
       ((spec->object&&spec->object->scene!=gizmo->view->scene)||
        (spec->anchor&&spec->anchor->scene!=gizmo->view->scene)))return GX3DE_WRONG_OWNER;
    if(!gizmo_spec_valid(gizmo->view,spec))return GX3DE_INVALID_ARGUMENT;
    gizmo->spec=*spec;gizmo->spec.struct_size=sizeof(*spec);gizmo->hover=0;
    return GX3DE_OK;
}
gx3de_result gx3de_gizmo_get(gx3de_gizmo* gizmo,gx3de_gizmo_spec* spec) {
    if(!gizmo||!spec||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    *spec=gizmo->spec;return GX3DE_OK;
}
gx3de_result gx3de_gizmo_hover_set(gx3de_gizmo* gizmo,uint32_t handle) {
    if(!gizmo||handle>GX3DE_GIZMO_ROTATE_Z)return GX3DE_INVALID_ARGUMENT;
    if(handle&&!(gizmo->spec.families&gizmo_family(handle)))return GX3DE_UNSUPPORTED;
    gizmo->hover=handle;return GX3DE_OK;
}
gx3de_result gx3de_gizmo_begin(gx3de_gizmo* gizmo,uint32_t handle,const gx3de_ray* ray) {
    if(!gizmo||!gizmo_ray_valid(ray)||!gizmo_family(handle))return GX3DE_INVALID_ARGUMENT;
    if(!gizmo->spec.object||!gizmo->spec.visible||
       !(gizmo->spec.families&gizmo_family(handle)))return GX3DE_UNSUPPORTED;
    if(gizmo->active)return GX3DE_UNSUPPORTED;
    gizmo->initial_local=gizmo->spec.object->transform;
    gizmo->initial_world=world(gizmo->spec.object);
    if(!gizmo_pivot(gizmo,gizmo->pivot))return GX3DE_NOT_FOUND;
    for(int i=0;i<3;++i){auto axis=gx3de_vec3{};
        if(i==0)axis={1,0,0};else if(i==1)axis={0,1,0};else axis={0,0,1};
        if(gizmo->spec.space==GX3DE_GIZMO_SPACE_LOCAL){const auto& m=gizmo->initial_world;
            axis={m.m[i*4],m.m[i*4+1],m.m[i*4+2]};}
        gizmo->basis[i]=gizmo_unit(axis);
        if(length(gizmo->basis[i])<1e-12)return GX3DE_DEGENERATE;}
    if(gizmo->spec.space==GX3DE_GIZMO_SPACE_LOCAL)
        for(int i=0;i<3;++i)for(int j=i+1;j<3;++j)
            if(std::abs(dot(gizmo->basis[i],gizmo->basis[j]))>1e-6)
                return GX3DE_UNSUPPORTED; // a sheared frame has no orthogonal rotation axes
    gx3de_vec3 normal{};
    if(handle<=3){auto axis=gizmo->basis[handle-1];
        // Plane contains the constrained axis and faces the pointer ray.
        normal=gizmo_unit(sub(ray->direction,mul(axis,dot(ray->direction,axis))));}
    else if(handle==4)normal=gizmo_unit(cross(gizmo->basis[0],gizmo->basis[1]));
    else if(handle==5)normal=gizmo_unit(cross(gizmo->basis[1],gizmo->basis[2]));
    else if(handle==6)normal=gizmo_unit(cross(gizmo->basis[2],gizmo->basis[0]));
    else if(handle==7)normal=gizmo_unit(ray->direction);
    else normal=gizmo->basis[handle-8];
    if(length(normal)<1e-12||!gizmo_ray_plane(ray,gizmo->pivot,normal,gizmo->start_point))
        return GX3DE_DEGENERATE;
    gizmo->drag_normal=normal;gizmo->active=handle;gizmo->angle=0;
    gizmo->translation_world={};gizmo->initial_scene_poses.clear();
    try{for(auto* o:gizmo->view->scene->objects)
            gizmo->initial_scene_poses.push_back({o,o->transform});}
    catch(const std::bad_alloc&){gizmo->active=0;return GX3DE_OUT_OF_MEMORY;}
    return GX3DE_OK;
}
static gx3de_mat4 gizmo_rotate(gx3de_vec3 axis,double radians,gx3de_vec3 pivot) {
    const double c=std::cos(radians),s=std::sin(radians),t=1-c;
    const double x=axis.x,y=axis.y,z=axis.z;auto m=identity();
    m.m[0]=t*x*x+c;m.m[4]=t*x*y-s*z;m.m[8]=t*x*z+s*y;
    m.m[1]=t*x*y+s*z;m.m[5]=t*y*y+c;m.m[9]=t*y*z-s*x;
    m.m[2]=t*x*z-s*y;m.m[6]=t*y*z+s*x;m.m[10]=t*z*z+c;
    return product(product(translation(pivot),m),translation(mul(pivot,-1)));
}
gx3de_result gx3de_gizmo_update(gx3de_gizmo* gizmo,const gx3de_ray* ray,
                                  gx3de_gizmo_result* out) {
    if(!gizmo||!gizmo_ray_valid(ray)||!out||out->struct_size<sizeof(*out))
        return GX3DE_INVALID_ARGUMENT;
    if(!gizmo->active||!gizmo->spec.object)return GX3DE_NOT_FOUND;
    auto* scene=gizmo->view->scene;
    auto restore=[&](){for(const auto& entry:gizmo->initial_scene_poses)
        if(std::find(scene->objects.begin(),scene->objects.end(),entry.first)!=scene->objects.end())
            entry.first->transform=entry.second;};
    gx3de_vec3 point{};
    if(!gizmo_ray_plane(ray,gizmo->pivot,gizmo->drag_normal,point))return GX3DE_DEGENERATE;
    const uint32_t handle=gizmo->active;gx3de_vec3 delta{};double angle=0;
    if(handle<=7){delta=sub(point,gizmo->start_point);
        if(handle<=3){auto axis=gizmo->basis[handle-1];delta=mul(axis,dot(delta,axis));}
        else if(handle!=7)delta=sub(delta,mul(gizmo->drag_normal,dot(delta,gizmo->drag_normal)));}
    else {const auto a=gizmo_unit(sub(gizmo->start_point,gizmo->pivot));
        const auto b=gizmo_unit(sub(point,gizmo->pivot));
        if(length(a)<1e-12||length(b)<1e-12)return GX3DE_DEGENERATE;
        angle=std::atan2(dot(cross(a,b),gizmo->drag_normal),dot(a,b));}
    if(!finite(delta)||!std::isfinite(angle))return GX3DE_DEGENERATE;
    restore(); // parent pose must be the one captured at begin on every update
    const auto change=handle<=7?translation(delta):
        gizmo_rotate(gizmo->drag_normal,angle,gizmo->pivot);
    const auto desired_world=product(change,gizmo->initial_world);
    gx3de_mat4 desired_local=desired_world;
    if(gizmo->spec.object->parent){gx3de_mat4 parent_inverse{};
        if(!inverse_affine(world(gizmo->spec.object->parent),parent_inverse))
            return GX3DE_DEGENERATE;
        desired_local=product(parent_inverse,desired_world);}
    if(!affine(desired_local))return GX3DE_DEGENERATE;
    const gx3de_mat4 requested_local=desired_local;
    gizmo->spec.object->transform=desired_local;
    std::vector<gx3de_constraint*> related;
    auto* moved=gizmo->spec.object;
    try{for(auto* c:scene->constraints){bool touches=c->spec.moving_object==moved||
            (c->spec.a&&c->spec.a->object==moved)||
            (c->spec.b&&c->spec.b->object==moved)||
            c->extended_spec.surface_object==moved;
            for(auto* anchor:c->extended_spec.anchors)
                touches|=anchor&&anchor->object==moved;
            if(touches)related.push_back(c);}}
    catch(const std::bad_alloc&){restore();return GX3DE_OUT_OF_MEMORY;}
    uint32_t status=GX3DE_CONSTRAINT_SATISFIED;
    if(!related.empty()){gx3de_constraint_system_result solved{sizeof(solved)};
        auto rc=gx3de_constraint_system_solve(scene,related.data(),related.size(),0,&solved);
        status=rc==GX3DE_OK?solved.status:GX3DE_CONSTRAINT_UNSUPPORTED;
        if(rc!=GX3DE_OK||status==GX3DE_CONSTRAINT_VIOLATED||
           status==GX3DE_CONSTRAINT_OVERCONSTRAINED||status==GX3DE_CONSTRAINT_UNSUPPORTED){
            restore();*out={sizeof(*out),handle,status,0,delta,angle,desired_local,{}};
            return rc==GX3DE_OK?GX3DE_DEGENERATE:rc;}
        desired_local=gizmo->spec.object->transform;
        // A fixed or incompatible system may solve by undoing the requested
        // drag. Report that as an overconstraint rather than a false commit.
        const auto solved_world=world(gizmo->spec.object);
        double deviation=0,scale=1;
        for(int i=0;i<16;++i){deviation=std::max(deviation,
            std::max(std::abs(desired_local.m[i]-requested_local.m[i]),
                     std::abs(solved_world.m[i]-desired_world.m[i])));
            scale=std::max({scale,std::abs(desired_local.m[i]),std::abs(desired_world.m[i])});}
        if(deviation>1e-7*scale){restore();*out={sizeof(*out),handle,
            GX3DE_CONSTRAINT_OVERCONSTRAINED,0,delta,angle,desired_local,{}};
            return GX3DE_DEGENERATE;}}
    *out={sizeof(*out),handle,status,0,delta,angle,desired_local,{}};
    gizmo->translation_world=delta;gizmo->angle=angle;
    if(gizmo->spec.preview_only)restore();
    return GX3DE_OK;
}
gx3de_result gx3de_gizmo_end(gx3de_gizmo* gizmo,uint32_t accept) {
    if(!gizmo||accept>1)return GX3DE_INVALID_ARGUMENT;
    if(!gizmo->active)return GX3DE_NOT_FOUND;
    if(!accept||gizmo->spec.preview_only){auto* scene=gizmo->view->scene;
        for(const auto& entry:gizmo->initial_scene_poses)
            if(std::find(scene->objects.begin(),scene->objects.end(),entry.first)!=scene->objects.end())
                entry.first->transform=entry.second;}
    gizmo->active=0;gizmo->initial_scene_poses.clear();return GX3DE_OK;
}
gx3de_result gx3de_viewport_ray(gx3de_viewport* vp,uint32_t x,uint32_t y,gx3de_ray* out) {
    if(!vp||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    if(x>=vp->width||y>=vp->height)return GX3DE_RANGE;
    const auto& c=vp->view->camera;const auto forward=gizmo_unit(sub(c.target,c.position));
    const auto right=gizmo_unit(cross(forward,c.up)),up=gizmo_unit(cross(right,forward));
    const double height=2*std::tan(c.vertical_fov_degrees*3.141592653589793/360.0);
    const double nx=(2*(double(x)+0.5)/vp->width-1)*height*vp->width/vp->height*0.5;
    const double ny=(1-2*(double(y)+0.5)/vp->height)*height*0.5;
    const double distance=length(sub(c.position,c.target));
    gx3de_vec3 origin=c.position,direction{};
    if(c.orthographic){const double scale=vp->view->orthographic_height>0?
        vp->view->orthographic_height/(distance*height):1.0;
        origin=add(origin,add(mul(right,nx*distance*scale),mul(up,ny*distance*scale)));
        direction=forward;}
    else direction=gizmo_unit(add(forward,add(mul(right,nx),mul(up,ny))));
    *out={sizeof(*out),0,origin,direction,{}};return GX3DE_OK;
}
gx3de_result gx3de_gizmo_begin_screen(gx3de_gizmo* gizmo,gx3de_viewport* vp,
    uint32_t handle,uint32_t x,uint32_t y) {
    if(!gizmo||!vp||vp->view!=gizmo->view)return GX3DE_WRONG_OWNER;
    gx3de_ray ray{sizeof(ray)};auto rc=gx3de_viewport_ray(vp,x,y,&ray);
    return rc==GX3DE_OK?gx3de_gizmo_begin(gizmo,handle,&ray):rc;
}
gx3de_result gx3de_gizmo_update_screen(gx3de_gizmo* gizmo,gx3de_viewport* vp,
    uint32_t x,uint32_t y,gx3de_gizmo_result* out) {
    if(!gizmo||!vp||vp->view!=gizmo->view)return GX3DE_WRONG_OWNER;
    gx3de_ray ray{sizeof(ray)};auto rc=gx3de_viewport_ray(vp,x,y,&ray);
    return rc==GX3DE_OK?gx3de_gizmo_update(gizmo,&ray,out):rc;
}
gx3de_result gx3de_gizmo_pick(gx3de_viewport* vp,uint32_t x,uint32_t y,
                               gx3de_gizmo** gizmo,uint32_t* handle) {
    if(!vp||!gizmo||!handle)return GX3DE_INVALID_ARGUMENT;
    if(x>=vp->width||y>=vp->height)return GX3DE_RANGE;
    auto rc=gx3de_target_render(vp->target);if(rc!=GX3DE_OK)return rc;
    auto it=std::find_if(vp->target->rendered.begin(),vp->target->rendered.end(),
                         [vp](const gx3de_render_viewport& rv){return rv.viewport==vp;});
    if(it==vp->target->rendered.end())return GX3DE_NOT_FOUND;
    const int px=int(vp->x+x),py=int(vp->target->height-1-(vp->y+y));
    // The rotation arcs cross translation axes in screen space. Test each
    // visible handle actor individually and give the compact translation
    // handles first choice at a crossing instead of VTK's depth tie-break.
    for(uint32_t candidate=1;candidate<=GX3DE_GIZMO_ROTATE_Z;++candidate)
        for(const auto& prop:it->props)if(prop.gizmo&&prop.gizmo_handle==candidate){
            vtkNew<vtkCellPicker> picker;
            picker->SetTolerance(viewport_pick_tolerance(vp,3.0));
            picker->PickFromListOn();picker->AddPickList(prop.actor);
            if(picker->Pick(px,py,0,it->renderer)&&picker->GetActor()==prop.actor){
                *gizmo=prop.gizmo;*handle=candidate;return GX3DE_OK;}}
    return GX3DE_NOT_FOUND;
}
