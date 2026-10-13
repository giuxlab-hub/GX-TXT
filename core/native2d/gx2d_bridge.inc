/* Public endpoint topology and explicit C0/C1 gap bridges. */
gx2d_status gx2d_point_distance(gx2d_point a,gx2d_point b,double *value) {
    double d;if(!value||!finite2(a)||!finite2(b))return GX2D_INVALID;
    d=dist(a,b);if(!isfinite(d))return GX2D_RANGE;
    *value=d;return GX2D_OK;
}
gx2d_status gx2d_sample_spline_range(const gx2d_scene *s,gx2d_id id,
    size_t first,size_t segments,size_t per,gx2d_point *points,size_t capacity,size_t *count) {
    const object *o=cobj(s,id);size_t i,k,n;
    if(!s||!count||!per||per>4096||!segments)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE||first>=o->count-1||segments>o->count-1-first||
       segments>(SIZE_MAX-1)/per)return GX2D_RANGE;
    for(i=first;i<first+segments;++i)if(o->breaks[i])return GX2D_INVALID;
    n=segments*per+1;*count=n;
    if(!points)return GX2D_OK;
    if(capacity<n)return GX2D_RANGE;
    for(i=0;i<segments;++i)for(k=0;k<per;++k)
        points[i*per+k]=spline_at(o,first+i,(double)k/per);
    points[n-1]=o->points[first+segments];return GX2D_OK;
}
gx2d_status gx2d_sample_spline_object(gx2d_scene *s,gx2d_id id,size_t per,gx2d_id *out) {
    const object *o=cobj(s,id);gx2d_point *points;size_t n;gx2d_status code;
    if(!s||!out||!per||per>4096)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(s->dragging)return GX2D_BUSY;
    code=gx2d_sample_spline_range(s,id,0,o->count-1,per,NULL,0,&n);
    if(code!=GX2D_OK)return code;
    if(n>SIZE_MAX/sizeof(*points))return GX2D_RANGE;
    points=(gx2d_point *)malloc(n*sizeof(*points));if(!points)return GX2D_NOMEM;
    code=gx2d_sample_spline_range(s,id,0,o->count-1,per,points,n,&n);
    if(code==GX2D_OK)code=gx2d_add_geometry(s,GX2D_CURVE,points,n,out);
    free(points);return code;
}
gx2d_status gx2d_curve_point_frame(const gx2d_scene *s,gx2d_id id,
    size_t endpoint,int incoming,int reverse,int interpolation,gx2d_endpoint_frame *out) {
    const object *o=cobj(s,id);size_t left,right;gx2d_point d;
    if(!s||!out||(incoming!=0&&incoming!=1)||(reverse!=0&&reverse!=1)||
       (interpolation!=0&&interpolation!=1))return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE||o->count<2||endpoint>=o->count)return GX2D_INVALID;
    if((incoming&&(!endpoint||o->breaks[endpoint-1]))||
       (!incoming&&(endpoint+1>=o->count||o->breaks[endpoint])))return GX2D_INVALID;
    if(o->sketch){gx2d_point point;gx2d_status code;
        if(o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE)return GX2D_INVALID;
        code=gx2d_sketch_evaluate(o->sketch,(double)endpoint/(double)(o->count-1),&point,&d);if(code!=GX2D_OK)return code;
        if(reverse){d.x=-d.x;d.y=-d.y;}if(hypot(d.x,d.y)==0)return GX2D_INVALID;
        *out=(gx2d_endpoint_frame){point,d,endpoint};return GX2D_OK;
    }
    left=incoming?endpoint-1:endpoint;right=incoming?endpoint:endpoint+1;
    if(interpolation) {
        left=endpoint&&!o->breaks[endpoint-1]?endpoint-1:endpoint;
        right=endpoint+1<o->count&&!o->breaks[endpoint]?endpoint+1:endpoint;
    }
    d=(gx2d_point){o->points[right].x-o->points[left].x,
        o->points[right].y-o->points[left].y};
    if(interpolation){d.x*=.5;d.y*=.5;}
    if(reverse){d.x=-d.x;d.y=-d.y;}
    if(!finite2(d)||hypot(d.x,d.y)==0)return GX2D_INVALID;
    *out=(gx2d_endpoint_frame){o->points[endpoint],d,endpoint};
    return GX2D_OK;
}
gx2d_status gx2d_curve_endpoint_frame(const gx2d_scene *s,gx2d_id id,
    int end,int reverse,int interpolation,gx2d_endpoint_frame *out) {
    const object *o=cobj(s,id);int incoming=end!=reverse;
    if((end!=0&&end!=1)||(reverse!=0&&reverse!=1))return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    return gx2d_curve_point_frame(s,id,incoming?o->count-1:0,incoming,
        reverse,interpolation,out);
}
/* Scientific measurements/constraints evaluate the authoritative representation:
 * exact retained definitions or the selected segment of source rows. Display
 * interpolation is deliberately absent from this contract. Explicit callers
 * may still request interpolation through gx2d_curve_point_frame. */
static gx2d_status curve_authoritative_frame(const gx2d_scene *s,const object *o,
    size_t index,gx2d_endpoint_frame *out) {
    return gx2d_curve_point_frame(s,o->id,index,index==o->count-1,0,0,out);
}
static int bridge_tangent(gx2d_point a,gx2d_point b,double tol) {
    double na=hypot(a.x,a.y),nb=hypot(b.x,b.y);
    return na>0&&nb>0&&fabs((a.x/na)*(b.y/nb)-(a.y/na)*(b.x/nb))<=tol&&
        (a.x/na)*(b.x/nb)+(a.y/na)*(b.y/nb)>0;
}
gx2d_status gx2d_bridge_create(gx2d_scene *s,const gx2d_bridge_spec *spec,
    gx2d_id *out,gx2d_bridge_result *receipt) {
    gx2d_bridge_result r;gx2d_point a,b,u,v,*points;size_t i,n;gx2d_status code;
    double det,alpha,beta,dx,dy;
    if(!s||!spec||!out||!receipt||spec->kind<GX2D_BRIDGE_STRAIGHT||
       spec->kind>GX2D_BRIDGE_HERMITE||spec->subdivisions<1||
       spec->subdivisions>4096||!isfinite(spec->tolerance)||spec->tolerance<=0||
       spec->tolerance>1||!finite2(spec->start.point)||!finite2(spec->end.point)||
       !finite2(spec->start.derivative)||!finite2(spec->end.derivative))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    a=spec->start.point;b=spec->end.point;u=spec->start.derivative;v=spec->end.derivative;
    if(dist(a,b)==0||hypot(u.x,u.y)==0||hypot(v.x,v.y)==0)
        return GX2D_INVALID;
    memset(&r,0,sizeof(r));r.c0=1;r.controls[0]=a;
    if(spec->kind==GX2D_BRIDGE_STRAIGHT) {
        r.control_count=2;r.controls[1]=b;
    } else if(spec->kind==GX2D_BRIDGE_QUADRATIC) {
        /* Positive tangent-ray intersection. Parallel collinear rays permit
         * the midpoint; incompatible/negative intersections fail explicitly. */
        det=u.x*v.y-u.y*v.x;dx=b.x-a.x;dy=b.y-a.y;
        if(!isfinite(det))return GX2D_RANGE;
        if(fabs(det)<=DBL_EPSILON*hypot(u.x,u.y)*hypot(v.x,v.y)*16) {
            gx2d_point chord={dx,dy};
            if(!bridge_tangent(u,chord,spec->tolerance)||
               !bridge_tangent(v,chord,spec->tolerance))return GX2D_CONSTRAINT;
            r.controls[1]=(gx2d_point){a.x+dx*.5,a.y+dy*.5};
        } else {
            alpha=(dx*v.y-dy*v.x)/det;beta=(u.x*dy-u.y*dx)/det;
            if(!isfinite(alpha)||!isfinite(beta)||alpha<=0||beta<=0)
                return GX2D_CONSTRAINT;
            r.controls[1]=(gx2d_point){a.x+alpha*u.x,a.y+alpha*u.y};
        }
        r.control_count=3;r.controls[2]=b;
    } else {
        r.control_count=4;r.controls[1]=(gx2d_point){a.x+u.x/3,a.y+u.y/3};
        r.controls[2]=(gx2d_point){b.x-v.x/3,b.y-v.y/3};r.controls[3]=b;
    }
    for(i=0;i<r.control_count;++i)if(!finite2(r.controls[i]))return GX2D_RANGE;
    r.start_derivative=(gx2d_point){(r.control_count-1)*(r.controls[1].x-a.x),
        (r.control_count-1)*(r.controls[1].y-a.y)};
    r.end_derivative=(gx2d_point){(r.control_count-1)*(b.x-r.controls[r.control_count-2].x),
        (r.control_count-1)*(b.y-r.controls[r.control_count-2].y)};
    r.c1_start=dist(r.start_derivative,u)<=spec->tolerance;
    r.c1_end=dist(r.end_derivative,v)<=spec->tolerance;
    if(!finite2(r.start_derivative)||!finite2(r.end_derivative)||
       (spec->kind>=GX2D_BRIDGE_CUBIC&&(!r.c1_start||!r.c1_end)))return GX2D_RANGE;
    r.tangent_start=bridge_tangent(r.start_derivative,u,spec->tolerance);
    r.tangent_end=bridge_tangent(r.end_derivative,v,spec->tolerance);
    n=spec->subdivisions+1;points=(gx2d_point *)malloc(n*sizeof(*points));
    if(!points)return GX2D_NOMEM;
    for(i=0;i<n;++i) {
        gx2d_point q[4];size_t k,level;double t=(double)i/spec->subdivisions;
        memcpy(q,r.controls,r.control_count*sizeof(*q));
        for(level=r.control_count-1;level>0;--level)for(k=0;k<level;++k)
            q[k]=(gx2d_point){(1-t)*q[k].x+t*q[k+1].x,(1-t)*q[k].y+t*q[k+1].y};
        points[i]=q[0];
    }
    points[0]=a;points[n-1]=b;
    code=gx2d_add_geometry(s,GX2D_CURVE,points,n,out);free(points);
    if(code==GX2D_OK)*receipt=r;
    return code;
}
