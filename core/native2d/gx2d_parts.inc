/* Native ownership of leaf presentation; no public definition POD size change. */
static gx2d_status part_states_init(object *o) {
    size_t count=sketch_is_composition(o->sketch)?o->sketch->part_count:0;
    if(count==o->part_state_count)return GX2D_OK;
    if(count>=(uint64_t)INT64_MAX-o->next_part_id)return GX2D_RANGE;
    gx2d_part_state *states=count?calloc(count,sizeof(*states)):NULL;
    if(count&&!states)return GX2D_NOMEM;
    for(size_t i=0;i<count;i++) {
        states[i].part_id=++o->next_part_id;
        states[i].direction=default_direction_marker();states[i].direction.present=0;
        states[i].direction.forward=!o->sketch->part_reversed[i];
    }
    free(o->part_states);o->part_states=states;o->part_state_count=count;return GX2D_OK;
}
gx2d_status gx2d_composition_states(const gx2d_scene *s,gx2d_id id,gx2d_part_state *out,size_t capacity,size_t *count) {
    const object *o=cobj(s,id);if(!o)return GX2D_NOT_FOUND;if(!count||!sketch_is_composition(o->sketch))return GX2D_INVALID;
    *count=o->part_state_count;if(out&&capacity<*count)return GX2D_RANGE;
    if(out)memcpy(out,o->part_states,*count*sizeof(*out));return GX2D_OK;
}
gx2d_status gx2d_composition_states_restore(gx2d_scene *s,gx2d_id id,const gx2d_part_state *states,size_t count) {
    object *o=obj(s,id);if(!o)return GX2D_NOT_FOUND;if(s->dragging)return GX2D_BUSY;
    if(!states||!sketch_is_composition(o->sketch)||count!=o->sketch->part_count)return GX2D_INVALID;
    uint64_t next=o->next_part_id;
    for(size_t i=0;i<count;i++) {
        if(!states[i].part_id||states[i].part_id>=INT64_MAX||!valid_direction_marker(&states[i].direction))return GX2D_INVALID;
        for(size_t j=0;j<i;j++)if(states[j].part_id==states[i].part_id)return GX2D_INVALID;
        if(states[i].part_id>next)next=states[i].part_id;
    }
    gx2d_part_state *copy=malloc(count*sizeof(*copy));if(!copy)return GX2D_NOMEM;
    memcpy(copy,states,count*sizeof(*copy));free(o->part_states);o->part_states=copy;o->part_state_count=count;o->next_part_id=next;return GX2D_OK;
}
gx2d_status gx2d_part_ordinal(const gx2d_scene *s,gx2d_id id,uint64_t part,size_t *ordinal) {
    const object *o=cobj(s,id);if(!o)return GX2D_NOT_FOUND;if(!ordinal||!sketch_is_composition(o->sketch))return GX2D_INVALID;
    for(size_t i=0;i<o->part_state_count;i++)if(o->part_states[i].part_id==part){*ordinal=i;return GX2D_OK;}return GX2D_NOT_FOUND;
}
gx2d_status gx2d_part_direction_get(const gx2d_scene *s,gx2d_id id,uint64_t part,gx2d_direction_marker *out) {
    size_t i;gx2d_status code=gx2d_part_ordinal(s,id,part,&i);if(code!=GX2D_OK)return code;if(!out)return GX2D_INVALID;*out=cobj(s,id)->part_states[i].direction;return GX2D_OK;
}
gx2d_status gx2d_part_direction_set(gx2d_scene *s,gx2d_id id,uint64_t part,const gx2d_direction_marker *state) {
    size_t i;gx2d_status code=gx2d_part_ordinal(s,id,part,&i);if(code!=GX2D_OK)return code;
    if(s->dragging)return GX2D_BUSY;if(!valid_direction_marker(state))return GX2D_INVALID;obj(s,id)->part_states[i].direction=*state;return GX2D_OK;
}
/* Borrow the exact transformed leaf in a disposable native scene. This reuses
 * the retained renderer, marker metric and device projection, including curves
 * inside unordered compounds, without mutating the source or its topology. */
static gx2d_status part_scene(const gx2d_scene *s,gx2d_id id,uint64_t part,gx2d_scene **temporary,gx2d_id *leaf) {
    size_t i;gx2d_status code=gx2d_part_ordinal(s,id,part,&i);if(code!=GX2D_OK)return code;
    gx2d_sketch_definition d;int reversed;code=gx2d_composition_part(s,id,i,&d,&reversed);if(code!=GX2D_OK)return code;
    gx2d_scene *t=gx2d_create();if(!t)return GX2D_NOMEM;t->view=s->view;t->requested_view=s->requested_view;t->aspect_mode=s->aspect_mode;
    code=gx2d_sketch_create(t,&d,d.control_count>4097?d.control_count:4097,leaf);
    if(code!=GX2D_OK){gx2d_destroy(t);return code;}
    const object *root=cobj(s,id);object *o=obj(t,*leaf);o->style=root->style;o->style.layer=0;
    o->direction_marker=root->part_states[i].direction;o->direction_marker.interpolation=0;
    if(!root->direction_marker.forward)o->direction_marker.forward=!o->direction_marker.forward;
    *temporary=t;return GX2D_OK;
}
gx2d_status gx2d_part_direction_render(const gx2d_scene *s,gx2d_id id,uint64_t part,gx2d_direction_primitives *out) {
    gx2d_scene *t;gx2d_id leaf;gx2d_status code=part_scene(s,id,part,&t,&leaf);if(code!=GX2D_OK)return code;
    code=gx2d_direction_marker_render(t,leaf,out);gx2d_destroy(t);return code;
}
gx2d_status gx2d_part_direction_hit(const gx2d_scene *s,gx2d_id id,uint64_t part,gx2d_point device,double tolerance,int *hit) {
    gx2d_scene *t;gx2d_id leaf;gx2d_status code=part_scene(s,id,part,&t,&leaf);if(code!=GX2D_OK)return code;
    code=gx2d_direction_marker_hit(t,leaf,device,tolerance,hit);gx2d_destroy(t);return code;
}
gx2d_status gx2d_part_direction_place(gx2d_scene *s,gx2d_id id,uint64_t part,gx2d_point device,double *fraction) {
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;gx2d_scene *t;gx2d_id leaf;gx2d_status code=part_scene(s,id,part,&t,&leaf);if(code!=GX2D_OK)return code;
    code=gx2d_direction_marker_place(t,leaf,device,fraction);gx2d_destroy(t);
    if(code==GX2D_OK){size_t i;gx2d_part_ordinal(s,id,part,&i);obj(s,id)->part_states[i].direction.fraction=*fraction;}return code;
}
gx2d_status gx2d_composition_traversal(const gx2d_scene *s,gx2d_id id,int *kind) {
    const object *o=cobj(s,id);if(!o)return GX2D_NOT_FOUND;if(!kind||!sketch_is_composition(o->sketch))return GX2D_INVALID;
    *kind=0;if(o->sketch->family==GX2D_SKETCH_COMPOUND)return GX2D_OK;
    *kind=1;gx2d_point previous={0,0},first={0,0};
    /* Connectivity is tested in the defining frame so affine/units preserve
     * the reviewed tolerance. No storage-order walk is invented for a branch. */
    for(size_t k=0;k<o->sketch->part_count;k++) {
        size_t i=o->direction_marker.forward?k:o->sketch->part_count-1-k;
        int forward=o->part_states[i].direction.forward==o->direction_marker.forward;
        gx2d_point a,b;gx2d_status code=gx2d_sketch_evaluate(&o->sketch->parts[i],forward?0:1,&a,NULL);
        if(code==GX2D_OK)code=gx2d_sketch_evaluate(&o->sketch->parts[i],forward?1:0,&b,NULL);if(code!=GX2D_OK)return code;
        if(k&&dist(previous,a)>o->sketch->join_tolerance)*kind=2;if(!k)first=a;previous=b;
    }
    if(o->sketch->path_closed&&dist(first,previous)>o->sketch->join_tolerance)*kind=2;
    if(o->sketch->node_count){
        /* Branches attached to interior controls cannot be represented by the
         * old endpoint chain even if particular endpoint coordinates coincide. */
        for(size_t i=0;i<o->sketch->node_count;i++)if(o->sketch->nodes[i]==i){size_t incidence=0;for(size_t j=0;j<o->sketch->node_count;j++)incidence+=o->sketch->nodes[j]==i;if(incidence>2)*kind=2;}
    }
    return GX2D_OK;
}
gx2d_status gx2d_part_render(const gx2d_scene *s,gx2d_id id,uint64_t part,gx2d_point *out,size_t capacity,size_t *count) {
    gx2d_scene *t;gx2d_id leaf;gx2d_status code=part_scene(s,id,part,&t,&leaf);if(code!=GX2D_OK)return code;size_t cuts=0;
    code=gx2d_object_display(t,leaf,4096,out,NULL,capacity,count,NULL,0,&cuts);gx2d_destroy(t);return code;
}
gx2d_status gx2d_part_pick(const gx2d_scene *s,gx2d_id id,gx2d_point device,double tolerance,uint64_t *part) {
    if(!part)return GX2D_INVALID;gx2d_reference ref;gx2d_status code=gx2d_interaction_pick(s,id,device,tolerance,&ref);if(code!=GX2D_OK)return code;
    const object *root=cobj(s,id);object leaf;gx2d_sketch_definition d;size_t ordinal,index=ref.index;
    if(network_leaf(root,&index,&leaf,&d,&ordinal)!=1)return GX2D_NOT_FOUND;*part=root->part_states[ordinal].part_id;return GX2D_OK;
}

/* Preallocate and validate the presentation snapshot before committing geometry.
 * This is the atomic import/edit contract used by persistence and Tcl. */
gx2d_status gx2d_composition_identity_counter(const gx2d_scene *s,gx2d_id id,uint64_t *counter) {
    const object *o=cobj(s,id);if(!o)return GX2D_NOT_FOUND;if(!counter||!sketch_is_composition(o->sketch))return GX2D_INVALID;*counter=o->next_part_id;return GX2D_OK;
}
gx2d_status gx2d_sketch_update_parts(gx2d_scene *s,gx2d_id id,const gx2d_sketch_definition *d,size_t samples,const gx2d_part_state *states,size_t count,uint64_t counter) {
    if(!s||!d||!states||!sketch_is_composition(d)||count!=d->part_count||counter>=INT64_MAX)return GX2D_INVALID;
    for(size_t i=0;i<count;i++) {
        if(!states[i].part_id||states[i].part_id>=INT64_MAX||!valid_direction_marker(&states[i].direction))return GX2D_INVALID;
        if(states[i].part_id>counter)counter=states[i].part_id;
        for(size_t j=0;j<i;j++)if(states[j].part_id==states[i].part_id)return GX2D_INVALID;
    }
    gx2d_part_state *copy=malloc(count*sizeof(*copy));if(!copy)return GX2D_NOMEM;memcpy(copy,states,count*sizeof(*copy));
    gx2d_status code=gx2d_sketch_update(s,id,d,samples);
    if(code!=GX2D_OK){free(copy);return code;}
    object *o=obj(s,id);free(o->part_states);o->part_states=copy;o->part_state_count=count;
    if(counter>o->next_part_id)o->next_part_id=counter;return GX2D_OK;
}
