# SPDX-License-Identifier: GPL-3.0-or-later
proc ::P017Manual::run {} {
    set original [publish]
    ::GX::modulePublicApiActivate viewer.replicate_curve_analysis REPLICATE_VIEWER_API_v1
    set ::w [::GX::ReplicateViewer::open {workspace_id new workspace_name {P017 Replicate adapter contract}}];set w $::w;pause 180
    check {[winfo ismapped $w]} {Replicate shared-manifest Viewer is mapped for its distinct adapter contract}
    set document [::GX::ReplicateViewer::save $w];durable $w
    set snapshot [::GX::ReplicateViewer::_sourceSnapshot qa_history_source]
    check {[::GX::ReplicateViewer::_sourceCheck qa_history_source $snapshot] eq $snapshot} {Replicate canonical source identity guard accepts the exact public snapshot}
    set foreign $snapshot;dict set foreign source_revision {foreign-revision}
    check {[catch {::GX::ReplicateViewer::_sourceCheck qa_history_source $foreign} message options] && [dict get $options -errorcode] eq {REPLICATE SOURCE SOURCE_CHANGED}} {Replicate source guard rejects stale identity without rebind or analysis}
    set before [::GX::ReplicateViewer::capture $w];set payload $before;dict set payload request grid_points 201
    set revision [dict get [::GX::interactiveDocumentMetadata $document] revision]
    auditStart
    ::GX::ReplicateViewer::_boundHistoryLatest $w
    check {[::GX::ReplicateViewer::change $w $payload {Change grid point request}]} {Replicate adapter records an inert study configuration change through CORE}
    ::GX::ReplicateViewer::_boundHistoryLatest $w
    ::GX::ReplicateViewer::navigate $w undo
    check {[dict get [::GX::ReplicateViewer::capture $w] request grid_points]==[dict get $before request grid_points]} {Replicate Undo restores exact study request without running analysis}
    ::GX::ReplicateViewer::navigate $w redo
    ::GX::scientificHistoryViewerBrowse $w 0
    check {[catch {::GX::ReplicateViewer::_boundHistoryLatest $w} message options] && [dict get $options -errorcode] eq {REPLICATE SOURCE UNAVAILABLE_BINDING}} {Replicate bound-source admission refuses historical browsing}
    ::GX::scientificHistoryViewerNavigate $w latest
    check {[dict get [::GX::interactiveDocumentMetadata $document] revision]==$revision} {Replicate configuration/browse contract does not synchronously project Document}
    auditEnd replicate
    ::GX::ReplicateViewer::save $w;durable $w
    shot replicate_contract $w
    ::GX::sessionWorkspaceRename $document {Externally changed owned test study}
    check {[catch {::GX::ReplicateViewer::guard $w}]} {Replicate owner guard rejects a changed Document revision}
    check {[dict get [::GX::sessionInspectionDatasetPayload qa_history_source] sha256] eq $original} {Replicate contract preserves scientific source bytes}
    emit final [dict create workspace_id $document source_sha256 $original history [::GX::scientificHistoryViewerStatus $w] no_analysis 1]
    ::GX::ReplicateViewer::discard $w
}
