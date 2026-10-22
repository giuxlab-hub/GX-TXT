# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::newExperimentDialog {} {
    variable currentSession;variable cfg;variable ui
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        tk_messageBox -icon info -title {Duplicate Experiment} -message {Open a Session to copy its preparation.};return
    }
    set w .gxNewExperiment;catch {destroy $w};toplevel $w;wm title $w {Duplicate Experiment};wm transient $w .
    set ui(newExperimentName) ""
    set pid [projectCurrentId]
    set ui(newExperimentRoot) [expr {$pid ne "" && [projectExists $pid] ? [projectSessionsRoot $pid] : $cfg(output_root)}]
    ttk::label $w.info -text "Copy preparation from [file tail $currentSession].\nThe new Experiment starts without Datasets, Workspaces or measured results.\nSafe preparation is copied; unsupported module settings reset.\nModules start disabled. Observations and graphs start empty.\nOriginal files stay unchanged." -wraplength 600
    ttk::label $w.nameLabel -text {Experiment name:};ttk::entry $w.name -textvariable ::GX::ui(newExperimentName) -width 55
    ttk::label $w.rootLabel -text {Destination root:};ttk::entry $w.root -textvariable ::GX::ui(newExperimentRoot) -width 55
    # A multiline filesystem error must not grow the dialog and push Create /
    # Cancel outside its visible area. Keep a readable, scrollable fixed region.
    text $w.status -height 4 -width 72 -wrap word -state disabled -foreground #a02020 -relief flat -background [$w cget -background]
    ttk::frame $w.buttons;ttk::button $w.buttons.create -text Create -command [list ::GX::newExperimentDialogCommit $w $currentSession]
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    grid $w.info -row 0 -column 0 -columnspan 2 -sticky ew -padx 8 -pady 8
    foreach {row label entry} {1 nameLabel name 2 rootLabel root} {grid $w.$label -row $row -column 0 -sticky e -padx 8 -pady 5;grid $w.$entry -row $row -column 1 -sticky ew -padx 8 -pady 5}
    grid $w.status -row 3 -column 0 -columnspan 2 -sticky ew -padx 8
    pack $w.buttons.create $w.buttons.cancel -side left -padx 5
    grid $w.buttons -row 4 -column 0 -columnspan 2 -pady 8;grid columnconfigure $w 1 -weight 1
    bind $w <Escape> [list destroy $w];bind $w.name <Return> [list ::GX::newExperimentDialogCommit $w $currentSession];focus $w.name
}
proc ::GX::newExperimentDialogCommit {w source} {
    variable ui
    if {$::GX::currentSession ne $source} {newExperimentDialogStatus $w {The current Session changed. Reopen Duplicate Experiment.};return}
    set drafts {}
    foreach tab {notes objective procedure observations} {
        set parent .top.nb.exp.notes.$tab
        if {[winfo exists $parent.t] && [info exists ::GX::scientificTextState($parent,mode)] && $::GX::scientificTextState($parent,mode) eq "edit"} {
            dict set drafts $tab [dict create text [scientificTextCurrent $parent] insert [$parent.t index insert] selection [$parent.t tag ranges sel] yview [lindex [$parent.t yview] 0]]
        }
    }
    if {[catch {set result [sessionExperimentClone $ui(newExperimentName) $ui(newExperimentRoot)]} err]} {newExperimentDialogStatus $w $err;return}
    if {[dict size $drafts]} {
        # Observations deliberately do not enter the duplicate. Keep the source
        # drafts in this GUI process so opening the result does not discard them.
        # This is UI memory, never another persistence authority or a source save.
        set ::GX::duplicateSourceNoteDrafts([file normalize $source]) [dict create tabs $drafts selected [.top.nb.exp.notes select]]
    }
    destroy $w
    # Drafts are already retained in the clone; this deliberate switch does
    # not save them back to the source or ask to discard them a second time.
    set ::GX::experimentCloneSwitch 1
    try {openSessionPath [dict get $result session_path]} finally {unset ::GX::experimentCloneSwitch}
    sessionPageSelect experiment
    setStatus "Experiment created: $::GX::cfg(experiment_name). Modules reset/disabled; see Session > Duplication report."

}
proc ::GX::newExperimentDialogStatus {w message} {
    $w.status configure -state normal;$w.status delete 1.0 end;$w.status insert end $message;$w.status configure -state disabled
}
# A pending note debounce must never write old text to the next Session. Flush
# only genuinely pending edits, then load the new Session's own note documents.
rename ::GX::openSessionPath ::GX::openSessionPath_before_experiment077
proc ::GX::openSessionPath {path} {
    if {![file isdirectory [file join $path channels]]} {error "The selected folder does not contain channels/: $path"}
    if {![info exists ::GX::experimentCloneSwitch] && $::GX::currentSession ne "" && [file normalize $path] ne [file normalize $::GX::currentSession]} {
        if {![sessionExperimentResolveNoteEdits]} {return $::GX::currentSession}
    }
    _experimentDocumentsFlushPending
    set result [openSessionPath_before_experiment077 $path]
    experimentDocumentsLoad $result
    if {[llength [info commands winfo]] && [winfo exists .top.nb.exp]} {
        rebuildNativeExperimentGui
        set identity [file normalize $result]
        if {[info exists ::GX::duplicateSourceNoteDrafts($identity)]} {
            set saved $::GX::duplicateSourceNoteDrafts($identity)
            dict for {tab draft} [dict get $saved tabs] {
                set parent .top.nb.exp.notes.$tab
                scientificTextEdit $parent
                $parent.t delete 1.0 end;$parent.t insert end [dict get $draft text]
                scientificTextRefresh $parent
                $parent.t mark set insert [dict get $draft insert]
                foreach {start end} [dict get $draft selection] {$parent.t tag add sel $start $end}
                $parent.t yview moveto [dict get $draft yview]
            }
            .top.nb.exp.notes select [dict get $saved selected]
            # Normal Save/Discard/Cancel owns these editors again once restored.
            unset ::GX::duplicateSourceNoteDrafts($identity)
        }
    }
    return $result
}
proc ::GX::sessionExperimentResolveNoteEdits {} {
    if {![llength [info commands winfo]] || ![winfo exists .top.nb.exp.notes]} {return 1}
    set dirty {}
    foreach tab {notes objective procedure observations} {
        set parent .top.nb.exp.notes.$tab
        if {[info exists ::GX::scientificTextState($parent,mode)] && $::GX::scientificTextState($parent,mode) eq "edit" && [scientificTextCurrent $parent] ne $::GX::scientificTextState($parent,content)} {lappend dirty $parent}
    }
    if {![llength $dirty]} {return 1}
    set choice [tk_messageBox -parent . -type yesnocancel -icon question -title {Unsaved Experiment notes} -message {Save the current Experiment's edited notes before switching Session?}]
    if {$choice eq "cancel"} {return 0}
    foreach parent $dirty {if {$choice eq "yes"} {scientificTextSave $parent} else {scientificTextCancel $parent}}
    return 1
}
