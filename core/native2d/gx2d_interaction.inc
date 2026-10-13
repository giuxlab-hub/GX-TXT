/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Renderer-neutral retained sketch interaction. All results are candidates
 * until adoption through the existing scene/constraint authority. */
static size_t control_count(const object *o) {
    if(!o||!o->sketch)return 0;
    if(sketch_is_composition(o->sketch)){
        size_t n=0;for(size_t i=0;i<o->sketch->part_count;i++){
            object part={0};part.sketch=(gx2d_sketch_definition *)&o->sketch->parts[i];n+=control_count(&part);
        }return n;
    }
    
    if(o->reference_image&&o->image.calibrated)return 4;
    switch(o->sketch->family){case GX2D_SKETCH_CIRCLE:return 2;
        case GX2D_SKETCH_ARC:case GX2D_SKETCH_ELLIPSE:return 3;
        default:return o->sketch->control_count;}
}
static gx2d_status control_point(const object *o,size_t i,gx2d_point *p,gx2d_control_role *role) {
    const gx2d_sketch_definition *d;gx2d_point local;double angle;gx2d_control_role r=GX2D_CONTROL_POSITION;
    if(!o||!(d=o->sketch)||i>=control_count(o))return GX2D_INVALID;
    if(sketch_is_composition(d)){
        for(size_t k=0;k<d->part_count;k++){
            object part={0};part.sketch=(gx2d_sketch_definition *)&d->parts[k];size_t n=control_count(&part);
            if(i<n){gx2d_status code=control_point(&part,i,p,role);if(code==GX2D_OK)*p=sketch_world(d,*p,0);return code;}i-=n;
        }return GX2D_RANGE;
    }
    if(o->reference_image&&i>=2){*p=sketch_world(d,o->image.calibration[i-2],0);if(role)*role=GX2D_CONTROL_POSITION;return finite2(*p)?GX2D_OK:GX2D_RANGE;}
    local=d->controls[i<d->control_count?i:0];
    switch(d->family){
    case GX2D_SKETCH_LINE:case GX2D_SKETCH_CONSTRUCTION_LINE:r=GX2D_CONTROL_ENDPOINT;break;
    case GX2D_SKETCH_RECTANGLE:r=GX2D_CONTROL_CORNER;break;
    case GX2D_SKETCH_QUADRATIC_BEZIER:case GX2D_SKETCH_CUBIC_BEZIER:r=GX2D_CONTROL_BEZIER;break;
    case GX2D_SKETCH_CIRCLE:r=i?GX2D_CONTROL_RADIUS:GX2D_CONTROL_CENTER;
        if(i)local.x+=d->radius_x;break;
    case GX2D_SKETCH_ARC:r=i==0?GX2D_CONTROL_CENTER:i==1?GX2D_CONTROL_ARC_START:GX2D_CONTROL_ARC_END;
        if(i){angle=d->angle_start+(i==2?d->angle_sweep:0);local.x+=d->radius_x*cos(angle);local.y+=d->radius_x*sin(angle);}break;
    case GX2D_SKETCH_ELLIPSE:r=i==0?GX2D_CONTROL_CENTER:i==1?GX2D_CONTROL_AXIS_X:GX2D_CONTROL_AXIS_Y;
        if(i){angle=d->rotation+(i==2?acos(-1)/2:0);double radius=i==1?d->radius_x:d->radius_y;local.x+=radius*cos(angle);local.y+=radius*sin(angle);}break;
    default:break;
    }
    *p=sketch_world(d,local,0);if(role)*role=r;return finite2(*p)?GX2D_OK:GX2D_RANGE;
}
/* Segment ordinals reserve a fixed stride for each exact leaf. The final
 * slot denotes the whole curved constituent; controls retain flat ordinals. */
#define NETWORK_STRIDE ((size_t)65536)
static int network_leaf(const object *root,size_t *index,object *leaf,gx2d_sketch_definition *definition,size_t *part) {
    if(!root||!root->sketch||!sketch_is_composition(root->sketch))return 0;
    size_t k=0,ix=*index;
    if(ix>=GX2D_CONTROL_INDEX&&ix<GX2D_SEGMENT_INDEX){ix-=GX2D_CONTROL_INDEX;
        for(;k<root->sketch->part_count;k++){object o={0};o.sketch=(gx2d_sketch_definition *)&root->sketch->parts[k];size_t n=control_count(&o);if(ix<n)break;ix-=n;}ix+=GX2D_CONTROL_INDEX;
    }else if(ix>=GX2D_SEGMENT_INDEX&&ix<GX2D_OBJECT_INDEX){k=(ix-GX2D_SEGMENT_INDEX)/NETWORK_STRIDE;ix=(ix-GX2D_SEGMENT_INDEX)%NETWORK_STRIDE;ix=ix==NETWORK_STRIDE-1?GX2D_OBJECT_INDEX:GX2D_SEGMENT_INDEX+ix;}
    else return 0;
    if(k>=root->sketch->part_count)return -1;
    *definition=root->sketch->parts[k];if(!sketch_compose(definition,root->sketch->matrix))return -1;
    *leaf=*root;leaf->sketch=definition;*index=ix;if(part)*part=k;return 1;
}
static size_t network_index(const object *root,size_t part,size_t index){
    if(index>=GX2D_CONTROL_INDEX&&index<GX2D_SEGMENT_INDEX){size_t offset=0;for(size_t k=0;k<part;k++){object o={0};o.sketch=(gx2d_sketch_definition *)&root->sketch->parts[k];offset+=control_count(&o);}return index+offset;}
    return GX2D_SEGMENT_INDEX+part*NETWORK_STRIDE+(index==GX2D_OBJECT_INDEX?NETWORK_STRIDE-1:index-GX2D_SEGMENT_INDEX);
}
static gx2d_status interaction_point(const object *o,size_t index,gx2d_point *p) {
    if(!o||o->kind==GX2D_GROUP)return GX2D_INVALID;
    object leaf;gx2d_sketch_definition definition;int resolved=network_leaf(o,&index,&leaf,&definition,NULL);
    if(resolved<0)return GX2D_INVALID;if(resolved)return interaction_point(&leaf,index,p);
    if(index==GX2D_OBJECT_INDEX){if(sketch_is_composition(o->sketch)){gx2d_status code=sketch_evaluate_valid(&o->sketch->parts[0],0,p,NULL);if(code==GX2D_OK)*p=sketch_world(o->sketch,*p,0);return code;}if(o->sketch)return control_point(o,0,p,NULL);index=0;}
    if(index>=GX2D_CONTROL_INDEX&&index<GX2D_SEGMENT_INDEX)return control_point(o,index-GX2D_CONTROL_INDEX,p,NULL);
    if(index>=GX2D_SEGMENT_INDEX&&index<GX2D_OBJECT_INDEX){
        size_t i=index-GX2D_SEGMENT_INDEX;const gx2d_sketch_definition *d=o->sketch;
        if(!d)return GX2D_INVALID;
        if(d->family==GX2D_SKETCH_SPLINE&&i+1<d->control_count)return sketch_evaluate_valid(d,(double)i/(d->control_count-1),p,NULL);
        if(d->family==GX2D_SKETCH_RECTANGLE&&i<4)return sketch_evaluate_valid(d,(double)i/4,p,NULL);
        if(d->family==GX2D_SKETCH_PATH&&i<d->control_count-1+(size_t)d->path_closed){*p=sketch_world(d,d->controls[i],0);return GX2D_OK;}
        if((d->family==GX2D_SKETCH_LINE||d->family==GX2D_SKETCH_CONSTRUCTION_LINE||d->family==GX2D_SKETCH_POLYLINE)&&i+1<d->control_count){*p=sketch_world(d,d->controls[i],0);return GX2D_OK;}
        return GX2D_INVALID;
    }
    if(index>=o->count)return GX2D_INVALID;*p=o->points[index];return GX2D_OK;
}
gx2d_status gx2d_sketch_construct(gx2d_sketch_family family,const gx2d_point *points,size_t n,
        gx2d_sketch_definition *out,gx2d_point *controls,size_t capacity) {
    gx2d_sketch_definition d;size_t count=n;gx2d_status code;
    if(!out||!controls||n>65536||!valid_points(points,n))return GX2D_INVALID;
    memset(&d,0,sizeof(d));d.family=family;d.matrix[0]=d.matrix[3]=1;
    switch(family){
    case GX2D_SKETCH_POINT:if(n!=1)return GX2D_INVALID;break;
    case GX2D_SKETCH_LINE:case GX2D_SKETCH_CONSTRUCTION_LINE:case GX2D_SKETCH_RECTANGLE:if(n!=2)return GX2D_INVALID;break;
    case GX2D_SKETCH_CIRCLE:if(n!=2)return GX2D_INVALID;count=1;d.radius_x=dist(points[0],points[1]);break;
    case GX2D_SKETCH_ARC:if(n!=3)return GX2D_INVALID;count=1;d.radius_x=dist(points[0],points[1]);
        d.angle_start=atan2(points[1].y-points[0].y,points[1].x-points[0].x);
        d.angle_sweep=atan2(points[2].y-points[0].y,points[2].x-points[0].x)-d.angle_start;
        if(d.angle_sweep<=0)d.angle_sweep+=2*acos(-1);break;
    case GX2D_SKETCH_ELLIPSE:if(n!=3)return GX2D_INVALID;count=1;d.radius_x=dist(points[0],points[1]);
        d.rotation=atan2(points[1].y-points[0].y,points[1].x-points[0].x);
        d.radius_y=fabs(-(points[2].x-points[0].x)*sin(d.rotation)+(points[2].y-points[0].y)*cos(d.rotation));break;
    case GX2D_SKETCH_QUADRATIC_BEZIER:if(n!=3)return GX2D_INVALID;break;
    case GX2D_SKETCH_CUBIC_BEZIER:if(n!=4)return GX2D_INVALID;break;
    case GX2D_SKETCH_PATH:case GX2D_SKETCH_POLYLINE:case GX2D_SKETCH_SPLINE:if(n<2)return GX2D_INVALID;break;
    default:return GX2D_INVALID;
    }
    if(family==GX2D_SKETCH_PATH&&n>2&&points[0].x==points[n-1].x&&points[0].y==points[n-1].y){count=n-1;d.path_closed=1;}
    d.controls=points;d.control_count=count;code=gx2d_sketch_validate(&d);if(code!=GX2D_OK)return code;
    if(capacity<count)return GX2D_RANGE;memcpy(controls,points,count*sizeof(*controls));d.controls=controls;*out=d;return GX2D_OK;
}
gx2d_status gx2d_reference_create(const gx2d_scene *s,gx2d_id id,gx2d_entity entity,size_t ordinal,gx2d_reference *out) {
    const object *o=cobj(s,id);gx2d_reference r;gx2d_point p;
    if(!s||!out||entity<GX2D_ENTITY_OBJECT||entity>GX2D_ENTITY_SEGMENT)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(o->sketch&&entity==GX2D_ENTITY_CONTROL&&ordinal>=control_count(o))return GX2D_RANGE;
    if(ordinal>=GX2D_CONTROL_INDEX&&entity!=GX2D_ENTITY_OBJECT)return GX2D_RANGE;
    r=(gx2d_reference){id,entity,ordinal,o->sketch?o->parameter_epoch:o->topology_epoch};
    if(entity==GX2D_ENTITY_OBJECT)r.index=GX2D_OBJECT_INDEX;
    else if(o->sketch)r.index=(entity==GX2D_ENTITY_CONTROL?GX2D_CONTROL_INDEX:GX2D_SEGMENT_INDEX)+ordinal;
    if(interaction_point(o,r.index,&p)!=GX2D_OK)return GX2D_INVALID;
    if(entity==GX2D_ENTITY_SEGMENT){
        if(o->sketch){gx2d_sketch_family f=o->sketch->family;if(f!=GX2D_SKETCH_COMPOUND&&f!=GX2D_SKETCH_COMPOSITE_PATH&&f!=GX2D_SKETCH_RECTANGLE&&f!=GX2D_SKETCH_LINE&&f!=GX2D_SKETCH_CONSTRUCTION_LINE&&f!=GX2D_SKETCH_POLYLINE&&f!=GX2D_SKETCH_PATH&&f!=GX2D_SKETCH_SPLINE)return GX2D_INVALID;
            if((f==GX2D_SKETCH_RECTANGLE&&ordinal>=4)||(f==GX2D_SKETCH_PATH?ordinal>=o->sketch->control_count-1+(size_t)o->sketch->path_closed:f!=GX2D_SKETCH_COMPOUND&&f!=GX2D_SKETCH_COMPOSITE_PATH&&f!=GX2D_SKETCH_RECTANGLE&&ordinal+1>=o->sketch->control_count))return GX2D_INVALID;
        }else if(ordinal+1>=o->count||o->breaks[ordinal])return GX2D_INVALID;
    }
    *out=r;return GX2D_OK;
}
gx2d_status gx2d_reference_from_index(const gx2d_scene *s,gx2d_id id,size_t index,gx2d_reference *out){
    if(index==GX2D_OBJECT_INDEX)return gx2d_reference_create(s,id,GX2D_ENTITY_OBJECT,0,out);
    if(index>=GX2D_OBJECT_INDEX)return GX2D_INVALID;
    if(index>=GX2D_SEGMENT_INDEX)return gx2d_reference_create(s,id,GX2D_ENTITY_SEGMENT,index-GX2D_SEGMENT_INDEX,out);
    return gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,index>=GX2D_CONTROL_INDEX?index-GX2D_CONTROL_INDEX:index,out);
}
gx2d_status gx2d_reference_resolve(const gx2d_scene *s,const gx2d_reference *r,gx2d_point *out) {
    const object *o;gx2d_reference canonical;size_t ordinal;gx2d_status code;
    if(!s||!r||!out||r->entity<GX2D_ENTITY_OBJECT||r->entity>GX2D_ENTITY_SEGMENT)return GX2D_INVALID;o=cobj(s,r->object);if(!o)return GX2D_NOT_FOUND;
    if(r->epoch!=(o->sketch?o->parameter_epoch:o->topology_epoch))return GX2D_CONSTRAINT;
    if(r->entity==GX2D_ENTITY_OBJECT){if(r->index!=GX2D_OBJECT_INDEX)return GX2D_INVALID;ordinal=0;}
    else if(o->sketch){
        size_t first=r->entity==GX2D_ENTITY_CONTROL?GX2D_CONTROL_INDEX:GX2D_SEGMENT_INDEX;
        size_t end=r->entity==GX2D_ENTITY_CONTROL?GX2D_SEGMENT_INDEX:GX2D_OBJECT_INDEX;
        if(r->index<first||r->index>=end)return GX2D_INVALID;ordinal=r->index-first;
    }else {if(r->index>=GX2D_CONTROL_INDEX)return GX2D_INVALID;ordinal=r->index;}
    code=gx2d_reference_create(s,r->object,r->entity,ordinal,&canonical);if(code!=GX2D_OK)return code;
    return interaction_point(o,r->index,out);
}
gx2d_status gx2d_sketch_controls(const gx2d_scene *s,gx2d_id id,gx2d_control *out,size_t cap,size_t *count) {
    const object *o=cobj(s,id);size_t i,n;gx2d_status code;
    if(!s||!count)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(!o->sketch)return GX2D_INVALID;n=control_count(o);
    if(out&&cap<n)return GX2D_RANGE;
    for(i=0;out&&i<n;++i){code=gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,i,&out[i].reference);if(code!=GX2D_OK)return code;
        code=control_point(o,i,&out[i].point,&out[i].role);if(code!=GX2D_OK)return code;}
    *count=n;return GX2D_OK;
}
static gx2d_status interaction_inverse(const gx2d_sketch_definition *d,gx2d_point p,gx2d_point *out) {
    long double det=(long double)d->matrix[0]*d->matrix[3]-(long double)d->matrix[1]*d->matrix[2],x=p.x-d->matrix[4],y=p.y-d->matrix[5];
    if(det==0)return GX2D_INVALID;*out=(gx2d_point){(double)((d->matrix[3]*x-d->matrix[1]*y)/det),(double)((d->matrix[0]*y-d->matrix[2]*x)/det)};
    return finite2(*out)?GX2D_OK:GX2D_RANGE;
}
/* Edit actual defining parameters in an owned leaf; never sampled proxies. */
static gx2d_status control_leaf_edit(gx2d_sketch_definition *copy,size_t i,gx2d_point target) {
    gx2d_sketch_definition d=*copy;object leaf={0};leaf.sketch=copy;
    gx2d_point local;double angle;gx2d_status code;
    if(i>=control_count(&leaf))return GX2D_RANGE;
    code=interaction_inverse(&d,target,&local);if(code!=GX2D_OK)return code;
    if(d.family==GX2D_SKETCH_CIRCLE||d.family==GX2D_SKETCH_ARC||d.family==GX2D_SKETCH_ELLIPSE){
        if(i==0)((gx2d_point *)copy->controls)[0]=local;
        else if(d.family==GX2D_SKETCH_CIRCLE)copy->radius_x=dist(d.controls[0],local);
        else if(d.family==GX2D_SKETCH_ARC){
            angle=atan2(local.y-d.controls[0].y,local.x-d.controls[0].x);
            if(i==1){double end=d.angle_start+d.angle_sweep;copy->radius_x=dist(d.controls[0],local);copy->angle_start=angle;copy->angle_sweep=end-angle;}
            else copy->angle_sweep=angle-d.angle_start;
            if(d.angle_sweep>0){while(copy->angle_sweep<=0)copy->angle_sweep+=2*acos(-1);}else{while(copy->angle_sweep>=0)copy->angle_sweep-=2*acos(-1);}
        }else if(i==1){copy->radius_x=dist(d.controls[0],local);copy->rotation=atan2(local.y-d.controls[0].y,local.x-d.controls[0].x);}
        else copy->radius_y=fabs(-(local.x-d.controls[0].x)*sin(d.rotation)+(local.y-d.controls[0].y)*cos(d.rotation));
    }else ((gx2d_point *)copy->controls)[i]=local;
    return gx2d_sketch_validate(copy);
}
static size_t control_endpoint_index(const gx2d_sketch_definition *d,int end) {
    if(d->family==GX2D_SKETCH_ARC)return end?2:1;
    return end?d->control_count-1:0;
}
gx2d_status gx2d_control_definition_owned(const gx2d_scene *s,const gx2d_reference *r,gx2d_point target,
        gx2d_sketch_definition **out) {
    const object *o;gx2d_point point,local;gx2d_status code;size_t ordinal;
    if(!s||!r||!out||!finite2(target))return GX2D_INVALID;
    code=gx2d_reference_resolve(s,r,&point);if(code!=GX2D_OK)return code;o=cobj(s,r->object);
    if(!o->sketch||o->reference_image||r->entity!=GX2D_ENTITY_CONTROL||r->index<GX2D_CONTROL_INDEX)return GX2D_INVALID;
    gx2d_sketch_definition *copy=sketch_clone(o->sketch);if(!copy)return GX2D_NOMEM;
    ordinal=r->index-GX2D_CONTROL_INDEX;
    if(copy->family==GX2D_SKETCH_COMPOSITE_PATH){
        code=interaction_inverse(copy,target,&local);
        size_t k=0;
        for(;code==GX2D_OK&&k<copy->part_count;k++){
            object leaf={0};leaf.sketch=(gx2d_sketch_definition *)&copy->parts[k];size_t n=control_count(&leaf);
            if(ordinal<n)break;ordinal-=n;
        }
        if(code==GX2D_OK&&k==copy->part_count)code=GX2D_RANGE;
        if(code==GX2D_OK){
            gx2d_sketch_definition *parts=(gx2d_sketch_definition *)copy->parts;
            code=control_leaf_edit(&parts[k],ordinal,local);
            if(copy->node_count){size_t selected=r->index-GX2D_CONTROL_INDEX,offset=0;
                for(size_t j=0;code==GX2D_OK&&j<copy->part_count;j++){object leaf={0};leaf.sketch=&parts[j];size_t count=control_count(&leaf);
                    for(size_t c=0;c<count&&code==GX2D_OK;c++)if(copy->nodes[offset+c]==copy->nodes[selected]&&(j!=k||c!=ordinal))code=control_leaf_edit(&parts[j],c,local);offset+=count;}
            }
            /* A Path junction is one shared topological point. Propagate the
             * edited leaf's endpoints to its neighbors in the defining frame.
             * Exact validation rejects any unsupported coupled round edit. */
            for(int side=0;!copy->node_count&&code==GX2D_OK&&side<2;side++){
                if((side==0&&k==0)||(side==1&&k+1==copy->part_count)){
                    if(!copy->path_closed)continue;
                }
                size_t neighbor=side?(k+1)%copy->part_count:(k+copy->part_count-1)%copy->part_count;
                if(neighbor==k)continue;
                int end=side?!copy->part_reversed[k]:copy->part_reversed[k];
                code=gx2d_sketch_evaluate(&parts[k],end,&point,NULL);
                int otherEnd=side?copy->part_reversed[neighbor]:!copy->part_reversed[neighbor];
                if(code==GX2D_OK)code=control_leaf_edit(&parts[neighbor],control_endpoint_index(&parts[neighbor],otherEnd),point);
            }
        }
    }else code=control_leaf_edit(copy,ordinal,target);
    if(code==GX2D_OK)code=gx2d_sketch_validate(copy);
    if(code!=GX2D_OK){sketch_free(copy);return code;}*out=copy;return GX2D_OK;
}
void gx2d_control_definition_release(gx2d_sketch_definition *definition){sketch_free(definition);}
gx2d_status gx2d_control_definition(const gx2d_scene *s,const gx2d_reference *r,gx2d_point target,
    gx2d_sketch_definition *out,gx2d_point *controls,size_t cap) {
    gx2d_sketch_definition *copy=NULL;gx2d_status code;
    if(!out||!controls)return GX2D_INVALID;
    code=gx2d_control_definition_owned(s,r,target,&copy);if(code!=GX2D_OK)return code;
    /* The legacy caller-buffer ABI cannot own heterogeneous part arrays.
     * The additive owned form is used by preview/adoption for all families. */
    if(sketch_is_composition(copy)){sketch_free(copy);return GX2D_INVALID;}
    if(cap<copy->control_count){sketch_free(copy);return GX2D_RANGE;}
    memcpy(controls,copy->controls,copy->control_count*sizeof(*controls));*out=*copy;out->controls=controls;
    const gx2d_sketch_definition *old=cobj(s,r->object)->sketch;
    out->tangents=old->tangents;out->tangent_count=old->tangent_count;
    out->path_segments=old->path_segments;out->path_segment_count=old->path_segment_count;
    sketch_free(copy);return GX2D_OK;
}
gx2d_status gx2d_control_edit(gx2d_scene *s,const gx2d_reference *r,gx2d_point target) {
    const object *o;gx2d_sketch_definition *d=NULL;gx2d_status code;
    if(!s||!r)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;o=cobj(s,r->object);if(!o)return GX2D_NOT_FOUND;
    if(!o->sketch){gx2d_point p;code=gx2d_reference_resolve(s,r,&p);if(code!=GX2D_OK)return code;if(r->entity!=GX2D_ENTITY_CONTROL)return GX2D_INVALID;return gx2d_set_point(s,r->object,r->index,target);}
    if(o->sketch->node_count||sketch_has_solver(s,r->object))return gx2d_sketch_solve_control(s,r,target);
    code=gx2d_control_definition_owned(s,r,target,&d);
    if(code==GX2D_OK)code=gx2d_sketch_update(s,r->object,d,o->count);
    sketch_free(d);return code;
}
gx2d_status gx2d_interaction_pick(const gx2d_scene *s,gx2d_id id,gx2d_point device,double tolerance,gx2d_reference *out) {
    const object *o=cobj(s,id);gx2d_point p,q;size_t i,best=0;double distance=DBL_MAX;gx2d_status code;gx2d_hit h;gx2d_segment_hit hit;
    if(!s||!out||!finite2(device)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(!can_select(s,o)||!o->style.selectable||o->kind==GX2D_GROUP)return GX2D_NOT_FOUND;
    if(!o->sketch){code=gx2d_hit_point_device(s,id,device,tolerance,&h);if(code==GX2D_OK)return gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,h.point_index,out);}
    else {for(i=0;i<control_count(o);++i){code=control_point(o,i,&p,NULL);if(code!=GX2D_OK)return code;gx2d_world_to_device(s,p,&q);double d=dist(device,q);if(d<distance){distance=d;best=i;}}
        if(distance<=tolerance)return gx2d_reference_create(s,id,GX2D_ENTITY_CONTROL,best,out);}
    gx2d_device_to_world(s,device,&p);
    if(o->sketch&&sketch_is_composition(o->sketch)){
        size_t chosen=0;double closest=DBL_MAX;
        for(size_t k=0;k<o->sketch->part_count;k++){
            gx2d_sketch_definition d=o->sketch->parts[k];sketch_compose(&d,o->sketch->matrix);
            int straight=d.family==GX2D_SKETCH_LINE||d.family==GX2D_SKETCH_POLYLINE||d.family==GX2D_SKETCH_PATH||d.family==GX2D_SKETCH_RECTANGLE;
            size_t edges=straight?(d.family==GX2D_SKETCH_RECTANGLE?4:d.control_count-1+(size_t)d.path_closed):128;
            for(size_t j=0;j<edges;j++){gx2d_point a,b,da,db;
                if(straight&&d.family!=GX2D_SKETCH_RECTANGLE){a=sketch_world(&d,d.controls[j],0);b=sketch_world(&d,d.controls[(j+1)%d.control_count],0);}
                else {sketch_evaluate_valid(&d,(double)j/edges,&a,NULL);sketch_evaluate_valid(&d,(double)(j+1)/edges,&b,NULL);}
                gx2d_world_to_device(s,a,&da);gx2d_world_to_device(s,b,&db);double distance=dist(device,nearest_segment(device,da,db));
                if(distance<closest){closest=distance;chosen=k*NETWORK_STRIDE+(straight?j:NETWORK_STRIDE-1);}
            }
        }
        if(closest<=tolerance)return gx2d_reference_create(s,id,GX2D_ENTITY_SEGMENT,chosen,out);return GX2D_NOT_FOUND;
    }
    if(o->kind==GX2D_POINT_OBJECT)return GX2D_NOT_FOUND;
    code=gx2d_nearest_segment(s,id,p,&hit);if(code!=GX2D_OK)return code;gx2d_world_to_device(s,hit.point,&q);if(dist(device,q)>tolerance)return GX2D_NOT_FOUND;
    if(o->sketch){gx2d_sketch_family f=o->sketch->family;
        if(f==GX2D_SKETCH_LINE||f==GX2D_SKETCH_CONSTRUCTION_LINE)return gx2d_reference_create(s,id,GX2D_ENTITY_SEGMENT,0,out);
        if(f==GX2D_SKETCH_RECTANGLE)return gx2d_reference_create(s,id,GX2D_ENTITY_SEGMENT,hit.segment,out);
        if(f==GX2D_SKETCH_POLYLINE||f==GX2D_SKETCH_PATH){size_t edges=o->sketch->control_count-1+(f==GX2D_SKETCH_PATH&&o->sketch->path_closed);distance=DBL_MAX;for(i=0;i<edges;++i){gx2d_point a=sketch_world(o->sketch,o->sketch->controls[i],0),b=sketch_world(o->sketch,o->sketch->controls[(i+1)%o->sketch->control_count],0);double d=dist(p,nearest_segment(p,a,b));if(d<distance){distance=d;best=i;}}return gx2d_reference_create(s,id,GX2D_ENTITY_SEGMENT,best,out);}
        return gx2d_reference_create(s,id,GX2D_ENTITY_OBJECT,0,out);
    }
    return gx2d_reference_create(s,id,GX2D_ENTITY_SEGMENT,hit.segment,out);
}
gx2d_status gx2d_placement_snap(const gx2d_scene *s,gx2d_point device,double tolerance,const gx2d_id *excluded,size_t ne,
    int objects,int grid,gx2d_point *out,int *kind,gx2d_reference *ref) {
    size_t i,j;double best=tolerance;gx2d_point world,p,q;gx2d_reference r={0};int found=0;
    gx2d_id *excluded_expanded=NULL;size_t expanded_count=0;gx2d_status code;
    if(!s||!out||!kind||!ref||!finite2(device)||!isfinite(tolerance)||tolerance<0||(ne&&!excluded)||(objects!=0&&objects!=1)||(grid!=0&&grid!=1))return GX2D_INVALID;
    if(ne){code=cad_expand(s,excluded,ne,&excluded_expanded,&expanded_count);if(code!=GX2D_OK)return code;}
    gx2d_device_to_world(s,device,&world);
    for(i=0;objects&&i<s->object_count;++i){const object *o=&s->objects[i];int skip=0;
        if(o->kind==GX2D_GROUP||!can_select(s,o)||!o->style.selectable)continue;for(j=0;j<expanded_count;++j)if(excluded_expanded[j]==o->id)skip=1;if(skip)continue;
        if(!o->sketch){gx2d_hit hit;if(gx2d_hit_point_device(s,o->id,device,best,&hit)==GX2D_OK){world=hit.point;best=hit.distance;found=1;gx2d_reference_create(s,o->id,GX2D_ENTITY_CONTROL,hit.point_index,&r);}continue;}
        for(j=0;j<control_count(o);++j){gx2d_control_role role;control_point(o,j,&p,&role);gx2d_world_to_device(s,p,&q);double d=dist(device,q);if(d<=best){best=d;world=p;found=role==GX2D_CONTROL_CENTER?5:role==GX2D_CONTROL_ENDPOINT?4:1;gx2d_reference_create(s,o->id,GX2D_ENTITY_CONTROL,j,&r);}}
        size_t segments=o->sketch->family==GX2D_SKETCH_PATH?o->sketch->control_count-1+(size_t)o->sketch->path_closed:o->sketch->family==GX2D_SKETCH_RECTANGLE?4:(o->sketch->family==GX2D_SKETCH_LINE||o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE||o->sketch->family==GX2D_SKETCH_POLYLINE?o->sketch->control_count-1:0);
        for(j=0;j<segments;++j){gx2d_point a,b;interaction_point(o,GX2D_SEGMENT_INDEX+j,&a);if(o->sketch->family==GX2D_SKETCH_RECTANGLE)sketch_evaluate_valid(o->sketch,(double)(j+1)/4,&b,NULL);else b=sketch_world(o->sketch,o->sketch->controls[(j+1)%o->sketch->control_count],0);
            p=(gx2d_point){a.x/2+b.x/2,a.y/2+b.y/2};gx2d_world_to_device(s,p,&q);double d=dist(device,q);if(d<best){best=d;world=p;found=2;gx2d_reference_create(s,o->id,GX2D_ENTITY_SEGMENT,j,&r);}}
    }
    if(!found&&grid&&s->grid.enabled&&s->grid.snap_enabled){gx2d_status code=gx2d_grid_snap(s,world,3,&p);if(code!=GX2D_OK){free(excluded_expanded);return code;}world=p;found=3;}
    free(excluded_expanded);*out=world;*kind=found;*ref=r;return GX2D_OK;
}
gx2d_status gx2d_viewport_clip_segment(const gx2d_scene *s,gx2d_point a,gx2d_point b,double inset,gx2d_point *first,gx2d_point *last,int *shown) {
    long double lo=0,hi=1,p[4],q[4];size_t i;gx2d_rect r;
    if(!s||!first||!last||!shown||!finite2(a)||!finite2(b)||!isfinite(inset)||inset<0)return GX2D_INVALID;
    r=(gx2d_rect){s->view.left+inset,s->view.top+inset,s->view.width-s->view.right-inset,s->view.height-s->view.bottom-inset};
    if(r.x0>r.x1||r.y0>r.y1){*shown=0;return GX2D_OK;}
    p[0]=(long double)a.x-b.x;p[1]=-p[0];p[2]=(long double)a.y-b.y;p[3]=-p[2];
    q[0]=(long double)a.x-r.x0;q[1]=(long double)r.x1-a.x;q[2]=(long double)a.y-r.y0;q[3]=(long double)r.y1-a.y;
    for(i=0;i<4;++i){if(p[i]==0){if(q[i]<0){*shown=0;return GX2D_OK;}continue;}long double t=q[i]/p[i];if(p[i]<0){if(t>hi){*shown=0;return GX2D_OK;}if(t>lo)lo=t;}else{if(t<lo){*shown=0;return GX2D_OK;}if(t<hi)hi=t;}}
    *first=(gx2d_point){(double)((1-lo)*a.x+lo*b.x),(double)((1-lo)*a.y+lo*b.y)};
    *last=(gx2d_point){(double)((1-hi)*a.x+hi*b.x),(double)((1-hi)*a.y+hi*b.y)};*shown=1;return GX2D_OK;
}
/* Translate the existing Numerical curve-model parameter contract into an
 * exact retained definition. This does no fitting or recognition. */
gx2d_status gx2d_sketch_from_fit(gx2d_sketch_family family,const double *parameters,size_t n,
    gx2d_sketch_definition *out,gx2d_point *controls,size_t cap){
    gx2d_sketch_definition d;gx2d_point points[4];size_t count,i;gx2d_status code;
    if(!parameters||!out||!controls||n>8)return GX2D_INVALID;for(i=0;i<n;++i)if(!isfinite(parameters[i]))return GX2D_INVALID;
    memset(&d,0,sizeof(d));d.family=family;d.matrix[0]=d.matrix[3]=1;
    if(family==GX2D_SKETCH_CIRCLE||family==GX2D_SKETCH_ARC){if(n!=5)return GX2D_INVALID;count=1;points[0]=(gx2d_point){parameters[0],parameters[1]};d.radius_x=parameters[2];
        if(family==GX2D_SKETCH_ARC){d.angle_start=parameters[3];d.angle_sweep=parameters[4]-parameters[3];}}
    else if(family==GX2D_SKETCH_QUADRATIC_BEZIER||family==GX2D_SKETCH_CUBIC_BEZIER){count=family==GX2D_SKETCH_QUADRATIC_BEZIER?3:4;if(n!=count*2)return GX2D_INVALID;for(i=0;i<count;++i)points[i]=(gx2d_point){parameters[i],parameters[i+count]};}
    else return GX2D_INVALID;
    d.controls=points;d.control_count=count;code=gx2d_sketch_validate(&d);if(code!=GX2D_OK)return code;if(cap<count)return GX2D_RANGE;
    memcpy(controls,points,count*sizeof(*controls));d.controls=controls;*out=d;return GX2D_OK;
}
gx2d_status gx2d_sketch_preview_definition(gx2d_sketch_family family,const gx2d_point *points,size_t n,
    gx2d_sketch_definition *out,gx2d_point *controls,size_t cap){
    gx2d_sketch_definition d;gx2d_status code;
    if(!out||!controls||n>65536||!valid_points(points,n))return GX2D_INVALID;
    if(n==1)return gx2d_sketch_construct(GX2D_SKETCH_POINT,points,n,out,controls,cap);
    if((family==GX2D_SKETCH_ARC||family==GX2D_SKETCH_ELLIPSE)&&n==2){
        code=gx2d_sketch_construct(GX2D_SKETCH_CIRCLE,points,2,&d,controls,cap);if(code!=GX2D_OK)return code;
        d.family=family;d.rotation=atan2(points[1].y-points[0].y,points[1].x-points[0].x);d.angle_start=d.rotation;d.angle_sweep=acos(-1)/2;d.radius_y=d.radius_x;*out=d;return GX2D_OK;
    }
    if((family==GX2D_SKETCH_QUADRATIC_BEZIER||family==GX2D_SKETCH_CUBIC_BEZIER)&&n==2)return gx2d_sketch_construct(GX2D_SKETCH_LINE,points,n,out,controls,cap);
    if(family==GX2D_SKETCH_CUBIC_BEZIER&&n==3)return gx2d_sketch_construct(GX2D_SKETCH_QUADRATIC_BEZIER,points,n,out,controls,cap);
    return gx2d_sketch_construct(family,points,n,out,controls,cap);
}
/* Compatibility with the existing endpoint Join API, only for actual defining
 * endpoints. Arbitrary display samples never become control references. */
gx2d_status gx2d_reference_point_index(const gx2d_scene *s,const gx2d_reference *r,size_t *out){
    gx2d_point point;gx2d_status code;const object *o;size_t i;
    if(!out)return GX2D_INVALID;code=gx2d_reference_resolve(s,r,&point);if(code!=GX2D_OK)return code;
    if(r->entity!=GX2D_ENTITY_CONTROL)return GX2D_INVALID;o=cobj(s,r->object);
    if(!o->sketch){*out=r->index;return GX2D_OK;}i=r->index-GX2D_CONTROL_INDEX;
    if(o->sketch->family==GX2D_SKETCH_POINT){*out=0;return GX2D_OK;}
    if(o->sketch->family==GX2D_SKETCH_LINE||o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE){*out=i;return GX2D_OK;}
    if(o->sketch->family==GX2D_SKETCH_PATH&&i<o->sketch->control_count){*out=i;return GX2D_OK;}
    if((o->sketch->family==GX2D_SKETCH_POLYLINE||o->sketch->family==GX2D_SKETCH_SPLINE||o->sketch->family==GX2D_SKETCH_QUADRATIC_BEZIER||o->sketch->family==GX2D_SKETCH_CUBIC_BEZIER)&&(i==0||i==o->sketch->control_count-1)){*out=i==0?0:o->count-1;return GX2D_OK;}
    return GX2D_INVALID;
}

/* Query derives untouched arms through the same evaluator as rendering/G2.
 * Editing stores offsets, never display samples or device coordinates. */
static const gx2d_sketch_definition *spline_control_leaf(const gx2d_sketch_definition *root,size_t *knot,size_t *part) {
    *part=SIZE_MAX;
    if(!root)return NULL;
    if(root->family==GX2D_SKETCH_COMPOSITE_PATH){
        for(size_t k=0;k<root->part_count;k++){
            object leaf={0};leaf.sketch=(gx2d_sketch_definition *)&root->parts[k];size_t n=control_count(&leaf);
            if(*knot<n){*part=k;root=&root->parts[k];break;}*knot-=n;
        }
        if(*part==SIZE_MAX)return NULL;
    }
    return root->family==GX2D_SKETCH_SPLINE&&*knot<root->control_count?root:NULL;
}
gx2d_status gx2d_spline_tangent_get(const gx2d_scene *s,gx2d_id id,size_t knot,int incoming,gx2d_point *anchor,gx2d_point *handle,int *explicit_state) {
    const object *o=cobj(s,id);gx2d_point b[4];size_t part;
    if(!s||!anchor||!handle||!explicit_state||(incoming!=0&&incoming!=1))return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    const gx2d_sketch_definition *d=spline_control_leaf(o->sketch,&knot,&part);
    if(!d)return GX2D_INVALID;
    if(knot>=d->control_count||(incoming?knot==0:knot+1==d->control_count))return GX2D_RANGE;
    sketch_spline_controls(d,incoming?knot-1:knot,b);
    *anchor=sketch_world(d,d->controls[knot],0);*handle=sketch_world(d,b[incoming?2:1],0);
    /* Reversed traversal does not rename a leaf's defining incoming/outgoing
     * controls. Only its root/leaf affine frames affect handle coordinates. */
    if(part!=SIZE_MAX){*anchor=sketch_world(o->sketch,*anchor,0);*handle=sketch_world(o->sketch,*handle,0);}
    *explicit_state=d->tangent_count&&(d->tangents[knot].flags&(incoming?1:2));
    return finite2(*anchor)&&finite2(*handle)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_spline_tangent_edit(gx2d_scene *s,gx2d_id id,size_t knot,int incoming,gx2d_point target,int reset) {
    gx2d_point anchor,handle,local;int explicit_state;gx2d_status code;
    if(!s||!finite2(target)||(reset!=0&&reset!=1))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    code=gx2d_spline_tangent_get(s,id,knot,incoming,&anchor,&handle,&explicit_state);if(code!=GX2D_OK)return code;
    object *o=obj(s,id);if(!can_move(s,o))return GX2D_LOCKED;
    /* The bounded object-symmetry solver currently constrains spline knots,
     * not independent arms. Reject rather than publish a false mirrored shape. */
    for(size_t i=0;i<s->rule_count;i++)if(!s->rules[i].disabled&&s->rules[i].spec.kind==GX2D_SYMMETRY&&(s->rules[i].spec.a==id||s->rules[i].spec.b==id))return GX2D_CONSTRAINT;

    gx2d_sketch_definition *d=sketch_clone(o->sketch);if(!d)return GX2D_NOMEM;
    size_t part;gx2d_sketch_definition *leaf=(gx2d_sketch_definition *)spline_control_leaf(d,&knot,&part);
    code=GX2D_OK;
    if(part!=SIZE_MAX)code=interaction_inverse(d,target,&target);
    if(code==GX2D_OK)code=interaction_inverse(leaf,target,&local);
    if(code==GX2D_OK){
        gx2d_spline_tangent *t=(gx2d_spline_tangent *)&leaf->tangents[knot];unsigned bit=incoming?1:2;
        if(reset)t->flags&=~bit;
        else {gx2d_point offset={local.x-leaf->controls[knot].x,local.y-leaf->controls[knot].y};if(incoming)t->incoming=offset;else t->outgoing=offset;t->flags|=bit;}
        code=gx2d_sketch_update(s,id,d,o->count);
    }
    sketch_free(d);return code;
}
