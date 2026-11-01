# SPDX-License-Identifier: GPL-3.0-or-later
# A temporary read-only projection within Configuration > Runtime.
namespace eval ::GX::PythonAuditUI {
    variable frame {};variable generation 0;variable request {};variable report {}
    variable scope {Registered Python source};variable reference {};variable references {}
    variable search {};variable availability All;variable kind All
    variable status {Choose a scope, then refresh. No source or dependency is executed.}
    variable interpreter {};variable selection {};variable originFocus {};variable layoutAfter {}
}
proc ::GX::_pythonAuditInfoCreate {widget variableName lines} {
    # Bound source paths, environment and diagnostics independently of their
    # length. Native text/scrollbars retain every byte without starving rows.
    ttk::frame $widget
    uiFieldComponentCreate $widget.text log [dict create height $lines width 1] {} {}
    $widget.text configure -font TkTextFont -wrap none -takefocus 1 -highlightthickness 1
    set background [ttk::style lookup TFrame -background]
    set foreground [ttk::style lookup TLabel -foreground]
    if {$background ne {}} {$widget.text configure -background $background}
    if {$foreground ne {}} {$widget.text configure -foreground $foreground}
    ttk::scrollbar $widget.y -command [list $widget.text yview]
    ttk::scrollbar $widget.x -orient horizontal -command [list $widget.text xview]
    $widget.text configure -yscrollcommand [list $widget.y set] -xscrollcommand [list $widget.x set]
    grid $widget.text -row 0 -column 0 -sticky nsew
    grid $widget.y -row 0 -column 1 -sticky ns
    grid $widget.x -row 1 -column 0 -sticky ew
    grid columnconfigure $widget 0 -weight 1;grid rowconfigure $widget 0 -weight 1
    set callback [list ::GX::_pythonAuditInfoSync $widget $variableName]
    trace add variable $variableName write $callback
    bind $widget <Destroy> [list ::GX::_pythonAuditInfoDisposed $widget $variableName $callback %W]
    _pythonAuditInfoSync $widget $variableName
}
proc ::GX::_pythonAuditInfoSync {widget variableName args} {
    if {![winfo exists $widget.text]} return
    upvar #0 $variableName value
    $widget.text configure -state normal
    $widget.text delete 1.0 end
    $widget.text insert 1.0 $value
    $widget.text configure -state disabled
}
proc ::GX::_pythonAuditInfoDisposed {widget variableName callback actual} {
    if {$widget eq $actual} {catch {trace remove variable $variableName write $callback}}
}
proc ::GX::pythonEnvironmentAuditOverlayOpen {} {
    variable ::GX::PythonAuditUI::frame
    if {$frame ne {} && [winfo exists $frame]} {raise $frame;focus $frame.controls.refresh;return}
    set tab .top.nb.configuration.sections.runtime
    if {![winfo exists $tab]} return
    set ::GX::PythonAuditUI::originFocus [focus]
    set frame $tab.import_audit
    set ::GX::PythonAuditUI::report {};set ::GX::PythonAuditUI::search {}
    set ::GX::PythonAuditUI::availability All;set ::GX::PythonAuditUI::kind All
    set ::GX::PythonAuditUI::status {Choose a scope, then refresh. Static availability does not test module initialization.}
    ttk::frame $frame -padding 10 -relief solid -borderwidth 1
    place $frame -relx 0 -rely 0 -relwidth 1 -relheight 1
    ttk::frame $frame.header
    ttk::label $frame.header.title -text {Python imports — read-only review}
    ttk::button $frame.header.close -text Close -command ::GX::pythonEnvironmentAuditOverlayClose
    pack $frame.header.close -side right;pack $frame.header.title -side left
    grid $frame.header -row 0 -column 0 -sticky ew -pady {0 6}
    ttk::frame $frame.controls
    ttk::combobox $frame.controls.scope -state readonly -width 18 -textvariable ::GX::PythonAuditUI::scope -values {{Registered Python source} {Installed framework / modules}}
    ttk::combobox $frame.controls.reference -state readonly -width 12 -textvariable ::GX::PythonAuditUI::reference
    ttk::button $frame.controls.refresh -text Refresh -command ::GX::pythonEnvironmentAuditOverlayRefresh
    ttk::button $frame.controls.cancel -text Cancel -state disabled -command ::GX::pythonEnvironmentAuditOverlayCancel
    grid $frame.controls.scope -row 0 -column 0 -sticky ew -padx {0 4}
    grid $frame.controls.reference -row 0 -column 1 -sticky ew
    grid $frame.controls.refresh -row 0 -column 2 -sticky ew -padx 4
    grid $frame.controls.cancel -row 0 -column 3 -sticky ew
    grid columnconfigure $frame.controls 0 -weight 1;grid columnconfigure $frame.controls 1 -weight 1
    bind $frame.controls.scope <<ComboboxSelected>> ::GX::pythonEnvironmentAuditScopeChanged
    bind $frame.controls.reference <<ComboboxSelected>> ::GX::pythonEnvironmentAuditScopeChanged
    grid $frame.controls -row 1 -column 0 -sticky ew
    _pythonAuditInfoCreate $frame.interpreter ::GX::PythonAuditUI::interpreter 1
    _pythonAuditInfoCreate $frame.status ::GX::PythonAuditUI::status 1
    grid $frame.interpreter -row 2 -column 0 -sticky ew -pady 2
    grid $frame.status -row 3 -column 0 -sticky ew -pady {2 6}
    ttk::frame $frame.filters
    ttk::label $frame.filters.label -text Filter
    ttk::entry $frame.filters.search -textvariable ::GX::PythonAuditUI::search -width 12
    ttk::combobox $frame.filters.status -state readonly -width 11 -textvariable ::GX::PythonAuditUI::availability -values {All AVAILABLE MISSING OPTIONAL UNKNOWN ERROR}
    ttk::combobox $frame.filters.kind -state readonly -width 11 -textvariable ::GX::PythonAuditUI::kind -values {All builtin stdlib local third_party unknown}
    ttk::button $frame.filters.clear -text Clear -command ::GX::pythonEnvironmentAuditOverlayClearFilter
    pack $frame.filters.label -side left -padx {0 4}
    pack $frame.filters.clear $frame.filters.kind $frame.filters.status -side right -padx 3
    pack $frame.filters.search -side left -fill x -expand 1
    bind $frame.filters.search <KeyRelease> ::GX::pythonEnvironmentAuditOverlayFilter
    foreach widget {status kind} {bind $frame.filters.$widget <<ComboboxSelected>> ::GX::pythonEnvironmentAuditOverlayFilter}
    grid $frame.filters -row 4 -column 0 -sticky ew -pady {0 4}
    ttk::frame $frame.results
    ttk::treeview $frame.results.tree -show {tree headings} -columns {status kind distribution origin source reason} -height 10 -selectmode browse
    set tree $frame.results.tree
    $tree heading #0 -text {Import module};$tree column #0 -width 190 -minwidth 100 -stretch 0
    foreach {column label width} {status Availability 100 kind Kind 100 distribution {Distribution / version} 180 origin Origin 260 source {Source / line} 240 reason Explanation 480} {
        $tree heading $column -text $label;$tree column $column -width $width -minwidth 80 -stretch 0
    }
    uiFieldInspectionColumnsFit $tree
    set background [ttk::style lookup Treeview -fieldbackground]
    if {$background eq {}} {set background white}
    lassign [winfo rgb $tree $background] red green blue
    set dark [expr {.2126*$red+.7152*$green+.0722*$blue<32768}]
    $tree tag configure AVAILABLE -foreground [expr {$dark?{#65df91}:{#14823b}}]
    $tree tag configure MISSING -foreground [expr {$dark?{#ff8e8e}:{#c82929}}]
    # Optional and unresolved records retain the theme's neutral foreground.
    ttk::scrollbar $frame.results.y -command [list $tree yview]
    ttk::scrollbar $frame.results.x -orient horizontal -command [list $tree xview]
    $tree configure -yscrollcommand [list $frame.results.y set] -xscrollcommand [list $frame.results.x set]
    grid $tree -row 0 -column 0 -sticky nsew;grid $frame.results.y -row 0 -column 1 -sticky ns
    grid $frame.results.x -row 1 -column 0 -sticky ew
    grid rowconfigure $frame.results 0 -weight 1;grid columnconfigure $frame.results 0 -weight 1
    grid $frame.results -row 5 -column 0 -sticky nsew
    _pythonAuditInfoCreate $frame.detail ::GX::PythonAuditUI::selection 2
    grid $frame.detail -row 6 -column 0 -sticky ew -pady {4 0}
    grid columnconfigure $frame 0 -weight 1;grid rowconfigure $frame 5 -weight 1
    bind $tree <<TreeviewSelect>> ::GX::pythonEnvironmentAuditOverlaySelect
    foreach event {<Map> <Configure> <<ThemeChanged>>} {
        bind $tree $event +[list ::GX::_pythonAuditResultsSchedule $frame]
    }
    bind $frame <Configure> [list ::GX::pythonEnvironmentAuditOverlaySize $frame %w]
    bind $frame <Destroy> [list ::GX::pythonEnvironmentAuditOverlayDestroyed $frame %W]
    set tag GXRuntimeImportAudit
    foreach child [concat [list $tree] [winfo children $frame.interpreter] [winfo children $frame.status] [winfo children $frame.detail] [winfo children $frame.controls] [winfo children $frame.filters] [winfo children $frame.header]] {
        bindtags $child [linsert [bindtags $child] 0 $tag]
    }
    bind $tag <Escape> {::GX::pythonEnvironmentAuditOverlayClose;break}
    pythonEnvironmentAuditOverlayReferences
    pythonEnvironmentAuditScopeChanged
    focus $frame.controls.refresh
}
proc ::GX::pythonEnvironmentAuditOverlayReferences {} {
    variable ::GX::PythonAuditUI::frame
    set refs {}
    foreach metadata [scriptRegistryList] {
        if {[dict get $metadata language] eq {Python} && ![dict exists $metadata access_policy]} {lappend refs "[dict get $metadata scope]:[dict get $metadata id]"}
    }
    set ::GX::PythonAuditUI::references $refs
    $frame.controls.reference configure -values $refs
    if {$::GX::PythonAuditUI::reference ni $refs} {set ::GX::PythonAuditUI::reference [lindex $refs 0]}
    if {$refs eq {}} {set ::GX::PythonAuditUI::scope {Installed framework / modules}}
}
proc ::GX::pythonEnvironmentAuditOverlaySize {frame width} {
    if {[winfo exists $frame.results.tree]} {uiFieldInspectionColumnsSchedule $frame.results.tree;_pythonAuditResultsSchedule $frame}
}
proc ::GX::_pythonAuditResultsMinimum {frame} {
    dict unset ::GX::PythonAuditUI::layoutAfter $frame
    if {[winfo exists $frame.results.tree]} {
        # InspectionColumns owns the actual scaled row style. Reserve space
        # from that style rather than introducing a competing font/row policy.
        set style [$frame.results.tree cget -style]
        set rowHeight [ttk::style lookup $style -rowheight]
        if {![string is integer -strict $rowHeight]} {set rowHeight [expr {[font metrics TkDefaultFont -linespace]+8}]}
        # Heading padding belongs to the active native theme. Font linespace
        # alone underestimates Clam's heading and can leave only two full rows.
        set heading [font metrics TkHeadingFont -linespace]
        set tree $frame.results.tree;set lastHeading -1
        for {set y 0} {$y<min(256,[winfo height $tree])} {incr y} {
            set region [$tree identify region 20 $y]
            if {$region in {heading separator}} {set lastHeading $y} elseif {$lastHeading>=0} {break}
        }
        if {$lastHeading>=0} {set heading [expr {max($heading,$lastHeading+3)}]}
        set minimum [expr {3*$rowHeight+$heading+[winfo reqheight $frame.results.x]+8}]
        if {[grid rowconfigure $frame 5 -minsize]!=$minimum} {grid rowconfigure $frame 5 -minsize $minimum}
    }
}
proc ::GX::_pythonAuditResultsSchedule {frame} {
    if {![winfo exists $frame.results.tree]} return
    # Native style updates may emit ThemeChanged themselves. This coalesced
    # callback only measures/reserves geometry; it never writes a row style or
    # schedules InspectionColumns again, avoiding a style/layout feedback loop.
    if {![dict exists $::GX::PythonAuditUI::layoutAfter $frame]} {
        dict set ::GX::PythonAuditUI::layoutAfter $frame [after idle [list ::GX::_pythonAuditResultsMinimum $frame]]
    }
}
proc ::GX::pythonEnvironmentAuditScopeChanged {} {
    variable ::GX::PythonAuditUI::frame
    pythonEnvironmentAuditOverlayCancel {Scope changed. Refresh to inspect the selected source.}
    if {$frame eq {} || ![winfo exists $frame]} return
    $frame.controls.reference configure -state [expr {$::GX::PythonAuditUI::scope eq {Registered Python source}?{readonly}:{disabled}}]
    set python [runtimeToolResolve python]
    set ::GX::PythonAuditUI::interpreter "Configured interpreter: $python"
}
proc ::GX::pythonEnvironmentAuditOverlayRefresh {} {
    variable ::GX::PythonAuditUI::frame;variable ::GX::PythonAuditUI::generation
    variable ::GX::PythonAuditUI::request
    pythonEnvironmentAuditOverlayCancel {}
    if {$frame eq {} || ![winfo exists $frame]} return
    if {[info exists ::GX::configurationUi(runtime.python)] && $::GX::configurationUi(runtime.python) ne [configurationGet runtime.python]} {
        set ::GX::PythonAuditUI::status {The Python path has unsaved changes. Save it before auditing its environment.};return
    }
    if {$::GX::PythonAuditUI::scope eq {Registered Python source}} {
        set scope [dict create scope script reference $::GX::PythonAuditUI::reference]
    } else {set scope {scope framework}}
    set token $generation
    set ::GX::PythonAuditUI::status {Reading admitted sources and static module specifications…}
    $frame.controls.refresh configure -state disabled;$frame.controls.cancel configure -state normal
    if {[catch {set request [pythonEnvironmentAuditImports $scope [list ::GX::pythonEnvironmentAuditOverlayFinished $token]]} reason]} {
        set ::GX::PythonAuditUI::status $reason
        $frame.controls.refresh configure -state normal;$frame.controls.cancel configure -state disabled
    }
}
proc ::GX::pythonEnvironmentAuditOverlayFinished {token response} {
    variable ::GX::PythonAuditUI::frame;variable ::GX::PythonAuditUI::report
    if {$token!=$::GX::PythonAuditUI::generation || $frame eq {} || ![winfo exists $frame]} return
    set ::GX::PythonAuditUI::request {}
    $frame.controls.refresh configure -state normal;$frame.controls.cancel configure -state disabled
    if {![dict get $response ok]} {set ::GX::PythonAuditUI::status [dict get $response error];return}
    set report [dict get $response result];set identity [dict get $report identity]
    set ::GX::PythonAuditUI::interpreter "[dict get $identity executable] — Python [dict get $identity version]\nPrefix: [dict get $identity prefix]; base: [dict get $identity base_prefix]; scanned [dict get $identity scanned_at]"
    set summary [dict get $report summary]
    set completeness [expr {[dict get $report complete]?{Complete admitted scope}:{Incomplete: review errors or choose a smaller scope}}]
    set ::GX::PythonAuditUI::status "[dict get $report file_count] files; present [dict get $summary AVAILABLE], missing [dict get $summary MISSING], optional [dict get $summary OPTIONAL], unknown [dict get $summary UNKNOWN], errors [dict get $summary ERROR]. $completeness."
    if {[dict get $summary MISSING]>0} {set ::GX::PythonAuditUI::availability MISSING}
    pythonEnvironmentAuditOverlayFilter
}
proc ::GX::pythonEnvironmentAuditOverlayFilter {} {
    variable ::GX::PythonAuditUI::frame;variable ::GX::PythonAuditUI::report
    if {$frame eq {} || ![winfo exists $frame.results.tree]} return
    set tree $frame.results.tree;$tree delete [$tree children {}]
    set ::GX::PythonAuditUI::selection {}
    if {$report eq {}} return
    set index 0
    foreach row [dict get $report imports] {
        set id row[incr index]
        if {$::GX::PythonAuditUI::availability ne {All} && [dict get $row status] ne $::GX::PythonAuditUI::availability} continue
        if {$::GX::PythonAuditUI::kind ne {All} && [dict get $row classification] ne $::GX::PythonAuditUI::kind} continue
        if {$::GX::PythonAuditUI::search ne {} && [string first [string tolower $::GX::PythonAuditUI::search] [string tolower $row]]<0} continue
        set versions {};dict for {name version} [dict get $row distributions] {lappend versions "$name $version"}
        if {$versions eq {}} {set versions [list {No distribution mapping}]}
        set relative [datasetPublicationV2DictDefault $row relative_file [file tail [dict get $row source_file]]]
        $tree insert {} end -id $id -text [dict get $row module] -values [list [dict get $row status] [dict get $row classification] [join $versions {; }] [datasetPublicationV2DictDefault $row origin {}] "$relative:[dict get $row line]" [dict get $row reason]] -tags [list [dict get $row status]]
    }
    if {[$tree children {}] eq {}} {
        set ::GX::PythonAuditUI::selection [expr {[dict get $report imports] eq {}?{No imports were found in the admitted source scope.}:{No rows match these filters. Clear the filters to see all results.}}]
    }
    uiFieldInspectionColumnsSchedule $tree
    _pythonAuditResultsSchedule $frame
}
proc ::GX::pythonEnvironmentAuditOverlayClearFilter {} {
    set ::GX::PythonAuditUI::search {};set ::GX::PythonAuditUI::availability All;set ::GX::PythonAuditUI::kind All
    pythonEnvironmentAuditOverlayFilter
}
proc ::GX::pythonEnvironmentAuditOverlaySelect {} {
    variable ::GX::PythonAuditUI::frame
    if {$frame eq {} || ![winfo exists $frame]} return
    set selected [$frame.results.tree selection]
    if {$selected eq {}} return
    set index [expr {[string range [lindex $selected 0] 3 end]-1}]
    set row [lindex [dict get $::GX::PythonAuditUI::report imports] $index]
    set ::GX::PythonAuditUI::selection "[dict get $row source_file]:[dict get $row line]\n[dict get $row reason]"
    foreach source [dict get $::GX::PythonAuditUI::report sources] {
        if {[dict get $source path] eq [dict get $row source_file]} {
            append ::GX::PythonAuditUI::selection "\n[dict get $source logical_id] — SHA-256 [dict get $source sha256]"
            break
        }
    }
}
proc ::GX::pythonEnvironmentAuditOverlayCancel {{message {Review cancelled. Refresh when ready.}}} {
    variable ::GX::PythonAuditUI::generation;variable ::GX::PythonAuditUI::request
    variable ::GX::PythonAuditUI::frame
    incr generation
    if {$request ne {}} {catch {pythonEnvironmentAuditCancel $request};set request {}}
    set ::GX::PythonAuditUI::report {};set ::GX::PythonAuditUI::selection {}
    if {$frame ne {} && [winfo exists $frame]} {
        $frame.controls.refresh configure -state normal;$frame.controls.cancel configure -state disabled
        $frame.results.tree delete [$frame.results.tree children {}]
        set ::GX::PythonAuditUI::status $message
    }
}
proc ::GX::pythonEnvironmentAuditRuntimeEdited {} {
    if {$::GX::PythonAuditUI::frame ne {} && [winfo exists $::GX::PythonAuditUI::frame]} {pythonEnvironmentAuditOverlayCancel {Interpreter selection changed. Save the desired path and refresh.}}
}
proc ::GX::pythonEnvironmentAuditOverlayClose {} {
    variable ::GX::PythonAuditUI::frame
    pythonEnvironmentAuditOverlayCancel {}
    set old $frame;set frame {}
    if {$old ne {} && [winfo exists $old]} {destroy $old}
    set target $::GX::PythonAuditUI::originFocus
    if {$target ne {} && [winfo exists $target]} {focus $target}
}
proc ::GX::pythonEnvironmentAuditOverlayDestroyed {expected actual} {
    if {$expected eq $actual && [dict exists $::GX::PythonAuditUI::layoutAfter $expected]} {
        after cancel [dict get $::GX::PythonAuditUI::layoutAfter $expected]
        dict unset ::GX::PythonAuditUI::layoutAfter $expected
    }
    if {$expected ne $actual || $::GX::PythonAuditUI::frame ne $expected} return
    pythonEnvironmentAuditOverlayCancel {};set ::GX::PythonAuditUI::frame {}
}
