# SPDX-License-Identifier: GPL-3.0-or-later
proc ::P017Manual::run {} {
    set original [publish]
    ::GX::modulePublicApiActivate viewer.curve_viewer CURVE_VIEWER_API_v1
    set ::w [::GX::CurveViewer::open {workspace_id new workspace_name {P017 canonical curve History} dataset_id qa_history_source}];set w $::w
    wm geometry $w 1250x850+20+20;pause 160
    check {[winfo ismapped $w]} {Manual Curve Viewer is actually mapped}
    if {![winfo exists $w.source]} {menu $w.toolbar.sourcesMenu {Add curve…}}
    combo $w.source.x 0;combo $w.source.y 1
    click $w.source.actions.add
    waitFor {[::GX::CurveViewer::_ready $w] && [dict size $::GX::CurveViewer::st($w,records)]==1 && ![winfo exists $w.source]} {canonical source load}
    set id [lindex [dict keys $::GX::CurveViewer::st($w,records)] 0]
    set record [dict get $::GX::CurveViewer::st($w,records) $id]
    check {[dict get $record request dataset_id] eq {qa_history_source} && [dict get $record request x_variable_id] eq {source_x} && [dict get $record request y_variable_id] eq {source_y} && [dict get $record descriptor row_count]==8} {Real source dialog binds canonical typed variables and all eight exact rows}
    menu $w.toolbar.workspace Save
    set document [::GX::CurveViewer::_currentWorkspace $w]
    check {$document ne {}} {Explicit Curve Save establishes its existing Document owner}
    durable $w
    $w.sources see $id;update;lassign [$w.sources bbox $id] x y width height
    click $w.sources [expr {$x+50}] [expr {$y+$height/2}]
    set initial [::GX::scientificHistoryViewerStatus $w];set count [dict get $initial count]
    set revision [dict get [::GX::interactiveDocumentMetadata $document] revision]
    auditStart
    menu $w.toolbar.curvesMenu {Hide selected}
    check {![dict get $::GX::CurveViewer::st($w,records) $id visible]} {Native Curve menu hides the scientific source presentation}
    check {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$count+1} {Curve presentation operation is immediately accepted into CORE History}
    activate $w.canvas;focus -force $w.canvas;key ctrl+z
    waitFor {[::GX::CurveViewer::_ready $w]} {Undo source restore}
    check {[dict get $::GX::CurveViewer::st($w,records) $id visible]} {Native Curve Ctrl+Z restores source visibility and owned source handles}
    key ctrl+y
    waitFor {[::GX::CurveViewer::_ready $w]} {Redo source restore}
    check {![dict get $::GX::CurveViewer::st($w,records) $id visible]} {Native Curve Ctrl+Y restores the accepted hidden presentation}
    check {[dict get [::GX::interactiveDocumentMetadata $document] revision]==$revision} {Curve edit and navigation do not update the stored Document}
    auditEnd curve
    shot curve_after_native_undo_redo $w
    menu $w.toolbar.workspace Save
    durable $w
    set persisted [dict get [::GX::sessionWorkspaceGet $document] payload]
    check {[dict exists $persisted scientific_history] && [llength [dict get $persisted scientific_history steps]]==$count+1} {Explicit Curve Save projects retained History through the normal Workspace}
    $w.sources selection set $id
    menu $w.toolbar.curvesMenu {Show selected}
    check {[dict get $::GX::CurveViewer::st($w,records) $id visible]} {Second normal Curve operation is accepted before Close}
    ::GX::CurveViewer::_close $w 1;pause
    check {![winfo exists $w]} {Curve Close flushes accepted operations before source/native disposal}
    set ::w [::GX::CurveViewer::open [dict create workspace_id $document]];set w $::w
    waitFor {[::GX::CurveViewer::_ready $w]} {saved Curve source reopen}
    check {[dict get $::GX::CurveViewer::st($w,records) $id visible]} {Real Curve reopen retains the operation pending when Close began}
    set restored [dict get $::GX::CurveViewer::st($w,records) $id]
    check {[dict get $restored request] eq [dict get $record request] && [dict get $restored descriptor row_count]==8} {Curve reopen preserves canonical Dataset request and exact source extent}
    check {[dict get [::GX::sessionInspectionDatasetPayload qa_history_source] sha256] eq $original} {History integration preserves canonical scientific Dataset bytes}
    check {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$count+2} {Close and reopen preserve complete Curve History without private recording}
    shot curve_reopened $w
    emit final [dict create workspace_id $document source_sha256 $original history [::GX::scientificHistoryViewerStatus $w] request [dict get $restored request]]
    ::GX::CurveViewer::_close $w 1
}
