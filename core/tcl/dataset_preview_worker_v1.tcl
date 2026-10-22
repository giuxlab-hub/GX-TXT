#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Fixed trusted managed-cache worker. Payload is dictionary data, never script.
namespace eval ::GXPreviewWorker {variable diagnostics {}}
rename ::puts ::GXPreviewWorker::originalPuts
proc ::puts {args} {
    set rest $args;set newline 1
    if {[lindex $rest 0] eq "-nonewline"} {set newline 0;set rest [lrange $rest 1 end]}
    if {[llength $rest]==1} {set channel stdout;set message [lindex $rest 0]
    } elseif {[llength $rest]==2} {lassign $rest channel message
    } else {tailcall ::GXPreviewWorker::originalPuts {*}$args}
    if {$channel ni {stdout stderr}} {tailcall ::GXPreviewWorker::originalPuts {*}$args}
    if {[string bytelength $message]>8192} {set message [string range $message end-1023 end]}
    append ::GXPreviewWorker::diagnostics $message
    if {$newline} {append ::GXPreviewWorker::diagnostics \n}
    if {[string bytelength $::GXPreviewWorker::diagnostics]>8192} {set ::GXPreviewWorker::diagnostics [string range $::GXPreviewWorker::diagnostics end-1023 end]}
    return
}
set status [catch {
    if {[llength $argv]!=1} {error {Preview worker needs its matching framework root}}
    set framework [file normalize [lindex $argv 0]]
    if {$framework ne [file normalize [file join [file dirname [info script]] .. ..]]} {error {Preview worker framework identity mismatch}}
    fconfigure stdin -encoding binary -translation binary
    set raw [read stdin 1048577]
    if {[string length $raw]>1048576 || ![eof stdin]} {error {Preview worker request exceeds1MiB}}
    set request [encoding convertfrom utf-8 $raw]
    if {[encoding convertto utf-8 $request] ne $raw} {error {Preview worker request is not canonical UTF-8}}
    if {[catch {dict size $request}]} {error {Preview worker request must be a dictionary}}
    foreach key {schema session dataset_id options expected_key} {if {![dict exists $request $key]} {error "Preview worker request needs $key"}}
    foreach key [dict keys $request] {if {$key ni {schema session dataset_id options expected_key}} {error "Unknown Preview worker request field '$key'"}}
    if {[dict get $request schema] ne "gxtxt.preview_worker.v1"} {error {Unsupported Preview worker request version}}
    set session [dict get $request session]
    if {[file pathtype $session] ne "absolute" || ![file isdirectory $session] || ![file isfile [file join $session metadata manifest.ini]]} {error {Preview worker needs an existing canonical Session}}
    if {![regexp {^[a-f0-9]{64}$} [dict get $request expected_key]]} {error {Preview worker needs an exact cache key}}
    dict size [dict get $request options]
    set ::env(GXTXT_PREVIEW_WORKER) 1
    set argv0 __gxtxt_preview_worker__
    source [file join $framework gxtxt_pipeline.tcl]
    ::GX::defaults;::GX::loadModuleCatalog
    set ::GX::currentSession [file normalize $session]
    ::GX::loadManifest [file join $session metadata manifest.ini]
    set ::GX::currentSession [file normalize $session]
    ::GX::loadDatasetRegistry $session
    set id [::GX::datasetPublicationV2ValidateId dataset [dict get $request dataset_id]]
    set prepared [::GX::datasetPreviewCacheGenerate $id [dict get $request options] [dict get $request expected_key]]
    set result [dict create key [dict get $prepared key] dataset_id $id status ready kind [dict get $prepared kind]]
} message options]
if {$status} {
    if {[string length $message]>4096} {set message "[string range $message 0 4095]…"}
    set response [dict create ok 0 error $message]
} else {set response [dict create ok 1 result $result]}
if {$::GXPreviewWorker::diagnostics ne {}} {dict set response diagnostic_tail $::GXPreviewWorker::diagnostics}
::GXPreviewWorker::originalPuts stdout $response
exit [expr {$status?1:0}]
