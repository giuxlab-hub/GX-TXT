// SPDX-License-Identifier: GPL-3.0-or-later
// Ordinary Viewer logic: shared CORE owns exact geometry and Document History.
#include <string>
namespace {
constexpr unsigned SKETCH=1, STATUS=3, CUSTOM=56;
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
        case 6: host.cad_command(SKETCH, "select"); return;
        case 7: host.cad_command(SKETCH, "rectangle_selection"); return;
        case 8: host.cad_command(SKETCH, "pan"); return;
        case 9: host.cad_command(SKETCH, "fit"); return;
        case 12: host.cad_command(SKETCH, "point"); return;
        case 13: host.cad_command(SKETCH, "line"); return;
        case 14: host.cad_command(SKETCH, "construction_line"); return;
        case 15: host.cad_command(SKETCH, "path"); return;
        case 16: host.cad_command(SKETCH, "polyline"); return;
        case 17: host.cad_command(SKETCH, "spline"); return;
        case 18: host.cad_command(SKETCH, "rectangle"); return;
        case 19: host.cad_command(SKETCH, "circle"); return;
        case 20: host.cad_command(SKETCH, "arc"); return;
        case 21: host.cad_command(SKETCH, "ellipse"); return;
        case 22: host.cad_command(SKETCH, "quadratic_bezier"); return;
        case 23: host.cad_command(SKETCH, "cubic_bezier"); return;
        case 26: host.cad_command(SKETCH, "translate"); return;
        case 27: host.cad_command(SKETCH, "rotate"); return;
        case 28: host.cad_command(SKETCH, "mirror"); return;
        case 29: host.cad_command(SKETCH, "join_points"); return;
        case 30: host.cad_command(SKETCH, "join_path"); return;
        case 31: host.cad_command(SKETCH, "compound"); return;
        case 32: host.cad_command(SKETCH, "separate"); return;
        case 33: host.cad_command(SKETCH, "split_path"); return;
        case 34: host.cad_command(SKETCH, "split_composition"); return;
        case 37: host.cad_command(SKETCH, "dimension"); return;
        case 38: host.cad_command(SKETCH, "horizontal"); return;
        case 39: host.cad_command(SKETCH, "vertical"); return;
        case 40: host.cad_command(SKETCH, "coincident"); return;
        case 41: host.cad_command(SKETCH, "parallel"); return;
        case 42: host.cad_command(SKETCH, "perpendicular"); return;
        case 43: host.cad_command(SKETCH, "tangent"); return;
        case 44: host.cad_command(SKETCH, "equal_length"); return;
        case 45: host.cad_command(SKETCH, "equal_radius"); return;
        case 46: host.cad_command(SKETCH, "fixed"); return;
        case 49: host.cad_command(SKETCH, "finish"); return;
        case 50: host.cad_command(SKETCH, "cancel"); return;
        case 51: host.cad_command(SKETCH, "undo"); return;
        case 52: host.cad_command(SKETCH, "redo"); return;
        case 53: host.cad_command(SKETCH, "save"); return;
        default: return;
        }
    }
};
}
void on_event(gx::Host& host,gx::State& state,const gx::Event& event) {
    CadViewer{}.event(host,state,event);
}
