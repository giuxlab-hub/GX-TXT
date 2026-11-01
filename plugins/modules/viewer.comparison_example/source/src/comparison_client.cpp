// SPDX-License-Identifier: GPL-3.0-or-later
// Pure finite client routing. No mathematical/model/persistence implementation.
#include "comparison_client.hpp"
#include <stdexcept>
#include <string>
#include <string_view>

namespace comparison_client {
namespace {
using Value = gx::WorkspaceValue;
struct Route { const char* action; const char* operation; };
constexpr Route routes[] = {
    {"comparison_discover", "discover"},
    {"comparison_add_dataset", "add_dataset"},
    {"comparison_add_library", "add_library"},
    {"comparison_remove", "remove"},
    {"comparison_up", "up"},
    {"comparison_down", "down"},
    {"comparison_prepare", "prepare"},
    {"comparison_clear", "clear"},
    {"comparison_inspect", "inspect"},
    {"comparison_plot_fit", "plot_fit"},
    {"comparison_plot_zoom_in", "plot_zoom_in"},
    {"comparison_plot_zoom_out", "plot_zoom_out"},
    {"comparison_plot_cursor", "plot_cursor"},
    {"comparison_plot_clear_cursor", "plot_clear_cursor"},
    {"comparison_plot_reverse_x", "plot_reverse_x"},
    {"comparison_plot_properties", "plot_properties"},
    {"comparison_plot_legend", "plot_legend"},
    {"comparison_plot_style", "plot_style"},
    {"comparison_plot_copy", "plot_copy"},
    {"comparison_plot_export", "plot_export"},
    {"comparison_plot_save_variant", "plot_save_variant"},
    {"comparison_plot_load_variant", "plot_load_variant"}
};
const Value& field(const Value& object, const char* name, Value::Kind kind) {
    if (object.kind != Value::Kind::object)
        throw std::runtime_error("Comparison receipt is not a typed object");
    const auto found = object.fields.find(name);
    if (found == object.fields.end() || found->second.kind != kind)
        throw std::runtime_error(std::string("Comparison receipt field is unavailable: ") + name);
    return found->second;
}
bool finite_operation(const std::string& value) {
    for (const auto& route : routes) if (value == route.operation) return true;
    return false;
}
void validate_receipt(const Value* value) {
    if (!value) throw std::runtime_error("The public Comparison receipt is unavailable");
    const auto& operation = field(*value, "operation", Value::Kind::text).text;
    const auto& status = field(*value, "status", Value::Kind::text).text;
    const auto& error = field(*value, "error", Value::Kind::text).text;
    const auto sequence = field(*value, "sequence", Value::Kind::integer).integer;
    const auto generation = field(*value, "event_generation", Value::Kind::integer).integer;
    field(*value, "view", Value::Kind::object);
    const auto result = value->fields.find("result");
    if (result == value->fields.end() || sequence < 0 || generation < 0 || error.size() > 8192)
        throw std::runtime_error("Comparison receipt identity or bound is malformed");
    if (operation != "snapshot" && !finite_operation(operation))
        throw std::runtime_error("Comparison receipt names an unsupported operation");
    if (status == "failed" || status == "cancelled") {
        if (result->second.kind != Value::Kind::null)
            throw std::runtime_error("Failed Comparison receipt retained a successful result");
        return; // The CORE status already carries the authoritative refusal.
    }
    if (status != "completed") throw std::runtime_error("Comparison receipt status is malformed");
    if (operation == "snapshot") {
        if (sequence != 0 || result->second.kind != Value::Kind::null)
            throw std::runtime_error("Initial Comparison snapshot is malformed");
        return;
    }
    if (sequence == 0 || result->second.kind != Value::Kind::object)
        throw std::runtime_error("Comparison completion lacks its fresh result");
    // CORE supplies only a bounded summary. Exact samples/provenance stay in
    // its admitted Plot/Numeric/Document owners, not a second C++ model.
    const auto count = result->second.fields.find("source_count");
    if (count != result->second.fields.end() &&
        (count->second.kind != Value::Kind::integer || count->second.integer < 0 || count->second.integer > 8))
        throw std::runtime_error("Comparison completion has an invalid source count");
    const auto modified = result->second.fields.find("canonical_values_modified");
    if (modified != result->second.fields.end() &&
        (modified->second.kind != Value::Kind::boolean || modified->second.integer != 0))
        throw std::runtime_error("Comparison completion is not readonly scientific consultation");
}
}
void route(gx::Host& host, const gx::Event& event, const Components& components) {
    if (!components.form || !components.status)
        throw std::runtime_error("Comparison requires actual declared Builder components");
    validate_receipt(host.comparison_result());
    if (event.kind == gx::EventKind::open) {
        host.comparison_command(components.form, "discover");
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    const char* data = host.data();
    if (!data) throw std::runtime_error("Comparison action identity is unavailable");
    const std::string_view action(data);
    for (const auto& route : routes) {
        if (action != route.action) continue;
        host.comparison_command(components.form, route.operation);
        return;
    }
    // Other ordinary Workspace/History/Help commands remain their real owners.
}
}
