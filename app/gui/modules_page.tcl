# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildModulesPage {} {
    variable ui
    set f .top.nb.modules
    ttk::label $f.title -text {Modules} -font TkHeadingFont -anchor w
    ttk::label $f.note -text {Activate modules for this Session. Help opens each module's manual. Always available services have a locked switch.} -anchor w -wraplength 900
    pack $f.title -anchor w -padx 12 -pady {10 3}
    pack $f.note -fill x -padx 12 -pady {0 8}
    ttk::frame $f.tools
    ttk::button $f.tools.builder -text {Script Module Builder…} -command ::GX::scriptModuleBuilderOpen
    ttk::button $f.tools.reset -text {Reset selected module runtime…} -command ::GX::resourceLifecycleModuleResetSelected
    ttk::label $f.tools.selected -textvariable ::GX::ui(moduleSelectedName)
    set ui(moduleSelectedName) {Select a module for runtime tools.}
    grid $f.tools.builder -row 0 -column 0 -sticky w -padx 4
    grid $f.tools.reset -row 0 -column 1 -sticky w -padx 4
    grid $f.tools.selected -row 0 -column 2 -sticky ew -padx 8
    grid columnconfigure $f.tools 2 -weight 1
    pack $f.tools -fill x -padx 8 -pady {0 6}
    set ui(moduleFeedback) {}
    ttk::label $f.feedback -textvariable ::GX::ui(moduleFeedback) -anchor w -justify left
    set ui(moduleCards) [uiFieldScrollableCreate $f.cards 900]
    set ui(moduleCardsSignature) {};set ui(moduleSelected) {}
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
    set tools .top.nb.modules.tools
    set buttons [expr {[winfo reqwidth $tools.builder]+[winfo reqwidth $tools.reset]+24}]
    if {$width<$buttons} {
        grid configure $tools.reset -row 1 -column 0 -columnspan 2
        grid configure $tools.selected -row 2 -column 0 -columnspan 3
        $tools.selected configure -wraplength [expr {max(160,$width-40)}]
    } else {
        grid configure $tools.reset -row 0 -column 1 -columnspan 1
        if {$width<$buttons+[font measure TkDefaultFont {Selected module details}]+30} {
            grid configure $tools.selected -row 1 -column 0 -columnspan 3
            $tools.selected configure -wraplength [expr {max(160,$width-40)}]
        } else {
            grid configure $tools.selected -row 0 -column 2 -columnspan 1
            $tools.selected configure -wraplength [expr {max(80,$width-$buttons-40)}]
        }
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
    set requested $::GX::ui(moduleQuick,$id)
    # The switch is a projection, including while a confirmation is open.
    refreshModuleCatalog
    set before [moduleCardsEnabledSnapshot]
    set cancelled 0
    if {[catch {
        if {[moduleIsAlwaysAvailable $id]} {error {This service is always available.}}
        set related [moduleCardsRelatedChanges $id $requested]
        if {[llength $related]} {
            set action [expr {$requested?{enable}:{disable}}]
            set message "[moduleField $id name $id]: $action?\n\nRelated modules may also change:\n[join $related \n]\n\nGX-TXT applies the registered dependency rules."
            if {[tk_messageBox -parent . -type okcancel -default cancel -icon question -title {Module dependencies} -message $message] ne {ok}} {
                set cancelled 1
            }
        }
        if {!$cancelled} {moduleSetEnabled $id $requested}
    } reason options]} {
        refreshModuleCatalog
        moduleCardsFeedbackSet "Activation failed. [moduleField $id name $id]: [moduleOperationalState $id]. $reason"
        tk_messageBox -parent . -icon error -title {Module activation} -message $::GX::ui(moduleFeedback)
        return
    }
    if {$cancelled} {
        moduleCardsFeedbackSet "Cancelled. [moduleField $id name $id]: [moduleOperationalState $id]."
        refreshModuleCatalog
        return
    }
    refreshModuleCatalog
    moduleCardsFeedbackSet [moduleCardsChangeSummary $id $before]
    if {[catch {
        rebuildNativeAnalysisGui
        refreshAnalysisStatus
        refreshManifestPreview
    } reason options]} {
        # A display refresh failure must not pretend that activation rolled back.
        moduleCardsFeedbackSet "$::GX::ui(moduleFeedback) Display refresh failed: $reason"
        tk_messageBox -parent . -icon error -title {Module display refresh} -message $::GX::ui(moduleFeedback)
    }
    refreshModuleCatalog
}
proc ::GX::moduleCardHelp {id} {
    moduleCardSelect $id
    if {[catch {documentationBrowserOpenModuleWindow $id .} reason]} {
        tk_messageBox -parent . -icon info -title {Module manual} -message $reason
    }
}
