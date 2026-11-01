// SPDX-License-Identifier: GPL-3.0-or-later
// Builder-authored Markdown Documents client. CORE owns every document byte,
// renderer, edit transaction, managed image, text selection and saved state.
#include <string>
namespace markdown_documents {
constexpr unsigned document = 8;
struct Command { const char* action; const char* operation; };
constexpr Command commands[] = {
    {"text_undo", "undo"}, {"text_redo", "redo"},
    {"new", "new"},
    {"open", "open"},
    {"save_existing", "save_existing"},
    {"publish_new", "publish_new"},
    {"cut", "cut"},
    {"copy", "copy"},
    {"paste", "paste"},
    {"select_all", "select_all"},
    {"find", "find"},
    {"replace", "replace"},
    {"heading1", "heading1"},
    {"heading2", "heading2"},
    {"heading3", "heading3"},
    {"bold", "bold"},
    {"italic", "italic"},
    {"inline_code", "inline_code"},
    {"code_block", "code_block"},
    {"bullet_list", "bullet_list"},
    {"numbered_list", "numbered_list"},
    {"table", "table"},
    {"link", "link"},
    {"quote", "quote"},
    {"rule", "rule"},
    {"color", "color"},
    {"insert_image", "insert_image"},
    {"view_source", "view_source"},
    {"view_rendered", "view_rendered"},
    {"view_outline", "view_outline"},
    {"view_properties", "view_properties"},
    {"view_resources", "view_resources"},
    {"reset_layout", "reset_layout"},
    {"render", "render"},
    {"zoom_in", "zoom_in"},
    {"zoom_out", "zoom_out"},
    {"zoom_reset", "zoom_reset"}
};

}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state;
    using namespace markdown_documents;
    if (event.kind == gx::EventKind::open) {
        host.document_command(document, "render");
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    const std::string action = host.data();
    for (const Command& command : commands) {
        if (action == command.action) {
            host.document_command(document, command.operation);
            return;
        }
    }
}
