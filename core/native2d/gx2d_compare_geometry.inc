/* SPDX-License-Identifier: GPL-3.0-or-later */
typedef struct {gx2d_point *points;size_t *cuts,count,ncuts;const char *policy;} comparison_sample;
static void comparison_sample_free(comparison_sample *s){free(s->points);free(s->cuts);memset(s,0,sizeof(*s));}
static gx2d_status comparison_sample_make(const gx2d_scene *s,const object *o,size_t budget,comparison_sample *out){
    gx2d_status code;size_t count=0,ncuts=0;
    memset(out,0,sizeof(*out));if(o->kind!=GX2D_CURVE||!o->count)return GX2D_INVALID;
    if(o->sketch&&o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE)return GX2D_INVALID;
    out->points=(gx2d_point *)calloc(budget,sizeof(gx2d_point));out->cuts=(size_t *)calloc(budget,sizeof(size_t));
    if(!out->points||!out->cuts){comparison_sample_free(out);return GX2D_NOMEM;}
    if(o->sketch){count=budget;code=gx2d_sketch_sample(o->sketch,0,1,budget,0,budget,out->points,budget);out->policy="retained_uniform_parameter_exact_evaluation";}
    else {code=gx2d_object_sample(s,o->id,budget,out->points,NULL,budget,&count,out->cuts,budget,&ncuts);out->policy=o->count<=budget?"complete_native_vertices_gap_aware":"native_extrema_preserving_vertices_gap_aware";}
    if(code!=GX2D_OK){comparison_sample_free(out);return code;}out->count=count;out->ncuts=ncuts;return GX2D_OK;
}
static int comparison_projection_exact(const object *o,size_t budget){
    if(!o->sketch)return o->count<=budget;
    if(o->sketch->family==GX2D_SKETCH_CIRCLE){double radius;return constraint_radius(o,&radius)==GX2D_OK;}
    if(o->sketch->family==GX2D_SKETCH_POLYLINE||o->sketch->family==GX2D_SKETCH_PATH)return o->sketch->control_count<=budget;
    return o->sketch->family==GX2D_SKETCH_LINE||o->sketch->family==GX2D_SKETCH_RECTANGLE;
}
static gx2d_status comparison_project(const gx2d_scene *s,const object *o,const comparison_sample *sample,int exact,gx2d_point point,gx2d_segment_hit *out){
    size_t i,cut=0;gx2d_point nearest;double best=DBL_MAX,d;
    if(exact)return gx2d_curve_nearest_point(s,o->id,point,out);
    if(!sample->count)return GX2D_INVALID;
    *out=(gx2d_segment_hit){0,0,dist(point,sample->points[0]),sample->points[0]};best=out->distance;
    for(i=0;i<sample->count;++i){
        d=dist(point,sample->points[i]);if(d<best){best=d;*out=(gx2d_segment_hit){i,0,d,sample->points[i]};}
        while(cut<sample->ncuts&&sample->cuts[cut]<i)++cut;
        if(i+1==sample->count||(cut<sample->ncuts&&sample->cuts[cut]==i))continue;
        nearest=nearest_segment(point,sample->points[i],sample->points[i+1]);d=dist(point,nearest);
        if(d<best){double length=dist(sample->points[i],sample->points[i+1]);best=d;*out=(gx2d_segment_hit){i,length?dist(sample->points[i],nearest)/length:0,d,nearest};}
    }
    return isfinite(best)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_compare_geometry(const gx2d_scene *s,gx2d_id a_id,gx2d_id b_id,size_t budget,gx2d_geometry_comparison *out,gx2d_residual *rows,size_t capacity){
    const object *a=cobj(s,a_id),*b=cobj(s,b_id);comparison_sample sa={0},sb={0};gx2d_geometry_comparison result={0};gx2d_residual *staged=NULL;gx2d_metrics ma,mb;gx2d_status code;size_t i,path_cut=0;long double sum=0,square=0,b_square=0;double b_max=0,closest=DBL_MAX,path=0;gx2d_segment_hit hit;
    if(!s||!out||budget<6||budget>4096)return GX2D_INVALID;if(!a||!b)return GX2D_NOT_FOUND;if(s->dragging)return GX2D_BUSY;
    code=comparison_sample_make(s,a,budget,&sa);if(code!=GX2D_OK)goto done;code=comparison_sample_make(s,b,budget,&sb);if(code!=GX2D_OK)goto done;
    if(rows&&capacity<sa.count){code=GX2D_RANGE;goto done;}
    staged=(gx2d_residual *)calloc(sa.count,sizeof(*staged));if(!staged){code=GX2D_NOMEM;goto done;}
    result.count_a=sa.count;result.count_b=sb.count;result.sampling_a=sa.policy;result.sampling_b=sb.policy;
    result.projection_exact_a=comparison_projection_exact(a,budget);result.projection_exact_b=comparison_projection_exact(b,budget);
    for(i=0;i<sa.count;++i){
        code=comparison_project(s,b,&sb,result.projection_exact_b,sa.points[i],&hit);if(code!=GX2D_OK)goto done;
        while(path_cut<sa.ncuts&&sa.cuts[path_cut]+1<i)++path_cut;
        if(i&&!(path_cut<sa.ncuts&&sa.cuts[path_cut]+1==i))path+=dist(sa.points[i-1],sa.points[i]);
        staged[i]=(gx2d_residual){path,hit.distance,hit.distance,sa.points[i],hit.point};sum+=hit.distance;square+=(long double)hit.distance*hit.distance;
        if(hit.distance>result.max_absolute){result.max_absolute=hit.distance;result.max_index=i;}
        if(hit.distance<closest){closest=hit.distance;result.closest_a=sa.points[i];result.closest_b=hit.point;}
    }
    for(i=0;i<sb.count;++i){
        code=comparison_project(s,a,&sa,result.projection_exact_a,sb.points[i],&hit);if(code!=GX2D_OK)goto done;
        b_square+=(long double)hit.distance*hit.distance;b_max=fmax(b_max,hit.distance);
        if(hit.distance<closest){closest=hit.distance;result.closest_a=hit.point;result.closest_b=sb.points[i];}
    }
    result.mean_absolute=(double)(sum/sa.count);result.rmse=sqrt((double)(square/sa.count));result.symmetric_rmse=sqrt((double)((square+b_square)/(sa.count+sb.count)));
    result.hausdorff_sampled=fmax(result.max_absolute,b_max);result.closest_distance=closest;
    /* Exact closest-boundary pairs are available for supported finite geometry;
     * the pair budget is checked before fallback to the explicit sample policy. */
    {gx2d_measurement closest_result={0};code=measurement_object_distance(s,a,b,1000000,&closest_result);
        if(code==GX2D_OK){result.closest_distance=closest_result.value;result.closest_a=closest_result.point_a;result.closest_b=closest_result.point_b;result.closest_exact=1;}
        else if(code!=GX2D_INVALID&&code!=GX2D_RANGE)goto done;}
    code=gx2d_curve_metrics(s,a_id,&ma);if(code!=GX2D_OK)goto done;code=gx2d_curve_metrics(s,b_id,&mb);if(code!=GX2D_OK)goto done;
    result.length_difference=mb.length-ma.length;result.area_supported=ma.closed&&mb.closed;result.area_difference=result.area_supported?mb.signed_area-ma.signed_area:0;
    if(!isfinite(result.rmse)||!isfinite(result.symmetric_rmse)||!isfinite(result.length_difference)||!isfinite(result.area_difference)){code=GX2D_RANGE;goto done;}
    if(rows)memcpy(rows,staged,sa.count*sizeof(*rows));*out=result;code=GX2D_OK;
done:free(staged);comparison_sample_free(&sa);comparison_sample_free(&sb);return code;
}
