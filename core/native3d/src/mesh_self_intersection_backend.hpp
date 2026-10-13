// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef GX3DE_MESH_SELF_INTERSECTION_BACKEND_HPP
#define GX3DE_MESH_SELF_INTERSECTION_BACKEND_HPP

#include "mesh_prep_backend.hpp"
#include <cstdint>
#include <string>
#include <vector>

namespace gx3de_backend {

// Counts unordered pairs of nonadjacent triangles whose closest Euclidean
// separation is at most tolerance. At tolerance=0, these are intersecting or
// touching pairs. Triangles sharing any vertex index are considered adjacent
// and excluded. Duplicate coordinates with different indices are distinct.
// Rejects non-finite coordinates, invalid indices and zero-area triangles.
// The broad phase uses axis-aligned boxes; the exact phase includes edge-face,
// coplanar overlap, vertex-face and edge-edge cases. It does not distinguish
// intended contact from unintended intersection. On failure count is unchanged.
bool mesh_self_intersections(const MeshData& input, double tolerance,
                             uint64_t& count, std::string& error);

struct MeshIntersectionHit {
    uint64_t triangle_a, triangle_b;
    gx3de_vec3 witness;
};

// Captures up to capacity pairs in deterministic broad-phase order while
// counting every pair. The witness lies on or between the two triangles and
// is a location of exact contact or a near contact within tolerance. Pair
// indices refer to the source triangle array, independent of mesh placement.
// On failure count and hits are unchanged.
bool mesh_self_intersection_details(const MeshData& input, double tolerance,
                                    uint64_t capacity,
                                    std::vector<MeshIntersectionHit>& hits,
                                    uint64_t& count, std::string& error);

} // namespace gx3de_backend

#endif
