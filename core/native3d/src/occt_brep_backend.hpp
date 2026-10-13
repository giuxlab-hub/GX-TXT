/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_OCCT_BREP_BACKEND_HPP
#define GX3DE_OCCT_BREP_BACKEND_HPP

#include "native_3d_engine_api_v1.h"
#include <memory>
#include <string>
#include <vector>

class TopoDS_Shape;

namespace gx3de_backend {

/* The native TopoDS_Shape is deliberately hidden from the public C ABI. */
struct BrepShape;
struct BrepSegment { gx3de_vec3 a, b; };
struct BrepTopologyCounts { uint64_t vertices, edges, faces; };
struct BrepValidation { bool topology_valid, closed_oriented_solids; uint64_t solids, shells, faces; };
struct BrepFaceAnchor { gx3de_vec3 point, normal; };
struct MeshData;
struct ProfileContour;
bool extrude_profile(const std::vector<ProfileContour>& contours,
    gx3de_vec3 origin,gx3de_vec3 u,gx3de_vec3 v,double signed_distance,
    std::shared_ptr<BrepShape>& out,std::string& error);
bool write_step(const BrepShape& shape,const std::string& path,double millimeters_per_unit,std::string& error);
/* Display-only tessellation of an immutable B-Rep copy. Triangle IDs are
 * renderer-local and do not represent persistent OCCT topology. */
bool tessellate_for_render(const BrepShape& shape,MeshData& output,std::string& error);
/* Explicit-quality conversion of an immutable generic B-Rep. Uses the same
 * guarded OCCT tessellator as STEP prototypes. */
bool tessellate_brep(const BrepShape& shape,double linear_deflection,
    double angular_deflection,double weld_tolerance,uint64_t max_triangles,
    uint64_t max_output_bytes,MeshData& output,std::string& error);

bool create_box(double x, double y, double z,
                std::shared_ptr<BrepShape>& out, std::string& error);
bool create_cylinder(double radius,double height,
                     std::shared_ptr<BrepShape>& out,std::string& error);

/* Retain a STEP/XDE part definition as an immutable B-Rep. TopoDS_Shape is a
 * reference-counted native handle, so the retained shape remains alive after
 * the source XDE document is closed. No occurrence transform is baked in. */
bool adopt_step_shape(const TopoDS_Shape& native,
                      std::shared_ptr<BrepShape>& out, std::string& error);

/* Exact OCCT intersection, returned as sampled 3D edge segments. Curved edges
 * are sampled to a chordal deflection of max(1e-7, 1e-5 * shape diagonal).
 * The underlying B-Rep is not tessellated or modified. Empty intersection is
 * successful with an empty segment vector. */
bool section(const BrepShape& shape, gx3de_vec3 origin, gx3de_vec3 normal,
             std::vector<BrepSegment>& out, std::string& error);

/* op: 1 union, 2 intersection, 3 difference (a minus b). */
bool boolean_op(const BrepShape& a, const BrepShape& b, int op,
                std::shared_ptr<BrepShape>& out, std::string& error);

/* Clip a closed solid against a plane, retaining the positive or negative
 * normal side. A successful empty result is represented by a null out pointer.
 * The source B-Rep remains immutable. The intersection creates a capping face.
 */
bool clip_halfspace(const BrepShape& shape, gx3de_vec3 origin,
                    gx3de_vec3 normal, bool keep_positive,
                    std::shared_ptr<BrepShape>& out, std::string& error);

/* Topology indices are 1-based and refer only to this exact immutable shape.
 * They must not be persisted across a Boolean, clip, rebuild or import.
 * edge_fraction and face_u/v_fraction are normalized parameter coordinates,
 * not arc-length or geodesic coordinates. Face queries reject coordinates
 * outside trimmed faces. A face's returned normal is outward with respect to
 * its TopoDS orientation. */
bool topology_counts(const BrepShape& shape, BrepTopologyCounts& out);
bool edge_geometry(const BrepShape& shape,uint64_t edge_index,double length_tolerance,
                   gx3de_brep_edge_geometry& out,std::string& error);
bool face_geometry(const BrepShape& shape,uint64_t face_index,
                   gx3de_brep_face_geometry& out,std::string& error);
/* Reports intrinsic topology of this exact immutable shape, independent of
 * object placement. Invalid topology is a successful diagnostic result. */
bool validate(const BrepShape& shape, BrepValidation& out, std::string& error);
/* ShapeFix runs on a deep copy. Only a shape that becomes valid, closed and
 * oriented with guarded volume/area/bounds is returned. Already valid closed
 * solids retain the same immutable topology. */
bool heal_solid(const BrepShape& shape,double tolerance,
                std::shared_ptr<BrepShape>& out,std::string& error);
bool vertex_anchor(const BrepShape& shape, uint64_t vertex_index,
                   gx3de_vec3& point, std::string& error);
bool edge_anchor(const BrepShape& shape, uint64_t edge_index, double edge_fraction,
                 gx3de_vec3& point, gx3de_vec3& tangent, std::string& error);
bool face_anchor(const BrepShape& shape, uint64_t face_index,
                 double face_u_fraction, double face_v_fraction,
                 BrepFaceAnchor& out, std::string& error);
/* Locate a unique trimmed face near a display hit in shape-local coordinates.
 * Returns false for no close face or ambiguity at shared topology. Indices
 * refer only to this exact shape and must not survive rebuilding/booleans. */
bool closest_face_fraction(const BrepShape& shape,gx3de_vec3 local_point,
    double tolerance,uint64_t& face_zero_based,double& u_fraction,
    double& v_fraction,std::string& error);

/* Applies a finite, non-singular, column-major affine matrix to a copy. */
bool transformed(const BrepShape& shape, const gx3de_mat4& transform,
                 std::shared_ptr<BrepShape>& out, std::string& error);

/* False for a null/empty shape. */
bool bounds(const BrepShape& shape, gx3de_bounds& out);

/* Surface area is always defined for a non-null shape. Volume is NaN if the
 * shape contains no solids; the caller must not present it as enclosed volume. */
bool properties(const BrepShape& shape, double& area, double& volume);

/* SHA-256 of the immutable, unplaced B-Rep serialization. The digest includes
 * namespace and OCCT version; it does not identify subshapes across rebuilds. */
bool shape_fingerprint(const BrepShape& shape,const std::string& namespace_utf8,
                       std::string& out,std::string& error);

} // namespace gx3de_backend
#endif
