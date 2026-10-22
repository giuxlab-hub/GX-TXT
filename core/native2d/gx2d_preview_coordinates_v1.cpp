/* SPDX-License-Identifier: GPL-3.0-or-later
 * Bounded presentation of existing samples using owner-issued affine plans.
 * No unit/calibration interpretation, source access or scientific publication.
 */
#include "gx2d_preview_coordinates_v1.h"
#include <tcl.h>
#include <tclTomMath.h>
#include <array>
#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <string>

namespace {
struct Object {
    Tcl_Obj *p;
    explicit Object(Tcl_Obj *value) : p(value) { Tcl_IncrRefCount(p); }
    ~Object() { Tcl_DecrRefCount(p); }
    Object(const Object &) = delete;
    Object &operator=(const Object &) = delete;
};
double finite(Tcl_Interp *ip, Tcl_Obj *value) {
    // The owner admits exact integer coordinates, including exact large powers
    // of two, but rejects rounded integers. Reuse Tcl's integer parser and its
    // canonical bignum representation; decimal %.0f is the exact integral value
    // represented by this finite binary64, not a scientific-notation shortcut.
    std::string integral; mp_int integer;
    if (Tcl_GetBignumFromObj(nullptr, value, &integer) == TCL_OK) {
        Object canonical(Tcl_NewBignumObj(&integer)); // owns the copied bignum
        integral = Tcl_GetString(canonical.p);
    }
    double number;
    if (Tcl_GetDoubleFromObj(ip, value, &number) != TCL_OK || !std::isfinite(number))
        throw std::runtime_error("Unit conversion requires finite real binary64 values");
    if (!integral.empty()) {
        std::array<char, 512> exact{};
        const int length = std::snprintf(exact.data(), exact.size(), "%.0f", number == 0 ? 0.0 : number);
        if (length < 0 || static_cast<std::size_t>(length) >= exact.size() ||
            integral != exact.data())
            throw std::runtime_error("Integer coordinate cannot be represented exactly as binary64");
    }
    return number;
}
Tcl_Obj *field(Tcl_Interp *ip, Tcl_Obj *dictionary, const char *name) {
    Object key(Tcl_NewStringObj(name, -1)); Tcl_Obj *value = nullptr;
    if (Tcl_DictObjGet(ip, dictionary, key.p, &value) != TCL_OK || !value)
        throw std::runtime_error(std::string("Coordinate affine plan requires ") + name);
    return value;
}
struct Plan { double scale; };
Plan plan(Tcl_Interp *ip, Tcl_Obj *value) {
    if (std::string(Tcl_GetString(field(ip, value, "coordinate_mode"))) != "canonical" ||
        std::string(Tcl_GetString(field(ip, value, "direction"))) != "forward")
        throw std::runtime_error("Coordinate display requires forward canonical owner plans");
    int affine;
    if (Tcl_GetBooleanFromObj(ip, field(ip, value, "affine"), &affine) != TCL_OK || !affine)
        throw std::runtime_error("Coordinate preparation requires an affine owner plan");
    Plan result{finite(ip, field(ip, value, "scale"))};
    if (finite(ip, field(ip, value, "offset")) != 0)
        throw std::runtime_error("Coordinate preparation requires identity or a single owner scale");
    if (result.scale == 0) throw std::runtime_error("Coordinate affine plan collapses its dimension");
    return result;
}
double convert(double value, const Plan &p) {
    if (p.scale == 1) return value;
    // Exactly the admitted owner's single binary64 multiplication; no fused
    // affine algebra or added zero that could change rounding/signed zero.
    volatile double product = value * p.scale;
    if (!std::isfinite(product))
        throw std::runtime_error("Unit conversion requires finite real binary64 values");
    return product;
}
int command(ClientData, Tcl_Interp *ip, int argc, Tcl_Obj *const argv[]) {
    try {
        if (argc != 4) throw std::runtime_error("Expected bounded points and two coordinate affine plans");
        const Plan x = plan(ip, argv[2]), y = plan(ip, argv[3]);
        int count; Tcl_Obj **points;
        if (Tcl_ListObjGetElements(ip, argv[1], &count, &points) != TCL_OK)
            throw std::runtime_error(Tcl_GetStringResult(ip));
        if (count > 4096) throw std::runtime_error("Scientific coordinate display is bounded to4096 points per trace");
        Object result(Tcl_NewListObj(0, nullptr));
        std::array<double, 4> bounds{};
        for (int i = 0; i < count; ++i) {
            int size; Tcl_Obj **xy;
            if (Tcl_ListObjGetElements(ip, points[i], &size, &xy) != TCL_OK || size != 2)
                throw std::runtime_error("Coordinate display requires XY pairs");
            const double a = finite(ip, xy[0]), b = finite(ip, xy[1]);
            if (!i) bounds = {a, b, a, b};
            else {
                if (a < bounds[0]) bounds[0] = a;
                if (b < bounds[1]) bounds[1] = b;
                if (a > bounds[2]) bounds[2] = a;
                if (b > bounds[3]) bounds[3] = b;
            }
            const double shownX = convert(a, x), shownY = convert(b, y);
            Tcl_Obj *pair[] = {Tcl_NewDoubleObj(shownX), Tcl_NewDoubleObj(shownY)};
            Tcl_ListObjAppendElement(ip, result.p, Tcl_NewListObj(2, pair));
        }
        Object envelope(Tcl_NewDictObj()), inputBounds(Tcl_NewListObj(0, nullptr));
        if (count) for (double value : bounds)
            Tcl_ListObjAppendElement(ip, inputBounds.p, Tcl_NewDoubleObj(value));
        Object pointsKey(Tcl_NewStringObj("points", -1)), boundsKey(Tcl_NewStringObj("input_bounds", -1));
        Tcl_DictObjPut(ip, envelope.p, pointsKey.p, result.p);
        Tcl_DictObjPut(ip, envelope.p, boundsKey.p, inputBounds.p);
        Tcl_SetObjResult(ip, envelope.p); return TCL_OK;
    } catch (const std::exception &error) {
        Tcl_SetObjResult(ip, Tcl_NewStringObj(error.what(), -1)); return TCL_ERROR;
    }
}
}
extern "C" int gx2d_preview_coordinates_v1_init(Tcl_Interp *ip) {
    if (!Tcl_FindNamespace(ip, "::gx::native2d", nullptr, 0) &&
        !Tcl_CreateNamespace(ip, "::gx::native2d", nullptr, nullptr)) return TCL_ERROR;
    Tcl_CreateObjCommand(ip, "::gx::native2d::_preview_coordinates", command, nullptr, nullptr);
    return TCL_OK;
}
extern "C" int Gxtxtcoordinates_Init(Tcl_Interp *ip) {
    if (!Tcl_InitStubs(ip, "8.6", 0)) return TCL_ERROR;
    return gx2d_preview_coordinates_v1_init(ip);
}
