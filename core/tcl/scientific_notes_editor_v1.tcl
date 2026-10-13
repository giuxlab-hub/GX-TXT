# GX-TXT Reusable Scientific Notes Editor v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Scientific notes are authoritative UTF-8 GX-Markup/Markdown source. Rendered
# views are derived and may always be regenerated from the stored source.

namespace eval ::GX {
    variable scientificNotesEditorVersion 1
    variable scientificNotesCounter 0
    variable scientificNotesState
    variable instrumentNoteSummary
}

proc ::GX::scientificNotesSummary {text {limit 150}} {
    set text [string trim [regsub -all {[[:space:]]+} $text { }]]
    if {$text eq ""} { return "(empty)" }
    if {[string length $text] > $limit} { return "[string range $text 0 [expr {$limit-2}]]…" }
    return $text
}

proc ::GX::scientificNotesOpen {title sections {windowKey ""}} {
    variable scientificNotesCounter
    variable scientificNotesState
    if {$windowKey eq ""} {
        set w ".gxScientificNotes[incr scientificNotesCounter]"
    } else {
        set safe [string map {" " _ "/" _ "\\" _ "." _ ":" _} $windowKey]
        set w ".gxScientificNotes_${safe}"
    }
    catch {destroy $w}
    toplevel $w
    wm title $w $title
    wm geometry $w 1100x720
    grid rowconfigure $w 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    ttk::notebook $w.nb
    grid $w.nb -row 0 -column 0 -sticky nsew -padx 6 -pady 6
    set scientificNotesState($w,ids) {}
    foreach section $sections {
        set id [dict get $section id]
        set label [dict get $section label]
        set content [dict get $section content]
        set saveCommand [dict get $section save_command]
        set safe [string map {" " _ "/" _ "\\" _ "." _ ":" _} $id]
        set tab $w.nb.$safe
        ttk::frame $tab
        $w.nb add $tab -text $label
        set scientificNotesState($w,$id,tab) $tab
        set scientificNotesState($w,$id,label) $label
        set scientificNotesState($w,$id,content) $content
        set scientificNotesState($w,$id,save_command) $saveCommand
        lappend scientificNotesState($w,ids) $id
        scientificNotesShowView $w $id
    }
    ttk::frame $w.bottom
    ttk::label $w.bottom.mode -text "Notes open in View mode. Choose Edit only when you need to change the source."
    ttk::button $w.bottom.close -text "Close" -command [list destroy $w]
    pack $w.bottom.mode -side left -fill x -expand 1
    pack $w.bottom.close -side right
    grid $w.bottom -row 1 -column 0 -sticky ew -padx 8 -pady {0 8}
    return $w
}

proc ::GX::scientificNotesShowView {w id} {
    variable scientificNotesState
    if {![info exists scientificNotesState($w,$id,tab)]} return
    set tab $scientificNotesState($w,$id,tab)
    destroyChildren $tab
    grid rowconfigure $tab 1 -weight 1
    grid columnconfigure $tab 0 -weight 1
    ttk::frame $tab.bar
    ttk::label $tab.bar.mode -text "View mode"
    ttk::button $tab.bar.edit -text "Edit" -command [list ::GX::scientificNotesShowEdit $w $id]
    pack $tab.bar.mode -side left
    pack $tab.bar.edit -side right
    grid $tab.bar -row 0 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 4
    text $tab.view -wrap word -state disabled
    ttk::scrollbar $tab.sy -orient vertical -command [list $tab.view yview]
    $tab.view configure -yscrollcommand [list $tab.sy set]
    grid $tab.view -row 1 -column 0 -sticky nsew -padx {4 0} -pady {0 4}
    grid $tab.sy -row 1 -column 1 -sticky ns -padx {0 4} -pady {0 4}
    markupRenderStringToWidget $tab.view $scientificNotesState($w,$id,content)
}

proc ::GX::scientificNotesShowEdit {w id} {
    variable scientificNotesState
    if {![info exists scientificNotesState($w,$id,tab)]} return
    set tab $scientificNotesState($w,$id,tab)
    destroyChildren $tab
    grid rowconfigure $tab 0 -weight 1
    grid columnconfigure $tab 0 -weight 1
    ttk::frame $tab.editor
    grid $tab.editor -row 0 -column 0 -sticky nsew
    lassign [buildMarkupEditorWidget $tab.editor $scientificNotesState($w,$id,content)] source preview
    set scientificNotesState($w,$id,source) $source
    ttk::frame $tab.actions
    ttk::label $tab.actions.mode -text "Edit mode"
    ttk::button $tab.actions.cancel -text "Cancel" -command [list ::GX::scientificNotesShowView $w $id]
    ttk::button $tab.actions.save -text "Save" -command [list ::GX::scientificNotesSaveSection $w $id]
    pack $tab.actions.mode -side left
    pack $tab.actions.save $tab.actions.cancel -side right -padx 3
    grid $tab.actions -row 1 -column 0 -sticky ew -padx 4 -pady {0 4}
    focus $source
}

proc ::GX::scientificNotesSaveSection {w id} {
    variable scientificNotesState
    if {![info exists scientificNotesState($w,$id,source)]} return
    set source $scientificNotesState($w,$id,source)
    if {![winfo exists $source]} return
    set text [$source get 1.0 "end-1c"]
    set cmd $scientificNotesState($w,$id,save_command)
    if {[catch {uplevel #0 [linsert $cmd end $text]} err]} {
        tk_messageBox -parent $w -icon error -title "Scientific Notes" -message $err
        return
    }
    set scientificNotesState($w,$id,content) $text
    scientificNotesShowView $w $id
}

# Experiment intentionally keeps the established 0.9.7.67 inline notebook.
# This reusable editor remains available for Instrument Library documentation
# and instrument notes without redefining Experiment UI or persistence behavior.

proc ::GX::instrumentNoteSave {idx key text} {
    variable instruments
    variable currentSession
    if {![info exists instruments($idx,module_id)]} { error "Instrument instance is no longer available." }
    set instruments($idx,field,$key) $text
    set instrumentNoteSummary($idx,$key) [scientificNotesSummary $text 110]
    if {$currentSession ne "" && [file isdirectory $currentSession]} {
        set mdir [file join $currentSession metadata]
        file mkdir $mdir
        catch {writeManifest [file join $mdir manifest.ini]}
        catch {refreshManifestPreview}
    }
    return $text
}

proc ::GX::instrumentNotesOpen {idx key label} {
    variable instruments
    if {![info exists instruments($idx,module_id)]} { return }
    set content [expr {[info exists instruments($idx,field,$key)] ? $instruments($idx,field,$key) : ""}]
    set sections [list [dict create id instrument_notes label $label content $content save_command [list ::GX::instrumentNoteSave $idx $key]]]
    return [scientificNotesOpen "Instrument Notes — $instruments($idx,display_name)" $sections "instrument_${idx}_${key}"]
}

# Replace only descriptor fields named notes with the reusable notes window.
# Other multiline instrument fields remain ordinary multiline metadata controls.
proc ::GX::refreshNativeInstrumentationGui_before_instrument_library_v1 {} {
    variable instruments
    variable instrumentCount
    variable instrumentNoteSummary
    ::GX::refreshNativeInstrumentationGui_before_scientific_notes_v1
    set f .top.nb.instr
    if {![winfo exists $f]} return
    for {set i 1} {$i <= $instrumentCount} {incr i} {
        if {![info exists instruments($i,module_id)]} continue
        set mid $instruments($i,module_id)
        set rr 3
        foreach key [instrumentModuleFieldKeys $mid] {
            if {$key eq "notes"} {
                foreach suffix [list l$rr w$rr s$rr] { catch {destroy $f.body.i$i.$suffix} }
                set label [instrumentModuleField $mid $key label "Instrument notes"]
                set value [expr {[info exists instruments($i,field,$key)] ? $instruments($i,field,$key) : ""}]
                set instrumentNoteSummary($i,$key) [scientificNotesSummary $value 110]
                ttk::label $f.body.i$i.l$rr -text $label
                ttk::label $f.body.i$i.w$rr -textvariable ::GX::instrumentNoteSummary($i,$key) -anchor w -justify left
                ttk::button $f.body.i$i.s$rr -text "Open Notes..." -command [list ::GX::instrumentNotesOpen $i $key $label]
                grid $f.body.i$i.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 3
                grid $f.body.i$i.w$rr -row $rr -column 1 -sticky ew -padx 4 -pady 3
                grid $f.body.i$i.s$rr -row $rr -column 2 -sticky e -padx 4 -pady 3
            }
            incr rr
        }
    }
}
proc ::GX::refreshNativeInstrumentationGui {} {
    tailcall ::GX::refreshNativeInstrumentationGui_before_instrument_library_v1
}
