// SPDX-License-Identifier: GPL-3.0-or-later
// A genuine finite SDK client: public CORE owns all data and scientific actions.
#include "ir_viewer_client.hpp"
#include <stdexcept>
#include <string>
#include <string_view>
namespace ir_viewer {
namespace {
struct Route {const char* action;const char* operation;};
constexpr Route commands[] = {
    {"comparison_discover","discover"},
    {"comparison_add_dataset","add_dataset"},
    {"comparison_add_library","add_library"},
    {"comparison_add_browser","add_browser"},
    {"comparison_add_opened","add_opened"},
    {"comparison_remove","remove"},
    {"comparison_up","up"},
    {"comparison_down","down"},
    {"comparison_prepare","prepare"},
    {"comparison_clear","clear"},
    {"comparison_inspect","inspect"},
    {"comparison_plot_fit","plot_fit"},
    {"comparison_plot_zoom_in","plot_zoom_in"},
    {"comparison_plot_zoom_out","plot_zoom_out"},
    {"comparison_plot_cursor","plot_cursor"},
    {"comparison_plot_clear_cursor","plot_clear_cursor"},
    {"comparison_plot_reverse_x","plot_reverse_x"},
    {"comparison_plot_properties","plot_properties"},
    {"comparison_plot_legend","plot_legend"},
    {"comparison_plot_style","plot_style"},
    {"comparison_plot_copy","plot_copy"},
    {"comparison_plot_export","plot_export"},
    {"comparison_plot_save_variant","plot_save_variant"},
    {"comparison_plot_load_variant","plot_load_variant"}
};
constexpr Route analysis_commands[] = {
    {"analysis_dd1b5896_discover","discover"},
    {"analysis_dd1b5896_submit","submit"},
    {"analysis_dd1b5896_status","status"},
    {"analysis_dd1b5896_cancel","cancel"},
    {"analysis_dd1b5896_candidates","candidates"},
    {"analysis_dd1b5896_add_candidate","add_candidate"}
};
const gx::WorkspaceValue& field(const gx::WorkspaceValue& value,const char* name,gx::WorkspaceValue::Kind type) {
    if(value.kind!=gx::WorkspaceValue::Kind::object)throw std::runtime_error("Public Comparison receipt is not an object");
    const auto found=value.fields.find(name);
    if(found==value.fields.end()||found->second.kind!=type)throw std::runtime_error(std::string("Public Comparison receipt lacks ")+name);
    return found->second;
}
void check_receipt(const gx::WorkspaceValue* value) {
    // No receipt is present before the user's first command. A receipt, when
    // present, belongs to the current immutable event and is never authority.
    if(!value)return;
    using Kind=gx::WorkspaceValue::Kind;
    const auto& status=field(*value,"status",Kind::text).text;
    field(*value,"operation",Kind::text);field(*value,"view",Kind::object);
    if(field(*value,"sequence",Kind::integer).integer<0||field(*value,"event_generation",Kind::integer).integer<0)throw std::runtime_error("Malformed Comparison receipt lifetime");
    if(field(*value,"error",Kind::text).text.size()>8192)throw std::runtime_error("Comparison diagnostic exceeds its public bound");
    if(status!="completed"&&status!="failed"&&status!="cancelled")throw std::runtime_error("Unsupported Comparison receipt status");
    if(value->fields.find("result")==value->fields.end())throw std::runtime_error("Comparison receipt lacks its result field");
}
}
void route(gx::Host& host,const gx::Event& event,const Components& components) {
    if(!components.comparison_form||!components.status)throw std::runtime_error("The authored IR component identities are unavailable");
    check_receipt(host.comparison_result());
    check_receipt(host.analysis_result());
    // Opening/restoring does not perform discovery, source selection, Analysis,
    // normalization, identification or publication on the user's behalf.
    if(event.kind!=gx::EventKind::invoke)return;
    const char* raw=host.data();
    if(!raw)throw std::runtime_error("The declared native action identity is unavailable");
    const std::string_view action(raw);
    for(const auto& command:commands) {
        if(action==command.action){host.comparison_command(components.comparison_form,command.operation);return;}
    }
    for(const auto& command:analysis_commands) {
        if(action==command.action){
            if(!components.analysis_form)throw std::runtime_error("The Analysis profile is not authored in this design");
            host.analysis_command(components.analysis_form,command.operation);return;
        }
    }
    // Shared Plot presentation, Browser, Workspace/History/Help keep their
    // existing declared owners. Public CORE source seams are not
    // replaced by a private parser, renderer, math routine or Tcl call here.
}
}
