// SPDX-License-Identifier: GPL-3.0-or-later
// Automatically supplied restricted author surface. No standard headers are exposed.
namespace gx {
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
    void numeric_discover(unsigned form) const;
    void numeric_evaluate(unsigned form) const;
    void numeric_statistics(unsigned form) const;
    void numeric_compare(unsigned form) const;
    void numeric_publish(unsigned form, unsigned dataset_selector) const;
    void demo(unsigned component, unsigned fixture) const;
private:
    void* context_;
    double (*dispatch_)(void*, unsigned, unsigned, double, double, const char*);
    friend struct HostAccess;
};
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event);
