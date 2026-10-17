#ifndef GX2D_H
#define GX2D_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(GX2D_BUILD_DLL)
#define GX2D_API __declspec(dllexport)
#elif defined(_WIN32) && defined(GX2D_USE_DLL)
#define GX2D_API __declspec(dllimport)
#else
#define GX2D_API
#endif

typedef uint64_t gx2d_id;
typedef struct gx2d_scene gx2d_scene;
typedef struct gx2d_display_accumulator gx2d_display_accumulator;
typedef struct { double x, y; } gx2d_point;
typedef struct { double x0, y0, x1, y1; } gx2d_rect;
typedef struct { double width, height, left, top, right, bottom; gx2d_rect world; } gx2d_view;
typedef enum { GX2D_ASPECT_AUTO = 0, GX2D_ASPECT_XY_EQUAL = 1 } gx2d_aspect_mode;
typedef struct { double red, green, blue, alpha; } gx2d_color;
typedef struct {
    int enabled, visible, snap_enabled, major_visible, minor_visible, axes_visible;
    gx2d_point origin;
    double spacing_x, spacing_y, angle; /* radians, orthogonal local grid */
    size_t major_interval;
    gx2d_color major_color, minor_color, axes_color;
    double major_width, minor_width, axes_width;
    int major_style, minor_style, axes_style; /* gx2d_line_style */
} gx2d_grid;
typedef struct { gx2d_point a,b; int classification; } gx2d_grid_segment; /* 0 minor,1 major,2 axes */
typedef enum { GX2D_CARTESIAN = 0, GX2D_POLAR = 1 } gx2d_coordinate_mode;
typedef struct {
    gx2d_point origin;
    double theta_zero; /* radians in world XY */
    int clockwise, degrees;
    double radius_min, radius_max;
    double angle_min, angle_span; /* radians; span in (0,2*pi] */
    double radial_spacing, angular_spacing; /* world units and radians */
    size_t radial_major_interval, angular_major_interval;
} gx2d_polar_frame;
typedef struct {
    int present, visible, forward, interpolation; /* Presentation only: 0 polyline, 1 Catmull-Rom. */
    double fraction, offset_px, length_px, line_width, head_scale;
    gx2d_color color;
} gx2d_direction_marker;
typedef struct {
    gx2d_point anchor, tail, tip, head_left, head_right;
    gx2d_rect bounds;
    double fraction;
} gx2d_direction_primitives;
/* Parent-scoped persistent leaf identity. Existing definition POD ABI stays intact. */
typedef struct {uint64_t part_id;gx2d_direction_marker direction;} gx2d_part_state;
typedef struct { gx2d_id object; size_t index; gx2d_point point; } gx2d_selected_point;
typedef struct { size_t segment; double t, distance; gx2d_point point; } gx2d_segment_hit;
typedef struct { double length, span_x, span_y, signed_area, length_span_ratio; int closed; } gx2d_metrics;
typedef struct { gx2d_point point, derivative; size_t point_index; } gx2d_endpoint_frame;
/* Mathematical sketch definitions; the caller owns the immutable control
 * array for the duration of these queries. Parameter is normalized [0,1],
 * except construction lines which also permit extrapolation. Angles are
 * radians. Matrix maps local defining coordinates into world coordinates. */
typedef enum {
    GX2D_SKETCH_POINT=1, GX2D_SKETCH_LINE, GX2D_SKETCH_CONSTRUCTION_LINE,
    GX2D_SKETCH_POLYLINE, GX2D_SKETCH_RECTANGLE, GX2D_SKETCH_CIRCLE,
    GX2D_SKETCH_ARC, GX2D_SKETCH_ELLIPSE, GX2D_SKETCH_QUADRATIC_BEZIER,
    GX2D_SKETCH_CUBIC_BEZIER, GX2D_SKETCH_SPLINE, GX2D_SKETCH_PATH,
    GX2D_SKETCH_COMPOSITE_PATH, GX2D_SKETCH_COMPOUND
} gx2d_sketch_family;
/* Optional offsets are local to each knot, so moving a knot moves its arms.
 * Zero flags retain the exact legacy automatically derived cubic controls. */
typedef struct { gx2d_point incoming,outgoing; unsigned flags; } gx2d_spline_tangent;
/* Composite retained path topology: segments reference shared vertex ordinals.
 * This shared-vertex Path stays straight. Heterogeneous finite leaves use
 * COMPOSITE_PATH/COMPOUND below, never approximated as straight segments. */
typedef struct {gx2d_sketch_family family;size_t first,last;} gx2d_path_segment;
typedef struct gx2d_sketch_definition {
    gx2d_sketch_family family;
    const gx2d_point *controls; size_t control_count;
    double radius_x, radius_y, rotation, angle_start, angle_sweep;
    double matrix[6];
    const gx2d_spline_tangent *tangents; size_t tangent_count;
    const gx2d_path_segment *path_segments;size_t path_segment_count;int path_closed;
    /* Composition owns a flat list of exact finite primitive definitions.
     * No nested compositions or display-derived controls. Ordered junctions
     * are shared topological nodes i+1, checked with explicit join_tolerance.
     * Compound parts have independent domains and no implicit traversal. */
    const struct gx2d_sketch_definition *parts;
    const int *part_reversed;size_t part_count;
    double join_tolerance;
    /* Canonical control ordinals identify shared nodes; absent for legacy chains. */
    const size_t *nodes; size_t node_count;
} gx2d_sketch_definition;
typedef enum { GX2D_BRIDGE_STRAIGHT=1, GX2D_BRIDGE_QUADRATIC,
    GX2D_BRIDGE_CUBIC, GX2D_BRIDGE_HERMITE } gx2d_bridge_kind;
typedef struct {
    gx2d_bridge_kind kind;
    gx2d_endpoint_frame start, end;
    size_t subdivisions; /* 1..4096; explicit materialization policy */
    double tolerance;
} gx2d_bridge_spec;
typedef struct {
    size_t control_count;
    gx2d_point controls[4], start_derivative, end_derivative;
    int c0, c1_start, c1_end, tangent_start, tangent_end;
} gx2d_bridge_result;
typedef enum { GX2D_COMPARE_X = 1, GX2D_COMPARE_PATH } gx2d_compare_method;
typedef struct { double position, signed_residual, absolute_residual; gx2d_point reference, derived; } gx2d_residual;
typedef struct { size_t count, max_index; double max_absolute, mean_absolute, rmse; } gx2d_residual_summary;

typedef enum {
    GX2D_OK = 0, GX2D_INVALID, GX2D_NOT_FOUND, GX2D_LOCKED,
    GX2D_CONSTRAINT, GX2D_NOMEM, GX2D_BUSY, GX2D_RANGE
} gx2d_status;
/* Exact globally ordered vertices. Closed reversal retains vertex zero as its
 * anchor; repeat_endpoint explicitly chooses whether to repeat it at the end. */
GX2D_API gx2d_status gx2d_path_vertices(const gx2d_scene *,gx2d_id,int,gx2d_point *,size_t,size_t *);
GX2D_API gx2d_status gx2d_path_split(gx2d_scene *,gx2d_id,size_t,gx2d_id [2]);
GX2D_API gx2d_status gx2d_path_join(gx2d_scene *,gx2d_id,gx2d_id,int,int,double,gx2d_id *);
/* Inputs survive. The candidate owns exact copies; stale/unsupported input
 * rejects the entire operation. Parts are indexed from zero. Create mode:
 * 0 Compound, 1 explicit ordered/oriented Path, 2 infer an unbranched Path. */
GX2D_API gx2d_status gx2d_composition_create(gx2d_scene *,const gx2d_id *,const int *,size_t,int,double,gx2d_id *);
GX2D_API gx2d_status gx2d_composition_part(const gx2d_scene *,gx2d_id,size_t,gx2d_sketch_definition *,int *);
GX2D_API gx2d_status gx2d_composition_identity_counter(const gx2d_scene *,gx2d_id,uint64_t *);
GX2D_API gx2d_status gx2d_sketch_update_parts(gx2d_scene *,gx2d_id,const gx2d_sketch_definition *,size_t,const gx2d_part_state *,size_t,uint64_t);
GX2D_API gx2d_status gx2d_composition_states(const gx2d_scene *,gx2d_id,gx2d_part_state *,size_t,size_t *);
GX2D_API gx2d_status gx2d_composition_states_restore(gx2d_scene *,gx2d_id,const gx2d_part_state *,size_t);
GX2D_API gx2d_status gx2d_part_ordinal(const gx2d_scene *,gx2d_id,uint64_t,size_t *);
GX2D_API gx2d_status gx2d_part_direction_get(const gx2d_scene *,gx2d_id,uint64_t,gx2d_direction_marker *);
GX2D_API gx2d_status gx2d_part_direction_set(gx2d_scene *,gx2d_id,uint64_t,const gx2d_direction_marker *);
GX2D_API gx2d_status gx2d_part_direction_render(const gx2d_scene *,gx2d_id,uint64_t,gx2d_direction_primitives *);
GX2D_API gx2d_status gx2d_part_direction_hit(const gx2d_scene *,gx2d_id,uint64_t,gx2d_point,double,int *);
GX2D_API gx2d_status gx2d_part_direction_place(gx2d_scene *,gx2d_id,uint64_t,gx2d_point,double *);
GX2D_API gx2d_status gx2d_part_render(const gx2d_scene *,gx2d_id,uint64_t,gx2d_point *,size_t,size_t *);
GX2D_API gx2d_status gx2d_part_pick(const gx2d_scene *,gx2d_id,gx2d_point,double,uint64_t *);
/* 0 unordered compound, 1 valid continuous stored traversal, 2 network/discontinuous.
 * Independent part directions and root direction are included in this check. */
GX2D_API gx2d_status gx2d_composition_traversal(const gx2d_scene *,gx2d_id,int *);
GX2D_API gx2d_status gx2d_composition_split(gx2d_scene *,gx2d_id,size_t,gx2d_id [2]);
GX2D_API gx2d_status gx2d_composition_explode(gx2d_scene *,gx2d_id,gx2d_id *,size_t,size_t *);
GX2D_API gx2d_status gx2d_sketch_validate(const gx2d_sketch_definition *);
GX2D_API gx2d_status gx2d_sketch_evaluate(const gx2d_sketch_definition *, double, gx2d_point *, gx2d_point *);
GX2D_API gx2d_status gx2d_sketch_bounds(const gx2d_sketch_definition *, gx2d_rect *);
/* A page of an explicit complete sampling grid. Never changes the definition.
 * Total 1..1000000, page at most 65536; no output mutation on failed evaluation. */
GX2D_API gx2d_status gx2d_sketch_sample(const gx2d_sketch_definition *, double, double, size_t, size_t, size_t, gx2d_point *, size_t);
/* Retained scene primitives own a deep copy of the definition. Display samples
 * are a cache; get_definition returns borrowed immutable scene-owned controls.
 * Use update for parameter edits, or explicitly explode to generic geometry. */
GX2D_API gx2d_status gx2d_sketch_create(gx2d_scene *, const gx2d_sketch_definition *, size_t, gx2d_id *);
GX2D_API gx2d_status gx2d_sketch_get_definition(const gx2d_scene *, gx2d_id, gx2d_sketch_definition *);
/* Exact selected definition and nonmutating span-to-Line plan. Caller releases
 * the owned definition with gx2d_control_definition_release. */
GX2D_API gx2d_status gx2d_selection_control_sources(const gx2d_scene *,gx2d_id,size_t,size_t *,size_t,size_t *);
GX2D_API gx2d_status gx2d_selection_definition_owned(const gx2d_scene *,gx2d_id,size_t,gx2d_sketch_definition **);
GX2D_API gx2d_status gx2d_spline_span_to_line(gx2d_scene *,gx2d_id,size_t);
GX2D_API gx2d_status gx2d_spline_line_plan(const gx2d_scene *,gx2d_id,size_t,gx2d_sketch_definition **,size_t *,size_t,size_t *,size_t *,size_t *);
GX2D_API gx2d_status gx2d_sketch_update(gx2d_scene *, gx2d_id, const gx2d_sketch_definition *, size_t);
/* incoming=1 addresses the previous piece; outgoing=0 addresses the next.
 * Query/edit use world coordinates. For a composed Path, knot is its global
 * defining-control ordinal and must address a Spline leaf. Leaf side names
 * survive reversed Path traversal. Absent endpoint sides reject explicitly. */
GX2D_API gx2d_status gx2d_spline_tangent_get(const gx2d_scene *,gx2d_id,size_t,int,gx2d_point *,gx2d_point *,int *);
GX2D_API gx2d_status gx2d_spline_tangent_edit(gx2d_scene *,gx2d_id,size_t,int,gx2d_point,int);
GX2D_API gx2d_status gx2d_sketch_explode(gx2d_scene *, gx2d_id, size_t, gx2d_id *);
/* Explicit finite parameter materialization; complete total up to one million,
 * native-owned generated coordinates, no publication or temporary Dataset. */
GX2D_API gx2d_status gx2d_sketch_materialize(gx2d_scene *,gx2d_id,double first,
    double last,size_t total,gx2d_id *);

typedef enum { GX2D_CURVE = 1, GX2D_POINT_SET, GX2D_POINT_OBJECT, GX2D_GROUP } gx2d_kind;
/* Resource identity is portable text, never a host file path. The Session
 * adapter validates actual ownership/integrity before attaching its raster. */
typedef struct {
    char resource_id[128],length_unit[32];
    double width,height,scale,rotation,opacity;
    gx2d_point translation,calibration[2];
    double calibrated_distance; /* Derived mapped distance; creation must agree with scale. */int visible,locked,calibrated;
} gx2d_reference_image;
GX2D_API gx2d_status gx2d_image_create(gx2d_scene *,const gx2d_reference_image *,gx2d_id *);
GX2D_API gx2d_status gx2d_image_get(const gx2d_scene *,gx2d_id,gx2d_reference_image *);
GX2D_API gx2d_status gx2d_image_update(gx2d_scene *,gx2d_id,const gx2d_reference_image *);
GX2D_API gx2d_status gx2d_image_calibrate(gx2d_scene *,gx2d_id,gx2d_point,gx2d_point,double);
GX2D_API gx2d_status gx2d_image_map(const gx2d_scene *,gx2d_id,gx2d_point,int,gx2d_point *);
/* Source-pixel simple polygon validation. Bounds are clipped, vertices unchanged. */
GX2D_API gx2d_status gx2d_image_roi_validate(const gx2d_scene *,gx2d_id,const gx2d_point *,size_t,gx2d_rect *,double *,int *);
/* Bounded ordered-path topology validation; shares ROI intersection predicates. */
GX2D_API gx2d_status gx2d_path_validate(const gx2d_point *,size_t,int,double *,double *);
/* Read-only preview transform, scaling device margins with output dimensions.
 * fit uses existing Fit All semantics; current preserves effective world view. */
GX2D_API gx2d_status gx2d_preview_view(const gx2d_scene *,int,double,double,double,gx2d_view *);
typedef enum { GX2D_LINE_SOLID = 0, GX2D_LINE_DASH, GX2D_LINE_DOT } gx2d_line_style;
typedef enum { GX2D_MARKER_NONE = 0, GX2D_MARKER_CIRCLE, GX2D_MARKER_SQUARE, GX2D_MARKER_CROSS } gx2d_marker;
typedef enum { GX2D_SELECT_REPLACE = 0, GX2D_SELECT_ADD, GX2D_SELECT_SUBTRACT } gx2d_select_mode;
typedef struct { gx2d_rect bounds; gx2d_select_mode mode; } gx2d_selection_region;
/* Read-only semantic selection state, safe during an active gesture. Manual
 * bytes are 0 inherit, 1 include, 2 exclude. Rectangle order is significant;
 * manual point overrides follow every rectangle. These queries do not rebuild
 * or modify the scene. A consumer can apply point-set regions to exact data. */
GX2D_API gx2d_status gx2d_selection_regions(const gx2d_scene *, gx2d_id,
    gx2d_selection_region *, size_t capacity, size_t *count, int *base_selected);
GX2D_API gx2d_status gx2d_selection_manual_range(const gx2d_scene *, gx2d_id,
    size_t start, size_t count, unsigned char *, size_t capacity);
typedef enum { GX2D_FIXED = 1, GX2D_DISTANCE, GX2D_ANGLE, GX2D_PARALLEL, GX2D_PERPENDICULAR,
    GX2D_COINCIDENT, GX2D_HORIZONTAL, GX2D_VERTICAL, GX2D_EQUAL_LENGTH,
    GX2D_EQUAL_RADIUS, GX2D_TANGENT, GX2D_CONCENTRIC, GX2D_COLLINEAR,
    GX2D_MIDPOINT, GX2D_POINT_ON_LINE, GX2D_POINT_ON_CURVE, GX2D_SYMMETRY,
    GX2D_RADIUS, GX2D_DIAMETER, GX2D_LOCK_X, GX2D_LOCK_Y,
    GX2D_HORIZONTAL_DISTANCE, GX2D_VERTICAL_DISTANCE, GX2D_POINT_LINE_DISTANCE,
    GX2D_LINE_DISTANCE, GX2D_AXIS_ANGLE, GX2D_CURVATURE } gx2d_constraint_kind;
typedef enum { GX2D_PIVOT_BOUNDS=0, GX2D_PIVOT_CENTROID,
    GX2D_PIVOT_ORIGIN, GX2D_PIVOT_CUSTOM } gx2d_pivot_mode;
typedef enum { GX2D_GIZMO_TRANSLATE=1, GX2D_GIZMO_ROTATE, GX2D_GIZMO_MIRROR } gx2d_gizmo_mode;
typedef enum { GX2D_OVERLAY_LINE=1, GX2D_OVERLAY_CIRCLE, GX2D_OVERLAY_BOX } gx2d_overlay_kind;
typedef enum { GX2D_HANDLE_NONE=0, GX2D_HANDLE_PIVOT=1, GX2D_HANDLE_X,
    GX2D_HANDLE_Y, GX2D_HANDLE_FREE, GX2D_HANDLE_ROTATE,
    GX2D_HANDLE_MIRROR_A, GX2D_HANDLE_MIRROR_B } gx2d_gizmo_handle;
typedef struct {
    int visible;gx2d_gizmo_mode mode;
    double radius_px,handle_px,line_width,axes_angle;
    gx2d_point mirror_a,mirror_b;
    gx2d_color x_color,y_color,rotation_color,pivot_color;
} gx2d_gizmo;
typedef struct {
    gx2d_overlay_kind kind;gx2d_gizmo_handle handle;
    gx2d_point a,b;gx2d_color color;double width;
} gx2d_overlay_primitive;
typedef struct {
    gx2d_point pivot,translation,world_point;
    double radians;
} gx2d_gizmo_delta;

typedef struct {
    int visible, selectable, selected, locked;
    gx2d_id layer;
    int order;
    double red, green, blue, line_width, opacity;
    gx2d_line_style line_style;
    gx2d_marker marker;
} gx2d_style;
typedef struct {
    int visible, selectable, locked, order;
    double opacity;
} gx2d_layer_style;
typedef struct {
    gx2d_constraint_kind kind;
    gx2d_id a, b;
    size_t a_index, b_index;
    double value; /* distance or signed angle in radians */
    double tolerance; /* positive world-coordinate/radian tolerance */
} gx2d_constraint;
typedef struct {
    gx2d_id object;
    size_t point_index;
    gx2d_point point;
    double distance;
} gx2d_hit;

/* Exact read-only scene vertex/endpoint search. Exclusions expand flat groups;
 * hidden/unselectable geometry is ignored, locked reference geometry is usable.
 * Endpoint mode includes the endpoints of every disconnected curve span.
 * Device search uses the effective view and reports distance in pixels; world
 * search reports world-coordinate distance. Both are safe during native drag. */
GX2D_API gx2d_status gx2d_scene_nearest_vertex(const gx2d_scene *, gx2d_point,
    double radius, const gx2d_id *exclude, size_t exclude_count,
    int endpoints_only, gx2d_hit *);
GX2D_API gx2d_status gx2d_scene_nearest_vertex_device(const gx2d_scene *, gx2d_point,
    double radius_px, const gx2d_id *exclude, size_t exclude_count,
    int endpoints_only, gx2d_hit *);
/* Positive coordinate-frame rescaling, not a physical Scale transform. Geometry,
 * fixed anchors/distance constraints, grid/polar lengths, view/pivot/mirror axes
 * convert atomically. Angles, pixels, IDs, styles and row/point ordering remain.
 * The host obtains the factor from the public Unit Registry. */
GX2D_API gx2d_status gx2d_scene_rescale_coordinates(gx2d_scene *, double factor);
/* Coherent translation snapping of the captured pivot. X/Y handles retain the
 * native gizmo axis; Free produces coincidence. Read-only and safe during drag. */
GX2D_API gx2d_status gx2d_gizmo_snap_translation(const gx2d_scene *,
    gx2d_gizmo_handle, gx2d_point pivot, gx2d_point requested_translation,
    double radius_px, const gx2d_id *exclude, size_t exclude_count,
    int endpoints_only, gx2d_point *translation, int *snapped, gx2d_hit *target);

/* Endpoint derivative is with respect to the incident source segment's local
 * parameter [0,1]. Reverse changes both endpoint and derivative direction.
 * Interpolation 1 uses the existing native Catmull-Rom derivative exactly.
 * Bridge is source-preserving. Cubic/Hermite match both derivatives (C1);
 * quadratic reports tangent-only continuity when derivative magnitudes differ. */
GX2D_API gx2d_status gx2d_curve_endpoint_frame(const gx2d_scene *, gx2d_id,
    int end, int reverse, int interpolation, gx2d_endpoint_frame *);
GX2D_API gx2d_status gx2d_curve_point_frame(const gx2d_scene *, gx2d_id,
    size_t point_index, int incoming, int reverse, int interpolation,
    gx2d_endpoint_frame *);
GX2D_API gx2d_status gx2d_bridge_create(gx2d_scene *, const gx2d_bridge_spec *,
    gx2d_id *, gx2d_bridge_result *);
GX2D_API gx2d_status gx2d_point_distance(gx2d_point, gx2d_point, double *);

GX2D_API gx2d_scene *gx2d_create(void);
GX2D_API void gx2d_destroy(gx2d_scene *scene);
GX2D_API const char *gx2d_status_text(gx2d_status status);

/* Geometry-role truth is Native metadata, shared by every consumer. It does
 * not alter geometry/units; normal scientific output excludes construction
 * and reference entities unless explicit finite materialization is requested. */
typedef enum {GX2D_ROLE_REGULAR=0,GX2D_ROLE_CONSTRUCTION=1,GX2D_ROLE_REFERENCE=2} gx2d_geometry_role;
GX2D_API gx2d_status gx2d_geometry_role_set(gx2d_scene *,gx2d_id,gx2d_geometry_role);
GX2D_API gx2d_status gx2d_geometry_role_get(const gx2d_scene *,gx2d_id,gx2d_geometry_role *);
/* Native sketch identity and inert UTF-8 attributes. Owner 0 is the scene.
 * Names use gx.name; keys must contain a namespace dot. Borrowed get strings
 * remain valid until the corresponding metadata mutation or scene destruction. */
GX2D_API gx2d_status gx2d_attribute_set(gx2d_scene *,gx2d_id,const char *,const char *);
GX2D_API gx2d_status gx2d_attribute_get(const gx2d_scene *,gx2d_id,const char *,const char **);
GX2D_API gx2d_status gx2d_attribute_remove(gx2d_scene *,gx2d_id,const char *);
GX2D_API gx2d_status gx2d_attribute_keys(const gx2d_scene *,gx2d_id,const char **,size_t,size_t *);
GX2D_API gx2d_status gx2d_set_name(gx2d_scene *,gx2d_id,const char *);
GX2D_API gx2d_status gx2d_get_name(const gx2d_scene *,gx2d_id,const char **);
GX2D_API gx2d_status gx2d_object_topology_epoch(const gx2d_scene *,gx2d_id,uint64_t *);
/* Fragments reference their parent without copying geometry. Discrete intervals
 * use inclusive point ordinals; retained intervals use normalized parameters.
 * Parameter direction may be reversed. Topology changes invalidate references. */
typedef struct {gx2d_id parent;int parameter;double first,last;} gx2d_fragment_spec;
typedef struct {gx2d_fragment_spec spec;uint64_t topology_epoch;int valid,missing;} gx2d_fragment;
GX2D_API gx2d_status gx2d_fragment_create(gx2d_scene *,const gx2d_fragment_spec *,gx2d_id *);
GX2D_API gx2d_status gx2d_fragment_get(const gx2d_scene *,gx2d_id,gx2d_fragment *);
GX2D_API gx2d_status gx2d_fragment_ids(const gx2d_scene *,gx2d_id *,size_t,size_t *);
GX2D_API gx2d_status gx2d_fragment_update(gx2d_scene *,gx2d_id,const gx2d_fragment_spec *);
GX2D_API gx2d_status gx2d_fragment_delete(gx2d_scene *,gx2d_id);
GX2D_API gx2d_status gx2d_fragment_sample(const gx2d_scene *,gx2d_id,size_t,size_t,size_t,gx2d_point *,size_t);
GX2D_API gx2d_status gx2d_fragment_materialize(gx2d_scene *,gx2d_id,size_t,gx2d_id *);
GX2D_API gx2d_status gx2d_fragment_length(const gx2d_scene *,gx2d_id,double *);
GX2D_API gx2d_status gx2d_fragment_bounds(const gx2d_scene *,gx2d_id,size_t,gx2d_rect *);

typedef enum {GX2D_SELECTION_OBJECT=1,GX2D_SELECTION_POINT,GX2D_SELECTION_FRAGMENT,GX2D_SELECTION_CONTROL,GX2D_SELECTION_SEGMENT} gx2d_selection_ref_kind;
typedef struct {gx2d_selection_ref_kind kind;gx2d_id id;size_t index;} gx2d_selection_ref;
typedef struct {gx2d_selection_ref reference;uint64_t topology_epoch;int valid,missing;} gx2d_selection_member;
GX2D_API gx2d_status gx2d_selection_set_create(gx2d_scene *,const gx2d_selection_ref *,size_t,gx2d_id *);
GX2D_API gx2d_status gx2d_selection_set_update(gx2d_scene *,gx2d_id,const gx2d_selection_ref *,size_t);
GX2D_API gx2d_status gx2d_selection_set_add_member(gx2d_scene *,gx2d_id,gx2d_selection_ref);
GX2D_API gx2d_status gx2d_selection_set_remove_member(gx2d_scene *,gx2d_id,size_t);
GX2D_API gx2d_status gx2d_selection_set_ids(const gx2d_scene *,gx2d_id *,size_t,size_t *);
GX2D_API gx2d_status gx2d_selection_set_get(const gx2d_scene *,gx2d_id,gx2d_selection_member *,size_t,size_t *);
GX2D_API gx2d_status gx2d_selection_set_delete(gx2d_scene *,gx2d_id);
GX2D_API gx2d_status gx2d_selection_set_activate(gx2d_scene *,gx2d_id,gx2d_select_mode);
/* Semantic selection uses the existing selection-set authority. id==0 denotes
 * an empty current selection; apply returns zero after removing its last member.
 * Region vertices are world coordinates; picking uses device coordinates.
 * Scope IDs are explicit and hidden/unselectable geometry is always excluded.
 * Retained controls/segments keep encoded Native references, never samples. */
GX2D_API gx2d_status gx2d_selection_set_apply(gx2d_scene *,gx2d_id *,const gx2d_selection_ref *,size_t,gx2d_select_mode);
/* Bounds of participating logical owners, including selected controls/segments. */
GX2D_API gx2d_status gx2d_selection_set_bounds(const gx2d_scene *,gx2d_id,gx2d_rect *);
GX2D_API gx2d_status gx2d_selection_set_restore(gx2d_scene *,gx2d_id *,const gx2d_selection_ref *,size_t);
GX2D_API gx2d_status gx2d_selection_pick(const gx2d_scene *,const gx2d_id *,size_t,gx2d_point,double,gx2d_selection_ref *);
GX2D_API gx2d_status gx2d_selection_polygon(const gx2d_scene *,const gx2d_id *,size_t,const gx2d_point *,size_t,gx2d_selection_ref *,size_t,size_t *);
/* Additive target policy: legacy detail APIs retain their exact behavior. Local
 * picks preserve controls, atomic primitives and exact Spline spans/constituents.
 * Object picks/regions return explicit whole logical owners, never sample masks. */
typedef enum {GX2D_PICK_DETAIL=0,GX2D_PICK_LOCAL,GX2D_PICK_OBJECT} gx2d_selection_target;
GX2D_API gx2d_status gx2d_selection_pick_target(const gx2d_scene *,const gx2d_id *,size_t,gx2d_point,double,gx2d_selection_target,gx2d_selection_ref *);
GX2D_API gx2d_status gx2d_selection_polygon_target(const gx2d_scene *,const gx2d_id *,size_t,const gx2d_point *,size_t,gx2d_selection_target,gx2d_selection_ref *,size_t,size_t *);


GX2D_API gx2d_status gx2d_add_layer(gx2d_scene *, const gx2d_layer_style *, gx2d_id *);
GX2D_API gx2d_status gx2d_get_layer(const gx2d_scene *, gx2d_id, gx2d_layer_style *);
GX2D_API gx2d_status gx2d_layer_ids(const gx2d_scene *, gx2d_id *, size_t, size_t *);
GX2D_API gx2d_status gx2d_set_layer(gx2d_scene *, gx2d_id, const gx2d_layer_style *);
GX2D_API gx2d_status gx2d_delete_layer(gx2d_scene *, gx2d_id);
GX2D_API gx2d_status gx2d_add_geometry(gx2d_scene *, gx2d_kind, const gx2d_point *, size_t, gx2d_id *);
GX2D_API gx2d_status gx2d_add_group(gx2d_scene *, const gx2d_id *, size_t, gx2d_id *);
GX2D_API gx2d_status gx2d_group_members(const gx2d_scene *, gx2d_id, gx2d_id *, size_t, size_t *);
GX2D_API gx2d_status gx2d_group_add_member(gx2d_scene *, gx2d_id, gx2d_id);
GX2D_API gx2d_status gx2d_group_remove_member(gx2d_scene *, gx2d_id, gx2d_id);
GX2D_API gx2d_status gx2d_group_contains(const gx2d_scene *, gx2d_id, gx2d_id, int *);
GX2D_API gx2d_status gx2d_ungroup(gx2d_scene *, gx2d_id);
/* Flat group expansion: request order, stable member order, first occurrence
 * wins. NULL output queries count. Transform never changes selection. Copies
 * preserve geometry/breaks/style/lock/direction, clear selection and keep
 * originals. Atomic failure removes every prepared copy; IDs are not reused. */
GX2D_API gx2d_status gx2d_expand_objects(const gx2d_scene *, const gx2d_id *,
    size_t, gx2d_id *, size_t, size_t *);
GX2D_API gx2d_status gx2d_affine_objects(gx2d_scene *, const gx2d_id *, size_t,
    const double matrix[6]); /* {a,b,c,d,tx,ty} */
GX2D_API gx2d_status gx2d_copy_affine_objects(gx2d_scene *, const gx2d_id *,
    size_t, const double matrix[6], gx2d_id *, size_t, size_t *);
/* Copy series retain native definitions and preserve sources. Rectangular
 * positions use rows*columns; circular positions use count and radians.
 * include_origin=0 omits position zero. Maximum 10,000 result objects and
 * 8,000,000 copied display vertices; the complete operation is atomic. */
typedef struct {
    int circular, include_origin, rotate_geometry;
    size_t rows, columns, positions;
    double spacing_x, spacing_y, angle_step;
    gx2d_point pivot;
} gx2d_series_spec;
GX2D_API gx2d_status gx2d_series_create(gx2d_scene *,const gx2d_id *,size_t,
    const gx2d_series_spec *,gx2d_id *objects,gx2d_id *sources,size_t capacity,size_t *count);
GX2D_API gx2d_status gx2d_reflection_matrix(gx2d_point axis_a, gx2d_point axis_b,
    double matrix[6]);
GX2D_API gx2d_status gx2d_rotation_matrix(gx2d_point pivot, double radians, double matrix[6]);
GX2D_API gx2d_status gx2d_scaling_matrix(gx2d_point pivot, gx2d_point scale, double matrix[6]);
GX2D_API gx2d_status gx2d_pivot_set(gx2d_scene *, gx2d_pivot_mode, gx2d_point);
GX2D_API gx2d_status gx2d_pivot_get(const gx2d_scene *, gx2d_pivot_mode *, gx2d_point *);
GX2D_API gx2d_status gx2d_gizmo_get(const gx2d_scene *, gx2d_gizmo *);
GX2D_API gx2d_status gx2d_gizmo_set(gx2d_scene *, const gx2d_gizmo *);
GX2D_API gx2d_status gx2d_gizmo_render(const gx2d_scene *, gx2d_overlay_primitive *, size_t, size_t *);
GX2D_API gx2d_status gx2d_gizmo_hit(const gx2d_scene *, gx2d_point device,
    double tolerance_px, gx2d_gizmo_handle *);
/* Absolute displacement/angle from gesture start, using the CORE world/view
 * projection. Render and hit remain readable during a native drag. */
GX2D_API gx2d_status gx2d_gizmo_parameters(const gx2d_scene *, gx2d_gizmo_handle,
    gx2d_point start_device, gx2d_point current_device, gx2d_gizmo_delta *);
GX2D_API gx2d_status gx2d_delete_object(gx2d_scene *, gx2d_id);
GX2D_API gx2d_status gx2d_object_ids(const gx2d_scene *, gx2d_id *, size_t, size_t *);
GX2D_API gx2d_status gx2d_kind_of(const gx2d_scene *, gx2d_id, gx2d_kind *);
GX2D_API gx2d_status gx2d_get_style(const gx2d_scene *, gx2d_id, gx2d_style *);
GX2D_API gx2d_status gx2d_set_style(gx2d_scene *, gx2d_id, const gx2d_style *);
GX2D_API gx2d_status gx2d_point_count(const gx2d_scene *, gx2d_id, size_t *);
GX2D_API gx2d_status gx2d_get_points(const gx2d_scene *, gx2d_id, gx2d_point *, size_t, size_t *);
GX2D_API gx2d_status gx2d_get_points_range(const gx2d_scene *, gx2d_id, size_t start, size_t count, gx2d_point *, size_t capacity, size_t *returned);
GX2D_API gx2d_status gx2d_replace_points(gx2d_scene *, gx2d_id, const gx2d_point *, size_t);
GX2D_API gx2d_status gx2d_append_points(gx2d_scene *, gx2d_id, const gx2d_point *, size_t);
/* One byte per incoming point: 1 breaks the edge from its predecessor.
 * Validation precedes the existing atomic append, including chunk seams. */
GX2D_API gx2d_status gx2d_append_points_with_gaps(gx2d_scene *, gx2d_id, const gx2d_point *, const unsigned char *, size_t);
GX2D_API gx2d_status gx2d_endpoints(const gx2d_scene *, gx2d_id, gx2d_point *, gx2d_point *);
GX2D_API gx2d_status gx2d_direction(const gx2d_scene *, gx2d_id, size_t segment, gx2d_point *); /* SIZE_MAX: global */
/* Logical per-curve marker state is independent of scientific point order.
 * Geometry changes retain normalized path anchor. Device primitives have
 * stable pixel dimensions under zoom/aspect/pan. Hidden markers do not hit. */
GX2D_API gx2d_status gx2d_direction_marker_get(const gx2d_scene *, gx2d_id, gx2d_direction_marker *);
GX2D_API gx2d_status gx2d_direction_marker_set(gx2d_scene *, gx2d_id, const gx2d_direction_marker *);
GX2D_API gx2d_status gx2d_direction_marker_attach(gx2d_scene *, gx2d_id from_curve, gx2d_id to_curve);
GX2D_API gx2d_status gx2d_direction_marker_render(const gx2d_scene *, gx2d_id, gx2d_direction_primitives *);
GX2D_API gx2d_status gx2d_direction_marker_hit(const gx2d_scene *, gx2d_id, gx2d_point device, double tolerance_px, int *);
GX2D_API gx2d_status gx2d_direction_marker_place(gx2d_scene *, gx2d_id, gx2d_point device, double *fraction);
GX2D_API gx2d_status gx2d_direction_marker_order(const gx2d_scene *, gx2d_id, size_t logical_count, size_t start, size_t count, size_t *source_indices);

GX2D_API gx2d_status gx2d_select_object(gx2d_scene *, gx2d_id, gx2d_select_mode);
GX2D_API gx2d_status gx2d_select_point(gx2d_scene *, gx2d_id, size_t, gx2d_select_mode);
GX2D_API gx2d_status gx2d_point_selected(const gx2d_scene *, gx2d_id, size_t, int *);
GX2D_API gx2d_status gx2d_select_rect(gx2d_scene *, gx2d_rect, gx2d_select_mode, gx2d_id *);
GX2D_API gx2d_status gx2d_remove_rect(gx2d_scene *, gx2d_id);
GX2D_API gx2d_status gx2d_clear_selection(gx2d_scene *);
/* Validates every index before replacing selection; no mutation during a drag. */
GX2D_API gx2d_status gx2d_selection_replace_points(gx2d_scene *, gx2d_id, const size_t *, size_t);
/* Atomically synchronize one bounded table page without losing selections
 * outside that page or rebuilding rectangle selection regions. */
GX2D_API gx2d_status gx2d_selection_patch_points(gx2d_scene *, gx2d_id, size_t start, size_t count, const size_t *, size_t);
GX2D_API gx2d_status gx2d_drag_is_active(const gx2d_scene *, int *);
GX2D_API gx2d_status gx2d_export_selected(const gx2d_scene *, gx2d_id, gx2d_point *, size_t, size_t *);

GX2D_API gx2d_status gx2d_nearest(const gx2d_scene *, gx2d_point, double max_distance, gx2d_hit *);
GX2D_API gx2d_status gx2d_hit_test(const gx2d_scene *, gx2d_id, gx2d_point, double tolerance, gx2d_hit *);
/* Point-only picking in the effective Native2D projection. Tolerance and
 * returned distance are device pixels; scientific coordinates stay exact. */
GX2D_API gx2d_status gx2d_hit_point_device(const gx2d_scene *, gx2d_id, gx2d_point device, double tolerance_px, gx2d_hit *);
GX2D_API gx2d_status gx2d_translate_selected(gx2d_scene *, double, double);
GX2D_API gx2d_status gx2d_rotate_selected(gx2d_scene *, gx2d_point pivot, double radians);
GX2D_API gx2d_status gx2d_drag_begin(gx2d_scene *);
GX2D_API gx2d_status gx2d_drag_translate(gx2d_scene *, double, double); /* absolute displacement from drag begin */
GX2D_API gx2d_status gx2d_drag_rotate(gx2d_scene *, gx2d_point, double); /* absolute angle from drag begin */
GX2D_API gx2d_status gx2d_drag_commit(gx2d_scene *);
GX2D_API gx2d_status gx2d_drag_cancel(gx2d_scene *);
GX2D_API gx2d_status gx2d_snap_point(gx2d_scene *, gx2d_id, size_t, gx2d_id, size_t);
GX2D_API gx2d_status gx2d_snap_to_curve(gx2d_scene *, gx2d_id, size_t, gx2d_id);

GX2D_API gx2d_status gx2d_add_constraint(gx2d_scene *, const gx2d_constraint *, gx2d_id *);
GX2D_API gx2d_status gx2d_remove_constraint(gx2d_scene *, gx2d_id);
/* Additive extended constraint descriptors leave the legacy POD ABI intact.
 * Legacy v2 creation validates native mutations. The additive retained-component
 * apply/solve APIs below provide driving while leaving legacy POD contracts intact. Point-on-curve supports lines, polylines and similarity circles;
 * unsupported retained families return explicit diagnostic status. */
typedef struct {
    gx2d_constraint base;
    gx2d_id axis;size_t axis_index;
    int disabled,anchor_valid;
    gx2d_point anchor;
    double angular_tolerance; /* tangent relationship's separate radians */
} gx2d_constraint_v2;
typedef struct {
    int valid,geometry_supported,enabled;
    double value,residual,angular_residual;
} gx2d_constraint_diagnostic;
GX2D_API gx2d_status gx2d_constraint_create(gx2d_scene *,const gx2d_constraint_v2 *,gx2d_id *);
GX2D_API gx2d_status gx2d_constraint_get(const gx2d_scene *,gx2d_id,gx2d_constraint_v2 *);
GX2D_API gx2d_status gx2d_constraint_ids(const gx2d_scene *,gx2d_id *,size_t,size_t *);
GX2D_API gx2d_status gx2d_constraint_update(gx2d_scene *,gx2d_id,const gx2d_constraint_v2 *);
GX2D_API gx2d_status gx2d_constraint_enable(gx2d_scene *,gx2d_id,int enabled);
GX2D_API gx2d_status gx2d_constraint_validate(const gx2d_scene *,gx2d_id,gx2d_constraint_diagnostic *);
/* dev-053 interaction extensions. No legacy POD layout changes. References
 * capture existing topology/parameter epochs, never a display tessellation ID.
 * Encoded indices extend the existing constraint reference namespace: ordinary
 * legacy indices retain their meaning. Clients obtain indices from this API. */
#define GX2D_CONTROL_INDEX ((size_t)1000000000)
#define GX2D_SEGMENT_INDEX ((size_t)2000000000)
#define GX2D_OBJECT_INDEX ((size_t)3000000000)
typedef enum { GX2D_ENTITY_OBJECT=0, GX2D_ENTITY_CONTROL, GX2D_ENTITY_SEGMENT } gx2d_entity;
typedef struct { gx2d_id object; gx2d_entity entity; size_t index; uint64_t epoch; } gx2d_reference;
typedef enum { GX2D_CONTROL_POSITION=0, GX2D_CONTROL_ENDPOINT, GX2D_CONTROL_CENTER,
    GX2D_CONTROL_RADIUS, GX2D_CONTROL_ARC_START, GX2D_CONTROL_ARC_END,
    GX2D_CONTROL_AXIS_X, GX2D_CONTROL_AXIS_Y, GX2D_CONTROL_CORNER,
    GX2D_CONTROL_BEZIER } gx2d_control_role;
typedef struct { gx2d_reference reference; gx2d_point point; gx2d_control_role role; } gx2d_control;
GX2D_API gx2d_status gx2d_sketch_construct(gx2d_sketch_family,const gx2d_point *,size_t,
    gx2d_sketch_definition *,gx2d_point *,size_t);
GX2D_API gx2d_status gx2d_sketch_preview_definition(gx2d_sketch_family,const gx2d_point *,size_t,
    gx2d_sketch_definition *,gx2d_point *,size_t);
GX2D_API gx2d_status gx2d_sketch_from_fit(gx2d_sketch_family,const double *,size_t,
    gx2d_sketch_definition *,gx2d_point *,size_t);
GX2D_API gx2d_status gx2d_sketch_controls(const gx2d_scene *,gx2d_id,gx2d_control *,size_t,size_t *);
GX2D_API gx2d_status gx2d_reference_create(const gx2d_scene *,gx2d_id,gx2d_entity,size_t,gx2d_reference *);
/* Map an existing constraint/measurement semantic index to a checked reference. */
GX2D_API gx2d_status gx2d_reference_from_index(const gx2d_scene *,gx2d_id,size_t,gx2d_reference *);
GX2D_API gx2d_status gx2d_reference_point_index(const gx2d_scene *,const gx2d_reference *,size_t *);
GX2D_API gx2d_status gx2d_reference_resolve(const gx2d_scene *,const gx2d_reference *,gx2d_point *);
/* Read-only device paths for semantic segment feedback; retained curved leaves
 * are evaluated exactly, not selected through display-sample indices. */
GX2D_API gx2d_status gx2d_reference_render(const gx2d_scene *,const gx2d_reference *,gx2d_point *,size_t,size_t *);
GX2D_API gx2d_status gx2d_interaction_pick(const gx2d_scene *,gx2d_id,gx2d_point,double,gx2d_reference *);
GX2D_API gx2d_status gx2d_control_definition(const gx2d_scene *,const gx2d_reference *,gx2d_point,
    gx2d_sketch_definition *,gx2d_point *,size_t);
/* Deep-owned edit candidate, including exact Path leaves and shared junctions.
 * Existing Tcl/Python/Octave control_definition uses this ownership-safe form. */
GX2D_API gx2d_status gx2d_control_definition_owned(const gx2d_scene *,const gx2d_reference *,gx2d_point,
    gx2d_sketch_definition **);
GX2D_API void gx2d_control_definition_release(gx2d_sketch_definition *);
GX2D_API gx2d_status gx2d_control_edit(gx2d_scene *,const gx2d_reference *,gx2d_point);
/* Read-only candidate query: excludes caller's objects, prefers true controls,
 * then straight-segment midpoints, then existing grid. 0=no snap, 1=control,
 * 2=midpoint, 3=grid, 4=endpoint, 5=center. Placement never creates a relationship. */
GX2D_API gx2d_status gx2d_placement_snap(const gx2d_scene *,gx2d_point,double,
    const gx2d_id *,size_t,int,int,gx2d_point *,int *,gx2d_reference *);
/* Compatibility is structural. Query returns measured defaults, or INVALID
 * for unsupported/incomplete selection. Apply drives only supported direct
 * edits and validates every other active relationship atomically. */
GX2D_API gx2d_status gx2d_constraint_from_selection(const gx2d_scene *,gx2d_constraint_kind,
    const gx2d_reference *,size_t,gx2d_constraint_v2 *);
GX2D_API gx2d_status gx2d_constraint_apply(gx2d_scene *,gx2d_id,const gx2d_constraint_v2 *,gx2d_id *);
GX2D_API gx2d_status gx2d_constraint_location(const gx2d_scene *,gx2d_id,gx2d_point *);
/* dev-054: bounded retained-sketch component solver and relationship presentation.
 * Existing rule IDs, reference namespace and v2 POD ABI remain unchanged.
 * Numeric rank is local at the current geometry; singular configurations report
 * this explicitly, never claim global uniqueness. Expressions are not parsed here. */
typedef struct { int solved,driven,placed; gx2d_point annotation; int branch; double curvature_tolerance; } gx2d_relationship_state;
typedef struct { size_t parameters,rank,degrees_of_freedom; int valid,analysis_complete; } gx2d_sketch_status;
typedef struct { gx2d_point lines[96];size_t line_count;gx2d_point label;
    gx2d_rect hit_bounds;double value;int driven,angular; } gx2d_dimension_geometry;
GX2D_API gx2d_status gx2d_constraint_create_state(gx2d_scene *,const gx2d_constraint_v2 *,const gx2d_relationship_state *,gx2d_id *);
GX2D_API gx2d_status gx2d_relationship_get(const gx2d_scene *,gx2d_id,gx2d_relationship_state *);
GX2D_API gx2d_status gx2d_relationship_set(gx2d_scene *,gx2d_id,const gx2d_relationship_state *);
GX2D_API gx2d_status gx2d_sketch_component_ids(const gx2d_scene *,gx2d_id,gx2d_id *,size_t,size_t *);
GX2D_API gx2d_status gx2d_sketch_status_get(gx2d_scene *,gx2d_id,gx2d_sketch_status *);
GX2D_API gx2d_status gx2d_sketch_solve_control(gx2d_scene *,const gx2d_reference *,gx2d_point);
GX2D_API gx2d_status gx2d_sketch_solve_definition(gx2d_scene *,gx2d_id,const gx2d_sketch_definition *);
GX2D_API gx2d_status gx2d_dimension_apply(gx2d_scene *,gx2d_id,const gx2d_constraint_v2 *,int,gx2d_point,gx2d_id *);
GX2D_API gx2d_status gx2d_dimension_infer(const gx2d_scene *,const gx2d_reference *,size_t,gx2d_point,gx2d_constraint_v2 *);
GX2D_API gx2d_status gx2d_dimension_preview(const gx2d_scene *,const gx2d_constraint_v2 *,gx2d_point,gx2d_dimension_geometry *);
GX2D_API gx2d_status gx2d_dimension_primitives(const gx2d_scene *,gx2d_id,gx2d_dimension_geometry *);
GX2D_API gx2d_status gx2d_relationship_hit(const gx2d_scene *,gx2d_id,gx2d_point,gx2d_rect,int *);
/* Ranked device hit: negative values prefer the nearest label center, then
 * 0..7 pixel witness distances; DBL_MAX means no hit. Presentation bounds are
 * supplied by the renderer; all proximity/priority semantics belong to CORE. */
GX2D_API gx2d_status gx2d_relationship_hit_score(const gx2d_scene *,gx2d_id,gx2d_point,gx2d_rect,double *);
/* dev-055 construction placement. REFERENCE resolves a checked existing
 * defining control; EARLIER resolves a previous placement in this request.
 * Attachment uses existing persistent Coincident rules, not coordinate equality.
 * Outputs and existing geometry are unchanged on failure. IDs remain monotonic.
 * Curves with coincident endpoints are not claimed to be periodic splines. */
typedef enum { GX2D_PLACEMENT_FREE=0,GX2D_PLACEMENT_REFERENCE=1,GX2D_PLACEMENT_EARLIER=2 } gx2d_placement_mode;
/* Straight/curved references project point through the existing finite-edge /
 * retained closest-point kernel; controls still resolve their defining point.
 * The existing POD layout is unchanged. */
typedef struct { gx2d_point point;gx2d_placement_mode mode;gx2d_reference reference;size_t earlier; } gx2d_construction_placement;
GX2D_API gx2d_status gx2d_construction_resolve(const gx2d_scene *,const gx2d_construction_placement *,size_t,gx2d_point *,size_t);
GX2D_API gx2d_status gx2d_construction_preview(const gx2d_scene *,gx2d_sketch_family,const gx2d_construction_placement *,size_t,gx2d_sketch_definition *,gx2d_point *,size_t);
GX2D_API gx2d_status gx2d_references_connected(const gx2d_scene *,const gx2d_reference *,const gx2d_reference *,int *);
GX2D_API gx2d_status gx2d_construction_pick(const gx2d_scene *,gx2d_point,double,const gx2d_construction_placement *,size_t,const gx2d_id *,size_t,int,gx2d_construction_placement *);
GX2D_API gx2d_status gx2d_symmetry_preview(const gx2d_scene *,const gx2d_reference *,const gx2d_sketch_definition *,gx2d_sketch_definition *);
GX2D_API gx2d_status gx2d_symmetry_attach(gx2d_scene *,gx2d_id,const gx2d_reference *,gx2d_id *,gx2d_id *);
GX2D_API gx2d_status gx2d_symmetry_construct(gx2d_scene *,const gx2d_reference *,const gx2d_sketch_definition *,size_t,gx2d_id [3]);
GX2D_API gx2d_status gx2d_sketch_create_attached(gx2d_scene *,gx2d_sketch_family,const gx2d_construction_placement *,size_t,size_t,const gx2d_reference *,size_t,gx2d_id *,gx2d_id *,size_t,size_t *,gx2d_reference *,int *);
/* Actual device-coordinate clipping; scientific coordinates stay unchanged. */
GX2D_API gx2d_status gx2d_viewport_clip_segment(const gx2d_scene *,gx2d_point,gx2d_point,
    double,gx2d_point *,gx2d_point *,int *);
/* Optional immediate merge of A onto B plus one persistent coincidence rule.
 * Merge supports generic points and retained point/line or Bezier/spline/
 * polyline endpoints; other primitives require explicit parameter edits first.
 * Native definitions/caches/existing constraints/new relation commit together. */
GX2D_API gx2d_status gx2d_join_points(gx2d_scene *,gx2d_id a,size_t a_index,
    gx2d_id b,size_t b_index,int merge,double tolerance,gx2d_id *constraint);

/* Structured scientific measurements reuse native geometry authorities. */
typedef enum {
    GX2D_MEASURE_POINT_DISTANCE=1,GX2D_MEASURE_HORIZONTAL_DISTANCE,
    GX2D_MEASURE_VERTICAL_DISTANCE,GX2D_MEASURE_SEGMENT_LENGTH,
    GX2D_MEASURE_SEGMENT_ANGLE,GX2D_MEASURE_TANGENT_ANGLE,
    GX2D_MEASURE_PATH_LENGTH,GX2D_MEASURE_RADIUS,GX2D_MEASURE_DIAMETER,
    GX2D_MEASURE_ARC_ANGLE,GX2D_MEASURE_BOUNDING_WIDTH,
    GX2D_MEASURE_BOUNDING_HEIGHT,GX2D_MEASURE_SIGNED_AREA,
    GX2D_MEASURE_POINT_CURVE_DISTANCE,GX2D_MEASURE_OBJECT_DISTANCE
} gx2d_measurement_kind;
typedef struct {
    gx2d_measurement_kind kind;gx2d_id a,b;size_t a_index,b_index;
    size_t pair_budget; /* 0 => 1,000,000 exact supported segment pairs */
} gx2d_measurement_spec;
typedef struct {
    double value;int unit_power,angular,exact;gx2d_point point_a,point_b;
    const char *policy; /* static diagnostic string, no caller ownership */
} gx2d_measurement;
GX2D_API gx2d_status gx2d_measure(const gx2d_scene *,const gx2d_measurement_spec *,gx2d_measurement *);
GX2D_API gx2d_status gx2d_curve_nearest_point(const gx2d_scene *,gx2d_id,
    gx2d_point query,gx2d_segment_hit *);
GX2D_API gx2d_status gx2d_check_constraints(const gx2d_scene *);
GX2D_API gx2d_status gx2d_align_direction(gx2d_scene *, gx2d_id moving, gx2d_id reference,
                                  double relative_radians, gx2d_point pivot);

/* Generic planar edits. Indices are zero based; ranges include both endpoints. */
GX2D_API gx2d_status gx2d_insert_point(gx2d_scene *, gx2d_id, size_t, gx2d_point);
GX2D_API gx2d_status gx2d_remove_point(gx2d_scene *, gx2d_id, size_t);
GX2D_API gx2d_status gx2d_set_point(gx2d_scene *, gx2d_id, size_t, gx2d_point);
GX2D_API gx2d_status gx2d_reverse_points(gx2d_scene *, gx2d_id);
GX2D_API gx2d_status gx2d_move_point(gx2d_scene *, gx2d_id, size_t from, size_t to);
GX2D_API gx2d_status gx2d_select_x_interval(gx2d_scene *, gx2d_id, double xmin, double xmax, gx2d_select_mode);
/* A break after point i suppresses the segment i -> i+1. */
GX2D_API gx2d_status gx2d_set_breaks(gx2d_scene *, gx2d_id, const size_t *, size_t);
GX2D_API gx2d_status gx2d_get_breaks(const gx2d_scene *, gx2d_id, size_t *, size_t, size_t *);
GX2D_API gx2d_status gx2d_extract_range(gx2d_scene *, gx2d_id, size_t, size_t, gx2d_id *);
GX2D_API gx2d_status gx2d_keep_range(gx2d_scene *, gx2d_id, size_t, size_t);
GX2D_API gx2d_status gx2d_remove_range(gx2d_scene *, gx2d_id, size_t, size_t);
GX2D_API gx2d_status gx2d_split(gx2d_scene *, gx2d_id, size_t, gx2d_id *, gx2d_id *);
GX2D_API gx2d_status gx2d_concatenate(gx2d_scene *, const gx2d_id *, const int *, size_t, gx2d_id *);
GX2D_API gx2d_status gx2d_concatenate_parts(gx2d_scene *, const gx2d_id *, const int *reverse,
    const int *break_before, size_t, gx2d_id *);
GX2D_API gx2d_status gx2d_object_bounds(const gx2d_scene *, gx2d_id, gx2d_rect *);
GX2D_API gx2d_status gx2d_scene_bounds(const gx2d_scene *, int selected_only, gx2d_rect *);
GX2D_API gx2d_status gx2d_selected_points(const gx2d_scene *, gx2d_id, gx2d_selected_point *, size_t, size_t *);
GX2D_API gx2d_status gx2d_nearest_segment(const gx2d_scene *, gx2d_id, gx2d_point, gx2d_segment_hit *);
GX2D_API gx2d_status gx2d_nearest_spline(const gx2d_scene *, gx2d_id, gx2d_point, size_t subdivisions, gx2d_segment_hit *);
GX2D_API gx2d_status gx2d_path_length(const gx2d_scene *, gx2d_id, double *);
GX2D_API gx2d_status gx2d_path_point(const gx2d_scene *, gx2d_id, double, gx2d_segment_hit *);
/* Geometry deviation uses bounded scientific Native samples, independent of
 * viewport; retained definitions are evaluated directly. Hausdorff/RMS are
 * sampled estimates with explicit policy, never claimed as continuous extrema. */
typedef struct {
    size_t count_a,count_b,max_index;
    double max_absolute,mean_absolute,rmse,symmetric_rmse,hausdorff_sampled;
    double length_difference,area_difference,closest_distance;
    int area_supported,projection_exact_a,projection_exact_b,closest_exact;
    gx2d_point closest_a,closest_b;
    const char *sampling_a,*sampling_b;
} gx2d_geometry_comparison;
GX2D_API gx2d_status gx2d_compare_geometry(const gx2d_scene *,gx2d_id,gx2d_id,size_t,
    gx2d_geometry_comparison *,gx2d_residual *,size_t);
GX2D_API gx2d_status gx2d_curve_metrics(const gx2d_scene *, gx2d_id, gx2d_metrics *);
/* Catmull-Rom geometric interpolation over ordered control points. */
GX2D_API gx2d_status gx2d_sample_spline(const gx2d_scene *, gx2d_id, size_t per_segment, gx2d_point *, size_t, size_t *);
GX2D_API gx2d_status gx2d_sample_spline_range(const gx2d_scene *, gx2d_id,
    size_t first_segment, size_t segment_count, size_t per_segment,
    gx2d_point *, size_t capacity, size_t *count);
GX2D_API gx2d_status gx2d_sample_spline_object(gx2d_scene *, gx2d_id,
    size_t per_segment, gx2d_id *);
GX2D_API gx2d_status gx2d_compare_curves(const gx2d_scene *, gx2d_id reference, gx2d_id derived,
    gx2d_compare_method, gx2d_residual *, size_t, gx2d_residual_summary *);
/* Exact full-input summary plus ordered CORE extrema presentation. Output and
 * scratch memory are bounded by budget (6..65536), independently of input size.
 * row_indices are ordinals in the complete residual result, never LOD science. */
GX2D_API gx2d_status gx2d_compare_curves_display(const gx2d_scene *, gx2d_id reference, gx2d_id derived,
    gx2d_compare_method, size_t budget, gx2d_residual *, uint64_t *row_indices, size_t capacity, size_t *returned, gx2d_residual_summary *);

/* Portable presentation snapshot; applying it never edits scientific geometry. */
typedef struct {gx2d_view view;gx2d_grid grid;gx2d_color background;gx2d_aspect_mode aspect;gx2d_polar_frame polar;gx2d_coordinate_mode coordinate_mode;} gx2d_view_state;
GX2D_API gx2d_status gx2d_view_state_get(const gx2d_scene *,gx2d_view_state *);
GX2D_API gx2d_status gx2d_view_state_set(gx2d_scene *,const gx2d_view_state *);
GX2D_API gx2d_status gx2d_view_state_rescale(const gx2d_view_state *,double,gx2d_view_state *);

/* Renderer-neutral view; coordinates returned in viewport pixels. */
GX2D_API gx2d_status gx2d_view_set(gx2d_scene *, const gx2d_view *);
GX2D_API gx2d_status gx2d_view_get(const gx2d_scene *, gx2d_view *);
GX2D_API gx2d_status gx2d_view_requested(const gx2d_scene *, gx2d_view *);
GX2D_API gx2d_status gx2d_view_aspect_set(gx2d_scene *, gx2d_aspect_mode);
GX2D_API gx2d_status gx2d_view_aspect_get(const gx2d_scene *, gx2d_aspect_mode *);
GX2D_API gx2d_status gx2d_view_fit(gx2d_scene *, gx2d_id); /* 0 fits visible scene */
GX2D_API gx2d_status gx2d_view_fit_selected(gx2d_scene *);
GX2D_API gx2d_status gx2d_view_fit_bounds(gx2d_scene *, gx2d_rect);
GX2D_API gx2d_status gx2d_world_to_device(const gx2d_scene *, gx2d_point, gx2d_point *);
GX2D_API gx2d_status gx2d_device_to_world(const gx2d_scene *, gx2d_point, gx2d_point *);
GX2D_API gx2d_status gx2d_view_zoom(gx2d_scene *, double factor, gx2d_point device_anchor);
GX2D_API gx2d_status gx2d_view_pan(gx2d_scene *, double device_dx, double device_dy);
GX2D_API gx2d_status gx2d_pixel_tolerance(const gx2d_scene *, double pixels, double *world_x, double *world_y);
GX2D_API gx2d_status gx2d_render_points(const gx2d_scene *, gx2d_id, gx2d_point *, size_t, size_t *);
GX2D_API gx2d_status gx2d_background_get(const gx2d_scene *, gx2d_color *);
GX2D_API gx2d_status gx2d_background_set(gx2d_scene *, gx2d_color);
GX2D_API gx2d_status gx2d_grid_get(const gx2d_scene *, gx2d_grid *);
GX2D_API gx2d_status gx2d_grid_set(gx2d_scene *, const gx2d_grid *);
GX2D_API gx2d_status gx2d_presentation_set(gx2d_scene *, const gx2d_grid *, gx2d_color background, gx2d_aspect_mode);
/* Bounded/clipped device primitives. Presentation suppression never changes
 * logical spacing. Native snap uses round-half-away-from-zero in grid space. */
GX2D_API gx2d_status gx2d_grid_render(const gx2d_scene *, gx2d_grid_segment *, size_t capacity, size_t *count);
GX2D_API gx2d_status gx2d_grid_snap(const gx2d_scene *, gx2d_point world, unsigned axes, gx2d_point *snapped); /* 1 X,2 Y,3 both */
GX2D_API gx2d_status gx2d_grid_translation(const gx2d_scene *, gx2d_point pivot, gx2d_point proposed_delta, unsigned axes, gx2d_point *snapped_delta);
/* Experimental polar frame. Conversion outputs/inputs respect degrees;
 * frame descriptors use radians. Conversion never changes geometry. */
GX2D_API gx2d_status gx2d_polar_frame_get(const gx2d_scene *, gx2d_polar_frame *);
GX2D_API gx2d_status gx2d_polar_frame_set(gx2d_scene *, const gx2d_polar_frame *);
GX2D_API gx2d_status gx2d_coordinate_mode_get(const gx2d_scene *, gx2d_coordinate_mode *);
GX2D_API gx2d_status gx2d_coordinate_mode_set(gx2d_scene *, gx2d_coordinate_mode);
GX2D_API gx2d_status gx2d_presentation_frame_set(gx2d_scene *, const gx2d_grid *, gx2d_color, gx2d_aspect_mode, const gx2d_polar_frame *, gx2d_coordinate_mode);
GX2D_API gx2d_status gx2d_angle_normalize(double value, int degrees, double *normalized);
GX2D_API gx2d_status gx2d_cartesian_to_polar(const gx2d_scene *, gx2d_point world, gx2d_point *radius_angle);
/* Complete finite input, atomic outputs. Origin has radius=angle=0 and
 * angle_defined=0; callers must preserve that explicit undefined-angle mask. */
GX2D_API gx2d_status gx2d_cartesian_to_polar_many(const gx2d_scene *, const gx2d_point *, size_t, gx2d_point *radius_angle, unsigned char *angle_defined);
GX2D_API gx2d_status gx2d_polar_to_cartesian(const gx2d_scene *, gx2d_point radius_angle, gx2d_point *world);
GX2D_API gx2d_status gx2d_polar_snap(const gx2d_scene *, gx2d_point world, unsigned axes, gx2d_point *snapped); /* 1 radius,2 angle,3 both */
GX2D_API gx2d_status gx2d_polar_grid_render(const gx2d_scene *, gx2d_grid_segment *, size_t capacity, size_t *count);
/* Streaming display proxy, never a scientific replacement for its source.
 * Push bounded XY chunks in increasing contiguous logical-row order. Nonfinite
 * XY rows are omitted. Results preserve exact zero-based source-row identities
 * and full finite-source bounds. Memory is bounded by display budget. */
GX2D_API gx2d_display_accumulator *gx2d_display_begin(size_t logical_rows, size_t budget, uint64_t source_row_base);
GX2D_API gx2d_status gx2d_display_push(gx2d_display_accumulator *, size_t start, const gx2d_point *, size_t count);
GX2D_API gx2d_status gx2d_display_push_rows(gx2d_display_accumulator *, size_t start, const gx2d_point *, const uint64_t *source_rows, size_t count);
GX2D_API gx2d_status gx2d_display_result(const gx2d_display_accumulator *, gx2d_point *, uint64_t *source_rows, size_t capacity, size_t *count, size_t *finite_rows, gx2d_rect *full_bounds);
GX2D_API gx2d_status gx2d_display_breaks(const gx2d_display_accumulator *, size_t *break_indices, size_t capacity, size_t *count);
GX2D_API gx2d_status gx2d_display_mark_break(gx2d_display_accumulator *);
GX2D_API void gx2d_display_destroy(gx2d_display_accumulator *);
GX2D_API gx2d_status gx2d_object_display(const gx2d_scene *, gx2d_id, size_t budget, gx2d_point *device_points, uint64_t *point_indices, size_t capacity, size_t *count, size_t *break_indices, size_t break_capacity, size_t *break_count);
GX2D_API gx2d_status gx2d_object_sample(const gx2d_scene *, gx2d_id, size_t budget, gx2d_point *world_points, uint64_t *point_indices, size_t capacity, size_t *count, size_t *break_indices, size_t break_capacity, size_t *break_count);
/* Read-only curve presentation. Native interpolation, when enabled, is sampled
 * in bounded chunks then reduced natively; source controls remain unchanged.
 * Returned indices identify the original control segment for interpolated
 * points. Explicit breaks are preserved. No temporary scene object is added. */
GX2D_API gx2d_status gx2d_curve_display(const gx2d_scene *, gx2d_id, size_t budget,
    gx2d_point *device_points,uint64_t *control_indices,size_t capacity,size_t *count,
    size_t *break_indices,size_t break_capacity,size_t *break_count);
/* Bounded Numeric input marshalling: finite XY pairs as interleaved IEEE
 * float64 little endian, exact original row IDs as uint64 little endian.
 * Nonfinite pairs are omitted together; this is an explicit input policy. */
GX2D_API gx2d_status gx2d_numeric_pack(const gx2d_point *, const uint64_t *source_rows, uint64_t row_base, size_t count, unsigned char *xy, size_t xy_capacity, unsigned char *rows, size_t rows_capacity, size_t *finite_count);

GX2D_API gx2d_status gx2d_composition_retarget(gx2d_scene *,gx2d_id,const gx2d_id *,size_t);
GX2D_API gx2d_status gx2d_constraint_values(gx2d_scene *,const gx2d_id *,const double *,size_t);
#ifdef __cplusplus
}
#endif
#endif

