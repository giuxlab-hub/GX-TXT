# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only TeX environment presentation under existing Configuration authority.
namespace eval ::GX::LatexEnvironment {variable generation 0;variable request {};variable inventory {};variable search {};variable subscription {};variable status {Refresh to inspect installed TeX tools and resources.}}
proc ::GX::latexEnvironmentPanelBuild {parent row} {
    set p $parent.latex
    ttk::labelframe $p -text {Local LaTeX environment — read-only} -padding 8
    grid $p -row $row -column 0 -columnspan 4 -sticky nsew -padx 8 -pady 8
    ttk::button $p.refresh -text {Refresh LaTeX environment} -command ::GX::latexEnvironmentRefresh
    ttk::button $p.cancel -text Cancel -command ::GX::latexEnvironmentCancel
    ttk::entry $p.search -textvariable ::GX::LatexEnvironment::search
    ttk::label $p.status -textvariable ::GX::LatexEnvironment::status -wraplength 900
    ttk::treeview $p.items -columns {kind version location status} -show {tree headings} -height 12
    $p.items heading #0 -text {Tool / package / class / font}
    foreach {id title} {kind Kind version Version location Location status Status} {$p.items heading $id -text $title;$p.items column $id -width 170 -stretch 1}
    ttk::scrollbar $p.vertical -command [list $p.items yview]
    ttk::scrollbar $p.horizontal -orient horizontal -command [list $p.items xview]
    $p.items configure -yscrollcommand [list $p.vertical set] -xscrollcommand [list $p.horizontal set]
    grid $p.refresh -row 0 -column 0 -sticky w;grid $p.cancel -row 0 -column 1 -sticky w
    grid $p.search -row 0 -column 2 -sticky ew;grid $p.status -row 1 -column 0 -columnspan 4 -sticky ew
    grid $p.items -row 2 -column 0 -columnspan 3 -sticky nsew;grid $p.vertical -row 2 -column 3 -sticky ns
    grid $p.horizontal -row 3 -column 0 -columnspan 3 -sticky ew
    grid columnconfigure $p 2 -weight 1;grid rowconfigure $p 2 -weight 1
    trace add variable ::GX::LatexEnvironment::search write ::GX::_latexEnvironmentSearch
    set ::GX::LatexEnvironment::subscription [configurationSubscribe ::GX::_latexEnvironmentConfigurationChanged]
    bind $p <Destroy> [list ::GX::_latexEnvironmentDestroyed $p %W]
}
proc ::GX::_latexEnvironmentDestroyed {parent actual} {
    if {$parent ne $actual} return
    latexEnvironmentCancel
    trace remove variable ::GX::LatexEnvironment::search write ::GX::_latexEnvironmentSearch
    if {$::GX::LatexEnvironment::subscription ne {}} {configurationUnsubscribe $::GX::LatexEnvironment::subscription;set ::GX::LatexEnvironment::subscription {}}
}
proc ::GX::latexEnvironmentCancel {} {
    incr ::GX::LatexEnvironment::generation
    if {$::GX::LatexEnvironment::request ne {}} {catch {scriptJobRequestCancel $::GX::LatexEnvironment::request};set ::GX::LatexEnvironment::request {};set ::GX::LatexEnvironment::status {Inventory refresh cancelled. Previous observations retained.}}
}
proc ::GX::latexEnvironmentRefresh {} {
    latexEnvironmentCancel
    # Machine Configuration inventory has no Session or Document dependency.
    # Report missing runtimes/launch failures in the existing panel as well.
    try {
        set executable [runtimeToolResolve latex]
        set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_latex_environment.py] --configured $executable]
        set ::GX::LatexEnvironment::status {Inspecting native TeX versions/search roots and installed resources…}
        set generation $::GX::LatexEnvironment::generation
        set ::GX::LatexEnvironment::request [scriptJobAsync $command {} [list ::GX::_latexEnvironmentRefreshed $generation $executable] {timeout_ms 60000 max_bytes 8388608 process_group 1 ui_lifetime 1 label {Read-only LaTeX environment}}]
    } on error {message options} {
        set ::GX::LatexEnvironment::request {}
        set ::GX::LatexEnvironment::status "LaTeX environment unavailable: $message"
    }
}
proc ::GX::_latexEnvironmentRefreshed {generation executable response} {
    if {$generation!=$::GX::LatexEnvironment::generation} return
    set ::GX::LatexEnvironment::request {}
    if {[catch {runtimeToolResolve latex} current] || $current ne $executable} {
        set ::GX::LatexEnvironment::inventory {}
        _latexEnvironmentSearch
        set ::GX::LatexEnvironment::status {LaTeX runtime changed. Refresh its environment inventory.}
        return
    }
    if {![dict get $response ok]} {set ::GX::LatexEnvironment::status [dict get $response error];return}
    set ::GX::LatexEnvironment::inventory [dict get $response result]
    _latexEnvironmentSearch
}
proc ::GX::_latexEnvironmentConfigurationChanged {id} {
    if {$id ne {runtime.latex}} return
    latexEnvironmentCancel
    set ::GX::LatexEnvironment::inventory {}
    _latexEnvironmentSearch
    set ::GX::LatexEnvironment::status {LaTeX runtime changed. Refresh its environment inventory.}
}
proc ::GX::_latexEnvironmentSearch {args} {
    set tree .top.nb.configuration.sections.scripts.latex.items
    if {![winfo exists $tree]} return
    $tree delete [$tree children {}]
    if {$::GX::LatexEnvironment::inventory eq {}} return
    set search [string tolower $::GX::LatexEnvironment::search];set shown 0;set matched 0
    foreach item [dict get $::GX::LatexEnvironment::inventory entries] {
        if {$search ne {} && [string first $search [string tolower $item]]<0} continue
        incr matched
        if {$shown>=500} continue
        $tree insert {} end -text [dict get $item name] -values [list [dict get $item kind] [dict get $item version] [dict get $item location] [dict get $item status]]
        incr shown
    }
    set ::GX::LatexEnvironment::status "$shown of $matched matching observations; [dict get $::GX::LatexEnvironment::inventory total] inventoried. [expr {[dict get $::GX::LatexEnvironment::inventory truncated] ? {Inventory bound reached; narrow search or inspect configured roots.} : {}}] Resource presence is not compilation acceptance."
}
