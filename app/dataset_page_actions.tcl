# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::datasetNotesOpenSelected {} {
    variable variableDatasetChoice
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode datasetId
    if {$mode ne "imported" || $datasetId eq ""} {
        error "Select an imported Dataset before opening Dataset notes."
    }
    datasetNotesOpen $datasetId
}

proc ::GX::refreshNativeVariablesGui {} {
    ::GX::refreshNativeVariablesGui_before_dataset_page_actions
    set f .top.nb.channels
    if {![winfo exists $f.bar]} return
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode datasetId
    datasetPageBuildViews
    if {[winfo exists $f.bar.ds]} {bind $f.bar.ds <<ComboboxSelected>> ::GX::datasetPageSelectionChanged}
    datasetPageRenderSections $mode $datasetId
    datasetBrowserBuild
    grid remove $f.bar $f.summary
    catch {refreshCsvPreview}
}

# This is presentation state only. Dataset choice, catalog, schema, notes and
# mutations continue to belong to their established CORE operations.
proc ::GX::datasetPageBuildViews {} {
    set f .top.nb.channels
    if {[winfo exists $f.views]} return
    ttk::notebook $f.views
    grid $f.views -row 0 -column 0 -columnspan 2 -sticky nsew -padx 6 -pady 4
    foreach {key title} {variables Variables metadata Metadata notes Notes temporal {Temporal Sets} preview Preview help {Variables Help}} {
        ttk::frame $f.views.$key
        $f.views add $f.views.$key -text $title
    }
    set v $f.views.variables
    grid columnconfigure $v 0 -weight 1;grid rowconfigure $v 1 -weight 1
    $f.bar.save configure -text "" -image [native2DViewportGlyph save]
    .top.nb forget .top.nb.preview
    pack .top.nb.preview -in $f.views.preview -fill both -expand 1
    raise .top.nb.preview
    bind $f.views <<NotebookTabChanged>> ::GX::datasetPageTabChanged
    grid rowconfigure $f 0 -weight 1
    grid rowconfigure $f 2 -weight 0
    grid $f.c -in $v -row 1 -column 0 -sticky nsew
    grid $f.sy -in $v -row 1 -column 1 -sticky ns
    grid $f.sx -in $v -row 2 -column 0 -sticky ew
    # These established editors predate the notebook. Sibling widgets managed
    # inside its descendant frames must sit above the notebook background.
    foreach widget [list $f.c $f.sy $f.sx] {raise $widget}
    foreach button {metadata rename delete temporal help} {pack forget $f.bar.$button}
    pack $f.help -in $f.views.help -fill both -expand 1
    raise $f.help
    datasetVariablesHelpIndex

    ttk::frame $f.metadata
    ttk::frame $f.metadata.head;pack $f.metadata.head -fill x
    ttk::button $f.metadata.head.edit -text "Edit Metadata..." -command ::GX::datasetMetadataOpenSelectedFromGui
    ttk::button $f.metadata.head.verify -text "Verify RAW source..."
    ttk::treeview $f.metadata.table -columns {key value} -show headings
    foreach {key title width} {key Key 220 value Value 540} {
        $f.metadata.table heading $key -text $title
        $f.metadata.table column $key -width $width -stretch [expr {$key eq "value"}]
    }
    ttk::scrollbar $f.metadata.scroll -command [list $f.metadata.table yview]
    $f.metadata.table configure -yscrollcommand [list $f.metadata.scroll set]
    pack $f.metadata.scroll -side right -fill y
    pack $f.metadata.table -fill both -expand 1
    pack $f.metadata -in $f.views.metadata -fill both -expand 1

    ttk::frame $f.notes
    ttk::button $f.notes.edit -text "Edit Notes..." -command ::GX::datasetNotesOpenSelected
    text $f.notes.view -wrap word -cursor arrow
    ttk::scrollbar $f.notes.scroll -command [list $f.notes.view yview]
    $f.notes.view configure -yscrollcommand [list $f.notes.scroll set]
    pack $f.notes.scroll -side right -fill y
    pack $f.notes.view -fill both -expand 1
    pack $f.notes -in $f.views.notes -fill both -expand 1

    ttk::frame $f.temporalSets
    ttk::button $f.temporalSets.open -text "Open Temporal Sets..." -command ::GX::temporalSetGuiOpen
    ttk::treeview $f.temporalSets.table -columns {id type} -show headings
    $f.temporalSets.table heading id -text ID;$f.temporalSets.table heading type -text Type
    ttk::scrollbar $f.temporalSets.scroll -command [list $f.temporalSets.table yview]
    $f.temporalSets.table configure -yscrollcommand [list $f.temporalSets.scroll set]
    pack $f.temporalSets.scroll -side right -fill y
    pack $f.temporalSets.table -fill both -expand 1
    pack $f.temporalSets -in $f.views.temporal -fill both -expand 1

    menu $f.bar.actionsMenu -tearoff 0
    foreach {title command} {
        {Preview / inspect active Dataset} datasetInspectionPreviewFromVariables
        {Table pages...} {datasetPreviewOpenSelectedTable variables}
        {Edit Metadata...} datasetMetadataOpenSelectedFromGui
        {Edit Notes...} datasetNotesOpenSelected
        {Temporal Sets...} temporalSetGuiOpen
        {Move active Dataset to namespace...} datasetPageMoveActive
        {Rename active Dataset...} datasetRenameSelectedFromGui
        {Delete active Dataset...} datasetDeleteSelectedFromGui
        {Export active Dataset ZIP...} portableResourceGuiExportDataset
    } {$f.bar.actionsMenu add command -label $title -command [list ::GX::datasetPageAction {*}$command]}
    $f.bar.actionsMenu add separator
    $f.bar.actionsMenu add command -label "Import Dataset ZIP..." -command [list ::GX::portableResourceGuiImport dataset]
    $f.bar.actionsMenu add command -label "Manage namespaces..." -command ::GX::datasetNamespaceManagerOpen
    ttk::menubutton $f.bar.actions -text "Active Dataset actions" -menu $f.bar.actionsMenu
    # The Current indicator exposes this same menu above the navigator.
}

proc ::GX::datasetPageAction {operation args} {
    if {[catch {::GX::$operation {*}$args} message]} {
        tk_messageBox -parent . -title "Dataset action" -icon error -message $message
    }
}
proc ::GX::datasetPageMoveActive {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode eq "imported"} {datasetBrowserMoveDialog $id}
}

proc ::GX::datasetPageRenderSections {mode datasetId} {
    set f .top.nb.channels
    set imported [expr {$mode eq "imported"&&$datasetId ne ""}]
    foreach widget [list $f.metadata.head.edit $f.notes.edit $f.temporalSets.open] {
        $widget state [expr {$imported?"!disabled":"disabled"}]
    }
    $f.bar.actionsMenu entryconfigure 0 -state [expr {$mode in {imported pending single}?"normal":"disabled"}]
    for {set i 1} {$i<9} {incr i} {$f.bar.actionsMenu entryconfigure $i -state [expr {$imported?"normal":"disabled"}]}
    $f.metadata.table delete [$f.metadata.table children {}]
    $f.temporalSets.table delete [$f.temporalSets.table children {}]
    pack forget $f.metadata.head.verify
    set note {Activate an imported Dataset using its browser glyph or context menu.}
    if {$imported} {
        if {[datasetField $datasetId source_storage_policy copy] eq "reference"} {
            $f.metadata.head.verify configure -command [list ::GX::datasetPageVerifyRawSource $datasetId]
            pack $f.metadata.head.verify -side right -padx 4 -pady 4
        }
        set details [sessionInspectionDataset $datasetId]
        dict for {key value} [datasetMetadataRead $::GX::currentSession $datasetId] {dict set details $key $value}
        dict for {key value} $details {
            if {[llength $value]>1} {set value [join $value {, }]}
            $f.metadata.table insert {} end -values [list $key $value]
        }
        set note [datasetUserNotes $datasetId]
        foreach item [temporalSetList $datasetId] {
            $f.temporalSets.table insert {} end -values [list [dict get $item id] [dict get $item type]]
        }
    }
    if {[catch {markupRenderStringToWidget $f.notes.view $note}]} {
        $f.notes.view configure -state normal;$f.notes.view delete 1.0 end
        $f.notes.view insert 1.0 $note;$f.notes.view configure -state disabled
    }
}

proc ::GX::datasetPageVerifyRawSource {datasetId} {
    if {[catch {set result [acquisitionHandlerRawIntegrity $datasetId]} reason]} {
        tk_messageBox -icon error -title "RAW source integrity" -message $reason
        return
    }
    tk_messageBox -icon info -title "RAW source integrity" -message "[dict get $result status]\n[dict get $result path]"
}

proc ::GX::launchGui_before_import_queue {} {
    ::GX::launchGui_before_dataset_page_actions
    .top.nb tab .top.nb.channels -text Dataset
    refreshNativeVariablesGui
}

# Editors own a fixed Session/Dataset identity until Save or Cancel. A refresh
# can update consultation panes but may never retarget a live draft.
namespace eval ::GX {variable datasetPageEditors {}}
proc ::GX::datasetPageEditorBegin {section id} {
    variable datasetPageEditors
    if {[dict exists $datasetPageEditors $section]} {error {Finish or cancel the existing editor first.}}
    dict set datasetPageEditors $section [list [interactiveDocumentSessionToken] $::GX::currentSession $id]
}
proc ::GX::datasetPageEditorRequire {section} {
    variable datasetPageEditors
    lassign [dict get $datasetPageEditors $section] token session id
    if {$token ne [interactiveDocumentSessionToken] || $session ne $::GX::currentSession} {error {Session changed. Draft input is preserved; return to its Session or Cancel.}}
    if {[datasetField $id id {}] eq {}} {error {Dataset no longer exists; draft input is preserved.}}
    return $id
}
proc ::GX::datasetPageCanSwitch {choice} {
    variable datasetPageEditors
    if {$choice eq $::GX::variableDatasetChoice || ![dict size $datasetPageEditors]} {return 1}
    setStatus {Save or Cancel the open Dataset editor before activating another Dataset.} 100
    return 0
}
proc ::GX::datasetPageEditorEnd {section} {
    variable datasetPageEditors
    dict unset datasetPageEditors $section
    set f .top.nb.channels
    switch $section {
        metadata {destroy $f.metadataEditor;pack $f.metadata -in $f.views.metadata -fill both -expand 1;raise $f.metadata}
        notes {destroy $f.notesEditor;pack $f.notes -in $f.views.notes -fill both -expand 1;raise $f.notes}
        temporal {catch {destroy $f.temporal};pack $f.temporalSets -in $f.views.temporal -fill both -expand 1;raise $f.temporalSets}
    }
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    datasetPageRenderSections $mode $id
}
proc ::GX::datasetPageNotesSave {} {
    if {[catch {
        set id [datasetPageEditorRequire notes]
        datasetUserNotesSave $id [.top.nb.channels.notesEditor.editor.t get 1.0 end-1c]
    } message]} {setStatus $message 100;return 0}
    datasetPageEditorEnd notes
    return 1
}

proc ::GX::datasetPageSelectionChanged {} {
    variable datasetPageEditors
    if {[dict size $datasetPageEditors]} {
        lassign [lindex [dict values $datasetPageEditors] 0] token session id
        set ::GX::variableDatasetChoice [datasetInspectionImportedChoice $id]
        setStatus {Save or Cancel the open Dataset editor before activating another Dataset.} 100
    }
    refreshNativeVariablesGui
}

proc ::GX::datasetPagePreviewSelectionChanged {} {
    if {[datasetPageCanSwitch $::GX::csvPreviewDatasetChoice]} {set ::GX::variableDatasetChoice $::GX::csvPreviewDatasetChoice;refreshNativeVariablesGui} else {set ::GX::csvPreviewDatasetChoice $::GX::variableDatasetChoice}
    refreshCsvPreview
}
