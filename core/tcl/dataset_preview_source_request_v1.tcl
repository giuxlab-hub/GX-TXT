# SPDX-License-Identifier: GPL-3.0-or-later
# Data-only requests to the existing Preview/Curve Source preparation owner.
proc ::GX::_datasetPreviewSourceRequestNormalize {id request} {
    if {[catch {dict size $request}] || [string bytelength $request]>4096} {error {Preview source request must be a bounded dictionary}}
    foreach key [dict keys $request] {if {$key ni {mode x_variable_id y_variable_id start count time_min time_max}} {error "Unknown Preview source request field '$key'"}}
    foreach key {mode x_variable_id y_variable_id} {if {![dict exists $request $key]} {error "Preview source request requires '$key'"}}
    set mode [dict get $request mode]
    if {$mode ni {full rows time}} {error {Preview source mode must be full, rows or time}}
    set x [dict get $request x_variable_id];set y [dict get $request y_variable_id]
    if {$x eq $y} {error {Preview source X/Y Variable IDs must be distinct}}
    foreach variable [list $x $y] {
        set schema [datasetVariableV3ById $id $variable]
        if {![dict get $schema enabled] || [dict get $schema rank]!=1 || [dict get $schema dtype] ni {float64 float32 int64 uint64 int32 uint32 int16 uint16 int8 uint8}} {error {Preview source axes require enabled rank-one numeric Variables}}
    }
    set allowed {mode x_variable_id y_variable_id}
    if {$mode eq {rows}} {
        lappend allowed start count
        foreach key {start count} {if {![dict exists $request $key] || ![string is entier -strict [dict get $request $key]]} {error {Row window requires exact integer start/count}}}
        set start [dict get $request start];set count [dict get $request count]
        set total [datasetField $id row_count -1]
        if {![string is entier -strict $total] || $total<0} {error {Exact row windows require an available canonical row count}}
        if {$start<0 || $count<1 || $start>9223372036854775807 || $count>9223372036854775807 || ($total>=0 && ($start>=$total || $count>$total-$start))} {error {Row window exceeds actual canonical source rows}}
    } elseif {$mode eq {time}} {
        lappend allowed time_min time_max
        if {[dict get [datasetVariableV3ById $id $x] semantic_role] ne {time}} {error {Time interval requires the canonical time Variable}}
        foreach key {time_min time_max} {
            if {![dict exists $request $key] || ![string is double -strict [dict get $request $key]] || [catch {expr {abs(double([dict get $request $key]))<Inf}} finite] || !$finite} {error {Time interval requires finite canonical time bounds}}
        }
        if {[dict get $request time_min]>[dict get $request time_max]} {error {Time interval From must not exceed To}}
    }
    foreach key [dict keys $request] {if {$key ni $allowed} {error {Source request fields do not match the selected mode}}}
    return $request
}
proc ::GX::datasetPreviewGuiSelectDataset {host datasetId} {
    set record [_datasetPreviewGuiRequire $host]
    set token [dict get $record context token]
    set datasetId [datasetPublicationV2ValidateId dataset $datasetId]
    sessionInspectionDataset $datasetId
    datasetBrowserActivate $datasetId
    if {[interactiveDocumentSessionToken] ne $token} {error {Session changed during Dataset selection}}
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode actual
    if {$mode ne {imported} || $actual ne $datasetId} {error {Dataset selection was not accepted by the existing inspection owner}}
    datasetPreviewGuiRefresh
    return [dict create dataset_id $datasetId selected 1]
}
proc ::GX::datasetPreviewGuiSourceRequest {host request} {
    set record [_datasetPreviewGuiRequire $host]
    set id [dict get $record dataset]
    set request [_datasetPreviewSourceRequestNormalize $id $request]
    # Existing Live/Cache/Job owners retain accepted geometry until an admitted
    # replacement. This opaque host is retired by the normal epoch guard.
    datasetPreviewLiveActivate $id 1 $request
    set plot [dict get $record plot]
    if {$plot ne {} && [winfo exists $plot]} {
        set pane [winfo parent $plot];set notebook [winfo parent $pane]
        if {[winfo class $notebook] eq {TNotebook}} {$notebook select $pane}
    }
    datasetPreviewGuiRefresh
    return [dict create dataset_id $id source_window $request key [dict get $::GX::PreviewLive::active key]]
}
