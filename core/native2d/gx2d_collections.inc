/* SPDX-License-Identifier: GPL-3.0-or-later */
static gx2d_status selection_reference(const gx2d_scene *s,gx2d_selection_ref ref,gx2d_selection_member *out){const object *o;gx2d_fragment f;gx2d_status code;*out=(gx2d_selection_member){ref,0,0,0};
    if(ref.kind==GX2D_SELECTION_FRAGMENT){code=gx2d_fragment_get(s,ref.id,&f);if(code==GX2D_NOT_FOUND){out->missing=1;return GX2D_OK;}if(code!=GX2D_OK)return code;out->valid=f.valid;out->missing=f.missing;out->topology_epoch=f.topology_epoch;return GX2D_OK;}
    if(ref.kind==GX2D_SELECTION_CONTROL||ref.kind==GX2D_SELECTION_SEGMENT){
        gx2d_reference native;gx2d_point point;o=cobj(s,ref.id);
        if(!o){out->missing=1;return GX2D_OK;}
        out->topology_epoch=o->sketch?o->parameter_epoch:o->topology_epoch;
        /* Point-backed segments use a source-row ordinal, shared numerically
         * with controls. The semantic kind, not the index alone, disambiguates
         * that reference. Retained references keep their encoded index. */
        code=!o->sketch&&ref.kind==GX2D_SELECTION_SEGMENT?
            gx2d_reference_create(s,ref.id,GX2D_ENTITY_SEGMENT,ref.index,&native):
            gx2d_reference_from_index(s,ref.id,ref.index,&native);
        if(code==GX2D_OK&&native.entity==(ref.kind==GX2D_SELECTION_CONTROL?GX2D_ENTITY_CONTROL:GX2D_ENTITY_SEGMENT))
            out->valid=gx2d_reference_resolve(s,&native,&point)==GX2D_OK;
        return GX2D_OK;
    }
    if(ref.kind!=GX2D_SELECTION_OBJECT&&ref.kind!=GX2D_SELECTION_POINT)return GX2D_INVALID;o=cobj(s,ref.id);if(!o){out->missing=1;return GX2D_OK;}out->topology_epoch=o->topology_epoch;
    out->valid=ref.kind==GX2D_SELECTION_OBJECT||(o->kind!=GX2D_GROUP&&ref.index<o->count);return GX2D_OK;
}
static int selection_ref_compare(const void *left,const void *right){const gx2d_selection_ref *a=(const gx2d_selection_ref *)left,*b=(const gx2d_selection_ref *)right;
    if(a->kind!=b->kind)return a->kind<b->kind?-1:1;if(a->id!=b->id)return a->id<b->id?-1:1;if((a->kind==GX2D_SELECTION_OBJECT||a->kind==GX2D_SELECTION_FRAGMENT)||a->index==b->index)return 0;return a->index<b->index?-1:1;
}
static gx2d_status selection_set_prepare(const gx2d_scene *s,const gx2d_selection_ref *refs,size_t count,gx2d_selection_member **out){gx2d_selection_member *all;gx2d_selection_ref *sorted;size_t i;gx2d_status code;
    if(!s||!refs||!count||count>65536)return GX2D_INVALID;sorted=(gx2d_selection_ref *)malloc(count*sizeof(*sorted));if(!sorted)return GX2D_NOMEM;memcpy(sorted,refs,count*sizeof(*sorted));qsort(sorted,count,sizeof(*sorted),selection_ref_compare);
    for(i=1;i<count;++i)if(!selection_ref_compare(sorted+i-1,sorted+i)){free(sorted);return GX2D_INVALID;}free(sorted);
    all=(gx2d_selection_member *)malloc(count*sizeof(*all));if(!all)return GX2D_NOMEM;
    for(i=0;i<count;++i){code=selection_reference(s,refs[i],all+i);if(code!=GX2D_OK||!all[i].valid){free(all);return code!=GX2D_OK?code:GX2D_CONSTRAINT;}}
    *out=all;return GX2D_OK;
}
gx2d_status gx2d_selection_set_create(gx2d_scene *s,const gx2d_selection_ref *refs,size_t count,gx2d_id *out){gx2d_selection_member *all;selection_set *sets;gx2d_status code;if(!s||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    if(s->selection_set_count>=4096||s->next_id==UINT64_MAX)return GX2D_RANGE;code=selection_set_prepare(s,refs,count,&all);if(code!=GX2D_OK)return code;
    sets=(selection_set *)realloc(s->selection_sets,(s->selection_set_count+1)*sizeof(*sets));if(!sets){free(all);return GX2D_NOMEM;}s->selection_sets=sets;
    sets[s->selection_set_count]=(selection_set){fresh(s),all,count};*out=sets[s->selection_set_count++].id;return GX2D_OK;
}
gx2d_status gx2d_selection_set_update(gx2d_scene *s,gx2d_id id,const gx2d_selection_ref *refs,size_t count){selection_set *set;gx2d_selection_member *all;gx2d_status code;if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    set=selection_set_find(s,id);if(!set)return GX2D_NOT_FOUND;code=selection_set_prepare(s,refs,count,&all);if(code!=GX2D_OK)return code;free(set->members);set->members=all;set->count=count;return GX2D_OK;
}
gx2d_status gx2d_selection_set_ids(const gx2d_scene *s,gx2d_id *out,size_t cap,size_t *count){size_t i;if(!s||!count)return GX2D_INVALID;if(out&&cap<s->selection_set_count)return GX2D_RANGE;for(i=0;i<s->selection_set_count;++i)if(out)out[i]=s->selection_sets[i].id;*count=s->selection_set_count;return GX2D_OK;}
gx2d_status gx2d_selection_set_get(const gx2d_scene *s,gx2d_id id,gx2d_selection_member *out,size_t cap,size_t *count){selection_set *set=selection_set_find((gx2d_scene *)s,id);gx2d_selection_member *all;gx2d_status code;size_t i;
    if(!s||!count)return GX2D_INVALID;if(!set)return GX2D_NOT_FOUND;if(out&&cap<set->count)return GX2D_RANGE;if(!out){*count=set->count;return GX2D_OK;}
    all=(gx2d_selection_member *)malloc(set->count*sizeof(*all));if(!all)return GX2D_NOMEM;for(i=0;i<set->count;++i){code=selection_reference(s,set->members[i].reference,all+i);if(code!=GX2D_OK){free(all);return code;}
        if(all[i].reference.kind!=GX2D_SELECTION_OBJECT&&all[i].topology_epoch!=set->members[i].topology_epoch)all[i].valid=0;
        all[i].topology_epoch=set->members[i].topology_epoch;}
    memcpy(out,all,set->count*sizeof(*out));*count=set->count;free(all);return GX2D_OK;
}
gx2d_status gx2d_selection_set_delete(gx2d_scene *s,gx2d_id id){selection_set *set;size_t index;if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;set=selection_set_find(s,id);if(!set)return GX2D_NOT_FOUND;index=(size_t)(set-s->selection_sets);free(set->members);identity_remove_all(s,id);memmove(s->selection_sets+index,s->selection_sets+index+1,(s->selection_set_count-index-1)*sizeof(selection_set));--s->selection_set_count;return GX2D_OK;}
gx2d_status gx2d_selection_set_activate(gx2d_scene *s,gx2d_id id,gx2d_select_mode mode){selection_set *set;gx2d_selection_member *all;gx2d_status code;size_t count,i,j;if(!s||mode<GX2D_SELECT_REPLACE||mode>GX2D_SELECT_SUBTRACT)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    set=selection_set_find(s,id);if(!set)return GX2D_NOT_FOUND;all=(gx2d_selection_member *)malloc(set->count*sizeof(*all));if(!all)return GX2D_NOMEM;code=gx2d_selection_set_get(s,id,all,set->count,&count);if(code!=GX2D_OK){free(all);return code;}
    for(i=0;i<count;++i){const object *o;if(!all[i].valid){code=GX2D_CONSTRAINT;goto done;}if(all[i].reference.kind==GX2D_SELECTION_FRAGMENT){gx2d_fragment f;code=gx2d_fragment_get(s,all[i].reference.id,&f);if(code!=GX2D_OK)goto done;o=cobj(s,f.spec.parent);}else o=cobj(s,all[i].reference.id);if(!o||!can_select(s,o)){code=GX2D_LOCKED;goto done;}}
    if(mode==GX2D_SELECT_REPLACE){clear_manual(s);s->block_count=0;}
    for(i=0;i<count;++i){gx2d_selection_ref ref=all[i].reference;object *o;
        if(ref.kind==GX2D_SELECTION_FRAGMENT){gx2d_fragment f;double first,last;gx2d_fragment_get(s,ref.id,&f);o=obj(s,f.spec.parent);first=fmin(f.spec.first,f.spec.last);last=fmax(f.spec.first,f.spec.last);
            if(f.spec.parameter){first*=o->count-1;last*=o->count-1;}
            for(j=0;j<o->count;++j)if((double)j>=first&&(double)j<=last)o->manual[j]=mode==GX2D_SELECT_SUBTRACT?2:1;
        }else {o=obj(s,ref.id);if(ref.kind==GX2D_SELECTION_POINT)o->manual[ref.index]=mode==GX2D_SELECT_SUBTRACT?2:1;else if(ref.kind==GX2D_SELECTION_OBJECT){o->style.selected=mode!=GX2D_SELECT_SUBTRACT;if(mode==GX2D_SELECT_SUBTRACT&&o->manual)memset(o->manual,2,o->count);}}
    }
    code=GX2D_OK;
done:free(all);return code;
}

gx2d_status gx2d_selection_set_add_member(gx2d_scene *s,gx2d_id id,gx2d_selection_ref ref){selection_set *set;gx2d_selection_member member,*all;gx2d_status code;size_t i;
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;set=selection_set_find(s,id);if(!set)return GX2D_NOT_FOUND;if(set->count>=65536)return GX2D_RANGE;
    for(i=0;i<set->count;++i)if(!selection_ref_compare(&set->members[i].reference,&ref))return GX2D_INVALID;
    code=selection_reference(s,ref,&member);if(code!=GX2D_OK||!member.valid)return code!=GX2D_OK?code:GX2D_CONSTRAINT;
    all=(gx2d_selection_member *)realloc(set->members,(set->count+1)*sizeof(*all));if(!all)return GX2D_NOMEM;set->members=all;all[set->count++]=member;return GX2D_OK;
}
gx2d_status gx2d_selection_set_remove_member(gx2d_scene *s,gx2d_id id,size_t index){selection_set *set;if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;set=selection_set_find(s,id);if(!set)return GX2D_NOT_FOUND;if(index>=set->count)return GX2D_RANGE;if(set->count==1)return GX2D_INVALID; /* Use delete for an empty set. */
    memmove(set->members+index,set->members+index+1,(set->count-index-1)*sizeof(*set->members));--set->count;return GX2D_OK;
}

/* Explicit object references may focus hidden/reference-only properties.
 * Ordinary pointer and region APIs still exclude that geometry completely.
 * Merge semantic membership atomically, then project point/object membership
 * into the existing paged selection masks. Retained controls are not samples. */
static const object *selection_owner(const gx2d_scene *s,gx2d_selection_ref ref) {
    gx2d_fragment fragment;
    if(ref.kind==GX2D_SELECTION_FRAGMENT){
        if(gx2d_fragment_get(s,ref.id,&fragment)!=GX2D_OK||!fragment.valid)return NULL;
        return cobj(s,fragment.spec.parent);
    }
    return cobj(s,ref.id);
}
static gx2d_status selection_set_apply(gx2d_scene *s,gx2d_id *id,
        const gx2d_selection_ref *refs,size_t n,gx2d_select_mode mode,int restoring) {
    selection_set *set;gx2d_selection_ref *merged;gx2d_selection_member *prepared=NULL;
    gx2d_status code;size_t count=0,i,j,capacity;
    if(!s||!id||(n&&!refs)||n>65536||mode<GX2D_SELECT_REPLACE||mode>GX2D_SELECT_SUBTRACT)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    set=*id?selection_set_find(s,*id):NULL;
    if(*id&&!set)return GX2D_NOT_FOUND;
    if(n){code=selection_set_prepare(s,refs,n,&prepared);if(code!=GX2D_OK)return code;free(prepared);}
    for(i=0;i<n;++i){const object *o=selection_owner(s,refs[i]);if(o&&o->sketch&&refs[i].kind==GX2D_SELECTION_POINT)return GX2D_INVALID;if(!o||(!restoring&&!can_select(s,o)&&refs[i].kind!=GX2D_SELECTION_OBJECT))return GX2D_LOCKED;}
    capacity=n+(set&&mode!=GX2D_SELECT_REPLACE?set->count:0);
    merged=malloc((capacity?capacity:1)*sizeof(*merged));if(!merged)return GX2D_NOMEM;
    if(set&&mode!=GX2D_SELECT_REPLACE)for(i=0;i<set->count;++i){
        gx2d_selection_member current;const object *o=selection_owner(s,set->members[i].reference);
        code=selection_reference(s,set->members[i].reference,&current);
        if(code==GX2D_OK&&current.valid&&o&&(can_select(s,o)||current.reference.kind==GX2D_SELECTION_OBJECT)&&
           (current.reference.kind==GX2D_SELECTION_OBJECT||current.topology_epoch==set->members[i].topology_epoch))
            merged[count++]=set->members[i].reference;
    }
    for(i=0;i<n;++i){
        /* An additive detail pick refines a previously selected whole object.
         * Whole-object and detail references must not become duplicate inputs
         * to dimension/constraint consumers of the semantic set. */
        if(mode==GX2D_SELECT_ADD)for(j=0;j<count;){
            if(merged[j].id==refs[i].id&&
               ((merged[j].kind==GX2D_SELECTION_OBJECT&&refs[i].kind!=GX2D_SELECTION_OBJECT)||
                (refs[i].kind==GX2D_SELECTION_OBJECT&&merged[j].kind!=GX2D_SELECTION_OBJECT))){
                memmove(merged+j,merged+j+1,(count-j-1)*sizeof(*merged));--count;
            }else ++j;
        }
        for(j=0;j<count;++j)if(!selection_ref_compare(merged+j,refs+i))break;
        if(mode==GX2D_SELECT_SUBTRACT){if(j<count){memmove(merged+j,merged+j+1,(count-j-1)*sizeof(*merged));--count;}}
        else if(j==count)merged[count++]=refs[i];
    }
    if(count>65536){free(merged);return GX2D_RANGE;}
    /* Preflight the final projection before replacing the previous selection. */
    for(i=0;i<count;++i){const object *o=selection_owner(s,merged[i]);if(!o||(!restoring&&!can_select(s,o)&&merged[i].kind!=GX2D_SELECTION_OBJECT)){free(merged);return GX2D_LOCKED;}}
    if(count){code=*id?gx2d_selection_set_update(s,*id,merged,count):gx2d_selection_set_create(s,merged,count,id);
        if(code==GX2D_OK){
            /* No fallible allocation after membership adoption: the projection
             * was fully preflighted and uses existing object masks only. */
            clear_manual(s);s->block_count=0;
            for(i=0;i<count;++i){object *o=(object *)selection_owner(s,merged[i]);
                if(merged[i].kind==GX2D_SELECTION_FRAGMENT){
                    gx2d_fragment f;double first,last;gx2d_fragment_get(s,merged[i].id,&f);
                    first=fmin(f.spec.first,f.spec.last);last=fmax(f.spec.first,f.spec.last);
                    if(f.spec.parameter){first*=o->count-1;last*=o->count-1;}
                    for(j=0;j<o->count;++j)if((double)j>=first&&(double)j<=last)o->manual[j]=1;
                } else if(merged[i].kind==GX2D_SELECTION_POINT)o->manual[merged[i].index]=1;
                else if(merged[i].kind==GX2D_SELECTION_OBJECT)o->style.selected=1;
            }
        }
    }else {code=*id?gx2d_selection_set_delete(s,*id):GX2D_OK;if(code==GX2D_OK){*id=0;clear_manual(s);s->block_count=0;}}
    free(merged);return code;
}
/* Restoration retains valid saved membership even when presentation hides a
 * member. Ordinary pick/region/apply continue to enforce selection exclusion. */
gx2d_status gx2d_selection_set_restore(gx2d_scene *s,gx2d_id *id,const gx2d_selection_ref *refs,size_t n) {
    return selection_set_apply(s,id,refs,n,GX2D_SELECT_REPLACE,1);
}
gx2d_status gx2d_selection_set_apply(gx2d_scene *s,gx2d_id *id,const gx2d_selection_ref *refs,size_t n,gx2d_select_mode mode) {
    return selection_set_apply(s,id,refs,n,mode,0);
}
static gx2d_status selection_scope(const gx2d_scene *s,const gx2d_id *ids,size_t n) {
    size_t i,j;if(!s||(n&&!ids)||n>65536)return GX2D_INVALID;
    for(i=0;i<n;++i){const object *o=cobj(s,ids[i]);if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
        for(j=0;j<i;++j)if(ids[i]==ids[j])return GX2D_INVALID;}
    return GX2D_OK;
}
gx2d_status gx2d_selection_pick(const gx2d_scene *s,const gx2d_id *ids,size_t n,
        gx2d_point device,double tolerance,gx2d_selection_ref *out) {
    gx2d_status code;gx2d_reference reference;gx2d_point point,q,world;
    gx2d_segment_hit hit;gx2d_selection_ref best={0};double distance=DBL_MAX;int priority=0;size_t i;
    if(!out||!finite2(device)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;
    code=selection_scope(s,ids,n);if(code!=GX2D_OK)return code;
    gx2d_device_to_world(s,device,&world);
    for(i=0;i<n;++i){const object *o=cobj(s,ids[i]);int rank;double d;
        code=gx2d_interaction_pick(s,ids[i],device,tolerance,&reference);
        if(code==GX2D_NOT_FOUND)continue;if(code!=GX2D_OK)return code;
        rank=reference.entity==GX2D_ENTITY_CONTROL?2:1;
        if(rank==2){gx2d_reference_resolve(s,&reference,&point);gx2d_world_to_device(s,point,&q);d=dist(q,device);}
        else {code=gx2d_nearest_segment(s,ids[i],world,&hit);if(code!=GX2D_OK)return code;gx2d_world_to_device(s,hit.point,&q);d=dist(q,device);}
        /* Every participating curve has the same vertex priority. Stable scope
         * order breaks exact ties; the active property focus is irrelevant. */
        if(rank>priority||(rank==priority&&d<distance)){
            priority=rank;distance=d;best.id=ids[i];best.index=reference.entity==GX2D_ENTITY_OBJECT?0:reference.index;
            best.kind=reference.entity==GX2D_ENTITY_OBJECT?GX2D_SELECTION_OBJECT:reference.entity==GX2D_ENTITY_SEGMENT?GX2D_SELECTION_SEGMENT:o->sketch?GX2D_SELECTION_CONTROL:GX2D_SELECTION_POINT;
        }
    }
    if(!priority)return GX2D_NOT_FOUND;*out=best;return GX2D_OK;
}
static int selection_polygon_contains(const gx2d_point *vertices,size_t n,gx2d_point p) {
    size_t i,j=n-1;int inside=0;
    for(i=0;i<n;j=i++){
        gx2d_point a=vertices[j],b=vertices[i];long double dx=(long double)b.x-a.x,dy=(long double)b.y-a.y;
        long double cross=dx*((long double)p.y-a.y)-dy*((long double)p.x-a.x);
        long double scale=fabsl(dx)+fabsl(dy)+1;
        if(fabsl(cross)<=1e-12L*scale&&p.x>=fmin(a.x,b.x)-1e-12&&p.x<=fmax(a.x,b.x)+1e-12&&p.y>=fmin(a.y,b.y)-1e-12&&p.y<=fmax(a.y,b.y)+1e-12)return 1;
        if((a.y>p.y)!=(b.y>p.y)&&((long double)p.x<(long double)a.x+((long double)p.y-a.y)*dx/dy))inside=!inside;
    }
    return inside;
}
gx2d_status gx2d_selection_polygon(const gx2d_scene *s,const gx2d_id *ids,size_t n,
        const gx2d_point *vertices,size_t nv,gx2d_selection_ref *out,size_t cap,size_t *count) {
    gx2d_status code;gx2d_selection_ref *refs;size_t i,j,total=0;long double area=0;
    if(!count||nv<3||nv>4096||!valid_points(vertices,nv))return GX2D_INVALID;
    code=selection_scope(s,ids,n);if(code!=GX2D_OK)return code;
    for(i=0;i<nv;++i){j=(i+1)%nv;area+=(long double)vertices[i].x*vertices[j].y-(long double)vertices[j].x*vertices[i].y;}
    if(area==0)return GX2D_INVALID;
    refs=malloc(65536*sizeof(*refs));if(!refs)return GX2D_NOMEM;
    for(i=0;i<n;++i){const object *o=cobj(s,ids[i]);if(!can_select(s,o))continue;
        size_t controls=o->sketch?control_count(o):o->count;
        for(j=0;j<controls;++j){gx2d_point point;
            if(o->sketch){code=control_point(o,j,&point,NULL);if(code!=GX2D_OK){free(refs);return code;}}else point=o->points[j];
            if(selection_polygon_contains(vertices,nv,point)){
                if(total==65536){free(refs);return GX2D_RANGE;}
                refs[total++]=(gx2d_selection_ref){o->sketch?GX2D_SELECTION_CONTROL:GX2D_SELECTION_POINT,ids[i],o->sketch?GX2D_CONTROL_INDEX+j:j};
            }
        }
    }
    if(out&&cap<total){free(refs);return GX2D_RANGE;}
    if(out&&total)memcpy(out,refs,total*sizeof(*out));*count=total;free(refs);return GX2D_OK;
}

static int selection_owner_id_compare(const void *a,const void *b){
    gx2d_id x=*(const gx2d_id *)a,y=*(const gx2d_id *)b;return x<y?-1:x>y?1:0;
}
gx2d_status gx2d_selection_set_bounds(const gx2d_scene *s,gx2d_id id,gx2d_rect *out){
    selection_set *set;gx2d_id *owners;size_t count=0;gx2d_status code=GX2D_NOT_FOUND;
    gx2d_rect result={0};int found=0;
    if(!s||!out)return GX2D_INVALID;set=selection_set_find((gx2d_scene *)s,id);if(!set)return GX2D_NOT_FOUND;
    owners=malloc((set->count?set->count:1)*sizeof(*owners));if(!owners)return GX2D_NOMEM;
    for(size_t i=0;i<set->count;++i){gx2d_selection_member current;const object *owner;
        code=selection_reference(s,set->members[i].reference,&current);
        if(code!=GX2D_OK||!current.valid||(current.reference.kind!=GX2D_SELECTION_OBJECT&&current.topology_epoch!=set->members[i].topology_epoch)){code=GX2D_CONSTRAINT;goto done;}
        owner=selection_owner(s,current.reference);
        const layer *owner_layer=owner&&owner->style.layer?lyr((gx2d_scene *)s,owner->style.layer):NULL;
        int visible=owner&&owner->style.visible&&(!owner_layer||owner_layer->style.visible);
        if(visible&&(current.reference.kind==GX2D_SELECTION_OBJECT||can_select(s,owner))){
            owners[count++]=owner->id;
            if(current.reference.kind==GX2D_SELECTION_CONTROL){gx2d_reference ref;gx2d_point point;
                code=gx2d_reference_from_index(s,owner->id,current.reference.index,&ref);if(code!=GX2D_OK)goto done;
                code=gx2d_reference_resolve(s,&ref,&point);if(code!=GX2D_OK)goto done;include_point(&result,point,&found);
            }
        }
    }
    /* Deduplicate before querying complete scientific owner bounds. This stays
     * efficient for thousands of selected points on the same logical curve. */
    qsort(owners,count,sizeof(*owners),selection_owner_id_compare);
    for(size_t i=0;i<count;++i){gx2d_rect bounds;if(i&&owners[i]==owners[i-1])continue;
        const object *owner=cobj(s,owners[i]);if(owner->sketch&&owner->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE)continue;
        code=gx2d_object_bounds(s,owners[i],&bounds);if(code!=GX2D_OK)goto done;
        include_point(&result,(gx2d_point){bounds.x0,bounds.y0},&found);include_point(&result,(gx2d_point){bounds.x1,bounds.y1},&found);
    }
    code=found?GX2D_OK:GX2D_NOT_FOUND;if(found)*out=result;
done:free(owners);return code;
}

/* The policy changes semantic targeting, not geometry or selection ownership.
 * Exact Spline pieces reuse the retained cubic evaluator and closest-point
 * kernel; display tessellation IDs never become semantic segment identities. */
gx2d_status gx2d_selection_pick_target(const gx2d_scene *s,const gx2d_id *ids,size_t n,gx2d_point device,double tolerance,gx2d_selection_target target,gx2d_selection_ref *out) {
    if(!out||target<GX2D_PICK_DETAIL||target>GX2D_PICK_OBJECT)return GX2D_INVALID;
    gx2d_selection_ref result;gx2d_status code=gx2d_selection_pick(s,ids,n,device,tolerance,&result);
    if(code!=GX2D_OK)return code;
    if(target==GX2D_PICK_OBJECT){result.kind=GX2D_SELECTION_OBJECT;result.index=0;}
    else if(target==GX2D_PICK_LOCAL&&result.kind!=GX2D_SELECTION_CONTROL&&result.kind!=GX2D_SELECTION_POINT){
        const object *root=cobj(s,result.id);object leaf;gx2d_sketch_definition definition;size_t index=result.kind==GX2D_SELECTION_OBJECT?GX2D_OBJECT_INDEX:result.index,part=0;
        int mapped=network_leaf(root,&index,&leaf,&definition,&part);if(mapped<0)return GX2D_INVALID;
        const gx2d_sketch_definition *shape=mapped?&definition:root->sketch;
        if(shape&&shape->family==GX2D_SKETCH_RECTANGLE){
            result.kind=mapped?GX2D_SELECTION_SEGMENT:GX2D_SELECTION_OBJECT;result.index=mapped?GX2D_SEGMENT_INDEX+part*NETWORK_STRIDE+NETWORK_STRIDE-1:0;
        }else if(shape&&shape->family==GX2D_SKETCH_SPLINE){
            gx2d_point query;gx2d_device_to_world(s,device,&query);double best=DBL_MAX;size_t chosen=0;
            for(size_t k=0;k+1<shape->control_count;k++){
                gx2d_point controls[4],world[4],point,projected;sketch_spline_controls(shape,k,controls);
                for(size_t j=0;j<4;j++)world[j]=sketch_world(shape,controls[j],0);
                gx2d_rect bounds={0};int initialized=0;if(!sketch_cubic_bounds(&bounds,world,&initialized))return GX2D_RANGE;
                gx2d_point lo,hi;gx2d_world_to_device(s,(gx2d_point){bounds.x0,bounds.y0},&lo);gx2d_world_to_device(s,(gx2d_point){bounds.x1,bounds.y1},&hi);
                double dx=fmax(fmax(fmin(lo.x,hi.x)-device.x,device.x-fmax(lo.x,hi.x)),0),dy=fmax(fmax(fmin(lo.y,hi.y)-device.y,device.y-fmax(lo.y,hi.y)),0);
                if(hypot(dx,dy)>best)continue;
                gx2d_sketch_definition cubic=*shape;cubic.family=GX2D_SKETCH_CUBIC_BEZIER;cubic.controls=controls;cubic.control_count=4;cubic.tangents=NULL;cubic.tangent_count=0;
                object piece=*root;piece.sketch=&cubic;if(!sk_nearest(&piece,query,&point))return GX2D_RANGE;
                gx2d_world_to_device(s,point,&projected);double distance=dist(device,projected);if(distance<best){best=distance;chosen=k;}
            }
            if(best>tolerance)return GX2D_NOT_FOUND;
            gx2d_reference ref;code=gx2d_reference_create(s,result.id,GX2D_ENTITY_SEGMENT,mapped?part*NETWORK_STRIDE+chosen:chosen,&ref);if(code!=GX2D_OK)return code;
            result.kind=GX2D_SELECTION_SEGMENT;result.index=ref.index;
        }
    }
    *out=result;return GX2D_OK;
}
gx2d_status gx2d_selection_polygon_target(const gx2d_scene *s,const gx2d_id *ids,size_t n,const gx2d_point *vertices,size_t nv,gx2d_selection_target target,gx2d_selection_ref *out,size_t cap,size_t *count) {
    if(target==GX2D_PICK_DETAIL)return gx2d_selection_polygon(s,ids,n,vertices,nv,out,cap,count);
    if(target!=GX2D_PICK_OBJECT||!count)return GX2D_INVALID;
    gx2d_selection_ref *refs=malloc(65536*sizeof(*refs));if(!refs)return GX2D_NOMEM;size_t total=0,objects=0;
    gx2d_status code=gx2d_selection_polygon(s,ids,n,vertices,nv,refs,65536,&total);
    /* Native region order groups controls by owner. Promotion is explicit here
     * and never changes the meaning of two separately clicked controls. */
    for(size_t i=0;code==GX2D_OK&&i<total;i++)if(!objects||refs[i].id!=refs[objects-1].id)refs[objects++]=(gx2d_selection_ref){GX2D_SELECTION_OBJECT,refs[i].id,0};
    if(code==GX2D_OK&&out&&cap<objects)code=GX2D_RANGE;
    if(code==GX2D_OK){if(out&&objects)memcpy(out,refs,objects*sizeof(*out));*count=objects;}
    free(refs);return code;
}
