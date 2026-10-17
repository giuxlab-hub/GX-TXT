/* Small Tcl adapter for the public Native 2D C API. No geometry lives here. */
#include "gx2d.h"
#include "gx2d_surface.h"
#ifdef GXTXT_NATIVE_PLOT_V4
#include "gx2d_plot_v4.h"
#endif
#include <tcl.h>
#include <stdint.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct scene_node {
    uint64_t serial;
    gx2d_scene *scene;
    gx2d_display_accumulator *display;
    Tcl_Obj *axis_presentation;
    struct scene_node *next;
} scene_node;
typedef struct { scene_node *head; uint64_t next; } bridge;

static int fail(Tcl_Interp *ip, const char *message) {
    Tcl_SetObjResult(ip, Tcl_NewStringObj(message, -1));
    return TCL_ERROR;
}
static int status(Tcl_Interp *ip, gx2d_status code) {
    if (code == GX2D_OK) return TCL_OK;
    return fail(ip, gx2d_status_text(code));
}
static void free_bridge(ClientData data) {
    bridge *b = (bridge *)data;
    scene_node *p = b->head;
    while (p) { scene_node *next = p->next; gx2d_display_destroy(p->display);gx2d_destroy(p->scene);if(p->axis_presentation)Tcl_DecrRefCount(p->axis_presentation); free(p); p = next; }
    free(b);
}
static scene_node *lookup(bridge *b, Tcl_Interp *ip, Tcl_Obj *value) {
    Tcl_WideInt serial;
    scene_node *p;
    if (Tcl_GetWideIntFromObj(ip, value, &serial) != TCL_OK || serial < 1) return NULL;
    for (p = b->head; p; p = p->next) if (p->serial == (uint64_t)serial) return p;
    fail(ip, "Native 2D scene not found");
    return NULL;
}
static int object_id(Tcl_Interp *ip, Tcl_Obj *value, gx2d_id *id) {
    Tcl_WideInt n;
    if (Tcl_GetWideIntFromObj(ip, value, &n) != TCL_OK) return TCL_ERROR;
    if (n < 1) return fail(ip, "Native 2D object ID must be positive");
    *id = (gx2d_id)n;
    return TCL_OK;
}
static Tcl_Obj *point_obj(gx2d_point p) {
    Tcl_Obj *items[2];
    items[0] = Tcl_NewDoubleObj(p.x); items[1] = Tcl_NewDoubleObj(p.y);
    return Tcl_NewListObj(2, items);
}
static Tcl_Obj *rect_obj(gx2d_rect r) {
    Tcl_Obj *v[4]={Tcl_NewDoubleObj(r.x0),Tcl_NewDoubleObj(r.y0),Tcl_NewDoubleObj(r.x1),Tcl_NewDoubleObj(r.y1)};
    return Tcl_NewListObj(4,v);
}
static int read_rect(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_rect *r){
    Tcl_Obj **v;int n;
    if(Tcl_ListObjGetElements(ip,arg,&n,&v)!=TCL_OK||n!=4||
       Tcl_GetDoubleFromObj(ip,v[0],&r->x0)!=TCL_OK||Tcl_GetDoubleFromObj(ip,v[1],&r->y0)!=TCL_OK||
       Tcl_GetDoubleFromObj(ip,v[2],&r->x1)!=TCL_OK||Tcl_GetDoubleFromObj(ip,v[3],&r->y1)!=TCL_OK)
       return fail(ip,"Expected four numeric bounds");
    return TCL_OK;
}
static int index_arg(Tcl_Interp *ip,Tcl_Obj *arg,size_t *out){Tcl_WideInt v;
    if(Tcl_GetWideIntFromObj(ip,arg,&v)!=TCL_OK||v<0)return fail(ip,"Index must be nonnegative");
    *out=(size_t)v;return TCL_OK;
}
static Tcl_Obj *segment_obj(gx2d_segment_hit h){
    Tcl_Obj *r=Tcl_NewDictObj();
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("segment",-1),Tcl_NewWideIntObj((Tcl_WideInt)h.segment));
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("t",-1),Tcl_NewDoubleObj(h.t));
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("distance",-1),Tcl_NewDoubleObj(h.distance));
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("point",-1),point_obj(h.point));return r;
}
static int read_point(Tcl_Interp *ip, Tcl_Obj *arg, gx2d_point *point) {
    Tcl_Obj **xy;
    int count;
    if (Tcl_ListObjGetElements(ip, arg, &count, &xy) != TCL_OK || count != 2 ||
        Tcl_GetDoubleFromObj(ip, xy[0], &point->x) != TCL_OK ||
        Tcl_GetDoubleFromObj(ip, xy[1], &point->y) != TCL_OK)
        return fail(ip, "Point must contain numeric X and Y");
    return TCL_OK;
}
static int read_mode(Tcl_Interp *ip, Tcl_Obj *arg, gx2d_select_mode *mode) {
    const char *word = Tcl_GetString(arg);
    if (strcmp(word, "replace") == 0) *mode = GX2D_SELECT_REPLACE;
    else if (strcmp(word, "add") == 0) *mode = GX2D_SELECT_ADD;
    else if (strcmp(word, "subtract") == 0) *mode = GX2D_SELECT_SUBTRACT;
    else return fail(ip, "Selection mode must be replace, add or subtract");
    return TCL_OK;
}
static Tcl_Obj *endpoint_frame_obj(gx2d_endpoint_frame frame) {
    Tcl_Obj *r=Tcl_NewDictObj();
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("point",-1),point_obj(frame.point));
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("derivative",-1),point_obj(frame.derivative));
    Tcl_DictObjPut(NULL,r,Tcl_NewStringObj("point_index",-1),Tcl_NewWideIntObj((Tcl_WideInt)frame.point_index));
    return r;
}
static int read_endpoint_frame(Tcl_Interp *ip,Tcl_Obj *value,gx2d_endpoint_frame *frame) {
    Tcl_Obj *point=NULL,*derivative=NULL;
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("point",-1),&point)!=TCL_OK||
       Tcl_DictObjGet(ip,value,Tcl_NewStringObj("derivative",-1),&derivative)!=TCL_OK||
       !point||!derivative||read_point(ip,point,&frame->point)!=TCL_OK||
       read_point(ip,derivative,&frame->derivative)!=TCL_OK)
        return fail(ip,"Endpoint frame needs point and derivative XY pairs");
    frame->point_index=0;return TCL_OK;
}
static Tcl_Obj *bridge_result_obj(Tcl_Interp *ip,gx2d_id id,const char *kind,
    gx2d_bridge_spec spec,gx2d_bridge_result receipt) {
    size_t i;Tcl_Obj *result,*controls;
    result=Tcl_NewDictObj();controls=Tcl_NewListObj(0,NULL);
        for(i=0;i<receipt.control_count;++i)Tcl_ListObjAppendElement(ip,controls,point_obj(receipt.controls[i]));
#define BRIDGE_PUT(key,value) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(key,-1),value)
        BRIDGE_PUT("native",Tcl_NewWideIntObj((Tcl_WideInt)id));
        BRIDGE_PUT("kind",Tcl_NewStringObj(kind,-1));BRIDGE_PUT("controls",controls);
        BRIDGE_PUT("start",endpoint_frame_obj(spec.start));BRIDGE_PUT("end",endpoint_frame_obj(spec.end));
        BRIDGE_PUT("start_derivative",point_obj(receipt.start_derivative));BRIDGE_PUT("end_derivative",point_obj(receipt.end_derivative));
        BRIDGE_PUT("c0",Tcl_NewBooleanObj(receipt.c0));
        BRIDGE_PUT("c1_start",Tcl_NewBooleanObj(receipt.c1_start));BRIDGE_PUT("c1_end",Tcl_NewBooleanObj(receipt.c1_end));
        BRIDGE_PUT("tangent_start",Tcl_NewBooleanObj(receipt.tangent_start));BRIDGE_PUT("tangent_end",Tcl_NewBooleanObj(receipt.tangent_end));
        BRIDGE_PUT("subdivisions",Tcl_NewWideIntObj((Tcl_WideInt)spec.subdivisions));
        BRIDGE_PUT("tolerance",Tcl_NewDoubleObj(spec.tolerance));
        BRIDGE_PUT("parameter_policy",Tcl_NewStringObj("incident_segment_local_0_1",-1));
#undef BRIDGE_PUT
    return result;
}
static Tcl_Obj *hit_obj(gx2d_hit hit) {
    Tcl_Obj *result = Tcl_NewDictObj();
    Tcl_DictObjPut(NULL, result, Tcl_NewStringObj("object", -1), Tcl_NewWideIntObj((Tcl_WideInt)hit.object));
    Tcl_DictObjPut(NULL, result, Tcl_NewStringObj("index", -1), Tcl_NewWideIntObj((Tcl_WideInt)hit.point_index));
    Tcl_DictObjPut(NULL, result, Tcl_NewStringObj("point", -1), point_obj(hit.point));
    Tcl_DictObjPut(NULL, result, Tcl_NewStringObj("distance", -1), Tcl_NewDoubleObj(hit.distance));
    return result;
}
static int point_list(Tcl_Interp *ip, Tcl_Obj *arg, gx2d_point **out, size_t *count) {
    Tcl_Obj **rows, **xy;
    int n, i, m;
    gx2d_point *points;
    if (Tcl_ListObjGetElements(ip, arg, &n, &rows) != TCL_OK) return TCL_ERROR;
    if (n < 1) return fail(ip, "Native 2D geometry needs at least one XY point");
    points = (gx2d_point *)calloc((size_t)n, sizeof(*points));
    if (!points) return fail(ip, "Out of memory");
    for (i = 0; i < n; ++i) {
        if (Tcl_ListObjGetElements(ip, rows[i], &m, &xy) != TCL_OK || m != 2 ||
            Tcl_GetDoubleFromObj(ip, xy[0], &points[i].x) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, xy[1], &points[i].y) != TCL_OK) {
            free(points); return fail(ip, "Each curve point must have numeric X and Y");
        }
    }
    *out = points; *count = (size_t)n;
    return TCL_OK;
}
static Tcl_Obj *color_obj(gx2d_color c) {
    Tcl_Obj *v[4]={Tcl_NewDoubleObj(c.red),Tcl_NewDoubleObj(c.green),Tcl_NewDoubleObj(c.blue),Tcl_NewDoubleObj(c.alpha)};
    return Tcl_NewListObj(4,v);
}
static int read_color(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_color *c) {
    Tcl_Obj **v;int n;
    if(Tcl_ListObjGetElements(ip,arg,&n,&v)!=TCL_OK||n!=4)return fail(ip,"Expected normalized RGBA color");
    if(Tcl_GetDoubleFromObj(ip,v[0],&c->red)!=TCL_OK||Tcl_GetDoubleFromObj(ip,v[1],&c->green)!=TCL_OK||Tcl_GetDoubleFromObj(ip,v[2],&c->blue)!=TCL_OK||Tcl_GetDoubleFromObj(ip,v[3],&c->alpha)!=TCL_OK)return TCL_ERROR;
    return TCL_OK;
}
static const char *gizmo_handles[]={"none","pivot","x","y","free","rotate","mirror_a","mirror_b"};
static Tcl_Obj *gizmo_obj(gx2d_gizmo g) {
    Tcl_Obj *result=Tcl_NewDictObj();
#define GIZMO_PUT(k,v) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#k,-1),v)
    GIZMO_PUT(visible,Tcl_NewBooleanObj(g.visible));
    GIZMO_PUT(mode,Tcl_NewStringObj(g.mode==GX2D_GIZMO_TRANSLATE?"translate":g.mode==GX2D_GIZMO_ROTATE?"rotate":"mirror",-1));
    GIZMO_PUT(radius_px,Tcl_NewDoubleObj(g.radius_px));GIZMO_PUT(handle_px,Tcl_NewDoubleObj(g.handle_px));
    GIZMO_PUT(line_width,Tcl_NewDoubleObj(g.line_width));GIZMO_PUT(axes_angle,Tcl_NewDoubleObj(g.axes_angle));
    GIZMO_PUT(mirror_a,point_obj(g.mirror_a));GIZMO_PUT(mirror_b,point_obj(g.mirror_b));
    GIZMO_PUT(x_color,color_obj(g.x_color));GIZMO_PUT(y_color,color_obj(g.y_color));
    GIZMO_PUT(rotation_color,color_obj(g.rotation_color));GIZMO_PUT(pivot_color,color_obj(g.pivot_color));
#undef GIZMO_PUT
    return result;
}
static int gizmo_read(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_gizmo *g) {
    Tcl_DictSearch search;Tcl_Obj *key,*value;int done,code=TCL_OK;
    if(Tcl_DictObjFirst(ip,arg,&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
    for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)) {
        const char *word=Tcl_GetString(key);
#define GIZMO_NUM(k) if(strcmp(word,#k)==0)code=Tcl_GetDoubleFromObj(ip,value,&g->k)
#define GIZMO_COLOR(k) if(strcmp(word,#k)==0)code=read_color(ip,value,&g->k)
        if(strcmp(word,"visible")==0)code=Tcl_GetBooleanFromObj(ip,value,&g->visible);
        else if(strcmp(word,"mode")==0) {
            const char *mode=Tcl_GetString(value);
            if(strcmp(mode,"translate")==0)g->mode=GX2D_GIZMO_TRANSLATE;
            else if(strcmp(mode,"rotate")==0)g->mode=GX2D_GIZMO_ROTATE;
            else if(strcmp(mode,"mirror")==0)g->mode=GX2D_GIZMO_MIRROR;
            else code=fail(ip,"Gizmo mode must be translate, rotate or mirror");
        }
        else GIZMO_NUM(radius_px);else GIZMO_NUM(handle_px);else GIZMO_NUM(line_width);else GIZMO_NUM(axes_angle);
        else if(strcmp(word,"mirror_a")==0)code=read_point(ip,value,&g->mirror_a);
        else if(strcmp(word,"mirror_b")==0)code=read_point(ip,value,&g->mirror_b);
        else GIZMO_COLOR(x_color);else GIZMO_COLOR(y_color);else GIZMO_COLOR(rotation_color);else GIZMO_COLOR(pivot_color);
        else code=fail(ip,"Unknown Native2D gizmo property");
#undef GIZMO_NUM
#undef GIZMO_COLOR
        if(code!=TCL_OK)break;
    }
    Tcl_DictObjDone(&search);return code;
}
static Tcl_Obj *marker_obj(gx2d_direction_marker m) {
    Tcl_Obj *result=Tcl_NewDictObj();
#define MARKER_INT(key) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#key,-1),Tcl_NewIntObj(m.key))
#define MARKER_DOUBLE(key) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#key,-1),Tcl_NewDoubleObj(m.key))
    MARKER_INT(present);MARKER_INT(visible);MARKER_INT(forward);MARKER_INT(interpolation);
    MARKER_DOUBLE(fraction);MARKER_DOUBLE(offset_px);MARKER_DOUBLE(length_px);MARKER_DOUBLE(line_width);MARKER_DOUBLE(head_scale);
    Tcl_DictObjPut(NULL,result,Tcl_NewStringObj("color",-1),color_obj(m.color));
#undef MARKER_INT
#undef MARKER_DOUBLE
    return result;
}
static int marker_read(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_direction_marker *m) {
    Tcl_DictSearch search;Tcl_Obj *key,*value;int done,code=TCL_OK;
    if(Tcl_DictObjFirst(ip,arg,&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
    for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)) {
        const char *word=Tcl_GetString(key);
#define MARKER_INT(k) if(strcmp(word,#k)==0)code=Tcl_GetBooleanFromObj(ip,value,&m->k)
#define MARKER_DOUBLE(k) if(strcmp(word,#k)==0)code=Tcl_GetDoubleFromObj(ip,value,&m->k)
        MARKER_INT(present);else MARKER_INT(visible);else MARKER_INT(forward);else MARKER_INT(interpolation);
        else MARKER_DOUBLE(fraction);else MARKER_DOUBLE(offset_px);else MARKER_DOUBLE(length_px);else MARKER_DOUBLE(line_width);else MARKER_DOUBLE(head_scale);
        else if(strcmp(word,"color")==0)code=read_color(ip,value,&m->color);
        else code=fail(ip,"Unknown direction marker field");
#undef MARKER_INT
#undef MARKER_DOUBLE
        if(code!=TCL_OK)break;
    }
    Tcl_DictObjDone(&search);return code;
}
static Tcl_Obj *grid_obj(gx2d_grid g) {
    Tcl_Obj *result=Tcl_NewDictObj();
#define GRID_INT(k) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#k,-1),Tcl_NewIntObj(g.k))
#define GRID_DOUBLE(k) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#k,-1),Tcl_NewDoubleObj(g.k))
#define GRID_COLOR(k) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#k,-1),color_obj(g.k))
    GRID_INT(enabled);GRID_INT(visible);GRID_INT(snap_enabled);GRID_INT(major_visible);GRID_INT(minor_visible);GRID_INT(axes_visible);
    GRID_DOUBLE(spacing_x);GRID_DOUBLE(spacing_y);GRID_DOUBLE(angle);GRID_DOUBLE(major_width);GRID_DOUBLE(minor_width);GRID_DOUBLE(axes_width);
    GRID_INT(major_style);GRID_INT(minor_style);GRID_INT(axes_style);
    Tcl_DictObjPut(NULL,result,Tcl_NewStringObj("major_interval",-1),Tcl_NewWideIntObj((Tcl_WideInt)g.major_interval));
    Tcl_DictObjPut(NULL,result,Tcl_NewStringObj("origin",-1),point_obj(g.origin));
    GRID_COLOR(major_color);GRID_COLOR(minor_color);GRID_COLOR(axes_color);
#undef GRID_INT
#undef GRID_DOUBLE
#undef GRID_COLOR
    return result;
}
static int grid_read(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_grid *g) {
    Tcl_DictSearch search;Tcl_Obj *key,*value;int done,code=TCL_OK;
    if(Tcl_DictObjFirst(ip,arg,&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
    for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){
        const char *word=Tcl_GetString(key);
#define GRID_BOOL(k) if(strcmp(word,#k)==0)code=Tcl_GetBooleanFromObj(ip,value,&g->k)
#define GRID_DOUBLE(k) if(strcmp(word,#k)==0)code=Tcl_GetDoubleFromObj(ip,value,&g->k)
#define GRID_COLOR(k) if(strcmp(word,#k)==0)code=read_color(ip,value,&g->k)
#define GRID_INT(k) if(strcmp(word,#k)==0)code=Tcl_GetIntFromObj(ip,value,&g->k)
        GRID_BOOL(enabled);else GRID_BOOL(visible);else GRID_BOOL(snap_enabled);else GRID_BOOL(major_visible);else GRID_BOOL(minor_visible);else GRID_BOOL(axes_visible);
        else GRID_DOUBLE(spacing_x);else GRID_DOUBLE(spacing_y);else GRID_DOUBLE(angle);else GRID_DOUBLE(major_width);else GRID_DOUBLE(minor_width);else GRID_DOUBLE(axes_width);
        else GRID_INT(major_style);else GRID_INT(minor_style);else GRID_INT(axes_style);
        else GRID_COLOR(major_color);else GRID_COLOR(minor_color);else GRID_COLOR(axes_color);
        else if(strcmp(word,"origin")==0)code=read_point(ip,value,&g->origin);
        else if(strcmp(word,"major_interval")==0)code=index_arg(ip,value,&g->major_interval);
        else code=fail(ip,"Unknown Native2D grid field");
#undef GRID_BOOL
#undef GRID_DOUBLE
#undef GRID_COLOR
#undef GRID_INT
        if(code!=TCL_OK)break;
    }
    Tcl_DictObjDone(&search);return code;
}
static Tcl_Obj *polar_obj(gx2d_polar_frame p) {
    Tcl_Obj *result=Tcl_NewDictObj();
#define PDOUBLE(k) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#k,-1),Tcl_NewDoubleObj(p.k))
#define PINT(k) Tcl_DictObjPut(NULL,result,Tcl_NewStringObj(#k,-1),Tcl_NewWideIntObj((Tcl_WideInt)p.k))
    Tcl_DictObjPut(NULL,result,Tcl_NewStringObj("origin",-1),point_obj(p.origin));
    PDOUBLE(theta_zero);PINT(clockwise);PINT(degrees);PDOUBLE(radius_min);PDOUBLE(radius_max);
    PDOUBLE(angle_min);PDOUBLE(angle_span);PDOUBLE(radial_spacing);PDOUBLE(angular_spacing);
    PINT(radial_major_interval);PINT(angular_major_interval);
#undef PDOUBLE
#undef PINT
    return result;
}
static int polar_read(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_polar_frame *p) {
    Tcl_DictSearch search;Tcl_Obj *key,*value;int done,code=TCL_OK;
    if(Tcl_DictObjFirst(ip,arg,&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
    for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){
        const char *word=Tcl_GetString(key);
#define PDOUBLE(k) if(strcmp(word,#k)==0)code=Tcl_GetDoubleFromObj(ip,value,&p->k)
#define PBOOL(k) if(strcmp(word,#k)==0)code=Tcl_GetBooleanFromObj(ip,value,&p->k)
        if(strcmp(word,"origin")==0)code=read_point(ip,value,&p->origin);
        else PDOUBLE(theta_zero);else PBOOL(clockwise);else PBOOL(degrees);
        else PDOUBLE(radius_min);else PDOUBLE(radius_max);else PDOUBLE(angle_min);else PDOUBLE(angle_span);
        else PDOUBLE(radial_spacing);else PDOUBLE(angular_spacing);
        else if(strcmp(word,"radial_major_interval")==0)code=index_arg(ip,value,&p->radial_major_interval);
        else if(strcmp(word,"angular_major_interval")==0)code=index_arg(ip,value,&p->angular_major_interval);
        else code=fail(ip,"Unknown Native2D polar field");
#undef PDOUBLE
#undef PBOOL
        if(code!=TCL_OK)break;
    }
    Tcl_DictObjDone(&search);return code;
}
static int coordinate_mode_read(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_coordinate_mode *mode) {
    const char *word=Tcl_GetString(arg);
    if(strcmp(word,"cartesian")==0)*mode=GX2D_CARTESIAN;
    else if(strcmp(word,"polar")==0)*mode=GX2D_POLAR;
    else return fail(ip,"Coordinate mode must be cartesian or experimental polar");
    return TCL_OK;
}
static Tcl_Obj *style_obj(gx2d_style s) {
    Tcl_Obj *out=Tcl_NewDictObj();
#define STYLE_INT(k) Tcl_DictObjPut(NULL,out,Tcl_NewStringObj(#k,-1),Tcl_NewWideIntObj((Tcl_WideInt)s.k))
#define STYLE_DOUBLE(k) Tcl_DictObjPut(NULL,out,Tcl_NewStringObj(#k,-1),Tcl_NewDoubleObj(s.k))
    STYLE_INT(visible);STYLE_INT(selectable);STYLE_INT(selected);STYLE_INT(locked);STYLE_INT(layer);STYLE_INT(order);
    STYLE_INT(line_style);STYLE_INT(marker);STYLE_DOUBLE(line_width);
    Tcl_DictObjPut(NULL,out,Tcl_NewStringObj("color",-1),color_obj((gx2d_color){s.red,s.green,s.blue,s.opacity}));
#undef STYLE_INT
#undef STYLE_DOUBLE
    return out;
}
static int style_read(Tcl_Interp *ip,Tcl_Obj *arg,gx2d_style *s) {
    Tcl_DictSearch search;Tcl_Obj *key,*value;int done,code=TCL_OK;
    if(Tcl_DictObjFirst(ip,arg,&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
    for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){
        const char *word=Tcl_GetString(key);
#define SBOOL(k) if(strcmp(word,#k)==0)code=Tcl_GetBooleanFromObj(ip,value,&s->k)
        SBOOL(visible);else SBOOL(selectable);else SBOOL(selected);else SBOOL(locked);
        else if(strcmp(word,"order")==0)code=Tcl_GetIntFromObj(ip,value,&s->order);
        else if(strcmp(word,"line_style")==0){int v;code=Tcl_GetIntFromObj(ip,value,&v);if(code==TCL_OK)s->line_style=(gx2d_line_style)v;}
        else if(strcmp(word,"marker")==0){int v;code=Tcl_GetIntFromObj(ip,value,&v);if(code==TCL_OK)s->marker=(gx2d_marker)v;}
        else if(strcmp(word,"line_width")==0)code=Tcl_GetDoubleFromObj(ip,value,&s->line_width);
        else if(strcmp(word,"layer")==0){Tcl_WideInt v;code=Tcl_GetWideIntFromObj(ip,value,&v);if(code==TCL_OK){if(v<0)code=fail(ip,"Layer ID must be nonnegative");else s->layer=(gx2d_id)v;}}
        else if(strcmp(word,"color")==0){gx2d_color c;code=read_color(ip,value,&c);if(code==TCL_OK){s->red=c.red;s->green=c.green;s->blue=c.blue;s->opacity=c.alpha;}}
        else code=fail(ip,"Unknown Native2D object style field");
#undef SBOOL
        if(code!=TCL_OK)break;
    }
    Tcl_DictObjDone(&search);return code;
}
#include "gx2d_tcl_columns.h"
static int read_object_ids(Tcl_Interp *ip,Tcl_Obj *value,gx2d_id **ids,size_t *count) {
    Tcl_Obj **items;int n,i;
    if(Tcl_ListObjGetElements(ip,value,&n,&items)!=TCL_OK||n<1||n>65536)
        return fail(ip,"Object list must contain 1..65536 IDs");
    *ids=(gx2d_id *)malloc((size_t)n*sizeof(**ids));if(!*ids)return fail(ip,"Out of memory");
    for(i=0;i<n;++i)if(object_id(ip,items[i],&(*ids)[i])!=TCL_OK){free(*ids);*ids=NULL;return TCL_ERROR;}
    *count=(size_t)n;return TCL_OK;
}
static int read_affine(Tcl_Interp *ip,Tcl_Obj *value,double m[6]) {
    Tcl_Obj **items;int n,i;
    if(Tcl_ListObjGetElements(ip,value,&n,&items)!=TCL_OK||n!=6)return fail(ip,"Affine matrix needs six values {a b c d tx ty}");
    for(i=0;i<6;++i)if(Tcl_GetDoubleFromObj(ip,items[i],&m[i])!=TCL_OK)return TCL_ERROR;
    return TCL_OK;
}
static Tcl_Obj *id_list_obj(Tcl_Interp *ip,const gx2d_id *ids,size_t count) {
    size_t i;Tcl_Obj *result=Tcl_NewListObj(0,NULL);
    for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj((Tcl_WideInt)ids[i]));
    return result;
}

#include "gx2d_parts_tcl.inc"
#include "gx2d_sketch_tcl.inc"
#include "gx2d_constraints_tcl.inc"
#include "gx2d_interaction_tcl.inc"
#include "gx2d_sketch_solver_tcl.inc"
#include "gx2d_construction_tcl.inc"
#include "gx2d_measurements_tcl.inc"
#include "gx2d_identity_tcl.inc"
#include "gx2d_collections_tcl.inc"
#include "gx2d_view_state_tcl.inc"
#include "gx2d_reference_images_tcl.inc"
#include "gx2d_image_roi_tcl.inc"

static int command(ClientData data, Tcl_Interp *ip, int argc, Tcl_Obj *const argv[]) {
    bridge *b = (bridge *)data;
    const char *op;
    scene_node *node;
    gx2d_id id;
    size_t count, i;
    Tcl_Obj *result;
    if (argc < 2) return fail(ip, "Usage: core operation ?arguments?");
    op = Tcl_GetString(argv[1]);
    if (strcmp(op, "api_info") == 0) {
        if(argc!=2)return fail(ip,"Usage: core api_info");
        Tcl_SetObjResult(ip,Tcl_NewStringObj("api_id NATIVE2D_API_v1 api_version 1 engine gx2d capabilities {path_validate image_local_roi native_cell_field native_virtual_grid native_cairo_surface native_cairo_export axis_presentation stable_constituent_identity independent_part_direction truthful_composition_traversal compound_subentities retained_network_nodes network_subentity_constraints atomic_dimension_batch multi_object_semantic_selection polygon_region_selection retained_straight_path ordered_path_vertices retained_path_join_split retained_spline_tangents calibrated_reference_images scene_preview_views atomic_symmetric_construction atomic_attached_construction semantic_point_connectivity retained_component_solver graphical_dimensions driven_dimensions local_sketch_rank relationship_hit_regions retained_control_descriptors epoch_checked_references canvas_construction selection_constraint_compatibility atomic_constraint_driving native_viewport_clip defining_control_snap atomic_presentation_snapshots native_selection_sets native_layer_lifecycle native_identity_attributes parent_linked_fragments topology_epoch structured_scientific_measurements exact_supported_projection extended_constraint_lifecycle constraint_diagnostics native_constraint_enforcement rectangular_circular_series retained_sketch exact_sketch_evaluation paged_sketch_sampling coordinate_rescale exact_vertex_snap gizmo_snap_translation gizmo rotation_transaction pivot flat_group_lifecycle affine_objects copy_reflect endpoint_frame point_frame point_distance bridge_c0_c1 bounded_spline_range native_spline_object selection_replace selection_state selection_paged device_point_hit bounded_compare drag_active aspect requested_view direction_marker grid background polar display_sample numeric_pack numeric_companions numeric_row_audit numeric_gaps binary_points bounded_points object_sample render_lod curve_render object_style fit_selected}",-1));
        return TCL_OK;
    }
    if (strcmp(op, "scene") == 0) {
        if (argc != 2) return fail(ip, "Usage: core scene");
        node = (scene_node *)calloc(1, sizeof(*node));
        if (!node) return fail(ip, "Out of memory");
        node->scene = gx2d_create();
        if (!node->scene) { free(node); return fail(ip, "Out of memory"); }
        node->serial = ++b->next; node->next = b->head; b->head = node;
        Tcl_SetObjResult(ip, Tcl_NewWideIntObj((Tcl_WideInt)node->serial));
        return TCL_OK;
    }
    if (argc < 3) return fail(ip, "Native 2D scene handle is required");
    node = lookup(b, ip, argv[2]);
    if (!node) return TCL_ERROR;
    if(strcmp(op,"append_binary_xy")==0||strcmp(op,"append_binary_xy_gaps")==0||strcmp(op,"append_binary_pointset")==0||strcmp(op,"append_binary_point")==0){numeric_column column;int bytes,stride=2,x=0,y=1,gapsMode=strcmp(op,"append_binary_xy_gaps")==0,pointsetMode=strcmp(op,"append_binary_pointset")==0,pointMode=strcmp(op,"append_binary_point")==0,gapBytes;unsigned char *gaps=NULL;Tcl_WideInt existing;gx2d_point *points;gx2d_status code;
        if((gapsMode?argc!=6:(argc!=5&&argc!=8))||Tcl_GetWideIntFromObj(ip,argv[3],&existing)!=TCL_OK||existing<0)return fail(ip,"Usage: core append_binary_xy scene object_or_zero float64_le_interleaved ?stride x_column y_column? | append_binary_xy_gaps scene object_or_zero float64_le_interleaved break_before_bytes");
        if(argc==8&&(Tcl_GetIntFromObj(ip,argv[5],&stride)!=TCL_OK||Tcl_GetIntFromObj(ip,argv[6],&x)!=TCL_OK||Tcl_GetIntFromObj(ip,argv[7],&y)!=TCL_OK||stride<2||stride>32||x<0||x>=stride||y<0||y>=stride||x==y))return fail(ip,"Invalid binary XY column layout");
        memset(&column,0,sizeof(column));column.bytes=Tcl_GetByteArrayFromObj(argv[4],&bytes);column.width=8;column.kind=1;
        if(bytes<stride*8||bytes%(stride*8)||bytes>65536*stride*8)return fail(ip,"Binary XY chunk needs 1..65536 complete rows");
        count=(size_t)bytes/(stride*8);
        if(gapsMode){gaps=Tcl_GetByteArrayFromObj(argv[5],&gapBytes);if((size_t)gapBytes!=count)return fail(ip,"Gap mask must contain one byte per XY row");for(i=0;i<count;++i)if(gaps[i]>1)return fail(ip,"Gap bytes must be zero or one");}
        points=(gx2d_point *)malloc(count*sizeof(*points));if(!points)return fail(ip,"Out of memory");
        for(i=0;i<count;++i)if(numeric_column_value(ip,&column,stride*i+x,&points[i].x)!=TCL_OK||numeric_column_value(ip,&column,stride*i+y,&points[i].y)!=TCL_OK){free(points);return TCL_ERROR;}
        id=(gx2d_id)existing;
        if(existing&&pointsetMode){gx2d_kind kind;code=gx2d_kind_of(node->scene,id,&kind);if(code!=GX2D_OK||kind!=GX2D_POINT_SET){free(points);return code!=GX2D_OK?status(ip,code):fail(ip,"Binary point-set append requires a point-set object");}}
        code=existing?(gapsMode?gx2d_append_points_with_gaps(node->scene,id,points,gaps,count):gx2d_append_points(node->scene,id,points,count)):gx2d_add_geometry(node->scene,pointsetMode?GX2D_POINT_SET:pointMode?GX2D_POINT_OBJECT:GX2D_CURVE,points,count,&id);
        if(code==GX2D_OK&&!existing&&gapsMode){size_t *cuts=(size_t *)malloc(count*sizeof(*cuts)),n=0;if(!cuts){gx2d_delete_object(node->scene,id);free(points);return fail(ip,"Out of memory");}for(i=1;i<count;++i)if(gaps[i])cuts[n++]=i-1;code=gx2d_set_breaks(node->scene,id,cuts,n);free(cuts);if(code!=GX2D_OK)gx2d_delete_object(node->scene,id);}
        free(points);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;
    }
    if(strcmp(op,"polar_binary")==0){numeric_column column;int bytes;gx2d_point *points,*polar;unsigned char *packed,*defined;size_t j;gx2d_status code;Tcl_Obj *reply;
        if(argc!=4)return fail(ip,"Usage: core polar_binary scene float64_le_xy");
        memset(&column,0,sizeof column);column.bytes=Tcl_GetByteArrayFromObj(argv[3],&bytes);column.width=8;column.count=(size_t)bytes/8;column.kind=1;
        if(bytes<16||bytes%16||bytes>1048576)return fail(ip,"Polar conversion requires1..65536 complete XY rows");
        count=(size_t)bytes/16;points=(gx2d_point *)malloc(count*sizeof(*points));polar=(gx2d_point *)malloc(count*sizeof(*polar));packed=(unsigned char *)malloc(count*16);defined=(unsigned char *)malloc(count);
        if(!points||!polar||!packed||!defined){free(points);free(polar);free(packed);free(defined);return fail(ip,"Out of memory");}
        for(i=0;i<count;++i)if(numeric_column_value(ip,&column,2*i,&points[i].x)!=TCL_OK||numeric_column_value(ip,&column,2*i+1,&points[i].y)!=TCL_OK){free(points);free(polar);free(packed);free(defined);return TCL_ERROR;}
        code=gx2d_cartesian_to_polar_many(node->scene,points,count,polar,defined);free(points);
        if(code!=GX2D_OK){free(polar);free(packed);free(defined);return status(ip,code);}
        for(i=0;i<count;++i){double values[2]={polar[i].y,polar[i].x};for(j=0;j<2;++j){uint64_t bits;size_t k;memcpy(&bits,values+j,8);for(k=0;k<8;++k)packed[16*i+8*j+k]=(unsigned char)(bits>>(8*k));}}
        reply=Tcl_NewDictObj();Tcl_DictObjPut(ip,reply,Tcl_NewStringObj("theta_r",-1),Tcl_NewByteArrayObj(packed,(int)(count*16)));Tcl_DictObjPut(ip,reply,Tcl_NewStringObj("angle_defined",-1),Tcl_NewByteArrayObj(defined,(int)count));Tcl_SetObjResult(ip,reply);
        free(polar);free(packed);free(defined);return TCL_OK;
    }
    if(strcmp(op,"numeric_pack")==0||strcmp(op,"numeric_pack_columns")==0){numeric_column x,y,mapping,parameter,companions[8];Tcl_Obj *companion_names[8],*companion_result=NULL;int companion_mode=strcmp(op,"numeric_pack_columns")==0,companion_count=0,has_parameter=(!companion_mode&&argc==8);gx2d_point *points;uint64_t *rows=NULL;size_t base,finite=0;unsigned char *xy,*packed_rows,*packed_parameter=NULL;gx2d_status code;
        if((companion_mode?argc!=8:(argc!=7&&argc!=8))||index_arg(ip,argv[6],&base)!=TCL_OK)return fail(ip,"Usage: core numeric_pack scene x_column y_column source_rows_or_empty row_base ?parameter_column?; numeric_pack_columns requires a companion dictionary");
        if(numeric_column_read(ip,argv[3],&x)!=TCL_OK||numeric_column_read(ip,argv[4],&y)!=TCL_OK)return TCL_ERROR;
        if(x.count!=y.count)return fail(ip,"Numeric XY columns have different row counts");
        if(has_parameter&&(numeric_column_read(ip,argv[7],&parameter)!=TCL_OK||parameter.count!=x.count))return fail(ip,"Numeric parameter column must align with XY rows");
        if(companion_mode){Tcl_DictSearch search;Tcl_Obj *key,*value;int done,n;
            if(Tcl_DictObjSize(ip,argv[7],&n)!=TCL_OK||n<1||n>8)return fail(ip,"Numeric packing requires one to eight named companion columns");
            if(Tcl_DictObjFirst(ip,argv[7],&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
            while(!done){
                if(Tcl_GetCharLength(key)<1||Tcl_GetCharLength(key)>128||numeric_column_read(ip,value,&companions[companion_count])!=TCL_OK||companions[companion_count].count!=x.count){Tcl_DictObjDone(&search);return fail(ip,"Numeric companion identity/shape must match the XY rows");}
                companion_names[companion_count++]=key;Tcl_DictObjNext(&search,&key,&value,&done);
            }
            Tcl_DictObjDone(&search);
        }
        if(Tcl_GetCharLength(argv[5])){
            if(numeric_column_read(ip,argv[5],&mapping)!=TCL_OK)return TCL_ERROR;
            if(mapping.count!=x.count)return fail(ip,"Numeric source-row mapping has a different row count");
            rows=(uint64_t *)calloc(x.count?x.count:1,sizeof(*rows));if(!rows)return fail(ip,"Out of memory");
            for(i=0;i<x.count;++i)if(numeric_column_row(ip,&mapping,i,&rows[i])!=TCL_OK){free(rows);return TCL_ERROR;}
        }
        points=(gx2d_point *)calloc(x.count?x.count:1,sizeof(*points));xy=(unsigned char *)malloc(x.count?x.count*16:1);packed_rows=(unsigned char *)malloc(x.count?x.count*8:1);
        if(!points||!xy||!packed_rows){free(points);free(xy);free(packed_rows);free(rows);return fail(ip,"Out of memory");}
        for(i=0;i<x.count;++i)if(numeric_column_value(ip,&x,i,&points[i].x)!=TCL_OK||numeric_column_value(ip,&y,i,&points[i].y)!=TCL_OK){free(points);free(xy);free(packed_rows);free(rows);return TCL_ERROR;}
        code=gx2d_numeric_pack(points,rows,base,x.count,xy,x.count*16,packed_rows,x.count*8,&finite);
        free(points);
        if(code!=GX2D_OK){free(xy);free(packed_rows);free(rows);return status(ip,code);}
        if(has_parameter){size_t k=0,j;packed_parameter=(unsigned char *)malloc(finite?finite*8:1);
            if(!packed_parameter){free(xy);free(packed_rows);free(rows);return fail(ip,"Out of memory");}
            for(i=0;i<x.count;++i){double px,py,p;uint64_t bits;
                numeric_column_value(ip,&x,i,&px);numeric_column_value(ip,&y,i,&py);
                if(!isfinite(px)||!isfinite(py))continue;
                if(numeric_column_value(ip,&parameter,i,&p)!=TCL_OK||!isfinite(p)){free(xy);free(packed_rows);free(rows);free(packed_parameter);return fail(ip,"Numeric parameters must be finite for every finite XY pair");}
                memcpy(&bits,&p,8);for(j=0;j<8;++j)packed_parameter[8*k+j]=(unsigned char)(bits>>(8*j));++k;
            }
        }
        if(companion_mode){int c;companion_result=Tcl_NewDictObj();Tcl_IncrRefCount(companion_result);
            for(c=0;c<companion_count;++c){size_t k=0,j;unsigned char *bytes=(unsigned char *)malloc(finite?finite*8:1);
                if(!bytes){free(xy);free(packed_rows);free(rows);Tcl_DecrRefCount(companion_result);return fail(ip,"Out of memory");}
                for(i=0;i<x.count;++i){double px,py,v;uint64_t bits;
                    numeric_column_value(ip,&x,i,&px);numeric_column_value(ip,&y,i,&py);
                    if(!isfinite(px)||!isfinite(py))continue;
                    /* Missing companion values stay aligned for consumer policy. */
                    if(numeric_column_value(ip,&companions[c],i,&v)!=TCL_OK){free(bytes);free(xy);free(packed_rows);free(rows);Tcl_DecrRefCount(companion_result);return TCL_ERROR;}
                    memcpy(&bits,&v,8);for(j=0;j<8;++j)bytes[8*k+j]=(unsigned char)(bits>>(8*j));++k;
                }
                Tcl_DictObjPut(ip,companion_result,companion_names[c],Tcl_NewByteArrayObj(bytes,(int)(finite*8)));free(bytes);
            }
        }
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("row_count",-1),Tcl_NewWideIntObj((Tcl_WideInt)finite));
        if(companion_result){Tcl_DictObjPut(ip,result,Tcl_NewStringObj("companions",-1),companion_result);Tcl_DecrRefCount(companion_result);}
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("xy",-1),Tcl_NewByteArrayObj(xy,(int)(finite*16)));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("source_rows",-1),Tcl_NewByteArrayObj(packed_rows,(int)(finite*8)));
        if(packed_parameter){Tcl_DictObjPut(ip,result,Tcl_NewStringObj("parameter",-1),Tcl_NewByteArrayObj(packed_parameter,(int)(finite*8)));free(packed_parameter);}
        {unsigned char *gaps=(unsigned char *)calloc(finite?finite:1,1);size_t k=0,missing=0;int previous=1;
         Tcl_Obj *input_rows,*nonfinite_rows;unsigned char *input_bytes,*nonfinite_bytes;
         if(!gaps){free(xy);free(packed_rows);free(rows);return fail(ip,"Out of memory");}
         input_rows=Tcl_NewByteArrayObj(NULL,(int)(x.count*8));nonfinite_rows=Tcl_NewByteArrayObj(NULL,(int)((x.count-finite)*8));
         Tcl_DictObjPut(ip,result,Tcl_NewStringObj("input_source_rows",-1),input_rows);
         Tcl_DictObjPut(ip,result,Tcl_NewStringObj("nonfinite_source_rows",-1),nonfinite_rows);
         input_bytes=Tcl_GetByteArrayFromObj(input_rows,NULL);nonfinite_bytes=Tcl_GetByteArrayFromObj(nonfinite_rows,NULL);
         /* Re-read the bounded input to preserve missing-pair gap semantics. */
         for(i=0;i<x.count;++i){double px,py;uint64_t row=rows?rows[i]:(uint64_t)base+(uint64_t)i;size_t j;
             numeric_column_value(ip,&x,i,&px);numeric_column_value(ip,&y,i,&py);
             for(j=0;j<8;++j)input_bytes[8*i+j]=(unsigned char)(row>>(8*j));
             if(isfinite(px)&&isfinite(py)){gaps[k++]=(unsigned char)!previous;previous=1;}
             else {for(j=0;j<8;++j)nonfinite_bytes[8*missing+j]=(unsigned char)(row>>(8*j));++missing;previous=0;}
         }
         Tcl_DictObjPut(ip,result,Tcl_NewStringObj("break_before",-1),Tcl_NewByteArrayObj(gaps,(int)finite));
         Tcl_DictObjPut(ip,result,Tcl_NewStringObj("ends_finite",-1),Tcl_NewBooleanObj(previous));free(gaps);}
        free(xy);free(packed_rows);free(rows);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"sample_begin")==0){size_t total,budget,base=0;
        if(argc!=5&&argc!=6)return fail(ip,"Usage: core sample_begin scene logical_rows budget ?source_row_base?");
        if(node->display)return fail(ip,"A Native2D display sample is already open");
        if(index_arg(ip,argv[3],&total)!=TCL_OK||index_arg(ip,argv[4],&budget)!=TCL_OK||(argc==6&&index_arg(ip,argv[5],&base)!=TCL_OK))return TCL_ERROR;
        if(!total||budget<6||budget>65536)return fail(ip,"Native2D display sample needs positive rows and budget 6..65536");
        if(total>(size_t)INT64_MAX||base>(size_t)INT64_MAX-total)return fail(ip,"Source-row mapping exceeds the signed 64-bit nonnegative range");
        node->display=gx2d_display_begin(total,budget,(uint64_t)base);
        if(!node->display)return fail(ip,"Cannot allocate Native2D display sample");return TCL_OK;
    }
    if(strcmp(op,"sample_cancel")==0){if(argc!=3)return fail(ip,"Usage: core sample_cancel scene");
        gx2d_display_destroy(node->display);node->display=NULL;return TCL_OK;}
    if(strcmp(op,"sample_push")==0){numeric_column x,y,mapping;gx2d_point *points;uint64_t *rows=NULL;size_t start;gx2d_status code;
        if((argc!=6&&argc!=7)||index_arg(ip,argv[3],&start)!=TCL_OK)return fail(ip,"Usage: core sample_push scene start x_column y_column ?source_rows_column?");
        if(!node->display)return fail(ip,"No Native2D display sample is open");
        if(numeric_column_read(ip,argv[4],&x)!=TCL_OK||numeric_column_read(ip,argv[5],&y)!=TCL_OK)return TCL_ERROR;
        if(x.count!=y.count)return fail(ip,"Native2D XY columns have different row counts");
        if(argc==7){
            if(numeric_column_read(ip,argv[6],&mapping)!=TCL_OK)return TCL_ERROR;
            if(mapping.count!=x.count)return fail(ip,"Source-row mapping has a different row count");
            rows=(uint64_t *)calloc(x.count?x.count:1,sizeof(*rows));if(!rows)return fail(ip,"Out of memory");
            for(i=0;i<x.count;++i)if(numeric_column_row(ip,&mapping,i,&rows[i])!=TCL_OK){free(rows);return TCL_ERROR;}
        }
        points=(gx2d_point *)calloc(x.count?x.count:1,sizeof(*points));if(!points){free(rows);return fail(ip,"Out of memory");}
        for(i=0;i<x.count;++i)if(numeric_column_value(ip,&x,i,&points[i].x)!=TCL_OK||numeric_column_value(ip,&y,i,&points[i].y)!=TCL_OK){free(points);free(rows);return TCL_ERROR;}
        code=gx2d_display_push_rows(node->display,start,points,rows,x.count);free(points);free(rows);return status(ip,code);
    }
    if(strcmp(op,"sample_finish")==0){gx2d_point *points;uint64_t *rows;size_t finite,ncuts,*cuts=NULL;gx2d_rect bounds;gx2d_status code;Tcl_Obj *mapped,*breaks;
        if(argc!=3||!node->display)return fail(ip,"No Native2D display sample is open");
        code=gx2d_display_result(node->display,NULL,NULL,0,&count,&finite,&bounds);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        if(count<2)return fail(ip,"A display curve needs at least two finite source rows");
        code=gx2d_display_breaks(node->display,NULL,0,&ncuts);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        if(ncuts){cuts=(size_t *)calloc(ncuts,sizeof(*cuts));if(!cuts)return fail(ip,"Out of memory");
            code=gx2d_display_breaks(node->display,cuts,ncuts,&ncuts);if(code!=GX2D_OK){free(cuts);return status(ip,code);}}
        points=(gx2d_point *)calloc(count,sizeof(*points));rows=(uint64_t *)calloc(count,sizeof(*rows));
        if(!points||!rows){free(points);free(rows);free(cuts);return fail(ip,"Out of memory");}
        code=gx2d_display_result(node->display,points,rows,count,&count,&finite,&bounds);
        if(code==GX2D_OK)code=gx2d_add_geometry(node->scene,GX2D_CURVE,points,count,&id);
        free(points);if(code!=GX2D_OK){free(rows);free(cuts);return status(ip,code);}
        if(ncuts){code=gx2d_set_breaks(node->scene,id,cuts,ncuts);if(code!=GX2D_OK){gx2d_delete_object(node->scene,id);free(rows);free(cuts);return status(ip,code);}}
        mapped=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,mapped,Tcl_NewWideIntObj((Tcl_WideInt)rows[i]));free(rows);
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("object",-1),Tcl_NewWideIntObj((Tcl_WideInt)id));
        breaks=Tcl_NewListObj(0,NULL);for(i=0;i<ncuts;++i)Tcl_ListObjAppendElement(ip,breaks,Tcl_NewWideIntObj((Tcl_WideInt)cuts[i]));free(cuts);
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("breaks",-1),breaks);
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("source_rows",-1),mapped);
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("finite_rows",-1),Tcl_NewWideIntObj((Tcl_WideInt)finite));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("display_rows",-1),Tcl_NewWideIntObj((Tcl_WideInt)count));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("full_bounds",-1),rect_obj(bounds));
        gx2d_display_destroy(node->display);node->display=NULL;Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"presentation")==0) {
        gx2d_grid grid;gx2d_color background;gx2d_aspect_mode aspect;gx2d_polar_frame polar;gx2d_coordinate_mode coordinate_mode;
        Tcl_DictSearch search;Tcl_Obj *key,*value;int done,code=TCL_OK;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core presentation scene ?changes?");
        if(status(ip,gx2d_grid_get(node->scene,&grid))!=TCL_OK||status(ip,gx2d_background_get(node->scene,&background))!=TCL_OK||status(ip,gx2d_view_aspect_get(node->scene,&aspect))!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_polar_frame_get(node->scene,&polar))!=TCL_OK||status(ip,gx2d_coordinate_mode_get(node->scene,&coordinate_mode))!=TCL_OK)return TCL_ERROR;
        if(argc==4){
            if(Tcl_DictObjFirst(ip,argv[3],&search,&key,&value,&done)!=TCL_OK)return TCL_ERROR;
            for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){
                const char *word=Tcl_GetString(key);
                if(strcmp(word,"grid")==0)code=grid_read(ip,value,&grid);
                else if(strcmp(word,"polar")==0)code=polar_read(ip,value,&polar);
                else if(strcmp(word,"coordinate_mode")==0)code=coordinate_mode_read(ip,value,&coordinate_mode);
                else if(strcmp(word,"background")==0)code=read_color(ip,value,&background);
                else if(strcmp(word,"aspect")==0){const char *mode=Tcl_GetString(value);
                    if(strcmp(mode,"auto")==0)aspect=GX2D_ASPECT_AUTO;else if(strcmp(mode,"xy_equal")==0)aspect=GX2D_ASPECT_XY_EQUAL;else code=fail(ip,"Aspect must be auto or xy_equal");}
                else code=fail(ip,"Unknown Native2D presentation field");
                if(code!=TCL_OK)break;
            }
            Tcl_DictObjDone(&search);if(code!=TCL_OK)return code;
            if(status(ip,gx2d_presentation_frame_set(node->scene,&grid,background,aspect,&polar,coordinate_mode))!=TCL_OK)return TCL_ERROR;
        }
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("grid",-1),grid_obj(grid));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("background",-1),color_obj(background));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("aspect",-1),Tcl_NewStringObj(aspect==GX2D_ASPECT_XY_EQUAL?"xy_equal":"auto",-1));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("polar",-1),polar_obj(polar));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("coordinate_mode",-1),Tcl_NewStringObj(coordinate_mode==GX2D_POLAR?"polar":"cartesian",-1));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"polar")==0){
        gx2d_polar_frame frame;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core polar scene ?changes?");
        if(status(ip,gx2d_polar_frame_get(node->scene,&frame))!=TCL_OK)return TCL_ERROR;
        if(argc==4){if(polar_read(ip,argv[3],&frame)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_polar_frame_set(node->scene,&frame))!=TCL_OK)return TCL_ERROR;}
        Tcl_SetObjResult(ip,polar_obj(frame));return TCL_OK;
    }
    if(strcmp(op,"coordinate_mode")==0){
        gx2d_coordinate_mode mode;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core coordinate_mode scene ?cartesian|polar?");
        if(argc==4){if(coordinate_mode_read(ip,argv[3],&mode)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_coordinate_mode_set(node->scene,mode))!=TCL_OK)return TCL_ERROR;}
        if(status(ip,gx2d_coordinate_mode_get(node->scene,&mode))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewStringObj(mode==GX2D_POLAR?"polar":"cartesian",-1));return TCL_OK;
    }
    if(strcmp(op,"to_polar")==0||strcmp(op,"from_polar")==0||strcmp(op,"polar_snap")==0){
        gx2d_point p,q;int axes;gx2d_status code;
        if(argc!=(strcmp(op,"polar_snap")==0?5:4)||read_point(ip,argv[3],&p)!=TCL_OK)return fail(ip,"Usage: core to_polar|from_polar scene point; polar_snap scene point axes");
        if(strcmp(op,"polar_snap")==0){if(Tcl_GetIntFromObj(ip,argv[4],&axes)!=TCL_OK)return TCL_ERROR;code=gx2d_polar_snap(node->scene,p,(unsigned)axes,&q);}
        else code=strcmp(op,"to_polar")==0?gx2d_cartesian_to_polar(node->scene,p,&q):gx2d_polar_to_cartesian(node->scene,p,&q);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,point_obj(q));return TCL_OK;
    }
    if(strcmp(op,"angle_normalize")==0){
        double value,normalized;int degrees;
        if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[3],&value)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[4],&degrees)!=TCL_OK)return fail(ip,"Usage: core angle_normalize scene angle degrees");
        if(status(ip,gx2d_angle_normalize(value,degrees,&normalized))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewDoubleObj(normalized));return TCL_OK;
    }
    if(strcmp(op,"background")==0) {
        gx2d_color color;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core background scene ?rgba?");
        if(argc==4){if(read_color(ip,argv[3],&color)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_background_set(node->scene,color))!=TCL_OK)return TCL_ERROR;}
        if(status(ip,gx2d_background_get(node->scene,&color))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,color_obj(color));return TCL_OK;
    }
    if(strcmp(op,"grid")==0) {
        gx2d_grid grid;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core grid scene ?changes?");
        if(status(ip,gx2d_grid_get(node->scene,&grid))!=TCL_OK)return TCL_ERROR;
        if(argc==4){if(grid_read(ip,argv[3],&grid)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_grid_set(node->scene,&grid))!=TCL_OK)return TCL_ERROR;}
        Tcl_SetObjResult(ip,grid_obj(grid));return TCL_OK;
    }
    if(strcmp(op,"render_grid")==0) {
        gx2d_grid_segment *lines;size_t count,j;
        if(argc!=3)return fail(ip,"Usage: core render_grid scene");
        lines=(gx2d_grid_segment *)calloc(2048,sizeof(*lines));if(!lines)return fail(ip,"Out of memory");
        if(status(ip,gx2d_grid_render(node->scene,lines,2048,&count))!=TCL_OK){free(lines);return TCL_ERROR;}
        result=Tcl_NewListObj(0,NULL);
        for(j=0;j<count;++j){Tcl_Obj *line=Tcl_NewDictObj();
            Tcl_DictObjPut(ip,line,Tcl_NewStringObj("a",-1),point_obj(lines[j].a));
            Tcl_DictObjPut(ip,line,Tcl_NewStringObj("b",-1),point_obj(lines[j].b));
            Tcl_DictObjPut(ip,line,Tcl_NewStringObj("classification",-1),Tcl_NewIntObj(lines[j].classification));
            Tcl_ListObjAppendElement(ip,result,line);}
        free(lines);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"grid_snap")==0||strcmp(op,"grid_snap_delta")==0) {
        gx2d_point point,delta,snapped;int axes;gx2d_status code;
        if(argc!=(strcmp(op,"grid_snap")==0?5:6))return fail(ip,"Usage: core grid_snap|grid_snap_delta scene point ?delta? axes");
        if(read_point(ip,argv[3],&point)!=TCL_OK||Tcl_GetIntFromObj(ip,argv[argc-1],&axes)!=TCL_OK)return TCL_ERROR;
        if(strcmp(op,"grid_snap")==0)code=gx2d_grid_snap(node->scene,point,(unsigned)axes,&snapped);
        else {if(read_point(ip,argv[4],&delta)!=TCL_OK)return TCL_ERROR;code=gx2d_grid_translation(node->scene,point,delta,(unsigned)axes,&snapped);}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,point_obj(snapped));return TCL_OK;
    }
    if(strcmp(op,"direction_marker")==0) {
        gx2d_direction_marker marker;
        if(argc!=4&&argc!=5)return fail(ip,"Usage: core direction_marker scene curve ?changes?");
        if(object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_direction_marker_get(node->scene,id,&marker))!=TCL_OK)return TCL_ERROR;
        if(argc==5){if(marker_read(ip,argv[4],&marker)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_direction_marker_set(node->scene,id,&marker))!=TCL_OK)return TCL_ERROR;}
        Tcl_SetObjResult(ip,marker_obj(marker));return TCL_OK;
    }
    if(strcmp(op,"marker_attach")==0) {
        gx2d_id target;
        if(argc!=5)return fail(ip,"Usage: core marker_attach scene from_curve to_curve");
        if(object_id(ip,argv[3],&id)!=TCL_OK||object_id(ip,argv[4],&target)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_direction_marker_attach(node->scene,id,target));
    }
    if(strcmp(op,"marker_order")==0) {
        size_t total,start,n,j,*indices;gx2d_status code;
        if(argc!=7)return fail(ip,"Usage: core marker_order scene curve total start count");
        if(object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&total)!=TCL_OK||index_arg(ip,argv[5],&start)!=TCL_OK||index_arg(ip,argv[6],&n)!=TCL_OK)return TCL_ERROR;
        if(n>65536)return fail(ip,"Direction ordering chunks are bounded to 65536 indices");
        indices=(size_t *)calloc(n?n:1,sizeof(*indices));if(!indices)return fail(ip,"Out of memory");
        code=gx2d_direction_marker_order(node->scene,id,total,start,n,indices);
        if(status(ip,code)!=TCL_OK){free(indices);return TCL_ERROR;}
        result=Tcl_NewListObj(0,NULL);for(j=0;j<n;++j)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj((Tcl_WideInt)indices[j]));
        free(indices);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"render_marker")==0) {
        gx2d_direction_primitives p;gx2d_status code;
        if(argc!=4)return fail(ip,"Usage: core render_marker scene curve");
        if(object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
        code=gx2d_direction_marker_render(node->scene,id,&p);if(code==GX2D_NOT_FOUND)return TCL_OK;
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();
#define MARKER_POINT(k) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(#k,-1),point_obj(p.k))
        MARKER_POINT(anchor);MARKER_POINT(tail);MARKER_POINT(tip);MARKER_POINT(head_left);MARKER_POINT(head_right);
#undef MARKER_POINT
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("bounds",-1),rect_obj(p.bounds));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("fraction",-1),Tcl_NewDoubleObj(p.fraction));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"marker_hit")==0||strcmp(op,"marker_place")==0) {
        gx2d_point point;double tolerance,fraction;int hit;
        if(argc!=(strcmp(op,"marker_hit")==0?6:5))return fail(ip,"Usage: core marker_hit|marker_place scene curve device_point ?tolerance_px?");
        if(object_id(ip,argv[3],&id)!=TCL_OK||read_point(ip,argv[4],&point)!=TCL_OK)return TCL_ERROR;
        if(strcmp(op,"marker_hit")==0){
            if(Tcl_GetDoubleFromObj(ip,argv[5],&tolerance)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_direction_marker_hit(node->scene,id,point,tolerance,&hit))!=TCL_OK)return TCL_ERROR;
            Tcl_SetObjResult(ip,Tcl_NewBooleanObj(hit));
        }else {
            if(status(ip,gx2d_direction_marker_place(node->scene,id,point,&fraction))!=TCL_OK)return TCL_ERROR;
            Tcl_SetObjResult(ip,Tcl_NewDoubleObj(fraction));
        }
        return TCL_OK;
    }
    if (strcmp(op, "destroy") == 0) {
        scene_node **link = &b->head;
        if (argc != 3) return fail(ip, "Usage: core destroy scene");
        while (*link != node) link = &(*link)->next;
        *link = node->next;gx2d_display_destroy(node->display); gx2d_destroy(node->scene);if(node->axis_presentation)Tcl_DecrRefCount(node->axis_presentation); free(node);
        return TCL_OK;
    }
    if (strcmp(op, "add") == 0 || strcmp(op, "pointset") == 0 || strcmp(op,"point")==0) {
        gx2d_point *points = NULL;
        gx2d_status code;
        if (argc != 4) return fail(ip, "Usage: core add|pointset scene points");
        if (point_list(ip, argv[3], &points, &count) != TCL_OK) return TCL_ERROR;
        code = gx2d_add_geometry(node->scene, strcmp(op, "add") == 0 ? GX2D_CURVE : strcmp(op,"point")==0?GX2D_POINT_OBJECT:GX2D_POINT_SET, points, count, &id);
        free(points);
        if (status(ip, code) != TCL_OK) return TCL_ERROR;
        Tcl_SetObjResult(ip, Tcl_NewWideIntObj((Tcl_WideInt)id));
        return TCL_OK;
    }
    if (strcmp(op, "clear") == 0) {
        if (argc != 3) return fail(ip, "Usage: core clear scene");
        return status(ip, gx2d_clear_selection(node->scene));
    }
    if (strcmp(op, "drag_active") == 0) {
        int active;
        if (argc != 3) return fail(ip, "Usage: core drag_active scene");
        if (status(ip, gx2d_drag_is_active(node->scene, &active)) != TCL_OK) return TCL_ERROR;
        Tcl_SetObjResult(ip, Tcl_NewBooleanObj(active));return TCL_OK;
    }
    if (strcmp(op, "selection_replace") == 0 || strcmp(op, "selection_patch") == 0) {
        Tcl_Obj **items;int n,i,patch=strcmp(op,"selection_patch")==0;size_t *indices,start=0,page=0;gx2d_status code;
        if (argc != (patch?7:5)) return fail(ip,"Usage: core selection_replace scene object indices | selection_patch scene object start count indices");
        if (object_id(ip, argv[3], &id) != TCL_OK) return TCL_ERROR;
        if(patch&&(index_arg(ip,argv[4],&start)!=TCL_OK||index_arg(ip,argv[5],&page)!=TCL_OK||page>65536))return fail(ip,"Selection page must contain at most 65536 points");
        if (Tcl_ListObjGetElements(ip, argv[patch?6:4], &n, &items) != TCL_OK) return TCL_ERROR;
        if(patch&&n>65536)return fail(ip,"Selection page exceeds bounded limit");
        indices=(size_t *)calloc(n?n:1,sizeof(*indices));
        if(!indices)return fail(ip,"Out of memory");
        for(i=0;i<n;++i){Tcl_WideInt index;
            if(Tcl_GetWideIntFromObj(ip,items[i],&index)!=TCL_OK){free(indices);return TCL_ERROR;}
            if(index<0 || (Tcl_WideInt)(size_t)index!=index){free(indices);return fail(ip,"Invalid point index");}
            indices[i]=(size_t)index;
        }
        code=patch?gx2d_selection_patch_points(node->scene,id,start,page,indices,(size_t)n):gx2d_selection_replace_points(node->scene,id,indices,(size_t)n);free(indices);
        return status(ip,code);
    }
    if (strcmp(op, "ids") == 0) {
        gx2d_id *ids;
        if (argc != 3) return fail(ip, "Usage: core ids scene");
        if (status(ip, gx2d_object_ids(node->scene, NULL, 0, &count)) != TCL_OK) return TCL_ERROR;
        ids = (gx2d_id *)calloc(count ? count : 1, sizeof(*ids));
        if (!ids) return fail(ip, "Out of memory");
        if (status(ip, gx2d_object_ids(node->scene, ids, count, &count)) != TCL_OK) { free(ids); return TCL_ERROR; }
        result = Tcl_NewListObj(0, NULL);
        for (i = 0; i < count; ++i) Tcl_ListObjAppendElement(ip, result, Tcl_NewWideIntObj((Tcl_WideInt)ids[i]));
        free(ids); Tcl_SetObjResult(ip, result); return TCL_OK;
    }
    if (strcmp(op, "nearest") == 0) {
        gx2d_point point;
        gx2d_hit hit;
        double distance;
        gx2d_status code;
        if (argc != 5) return fail(ip, "Usage: core nearest scene {x y} max_distance");
        if (read_point(ip, argv[3], &point) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, argv[4], &distance) != TCL_OK) return TCL_ERROR;
        code = gx2d_nearest(node->scene, point, distance, &hit);
        if (code == GX2D_NOT_FOUND) return TCL_OK;
        if (status(ip, code) != TCL_OK) return TCL_ERROR;
        Tcl_SetObjResult(ip, hit_obj(hit));
        return TCL_OK;
    }
    if(strcmp(op,"selection_state")==0){gx2d_selection_region *regions;unsigned char *manual;size_t start,nregions;int base;Tcl_Obj *regionList,*manualList;gx2d_status code;
        if(argc!=6||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&start)!=TCL_OK||index_arg(ip,argv[5],&count)!=TCL_OK||count>65536)return fail(ip,"Usage: core selection_state scene object start count (count <= 65536)");
        if(status(ip,gx2d_selection_regions(node->scene,id,NULL,0,&nregions,&base))!=TCL_OK)return TCL_ERROR;
        if(nregions>65536)return fail(ip,"Selection regions exceed the bounded descriptor limit");
        regions=(gx2d_selection_region *)calloc(nregions?nregions:1,sizeof(*regions));manual=(unsigned char *)calloc(count?count:1,1);
        if(!regions||!manual){free(regions);free(manual);return fail(ip,"Out of memory");}
        code=gx2d_selection_regions(node->scene,id,regions,nregions,&nregions,&base);
        if(code==GX2D_OK)code=gx2d_selection_manual_range(node->scene,id,start,count,manual,count);
        if(code!=GX2D_OK){free(regions);free(manual);return status(ip,code);}
        regionList=Tcl_NewListObj(0,NULL);manualList=Tcl_NewListObj(0,NULL);
        for(i=0;i<nregions;++i){Tcl_Obj *r=Tcl_NewDictObj();Tcl_DictObjPut(ip,r,Tcl_NewStringObj("bounds",-1),rect_obj(regions[i].bounds));Tcl_DictObjPut(ip,r,Tcl_NewStringObj("mode",-1),Tcl_NewStringObj(regions[i].mode==GX2D_SELECT_ADD?"add":"subtract",-1));Tcl_ListObjAppendElement(ip,regionList,r);}
        for(i=0;i<count;++i)if(manual[i]){Tcl_Obj *v[2]={Tcl_NewWideIntObj((Tcl_WideInt)(start+i)),Tcl_NewIntObj(manual[i])};Tcl_ListObjAppendElement(ip,manualList,Tcl_NewListObj(2,v));}
        free(regions);free(manual);result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("base_selected",-1),Tcl_NewBooleanObj(base));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("regions",-1),regionList);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("manual",-1),manualList);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if (strcmp(op, "rect") == 0) {
        Tcl_Obj **xy;
        gx2d_rect rect;
        gx2d_select_mode mode;
        int n;
        if (argc != 5) return fail(ip, "Usage: core rect scene {x0 y0 x1 y1} replace|add|subtract");
        if (Tcl_ListObjGetElements(ip, argv[3], &n, &xy) != TCL_OK || n != 4 ||
            Tcl_GetDoubleFromObj(ip, xy[0], &rect.x0) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, xy[1], &rect.y0) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, xy[2], &rect.x1) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, xy[3], &rect.y1) != TCL_OK) return fail(ip, "Invalid Native 2D rectangle");
        if (read_mode(ip, argv[4], &mode) != TCL_OK) return TCL_ERROR;
        if (status(ip, gx2d_select_rect(node->scene, rect, mode, &id)) != TCL_OK) return TCL_ERROR;
        Tcl_SetObjResult(ip, Tcl_NewWideIntObj((Tcl_WideInt)id));
        return TCL_OK;
    }
    if(strcmp(op,"aspect")==0){gx2d_aspect_mode mode;
        if(argc==3){if(status(ip,gx2d_view_aspect_get(node->scene,&mode))!=TCL_OK)return TCL_ERROR;
            Tcl_SetObjResult(ip,Tcl_NewStringObj(mode==GX2D_ASPECT_AUTO?"auto":"xy_equal",-1));return TCL_OK;}
        if(argc!=4)return fail(ip,"Usage: core aspect scene ?auto|xy_equal?");
        if(strcmp(Tcl_GetString(argv[3]),"auto")==0)mode=GX2D_ASPECT_AUTO;
        else if(strcmp(Tcl_GetString(argv[3]),"xy_equal")==0)mode=GX2D_ASPECT_XY_EQUAL;
        else return fail(ip,"Aspect must be auto or xy_equal");
        return status(ip,gx2d_view_aspect_set(node->scene,mode));}
    if(strcmp(op,"view") == 0||strcmp(op,"view_requested")==0){gx2d_view v;Tcl_Obj **items;int n;
        if(argc==3){if(status(ip,strcmp(op,"view_requested")==0?gx2d_view_requested(node->scene,&v):gx2d_view_get(node->scene,&v))!=TCL_OK)return TCL_ERROR;
            items=(Tcl_Obj **)calloc(7,sizeof(*items));if(!items)return fail(ip,"Out of memory");
            items[0]=Tcl_NewDoubleObj(v.width);items[1]=Tcl_NewDoubleObj(v.height);
            items[2]=Tcl_NewDoubleObj(v.left);items[3]=Tcl_NewDoubleObj(v.top);
            items[4]=Tcl_NewDoubleObj(v.right);items[5]=Tcl_NewDoubleObj(v.bottom);items[6]=rect_obj(v.world);
            Tcl_SetObjResult(ip,Tcl_NewListObj(7,items));free(items);return TCL_OK;}
        if(strcmp(op,"view_requested")==0)return fail(ip,"view_requested is read-only");
        if(argc!=4||Tcl_ListObjGetElements(ip,argv[3],&n,&items)!=TCL_OK||n!=7)return fail(ip,"Usage: core view scene ?{width height left top right bottom {x0 y0 x1 y1}}?");
        if(Tcl_GetDoubleFromObj(ip,items[0],&v.width)!=TCL_OK||Tcl_GetDoubleFromObj(ip,items[1],&v.height)!=TCL_OK||
           Tcl_GetDoubleFromObj(ip,items[2],&v.left)!=TCL_OK||Tcl_GetDoubleFromObj(ip,items[3],&v.top)!=TCL_OK||
           Tcl_GetDoubleFromObj(ip,items[4],&v.right)!=TCL_OK||Tcl_GetDoubleFromObj(ip,items[5],&v.bottom)!=TCL_OK||
           read_rect(ip,items[6],&v.world)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_view_set(node->scene,&v));
    }
    if(strcmp(op,"scene_bounds")==0){gx2d_rect r;int selected=0;gx2d_status code;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core scene_bounds scene ?selected_only?");
        if(argc==4&&Tcl_GetBooleanFromObj(ip,argv[3],&selected)!=TCL_OK)return TCL_ERROR;
        code=gx2d_scene_bounds(node->scene,selected,&r);if(code==GX2D_NOT_FOUND)return TCL_OK;
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,rect_obj(r));return TCL_OK;}
    if(strcmp(op,"fit")==0){gx2d_id target=0;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core fit scene ?object?");
        if(argc==4&&object_id(ip,argv[3],&target)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_view_fit(node->scene,target));}
    if(strcmp(op,"fit_selected")==0){if(argc!=3)return fail(ip,"Usage: core fit_selected scene");return status(ip,gx2d_view_fit_selected(node->scene));}
    if(strcmp(op,"fit_bounds")==0){gx2d_rect bounds;if(argc!=4||read_rect(ip,argv[3],&bounds)!=TCL_OK)return fail(ip,"Usage: core fit_bounds scene bounds");return status(ip,gx2d_view_fit_bounds(node->scene,bounds));}
    if(strcmp(op,"world") == 0||strcmp(op,"device")==0){gx2d_point p,q;
        if(argc!=4||read_point(ip,argv[3],&p)!=TCL_OK)return TCL_ERROR;
        if(status(ip,strcmp(op,"world")==0?gx2d_device_to_world(node->scene,p,&q):gx2d_world_to_device(node->scene,p,&q))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,point_obj(q));return TCL_OK;}
    if(strcmp(op,"zoom")==0){double f;gx2d_point p;
        if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[3],&f)!=TCL_OK||read_point(ip,argv[4],&p)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_view_zoom(node->scene,f,p));}
    if(strcmp(op,"pan")==0){double x,y;
        if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[3],&x)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&y)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_view_pan(node->scene,x,y));}
    if(strcmp(op,"tolerance")==0){double p,x,y;Tcl_Obj *v[2];
        if(argc!=4||Tcl_GetDoubleFromObj(ip,argv[3],&p)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_pixel_tolerance(node->scene,p,&x,&y))!=TCL_OK)return TCL_ERROR;
        v[0]=Tcl_NewDoubleObj(x);v[1]=Tcl_NewDoubleObj(y);Tcl_SetObjResult(ip,Tcl_NewListObj(2,v));return TCL_OK;}
    if(strcmp(op,"concat")==0){Tcl_Obj **rows,**item;gx2d_id *ids;int *rev,*gap;int n,j,m;gx2d_status code;
        if(argc!=4||Tcl_ListObjGetElements(ip,argv[3],&n,&rows)!=TCL_OK||n<1)return fail(ip,"Usage: core concat scene {{object reverse ?break_before?} ...}");
        ids=(gx2d_id *)calloc((size_t)n,sizeof(*ids));rev=(int *)calloc((size_t)n,sizeof(*rev));gap=(int *)calloc((size_t)n,sizeof(*gap));
        if(!ids||!rev||!gap){free(ids);free(rev);free(gap);return fail(ip,"Out of memory");}
        for(j=0;j<n;++j){if(Tcl_ListObjGetElements(ip,rows[j],&m,&item)!=TCL_OK||(m!=2&&m!=3)||
            object_id(ip,item[0],&ids[j])!=TCL_OK||Tcl_GetBooleanFromObj(ip,item[1],&rev[j])!=TCL_OK||
            (m==3&&Tcl_GetBooleanFromObj(ip,item[2],&gap[j])!=TCL_OK)){free(ids);free(rev);free(gap);return TCL_ERROR;}}
        code=gx2d_concatenate_parts(node->scene,ids,rev,gap,(size_t)n,&id);free(ids);free(rev);free(gap);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;}
    if(strcmp(op,"compare_geometry")==0){gx2d_id reference,derived;size_t budget,i;gx2d_geometry_comparison summary;gx2d_residual *rows;gx2d_status code;Tcl_Obj *result,*records;
        if(argc!=6||object_id(ip,argv[3],&reference)!=TCL_OK||object_id(ip,argv[4],&derived)!=TCL_OK||index_arg(ip,argv[5],&budget)!=TCL_OK||budget<6||budget>4096)return fail(ip,"Usage: core compare_geometry scene reference derived sample_budget 6..4096");
        rows=(gx2d_residual *)calloc(budget,sizeof(*rows));if(!rows)return fail(ip,"Out of memory");code=gx2d_compare_geometry(node->scene,reference,derived,budget,&summary,rows,budget);if(code!=GX2D_OK){free(rows);return status(ip,code);}
        result=Tcl_NewDictObj();records=Tcl_NewListObj(0,NULL);
#define GCPUT(key,value) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(key,-1),value)
#define GCNUM(key) GCPUT(#key,Tcl_NewDoubleObj(summary.key))
#define GCBOOL(key) GCPUT(#key,Tcl_NewBooleanObj(summary.key))
        GCPUT("count",Tcl_NewWideIntObj((Tcl_WideInt)summary.count_a));GCPUT("count_a",Tcl_NewWideIntObj((Tcl_WideInt)summary.count_a));GCPUT("count_b",Tcl_NewWideIntObj((Tcl_WideInt)summary.count_b));GCPUT("max_index",Tcl_NewWideIntObj((Tcl_WideInt)summary.max_index));GCPUT("sample_budget",Tcl_NewWideIntObj((Tcl_WideInt)budget));
        GCNUM(max_absolute);GCNUM(mean_absolute);GCNUM(rmse);GCNUM(symmetric_rmse);GCNUM(hausdorff_sampled);GCNUM(length_difference);GCNUM(area_difference);GCNUM(closest_distance);
        GCBOOL(area_supported);GCBOOL(projection_exact_a);GCBOOL(projection_exact_b);GCBOOL(closest_exact);
        GCPUT("closest_a",point_obj(summary.closest_a));GCPUT("closest_b",point_obj(summary.closest_b));GCPUT("sampling_a",Tcl_NewStringObj(summary.sampling_a,-1));GCPUT("sampling_b",Tcl_NewStringObj(summary.sampling_b,-1));
        GCPUT("policy",Tcl_NewStringObj("bounded_scientific_native_samples; sampled_RMS_and_Hausdorff; gap_aware_sampled_path; exact_supported_target_projection_and_closest_pairs",-1));
        for(i=0;i<summary.count_a;++i){Tcl_Obj *values[5]={Tcl_NewDoubleObj(rows[i].position),Tcl_NewDoubleObj(rows[i].signed_residual),Tcl_NewDoubleObj(rows[i].absolute_residual),point_obj(rows[i].reference),point_obj(rows[i].derived)};Tcl_ListObjAppendElement(ip,records,Tcl_NewListObj(5,values));}
        GCPUT("rows",records);
#undef GCBOOL
#undef GCNUM
#undef GCPUT
        free(rows);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"compare")==0||strcmp(op,"compare_lod")==0){gx2d_id reference,derived;gx2d_compare_method method;gx2d_residual *rows;int bounded=strcmp(op,"compare_lod")==0;
        gx2d_residual_summary summary;gx2d_status code;Tcl_Obj *data,*record,*rowIds;uint64_t *indices=NULL;size_t budget=4096,returned,max_display=0;
        if(argc!=(bounded?7:6)||object_id(ip,argv[3],&reference)!=TCL_OK||object_id(ip,argv[4],&derived)!=TCL_OK)return fail(ip,"Usage: core compare scene reference derived x|path | compare_lod scene reference derived x|path budget");
        if(bounded&&(index_arg(ip,argv[6],&budget)!=TCL_OK||budget<6||budget>65536))return fail(ip,"Comparison display budget must be between 6 and 65536");
        if(strcmp(Tcl_GetString(argv[5]),"x")==0)method=GX2D_COMPARE_X;
        else if(strcmp(Tcl_GetString(argv[5]),"path")==0)method=GX2D_COMPARE_PATH;
        else return fail(ip,"Comparison method must be x or path");
        if(status(ip,gx2d_point_count(node->scene,reference,&count))!=TCL_OK)return TCL_ERROR;
        if(bounded){count=budget;indices=(uint64_t *)calloc(budget,sizeof(*indices));if(!indices)return fail(ip,"Out of memory");}
        rows=(gx2d_residual *)calloc(count?count:1,sizeof(*rows));if(!rows){free(indices);return fail(ip,"Out of memory");}
        code=bounded?gx2d_compare_curves_display(node->scene,reference,derived,method,budget,rows,indices,budget,&returned,&summary):gx2d_compare_curves(node->scene,reference,derived,method,rows,count,&summary);
        if(status(ip,code)!=TCL_OK){free(rows);free(indices);return TCL_ERROR;}
        if(!bounded)returned=summary.count;
        data=Tcl_NewListObj(0,NULL);rowIds=Tcl_NewListObj(0,NULL);for(i=0;i<returned;++i){Tcl_Obj *v[5];
            v[0]=Tcl_NewDoubleObj(rows[i].position);v[1]=Tcl_NewDoubleObj(rows[i].signed_residual);
            v[2]=Tcl_NewDoubleObj(rows[i].absolute_residual);v[3]=point_obj(rows[i].reference);v[4]=point_obj(rows[i].derived);
            if(bounded){Tcl_ListObjAppendElement(ip,rowIds,Tcl_NewWideIntObj((Tcl_WideInt)indices[i]));if(indices[i]==summary.max_index)max_display=i;}
            Tcl_ListObjAppendElement(ip,data,Tcl_NewListObj(5,v));}
        free(rows);free(indices);record=Tcl_NewDictObj();
#define PUT_COMPARE(key,value) Tcl_DictObjPut(ip,record,Tcl_NewStringObj(key,-1),value)
        PUT_COMPARE("rows",data);PUT_COMPARE("count",Tcl_NewWideIntObj((Tcl_WideInt)summary.count));
        PUT_COMPARE("max_index",Tcl_NewWideIntObj((Tcl_WideInt)(bounded?max_display:summary.max_index)));
        if(bounded){PUT_COMPARE("max_source_index",Tcl_NewWideIntObj((Tcl_WideInt)summary.max_index));PUT_COMPARE("row_indices",rowIds);PUT_COMPARE("display_rows",Tcl_NewWideIntObj((Tcl_WideInt)returned));PUT_COMPARE("display_is_scientific_data",Tcl_NewBooleanObj(0));}
        PUT_COMPARE("max_absolute",Tcl_NewDoubleObj(summary.max_absolute));
        PUT_COMPARE("mean_absolute",Tcl_NewDoubleObj(summary.mean_absolute));
        PUT_COMPARE("rmse",Tcl_NewDoubleObj(summary.rmse));
#undef PUT_COMPARE
        Tcl_SetObjResult(ip,record);return TCL_OK;}
    if(strcmp(op,"select_object")==0){gx2d_select_mode mode;
        if(argc!=5||object_id(ip,argv[3],&id)!=TCL_OK||read_mode(ip,argv[4],&mode)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_select_object(node->scene,id,mode));}
    if(strcmp(op,"drag_begin")==0||strcmp(op,"drag_commit")==0||strcmp(op,"drag_cancel")==0){
        if(argc!=3)return fail(ip,"Usage: core drag_begin|drag_commit|drag_cancel scene");
        return status(ip,strcmp(op,"drag_begin")==0?gx2d_drag_begin(node->scene):
            strcmp(op,"drag_commit")==0?gx2d_drag_commit(node->scene):gx2d_drag_cancel(node->scene));}
    if(strcmp(op,"drag_translate")==0||strcmp(op,"translate")==0){double x,y;
        if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[3],&x)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&y)!=TCL_OK)return TCL_ERROR;
        return status(ip,strcmp(op,"drag_translate")==0?gx2d_drag_translate(node->scene,x,y):gx2d_translate_selected(node->scene,x,y));}
    if(strcmp(op,"gizmo")==0) {
        gx2d_gizmo g;
        if(argc!=3&&argc!=4)return fail(ip,"Usage: core gizmo scene ?properties?");
        if(status(ip,gx2d_gizmo_get(node->scene,&g))!=TCL_OK)return TCL_ERROR;
        if(argc==4&&(gizmo_read(ip,argv[3],&g)!=TCL_OK||status(ip,gx2d_gizmo_set(node->scene,&g))!=TCL_OK))return TCL_ERROR;
        Tcl_SetObjResult(ip,gizmo_obj(g));return TCL_OK;
    }
    if(strcmp(op,"render_gizmo")==0) {
        gx2d_overlay_primitive items[64];size_t n;gx2d_status code;
        if(argc!=3)return fail(ip,"Usage: core render_gizmo scene");
        code=gx2d_gizmo_render(node->scene,items,64,&n);
        if(code==GX2D_NOT_FOUND){Tcl_SetObjResult(ip,Tcl_NewListObj(0,NULL));return TCL_OK;}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewListObj(0,NULL);
        for(i=0;i<n;++i) {
            Tcl_Obj *item=Tcl_NewDictObj();gx2d_overlay_primitive p=items[i];
            Tcl_DictObjPut(ip,item,Tcl_NewStringObj("kind",-1),Tcl_NewStringObj(p.kind==GX2D_OVERLAY_LINE?"line":p.kind==GX2D_OVERLAY_CIRCLE?"circle":"box",-1));
            Tcl_DictObjPut(ip,item,Tcl_NewStringObj("handle",-1),Tcl_NewStringObj(gizmo_handles[p.handle],-1));
            Tcl_DictObjPut(ip,item,Tcl_NewStringObj("a",-1),point_obj(p.a));Tcl_DictObjPut(ip,item,Tcl_NewStringObj("b",-1),point_obj(p.b));
            Tcl_DictObjPut(ip,item,Tcl_NewStringObj("color",-1),color_obj(p.color));Tcl_DictObjPut(ip,item,Tcl_NewStringObj("width",-1),Tcl_NewDoubleObj(p.width));
            Tcl_ListObjAppendElement(ip,result,item);
        }
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"gizmo_hit")==0) {
        gx2d_point device;double tolerance;gx2d_gizmo_handle handle;
        if(argc!=5||read_point(ip,argv[3],&device)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&tolerance)!=TCL_OK)return fail(ip,"Usage: core gizmo_hit scene device_point tolerance_px");
        if(status(ip,gx2d_gizmo_hit(node->scene,device,tolerance,&handle))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewStringObj(gizmo_handles[handle],-1));return TCL_OK;
    }
    if(strcmp(op,"gizmo_parameters")==0) {
        gx2d_point start,current;gx2d_gizmo_delta delta;size_t index;const char *handle;
        if(argc!=6||read_point(ip,argv[4],&start)!=TCL_OK||read_point(ip,argv[5],&current)!=TCL_OK)return fail(ip,"Usage: core gizmo_parameters scene handle start_device current_device");
        handle=Tcl_GetString(argv[3]);for(index=0;index<8&&strcmp(handle,gizmo_handles[index]);++index){}
        if(index==8)return fail(ip,"Unknown Native2D gizmo handle");
        if(status(ip,gx2d_gizmo_parameters(node->scene,(gx2d_gizmo_handle)index,start,current,&delta))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("pivot",-1),point_obj(delta.pivot));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("translation",-1),point_obj(delta.translation));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("world_point",-1),point_obj(delta.world_point));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("radians",-1),Tcl_NewDoubleObj(delta.radians));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"drag_rotate")==0||strcmp(op,"rotate")==0||strcmp(op,"rotate_degrees")==0) {
        gx2d_point pivot;double radians;
        if(argc!=5||read_point(ip,argv[3],&pivot)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&radians)!=TCL_OK)return fail(ip,"Usage: core drag_rotate|rotate|rotate_degrees scene world_pivot angle");
        if(strcmp(op,"rotate_degrees")==0)radians*=acos(-1.)/180;
        return status(ip,strcmp(op,"drag_rotate")==0?gx2d_drag_rotate(node->scene,pivot,radians):gx2d_rotate_selected(node->scene,pivot,radians));
    }
    if(strcmp(op,"group")==0) {
        gx2d_id *ids;size_t n;gx2d_status code;
        if(argc!=4||read_object_ids(ip,argv[3],&ids,&n)!=TCL_OK)return fail(ip,"Usage: core group scene object_ids");
        code=gx2d_add_group(node->scene,ids,n,&id);free(ids);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;
    }
    if(strcmp(op,"rotation_matrix_degrees")==0||strcmp(op,"scaling_matrix")==0) {
        gx2d_point pivot,scale;double m[6],degrees;Tcl_Obj *v[6];gx2d_status code;
        if(argc!=5||read_point(ip,argv[3],&pivot)!=TCL_OK)return fail(ip,"Usage: core rotation_matrix_degrees scene pivot degrees | scaling_matrix scene pivot {sx sy}");
        if(strcmp(op,"scaling_matrix")==0){if(read_point(ip,argv[4],&scale)!=TCL_OK)return TCL_ERROR;code=gx2d_scaling_matrix(pivot,scale,m);}
        else {if(Tcl_GetDoubleFromObj(ip,argv[4],&degrees)!=TCL_OK)return TCL_ERROR;code=gx2d_rotation_matrix(pivot,degrees*(acos(-1.)/180),m);}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        for(i=0;i<6;++i)v[i]=Tcl_NewDoubleObj(m[i]);Tcl_SetObjResult(ip,Tcl_NewListObj(6,v));return TCL_OK;
    }
    if(strcmp(op,"reflection_matrix")==0) {
        gx2d_point a,z;double m[6];Tcl_Obj *v[6];
        if(argc!=5||read_point(ip,argv[3],&a)!=TCL_OK||read_point(ip,argv[4],&z)!=TCL_OK)return fail(ip,"Usage: core reflection_matrix scene axis_a axis_b");
        if(status(ip,gx2d_reflection_matrix(a,z,m))!=TCL_OK)return TCL_ERROR;
        for(i=0;i<6;++i)v[i]=Tcl_NewDoubleObj(m[i]);Tcl_SetObjResult(ip,Tcl_NewListObj(6,v));return TCL_OK;
    }
    if(strcmp(op,"affine")==0||strcmp(op,"expand_objects")==0) {
        gx2d_id *input=NULL,*source=NULL,*output=NULL;size_t n,total;double m[6];int copy=0,expand=strcmp(op,"expand_objects")==0;gx2d_status code;
        if((expand?argc!=4:(argc!=5&&argc!=6))||read_object_ids(ip,argv[3],&input,&n)!=TCL_OK)return fail(ip,"Usage: core affine scene object_ids matrix ?copy? | expand_objects scene object_ids");
        if(!expand&&(read_affine(ip,argv[4],m)!=TCL_OK||(argc==6&&Tcl_GetBooleanFromObj(ip,argv[5],&copy)!=TCL_OK))){free(input);return TCL_ERROR;}
        code=gx2d_expand_objects(node->scene,input,n,NULL,0,&total);
        if(code!=GX2D_OK){free(input);return status(ip,code);}
        source=(gx2d_id *)malloc(total*sizeof(*source));output=(gx2d_id *)malloc(total*sizeof(*output));
        if(!source||!output){free(source);free(output);free(input);return fail(ip,"Out of memory");}
        code=gx2d_expand_objects(node->scene,input,n,source,total,&total);
        if(code==GX2D_OK&&!expand) {
            if(copy)code=gx2d_copy_affine_objects(node->scene,input,n,m,output,total,&total);
            else {code=gx2d_affine_objects(node->scene,input,n,m);memcpy(output,source,total*sizeof(*output));}
        }
        free(input);
        if(code!=GX2D_OK){free(source);free(output);return status(ip,code);}
        if(expand)result=id_list_obj(ip,source,total);
        else {
            result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("source_ids",-1),id_list_obj(ip,source,total));
            Tcl_DictObjPut(ip,result,Tcl_NewStringObj("object_ids",-1),id_list_obj(ip,output,total));
            Tcl_DictObjPut(ip,result,Tcl_NewStringObj("copy",-1),Tcl_NewBooleanObj(copy));
        }
        free(source);free(output);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"pivot")==0) {
        gx2d_pivot_mode mode;gx2d_point p={0,0};gx2d_status code;const char *word;
        static const char *names[]={"bounds","centroid","origin","custom"};
        if(argc<3||argc>5)return fail(ip,"Usage: core pivot scene ?bounds|centroid|origin|custom ?world_point??");
        if(argc>=4) {
            word=Tcl_GetString(argv[3]);
            for(i=0;i<4&&strcmp(word,names[i]);++i){}
            if(i==4)return fail(ip,"Pivot mode must be bounds, centroid, origin or custom");mode=(gx2d_pivot_mode)i;
            if((mode==GX2D_PIVOT_CUSTOM&&argc!=5)||(argc==5&&read_point(ip,argv[4],&p)!=TCL_OK))return fail(ip,"Custom pivot needs a finite world XY point");
            if(status(ip,gx2d_pivot_set(node->scene,mode,p))!=TCL_OK)return TCL_ERROR;
        }
        code=gx2d_pivot_get(node->scene,&mode,&p);
        if(code!=GX2D_OK&&code!=GX2D_NOT_FOUND)return status(ip,code);
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("mode",-1),Tcl_NewStringObj(names[mode],-1));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point",-1),code==GX2D_OK?point_obj(p):Tcl_NewListObj(0,NULL));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"distance")==0) {
        gx2d_point a,z;double value;
        if(argc!=5||read_point(ip,argv[3],&a)!=TCL_OK||read_point(ip,argv[4],&z)!=TCL_OK)
            return fail(ip,"Usage: core distance scene point_a point_b");
        if(status(ip,gx2d_point_distance(a,z,&value))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewDoubleObj(value));return TCL_OK;
    }
    if(strcmp(op,"rescale_coordinates")==0) {
        double factor;
        if(argc!=4||Tcl_GetDoubleFromObj(ip,argv[3],&factor)!=TCL_OK)return fail(ip,"Usage: core rescale_coordinates scene positive_factor");
        return status(ip,gx2d_scene_rescale_coordinates(node->scene,factor));
    }
    if(strcmp(op,"gizmo_snap_translation")==0) {
        gx2d_gizmo_handle handle;gx2d_point pivot,requested,translation;gx2d_hit hit;double radius;
        gx2d_id *excluded=NULL;size_t n=0;int endpoints,length,snapped;gx2d_status code;
        const char *word=argc>3?Tcl_GetString(argv[3]):"";
        handle=strcmp(word,"x")==0?GX2D_HANDLE_X:strcmp(word,"y")==0?GX2D_HANDLE_Y:strcmp(word,"free")==0?GX2D_HANDLE_FREE:GX2D_HANDLE_NONE;
        if(argc!=9||handle==GX2D_HANDLE_NONE||read_point(ip,argv[4],&pivot)!=TCL_OK||read_point(ip,argv[5],&requested)!=TCL_OK||
            Tcl_GetDoubleFromObj(ip,argv[6],&radius)!=TCL_OK||Tcl_ListObjLength(ip,argv[7],&length)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[8],&endpoints)!=TCL_OK)
            return fail(ip,"Usage: core gizmo_snap_translation scene x|y|free pivot requested_translation radius_px excluded_object_ids endpoints_only");
        if(length&&read_object_ids(ip,argv[7],&excluded,&n)!=TCL_OK)return TCL_ERROR;
        code=gx2d_gizmo_snap_translation(node->scene,handle,pivot,requested,radius,excluded,n,endpoints,&translation,&snapped,&hit);free(excluded);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;result=Tcl_NewDictObj();
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("translation",-1),point_obj(translation));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("snapped",-1),Tcl_NewBooleanObj(snapped));
        if(snapped)Tcl_DictObjPut(ip,result,Tcl_NewStringObj("target",-1),hit_obj(hit));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"scene_nearest_vertex")==0||strcmp(op,"scene_nearest_vertex_device")==0) {
        gx2d_point query;gx2d_hit hit;double radius;gx2d_id *excluded=NULL;size_t n=0;int endpoints,length;gx2d_status code;
        if(argc!=7||read_point(ip,argv[3],&query)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&radius)!=TCL_OK||
            Tcl_ListObjLength(ip,argv[5],&length)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[6],&endpoints)!=TCL_OK)
            return fail(ip,"Usage: core scene_nearest_vertex[_device] scene query radius excluded_object_ids endpoints_only");
        if(length&&read_object_ids(ip,argv[5],&excluded,&n)!=TCL_OK)return TCL_ERROR;
        for(size_t k=0;k<n;++k){gx2d_kind kind;code=gx2d_kind_of(node->scene,excluded[k],&kind);if(code!=GX2D_OK){free(excluded);return status(ip,code);}}
        code=strcmp(op,"scene_nearest_vertex_device")==0?
            gx2d_scene_nearest_vertex_device(node->scene,query,radius,excluded,n,endpoints,&hit):
            gx2d_scene_nearest_vertex(node->scene,query,radius,excluded,n,endpoints,&hit);
        free(excluded);if(code==GX2D_NOT_FOUND){Tcl_SetObjResult(ip,Tcl_NewDictObj());return TCL_OK;}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,hit_obj(hit));return TCL_OK;
    }
    if(strcmp(op,"bridge")==0) {
        gx2d_id a,z;gx2d_bridge_spec spec;gx2d_bridge_result receipt;
        int ra,rz,ia,iz;const char *kind;
        memset(&spec,0,sizeof(spec));
        if(argc!=12||object_id(ip,argv[3],&a)!=TCL_OK||object_id(ip,argv[4],&z)!=TCL_OK||
           index_arg(ip,argv[6],&spec.subdivisions)!=TCL_OK||
           Tcl_GetDoubleFromObj(ip,argv[7],&spec.tolerance)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[8],&ra)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[9],&rz)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[10],&ia)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[11],&iz)!=TCL_OK)
            return fail(ip,"Usage: core bridge scene start_curve end_curve straight|quadratic|cubic|smooth subdivisions tolerance reverse_start reverse_end spline_start spline_end");
        kind=Tcl_GetString(argv[5]);
        if(strcmp(kind,"straight")==0)spec.kind=GX2D_BRIDGE_STRAIGHT;
        else if(strcmp(kind,"quadratic")==0)spec.kind=GX2D_BRIDGE_QUADRATIC;
        else if(strcmp(kind,"cubic")==0)spec.kind=GX2D_BRIDGE_CUBIC;
        else if(strcmp(kind,"smooth")==0)spec.kind=GX2D_BRIDGE_HERMITE;
        else return fail(ip,"Bridge kind must be straight, quadratic, cubic or smooth");
        if(status(ip,gx2d_curve_endpoint_frame(node->scene,a,1,ra,ia,&spec.start))!=TCL_OK||
           status(ip,gx2d_curve_endpoint_frame(node->scene,z,0,rz,iz,&spec.end))!=TCL_OK||
           status(ip,gx2d_bridge_create(node->scene,&spec,&id,&receipt))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,bridge_result_obj(ip,id,kind,spec,receipt));return TCL_OK;
    }
    if(strcmp(op,"bridge_frames")==0) {
        gx2d_bridge_spec spec;gx2d_bridge_result receipt;const char *kind;
        memset(&spec,0,sizeof(spec));
        if(argc!=8||read_endpoint_frame(ip,argv[3],&spec.start)!=TCL_OK||
           read_endpoint_frame(ip,argv[4],&spec.end)!=TCL_OK||
           index_arg(ip,argv[6],&spec.subdivisions)!=TCL_OK||
           Tcl_GetDoubleFromObj(ip,argv[7],&spec.tolerance)!=TCL_OK)
            return fail(ip,"Usage: core bridge_frames scene start_frame end_frame straight|quadratic|cubic|smooth subdivisions tolerance");
        kind=Tcl_GetString(argv[5]);
        if(strcmp(kind,"straight")==0)spec.kind=GX2D_BRIDGE_STRAIGHT;
        else if(strcmp(kind,"quadratic")==0)spec.kind=GX2D_BRIDGE_QUADRATIC;
        else if(strcmp(kind,"cubic")==0)spec.kind=GX2D_BRIDGE_CUBIC;
        else if(strcmp(kind,"smooth")==0)spec.kind=GX2D_BRIDGE_HERMITE;
        else return fail(ip,"Bridge kind must be straight, quadratic, cubic or smooth");
        if(status(ip,gx2d_bridge_create(node->scene,&spec,&id,&receipt))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,bridge_result_obj(ip,id,kind,spec,receipt));return TCL_OK;
    }
    if(strcmp(op,"series")==0){gx2d_series_spec spec;gx2d_id *input=NULL,*objects=NULL,*sources=NULL;size_t n,total;gx2d_status code;Tcl_Obj *field=NULL;int value;
        memset(&spec,0,sizeof(spec));spec.rows=spec.columns=2;spec.positions=4;spec.spacing_x=spec.spacing_y=1;spec.angle_step=acos(-1.0)/2;spec.rotate_geometry=1;
        if(argc!=5||read_object_ids(ip,argv[3],&input,&n)!=TCL_OK)return fail(ip,"Usage: core series scene object_ids parameters");
#define SERIES_BOOL(key,member) if(Tcl_DictObjGet(ip,argv[4],Tcl_NewStringObj(key,-1),&field)!=TCL_OK)goto series_invalid; if(field){if(Tcl_GetBooleanFromObj(ip,field,&value)!=TCL_OK)goto series_invalid;spec.member=value;}
#define SERIES_SIZE(key,member) if(Tcl_DictObjGet(ip,argv[4],Tcl_NewStringObj(key,-1),&field)!=TCL_OK)goto series_invalid; if(field&&index_arg(ip,field,&spec.member)!=TCL_OK)goto series_invalid
#define SERIES_DOUBLE(key,member) if(Tcl_DictObjGet(ip,argv[4],Tcl_NewStringObj(key,-1),&field)!=TCL_OK)goto series_invalid; if(field&&Tcl_GetDoubleFromObj(ip,field,&spec.member)!=TCL_OK)goto series_invalid
        SERIES_BOOL("circular",circular);SERIES_BOOL("include_origin",include_origin);SERIES_BOOL("rotate_geometry",rotate_geometry);
        SERIES_SIZE("rows",rows);SERIES_SIZE("columns",columns);SERIES_SIZE("positions",positions);
        SERIES_DOUBLE("spacing_x",spacing_x);SERIES_DOUBLE("spacing_y",spacing_y);SERIES_DOUBLE("angle_step",angle_step);
#undef SERIES_BOOL
#undef SERIES_SIZE
#undef SERIES_DOUBLE
        if(Tcl_DictObjGet(ip,argv[4],Tcl_NewStringObj("pivot",-1),&field)!=TCL_OK)goto series_invalid;if(field&&read_point(ip,field,&spec.pivot)!=TCL_OK)goto series_invalid;
        code=gx2d_series_create(node->scene,input,n,&spec,NULL,NULL,0,&total);if(status(ip,code)!=TCL_OK)goto series_invalid;
        objects=(gx2d_id *)calloc(total,sizeof(*objects));sources=(gx2d_id *)calloc(total,sizeof(*sources));if(!objects||!sources){fail(ip,"Out of memory");goto series_invalid;}
        code=gx2d_series_create(node->scene,input,n,&spec,objects,sources,total,&total);free(input);input=NULL;
        if(status(ip,code)!=TCL_OK)goto series_invalid;
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("object_ids",-1),id_list_obj(ip,objects,total));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("source_ids",-1),id_list_obj(ip,sources,total));
        free(objects);free(sources);Tcl_SetObjResult(ip,result);return TCL_OK;
series_invalid:free(input);free(objects);free(sources);return TCL_ERROR;
    }
    if(strcmp(op,"axis_presentation")==0)return axis_presentation_command(node,ip,argc,argv);
    if(strcmp(op,"view_state")==0||strcmp(op,"view_state_rescale")==0)return view_state_command(node,ip,op,argc,argv);
    if(!strcmp(op,"path_vertices")||!strcmp(op,"path_split")||!strcmp(op,"path_join"))return path_command(node->scene,ip,op,argc,argv);
    if(!strncmp(op,"part_",5)||!strcmp(op,"composition_states")||!strcmp(op,"composition_traversal"))return part_command(node->scene,ip,op,argc,argv);
    if(!strncmp(op,"composition_",12))return composition_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"layer_",6)==0)return layer_command(node->scene,ip,op,argc,argv);
    if(!strcmp(op,"selection_set_apply")||!strcmp(op,"selection_set_restore")||!strcmp(op,"selection_set_bounds")||!strcmp(op,"selection_pick")||!strcmp(op,"selection_region"))return semantic_selection_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"selection_set_",14)==0)return selection_set_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"identity_",9)==0||strncmp(op,"fragment_",9)==0)return identity_command(node->scene,ip,op,argc,argv);
    if(strcmp(op,"measure")==0)return measurement_command(node->scene,ip,argc,argv);
    if(strncmp(op,"constraint_",11)==0)return constraint_command(node->scene,ip,op,argc,argv);
    if(strcmp(op,"symmetry_preview")==0||strcmp(op,"symmetry_construct")==0){
        int create=strcmp(op,"symmetry_construct")==0;gx2d_reference axis;gx2d_sketch_definition d,mirrored;gx2d_point *owned=NULL;size_t samples=257;
        if(argc!=(create?6:5)||reference_read(ip,argv[3],&axis)!=TCL_OK||(create&&index_arg(ip,argv[5],&samples)!=TCL_OK)||sketch_read(ip,argv[4],&d,&owned)!=TCL_OK)return TCL_ERROR;
        gx2d_status code;Tcl_Obj *result=Tcl_NewDictObj();
        if(create){gx2d_id ids[3];code=gx2d_symmetry_construct(node->scene,&axis,&d,samples,ids);if(code==GX2D_OK){Tcl_DictObjPut(ip,result,Tcl_NewStringObj("source",-1),Tcl_NewWideIntObj(ids[0]));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("mirror",-1),Tcl_NewWideIntObj(ids[1]));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("relationship",-1),Tcl_NewWideIntObj(ids[2]));}}
        else {code=gx2d_symmetry_preview(node->scene,&axis,&d,&mirrored);if(code==GX2D_OK)Tcl_DictObjPut(ip,result,Tcl_NewStringObj("definition",-1),sketch_obj(ip,&mirrored));}
        sketch_read_release(&d,owned);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"path_validate")==0){
        int n,i,closed;Tcl_Obj **rows;double length,area;gx2d_point *points;gx2d_status code;
        if(argc!=5||Tcl_ListObjGetElements(ip,argv[3],&n,&rows)!=TCL_OK||n<3||n>4096||Tcl_GetBooleanFromObj(ip,argv[4],&closed)!=TCL_OK)return fail(ip,"Path validation requires 3–4096 ordered points and a closed flag");
        points=malloc((size_t)n*sizeof(*points));if(!points)return fail(ip,"Path validation allocation failed");
        for(i=0;i<n;++i){int m;Tcl_Obj **xy;if(Tcl_ListObjGetElements(ip,rows[i],&m,&xy)!=TCL_OK||m!=2||Tcl_GetDoubleFromObj(ip,xy[0],&points[i].x)!=TCL_OK||Tcl_GetDoubleFromObj(ip,xy[1],&points[i].y)!=TCL_OK){free(points);return fail(ip,"Invalid path coordinate");}}
        code=gx2d_path_validate(points,(size_t)n,closed,&length,&area);free(points);
        if(code!=GX2D_OK)return fail(ip,"Degenerate, self-intersecting, branched or unsupported ordered path");
        Tcl_Obj *result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("length",-1),Tcl_NewDoubleObj(length));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("signed_area",-1),Tcl_NewDoubleObj(area));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("closed",-1),Tcl_NewBooleanObj(closed));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strncmp(op,"image_roi_",10)==0)return image_roi_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"image_",6)==0)return image_command(node->scene,ip,op,argc,argv);
    if(strcmp(op,"preview_view")==0){
        int fit;double width,height,padding;gx2d_view v;
        if(argc!=7||Tcl_GetBooleanFromObj(ip,argv[3],&fit)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&width)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&height)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[6],&padding)!=TCL_OK)return fail(ip,"Usage: core preview_view scene fit width height padding");
        if(status(ip,gx2d_preview_view(node->scene,fit,width,height,padding,&v))!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *items[7]={Tcl_NewDoubleObj(v.width),Tcl_NewDoubleObj(v.height),Tcl_NewDoubleObj(v.left),Tcl_NewDoubleObj(v.top),Tcl_NewDoubleObj(v.right),Tcl_NewDoubleObj(v.bottom),rect_obj(v.world)};Tcl_SetObjResult(ip,Tcl_NewListObj(7,items));return TCL_OK;
    }
    if(strcmp(op,"spline_tangent")==0){
        size_t knot;int incoming,explicit_state,reset=0;gx2d_point anchor,handle;
        if((argc!=6&&argc!=7&&argc!=8)||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&knot)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[5],&incoming)!=TCL_OK)return fail(ip,"Usage: core spline_tangent scene object knot incoming ?world_handle ?reset??");
        if(argc>=7){if(read_point(ip,argv[6],&handle)!=TCL_OK||(argc==8&&Tcl_GetBooleanFromObj(ip,argv[7],&reset)!=TCL_OK))return TCL_ERROR;if(status(ip,gx2d_spline_tangent_edit(node->scene,id,knot,incoming,handle,reset))!=TCL_OK)return TCL_ERROR;}
        if(status(ip,gx2d_spline_tangent_get(node->scene,id,knot,incoming,&anchor,&handle,&explicit_state))!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("anchor",-1),point_obj(anchor));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point",-1),point_obj(handle));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("explicit",-1),Tcl_NewBooleanObj(explicit_state));gx2d_sketch_definition d;gx2d_sketch_get_definition(node->scene,id,&d);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("definition",-1),sketch_obj(ip,&d));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"selection_control_sources")) {
        gx2d_id id;size_t index,refs[65536],count;
        if(argc!=5||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: core selection_control_sources scene object reference_index");
        if(status(ip,gx2d_selection_control_sources(node->scene,id,index,refs,65536,&count))!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *result=Tcl_NewListObj(0,NULL);for(size_t k=0;k<count;k++)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj(refs[k]));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"spline_span_to_line")) {
        gx2d_id id;size_t index;
        if(argc!=5||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: core spline_span_to_line scene object reference_index");
        if(status(ip,gx2d_spline_span_to_line(node->scene,id,index))!=TCL_OK)return TCL_ERROR;
        gx2d_sketch_definition d;gx2d_sketch_get_definition(node->scene,id,&d);Tcl_SetObjResult(ip,sketch_obj(ip,&d));return TCL_OK;
    }
    if(!strcmp(op,"selection_definition")||!strcmp(op,"spline_line_plan")) {
        gx2d_id id;size_t index,controls[65536],count=0,part=0,spans=0;gx2d_sketch_definition *d=NULL;
        if(argc!=5||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: core selection_definition|spline_line_plan scene object reference_index");
        gx2d_status code=!strcmp(op,"selection_definition")?gx2d_selection_definition_owned(node->scene,id,index,&d):gx2d_spline_line_plan(node->scene,id,index,&d,controls,65536,&count,&part,&spans);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *result=sketch_obj(ip,d);
        if(!strcmp(op,"spline_line_plan")) {Tcl_Obj *plan=Tcl_NewDictObj(),*map=Tcl_NewListObj(0,NULL);for(size_t k=0;k<count;k++)Tcl_ListObjAppendElement(ip,map,Tcl_NewWideIntObj(controls[k]));
            Tcl_DictObjPut(ip,plan,Tcl_NewStringObj("definition",-1),result);Tcl_DictObjPut(ip,plan,Tcl_NewStringObj("control_map",-1),map);Tcl_DictObjPut(ip,plan,Tcl_NewStringObj("split_part",-1),Tcl_NewWideIntObj(part));Tcl_DictObjPut(ip,plan,Tcl_NewStringObj("span_count",-1),Tcl_NewWideIntObj(spans));result=plan;}
        gx2d_control_definition_release(d);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strncmp(op,"sketch_",7)==0&&strcmp(op,"sketch_create")&&strcmp(op,"sketch_update")&&strcmp(op,"sketch_explode")&&strcmp(op,"sketch_definition")&&strcmp(op,"sketch_evaluate")&&strcmp(op,"sketch_bounds")&&strcmp(op,"sketch_sample")&&strcmp(op,"sketch_materialize")&&strcmp(op,"sketch_validate"))return sketch_solver_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"interaction_",12)==0)return interaction_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"construction_",13)==0)return construction_command(node->scene,ip,op,argc,argv);
    if(strncmp(op,"sketch_",7)==0)return sketch_command(node->scene,ip,op,argc,argv);
    if (argc < 4 || object_id(ip, argv[3], &id) != TCL_OK) return TCL_ERROR;
    if(strcmp(op,"group_members")==0) {
        gx2d_id *ids;gx2d_status code;
        if(argc!=4)return fail(ip,"Usage: core group_members scene group");
        if(status(ip,gx2d_group_members(node->scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;
        ids=(gx2d_id *)malloc((count?count:1)*sizeof(*ids));if(!ids)return fail(ip,"Out of memory");
        code=gx2d_group_members(node->scene,id,ids,count,&count);
        if(code!=GX2D_OK){free(ids);return status(ip,code);}result=id_list_obj(ip,ids,count);free(ids);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"group_add")==0||strcmp(op,"group_remove")==0||strcmp(op,"group_contains")==0) {
        gx2d_id member;int yes;
        if(argc!=5||object_id(ip,argv[4],&member)!=TCL_OK)return fail(ip,"Usage: core group_add|group_remove|group_contains scene group member");
        if(strcmp(op,"group_contains")==0){if(status(ip,gx2d_group_contains(node->scene,id,member,&yes))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewBooleanObj(yes));return TCL_OK;}
        return status(ip,strcmp(op,"group_add")==0?gx2d_group_add_member(node->scene,id,member):gx2d_group_remove_member(node->scene,id,member));
    }
    if(strcmp(op,"ungroup")==0) {if(argc!=4)return fail(ip,"Usage: core ungroup scene group");return status(ip,gx2d_ungroup(node->scene,id));}
    if(strcmp(op,"point_frame")==0) {
        int incoming,reverse,interpolation;size_t index;gx2d_endpoint_frame frame;
        if(argc!=8||index_arg(ip,argv[4],&index)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[5],&incoming)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[6],&reverse)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[7],&interpolation)!=TCL_OK)
            return fail(ip,"Usage: core point_frame scene curve point_index incoming reverse spline");
        if(status(ip,gx2d_curve_point_frame(node->scene,id,index,incoming,reverse,interpolation,&frame))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,endpoint_frame_obj(frame));return TCL_OK;
    }
    if(strcmp(op,"spline_object")==0) {
        size_t per;gx2d_id output;
        if(argc!=5||index_arg(ip,argv[4],&per)!=TCL_OK)return fail(ip,"Usage: core spline_object scene curve subdivisions");
        if(status(ip,gx2d_sample_spline_object(node->scene,id,per,&output))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)output));return TCL_OK;
    }
    if(strcmp(op,"spline_range")==0) {
        size_t first,segments,per,n;gx2d_point *points;gx2d_status code;
        if(argc!=7||index_arg(ip,argv[4],&first)!=TCL_OK||index_arg(ip,argv[5],&segments)!=TCL_OK||
           index_arg(ip,argv[6],&per)!=TCL_OK)return fail(ip,"Usage: core spline_range scene curve first_segment segment_count subdivisions");
        if(status(ip,gx2d_sample_spline_range(node->scene,id,first,segments,per,NULL,0,&n))!=TCL_OK)return TCL_ERROR;
        if(n>65536)return fail(ip,"Spline point-list output is bounded to 65536 points; use spline_object and paged/resource APIs");
        points=(gx2d_point *)malloc(n*sizeof(*points));if(!points)return fail(ip,"Out of memory");
        code=gx2d_sample_spline_range(node->scene,id,first,segments,per,points,n,&n);
        if(code!=GX2D_OK){free(points);return status(ip,code);}
        result=Tcl_NewListObj(0,NULL);for(i=0;i<n;++i)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));
        free(points);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"endpoint_frame")==0) {
        int end,reverse,interpolation;gx2d_endpoint_frame frame;
        if(argc!=7||Tcl_GetBooleanFromObj(ip,argv[4],&end)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[5],&reverse)!=TCL_OK||
           Tcl_GetBooleanFromObj(ip,argv[6],&interpolation)!=TCL_OK)
            return fail(ip,"Usage: core endpoint_frame scene curve end reverse spline");
        if(status(ip,gx2d_curve_endpoint_frame(node->scene,id,end,reverse,interpolation,&frame))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,endpoint_frame_obj(frame));return TCL_OK;
    }
    if (strcmp(op, "remove_rect") == 0) {
        if (argc != 4) return fail(ip, "Usage: core remove_rect scene block");
        return status(ip, gx2d_remove_rect(node->scene, id));
    }
    if (strcmp(op, "delete") == 0) {
        if (argc != 4) return fail(ip, "Usage: core delete scene object");
        return status(ip, gx2d_delete_object(node->scene, id));
    }
    if (strcmp(op, "visible") == 0) {
        gx2d_style style;
        int visible;
        if (argc != 5) return fail(ip, "Usage: core visible scene object boolean");
        if (Tcl_GetBooleanFromObj(ip, argv[4], &visible) != TCL_OK) return TCL_ERROR;
        if (status(ip, gx2d_get_style(node->scene, id, &style)) != TCL_OK) return TCL_ERROR;
        style.visible = visible;
        return status(ip, gx2d_set_style(node->scene, id, &style));
    }
    if (strcmp(op, "hit") == 0 || strcmp(op,"hit_point_device")==0) {
        gx2d_point point;
        gx2d_hit hit;
        double tolerance;
        gx2d_status code;
        if (argc != 6) return fail(ip, "Usage: core hit scene object {x y} tolerance");
        if (read_point(ip, argv[4], &point) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, argv[5], &tolerance) != TCL_OK) return TCL_ERROR;
        code = strcmp(op,"hit_point_device")==0?gx2d_hit_point_device(node->scene,id,point,tolerance,&hit):gx2d_hit_test(node->scene, id, point, tolerance, &hit);
        if (code == GX2D_NOT_FOUND) return TCL_OK;
        if (status(ip, code) != TCL_OK) return TCL_ERROR;
        Tcl_SetObjResult(ip, hit_obj(hit));
        return TCL_OK;
    }
    if (strcmp(op, "points") == 0 || strcmp(op, "export") == 0) {
        gx2d_point *points;
        gx2d_status code;
        if (argc != 4) return fail(ip, "Usage: core points|export scene object");
        code = strcmp(op, "points") == 0 ? gx2d_get_points(node->scene, id, NULL, 0, &count) : gx2d_export_selected(node->scene, id, NULL, 0, &count);
        if (status(ip, code) != TCL_OK) return TCL_ERROR;
        points = (gx2d_point *)calloc(count ? count : 1, sizeof(*points));
        if (!points) return fail(ip, "Out of memory");
        code = strcmp(op, "points") == 0 ? gx2d_get_points(node->scene, id, points, count, &count) : gx2d_export_selected(node->scene, id, points, count, &count);
        if (status(ip, code) != TCL_OK) { free(points); return TCL_ERROR; }
        result = Tcl_NewListObj(0, NULL);
        for (i = 0; i < count; ++i) Tcl_ListObjAppendElement(ip, result, point_obj(points[i]));
        free(points); Tcl_SetObjResult(ip, result); return TCL_OK;
    }
    if(strcmp(op,"selection_flags")==0){Tcl_Obj **items;int n,chosen;size_t index;
        if(argc!=5||Tcl_ListObjGetElements(ip,argv[4],&n,&items)!=TCL_OK||n>65536)return fail(ip,"Usage: core selection_flags scene object indices (at most 65536)");
        result=Tcl_NewListObj(0,NULL);
        for(i=0;i<(size_t)n;++i){if(index_arg(ip,items[i],&index)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_point_selected(node->scene,id,index,&chosen))!=TCL_OK)return TCL_ERROR;Tcl_ListObjAppendElement(ip,result,Tcl_NewBooleanObj(chosen));}
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if (strcmp(op, "selected") == 0 || strcmp(op,"selection_summary")==0) {
        int selected,summary=strcmp(op,"selection_summary")==0;size_t start=0,page=0,total=0,first=SIZE_MAX,last=SIZE_MAX;
        if (argc != 4 && (!summary&&argc!=6)) return fail(ip, "Usage: core selected scene object ?start count? | selection_summary scene object");
        if (status(ip, gx2d_point_count(node->scene, id, &count)) != TCL_OK) return TCL_ERROR;
        page=count;
        if(argc==6){if(index_arg(ip,argv[4],&start)!=TCL_OK||index_arg(ip,argv[5],&page)!=TCL_OK||page>65536||start>count||page>count-start)return fail(ip,"Selection page is outside its bounded range");}
        result = summary?Tcl_NewDictObj():Tcl_NewListObj(0, NULL);
        for (i = start; i < start+page; ++i) {
            if (status(ip, gx2d_point_selected(node->scene, id, i, &selected)) != TCL_OK) return TCL_ERROR;
            if (selected) {if(!total)first=i;last=i;++total;if(!summary)Tcl_ListObjAppendElement(ip, result, Tcl_NewWideIntObj((Tcl_WideInt)i));}
        }
        if(summary){Tcl_DictObjPut(ip,result,Tcl_NewStringObj("count",-1),Tcl_NewWideIntObj((Tcl_WideInt)total));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("first",-1),Tcl_NewWideIntObj(first==SIZE_MAX?-1:(Tcl_WideInt)first));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("last",-1),Tcl_NewWideIntObj(last==SIZE_MAX?-1:(Tcl_WideInt)last));}
        Tcl_SetObjResult(ip, result); return TCL_OK;
    }
    if (strcmp(op, "select") == 0) {
        Tcl_WideInt index;
        gx2d_select_mode mode;
        if (argc != 6) return fail(ip, "Usage: core select scene object index replace|add|subtract");
        if (Tcl_GetWideIntFromObj(ip, argv[4], &index) != TCL_OK || index < 0) return fail(ip, "Point index must be nonnegative");
        if (read_mode(ip, argv[5], &mode) != TCL_OK) return TCL_ERROR;
        return status(ip, gx2d_select_point(node->scene, id, (size_t)index, mode));
    }
    if(strcmp(op,"object_style")==0){gx2d_style style;
        if(argc!=4&&argc!=5)return fail(ip,"Usage: core object_style scene object ?changes?");
        if(status(ip,gx2d_get_style(node->scene,id,&style))!=TCL_OK)return TCL_ERROR;
        if(argc==5){if(style_read(ip,argv[4],&style)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_set_style(node->scene,id,&style))!=TCL_OK)return TCL_ERROR;}
        Tcl_SetObjResult(ip,style_obj(style));return TCL_OK;
    }
    if(strcmp(op,"kind")==0){gx2d_kind kind;
        if(argc!=4)return fail(ip,"Usage: core kind scene object");
        if(status(ip,gx2d_kind_of(node->scene,id,&kind))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewStringObj(kind==GX2D_CURVE?"curve":kind==GX2D_POINT_SET?"point_set":kind==GX2D_POINT_OBJECT?"point":"group",-1));return TCL_OK;
    }
    if(strcmp(op,"layer_info")==0){gx2d_layer_style style;
        if(argc!=4)return fail(ip,"Usage: core layer_info scene layer");
        if(status(ip,gx2d_get_layer(node->scene,id,&style))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();
#define LAYER_INT(k) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(#k,-1),Tcl_NewIntObj(style.k))
        LAYER_INT(visible);LAYER_INT(selectable);LAYER_INT(locked);LAYER_INT(order);
#undef LAYER_INT
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("opacity",-1),Tcl_NewDoubleObj(style.opacity));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"points_page")==0){gx2d_point *points;size_t start,n;gx2d_status code;
        if(argc!=6||index_arg(ip,argv[4],&start)!=TCL_OK||index_arg(ip,argv[5],&n)!=TCL_OK)return fail(ip,"Usage: core points_page scene object start count");
        code=gx2d_get_points_range(node->scene,id,start,n,NULL,0,&count);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        points=(gx2d_point *)calloc(count?count:1,sizeof(*points));if(!points)return fail(ip,"Out of memory");
        code=gx2d_get_points_range(node->scene,id,start,n,points,count,&count);
        if(code!=GX2D_OK){free(points);return status(ip,code);}
        result=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));free(points);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(strcmp(op,"points_binary")==0){gx2d_point *points;size_t start,n,finite;unsigned char *xy,*rows;gx2d_status code;
        if(argc!=6||index_arg(ip,argv[4],&start)!=TCL_OK||index_arg(ip,argv[5],&n)!=TCL_OK)return fail(ip,"Usage: core points_binary scene object start count");
        code=gx2d_get_points_range(node->scene,id,start,n,NULL,0,&count);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        points=(gx2d_point *)malloc((count?count:1)*sizeof(*points));xy=(unsigned char *)malloc(count?count*16:1);rows=(unsigned char *)malloc(count?count*8:1);
        if(!points||!xy||!rows){free(points);free(xy);free(rows);return fail(ip,"Out of memory");}
        code=gx2d_get_points_range(node->scene,id,start,n,points,count,&count);
        if(code==GX2D_OK)code=gx2d_numeric_pack(points,NULL,(uint64_t)start,count,xy,count*16,rows,count*8,&finite);
        free(points);free(rows);
        if(code!=GX2D_OK){free(xy);return status(ip,code);}
        Tcl_SetObjResult(ip,Tcl_NewByteArrayObj(xy,(int)(finite*16)));free(xy);return TCL_OK;
    }
    if(strcmp(op,"render_lod")==0||strcmp(op,"render_curve_lod")==0||strcmp(op,"object_sample")==0){gx2d_point *points;uint64_t *indices;size_t budget,ncuts,*cuts;gx2d_status code;Tcl_Obj *mapped,*breaks,*coords;
        if(argc!=5||index_arg(ip,argv[4],&budget)!=TCL_OK)return fail(ip,"Usage: core render_lod scene object point_budget");
        if(budget<6||budget>65536)return fail(ip,"Display budget must be between 6 and 65536");
        count=budget;ncuts=budget;
        /* Interpolation can produce more display vertices than controls. */
        points=(gx2d_point *)calloc(count,sizeof(*points));indices=(uint64_t *)calloc(count,sizeof(*indices));cuts=(size_t *)calloc(ncuts,sizeof(*cuts));
        if(!points||!indices||!cuts){free(points);free(indices);free(cuts);return fail(ip,"Out of memory");}
        code=strcmp(op,"object_sample")==0?gx2d_object_sample(node->scene,id,budget,points,indices,count,&count,cuts,ncuts,&ncuts):strcmp(op,"render_curve_lod")==0?gx2d_curve_display(node->scene,id,budget,points,indices,count,&count,cuts,ncuts,&ncuts):gx2d_object_display(node->scene,id,budget,points,indices,count,&count,cuts,ncuts,&ncuts);
        if(code!=GX2D_OK){free(points);free(indices);free(cuts);return status(ip,code);}
        mapped=Tcl_NewListObj(0,NULL);breaks=Tcl_NewListObj(0,NULL);coords=Tcl_NewListObj(0,NULL);
        for(i=0;i<count;++i){Tcl_ListObjAppendElement(ip,mapped,Tcl_NewWideIntObj((Tcl_WideInt)indices[i]));Tcl_ListObjAppendElement(ip,coords,point_obj(points[i]));}
        for(i=0;i<ncuts;++i)Tcl_ListObjAppendElement(ip,breaks,Tcl_NewWideIntObj((Tcl_WideInt)cuts[i]));free(points);free(indices);free(cuts);
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("points",-1),coords);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point_indices",-1),mapped);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("breaks",-1),breaks);
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if (strcmp(op, "style") == 0) {
        gx2d_style style;
        double r, g, blue, width;
        int n;
        Tcl_Obj **rgb;
        if (argc != 6) return fail(ip, "Usage: core style scene object {r g b} width");
        if (Tcl_ListObjGetElements(ip, argv[4], &n, &rgb) != TCL_OK || n != 3 ||
            Tcl_GetDoubleFromObj(ip, rgb[0], &r) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, rgb[1], &g) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, rgb[2], &blue) != TCL_OK ||
            Tcl_GetDoubleFromObj(ip, argv[5], &width) != TCL_OK) return fail(ip, "Invalid style");
        if (status(ip, gx2d_get_style(node->scene, id, &style)) != TCL_OK) return TCL_ERROR;
        style.red = r; style.green = g; style.blue = blue; style.line_width = width;
        return status(ip, gx2d_set_style(node->scene, id, &style));
    }
    if(strcmp(op,"count")==0){if(argc!=4)return fail(ip,"Usage: core count scene object");
        if(status(ip,gx2d_point_count(node->scene,id,&count))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)count));return TCL_OK;}
    if(strcmp(op,"breaks")==0){size_t *v;gx2d_status code;
        if(argc!=4)return fail(ip,"Usage: core breaks scene object");
        if(status(ip,gx2d_get_breaks(node->scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;
        v=(size_t *)calloc(count?count:1,sizeof(*v));if(!v)return fail(ip,"Out of memory");
        code=gx2d_get_breaks(node->scene,id,v,count,&count);if(status(ip,code)!=TCL_OK){free(v);return TCL_ERROR;}
        result=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj((Tcl_WideInt)v[i]));
        free(v);Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"set_breaks")==0){Tcl_Obj **rows;size_t *v;int n,j;gx2d_status code;
        if(argc!=5||Tcl_ListObjGetElements(ip,argv[4],&n,&rows)!=TCL_OK)return fail(ip,"Usage: core set_breaks scene object indices");
        v=(size_t *)calloc(n?n:1,sizeof(*v));if(!v)return fail(ip,"Out of memory");
        for(j=0;j<n;++j)if(index_arg(ip,rows[j],&v[j])!=TCL_OK){free(v);return TCL_ERROR;}
        code=gx2d_set_breaks(node->scene,id,v,(size_t)n);free(v);return status(ip,code);}
    if(strcmp(op,"replace")==0){gx2d_point *p=NULL;gx2d_status code;
        if(argc!=5||point_list(ip,argv[4],&p,&count)!=TCL_OK)return TCL_ERROR;
        code=gx2d_replace_points(node->scene,id,p,count);free(p);return status(ip,code);}
    if(strcmp(op,"insert")==0||strcmp(op,"set_point")==0){size_t index;gx2d_point p;
        if(argc!=6||index_arg(ip,argv[4],&index)!=TCL_OK||read_point(ip,argv[5],&p)!=TCL_OK)return TCL_ERROR;
        return status(ip,strcmp(op,"insert")==0?gx2d_insert_point(node->scene,id,index,p):gx2d_set_point(node->scene,id,index,p));}
    if(strcmp(op,"remove_point")==0){size_t index;
        if(argc!=5||index_arg(ip,argv[4],&index)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_remove_point(node->scene,id,index));}
    if(strcmp(op,"move_point")==0){size_t from,to;
        if(argc!=6||index_arg(ip,argv[4],&from)!=TCL_OK||index_arg(ip,argv[5],&to)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_move_point(node->scene,id,from,to));}
    if(strcmp(op,"select_x")==0){double xmin,xmax;gx2d_select_mode mode;
        if(argc!=7||Tcl_GetDoubleFromObj(ip,argv[4],&xmin)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&xmax)!=TCL_OK||read_mode(ip,argv[6],&mode)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_select_x_interval(node->scene,id,xmin,xmax,mode));}
    if(strcmp(op,"reverse")==0){if(argc!=4)return fail(ip,"Usage: core reverse scene object");return status(ip,gx2d_reverse_points(node->scene,id));}
    if(strcmp(op,"extract")==0||strcmp(op,"keep")==0||strcmp(op,"remove_range")==0){size_t first,last;gx2d_status code;
        if(argc!=6||index_arg(ip,argv[4],&first)!=TCL_OK||index_arg(ip,argv[5],&last)!=TCL_OK)return TCL_ERROR;
        if(strcmp(op,"extract")==0)code=gx2d_extract_range(node->scene,id,first,last,&id);
        else if(strcmp(op,"keep")==0)code=gx2d_keep_range(node->scene,id,first,last);
        else code=gx2d_remove_range(node->scene,id,first,last);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        if(strcmp(op,"extract")==0)Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;}
    if(strcmp(op,"split")==0){size_t index;gx2d_id a,bid;Tcl_Obj *v[2];
        if(argc!=5||index_arg(ip,argv[4],&index)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_split(node->scene,id,index,&a,&bid))!=TCL_OK)return TCL_ERROR;
        v[0]=Tcl_NewWideIntObj((Tcl_WideInt)a);v[1]=Tcl_NewWideIntObj((Tcl_WideInt)bid);
        Tcl_SetObjResult(ip,Tcl_NewListObj(2,v));return TCL_OK;}
    if(strcmp(op,"bounds")==0){gx2d_rect r;
        if(argc!=4||status(ip,gx2d_object_bounds(node->scene,id,&r))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,rect_obj(r));return TCL_OK;}
    if(strcmp(op,"selected_records")==0){gx2d_selected_point *v;gx2d_status code;
        if(argc!=4)return fail(ip,"Usage: core selected_records scene object");
        if(status(ip,gx2d_selected_points(node->scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;
        v=(gx2d_selected_point *)calloc(count?count:1,sizeof(*v));if(!v)return fail(ip,"Out of memory");
        code=gx2d_selected_points(node->scene,id,v,count,&count);if(status(ip,code)!=TCL_OK){free(v);return TCL_ERROR;}
        result=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i){Tcl_Obj *r=Tcl_NewDictObj();
            Tcl_DictObjPut(ip,r,Tcl_NewStringObj("object",-1),Tcl_NewWideIntObj((Tcl_WideInt)v[i].object));
            Tcl_DictObjPut(ip,r,Tcl_NewStringObj("index",-1),Tcl_NewWideIntObj((Tcl_WideInt)v[i].index));
            Tcl_DictObjPut(ip,r,Tcl_NewStringObj("point",-1),point_obj(v[i].point));Tcl_ListObjAppendElement(ip,result,r);}
        free(v);Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"nearest_segment")==0){gx2d_point p;gx2d_segment_hit h;
        if(argc!=5||read_point(ip,argv[4],&p)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_nearest_segment(node->scene,id,p,&h))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,segment_obj(h));return TCL_OK;}
    if(strcmp(op,"nearest_spline")==0){gx2d_point p;gx2d_segment_hit h;size_t steps;
        if(argc!=6||read_point(ip,argv[4],&p)!=TCL_OK||index_arg(ip,argv[5],&steps)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_nearest_spline(node->scene,id,p,steps,&h))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,segment_obj(h));return TCL_OK;}
    if(strcmp(op,"snap_to_curve")==0){gx2d_id target;size_t index;
        if(argc!=6||index_arg(ip,argv[4],&index)!=TCL_OK||object_id(ip,argv[5],&target)!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_snap_to_curve(node->scene,id,index,target));}
    if(strcmp(op,"path_length")==0){double x;
        if(argc!=4||status(ip,gx2d_path_length(node->scene,id,&x))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewDoubleObj(x));return TCL_OK;}
    if(strcmp(op,"path_point")==0){double x;gx2d_segment_hit h;
        if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[4],&x)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_path_point(node->scene,id,x,&h))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,segment_obj(h));return TCL_OK;}
    if(strcmp(op,"metrics")==0){gx2d_metrics m;Tcl_Obj *r;
        if(argc!=4||status(ip,gx2d_curve_metrics(node->scene,id,&m))!=TCL_OK)return TCL_ERROR;
        r=Tcl_NewDictObj();
#define PUT_METRIC(key,value) Tcl_DictObjPut(ip,r,Tcl_NewStringObj(key,-1),Tcl_NewDoubleObj(value))
        PUT_METRIC("length",m.length);PUT_METRIC("span_x",m.span_x);PUT_METRIC("span_y",m.span_y);
        PUT_METRIC("signed_area",m.signed_area);PUT_METRIC("length_span_ratio",m.length_span_ratio);
        Tcl_DictObjPut(ip,r,Tcl_NewStringObj("closed",-1),Tcl_NewBooleanObj(m.closed));
#undef PUT_METRIC
        Tcl_SetObjResult(ip,r);return TCL_OK;}
    if(strcmp(op,"spline")==0||strcmp(op,"render_spline")==0||strcmp(op,"render")==0){gx2d_point *v;gx2d_status code;size_t per=0;
        if(strcmp(op,"spline")==0||strcmp(op,"render_spline")==0){if(argc!=5||index_arg(ip,argv[4],&per)!=TCL_OK)return TCL_ERROR;
            code=gx2d_sample_spline(node->scene,id,per,NULL,0,&count);}
        else {if(argc!=4)return fail(ip,"Usage: core render scene object");code=gx2d_render_points(node->scene,id,NULL,0,&count);}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        v=(gx2d_point *)calloc(count?count:1,sizeof(*v));if(!v)return fail(ip,"Out of memory");
        code=strcmp(op,"render")==0?gx2d_render_points(node->scene,id,v,count,&count):gx2d_sample_spline(node->scene,id,per,v,count,&count);
        if(status(ip,code)!=TCL_OK){free(v);return TCL_ERROR;}
        if(strcmp(op,"render_spline")==0){for(i=0;i<count;++i){gx2d_point q;
            code=gx2d_world_to_device(node->scene,v[i],&q);if(code!=GX2D_OK){free(v);return status(ip,code);}v[i]=q;}}
        result=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,point_obj(v[i]));
        free(v);Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"render_paths")==0){gx2d_point *v;size_t *cuts;size_t ncuts,j,start=0;gx2d_status code;
        if(argc!=4)return fail(ip,"Usage: core render_paths scene object");
        if(status(ip,gx2d_render_points(node->scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;
        if(!count){Tcl_SetObjResult(ip,Tcl_NewListObj(0,NULL));return TCL_OK;}
        if(status(ip,gx2d_get_breaks(node->scene,id,NULL,0,&ncuts))!=TCL_OK)return TCL_ERROR;
        v=(gx2d_point *)calloc(count?count:1,sizeof(*v));cuts=(size_t *)calloc(ncuts?ncuts:1,sizeof(*cuts));
        if(!v||!cuts){free(v);free(cuts);return fail(ip,"Out of memory");}
        code=gx2d_render_points(node->scene,id,v,count,&count);
        if(code==GX2D_OK)code=gx2d_get_breaks(node->scene,id,cuts,ncuts,&ncuts);
        if(status(ip,code)!=TCL_OK){free(v);free(cuts);return TCL_ERROR;}
        result=Tcl_NewListObj(0,NULL);
        for(j=0;j<=ncuts;++j){size_t end=j<ncuts?cuts[j]:count-1,k;Tcl_Obj *part=Tcl_NewListObj(0,NULL);
            for(k=start;k<=end;++k)Tcl_ListObjAppendElement(ip,part,point_obj(v[k]));
            Tcl_ListObjAppendElement(ip,result,part);start=end+1;}
        free(v);free(cuts);Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"locked")==0){gx2d_style style;int locked;
        if(argc!=5||Tcl_GetBooleanFromObj(ip,argv[4],&locked)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_get_style(node->scene,id,&style))!=TCL_OK)return TCL_ERROR;
        style.locked=locked;return status(ip,gx2d_set_style(node->scene,id,&style));}
    if(strcmp(op,"endpoints")==0){gx2d_point a,z;Tcl_Obj *v[2];
        if(argc!=4||status(ip,gx2d_endpoints(node->scene,id,&a,&z))!=TCL_OK)return TCL_ERROR;
        v[0]=point_obj(a);v[1]=point_obj(z);Tcl_SetObjResult(ip,Tcl_NewListObj(2,v));return TCL_OK;}
    return fail(ip, "Unknown Native 2D bridge operation");
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int Gx2dtcl_Init(Tcl_Interp *ip) {
    bridge *b;
    if (Tcl_InitStubs(ip, "8.6", 0) == NULL) return TCL_ERROR;
    b = (bridge *)calloc(1, sizeof(*b));
    if (!b) return fail(ip, "Out of memory");
    Tcl_CreateNamespace(ip, "::GX::Native2D", NULL, NULL);
    Tcl_CreateObjCommand(ip, "::GX::Native2D::core", command, b, free_bridge);
    if(gx2d_surface_init(ip)!=TCL_OK)return TCL_ERROR;
#ifdef GXTXT_NATIVE_PLOT_V4
    if(gx2d_plot_v4_init(ip)!=TCL_OK)return TCL_ERROR;
#endif
    return Tcl_PkgProvide(ip, "gx2dtcl", "1.0");
}
