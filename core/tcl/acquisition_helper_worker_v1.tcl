# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted master only. Never source this file into the authored interpreter.
namespace eval ::GX::AcquisitionHelper {}
proc ::GX::AcquisitionHelper::validateNode {node {depth 0}} {
    if {$depth > 24 || [llength $node] != 2} {error {Helper requires bounded typed JSON nodes}}
    lassign $node kind value
    switch -- $kind {
        null - bool - int - real - text {}
        array {foreach child $value {validateNode $child [expr {$depth+1}]}}
        object {dict for {key child} $value {validateNode $child [expr {$depth+1}]}}
        default {error {Helper accepts JSON metadata only; resource nodes are unavailable}}
    }
    return $node
}
proc ::GX::AcquisitionHelper::decode {json} {
    if {[string bytelength $json] > 196608} {error {Helper JSON exceeds 192 KiB}}
    return [validateNode [::GX::nativeWorkspaceJsonDecode $json]]
}
proc ::GX::AcquisitionHelper::encode {node} {
    set json [::GX::nativeWorkspaceJsonEncode [validateNode $node]]
    if {[string bytelength $json] > 196608} {error {Helper JSON exceeds 192 KiB}}
    return $json
}
proc ::GX::AcquisitionHelper::prepare {} {
    set child [interp create -safe]
    # Hidden originals remain callable only by this trusted master. In
    # particular authored code cannot impersonate the info/proc ownership check.
    set commands [interp eval $child {info commands}]
    foreach name {interp after vwait update rename info package chan close read gets
                  seek tell flush fcopy fileevent puts pid clock} {
        if {$name in $commands} {
            interp hide $child $name
        }
    }
    interp alias $child json_decode {} ::GX::AcquisitionHelper::decode
    interp alias $child json_encode {} ::GX::AcquisitionHelper::encode
    interp alias $child puts {} ::GX::AcquisitionHelper::diagnostic
    interp recursionlimit $child 64
    return $child
}
proc ::GX::AcquisitionHelper::invoke {child source entrypoint json} {
    set deadline [expr {[clock milliseconds]+1500}]
    interp limit $child time -seconds [expr {$deadline/1000}] -milliseconds [expr {$deadline%1000}] -granularity 1
    interp limit $child command -value 100000 -granularity 1
    interp eval $child $source
    set name ::[string trimleft $entrypoint :]
    if {[interp invokehidden $child info procs $name] ne $name ||
        [llength [interp invokehidden $child info args $name]] != 1 ||
        [interp invokehidden $child info args $name] eq {args}} {
        error {Registered helper must be an authored one-argument Tcl proc}
    }
    set argument [decode $json]
    set result [interp eval $child [list $name $argument]]
    return [encode $result]
}
