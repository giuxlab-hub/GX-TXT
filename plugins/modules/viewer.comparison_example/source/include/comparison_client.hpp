// SPDX-License-Identifier: GPL-3.0-or-later
// Registered genuine public-client declaration; no scientific model is owned here.
#pragma once
namespace gx { class Host; struct Event; }
namespace comparison_client {
struct Components { unsigned form; unsigned status; };
void route(gx::Host&, const gx::Event&, const Components&);
}
