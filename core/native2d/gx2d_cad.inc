/* Reference rasters support orientation-preserving similarity transforms;
 * arbitrary affine stretching/reflection would falsify calibration. */
static int cad_image_matrix(const double m[6]) {
    double a=hypot(m[0],m[2]),b=hypot(m[1],m[3]);
    return a>0&&fabs(a-b)<=1e-10*fmax(1,a)&&fabs(m[0]*m[1]+m[2]*m[3])<=1e-10*fmax(1,a*a)&&m[0]*m[3]-m[1]*m[2]>0;
}
/* Native object/container transforms. No host geometry calculations. */
gx2d_status gx2d_group_contains(const gx2d_scene *s,gx2d_id group,gx2d_id member,int *found) {
    const object *g=cobj(s,group);if(!s||!found||!member)return GX2D_INVALID;
    if(!g)return GX2D_NOT_FOUND;if(g->kind!=GX2D_GROUP)return GX2D_INVALID;
    *found=group_contains(g,member);return GX2D_OK;
}
gx2d_status gx2d_group_add_member(gx2d_scene *s,gx2d_id group,gx2d_id member) {
    object *g=obj(s,group);const object *m=cobj(s,member);gx2d_id *ids;
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    if(!g||!m)return GX2D_NOT_FOUND;
    if(g->kind!=GX2D_GROUP||m->kind==GX2D_GROUP)return GX2D_INVALID;
    if(!can_move(s,g))return GX2D_LOCKED;
    if(group_contains(g,member))return GX2D_OK;
    if(g->member_count==SIZE_MAX/sizeof(*ids))return GX2D_RANGE;
    ids=(gx2d_id *)realloc(g->members,(g->member_count+1)*sizeof(*ids));
    if(!ids)return GX2D_NOMEM;g->members=ids;g->members[g->member_count++]=member;return GX2D_OK;
}
gx2d_status gx2d_group_remove_member(gx2d_scene *s,gx2d_id group,gx2d_id member) {
    object *g=obj(s,group);size_t i;
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    if(!g)return GX2D_NOT_FOUND;if(g->kind!=GX2D_GROUP)return GX2D_INVALID;
    if(!can_move(s,g))return GX2D_LOCKED;
    for(i=0;i<g->member_count&&g->members[i]!=member;++i){}
    if(i==g->member_count)return GX2D_NOT_FOUND;
    if(g->member_count==1)return gx2d_delete_object(s,group);
    memmove(g->members+i,g->members+i+1,(g->member_count-i-1)*sizeof(*g->members));
    --g->member_count;return GX2D_OK;
}
gx2d_status gx2d_ungroup(gx2d_scene *s,gx2d_id group) {
    object *g=obj(s,group);if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    if(!g)return GX2D_NOT_FOUND;if(g->kind!=GX2D_GROUP)return GX2D_INVALID;
    if(!can_move(s,g))return GX2D_LOCKED;return gx2d_delete_object(s,group);
}
static gx2d_status cad_expand(const gx2d_scene *s,const gx2d_id *input,size_t n,
    gx2d_id **result,size_t *count) {
    size_t i,j,k,total=0;gx2d_id *ids;
    if(!s||!input||!n||n>65536||!result||!count)return GX2D_INVALID;
    for(i=0;i<n;++i) {
        const object *o=cobj(s,input[i]);size_t add;
        if(!o)return GX2D_NOT_FOUND;add=o->kind==GX2D_GROUP?o->member_count:1;
        if(add>65536-total)return GX2D_RANGE;total+=add;
    }
    if(!total)return GX2D_INVALID;
    ids=(gx2d_id *)malloc(total*sizeof(*ids));if(!ids)return GX2D_NOMEM;
    total=0;
    for(i=0;i<n;++i) {
        const object *o=cobj(s,input[i]);size_t members=o->kind==GX2D_GROUP?o->member_count:1;
        for(j=0;j<members;++j) {
            gx2d_id id=o->kind==GX2D_GROUP?o->members[j]:o->id;
            for(k=0;k<total&&ids[k]!=id;++k){}
            if(k==total)ids[total++]=id;
        }
    }
    *result=ids;*count=total;return GX2D_OK;
}
gx2d_status gx2d_expand_objects(const gx2d_scene *s,const gx2d_id *input,size_t n,
    gx2d_id *out,size_t capacity,size_t *count) {
    gx2d_id *ids;gx2d_status code;size_t total;
    if(!count)return GX2D_INVALID;code=cad_expand(s,input,n,&ids,&total);
    if(code!=GX2D_OK)return code;*count=total;
    if(out&&capacity<total){free(ids);return GX2D_RANGE;}
    if(out)memcpy(out,ids,total*sizeof(*out));free(ids);return GX2D_OK;
}
static int cad_matrix_valid(const double *m) {size_t i;if(!m)return 0;for(i=0;i<6;++i)if(!isfinite(m[i]))return 0;return 1;}
static gx2d_status cad_points(const object *o,const double *m,gx2d_point **result) {
    size_t j;gx2d_point *points=(gx2d_point *)malloc(o->count*sizeof(*points));
    if(!points)return GX2D_NOMEM;
    for(j=0;j<o->count;++j) {
        long double x=(long double)m[0]*o->points[j].x+(long double)m[1]*o->points[j].y+m[4];
        long double y=(long double)m[2]*o->points[j].x+(long double)m[3]*o->points[j].y+m[5];
        points[j]=(gx2d_point){(double)x,(double)y};
        if(!finite2(points[j])){free(points);return GX2D_RANGE;}
    }
    *result=points;return GX2D_OK;
}
gx2d_status gx2d_affine_objects(gx2d_scene *s,const gx2d_id *input,size_t n,const double m[6]) {
    gx2d_id *ids=NULL;gx2d_point **old=NULL,**next=NULL;gx2d_sketch_definition *definitions=NULL,*previous_definitions=NULL;size_t total=0,i;gx2d_status code;
    if(!s||!input||!n||n>65536||!cad_matrix_valid(m))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    for(i=0;i<n;++i){const object *o=cobj(s,input?input[i]:0);if(o&&!can_move(s,o))return GX2D_LOCKED;}
    code=cad_expand(s,input,n,&ids,&total);if(code!=GX2D_OK)return code;
    old=(gx2d_point **)calloc(total,sizeof(*old));next=(gx2d_point **)calloc(total,sizeof(*next));
    definitions=(gx2d_sketch_definition *)calloc(total,sizeof(*definitions));
    previous_definitions=(gx2d_sketch_definition *)calloc(total,sizeof(*previous_definitions));
    if(!old||!next||!definitions||!previous_definitions){code=GX2D_NOMEM;goto done;}
    for(i=0;i<total;++i) {
        object *o=obj(s,ids[i]);if(o->reference_image&&!cad_image_matrix(m)){code=GX2D_INVALID;goto done;}if(!can_move(s,o)){code=GX2D_LOCKED;goto done;}
        code=cad_points(o,m,&next[i]);if(code!=GX2D_OK)goto done;old[i]=o->points;
        if(o->sketch){previous_definitions[i]=definitions[i]=*o->sketch;if(!sketch_compose(&definitions[i],m)){code=GX2D_RANGE;goto done;}}
    }
    for(i=0;i<total;++i){object *o=obj(s,ids[i]);o->points=next[i];if(o->sketch)*o->sketch=definitions[i];}
    code=gx2d_check_constraints(s);
    if(code!=GX2D_OK){for(i=0;i<total;++i){object *o=obj(s,ids[i]);o->points=old[i];if(o->sketch)*o->sketch=previous_definitions[i];}}
    else {for(i=0;i<total;++i){object *o=obj(s,ids[i]);o->capacity=o->count;if(o->sketch)*o->sketch=definitions[i];free(old[i]);next[i]=NULL;}}
done:
    if(next){for(i=0;i<total;++i)free(next[i]);}free(previous_definitions);free(definitions);free(next);free(old);free(ids);return code;
}
gx2d_status gx2d_copy_affine_objects(gx2d_scene *s,const gx2d_id *input,size_t n,
    const double m[6],gx2d_id *out,size_t capacity,size_t *count) {
    gx2d_id *ids=NULL,*created=NULL;object *copies=NULL;size_t total=0,i,committed=0;gx2d_status code;
    if(!s||!count||!cad_matrix_valid(m))return GX2D_INVALID;
    code=cad_expand(s,input,n,&ids,&total);if(code!=GX2D_OK)return code;*count=total;
    if(!out){free(ids);return GX2D_OK;}
    if(s->dragging){free(ids);return GX2D_BUSY;}
    if(capacity<total){free(ids);return GX2D_RANGE;}
    copies=(object *)calloc(total,sizeof(*copies));created=(gx2d_id *)calloc(total,sizeof(*created));
    if(!copies||!created){code=GX2D_NOMEM;goto done;}
    for(i=0;i<total;++i) {
        const object *o=cobj(s,ids[i]);object *copy=&copies[i];
        if(o->reference_image&&!cad_image_matrix(m)){code=GX2D_INVALID;goto done;}
        *copy=*o;copy->id=0;copy->points=NULL;copy->manual=NULL;copy->breaks=NULL;
        copy->sketch=NULL;copy->part_states=NULL;
        if(o->part_state_count){copy->part_states=malloc(o->part_state_count*sizeof(*copy->part_states));if(!copy->part_states){code=GX2D_NOMEM;goto done;}memcpy(copy->part_states,o->part_states,o->part_state_count*sizeof(*copy->part_states));}
        if(o->sketch){copy->sketch=sketch_clone(o->sketch);if(!copy->sketch){code=GX2D_NOMEM;goto done;}if(!sketch_compose(copy->sketch,m)){code=GX2D_RANGE;goto done;}}
        copy->capacity=copy->count;
        copy->members=NULL;copy->member_count=0;copy->style.selected=0;
        code=cad_points(o,m,&copy->points);if(code!=GX2D_OK)goto done;
        copy->manual=(unsigned char *)calloc(o->count,1);copy->breaks=(unsigned char *)malloc(o->count);
        if(!copy->manual||!copy->breaks){code=GX2D_NOMEM;goto done;}
        memcpy(copy->breaks,o->breaks,o->count);
    }
    for(i=0;i<total;++i) {
        code=append_object(s,copies[i],&created[i]);if(code!=GX2D_OK)goto done;
        ++committed;copies[i].points=NULL;copies[i].manual=NULL;copies[i].breaks=NULL;copies[i].sketch=NULL;copies[i].part_states=NULL;
        code=identity_copy_all(s,ids[i],created[i]);if(code!=GX2D_OK)goto done;
    }
    memcpy(out,created,total*sizeof(*out));code=GX2D_OK;
done:
    if(code!=GX2D_OK)while(committed){--committed;gx2d_delete_object(s,created[committed]);}
    if(copies){for(i=0;i<total;++i){free(copies[i].points);free(copies[i].manual);free(copies[i].breaks);sketch_free(copies[i].sketch);free(copies[i].part_states);}}
    free(copies);free(created);free(ids);return code;
}
gx2d_status gx2d_reflection_matrix(gx2d_point a,gx2d_point b,double m[6]) {
    long double dx,dy,length,u,v;double result[6];size_t i;
    if(!m||!finite2(a)||!finite2(b))return GX2D_INVALID;
    dx=(long double)b.x-a.x;dy=(long double)b.y-a.y;length=hypotl(dx,dy);
    if(length==0)return GX2D_INVALID;if(!isfinite(length))return GX2D_RANGE;
    u=dx/length;v=dy/length;
    result[0]=(double)(2*u*u-1);result[1]=(double)(2*u*v);result[2]=result[1];result[3]=(double)(2*v*v-1);
    result[4]=(double)((long double)a.x-result[0]*(long double)a.x-result[1]*(long double)a.y);
    result[5]=(double)((long double)a.y-result[2]*(long double)a.x-result[3]*(long double)a.y);
    for(i=0;i<6;++i)if(!isfinite(result[i]))return GX2D_RANGE;
    memcpy(m,result,sizeof(result));return GX2D_OK;
}
gx2d_status gx2d_pivot_set(gx2d_scene *s,gx2d_pivot_mode mode,gx2d_point custom) {
    if(!s||mode<GX2D_PIVOT_BOUNDS||mode>GX2D_PIVOT_CUSTOM||!finite2(custom))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;s->pivot_mode=mode;s->custom_pivot=custom;return GX2D_OK;
}
gx2d_status gx2d_rotation_matrix(gx2d_point p,double radians,double m[6]) {
    double result[6],co,si;size_t i;
    if(!m||!finite2(p)||!isfinite(radians))return GX2D_INVALID;
    co=cos(radians);si=sin(radians);result[0]=co;result[1]=-si;result[2]=si;result[3]=co;
    result[4]=(double)((long double)p.x-co*(long double)p.x+si*(long double)p.y);
    result[5]=(double)((long double)p.y-si*(long double)p.x-co*(long double)p.y);
    for(i=0;i<6;++i)if(!isfinite(result[i]))return GX2D_RANGE;
    memcpy(m,result,sizeof(result));return GX2D_OK;
}
gx2d_status gx2d_scaling_matrix(gx2d_point p,gx2d_point scale,double m[6]) {
    double result[6];size_t i;
    if(!m||!finite2(p)||!finite2(scale))return GX2D_INVALID;
    result[0]=scale.x;result[1]=0;result[2]=0;result[3]=scale.y;
    result[4]=(double)((long double)p.x-scale.x*(long double)p.x);
    result[5]=(double)((long double)p.y-scale.y*(long double)p.y);
    for(i=0;i<6;++i)if(!isfinite(result[i]))return GX2D_RANGE;
    memcpy(m,result,sizeof(result));return GX2D_OK;
}
gx2d_status gx2d_pivot_get(const gx2d_scene *s,gx2d_pivot_mode *mode,gx2d_point *point) {
    size_t i,j,count=0;int found=0;gx2d_rect bounds={0,0,0,0};long double cx=0,cy=0;
    if(!s||!mode||!point)return GX2D_INVALID;*mode=s->pivot_mode;
    if(s->dragging){*point=s->drag_pivot;return GX2D_OK;}
    if(s->pivot_mode==GX2D_PIVOT_ORIGIN){*point=(gx2d_point){0,0};return GX2D_OK;}
    if(s->pivot_mode==GX2D_PIVOT_CUSTOM){*point=s->custom_pivot;return GX2D_OK;}
    for(i=0;i<s->object_count;++i) {
        const object *o=&s->objects[i];
        for(j=0;j<o->count;++j)if(selected_at(s,o,j)) {
            ++count;include_point(&bounds,o->points[j],&found);
            cx+=(long double)o->points[j].x/count-cx/count;
            cy+=(long double)o->points[j].y/count-cy/count;
        }
    }
    if(!found)return GX2D_NOT_FOUND;
    *point=s->pivot_mode==GX2D_PIVOT_CENTROID?(gx2d_point){(double)cx,(double)cy}:
        (gx2d_point){bounds.x0*.5+bounds.x1*.5,bounds.y0*.5+bounds.y1*.5};
    return finite2(*point)?GX2D_OK:GX2D_RANGE;
}

gx2d_status gx2d_series_create(gx2d_scene *s,const gx2d_id *input,size_t n,const gx2d_series_spec *spec,
    gx2d_id *out,gx2d_id *sources,size_t capacity,size_t *count) {
    gx2d_id *ids=NULL,*created=NULL;double *matrices=NULL;size_t members=0,positions,total,vertices=0,i,j,made=0,copied=0,first;
    gx2d_status code;gx2d_point reference={0,0};gx2d_rect bounds={0,0,0,0};int initialized=0;
    if(!s||!spec||!count||(spec->circular!=0&&spec->circular!=1)||(spec->include_origin!=0&&spec->include_origin!=1)||
       (spec->rotate_geometry!=0&&spec->rotate_geometry!=1)||!isfinite(spec->spacing_x)||!isfinite(spec->spacing_y)||!isfinite(spec->angle_step)||!finite2(spec->pivot))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    if(spec->circular)positions=spec->positions;
    else {if(!spec->rows||!spec->columns||spec->rows>10000/spec->columns)return GX2D_RANGE;positions=spec->rows*spec->columns;}
    first=spec->include_origin?0:1;if(positions<=first||positions>10000)return GX2D_RANGE;
    code=cad_expand(s,input,n,&ids,&members);if(code!=GX2D_OK)return code;
    if(!members||members>10000/(positions-first)){code=GX2D_RANGE;goto done;}total=members*(positions-first);
    for(i=0;i<members;++i){const object *o=cobj(s,ids[i]);
        if(o->count>8000000-vertices){code=GX2D_RANGE;goto done;}vertices+=o->count;
        if(spec->circular&&!spec->rotate_geometry){gx2d_rect b;code=gx2d_object_bounds(s,o->id,&b);if(code!=GX2D_OK)goto done;
            include_point(&bounds,(gx2d_point){b.x0,b.y0},&initialized);include_point(&bounds,(gx2d_point){b.x1,b.y1},&initialized);}
    }
    if(vertices>8000000/(positions-first)){code=GX2D_RANGE;goto done;}
    if(initialized)reference=(gx2d_point){bounds.x0/2+bounds.x1/2,bounds.y0/2+bounds.y1/2};
    matrices=(double *)calloc((positions-first)*6,sizeof(*matrices));if(!matrices){code=GX2D_NOMEM;goto done;}
    for(i=first;i<positions;++i){double *m=matrices+(i-first)*6;
        if(spec->circular){code=gx2d_rotation_matrix(spec->pivot,spec->angle_step*(double)i,m);if(code!=GX2D_OK)goto done;
            if(!spec->rotate_geometry){double dx=m[0]*reference.x+m[1]*reference.y+m[4]-reference.x,dy=m[2]*reference.x+m[3]*reference.y+m[5]-reference.y;
                m[0]=m[3]=1;m[1]=m[2]=0;m[4]=dx;m[5]=dy;}
        } else {m[0]=m[3]=1;m[4]=(double)(i%spec->columns)*spec->spacing_x;m[5]=(double)(i/spec->columns)*spec->spacing_y;}
        if(!cad_matrix_valid(m)){code=GX2D_RANGE;goto done;}
    }
    *count=total;if(!out){code=GX2D_OK;goto done;}if(capacity<total){code=GX2D_RANGE;goto done;}
    created=(gx2d_id *)calloc(total,sizeof(*created));if(!created){code=GX2D_NOMEM;goto done;}
    for(i=first;i<positions;++i){code=gx2d_copy_affine_objects(s,ids,members,matrices+(i-first)*6,created+made,total-made,&copied);
        if(code!=GX2D_OK)goto done;made+=copied;}
    memcpy(out,created,total*sizeof(*out));if(sources)for(i=0;i<positions-first;++i)for(j=0;j<members;++j)sources[i*members+j]=ids[j];code=GX2D_OK;
done:
    if(code!=GX2D_OK)while(made){--made;gx2d_delete_object(s,created[made]);}
    free(ids);free(created);free(matrices);return code;
}
