// SPDX-License-Identifier: GPL-3.0-or-later
// Stable, opaque C boundary. GUI processes may use it without exposing a C++ ABI.
#define GX3D_BUILD 1
#include "gx3d.h"
#include <vtkActor.h>
#include <vtkCamera.h>
#include <vtkCellPicker.h>
#include <vtkInteractorStyleTrackballCamera.h>
#include <vtkNew.h>
#include <vtkPolyData.h>
#include <vtkPolyDataMapper.h>
#include <vtkProperty.h>
#include <vtkRenderWindow.h>
#include <vtkRenderWindowInteractor.h>
#include <vtkRenderer.h>
#include "display_cache.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <queue>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;

struct gx3d_context { std::string error; fs::path worker; };
struct ModelState { fs::path cache; std::atomic<int> lod{GX3D_LOD_MEDIUM}; };
struct gx3d_model { std::shared_ptr<ModelState> state; };
struct gx3d_job {
    fs::path cache_root;
    fs::path source;
    fs::path worker;
    std::string key;
    std::mutex mutex;
    std::queue<gx3d_event> events;
    std::thread reader;
    std::atomic<bool> cancelled{false};
    std::atomic<bool> done{false};
    std::atomic<bool> succeeded{false};
    std::atomic<uint64_t> sequence{0};
#ifdef _WIN32
    std::atomic<HANDLE> process{nullptr};
#else
    std::atomic<pid_t> process{0};
#endif
};
struct gx3d_view {
    std::shared_ptr<ModelState> model;
    vtkNew<vtkRenderer> renderer;
    vtkNew<vtkRenderWindow> window;
    vtkNew<vtkRenderWindowInteractor> interactor;
    vtkNew<vtkInteractorStyleTrackballCamera> style;
    vtkNew<vtkPolyDataMapper> mapper;
    vtkNew<vtkActor> actor;
    vtkNew<vtkCellPicker> picker;
    bool shown{false};
    int active_lod{-1};
};

static gx3d_result failure(gx3d_context* context, gx3d_result result, const std::string& message) {
    if (context) context->error = message;
    return result;
}

static std::string json_string(const std::string& line, const std::string& key) {
    const auto start = line.find('"' + key + "\":\"");
    if (start == std::string::npos) return {};
    const auto value = start + key.size() + 4;
    const auto end = line.find('"', value);
    return end == std::string::npos ? std::string{} : line.substr(value, end - value);
}

static uint64_t json_number(const std::string& line, const std::string& key) {
    const auto start = line.find('"' + key + "\":");
    if (start == std::string::npos) return 0;
    try { return std::stoull(line.substr(start + key.size() + 3)); }
    catch (...) { return 0; }
}

static double json_decimal(const std::string& line, const std::string& key) {
    const auto start = line.find('"' + key + "\":");
    if (start == std::string::npos) return 0;
    try { return std::stod(line.substr(start + key.size() + 3)); }
    catch (...) { return 0; }
}

static fs::path worker_near_library() {
#ifdef _WIN32
    HMODULE module{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&gx3d_abi_version), &module)) return {};
    std::wstring path(32768, L'\0');
    const auto length = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    path.resize(length);
    return fs::path(path).parent_path().parent_path() / "bin" / "gx3d-worker.exe";
#else
    Dl_info information{};
    if (!dladdr(reinterpret_cast<void*>(&gx3d_abi_version), &information) || !information.dli_fname) return {};
    return fs::path(information.dli_fname).parent_path().parent_path() / "bin" / "gx3d-worker";
#endif
}

static void push_event(gx3d_job* job, const std::string& line) {
    gx3d_event event{};
    event.struct_size = sizeof(event);
    const auto kind = json_string(line, "event");
    if (kind == "complete" || kind == "cache_hit") event.type = GX3D_EVENT_COMPLETE;
    else if (kind == "preview_ready") event.type = GX3D_EVENT_PREVIEW_READY;
    else if (kind == "error") event.type = GX3D_EVENT_ERROR;
    else event.type = GX3D_EVENT_PROGRESS;
    event.triangles = json_number(line, "triangles");
    event.bytes = json_number(line, "size_bytes");
    event.elapsed_seconds = json_decimal(line, "elapsed_s");
    if (kind == "start" || kind == "cache_hit") job->key = json_string(line, "key");
    if (kind == "preview_ready") event.progress_0_1 = .2;
    else if (kind == "complete" || kind == "cache_hit") event.progress_0_1 = 1;
    else if (kind == "lod_ready") {
        const auto lod = json_string(line, "lod");
        event.progress_0_1 = lod == "low" ? .3 : lod == "medium" ? .5 : lod == "high" ? .75 : .9;
    }
    std::strncpy(event.message_utf8, line.c_str(), sizeof(event.message_utf8) - 1);
    std::lock_guard<std::mutex> guard(job->mutex);
    event.sequence = ++job->sequence;
    job->events.push(event);
}

static void consume_output(gx3d_job* job, const char* data, size_t size, std::string& pending) {
    pending.append(data, size);
    size_t newline = 0;
    while ((newline = pending.find('\n')) != std::string::npos) {
        std::string line = pending.substr(0, newline);
        pending.erase(0, newline + 1);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!line.empty()) push_event(job, line);
    }
    if (pending.size() > 1 << 20) throw std::runtime_error("native worker emitted an oversized event");
}

#ifdef _WIN32
static std::wstring windows_quote(const std::wstring& value) {
    std::wstring output = L"\"";
    unsigned slashes = 0;
    for (wchar_t c : value) {
        if (c == L'\\') { ++slashes; continue; }
        if (c == L'"') { output.append(slashes * 2 + 1, L'\\'); output += L'"'; slashes = 0; continue; }
        output.append(slashes, L'\\'); slashes = 0; output += c;
    }
    output.append(slashes * 2, L'\\');
    output += L'"';
    return output;
}
static void run_worker(gx3d_job* job) {
    SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
    HANDLE read_pipe = nullptr, write_pipe = nullptr;
    if (!CreatePipe(&read_pipe, &write_pipe, &attributes, 0)) throw std::runtime_error("cannot create native worker pipe");
    SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdOutput = write_pipe; startup.hStdError = write_pipe;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION process{};
    std::wstring command = windows_quote(job->worker.wstring()) + L" " +
        windows_quote(job->source.wstring()) + L" " + windows_quote(job->cache_root.wstring());
    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');
    const BOOL created = CreateProcessW(job->worker.c_str(), mutable_command.data(), nullptr, nullptr,
                                        TRUE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process);
    CloseHandle(write_pipe);
    if (!created) { CloseHandle(read_pipe); throw std::runtime_error("cannot launch native worker"); }
    CloseHandle(process.hThread);
    job->process = process.hProcess;
    if (job->cancelled) TerminateProcess(process.hProcess, 130);
    std::string pending;
    std::array<char, 8192> buffer{};
    DWORD read_count = 0;
    while (ReadFile(read_pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &read_count, nullptr) && read_count)
        consume_output(job, buffer.data(), read_count, pending);
    CloseHandle(read_pipe);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 1; GetExitCodeProcess(process.hProcess, &code);
    job->process = nullptr;
    CloseHandle(process.hProcess);
    if (!pending.empty()) push_event(job, pending);
    job->succeeded = code == 0 && !job->cancelled;
}
#else
static void run_worker(gx3d_job* job) {
    int pipes[2];
    if (pipe(pipes) != 0) throw std::runtime_error("cannot create native worker pipe");
    const pid_t pid = fork();
    if (pid < 0) { close(pipes[0]); close(pipes[1]); throw std::runtime_error("cannot launch native worker"); }
    if (pid == 0) {
        close(pipes[0]);
        dup2(pipes[1], STDOUT_FILENO);
        dup2(pipes[1], STDERR_FILENO);
        close(pipes[1]);
        const std::string executable = job->worker.string();
        const std::string source = job->source.string();
        const std::string cache = job->cache_root.string();
        execl(executable.c_str(), executable.c_str(), source.c_str(), cache.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }
    close(pipes[1]);
    job->process = pid;
    if (job->cancelled) kill(pid, SIGTERM);
    std::string pending;
    std::array<char, 8192> buffer{};
    ssize_t size = 0;
    while ((size = read(pipes[0], buffer.data(), buffer.size())) > 0)
        consume_output(job, buffer.data(), static_cast<size_t>(size), pending);
    close(pipes[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    job->process = 0;
    if (!pending.empty()) push_event(job, pending);
    job->succeeded = WIFEXITED(status) && WEXITSTATUS(status) == 0 && !job->cancelled;
}
#endif

static void worker_thread(gx3d_job* job) {
    try { run_worker(job); }
    catch (const std::exception& error) { push_event(job, "{\"event\":\"error\",\"message\":\"" + std::string(error.what()) + "\"}"); }
    job->done = true;
}

extern "C" uint32_t gx3d_abi_version(void) { return GX3D_ABI_VERSION; }
extern "C" const char* gx3d_version_utf8(void) { return "0.8.0"; }
extern "C" gx3d_result gx3d_context_create(gx3d_context** out_context) {
    if (!out_context) return GX3D_E_INVALID;
    *out_context = nullptr;
    try {
        auto context = new gx3d_context;
        context->worker = worker_near_library();
        *out_context = context;
        return GX3D_OK;
    } catch (...) { return GX3D_E_INTERNAL; }
}
extern "C" void gx3d_context_destroy(gx3d_context* context) { delete context; }
extern "C" const char* gx3d_last_error_utf8(gx3d_context* context) { return context ? context->error.c_str() : "invalid context"; }

extern "C" gx3d_result gx3d_import_start(gx3d_context* context, const char* source_utf8,
    const char* cache_root_utf8, const gx3d_import_options* options, gx3d_job** out_job) {
    if (!context || !source_utf8 || !cache_root_utf8 || !out_job || !*source_utf8 || !*cache_root_utf8)
        return failure(context, GX3D_E_INVALID, "source, cache and output job are required");
    *out_job = nullptr;
    if (options && options->struct_size < sizeof(gx3d_import_options))
        return failure(context, GX3D_E_INVALID, "import options have an incompatible struct_size");
    if (options && (options->step_linear_deflection != 0 || options->step_angular_deflection_rad != 0 ||
                    options->interactive_triangle_budget != 0 || options->memory_budget_bytes != 0 ||
                    options->generate_lod_mask != 0 || options->flags != 0))
        return failure(context, GX3D_E_UNSUPPORTED, "native import options are not supported by this worker");
    try {
        if (!fs::is_regular_file(context->worker))
            return failure(context, GX3D_E_IO, "native preprocessing worker is missing");
        auto job = new gx3d_job;
        job->source = fs::absolute(fs::u8path(source_utf8));
        job->cache_root = fs::absolute(fs::u8path(cache_root_utf8));
        job->worker = context->worker;
        if (!fs::is_regular_file(job->source)) { delete job; return failure(context, GX3D_E_IO, "source model is missing"); }
        job->reader = std::thread(worker_thread, job);
        *out_job = job;
        return GX3D_OK;
    } catch (const std::exception& error) { return failure(context, GX3D_E_INTERNAL, error.what()); }
}

extern "C" gx3d_result gx3d_job_cancel(gx3d_job* job) {
    if (!job) return GX3D_E_INVALID;
    job->cancelled = true;
#ifdef _WIN32
    if (auto process = job->process.load()) TerminateProcess(process, 130);
#else
    if (auto process = job->process.load()) kill(process, SIGTERM);
#endif
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_job_poll(gx3d_job* job, gx3d_event* event_out) {
    if (!job || !event_out || event_out->struct_size < sizeof(gx3d_event)) return GX3D_E_INVALID;
    std::lock_guard<std::mutex> guard(job->mutex);
    if (job->events.empty()) return GX3D_E_NOT_READY;
    const auto event = job->events.front(); job->events.pop();
    *event_out = event;
    return GX3D_OK;
}
extern "C" void gx3d_job_destroy(gx3d_job* job) {
    if (!job) return;
    if (!job->done) gx3d_job_cancel(job);
    if (job->reader.joinable()) job->reader.join();
    delete job;
}

extern "C" gx3d_result gx3d_cache_open(gx3d_context* context, const char* cache_manifest_utf8,
                                         gx3d_model** out_model) {
    if (!context || !cache_manifest_utf8 || !out_model)
        return failure(context, GX3D_E_INVALID, "cache manifest and model output are required");
    *out_model = nullptr;
    try {
        const auto manifest = fs::absolute(fs::u8path(cache_manifest_utf8));
        if (!fs::is_regular_file(manifest)) return failure(context, GX3D_E_IO, "display cache manifest is missing");
        if (fs::file_size(manifest) > 65536) return failure(context, GX3D_E_FORMAT, "display cache manifest is oversized");
        std::ifstream input(manifest, std::ios::binary);
        const std::string contents((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
        if (contents.find("\"format\":\"GX3D_DISPLAY_CACHE_v1\"") == std::string::npos ||
            contents.find("\"geometry_format\":\"GX3D_GEOMETRY_v1\"") == std::string::npos)
            return failure(context, GX3D_E_FORMAT, "display cache format is unsupported");
        const bool instanced = contents.find("\"instancing_file\":\"step_instances.gx3di\"") != std::string::npos;
        for (const auto* level : {"preview", "low", "medium", "high", "full"}) {
            if (instanced && std::string(level) != "preview") continue;
            const auto path = manifest.parent_path() / (std::string("lod_") + level + ".gx3d");
            if (!fs::is_regular_file(path) || !fs::is_regular_file(path.string() + ".sha256"))
                return failure(context, GX3D_E_FORMAT, "display cache is incomplete");
        }
        if (instanced) {
            if (!fs::is_regular_file(manifest.parent_path() / "step_instances.gx3di") ||
                !fs::is_regular_file(manifest.parent_path() / "step_instances.gx3di.sha256"))
                return failure(context, GX3D_E_FORMAT, "STEP instance placement cache is missing");
            const auto location = contents.find("\"prototype_count\":");
            if (location == std::string::npos)
                return failure(context, GX3D_E_FORMAT, "STEP prototype count is missing");
            const auto count = std::stoul(contents.substr(location + 18));
            if (!count || count > 10000) return failure(context, GX3D_E_FORMAT, "STEP prototype count is invalid");
            for (unsigned i=0; i<count; ++i) for (const auto* level : {"preview", "low", "medium", "high", "full"}) {
                const auto path = manifest.parent_path() /
                    ("prototype_" + std::to_string(i) + "_lod_" + level + ".gx3d");
                if (!fs::is_regular_file(path) || !fs::is_regular_file(path.string() + ".sha256"))
                    return failure(context, GX3D_E_FORMAT, "STEP prototype display cache is incomplete");
            }
        }
        auto model = new gx3d_model;
        model->state = std::make_shared<ModelState>();
        model->state->cache = manifest.parent_path();
        *out_model = model;
        return GX3D_OK;
    } catch (const std::exception& error) { return failure(context, GX3D_E_INTERNAL, error.what()); }
}

extern "C" gx3d_result gx3d_job_get_model(gx3d_job* job, gx3d_model** out_model) {
    if (!job || !out_model) return GX3D_E_INVALID;
    *out_model = nullptr;
    if (!job->done) return GX3D_E_NOT_READY;
    if (job->cancelled) return GX3D_E_CANCELLED;
    if (!job->succeeded || job->key.empty()) return GX3D_E_IO;
    gx3d_context temporary{};
    return gx3d_cache_open(&temporary, (job->cache_root / job->key / "manifest.json").u8string().c_str(), out_model);
}

extern "C" void gx3d_model_destroy(gx3d_model* model) { delete model; }
extern "C" gx3d_result gx3d_model_set_lod(gx3d_model* model, gx3d_lod lod) {
    if (!model || !model->state || lod < GX3D_LOD_PREVIEW || lod > GX3D_LOD_AUTO) return GX3D_E_INVALID;
    model->state->lod = lod == GX3D_LOD_AUTO ? GX3D_LOD_MEDIUM : lod;
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_model_get_lod(gx3d_model* model, gx3d_lod* lod_out) {
    if (!model || !model->state || !lod_out) return GX3D_E_INVALID;
    *lod_out = static_cast<gx3d_lod>(model->state->lod.load());
    return GX3D_OK;
}

static const std::array<const char*, 5> level_names{{"preview", "low", "medium", "high", "full"}};

static void refresh_view_geometry(gx3d_view* view) {
    const int requested = view->model->lod.load();
    if (view->active_lod == requested) return;
    const auto path = view->model->cache / (std::string("lod_") + level_names.at(requested) + ".gx3d");
    auto poly = gx3d_cache::read(path);
    if (poly->GetNumberOfPolys() <= 0) throw std::runtime_error("display cache LOD is empty");
    view->mapper->SetInputData(poly);
    view->active_lod = requested;
}

extern "C" gx3d_result gx3d_view_create(gx3d_context* context, gx3d_model* model, gx3d_view** out_view) {
    if (!context || !model || !model->state || !out_view)
        return failure(context, GX3D_E_INVALID, "model and view output are required");
    *out_view = nullptr;
    try {
        auto view = new gx3d_view;
        view->model = model->state;
        view->actor->SetMapper(view->mapper);
        view->renderer->AddActor(view->actor);
        view->renderer->SetBackground(.12, .14, .18);
        view->window->AddRenderer(view->renderer);
        view->window->SetSize(1100, 750);
        view->window->SetWindowName("GX-TXT Native 3D Viewer");
        view->interactor->SetRenderWindow(view->window);
        view->interactor->SetInteractorStyle(view->style);
        *out_view = view;
        return GX3D_OK;
    } catch (const std::exception& error) { return failure(context, GX3D_E_INTERNAL, error.what()); }
}
extern "C" void gx3d_view_destroy(gx3d_view* view) { delete view; }
extern "C" gx3d_result gx3d_view_show(gx3d_view* view) {
    if (!view) return GX3D_E_INVALID;
    try {
        refresh_view_geometry(view);
        view->renderer->ResetCamera();
        view->window->Render();
        view->interactor->Initialize();
        view->shown = true;
        return GX3D_OK;
    } catch (...) { return GX3D_E_INTERNAL; }
}
extern "C" gx3d_result gx3d_view_focus(gx3d_view* view) {
    if (!view || !view->shown) return GX3D_E_NOT_READY;
    try {
        refresh_view_geometry(view);
        view->interactor->ProcessEvents();
        view->window->Render();
        return GX3D_OK;
    } catch (...) { return GX3D_E_INTERNAL; }
}

extern "C" gx3d_result gx3d_view_set_camera(gx3d_view* view, const gx3d_camera* camera) {
    if (!view || !camera) return GX3D_E_INVALID;
    for (double value : {camera->position[0], camera->position[1], camera->position[2],
                         camera->target[0], camera->target[1], camera->target[2],
                         camera->up[0], camera->up[1], camera->up[2]})
        if (!std::isfinite(value)) return GX3D_E_INVALID;
    auto* active = view->renderer->GetActiveCamera();
    active->SetPosition(camera->position);
    active->SetFocalPoint(camera->target);
    active->SetViewUp(camera->up);
    active->SetParallelProjection(camera->projection == GX3D_ORTHOGRAPHIC);
    if (camera->parallel_scale > 0) active->SetParallelScale(camera->parallel_scale);
    if (camera->view_angle_deg > 0) active->SetViewAngle(camera->view_angle_deg);
    view->renderer->ResetCameraClippingRange();
    if (view->shown) view->window->Render();
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_view_get_camera(gx3d_view* view, gx3d_camera* camera_out) {
    if (!view || !camera_out) return GX3D_E_INVALID;
    auto* active = view->renderer->GetActiveCamera();
    active->GetPosition(camera_out->position);
    active->GetFocalPoint(camera_out->target);
    active->GetViewUp(camera_out->up);
    camera_out->parallel_scale = active->GetParallelScale();
    camera_out->view_angle_deg = active->GetViewAngle();
    camera_out->projection = active->GetParallelProjection() ? GX3D_ORTHOGRAPHIC : GX3D_PERSPECTIVE;
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_view_fit(gx3d_view* view) {
    if (!view) return GX3D_E_INVALID;
    view->renderer->ResetCamera();
    if (view->shown) view->window->Render();
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_view_set_preset(gx3d_view* view, const char* preset_utf8) {
    if (!view || !preset_utf8) return GX3D_E_INVALID;
    const std::string name(preset_utf8);
    std::array<double, 3> direction{{0, 0, 1}};
    if (name == "back") direction = {{0, 0, -1}};
    else if (name == "left") direction = {{-1, 0, 0}};
    else if (name == "right") direction = {{1, 0, 0}};
    else if (name == "top") direction = {{0, 1, 0}};
    else if (name == "bottom") direction = {{0, -1, 0}};
    else if (name != "front") return GX3D_E_INVALID;
    auto* camera = view->renderer->GetActiveCamera();
    const double* target = camera->GetFocalPoint();
    const double distance = std::max(1.0, camera->GetDistance());
    camera->SetPosition(target[0] + distance * direction[0], target[1] + distance * direction[1],
                        target[2] + distance * direction[2]);
    camera->SetViewUp(0, name == "top" || name == "bottom" ? 0 : 1,
                      name == "top" ? -1 : name == "bottom" ? 1 : 0);
    view->renderer->ResetCameraClippingRange();
    if (view->shown) view->window->Render();
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_view_set_display_mode(gx3d_view* view, gx3d_display_mode mode) {
    if (!view || mode < GX3D_SURFACE || mode > GX3D_SURFACE_EDGES) return GX3D_E_INVALID;
    auto* property = view->actor->GetProperty();
    if (mode == GX3D_WIREFRAME) property->SetRepresentationToWireframe();
    else property->SetRepresentationToSurface();
    property->SetEdgeVisibility(mode == GX3D_SURFACE_EDGES);
    if (view->shown) view->window->Render();
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_view_set_background(gx3d_view* view, float r, float g, float b) {
    if (!view || !std::isfinite(r) || !std::isfinite(g) || !std::isfinite(b) ||
        r < 0 || r > 1 || g < 0 || g > 1 || b < 0 || b > 1) return GX3D_E_INVALID;
    view->renderer->SetBackground(r, g, b);
    if (view->shown) view->window->Render();
    return GX3D_OK;
}
extern "C" gx3d_result gx3d_view_pick(gx3d_view* view, int x_px, int y_px, gx3d_pick_result* out_pick) {
    if (!view || !out_pick || out_pick->struct_size < sizeof(gx3d_pick_result)) return GX3D_E_INVALID;
    out_pick->hit = view->picker->Pick(x_px, y_px, 0, view->renderer) ? 1 : 0;
    out_pick->object_id = 0;
    out_pick->cell_id = out_pick->hit ? static_cast<uint64_t>(view->picker->GetCellId()) : 0;
    out_pick->point_id = out_pick->hit ? static_cast<uint64_t>(view->picker->GetPointId()) : 0;
    const auto* position = view->picker->GetPickPosition();
    std::copy(position, position + 3, out_pick->world);
    return GX3D_OK;
}
