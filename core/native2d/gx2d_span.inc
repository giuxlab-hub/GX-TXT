/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Exact extraction and Spline replacement plans. No display samples participate. */
gx2d_status gx2d_selection_definition_owned(const gx2d_scene *s,gx2d_id id,size_t index,gx2d_sketch_definition **out) {
    const object *root=cobj(s,id);object leaf;gx2d_sketch_definition d;gx2d_point p[4];gx2d_spline_tangent arms[2];
    if(!root||!root->sketch||!out)return GX2D_INVALID;
    int mapped=network_leaf(root,&index,&leaf,&d,NULL);if(mapped<0)return GX2D_INVALID;
    if(!mapped)d=*root->sketch;
    if(index==GX2D_OBJECT_INDEX){*out=sketch_clone(&d);return *out?GX2D_OK:GX2D_NOMEM;}
    if(index>=GX2D_CONTROL_INDEX&&index<GX2D_SEGMENT_INDEX){
        if(control_point(mapped?&leaf:root,index-GX2D_CONTROL_INDEX,p,NULL)!=GX2D_OK)return GX2D_INVALID;
        memset(&d,0,sizeof(d));d.family=GX2D_SKETCH_POINT;d.matrix[0]=d.matrix[3]=1;d.controls=p;d.control_count=1;
    }else if(index>=GX2D_SEGMENT_INDEX&&index<GX2D_OBJECT_INDEX){
        size_t k=index-GX2D_SEGMENT_INDEX;
        if(d.family==GX2D_SKETCH_SPLINE&&k+1<d.control_count){
            sketch_spline_controls(&d,k,p);
            arms[0]=(gx2d_spline_tangent){.flags=2,.outgoing={p[1].x-p[0].x,p[1].y-p[0].y}};
            arms[1]=(gx2d_spline_tangent){.flags=1,.incoming={p[2].x-p[3].x,p[2].y-p[3].y}};
            p[1]=p[3];d.controls=p;d.control_count=2;d.tangents=arms;d.tangent_count=2;
        }else if((d.family==GX2D_SKETCH_LINE||d.family==GX2D_SKETCH_POLYLINE||d.family==GX2D_SKETCH_PATH)&&k<d.control_count-1+(size_t)d.path_closed){
            p[0]=d.controls[k];p[1]=d.controls[(k+1)%d.control_count];d.family=GX2D_SKETCH_LINE;d.controls=p;d.control_count=2;d.path_closed=0;d.path_segments=NULL;d.path_segment_count=0;
        }else return GX2D_INVALID;
    }else return GX2D_INVALID;
    *out=sketch_clone(&d);return *out?GX2D_OK:GX2D_NOMEM;
}
/* controls maps each old defining-control ordinal to its new ordinal. segments
 * maps old constituent bases; the split constituent is addressed span by span. */
gx2d_status gx2d_spline_line_plan(const gx2d_scene *s,gx2d_id id,size_t index,gx2d_sketch_definition **out,size_t *controls,size_t cap,size_t *count,size_t *split_part,size_t *span_count) {
    const object *o=cobj(s,id);object leaf;gx2d_sketch_definition chosen;size_t part=0;
    if(!o||!o->sketch||!out||!count||!split_part||!span_count)return GX2D_INVALID;
    size_t nc=control_count(o);*count=nc;if(!controls||cap<nc)return GX2D_RANGE;
    int mapped=network_leaf(o,&index,&leaf,&chosen,&part);if(mapped<0)return GX2D_INVALID;if(!mapped)chosen=*o->sketch;
    if(chosen.family!=GX2D_SKETCH_SPLINE||index<GX2D_SEGMENT_INDEX||index>=GX2D_OBJECT_INDEX)return GX2D_INVALID;
    size_t span=index-GX2D_SEGMENT_INDEX,n=chosen.control_count-1,old_parts=mapped?o->sketch->part_count:1,total=old_parts+n-1;
    if(span>=n||total>256||nc+n-1>65536)return GX2D_RANGE;
    gx2d_sketch_definition parts[256],d={0};int reversed[256];gx2d_point xy[256][2];gx2d_spline_tangent arms[256][2];
    size_t origins[65536],nodes[65536],offset=0,old_offset=0,at=0;
    for(size_t k=0;k<old_parts;k++){
        gx2d_sketch_definition original=mapped?o->sketch->parts[k]:*o->sketch;object source={0};source.sketch=&original;size_t old_n=control_count(&source);
        int rev=mapped?o->sketch->part_reversed[k]:0;
        if(k!=part){parts[at]=original;reversed[at++]=rev;for(size_t j=0;j<old_n;j++){controls[old_offset+j]=offset;origins[offset++]=old_offset+j;}}
        else {
            /* Freeze the existing exact cubic arms before subdivision: a
             * neighbouring span must not change its automatic tangent. */
            for(size_t j=0;j<n;j++){
                size_t q=rev?n-1-j:j;gx2d_point b[4];sketch_spline_controls(&original,q,b);
                xy[at][0]=b[0];xy[at][1]=b[3];parts[at]=original;parts[at].controls=xy[at];parts[at].control_count=2;
                parts[at].tangent_count=0;parts[at].tangents=NULL;
                if(q==span)parts[at].family=GX2D_SKETCH_LINE;
                else {arms[at][0]=(gx2d_spline_tangent){.flags=2,.outgoing={b[1].x-b[0].x,b[1].y-b[0].y}};arms[at][1]=(gx2d_spline_tangent){.flags=1,.incoming={b[2].x-b[3].x,b[2].y-b[3].y}};parts[at].tangents=arms[at];parts[at].tangent_count=2;}
                reversed[at++]=rev;
                controls[old_offset+q]=offset;origins[offset++]=old_offset+q;
                controls[old_offset+q+1]=offset;origins[offset++]=old_offset+q+1;
            }
        }
        old_offset+=old_n;
    }
    if(offset>65536)return GX2D_RANGE;
    d.family=GX2D_SKETCH_COMPOSITE_PATH;d.matrix[0]=d.matrix[3]=1;
    if(mapped){memcpy(d.matrix,o->sketch->matrix,sizeof(d.matrix));d.path_closed=o->sketch->path_closed;d.join_tolerance=o->sketch->join_tolerance;}
    d.parts=parts;d.part_reversed=reversed;d.part_count=total;
    /* Preserve canonical shared node identities; added duplicate endpoints
     * inherit the original knot, never a proximity-based weld. */
    if(!mapped||o->sketch->node_count){
        /* Canonical node ordinals are bounded by the original control count.
         * Direct indexing preserves first-occurrence identity in linear time. */
        size_t *first=malloc(nc*sizeof(*first));
        if(!first)return GX2D_NOMEM;
        for(size_t i=0;i<nc;i++)first[i]=SIZE_MAX;
        for(size_t i=0;i<offset;i++){
            size_t original=mapped?o->sketch->nodes[origins[i]]:origins[i];
            if(original>=nc){free(first);return GX2D_INVALID;}
            if(first[original]==SIZE_MAX)first[original]=i;
            nodes[i]=first[original];
        }
        free(first);
        d.nodes=nodes;d.node_count=offset;
    }
    gx2d_status code=gx2d_sketch_validate(&d);if(code!=GX2D_OK)return code;
    *out=sketch_clone(&d);*split_part=part;*span_count=n;return *out?GX2D_OK:GX2D_NOMEM;
}
static int span_remap_index(size_t *index,const size_t *map,size_t nc,size_t part,size_t spans,int composite,int reverse) {
    if(*index==GX2D_OBJECT_INDEX)return 1;
    if(*index>=GX2D_CONTROL_INDEX&&*index<GX2D_SEGMENT_INDEX){size_t k=*index-GX2D_CONTROL_INDEX;if(k>=nc)return 0;*index=GX2D_CONTROL_INDEX+map[k];return 1;}
    if(*index<GX2D_SEGMENT_INDEX||*index>=GX2D_OBJECT_INDEX)return 0;
    size_t k=composite?(*index-GX2D_SEGMENT_INDEX)/NETWORK_STRIDE:0,q=composite?(*index-GX2D_SEGMENT_INDEX)%NETWORK_STRIDE:*index-GX2D_SEGMENT_INDEX;
    if(k==part){if(q==NETWORK_STRIDE-1){if(spans!=1)return 0;q=0;}if(q>=spans)return 0;k+=reverse?spans-1-q:q;q=0;}
    else if(k>part)k+=spans-1;
    *index=GX2D_SEGMENT_INDEX+k*NETWORK_STRIDE+q;return 1;
}
gx2d_status gx2d_spline_span_to_line(gx2d_scene *s,gx2d_id id,size_t index) {
    object *o=obj(s,id);if(!o||!o->sketch)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;if(!can_move(s,o))return GX2D_LOCKED;
    size_t map[65536],nc,part,spans;gx2d_sketch_definition *d=NULL;
    gx2d_status code=gx2d_spline_line_plan(s,id,index,&d,map,65536,&nc,&part,&spans);if(code!=GX2D_OK)return code;
    int composite=o->sketch->family==GX2D_SKETCH_COMPOSITE_PATH,reverse=composite?o->sketch->part_reversed[part]:0;
    rule *rules=malloc((s->rule_count?s->rule_count:1)*sizeof(rule));if(!rules){sketch_free(d);return GX2D_NOMEM;}memcpy(rules,s->rules,s->rule_count*sizeof(rule));
    for(size_t i=0;i<s->rule_count;i++){
        rule *r=&rules[i];
        if((r->spec.a==id&&!span_remap_index(&r->spec.a_index,map,nc,part,spans,composite,reverse))||
           (r->spec.b==id&&!span_remap_index(&r->spec.b_index,map,nc,part,spans,composite,reverse))||
           (r->axis==id&&!span_remap_index(&r->axis_index,map,nc,part,spans,composite,reverse))){free(rules);sketch_free(d);return GX2D_CONSTRAINT;}
    }
    gx2d_id temporary;code=gx2d_sketch_create(s,d,257,&temporary);sketch_free(d);if(code!=GX2D_OK){free(rules);return code;}
    o=obj(s,id);object *candidate=obj(s,temporary),before=*o;rule *old_rules=s->rules;
    o->sketch=candidate->sketch;o->points=candidate->points;o->breaks=candidate->breaks;o->manual=candidate->manual;o->count=candidate->count;o->capacity=candidate->capacity;
    candidate->sketch=before.sketch;candidate->points=before.points;candidate->breaks=before.breaks;candidate->manual=before.manual;candidate->count=before.count;candidate->capacity=before.capacity;
    s->rules=rules;code=gx2d_check_constraints(s);s->rules=old_rules;
    if(code==GX2D_OK){memcpy(s->rules,rules,s->rule_count*sizeof(rule));o->parameter_epoch++;o->topology_epoch++;}
    else {object failed=*o;*o=before;candidate->sketch=failed.sketch;candidate->points=failed.points;candidate->breaks=failed.breaks;candidate->manual=failed.manual;candidate->count=failed.count;candidate->capacity=failed.capacity;}
    free(rules);gx2d_delete_object(s,temporary);return code;
}
/* Source topological control identities for an exact extracted definition. */
gx2d_status gx2d_selection_control_sources(const gx2d_scene *s,gx2d_id id,size_t index,size_t *out,size_t cap,size_t *count) {
    const object *root=cobj(s,id);object leaf;gx2d_sketch_definition d;size_t part=0,offset=0,n=0,first=0;
    if(!root||!root->sketch||!count)return GX2D_INVALID;
    int mapped=network_leaf(root,&index,&leaf,&d,&part);if(mapped<0)return GX2D_INVALID;if(!mapped)d=*root->sketch;
    if(mapped){size_t ix=network_index(root,part,GX2D_CONTROL_INDEX);offset=ix-GX2D_CONTROL_INDEX;}
    if(index==GX2D_OBJECT_INDEX)n=control_count(mapped?&leaf:root);
    else if(index>=GX2D_CONTROL_INDEX&&index<GX2D_SEGMENT_INDEX){first=index-GX2D_CONTROL_INDEX;n=1;}
    else if(index>=GX2D_SEGMENT_INDEX&&index<GX2D_OBJECT_INDEX){first=index-GX2D_SEGMENT_INDEX;n=2;
        if(d.family!=GX2D_SKETCH_SPLINE&&d.family!=GX2D_SKETCH_LINE&&d.family!=GX2D_SKETCH_POLYLINE&&d.family!=GX2D_SKETCH_PATH)return GX2D_INVALID;
    }else return GX2D_INVALID;
    if(out&&cap<n)return GX2D_RANGE;
    for(size_t i=0;out&&i<n;i++){
        size_t q=offset+((index>=GX2D_SEGMENT_INDEX&&index<GX2D_OBJECT_INDEX)?(first+i)%d.control_count:first+i);
        if(q>=control_count(root))return GX2D_INVALID;
        if(root->sketch->node_count)q=root->sketch->nodes[q];out[i]=GX2D_CONTROL_INDEX+q;
    }
    *count=n;return GX2D_OK;
}
