# SPDX-License-Identifier: GPL-3.0-or-later
# Unwired TASK210 development factory. MAIN owns loader/notebook/lifecycle hooks.
# Installed metadata and operational state stay with their existing public owners.
namespace eval ::GX::ConfigurationPreviewComponents {
    variable views; if {![info exists views]} {set views {}}
    variable serial; if {![info exists serial]} {set serial 0}
    variable query; variable selected; variable status
}
proc ::GX::ConfigurationPreviewComponents::_Text {value {maximum 256}} {
    regsub -all {[\x00-\x1f\x7f]} $value { } value
    return [string range $value 0 [expr {$maximum-1}]]
}
proc ::GX::ConfigurationPreviewComponents::_Default {data key fallback} {
    if {[dict exists $data $key]} {return [dict get $data $key]}
    return $fallback
}
proc ::GX::ConfigurationPreviewComponents::_Bool {value} {
    return [expr {[string is boolean -strict $value] && $value ? 1 : 0}]
}
proc ::GX::ConfigurationPreviewComponents::_List {value} {
    if {[catch {llength $value}]} {return {}}
    set result {}
    foreach item [lrange $value 0 63] {lappend result [_Text $item 128]}
    return $result
}
# Pure presentation projection. It never probes, hashes, selects, loads or admits.
proc ::GX::ConfigurationPreviewComponents::_Project {information operational} {
    if {[catch {dict size $information}]} {set information {}}
    if {[catch {dict size $operational}]} {set operational {}}
    set row [dict create component_id {} name {} installed_version {} active_version {} pending_version {} enabled 0 descriptor_valid 0 native_abi {} native_platform {} native_layout_id {} native_build_id {} dataset_contracts {} capabilities {} verified_capabilities {} gui_design_sha256 {} compatibility_status unknown load_status not_checked available 0 reason {Package admission is unavailable} admission_fingerprint {}]
    foreach key {component_id name installed_version active_version pending_version native_abi native_platform native_layout_id native_build_id gui_design_sha256 admission_fingerprint} {dict set row $key [_Text [_Default $information $key [dict get $row $key]] 256]}
    dict set row reason [_Text [_Default $information reason [dict get $row reason]] 512]
    foreach key {dataset_contracts capabilities verified_capabilities} {dict set row $key [_List [_Default $information $key {}]]}
    dict set row descriptor_valid [_Bool [_Default $information descriptor_valid 0]]
    set compatibility [_Default $information compatibility_status unknown]
    if {$compatibility ni {compatible incompatible unknown}} {set compatibility unknown}
    dict set row compatibility_status $compatibility
    set load [_Default $information load_status not_checked]
    if {$load ni {not_checked verified failed restart_required}} {set load not_checked}
    dict set row load_status $load
    set id [dict get $row component_id]
    set operationalKnown [expr {$id ne {} && [_Default $operational module_id {}] eq $id && [_Default $operational kind {}] eq {preview} && [dict exists $operational enabled] && [string is boolean -strict [dict get $operational enabled]]}]
    set enabled [expr {$operationalKnown && [_Bool [dict get $operational enabled]]}]
    dict set row enabled $enabled
    dict set row operational_known $operationalKnown
    dict set row operational_state [_Text [_Default $operational state {Unavailable}]]
    dict set row can_toggle [expr {$operationalKnown && ![_Bool [_Default $operational always_available 1]]}]
    set reportedEnabled [_Bool [_Default $information enabled 0]]
    set fingerprint [dict get $row admission_fingerprint]
    if {$fingerprint ne {} && ![regexp {^[0-9a-f]{64}$} $fingerprint]} {set fingerprint {};dict set row admission_fingerprint {}}
    set ready [expr {$operationalKnown && $enabled && $reportedEnabled && [dict get $row descriptor_valid] && $compatibility eq {compatible} && $load eq {verified} && [_Bool [_Default $information available 0]] && $fingerprint ne {} && [dict get $row pending_version] eq {}}]
    dict set row available $ready
    if {!$ready} {dict set row verified_capabilities {}}
    if {!$operationalKnown} {
        dict set row readiness {Module unavailable}
    } elseif {!$enabled} {
        dict set row readiness Inactive
    } elseif {![dict get $row descriptor_valid]} {
        dict set row readiness {Invalid descriptor}
    } elseif {$load eq {restart_required} || [dict get $row pending_version] ne {}} {
        dict set row readiness {Activation pending}
    } elseif {$compatibility eq {incompatible}} {
        dict set row readiness Incompatible
    } elseif {$ready} {
        dict set row readiness {Ready (admitted)}
    } elseif {$load eq {failed}} {
        dict set row readiness {Admission failed}
    } elseif {$load eq {verified}} {
        dict set row readiness {Admission unavailable}
    } else {dict set row readiness {Not checked}}
    if {$operationalKnown && $enabled!=$reportedEnabled} {dict set row reason {Module activation changed; current provider admission is unavailable.}}
    if {!$ready && [dict get $row reason] eq {}} {dict set row reason {Package admission is unavailable}}
    return $row
}
proc ::GX::ConfigurationPreviewComponents::_Matches {row query} {
    set query [string tolower [string trim $query]]
    if {$query eq {}} {return 1}
    return [expr {[string first $query [string tolower "[dict get $row component_id] [dict get $row name] [dict get $row capabilities] [dict get $row readiness]"]]>-1}]
}
proc ::GX::ConfigurationPreviewComponents::_Display {value {empty {Not reported}}} {if {$value eq {}} {return $empty};return $value}
proc ::GX::ConfigurationPreviewComponents::_Details {row} {
    set lines [list "[dict get $row name] ([dict get $row component_id])" "Installed: [_Display [dict get $row installed_version]]    Activation version: [_Display [dict get $row active_version]]    Pending: [_Display [dict get $row pending_version] {None reported}]" "Module state: [dict get $row operational_state]    Readiness: [dict get $row readiness]" "Declared capabilities: [_Display [join [dict get $row capabilities] {, }] {None declared}]" "Current verified capabilities: [_Display [join [dict get $row verified_capabilities] {, }] {None verified}]" "Dataset contracts: [_Display [join [dict get $row dataset_contracts] {, }] {None declared}]" "Compatibility: [dict get $row compatibility_status]    Admission: [dict get $row load_status]" "Declared native ABI: [_Display [dict get $row native_abi]]    Platform: [_Display [dict get $row native_platform]]" "Declared layout: [_Display [dict get $row native_layout_id]]    Build: [_Display [dict get $row native_build_id]]" "Declared GUI design SHA: [_Display [dict get $row gui_design_sha256]]" "Admission fingerprint: [_Display [dict get $row admission_fingerprint]]" "[dict get $row reason]"]
    return [join $lines \n]
}
proc ::GX::ConfigurationPreviewComponents::_Collect {} {
    if {![llength [info commands ::GX::datasetPreviewProviders]] || ![llength [info commands ::GX::datasetPreviewProviderInfo]]} {return [dict create rows {} status {Preview provider discovery is unavailable.}]}
    if {[catch {::GX::datasetPreviewProviders} information] || [catch {llength $information}]} {return [dict create rows {} status {Preview provider information is unavailable.}]}
    set rows {}
    foreach item [lrange $information 0 1023] {
        set operational {}
        if {![catch {dict get $item component_id} id] && $id ne {}} {catch {set operational [::GX::moduleOperationalInfo $id]}}
        lappend rows [_Project $item $operational]
    }
    set status "[llength $rows] installed Preview component(s)."
    if {[llength $information]>1024} {set status {Showing the first1024 installed Preview components.}}
    return [dict create rows $rows status $status]
}
proc ::GX::ConfigurationPreviewComponents::_Live {parent} {
    variable views
    if {![dict exists $views $parent] || ![llength [info commands winfo]]} {return 0}
    set view [dict get $views $parent];set root [dict get $view root]
    return [expr {[winfo exists $parent] && [winfo id $parent] eq [dict get $view parent_window_id] && [winfo exists $root] && [winfo id $root] eq [dict get $view root_window_id]}]
}
# Destroy callbacks can remove only their own presentation instance bookkeeping.
proc ::GX::ConfigurationPreviewComponents::_Forget {parent instance actual} {
    variable views;variable query;variable selected;variable status
    if {![dict exists $views $parent]} return
    set view [dict get $views $parent]
    if {[dict get $view instance] ne $instance || [dict get $view root] ne $actual} return
    foreach variable {query selected status} {unset -nocomplain ${variable}($instance)}
    dict unset views $parent
}
proc ::GX::ConfigurationPreviewComponents::_SetStatus {parent instance message} {
    variable views;variable status
    if {![dict exists $views $parent] || [dict get $views $parent instance] ne $instance} {return 0}
    set status($instance) [_Text $message 512]
    return 1
}
proc ::GX::ConfigurationPreviewComponents::_ApplyEnabled {id requested} {
    if {![string is boolean -strict $requested]} {error {Preview activation requires a boolean.}}
    set operational [::GX::moduleOperationalInfo $id]
    if {[dict get $operational module_id] ne $id || [dict get $operational kind] ne {preview}} {error {Select an installed Preview component.}}
    if {[dict get $operational always_available]} {error {The Module owner marks this component always available.}}
    ::GX::moduleSetEnabled $id [expr {$requested?1:0}]
    return [::GX::moduleOperationalInfo $id]
}
proc ::GX::ConfigurationPreviewComponents::_ShowDetails {parent {refreshInfo 0}} {
    variable views;variable selected
    if {![_Live $parent]} return
    set view [dict get $views $parent];set instance [dict get $view instance];set root [dict get $view root];set tree $root.list.tree
    set choice [$tree selection];set row {}
    if {[llength $choice]==1 && [dict exists $view visible [lindex $choice 0]]} {
        set row [dict get $view visible [lindex $choice 0]];set selected($instance) [dict get $row component_id]
        if {$refreshInfo} {
            if {[catch {set info [::GX::datasetPreviewProviderInfo $selected($instance)];set operational [::GX::moduleOperationalInfo $selected($instance)]}]} {
                set row {};set selected($instance) {}
            } else {set row [_Project $info $operational]}
        }
    } else {set selected($instance) {}}
    set text {No installed Preview component is selected.}
    $root.actions.toggle configure -state disabled -text {Enable / disable}
    if {$row ne {}} {
        set text [_Details $row]
        $root.actions.toggle configure -state [expr {[dict get $row can_toggle]?{normal}:{disabled}}] -text [expr {[dict get $row enabled]?{Disable}:{Enable}}]
    }
    $root.detail.text configure -state normal;$root.detail.text delete 1.0 end;$root.detail.text insert end $text;$root.detail.text configure -state disabled
}
proc ::GX::ConfigurationPreviewComponents::_Filter {parent} {
    variable views;variable query;variable selected
    if {![_Live $parent]} return
    set view [dict get $views $parent];set instance [dict get $view instance];set root [dict get $view root];set tree $root.list.tree
    $tree delete [$tree children {}]
    set visible {};set restore {};set first {};set ordinal 0
    foreach row [dict get $view rows] {
        if {![_Matches $row $query($instance)]} continue
        set iid component[incr ordinal];dict set visible $iid $row
        set activation [expr {[dict get $row operational_known]?([dict get $row enabled]?{On}:{Off}):{Unknown}}]
        $tree insert {} end -id $iid -text "[dict get $row name] ([dict get $row component_id])" -values [list $activation [_Display [dict get $row installed_version] —] [_Display [dict get $row active_version] —] [_Display [dict get $row pending_version] —] [dict get $row readiness]]
        if {$first eq {}} {set first $iid}
        if {[dict get $row component_id] eq $selected($instance)} {set restore $iid}
    }
    dict set views $parent visible $visible
    if {$restore eq {}} {set restore $first}
    if {$restore ne {}} {$tree selection set $restore;$tree see $restore}
    _ShowDetails $parent
}
proc ::GX::ConfigurationPreviewComponents::_Toggle {parent} {
    variable views;variable selected
    if {![_Live $parent]} return
    set instance [dict get $views $parent instance];set id $selected($instance)
    if {$id eq {}} return
    if {[catch {set operational [::GX::moduleOperationalInfo $id];_ApplyEnabled $id [expr {![dict get $operational enabled]}]} message]} {
        catch {::GX::configurationPreviewComponentsRefresh}
        _SetStatus $parent $instance "Activation request reported: [_Text $message]";return
    }
    ::GX::configurationPreviewComponentsRefresh
}
proc ::GX::configurationPreviewComponentsBuild {parent} {
    variable ::GX::ConfigurationPreviewComponents::views
    variable ::GX::ConfigurationPreviewComponents::serial
    variable ::GX::ConfigurationPreviewComponents::query
    variable ::GX::ConfigurationPreviewComponents::selected
    variable ::GX::ConfigurationPreviewComponents::status
    if {![llength [info commands winfo]] || ![winfo exists $parent] || [winfo class $parent] ni {Frame TFrame}} {error {Preview Configuration requires an existing Frame.}}
    if {[::GX::ConfigurationPreviewComponents::_Live $parent]} {configurationPreviewComponentsRefresh $parent;return [dict get $views $parent root]}
    if {[dict exists $views $parent]} {set old [dict get $views $parent];::GX::ConfigurationPreviewComponents::_Forget $parent [dict get $old instance] [dict get $old root]}
    set instance preview-components-[incr serial];set root $parent.preview_components$serial
    ttk::frame $root -padding 8
    dict set views $parent [dict create instance $instance root $root parent_window_id [winfo id $parent] root_window_id [winfo id $root] rows {} visible {}]
    set query($instance) {};set selected($instance) {};set status($instance) {}
    bind $root <Destroy> [list ::GX::ConfigurationPreviewComponents::_Forget $parent $instance %W]
    try {
        ttk::label $root.title -text {Installed Preview components} -font TkHeadingFont
        ttk::label $root.note -text {Declared capabilities remain unverified until current admission checks succeed. Activation follows normal Module dependency rules.} -wraplength 650
        ttk::frame $root.search
        ttk::label $root.search.label -text Filter
        ttk::entry $root.search.query -textvariable ::GX::ConfigurationPreviewComponents::query($instance)
        ttk::button $root.search.refresh -text Refresh -command [list ::GX::configurationPreviewComponentsRefresh $parent]
        pack $root.search.label -side left -padx 3;pack $root.search.refresh -side right -padx 3;pack $root.search.query -fill x -expand 1
        bind $root.search.query <KeyRelease> [list ::GX::ConfigurationPreviewComponents::_Filter $parent]
        ttk::frame $root.list
        ttk::treeview $root.list.tree -columns {enabled installed activation pending readiness} -show {tree headings} -selectmode browse -height 9
        $root.list.tree heading #0 -text {Name / ID};$root.list.tree column #0 -width 230 -minwidth 120
        foreach {column title width} {enabled Enabled 65 installed Installed 85 activation Activation 85 pending Pending 85 readiness Readiness 160} {$root.list.tree heading $column -text $title;$root.list.tree column $column -width $width -minwidth 55}
        ttk::scrollbar $root.list.y -command [list $root.list.tree yview]
        ttk::scrollbar $root.list.x -orient horizontal -command [list $root.list.tree xview]
        $root.list.tree configure -yscrollcommand [list $root.list.y set] -xscrollcommand [list $root.list.x set]
        grid $root.list.tree -row 0 -column 0 -sticky nsew;grid $root.list.y -row 0 -column 1 -sticky ns;grid $root.list.x -row 1 -column 0 -sticky ew
        grid rowconfigure $root.list 0 -weight 1;grid columnconfigure $root.list 0 -weight 1
        bind $root.list.tree <<TreeviewSelect>> [list ::GX::ConfigurationPreviewComponents::_ShowDetails $parent 1]
        ttk::frame $root.detail
        text $root.detail.text -height 7 -wrap word -state disabled -font TkDefaultFont
        ttk::scrollbar $root.detail.y -command [list $root.detail.text yview]
        $root.detail.text configure -yscrollcommand [list $root.detail.y set]
        pack $root.detail.y -side right -fill y;pack $root.detail.text -fill both -expand 1
        ttk::frame $root.actions
        ttk::button $root.actions.toggle -text {Enable / disable} -state disabled -command [list ::GX::ConfigurationPreviewComponents::_Toggle $parent]
        ttk::button $root.actions.manage -text {Install or update in Plugin Manager…} -command ::GX::pluginManagerDialog
        pack $root.actions.toggle $root.actions.manage -side left -padx 3
        ttk::label $root.status -textvariable ::GX::ConfigurationPreviewComponents::status($instance) -wraplength 650
        pack $root.title $root.note $root.search -side top -fill x -pady 3
        pack $root.status $root.actions -side bottom -fill x -pady 3
        pack $root.detail -side bottom -fill x -pady 4
        pack $root.list -fill both -expand 1 -pady 4
        pack $root -fill both -expand 1
        configurationPreviewComponentsRefresh $parent
    } on error {message options} {if {[winfo exists $root]} {destroy $root};return -options $options $message}
    return $root
}
proc ::GX::configurationPreviewComponentsRefresh {{parent {}}} {
    variable ::GX::ConfigurationPreviewComponents::views
    variable ::GX::ConfigurationPreviewComponents::status
    if {$parent eq {}} {
        set count 0
        foreach item [dict keys $views] {incr count [dict get [configurationPreviewComponentsRefresh $item] refreshed]}
        return [dict create refreshed $count]
    }
    if {![::GX::ConfigurationPreviewComponents::_Live $parent]} {return [dict create refreshed 0]}
    set instance [dict get $views $parent instance];set root [dict get $views $parent root]
    set collected [::GX::ConfigurationPreviewComponents::_Collect]
    if {![::GX::ConfigurationPreviewComponents::_Live $parent] || [dict get $views $parent instance] ne $instance} {return [dict create refreshed 0]}
    dict set views $parent rows [dict get $collected rows]
    ::GX::ConfigurationPreviewComponents::_SetStatus $parent $instance [dict get $collected status]
    $root.actions.manage configure -state [expr {[llength [info commands ::GX::pluginManagerDialog]]?{normal}:{disabled}}]
    ::GX::ConfigurationPreviewComponents::_Filter $parent
    return [dict create refreshed 1]
}
