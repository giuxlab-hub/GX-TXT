# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::PythonEnvironment {variable generation 0;variable inventory {};variable request {};variable status {Refresh to inspect the exact configured local Python environment.}}
proc ::GX::pythonEnvironmentApiInfo {} {return [dict create api_id PYTHON_ENVIRONMENT_API_v1 api_version 1 local_only 1 operations {inventory preflight organize} discovery nonexecuting package_installation forbidden]}
proc ::GX::pythonEnvironmentCommand {operation args} {
    return [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_python_environment.py] $operation {*}$args]
}
proc ::GX::pythonEnvironmentPreflight {source {report {}}} {
    set command [pythonEnvironmentCommand preflight --source $source]
    if {$report ne {}} {lappend command --report $report}
    set response [exec {*}$command]
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::pythonEnvironmentPanelBuild {parent row} {
    set p $parent.python
    ttk::labelframe $p -text {Local Python environment — read-only} -padding 8
    grid $p -row $row -column 0 -columnspan 4 -sticky nsew -padx 8 -pady 8
    ttk::button $p.refresh -text {Refresh Python environment} -command ::GX::pythonEnvironmentRefresh
    ttk::label $p.status -textvariable ::GX::PythonEnvironment::status -wraplength 900
    ttk::entry $p.search -textvariable ::GX::PythonEnvironment::search
    ttk::treeview $p.modules -columns {classification distributions origin status} -show {tree headings} -height 12
    $p.modules heading #0 -text {Import module}
    foreach {column label} {classification Kind distributions {Distribution / version} origin Origin status Availability} {$p.modules heading $column -text $label;$p.modules column $column -width 150 -stretch 1}
    ttk::scrollbar $p.scroll -command [list $p.modules yview];$p.modules configure -yscrollcommand [list $p.scroll set]
    grid $p.refresh -row 0 -column 0 -sticky w;grid $p.search -row 0 -column 1 -sticky ew
    grid $p.status -row 1 -column 0 -columnspan 3 -sticky ew;grid $p.modules -row 2 -column 0 -columnspan 2 -sticky nsew;grid $p.scroll -row 2 -column 2 -sticky ns
    grid columnconfigure $p 1 -weight 1;grid rowconfigure $p 2 -weight 1
    configurationSubscribe ::GX::pythonEnvironmentConfigurationChanged
    set ::GX::PythonEnvironment::search {};trace add variable ::GX::PythonEnvironment::search write ::GX::_pythonEnvironmentSearch
}
proc ::GX::pythonEnvironmentRefresh {} {
    variable ::GX::PythonEnvironment::generation;variable ::GX::PythonEnvironment::request
    incr generation;set token $generation
    if {$request ne {}} {catch {scriptJobRequestCancel $request}}
    set ::GX::PythonEnvironment::status {Inspecting the configured interpreter without importing discovered packages…}
    if {[catch {set executable [runtimeToolRequired python];set request [scriptJobAsync [pythonEnvironmentCommand inventory] {} [list ::GX::_pythonEnvironmentRefreshed $token $executable] {timeout_ms 30000 max_bytes 4194304 ui_lifetime 1 label {Python environment inventory}}]} reason]} {set ::GX::PythonEnvironment::status $reason}
}
proc ::GX::_pythonEnvironmentRefreshed {generation executable response} {
    if {$generation!=$::GX::PythonEnvironment::generation || $executable ne [runtimeToolResolve python]} return
    set ::GX::PythonEnvironment::request {}
    if {![dict get $response ok]} {set ::GX::PythonEnvironment::status [dict get $response error];return}
    set ::GX::PythonEnvironment::inventory [dict get $response result]
    set identity [dict get $::GX::PythonEnvironment::inventory identity]
    set ::GX::PythonEnvironment::status "[dict get $identity executable] — Python [dict get $identity version]\nPrefix: [dict get $identity prefix]; base: [dict get $identity base_prefix]\n[dict get $::GX::PythonEnvironment::inventory total] module names; scanned [dict get $identity scanned_at]. Static availability does not guarantee successful module initialization."
    _pythonEnvironmentSearch
}
proc ::GX::_pythonEnvironmentSearch {args} {
    set p .top.nb.configuration.sections.scripts.python.modules
    if {![winfo exists $p] || $::GX::PythonEnvironment::inventory eq {}} return
    $p delete [$p children {}]
    set filter [string tolower $::GX::PythonEnvironment::search]
    foreach row [dict get $::GX::PythonEnvironment::inventory entries] {
        if {$filter ne {} && [string first $filter [string tolower $row]]<0} continue
        $p insert {} end -text [dict get $row module] -values [list [dict get $row classification] [dict get $row distributions] [dict get $row origin] [dict get $row status]]
    }
}
# Embedded editor assistance; source persistence remains with Script Registry.
namespace eval ::GX::PythonImports {variable state}
proc ::GX::pythonImportsOpen {editor} {
    variable ::GX::PythonImports::state
    set w $editor.p.imports
    if {[winfo exists $w]} {return $w}
    ttk::frame $w -padding 6
    scriptWorkspaceAssistMount $editor $w
    set text $::GX::PythonScriptEditorUI::ui(text)
    set state($w,editor) $editor;set state($w,token) [interactiveDocumentSessionToken];set state($w,runtime) [runtimeToolResolve python]
    set state($w,statement) {import math};set state($w,search) {};set state($w,status) {Select a module or type an explicit import. Preview before Apply.}
    ttk::label $w.title -text {Manage imports — Overview}
    ttk::entry $w.search -textvariable ::GX::PythonImports::state($w,search)
    ttk::treeview $w.modules -columns {origin} -show {tree headings} -height 7
    $w.modules heading #0 -text {Import name};$w.modules heading origin -text {Origin / availability}
    ttk::entry $w.statement -textvariable ::GX::PythonImports::state($w,statement)
    ttk::frame $w.actions
    foreach {name label command} [list add {Add choice} [list ::GX::pythonImportsChoose $w] preview {Preview source changes} [list ::GX::pythonImportsPreview $w] apply Apply [list ::GX::pythonImportsApply $w] cancel Cancel [list destroy $w]] {ttk::button $w.actions.$name -text $label -command $command;pack $w.actions.$name -side left -padx 2}
    set state($w,statements) {}
    set view [sourceSurfaceCreate $w.preview {mode read_only language python}]
    $view configure -height 12 -width 38
    ttk::label $w.status -textvariable ::GX::PythonImports::state($w,status) -wraplength 360
    pack $w.title $w.search $w.modules $w.statement $w.actions -fill x -pady 3
    pack $w.preview -fill both -expand 1;pack $w.status -fill x
    bind $w.modules <<TreeviewSelect>> [list ::GX::pythonImportsModuleSelected $w]
    bind $w.search <KeyRelease> [list ::GX::pythonImportsFilter $w]
    scriptJobAsync [pythonEnvironmentCommand inventory --limit 2000] {} [list ::GX::pythonImportsInventory $w] {timeout_ms 30000 max_bytes 4194304 ui_lifetime 1 label {Import module inventory}}
    return $w
}
proc ::GX::pythonImportsInventory {w response} {
    if {![winfo exists $w]} return
    variable ::GX::PythonImports::state
    if {![dict get $response ok]} {set state($w,status) [dict get $response error];return}
    set state($w,inventory) [dict get $response result entries];pythonImportsFilter $w
}
proc ::GX::pythonImportsFilter {w} {
    variable ::GX::PythonImports::state
    if {![info exists state($w,inventory)]} return
    $w.modules delete [$w.modules children {}]
    foreach row $state($w,inventory) {
        set name [dict get $row module]
        if {$state($w,search) ne {} && [string first [string tolower $state($w,search)] [string tolower $name]]<0} continue
        $w.modules insert {} end -text $name -values [list "[dict get $row classification] / [dict get $row status]: [dict get $row origin]"]
    }
}
proc ::GX::pythonImportsModuleSelected {w} {variable ::GX::PythonImports::state;set selected [$w.modules selection];if {$selected ne {}} {set state($w,statement) "import [$w.modules item [lindex $selected 0] -text]"}}
proc ::GX::pythonImportsChoose {w} {variable ::GX::PythonImports::state;if {$state($w,statement) ni $state($w,statements)} {lappend state($w,statements) $state($w,statement)};set state($w,status) "Selected: [join $state($w,statements) {; }]"}
proc ::GX::pythonImportsPreview {w} {
    variable ::GX::PythonImports::state
    pythonImportsChoose $w
    set state($w,original) [sourceSurfaceGet $::GX::PythonScriptEditorUI::ui(text)]
    set command [pythonEnvironmentCommand organize]
    foreach statement $state($w,statements) {lappend command --statement $statement}
    scriptJobAsync $command $state($w,original) [list ::GX::pythonImportsPreviewed $w] {timeout_ms 15000 max_bytes 16777216 ui_lifetime 1 label {Import insertion preview}}
}
proc ::GX::pythonImportsPreviewed {w response} {
    if {![winfo exists $w]} return
    variable ::GX::PythonImports::state
    if {![dict get $response ok]} {set state($w,status) [dict get $response error];return}
    set state($w,result) [dict get $response result]
    sourceSurfaceSet $w.preview [dict get $state($w,result) source]
    set state($w,status) "Preview only. Duplicates: [dict get $state($w,result) duplicates]. Apply makes one undoable edit."
}
proc ::GX::pythonImportsApply {w} {
    variable ::GX::PythonImports::state
    if {[catch {
        if {![info exists state($w,result)]} {error {Preview the proposed imports first}}
        if {$state($w,token) ne [interactiveDocumentSessionToken] || $state($w,runtime) ne [runtimeToolResolve python]} {error {Session or interpreter changed; reopen Manage imports}}
        if {[sourceSurfaceGet $::GX::PythonScriptEditorUI::ui(text)] ne $state($w,original)} {error {Source changed after preview; generate a new preview}}
        if {[dict get $state($w,result) changed]} {sourceSurfaceReplace $::GX::PythonScriptEditorUI::ui(text) [dict get $state($w,result) source]}
        destroy $w
    } reason]} {set state($w,status) $reason}
}

proc ::GX::pythonEnvironmentConfigurationChanged {id} {
    if {$id ne {runtime.python}} return
    incr ::GX::PythonEnvironment::generation
    if {$::GX::PythonEnvironment::request ne {}} {catch {scriptJobRequestCancel $::GX::PythonEnvironment::request};set ::GX::PythonEnvironment::request {}}
    set ::GX::PythonEnvironment::inventory {};set ::GX::PythonEnvironment::status {Interpreter changed. Refresh its environment inventory.}
    set p .top.nb.configuration.sections.scripts.python.modules
    if {[llength [info commands winfo]] && [winfo exists $p]} {$p delete [$p children {}];after idle ::GX::pythonEnvironmentRefresh}
}
