# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::P028ElectronicsComponent {variable helper [file join [file dirname [info script]] record_worker.py]}
proc ::P028ElectronicsComponent::_run {source args} {
 variable helper
 set command [list [::GX::runtimeToolRequired python] -I -B $helper [binary encode base64 -maxlen 0 [encoding convertto utf-8 $source]]]
 if {[llength $args]} {lappend command [binary encode base64 -maxlen 0 [encoding convertto utf-8 [lindex $args 0]]] [lindex $args 1]}
 if {[catch {exec {*}$command 2>@1} result]} {error {Structured record validation failed; check record type, required fields and identifiers.}}
 if {![dict get $result recognized]} {error {Unrecognized structured record}}
 return $result
}
proc ::P028ElectronicsComponent::inspect {request} {
 if {[catch {set result [_run [dict get $request source_path]]} reason]} {return [dict create recognized 0 warnings [list $reason] variables {} metadata {} preview_rows {}]}
 return [dict create recognized 1 format [dict get $result format] metadata [dict get $result metadata] variables {} preview_rows {} warnings {} preview_kind metadata preview_metadata [dict get $result metadata]]
}
proc ::P028ElectronicsComponent::import {request} {
 set result [_run [dict get $request raw_path] [dict get $request output_dir] [dict get $request dataset_id]]
 return [dict create datasets [list [dict create dataset_id [dict get $request dataset_id] contract [dict get $result contract] format [dict get $result format] path [dict get $result path] storage_kind binary media_type application/json variables {} units {} semantic_roles {} structured_metadata [dict get $result metadata] source {Typed Library/source record} provenance {Original structured JSON bytes preserved; domain validation; no invented numeric rows.}]]]
}
