# GX-TXT Analysis Source runtime access extension for Canonical Dataset API v2
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX {
    variable analysisSourceAccessApiVersion 2
}

proc ::GX::writeStandardRuntimeConfig_before_table_stream_v3 {moduleId} {
    variable currentSession
    set path [::GX::writeStandardRuntimeConfig_before_dataset_access_v2 $moduleId]
    if {$currentSession eq "" || ![file isdirectory $currentSession] || ![file isfile $path]} { return $path }
    set runtime [parseIni $path]
    if {![dict exists $runtime analysis_sources.ids]} { return $path }
    set fd [open $path a]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
      puts $fd "\n\[analysis_source_access_api\]"
      putKV $fd api_version $::GX::analysisSourceAccessApiVersion
      foreach sourceId [splitList [dict get $runtime analysis_sources.ids]] {
        set key "analysis_source.$sourceId.dataset_id"
        if {![dict exists $runtime $key]} continue
        set datasetId [string trim [dict get $runtime $key]]
        if {$datasetId eq ""} continue
        set handle ""
        try {
            set handle [datasetAccessOpen $currentSession $datasetId]
            set metadata [datasetAccessMetadata $handle]
            puts $fd "\n\[analysis_source.$sourceId\]"
            putKV $fd access_api_version 2
            putKV $fd storage_provider [dict get $metadata storage_provider]
            putKV $fd capabilities [join [datasetAccessTrueCapabilities $handle] ";"]
            putKV $fd row_count [dict get $metadata row_count]
            putKV $fd sample_count [dict get $metadata sample_count]
            set index 0
            foreach variable [dict get $metadata variables] {
                incr index
                puts $fd "\n\[analysis_source.$sourceId.variable.$index\]"
                foreach field {dtype rank shape dimension_ids coordinate_variable_ids coordinate_role axis_kind axis_origin axis_step axis_count component_ids group_id} {
                    putKV $fd $field [dict get $variable $field]
                }
            }
        } finally {
            if {$handle ne ""} { datasetAccessClose $handle }
        }
      }
    } finally {
      close $fd
    }
    return $path
}
