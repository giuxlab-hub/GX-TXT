/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Device-space tessellation queries exact retained definitions. Stored samples
 * are compatibility/picking proxies and never bound rendering fidelity. */
typedef struct {
    const gx2d_scene *scene; const gx2d_sketch_definition *definition;
    gx2d_point *points; uint64_t *indices; size_t count,budget,offset,proxy_count;
    double tolerance; int reversed;
} retained_display;
static gx2d_status retained_device(retained_display *r,double t,gx2d_point *p) {
    gx2d_point world;gx2d_status code=sketch_evaluate_valid(r->definition,t,&world,NULL);
    return code==GX2D_OK?gx2d_world_to_device(r->scene,world,p):code;
}
static gx2d_status retained_append(retained_display *r,double t,gx2d_point p) {
    if(r->count==r->budget)return GX2D_RANGE;
    if(r->points)r->points[r->count]=p;
    if(r->indices)r->indices[r->count]=r->offset+(uint64_t)llround((r->reversed?1-t:t)*(r->proxy_count-1));
    r->count++;return GX2D_OK;
}
static gx2d_status retained_interval(retained_display *r,double a,double b,gx2d_point pa,gx2d_point pb,unsigned depth) {
    gx2d_point p[3];double error=0;gx2d_status code;
    for(size_t i=0;i<3;i++) {
        double f=(i+1)*.25;code=retained_device(r,a+(b-a)*f,&p[i]);if(code!=GX2D_OK)return code;
        double dx=p[i].x-(pa.x+(pb.x-pa.x)*f),dy=p[i].y-(pa.y+(pb.y-pa.y)*f);
        error=fmax(error,hypot(dx,dy));
    }
    if(error<=r->tolerance||depth>=18)return retained_append(r,b,pb);
    code=retained_interval(r,a,(a+b)*.5,pa,p[1],depth+1);
    return code==GX2D_OK?retained_interval(r,(a+b)*.5,b,p[1],pb,depth+1):code;
}
static gx2d_status retained_leaf(retained_display *r) {
    const gx2d_sketch_definition *d=r->definition;size_t spans=1;gx2d_point a,b;gx2d_status code;
    if(d->family==GX2D_SKETCH_SPLINE||d->family==GX2D_SKETCH_PATH||d->family==GX2D_SKETCH_POLYLINE)spans=d->control_count-1+(d->family==GX2D_SKETCH_PATH&&d->path_closed);
    else if(d->family==GX2D_SKETCH_RECTANGLE)spans=4;
    else if(d->family==GX2D_SKETCH_CIRCLE||d->family==GX2D_SKETCH_ARC||d->family==GX2D_SKETCH_ELLIPSE)spans=16;
    double start=r->reversed?1:0;code=retained_device(r,start,&a);if(code!=GX2D_OK)return code;
    code=retained_append(r,start,a);if(code!=GX2D_OK)return code;
    if(d->family==GX2D_SKETCH_POINT)return GX2D_OK;
    for(size_t i=0;i<spans;i++) {
        double ta=(double)i/spans,tb=(double)(i+1)/spans;
        if(r->reversed){ta=1-ta;tb=1-tb;}
        code=retained_device(r,tb,&b);if(code!=GX2D_OK)return code;
        code=retained_interval(r,ta,tb,a,b,0);if(code!=GX2D_OK)return code;a=b;
    }
    return GX2D_OK;
}
static gx2d_status sketch_render_device(const gx2d_scene *s,const object *o,size_t budget,gx2d_point *out,uint64_t *indices,size_t capacity,size_t *count,size_t *cuts,size_t cut_capacity,size_t *ncuts) {
    size_t limit=out&&capacity<budget?capacity:budget;gx2d_status code=GX2D_OK;
    for(unsigned attempt=0;attempt<16;attempt++) {
        retained_display r={s,o->sketch,out,indices,0,limit,0,o->count,.35*pow(2,attempt),0};size_t ncuts_local=0;
        if(sketch_is_composition(o->sketch)) {
            size_t sizes[256],total,offset=0;code=composition_layout(o->sketch,o->count,sizes,&total);if(code!=GX2D_OK)return code;
            for(size_t i=0;i<o->sketch->part_count;i++) {
                gx2d_sketch_definition leaf=o->sketch->parts[i];if(!sketch_compose(&leaf,o->sketch->matrix))return GX2D_RANGE;
                if(i&&(o->sketch->family==GX2D_SKETCH_COMPOUND||o->sketch->node_count)) {
                    if(cuts&&ncuts_local<cut_capacity)cuts[ncuts_local]=r.count-1;ncuts_local++;
                }
                r.definition=&leaf;r.reversed=o->sketch->part_reversed[i];r.offset=offset;r.proxy_count=sizes[i];
                code=retained_leaf(&r);if(code!=GX2D_OK)break;
                offset+=sizes[i]-(o->sketch->family==GX2D_SKETCH_COMPOSITE_PATH&&!o->sketch->node_count&&i+1<o->sketch->part_count?1:0);
            }
        } else code=retained_leaf(&r);
        if(code==GX2D_OK) {*count=r.count;*ncuts=ncuts_local;return cuts&&ncuts_local>cut_capacity?GX2D_RANGE:GX2D_OK;}
        if(code!=GX2D_RANGE)return code;
    }
    /* More exact constituent boundaries than the requested budget: retain the
     * established ordered extrema display fallback, never alter definitions. */
    return GX2D_NOT_FOUND;
}
