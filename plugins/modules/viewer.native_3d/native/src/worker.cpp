// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated native preprocessing worker. A complete manifest is the commit mark.
#include <vtkCleanPolyData.h>
#include <vtkCellArray.h>
#include <vtkNew.h>
#include <vtkOBJReader.h>
#include <vtkPolyData.h>
#include <vtkPoints.h>
#include <vtkQuadricClustering.h>
#include <vtkQuadricDecimation.h>
#include <vtkSTLReader.h>
#include <vtkTriangleFilter.h>
#include <vtkVersion.h>
#include "display_cache.hpp"
#include <openssl/sha.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <chrono>
#include <charconv>
#include <cmath>
#include <cstring>
#include <csignal>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef GX3D_WITH_OCCT
#include <Standard_Version.hxx>
#include <BRep_Builder.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <TCollection_AsciiString.hxx>
#include <TDataStd_Name.hxx>
#include <TDF_LabelSequence.hxx>
#include <TDF_Tool.hxx>
#include <TDocStd_Document.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Compound.hxx>
#include <TopLoc_Location.hxx>
#include <gp_Quaternion.hxx>
#include <XCAFApp_Application.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>
#endif
#ifdef _WIN32
#include <process.h>
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#define GX3D_PROCESS_ID _getpid
#else
#include <sys/resource.h>
#include <unistd.h>
#define GX3D_PROCESS_ID getpid
#endif

namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
struct StepSummary {
    bool active{false};
    double parse_s{0};
    double tessellation_s{0};
    double read_s{0};
    double transfer_s{0};
    double traversal_s{0};
    double meshing_s{0};
    double extraction_s{0};
    double vtk_conversion_s{0};
    int roots{0};
    int assemblies{0};
    int occurrences{0};
    int unique_parts{0};
    int faces{0};
    std::string objects;
#ifdef GX3D_WITH_OCCT
    std::map<std::string, TopoDS_Shape> prototypes;
    struct Instance { std::string prototype_id; std::array<double, 7> pose; };
    std::vector<Instance> instances;
#endif
};
static StepSummary step_summary;
static std::atomic<bool> cancelled{false};
static uint64_t active_memory_budget{0};
static void on_signal(int) { cancelled = true; }
static void ensure_running() { if (cancelled) throw std::runtime_error("cancelled"); }

static uint64_t resident_memory_bytes() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS counters{};
    if (!GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters)))
        throw std::runtime_error("cannot measure native 3D worker memory");
    return static_cast<uint64_t>(counters.WorkingSetSize);
#else
    std::ifstream input("/proc/self/statm");
    uint64_t virtual_pages = 0, resident_pages = 0;
    if (!(input >> virtual_pages >> resident_pages))
        throw std::runtime_error("cannot measure native 3D worker memory");
    const long page_size = ::sysconf(_SC_PAGESIZE);
    if (page_size <= 0 || resident_pages > UINT64_MAX / static_cast<uint64_t>(page_size))
        throw std::runtime_error("invalid native 3D worker memory measurement");
    return resident_pages * static_cast<uint64_t>(page_size);
#endif
}

static double peak_memory_mib() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS counters{};
    if (!GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters)))
        throw std::runtime_error("cannot measure native 3D worker peak memory");
    return static_cast<double>(counters.PeakWorkingSetSize) / (1024.0 * 1024.0);
#else
    rusage usage{};
    if (getrusage(RUSAGE_SELF, &usage) != 0)
        throw std::runtime_error("cannot measure native 3D worker peak memory");
    return static_cast<double>(usage.ru_maxrss) / 1024.0;
#endif
}

static void enforce_memory_budget() {
    if (!active_memory_budget) return;
    const auto resident = resident_memory_bytes();
    if (resident > active_memory_budget)
        throw std::runtime_error("native 3D worker exceeded its configured memory budget");
}

static uint64_t memory_budget_bytes() {
    const char* text = std::getenv("GX3D_MEMORY_BUDGET_MIB");
    if (!text || !*text) return uint64_t(4096) * 1024 * 1024;
    const std::string value(text);
    if (value.empty() || value.find_first_not_of("0123456789") != std::string::npos)
        throw std::runtime_error("invalid native 3D memory budget");
    const uint64_t mib = std::stoull(value);
    if (mib < 32 || mib > 1048576) throw std::runtime_error("native 3D memory budget must be 32..1048576 MiB");
    return mib * 1024 * 1024;
}

static void memory_preflight(const fs::path& source, uint64_t budget) {
    auto extension = source.extension().string();
    for (auto& c : extension) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    const auto bytes = fs::file_size(source);
    uint64_t estimate = 0;
    if (extension == ".stl" && bytes >= 84 && (bytes - 84) % 50 == 0)
        estimate = ((bytes - 84) / 50) * 640;
    else if (extension == ".obj") estimate = bytes * 16;
    else if (extension == ".step" || extension == ".stp") estimate = bytes * 32;
    if (estimate > budget)
        throw std::runtime_error("model exceeds configured native 3D memory budget; raise the budget on a suitable machine");
}

static std::string escape_json(const std::string& value) {
    std::ostringstream out;
    for (unsigned char c : value) {
        switch (c) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (c < 0x20) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c) << std::dec;
            else out << c;
        }
    }
    return out.str();
}

static std::string sha256_file(const fs::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("cannot read source file");
    SHA256_CTX sha;
    SHA256_Init(&sha);
    std::array<char, 1 << 16> buffer{};
    while (in) {
        ensure_running();
        in.read(buffer.data(), buffer.size());
        if (in.gcount()) SHA256_Update(&sha, buffer.data(), static_cast<size_t>(in.gcount()));
    }
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256_Final(digest, &sha);
    std::ostringstream out;
    for (auto byte : digest) out << std::hex << std::setw(2) << std::setfill('0') << int(byte);
    return out.str();
}

static std::string sha256_text(const std::string& text) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(text.data()), text.size(), digest);
    std::ostringstream out;
    for (auto byte : digest) out << std::hex << std::setw(2) << std::setfill('0') << int(byte);
    return out.str();
}

static std::optional<uint32_t> binary_stl_triangles(const fs::path& path) {
    if (path.extension() != ".stl" || fs::file_size(path) < 84) return std::nullopt;
    std::ifstream input(path, std::ios::binary);
    std::array<unsigned char,84> header{};
    input.read(reinterpret_cast<char*>(header.data()), header.size());
    if (!input) throw std::runtime_error("cannot read STL header");
    const uint32_t count = uint32_t(header[80]) | (uint32_t(header[81]) << 8) |
                           (uint32_t(header[82]) << 16) | (uint32_t(header[83]) << 24);
    if (!count || fs::file_size(path) != uint64_t(84) + uint64_t(count)*50)
        return std::nullopt;
    return count;
}

static vtkSmartPointer<vtkPolyData> streaming_stl_preview(const fs::path& path,
                                                          uint32_t triangles, uint64_t budget) {
    if (!std::numeric_limits<float>::is_iec559)
        throw std::runtime_error("binary STL requires IEEE 754 floats");
    const uint64_t target = std::min<uint64_t>(100000,
        std::min<uint64_t>(std::max<uint64_t>(64, triangles/100), budget/1024));
    const uint64_t stride = std::max<uint64_t>(1, (uint64_t(triangles)+target-1)/target);
    std::ifstream input(path, std::ios::binary);
    input.seekg(84);
    vtkNew<vtkPoints> points;
    vtkNew<vtkCellArray> cells;
    std::array<char,50> record{};
    for (uint64_t i=0; i<triangles; ++i) {
        if ((i & 1023) == 0) ensure_running();
        input.read(record.data(),record.size());
        if (!input) throw std::runtime_error("truncated binary STL during preview scan");
        if (i % stride) continue;
        vtkIdType ids[3]{};
        for (int vertex=0; vertex<3; ++vertex) {
            float coordinate[3]{};
            std::memcpy(coordinate, record.data()+12+vertex*12, 12);
            for (float c : coordinate) if (!std::isfinite(c))
                throw std::runtime_error("non-finite binary STL vertex");
            ids[vertex] = points->InsertNextPoint(coordinate[0],coordinate[1],coordinate[2]);
        }
        cells->InsertNextCell(3, ids);
    }
    if (cells->GetNumberOfCells() == 0) throw std::runtime_error("binary STL preview has no triangles");
    vtkSmartPointer<vtkPolyData> output = vtkSmartPointer<vtkPolyData>::New();
    output->SetPoints(points);
    output->SetPolys(cells);
    enforce_memory_budget();
    return output;
}

static vtkSmartPointer<vtkPolyData> streaming_obj_preview(const fs::path& path, uint64_t budget) {
    auto kind = [](const std::string& line) {
        const auto first = line.find_first_not_of(" \t");
        if (first == std::string::npos || first+1 >= line.size() ||
            (line[first+1] != ' ' && line[first+1] != '\t')) return '\0';
        return line[first];
    };
    uint64_t faces = 0, vertex_count = 0, lines = 0;
    std::string line;
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("cannot open OBJ for preview");
    while (std::getline(input,line)) {
        if ((++lines & 16383u) == 0) ensure_running();
        if (line.size() > 1048576) return nullptr;
        const char tag = kind(line);
        if (tag == 'f') ++faces;
        else if (tag == 'v') ++vertex_count;
    }
    if (input.bad() || !faces || !vertex_count) return nullptr;
    const uint64_t target = std::min<uint64_t>({30000,
        std::max<uint64_t>(64,faces/100), std::max<uint64_t>(64,budget/4096)});
    const uint64_t stride = std::max<uint64_t>(1,(faces+target-1)/target);
    input.clear(); input.seekg(0);
    std::map<uint64_t,vtkIdType> selected_vertices;
    vtkNew<vtkCellArray> cells;
    uint64_t face_index = 0;
    while (std::getline(input,line)) {
        if (kind(line) != 'f') continue;
        uint64_t mixed = face_index++ + 0x9e3779b97f4a7c15ull;
        mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
        mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
        mixed ^= mixed >> 31;
        if (mixed % stride != 0) continue;
        if ((face_index & 4095u) == 0) ensure_running();
        if (line.size() > 1048576) return nullptr;
        std::istringstream row(line);
        std::string token;
        row >> token;
        std::vector<vtkIdType> polygon;
        while (row >> token) {
            const auto slash = token.find('/');
            if (slash != std::string::npos) token.resize(slash);
            if (token.empty() || token[0] == '-' || token[0] == '+') return nullptr;
            uint64_t index = 0;
            try {
                size_t end = 0;
                index = std::stoull(token,&end);
                if (end != token.size() || index == 0 || index > vertex_count) return nullptr;
            } catch (...) { return nullptr; }
            const auto inserted = selected_vertices.emplace(index,static_cast<vtkIdType>(selected_vertices.size()));
            polygon.push_back(inserted.first->second);
        }
        if (polygon.size() < 3) return nullptr;
        for (size_t i=1; i+1<polygon.size(); ++i) {
            if (cells->GetNumberOfCells() >= 50000) break;
            const vtkIdType ids[3]{polygon[0],polygon[i],polygon[i+1]};
            cells->InsertNextCell(3,ids);
        }
        if (cells->GetNumberOfCells() >= 50000) break;
    }
    if (input.bad() || cells->GetNumberOfCells() == 0) return nullptr;
    vtkNew<vtkPoints> points;
    points->SetNumberOfPoints(static_cast<vtkIdType>(selected_vertices.size()));
    input.clear(); input.seekg(0);
    uint64_t vertex_index = 0, found = 0;
    while (std::getline(input,line)) {
        if (kind(line) != 'v') continue;
        if ((++vertex_index & 16383u) == 0) ensure_running();
        const auto selected = selected_vertices.find(vertex_index);
        if (selected == selected_vertices.end()) continue;
        std::istringstream row(line);
        std::string tag;
        double xyz[3]{};
        if (!(row >> tag >> xyz[0] >> xyz[1] >> xyz[2]) ||
            !std::isfinite(xyz[0]) || !std::isfinite(xyz[1]) || !std::isfinite(xyz[2])) return nullptr;
        points->SetPoint(selected->second,xyz);
        ++found;
    }
    if (input.bad() || found != selected_vertices.size()) return nullptr;
    vtkSmartPointer<vtkPolyData> output = vtkSmartPointer<vtkPolyData>::New();
    output->SetPoints(points); output->SetPolys(cells);
    enforce_memory_budget();
    return output;
}

static const std::array<const char*,5> lod_names{{"preview","low","medium","high","full"}};

static bool valid_cache_chunk(const fs::path& chunk) {
    const auto marker = fs::path(chunk.string() + ".sha256");
    if (!fs::is_regular_file(chunk) || !fs::is_regular_file(marker) || fs::file_size(chunk) == 0)
        return false;
    std::ifstream mark(marker);
    std::string hash;
    uintmax_t size = 0;
    if (!(mark >> hash >> size) || hash.size() != 64 || size != fs::file_size(chunk)) return false;
    return sha256_file(chunk) == hash;
}

static bool cache_complete(const fs::path& directory, const std::string& key,
                           const std::string& source_hash) {
    const auto manifest_path = directory / "manifest.json";
    if (!fs::is_regular_file(manifest_path)) return false;
    std::ifstream manifest(manifest_path, std::ios::binary);
    const std::string contents((std::istreambuf_iterator<char>(manifest)), std::istreambuf_iterator<char>());
    if (contents.size() > 65536 || contents.find("\"format\":\"GX3D_DISPLAY_CACHE_v1\"") == std::string::npos ||
        contents.find("\"geometry_format\":\"GX3D_GEOMETRY_v1\"") == std::string::npos ||
        contents.find("\"key\":\"" + key + "\"") == std::string::npos ||
        contents.find("\"sha256\":\"" + source_hash + "\"") == std::string::npos) return false;
    const bool instanced = contents.find("\"instancing_file\":\"step_instances.gx3di\"") != std::string::npos;
    for (const auto* level : lod_names) {
        if (instanced && std::string(level) != "preview") continue;
        const auto name = std::string("lod_") + level + ".gx3d";
        const auto chunk = directory / name;
        if (!valid_cache_chunk(chunk)) return false;
    }
    if (contents.find("\"objects_file\":\"step_objects.json\"") != std::string::npos) {
        const auto objects = directory / "step_objects.json";
        if (!fs::is_regular_file(objects) ||
            contents.find("\"objects_sha256\":\"" + sha256_file(objects) + "\"") == std::string::npos)
            return false;
    }
    if (instanced) {
        const auto instances = directory / "step_instances.gx3di";
        if (!valid_cache_chunk(instances) ||
            contents.find("\"instancing_sha256\":\"" + sha256_file(instances) + "\"") == std::string::npos)
            return false;
        const auto marker = contents.find("\"prototype_count\":");
        if (marker == std::string::npos) return false;
        const auto count = std::stoul(contents.substr(marker + 18));
        if (count == 0 || count > 10000) return false;
        for (unsigned i=0; i<count; ++i) for (const auto* level : lod_names) {
            const auto name = "prototype_" + std::to_string(i) + "_lod_" + level + ".gx3d";
            const auto path = directory / name;
            if (!valid_cache_chunk(path)) return false;
        }
    }
    return true;
}

static double seconds(Clock::time_point start) {
    return std::chrono::duration<double>(Clock::now() - start).count();
}

#ifdef GX3D_WITH_OCCT
static vtkSmartPointer<vtkPolyData> shape_mesh(const TopoDS_Shape& shape, int* face_count = nullptr) {
    vtkNew<vtkPoints> points;
    vtkNew<vtkCellArray> cells;
    size_t visited_faces = 0;
    for (TopExp_Explorer faceIt(shape, TopAbs_FACE); faceIt.More(); faceIt.Next()) {
        if ((++visited_faces & 255u) == 0) { ensure_running(); enforce_memory_budget(); }
        if (face_count) ++*face_count;
        const auto face = TopoDS::Face(faceIt.Current());
        TopLoc_Location location;
        const Handle(Poly_Triangulation) triangles = BRep_Tool::Triangulation(face, location);
        if (triangles.IsNull()) continue;
        const auto transform = location.Transformation();
        const vtkIdType base = points->GetNumberOfPoints();
        for (int i=1; i<=triangles->NbNodes(); ++i) {
            const gp_Pnt point = triangles->Node(i).Transformed(transform);
            points->InsertNextPoint(point.X(), point.Y(), point.Z());
        }
        for (int i=1; i<=triangles->NbTriangles(); ++i) {
            int a,b,c;
            triangles->Triangle(i).Get(a,b,c);
            if (face.Orientation() == TopAbs_REVERSED) std::swap(b,c);
            vtkIdType indices[3] = {base+a-1,base+b-1,base+c-1};
            cells->InsertNextCell(3,indices);
        }
    }
    vtkSmartPointer<vtkPolyData> output = vtkSmartPointer<vtkPolyData>::New();
    output->SetPoints(points);
    output->SetPolys(cells);
    return output;
}
#endif

// VTK's OBJ reader can terminate the process on out-of-range face references.
// Check indexed records before handing untrusted model text to that reader.
static void validate_obj_indices(const fs::path& source) {
    constexpr size_t max_record = 8 * 1024 * 1024;
    std::ifstream input(source);
    if (!input) throw std::runtime_error("cannot open OBJ source for validation");
    std::string line, tag;
    std::array<uint64_t,3> preceding{};
    auto checked_index = [&](const std::string& field, size_t kind) {
        if (field.empty()) throw std::runtime_error("OBJ indexed record has an empty required index");
        int64_t index = 0;
        const char* begin = field.data();
        const char* end = begin + field.size();
        const auto parsed = std::from_chars(begin,end,index);
        if (parsed.ec != std::errc{} || parsed.ptr != end || index == 0)
            throw std::runtime_error("OBJ indexed record has an invalid index");
        if (index > 0 && static_cast<uint64_t>(index) > preceding[kind])
            throw std::runtime_error("OBJ indexed record references a missing element");
        if (index < 0 && static_cast<uint64_t>(-(index+1))+1 > preceding[kind])
            throw std::runtime_error("OBJ relative index precedes available elements");
    };
    while (std::getline(input,line)) {
        ensure_running();
        if (line.size() > max_record) throw std::runtime_error("OBJ record exceeds safety limit");
        std::istringstream record(line);
        if (!(record >> tag)) continue;
        if (tag == "v") { ++preceding[0]; continue; }
        if (tag == "vt") { ++preceding[1]; continue; }
        if (tag == "vn") { ++preceding[2]; continue; }
        if (tag != "f" && tag != "l" && tag != "p") continue;
        size_t vertices = 0;
        std::string token;
        while (record >> token) {
            if (token[0] == '#') break;
            const auto first = token.find('/');
            const auto second = first == std::string::npos ? first : token.find('/',first+1);
            if (second != std::string::npos && token.find('/',second+1) != std::string::npos)
                throw std::runtime_error("OBJ indexed record has too many fields");
            checked_index(token.substr(0,first),0);
            if (first != std::string::npos) {
                const auto texture = token.substr(first+1,second == std::string::npos ?
                    std::string::npos : second-first-1);
                if (!texture.empty()) checked_index(texture,1);
                if (second != std::string::npos) checked_index(token.substr(second+1),2);
            }
            ++vertices;
        }
        const size_t minimum = tag == "f" ? 3 : tag == "l" ? 2 : 1;
        if (vertices < minimum) throw std::runtime_error("OBJ indexed record has too few vertices");
    }
    if (!input.eof()) throw std::runtime_error("OBJ validation read failed");
}

static vtkSmartPointer<vtkPolyData> load_mesh(const fs::path& source) {
    auto extension = source.extension().string();
    for (auto& c : extension) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    vtkSmartPointer<vtkPolyData> raw;
    if (extension == ".stl") {
        vtkNew<vtkSTLReader> reader;
        reader->SetFileName(source.string().c_str());
        reader->Update();
        raw = reader->GetOutput();
    } else if (extension == ".obj") {
        vtkNew<vtkOBJReader> reader;
        reader->SetFileName(source.string().c_str());
        reader->Update();
        raw = reader->GetOutput();
    }
#ifdef GX3D_WITH_OCCT
    else if (extension == ".step" || extension == ".stp") {
        const auto parse_start = Clock::now();
        std::cout << "{\"event\":\"step_phase\",\"phase\":\"reading\",\"elapsed_s\":0}" << std::endl;
        STEPCAFControl_Reader reader;
        reader.SetNameMode(Standard_True);
        reader.SetColorMode(Standard_True);
        if (reader.ReadFile(source.string().c_str()) != IFSelect_RetDone) throw std::runtime_error("STEP parse failed");
        step_summary.read_s = seconds(parse_start);
        ensure_running();
        std::cout << "{\"event\":\"step_phase\",\"phase\":\"transferring\",\"elapsed_s\":"
                  << seconds(parse_start) << "}" << std::endl;
        Handle(TDocStd_Document) document;
        XCAFApp_Application::GetApplication()->NewDocument("BinXCAF", document);
        const auto transfer_start = Clock::now();
        if (document.IsNull() || !reader.Transfer(document)) throw std::runtime_error("STEP XDE transfer failed");
        step_summary.transfer_s = seconds(transfer_start);
        ensure_running();
        std::cout << "{\"event\":\"step_phase\",\"phase\":\"inspecting assembly\",\"elapsed_s\":"
                  << seconds(parse_start) << "}" << std::endl;
        const auto traversal_start = Clock::now();
        const Handle(XCAFDoc_ShapeTool) shapes = XCAFDoc_DocumentTool::ShapeTool(document->Main());
        TDF_LabelSequence roots;
        shapes->GetFreeShapes(roots);
        if (roots.Length() < 1) throw std::runtime_error("STEP has no transferable roots");
        step_summary.active = true;
        step_summary.roots = roots.Length();
        std::ostringstream objects;
        bool first_object = true;
        std::function<void(const TDF_Label&, int, const gp_Trsf&)> inspect =
            [&](const TDF_Label& label, int depth, const gp_Trsf& parent) {
            if (depth > 128) throw std::runtime_error("STEP assembly nesting exceeds safety limit");
            TCollection_AsciiString identity;
            TDF_Tool::Entry(label, identity);
            const bool reference = XCAFDoc_ShapeTool::IsReference(label);
            const bool assembly = XCAFDoc_ShapeTool::IsAssembly(label);
            gp_Trsf world = parent;
            if (reference) world.Multiply(XCAFDoc_ShapeTool::GetLocation(label).Transformation());
            if (reference) ++step_summary.occurrences;
            if (assembly) ++step_summary.assemblies;
            std::string name;
            Handle(TDataStd_Name) attribute;
            if (label.FindAttribute(TDataStd_Name::GetID(), attribute)) {
                const auto& value = attribute->Get();
                std::vector<char> utf8(value.LengthOfCString() + 1, '\0');
                Standard_PCharacter pointer = utf8.data();
                value.ToUTF8CString(pointer);
                name = utf8.data();
            }
            if (!first_object) objects << ',';
            first_object = false;
            objects << "{\"id\":\"" << escape_json(identity.ToCString()) << "\",\"name\":\""
                    << escape_json(name) << "\",\"depth\":" << depth << ",\"kind\":\""
                    << (reference ? "instance" : assembly ? "assembly" : "part") << "\"";
            if (reference) {
                TDF_Label referred;
                if (!XCAFDoc_ShapeTool::GetReferredShape(label, referred))
                    throw std::runtime_error("STEP occurrence has no part definition");
                TCollection_AsciiString target;
                TDF_Tool::Entry(referred, target);
                objects << ",\"prototype_id\":\"" << escape_json(target.ToCString()) << "\"";
                objects << ",\"transform\":[";
                for (int row=1; row<=3; ++row) for (int col=1; col<=4; ++col) {
                    if (row != 1 || col != 1) objects << ',';
                    objects << world.Value(row, col);
                }
                objects << ']';
                if (XCAFDoc_ShapeTool::IsSimpleShape(referred)) {
                    const auto rotation = world.GetRotation();
                    const auto offset = world.TranslationPart();
                    step_summary.instances.push_back({target.ToCString(),
                        {offset.X(), offset.Y(), offset.Z(), rotation.W(), rotation.X(), rotation.Y(), rotation.Z()}});
                }
            }
            objects << '}';
            if (reference) {
                TDF_Label referred;
                XCAFDoc_ShapeTool::GetReferredShape(label, referred);
                inspect(referred, depth + 1, world);
            } else if (assembly) {
                TDF_LabelSequence children;
                XCAFDoc_ShapeTool::GetComponents(label, children);
                for (int i=1; i<=children.Length(); ++i) inspect(children.Value(i), depth + 1, world);
            } else if (XCAFDoc_ShapeTool::IsSimpleShape(label)) {
                step_summary.prototypes.emplace(identity.ToCString(), XCAFDoc_ShapeTool::GetShape(label));
                if (depth == 0) {
                    const auto rotation = world.GetRotation();
                    const auto offset = world.TranslationPart();
                    step_summary.instances.push_back({identity.ToCString(),
                        {offset.X(), offset.Y(), offset.Z(), rotation.W(), rotation.X(), rotation.Y(), rotation.Z()}});
                }
            }
        };
        const gp_Trsf identity_transform;
        for (int i=1; i<=roots.Length(); ++i) inspect(roots.Value(i), 0, identity_transform);
        ensure_running();
        std::cout << "{\"event\":\"step_phase\",\"phase\":\"tessellating\",\"elapsed_s\":"
                  << seconds(parse_start) << "}" << std::endl;
        step_summary.unique_parts = static_cast<int>(step_summary.prototypes.size());
        step_summary.objects = objects.str();
        BRep_Builder builder;
        TopoDS_Compound shape;
        builder.MakeCompound(shape);
        for (int i=1; i<=roots.Length(); ++i) builder.Add(shape, XCAFDoc_ShapeTool::GetShape(roots.Value(i)));
        step_summary.traversal_s = seconds(traversal_start);
        step_summary.parse_s = seconds(parse_start);
        const auto tess_start = Clock::now();
        // The worker is one computation unit; keep OCCT meshing serial so it
        // cannot exceed the configured framework worker budget internally.
        BRepMesh_IncrementalMesh mesher(shape, 0.5, false, 0.5, false);
        mesher.Perform();
        step_summary.meshing_s = seconds(tess_start);
        ensure_running();
        const auto extraction_start = Clock::now();
        raw = shape_mesh(shape, &step_summary.faces);
        step_summary.extraction_s = seconds(extraction_start);
        std::cout << "{\"event\":\"step_phase\",\"phase\":\"display geometry ready\",\"elapsed_s\":"
                  << seconds(parse_start) << "}" << std::endl;
        step_summary.tessellation_s = seconds(tess_start);
    }
#endif
    else {
        throw std::runtime_error("unsupported native mesh format; expected STL or OBJ");
    }
    ensure_running();
    const auto vtk_conversion_start = Clock::now();
    vtkNew<vtkTriangleFilter> triangles;
    triangles->SetInputData(raw);
    triangles->Update();
    vtkNew<vtkCleanPolyData> clean;
    clean->SetInputConnection(triangles->GetOutputPort());
    clean->Update();
    vtkSmartPointer<vtkPolyData> output = vtkSmartPointer<vtkPolyData>::New();
    output->ShallowCopy(clean->GetOutput());
    if (step_summary.active) step_summary.vtk_conversion_s = seconds(vtk_conversion_start);
    if (output->GetNumberOfPolys() <= 0) throw std::runtime_error("source has no renderable triangles");
    return output;
}

static vtkSmartPointer<vtkPolyData> lod(vtkPolyData* full, double fraction, bool fast) {
    vtkSmartPointer<vtkPolyData> output = vtkSmartPointer<vtkPolyData>::New();
    if (fraction >= 0.999) { output->ShallowCopy(full); return output; }
    auto clustered = [&]() {
        const auto target = std::max<vtkIdType>(64, static_cast<vtkIdType>(full->GetNumberOfPolys() * fraction));
        double bounds[6]; full->GetBounds(bounds);
        double spans[3] = {bounds[1]-bounds[0], bounds[3]-bounds[2], bounds[5]-bounds[4]};
        double largest = std::max({spans[0], spans[1], spans[2], 1e-12});
        int dimensions[3] = {1, 1, 1};
        int active = 0;
        double geometric = 1.0;
        for (int axis=0; axis<3; ++axis) if (spans[axis] > largest*1e-5) { ++active; geometric *= spans[axis]; }
        geometric = std::pow(geometric, 1.0/std::max(1, active));
        double base = std::pow(std::max(8.0, double(target)/2.0), 1.0/std::max(1, active));
        for (int axis=0; axis<3; ++axis) if (spans[axis] > largest*1e-5)
            dimensions[axis] = std::max(2, int(std::round(base * spans[axis] / geometric)));
        vtkNew<vtkQuadricClustering> clustering;
        clustering->SetInputData(full);
        clustering->SetNumberOfDivisions(dimensions);
        clustering->UseInputPointsOn();
        clustering->Update();
        output->ShallowCopy(clustering->GetOutput());
    };
    if (fast) clustered();
    else {
        vtkNew<vtkQuadricDecimation> decimation;
        decimation->SetInputData(full);
        decimation->SetTargetReduction(std::clamp(1.0 - fraction, 0.0, 0.999));
        decimation->VolumePreservationOn();
        decimation->Update();
        output->ShallowCopy(decimation->GetOutput());
        double source_bounds[6]{}, result_bounds[6]{};
        full->GetBounds(source_bounds);
        output->GetBounds(result_bounds);
        bool lost_envelope = output->GetNumberOfPolys() == 0;
        for (int axis=0; axis<3; ++axis) {
            const double span = std::max(1e-9,source_bounds[2*axis+1]-source_bounds[2*axis]);
            if (std::max(std::abs(result_bounds[2*axis]-source_bounds[2*axis]),
                    std::abs(result_bounds[2*axis+1]-source_bounds[2*axis+1])) > span*0.02)
                lost_envelope = true;
        }
        if (lost_envelope) clustered();
    }
    return output;
}

int main(int argc, char** argv) {
    fs::path stage;
    fs::path portable_stage;
    try {
        if (argc != 3 && argc != 4) throw std::runtime_error("usage: gx3d-worker <source.stl|source.obj|source.step> <cache-root> [portable-resource-root]");
        std::signal(SIGTERM, on_signal);
        std::signal(SIGINT, on_signal);
        const fs::path source = fs::canonical(argv[1]);
        const fs::path root = fs::absolute(argv[2]);
        if (!fs::is_regular_file(source)) throw std::runtime_error("source is not a regular file");
        fs::create_directories(root);
        const auto source_hash_start = Clock::now();
        const auto source_hash = sha256_file(source);
        const double source_hash_s = seconds(source_hash_start);
        if (argc == 4) {
            const fs::path portable_target = fs::absolute(argv[3]) / source_hash / source.filename();
            if (fs::exists(portable_target)) {
                if (!fs::is_regular_file(portable_target) || sha256_file(portable_target) != source_hash)
                    throw std::runtime_error("existing portable source has different content");
            } else {
                fs::create_directories(portable_target.parent_path());
                portable_stage = portable_target;
                portable_stage += ".part-" + std::to_string(GX3D_PROCESS_ID());
                std::ifstream input(source, std::ios::binary);
                std::ofstream output(portable_stage, std::ios::binary | std::ios::trunc);
                if (!input || !output) throw std::runtime_error("cannot open portable source copy");
                SHA256_CTX copy_hash;
                SHA256_Init(&copy_hash);
                std::array<char, 1 << 16> buffer{};
                uintmax_t written = 0;
                uintmax_t last_report = 0;
                while (input) {
                    ensure_running();
                    input.read(buffer.data(), buffer.size());
                    const auto n = input.gcount();
                    if (!n) break;
                    output.write(buffer.data(), n);
                    if (!output) throw std::runtime_error("portable source copy failed");
                    SHA256_Update(&copy_hash, buffer.data(), static_cast<size_t>(n));
                    written += static_cast<uintmax_t>(n);
                    if (written - last_report >= 64 * 1024 * 1024) {
                        std::cout << "{\"event\":\"portable_progress\",\"bytes\":" << written << "}" << std::endl;
                        last_report = written;
                    }
                }
                output.close();
                if (!output) throw std::runtime_error("portable source copy flush failed");
                unsigned char digest[SHA256_DIGEST_LENGTH];
                SHA256_Final(digest, &copy_hash);
                std::ostringstream value;
                for (auto byte : digest) value << std::hex << std::setw(2) << std::setfill('0') << int(byte);
                if (written != fs::file_size(source) || value.str() != source_hash)
                    throw std::runtime_error("portable copy integrity check failed");
                fs::rename(portable_stage, portable_target);
                portable_stage.clear();
            }
            std::cout << "{\"event\":\"portable_ready\",\"sha256\":\"" << source_hash << "\"}" << std::endl;
        }
        const auto format = source.extension().string();
        const auto binary_stl = binary_stl_triangles(source);
        const bool streaming_obj = format == ".obj" && fs::file_size(source) >= 8*1024*1024;
        std::string importer_version = "vtk-" + std::string(vtkVersion::GetVTKVersion());
#ifdef GX3D_WITH_OCCT
        if (format == ".step" || format == ".stp") importer_version += "|occt-" OCC_VERSION_COMPLETE "|xde|linear-0.5|angular-0.5";
#endif
        // This cache key describes output geometry. The 0.9.1 transfer lookup
        // produces byte-identical chunks, so existing warm caches remain valid.
        const auto key = sha256_text("GX3D_DISPLAY_CACHE_v1|native-worker-0.8.0|binary-geometry-v1|binary-instances-v1|input-point-clustering|volume-preserving-decimation|envelope-fallback|" + importer_version +
            "|" + source_hash + "|" + format + "|vtk-clustering-quadric|lod-1-5-20-50-100" +
            (binary_stl ? "|streaming-stl-preview-v1" : "") +
            (streaming_obj ? "|streaming-obj-preview-v3" : ""));
        const auto final = root / key;
        if (cache_complete(final, key, source_hash)) {
            std::cout << "{\"event\":\"cache_hit\",\"key\":\"" << key << "\",\"sha256\":\"" << source_hash
                      << "\",\"size_bytes\":" << fs::file_size(source) << ",\"cache_dir\":\"" << escape_json(final.string()) << "\"}" << std::endl;
            return 0;
        }
        if (fs::exists(final)) {
            std::cout << "{\"event\":\"cache_invalid\",\"reason\":\"manifest or LOD integrity failure\"}" << std::endl;
            fs::remove_all(final);
        }
        active_memory_budget = memory_budget_bytes();
        memory_preflight(source, active_memory_budget);
        if (format == ".obj") validate_obj_indices(source);
        stage = root / ("." + key + ".tmp-" + std::to_string(GX3D_PROCESS_ID()));
        if (fs::exists(stage)) throw std::runtime_error("staging cache already exists");
        fs::create_directories(stage);
        auto start = Clock::now();
        std::cout << "{\"event\":\"start\",\"source\":\"" << escape_json(source.string()) << "\",\"key\":\"" << key
                  << "\",\"sha256\":\"" << source_hash << "\",\"size_bytes\":" << fs::file_size(source)
                  << ",\"source_hash_s\":" << source_hash_s << "}" << std::endl;
        std::ostringstream entries;
        bool first = true;
        bool has_early_preview = false;
        if (binary_stl || streaming_obj) {
            auto preview = binary_stl ? streaming_stl_preview(source,*binary_stl,active_memory_budget) :
                streaming_obj_preview(source,active_memory_budget);
            if (preview) {
            const auto chunk = stage / "lod_preview.gx3d";
            gx3d_cache::write(chunk,preview);
            std::ofstream marker(chunk.string() + ".sha256", std::ios::binary);
            marker << sha256_file(chunk) << ' ' << fs::file_size(chunk) << '\n';
            marker.close();
            if (!marker) throw std::runtime_error("streamed preview checksum write failed");
            entries << "{\"name\":\"preview\",\"file\":\"lod_preview.gx3d\",\"triangles\":"
                    << preview->GetNumberOfPolys() << "}";
            first = false;
            std::cout << "{\"event\":\"lod_ready\",\"lod\":\"preview\",\"triangles\":"
                      << preview->GetNumberOfPolys() << ",\"elapsed_s\":" << seconds(start) << "}" << std::endl;
            std::ofstream ready(stage / "preview.ready",std::ios::binary);
            ready << "GX3D_PREVIEW_v1 " << key << '\n';
            ready.close();
            if (!ready) throw std::runtime_error("streamed preview marker write failed");
            std::cout << "{\"event\":\"preview_ready\",\"cache_dir\":\""
                      << escape_json(stage.string()) << "\",\"elapsed_s\":" << seconds(start) << "}" << std::endl;
            has_early_preview = true;
            } else if (streaming_obj) {
                std::cout << "{\"event\":\"preview_fallback\",\"reason\":\"unsupported OBJ face indexing\"}" << std::endl;
            }
        }
        auto full = load_mesh(source);
        ensure_running();
        enforce_memory_budget();
        const vtkIdType source_triangles = full->GetNumberOfPolys();
        double bounds[6]; full->GetBounds(bounds);
        bool use_instances = false;
#ifdef GX3D_WITH_OCCT
        use_instances = step_summary.active && step_summary.instances.size() > 1 && !step_summary.prototypes.empty();
#endif
        std::cout << "{\"event\":\"parsed\",\"triangles\":" << source_triangles << ",\"elapsed_s\":" << seconds(start);
        if (step_summary.active) {
            std::cout << ",\"step_parse_s\":" << step_summary.parse_s
                      << ",\"step_tessellation_s\":" << step_summary.tessellation_s
                      << ",\"step_read_s\":" << step_summary.read_s
                      << ",\"step_transfer_s\":" << step_summary.transfer_s
                      << ",\"step_traversal_s\":" << step_summary.traversal_s
                      << ",\"step_meshing_s\":" << step_summary.meshing_s
                      << ",\"step_extraction_s\":" << step_summary.extraction_s
                      << ",\"step_vtk_conversion_s\":" << step_summary.vtk_conversion_s
                      << ",\"step_faces\":" << step_summary.faces
                      << ",\"step_roots\":" << step_summary.roots
                      << ",\"step_unique_parts\":" << step_summary.unique_parts
                      << ",\"step_occurrences\":" << step_summary.occurrences;
        }
        std::cout << "}" << std::endl;
        const auto cache_build_start = Clock::now();
        struct Entry { const char* name; double fraction; };
        const Entry levels[] = {{"preview",0.01},{"low",0.05},{"medium",0.20},{"high",0.50},{"full",1.0}};
        for (const auto& level : levels) {
            if (has_early_preview && std::string(level.name) == "preview") continue;
            if (use_instances && std::string(level.name) != "preview") continue;
            ensure_running();
            auto generated = lod(full, level.fraction, level.fraction <= 0.05);
            ensure_running();
            enforce_memory_budget();
            const auto name = std::string("lod_") + level.name + ".gx3d";
            gx3d_cache::write(stage / name, generated);
            const auto chunk = stage / name;
            std::ofstream marker(stage / (name + ".sha256"), std::ios::binary);
            marker << sha256_file(chunk) << ' ' << fs::file_size(chunk) << '\n';
            marker.close();
            if (!marker) throw std::runtime_error("LOD cache checksum write failed");
            if (!first) entries << ',';
            first = false;
            entries << "{\"name\":\"" << level.name << "\",\"file\":\"" << name << "\",\"triangles\":" << generated->GetNumberOfPolys() << "}";
            std::cout << "{\"event\":\"lod_ready\",\"lod\":\"" << level.name << "\",\"triangles\":" << generated->GetNumberOfPolys() << ",\"elapsed_s\":" << seconds(start) << "}" << std::endl;
            if (std::string(level.name) == "preview") {
                std::ofstream ready(stage / "preview.ready", std::ios::binary);
                ready << "GX3D_PREVIEW_v1 " << key << '\n';
                ready.close();
                if (!ready) throw std::runtime_error("preview marker write failed");
                std::cout << "{\"event\":\"preview_ready\",\"cache_dir\":\""
                          << escape_json(stage.string()) << "\",\"elapsed_s\":" << seconds(start) << "}" << std::endl;
            }
        }
        ensure_running();
        if (use_instances) full = nullptr;
        std::string instancing_hash;
        unsigned prototype_count = 0;
#ifdef GX3D_WITH_OCCT
        if (use_instances) {
            std::map<std::string, unsigned> indices;
            for (const auto& item : step_summary.prototypes) indices[item.first] = prototype_count++;
            std::map<std::string, size_t> multiplicity;
            for (const auto& item : step_summary.instances) ++multiplicity[item.prototype_id];
            std::array<vtkIdType, 5> logical_triangles{};
            const auto placement_file = stage / "step_instances.gx3di";
            std::vector<gx3d_cache::Placement> placements;
            placements.reserve(step_summary.instances.size());
            for (const auto& instance : step_summary.instances) {
                ensure_running();
                gx3d_cache::Placement placement{};
                placement.prototype = indices.at(instance.prototype_id);
                std::copy(instance.pose.begin(), instance.pose.end(), placement.pose);
                placements.push_back(placement);
            }
            gx3d_cache::write_instances(placement_file, prototype_count, placements);
            instancing_hash = sha256_file(placement_file);
            std::ofstream placement_marker(placement_file.string() + ".sha256", std::ios::binary);
            placement_marker << instancing_hash << ' ' << fs::file_size(placement_file) << '\n';
            placement_marker.close();
            if (!placement_marker) throw std::runtime_error("STEP instance checksum write failed");
            for (const auto& item : step_summary.prototypes) {
                ensure_running();
                auto prototype = shape_mesh(item.second);
                enforce_memory_budget();
                if (prototype->GetNumberOfPolys() <= 0) throw std::runtime_error("STEP prototype has no tessellation");
                for (size_t level_index=0; level_index<5; ++level_index) {
                    const auto& level = levels[level_index];
                    ensure_running();
                    // Small CAD parts retain all boundaries at every presentation level.
                    auto geometry = prototype->GetNumberOfPolys() < 1000 ?
                        lod(prototype, 1.0, false) : lod(prototype, level.fraction, level.fraction <= 0.05);
                    enforce_memory_budget();
                    const auto name = "prototype_" + std::to_string(indices.at(item.first)) + "_lod_" + level.name + ".gx3d";
                    const auto chunk = stage / name;
                    gx3d_cache::write(chunk, geometry);
                    std::ofstream checksum(chunk.string() + ".sha256", std::ios::binary);
                    checksum << sha256_file(chunk) << ' ' << fs::file_size(chunk) << '\n';
                    checksum.close();
                    if (!checksum) throw std::runtime_error("STEP prototype checksum write failed");
                    logical_triangles[level_index] += geometry->GetNumberOfPolys() * multiplicity.at(item.first);
                }
            }
            entries.str(""); entries.clear();
            for (size_t i=0; i<5; ++i) {
                if (i) entries << ',';
                entries << "{\"name\":\"" << levels[i].name << "\",\"file\":\"instanced\",\"triangles\":"
                        << logical_triangles[i] << "}";
            }
        }
#endif
        std::string objects_hash;
        if (step_summary.active) {
            const auto objects_path = stage / "step_objects.json";
            std::ofstream objects(objects_path, std::ios::binary);
            objects << "{\"schema\":\"GX3D_STEP_OBJECTS_v1\",\"objects\":[" << step_summary.objects << "]}";
            objects.close();
            if (!objects) throw std::runtime_error("STEP object metadata write failed");
            objects_hash = sha256_file(objects_path);
        }
        std::ofstream manifest(stage / "manifest.json", std::ios::binary);
        if (!manifest) throw std::runtime_error("cannot write cache manifest");
        manifest << "{\"format\":\"GX3D_DISPLAY_CACHE_v1\",\"worker_version\":\"0.9.1\",\"geometry_format\":\"GX3D_GEOMETRY_v1\",\"key\":\"" << key
                 << "\",\"source\":{\"sha256\":\"" << source_hash << "\",\"size_bytes\":" << fs::file_size(source)
                 << ",\"format\":\"" << escape_json(format) << "\"},\"source_triangles\":" << source_triangles
                 << ",\"bounds\":[";
        for (int i=0;i<6;++i) { if (i) manifest << ','; manifest << bounds[i]; }
        manifest << "],\"lods\":[" << entries.str() << ']';
        if (step_summary.active) {
            manifest << ",\"step\":{\"parse_s\":" << step_summary.parse_s
                     << ",\"tessellation_s\":" << step_summary.tessellation_s
                     << ",\"faces\":" << step_summary.faces
                     << ",\"roots\":" << step_summary.roots
                     << ",\"unique_parts\":" << step_summary.unique_parts
                     << ",\"occurrences\":" << step_summary.occurrences
                     << ",\"objects_file\":\"step_objects.json\",\"objects_sha256\":\""
                     << objects_hash << "\"";
            if (!instancing_hash.empty()) {
                manifest << ",\"instancing_file\":\"step_instances.gx3di\",\"instancing_sha256\":\""
                         << instancing_hash << "\",\"prototype_count\":" << prototype_count
                         << ",\"instance_count\":" << step_summary.instances.size();
            }
            manifest << '}';
        }
        manifest << '}';
        manifest.close();
        if (!manifest) throw std::runtime_error("cache manifest flush failed");
        fs::rename(stage, final);
        stage.clear();
        std::cout << "{\"event\":\"complete\",\"cache_dir\":\"" << escape_json(final.string())
                  << "\",\"elapsed_s\":" << seconds(start)
                  << ",\"cache_build_s\":" << seconds(cache_build_start)
                  << ",\"peak_rss_mib\":" << peak_memory_mib() << "}" << std::endl;
        return 0;
    } catch (const std::exception& error) {
        if (!stage.empty()) { std::error_code ignored; fs::remove_all(stage, ignored); }
        if (!portable_stage.empty()) { std::error_code ignored; fs::remove(portable_stage, ignored); }
        std::cout << "{\"event\":\"error\",\"message\":\"" << escape_json(error.what()) << "\"}" << std::endl;
        return cancelled ? 130 : 1;
    }
}
