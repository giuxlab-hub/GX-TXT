# SPDX-License-Identifier: GPL-3.0-or-later
# Declared generic comparison controls; C++ routes finite intents only.
proc ::GX::_viewerGuiComparisonForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Comparison belongs to a previous Session lifetime}}
    _viewerGuiComparisonDesignValidate [dict get $::GX::ViewerGui::instances $window design]
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || ![dict exists $c properties comparison_target]} {error {Select a declared Comparison form}}
    return [dict get $c properties]
}
proc ::GX::_viewerGuiComparisonSources {window form} {
    return [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] comparison_sources {}] $form {}]
}
proc ::GX::_viewerGuiComparisonRefresh {window form {message {}}} {
    set p [_viewerGuiComparisonForm $window $form]
    set sources [_viewerGuiComparisonSources $window $form];set rows {};set choices {};set index 0
    foreach source $sources {
        set state current
        if {[catch {_comparisonPlotCurrent $source}]} {set state stale}
        lappend rows [list $index [dict get $source kind] [dict get $source label] [dict get $source x_unit] [dict get $source y_unit] $state]
        lappend choices $index;incr index
    }
    viewerGuiDesignTableSet $window [dict get $p comparison_sources] $rows
    set selected [dict get [viewerGuiDesignValues $window] [dict get $p comparison_source]]
    viewerGuiDesignChoicesSet $window [dict get $p comparison_source] $choices
    if {$selected ni $choices} {viewerGuiDesignValueSet $window [dict get $p comparison_source] [lindex $choices 0]}
    if {$message ne {}} {viewerGuiDesignTextSet $window [dict get $p comparison_status] $message}
    return [dict create source_count [llength $sources] sources $sources]
}
proc ::GX::_viewerGuiComparisonCapture {window} {
    if {![dict exists $::GX::ViewerGui::instances $window comparison_sources]} return
    set forms {}
    dict for {form sources} [dict get $::GX::ViewerGui::instances $window comparison_sources] {dict set forms $form [dict create sources $sources]}
    set state [viewerGuiDesignContextGet $window];dict set state comparison_forms $forms
    viewerGuiDesignContextSet $window $state
}
proc ::GX::_viewerGuiComparisonRestoreCheck {window state} {
    dict for {form data} [datasetPublicationV2DictDefault $state comparison_forms {}] {
        _viewerGuiComparisonForm $window $form
        if {[dict keys $data] ne {sources} || [llength [dict get $data sources]]>8} {error {Malformed saved comparison source selection}}
        foreach source [dict get $data sources] {_comparisonPlotCurrent $source}
    }
}
proc ::GX::_viewerGuiComparisonRestore {window state} {
    dict set ::GX::ViewerGui::instances $window comparison_sources {}
    dict for {form data} [datasetPublicationV2DictDefault $state comparison_forms {}] {
        dict set ::GX::ViewerGui::instances $window comparison_sources $form [dict get $data sources]
        _viewerGuiComparisonRefresh $window $form {Restored exact source identities. Prepared comparison remains source-bound.}
    }
}
proc ::GX::_viewerGuiComparisonConfig {window form} {
    set p [_viewerGuiComparisonForm $window $form];set values [viewerGuiDesignValues $window]
    set mode [dict get $values [dict get $p comparison_mode]]
    set configuration [dict create schema GXTXT_COMPARISON_PLOT_v1 sources [_viewerGuiComparisonSources $window $form] mode $mode \
        normalization [dict get $values [dict get $p comparison_normalization]] \
        offset [expr {$mode eq {stacked}?[dict get $values [dict get $p comparison_offset]]:0}] \
        denominator_floor [dict get $values [dict get $p comparison_floor]] interpolation linear domain intersection_first_source_grid]
    if {[datasetPublicationV2DictDefault $p comparison_single_source 0]} {dict set configuration single_source_consultation 1}
    return $configuration
}
proc ::GX::viewerGuiDesignComparisonCommand {window form operation} {
    set p [_viewerGuiComparisonForm $window $form]
    if {$operation ni [viewerGuiComparisonCommands]} {error {Unknown finite Comparison operation}}
    if {[string match plot_* $operation]} {
        if {$operation ni {plot_fit plot_zoom_in plot_zoom_out plot_copy plot_export} && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerEditable $window]} {error {History browsing is read-only; return to latest before editing the Plot}}
        return [_viewerComparisonPlotCommand $window $form $operation]
    }
    set values [viewerGuiDesignValues $window];set sources [_viewerGuiComparisonSources $window $form]
    if {$operation ni {discover inspect} && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerEditable $window]} {error {History browsing is read-only; return to latest before changing comparison}}
    switch $operation {
        discover {
            set dataset [dict get $values [dict get $p comparison_dataset]]
            if {$dataset ne {}} {
                set choices [dict get [_viewerGuiPlotVariables $dataset] choices]
                foreach key {comparison_x comparison_y} {
                    viewerGuiDesignChoicesSet $window [dict get $p $key] $choices
                    if {[dict get $values [dict get $p $key]] ni $choices} {viewerGuiDesignValueSet $window [dict get $p $key] [lindex $choices [expr {$key eq {comparison_y} && [llength $choices]>1?1:0}]]}
                }
            }
            set legacyLibrary [expr {[dict exists $p comparison_library] && [dict exists $p comparison_entry] && (![dict exists $p comparison_library_browser_group] || {add_library} in [dict values [dict get $p comparison_commands]])}]
            if {$legacyLibrary} {
                set libraryChoices {}
                set allowLibrary [_viewerComparisonLibraryAllowed $window]
                if {$allowLibrary} {
                    set page [::GX::ScientificLibraryManagerAPIv1::libraryCatalogPage {mode all offset 0 limit 200}]
                    foreach info [dict get $page records] {
                        if {[_comparisonPlotGet $info state {}] eq {installed} && [_comparisonPlotGet $info mode managed] eq {managed}} {lappend libraryChoices [dict get $info library_id]}
                    }
                }
                viewerGuiDesignChoicesSet $window [dict get $p comparison_library] $libraryChoices
                set library [dict get $values [dict get $p comparison_library]]
                if {$library ni $libraryChoices} {set library [lindex $libraryChoices 0];viewerGuiDesignValueSet $window [dict get $p comparison_library] $library}
                set entries {}
                if {$library ne {}} {
                    set page [::GX::ScientificLibraryManagerAPIv1::libraryEntriesPage $library {limit 200}]
                    foreach row [dict get $page records] {lappend entries [dict get $row entry_id]}
                }
                viewerGuiDesignChoicesSet $window [dict get $p comparison_entry] $entries
                if {[dict get $values [dict get $p comparison_entry]] ni $entries} {viewerGuiDesignValueSet $window [dict get $p comparison_entry] [lindex $entries 0]}
            }
            return [_viewerGuiComparisonRefresh $window $form [expr {$legacyLibrary?{Choose actual Dataset Variables or a managed Library entry. Legacy choices cover the first200 entries; consultation never publishes a Dataset.}:{Choose actual Dataset Variables or inspect an Entry in the shared paginated Library Browser. Consultation never publishes a Dataset.}}]]
        }
        add_dataset {
            set source [comparisonPlotSourceDataset [dict get $values [dict get $p comparison_dataset]] [dict get $values [dict get $p comparison_x]] [dict get $values [dict get $p comparison_y]]]
            if {$source in $sources} {error {This exact source is already selected}}
            if {[llength $sources]>=8} {error {Comparison supports at most eight source references}}
            lappend sources $source
        }
        add_library {
            set source [comparisonPlotSourceLibrary [dict get $values [dict get $p comparison_library]] [dict get $values [dict get $p comparison_entry]]]
            if {$source in $sources} {error {This exact source is already selected}}
            if {[llength $sources]>=8} {error {Comparison supports at most eight source references}}
            lappend sources $source
        }
        add_browser - add_opened {
            if {![dict exists $p comparison_library_browser_group]} {error {This Comparison form has no declared Library Browser group}}
            if {$operation eq {add_browser}} {
                set selectionCommand [list viewerGuiDesignLibrarySelection $window [dict get $p comparison_library_browser_group]]
            } else {
                if {![dict exists $::GX::ViewerDevelopment::windows $window open_context library_id] || ![dict exists $::GX::ViewerDevelopment::windows $window open_context entry_id]} {error {The Viewer was not opened with an actual Library entry}}
                set context [dict get $::GX::ViewerDevelopment::windows $window open_context]
                set selectionCommand [list _viewerGuiLibraryReference $window [dict get $p comparison_library_browser_group] [dict get $context library_id] [dict get $context entry_id]]
            }
            set selected [{*}$selectionCommand]
            set source [comparisonPlotSourceLibrary [dict get $selected library_id] [dict get $selected entry_id]]
            # Pin through the normal scientific owner, then recheck the exact
            # inspected domain identity after that owner's bounded reads.
            if {[{*}$selectionCommand] ne $selected} {error {Library selection changed during admission}}
            if {$source in $sources} {error {This exact source is already selected}}
            if {[llength $sources]>=8} {error {Comparison supports at most eight source references}}
            lappend sources $source
        }
        remove - up - down - inspect {
            set selected [dict get $values [dict get $p comparison_source]]
            if {![string is entier -strict $selected] || $selected<0 || $selected>=[llength $sources]} {error {Select an actual source reference}}
            if {$operation eq {inspect}} {return [_viewerGuiComparisonRefresh $window $form [lindex $sources $selected]]}
            if {$operation eq {remove}} {set sources [lreplace $sources $selected $selected]} else {
                set next [expr {$selected+($operation eq {up}?-1:1)}]
                if {$next<0 || $next>=[llength $sources]} {error {Source is already at the requested boundary}}
                set source [lindex $sources $selected];set sources [lreplace $sources $selected $selected]
                set sources [linsert $sources $next $source]
                viewerGuiDesignValueSet $window [dict get $p comparison_source] $next
            }
        }
        prepare {
            set configuration [_viewerGuiComparisonConfig $window $form]
            comparisonPlotValidate $configuration
            if {[dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {error {Comparison cancelled before changing the valid Plot}}
            set plot [viewerGuiDesignPlotSet $window [dict get $p comparison_target] [comparisonPlotSpec $configuration]]
            set scientific [::GX::PlotDatasetAPIv4::widgetComparisonReceipt $plot]
            # The native widget stores the complete prepared scientific receipt;
            # only a source-free summary is needed by C++ event dispatch.
            set alignment [expr {[dict get $configuration mode] in {difference ratio}?{Linear alignment uses only common first-source coordinates; no extrapolation.}:{Independent complete source grids; no resampling or domain clipping.}}]
            set message "Prepared [dict get $configuration mode]; normalization [dict get $configuration normalization]; display offset step [dict get $configuration offset]; denominator floor [dict get $configuration denominator_floor].\nExplicit invalid/gap samples: [dict get $scientific invalid_samples].\nSource order is explicit. $alignment\nCanonical samples and identities are unchanged; this is a transient display, not scientific identification."
            _viewerGuiComparisonRefresh $window $form $message
            return [dict create status prepared mode [dict get $configuration mode] source_count [llength $sources] canonical_values_modified 0]
        }
        clear {set sources {}}
    }
    dict set ::GX::ViewerGui::instances $window comparison_sources $form $sources
    _viewerGuiComparisonCapture $window
    set result [_viewerGuiComparisonRefresh $window $form {Source selection changed. Prepare explicitly to replace the last valid frame.}]
    if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window "Comparison sources: $operation"}
    if {$operation in {add_browser add_opened}} {dict set result selected_entry $selected}
    return $result
}
proc ::GX::_viewerComparisonNativeCommand {window form operation} {
    set scope [_viewerNativeClientScope $window]
    set r [dict get $::GX::ViewerDevelopment::windows $window]
    set sequence [expr {[datasetPublicationV2DictDefault $r comparison_sequence 0]+1}]
    dict set ::GX::ViewerDevelopment::windows $window comparison_sequence $sequence
    set status completed;set problem {};set result {null {}}
    try {
        if {{comparison_command} ni [datasetPublicationV2DictDefault [dict get $r native_client_grants] COMPARISON_PLOT_API_v1 {}]} {error {Comparison native capability is not granted}}
        set p [_viewerGuiComparisonForm $window $form]
        set permitted [expr {$operation eq {discover} && ![dict get $scope user_action]}]
        if {[dict exists $p comparison_commands [dict get $scope action]] && [dict get $p comparison_commands [dict get $scope action]] eq $operation && [dict get $scope effect] eq {presentation}} {set permitted 1}
        if {!$permitted} {error {Comparison requires its exact declared presentation action}}
        set grants [dict get $r native_client_grants]
        if {$operation in {add_library add_browser add_opened} && ![_viewerComparisonLibraryAllowed $window]} {error {Read-only Library consultation is not granted}}
        if {$operation eq {prepare}} {
            foreach source [_viewerGuiComparisonSources $window $form] {
                if {[dict get $source kind] eq {library_entry} && ![_viewerComparisonLibraryAllowed $window]} {error {Saved Library source consultation is not granted}}
            }
        }
        set value [viewerGuiDesignComparisonCommand $window $form $operation]
        _viewerNativeClientScope $window
        if {[dict exists $value status] && [dict get $value status] eq {cancelled}} {
            set status cancelled
            set result {null {}}
        } else {
            set summary [dict create status $operation source_count [llength [_viewerGuiComparisonSources $window $form]] canonical_values_modified 0]
            foreach key {status mode source_count canonical_values_modified} {if {[dict exists $value $key]} {dict set summary $key [dict get $value $key]}}
            set result [nativeWorkspaceEncode {record {status text mode text source_count int canonical_values_modified bool}} $summary]
            if {$operation in {add_browser add_opened}} {
                set source [lindex [_viewerGuiComparisonSources $window $form] end]
                set pin [dict create library_id [dict get $source library_id] entry_id [dict get $source entry_id] library_version [dict get $source revision] payload_sha256 [dict get $source sha256] semantic_sha256 [dict get $source semantic_sha256]]
                set selection [dict get $value selected_entry]
                set pin [dict merge $pin [dict create entry_revision [dict get $selection revision] content_sha256 [dict get $selection content_sha256] provider_id [dict get $selection provider_id] source_id [dict get $selection source_id] session_token [_viewerNativeClientSessionToken] window_lifetime [dict get $r lifetime] event_generation [dict get $scope generation]]]
                lset result 1 [dict merge [lindex $result 1] [dict create selected_source [nativeWorkspaceEncode {record {library_id text entry_id text library_version text payload_sha256 text semantic_sha256 text entry_revision text content_sha256 text provider_id text source_id text session_token text window_lifetime int event_generation int}} $pin]]]
            }
        }
    } on error {message options} {
        set status failed;set problem [_viewerNativeClientPublicMessage $message]
        if {[viewerGuiDesignGuard $window]} {catch {_viewerGuiComparisonRefresh $window $form "Comparison refused: $problem\nThe last valid Plot and canonical data are retained."}}
    }
    if {[dict exists $::GX::ViewerDevelopment::windows $window]} {
        dict set ::GX::ViewerDevelopment::windows $window comparison_result [_viewerNativeClientEnvelope $operation $status $problem $result [list object [dict create form [list text $form]]] $sequence [dict get $scope generation]]
    }
    # Keep the fresh failed/null receipt, and let the existing native action
    # owner display the same refusal instead of a misleading completed footer.
    if {$status eq {failed}} {return -code error $problem}
}
proc ::GX::_viewerComparisonSnapshot {window} {
    set r [_viewerNativeClientBase $window]
    set value [datasetPublicationV2DictDefault $r comparison_result [_viewerNativeClientEnvelope snapshot completed {} {null {}} {object {}} 0 0]]
    return [_viewerWorkspaceTypedJson $value]
}
proc ::GX::_viewerComparisonLibraryAllowed {window} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]} {return 1}
    set grants [datasetPublicationV2DictDefault [dict get $::GX::ViewerDevelopment::windows $window] native_client_grants {}]
    set actual [datasetPublicationV2DictDefault $grants SCIENTIFIC_LIBRARY_MANAGER_API_v1 {}]
    foreach operation {libraryCatalogPage libraryEntriesPage getLibraryInfo getLibraryEntryInfo readLibraryEntry} {if {$operation ni $actual} {return 0}}
    return 1
}
