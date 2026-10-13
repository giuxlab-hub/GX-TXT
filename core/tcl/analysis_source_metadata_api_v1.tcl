# GX-TXT Analysis Source Metadata Runtime Extension v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Additive metadata bridge: Dataset Registry -> Standard Module runtime.

namespace eval ::GX {
    variable analysisSourceMetadataApiVersion 1
}

proc ::GX::analysisSourceDatasetVariables_v1_before_schema {datasetId} {
    set rawVars [datasetField $datasetId variables ""]
    if {$rawVars eq ""} { set rawVars [datasetField $datasetId columns ""] }
    set vars [splitList $rawVars]
    set rawUnits [string map {"," ";"} [datasetField $datasetId units ""]]
    set rawRoles [string map {"," ";"} [datasetField $datasetId semantic_roles ""]]
    set units [expr {$rawUnits eq "" ? {} : [split $rawUnits ";"]}]
    set roles [expr {$rawRoles eq "" ? {} : [split $rawRoles ";"]}]
    set out {}
    set n [llength $vars]
    for {set i 0} {$i < $n} {incr i} {
        set name [lindex $vars $i]
        set unit [expr {$i < [llength $units] ? [lindex $units $i] : ""}]
        set role [expr {$i < [llength $roles] ? [lindex $roles $i] : ""}]
        set original ""
        set sourceColumn ""
        set count [datasetField $datasetId var_count 0]
        if {[string is integer -strict $count] && $count > 0} {
            for {set j 1} {$j <= $count} {incr j} {
                set canonical [string trim [datasetField $datasetId var${j}_canonical ""]]
                if {$canonical ne $name} continue
                set q [datasetField $datasetId var${j}_unit ""]; if {[string trim $q] ne ""} { set unit $q }
                set q [datasetField $datasetId var${j}_semantic_role ""]; if {[string trim $q] ne ""} { set role $q }
                set original [datasetField $datasetId var${j}_original_header ""]
                set sourceColumn [datasetField $datasetId var${j}_source_column ""]
                break
            }
        }
        lappend out [dict create name $name unit $unit semantic_role $role original_header $original source_column $sourceColumn]
    }
    return $out
}

# This wrapper intentionally runs after Analysis Source Map API v1 has written
# the source IDs/dataset IDs. It does not change the path-only Octave source_map
# contract; it enriches runtime.ini for modules/renderers that need metadata.
proc ::GX::analysisSourceDatasetVariables {datasetId} {
    tailcall ::GX::analysisSourceDatasetVariables_v1_before_schema $datasetId
}
proc ::GX::writeStandardRuntimeConfig_v090_before_plot_region {id} {
    variable currentSession
    set path [::GX::writeStandardRuntimeConfig_v090_before_source_metadata $id]
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return $path }
    set d [parseIni $path]
    if {![dict exists $d analysis_sources.ids]} { return $path }
    loadDatasetRegistry $currentSession
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[analysis_source_metadata_api\]"
    putKV $fd api_version $::GX::analysisSourceMetadataApiVersion
    foreach sourceId [splitList [dict get $d analysis_sources.ids]] {
        set key "analysis_source.$sourceId.dataset_id"
        if {![dict exists $d $key]} continue
        set datasetId [string trim [dict get $d $key]]
        if {$datasetId eq ""} continue
        set meta [analysisSourceDatasetVariables $datasetId]
        set vars {}; set units {}; set roles {}
        foreach v $meta {
            lappend vars [dict get $v name]
            lappend units [dict get $v unit]
            lappend roles [dict get $v semantic_role]
        }
        puts $fd "\n\[analysis_source.$sourceId\]"
        putKV $fd contract [datasetField $datasetId kind ""]
        putKV $fd format [datasetField $datasetId format ""]
        putKV $fd storage_kind [datasetField $datasetId storage_kind "text"]
        putKV $fd media_type [datasetField $datasetId media_type ""]
        putKV $fd variables [join $vars ";"]
        putKV $fd units [join $units ";"]
        putKV $fd semantic_roles [join $roles ";"]
        putKV $fd variable_count [llength $meta]
        set i 0
        foreach v $meta {
            incr i
            puts $fd "\n\[analysis_source.$sourceId.variable.$i\]"
            foreach field {name variable_id unit semantic_role semantic_source semantic_reason original_header source_column value_kind value_format decimal_separator time_reference time_origin} { putKV $fd $field [dict get $v $field] }
        }
    }
    close $fd
    return $path
}
