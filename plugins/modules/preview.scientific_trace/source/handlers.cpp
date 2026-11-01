// SPDX-License-Identifier: GPL-3.0-or-later
// Genuine spectrum/trace design form=source/1, Plot=waveform/5, status=6.
#include "scientific_preview_routing.hpp"
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state;
    try {
        if (event.kind == gx::EventKind::open) {
            host.plot_discover(1);host.plot_bind(5, 1);
            scientific_preview::initialize(host, 1);return;
        }
        if (event.kind == gx::EventKind::changed && (event.component == 3 || event.component == 4)) {host.plot_bind(5, 1);return;}
        scientific_preview::route(host, 1, event);
    } catch (const std::exception& error) {host.text(6, error.what());}
}
