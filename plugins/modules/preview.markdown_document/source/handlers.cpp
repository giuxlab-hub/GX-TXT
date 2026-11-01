// SPDX-License-Identifier: GPL-3.0-or-later
#include <string>

// The standard Preview host supplies the exact selected declared component ID.
// Text, resources, associations and selection remain in the shared CORE owner.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state;
    if (event.kind != gx::EventKind::open) return;
    const std::string selected = host.data();
    struct Pane { const char* id; unsigned component; };
    static const Pane panes[] = {
        {"document_1", 1}, {"document_2", 2},
        {"document_3", 3}, {"document_4", 4}
    };
    for (const Pane& pane : panes) {
        if (selected == pane.id) {
            host.document_command(pane.component, "render");
            return;
        }
    }
}
