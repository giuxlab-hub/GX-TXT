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
    void demo(unsigned component, unsigned fixture) const;
private:
    void* context_;
    double (*dispatch_)(void*, unsigned, unsigned, double, double, const char*);
    friend struct HostAccess;
};
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event);
