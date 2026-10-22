// SPDX-License-Identifier: GPL-3.0-or-later
// Scientific Library Workspace: UI intents only. CORE owns every registry ID,
// provider request, capability decision, administrative dialog and Viewer route.
namespace library_workspace {
constexpr unsigned form = 1;
constexpr unsigned page = 31;
struct Command { unsigned component; const char* action; };
constexpr Command commands[] = {
    {18, "open"}, {19, "entry_open"}, {20, "verify"},
    {22, "install"}, {23, "update"}, {24, "remove"},
    {25, "register_external"}, {26, "register_remote"},
    {27, "unregister"}, {33, "extra_action"}
};
bool dispatch(gx::Host& host, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.catalog_refresh(form);
        return true;
    }
    if (event.kind != gx::EventKind::invoke &&
        event.kind != gx::EventKind::changed) return false;
    if (event.component == 2 || event.component == 4) {
        host.number(page, 1);
        host.catalog_refresh(form);
        return true;
    }
    if (event.component == 17 || event.component == page) {
        host.catalog_refresh(form);
        return true;
    }
    if (event.component == 5 || event.component == 13 ||
        event.component == 32) {
        host.catalog_inspect(form);
        return true;
    }
    for (const Command& command : commands) {
        if (event.component == command.component) {
            host.catalog_action(form, command.action);
            return true;
        }
    }
    return false;
}
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    // Counts emitted UI intents only; never claims an operation completed.
    if (library_workspace::dispatch(host, event)) ++state.counter;
}
