# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative catalog presentation; the existing Library Manager owns registry,
# integrity, providers and administration. No library data is persisted here.
proc ::GX::_viewerGuiLibraryUnicodeLength {value} {
    # Tcl8.6 counts UTF-16 surrogate units; the JSON/Manager contract counts
    # Unicode scalar characters. Collapse valid pairs and refuse unpaired units.
    set scalars [regsub -all {[\uD800-\uDBFF][\uDC00-\uDFFF]} $value x]
    if {[regexp {[\uD800-\uDFFF]} $scalars]} {error {Library scope requires valid Unicode characters}}
    return [string length $scalars]
}
proc ::GX::_viewerGuiLibraryScopeNormalize {scope} {
    if {[catch {dict size $scope}] || [dict size $scope]>5} {error {Library scope must be a dictionary of the five supported ID-list dimensions}}
    set normalized {};set encoded {};set canonicalSavings 0
    foreach key [lsort [dict keys $scope]] {
        if {$key ni {library_types record_types library_ids provider_ids source_ids}} {error "Unsupported Library scope dimension '$key'"}
        set values [dict get $scope $key]
        if {[catch {llength $values}] || [llength $values]>64} {error {Each Library scope dimension requires at most64 stable IDs}}
        if {[llength [lsort -unique $values]]!=[llength $values]} {error {Duplicate Library scope IDs are not allowed}}
        set strings {}
        foreach value [lsort $values] {
            if {$value eq {} || [regexp {[\x00\r\n]} $value]} {error {Library scope IDs must be nonempty and contain no control separators}}
            if {$key eq {source_ids}} {
                if {[_viewerGuiLibraryUnicodeLength $value]>512} {error {A source identity exceeds512 characters}}
            } elseif {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $value]} {error {Library scope requires stable public Manager/schema IDs}}
            lappend strings [viewerDevelopmentJsonString $value]
            # The existing encoder uses six-byte escapes for these actual
            # controls; canonical JSON uses two. Count original characters,
            # never replace escape-looking literal identity text.
            incr canonicalSavings [expr {4*[regexp -all {[\x08\t\f]} $value]}]
        }
        if {![llength $strings]} continue
        dict set normalized $key [lsort $values]
        lappend encoded "[viewerDevelopmentJsonString $key]:\[[join $strings ,]\]"
    }
    if {[string length [encoding convertto utf-8 "\{[join $encoded ,]\}"]]-$canonicalSavings>32768} {error {Library scope exceeds32 KiB}}
    return $normalized
}
proc ::GX::_viewerGuiLibraryScope {design group} {
    foreach component [dict get $design components] {
        if {[dict get $component type] eq {library_browser} && [dict get $component properties group] eq $group} {
            return [_viewerGuiLibraryScopeNormalize [datasetPublicationV2DictDefault [dict get $component properties] scope {}]]
        }
    }
    return {}
}
proc ::GX::viewerGuiComponentInitialProperties {type {design {}}} {
    set capabilities [viewerGuiComponentCapabilities]
    if {![dict exists $capabilities $type]} {error {Unknown public Viewer component}}
    set properties [datasetPublicationV2DictDefault [dict get $capabilities $type] default_properties {}]
    if {$type eq {document} && [datasetPublicationV2DictDefault $design target viewer] eq {preview} && [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $design preview {}] runtime {}] eq {managed_cpp}} {
        set kind markdown
        if {[datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $design contract_visualizer {}] document_kinds {}] eq {uml}} {set kind uml}
        foreach item [dict get $design components] {if {[dict get $item type] eq {document}} {set kind [dict get $item properties kind];break}}
        set used {}
        foreach component [dict get $design components] {if {[dict get $component type] eq {document}} {lappend used [datasetPublicationV2DictDefault [dict get $component properties] pane rendered]}}
        foreach pane [expr {$kind eq {uml}?{diagram source metadata}:{rendered source metadata associated_source}}] {if {$pane ni $used} {return [dict create kind $kind mode read_only pane $pane title [string totitle [string map {_ { }} $pane]]]}}
        error {All managed document panes are already declared}
    }
    if {$type ne {library_browser} || $design eq {}} {return $properties}
    set groups [_viewerGuiLibraryDefinitions $design]
    dict for {group pages} $groups {
        foreach page {records sources manual} {
            if {[dict exists $pages $page]} continue
            set result [dict create group $group page $page]
            set scope [_viewerGuiLibraryScope $design $group]
            if {$scope ne {}} {dict set result scope $scope}
            return $result
        }
    }
    set group libraries;set serial 1
    while {[dict exists $groups $group]} {set group libraries_[incr serial]}
    return [dict create group $group page records]
}
proc ::GX::_viewerGuiLibraryDefinitions {design {requireComplete 0}} {
    set groups {};set scopes {}
    foreach component [dict get $design components] {
        if {[dict get $component type] ne {library_browser}} continue
        if {[datasetPublicationV2DictDefault $design target viewer] ne {viewer}} {error {Library Browser pages require the existing Viewer target}}
        set properties [dict get $component properties]
        foreach key {page group} {if {![dict exists $properties $key]} {error "Library Browser component requires '$key'"}}
        set page [dict get $properties page];set group [dict get $properties group]
        if {$page ni {records sources manual} || ![regexp {^[a-z][a-z0-9_]{0,63}$} $group]} {error {Library Browser requires a finite page and a stable group identifier}}
        if {[dict exists $groups $group $page]} {error {Only one declared Library Browser component may own a group/page}}
        set scope [_viewerGuiLibraryScopeNormalize [datasetPublicationV2DictDefault $properties scope {}]]
        if {[dict exists $scopes $group] && [dict get $scopes $group] ne $scope} {error {All Library Browser pages in a group require the same declarative scope}}
        dict set scopes $group $scope
        dict set groups $group $page [dict get $component id]
    }
    if {[dict size $groups]>4} {error {A Viewer supports at most four declared Library Browser groups}}
    dict for {group pages} $groups {
        if {$requireComplete && [lsort [dict keys $pages]] ne {manual records sources}} {error {Declare all three Library Browser pages in the same group}}
    }
    return $groups
}
proc ::GX::_viewerGuiLibraryMount {window} {
    set instance [dict get $::GX::ViewerGui::instances $window]
    set runtime [expr {[dict get $instance mode] eq {runtime}}]
    dict for {group components} [_viewerGuiLibraryDefinitions [dict get $instance design] $runtime] {
        set pages {}
        dict for {page component} $components {dict set pages $page [dict get $instance widgets $component]}
        if {!$runtime} {
            dict for {page widget} $pages {
                ttk::label $widget.empty -text "Scientific Library $page page — layout preview. Open the Viewer to use the existing Library services." -wraplength 420
                pack $widget.empty -fill both -expand 1 -padx 8 -pady 8
            }
            continue
        }
        if {![llength [info commands ::GX::LibraryBrowser::mountPages]]} {error {This framework requires the compatible embedded Scientific Library Browser implementation}}
        set status [list [dict get $instance slots status] configure -text]
        set statusWidget [dict get $instance slots status]
        foreach definition [dict get $instance design components] {
            set properties [dict get $definition properties]
            if {[dict get $definition type] eq {section} && [datasetPublicationV2DictDefault $properties catalog_browser_group {}] eq $group} {
                set status [list ::GX::viewerGuiDesignTextSet $window [dict get $properties catalog_status]]
                set statusWidget [dict get $instance widgets [dict get $properties catalog_status]]
                break
            }
        }
        # Both authored catalog and fallback routes carry service diagnostics.
        # Use their actual allocated width rather than a narrow static label
        # request that would consume the Viewer height at larger fonts.
        ::GX::LibraryBrowser::wrapLabel $statusWidget
        set scope [_viewerGuiLibraryScope [dict get $instance design] $group]
        if {$scope eq {}} {set controller [::GX::LibraryBrowser::mountPages $window $group $pages $status]
        } else {set controller [::GX::LibraryBrowser::mountPages $window $group $pages $status $scope]}
        dict set ::GX::ViewerGui::instances $window library_browsers $group [dict create controller $controller components $components]
    }
}
proc ::GX::viewerGuiDesignLibraryPage {window group page} {
    if {![viewerGuiDesignGuard $window]} {error {Library Viewer belongs to a previous Session; reopen it}}
    if {$page ni {records sources manual}} {error {Select a declared records, sources or manual Library page}}
    if {![dict exists $::GX::ViewerGui::instances $window library_browsers $group]} {error {This Viewer has no embedded Library Browser group; update its compatible Scientific Libraries module}}
    set browser [dict get $::GX::ViewerGui::instances $window library_browsers $group]
    set component [dict get $browser components $page]
    set widget [dict get $::GX::ViewerGui::instances $window widgets $component]
    # Reveal each declarative ancestor tab without changing another window.
    set child $widget
    while {$child ne $window && [winfo exists $child]} {
        set parent [winfo parent $child]
        if {[winfo class $parent] eq {TNotebook}} {$parent select $child}
        set child $parent
    }
    ::GX::LibraryBrowser::focusPage [dict get $browser controller] $page
    viewerGuiTraceEmit $window $component view_changed [dict create status focused page $page]
    return [dict create status focused group $group page $page component $component]
}
proc ::GX::_viewerGuiLibraryReference {window group library entry} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window library_browsers $group]} {error {The declared Library Browser is unavailable or stale}}
    set controller [dict get $::GX::ViewerGui::instances $window library_browsers $group controller]
    ::GX::LibraryBrowser::guard $controller
    set reference [dict create kind library_entry library_id $library entry_id $entry]
    set current [::GX::LibraryBrowser::domain $controller detail [format {{"reference":%s}} [::GX::LibraryBrowser::object $reference]]]
    set info [::GX::ScientificLibraryManagerAPIv1::getLibraryInfo $library]
    return [dict create library_id $library entry_id $entry revision [dict get $current revision] content_sha256 [dict get $current content_sha256] provider_id [dict get $info provider_id] source_id [datasetPublicationV2DictDefault [dict get $current provenance] source_id {}]]
}
proc ::GX::viewerGuiDesignLibrarySelection {window group} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window library_browsers $group]} {error {The declared Library Browser is unavailable or stale}}
    set controller [dict get $::GX::ViewerGui::instances $window library_browsers $group controller]
    ::GX::LibraryBrowser::guard $controller
    set reference [::GX::LibraryBrowser::reference $controller]
    if {![dict exists $::GX::LibraryBrowser::states $controller selected_reference] ||
        $reference ne [dict get $::GX::LibraryBrowser::states $controller selected_reference]} {error {Inspect the selected Library entry before using it}}
    set inspected [dict get $::GX::LibraryBrowser::states $controller selected_entry]
    set current [::GX::LibraryBrowser::domain $controller detail [format {{"reference":%s}} [::GX::LibraryBrowser::object $reference]]]
    foreach key {revision content_sha256} {
        if {![dict exists $inspected $key] || ![dict exists $current $key] || [dict get $inspected $key] ne [dict get $current $key]} {error {Library entry changed after inspection; inspect its current revision explicitly}}
    }
    set library [::GX::ScientificLibraryManagerAPIv1::getLibraryInfo [dict get $reference library_id]]
    set source [datasetPublicationV2DictDefault [dict get $current provenance] source_id {}]
    return [dict create library_id [dict get $reference library_id] entry_id [dict get $reference entry_id] revision [dict get $current revision] content_sha256 [dict get $current content_sha256] provider_id [dict get $library provider_id] source_id $source]
}
proc ::GX::_viewerGuiLibraryCanClose {window} {
    if {![_viewerGuiScriptLibraryCanClose $window]} {return 0}
    if {![dict exists $::GX::ViewerGui::instances $window library_browsers]} {return 1}
    dict for {group browser} [dict get $::GX::ViewerGui::instances $window library_browsers] {
        set allowed [::GX::LibraryBrowser::canClose [dict get $browser controller]]
        if {![string is boolean -strict $allowed]} {error {Library close review must return a boolean}}
        if {!$allowed} {return 0}
    }
    return 1
}
proc ::GX::viewerGuiDesignClose {window} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} return
    if {[dict exists $::GX::ViewerGui::instances $window project_draft]} {return [_viewerDevelopmentProjectDraftClose $window]}
    if {[dict exists $::GX::ViewerGui::instances $window workspace_provider]} {return [viewerGuiDesignWorkspaceClose $window]}
    if {[_viewerGuiLibraryCanClose $window]} {destroy $window}
}
proc ::GX::_viewerGuiCatalogDesignValidate {design} {
    set browserGroups [_viewerGuiLibraryDefinitions $design]
    set definitions {};foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {[dict get $c type] eq {section} && [dict exists $p catalog_browser_group] && [datasetPublicationV2DictDefault $p catalog_owner {}] ne {scientific_libraries}} {error {catalog_browser_group requires the existing Scientific Libraries catalog owner}}
        if {[dict get $c type] ne {section} || ![dict exists $p catalog_owner]} continue
        if {[dict get $p catalog_owner] ne {scientific_libraries} || [datasetPublicationV2DictDefault [dict get $design requirements] SCIENTIFIC_LIBRARY_MANAGER_API_v1 0]!=1} {error {Catalog section requires Scientific Library Manager v1}}
        foreach {key types} {catalog_records list catalog_mode {choice combobox} catalog_filter {entry field} catalog_info table catalog_capabilities table catalog_log log catalog_status {label status} catalog_count {label status}} {
            if {![dict exists $p $key] || ![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types} {error "Invalid declared catalog control $key"}
        }
        foreach {key types} {catalog_entries list catalog_extra_action {choice combobox} catalog_page {entry field} catalog_type {choice combobox} catalog_providers table catalog_entry_filter {entry field} catalog_entry_info table catalog_entry_count {label status}} {
            if {[dict exists $p $key] && (![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types)} {error "Invalid optional catalog control $key"}
        }
        foreach {key columns} {catalog_info 2 catalog_capabilities 4} {
            if {[llength [dict get $definitions [dict get $p $key] properties columns]]!=$columns} {error "Catalog $key requires $columns columns"}
        }
        dict for {action command} [dict get $p catalog_actions] {
            if {$action ni {refresh open entry_open entry_search entry_next entry_previous entry_info verify install update remove register_external register_remote unregister extra_action browse_records browse_sources browse_manual} || ![dict exists $design handlers $command]} {error {Catalog actions require finite manager actions and declared command handlers}}
            if {[string match browse_* $action] && ![dict exists $p catalog_browser_group]} {error {Library page actions require a declared catalog_browser_group}}
        }
        if {[dict exists $p catalog_browser_group] && ![dict exists $browserGroups [dict get $p catalog_browser_group]]} {error {Catalog Browser group must name the complete declared embedded pages}}
    }
}
proc ::GX::_viewerGuiCatalogForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Catalog window belongs to a previous Session; reopen it}}
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || [datasetPublicationV2DictDefault [dict get $c properties] catalog_owner {}] ne {scientific_libraries}} {error {Select a declared Scientific Libraries catalog section}}
    return [dict get $c properties]
}
proc ::GX::_viewerGuiCatalogState {window form} {
    if {![dict exists $::GX::ViewerGui::instances $window catalogs $form]} {
        # Paths and request generations can repeat after close/reopen. This
        # process-local identity belongs to this presentation lifetime only.
        variable ::GX::ViewerGui::catalogLifetime
        if {![info exists catalogLifetime]} {set catalogLifetime 0}
        set state [dict create lifetime [incr catalogLifetime] generation 0 active_generation 0 request {} pending {} rows {} selected {} capabilities {} entries {} entry_query {} entry_token {} entry_history {} entry_next {} page {} activity {} last_action {}]
        dict set ::GX::ViewerGui::instances $window catalogs $form $state
    }
    return [dict get $::GX::ViewerGui::instances $window catalogs $form]
}
proc ::GX::_viewerGuiCatalogWidget {window properties key} {return [dict get $::GX::ViewerGui::instances $window widgets [dict get $properties $key]]}
proc ::GX::_viewerGuiCatalogMessage {window form message {detail {}}} {
    set p [_viewerGuiCatalogForm $window $form]
    viewerGuiDesignTextSet $window [dict get $p catalog_status] $message
    if {$detail ne {}} {
        set state [_viewerGuiCatalogState $window $form]
        set activity [dict get $state activity]
        append activity "\n[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $message\n$detail\n"
        if {[string length $activity]>65536} {set activity "Earlier activity omitted by the presentation bound.\n[string range $activity end-65000 end]"}
        dict set ::GX::ViewerGui::instances $window catalogs $form activity $activity
        viewerGuiDesignTextSet $window [dict get $p catalog_log] $activity
    }
    viewerGuiTraceEmit $window $form catalog_state [dict create status $message]
    viewerGuiActionsRefresh $window
}
proc ::GX::_viewerGuiCatalogRequest {window form operation arguments stage} {
    _viewerGuiCatalogForm $window $form
    set state [_viewerGuiCatalogState $window $form]
    if {[dict get $state request] ne {} && [datasetPublicationV2DictDefault $state active_stage {}] eq {action}} {error {A library operation is in progress; wait for its actual result}}
    dict incr state generation
    set pending [dict create operation $operation arguments $arguments stage $stage generation [dict get $state generation]]
    if {[dict get $state request] ne {}} {
        dict set state pending $pending
        dict set ::GX::ViewerGui::instances $window catalogs $form $state
        scriptJobRequestCancel [dict get $state request]
    } else {
        dict set state pending {}
        dict set state active_stage $stage
        dict set state active_operation $operation
        dict set state active_library [dict get $state selected]
        dict set state active_generation [dict get $pending generation]
        dict set state request [::GX::ScientificLibraryManagerAPIv1::libraryRequest $operation $arguments [list ::GX::_viewerGuiCatalogReply $window $form [dict get $state lifetime] [dict get $pending generation] $stage]]
        dict set ::GX::ViewerGui::instances $window catalogs $form $state
    }
    _viewerGuiCatalogMessage $window $form {Loading library information…}
}
proc ::GX::_viewerGuiCatalogReply {window form lifetime generation stage response} {
    if {![dict exists $::GX::ViewerGui::instances $window catalogs $form]} return
    if {[catch {viewerGuiDesignGuard $window} live] || !$live} return
    set state [_viewerGuiCatalogState $window $form]
    # A canceled active read still owns the handoff to the newest pending
    # read. A duplicate, previous Session or recycled-path response owns none
    # of this state, including the successor request and pending handoff.
    if {$lifetime ne [dict get $state lifetime] || $generation!=[dict get $state active_generation] || $stage ne [dict get $state active_stage] || [dict get $state request] eq {}} return
    dict set state request {}
    dict set ::GX::ViewerGui::instances $window catalogs $form $state
    if {[dict get $state pending] ne {}} {
        set next [dict get $state pending];dict set ::GX::ViewerGui::instances $window catalogs $form pending {}
        _viewerGuiCatalogRequest $window $form [dict get $next operation] [dict get $next arguments] [dict get $next stage];return
    }
    if {$generation!=[dict get $state generation]} return
    if {$stage eq {action}} {
        # Preserve the actual correlated manager response independently of the
        # automatic page/capability refresh. This is window RAM, not a registry.
        set receipt [dict create schema gxtxt.library_catalog_action.v1 operation [dict get $state active_operation] requested_library_id [dict get $state active_library] library_id [dict get $state active_library] generation $generation ok [dict get $response ok]]
        if {[dict get $response ok]} {
            set actualResult [dict get $response result]
            dict set receipt result $actualResult
            if {[dict exists $actualResult library_id]} {dict set receipt library_id [dict get $actualResult library_id]}
        } else {dict set receipt error [dict get $response error]}
        dict set state last_action $receipt
        dict set ::GX::ViewerGui::instances $window catalogs $form $state
    }
    if {[catch {
        if {![dict get $response ok]} {error [dict get $response error]}
        set result [dict get $response result];set p [_viewerGuiCatalogForm $window $form]
        switch $stage {
            page {
                set old [dict get $state selected];set selected -1;set labels {};set index 0
                foreach row [dict get $result records] {
                    lappend labels "[dict get $row display_name] · [dict get $row mode] · [dict get $row library_id]"
                    if {[dict get $row library_id] eq $old} {set selected $index};incr index
                }
                uiFieldComponentItemsSet [_viewerGuiCatalogWidget $window $p catalog_records] list $labels
                dict set state rows [dict get $result records];dict set state page $result;dict set state selected {};dict set state capabilities {};dict set state entries {}
                foreach key {entry_query entry_token entry_history entry_next} {dict set state $key {}}
                dict set ::GX::ViewerGui::instances $window catalogs $form $state
                viewerGuiDesignValueSet $window [dict get $p catalog_records] [expr {$selected<0?{}:[list $selected]}]
                viewerGuiDesignTableSet $window [dict get $p catalog_info] {}
                viewerGuiDesignTableSet $window [dict get $p catalog_capabilities] {}
                if {[dict exists $p catalog_entries]} {uiFieldComponentItemsSet [_viewerGuiCatalogWidget $window $p catalog_entries] list {}}
                if {[dict exists $p catalog_entry_info]} {viewerGuiDesignTableSet $window [dict get $p catalog_entry_info] {}}
                viewerGuiDesignTextSet $window [dict get $p catalog_count] "[dict get $result count] shown / [dict get $result total] registered matches · offset [dict get $result offset]"
                _viewerGuiCatalogMessage $window $form {Select a registered library to inspect its capabilities.}
                if {$selected>=0} {viewerGuiDesignCatalogInspect $window $form}
            }
            capabilities {
                if {[dict get $result library_id] ne [dict get $state selected]} return
                if {[dict get $result registry_sha256] ne [dict get $state page registry_sha256]} {viewerGuiDesignCatalogRefresh $window $form;return}
                dict set state capabilities $result;dict set ::GX::ViewerGui::instances $window catalogs $form $state
                set rows {}
                foreach name {list_entries entry_info search_entries read_entry add_entry remove_entry export_entry verify mutable read_only remote external offline_available authentication_required library_viewer entry_viewer} {
                    set declared [datasetPublicationV2DictDefault $result capability.$name unknown]
                    set enabled {N/A}
                    set reason {Provider property declaration; this row is not an action}
                    switch $name {
                        list_entries - verify {
                            set enabled [datasetPublicationV2DictDefault $result action.$name 0]
                            set reason [datasetPublicationV2DictDefault $result reason.$name {Capability or owned hook unavailable}]
                        }
                        library_viewer - entry_viewer {
                            set action [expr {$name eq {library_viewer}?{open}:{entry_open}}]
                            set enabled [expr {$declared eq {1} && [datasetPublicationV2DictDefault $result action.$action 0]}]
                            set reason [expr {$declared eq {1}?[datasetPublicationV2DictDefault $result reason.$action {}]:{Provider does not declare this Viewer kind; an Open fallback is a distinct route}}]
                        }
                        read_only {set enabled [datasetPublicationV2DictDefault $result status.read_only unknown];set reason {Effective library policy}}
                        authentication_required {set enabled [datasetPublicationV2DictDefault $result status.authentication_required unknown];set reason [datasetPublicationV2DictDefault $result status.authentication_status unknown]}
                        entry_info - search_entries - read_entry - add_entry - remove_entry - export_entry - mutable {
                            if {$declared eq {0}} {set enabled 0;set reason {Provider does not declare this capability}} else {set reason {Declared normalized content operation; CORE validates availability, authentication and source policy on each request}}
                        }
                        remote - external - offline_available {set reason "Provider property; current mode [datasetPublicationV2DictDefault $result mode unknown], availability [datasetPublicationV2DictDefault $result status.availability unknown]"}
                    }
                    lappend rows [list $name $declared $enabled $reason]
                }
                viewerGuiDesignTableSet $window [dict get $p catalog_capabilities] $rows
                set facts {};dict for {key value} $result {if {[string match status.* $key] || $key in {status_source declaration_source supported_modes}} {lappend facts [list $key $value]}}
                foreach row [dict get $state rows] {if {[dict get $row library_id] eq [dict get $state selected]} {dict for {key value} $row {lappend facts [list "registry.$key" $value]};break}}
                viewerGuiDesignTableSet $window [dict get $p catalog_info] $facts
                if {[dict exists $p catalog_extra_action]} {viewerGuiDesignChoicesSet $window [dict get $p catalog_extra_action] [dict get $result extra_actions]}
                _viewerGuiCatalogMessage $window $form "[dict get $state selected] · [datasetPublicationV2DictDefault $result status.availability unavailable]"
                if {[dict exists $p catalog_entry_filter] && [datasetPublicationV2DictDefault $result capability.list_entries 0]} {
                    viewerGuiDesignCatalogAction $window $form entry_search
                } elseif {[dict exists $p catalog_entries] && [datasetPublicationV2DictDefault $result action.list_entries 0]} {_viewerGuiCatalogRequest $window $form entries [list [dict get $state selected]] entries}
            }
            entries {
                # Existing managed entry enumeration remains its own public
                # contract; consultation is bounded, not a scientific search.
                set shown [lrange $result 0 999]
                uiFieldComponentItemsSet [_viewerGuiCatalogWidget $window $p catalog_entries] list $shown
                dict set ::GX::ViewerGui::instances $window catalogs $form entries $shown
                viewerGuiDesignValueSet $window [dict get $p catalog_entries] {}
                _viewerGuiCatalogMessage $window $form "[llength $shown] / [llength $result] entry IDs shown; source IDs retained."
            }
            entry_page {
                set ids {};foreach row [dict get $result records] {lappend ids [dict get $row entry_id]}
                uiFieldComponentItemsSet [_viewerGuiCatalogWidget $window $p catalog_entries] list $ids
                dict set state entries $ids
                dict set state entry_next [datasetPublicationV2DictDefault $result continuation {}]
                dict set ::GX::ViewerGui::instances $window catalogs $form $state
                viewerGuiDesignValueSet $window [dict get $p catalog_entries] {}
                set total [datasetPublicationV2DictDefault $result total unknown]
                if {[dict exists $p catalog_entry_count]} {viewerGuiDesignTextSet $window [dict get $p catalog_entry_count] "[dict get $result count] entries on this page · total $total · page [expr {[llength [dict get $state entry_history]]+1}]"}
                _viewerGuiCatalogMessage $window $form {Entry page loaded from the selected provider. Select an entry to inspect its exact metadata and provenance.}
            }
            entry_info {
                set facts {};dict for {key value} $result {lappend facts [list $key $value]}
                viewerGuiDesignTableSet $window [dict get $p catalog_entry_info] $facts
                _viewerGuiCatalogMessage $window $form "Entry [dict get $result entry_id] · provider metadata and provenance loaded."
            }
            action {_viewerGuiCatalogMessage $window $form "Library operation [dict get $state active_operation] completed for [dict get $state last_action library_id]." [dict get $state last_action];viewerGuiDesignCatalogRefresh $window $form}
        }
    } message]} {catch {_viewerGuiCatalogMessage $window $form "Library operation unavailable: $message" $message}}
}
proc ::GX::viewerGuiDesignCatalogRefresh {window form} {
    set p [_viewerGuiCatalogForm $window $form];set values [viewerGuiDesignValues $window]
    # Browser pages are declared in the existing Builder design and mounted by
    # the same GUI Host. Catalog refresh never creates another Library window.
    set page 1;if {[dict exists $p catalog_page]} {set page [dict get $values [dict get $p catalog_page]]}
    if {![string is integer -strict $page] || $page<1} {error {Library page must be a positive integer}}
    set type {}
    if {[dict exists $p catalog_type]} {
        set types [::GX::ScientificLibraryManagerAPIv1::listLibraryTypes]
        set type [dict get $values [dict get $p catalog_type]]
        viewerGuiDesignChoicesSet $window [dict get $p catalog_type] [linsert $types 0 {All types}]
        if {$type eq {All types}} {set type {}}
        set facts {}
        foreach item $types {dict for {key value} [::GX::ScientificLibraryManagerAPIv1::getProviderCapabilities $item] {lappend facts [list "$item · $key" $value]}}
        if {[dict exists $p catalog_providers]} {viewerGuiDesignTableSet $window [dict get $p catalog_providers] $facts}
    }
    _viewerGuiCatalogRequest $window $form catalog_page [list [dict get $values [dict get $p catalog_mode]] [dict get $values [dict get $p catalog_filter]] [expr {($page-1)*100}] 100 $type] page
}
proc ::GX::viewerGuiDesignCatalogInspect {window form} {
    set p [_viewerGuiCatalogForm $window $form];set state [_viewerGuiCatalogState $window $form]
    set index [lindex [[_viewerGuiCatalogWidget $window $p catalog_records] curselection] 0]
    if {![string is integer -strict $index] || $index<0 || $index>=[llength [dict get $state rows]]} {return [dict create status awaiting_selection]}
    set id [dict get [lindex [dict get $state rows] $index] library_id]
    if {$id eq [dict get $state selected] && [dict get $state capabilities] ne {} && [dict get $state request] eq {}} {viewerGuiActionsRefresh $window;return [dict create status selected library_id $id]}
    dict set state selected $id;dict set state capabilities {};dict set state entries {}
    foreach key {entry_query entry_token entry_history entry_next} {dict set state $key {}}
    dict set ::GX::ViewerGui::instances $window catalogs $form $state
    if {[dict exists $p catalog_entries]} {uiFieldComponentItemsSet [_viewerGuiCatalogWidget $window $p catalog_entries] list {};viewerGuiDesignValueSet $window [dict get $p catalog_entries] {}}
    if {[dict exists $p catalog_entry_info]} {viewerGuiDesignTableSet $window [dict get $p catalog_entry_info] {}}
    _viewerGuiCatalogRequest $window $form library_capabilities [list $id] capabilities
}
proc ::GX::_viewerGuiCatalogActionEnabled {window command} {
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $c properties]
        if {[dict get $c type] ne {section} || ![dict exists $p catalog_owner]} continue
        dict for {action id} [dict get $p catalog_actions] {
            if {$id ne $command} continue
            if {[string match browse_* $action]} {return [expr {[dict exists $p catalog_browser_group] && [dict exists $::GX::ViewerGui::instances $window library_browsers [dict get $p catalog_browser_group]]}]}
            set state [_viewerGuiCatalogState $window [dict get $c id]]
            if {[dict get $state request] ne {}} {return 0}
            if {$action in {refresh install register_external register_remote}} {return 1}
            set caps [dict get $state capabilities]
            if {$action eq {entry_search}} {return [expr {[datasetPublicationV2DictDefault $caps capability.list_entries 0] && [dict exists $p catalog_entry_filter]}]}
            if {$action eq {entry_next}} {return [expr {[dict get $state selected] ne {} && [dict get $state entry_next] ne {}}]}
            if {$action eq {entry_previous}} {return [expr {[dict get $state selected] ne {} && [llength [dict get $state entry_history]]>0}]}
            if {$action eq {entry_info}} {return [expr {[datasetPublicationV2DictDefault $caps capability.entry_info 0] && [llength [[_viewerGuiCatalogWidget $window $p catalog_entries] curselection]]==1}]}
            if {$action eq {entry_open}} {return [expr {[datasetPublicationV2DictDefault $caps action.entry_open 0] && [dict exists $p catalog_entries] && [llength [[_viewerGuiCatalogWidget $window $p catalog_entries] curselection]]==1}]}
            if {$action eq {extra_action}} {return [expr {[dict exists $p catalog_extra_action] && [llength [datasetPublicationV2DictDefault $caps extra_actions {}]]>0}]}
            return [datasetPublicationV2DictDefault $caps action.$action 0]
        }
    }
    return {}
}
proc ::GX::viewerGuiDesignCatalogAction {window form action} {
    set p [_viewerGuiCatalogForm $window $form];set state [_viewerGuiCatalogState $window $form]
    if {![dict exists $p catalog_actions $action] || ![_viewerGuiCatalogActionEnabled $window [dict get $p catalog_actions $action]]} {error {This library action is currently unavailable; inspect its capability/status first}}
    if {[string match browse_* $action]} {return [viewerGuiDesignLibraryPage $window [dict get $p catalog_browser_group] [string range $action 7 end]]}
    set id [dict get $state selected]
    switch $action {
        refresh {viewerGuiDesignCatalogRefresh $window $form}
        entry_search - entry_next - entry_previous {
            if {$action eq {entry_search}} {
                dict set state entry_query [dict get [viewerGuiDesignValues $window] [dict get $p catalog_entry_filter]]
                dict set state entry_token {};dict set state entry_history {}
            } elseif {$action eq {entry_next}} {
                dict lappend state entry_history [dict get $state entry_token]
                dict set state entry_token [dict get $state entry_next]
            } else {
                dict set state entry_token [lindex [dict get $state entry_history] end]
                dict set state entry_history [lrange [dict get $state entry_history] 0 end-1]
            }
            # Tokens are provider-owned and bound to the exact original query.
            # An edited query is applied only by an explicit Search request.
            set parameters [dict create limit 100]
            if {[dict get $state entry_token] ne {}} {dict set parameters continuation [dict get $state entry_token]}
            set operation list_entries
            if {[dict get $state entry_query] ne {}} {
                set operation search_entries
                dict set parameters query_json [viewerDevelopmentJsonString [dict get $state entry_query]]
            }
            dict set state entry_next {};dict set state entries {}
            dict set ::GX::ViewerGui::instances $window catalogs $form $state
            uiFieldComponentItemsSet [_viewerGuiCatalogWidget $window $p catalog_entries] list {}
            if {[dict exists $p catalog_entry_info]} {viewerGuiDesignTableSet $window [dict get $p catalog_entry_info] {}}
            _viewerGuiCatalogRequest $window $form content [list $id $operation $parameters] entry_page
        }
        entry_info {
            set index [lindex [[_viewerGuiCatalogWidget $window $p catalog_entries] curselection] 0]
            set entry [lindex [dict get $state entries] $index]
            viewerGuiDesignTableSet $window [dict get $p catalog_entry_info] {}
            _viewerGuiCatalogRequest $window $form content [list $id entry_info [dict create entry_id $entry]] entry_info
        }
        open - entry_open {
            set context {}
            if {$action eq {entry_open}} {set index [lindex [[_viewerGuiCatalogWidget $window $p catalog_entries] curselection] 0];dict set context entry_id [lindex [dict get $state entries] $index]}
            set receipt [::GX::ScientificLibraryManagerAPIv1::openLibraryViewer $id $context]
            _viewerGuiCatalogMessage $window $form {Opened the provider's registered Viewer.} $receipt
        }
        verify {_viewerGuiCatalogRequest $window $form verify [list $id] action}
        install - update {
            set path [workspaceOpenFile acquisition_dir -parent $window -title {Select scientific library package} -filetypes {{{Scientific library ZIP} {.zip}}}]
            if {$path eq {}} return
            set args [list $path];if {$action eq {update}} {set args [list $id $path]}
            _viewerGuiCatalogRequest $window $form $action $args action
        }
        remove - unregister {
            if {[tk_messageBox -parent $window -type yesno -icon question -message "[string totitle $action] registered library $id? Existing references may become unavailable."] ne {yes}} return
            _viewerGuiCatalogRequest $window $form $action [list $id] action
        }
        register_external - register_remote {_viewerGuiCatalogRegistration $window $form [string range $action 9 end]}
        extra_action {
            set selected [dict get [viewerGuiDesignValues $window] [dict get $p catalog_extra_action]]
            set current [::GX::ScientificLibraryManagerAPIv1::getLibraryCapabilities $id]
            if {$selected ni [dict get $current extra_actions] || ![dict get $current action.$selected]} {error {Selected provider action is unavailable}}
            _viewerGuiCatalogRequest $window $form library_action [list $id $selected] action
        }
        default {error {Unsupported catalog action}}
    }
}
proc ::GX::viewerGuiDesignCatalogDescribe {window form} {
    _viewerGuiCatalogForm $window $form
    return [dict merge [dict create owner SCIENTIFIC_LIBRARY_MANAGER_API_v1 presentation_only 1] [_viewerGuiCatalogState $window $form]]
}
proc ::GX::_viewerGuiCatalogRegistration {window form mode} {
    _viewerGuiCatalogForm $window $form
    set types [::GX::ScientificLibraryManagerAPIv1::listLibraryTypes]
    if {$types eq {}} {error {Install a Library Type Provider before registering a scientific library}}
    uiFieldFormCreate $window.catalogRegistration {Register library — choose provider type} [dict create library_type [dict create type choice values $types label {Library type / registered provider}]] [dict create library_type [lindex $types 0]] [list ::GX::_viewerGuiCatalogRegistrationType $window $form $mode] $window
}
proc ::GX::_viewerGuiCatalogRegistrationType {window form mode values} {
    _viewerGuiCatalogForm $window $form
    set type [dict get $values library_type]
    set capabilities [::GX::ScientificLibraryManagerAPIv1::getProviderCapabilities $type]
    set fields [dict create library_id {type string label {Stable library ID}} display_name {type string label {Display name}} origin {type string label {Origin / source reference}} license {type string label License} rights {type string label {Rights summary}} description {type string label Description} version {type string label {Version if meaningful}} read_only {type boolean label {Read only}} availability {type choice values {unknown available unavailable temporarily_unavailable} label {Registration availability declaration}}]
    set initial {read_only 1 availability unknown};set mapping {};set index 0
    foreach kind {required optional} {
        foreach key [dict get $capabilities registration.$mode.$kind] {
            set control provider_[incr index]
            dict set mapping $control [dict create key $key required [expr {$kind eq {required}}]]
            dict set fields $control [dict create type string label "Provider $key ($kind, non-secret)"]
            dict set initial $control {}
        }
    }
    if {$index>32} {error {This provider requires more than32 configuration fields; a reviewed larger form is needed}}
    set dialog $window.catalogRegistration
    # Use a second dialog so the existing UI Field Apply callback is not
    # destroyed while it is still processing its first form's return value.
    set details $window.catalogRegistrationDetails
    uiFieldFormCreate $details "Register $mode library — $type" $fields $initial [list ::GX::_viewerGuiCatalogRegistrationApply $window $form $mode $type $mapping] $window
    if {$mode ni [dict get $capabilities supported_modes]} {
        ttk::label $details.viewport.content.scope -text "This provider does not declare $mode access. Registration stores a reference; it does not establish connectivity or scientific availability." -wraplength 480
        grid $details.viewport.content.scope -row 80 -column 0 -sticky ew
    }
}
proc ::GX::_viewerGuiCatalogRegistrationApply {window form mode type mapping values} {
    _viewerGuiCatalogForm $window $form
    set fields [dict create mode $mode library_type $type]
    foreach key {library_id display_name origin license rights description version read_only availability} {dict set fields $key [dict get $values $key]}
    dict for {control specification} $mapping {
        set value [dict get $values $control]
        if {[dict get $specification required] && [string trim $value] eq {}} {error "Required provider configuration is empty: [dict get $specification key]"}
        if {$value ne {}} {dict set fields config.[dict get $specification key] $value}
    }
    set arguments {};dict for {key value} $fields {lappend arguments $key $value}
    _viewerGuiCatalogRequest $window $form register $arguments action
}
proc ::GX::_viewerGuiCatalogDispose {window} {
    if {[dict exists $::GX::ViewerGui::instances $window catalogs]} {
        set catalogs [dict get $::GX::ViewerGui::instances $window catalogs]
        # Invalidate before cancellation: completion must not restart pending
        # reads or resurrect state while this window is being disposed.
        dict unset ::GX::ViewerGui::instances $window catalogs
        dict for {form state} $catalogs {if {[dict get $state request] ne {}} {scriptJobRequestCancel [dict get $state request]}}
    }
}
