// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef GX3DE_MESH_PREP_BACKEND_HPP
#define GX3DE_MESH_PREP_BACKEND_HPP

#include "native_3d_engine_api_v1.h"
#include <cstdint>
#include <string>
#include <vector>

namespace gx3de_backend {

// Native-only data. No C++ type crosses the public GX3DE ABI.
struct MeshData {
    std::vector<gx3de_vec3> vertices;
    std::vector<uint32_t> triangles; // Three vertex indices per triangle.
};

struct MeshPrepStats {
    uint64_t input_vertices = 0;
    uint64_t output_vertices = 0;
    uint64_t input_triangles = 0;
    uint64_t output_triangles = 0;
    uint64_t welded_vertices = 0;
    uint64_t removed_collapsed_triangles = 0;
    uint64_t removed_duplicate_triangles = 0;
    uint64_t removed_unreferenced_vertices = 0;
};

struct MeshOrientationStats {
    uint64_t connected_components = 0;
    uint64_t closed_components = 0;
    uint64_t flipped_triangles = 0;
    uint64_t outward_reversed_components = 0;
};

// The first input vertex within tolerance is the representative. Distance is
// Euclidean and inclusive; tolerance=0 performs exact positional welding.
// On failure output and stats remain unchanged and error describes the cause.
// Surviving triangles retain their input winding and relative order.
bool weld_mesh(const MeshData& input, double tolerance, MeshData& output,
               std::string& error, MeshPrepStats* stats = nullptr);

// Exact positional welding followed by collapsed/duplicate face removal.
bool clean_duplicates(const MeshData& input, MeshData& output,
                      std::string& error, MeshPrepStats* stats = nullptr);

// Returns closed, ordered boundary cycles. Each loop starts at its smallest
// vertex index, follows the incident triangle winding and omits a repeated
// closing vertex. Loops are sorted by their starting index. Rejects collapsed
// faces, non-manifold edges, inconsistent interior edge winding and branched
// boundary vertices. On failure loops remain unchanged.
bool boundary_loops(const MeshData& input,
                    std::vector<std::vector<uint32_t>>& loops,
                    std::string& error);

// Joins two meshes only at their boundary vertices. Every boundary loop of A
// must match exactly one reversed-winding loop of B with the same vertex count;
// corresponding 3D positions must be within the inclusive Euclidean tolerance.
// Unmatched, ambiguous, degenerate or overlapping-face seams are rejected.
// Interior vertices are never welded. On failure output remains unchanged.
bool stitch_boundaries(const MeshData& a, const MeshData& b, double tolerance,
                       MeshData& output, std::string& error);

// Consistently orients each edge-manifold connected triangle component. Open
// components retain the winding of their first input face. Closed components
// are made outward according to signed enclosed volume. Rejects degenerate,
// non-manifold, non-orientable and zero-volume closed components. Geometry and
// triangle order are preserved; only index 1/2 within faces may swap.
// On failure output and stats remain unchanged.
bool orient_normals(const MeshData& input, MeshData& output,
                    std::string& error, MeshOrientationStats* stats = nullptr);

} // namespace gx3de_backend

#endif
