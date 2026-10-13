// SPDX-License-Identifier: GPL-3.0-or-later
// GX3D display geometry v1: little-endian, 64-byte header and aligned arrays.
#pragma once
#include <vtkCellArray.h>
#include <vtkIdList.h>
#include <vtkNew.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <vtkSmartPointer.h>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace gx3d_cache {
namespace fs = std::filesystem;
constexpr uint64_t align64(uint64_t n) { return (n + 63u) & ~uint64_t(63u); }
constexpr std::array<char, 8> magic{{'G','X','3','D','G','E','O','1'}};
constexpr std::array<char, 8> instance_magic{{'G','X','3','D','I','N','S','1'}};

struct Header {
    char magic[8];
    uint32_t version;
    uint32_t endian;
    uint64_t vertices;
    uint64_t triangles;
    float bounds[6];
    uint64_t indices_offset;
};
static_assert(sizeof(Header) == 64, "display geometry header must be 64 bytes");

struct InstanceHeader {
    char magic[8];
    uint32_t version;
    uint32_t endian;
    uint32_t prototypes;
    uint32_t reserved;
    uint64_t instances;
    uint64_t records_offset;
    uint8_t padding[24];
};
static_assert(sizeof(InstanceHeader) == 64, "instance header must be 64 bytes");
struct Placement {
    uint32_t prototype;
    uint32_t reserved;
    double pose[7];
};
static_assert(sizeof(Placement) == 64, "instance placement must be 64 bytes");

inline void check_platform() {
    const uint16_t marker = 1;
    if (*reinterpret_cast<const uint8_t*>(&marker) != 1 || sizeof(float) != 4 ||
        !std::numeric_limits<float>::is_iec559)
        throw std::runtime_error("GX3D display geometry requires IEEE754 little-endian floats");
}

inline Header checked_header(const void* bytes, uint64_t size) {
    check_platform();
    if (size < sizeof(Header)) throw std::runtime_error("truncated GX3D display geometry header");
    Header header{};
    std::memcpy(&header, bytes, sizeof(header));
    if (std::memcmp(header.magic, magic.data(), magic.size()) != 0 ||
        header.version != 1 || header.endian != 0x01020304u ||
        header.vertices == 0 || header.vertices > UINT32_MAX ||
        header.triangles == 0 || header.triangles > UINT32_MAX)
        throw std::runtime_error("invalid GX3D display geometry header");
    if (header.vertices > (UINT64_MAX - sizeof(Header)) / 12 ||
        header.triangles > (UINT64_MAX / 12) ||
        header.indices_offset != align64(sizeof(Header) + header.vertices * 12) ||
        header.indices_offset > size || header.triangles * 12 > size - header.indices_offset ||
        size != header.indices_offset + header.triangles * 12)
        throw std::runtime_error("invalid GX3D display geometry layout");
    for (float bound : header.bounds)
        if (!std::isfinite(bound)) throw std::runtime_error("nonfinite GX3D bounds");
    return header;
}

inline InstanceHeader checked_instance_header(const void* bytes, uint64_t size) {
    check_platform();
    if (size < sizeof(InstanceHeader)) throw std::runtime_error("truncated GX3D instance header");
    InstanceHeader header{};
    std::memcpy(&header, bytes, sizeof(header));
    if (std::memcmp(header.magic, instance_magic.data(), instance_magic.size()) != 0 ||
        header.version != 1 || header.endian != 0x01020304u ||
        header.prototypes == 0 || header.prototypes > 10000 ||
        header.instances < 2 || header.instances > 1000000 ||
        header.records_offset != 64 ||
        size != 64 + header.instances * sizeof(Placement))
        throw std::runtime_error("invalid GX3D instance layout");
    return header;
}

inline void write_instances(const fs::path& path, uint32_t prototypes,
                            const std::vector<Placement>& placements) {
    check_platform();
    if (prototypes == 0 || prototypes > 10000 || placements.size() < 2 ||
        placements.size() > 1000000)
        throw std::runtime_error("GX3D instance count is out of range");
    InstanceHeader header{};
    std::memcpy(header.magic, instance_magic.data(), instance_magic.size());
    header.version = 1;
    header.endian = 0x01020304u;
    header.prototypes = prototypes;
    header.instances = placements.size();
    header.records_offset = 64;
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) throw std::runtime_error("cannot create GX3D instance chunk");
    output.write(reinterpret_cast<const char*>(&header), sizeof(header));
    for (const auto& placement : placements) {
        if (placement.prototype >= prototypes || placement.reserved != 0)
            throw std::runtime_error("invalid GX3D instance prototype");
        for (double value : placement.pose)
            if (!std::isfinite(value)) throw std::runtime_error("nonfinite GX3D instance pose");
        output.write(reinterpret_cast<const char*>(&placement), sizeof(placement));
    }
    output.close();
    if (!output) throw std::runtime_error("GX3D instance write failed");
}

inline void write(const fs::path& path, vtkPolyData* poly) {
    check_platform();
    if (!poly || !poly->GetPoints() || !poly->GetPolys())
        throw std::runtime_error("GX3D display geometry is empty");
    const auto vertex_count = poly->GetNumberOfPoints();
    const auto triangle_count = poly->GetNumberOfPolys();
    if (vertex_count <= 0 || triangle_count <= 0 ||
        uint64_t(vertex_count) > UINT32_MAX || uint64_t(triangle_count) > UINT32_MAX)
        throw std::runtime_error("GX3D display geometry exceeds v1 limits");
    Header header{};
    std::memcpy(header.magic, magic.data(), magic.size());
    header.version = 1;
    header.endian = 0x01020304u;
    header.vertices = static_cast<uint64_t>(vertex_count);
    header.triangles = static_cast<uint64_t>(triangle_count);
    header.indices_offset = align64(sizeof(Header) + header.vertices * 12);
    double bounds[6]{};
    poly->GetBounds(bounds);
    for (int i = 0; i < 6; ++i) {
        if (!std::isfinite(bounds[i]) || std::abs(bounds[i]) > std::numeric_limits<float>::max())
            throw std::runtime_error("GX3D display geometry has nonfinite bounds");
        header.bounds[i] = static_cast<float>(bounds[i]);
    }
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) throw std::runtime_error("cannot create GX3D display geometry");
    out.write(reinterpret_cast<const char*>(&header), sizeof(header));
    for (vtkIdType i = 0; i < vertex_count; ++i) {
        double p[3]{};
        poly->GetPoint(i, p);
        float xyz[3]{};
        for (int j = 0; j < 3; ++j) {
            if (!std::isfinite(p[j]) || std::abs(p[j]) > std::numeric_limits<float>::max())
                throw std::runtime_error("GX3D vertex is nonfinite");
            xyz[j] = static_cast<float>(p[j]);
        }
        out.write(reinterpret_cast<const char*>(xyz), sizeof(xyz));
    }
    const std::array<char, 64> zeros{};
    const auto padding = header.indices_offset - sizeof(Header) - header.vertices * 12;
    out.write(zeros.data(), static_cast<std::streamsize>(padding));
    vtkNew<vtkIdList> cell;
    auto* polys = poly->GetPolys();
    polys->InitTraversal();
    for (vtkIdType i = 0; i < triangle_count; ++i) {
        if (!polys->GetNextCell(cell) || cell->GetNumberOfIds() != 3)
            throw std::runtime_error("GX3D cache requires triangulated polys");
        uint32_t indices[3]{};
        for (int j = 0; j < 3; ++j) {
            const auto id = cell->GetId(j);
            if (id < 0 || id >= vertex_count) throw std::runtime_error("invalid GX3D triangle index");
            indices[j] = static_cast<uint32_t>(id);
        }
        out.write(reinterpret_cast<const char*>(indices), sizeof(indices));
    }
    out.close();
    if (!out) throw std::runtime_error("GX3D display geometry write failed");
}

class MappedFile {
public:
    explicit MappedFile(const fs::path& path) {
        try {
#ifdef _WIN32
        file_ = CreateFileW(path.wstring().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file_ == INVALID_HANDLE_VALUE) throw std::runtime_error("cannot open GX3D cache chunk");
        LARGE_INTEGER length{};
        if (!GetFileSizeEx(file_, &length) || length.QuadPart < 64 ||
            uint64_t(length.QuadPart) > SIZE_MAX)
            throw std::runtime_error("invalid GX3D cache chunk size");
        size_ = static_cast<size_t>(length.QuadPart);
        mapping_ = CreateFileMappingW(file_, nullptr, PAGE_READONLY, 0, 0, nullptr);
        if (!mapping_) throw std::runtime_error("cannot map GX3D cache chunk");
        data_ = MapViewOfFile(mapping_, FILE_MAP_READ, 0, 0, 0);
        if (!data_) throw std::runtime_error("cannot view GX3D cache chunk");
#else
        fd_ = ::open(path.c_str(), O_RDONLY);
        if (fd_ < 0) throw std::runtime_error("cannot open GX3D cache chunk");
        struct stat st{};
        if (::fstat(fd_, &st) != 0 || st.st_size < 64 || uint64_t(st.st_size) > SIZE_MAX)
            throw std::runtime_error("invalid GX3D cache chunk size");
        size_ = static_cast<size_t>(st.st_size);
        data_ = ::mmap(nullptr, size_, PROT_READ, MAP_PRIVATE, fd_, 0);
        if (data_ == MAP_FAILED) { data_ = nullptr; throw std::runtime_error("cannot map GX3D cache chunk"); }
#endif
        } catch (...) { close(); throw; }
    }
    ~MappedFile() { close(); }
    MappedFile(const MappedFile&) = delete;
    MappedFile& operator=(const MappedFile&) = delete;
    const void* data() const { return data_; }
    uint64_t size() const { return size_; }
private:
    void close() noexcept {
#ifdef _WIN32
        if (data_) { UnmapViewOfFile(data_); data_ = nullptr; }
        if (mapping_) { CloseHandle(mapping_); mapping_ = nullptr; }
        if (file_ != INVALID_HANDLE_VALUE) { CloseHandle(file_); file_ = INVALID_HANDLE_VALUE; }
#else
        if (data_) { ::munmap(data_, size_); data_ = nullptr; }
        if (fd_ >= 0) { ::close(fd_); fd_ = -1; }
#endif
    }
    void* data_{nullptr};
    size_t size_{0};
#ifdef _WIN32
    HANDLE file_{INVALID_HANDLE_VALUE};
    HANDLE mapping_{nullptr};
#else
    int fd_{-1};
#endif
};

inline vtkSmartPointer<vtkPolyData> read(const fs::path& path) {
    MappedFile mapped(path);
    const auto header = checked_header(mapped.data(), mapped.size());
    const auto* bytes = static_cast<const uint8_t*>(mapped.data());
    vtkNew<vtkPoints> points;
    points->SetDataTypeToFloat();
    points->SetNumberOfPoints(static_cast<vtkIdType>(header.vertices));
    for (uint64_t i = 0; i < header.vertices; ++i) {
        float xyz[3];
        std::memcpy(xyz, bytes + sizeof(Header) + i * 12, sizeof(xyz));
        for (float value : xyz) if (!std::isfinite(value)) throw std::runtime_error("nonfinite GX3D vertex");
        points->SetPoint(static_cast<vtkIdType>(i), xyz[0], xyz[1], xyz[2]);
    }
    vtkNew<vtkCellArray> polys;
    for (uint64_t i = 0; i < header.triangles; ++i) {
        uint32_t indices[3];
        std::memcpy(indices, bytes + header.indices_offset + i * 12, sizeof(indices));
        vtkIdType ids[3];
        for (int j = 0; j < 3; ++j) {
            if (indices[j] >= header.vertices) throw std::runtime_error("invalid GX3D triangle index");
            ids[j] = static_cast<vtkIdType>(indices[j]);
        }
        polys->InsertNextCell(3, ids);
    }
    auto poly = vtkSmartPointer<vtkPolyData>::New();
    poly->SetPoints(points);
    poly->SetPolys(polys);
    return poly;
}
} // namespace gx3d_cache
