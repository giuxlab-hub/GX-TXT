# SPDX-License-Identifier: GPL-3.0-or-later
# Configuration consumes installed descriptors; Plugin Install owns all paths
# and lifecycle actions. This browser never accepts an installation root.
namespace eval ::GX::ConfigurationModules {
    variable query ""
    variable records {}
    variable selected ""
    variable catalog {}
    variable exportQuery {}
    variable exportRecords {}
    variable exportSelected {}
    variable libraryImporterQuery {}
    variable libraryImporterRecords {}
    variable libraryImporterSelected {}
    variable visualizerQuery {}
    variable visualizerRecords {}
    variable visualizerSelected {}
    variable acquisitionQuery {}
    variable acquisitionRecords {}
    variable acquisitionSelected {}
}
proc ::GX::configurationInstalledPlugins {} {
    set result {}
    foreach type {module model instrument analysis_definition} {
        set spec [pluginTypeSpec $type]
        set base [file join $::GX::scriptDir plugins [dict get $spec dir]]
        foreach descriptor [lsort -dictionary [glob -nocomplain -types f [file join $base * [dict get $spec descriptor]]]] {
            set d [parseIni $descriptor]
            set id [descriptorValue $d meta id [file tail [file dirname $descriptor]]]
            set state Installed;set health Available
            if {$id ne [file tail [file dirname $descriptor]]} {set health {Descriptor identity mismatch}}
            if {$type eq "module" && [moduleField $id descriptor ""] ne ""} {
                set state [moduleOperationalState $id]
                set missing {}
                foreach dependency [splitList [moduleField $id depends ""]] {
                    if {[moduleField $dependency descriptor ""] eq ""} {lappend missing $dependency}
                }
                if {[llength $missing]} {set health "Missing dependency: [join $missing {, }]"}
            }
            lappend result [dict create id $id type $type name [descriptorValue $d meta name $id] version [descriptorValue $d meta version ""] state $state health $health core [descriptorValue $d meta core 0] managed [pluginRegistryIsManaged $id] descriptor $descriptor fields $d]
        }
    }
    return $result
}
proc ::GX::configurationModulesBuild {parent row} {
    ttk::notebook $parent.kinds
    ttk::frame $parent.kinds.services;ttk::frame $parent.kinds.exports;ttk::frame $parent.kinds.viewers
    $parent.kinds add $parent.kinds.services -text {Analysis & Services}
    ttk::frame $parent.kinds.library_importers
    $parent.kinds add $parent.kinds.library_importers -text {Library Importers}
    $parent.kinds add $parent.kinds.exports -text Export
    $parent.kinds add $parent.kinds.viewers -text Viewers
    ttk::frame $parent.kinds.acquisition
    ttk::frame $parent.kinds.preview
    $parent.kinds add $parent.kinds.acquisition -text Acquisition
    $parent.kinds add $parent.kinds.preview -text {Preview Components}
    ttk::frame $parent.kinds.contract_visualizers
    $parent.kinds add $parent.kinds.contract_visualizers -text {Contract Visualizers}
    grid $parent.kinds -row $row -column 0 -columnspan 4 -sticky nsew
    grid rowconfigure $parent $row -weight 1
    _uiFieldNotebookAttach $parent.kinds
    configurationModulesBrowserBuild $parent.kinds.services services
    configurationModulesBrowserBuild $parent.kinds.exports exports
    configurationModulesBrowserBuild $parent.kinds.library_importers library_importers
    configurationModulesBrowserBuild $parent.kinds.acquisition acquisition
    configurationModulesBrowserBuild $parent.kinds.contract_visualizers contract_visualizers
    configurationSubscribe ::GX::configurationEditorChanged
    configurationModulesReload
    viewerManagerBuild $parent.kinds.viewers
    configurationPreviewComponentsBuild $parent.kinds.preview
}
# Both category browsers consume the same installed registry and Configuration
# editor. Their query/selection variables are presentation drafts only.
proc ::GX::configurationModulesBrowserBuild {parent category} {
    set w $parent.browser
    ttk::frame $w
    pack $w -fill both -expand 1 -padx 8 -pady 8
    grid columnconfigure $w 0 -weight 1
    ttk::frame $w.search
    ttk::label $w.search.label -text "Installed plugins"
    set queryVariable [expr {$category eq {exports} ? {::GX::ConfigurationModules::exportQuery} : {::GX::ConfigurationModules::query}}]
    if {$category eq {library_importers}} {set queryVariable ::GX::ConfigurationModules::libraryImporterQuery}
    if {$category eq {contract_visualizers}} {set queryVariable ::GX::ConfigurationModules::visualizerQuery}
    if {$category eq {acquisition}} {set queryVariable ::GX::ConfigurationModules::acquisitionQuery}
    ttk::entry $w.search.query -textvariable $queryVariable -width 32
    ttk::button $w.search.refresh -text Refresh -command ::GX::configurationModulesReload
    pack $w.search.label $w.search.query $w.search.refresh -side left -padx 4
    pack $w.search -fill x -pady 4
    bind $w.search.query <KeyRelease> [list ::GX::configurationModulesRefresh $category]
    ttk::panedwindow $w.split -orient horizontal
    ttk::frame $w.split.list
    ttk::frame $w.split.detail
    $w.split add $w.split.list -weight 1
    $w.split add $w.split.detail -weight 2
    pack $w.split -fill both -expand 1
    ttk::treeview $w.split.list.tree -style GXInstalled.Treeview -columns {type version state} -show {tree headings} -selectmode browse -height 10
    bind $w.split.list.tree <Configure> [list ::GX::configurationModulesTableLayout $w.split.list.tree]
    $w.split.list.tree heading #0 -text "Name / ID"
    $w.split.list.tree column #0 -width 230 -minwidth 130
    foreach {key label width} {type Type 80 version Version 80 state State 90} {
        $w.split.list.tree heading $key -text $label
        set minimum [expr {max(60,[font measure TkDefaultFont $label]+24)}]
        $w.split.list.tree column $key -width [expr {max($width,$minimum)}] -minwidth $minimum
    }
    ttk::scrollbar $w.split.list.y -orient vertical -command [list $w.split.list.tree yview]
    ttk::scrollbar $w.split.list.x -orient horizontal -command [list $w.split.list.tree xview]
    $w.split.list.tree configure -yscrollcommand [list $w.split.list.y set] -xscrollcommand [list $w.split.list.x set]
    grid $w.split.list.tree -row 0 -column 0 -sticky nsew
    grid $w.split.list.y -row 0 -column 1 -sticky ns
    grid $w.split.list.x -row 1 -column 0 -sticky ew
    grid columnconfigure $w.split.list 0 -weight 1;grid rowconfigure $w.split.list 0 -weight 1
    bind $w.split.list.tree <<TreeviewSelect>> [list ::GX::configurationModulesSelect $category]
    canvas $w.split.detail.viewport -highlightthickness 0 -width 360
    ttk::scrollbar $w.split.detail.y -orient vertical -command [list $w.split.detail.viewport yview]
    $w.split.detail.viewport configure -yscrollcommand [list $w.split.detail.y set]
    ttk::frame $w.split.detail.viewport.content -padding 8
    $w.split.detail.viewport create window 0 0 -anchor nw -window $w.split.detail.viewport.content -tags content
    bind $w.split.detail.viewport <Configure> [list $w.split.detail.viewport itemconfigure content -width %w]
    bind $w.split.detail.viewport.content <Configure> [list $w.split.detail.viewport configure -scrollregion [list 0 0 %w %h]]
    pack $w.split.detail.y -side right -fill y
    pack $w.split.detail.viewport -fill both -expand 1
    ttk::frame $w.actions
    ttk::button $w.actions.manage -text "Plugin Manager…" -command ::GX::pluginManagerDialog
    ttk::button $w.actions.docs -text Documentation -command [list ::GX::configurationModulesDocumentation $category]
    pack $w.actions.manage $w.actions.docs -side left -padx 4
    # Reserve the existing actions before the expanding browser consumes the
    # remaining height, including compact windows with a larger UI font.
    pack $w.actions -side bottom -before $w.split -fill x -pady 6
}
proc ::GX::configurationModulesReload {} {
    set ::GX::ConfigurationModules::catalog {}
    configurationModulesRefresh
    configurationPreviewComponentsRefresh
}
proc ::GX::configurationModulesCategoryMatches {record category} {
    set kind {}
    if {[dict get $record type] eq {module}} {set kind [moduleField [dict get $record id] kind {}]}
    set fields [dict get $record fields]
    set libraryImporter [expr {[descriptorValue $fields library_source_connector api_version {}] eq {1}}]
    switch -- $category {
        contract_visualizers {return [expr {[dict get $record type] eq {module} && [descriptorValue $fields contract_visualizers api_version {}] eq {1}}]}
        library_importers {return $libraryImporter}
        exports {return [expr {$kind eq {export}}]}
        acquisition {return [expr {$kind eq {acquisition}}]}
        services {return [expr {!$libraryImporter && $kind ni {viewer export preview acquisition}}]}
        default {error "Unknown module configuration category '$category'"}
    }
}
proc ::GX::configurationModulesTableLayout {tree} {
    if {![winfo exists $tree]} return
    ttk::style configure GXInstalled.Treeview -rowheight [expr {[font metrics TkDefaultFont -linespace]+8}]
    set font [ttk::style lookup Treeview.Heading -font]
    if {$font eq {}} {set font TkHeadingFont}
    foreach key {type version state} {
        set minimum [expr {max(60,[font measure $font [$tree heading $key -text]]+24)}]
        if {[$tree column $key -minwidth]!=$minimum} {$tree column $key -minwidth $minimum}
        if {[$tree column $key -width]<$minimum} {$tree column $key -width $minimum}
    }
}
proc ::GX::configurationModulesRefresh {{category all}} {
    if {$category eq {all}} {
        foreach kind {services library_importers exports acquisition contract_visualizers} {configurationModulesRefresh $kind}
        return
    }
    if {$category eq {services}} {
        upvar #0 ::GX::ConfigurationModules::records records ::GX::ConfigurationModules::query query ::GX::ConfigurationModules::selected selected
    } elseif {$category eq {library_importers}} {
        upvar #0 ::GX::ConfigurationModules::libraryImporterRecords records ::GX::ConfigurationModules::libraryImporterQuery query ::GX::ConfigurationModules::libraryImporterSelected selected
    } elseif {$category eq {contract_visualizers}} {
        upvar #0 ::GX::ConfigurationModules::visualizerRecords records ::GX::ConfigurationModules::visualizerQuery query ::GX::ConfigurationModules::visualizerSelected selected
    } elseif {$category eq {acquisition}} {
        upvar #0 ::GX::ConfigurationModules::acquisitionRecords records ::GX::ConfigurationModules::acquisitionQuery query ::GX::ConfigurationModules::acquisitionSelected selected
    } else {
        upvar #0 ::GX::ConfigurationModules::exportRecords records ::GX::ConfigurationModules::exportQuery query ::GX::ConfigurationModules::exportSelected selected
    }
    variable ::GX::ConfigurationModules::catalog
    set tree .top.nb.configuration.sections.modules.kinds.$category.browser.split.list.tree
    if {![winfo exists $tree]} return
    configurationModulesTableLayout $tree
    set records [dict create]
    $tree delete [$tree children {}]
    set match [string tolower [string trim $query]]
    set ordinal 0;set restore "";set first ""
    if {$catalog eq {}} {set catalog [configurationInstalledPlugins]}
    foreach record $catalog {
        if {![configurationModulesCategoryMatches $record $category]} continue
        if {$match ne "" && [string first $match [string tolower "[dict get $record id] [dict get $record name] [dict get $record type] [dict get $record state] [dict get $record health]"]]<0} continue
        set iid plugin[incr ordinal]
        dict set records $iid $record
        $tree insert {} end -id $iid -text "[dict get $record name] ([dict get $record id])" -values [list [dict get $record type] [dict get $record version] [dict get $record state]]
        if {$first eq ""} {set first $iid}
        if {$selected eq "[dict get $record type]:[dict get $record id]"} {set restore $iid}
    }
    if {$restore eq ""} {set restore $first}
    if {$restore ne ""} {$tree selection set $restore;$tree see $restore}
    configurationModulesSelect $category
}
proc ::GX::configurationModulesSelect {{category services}} {
    if {$category eq {exports}} {
        upvar #0 ::GX::ConfigurationModules::exportRecords records ::GX::ConfigurationModules::exportSelected selected
    } elseif {$category eq {library_importers}} {
        upvar #0 ::GX::ConfigurationModules::libraryImporterRecords records ::GX::ConfigurationModules::libraryImporterSelected selected
    } elseif {$category eq {contract_visualizers}} {
        upvar #0 ::GX::ConfigurationModules::visualizerRecords records ::GX::ConfigurationModules::visualizerSelected selected
    } elseif {$category eq {acquisition}} {
        upvar #0 ::GX::ConfigurationModules::acquisitionRecords records ::GX::ConfigurationModules::acquisitionSelected selected
    } else {
        upvar #0 ::GX::ConfigurationModules::records records ::GX::ConfigurationModules::selected selected
    }
    set base .top.nb.configuration.sections.modules.kinds.$category.browser
    set tree $base.split.list.tree
    set parent $base.split.detail.viewport.content
    foreach child [winfo children $parent] {
        if {$child eq "$parent.editor"} {pack forget $child} else {destroy $child}
    }
    set choice [$tree selection]
    if {[llength $choice]!=1 || ![dict exists $records [lindex $choice 0]]} {
        ttk::label $parent.empty -text "No installed plugins match the search." -wraplength 240
        pack $parent.empty -fill x -anchor w
        bind $parent.empty <Configure> [list $parent.empty configure -wraplength %w]
        set selected ""
        return
    }
    set record [dict get $records [lindex $choice 0]]
    set id [dict get $record id];set type [dict get $record type]
    set selected "$type:$id"
    set fields [dict get $record fields]
    set text "[dict get $record name]\nID: $id\nType: $type    Version: [dict get $record version]\nState: [dict get $record state]\nHealth: [dict get $record health]\nOwnership: [expr {[dict get $record core] ? "CORE" : "Plugin"}] / [expr {[dict get $record managed] ? "managed package" : "bundled descriptor"}]\n"
    append text [descriptorValue $fields meta description ""]
    if {$category eq {library_importers}} {
        append text "\nRole: Persistent Library Source Connector\nDomains: [descriptorValue $fields library_source_connector library_types {}]\nAuthentication: [descriptorValue $fields library_source_connector authentication none]\nConnection: not probed (use the Library Browser)"
    }
    if {$category eq {contract_visualizers}} {
        foreach role [contractVisualizerProviders] {
            if {[dict get $role module_id] ne $id} continue
            if {![dict get $role valid]} {append text "\nInvalid declaration: [dict get $role reason]";continue}
            append text "\nProvider: [dict get $role token]\nContracts: [join [dict get $role contracts] {, }]\nTargets: [join [dict get $role targets] {, }]\nAvailable: [join [dict get $role available_targets] {, }]\nInheritance: [dict get $role inheritance]\nDocument kinds: [join [dict get $role document_kinds] {, }]"
        }
    }
    if {$type eq "module"} {append text "\nPublic APIs: [join [modulePublicApiIds $id] {, }]\nDependencies: [moduleField $id depends {}]"}
    if {$type eq {module} && [moduleField $id kind {}] eq {preview}} {append text "\nPreview activation is framework-wide; Save user defaults to persist it."}
    ttk::label $parent.identity -text $text -justify left -wraplength 400
    pack $parent.identity -fill x -pady 4
    bind $parent <Configure> [list ::GX::configurationModulesResize $parent %w %h]
    if {$type eq "module"} {
        if {![moduleIsAlwaysAvailable $id]} {
            set scopeCaption [expr {[moduleField $id kind {}] eq {preview} ? {Preview} : {module}}]
            ttk::button $parent.activation -text "[expr {[moduleIsEnabled $id] ? {Disable} : {Enable}}] $scopeCaption" \
                -command [list ::GX::configurationModuleProviderToggle $id]
            pack $parent.activation -anchor w -pady 4
        }
        set scope user
        if {[dict exists $::GX::ConfigurationEditor::contexts $parent.editor] && [dict get $::GX::ConfigurationEditor::contexts $parent.editor module] eq $id} {set scope [dict get $::GX::ConfigurationEditor::contexts $parent.editor scope]}
        if {![winfo exists $parent.editor]} {ttk::frame $parent.editor}
        pack $parent.editor -fill both -expand 1
        configurationModuleEditorBuild $parent.editor $id $scope
    } else {
        ttk::label $parent.none -text {This package has no Module Configuration schema.}
        pack $parent.none -fill x
    }
}
proc ::GX::configurationModulesDocumentation {{category services}} {
    if {$category eq {contract_visualizers}} {
        upvar #0 ::GX::ConfigurationModules::visualizerSelected selected
    } elseif {$category eq {library_importers}} {
        upvar #0 ::GX::ConfigurationModules::libraryImporterSelected selected
    } elseif {$category eq {acquisition}} {
        upvar #0 ::GX::ConfigurationModules::acquisitionSelected selected
    } else {
    if {$category eq {exports}} {upvar #0 ::GX::ConfigurationModules::exportSelected selected} else {upvar #0 ::GX::ConfigurationModules::selected selected}
    }
    if {[string match module:* $selected]} {documentationBrowserOpenModule [string range $selected 7 end]} else {.top.nb select .top.nb.help;documentationBrowserPopulate}
}
proc ::GX::configurationModuleProviderToggle {id} {
    if {[moduleIsAlwaysAvailable $id]} {error "Module '$id' is always available"}
    set requested [expr {![moduleIsEnabled $id]}]
    set related [moduleCardsRelatedChanges $id $requested]
    if {[llength $related]} {
        set action [expr {$requested ? {enable} : {disable}}]
        set message "[moduleField $id name $id]: $action?\n\nRelated modules may also change:\n[join $related \n]\n\nGX-TXT applies the registered dependency rules."
        if {[tk_messageBox -parent . -type okcancel -default cancel -icon question -title {Module dependencies} -message $message] ne {ok}} {return}
    }
    if {[catch {moduleSetEnabled $id $requested} reason]} {
        configurationModulesReload
        tk_messageBox -parent . -icon error -title {Module activation} -message $reason
        return
    }
    configurationModulesReload
    refreshModuleCatalog
    if {[catch {
        rebuildNativeAnalysisGui
        refreshAnalysisStatus
        refreshManifestPreview
    } reason]} {
        # Activation already succeeded; report a display failure truthfully
        # rather than implying that the canonical enablement was rolled back.
        tk_messageBox -parent . -icon error -title {Module display refresh} -message "[moduleField $id name $id]: [moduleOperationalState $id]. Display refresh failed: $reason"
    }
}

proc ::GX::configurationModulesResize {parent width {height {}}} {
    if {$height eq {}} {set height [winfo height $parent]}
    # The content Configure handler owns wrapping AND the scrolling extent.
    # Replacing the initial handler with wrapping alone disabled long editors.
    [winfo parent $parent] configure -scrollregion [list 0 0 $width $height]
    foreach child {identity defaults none} {
        if {[winfo exists $parent.$child]} {$parent.$child configure -wraplength [expr {max(160,$width-20)}]}
    }
}

source [file join [file dirname [info script]] configuration_preview_components.tcl]
source [file join [file dirname [info script]] configuration_module_editor.tcl]
