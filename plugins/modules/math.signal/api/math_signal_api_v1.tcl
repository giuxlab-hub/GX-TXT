# Provider-owned SIGNAL_API_v1 Tcl binding.
# SPDX-License-Identifier: GPL-3.0-or-later
source [file normalize [file join [file dirname [info script]] .. .. .. .. core tcl scientific_provider_transport_v1.tcl]]
namespace eval ::GX::SignalAPIv1 {variable lastTypes [dict create]}
source [file join [file dirname [info script]] operation_schema_v1.tcl]
proc ::GX::SignalAPIv1::capabilities {} {
    set d [::GX::parseIni [::GX::moduleField math.signal descriptor ""]]
    return [::GX::splitList [::GX::descriptorValue $d public_api.SIGNAL_API_v1 capabilities ""]]
}
proc ::GX::SignalAPIv1::apiInfo {} {
    return [dict create api_id SIGNAL_API_v1 api_version 1 provider_id math.signal provider_version [::GX::moduleField math.signal version ""] capabilities [capabilities]]
}
proc ::GX::SignalAPIv1::listOperations {} {
    set path [file join [file dirname [::GX::moduleField math.signal descriptor ""]] api operations_v1.tsv]
    set fd [open $path r];set ids {}
    try {while {[gets $fd line]>=0} {if {$line eq "" || [string index $line 0] eq "#"} continue;lappend ids [lindex [split $line |] 0]}} finally {close $fd}
    lappend ids statistical_contract
    return $ids
}
proc ::GX::SignalAPIv1::operationMetadata {id} {
    if {$id eq "statistical_contract"} {return [dict create id $id api_id SIGNAL_API_v1 api_version 1 operation_kind metadata summary {Resolve the registered CORE statistical contract for a Signal operation} operands signal_operation input_shapes text result_shapes bounded_dictionary units {CORE-owned} complex_behavior {preserved by the selected estimator} errors {UnknownOperation}]}
    set path [file join [file dirname [::GX::moduleField math.signal descriptor ""]] api operations_v1.tsv]
    set fd [open $path r]
    try {while {[gets $fd line]>=0} {if {[lindex [split $line |] 0] eq $id} {set familyContract [_familyMetadata [lindex [split $id .] 0]]; return [dict merge [dict create id $id summary [lindex [split $line |] 1] api_id SIGNAL_API_v1 api_version 1] $familyContract [::GX::ScientificTransportv1::operationHelp signal $id $familyContract] [dict create operation_schema [operationSchema $id]] ]}}} finally {close $fd}
    return -code error -errorcode {GXTXT SCIENTIFIC UnknownOperation} "unknown operation $id"
}
proc ::GX::SignalAPIv1::_familyMetadata {family} {
    set path [file join [file dirname [::GX::moduleField math.signal descriptor ""]] api family_contracts_v1.tsv]
    set fd [open $path r]
    try {
        while {[gets $fd line] >= 0} {
            if {$line eq "" || [string index $line 0] eq "#"} continue
            set parts [split $line |]
            if {[llength $parts] != 7} {error "invalid scientific family contract"}
            if {[lindex $parts 0] eq $family} {
                return [dict create operands [lindex $parts 1] input_shapes [lindex $parts 2] result_shapes [lindex $parts 3] units [lindex $parts 4] complex_behavior [lindex $parts 5] errors [lindex $parts 6]]
            }
        }
    } finally {close $fd}
    error "missing scientific family contract: $family"
}
proc ::GX::SignalAPIv1::call {family action a b c {options {kind struct fields {}}}} {
    set id "$family.$action"
    if {[lsearch -exact [listOperations] $id]<0} {return -code error -errorcode {GXTXT SCIENTIFIC UnknownOperation} "unknown operation $id"}
    set raw [::GX::ScientificTransportv1::call math.signal gxtxt_signal_v1 $family $action $a $b $c $options]
    variable lastTypes;set lastTypes [dict get $raw types]
    return [dict get $raw values]
}
proc ::GX::SignalAPIv1::resultTypes {} {variable lastTypes;return $lastTypes}
proc ::GX::SignalAPIv1::callCaptured {document operation a b c context {options {kind struct fields {}}} {provenance {}}} {
    ::GX::interactiveDocumentRead $document
    set contract [statisticalContract $operation]
    set numeric [dict get $contract numerical_operation]
    set fields [dict keys [::GX::StatisticsV1::numericFieldMap $numeric]]
    lassign [split $operation .] family action
    return [::GX::ScientificTransportv1::withCapturedColumns math.signal gxtxt_signal_v1 $family $action $a $b $c $options $fields \
        [list ::GX::StatisticsV1::fromProviderColumns $document $numeric $context $provenance]]
}
proc ::GX::SignalAPIv1::statisticalContract {operation} {
    switch -- $operation {
        quality.basic {set numeric signal_summary}
        quality.snr {set numeric signal_snr}
        quality.spectrum - quality.harmonics {set numeric signal_spectrum_quality}
        correlation.auto - correlation.cross - correlation.delay {set numeric signal_correlation}
        events.period {set numeric event_period}
        time_metric.pulse {set numeric pulse_timing}
        spectral.window_metrics {set numeric window_metrics}
        spectral.periodogram - spectral.welch - spectral.asd - spectral.cross_psd - spectral.coherence - spectral.frf_h1 - spectral.frf_h2 {set numeric signal_[lindex [split $operation .] 1]}
        default {return -code error -errorcode {GXTXT SCIENTIFIC UnknownOperation} {Signal operation has no registered statistical-result contract}}
    }
    set model [::GX::StatisticsV1::numericModel $numeric]
    return [dict create api_version 1 signal_operation $operation numerical_api NUMERIC_API_v1 numerical_operation $numeric semantics_api STATISTICAL_RESULT_SEMANTICS_API_v1 model_id [dict get $model id] profile [dict get $model profile]]
}
proc ::GX::SignalAPIv1::interpretResult {operation raw context {provenance {}}} {
    set contract [statisticalContract $operation]
    return [::GX::StatisticsV1::fromNumeric [dict get $contract model_id] [dict get $contract numerical_operation] $raw $context {} $provenance]
}
