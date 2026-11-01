# SPDX-License-Identifier: GPL-3.0-or-later
# Invocation presets are ordinary typed canonical Datasets. The Script Registry
# supplies the schema; Publication owns every byte, variable and namespace.
proc ::GX::scriptParameterDatasetApiInfo {} {
    set contracts {}
    foreach {name command arguments description} {
        save ::GX::scriptParameterDatasetSave {session reference supplied datasetId ?label? ?reviewed? ?invocationSchema?} {Committed canonical Dataset identity and revision; no Job submission}
        load ::GX::scriptParameterDatasetLoad {session reference datasetId} {Validated typed parameters and exact Dataset revision SHA and Variable IDs}
    } {
        set parameters {}
        foreach argument $arguments {
            set key [string trim $argument ?]
            set descriptor [dict create type [expr {$key in {supplied reviewed invocationSchema} ? {dictionary} : {string}}] description $key required [expr {$argument eq $key}]]
            if {$argument ne $key} {dict set descriptor default {}}
            dict set parameters $key $descriptor
        }
        dict set contracts $name [dict create command $command arguments $arguments parameters $parameters result [dict create type dictionary description $description] context {Reviewed current Session; existing Script Registry and canonical Dataset authorities}]
    }
    return [dict create api_id SCRIPT_PARAMETER_DATASET_API_v1 api_version 1 authority script_execution host_entrypoint ::GX::scriptParameterDatasetApiInfo operations {save load} host_operation_contracts $contracts script_exposure host_only reason {Invocation review is a trusted host operation; scripts consume ordinary canonical typed Variables and immutable Job context}]
}
proc ::GX::scriptParameterDatasetSchema {metadata} {
    set schema {}
    foreach name [lsort [dict keys [dict get $metadata parameters]]] {
        set descriptor {}
        foreach key [lsort [dict keys [dict get $metadata parameters $name]]] {dict set descriptor $key [dict get $metadata parameters $name $key]}
        dict set schema $name $descriptor
    }
    return $schema
}
proc ::GX::scriptParameterDatasetDtype {descriptor} {
    switch -- [dict get $descriptor type] {
        integer {return int64}
        double - number {return float64}
        boolean {return bool}
        default {return string}
    }
}
proc ::GX::scriptParameterDatasetSave {session reference supplied datasetId {label {}} {reviewed {}} {invocationSchema {}}} {
    if {$session eq {} || $::GX::currentSession eq {} || ![file isdirectory $session] || [file normalize $session] ne [file normalize $::GX::currentSession]} {error {Parameter presets require the reviewed current Session}}
    set metadata [scriptRegistryDescribe $reference $session]
    if {$reviewed ne {}} {
        foreach key {sha256 revision parameters} {
            if {[dict get $metadata $key] ne [dict get $reviewed $key]} {error {Script changed since preset review; reopen Script Runner}}
        }
    }
    set registrySchema [scriptParameterDatasetSchema $metadata]
    set schema [scriptParameterDatasetSchema [dict create parameters [scriptInvocationSchema $metadata $invocationSchema]]]
    set values [scriptExecutionParameters $metadata $supplied $invocationSchema]
    set names [lsort [dict keys $values]]
    set info [dict create script_parameters.schema gxtxt.script_parameters.v1 script_parameters.reference $reference script_parameters.source_sha256 [dict get $metadata sha256] script_parameters.script_revision [dict get $metadata revision] script_parameters.declarations $schema script_parameters.names $names metadata.display_name $label]
    set definition [dict create dataset_id $datasetId contract gxtxt.script_parameters.v1 storage csv expected_rows 1 structured_metadata $info source $reference provenance "Script invocation preset; SHA-256 [dict get $metadata sha256]; revision [dict get $metadata revision]" replace_owned 0]
    dict set definition structured_metadata script_parameters.registry_declarations $registrySchema
    dict set definition structured_metadata script_parameters.invocation_declarations $invocationSchema
    set writer {}
    try {
        set plan [datasetPublicationV2Prepare $session [scriptAnalysisModule [dict get $metadata language]] $definition]
        set writer [datasetPublicationV2OpenWriter $plan]
        datasetPublicationV2DeclareDimension $writer preset_row 0 {extendible 1}
        set row {}
        foreach name $names {
            set variable p_$name
            datasetPublicationV2DeclareVariable $writer $variable [dict create name $name dtype [scriptParameterDatasetDtype [dict get $schema $name]] rank 1 dimension_ids preset_row semantic_role script_parameter]
            dict set row $variable [list [dict get $values $name]]
        }
        # A permanent marker preserves one physical CSV row even when the only
        # parameter is an empty/whitespace string. Readers skip blank lines.
        datasetPublicationV2DeclareVariable $writer preset_marker [dict create name preset_marker dtype bool rank 1 dimension_ids preset_row]
        dict set row preset_marker 1
        datasetPublicationV2Append $writer preset_row $row
        set current [scriptRegistryDescribe $reference $session]
        foreach key {sha256 revision parameters} {
            if {[dict get $current $key] ne [dict get $metadata $key]} {error {Script changed while preparing parameter Dataset}}
        }
        set result [datasetPublicationV2Finalize $writer]
    } on error {reason options} {
        if {$writer ne {}} {catch {datasetPublicationV2Abort $writer}}
        return -options $options $reason
    }
    return [dict merge $result [dict create dataset_id $datasetId revision [datasetRevisionToken $datasetId $session]]]
}
proc ::GX::scriptParameterDatasetLoad {session reference datasetId} {
    if {$session eq {} || $::GX::currentSession eq {} || ![file isdirectory $session] || [file normalize $session] ne [file normalize $::GX::currentSession]} {error {Parameter presets require the reviewed current Session}}
    # Read one persisted descriptor/schema projection, including when another
    # process published since this GUI last refreshed its Dataset Catalog.
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::scriptParameterDatasetLoad $session $reference $datasetId]}
    if {[datasetField $datasetId contract {}] ne {gxtxt.script_parameters.v1}} {error {Select a compatible Script parameter Dataset}}
    set revision [datasetRevisionToken $datasetId $session]
    set path [datasetResolvePath $session $datasetId]
    set expected [datasetField $datasetId canonical_sha256 {}]
    if {$expected eq {} || ![file isfile $path] || [sha256File $path] ne $expected} {error {Parameter Dataset payload integrity differs}}
    set metadata [scriptRegistryDescribe $reference $session]
    set info [datasetMetadataRead $session $datasetId]
    set invocationSchema [datasetPublicationV2DictDefault $info script_parameters.invocation_declarations {}]
    set effectiveSchema [scriptParameterDatasetSchema [dict create parameters [scriptInvocationSchema $metadata $invocationSchema]]]
    set declarationField [expr {[dict exists $info script_parameters.registry_declarations] ? {registry_declarations} : {declarations}}]
    foreach {field value} [list schema gxtxt.script_parameters.v1 reference $reference source_sha256 [dict get $metadata sha256] script_revision [dict get $metadata revision] $declarationField [scriptParameterDatasetSchema $metadata]] {
        if {![dict exists $info script_parameters.$field] || [dict get $info script_parameters.$field] ne $value} {error "Parameter Dataset has incompatible $field; save a new preset for the current Script"}
    }
    set names [dict get $info script_parameters.names]
    if {[llength [lsort -unique $names]] != [llength $names]} {error {Parameter Dataset has duplicate names}}
    set schema $effectiveSchema
    if {[dict get $info script_parameters.declarations] ne $schema} {error {Parameter Dataset effective declarations differ}}
    set variables {};foreach name $names {
        if {![dict exists $schema $name]} {error "Unexpected preset parameter '$name'"}
        lappend variables p_$name
    }
    lappend variables preset_marker
    set access [datasetAccessOpen $session $datasetId]
    try {
        set actual {};foreach variable [dict get [datasetAccessMetadata $access] variables] {
            set id [dict get $variable variable_id];lappend actual $id
            set name [string range $id 2 end]
            set dtype [expr {$id eq {preset_marker} ? {bool} : ([dict exists $schema $name] ? [scriptParameterDatasetDtype [dict get $schema $name]] : {})}]
            if {[dict get $variable dtype] ne $dtype || [dict get $variable rank] != 1 || [dict get $variable shape] ne {1}} {error "Preset Variable '$id' has incompatible type or shape"}
        }
        if {[lsort $actual] ne [lsort $variables]} {error {Parameter Dataset has missing or extra Variables}}
        set raw [datasetAccessReadRange $access $variables 0 1]
    } finally {datasetAccessClose $access}
    if {[dict get $raw preset_marker count] != 1 || [lindex [dict get $raw preset_marker values] 0] ni {1 true}} {error {Parameter Dataset row marker is invalid}}
    set supplied {};foreach name $names {dict set supplied $name [lindex [dict get $raw p_$name values] 0]}
    set normalized [scriptExecutionParameters $metadata $supplied $invocationSchema]
    if {[lsort [dict keys $normalized]] ne [lsort $names]} {error {Parameter Dataset is missing effective parameter values}}
    if {[datasetRevisionToken $datasetId $session] ne $revision || [sha256File $path] ne $expected} {error {Parameter Dataset changed while loading}}
    return [dict create dataset_id $datasetId revision $revision sha256 $expected variable_ids $variables parameters $normalized invocation_parameters $invocationSchema]
}
