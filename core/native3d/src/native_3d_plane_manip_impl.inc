// SPDX-License-Identifier: GPL-3.0-or-later
// Camera/ray manipulation for working planes, clip planes and box faces.
static gx3de_vec3 manipulation_axis(uint32_t handle){
    switch(handle){
    case GX3DE_MANIP_X:case GX3DE_MANIP_BOX_MIN_X:case GX3DE_MANIP_BOX_MAX_X:return {1,0,0};
    case GX3DE_MANIP_Y:case GX3DE_MANIP_BOX_MIN_Y:case GX3DE_MANIP_BOX_MAX_Y:return {0,1,0};
    case GX3DE_MANIP_Z:case GX3DE_MANIP_BOX_MIN_Z:case GX3DE_MANIP_BOX_MAX_Z:return {0,0,1};
    default:return {0,0,0};}
}
static gx3de_vec3 manipulation_rotate(gx3de_vec3 value,gx3de_vec3 axis,double angle){
    const double c=std::cos(angle),s=std::sin(angle);
    return add(add(mul(value,c),mul(cross(axis,value),s)),mul(axis,dot(axis,value)*(1-c)));
}
extern "C" GX3DE_API gx3de_result gx3de_view_manipulation_begin(gx3de_viewport* vp,uint32_t target,uint32_t slot,
    uint32_t action,uint32_t handle,uint32_t x,uint32_t y,gx3de_view_manipulation** out){
    if(!vp||!out||x>=vp->width||y>=vp->height||target<GX3DE_MANIP_WORKING_PLANE||
       target>GX3DE_MANIP_CLIP_BOX||action<GX3DE_MANIP_TRANSLATE||action>GX3DE_MANIP_ROTATE)
        return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    if(target==GX3DE_MANIP_CLIP_BOX){
        if(action!=GX3DE_MANIP_TRANSLATE||handle<GX3DE_MANIP_BOX_MIN_X||handle>GX3DE_MANIP_BOX_MAX_Z)
            return GX3DE_INVALID_ARGUMENT;
        if(!vp->view->clip_box.enabled)return GX3DE_NOT_FOUND;
    }else if(action==GX3DE_MANIP_ROTATE){
        if(handle<GX3DE_MANIP_X||handle>GX3DE_MANIP_Z)return GX3DE_INVALID_ARGUMENT;
    }else if(handle>GX3DE_MANIP_Z)return GX3DE_INVALID_ARGUMENT;
    if(target==GX3DE_MANIP_CLIP_PLANE&&(slot>=GX3DE_MAX_VIEW_CLIP_PLANES||!vp->view->clips[slot].enabled))
        return GX3DE_NOT_FOUND;
    if(target==GX3DE_MANIP_WORKING_PLANE&&!vp->view->working_plane)return GX3DE_NOT_FOUND;
    auto* m=new(std::nothrow) gx3de_view_manipulation{};if(!m)return GX3DE_OUT_OF_MEMORY;
    m->viewport=vp;m->target=target;m->slot=slot;m->action=action;m->handle=handle;
    m->start_x=x;m->start_y=y;m->forward=gizmo_unit(sub(vp->view->camera.target,vp->view->camera.position));
    if(length(m->forward)<1e-12){delete m;return GX3DE_DEGENERATE;}
    if(target==GX3DE_MANIP_WORKING_PLANE){m->plane=vp->view->working_plane;
        m->origin=m->plane->origin;m->normal=m->plane->n;m->u=m->plane->u;}
    else if(target==GX3DE_MANIP_CLIP_PLANE){m->clip=vp->view->clips[slot];
        m->origin=m->clip.origin;m->normal=m->clip.normal;}
    else{m->box=vp->view->clip_box;
        m->origin=mul(add(m->box.world_bounds.min,m->box.world_bounds.max),.5);}
    try{vp->view->plane_manipulations.push_back(m);*out=m;return GX3DE_OK;}
    catch(const std::bad_alloc&){delete m;return GX3DE_OUT_OF_MEMORY;}
}
extern "C" GX3DE_API gx3de_result gx3de_view_manipulation_update(gx3de_view_manipulation* m,uint32_t x,uint32_t y,
    gx3de_view_manipulation_result* out){
    if(!m||!out||out->struct_size<sizeof(*out)||x>=m->viewport->width||y>=m->viewport->height)
        return GX3DE_INVALID_ARGUMENT;
    gx3de_vec3 origin=m->origin,normal=m->normal,u=m->u;
    gx3de_view_clip_box box=m->box;
    if(m->action==GX3DE_MANIP_TRANSLATE){
        gx3de_ray start{};start.struct_size=sizeof(start);
        gx3de_ray now{};now.struct_size=sizeof(now);
        auto rc=gx3de_viewport_ray(m->viewport,m->start_x,m->start_y,&start);
        if(rc==GX3DE_OK)rc=gx3de_viewport_ray(m->viewport,x,y,&now);
        if(rc!=GX3DE_OK)return rc;
        gx3de_vec3 a{},b{};
        if(!gizmo_ray_plane(&start,m->origin,m->forward,a)||
           !gizmo_ray_plane(&now,m->origin,m->forward,b))return GX3DE_DEGENERATE;
        gx3de_vec3 delta=sub(b,a);
        if(m->handle!=GX3DE_MANIP_FREE){auto axis=manipulation_axis(m->handle);
            delta=mul(axis,dot(delta,axis));}
        if(m->target==GX3DE_MANIP_CLIP_BOX){
            auto& min=box.world_bounds.min;auto& max=box.world_bounds.max;
            switch(m->handle){
            case GX3DE_MANIP_BOX_MIN_X:min.x+=delta.x;break;
            case GX3DE_MANIP_BOX_MIN_Y:min.y+=delta.y;break;
            case GX3DE_MANIP_BOX_MIN_Z:min.z+=delta.z;break;
            case GX3DE_MANIP_BOX_MAX_X:max.x+=delta.x;break;
            case GX3DE_MANIP_BOX_MAX_Y:max.y+=delta.y;break;
            case GX3DE_MANIP_BOX_MAX_Z:max.z+=delta.z;break;}
            rc=gx3de_view_clip_box_set(m->viewport->view,&box);
            if(rc!=GX3DE_OK)return rc;
            origin=mul(add(min,max),.5);
        }else origin=add(origin,delta);
    }else{
        const double angle=(double(int64_t(x)-int64_t(m->start_x))+
                            double(int64_t(y)-int64_t(m->start_y)))*.006;
        const auto axis=manipulation_axis(m->handle);
        normal=manipulation_rotate(normal,axis,angle);
        if(m->target==GX3DE_MANIP_WORKING_PLANE)u=manipulation_rotate(u,axis,angle);
    }
    gx3de_result rc=GX3DE_OK;
    if(m->target==GX3DE_MANIP_WORKING_PLANE)
        rc=gx3de_plane_set(m->plane,origin,normal,u);
    else if(m->target==GX3DE_MANIP_CLIP_PLANE){auto clip=m->clip;
        clip.origin=origin;clip.normal=normal;
        rc=gx3de_view_clip_plane_set(m->viewport->view,m->slot,&clip);}
    if(rc!=GX3DE_OK)return rc;
    gx3de_view_manipulation_result result{};result.struct_size=sizeof(result);
    result.target=m->target;result.action=m->action;result.handle=m->handle;
    result.origin=origin;result.normal=normal;result.u_axis=u;
    result.box=m->target==GX3DE_MANIP_CLIP_BOX?box:m->viewport->view->clip_box;
    *out=result;return GX3DE_OK;
}
extern "C" GX3DE_API gx3de_result gx3de_view_manipulation_end(gx3de_view_manipulation* m,uint32_t accept){
    if(!m||accept>1)return GX3DE_INVALID_ARGUMENT;
    gx3de_result rc=GX3DE_OK;
    if(!accept){
        if(m->target==GX3DE_MANIP_WORKING_PLANE)rc=gx3de_plane_set(m->plane,m->origin,m->normal,m->u);
        else if(m->target==GX3DE_MANIP_CLIP_PLANE)
            rc=gx3de_view_clip_plane_set(m->viewport->view,m->slot,&m->clip);
        else rc=gx3de_view_clip_box_set(m->viewport->view,&m->box);
    }
    erase_ptr(m->viewport->view->plane_manipulations,m);delete m;return rc;
}
