# Provider-owned SIGNAL_API_v1 Tcl binding.
# SPDX-License-Identifier: GPL-3.0-or-later
source [file normalize [file join [file dirname [info script]] .. .. .. .. core tcl scientific_provider_transport_v1.tcl]]
namespace eval ::GX::SignalAPIv1 {variable lastTypes [dict create]}
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
    return $ids
}
proc ::GX::SignalAPIv1::operationMetadata {id} {
    set path [file join [file dirname [::GX::moduleField math.signal descriptor ""]] api operations_v1.tsv]
    set fd [open $path r]
    try {while {[gets $fd line]>=0} {if {[lindex [split $line |] 0] eq $id} {set familyContract [_familyMetadata [lindex [split $id .] 0]]; return [dict merge [dict create id $id summary [lindex [split $line |] 1] api_id SIGNAL_API_v1 api_version 1] $familyContract [::GX::ScientificTransportv1::operationHelp signal $id $familyContract]]}}} finally {close $fd}
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
