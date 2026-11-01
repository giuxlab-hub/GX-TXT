# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only semantic registry projection; preference writes use Configuration CAS.
namespace eval ::GX::ConfigurationContracts {variable selected {};variable choices;variable status {};variable rendered}
proc ::GX::configurationContractsBuild {parent} {
    ttk::label $parent.intro -text {Dataset contracts describe scientific meaning. Choose independent Open and embedded Preview presentations below.} -wraplength 620
    pack $parent.intro -fill x -padx 8 -pady 8
    ttk::panedwindow $parent.split -orient vertical
    ttk::frame $parent.split.list
    ttk::frame $parent.split.detail -padding 8
    $parent.split add $parent.split.list -weight 2
    $parent.split add $parent.split.detail -weight 1
    pack $parent.split -fill both -expand 1 -padx 8
    foreach event {<Map> <Configure> <ButtonRelease-1>} {bind $parent.split $event +[list after idle [list ::GX::configurationContractsLayout $parent]]}
    set tree $parent.split.list.tree
    ttk::style configure GXContracts.Treeview -rowheight [expr {[font metrics TkDefaultFont -linespace]+8}]
    ttk::treeview $tree -style GXContracts.Treeview -columns {state owner} -show {tree headings} -selectmode browse -height 8
    $tree heading #0 -text {Contract ID};$tree column #0 -width 240 -minwidth 140
    foreach {key title width} {state Status 120 owner {Semantic owner} 280} {$tree heading $key -text $title;$tree column $key -width $width -minwidth 90}
    ttk::scrollbar $parent.split.list.scroll -command [list $tree yview]
    ttk::scrollbar $parent.split.list.horizontal -orient horizontal -command [list $tree xview]
    $tree configure -yscrollcommand [list $parent.split.list.scroll set] -xscrollcommand [list $parent.split.list.horizontal set]
    grid $tree -row 0 -column 0 -sticky nsew
    grid $parent.split.list.scroll -row 0 -column 1 -sticky ns
    grid $parent.split.list.horizontal -row 1 -column 0 -sticky ew
    grid columnconfigure $parent.split.list 0 -weight 1
    grid rowconfigure $parent.split.list 0 -weight 1
    uiFieldScrollableCreate $parent.split.detail.viewport 480
    pack $parent.split.detail.viewport -fill both -expand 1
    bind $tree <<TreeviewSelect>> [list ::GX::configurationContractsSelect $parent]
    ttk::button $parent.refresh -text {Refresh contracts} -command [list ::GX::configurationContractsRefresh $parent]
    pack $parent.refresh -side bottom -before $parent.split -anchor w -padx 8 -pady 6
    bind $parent <Visibility> +[list ::GX::configurationContractsVisible $parent]
    bind $parent <Configure> +[list ::GX::configurationContractsResize $parent %w]
    configurationContractsRefresh $parent
}
proc ::GX::configurationContractsIds {} {
    set ids [contractRegistryIds]
    if {$::GX::currentSession ne {}} {
        foreach dataset [datasetRegistryIds] {
            set contract [datasetField $dataset contract [datasetField $dataset kind {}]]
            if {[_contractVisualizerContractIdentifier $contract]} {lappend ids $contract}
        }
    }
    foreach target {open preview} {
        foreach contract [dict keys [configurationGet contracts.${target}_visualizers]] {lappend ids $contract}
    }
    # Referenced missing contracts are UI rows, never new schema registrations.
    return [lsort -dictionary -unique $ids]
}
proc ::GX::configurationContractsViewIdentity {} {
    set registry {}
    foreach key [lsort [array names ::GX::contractRegistry]] {lappend registry $key $::GX::contractRegistry($key)}
    set modules {}
    foreach module $::GX::moduleOrder {
        set enabled unknown;catch {set enabled [moduleIsEnabled $module]}
        set viewers {}
        if {![catch {viewerProviderIds $module} ids]} {foreach id $ids {set active unknown;catch {set active [viewerProviderEnabled $module $id]};lappend viewers $id $active}}
        lappend modules $module [moduleField $module dict {}] $enabled $viewers
    }
    return [list $registry $modules $::GX::currentSession [configurationContractsIds] [configurationGet contracts.open_visualizers] [configurationGet contracts.preview_visualizers]]
}
proc ::GX::configurationContractsVisible {parent} {
    variable ::GX::ConfigurationContracts::rendered
    if {![winfo exists $parent.split.list.tree]} return
    # A native combobox popdown obscures this page. Rebuilding identical data
    # here destroys the posted control and discards its uncommitted selection.
    # Real catalog/activation/Session/preference changes still refresh normally.
    set identity [configurationContractsViewIdentity]
    if {![info exists rendered($parent)] || $rendered($parent) ne $identity} {configurationContractsRefresh $parent}
}
proc ::GX::configurationContractsRefresh {parent} {
    set tree $parent.split.list.tree
    if {![winfo exists $tree]} return
    set selected [$tree selection]
    ttk::style configure GXContracts.Treeview -rowheight [expr {[font metrics TkDefaultFont -linespace]+8}]
    $tree delete [$tree children {}]
    foreach contract [configurationContractsIds] {
        set row [contractRegistryDescribe $contract]
        set owners [join [dict get $row owners] {, }]
        if {$owners eq {} && [dict get $row status] eq {missing_provider}} {set owners {Not installed}}
        $tree insert {} end -id $contract -text $contract -values [list [dict get $row status] $owners]
    }
    if {[llength $selected] && [$tree exists [lindex $selected 0]]} {$tree selection set $selected
    } elseif {[llength [$tree children {}]]} {$tree selection set [lindex [$tree children {}] 0]}
    configurationContractsSelect $parent
    after idle [list ::GX::configurationContractsLayout $parent]
}
proc ::GX::configurationContractsSelect {parent} {
    variable ::GX::ConfigurationContracts::selected
    variable ::GX::ConfigurationContracts::choices
    variable ::GX::ConfigurationContracts::rendered
    set selection [$parent.split.list.tree selection]
    if {[llength $selection]!=1} return
    set selected [lindex $selection 0]
    set detail $parent.split.detail.viewport.scroll.content
    foreach child [winfo children $detail] {destroy $child}
    set info [contractRegistryDescribe $selected]
    set description "$selected — [dict get $info status]\n[dict get $info description]\nParents: [join [dict get $info parents] {, }]"
    if {[dict get $info status] eq {missing_provider}} {append description "\nNo Contract provider is installed. Existing data and saved choices are preserved. Reinstall the provider to restore semantic resolution."}
    foreach declaration [dict get $info declarations] {append description "\nSemantic owner: [dict get $declaration owner] · Module version: [dict get $declaration module_version] · Contract version: [dict get $declaration version]"}
    foreach target {open preview} {append description "\nRecommended $target: [expr {[llength [dict get $info recommendations $target]] ? [join [dict get $info recommendations $target] {, }] : {None declared}}]"}
    ttk::label $detail.identity -text $description -wraplength 620 -justify left
    grid $detail.identity -row 0 -column 0 -columnspan 4 -sticky ew -pady 4
    set row 1
    foreach {target title} {open Open preview {Embedded Preview}} {
        set choices($target) [contractVisualizerPreferenceGet $selected $target]
        set values {auto}
        foreach provider [contractVisualizerCandidates $selected $target] {if {$target in [dict get $provider available_targets]} {lappend values [dict get $provider token]}}
        ttk::label $detail.${target}Label -text $title
        ttk::combobox $detail.$target -state readonly -values $values -textvariable ::GX::ConfigurationContracts::choices($target) -width 16
        ttk::button $detail.${target}Apply -text Apply -command [list ::GX::configurationContractsApply $parent $selected $target]
        ttk::button $detail.${target}Auto -text {Restore Auto} -command [list ::GX::configurationContractsApply $parent $selected $target auto]
        grid $detail.${target}Label -row $row -column 0 -sticky w -padx 3
        grid $detail.$target -row $row -column 1 -sticky ew -padx 3
        grid $detail.${target}Apply -row $row -column 2 -padx 3
        grid $detail.${target}Auto -row $row -column 3 -padx 3
        incr row
        set resolution [contractVisualizerResolve $selected $target]
        set summary "[dict get $resolution status]: [dict get $resolution selected_token] ([dict get $resolution selection_source])"
        if {[dict exists $resolution version]} {append summary " · Module version [dict get $resolution version]"}
        foreach message [dict get $resolution diagnostics] {append summary "\n$message"}
        ttk::label $detail.${target}Reason -text $summary -wraplength 620 -justify left
        grid $detail.${target}Reason -row $row -column 0 -columnspan 4 -sticky ew -pady {2 8}
        incr row
    }
    grid columnconfigure $detail 1 -weight 1
    configurationContractsResize $parent [winfo width $parent]
    set rendered($parent) [configurationContractsViewIdentity]
}
proc ::GX::configurationContractsResize {parent width} {
    if {![winfo exists $parent.intro]} return
    set wrap [expr {max(180,$width-40)}]
    $parent.intro configure -wraplength $wrap
    set detail $parent.split.detail.viewport.scroll.content
    foreach name {identity openReason previewReason} {if {[winfo exists $detail.$name]} {$detail.$name configure -wraplength $wrap}}
    after idle [list ::GX::configurationContractsLayout $parent]
}
proc ::GX::configurationContractsLayout {parent} {
    set split $parent.split
    set tree $split.list.tree
    if {![winfo exists $tree] || ![winfo ismapped $split] || [winfo height $split]<2} return
    set line [font metrics TkDefaultFont -linespace]
    set row [expr {$line+8}]
    ttk::style configure GXContracts.Treeview -rowheight $row
    # Use the theme's actual requested heading/border and horizontal scrollbar,
    # not a fixed pixel row or the detail canvas's larger initial request. The
    # list must retain complete selectable rows when the split is compressed.
    set heading [expr {max([font metrics TkHeadingFont -linespace]+4,[winfo reqheight $tree]-[$tree cget -height]*$row)}]
    set chrome [expr {$heading+[winfo reqheight $split.list.horizontal]+4}]
    set height [winfo height $split]
    set detail [expr {min($line*3+20,max(1,$height-$chrome-$row-8))}]
    set rows [expr {max(1,min(3,int(($height-$detail-$chrome-8)/$row)))}]
    set minimum [expr {$chrome+$rows*$row}]
    set maximum [expr {max($minimum,$height-$detail-8)}]
    set current [$split sashpos 0]
    set desired [expr {max($minimum,min($current,$maximum))}]
    if {$current!=$desired} {$split sashpos 0 $desired}
}
proc ::GX::configurationContractsApply {parent contract target {value {}}} {
    variable ::GX::ConfigurationContracts::choices
    if {$value eq {}} {set value $choices($target)}
    if {[catch {contractVisualizerPreferenceSet $contract $target $value} reason]} {tk_messageBox -parent [winfo toplevel $parent] -icon warning -type ok -message $reason;return}
    configurationContractsSelect $parent
}
