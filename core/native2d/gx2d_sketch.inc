/* SPDX-License-Identifier: GPL-3.0-or-later */
/* One stateless mathematical kernel for retained sketch definitions. Native
 * scene ownership/adoption is a separate layer; sampled geometry is never the
 * authority for these exact point/derivative/bounds queries. */
static gx2d_point sketch_world(const gx2d_sketch_definition *d,gx2d_point p,int derivative) {
    return (gx2d_point){d->matrix[0]*p.x+d->matrix[1]*p.y+(derivative?0:d->matrix[4]),d->matrix[2]*p.x+d->matrix[3]*p.y+(derivative?0:d->matrix[5])};
}
gx2d_status gx2d_sketch_validate(const gx2d_sketch_definition *d) {
    size_t i,n;
    if(sketch_is_composition(d)) {
        if(d->control_count||d->tangent_count||d->path_segment_count||!d->parts||!d->part_reversed||!d->part_count||d->part_count>256||!isfinite(d->join_tolerance)||d->join_tolerance<0)return GX2D_INVALID;
        for(i=0;i<6;i++)if(!isfinite(d->matrix[i]))return GX2D_INVALID;
        if(d->path_closed<0||d->path_closed>1||(d->family==GX2D_SKETCH_COMPOUND&&d->path_closed))return GX2D_INVALID;
        gx2d_point first={0,0},previous={0,0};size_t controls=0;
        for(i=0;i<d->part_count;i++) {
            const gx2d_sketch_definition *part=&d->parts[i];gx2d_point a,b;
            if(sketch_is_composition(part)||part->family==GX2D_SKETCH_CONSTRUCTION_LINE||part->family==GX2D_SKETCH_POINT||(d->part_reversed[i]!=0&&d->part_reversed[i]!=1)||gx2d_sketch_validate(part)!=GX2D_OK)return GX2D_INVALID;
            controls+=part->control_count;if(controls>65536)return GX2D_RANGE;
            if(gx2d_sketch_evaluate(part,d->part_reversed[i]?1:0,&a,NULL)!=GX2D_OK||gx2d_sketch_evaluate(part,d->part_reversed[i]?0:1,&b,NULL)!=GX2D_OK)return GX2D_RANGE;
            /* Junction tolerance belongs to the composition's defining frame;
             * an affine presentation/coordinate transform preserves topology. */
            if(!finite2(sketch_world(d,a,0))||!finite2(sketch_world(d,b,0)))return GX2D_RANGE;
            if(d->family==GX2D_SKETCH_COMPOSITE_PATH&&!d->node_count) {
                if(i&&dist(previous,a)>d->join_tolerance)return GX2D_CONSTRAINT;
                if(d->part_count>1&&(part->family==GX2D_SKETCH_CIRCLE||part->family==GX2D_SKETCH_ELLIPSE||part->family==GX2D_SKETCH_RECTANGLE||part->path_closed))return GX2D_CONSTRAINT;
            }
            if(!i)first=a;previous=b;
        }
        if(d->family==GX2D_SKETCH_COMPOSITE_PATH&&!d->node_count&&d->path_closed&&dist(previous,first)>d->join_tolerance)return GX2D_CONSTRAINT;
        if(d->node_count) {
            object root={0};root.sketch=(gx2d_sketch_definition *)d;
            if(!d->nodes||d->node_count!=control_count(&root))return GX2D_INVALID;
            size_t owners[65536],offset=0;int connected[256]={1};
            if(d->node_count>65536)return GX2D_RANGE;
            for(size_t k=0;k<d->part_count;k++){object leaf={0};leaf.sketch=(gx2d_sketch_definition *)&d->parts[k];for(size_t j=0;j<control_count(&leaf);j++)owners[offset++]=k;}
            for(i=0;i<d->node_count;i++) {
                gx2d_point a,b;size_t node=d->nodes[i];
                if(node>i||d->nodes[node]!=node)return GX2D_INVALID;
                if(control_point(&root,i,&a,NULL)!=GX2D_OK||control_point(&root,node,&b,NULL)!=GX2D_OK)return GX2D_INVALID;
                if(dist(a,b)>fmax(d->join_tolerance,1e-8))return GX2D_CONSTRAINT;
            }
            for(size_t pass=0;pass<d->part_count;pass++)for(i=0;i<d->node_count;i++)if(connected[owners[i]]||connected[owners[d->nodes[i]]])connected[owners[i]]=connected[owners[d->nodes[i]]]=1;
            for(i=0;i<d->part_count;i++)if(!connected[i])return GX2D_CONSTRAINT;
        }
        return GX2D_OK;
    }
    if(!d||d->family<GX2D_SKETCH_POINT||d->family>GX2D_SKETCH_PATH||!valid_points(d->controls,d->control_count)||d->control_count>65536)return GX2D_INVALID;
    if(d->part_count)return GX2D_INVALID;
    for(i=0;i<6;++i)if(!isfinite(d->matrix[i]))return GX2D_INVALID;
    if(!isfinite(d->radius_x)||!isfinite(d->radius_y)||!isfinite(d->rotation)||!isfinite(d->angle_start)||!isfinite(d->angle_sweep))return GX2D_INVALID;
    if(d->tangent_count) {
        if(d->family!=GX2D_SKETCH_SPLINE||d->tangent_count!=d->control_count||!d->tangents)return GX2D_INVALID;
        for(i=0;i<d->tangent_count;i++)if(d->tangents[i].flags>3||!finite2(d->tangents[i].incoming)||!finite2(d->tangents[i].outgoing))return GX2D_INVALID;
        if((d->tangents[0].flags&1)||(d->tangents[d->control_count-1].flags&2))return GX2D_INVALID;
    }
    n=d->control_count;
    if(d->family!=GX2D_SKETCH_PATH&&(d->path_closed||d->path_segment_count))return GX2D_INVALID;
    if(d->family==GX2D_SKETCH_PATH){
        if(n<2||(d->path_closed!=0&&d->path_closed!=1)||(d->path_closed&&n<3))return GX2D_INVALID;
        size_t edges=n-1+(size_t)d->path_closed;
        if(d->path_segment_count&&(d->path_segment_count!=edges||!d->path_segments))return GX2D_INVALID;
        for(i=0;i<edges;++i){size_t end=(i+1)%n;
            if(dist(d->controls[i],d->controls[end])==0)return GX2D_INVALID;
            if(d->path_segment_count){gx2d_path_segment edge=d->path_segments[i];
                if(edge.family!=GX2D_SKETCH_LINE||edge.first!=i||edge.last!=end)return GX2D_INVALID;
            }
        }
    }
    switch(d->family) {
        case GX2D_SKETCH_POINT:if(n!=1)return GX2D_INVALID;break;
        case GX2D_SKETCH_LINE:case GX2D_SKETCH_CONSTRUCTION_LINE:if(n!=2||dist(d->controls[0],d->controls[1])==0)return GX2D_INVALID;break;
        case GX2D_SKETCH_RECTANGLE:if(n!=2||d->controls[0].x==d->controls[1].x||d->controls[0].y==d->controls[1].y)return GX2D_INVALID;break;
        case GX2D_SKETCH_CIRCLE:case GX2D_SKETCH_ARC:case GX2D_SKETCH_ELLIPSE:
            if(n!=1||d->radius_x<=0)return GX2D_INVALID;
            if(d->family==GX2D_SKETCH_ELLIPSE&&d->radius_y<=0)return GX2D_INVALID;
            if(d->family==GX2D_SKETCH_ARC&&(d->angle_sweep==0||fabs(d->angle_sweep)>2*acos(-1.0)))return GX2D_INVALID;
            break;
        case GX2D_SKETCH_QUADRATIC_BEZIER:if(n!=3)return GX2D_INVALID;break;
        case GX2D_SKETCH_CUBIC_BEZIER:if(n!=4)return GX2D_INVALID;break;
        case GX2D_SKETCH_PATH:case GX2D_SKETCH_POLYLINE:case GX2D_SKETCH_SPLINE:if(n<2)return GX2D_INVALID;break;
        default:return GX2D_INVALID;
    }
    return GX2D_OK;
}
static void sketch_cubic(const gx2d_point *p,double t,gx2d_point *point,gx2d_point *tangent) {
    double u=1-t;
    *point=(gx2d_point){u*u*u*p[0].x+3*u*u*t*p[1].x+3*u*t*t*p[2].x+t*t*t*p[3].x,u*u*u*p[0].y+3*u*u*t*p[1].y+3*u*t*t*p[2].y+t*t*t*p[3].y};
    *tangent=(gx2d_point){3*(u*u*(p[1].x-p[0].x)+2*u*t*(p[2].x-p[1].x)+t*t*(p[3].x-p[2].x)),3*(u*u*(p[1].y-p[0].y)+2*u*t*(p[2].y-p[1].y)+t*t*(p[3].y-p[2].y))};
}
static void sketch_spline_controls(const gx2d_sketch_definition *d,size_t segment,gx2d_point p[4]) {
    gx2d_point a=d->controls[segment?segment-1:segment],b=d->controls[segment],c=d->controls[segment+1],e=d->controls[segment+2<d->control_count?segment+2:segment+1];
    p[0]=b;p[1]=(gx2d_point){b.x+(c.x-a.x)/6,b.y+(c.y-a.y)/6};p[2]=(gx2d_point){c.x-(e.x-b.x)/6,c.y-(e.y-b.y)/6};p[3]=c;
    if(d->tangent_count) {
        const gx2d_spline_tangent *left=&d->tangents[segment],*right=&d->tangents[segment+1];
        if(left->flags&2)p[1]=(gx2d_point){b.x+left->outgoing.x,b.y+left->outgoing.y};
        if(right->flags&1)p[2]=(gx2d_point){c.x+right->incoming.x,c.y+right->incoming.y};
    }
}
static gx2d_status sketch_evaluate_valid(const gx2d_sketch_definition *d,double t,gx2d_point *point,gx2d_point *tangent) {
    gx2d_point p={0,0},v={0,0};size_t segment;double local,n,co,si,theta,sweep,rx,ry;const gx2d_point *c=d->controls;
    if(!isfinite(t)||(d->family!=GX2D_SKETCH_CONSTRUCTION_LINE&&(t<0||t>1)))return GX2D_RANGE;
    switch(d->family) {
        case GX2D_SKETCH_COMPOSITE_PATH: {
            size_t part=t==1?d->part_count-1:(size_t)(t*d->part_count);
            double u=t*d->part_count-part;int reverse=d->part_reversed[part];
            gx2d_status code=sketch_evaluate_valid(&d->parts[part],reverse?1-u:u,&p,&v);
            if(code!=GX2D_OK)return code;double scale=(reverse?-1:1)*(double)d->part_count;v.x*=scale;v.y*=scale;break;
        }
        case GX2D_SKETCH_COMPOUND:return GX2D_INVALID; /* No global parameter/traversal. */
        case GX2D_SKETCH_POINT:p=c[0];break;
        case GX2D_SKETCH_LINE:case GX2D_SKETCH_CONSTRUCTION_LINE:
            v=(gx2d_point){c[1].x-c[0].x,c[1].y-c[0].y};p=(gx2d_point){c[0].x+t*v.x,c[0].y+t*v.y};break;
        case GX2D_SKETCH_RECTANGLE: {
            gx2d_point vertices[5]={c[0],{c[1].x,c[0].y},c[1],{c[0].x,c[1].y},c[0]};
            segment=t==1?3:(size_t)(t*4);local=t*4-segment;
            v=(gx2d_point){4*(vertices[segment+1].x-vertices[segment].x),4*(vertices[segment+1].y-vertices[segment].y)};
            p=(gx2d_point){vertices[segment].x+local*v.x/4,vertices[segment].y+local*v.y/4};
            co=cos(d->rotation);si=sin(d->rotation);local=p.x-c[0].x;n=p.y-c[0].y;
            p=(gx2d_point){c[0].x+co*local-si*n,c[0].y+si*local+co*n};v=(gx2d_point){co*v.x-si*v.y,si*v.x+co*v.y};break;
        }
        case GX2D_SKETCH_CIRCLE:case GX2D_SKETCH_ARC:case GX2D_SKETCH_ELLIPSE:
            sweep=d->family==GX2D_SKETCH_ARC?d->angle_sweep:2*acos(-1.0);
            theta=(d->family==GX2D_SKETCH_ARC?remainder(d->angle_start,2*acos(-1.0)):0)+sweep*t;
            if(t==1&&d->family!=GX2D_SKETCH_ARC)theta=0;
            rx=d->radius_x;ry=d->family==GX2D_SKETCH_ELLIPSE?d->radius_y:rx;
            co=cos(d->rotation);si=sin(d->rotation);
            p=(gx2d_point){c[0].x+co*rx*cos(theta)-si*ry*sin(theta),c[0].y+si*rx*cos(theta)+co*ry*sin(theta)};
            v=(gx2d_point){sweep*(-co*rx*sin(theta)-si*ry*cos(theta)),sweep*(-si*rx*sin(theta)+co*ry*cos(theta))};break;
        case GX2D_SKETCH_QUADRATIC_BEZIER: {
            double u=1-t;p=(gx2d_point){u*u*c[0].x+2*u*t*c[1].x+t*t*c[2].x,u*u*c[0].y+2*u*t*c[1].y+t*t*c[2].y};
            v=(gx2d_point){2*(u*(c[1].x-c[0].x)+t*(c[2].x-c[1].x)),2*(u*(c[1].y-c[0].y)+t*(c[2].y-c[1].y))};break;
        }
        case GX2D_SKETCH_CUBIC_BEZIER:sketch_cubic(c,t,&p,&v);break;
        case GX2D_SKETCH_PATH:case GX2D_SKETCH_POLYLINE:case GX2D_SKETCH_SPLINE:
            n=(double)(d->control_count-1+(d->family==GX2D_SKETCH_PATH&&d->path_closed));segment=t==1?(size_t)n-1:(size_t)(t*n);local=t*n-segment;
            if(d->family==GX2D_SKETCH_SPLINE){gx2d_point b[4];sketch_spline_controls(d,segment,b);sketch_cubic(b,local,&p,&v);v.x*=n;v.y*=n;}
            else {size_t next=(segment+1)%d->control_count;v=(gx2d_point){n*(c[next].x-c[segment].x),n*(c[next].y-c[segment].y)};p=(gx2d_point){c[segment].x+local*v.x/n,c[segment].y+local*v.y/n};}break;
        default:return GX2D_INVALID;
    }
    p=sketch_world(d,p,0);v=sketch_world(d,v,1);
    if(!finite2(p)||!finite2(v))return GX2D_RANGE;
    if(point)*point=p;if(tangent)*tangent=v;return GX2D_OK;
}
gx2d_status gx2d_sketch_evaluate(const gx2d_sketch_definition *d,double t,gx2d_point *point,gx2d_point *tangent) {
    gx2d_status code;if(!point&&!tangent)return GX2D_INVALID;code=gx2d_sketch_validate(d);if(code!=GX2D_OK)return code;
    return sketch_evaluate_valid(d,t,point,tangent);
}
gx2d_status gx2d_sketch_sample(const gx2d_sketch_definition *d,double first,double last,size_t total,size_t start,size_t count,gx2d_point *out,size_t capacity) {
    gx2d_point *staged;gx2d_status code;size_t i;
    if(!out||!total||total>1000000||!count||count>65536||capacity<count||start>total||count>total-start||!isfinite(first)||!isfinite(last))return GX2D_INVALID;
    code=gx2d_sketch_validate(d);if(code!=GX2D_OK)return code;
    if(d->family!=GX2D_SKETCH_CONSTRUCTION_LINE&&(first<0||first>1||last<0||last>1))return GX2D_RANGE;
    staged=(gx2d_point *)malloc(count*sizeof(*staged));if(!staged)return GX2D_NOMEM;
    for(i=0;i<count;++i){double t=total==1?first:first+(last-first)*(double)(start+i)/(double)(total-1);code=sketch_evaluate_valid(d,t,&staged[i],NULL);if(code!=GX2D_OK){free(staged);return code;}}
    memcpy(out,staged,count*sizeof(*out));free(staged);return GX2D_OK;
}
static int sketch_bound_add(gx2d_rect *bounds,gx2d_point p,int *initialized) {
    if(!finite2(p))return 0;
    if(!*initialized){*bounds=(gx2d_rect){p.x,p.y,p.x,p.y};*initialized=1;}
    else {if(p.x<bounds->x0)bounds->x0=p.x;if(p.x>bounds->x1)bounds->x1=p.x;if(p.y<bounds->y0)bounds->y0=p.y;if(p.y>bounds->y1)bounds->y1=p.y;}
    return 1;
}
static size_t sketch_derivative_roots(double a,double b,double c,double roots[2]) {
    double scale=fmax(fabs(a),fmax(fabs(b),fabs(c))),discriminant,q;
    if(!scale)return 0;a/=scale;b/=scale;c/=scale;
    if(fabs(a)<DBL_EPSILON){if(fabs(b)<DBL_EPSILON)return 0;roots[0]=-c/b;return 1;}
    discriminant=b*b-4*a*c;if(discriminant<0)return 0;
    q=-.5*(b+copysign(sqrt(discriminant),b));
    if(q==0){roots[0]=-b/(2*a);return 1;}
    roots[0]=q/a;roots[1]=c/q;return 2;
}
static int sketch_cubic_bounds(gx2d_rect *bounds,const gx2d_point p[4],int *initialized) {
    size_t axis,i,n;double roots[2];gx2d_point point,tangent;
    if(!sketch_bound_add(bounds,p[0],initialized)||!sketch_bound_add(bounds,p[3],initialized))return 0;
    for(axis=0;axis<2;++axis) {
        double a=axis?p[0].y:p[0].x,b=axis?p[1].y:p[1].x,c=axis?p[2].y:p[2].x,d=axis?p[3].y:p[3].x;
        /* Long double protects coefficient formation for large finite controls. */
        long double qa=3*(-(long double)a+3*(long double)b-3*(long double)c+d),qb=6*((long double)a-2*(long double)b+c),qc=3*((long double)b-a);
        long double scale=fmaxl(fabsl(qa),fmaxl(fabsl(qb),fabsl(qc)));
        if(!isfinite(scale))return 0;if(scale==0)continue;
        n=sketch_derivative_roots((double)(qa/scale),(double)(qb/scale),(double)(qc/scale),roots);
        for(i=0;i<n;++i)if(roots[i]>0&&roots[i]<1){sketch_cubic(p,roots[i],&point,&tangent);if(!sketch_bound_add(bounds,point,initialized))return 0;}
    }
    return 1;
}
gx2d_status gx2d_sketch_bounds(const gx2d_sketch_definition *d,gx2d_rect *out) {
    gx2d_rect bounds={0,0,0,0};gx2d_status code;gx2d_point point;int initialized=0;size_t i,j;
    if(!out)return GX2D_INVALID;code=gx2d_sketch_validate(d);if(code!=GX2D_OK)return code;
    if(sketch_is_composition(d)) {
        for(i=0;i<d->part_count;i++) {gx2d_sketch_definition part=d->parts[i];gx2d_rect b;
            if(!sketch_compose(&part,d->matrix))return GX2D_RANGE;
            code=gx2d_sketch_bounds(&part,&b);if(code!=GX2D_OK)return code;
            sketch_bound_add(&bounds,(gx2d_point){b.x0,b.y0},&initialized);sketch_bound_add(&bounds,(gx2d_point){b.x1,b.y1},&initialized);
        }
        *out=bounds;return GX2D_OK;
    }
    if(d->family==GX2D_SKETCH_CONSTRUCTION_LINE)return GX2D_INVALID; /* infinite bounds are undefined */
    if(d->family==GX2D_SKETCH_CIRCLE||d->family==GX2D_SKETCH_ELLIPSE||d->family==GX2D_SKETCH_ARC) {
        double co=cos(d->rotation),si=sin(d->rotation),rx=d->radius_x,ry=d->family==GX2D_SKETCH_ELLIPSE?d->radius_y:rx;
        gx2d_point center=sketch_world(d,d->controls[0],0),a=sketch_world(d,(gx2d_point){co*rx,si*rx},1),b=sketch_world(d,(gx2d_point){-si*ry,co*ry},1);
        if(!finite2(center)||!finite2(a)||!finite2(b))return GX2D_RANGE;
        if(d->family!=GX2D_SKETCH_ARC) {
            double x=hypot(a.x,b.x),y=hypot(a.y,b.y);
            bounds=(gx2d_rect){center.x-x,center.y-y,center.x+x,center.y+y};
        } else {
            double start=remainder(d->angle_start,2*acos(-1.0));
            for(i=0;i<2;++i){code=sketch_evaluate_valid(d,(double)i,&point,NULL);if(code!=GX2D_OK||!sketch_bound_add(&bounds,point,&initialized))return GX2D_RANGE;}
            for(i=0;i<2;++i)for(j=0;j<2;++j) {
                double angle=atan2(i?b.y:b.x,i?a.y:a.x)+j*acos(-1.0);
                double delta=fmod(d->angle_sweep>0?angle-start:start-angle,2*acos(-1.0));if(delta<0)delta+=2*acos(-1.0);
                if(delta<=fabs(d->angle_sweep)) {
                    point=(gx2d_point){center.x+a.x*cos(angle)+b.x*sin(angle),center.y+a.y*cos(angle)+b.y*sin(angle)};
                    if(!sketch_bound_add(&bounds,point,&initialized))return GX2D_RANGE;
                }
            }
        }
    } else if(d->family==GX2D_SKETCH_QUADRATIC_BEZIER||d->family==GX2D_SKETCH_CUBIC_BEZIER||d->family==GX2D_SKETCH_SPLINE) {
        size_t segments=d->family==GX2D_SKETCH_SPLINE?d->control_count-1:1;
        for(i=0;i<segments;++i) {
            gx2d_point p[4];
            if(d->family==GX2D_SKETCH_SPLINE)sketch_spline_controls(d,i,p);
            else if(d->family==GX2D_SKETCH_QUADRATIC_BEZIER){p[0]=d->controls[0];p[1]=(gx2d_point){p[0].x+2*(d->controls[1].x-p[0].x)/3,p[0].y+2*(d->controls[1].y-p[0].y)/3};p[3]=d->controls[2];p[2]=(gx2d_point){p[3].x+2*(d->controls[1].x-p[3].x)/3,p[3].y+2*(d->controls[1].y-p[3].y)/3};}
            else memcpy(p,d->controls,sizeof(p));
            for(j=0;j<4;++j)p[j]=sketch_world(d,p[j],0);
            if(!sketch_cubic_bounds(&bounds,p,&initialized))return GX2D_RANGE;
        }
    } else if(d->family==GX2D_SKETCH_RECTANGLE) {
        for(i=0;i<4;++i){code=sketch_evaluate_valid(d,(double)i/4,&point,NULL);if(code!=GX2D_OK||!sketch_bound_add(&bounds,point,&initialized))return GX2D_RANGE;}
    } else {
        for(i=0;i<d->control_count;++i)if(!sketch_bound_add(&bounds,sketch_world(d,d->controls[i],0),&initialized))return GX2D_RANGE;
    }
    if(!valid_rect(bounds))return GX2D_RANGE;*out=bounds;return GX2D_OK;
}
static gx2d_sketch_definition *sketch_clone(const gx2d_sketch_definition *source) {
    gx2d_sketch_definition *result=(gx2d_sketch_definition *)malloc(sizeof(*result));gx2d_point *controls;
    if(sketch_is_composition(source)) {
        if(!result)return NULL;*result=*source;result->controls=NULL;result->nodes=NULL;
        result->parts=calloc(source->part_count,sizeof(*result->parts));result->part_reversed=calloc(source->part_count,sizeof(int));
        if(!result->parts||!result->part_reversed){free((void *)result->parts);free((void *)result->part_reversed);free(result);return NULL;}
        memcpy((void *)result->part_reversed,source->part_reversed,source->part_count*sizeof(int));
        for(size_t i=0;i<source->part_count;i++) {
            gx2d_sketch_definition *part=sketch_clone(&source->parts[i]);
            if(!part){sketch_free(result);return NULL;}
            ((gx2d_sketch_definition *)result->parts)[i]=*part;free(part);
        }
        if(source->node_count){
            result->nodes=malloc(source->node_count*sizeof(size_t));
            if(!result->nodes){sketch_free(result);return NULL;}
            memcpy((void *)result->nodes,source->nodes,source->node_count*sizeof(size_t));
        }
        return result;
    }
    if(!result)return NULL;controls=(gx2d_point *)calloc(1,source->control_count*sizeof(*controls)+(source->family==GX2D_SKETCH_SPLINE?source->control_count*sizeof(gx2d_spline_tangent):0)+(source->family==GX2D_SKETCH_PATH?source->control_count*sizeof(gx2d_path_segment):0));
    if(!controls){free(result);return NULL;}memcpy(controls,source->controls,source->control_count*sizeof(*controls));
    *result=*source;result->controls=controls;
    if(source->family==GX2D_SKETCH_SPLINE) {
        result->tangents=(gx2d_spline_tangent *)(controls+source->control_count);result->tangent_count=source->control_count;
        if(source->tangent_count)memcpy((void *)result->tangents,source->tangents,source->tangent_count*sizeof(*source->tangents));
    }
    if(source->family==GX2D_SKETCH_PATH){
        result->path_segments=(gx2d_path_segment *)(controls+source->control_count);
        result->path_segment_count=source->control_count-1+(size_t)source->path_closed;
        for(size_t i=0;i<result->path_segment_count;++i)((gx2d_path_segment *)result->path_segments)[i]=(gx2d_path_segment){GX2D_SKETCH_LINE,i,(i+1)%source->control_count};
    }
    return result;
}
static void sketch_free(gx2d_sketch_definition *definition) {if(definition){
    if(sketch_is_composition(definition)){for(size_t i=0;i<definition->part_count;i++)free((void *)definition->parts[i].controls);free((void *)definition->parts);free((void *)definition->part_reversed);}
    free((void *)definition->nodes);free((void *)definition->controls);free(definition);
}}
/* Restore values while retaining every live allocation. Drag capture forbids
 * topology changes, so constituent/control cardinalities cannot change here. */
static void sketch_restore_owned(gx2d_sketch_definition *d,const gx2d_sketch_definition *s) {
    gx2d_point *controls=(gx2d_point *)d->controls;gx2d_spline_tangent *tangents=(gx2d_spline_tangent *)d->tangents;
    gx2d_path_segment *segments=(gx2d_path_segment *)d->path_segments;gx2d_sketch_definition *parts=(gx2d_sketch_definition *)d->parts;int *reversed=(int *)d->part_reversed;size_t *nodes=(size_t *)d->nodes;
    if(s->control_count)memcpy(controls,s->controls,s->control_count*sizeof(*controls));
    if(s->tangent_count)memcpy(tangents,s->tangents,s->tangent_count*sizeof(*tangents));
    if(s->path_segment_count)memcpy(segments,s->path_segments,s->path_segment_count*sizeof(*segments));
    for(size_t i=0;i<s->part_count;i++)sketch_restore_owned(&parts[i],&s->parts[i]);
    if(s->part_count)memcpy(reversed,s->part_reversed,s->part_count*sizeof(int));
    if(s->node_count)memcpy(nodes,s->nodes,s->node_count*sizeof(size_t));
    *d=*s;d->nodes=nodes;d->controls=controls;d->tangents=tangents;d->path_segments=segments;d->parts=parts;d->part_reversed=reversed;
}
static int sketch_compose(gx2d_sketch_definition *d,const double m[6]) {
    double result[6];size_t i;
    result[0]=m[0]*d->matrix[0]+m[1]*d->matrix[2];result[1]=m[0]*d->matrix[1]+m[1]*d->matrix[3];
    result[2]=m[2]*d->matrix[0]+m[3]*d->matrix[2];result[3]=m[2]*d->matrix[1]+m[3]*d->matrix[3];
    result[4]=m[0]*d->matrix[4]+m[1]*d->matrix[5]+m[4];result[5]=m[2]*d->matrix[4]+m[3]*d->matrix[5]+m[5];
    for(i=0;i<6;++i)if(!isfinite(result[i]))return 0;memcpy(d->matrix,result,sizeof(result));return 1;
}
/* Distribute a bounded rendering budget, retaining every exact straight
 * vertex. Reusing the resulting total gives the same layout on an edit. */
static int composition_shared_boundary(const gx2d_sketch_definition *d,size_t i) {
    if(!i||d->family!=GX2D_SKETCH_COMPOSITE_PATH||d->node_count)return 0;
    gx2d_point previous,current;
    if(sketch_evaluate_valid(&d->parts[i-1],d->part_reversed[i-1]?0:1,&previous,NULL)!=GX2D_OK||
       sketch_evaluate_valid(&d->parts[i],d->part_reversed[i]?1:0,&current,NULL)!=GX2D_OK)return 0;
    return previous.x==current.x&&previous.y==current.y;
}
static gx2d_status composition_layout(const gx2d_sketch_definition *d,size_t budget,size_t sizes[256],size_t *total) {
    size_t fixed=0,curved=0,shared=0;
    for(size_t i=1;i<d->part_count;i++)shared+=(size_t)composition_shared_boundary(d,i);
    for(size_t i=0;i<d->part_count;i++) {
        const gx2d_sketch_definition *p=&d->parts[i];size_t n=0;
        if(p->family==GX2D_SKETCH_LINE)n=2;
        else if(p->family==GX2D_SKETCH_RECTANGLE)n=5;
        else if(p->family==GX2D_SKETCH_POLYLINE||p->family==GX2D_SKETCH_PATH)n=p->control_count+(size_t)p->path_closed;
        sizes[i]=n;if(n)fixed+=n;else curved++;
    }
    size_t available=budget+shared>fixed?budget+shared-fixed:0;
    if(available<2*curved)available=2*curved;
    *total=fixed+(curved?available:0)-shared;if(*total>65536)return GX2D_RANGE;
    size_t extra=curved?available%curved:0;
    for(size_t i=0;i<d->part_count;i++)if(!sizes[i]){sizes[i]=available/curved+(extra?1:0);if(extra)extra--;}
    return GX2D_OK;
}
static void composition_breaks(const gx2d_sketch_definition *d,size_t n,unsigned char *breaks) {
    if(d->family!=GX2D_SKETCH_COMPOUND&&!d->node_count)return;
    size_t sizes[256],total,offset=0;if(composition_layout(d,n,sizes,&total)!=GX2D_OK||total!=n)return;
    for(size_t i=0;i+1<d->part_count;i++){offset+=sizes[i];breaks[offset-1]=1;}
}
static gx2d_status sketch_display(const gx2d_sketch_definition *d,size_t samples,gx2d_point **out,size_t *count) {
    gx2d_status code;size_t start,n;gx2d_point *points;
    code=gx2d_sketch_validate(d);if(code!=GX2D_OK)return code;
    if(samples<(d->family==GX2D_SKETCH_POINT?1:2)||samples>65536)return GX2D_RANGE;
    if(sketch_is_composition(d)) {
        size_t sizes[256],offset=0;code=composition_layout(d,samples,sizes,&n);if(code!=GX2D_OK)return code;
        points=malloc(n*sizeof(*points));if(!points)return GX2D_NOMEM;
        for(size_t i=0;i<d->part_count;i++) {
            gx2d_point *part=NULL;size_t returned=0;code=sketch_display(&d->parts[i],sizes[i],&part,&returned);
            if(code!=GX2D_OK){free(points);return code;}
            for(size_t j=(composition_shared_boundary(d,i)?1:0);j<returned;j++)points[offset++]=sketch_world(d,part[d->part_reversed[i]?returned-1-j:j],0);
            free(part);
        }
        *out=points;*count=n;return GX2D_OK;
    }
    n=d->family==GX2D_SKETCH_PATH?d->control_count+(size_t)d->path_closed:d->family==GX2D_SKETCH_POINT?1:d->family==GX2D_SKETCH_LINE||d->family==GX2D_SKETCH_CONSTRUCTION_LINE?2:d->family==GX2D_SKETCH_RECTANGLE?5:samples;
    points=(gx2d_point *)malloc(n*sizeof(*points));if(!points)return GX2D_NOMEM;
    if(d->family==GX2D_SKETCH_PATH){for(start=0;start<n;++start)points[start]=sketch_world(d,d->controls[start%d->control_count],0);*out=points;*count=n;return GX2D_OK;}
    for(start=0;start<n;start+=65536){size_t page=n-start;if(page>65536)page=65536;code=gx2d_sketch_sample(d,0,1,n,start,page,points+start,page);if(code!=GX2D_OK){free(points);return code;}}
    *out=points;*count=n;return GX2D_OK;
}
gx2d_status gx2d_sketch_create(gx2d_scene *s,const gx2d_sketch_definition *d,size_t samples,gx2d_id *out) {
    gx2d_status code;gx2d_point *points;gx2d_sketch_definition *owned;size_t n;gx2d_id created;
    if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    code=sketch_display(d,samples,&points,&n);if(code!=GX2D_OK)return code;
    owned=sketch_clone(d);if(!owned){free(points);return GX2D_NOMEM;}
    code=gx2d_add_geometry(s,d->family==GX2D_SKETCH_POINT?GX2D_POINT_OBJECT:GX2D_CURVE,points,n,&created);free(points);
    if(code!=GX2D_OK){sketch_free(owned);return code;}obj(s,created)->sketch=owned;composition_breaks(d,n,obj(s,created)->breaks);
    code=part_states_init(obj(s,created));if(code!=GX2D_OK){gx2d_delete_object(s,created);return code;}*out=created;return GX2D_OK;
}
gx2d_status gx2d_sketch_get_definition(const gx2d_scene *s,gx2d_id id,gx2d_sketch_definition *out) {
    const object *o=cobj(s,id);if(!s||!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(!o->sketch)return GX2D_INVALID;*out=*o->sketch;return GX2D_OK;
}
static int sketch_same_reference_layout(const gx2d_sketch_definition *a,const gx2d_sketch_definition *b) {
    if(a->family!=b->family||a->control_count!=b->control_count||a->part_count!=b->part_count||a->path_closed!=b->path_closed||a->node_count!=b->node_count)return 0;
    for(size_t i=0;i<a->node_count;i++)if(a->nodes[i]!=b->nodes[i])return 0;
    for(size_t i=0;i<a->part_count;i++)if(a->part_reversed[i]!=b->part_reversed[i]||!sketch_same_reference_layout(&a->parts[i],&b->parts[i]))return 0;
    return 1;
}
gx2d_status gx2d_sketch_update(gx2d_scene *s,gx2d_id id,const gx2d_sketch_definition *d,size_t samples) {
    object *o;gx2d_status code;gx2d_point *points;gx2d_sketch_definition *owned;size_t n;unsigned char *manual,*breaks;object before;
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;o=obj(s,id);if(!o)return GX2D_NOT_FOUND;
    if(!o->sketch)return GX2D_INVALID;if(!can_move(s,o))return GX2D_LOCKED;
    if(!o->reference_image&&!sketch_is_composition(d)&&sketch_has_solver(s,id)&&d&&d->family==o->sketch->family&&d->control_count==o->sketch->control_count&&samples==o->count)return gx2d_sketch_solve_definition(s,id,d);
    code=sketch_display(d,samples,&points,&n);if(code!=GX2D_OK)return code;
    if(n!=o->count||d->family!=o->sketch->family||d->control_count!=o->sketch->control_count){size_t i;for(i=0;i<s->rule_count;++i)if(s->rules[i].spec.a==id||s->rules[i].spec.b==id||s->rules[i].axis==id){free(points);return GX2D_CONSTRAINT;}}
    owned=sketch_clone(d);manual=(unsigned char *)calloc(n,1);breaks=(unsigned char *)calloc(n,1);
    if(!owned||!manual||!breaks){free(points);sketch_free(owned);free(manual);free(breaks);return GX2D_NOMEM;}
    /* Allocate changed leaf ownership before committing the geometry. */
    gx2d_part_state *new_parts=NULL;size_t part_count=sketch_is_composition(d)?d->part_count:0;int replace_parts=!sketch_same_reference_layout(o->sketch,d);
    if(replace_parts&&part_count>=(uint64_t)INT64_MAX-o->next_part_id){free(points);sketch_free(owned);free(manual);free(breaks);return GX2D_RANGE;}
    if(replace_parts&&part_count){new_parts=calloc(part_count,sizeof(*new_parts));if(!new_parts){free(points);sketch_free(owned);free(manual);free(breaks);return GX2D_NOMEM;}for(size_t i=0;i<part_count;i++){new_parts[i].part_id=o->next_part_id+i+1;new_parts[i].direction=default_direction_marker();new_parts[i].direction.present=0;new_parts[i].direction.forward=!d->part_reversed[i];}}
    before=*o;o->points=points;o->count=o->capacity=n;o->manual=manual;o->breaks=breaks;o->sketch=owned;o->kind=d->family==GX2D_SKETCH_POINT?GX2D_POINT_OBJECT:GX2D_CURVE;
    composition_breaks(d,n,breaks);
    code=gx2d_check_constraints(s);
    if(code!=GX2D_OK){*o=before;free(new_parts);free(points);sketch_free(owned);free(manual);free(breaks);return code;}
    /* Parameter edits keep constituent-control references stable. Only an
     * actual layout/topology change invalidates their flattened ordinals. */
    if(!sketch_same_reference_layout(before.sketch,d)){++o->parameter_epoch;++o->topology_epoch;}else if(n!=before.count)++o->topology_epoch;
    if(replace_parts){free(o->part_states);o->part_states=new_parts;o->part_state_count=part_count;o->next_part_id+=part_count;}else free(new_parts);
    free(before.points);free(before.manual);free(before.breaks);sketch_free(before.sketch);return GX2D_OK;
}
gx2d_status gx2d_sketch_explode(gx2d_scene *s,gx2d_id id,size_t samples,gx2d_id *out) {
    object *o;gx2d_point *points;size_t n;gx2d_status code;gx2d_direction_marker direction;
    if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;o=obj(s,id);if(!o)return GX2D_NOT_FOUND;if(!o->sketch)return GX2D_INVALID;
    code=sketch_display(o->sketch,samples,&points,&n);if(code!=GX2D_OK)return code;
    direction=o->direction_marker;direction.interpolation=0;
    gx2d_sketch_definition *definition=o->sketch;
    code=gx2d_add_geometry(s,n==1?GX2D_POINT_OBJECT:GX2D_CURVE,points,n,out);free(points);if(code==GX2D_OK&&n>1){obj(s,*out)->direction_marker=direction;composition_breaks(definition,n,obj(s,*out)->breaks);}return code;
}

/* Signed line integral for a finite constituent, without inventing a closing
 * chord. Used only to assemble the area of a topologically closed Path. */
static gx2d_status sketch_area_integral(const gx2d_sketch_definition *d,gx2d_point origin,double *out) {
    static const double nodes[4]={.18343464249564980494,.52553240991632898582,.79666647741362673959,.96028985649753623168};
    static const double weights[4]={.36268378337836198297,.31370664587788728734,.22238103445337447054,.10122853629037625915};
    size_t pieces=d->family==GX2D_SKETCH_RECTANGLE?4:d->family==GX2D_SKETCH_PATH?d->control_count-1+(size_t)d->path_closed:d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_SPLINE?d->control_count-1:1;
    double previous=0;size_t used=0;
    for(size_t subdivisions=1;subdivisions<=4096;subdivisions*=2) {
        if(pieces>1000000/(8*subdivisions)||used>1000000-pieces*8*subdivisions)return GX2D_RANGE;
        used+=pieces*8*subdivisions;long double sum=0;
        for(size_t segment=0;segment<pieces;segment++)for(size_t part=0;part<subdivisions;part++) {
            double half=.5/(double)(pieces*subdivisions),middle=((double)segment+((double)part+.5)/subdivisions)/pieces;
            for(size_t k=0;k<4;k++)for(int sign=-1;sign<=1;sign+=2) {
                gx2d_point p,v;gx2d_status code=sketch_evaluate_valid(d,middle+sign*half*nodes[k],&p,&v);if(code!=GX2D_OK)return code;
                sum+=(long double)half*weights[k]*((long double)(p.x-origin.x)*v.y-(long double)(p.y-origin.y)*v.x)/2;
            }
        }
        double area=(double)sum;if(!isfinite(area))return GX2D_RANGE;
        if(subdivisions>1&&fabs(area-previous)<=1e-11*fmax(1,fabs(area))){*out=area;return GX2D_OK;}previous=area;
    }
    return GX2D_RANGE;
}
/* Eight-point Gauss integration with bounded refinement. Every native piece is
 * integrated separately; retained measurements never integrate display chords. */
static gx2d_status sketch_metrics(const gx2d_sketch_definition *d,gx2d_metrics *out) {
    static const double nodes[4]={.18343464249564980494,.52553240991632898582,.79666647741362673959,.96028985649753623168};
    static const double weights[4]={.36268378337836198297,.31370664587788728734,.22238103445337447054,.10122853629037625915};
    gx2d_rect bounds;gx2d_point origin,end,p,v;gx2d_status code;size_t pieces,subdivisions,segment,part,k,used=0;int sign,closed;double previous_length=-1,previous_area=0,length=0,area=0;
    code=gx2d_sketch_bounds(d,&bounds);if(code!=GX2D_OK)return code;
    if(sketch_is_composition(d)) {
        long double sum=0,area_sum=0;gx2d_point area_origin={bounds.x0,bounds.y0};
        for(size_t i=0;i<d->part_count;i++){gx2d_sketch_definition part=d->parts[i];gx2d_metrics metrics;
            if(!sketch_compose(&part,d->matrix))return GX2D_RANGE;
            code=sketch_metrics(&part,&metrics);if(code!=GX2D_OK)return code;
            double area=metrics.signed_area;
            if(d->family==GX2D_SKETCH_COMPOSITE_PATH&&d->path_closed){code=sketch_area_integral(&part,area_origin,&area);if(code!=GX2D_OK)return code;}
            sum+=metrics.length;area_sum+=(d->part_reversed[i]?-1:1)*area;
        }
        double span=hypot(bounds.x1-bounds.x0,bounds.y1-bounds.y0);
        *out=(gx2d_metrics){(double)sum,bounds.x1-bounds.x0,bounds.y1-bounds.y0,(double)area_sum,span?(double)sum/span:0,d->family==GX2D_SKETCH_COMPOSITE_PATH&&d->path_closed};
        return isfinite(out->length)&&isfinite(out->signed_area)?GX2D_OK:GX2D_RANGE;
    }
    code=sketch_evaluate_valid(d,0,&origin,NULL);if(code!=GX2D_OK)return code;
    code=sketch_evaluate_valid(d,1,&end,NULL);if(code!=GX2D_OK)return code;
    closed=dist(origin,end)<=1e-12;
    if(d->family==GX2D_SKETCH_CIRCLE||d->family==GX2D_SKETCH_ELLIPSE||d->family==GX2D_SKETCH_RECTANGLE||(d->family==GX2D_SKETCH_ARC&&fabs(fabs(d->angle_sweep)-2*acos(-1.0))<=8*DBL_EPSILON))closed=1;
    if(d->family==GX2D_SKETCH_POINT||d->family==GX2D_SKETCH_LINE||(d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_PATH)||d->family==GX2D_SKETCH_RECTANGLE){
        size_t vertices=d->family==GX2D_SKETCH_RECTANGLE?5:d->control_count+(d->family==GX2D_SKETCH_PATH&&d->path_closed);gx2d_point previous=origin;long double sum_length=0,sum_area=0;
        for(segment=1;segment<vertices;++segment){
            if(d->family==GX2D_SKETCH_RECTANGLE)code=sketch_evaluate_valid(d,(double)segment/4,&p,NULL);
            else {p=sketch_world(d,d->controls[segment%d->control_count],0);code=finite2(p)?GX2D_OK:GX2D_RANGE;}
            if(code!=GX2D_OK)return code;sum_length+=dist(previous,p);
            if(closed)sum_area+=((long double)previous.x-origin.x)*((long double)p.y-origin.y)-((long double)p.x-origin.x)*((long double)previous.y-origin.y);
            previous=p;
        }
        double span=bounds.x1-bounds.x0,height=bounds.y1-bounds.y0;length=(double)sum_length;area=(double)(sum_area/2);
        if(!isfinite(span)||!isfinite(height)||!isfinite(length)||!isfinite(area))return GX2D_RANGE;
        *out=(gx2d_metrics){length,span,height,closed?area:0,span>0?length/span:0,closed};return GX2D_OK;
    }
    pieces=d->family==GX2D_SKETCH_RECTANGLE?4:d->family==GX2D_SKETCH_PATH?d->control_count-1+(size_t)d->path_closed:d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_SPLINE?d->control_count-1:1;
    for(subdivisions=1;subdivisions<=4096;subdivisions*=2){long double accumulated_length=0,accumulated_area=0;
        if(pieces>1000000/(8*subdivisions)||used>1000000-pieces*8*subdivisions)return GX2D_RANGE;
        used+=pieces*8*subdivisions;
        for(segment=0;segment<pieces;++segment)for(part=0;part<subdivisions;++part){
            double half=.5/(double)(pieces*subdivisions),middle=((double)segment+((double)part+.5)/subdivisions)/pieces;
            for(k=0;k<4;++k)for(sign=-1;sign<=1;sign+=2){
                code=sketch_evaluate_valid(d,middle+sign*half*nodes[k],&p,&v);if(code!=GX2D_OK)return code;
                accumulated_length+=(long double)half*weights[k]*hypot(v.x,v.y);
                if(closed)accumulated_area+=(long double)half*weights[k]*((long double)(p.x-origin.x)*v.y-(long double)(p.y-origin.y)*v.x)/2;
            }
        }
        length=(double)accumulated_length;area=(double)accumulated_area;
        if(!isfinite(length)||!isfinite(area))return GX2D_RANGE;
        if(previous_length>=0&&fabs(length-previous_length)<=1e-10*fmax(1,length)&&fabs(area-previous_area)<=1e-10*fmax(1,fabs(area))){
            double span=bounds.x1-bounds.x0,height=bounds.y1-bounds.y0;if(!isfinite(span)||!isfinite(height))return GX2D_RANGE;*out=(gx2d_metrics){length,span,height,closed?area:0,span>0?length/span:0,closed};return GX2D_OK;
        }
        previous_length=length;previous_area=area;
    }
    return GX2D_RANGE;
}

static gx2d_status sketch_construction_clip(const gx2d_scene *s,const gx2d_sketch_definition *d,gx2d_point out[2]) {
    gx2d_point a,v;gx2d_status code;double lo=-DBL_MAX,hi=DBL_MAX;size_t axis;
    code=sketch_evaluate_valid(d,0,&a,&v);if(code!=GX2D_OK)return code;
    if(v.x==0&&v.y==0)return GX2D_INVALID;
    for(axis=0;axis<2;++axis){double origin=axis?a.y:a.x,direction=axis?v.y:v.x,minimum=axis?s->view.world.y0:s->view.world.x0,maximum=axis?s->view.world.y1:s->view.world.x1;
        double first,last;
        if(direction==0){if(origin<minimum||origin>maximum)return GX2D_NOT_FOUND;continue;}
        first=(minimum-origin)/direction;last=(maximum-origin)/direction;if(first>last){double swap=first;first=last;last=swap;}
        if(first>lo)lo=first;if(last<hi)hi=last;if(lo>hi)return GX2D_NOT_FOUND;
    }
    code=sketch_evaluate_valid(d,lo,&out[0],NULL);if(code!=GX2D_OK)return code;return sketch_evaluate_valid(d,hi,&out[1],NULL);
}

gx2d_status gx2d_sketch_materialize(gx2d_scene *s,gx2d_id id,double first,double last,size_t total,gx2d_id *out) {
    const object *o=cobj(s,id);gx2d_point *points;size_t start;gx2d_status code;gx2d_direction_marker direction;
    if(!s||!out||!total||total>1000000)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    if(!o)return GX2D_NOT_FOUND;if(!o->sketch)return GX2D_INVALID;
    gx2d_sketch_definition chosen,parts[256];int reversed[256];
    const gx2d_sketch_definition *sampling=o->sketch;
    if(sketch_is_composition(o->sketch)) {
        int traversal;code=gx2d_composition_traversal(s,id,&traversal);
        if(code!=GX2D_OK)return code;if(traversal!=1)return GX2D_CONSTRAINT;
        chosen=*o->sketch;chosen.parts=parts;chosen.part_reversed=reversed;
        chosen.nodes=NULL;chosen.node_count=0;
        for(size_t i=0;i<chosen.part_count;i++) {
            size_t k=o->direction_marker.forward?i:chosen.part_count-1-i;
            parts[i]=o->sketch->parts[k];reversed[i]=!o->part_states[k].direction.forward;
            if(!o->direction_marker.forward)reversed[i]=!reversed[i];
        }
        sampling=&chosen;
    }
    points=(gx2d_point *)malloc(total*sizeof(*points));if(!points)return GX2D_NOMEM;
    for(start=0;start<total;start+=65536){size_t count=total-start;if(count>65536)count=65536;
        code=gx2d_sketch_sample(sampling,first,last,total,start,count,points+start,count);if(code!=GX2D_OK){free(points);return code;}}
    direction=o->direction_marker;direction.interpolation=0;
    if(sketch_is_composition(o->sketch))direction.forward=1;
    code=gx2d_add_geometry(s,total==1?GX2D_POINT_OBJECT:GX2D_CURVE,points,total,out);free(points);if(code==GX2D_OK&&total>1)obj(s,*out)->direction_marker=direction;return code;
}

static gx2d_status sketch_prefix_length(const gx2d_sketch_definition *d,double last,double *out) {
    static const double nodes[4]={.18343464249564980494,.52553240991632898582,.79666647741362673959,.96028985649753623168};
    static const double weights[4]={.36268378337836198297,.31370664587788728734,.22238103445337447054,.10122853629037625915};
    gx2d_point a,b,v;gx2d_status code;size_t pieces,segment,part,k,subdivisions,used=0;int sign;double previous=-1;
    if(d->family==GX2D_SKETCH_CONSTRUCTION_LINE)return GX2D_INVALID;
    pieces=d->family==GX2D_SKETCH_RECTANGLE?4:d->family==GX2D_SKETCH_PATH?d->control_count-1+(size_t)d->path_closed:d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_SPLINE?d->control_count-1:1;
    if(d->family==GX2D_SKETCH_LINE||d->family==GX2D_SKETCH_RECTANGLE||d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_PATH){long double length=0;
        code=sketch_evaluate_valid(d,0,&a,NULL);if(code!=GX2D_OK)return code;
        for(segment=0;segment<pieces&&(double)segment/pieces<last;++segment){double end=fmin(last,(double)(segment+1)/pieces);
            code=sketch_evaluate_valid(d,end,&b,NULL);if(code!=GX2D_OK)return code;length+=dist(a,b);a=b;}
        *out=(double)length;return isfinite(*out)?GX2D_OK:GX2D_RANGE;
    }
    for(subdivisions=1;subdivisions<=4096;subdivisions*=2){long double length=0;
        for(segment=0;segment<pieces&&(double)segment/pieces<last;++segment){
            double begin=(double)segment/pieces,end=fmin(last,(double)(segment+1)/pieces),half=(end-begin)/(2*subdivisions);
            if(used>1000000-8*subdivisions)return GX2D_RANGE;used+=8*subdivisions;
            for(part=0;part<subdivisions;++part){double middle=begin+(2*part+1)*half;
                for(k=0;k<4;++k)for(sign=-1;sign<=1;sign+=2){code=sketch_evaluate_valid(d,middle+sign*half*nodes[k],NULL,&v);if(code!=GX2D_OK)return code;length+=(long double)half*weights[k]*hypot(v.x,v.y);}}
        }
        double value=(double)length;if(!isfinite(value))return GX2D_RANGE;
        if(previous>=0&&fabs(value-previous)<=1e-10*fmax(1,value)){*out=value;return GX2D_OK;}previous=value;
    }
    return GX2D_RANGE;
}
static gx2d_status sketch_path_point(const object *o,double distance,gx2d_segment_hit *out) {
    gx2d_metrics metrics;gx2d_point p;gx2d_segment_hit result;gx2d_status code;double lo=0,hi=1,t=0,prefix,total,scaled;size_t iteration;
    if(o->sketch->family==GX2D_SKETCH_COMPOUND)return GX2D_INVALID;
    if(o->sketch->family==GX2D_SKETCH_COMPOSITE_PATH) {
        double traversed=0;
        for(size_t i=0;i<o->sketch->part_count;i++) {
            gx2d_sketch_definition part=o->sketch->parts[i];if(!sketch_compose(&part,o->sketch->matrix))return GX2D_RANGE;
            code=sketch_metrics(&part,&metrics);if(code!=GX2D_OK)return code;
            if(distance<=metrics.length||i+1==o->sketch->part_count){
                object child=*o;child.sketch=&part;double local=fmin(distance,metrics.length);
                code=sketch_path_point(&child,o->sketch->part_reversed[i]?metrics.length-local:local,&result);
                if(code==GX2D_OK){result.t=((double)result.segment+result.t)/(child.count-1);result.segment=i;result.t=o->sketch->part_reversed[i]?1-result.t:result.t;result.distance=traversed+local;*out=result;}return code;
            }
            distance-=metrics.length;traversed+=metrics.length;
        }
        return GX2D_RANGE;
    }
    code=sketch_metrics(o->sketch,&metrics);if(code!=GX2D_OK)return code;total=metrics.length;
    distance=fmin(distance,total);
    if(distance>=total)t=1;
    else if(distance>0)for(iteration=0;iteration<64;++iteration){t=(lo+hi)/2;code=sketch_prefix_length(o->sketch,t,&prefix);if(code!=GX2D_OK)return code;
        if(fabs(prefix-distance)<=1e-11*fmax(1,total))break;if(prefix<distance)lo=t;else hi=t;}
    code=sketch_evaluate_valid(o->sketch,t,&p,NULL);if(code!=GX2D_OK)return code;
    scaled=t*(o->count-1);result.segment=t==1?o->count-2:(size_t)scaled;result.t=scaled-result.segment;result.distance=distance;result.point=p;*out=result;return GX2D_OK;
}

/* Ordered-path services operate on retained topology, never display samples.
 * Join/Split return new candidates, leaving inputs, constraints and provenance
 * ownership intact. Callers adopt/remove inputs at their semantic undo boundary. */
gx2d_status gx2d_path_vertices(const gx2d_scene *s,gx2d_id id,int repeat,
        gx2d_point *out,size_t capacity,size_t *count){
    const object *o=cobj(s,id);size_t i,n;
    if(!s||!count||(repeat!=0&&repeat!=1))return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;if(!o->sketch||o->sketch->family!=GX2D_SKETCH_PATH)return GX2D_INVALID;
    n=o->sketch->control_count;size_t total=n+(repeat&&o->sketch->path_closed);
    if(out&&capacity<total)return GX2D_RANGE;
    for(i=0;out&&i<total;++i){size_t ordinal=i%n;
        if(!o->direction_marker.forward)ordinal=o->sketch->path_closed?(n-ordinal)%n:n-1-ordinal;
        out[i]=sketch_world(o->sketch,o->sketch->controls[ordinal],0);
    }
    *count=total;return GX2D_OK;
}
static gx2d_status path_linear_vertices(const object *o,int reversed,gx2d_point **out,size_t *count){
    if(!o||!o->sketch)return GX2D_INVALID;
    const gx2d_sketch_definition *d=o->sketch;
    if(d->family!=GX2D_SKETCH_LINE&&d->family!=GX2D_SKETCH_POLYLINE&&d->family!=GX2D_SKETCH_PATH)return GX2D_INVALID;
    if(d->path_closed)return GX2D_INVALID;
    gx2d_point *points=malloc(d->control_count*sizeof(*points));if(!points)return GX2D_NOMEM;
    for(size_t i=0;i<d->control_count;++i)points[i]=sketch_world(d,d->controls[reversed?d->control_count-1-i:i],0);
    *out=points;*count=d->control_count;return GX2D_OK;
}
gx2d_status gx2d_path_join(gx2d_scene *s,gx2d_id a,gx2d_id b,int reverse_a,int reverse_b,double tolerance,gx2d_id *out){
    if(!s||!out||a==b||(reverse_a!=0&&reverse_a!=1)||(reverse_b!=0&&reverse_b!=1)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    const object *oa=cobj(s,a),*ob=cobj(s,b);
    if(oa&&ob&&oa->sketch&&ob->sketch&&(oa->sketch->family!=GX2D_SKETCH_LINE&&oa->sketch->family!=GX2D_SKETCH_POLYLINE&&oa->sketch->family!=GX2D_SKETCH_PATH||ob->sketch->family!=GX2D_SKETCH_LINE&&ob->sketch->family!=GX2D_SKETCH_POLYLINE&&ob->sketch->family!=GX2D_SKETCH_PATH)) {
        gx2d_id ids[2]={a,b};int reversed[2]={reverse_a,reverse_b};return gx2d_composition_create(s,ids,reversed,2,1,tolerance,out);
    }
    gx2d_point *first=NULL,*last=NULL,*vertices=NULL;size_t n=0,m=0;gx2d_status code=path_linear_vertices(cobj(s,a),reverse_a,&first,&n);
    if(code==GX2D_OK)code=path_linear_vertices(cobj(s,b),reverse_b,&last,&m);
    if(code==GX2D_OK&&(n+m-1>65536||dist(first[n-1],last[0])>tolerance))code=GX2D_CONSTRAINT;
    if(code==GX2D_OK){vertices=malloc((n+m-1)*sizeof(*vertices));if(!vertices)code=GX2D_NOMEM;}
    if(code==GX2D_OK){memcpy(vertices,first,n*sizeof(*vertices));memcpy(vertices+n,last+1,(m-1)*sizeof(*vertices));
        gx2d_sketch_definition d;
        code=gx2d_sketch_construct(GX2D_SKETCH_PATH,vertices,n+m-1,&d,vertices,n+m-1);
        if(code==GX2D_OK)code=gx2d_sketch_create(s,&d,n+m-1,out);
    }
    free(first);free(last);free(vertices);return code;
}
gx2d_status gx2d_path_split(gx2d_scene *s,gx2d_id id,size_t vertex,gx2d_id out[2]){
    if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    const object *o=cobj(s,id);gx2d_point *points=NULL;size_t n=0;gx2d_status code;
    if(o&&o->sketch&&o->sketch->family==GX2D_SKETCH_PATH&&o->sketch->path_closed){
        n=o->sketch->control_count+1;points=malloc(n*sizeof(*points));if(!points)return GX2D_NOMEM;
        for(size_t i=0;i<n;++i)points[i]=sketch_world(o->sketch,o->sketch->controls[i%o->sketch->control_count],0);
        code=GX2D_OK;
    }else code=path_linear_vertices(o,0,&points,&n);
    if(code!=GX2D_OK)return code;
    if(vertex==0||vertex+1>=n){free(points);return GX2D_RANGE;}
    gx2d_sketch_definition d={0};d.family=GX2D_SKETCH_PATH;d.controls=points;d.control_count=vertex+1;d.matrix[0]=d.matrix[3]=1;
    gx2d_id parts[2];code=gx2d_sketch_create(s,&d,vertex+1,&parts[0]);
    if(code==GX2D_OK){d.controls=points+vertex;d.control_count=n-vertex;code=gx2d_sketch_create(s,&d,n-vertex,&parts[1]);
        if(code!=GX2D_OK)gx2d_delete_object(s,parts[0]);}
    if(code==GX2D_OK){out[0]=parts[0];out[1]=parts[1];}
    free(points);return code;
}

/* Flat exact leaves avoid recursive ownership/reference graphs. A composite's
 * affine frame is composed into each borrowed leaf before the candidate makes
 * its deep copy. Input actor lifetimes never become output dependencies. */
gx2d_status gx2d_composition_create(gx2d_scene *s,const gx2d_id *ids,const int *reverse,size_t count,int ordered,double tolerance,gx2d_id *out) {
    if(!s||!ids||!count||count>256||!out||ordered<0||ordered>2||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    gx2d_sketch_definition parts[256];gx2d_direction_marker markers[256];int reversed[256];size_t n=0;
    for(size_t i=0;i<count;i++) {
        for(size_t j=0;j<i;j++)if(ids[j]==ids[i])return GX2D_INVALID;
        const object *o=cobj(s,ids[i]);if(!o)return GX2D_NOT_FOUND;
        if(!o->sketch||o->reference_image)return GX2D_INVALID;
        const gx2d_sketch_definition *d=o->sketch;int rev=reverse?reverse[i]:0;
        if(rev!=0&&rev!=1)return GX2D_INVALID;
        if(ordered==2&&rev)return GX2D_INVALID; /* Automatic ordering owns orientation. */
        if(sketch_is_composition(d)) {
            if(ordered&&d->family==GX2D_SKETCH_COMPOUND)return GX2D_CONSTRAINT;
            if(n+d->part_count>256)return GX2D_RANGE;
            for(size_t j=0;j<d->part_count;j++) {size_t k=rev?d->part_count-1-j:j;parts[n]=d->parts[k];
                if(!sketch_compose(&parts[n],d->matrix))return GX2D_RANGE;
                markers[n]=o->part_states[k].direction;markers[n].forward=(markers[n].forward==o->direction_marker.forward)^rev;reversed[n++]=d->part_reversed[k]^rev;
            }
        } else {if(n==256)return GX2D_RANGE;parts[n]=*d;markers[n]=o->direction_marker;markers[n].forward^=rev;markers[n].visible=0;reversed[n++]=rev;}
    }
    gx2d_sketch_definition d={0};d.family=ordered?GX2D_SKETCH_COMPOSITE_PATH:GX2D_SKETCH_COMPOUND;
    d.matrix[0]=d.matrix[3]=1;d.parts=parts;d.part_reversed=reversed;d.part_count=n;d.join_tolerance=tolerance;
    if(ordered==2) {
        /* Canonical node IDs are frozen at composition, never inferred again
         * during editing. Equal coordinates later do not silently weld nodes. */
        object root={0};root.sketch=&d;size_t count=control_count(&root);if(count>65536)return GX2D_RANGE;
        size_t *nodes=malloc(count*sizeof(size_t));size_t owners[65536];int connected[256]={1};
        if(!nodes)return GX2D_NOMEM;
        size_t offset=0;for(size_t k=0;k<n;k++){object leaf={0};leaf.sketch=&parts[k];for(size_t j=0;j<control_count(&leaf);j++)owners[offset++]=k;}
        for(size_t i=0;i<count;i++){gx2d_point p,q;nodes[i]=i;control_point(&root,i,&p,NULL);
            for(size_t j=0;j<i;j++)if(owners[i]!=owners[j]){control_point(&root,j,&q,NULL);if(dist(p,q)<=tolerance){nodes[i]=nodes[j];break;}}
        }
        for(size_t pass=0;pass<n;pass++)for(size_t i=0;i<count;i++)if(connected[owners[i]]||connected[owners[nodes[i]]])connected[owners[i]]=connected[owners[nodes[i]]]=1;
        for(size_t i=0;i<n;i++)if(!connected[i]){free(nodes);return GX2D_CONSTRAINT;}
        d.nodes=nodes;d.node_count=count;
        gx2d_status code=gx2d_sketch_create(s,&d,257,out);if(code==GX2D_OK)for(size_t i=0;i<n;i++)obj(s,*out)->part_states[i].direction=markers[i];free(nodes);return code;
    }
    if(ordered){gx2d_point a,b;gx2d_sketch_evaluate(&parts[0],reversed[0]?1:0,&a,NULL);gx2d_sketch_evaluate(&parts[n-1],reversed[n-1]?0:1,&b,NULL);d.path_closed=dist(a,b)<=tolerance;}
    gx2d_status code=gx2d_sketch_create(s,&d,257,out);if(code==GX2D_OK)for(size_t i=0;i<n;i++)obj(s,*out)->part_states[i].direction=markers[i];return code;
}
gx2d_status gx2d_composition_part(const gx2d_scene *s,gx2d_id id,size_t index,gx2d_sketch_definition *out,int *reversed) {
    const object *o=cobj(s,id);if(!s||!out||!reversed)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(!sketch_is_composition(o->sketch)||index>=o->sketch->part_count)return GX2D_RANGE;
    gx2d_sketch_definition part=o->sketch->parts[index];if(!sketch_compose(&part,o->sketch->matrix))return GX2D_RANGE;
    *out=part;*reversed=o->sketch->part_reversed[index];return GX2D_OK;
}
gx2d_status gx2d_composition_split(gx2d_scene *s,gx2d_id id,size_t junction,gx2d_id out[2]) {
    const object *o=cobj(s,id);if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;if(!o)return GX2D_NOT_FOUND;
    if(!o->sketch||o->sketch->family!=GX2D_SKETCH_COMPOSITE_PATH||junction==0||junction>=o->sketch->part_count)return GX2D_RANGE;
    gx2d_sketch_definition first=*o->sketch,second=first;first.part_count=junction;first.path_closed=0;
    gx2d_direction_marker direction=o->direction_marker;gx2d_part_state saved_states[256];size_t saved_count=o->part_state_count;memcpy(saved_states,o->part_states,saved_count*sizeof(*saved_states));
    second.parts+=junction;second.part_reversed+=junction;second.part_count-=junction;second.path_closed=0;
    size_t *nodes=NULL;
    if(first.node_count){
        size_t offset=0;for(size_t k=0;k<junction;k++){object leaf={0};leaf.sketch=(gx2d_sketch_definition *)&first.parts[k];offset+=control_count(&leaf);}
        nodes=malloc(first.node_count*sizeof(size_t));if(!nodes)return GX2D_NOMEM;
        for(size_t i=0;i<first.node_count;i++){size_t start=i<offset?0:offset;nodes[i]=i-start;for(size_t j=start;j<i;j++)if(first.nodes[j]==first.nodes[i]){nodes[i]=nodes[j];break;}}
        second.nodes=nodes+offset;second.node_count=first.node_count-offset;first.nodes=nodes;first.node_count=offset;
    }
    gx2d_id result[2];gx2d_status code=gx2d_sketch_create(s,&first,257,&result[0]);
    if(code==GX2D_OK){code=gx2d_sketch_create(s,&second,257,&result[1]);if(code!=GX2D_OK)gx2d_delete_object(s,result[0]);}
    if(code==GX2D_OK){obj(s,result[0])->direction_marker=direction;obj(s,result[1])->direction_marker=direction;code=gx2d_composition_states_restore(s,result[0],saved_states,junction);if(code==GX2D_OK)code=gx2d_composition_states_restore(s,result[1],saved_states+junction,saved_count-junction);if(code==GX2D_OK){out[0]=result[0];out[1]=result[1];}else{gx2d_delete_object(s,result[0]);gx2d_delete_object(s,result[1]);}}free(nodes);return code;
}
gx2d_status gx2d_composition_explode(gx2d_scene *s,gx2d_id id,gx2d_id *out,size_t capacity,size_t *count) {
    const object *o=cobj(s,id);if(!s||!count)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(!sketch_is_composition(o->sketch))return GX2D_INVALID;size_t n=o->sketch->part_count;
    gx2d_direction_marker direction=o->direction_marker;gx2d_part_state saved_states[256];memcpy(saved_states,o->part_states,o->part_state_count*sizeof(*saved_states));
    if(!out){*count=n;return GX2D_OK;}if(capacity<n)return GX2D_RANGE;if(s->dragging)return GX2D_BUSY;
    gx2d_id result[256];gx2d_status code=GX2D_OK;size_t made=0;
    for(;made<n;made++){gx2d_sketch_definition part;int reverse;
        code=gx2d_composition_part(s,id,made,&part,&reverse);if(code!=GX2D_OK)break;
        code=gx2d_sketch_create(s,&part,257,&result[made]);if(code!=GX2D_OK)break;
        obj(s,result[made])->direction_marker=saved_states[made].direction;
        obj(s,result[made])->direction_marker.forward=saved_states[made].direction.forward==direction.forward;
    }
    if(code!=GX2D_OK){for(size_t i=0;i<made;i++)gx2d_delete_object(s,result[i]);return code;}
    memcpy(out,result,n*sizeof(*out));*count=n;return GX2D_OK;
}
