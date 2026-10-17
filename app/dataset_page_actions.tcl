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
    # Preparing Preview never rebuilds hidden schema/metadata editors. The
    # existing tab owner refreshes their projection when they become visible.
    if {[winfo exists .top.nb.channels.views] && [.top.nb.channels.views select] eq ".top.nb.channels.views.preview"} {
        lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
        if {$mode eq "imported" && [datasetPreviewLiveEligible $id]} {
            set ::GX::ui(datasetPageDeferred) [list [interactiveDocumentSessionToken] $::GX::variableDatasetChoice]
            refreshCsvPreview
            return
        }
    }
    unset -nocomplain ::GX::ui(datasetPageDeferred)
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
    foreach {key title} {variables Variables metadata Metadata technical {Technical Details / Provenance} notes Notes temporal {Temporal Sets} preview Preview help {Variables Help}} {
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

    ttk::treeview $f.views.technical.table -columns {key value} -show headings
    foreach {key label width} {key {CORE inspection field (read-only)} 240 value Value 540} {
        $f.views.technical.table heading $key -text $label
        $f.views.technical.table column $key -width $width -stretch 1
    }
    ttk::scrollbar $f.views.technical.scroll -command [list $f.views.technical.table yview]
    $f.views.technical.table configure -yscrollcommand [list $f.views.technical.scroll set]
    pack $f.views.technical.scroll -side right -fill y
    pack $f.views.technical.table -fill both -expand 1

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
        {Coordinate units / magnification / calibration...} datasetCoordinatesOpenSelected
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
proc ::GX::datasetPageVariablesDraft {id} {
    set variables [datasetVariableSchemaV3 $id];set result {};set index 0
    foreach variable $variables {
        incr index
        foreach key {enabled canonical unit canonical_unit to_canonical from_canonical display_label semantic_role instrument_id instrument_channel value_kind value_format decimal_separator time_reference time_origin} {
            if {[info exists ::GX::inspectVar($index,$key)]} {dict set variable $key $::GX::inspectVar($index,$key)}
        }
        lappend result $variable
    }
    return $result
}
proc ::GX::datasetPageExportCurrent {format} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported" || $id eq {}} {error {Activate a canonical Dataset before exporting its current view}}
    set token [interactiveDocumentSessionToken]
    set section [lindex [split [.top.nb.channels.views select] .] end]
    set request {};set draft 0
    if {$section in {notes metadata} && [dict exists $::GX::datasetPageEditors $section]} {set draft 1}
    if {$section eq "variables" && [datasetPageVariablesDraft $id] ne [datasetVariableSchemaV3 $id]} {set draft 1}
    if {$draft} {
        set choice [tk_messageBox -parent . -type yesnocancel -default cancel -title {Export Dataset view} -message "Dataset $id — $section\nYes: export the displayed draft, without saving it.\nNo: export saved canonical content.\nCancel: create no file."]
        if {$choice eq "cancel"} return
        if {$choice eq "yes"} {
            dict set request source draft
            switch $section {
                notes {dict set request notes [.top.nb.channels.notesEditor.editor.t get 1.0 end-1c]}
                metadata {
                    dict set request metadata $::GX::datasetMetadataEditorData
                    dict set request pending_metadata [dict create key $::GX::datasetMetadataEditorKey value [.top.nb.channels.metadataEditor.edit.value get 1.0 end-1c]]
                }
                variables {dict set request variables [datasetPageVariablesDraft $id]}
            }
        }
    }
    set document [datasetInspectionSectionDocument $id $section $request]
    set extension [expr {$format eq "text" ? ".txt" : ".pdf"}]
    set path [workspaceSaveFile export_dir -title "Export Dataset $id — $section" -initialfile "[sanitize $id]-$section$extension" -defaultextension $extension -filetypes [list [list [string toupper [string range $extension 1 end]] [list $extension]]]]
    if {$path eq {}} return
    if {$token ne [interactiveDocumentSessionToken] || $::GX::variableDatasetChoice ne [datasetInspectionImportedChoice $id]} {error {Session or active Dataset changed during export; reopen the action}}
    set normalized [file normalize $path];set session [file normalize $::GX::currentSession]
    if {[string match $session/* $normalized]} {error {Choose an external destination outside the scientific Session}}
    set settings [dict create page $::GX::cfg(print_page) orientation $::GX::cfg(print_orientation) margin_mm $::GX::cfg(print_margin_mm)]
    filePublicationTextDocument $path [dict get $document text] [expr {$format eq "text" ? "text" : "pdf"}] $settings
    if {$format eq "print"} {
        set previous $::GX::cfg(print_output_pdf);set ::GX::cfg(print_output_pdf) $path
        try {printPdf} finally {set ::GX::cfg(print_output_pdf) $previous}
    }
    setStatus "Exported Dataset $id — $section: $path (no Dataset changes)" 100
}

proc ::GX::datasetPageRenderSections {mode datasetId} {
    set f .top.nb.channels
    set imported [expr {$mode eq "imported"&&$datasetId ne ""}]
    foreach widget [list $f.metadata.head.edit $f.notes.edit $f.temporalSets.open] {
        $widget state [expr {$imported?"!disabled":"disabled"}]
    }
    $f.bar.actionsMenu entryconfigure 0 -state [expr {$mode in {imported pending single}?"normal":"disabled"}]
    for {set i 1} {$i<10} {incr i} {$f.bar.actionsMenu entryconfigure $i -state [expr {$imported?"normal":"disabled"}]}
    $f.metadata.table delete [$f.metadata.table children {}]
    $f.views.technical.table delete [$f.views.technical.table children {}]
    $f.temporalSets.table delete [$f.temporalSets.table children {}]
    pack forget $f.metadata.head.verify
    set note {Activate an imported Dataset using its browser glyph or context menu.}
    if {$imported} {
        if {[datasetField $datasetId source_storage_policy copy] eq "reference"} {
            $f.metadata.head.verify configure -command [list ::GX::datasetPageVerifyRawSource $datasetId]
            pack $f.metadata.head.verify -side right -padx 4 -pady 4
        }
        datasetMetadataPageRefresh $datasetId
        dict for {key value} [sessionInspectionDataset $datasetId] {
            if {[_datasetMetadataReserved $key]} continue
            $f.views.technical.table insert {} end -values [list $key $value]
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
namespace eval ::GX {variable datasetPageEditors {};variable datasetPageEditorBaselines {}}
proc ::GX::datasetPageEditorBegin {section id} {
    variable datasetPageEditors
    if {[dict exists $datasetPageEditors $section]} {error {Finish or cancel the existing editor first.}}
    dict set datasetPageEditors $section [list [interactiveDocumentSessionToken] $::GX::currentSession $id]
    switch $section {
        metadata {dict set ::GX::datasetPageEditorBaselines $section [datasetMetadataUserFields $::GX::currentSession $id]}
        notes {dict set ::GX::datasetPageEditorBaselines $section [datasetUserNotes $id]}
        temporal {dict set ::GX::datasetPageEditorBaselines $section {}}
    }
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
    if {![dict size $datasetPageEditors]} {return 1}
    lassign [datasetInspectionParseChoice $choice] targetMode target
    set dirty {};set previous {}
    dict for {section binding} $datasetPageEditors {
        lassign $binding token session id
        if {$targetMode eq "imported" && $target eq $id} continue
        set previous $id
        if {[datasetPageEditorDirty $section]} {lappend dirty $section}
    }
    if {$previous eq {}} {return 1}
    if {$dirty ne {} && [tk_messageBox -parent . -type okcancel -default cancel -icon warning -title {Discard changes and switch Dataset} \
        -message "Dataset $previous has unsaved [join $dirty { / }] changes.\nDiscard changes and switch to $choice?\nCancel keeps every draft and Dataset $previous active."] ne "ok"} {
        set ::GX::variableDatasetChoice [datasetInspectionImportedChoice $previous]
        set ::GX::csvPreviewDatasetChoice $::GX::variableDatasetChoice
        return 0
    }
    # End ownership before assigning the new existing active choice. Consultation
    # refresh and Preview cancellation remain on their established lifecycle.
    foreach section [dict keys $datasetPageEditors] {datasetPageEditorEnd $section}
    return 1
}
proc ::GX::datasetPageMetadataEqual {left right} {
    if {[dict size $left]!=[dict size $right]} {return 0}
    dict for {key value} $left {if {![dict exists $right $key] || [dict get $right $key] ne $value} {return 0}}
    return 1
}
proc ::GX::datasetPageTemporalDraft {} {
    set draft {}
    foreach key {EditingId EditingType VarDisplay ParentDisplay Basis Label WindowSize Step Partial DurationUnit SegmentUnit SegmentLabel SegmentStart SegmentEnd Segments} {
        if {[info exists ::GX::temporalSetGui$key]} {dict set draft $key [set ::GX::temporalSetGui$key]}
    }
    return $draft
}
proc ::GX::datasetPageEditorDirty {section} {
    set baseline [dict get $::GX::datasetPageEditorBaselines $section]
    switch $section {
        notes {return [expr {[.top.nb.channels.notesEditor.editor.t get 1.0 end-1c] ne $baseline}]}
        metadata {
            if {![datasetPageMetadataEqual $baseline $::GX::datasetMetadataEditorData]} {return 1}
            set key [string trim $::GX::datasetMetadataEditorKey]
            set value [.top.nb.channels.metadataEditor.edit.value get 1.0 end-1c]
            if {$key ne {}} {
                if {![dict exists $::GX::datasetMetadataEditorData $key] || [dict get $::GX::datasetMetadataEditorData $key] ne $value} {return 1}
            } elseif {$value ne {}} {return 1}
            set bulk .top.nb.channels.metadataEditor.bulk.text
            if {[winfo exists $bulk]} {
                set text [$bulk get 1.0 end-1c]
                if {[string trim $text] ne {}} {
                    if {[catch {datasetMetadataParseText $text} parsed] || ![datasetPageMetadataEqual $baseline [dict merge $baseline $parsed]]} {return 1}
                }
            }
            return 0
        }
        temporal {
            if {![winfo exists .top.nb.channels.temporal.body.editor]} {return 0}
            return [expr {[datasetPageTemporalDraft] ne $baseline}]
        }
        default {error {Dataset editor has no semantic dirty-state adapter}}
    }
}
proc ::GX::datasetPageEditorEnd {section} {
    variable datasetPageEditors
    dict unset datasetPageEditors $section
    dict unset ::GX::datasetPageEditorBaselines $section
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
    datasetPageCanSwitch $::GX::variableDatasetChoice
    refreshNativeVariablesGui
}

proc ::GX::datasetPagePreviewSelectionChanged {} {
    if {[datasetPageCanSwitch $::GX::csvPreviewDatasetChoice]} {set ::GX::variableDatasetChoice $::GX::csvPreviewDatasetChoice;refreshNativeVariablesGui} else {set ::GX::csvPreviewDatasetChoice $::GX::variableDatasetChoice}
    refreshCsvPreview
}
