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
    if {$value==0} {_acceptBaseline} else {_recomputeDirty}
    _updateStatus
}

proc ::GX::PythonScriptEditorUI::_editorModified {} {variable ui;::GX::_sourceSurfaceModified [winfo parent $ui(text)]}

proc ::GX::PythonScriptEditorUI::_propertyModified {name element operation} {
    variable ui
    variable propertyValues
    if {$element ni {scope scriptId name description version requiredApis}} return
    set value $ui($element)
    if {![dict exists $propertyValues $element] || [dict get $propertyValues $element] ne $value} {
        dict set propertyValues $element $value
        _setModified 1
    }
}
proc ::GX::PythonScriptEditorUI::_watchProperties {} {
    variable ui
    variable propertyValues
    set propertyValues {}
    foreach key {scope scriptId name description version requiredApis} {dict set propertyValues $key $ui($key)}
    catch {trace remove variable ui write ::GX::PythonScriptEditorUI::_propertyModified}
    trace add variable ui write ::GX::PythonScriptEditorUI::_propertyModified
}

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

proc ::GX::PythonScriptEditorUI::_updateLineNumbers {} {variable ui;if {[info exists ui(text)] && [winfo exists $ui(text)]} {::GX::_sourceSurfaceGutter [winfo parent $ui(text)]}}



proc ::GX::PythonScriptEditorUI::_highlight {} {variable ui;::GX::sourceSurfaceRefresh $ui(text)}

proc ::GX::PythonScriptEditorUI::_yscroll {first last} {variable ui;::GX::_sourceSurfaceScroll [winfo parent $ui(text)] $first $last}

proc ::GX::PythonScriptEditorUI::_scrollBoth {args} {variable ui;$ui(text) yview {*}$args}

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
    set hash [expr {[info exists ui(currentSha)] && $ui(currentSha) ne "" ? "[string range $ui(currentSha) 0 11]…" : "pending"}]
    set ui(status) "$id  |  $revision  |  SHA-256 $hash  |  $state  |  $pos"
    if {[info exists ui(window)] && [winfo exists $ui(window)]} {
        set star [expr {$state eq "modified" ? " *" : ""}]
        wm title $ui(window) "Python Script Workspace$star"
    }
}

proc ::GX::PythonScriptEditorUI::_confirmAbandon {} {
    variable ui
    _recomputeDirty
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
    if {![::GX::scriptWorkspaceEditorSessionValid $ui(window) $ui(sessionToken) [lindex [split $documentId :] 0]]} {return 0}
    if {![_confirmAbandon]} { return 0 }
    if {[catch {set full [::GX::PythonScriptEditor::workspaceRead $documentId]} failure]} {
        tk_messageBox -parent $ui(window) -icon error -title "Open failed" -message $failure
        return 0
    }
    set ui(sessionToken) [::GX::scriptWorkspaceSessionToken]
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
    set ui(parameterDefinitions) [dict get $full parameters]
    $ui(parameters) insert 1.0 [::GX::scriptParameterDefinitionsFormat $ui(parameterDefinitions)]
    $ui(parameters) edit reset
    $ui(parameters) edit modified 0
    $ui(text) delete 1.0 end
    $ui(text) insert 1.0 [dict get $full code]
    $ui(text) edit reset
    $ui(text) edit modified 0
    _acceptBaseline
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
    set ui(scope) [::GX::scriptWorkspaceDefaultScope]
    set ui(sessionToken) [::GX::scriptWorkspaceSessionToken]
    set ui(scriptId) ""
    set ui(name) "Untitled script"
    set ui(parameterDefinitions) {}
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
    _acceptBaseline
    $ui(tree) selection remove [$ui(tree) selection]
    _refreshEditor
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::_parametersFromEditor {} {
    variable ui
    set text [$ui(parameters) get 1.0 end-1c]
    if {$text eq [::GX::scriptParameterDefinitionsFormat $ui(parameterDefinitions)]} {return $ui(parameterDefinitions)}
    return [::GX::scriptParameterDefinitionsParse $text $ui(parameterDefinitions)]
}

proc ::GX::PythonScriptEditorUI::_save {} {
    variable ui
    if {![::GX::scriptWorkspaceEditorSessionValid $ui(window) $ui(sessionToken) $ui(scope)]} {return 0}
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
    set ui(parameterDefinitions) [dict get $result parameters]
    _acceptBaseline
    _refreshDocuments
    _selectTreeId $ui(currentId)
    _updateStatus
    return 1
}

proc ::GX::PythonScriptEditorUI::_saveAs {} {
    variable ui
    if {![::GX::scriptWorkspaceEditorSessionValid $ui(window) $ui(sessionToken) $ui(scope)]} {return 0}
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
    set ui(parameterDefinitions) [dict get $result parameters]
    _acceptBaseline
    _refreshDocuments
    _selectTreeId $ui(currentId)
    _updateStatus
    return 1
}

proc ::GX::PythonScriptEditorUI::_delete {} {
    variable ui
    if {![::GX::scriptWorkspaceEditorSessionValid $ui(window) $ui(sessionToken) [lindex [split $ui(currentId) :] 0]]} {return 0}
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
    set ui(scope) [::GX::scriptWorkspaceDefaultScope]
    set ui(sessionToken) [::GX::scriptWorkspaceSessionToken]
    _acceptBaseline
    _refreshDocuments
    _new
}

proc ::GX::PythonScriptEditorUI::_decodeUtf8Bytes {bytes} {
    return [::GX::scriptWorkspaceDecodeUtf8 $bytes]
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
    set ui(scope) [::GX::scriptWorkspaceDefaultScope]
    set ui(sessionToken) [::GX::scriptWorkspaceSessionToken]
    set ui(name) [file tail [file rootname $path]]
    set ui(parameterDefinitions) {}
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
    set ui(importDraft) 1
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
    ::GX::scriptWorkspaceOpenEditorRunner $ui(window) $ui(currentId) $ui(modified) ::GX::PythonScriptEditorUI::_save $ui(currentSha) $ui(sessionToken)
}
proc ::GX::PythonScriptEditorUI::_undo {} {variable ui; ::GX::uiTextEdit $ui(window) undo}
proc ::GX::PythonScriptEditorUI::_redo {} {variable ui; ::GX::uiTextEdit $ui(window) redo}
proc ::GX::PythonScriptEditorUI::_copy {} {variable ui; ::GX::uiTextEdit $ui(window) copy}
proc ::GX::PythonScriptEditorUI::_paste {} {variable ui; ::GX::uiTextEdit $ui(window) paste}

proc ::GX::PythonScriptEditorUI::_find {{direction forward}} {
    variable ui
    if {[::GX::sourceSurfaceFind $ui(text) $ui(find) $direction] eq {}} {bell}
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
    if {![::GX::scriptDebugPrepareEditorClose $ui(window)]} return
    ::GX::scriptWorkspaceLayoutRemember $ui(window)
    catch {destroy $ui(window)}
}

proc ::GX::PythonScriptEditorUI::_buildMenus {w} {
    ttk::frame $w.toolbar -padding {8 4}
    pack $w.toolbar -side top -fill x
    foreach {key label} {file File edit Edit view View run Run help Help} {
        ttk::menubutton $w.toolbar.$key -text $label -menu $w.toolbar.$key.menu
        menu $w.toolbar.$key.menu -tearoff 0 -postcommand [list ::GX::PythonScriptEditorUI::_menuState $key]
    }
    ::GX::scriptWorkspaceViewMenu $w $w.toolbar.view.menu Python
    set m $w.toolbar.file.menu
    foreach {label shortcut command} {
        New Ctrl+N _new
        {Import .py...} Ctrl+O _import
        Save Ctrl+S _save
        {Save As...} {} _saveAs
        {Export .py...} {} _export
        Delete {} _delete
        {Copy ID} {} _copyId
    } {$m add command -label $label -accelerator $shortcut -command ::GX::PythonScriptEditorUI::$command}

    $m add separator
    $m add command -label Close -command ::GX::PythonScriptEditorUI::_close
    set m $w.toolbar.edit.menu
    foreach {label shortcut operation} {Undo Ctrl+Z undo Redo Ctrl+Y redo Cut Ctrl+X cut Copy Ctrl+C copy Paste Ctrl+V paste {Select all} Ctrl+A select_all} {
        $m add command -label $label -accelerator $shortcut -command [list ::GX::uiTextEdit $w $operation]
    }
    $m add separator
    $m add command -label {Manage imports…} -command [list ::GX::pythonImportsOpen $w]
    $m add command -label Find -accelerator Ctrl+F -command [list focus $w.p.center.find.e]
    $m add command -label {Find next} -accelerator F3 -command {::GX::PythonScriptEditorUI::_find forward}
    $m add command -label {Find previous} -accelerator Shift+F3 -command {::GX::PythonScriptEditorUI::_find backward}
    $m add command -label {Go to line...} -accelerator Ctrl+G -command ::GX::PythonScriptEditorUI::_gotoLineDialog
    foreach {label operation} {{Fold current block} toggle {Fold all} fold_all {Unfold all} unfold_all} {$m add command -label $label -command [list ::GX::sourceSurfaceFold $w.p.center.edit $operation]}
    set m $w.toolbar.run.menu
    $m add command -label {Debug Session script…} -command [list ::GX::scriptDebugOpen $w Python]
    $m add command -label {Open Script Runner...} -command ::GX::PythonScriptEditorUI::_run
    $m add command -label {Script Library...} -command ::GX::scriptLibraryDialog
    $m add command -label {Script Jobs Manager...} -command ::GX::scriptJobsDialog
    $w.toolbar.help.menu add command -label {Script Bridge help} -command ::GX::PythonScriptEditorUI::_bridgeHelp
    $w.toolbar.help.menu add command -label {Viewer manual / Debugger guide…} -accelerator F1 -command [list ::GX::documentationBrowserOpenModuleWindow analysis.python_script $w]
    $w.toolbar.help.menu add command -label {About…} -command [list ::GX::documentationBrowserAboutModule analysis.python_script python_script_editor $w]
    bind $w <F1> [list ::GX::documentationBrowserOpenModuleWindow analysis.python_script $w]
    ::GX::uiMenuRowAttach $w.toolbar [list $w.toolbar.file $w.toolbar.edit $w.toolbar.view $w.toolbar.run $w.toolbar.help]
}
proc ::GX::PythonScriptEditorUI::_menuState {group} {
    variable ui
    set m $ui(window).toolbar.$group.menu
    if {$group eq "edit"} {
        set index 0
        foreach operation {undo redo cut copy paste select_all} {
            $m entryconfigure $index -state [expr {[::GX::uiTextEditCan $ui(window) $operation] ? "normal" : "disabled"}]
            incr index
        }
    } elseif {$group eq "file"} {
        foreach index {5 6} {$m entryconfigure $index -state [expr {$ui(currentId) eq {} ? "disabled" : "normal"}]}

    }
}

proc ::GX::PythonScriptEditorUI::_build {} {
    variable ui
    variable window
    catch {trace remove variable ui write ::GX::PythonScriptEditorUI::_propertyModified}
    set w $window
    set ui(window) $w
    set ui(sessionToken) [::GX::scriptWorkspaceSessionToken]
    set ui(currentId) ""
    set ui(currentSha) ""
    set ui(modified) 0
    set ui(name) ""
    set ui(scope) [::GX::scriptWorkspaceDefaultScope]
    set ui(sessionToken) [::GX::scriptWorkspaceSessionToken]
    set ui(scriptId) ""
    set ui(parameterDefinitions) {}
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
    wm minsize $w 850 550
    wm protocol $w WM_DELETE_WINDOW ::GX::PythonScriptEditorUI::_close

    _buildMenus $w

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
    ::GX::scriptWorkspaceExplorerPresentation $ui(tree)
    ttk::scrollbar $w.p.left.ts -orient vertical -command [list $ui(tree) yview]
    $ui(tree) configure -yscrollcommand [list $w.p.left.ts set]
    ttk::scrollbar $w.p.left.hs -orient horizontal -command [list $ui(tree) xview]
    $ui(tree) configure -xscrollcommand [list $w.p.left.hs set]
    pack $w.p.left.hs -side bottom -fill x
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
    grid $w.p.center.props.nl $w.p.center.props.ne -columnspan 1 -sticky ew -padx {0 6}
    ttk::frame $w.p.center.version
    pack $w.p.center.version -side top -fill x -pady {0 5}
    ttk::label $w.p.center.version.l -text "Version:"
    ttk::entry $w.p.center.version.e -textvariable ::GX::PythonScriptEditorUI::ui(version) -width 15
    pack $w.p.center.version.l -side left -padx {0 6}
    pack $w.p.center.version.e -side left -fill x -expand 1
    ttk::frame $w.p.center.requiredApis
    pack $w.p.center.requiredApis -side top -fill x -pady {0 5}
    ttk::label $w.p.center.requiredApis.l -text "Additional required APIs:"
    ttk::entry $w.p.center.requiredApis.e -textvariable ::GX::PythonScriptEditorUI::ui(requiredApis)
    pack $w.p.center.requiredApis.l -side left -padx {0 6}
    pack $w.p.center.requiredApis.e -side left -fill x -expand 1
    grid columnconfigure $w.p.center.props 1 -weight 1
    grid columnconfigure $w.p.center.props 3 -weight 1

    ttk::frame $w.p.center.desc
    pack $w.p.center.desc -side top -fill x -pady {0 5}
    ttk::label $w.p.center.desc.l -text "Description:"
    ttk::entry $w.p.center.desc.e -textvariable ::GX::PythonScriptEditorUI::ui(description)
    pack $w.p.center.desc.l -side left -padx {0 6}
    pack $w.p.center.desc.e -side left -fill x -expand 1

    ttk::frame $w.p.center.params
    pack $w.p.center.params -side top -fill x -pady {0 5}
    ttk::label $w.p.center.params.l -text "Typed parameters: name | type | required (0/1) | default | description"
    pack $w.p.center.params.l -side top -anchor w
    text $w.p.center.params.t -height 3 -wrap none -undo 1 -font TkFixedFont
    set ui(parameters) $w.p.center.params.t
    pack $ui(parameters) -side top -fill x
    bind $ui(parameters) <<Modified>> ::GX::PythonScriptEditorUI::_parametersModified

    set ui(text) [::GX::sourceSurfaceCreate $w.p.center.edit [dict create mode editable language python change_command ::GX::PythonScriptEditorUI::_sourceChanged]]
    pack $w.p.center.edit -side top -fill both -expand 1
    set ui(lines) $w.p.center.edit.lines
    set ui(vscroll) $w.p.center.edit.v
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

Save a Session script here, then select its session: ID in Python Script Analysis. User scripts appear in Script Library and can be assigned to a Session. Run > Open Script Runner opens the existing dialog for an explicit saved revision without submitting a Job. The analysis run executes an exact snapshot and records its SHA-256.

The bridge is not a sandbox.}
    $w.p.right.ref configure -state disabled
    pack $w.p.right.ref -side top -fill both -expand 1
    ::GX::scriptWorkspaceReferenceScroll $w.p.right $w.p.right.ref

    ttk::label $w.status -textvariable ::GX::PythonScriptEditorUI::ui(status) -anchor w -padding {8 4}
    pack $w.status -side bottom -fill x -before $w.p

    bind $w <Control-s> {::GX::PythonScriptEditorUI::_save; break}
    bind $w <Control-n> {::GX::PythonScriptEditorUI::_new; break}
    bind $w <Control-o> {::GX::PythonScriptEditorUI::_import; break}
    bind $w <Control-f> {focus $::GX::PythonScriptEditorUI::ui(window).p.center.find.e; break}
    bind $w <Control-g> {::GX::PythonScriptEditorUI::_gotoLineDialog; break}
    bind $w <F3> {::GX::PythonScriptEditorUI::_find forward; break}
    bind $w <Shift-F3> {::GX::PythonScriptEditorUI::_find backward; break}

    ::GX::uiTextEditingAttach $w [list $ui(text) $w.p.center.props.ie $w.p.center.props.ne $w.p.center.desc.e $w.p.center.find.e $w.p.center.version.e $w.p.center.requiredApis.e $w.p.center.params.t]
    bind $w.p.center.find.e <Escape> [list focus $ui(text)]
    ::GX::scriptWorkspaceLayoutInit $w
    _watchProperties
    # A rebuilt empty shell must not inherit the previous document baseline.
    _acceptBaseline
    _refreshDocuments
    set docs [$ui(tree) children {}]
    if {[llength $docs]} { _loadDocument [lindex $docs 0] } else { _new }
    focus $ui(text)
}

proc ::GX::PythonScriptEditorUI::open {} {
    variable window
    if {[winfo exists $window]} {
        wm deiconify $window
        raise $window
        focus -force $window
        return [dict create status focused]
    }
    _build
    return [dict create status opened]
}

proc ::GX::PythonScriptEditorUI::_snapshot {} {
    variable ui
    set out {}
    foreach key {scope scriptId name description version requiredApis} {if {[info exists ui($key)]} {dict set out $key $ui($key)}}
    foreach key {text parameters} {if {[info exists ui($key)] && [winfo exists $ui($key)]} {dict set out $key [$ui($key) get 1.0 end-1c]}}
    return $out
}
proc ::GX::PythonScriptEditorUI::_acceptBaseline {} {variable ui;set ui(importDraft) 0;set ui(baseline) [_snapshot];set ui(modified) 0;::GX::sourceSurfaceDocumentIdentity $ui(text) [list $ui(currentId) $ui(currentSha) [zlib crc32 [$ui(text) get 1.0 end-1c]]]}
proc ::GX::PythonScriptEditorUI::_recomputeDirty {} {variable ui;if {![info exists ui(baseline)]} {return};set ui(modified) [expr {([info exists ui(importDraft)] && $ui(importDraft)) || [_snapshot] ne $ui(baseline)}]}
proc ::GX::PythonScriptEditorUI::_sourceChanged {} {_recomputeDirty;_scheduleRefresh}
