# SPDX-License-Identifier: GPL-3.0-or-later
# Thin registered-source adapter to the same common source-note editor.
proc ::GX::ViewerDevelopmentWorkspace::projectNoteSources {} {
    variable s
    if {$s(mode) eq {acquisition}} {
        set names {}
        if {![info exists s(acqFiles)]} {return $names}
        dict for {name row} $s(acqFiles) {
            if {[::GX::datasetPublicationV2DictDefault $row source_notes_available 0] && [::GX::datasetPublicationV2DictDefault $row source_notes_language {}] in {cpp python}} {lappend names $name}
        }
        return $names
    }
    return [::GX::viewerDevelopmentSourceFiles $s(project)]
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesActive {} {
    variable s
    if {![info exists s(notes)] || ![winfo exists .gxViewerDevelopment.body.center.sources]} {return {}}
    set selected [.gxViewerDevelopment.body.center.sources select]
    dict for {name note} $s(notes) {if {[dict get $note page] eq $selected} {return $name}}
    return {}
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesPackSnapshot {widget} {
    if {[winfo manager $widget] ne {pack}} {return {}}
    set options [pack info $widget];set siblings [pack slaves [dict get $options -in]]
    return [dict create options $options after [lrange $siblings [expr {[lsearch -exact $siblings $widget]+1}] end]]
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesPackRestore {widget snapshot} {
    if {$snapshot eq {} || ![winfo exists $widget]} return
    set options [dict get $snapshot options]
    foreach next [dict get $snapshot after] {
        if {[winfo exists $next] && [winfo manager $next] eq {pack}} {pack $widget {*}$options -before $next;return}
    }
    pack $widget {*}$options
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesFocus {active} {
    variable s;set w .gxViewerDevelopment;set right $w.body.right
    if {![winfo exists $w.body]} return
    if {$active} {
        if {[info exists s(noteFocus)]} return
        set panes [$w.body panes];set sashes {}
        for {set i 0} {$i<[llength $panes]-1} {incr i} {lappend sashes [$w.body sashpos $i]}
        set saved [dict create panes $panes sashes $sashes focus [focus] file $s(file) bottom [projectNotesPackSnapshot $w.bottom] find [projectNotesPackSnapshot $w.body.center.find]]
        set s(noteFocus) $saved
        # Same retained widgets/controls: only their existing layout membership
        # changes while a Note is selected. Source queries/Undo/scroll stay live.
        # Keep the reference pane registered: its existing sash collapses it
        # without the remapping race caused by remove/reinsert.
        pack forget $w.body.center.find
        pack forget $w.bottom
        set at [lsearch -exact $panes $right]
        if {$at>0} {$w.body sashpos [expr {$at-1}] [winfo width $w.body]}
        return
    }
    if {![info exists s(noteFocus)]} return
    set saved $s(noteFocus);unset s(noteFocus)
    projectNotesPackRestore $w.bottom [dict get $saved bottom]
    projectNotesPackRestore $w.body.center.find [dict get $saved find]
    set i 0;foreach position [dict get $saved sashes] {$w.body sashpos $i $position;incr i}
    set previous [dict get $saved focus]
    if {$s(file) eq [dict get $saved file] && $previous ne {} && [winfo exists $previous] && [winfo toplevel $previous] eq $w && ![string match *.menus* $previous]} {focus $previous} elseif {[winfo exists [text]]} {focus [text]}
    responsiveBody $w
}
proc ::GX::ViewerDevelopmentWorkspace::projectNoteRef {name} {
    return [dict create owner cpp_viewer_project reference [dict create relative $name]]
}
proc ::GX::ViewerDevelopmentWorkspace::projectNoteRequestJson {fields} {
    variable s
    if {$s(mode) eq {acquisition}} {
        lappend fields {"schema":"gxtxt.development_project_edit.v1"} "\"expected_revision\":[::GX::viewerDevelopmentJsonString [dict get $s(acqDescription) revision]]"
    }
    return "\{[join $fields ,]\}"
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesSearchHandle {handle operation} {
    if {$operation ni {find replace hide}} {error {Unsupported source-note search presentation}}
    set source [dict get [::GX::_documentEditorRecord $handle] source]
    set surface [::GX::sourceSurfaceParent $source]
    if {$operation eq {hide}} {grid remove $surface.find;focus $source;return}
    grid $surface.find
    ::GX::documentEditorCommand $handle $operation
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesSearch {operation} {
    set handle [noteMenuHandle]
    if {$handle eq {}} {
        if {$operation eq {find}} {focus .gxViewerDevelopment.body.center.find.entry;return}
        error {Select an editable Note before replacing its literal text}
    }
    projectNotesSearchHandle $handle $operation
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesShow {{visible 1}} {
    variable s
    if {$s(mode) ni {cpp acquisition} || $s(project) eq {} || $s(busy) ne {}} {error {Open an idle source project first}}
    set name $s(file);set book .gxViewerDevelopment.body.center.sources
    if {$name ni [projectNoteSources]} {
        if {$s(mode) eq {acquisition} && [dict exists $s(acqFiles) $name]} {error [dict get $s(acqFiles) $name source_notes_reason]}
        error {Choose a registered source with available Notes support}
    }
    if {!$visible} {
        if {[dict exists $s(notes) $name]} {set page [dict get $s(notes) $name page];if {$page in [$book tabs]} {$book forget $page;$book select [dict get $s(tabs) $name page]}}
        set s(showNotes) 0;projectTabSelected;return
    }
    if {![dict exists $s(notes) $name]} {
        set page $book.notes[incr s(tabSerial)];ttk::frame $page
        set cap [dict get [::GX::_datasetPrivateModuleContext viewer.development_workspace] capability]
        if {[catch {set handle [::GX::sourceNoteEditorMount $page.editor $cap [projectNoteRef $name] [dict create on_change [list ::GX::ViewerDevelopmentWorkspace::projectNotesChanged $name] on_saved ::GX::ViewerDevelopmentWorkspace::projectNotesSaved]]} reason options]} {destroy $page;return -options $options $reason}
        # Same SourceSurface controls, initially collapsed as in UML's narrow
        # source presentation. No query/parser/search or editing owner changes.
        set source [dict get [::GX::_documentEditorRecord $handle] source]
        set surface [::GX::sourceSurfaceParent $source]
        grid remove $surface.find
        foreach {key operation} {<Control-f> find <Control-h> replace <Escape> hide} {bind $source $key "[list ::GX::ViewerDevelopmentWorkspace::projectNotesSearchHandle $handle $operation];break"}
        foreach control {query previous next replace.value replace.current replace.all} {bind $surface.find.$control <Escape> "[list ::GX::ViewerDevelopmentWorkspace::projectNotesSearchHandle $handle hide];break"}
        pack $page.editor -fill both -expand 1
        dict set s(notes) $name [dict create page $page editor $handle]
    }
    set note [dict get $s(notes) $name];set page [dict get $note page]
    if {$page ni [$book tabs]} {
        set at [expr {[$book index [dict get $s(tabs) $name page]]+1}];if {$at>=[llength [$book tabs]]} {set at end}
        $book insert $at $page -text "$name — Notes"
    }
    $book select $page;set s(showNotes) 1
    projectTabSelected
    focus [dict get [::GX::_documentEditorRecord [dict get $note editor]] source]
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesToggle {} {variable s;projectNotesShow $s(showNotes)}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesChanged {name handle receipt} {
    variable s
    if {![info exists s(notes)] || ![dict exists $s(notes) $name]} return
    set page [dict get $s(notes) $name page];set book .gxViewerDevelopment.body.center.sources
    if {$page in [$book tabs]} {$book tab $page -text "$name — Notes[expr {[dict get $receipt dirty]?{ *}:{}}]"}
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesSaved {handle receipt} {
    variable s
    set s(projectHash) [dict get $receipt source owner_revision]
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesReview {{name {}}} {
    variable s
    if {![info exists s(notes)]} {return 1}
    dict for {source note} $s(notes) {
        if {$name ne {} && $source ne $name} continue
        if {![::GX::sourceNoteEditorReview [dict get $note editor]]} {return 0}
    }
    return 1
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesDispose {name} {
    variable s
    if {![dict exists $s(notes) $name]} return
    destroy [dict get $s(notes) $name page];dict unset s(notes) $name
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesSaveAll {} {
    variable s
    dict for {name note} $s(notes) {
        set handle [dict get $note editor]
        if {[dict get [::GX::documentEditorCommand $handle inspect] dirty] && ![::GX::sourceNoteEditorSaveSafe $handle]} {return 0}
        ::GX::sourceNoteEditorSnapshot $handle
    }
    return 1
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesSourceUpdated {} {
    variable s
    if {![info exists s(notes)]} return
    dict for {name note} $s(notes) {
        if {$name ni [projectNoteSources]} continue
        ::GX::sourceNoteEditorSourceUpdated [dict get $note editor] [projectNoteRef $name] [dict create owner_revision $s(projectHash)]
    }
}
proc ::GX::ViewerDevelopmentWorkspace::projectNotesSnapshotExport {} {
    variable s
    set cap [dict get [::GX::_datasetPrivateModuleContext viewer.development_workspace] capability]
    foreach name [projectNoteSources] {
        set ref [projectNoteRef $name];set note [::GX::sourceNoteRead $cap $ref]
        if {[dict get $note state] eq {canonical}} {
            set result [::GX::sourceNoteSnapshotRef $cap $ref $note]
            ::GX::_sourceNoteEditorOwnerCommitted {} $result
            set s(projectHash) [dict get [sourceNoteOwner describe [dict create relative $name]] owner_revision]
            if {[::GX::datasetPublicationV2DictDefault $result assets_present 0]} {
                set inert [::GX::datasetPublicationV2DictDefault [dict get $result source] asset_snapshots {}]
                if {[lsort [dict keys $inert]] ne [lsort [dict keys [dict get $result assets]]]} {error {Source image snapshot closure is incomplete}}
                dict for {name resource} [dict get $result assets] {if {[dict get $inert $name sha256] ne [dict get $resource sha256]} {error {Source image snapshot identity differs}}}
            }
        }
    }
}
