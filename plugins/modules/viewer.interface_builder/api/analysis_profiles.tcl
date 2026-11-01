# SPDX-License-Identifier: GPL-3.0-or-later
# Native Builder forms use the same public validated atomic model operations.
proc ::GX::InterfaceBuilder::analysisProfile {} {
    variable s
    set current {};set choices {}
    foreach c [dict get [design] components] {
        if {[dict get $c id] eq $s(selected)} {set current $c}
        dict lappend choices [dict get $c type] [dict get $c id]
    }
    if {$current eq {} || [dict get $current type] ne {section}} {error {Select the section that will own the Analysis controls}}
    set fields [dict create analysis_module [dict create type string label {Registered Analysis module ID} required 1] \
        analysis_bindings [dict create type string label {Binding role to Variable-choice component map} default {}] \
        analysis_config [dict create type string label {Analysis parameter to value-control component map} default {}]]
    foreach {key type label} {
        analysis_dataset dataset_selector {Canonical source Dataset selector}
        analysis_status log {Analysis status log}
        analysis_candidates table {Ranked-reference result table}
        analysis_candidate choice {Selected stable candidate rank}
        analysis_comparison_form section {Existing Comparison form}
    } {
        set ids [::GX::datasetPublicationV2DictDefault $choices $type {}]
        if {$key eq {analysis_candidate}} {set ids [concat $ids [::GX::datasetPublicationV2DictDefault $choices combobox {}]]}
        if {$key eq {analysis_comparison_form}} {
            set ids {};foreach c [dict get [design] components] {if {[dict get $c type] eq {section} && [dict exists $c properties comparison_target]} {lappend ids [dict get $c id]}}
        }
        if {$ids eq {}} {error "Add the required $label control before applying the profile"}
        dict set fields $key [dict create type choice label $label values $ids required 1]
    }
    set pages [concat [list {}] [::GX::datasetPublicationV2DictDefault $choices field {}] [::GX::datasetPublicationV2DictDefault $choices entry {}]]
    dict set fields analysis_page [dict create type choice label {Optional zero-based result page control} values $pages]
    set initial {}
    dict for {key descriptor} $fields {dict set initial $key [::GX::datasetPublicationV2DictDefault [dict get $current properties] $key [::GX::datasetPublicationV2DictDefault $descriptor default [lindex [::GX::datasetPublicationV2DictDefault $descriptor values {}] 0]]]}
    set w .gxInterfaceAnalysisProfile
    ::GX::uiFieldFormCreate $w {Targeted Analysis profile — apply together} $fields $initial [list ::GX::InterfaceBuilder::analysisProfileApply $s(selected) [dict get $s(model) revision]] .gxInterfaceDesigner
    set ::GX::UiField::formStatus($w) {Map existing controls by their stable component IDs. Apply validates the complete profile and adds one primary Analysis menu. Runtime module and native SDK admission remain separate.}
    return $w
}
proc ::GX::InterfaceBuilder::analysisProfileApply {form revision values} {
    variable s
    if {[dict get $s(model) revision]!=$revision} {error {The design changed while this profile was open; reopen it}}
    foreach key {analysis_bindings analysis_config} {if {[catch {dict size [dict get $values $key]}]} {error {Binding/config mappings must be dictionaries of stable role/parameter and component IDs}}}
    if {[dict get $values analysis_page] eq {}} {dict unset values analysis_page}
    apply analysis_profile $form $values
    if {[winfo exists .gxInterfaceAnalysisProfile]} {destroy .gxInterfaceAnalysisProfile}
}
proc ::GX::InterfaceBuilder::comparisonBrowserOnly {} {
    variable s
    set current {};foreach c [dict get [design] components] {if {[dict get $c id] eq $s(selected)} {set current $c;break}}
    if {$current eq {} || [dict get $current type] ne {section} || ![dict exists $current properties comparison_target]} {error {Select an existing Comparison form}}
    set groups [dict keys [::GX::_viewerGuiLibraryDefinitions [design] 1]]
    if {$groups eq {}} {error {Add all three shared Library Browser pages first}}
    set group [::GX::datasetPublicationV2DictDefault [dict get $current properties] comparison_library_browser_group [lindex $groups 0]]
    set w .gxInterfaceComparisonBrowser
    ::GX::uiFieldFormCreate $w {Use the shared Library Browser} [dict create group [dict create type choice label {Complete Library Browser group} values $groups required 1]] [dict create group $group] [list ::GX::InterfaceBuilder::comparisonBrowserOnlyApply $s(selected) [dict get $s(model) revision]] .gxInterfaceDesigner
    set ::GX::UiField::formStatus($w) {Apply removes both legacy Library/Entry profile references and its add_library intent in one undoable edit. Remove unused controls and menu entries through the normal Builder afterwards. The shared Browser retains selection and pagination.}
    return $w
}
proc ::GX::InterfaceBuilder::comparisonBrowserOnlyApply {form revision values} {
    variable s
    if {[dict get $s(model) revision]!=$revision} {error {The design changed; reopen this profile}}
    apply comparison_browser_only $form [dict get $values group]
    if {[winfo exists .gxInterfaceComparisonBrowser]} {destroy .gxInterfaceComparisonBrowser}
}
