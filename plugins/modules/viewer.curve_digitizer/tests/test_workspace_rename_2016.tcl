# SPDX-License-Identifier: GPL-3.0-or-later
# Execute the actual module Tcl _documentRename procedure with a public API stub.
set root [file normalize [file join [file dirname [info script]] ..]]
set sourceFile [file join $root api curve_digitizer_viewer_api_v1.tcl]
set ch [open $sourceFile r];set src [read $ch];close $ch
set start [string first "proc ::GX::CurveDigitizer::_documentRename " $src]
set end [string first "proc ::GX::CurveDigitizer::_documentDelete " $src $start]
if {$start<0 || $end<0 || $end<=$start} {error "Actual document rename procedure was not found"}
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizer {}
proc assert {exprValue label} {if {![uplevel 1 [list expr $exprValue]]} {error "FAIL: $label"}}
set ::token goodtoken
set ::native_name Original
set ::doc_hash abcdef123
set ::doc_rev 1
set ::gen generation1
set ::native_changes 0
proc ::GX::interactiveDocumentSessionToken {} {return $::token}
proc ::GX::CurveDigitizer::_ownedDocumentRead {id} {
    if {$id ne {doc1}} {error {Foreign owner}}
    return [dict create id doc1 sha256 $::doc_hash generation $::gen revision $::doc_rev name $::native_name]
}
proc ::GX::CurveDigitizer::_documentResult {result} {
    return [join [list [dict get $result id] [dict get $result sha256] [dict get $result generation] [dict get $result revision]] \t]
}
proc ::GX::sessionWorkspaceRename {id name} {
    if {$id ne {doc1}} {error {Foreign object}}
    if {$name eq {Conflict}} {error {Duplicate Workspace name}}
    set ::native_name $name
    incr ::doc_rev
    incr ::native_changes
    return [dict create id $id generation $::gen revision $::doc_rev]
}
# Only this exact production procedure is sourced; never load framework CORE.
uplevel #0 [string range $src $start [expr {$end-1}]]
set result [::GX::CurveDigitizer::_documentRename doc1 Renamed goodtoken $::doc_hash $::gen $::doc_rev]
assert {[lindex [split $result "\t"] 0] eq {doc1}} {correct identifier}
assert {$::native_name eq {Renamed}} {native rename}
assert {$::doc_rev==2} {new revision}
assert {$::native_changes==1} {one public rename}
assert {[lindex [split $result "\t"] 1] eq $::doc_hash} {configuration SHA unchanged}
set got [catch {::GX::CurveDigitizer::_documentRename doc1 Bad badtoken $::doc_hash $::gen $::doc_rev} msg]
assert {$got==1 && $::native_name eq {Renamed}} {stale session refused}
set got [catch {::GX::CurveDigitizer::_documentRename doc1 Bad goodtoken WRONG $::gen $::doc_rev} msg]
assert {$got==1 && $::native_name eq {Renamed}} {stale content SHA refused}
set got [catch {::GX::CurveDigitizer::_documentRename doc1 Bad goodtoken $::doc_hash $::gen 1} msg]
assert {$got==1 && $::native_name eq {Renamed}} {stale revision refused}
set got [catch {::GX::CurveDigitizer::_documentRename doc1 Conflict goodtoken $::doc_hash $::gen $::doc_rev} msg]
assert {$got==1 && $::native_name eq {Renamed}} {name conflict refused}
set same [::GX::CurveDigitizer::_documentRename doc1 Renamed goodtoken $::doc_hash $::gen $::doc_rev]
assert {$::native_changes==1 && $::doc_rev==2} {idempotent no-op}
puts "PASS: actual Tcl rename action, public native API, generation/revision guard, conflict and no-op"
