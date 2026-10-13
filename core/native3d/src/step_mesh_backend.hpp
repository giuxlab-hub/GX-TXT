// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef GX3DE_STEP_MESH_BACKEND_HPP
#define GX3DE_STEP_MESH_BACKEND_HPP

#include "mesh_prep_backend.hpp"
#include <cstdint>
#include <string>
class TopoDS_Shape;

namespace gx3de_backend {
/* Tessellates a deep copy of one XDE prototype. The authoritative shape is
 * never meshed or mutated. All tolerances and the output triangle cap are
 * supplied by the caller. */
bool tessellate_step_prototype(const TopoDS_Shape& shape,double linear_deflection,
    double angular_deflection,double weld_tolerance,uint64_t max_triangles,uint64_t max_output_bytes,
    MeshData& output,std::string& error);
}
#endif
