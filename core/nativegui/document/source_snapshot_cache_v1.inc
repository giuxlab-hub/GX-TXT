/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Trusted CORE Document cache; absent from the Viewer SDK file surface.
 * Exact payloads remain owned by Interactive Document, never by this cache. */
struct SnapshotEntry {
    std::string bytes, identity, sha;
    std::uint64_t used = 0;
    std::size_t accounted = 0;
};
struct SnapshotCache {
    std::map<std::string, SnapshotEntry> entries;
    std::size_t budget = 8 * 1024 * 1024, maxEntries = 128, retained = 0;
    std::uint64_t serial = 0, hits = 0, misses = 0, evictions = 0, verifiedBytes = 0;
    void erase(std::map<std::string, SnapshotEntry>::iterator it) {
        retained -= it->second.accounted; entries.erase(it);
    }
    void trim(std::size_t incoming = 0) {
        while (!entries.empty() && (retained + incoming > budget || entries.size() >= maxEntries)) {
            auto oldest = entries.begin();
            for (auto it = entries.begin(); it != entries.end(); ++it)
                if (it->second.used < oldest->second.used) oldest = it;
            erase(oldest); ++evictions;
        }
    }
};
void disposeSnapshotCache(ClientData data, Tcl_Interp *) { delete static_cast<SnapshotCache *>(data); }
Tcl_Obj *snapshotField(Tcl_Interp *ip, Tcl_Obj *object, const char *key) {
    Tcl_Obj *value = nullptr;
    auto *name = Tcl_NewStringObj(key, -1); Tcl_IncrRefCount(name);
    const auto code = Tcl_DictObjGet(ip, object, name, &value); Tcl_DecrRefCount(name);
    if (code != TCL_OK || !value) throw std::runtime_error("Incomplete private Document capture");
    return value;
}
std::string snapshotDigest(const std::string &bytes) {
    unsigned char value[EVP_MAX_MD_SIZE]; unsigned length = 0;
    if (EVP_Digest(bytes.data(), bytes.size(), value, &length, EVP_sha256(), nullptr) != 1 || length != 32)
        throw std::runtime_error("Document SHA-256 calculation failed");
    constexpr char digits[] = "0123456789abcdef"; std::string out; out.reserve(64);
    for (unsigned i = 0; i < length; ++i) {out += digits[value[i] >> 4]; out += digits[value[i] & 15];}
    return out;
}
#if defined(__linux__)
Tcl_Obj *snapshotIdentity(Tcl_Interp *ip, const std::string &name) {
    // Identity inspection allocates no payload buffer. The separate read path
    // remains bounded at64 MiB; larger valid Documents use the original reader.
    const auto current = namedStat(namedSource(name), std::numeric_limits<std::size_t>::max());
    const Tcl_WideInt values[] = {wide(current.st_dev), wide(current.st_ino), wide(current.st_size),
        wide(current.st_mode & 07777), wide(current.st_uid), wide(current.st_gid), wide(current.st_nlink),
        nanos(current.st_mtim), nanos(current.st_ctim)};
    const char *keys[] = {"device", "inode", "size", "mode", "uid", "gid", "links", "mtime_ns", "ctime_ns"};
    auto *out = Tcl_NewDictObj();
    for (unsigned i = 0; i < 9; ++i) put(ip, out, keys[i], Tcl_NewWideIntObj(values[i]));
    return out;
}
#endif
int snapshotCacheCommand(ClientData data, Tcl_Interp *ip, int objc, Tcl_Obj *const objv[]) {
    auto &cache = *static_cast<SnapshotCache *>(data);
    try {
        if (objc < 2) throw std::runtime_error("Document cache expects status, clear, configure, identity or read");
        const std::string op = Tcl_GetString(objv[1]);
        if(op=="digest") {
            if(objc!=3)throw std::runtime_error("Document cache digest expects bounded bytes");
            int size=0;const auto* bytes=Tcl_GetByteArrayFromObj(objv[2],&size);
            if(size>67108864)throw std::runtime_error("Document digest exceeds64 MiB");
            const auto digest=snapshotDigest(std::string(reinterpret_cast<const char*>(bytes),size));
            Tcl_SetObjResult(ip,Tcl_NewStringObj(digest.c_str(),-1));return TCL_OK;
        }
        auto status = [&]() {
            auto *out = Tcl_NewDictObj();
            put(ip, out, "schema", Tcl_NewStringObj("gxtxt.document.snapshot_cache.v1", -1));
            for (const auto &row : std::vector<std::pair<const char *, std::uint64_t>>{
                {"entries",cache.entries.size()},{"accounted_bytes",cache.retained},{"byte_budget",cache.budget},
                {"entry_budget",cache.maxEntries},{"hits",cache.hits},{"misses",cache.misses},
                {"evictions",cache.evictions},{"verified_bytes",cache.verifiedBytes}})
                put(ip, out, row.first, Tcl_NewWideIntObj(wide(row.second)));
            return out;
        };
        if (op == "status" || op == "clear") {
            if (objc != 2) throw std::runtime_error("Document cache status/clear accepts no arguments");
            if (op == "clear") {cache.entries.clear(); cache.retained = 0;}
            Tcl_SetObjResult(ip, status()); return TCL_OK;
        }
        if (op == "configure") {
            Tcl_WideInt bytes = 0, entries = 0;
            if (objc != 4 || Tcl_GetWideIntFromObj(ip,objv[2],&bytes) != TCL_OK ||
                Tcl_GetWideIntFromObj(ip,objv[3],&entries) != TCL_OK || bytes < 1048576 ||
                bytes > 268435456 || entries < 1 || entries > 512)
                throw std::runtime_error("Document cache budget is1..256 MiB and1..512 entries");
            cache.budget = static_cast<std::size_t>(bytes); cache.maxEntries = static_cast<std::size_t>(entries);
            while (!cache.entries.empty() && (cache.retained > cache.budget || cache.entries.size() > cache.maxEntries)) {
                auto oldest=cache.entries.begin();
                for(auto it=cache.entries.begin();it!=cache.entries.end();++it)if(it->second.used<oldest->second.used)oldest=it;
                cache.erase(oldest); ++cache.evictions;
            }
            Tcl_SetObjResult(ip,status()); return TCL_OK;
        }
#if defined(__linux__)
        if (op == "identity") {
            if (objc != 3) throw std::runtime_error("Document identity expects its CORE-owned path");
            Tcl_SetObjResult(ip,snapshotIdentity(ip,nativePath(objv[2]))); return TCL_OK;
        }
        if (op == "read") {
            if (objc != 4) throw std::runtime_error("Document cached read expects its CORE-owned path and SHA-256 or registry marker");
            const auto name = nativePath(objv[2]); const std::string expected = Tcl_GetString(objv[3]);
            if (!expected.empty() && (expected.size()!=64 || expected.find_first_not_of("0123456789abcdef")!=std::string::npos))
                throw std::runtime_error("Invalid expected Document SHA-256");
            auto *now = snapshotIdentity(ip,name); Tcl_IncrRefCount(now);
            const std::string currentIdentity = Tcl_GetString(now); Tcl_DecrRefCount(now);
            const std::string key = name + '\0' + expected;
            auto found = cache.entries.find(key);
            const bool hit = found != cache.entries.end() && found->second.identity == currentIdentity;
            if (!hit) {
                if(found!=cache.entries.end())cache.erase(found);
                ++cache.misses;
                auto *captureResult = capture(ip,objv[2],64*1024*1024); Tcl_IncrRefCount(captureResult);
                SnapshotEntry entry;
                try {
                    int length=0;const auto *bytes=Tcl_GetByteArrayFromObj(snapshotField(ip,captureResult,"bytes"),&length);
                    entry.bytes.assign(reinterpret_cast<const char *>(bytes),static_cast<std::size_t>(length));
                    entry.identity=Tcl_GetString(snapshotField(ip,captureResult,"identity"));
                    entry.sha=snapshotDigest(entry.bytes); cache.verifiedBytes += entry.bytes.size();
                } catch (...) {Tcl_DecrRefCount(captureResult);throw;}
                Tcl_DecrRefCount(captureResult);
                if(!expected.empty() && entry.sha!=expected) {
                    Tcl_SetErrorCode(ip,"GXTXT","DOCUMENT","CACHE","SHA_MISMATCH",nullptr);
                    Tcl_SetObjResult(ip,Tcl_NewStringObj("Interactive Document is corrupt: payload SHA-256 mismatch",-1)); return TCL_ERROR;
                }
                entry.used=++cache.serial;
                entry.accounted=entry.bytes.capacity()+entry.identity.capacity()+entry.sha.capacity()+key.capacity()+sizeof(SnapshotEntry)+64;
                auto *out=Tcl_NewDictObj();put(ip,out,"cache_hit",Tcl_NewBooleanObj(0));
                put(ip,out,"identity",Tcl_NewStringObj(entry.identity.data(),static_cast<int>(entry.identity.size())));
                put(ip,out,"sha256",Tcl_NewStringObj(entry.sha.data(),static_cast<int>(entry.sha.size())));
                put(ip,out,"bytes",Tcl_NewByteArrayObj(reinterpret_cast<const unsigned char *>(entry.bytes.data()),static_cast<int>(entry.bytes.size())));
                if(entry.accounted<=cache.budget){cache.trim(entry.accounted);cache.retained+=entry.accounted;cache.entries.emplace(key,std::move(entry));}
                Tcl_SetObjResult(ip,out);return TCL_OK;
            }
            ++cache.hits;found->second.used=++cache.serial;
            auto *out=Tcl_NewDictObj();put(ip,out,"cache_hit",Tcl_NewBooleanObj(1));
            put(ip,out,"identity",Tcl_NewStringObj(found->second.identity.data(),static_cast<int>(found->second.identity.size())));
            put(ip,out,"sha256",Tcl_NewStringObj(found->second.sha.data(),static_cast<int>(found->second.sha.size())));
            put(ip,out,"bytes",Tcl_NewByteArrayObj(reinterpret_cast<const unsigned char *>(found->second.bytes.data()),static_cast<int>(found->second.bytes.size())));
            Tcl_SetObjResult(ip,out);return TCL_OK;
        }
#endif
        throw std::runtime_error("Unsupported Document cache operation/platform");
    } catch(const std::exception &error) {
        Tcl_SetObjResult(ip,Tcl_NewStringObj(error.what(),-1));
        Tcl_SetErrorCode(ip,"GXTXT","DOCUMENT","CACHE","REFUSED",nullptr);return TCL_ERROR;
    }
}
