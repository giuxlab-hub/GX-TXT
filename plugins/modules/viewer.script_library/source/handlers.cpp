// SPDX-License-Identifier: GPL-3.0-or-later
// Authored P033 source staging. The real MAIN SDK/host extension is required.
// Paste/save this source through the normal C++ Workspace after GUI generation;
// this file alone is not a built, packaged or available Viewer.
#include <stdexcept>
#include <string_view>

namespace script_library {
using Value = gx::WorkspaceValue;
// Actual native Builder component order, not handwritten design identities.
constexpr unsigned form = 1, scope_filter = 4, language_filter = 5;
constexpr unsigned query = 6, records = 7, record_scope = 11;
constexpr unsigned record_language = 12, operation_status = 22;
constexpr unsigned source_files = 31;
constexpr std::int64_t page_size = 50;

const Value* field(const Value& object, const char* key) {
    if (object.kind != Value::Kind::object) return nullptr;
    const auto found = object.fields.find(key);
    return found == object.fields.end() ? nullptr : &found->second;
}
std::string text(const Value& object, const char* key) {
    const auto* value = field(object, key);
    if (!value || value->kind != Value::Kind::text)
        throw std::runtime_error("Script Library context has a missing text field");
    return value->text;
}
std::int64_t integer(const Value& object, const char* key) {
    const auto* value = field(object, key);
    if (!value || value->kind != Value::Kind::integer || value->integer < 0)
        throw std::runtime_error("Script Library context has an invalid integer field");
    return value->integer;
}
bool flag(const Value& object, const char* key) {
    const auto* value = field(object, key);
    if (!value || value->kind != Value::Kind::boolean)
        throw std::runtime_error("Script Library context has a missing Boolean field");
    return value->integer != 0;
}
const Value& current_view(gx::Host& host) {
    const auto* receipt = host.script_library_result();
    const auto* view = receipt ? field(*receipt, "view") : nullptr;
    if (!view || view->kind != Value::Kind::object)
        throw std::runtime_error("Script Library owner context is unavailable; reopen the Viewer");
    return *view;
}
const Value& selected(const Value& view, bool existing, bool source_read = false) {
    const auto* selection = field(view, "selected");
    if (!selection || selection->kind != Value::Kind::object)
        throw std::runtime_error("Choose a registered script or create a draft first");
    // Read availability is a typed feature hint; CORE authoritatively checks
    // the finite request even when false. Writers retain their original guard.
    if (source_read) (void)flag(view, "source_read_valid");
    if (!source_read && !flag(view, "selection_valid")) {
        const auto* message = field(view, "conflict_message");
        throw std::runtime_error(message && message->kind == Value::Kind::text
            ? message->text : "Registered source changed; review or reload before continuing");
    }
    const auto reference = text(*selection, "reference");
    if (existing && reference.empty())
        throw std::runtime_error("Save the new draft before using this action");
    return *selection;
}
Value cas(const Value& selection, bool draft) {
    const auto revision = integer(selection, "revision");
    const auto sha = text(selection, "sha256");
    auto request = gx::workspace_object({
        {"expected_revision", gx::workspace_integer(revision)},
        {"expected_sha256", gx::workspace_text(sha)}});
    if (draft) {
        const auto token = text(selection, "draft_token");
        if (token.empty()) throw std::runtime_error("The draft owner token is unavailable");
        request.fields.emplace("draft_token", gx::workspace_text(token));
    } else {
        request.fields.emplace("reference", gx::workspace_text(text(selection, "reference")));
    }
    return request;
}
std::string choice(const char* raw, const char* first, const char* second,
                   const char* third = nullptr) {
    const std::string value(raw ? raw : "");
    if (value == first || value == second || (third && value == third)) return value;
    throw std::runtime_error("The declared Script Library choice is invalid");
}
std::string bounded_query(const char* raw) {
    const std::string value(raw ? raw : "");
    // CORE supplies valid UTF-8. Count scalar starts without truncating a name,
    // source identity or multi-byte search character. No source is transported.
    std::size_t characters = 0;
    for (const unsigned char c : value) if ((c & 0xc0) != 0x80) ++characters;
    if (value.size() > 1024 || characters > 256)
        throw std::runtime_error("Narrow the search to at most 256 characters");
    return value;
}
void inventory(gx::Host& host, const Value& view, int direction, bool reset) {
    std::int64_t offset = 0;
    const auto* page = field(view, "inventory");
    if (!page || page->kind != Value::Kind::object)
        throw std::runtime_error("The Library inventory page is unavailable");
    const auto total = integer(*page, "total");
    const auto limit = integer(*page, "limit");
    if (limit > 100) throw std::runtime_error("The Library page exceeds its bound");
    if (!reset) offset = integer(*page, "offset");
    if (direction > 0 && offset < total && total - offset > page_size) offset += page_size;
    if (direction < 0) offset = offset >= page_size ? offset - page_size : 0;
    host.script_library_command(form, "list", gx::workspace_object({
        {"scope", gx::workspace_text(choice(host.input(scope_filter), "all", "user", "session"))},
        {"language", gx::workspace_text(choice(host.input(language_filter), "all", "python", "octave"))},
        {"query", gx::workspace_text(bounded_query(host.input(query)))},
        {"offset", gx::workspace_integer(offset)},
        {"limit", gx::workspace_integer(page_size)}}));
}
std::string draft_language(gx::Host& host) {
    const std::string value(host.input(record_language));
    if (value == "python" || value == "Python") return "python";
    if (value == "octave" || value == "Octave" || value.empty()) return "octave";
    throw std::runtime_error("Choose Python or Octave for the new draft");
}
struct Action { const char* id; const char* operation; bool needs_selection; };
constexpr Action actions[] = {
    {"save", "save", true}, {"copy_record", "copy_record", true},
    {"assign_session", "assign_session", true}, {"export", "export", true},
    {"delete", "delete", true}, {"open_workspace", "open_workspace", true},
    {"run_review", "run_review", true},
    {"source_undo", "undo", false}, {"source_redo", "redo", false},
    {"cut", "cut", false}, {"copy_text", "copy_text", false},
    {"paste", "paste", false}, {"select_all", "select_all", false},
    {"find", "find", false}, {"replace", "replace", false},
    {"jobs", "jobs", false}, {"close", "close", false}
};
void route(gx::Host& host, const gx::Event& event) {
    const auto& view = current_view(host);
    const std::string_view action(host.data());
    if (event.kind == gx::EventKind::open || action == "refresh") {
        inventory(host, view, 0, event.kind == gx::EventKind::open);
        return;
    }
    if (action == "filter_changed" || (event.kind == gx::EventKind::changed &&
        (event.component == scope_filter || event.component == language_filter || event.component == query))) {
        inventory(host, view, 0, true);
        return;
    }
    if (action == "page_previous" || action == "page_next") {
        inventory(host, view, action == "page_next" ? 1 : -1, false);
        return;
    }
    if (action == "record_selected" || action == "review_owner" ||
        ((event.kind == gx::EventKind::selection || event.kind == gx::EventKind::changed) && event.component == records)) {
        const auto* selected_row = field(view, "selected_row_reference");
        if (selected_row && selected_row->kind == Value::Kind::null) {
            if (action == "review_owner")
                throw std::runtime_error("Select the registered source row to review its current owner");
            return;
        }
        const auto reference = text(view, "selected_row_reference");
        const auto* page = field(view, "inventory");
        const auto* entries = page ? field(*page, "records") : nullptr;
        if (!entries || entries->kind != Value::Kind::array || entries->elements.size() > 100)
            throw std::runtime_error("The selected inventory page is invalid");
        for (const auto& record : entries->elements) {
            if (text(record, "reference") == reference) {
                auto request = cas(record, false);
                if (action == "review_owner")
                    request.fields.emplace("review_owner", gx::workspace_flag(true));
                host.script_library_command(form, "select", request);
                return;
            }
        }
        throw std::runtime_error("The selected row is not in the current owner inventory");
    }
    if (action == "source_select" ||
        ((event.kind == gx::EventKind::selection || event.kind == gx::EventKind::changed) && event.component == source_files)) {
        auto request = cas(selected(view, true, true), false);
        request.fields.emplace("relative_file", gx::workspace_text(text(view, "selected_relative_file")));
        host.script_library_command(form, "source_select", request);
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    if (action == "new_user_script" || action == "new_session_script" || action == "new_project") {
        std::string scope = action == "new_session_script" ? "session" : "user";
        if (action == "new_project") {
            const std::string proposed(host.input(record_scope));
            if (!proposed.empty()) scope = choice(proposed.c_str(), "user", "session");
        }
        const auto language = draft_language(host);
        host.script_library_command(form, action == "new_project" ? "new_project" : "new_script",
            gx::workspace_object({{"scope", gx::workspace_text(scope)},
                                  {"language", gx::workspace_text(language)}}));
        return;
    }
    if (action == "import_script" || action == "import_project") {
        const std::string current_scope(host.input(record_scope));
        const std::string filter_scope(host.input(scope_filter));
        const std::string scope = current_scope.empty()
            ? (filter_scope == "session" ? "session" : "user")
            : choice(current_scope.c_str(), "user", "session");
        host.script_library_command(form, action.data(),
            gx::workspace_object({{"scope", gx::workspace_text(scope)}}));
        return;
    }
    for (const auto& route : actions) {
        if (action != route.id) continue;
        auto request = gx::workspace_object();
        if (route.needs_selection) request = cas(selected(view, action != "save"), action == "save");
        host.script_library_command(form, route.operation, request);
        return;
    }
}
}
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    (void)state; // Viewing/copying never dirties the Workspace with a synthetic counter.
    try {
        script_library::route(host, event);
    } catch (const std::exception& error) {
        host.text(script_library::operation_status, error.what());
    }
}
