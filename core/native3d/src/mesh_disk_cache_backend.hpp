/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_MESH_DISK_CACHE_BACKEND_HPP
#define GX3DE_MESH_DISK_CACHE_BACKEND_HPP

#include "mesh_prep_backend.hpp"
#include <cstdint>
#include <string>

namespace gx3de_backend {

struct MeshDiskCacheKey {
    std::string namespace_utf8;
    std::string source_sha256_hex; // SHA-256 of source bytes or immutable B-Rep geometry.
    uint32_t format=0;             // OBJ=1, STL=2, mesh LOD=3, STEP mesh=4, generic B-Rep mesh=5.
    std::string importer_version;   // Must change when derived geometry changes.
};

enum class MeshDiskCacheLoad {
    Hit, Miss, Invalid, Unsafe, IoError
};

/* A cache filename is derived only from the validated key hash. Empty means
 * invalid key. This helper does not touch the filesystem. */
std::string mesh_disk_cache_filename(const MeshDiskCacheKey& key);

/* `root_utf8` is an explicitly chosen cache directory. On Linux each path
 * component is opened without following symlinks; missing directories are
 * created with mode 0700. The entry is a regular file with a checked v1
 * header, exact length, finite vertices, bounded counts, valid indices, and
 * SHA-256 of its serialized payload. A corrupt/incomplete file returns
 * Invalid so the caller can rebuild it. Unsafe symlinks/non-directory path
 * components are never followed. Output changes only on Hit.
 *
 * `max_payload_bytes==0` selects 1 GiB. This limits cache payload, not VTK's
 * peak memory. A caller must validate source SHA independently before lookup.
 */
MeshDiskCacheLoad mesh_disk_cache_load(const char* root_utf8,
                                      const MeshDiskCacheKey& key,
                                      MeshData& output, std::string& error,
                                      uint64_t max_payload_bytes=0);

/* Write through a unique, exclusive temporary file in the same directory,
 * fsync it, then atomically rename over an invalid or missing regular entry.
 * A preexisting symlink is rejected. The temp file is removed on failure.
 * No process-global mutable cache state is used. */
bool mesh_disk_cache_store(const char* root_utf8,const MeshDiskCacheKey& key,
                           const MeshData& mesh,std::string& error,
                           uint64_t max_payload_bytes=0);

/* Validated, transactional derived scientific payload cache. The caller's
 * operation SHA must include the exact source fingerprint and all derivation
 * parameters. Key, length and payload SHA are checked before a hit. */
struct ScientificDiskCacheKey {
    std::string namespace_utf8;
    std::string operation_sha256_hex;
};
std::string scientific_disk_cache_filename(const ScientificDiskCacheKey& key);
MeshDiskCacheLoad scientific_disk_cache_load(const char* root_utf8,
    const ScientificDiskCacheKey& key,std::string& payload,std::string& error);
bool scientific_disk_cache_store(const char* root_utf8,
    const ScientificDiskCacheKey& key,const std::string& payload,std::string& error);

} // namespace gx3de_backend
#endif
