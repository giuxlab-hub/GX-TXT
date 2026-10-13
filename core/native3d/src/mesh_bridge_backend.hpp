// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "mesh_prep_backend.hpp"
#include <string>

namespace gx3de_backend {
/* Generate bridge faces only for a unique reversed cyclic correspondence of
 * two simple boundary loops. Input coordinates are already in world space.
 * The result is closed, consistently oriented, self-intersection-free, and
 * assigned only on success. */
bool bridge_two_meshes(const MeshData& a,const MeshData& b,double max_gap,
                       MeshData& output,std::string& error);
bool heal_one_mesh_seam(const MeshData& source,double max_gap,
                        MeshData& output,std::string& error);
}
