/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Persistent native validation/enforcement. No general nonlinear solver. */
static gx2d_status constraint_point(const object *o,size_t index,gx2d_point *p) {
    return interaction_point(o,index,p);
}
static gx2d_status constraint_segment(const object *o,size_t index,gx2d_point *a,gx2d_point *b,gx2d_point *direction) {
    double length;object leaf;gx2d_sketch_definition definition;
    int resolved=network_leaf(o,&index,&leaf,&definition,NULL);if(resolved<0)return GX2D_INVALID;if(resolved)return constraint_segment(&leaf,index,a,b,direction);
    if(o&&o->sketch&&index>=GX2D_SEGMENT_INDEX){size_t i=index==GX2D_OBJECT_INDEX?0:index-GX2D_SEGMENT_INDEX;
        const gx2d_sketch_definition *d=o->sketch;
        if(d->family==GX2D_SKETCH_RECTANGLE&&i<4){sketch_evaluate_valid(d,(double)i/4,a,NULL);sketch_evaluate_valid(d,(double)(i+1)/4,b,NULL);}
        else if(d->family==GX2D_SKETCH_PATH&&i<d->control_count-1+(size_t)d->path_closed){*a=sketch_world(d,d->controls[i],0);*b=sketch_world(d,d->controls[(i+1)%d->control_count],0);}
        else if((d->family==GX2D_SKETCH_LINE||d->family==GX2D_SKETCH_CONSTRUCTION_LINE||d->family==GX2D_SKETCH_POLYLINE)&&i+1<d->control_count){*a=sketch_world(d,d->controls[i],0);*b=sketch_world(d,d->controls[(i+1)%d->control_count],0);}
        else return GX2D_INVALID;
        length=dist(*a,*b);if(length==0||!isfinite(length))return GX2D_INVALID;*direction=(gx2d_point){(b->x-a->x)/length,(b->y-a->y)/length};return GX2D_OK;
    }
    if(!o||o->kind!=GX2D_CURVE||index+1>=o->count||o->breaks[index])return GX2D_INVALID;
    if(o->sketch){gx2d_sketch_family family=o->sketch->family;
        if(family!=GX2D_SKETCH_LINE&&family!=GX2D_SKETCH_CONSTRUCTION_LINE&&family!=GX2D_SKETCH_RECTANGLE&&!(family==GX2D_SKETCH_POLYLINE&&o->count==o->sketch->control_count))return GX2D_INVALID;}
    *a=o->points[index];*b=o->points[index+1];length=dist(*a,*b);if(!isfinite(length)||length==0)return GX2D_INVALID;
    *direction=(gx2d_point){(b->x-a->x)/length,(b->y-a->y)/length};return GX2D_OK;
}
gx2d_status gx2d_reference_render(const gx2d_scene *s,const gx2d_reference *ref,gx2d_point *out,size_t cap,size_t *count) {
    gx2d_point checked,a,b,dir;gx2d_status code;
    if(!s||!ref||!count||ref->entity!=GX2D_ENTITY_SEGMENT)return GX2D_INVALID;
    code=gx2d_reference_resolve(s,ref,&checked);if(code!=GX2D_OK)return code;
    const object *o=cobj(s,ref->object);object leaf;gx2d_sketch_definition definition;size_t index=ref->index;
    int mapped=network_leaf(o,&index,&leaf,&definition,NULL);
    if(mapped<0)return GX2D_INVALID;
    const gx2d_sketch_definition *shape=mapped?&definition:o->sketch;
    int span=shape&&shape->family==GX2D_SKETCH_SPLINE&&index>=GX2D_SEGMENT_INDEX&&index<GX2D_OBJECT_INDEX;
    int curved=(mapped&&index==GX2D_OBJECT_INDEX)||span;
    double first=span?(double)(index-GX2D_SEGMENT_INDEX)/(shape->control_count-1):0;
    double last=span?(double)(index-GX2D_SEGMENT_INDEX+1)/(shape->control_count-1):1;
    size_t n=curved?129:2;
    if(out&&cap<n)return GX2D_RANGE;
    if(!curved){code=constraint_segment(o,ref->index,&a,&b,&dir);if(code!=GX2D_OK)return code;}
    for(size_t i=0;out&&i<n;i++){
        gx2d_point p={0,0};if(!curved)p=i?b:a;
        if(curved){code=sketch_evaluate_valid(shape,first+(last-first)*(double)i/(n-1),&p,NULL);if(code!=GX2D_OK)return code;}
        code=gx2d_world_to_device(s,p,out+i);if(code!=GX2D_OK)return code;
    }
    *count=n;return GX2D_OK;
}
static gx2d_status constraint_radius(const object *o,double *radius) {
    double u,v,cross;const gx2d_sketch_definition *d;
    if(!o||!(d=o->sketch)||(d->family!=GX2D_SKETCH_CIRCLE&&d->family!=GX2D_SKETCH_ARC))return GX2D_INVALID;
    u=hypot(d->matrix[0],d->matrix[2]);v=hypot(d->matrix[1],d->matrix[3]);if(u==0||v==0)return GX2D_INVALID;
    cross=(d->matrix[0]/u)*(d->matrix[1]/v)+(d->matrix[2]/u)*(d->matrix[3]/v);
    if(fabs(u-v)>1e-10*fmax(u,v)||fabs(cross)>1e-10)return GX2D_INVALID;
    *radius=d->radius_x*u;return isfinite(*radius)?GX2D_OK:GX2D_RANGE;
}
static gx2d_status constraint_center(const object *o,gx2d_point *center) {
    const gx2d_sketch_definition *d;if(!o||!(d=o->sketch)||
       (d->family!=GX2D_SKETCH_CIRCLE&&d->family!=GX2D_SKETCH_ARC&&d->family!=GX2D_SKETCH_ELLIPSE))return GX2D_INVALID;
    *center=sketch_world(d,d->controls[0],0);return finite2(*center)?GX2D_OK:GX2D_RANGE;
}
static gx2d_status constraint_curve_distance(const gx2d_scene *s,const object *o,gx2d_point p,double *distance) {
    gx2d_segment_hit hit;gx2d_status code;
    if(!o||o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch){const gx2d_sketch_definition *d=o->sketch;
        if(d->family==GX2D_SKETCH_CIRCLE){double radius;gx2d_point center;
            code=constraint_radius(o,&radius);if(code!=GX2D_OK)return code;code=constraint_center(o,&center);if(code!=GX2D_OK)return code;
            *distance=fabs(dist(p,center)-radius);return isfinite(*distance)?GX2D_OK:GX2D_RANGE;}
        if(d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_PATH){double best=DBL_MAX;size_t i;
            for(i=0;i<d->control_count-1+(size_t)(d->family==GX2D_SKETCH_PATH&&d->path_closed);++i){gx2d_point a=sketch_world(d,d->controls[i],0),b=sketch_world(d,d->controls[(i+1)%d->control_count],0),q=nearest_segment(p,a,b);double value=dist(p,q);if(value<best)best=value;}
            *distance=best;return isfinite(best)?GX2D_OK:GX2D_RANGE;}
        if(d->family!=GX2D_SKETCH_LINE&&d->family!=GX2D_SKETCH_CONSTRUCTION_LINE&&d->family!=GX2D_SKETCH_RECTANGLE)return GX2D_INVALID;
    }
    code=gx2d_nearest_segment(s,o->id,p,&hit);if(code==GX2D_OK)*distance=hit.distance;return code;
}
static gx2d_status rule_check_extended(const gx2d_scene *s,const rule *r,gx2d_constraint_diagnostic *diagnostic) {
    if(r->presentation.solved)return sketch_rule_check(s,r,diagnostic);
    const gx2d_constraint *c=&r->spec;const object *a=cobj(s,c->a),*b=cobj(s,c->b),*axis=cobj(s,r->axis);
    gx2d_point pa,pb,qa,qb,da,db,center;double value=0,residual=0,angular=0,ra,rb;gx2d_status code=GX2D_OK;
    gx2d_endpoint_frame fa,fb;gx2d_metrics ma,mb;
    if(constraint_point(a,c->a_index,&pa)!=GX2D_OK){code=GX2D_INVALID;goto result;}
    if(constraint_point(b,c->b_index,&pb)!=GX2D_OK)pb=(gx2d_point){0,0};
    switch(c->kind){
        case GX2D_FIXED:value=dist(pa,r->anchor);residual=value;break;
        case GX2D_LOCK_X:value=pa.x;residual=fabs(value-c->value);break;
        case GX2D_LOCK_Y:value=pa.y;residual=fabs(value-c->value);break;
        case GX2D_RADIUS:case GX2D_DIAMETER:
            code=constraint_radius(a,&value);if(code!=GX2D_OK)goto result;if(c->kind==GX2D_DIAMETER)value*=2;residual=fabs(value-c->value);break;
        case GX2D_HORIZONTAL:case GX2D_VERTICAL:
            code=constraint_segment(a,c->a_index,&pa,&qa,&da);if(code!=GX2D_OK)goto result;
            value=c->kind==GX2D_HORIZONTAL?fabs(qa.y-pa.y):fabs(qa.x-pa.x);residual=value;break;
        default:
            code=constraint_point(b,c->b_index,&pb);if(code!=GX2D_OK)goto result;
            switch(c->kind){
                case GX2D_DISTANCE:value=dist(pa,pb);residual=fabs(value-c->value);break;
                case GX2D_COINCIDENT:value=dist(pa,pb);residual=value;break;
                case GX2D_ANGLE:case GX2D_PARALLEL:case GX2D_PERPENDICULAR:
                    if((c->a_index>=GX2D_SEGMENT_INDEX?constraint_segment(a,c->a_index,&pa,&qa,&da):direction_raw(a,&da))!=GX2D_OK||(c->b_index>=GX2D_SEGMENT_INDEX?constraint_segment(b,c->b_index,&pb,&qb,&db):direction_raw(b,&db))!=GX2D_OK){code=GX2D_INVALID;goto result;}
                    value=atan2(da.x*db.y-da.y*db.x,da.x*db.x+da.y*db.y);
                    residual=c->kind==GX2D_ANGLE?fabs(atan2(sin(value-c->value),cos(value-c->value))):c->kind==GX2D_PARALLEL?fabs(sin(value)):fabs(cos(value));break;
                case GX2D_EQUAL_LENGTH:
                    code=gx2d_curve_metrics(s,a->id,&ma);if(code!=GX2D_OK)goto result;code=gx2d_curve_metrics(s,b->id,&mb);if(code!=GX2D_OK)goto result;
                    value=ma.length-mb.length;residual=fabs(value);break;
                case GX2D_EQUAL_RADIUS:
                    code=constraint_radius(a,&ra);if(code!=GX2D_OK)goto result;code=constraint_radius(b,&rb);if(code!=GX2D_OK)goto result;
                    value=ra-rb;residual=fabs(value);break;
                case GX2D_CONCENTRIC:
                    code=constraint_center(a,&pa);if(code!=GX2D_OK)goto result;code=constraint_center(b,&pb);if(code!=GX2D_OK)goto result;
                    value=dist(pa,pb);residual=value;break;
                case GX2D_TANGENT:
                    if(c->a_index==GX2D_OBJECT_INDEX&&c->b_index==GX2D_OBJECT_INDEX){
                        const object *line=a->sketch&&(a->sketch->family==GX2D_SKETCH_LINE||a->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE||(a->sketch->family==GX2D_SKETCH_PATH&&a->sketch->control_count==2&&!a->sketch->path_closed))?a:b;const object *circle=line==a?b:a;
                        if(!circle->sketch||circle->sketch->family!=GX2D_SKETCH_CIRCLE){code=GX2D_INVALID;goto result;}
                        code=constraint_segment(line,GX2D_OBJECT_INDEX,&pa,&qa,&da);if(code!=GX2D_OK)goto result;code=constraint_center(circle,&center);if(code!=GX2D_OK)goto result;code=constraint_radius(circle,&ra);if(code!=GX2D_OK)goto result;
                        value=fabs((center.x-pa.x)*da.y-(center.y-pa.y)*da.x);residual=fabs(value-ra);break;
                    }
                    code=curve_authoritative_frame(s,a,c->a_index,&fa);if(code!=GX2D_OK)goto result;
                    code=curve_authoritative_frame(s,b,c->b_index,&fb);if(code!=GX2D_OK)goto result;
                    ra=hypot(fa.derivative.x,fa.derivative.y);rb=hypot(fb.derivative.x,fb.derivative.y);
                    if(ra==0||rb==0){code=GX2D_INVALID;goto result;}
                    angular=fabs(atan2((fa.derivative.x/ra)*(fb.derivative.y/rb)-(fa.derivative.y/ra)*(fb.derivative.x/rb),fabs((fa.derivative.x/ra)*(fb.derivative.x/rb)+(fa.derivative.y/ra)*(fb.derivative.y/rb))));
                    value=dist(fa.point,fb.point);residual=value;break;
                case GX2D_COLLINEAR:
                    code=constraint_segment(a,c->a_index,&pa,&qa,&da);if(code!=GX2D_OK)goto result;code=constraint_segment(b,c->b_index,&pb,&qb,&db);if(code!=GX2D_OK)goto result;
                    angular=fabs(atan2(da.x*db.y-da.y*db.x,fabs(da.x*db.x+da.y*db.y)));
                    value=fabs((pa.x-pb.x)*db.y-(pa.y-pb.y)*db.x);residual=value;break;
                case GX2D_MIDPOINT:
                    code=constraint_segment(b,c->b_index,&pb,&qb,&db);if(code!=GX2D_OK)goto result;
                    center=(gx2d_point){pb.x/2+qb.x/2,pb.y/2+qb.y/2};value=dist(pa,center);residual=value;break;
                case GX2D_POINT_ON_LINE:
                    code=constraint_segment(b,c->b_index,&pb,&qb,&db);if(code!=GX2D_OK)goto result;
                    value=fabs((pa.x-pb.x)*db.y-(pa.y-pb.y)*db.x);residual=value;break;
                case GX2D_POINT_ON_CURVE:
                    code=constraint_curve_distance(s,b,pa,&value);if(code!=GX2D_OK)goto result;residual=value;break;
                case GX2D_SYMMETRY:
                    code=constraint_segment(axis,r->axis_index,&qa,&qb,&da);if(code!=GX2D_OK)goto result;
                    center=(gx2d_point){pa.x/2+pb.x/2,pa.y/2+pb.y/2};
                    value=fmax(fabs((center.x-qa.x)*da.y-(center.y-qa.y)*da.x),fabs((pa.x-pb.x)*da.x+(pa.y-pb.y)*da.y));residual=value;break;
                default:code=GX2D_INVALID;goto result;
            }
    }
    if(!isfinite(value)||!isfinite(residual)||!isfinite(angular))code=GX2D_RANGE;
    else if(residual>c->tolerance||angular>(r->angular_tolerance>0?r->angular_tolerance:1e-9))code=GX2D_CONSTRAINT;
result:
    if(diagnostic)*diagnostic=(gx2d_constraint_diagnostic){code==GX2D_OK,code!=GX2D_INVALID,!r->disabled,value,residual,angular};
    return code;
}
static gx2d_status constraint_prepare(const gx2d_scene *s,const gx2d_constraint_v2 *definition,rule *out) {
    const gx2d_constraint *c;const object *a;rule result;
    if(!s||!definition||!out)return GX2D_INVALID;c=&definition->base;
    if(c->kind<GX2D_FIXED||c->kind>GX2D_CURVATURE||!isfinite(c->value)||!isfinite(c->tolerance)||c->tolerance<=0||
       (definition->disabled!=0&&definition->disabled!=1)||(definition->anchor_valid!=0&&definition->anchor_valid!=1)||
       !isfinite(definition->angular_tolerance)||definition->angular_tolerance<0)return GX2D_INVALID;
    if((c->kind==GX2D_DISTANCE||c->kind==GX2D_RADIUS||c->kind==GX2D_DIAMETER)&&c->value<0)return GX2D_INVALID;
    gx2d_point anchor;a=cobj(s,c->a);if(constraint_point(a,c->a_index,&anchor)!=GX2D_OK)return GX2D_INVALID;
    memset(&result,0,sizeof(result));result.spec=*c;result.axis=definition->axis;result.axis_index=definition->axis_index;
    result.disabled=definition->disabled;result.anchor=definition->anchor_valid?definition->anchor:anchor;
    if(c->kind>GX2D_LOCK_Y)result.presentation.solved=1;
    result.angular_tolerance=definition->angular_tolerance>0?definition->angular_tolerance:1e-9;
    if(!finite2(result.anchor))return GX2D_INVALID;
    /* Disabled records can retain a diagnosed mismatch, but structural shape
     * support/references are always validated before adoption. */
    gx2d_status code=rule_check_extended(s,&result,NULL);if(code!=GX2D_OK&&!(result.disabled&&code==GX2D_CONSTRAINT))return code;
    *out=result;return GX2D_OK;
}
gx2d_status gx2d_constraint_create(gx2d_scene *s,const gx2d_constraint_v2 *definition,gx2d_id *out) {
    rule prepared,*next;gx2d_status code;if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    code=constraint_prepare(s,definition,&prepared);if(code!=GX2D_OK)return code;
    if(s->next_id==UINT64_MAX||s->rule_count==SIZE_MAX/sizeof(*next))return GX2D_RANGE;
    next=(rule *)realloc(s->rules,(s->rule_count+1)*sizeof(*next));if(!next)return GX2D_NOMEM;
    s->rules=next;prepared.id=fresh(s);s->rules[s->rule_count++]=prepared;*out=prepared.id;return GX2D_OK;
}
gx2d_status gx2d_constraint_get(const gx2d_scene *s,gx2d_id id,gx2d_constraint_v2 *out) {
    size_t i;if(!s||!out||!id)return GX2D_INVALID;for(i=0;i<s->rule_count;++i)if(s->rules[i].id==id){const rule *r=&s->rules[i];
        *out=(gx2d_constraint_v2){r->spec,r->axis,r->axis_index,r->disabled,1,r->anchor,r->angular_tolerance>0?r->angular_tolerance:1e-9};return GX2D_OK;}
    return GX2D_NOT_FOUND;
}
gx2d_status gx2d_constraint_ids(const gx2d_scene *s,gx2d_id *out,size_t capacity,size_t *count) {
    size_t i;if(!s||!count)return GX2D_INVALID;*count=s->rule_count;if(!out)return GX2D_OK;if(capacity<s->rule_count)return GX2D_RANGE;
    for(i=0;i<s->rule_count;++i)out[i]=s->rules[i].id;return GX2D_OK;
}
gx2d_status gx2d_constraint_update(gx2d_scene *s,gx2d_id id,const gx2d_constraint_v2 *definition) {
    size_t i;rule prepared;gx2d_status code;gx2d_constraint_v2 copy;
    if(!s||!definition)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->rule_count;++i)if(s->rules[i].id==id)break;if(i==s->rule_count)return GX2D_NOT_FOUND;
    if(s->rules[i].presentation.solved){gx2d_relationship_state state=s->rules[i].presentation;gx2d_id out;gx2d_status result=gx2d_constraint_apply(s,id,definition,&out);if(result==GX2D_OK)s->rules[i].presentation=state;return result;}
    copy=*definition;if(!copy.anchor_valid&&copy.base.kind==GX2D_FIXED){copy.anchor_valid=1;copy.anchor=s->rules[i].anchor;}
    code=constraint_prepare(s,&copy,&prepared);if(code!=GX2D_OK)return code;prepared.id=id;s->rules[i]=prepared;return GX2D_OK;
}
gx2d_status gx2d_constraint_enable(gx2d_scene *s,gx2d_id id,int enabled) {
    size_t i;rule candidate;gx2d_status code;if(!s||(enabled!=0&&enabled!=1))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->rule_count;++i)if(s->rules[i].id==id)break;if(i==s->rule_count)return GX2D_NOT_FOUND;
    candidate=s->rules[i];candidate.disabled=!enabled;
    if(enabled&&candidate.presentation.solved){gx2d_constraint_v2 d;gx2d_id out;gx2d_constraint_get(s,id,&d);d.disabled=0;gx2d_status solved=gx2d_constraint_apply(s,id,&d,&out);if(solved==GX2D_OK)s->rules[i].presentation=candidate.presentation;return solved;}
    if(enabled){code=rule_check_extended(s,&candidate,NULL);if(code!=GX2D_OK)return code;}
    s->rules[i]=candidate;return GX2D_OK;
}
gx2d_status gx2d_constraint_validate(const gx2d_scene *s,gx2d_id id,gx2d_constraint_diagnostic *out) {
    size_t i;gx2d_constraint_diagnostic result;if(!s||!out)return GX2D_INVALID;
    for(i=0;i<s->rule_count;++i)if(s->rules[i].id==id){rule_check_extended(s,&s->rules[i],&result);*out=result;return GX2D_OK;}
    return GX2D_NOT_FOUND;
}

gx2d_status gx2d_join_points(gx2d_scene *s,gx2d_id a_id,size_t a_index,gx2d_id b_id,size_t b_index,int merge,double tolerance,gx2d_id *out) {
    object *a;const object *b;object before;gx2d_point target,*points=NULL;gx2d_sketch_definition *definition=NULL;
    gx2d_constraint_v2 relationship;gx2d_id id;gx2d_status code;size_t controls_index,count;
    if(!s||!out||(merge!=0&&merge!=1)||!isfinite(tolerance)||tolerance<=0)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    a=obj(s,a_id);b=cobj(s,b_id);if(!a||!b||a->kind==GX2D_GROUP||b->kind==GX2D_GROUP||a_index>=a->count||b_index>=b->count||(a_id==b_id&&a_index==b_index))return GX2D_INVALID;
    target=b->points[b_index];before=*a;memset(&relationship,0,sizeof(relationship));relationship.base=(gx2d_constraint){GX2D_COINCIDENT,a_id,b_id,a_index,b_index,0,tolerance};
    if(!merge)return gx2d_constraint_create(s,&relationship,out);
    if(!can_move(s,a))return GX2D_LOCKED;
    if(a->sketch){gx2d_sketch_family family=a->sketch->family;long double determinant,dx,dy,x,y;
        if(family==GX2D_SKETCH_POINT)controls_index=0;
        else if(family==GX2D_SKETCH_LINE||family==GX2D_SKETCH_CONSTRUCTION_LINE)controls_index=a_index;
        else if(family==GX2D_SKETCH_PATH&&a_index<a->sketch->control_count)controls_index=a_index;
        else if((family==GX2D_SKETCH_POLYLINE||family==GX2D_SKETCH_SPLINE||family==GX2D_SKETCH_QUADRATIC_BEZIER||family==GX2D_SKETCH_CUBIC_BEZIER)&&(a_index==0||a_index==a->count-1))controls_index=a_index==0?0:a->sketch->control_count-1;
        else return GX2D_INVALID;
        definition=sketch_clone(a->sketch);if(!definition)return GX2D_NOMEM;
        determinant=(long double)definition->matrix[0]*definition->matrix[3]-(long double)definition->matrix[1]*definition->matrix[2];
        if(determinant==0){code=GX2D_INVALID;goto failed;}
        dx=(long double)target.x-definition->matrix[4];dy=(long double)target.y-definition->matrix[5];
        x=(definition->matrix[3]*dx-definition->matrix[1]*dy)/determinant;y=(definition->matrix[0]*dy-definition->matrix[2]*dx)/determinant;
        ((gx2d_point *)definition->controls)[controls_index]=(gx2d_point){(double)x,(double)y};
        code=sketch_display(definition,a->count,&points,&count);if(code!=GX2D_OK)goto failed;if(count!=a->count){code=GX2D_INVALID;goto failed;}
    } else {points=(gx2d_point *)malloc(a->count*sizeof(*points));if(!points)return GX2D_NOMEM;memcpy(points,a->points,a->count*sizeof(*points));points[a_index]=target;}
    a->points=points;if(definition)a->sketch=definition;
    code=gx2d_check_constraints(s);if(code==GX2D_OK)code=gx2d_constraint_create(s,&relationship,&id);
    if(code!=GX2D_OK){*a=before;goto failed;}
    a->capacity=a->count;free(before.points);if(definition)sketch_free(before.sketch);*out=id;return GX2D_OK;
failed:free(points);sketch_free(definition);return code;
}
