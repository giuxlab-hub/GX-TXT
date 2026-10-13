/* SPDX-License-Identifier: GPL-3.0-or-later */
/* A referenced edge keeps its Native identity and uses the existing finite
 * projection and point-on-line equation. No unrecorded visual-only junction. */
static gx2d_status construction_reference_point(const gx2d_scene *s,const gx2d_construction_placement *place,gx2d_point *out) {
    gx2d_point checked,a,b,dir;gx2d_status code=gx2d_reference_resolve(s,&place->reference,&checked);
    if(code!=GX2D_OK)return code;
    if(place->reference.entity==GX2D_ENTITY_CONTROL){*out=checked;return GX2D_OK;}
    if(!finite2(place->point))return GX2D_INVALID;
    const object *root=cobj(s,place->reference.object);object leaf;gx2d_sketch_definition definition;size_t index=place->reference.index;
    int mapped=network_leaf(root,&index,&leaf,&definition,NULL);if(mapped<0)return GX2D_INVALID;
    const object *shape=mapped?&leaf:root;
    if(place->reference.entity==GX2D_ENTITY_SEGMENT&&index!=GX2D_OBJECT_INDEX){
        code=constraint_segment(root,place->reference.index,&a,&b,&dir);
        if(code==GX2D_OK)*out=nearest_segment(place->point,a,b);return code;
    }
    /* Curved constituents already have exact evaluation/closest-point and
     * point-on-curve equations in the solver. Reuse that same authority for
     * placement, so a valid curved branch is not treated as an empty click. */
    if((place->reference.entity!=GX2D_ENTITY_OBJECT&&place->reference.entity!=GX2D_ENTITY_SEGMENT)||!shape||!shape->sketch)return GX2D_INVALID;
    return sk_nearest(shape,place->point,out)?GX2D_OK:GX2D_INVALID;
}
/* Additive construction transactions over retained definitions and existing
 * scene/rule/reference authorities. No separate chain or topology store. */
gx2d_status gx2d_construction_resolve(const gx2d_scene *s,const gx2d_construction_placement *places,size_t n,gx2d_point *out,size_t cap){
    if(!s||!places||!out||!n||n>65536)return GX2D_INVALID;if(cap<n)return GX2D_RANGE;
    gx2d_point *points=malloc(n*sizeof(*points));if(!points)return GX2D_NOMEM;gx2d_status code=GX2D_OK;
    for(size_t i=0;i<n;i++){
        if(places[i].mode==GX2D_PLACEMENT_FREE){points[i]=places[i].point;if(!finite2(points[i])){code=GX2D_INVALID;break;}}
        else if(places[i].mode==GX2D_PLACEMENT_REFERENCE){code=construction_reference_point(s,&places[i],&points[i]);if(code!=GX2D_OK)break;}
        else if(places[i].mode==GX2D_PLACEMENT_EARLIER){if(places[i].earlier>=i){code=GX2D_INVALID;break;}points[i]=points[places[i].earlier];}
        else {code=GX2D_INVALID;break;}
    }
    if(code==GX2D_OK)memcpy(out,points,n*sizeof(*out));free(points);return code;
}
/* A circle's existing affine parameter chart can orient the radius handle at
 * its placed defining point without changing its exact circular shape. */
static void construction_chart(gx2d_sketch_definition *d,const gx2d_point *points,size_t n){
    if(d->family==GX2D_SKETCH_CIRCLE&&n>=2){double angle=atan2(points[1].y-points[0].y,points[1].x-points[0].x),c=cos(angle),v=sin(angle);
        d->matrix[0]=c;d->matrix[1]=-v;d->matrix[2]=v;d->matrix[3]=c;
        d->matrix[4]=points[0].x-c*points[0].x+v*points[0].y;d->matrix[5]=points[0].y-v*points[0].x-c*points[0].y;}
}
gx2d_status gx2d_construction_preview(const gx2d_scene *s,gx2d_sketch_family family,const gx2d_construction_placement *places,size_t n,gx2d_sketch_definition *out,gx2d_point *controls,size_t cap){
    if(!out||!controls||!n||n>65536)return GX2D_INVALID;gx2d_point *points=malloc(n*sizeof(*points)),*buffer=malloc(n*sizeof(*buffer));if(!points||!buffer){free(points);free(buffer);return GX2D_NOMEM;}
    gx2d_sketch_definition d;gx2d_status code=gx2d_construction_resolve(s,places,n,points,n);
    if(code==GX2D_OK)code=gx2d_sketch_preview_definition(family,points,n,&d,buffer,n);
    if(code==GX2D_OK){construction_chart(&d,points,n);if(cap<d.control_count)code=GX2D_RANGE;else {memcpy(controls,d.controls,d.control_count*sizeof(*controls));*out=d;out->controls=controls;}}
    free(points);free(buffer);return code;
}
static int construction_ref_equal(gx2d_reference a,gx2d_reference b){return a.object==b.object&&a.entity==b.entity&&a.index==b.index&&a.epoch==b.epoch;}
gx2d_status gx2d_references_connected(const gx2d_scene *s,const gx2d_reference *a,const gx2d_reference *b,int *out){
    if(!s||!a||!b||!out||a->entity!=GX2D_ENTITY_CONTROL||b->entity!=GX2D_ENTITY_CONTROL)return GX2D_INVALID;gx2d_point p;gx2d_status code=gx2d_reference_resolve(s,a,&p);if(code!=GX2D_OK)return code;code=gx2d_reference_resolve(s,b,&p);if(code!=GX2D_OK)return code;
    if(a->object==b->object){const object *o=cobj(s,a->object);if(o->sketch&&o->sketch->node_count){*out=o->sketch->nodes[a->index-GX2D_CONTROL_INDEX]==o->sketch->nodes[b->index-GX2D_CONTROL_INDEX];if(*out)return GX2D_OK;}}
    if(s->rule_count>(SIZE_MAX/sizeof(gx2d_reference)-1)/2)return GX2D_RANGE;size_t cap=2*s->rule_count+1,n=1;gx2d_reference *queue=malloc(cap*sizeof(*queue));if(!queue)return GX2D_NOMEM;queue[0]=*a;int found=0;
    for(size_t i=0;i<n&&!found;i++){
        if(construction_ref_equal(queue[i],*b)){found=1;break;}
        for(size_t j=0;j<s->rule_count;j++){const rule *r=&s->rules[j];if(r->disabled||r->spec.kind!=GX2D_COINCIDENT)continue;gx2d_reference x,y;
            if(gx2d_reference_from_index(s,r->spec.a,r->spec.a_index,&x)!=GX2D_OK||gx2d_reference_from_index(s,r->spec.b,r->spec.b_index,&y)!=GX2D_OK||x.entity!=GX2D_ENTITY_CONTROL||y.entity!=GX2D_ENTITY_CONTROL)continue;
            gx2d_reference next;if(construction_ref_equal(queue[i],x))next=y;else if(construction_ref_equal(queue[i],y))next=x;else continue;
            int seen=0;for(size_t z=0;z<n;z++)if(construction_ref_equal(queue[z],next)){seen=1;break;}if(!seen)queue[n++]=next;
        }
    }
    free(queue);*out=found;return GX2D_OK;
}
gx2d_status gx2d_construction_pick(const gx2d_scene *s,gx2d_point device,double tolerance,const gx2d_construction_placement *places,size_t n,const gx2d_id *excluded,size_t ne,int grid,gx2d_construction_placement *out){
    if(!s||!out||!finite2(device)||!isfinite(tolerance)||tolerance<0||(n&&!places)||n>65536)return GX2D_INVALID;gx2d_construction_placement result={0};int kind;gx2d_status code=gx2d_placement_snap(s,device,tolerance,excluded,ne,0,grid,&result.point,&kind,&result.reference);if(code!=GX2D_OK)return code;
    double best=tolerance;int priority=0;gx2d_point projected;
    gx2d_id *expanded=NULL;size_t nexpanded=0;if(ne){code=cad_expand(s,excluded,ne,&expanded,&nexpanded);if(code!=GX2D_OK)return code;}
    for(size_t i=0;i<s->object_count;i++){const object *o=&s->objects[i];if(o->kind==GX2D_GROUP||!can_select(s,o)||!o->style.selectable)continue;int skip=0;for(size_t j=0;j<nexpanded;j++)if(expanded[j]==o->id)skip=1;if(skip)continue;
        gx2d_reference reference;if(gx2d_interaction_pick(s,o->id,device,tolerance,&reference)!=GX2D_OK||(reference.entity!=GX2D_ENTITY_CONTROL&&reference.entity!=GX2D_ENTITY_SEGMENT&&reference.entity!=GX2D_ENTITY_OBJECT))continue;
        gx2d_point point;gx2d_construction_placement candidate={0};candidate.reference=reference;gx2d_device_to_world(s,device,&candidate.point);
        code=construction_reference_point(s,&candidate,&point);if(code==GX2D_INVALID)continue;if(code!=GX2D_OK){free(expanded);return code;}gx2d_world_to_device(s,point,&projected);double distance=dist(device,projected);
        int rank=reference.entity==GX2D_ENTITY_CONTROL?2:1;
        /* A defining point wins over a nearby/crossing edge across the entire
         * scene, exactly as semantic selection does. Pixel rounding must not
         * turn a shared endpoint into an incidental segment attachment. */
        if(distance<=tolerance&&(rank>priority||(rank==priority&&distance<=best))){priority=rank;best=distance;result.point=point;result.reference=reference;result.mode=GX2D_PLACEMENT_REFERENCE;}
    }
    free(expanded);
    /* Current placements have semantic identity within this transaction.
     * They are separate from transient render-preview objects. */
    if(n){gx2d_point *points=malloc(n*sizeof(*points));if(!points)return GX2D_NOMEM;code=gx2d_construction_resolve(s,places,n,points,n);if(code!=GX2D_OK){free(points);return code;}
        for(size_t i=0;i<n;i++){gx2d_world_to_device(s,points[i],&projected);double distance=dist(device,projected);if(distance<=tolerance&&(priority<2||distance<=best)){priority=2;best=distance;result.point=points[i];result.mode=GX2D_PLACEMENT_EARLIER;result.earlier=i;}}
        free(points);
    }
    *out=result;return GX2D_OK;
}
gx2d_status gx2d_sketch_create_attached(gx2d_scene *s,gx2d_sketch_family family,const gx2d_construction_placement *places,size_t n,size_t samples,const gx2d_reference *closure,size_t nc,gx2d_id *out,gx2d_id *relationships,size_t cap,size_t *count,gx2d_reference *tail,int *closed){
    if(!s||!places||!n||n>65536||!out||!count||!tail||!closed||(nc&&!closure)||nc>65536)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    size_t needed=0;for(size_t i=0;i<n;i++)if(places[i].mode!=GX2D_PLACEMENT_FREE)needed++;
    if(needed>cap||(needed&&!relationships))return GX2D_RANGE;
    gx2d_point *points=malloc(n*sizeof(*points)),*controls=malloc(n*sizeof(*controls));gx2d_id *rules=needed?malloc(needed*sizeof(*rules)):NULL;
    if(!points||!controls||(needed&&!rules)){free(points);free(controls);free(rules);return GX2D_NOMEM;}
    gx2d_status code=gx2d_construction_resolve(s,places,n,points,n);gx2d_sketch_definition d;gx2d_id id=0;size_t made=0;gx2d_reference endpoint;int closure_found=0;
    for(size_t i=0;code==GX2D_OK&&i<nc;i++){gx2d_point p;if(closure[i].entity!=GX2D_ENTITY_CONTROL)code=GX2D_INVALID;else code=gx2d_reference_resolve(s,&closure[i],&p);}
    if(code==GX2D_OK)code=gx2d_sketch_construct(family,points,n,&d,controls,n);
    if(code==GX2D_OK&&(family==GX2D_SKETCH_LINE||family==GX2D_SKETCH_CONSTRUCTION_LINE)&&dist(points[0],points[1])<=1e-14)code=GX2D_INVALID;
    if(code==GX2D_OK){construction_chart(&d,points,n);code=gx2d_sketch_create(s,&d,samples,&id);}
    for(size_t i=0;code==GX2D_OK&&i<(family==GX2D_SKETCH_PATH?d.control_count:n);i++)if(places[i].mode!=GX2D_PLACEMENT_FREE){
        gx2d_reference refs[2];gx2d_point actual,target;code=gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,i,&refs[0]);if(code!=GX2D_OK)break;
        code=gx2d_reference_resolve(s,&refs[0],&actual);if(code!=GX2D_OK)break;
        if(places[i].mode==GX2D_PLACEMENT_REFERENCE)refs[1]=places[i].reference;
        else {code=gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,places[i].earlier,&refs[1]);if(code!=GX2D_OK)break;}
        if(places[i].mode==GX2D_PLACEMENT_REFERENCE)code=construction_reference_point(s,&places[i],&target);
        else code=gx2d_reference_resolve(s,&refs[1],&target);if(code!=GX2D_OK)break;
        /* Arc angular placement and ellipse minor-radius projection must not
         * silently turn an incompatible click into a fake shared control. */
        double tolerance=1e-8;if(dist(actual,target)>tolerance){code=GX2D_INVALID;break;}
        gx2d_constraint_kind kind=GX2D_COINCIDENT;
        if(refs[1].entity!=GX2D_ENTITY_CONTROL){
            gx2d_point a,b,dir;
            kind=constraint_segment(cobj(s,refs[1].object),refs[1].index,&a,&b,&dir)==GX2D_OK?GX2D_POINT_ON_LINE:GX2D_POINT_ON_CURVE;
        }
        gx2d_constraint_v2 specification;code=gx2d_constraint_from_selection(s,kind,refs,2,&specification);if(code!=GX2D_OK)break;
        gx2d_relationship_state state={0};state.solved=1;state.branch=-1;state.curvature_tolerance=1e-8;
        code=gx2d_constraint_create_state(s,&specification,&state,&rules[made]);if(code==GX2D_OK)made++;
    }
    if(code==GX2D_OK)code=gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,family==GX2D_SKETCH_PATH?(d.path_closed?0:d.control_count-1):n-1,&endpoint);
    if(code==GX2D_OK&&made){gx2d_sketch_status status;code=gx2d_sketch_status_get(s,id,&status);}
    if(code==GX2D_OK&&places[n-1].mode==GX2D_PLACEMENT_EARLIER)closure_found=1;
    for(size_t i=0;code==GX2D_OK&&!closure_found&&i<nc;i++)if(places[n-1].mode==GX2D_PLACEMENT_REFERENCE&&places[n-1].reference.entity==GX2D_ENTITY_CONTROL){code=gx2d_references_connected(s,&places[n-1].reference,&closure[i],&closure_found);}
    if(code==GX2D_OK){*out=id;*count=made;*tail=endpoint;*closed=closure_found;if(made)memcpy(relationships,rules,made*sizeof(*rules));}
    else if(id){for(size_t i=0;i<made;i++)gx2d_remove_constraint(s,rules[i]);gx2d_delete_object(s,id);}
    free(points);free(controls);free(rules);return code;
}

/* Retarget relations before a host consumes source rows. No geometry or rule
 * identity changes until every mapped relationship has passed validation. */
gx2d_status gx2d_composition_retarget(gx2d_scene *s,gx2d_id target,const gx2d_id *sources,size_t count){
    object *result=obj(s,target);if(!result||!result->sketch||!result->sketch->node_count||!sources||!count)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    rule *before=malloc((s->rule_count?s->rule_count:1)*sizeof(rule));if(!before)return GX2D_NOMEM;memcpy(before,s->rules,s->rule_count*sizeof(rule));
    gx2d_status code=GX2D_OK;size_t part_offset=0,control_offset=0;
    for(size_t i=0;i<count&&code==GX2D_OK;i++){
        object *source=obj(s,sources[i]);if(!source||!source->sketch){code=GX2D_INVALID;break;}
        for(size_t j=0;j<s->rule_count&&code==GX2D_OK;j++){
            rule *r=&s->rules[j];gx2d_id *ids[3]={&r->spec.a,&r->spec.b,&r->axis};size_t *ix[3]={&r->spec.a_index,&r->spec.b_index,&r->axis_index};
            for(int k=0;k<3;k++)if(*ids[k]==sources[i]){
                if(*ix[k]>=GX2D_CONTROL_INDEX&&*ix[k]<GX2D_SEGMENT_INDEX)*ix[k]+=control_offset;
                else if(*ix[k]==GX2D_OBJECT_INDEX)*ix[k]=GX2D_SEGMENT_INDEX+part_offset*NETWORK_STRIDE+NETWORK_STRIDE-1;
                else if(*ix[k]>=GX2D_SEGMENT_INDEX)*ix[k]+=part_offset*NETWORK_STRIDE;
                else {code=GX2D_INVALID;break;}*ids[k]=target;
            }
        }
        control_offset+=control_count(source);part_offset+=sketch_is_composition(source->sketch)?source->sketch->part_count:1;
    }
    if(code==GX2D_OK)code=gx2d_check_constraints(s);
    if(code!=GX2D_OK)memcpy(s->rules,before,s->rule_count*sizeof(rule));free(before);return code;
}
