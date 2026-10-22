/* SPDX-License-Identifier: GPL-3.0-or-later
 * Repeated cell/lexical uniqueness/byte-budget collection, not a scientific
 * validator. Numeric candidate admission calls the existing Graph Series owner.
 */
#include "gx2d_preview_categories_v1.h"
#include <tcl.h>
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {
class Object {
public:
    explicit Object(Tcl_Obj *value) : p(value) { Tcl_IncrRefCount(p); }
    ~Object() { Tcl_DecrRefCount(p); }
    Object(const Object &) = delete;
    Object &operator=(const Object &) = delete;
    Tcl_Obj *get() const { return p; }
private:
    Tcl_Obj *p;
};
Tcl_Obj *text(const std::string &s) {
    if (s.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()))
        throw std::runtime_error("Categorical text exceeds Tcl capacity");
    return Tcl_NewStringObj(s.data(), static_cast<int>(s.size()));
}
std::string key(Tcl_Obj *value) {
    int bytes = 0; const auto p = Tcl_GetStringFromObj(value, &bytes);
    // Tcl's own byte representation matches string bytelength/dictionary keys,
    // including embedded NUL and non-BMP characters; do not re-encode UTF-8.
    return std::string(p, static_cast<std::size_t>(bytes));
}
void put(Tcl_Interp *ip, Tcl_Obj *d, const std::string &name, Tcl_Obj *value) {
    Object k(text(name));
    if (Tcl_DictObjPut(ip, d, k.get(), value) != TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
}
Tcl_Obj *field(Tcl_Interp *ip, Tcl_Obj *d, const char *name) {
    Object k(Tcl_NewStringObj(name, -1)); Tcl_Obj *out = nullptr;
    if (Tcl_DictObjGet(ip, d, k.get(), &out) != TCL_OK || !out)
        throw std::runtime_error(std::string("Categorical column is missing ") + name);
    return out;
}
std::vector<Tcl_Obj *> list(Tcl_Interp *ip, Tcl_Obj *value) {
    int count; Tcl_Obj **items;
    if (Tcl_ListObjGetElements(ip, value, &count, &items) != TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
    if (!count) return {};
    return std::vector<Tcl_Obj *>(items, items + count);
}
Tcl_WideInt integer(Tcl_Interp *ip, Tcl_Obj *value) {
    Tcl_WideInt out;
    if (Tcl_GetWideIntFromObj(ip, value, &out) != TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
    return out;
}
struct Column {
    std::string id, dtype;
    std::vector<std::string> order;
    std::unordered_set<std::string> retained;
    std::unordered_map<std::string, bool> checked;
    std::size_t cacheBytes = 0;
    bool truncated = false;
};
struct Collector {
    std::vector<Column> columns;
    Tcl_WideInt valueBudget, retainedBytes;
    std::size_t cacheBytes = 0;
    bool busy = false;
};
struct State {
    std::uint64_t serial = 0;
    std::map<std::string, std::shared_ptr<Collector>> instances;
};
struct Busy {
    explicit Busy(Collector &value) : c(value) {
        if (c.busy) throw std::runtime_error("Categorical collector is already in use");
        c.busy = true;
    }
    ~Busy() { c.busy = false; }
    Collector &c;
};
bool valid(Tcl_Interp *ip, Collector &collector, Column &column,
           Tcl_Obj *value, const std::string &lexical) {
    if (column.dtype == "string") return true;
    const auto found = column.checked.find(lexical);
    if (found != column.checked.end()) return found->second;
    Object command(Tcl_NewStringObj("::GX::graphSeriesCanonicalMember", -1));
    Object dtype(text(column.dtype));
    Tcl_Obj *arguments[] = {command.get(), dtype.get(), value};
    const bool admitted = Tcl_EvalObjv(ip, 3, arguments, TCL_EVAL_GLOBAL) == TCL_OK;
    // Equivalent to the old catch: admission only; the owner's canonicalized
    // return value must NEVER replace the original lexical category key.
    Tcl_ResetResult(ip);
    // Ephemeral cache: <=128 candidate keys per column, <=512KiB key bytes
    // across the collector, and no key longer than the retained-value bound.
    // Evicted/uncached candidates may call the owner again; this is not a claim
    // of one validation per source value over an unbounded dataset.
    if (lexical.size() <= 1024) {
        if (column.checked.size() >= 128) {
            collector.cacheBytes -= column.cacheBytes;
            column.checked.clear(); column.cacheBytes = 0;
        }
        if (collector.cacheBytes + lexical.size() <= 524288) {
            column.checked.emplace(lexical, admitted);
            column.cacheBytes += lexical.size(); collector.cacheBytes += lexical.size();
        }
    }
    return admitted;
}
void push(Tcl_Interp *ip, Collector &collector, Tcl_Obj *columns, Tcl_WideInt take) {
    Busy guard(collector);
    if (take < 0 || take > 2048) throw std::runtime_error("Categorical chunk exceeds the owning host's 2048-row bound");
    const auto input = list(ip, columns);
    if (input.size() != collector.columns.size())
        throw std::runtime_error("Categorical columns differ from their schema projection");
    for (std::size_t at = 0; at < input.size(); ++at) {
        const auto values = list(ip, field(ip, input[at], "values"));
        if (static_cast<std::uint64_t>(take) > values.size())
            throw std::runtime_error("Categorical column is shorter than the selected row prefix");
        auto &column = collector.columns[at];
        for (Tcl_WideInt row = 0; row < take; ++row) {
            auto *value = values[static_cast<std::size_t>(row)]; const auto lexical = key(value);
            // Already-retained exact lexical keys were admitted by this same
            // authority and can bypass repeated numeric validator calls.
            if (column.retained.find(lexical) != column.retained.end()) continue;
            if (!valid(ip, collector, column, value, lexical)) continue;
            if (lexical.size() > 1024) { column.truncated = true; continue; }
            // Preserve the old empty-dictionary edge: even valueBudget<=0 may
            // retain the first value, then marks later distinct keys truncated.
            if (!column.order.empty() && (collector.valueBudget <= 0 ||
                column.order.size() >= static_cast<std::uint64_t>(collector.valueBudget))) {
                column.truncated = true; continue;
            }
            if (collector.retainedBytes > 2097152 - static_cast<Tcl_WideInt>(lexical.size())) {
                column.truncated = true; continue;
            }
            column.retained.insert(lexical); column.order.push_back(lexical);
            collector.retainedBytes += static_cast<Tcl_WideInt>(lexical.size());
        }
    }
}
Tcl_Obj *finish(Tcl_Interp *ip, const Collector &collector) {
    Object result(Tcl_NewDictObj()), truncated(Tcl_NewDictObj()); bool haveTruncated = false;
    for (const auto &column : collector.columns) {
        if (!column.order.empty()) {
            Object values(Tcl_NewDictObj());
            for (const auto &lexical : column.order) put(ip, values.get(), lexical, Tcl_NewIntObj(1));
            put(ip, result.get(), column.id, values.get());
        }
        if (column.truncated) { put(ip, truncated.get(), column.id, Tcl_NewIntObj(1)); haveTruncated = true; }
    }
    if (haveTruncated) put(ip, result.get(), "@truncated", truncated.get());
    Tcl_SetObjResult(ip, result.get()); return Tcl_GetObjResult(ip);
}
int command(ClientData data, Tcl_Interp *ip, int argc, Tcl_Obj *const argv[]) {
    auto &state = *static_cast<State *>(data);
    try {
        if (argc < 2) throw std::runtime_error("Expected internal category operation");
        const auto operation = key(argv[1]);
        if (operation == "api_info" && argc == 2) {
            Object result(Tcl_NewDictObj()); put(ip, result.get(), "abi_version", Tcl_NewIntObj(1));
            put(ip, result.get(), "validator", Tcl_NewStringObj("graphSeriesCanonicalMember", -1));
            put(ip, result.get(), "active_collectors", Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(state.instances.size())));
            Tcl_SetObjResult(ip, result.get()); return TCL_OK;
        }
        if (operation == "begin" && argc == 5) {
            const auto specifications = list(ip, argv[2]);
            if (specifications.size() > 32) throw std::runtime_error("Categorical schema exceeds the existing 32-variable discovery bound");
            auto collector = std::make_shared<Collector>();
            collector->valueBudget = integer(ip, argv[3]); collector->retainedBytes = integer(ip, argv[4]);
            if (collector->retainedBytes < 0 || collector->retainedBytes > 2097152)
                throw std::runtime_error("Categorical initial byte accounting is outside the owning discovery budget");
            for (auto *specification : specifications) {
                Column column;
                column.id = key(field(ip, specification, "variable_id"));
                column.dtype = key(field(ip, specification, "dtype"));
                collector->columns.push_back(std::move(column));
            }
            const auto token = "preview-categories#" + std::to_string(++state.serial);
            state.instances.emplace(token, collector);
            Tcl_SetObjResult(ip, text(token)); return TCL_OK;
        }
        if (argc < 3) throw std::runtime_error("Expected internal category token");
        const auto token = key(argv[2]); const auto found = state.instances.find(token);
        if (operation == "destroy" && argc == 3) { state.instances.erase(token); return TCL_OK; }
        if (found == state.instances.end()) throw std::runtime_error("Unknown category collector token");
        const auto collector = found->second; // safe even if an owner callback removes the token
        if (operation == "push" && argc == 5) {
            push(ip, *collector, argv[3], integer(ip, argv[4]));
            Tcl_SetObjResult(ip, Tcl_NewWideIntObj(collector->retainedBytes)); return TCL_OK;
        }
        if (operation == "finish" && argc == 3) {
            if (collector->busy) throw std::runtime_error("Categorical collector is already in use");
            finish(ip, *collector); return TCL_OK;
        }
        throw std::runtime_error("Invalid internal category operation/arguments");
    } catch (const std::exception &e) {
        Tcl_SetObjResult(ip, Tcl_NewStringObj(e.what(), -1));
        Tcl_SetErrorCode(ip, "GXTXT", "PreviewCategories", "NativeCollect", nullptr);
        return TCL_ERROR;
    }
}
void cleanup(ClientData data, Tcl_Interp *) { delete static_cast<State *>(data); }
} // namespace

extern "C" int gx2d_preview_categories_v1_init(Tcl_Interp *ip) {
    if (!Tcl_FindNamespace(ip, "::GX", nullptr, TCL_GLOBAL_ONLY)) Tcl_CreateNamespace(ip, "::GX", nullptr, nullptr);
    if (!Tcl_FindNamespace(ip, "::GX::PreviewCategories", nullptr, TCL_GLOBAL_ONLY))
        Tcl_CreateNamespace(ip, "::GX::PreviewCategories", nullptr, nullptr);
    auto *state = new State;
    Tcl_SetAssocData(ip, "gxtxt.preview.categories.v1", cleanup, state);
    Tcl_CreateObjCommand(ip, "::GX::PreviewCategories::native", command, state, nullptr);
    return TCL_OK;
}
extern "C" int Gxtxtcategories_Init(Tcl_Interp *ip) {
    if (!Tcl_InitStubs(ip, "8.6", 0)) return TCL_ERROR;
    return gx2d_preview_categories_v1_init(ip);
}
