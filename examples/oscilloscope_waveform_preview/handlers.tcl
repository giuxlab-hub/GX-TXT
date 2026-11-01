# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only Preview consumer. Numeric values/reduction/render/cache stay in CORE.
namespace eval ::GX::Generated_preview_oscilloscope_waveform::Handlers {variable mounts {}}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::axes {context} {
    set times {};set signals {}
    foreach variable [dict get $context variables] {
        if {![dict get $variable enabled] || [dict get $variable rank]!=1} continue
        if {[dict get $variable semantic_role] eq {time}} {lappend times $variable}
        if {[dict get $variable semantic_role] eq {signal}} {lappend signals $variable}
    }
    if {[llength $times]!=1 || [llength $signals]!=1} {error {This recording requires one unambiguous time and signal Variable per channel}}
    return [list [lindex $times 0] [lindex $signals 0]]
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::initialize {host event} {
    variable mounts
    set context [::GX::datasetPreviewGuiContext $host]
    lassign [axes $context] x y
    set id [dict get $context dataset_id];set session [dict get $context session]
    set metadata [dict get $context metadata];set contributors [dict get $context contributors]
    set items [list "Dataset: $id" "Contract: [dict get $context contract]" "Source module: [dict get $context source_module]" "Time: [dict get $x display_label] \[[dict get $x unit]\] / [dict get $x variable_id]" "Signal: [dict get $y display_label] \[[dict get $y unit]\] / [dict get $y variable_id]"]
    # Show only actual registered acquisition facts, with contributor qualification.
    foreach {key title} {oscilloscope.source_channel Channel oscilloscope.sample_count Samples oscilloscope.tStart_s {Source start [s]} oscilloscope.dt_s {Source interval [s]} oscilloscope.sample_rate_Sa_s {Sample rate [Sa/s]} oscilloscope.duration_s {Source duration [s]} oscilloscope.sequence_errors {Source sequence errors} instrument.manufacturer Manufacturer instrument.model Model} {
        if {![dict exists $metadata $key]} continue
        set qualification {registered; contributor not verified}
        if {[dict exists $contributors $key verified] && [dict get $contributors $key verified]} {set qualification [dict get $contributors $key last_contributor]}
        lappend items "$title: [dict get $metadata $key] ($qualification)"
    }
    set representation [dict get $context representation]
    foreach {key title} {row_count {Prepared source rows} displayed_points {Bounded display points}} {
        if {[dict exists $representation $key]} {lappend items "$title: [dict get $representation $key]"}
    }
    ::GX::datasetPreviewGuiControlSet $host metadata $items
    set channels [list $id];set labels [list "[::GX::datasetPublicationV2DictDefault $metadata oscilloscope.source_channel Signal] — $id"]
    set groupId [::GX::datasetGroupForDataset $session $id];set revision {}
    if {$groupId ne {}} {
        set group [::GX::datasetGroupGet $session $groupId];set revision [dict get $group revision]
        set channels {};set labels {}
        foreach member [dict get $group members] {
            set target [dict get $member dataset_id]
            if {[catch {set data [::GX::sessionInspectionDataset $target]}]} continue
            if {[dict get $data contract] ne {timeseries.table} || [::GX::datasetPublicationV2DictDefault $data source_module {}] ne [dict get $context source_module]} continue
            set values [::GX::datasetMetadataRead $session $target]
            lappend channels $target
            lappend labels "[::GX::datasetPublicationV2DictDefault $values oscilloscope.source_channel Signal] — $target"
        }
        lappend items "Recording Group: [dict get $group display_name] / [dict get $group status] / revision $revision"
        ::GX::datasetPreviewGuiControlSet $host metadata $items
    }
    ::GX::datasetPreviewGuiControlSet $host channels $labels
    dict set mounts $host [dict create token [dict get $context token] dataset_id $id group_id $groupId revision $revision channels $channels]
    if {[dict exists $metadata oscilloscope.sample_count] && [string is entier -strict [dict get $metadata oscilloscope.sample_count]] && [dict get $metadata oscilloscope.sample_count]>0} {
        ::GX::datasetPreviewGuiControlSet $host row_count [expr {min(10000,[dict get $metadata oscilloscope.sample_count])}]
    }
    if {[dict exists $metadata oscilloscope.tStart_s]} {::GX::datasetPreviewGuiControlSet $host time_min [dict get $metadata oscilloscope.tStart_s]}
    if {[dict exists $metadata oscilloscope.tStart_s] && [dict exists $metadata oscilloscope.duration_s]} {
        ::GX::datasetPreviewGuiControlSet $host time_max [expr {double([dict get $metadata oscilloscope.tStart_s])+double([dict get $metadata oscilloscope.duration_s])}]
    }
    if {[dict exists $representation source_window]} {
        set window [dict get $representation source_window]
        foreach {source control} {start row_start count row_count time_min time_min time_max time_max} {
            if {[dict exists $window $source]} {::GX::datasetPreviewGuiControlSet $host $control [dict get $window $source]}
        }
    }
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::select_channel {host event} {
    variable mounts
    set context [::GX::datasetPreviewGuiContext $host]
    if {![dict exists $mounts $host]} {initialize $host $event}
    set state [dict get $mounts $host]
    if {[dict get $state group_id] ne {}} {
        set group [::GX::datasetGroupGet [dict get $context session] [dict get $state group_id]]
        if {[dict get $group revision] ne [dict get $state revision]} {error {Recording membership changed. Refresh recording details before selecting another channel.}}
    }
    set selection [dict get [::GX::datasetPreviewGuiControlGet $host channels] selection]
    if {[llength $selection]!=1} return
    set target [lindex [dict get $state channels] [lindex $selection 0]]
    if {$target ne [dict get $context dataset_id]} {::GX::datasetPreviewGuiSelectDataset $host $target}
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::request {host mode} {
    set context [::GX::datasetPreviewGuiContext $host]
    lassign [axes $context] x y
    return [dict create mode $mode x_variable_id [dict get $x variable_id] y_variable_id [dict get $y variable_id]]
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::full {host event} {
    ::GX::datasetPreviewGuiSourceRequest $host [request $host full]
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::apply_rows {host event} {
    set value [request $host rows]
    dict set value start [::GX::datasetPreviewGuiControlGet $host row_start]
    dict set value count [::GX::datasetPreviewGuiControlGet $host row_count]
    ::GX::datasetPreviewGuiSourceRequest $host $value
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::apply_time {host event} {
    set value [request $host time]
    dict set value time_min [::GX::datasetPreviewGuiControlGet $host time_min]
    dict set value time_max [::GX::datasetPreviewGuiControlGet $host time_max]
    ::GX::datasetPreviewGuiSourceRequest $host $value
}
proc ::GX::Generated_preview_oscilloscope_waveform::Handlers::dispose {context reason} {
    variable mounts
    dict for {host state} $mounts {
        if {[dict get $state token] eq [dict get $context token] && [dict get $state dataset_id] eq [dict get $context dataset_id]} {dict unset mounts $host}
    }
}
