// SPDX-License-Identifier: GPL-3.0-or-later
// P034 non-IR genuine client; finite public owner intents only.
// The normal Development compiler supplies the genuine public gx SDK prefix.
#include "comparison_client.hpp"
#include <exception>

namespace {
// Ordinals verified from the actual native-Builder saved design readback.
constexpr comparison_client::Components components{1, 19};
}

void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state; // Presentation never dirties a Workspace with synthetic counters.
    // Let the trusted SDK C entry report errors without a second GUI call.
    comparison_client::route(host, event, components);
}
