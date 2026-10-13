# SPDX-License-Identifier: GPL-3.0-or-later
# Cooperative exact single-output transformations. Scientific planning runs in
# the existing CORE Parallel Execution process service; publication stays in the
# parent canonical Dataset authority and yields only before its atomic commit.
namespace eval ::GX::DatasetTransform {variable executions;array set executions {}}
proc ::GX::datasetTransformResponsiveApiInfo {} {
    return [dict create api_id DATASET_TRANSFORM_API_v1 api_version 1 operations {execute_responsive cancel} maximum_chunk_rows 65536 default_chunk_rows 8192 cancellation precommit source_authority immutable implicit_publication 0 split_family_responsive 0]
}
proc ::GX::datasetTransformCancel {job} {
    variable ::GX::DatasetTransform::executions
    if {![info exists executions($job)]} {error "Unknown or completed Dataset Transform execution"}
    dict set executions($job) cancelled 1
    set run [dict get $executions($job) native_run]
    if {$run ne ""&&[parallelExecutionRunExists $run]} {parallelExecutionCancel $run}
    return 1
}
proc ::GX::_datasetTransformResponsiveCheck {job} {
    variable ::GX::DatasetTransform::executions
    if {![info exists executions($job)]} {error "Dataset Transform execution is no longer active"}
    set record $executions($job)
    if {[dict get $record lifetime] ne [interactiveDocumentSessionToken]} {error "Dataset Transform Session lifetime changed; staged output was discarded"}
    if {[dict get $record fault] ne {}} {lassign [dict get $record fault] message options;return -options $options $message}
    set cancel [dict get $record options cancel_command]
    if {$cancel ne ""&&[uplevel #0 [list {*}$cancel]]} {datasetTransformCancel $job}
    if {[dict get $executions($job) cancelled]} {return -code error -errorcode {GX DATASET_TRANSFORM CANCELLED} "Dataset Transform cancelled before publication; no Dataset was committed"}
}
proc ::GX::_datasetTransformResponsiveEvent {job stage current total} {
    variable ::GX::DatasetTransform::executions
    _datasetTransformResponsiveCheck $job
    set command [dict get $executions($job) options progress_command]
    if {$command ne ""} {
        uplevel #0 [list {*}$command [dict create api_id DATASET_TRANSFORM_API_v1 api_version 1 job_id $job stage $stage current $current total $total cancellable 1]]
    }
    _datasetTransformResponsiveCheck $job
}
proc ::GX::_datasetTransformResponsiveBoundary {job stage current total} {
    variable ::GX::DatasetTransform::executions
    _datasetTransformResponsiveEvent $job $stage $current $total
    # Yield at bounded staging boundaries; scientific/native transactions and
    # canonical commit never run inside this event-loop callback.
    set executions($job,wakeup) 0
    set timer [after 0 [list set ::GX::DatasetTransform::executions($job,wakeup) 1]]
    try {vwait ::GX::DatasetTransform::executions($job,wakeup)} finally {after cancel $timer;unset -nocomplain executions($job,wakeup)}
    _datasetTransformResponsiveCheck $job
}
proc ::GX::_datasetTransformResponsiveChunkRows {job} {
    variable ::GX::DatasetTransform::executions
    return [dict get $executions($job) options chunk_rows]
}
proc ::GX::_datasetTransformResponsiveCommand {item context} {return [dict get $item argv]}
proc ::GX::_datasetTransformResponsivePulse {job} {
    variable ::GX::DatasetTransform::executions
    if {![info exists executions($job)]} return
    if {[catch {_datasetTransformResponsiveEvent $job planning 0 0} message options]} {
        dict set executions($job) fault [list $message $options]
        datasetTransformCancel $job
    }
    if {[dict get $executions($job) native_run] ne ""} {
        dict set executions($job) timer [after 50 [list ::GX::_datasetTransformResponsivePulse $job]]
    }
}
proc ::GX::_datasetTransformResponsiveWorker {job command} {
    variable ::GX::DatasetTransform::executions
    _datasetTransformResponsiveBoundary $job planning 0 0
    set run [parallelExecutionNewRunId dataset_transform]
    dict set executions($job) native_run $run
    dict set executions($job) timer [after 50 [list ::GX::_datasetTransformResponsivePulse $job]]
    try {
        set execution [parallelExecutionExecute [list [dict create id plan argv $command]] [dict create kind process command_builder ::GX::_datasetTransformResponsiveCommand environment [dict create PYTHONNOUSERSITE 1 PYTHONDONTWRITEBYTECODE 1]] [dict create workers 1 run_id $run]]
        _datasetTransformResponsiveCheck $job
        if {[dict get $execution state] eq "cancelled"} {return -code error -errorcode {GX DATASET_TRANSFORM CANCELLED} "Dataset Transform planning was cancelled"}
        set result [lindex [dict get $execution results] 0]
        if {[dict get $result state] ne "success"} {
            set message [dict get $result stderr]
            if {$message eq ""} {set message [dict get $result error]}
            return -code error -errorcode [dict get $result error_code] $message
        }
        return [string trimright [encoding convertfrom utf-8 [dict get $result value]] "\r\n"]
    } finally {
        after cancel [dict get $executions($job) timer]
        dict set executions($job) native_run "";dict set executions($job) timer ""
        parallelExecutionRelease $run
    }
}
proc ::GX::datasetTransformExecuteResponsive {session manifestOrPlan {options {}}} {
    variable ::GX::DatasetTransform::executions;variable ::GX::DatasetTransform::serial
    if {[catch {dict size $options}]} {error "Responsive Dataset Transform options must be a dictionary"}
    foreach key [dict keys $options] {if {$key ni {progress_command cancel_command chunk_rows}} {error "Unknown responsive transform option '$key'"}}
    set options [dict merge [dict create progress_command "" cancel_command "" chunk_rows 8192] $options]
    set rows [dict get $options chunk_rows]
    if {![string is entier -strict $rows]||$rows<1||$rows>65536} {error "Responsive transform chunk_rows must be 1..65536"}
    foreach key [array names executions] {
        if {[string match "transform-execution#*" $key]&&![string match *,wakeup $key]} {error "A responsive Dataset Transform is already active; finish or cancel it first"}
    }
    set session [file normalize $session];set ::GX::currentSession $session;loadDatasetRegistry $session
    set own [expr {![dict exists $manifestOrPlan plan_id]}]
    if {$own} {set operation [dict get $manifestOrPlan operation]} else {set operation [dict get [_datasetTransformRequire [dict get $manifestOrPlan plan_id]] manifest operation]}
    if {$operation eq "split_family"} {error "Responsive execution currently supports one output Dataset; use the atomic split-family API for a bundle"}
    set job "transform-execution#[pid]-[incr serial]"
    set executions($job) [dict create options $options lifetime [interactiveDocumentSessionToken] cancelled 0 native_run "" timer "" fault {}]
    set plan ""
    try {
        if {$own} {set plan [_datasetTransformPlanInternal $session $manifestOrPlan $job]} else {set plan $manifestOrPlan}
        _datasetTransformResponsiveBoundary $job planned 0 [dict get $plan row_count]
        return [_datasetTransformMaterialize $session $plan "" $job]
    } finally {
        set timer [dict get $executions($job) timer];if {$timer ne ""} {after cancel $timer}
        try {if {$own&&$plan ne ""} {datasetTransformReleasePlan [dict get $plan plan_id]}} finally {unset executions($job)}
    }
}
