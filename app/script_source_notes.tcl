# SPDX-License-Identifier: GPL-3.0-or-later
# Notes pages extend the existing source notebook; code-only operations exclude
# them explicitly. Hiding forgets a retained page, never discards its draft.
proc ::GX::scriptSourceTabsPages {p} {
    variable ::GX::ScriptSourceTabs::state
    set pages {}
    foreach tab [$p.book tabs] {if {![info exists state($p,$tab,note_source)]} {lappend pages $tab}}
    return $pages
}
# Notes temporarily use the existing source region. Code-panel preferences and
# widgets stay intact; this presentation overlay is never persisted as code UI.
proc ::GX::scriptSourceNotesFocus {p visible} {
    variable ::GX::ScriptSourceTabs::state
    upvar #0 $state($p,editor)::ui ui
    set editor $ui(window);set center $editor.p.center;set work $center.work
    if {![winfo exists $work]} return
    upvar #0 ::GX::WorkspaceAssist::state layout
    set active [expr {[info exists layout($editor,noteFocus)] && $layout($editor,noteFocus)}]
    if {!!$visible==$active} return
    if {$visible} {
        # Respect a saved layout even if Notes is opened before the normal
        # deferred initial allocation has fired.
        if {[info exists layout($editor,initialTimer)] && ![catch {after info $layout($editor,initialTimer)}]} {
            after cancel $layout($editor,initialTimer);unset layout($editor,initialTimer)
            scriptWorkspaceLayoutRestore $editor
        } else {scriptWorkspaceLayoutFractions $editor}
        set saved [dict create sides [$editor.p panes] tools [expr {"$work.tools" in [$work panes]}] find [pack info $center.find]]
        foreach key {properties parameters version requiredApis fractions sourceFraction restoreSides} {dict set saved $key $layout($editor,$key)}
        set browser $editor.p.left.apiSplit
        set browserSaved {}
        foreach key {visible fraction} {if {[info exists ::GX::ApiBrowser::state($browser,$key)]} {dict set browserSaved $key $::GX::ApiBrowser::state($browser,$key)}}
        dict set saved api_browser $browserSaved
        set layout($editor,noteCodeLayout) $saved;set layout($editor,noteFocus) 1
        if {$browserSaved ne {}} {set ::GX::ApiBrowser::state($browser,visible) 0;apiBrowserToggle $editor.p.left}
        foreach key {properties parameters version requiredApis} {set layout($editor,$key) 0}
        scriptWorkspacePropertiesToggle $editor 1 0
        pack forget $center.propertiesToggle;pack forget $center.find
        foreach side {left right} {if {"$editor.p.$side" in [$editor.p panes]} {$editor.p forget $editor.p.$side}}
        if {"$work.tools" in [$work panes]} {$work forget $work.tools}
    } else {
        set saved $layout($editor,noteCodeLayout)
        # Restore the retained widgets in their existing layout owners, including
        # the same assistant notebook/drafts and code Find controls.
        pack $center.find {*}[dict get $saved find] -before $work
        foreach key {properties parameters version requiredApis fractions sourceFraction restoreSides} {set layout($editor,$key) [dict get $saved $key]}
        scriptWorkspacePropertiesToggle $editor 1 0
        foreach side {left right} {
            set pane $editor.p.$side
            if {$pane in [dict get $saved sides] && $pane ni [$editor.p panes]} {if {$side eq {left}} {$editor.p insert 0 $pane -weight 1} else {$editor.p add $pane -weight 1}}
            if {$pane ni [dict get $saved sides] && $pane in [$editor.p panes]} {$editor.p forget $pane}
        }
        if {[dict get $saved tools] && "$work.tools" ni [$work panes]} {$work add $work.tools -weight 2}
        if {![dict get $saved tools] && "$work.tools" in [$work panes]} {$work forget $work.tools}
        set browser $editor.p.left.apiSplit
        dict for {key value} [dict get $saved api_browser] {set ::GX::ApiBrowser::state($browser,$key) $value}
        if {[dict get $saved api_browser] ne {}} {apiBrowserToggle $editor.p.left}
        unset layout($editor,noteCodeLayout);set layout($editor,noteFocus) 0
    }
    scriptSourceTabsTree $p
    scriptWorkspaceViewRefresh $editor
    scriptWorkspaceLayoutSchedule $editor
}
proc ::GX::scriptSourceNotesFind {p operation} {
    variable ::GX::ScriptSourceTabs::state
    if {![scriptSourceNotesActive $p]} {return 0}
    set handle $state($p,[$p.book select],note_editor)
    if {$operation eq {focus}} {documentEditorCommand $handle find
    } else {sourceSurfaceFindCurrent [dict get [_documentEditorRecord $handle] source] $operation}
    return 1
}
proc ::GX::scriptSourceNotesActive {p} {
    variable ::GX::ScriptSourceTabs::state
    expr {[winfo exists $p.book] && [info exists state($p,[$p.book select],note_source)]}
}
proc ::GX::scriptSourceNotesRef {p tab} {
    variable ::GX::ScriptSourceTabs::state
    if {![scriptSourceTabsOwnerCurrent $p $tab]} {error {Source owner changed; retain this local draft and reopen its intended Session or User Registry before reading associated Notes}}
    set reference $state($p,$tab,reference)
    if {![regexp {^(user|session):} $reference]} {error {Save the executable source in Script Registry before attaching its note}}
    set owner [expr {$state($p,language) eq {Python}?{python_script}:{octave_script}}]
    return [dict create owner $owner reference [dict create reference $reference relative $state($p,$tab,path)]]
}
proc ::GX::scriptSourceNotesShow {p {visible 1}} {
    variable ::GX::ScriptSourceTabs::state
    set tab $state($p,active)
    if {$tab eq {}} return
    if {!$visible} {
        if {[info exists state($p,$tab,notes)]} {
            set note $state($p,$tab,notes)
            if {$note in [$p.book tabs]} {$p.book forget $note;$p.book select $tab}
        }
        set state($p,show_notes) 0;return
    }
    if {![scriptSourceTabsWritable $p]} {error {Historical source snapshots cannot acquire or edit live source notes}}
    if {![info exists state($p,$tab,notes)]} {
        set ref [scriptSourceNotesRef $p $tab]
        set note $p.book.notes[incr ::GX::ScriptSourceTabs::serial]
        ttk::frame $note
        set cap [dict get [_datasetPrivateModuleContext [expr {$state($p,language) eq {Python}?{analysis.python_script}:{analysis.octave_script}}]] capability]
        if {[catch {set handle [sourceNoteEditorMount $note.editor $cap $ref [dict create on_change [list ::GX::scriptSourceNotesChanged $p $tab] on_saved [list ::GX::scriptSourceNotesSaved $p $tab]]]} message options]} {destroy $note;return -options $options $message}
        pack $note.editor -fill both -expand 1
        set state($p,$tab,notes) $note;set state($p,$note,note_source) $tab;set state($p,$note,note_editor) $handle
        set state($p,$note,reference) $state($p,$tab,reference);set state($p,$note,path) "$state($p,$tab,path) — Notes"
        set state($p,$note,label) $state($p,$note,path)
    } else {set note $state($p,$tab,notes)}
    if {$note ni [$p.book tabs]} {
        set at [expr {[$p.book index $tab]+1}];if {$at>=[llength [$p.book tabs]]} {set at end}
        $p.book insert $at $note -text $state($p,$note,label)
    }
    $p.book select $note;set state($p,show_notes) 1
    scriptSourceTabsLayoutSchedule $p
    focus [dict get [_documentEditorRecord $state($p,$note,note_editor)] source]
}
proc ::GX::scriptSourceNotesToggle {p} {variable ::GX::ScriptSourceTabs::state;scriptSourceNotesShow $p $state($p,show_notes)}
proc ::GX::scriptSourceNotesMenu {p menu group} {
    variable ::GX::ScriptSourceTabs::state
    if {$group eq {edit}} {$menu add command -label {Edit Notes} -command [list ::GX::scriptSourceNotesSafe $p show]
    } else {
        set state($p,show_notes) 0
        $menu add checkbutton -label {Show Notes} -variable ::GX::ScriptSourceTabs::state($p,show_notes) -command [list ::GX::scriptSourceNotesSafe $p toggle]
    }
}
proc ::GX::scriptSourceNotesSafe {p operation} {
    if {[catch {switch -- $operation {show {scriptSourceNotesShow $p} toggle {scriptSourceNotesToggle $p}}} message]} {tk_messageBox -parent [winfo toplevel $p] -icon info -message $message}
}
proc ::GX::scriptSourceNotesChanged {p tab handle receipt} {
    variable ::GX::ScriptSourceTabs::state
    if {![info exists state($p,$tab,notes)]} return
    set note $state($p,$tab,notes)
    set state($p,$note,label) "$state($p,$tab,path) — Notes[expr {[dict get $receipt dirty]?{ *}:{}}]"
    if {$note in [$p.book tabs]} {$p.book tab $note -text $state($p,$note,label)}
    scriptSourceTabsLayoutSchedule $p
}
proc ::GX::scriptSourceNotesSaved {p tab handle receipt} {
    variable ::GX::ScriptSourceTabs::state
    set ref $state($p,$tab,reference)
    set group [scriptSourceTabsGroupKey $p $tab]
    if {![scriptSourceTabsOwnerCurrent $p $tab]} return
    # Notes increment Registry metadata independently of executable source SHA.
    # Refresh only that CAS field, preserving every code/metadata draft buffer.
    if {[regexp {^(user|session):} $ref]} {
        set meta [scriptRegistryDescribe $ref]
        foreach code [scriptSourceTabsPages $p] {
            if {[scriptSourceTabsGroupKey $p $code] eq $group} {dict set state($p,$code,fields) revision [dict get $meta revision];dict set state($p,$code,document) revision [dict get $meta revision]}
        }
        upvar #0 $state($p,editor)::ui ui
        if {[scriptSourceTabsGroupKey $p] eq $group} {set ui(revision) [dict get $meta revision]}
    }
}
proc ::GX::scriptSourceNotesSave {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![scriptSourceNotesActive $p]} {return 0}
    if {![scriptSourceTabsRequireOwner $p]} {return 0}
    return [sourceNoteEditorSaveSafe $state($p,[$p.book select],note_editor)]
}
proc ::GX::scriptSourceNotesSaveAll {p} {
    variable ::GX::ScriptSourceTabs::state
    foreach tab [scriptSourceTabsPages $p] {
        if {![info exists state($p,$tab,notes)]} continue
        if {![scriptSourceTabsRequireOwner $p $tab]} {return 0}
        set note $state($p,$tab,notes);set handle $state($p,$note,note_editor)
        if {[dict get [documentEditorCommand $handle inspect] dirty] && ![sourceNoteEditorSaveSafe $handle]} {return 0}
        sourceNoteEditorSnapshot $handle
    }
    return 1
}
proc ::GX::scriptSourceNotesReview {p tab} {
    variable ::GX::ScriptSourceTabs::state
    if {[info exists state($p,$tab,note_source)]} {set tab $state($p,$tab,note_source)}
    if {![info exists state($p,$tab,notes)]} {return 1}
    return [sourceNoteEditorReview $state($p,$state($p,$tab,notes),note_editor)]
}
proc ::GX::scriptSourceNotesDispose {p tab} {
    variable ::GX::ScriptSourceTabs::state
    if {![info exists state($p,$tab,notes)]} return
    set note $state($p,$tab,notes);destroy $note
    foreach key [array names state "$p,$note,*"] {unset state($key)}
    unset state($p,$tab,notes)
}
proc ::GX::scriptSourceNotesSourceUpdated {p tab {result {}}} {
    variable ::GX::ScriptSourceTabs::state
    if {![info exists state($p,$tab,notes)]} return
    set note $state($p,$tab,notes)
    set state($p,$note,reference) $state($p,$tab,reference);set state($p,$note,path) "$state($p,$tab,path) — Notes"
    set expected {}
    if {$result ne {}} {set expected [dict create owner_revision [dict get $result revision] source_revision [dict get $result sha256]]}
    sourceNoteEditorSourceUpdated $state($p,$note,note_editor) [scriptSourceNotesRef $p $tab] $expected
    scriptSourceNotesChanged $p $tab $state($p,$note,note_editor) [documentEditorCommand $state($p,$note,note_editor) inspect]
}
proc ::GX::scriptSourceNotesCopyPrepare {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![scriptSourceTabsRequireOwner $p]} {error {Source owner changed; copy was not prepared}}
    upvar #0 $state($p,editor)::ui ui
    set reference $state($p,$state($p,active),reference)
    if {![regexp {^(user|session):} $reference]} {return {}}
    set metadata [scriptRegistryDescribe $reference]
    if {[dict get $metadata sha256] ne $ui(currentSha)} {error {Source changed before Save As; original buffers retained}}
    set owner [expr {$state($p,language) eq {Python}?{python_script}:{octave_script}}]
    set capability [dict get [_datasetPrivateModuleContext [scriptAnalysisModule $state($p,language)]] capability]
    set files [expr {[dict get $metadata kind] eq {project}?[dict keys [dict get $metadata project_files]]:[list [scriptRegistrySourceName [dict get $metadata language]]]}]
    foreach relative $files {
        set ref [dict create owner $owner reference [dict create reference $reference relative $relative]]
        set note [sourceNoteRead $capability $ref]
        if {[dict get $note state] eq {canonical}} {
            set snapshot [sourceNoteSnapshotRef $capability $ref $note]
            _sourceNoteEditorOwnerCommitted {} $snapshot
            if {[datasetPublicationV2DictDefault $snapshot assets_present 0]} {
                set snapshots [datasetPublicationV2DictDefault [dict get $snapshot source] asset_snapshots {}]
                if {[lsort [dict keys $snapshots]] ne [lsort [dict keys [dict get $snapshot assets]]]} {error {Verified source-note image snapshot is incomplete; original buffers retained}}
                dict for {name resource} [dict get $snapshot assets] {if {[dict get $snapshots $name sha256] ne [dict get $resource sha256]} {error {Source-note image snapshot identity differs; original buffers retained}}}
            }
        }
    }
    set metadata [scriptRegistryDescribe $reference]
    if {[dict get $metadata sha256] ne $ui(currentSha)} {error {Source changed during the reviewed note snapshot; original buffers retained}}
    scriptSourceNotesSaved $p $state($p,active) {} {}
    set authoring [_scriptAuthoringPointer $metadata]
    return [dict create reference $reference sha256 [dict get $metadata sha256] owner_revision [dict get $metadata revision] authoring_revision [datasetPublicationV2DictDefault $authoring revision {}]]
}
proc ::GX::scriptSourceNotesCopyCommit {prepared target} {
    if {$prepared eq {}} {return $target}
    set reference "[dict get $target scope]:[dict get $target id]"
    set options [dict create expected_source_owner_revision [dict get $prepared owner_revision] expected_target_owner_revision [dict get $target revision] expected_authoring_revision [dict get $prepared authoring_revision]]
    if {[catch {scriptRegistryCopyAuthoring [dict get $prepared reference] $reference [dict get $prepared sha256] [dict get $target sha256] $options} message opts]} {
        return -options $opts "Note copy failed for new target $reference; original buffers and the reviewable target source are retained: $message"
    }
    set result [scriptRegistryDescribe $reference];dict set result reference $reference
    return $result
}
proc ::GX::scriptSourceNotesPublishCopy {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![scriptSourceNotesActive $p]} {return 0}
    _sourceNoteEditorCopyDialog $state($p,[$p.book select],note_editor)
    return 1
}

proc ::GX::scriptSourceNotesMenuHandle {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![scriptSourceNotesActive $p]} {return {}}
    return $state($p,[$p.book select],note_editor)
}
