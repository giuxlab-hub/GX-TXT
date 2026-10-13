// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "mesh_disk_cache_backend.hpp"
#include "mesh_repeat_backend.hpp"
#include <cstdint>
#include <string>

namespace gx3de_backend {
/* One versioned binary payload contains prototype, placements and unmatched
 * geometry. The existing validated blob cache provides symlink-safe roots,
 * SHA-256 integrity, same-directory staging and atomic publication. */
MeshDiskCacheLoad repeat_disk_cache_load(const char* mesh_root,
    const std::string& namespace_utf8,const std::string& operation_sha256_hex,
    const std::string& source_fingerprint,uint64_t selected,
    RepeatResult& output,std::string& error);
bool repeat_disk_cache_store(const char* mesh_root,
    const std::string& namespace_utf8,const std::string& operation_sha256_hex,
    const std::string& source_fingerprint,const RepeatResult& data,
    std::string& error);
}
