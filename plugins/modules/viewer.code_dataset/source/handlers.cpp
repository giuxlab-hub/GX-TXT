// SPDX-License-Identifier: GPL-3.0-or-later
// CORE owns canonical bytes, language metadata, Find and readonly Source Surface.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open ||
        (event.kind == gx::EventKind::changed && event.component == 1) ||
        (event.kind == gx::EventKind::invoke && event.component == 2)) {
        host.document_bind(3, 1);
    }
}
