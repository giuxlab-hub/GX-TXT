/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "source_capture.h"
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
#if defined(__linux__)
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace {
constexpr std::size_t captureLimit = 4194304;
constexpr std::size_t pathLimit = 16384;

#if defined(__linux__)
class Descriptor {
    int value_;
public:
    explicit Descriptor(int value = -1) : value_(value) {}
    ~Descriptor() { if (value_ >= 0) (void)::close(value_); }
    Descriptor(const Descriptor &) = delete;
    Descriptor &operator=(const Descriptor &) = delete;
    Descriptor(Descriptor &&other) noexcept : value_(other.value_) { other.value_ = -1; }
    Descriptor &operator=(Descriptor &&other) noexcept {
        if (this != &other) {
            if (value_ >= 0) (void)::close(value_);
            value_ = other.value_;
            other.value_ = -1;
        }
        return *this;
    }
    int get() const { return value_; }
};

struct NamedSource { Descriptor parent; std::string leaf; };

/* Walk again from / for every named check. An old held parent is insufficient
 * after a directory has been renamed or replaced. Do not normalize symlinks. */
NamedSource namedSource(const std::string &path) {
    Descriptor parent(::open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    if (parent.get() < 0) throw std::runtime_error("Source root cannot be opened");
    std::size_t start = 1;
    for (;;) {
        const auto slash = path.find('/', start);
        const auto part = path.substr(start, slash == std::string::npos ? slash : slash - start);
        if (part.empty() || part == "." || part == "..")
            throw std::runtime_error("Source path must have explicit ordinary components");
        if (slash == std::string::npos) return {std::move(parent), part};
        Descriptor next(::openat(parent.get(), part.c_str(),
                                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
        if (next.get() < 0) throw std::runtime_error("Source ancestry is unavailable or linked");
        parent = std::move(next);
        start = slash + 1;
    }
}

void ordinary(const struct stat &value) {
    if (!S_ISREG(value.st_mode) || value.st_nlink != 1 || value.st_size < 0 ||
        static_cast<std::uintmax_t>(value.st_size) > captureLimit)
        throw std::runtime_error("Source must be singly linked, regular and at most 4 MiB");
}

struct stat namedStat(const NamedSource &source) {
    struct stat value {};
    if (::fstatat(source.parent.get(), source.leaf.c_str(), &value, AT_SYMLINK_NOFOLLOW) != 0)
        throw std::runtime_error("Source name cannot be inspected");
    ordinary(value);
    return value;
}

bool same(const struct stat &a, const struct stat &b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
           (a.st_mode & 07777) == (b.st_mode & 07777) && a.st_uid == b.st_uid &&
           a.st_gid == b.st_gid && a.st_nlink == b.st_nlink &&
           a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec &&
           a.st_ctim.tv_sec == b.st_ctim.tv_sec && a.st_ctim.tv_nsec == b.st_ctim.tv_nsec;
}

Tcl_WideInt wide(std::uintmax_t value) {
    if (value > static_cast<std::uintmax_t>(std::numeric_limits<Tcl_WideInt>::max()))
        throw std::runtime_error("Source identity is outside the supported integer range");
    return static_cast<Tcl_WideInt>(value);
}

Tcl_WideInt nanos(const struct timespec &value) {
    constexpr Tcl_WideInt scale = 1000000000;
    const auto low = std::numeric_limits<Tcl_WideInt>::min();
    const auto high = std::numeric_limits<Tcl_WideInt>::max();
    if (value.tv_nsec < 0 || value.tv_nsec >= scale ||
        value.tv_sec < low / scale || value.tv_sec > high / scale)
        throw std::runtime_error("Source timestamp is outside the supported nanosecond range");
    const auto seconds = static_cast<Tcl_WideInt>(value.tv_sec) * scale;
    if (seconds > high - value.tv_nsec)
        throw std::runtime_error("Source timestamp is outside the supported nanosecond range");
    return seconds + value.tv_nsec;
}

void put(Tcl_Interp *interp, Tcl_Obj *dict, const char *key, Tcl_Obj *value) {
    Tcl_DictObjPut(interp, dict, Tcl_NewStringObj(key, -1), value);
}

std::string nativePath(Tcl_Obj *path) {
    int length = 0;
    const char *text = Tcl_GetStringFromObj(path, &length);
    if (length <= 1 || length > static_cast<int>(pathLimit))
        throw std::runtime_error("Source absolute path exceeds the supported path budget");
    const std::string original(text, static_cast<std::size_t>(length));
    int characters = 0;
    const Tcl_UniChar *unicode = Tcl_GetUnicodeFromObj(path, &characters);
    for (int i = 0; i < characters; ++i)
        if (unicode[i] == 0) throw std::runtime_error("Source path contains a NUL character");
    if (Tcl_FSGetPathType(path) != TCL_PATH_ABSOLUTE)
        throw std::runtime_error("Source capture requires an absolute native path");
    const auto *native = static_cast<const char *>(Tcl_FSGetNativePath(path));
    if (!native) throw std::runtime_error("Source path has no supported native representation");
    const auto bytes = ::strnlen(native, pathLimit + 1);
    if (bytes <= 1 || bytes > pathLimit || native[0] != '/')
        throw std::runtime_error("Source path has no supported absolute native representation");
    /* Refuse lossy encoding, expansion or normalization. In particular, never
     * accept an already-resolved symlink name instead of the supplied name. */
    Tcl_DString converted;
    Tcl_ExternalToUtfDString(nullptr, native, static_cast<int>(bytes), &converted);
    const bool exact = original == std::string(Tcl_DStringValue(&converted),
                                              Tcl_DStringLength(&converted));
    Tcl_DStringFree(&converted);
    if (!exact) throw std::runtime_error("Source path native conversion is not lossless and literal");
    return std::string(native, bytes);
}

Tcl_Obj *capture(Tcl_Interp *interp, Tcl_Obj *path) {
    const auto name = nativePath(path);
    auto named = namedSource(name);
    const auto beforeName = namedStat(named);
    Descriptor fd(::openat(named.parent.get(), named.leaf.c_str(),
                           O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK));
    if (fd.get() < 0) throw std::runtime_error("Source cannot be opened without following links");
    struct stat before {}, after {};
    if (::fstat(fd.get(), &before) != 0) throw std::runtime_error("Source descriptor cannot be inspected");
    ordinary(before);
    if (!same(beforeName, before)) throw std::runtime_error("Source changed before capture");
    std::vector<unsigned char> bytes;
    bytes.reserve(static_cast<std::size_t>(before.st_size) + 1);
    unsigned char block[65536];
    bool eof = false;
    for (unsigned call = 0; call < 8192; ++call) {
        const auto wanted = std::min(sizeof block, captureLimit + 1 - bytes.size());
        const auto count = ::read(fd.get(), block, wanted);
        if (count < 0) {
            if (errno == EINTR) continue;
            throw std::runtime_error("Source capture read failed");
        }
        if (count == 0) { eof = true; break; }
        bytes.insert(bytes.end(), block, block + count);
        if (bytes.size() > captureLimit) throw std::runtime_error("Source grew beyond 4 MiB during capture");
    }
    if (!eof) throw std::runtime_error("Source capture read-call budget exceeded");
    if (::fstat(fd.get(), &after) != 0) throw std::runtime_error("Captured descriptor cannot be inspected");
    ordinary(after);
    /* Resolve the current absolute name afresh, including every parent. */
    const auto finalName = namedStat(namedSource(name));
    if (!same(before, after) || !same(after, finalName) ||
        bytes.size() != static_cast<std::size_t>(after.st_size))
        throw std::runtime_error("Source identity changed during capture");
    /* Validate every integer before allocating Tcl result objects. */
    const Tcl_WideInt values[] = {
        wide(after.st_dev), wide(after.st_ino), wide(after.st_size),
        wide(after.st_mode & 07777), wide(after.st_uid), wide(after.st_gid),
        wide(after.st_nlink), nanos(after.st_mtim), nanos(after.st_ctim)
    };
    constexpr const char *keys[] = {
        "device", "inode", "size", "mode", "uid", "gid", "links", "mtime_ns", "ctime_ns"
    };
    Tcl_Obj *identity = Tcl_NewDictObj();
    for (std::size_t i = 0; i < 9; ++i) put(interp, identity, keys[i], Tcl_NewWideIntObj(values[i]));
    Tcl_Obj *result = Tcl_NewDictObj();
    put(interp, result, "schema", Tcl_NewStringObj("gxtxt.native_source_capture.v1", -1));
    put(interp, result, "identity", identity);
    put(interp, result, "bytes", Tcl_NewByteArrayObj(bytes.data(), static_cast<int>(bytes.size())));
    return result;
}
#endif

int command(ClientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "absolute_native_path");
        return TCL_ERROR;
    }
    try {
#if defined(__linux__)
        Tcl_SetObjResult(interp, capture(interp, objv[1]));
        return TCL_OK;
#else
        throw std::runtime_error("Private source capture requires the supported Linux native filesystem");
#endif
    } catch (const std::exception &error) {
        Tcl_SetObjResult(interp, Tcl_NewStringObj(error.what(), -1));
        Tcl_SetErrorCode(interp, "GXTXT", "DOCUMENT", "SOURCE_CAPTURE", "REFUSED", nullptr);
        return TCL_ERROR;
    }
}
}

void GXDocumentSourceCaptureInit(Tcl_Interp *interp) {
    Tcl_CreateObjCommand(interp, "::GX::NativeDocument::sourceCapture", command, nullptr, nullptr);
}
