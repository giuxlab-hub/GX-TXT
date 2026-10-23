# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildModulesPage {} {
    variable ui
    set f .top.nb.modules
    ttk::label $f.title -text {Analysis Modules} -font TkHeadingFont -anchor w
    ttk::label $f.note -text {Show or hide enabled module panes in Analysis. Use Run / recalculate now there to select calculations. Enable or disable modules in Configuration > Modules. Help opens each module's manual.} -anchor w -wraplength 900
    pack $f.title -anchor w -padx 12 -pady {10 3}
    pack $f.note -fill x -padx 12 -pady {0 8}
    ttk::frame $f.search
    ttk::label $f.search.label -text {Module name:}
    ttk::entry $f.search.query -textvariable ::GX::moduleSearch -width 32
    bind $f.search.query <KeyRelease> ::GX::refreshModuleCatalog
    pack $f.search.label $f.search.query -side left -padx 4
    # Native check indicators show visibility; rows keep neutral theme styling.
    ttk::frame $f.tools
    ttk::button $f.tools.builder -text {Script Module Builder…} -command ::GX::scriptModuleBuilderOpen
    ttk::button $f.tools.reset -text {Reset selected module runtime…} -command ::GX::resourceLifecycleModuleResetSelected
    ttk::label $f.tools.selected -textvariable ::GX::ui(moduleSelectedName)
    set ui(moduleSelectedName) {Select a module for runtime tools.}
    foreach row {0 1 2 3} {ttk::frame $f.tools.line$row}
    pack $f.tools -fill x -padx 8 -pady {0 6}
    raise $f.search $f.tools
    foreach w [list $f.tools.builder $f.tools.reset $f.tools.selected] {raise $w}
    set ui(moduleFeedback) {}
    ttk::label $f.feedback -textvariable ::GX::ui(moduleFeedback) -anchor w -justify left
    set ui(moduleCards) [uiFieldScrollableCreate $f.cards 900]
    set ui(moduleCardsSignature) __unbuilt__;set ui(moduleSelected) {}
    pack $f.cards -fill both -expand 1 -padx 8 -pady {0 8}
    bind $ui(moduleCards) <Configure> +[list ::GX::modulesCardsLayout %W %w]
    bind $ui(moduleCards) <Map> +[list ::GX::modulesCardsMapped %W]
    bind $f <Configure> [list ::GX::modulesPageFit %W %w]
    trace add variable ::GX::currentSession write ::GX::modulesCardsSessionChanged
    bind $f <Destroy> [list ::GX::modulesCardsDispose %W]
    refreshModuleCatalog
}
proc ::GX::modulesCardsSessionChanged {args} {
    variable ui
    if {[info exists ui(moduleCardsRefresh)]} {after cancel $ui(moduleCardsRefresh)}
    set ui(moduleCardsRefresh) [after idle ::GX::refreshModuleCatalog]
}
proc ::GX::modulesCardsDispose {actual} {
    if {$actual ne {.top.nb.modules}} return
    trace remove variable ::GX::currentSession write ::GX::modulesCardsSessionChanged
    if {[info exists ::GX::ui(moduleCardsRefresh)]} {after cancel $::GX::ui(moduleCardsRefresh)}
    unset -nocomplain ::GX::ui(moduleCardsRefresh)
}
proc ::GX::modulesPageFit {actual width} {
    if {$actual ne {.top.nb.modules}} return
    .top.nb.modules.note configure -wraplength [expr {max(160,$width-30)}]
    .top.nb.modules.feedback configure -wraplength [expr {max(160,$width-30)}]
    set f .top.nb.modules
    set tools $f.tools
    set available [expr {max(160,$width-32)}]
    set signature $available
    if {[info exists ::GX::ui(moduleToolbarLayout)] && $::GX::ui(moduleToolbarLayout) eq $signature} return
    set ::GX::ui(moduleToolbarLayout) $signature
    # Keep the original controls and commands in reading/focus order. Each
    # existing control moves to the next line only when its measured width
    # cannot fit; the final status wraps instead of being clipped.
    foreach w [list $f.search $tools.builder $tools.reset $tools.selected] {pack forget $w}
    foreach row {0 1 2 3} {pack forget $tools.line$row}
    set row 0;set used 0
    pack $tools.line$row -fill x -anchor w
    foreach w [list $f.search $tools.builder $tools.reset $tools.selected] {
        set needed [expr {[winfo reqwidth $w]+8}]
        if {$w eq "$tools.selected"} {
            set needed [expr {[font measure TkDefaultFont {Select a module for runtime tools.}]+16}]
        }
        if {$used && $used+$needed>$available} {
            incr row;set used 0
            pack $tools.line$row -fill x -anchor w
        }
        if {$w eq "$tools.selected"} {
            $w configure -wraplength [expr {max(80,$available-$used-16)}] -justify left
            pack $w -in $tools.line$row -side left -fill x -expand 1 -padx 4
        } else {
            pack $w -in $tools.line$row -side left -padx 4 -pady 2
        }
        incr used $needed
    }
}
proc ::GX::modulesCardsMapped {actual} {
    if {[info exists ::GX::ui(moduleCards)] && $actual eq $::GX::ui(moduleCards)} {modulesCardsLayout $actual [winfo width $actual]}
}
proc ::GX::modulesCardsLayout {actual width} {
    variable ui
    if {![info exists ui(moduleCards)] || $actual ne $ui(moduleCards)} return
    if {$width<100 || ![winfo ismapped $actual]} return
    # Measure the real controls: fonts and DPI can make a 900px pair unusable.
    set minimum 0
    foreach group $ui(moduleGroupCards) {
        foreach label [dict get $ui(moduleCardLabels) $group] {
            set row [winfo parent $label]
            set controls [expr {[winfo reqwidth $row.toggle]+[winfo reqwidth $row.state]+[winfo reqwidth $row.help]+56}]
            set labelFont [$label cget -font]
            if {$labelFont eq {}} {set labelFont TkDefaultFont}
            set minimum [expr {max($minimum,$controls+[font measure $labelFont {Scientific analysis module}])}]
        }
    }
    set columns [expr {$width>=max(900,2*$minimum)?2:1}]
    if {[info exists ui(moduleCardsColumns)] && $ui(moduleCardsColumns)==$columns && [info exists ui(moduleCardsWidth)] && abs($ui(moduleCardsWidth)-$width)<3 && [info exists ui(moduleCardsMinimum)] && $ui(moduleCardsMinimum)==$minimum} return
    set ui(moduleCardsMinimum) $minimum
    set ui(moduleCardsColumns) $columns;set ui(moduleCardsWidth) $width
    foreach column {0 1} {
        grid columnconfigure $actual $column -weight [expr {$column<$columns?1:0}] -uniform [expr {$column<$columns?{moduleCards}:{}}] -minsize 0
        if {$column<$columns} {
            grid $actual.column$column -row 0 -column $column -sticky new -padx 5
        } else {
            grid remove $actual.column$column
        }
    }
    set n 0
    foreach group $ui(moduleGroupCards) {
        # Each column stacks independently; a tall group must not leave a
        # matching blank region below its shorter neighbour.
        grid $group -in $actual.column[expr {$n%$columns}] -row [expr {$n/$columns}] -column 0 -sticky new -pady 5
        foreach label [dict get $ui(moduleCardLabels) $group] {
            set row [winfo parent $label]
            set controls [expr {[winfo reqwidth $row.toggle]+[winfo reqwidth $row.state]+[winfo reqwidth $row.help]+56}]
            $label configure -wraplength [expr {max(40,$width/$columns-$controls)}]
        }
        incr n
    }
}
proc ::GX::moduleCardSelect {id} {
    set ::GX::ui(moduleSelected) $id
    set ::GX::ui(moduleSelectedName) [moduleField $id name $id]
}
proc ::GX::moduleCardToggle {id} {
    moduleCardSelect $id
    if {![moduleAnalysisEligible $id] || ![moduleIsEnabled $id]} {return}
    moduleSetAnalysisShown $id $::GX::ui(moduleShown,$id)
    rebuildNativeAnalysisGui
    refreshAnalysisStatus
    refreshManifestPreview
    refreshModuleCatalog
}
proc ::GX::moduleCardHelp {id} {
    moduleCardSelect $id
    if {[catch {documentationBrowserOpenModuleWindow $id .} reason]} {
        tk_messageBox -parent . -icon info -title {Module manual} -message $reason
    }
}
