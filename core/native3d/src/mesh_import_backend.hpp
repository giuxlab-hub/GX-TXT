/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_MESH_IMPORT_BACKEND_HPP
#define GX3DE_MESH_IMPORT_BACKEND_HPP

#include "mesh_prep_backend.hpp"
#include <cstdint>
#include <string>

namespace gx3de_backend {

enum class MeshImportFormat : uint32_t { Obj=1, Stl=2 };
enum class MeshSourceStatus { Ok, NotFound, Range, Invalid };
enum class MeshPreviewStatus { Success, Unsupported, Invalid };
using MeshImportCancel = bool (*)(void* user);
using MeshImportProgress = void (*)(void* user, uint64_t progress_permille);

/* The frozen worker's 640 bytes/binary-STL-triangle and 16 bytes/OBJ-source
 * preflight, with 4 GiB default budget. Preview checks source and budget
 * settings but skips the full-import estimate. */
MeshSourceStatus mesh_source_preflight(const char* path_utf8,MeshImportFormat format,
    uint64_t max_source_bytes,uint64_t max_memory_bytes,bool full_import,
    std::string& error);

/*
 * Full, synchronous STL/OBJ import. No preview, persistent cache, or LOD is
 * implied. `max_source_bytes == 0` selects the conservative 256 MiB default;
 * callers can set an explicit larger source limit. The OBJ index validator is
 * ported from the golden viewer before vtkOBJReader is called. Source SHA-256
 * is computed over exact file bytes and checked again after VTK import. A
 * changing source is rejected. On failure outputs remain unchanged.
 *
 * VTK retains its normal STL vertex welding and OBJ face triangulation.
 * The returned mesh contains only triangles and finite coordinates.
 */
bool import_mesh_file(const char* path_utf8, MeshImportFormat format,
                      uint64_t max_source_bytes, uint64_t max_memory_bytes,MeshData& output,
                      std::string& source_sha256_hex, std::string& error,
                      MeshImportCancel cancel=nullptr, void* cancel_user=nullptr,
                      MeshImportProgress progress=nullptr, void* progress_user=nullptr);

/* Early source preview independent of VTK's blocking full parse. A supported
 * source produces a bounded mesh and SHA-256 source identity. */
MeshPreviewStatus preview_mesh_file(const char* path_utf8,MeshImportFormat format,
    uint64_t max_source_bytes,uint64_t max_memory_bytes,MeshData& output,
    std::string& source_sha256_hex,std::string& error,
    MeshImportCancel cancel=nullptr,void* cancel_user=nullptr);

} // namespace gx3de_backend
#endif
