# SPDX-License-Identifier: GPL-3.0-or-later
# Backend tests: new notes are written via the CORE Dataset Notes authority.
# Both generic and image publications preserve unrelated Markdown.
source [file join [file dirname [info script]] test_publication_manifest.tcl]
namespace eval ::GX {variable noteText "# Lab notes\n\nDo not remove the calibration record.\n";variable notesSaved 0;variable notesFail 0}
proc ::GX::datasetUserNotes {id} {return $::GX::noteText}
proc ::GX::datasetUserNotesSave {id text} {
    if {$::GX::notesFail} {error {test filesystem failure}}
    incr ::GX::notesSaved
    set ::GX::noteText $text
    return [file join notes datasets ${id}.md]
}
proc _assert {test detail} {if {!$test} {error "FAIL: $detail"}}
set userNote "SEM edge tracing: µm values.\n\n- top boundary\n- bottom boundary"
set argsWithNotes [concat $callArgs [list $userNote]]
set receipt [::GX::CurveDigitizer::_publish {*}$argsWithNotes]
_assert [expr {[llength [split $receipt "\t"]] == 5}] {new receipt has notes status}
_assert [expr {[lindex [split $receipt "\t"] 4] eq "written"}] {notes written}
_assert [expr {[string first {# Lab notes} $::GX::noteText] == 0}] {original note was not erased}
_assert [expr {[string first $userNote $::GX::noteText] >= 0}] {user-authored note missing}
_assert [expr {[string first {## Curve Digitalizer notes} $::GX::noteText] >= 0}] {note heading missing}
set firstText $::GX::noteText
set receipt [::GX::CurveDigitizer::_publish {*}$argsWithNotes]
_assert [expr {$::GX::noteText eq $firstText && $::GX::notesSaved == 1}] {duplicate text on republish}
_assert [expr {[lindex [split $receipt "\t"] 4] eq "unchanged"}] {not reported unchanged}
set brief [lreplace $argsWithNotes end end {Brief note}]
::GX::CurveDigitizer::_publish {*}$brief
set extended [lreplace $argsWithNotes end end "Brief note\nMore details"]
::GX::CurveDigitizer::_publish {*}$extended
_assert [expr {[string first "More details" $::GX::noteText] >= 0}] {prefix must not be treated as a duplicate}
set updatedCount $::GX::notesSaved
set newer "Updated SEM notes with **reviewed** edge."
set changed [lreplace $argsWithNotes end end $newer]
set receipt [::GX::CurveDigitizer::_publish {*}$changed]
_assert [expr {$::GX::notesSaved == $updatedCount + 1}] {new note must write}
_assert [expr {[string first $firstText $::GX::noteText] == 0}] {old notes were modified}
_assert [expr {[string first $newer $::GX::noteText] >= 0}] {new note missing}
set empty [lreplace $argsWithNotes end end ""]
set receipt [::GX::CurveDigitizer::_publish {*}$empty]
_assert [expr {$::GX::notesSaved == $updatedCount + 1}] {empty notes must not touch existing note}
_assert [expr {[lindex [split $receipt "\t"] 4] eq "empty"}] {empty note result}
set ::GX::notesFail 1
set result [::GX::CurveDigitizer::_publish {*}[lreplace $argsWithNotes end end {Different notes}]]
_assert [expr {[lindex [split $result "\t"] 0] eq {published}}] {scientific Dataset must remain published}
_assert [expr {[string match {failed:*} [lindex [split $result "\t"] 4]]}] {notes failure must not be reported as failed dataset publication}
_assert [expr {$::GX::notesSaved == $updatedCount + 1}] {failed notes save unexpectedly wrote}
puts {PASS: existing Dataset Markdown preserved, note appended, idempotent, edited, empty, failed after publication}
