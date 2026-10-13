// SPDX-License-Identifier: GPL-3.0-or-later
// Native VTK window. Tcl communicates through a bounded line-oriented pipe.
#include <vtkActor.h>
#include <vtkAxesActor.h>
#include <vtkArrowSource.h>
#include <vtkCamera.h>
#include <vtkCell.h>
#include <vtkCellArray.h>
#include <vtkCellData.h>
#include <vtkCellPicker.h>
#include <vtkCommand.h>
#include <vtkDataArray.h>
#include <vtkDoubleArray.h>
#include <vtkGeometryFilter.h>
#include <vtkGlyph3DMapper.h>
#include <vtkInteractorStyleTrackballCamera.h>
#include <vtkImplicitPlaneRepresentation.h>
#include <vtkImplicitPlaneWidget2.h>
#include <vtkNew.h>
#include <vtkMaskPoints.h>
#include <vtkMath.h>
#include <vtkMatrix4x4.h>
#include <vtkOpenGLRenderWindow.h>
#include <vtkPointData.h>
#include <vtkPoints.h>
#include <vtkPNGWriter.h>
#include <vtkPlane.h>
#include <vtkPolyData.h>
#include <vtkPolyDataMapper.h>
#include <vtkProperty.h>
#include <vtkRenderWindow.h>
#include <vtkRenderWindowInteractor.h>
#include <vtkRenderer.h>
#include <vtkRenderLargeImage.h>
#include <vtkXMLUnstructuredGridReader.h>
#include <vtkXMLPolyDataReader.h>
#include <vtkXMLImageDataReader.h>
#include <vtkContourFilter.h>
#include <vtkSphereSource.h>
#include <vtkTubeFilter.h>
#include "display_cache.hpp"
#include "repeat_components.hpp"
#include "gx3d.h"
#include <openssl/evp.h>
#include <array>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <cmath>
#include <mutex>
#include <map>
#include <optional>
#include <queue>
#include <stdexcept>
#include <string>
#include <sstream>
#include <thread>
#include <vector>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#else
#include <sys/resource.h>
#endif

namespace fs = std::filesystem;
static const std::array<const char*,5> levels{{"preview","low","medium","high","full"}};
static double peak_memory_mib() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS counters{};
    if (!GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters)))
        throw std::runtime_error("cannot measure native 3D host peak memory");
    return static_cast<double>(counters.PeakWorkingSetSize) / (1024.0 * 1024.0);
#else
    rusage usage{};
    if (getrusage(RUSAGE_SELF, &usage) != 0)
        throw std::runtime_error("cannot measure native 3D host peak memory");
    return static_cast<double>(usage.ru_maxrss) / 1024.0;
#endif
}
static std::string capability_line(const std::string& report, const std::string& label) {
    const auto start = report.find(label);
    if (start == std::string::npos) return "unavailable";
    const auto from = start + label.size();
    const auto end = report.find_first_of("\r\n", from);
    std::string value = report.substr(from, end == std::string::npos ? end : end - from);
    const auto first = value.find_first_not_of(" :\t");
    return first == std::string::npos ? "unavailable" : value.substr(first);
}
static std::string json_text(const std::string& value) {
    std::string result;
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') result.push_back('\\');
        if (c >= 32 && c < 127) result.push_back(static_cast<char>(c));
    }
    return result;
}
static std::string decode_hex(const std::string& encoded) {
    if (encoded == "-") return {};
    if (encoded.size() > 16384 || encoded.size() % 2 != 0)
        throw std::runtime_error("invalid scientific layer text length");
    std::string value;
    value.reserve(encoded.size() / 2);
    for (size_t i=0; i<encoded.size(); i+=2) {
        const auto hex = encoded.substr(i, 2);
        if (!std::isxdigit(static_cast<unsigned char>(hex[0])) ||
            !std::isxdigit(static_cast<unsigned char>(hex[1])))
            throw std::runtime_error("invalid scientific layer text encoding");
        value.push_back(static_cast<char>(std::stoi(hex, nullptr, 16)));
    }
    if (value.find('\0') != std::string::npos || value.find('\n') != std::string::npos ||
        value.find('\r') != std::string::npos)
        throw std::runtime_error("invalid scientific layer text content");
    return value;
}
static std::vector<std::string> csv_fields(const std::string& line) {
    std::vector<std::string> fields;
    std::string field;
    bool quoted = false;
    for (size_t i=0; i<line.size(); ++i) {
        const char c = line[i];
        if (quoted) {
            if (c == '"' && i+1 < line.size() && line[i+1] == '"') { field.push_back('"'); ++i; }
            else if (c == '"') quoted = false;
            else field.push_back(c);
        } else if (c == '"' && field.empty()) quoted = true;
        else if (c == ',') { fields.push_back(field); field.clear(); }
        else field.push_back(c);
    }
    if (quoted) throw std::runtime_error("multiline CSV fields are unsupported for native 3D points");
    if (!field.empty() && field.back() == '\r') field.pop_back();
    fields.push_back(field);
    return fields;
}
static bool csv_number(const std::string& field, double& result) {
    try {
        size_t end = 0;
        result = std::stod(field, &end);
        while (end < field.size() && std::isspace(static_cast<unsigned char>(field[end]))) ++end;
        return end == field.size() && std::isfinite(result);
    } catch (...) { return false; }
}

static std::string sha256_path(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("cannot read native cache chunk");
    EVP_MD_CTX* digest = EVP_MD_CTX_new();
    if (!digest || EVP_DigestInit_ex(digest, EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("cache integrity service is unavailable");
    std::array<char, 1 << 16> buffer{};
    while (input) {
        input.read(buffer.data(), buffer.size());
        if (input.gcount() && EVP_DigestUpdate(digest, buffer.data(), static_cast<size_t>(input.gcount())) != 1) {
            EVP_MD_CTX_free(digest);
            throw std::runtime_error("cache integrity update failed");
        }
    }
    unsigned char bytes[EVP_MAX_MD_SIZE]; unsigned length = 0;
    if (EVP_DigestFinal_ex(digest, bytes, &length) != 1) {
        EVP_MD_CTX_free(digest);
        throw std::runtime_error("cache integrity finalization failed");
    }
    EVP_MD_CTX_free(digest);
    std::ostringstream actual;
    for (unsigned i=0; i<length; ++i) actual << std::hex << std::setw(2) << std::setfill('0') << int(bytes[i]);
    return actual.str();
}
static void validate_chunk(const fs::path& path) {
    std::ifstream marker(path.string() + ".sha256");
    std::string expected;
    uintmax_t size = 0;
    if (!(marker >> expected >> size) || expected.size() != 64 || size != fs::file_size(path))
        throw std::runtime_error("cache LOD metadata is invalid");
    if (sha256_path(path) != expected) throw std::runtime_error("cache LOD checksum mismatch");
}
static void write_chunk_marker(const fs::path& path) {
    std::ofstream marker(path.string() + ".sha256",std::ios::binary);
    marker << sha256_path(path) << ' ' << fs::file_size(path) << '\n';
    marker.close();
    if (!marker) throw std::runtime_error("native cache checksum write failed");
}

struct Host {
    fs::path cache;
    bool scene_only{false};
    vtkNew<vtkRenderer> renderer;
    vtkNew<vtkRenderWindow> window;
    vtkNew<vtkRenderWindowInteractor> interactor;
    vtkNew<vtkInteractorStyleTrackballCamera> style;
    vtkNew<vtkPolyDataMapper> mapper;
    vtkNew<vtkActor> actor;
    vtkNew<vtkCellPicker> picker;
    vtkNew<vtkPlane> clip_plane;
    vtkNew<vtkImplicitPlaneRepresentation> working_plane_representation;
    vtkNew<vtkImplicitPlaneWidget2> working_plane_widget;
    vtkNew<vtkAxesActor> working_axes;
    std::array<double,3> working_u_axis{{1,0,0}};
    bool working_plane_enabled{false};
    std::array<double,6> scene_bounds{};
    std::array<vtkSmartPointer<vtkPolyData>,5> resident{};
    std::vector<std::array<vtkSmartPointer<vtkPolyData>,5>> prototype_resident;
    std::vector<vtkSmartPointer<vtkGlyph3DMapper>> glyph_mappers;
    std::vector<vtkSmartPointer<vtkActor>> glyph_actors;
    std::vector<vtkSmartPointer<vtkActor>> prototype_actors;
    std::vector<size_t> prototype_counts;
    struct ScientificLayer {
        vtkSmartPointer<vtkActor> surface;
        vtkSmartPointer<vtkActor> vectors;
    };
    std::map<std::string, ScientificLayer> scientific_layers;
    std::optional<gx3d_repeat::Proposal> repeat_proposal;
    vtkSmartPointer<vtkPolyData> repeat_remainder;
    vtkSmartPointer<vtkGlyph3DMapper> repeat_mapper;
    vtkSmartPointer<vtkActor> repeat_actor;
    bool repeat_accepted{false};
    std::mutex mutex;
    std::queue<std::string> commands;
    std::atomic<bool> input_closed{false};
    std::string requested{"medium"};
    std::string active{""};
    bool interaction{false};
    uint64_t display_budget_bytes{0};
    gx3d_context* abi_context{nullptr};
    gx3d_model* abi_model{nullptr};

    ~Host() { gx3d_model_destroy(abi_model); gx3d_context_destroy(abi_context); }

    int lod_index(const std::string& name) {
        for (int i=0; i<5; ++i) if (name == levels[i]) return i;
        return -1;
    }
    void configure_display_budget() {
        const char* text = std::getenv("GX3D_GPU_BUDGET_MIB");
        const std::string value = text && *text ? text : "1024";
        if (value.find_first_not_of("0123456789") != std::string::npos)
            throw std::runtime_error("invalid native 3D display memory budget");
        const uint64_t mib = std::stoull(value);
        if (mib < 16 || mib > 1048576)
            throw std::runtime_error("native 3D display memory budget must be 16..1048576 MiB");
        display_budget_bytes = mib * 1024 * 1024;
    }
    void check_display_budget(const std::string& name) {
        if (lod_index(name) < 0) throw std::runtime_error("unknown LOD");
        uintmax_t bytes = 0;
        if (fs::is_regular_file(cache / "step_instances.gx3di")) {
            bytes = fs::file_size(cache / "step_instances.gx3di");
            const std::string suffix = "_lod_" + name + ".gx3d";
            for (const auto& entry : fs::directory_iterator(cache)) {
                const auto filename = entry.path().filename().string();
                if (entry.is_regular_file() && filename.rfind("prototype_", 0) == 0 &&
                    filename.size() >= suffix.size() &&
                    filename.compare(filename.size() - suffix.size(), suffix.size(), suffix) == 0)
                    bytes += entry.file_size();
            }
        } else {
            const auto path = cache / ("lod_" + name + ".gx3d");
            if (!fs::is_regular_file(path)) throw std::runtime_error("missing cache LOD: " + name);
            bytes = fs::file_size(path);
        }
        // VTK creates CPU arrays and OpenGL buffers from the compact cache chunk.
        if (bytes > display_budget_bytes / 4)
            throw std::runtime_error("native 3D LOD exceeds configured display memory budget");
    }
    vtkPolyData* prototype_geometry(size_t index, const std::string& name) {
        const int level = lod_index(name);
        if (level < 0 || index >= prototype_resident.size()) throw std::runtime_error("invalid STEP prototype LOD");
        auto& slot = prototype_resident[index][level];
        if (!slot) {
            const auto path = cache / ("prototype_" + std::to_string(index) + "_lod_" + name + ".gx3d");
            if (!fs::is_regular_file(path)) throw std::runtime_error("missing STEP prototype cache");
            validate_chunk(path);
            slot = gx3d_cache::read(path);
            if (slot->GetNumberOfPolys() < 1) throw std::runtime_error("empty STEP prototype cache");
        }
        return slot;
    }
    void load_instances() {
        const auto path = cache / "step_instances.gx3di";
        validate_chunk(path);
        gx3d_cache::MappedFile mapped(path);
        const auto header = gx3d_cache::checked_instance_header(mapped.data(), mapped.size());
        const size_t prototypes = header.prototypes;
        const size_t instances = static_cast<size_t>(header.instances);
        prototype_resident.resize(prototypes);
        prototype_actors.resize(prototypes);
        prototype_counts.assign(prototypes, 0);
        std::vector<vtkSmartPointer<vtkPoints>> locations(prototypes);
        std::vector<vtkSmartPointer<vtkDoubleArray>> rotations(prototypes);
        for (size_t index=0; index<prototypes; ++index) {
            locations[index] = vtkSmartPointer<vtkPoints>::New();
            rotations[index] = vtkSmartPointer<vtkDoubleArray>::New();
            rotations[index]->SetName("orientation");
            rotations[index]->SetNumberOfComponents(4);
        }
        const auto* bytes = static_cast<const uint8_t*>(mapped.data());
        for (size_t i=0; i<instances; ++i) {
            gx3d_cache::Placement placement{};
            std::memcpy(&placement, bytes + header.records_offset + i * sizeof(placement), sizeof(placement));
            if (placement.prototype >= prototypes || placement.reserved != 0)
                throw std::runtime_error("invalid STEP instance prototype");
            for (double value : placement.pose) if (!std::isfinite(value)) throw std::runtime_error("nonfinite STEP placement");
            const auto index = placement.prototype;
            locations[index]->InsertNextPoint(placement.pose[0], placement.pose[1], placement.pose[2]);
            rotations[index]->InsertNextTuple4(placement.pose[3], placement.pose[4], placement.pose[5], placement.pose[6]);
            ++prototype_counts[index];
        }
        for (size_t index=0; index<prototypes; ++index) {
            if (!prototype_counts[index]) continue;
            auto placements = vtkSmartPointer<vtkPolyData>::New();
            placements->SetPoints(locations[index]);
            placements->GetPointData()->AddArray(rotations[index]);
            auto glyph = vtkSmartPointer<vtkGlyph3DMapper>::New();
            glyph->SetInputData(placements);
            glyph->SetSourceData(prototype_geometry(index, requested));
            glyph->SetOrientationArray("orientation");
            glyph->SetOrientationModeToQuaternion();
            glyph->OrientOn();
            glyph->SetScaleModeToNoDataScaling();
            glyph->ScalarVisibilityOff();
            auto placed_actor = vtkSmartPointer<vtkActor>::New();
            placed_actor->SetMapper(glyph);
            renderer->AddActor(placed_actor);
            glyph_mappers.push_back(glyph);
            glyph_actors.push_back(placed_actor);
            prototype_actors[index] = placed_actor;
            std::cout << "{\"event\":\"assembly_object\",\"index\":" << index
                      << ",\"instances\":" << prototype_counts[index] << "}" << std::endl;
        }
    }
    vtkIdType displayed_triangles(const std::string& name) {
        vtkIdType total = 0;
        for (size_t i=0; i<prototype_counts.size(); ++i)
            if (prototype_counts[i]) total += prototype_geometry(i, name)->GetNumberOfPolys() * prototype_counts[i];
        return total;
    }
    void evict_unused(int selected) {
        for (int i=0; i<5; ++i) if (i != selected && i != 1) {
            resident[i] = nullptr;
            for (auto& prototype : prototype_resident) prototype[i] = nullptr;
        }
    }
    vtkPolyData* geometry(const std::string& name) {
        const int index = lod_index(name);
        if (index < 0) throw std::runtime_error("unknown LOD");
        if (abi_model && gx3d_model_set_lod(abi_model, static_cast<gx3d_lod>(index)) != GX3D_OK)
            throw std::runtime_error("native ABI rejected display LOD");
        if (!resident[index]) {
            auto path = cache / (std::string("lod_") + name + ".gx3d");
            if (!fs::is_regular_file(path)) throw std::runtime_error("missing cache LOD: " + name);
            validate_chunk(path);
            resident[index] = gx3d_cache::read(path);
            if (resident[index]->GetNumberOfPolys() < 1) throw std::runtime_error("empty cache LOD: " + name);
        }
        return resident[index];
    }
    void switch_lod(const std::string& name) {
        if (scene_only) { active = name; return; }
        check_display_budget(name);
        vtkIdType triangles = 0;
        if (!glyph_mappers.empty()) {
            size_t mapper_index = 0;
            for (size_t i=0; i<prototype_counts.size(); ++i) if (prototype_counts[i]) {
                glyph_mappers[mapper_index++]->SetSourceData(prototype_geometry(i, name));
            }
            triangles = displayed_triangles(name);
        } else {
            vtkPolyData* poly = repeat_accepted && name == "full" ?
                repeat_remainder.GetPointer() : geometry(name);
            mapper->SetInputData(poly);
            triangles = poly->GetNumberOfPolys();
            if (repeat_actor) {
                repeat_actor->SetVisibility(name == "full" && actor->GetVisibility());
                if (repeat_accepted && name == "full" && repeat_proposal)
                    triangles += repeat_proposal->source_triangles *
                        static_cast<vtkIdType>(repeat_proposal->matches.size());
            }
        }
        if (abi_model) gx3d_model_set_lod(abi_model, static_cast<gx3d_lod>(lod_index(name)));
        active = name;
        window->Render();
        evict_unused(lod_index(name));
        size_t instances = 0;
        if (!glyph_mappers.empty()) for (size_t count : prototype_counts) instances += count;
        std::cout << "{\"event\":\"lod\",\"name\":\"" << name << "\",\"triangles\":" << triangles
                  << ",\"instances\":" << instances << "}" << std::endl;
    }
    void camera_event() {
        auto* camera = renderer->GetActiveCamera();
        double p[3], t[3], u[3];
        camera->GetPosition(p); camera->GetFocalPoint(t); camera->GetViewUp(u);
        std::cout << "{\"event\":\"camera\",\"position\":[" << p[0] << ',' << p[1] << ',' << p[2]
                  << "],\"target\":[" << t[0] << ',' << t[1] << ',' << t[2]
                  << "],\"up\":[" << u[0] << ',' << u[1] << ',' << u[2]
                  << "],\"projection\":\"" << (camera->GetParallelProjection() ? "orthographic" : "perspective")
                  << "\",\"parallel_scale\":" << camera->GetParallelScale()
                  << ",\"view_angle_deg\":" << camera->GetViewAngle() << "}" << std::endl;
    }
    void preset(const std::string& name) {
        auto* camera = renderer->GetActiveCamera();
        const double* target = camera->GetFocalPoint();
        double center[3] = {target[0],target[1],target[2]};
        const double d = std::max(1.0, camera->GetDistance());
        double direction[3] = {0,0,1};
        if (name == "back") direction[2] = -1;
        else if (name == "left") { direction[0] = -1; direction[2] = 0; }
        else if (name == "right") { direction[0] = 1; direction[2] = 0; }
        else if (name == "top") { direction[1] = 1; direction[2] = 0; }
        else if (name == "bottom") { direction[1] = -1; direction[2] = 0; }
        else if (name != "front") throw std::runtime_error("unknown camera preset");
        camera->SetPosition(center[0]+d*direction[0], center[1]+d*direction[1], center[2]+d*direction[2]);
        camera->SetViewUp(0, 0, name == "top" ? -1 : (name == "bottom" ? 1 : 0));
        if (name == "front" || name == "back" || name == "left" || name == "right") camera->SetViewUp(0,1,0);
        renderer->ResetCameraClippingRange();
        window->Render(); camera_event();
    }
    void arrow(const std::string& name) {
        auto* camera = renderer->GetActiveCamera();
        if (name == "left") camera->Azimuth(-5);
        else if (name == "right") camera->Azimuth(5);
        else if (name == "up") camera->Elevation(5);
        else if (name == "down") camera->Elevation(-5);
        else throw std::runtime_error("unknown arrow direction");
        camera->OrthogonalizeViewUp();
        renderer->ResetCameraClippingRange();
        window->Render(); camera_event();
    }
    void capabilities() {
        auto* gl = vtkOpenGLRenderWindow::SafeDownCast(window);
        if (!gl) throw std::runtime_error("the native window has no OpenGL renderer");
        window->MakeCurrent();
        const std::string report = gl->ReportCapabilities();
        std::cout << "{\"event\":\"capabilities\",\"vendor\":\""
                  << json_text(capability_line(report, "OpenGL vendor string:"))
                  << "\",\"renderer\":\""
                  << json_text(capability_line(report, "OpenGL renderer string:"))
                  << "\",\"version\":\""
                  << json_text(capability_line(report, "OpenGL version string:"))
                  << "\"}" << std::endl;
    }
    void add_vtu_layer(const std::string& value) {
        std::istringstream input(value);
        std::string id, path_hex, scalar_hex, vector_hex, extra;
        if (!(input >> id >> path_hex >> scalar_hex >> vector_hex) || (input >> extra) ||
            id.empty() || id.size() > 64 ||
            id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") != std::string::npos ||
            scientific_layers.count(id))
            throw std::runtime_error("invalid or duplicate scientific layer ID");
        const auto path = fs::u8path(decode_hex(path_hex));
        const auto scalar = decode_hex(scalar_hex);
        const auto vector = decode_hex(vector_hex);
        if (path.extension() != ".vtu" || !fs::is_regular_file(path))
            throw std::runtime_error("scientific layer requires an existing VTU file");
        if (fs::file_size(path) > display_budget_bytes)
            throw std::runtime_error("scientific layer exceeds configured display memory budget");
        vtkNew<vtkXMLUnstructuredGridReader> reader;
        reader->SetFileName(path.u8string().c_str());
        reader->Update();
        vtkNew<vtkGeometryFilter> surface;
        surface->SetInputConnection(reader->GetOutputPort());
        surface->Update();
        vtkPolyData* poly = surface->GetOutput();
        if (!poly || poly->GetNumberOfPoints() == 0 || poly->GetNumberOfCells() == 0)
            throw std::runtime_error("scientific VTU layer has no displayable cells");
        auto mapper_layer = vtkSmartPointer<vtkPolyDataMapper>::New();
        mapper_layer->SetInputData(poly);
        if (!scalar.empty()) {
            vtkDataArray* values = poly->GetPointData()->GetArray(scalar.c_str());
            if (values) mapper_layer->SetScalarModeToUsePointFieldData();
            else {
                values = poly->GetCellData()->GetArray(scalar.c_str());
                if (!values) throw std::runtime_error("scientific scalar array is missing");
                mapper_layer->SetScalarModeToUseCellFieldData();
            }
            if (values->GetNumberOfComponents() != 1)
                throw std::runtime_error("scientific scalar array must have one component");
            mapper_layer->SelectColorArray(scalar.c_str());
            mapper_layer->SetScalarRange(values->GetRange());
            mapper_layer->ScalarVisibilityOn();
        } else mapper_layer->ScalarVisibilityOff();
        ScientificLayer layer;
        layer.surface = vtkSmartPointer<vtkActor>::New();
        layer.surface->SetMapper(mapper_layer);
        if (!vector.empty()) {
            vtkDataArray* values = poly->GetPointData()->GetArray(vector.c_str());
            if (!values || values->GetNumberOfComponents() != 3)
                throw std::runtime_error("scientific vector array requires three point components");
            vtkNew<vtkMaskPoints> sample;
            sample->SetInputData(poly);
            sample->SetOnRatio(std::max<vtkIdType>(1, poly->GetNumberOfPoints() / 2000));
            sample->Update();
            vtkNew<vtkArrowSource> arrow;
            auto arrows = vtkSmartPointer<vtkGlyph3DMapper>::New();
            arrows->SetInputData(sample->GetOutput());
            arrows->SetSourceConnection(arrow->GetOutputPort());
            arrows->SetOrientationArray(vector.c_str());
            arrows->SetOrientationModeToDirection();
            arrows->SetScaleArray(vector.c_str());
            arrows->SetScaleModeToScaleByMagnitude();
            double magnitude[2]{};
            values->GetRange(magnitude, -1);
            double bounds[6]{};
            poly->GetBounds(bounds);
            const double span = std::max({bounds[1]-bounds[0], bounds[3]-bounds[2], bounds[5]-bounds[4]});
            arrows->SetScaleFactor(magnitude[1] > 0 ? span / (50.0 * magnitude[1]) : 1.0);
            layer.vectors = vtkSmartPointer<vtkActor>::New();
            layer.vectors->SetMapper(arrows);
            layer.vectors->GetProperty()->SetColor(1.0, 0.45, 0.15);
        }
        renderer->AddActor(layer.surface);
        if (layer.vectors) renderer->AddActor(layer.vectors);
        scientific_layers.emplace(id, layer);
        if (scene_only) { renderer->ResetCamera(); renderer->ComputeVisiblePropBounds(scene_bounds.data()); }
        renderer->ResetCameraClippingRange();
        window->Render();
        std::cout << "{\"event\":\"layer_ready\",\"id\":\"" << id << "\",\"cells\":"
                  << poly->GetNumberOfCells() << ",\"points\":" << poly->GetNumberOfPoints()
                  << ",\"scalar\":\"" << json_text(scalar) << "\",\"vector\":\""
                  << json_text(vector) << "\"}" << std::endl;
    }
    // The scene protocol consumes canonical VTK scientific files. Geometry
    // conversion and isosurface extraction stay in the existing VTK engine.
    void add_scientific_layer(const std::string& value) {
        std::istringstream input(value);
        std::string id, path_hex, primitive, scalar_hex, vector_hex, isovalues_text, radius_hex, extra;
        double tube_radius = 0;
        if (!(input >> id >> path_hex >> primitive >> scalar_hex >> vector_hex >> isovalues_text >> radius_hex >> tube_radius) ||
            (input >> extra) || !std::isfinite(tube_radius) || tube_radius < 0 ||
            id.empty() || id.size() > 64 ||
            id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") != std::string::npos ||
            scientific_layers.count(id)) throw std::runtime_error("invalid or duplicate scientific layer ID");
        const auto path = fs::u8path(decode_hex(path_hex));
        const auto scalar = decode_hex(scalar_hex);
        const auto vector = decode_hex(vector_hex);
        const auto radius_array = decode_hex(radius_hex);
        if (!fs::is_regular_file(path) || fs::file_size(path) > display_budget_bytes)
            throw std::runtime_error("scientific layer payload is missing or exceeds display budget");
        const auto extension = path.extension().string();
        auto poly = vtkSmartPointer<vtkPolyData>::New();
        if (extension == ".vtu") {
            vtkNew<vtkXMLUnstructuredGridReader> reader;
            reader->SetFileName(path.u8string().c_str()); reader->Update();
            vtkNew<vtkGeometryFilter> filter;
            filter->SetInputConnection(reader->GetOutputPort()); filter->Update();
            poly->ShallowCopy(filter->GetOutput());
        } else if (extension == ".vtp") {
            vtkNew<vtkXMLPolyDataReader> reader;
            reader->SetFileName(path.u8string().c_str()); reader->Update();
            poly->ShallowCopy(reader->GetOutput());
        } else if (extension == ".vti") {
            if (primitive != "isosurface" || scalar.empty() || isovalues_text == "-")
                throw std::runtime_error("VTI scalar grid needs an isosurface, scalar array and isovalues");
            vtkNew<vtkXMLImageDataReader> reader;
            reader->SetFileName(path.u8string().c_str()); reader->Update();
            auto* values = reader->GetOutput()->GetPointData()->GetArray(scalar.c_str());
            if (!values || values->GetNumberOfComponents() != 1)
                throw std::runtime_error("isosurface scalar array is missing or not scalar");
            reader->GetOutput()->GetPointData()->SetActiveScalars(scalar.c_str());
            vtkNew<vtkContourFilter> contour;
            contour->SetInputConnection(reader->GetOutputPort());
            std::istringstream levels(isovalues_text);
            std::string token;
            int n = 0;
            while (std::getline(levels, token, ',')) {
                if (token.empty() || n >= 32) throw std::runtime_error("isosurface requires 1..32 values");
                size_t consumed = 0;
                const double level = std::stod(token, &consumed);
                if (consumed != token.size() || !std::isfinite(level))
                    throw std::runtime_error("isosurface values must be finite");
                contour->SetValue(n++, level);
            }
            if (n == 0) throw std::runtime_error("isosurface requires a value");
            contour->Update(); poly->ShallowCopy(contour->GetOutput());
        } else throw std::runtime_error("scientific layer expects VTU, VTP or VTI");
        if (poly->GetNumberOfPoints() < 1 || poly->GetNumberOfCells() < 1)
            throw std::runtime_error("scientific layer has no displayable geometry");
        if (!radius_array.empty() && primitive != "points")
            throw std::runtime_error("radius array applies only to point glyphs");
        if (tube_radius > 0 && primitive != "trajectory")
            throw std::runtime_error("tube radius applies only to line geometry");
        if (tube_radius > 0) {
            vtkNew<vtkTubeFilter> tube;
            tube->SetInputData(poly); tube->SetRadius(tube_radius);
            tube->SetNumberOfSides(12); tube->CappingOn(); tube->Update();
            auto surface = vtkSmartPointer<vtkPolyData>::New();
            surface->ShallowCopy(tube->GetOutput());
            poly = surface;
        }
        auto mapper_layer = vtkSmartPointer<vtkPolyDataMapper>::New();
        mapper_layer->SetInputData(poly);
        if (!scalar.empty() && extension != ".vti") {
            vtkDataArray* values = poly->GetPointData()->GetArray(scalar.c_str());
            if (values) mapper_layer->SetScalarModeToUsePointFieldData();
            else {
                values = poly->GetCellData()->GetArray(scalar.c_str());
                if (!values) throw std::runtime_error("scientific scalar array is missing");
                mapper_layer->SetScalarModeToUseCellFieldData();
            }
            if (values->GetNumberOfComponents() != 1)
                throw std::runtime_error("scientific scalar array must have one component");
            mapper_layer->SelectColorArray(scalar.c_str());
            mapper_layer->SetScalarRange(values->GetRange()); mapper_layer->ScalarVisibilityOn();
        } else if (extension == ".vti") {
            mapper_layer->SetScalarRange(poly->GetScalarRange()); mapper_layer->ScalarVisibilityOn();
        } else mapper_layer->ScalarVisibilityOff();
        ScientificLayer layer;
        layer.surface = vtkSmartPointer<vtkActor>::New();
        if (!radius_array.empty()) {
            vtkDataArray* radii = poly->GetPointData()->GetArray(radius_array.c_str());
            if (!radii || radii->GetNumberOfComponents() != 1)
                throw std::runtime_error("point radius array is missing or not scalar");
            vtkNew<vtkSphereSource> sphere;
            sphere->SetRadius(0.5); sphere->SetThetaResolution(16); sphere->SetPhiResolution(12);
            auto glyph = vtkSmartPointer<vtkGlyph3DMapper>::New();
            glyph->SetInputData(poly); glyph->SetSourceConnection(sphere->GetOutputPort());
            glyph->SetScaleArray(radius_array.c_str());
            glyph->SetScaleModeToScaleByMagnitude(); glyph->SetScaleFactor(2.0);
            if (!scalar.empty()) {
                glyph->SetScalarModeToUsePointFieldData(); glyph->SelectColorArray(scalar.c_str());
                glyph->SetScalarRange(poly->GetPointData()->GetArray(scalar.c_str())->GetRange());
                glyph->ScalarVisibilityOn();
            } else glyph->ScalarVisibilityOff();
            layer.surface->SetMapper(glyph);
        } else layer.surface->SetMapper(mapper_layer);
        if (primitive == "points") layer.surface->GetProperty()->SetPointSize(7);
        if (primitive == "trajectory" || primitive == "molecule") {
            layer.surface->GetProperty()->SetLineWidth(3);
            layer.surface->GetProperty()->SetPointSize(12);
        }
        if (!vector.empty()) {
            vtkDataArray* values = poly->GetPointData()->GetArray(vector.c_str());
            if (!values || values->GetNumberOfComponents() != 3)
                throw std::runtime_error("scientific vector array requires three point components");
            vtkNew<vtkMaskPoints> sample;
            sample->SetInputData(poly);
            sample->SetOnRatio(std::max<vtkIdType>(1, poly->GetNumberOfPoints()/2000));
            sample->Update();
            vtkNew<vtkArrowSource> arrow;
            auto arrows = vtkSmartPointer<vtkGlyph3DMapper>::New();
            arrows->SetInputData(sample->GetOutput());
            arrows->SetSourceConnection(arrow->GetOutputPort());
            arrows->SetOrientationArray(vector.c_str());
            arrows->SetOrientationModeToDirection();
            arrows->SetScaleArray(vector.c_str());
            arrows->SetScaleModeToScaleByMagnitude();
            double magnitude[2]{}; values->GetRange(magnitude, -1);
            double bounds[6]{}; poly->GetBounds(bounds);
            const double span = std::max({bounds[1]-bounds[0],bounds[3]-bounds[2],bounds[5]-bounds[4]});
            arrows->SetScaleFactor(magnitude[1] > 0 ? span/(50.0*magnitude[1]) : 1.0);
            layer.vectors = vtkSmartPointer<vtkActor>::New();
            layer.vectors->SetMapper(arrows);
            layer.vectors->GetProperty()->SetColor(1.0,0.45,0.15);
        }
        renderer->AddActor(layer.surface);
        if (layer.vectors) renderer->AddActor(layer.vectors);
        scientific_layers.emplace(id, layer);
        if (scene_only) { renderer->ResetCamera(); renderer->ComputeVisiblePropBounds(scene_bounds.data()); }
        renderer->ResetCameraClippingRange(); window->Render();
        std::cout << "{\"event\":\"layer_ready\",\"id\":\"" << id
                  << "\",\"cells\":" << poly->GetNumberOfCells()
                  << ",\"points\":" << poly->GetNumberOfPoints()
                  << ",\"primitive\":\"" << json_text(primitive)
                  << "\",\"vector\":\"" << json_text(vector) << "\"}" << std::endl;
    }
    void add_dataset_points(const std::string& value) {
        std::istringstream input(value);
        std::string id, path_hex, extra;
        int columns[7]{};
        if (!(input >> id >> path_hex)) throw std::runtime_error("Dataset point layer requires ID and path");
        for (int& column : columns) if (!(input >> column))
            throw std::runtime_error("Dataset point layer requires seven column indices");
        std::string primitive = "points";
        if (input >> extra) primitive = extra;
        if ((input >> extra) || (primitive != "points" && primitive != "trajectory") ||
            id.empty() || id.size() > 64 ||
            id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") != std::string::npos ||
            scientific_layers.count(id)) throw std::runtime_error("invalid or duplicate Dataset point layer ID");
        for (int i=0; i<3; ++i) if (columns[i] < 1 || columns[i] > 4096)
            throw std::runtime_error("Dataset X/Y/Z columns must be 1..4096");
        if (columns[3] < 0 || columns[3] > 4096) throw std::runtime_error("invalid Dataset scalar column");
        const bool vectors = columns[4] || columns[5] || columns[6];
        if (vectors && (columns[4] < 1 || columns[5] < 1 || columns[6] < 1 ||
                        columns[4] > 4096 || columns[5] > 4096 || columns[6] > 4096))
            throw std::runtime_error("Dataset vector requires three columns");
        const auto path = fs::u8path(decode_hex(path_hex));
        if (path.extension() != ".csv" || !fs::is_regular_file(path))
            throw std::runtime_error("Dataset point layer requires an existing canonical CSV");
        if (fs::file_size(path) > display_budget_bytes / 4)
            throw std::runtime_error("Dataset CSV exceeds the configured display memory budget");
        std::ifstream file(path, std::ios::binary);
        if (!file) throw std::runtime_error("cannot open Dataset CSV");
        std::string line;
        if (!std::getline(file, line)) throw std::runtime_error("Dataset CSV is empty");
        const auto header = csv_fields(line);
        for (int column : columns) if (column > static_cast<int>(header.size()))
            throw std::runtime_error("Dataset variable column is absent from the canonical CSV");
        vtkNew<vtkPoints> points;
        vtkNew<vtkCellArray> vertices;
        vtkNew<vtkCellArray> lines;
        vtkNew<vtkDoubleArray> scalar_values;
        scalar_values->SetName("dataset_scalar");
        vtkNew<vtkDoubleArray> vector_values;
        vector_values->SetName("dataset_vector");
        vector_values->SetNumberOfComponents(3);
        size_t skipped = 0;
        const uint64_t maximum_points = std::min<uint64_t>(5000000, display_budget_bytes / 256);
        while (std::getline(file, line)) {
            if (line.size() > 65536) throw std::runtime_error("Dataset CSV row exceeds native 3D limit");
            const auto fields = csv_fields(line);
            double values[7]{};
            bool good = true;
            for (int i=0; i<7; ++i) {
                if (!columns[i]) continue;
                if (columns[i] > static_cast<int>(fields.size()) ||
                    !csv_number(fields[static_cast<size_t>(columns[i]-1)], values[i])) {good=false; break;}
            }
            if (!good) { ++skipped; continue; }
            if (static_cast<uint64_t>(points->GetNumberOfPoints()) >= maximum_points)
                throw std::runtime_error("Dataset point count exceeds the configured display memory budget");
            const vtkIdType index = points->InsertNextPoint(values[0],values[1],values[2]);
            if (primitive == "points") vertices->InsertNextCell(1, &index);
            if (columns[3]) scalar_values->InsertNextValue(values[3]);
            if (vectors) vector_values->InsertNextTuple3(values[4],values[5],values[6]);
        }
        if (file.bad() || points->GetNumberOfPoints() == 0)
            throw std::runtime_error("Dataset CSV has no valid numeric 3D points");
        vtkNew<vtkPolyData> poly;
        poly->SetPoints(points);
        if (primitive == "points") poly->SetVerts(vertices);
        else {
            if (points->GetNumberOfPoints() < 2)
                throw std::runtime_error("Dataset trajectory needs at least two valid points");
            lines->InsertNextCell(points->GetNumberOfPoints());
            for (vtkIdType index=0; index<points->GetNumberOfPoints(); ++index)
                lines->InsertCellPoint(index);
            poly->SetLines(lines);
        }
        if (columns[3]) poly->GetPointData()->AddArray(scalar_values);
        if (vectors) poly->GetPointData()->AddArray(vector_values);
        auto layer_mapper = vtkSmartPointer<vtkPolyDataMapper>::New();
        layer_mapper->SetInputData(poly);
        ScientificLayer layer;
        layer.surface = vtkSmartPointer<vtkActor>::New();
        layer.surface->SetMapper(layer_mapper);
        layer.surface->GetProperty()->SetPointSize(4.0);
        if (primitive == "trajectory") layer.surface->GetProperty()->SetLineWidth(3.0);
        layer.surface->GetProperty()->SetColor(0.1,0.8,1.0);
        if (columns[3]) {
            layer_mapper->SetScalarModeToUsePointFieldData();
            layer_mapper->SelectColorArray("dataset_scalar");
            layer_mapper->SetScalarRange(scalar_values->GetRange());
            layer_mapper->ScalarVisibilityOn();
        } else layer_mapper->ScalarVisibilityOff();
        if (vectors) {
            vtkNew<vtkMaskPoints> sample;
            sample->SetInputData(poly);
            sample->SetOnRatio(std::max<vtkIdType>(1,points->GetNumberOfPoints()/2000));
            sample->Update();
            vtkNew<vtkArrowSource> arrow;
            auto arrows = vtkSmartPointer<vtkGlyph3DMapper>::New();
            arrows->SetInputData(sample->GetOutput());
            arrows->SetSourceConnection(arrow->GetOutputPort());
            arrows->SetOrientationArray("dataset_vector");
            arrows->SetOrientationModeToDirection();
            arrows->SetScaleArray("dataset_vector");
            arrows->SetScaleModeToScaleByMagnitude();
            double bounds[6]{}; poly->GetBounds(bounds);
            double magnitude[2]{}; vector_values->GetRange(magnitude,-1);
            const double span = std::max({bounds[1]-bounds[0],bounds[3]-bounds[2],bounds[5]-bounds[4]});
            arrows->SetScaleFactor(magnitude[1] > 0 ? span/(50.0*magnitude[1]) : 1.0);
            layer.vectors = vtkSmartPointer<vtkActor>::New();
            layer.vectors->SetMapper(arrows);
            layer.vectors->GetProperty()->SetColor(1.0,0.45,0.15);
        }
        renderer->AddActor(layer.surface);
        if (layer.vectors) renderer->AddActor(layer.vectors);
        scientific_layers.emplace(id,layer);
        if (scene_only) { renderer->ResetCamera(); renderer->ComputeVisiblePropBounds(scene_bounds.data()); }
        renderer->ResetCameraClippingRange(); window->Render();
        std::cout << "{\"event\":\"layer_ready\",\"id\":\"" << id
                  << "\",\"points\":" << points->GetNumberOfPoints()
                  << ",\"skipped\":" << skipped << ",\"primitive\":\"" << primitive
                  << "\",\"source\":\"dataset\"}" << std::endl;
    }
    void add_pattern_region(const std::string& value) {
        std::istringstream input(value);
        std::string id, extra;
        vtkIdType selected = -1;
        double radius = 0, step_x = 0, step_y = 0;
        int count_x = 0, count_y = 0;
        if (!(input >> id >> selected >> radius >> count_x >> count_y >> step_x >> step_y))
            throw std::runtime_error("pattern requires a cell, radius, counts and placement spacing");
        std::string layout = "rectangular";
        if (input >> extra) layout = extra;
        std::string placements_hex;
        if (layout == "explicit") input >> placements_hex;
        if ((input >> extra) ||
            (layout != "rectangular" && layout != "linear" && layout != "circular" && layout != "explicit") ||
            (layout == "linear" && count_y != 1) ||
            (layout == "explicit" && (placements_hex.empty() || count_x != 1 || count_y != 1)) ||
            id.empty() || id.size() > 64 ||
            id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") != std::string::npos ||
            scientific_layers.count(id) || selected < 0 ||
            !std::isfinite(radius) || radius <= 0 ||
            !std::isfinite(step_x) || !std::isfinite(step_y) ||
            step_x == 0 || step_y == 0 || count_x < 1 || count_y < 1 ||
            uint64_t(count_x)*uint64_t(count_y) > 1000000)
            throw std::runtime_error("pattern requires a cell, positive patch radius and bounded placements");
        if (active != "full" || !glyph_mappers.empty())
            throw std::runtime_error("select a cell at Full LOD on a mesh model before defining a pattern");
        check_display_budget("full");
        vtkPolyData* full = geometry("full");
        if (selected >= full->GetNumberOfCells()) throw std::runtime_error("selected pattern cell is unavailable");
        vtkCell* picked = full->GetCell(selected);
        if (!picked || picked->GetNumberOfPoints() < 3) throw std::runtime_error("selected pattern cell is invalid");
        double center[3]{};
        for (vtkIdType point=0; point<picked->GetNumberOfPoints(); ++point) {
            double position[3]{}; picked->GetPoints()->GetPoint(point,position);
            for (int axis=0; axis<3; ++axis) center[axis] += position[axis];
        }
        for (double& component : center) component /= picked->GetNumberOfPoints();
        vtkNew<vtkPoints> patch_points;
        vtkNew<vtkCellArray> patch_cells;
        const double radius_squared = radius*radius;
        for (vtkIdType cell_id=0; cell_id<full->GetNumberOfCells(); ++cell_id) {
            if ((cell_id & 4095) == 0 && input_closed) throw std::runtime_error("pattern job interrupted");
            vtkCell* cell = full->GetCell(cell_id);
            if (!cell || cell->GetNumberOfPoints() != 3) continue;
            double centroid[3]{};
            for (int point=0; point<3; ++point) {
                double position[3]{}; cell->GetPoints()->GetPoint(point,position);
                for (int axis=0; axis<3; ++axis) centroid[axis] += position[axis]/3.0;
            }
            if (vtkMath::Distance2BetweenPoints(center,centroid) > radius_squared) continue;
            if (patch_cells->GetNumberOfCells() >= 10000)
                throw std::runtime_error("selected pattern patch exceeds 10,000 triangles");
            vtkIdType ids[3]{};
            for (int point=0; point<3; ++point) {
                double position[3]{}; cell->GetPoints()->GetPoint(point,position);
                ids[point] = patch_points->InsertNextPoint(position[0]-center[0],
                    position[1]-center[1],position[2]-center[2]);
            }
            patch_cells->InsertNextCell(3,ids);
        }
        if (patch_cells->GetNumberOfCells() == 0) throw std::runtime_error("selected pattern patch is empty");
        vtkNew<vtkPolyData> patch;
        patch->SetPoints(patch_points); patch->SetPolys(patch_cells);
        vtkNew<vtkPoints> placements;
        if (layout == "explicit") {
            const fs::path path = fs::u8path(decode_hex(placements_hex));
            if (path.extension() != ".csv" || !fs::is_regular_file(path) ||
                fs::file_size(path) > display_budget_bytes/4)
                throw std::runtime_error("explicit placements require a bounded Session CSV file");
            std::ifstream file(path, std::ios::binary);
            std::string line;
            if (!file || !std::getline(file,line) || csv_fields(line) != std::vector<std::string>{"x","y","z"})
                throw std::runtime_error("explicit placements CSV header must be x,y,z");
            const uint64_t maximum = std::min<uint64_t>(1000000,display_budget_bytes/64);
            while (std::getline(file,line)) {
                if (line.size() > 1024) throw std::runtime_error("explicit placement row is too long");
                const auto fields = csv_fields(line);
                double xyz[3]{};
                if (fields.size() != 3 || !csv_number(fields[0],xyz[0]) ||
                    !csv_number(fields[1],xyz[1]) || !csv_number(fields[2],xyz[2]))
                    throw std::runtime_error("explicit placement row needs three finite coordinates");
                if (static_cast<uint64_t>(placements->GetNumberOfPoints()) >= maximum)
                    throw std::runtime_error("explicit placements exceed the display budget");
                placements->InsertNextPoint(xyz);
            }
            if (file.bad() || placements->GetNumberOfPoints() == 0)
                throw std::runtime_error("explicit placements CSV has no valid placements");
        } else {
            for (int y=0; y<count_y; ++y) for (int x=0; x<count_x; ++x) {
                if (layout == "circular") {
                    const double angle = y*step_y*vtkMath::Pi()/180.0;
                    const double distance = (x+1)*step_x;
                    placements->InsertNextPoint(center[0]+distance*std::cos(angle),
                        center[1]+distance*std::sin(angle),center[2]);
                } else {
                    placements->InsertNextPoint(center[0]+x*step_x,
                        center[1]+y*step_y,center[2]);
                }
            }
        }
        const uint64_t instances = static_cast<uint64_t>(placements->GetNumberOfPoints());
        const uint64_t estimated = instances*64 + uint64_t(patch_cells->GetNumberOfCells())*256;
        if (estimated > display_budget_bytes/4)
            throw std::runtime_error("pattern exceeds the configured display memory budget");
        vtkNew<vtkPolyData> locations;
        locations->SetPoints(placements);
        auto glyph = vtkSmartPointer<vtkGlyph3DMapper>::New();
        glyph->SetInputData(locations);
        glyph->SetSourceData(patch);
        glyph->SetScaleModeToNoDataScaling();
        glyph->ScalarVisibilityOff();
        ScientificLayer layer;
        layer.surface = vtkSmartPointer<vtkActor>::New();
        layer.surface->SetMapper(glyph);
        layer.surface->GetProperty()->SetColor(0.15,0.85,0.75);
        renderer->AddActor(layer.surface);
        scientific_layers.emplace(id,layer);
        renderer->ResetCameraClippingRange(); window->Render();
        std::cout << "{\"event\":\"pattern_ready\",\"id\":\"" << id
                  << "\",\"source_cell\":" << selected
                  << ",\"patch_triangles\":" << patch_cells->GetNumberOfCells()
                  << ",\"instances\":" << instances
                  << ",\"layout\":\"" << layout << "\"}" << std::endl;
    }
    void show_repeat_actor(bool proposed) {
        if (!repeat_proposal) throw std::runtime_error("repeat representation is unavailable");
        if (repeat_actor) renderer->RemoveActor(repeat_actor);
        vtkNew<vtkPoints> points;
        vtkNew<vtkDoubleArray> orientations;
        orientations->SetName("orientation");
        orientations->SetNumberOfComponents(4);
        for (const auto& match : repeat_proposal->matches) {
            points->InsertNextPoint(match.center.data());
            orientations->InsertNextTuple(match.quaternion.data());
        }
        vtkNew<vtkPolyData> placements;
        placements->SetPoints(points);
        placements->GetPointData()->AddArray(orientations);
        repeat_mapper = vtkSmartPointer<vtkGlyph3DMapper>::New();
        repeat_mapper->SetInputData(placements);
        repeat_mapper->SetSourceData(repeat_proposal->prototype);
        repeat_mapper->SetOrientationArray("orientation");
        repeat_mapper->SetOrientationModeToQuaternion();
        repeat_mapper->OrientOn();
        repeat_mapper->SetScaleModeToNoDataScaling();
        repeat_mapper->ScalarVisibilityOff();
        repeat_actor = vtkSmartPointer<vtkActor>::New();
        repeat_actor->SetMapper(repeat_mapper);
        repeat_actor->GetProperty()->SetColor(proposed ? 1.0 : 0.3,
            proposed ? 0.65 : 0.82, proposed ? 0.15 : 0.82);
        if (proposed) {
            repeat_actor->GetProperty()->SetRepresentationToWireframe();
            repeat_actor->GetProperty()->SetLineWidth(2.0);
        }
        renderer->AddActor(repeat_actor);
        window->Render();
    }
    void propose_repeats(const std::string& value) {
        if (active != "full" || !glyph_mappers.empty() || repeat_accepted)
            throw std::runtime_error("select a mesh component at Full LOD before matching repeats");
        vtkIdType selected = -1;
        std::string extra;
        std::istringstream input(value);
        if (!(input >> selected) || (input >> extra) || selected < 0)
            throw std::runtime_error("repeat proposal requires a selected source cell");
        repeat_proposal = gx3d_repeat::discover(geometry("full"),selected);
        show_repeat_actor(true);
        std::cout << "{\"event\":\"repeat_proposal\",\"source_cell\":" << selected
                  << ",\"matches\":" << repeat_proposal->matches.size()
                  << ",\"triangles_per_component\":" << repeat_proposal->source_triangles
                  << ",\"rigid_transform\":\"orthogonal_rotation_translation\"}" << std::endl;
    }
    void reject_repeats() {
        if (repeat_accepted) throw std::runtime_error("accepted repeats are stored in the Session");
        if (repeat_actor) renderer->RemoveActor(repeat_actor);
        repeat_actor = nullptr;
        repeat_mapper = nullptr;
        repeat_proposal.reset();
        window->Render();
        std::cout << "{\"event\":\"repeat_rejected\"}" << std::endl;
    }
    fs::path repeat_cache_directory(vtkIdType cell) const {
        return cache / ("repeat_cell_" + std::to_string(cell));
    }
    void save_repeat_cache(const gx3d_repeat::Proposal& proposal, vtkPolyData* remaining) {
        const auto final = repeat_cache_directory(proposal.source_cell);
        if (fs::is_regular_file(final / "complete")) return;
        const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
        const auto stage = cache / (".repeat_cell_" + std::to_string(proposal.source_cell) +
            ".tmp-" + std::to_string(stamp));
        fs::create_directory(stage);
        try {
            const auto prototype = stage / "prototype.gx3d";
            gx3d_cache::write(prototype,proposal.prototype);
            write_chunk_marker(prototype);
            std::vector<gx3d_cache::Placement> instances;
            instances.reserve(proposal.matches.size());
            for (const auto& match : proposal.matches) {
                gx3d_cache::Placement placement{};
                for (int axis=0; axis<3; ++axis) placement.pose[axis] = match.center[axis];
                for (int axis=0; axis<4; ++axis) placement.pose[axis+3] = match.quaternion[axis];
                instances.push_back(placement);
            }
            const auto locations = stage / "placements.gx3di";
            gx3d_cache::write_instances(locations,1,instances);
            write_chunk_marker(locations);
            if (remaining->GetNumberOfPolys()) {
                const auto remainder = stage / "remainder.gx3d";
                gx3d_cache::write(remainder,remaining);
                write_chunk_marker(remainder);
            }
            std::ifstream full_marker(cache / "lod_full.gx3d.sha256");
            std::string full_hash;
            if (!(full_marker >> full_hash) || full_hash.size() != 64)
                throw std::runtime_error("source Full LOD hash is unavailable for repeat cache");
            std::ofstream complete(stage / "complete",std::ios::binary);
            complete << "GX3D_REPEAT_v1 " << full_hash << ' ' << proposal.source_cell << ' '
                     << proposal.matches.size() << ' ' << proposal.source_triangles << ' '
                     << remaining->GetNumberOfPolys() << '\n';
            complete.close();
            if (!complete) throw std::runtime_error("repeat cache commit marker write failed");
            fs::rename(stage,final);
        } catch (...) {
            fs::remove_all(stage);
            throw;
        }
    }
    bool load_repeat_cache(vtkIdType selected) {
        const auto directory = repeat_cache_directory(selected);
        if (!fs::is_regular_file(directory / "complete")) return false;
        try {
            std::ifstream complete(directory / "complete",std::ios::binary);
            std::string version, source_hash, extra;
            vtkIdType recorded_cell = -1, source_triangles = 0, remainder_triangles = 0;
            uint64_t instances = 0;
            if (!(complete >> version >> source_hash >> recorded_cell >> instances >>
                    source_triangles >> remainder_triangles) || (complete >> extra) ||
                version != "GX3D_REPEAT_v1" || source_hash.size() != 64 ||
                recorded_cell != selected || instances < 2 || instances > 1000000 ||
                source_triangles < 1 || remainder_triangles < 0)
                throw std::runtime_error("repeat cache commit marker is invalid");
            std::ifstream full_marker(cache / "lod_full.gx3d.sha256");
            std::string actual_source_hash;
            if (!(full_marker >> actual_source_hash) || actual_source_hash != source_hash)
                throw std::runtime_error("repeat cache source Full LOD changed");
            const auto prototype = directory / "prototype.gx3d";
            const auto locations = directory / "placements.gx3di";
            validate_chunk(prototype);
            validate_chunk(locations);
            gx3d_cache::MappedFile mapped(locations);
            const auto header = gx3d_cache::checked_instance_header(mapped.data(),mapped.size());
            if (header.prototypes != 1 || header.instances != instances)
                throw std::runtime_error("repeat cache placement count changed");
            gx3d_repeat::Proposal restored;
            restored.source_cell = selected;
            restored.source_triangles = source_triangles;
            restored.prototype = gx3d_cache::read(prototype);
            if (restored.prototype->GetNumberOfPolys() != source_triangles)
                throw std::runtime_error("repeat cache prototype geometry changed");
            const auto* bytes = static_cast<const uint8_t*>(mapped.data());
            for (uint64_t i=0; i<instances; ++i) {
                gx3d_cache::Placement placement{};
                std::memcpy(&placement,bytes + header.records_offset + i*sizeof(placement),sizeof(placement));
                if (placement.prototype != 0 || placement.reserved != 0)
                    throw std::runtime_error("repeat cache prototype index is invalid");
                gx3d_repeat::Match match;
                for (int axis=0; axis<3; ++axis) match.center[axis] = placement.pose[axis];
                for (int axis=0; axis<4; ++axis) match.quaternion[axis] = placement.pose[axis+3];
                for (double value : placement.pose) if (!std::isfinite(value))
                    throw std::runtime_error("repeat cache placement is nonfinite");
                restored.matches.push_back(std::move(match));
            }
            vtkSmartPointer<vtkPolyData> remaining;
            if (remainder_triangles) {
                const auto path = directory / "remainder.gx3d";
                validate_chunk(path);
                remaining = gx3d_cache::read(path);
                if (remaining->GetNumberOfPolys() != remainder_triangles)
                    throw std::runtime_error("repeat cache remainder geometry changed");
            } else {
                remaining = vtkSmartPointer<vtkPolyData>::New();
                vtkNew<vtkPoints> empty_points;
                vtkNew<vtkCellArray> empty_cells;
                remaining->SetPoints(empty_points);
                remaining->SetPolys(empty_cells);
            }
            repeat_proposal = std::move(restored);
            repeat_remainder = remaining;
            show_repeat_actor(false);
            mapper->SetInputData(repeat_remainder);
            repeat_accepted = true;
            resident[4] = nullptr;
            renderer->ResetCameraClippingRange(); window->Render();
            std::cout << "{\"event\":\"repeat_ready\",\"source_cell\":" << selected
                      << ",\"instances\":" << instances
                      << ",\"prototype_triangles\":" << source_triangles
                      << ",\"remainder_triangles\":" << remainder_triangles
                      << ",\"cache_hit\":true}" << std::endl;
            return true;
        } catch (const std::exception& problem) {
            std::cout << "{\"event\":\"repeat_cache_invalid\",\"reason\":\""
                      << json_text(problem.what()) << "\"}" << std::endl;
            fs::remove_all(directory);
            return false;
        }
    }
    void accept_repeats() {
        if (!repeat_proposal || repeat_accepted)
            throw std::runtime_error("no repeat proposal is awaiting acceptance");
        auto remaining = gx3d_repeat::remainder(geometry("full"),*repeat_proposal);
        save_repeat_cache(*repeat_proposal,remaining);
        repeat_remainder = remaining;
        mapper->SetInputData(repeat_remainder);
        repeat_actor->GetProperty()->SetRepresentationToSurface();
        repeat_actor->GetProperty()->SetColor(0.3,0.82,0.82);
        repeat_actor->GetProperty()->SetOpacity(actor->GetProperty()->GetOpacity());
        repeat_accepted = true;
        resident[4] = nullptr;
        renderer->ResetCameraClippingRange();
        window->Render();
        std::cout << "{\"event\":\"repeat_ready\",\"source_cell\":"
                  << repeat_proposal->source_cell << ",\"instances\":"
                  << repeat_proposal->matches.size() << ",\"prototype_triangles\":"
                  << repeat_proposal->source_triangles << ",\"remainder_triangles\":"
                  << repeat_remainder->GetNumberOfPolys() << ",\"cache_hit\":false}" << std::endl;
    }
    void benchmark(const std::string& value) {
        int frames = 0;
        try { frames = std::stoi(value); } catch (...) { throw std::runtime_error("invalid benchmark frame count"); }
        if (frames < 2 || frames > 240) throw std::runtime_error("benchmark frames must be 2..240");
        vtkNew<vtkCamera> saved;
        auto* camera = renderer->GetActiveCamera();
        saved->DeepCopy(camera);
        std::vector<double> frame_seconds;
        frame_seconds.reserve(static_cast<size_t>(frames));
        for (int i=0; i<frames; ++i) {
            const auto start = std::chrono::steady_clock::now();
            camera->Azimuth(1);
            renderer->ResetCameraClippingRange();
            window->Render();
            frame_seconds.push_back(std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());
        }
        camera->DeepCopy(saved);
        renderer->ResetCameraClippingRange();
        window->Render();
        std::sort(frame_seconds.begin(), frame_seconds.end());
        double total = 0;
        for (double seconds : frame_seconds) total += seconds;
        const double slowest = frame_seconds.back();
        const double p95 = frame_seconds[static_cast<size_t>(std::ceil(frames * .95)) - 1];
        std::cout << "{\"event\":\"benchmark\",\"frames\":" << frames
                  << ",\"lod\":\"" << active << "\",\"average_fps\":" << frames / total
                  << ",\"minimum_fps\":" << 1.0 / slowest
                  << ",\"p95_frame_ms\":" << p95 * 1000.0
                  << ",\"slowest_frame_ms\":" << slowest * 1000.0
                  << ",\"peak_rss_mib\":" << peak_memory_mib()
                  << "}" << std::endl;
    }
    void benchmark_sequence() {
        vtkNew<vtkCamera> saved;
        auto* camera = renderer->GetActiveCamera();
        saved->DeepCopy(camera);
        for (int i=0; i<10; ++i) window->Render();
        const auto started = std::chrono::steady_clock::now();
        std::vector<double> frame_seconds;
        frame_seconds.reserve(76);
        double first_frame_ms = 0;
        auto render_step = [&]() {
            const auto begin = std::chrono::steady_clock::now();
            renderer->ResetCameraClippingRange();
            window->Render();
            const auto finish = std::chrono::steady_clock::now();
            frame_seconds.push_back(std::chrono::duration<double>(finish-begin).count());
            if (first_frame_ms == 0)
                first_frame_ms = std::chrono::duration<double,std::milli>(finish-started).count();
        };
        for (int i=0; i<30; ++i) {camera->Azimuth(1.0); render_step();}
        for (int i=0; i<15; ++i) {camera->Elevation(1.0); render_step();}
        double direction[3]{}, up[3]{}, right[3]{};
        camera->GetDirectionOfProjection(direction);
        camera->GetViewUp(up);
        vtkMath::Cross(direction,up,right);
        if (vtkMath::Normalize(right) == 0) throw std::runtime_error("camera pan direction is invalid");
        double position[3]{}, target[3]{};
        camera->GetPosition(position); camera->GetFocalPoint(target);
        const double distance = std::sqrt(vtkMath::Distance2BetweenPoints(position,target));
        const double height = camera->GetParallelProjection() ? 2.0*camera->GetParallelScale() :
            2.0*distance*std::tan(vtkMath::RadiansFromDegrees(camera->GetViewAngle())/2.0);
        const int* viewport = window->GetSize();
        const double width = height * (viewport[1] > 0 ? double(viewport[0])/viewport[1] : 1.0);
        const double pan_step = width*0.01;
        auto pan = [&](double sign) {
            camera->GetPosition(position); camera->GetFocalPoint(target);
            for (int coordinate=0; coordinate<3; ++coordinate) {
                position[coordinate] += sign*right[coordinate]*pan_step;
                target[coordinate] += sign*right[coordinate]*pan_step;
            }
            camera->SetPosition(position); camera->SetFocalPoint(target);
            render_step();
        };
        for (int i=0; i<10; ++i) pan(1.0);
        const double zoom_step = std::pow(1.25,0.1);
        for (int i=0; i<10; ++i) {camera->Zoom(zoom_step); render_step();}
        for (int i=0; i<10; ++i) pan(-1.0);
        camera->DeepCopy(saved); render_step();
        std::sort(frame_seconds.begin(),frame_seconds.end());
        double total = 0;
        for (double seconds : frame_seconds) total += seconds;
        const double slowest = frame_seconds.back();
        const double p95 = frame_seconds[static_cast<size_t>(std::ceil(frame_seconds.size()*.95))-1];
        uint64_t geometry_bytes = 0;
        if (fs::is_regular_file(cache / "step_instances.gx3di")) {
            geometry_bytes = fs::file_size(cache / "step_instances.gx3di");
            const auto suffix = "_lod_" + active + ".gx3d";
            for (const auto& entry : fs::directory_iterator(cache)) {
                const auto name = entry.path().filename().string();
                if (entry.is_regular_file() && name.rfind("prototype_",0) == 0 &&
                    name.size() >= suffix.size() &&
                    name.compare(name.size()-suffix.size(),suffix.size(),suffix) == 0)
                    geometry_bytes += entry.file_size();
            }
        } else if (repeat_accepted && active == "full" && repeat_proposal) {
            const auto directory = repeat_cache_directory(repeat_proposal->source_cell);
            for (const auto& name : {"prototype.gx3d","placements.gx3di","remainder.gx3d"}) {
                const auto chunk = directory / name;
                if (fs::is_regular_file(chunk)) geometry_bytes += fs::file_size(chunk);
            }
        } else {
            const auto chunk = cache / ("lod_"+active+".gx3d");
            if (fs::is_regular_file(chunk)) geometry_bytes = fs::file_size(chunk);
        }
        const auto source_full = cache / "lod_full.gx3d";
        const auto source_full_bytes = fs::is_regular_file(source_full) ? fs::file_size(source_full) : 0;
        renderer->ResetCameraClippingRange(); window->Render();
        std::cout << "{\"event\":\"benchmark_sequence\",\"sequence\":\"warmup10_azimuth30_elevation15_pan10_zoom1.25_reversepan10_restore\""
                  << ",\"frames\":" << frame_seconds.size()
                  << ",\"first_frame_ms\":" << first_frame_ms
                  << ",\"average_fps\":" << frame_seconds.size()/total
                  << ",\"minimum_fps\":" << 1.0/slowest
                  << ",\"p95_frame_ms\":" << p95*1000.0
                  << ",\"slowest_frame_ms\":" << slowest*1000.0
                  << ",\"active_lod\":\"" << active << "\""
                  << ",\"requested_lod\":\"" << requested << "\""
                  << ",\"cache_geometry_bytes\":" << geometry_bytes
                  << ",\"source_full_cache_bytes\":" << source_full_bytes
                  << ",\"representation\":\"" << (repeat_accepted && active == "full" ?
                      "mesh_repeat_instanced" : "source_lod") << "\""
                  << ",\"repeat_instances\":" << (repeat_accepted && repeat_proposal ?
                      repeat_proposal->matches.size() : 0)
                  << ",\"peak_rss_mib\":" << peak_memory_mib() << "}" << std::endl;
    }
    void command(const std::string& line) {
        const auto space = line.find(' ');
        const std::string verb = line.substr(0,space);
        const std::string value = space == std::string::npos ? "" : line.substr(space+1);
        if (verb == "LOD") { if (lod_index(value) < 0) throw std::runtime_error("invalid LOD"); requested=value; if (!interaction) switch_lod(value); }
        else if (verb == "FIT" || verb == "RESET") { renderer->ResetCamera(); window->Render(); camera_event(); }
        else if (verb == "PRESET") preset(value);
        else if (verb == "ARROW") arrow(value);
        else if (verb == "ADD_VTU") add_vtu_layer(value);
        else if (verb == "ADD_SCIENTIFIC") add_scientific_layer(value);
        else if (verb == "ADD_DATASET_POINTS") add_dataset_points(value);
        else if (verb == "ADD_PATTERN_REGION") add_pattern_region(value);
        else if (verb == "PROPOSE_REPEATS") propose_repeats(value);
        else if (verb == "ACCEPT_REPEATS") accept_repeats();
        else if (verb == "REJECT_REPEATS") reject_repeats();
        else if (verb == "APPLY_REPEATS") {
            vtkIdType selected = -1;
            std::string extra;
            std::istringstream input(value);
            if (!(input >> selected) || (input >> extra) || selected < 0 ||
                active != "full" || !glyph_mappers.empty() || repeat_accepted)
                throw std::runtime_error("saved repeats require a selected mesh cell at Full LOD");
            if (!load_repeat_cache(selected)) { propose_repeats(value); accept_repeats(); }
        }
        else if (verb == "OBJECT_VISIBLE") {
            std::istringstream input(value);
            int index = -1;
            std::string visible, extra;
            if (!(input >> index >> visible) || (input >> extra) ||
                index < 0 || static_cast<size_t>(index) >= prototype_actors.size() ||
                !prototype_actors[static_cast<size_t>(index)] ||
                (visible != "0" && visible != "1"))
                throw std::runtime_error("assembly object visibility requires a valid index and 0 or 1");
            prototype_actors[static_cast<size_t>(index)]->SetVisibility(visible == "1");
            window->Render();
            std::cout << "{\"event\":\"object_visibility\",\"index\":" << index
                      << ",\"visible\":" << visible << "}" << std::endl;
        }
        else if (verb == "LAYER_VISIBLE") {
            std::istringstream input(value);
            std::string id, visible, extra;
            if (!(input >> id >> visible) || (input >> extra) || (visible != "0" && visible != "1"))
                throw std::runtime_error("layer visibility requires an ID and 0 or 1");
            const auto found = scientific_layers.find(id);
            if (found == scientific_layers.end()) throw std::runtime_error("unknown scientific layer");
            found->second.surface->SetVisibility(visible == "1");
            if (found->second.vectors) found->second.vectors->SetVisibility(visible == "1");
            window->Render();
            std::cout << "{\"event\":\"layer_visibility\",\"id\":\"" << id
                      << "\",\"visible\":" << visible << "}" << std::endl;
        }
        else if (verb == "LAYER_OPACITY") {
            std::istringstream input(value);
            std::string id, extra;
            double opacity = 0;
            if (!(input >> id >> opacity) || (input >> extra) ||
                !std::isfinite(opacity) || opacity < 0 || opacity > 1)
                throw std::runtime_error("layer opacity requires an ID and value 0..1");
            const auto found = scientific_layers.find(id);
            if (found == scientific_layers.end()) throw std::runtime_error("unknown scientific layer");
            found->second.surface->GetProperty()->SetOpacity(opacity);
            if (found->second.vectors) found->second.vectors->GetProperty()->SetOpacity(opacity);
            window->Render();
            std::cout << "{\"event\":\"layer_opacity\",\"id\":\"" << id
                      << "\",\"opacity\":" << opacity << "}" << std::endl;
        }
        else if (verb == "LAYER_MODE") {
            std::istringstream input(value);
            std::string id, mode, extra;
            if (!(input >> id >> mode) || (input >> extra) ||
                (mode != "surface" && mode != "wireframe" && mode != "points"))
                throw std::runtime_error("layer mode requires surface, wireframe or points");
            const auto found = scientific_layers.find(id);
            if (found == scientific_layers.end()) throw std::runtime_error("unknown scientific layer");
            if (mode == "surface") found->second.surface->GetProperty()->SetRepresentationToSurface();
            else if (mode == "wireframe") found->second.surface->GetProperty()->SetRepresentationToWireframe();
            else found->second.surface->GetProperty()->SetRepresentationToPoints();
            window->Render();
            std::cout << "{\"event\":\"layer_mode\",\"id\":\"" << id
                      << "\",\"mode\":\"" << mode << "\"}" << std::endl;
        }
        else if (verb == "LAYER_REMOVE") {
            const auto found = scientific_layers.find(value);
            if (found == scientific_layers.end()) throw std::runtime_error("unknown scientific layer");
            renderer->RemoveActor(found->second.surface);
            if (found->second.vectors) renderer->RemoveActor(found->second.vectors);
            scientific_layers.erase(found);
            window->Render();
            std::cout << "{\"event\":\"layer_removed\",\"id\":\"" << value << "\"}" << std::endl;
        }
        else if (verb == "CAPABILITIES") capabilities();
        else if (verb == "BENCHMARK") benchmark(value);
        else if (verb == "BENCHMARK_SEQUENCE") benchmark_sequence();
        else if (verb == "SCREENSHOT") {
            if (value.empty() || fs::path(value).extension() != ".png" ||
                !fs::is_directory(fs::path(value).parent_path()))
                throw std::runtime_error("screenshot requires a PNG path in an existing directory");
            vtkNew<vtkRenderLargeImage> capture;
            capture->SetInput(renderer);
            capture->SetMagnification(1);
            capture->Update();
            vtkNew<vtkPNGWriter> writer;
            writer->SetFileName(value.c_str());
            writer->SetInputConnection(capture->GetOutputPort());
            writer->Write();
            if (!fs::is_regular_file(value) || fs::file_size(value) < 100)
                throw std::runtime_error("native screenshot write failed");
            std::cout << "{\"event\":\"screenshot\",\"path\":\""
                      << json_text(value) << "\"}" << std::endl;
        }
        else if (verb == "PROJECTION") {
            if (value != "orthographic" && value != "perspective") throw std::runtime_error("invalid projection");
            renderer->GetActiveCamera()->SetParallelProjection(value == "orthographic"); window->Render(); camera_event();
        } else if (verb == "SET_CAMERA") {
            std::istringstream input(value);
            double number[11]{};
            std::string kind, extra;
            for (double& item : number) if (!(input >> item) || !std::isfinite(item))
                throw std::runtime_error("invalid saved camera vector");
            if (!(input >> kind) || (input >> extra) || (kind != "perspective" && kind != "orthographic") ||
                number[9] <= 0 || number[10] <= 0 ||
                (number[0] == number[3] && number[1] == number[4] && number[2] == number[5]))
                throw std::runtime_error("invalid saved camera state");
            auto* camera = renderer->GetActiveCamera();
            camera->SetPosition(number[0], number[1], number[2]);
            camera->SetFocalPoint(number[3], number[4], number[5]);
            camera->SetViewUp(number[6], number[7], number[8]);
            camera->SetParallelScale(number[9]);
            camera->SetViewAngle(number[10]);
            camera->SetParallelProjection(kind == "orthographic");
            renderer->ResetCameraClippingRange(); window->Render(); camera_event();
        } else if (verb == "MODE") {
            if (value != "surface" && value != "wireframe" && value != "surface_edges")
                throw std::runtime_error("invalid display mode");
            std::vector<vtkActor*> targets{actor};
            for (const auto& placed : glyph_actors) targets.push_back(placed);
            if (repeat_actor && repeat_accepted) targets.push_back(repeat_actor);
            for (auto* target : targets) {
                if (value == "wireframe") target->GetProperty()->SetRepresentationToWireframe();
                else target->GetProperty()->SetRepresentationToSurface();
                target->GetProperty()->SetEdgeVisibility(value == "surface_edges");
            }
            window->Render();
        } else if (verb == "VISIBLE") {
            if (value != "0" && value != "1") throw std::runtime_error("invalid visibility");
            actor->SetVisibility(value == "1");
            for (const auto& placed : glyph_actors) placed->SetVisibility(value == "1");
            if (repeat_actor) repeat_actor->SetVisibility(value == "1" && active == "full");
            window->Render();
        } else if (verb == "OPACITY") {
            std::istringstream input(value);
            double opacity = 0;
            std::string extra;
            if (!(input >> opacity) || (input >> extra) || !std::isfinite(opacity) ||
                opacity < 0 || opacity > 1)
                throw std::runtime_error("opacity must be between 0 and 1");
            actor->GetProperty()->SetOpacity(opacity);
            for (const auto& placed : glyph_actors) placed->GetProperty()->SetOpacity(opacity);
            if (repeat_actor && repeat_accepted) repeat_actor->GetProperty()->SetOpacity(opacity);
            window->Render();
        } else if (verb == "BACKGROUND") {
            std::istringstream input(value);
            double rgb[3]{};
            std::string extra;
            for (double& channel : rgb)
                if (!(input >> channel) || !std::isfinite(channel) || channel < 0 || channel > 1)
                    throw std::runtime_error("background requires three colors between 0 and 1");
            if (input >> extra) throw std::runtime_error("background requires exactly three colors");
            renderer->SetBackground(rgb);
            window->Render();
        } else if (verb == "LIGHTING") {
            if (value != "0" && value != "1") throw std::runtime_error("lighting requires 0 or 1");
            actor->GetProperty()->SetLighting(value == "1");
            for (const auto& placed : glyph_actors) placed->GetProperty()->SetLighting(value == "1");
            window->Render();
        } else if (verb == "CLIP") {
            std::vector<vtkMapper*> targets{mapper};
            for (const auto& glyph : glyph_mappers) targets.push_back(glyph);
            if (repeat_mapper) targets.push_back(repeat_mapper);
            for (auto* target : targets) target->RemoveAllClippingPlanes();
            if (value != "OFF") {
                std::istringstream input(value);
                std::string axis, extra;
                double fraction = 0;
                if (!(input >> axis >> fraction) || (input >> extra) ||
                    axis.size() != 1 || axis.find_first_not_of("xyz") != std::string::npos ||
                    !std::isfinite(fraction) || fraction < 0 || fraction > 1)
                    throw std::runtime_error("clip requires x, y or z and fraction 0..1");
                const int coordinate = axis[0] - 'x';
                double origin[3] = {(scene_bounds[0]+scene_bounds[1])*0.5,
                                    (scene_bounds[2]+scene_bounds[3])*0.5,
                                    (scene_bounds[4]+scene_bounds[5])*0.5};
                double normal[3] = {0,0,0};
                origin[coordinate] = scene_bounds[2*coordinate] + fraction *
                    (scene_bounds[2*coordinate+1] - scene_bounds[2*coordinate]);
                normal[coordinate] = 1;
                clip_plane->SetOrigin(origin);
                clip_plane->SetNormal(normal);
                for (auto* target : targets) target->AddClippingPlane(clip_plane);
            }
            window->Render();
        }
        else if (verb == "CLIP_PLANE") {
            std::istringstream input(value);
            double nx, ny, nz, d;
            std::string extra;
            if (!(input >> nx >> ny >> nz >> d) || (input >> extra) ||
                !std::isfinite(nx) || !std::isfinite(ny) || !std::isfinite(nz) ||
                !std::isfinite(d) || nx*nx+ny*ny+nz*nz == 0)
                throw std::runtime_error("clip plane requires finite nx ny nz d");
            const double norm2 = nx*nx+ny*ny+nz*nz;
            clip_plane->SetNormal(nx, ny, nz);
            clip_plane->SetOrigin(-d*nx/norm2, -d*ny/norm2, -d*nz/norm2);
            std::vector<vtkMapper*> targets{mapper};
            for (const auto& glyph : glyph_mappers) targets.push_back(glyph);
            if (repeat_mapper) targets.push_back(repeat_mapper);
            for (auto* target : targets) {
                target->RemoveAllClippingPlanes();
                target->AddClippingPlane(clip_plane);
            }
            window->Render();
        }
        else if (verb == "WORKING_PLANE") {
            std::istringstream input(value);
            double origin[3], normal[3], u_axis[3];
            int visible=0;
            std::string extra;
            for (double& coordinate : origin) if (!(input >> coordinate) || !std::isfinite(coordinate))
                throw std::runtime_error("working plane requires finite origin");
            for (double& coordinate : normal) if (!(input >> coordinate) || !std::isfinite(coordinate))
                throw std::runtime_error("working plane requires finite normal");
            for (double& coordinate : u_axis) if (!(input >> coordinate) || !std::isfinite(coordinate))
                throw std::runtime_error("working plane requires finite U axis");
            if (!(input >> visible) || (input >> extra) || (visible != 0 && visible != 1) ||
                vtkMath::Norm(normal) < 1e-12 || vtkMath::Norm(u_axis) < 1e-12)
                throw std::runtime_error("working plane requires nonzero normal/U and visibility 0 or 1");
            vtkMath::Normalize(normal);
            const double projection=vtkMath::Dot(normal,u_axis);
            for (int j=0;j<3;++j) u_axis[j]-=projection*normal[j];
            if (vtkMath::Norm(u_axis) < 1e-12) throw std::runtime_error("working plane U is parallel to normal");
            vtkMath::Normalize(u_axis);
            for (int j=0;j<3;++j) working_u_axis[static_cast<size_t>(j)]=u_axis[j];
            working_plane_representation->SetOrigin(origin);
            working_plane_representation->SetNormal(normal);
            working_plane_widget->SetEnabled(visible);
            working_plane_enabled=(visible != 0);
            plane_event();
            window->Render();
        }
        else if (verb == "CAMERA") camera_event();
        else if (verb == "QUIT") {
            std::cout << "{\"event\":\"quit_ack\"}" << std::endl;
            std::_Exit(0);
        }
        else throw std::runtime_error("unknown command");
    }
    void setup() {
        configure_display_budget();
        if (!scene_only) check_display_budget(requested);
        if (scene_only) {
            renderer->SetBackground(0.12,0.14,0.18);
            window->SetWindowName("GX-TXT Scientific 3D Scene"); window->SetSize(1100,750); window->AddRenderer(renderer);
            interactor->SetRenderWindow(window); interactor->SetInteractorStyle(style);
            renderer->ResetCamera(); window->Render(); interactor->Initialize();
            configure_working_plane();
            active=requested;
            std::cout << "{\"event\":\"interactive\",\"lod\":\"scene\",\"triangles\":0,\"render_mode\":\"scene\"}" << std::endl;
            camera_event();
            return;
        }
        if (!fs::is_regular_file(cache / "manifest.json") &&
            !(requested == "preview" && fs::is_regular_file(cache / "preview.ready")))
            throw std::runtime_error("cache manifest or preview marker is missing");
        if (fs::is_regular_file(cache / "manifest.json")) {
            if (gx3d_context_create(&abi_context) != GX3D_OK ||
                gx3d_cache_open(abi_context, (cache / "manifest.json").string().c_str(), &abi_model) != GX3D_OK)
                throw std::runtime_error("native ABI rejected display cache");
        }
        if (fs::is_regular_file(cache / "step_instances.gx3di") && fs::is_regular_file(cache / "manifest.json")) {
            load_instances();
        } else {
            mapper->SetInputData(geometry(requested)); mapper->ScalarVisibilityOff();
            actor->SetMapper(mapper);
            renderer->AddActor(actor);
        }
        renderer->SetBackground(0.12,0.14,0.18);
        window->SetWindowName("GX-TXT Native 3D Viewer"); window->SetSize(1100,750); window->AddRenderer(renderer);
        interactor->SetRenderWindow(window); interactor->SetInteractorStyle(style);
        renderer->ComputeVisiblePropBounds(scene_bounds.data());
        if (!glyph_mappers.empty()) {
            const auto* bounds = scene_bounds.data();
            const double width = bounds[1] - bounds[0];
            const double depth = bounds[3] - bounds[2];
            const double height = bounds[5] - bounds[4];
            // A tall assembly viewed down Z collapses into a tiny end-on patch.
            // Start from its broad side while preserving normal mouse camera control.
            if (std::isfinite(height) && height > 2.0 * std::max(width, depth)) {
                const double center[3] = {(bounds[0]+bounds[1])*0.5,
                                          (bounds[2]+bounds[3])*0.5,
                                          (bounds[4]+bounds[5])*0.5};
                auto* camera = renderer->GetActiveCamera();
                camera->SetFocalPoint(center);
                camera->SetPosition(center[0], center[1] + height, center[2]);
                camera->SetViewUp(0, 0, 1);
            }
        }
        renderer->ResetCamera(); window->Render(); interactor->Initialize();
        configure_working_plane();
        active=requested;
        const auto count = glyph_mappers.empty() ? geometry(active)->GetNumberOfPolys() : displayed_triangles(active);
        std::cout << "{\"event\":\"interactive\",\"lod\":\"" << active << "\",\"triangles\":" << count
                  << ",\"render_mode\":\"" << (glyph_mappers.empty() ? "flat" : "instanced") << "\"}" << std::endl;
        camera_event();
    }
    void configure_working_plane() {
        working_plane_representation->SetPlaceFactor(1.0);
        double bounds[6];renderer->ComputeVisiblePropBounds(bounds);
        if (bounds[0] > bounds[1]) for (int j=0;j<3;++j) { bounds[2*j]=-1;bounds[2*j+1]=1; }
        working_plane_representation->PlaceWidget(bounds);
        working_plane_representation->SetDrawPlane(true);
        working_plane_representation->SetOutlineTranslation(true);
        working_plane_widget->SetInteractor(interactor);
        working_plane_widget->SetRepresentation(working_plane_representation);
        working_axes->SetXAxisLabelText("U");working_axes->SetYAxisLabelText("V");working_axes->SetZAxisLabelText("N");
        const double extent=std::max({bounds[1]-bounds[0],bounds[3]-bounds[2],bounds[5]-bounds[4],1e-3});
        working_axes->SetTotalLength(0.2*extent,0.2*extent,0.2*extent);
        working_axes->PickableOff();working_axes->SetVisibility(false);renderer->AddActor(working_axes);
    }
    void plane_event() {
        vtkNew<vtkPlane> plane;working_plane_representation->GetPlane(plane);
        double origin[3],normal[3],u[3],v[3];
        plane->GetOrigin(origin);plane->GetNormal(normal);vtkMath::Normalize(normal);
        double hint[3]={working_u_axis[0],working_u_axis[1],working_u_axis[2]};
        const double projection=vtkMath::Dot(hint,normal);
        for (int j=0;j<3;++j) hint[j]-=projection*normal[j];
        if (vtkMath::Norm(hint)<1e-8) {hint[0]=1;hint[1]=0;hint[2]=0;
            const double p=vtkMath::Dot(hint,normal);for(int j=0;j<3;++j)hint[j]-=p*normal[j];}
        if (vtkMath::Norm(hint)<1e-8) {hint[0]=0;hint[1]=1;hint[2]=0;
            const double p=vtkMath::Dot(hint,normal);for(int j=0;j<3;++j)hint[j]-=p*normal[j];}
        vtkMath::Normalize(hint);vtkMath::Cross(normal,hint,v);vtkMath::Normalize(v);vtkMath::Cross(v,normal,u);vtkMath::Normalize(u);
        vtkNew<vtkMatrix4x4> frame;
        for (int j=0;j<3;++j) {frame->SetElement(j,0,u[j]);frame->SetElement(j,1,v[j]);frame->SetElement(j,2,normal[j]);frame->SetElement(j,3,origin[j]);working_u_axis[static_cast<size_t>(j)]=u[j];}
        working_axes->SetUserMatrix(frame);working_axes->SetVisibility(working_plane_enabled);
        std::cout << "{\"event\":\"plane\",\"origin\":[" << origin[0] << ',' << origin[1] << ',' << origin[2]
                  << "],\"normal\":[" << normal[0] << ',' << normal[1] << ',' << normal[2]
                  << "],\"u_axis\":[" << u[0] << ',' << u[1] << ',' << u[2]
                  << "],\"visible\":" << (working_plane_enabled ? 1 : 0) << "}" << std::endl;
    }
};

class HostCallback : public vtkCommand {
public:
    static HostCallback* New() { return new HostCallback; }
    Host* host{};
    void Execute(vtkObject* sender, unsigned long event, void*) override {
        try {
            if (sender == host->working_plane_widget.GetPointer() &&
                (event == vtkCommand::InteractionEvent || event == vtkCommand::EndInteractionEvent)) {
                host->plane_event();
                return;
            }
            if (event == vtkCommand::TimerEvent) {
                for (int i=0;i<16;++i) {
                    std::string next;
                    { std::lock_guard<std::mutex> lock(host->mutex);
                      if (host->commands.empty()) break;
                      next=std::move(host->commands.front()); host->commands.pop(); }
                    host->command(next);
                }
            } else if (event == vtkCommand::StartInteractionEvent) {
                host->interaction=true;
                if (!host->scene_only && host->active != "low" && host->active != "preview") host->switch_lod("low");
            } else if (event == vtkCommand::EndInteractionEvent) {
                host->interaction=false;
                if (!host->scene_only && host->active != host->requested) host->switch_lod(host->requested);
                host->camera_event();
            } else if (event == vtkCommand::LeftButtonPressEvent) {
                int* xy=host->interactor->GetEventPosition();
                if (host->picker->Pick(xy[0],xy[1],0,host->renderer)) {
                    double* position=host->picker->GetPickPosition();
                    double* normal=host->picker->GetPickNormal();
                    const auto* picked=host->picker->GetActor();
                    std::string source="primary";
                    for (const auto& layer : host->scientific_layers)
                        if (picked == layer.second.surface.GetPointer()) source=layer.first;
                    std::cout << "{\"event\":\"pick\",\"cell_id\":" << host->picker->GetCellId()
                              << ",\"point_id\":" << host->picker->GetPointId()
                              << ",\"position\":[" << position[0] << ',' << position[1] << ',' << position[2]
                              << "],\"normal\":[" << normal[0] << ',' << normal[1] << ',' << normal[2]
                              << "],\"source\":\"" << json_text(source) << "\"}" << std::endl;
                }
            } else if (event == vtkCommand::KeyPressEvent) {
                const std::string key = host->interactor->GetKeySym();
                if (key == "Left") host->arrow("left");
                else if (key == "Right") host->arrow("right");
                else if (key == "Up") host->arrow("up");
                else if (key == "Down") host->arrow("down");
            }
        } catch (const std::exception& e) { std::cout << "{\"event\":\"error\",\"message\":\"" << e.what() << "\"}" << std::endl; }
    }
};

int main(int argc, char** argv) {
    try {
        if (argc < 2 || argc > 3) throw std::runtime_error("usage: gx3d-host <cache-dir> [lod] | --scene");
        Host host;
        if (std::string(argv[1]) == "--scene") {
            if (argc != 2) throw std::runtime_error("scene mode takes no LOD");
            host.scene_only=true;
        } else host.cache=fs::canonical(argv[1]);
        if (argc == 3) host.requested=argv[2];
        host.setup();
        vtkNew<HostCallback> callback; callback->host=&host;
        host.interactor->AddObserver(vtkCommand::TimerEvent,callback);
        host.style->AddObserver(vtkCommand::StartInteractionEvent,callback);
        host.style->AddObserver(vtkCommand::EndInteractionEvent,callback);
        host.interactor->AddObserver(vtkCommand::LeftButtonPressEvent,callback);
        host.interactor->AddObserver(vtkCommand::KeyPressEvent,callback);
        host.working_plane_widget->AddObserver(vtkCommand::InteractionEvent,callback);
        host.working_plane_widget->AddObserver(vtkCommand::EndInteractionEvent,callback);
        std::thread input([&]{
            std::string line;
            while (std::getline(std::cin,line)) {
                if (line.size() > 32768 || line.find_first_of("\r\n\t") != std::string::npos) {
                    std::cout << "{\"event\":\"error\",\"message\":\"invalid native command length or control character\"}" << std::endl;
                    continue;
                }
                std::lock_guard<std::mutex> lock(host.mutex);
                if (host.commands.size() < 128) host.commands.push(line);
            }
            host.input_closed=true;
        });
        input.detach();
        host.interactor->CreateRepeatingTimer(30);
        host.interactor->Start();
        std::cout << "{\"event\":\"closed\"}" << std::endl;
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
