# SPDX-License-Identifier: GPL-3.0-or-later
# Shared host editor; no parser, parameter store or namespace selector in UI.
namespace eval ::GX::ParameterEditor {variable ui}
proc ::GX::parameterEditorBuild {frame token} {
    variable ::GX::ParameterEditor::ui
    set ui($frame,token) $token;set ui($frame,name) {};set ui($frame,formula) {};set ui($frame,status) {}
    ttk::treeview $frame.tree -columns {formula value dependencies unit} -show {tree headings} -selectmode browse
    $frame.tree heading #0 -text Name;$frame.tree column #0 -width 150
    foreach column {formula value dependencies unit} {$frame.tree heading $column -text [string totitle $column];$frame.tree column $column -width 140}
    pack $frame.tree -fill both -expand 1
    ttk::frame $frame.fields;pack $frame.fields -fill x -pady 6
    foreach key {name formula} {
        ttk::label $frame.fields.${key}Label -text [string totitle $key]
        ttk::entry $frame.fields.$key -textvariable ::GX::ParameterEditor::ui($frame,$key) -width 25
        pack $frame.fields.${key}Label $frame.fields.$key -side left -padx 3
    }
    ttk::frame $frame.actions;pack $frame.actions -fill x
    foreach {key label} {save {Create / Update} delete Delete clear New refresh Refresh} {
        ttk::button $frame.actions.$key -text $label -command [list ::GX::parameterEditorAction $frame $key];pack $frame.actions.$key -side left -padx 4
    }
    ttk::label $frame.help -text {Formulas: + - * / ^, functions, local names, session.name (Workspace only). Angles use radians.} -wraplength 850
    ttk::label $frame.status -textvariable ::GX::ParameterEditor::ui($frame,status) -wraplength 850 -foreground #a03020
    pack $frame.help $frame.status -fill x -pady 4
    bind $frame.tree <<TreeviewSelect>> [list ::GX::parameterEditorSelect $frame]
    bind $frame.fields.formula <Return> [list ::GX::parameterEditorAction $frame save]
    parameterEditorAction $frame refresh
}
proc ::GX::parameterEditorSelect {frame} {
    variable ::GX::ParameterEditor::ui
    set selection [$frame.tree selection];if {[llength $selection]!=1} return
    set name [lindex $selection 0];set ui($frame,name) $name;set ui($frame,formula) [lindex [$frame.tree item $name -values] 0]
}
proc ::GX::parameterEditorAction {frame action} {
    variable ::GX::ParameterEditor::ui
    if {[catch {
        set token $ui($frame,token);set name [string trim $ui($frame,name)]
        if {$action eq "clear"} {set ui($frame,name) {};set ui($frame,formula) {};set ui($frame,status) {};return}
        if {$action in {save delete}} {
            if {$token eq "session"} {set defs [parameterSessionDefinitions]} else {set defs [parameterDefinitions $token]}
            set definition [datasetPublicationV2DictDefault $defs $name {}];dict set definition formula $ui($frame,formula)
            if {$token eq "session"} {
                if {$action eq "save"} {parameterSessionSet $name $definition} else {parameterSessionDelete $name}
            } else {if {$action eq "save"} {parameterSet $token $name $definition} else {parameterDelete $token $name}}
        }
        set values [expr {$token eq "session"?[parameterSessionList]:[parameterList $token]}]
        $frame.tree delete [$frame.tree children {}]
        dict for {name receipt} $values {$frame.tree insert {} end -id $name -text $name -values [list [dict get $receipt formula] [format %.12g [dict get $receipt value]] [lsort -unique [dict get $receipt dependencies]] [datasetPublicationV2DictDefault $receipt unit {}]]}
        set ui($frame,status) [expr {$action eq "refresh"?{}:"Parameter state saved."}]
    } message]} {set ui($frame,status) $message}
}
proc ::GX::parameterEditorOpen {token {parent .}} {
    set w $parent.parameters;if {[winfo exists $w]} {raise $w;return $w}
    toplevel $w;wm title $w Parameters;wm geometry $w 860x430;wm transient $w $parent
    parameterEditorBuild $w $token;return $w
}
