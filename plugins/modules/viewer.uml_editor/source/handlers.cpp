// SPDX-License-Identifier: GPL-3.0-or-later
// Genuine Builder-authored UML Editor. CORE owns exact source, semantic model,
// Native2D rendering, Document transactions and typed Workspace/History.
#include <string_view>
namespace uml_editor {
constexpr unsigned document = 1;
struct PrimaryAction { const char* id; const char* operation; };
constexpr PrimaryAction actions[] = {
    {"new", "new"},
    {"new_sequence", "new_sequence"},
    {"open", "open"},
    {"save_existing", "save_existing"},
    {"publish_new", "publish_new"},
    {"export_source", "export_source"},
    {"export_png", "export_png"},
    {"export_svg", "export_svg"},
    {"text_undo", "undo"},
    {"text_redo", "redo"},
    {"cut", "cut"},
    {"copy", "copy"},
    {"paste", "paste"},
    {"select_all", "select_all"},
    {"find", "find"},
    {"replace", "replace"},
    {"add_class", "add_class"},
    {"add_interface", "add_interface"},
    {"add_member", "add_member"},
    {"add_relation", "add_relation"},
    {"add_actor", "add_actor"},
    {"add_participant", "add_participant"},
    {"add_message", "add_message"},
    {"add_frame", "add_frame"},
    {"edit_selected", "edit_selected"},
    {"delete_selected", "delete_selected"},
    {"message_up", "message_up"},
    {"message_down", "message_down"},
    {"auto_layout", "auto_layout"},
    {"view_source", "view_source"},
    {"view_diagram", "view_diagram"},
    {"view_outline", "view_outline"},
    {"view_properties", "view_properties"},
    {"view_diagnostics", "view_diagnostics"},
    {"fit", "fit"},
    {"zoom_in", "zoom_in"},
    {"zoom_out", "zoom_out"},
    {"zoom_reset", "zoom_reset"},
    {"render", "render"},
    {"reset_layout", "reset_layout"},
};
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state;
    if (event.kind == gx::EventKind::open) {
        host.document_command(uml_editor::document, "render");
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    const std::string_view declared_action(host.data());
    for (const auto& action : uml_editor::actions) {
        if (declared_action == action.id) {
            host.document_command(uml_editor::document, action.operation);
            return;
        }
    }
}
