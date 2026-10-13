/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_VTK_MESH_BACKEND_HPP
#define GX3DE_VTK_MESH_BACKEND_HPP

#include "native_3d_engine_api_v1.h"
#include "mesh_prep_backend.hpp"
#include <cstdint>
#include <string>
#include <vector>

namespace gx3de_backend {

/* A world-space, unoriented edge of a plane/triangle-mesh intersection. */
struct Segment {
    gx3de_vec3 a, b;
};

/*
 * Cut a triangle mesh using vtkCutter for strictly transverse intersections
 * and explicit triangle classification when source vertices lie on the plane.
 * `triangles` contains consecutive index triples. On success, out contains
 * sorted, unique nonzero 3D segments, or is empty when the plane misses.
 * Coplanar triangles contribute their external patch boundary, omitting
 * subdivisions from partial overlaps and T junctions. Exact plane
 * coincidence is used; profile joining has its own explicit tolerance.
 * Duplicate faces and ambiguous or non-manifold patch topology fail.
 * The function does not infer closed contours or fill coincident faces.
 * On failure, out is empty and error describes the invalid input or backend
 * failure. No renderer, display, or process-global scene state is involved.
 */
bool vtk_section(const std::vector<gx3de_vec3>& world_vertices,
                 const std::vector<uint32_t>& triangles,
                 gx3de_vec3 origin,
                 gx3de_vec3 normal,
                 std::vector<Segment>& out,
                 std::string& error);

/* Unsigned Euclidean distance to the closest triangle surface point. The
 * mesh must contain at least one nondegenerate triangle. `distance` changes
 * only on success. Uses a local VTK locator and creates no renderer/state. */
bool vtk_point_surface_distance(const std::vector<gx3de_vec3>& world_vertices,
                                const std::vector<uint32_t>& triangles,
                                gx3de_vec3 point,
                                double& distance,
                                std::string& error,
                                gx3de_vec3* closest_world_point = nullptr);
/* One full-surface locator for a bounded scientific query batch. */
bool vtk_surface_query_batch(const std::vector<gx3de_vec3>& vertices,
                             const std::vector<uint32_t>& triangles,
                             const std::vector<gx3de_vec3>& queries,
                             std::vector<double>& distances,
                             std::vector<gx3de_vec3>& closest,
                             std::string& error);

/* Keep the positive or negative half-space of a world-space triangle mesh.
 * VTK clips faces at the plane and triangulates survivors; the cut is not
 * capped, so a closed input will generally produce an open output. On an
 * invalid input or backend failure, output remains unchanged. */
bool vtk_clip_mesh(const std::vector<gx3de_vec3>& world_vertices,
                   const std::vector<uint32_t>& triangles,
                   gx3de_vec3 origin,
                   gx3de_vec3 normal,
                   bool keep_positive,
                   MeshData& output,
                   std::string& error);

} // namespace gx3de_backend

#endif
