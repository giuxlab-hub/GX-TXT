// SPDX-License-Identifier: GPL-3.0-or-later
// Normal Development supplies the admitted SDK; source includes no fake header.
#include "ir_viewer_client.hpp"
#include <exception>
namespace {constexpr ir_viewer::Components components{1,17,31};}
void on_event(gx::Host& host,gx::State& state,const gx::Event& event) {
    (void)state;
    try {ir_viewer::route(host,event,components);}
    catch(const std::exception& error) {host.text(components.status,error.what());}
}
