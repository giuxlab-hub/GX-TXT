# SPDX-License-Identifier: GPL-3.0-or-later
# GUI hosting only. Existing Instrument/Library/Manifest services own the data.
namespace eval ::GX {
    variable sessionInstrumentSelected 0
    variable sessionInstrumentLibraryVisible 0
    variable sessionInstrumentIdentity {}
    variable sessionInstrumentLegacyBaseline {}
    variable sessionInstrumentBrowserUpdating 0
}
proc ::GX::sessionInstrumentModel {} {
    set d [dict create count $::GX::instrumentCount]
    for {set i 1} {$i <= $::GX::instrumentCount} {incr i} {
        foreach key {enabled module_id id display_name} {dict set d $i.$key $::GX::instruments($i,$key)}
        foreach key [instrumentModuleFieldKeys $::GX::instruments($i,module_id)] {
            dict set d $i.field.$key $::GX::instruments($i,field,$key)
        }
    }
    return $d
}
proc ::GX::sessionInstrumentFlushText {} {
    if {[info exists ::GX::sessionInstrumentLoading]} return
    # Drain raw multiline edits before an existing full editor refresh destroys
    # widgets; ordinary Entry/Combobox fields already bind to Session variables.
    for {set i 1} {$i <= $::GX::instrumentCount} {incr i} {
        if {![info exists ::GX::instruments($i,module_id)]} continue
        set row 3
        foreach key [instrumentModuleFieldKeys $::GX::instruments($i,module_id)] {
            set w .top.nb.instr.body.i$i.w$row
            if {[winfo exists $w] && [winfo class $w] eq "Text"} {instrumentTextChanged $w $i $key}
            incr row
        }
    }
}
proc ::GX::sessionInstrumentNoteWindows {} {
    set out {}
    if {![llength [info commands winfo]]} {return $out}
    foreach w [winfo children .] {
        if {[string match .gxScientificText_instrument_* $w]} {lappend out $w}
    }
    return $out
}
proc ::GX::sessionInstrumentNoteParents {w} {
    if {![winfo exists $w.nb]} {return {}}
    return [$w.nb tabs]
}
proc ::GX::sessionInstrumentNotesDirty {w} {
    foreach p [sessionInstrumentNoteParents $w] {
        if {[scientificTextCurrent $p] ne $::GX::scientificTextState($p,content)} {return 1}
    }
    return 0
}
proc ::GX::sessionInstrumentSaveNotes {{window {}}} {
    set windows [expr {$window eq {} ? [sessionInstrumentNoteWindows] : [list $window]}]
    foreach w $windows {foreach p [sessionInstrumentNoteParents $w] {scientificTextSave $p}}
}
proc ::GX::sessionInstrumentCloseNotes {} {
    foreach w [sessionInstrumentNoteWindows] {destroy $w}
}
proc ::GX::sessionInstrumentNoteClose {w} {
    if {[sessionInstrumentNotesDirty $w]} {
        set answer [tk_messageBox -parent $w -type yesnocancel -icon question -title {Unsaved instrument notes} -message {Save edited instrument notes before closing?}]
        if {$answer eq "cancel"} return
        if {$answer eq "yes"} {sessionInstrumentSaveNotes $w}
    }
    destroy $w
}
rename ::GX::instrumentNotesOpen ::GX::instrumentNotesOpen_before_session081
proc ::GX::instrumentNotesOpen {idx key label} {
    set w [instrumentNotesOpen_before_session081 $idx $key $label]
    if {$w ne {} && [winfo exists $w]} {
        $w.close configure -command [list ::GX::sessionInstrumentNoteClose $w]
        wm protocol $w WM_DELETE_WINDOW [list ::GX::sessionInstrumentNoteClose $w]
    }
    return $w
}
proc ::GX::sessionInstrumentChangesPending {} {
    if {$::GX::currentSession eq {}} {return 0}
    foreach w [sessionInstrumentNoteWindows] {if {[sessionInstrumentNotesDirty $w]} {return 1}}
    sessionInstrumentFlushText
    set path [file join $::GX::currentSession metadata manifest.ini]
    if {![file isfile $path]} {return [expr {$::GX::instrumentCount>0}]}
    set saved [parseIni $path]
    if {![dict exists $saved instrument_modules.count]} {
        # Historical loaders normalize older schemas. Compare their existing
        # loaded UI values, never reinterpret or rewrite the old Manifest.
        return [expr {$::GX::sessionInstrumentLegacyBaseline ne {} && [sessionInstrumentModel] ne $::GX::sessionInstrumentLegacyBaseline}]
    }
    if {[dict get $saved instrument_modules.count] != $::GX::instrumentCount} {return 1}
    dict for {key value} [sessionInstrumentModel] {
        if {$key eq "count"} continue
        if {[dict exists $saved instrument_module_instance.$key]} {
            if {[dict get $saved instrument_module_instance.$key] ne $value} {return 1}
        } else {
            set default {}
            if {[regexp {^([0-9]+)\.field\.(.+)$} $key -> idx field]} {set default [instrumentModuleField $::GX::instruments($idx,module_id) $field default {}]}
            if {[string match *.enabled $key]} {set default 1}
            if {[string match *.module_id $key]} {set default instrument.generic}
            if {$value ne $default} {return 1}
        }
    }
    return 0
}
proc ::GX::sessionInstrumentResolveEdits {} {
    if {![llength [info commands winfo]] || ![winfo exists .top.nb.instr]} {return 1}
    if {![sessionInstrumentChangesPending]} {return 1}
    set answer [tk_messageBox -parent . -type yesnocancel -icon question -title {Unsaved Session instruments} -message {Save the current Session's instrument configuration and edited notes before leaving it?}]
    if {$answer eq "cancel"} {return 0}
    if {$answer eq "yes"} {
        saveCurrentSessionConfig
        # The established Save UI reports write failures without throwing.
        # Stay in the source if its instrument changes are still unsaved.
        if {[sessionInstrumentChangesPending]} {return 0}
    }
    # Discard is applied only when the established controller actually switches.
    return 1
}
rename ::GX::saveCurrentSessionConfig ::GX::saveCurrentSessionConfig_before_session081
proc ::GX::saveCurrentSessionConfig {} {
    if {[llength [info commands winfo]] && [winfo exists .top.nb.instr]} {
        sessionInstrumentFlushText
        sessionInstrumentSaveNotes
    }
    return [saveCurrentSessionConfig_before_session081]
}
rename ::GX::openSessionPath ::GX::openSessionPath_before_session081
proc ::GX::openSessionPath {path} {
    set old $::GX::currentSession
    if {[llength [info commands winfo]] && [winfo exists .top.nb.instr] && $old ne {} && [file normalize $path] ne [file normalize $old] && ![info exists ::GX::experimentCloneSwitch]} {
        if {![file isdirectory [file join $path channels]]} {error "The selected folder does not contain channels/: $path"}
        if {![sessionInstrumentResolveEdits]} {return $old}
    }
    set result [openSessionPath_before_session081 $path]
    if {[llength [info commands winfo]] && [winfo exists .top.nb.instr]} {
        if {$old ne $::GX::currentSession} {sessionInstrumentCloseNotes}
        set ::GX::sessionInstrumentLegacyBaseline [sessionInstrumentModel]
    }
    return $result
}
rename ::GX::loadManifestDialog ::GX::loadManifestDialog_before_session081
proc ::GX::loadManifestDialog {} {
    if {![sessionInstrumentResolveEdits]} return
    set before [sessionInstrumentModel]
    set result [loadManifestDialog_before_session081]
    if {$before ne [sessionInstrumentModel]} {sessionInstrumentCloseNotes}
    return $result
}
rename ::GX::newSessionDialogCommit ::GX::newSessionDialogCommit_before_session081
proc ::GX::newSessionDialogCommit {w} {
    if {![sessionInstrumentResolveEdits]} return
    set old $::GX::currentSession
    newSessionDialogCommit_before_session081 $w
    if {$old ne $::GX::currentSession} {sessionInstrumentCloseNotes;set ::GX::sessionInstrumentLegacyBaseline [sessionInstrumentModel]}
}
rename ::GX::removeInstrumentAndRefresh ::GX::removeInstrumentAndRefresh_before_session081
proc ::GX::removeInstrumentAndRefresh {idx} {
    # Removal renumbers array indices. Never leave a notes callback targeting a
    # different instrument after renumbering, including clean open notes windows.
    foreach w [sessionInstrumentNoteWindows] {
        if {[sessionInstrumentNotesDirty $w]} {
            set answer [tk_messageBox -parent $w -type yesnocancel -icon question -title {Unsaved instrument notes} -message {Save edited notes before removing an instrument?}]
            if {$answer eq "cancel"} return
            if {$answer eq "yes"} {sessionInstrumentSaveNotes $w}
        }
    }
    sessionInstrumentCloseNotes
    removeInstrumentAndRefresh_before_session081 $idx
}
proc ::GX::sessionInstrumentCanvasResize {width} {
    if {![winfo exists .top.nb.instr.c]} return
    .top.nb.instr.c itemconfigure body -width $width
    .top.nb.instr.c configure -scrollregion [.top.nb.instr.c bbox all]
}
proc ::GX::sessionInstrumentBrowserRefresh {} {
    set tree .top.nb.instr.browser.tree
    if {![winfo exists $tree]} return
    set ::GX::sessionInstrumentBrowserUpdating 1
    $tree delete [$tree children {}]
    for {set i 1} {$i <= $::GX::instrumentCount} {incr i} {
        $tree insert {} end -id instance:$i -text $::GX::instruments($i,display_name) -values [list $::GX::instruments($i,id) [expr {$::GX::instruments($i,enabled) ? "Enabled" : "Disabled"}]]
    }
    if {$::GX::sessionInstrumentSelected>0 && [$tree exists instance:$::GX::sessionInstrumentSelected]} {$tree selection set instance:$::GX::sessionInstrumentSelected}
    after idle {set ::GX::sessionInstrumentBrowserUpdating 0}
}
proc ::GX::sessionInstrumentShowSelected {} {
    set f .top.nb.instr
    if {![winfo exists $f.body]} return
    foreach child [winfo children $f.body] {grid remove $child}
    if {$::GX::instrumentCount==0} {
        if {[winfo exists $f.body.none]} {grid $f.body.none -row 0 -column 0 -sticky nw}
    } elseif {[winfo exists $f.body.i$::GX::sessionInstrumentSelected]} {
        grid $f.body.i$::GX::sessionInstrumentSelected -row 0 -column 0 -sticky new -padx 5 -pady 5
    }
    if {$::GX::sessionInstrumentLibraryVisible && [winfo exists .top.nb.instrLibrary]} {
        grid remove $f.c $f.sy
        grid .top.nb.instrLibrary -in $f -row 1 -column 1 -columnspan 2 -sticky nsew -padx 5 -pady 5
        raise .top.nb.instrLibrary
    } else {
        if {[winfo exists .top.nb.instrLibrary]} {grid remove .top.nb.instrLibrary}
        grid $f.c -row 1 -column 1 -sticky nsew -padx 5 -pady 5
        grid $f.sy -row 1 -column 2 -sticky ns -pady 5
        $f.c yview moveto 0
        after idle [list ::GX::sessionInstrumentCanvasResize [winfo width $f.c]]
    }
}
proc ::GX::sessionInstrumentSelect {{clicked 0}} {
    if {$::GX::sessionInstrumentBrowserUpdating} return
    set tree .top.nb.instr.browser.tree
    set items [$tree selection]
    if {[llength $items]!=1} return
    scan [lindex $items 0] instance:%d selected
    if {![info exists selected]} return
    if {$selected==$::GX::sessionInstrumentSelected && (!$clicked || !$::GX::sessionInstrumentLibraryVisible)} return
    set ::GX::sessionInstrumentSelected $selected
    set ::GX::sessionInstrumentLibraryVisible 0
    sessionInstrumentShowSelected
}
proc ::GX::sessionInstrumentLabelChanged {tree item idx args} {
    if {[winfo exists $tree] && [$tree exists $item] && [info exists ::GX::instruments($idx,display_name)] && [info exists ::GX::instruments($idx,id)] && [info exists ::GX::instruments($idx,enabled)]} {
        $tree item $item -text $::GX::instruments($idx,display_name) -values [list $::GX::instruments($idx,id) [expr {$::GX::instruments($idx,enabled) ? "Enabled" : "Disabled"}]]
    }
}
rename ::GX::refreshNativeInstrumentationGui ::GX::refreshNativeInstrumentationGui_before_session081
proc ::GX::refreshNativeInstrumentationGui {} {
    if {![llength [info commands winfo]] || ![winfo exists .top.nb.instr]} return
    sessionInstrumentFlushText
    # Avoid duplicate traces across established full refresh/load cycles.
    foreach key [array names ::GX::instruments] {
        foreach pair [trace info variable ::GX::instruments($key)] {
            lassign $pair ops command
            if {[lindex $command 0] eq "::GX::sessionInstrumentLabelChanged"} {trace remove variable ::GX::instruments($key) $ops $command}
        }
    }
    refreshNativeInstrumentationGui_before_session081
    set f .top.nb.instr
    grid remove $f.bar
    grid columnconfigure $f 0 -weight 0 -minsize 240
    grid columnconfigure $f 1 -weight 1
    grid columnconfigure $f 2 -weight 0
    grid rowconfigure $f 0 -weight 0
    ttk::frame $f.browser
    ttk::label $f.browser.title -text {Session instruments}
    ttk::treeview $f.browser.tree -columns {id state} -show {tree headings} -selectmode browse
    $f.browser.tree heading #0 -text Instrument
    $f.browser.tree heading id -text {Stable ID}
    $f.browser.tree heading state -text State
    $f.browser.tree column #0 -width 180 -stretch 1
    $f.browser.tree column id -width 90 -stretch 0
    $f.browser.tree column state -width 65 -stretch 0
    ttk::scrollbar $f.browser.sy -command [list $f.browser.tree yview]
    $f.browser.tree configure -yscrollcommand [list $f.browser.sy set]
    grid $f.browser.title -row 0 -column 0 -columnspan 2 -sticky w -padx 5 -pady 5
    grid $f.browser.tree -row 1 -column 0 -sticky nsew
    grid $f.browser.sy -row 1 -column 1 -sticky ns
    grid rowconfigure $f.browser 1 -weight 1;grid columnconfigure $f.browser 0 -weight 1
    grid $f.browser -row 1 -column 0 -sticky nsew -padx 5 -pady 5
    bind $f.browser.tree <<TreeviewSelect>> ::GX::sessionInstrumentSelect
    bind $f.browser.tree <ButtonRelease-1> {after idle {::GX::sessionInstrumentSelect 1}}
    bind $f.c <Configure> {::GX::sessionInstrumentCanvasResize %w}
    bind $f.body <Configure> {catch {.top.nb.instr.c configure -scrollregion [.top.nb.instr.c bbox all]}}
    if {$::GX::sessionInstrumentIdentity ne $::GX::currentSession} {
        set ::GX::sessionInstrumentIdentity $::GX::currentSession
        set ::GX::sessionInstrumentLegacyBaseline [sessionInstrumentModel]
        set ::GX::sessionInstrumentSelected 0
        set ::GX::sessionInstrumentLibraryVisible 0
    }
    if {$::GX::sessionInstrumentSelected<1 || $::GX::sessionInstrumentSelected>$::GX::instrumentCount} {set ::GX::sessionInstrumentSelected [expr {$::GX::instrumentCount ? 1 : 0}]}
    if {[winfo exists $f.body.none]} {$f.body.none configure -text {No Session instruments. Use Instruments > Add Instrument… or Open Library….} -wraplength 550}
    sessionInstrumentBrowserRefresh
    for {set i 1} {$i <= $::GX::instrumentCount} {incr i} {
        foreach key {display_name id enabled} {trace add variable ::GX::instruments($i,$key) write [list ::GX::sessionInstrumentLabelChanged $f.browser.tree instance:$i $i]}
    }
    sessionInstrumentShowSelected
}
proc ::GX::sessionInstrumentAddDialog {} {
    if {$::GX::currentSession eq {}} {setStatus {Open or create a Session before adding instruments.};return}
    sessionPageSelect instrumentation;.top.nb select .top.nb.sessionfiles
    set w .gxSessionInstrumentAdd
    if {[winfo exists $w]} {raise $w;return}
    toplevel $w;wm title $w {Add Instrument};wm transient $w .
    ttk::label $w.label -text {Choose an installed Instrument Module:}
    ttk::combobox $w.module -textvariable ::GX::instrumentModuleChoice -values $::GX::instrumentOrder -state readonly -width 35
    ttk::button $w.add -text Add -command [list ::GX::sessionInstrumentAdd $w]
    ttk::button $w.cancel -text Cancel -command [list destroy $w]
    grid $w.label -row 0 -column 0 -columnspan 2 -padx 10 -pady 10
    grid $w.module -row 1 -column 0 -columnspan 2 -sticky ew -padx 10 -pady 5
    grid $w.add -row 2 -column 0 -padx 8 -pady 10
    grid $w.cancel -row 2 -column 1 -padx 8 -pady 10
    bind $w <Escape> [list destroy $w];wm protocol $w WM_DELETE_WINDOW [list destroy $w]
    set ::GX::ui(sessionInstrumentAddSource) $::GX::currentSession
}
proc ::GX::sessionInstrumentAdd {w} {
    if {$::GX::currentSession ne $::GX::ui(sessionInstrumentAddSource)} {tk_messageBox -parent $w -icon info -message {The Session changed. Reopen Add Instrument.};return}
    if {[catch {set n [addInstrumentFromModule]} message]} {tk_messageBox -parent $w -icon error -message $message;return}
    set ::GX::sessionInstrumentSelected $n
    set ::GX::sessionInstrumentLibraryVisible 0
    refreshNativeInstrumentationGui;refreshNativeVariablesGui;refreshManifestPreview
    destroy $w
}
rename ::GX::instrumentLibraryOpenWindow ::GX::instrumentLibraryOpenWindow_before_session081
proc ::GX::instrumentLibraryOpenWindow {} {
    if {![llength [info commands winfo]] || ![winfo exists .top.nb.instr.c]} {return [instrumentLibraryOpenWindow_before_session081]}
    instrumentLibraryEnsureLoaded
    set w .top.nb.instrLibrary
    if {![winfo exists $w]} {
        ttk::frame $w
        instrumentLibraryBuildInterface $w ::GX::sessionInstrumentLibraryClose
        # The narrower host must keep every original action, including Close,
        # reachable at the application's supported minimum window size.
        foreach child [winfo children $w.toolbar] {pack forget $child}
        bind $w.toolbar <Configure> [list ::GX::sessionInstrumentLibraryToolbar $w.toolbar %w]
        sessionInstrumentLibraryToolbar $w.toolbar 900
    }
    set ::GX::sessionInstrumentLibraryVisible 1
    sessionPageSelect instrumentation;.top.nb select .top.nb.sessionfiles
    sessionInstrumentShowSelected
    return $w
}
proc ::GX::sessionInstrumentLibraryToolbar {bar width} {
    if {![winfo exists $bar]} return
    set row 0;set used 0;set height 32
    foreach child [winfo children $bar] {
        set needed [expr {[winfo reqwidth $child]+6}]
        if {$used && $used+$needed>max(200,$width)} {incr row;set used 0}
        place $child -x [expr {$used+3}] -y [expr {$row*$height+2}] -width [expr {$needed-6}] -height 28
        incr used $needed
    }
    $bar configure -height [expr {($row+1)*$height}]
}
rename ::GX::instrumentLibraryEditDialog ::GX::instrumentLibraryEditDialog_before_session081
proc ::GX::instrumentLibraryEditDialog {{mode new} {id ""}} {
    instrumentLibraryEditDialog_before_session081 $mode $id
    set w .gxInstrumentLibraryEditor
    if {![winfo exists $w]} return
    # The existing scientific text component needs the expandable notes row;
    # weighting the buttons instead can clip Save below the dialog viewport.
    grid rowconfigure $w 10 -weight 0
    grid rowconfigure $w [dict get [grid info $w.notes] -row] -weight 1
}
proc ::GX::sessionInstrumentLibraryClose {} {
    set ::GX::sessionInstrumentLibraryVisible 0
    sessionInstrumentShowSelected
}
rename ::GX::instrumentLibraryRefreshWindow ::GX::instrumentLibraryRefreshWindow_before_session081
proc ::GX::instrumentLibraryRefreshWindow {{w .gxInstrumentLibrary}} {
    if {$w eq ".gxInstrumentLibrary" && [winfo exists .top.nb.instrLibrary]} {set w .top.nb.instrLibrary}
    set selected [instrumentLibrarySelectedId $w]
    instrumentLibraryRefreshWindow_before_session081 $w
    if {$selected ne {} && [winfo exists $w.pw.left.tree] && [$w.pw.left.tree exists instrument:$selected]} {
        $w.pw.left.tree selection set instrument:$selected
        $w.pw.left.tree see instrument:$selected
        instrumentLibraryRenderDetails $w
    }
}
rename ::GX::instrumentLibraryRenderDetails ::GX::instrumentLibraryRenderDetails_before_session081
proc ::GX::instrumentLibraryRenderDetails {w} {
    instrumentLibraryRenderDetails_before_session081 $w
    if {$w eq ".top.nb.instrLibrary" && [winfo exists $w.details.meta]} {
        # Stable Library identities are longer than the narrower embedded pane.
        # Wrap existing labels so inspection never truncates their provenance.
        bind $w.details.meta <Configure> [list ::GX::sessionInstrumentLibraryWrap $w %w]
    }
}
proc ::GX::sessionInstrumentLibraryWrap {w width} {
    if {![winfo exists $w.details.meta]} return
    foreach label [winfo children $w.details.meta] {
        if {[string match v* [file tail [string map {. /} $label]]]} {$label configure -wraplength [expr {max(120,$width-180)}]}
    }
}
