#include "gx2d.h"
#include "../../plugins/modules/math.numeric/api/c/gxtxt_numeric_reductions_v1.h"
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* No renderer or platform handles enter the model. IDs are monotonic per scene. */
typedef struct {
    gx2d_id id;
    gx2d_kind kind;
    gx2d_style style;
    gx2d_point *points;
    unsigned char *manual;
    unsigned char *breaks; /* break after vertex i; final entry is unused */
    size_t count;
    size_t capacity;
    gx2d_id *members;
    size_t member_count;
    gx2d_direction_marker direction_marker;
    gx2d_part_state *part_states;size_t part_state_count;uint64_t next_part_id;
    gx2d_sketch_definition *sketch;
    int reference_image;
    struct {char resource_id[128],length_unit[32];double width,height;gx2d_point calibration[2];int calibrated;} image;
    uint64_t topology_epoch,parameter_epoch;
} object;
static gx2d_sketch_definition *sketch_clone(const gx2d_sketch_definition *);
static void sketch_free(gx2d_sketch_definition *);
static size_t control_count(const object *);
static gx2d_status control_point(const object *,size_t,gx2d_point *,gx2d_control_role *);
static int sketch_is_composition(const gx2d_sketch_definition *d) {return d&&(d->family==GX2D_SKETCH_COMPOSITE_PATH||d->family==GX2D_SKETCH_COMPOUND);}
static gx2d_status part_states_init(object *);
static void sketch_restore_owned(gx2d_sketch_definition *,const gx2d_sketch_definition *);
static void identity_remove_all(gx2d_scene *,gx2d_id);
static gx2d_status identity_copy_all(gx2d_scene *,gx2d_id,gx2d_id);
static int sketch_compose(gx2d_sketch_definition *,const double [6]);
static gx2d_status sketch_metrics(const gx2d_sketch_definition *,gx2d_metrics *);
static gx2d_status sketch_path_point(const object *,double,gx2d_segment_hit *);
static gx2d_status sketch_render_device(const gx2d_scene *,const object *,size_t,gx2d_point *,uint64_t *,size_t,size_t *,size_t *,size_t,size_t *);
static gx2d_status sketch_construction_clip(const gx2d_scene *,const gx2d_sketch_definition *,gx2d_point [2]);
typedef struct { gx2d_id id; gx2d_layer_style style; } layer;
typedef struct { gx2d_id id; gx2d_rect rect; gx2d_select_mode mode; } block;
typedef struct { gx2d_id id; gx2d_constraint spec; gx2d_point anchor;
    gx2d_id axis;size_t axis_index;int disabled;double angular_tolerance;
    gx2d_relationship_state presentation;
} rule;
static gx2d_status sketch_rule_check(const gx2d_scene *,const rule *,gx2d_constraint_diagnostic *);
static int sketch_has_solver(const gx2d_scene *,gx2d_id);
static gx2d_status sketch_solve_drag(gx2d_scene *);
static gx2d_status rule_check_extended(const gx2d_scene *,const rule *,gx2d_constraint_diagnostic *);
typedef struct {gx2d_id owner;char *key,*value;} attribute;
typedef struct {gx2d_id id;gx2d_fragment value;} fragment;
typedef struct {gx2d_id id;gx2d_selection_member *members;size_t count;} selection_set;
struct gx2d_scene {
    selection_set *selection_sets;size_t selection_set_count;
    attribute *attributes;size_t attribute_count;
    fragment *fragments;size_t fragment_count;
    gx2d_id next_id;
    object *objects; size_t object_count;
    layer *layers; size_t layer_count;
    block *blocks; size_t block_count;
    rule *rules; size_t rule_count;
    gx2d_point **drag_points;
    unsigned char **drag_masks;
    size_t *drag_counts;
    gx2d_sketch_definition *drag_sketches;
    gx2d_sketch_definition **drag_retained;
    int dragging;
    gx2d_view view;
    gx2d_view requested_view;
    gx2d_view drag_view;
    gx2d_aspect_mode aspect_mode;
    gx2d_grid grid;
    gx2d_color background;
    gx2d_polar_frame polar;
    gx2d_coordinate_mode coordinate_mode;
    gx2d_pivot_mode pivot_mode;
    gx2d_point custom_pivot,drag_pivot;
    gx2d_gizmo gizmo;
};

static int finite2(gx2d_point p) { return isfinite(p.x) && isfinite(p.y); }
static gx2d_gizmo default_gizmo(void);
static int valid_points(const gx2d_point *p, size_t n) {
    size_t i;
    if (!p || !n || n > SIZE_MAX / sizeof(*p)) return 0;
    for (i=0; i<n; ++i) if (!finite2(p[i])) return 0;
    return 1;
}
static int valid_rect(gx2d_rect r) {
    return isfinite(r.x0)&&isfinite(r.y0)&&isfinite(r.x1)&&isfinite(r.y1)&&r.x0<=r.x1&&r.y0<=r.y1;
}
static int inside(gx2d_rect r, gx2d_point p) { return p.x>=r.x0&&p.x<=r.x1&&p.y>=r.y0&&p.y<=r.y1; }
static int segment_in_rect(gx2d_rect r,gx2d_point a,gx2d_point b){
    /* Liang-Barsky clipping; touching the boundary counts as a hit. */
    double p[4],q[4],lo=0,hi=1,t;size_t i;
    p[0]=a.x-b.x;p[1]=b.x-a.x;p[2]=a.y-b.y;p[3]=b.y-a.y;
    q[0]=a.x-r.x0;q[1]=r.x1-a.x;q[2]=a.y-r.y0;q[3]=r.y1-a.y;
    for(i=0;i<4;++i){
        if(p[i]==0){if(q[i]<0)return 0;continue;}
        t=q[i]/p[i];
    if(p[i]<0){if(t>hi)return 0;
    if(t>lo)lo=t;}
        else {if(t<lo)return 0;
    if(t<hi)hi=t;}
    }
    return 1;
}
static object *obj(gx2d_scene *s, gx2d_id id) {
    size_t i; if (!s || !id) return NULL;
    for(i=0;i<s->object_count;++i) if(s->objects[i].id==id) return &s->objects[i];
    return NULL;
}
static const object *cobj(const gx2d_scene *s, gx2d_id id) { return obj((gx2d_scene *)s,id); }
/* Extended point/segment references cannot silently follow a different ordinal
 * after a topology edit. Disconnect them explicitly before reindexing. Legacy
 * five-kind semantics remain unchanged. */
static int extended_constraint_references(const gx2d_scene *s,gx2d_id id) {
    size_t i;for(i=0;i<s->rule_count;++i){const rule *r=&s->rules[i];if(r->spec.kind>GX2D_PERPENDICULAR&&(r->spec.a==id||r->spec.b==id||r->axis==id))return 1;}return 0;
}
static layer *lyr(gx2d_scene *s, gx2d_id id) {
    size_t i;
    if(!s||!id) return NULL;
    for(i=0;i<s->layer_count;++i) if(s->layers[i].id==id) return &s->layers[i];
    return NULL;
}
static int can_select(const gx2d_scene *s, const object *o) {
    const layer *l = o->style.layer ? lyr((gx2d_scene *)s,o->style.layer) : NULL;
    return o->style.visible && o->style.selectable && (!l || (l->style.visible && l->style.selectable));
}
static int can_move(const gx2d_scene *s, const object *o) {
    const layer *l = o->style.layer ? lyr((gx2d_scene *)s,o->style.layer) : NULL;
    size_t i;for(i=0;i<s->rule_count;++i)if(!s->rules[i].disabled&&s->rules[i].spec.kind==GX2D_FIXED&&s->rules[i].spec.a==o->id&&s->rules[i].spec.a_index==GX2D_OBJECT_INDEX)return 0;
    return !o->style.locked && (!l || !l->style.locked);
}
static int valid_style(const gx2d_style *v) {
    return v && isfinite(v->red)&&isfinite(v->green)&&isfinite(v->blue)&&
        v->red>=0&&v->red<=1&&v->green>=0&&v->green<=1&&v->blue>=0&&v->blue<=1&&
        isfinite(v->opacity)&&v->opacity>=0&&v->opacity<=1&&isfinite(v->line_width)&&v->line_width>0&&
        v->line_style>=GX2D_LINE_SOLID&&v->line_style<=GX2D_LINE_DOT&&
        v->marker>=GX2D_MARKER_NONE&&v->marker<=GX2D_MARKER_CROSS;
}
static int valid_layer_style(const gx2d_layer_style *v) { return v&&isfinite(v->opacity)&&v->opacity>=0&&v->opacity<=1; }
static gx2d_style default_style(void) {
    gx2d_style v; memset(&v,0,sizeof(v)); v.visible=1;v.selectable=1;
    v.red=v.green=v.blue=1;v.line_width=1;v.opacity=1;v.line_style=GX2D_LINE_SOLID;
    v.marker=GX2D_MARKER_CIRCLE; return v;
}
static gx2d_direction_marker default_direction_marker(void) {
    gx2d_direction_marker value = {1,0,1,0,.5,12,32,2,1,{.12,.19,.34,1}};
    return value;
}
static gx2d_id fresh(gx2d_scene *s) { return s->next_id++; }
static void clear_manual(gx2d_scene *s) {
    size_t i; for(i=0;i<s->object_count;++i) {
        s->objects[i].style.selected=0;
        if(s->objects[i].manual) memset(s->objects[i].manual,0,s->objects[i].count);
    }
}
static int point_selected_at(const gx2d_scene *s, const object *o, size_t j) {
    size_t k; int selected = o->style.selected;
    for(k=0;k<s->block_count;++k){
        gx2d_rect r=s->blocks[k].rect;
        int hit=inside(r,o->points[j]);
        if(o->kind==GX2D_CURVE&&!hit){
            if(j>0&&!o->breaks[j-1]&&!inside(r,o->points[j-1]))
                hit=segment_in_rect(r,o->points[j-1],o->points[j]);
            if(j+1<o->count&&!o->breaks[j]&&!inside(r,o->points[j+1]))
                hit=hit||segment_in_rect(r,o->points[j],o->points[j+1]);
        }
        if(hit&&(can_select(s,o)||s->blocks[k].mode==GX2D_SELECT_SUBTRACT))
            selected=s->blocks[k].mode==GX2D_SELECT_ADD;
    }
    if(o->manual[j]==1)selected=1;
    if(o->manual[j]==2)selected=0;
    return selected;
}
static gx2d_status append_object(gx2d_scene *s, object value, gx2d_id *out) {
    object *v;
    if(s->next_id==UINT64_MAX || s->object_count==SIZE_MAX/sizeof(*v)) return GX2D_RANGE;
    v=(object *)realloc(s->objects,(s->object_count+1)*sizeof(*v));
    if(!v) return GX2D_NOMEM;
    s->objects=v; value.id=fresh(s); s->objects[s->object_count++]=value; *out=value.id;
    return GX2D_OK;
}
static gx2d_point nearest_segment(gx2d_point p, gx2d_point a, gx2d_point b) {
    double dx=b.x-a.x,dy=b.y-a.y,den=dx*dx+dy*dy,t;
    if(den<=0) return a;
    t=((p.x-a.x)*dx+(p.y-a.y)*dy)/den;
    if(t<0)t=0;
    if(t>1)t=1;
    a.x+=t*dx;a.y+=t*dy;
    return a;
}
static double dist(gx2d_point a,gx2d_point b) { return hypot(a.x-b.x,a.y-b.y); }
static gx2d_status closest(const gx2d_scene *s,const object *o,gx2d_point p,gx2d_hit *hit) {
    size_t j; double best=DBL_MAX; gx2d_point q; size_t index=0;
    if(!o || !o->count) return GX2D_INVALID;
    for(j=0;j<o->count;++j) {
        q=o->points[j];
    if(dist(q,p)<best){best=dist(q,p);hit->point=q;index=j;}
    }
    if(o->kind==GX2D_CURVE) for(j=0;j+1<o->count;++j) {if(o->breaks[j])continue;
        q=nearest_segment(p,o->points[j],o->points[j+1]);
        if(dist(q,p)<best){best=dist(q,p);hit->point=q;index=j;}
    }
    hit->object=o->id;hit->point_index=index;hit->distance=best;(void)s;
    return GX2D_OK;
}

gx2d_scene *gx2d_create(void) { gx2d_scene *s=(gx2d_scene *)calloc(1,sizeof(*s));
    if(s){s->next_id=1;s->view=(gx2d_view){800,600,52,20,28,50,{0,0,1,1}};s->requested_view=s->view;
        /* Shared host default: equal world units in both device directions.
         * Apply through the view authority so even the initial scene agrees. */
        s->aspect_mode=GX2D_ASPECT_XY_EQUAL;gx2d_view_set(s,&s->requested_view);
        s->background=(gx2d_color){1,1,1,1};s->gizmo=default_gizmo();
        s->grid=(gx2d_grid){0,0,0,1,1,1,{0,0},1,1,0,5,{.38,.46,.55,.5},{.55,.62,.7,.3},{.24,.3,.38,.8},1,.6,1.5,0,2,0};
        s->polar=(gx2d_polar_frame){{0,0},0,0,1,0,10,0,2*acos(-1.),1,acos(-1.)/12,5,3};}
    return s; }
void gx2d_destroy(gx2d_scene *s) {
    size_t i;
    if(!s)return;
    for(i=0;i<s->object_count;++i){free(s->objects[i].points);free(s->objects[i].manual);free(s->objects[i].breaks);free(s->objects[i].members);free(s->objects[i].part_states);sketch_free(s->objects[i].sketch);}
    if(s->drag_points){for(i=0;i<s->object_count;++i)free(s->drag_points[i]);free(s->drag_points);}
    if(s->drag_masks){for(i=0;i<s->object_count;++i)free(s->drag_masks[i]);free(s->drag_masks);}
    for(i=0;i<s->attribute_count;++i){free(s->attributes[i].key);free(s->attributes[i].value);}
    free(s->attributes);free(s->fragments);
    for(i=0;i<s->selection_set_count;++i)free(s->selection_sets[i].members);free(s->selection_sets);
    free(s->drag_sketches);free(s->drag_counts);free(s->objects);free(s->layers);free(s->blocks);free(s->rules);free(s);
}
const char *gx2d_status_text(gx2d_status v) {
    static const char *const names[]={"ok","invalid input","not found","locked","constraint violation","out of memory","busy","range exceeded"};
    return v>=GX2D_OK&&v<=GX2D_RANGE?names[v]:"unknown status";
}

gx2d_status gx2d_add_layer(gx2d_scene *s,const gx2d_layer_style *style,gx2d_id *out) {
    layer *v;
    if(!s||!out||!valid_layer_style(style))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    if(s->next_id==UINT64_MAX||s->layer_count==SIZE_MAX/sizeof(*v))return GX2D_RANGE;
    v=(layer *)realloc(s->layers,(s->layer_count+1)*sizeof(*v));
    if(!v)return GX2D_NOMEM;
    s->layers=v;v[s->layer_count].id=fresh(s);v[s->layer_count].style=*style;
    *out=v[s->layer_count++].id;
    return GX2D_OK;
}
gx2d_status gx2d_get_layer(const gx2d_scene *s,gx2d_id id,gx2d_layer_style *out) {
    layer *l=lyr((gx2d_scene *)s,id);
    if(!out)return GX2D_INVALID;
    if(!l)return GX2D_NOT_FOUND;
    *out=l->style;
    return GX2D_OK;
}
gx2d_status gx2d_layer_ids(const gx2d_scene *s,gx2d_id *out,size_t capacity,size_t *count){
    size_t i;
    if(!s||!count)return GX2D_INVALID;
    *count=s->layer_count;
    if(out){
        if(capacity<s->layer_count)return GX2D_RANGE;
        for(i=0;i<s->layer_count;++i)out[i]=s->layers[i].id;
    }
    return GX2D_OK;
}
gx2d_status gx2d_set_layer(gx2d_scene *s,gx2d_id id,const gx2d_layer_style *style) {
    layer *l;
    if(!s||!valid_layer_style(style))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    l=lyr(s,id);
    if(!l)return GX2D_NOT_FOUND;
    l->style=*style;
    return GX2D_OK;
}
gx2d_status gx2d_delete_layer(gx2d_scene *s,gx2d_id id) {
    size_t i,j;
    if(!s||!id)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->layer_count;++i)if(s->layers[i].id==id)break;
    if(i==s->layer_count)return GX2D_NOT_FOUND;
    for(j=0;j<s->object_count;++j)if(s->objects[j].style.layer==id)s->objects[j].style.layer=0;
    identity_remove_all(s,id);
    memmove(&s->layers[i],&s->layers[i+1],(s->layer_count-i-1)*sizeof(layer));--s->layer_count;
    return GX2D_OK;
}

gx2d_status gx2d_add_geometry(gx2d_scene *s,gx2d_kind kind,const gx2d_point *p,size_t n,gx2d_id *out) {
    object o;gx2d_status st;
    if(!s||!out||!valid_points(p,n)|| (kind!=GX2D_CURVE&&kind!=GX2D_POINT_SET&&kind!=GX2D_POINT_OBJECT) ||
       (kind==GX2D_CURVE&&n<2)||(kind==GX2D_POINT_OBJECT&&n!=1))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    memset(&o,0,sizeof(o));o.points=(gx2d_point *)malloc(n*sizeof(*p));o.manual=(unsigned char *)calloc(n,1);o.breaks=(unsigned char *)calloc(n,1);
    if(!o.points||!o.manual||!o.breaks){free(o.points);free(o.manual);free(o.breaks);
    return GX2D_NOMEM;}
    memcpy(o.points,p,n*sizeof(*p));o.count=n;o.capacity=n;o.kind=kind;o.style=default_style();
    o.direction_marker=default_direction_marker();
    if(kind!=GX2D_CURVE)o.direction_marker.present=0;
    st=append_object(s,o,out);
    if(st!=GX2D_OK){free(o.points);free(o.manual);free(o.breaks);}
    return st;
}
static int group_contains(const object *g,gx2d_id id){size_t j;for(j=0;j<g->member_count;++j)if(g->members[j]==id)return 1;
    return 0;}
gx2d_status gx2d_add_group(gx2d_scene *s,const gx2d_id *ids,size_t n,gx2d_id *out) {
    object o;size_t i,j;gx2d_status st;
    if(!s||!out||!ids||!n||n>SIZE_MAX/sizeof(*ids))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    for(i=0;i<n;++i){const object *m=cobj(s,ids[i]);
    if(!m||m->kind==GX2D_GROUP)return GX2D_INVALID;
        for(j=0;j<i;++j)if(ids[j]==ids[i])return GX2D_INVALID;}
    memset(&o,0,sizeof(o));o.members=(gx2d_id *)malloc(n*sizeof(*ids));
    if(!o.members)return GX2D_NOMEM;
    memcpy(o.members,ids,n*sizeof(*ids));o.member_count=n;o.kind=GX2D_GROUP;o.style=default_style();
    st=append_object(s,o,out);
    if(st!=GX2D_OK)free(o.members);
    return st;
}
gx2d_status gx2d_group_members(const gx2d_scene *s,gx2d_id id,gx2d_id *out,size_t capacity,size_t *count) {
    const object *o=cobj(s,id);
    if(!count)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_GROUP)return GX2D_INVALID;
    *count=o->member_count;
    if(out){if(capacity<o->member_count)return GX2D_RANGE;memcpy(out,o->members,o->member_count*sizeof(*out));}
    return GX2D_OK;
}
gx2d_status gx2d_delete_object(gx2d_scene *s,gx2d_id id) {
    size_t i,j,k;
    if(!s||!id)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->object_count;++i)if(s->objects[i].id==id)break;
    if(i==s->object_count)return GX2D_NOT_FOUND;
    identity_remove_all(s,id);
    free(s->objects[i].points);free(s->objects[i].manual);free(s->objects[i].breaks);free(s->objects[i].members);free(s->objects[i].part_states);sketch_free(s->objects[i].sketch);
    memmove(&s->objects[i],&s->objects[i+1],(s->object_count-i-1)*sizeof(object));--s->object_count;
    for(j=0;j<s->object_count;){
        if(s->objects[j].kind==GX2D_GROUP){object *g=&s->objects[j];
            for(k=0;k<g->member_count;++k)if(g->members[k]==id){memmove(&g->members[k],&g->members[k+1],(g->member_count-k-1)*sizeof(gx2d_id));--g->member_count;break;}
            if(!g->member_count){identity_remove_all(s,g->id);free(g->members);memmove(s->objects+j,s->objects+j+1,(s->object_count-j-1)*sizeof(object));--s->object_count;continue;}}
        ++j;
    }
    for(j=0;j<s->rule_count;)if(s->rules[j].spec.a==id||s->rules[j].spec.b==id||s->rules[j].axis==id){memmove(&s->rules[j],&s->rules[j+1],(s->rule_count-j-1)*sizeof(rule));--s->rule_count;}else ++j;
    return GX2D_OK;
}
gx2d_status gx2d_object_ids(const gx2d_scene *s,gx2d_id *out,size_t capacity,size_t *count){
    size_t i;
    if(!s||!count)return GX2D_INVALID;
    *count=s->object_count;
    if(out){
        if(capacity<s->object_count)return GX2D_RANGE;
        for(i=0;i<s->object_count;++i)out[i]=s->objects[i].id;
    }
    return GX2D_OK;
}
gx2d_status gx2d_kind_of(const gx2d_scene *s,gx2d_id id,gx2d_kind *out){const object *o=cobj(s,id);
    if(!out)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    *out=o->kind;
    return GX2D_OK;}
gx2d_status gx2d_get_style(const gx2d_scene *s,gx2d_id id,gx2d_style *out){const object *o=cobj(s,id);
    if(!out)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    *out=o->style;
    return GX2D_OK;}
gx2d_status gx2d_set_style(gx2d_scene *s,gx2d_id id,const gx2d_style *style){object *o;
    if(!s||!valid_style(style))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);
    if(!o)return GX2D_NOT_FOUND;
    if(style->layer&&!lyr(s,style->layer))return GX2D_NOT_FOUND;
    o->style=*style;
    return GX2D_OK;
}
gx2d_status gx2d_point_count(const gx2d_scene *s,gx2d_id id,size_t *out){const object *o=cobj(s,id);
    if(!out)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    *out=o->count;
    return GX2D_OK;}
gx2d_status gx2d_get_points(const gx2d_scene *s,gx2d_id id,gx2d_point *out,size_t capacity,size_t *count){const object *o=cobj(s,id);
    if(!count)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    *count=o->count;
    if(out){if(capacity<o->count)return GX2D_RANGE;memcpy(out,o->points,o->count*sizeof(*out));}
    return GX2D_OK;
}
gx2d_status gx2d_endpoints(const gx2d_scene *s,gx2d_id id,gx2d_point *a,gx2d_point *b){const object *o=cobj(s,id);
    if(!a||!b)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch&&o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE)return GX2D_INVALID;
    *a=o->points[0];*b=o->points[o->count-1];
    return GX2D_OK;
}
gx2d_status gx2d_direction(const gx2d_scene *s,gx2d_id id,size_t segment,gx2d_point *out){const object *o=cobj(s,id);gx2d_point a,b;double len;
    if(!out)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(segment==SIZE_MAX){a=o->points[0];b=o->points[o->count-1];}
    else {if(segment>=o->count-1)return GX2D_RANGE;a=o->points[segment];b=o->points[segment+1];}
    len=dist(a,b);
    if(len<=DBL_EPSILON)return GX2D_CONSTRAINT;
    out->x=(b.x-a.x)/len;out->y=(b.y-a.y)/len;
    return GX2D_OK;
}

static int member_selected(const gx2d_scene *s,const object *o){
    size_t i;for(i=0;i<s->object_count;++i)if(s->objects[i].kind==GX2D_GROUP&&s->objects[i].style.selected&&group_contains(&s->objects[i],o->id))return 1;
    return 0;
}
static int selected_at(const gx2d_scene *s,const object *o,size_t j){
    if(o->manual[j]==2)return 0;
    return member_selected(s,o)||point_selected_at(s,o,j);
}
gx2d_status gx2d_clear_selection(gx2d_scene *s){if(!s)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    clear_manual(s);s->block_count=0;
    return GX2D_OK;}
gx2d_status gx2d_drag_is_active(const gx2d_scene *s,int *active){
    if(!s||!active)return GX2D_INVALID;
    *active=s->dragging?1:0;return GX2D_OK;
}
gx2d_status gx2d_selection_replace_points(gx2d_scene *s,gx2d_id id,const size_t *indices,size_t count){
    object *o;size_t i;
    if(!s||(count&&!indices))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(!can_select(s,o))return GX2D_LOCKED;
    for(i=0;i<count;++i)if(indices[i]>=o->count)return GX2D_RANGE;
    clear_manual(s);s->block_count=0;
    for(i=0;i<count;++i)o->manual[indices[i]]=1;
    return GX2D_OK;
}
gx2d_status gx2d_selection_patch_points(gx2d_scene *s,gx2d_id id,size_t start,size_t count,const size_t *indices,size_t selected){
    object *o;size_t i;
    if(!s||(selected&&!indices)||count>65536)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(!can_select(s,o))return GX2D_LOCKED;
    if(start>o->count||count>o->count-start)return GX2D_RANGE;
    for(i=0;i<selected;++i)if(indices[i]<start||indices[i]-start>=count)return GX2D_RANGE;
    if(count)memset(o->manual+start,2,count);
    for(i=0;i<selected;++i)o->manual[indices[i]]=1;
    return GX2D_OK;
}
gx2d_status gx2d_select_object(gx2d_scene *s,gx2d_id id,gx2d_select_mode mode){object *o;
    if(!s||mode<GX2D_SELECT_REPLACE||mode>GX2D_SELECT_SUBTRACT)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);
    if(!o)return GX2D_NOT_FOUND;
    if(!can_select(s,o))return GX2D_LOCKED;
    if(mode==GX2D_SELECT_REPLACE){clear_manual(s);s->block_count=0;}
    o->style.selected=mode!=GX2D_SELECT_SUBTRACT;
    if(mode==GX2D_SELECT_SUBTRACT&&o->manual)memset(o->manual,0,o->count);
    return GX2D_OK;
}
gx2d_status gx2d_selection_regions(const gx2d_scene *s,gx2d_id id,gx2d_selection_region *out,size_t cap,size_t *count,int *base){
    const object *o=cobj(s,id);size_t i;
    if(!s||!count||!base)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(out&&cap<s->block_count)return GX2D_RANGE;
    *count=s->block_count;*base=can_select(s,o)&&o->style.selected;
    if(out)for(i=0;i<s->block_count;++i){out[i].bounds=s->blocks[i].rect;out[i].mode=s->blocks[i].mode;}
    return GX2D_OK;
}
gx2d_status gx2d_selection_manual_range(const gx2d_scene *s,gx2d_id id,size_t start,size_t count,unsigned char *out,size_t cap){
    const object *o=cobj(s,id);
    if(!s||(!out&&count))return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP||start>o->count||count>o->count-start||count>65536||cap<count)return GX2D_RANGE;
    if(count)memcpy(out,o->manual+start,count);
    return GX2D_OK;
}
gx2d_status gx2d_select_point(gx2d_scene *s,gx2d_id id,size_t j,gx2d_select_mode mode){object *o;
    if(!s||mode<GX2D_SELECT_REPLACE||mode>GX2D_SELECT_SUBTRACT)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP||j>=o->count)return GX2D_RANGE;
    if(!can_select(s,o))return GX2D_LOCKED;
    if(mode==GX2D_SELECT_REPLACE){clear_manual(s);s->block_count=0;}
    o->manual[j]=mode==GX2D_SELECT_SUBTRACT?2:1;
    if(mode==GX2D_SELECT_SUBTRACT&&o->style.selected){size_t k; o->style.selected=0;for(k=0;k<o->count;++k)o->manual[k]=k==j?2:1;}
    return GX2D_OK;
}
gx2d_status gx2d_point_selected(const gx2d_scene *s,gx2d_id id,size_t j,int *out){const object *o=cobj(s,id);
    if(!out)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP||j>=o->count)return GX2D_RANGE;
    *out=selected_at(s,o,j);
    return GX2D_OK;
}
gx2d_status gx2d_select_rect(gx2d_scene *s,gx2d_rect r,gx2d_select_mode mode,gx2d_id *out){block *v;
    if(!s||!out||!valid_rect(r)||mode<GX2D_SELECT_REPLACE||mode>GX2D_SELECT_SUBTRACT)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    if(s->next_id==UINT64_MAX||s->block_count==SIZE_MAX/sizeof(*v))return GX2D_RANGE;
    v=(block *)realloc(s->blocks,(s->block_count+1)*sizeof(*v));
    if(!v)return GX2D_NOMEM;
    s->blocks=v;
    if(mode==GX2D_SELECT_REPLACE){clear_manual(s);s->block_count=0;}
    v[s->block_count].id=fresh(s);v[s->block_count].rect=r;
    v[s->block_count].mode=mode==GX2D_SELECT_REPLACE?GX2D_SELECT_ADD:mode;
    *out=v[s->block_count++].id;
    return GX2D_OK;
}
gx2d_status gx2d_remove_rect(gx2d_scene *s,gx2d_id id){size_t i;
    if(!s||!id)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->block_count;++i)if(s->blocks[i].id==id)break;
    if(i==s->block_count)return GX2D_NOT_FOUND;
    memmove(&s->blocks[i],&s->blocks[i+1],(s->block_count-i-1)*sizeof(block));--s->block_count;
    return GX2D_OK;
}
gx2d_status gx2d_export_selected(const gx2d_scene *s,gx2d_id id,gx2d_point *out,size_t cap,size_t *count){const object *o=cobj(s,id);size_t j,n=0;
    if(!count)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    for(j=0;j<o->count;++j)if(selected_at(s,o,j))++n;
    *count=n;
    if(out){if(cap<n)return GX2D_RANGE;n=0;for(j=0;j<o->count;++j)if(selected_at(s,o,j))out[n++]=o->points[j];}
    return GX2D_OK;
}
gx2d_status gx2d_hit_test(const gx2d_scene *s,gx2d_id id,gx2d_point p,double tolerance,gx2d_hit *hit){const object *o=cobj(s,id);gx2d_status st;
    if(!hit||!finite2(p)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(!can_select(s,o))return GX2D_NOT_FOUND;
    st=closest(s,o,p,hit);
    return st==GX2D_OK&&hit->distance<=tolerance?GX2D_OK:GX2D_NOT_FOUND;
}
gx2d_status gx2d_hit_point_device(const gx2d_scene *s,gx2d_id id,gx2d_point p,double tolerance,gx2d_hit *hit){
    const object *o=cobj(s,id);const gx2d_view *v;double sx,sy,best=tolerance;size_t i,index=0;int found=0;
    if(!s||!hit||!finite2(p)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(!can_select(s,o))return GX2D_NOT_FOUND;
    v=&s->view;sx=(v->width-v->left-v->right)/(v->world.x1-v->world.x0);sy=(v->height-v->top-v->bottom)/(v->world.y1-v->world.y0);
    if(p.x<v->left-tolerance||p.x>v->width-v->right+tolerance||p.y<v->top-tolerance||p.y>v->height-v->bottom+tolerance)return GX2D_NOT_FOUND;
    for(i=0;i<o->count;++i){double x=v->left+(o->points[i].x-v->world.x0)*sx,y=v->top+(v->world.y1-o->points[i].y)*sy,d=hypot(x-p.x,y-p.y);
        if(d<=best&&(!found||d<best)){index=i;best=d;found=1;}}
    if(!found)return GX2D_NOT_FOUND;
    *hit=(gx2d_hit){id,index,o->points[index],best};return GX2D_OK;
}
gx2d_status gx2d_nearest(const gx2d_scene *s,gx2d_point p,double max_distance,gx2d_hit *hit){size_t i;gx2d_hit h;double best=max_distance;int found=0;
    if(!s||!hit||!finite2(p)||!isfinite(max_distance)||max_distance<0)return GX2D_INVALID;
    for(i=0;i<s->object_count;++i){const object *o=&s->objects[i];
    if(o->kind==GX2D_GROUP||!can_select(s,o))continue;
        if(closest(s,o,p,&h)==GX2D_OK&&h.distance<=best){best=h.distance;*hit=h;found=1;}}
    return found?GX2D_OK:GX2D_NOT_FOUND;
}

static gx2d_status direction_raw(const object *o,gx2d_point *d){gx2d_point a,b;double length;
    if(!o||o->kind!=GX2D_CURVE)return GX2D_INVALID;
    a=o->points[0];b=o->points[o->count-1];length=dist(a,b);
    if(length<=DBL_EPSILON)return GX2D_CONSTRAINT;
    d->x=(b.x-a.x)/length;d->y=(b.y-a.y)/length;
    return GX2D_OK;
}
static gx2d_status rule_check(const gx2d_scene *s,const rule *r){
    if(r->disabled)return GX2D_OK;
    if(r->spec.kind>GX2D_PERPENDICULAR||r->spec.a_index>=GX2D_CONTROL_INDEX||r->spec.b_index>=GX2D_CONTROL_INDEX)return rule_check_extended(s,r,NULL);
    const gx2d_constraint *c=&r->spec;const object *a=cobj(s,c->a),*b=c->b?cobj(s,c->b):NULL;
    gx2d_point da,db;double value,delta;
    if(!a||c->a_index>=a->count)return GX2D_CONSTRAINT;
    if(c->kind==GX2D_FIXED)return dist(a->points[c->a_index],r->anchor)<=c->tolerance?GX2D_OK:GX2D_CONSTRAINT;
    if(!b||c->b_index>=b->count)return GX2D_CONSTRAINT;
    if(c->kind==GX2D_DISTANCE)return fabs(dist(a->points[c->a_index],b->points[c->b_index])-c->value)<=c->tolerance?GX2D_OK:GX2D_CONSTRAINT;
    if(direction_raw(a,&da)!=GX2D_OK||direction_raw(b,&db)!=GX2D_OK)return GX2D_CONSTRAINT;
    value=atan2(da.x*db.y-da.y*db.x,da.x*db.x+da.y*db.y);
    if(c->kind==GX2D_ANGLE){delta=atan2(sin(value-c->value),cos(value-c->value));
    return fabs(delta)<=c->tolerance?GX2D_OK:GX2D_CONSTRAINT;}
    if(c->kind==GX2D_PARALLEL)return fabs(sin(value))<=c->tolerance?GX2D_OK:GX2D_CONSTRAINT;
    if(c->kind==GX2D_PERPENDICULAR)return fabs(cos(value))<=c->tolerance?GX2D_OK:GX2D_CONSTRAINT;
    return GX2D_INVALID;
}
gx2d_status gx2d_check_constraints(const gx2d_scene *s){size_t i;
    if(!s)return GX2D_INVALID;
    for(i=0;i<s->rule_count;++i)if(rule_check(s,&s->rules[i])!=GX2D_OK)return GX2D_CONSTRAINT;
    return GX2D_OK;
}
gx2d_status gx2d_add_constraint(gx2d_scene *s,const gx2d_constraint *c,gx2d_id *out){rule r,*v;const object *a,*b;
    if(!s||!c||!out||c->kind<GX2D_FIXED||c->kind>GX2D_PERPENDICULAR||!isfinite(c->tolerance)||c->tolerance<=0||!isfinite(c->value))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    a=cobj(s,c->a);b=c->b?cobj(s,c->b):NULL;
    if(!a||a->kind==GX2D_GROUP||c->a_index>=a->count)return GX2D_INVALID;
    if(c->kind!=GX2D_FIXED&&(!b||b->kind==GX2D_GROUP||c->b_index>=b->count))return GX2D_INVALID;
    if(c->kind==GX2D_DISTANCE&&c->value<0)return GX2D_INVALID;
    if(c->kind>=GX2D_ANGLE&&(a->kind!=GX2D_CURVE||b->kind!=GX2D_CURVE))return GX2D_INVALID;
    if(s->next_id==UINT64_MAX||s->rule_count==SIZE_MAX/sizeof(*v))return GX2D_RANGE;
    memset(&r,0,sizeof(r));r.spec=*c;r.anchor=a->points[c->a_index];
    if(rule_check(s,&r)!=GX2D_OK)return GX2D_CONSTRAINT;
    v=(rule *)realloc(s->rules,(s->rule_count+1)*sizeof(*v));
    if(!v)return GX2D_NOMEM;
    s->rules=v;r.id=fresh(s);s->rules[s->rule_count++]=r;
    *out=r.id;
    return GX2D_OK;
}
gx2d_status gx2d_remove_constraint(gx2d_scene *s,gx2d_id id){size_t i;
    if(!s||!id)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->rule_count;++i)if(s->rules[i].id==id)break;
    if(i==s->rule_count)return GX2D_NOT_FOUND;
    memmove(&s->rules[i],&s->rules[i+1],(s->rule_count-i-1)*sizeof(rule));--s->rule_count;
    return GX2D_OK;
}

static void drag_free(gx2d_scene *s){size_t i;
    if(s->drag_points){for(i=0;i<s->object_count;++i)free(s->drag_points[i]);free(s->drag_points);s->drag_points=NULL;}
    if(s->drag_masks){for(i=0;i<s->object_count;++i)free(s->drag_masks[i]);free(s->drag_masks);s->drag_masks=NULL;}
    if(s->drag_retained){for(i=0;i<s->object_count;i++)sketch_free(s->drag_retained[i]);free(s->drag_retained);s->drag_retained=NULL;}
    free(s->drag_sketches);s->drag_sketches=NULL;free(s->drag_counts);s->drag_counts=NULL;s->dragging=0;
}
static void drag_restore(gx2d_scene *s){size_t i;
    for(i=0;i<s->object_count;++i)if(s->drag_points[i]&&s->drag_counts[i]==s->objects[i].count){
        memcpy(s->objects[i].points,s->drag_points[i],s->objects[i].count*sizeof(gx2d_point));
        if(s->objects[i].sketch&&s->drag_retained[i]){
            gx2d_sketch_definition *current=s->objects[i].sketch,*saved=s->drag_retained[i];
            /* Retain every live owned buffer. Copying snapshot pointers makes
             * unselected definitions dangle when drag_free releases snapshots.
             * Topology cannot change while this captured drag is active. */
            sketch_restore_owned(current,saved);
        }
    }
}
gx2d_status gx2d_drag_begin(gx2d_scene *s){size_t i,j;int any=0;
    if(!s)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    for(i=0;i<s->object_count;++i)if(s->objects[i].kind==GX2D_GROUP&&s->objects[i].style.selected&&!can_move(s,&s->objects[i]))return GX2D_LOCKED;
    s->drag_points=(gx2d_point **)calloc(s->object_count? s->object_count:1,sizeof(gx2d_point *));
    s->drag_masks=(unsigned char **)calloc(s->object_count? s->object_count:1,sizeof(unsigned char *));
    s->drag_counts=(size_t *)calloc(s->object_count? s->object_count:1,sizeof(size_t));
    s->drag_sketches=(gx2d_sketch_definition *)calloc(s->object_count?s->object_count:1,sizeof(*s->drag_sketches));
    s->drag_retained=calloc(s->object_count?s->object_count:1,sizeof(*s->drag_retained));
    if(!s->drag_retained||!s->drag_points||!s->drag_masks||!s->drag_counts||!s->drag_sketches){drag_free(s);
    return GX2D_NOMEM;}
    for(i=0;i<s->object_count;++i){object *o=&s->objects[i];int has_selected=0;
    if(!o->count)continue;
    for(j=0;j<o->count;++j)if(selected_at(s,o,j)){has_selected=1;break;}
    if(!has_selected&&!o->sketch)continue;
    if(o->sketch){s->drag_retained[i]=sketch_clone(o->sketch);if(!s->drag_retained[i]){drag_free(s);return GX2D_NOMEM;}for(j=0;has_selected&&j<o->count;++j)if(!selected_at(s,o,j)){drag_free(s);return GX2D_INVALID;}s->drag_sketches[i]=*o->sketch;}
    if(has_selected&&!can_move(s,o)){drag_free(s);return GX2D_LOCKED;}
    s->drag_points[i]=(gx2d_point *)malloc(o->count*sizeof(gx2d_point));
        s->drag_masks[i]=(unsigned char *)calloc(o->count,1);
        if(!s->drag_points[i]||!s->drag_masks[i]){drag_free(s);
    return GX2D_NOMEM;}
        s->drag_counts[i]=o->count;memcpy(s->drag_points[i],o->points,o->count*sizeof(gx2d_point));
        for(j=0;j<o->count;++j)if(selected_at(s,o,j)){
            s->drag_masks[i][j]=1;any=1;
        }
    }
    if(!any){drag_free(s);
    return GX2D_INVALID;}
    {gx2d_pivot_mode mode;gx2d_status pivot_status=gx2d_pivot_get(s,&mode,&s->drag_pivot);
        if(pivot_status!=GX2D_OK){drag_free(s);return pivot_status;}}
    s->drag_view=s->view;s->dragging=1;
    return GX2D_OK;
}
gx2d_status gx2d_drag_translate(gx2d_scene *s,double dx,double dy){size_t i,j;
    if(!s||!isfinite(dx)||!isfinite(dy))return GX2D_INVALID;
    if(!s->dragging)return GX2D_INVALID;
    drag_restore(s);
    for(i=0;i<s->object_count;++i)for(j=0;j<s->drag_counts[i];++j)if(s->drag_masks[i][j]){
        s->objects[i].points[j].x+=dx;s->objects[i].points[j].y+=dy;
        if(!finite2(s->objects[i].points[j])){drag_restore(s);
    return GX2D_RANGE;}
    }
    {double matrix[6]={1,0,0,1,dx,dy};for(i=0;i<s->object_count;++i)if(s->drag_counts[i]&&s->objects[i].sketch&&s->drag_masks[i]&&s->drag_masks[i][0]&&!sketch_compose(s->objects[i].sketch,matrix)){drag_restore(s);return GX2D_RANGE;}}
    return GX2D_OK;
}
gx2d_status gx2d_drag_rotate(gx2d_scene *s,gx2d_point pivot,double radians){size_t i,j;double co,si,x,y;
    if(!s||!finite2(pivot)||!isfinite(radians))return GX2D_INVALID;
    if(!s->dragging)return GX2D_INVALID;
    co=cos(radians);si=sin(radians);drag_restore(s);
    for(i=0;i<s->object_count;++i)for(j=0;j<s->drag_counts[i];++j)if(s->drag_masks[i][j]){
        x=s->drag_points[i][j].x-pivot.x;y=s->drag_points[i][j].y-pivot.y;
        s->objects[i].points[j].x=pivot.x+co*x-si*y;
        s->objects[i].points[j].y=pivot.y+si*x+co*y;
        if(!finite2(s->objects[i].points[j])){drag_restore(s);
    return GX2D_RANGE;}
    }
    {double matrix[6];gx2d_status code=gx2d_rotation_matrix(pivot,radians,matrix);if(code!=GX2D_OK){drag_restore(s);return code;}for(i=0;i<s->object_count;++i)if(s->drag_counts[i]&&s->objects[i].sketch&&s->drag_masks[i]&&s->drag_masks[i][0]&&!sketch_compose(s->objects[i].sketch,matrix)){drag_restore(s);return GX2D_RANGE;}}
    return GX2D_OK;
}
gx2d_status gx2d_drag_commit(gx2d_scene *s){gx2d_status st;
    if(!s||!s->dragging)return GX2D_INVALID;
    st=sketch_solve_drag(s);
    if(st==GX2D_OK)st=gx2d_check_constraints(s);
    if(st!=GX2D_OK){drag_restore(s);
    return st;}
    drag_free(s);
    return GX2D_OK;
}
gx2d_status gx2d_drag_cancel(gx2d_scene *s){if(!s||!s->dragging)return GX2D_INVALID;drag_restore(s);drag_free(s);
    return GX2D_OK;}
gx2d_status gx2d_translate_selected(gx2d_scene *s,double dx,double dy){gx2d_status st;
    st=gx2d_drag_begin(s);
    if(st!=GX2D_OK)return st;
    st=gx2d_drag_translate(s,dx,dy);
    if(st==GX2D_OK)st=gx2d_drag_commit(s);
    if(st!=GX2D_OK)gx2d_drag_cancel(s);
    return st;
}
gx2d_status gx2d_rotate_selected(gx2d_scene *s,gx2d_point pivot,double radians){gx2d_status st;
    st=gx2d_drag_begin(s);
    if(st!=GX2D_OK)return st;
    st=gx2d_drag_rotate(s,pivot,radians);
    if(st==GX2D_OK)st=gx2d_drag_commit(s);
    if(st!=GX2D_OK)gx2d_drag_cancel(s);
    return st;
}
gx2d_status gx2d_replace_points(gx2d_scene *s,gx2d_id id,const gx2d_point *p,size_t n){object *o;gx2d_point *newp,*oldp;unsigned char *newsel,*oldsel,*newbreak,*oldbreak;size_t m;gx2d_status st;
    if(!s||!valid_points(p,n))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP||(o->kind==GX2D_CURVE&&n<2)||(o->kind==GX2D_POINT_OBJECT&&n!=1))return GX2D_INVALID;
    if(o->sketch)return GX2D_INVALID;
    if(n!=o->count&&extended_constraint_references(s,id))return GX2D_CONSTRAINT;
    if(!can_move(s,o))return GX2D_LOCKED;
    newp=(gx2d_point *)malloc(n*sizeof(*newp));newsel=(unsigned char *)calloc(n,1);newbreak=(unsigned char *)calloc(n,1);
    if(!newp||!newsel||!newbreak){free(newp);free(newsel);free(newbreak);
    return GX2D_NOMEM;}
    memcpy(newp,p,n*sizeof(*p));m=n<o->count?n:o->count;memcpy(newsel,o->manual,m);
    if(m>1)memcpy(newbreak,o->breaks,(m-1));
    oldp=o->points;oldsel=o->manual;oldbreak=o->breaks;m=o->count;o->points=newp;o->manual=newsel;o->breaks=newbreak;o->count=n;
    st=gx2d_check_constraints(s);
    if(st!=GX2D_OK){o->points=oldp;o->manual=oldsel;o->breaks=oldbreak;o->count=m;free(newp);free(newsel);free(newbreak);
    return st;}
    free(oldp);free(oldsel);free(oldbreak);o->capacity=n;if(n!=m)++o->topology_epoch;
    return GX2D_OK;
}
gx2d_status gx2d_append_points(gx2d_scene *s,gx2d_id id,const gx2d_point *points,size_t n) {
    object *o;gx2d_point *newp,*oldp;unsigned char *newsel,*newbreak,*oldsel,*oldbreak;
    size_t oldcount,total,capacity;gx2d_status code;
    if(!s||!valid_points(points,n)||n>65536)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE&&o->kind!=GX2D_POINT_SET)return GX2D_INVALID;
    if(o->sketch)return GX2D_INVALID;
    if(extended_constraint_references(s,id))return GX2D_CONSTRAINT;
    if(!can_move(s,o))return GX2D_LOCKED;
    if(n>SIZE_MAX/sizeof(*points)-o->count)return GX2D_RANGE;
    oldcount=o->count;total=oldcount+n;capacity=o->capacity;
    if(total<=capacity){
        memcpy(o->points+oldcount,points,n*sizeof(*points));memset(o->manual+oldcount,0,n);memset(o->breaks+oldcount,0,n);
        o->count=total;code=gx2d_check_constraints(s);if(code!=GX2D_OK)o->count=oldcount;else ++o->topology_epoch;return code;
    }
    if(capacity<2)capacity=2;
    while(capacity<total){if(capacity>SIZE_MAX/sizeof(*points)/2){capacity=total;break;}capacity*=2;}
    newp=(gx2d_point *)malloc(capacity*sizeof(*points));newsel=(unsigned char *)calloc(capacity,1);newbreak=(unsigned char *)calloc(capacity,1);
    if(!newp||!newsel||!newbreak){free(newp);free(newsel);free(newbreak);return GX2D_NOMEM;}
    memcpy(newp,o->points,oldcount*sizeof(*points));memcpy(newp+oldcount,points,n*sizeof(*points));memcpy(newsel,o->manual,oldcount);memcpy(newbreak,o->breaks,oldcount);
    oldp=o->points;oldsel=o->manual;oldbreak=o->breaks;o->points=newp;o->manual=newsel;o->breaks=newbreak;o->count=total;
    code=gx2d_check_constraints(s);
    if(code!=GX2D_OK){o->points=oldp;o->manual=oldsel;o->breaks=oldbreak;o->count=oldcount;free(newp);free(newsel);free(newbreak);return code;}
    free(oldp);free(oldsel);free(oldbreak);o->capacity=capacity;++o->topology_epoch;return GX2D_OK;
}
static gx2d_status move_one(gx2d_scene *s,object *o,size_t j,gx2d_point p){gx2d_point old;gx2d_status st;
    if(!finite2(p))return GX2D_INVALID;
    if(o->sketch)return GX2D_INVALID;
    if(!can_move(s,o))return GX2D_LOCKED;
    old=o->points[j];o->points[j]=p;
    st=gx2d_check_constraints(s);
    if(st!=GX2D_OK)o->points[j]=old;
    return st;
}
gx2d_status gx2d_snap_point(gx2d_scene *s,gx2d_id source,size_t source_index,gx2d_id target,size_t target_index){object *a,*b;
    if(!s)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    a=obj(s,source);b=obj(s,target);
    if(!a||!b)return GX2D_NOT_FOUND;
    if(a->kind==GX2D_GROUP||b->kind==GX2D_GROUP||source_index>=a->count||target_index>=b->count)return GX2D_RANGE;
    return move_one(s,a,source_index,b->points[target_index]);
}
gx2d_status gx2d_snap_to_curve(gx2d_scene *s,gx2d_id source,size_t index,gx2d_id curve){object *a,*b;gx2d_point q,best;double d=DBL_MAX,current;size_t j;
    if(!s)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    a=obj(s,source);b=obj(s,curve);
    if(!a||!b)return GX2D_NOT_FOUND;
    if(a->kind==GX2D_GROUP||index>=a->count||b->kind!=GX2D_CURVE)return GX2D_INVALID;
    for(j=0;j+1<b->count;++j){q=nearest_segment(a->points[index],b->points[j],b->points[j+1]);current=dist(a->points[index],q);
    if(current<d){d=current;best=q;}}
    return move_one(s,a,index,best);
}
gx2d_status gx2d_align_direction(gx2d_scene *s,gx2d_id moving,gx2d_id reference,double relative,gx2d_point pivot){object *a,*b;gx2d_point da,db,*backup;double desired,current,angle,co,si,x,y;size_t i;gx2d_status st;
    if(!s||!isfinite(relative)||!finite2(pivot))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    a=obj(s,moving);b=obj(s,reference);
    if(!a||!b)return GX2D_NOT_FOUND;
    if(a==b||a->kind!=GX2D_CURVE||b->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(!can_move(s,a))return GX2D_LOCKED;
    if(direction_raw(a,&da)!=GX2D_OK||direction_raw(b,&db)!=GX2D_OK)return GX2D_CONSTRAINT;
    current=atan2(da.y,da.x);desired=atan2(db.y,db.x)+relative;
    angle=atan2(sin(desired-current),cos(desired-current));co=cos(angle);si=sin(angle);
    if(a->sketch){double matrix[6];st=gx2d_rotation_matrix(pivot,angle,matrix);return st==GX2D_OK?gx2d_affine_objects(s,&moving,1,matrix):st;}
    backup=(gx2d_point *)malloc(a->count*sizeof(*backup));
    if(!backup)return GX2D_NOMEM;
    memcpy(backup,a->points,a->count*sizeof(*backup));
    for(i=0;i<a->count;++i){x=backup[i].x-pivot.x;y=backup[i].y-pivot.y;
        a->points[i].x=pivot.x+co*x-si*y;a->points[i].y=pivot.y+si*x+co*y;
        if(!finite2(a->points[i])){memcpy(a->points,backup,a->count*sizeof(*backup));free(backup);
    return GX2D_RANGE;}}
    st=gx2d_check_constraints(s);
    if(st!=GX2D_OK)memcpy(a->points,backup,a->count*sizeof(*backup));
    free(backup);
    return st;
}

/* The edit operations deliberately delegate replacement to the existing
 * constraint-aware atomic mutation path. New derived objects keep new IDs. */
static gx2d_status curve_for_edit(gx2d_scene *s,gx2d_id id,object **out){
    if(!s||!out)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    *out=obj(s,id);
    if(!*out)return GX2D_NOT_FOUND;
    if((*out)->kind!=GX2D_CURVE)return GX2D_INVALID;
    if((*out)->sketch)return GX2D_INVALID;
    if(extended_constraint_references(s,id))return GX2D_CONSTRAINT;
    return can_move(s,*out)?GX2D_OK:GX2D_LOCKED;
}
gx2d_status gx2d_insert_point(gx2d_scene *s,gx2d_id id,size_t at,gx2d_point p){
    object *o;gx2d_point *v;unsigned char *breaks,*manual;size_t oldCount,i;gx2d_status st=curve_for_edit(s,id,&o);
    if(st!=GX2D_OK)return st;
    if(!finite2(p)||at>o->count)return GX2D_RANGE;
    if(o->count>=SIZE_MAX/sizeof(*v)-1)return GX2D_RANGE;
    oldCount=o->count;v=(gx2d_point *)malloc((oldCount+1)*sizeof(*v));breaks=(unsigned char *)malloc(oldCount);manual=(unsigned char *)malloc(oldCount);
    if(!v||!breaks||!manual){free(v);free(breaks);free(manual);return GX2D_NOMEM;}
    memcpy(breaks,o->breaks,oldCount);memcpy(manual,o->manual,oldCount);
    memcpy(v,o->points,at*sizeof(*v));v[at]=p;
    memcpy(v+at+1,o->points+at,(o->count-at)*sizeof(*v));
    st=gx2d_replace_points(s,id,v,oldCount+1);
    if(st==GX2D_OK){o=obj(s,id);memset(o->breaks,0,o->count);memset(o->manual,0,o->count);
        for(i=0;i<oldCount;++i){size_t dst=i>=at?i+1:i;o->manual[dst]=manual[i];if(i+1<oldCount)o->breaks[dst]=breaks[i];}}
    free(v);free(breaks);free(manual);return st;
}
gx2d_status gx2d_remove_point(gx2d_scene *s,gx2d_id id,size_t at){
    object *o;gx2d_point *v;unsigned char *breaks,*manual;size_t oldCount,i;gx2d_status st=curve_for_edit(s,id,&o);
    if(st!=GX2D_OK)return st;
    if(at>=o->count||o->count<=2)return GX2D_RANGE;
    oldCount=o->count;v=(gx2d_point *)malloc((oldCount-1)*sizeof(*v));breaks=(unsigned char *)malloc(oldCount);manual=(unsigned char *)malloc(oldCount);
    if(!v||!breaks||!manual){free(v);free(breaks);free(manual);return GX2D_NOMEM;}
    memcpy(breaks,o->breaks,oldCount);memcpy(manual,o->manual,oldCount);
    memcpy(v,o->points,at*sizeof(*v));
    memcpy(v+at,o->points+at+1,(o->count-at-1)*sizeof(*v));
    st=gx2d_replace_points(s,id,v,oldCount-1);
    if(st==GX2D_OK){o=obj(s,id);memset(o->breaks,0,o->count);memset(o->manual,0,o->count);
        for(i=0;i<oldCount;++i){if(i!=at)o->manual[i>at?i-1:i]=manual[i];
            if(i+1<oldCount&&breaks[i]){
                if(i+1<at)o->breaks[i]=1;
                else if(i>at)o->breaks[i-1]=1;
                else if(at>0&&at<oldCount-1)o->breaks[at-1]=1;}}
        if(at>0&&at<oldCount-1)o->breaks[at-1]=1;}
    free(v);free(breaks);free(manual);return st;
}
gx2d_status gx2d_set_point(gx2d_scene *s,gx2d_id id,size_t at,gx2d_point p){
    object *o=obj(s,id);if(!s||!finite2(p))return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP||at>=o->count)return GX2D_RANGE;
    if(s->dragging)return GX2D_BUSY;
    if(!can_move(s,o))return GX2D_LOCKED;
    return move_one(s,o,at,p);
}
gx2d_status gx2d_reverse_points(gx2d_scene *s,gx2d_id id){
    object *o;gx2d_point *v;unsigned char *breaks,*manual;size_t i,n;gx2d_status st=curve_for_edit(s,id,&o);
    if(st!=GX2D_OK)return st;
    n=o->count;v=(gx2d_point *)malloc(n*sizeof(*v));breaks=(unsigned char *)malloc(n);manual=(unsigned char *)malloc(n);
    if(!v||!breaks||!manual){free(v);free(breaks);free(manual);return GX2D_NOMEM;}
    memcpy(breaks,o->breaks,n);memcpy(manual,o->manual,n);
    for(i=0;i<n;++i)v[i]=o->points[n-i-1];
    st=gx2d_replace_points(s,id,v,n);
    if(st==GX2D_OK){o=obj(s,id);++o->topology_epoch;for(i=0;i<n;++i){o->manual[i]=manual[n-i-1];o->breaks[i]=i+1<n?breaks[n-i-2]:0;}}
    free(v);free(breaks);free(manual);return st;
}
gx2d_status gx2d_move_point(gx2d_scene *s,gx2d_id id,size_t from,size_t to){
    object *o;gx2d_point *v;unsigned char *mask;gx2d_point moved;unsigned char selected;size_t i;gx2d_status st=curve_for_edit(s,id,&o);
    if(st!=GX2D_OK)return st;
    if(from>=o->count||to>=o->count)return GX2D_RANGE;
    for(i=0;i+1<o->count;++i)if(o->breaks[i])return GX2D_INVALID;
    if(from==to)return GX2D_OK;
    v=(gx2d_point *)malloc(o->count*sizeof(*v));mask=(unsigned char *)malloc(o->count);
    if(!v||!mask){free(v);free(mask);return GX2D_NOMEM;}
    memcpy(v,o->points,o->count*sizeof(*v));memcpy(mask,o->manual,o->count);
    moved=v[from];selected=mask[from];
    if(from<to){for(i=from;i<to;++i){v[i]=v[i+1];mask[i]=mask[i+1];}}
    else {for(i=from;i>to;--i){v[i]=v[i-1];mask[i]=mask[i-1];}}
    v[to]=moved;mask[to]=selected;
    st=gx2d_replace_points(s,id,v,o->count);
    if(st==GX2D_OK){memcpy(obj(s,id)->manual,mask,o->count);++o->topology_epoch;}
    free(v);free(mask);return st;
}
gx2d_status gx2d_select_x_interval(gx2d_scene *s,gx2d_id id,double xmin,double xmax,gx2d_select_mode mode){
    object *o;size_t i;
    if(!s||!isfinite(xmin)||!isfinite(xmax)||xmin>xmax||mode<GX2D_SELECT_REPLACE||mode>GX2D_SELECT_SUBTRACT)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(!can_select(s,o))return GX2D_LOCKED;
    if(mode==GX2D_SELECT_REPLACE){clear_manual(s);s->block_count=0;}
    for(i=0;i<o->count;++i)if(o->points[i].x>=xmin&&o->points[i].x<=xmax)o->manual[i]=mode==GX2D_SELECT_SUBTRACT?2:1;
    return GX2D_OK;
}
gx2d_status gx2d_set_breaks(gx2d_scene *s,gx2d_id id,const size_t *indices,size_t count){
    object *o;unsigned char *mask,*old;size_t i;gx2d_status code;
    if(!s||(!indices&&count))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE||o->sketch)return GX2D_INVALID;
    if(!can_move(s,o))return GX2D_LOCKED;
    mask=(unsigned char *)calloc(o->count,1);if(!mask)return GX2D_NOMEM;
    for(i=0;i<count;++i){if(indices[i]>=o->count-1||mask[indices[i]]){free(mask);return GX2D_RANGE;}mask[indices[i]]=1;}
    old=o->breaks;o->breaks=mask;code=gx2d_check_constraints(s);
    if(code!=GX2D_OK){o->breaks=old;free(mask);return code;}if(memcmp(old,mask,o->count))++o->topology_epoch;free(old);return GX2D_OK;
}
gx2d_status gx2d_append_points_with_gaps(gx2d_scene *s,gx2d_id id,const gx2d_point *points,const unsigned char *gaps,size_t count){
    object *o;size_t i,start;gx2d_status code;
    if(!s||(!gaps&&count))return GX2D_INVALID;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(count>65536)return GX2D_RANGE;
    for(i=0;i<count;++i)if(gaps[i]>1)return GX2D_INVALID;
    start=o->count;code=gx2d_append_points(s,id,points,count);
    if(code!=GX2D_OK)return code;
    o=obj(s,id);
    for(i=0;i<count;++i)if(gaps[i]&&start+i)o->breaks[start+i-1]=1;
    return GX2D_OK;
}
gx2d_status gx2d_get_breaks(const gx2d_scene *s,gx2d_id id,size_t *out,size_t cap,size_t *count){
    const object *o=cobj(s,id);size_t i,n=0;
    if(!count)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    for(i=0;i+1<o->count;++i)if(o->breaks[i]){if(out&&n<cap)out[n]=i;++n;}
    *count=n;return out&&cap<n?GX2D_RANGE:GX2D_OK;
}
gx2d_status gx2d_extract_range(gx2d_scene *s,gx2d_id id,size_t first,size_t last,gx2d_id *out){
    const object *o=cobj(s,id);gx2d_status st;gx2d_style style;unsigned char *mask;size_t n;
    if(!s||!out)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE||first>=last||last>=o->count)return GX2D_RANGE;
    n=last-first+1;mask=(unsigned char *)malloc(n);if(!mask)return GX2D_NOMEM;
    memcpy(mask,o->breaks+first,n-1);mask[n-1]=0;
    style=o->style;style.selected=0;
    st=gx2d_add_geometry(s,GX2D_CURVE,o->points+first,n,out);
    if(st==GX2D_OK){memcpy(obj(s,*out)->breaks,mask,n);gx2d_set_style(s,*out,&style);}
    free(mask);
    return st;
}
gx2d_status gx2d_keep_range(gx2d_scene *s,gx2d_id id,size_t first,size_t last){
    object *o;unsigned char *mask;size_t n;gx2d_status st=curve_for_edit(s,id,&o);
    if(st!=GX2D_OK)return st;
    if(first>=last||last>=o->count)return GX2D_RANGE;
    n=last-first+1;mask=(unsigned char *)malloc(n);if(!mask)return GX2D_NOMEM;
    memcpy(mask,o->breaks+first,n-1);mask[n-1]=0;
    st=gx2d_replace_points(s,id,o->points+first,n);
    if(st==GX2D_OK)memcpy(obj(s,id)->breaks,mask,n);
    free(mask);return st;
}
gx2d_status gx2d_remove_range(gx2d_scene *s,gx2d_id id,size_t first,size_t last){
    object *o;gx2d_point *v;unsigned char *oldbreak;size_t n,oldCount,i;gx2d_status st=curve_for_edit(s,id,&o);
    if(st!=GX2D_OK)return st;
    if(first>last||last>=o->count||o->count-(last-first+1)<2)return GX2D_RANGE;
    oldCount=o->count;n=oldCount-(last-first+1);v=(gx2d_point *)malloc(n*sizeof(*v));oldbreak=(unsigned char *)malloc(oldCount);
    if(!v||!oldbreak){free(v);free(oldbreak);return GX2D_NOMEM;}
    memcpy(oldbreak,o->breaks,oldCount);
    memcpy(v,o->points,first*sizeof(*v));
    memcpy(v+first,o->points+last+1,(o->count-last-1)*sizeof(*v));
    st=gx2d_replace_points(s,id,v,n);
    if(st==GX2D_OK){o=obj(s,id);memset(o->breaks,0,n);
        for(i=0;i+1<oldCount;++i)if(oldbreak[i]){
            if(i+1<first)o->breaks[i]=1;
            else if(i>last)o->breaks[i-(last-first+1)]=1;}
        if(first>0&&last+1<oldCount)o->breaks[first-1]=1;}
    free(v);free(oldbreak);return st;
}
gx2d_status gx2d_split(gx2d_scene *s,gx2d_id id,size_t index,gx2d_id *left,gx2d_id *right){
    const object *o=cobj(s,id);gx2d_status st;size_t count;
    if(!s||!left||!right)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE||index==0||index>=o->count-1)return GX2D_RANGE;
    count=o->count;st=gx2d_extract_range(s,id,0,index,left);if(st!=GX2D_OK)return st;
    st=gx2d_extract_range(s,id,index,count-1,right);
    if(st!=GX2D_OK)gx2d_delete_object(s,*left);
    return st;
}
gx2d_status gx2d_concatenate_parts(gx2d_scene *s,const gx2d_id *ids,const int *reverse,const int *break_before,size_t n,gx2d_id *out){
    size_t i,j,total=0,k=0;gx2d_point *v;unsigned char *mask;gx2d_status st;
    if(!s||!ids||!out||n<1)return GX2D_INVALID;
    for(i=0;i<n;++i){const object *o=cobj(s,ids[i]);if(!o)return GX2D_NOT_FOUND;
        if(o->kind!=GX2D_CURVE||total>SIZE_MAX/sizeof(*v)-o->count)return GX2D_RANGE;total+=o->count;}
    v=(gx2d_point *)malloc(total*sizeof(*v));mask=(unsigned char *)calloc(total,1);
    if(!v||!mask){free(v);free(mask);return GX2D_NOMEM;}
    for(i=0;i<n;++i){const object *o=cobj(s,ids[i]);
        if(k&&break_before&&break_before[i])mask[k-1]=1;
        for(j=0;j<o->count;++j){size_t src=reverse&&reverse[i]?o->count-j-1:j;
            v[k]=o->points[src];if(j+1<o->count)mask[k]=reverse&&reverse[i]?o->breaks[src-1]:o->breaks[src];++k;}}
    st=gx2d_add_geometry(s,GX2D_CURVE,v,total,out);
    if(st==GX2D_OK)memcpy(obj(s,*out)->breaks,mask,total);
    free(v);free(mask);return st;
}
gx2d_status gx2d_concatenate(gx2d_scene *s,const gx2d_id *ids,const int *reverse,size_t n,gx2d_id *out){
    return gx2d_concatenate_parts(s,ids,reverse,NULL,n,out);
}
static void include_point(gx2d_rect *r,gx2d_point p,int *found){
    if(!*found){*r=(gx2d_rect){p.x,p.y,p.x,p.y};*found=1;return;}
    if(p.x<r->x0)r->x0=p.x;if(p.x>r->x1)r->x1=p.x;
    if(p.y<r->y0)r->y0=p.y;if(p.y>r->y1)r->y1=p.y;
}
gx2d_status gx2d_object_bounds(const gx2d_scene *s,gx2d_id id,gx2d_rect *r){
    const object *o=cobj(s,id);size_t i;int found=0;
    if(!r)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(o->sketch)return gx2d_sketch_bounds(o->sketch,r);
    if(o->kind==GX2D_GROUP){size_t j;for(i=0;i<o->member_count;++i){const object *member=cobj(s,o->members[i]);if(!member)return GX2D_NOT_FOUND;
        if(member->sketch){gx2d_rect bounds;gx2d_status code;if(member->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE)continue;code=gx2d_sketch_bounds(member->sketch,&bounds);if(code!=GX2D_OK)return code;include_point(r,(gx2d_point){bounds.x0,bounds.y0},&found);include_point(r,(gx2d_point){bounds.x1,bounds.y1},&found);continue;}
        for(j=0;j<member->count;++j)include_point(r,member->points[j],&found);}}
    else for(i=0;i<o->count;++i)include_point(r,o->points[i],&found);
    return found?GX2D_OK:GX2D_NOT_FOUND;
}
gx2d_status gx2d_scene_bounds(const gx2d_scene *s,int selected_only,gx2d_rect *r){
    size_t i,j;int found=0;if(!s||!r)return GX2D_INVALID;
    for(i=0;i<s->object_count;++i){const object *o=&s->objects[i];
        const layer *l=o->style.layer?lyr((gx2d_scene *)s,o->style.layer):NULL;
        if(o->kind==GX2D_GROUP||!o->style.visible||(l&&!l->style.visible)||(selected_only&&!can_select(s,o)))continue;
        if(o->sketch){gx2d_rect bounds;gx2d_status code;int chosen=!selected_only;
            if(o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE)continue;
            for(j=0;selected_only&&j<o->count;++j)if(selected_at(s,o,j)){chosen=1;break;}
            if(!chosen)continue;code=gx2d_sketch_bounds(o->sketch,&bounds);if(code!=GX2D_OK)return code;
            include_point(r,(gx2d_point){bounds.x0,bounds.y0},&found);include_point(r,(gx2d_point){bounds.x1,bounds.y1},&found);continue;}
        for(j=0;j<o->count;++j)if(!selected_only||selected_at(s,o,j))include_point(r,o->points[j],&found);}
    return found?GX2D_OK:GX2D_NOT_FOUND;
}
gx2d_status gx2d_selected_points(const gx2d_scene *s,gx2d_id id,gx2d_selected_point *out,size_t cap,size_t *count){
    const object *o=cobj(s,id);size_t j,n=0;
    if(!count)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    for(j=0;j<o->count;++j)if(selected_at(s,o,j)){
        if(out&&n<cap)out[n]=(gx2d_selected_point){id,j,o->points[j]};++n;}
    *count=n;return out&&cap<n?GX2D_RANGE:GX2D_OK;
}
gx2d_status gx2d_nearest_segment(const gx2d_scene *s,gx2d_id id,gx2d_point p,gx2d_segment_hit *hit){
    const object *o=cobj(s,id);size_t j;double best=DBL_MAX;
    if(!hit||!finite2(p))return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch&&o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE){
        gx2d_point a,v,q;gx2d_status code=gx2d_sketch_evaluate(o->sketch,0,&a,&v);long double den,t;
        if(code!=GX2D_OK)return code;den=(long double)v.x*v.x+(long double)v.y*v.y;if(den==0)return GX2D_INVALID;
        t=((long double)(p.x-a.x)*v.x+(long double)(p.y-a.y)*v.y)/den;
        code=gx2d_sketch_evaluate(o->sketch,(double)t,&q,NULL);if(code!=GX2D_OK)return code;
        *hit=(gx2d_segment_hit){0,(double)t,dist(p,q),q};return GX2D_OK;
    }
    for(j=0;j+1<o->count;++j){gx2d_point a=o->points[j],b=o->points[j+1],q;
        if(o->breaks[j])continue;
        double dx=b.x-a.x,dy=b.y-a.y,den=dx*dx+dy*dy,t=den>0?((p.x-a.x)*dx+(p.y-a.y)*dy)/den:0,d;
        if(t<0)t=0;if(t>1)t=1;q=(gx2d_point){a.x+t*dx,a.y+t*dy};d=dist(p,q);
        if(d<best){best=d;*hit=(gx2d_segment_hit){j,t,d,q};}}
    return best<DBL_MAX?GX2D_OK:GX2D_NOT_FOUND;
}
static gx2d_point spline_at(const object *o,size_t segment,double t){
    gx2d_point p0=o->points[segment&&!o->breaks[segment-1]?segment-1:segment],p1=o->points[segment],
        p2=o->points[segment+1],p3=o->points[segment+2<o->count&&!o->breaks[segment+1]?segment+2:segment+1];
    double t2=t*t,t3=t2*t,h00=2*t3-3*t2+1,h10=t3-2*t2+t,h01=-2*t3+3*t2,h11=t3-t2;
    return (gx2d_point){h00*p1.x+h10*(p2.x-p0.x)*0.5+h01*p2.x+h11*(p3.x-p1.x)*0.5,
        h00*p1.y+h10*(p2.y-p0.y)*0.5+h01*p2.y+h11*(p3.y-p1.y)*0.5};
}
gx2d_status gx2d_nearest_spline(const gx2d_scene *s,gx2d_id id,gx2d_point p,size_t subdivisions,gx2d_segment_hit *hit){
    const object *o=cobj(s,id);size_t segment,k;double best=DBL_MAX;
    if(!hit||!finite2(p)||subdivisions<1)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    for(segment=0;segment+1<o->count;++segment){
        if(o->breaks[segment])continue;
        gx2d_point a=spline_at(o,segment,0);
        for(k=0;k<subdivisions;++k){gx2d_point b=spline_at(o,segment,(double)(k+1)/subdivisions),q;
            double dx=b.x-a.x,dy=b.y-a.y,den=dx*dx+dy*dy,t=den>0?((p.x-a.x)*dx+(p.y-a.y)*dy)/den:0,d;
            if(t<0)t=0;if(t>1)t=1;q=(gx2d_point){a.x+t*dx,a.y+t*dy};d=dist(p,q);
            if(d<best){best=d;*hit=(gx2d_segment_hit){segment,((double)k+t)/subdivisions,d,q};}
            a=b;
        }
    }
    return best<DBL_MAX?GX2D_OK:GX2D_NOT_FOUND;
}
gx2d_status gx2d_path_length(const gx2d_scene *s,gx2d_id id,double *out){
    const object *o=cobj(s,id);size_t i;double length=0;
    if(!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch){gx2d_metrics metrics;gx2d_status code=sketch_metrics(o->sketch,&metrics);if(code==GX2D_OK)*out=metrics.length;return code;}
    for(i=1;i<o->count;++i)if(!o->breaks[i-1])length+=dist(o->points[i-1],o->points[i]);*out=length;
    return isfinite(length)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_path_point(const gx2d_scene *s,gx2d_id id,double path,gx2d_segment_hit *hit){
    const object *o=cobj(s,id);size_t i;double total=0;
    if(!hit||!isfinite(path)||path<0)return GX2D_INVALID;
    if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch)return sketch_path_point(o,path,hit);
    for(i=1;i<o->count;++i){double len;
        if(o->breaks[i-1])continue;
        len=dist(o->points[i-1],o->points[i]);
        if(path<=total+len||i==o->count-1){double t=len>0?(path-total)/len:0;
            if(t<0)t=0;if(t>1)t=1;
            hit->segment=i-1;hit->t=t;hit->distance=total+t*len;
            hit->point=(gx2d_point){o->points[i-1].x+t*(o->points[i].x-o->points[i-1].x),o->points[i-1].y+t*(o->points[i].y-o->points[i-1].y)};
            return GX2D_OK;}total+=len;}
    return GX2D_NOT_FOUND;
}
gx2d_status gx2d_curve_metrics(const gx2d_scene *s,gx2d_id id,gx2d_metrics *out){
    const object *o=cobj(s,id);gx2d_rect b;size_t i;double length,area=0,span;int closed=1;
    if(!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE)return GX2D_INVALID;
    if(o->sketch)return sketch_metrics(o->sketch,out);
    if(gx2d_path_length(s,id,&length)!=GX2D_OK||gx2d_object_bounds(s,id,&b)!=GX2D_OK)return GX2D_RANGE;
    for(i=1;i<o->count;++i){if(o->breaks[i-1])closed=0;
        area+=o->points[i-1].x*o->points[i].y-o->points[i].x*o->points[i-1].y;}
    if(dist(o->points[0],o->points[o->count-1])>1e-12)closed=0;
    if(closed)area+=o->points[o->count-1].x*o->points[0].y-o->points[0].x*o->points[o->count-1].y;
    span=b.x1-b.x0;*out=(gx2d_metrics){length,span,b.y1-b.y0,closed?area/2:0,span>0?length/span:0,closed};
    return GX2D_OK;
}
gx2d_status gx2d_sample_spline(const gx2d_scene *s,gx2d_id id,size_t per,gx2d_point *out,size_t cap,size_t *count){
    const object *o=cobj(s,id);size_t seg,k,n;
    if(!count||per<1)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(o->kind!=GX2D_CURVE||per>(SIZE_MAX-1)/(o->count-1))return GX2D_RANGE;
    for(seg=0;seg+1<o->count;++seg)if(o->breaks[seg])return GX2D_INVALID;
    n=(o->count-1)*per+1;*count=n;if(!out)return GX2D_OK;if(cap<n)return GX2D_RANGE;
    for(seg=0;seg+1<o->count;++seg){
        for(k=0;k<per;++k)out[seg*per+k]=spline_at(o,seg,(double)k/per);}
    out[n-1]=o->points[o->count-1];return GX2D_OK;
}
static int monotonic_x(const object *o){size_t i;int direction=0;
    for(i=1;i<o->count;++i){double dx=o->points[i].x-o->points[i-1].x;
        if(dx==0)return 0;if(!direction)direction=dx>0?1:-1;
        if((dx>0?1:-1)!=direction)return 0;}return direction;
}
typedef gx2d_status (*residual_consumer)(void *,size_t,const gx2d_residual *);
static gx2d_status compare_kernel(const gx2d_scene *s,gx2d_id reference,gx2d_id derived,
    gx2d_compare_method method,residual_consumer emit,void *context,gx2d_residual_summary *summary){
    const object *a=cobj(s,reference),*b=cobj(s,derived);size_t i,j=0,n=0;
    gx_numeric_residual_accumulator_v1 statistics;gx_numeric_residual_result_v1 facts;
    double total_a=0,total_b=0,progress=0,b_progress=0;
    gx_numeric_residual_init_v1(&statistics);
    if((!summary&&!emit)||method<GX2D_COMPARE_X||method>GX2D_COMPARE_PATH)return GX2D_INVALID;
    if(!a||!b)return GX2D_NOT_FOUND;if(a->kind!=GX2D_CURVE||b->kind!=GX2D_CURVE)return GX2D_INVALID;
    for(i=0;i+1<a->count;++i)if(a->breaks[i])return GX2D_INVALID;
    for(i=0;i+1<b->count;++i)if(b->breaks[i])return GX2D_INVALID;
    if(method==GX2D_COMPARE_X&&(!monotonic_x(a)||!monotonic_x(b)))return GX2D_INVALID;
    if(method==GX2D_COMPARE_PATH){if(gx2d_path_length(s,reference,&total_a)!=GX2D_OK||gx2d_path_length(s,derived,&total_b)!=GX2D_OK)return GX2D_RANGE;
        if(total_a<=0||total_b<=0)return GX2D_INVALID;}
    for(i=0;i<a->count;++i){gx2d_point ref=a->points[i],fit={0,0};double position,residual,absolute;
        if(method==GX2D_COMPARE_X){double lo=fmin(b->points[0].x,b->points[b->count-1].x),hi=fmax(b->points[0].x,b->points[b->count-1].x);
            if(ref.x<lo||ref.x>hi)continue;
            {size_t left=0,right=b->count-1;int ascending=b->points[right].x>b->points[0].x;
             while(right-left>1){size_t middle=left+(right-left)/2;if(ascending?ref.x<b->points[middle].x:ref.x>b->points[middle].x)right=middle;else left=middle;}j=left;}
            {double t=(ref.x-b->points[j].x)/(b->points[j+1].x-b->points[j].x);
                fit=(gx2d_point){ref.x,b->points[j].y+t*(b->points[j+1].y-b->points[j].y)};}
            residual=ref.y-fit.y;absolute=fabs(residual);position=ref.x;
        }else{gx2d_point tangent;double len,target,t;
            if(i)progress+=dist(a->points[i-1],ref);
            target=total_b*progress/total_a;
            while(j+2<b->count&&target>b_progress+dist(b->points[j],b->points[j+1])){b_progress+=dist(b->points[j],b->points[j+1]);++j;}
            len=dist(b->points[j],b->points[j+1]);t=len>0?(target-b_progress)/len:0;
            if(t<0)t=0;if(t>1)t=1;
            fit=(gx2d_point){b->points[j].x+t*(b->points[j+1].x-b->points[j].x),b->points[j].y+t*(b->points[j+1].y-b->points[j].y)};
            tangent=(gx2d_point){b->points[j+1].x-b->points[j].x,b->points[j+1].y-b->points[j].y};len=hypot(tangent.x,tangent.y);
            absolute=dist(ref,fit);
            residual=len>0&&((ref.y-fit.y)*tangent.x-(ref.x-fit.x)*tangent.y)<0?-absolute:absolute;
            position=progress;
        }
        if(!isfinite(position)||!isfinite(residual)||!isfinite(absolute))return GX2D_RANGE;
        if(emit){gx2d_residual row={position,residual,absolute,ref,fit};gx2d_status code=emit(context,n,&row);if(code!=GX2D_OK)return code;}
        if(summary&&gx_numeric_residual_push_v1(&statistics,absolute)!=GX_NUMERIC_OK_V1)return GX2D_RANGE;
        ++n;
    }
    if(!n)return GX2D_NOT_FOUND;
    if(summary){
        if(gx_numeric_residual_finish_v1(&statistics,&facts)!=GX_NUMERIC_OK_V1)return GX2D_RANGE;
        *summary=(gx2d_residual_summary){(size_t)facts.count,(size_t)facts.max_index,facts.max_absolute,facts.mean_absolute,facts.rmse};
    }
    return GX2D_OK;
}
typedef struct {gx2d_residual *rows;size_t capacity;} residual_buffer;
static gx2d_status residual_write(void *context,size_t index,const gx2d_residual *row){residual_buffer *buffer=context;if(index>=buffer->capacity)return GX2D_RANGE;buffer->rows[index]=*row;return GX2D_OK;}
gx2d_status gx2d_compare_curves(const gx2d_scene *s,gx2d_id reference,gx2d_id derived,
    gx2d_compare_method method,gx2d_residual *out,size_t cap,gx2d_residual_summary *summary){
    residual_buffer buffer={out,cap};if(!summary)return GX2D_INVALID;return compare_kernel(s,reference,derived,method,out?residual_write:NULL,&buffer,summary);
}
static gx2d_status residual_sample(void *context,size_t index,const gx2d_residual *row){gx2d_point point={row->position,row->signed_residual};return gx2d_display_push(context,index,&point,1);}
typedef struct {gx2d_residual *rows;uint64_t *indices;size_t count,next;} residual_sample_buffer;
static gx2d_status residual_collect(void *context,size_t index,const gx2d_residual *row){residual_sample_buffer *buffer=context;if(buffer->next<buffer->count&&buffer->indices[buffer->next]==index)buffer->rows[buffer->next++]=*row;return GX2D_OK;}
gx2d_status gx2d_compare_curves_display(const gx2d_scene *s,gx2d_id reference,gx2d_id derived,
    gx2d_compare_method method,size_t budget,gx2d_residual *out,uint64_t *indices,size_t cap,size_t *returned,gx2d_residual_summary *summary){
    gx2d_display_accumulator *accumulator=NULL;gx2d_point *sampled=NULL;gx2d_status code;gx2d_rect bounds;
    size_t count,finite;residual_sample_buffer buffer;
    if(!out||!indices||!returned||!summary||budget<6||budget>65536||cap<budget)return GX2D_INVALID;
    code=compare_kernel(s,reference,derived,method,NULL,NULL,summary);if(code!=GX2D_OK)return code;
    accumulator=gx2d_display_begin(summary->count,budget,0);sampled=calloc(budget,sizeof(*sampled));
    if(!accumulator||!sampled){code=GX2D_NOMEM;goto finished;}
    code=compare_kernel(s,reference,derived,method,residual_sample,accumulator,NULL);if(code!=GX2D_OK)goto finished;
    code=gx2d_display_result(accumulator,sampled,indices,budget,&count,&finite,&bounds);if(code!=GX2D_OK)goto finished;
    buffer=(residual_sample_buffer){out,indices,count,0};
    code=compare_kernel(s,reference,derived,method,residual_collect,&buffer,NULL);
    if(code==GX2D_OK){if(buffer.next!=count)code=GX2D_RANGE;else *returned=count;}
finished:
    free(sampled);gx2d_display_destroy(accumulator);return code;
}
static int valid_view(const gx2d_view *v){return v&&isfinite(v->width)&&isfinite(v->height)&&v->width>v->left+v->right+1&&v->height>v->top+v->bottom+1&&
    v->left>=0&&v->top>=0&&v->right>=0&&v->bottom>=0&&valid_rect(v->world)&&v->world.x0<v->world.x1&&v->world.y0<v->world.y1;}
static gx2d_status aspect_view(gx2d_aspect_mode mode,const gx2d_view *requested,gx2d_view *effective){
    double dx,dy,pw,ph,scale,cx,cy;
    if(!valid_view(requested))return GX2D_INVALID;
    *effective=*requested;
    dx=requested->world.x1-requested->world.x0;dy=requested->world.y1-requested->world.y0;
    if(!isfinite(dx)||!isfinite(dy))return GX2D_RANGE;
    if(mode==GX2D_ASPECT_AUTO)return GX2D_OK;
    if(mode!=GX2D_ASPECT_XY_EQUAL)return GX2D_INVALID;
    pw=requested->width-requested->left-requested->right;
    ph=requested->height-requested->top-requested->bottom;
    scale=fmax(dx/pw,dy/ph);
    cx=requested->world.x0+dx/2;cy=requested->world.y0+dy/2;
    effective->world=(gx2d_rect){cx-pw*scale/2,cy-ph*scale/2,cx+pw*scale/2,cy+ph*scale/2};
    return valid_view(effective)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_view_set(gx2d_scene *s,const gx2d_view *v){gx2d_view effective;gx2d_status st;
    if(!s)return GX2D_INVALID;st=aspect_view(s->aspect_mode,v,&effective);if(st!=GX2D_OK)return st;
    s->requested_view=*v;s->view=effective;return GX2D_OK;}
gx2d_status gx2d_view_get(const gx2d_scene *s,gx2d_view *v){if(!s||!v)return GX2D_INVALID;*v=s->view;return GX2D_OK;}
gx2d_status gx2d_view_requested(const gx2d_scene *s,gx2d_view *v){if(!s||!v)return GX2D_INVALID;*v=s->requested_view;return GX2D_OK;}
gx2d_status gx2d_view_aspect_get(const gx2d_scene *s,gx2d_aspect_mode *mode){if(!s||!mode)return GX2D_INVALID;*mode=s->aspect_mode;return GX2D_OK;}
gx2d_status gx2d_view_aspect_set(gx2d_scene *s,gx2d_aspect_mode mode){gx2d_view effective;gx2d_status st;
    if(!s)return GX2D_INVALID;st=aspect_view(mode,&s->requested_view,&effective);if(st!=GX2D_OK)return st;
    s->view=effective;s->aspect_mode=mode;return GX2D_OK;}
gx2d_status gx2d_view_fit_bounds(gx2d_scene *s,gx2d_rect b){double dx,dy;
    gx2d_view v;
    if(!s||!valid_rect(b))return GX2D_INVALID;
    dx=b.x1-b.x0;dy=b.y1-b.y0;if(dx<=0)dx=fmax(fabs(b.x0)*0.1,1);if(dy<=0)dy=fmax(fabs(b.y0)*0.1,1);
    v=s->view;v.world=(gx2d_rect){b.x0-0.06*dx,b.y0-0.06*dy,b.x1+0.06*dx,b.y1+0.06*dy};
    if(b.x0==b.x1){v.world.x0=b.x0-0.5*dx;v.world.x1=b.x0+0.5*dx;}
    if(b.y0==b.y1){v.world.y0=b.y0-0.5*dy;v.world.y1=b.y0+0.5*dy;}
    return gx2d_view_set(s,&v);
}
gx2d_status gx2d_view_fit(gx2d_scene *s,gx2d_id id){gx2d_rect b;gx2d_status st;
    if(!s)return GX2D_INVALID;st=id?gx2d_object_bounds(s,id,&b):gx2d_scene_bounds(s,0,&b);
    return st==GX2D_OK?gx2d_view_fit_bounds(s,b):st;
}
gx2d_status gx2d_view_fit_selected(gx2d_scene *s){gx2d_rect b;gx2d_status st;
    if(!s)return GX2D_INVALID;st=gx2d_scene_bounds(s,1,&b);
    return st==GX2D_OK?gx2d_view_fit_bounds(s,b):st;
}
gx2d_status gx2d_world_to_device(const gx2d_scene *s,gx2d_point p,gx2d_point *out){const gx2d_view *v;
    if(!s||!out||!finite2(p))return GX2D_INVALID;v=&s->view;
    out->x=v->left+(p.x-v->world.x0)*(v->width-v->left-v->right)/(v->world.x1-v->world.x0);
    out->y=v->top+(v->world.y1-p.y)*(v->height-v->top-v->bottom)/(v->world.y1-v->world.y0);
    return finite2(*out)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_device_to_world(const gx2d_scene *s,gx2d_point p,gx2d_point *out){const gx2d_view *v;
    if(!s||!out||!finite2(p))return GX2D_INVALID;v=&s->view;
    out->x=v->world.x0+(p.x-v->left)*(v->world.x1-v->world.x0)/(v->width-v->left-v->right);
    out->y=v->world.y1-(p.y-v->top)*(v->world.y1-v->world.y0)/(v->height-v->top-v->bottom);
    return finite2(*out)?GX2D_OK:GX2D_RANGE;
}
gx2d_status gx2d_view_zoom(gx2d_scene *s,double factor,gx2d_point anchor){gx2d_point p;gx2d_rect r,next;
    if(!s||!isfinite(factor)||factor<=0)return GX2D_INVALID;
    if(gx2d_device_to_world(s,anchor,&p)!=GX2D_OK)return GX2D_INVALID;r=s->view.world;
    next=(gx2d_rect){p.x+(r.x0-p.x)*factor,p.y+(r.y0-p.y)*factor,p.x+(r.x1-p.x)*factor,p.y+(r.y1-p.y)*factor};
    if(!valid_rect(next)||next.x0>=next.x1||next.y0>=next.y1)return GX2D_RANGE;
    {gx2d_view v=s->view;v.world=next;return gx2d_view_set(s,&v);}
}
gx2d_status gx2d_view_pan(gx2d_scene *s,double dx,double dy){double wx,wy;gx2d_rect r,next;
    if(!s||!isfinite(dx)||!isfinite(dy))return GX2D_INVALID;r=s->view.world;
    wx=dx*(r.x1-r.x0)/(s->view.width-s->view.left-s->view.right);
    wy=dy*(r.y1-r.y0)/(s->view.height-s->view.top-s->view.bottom);
    next=(gx2d_rect){r.x0-wx,r.y0+wy,r.x1-wx,r.y1+wy};
    if(!valid_rect(next))return GX2D_RANGE;{gx2d_view v=s->view;v.world=next;return gx2d_view_set(s,&v);}
}
gx2d_status gx2d_pixel_tolerance(const gx2d_scene *s,double pixels,double *wx,double *wy){
    if(!s||!wx||!wy||!isfinite(pixels)||pixels<0)return GX2D_INVALID;
    *wx=pixels*(s->view.world.x1-s->view.world.x0)/(s->view.width-s->view.left-s->view.right);
    *wy=pixels*(s->view.world.y1-s->view.world.y0)/(s->view.height-s->view.top-s->view.bottom);
    return GX2D_OK;
}
gx2d_status gx2d_render_points(const gx2d_scene *s,gx2d_id id,gx2d_point *out,size_t cap,size_t *count){
    const object *o=cobj(s,id);size_t i;gx2d_status st;
    if(!count)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(o->sketch&&o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE){
        gx2d_point clipped[2];st=sketch_construction_clip(s,o->sketch,clipped);*count=st==GX2D_NOT_FOUND?0:2;
        if(st==GX2D_NOT_FOUND)return GX2D_OK;if(st!=GX2D_OK)return st;if(!out)return GX2D_OK;if(cap<2)return GX2D_RANGE;
        for(i=0;i<2;++i){st=gx2d_world_to_device(s,clipped[i],&out[i]);if(st!=GX2D_OK)return st;}return GX2D_OK;
    }
    *count=o->count;if(!out)return GX2D_OK;if(cap<o->count)return GX2D_RANGE;
    for(i=0;i<o->count;++i){st=gx2d_world_to_device(s,o->points[i],&out[i]);if(st!=GX2D_OK)return st;}
    return GX2D_OK;
}

/* Presentation-only direction overlays. The sampled spline path is generated
 * here by the same native spline evaluator; hosts never scan Tcl point lists. */
static int valid_color(gx2d_color c) {
    return isfinite(c.red)&&isfinite(c.green)&&isfinite(c.blue)&&isfinite(c.alpha)&&
        c.red>=0&&c.red<=1&&c.green>=0&&c.green<=1&&c.blue>=0&&c.blue<=1&&c.alpha>=0&&c.alpha<=1;
}
static int valid_direction_marker(const gx2d_direction_marker *m) {
    return m&&m->present>=0&&m->present<=1&&m->visible>=0&&m->visible<=1&&
        m->forward>=0&&m->forward<=1&&m->interpolation>=0&&m->interpolation<=1&&
        isfinite(m->fraction)&&m->fraction>=0&&m->fraction<=1&&
        isfinite(m->offset_px)&&fabs(m->offset_px)<=4096&&
        isfinite(m->length_px)&&m->length_px>=4&&m->length_px<=4096&&
        isfinite(m->line_width)&&m->line_width>0&&m->line_width<=64&&
        isfinite(m->head_scale)&&m->head_scale>0&&m->head_scale<=4&&valid_color(m->color);
}
gx2d_status gx2d_direction_marker_get(const gx2d_scene *s,gx2d_id id,gx2d_direction_marker *out) {
    const object *o=cobj(s,id);if(!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;*out=o->direction_marker;return GX2D_OK;
}
gx2d_status gx2d_direction_marker_set(gx2d_scene *s,gx2d_id id,const gx2d_direction_marker *value) {
    object *o;if(!s||!valid_direction_marker(value))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;o=obj(s,id);if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP||(o->kind!=GX2D_CURVE&&value->present))return GX2D_INVALID;o->direction_marker=*value;return GX2D_OK;
}
gx2d_status gx2d_direction_marker_attach(gx2d_scene *s,gx2d_id source,gx2d_id target) {
    object *a,*b;if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    a=obj(s,source);b=obj(s,target);if(!a||!b)return GX2D_NOT_FOUND;
    if(a==b||a->kind!=GX2D_CURVE||b->kind!=GX2D_CURVE||!a->direction_marker.present)return GX2D_INVALID;
    b->direction_marker=a->direction_marker;a->direction_marker.present=0;return GX2D_OK;
}
static gx2d_status marker_path(const gx2d_scene *s,const object *o,object *path,gx2d_point **owned) {
    size_t count;gx2d_status code;*owned=NULL;*path=*o;
    if(!o->direction_marker.interpolation)return GX2D_OK;
    code=gx2d_sample_spline(s,o->id,64,NULL,0,&count);if(code!=GX2D_OK)return code;
    if(count>1048576)return GX2D_RANGE;
    *owned=(gx2d_point *)malloc(count*sizeof(**owned));if(!*owned)return GX2D_NOMEM;
    code=gx2d_sample_spline(s,o->id,64,*owned,count,&count);
    if(code!=GX2D_OK){free(*owned);*owned=NULL;return code;}
    path->points=*owned;path->count=count;path->breaks=NULL;return GX2D_OK;
}
static double marker_path_length(const object *o) {
    size_t i;double total=0;
    for(i=0;i+1<o->count;++i)if(!o->breaks||!o->breaks[i])total+=dist(o->points[i],o->points[i+1]);
    return total;
}
static gx2d_status marker_anchor(const object *o,double fraction,gx2d_point *anchor,gx2d_point *tangent) {
    size_t i;double total=marker_path_length(o),position=0,requested=fraction*total;
    if(!isfinite(total)||total<=DBL_EPSILON)return GX2D_CONSTRAINT;
    for(i=0;i+1<o->count;++i){double length,t;
        if(o->breaks&&o->breaks[i])continue;
        length=dist(o->points[i],o->points[i+1]);if(length<=DBL_EPSILON)continue;
        if(requested<=position+length||fabs(total-position-length)<=total*1e-13){
            t=fmin(1,fmax(0,(requested-position)/length));
            *anchor=(gx2d_point){o->points[i].x+t*(o->points[i+1].x-o->points[i].x),o->points[i].y+t*(o->points[i+1].y-o->points[i].y)};
            *tangent=(gx2d_point){(o->points[i+1].x-o->points[i].x)/length,(o->points[i+1].y-o->points[i].y)/length};return GX2D_OK;
        }
        position+=length;
    }
    return GX2D_NOT_FOUND;
}
gx2d_status gx2d_direction_marker_render(const gx2d_scene *s,gx2d_id id,gx2d_direction_primitives *out) {
    const object *o=cobj(s,id);object path;gx2d_point *owned,anchor,tangent,device,next,center;
    gx2d_status code;double norm,dx,dy,nx,ny,half,head,wings;
    if(!out)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP)return GX2D_INVALID;if(o->kind!=GX2D_CURVE)return GX2D_NOT_FOUND;
    if(!o->direction_marker.present||!o->direction_marker.visible||!o->style.visible)return GX2D_NOT_FOUND;
    if(o->style.layer){const layer *l=lyr((gx2d_scene *)s,o->style.layer);if(l&&!l->style.visible)return GX2D_NOT_FOUND;}
    code=marker_path(s,o,&path,&owned);if(code!=GX2D_OK)return code;
    code=marker_anchor(&path,o->direction_marker.fraction,&anchor,&tangent);free(owned);if(code!=GX2D_OK)return code;
    code=gx2d_world_to_device(s,anchor,&device);if(code!=GX2D_OK)return code;
    code=gx2d_world_to_device(s,(gx2d_point){anchor.x+tangent.x,anchor.y+tangent.y},&next);if(code!=GX2D_OK)return code;
    norm=dist(device,next);if(norm<=DBL_EPSILON)return GX2D_CONSTRAINT;
    dx=(next.x-device.x)/norm;dy=(next.y-device.y)/norm;nx=-dy;ny=dx;
    /* Offset side follows the ordered path, independently of intended flip. */
    center=(gx2d_point){device.x+nx*o->direction_marker.offset_px,device.y+ny*o->direction_marker.offset_px};
    if(!o->direction_marker.forward){dx=-dx;dy=-dy;}
    half=o->direction_marker.length_px/2;head=fmin(o->direction_marker.length_px*.3,12)*o->direction_marker.head_scale;wings=head*.48;
    out->anchor=device;out->tail=(gx2d_point){center.x-dx*half,center.y-dy*half};out->tip=(gx2d_point){center.x+dx*half,center.y+dy*half};
    out->head_left=(gx2d_point){out->tip.x-dx*head+nx*wings,out->tip.y-dy*head+ny*wings};
    out->head_right=(gx2d_point){out->tip.x-dx*head-nx*wings,out->tip.y-dy*head-ny*wings};out->fraction=o->direction_marker.fraction;
    out->bounds=(gx2d_rect){fmin(out->tail.x,fmin(out->tip.x,fmin(out->head_left.x,out->head_right.x))),fmin(out->tail.y,fmin(out->tip.y,fmin(out->head_left.y,out->head_right.y))),fmax(out->tail.x,fmax(out->tip.x,fmax(out->head_left.x,out->head_right.x))),fmax(out->tail.y,fmax(out->tip.y,fmax(out->head_left.y,out->head_right.y)))};
    return GX2D_OK;
}
gx2d_status gx2d_direction_marker_hit(const gx2d_scene *s,gx2d_id id,gx2d_point device,double tolerance,int *hit) {
    gx2d_direction_primitives p;gx2d_status code;double nearest;
    if(!hit||!finite2(device)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;*hit=0;
    code=gx2d_direction_marker_render(s,id,&p);if(code==GX2D_NOT_FOUND)return GX2D_OK;if(code!=GX2D_OK)return code;
    nearest=dist(device,nearest_segment(device,p.tail,p.tip));
    nearest=fmin(nearest,dist(device,nearest_segment(device,p.tip,p.head_left)));
    nearest=fmin(nearest,dist(device,nearest_segment(device,p.tip,p.head_right)));
    *hit=nearest<=tolerance;return GX2D_OK;
}
gx2d_status gx2d_direction_marker_place(gx2d_scene *s,gx2d_id id,gx2d_point device,double *fraction) {
    object *o,path;gx2d_point *owned,world;gx2d_status code;size_t i;double total,position=0,best=DBL_MAX,result=0;
    if(!s||!fraction||!finite2(device))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    o=obj(s,id);if(!o)return GX2D_NOT_FOUND;if(o->kind!=GX2D_CURVE||!o->direction_marker.present)return GX2D_INVALID;
    code=gx2d_device_to_world(s,device,&world);if(code!=GX2D_OK)return code;
    code=marker_path(s,o,&path,&owned);if(code!=GX2D_OK)return code;
    total=marker_path_length(&path);if(!isfinite(total)||total<=DBL_EPSILON){free(owned);return GX2D_CONSTRAINT;}
    for(i=0;i+1<path.count;++i){gx2d_point q,qd;double length,distance;
        if(path.breaks&&path.breaks[i])continue;
        length=dist(path.points[i],path.points[i+1]);if(length<=DBL_EPSILON)continue;
        /* Project in device metric, preserving correct picking under auto aspect. */
        gx2d_point a,b;gx2d_world_to_device(s,path.points[i],&a);gx2d_world_to_device(s,path.points[i+1],&b);
        qd=nearest_segment(device,a,b);distance=dist(device,qd);
        gx2d_device_to_world(s,qd,&q);
        if(distance<best){best=distance;result=(position+dist(path.points[i],q))/total;}
        position+=length;
    }
    free(owned);o->direction_marker.fraction=fmin(1,fmax(0,result));*fraction=o->direction_marker.fraction;return GX2D_OK;
}
gx2d_status gx2d_direction_marker_order(const gx2d_scene *s,gx2d_id id,size_t total,size_t start,size_t count,size_t *indices) {
    const object *o=cobj(s,id);size_t i;
    if(!o)return GX2D_NOT_FOUND;if(o->kind==GX2D_GROUP||!indices)return GX2D_INVALID;
    if(!total||start>total||count>total-start)return GX2D_RANGE;
    for(i=0;i<count;++i)indices[i]=o->direction_marker.forward?start+i:total-start-i-1;
    return GX2D_OK;
}
gx2d_status gx2d_background_get(const gx2d_scene *s,gx2d_color *out) {
    if(!s||!out)return GX2D_INVALID;*out=s->background;return GX2D_OK;
}
gx2d_status gx2d_background_set(gx2d_scene *s,gx2d_color value) {
    if(!s||!valid_color(value))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;s->background=value;return GX2D_OK;
}
gx2d_status gx2d_grid_get(const gx2d_scene *s,gx2d_grid *out) {
    if(!s||!out)return GX2D_INVALID;*out=s->grid;return GX2D_OK;
}
gx2d_status gx2d_grid_set(gx2d_scene *s,const gx2d_grid *g) {
    if(!s||!g||!finite2(g->origin)||!isfinite(g->spacing_x)||!isfinite(g->spacing_y)||
        g->spacing_x<=0||g->spacing_y<=0||!isfinite(g->angle)||!g->major_interval||g->major_interval>1000000||
        !valid_color(g->major_color)||!valid_color(g->minor_color)||!valid_color(g->axes_color)||
        !isfinite(g->major_width)||g->major_width<=0||g->major_width>64||
        !isfinite(g->minor_width)||g->minor_width<=0||g->minor_width>64||
        !isfinite(g->axes_width)||g->axes_width<=0||g->axes_width>64||
        g->major_style<0||g->major_style>2||g->minor_style<0||g->minor_style>2||g->axes_style<0||g->axes_style>2)
        return GX2D_INVALID;
    if(g->enabled<0||g->enabled>1||g->visible<0||g->visible>1||g->snap_enabled<0||g->snap_enabled>1||g->major_visible<0||g->major_visible>1||g->minor_visible<0||g->minor_visible>1||g->axes_visible<0||g->axes_visible>1)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;s->grid=*g;return GX2D_OK;
}
gx2d_status gx2d_presentation_set(gx2d_scene *s,const gx2d_grid *grid,gx2d_color background,gx2d_aspect_mode aspect) {
    gx2d_scene trial;gx2d_status code;
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    trial=*s;
    code=gx2d_grid_set(&trial,grid);if(code!=GX2D_OK)return code;
    code=gx2d_background_set(&trial,background);if(code!=GX2D_OK)return code;
    code=gx2d_view_aspect_set(&trial,aspect);if(code!=GX2D_OK)return code;
    s->grid=trial.grid;s->background=trial.background;s->aspect_mode=trial.aspect_mode;s->view=trial.view;
    return GX2D_OK;
}
static gx2d_point grid_local(const gx2d_grid *g,gx2d_point p) {
    double x=p.x-g->origin.x,y=p.y-g->origin.y,co=cos(g->angle),si=sin(g->angle);
    return (gx2d_point){co*x+si*y,-si*x+co*y};
}
static gx2d_point grid_world(const gx2d_grid *g,gx2d_point p) {
    double co=cos(g->angle),si=sin(g->angle);
    return (gx2d_point){g->origin.x+co*p.x-si*p.y,g->origin.y+si*p.x+co*p.y};
}
gx2d_status gx2d_grid_snap(const gx2d_scene *s,gx2d_point p,unsigned axes,gx2d_point *out) {
    gx2d_point local,value;double x,y;
    if(!s||!out||!finite2(p)||axes<1||axes>3)return GX2D_INVALID;
    if(s->coordinate_mode==GX2D_POLAR)return gx2d_polar_snap(s,p,axes,out);
    local=grid_local(&s->grid,p);
    if(axes&1){x=local.x/s->grid.spacing_x;if(!isfinite(x))return GX2D_RANGE;local.x=round(x)*s->grid.spacing_x;}
    if(axes&2){y=local.y/s->grid.spacing_y;if(!isfinite(y))return GX2D_RANGE;local.y=round(y)*s->grid.spacing_y;}
    value=grid_world(&s->grid,local);if(!finite2(value))return GX2D_RANGE;*out=value;return GX2D_OK;
}
gx2d_status gx2d_grid_translation(const gx2d_scene *s,gx2d_point pivot,gx2d_point proposed,unsigned axes,gx2d_point *out) {
    gx2d_point snapped,value;gx2d_status code;
    if(!out||!finite2(pivot)||!finite2(proposed))return GX2D_INVALID;
    code=gx2d_grid_snap(s,(gx2d_point){pivot.x+proposed.x,pivot.y+proposed.y},axes,&snapped);
    if(code!=GX2D_OK)return code;value=(gx2d_point){snapped.x-pivot.x,snapped.y-pivot.y};
    if(!finite2(value))return GX2D_RANGE;*out=value;return GX2D_OK;
}
static int clip_grid_segment(gx2d_rect r,gx2d_point *a,gx2d_point *b) {
    double dx=b->x-a->x,dy=b->y-a->y,p[4]={-dx,dx,-dy,dy},q[4]={a->x-r.x0,r.x1-a->x,a->y-r.y0,r.y1-a->y};
    double lo=0,hi=1;size_t i;
    for(i=0;i<4;++i){double t;if(p[i]==0){if(q[i]<0)return 0;continue;}t=q[i]/p[i];
        if(p[i]<0){if(t>hi)return 0;if(t>lo)lo=t;}else{if(t<lo)return 0;if(t<hi)hi=t;}}
    *b=(gx2d_point){a->x+hi*dx,a->y+hi*dy};*a=(gx2d_point){a->x+lo*dx,a->y+lo*dy};return finite2(*a)&&finite2(*b);
}
gx2d_status gx2d_grid_render(const gx2d_scene *s,gx2d_grid_segment *out,size_t capacity,size_t *count) {
    const gx2d_grid *g;gx2d_rect local;gx2d_point corners[4];size_t i,axis,n=0,limit;int found=0;
    if(!s||!count||capacity>65536)return GX2D_INVALID;*count=0;g=&s->grid;
    if(s->coordinate_mode==GX2D_POLAR)return gx2d_polar_grid_render(s,out,capacity,count);
    if(!g->enabled||!g->visible)return GX2D_OK;
    limit=2048;
    corners[0]=(gx2d_point){s->view.world.x0,s->view.world.y0};corners[1]=(gx2d_point){s->view.world.x1,s->view.world.y0};
    corners[2]=(gx2d_point){s->view.world.x1,s->view.world.y1};corners[3]=(gx2d_point){s->view.world.x0,s->view.world.y1};
    for(i=0;i<4;++i){gx2d_point p=grid_local(g,corners[i]);if(!finite2(p))return GX2D_RANGE;include_point(&local,p,&found);}
    for(axis=0;axis<2;++axis){
        double spacing=axis?g->spacing_y:g->spacing_x,low=axis?local.y0:local.x0,high=axis?local.y1:local.x1;
        double first=floor(low/spacing),last=ceil(high/spacing),stride=1,index;
        double pixels,required,co=cos(g->angle),si=sin(g->angle);size_t attempts=0;
        double world_per_pixel_x=(s->view.world.x1-s->view.world.x0)/(s->view.width-s->view.left-s->view.right);
        double world_per_pixel_y=(s->view.world.y1-s->view.world.y0)/(s->view.height-s->view.top-s->view.bottom);
        if(!isfinite(first)||!isfinite(last)||!isfinite(last-first))return GX2D_RANGE;
        /* Perpendicular distance between parallel lines under the actual
         * anisotropic viewport transform. Length of the transformed normal
         * vector is wrong for a rotated grid with unequal axis scales. This
         * derivative form also avoids cancellation at large grid origins. */
        pixels=spacing/(axis?hypot(co*world_per_pixel_y,si*world_per_pixel_x):
                                  hypot(si*world_per_pixel_y,co*world_per_pixel_x));
        required=fmax(1,fmax(8/pixels,(last-first)/(limit/2-1)));
        if(required>1){stride=(double)g->major_interval*ceil(required/g->major_interval);
            first=ceil(first/stride)*stride;}
        if(!isfinite(stride)||stride<=0)return GX2D_RANGE;
        for(index=first;index<=last&&attempts++<limit/2;){
            gx2d_point a,b;int classification=index==0?2:(fmod(fabs(index),(double)g->major_interval)<.5?1:0);
            int visible=classification==2?g->axes_visible:classification==1?g->major_visible:g->minor_visible;
            if(visible){
                a=grid_world(g,axis?(gx2d_point){local.x0,index*spacing}:(gx2d_point){index*spacing,local.y0});
                b=grid_world(g,axis?(gx2d_point){local.x1,index*spacing}:(gx2d_point){index*spacing,local.y1});
                if(clip_grid_segment(s->view.world,&a,&b)){
                    gx2d_grid_segment value;gx2d_status ca,cb;
                    ca=gx2d_world_to_device(s,a,&value.a);cb=gx2d_world_to_device(s,b,&value.b);if(ca!=GX2D_OK||cb!=GX2D_OK)return GX2D_RANGE;
                    value.classification=classification;if(out&&n<capacity)out[n]=value;++n;
                }
            }
            if(index+stride==index)break;index+=stride;
        }
    }
    *count=n;return out&&capacity<n?GX2D_RANGE:GX2D_OK;
}

static int valid_polar(const gx2d_polar_frame *p) {
    return p&&finite2(p->origin)&&isfinite(p->theta_zero)&&
        (p->clockwise==0||p->clockwise==1)&&(p->degrees==0||p->degrees==1)&&
        isfinite(p->radius_min)&&isfinite(p->radius_max)&&p->radius_min>=0&&p->radius_max>p->radius_min&&
        isfinite(p->angle_min)&&isfinite(p->angle_span)&&p->angle_span>0&&p->angle_span<=2*acos(-1.)&&
        isfinite(p->radial_spacing)&&p->radial_spacing>0&&isfinite(p->angular_spacing)&&
        p->angular_spacing>0&&p->angular_spacing<=2*acos(-1.)&&
        p->radial_major_interval>0&&p->radial_major_interval<=1000000&&
        p->angular_major_interval>0&&p->angular_major_interval<=1000000;
}
gx2d_status gx2d_polar_frame_get(const gx2d_scene *s,gx2d_polar_frame *out) {
    if(!s||!out)return GX2D_INVALID;*out=s->polar;return GX2D_OK;
}
gx2d_status gx2d_polar_frame_set(gx2d_scene *s,const gx2d_polar_frame *p) {
    if(!s||!valid_polar(p))return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    s->polar=*p;return GX2D_OK;
}
gx2d_status gx2d_coordinate_mode_get(const gx2d_scene *s,gx2d_coordinate_mode *out) {
    if(!s||!out)return GX2D_INVALID;*out=s->coordinate_mode;return GX2D_OK;
}
gx2d_status gx2d_coordinate_mode_set(gx2d_scene *s,gx2d_coordinate_mode mode) {
    if(!s||(mode!=GX2D_CARTESIAN&&mode!=GX2D_POLAR))return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;s->coordinate_mode=mode;return GX2D_OK;
}
gx2d_status gx2d_presentation_frame_set(gx2d_scene *s,const gx2d_grid *grid,gx2d_color color,gx2d_aspect_mode aspect,const gx2d_polar_frame *polar,gx2d_coordinate_mode mode) {
    gx2d_scene trial;gx2d_status code;
    if(!s)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;trial=*s;
    code=gx2d_presentation_set(&trial,grid,color,aspect);if(code!=GX2D_OK)return code;
    code=gx2d_polar_frame_set(&trial,polar);if(code!=GX2D_OK)return code;
    code=gx2d_coordinate_mode_set(&trial,mode);if(code!=GX2D_OK)return code;
    s->grid=trial.grid;s->background=trial.background;s->aspect_mode=trial.aspect_mode;s->view=trial.view;
    s->polar=trial.polar;s->coordinate_mode=trial.coordinate_mode;return GX2D_OK;
}
gx2d_status gx2d_angle_normalize(double value,int degrees,double *out) {
    double turn=degrees?360:2*acos(-1.),normalized;
    if(!out||!isfinite(value)||(degrees!=0&&degrees!=1))return GX2D_INVALID;
    normalized=fmod(value,turn);if(normalized<0)normalized+=turn;
    if(normalized>=turn||normalized==0)normalized=0;*out=normalized;return GX2D_OK;
}
gx2d_status gx2d_cartesian_to_polar(const gx2d_scene *s,gx2d_point world,gx2d_point *out) {
    double angle,dx,dy;gx2d_point value;
    if(!s||!out||!finite2(world))return GX2D_INVALID;
    dx=world.x-s->polar.origin.x;dy=world.y-s->polar.origin.y;
    value.x=hypot(dx,dy);if(!isfinite(value.x))return GX2D_RANGE;
    angle=value.x==0?0:atan2(dy,dx)-s->polar.theta_zero;
    if(s->polar.clockwise)angle=-angle;
    gx2d_angle_normalize(angle,0,&angle);value.y=s->polar.degrees?angle*180/acos(-1.):angle;
    *out=value;return GX2D_OK;
}
gx2d_status gx2d_cartesian_to_polar_many(const gx2d_scene *s,const gx2d_point *input,size_t n,gx2d_point *out,unsigned char *defined) {
    gx2d_point *candidate;size_t i;gx2d_status code;
    if(!s||!input||!out||!defined||!n||n>SIZE_MAX/sizeof(*candidate))return GX2D_INVALID;
    candidate=(gx2d_point *)malloc(n*sizeof(*candidate));if(!candidate)return GX2D_NOMEM;
    for(i=0;i<n;++i){code=gx2d_cartesian_to_polar(s,input[i],candidate+i);if(code!=GX2D_OK){free(candidate);return code;}}
    for(i=0;i<n;++i)defined[i]=(unsigned char)(candidate[i].x>0);
    memcpy(out,candidate,n*sizeof(*candidate));free(candidate);return GX2D_OK;
}
gx2d_status gx2d_polar_to_cartesian(const gx2d_scene *s,gx2d_point p,gx2d_point *out) {
    double angle;gx2d_point value;
    if(!s||!out||!finite2(p)||p.x<0)return GX2D_INVALID;
    angle=s->polar.degrees?p.y*acos(-1.)/180:p.y;
    if(!isfinite(angle))return GX2D_RANGE;
    /* Reduce before adding the frame angle to avoid overflow for valid input. */
    gx2d_angle_normalize(angle,0,&angle);
    angle=s->polar.theta_zero+(s->polar.clockwise?-angle:angle);
    if(!isfinite(angle))return GX2D_RANGE;
    value=(gx2d_point){s->polar.origin.x+p.x*cos(angle),s->polar.origin.y+p.x*sin(angle)};
    if(!finite2(value))return GX2D_RANGE;*out=value;return GX2D_OK;
}
gx2d_status gx2d_polar_snap(const gx2d_scene *s,gx2d_point world,unsigned axes,gx2d_point *out) {
    gx2d_point p;double angle,original_angle,relative,steps;gx2d_status code;
    if(!s||!out||axes<1||axes>3)return GX2D_INVALID;
    code=gx2d_cartesian_to_polar(s,world,&p);if(code!=GX2D_OK)return code;
    angle=s->polar.degrees?p.y*acos(-1.)/180:p.y;
    original_angle=angle;
    gx2d_angle_normalize(angle-s->polar.angle_min,0,&relative);
    if(s->polar.angle_span<2*acos(-1.)&&relative>s->polar.angle_span+1e-12)return GX2D_RANGE;
    if(axes&2){steps=relative/s->polar.angular_spacing;if(!isfinite(steps))return GX2D_RANGE;
        relative=round(steps)*s->polar.angular_spacing;
        if(s->polar.angle_span<2*acos(-1.)&&relative>s->polar.angle_span+1e-12)return GX2D_RANGE;
        angle=s->polar.angle_min+relative;}
    if(axes&1){
        /* A joint nearest intersection minimizes Cartesian distance along the
         * chosen spoke; independent rounding of radius can choose a farther
         * lattice point. Radial-only snapping retains the input angle. */
        double radial=axes==3?fmax(s->polar.radius_min,p.x*cos(original_angle-angle)):p.x;
        steps=(radial-s->polar.radius_min)/s->polar.radial_spacing;
        if(!isfinite(steps))return GX2D_RANGE;p.x=s->polar.radius_min+round(steps)*s->polar.radial_spacing;
    }
    if(p.x<s->polar.radius_min||p.x>s->polar.radius_max)return GX2D_RANGE;
    p.y=s->polar.degrees?angle*180/acos(-1.):angle;
    return gx2d_polar_to_cartesian(s,p,out);
}
static gx2d_point polar_world(const gx2d_polar_frame *p,double radius,double angle) {
    double theta=p->theta_zero+(p->clockwise?-angle:angle);
    return (gx2d_point){p->origin.x+radius*cos(theta),p->origin.y+radius*sin(theta)};
}
static gx2d_status polar_segment(const gx2d_scene *s,gx2d_point a,gx2d_point b,int type,gx2d_grid_segment *out,size_t capacity,size_t *n) {
    gx2d_grid_segment line;gx2d_status code;
    if(!finite2(a)||!finite2(b))return GX2D_RANGE;
    if(!clip_grid_segment(s->view.world,&a,&b))return GX2D_OK;
    code=gx2d_world_to_device(s,a,&line.a);if(code!=GX2D_OK)return code;
    code=gx2d_world_to_device(s,b,&line.b);if(code!=GX2D_OK)return code;
    line.classification=type;if(out&&*n<capacity)out[*n]=line;++*n;return GX2D_OK;
}
gx2d_status gx2d_polar_grid_render(const gx2d_scene *s,gx2d_grid_segment *out,size_t capacity,size_t *count) {
    const gx2d_polar_frame *p;const gx2d_grid *g;double last,stride,k;size_t n=0,attempts=0,j;gx2d_status code;
    if(!s||!count||capacity>65536)return GX2D_INVALID;*count=0;p=&s->polar;g=&s->grid;
    if(!g->enabled||!g->visible)return GX2D_OK;
    last=floor((p->radius_max-p->radius_min)/p->radial_spacing);if(!isfinite(last))return GX2D_RANGE;
    stride=last>23?ceil(last/(23*p->radial_major_interval))*p->radial_major_interval:1;
    for(k=0;k<=last&&attempts++<24;){
        double radius=p->radius_min+k*p->radial_spacing;
        int type=fmod(k,(double)p->radial_major_interval)<.5?1:0;
        int visible=type?g->major_visible:g->minor_visible;
        if(radius>0&&visible)for(j=0;j<64;++j){
            double a=p->angle_min+p->angle_span*j/64,b=p->angle_min+p->angle_span*(j+1)/64;
            code=polar_segment(s,polar_world(p,radius,a),polar_world(p,radius,b),type,out,capacity,&n);
            if(code!=GX2D_OK)return code;
        }
        if(k+stride==k)break;k+=stride;
    }
    last=ceil(p->angle_span/p->angular_spacing);if(!isfinite(last))return GX2D_RANGE;
    stride=last>63?ceil(last/(63*p->angular_major_interval))*p->angular_major_interval:1;
    attempts=0;
    for(k=0;k<=last&&attempts++<64;){
        double angle=p->angle_min+k*p->angular_spacing;
        int type=k==0?2:(fmod(k,(double)p->angular_major_interval)<.5?1:0);
        int visible=type==2?g->axes_visible:type==1?g->major_visible:g->minor_visible;
        if(angle>p->angle_min+p->angle_span+1e-12)break;
        if(k>0&&angle>=p->angle_min+p->angle_span-1e-12&&p->angle_span==2*acos(-1.))break;
        if(visible){code=polar_segment(s,polar_world(p,p->radius_min,angle),polar_world(p,p->radius_max,angle),type,out,capacity,&n);if(code!=GX2D_OK)return code;}
        if(k+stride==k)break;k+=stride;
    }
    *count=n;return out&&capacity<n?GX2D_RANGE:GX2D_OK;
}

typedef struct {gx2d_point point;uint64_t row;size_t logical,run;int present;} display_value;
typedef struct {display_value xmin,xmax,ymin,ymax;} display_bucket;
struct gx2d_display_accumulator {
    size_t total,budget,position,finite_count,bucket_count;
    uint64_t row_base;
    display_bucket *buckets;
    display_value *exact,first,last;
    gx2d_rect bounds;
    int have_bounds,previous_finite;
    size_t run;
};
gx2d_display_accumulator *gx2d_display_begin(size_t total,size_t budget,uint64_t base) {
    gx2d_display_accumulator *a;
    if(!total||budget<6||budget>65536||base>UINT64_MAX-total)return NULL;
    a=(gx2d_display_accumulator *)calloc(1,sizeof(*a));if(!a)return NULL;
    a->total=total;a->budget=budget;a->row_base=base;
    if(total<=budget){a->exact=(display_value *)calloc(total,sizeof(*a->exact));if(!a->exact){free(a);return NULL;}}
    else{a->bucket_count=(budget-2)/4;a->buckets=(display_bucket *)calloc(a->bucket_count,sizeof(*a->buckets));if(!a->buckets){free(a);return NULL;}}
    return a;
}
void gx2d_display_destroy(gx2d_display_accumulator *a) {
    if(a){free(a->exact);free(a->buckets);free(a);}
}
gx2d_status gx2d_display_push_rows(gx2d_display_accumulator *a,size_t start,const gx2d_point *points,const uint64_t *rows,size_t count) {
    size_t i;
    if(!a||(!points&&count)||count>65536)return GX2D_INVALID;
    if(start!=a->position||start>a->total||count>a->total-start)return GX2D_RANGE;
    for(i=0;i<count;++i){
        gx2d_point p=points[i];display_value v;size_t index;
        if(!finite2(p)){if(a->previous_finite)++a->run;a->previous_finite=0;continue;}
        v=(display_value){p,rows?rows[i]:a->row_base+start+i,start+i,a->run,1};
        a->previous_finite=1;
        include_point(&a->bounds,p,&a->have_bounds);
        if(!a->first.present)a->first=v;a->last=v;
        if(a->exact)a->exact[a->finite_count]=v;
        else{
            display_bucket *b;
            index=(size_t)(((long double)(start+i)*a->bucket_count)/a->total);
            if(index>=a->bucket_count)index=a->bucket_count-1;b=&a->buckets[index];
            if(!b->xmin.present||p.x<b->xmin.point.x)b->xmin=v;
            if(!b->xmax.present||p.x>b->xmax.point.x)b->xmax=v;
            if(!b->ymin.present||p.y<b->ymin.point.y)b->ymin=v;
            if(!b->ymax.present||p.y>b->ymax.point.y)b->ymax=v;
        }
        ++a->finite_count;
    }
    a->position+=count;return GX2D_OK;
}
gx2d_status gx2d_display_push(gx2d_display_accumulator *a,size_t start,const gx2d_point *points,size_t count) {
    return gx2d_display_push_rows(a,start,points,NULL,count);
}
gx2d_status gx2d_display_mark_break(gx2d_display_accumulator *a) {
    if(!a)return GX2D_INVALID;if(a->previous_finite)++a->run;a->previous_finite=0;return GX2D_OK;
}
static int display_row_compare(const void *left,const void *right) {
    size_t a=((const display_value *)left)->logical,b=((const display_value *)right)->logical;
    return a<b?-1:a>b?1:0;
}
static gx2d_status display_values(const gx2d_display_accumulator *a,display_value **out,size_t *count) {
    display_value *values;size_t n=0,i,k;
    if(!a||!out||!count)return GX2D_INVALID;
    if(a->position!=a->total)return GX2D_BUSY;
    *count=0;if(!a->have_bounds)return GX2D_NOT_FOUND;
    values=(display_value *)calloc(a->budget,sizeof(*values));if(!values)return GX2D_NOMEM;
    if(a->exact){n=a->finite_count;memcpy(values,a->exact,n*sizeof(*values));}
    else{
        values[n++]=a->first;
        for(i=0;i<a->bucket_count;++i){
            display_value bucket[4]={a->buckets[i].xmin,a->buckets[i].xmax,a->buckets[i].ymin,a->buckets[i].ymax};
            for(k=0;k<4;++k)if(bucket[k].present)values[n++]=bucket[k];
        }
        values[n++]=a->last;qsort(values,n,sizeof(*values),display_row_compare);
    }
    k=0;for(i=0;i<n;++i){
        if(k&&values[i].logical==values[k-1].logical)continue;
        values[k++]=values[i];
    }
    *out=values;*count=k;return GX2D_OK;
}
gx2d_status gx2d_display_result(const gx2d_display_accumulator *a,gx2d_point *points,uint64_t *rows,size_t capacity,size_t *count,size_t *finite,gx2d_rect *bounds) {
    display_value *values;size_t n,i;gx2d_status code;
    if(!a||!count||!finite||!bounds||(!points&&rows)||capacity>65536)return GX2D_INVALID;
    code=display_values(a,&values,&n);if(code!=GX2D_OK)return code;
    *count=n;*finite=a->finite_count;*bounds=a->bounds;
    for(i=0;points&&i<n&&i<capacity;++i){points[i]=values[i].point;if(rows)rows[i]=values[i].row;}
    free(values);return points&&capacity<n?GX2D_RANGE:GX2D_OK;
}
gx2d_status gx2d_display_breaks(const gx2d_display_accumulator *a,size_t *indices,size_t capacity,size_t *count) {
    display_value *values;size_t n,i,k=0;gx2d_status code;
    if(!a||!count||capacity>65536)return GX2D_INVALID;
    code=display_values(a,&values,&n);if(code!=GX2D_OK)return code;
    for(i=0;i+1<n;++i)if(values[i].run!=values[i+1].run){if(indices&&k<capacity)indices[k]=i;++k;}
    free(values);*count=k;return indices&&capacity<k?GX2D_RANGE:GX2D_OK;
}
gx2d_status gx2d_get_points_range(const gx2d_scene *s,gx2d_id id,size_t start,size_t n,gx2d_point *out,size_t capacity,size_t *returned) {
    const object *o=cobj(s,id);
    if(!returned||n>65536)return GX2D_INVALID;if(!o)return GX2D_NOT_FOUND;
    if(o->kind==GX2D_GROUP)return GX2D_INVALID;
    if(start>o->count||n>o->count-start)return GX2D_RANGE;
    *returned=n;if(out&&capacity<n)return GX2D_RANGE;
    if(out&&n)memcpy(out,o->points+start,n*sizeof(*out));return GX2D_OK;
}
static gx2d_status object_sample(const gx2d_scene *s,gx2d_id id,size_t budget,gx2d_point *out,uint64_t *indices,size_t capacity,size_t *count,size_t *cuts,size_t cut_capacity,size_t *ncuts,int device) {
    const object *o=cobj(s,id);gx2d_display_accumulator *a;gx2d_status code=GX2D_OK;size_t start=0,end,i,finite,n=0;gx2d_rect bounds;
    if(!o)return GX2D_NOT_FOUND;if(!count||!ncuts||o->kind==GX2D_GROUP||!o->count||budget<6||budget>65536)return GX2D_INVALID;
    if(device&&o->sketch&&o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE){
        gx2d_point clipped[2];code=sketch_construction_clip(s,o->sketch,clipped);*ncuts=0;*count=code==GX2D_NOT_FOUND?0:2;
        if(code==GX2D_NOT_FOUND)return GX2D_OK;if(code!=GX2D_OK)return code;if(!out)return GX2D_OK;if(capacity<2)return GX2D_RANGE;
        for(i=0;i<2;++i){code=gx2d_world_to_device(s,clipped[i],&out[i]);if(code!=GX2D_OK)return code;if(indices)indices[i]=i;}return GX2D_OK;
    }
    if(device&&o->sketch&&o->sketch->family!=GX2D_SKETCH_CONSTRUCTION_LINE) {
        code=sketch_render_device(s,o,budget,out,indices,capacity,count,cuts,cut_capacity,ncuts);
        if(code!=GX2D_NOT_FOUND)return code;
    }
    a=gx2d_display_begin(o->count,budget,0);if(!a)return GX2D_NOMEM;
    while(start<o->count){
        end=start;while(end+1<o->count&&end-start+1<65536&&!o->breaks[end])++end;
        code=gx2d_display_push(a,start,o->points+start,end-start+1);if(code!=GX2D_OK)break;
        start=end+1;if(start<o->count&&o->breaks[end])gx2d_display_mark_break(a);
    }
    if(code==GX2D_OK)code=gx2d_display_result(a,out,indices,capacity,&n,&finite,&bounds);
    if(code==GX2D_OK&&out&&device)for(i=0;i<n;++i){gx2d_point p;code=gx2d_world_to_device(s,out[i],&p);if(code!=GX2D_OK)break;out[i]=p;}
    if(code==GX2D_OK)code=gx2d_display_breaks(a,cuts,cut_capacity,ncuts);
    *count=n;gx2d_display_destroy(a);return code;
}
gx2d_status gx2d_object_display(const gx2d_scene *s,gx2d_id id,size_t budget,gx2d_point *out,uint64_t *indices,size_t capacity,size_t *count,size_t *cuts,size_t cut_capacity,size_t *ncuts) {
    return object_sample(s,id,budget,out,indices,capacity,count,cuts,cut_capacity,ncuts,1);
}
gx2d_status gx2d_object_sample(const gx2d_scene *s,gx2d_id id,size_t budget,gx2d_point *out,uint64_t *indices,size_t capacity,size_t *count,size_t *cuts,size_t cut_capacity,size_t *ncuts) {
    return object_sample(s,id,budget,out,indices,capacity,count,cuts,cut_capacity,ncuts,0);
}
gx2d_status gx2d_curve_display(const gx2d_scene *s,gx2d_id id,size_t budget,gx2d_point *out,uint64_t *indices,size_t capacity,size_t *count,size_t *cuts,size_t cut_capacity,size_t *ncuts){
    const object *o=cobj(s,id);gx2d_display_accumulator *a;gx2d_status code=GX2D_OK;
    gx2d_point buffer[16];uint64_t mapping[16];gx2d_rect bounds;
    size_t per,segment,k,total=1,position=0,n,finite;
    if(!o)return GX2D_NOT_FOUND;
    if(o->sketch||o->kind!=GX2D_CURVE||!o->direction_marker.interpolation)return gx2d_object_display(s,id,budget,out,indices,capacity,count,cuts,cut_capacity,ncuts);
    if(!count||!ncuts||budget<6||budget>65536)return GX2D_INVALID;
    per=o->count>65536?2:o->count>4096?8:16;
    for(segment=0;segment+1<o->count;++segment){n=o->breaks[segment]?1:per;if(total>SIZE_MAX-n)return GX2D_RANGE;total+=n;}
    a=gx2d_display_begin(total,budget,0);if(!a)return GX2D_NOMEM;
    for(segment=0;segment+1<o->count&&code==GX2D_OK;++segment){
        n=o->breaks[segment]?1:per;
        for(k=0;k<n;++k){buffer[k]=spline_at(o,segment,(double)k/per);mapping[k]=segment;}
        code=gx2d_display_push_rows(a,position,buffer,mapping,n);position+=n;
        if(code==GX2D_OK&&o->breaks[segment])code=gx2d_display_mark_break(a);
    }
    if(code==GX2D_OK){buffer[0]=o->points[o->count-1];mapping[0]=o->count-1;code=gx2d_display_push_rows(a,position,buffer,mapping,1);}
    if(code==GX2D_OK)code=gx2d_display_result(a,out,indices,capacity,count,&finite,&bounds);
    if(code==GX2D_OK&&out)for(k=0;k<*count;++k){gx2d_point p;code=gx2d_world_to_device(s,out[k],&p);if(code!=GX2D_OK)break;out[k]=p;}
    if(code==GX2D_OK)code=gx2d_display_breaks(a,cuts,cut_capacity,ncuts);
    gx2d_display_destroy(a);return code;
}
gx2d_status gx2d_numeric_pack(const gx2d_point *points,const uint64_t *source_rows,uint64_t base,size_t count,unsigned char *xy,size_t xy_capacity,unsigned char *rows,size_t rows_capacity,size_t *finite_count) {
    size_t i,j,n=0;uint64_t bits,row;
    if(!finite_count||(count&&(!points||!xy||!rows))||sizeof(double)!=8||DBL_MANT_DIG!=53)return GX2D_INVALID;
    if(count>65536||xy_capacity<count*16||rows_capacity<count*8||(!source_rows&&count&&base>UINT64_MAX-count+1))return GX2D_RANGE;
    for(i=0;i<count;++i){
        if(!finite2(points[i]))continue;
        memcpy(&bits,&points[i].x,8);for(j=0;j<8;++j)xy[n*16+j]=(unsigned char)(bits>>(8*j));
        memcpy(&bits,&points[i].y,8);for(j=0;j<8;++j)xy[n*16+8+j]=(unsigned char)(bits>>(8*j));
        row=source_rows?source_rows[i]:base+i;for(j=0;j<8;++j)rows[n*8+j]=(unsigned char)(row>>(8*j));
        ++n;
    }
    *finite_count=n;return GX2D_OK;
}

#include "gx2d_bridge.inc"
#include "gx2d_cad.inc"
#include "gx2d_gizmo.inc"
#include "gx2d_snap.inc"
#include "gx2d_units.inc"
#include "gx2d_sketch.inc"
#include "gx2d_retained_display.inc"

#include "gx2d_interaction.inc"
#include "gx2d_span.inc"

#include "gx2d_constraints.inc"
#include "gx2d_interaction_constraints.inc"
#include "gx2d_sketch_solver.inc"
#include "gx2d_construction.inc"

#include "gx2d_measurements.inc"

#include "gx2d_identity.inc"

#include "gx2d_collections.inc"

/* Presentation snapshots validate against a temporary model before commit. */
gx2d_status gx2d_view_state_get(const gx2d_scene *s,gx2d_view_state *out){if(!s||!out)return GX2D_INVALID;*out=(gx2d_view_state){s->requested_view,s->grid,s->background,s->aspect_mode,s->polar,s->coordinate_mode};return GX2D_OK;}
gx2d_status gx2d_view_state_set(gx2d_scene *s,const gx2d_view_state *state){gx2d_scene trial;gx2d_status code;if(!s||!state)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;trial=*s;
    code=gx2d_view_set(&trial,&state->view);if(code!=GX2D_OK)return code;code=gx2d_presentation_frame_set(&trial,&state->grid,state->background,state->aspect,&state->polar,state->coordinate_mode);if(code!=GX2D_OK)return code;
    s->requested_view=trial.requested_view;s->view=trial.view;s->grid=trial.grid;s->background=trial.background;s->aspect_mode=trial.aspect_mode;s->polar=trial.polar;s->coordinate_mode=trial.coordinate_mode;return GX2D_OK;
}
gx2d_status gx2d_view_state_rescale(const gx2d_view_state *state,double factor,gx2d_view_state *out){gx2d_view_state result;gx2d_scene trial;gx2d_status code;
    if(!state||!out||!isfinite(factor)||factor<=0)return GX2D_INVALID;memset(&trial,0,sizeof(trial));trial.view=trial.requested_view=state->view;trial.aspect_mode=state->aspect;
    code=gx2d_view_state_set(&trial,state);if(code!=GX2D_OK)return code;result=*state;
    if(!units_rect(&result.view.world,factor)||!units_point(&result.grid.origin,factor)||!units_point(&result.polar.origin,factor))return GX2D_RANGE;
    result.grid.spacing_x*=factor;result.grid.spacing_y*=factor;result.polar.radius_min*=factor;result.polar.radius_max*=factor;result.polar.radial_spacing*=factor;
    code=gx2d_view_state_set(&trial,&result);if(code!=GX2D_OK)return code;*out=result;return GX2D_OK;
}

#include "gx2d_compare_geometry.inc"

#include "gx2d_reference_images.inc"

/* The existing rule/solver owns the mirror relation. Creation rolls back all
 * new objects/rules while retaining monotonic IDs on rejected candidates. */
gx2d_status gx2d_symmetry_preview(const gx2d_scene *s,const gx2d_reference *axis,const gx2d_sketch_definition *d,gx2d_sketch_definition *out){
    gx2d_point a,b,direction,resolved;double matrix[6];gx2d_status code;
    if(!s||!axis||!d||!out)return GX2D_INVALID;
    code=gx2d_sketch_validate(d);if(code!=GX2D_OK)return code;
    if(d->family==GX2D_SKETCH_ARC||d->family==GX2D_SKETCH_ELLIPSE||d->family==GX2D_SKETCH_RECTANGLE||d->control_count>12)return GX2D_INVALID;
    for(size_t i=0;i<d->tangent_count;i++)if(d->tangents[i].flags)return GX2D_INVALID;
    code=gx2d_reference_resolve(s,axis,&resolved);if(code!=GX2D_OK)return code;
    if(axis->entity==GX2D_ENTITY_CONTROL)return GX2D_INVALID;
    code=constraint_segment(cobj(s,axis->object),axis->index,&a,&b,&direction);if(code!=GX2D_OK)return code;
    code=gx2d_reflection_matrix(a,b,matrix);if(code!=GX2D_OK)return code;
    gx2d_sketch_definition mirrored=*d;if(!sketch_compose(&mirrored,matrix))return GX2D_RANGE;
    *out=mirrored;return GX2D_OK;
}
gx2d_status gx2d_symmetry_attach(gx2d_scene *s,gx2d_id source,const gx2d_reference *axis,gx2d_id *mirror,gx2d_id *relationship){
    if(!s||!mirror||!relationship)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    const object *o=cobj(s,source);if(!o||!o->sketch)return GX2D_INVALID;
    gx2d_sketch_definition d;gx2d_status code=gx2d_symmetry_preview(s,axis,o->sketch,&d);if(code!=GX2D_OK)return code;
    size_t samples=o->count;gx2d_id id,rule_id;
    code=gx2d_sketch_create(s,&d,samples,&id);if(code!=GX2D_OK)return code;
    gx2d_constraint_v2 spec={0};spec.base.kind=GX2D_SYMMETRY;spec.base.a=source;spec.base.b=id;spec.base.a_index=spec.base.b_index=GX2D_OBJECT_INDEX;spec.base.tolerance=1e-7;spec.axis=axis->object;spec.axis_index=axis->index;
    gx2d_relationship_state state={0};state.solved=1;
    code=gx2d_constraint_create_state(s,&spec,&state,&rule_id);
    if(code!=GX2D_OK){gx2d_delete_object(s,id);return code;}
    *mirror=id;*relationship=rule_id;return GX2D_OK;
}
gx2d_status gx2d_symmetry_construct(gx2d_scene *s,const gx2d_reference *axis,const gx2d_sketch_definition *d,size_t samples,gx2d_id out[3]){
    if(!s||!out)return GX2D_INVALID;gx2d_sketch_definition preview;gx2d_status code=gx2d_symmetry_preview(s,axis,d,&preview);if(code!=GX2D_OK)return code;
    gx2d_id ids[3];code=gx2d_sketch_create(s,d,samples,&ids[0]);if(code!=GX2D_OK)return code;
    code=gx2d_symmetry_attach(s,ids[0],axis,&ids[1],&ids[2]);if(code!=GX2D_OK){gx2d_delete_object(s,ids[0]);return code;}
    memcpy(out,ids,sizeof(ids));return GX2D_OK;
}

#include "gx2d_parts.inc"

#include "gx2d_presentation_visit_v1.h"
#include "gx2d_presentation_visit_v1.inc"
