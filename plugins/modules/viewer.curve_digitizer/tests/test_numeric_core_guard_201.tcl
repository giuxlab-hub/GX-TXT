# SPDX-License-Identifier: GPL-3.0-or-later
# CORE unavailability must never produce independently propagated sigmas.
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerCompanion {}
proc ::GX::modulePublicApiActivate {args} {error {Numeric/CORE is unavailable}}
source [file join [file dirname [info script]] .. api curve_digitizer_numeric_core.tcl]
source [file join [file dirname [info script]] .. api curve_digitizer_core_consumers.tcl]
set failed [catch {::GX::CurveDigitizerNumericCore::propagate document {} measurement {} image sha {}} msg]
if {!$failed || ![string match {*unavailable*} $msg]} {error {Numerical service missing but propagation did not fail closed}}
# The public CORE fit-plan owner, not GUI logic, is the final admissibility gate.
proc ::GX::CurveDigitizerCompanion::publicationUncertainty {dataset} {
    return [dict create meaning [dict create summary [dict create point_count 2] columns [dict create sigma_y [dict create unit V]]] \
        binding {} source_identity {}]
}
namespace eval ::GX::StatisticsV1 {}
proc ::GX::StatisticsV1::digitizationFitPlan {meaning kind orientation} {
    return [dict create status unavailable reason {Within-point correlation or incompatible fit plan}]
}
set rejected [catch {::GX::CurveDigitizerCompanion::publishCovariance dataset result y} reason]
if {!$rejected || ![string match {*disallows full covariance*} $reason]} {
    error "Illegal Fitter covariance plan was not rejected: $reason"
}
puts {PASS: missing Numeric fails closed and CORE fit-plan rejection is authoritative}
