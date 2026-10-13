/* SPDX-License-Identifier: GPL-3.0-or-later */
static fragment *fragment_find(gx2d_scene *s,gx2d_id id){size_t i;if(!s)return NULL;for(i=0;i<s->fragment_count;++i)if(s->fragments[i].id==id)return &s->fragments[i];return NULL;}
static void identity_remove_all(gx2d_scene *s,gx2d_id id){size_t i;for(i=0;i<s->attribute_count;){if(s->attributes[i].owner==id){free(s->attributes[i].key);free(s->attributes[i].value);memmove(s->attributes+i,s->attributes+i+1,(s->attribute_count-i-1)*sizeof(attribute));--s->attribute_count;}else ++i;}}
static selection_set *selection_set_find(gx2d_scene *s,gx2d_id id){size_t i;if(!s)return NULL;for(i=0;i<s->selection_set_count;++i)if(s->selection_sets[i].id==id)return &s->selection_sets[i];return NULL;}
static int identity_owner(const gx2d_scene *s,gx2d_id id){return !id||cobj(s,id)||lyr((gx2d_scene *)s,id)||fragment_find((gx2d_scene *)s,id)||selection_set_find((gx2d_scene *)s,id);}
static int identity_utf8(const char *text,size_t limit){const unsigned char *p=(const unsigned char *)text;size_t used=0;if(!p)return 0;
    while(*p){uint32_t value;size_t n,i;if(++used>limit)return 0;if(*p<128){++p;continue;}
        if(*p>=0xc2&&*p<=0xdf){n=1;value=*p&31;}else if(*p>=0xe0&&*p<=0xef){n=2;value=*p&15;}else if(*p>=0xf0&&*p<=0xf4){n=3;value=*p&7;}else return 0;
        for(i=1;i<=n;++i){if(!p[i]||(p[i]&0xc0)!=0x80)return 0;value=(value<<6)|(p[i]&63);}
        if((n==2&&value<0x800)||(n==3&&value<0x10000)||value>0x10ffff||(value>=0xd800&&value<=0xdfff))return 0;
        used+=n;if(used>limit)return 0;p+=n+1;
    }return 1;
}
static char *identity_copy(const char *value){size_t n=strlen(value)+1;char *p=(char *)malloc(n);if(p)memcpy(p,value,n);return p;}
gx2d_status gx2d_attribute_set(gx2d_scene *s,gx2d_id owner,const char *key,const char *value){size_t i;char *copy,*keycopy;attribute *all;
    if(!s||!identity_utf8(key,1024)||!*key||!strchr(key,'.')||!identity_utf8(value,16384))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;if(!identity_owner(s,owner))return GX2D_NOT_FOUND;
    if(!strcmp(key,"gx.geometry_role")&&(!cobj(s,owner)||cobj(s,owner)->kind==GX2D_GROUP||(strcmp(value,"regular")&&strcmp(value,"construction")&&strcmp(value,"reference"))))return GX2D_INVALID;
    for(i=0;i<s->attribute_count;++i)if(s->attributes[i].owner==owner&&!strcmp(s->attributes[i].key,key))break;
    copy=identity_copy(value);if(!copy)return GX2D_NOMEM;
    if(i<s->attribute_count){free(s->attributes[i].value);s->attributes[i].value=copy;return GX2D_OK;}
    if(s->attribute_count>=4096){free(copy);return GX2D_RANGE;}keycopy=identity_copy(key);if(!keycopy){free(copy);return GX2D_NOMEM;}
    all=(attribute *)realloc(s->attributes,(s->attribute_count+1)*sizeof(*all));if(!all){free(keycopy);free(copy);return GX2D_NOMEM;}
    s->attributes=all;all[s->attribute_count++]=(attribute){owner,keycopy,copy};return GX2D_OK;
}
gx2d_status gx2d_attribute_get(const gx2d_scene *s,gx2d_id owner,const char *key,const char **out){size_t i;if(!s||!key||!out)return GX2D_INVALID;if(!identity_owner(s,owner))return GX2D_NOT_FOUND;
    for(i=0;i<s->attribute_count;++i)if(s->attributes[i].owner==owner&&!strcmp(s->attributes[i].key,key)){*out=s->attributes[i].value;return GX2D_OK;}return GX2D_NOT_FOUND;
}
gx2d_status gx2d_attribute_remove(gx2d_scene *s,gx2d_id owner,const char *key){size_t i;if(!s||!key)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->attribute_count;++i)if(s->attributes[i].owner==owner&&!strcmp(s->attributes[i].key,key)){free(s->attributes[i].key);free(s->attributes[i].value);memmove(s->attributes+i,s->attributes+i+1,(s->attribute_count-i-1)*sizeof(attribute));--s->attribute_count;return GX2D_OK;}return GX2D_NOT_FOUND;
}
gx2d_status gx2d_attribute_keys(const gx2d_scene *s,gx2d_id owner,const char **keys,size_t cap,size_t *count){size_t i,n=0;if(!s||!count)return GX2D_INVALID;if(!identity_owner(s,owner))return GX2D_NOT_FOUND;
    for(i=0;i<s->attribute_count;++i)if(s->attributes[i].owner==owner)++n;if(keys&&cap<n)return GX2D_RANGE;
    n=0;for(i=0;i<s->attribute_count;++i)if(s->attributes[i].owner==owner){if(keys)keys[n]=s->attributes[i].key;++n;}*count=n;return GX2D_OK;
}
gx2d_status gx2d_set_name(gx2d_scene *s,gx2d_id owner,const char *name){if(!name||!*name)return GX2D_INVALID;return gx2d_attribute_set(s,owner,"gx.name",name);}
gx2d_status gx2d_get_name(const gx2d_scene *s,gx2d_id owner,const char **name){return gx2d_attribute_get(s,owner,"gx.name",name);}
gx2d_status gx2d_object_topology_epoch(const gx2d_scene *s,gx2d_id id,uint64_t *out){const object *o=cobj(s,id);if(!s||!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;*out=o->topology_epoch;return GX2D_OK;}
static uint64_t fragment_epoch(const object *o,const gx2d_fragment_spec *spec){return spec->parameter?o->parameter_epoch:o->topology_epoch;}
static gx2d_status fragment_validate(const gx2d_scene *s,const gx2d_fragment_spec *spec){const object *o;size_t i,first,last;if(!s||!spec||!isfinite(spec->first)||!isfinite(spec->last)||spec->parameter<0||spec->parameter>1)return GX2D_INVALID;
    o=cobj(s,spec->parent);if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(spec->parameter){if(!o->sketch)return GX2D_INVALID;if(o->sketch->family!=GX2D_SKETCH_CONSTRUCTION_LINE&&(spec->first<0||spec->first>1||spec->last<0||spec->last>1))return GX2D_RANGE;}
    else {if(o->sketch||floor(spec->first)!=spec->first||floor(spec->last)!=spec->last||spec->first<0||spec->last<0||spec->first>=o->count||spec->last>=o->count)return GX2D_RANGE;
        first=(size_t)fmin(spec->first,spec->last);last=(size_t)fmax(spec->first,spec->last);for(i=first;i<last;++i)if(o->breaks[i])return GX2D_INVALID;}
    return GX2D_OK;
}
gx2d_status gx2d_fragment_create(gx2d_scene *s,const gx2d_fragment_spec *spec,gx2d_id *out){fragment *all;gx2d_status code;if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    code=fragment_validate(s,spec);if(code!=GX2D_OK)return code;if(s->fragment_count>=4096||s->next_id==UINT64_MAX)return GX2D_RANGE;
    all=(fragment *)realloc(s->fragments,(s->fragment_count+1)*sizeof(*all));if(!all)return GX2D_NOMEM;s->fragments=all;
    all[s->fragment_count]=(fragment){fresh(s),{*spec,fragment_epoch(cobj(s,spec->parent),spec),1,0}};*out=all[s->fragment_count++].id;return GX2D_OK;
}
gx2d_status gx2d_fragment_get(const gx2d_scene *s,gx2d_id id,gx2d_fragment *out){fragment *f=fragment_find((gx2d_scene *)s,id);const object *o;if(!s||!out)return GX2D_INVALID;if(!f)return GX2D_NOT_FOUND;
    *out=f->value;o=cobj(s,out->spec.parent);out->missing=!o;out->valid=o&&fragment_epoch(o,&out->spec)==out->topology_epoch&&fragment_validate(s,&out->spec)==GX2D_OK;return GX2D_OK;
}
gx2d_status gx2d_fragment_ids(const gx2d_scene *s,gx2d_id *ids,size_t cap,size_t *count){size_t i;if(!s||!count)return GX2D_INVALID;if(ids&&cap<s->fragment_count)return GX2D_RANGE;for(i=0;i<s->fragment_count;++i)if(ids)ids[i]=s->fragments[i].id;*count=s->fragment_count;return GX2D_OK;}
gx2d_status gx2d_fragment_update(gx2d_scene *s,gx2d_id id,const gx2d_fragment_spec *spec){fragment *f;gx2d_status code;if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;f=fragment_find(s,id);if(!f)return GX2D_NOT_FOUND;
    code=fragment_validate(s,spec);if(code!=GX2D_OK)return code;f->value=(gx2d_fragment){*spec,fragment_epoch(cobj(s,spec->parent),spec),1,0};return GX2D_OK;
}
gx2d_status gx2d_fragment_delete(gx2d_scene *s,gx2d_id id){fragment *f;size_t index,i;if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;f=fragment_find(s,id);if(!f)return GX2D_NOT_FOUND;index=(size_t)(f-s->fragments);
    for(i=0;i<s->attribute_count;){if(s->attributes[i].owner==id){free(s->attributes[i].key);free(s->attributes[i].value);memmove(s->attributes+i,s->attributes+i+1,(s->attribute_count-i-1)*sizeof(attribute));--s->attribute_count;}else ++i;}
    memmove(s->fragments+index,s->fragments+index+1,(s->fragment_count-index-1)*sizeof(fragment));--s->fragment_count;return GX2D_OK;
}
static gx2d_status fragment_point(const object *o,const gx2d_fragment_spec *spec,double t,gx2d_point *out){double position=spec->first+(spec->last-spec->first)*t;size_t i;if(!isfinite(position))return GX2D_RANGE;
    if(spec->parameter)return sketch_evaluate_valid(o->sketch,position,out,NULL);i=(size_t)floor(position);if(i+1>=o->count){*out=o->points[i];return GX2D_OK;}
    t=position-i;*out=(gx2d_point){(1-t)*o->points[i].x+t*o->points[i+1].x,(1-t)*o->points[i].y+t*o->points[i+1].y};return finite2(*out)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_fragment_sample(const gx2d_scene *s,gx2d_id id,size_t total,size_t start,size_t count,gx2d_point *out,size_t cap){gx2d_fragment f;gx2d_point *points;gx2d_status code;size_t i;
    if(!s||!out||!total||total>1000000||count>65536||cap<count||start>total||count>total-start)return GX2D_INVALID;
    code=gx2d_fragment_get(s,id,&f);if(code!=GX2D_OK)return code;if(!f.valid)return f.missing?GX2D_NOT_FOUND:GX2D_CONSTRAINT;
    points=(gx2d_point *)malloc((count?count:1)*sizeof(*points));if(!points)return GX2D_NOMEM;
    for(i=0;i<count;++i){code=fragment_point(cobj(s,f.spec.parent),&f.spec,total==1?0:(double)(start+i)/(total-1),points+i);if(code!=GX2D_OK){free(points);return code;}}
    memcpy(out,points,count*sizeof(*out));free(points);return GX2D_OK;
}
gx2d_status gx2d_fragment_length(const gx2d_scene *s,gx2d_id id,double *out){gx2d_fragment f;gx2d_status code;const object *o;double a,b,length=0;size_t i,first,last;if(!out)return GX2D_INVALID;
    code=gx2d_fragment_get(s,id,&f);if(code!=GX2D_OK)return code;if(!f.valid)return f.missing?GX2D_NOT_FOUND:GX2D_CONSTRAINT;o=cobj(s,f.spec.parent);
    if(f.spec.parameter){if(o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE){gx2d_point pa,pb;code=fragment_point(o,&f.spec,0,&pa);if(code!=GX2D_OK)return code;code=fragment_point(o,&f.spec,1,&pb);if(code!=GX2D_OK)return code;length=dist(pa,pb);}
        else {code=sketch_prefix_length(o->sketch,f.spec.first,&a);if(code!=GX2D_OK)return code;code=sketch_prefix_length(o->sketch,f.spec.last,&b);if(code!=GX2D_OK)return code;length=fabs(b-a);}}
    else {first=(size_t)fmin(f.spec.first,f.spec.last);last=(size_t)fmax(f.spec.first,f.spec.last);for(i=first;i<last;++i)length+=dist(o->points[i],o->points[i+1]);}
    if(!isfinite(length))return GX2D_RANGE;*out=length;return GX2D_OK;
}
gx2d_status gx2d_fragment_bounds(const gx2d_scene *s,gx2d_id id,size_t samples,gx2d_rect *out){gx2d_fragment f;gx2d_status code;gx2d_rect bounds;gx2d_point p;size_t i;const object *o;
    if(!out||samples<2||samples>65536)return GX2D_INVALID;code=gx2d_fragment_get(s,id,&f);if(code!=GX2D_OK)return code;if(!f.valid)return f.missing?GX2D_NOT_FOUND:GX2D_CONSTRAINT;o=cobj(s,f.spec.parent);
    if(f.spec.parameter){
        gx2d_sketch_definition definition=*o->sketch;
        if(definition.family==GX2D_SKETCH_CIRCLE||definition.family==GX2D_SKETCH_ARC){
            double sweep=definition.family==GX2D_SKETCH_CIRCLE?2*acos(-1.0):definition.angle_sweep;
            double begin=definition.family==GX2D_SKETCH_CIRCLE?0:definition.angle_start;
            definition.family=GX2D_SKETCH_ARC;definition.angle_start=begin+sweep*f.spec.first;definition.angle_sweep=sweep*(f.spec.last-f.spec.first);
            if(definition.angle_sweep==0){code=fragment_point(o,&f.spec,0,&p);if(code!=GX2D_OK)return code;*out=(gx2d_rect){p.x,p.y,p.x,p.y};return GX2D_OK;}
            return gx2d_sketch_bounds(&definition,out);
        }
        if(definition.family!=GX2D_SKETCH_LINE&&definition.family!=GX2D_SKETCH_CONSTRUCTION_LINE)return gx2d_sketch_bounds(&definition,out); /* Conservative parent bounds, never a sampled underestimate. */
    }
    code=fragment_point(o,&f.spec,0,&p);if(code!=GX2D_OK)return code;bounds=(gx2d_rect){p.x,p.y,p.x,p.y};
    if(!f.spec.parameter){size_t first=(size_t)fmin(f.spec.first,f.spec.last),last=(size_t)fmax(f.spec.first,f.spec.last);for(i=first;i<=last;++i){p=o->points[i];bounds.x0=fmin(bounds.x0,p.x);bounds.x1=fmax(bounds.x1,p.x);bounds.y0=fmin(bounds.y0,p.y);bounds.y1=fmax(bounds.y1,p.y);}}
    else for(i=1;i<samples;++i){code=fragment_point(o,&f.spec,(double)i/(samples-1),&p);if(code!=GX2D_OK)return code;bounds.x0=fmin(bounds.x0,p.x);bounds.x1=fmax(bounds.x1,p.x);bounds.y0=fmin(bounds.y0,p.y);bounds.y1=fmax(bounds.y1,p.y);}
    *out=bounds;return GX2D_OK;
}
gx2d_status gx2d_fragment_materialize(gx2d_scene *s,gx2d_id fragment_id,size_t total,gx2d_id *out){gx2d_point *points;gx2d_status code;size_t start;if(!s||!out||!total||total>1000000)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    points=(gx2d_point *)malloc(total*sizeof(*points));if(!points)return GX2D_NOMEM;
    for(start=0;start<total;start+=65536){size_t count=total-start;if(count>65536)count=65536;code=gx2d_fragment_sample(s,fragment_id,total,start,count,points+start,count);if(code!=GX2D_OK){free(points);return code;}}
    code=gx2d_add_geometry(s,total==1?GX2D_POINT_OBJECT:GX2D_CURVE,points,total,out);free(points);return code;
}

static gx2d_status identity_copy_all(gx2d_scene *s,gx2d_id source,gx2d_id target){size_t i,n=s->attribute_count;gx2d_status code;
    for(i=0;i<n;++i)if(s->attributes[i].owner==source){const char *key=s->attributes[i].key,*value=s->attributes[i].value;code=gx2d_attribute_set(s,target,key,value);if(code!=GX2D_OK)return code;}
    return GX2D_OK;
}

gx2d_status gx2d_geometry_role_set(gx2d_scene *s,gx2d_id id,gx2d_geometry_role role){
    static const char *names[]={"regular","construction","reference"};
    if(role<GX2D_ROLE_REGULAR||role>GX2D_ROLE_REFERENCE)return GX2D_INVALID;
    return gx2d_attribute_set(s,id,"gx.geometry_role",names[role]);
}
gx2d_status gx2d_geometry_role_get(const gx2d_scene *s,gx2d_id id,gx2d_geometry_role *out){
    const object *o;const char *value;gx2d_status code;
    if(!s||!out)return GX2D_INVALID;o=cobj(s,id);if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    code=gx2d_attribute_get(s,id,"gx.geometry_role",&value);
    if(code==GX2D_NOT_FOUND){*out=o->sketch&&o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE?GX2D_ROLE_CONSTRUCTION:GX2D_ROLE_REGULAR;return GX2D_OK;}
    if(code!=GX2D_OK)return code;
    *out=!strcmp(value,"construction")?GX2D_ROLE_CONSTRUCTION:!strcmp(value,"reference")?GX2D_ROLE_REFERENCE:GX2D_ROLE_REGULAR;return GX2D_OK;
}
