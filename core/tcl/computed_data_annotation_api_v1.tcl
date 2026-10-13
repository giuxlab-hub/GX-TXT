# GX-TXT Computed Data Annotation API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative module-produced annotations anchored to canonical dataset coordinates.

namespace eval ::GX { variable computedDataAnnotationApiVersion 1 }

proc ::GX::computedDataAnnotationSafeRelPath {rel} {
    set rel [string trim $rel]
    if {$rel eq ""} { error "Computed annotation sidecar path is empty." }
    if {[file pathtype $rel] eq "absolute"} { error "Computed annotation sidecar path must be module-output-relative." }
    foreach p [file split $rel] { if {$p eq ".."} { error "Computed annotation sidecar path may not contain '..'." } }
    return $rel
}

proc ::GX::computedDataAnnotationValidateFile {path {expectedDatasetId ""}} {
    if {![file isfile $path]} { error "Computed annotation sidecar does not exist: $path" }
    set d [parseIni $path]
    if {![dict exists $d annotations.api_version] || [string trim [dict get $d annotations.api_version]] ne "1"} {
        error "Computed annotation sidecar must declare \[annotations\] api_version=1: $path"
    }
    set ds [expr {[dict exists $d annotations.dataset_id] ? [string trim [dict get $d annotations.dataset_id]] : ""}]
    if {$ds eq ""} { error "Computed annotation sidecar is missing annotations.dataset_id: $path" }
    if {$expectedDatasetId ne "" && $ds ne $expectedDatasetId} {
        error "Computed annotation sidecar dataset_id '$ds' does not match published dataset '$expectedDatasetId'."
    }
    set n [expr {[dict exists $d annotations.count] ? [dict get $d annotations.count] : 0}]
    if {![string is integer -strict $n] || $n < 0} { error "Computed annotation count must be a non-negative integer: $path" }
    set ids {}
    for {set i 1} {$i <= $n} {incr i} {
        set p "annotation.$i"
        foreach key {id type} {
            if {![dict exists $d $p.$key] || [string trim [dict get $d $p.$key]] eq ""} { error "$p is missing '$key'." }
        }
        set aid [string trim [dict get $d $p.id]]
        if {[lsearch -exact $ids $aid] >= 0} { error "Duplicate computed annotation id '$aid'." }
        lappend ids $aid
        set t [string tolower [string trim [dict get $d $p.type]]]
        if {[lsearch -exact {vline hline point text} $t] < 0} { error "$p has unsupported type '$t'." }
        if {$t in {vline point text}} {
            foreach k {x x_variable x_unit} { if {![dict exists $d $p.$k] || [string trim [dict get $d $p.$k]] eq ""} { error "$p ($t) is missing '$k'." } }
            if {![string is double -strict [string trim [dict get $d $p.x]]]} { error "$p x must be numeric." }
        }
        if {$t in {hline point text}} {
            foreach k {y y_variable y_unit} { if {![dict exists $d $p.$k] || [string trim [dict get $d $p.$k]] eq ""} { error "$p ($t) is missing '$k'." } }
            if {![string is double -strict [string trim [dict get $d $p.y]]]} { error "$p y must be numeric." }
        }
    }
    return $d
}

# Runtime bridge: dataset registry -> consumer module runtime.
# It is deliberately source-oriented so any Graph Provider can consume it.
proc ::GX::writeStandardRuntimeConfig_before_schema_v2 {id} {
    variable currentSession
    set path [::GX::writeStandardRuntimeConfig_v0941_before_computed_annotations $id]
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return $path }
    set r [parseIni $path]
    if {![dict exists $r analysis_sources.ids]} { return $path }
    loadDatasetRegistry $currentSession
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[computed_data_annotation_api\]"; putKV $fd api_version $::GX::computedDataAnnotationApiVersion
    foreach sourceId [splitList [dict get $r analysis_sources.ids]] {
        set dk "analysis_source.$sourceId.dataset_id"
        if {![dict exists $r $dk]} continue
        set ds [string trim [dict get $r $dk]]; if {$ds eq ""} continue
        set rel [string trim [datasetField $ds computed_annotations_file ""]]
        if {$rel eq ""} continue
        set abs [file normalize [file join $currentSession $rel]]
        puts $fd "\n\[analysis_source.$sourceId.computed_annotations\]"
        putKV $fd api_version 1; putKV $fd dataset_id $ds; putKV $fd file $abs
    }
    close $fd
    return $path
}
