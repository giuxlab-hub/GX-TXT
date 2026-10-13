# GX-TXT Python Script Workspace optional Tk adapter.
# SPDX-License-Identifier: GPL-3.0-or-later

package require Tk

namespace eval ::GX::PythonScriptEditorUI {
    variable window .gxtxt_python_script_workspace
    variable ui
    array set ui {}
}

proc ::GX::PythonScriptEditorUI::_setModified {{value 1}} {
    variable ui
    set ui(modified) [expr {$value ? 1 : 0}]
    _updateStatus
}

proc ::GX::PythonScriptEditorUI::_editorModified {} {
    variable ui
    if {![info exists ui(text)] || ![winfo exists $ui(text)]} return
    if {[$ui(text) edit modified]} {
        $ui(text) edit modified 0
        _setModified 1
        _scheduleRefresh
    }
}

proc ::GX::PythonScriptEditorUI::_propertyModified {} { _setModified 1 }

proc ::GX::PythonScriptEditorUI::_parametersModified {} {
    variable ui
    if {![info exists ui(parameters)] || ![winfo exists $ui(parameters)]} return
    if {[$ui(parameters) edit modified]} {
        $ui(parameters) edit modified 0
        _setModified 1
    }
}

proc ::GX::PythonScriptEditorUI::_scheduleRefresh {} {
    variable ui
    if {[info exists ui(refreshAfter)] && $ui(refreshAfter) ne ""} { catch {after cancel $ui(refreshAfter)} }
    set ui(refreshAfter) [after 120 ::GX::PythonScriptEditorUI::_refreshEditor]
}

proc ::GX::PythonScriptEditorUI::_refreshEditor {} {
    variable ui
    set ui(refreshAfter) ""
    if {![info exists ui(text)] || ![winfo exists $ui(text)]} return
    _updateLineNumbers
    _highlight
    _updateStatus
}

proc ::GX::PythonScriptEditorUI::_updateLineNumbers {} {
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

proc ::GX::PythonScriptEditorUI::_tagRegexp {tag pattern} {
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

proc ::GX::PythonScriptEditorUI::_highlight {} {
    variable ui
    set t $ui(text)
    foreach tag {comment string keyword number bridge} { $t tag remove $tag 1.0 end }
    _tagRegexp comment {#[^\n]*}
    _tagRegexp string {('''[^']*'''|"""[^"]*"""|'[^'\n]*'|"[^"\n]*")}
    _tagRegexp keyword {\m(and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\M}
    _tagRegexp number {\m([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?\M}
    _tagRegexp bridge {\mgxtxt_[A-Za-z0-9_]+\M}
    $t tag raise string
    $t tag raise comment
}

proc ::GX::PythonScriptEditorUI::_yscroll {first last} {
    variable ui
    if {[winfo exists $ui(vscroll)]} { $ui(vscroll) set $first $last }
    if {[winfo exists $ui(lines)]} { $ui(lines) yview moveto $first }
}

proc ::GX::PythonScriptEditorUI::_scrollBoth {args} {
    variable ui
    $ui(text) yview {*}$args
    $ui(lines) yview moveto [lindex [$ui(text) yview] 0]
}

proc ::GX::PythonScriptEditorUI::_updateStatus {} {
    variable ui
    if {![info exists ui(status)]} return
    set id [expr {[info exists ui(currentId)] && $ui(currentId) ne "" ? $ui(currentId) : "unsaved"}]
    set state [expr {[info exists ui(modified)] && $ui(modified) ? "modified" : "saved"}]
    set pos "Ln 1, Col 1"
    if {[info exists ui(text)] && [winfo exists $ui(text)]} {
        set parts [split [$ui(text) index insert] .]
        set pos "Ln [lindex $parts 0], Col [expr {[lindex $parts 1] + 1}]"
    }
    set revision [expr {[info exists ui(revision)] && $ui(revision) ne "" ? "r$ui(revision)" : "new"}]
    set hash [expr {[info exists ui(currentSha)] && $ui(currentSha) ne "" ? $ui(currentSha) : "no SHA-256 yet"}]
    set ui(status) "$id  |  $revision  |  SHA-256 $hash  |  $state  |  $pos"
    if {[info exists ui(window)] && [winfo exists $ui(window)]} {
        set star [expr {$state eq "modified" ? " *" : ""}]
        wm title $ui(window) "Python Script Workspace$star"
    }
}

proc ::GX::PythonScriptEditorUI::_confirmAbandon {} {
    variable ui
    if {![info exists ui(modified)] || !$ui(modified)} { return 1 }
    set answer [tk_messageBox -parent $ui(window) -icon question -type yesnocancel -default yes -title "Unsaved script" -message "Save changes to the current script before continuing?"]
    switch -- $answer {
        yes { return [_save] }
        no { return 1 }
        default { return 0 }
    }
}

proc ::GX::PythonScriptEditorUI::_loadDocument {documentId} {
    variable ui
    if {![_confirmAbandon]} { return 0 }
    if {[catch {set full [::GX::PythonScriptEditor::workspaceRead $documentId]} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Open failed" -message $failure
        return 0
    }
    set ui(currentId) $documentId
    set ui(currentSha) [dict get $full sha256]
    set ui(revision) [dict get $full revision]
    set ui(scope) [dict get $full scope]
    set ui(scriptId) [dict get $full id]
    set ui(name) [dict get $full name]
    set ui(version) [dict get $full version]
    set ui(requiredApis) [dict get $full explicit_apis]
    set ui(description) [dict get $full description]
    $ui(parameters) delete 1.0 end
    dict for {param descriptor} [dict get $full parameters] {
        $ui(parameters) insert end "$param | [dict get $descriptor type] | [dict get $descriptor required] | [dict get $descriptor default] | [dict get $descriptor description]\n"
    }
    $ui(parameters) edit reset
    $ui(parameters) edit modified 0
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 [dict get $full code]
    $ui(text) edit reset
    $ui(text) edit modified 0
    set ui(modified) 0
    _refreshEditor
    _selectTreeId $documentId
    return 1
}

proc ::GX::PythonScriptEditorUI::_treeSelected {} {
    variable ui
    set sel [$ui(tree) selection]
    if {[llength $sel] != 1} return
    set id [lindex $sel 0]
    if {[info exists ui(currentId)] && $ui(currentId) eq $id} return
    if {![_loadDocument $id]} { _selectTreeId $ui(currentId) }
}

proc ::GX::PythonScriptEditorUI::_selectTreeId {documentId} {
    variable ui
    if {$documentId eq "" || ![winfo exists $ui(tree)]} return
    if {[lsearch -exact [$ui(tree) children {}] $documentId] >= 0} {
        $ui(tree) selection set $documentId
        $ui(tree) see $documentId
    }
}

proc ::GX::PythonScriptEditorUI::_refreshDocuments {} {
    variable ui
    if {![winfo exists $ui(tree)]} return
    set current [expr {[info exists ui(currentId)] ? $ui(currentId) : ""}]
    $ui(tree) delete [$ui(tree) children {}]
    foreach item [::GX::PythonScriptEditor::workspaceList] {
        set id [dict get $item reference]
        $ui(tree) insert {} end -id $id -values [list [dict get $item name] $id [dict get $item updated_at]]
    }
    if {$current ne ""} { _selectTreeId $current }
}

proc ::GX::PythonScriptEditorUI::_new {} {
    variable ui
    if {![_confirmAbandon]} return
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(revision) ""
    set ui(revision) ""
    set ui(scope) session
    set ui(scriptId) ""
    set ui(name) "Untitled script"
    set ui(version) "1.0.0"
    set ui(requiredApis) ""
    set ui(description) ""
    $ui(parameters) delete 1.0 end
    $ui(parameters) edit reset
    $ui(parameters) edit modified 0
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 [::GX::PythonScriptEditor::defaultCode]
    $ui(text) edit reset
    $ui(text) edit modified 0
    set ui(modified) 0
    $ui(tree) selection remove [$ui(tree) selection]
    _refreshEditor
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::_parametersFromEditor {} {
    variable ui
    set parameters [dict create]
    foreach line [split [$ui(parameters) get 1.0 end-1c] "\n"] {
        if {[string trim $line] eq ""} continue
        set fields [split $line |]
        if {[llength $fields] < 2 || [llength $fields] > 5} {
            error "Each parameter needs name | type | required | default | description."
        }
        while {[llength $fields] < 5} {lappend fields ""}
        lassign [lmap field $fields {string trim $field}] name type required default description
        if {$required eq ""} {set required 0}
        dict set parameters $name [dict create type $type required $required default $default description $description]
    }
    return $parameters
}

proc ::GX::PythonScriptEditorUI::_save {} {
    variable ui
    set name [string trim $ui(name)]
    if {$name eq ""} {
        tk_messageBox -parent $ui(window) -icon error -title "Script name" -message "Script name is required."
        return 0
    }
    set code [$ui(text) get 1.0 "end-1c"]
    if {[catch {
        set parameters [_parametersFromEditor]
        set result [::GX::PythonScriptEditor::workspaceSave $ui(currentId) $ui(currentSha) \
            $ui(scope) $ui(scriptId) $name $ui(version) $ui(description) $ui(requiredApis) $parameters $code]
    } failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Save failed" -message $failure
        return 0
    }
    set ui(currentId) [dict get $result reference]
    set ui(currentSha) [dict get $result sha256]
    set ui(revision) [dict get $result revision]
    set ui(modified) 0
    _refreshDocuments
    _selectTreeId $ui(currentId)
    _updateStatus
    return 1
}

proc ::GX::PythonScriptEditorUI::_saveAs {} {
    variable ui
    set name [string trim $ui(name)]
    if {$name eq ""} { set name "Untitled script" }
    set copyName "$name (copy)"
    set code [$ui(text) get 1.0 "end-1c"]
    set base [expr {$ui(scriptId) eq "" ? "script" : $ui(scriptId)}]
    set suffix 2
    while {[lsearch -exact [lmap script [::GX::scriptRegistryList $ui(scope)] {dict get $script id}] "${base}_$suffix"] >= 0} {incr suffix}
    set newId "${base}_$suffix"
    if {[catch {
        set parameters [_parametersFromEditor]
        set result [::GX::PythonScriptEditor::workspaceSave "" "" $ui(scope) $newId $copyName \
            $ui(version) $ui(description) $ui(requiredApis) $parameters $code]
    } failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Save As failed" -message $failure
        return 0
    }
    set ui(currentId) [dict get $result reference]
    set ui(currentSha) [dict get $result sha256]
    set ui(revision) [dict get $result revision]
    set ui(scriptId) $newId
    set ui(name) $copyName
    set ui(modified) 0
    _refreshDocuments
    _selectTreeId $ui(currentId)
    _updateStatus
    return 1
}

proc ::GX::PythonScriptEditorUI::_delete {} {
    variable ui
    if {$ui(currentId) eq ""} return
    set answer [tk_messageBox -parent $ui(window) -icon warning -type yesno -default no -title "Delete script" -message "Delete '$ui(name)' ($ui(currentId))? The Script Registry source will be removed. Historical execution snapshots remain."]
    if {$answer ne "yes"} return
    if {[catch {::GX::PythonScriptEditor::workspaceDelete $ui(currentId) $ui(currentSha)} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Delete failed" -message $failure
        return
    }
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(revision) ""
    set ui(scriptId) ""
    set ui(scope) session
    set ui(modified) 0
    _refreshDocuments
    _new
}

proc ::GX::PythonScriptEditorUI::_decodeUtf8Bytes {bytes} {
    set source [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $source] ne $bytes} {
        error "Python source must be valid UTF-8."
    }
    return $source
}

proc ::GX::PythonScriptEditorUI::_import {} {
    variable ui
    if {![_confirmAbandon]} return
    set path [tk_getOpenFile -parent $ui(window) -title "Import Python script" -filetypes {{{Python scripts} {.py}} {{All files} {*}}}]
    if {$path eq ""} return
    if {[string tolower [file extension $path]] ne ".py"} {
        tk_messageBox -parent $ui(window) -icon error -title "Import failed" -message "Choose a .py Python source file."
        return
    }
    if {[catch {
        set fd [::open $path r]
        fconfigure $fd -translation binary -encoding binary
        set code [_decodeUtf8Bytes [read $fd]]
        close $fd
    } failure]} {
        catch {close $fd}
        tk_messageBox -parent $ui(window) -icon error -title "Import failed" -message $failure
        return
    }
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(revision) ""
    set ui(scriptId) ""
    set ui(scope) session
    set ui(name) [file tail [file rootname $path]]
    set ui(version) "1.0.0"
    set ui(requiredApis) ""
    set ui(description) "Imported from [file tail $path]. The registered script is independent of the original file."
    $ui(parameters) delete 1.0 end
    $ui(parameters) edit reset
    $ui(parameters) edit modified 0
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 $code
    $ui(text) edit reset
    $ui(text) edit modified 0
    set ui(modified) 1
    _refreshEditor
}

proc ::GX::PythonScriptEditorUI::_export {} {
    variable ui
    set initial [string map {"/" "_" "\\" "_" ":" "_"} [string trim $ui(name)]]
    if {$initial eq ""} { set initial "script" }
    if {![string match *.py $initial]} { append initial .py }
    set path [tk_getSaveFile -parent $ui(window) -title "Export Python script" -defaultextension .py -initialfile $initial -filetypes {{{Python scripts} {.py}} {{All files} {*}}}]
    if {$path eq ""} return
    if {[string tolower [file extension $path]] ne ".py"} {
        tk_messageBox -parent $ui(window) -icon error -title "Export failed" -message "Choose a .py target file."
        return
    }
    if {[catch {
        set fd [::open $path w]
        fconfigure $fd -encoding binary -translation binary
        puts -nonewline $fd [encoding convertto utf-8 [$ui(text) get 1.0 "end-1c"]]
        close $fd
    } failure]} {
        catch {close $fd}
        tk_messageBox -parent $ui(window) -icon error -title "Export failed" -message $failure
        return
    }
    set ui(status) "Exported to [file tail $path]"
    after 1800 ::GX::PythonScriptEditorUI::_updateStatus
}

proc ::GX::PythonScriptEditorUI::_copyId {} {
    variable ui
    if {$ui(currentId) eq ""} return
    clipboard clear -displayof $ui(window)
    clipboard append -displayof $ui(window) $ui(currentId)
    set ui(status) "Copied script ID $ui(currentId)"
    after 1200 ::GX::PythonScriptEditorUI::_updateStatus
}

proc ::GX::PythonScriptEditorUI::_run {} {
    variable ui
    if {$ui(currentId) eq ""} {
        tk_messageBox -parent $ui(window) -icon info -title "Run Python script" -message "Save this Python script before running it."
        return
    }
    if {$ui(modified)} {
        if {![_save]} return
    }
    set ::GX::scriptWorkspaceChoice $ui(currentId)
    ::GX::scriptWorkspaceRunDialog
}

proc ::GX::PythonScriptEditorUI::_undo {} {
    variable ui
    if {![catch {$ui(text) edit undo}]} {_setModified 1; _scheduleRefresh}
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::_redo {} {
    variable ui
    if {![catch {$ui(text) edit redo}]} {_setModified 1; _scheduleRefresh}
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::_copy {} {
    variable ui
    event generate $ui(text) <<Copy>>
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::_paste {} {
    variable ui
    event generate $ui(text) <<Paste>>
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::_find {{direction forward}} {
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

proc ::GX::PythonScriptEditorUI::_gotoLineDialog {} {
    variable ui
    set d $ui(window).goto
    catch {destroy $d}
    toplevel $d
    wm title $d "Go to line"
    wm transient $d $ui(window)
    set ui(gotoLine) ""
    ttk::label $d.l -text "Line:"
    ttk::entry $d.e -textvariable ::GX::PythonScriptEditorUI::ui(gotoLine) -width 12
    ttk::button $d.ok -text "Go" -command ::GX::PythonScriptEditorUI::_gotoLineApply
    ttk::button $d.cancel -text "Cancel" -command [list destroy $d]
    grid $d.l $d.e -padx 6 -pady 8
    grid $d.ok $d.cancel -padx 6 -pady {0 8}
    focus $d.e
    bind $d.e <Return> ::GX::PythonScriptEditorUI::_gotoLineApply
}

proc ::GX::PythonScriptEditorUI::_gotoLineApply {} {
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

proc ::GX::PythonScriptEditorUI::_insertSnippet {} {
    variable ui
    switch -- $ui(snippet) {
        "Context" { set code "from gxtxt import gxtxt_context\nctx = gxtxt_context()\nprint(ctx)\n" }
        "Discover APIs" { set code "from gxtxt import gxtxt_api_list\nfor api in gxtxt_api_list():\n    print(api)\n" }
        "Require API" { set code "from gxtxt import gxtxt_api_require\ngxtxt_api_require('SOME_PUBLIC_API_v1@1')\n" }
        "Describe API" { set code "from gxtxt import gxtxt_api_describe\ndescription = gxtxt_api_describe('SOME_PUBLIC_API_v1')\nprint(description)\n" }
        "Call API" { set code "from gxtxt import gxtxt_api_call\nresult = gxtxt_api_call('SOME_PUBLIC_API_v1', 'documented_operation', \[request\])\nprint(result)\n" }
        default { return }
    }
    $ui(text) insert insert $code
    _setModified 1
    _scheduleRefresh
}

proc ::GX::PythonScriptEditorUI::_bridgeHelp {} {
    variable ui
    set d $ui(window).bridgehelp
    catch {destroy $d}
    toplevel $d
    wm title $d "GX-TXT Python Script Bridge"
    wm transient $d $ui(window)
    text $d.t -wrap word -width 90 -height 28 -font TkFixedFont -padx 10 -pady 10
    ttk::scrollbar $d.s -orient vertical -command [list $d.t yview]
    $d.t configure -yscrollcommand [list $d.s set]
    pack $d.s -side right -fill y
    pack $d.t -side left -fill both -expand 1
    set help {Python gxtxt public client

The historical Bridge descriptor is OCTAVE_SCRIPT_BRIDGE_API_v1. It supports
Python and Octave. Import the public package in a registered Python script:

  from gxtxt import (
      gxtxt_context, gxtxt_api_list, gxtxt_api_has,
      gxtxt_api_describe, gxtxt_api_require, gxtxt_api_call,
  )

The bridge is generic. Read the current manual of the public GX-TXT API you want to use, then reach its script-callable operations with:

  gxtxt_bridge_info()
  gxtxt_api_list()
  gxtxt_api_has(api_id)
  gxtxt_api_describe(api_id)
  gxtxt_api_has_operation(api_id, operation)
  gxtxt_api_require(declaration)
  gxtxt_api_call(api_id, operation, positional_args)
  gxtxt_context()

Typical pattern:

  ctx = gxtxt_context()
  api_id = 'SOME_PUBLIC_API_v1'
  gxtxt_api_require(api_id)
  d = gxtxt_api_describe(api_id)
  request = {}
  result = gxtxt_api_call(api_id, 'documented_operation', [request])

The complete client reference is docs/api/PYTHON_SCRIPT_CLIENT_v1.md. The
Script Registry's required APIs are checked before source execution. Typed
parameters appear in gxtxt_context().

The bridge is not a sandbox. Ordinary Python filesystem/process capabilities remain available according to the configured runtime environment.}
    $d.t insert 1.0 $help
    $d.t configure -state disabled
}

proc ::GX::PythonScriptEditorUI::_close {} {
    variable ui
    if {![_confirmAbandon]} return
    catch {destroy $ui(window)}
}

proc ::GX::PythonScriptEditorUI::_build {} {
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
    set ui(version) "1.0.0"
    set ui(requiredApis) ""
    set ui(description) ""
    set ui(find) ""
    set ui(snippet) "Context"
    set ui(status) ""
    set ui(refreshAfter) ""

    toplevel $w
    wm title $w "Python Script Workspace"
    wm geometry $w 1180x760
    wm minsize $w 900 560
    wm protocol $w WM_DELETE_WINDOW ::GX::PythonScriptEditorUI::_close

    ttk::frame $w.toolbar -padding {8 6}
    pack $w.toolbar -side top -fill x
    set column 0
    foreach spec {
        {new New ::GX::PythonScriptEditorUI::_new}
        {import {Import .py...} ::GX::PythonScriptEditorUI::_import}
        {save Save ::GX::PythonScriptEditorUI::_save}
        {copy {Save As...} ::GX::PythonScriptEditorUI::_saveAs}
        {export {Export .py...} ::GX::PythonScriptEditorUI::_export}
        {delete Delete ::GX::PythonScriptEditorUI::_delete}
        {copyid {Copy ID} ::GX::PythonScriptEditorUI::_copyId}
    } {
        lassign $spec name label cmd
        ttk::button $w.toolbar.$name -text $label -command $cmd
        grid $w.toolbar.$name -row 0 -column $column -sticky w -padx {0 5} -pady {0 4}
        incr column
    }
    set column 0
    foreach spec {
        {undo Undo ::GX::PythonScriptEditorUI::_undo}
        {redo Redo ::GX::PythonScriptEditorUI::_redo}
        {copycode Copy ::GX::PythonScriptEditorUI::_copy}
        {pastecode Paste ::GX::PythonScriptEditorUI::_paste}
    } {
        lassign $spec name label cmd
        ttk::button $w.toolbar.$name -text $label -command $cmd
        grid $w.toolbar.$name -row 1 -column $column -sticky w -padx {0 5}
        incr column
    }
    ttk::button $w.toolbar.goto -text "Go to line..." -command ::GX::PythonScriptEditorUI::_gotoLineDialog
    ttk::button $w.toolbar.run -text "Run registered..." -command ::GX::PythonScriptEditorUI::_run
    ttk::button $w.toolbar.help -text "Bridge help" -command ::GX::PythonScriptEditorUI::_bridgeHelp
    grid $w.toolbar.goto -row 1 -column 4 -sticky w -padx {0 5}
    grid $w.toolbar.run -row 1 -column 5 -sticky w -padx {0 5}
    grid $w.toolbar.help -row 1 -column 6 -sticky w -padx {0 5}

    ttk::panedwindow $w.p -orient horizontal
    pack $w.p -side top -fill both -expand 1 -padx 8 -pady {0 6}
    ttk::frame $w.p.left -padding 4
    ttk::frame $w.p.center -padding 4
    ttk::frame $w.p.right -padding 4
    $w.p add $w.p.left -weight 1
    $w.p add $w.p.center -weight 5
    $w.p add $w.p.right -weight 2

    ttk::label $w.p.left.title -text "Registered Python scripts"
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
    bind $ui(tree) <<TreeviewSelect>> ::GX::PythonScriptEditorUI::_treeSelected

    ttk::frame $w.p.center.props
    pack $w.p.center.props -side top -fill x -pady {0 5}
    ttk::label $w.p.center.props.sl -text "Scope:"
    ttk::combobox $w.p.center.props.se -state readonly -values {session user} -textvariable ::GX::PythonScriptEditorUI::ui(scope) -width 10
    ttk::label $w.p.center.props.il -text "Script ID:"
    ttk::entry $w.p.center.props.ie -textvariable ::GX::PythonScriptEditorUI::ui(scriptId) -width 20
    grid $w.p.center.props.sl $w.p.center.props.se $w.p.center.props.il $w.p.center.props.ie -sticky ew -padx {0 6}
    ttk::label $w.p.center.props.nl -text "Name:"
    ttk::entry $w.p.center.props.ne -textvariable ::GX::PythonScriptEditorUI::ui(name) -width 30
    ttk::label $w.p.center.props.vl -text "Version:"
    ttk::entry $w.p.center.props.ve -textvariable ::GX::PythonScriptEditorUI::ui(version) -width 15
    grid $w.p.center.props.nl $w.p.center.props.ne $w.p.center.props.vl $w.p.center.props.ve -sticky ew -padx {0 6}
    ttk::label $w.p.center.props.rl -text "Additional APIs:"
    ttk::entry $w.p.center.props.re -textvariable ::GX::PythonScriptEditorUI::ui(requiredApis)
    grid $w.p.center.props.rl -row 2 -column 0 -sticky e -padx {0 6}
    grid $w.p.center.props.re -row 2 -column 1 -columnspan 3 -sticky ew -padx {0 6}
    grid columnconfigure $w.p.center.props 1 -weight 1
    grid columnconfigure $w.p.center.props 3 -weight 1
    bind $w.p.center.props.ne <KeyRelease> ::GX::PythonScriptEditorUI::_propertyModified
    bind $w.p.center.props.ve <KeyRelease> ::GX::PythonScriptEditorUI::_propertyModified
    bind $w.p.center.props.re <KeyRelease> ::GX::PythonScriptEditorUI::_propertyModified

    ttk::frame $w.p.center.desc
    pack $w.p.center.desc -side top -fill x -pady {0 5}
    ttk::label $w.p.center.desc.l -text "Description:"
    ttk::entry $w.p.center.desc.e -textvariable ::GX::PythonScriptEditorUI::ui(description)
    pack $w.p.center.desc.l -side left -padx {0 6}
    pack $w.p.center.desc.e -side left -fill x -expand 1
    bind $w.p.center.desc.e <KeyRelease> ::GX::PythonScriptEditorUI::_propertyModified

    ttk::frame $w.p.center.params
    pack $w.p.center.params -side top -fill x -pady {0 5}
    ttk::label $w.p.center.params.l -text "Typed parameters: name | type | required (0/1) | default | description"
    pack $w.p.center.params.l -side top -anchor w
    text $w.p.center.params.t -height 3 -wrap none -undo 1 -font TkFixedFont
    set ui(parameters) $w.p.center.params.t
    pack $ui(parameters) -side top -fill x
    bind $ui(parameters) <<Modified>> ::GX::PythonScriptEditorUI::_parametersModified

    ttk::frame $w.p.center.edit
    pack $w.p.center.edit -side top -fill both -expand 1
    text $w.p.center.edit.lines -width 6 -state disabled -takefocus 0 -wrap none -font TkFixedFont -background #f0f0f0 -foreground #666666 -padx 4 -pady 4
    text $w.p.center.edit.text -undo 1 -autoseparators 1 -maxundo 0 -wrap none -font TkFixedFont -tabs {32} -padx 5 -pady 4
    ttk::scrollbar $w.p.center.edit.v -orient vertical -command ::GX::PythonScriptEditorUI::_scrollBoth
    ttk::scrollbar $w.p.center.edit.h -orient horizontal -command [list $w.p.center.edit.text xview]
    set ui(lines) $w.p.center.edit.lines
    set ui(text) $w.p.center.edit.text
    set ui(vscroll) $w.p.center.edit.v
    $ui(text) configure -yscrollcommand ::GX::PythonScriptEditorUI::_yscroll -xscrollcommand [list $w.p.center.edit.h set]
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
    bind $ui(text) <<Modified>> ::GX::PythonScriptEditorUI::_editorModified
    bind $ui(text) <KeyRelease> ::GX::PythonScriptEditorUI::_updateStatus
    bind $ui(text) <ButtonRelease-1> ::GX::PythonScriptEditorUI::_updateStatus

    ttk::frame $w.p.center.find
    pack $w.p.center.find -side bottom -fill x -pady {5 0}
    ttk::label $w.p.center.find.l -text "Find:"
    ttk::entry $w.p.center.find.e -textvariable ::GX::PythonScriptEditorUI::ui(find) -width 28
    ttk::button $w.p.center.find.prev -text "Previous" -command {::GX::PythonScriptEditorUI::_find backward}
    ttk::button $w.p.center.find.next -text "Next" -command {::GX::PythonScriptEditorUI::_find forward}
    pack $w.p.center.find.l $w.p.center.find.e $w.p.center.find.prev $w.p.center.find.next -side left -padx {0 5}
    bind $w.p.center.find.e <Return> {::GX::PythonScriptEditorUI::_find forward}

    ttk::label $w.p.right.title -text "GX-TXT bridge snippets"
    pack $w.p.right.title -side top -anchor w -pady {0 5}
    ttk::combobox $w.p.right.snip -state readonly -values {Context {Discover APIs} {Require API} {Describe API} {Call API}} -textvariable ::GX::PythonScriptEditorUI::ui(snippet)
    ttk::button $w.p.right.insert -text "Insert" -command ::GX::PythonScriptEditorUI::_insertSnippet
    pack $w.p.right.snip -side top -fill x -pady {0 5}
    pack $w.p.right.insert -side top -anchor e -pady {0 10}

    text $w.p.right.ref -wrap word -height 24 -width 33 -font TkFixedFont -padx 6 -pady 6
    $w.p.right.ref insert 1.0 {Research-script workflow

1. Use normal Python syntax.
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

Save a Session script here, then select its session: ID in Python Script Analysis. User scripts appear in Script Library and can be assigned to a Session. Run registered uses the existing Script Execution dialog. The analysis run executes an exact snapshot and records its SHA-256.

The bridge is not a sandbox.}
    $w.p.right.ref configure -state disabled
    pack $w.p.right.ref -side top -fill both -expand 1

    ttk::label $w.status -textvariable ::GX::PythonScriptEditorUI::ui(status) -anchor w -padding {8 4}
    pack $w.status -side bottom -fill x

    bind $w <Control-s> {::GX::PythonScriptEditorUI::_save; break}
    bind $w <Control-n> {::GX::PythonScriptEditorUI::_new; break}
    bind $w <Control-o> {::GX::PythonScriptEditorUI::_import; break}
    bind $w <Control-f> {focus $::GX::PythonScriptEditorUI::ui(window).p.center.find.e; break}
    bind $w <Control-g> {::GX::PythonScriptEditorUI::_gotoLineDialog; break}
    bind $w <F3> {::GX::PythonScriptEditorUI::_find forward; break}
    bind $w <Shift-F3> {::GX::PythonScriptEditorUI::_find backward; break}

    _refreshDocuments
    set docs [$ui(tree) children {}]
    if {[llength $docs]} { _loadDocument [lindex $docs 0] } else { _new }
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::open {} {
    variable window
    if {$::GX::currentSession eq ""} {error "Open a Session before opening Python Script Workspace."}
    if {[winfo exists $window]} {
        wm deiconify $window
        raise $window
        focus -force $window
        return [dict create status focused]
    }
    _build
    return [dict create status opened]
}
