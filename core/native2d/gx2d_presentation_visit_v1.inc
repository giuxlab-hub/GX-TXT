/* SPDX-License-Identifier: GPL-3.0-or-later
 * Read-only companion to the existing geometry implementation. Exact state
 * slices allow observers to detect all mutations, including drag/solver edits
 * that deliberately preserve topology epochs. No mutator, grid or snap changes.
 */
static int presentation_definition_visit(const gx2d_sketch_definition *d,
    gx2d_presentation_visitor_v1 visit,void *data) {
    gx2d_sketch_definition copy=*d;size_t i;
    copy.controls=NULL;copy.tangents=NULL;copy.path_segments=NULL;
    copy.parts=NULL;copy.part_reversed=NULL;copy.nodes=NULL;
    if(!visit(data,&copy,sizeof(copy)))return 0;
    if(d->controls&&d->control_count&&!visit(data,d->controls,d->control_count*sizeof(*d->controls)))return 0;
    if(d->tangents&&d->tangent_count&&!visit(data,d->tangents,d->tangent_count*sizeof(*d->tangents)))return 0;
    if(d->path_segments&&d->path_segment_count&&!visit(data,d->path_segments,d->path_segment_count*sizeof(*d->path_segments)))return 0;
    if(d->nodes&&d->node_count&&!visit(data,d->nodes,d->node_count*sizeof(*d->nodes)))return 0;
    if(d->part_reversed&&d->part_count&&!visit(data,d->part_reversed,d->part_count*sizeof(*d->part_reversed)))return 0;
    for(i=0;i<d->part_count;i++)if(!presentation_definition_visit(d->parts+i,visit,data))return 0;
    return 1;
}
gx2d_status gx2d_presentation_visit_v1(const gx2d_scene *s,gx2d_id id,
    gx2d_presentation_visitor_v1 visit,void *data) {
    const object *o;object copy;gx2d_layer_style style;
    if(!s||!visit)return GX2D_INVALID;o=cobj(s,id);if(!o)return GX2D_NOT_FOUND;
    copy=*o;copy.points=NULL;copy.manual=NULL;copy.breaks=NULL;copy.members=NULL;
    copy.part_states=NULL;copy.sketch=NULL;copy.capacity=copy.count;
    /* Presence is semantic: null optional arrays must not alias an empty but
     * present definition with the same counts. No pointer value is exported. */
    unsigned presence=(o->points?1:0)|(o->manual?2:0)|(o->breaks?4:0)|(o->sketch?8:0)|(o->members?16:0)|(o->part_states?32:0);
    if(!visit(data,&presence,sizeof presence)||!visit(data,&copy,sizeof copy))return GX2D_OK;
    if(o->points&&o->count&&!visit(data,o->points,o->count*sizeof(*o->points)))return GX2D_OK;
    if(o->manual&&o->count&&!visit(data,o->manual,o->count))return GX2D_OK;
    if(o->breaks&&o->count&&!visit(data,o->breaks,o->count))return GX2D_OK;
    if(o->members&&o->member_count&&!visit(data,o->members,o->member_count*sizeof(*o->members)))return GX2D_OK;
    if(o->part_states&&o->part_state_count&&!visit(data,o->part_states,o->part_state_count*sizeof(*o->part_states)))return GX2D_OK;
    if(o->style.layer){gx2d_status code=gx2d_get_layer(s,o->style.layer,&style);if(code!=GX2D_OK)return code;if(!visit(data,&style,sizeof style))return GX2D_OK;}
    if(o->sketch)presentation_definition_visit(o->sketch,visit,data);
    return GX2D_OK;
}
