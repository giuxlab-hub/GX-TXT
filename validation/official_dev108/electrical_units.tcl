# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set out [file normalize $out]
if {![string match */_private_dev108/electrical-units* $out] || [file exists $out]} {error {Fresh private units output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev108_electrical_units_contract__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::createNewSession electrical_units
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
proc receipt {name value} {set f [open [file join $::out $name.tcldict] w];try {puts $f $value} finally {close $f}}
set plans {}
foreach {a b} {F A*s/V H V*s/A Ohm*F s H/Ohm s uF nF mH H V mV} {
    check {[::GX::unitTclCompatible $a $b]} "Public unit dimension mismatch $a / $b"
    dict set plans $a [::GX::unitRegistryConversionPlan $a $b]
}
check {![::GX::unitTclCompatible F H]} {Capacitance and inductance conflated}
check {![::GX::unitTclCompatible dB V]} {Semantic unit falsely linearized}
check {[::GX::unitTclCompatible dB dB]} {Legacy semantic identity lost}
foreach unit {pF nF uF mF F nH uH mH H} {check {$unit in [::GX::unitSelectorCandidates]} "Unit selector missing $unit"}
receipt tcl_units $plans
proc textNode {value} {::GX::ScientificTransportv1::text $value}
proc scalar {value} {dict create kind scalar value $value}
proc structure {fields} {dict create kind struct fields $fields}
set units [structure [dict create R [textNode Ohm] C [textNode uF] L [textNode mH]]]
set symbols [structure [dict create R [::GX::ScientificTransportv1::array {1 1} {1000}] C [::GX::ScientificTransportv1::array {1 1} {1}] L [::GX::ScientificTransportv1::array {1 1} {1}]]]
set results {}
foreach {expression expected} {R*C .001 L/R .000001} {
    set result [::GX::NumericAPIv1::callOperation expression_evaluate [list [textNode $expression] $symbols $units] [structure [dict create output_unit [textNode s]]]]
    set error [dict get [::GX::NumericAPIv1::arrayBinary subtract [scalar [dict get $result values]] [scalar $expected]] values]
    set absolute [dict get [::GX::NumericAPIv1::arrayUnary abs [scalar $error]] values]
    check {[dict get [::GX::NumericAPIv1::arrayCompare less_equal [scalar $absolute] [scalar 1e-15]] values] eq {1}} {Public Numeric unit-scaled result failed}
    dict set results $expression $result
}
check {[catch {::GX::NumericAPIv1::callOperation expression_evaluate [list [textNode {C+L}] $symbols $units]} rejected]} {Numeric added incompatible capacitance and inductance}
receipt numeric_results $results
receipt incompatible_expression_rejected $rejected
receipt installed_services [::GX::scientificExecutionCoreCapabilities]
receipt result [dict create result PASS APIs {UNIT_REGISTRY_API_v1 UNIT_DIMENSION_API_v1 NUMERIC_API_v1} scope {Tcl/actual Octave expression, existing prefixes, dimensions, selectors, semantic identity and incompatibility}]
puts {PASS public electrical units and Numeric expressions}
