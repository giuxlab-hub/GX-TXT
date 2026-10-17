# SPDX-License-Identifier: GPL-3.0-or-later
# Hermetic Tcl test. No CORE/Octave invocation; host-level acceptance is separate.
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerNumericCore {}
source [file join [file dirname [info script]] .. api curve_digitizer_factor_guard.tcl]
proc insist {condition message} {if {!$condition} {error $message}}
insist [expr {[::GX::CurveDigitizerNumericCore::covarianceUnit V mA] eq "V*mA"}] {Atomic product unit}
insist [expr {[::GX::CurveDigitizerNumericCore::covarianceUnit {m/s} {mol/L}] eq "(m/s)*(mol/L)"}] {Grouped composite units}
insist [catch {::GX::CurveDigitizerNumericCore::covarianceUnit "" V}] {Missing units must fail}

set local {{0 0} {0 0} {0 0} {0 0}}
set shared {}
foreach v {0.3 0.1 0.4 0.2} {
    lappend shared [concat [list $v] [lrepeat 11 0.0]]
}
proc makeRecord {local shared} {
    set values {}
    foreach row $local {foreach v $row {lappend values $v}}
    foreach row $shared {foreach v $row {lappend values $v}}
    set wire [binary format q* $values]
    set payload [binary encode base64 -maxlen 0 [zlib compress $wire]]
    return [format {{"format":"zlib-base64-float64-le-v1","shape_local":[2,2,2],"shape_shared":[4,12],"payload":"%s"}} $payload]
}
set json [makeRecord $local $shared]
set original [dict create independent_factor $local shared_factor $shared]
insist [expr {[::GX::CurveDigitizerNumericCore::_checkPreflightFactors $json $original 2] eq "verified"}] {Matching factors should pass}

# Reverse BOTH X and Y shared loadings of point 2. This preserves point 2's
# X/Y marginal variances and within-point XY covariance, yet changes the
# cross-point covariance for points 1 and 2. It must still be rejected.
set tampered $shared
lset tampered 2 0 -0.4
lset tampered 3 0 -0.2
set mutated [dict replace $original shared_factor $tampered]
set failed [catch {::GX::CurveDigitizerNumericCore::_checkPreflightFactors $json $mutated 2} reason]
insist [expr {$failed && [string match {*shared component*} $reason]}] {Undetected cross-point divergence}
set zeros [lrepeat 4 [lrepeat 12 0.0]]
set emptyLocal [lrepeat 4 {0.0 0.0}]
insist [expr {[::GX::CurveDigitizerNumericCore::_checkPreflightFactors [makeRecord $emptyLocal $zeros] [dict create independent_factor $emptyLocal shared_factor $zeros] 2] eq "verified"}] {Exactly zero factors must be valid}
insist [catch {::GX::CurveDigitizerNumericCore::_checkPreflightFactors $json $original 3}] {Changed point count accepted}
puts {PASS: entire factors, unchanged marginals with changed cross covariance rejected, zero factors, unit schema notation}
