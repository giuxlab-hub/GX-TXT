// SPDX-License-Identifier: GPL-3.0-or-later
// P033 authored client staging. Import through normal ProjectFiles before build.
// CORE alone reads canonical arrays and renders the three managed role tables.
#include <algorithm>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace scientific_preview {
using Value = gx::WorkspaceValue;
using Index = std::int64_t;
const Value& field(const Value& value, const char* key) {
    if (value.kind != Value::Kind::object) throw std::runtime_error("Scientific owner object is unavailable");
    const auto found = value.fields.find(key);
    if (found == value.fields.end()) throw std::runtime_error("Scientific owner field is unavailable");
    return found->second;
}
std::string text(const Value& object, const char* key) {
    const auto& value = field(object, key);
    if (value.kind != Value::Kind::text) throw std::runtime_error("Scientific owner text is malformed");
    return value.text;
}
Index integer(const Value& object, const char* key) {
    const auto& value = field(object, key);
    if (value.kind != Value::Kind::integer || value.integer < 0) throw std::runtime_error("Scientific owner integer is malformed");
    return value.integer;
}
const std::vector<Value>& array(const Value& object, const char* key) {
    const auto& value = field(object, key);
    if (value.kind != Value::Kind::array) throw std::runtime_error("Scientific owner array is malformed");
    return value.elements;
}
std::vector<Index> indices(const Value& object, const char* key) {
    std::vector<Index> result;
    for (const auto& value : array(object, key)) {
        if (value.kind != Value::Kind::integer || value.integer < 0) throw std::runtime_error("Scientific shape/index is malformed");
        result.push_back(value.integer);
    }
    if (result.empty() || result.size() > 64) throw std::runtime_error("Scientific rank is outside its bounded read contract");
    return result;
}
const Value& view(gx::Host& host) {
    const auto* receipt = host.scientific_preview_result();
    if (!receipt) throw std::runtime_error("The admitted scientific Preview owner is unavailable");
    const auto& result = field(*receipt, "view");
    // Identity is opaque text from CORE. Never parse revision or use it as grant.
    const auto& source = field(result, "source");
    (void)text(source, "dataset_id");(void)text(source, "revision");
    return result;
}
Value index_array(const std::vector<Index>& values) {
    std::vector<Value> result;
    for (const auto value : values) result.push_back(gx::workspace_integer(value));
    return gx::workspace_array(std::move(result));
}
struct Plan {std::vector<Index> starts, counts;};
// A page is an exact canonical C-order hyperslab: leading counts=1, final count
// <=512. This browses all cells without constructing or flattening a Dataset.
Plan plan(const std::vector<Index>& shape, std::vector<Index> starts, int direction) {
    if (shape.empty() || shape.size() > 64 || starts.size() != shape.size()) throw std::runtime_error("Page rank differs from the actual Variable");
    for (std::size_t i = 0; i < shape.size(); ++i)
        if (shape[i] < 1 || starts[i] < 0 || starts[i] >= shape[i]) throw std::runtime_error("Variable is empty or page is outside its actual shape");
    const auto last = shape.size() - 1;
    if (direction > 0) {
        const auto remaining = shape[last] - starts[last];
        if (remaining > 512) starts[last] += 512;
        else {
            bool advanced = false;
            auto next = starts;next[last] = 0;
            for (std::size_t i = last; i > 0; --i) {
                const auto axis = i - 1;
                if (next[axis] < shape[axis] - 1) {++next[axis];advanced = true;break;}
                next[axis] = 0;
            }
            if (!advanced) throw std::runtime_error("This is the last values page");
            starts = std::move(next);
        }
    } else if (direction < 0) {
        if (starts[last] >= 512) starts[last] -= 512;
        else {
            bool retreated = false;
            auto previous = starts;previous[last] = ((shape[last] - 1) / 512) * 512;
            for (std::size_t i = last; i > 0; --i) {
                const auto axis = i - 1;
                if (previous[axis] > 0) {--previous[axis];retreated = true;break;}
                previous[axis] = shape[axis] - 1;
            }
            if (!retreated) throw std::runtime_error("This is the first values page");
            starts = std::move(previous);
        }
    }
    auto counts = std::vector<Index>(shape.size(), 1);
    counts[last] = std::min<Index>(512, shape[last] - starts[last]);
    return {std::move(starts), std::move(counts)};
}
const Value& selected(const Value& current) {
    const auto wanted = text(current, "selected_variable");
    if (wanted.empty()) throw std::runtime_error("Choose First variable values to browse the discovered Variables");
    for (const auto& variable : array(current, "variables")) if (text(variable, "variable_id") == wanted) return variable;
    throw std::runtime_error("The selected Variable is outside this discovery batch; choose a Variable explicitly");
}
void read_values(gx::Host& host, unsigned form, const Value& current, const Value& variable, int direction) {
    const auto shape = indices(variable, "shape");
    if (integer(variable, "rank") != static_cast<Index>(shape.size())) throw std::runtime_error("Variable rank/shape differs");
    auto starts = std::vector<Index>(shape.size(), 0);
    if (direction) {
        const auto& page = field(current, "page");
        if (page.kind != Value::Kind::object || text(page, "variable_id") != text(variable, "variable_id") || text(page, "order") != "C")
            throw std::runtime_error("Read the first values page of this actual Variable first");
        starts = indices(page, "starts");
    }
    const auto page = plan(shape, std::move(starts), direction);
    host.scientific_preview_command(form, "page", gx::workspace_object({
        {"variable_id", gx::workspace_text(text(variable, "variable_id"))},
        {"starts", index_array(page.starts)}, {"counts", index_array(page.counts)}}));
}
void variable(gx::Host& host, unsigned form, const Value& current, int direction) {
    const auto& variables = array(current, "variables");
    if (variables.empty() || variables.size() > 64) throw std::runtime_error("Discover an admitted numeric Variable batch first");
    std::size_t index = 0;
    if (direction) {
        const auto wanted = text(selected(current), "variable_id");
        while (index < variables.size() && text(variables[index], "variable_id") != wanted) ++index;
        if ((direction > 0 && index + 1 >= variables.size()) || (direction < 0 && index == 0)) throw std::runtime_error("Choose the adjacent Variables batch to continue browsing");
        index = direction > 0 ? index + 1 : index - 1;
    }
    // First means an explicit user enumeration action, never a scientific default.
    read_values(host, form, current, variables[index], 0);
}
void batch(gx::Host& host, unsigned form, const Value& current, const char* operation, const char* prefix, int direction) {
    const auto offset = integer(current, (std::string(prefix) + "_offset").c_str());
    const auto total = integer(current, (std::string(prefix) + "_total").c_str());
    const Index size = std::string_view(operation) == "discover" ? 32 : 16;
    Index next = 0;
    if (direction > 0) {if (total <= offset || total - offset <= size) throw std::runtime_error("This is the last inspection batch");next = offset + size;}
    if (direction < 0) {if (offset == 0) throw std::runtime_error("This is the first inspection batch");next = offset >= size ? offset - size : 0;}
    host.scientific_preview_command(form, operation, gx::workspace_object({{"offset", gx::workspace_integer(next)}, {"limit", gx::workspace_integer(size)}}));
}
void initialize(gx::Host& host, unsigned form) {
    host.scientific_preview_command(form, "discover", gx::workspace_object());
    host.scientific_preview_command(form, "metadata", gx::workspace_object());
    host.scientific_preview_command(form, "source", gx::workspace_object());
}
bool route(gx::Host& host, unsigned form, const gx::Event&) {
    const std::string_view action(host.data());
    if (action == "science_refresh") {initialize(host, form);return true;}
    const auto& current = view(host);
    if (action == "values_first_variable") variable(host, form, current, 0);
    else if (action == "values_previous_variable") variable(host, form, current, -1);
    else if (action == "values_next_variable") variable(host, form, current, 1);
    else if (action == "values_first") read_values(host, form, current, selected(current), 0);
    else if (action == "values_previous") read_values(host, form, current, selected(current), -1);
    else if (action == "values_next") read_values(host, form, current, selected(current), 1);
    else {
        for (const auto* operation : {"discover", "metadata", "source"}) {
            const auto prefix = std::string_view(operation) == "discover" ? "variable" : operation;
            for (const auto* suffix : {"first", "previous", "next"}) {
                if (action == std::string(operation) + "_" + suffix) {
                    const int direction = std::string_view(suffix) == "next" ? 1 : std::string_view(suffix) == "previous" ? -1 : 0;
                    batch(host, form, current, operation, prefix, direction);return true;
                }
            }
        }
        return false;
    }
    return true;
}
}
