# SPDX-License-Identifier: GPL-3.0-or-later
proc ::P017Manual::run {} {
    ::GX::modulePublicApiActivate viewer.scientific_worksheet SCIENTIFIC_WORKSHEET_API_v1
    set ::w [::GX::ScientificWorksheet::open {workspace_id new workspace_name {P017 native cell History}}];set w $::w
    wm geometry $w 1250x850+20+20;pause 220
    check {[winfo ismapped $w]} {Scientific Worksheet is actually mapped}
    set g [::GX::ScientificWorksheet::UI::grid $w]
    check {[winfo class $g] eq {GXNativeGrid}} {Worksheet scientific cells use the actual native grid}
    click $w.toolbar.save
    set id [::GX::ScientificWorksheet::UI::current $w]
    check {$id ne {}} {Initial explicit Save establishes Document owner}
    durable $w
    set initial [::GX::scientificHistoryViewerStatus $w];set initialCount [dict get $initial count]
    set revision [dict get [::GX::interactiveDocumentMetadata $id] revision]
    auditStart
    lassign [$g bbox 1 1] x y width height
    click $g [expr {$x+16}] [expr {$y+$height/2}]
    key F2;type 42;key Return
    check {[dict get [::GX::ScientificWorksheet::value [::GX::ScientificWorksheet::UI::book $w] A1] value]==42} {Native pointer F2 typing and Return commit exact A1 scientific value}
    set accepted [::GX::scientificHistoryViewerStatus $w]
    check {[dict get $accepted count]==$initialCount+1 && [dict get $accepted cursor]==[dict get $accepted count]} {One cell commit is immediately present in accepted RAM History}
    focus -force $g;key ctrl+z
    check {![dict exists [::GX::ScientificWorksheet::UI::book $w] cells A1]} {Native Ctrl+Z immediately restores the preceding Worksheet state}
    key ctrl+y
    check {[dict get [::GX::ScientificWorksheet::value [::GX::ScientificWorksheet::UI::book $w] A1] value]==42} {Native Ctrl+Y restores exact scientific cell value}
    lassign [$g bbox 1 2] x y width height
    click $g [expr {$x+16}] [expr {$y+$height/2}]
    key F2;type {=A1*2};key Return
    check {[dict get [::GX::ScientificWorksheet::value [::GX::ScientificWorksheet::UI::book $w] B1] value]==84 && [dict get [::GX::ScientificWorksheet::UI::book $w] cells B1 source] eq {=A1*2}} {Second native edit retains exact formula text and evaluates scientific dependency}
    set accepted [::GX::scientificHistoryViewerStatus $w]
    check {[dict get $accepted count]==$initialCount+2} {Undo/Redo navigates existing operations without appending duplicate scientific History}
    check {[dict get [::GX::interactiveDocumentMetadata $id] revision]==$revision} {Ordinary Worksheet operations leave stored Document revision unchanged}
    auditEnd worksheet
    shot worksheet_after_native_edits $w
    click $w.toolbar.save
    durable $w
    set doc [::GX::interactiveDocumentRead $id]
    check {[dict get $doc revision]>$revision} {Explicit Worksheet Save projects the accepted operations}
    set persisted [dict get [::GX::sessionWorkspaceGet $id] payload]
    check {[dict exists $persisted history] && [llength [dict get $persisted history steps]]==$initialCount+2} {Canonical Worksheet payload contains all retained scientific History}
    check {![::GX::ScientificWorksheet::UI::dirty $w]} {Explicit Save updates the Worksheet saved marker}
    ::GX::ScientificWorksheet::UI::close $w;pause
    check {![winfo exists $w]} {Clean Worksheet Close drains and disposes its CORE History adapter}
    set ::w [::GX::ScientificWorksheet::open [dict create workspace_id $id]];set w $::w;pause 180
    check {[dict get [::GX::ScientificWorksheet::value [::GX::ScientificWorksheet::UI::book $w] A1] value]==42 && [dict get [::GX::ScientificWorksheet::UI::book $w] cells B1 source] eq {=A1*2}} {Real Worksheet reopen preserves scientific values and exact formula source}
    check {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$initialCount+2} {Real Worksheet reopen restores the complete native History}
    shot worksheet_reopened $w
    emit final [dict create workspace_id $id history [::GX::scientificHistoryViewerStatus $w] cells [dict get [::GX::ScientificWorksheet::UI::book $w] cells]]
    ::GX::ScientificWorksheet::UI::close $w
}
