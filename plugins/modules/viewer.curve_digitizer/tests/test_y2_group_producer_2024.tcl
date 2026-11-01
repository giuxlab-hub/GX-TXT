# SPDX-License-Identifier: GPL-3.0-or-later
# Producer-scoped Dataset Group authorization and review/create sequence.
namespace eval ::GX {
    variable mockToken f4_session
    variable reviews 0
    variable creates 0
    variable lastGroup {}
    variable lastMembers {}
    variable metadata {}
}
proc ::GX::viewerBackendRegister {args} {}
proc ::GX::interactiveDocumentSessionToken {} {return $::GX::mockToken}
proc ::GX::sessionInspectionCurrentSession {} {return /tmp/f4_group_session}
proc ::GX::datasetGroupProducerReviewV1 {cap session ids} {
    if {$cap ne "core_issued_mock_cap" ||
        $session ne "/tmp/f4_group_session"} {error {Untrusted producer}}
    incr ::GX::reviews
    return [dict create schema gxtxt.dataset_group_review.v1 \
        session_token $::GX::mockToken producer_module viewer.curve_digitizer \
        dataset_revisions [dict create alpha opaque_rev_A beta opaque_rev_B]]
}
proc ::GX::datasetGroupProducerCreateV1 {cap session definition review} {
    if {$cap ne "core_issued_mock_cap" ||
        $session ne "/tmp/f4_group_session"} {error {Invalid group authority}}
    if {[dict get $review schema] ne "gxtxt.dataset_group_review.v1"} {
        error {Wrong review}
    }
    if {[dict get $definition group_contract] ne "curve_digitizer.publication"} {
        error {Group contract changed}
    }
    set ::GX::lastGroup $definition
    set ::GX::lastMembers [dict get $definition members]
    incr ::GX::creates
    return [dict create group_id [dict get $definition group_id] status COMPLETE]
}
proc ::GX::datasetMetadataRead {session id} {
    if {![dict exists $::GX::metadata $id]} {error {Unknown output}}
    return [dict get $::GX::metadata $id]
}
proc assert {x y msg} {if {$x ne $y} {error "$msg: $x != $y"}}
source [file join [file dirname [info script]] .. api curve_digitizer_viewer_api_v1.tcl]
set ::GX::metadata [dict create \
    alpha [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
        curve_digitizer.publication_axis_id y1] \
    beta [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
        curve_digitizer.publication_axis_id y2]]
# No retained capability: no group operation and no false success.
assert [::GX::CurveDigitizer::_groupAvailable $::GX::mockToken] 0 capability_absent
if {![catch {::GX::CurveDigitizer::_groupCreate $::GX::mockToken gxtxt_test Group "alpha\nbeta"}]} {
    error {Ungrantable group operation was accepted}
}
assert $::GX::creates 0 absent_writes
# The real framework issues this opaque context inside registered viewerDispatch.
set ::GX::CurveDigitizer::groupProducerCapability core_issued_mock_cap
assert [::GX::CurveDigitizer::_groupAvailable $::GX::mockToken] 1 granted
if {![catch {::GX::CurveDigitizer::_groupAvailable wrong_token}]} {
    error {Stale Session token accepted}
}
set output [::GX::CurveDigitizer::_groupCreate \
    $::GX::mockToken gxtxt_test {Grouped curves} "alpha\nbeta"]
assert $output gxtxt_test created_identity
assert $::GX::reviews 1 single_review
assert $::GX::creates 1 single_group_create
assert [dict get [lindex $::GX::lastMembers 0] role] \
       curve_digitizer.axis.y1 member1_role
assert [dict get [lindex $::GX::lastMembers 1] role] \
       curve_digitizer.axis.y2 member2_role
# Bad inputs must fail before review.
set prev $::GX::reviews
if {![catch {::GX::CurveDigitizer::_groupCreate $::GX::mockToken gxtxt_test Bad "alpha\nalpha"}]} {
    error {Duplicate members accepted}
}
assert $::GX::reviews $prev duplicate_preflight
dict set ::GX::metadata beta curve_digitizer.plugin_id another.plugin
if {![catch {::GX::CurveDigitizer::_groupCreate $::GX::mockToken gxtxt_test Bad "alpha\nbeta"}]} {
    error {Foreign producer metadata accepted}
}
assert $::GX::reviews $prev foreign_preflight
puts {PASS F4 Group: fail-closed capability, exact Session, 2 reviewed producer outputs, scientific member roles}
