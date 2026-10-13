# SPDX-License-Identifier: GPL-3.0-or-later
# No row/filter evaluator or renderer access. CORE owns the exact selected view,
# original-row identities, schema validation and atomic create-only publication.
namespace eval ::GX::CurveDatasetExport {variable version 1.0.0}
proc ::GX::CurveDatasetExport::publish {context} {
    variable version
    if {"source_row_adjacency" ni [::GX::datasetPublicationV2DictDefault [::GX::curveSourceApiInfo] continuity_policies {}]} {error {CORE Curve Source does not support declared scientific row continuity}}
    set selection [dict get $context selection]
    if {[dict get $selection kind] ne "curve_source"} {error {Select one visible scientific source curve}}
    set frozen [dict get $selection descriptor]
    set request [dict get $selection request]
    set session $::GX::currentSession;set lifetime [::GX::interactiveDocumentSessionToken]
    if {[dict get $selection session_token] ne $lifetime} {error {Publication submission belongs to a different Session lifetime}}
    set document [::GX::interactiveDocumentRead [dict get $context document_id]]
    if {[dict get $document generation] ne [dict get $selection document_generation]} {error {Publication submission belongs to a stale Workspace generation}}
    if {![dict get [::GX::curveSourceValidateSnapshot $session $frozen] valid]} {error {Scientific source changed since publication submission}}
    if {[string trim [dict get $context parameters dataset_id]] eq {}} {error {Output Dataset ID is required}}
    set output [::GX::datasetPublicationV2RequestedId [dict get $context parameters dataset_id]]
    if {$output eq {}} {error {Output Dataset ID is required}}
    set display [dict get $context parameters display_name]
    if {$display eq {}} {set display $output}
    set source {};set writer {}
    try {
        set source [::GX::curveSourceOpen $session $request]
        set descriptor [::GX::curveSourceDescribe $source]
        if {[dict get $descriptor source_id] ne [dict get $frozen source_id]} {error {Scientific source request is stale}}
        set count [dict get $descriptor row_count]
        if {$count<1} {error {No scientific rows match the selected curve}}
        set variables [dict get $descriptor variables]
        foreach variable $variables {
            set unit [dict get $variable unit]
            if {$unit ne {}} {
                # Registered opaque scientific units are legitimate labels;
                # unregistered expressions must be understood by CORE units.
                if {$unit ni [::GX::unitRegistryList]} {::GX::unitRegistryIntrinsicScale $unit}
                ::GX::unitRegistryConversionPlan $unit $unit
            }
        }
        set ids [lmap v $variables {dict get $v variable_id}]
        set lineage published_source_row
        while {$lineage in $ids} {append lineage _}
        set metadata [dict create dataset.display_name $display \
            curve_publication.producer export.curve_dataset curve_publication.producer_version $version \
            curve_publication.source_dataset_id [dict get $request dataset_id] \
            curve_publication.source_id [dict get $descriptor source_id] \
            curve_publication.source_identities [dict get $descriptor source_identities] \
            curve_publication.source_request $request curve_publication.variable_schema $variables \
            curve_publication.publication_method exact_curve_source_pages \
            curve_publication.finite_policy preserve_all_exact_rows \
            curve_publication.order_policy curve_source_request_order \
            curve_source.continuity_policy source_row_adjacency curve_source.continuity_variable_id $lineage]
        set definition [dict create dataset_id $output contract table.generic storage auto expected_rows $count \
            estimated_numeric_bytes [expr {24*$count}] producer_version $version \
            source_dataset_ids [list [dict get $request dataset_id]] source_variable_ids $ids \
            source {Exact filtered scientific curve} provenance $request structured_metadata $metadata]
        set plan [::GX::datasetPublicationV2Prepare $session export.curve_dataset $definition]
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach variable $variables {
            set schema [dict create dimension_ids row rank 1 axis_kind explicit]
            foreach field {dtype canonical name display_label unit value_kind semantic_role semantic_source coordinate_role value_format decimal_separator time_origin time_reference canonical_unit to_canonical from_canonical instrument_id instrument_channel} {
                if {[dict exists $variable $field]} {dict set schema $field [dict get $variable $field]}
            }
            ::GX::datasetPublicationV2DeclareVariable $writer [dict get $variable variable_id] $schema
        }
        ::GX::datasetPublicationV2DeclareVariable $writer $lineage [dict create dimension_ids row rank 1 dtype int64 unit {} semantic_role source_row_identity coordinate_role auxiliary value_kind number display_label {Original source row (zero based)}]
        for {set start 0} {$start<$count} {incr start 1000} {
            set page [::GX::curveSourcePage $source $start [expr {min(1000,$count-$start)}]]
            set data [dict create $lineage [dict get $page source_rows]]
            foreach id $ids column {0 1} {dict set data $id [lmap pair [dict get $page rows] {lindex $pair $column}]}
            ::GX::datasetPublicationV2Append $writer row $data
        }
        if {$lifetime ne [::GX::interactiveDocumentSessionToken] || $session ne $::GX::currentSession} {error {Session changed before publication commit}}
        ::GX::curveSourceDescribe $source
        set document [::GX::interactiveDocumentRead [dict get $context document_id]]
        if {[dict get $document module_id] ne [dict get $context workbench_id] || [dict get $document revision] ne [dict get $context revision] || [dict get $document generation] ne [dict get $selection document_generation]} {error {Viewer Workspace changed before publication commit}}
        set receipt [::GX::datasetPublicationV2Finalize $writer];set writer {}
        return [dict create status ok dataset_id $output publication $receipt exact_rows $count provenance $metadata]
    } finally {
        if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}
        if {$source ne {}} {::GX::curveSourceClose $source}
    }
}
proc ::GX::CurveDatasetExport::apiInfo {} {
    variable version
    return [dict create api_name CURVE_DATASET_EXPORT_API_v1 api_version 1 module_id export.curve_dataset module_version $version operations publish scientific_authorities {CURVE_SOURCE_API_v1 DATASET_PUBLICATION_API_v2}]
}
