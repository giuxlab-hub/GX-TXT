// SPDX-License-Identifier: GPL-3.0-or-later
// Genuine Builder UML Preview: exact pane admission through public SDK41.
// CORE owns canonical source, semantic parsing/layout and Native2D presentation.
#include <string_view>
namespace uml_preview {
struct Pane { const char* id; unsigned component; };
constexpr Pane panes[] = {{"document_1", 1}, {"document_2", 2}, {"document_3", 3}};
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state;
    if (event.kind != gx::EventKind::open) return;
    const std::string_view actual_pane(host.data());
    for (const auto& pane : uml_preview::panes) {
        if (actual_pane == pane.id) {
            host.document_command(pane.component, "render");
            return;
        }
    }
}
