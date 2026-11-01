// SPDX-License-Identifier: GPL-3.0-or-later
// Ordinary Viewer logic: shared CORE owns exact geometry and Document History.
#include <string>
namespace {
constexpr unsigned SKETCH=1, STATUS=3, CUSTOM=5;
class CadViewer final {
public:
    void event(gx::Host& host, gx::State& state, const gx::Event& event) const {
        if (event.kind==gx::EventKind::open) {
            host.text(STATUS,"TEST CAD ready: shared exact sketch, mm, XY plane.");
            return;
        }
        if (event.kind!=gx::EventKind::invoke) return;
        if (event.component==CUSTOM) {
            ++state.counter;
            const std::string message="TEST Viewer action #"+std::to_string(state.counter)+"; shared CAD remains available.";
            host.text(STATUS,message.c_str());
            return;
        }
        switch (event.component) {

        default: return;
        }
    }
};
}
void on_event(gx::Host& host,gx::State& state,const gx::Event& event) {
    CadViewer{}.event(host,state,event);
}
