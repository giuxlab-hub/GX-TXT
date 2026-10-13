/* SPDX-License-Identifier: GPL-3.0-or-later */
gx2d_status gx2d_curve_nearest_point(const gx2d_scene *s,gx2d_id id,gx2d_point query,gx2d_segment_hit *out) {
    const object *o=cobj(s,id);gx2d_segment_hit result;gx2d_status code;
    if(!s||!out||!finite2(query))return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch){const gx2d_sketch_definition *d=o->sketch;
        if(d->family==GX2D_SKETCH_CIRCLE){gx2d_point center;double radius,length;
            code=constraint_center(o,&center);if(code!=GX2D_OK)return code;code=constraint_radius(o,&radius);if(code!=GX2D_OK)return code;
            length=dist(query,center);if(length==0){code=sketch_evaluate_valid(d,0,&result.point,NULL);if(code!=GX2D_OK)return code;}
            else result.point=(gx2d_point){center.x+radius*(query.x-center.x)/length,center.y+radius*(query.y-center.y)/length};
            result.segment=0;result.t=0;result.distance=dist(query,result.point);*out=result;return GX2D_OK;
        }
        if(d->family==GX2D_SKETCH_POLYLINE||d->family==GX2D_SKETCH_PATH){double best=DBL_MAX;size_t i;
            for(i=0;i<d->control_count-1+(size_t)(d->family==GX2D_SKETCH_PATH&&d->path_closed);++i){gx2d_point a=sketch_world(d,d->controls[i],0),b=sketch_world(d,d->controls[(i+1)%d->control_count],0),q=nearest_segment(query,a,b);double distance=dist(query,q),length=dist(a,b);
                if(distance<best){best=distance;result=(gx2d_segment_hit){i,length>0?dist(a,q)/length:0,distance,q};}}
            if(!isfinite(best))return GX2D_RANGE;*out=result;return GX2D_OK;
        }
        if(d->family!=GX2D_SKETCH_LINE&&d->family!=GX2D_SKETCH_CONSTRUCTION_LINE&&d->family!=GX2D_SKETCH_RECTANGLE)return GX2D_INVALID;
    }
    return gx2d_nearest_segment(s,id,query,out);
}

static gx2d_status measurement_linear_edge(const object *o,size_t index,gx2d_point *a,gx2d_point *b) {
    if(o->sketch&&(o->sketch->family==GX2D_SKETCH_POLYLINE||o->sketch->family==GX2D_SKETCH_PATH)){*a=sketch_world(o->sketch,o->sketch->controls[index],0);*b=sketch_world(o->sketch,o->sketch->controls[(index+1)%o->sketch->control_count],0);}
    else {*a=o->points[index];*b=o->points[index+1];}
    return finite2(*a)&&finite2(*b)?GX2D_OK:GX2D_RANGE;
}
static gx2d_status measurement_linear_count(const object *o,size_t *count) {
    if(!o||o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch){gx2d_sketch_family family=o->sketch->family;
        if(family==GX2D_SKETCH_POLYLINE||family==GX2D_SKETCH_PATH){*count=o->sketch->control_count-1+(size_t)(family==GX2D_SKETCH_PATH&&o->sketch->path_closed);return GX2D_OK;}
        if(family!=GX2D_SKETCH_LINE&&family!=GX2D_SKETCH_RECTANGLE)return GX2D_INVALID;}
    *count=o->count-1;return GX2D_OK;
}
static double measurement_segment_pair(gx2d_point a,gx2d_point b,gx2d_point c,gx2d_point d,gx2d_point *pa,gx2d_point *pb) {
    long double ax=(long double)b.x-a.x,ay=(long double)b.y-a.y,bx=(long double)d.x-c.x,by=(long double)d.y-c.y,den=ax*by-ay*bx;
    gx2d_point q;double best=DBL_MAX,value;size_t i;
    if(den!=0){long double dx=(long double)c.x-a.x,dy=(long double)c.y-a.y,t=(dx*by-dy*bx)/den,u=(dx*ay-dy*ax)/den;
        if(t>=0&&t<=1&&u>=0&&u<=1){*pa=*pb=(gx2d_point){(double)((long double)a.x+t*ax),(double)((long double)a.y+t*ay)};return 0;}}
    gx2d_point endpoints[4]={a,b,c,d};
    for(i=0;i<4;++i){q=i<2?nearest_segment(endpoints[i],c,d):nearest_segment(endpoints[i],a,b);value=dist(endpoints[i],q);
        if(value<best){best=value;*pa=i<2?endpoints[i]:q;*pb=i<2?q:endpoints[i];}}
    return best;
}
static gx2d_status measurement_object_distance(const gx2d_scene *s,const object *a,const object *b,size_t budget,gx2d_measurement *out) {
    double ra,rb;gx2d_point ca,cb;gx2d_status ar=constraint_radius(a,&ra),br=constraint_radius(b,&rb);size_t na,nb,i,j,pairs=0;double best=DBL_MAX;gx2d_point best_a={0,0},best_b={0,0};
    if(!a||!b)return GX2D_INVALID;if(!budget)budget=1000000;if(budget>1000000)return GX2D_RANGE;
    if(!a->sketch||a->sketch->family!=GX2D_SKETCH_CIRCLE)ar=GX2D_INVALID;
    if(!b->sketch||b->sketch->family!=GX2D_SKETCH_CIRCLE)br=GX2D_INVALID;
    if(ar==GX2D_OK&&br==GX2D_OK){double length,ux,uy,h,height;
        if(constraint_center(a,&ca)!=GX2D_OK||constraint_center(b,&cb)!=GX2D_OK)return GX2D_INVALID;
        length=dist(ca,cb);if(!isfinite(length))return GX2D_RANGE;ux=length>0?(cb.x-ca.x)/length:1;uy=length>0?(cb.y-ca.y)/length:0;
        if(length>ra+rb){best_a=(gx2d_point){ca.x+ra*ux,ca.y+ra*uy};best_b=(gx2d_point){cb.x-rb*ux,cb.y-rb*uy};best=length-ra-rb;}
        else if(length<fabs(ra-rb)||length==0){double sign=ra>=rb?1:-1;best_a=(gx2d_point){ca.x+sign*ra*ux,ca.y+sign*ra*uy};best_b=(gx2d_point){cb.x+sign*rb*ux,cb.y+sign*rb*uy};best=fabs(ra-rb)-length;}
        else {h=(double)(((long double)ra*ra-(long double)rb*rb+(long double)length*length)/(2*length));height=sqrt(fmax(0,ra*ra-h*h));best_a=best_b=(gx2d_point){ca.x+h*ux-height*uy,ca.y+h*uy+height*ux};best=0;}
        out->policy="native_analytic_circle_boundary_pair";
    } else if(a->kind==GX2D_POINT_OBJECT||b->kind==GX2D_POINT_OBJECT){const object *point=a->kind==GX2D_POINT_OBJECT?a:b,*other=point==a?b:a;gx2d_segment_hit nearest;
        best_a=point->points[0];if(other->kind==GX2D_POINT_OBJECT){best_b=other->points[0];best=dist(best_a,best_b);}
        else {gx2d_status code=gx2d_curve_nearest_point(s,other->id,best_a,&nearest);if(code!=GX2D_OK)return code;best_b=nearest.point;best=nearest.distance;}
        if(point==b){gx2d_point swap=best_a;best_a=best_b;best_b=swap;}out->policy="native_exact_point_supported_curve_pair";
    } else {
        if(measurement_linear_count(a,&na)!=GX2D_OK||measurement_linear_count(b,&nb)!=GX2D_OK)return GX2D_INVALID;
        if(!na||!nb||na>budget/nb)return GX2D_RANGE;
        for(i=0;i<na;++i){gx2d_point aa,ab;if(!a->sketch&&a->breaks[i])continue;if(measurement_linear_edge(a,i,&aa,&ab)!=GX2D_OK)return GX2D_RANGE;
            for(j=0;j<nb;++j){gx2d_point ba,bb,pa,pb;double value;if(!b->sketch&&b->breaks[j])continue;if(++pairs>budget)return GX2D_RANGE;
                if(measurement_linear_edge(b,j,&ba,&bb)!=GX2D_OK)return GX2D_RANGE;value=measurement_segment_pair(aa,ab,ba,bb,&pa,&pb);
                if(value<best){best=value;best_a=pa;best_b=pb;}}}
        out->policy="native_complete_supported_segment_pairs";
    }
    if(!isfinite(best)||best==DBL_MAX||!finite2(best_a)||!finite2(best_b))return GX2D_RANGE;
    out->value=fmax(0,best);out->point_a=best_a;out->point_b=best_b;return GX2D_OK;
}
gx2d_status gx2d_measure(const gx2d_scene *s,const gx2d_measurement_spec *spec,gx2d_measurement *out) {
    const object *a,*b;gx2d_measurement result;gx2d_metrics metrics;gx2d_rect bounds;gx2d_status code;
    gx2d_point pa={0,0},pb={0,0},qa,qb,da,db;gx2d_endpoint_frame fa,fb;gx2d_segment_hit nearest;double ra,rb;
    if(!s||!spec||!out||spec->kind<GX2D_MEASURE_POINT_DISTANCE||spec->kind>GX2D_MEASURE_OBJECT_DISTANCE)return GX2D_INVALID;
    a=cobj(s,spec->a);b=cobj(s,spec->b);if(!a||a->kind==GX2D_GROUP)return GX2D_INVALID;
    memset(&result,0,sizeof(result));result.unit_power=1;result.exact=1;result.policy="native_exact_geometry";
    switch(spec->kind){
        case GX2D_MEASURE_OBJECT_DISTANCE:
            code=measurement_object_distance(s,a,b,spec->pair_budget,&result);if(code!=GX2D_OK)return code;*out=result;return GX2D_OK;
        case GX2D_MEASURE_POINT_DISTANCE:case GX2D_MEASURE_HORIZONTAL_DISTANCE:case GX2D_MEASURE_VERTICAL_DISTANCE:
            code=constraint_point(a,spec->a_index,&pa);if(code!=GX2D_OK)return code;code=constraint_point(b,spec->b_index,&pb);if(code!=GX2D_OK)return code;
            result.value=spec->kind==GX2D_MEASURE_POINT_DISTANCE?dist(pa,pb):spec->kind==GX2D_MEASURE_HORIZONTAL_DISTANCE?fabs(pa.x-pb.x):fabs(pa.y-pb.y);break;
        case GX2D_MEASURE_SEGMENT_LENGTH:
            if(a->sketch&&a->sketch->family!=GX2D_SKETCH_CONSTRUCTION_LINE){double first,last;
                if(a->kind!=GX2D_CURVE||spec->a_index+1>=a->count)return GX2D_INVALID;
                code=sketch_prefix_length(a->sketch,(double)spec->a_index/(a->count-1),&first);if(code!=GX2D_OK)return code;
                code=sketch_prefix_length(a->sketch,(double)(spec->a_index+1)/(a->count-1),&last);if(code!=GX2D_OK)return code;
                result.value=last-first;result.exact=0;result.policy="native_retained_parameter_interval_arclength";
                code=sketch_evaluate_valid(a->sketch,(double)spec->a_index/(a->count-1),&pa,NULL);if(code!=GX2D_OK)return code;
                code=sketch_evaluate_valid(a->sketch,(double)(spec->a_index+1)/(a->count-1),&pb,NULL);if(code!=GX2D_OK)return code;break;
            }
            code=constraint_segment(a,spec->a_index,&pa,&pb,&da);if(code!=GX2D_OK)return code;result.value=dist(pa,pb);result.policy="native_exact_selected_segment";break;
        case GX2D_MEASURE_SEGMENT_ANGLE:
            code=constraint_segment(a,spec->a_index,&pa,&qa,&da);if(code!=GX2D_OK)return code;code=constraint_segment(b,spec->b_index,&pb,&qb,&db);if(code!=GX2D_OK)return code;
            result.value=atan2(da.x*db.y-da.y*db.x,da.x*db.x+da.y*db.y);result.angular=1;result.unit_power=0;break;
        case GX2D_MEASURE_TANGENT_ANGLE:
            if(!b||a->kind!=GX2D_CURVE||b->kind!=GX2D_CURVE)return GX2D_INVALID;
            code=curve_authoritative_frame(s,a,spec->a_index,&fa);if(code!=GX2D_OK)return code;
            code=curve_authoritative_frame(s,b,spec->b_index,&fb);if(code!=GX2D_OK)return code;
            ra=hypot(fa.derivative.x,fa.derivative.y);rb=hypot(fb.derivative.x,fb.derivative.y);if(!ra||!rb)return GX2D_INVALID;
            da=(gx2d_point){fa.derivative.x/ra,fa.derivative.y/ra};db=(gx2d_point){fb.derivative.x/rb,fb.derivative.y/rb};
            result.value=atan2(da.x*db.y-da.y*db.x,da.x*db.x+da.y*db.y);pa=fa.point;pb=fb.point;result.angular=1;result.unit_power=0;result.policy="native_curve_derivatives";break;
        case GX2D_MEASURE_PATH_LENGTH:case GX2D_MEASURE_SIGNED_AREA:
            code=gx2d_curve_metrics(s,a->id,&metrics);if(code!=GX2D_OK)return code;
            if(spec->kind==GX2D_MEASURE_SIGNED_AREA&&!metrics.closed)return GX2D_INVALID;
            result.value=spec->kind==GX2D_MEASURE_PATH_LENGTH?metrics.length:metrics.signed_area;result.unit_power=spec->kind==GX2D_MEASURE_SIGNED_AREA?2:1;
            if(a->sketch&&a->sketch->family>=GX2D_SKETCH_CIRCLE&&a->sketch->family!=GX2D_SKETCH_POLYLINE&&a->sketch->family!=GX2D_SKETCH_PATH){result.exact=0;result.policy="native_definition_piecewise_gauss8_refinement_1e-10";}
            else result.policy="native_complete_linear_segments";break;
        case GX2D_MEASURE_RADIUS:case GX2D_MEASURE_DIAMETER:
            code=constraint_radius(a,&result.value);if(code!=GX2D_OK)return code;if(spec->kind==GX2D_MEASURE_DIAMETER)result.value*=2;
            code=constraint_center(a,&pa);if(code!=GX2D_OK)return code;break;
        case GX2D_MEASURE_ARC_ANGLE:
            if(!a->sketch||a->sketch->family!=GX2D_SKETCH_ARC)return GX2D_INVALID;
            result.value=a->sketch->angle_sweep;if(a->sketch->matrix[0]*a->sketch->matrix[3]-a->sketch->matrix[1]*a->sketch->matrix[2]<0)result.value=-result.value;
            result.angular=1;result.unit_power=0;break;
        case GX2D_MEASURE_BOUNDING_WIDTH:case GX2D_MEASURE_BOUNDING_HEIGHT:
            code=gx2d_object_bounds(s,a->id,&bounds);if(code!=GX2D_OK)return code;
            result.value=spec->kind==GX2D_MEASURE_BOUNDING_WIDTH?bounds.x1-bounds.x0:bounds.y1-bounds.y0;pa=(gx2d_point){bounds.x0,bounds.y0};pb=(gx2d_point){bounds.x1,bounds.y1};break;
        case GX2D_MEASURE_POINT_CURVE_DISTANCE:
            code=constraint_point(a,spec->a_index,&pa);if(code!=GX2D_OK)return code;if(!b)return GX2D_INVALID;
            code=gx2d_curve_nearest_point(s,b->id,pa,&nearest);if(code!=GX2D_OK)return code;result.value=nearest.distance;pb=nearest.point;result.policy="native_exact_supported_projection";break;
        default:return GX2D_INVALID;
    }
    if(!isfinite(result.value)||!finite2(pa)||!finite2(pb))return GX2D_RANGE;
    result.point_a=pa;result.point_b=pb;*out=result;return GX2D_OK;
}
