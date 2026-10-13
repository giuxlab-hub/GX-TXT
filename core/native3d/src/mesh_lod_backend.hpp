// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "mesh_prep_backend.hpp"
#include <cstdint>
#include <string>

namespace gx3de_backend {
/* Faithful non-rendering port of the frozen worker's lod() path. The output
 * is assigned only on success; no source or scene state is mutated. */
bool mesh_lod(const MeshData& source, uint32_t level, MeshData& output,
              std::string& error);
}
