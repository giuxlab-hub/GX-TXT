# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {}
proc ::GX::viewerBackendRegister {args} {}
proc ::GX::modulePublicApiActivate {module api} {return 1}
namespace eval ::GX::NumericAPIv1 {}
proc ::GX::NumericAPIv1::interpolate {t values queries options} {
    set out {}
    foreach q $queries {lappend out [expr {[lindex $values 0]+$q} ]}
    return [dict create yq $out]
}
source [file join [file dirname [info script]] .. api curve_digitizer_viewer_api_v1.tcl]
set x [::GX::CurveDigitizer::_assistNumericFit {0 10 20} {1 11 21} {2 12 22} {0 5 10 15 20}]
if {$x eq {} || [string index $x 0] ne {[} || [string index $x end] ne {]}} {error "Invalid numeric response: $x"}
rename ::GX::NumericAPIv1::interpolate {}
if {[::GX::CurveDigitizer::_assistNumericFit {0 10 20} {1 11 21} {2 12 22} {0 5 10 15 20}] ne {}} {error {Expected explicit fallback}}
puts {PASS optional CORE numeric fit}
