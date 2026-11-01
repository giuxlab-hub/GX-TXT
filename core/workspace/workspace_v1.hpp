// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstdint>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <utility>

namespace gx::workspace::v1 {
inline constexpr unsigned contract_version = 1;
enum class Kind { null, text, boolean, integer, real, object, array, resource };

// The native domain has no dependency on Tcl, a GUI, SQL or IPC. Text is never
// interpreted as a dictionary/list/code by the persistence engine.
struct Value {
    Kind kind = Kind::null;
    // Text content, or optional original numeric/boolean scalar spelling.
    // Numeric semantics remain in integer/real; no container is serialized here.
    std::string text;
    std::int64_t integer = 0;
    double real = 0;
    std::map<std::string, Value> fields;
    // Optional declared order for transports whose scientific receipts retain
    // ordered fields. Empty means canonical key order; it is never parsed text.
    std::vector<std::string> field_order;
    std::vector<Value> elements;
    static Value string(std::string);
    static Value number(std::int64_t);
    static Value floating(double);
    static Value boolean(bool);
    static Value object(std::map<std::string, Value> = {});
    static Value array(std::vector<Value> = {});
    bool operator==(const Value&) const;
    bool operator!=(const Value& other) const {return !(*this == other);}
};

struct Error : std::runtime_error {
    std::string code;
    Error(std::string code, std::string message);
};
struct Schema {
    std::string provider, owner, id, version;
    std::map<std::string, Kind> required;
};
struct Identity {
    std::string id, generation;
    std::uint64_t revision = 0;
};
struct Workspace {
    Identity identity;
    std::string owner, provider, schema, schema_version, name, notes;
    std::string created_at, updated_at, content_sha256;
    Value state = Value::object();
    Value properties = Value::object();
    Value provenance = Value::object();
};
struct Receipt {
    Identity identity;
    std::uint64_t durable_revision = 0;
    bool accepted = true, pending = false, failed = false;
    std::size_t queued_bytes = 0;
    std::string error;
};
struct Query {
    std::string provider, owner, name_prefix;
    std::size_t offset = 0, limit = 1000;
};
struct Summary {
    Identity identity;
    std::string owner, provider, schema, schema_version, name, created_at, updated_at, content_sha256;
    bool has_notes = false, has_preview = false;
};

// A Store exclusively owns one Session database. Its worker owns the SQLite
// connection. Readers see accepted immutable RAM snapshots; status never reads
// state or hashes scientific data. Closing drains accepted work or throws.
class Store {
public:
    explicit Store(const std::string& database_path);
    ~Store();
    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;
    void register_schema(Schema);
    Receipt create(std::string provider, std::string name, Value state,
                   Value properties = Value::object(), Value provenance = Value::object());
    Workspace get(const std::string& id) const;
    Value properties(const std::string& id) const;
    Summary metadata(const std::string& id) const;
    std::string note_text(const std::string& id) const;
    std::string resource_owner_generation(const std::string& id) const;
    std::string retired_owner_generation(const std::string& id) const;
    Value retained_references(const std::string& exclude_workspace = {}, const std::string& only_workspace = {});
    // Trusted scientific-owner admission, scoped to this open Store lifetime.
    // This registers identity only; it neither creates nor converts a Workspace.
    void register_resource_owner(std::string id, std::string generation);
    std::vector<Summary> query(const Query& = {}) const;
    Receipt duplicate(const Identity& source, std::string name);
    Value lineage(const std::string& id) const;
    void checkpoint();
    std::string transition_prepare(const Identity&, Value intent);
    Value transition_list();
    Receipt transition_commit(const std::string& token, const Identity&, Value state, Value properties);
    void transition_finish(const std::string& token);
    void capsule_export(const Identity&, const std::string& path);
    Receipt capsule_import(const std::string& path, std::string name);
    static Value capsule_inspect(const std::string& path);
    Receipt save(const Identity& expected, Value state, Value properties);
    Receipt save_properties(const Identity& expected, Value properties);
    Receipt rename(const Identity& expected, std::string name);
    Receipt notes(const Identity& expected, std::string text);
    Receipt erase(const Identity& expected, bool confirmed);
    std::pair<Receipt,std::string> history_save(const Identity&, std::string name,
                                               Value record, Value auxiliary, Value context);
    Value history_list(const std::string& workspace) const;
    Value history_get(const std::string& workspace, const std::string& archive) const;
    Receipt history_rename(const Identity&, const std::string& archive, std::string name);
    Receipt history_delete(const Identity&, const std::string& archive, bool confirmed);
    Receipt status(const std::string& id) const;
    Receipt flush(const std::string& id, unsigned timeout_ms = 30000);
    void flush_all(unsigned timeout_ms = 30000);
    void close();
private:
    struct Impl;
    std::unique_ptr<Impl> p;
};
}
