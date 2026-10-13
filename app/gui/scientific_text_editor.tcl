# GX-TXT scientific text component. Source text is the authoritative UTF-8 value.
# This file is loaded after the CORE note and Instrument Library procedures.
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX {
    variable scientificTextState
    variable scientificTextCounter 0
}

proc ::GX::scientificTextCreate {parent initial saveCommand} {
    variable scientificTextState
    set scientificTextState($parent,content) $initial
    set scientificTextState($parent,save) $saveCommand
    set scientificTextState($parent,mode) view
    set scientificTextState($parent,find) ""
    grid columnconfigure $parent 0 -weight 1
    grid columnconfigure $parent 2 -weight 1
    grid rowconfigure $parent 2 -weight 1

    ttk::frame $parent.tb
    foreach {name caption command} [list \
        edit Edit [list ::GX::scientificTextEdit $parent] \
        save Save [list ::GX::scientificTextSave $parent] \
        cancel Cancel [list ::GX::scientificTextCancel $parent] \
        undo Undo [list ::GX::scientificTextUndo $parent] \
        redo Redo [list ::GX::scientificTextRedo $parent] \
        wrap {Wrap / No wrap} [list ::GX::markupToggleWrap $parent.t] \
        refresh {Refresh preview} [list ::GX::scientificTextRefresh $parent] \
        next {Find next} [list ::GX::scientificTextFind $parent 1] \
        previous {Find previous} [list ::GX::scientificTextFind $parent -1]] {
        ttk::button $parent.tb.$name -text $caption -command $command
    }
    ttk::entry $parent.tb.find -textvariable ::GX::scientificTextState($parent,find) -width 18
    ttk::label $parent.tb.findLabel -text "Find:"
    pack $parent.tb.edit $parent.tb.save $parent.tb.cancel $parent.tb.undo \
        $parent.tb.redo $parent.tb.wrap $parent.tb.refresh -side left -padx 2 -pady 3
    pack $parent.tb.previous $parent.tb.next $parent.tb.find $parent.tb.findLabel \
        -side right -padx 2 -pady 3
    grid $parent.tb -row 0 -column 0 -columnspan 4 -sticky ew -padx 4

    ttk::label $parent.sourceLabel -text "GX-Markup / Markdown source"
    ttk::label $parent.previewLabel -text "Rendered preview"
    grid $parent.sourceLabel -row 1 -column 0 -sticky w -padx 4
    grid $parent.previewLabel -row 1 -column 2 -sticky w -padx 4
    text $parent.t -wrap word -undo 1 -autoseparators 1 -font TkFixedFont
    ttk::scrollbar $parent.sy -orient vertical -command [list $parent.t yview]
    ttk::scrollbar $parent.sx -orient horizontal -command [list $parent.t xview]
    $parent.t configure -yscrollcommand [list $parent.sy set] -xscrollcommand [list $parent.sx set]
    text $parent.preview -wrap word -state disabled
    ttk::scrollbar $parent.psy -orient vertical -command [list $parent.preview yview]
    $parent.preview configure -yscrollcommand [list $parent.psy set]
    text $parent.view -wrap word -state disabled
    ttk::scrollbar $parent.vsy -orient vertical -command [list $parent.view yview]
    $parent.view configure -yscrollcommand [list $parent.vsy set]
    $parent.t insert 1.0 $initial
    $parent.t edit reset
    $parent.t edit modified 0
    markupConfigurePreviewTags $parent.preview
    markupConfigurePreviewTags $parent.view
    bind $parent.t <KeyRelease> [list ::GX::scientificTextRefresh $parent]
    bind $parent.t <Control-f> "[list ::GX::scientificTextFocusFind $parent]; break"
    bind $parent.t <Control-g> "[list ::GX::scientificTextFind $parent 1]; break"
    bind $parent.t <Control-Shift-G> "[list ::GX::scientificTextFind $parent -1]; break"
    bind $parent.t <Control-z> "[list ::GX::scientificTextUndo $parent]; break"
    bind $parent.t <Control-y> "[list ::GX::scientificTextRedo $parent]; break"
    bind $parent.tb.find <Return> [list ::GX::scientificTextFind $parent 1]
    bind $parent.tb.find <Shift-Return> [list ::GX::scientificTextFind $parent -1]
    scientificTextShowView $parent
    return $parent
}

proc ::GX::scientificTextShowView {parent} {
    variable scientificTextState
    if {![winfo exists $parent]} return
    set scientificTextState($parent,mode) view
    foreach child {t sy sx preview psy sourceLabel previewLabel} { grid remove $parent.$child }
    grid $parent.view -row 2 -column 0 -columnspan 3 -sticky nsew -padx {4 0} -pady 4
    grid $parent.vsy -row 2 -column 3 -sticky ns -pady 4
    markupRenderStringToWidget $parent.view $scientificTextState($parent,content)
    foreach child {edit} { $parent.tb.$child state !disabled }
    foreach child {save cancel undo redo wrap refresh} { $parent.tb.$child state disabled }
}

proc ::GX::scientificTextEdit {parent} {
    variable scientificTextState
    if {![winfo exists $parent]} return
    $parent.t delete 1.0 end
    $parent.t insert 1.0 $scientificTextState($parent,content)
    $parent.t edit reset
    $parent.t edit modified 0
    set scientificTextState($parent,mode) edit
    grid remove $parent.view $parent.vsy
    grid $parent.sourceLabel -row 1 -column 0 -sticky w -padx 4
    grid $parent.previewLabel -row 1 -column 2 -sticky w -padx 4
    grid $parent.t -row 2 -column 0 -sticky nsew -padx {4 0} -pady {0 4}
    grid $parent.sy -row 2 -column 1 -sticky ns -pady {0 4}
    grid $parent.sx -row 3 -column 0 -sticky ew -padx {4 0} -pady {0 4}
    grid $parent.preview -row 2 -column 2 -sticky nsew -padx {8 0} -pady {0 4}
    grid $parent.psy -row 2 -column 3 -sticky ns -pady {0 4}
    foreach child {edit} { $parent.tb.$child state disabled }
    foreach child {save cancel undo redo wrap refresh} { $parent.tb.$child state !disabled }
    scientificTextRefresh $parent
    focus $parent.t
}

proc ::GX::scientificTextRefresh {parent} {
    variable scientificTextState
    if {![winfo exists $parent] || $scientificTextState($parent,mode) ne "edit"} return
    markupRenderStringToWidget $parent.preview [$parent.t get 1.0 "end-1c"]
}

proc ::GX::scientificTextCurrent {parent} {
    variable scientificTextState
    if {$scientificTextState($parent,mode) eq "edit" && [winfo exists $parent.t]} {
        return [$parent.t get 1.0 "end-1c"]
    }
    return $scientificTextState($parent,content)
}

proc ::GX::scientificTextSave {parent} {
    variable scientificTextState
    if {$scientificTextState($parent,mode) ne "edit"} return
    set value [scientificTextCurrent $parent]
    set callback $scientificTextState($parent,save)
    if {[llength $callback] && [catch {uplevel #0 [linsert $callback end $value]} err]} {
        tk_messageBox -parent [winfo toplevel $parent] -icon error -title "Scientific Text" -message $err
        return -code error $err
    }
    set scientificTextState($parent,content) $value
    scientificTextShowView $parent
}

proc ::GX::scientificTextCancel {parent} {
    variable scientificTextState
    if {$scientificTextState($parent,mode) ne "edit"} return
    scientificTextShowView $parent
}

proc ::GX::scientificTextUndo {parent} { catch {$parent.t edit undo}; scientificTextRefresh $parent }
proc ::GX::scientificTextRedo {parent} { catch {$parent.t edit redo}; scientificTextRefresh $parent }
proc ::GX::scientificTextFocusFind {parent} { focus $parent.tb.find; $parent.tb.find selection range 0 end }

proc ::GX::scientificTextFind {parent direction} {
    variable scientificTextState
    set needle $scientificTextState($parent,find)
    if {$needle eq ""} { scientificTextFocusFind $parent; return "" }
    set widget [expr {$scientificTextState($parent,mode) eq "edit" ? "$parent.t" : "$parent.view"}]
    if {$direction > 0} {
        set start [$widget index "insert +1c"]
        set found [$widget search -nocase -- $needle $start end]
        if {$found eq ""} { set found [$widget search -nocase -- $needle 1.0 end] }
    } else {
        set start [$widget index insert]
        set found [$widget search -backwards -nocase -- $needle $start 1.0]
        if {$found eq ""} { set found [$widget search -backwards -nocase -- $needle end 1.0] }
    }
    if {$found eq ""} { bell; return "" }
    $widget tag remove sel 1.0 end
    $widget tag add sel $found "$found + [string length $needle] chars"
    $widget mark set insert $found
    $widget see $found
    focus $widget
    return $found
}

# The Experiment notebook retains the established four tabs and field keys.
proc ::GX::addExperimentTextTab {nb name label key} {
    variable cfg
    set tab $nb.$name
    ttk::frame $tab
    $nb add $tab -text $label
    set initial [expr {[info exists cfg($key)] ? $cfg($key) : ""}]
    scientificTextCreate $tab $initial [list ::GX::experimentDocumentSave $key]
}

# Existing Instrument notes entry points now use the same component.
proc ::GX::scientificNotesOpen {title sections {windowKey ""}} {
    variable scientificTextCounter
    if {$windowKey eq ""} {
        set w ".gxScientificText[incr scientificTextCounter]"
    } else {
        set safe [string map {" " _ "/" _ "\\" _ "." _ ":" _} $windowKey]
        set w ".gxScientificText_$safe"
    }
    catch {destroy $w}
    toplevel $w
    wm title $w $title
    wm geometry $w 1100x720
    grid rowconfigure $w 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    ttk::notebook $w.nb
    grid $w.nb -row 0 -column 0 -sticky nsew -padx 6 -pady 6
    foreach section $sections {
        set id [dict get $section id]
        set safe [string map {" " _ "/" _ "\\" _ "." _ ":" _} $id]
        set tab $w.nb.$safe
        ttk::frame $tab
        $w.nb add $tab -text [dict get $section label]
        scientificTextCreate $tab [dict get $section content] [dict get $section save_command]
    }
    ttk::button $w.close -text Close -command [list destroy $w]
    grid $w.close -row 1 -column 0 -sticky e -padx 8 -pady {0 8}
    return $w
}

# Instrument Library metadata remains one transaction at the dialog Save.
rename ::GX::instrumentLibraryEditDialog ::GX::instrumentLibraryEditDialog_before_scientific_text
proc ::GX::instrumentLibraryEditDialog {{mode new} {id ""}} {
    variable instrumentLibraryEditor
    ::GX::instrumentLibraryEditDialog_before_scientific_text $mode $id
    set w .gxInstrumentLibraryEditor
    if {![winfo exists $w]} return
    set source $instrumentLibraryEditor(notes_widget)
    set initial [$source get 1.0 "end-1c"]
    destroyChildren $w.notes.editor
    scientificTextCreate $w.notes.editor $initial {}
}

proc ::GX::instrumentLibraryEditorSave {w mode id} {
    variable instrumentLibraryEditor
    set notes [scientificTextCurrent $w.notes.editor]
    set fields [dict create]
    foreach key [instrumentModuleFieldKeys $instrumentLibraryEditor(module_id)] {
        if {$key in {role manufacturer model serial firmware notes}} continue
        if {[info exists instrumentLibraryEditor(field,$key)]} { dict set fields $key $instrumentLibraryEditor(field,$key) }
    }
    set entry [dict create display_name $instrumentLibraryEditor(display_name) module_id $instrumentLibraryEditor(module_id) category $instrumentLibraryEditor(category) manufacturer $instrumentLibraryEditor(manufacturer) model $instrumentLibraryEditor(model) serial $instrumentLibraryEditor(serial) firmware $instrumentLibraryEditor(firmware) default_role $instrumentLibraryEditor(default_role) notes $notes fields $fields]
    if {[catch {
        if {$mode eq "new"} { instrumentLibraryCreate $entry } else { instrumentLibraryUpdate $id $entry }
    } err]} {
        tk_messageBox -parent $w -icon error -title "Instrument Library" -message $err
        return
    }
    destroy $w
    catch {instrumentLibraryRefreshWindow}
}

proc ::GX::datasetNotesOpen {datasetId} {
    if {[datasetField $datasetId id {}] eq {}} {error {Activate a canonical Dataset first.}}
    datasetPageBuildViews
    if {[catch {datasetPageEditorBegin notes $datasetId} message]} {setStatus $message 100;return}
    set w .top.nb.channels.notesEditor
    pack forget .top.nb.channels.notes
    ttk::frame $w
    ttk::frame $w.editor;pack $w.editor -fill both -expand 1
    scientificTextCreate $w.editor [datasetUserNotes $datasetId] ::GX::datasetPageNotesStore
    $w.editor.tb.cancel configure -command {::GX::datasetPageEditorEnd notes}
    scientificTextEdit $w.editor
    pack $w -in .top.nb.channels.views.notes -fill both -expand 1;raise $w
    .top.nb select .top.nb.channels
    .top.nb.channels.views select .top.nb.channels.views.notes
    return $w
}
proc ::GX::datasetPageNotesStore {text} {
    set id [datasetPageEditorRequire notes]
    datasetUserNotesSave $id $text
    after idle {::GX::datasetPageEditorEnd notes}
}
