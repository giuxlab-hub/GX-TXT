#!/usr/bin/env tclsh
# Private Octave adapter for the public CORE Curve Source identity operation.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] .. ..]]
set argv0 __curve_source_identity__
if {[catch {
    source [file join $root gxtxt_pipeline.tcl]
    ::GX::defaults
    if {[llength $argv]!=2} {error {Curve Source identity requires Session and Dataset ID}}
    lassign $argv session dataset
    set ::GX::currentSession [file normalize $session]
    if {![file isdirectory $::GX::currentSession]} {error {Curve Source Session is unavailable}}
    ::GX::loadDatasetRegistry $::GX::currentSession
    set identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]
    puts [join [list CURVE_SOURCE_IDENTITY_V1 [dict get $identity dataset_id] [dict get $identity sha256] [dict get $identity schema_identity]] \t]
} message]} {
    puts [join [list CURVE_SOURCE_IDENTITY_ERROR_V1 [binary encode base64 -maxlen 0 [encoding convertto utf-8 $message]]] \t]
    exit 2
}
exit 0
