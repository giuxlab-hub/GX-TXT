/* SPDX-License-Identifier: GPL-3.0-or-later
 * Bounded display-only plane preparation. Source acquisition remains canonical.
 */
#include "gx2d_preview_plane_v1.h"
#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

namespace {
int fail(Tcl_Interp *ip, const char *message) {
    Tcl_SetObjResult(ip, Tcl_NewStringObj(message, -1));
    return TCL_ERROR;
}
// Share the existing typed-column structural/float decoder. Integer plane
// intensities use exact ordered keys, rather than coordinate double conversion.
#include "gx2d_tcl_columns.h"
struct Sample { double value = 0; uint64_t key = 0; bool finite = false; };

bool decimal_integer(const char *word, size_t length, bool is_unsigned, uint64_t &key) {
    const char *end = word + length;
    if (word == end) return false;
    if (*word == '+') ++word;
    if (word == end) return false;
    if (is_unsigned) {
        uint64_t v;
        auto r = std::from_chars(word, end, v);
        if (r.ec != std::errc() || r.ptr != end) return false;
        key = v;
    } else {
        int64_t v;
        auto r = std::from_chars(word, end, v);
        if (r.ec != std::errc() || r.ptr != end) return false;
        key = static_cast<uint64_t>(v) ^ (UINT64_C(1) << 63);
    }
    return true;
}
Sample sample(const numeric_column &column, size_t index) {
    Sample result;
    if (column.kind == 5 || column.kind == 6) {
        if (column.values) {
            int length;
            const char *word = Tcl_GetStringFromObj(column.values[index], &length);
            result.finite = decimal_integer(word, static_cast<size_t>(length),
                                           column.kind == 5, result.key);
            if (result.finite && column.width < 8) {
                const unsigned bits = static_cast<unsigned>(8 * column.width);
                if (column.kind == 5) result.finite = result.key < (UINT64_C(1) << bits);
                else {
                    const uint64_t middle = UINT64_C(1) << 63, half = UINT64_C(1) << (bits - 1);
                    result.finite = result.key >= middle - half && result.key < middle + half;
                }
            }
        } else {
            uint64_t bits = 0;
            for (size_t j = 0; j < column.width; ++j)
                bits |= uint64_t(column.bytes[index * column.width +
                              (column.big ? column.width - j - 1 : j)]) << (8 * j);
            if (column.kind == 6) {
                if (column.width < 8 && (bits & (UINT64_C(1) << (8 * column.width - 1))))
                    bits |= UINT64_MAX << (8 * column.width);
                bits ^= UINT64_C(1) << 63;
            }
            result.key = bits;
            result.finite = true;
        }
    } else {
        // Invalid/missing/nonfinite values retain the existing gray-cell policy.
        result.finite = numeric_column_value(nullptr, &column, index, &result.value) == TCL_OK
                        && std::isfinite(result.value);
    }
    return result;
}
Tcl_Obj *label(const Sample &s, int kind) {
    if (kind != 5 && kind != 6) return Tcl_NewDoubleObj(s.value);
    std::string text;
    if (kind == 5) text = std::to_string(s.key);
    else {
        uint64_t bits = s.key ^ (UINT64_C(1) << 63);
        int64_t value;
        std::memcpy(&value, &bits, sizeof value);
        text = std::to_string(value);
    }
    return Tcl_NewStringObj(text.data(), static_cast<int>(text.size()));
}
void field(Tcl_Obj *dict, const char *name, Tcl_Obj *value) {
    Tcl_DictObjPut(nullptr, dict, Tcl_NewStringObj(name, -1), value);
}
int prepare(ClientData, Tcl_Interp *ip, int objc, Tcl_Obj *const objv[]) {
    if (objc != 4) {Tcl_WrongNumArgs(ip, 1, objv, "column width height"); return TCL_ERROR;}
    int nx, ny;
    if (Tcl_GetIntFromObj(ip, objv[2], &nx) != TCL_OK ||
        Tcl_GetIntFromObj(ip, objv[3], &ny) != TCL_OK) return TCL_ERROR;
    if (nx < 1 || nx > 128 || ny < 1 || ny > 128)
        return fail(ip, "Array Preview plane dimensions must be in 1..128");
    Tcl_Obj *dtype = nullptr;
    if (column_field(ip, objv[1], "dtype", &dtype) != TCL_OK) return TCL_ERROR;
    const char *types[] = {"bool", "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64", "float16", "float32", "float64"};
    bool admitted = false;
    if (dtype) for (const char *type : types) admitted |= std::strcmp(type, Tcl_GetString(dtype)) == 0;
    if (!admitted) return fail(ip, "Array Preview requires a declared numeric dtype");
    numeric_column column;
    if (numeric_column_read(ip, objv[1], &column) != TCL_OK) return TCL_ERROR;
    if (column.values && (column.kind == 5 || column.kind == 6)) {
        const char *bits = Tcl_GetString(dtype) + (column.kind == 5 ? 4 : 3);
        column.width = std::strcmp(bits, "8") == 0 ? 1 : std::strcmp(bits, "16") == 0 ? 2 : std::strcmp(bits, "32") == 0 ? 4 : 8;
    }
    if (column.count != static_cast<size_t>(nx * ny))
        return fail(ip, "Array Preview plane count does not match dimensions");
    try {
        std::vector<Sample> cells;
        cells.reserve(column.count);
        Sample lo, hi;
        size_t finite = 0;
        const bool integer = column.kind == 5 || column.kind == 6;
        for (size_t i = 0; i < column.count; ++i) {
            Sample s = sample(column, i);
            cells.push_back(s);
            if (!s.finite) continue;
            if (!finite || (integer ? s.key < lo.key : s.value < lo.value)) lo = s;
            if (!finite || (integer ? s.key > hi.key : s.value > hi.value)) hi = s;
            ++finite;
        }
        if (!finite) return fail(ip, "Array plane has no finite values.");
        int scale = std::max(1, std::min({8, 640 / nx, 420 / ny}));
        int width = nx * scale, height = ny * scale;
        std::string ppm = "P6\n" + std::to_string(width) + " " + std::to_string(height) + "\n255\n";
        ppm.reserve(ppm.size() + static_cast<size_t>(width * height * 3));
        for (int y = 0; y < ny; ++y) {
            std::string row;
            row.reserve(static_cast<size_t>(width * 3));
            for (int x = 0; x < nx; ++x) {
                const Sample &s = cells[static_cast<size_t>(y * nx + x)];
                unsigned char color[3] = {184, 184, 184};
                if (s.finite) {
                    double t = .5;
                    if (integer && hi.key != lo.key)
                        t = static_cast<double>(s.key - lo.key) / static_cast<double>(hi.key - lo.key);
                    else if (!integer && hi.value != lo.value) {
                        // Match the established palette for ordinary ranges;
                        // scale huge opposing finite endpoints to avoid overflow.
                        double span = hi.value - lo.value;
                        t = std::isfinite(span) ? (s.value - lo.value) / span
                            : (s.value / 2 - lo.value / 2) / (hi.value / 2 - lo.value / 2);
                    }
                    t = std::max(0., std::min(1., t));
                    color[0] = static_cast<unsigned char>(255 * t);
                    color[1] = static_cast<unsigned char>(180 * (1 - std::abs(2 * t - 1)));
                    color[2] = static_cast<unsigned char>(255 * (1 - t));
                }
                for (int i = 0; i < scale; ++i)
                    row.append(reinterpret_cast<const char *>(color), 3);
            }
            for (int i = 0; i < scale; ++i) ppm += row;
        }
        Tcl_Obj *result = Tcl_NewDictObj();
        field(result, "ppm", Tcl_NewByteArrayObj(reinterpret_cast<const unsigned char *>(ppm.data()), static_cast<int>(ppm.size())));
        field(result, "minimum", label(lo, column.kind));
        field(result, "maximum", label(hi, column.kind));
        field(result, "finite_count", Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(finite)));
        field(result, "width", Tcl_NewIntObj(width));
        field(result, "height", Tcl_NewIntObj(height));
        Tcl_SetObjResult(ip, result);
        return TCL_OK;
    } catch (const std::exception &) { return fail(ip, "Array Preview plane allocation failed"); }
}
} // namespace
extern "C" int gx2d_preview_plane_v1_init(Tcl_Interp *ip) {
    if (!Tcl_FindNamespace(ip, "::gx::native2d", nullptr, 0) &&
        !Tcl_CreateNamespace(ip, "::gx::native2d", nullptr, nullptr)) return TCL_ERROR;
    Tcl_CreateObjCommand(ip, "::gx::native2d::_preview_plane", prepare, nullptr, nullptr);
    return TCL_OK;
}
