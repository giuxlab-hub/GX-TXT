// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_prep_backend.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <map>
#include <new>
#include <queue>
#include <set>
#include <stdexcept>
#include <utility>

namespace gx3de_backend {
namespace {

bool valid_input(const MeshData& input, std::string& error) {
    if (input.vertices.size() > UINT32_MAX) {
        error = "mesh has more than UINT32_MAX vertices";
        return false;
    }
    if (input.triangles.size() % 3 != 0) {
        error = "triangle index array length is not divisible by three";
        return false;
    }
    if (input.triangles.size() / 3 > UINT32_MAX) {
        error = "mesh has more than UINT32_MAX triangles";
        return false;
    }
    for (const auto& p : input.vertices) {
        if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z)) {
            error = "mesh contains a non-finite vertex";
            return false;
        }
    }
    for (uint32_t index : input.triangles) {
        if (index >= input.vertices.size()) {
            error = "triangle index is outside the vertex array";
            return false;
        }
    }
    return true;
}

bool within_tolerance(const gx3de_vec3& a, const gx3de_vec3& b,
                      long double tolerance_squared) {
    const long double dx = static_cast<long double>(a.x) - b.x;
    const long double dy = static_cast<long double>(a.y) - b.y;
    const long double dz = static_cast<long double>(a.z) - b.z;
    return dx * dx + dy * dy + dz * dz <= tolerance_squared;
}

// An exactly collinear triangle has no usable surface. Long-double arithmetic
// avoids double overflow for otherwise finite, very large input coordinates.
bool collapsed(const gx3de_vec3& a, const gx3de_vec3& b,
               const gx3de_vec3& c) {
    const long double ux = static_cast<long double>(b.x) - a.x;
    const long double uy = static_cast<long double>(b.y) - a.y;
    const long double uz = static_cast<long double>(b.z) - a.z;
    const long double vx = static_cast<long double>(c.x) - a.x;
    const long double vy = static_cast<long double>(c.y) - a.y;
    const long double vz = static_cast<long double>(c.z) - a.z;
    const long double nx = uy * vz - uz * vy;
    const long double ny = uz * vx - ux * vz;
    const long double nz = ux * vy - uy * vx;
    return nx == 0 && ny == 0 && nz == 0;
}

struct EdgeUse { uint32_t face, from, to; };
using EdgeKey = std::pair<uint32_t, uint32_t>;
using EdgeMap = std::map<EdgeKey, std::vector<EdgeUse>>;

bool build_edges(const MeshData& input, EdgeMap& edges, std::string& error) {
    if (!valid_input(input, error)) return false;
    for (size_t i = 0; i < input.triangles.size(); i += 3) {
        uint32_t a = input.triangles[i], b = input.triangles[i + 1], c = input.triangles[i + 2];
        if (a == b || b == c || c == a || collapsed(input.vertices[a], input.vertices[b], input.vertices[c])) {
            error = "mesh contains a collapsed triangle";
            return false;
        }
        const uint32_t face = static_cast<uint32_t>(i / 3);
        for (auto [from, to] : {EdgeKey{a, b}, EdgeKey{b, c}, EdgeKey{c, a}}) {
            auto& uses = edges[{std::min(from, to), std::max(from, to)}];
            uses.push_back({face, from, to});
            if (uses.size() > 2) {
                error = "mesh contains a non-manifold edge";
                return false;
            }
        }
    }
    return true;
}

bool boundary_loops_impl(const MeshData& input, std::vector<std::vector<uint32_t>>& result,
                         std::string& error) {
    EdgeMap edges;
    if (!build_edges(input, edges, error)) return false;
    std::map<uint32_t, uint32_t> next, incoming;
    for (const auto& [key, uses] : edges) {
        if (uses.size() == 2) {
            if (uses[0].from == uses[1].from) {
                error = "mesh has inconsistent interior edge winding";
                return false;
            }
            continue;
        }
        const EdgeUse& use = uses.front();
        if (!next.emplace(use.from, use.to).second || !incoming.emplace(use.to, use.from).second) {
            error = "mesh has a branched boundary vertex";
            return false;
        }
    }
    if (next.size() != incoming.size()) {
        error = "mesh has an open boundary chain";
        return false;
    }
    for (const auto& [vertex, unused] : next) {
        if (!incoming.count(vertex)) {
            error = "mesh has an open boundary chain";
            return false;
        }
    }
    std::set<uint32_t> visited;
    for (const auto& [start, unused] : next) {
        if (visited.count(start)) continue;
        std::vector<uint32_t> cycle;
        uint32_t at = start;
        do {
            if (!visited.insert(at).second) {
                error = "mesh boundary does not form simple loops";
                return false;
            }
            cycle.push_back(at);
            at = next.at(at);
        } while (at != start);
        if (cycle.size() < 3) {
            error = "mesh contains a boundary loop with fewer than three vertices";
            return false;
        }
        result.push_back(std::move(cycle));
    }
    return true;
}

long double signed_volume6(const MeshData& mesh, const std::vector<uint32_t>& faces) {
    const gx3de_vec3 origin = mesh.vertices[mesh.triangles[3 * faces.front()]];
    long double volume6 = 0;
    for (uint32_t face : faces) {
        const auto& a = mesh.vertices[mesh.triangles[3 * face]];
        const auto& b = mesh.vertices[mesh.triangles[3 * face + 1]];
        const auto& c = mesh.vertices[mesh.triangles[3 * face + 2]];
        const long double ax = static_cast<long double>(a.x) - origin.x;
        const long double ay = static_cast<long double>(a.y) - origin.y;
        const long double az = static_cast<long double>(a.z) - origin.z;
        const long double bx = static_cast<long double>(b.x) - origin.x;
        const long double by = static_cast<long double>(b.y) - origin.y;
        const long double bz = static_cast<long double>(b.z) - origin.z;
        const long double cx = static_cast<long double>(c.x) - origin.x;
        const long double cy = static_cast<long double>(c.y) - origin.y;
        const long double cz = static_cast<long double>(c.z) - origin.z;
        volume6 += ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx);
    }
    return volume6;
}

} // namespace

bool weld_mesh(const MeshData& input, double tolerance, MeshData& output,
               std::string& error, MeshPrepStats* stats) {
    if (!std::isfinite(tolerance) || tolerance < 0) {
        error = "weld tolerance must be finite and non-negative";
        return false;
    }
    if (!valid_input(input, error)) return false;

    try {
        MeshData result;
        MeshPrepStats counts;
        counts.input_vertices = input.vertices.size();
        counts.input_triangles = input.triangles.size() / 3;
        std::vector<uint32_t> representative(input.vertices.size());
        std::vector<gx3de_vec3> unique;
        unique.reserve(input.vertices.size());

        // Ordered x-coordinate lookup makes the choice of representative
        // deterministic, including when several vertices lie within tolerance.
        std::map<double, std::vector<uint32_t>> by_x;
        const long double squared = static_cast<long double>(tolerance) * tolerance;
        for (size_t i = 0; i < input.vertices.size(); ++i) {
            const gx3de_vec3 p = input.vertices[i];
            const double lo = p.x - tolerance;
            const double hi = p.x + tolerance;
            uint32_t best = UINT32_MAX;
            for (auto iter = by_x.lower_bound(lo); iter != by_x.end() && iter->first <= hi; ++iter) {
                for (uint32_t candidate : iter->second) {
                    if (candidate < best && within_tolerance(p, unique[candidate], squared)) {
                        best = candidate;
                    }
                }
            }
            if (best == UINT32_MAX) {
                best = static_cast<uint32_t>(unique.size());
                unique.push_back(p);
                by_x[p.x].push_back(best);
            }
            representative[i] = best;
        }
        counts.welded_vertices = input.vertices.size() - unique.size();

        // Face identity ignores winding for duplicate detection, but the
        // surviving first face retains its original vertex order and winding.
        std::set<std::array<uint32_t, 3>> seen_faces;
        std::vector<uint32_t> surviving;
        surviving.reserve(input.triangles.size());
        for (size_t i = 0; i < input.triangles.size(); i += 3) {
            const uint32_t a = representative[input.triangles[i]];
            const uint32_t b = representative[input.triangles[i + 1]];
            const uint32_t c = representative[input.triangles[i + 2]];
            if (a == b || b == c || c == a || collapsed(unique[a], unique[b], unique[c])) {
                ++counts.removed_collapsed_triangles;
                continue;
            }
            std::array<uint32_t, 3> key{a, b, c};
            std::sort(key.begin(), key.end());
            if (!seen_faces.insert(key).second) {
                ++counts.removed_duplicate_triangles;
                continue;
            }
            surviving.insert(surviving.end(), {a, b, c});
        }

        // Compact unused vertices without changing the order of retained
        // representatives. This also makes repeat application idempotent.
        std::vector<uint8_t> used(unique.size(), 0);
        for (uint32_t index : surviving) used[index] = 1;
        std::vector<uint32_t> compact(unique.size(), UINT32_MAX);
        result.vertices.reserve(unique.size());
        for (size_t i = 0; i < unique.size(); ++i) {
            if (used[i]) {
                compact[i] = static_cast<uint32_t>(result.vertices.size());
                result.vertices.push_back(unique[i]);
            }
        }
        result.triangles.reserve(surviving.size());
        for (uint32_t index : surviving) result.triangles.push_back(compact[index]);
        counts.removed_unreferenced_vertices = unique.size() - result.vertices.size();
        counts.output_vertices = result.vertices.size();
        counts.output_triangles = result.triangles.size() / 3;

        output = std::move(result);
        if (stats) *stats = counts;
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error = "mesh preparation exhausted memory";
    } catch (const std::length_error&) {
        error = "mesh preparation exceeded container capacity";
    }
    return false;
}

bool clean_duplicates(const MeshData& input, MeshData& output,
                      std::string& error, MeshPrepStats* stats) {
    return weld_mesh(input, 0.0, output, error, stats);
}

bool boundary_loops(const MeshData& input,
                    std::vector<std::vector<uint32_t>>& loops,
                    std::string& error) {
    try {
        std::vector<std::vector<uint32_t>> result;
        if (!boundary_loops_impl(input, result, error)) return false;
        loops = std::move(result);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error = "boundary loop extraction exhausted memory";
    } catch (const std::length_error&) {
        error = "boundary loop extraction exceeded container capacity";
    }
    return false;
}

bool stitch_boundaries(const MeshData& a, const MeshData& b, double tolerance,
                       MeshData& output, std::string& error) {
    if (!std::isfinite(tolerance) || tolerance < 0) {
        error = "stitch tolerance must be finite and non-negative";
        return false;
    }
    try {
        std::vector<std::vector<uint32_t>> loops_a, loops_b;
        if (!boundary_loops_impl(a, loops_a, error) || !boundary_loops_impl(b, loops_b, error)) return false;
        if (loops_a.empty() || loops_a.size() != loops_b.size()) {
            error = "stitch requires corresponding boundary loops on both meshes";
            return false;
        }
        if (a.vertices.size() > UINT32_MAX - b.vertices.size()) {
            error = "stitched mesh exceeds UINT32_MAX vertices";
            return false;
        }
        const long double squared = static_cast<long double>(tolerance) * tolerance;
        std::vector<uint32_t> map_b(b.vertices.size(), UINT32_MAX);
        std::vector<bool> assigned(loops_b.size(), false);
        for (const auto& loop_a : loops_a) {
            // The pair and offset must be unique. Ambiguity otherwise makes
            // seam topology dependent on input enumeration.
            size_t candidates = 0, matched_loop = 0, matched_offset = 0;
            for (size_t j = 0; j < loops_b.size(); ++j) {
                if (assigned[j] || loops_b[j].size() != loop_a.size()) continue;
                const auto& loop_b = loops_b[j];
                for (size_t offset = 0; offset < loop_b.size(); ++offset) {
                    bool match = true;
                    for (size_t k = 0; k < loop_a.size(); ++k) {
                        size_t backward = (offset + loop_b.size() - k) % loop_b.size();
                        if (!within_tolerance(a.vertices[loop_a[k]], b.vertices[loop_b[backward]], squared)) {
                            match = false;
                            break;
                        }
                    }
                    if (match) {
                        ++candidates;
                        matched_loop = j;
                        matched_offset = offset;
                    }
                }
            }
            if (candidates != 1) {
                error = candidates ? "stitch boundary pairing is ambiguous" : "stitch boundaries are not compatible";
                return false;
            }
            assigned[matched_loop] = true;
            const auto& loop_b = loops_b[matched_loop];
            for (size_t k = 0; k < loop_a.size(); ++k) {
                size_t backward = (matched_offset + loop_b.size() - k) % loop_b.size();
                map_b[loop_b[backward]] = loop_a[k];
            }
        }
        MeshData joined;
        joined.vertices = a.vertices;
        for (size_t i = 0; i < b.vertices.size(); ++i) {
            if (map_b[i] == UINT32_MAX) {
                map_b[i] = static_cast<uint32_t>(joined.vertices.size());
                joined.vertices.push_back(b.vertices[i]);
            }
        }
        joined.triangles = a.triangles;
        for (uint32_t i : b.triangles) joined.triangles.push_back(map_b[i]);
        // A coincident triangle across the seam forms a zero-thickness sheet,
        // even though the edge graph alone looks two-manifold.
        std::set<std::array<uint32_t, 3>> faces;
        for (size_t i = 0; i < joined.triangles.size(); i += 3) {
            std::array<uint32_t, 3> face{joined.triangles[i], joined.triangles[i + 1], joined.triangles[i + 2]};
            std::sort(face.begin(), face.end());
            if (!faces.insert(face).second) {
                error = "stitch would create overlapping faces";
                return false;
            }
        }
        std::vector<std::vector<uint32_t>> remaining;
        if (!boundary_loops_impl(joined, remaining, error)) return false;
        if (!remaining.empty()) {
            error = "stitch left unmatched boundary loops";
            return false;
        }
        output = std::move(joined);
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error = "boundary stitching exhausted memory";
    } catch (const std::length_error&) {
        error = "boundary stitching exceeded container capacity";
    }
    return false;
}

bool orient_normals(const MeshData& input, MeshData& output,
                    std::string& error, MeshOrientationStats* stats) {
    try {
        EdgeMap edges;
        if (!build_edges(input, edges, error)) return false;
        const size_t faces = input.triangles.size() / 3;
        std::vector<std::vector<std::pair<uint32_t, uint8_t>>> adjacent(faces);
        std::vector<uint8_t> boundary(faces, 0);
        for (const auto& [key, uses] : edges) {
            if (uses.size() == 1) {
                boundary[uses[0].face] = 1;
            } else {
                bool same_direction = uses[0].from == uses[1].from;
                adjacent[uses[0].face].push_back({uses[1].face, static_cast<uint8_t>(same_direction)});
                adjacent[uses[1].face].push_back({uses[0].face, static_cast<uint8_t>(same_direction)});
            }
        }
        MeshData result = input;
        MeshOrientationStats counts;
        std::vector<int8_t> flip(faces, -1);
        for (size_t start = 0; start < faces; ++start) {
            if (flip[start] >= 0) continue;
            ++counts.connected_components;
            bool closed = true;
            std::vector<uint32_t> component;
            std::queue<uint32_t> todo;
            flip[start] = 0;
            todo.push(static_cast<uint32_t>(start));
            while (!todo.empty()) {
                uint32_t face = todo.front();
                todo.pop();
                component.push_back(face);
                if (boundary[face]) closed = false;
                for (auto [other, same_direction] : adjacent[face]) {
                    int8_t needed = static_cast<int8_t>(flip[face] ^ same_direction);
                    if (flip[other] < 0) {
                        flip[other] = needed;
                        todo.push(other);
                    } else if (flip[other] != needed) {
                        error = "mesh component cannot be oriented consistently";
                        return false;
                    }
                }
            }
            for (uint32_t face : component) {
                if (flip[face]) {
                    std::swap(result.triangles[3 * face + 1], result.triangles[3 * face + 2]);
                    ++counts.flipped_triangles;
                }
            }
            if (closed) {
                ++counts.closed_components;
                long double volume = signed_volume6(result, component);
                if (volume == 0) {
                    error = "closed mesh component has zero signed volume";
                    return false;
                }
                if (volume < 0) {
                    ++counts.outward_reversed_components;
                    for (uint32_t face : component) {
                        std::swap(result.triangles[3 * face + 1], result.triangles[3 * face + 2]);
                        if (flip[face]) --counts.flipped_triangles;
                        else ++counts.flipped_triangles;
                    }
                }
            }
        }
        output = std::move(result);
        if (stats) *stats = counts;
        error.clear();
        return true;
    } catch (const std::bad_alloc&) {
        error = "normal orientation exhausted memory";
    } catch (const std::length_error&) {
        error = "normal orientation exceeded container capacity";
    }
    return false;
}

} // namespace gx3de_backend
