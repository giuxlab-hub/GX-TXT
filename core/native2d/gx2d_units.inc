/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Coordinate-frame conversion stages complete geometry and all dimensional
 * engine state, validates it, then commits without an intermediate mutation. */
static int units_point(gx2d_point *p,double factor) {
    p->x*=factor;p->y*=factor;return finite2(*p);
}
static int units_rect(gx2d_rect *r,double factor) {
    r->x0*=factor;r->y0*=factor;r->x1*=factor;r->y1*=factor;return valid_rect(*r);
}
gx2d_status gx2d_scene_rescale_coordinates(gx2d_scene *s,double factor) {
    gx2d_scene next;size_t i,j;gx2d_status code=GX2D_RANGE;
    if(!s||!isfinite(factor)||factor<=0)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    if(factor==1)return GX2D_OK;
    next=*s;next.objects=NULL;next.rules=NULL;next.blocks=NULL;
    next.objects=(object *)calloc(s->object_count?s->object_count:1,sizeof(object));
    next.rules=(rule *)malloc((s->rule_count?s->rule_count:1)*sizeof(rule));
    next.blocks=(block *)malloc((s->block_count?s->block_count:1)*sizeof(block));
    if(!next.objects||!next.rules||!next.blocks){code=GX2D_NOMEM;goto done;}
    if(s->rule_count)memcpy(next.rules,s->rules,s->rule_count*sizeof(rule));
    if(s->block_count)memcpy(next.blocks,s->blocks,s->block_count*sizeof(block));
    for(i=0;i<s->object_count;++i) {
        next.objects[i]=s->objects[i];next.objects[i].points=NULL;next.objects[i].capacity=next.objects[i].count;
        next.objects[i].sketch=NULL;
        if(s->objects[i].sketch) {
            gx2d_sketch_definition *d=sketch_clone(s->objects[i].sketch);next.objects[i].sketch=d;
            if(!d){code=GX2D_NOMEM;goto done;}
            if(s->objects[i].reference_image||sketch_is_composition(d)) {
                /* Pixel coordinates/dimensions remain immutable. Physical unit
                 * conversion scales the image-to-world linear map instead. */
                for(j=0;j<4;j++)d->matrix[j]*=factor;
            } else for(j=0;j<d->control_count;++j)if(!units_point(&((gx2d_point *)d->controls)[j],factor))goto done;
            for(j=0;j<d->tangent_count;j++){gx2d_spline_tangent *arm=(gx2d_spline_tangent *)&d->tangents[j];if(!units_point(&arm->incoming,factor)||!units_point(&arm->outgoing,factor))goto done;}
            d->radius_x*=factor;d->radius_y*=factor;d->matrix[4]*=factor;d->matrix[5]*=factor;
            if(gx2d_sketch_validate(d)!=GX2D_OK)goto done;
        }
        if(s->objects[i].count) {
            next.objects[i].points=(gx2d_point *)malloc(s->objects[i].count*sizeof(gx2d_point));
            if(!next.objects[i].points){code=GX2D_NOMEM;goto done;}
            memcpy(next.objects[i].points,s->objects[i].points,s->objects[i].count*sizeof(gx2d_point));
            for(j=0;j<next.objects[i].count;++j)if(!units_point(&next.objects[i].points[j],factor))goto done;
        }
    }
    for(i=0;i<s->rule_count;++i) {
        rule *r=&next.rules[i];
        if(r->spec.kind==GX2D_DISTANCE||r->spec.kind==GX2D_RADIUS||r->spec.kind==GX2D_DIAMETER||r->spec.kind==GX2D_LOCK_X||r->spec.kind==GX2D_LOCK_Y||r->spec.kind==GX2D_HORIZONTAL_DISTANCE||r->spec.kind==GX2D_VERTICAL_DISTANCE||r->spec.kind==GX2D_POINT_LINE_DISTANCE||r->spec.kind==GX2D_LINE_DISTANCE){r->spec.value*=factor;if(!isfinite(r->spec.value))goto done;}
        if(r->spec.kind==GX2D_FIXED||r->spec.kind==GX2D_DISTANCE||r->spec.kind>GX2D_PERPENDICULAR){r->spec.tolerance*=factor;if(!isfinite(r->spec.tolerance)||r->spec.tolerance<=0)goto done;}
        if(r->presentation.placed&&!units_point(&r->presentation.annotation,factor))goto done;
        if(r->spec.kind==GX2D_CURVATURE){r->presentation.curvature_tolerance=(r->presentation.curvature_tolerance>0?r->presentation.curvature_tolerance:1e-8)/factor;if(!isfinite(r->presentation.curvature_tolerance))goto done;}
        if(r->spec.kind==GX2D_FIXED&&!units_point(&r->anchor,factor))goto done;
    }
    for(i=0;i<s->block_count;++i)if(!units_rect(&next.blocks[i].rect,factor))goto done;
    if(!units_rect(&next.view.world,factor)||!units_rect(&next.requested_view.world,factor)||
        next.view.world.x0==next.view.world.x1||next.view.world.y0==next.view.world.y1||
        next.requested_view.world.x0==next.requested_view.world.x1||next.requested_view.world.y0==next.requested_view.world.y1)goto done;
    {gx2d_point projected;
        double sx=(next.view.width-next.view.left-next.view.right)/(next.view.world.x1-next.view.world.x0);
        double sy=(next.view.height-next.view.top-next.view.bottom)/(next.view.world.y1-next.view.world.y0);
        if(!isfinite(sx)||!isfinite(sy)||sx<=0||sy<=0)goto done;
        if(gx2d_world_to_device(&next,(gx2d_point){next.view.world.x0,next.view.world.y0},&projected)!=GX2D_OK||
            gx2d_world_to_device(&next,(gx2d_point){next.view.world.x1,next.view.world.y1},&projected)!=GX2D_OK)goto done;}
    if(!units_point(&next.custom_pivot,factor)||!units_point(&next.drag_pivot,factor)||
        !units_point(&next.grid.origin,factor)||!units_point(&next.gizmo.mirror_a,factor)||
        !units_point(&next.gizmo.mirror_b,factor)||!units_point(&next.polar.origin,factor))goto done;
    next.grid.spacing_x*=factor;next.grid.spacing_y*=factor;
    next.polar.radius_min*=factor;next.polar.radius_max*=factor;next.polar.radial_spacing*=factor;
    if(!isfinite(next.grid.spacing_x)||next.grid.spacing_x<=0||!isfinite(next.grid.spacing_y)||next.grid.spacing_y<=0||
        !isfinite(next.polar.radius_min)||!isfinite(next.polar.radius_max)||next.polar.radius_min<0||next.polar.radius_max<=next.polar.radius_min||
        !isfinite(next.polar.radial_spacing)||next.polar.radial_spacing<=0)goto done;
    code=gx2d_check_constraints(&next);if(code!=GX2D_OK)goto done;
    for(i=0;i<s->object_count;++i){gx2d_point *old=s->objects[i].points;gx2d_sketch_definition *oldSketch=s->objects[i].sketch;s->objects[i].points=next.objects[i].points;s->objects[i].sketch=next.objects[i].sketch;s->objects[i].capacity=next.objects[i].capacity;next.objects[i].points=old;next.objects[i].sketch=oldSketch;}
    {rule *old=s->rules;s->rules=next.rules;next.rules=old;block *blocks=s->blocks;s->blocks=next.blocks;next.blocks=blocks;}
    s->view=next.view;s->requested_view=next.requested_view;s->custom_pivot=next.custom_pivot;s->drag_pivot=next.drag_pivot;
    s->grid=next.grid;s->gizmo=next.gizmo;s->polar=next.polar;
    code=GX2D_OK;
done:
    if(next.objects){for(i=0;i<s->object_count;++i){free(next.objects[i].points);sketch_free(next.objects[i].sketch);}}free(next.objects);free(next.rules);free(next.blocks);return code;
}
