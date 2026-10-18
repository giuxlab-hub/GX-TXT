// SPDX-License-Identifier: GPL-3.0-or-later
// Restricted SDK v1 is supplied automatically; do not add includes.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.demo(3, 0);
        host.text(2, "Synthetic response; C++ handler uses the public Numeric API.");
    }
    if (event.kind == gx::EventKind::invoke) {
        state.counter += 1;
        state.values[0] = host.numeric_add(event.value, 273.15);
        host.number(1, state.values[0]);
        host.text(2, "Synthetic temperature in kelvin; display only.");
    }
}
