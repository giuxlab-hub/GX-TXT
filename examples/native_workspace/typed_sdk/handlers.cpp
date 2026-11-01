// SPDX-License-Identifier: GPL-3.0-or-later
// GUI properties and this typed model are persisted by the Workspace owner.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    auto workspace = host.workspace();
    if (event.kind == gx::EventKind::open) {
        auto restored = workspace.state();
        if (restored.kind == gx::WorkspaceValue::Kind::object) {
            auto found = restored.fields.find("accepted_notes");
            if (found != restored.fields.end()) state.counter = static_cast<unsigned>(found->second.integer);
        }
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    ++state.counter;
    workspace.set_state(gx::workspace_object({
        {"accepted_notes", gx::workspace_integer(state.counter)},
        {"meaning", gx::workspace_text("Literal text: 001 {a b}")}
    }));
    workspace.set_property("reviewed", gx::workspace_flag(true));
    workspace.set_property("scale", gx::workspace_number(2.5));
    auto status = workspace.status();
    if (status.id.empty()) workspace.save_as("Typed notes");
    else workspace.save();
    host.text(2, "Note accepted through the typed Workspace facade");
}
