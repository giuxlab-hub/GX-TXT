// SPDX-License-Identifier: GPL-3.0-or-later
// Author-owned UI dispatch only. Original CORE owners retain scientific state.
// Original ordinals1..78 are preserved. All EM actions target declared form10.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.em_command(10, "refresh");
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    switch (event.component) {
    case 45: host.document_bind(44, 32); break;
    case 55: host.em_command(10, "refresh"); break;
    case 56: host.em_command(10, "new_electric"); break;
    case 57: host.em_command(10, "new_magnetic"); break;
    case 58: host.em_command(10, "validate"); break;
    case 59: host.em_command(10, "open"); break;
    case 60: host.em_command(10, "save"); break;
    case 61: host.em_command(10, "duplicate"); break;
    case 62: host.em_command(10, "workspaces"); break;
    case 63: host.em_command(10, "rename"); break;
    case 64: host.em_command(10, "run"); break;
    case 65: host.em_command(10, "jobs"); break;
    case 66: host.em_command(10, "reconnect"); break;
    case 67: host.em_command(10, "status"); break;
    case 68: host.em_command(10, "cancel"); break;
    case 69: host.em_command(10, "log"); break;
    case 70: host.em_command(10, "results"); break;
    case 71: host.em_command(10, "publish"); break;
    case 72: host.em_command(10, "field"); break;
    case 78: host.em_command(10, "field_3d"); break;
    case 82: host.em_command(10, "runtime"); break;
    case 83: host.em_command(10, "profile"); break;
    case 84: host.em_command(10, "publish_charts"); break;
    case 85: host.em_command(10, "export_field"); break;
    default: break;
    }
}
