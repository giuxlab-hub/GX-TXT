/* SPDX-License-Identifier: GPL-3.0-or-later
 * Canonical CSV provider adapter. No source paths, storage registry, renderer,
 * persistent parser, Tcl evaluation, worker process or GUI access lives here.
 */
#include "gx2d_csv_provider_v1.h"
#include <tcl.h>
#include <algorithm>
#include <cstdint>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Unicode = std::basic_string<Tcl_UniChar>;
class Object {
public:
    explicit Object(Tcl_Obj *p) : value(p) { Tcl_IncrRefCount(value); }
    ~Object() { Tcl_DecrRefCount(value); }
    Object(const Object &) = delete;
    Object &operator=(const Object &) = delete;
    Tcl_Obj *get() const { return value; }
private:
    Tcl_Obj *value;
};
Tcl_Obj *text(const char *s) { return Tcl_NewStringObj(s, -1); }
void put(Tcl_Interp *ip, Tcl_Obj *dict, const char *key, Tcl_Obj *value) {
    Object name(text(key));
    if (Tcl_DictObjPut(ip, dict, name.get(), value) != TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
}
Tcl_Obj *field(Tcl_Interp *ip, Tcl_Obj *dict, const char *key) {
    Object name(text(key)); Tcl_Obj *out = nullptr;
    if (Tcl_DictObjGet(ip, dict, name.get(), &out) != TCL_OK || !out)
        throw std::runtime_error(std::string("CSV variable specification is missing ") + key);
    return out;
}
Unicode unicode(Tcl_Obj *value) {
    int count = 0; const auto *p = Tcl_GetUnicodeFromObj(value, &count);
    return Unicode(p, p + count);
}
Tcl_Obj *unicodeObject(const Unicode &value) {
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()))
        throw std::runtime_error("CSV field exceeds the Tcl string capacity");
    return Tcl_NewUnicodeObj(value.data(), static_cast<int>(value.size()));
}
bool blank(const Unicode &value) {
    return std::all_of(value.begin(), value.end(), [](Tcl_UniChar c) {
        return Tcl_UniCharIsSpace(c) != 0;
    });
}
bool physical(Tcl_Interp *ip, Tcl_Channel channel, Unicode &out) {
    Object line(Tcl_NewObj());
    if (Tcl_GetsObj(channel, line.get()) < 0) {
        if (Tcl_Eof(channel)) return false;
        throw std::runtime_error(std::string("Cannot read canonical CSV channel: ") + Tcl_PosixError(ip));
    }
    out = unicode(line.get()); return true;
}
// Same quote admission/continuation policy as datasetSchemaCsvSplit. In
// particular, a quote following whitespace is scientific text, not syntax.
std::vector<Unicode> record(Tcl_Interp *ip, Tcl_Channel channel,
                            Unicode line, Tcl_UniChar separator) {
    std::vector<Unicode> out; Unicode buffer; bool quoted = false;
    for (std::size_t i = 0; i < line.size(); ++i) {
        const auto c = line[i];
        if (quoted) {
            if (c == '"') {
                if (i + 1 < line.size() && line[i + 1] == '"') { buffer.push_back('"'); ++i; }
                else quoted = false;
            } else buffer.push_back(c);
        } else if (c == separator) { out.push_back(std::move(buffer)); buffer.clear(); }
        else if (c == '"' && buffer.empty()) quoted = true;
        else buffer.push_back(c);
        if (i == line.size() - 1 && quoted) {
            Unicode continuation;
            if (!physical(ip, channel, continuation))
                throw std::runtime_error("Unterminated quoted CSV field");
            line.assign(1, '\n'); line += continuation;
            // Unsigned wrap is defined; the loop increment resumes at zero.
            i = std::numeric_limits<std::size_t>::max();
        }
    }
    if (quoted) throw std::runtime_error("Unterminated quoted CSV field");
    out.push_back(std::move(buffer)); return out;
}
struct Projection {
    std::string id, dtype, kind, format, decimal;
    std::size_t column;
    std::unique_ptr<Object> values;
};
std::vector<Projection> projections(Tcl_Interp *ip, Tcl_Obj *specifications) {
    Tcl_DictSearch search; Tcl_Obj *key, *item; int done = 0;
    if (Tcl_DictObjFirst(ip, specifications, &search, &key, &item, &done) != TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
    std::vector<Projection> out;
    try {
        for (; !done; Tcl_DictObjNext(&search, &key, &item, &done)) {
            Tcl_WideInt position;
            if (Tcl_GetWideIntFromObj(ip, field(ip, item, "column"), &position) != TCL_OK || position < 0)
                throw std::runtime_error("Invalid canonical CSV column position");
            auto variable = field(ip, item, "variable");
            Projection p;
            p.id = Tcl_GetString(key);
            p.column = static_cast<std::size_t>(position);
            p.dtype = Tcl_GetString(field(ip, variable, "dtype"));
            p.kind = Tcl_GetString(field(ip, variable, "value_kind"));
            p.format = Tcl_GetString(field(ip, variable, "value_format"));
            p.decimal = Tcl_GetString(field(ip, variable, "decimal_separator"));
            p.values = std::make_unique<Object>(Tcl_NewListObj(0, nullptr));
            out.push_back(std::move(p));
        }
    } catch (...) { Tcl_DictObjDone(&search); throw; }
    Tcl_DictObjDone(&search); return out;
}
Unicode trimNumeric(Unicode raw) {
    const auto space = [](Tcl_UniChar c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; };
    const auto first = std::find_if_not(raw.begin(), raw.end(), space);
    const auto last = std::find_if_not(raw.rbegin(), raw.rend(), space).base();
    return first < last ? Unicode(first, last) : Unicode();
}
bool hmsParts(const Unicode &raw, Unicode &hours, Unicode &minutes, Unicode &seconds) {
    const auto digit = [](Tcl_UniChar c) { return c >= '0' && c <= '9'; };
    auto colon = std::find(raw.begin(), raw.end(), ':');
    if (colon == raw.begin() || colon == raw.end() || !std::all_of(raw.begin(), colon, digit)) return false;
    const auto start = static_cast<std::size_t>(colon - raw.begin());
    if (raw.size() < start + 6 || raw[start + 1] < '0' || raw[start + 1] > '5' ||
        !digit(raw[start + 2]) || raw[start + 3] != ':' || raw[start + 4] < '0' ||
        raw[start + 4] > '5' || !digit(raw[start + 5])) return false;
    if (raw.size() != start + 6) {
        if (raw.size() < start + 8 || (raw[start + 6] != '.' && raw[start + 6] != ',') ||
            !std::all_of(raw.begin() + start + 7, raw.end(), digit)) return false;
    }
    hours.assign(raw.begin(), colon);
    minutes.assign(raw.begin() + start + 1, raw.begin() + start + 3);
    seconds.assign(raw.begin() + start + 4, raw.end());
    std::replace(seconds.begin(), seconds.end(), static_cast<Tcl_UniChar>(','), static_cast<Tcl_UniChar>('.'));
    return true;
}
double number(Tcl_Interp *ip, const Unicode &value) {
    Object operand(unicodeObject(value)); double result;
    if (Tcl_GetDoubleFromObj(ip, operand.get(), &result) != TCL_OK)
        throw std::runtime_error(Tcl_GetStringResult(ip));
    return result;
}
Tcl_Obj *typedValue(Tcl_Interp *ip, const Projection &p, const Unicode &source) {
    if (p.dtype == "string" || p.kind == "text") return unicodeObject(source);
    auto raw = trimNumeric(source);
    if (raw.empty()) return Tcl_NewObj();
    if (p.kind == "elapsed_time" && p.format == "hms") {
        Unicode hours, minutes, seconds;
        if (!hmsParts(raw, hours, minutes, seconds)) return text("NaN");
        const auto h = number(ip, hours), m = number(ip, minutes), s = number(ip, seconds);
        return Tcl_NewDoubleObj(h * 3600.0 + m * 60.0 + s);
    }
    if (p.decimal == ",")
        std::replace(raw.begin(), raw.end(), static_cast<Tcl_UniChar>(','), static_cast<Tcl_UniChar>('.'));
    Object candidate(unicodeObject(raw));
    int utf8Bytes = 0;
    const auto utf8 = Tcl_GetStringFromObj(candidate.get(), &utf8Bytes);
    std::string lower(utf8, static_cast<std::size_t>(utf8Bytes));
    for (auto &c : lower) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    if (lower == "nan" || lower == "+nan" || lower == "-nan" || lower == "inf" ||
        lower == "+inf" || lower == "-inf" || lower == "infinity" ||
        lower == "+infinity" || lower == "-infinity") return unicodeObject(raw);
    double ignored;
    if (Tcl_GetDoubleFromObj(nullptr, candidate.get(), &ignored) == TCL_OK) return unicodeObject(raw);
    return text("NaN");
}
Tcl_Channel readable(Tcl_Interp *ip, Tcl_Obj *name) {
    int mode = 0; const auto channel = Tcl_GetChannel(ip, Tcl_GetString(name), &mode);
    if (!channel || !(mode & TCL_READABLE)) throw std::runtime_error("Canonical CSV channel is not readable");
    return channel;
}
Tcl_UniChar delimiter(Tcl_Obj *value) {
    const auto u = unicode(value);
    if (u.size() != 1) throw std::runtime_error("Native CSV requires one Unicode delimiter character");
    return u[0];
}
int command(ClientData, Tcl_Interp *ip, int argc, Tcl_Obj *const argv[]) {
    try {
        if (argc < 2) throw std::runtime_error("Expected canonical CSV native operation");
        const std::string operation = Tcl_GetString(argv[1]);
        if (operation == "api_info" && argc == 2) {
            Object result(Tcl_NewDictObj());
            put(ip, result.get(), "abi_version", Tcl_NewIntObj(1));
            put(ip, result.get(), "operations", text("header read"));
            put(ip, result.get(), "transport", text("canonical_values"));
            Tcl_SetObjResult(ip, result.get()); return TCL_OK;
        }
        if (operation == "header" && argc == 4) {
            const auto channel = readable(ip, argv[2]); const auto sep = delimiter(argv[3]);
            Unicode line; if (physical(ip, channel, line)) record(ip, channel, std::move(line), sep);
            return TCL_OK;
        }
        if (operation != "read" || argc != 8)
            throw std::runtime_error("Usage: canonical CSV native read channel delimiter specifications next_row start count");
        const auto channel = readable(ip, argv[2]); const auto sep = delimiter(argv[3]);
        auto projected = projections(ip, argv[4]);
        Tcl_WideInt row, start, count;
        if (Tcl_GetWideIntFromObj(ip, argv[5], &row) != TCL_OK || row < 0 ||
            Tcl_GetWideIntFromObj(ip, argv[6], &start) != TCL_OK || start < row ||
            Tcl_GetWideIntFromObj(ip, argv[7], &count) != TCL_OK || count < -1)
            throw std::runtime_error("Invalid canonical CSV native range");
        Tcl_WideInt skipped = 0, taken = 0; Unicode line;
        while (row < start && physical(ip, channel, line)) {
            if (blank(line)) continue;
            record(ip, channel, std::move(line), sep); ++row; ++skipped;
        }
        while (count < 0 || taken < count) {
            if (!physical(ip, channel, line)) break;
            if (blank(line)) continue;
            const auto fields = record(ip, channel, std::move(line), sep);
            for (auto &p : projected) {
                const Unicode empty;
                if (Tcl_ListObjAppendElement(ip, p.values->get(), typedValue(ip, p, p.column < fields.size() ? fields[p.column] : empty)) != TCL_OK)
                    throw std::runtime_error(Tcl_GetStringResult(ip));
            }
            if (row == std::numeric_limits<Tcl_WideInt>::max()) throw std::runtime_error("CSV row identity exceeds supported range");
            ++row; ++taken;
        }
        Object result(Tcl_NewDictObj()), columns(Tcl_NewDictObj());
        for (const auto &p : projected) put(ip, columns.get(), p.id.c_str(), p.values->get());
        put(ip, result.get(), "values", columns.get());
        put(ip, result.get(), "next_row", Tcl_NewWideIntObj(row));
        put(ip, result.get(), "taken", Tcl_NewWideIntObj(taken));
        put(ip, result.get(), "skipped", Tcl_NewWideIntObj(skipped));
        Tcl_SetObjResult(ip, result.get()); return TCL_OK;
    } catch (const std::exception &e) {
        Tcl_SetObjResult(ip, text(e.what()));
        Tcl_SetErrorCode(ip, "GXTXT", "CanonicalCSV", "NativeRead", nullptr);
        return TCL_ERROR;
    }
}
} // namespace

extern "C" int gx2d_csv_provider_v1_init(Tcl_Interp *ip) {
    if (!Tcl_FindNamespace(ip, "::GX", nullptr, TCL_GLOBAL_ONLY))
        Tcl_CreateNamespace(ip, "::GX", nullptr, nullptr);
    if (!Tcl_FindNamespace(ip, "::GX::DatasetCSV", nullptr, TCL_GLOBAL_ONLY))
        Tcl_CreateNamespace(ip, "::GX::DatasetCSV", nullptr, nullptr);
    Tcl_CreateObjCommand(ip, "::GX::DatasetCSV::native", command, nullptr, nullptr);
    return TCL_OK;
}

// Developer-only standalone build entry; normal installation registers through
// the existing gx2dtcl initializer. This entry never opens a display.
extern "C" int Gxtxtcsv_Init(Tcl_Interp *ip) {
    if (!Tcl_InitStubs(ip, "8.6", 0)) return TCL_ERROR;
    return gx2d_csv_provider_v1_init(ip);
}
