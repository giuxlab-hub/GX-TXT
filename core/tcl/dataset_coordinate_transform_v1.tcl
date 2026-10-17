# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset Transform lifecycle adapter for the existing Metadata coordinate owner.
proc ::GX::_datasetCoordinateTransformCandidate {snapshot mapping target manifest report} {
    set stored [dict get $snapshot coordinate_context]
    if {$stored eq {}} {return [dict create status identity settings [_datasetCoordinateDefaults [_datasetCoordinateSource $target]] configured 0]}
    set sourceId [dict get $snapshot dataset_id];set sourceVid [dict get $mapping source_variable_id]
    _datasetCoordinateValidate $sourceId $stored [dict get $snapshot sha256]
    if {![dict exists $stored variables $sourceVid]} {return [dict create status identity settings [_datasetCoordinateDefaults [_datasetCoordinateSource $target]] configured 0]}
    set settings [dict get $stored variables $sourceVid]
    set op [dict get $manifest operation];set options [dict get $manifest options]
    set outputId [dict get $mapping output_variable_id]
    if {$op eq "transform_xy"&&$outputId in [list [dict get $options x_variable_id] [dict get $options y_variable_id]]} {error {Explicit geometry transform changes coordinate values; source settings retained only in lineage}}
    if {[dict exists $options polar_output]} {error {Polar coordinate transformation requires an explicit new presentation context}}
    if {$op eq "calibrate_variables"&&$sourceVid in [dict get $options calibration_variable_ids]} {
        dict set settings view_pivot [_unitFiniteValue [expr {[dict get $settings output_origin]+[dict get $settings calibration_factor]*([dict get $settings view_pivot]-[dict get $settings input_origin])}]]
        dict set settings calibration_factor 1.0
        dict set settings input_origin 0.0
        dict set settings output_origin 0.0
    }
    set source [dict get $settings source];set destination [_datasetCoordinateSource $target]
    if {[dict get $source unit] ne [dict get $destination unit]} {
        set plan [unitRegistryAffinePlan [dict get $source unit] [dict get $destination unit] [_datasetCoordinateOverride $source]]
        if {![dict get $plan affine]} {error {Nonlinear unit conversion cannot inherit an affine calibration/pivot without an explicit new context}}
        set scale [dict get $plan scale];set offset [dict get $plan offset]
        foreach key {view_pivot input_origin output_origin} {dict set settings $key [_unitFiniteValue [expr {$scale*[dict get $settings $key]+$offset}]]}
    }
    dict set settings source $destination
    set settings [_datasetCoordinateVariable $target $settings]
    return [dict create status inherited settings $settings configured 1]
}
proc ::GX::_datasetCoordinateTransformAdopt {session id record sha} {
    set snapshots [dict get $record snapshots];set manifest [dict get $record manifest];set report [dict get $record report]
    set hasContext 0;set bySource {};set lineage {}
    foreach snapshot $snapshots {
        dict set bySource [dict get $snapshot dataset_id] $snapshot
        if {[dict get $snapshot coordinate_context] ne {}} {set hasContext 1}
        lappend lineage [dict create dataset_id [dict get $snapshot dataset_id] source_sha256 [dict get $snapshot sha256] context [dict get $snapshot coordinate_context]]
    }
    if {!$hasContext&&[dict get $manifest operation] ne "calibrate_variables"} {return}
    set mapped {}
    foreach mapping [dict get $report variable_mapping] {dict lappend mapped [dict get $mapping output_variable_id] $mapping}
    set variables {};set decisions {}
    dict for {vid bindings} $mapped {
        set target [datasetVariableV3ById $id $vid]
        if {[catch {_datasetCoordinateSource $target}]} continue
        set choices {};set configured 0;set reasons {}
        foreach mapping $bindings {
            set sourceId [dict get $mapping source_dataset_id]
            if {![dict exists $bySource $sourceId]} {lappend reasons {Native geometry has no Dataset coordinate context};continue}
            if {[catch {set candidate [_datasetCoordinateTransformCandidate [dict get $bySource $sourceId] $mapping $target $manifest $report]} reason]} {
                lappend reasons $reason;continue
            }
            if {[dict get $candidate configured]} {set configured 1}
            set settings [dict get $candidate settings]
            if {$settings ni $choices} {lappend choices $settings}
        }
        if {[llength $choices]>1} {lappend reasons {Contributing Datasets have conflicting coordinate settings}}
        if {[llength $reasons]} {
            dict set decisions $vid [dict create status not_inherited reason [join [lsort -unique $reasons] {; }] sources $bindings]
        } elseif {$configured&&[llength $choices]==1} {
            dict set variables $vid [lindex $choices 0]
            dict set decisions $vid [dict create status [expr {[dict get $manifest operation] eq "calibrate_variables"&&[dict get [lindex $bindings 0] source_variable_id] in [dict get $manifest options calibration_variable_ids]?"calibration_consumed":"inherited"}] sources $bindings]
        }
    }
    set context [dict create schema_version 1 revision 1 source_sha256 $sha variables $variables]
    _datasetCoordinateValidate $id $context $sha
    _datasetCoordinateWrite $session $id $context
    datasetMetadataUpdate $session $id [dict create transform.source_coordinate_contexts $lineage transform.coordinate_inheritance $decisions]
}
proc ::GX::_datasetCoordinateTransformFinalize {session writer record} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_datasetCoordinateTransformFinalize $session $writer $record]}
    set result [datasetPublicationV2Finalize $writer]
    _datasetCoordinateTransformAdopt $session [dict get $result dataset_id] $record [dict get $result sha256]
    return $result
}
