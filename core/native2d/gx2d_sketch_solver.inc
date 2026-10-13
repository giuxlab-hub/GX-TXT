/* SPDX-License-Identifier: GPL-3.0-or-later
 * Local retained-sketch solve. Candidate definitions are deep copies of the
 * existing objects; only a converged, validated component is adopted. Display
 * samples never enter equations. Limits bound interactive memory/work. */
#ifdef GX2D_SOLVER_TRACE
#include <stdio.h>
#define SK_TRACE(...) fprintf(stderr,__VA_ARGS__)
#else
#define SK_TRACE(...) ((void)0)
#endif
#define SK_PARAMS 1024
#define SK_ROWS 4096
#define SK_OBJECTS 256
static rule *sk_rule(gx2d_scene *s,gx2d_id id){size_t i;for(i=0;i<s->rule_count;i++)if(s->rules[i].id==id)return &s->rules[i];return NULL;}
static int sketch_has_solver(const gx2d_scene *s,gx2d_id id){size_t i;for(i=0;i<s->rule_count;i++){const rule *r=&s->rules[i];if(r->presentation.solved&&!r->disabled&&(r->spec.a==id||r->spec.b==id||r->axis==id))return 1;}return 0;}
static gx2d_point sk_sub(gx2d_point a,gx2d_point b){return (gx2d_point){a.x-b.x,a.y-b.y};}
static double sk_cross(gx2d_point a,gx2d_point b){return a.x*b.y-a.y*b.x;}
static double sk_dot(gx2d_point a,gx2d_point b){return a.x*b.x+a.y*b.y;}
static int sk_round(const object *o){double r;return constraint_radius(o,&r)==GX2D_OK;}
static int sk_endpoint(const object *o,size_t ix,double *t){
    if(!o||!o->sketch)return 0;
    gx2d_sketch_family f=o->sketch->family;
    if(f==GX2D_SKETCH_PATH&&o->sketch->path_closed)return 0;
    if(f==GX2D_SKETCH_ARC){if(ix==GX2D_CONTROL_INDEX+1){*t=0;return 1;}if(ix==GX2D_CONTROL_INDEX+2){*t=1;return 1;}return 0;}
    if(ix==GX2D_CONTROL_INDEX){*t=0;return 1;}if(ix==GX2D_CONTROL_INDEX+o->sketch->control_count-1){*t=1;return 1;}return 0;
}
/* Exact second derivative for supported endpoint jets. Catmull-Rom's endpoints
 * reuse the existing exact cubic-piece authority. */
static int sk_jet(const object *o,size_t ix,gx2d_point *p,gx2d_point *d,double *k){
    double t;gx2d_point dd={0,0};const gx2d_sketch_definition *s=o?o->sketch:NULL;
    if(!s||!sk_endpoint(o,ix,&t)||gx2d_sketch_evaluate(s,t,p,d)!=GX2D_OK)return 0;
    if(s->family==GX2D_SKETCH_QUADRATIC_BEZIER){dd=(gx2d_point){2*(s->controls[2].x-2*s->controls[1].x+s->controls[0].x),2*(s->controls[2].y-2*s->controls[1].y+s->controls[0].y)};dd=sketch_world(s,dd,1);}
    else if(s->family==GX2D_SKETCH_CUBIC_BEZIER){int i=t==0?0:1;dd=(gx2d_point){6*(s->controls[i+2].x-2*s->controls[i+1].x+s->controls[i].x),6*(s->controls[i+2].y-2*s->controls[i+1].y+s->controls[i].y)};dd=sketch_world(s,dd,1);}
    else if(s->family==GX2D_SKETCH_SPLINE){gx2d_point b[4];size_t piece=t==0?0:s->control_count-2;sketch_spline_controls(s,piece,b);int i=t==0?0:1;double n=(double)(s->control_count-1);dd=(gx2d_point){6*n*n*(b[i+2].x-2*b[i+1].x+b[i].x),6*n*n*(b[i+2].y-2*b[i+1].y+b[i].y)};dd=sketch_world(s,dd,1);}
    else if(s->family==GX2D_SKETCH_ARC){gx2d_point center=sketch_world(s,s->controls[0],0);dd=(gx2d_point){-(p->x-center.x)*s->angle_sweep*s->angle_sweep,-(p->y-center.y)*s->angle_sweep*s->angle_sweep};}
    else if(!interaction_is_line(o)&&!(s->family==GX2D_SKETCH_PATH&&!s->path_closed))return 0;
    double len=hypot(d->x,d->y);if(len<1e-12)return 0;*k=sk_cross(*d,dd)/(len*len*len);return isfinite(*k);
}
static int sk_arc_contains(const object *o,gx2d_point p){
    if(!o||!o->sketch||o->sketch->family!=GX2D_SKETCH_ARC)return 1;
    gx2d_point q;if(interaction_inverse(o->sketch,p,&q)!=GX2D_OK)return 0;
    double a=atan2(q.y-o->sketch->controls[0].y,q.x-o->sketch->controls[0].x),start=o->sketch->angle_start,span=o->sketch->angle_sweep;
    double delta=fmod((span>0?a-start:start-a)+8*acos(-1),2*acos(-1));return delta<=fabs(span)+1e-12;
}
static double sk_arc_violation(const object *o,gx2d_point p){
    if(sk_arc_contains(o,p))return 0;
    gx2d_point q;double radius;if(interaction_inverse(o->sketch,p,&q)!=GX2D_OK||constraint_radius(o,&radius)!=GX2D_OK)return DBL_MAX;
    double angle=atan2(q.y-o->sketch->controls[0].y,q.x-o->sketch->controls[0].x);
    double first=angle-o->sketch->angle_start,last=first-o->sketch->angle_sweep;
    return radius*fmin(fabs(atan2(sin(first),cos(first))),fabs(atan2(sin(last),cos(last))));
}
/* Closest parameter on the mathematical retained curve, never its render cache.
 * Bracket all stationary minima on a bounded grid, then refine evaluations.
 * The evaluated witness is exact; this numerical search has explicit tolerance. */
static int sk_nearest(const object *o,gx2d_point p,gx2d_point *q){
    if(!o||!o->sketch)return 0;double best=DBL_MAX;gx2d_point v;
    for(int i=0;i<=32;i++){
        double lo=fmax(0,(i-1)/32.0),hi=fmin(1,(i+1)/32.0);
        for(int j=0;j<60;j++){double u=lo+(hi-lo)/3,w=hi-(hi-lo)/3;gx2d_point a,b;if(gx2d_sketch_evaluate(o->sketch,u,&a,NULL)!=GX2D_OK||gx2d_sketch_evaluate(o->sketch,w,&b,NULL)!=GX2D_OK)return 0;if(dist(p,a)<dist(p,b))hi=w;else lo=u;}
        gx2d_sketch_evaluate(o->sketch,(lo+hi)/2,&v,NULL);double d=dist(p,v);if(d<best){best=d;*q=v;}
    }
    for(int i=0;i<2;i++){gx2d_sketch_evaluate(o->sketch,i,&v,NULL);double d=dist(p,v);if(d<best){best=d;*q=v;}}
    return isfinite(best);
}
static gx2d_status sk_equations(const gx2d_scene *s,const rule *r,double *v,size_t *count,double *measured){
    rule local=*r;gx2d_constraint *c=&local.spec;
    const object *a=cobj(s,c->a),*b=cobj(s,c->b),*axis=cobj(s,r->axis);
    object la,lb,laxis;gx2d_sketch_definition da_leaf,db_leaf,axis_leaf;
    int na=network_leaf(a,&c->a_index,&la,&da_leaf,NULL),nb=network_leaf(b,&c->b_index,&lb,&db_leaf,NULL),nx=network_leaf(axis,&local.axis_index,&laxis,&axis_leaf,NULL);
    if(na<0||nb<0||nx<0)return GX2D_INVALID;if(na)a=&la;if(nb)b=&lb;if(nx)axis=&laxis;r=&local;
    gx2d_point p,q,u,w,da,db,ca,cb;double ra=0,rb=0,k1,k2,t1,t2;size_t n=0;
    if(!a||constraint_point(a,c->a_index,&p)!=GX2D_OK)return GX2D_INVALID;
    if(b&&constraint_point(b,c->b_index,&q)!=GX2D_OK)return GX2D_INVALID;
#define E(x) do {if(n>=32)return GX2D_RANGE;v[n++]=(x);}while(0)
#define LINE(o,ix,pa,pb,di) if(constraint_segment(o,ix,&pa,&pb,&di)!=GX2D_OK)return GX2D_INVALID
#define ROUND(o,center,radius) if(constraint_center(o,&center)!=GX2D_OK||constraint_radius(o,&radius)!=GX2D_OK)return GX2D_INVALID
    double value=0;
    switch(c->kind){
    case GX2D_FIXED:E(p.x-r->anchor.x);E(p.y-r->anchor.y);break;
    case GX2D_LOCK_X:value=p.x;E(value-c->value);break;
    case GX2D_LOCK_Y:value=p.y;E(value-c->value);break;
    case GX2D_DISTANCE:value=dist(p,q);E(value-c->value);break;
    case GX2D_HORIZONTAL_DISTANCE:value=fabs(q.x-p.x);E(value-c->value);break;
    case GX2D_VERTICAL_DISTANCE:value=fabs(q.y-p.y);E(value-c->value);break;
    case GX2D_COINCIDENT:E(p.x-q.x);E(p.y-q.y);break;
    case GX2D_RADIUS:case GX2D_DIAMETER:ROUND(a,ca,ra);value=ra*(c->kind==GX2D_DIAMETER?2:1);E(value-c->value);break;
    case GX2D_CONCENTRIC:if(constraint_center(a,&p)!=GX2D_OK||constraint_center(b,&q)!=GX2D_OK)return GX2D_INVALID;E(p.x-q.x);E(p.y-q.y);break;
    case GX2D_EQUAL_RADIUS:ROUND(a,ca,ra);ROUND(b,cb,rb);E(ra-rb);break;
    case GX2D_HORIZONTAL:case GX2D_VERTICAL:
        if(c->b){E(c->kind==GX2D_HORIZONTAL?p.y-q.y:p.x-q.x);}else {LINE(a,c->a_index,p,u,da);E(c->kind==GX2D_HORIZONTAL?da.y:da.x);}break;
    case GX2D_AXIS_ANGLE:LINE(a,c->a_index,p,u,da);value=atan2(da.y,da.x);E(atan2(sin(value-c->value),cos(value-c->value)));break;
    case GX2D_ANGLE:case GX2D_PARALLEL:case GX2D_PERPENDICULAR:case GX2D_COLLINEAR:case GX2D_EQUAL_LENGTH:case GX2D_LINE_DISTANCE:
        LINE(a,c->a_index,p,u,da);LINE(b,c->b_index,q,w,db);
        value=atan2(sk_cross(da,db),sk_dot(da,db));
        if(c->kind==GX2D_ANGLE)E(atan2(sin(value-c->value),cos(value-c->value)));
        else if(c->kind==GX2D_PERPENDICULAR)E(sk_dot(da,db));
        else if(c->kind==GX2D_EQUAL_LENGTH)E(dist(p,u)-dist(q,w));
        else {E(sk_cross(da,db));if(c->kind==GX2D_COLLINEAR)E(sk_cross(sk_sub(p,q),db));if(c->kind==GX2D_LINE_DISTANCE){value=fabs(sk_cross(sk_sub(p,q),db));E(value-c->value);}}
        break;
    case GX2D_MIDPOINT:LINE(b,c->b_index,q,w,db);E(p.x-(q.x+w.x)/2);E(p.y-(q.y+w.y)/2);break;
    case GX2D_POINT_ON_LINE:case GX2D_POINT_LINE_DISTANCE:LINE(b,c->b_index,q,w,db);value=sk_cross(sk_sub(p,q),db);if(c->kind==GX2D_POINT_LINE_DISTANCE)value=fabs(value);E(value-(c->kind==GX2D_POINT_LINE_DISTANCE?c->value:0));break;
    case GX2D_POINT_ON_CURVE:
        if(sk_round(b)){ROUND(b,cb,rb);value=dist(p,cb);E(value-rb);if(b->sketch->family==GX2D_SKETCH_ARC)E(sk_arc_violation(b,p));}
        else {if(b&& !b->sketch){gx2d_segment_hit hit;if(gx2d_nearest_segment(s,b->id,p,&hit)!=GX2D_OK)return GX2D_INVALID;q=hit.point;}else if(!sk_nearest(b,p,&q))return GX2D_INVALID;E(p.x-q.x);E(p.y-q.y);}break;
    case GX2D_SYMMETRY:
        LINE(axis,r->axis_index,ca,cb,da);
        if(c->a_index==GX2D_OBJECT_INDEX&&c->b_index==GX2D_OBJECT_INDEX){
            if(!a->sketch||!b->sketch||a->sketch->family!=b->sketch->family||a->sketch->control_count!=b->sketch->control_count||a->sketch->control_count>12)return GX2D_INVALID;
            for(size_t i=0;i<a->sketch->control_count;i++){p=sketch_world(a->sketch,a->sketch->controls[i],0);q=sketch_world(b->sketch,b->sketch->controls[i],0);double along=sk_dot(sk_sub(q,ca),da);E(p.x-(2*(ca.x+along*da.x)-q.x));E(p.y-(2*(ca.y+along*da.y)-q.y));}
            if(sk_round(a)){constraint_radius(a,&ra);constraint_radius(b,&rb);E(ra-rb);}
        }else {gx2d_point mid={(p.x+q.x)/2,(p.y+q.y)/2};E(sk_cross(sk_sub(mid,ca),da));E(sk_dot(sk_sub(p,q),da));}break;
    case GX2D_TANGENT:case GX2D_CURVATURE:
        if(c->kind==GX2D_TANGENT&&((c->a_index>=GX2D_SEGMENT_INDEX&&c->a_index<GX2D_OBJECT_INDEX&&c->b_index==GX2D_OBJECT_INDEX)||(c->b_index>=GX2D_SEGMENT_INDEX&&c->b_index<GX2D_OBJECT_INDEX&&c->a_index==GX2D_OBJECT_INDEX))) {
            const object *line=c->a_index==GX2D_OBJECT_INDEX?b:a,*round=line==a?b:a;
            size_t ix=line==a?c->a_index:c->b_index;
            LINE(line,ix,p,u,da);ROUND(round,ca,ra);
            value=sk_cross(sk_sub(ca,p),da);E(value-(r->presentation.branch<0?-ra:ra));
            double along=sk_dot(sk_sub(ca,p),da);q=(gx2d_point){p.x+along*da.x,p.y+along*da.y};
            if(line->sketch->family!=GX2D_SKETCH_CONSTRUCTION_LINE){double len=dist(p,u);E(along<0?along:along>len?along-len:0);}
            if(round->sketch->family==GX2D_SKETCH_ARC)E(sk_arc_violation(round,q));break;
        }
        if((c->a_index==GX2D_OBJECT_INDEX&&c->b_index!=GX2D_OBJECT_INDEX)||(c->a_index!=GX2D_OBJECT_INDEX&&c->b_index==GX2D_OBJECT_INDEX)){
            const object *curve=c->a_index!=GX2D_OBJECT_INDEX?a:b,*round=curve==a?b:a;size_t ix=curve==a?c->a_index:c->b_index;
            if(!sk_jet(curve,ix,&p,&da,&k1))return GX2D_INVALID;ROUND(round,ca,ra);db=sk_sub(p,ca);rb=hypot(da.x,da.y);
            E(dist(p,ca)-ra);E(sk_dot(da,db)/(rb*ra));
            if(c->kind==GX2D_CURVATURE)E(k1-(sk_cross(db,da)<0?-1:1)/ra);
            if(round->sketch->family==GX2D_SKETCH_ARC)E(sk_arc_violation(round,p));break;
        }
        if(c->a_index!=GX2D_OBJECT_INDEX&&c->b_index!=GX2D_OBJECT_INDEX){
            if(!sk_jet(a,c->a_index,&p,&da,&k1)||!sk_jet(b,c->b_index,&q,&db,&k2)||!sk_endpoint(a,c->a_index,&t1)||!sk_endpoint(b,c->b_index,&t2))return GX2D_INVALID;
            E(p.x-q.x);E(p.y-q.y);ra=hypot(da.x,da.y);rb=hypot(db.x,db.y);E(sk_cross(da,db)/(ra*rb));
            /* Tangents point along parameter direction; curvature orientation
             * follows that direction, reversing when aligned jets oppose. */
            if(c->kind==GX2D_CURVATURE)E(k1-(sk_dot(da,db)<0?-k2:k2));break;
        }
        if(c->kind==GX2D_CURVATURE)return GX2D_INVALID;
        if(sk_round(a)&&sk_round(b)){
            ROUND(a,ca,ra);ROUND(b,cb,rb);double len=dist(ca,cb);if(len<1e-12)return GX2D_INVALID;
            int inside=r->presentation.branch==2;E(len-(inside?fabs(ra-rb):ra+rb));
            double sign=inside&&ra<rb?-1:1;gx2d_point contact={ca.x+sign*ra*(cb.x-ca.x)/len,ca.y+sign*ra*(cb.y-ca.y)/len};
            if(a->sketch->family==GX2D_SKETCH_ARC)E(sk_arc_violation(a,contact));if(b->sketch->family==GX2D_SKETCH_ARC)E(sk_arc_violation(b,contact));
        }else {
            const object *line=interaction_is_line(a)?a:b,*round=line==a?b:a;
            LINE(line,GX2D_SEGMENT_INDEX,p,u,da);ROUND(round,ca,ra);
            value=sk_cross(sk_sub(ca,p),da);E(value-(r->presentation.branch<0?-ra:ra));
            double along=sk_dot(sk_sub(ca,p),da);q=(gx2d_point){p.x+along*da.x,p.y+along*da.y};
            if(line->sketch->family!=GX2D_SKETCH_CONSTRUCTION_LINE){double len=dist(p,u);E(along<0?along:along>len?along-len:0);}
            if(round->sketch->family==GX2D_SKETCH_ARC)E(sk_arc_violation(round,q));
        }break;
    default:return GX2D_INVALID;
    }
    for(size_t i=0;i<n;i++)if(!isfinite(v[i]))return GX2D_RANGE;
    *count=n;if(measured)*measured=value;return GX2D_OK;
#undef E
#undef LINE
#undef ROUND
}
static gx2d_status sketch_rule_check(const gx2d_scene *s,const rule *r,gx2d_constraint_diagnostic *d){
    double v[32],value=0,residual=0,angular=0;size_t n=0;gx2d_status code=sk_equations(s,r,v,&n,&value);int invalid=0;
    int kind=r->spec.kind;double angular_tol=r->angular_tolerance>0?r->angular_tolerance:1e-9;
    for(size_t i=0;i<n;i++){
        int angle=(kind==GX2D_ANGLE||kind==GX2D_AXIS_ANGLE||kind==GX2D_PARALLEL||kind==GX2D_PERPENDICULAR||((kind==GX2D_HORIZONTAL||kind==GX2D_VERTICAL)&&!r->spec.b)||((kind==GX2D_COLLINEAR||kind==GX2D_LINE_DISTANCE)&&i==0));
        int mixed=((r->spec.a_index==GX2D_OBJECT_INDEX)&&(r->spec.b_index>=GX2D_CONTROL_INDEX&&r->spec.b_index<GX2D_SEGMENT_INDEX))||((r->spec.b_index==GX2D_OBJECT_INDEX)&&(r->spec.a_index>=GX2D_CONTROL_INDEX&&r->spec.a_index<GX2D_SEGMENT_INDEX));
        int endpoint=r->spec.a_index!=GX2D_OBJECT_INDEX&&r->spec.b_index!=GX2D_OBJECT_INDEX;
        if((kind==GX2D_TANGENT||kind==GX2D_CURVATURE)&&((endpoint&&i==2)||(mixed&&i==1)))angle=1;
        int curvature=kind==GX2D_CURVATURE&&((endpoint&&i==3)||(mixed&&i==2));
        double tolerance=curvature?(r->presentation.curvature_tolerance>0?r->presentation.curvature_tolerance:1e-8):angle?angular_tol:r->spec.tolerance;
        if(angle)angular=fmax(angular,fabs(v[i]));else residual=fmax(residual,fabs(v[i]));
        if(fabs(v[i])>tolerance)invalid=1;
    }
    if(code==GX2D_OK&&invalid&&!r->presentation.driven)code=GX2D_CONSTRAINT;
    if(d)*d=(gx2d_constraint_diagnostic){code==GX2D_OK,code!=GX2D_INVALID,!r->disabled,value,residual,angular};return r->presentation.driven&&code==GX2D_CONSTRAINT?GX2D_OK:code;
}
typedef struct {object before[SK_OBJECTS];size_t indices[SK_OBJECTS],objects;double *parameters[SK_PARAMS],initial[SK_PARAMS];size_t n;gx2d_scene *scene;gx2d_reference target;gx2d_point point;int has_target;} sk_transaction;
static int sk_member(const sk_transaction *t,gx2d_id id){for(size_t i=0;i<t->objects;i++)if(t->before[i].id==id)return 1;return 0;}
static void sk_finish(sk_transaction *t,int commit){
    for(size_t i=0;i<t->objects;i++){object *o=&t->scene->objects[t->indices[i]];if(commit){free(t->before[i].points);sketch_free(t->before[i].sketch);}else {free(o->points);sketch_free(o->sketch);*o=t->before[i];}}
}
gx2d_status gx2d_sketch_component_ids(const gx2d_scene *s,gx2d_id seed,gx2d_id *out,size_t capacity,size_t *count){
    if(!s||!count||!cobj(s,seed))return GX2D_INVALID;gx2d_id ids[SK_OBJECTS]={seed};size_t n=1;
    for(size_t j=0;j<n;j++)for(size_t k=0;k<s->rule_count;k++){
        const rule *r=&s->rules[k];if(r->disabled||r->presentation.driven)continue;
        if(r->spec.a!=ids[j]&&r->spec.b!=ids[j]&&r->axis!=ids[j])continue;
        gx2d_id related[3]={r->spec.a,r->spec.b,r->axis};for(int z=0;z<3;z++){gx2d_id id=related[z];if(!id)continue;size_t i;for(i=0;i<n;i++)if(ids[i]==id)break;if(i==n){if(n==SK_OBJECTS)return GX2D_RANGE;ids[n++]=id;}}
    }
    *count=n;if(out){if(capacity<n)return GX2D_RANGE;memcpy(out,ids,n*sizeof(*ids));}return GX2D_OK;
}
static gx2d_status sk_begin(gx2d_scene *s,gx2d_id seed,sk_transaction *t){
    memset(t,0,sizeof(*t));t->scene=s;gx2d_id ids[SK_OBJECTS]={seed};size_t count=1;
    gx2d_status component=gx2d_sketch_component_ids(s,seed,ids,SK_OBJECTS,&count);if(component!=GX2D_OK)return component;
    for(size_t j=0;j<count;j++){
        object *o=obj(s,ids[j]);if(!o||!o->sketch)continue;
        object copy=*o;copy.points=malloc(o->count*sizeof(*copy.points));copy.sketch=sketch_clone(o->sketch);
        if(!copy.points||!copy.sketch){free(copy.points);sketch_free(copy.sketch);sk_finish(t,0);return GX2D_NOMEM;}memcpy(copy.points,o->points,o->count*sizeof(*copy.points));
        t->indices[t->objects]=(size_t)(o-s->objects);t->before[t->objects++]=*o;*o=copy;
        if(!can_move(s,o)||o->reference_image)continue; /* Raster pixel/control topology is immutable; other geometry can solve against it. */
        size_t leaves=sketch_is_composition(o->sketch)?o->sketch->part_count:1;
        for(size_t leaf=0;leaf<leaves;leaf++){
            gx2d_sketch_definition *definition=sketch_is_composition(o->sketch)?(gx2d_sketch_definition *)&o->sketch->parts[leaf]:o->sketch;
        size_t needed=2*definition->control_count+5;for(size_t i=0;i<definition->tangent_count;i++){unsigned flags=definition->tangents[i].flags;if(flags&1)needed+=2;if(flags&2)needed+=2;}if(t->n+needed>SK_PARAMS){sk_finish(t,0);return GX2D_RANGE;}
        for(size_t i=0;i<definition->control_count;i++){gx2d_point *p=(gx2d_point *)&definition->controls[i];t->parameters[t->n++]=&p->x;t->parameters[t->n++]=&p->y;}
        for(size_t i=0;i<definition->tangent_count;i++) {
            gx2d_spline_tangent *arm=(gx2d_spline_tangent *)&definition->tangents[i];
            if(arm->flags&1){t->parameters[t->n++]=&arm->incoming.x;t->parameters[t->n++]=&arm->incoming.y;}
            if(arm->flags&2){t->parameters[t->n++]=&arm->outgoing.x;t->parameters[t->n++]=&arm->outgoing.y;}
        }
        gx2d_sketch_family f=definition->family;if(f==GX2D_SKETCH_CIRCLE||f==GX2D_SKETCH_ARC||f==GX2D_SKETCH_ELLIPSE)t->parameters[t->n++]=&definition->radius_x;
        if(f==GX2D_SKETCH_RECTANGLE)t->parameters[t->n++]=&definition->rotation;
        if(f==GX2D_SKETCH_ELLIPSE){t->parameters[t->n++]=&definition->radius_y;t->parameters[t->n++]=&definition->rotation;}
        if(f==GX2D_SKETCH_ARC){t->parameters[t->n++]=&definition->angle_start;t->parameters[t->n++]=&definition->angle_sweep;}
        }
    }
    for(size_t j=0;j<t->n;j++)t->initial[j]=*t->parameters[j];return GX2D_OK;
}
static gx2d_status sk_residual(sk_transaction *t,double *v,size_t *count){
    size_t n=0;
    for(size_t i=0;i<t->objects;i++){
        object *o=&t->scene->objects[t->indices[i]];const gx2d_sketch_definition *d=o->sketch;
        if(!sketch_is_composition(d)){if(gx2d_sketch_validate(d)!=GX2D_OK)return GX2D_INVALID;continue;}
        /* Topology is an equation during iteration, a strict invariant at commit. */
        for(size_t k=0;k<d->part_count;k++)if(gx2d_sketch_validate(&d->parts[k])!=GX2D_OK)return GX2D_INVALID;
        if(d->node_count){for(size_t k=0;k<d->node_count;k++)if(d->nodes[k]!=k){gx2d_point a,b;if(n+2>SK_ROWS)return GX2D_RANGE;control_point(o,k,&a,NULL);control_point(o,d->nodes[k],&b,NULL);v[n++]=a.x-b.x;v[n++]=a.y-b.y;}}
        else if(d->family==GX2D_SKETCH_COMPOSITE_PATH){for(size_t k=1;k<d->part_count;k++){gx2d_point a,b;if(n+2>SK_ROWS)return GX2D_RANGE;sketch_evaluate_valid(&d->parts[k-1],!d->part_reversed[k-1],&a,NULL);sketch_evaluate_valid(&d->parts[k],d->part_reversed[k],&b,NULL);v[n++]=a.x-b.x;v[n++]=a.y-b.y;}}
    }
    for(size_t i=0;i<t->scene->rule_count;i++){rule *r=&t->scene->rules[i];if(r->disabled||r->presentation.driven||!sk_member(t,r->spec.a))continue;
        if(!r->presentation.solved)continue;size_t m=0;if(n+32>SK_ROWS)return GX2D_RANGE;
        gx2d_status code=sk_equations(t->scene,r,v+n,&m,NULL);if(code!=GX2D_OK)return code;n+=m;
    }
    if(t->has_target){gx2d_point p;gx2d_status code=gx2d_reference_resolve(t->scene,&t->target,&p);if(code!=GX2D_OK)return code;v[n++]=p.x-t->point.x;v[n++]=p.y-t->point.y;}
    *count=n;return GX2D_OK;
}
static double sk_norm(const double *v,size_t n){double value=0;for(size_t i=0;i<n;i++)value+=v[i]*v[i];return value;}
static int sk_linear(double *a,double *b,size_t n){
    for(size_t k=0;k<n;k++){size_t pivot=k;for(size_t i=k+1;i<n;i++)if(fabs(a[i*n+k])>fabs(a[pivot*n+k]))pivot=i;if(fabs(a[pivot*n+k])<1e-18)return 0;
        if(pivot!=k){for(size_t j=k;j<n;j++){double x=a[k*n+j];a[k*n+j]=a[pivot*n+j];a[pivot*n+j]=x;}double x=b[k];b[k]=b[pivot];b[pivot]=x;}
        for(size_t i=k+1;i<n;i++){double f=a[i*n+k]/a[k*n+k];for(size_t j=k+1;j<n;j++)a[i*n+j]-=f*a[k*n+j];b[i]-=f*b[k];}
    }for(size_t i=n;i-->0;){for(size_t j=i+1;j<n;j++)b[i]-=a[i*n+j]*b[j];b[i]/=a[i*n+i];}return 1;
}
static gx2d_status sk_jacobian(sk_transaction *t,const double *v,size_t rows,double *j){
    double trial[SK_ROWS];size_t n;for(size_t k=0;k<t->n;k++){
        double old=*t->parameters[k],h=1e-6*fmax(1,fabs(old));*t->parameters[k]=old+h;gx2d_status code=sk_residual(t,trial,&n);*t->parameters[k]=old;
        if(code!=GX2D_OK){h=-h;*t->parameters[k]=old+h;code=sk_residual(t,trial,&n);*t->parameters[k]=old;}
        if(code!=GX2D_OK||n!=rows)return code==GX2D_OK?GX2D_INVALID:code;
        for(size_t i=0;i<rows;i++)j[i*t->n+k]=(trial[i]-v[i])/h;
    }return GX2D_OK;
}
static size_t sk_rank(double *j,size_t rows,size_t cols){
    size_t rank=0;for(size_t k=0;k<cols&&rank<rows;k++){size_t pivot=rank;for(size_t i=rank+1;i<rows;i++)if(fabs(j[i*cols+k])>fabs(j[pivot*cols+k]))pivot=i;
        if(fabs(j[pivot*cols+k])<1e-5)continue;
        for(size_t z=k;z<cols;z++){double x=j[rank*cols+z];j[rank*cols+z]=j[pivot*cols+z];j[pivot*cols+z]=x;}
        for(size_t i=rank+1;i<rows;i++){double f=j[i*cols+k]/j[rank*cols+k];for(size_t z=k;z<cols;z++)j[i*cols+z]-=f*j[rank*cols+z];}rank++;
    }return rank;
}
static gx2d_status sk_solve(sk_transaction *t){
    double goal=1e-9;for(size_t i=0;i<t->scene->rule_count;i++){const rule *r=&t->scene->rules[i];if(!r->disabled&&!r->presentation.driven&&sk_member(t,r->spec.a))goal=fmin(goal,r->spec.tolerance*.1);}
    double v[SK_ROWS],trial[SK_ROWS],old[SK_PARAMS];size_t rows=0,n=t->n,rr;double lambda=1e-6;gx2d_status code=sk_residual(t,v,&rows);if(code!=GX2D_OK)return code;
    SK_TRACE("solve n=%zu rows=%zu norm=%.12g\n",n,rows,sk_norm(v,rows));
    if(sk_norm(v,rows)<goal*goal)return GX2D_OK;if(n==0)return GX2D_CONSTRAINT;
    double *j=calloc(SK_ROWS*n,sizeof(double)),*a=calloc(n*n,sizeof(double)),*b=calloc(n,sizeof(double));if(!j||!a||!b){free(j);free(a);free(b);return GX2D_NOMEM;}
    code=GX2D_CONSTRAINT;
    for(int step=0;step<100;step++){
        code=sk_jacobian(t,v,rows,j);if(code!=GX2D_OK)break;memset(a,0,n*n*sizeof(double));memset(b,0,n*sizeof(double));
        for(size_t k=0;k<n;k++){for(size_t i=0;i<rows;i++){b[k]-=j[i*n+k]*v[i];for(size_t l=0;l<n;l++)a[k*n+l]+=j[i*n+k]*j[i*n+l];}a[k*n+k]+=lambda;old[k]=*t->parameters[k];}
        if(!sk_linear(a,b,n)){code=GX2D_CONSTRAINT;break;}
        for(size_t k=0;k<n;k++)*t->parameters[k]=old[k]+b[k];
        gx2d_status candidate=sk_residual(t,trial,&rr);
        if(candidate==GX2D_OK&&rr==rows&&sk_norm(trial,rows)<sk_norm(v,rows)){
            memcpy(v,trial,rows*sizeof(double));lambda=fmax(1e-12,lambda/3);double max=0;for(size_t k=0;k<rows;k++)max=fmax(max,fabs(v[k]));if(max<goal){code=GX2D_OK;break;}
        }else {for(size_t k=0;k<n;k++)*t->parameters[k]=old[k];lambda*=10;}
        SK_TRACE("step=%d norm=%.12g lambda=%.12g\n",step,sk_norm(v,rows),lambda);
        code=GX2D_CONSTRAINT;if(lambda>1e12)break;
    }
    free(j);free(a);free(b);return code;
}
static gx2d_status sk_adopt(sk_transaction *t){
    gx2d_status code;for(size_t i=0;i<t->objects;i++){object *o=&t->scene->objects[t->indices[i]];gx2d_point *points;size_t n;code=sketch_display(o->sketch,o->count,&points,&n);if(code!=GX2D_OK)return code;free(o->points);o->points=points;}
    return gx2d_check_constraints(t->scene);
}
gx2d_status gx2d_sketch_status_get(gx2d_scene *s,gx2d_id id,gx2d_sketch_status *out){
    if(!s||!out)return GX2D_INVALID;sk_transaction t;gx2d_status code=sk_begin(s,id,&t);if(code!=GX2D_OK)return code;
    double v[SK_ROWS];size_t rows=0,rank=0;code=sk_residual(&t,v,&rows);double *j=calloc(SK_ROWS*(t.n?t.n:1),sizeof(double));if(!j){sk_finish(&t,0);return GX2D_NOMEM;}
    if(code==GX2D_OK&&t.n){code=sk_jacobian(&t,v,rows,j);if(code==GX2D_OK)rank=sk_rank(j,rows,t.n);}free(j);
    int complete=1,valid=code==GX2D_OK&&sk_norm(v,rows)<1e-14;
    gx2d_id ids[SK_OBJECTS];size_t count;gx2d_sketch_component_ids(s,id,ids,SK_OBJECTS,&count);
    for(size_t i=0;i<count;i++){const object *o=cobj(s,ids[i]);if(!o||!o->sketch)complete=0;}
    for(size_t i=0;i<s->rule_count;i++){const rule *r=&s->rules[i];if(!r->disabled&&!r->presentation.driven&&sk_member(&t,r->spec.a)){if(!r->presentation.solved)complete=0;if(rule_check(s,r)!=GX2D_OK)valid=0;}}
    *out=(gx2d_sketch_status){t.n,rank,t.n-rank,valid,complete};sk_finish(&t,0);return code;
}
static void sk_branch(gx2d_scene *s,rule *r){
    const object *a=cobj(s,r->spec.a),*b=cobj(s,r->spec.b);if(r->spec.kind!=GX2D_TANGENT||r->spec.a_index<GX2D_SEGMENT_INDEX||r->spec.b_index<GX2D_SEGMENT_INDEX)return;
    if(sk_round(a)&&sk_round(b)){gx2d_point ca,cb;double ra,rb;constraint_center(a,&ca);constraint_center(b,&cb);constraint_radius(a,&ra);constraint_radius(b,&rb);r->presentation.branch=fabs(dist(ca,cb)-fabs(ra-rb))<fabs(dist(ca,cb)-(ra+rb))?2:1;}
    else {const object *line=sk_round(a)?b:a,*round=line==a?b:a;size_t ix=line==a?r->spec.a_index:r->spec.b_index;if(ix==GX2D_OBJECT_INDEX)ix=GX2D_SEGMENT_INDEX;gx2d_point p,q,d,c;if(constraint_segment(line,ix,&p,&q,&d)==GX2D_OK&&constraint_center(round,&c)==GX2D_OK)r->presentation.branch=sk_cross(sk_sub(c,p),d)<0?-1:1;}
}
static gx2d_status sk_apply(gx2d_scene *s,gx2d_id existing,const gx2d_constraint_v2 *d,int driven,int placed,gx2d_point annotation,gx2d_id *out){
    if(!s||!d||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    if(!isfinite(d->base.value)||!isfinite(d->base.tolerance)||d->base.tolerance<=0||d->base.kind<GX2D_FIXED||d->base.kind>GX2D_CURVATURE||!isfinite(d->angular_tolerance)||d->angular_tolerance<0||(d->disabled!=0&&d->disabled!=1)||(d->anchor_valid!=0&&d->anchor_valid!=1)||(driven!=0&&driven!=1)||(d->anchor_valid&&!finite2(d->anchor))||!finite2(annotation))return GX2D_INVALID;
    if((d->base.kind==GX2D_DISTANCE||d->base.kind==GX2D_RADIUS||d->base.kind==GX2D_DIAMETER)&&d->base.value<0)return GX2D_INVALID;
    if(!driven&&((d->base.kind==GX2D_RADIUS||d->base.kind==GX2D_DIAMETER||(d->base.kind==GX2D_DISTANCE&&d->base.a==d->base.b&&interaction_is_line(cobj(s,d->base.a))))&&d->base.value==0))return GX2D_INVALID;
    rule *r=existing?sk_rule(s,existing):NULL,old;size_t index;int added=!existing;
    if(existing&&!r)return GX2D_NOT_FOUND;
    if(added&&(s->next_id==UINT64_MAX||s->rule_count==SIZE_MAX/sizeof(rule)))return GX2D_RANGE;
    if(added){rule *next=realloc(s->rules,(s->rule_count+1)*sizeof(rule));if(!next)return GX2D_NOMEM;s->rules=next;index=s->rule_count++;r=&s->rules[index];memset(r,0,sizeof(*r));r->id=s->next_id;}else {index=(size_t)(r-s->rules);old=*r;}
    r->spec=d->base;r->axis=d->axis;r->axis_index=d->axis_index;r->disabled=d->disabled;r->angular_tolerance=d->angular_tolerance;
    r->presentation=(gx2d_relationship_state){1,driven,placed,annotation,0,existing?old.presentation.curvature_tolerance:0};sk_branch(s,r);
    gx2d_status code=constraint_point(cobj(s,d->base.a),d->base.a_index,&r->anchor);if(d->anchor_valid)r->anchor=d->anchor;
    sk_transaction t;int begun=0;if(code==GX2D_OK){code=sk_begin(s,d->base.a,&t);begun=code==GX2D_OK;}
    if(code==GX2D_OK&&!driven&&!d->disabled){
        object *a=obj(s,d->base.a);
        if(can_move(s,a)&&d->base.kind<=GX2D_LOCK_Y&&d->base.kind!=GX2D_TANGENT&&d->base.kind!=GX2D_SYMMETRY){gx2d_status guess=interaction_drive(a,cobj(s,d->base.b),cobj(s,d->axis),d);if(guess==GX2D_RANGE)code=guess;}
        if(code==GX2D_OK)code=sk_solve(&t);
    }
    if(code==GX2D_OK&&placed&&!driven&&!d->disabled&&(added||old.presentation.driven)){
        double residual[SK_ROWS];size_t rows=0;double *j=calloc(SK_ROWS*(t.n?t.n:1),sizeof(double));
        if(!j)code=GX2D_NOMEM;else {
            code=sk_residual(&t,residual,&rows);size_t after=0,before=0;
            if(code==GX2D_OK){code=sk_jacobian(&t,residual,rows,j);if(code==GX2D_OK)after=sk_rank(j,rows,t.n);}
            s->rules[index].disabled=1;
            if(code==GX2D_OK){code=sk_residual(&t,residual,&rows);if(code==GX2D_OK)code=sk_jacobian(&t,residual,rows,j);if(code==GX2D_OK)before=sk_rank(j,rows,t.n);}
            s->rules[index].disabled=d->disabled;free(j);if(code==GX2D_OK&&after<=before)code=GX2D_CONSTRAINT;
        }
    }
    if(code==GX2D_OK)code=sk_adopt(&t);
    SK_TRACE("apply kind=%d result=%d\n",d->base.kind,code);
    if(begun)sk_finish(&t,code==GX2D_OK);
    if(code!=GX2D_OK){if(added)s->rule_count--;else s->rules[index]=old;return code;}
    if(added)s->next_id++;*out=s->rules[index].id;return GX2D_OK;
}
gx2d_status gx2d_constraint_apply(gx2d_scene *s,gx2d_id existing,const gx2d_constraint_v2 *d,gx2d_id *out){
    if(!s||!d)return GX2D_INVALID;const object *a=cobj(s,d->base.a);
    if(!a||!a->sketch)return interaction_legacy_apply(s,existing,d,out);
    gx2d_relationship_state state={0};if(existing)gx2d_relationship_get(s,existing,&state);
    return sk_apply(s,existing,d,state.driven,state.placed,state.annotation,out);
}
static int sk_dimension_kind(gx2d_constraint_kind kind){return kind==GX2D_DISTANCE||kind==GX2D_ANGLE||kind==GX2D_RADIUS||kind==GX2D_DIAMETER||kind==GX2D_LOCK_X||kind==GX2D_LOCK_Y||(kind>=GX2D_HORIZONTAL_DISTANCE&&kind<=GX2D_AXIS_ANGLE);}
gx2d_status gx2d_dimension_apply(gx2d_scene *s,gx2d_id existing,const gx2d_constraint_v2 *d,int driven,gx2d_point annotation,gx2d_id *out){if(!d||!sk_dimension_kind(d->base.kind))return GX2D_INVALID;return sk_apply(s,existing,d,driven,1,annotation,out);}
gx2d_status gx2d_constraint_create_state(gx2d_scene *s,const gx2d_constraint_v2 *d,const gx2d_relationship_state *state,gx2d_id *out){
    if(!s||!d||!state||!out||s->dragging||!finite2(state->annotation)||!isfinite(state->curvature_tolerance)||state->curvature_tolerance<0||state->branch < -1||state->branch>2||!isfinite(d->base.value)||!isfinite(d->base.tolerance)||d->base.tolerance<=0||d->base.kind<GX2D_FIXED||d->base.kind>GX2D_CURVATURE||
       (state->solved!=0&&state->solved!=1)||(state->driven!=0&&state->driven!=1)||(state->driven&&!sk_dimension_kind(d->base.kind))||(state->placed!=0&&state->placed!=1)||(d->disabled!=0&&d->disabled!=1)||!isfinite(d->angular_tolerance)||d->angular_tolerance<0||(d->anchor_valid!=0&&d->anchor_valid!=1)||(d->anchor_valid&&!finite2(d->anchor))||
       ((d->base.kind==GX2D_DISTANCE||d->base.kind==GX2D_RADIUS||d->base.kind==GX2D_DIAMETER)&&d->base.value<0))return GX2D_INVALID;
    rule candidate={0};candidate.spec=d->base;candidate.axis=d->axis;candidate.axis_index=d->axis_index;candidate.disabled=d->disabled;candidate.angular_tolerance=d->angular_tolerance;candidate.presentation=*state;
    gx2d_status code=constraint_point(cobj(s,d->base.a),d->base.a_index,&candidate.anchor);if(code!=GX2D_OK)return code;if(d->anchor_valid)candidate.anchor=d->anchor;
    code=rule_check_extended(s,&candidate,NULL);if(code!=GX2D_OK&&!(candidate.disabled&&code==GX2D_CONSTRAINT))return code;
    if(s->next_id==UINT64_MAX||s->rule_count==SIZE_MAX/sizeof(rule))return GX2D_RANGE;
    rule *next=realloc(s->rules,(s->rule_count+1)*sizeof(rule));if(!next)return GX2D_NOMEM;s->rules=next;candidate.id=fresh(s);s->rules[s->rule_count++]=candidate;*out=candidate.id;return GX2D_OK;
}
gx2d_status gx2d_relationship_get(const gx2d_scene *s,gx2d_id id,gx2d_relationship_state *out){rule *r=s?sk_rule((gx2d_scene *)s,id):NULL;if(!out)return GX2D_INVALID;if(!r)return GX2D_NOT_FOUND;*out=r->presentation;return GX2D_OK;}
gx2d_status gx2d_relationship_set(gx2d_scene *s,gx2d_id id,const gx2d_relationship_state *d){
    rule *r=s?sk_rule(s,id):NULL;if(!r)return GX2D_NOT_FOUND;if(!d||!finite2(d->annotation)||!isfinite(d->curvature_tolerance)||d->curvature_tolerance<0||d->branch < -1||d->branch>2||(d->driven!=0&&d->driven!=1)||(d->driven&&!sk_dimension_kind(r->spec.kind))||(d->solved!=0&&d->solved!=1)||(d->placed!=0&&d->placed!=1))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    if(r->presentation.driven&&!d->driven){gx2d_constraint_v2 spec;gx2d_id out;gx2d_constraint_get(s,id,&spec);gx2d_status code=sk_apply(s,id,&spec,0,d->placed,d->annotation,&out);if(code!=GX2D_OK)return code;r=sk_rule(s,id);}
    rule old=*r;r->presentation=*d;gx2d_status code=rule_check_extended(s,r,NULL);if(code!=GX2D_OK&&!r->disabled){*r=old;return code;}return GX2D_OK;
}
gx2d_status gx2d_sketch_solve_control(gx2d_scene *s,const gx2d_reference *ref,gx2d_point point){
    if(!s||!ref||!finite2(point))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;gx2d_point old;gx2d_status code=gx2d_reference_resolve(s,ref,&old);if(code!=GX2D_OK)return code;
    object *o=obj(s,ref->object);if(!o||!o->sketch||ref->entity!=GX2D_ENTITY_CONTROL)return GX2D_INVALID;if(!can_move(s,o))return GX2D_LOCKED;
    sk_transaction t;code=sk_begin(s,ref->object,&t);if(code!=GX2D_OK)return code;t.has_target=1;t.target=*ref;t.point=point;
    gx2d_control_role role;gx2d_point current;control_point(o,ref->index-GX2D_CONTROL_INDEX,&current,&role);
    if(!sketch_is_composition(o->sketch)&&(role==GX2D_CONTROL_RADIUS||role==GX2D_CONTROL_AXIS_X||role==GX2D_CONTROL_AXIS_Y||role==GX2D_CONTROL_ARC_START||role==GX2D_CONTROL_ARC_END)){
        gx2d_sketch_definition desired;gx2d_point *controls=malloc(o->sketch->control_count*sizeof(*controls));
        if(!controls){sk_finish(&t,0);return GX2D_NOMEM;}
        code=gx2d_control_definition(s,ref,point,&desired,controls,o->sketch->control_count);
        if(code==GX2D_OK){object witness=*o;witness.sketch=&desired;code=control_point(&witness,ref->index-GX2D_CONTROL_INDEX,&t.point,NULL);}
        free(controls);if(code!=GX2D_OK){sk_finish(&t,0);return code;}
        double *x=(double *)&o->sketch->controls[0].x,*y=(double *)&o->sketch->controls[0].y;
        size_t n=0;for(size_t i=0;i<t.n;i++)if(t.parameters[i]!=x&&t.parameters[i]!=y)t.parameters[n++]=t.parameters[i];t.n=n;
    }
    code=sk_solve(&t);if(code==GX2D_OK)code=sk_adopt(&t);sk_finish(&t,code==GX2D_OK);return code;
}
gx2d_status gx2d_sketch_solve_definition(gx2d_scene *s,gx2d_id id,const gx2d_sketch_definition *d){
    if(!s||!d)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;object *o=obj(s,id);if(!o||!o->sketch)return GX2D_INVALID;if(!can_move(s,o))return GX2D_LOCKED;
    if(d->family!=o->sketch->family||d->control_count!=o->sketch->control_count||gx2d_sketch_validate(d)!=GX2D_OK)return GX2D_INVALID;
    /* Definition edits express desired parameters; constraints project the
     * candidate to the nearest supported solution. Handle edits use hard goals. */
    sk_transaction t;gx2d_status code=sk_begin(s,id,&t);if(code!=GX2D_OK)return code;
    gx2d_point *controls=(gx2d_point *)o->sketch->controls;memcpy(controls,d->controls,d->control_count*sizeof(*controls));
    gx2d_spline_tangent *arms=(gx2d_spline_tangent *)o->sketch->tangents;size_t arm_count=o->sketch->tangent_count;
    if(arms){memset(arms,0,arm_count*sizeof(*arms));if(d->tangent_count)memcpy(arms,d->tangents,d->tangent_count*sizeof(*arms));}
    *o->sketch=*d;o->sketch->controls=controls;o->sketch->tangents=arms;o->sketch->tangent_count=arm_count;
    size_t count=0;for(size_t i=0;i<t.n;i++){
        double *parameter=t.parameters[i];int changed=0;
        const gx2d_sketch_definition *old=NULL;for(size_t k=0;k<t.objects;k++)if(t.before[k].id==id)old=t.before[k].sketch;
        for(size_t k=0;k<o->sketch->control_count;k++){
            if(parameter==&o->sketch->controls[k].x&&d->controls[k].x!=old->controls[k].x)changed=1;
            if(parameter==&o->sketch->controls[k].y&&d->controls[k].y!=old->controls[k].y)changed=1;
        }
        for(size_t k=0;k<o->sketch->tangent_count;k++) {
            const gx2d_spline_tangent zero={{0,0},{0,0},0};
            const gx2d_spline_tangent *before=old->tangent_count?&old->tangents[k]:&zero;
            const gx2d_spline_tangent *after=&o->sketch->tangents[k];
            if(parameter==&after->incoming.x&&after->incoming.x!=before->incoming.x)changed=1;
            if(parameter==&after->incoming.y&&after->incoming.y!=before->incoming.y)changed=1;
            if(parameter==&after->outgoing.x&&after->outgoing.x!=before->outgoing.x)changed=1;
            if(parameter==&after->outgoing.y&&after->outgoing.y!=before->outgoing.y)changed=1;
        }
        if(parameter==&o->sketch->radius_x&&d->radius_x!=old->radius_x)changed=1;
        if(parameter==&o->sketch->radius_y&&d->radius_y!=old->radius_y)changed=1;
        if(parameter==&o->sketch->rotation&&d->rotation!=old->rotation)changed=1;
        if(parameter==&o->sketch->angle_start&&d->angle_start!=old->angle_start)changed=1;
        if(parameter==&o->sketch->angle_sweep&&d->angle_sweep!=old->angle_sweep)changed=1;
        if(!changed)t.parameters[count++]=parameter;
    }t.n=count;
    code=sk_solve(&t);if(code==GX2D_OK)code=sk_adopt(&t);sk_finish(&t,code==GX2D_OK);return code;
}
/* Move/rotate preserve the legacy controller transaction. Retained components
 * solve at commit; cancellation restores all coupled definitions as well. */
static gx2d_status sketch_solve_drag(gx2d_scene *s){
    for(size_t i=0;i<s->object_count;i++)if(s->objects[i].sketch&&s->drag_masks[i]&&s->drag_masks[i][0]&&sketch_has_solver(s,s->objects[i].id)){
        sk_transaction t;gx2d_status code=sk_begin(s,s->objects[i].id,&t);if(code!=GX2D_OK)return code;
        code=sk_solve(&t);if(code==GX2D_OK)code=sk_adopt(&t);sk_finish(&t,code==GX2D_OK);if(code!=GX2D_OK)return code;
    }return GX2D_OK;
}

gx2d_status gx2d_dimension_infer(const gx2d_scene *s,const gx2d_reference *refs,size_t n,gx2d_point cursor,gx2d_constraint_v2 *out){
    if(!s||!refs||!out||!finite2(cursor)||n<1||n>2)return GX2D_INVALID;
    const object *a=cobj(s,refs[0].object),*b=n==2?cobj(s,refs[1].object):NULL;gx2d_constraint_kind kind=GX2D_DISTANCE;
    if(n==1){
        object leaf;gx2d_sketch_definition definition;size_t index=refs[0].index;
        const object *shape=a;
        /* Inference must classify the selected constituent, as constraint
         * creation already does, rather than the enclosing composed Path. */
        int mapped=network_leaf(a,&index,&leaf,&definition,NULL);
        if(mapped<0)return GX2D_INVALID;if(mapped)shape=&leaf;
        if(sk_round(shape))kind=shape->sketch->family==GX2D_SKETCH_CIRCLE?GX2D_DIAMETER:GX2D_RADIUS;
        else if(refs[0].entity==GX2D_ENTITY_CONTROL){gx2d_point p;gx2d_reference_resolve(s,&refs[0],&p);kind=fabs(cursor.x-p.x)>fabs(cursor.y-p.y)?GX2D_LOCK_Y:GX2D_LOCK_X;}}
    else if(refs[0].entity==GX2D_ENTITY_CONTROL&&refs[1].entity==GX2D_ENTITY_CONTROL){gx2d_point p,q;gx2d_reference_resolve(s,&refs[0],&p);gx2d_reference_resolve(s,&refs[1],&q);
        double x0=fmin(p.x,q.x),x1=fmax(p.x,q.x),y0=fmin(p.y,q.y),y1=fmax(p.y,q.y);
        if(cursor.x>=x0&&cursor.x<=x1&&(cursor.y<y0||cursor.y>y1))kind=GX2D_HORIZONTAL_DISTANCE;
        else if(cursor.y>=y0&&cursor.y<=y1&&(cursor.x<x0||cursor.x>x1))kind=GX2D_VERTICAL_DISTANCE;
    }else if(refs[0].entity==GX2D_ENTITY_CONTROL)kind=GX2D_POINT_LINE_DISTANCE;
    else if(refs[1].entity==GX2D_ENTITY_CONTROL){gx2d_reference pair[2]={refs[1],refs[0]};return gx2d_dimension_infer(s,pair,n,cursor,out);}
    else {gx2d_point p,q,u,v,da,db;if(constraint_segment(a,refs[0].entity==GX2D_ENTITY_SEGMENT?refs[0].index:GX2D_SEGMENT_INDEX,&p,&q,&da)!=GX2D_OK||constraint_segment(b,refs[1].entity==GX2D_ENTITY_SEGMENT?refs[1].index:GX2D_SEGMENT_INDEX,&u,&v,&db)!=GX2D_OK)return GX2D_INVALID;kind=fabs(sk_cross(da,db))<1e-6?GX2D_LINE_DISTANCE:GX2D_ANGLE;}
    return gx2d_constraint_from_selection(s,kind,refs,n,out);
}
static void sk_line(gx2d_dimension_geometry *g,gx2d_point a,gx2d_point b){if(g->line_count+2<=96){g->lines[g->line_count++]=a;g->lines[g->line_count++]=b;}}
static void sk_arrow(gx2d_dimension_geometry *g,gx2d_point p,gx2d_point q){double len=dist(p,q);if(len<1e-6)return;gx2d_point d={(q.x-p.x)/len,(q.y-p.y)/len};sk_line(g,p,(gx2d_point){p.x+8*d.x+3*d.y,p.y+8*d.y-3*d.x});sk_line(g,p,(gx2d_point){p.x+8*d.x-3*d.y,p.y+8*d.y+3*d.x});}
static gx2d_status sk_dimension_geometry(const gx2d_scene *s,const rule *r,gx2d_dimension_geometry *out){
    if(!out||!sk_dimension_kind(r->spec.kind))return GX2D_INVALID;
    const object *a=cobj(s,r->spec.a),*b=cobj(s,r->spec.b);gx2d_point p,q,an,dir,u,w,da,db;gx2d_constraint_kind kind=r->spec.kind;double radius,value[32];size_t n;
    memset(out,0,sizeof(*out));gx2d_status code=sk_equations(s,r,value,&n,&out->value);if(code!=GX2D_OK)return code;
    constraint_point(a,r->spec.a_index,&p);if(b)constraint_point(b,r->spec.b_index,&q);else q=(gx2d_point){0,0};
    an=r->presentation.placed?r->presentation.annotation:(gx2d_point){p.x+1,p.y+1};out->driven=r->presentation.driven;
    if(kind==GX2D_RADIUS||kind==GX2D_DIAMETER){constraint_center(a,&p);constraint_radius(a,&radius);dir=sk_sub(an,p);double len=hypot(dir.x,dir.y);if(len==0){dir=(gx2d_point){1,0};len=1;}q=(gx2d_point){p.x+radius*dir.x/len,p.y+radius*dir.y/len};if(kind==GX2D_DIAMETER)p=(gx2d_point){p.x-radius*dir.x/len,p.y-radius*dir.y/len};}
    else if(kind==GX2D_LOCK_X){q=p;p=(gx2d_point){0,p.y};}
    else if(kind==GX2D_LOCK_Y){q=p;p=(gx2d_point){p.x,0};}
    else if(kind==GX2D_POINT_LINE_DISTANCE||kind==GX2D_LINE_DISTANCE){constraint_segment(b,r->spec.b_index,&q,&w,&db);double along=sk_dot(sk_sub(p,q),db);q=(gx2d_point){q.x+along*db.x,q.y+along*db.y};}
    else if(kind==GX2D_ANGLE||kind==GX2D_AXIS_ANGLE){
        constraint_segment(a,r->spec.a_index,&p,&u,&da);if(kind==GX2D_ANGLE){constraint_segment(b,r->spec.b_index,&q,&w,&db);double cross=sk_cross(da,db);if(fabs(cross)>1e-10){double along=sk_cross(sk_sub(q,p),db)/cross;p=(gx2d_point){p.x+along*da.x,p.y+along*da.y};}}else db=(gx2d_point){1,0};
        double start=atan2(da.y,da.x),sweep=kind==GX2D_AXIS_ANGLE?-start:atan2(sk_cross(da,db),sk_dot(da,db));radius=dist(an,p);gx2d_point first,last,prev;
        for(int i=0;i<=16;i++){double theta=start+sweep*i/16;gx2d_point v={p.x+radius*cos(theta),p.y+radius*sin(theta)},d;gx2d_world_to_device(s,v,&d);if(i==0){first=d;prev=d;}else {sk_line(out,prev,d);prev=d;}if(i==16)last=d;}
        gx2d_point center;gx2d_world_to_device(s,p,&center);sk_line(out,center,first);sk_line(out,center,last);sk_arrow(out,first,out->lines[1]);sk_arrow(out,last,out->lines[30]);out->angular=1;gx2d_world_to_device(s,an,&out->label);goto bounds;
    }
    gx2d_point p0,q0,a0,b0;gx2d_world_to_device(s,p,&p0);gx2d_world_to_device(s,q,&q0);gx2d_world_to_device(s,an,&out->label);
    a0=p0;b0=q0;
    if(kind==GX2D_HORIZONTAL_DISTANCE||kind==GX2D_LOCK_X){a0.y=b0.y=out->label.y;}
    else if(kind==GX2D_VERTICAL_DISTANCE||kind==GX2D_LOCK_Y){a0.x=b0.x=out->label.x;}
    else if(kind!=GX2D_RADIUS&&kind!=GX2D_DIAMETER){double len=dist(p0,q0);if(len>1e-9){gx2d_point normal={-(q0.y-p0.y)/len,(q0.x-p0.x)/len};double offset=sk_dot(sk_sub(out->label,p0),normal);a0=(gx2d_point){p0.x+offset*normal.x,p0.y+offset*normal.y};b0=(gx2d_point){q0.x+offset*normal.x,q0.y+offset*normal.y};}}
    sk_line(out,p0,a0);sk_line(out,q0,b0);sk_line(out,a0,b0);sk_arrow(out,a0,b0);sk_arrow(out,b0,a0);if(kind==GX2D_RADIUS||kind==GX2D_DIAMETER)sk_line(out,q0,out->label);
bounds:
    out->hit_bounds=(gx2d_rect){out->label.x-52,out->label.y-14,out->label.x+52,out->label.y+14};return GX2D_OK;
}
gx2d_status gx2d_relationship_hit_score(const gx2d_scene *s,gx2d_id id,gx2d_point device,gx2d_rect label,double *score){
    if(!s||!score||!finite2(device)||!valid_rect(label)||!sk_rule((gx2d_scene *)s,id))return GX2D_INVALID;
    *score=DBL_MAX;
    if(inside(label,device)){gx2d_point center={(label.x0+label.x1)/2,(label.y0+label.y1)/2};*score=-1/(1+dist(device,center));return GX2D_OK;}
    gx2d_dimension_geometry g;
    if(gx2d_dimension_primitives(s,id,&g)==GX2D_OK)for(size_t i=0;i+1<g.line_count;i+=2){double distance=dist(device,nearest_segment(device,g.lines[i],g.lines[i+1]));if(distance<=7&&distance<*score)*score=distance;}
    return GX2D_OK;
}
gx2d_status gx2d_relationship_hit(const gx2d_scene *s,gx2d_id id,gx2d_point device,gx2d_rect label,int *hit){
    double score;if(!hit)return GX2D_INVALID;gx2d_status result=gx2d_relationship_hit_score(s,id,device,label,&score);if(result==GX2D_OK)*hit=score<=7;return result;
}

gx2d_status gx2d_dimension_primitives(const gx2d_scene *s,gx2d_id id,gx2d_dimension_geometry *out){const rule *r=s?sk_rule((gx2d_scene *)s,id):NULL;if(!r)return GX2D_NOT_FOUND;return sk_dimension_geometry(s,r,out);}
gx2d_status gx2d_dimension_preview(const gx2d_scene *s,const gx2d_constraint_v2 *d,gx2d_point annotation,gx2d_dimension_geometry *out){if(!s||!d||!out||!finite2(annotation))return GX2D_INVALID;rule r={0};r.spec=d->base;r.axis=d->axis;r.axis_index=d->axis_index;r.presentation.placed=1;r.presentation.annotation=annotation;return sk_dimension_geometry(s,&r,out);}

/* Batch dimension recalculation is one scene transaction, including disconnected
 * components. Saving each original allocation permits exact rollback if any
 * later component fails, without publishing a partially recalculated sketch. */
gx2d_status gx2d_constraint_values(gx2d_scene *s,const gx2d_id *ids,const double *values,size_t count){
    if(!s||(count&&(!ids||!values)))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    for(size_t i=0;i<count;i++){rule *r=sk_rule(s,ids[i]);if(!r||!sk_dimension_kind(r->spec.kind)||!isfinite(values[i])||((r->spec.kind==GX2D_DISTANCE||r->spec.kind==GX2D_RADIUS||r->spec.kind==GX2D_DIAMETER)&&values[i]<0))return GX2D_INVALID;}
    object *saved=calloc(s->object_count?s->object_count:1,sizeof(object));rule *rules=malloc((s->rule_count?s->rule_count:1)*sizeof(rule));
    if(!saved||!rules){free(saved);free(rules);return GX2D_NOMEM;}memcpy(rules,s->rules,s->rule_count*sizeof(rule));
    size_t copied=0;gx2d_status code=GX2D_OK;
    for(;copied<s->object_count;copied++){object *o=&s->objects[copied];saved[copied]=*o;if(!o->sketch)continue;
        gx2d_sketch_definition *d=sketch_clone(o->sketch);gx2d_point *p=malloc(o->count*sizeof(gx2d_point));
        if(!d||!p){sketch_free(d);free(p);code=GX2D_NOMEM;break;}memcpy(p,o->points,o->count*sizeof(gx2d_point));o->sketch=d;o->points=p;
    }
    if(code==GX2D_OK){
        for(size_t i=0;i<count;i++)sk_rule(s,ids[i])->spec.value=values[i];
        for(size_t i=0;i<count&&code==GX2D_OK;i++){
            rule *r=sk_rule(s,ids[i]);sk_transaction t;code=sk_begin(s,r->spec.a,&t);
            if(code==GX2D_OK){
                code=sk_solve(&t);
                if(code==GX2D_OK)for(size_t k=0;k<t.objects;k++){object *o=&s->objects[t.indices[k]];gx2d_point *points;size_t n;code=sketch_display(o->sketch,o->count,&points,&n);if(code!=GX2D_OK)break;free(o->points);o->points=points;}
                sk_finish(&t,code==GX2D_OK);
            }
        }
    }
    if(code==GX2D_OK)code=gx2d_check_constraints(s);
    for(size_t i=0;i<copied;i++)if(saved[i].sketch){object *o=&s->objects[i];if(code==GX2D_OK){sketch_free(saved[i].sketch);free(saved[i].points);}else {sketch_free(o->sketch);free(o->points);*o=saved[i];}}
    if(code!=GX2D_OK)memcpy(s->rules,rules,s->rule_count*sizeof(rule));free(saved);free(rules);return code;
}
