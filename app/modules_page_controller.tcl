# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::moduleGroups {} {
    variable moduleOrder
    set groups {}
    foreach id $moduleOrder {
        if {![moduleAnalysisEligible $id]} continue
        set g [string trim [moduleField $id group "General"]]
        if {$g eq ""} { set g "General" }
        if {[lsearch -exact $groups $g] < 0} { lappend groups $g }
    }
    return [lsort -dictionary $groups]
}

# Read-only presentation helpers; moduleSetEnabled remains the sole mutator.
proc ::GX::moduleCardsFeedbackSet {message} {
    set ::GX::ui(moduleFeedback) $message
    set page .top.nb.modules
    if {[llength [info commands winfo]] && [winfo exists $page.feedback]} {
        if {$message eq {}} {
            pack forget $page.feedback
        } else {
            pack $page.feedback -after $page.tools -fill x -padx 12 -pady {0 4}
        }
    }
}
proc ::GX::moduleCardsEnabledSnapshot {} {
    set states {}
    foreach id $::GX::moduleOrder {dict set states $id [moduleIsEnabled $id]}
    return $states
}
proc ::GX::moduleCardsRelatedChanges {id enabled} {
    set names {}
    if {$enabled} {
        foreach dependency [splitList [moduleField $id depends {}]] {
            if {![moduleIsEnabled $dependency]} {lappend names [moduleField $dependency name $dependency]}
        }
    } else {
        foreach other $::GX::moduleOrder {
            if {[moduleIsEnabled $other] && $id in [splitList [moduleField $other depends {}]]} {
                lappend names [moduleField $other name $other]
            }
        }
    }
    return $names
}
proc ::GX::moduleCardsChangeSummary {id before} {
    set changes {}
    foreach other $::GX::moduleOrder {
        if {$other eq $id || ![dict exists $before $other]} continue
        if {[dict get $before $other] != [moduleIsEnabled $other]} {
            lappend changes "[moduleField $other name $other]: [moduleOperationalState $other]"
        }
    }
    set message "[moduleField $id name $id]: [moduleOperationalState $id]."
    if {[llength $changes]} {append message " Related changes: [join $changes {; }]."}
    return $message
}
proc ::GX::moduleCardStateText {id} {
    set state [expr {[moduleRunIsSelected $id] ? {Selected for Run} : {Not selected}}]
    # Package runtime status is separate from the Session enable flag.
    set runtime [pluginRuntimeInfo $id]
    if {[dict get $runtime status] eq {Updated — restart required}} {
        append state "\nRestart required"
    }
    return $state
}

# Filtering is a read-only projection of Configuration eligibility. Do not
# retain another module/Run registry or change flags when a name is hidden.
proc ::GX::moduleCardsVisibleIds {} {
    set result {}
    set query [string tolower [string trim $::GX::moduleSearch]]
    foreach id $::GX::moduleOrder {
        if {![moduleAnalysisEligible $id] || ![moduleIsEnabled $id]} continue
        if {$query ne {} && [string first $query [string tolower [moduleField $id name $id]]]<0} continue
        lappend result $id
    }
    return $result
}

proc ::GX::refreshModuleCatalog {} {
    variable ui
    variable moduleOrder
    if {![info exists ui(moduleCards)] || ![winfo exists $ui(moduleCards)]} return
    set stateSignature [list $::GX::currentSession [moduleCardsEnabledSnapshot]]
    if {![info exists ui(moduleCardsStateSignature)] || $ui(moduleCardsStateSignature) ne $stateSignature} {
        moduleCardsFeedbackSet {}
        set ui(moduleCardsStateSignature) $stateSignature
    }
    set signature {};set groups {}
    foreach id [moduleCardsVisibleIds] {
        set group [string trim [moduleField $id group General]]
        if {$group eq {}} {set group General}
        dict lappend groups $group $id
        lappend signature [list $id $group [moduleField $id name $id] [moduleOperationalClass $id]]
    }
    if {$signature ne $ui(moduleCardsSignature)} {
        foreach child [winfo children $ui(moduleCards)] {destroy $child}
        set ui(moduleGroupCards) {};set ui(moduleCardLabels) {};set ui(moduleStateWidgets) {}
        foreach column {0 1} {
            ttk::frame $ui(moduleCards).column$column
            grid columnconfigure $ui(moduleCards).column$column 0 -weight 1
        }
        set n 0
        foreach group [lsort -dictionary [dict keys $groups]] {
            set box $ui(moduleCards).group[incr n]
            ttk::labelframe $box -text $group -padding 8
            lappend ui(moduleGroupCards) $box
            dict set ui(moduleCardLabels) $box {}
            grid columnconfigure $box 1 -weight 1
            set row 0
            foreach id [dict get $groups $group] {
                set item $box.module$row
                ttk::frame $item -padding {2 5} -style GXModuleRun.TFrame
                set runKey [moduleField $id run_key {}]
                set runVariable [expr {$runKey eq {} ? "::GX::moduleRun($id)" : "::GX::cfg($runKey)"}]
                ttk::checkbutton $item.toggle -variable $runVariable -command [list ::GX::moduleCardToggle $id] -takefocus 1 -style GXModuleRun.TCheckbutton
                ttk::label $item.name -text [moduleField $id name $id] -wraplength 230 -justify left -style GXModuleRun.TLabel
                ttk::label $item.state -width 17 -anchor w -justify left -style GXModuleRun.TLabel
                ttk::button $item.help -text Help -command [list ::GX::moduleCardHelp $id] -width 5
                grid $item.toggle -row 0 -column 0 -padx {0 5} -sticky w
                grid $item.name -row 0 -column 1 -sticky ew -padx {0 8}
                grid $item.state -row 0 -column 2 -sticky w -padx {0 5}
                grid $item.help -row 0 -column 3 -sticky e
                grid columnconfigure $item 1 -weight 1
                grid $item -row $row -column 0 -columnspan 2 -sticky ew
                bind $item.name <Button-1> [list ::GX::moduleCardSelect $id]
                bind $item.toggle <FocusIn> [list ::GX::moduleCardSelect $id]
                dict set ui(moduleStateWidgets) $id $item.state
                dict lappend ui(moduleCardLabels) $box $item.name
                incr row
            }
        }
        if {![dict size $groups]} {
            ttk::label $ui(moduleCards).empty -text {No enabled Analysis modules match. Enable modules in Configuration > Modules or clear the name filter.} -wraplength 650 -justify left
            grid $ui(moduleCards).empty -row 1 -column 0 -columnspan 2 -sticky w -padx 12 -pady 12
        }
        set ui(moduleCardsSignature) $signature
        unset -nocomplain ui(moduleCardsColumns) ui(moduleCardsWidth)
        modulesCardsLayout $ui(moduleCards) [winfo width $ui(moduleCards)]
    }
    dict for {id widget} $ui(moduleStateWidgets) {
        set selected [moduleRunIsSelected $id]
        set row [winfo parent $widget]
        foreach child [list $row $row.name $row.state] {$child state [expr {$selected?{selected}:{!selected}}]}
        set state [moduleCardStateText $id]
        $widget configure -text $state
    }
}

proc ::GX::selectedModuleFromTree {} {
    variable ui
    if {[info exists ui(moduleSelected)]} {return $ui(moduleSelected)}
    return {}
}

proc ::GX::refreshModuleDetails {} {
    variable ui
    if {![info exists ui(moduleDetails)] || ![winfo exists $ui(moduleDetails)]} return
    set id [selectedModuleFromTree]
    set w $ui(moduleDetails)
    $w configure -state normal
    $w delete 1.0 end
    if {$id eq ""} { $w insert end "Select a module." } else { $w insert end [moduleHelpText $id] }
    $w configure -state disabled
}

proc ::GX::setSelectedModuleState_v078_workspace {state} {
    set id [selectedModuleFromTree]
    if {$id eq ""} return
    if {![moduleAnalysisEligible $id]} {
        tk_messageBox -icon info -title "Analysis selection" -message "Module availability is managed in Configuration > Modules."
        return
    }
    if {![moduleIsEnabled $id]} return
    moduleSetRunSelected $id $state
    refreshModuleCatalog
    refreshAnalysisStatus
    refreshManifestPreview
}

proc ::GX::toggleSelectedModule_v078_workspace {} {
    set id [selectedModuleFromTree]
    if {$id eq ""} return
    if {![moduleAnalysisEligible $id]} return
    if {![moduleIsEnabled $id]} return
    moduleSetRunSelected $id [expr {![moduleRunIsSelected $id]}]
    refreshModuleCatalog
    refreshAnalysisStatus
    refreshManifestPreview
}

proc ::GX::moduleHelpDialog {{initial ""}} {
    variable moduleOrder
    catch {destroy .gxModuleHelp}
    toplevel .gxModuleHelp
    wm title .gxModuleHelp "Module catalog"
    wm geometry .gxModuleHelp 980x620
    grid columnconfigure .gxModuleHelp 0 -weight 1
    grid columnconfigure .gxModuleHelp 1 -weight 2
    grid rowconfigure .gxModuleHelp 0 -weight 1
    ttk::treeview .gxModuleHelp.tree -columns {kind group name ver} -show headings -selectmode browse
    foreach {c title width} {kind "Type" 120 group "Group" 220 name "Module" 280 ver "Version" 80} {
        .gxModuleHelp.tree heading $c -text $title
        .gxModuleHelp.tree column $c -width $width
    }
    text .gxModuleHelp.txt -wrap word -state disabled
    ttk::scrollbar .gxModuleHelp.sy -orient vertical -command {.gxModuleHelp.tree yview}
    ttk::scrollbar .gxModuleHelp.ty -orient vertical -command {.gxModuleHelp.txt yview}
    .gxModuleHelp.tree configure -yscrollcommand {.gxModuleHelp.sy set}
    .gxModuleHelp.txt configure -yscrollcommand {.gxModuleHelp.ty set}
    grid .gxModuleHelp.tree -row 0 -column 0 -sticky nsew -padx {8 0} -pady 8
    grid .gxModuleHelp.sy -row 0 -column 0 -sticky nse -pady 8
    grid .gxModuleHelp.txt -row 0 -column 1 -sticky nsew -padx {8 0} -pady 8
    grid .gxModuleHelp.ty -row 0 -column 2 -sticky ns -padx {0 8} -pady 8
    set found ""
    set n 0
    foreach id $moduleOrder {
        incr n; set iid "h$n"
        set ::GX::ui(moduleHelpId,$iid) $id
        .gxModuleHelp.tree insert {} end -id $iid -values [list [moduleKindLabel [moduleField $id kind]] [moduleField $id group] [moduleField $id name] [moduleField $id version]]
        if {$id eq $initial} { set found $iid }
    }
    bind .gxModuleHelp.tree <<TreeviewSelect>> {
        set __sel [.gxModuleHelp.tree selection]
        if {[llength $__sel] == 1 && [info exists ::GX::ui(moduleHelpId,[lindex $__sel 0])]} {
            set __id $::GX::ui(moduleHelpId,[lindex $__sel 0])
            .gxModuleHelp.txt configure -state normal
            .gxModuleHelp.txt delete 1.0 end
            .gxModuleHelp.txt insert end [::GX::moduleHelpText $__id]
            .gxModuleHelp.txt configure -state disabled
        }
    }
    if {$found eq "" && $n > 0} { set found h1 }
    if {$found ne ""} { .gxModuleHelp.tree selection set $found; event generate .gxModuleHelp.tree <<TreeviewSelect>> }
}

proc ::GX::showSelectedModuleHelp {} {
    set id [selectedModuleFromTree]
    if {$id ne {}} {moduleCardHelp $id}
}

proc ::GX::resourceLifecycleModuleResetSelected {} {
    set id [selectedModuleFromTree]
    if {$id eq ""} return
    set message "Reset derived runtime for module '$id' in the current Session?\n\nWILL delete: this module's disposable Session cache.\nWILL preserve: Scripts, Projects, Sessions, scientific text, Worksheet documents, Viewer scenes, Plot Dataset state and scientific analysis outputs."
    if {[tk_messageBox -type yesno -default no -icon question -title "Reset module runtime" -message $message] ne "yes"} return
    if {[catch {resourceLifecycleModuleReset $id} reason]} {
        tk_messageBox -icon error -title "Reset module runtime" -message $reason
    }
}

# Quick controls use the existing selection/lifecycle authority.
proc ::GX::moduleQuickSet {id} {
    if {![moduleAnalysisEligible $id] || ![moduleIsEnabled $id]} {error "Module '$id' is not an enabled analysis selection"}
    moduleSetRunSelected $id $::GX::ui(moduleQuick,$id)
    refreshModuleCatalog
    refreshAnalysisStatus
    refreshManifestPreview
}
proc ::GX::moduleContextMenu {x y rootX rootY} {
    set tree $::GX::ui(moduleTree)
    set row [$tree identify row $x $y]
    if {$row eq "" || ![info exists ::GX::ui(moduleId,$row)]} return
    $tree selection set $row
    $tree focus $row
    refreshModuleDetails
    ::GX::uiMenuPopup .top.nb.modules.context $rootX $rootY
}
proc ::GX::modulesFiltersFit {f width} {
    # Narrow screens retain all filters on a second row; quick controls stay
    # on the right. At normal desktop width everything uses one row.
    set narrow [expr {$width < [winfo reqwidth $f.filters]+[winfo reqwidth $f.quick]+20}]
    if {$narrow} {
        grid configure $f.filters -columnspan 2
        grid configure $f.quick -row 1
    } else {
        grid configure $f.filters -columnspan 1
        grid configure $f.quick -row 0
    }
}
