# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted in-place source-note presentation. Dataset/Registry/Project owners
# retain all persistence, identity, capability and transaction responsibilities.
namespace eval ::GX::SourceNoteEditor {variable bindings {}}
proc ::GX::sourceNoteEditorMount {parent capability sourceRef {options {}}} {
    variable ::GX::SourceNoteEditor::bindings
    set receipt [sourceNoteRead $capability $sourceRef]
    set options [dict merge {on_change {} on_saved {}} $options]
    set mount [dict create capability $capability initial [dict get $receipt text] assets [dict get $receipt assets] \
        on_command ::GX::_sourceNoteEditorPrimary on_change ::GX::_sourceNoteEditorChanged]
    if {[dict get $receipt state] eq {canonical}} {dict set mount dataset_id [dict get $receipt dataset_id]}
    set provider [_sourceNoteAssetProviderCreate $capability [dict get $receipt source_ref] $receipt]
    if {$provider ne {}} {dict set mount asset_provider [list ::GX::_sourceNoteAssetProvider $provider]}
    if {[catch {set handle [documentEditorMount $parent $mount]} message opts]} {_sourceNoteAssetProviderDelete $provider;return -options $opts $message}
    dict set bindings $handle [dict create capability $capability source_ref [dict get $receipt source_ref] receipt $receipt options $options asset_provider $provider]
    bind $parent <Destroy> +[list ::GX::_sourceNoteEditorDestroyed $handle %W $parent]
    return $handle
}
proc ::GX::_sourceNoteEditorDestroyed {handle actual parent} {
    variable ::GX::SourceNoteEditor::bindings
    if {$actual eq $parent && [dict exists $bindings $handle]} {_sourceNoteAssetProviderDelete [dict get $bindings $handle asset_provider];dict unset bindings $handle}
}
proc ::GX::_sourceNoteEditorChanged {handle receipt} {
    variable ::GX::SourceNoteEditor::bindings
    if {![dict exists $bindings $handle]} return
    set callback [dict get $bindings $handle options on_change]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $receipt]}
}
proc ::GX::sourceNoteEditorSave {handle} {
    variable ::GX::SourceNoteEditor::bindings
    variable ::GX::DocumentSource::editors
    set binding [dict get $bindings $handle];set receipt [dict get $binding receipt]
    set draft [documentEditorCommand $handle draft_get];set source [dict get $receipt source]
    set request [dict create text [dict get $draft text] assets [dict get $draft assets] expected_session [dict get $receipt session] \
        expected_owner_revision [dict get $source owner_revision] expected_authoring_revision [dict get $source authoring_revision] expected_source_sha256 [dict get $source source_sha256]]
    foreach key {revision sha256} {if {[dict exists $receipt $key] && [dict get $receipt $key] ne {}} {dict set request expected_$key [dict get $receipt $key]}}
    set saved [sourceNoteWrite [dict get $binding capability] [dict get $binding source_ref] $request]
    dict set bindings $handle receipt $saved
    dict set bindings $handle source_ref [dict get $saved source_ref]
    _sourceNoteEditorOwnerCommitted $handle $saved
    if {[dict get $saved state] eq {canonical}} {
        # Bind the exact committed receipt; a later Describe could silently
        # adopt an external update between publication and the GUI response.
        set baseline [dict get $editors $handle baseline]
        if {$baseline eq {}} {set baseline [dict create kind markdown contract document.text format md media_type text/markdown producer [_documentActor [dict get $binding capability]] immutable 0]}
        foreach key {dataset_id session revision sha256 assets metadata association can_replace} {if {[dict exists $saved $key]} {dict set baseline $key [dict get $saved $key]}}
        dict set editors $handle baseline $baseline
    }
    set live [dict get $editors $handle assets];set adopted [dict get $saved assets]
    dict for {name reference} $live {if {![dict exists $draft assets $name] || $reference ne [dict get $draft assets $name]} {dict set adopted $name $reference}}
    dict for {name reference} [dict get $draft assets] {if {![dict exists $live $name]} {dict unset adopted $name}}
    dict set editors $handle assets $adopted
    set retained {};set index 0
    dict for {name reference} $adopted {dict set retained draft[incr index] $reference}
    if {[dict get $saved state] eq {canonical}} {dict for {name reference} [dict get $saved assets] {dict set retained baseline[incr index] $reference}}
    dict set editors $handle asset_owner [datasetDocumentAssetOwnerRetain [dict get $binding capability] $retained [dict get $editors $handle asset_owner]]
    _sourceNoteEditorAssetProviderRefresh $handle
    dict set editors $handle baseline_text [dict get $draft text]
    markupSourceChanged [dict get $editors $handle source]
    # Only submitted bytes become the baseline; newer keystrokes stay dirty.
    set callback [dict get $binding options on_saved]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $saved]}
    _documentEditorChanged $handle
    return $saved
}
proc ::GX::sourceNoteEditorPublishNew {handle datasetId} {
    variable ::GX::SourceNoteEditor::bindings
    set binding [dict get $bindings $handle];set receipt [dict get $binding receipt]
    set draft [documentEditorCommand $handle draft_get]
    set request [dict create mode new dataset_id $datasetId text [dict get $draft text] assets [dict get $draft assets] expected_session [dict get $receipt session]]
    if {[dict get $receipt dataset_id] ne {}} {dict set request source_dataset_id [dict get $receipt dataset_id];dict set request source_revision [dict get $receipt revision]}
    # Generic copy is distinct; portable snapshot images are explicitly adopted
    # through the existing current-Session carrier, never silently omitted.
    set carrier {}
    try {
        if {[dict get $receipt state] ne {canonical}} {
            set materialized [sourceNoteAssetsMaterialize [dict get $binding capability] [dict get $binding source_ref] [dict get $receipt source] [dict get $receipt session]]
            set carrier [dict get $materialized owner]
            dict set request assets [dict merge [dict get $materialized assets] [dict get $draft assets]]
        }
        return [datasetDocumentWrite [dict get $binding capability] $request]
    } finally {if {$carrier ne {}} {datasetDocumentAssetOwnerClose [dict get $binding capability] $carrier}}
}
proc ::GX::_sourceNoteEditorCopyDialog {handle} {
    variable ::GX::SourceNoteEditor::bindings
    set parent [dict get [_documentEditorRecord $handle] parent];set w [winfo toplevel $parent].sourceNoteCopy
    if {[winfo exists $w]} {raise $w;return}
    uiFieldDialogCreate $w [winfo toplevel $parent] {Publish New document copy}
    dict set bindings $handle copy_id {}
    ttk::label $w.label -text {New canonical Dataset ID (the primary source note remains unchanged):} -wraplength 440
    ttk::entry $w.value -width 38
    ttk::button $w.save -text {Publish New} -command [list ::GX::_sourceNoteEditorCopyCommit $handle $w]
    ttk::button $w.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.label $w.value $w.save $w.cancel -fill x -padx 10 -pady 5
    uiTextEditingAttach $w [list $w.value]
    uiFieldDialogPresent $w $w.value 0
}
proc ::GX::_sourceNoteEditorCopyCommit {handle w} {
    if {[catch {sourceNoteEditorPublishNew $handle [$w.value get]} message]} {tk_messageBox -parent $w -icon warning -message $message;return}
    uiFieldDialogClose $w
}
proc ::GX::sourceNoteEditorSaveSafe {handle} {
    if {![catch {sourceNoteEditorSave $handle} message]} {return 1}
    set parent [winfo toplevel [dict get [_documentEditorRecord $handle] parent]]
    if {[tk_messageBox -parent $parent -icon warning -type yesno -default no -title {Note save refused; draft retained} -message "$message\n\nPublish a distinct new document copy instead? The primary source note will remain unchanged."] eq {yes}} {_sourceNoteEditorCopyDialog $handle}
    return 0
}
proc ::GX::_sourceNoteEditorPrimary {handle operation} {
    switch -- $operation {
        save_existing {sourceNoteEditorSaveSafe $handle}
        publish_new {_sourceNoteEditorCopyDialog $handle}
        zoom_in - zoom_out - zoom_reset {documentEditorCommand $handle $operation}
        default {error {Unsupported source-note primary action}}
    }
}
proc ::GX::sourceNoteEditorReview {handle} {
    if {![dict get [documentEditorCommand $handle inspect] dirty]} {return 1}
    set parent [winfo toplevel [dict get [_documentEditorRecord $handle] parent]]
    set answer [tk_messageBox -parent $parent -type yesnocancel -default cancel -icon question -title {Unsaved source note} -message {Save this source note before closing?}]
    switch -- $answer {yes {return [sourceNoteEditorSaveSafe $handle]} no {return 1} default {return 0}}
}
proc ::GX::sourceNoteEditorSourceUpdated {handle sourceRef {expected {}}} {
    variable ::GX::SourceNoteEditor::bindings
    set binding [dict get $bindings $handle]
    # Called only after this source editor's explicit successful code transaction.
    # Refresh source CAS independently; never rebase a changed canonical note.
    if {[catch {set current [sourceNoteRead [dict get $binding capability] $sourceRef]}]} {return 0}
    dict for {key value} $expected {if {[dict get $current source $key] ne $value} {return 0}}
    set old [dict get $binding receipt]
    foreach key {source source_ref} {dict set old $key [dict get $current $key]}
    dict set bindings $handle receipt $old;dict set bindings $handle source_ref [dict get $current source_ref]
    _sourceNoteEditorAssetProviderRefresh $handle
}
proc ::GX::sourceNoteEditorSnapshot {handle} {
    variable ::GX::SourceNoteEditor::bindings
    set binding [dict get $bindings $handle];set receipt [dict get $binding receipt]
    if {[dict get $receipt state] ne {canonical}} {return [dict create status local_draft assets_present 0]}
    set result [sourceNoteSnapshotRef [dict get $binding capability] [dict get $binding source_ref] $receipt]
    _sourceNoteEditorOwnerCommitted $handle $result
    set callback [dict get $binding options on_saved]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle [dict get $bindings $handle receipt]]}
    return $result
}
proc ::GX::sourceNoteSnapshotRef {capability sourceRef receipt} {
    set source [dict get $receipt source]
    set request [dict create expected_session [dict get $receipt session] expected_revision [dict get $receipt revision] expected_sha256 [dict get $receipt sha256] expected_owner_revision [dict get $source owner_revision] expected_authoring_revision [dict get $source authoring_revision] expected_source_sha256 [dict get $source source_sha256]]
    return [sourceNoteSnapshot $capability $sourceRef $request]
}
proc ::GX::scriptSourceNoteSnapshotProject {reference} {
    set metadata [scriptRegistryDescribe $reference]
    if {[dict get $metadata kind] ne {project}} {error {Choose an admitted Script Project}}
    set language [dict get $metadata language]
    if {$language ni {Python Octave}} {error {Unsupported source-note editor language}}
    set owner [expr {$language eq {Python}?{python_script}:{octave_script}}]
    set capability [dict get [_datasetPrivateModuleContext [expr {$language eq {Python}?{analysis.python_script}:{analysis.octave_script}}]] capability]
    foreach relative [dict keys [dict get $metadata project_files]] {
        set ref [dict create owner $owner reference [dict create reference $reference relative $relative]]
        set note [sourceNoteRead $capability $ref]
        if {[dict get $note state] eq {canonical}} {
            set snapshot [sourceNoteSnapshotRef $capability $ref $note]
            _sourceNoteEditorOwnerCommitted {} $snapshot
            if {[datasetPublicationV2DictDefault $snapshot assets_present 0]} {
                set inert [datasetPublicationV2DictDefault [dict get $snapshot source] asset_snapshots {}]
                if {[lsort [dict keys $inert]] ne [lsort [dict keys [dict get $snapshot assets]]]} {error {Source image snapshot closure is incomplete}}
                dict for {name resource} [dict get $snapshot assets] {if {[dict get $inert $name sha256] ne [dict get $resource sha256]} {error {Source image snapshot identity differs}}}
            }
        }
    }
}
# Fixed source-UI hook for the standard Dataset Open/source association owner.
proc ::GX::sourceNoteSourceUiOpen {sourceRef} {
    set owner [dict get $sourceRef owner];set reference [dict get $sourceRef reference]
    if {$owner eq {cpp_viewer_project}} {
        if {![llength [info commands ::GX::ViewerDevelopmentWorkspace::sourceNoteOwner]]} {error {The original C++ project editor is unavailable}}
        set source [::GX::ViewerDevelopmentWorkspace::sourceNoteOwner describe $reference]
        ::GX::ViewerDevelopmentWorkspace::projectRead [dict get $source relative]
        ::GX::ViewerDevelopmentWorkspace::projectNotesShow
        return [dict create status opened owner $owner]
    }
    switch -- $owner {
        python_script {set api ::GX::PythonScriptEditor;set ui ::GX::PythonScriptEditorUI}
        octave_script {set api ::GX::OctaveScriptEditor;set ui ::GX::OctaveScriptEditorUI}
        default {error {Source editor is unavailable}}
    }
    if {![llength [info commands ${api}::_ensureUi]]} {error {The original source-editor module is unavailable}}
    # Resolve stable identities before opening, including renamed project files.
    set source [scriptSourceNoteOwner describe $reference]
    ${api}::_ensureUi
    ${ui}::open
    ${ui}::_refreshDocuments
    upvar #0 ${ui}::ui fields
    set full [${api}::workspaceRead [dict get $source reference]]
    scriptSourceTabsOpen $fields(tabs) [dict get $source reference] $full [dict get $source relative]
    scriptSourceNotesShow $fields(tabs)
    return [dict create status opened owner $owner reference [dict get $source reference] relative [dict get $source relative]]
}
proc ::GX::_sourceNoteEditorOwnerCommitted {originHandle committed} {
    variable ::GX::SourceNoteEditor::bindings
    set source [dict get $committed source]
    dict for {handle binding} $bindings {
        if {![dict exists $binding receipt source]} continue
        set old [dict get $binding receipt source]
        if {[dict get $old owner] ne [dict get $source owner]} continue
        set same [expr {[dict get $old reference] eq [dict get $source reference]}]
        if {!$same && [dict get $old owner] eq {cpp_viewer_project} && [dict get $old owner_key] eq {} && $originHandle ne {}} {
            set same [expr {[winfo toplevel [dict get [_documentEditorRecord $handle] parent]] eq [winfo toplevel [dict get [_documentEditorRecord $originHandle] parent]]}]
        }
        if {!$same || [catch {set current [sourceNoteRead [dict get $binding capability] [dict get $binding source_ref]]}]} continue
        set actual [dict get $current source]
        # Rebase only the exact source-owner transaction just committed here.
        # A concurrent external owner update keeps the older draft CAS stale.
        set match 1
        foreach key {owner_revision authoring_revision source_revision} {if {[dict get $actual $key] ne [dict get $source $key]} {set match 0}}
        if {!$match} continue
        set receipt [dict get $binding receipt]
        dict set receipt source $actual;dict set receipt source_ref [dict get $current source_ref]
        dict set bindings $handle receipt $receipt
        dict set bindings $handle source_ref [dict get $current source_ref]
        _sourceNoteEditorAssetProviderRefresh $handle
    }
}

# Thin primary-menu presentation of the SAME common editor operations. Store
# only the active-owner resolver, never a selected note handle or capability.
namespace eval ::GX::SourceNoteEditor {variable menus {};variable menuView}
proc ::GX::sourceNoteEditorMenusAttach {edit view resolver} {
    variable ::GX::SourceNoteEditor::menus
    set key $edit
    set format $edit.note_format;menu $format -tearoff 0
    set headings $format.headings;menu $headings -tearoff 0
    foreach {operation label} {heading1 {Heading 1} heading2 {Heading 2} heading3 {Heading 3}} {$headings add command -label $label -command [list ::GX::sourceNoteEditorMenuAction $key $operation]}
    $format add cascade -label Heading -menu $headings
    foreach {operation label} {bold Bold italic Italic inline_code {Inline code} code_block {Code block} color {Text color…} bullet_list {Bullet list} numbered_list {Numbered list} table {Insert table} link {Insert link} quote {Insert quote} rule {Insert rule}} {
        $format add command -label $label -command [list ::GX::sourceNoteEditorMenuAction $key $operation]
    }
    set images $edit.note_images;menu $images -tearoff 0
    foreach {operation label} {insert_image {Insert image…} replace_image {Replace image…} remove_image {Remove image}} {$images add command -label $label -command [list ::GX::sourceNoteEditorMenuAction $key $operation]}
    $edit add separator
    $edit add cascade -label {Note format} -menu $format -state disabled
    $edit add cascade -label {Note images} -menu $images -state disabled
    set panes $view.note_panes;menu $panes -tearoff 0
    foreach {pane label} {source Source rendered {Rendered preview} outline Outline properties Properties resources Resources} {
        set ::GX::SourceNoteEditor::menuView($key,$pane) 0
        $panes add checkbutton -label $label -variable ::GX::SourceNoteEditor::menuView($key,$pane) -command [list ::GX::sourceNoteEditorMenuAction $key view_$pane]
    }
    $panes add separator
    foreach {operation label} {zoom_in {Zoom in} zoom_out {Zoom out} zoom_reset {Reset zoom} reset_layout {Reset note layout}} {$panes add command -label $label -command [list ::GX::sourceNoteEditorMenuAction $key $operation]}
    $view add separator
    $view add cascade -label {Note panes and zoom} -menu $panes -state disabled
    dict set menus $key [dict create resolver $resolver edit $edit view $view format $format headings $headings images $images panes $panes]
    foreach menu [list $edit $view $format $headings $images $panes] {
        set prior [$menu cget -postcommand]
        $menu configure -postcommand "$prior\n[list ::GX::sourceNoteEditorMenusRefresh $key]"
    }
    bind $edit <Destroy> +[list ::GX::_sourceNoteEditorMenusDestroyed $key %W $edit]
}
proc ::GX::_sourceNoteEditorMenusDestroyed {key actual original} {
    variable ::GX::SourceNoteEditor::menus
    if {$actual eq $original} {catch {dict unset menus $key};array unset ::GX::SourceNoteEditor::menuView $key,*}
}
proc ::GX::_sourceNoteEditorMenuHandle {key} {
    variable ::GX::SourceNoteEditor::menus
    variable ::GX::SourceNoteEditor::bindings
    if {![dict exists $menus $key]} {return {}}
    if {[catch {set handle [uplevel #0 [dict get $menus $key resolver]]}] || $handle eq {} || ![dict exists $bindings $handle]} {return {}}
    if {[catch {set status [documentEditorCommand $handle inspect]}] || [dict get $status status] ne {ready} || [dict get $status read_only]} {return {}}
    return $handle
}
proc ::GX::sourceNoteEditorMenusRefresh {key} {
    variable ::GX::SourceNoteEditor::menus
    variable ::GX::SourceNoteEditor::menuView
    if {![dict exists $menus $key]} return
    set binding [dict get $menus $key];set handle [_sourceNoteEditorMenuHandle $key]
    set state [expr {$handle eq {}?{disabled}:{normal}}]
    set inert 0;set empty 1
    if {$handle ne {}} {
        set record [_documentEditorRecord $handle]
        set inert [expr {[dict get $record options asset_provider] ne {}}]
        set empty [expr {![dict size [dict get $record assets]]}]
    }
    # Child postcommands run inside Tk's MenuNextMenu. Reconfiguring an
    # unchanged parent state clears its active cascade before Tk can focus it.
    # Compute final restrictions first, then update only genuinely changed states.
    foreach {parent label} {edit {Note format} edit {Note images} view {Note panes and zoom}} {
        set menu [dict get $binding $parent]
        set desired [expr {$label eq {Note images} && $inert?{disabled}:$state}]
        set current [$menu entrycget $label -state]
        if {$current eq {active}} {set current normal}
        if {$current ne $desired} {$menu entryconfigure $label -state $desired}
    }
    foreach name {format headings images panes} {
        set menu [dict get $binding $name]
        for {set index 0} {$index<=[$menu index end]} {incr index} {
            if {[$menu type $index] eq {separator}} continue
            set desired [expr {$name eq {images} && ($inert || ($index>0 && $empty))?{disabled}:$state}]
            set current [$menu entrycget $index -state]
            if {$current eq {active}} {set current normal}
            if {$current ne $desired} {$menu entryconfigure $index -state $desired}
        }
    }
    foreach pane {source rendered outline properties resources} {set menuView($key,$pane) 0}
    if {$handle ne {}} {
        foreach pane {source rendered outline properties resources} {set menuView($key,$pane) [dict get $record view $pane]}
    }
}
proc ::GX::sourceNoteEditorMenuAction {key operation} {
    if {$operation ni {heading1 heading2 heading3 bold italic inline_code code_block bullet_list numbered_list table link quote rule color insert_image replace_image remove_image view_source view_rendered view_outline view_properties view_resources zoom_in zoom_out zoom_reset reset_layout}} {error {Unsupported source-note menu operation}}
    # A posted menu can outlive a tab change; resolve again immediately before
    # invoking the shared owner so an inactive file's note is never edited.
    set handle [_sourceNoteEditorMenuHandle $key]
    if {$handle eq {}} {sourceNoteEditorMenusRefresh $key;return 0}
    _documentEditorDialogCommand $handle $operation
    sourceNoteEditorMenusRefresh $key
    return 1
}
