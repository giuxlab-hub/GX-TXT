// SPDX-License-Identifier: GPL-3.0-or-later
#include <stdexcept>
namespace {
struct NoteModel {std::string label = "001 {a b}";std::int64_t count = 0;} model;
std::uint64_t last_committed_revision = 0;
}
gx::WorkspaceValue gx::on_workspace_capture() {
    return gx::workspace_object({{"label",gx::workspace_text(model.label)},
                                 {"count",gx::workspace_integer(model.count)}});
}
void gx::on_workspace_validate(const gx::WorkspaceValue& state) {
    if (state.kind != gx::WorkspaceValue::Kind::object ||
        state.fields.at("label").kind != gx::WorkspaceValue::Kind::text ||
        state.fields.at("count").kind != gx::WorkspaceValue::Kind::integer ||
        state.fields.at("count").integer < 0) throw std::runtime_error("Invalid note model");
}
void gx::on_workspace_restore(const gx::WorkspaceValue& state) {
    gx::on_workspace_validate(state);
    // Prepare first, then adopt, so a rejected restore retains the old model.
    NoteModel next{state.fields.at("label").text,state.fields.at("count").integer};
    model = std::move(next);
}
void gx::on_workspace_committed(const gx::WorkspaceStatus& status) {
    if (status.pending || status.durable_revision < status.revision)
        throw std::runtime_error("Expected a durable Workspace acknowledgement");
    last_committed_revision = status.revision;
}
void on_event(gx::Host& host, gx::State&, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {host.text(2,model.label.c_str());return;}
    if (event.kind != gx::EventKind::invoke) return;
    ++model.count;
    auto workspace = host.workspace();
    if (workspace.status().id.empty()) workspace.save_as("Hooked notes");
    else workspace.save();
    host.text(2,"The captured note is submitted to native Workspace storage");
}
