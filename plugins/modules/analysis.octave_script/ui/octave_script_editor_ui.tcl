# GX-TXT Octave Script Workspace optional Tk adapter.
# SPDX-License-Identifier: GPL-3.0-or-later

package require Tk

namespace eval ::GX::OctaveScriptEditorUI {
    variable window .gxtxt_octave_script_workspace
    variable ui
    array set ui {}
}

proc ::GX::OctaveScriptEditorUI::_setModified {{value 1}} {
    variable ui
    set ui(modified) [expr {$value ? 1 : 0}]
    _updateStatus
}

proc ::GX::OctaveScriptEditorUI::_editorModified {} {
    variable ui
    if {![info exists ui(text)] || ![winfo exists $ui(text)]} return
    if {[$ui(text) edit modified]} {
        $ui(text) edit modified 0
        _setModified 1
        _scheduleRefresh
    }
}

proc ::GX::OctaveScriptEditorUI::_propertyModified {} { _setModified 1 }

proc ::GX::OctaveScriptEditorUI::_scheduleRefresh {} {
    variable ui
    if {[info exists ui(refreshAfter)] && $ui(refreshAfter) ne ""} { catch {after cancel $ui(refreshAfter)} }
    set ui(refreshAfter) [after 120 ::GX::OctaveScriptEditorUI::_refreshEditor]
}

proc ::GX::OctaveScriptEditorUI::_refreshEditor {} {
    variable ui
    set ui(refreshAfter) ""
    if {![info exists ui(text)] || ![winfo exists $ui(text)]} return
    _updateLineNumbers
    _highlight
    _updateStatus
}

proc ::GX::OctaveScriptEditorUI::_updateLineNumbers {} {
    variable ui
    if {![winfo exists $ui(text)] || ![winfo exists $ui(lines)]} return
    set last [lindex [split [$ui(text) index "end-1c"] .] 0]
    if {$last < 1} { set last 1 }
    set data ""
    for {set i 1} {$i <= $last} {incr i} { append data "$i\n" }
    $ui(lines) configure -state normal
    $ui(lines) delete 1.0 end
    $ui(lines) insert 1.0 $data
    $ui(lines) configure -state disabled
    $ui(lines) yview moveto [lindex [$ui(text) yview] 0]
}

proc ::GX::OctaveScriptEditorUI::_tagRegexp {tag pattern} {
    variable ui
    set t $ui(text)
    set start 1.0
    while 1 {
        set count 0
        set idx [$t search -regexp -count count -- $pattern $start end]
        if {$idx eq ""} break
        if {$count <= 0} { set count 1 }
        set stop "$idx + $count chars"
        $t tag add $tag $idx $stop
        set start $stop
    }
}

proc ::GX::OctaveScriptEditorUI::_highlight {} {
    variable ui
    set t $ui(text)
    foreach tag {comment string keyword number bridge} { $t tag remove $tag 1.0 end }
    _tagRegexp comment {%[^\n]*}
    _tagRegexp string {'[^'\n]*'|"[^"\n]*"}
    _tagRegexp keyword {\m(break|case|catch|classdef|continue|do|else|elseif|end|endfor|endfunction|endif|endswitch|endwhile|for|function|global|if|otherwise|persistent|return|switch|try|until|unwind_protect|unwind_protect_cleanup|while)\M}
    _tagRegexp number {\m([0-9]+(\.[0-9]*)?|\.[0-9]+)([eEdD][+-]?[0-9]+)?\M}
    _tagRegexp bridge {\mgxtxt_[A-Za-z0-9_]+\M}
    $t tag raise string
    $t tag raise comment
}

proc ::GX::OctaveScriptEditorUI::_yscroll {first last} {
    variable ui
    if {[winfo exists $ui(vscroll)]} { $ui(vscroll) set $first $last }
    if {[winfo exists $ui(lines)]} { $ui(lines) yview moveto $first }
}

proc ::GX::OctaveScriptEditorUI::_scrollBoth {args} {
    variable ui
    $ui(text) yview {*}$args
    $ui(lines) yview moveto [lindex [$ui(text) yview] 0]
}

proc ::GX::OctaveScriptEditorUI::_updateStatus {} {
    variable ui
    if {![info exists ui(status)]} return
    set id [expr {[info exists ui(currentId)] && $ui(currentId) ne "" ? $ui(currentId) : "unsaved"}]
    set state [expr {[info exists ui(modified)] && $ui(modified) ? "modified" : "saved"}]
    set pos "Ln 1, Col 1"
    if {[info exists ui(text)] && [winfo exists $ui(text)]} {
        set parts [split [$ui(text) index insert] .]
        set pos "Ln [lindex $parts 0], Col [expr {[lindex $parts 1] + 1}]"
    }
    set ui(status) "$id  |  $state  |  $pos"
    if {[info exists ui(window)] && [winfo exists $ui(window)]} {
        set star [expr {$state eq "modified" ? " *" : ""}]
        wm title $ui(window) "Octave Script Workspace$star"
    }
}

proc ::GX::OctaveScriptEditorUI::_confirmAbandon {} {
    variable ui
    if {![info exists ui(modified)] || !$ui(modified)} { return 1 }
    set answer [tk_messageBox -parent $ui(window) -icon question -type yesnocancel -default yes -title "Unsaved script" -message "Save changes to the current script before continuing?"]
    switch -- $answer {
        yes { return [_save] }
        no { return 1 }
        default { return 0 }
    }
}

proc ::GX::OctaveScriptEditorUI::_loadDocument {documentId} {
    variable ui
    if {![_confirmAbandon]} { return 0 }
    if {[catch {set full [::GX::OctaveScriptEditor::workspaceRead $documentId]} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Open failed" -message $failure
        return 0
    }
    set ui(currentId) $documentId
    set ui(currentSha) [dict get $full sha256]
    set ui(scope) [dict get $full scope]
    set ui(scriptId) [dict get $full script_id]
    set ui(name) [dict get $full name]
    set ui(arguments) [dict get $full arguments]
    set ui(description) [dict get $full description]
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 [dict get $full code]
    $ui(text) edit reset
    $ui(text) edit modified 0
    set ui(modified) 0
    _refreshEditor
    _selectTreeId $documentId
    return 1
}

proc ::GX::OctaveScriptEditorUI::_treeSelected {} {
    variable ui
    set sel [$ui(tree) selection]
    if {[llength $sel] != 1} return
    set id [lindex $sel 0]
    if {[info exists ui(currentId)] && $ui(currentId) eq $id} return
    if {![_loadDocument $id]} { _selectTreeId $ui(currentId) }
}

proc ::GX::OctaveScriptEditorUI::_selectTreeId {documentId} {
    variable ui
    if {$documentId eq "" || ![winfo exists $ui(tree)]} return
    if {[lsearch -exact [$ui(tree) children {}] $documentId] >= 0} {
        $ui(tree) selection set $documentId
        $ui(tree) see $documentId
    }
}

proc ::GX::OctaveScriptEditorUI::_refreshDocuments {} {
    variable ui
    if {![winfo exists $ui(tree)]} return
    set current [expr {[info exists ui(currentId)] ? $ui(currentId) : ""}]
    $ui(tree) delete [$ui(tree) children {}]
    foreach item [::GX::OctaveScriptEditor::workspaceList] {
        set id [dict get $item reference]
        $ui(tree) insert {} end -id $id -values [list [dict get $item name] $id [dict get $item updated_at]]
    }
    if {$current ne ""} { _selectTreeId $current }
}

proc ::GX::OctaveScriptEditorUI::_new {} {
    variable ui
    if {![_confirmAbandon]} return
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(scope) session
    set ui(scriptId) ""
    set ui(name) "Untitled script"
    set ui(arguments) ""
    set ui(description) ""
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 [::GX::OctaveScriptEditor::defaultCode]
    $ui(text) edit reset
    $ui(text) edit modified 0
    set ui(modified) 1
    $ui(tree) selection remove [$ui(tree) selection]
    _refreshEditor
    focus $ui(text)
}

proc ::GX::OctaveScriptEditorUI::_save {} {
    variable ui
    set name [string trim $ui(name)]
    if {$name eq ""} {
        tk_messageBox -parent $ui(window) -icon error -title "Script name" -message "Script name is required."
        return 0
    }
    set code [$ui(text) get 1.0 "end-1c"]
    set command [list ::GX::OctaveScriptEditor::workspaceSave $ui(currentId) $ui(currentSha) $ui(scope) $ui(scriptId) $name $ui(description) $code]
    if {[catch {set result [uplevel #0 $command]} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Save failed" -message $failure
        return 0
    }
    set ui(currentId) [dict get $result reference]
    set ui(currentSha) [dict get $result sha256]
    set ui(modified) 0
    _refreshDocuments
    _selectTreeId $ui(currentId)
    _updateStatus
    return 1
}

proc ::GX::OctaveScriptEditorUI::_saveCopy {} {
    variable ui
    if {$ui(scope) eq "legacy"} {set ui(scope) session}
    set name [string trim $ui(name)]
    if {$name eq ""} { set name "Untitled script" }
    set copyName "$name (copy)"
    set code [$ui(text) get 1.0 "end-1c"]
    set base [expr {$ui(scriptId) eq "" ? "script" : $ui(scriptId)}]
    set suffix 2
    while {[lsearch -exact [lmap m [::GX::scriptRegistryList $ui(scope)] {dict get $m id}] "${base}_$suffix"] >= 0} {incr suffix}
    set ui(scriptId) "${base}_$suffix"
    if {[catch {set result [::GX::OctaveScriptEditor::workspaceSave "" "" $ui(scope) $ui(scriptId) $copyName $ui(description) $code]} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Save copy failed" -message $failure
        return
    }
    set ui(currentId) [dict get $result reference]
    set ui(currentSha) [dict get $result sha256]
    set ui(name) $copyName
    set ui(modified) 0
    _refreshDocuments
    _selectTreeId $ui(currentId)
    _updateStatus
}

proc ::GX::OctaveScriptEditorUI::_registerLegacy {scope} {
    variable ui
    if {![string match legacy:* $ui(currentId)]} {
        tk_messageBox -parent $ui(window) -icon info -message "Select a legacy Interactive Document to convert."
        return
    }
    set ui(scope) $scope
    set candidate [string tolower [string trim $ui(name)]]
    regsub -all {[^a-z0-9_.-]} $candidate _ candidate
    if {![regexp {^[a-z]} $candidate]} {set candidate "script_$candidate"}
    set ui(scriptId) $candidate
    _save
}

proc ::GX::OctaveScriptEditorUI::_delete {} {
    variable ui
    if {$ui(currentId) eq ""} return
    set answer [tk_messageBox -parent $ui(window) -icon warning -type yesno -default no -title "Delete script" -message "Delete '$ui(name)' ($ui(currentId))?"]
    if {$answer ne "yes"} return
    if {[catch {::GX::OctaveScriptEditor::workspaceDelete $ui(currentId) $ui(currentSha)} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Delete failed" -message $failure
        return
    }
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(scriptId) ""
    set ui(scope) session
    set ui(modified) 0
    _refreshDocuments
    _new
}

proc ::GX::OctaveScriptEditorUI::_import {} {
    variable ui
    if {![_confirmAbandon]} return
    set path [tk_getOpenFile -parent $ui(window) -title "Import GNU Octave script" -filetypes {{{GNU Octave scripts} {.m}} {{All files} {*}}}]
    if {$path eq ""} return
    if {[catch {
        set fd [::open $path r]
        fconfigure $fd -encoding utf-8 -translation auto
        set code [read $fd]
        close $fd
    } failure]} {
        catch {close $fd}
        tk_messageBox -parent $ui(window) -icon error -title "Import failed" -message $failure
        return
    }
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(scriptId) ""
    set ui(scope) session
    set ui(name) [file tail [file rootname $path]]
    set ui(arguments) ""
    set ui(description) "Imported from [file tail $path]. The registered script is independent of the original file."
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 $code
    $ui(text) edit reset
    $ui(text) edit modified 0
    set ui(modified) 1
    _refreshEditor
}

proc ::GX::OctaveScriptEditorUI::_export {} {
    variable ui
    set initial [string map {"/" "_" "\\" "_" ":" "_"} [string trim $ui(name)]]
    if {$initial eq ""} { set initial "script" }
    if {![string match *.m $initial]} { append initial .m }
    set path [tk_getSaveFile -parent $ui(window) -title "Export GNU Octave script" -defaultextension .m -initialfile $initial -filetypes {{{GNU Octave scripts} {.m}} {{All files} {*}}}]
    if {$path eq ""} return
    if {[catch {
        set fd [::open $path w]
        fconfigure $fd -encoding utf-8 -translation lf
        puts -nonewline $fd [$ui(text) get 1.0 "end-1c"]
        close $fd
    } failure]} {
        catch {close $fd}
        tk_messageBox -parent $ui(window) -icon error -title "Export failed" -message $failure
        return
    }
    set ui(status) "Exported to [file tail $path]"
    after 1800 ::GX::OctaveScriptEditorUI::_updateStatus
}

proc ::GX::OctaveScriptEditorUI::_copyId {} {
    variable ui
    if {$ui(currentId) eq ""} return
    clipboard clear -displayof $ui(window)
    clipboard append -displayof $ui(window) $ui(currentId)
    set ui(status) "Copied document ID $ui(currentId)"
    after 1200 ::GX::OctaveScriptEditorUI::_updateStatus
}

proc ::GX::OctaveScriptEditorUI::_find {{direction forward}} {
    variable ui
    set pattern $ui(find)
    if {$pattern eq ""} return
    set t $ui(text)
    $t tag remove search_hit 1.0 end
    if {$direction eq "backward"} {
        set start [$t index "insert - 1c"]
        set idx [$t search -backwards -nocase -- $pattern $start 1.0]
        if {$idx eq ""} { set idx [$t search -backwards -nocase -- $pattern end 1.0] }
    } else {
        set start [$t index "insert + 1c"]
        set idx [$t search -nocase -- $pattern $start end]
        if {$idx eq ""} { set idx [$t search -nocase -- $pattern 1.0 end] }
    }
    if {$idx eq ""} { bell; return }
    set stop "$idx + [string length $pattern] chars"
    $t tag add search_hit $idx $stop
    $t mark set insert $stop
    $t see $idx
    focus $t
    _updateStatus
}

proc ::GX::OctaveScriptEditorUI::_gotoLineDialog {} {
    variable ui
    set d $ui(window).goto
    catch {destroy $d}
    toplevel $d
    wm title $d "Go to line"
    wm transient $d $ui(window)
    set ui(gotoLine) ""
    ttk::label $d.l -text "Line:"
    ttk::entry $d.e -textvariable ::GX::OctaveScriptEditorUI::ui(gotoLine) -width 12
    ttk::button $d.ok -text "Go" -command ::GX::OctaveScriptEditorUI::_gotoLineApply
    ttk::button $d.cancel -text "Cancel" -command [list destroy $d]
    grid $d.l $d.e -padx 6 -pady 8
    grid $d.ok $d.cancel -padx 6 -pady {0 8}
    focus $d.e
    bind $d.e <Return> ::GX::OctaveScriptEditorUI::_gotoLineApply
}

proc ::GX::OctaveScriptEditorUI::_gotoLineApply {} {
    variable ui
    set d $ui(window).goto
    set n [string trim $ui(gotoLine)]
    if {![string is integer -strict $n] || $n < 1} { bell; return }
    set last [lindex [split [$ui(text) index "end-1c"] .] 0]
    if {$n > $last} { set n $last }
    $ui(text) mark set insert "$n.0"
    $ui(text) see "$n.0"
    focus $ui(text)
    catch {destroy $d}
    _updateStatus
}

proc ::GX::OctaveScriptEditorUI::_insertSnippet {} {
    variable ui
    switch -- $ui(snippet) {
        "Context" { set code "ctx = gxtxt_context();\ndisp(ctx);\n" }
        "Discover APIs" { set code "apis = gxtxt_api_list();\nfprintf('Script-callable GX-TXT APIs: %d\\n', numel(apis));\ndisp(apis);\n" }
        "Require API" { set code "api_id = 'SOME_PUBLIC_API_v1';\nif (!gxtxt_api_has(api_id))\n  error('Required GX-TXT API is unavailable: %s', api_id);\nendif\n" }
        "Describe API" { set code "description = gxtxt_api_describe('SOME_PUBLIC_API_v1');\ndisp(description);\n" }
        "Call API" { set code "request = struct();\nresult = gxtxt_api_call('SOME_PUBLIC_API_v1', 'documented_operation', {request});\ndisp(result);\n" }
        default { return }
    }
    $ui(text) insert insert $code
    _setModified 1
    _scheduleRefresh
}

proc ::GX::OctaveScriptEditorUI::_bridgeHelp {} {
    variable ui
    set d $ui(window).bridgehelp
    catch {destroy $d}
    toplevel $d
    wm title $d "GX-TXT Octave Script Bridge"
    wm transient $d $ui(window)
    text $d.t -wrap word -width 90 -height 28 -font TkFixedFont -padx 10 -pady 10
    ttk::scrollbar $d.s -orient vertical -command [list $d.t yview]
    $d.t configure -yscrollcommand [list $d.s set]
    pack $d.s -side right -fill y
    pack $d.t -side left -fill both -expand 1
    set help {OCTAVE_SCRIPT_BRIDGE_API_v1

The bridge is generic. Read the current manual of the public GX-TXT API you want to use, then reach its script-callable operations with:

  gxtxt_bridge_info()
  gxtxt_api_list()
  gxtxt_api_has(api_id)
  gxtxt_api_describe(api_id)
  gxtxt_api_has_operation(api_id, operation)
  gxtxt_api_call(api_id, operation, args)
  gxtxt_context()

Typical pattern:

  ctx = gxtxt_context();
  api_id = 'SOME_PUBLIC_API_v1';
  if (!gxtxt_api_has(api_id))
    error('Required API is unavailable: %s', api_id);
  endif
  d = gxtxt_api_describe(api_id);
  request = struct();
  result = gxtxt_api_call(api_id, 'documented_operation', {request});

Do not call private ::GX commands, open Dataset registry files, or depend on CORE filesystem layout from a research script.

The bridge is not a sandbox. Ordinary GNU Octave filesystem/process capabilities remain available according to the configured runtime environment.}
    $d.t insert 1.0 $help
    $d.t configure -state disabled
}

proc ::GX::OctaveScriptEditorUI::_close {} {
    variable ui
    if {![_confirmAbandon]} return
    catch {destroy $ui(window)}
}

proc ::GX::OctaveScriptEditorUI::_build {} {
    variable ui
    variable window
    set w $window
    set ui(window) $w
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(modified) 0
    set ui(name) ""
    set ui(scope) session
    set ui(scriptId) ""
    set ui(arguments) ""
    set ui(description) ""
    set ui(find) ""
    set ui(snippet) "Context"
    set ui(status) ""
    set ui(refreshAfter) ""

    toplevel $w
    wm title $w "Octave Script Workspace"
    wm geometry $w 1180x760
    wm minsize $w 900 560
    wm protocol $w WM_DELETE_WINDOW ::GX::OctaveScriptEditorUI::_close

    ttk::frame $w.toolbar -padding {8 6}
    pack $w.toolbar -side top -fill x
    set column 0
    foreach spec {
        {new New ::GX::OctaveScriptEditorUI::_new}
        {import {Import .m...} ::GX::OctaveScriptEditorUI::_import}
        {save Save ::GX::OctaveScriptEditorUI::_save}
        {copy {Save copy} ::GX::OctaveScriptEditorUI::_saveCopy}
        {export {Export .m...} ::GX::OctaveScriptEditorUI::_export}
        {delete Delete ::GX::OctaveScriptEditorUI::_delete}
        {copyid {Copy ID} ::GX::OctaveScriptEditorUI::_copyId}
    } {
        lassign $spec name label cmd
        ttk::button $w.toolbar.$name -text $label -command $cmd
        grid $w.toolbar.$name -row 0 -column $column -sticky w -padx {0 5} -pady {0 4}
        incr column
    }
    ttk::button $w.toolbar.registerSession -text "Register legacy as Session..." -command {::GX::OctaveScriptEditorUI::_registerLegacy session}
    ttk::button $w.toolbar.registerUser -text "Register legacy as User..." -command {::GX::OctaveScriptEditorUI::_registerLegacy user}
    grid $w.toolbar.registerSession -row 1 -column 0 -columnspan 2 -sticky w -padx {0 5}
    grid $w.toolbar.registerUser -row 1 -column 2 -columnspan 2 -sticky w -padx {0 5}
    ttk::button $w.toolbar.goto -text "Go to line..." -command ::GX::OctaveScriptEditorUI::_gotoLineDialog
    ttk::button $w.toolbar.help -text "Bridge help" -command ::GX::OctaveScriptEditorUI::_bridgeHelp
    grid $w.toolbar.goto -row 1 -column 4 -sticky w -padx {0 5}
    grid $w.toolbar.help -row 1 -column 5 -sticky w -padx {0 5}

    ttk::panedwindow $w.p -orient horizontal
    pack $w.p -side top -fill both -expand 1 -padx 8 -pady {0 6}
    ttk::frame $w.p.left -padding 4
    ttk::frame $w.p.center -padding 4
    ttk::frame $w.p.right -padding 4
    $w.p add $w.p.left -weight 1
    $w.p add $w.p.center -weight 5
    $w.p add $w.p.right -weight 2

    ttk::label $w.p.left.title -text "Registered scripts and legacy documents"
    pack $w.p.left.title -side top -anchor w -pady {0 4}
    ttk::treeview $w.p.left.tree -columns {name id updated} -show headings -selectmode browse -height 20
    set ui(tree) $w.p.left.tree
    foreach {c label width stretch} {name Name 160 1 id ID 78 0 updated Updated 125 0} {
        $ui(tree) heading $c -text $label
        $ui(tree) column $c -width $width -stretch $stretch
    }
    ttk::scrollbar $w.p.left.ts -orient vertical -command [list $ui(tree) yview]
    $ui(tree) configure -yscrollcommand [list $w.p.left.ts set]
    pack $w.p.left.ts -side right -fill y
    pack $ui(tree) -side left -fill both -expand 1
    bind $ui(tree) <<TreeviewSelect>> ::GX::OctaveScriptEditorUI::_treeSelected

    ttk::frame $w.p.center.props
    pack $w.p.center.props -side top -fill x -pady {0 5}
    ttk::label $w.p.center.props.sl -text "Scope:"
    ttk::combobox $w.p.center.props.se -state readonly -values {session user} -textvariable ::GX::OctaveScriptEditorUI::ui(scope) -width 10
    ttk::label $w.p.center.props.il -text "Script ID:"
    ttk::entry $w.p.center.props.ie -textvariable ::GX::OctaveScriptEditorUI::ui(scriptId) -width 20
    grid $w.p.center.props.sl $w.p.center.props.se $w.p.center.props.il $w.p.center.props.ie -sticky ew -padx {0 6}
    ttk::label $w.p.center.props.nl -text "Name:"
    ttk::entry $w.p.center.props.ne -textvariable ::GX::OctaveScriptEditorUI::ui(name) -width 30
    ttk::label $w.p.center.props.al -text "Default arguments:"
    ttk::entry $w.p.center.props.ae -textvariable ::GX::OctaveScriptEditorUI::ui(arguments) -width 36
    grid $w.p.center.props.nl $w.p.center.props.ne $w.p.center.props.al $w.p.center.props.ae -sticky ew -padx {0 6}
    grid columnconfigure $w.p.center.props 1 -weight 1
    grid columnconfigure $w.p.center.props 3 -weight 1
    bind $w.p.center.props.ne <KeyRelease> ::GX::OctaveScriptEditorUI::_propertyModified
    bind $w.p.center.props.ae <KeyRelease> ::GX::OctaveScriptEditorUI::_propertyModified

    ttk::frame $w.p.center.desc
    pack $w.p.center.desc -side top -fill x -pady {0 5}
    ttk::label $w.p.center.desc.l -text "Description:"
    ttk::entry $w.p.center.desc.e -textvariable ::GX::OctaveScriptEditorUI::ui(description)
    pack $w.p.center.desc.l -side left -padx {0 6}
    pack $w.p.center.desc.e -side left -fill x -expand 1
    bind $w.p.center.desc.e <KeyRelease> ::GX::OctaveScriptEditorUI::_propertyModified

    ttk::frame $w.p.center.edit
    pack $w.p.center.edit -side top -fill both -expand 1
    text $w.p.center.edit.lines -width 6 -state disabled -takefocus 0 -wrap none -font TkFixedFont -background #f0f0f0 -foreground #666666 -padx 4 -pady 4
    text $w.p.center.edit.text -undo 1 -autoseparators 1 -maxundo 0 -wrap none -font TkFixedFont -tabs {32} -padx 5 -pady 4
    ttk::scrollbar $w.p.center.edit.v -orient vertical -command ::GX::OctaveScriptEditorUI::_scrollBoth
    ttk::scrollbar $w.p.center.edit.h -orient horizontal -command [list $w.p.center.edit.text xview]
    set ui(lines) $w.p.center.edit.lines
    set ui(text) $w.p.center.edit.text
    set ui(vscroll) $w.p.center.edit.v
    $ui(text) configure -yscrollcommand ::GX::OctaveScriptEditorUI::_yscroll -xscrollcommand [list $w.p.center.edit.h set]
    grid $ui(lines) -row 0 -column 0 -sticky ns
    grid $ui(text) -row 0 -column 1 -sticky nsew
    grid $w.p.center.edit.v -row 0 -column 2 -sticky ns
    grid $w.p.center.edit.h -row 1 -column 1 -sticky ew
    grid rowconfigure $w.p.center.edit 0 -weight 1
    grid columnconfigure $w.p.center.edit 1 -weight 1
    $ui(text) tag configure comment -foreground #6a737d
    $ui(text) tag configure string -foreground #a31515
    $ui(text) tag configure keyword -foreground #0000aa
    $ui(text) tag configure number -foreground #7a3e9d
    $ui(text) tag configure bridge -foreground #006b54
    $ui(text) tag configure search_hit -background #fff2a8
    bind $ui(text) <<Modified>> ::GX::OctaveScriptEditorUI::_editorModified
    bind $ui(text) <KeyRelease> ::GX::OctaveScriptEditorUI::_updateStatus
    bind $ui(text) <ButtonRelease-1> ::GX::OctaveScriptEditorUI::_updateStatus

    ttk::frame $w.p.center.find
    pack $w.p.center.find -side bottom -fill x -pady {5 0}
    ttk::label $w.p.center.find.l -text "Find:"
    ttk::entry $w.p.center.find.e -textvariable ::GX::OctaveScriptEditorUI::ui(find) -width 28
    ttk::button $w.p.center.find.prev -text "Previous" -command {::GX::OctaveScriptEditorUI::_find backward}
    ttk::button $w.p.center.find.next -text "Next" -command {::GX::OctaveScriptEditorUI::_find forward}
    pack $w.p.center.find.l $w.p.center.find.e $w.p.center.find.prev $w.p.center.find.next -side left -padx {0 5}
    bind $w.p.center.find.e <Return> {::GX::OctaveScriptEditorUI::_find forward}

    ttk::label $w.p.right.title -text "GX-TXT bridge snippets"
    pack $w.p.right.title -side top -anchor w -pady {0 5}
    ttk::combobox $w.p.right.snip -state readonly -values {Context {Discover APIs} {Require API} {Describe API} {Call API}} -textvariable ::GX::OctaveScriptEditorUI::ui(snippet)
    ttk::button $w.p.right.insert -text "Insert" -command ::GX::OctaveScriptEditorUI::_insertSnippet
    pack $w.p.right.snip -side top -fill x -pady {0 5}
    pack $w.p.right.insert -side top -anchor e -pady {0 10}

    text $w.p.right.ref -wrap word -height 24 -width 33 -font TkFixedFont -padx 6 -pady 6
    $w.p.right.ref insert 1.0 {Research-script workflow

1. Use normal GNU Octave syntax.
2. Read gxtxt_context() for runtime inputs.
3. Discover public APIs with gxtxt_api_list().
4. Read the current API manual.
5. Call only documented script-callable operations with gxtxt_api_call().

Bridge functions

gxtxt_bridge_info
gxtxt_api_list
gxtxt_api_has
gxtxt_api_describe
gxtxt_api_has_operation
gxtxt_api_call
gxtxt_context

Execution

Save a Session script here, then select its session: ID in Octave Script Analysis. User scripts appear in Script Library and can be assigned to a Session. Legacy documents can be registered explicitly. The analysis run executes an exact snapshot and records its SHA-256.

The bridge is not a sandbox.}
    $w.p.right.ref configure -state disabled
    pack $w.p.right.ref -side top -fill both -expand 1

    ttk::label $w.status -textvariable ::GX::OctaveScriptEditorUI::ui(status) -anchor w -padding {8 4}
    pack $w.status -side bottom -fill x

    bind $w <Control-s> {::GX::OctaveScriptEditorUI::_save; break}
    bind $w <Control-n> {::GX::OctaveScriptEditorUI::_new; break}
    bind $w <Control-o> {::GX::OctaveScriptEditorUI::_import; break}
    bind $w <Control-f> {focus $::GX::OctaveScriptEditorUI::ui(window).p.center.find.e; break}
    bind $w <Control-g> {::GX::OctaveScriptEditorUI::_gotoLineDialog; break}
    bind $w <F3> {::GX::OctaveScriptEditorUI::_find forward; break}
    bind $w <Shift-F3> {::GX::OctaveScriptEditorUI::_find backward; break}

    _refreshDocuments
    set docs [$ui(tree) children {}]
    if {[llength $docs]} { _loadDocument [lindex $docs 0] } else { _new }
    focus $ui(text)
}

proc ::GX::OctaveScriptEditorUI::open {} {
    variable window
    ::GX::OctaveScriptEditor::requireSession
    if {[winfo exists $window]} {
        wm deiconify $window
        raise $window
        focus -force $window
        return [dict create status focused]
    }
    _build
    return [dict create status opened]
}
