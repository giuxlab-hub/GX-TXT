# Mocks only: verify CORE publication orchestration, not actual data integrity.
# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] test_isolated.tcl]
proc ::GX::sessionInspectionCurrentSession {} {return /isolated-fake-session}
proc ::GX::interactiveDocumentSessionToken {} {return mock-token}
proc ::GX::interactiveDocumentRead {id} {
    return [dict create id $id module_id viewer.mathematics_explorer provider_id mathematics_explorer \
        format gxtxt.mathematics_explorer.state format_version 1 payload $::saved_state]
}
set ::publish_log {}
set ::publication_fail 0
proc ::GX::datasetPublicationV2ValidateId {kind id} {
    if {$kind ne "dataset" || ![regexp {^[a-zA-Z][a-zA-Z0-9_.-]*$} $id]} {error "Invalid Dataset ID"}
    return $id
}
proc ::GX::datasetPublicationV2Prepare {session module definition} {
    if {$module ne "viewer.mathematics_explorer"} {error "Wrong owner"}
    if {[dict exists $definition replace_owned] && [dict get $definition replace_owned]} {error "Overwrite requested"}
    lappend ::publish_log prepare
    return mock-plan
}
proc ::GX::datasetPublicationV2OpenWriter {plan} {lappend ::publish_log open;return mock-writer}
proc ::GX::datasetPublicationV2DeclareDimension {writer id size opts} {lappend ::publish_log dimension}
proc ::GX::datasetPublicationV2DeclareVariable {writer id opts} {
    if {[dict get $opts unit] ne ""} {error "Non-unitless output"}
    lappend ::publish_log "variable:$id"
}
proc ::GX::datasetPublicationV2Append {writer dimension data} {
    if {$dimension ne "row" || ![dict exists $data x] || ![dict exists $data f1]} {error "Missing data"}
    lappend ::publish_log append
    if {$::publication_fail} {error "Simulated writer fault"}
}
proc ::GX::datasetPublicationV2Finalize {writer} {lappend ::publish_log finalize; return [dict create dataset_id mathematics.prototest]}
proc ::GX::datasetPublicationV2Abort {writer} {lappend ::publish_log abort}

set state [::GX::MathematicsExplorer::initialState]
set ::saved_state $state
set computed [::GX::MathematicsExplorer::calculate $state]
assert [catch {::GX::MathematicsExplorer::publishComputed $state $computed "" mock-token mathematics.prototest}] {unsaved document refused}
set ::saved_state [dict replace $state title {Different saved function}]
assert [catch {::GX::MathematicsExplorer::publishComputed $state $computed idoc_0001 mock-token mathematics.prototest}] {stale saved model refused}
set ::saved_state $state
set result [::GX::MathematicsExplorer::publishComputed $state $computed idoc_0001 mock-token mathematics.prototest]
assert [expr {[dict get $result dataset_id] eq "mathematics.prototest"}] {publication forwarded}
assert [expr {$::publish_log eq {prepare open dimension variable:x variable:f1 append finalize}}] {public lifecycle order}
set ::publication_fail 1
set ::publish_log {}
assert [catch {::GX::MathematicsExplorer::publishComputed $state $computed idoc_0001 mock-token mathematics.prototest}] {simulated write failure}
assert [expr {[lindex $::publish_log end] eq "abort"}] {error triggers abort}
puts "ISOLATED PUBLICATION FLOW: PASS (mocks; NOT GX-TXT integration)"
