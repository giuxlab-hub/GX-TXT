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

proc ::GX::refreshModuleCatalog {} {
    variable ui
    variable moduleOrder
    variable moduleSearch
    variable moduleKindFilter
    variable moduleGroupFilter
    variable moduleCoreFilter
    if {![info exists ui(moduleTree)] || ![winfo exists $ui(moduleTree)]} return
    set t $ui(moduleTree)
    foreach item [$t children {}] { $t delete $item }
    foreach k [array names ui "moduleId,*"] { unset ui($k) }
    set q [string tolower [string trim $moduleSearch]]
    array set groupIid {}
    set ng 0; set nm 0; set firstLeaf ""
    foreach id $moduleOrder {
        if {![moduleAnalysisEligible $id] || $id in {plot.dataset analysis.octave_script analysis.python_script}} continue
        if {$moduleCoreFilter eq "CORE" && ![moduleIsCore $id]} continue
        if {$moduleCoreFilter eq "Non-CORE" && [moduleIsCore $id]} continue
        set kind [moduleKindLabel [moduleField $id kind]]
        set group [moduleField $id group "General"]
        set name [moduleField $id name $id]
        set ver [moduleField $id version ""]
        if {$moduleKindFilter ne "All" && $kind ne $moduleKindFilter} continue
        if {$moduleGroupFilter ne "All" && $group ne $moduleGroupFilter} continue
        if {$q ne ""} {
            set hay [string tolower "$id $name $group $kind [moduleField $id description]"]
            if {[string first $q $hay] < 0} continue
        }
        if {![info exists groupIid($group)]} {
            incr ng; set gi "grp$ng"; set groupIid($group) $gi
            $t insert {} end -id $gi -text $group -open 1 -values [list "" "" "" ""]
        }
        incr nm; set iid "mod$nm"
        set ui(moduleId,$iid) $id
        set state [moduleOperationalState $id]
        $t insert $groupIid($group) end -id $iid -text $name -values [list $state $kind $ver $id]
        if {$firstLeaf eq ""} { set firstLeaf $iid }
    }
    if {$firstLeaf ne ""} { $t selection set $firstLeaf; $t see $firstLeaf }
    refreshModuleDetails
    foreach id {plot.dataset analysis.octave_script analysis.python_script} {set ui(moduleQuick,$id) [moduleIsEnabled $id]}
}

proc ::GX::selectedModuleFromTree {} {
    variable ui
    if {![info exists ui(moduleTree)] || ![winfo exists $ui(moduleTree)]} { return "" }
    set sel [$ui(moduleTree) selection]
    if {[llength $sel] != 1} { return "" }
    set iid [lindex $sel 0]
    if {[info exists ui(moduleId,$iid)]} { return $ui(moduleId,$iid) }
    return ""
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
        tk_messageBox -icon info -title "Module activation" -message "Provider availability is managed in Configuration → Modules. Import prerequisites are checked when invoked."
        return
    }
    moduleSetEnabled $id $state
    refreshModuleCatalog
    refreshAnalysisStatus
    refreshManifestPreview
}

proc ::GX::toggleSelectedModule_v078_workspace {} {
    set id [selectedModuleFromTree]
    if {$id eq ""} return
    if {![moduleAnalysisEligible $id]} return
    moduleSetEnabled $id [expr {![moduleIsEnabled $id]}]
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
    moduleHelpDialog $id
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
    if {![moduleAnalysisEligible $id]} {error "Module '$id' is not an analysis selection"}
    moduleSetEnabled $id $::GX::ui(moduleQuick,$id)
    rebuildNativeAnalysisGui
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
