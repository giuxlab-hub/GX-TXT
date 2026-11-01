// SPDX-License-Identifier: GPL-3.0-or-later
// Actual genuine frame02 IDs: form=section_1/15, frame=panel_6/8, status=3.
#include "scientific_preview_routing.hpp"
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state;
    try {
        if (event.kind == gx::EventKind::open) {
            scientific_preview::initialize(host, 15);host.scientific_frame_bind(8, 15);return;
        }
        if (event.kind == gx::EventKind::changed && (event.component == 1 || event.component == 2 || event.component == 4 || event.component == 5)) {host.scientific_frame_bind(8, 15);return;}
        scientific_preview::route(host, 15, event);
    } catch (const std::exception& error) {host.text(3, error.what());}
}
