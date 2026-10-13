// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef GX3DE_MESH_CAP_BACKEND_HPP
#define GX3DE_MESH_CAP_BACKEND_HPP
#include "mesh_prep_backend.hpp"
#include <string>
namespace gx3de_backend {

// Capped clipping is intentionally limited to transverse cuts of consistently
// wound, closed triangle meshes with disjoint simple section contours. The
// cap triangulates the clipped mesh's boundary vertices after matching every
// cycle to the actual section profile. Holes and unsupported topology are
// reported, never returned as a supposedly closed mesh.
gx3de_result capped_clip_mesh(const MeshData& input,gx3de_vec3 origin,
                              gx3de_vec3 normal,gx3de_vec3 u,gx3de_vec3 v,
                              bool keep_positive,double tolerance,
                              MeshData& output,std::string& error);
}
#endif
