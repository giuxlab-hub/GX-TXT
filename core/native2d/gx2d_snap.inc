/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Exact Native scene search, never a display/LOD approximation. */
static gx2d_status snap_vertex(const gx2d_scene *s,gx2d_point query,double radius,
    const gx2d_id *excluded,size_t excluded_count,int endpoints,int device,gx2d_hit *out) {
    gx2d_id *ids=NULL;size_t count=0,i,j,k;gx2d_status code;gx2d_hit best;
    long double distance=radius;int found=0;
    if(!s||!out||!finite2(query)||!isfinite(radius)||radius<0||
        (excluded_count&&!excluded)||(endpoints!=0&&endpoints!=1))return GX2D_INVALID;
    if(excluded_count){code=cad_expand(s,excluded,excluded_count,&ids,&count);if(code!=GX2D_OK)return code;}
    for(i=0;i<s->object_count;++i) {
        const object *o=&s->objects[i];if(o->kind==GX2D_GROUP||!can_select(s,o))continue;
        for(k=0;k<count&&ids[k]!=o->id;++k){}if(k<count)continue;
        for(j=0;j<o->count;++j) {
            gx2d_point candidate=o->points[j];long double dx,dy,d;
            if(endpoints&&o->kind==GX2D_CURVE&&j>0&&j+1<o->count&&!o->breaks[j-1]&&!o->breaks[j])continue;
            if(device){code=gx2d_world_to_device(s,candidate,&candidate);if(code!=GX2D_OK){free(ids);return code;}}
            dx=(long double)candidate.x-query.x;dy=(long double)candidate.y-query.y;
            if(fabsl(dx)>distance||fabsl(dy)>distance)continue;
            d=hypotl(dx,dy);
            if(d<=distance&&(!found||d<distance||o->id<best.object||(o->id==best.object&&j<best.point_index))) {
                distance=d;best=(gx2d_hit){o->id,j,o->points[j],(double)d};found=1;
            }
        }
    }
    free(ids);if(!found)return GX2D_NOT_FOUND;*out=best;return GX2D_OK;
}
gx2d_status gx2d_scene_nearest_vertex(const gx2d_scene *s,gx2d_point query,double radius,
    const gx2d_id *excluded,size_t excluded_count,int endpoints,gx2d_hit *out) {
    return snap_vertex(s,query,radius,excluded,excluded_count,endpoints,0,out);
}
gx2d_status gx2d_scene_nearest_vertex_device(const gx2d_scene *s,gx2d_point query,double radius,
    const gx2d_id *excluded,size_t excluded_count,int endpoints,gx2d_hit *out) {
    return snap_vertex(s,query,radius,excluded,excluded_count,endpoints,1,out);
}
gx2d_status gx2d_gizmo_snap_translation(const gx2d_scene *s,gx2d_gizmo_handle handle,
    gx2d_point pivot,gx2d_point requested,double radius,const gx2d_id *excluded,
    size_t excluded_count,int endpoints,gx2d_point *translation,int *snapped,gx2d_hit *target) {
    gx2d_scene captured;gx2d_point probe,device,delta;gx2d_hit hit;gx2d_status code;
    if(!s||!translation||!snapped||!target||!finite2(pivot)||!finite2(requested)||
        (handle!=GX2D_HANDLE_X&&handle!=GX2D_HANDLE_Y&&handle!=GX2D_HANDLE_FREE))return GX2D_INVALID;
    if(excluded_count>65536||(excluded_count&&!excluded))return GX2D_INVALID;
    for(size_t i=0;i<excluded_count;++i)if(!cobj(s,excluded[i]))return GX2D_NOT_FOUND;
    probe=(gx2d_point){pivot.x+requested.x,pivot.y+requested.y};if(!finite2(probe))return GX2D_RANGE;
    captured=*s;if(s->dragging)captured.view=s->drag_view;
    code=gx2d_world_to_device(&captured,probe,&device);if(code!=GX2D_OK)return code;
    code=gx2d_scene_nearest_vertex_device(&captured,device,radius,excluded,excluded_count,endpoints,&hit);
    if(code==GX2D_NOT_FOUND){*translation=requested;*snapped=0;return GX2D_OK;}if(code!=GX2D_OK)return code;
    delta=(gx2d_point){hit.point.x-pivot.x,hit.point.y-pivot.y};
    if(handle!=GX2D_HANDLE_FREE) {
        double angle=s->gizmo.axes_angle+(handle==GX2D_HANDLE_Y?acos(-1.)/2:0);
        long double x=cos(angle),y=sin(angle),projection=(long double)delta.x*x+(long double)delta.y*y;
        delta=(gx2d_point){(double)(projection*x),(double)(projection*y)};
    }
    if(!finite2(delta))return GX2D_RANGE;
    *translation=delta;*snapped=1;*target=hit;return GX2D_OK;
}
