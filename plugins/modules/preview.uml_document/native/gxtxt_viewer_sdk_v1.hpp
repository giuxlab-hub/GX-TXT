// SPDX-License-Identifier: GPL-3.0-or-later
// Automatically supplied public integration surface. Reviewed C/C++ headers may be included.
#include <cstdint>
#include <map>
#include <string>
#include <vector>
namespace gx {
struct WorkspaceValue {
    enum class Kind { null, text, boolean, integer, real, object, array, resource };
    Kind kind = Kind::null;
    std::string text;
    std::int64_t integer = 0;
    double real = 0;
    std::map<std::string, WorkspaceValue> fields;
    std::vector<WorkspaceValue> elements;
};
WorkspaceValue workspace_text(std::string);
WorkspaceValue workspace_integer(std::int64_t);
WorkspaceValue workspace_number(double);
WorkspaceValue workspace_flag(bool);
WorkspaceValue workspace_object(std::map<std::string, WorkspaceValue> = {});
WorkspaceValue workspace_array(std::vector<WorkspaceValue> = {});
WorkspaceValue workspace_resource(std::map<std::string, WorkspaceValue>);
struct WorkspaceStatus {
    std::string id, generation, error;
    std::uint64_t revision = 0, durable_revision = 0;
    bool dirty = false, pending = false, failed = false;
};
struct WorkspaceEntry {std::string id, name, provider;std::uint64_t revision = 0;};
// Optional authored model hooks. Missing hooks use the safe facade defaults.
// Restoration must be atomic or compensatable with a previously captured value.
WorkspaceValue on_workspace_capture() __attribute__((weak));
void on_workspace_validate(const WorkspaceValue&) __attribute__((weak));
void on_workspace_restore(const WorkspaceValue&) __attribute__((weak));
void on_workspace_committed(const WorkspaceStatus&) __attribute__((weak));
class Workspace;
enum class EventKind { open, invoke, changed, selection, close, test };
struct Event { EventKind kind; unsigned component; double value; };
struct State { double values[16]; unsigned counter; };
class Host {
public:
    void text(unsigned component, const char* value) const;
    void number(unsigned component, double value) const;
    void flag(unsigned component, bool value) const;
    double numeric_add(double left, double right) const;
    double numeric_sqrt(double value) const;
    double numeric_exp(double value) const;
    void diagram_open(unsigned component) const;
    void diagram_tool(unsigned component, const char* tool) const;
    void diagram_command(unsigned component, const char* command) const;
    void scientific_discover(unsigned form) const;
    void scientific_prepare(unsigned diagram, unsigned form) const;
    void scientific_submit(unsigned form) const;
    void scientific_status(unsigned form) const;
    void scientific_cancel(unsigned form) const;
    void scientific_reconnect(unsigned form) const;
    void scientific_log(unsigned form) const;
    void scientific_import(unsigned form, unsigned dataset_selector) const;
    void plot_discover(unsigned form) const;
    void plot_bind(unsigned plot, unsigned form) const;
    void document_bind(unsigned document, unsigned dataset_selector) const;
    void document_command(unsigned document, const char* operation) const;
    void raster_bind(unsigned viewport, unsigned dataset_selector) const;
    void raster_tool(unsigned viewport, const char* tool) const;
    void raster_command(unsigned viewport, const char* command) const;
    void tex_command(unsigned form, const char* operation) const;
    void em_command(unsigned form, const char* operation) const;
    void workbench_command(unsigned form, const char* operation) const;
    // Immutable declared GUI values and typed CORE data for this event only.
    const char* input(unsigned component) const;
    const char* data() const;
    void cad_command(unsigned component, const char* action) const;
    void diagnostics_command(unsigned form, const char* operation, const char* request = "{}") const;
    void text_runs(unsigned component, const char* runs_json) const;
    void table(unsigned component, const char* rows_json) const;
    void catalog_refresh(unsigned form) const;
    void catalog_inspect(unsigned form) const;
    void catalog_action(unsigned form, const char* action) const;
    void numeric_discover(unsigned form) const;
    void numeric_evaluate(unsigned form) const;
    void numeric_statistics(unsigned form) const;
    void numeric_compare(unsigned form) const;
    void numeric_publish(unsigned form, unsigned dataset_selector) const;
    // Typed producer requests; CORE applies them after the native event.
    // Full review strings remain opaque. Read the next event's transient receipt.
    void dataset_group_review(const WorkspaceValue& dataset_ids) const;
    void dataset_group_create(const WorkspaceValue& definition, const WorkspaceValue& review) const;
    void dataset_publish_batch(const WorkspaceValue& request) const;
    WorkspaceValue dataset_producer_result() const;
    void demo(unsigned component, unsigned fixture) const;
    Workspace workspace() const;
private:
    void* context_;
    double (*dispatch_)(void*, unsigned, unsigned, double, double, const char*);
    friend struct HostAccess;
    friend class Workspace;
};
// This is an owning-thread Viewer facade. Reads use the immutable event
// snapshot; mutations are validated/applied by CORE after this native event.
class Workspace {
public:
    WorkspaceValue state() const;
    WorkspaceValue property(const std::string& name) const;
    WorkspaceStatus status() const;
    std::vector<WorkspaceEntry> query(const std::string& prefix = "") const;
    void set_state(const WorkspaceValue& value) const;
    void set_property(const std::string& name, const WorkspaceValue& value) const;
    void save(bool asynchronous = false) const;
    void save_as(const std::string& name) const;
    void rename(const std::string& name) const;
    void open(const std::string& id) const;
    void close() const;
private:
    const Host* host_;
    explicit Workspace(const Host* host):host_(host){}
    void send(const char*, const WorkspaceValue&) const;
    friend class Host;
};
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event);
