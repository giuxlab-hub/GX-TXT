// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "mesh_prep_backend.hpp"
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace gx3de_backend {
struct RepeatMatch {
    std::array<double,3> center{};
    std::array<std::array<int,3>,3> rotation{};
    std::vector<uint32_t> triangles;
};
struct RepeatResult {
    MeshData prototype,remainder;
    std::vector<RepeatMatch> matches;
    uint64_t source_triangle=0,source_triangles=0;
    double tolerance=0;
};
/* The frozen viewer's bounded 24-orientation component matcher, with exact
 * source-point connectivity and the same quantized geometry signature. */
bool discover_repeats(const MeshData& source,uint64_t selected,
                      RepeatResult& output,std::string& error);
}
