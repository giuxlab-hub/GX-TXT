// SPDX-License-Identifier: GPL-3.0-or-later
// Canonical Dataset and rendering remain public CORE owners.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.text(1, "Select a canonical trace. Open Baseline correction for an explicit new Dataset; saved study is unavailable.");
    } else if (event.kind == gx::EventKind::invoke && event.component == 9) {
        host.plot_discover(3); state.counter += 1;
    } else if (event.kind == gx::EventKind::invoke && event.component == 10) {
        host.plot_bind(15, 3); state.counter += 1;
    }
}
