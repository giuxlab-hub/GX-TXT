# GX-TXT Dataset Variable Schema API v3
# SPDX-License-Identifier: GPL-3.0-or-later
# Additive multidimensional metadata over the stable dataset_id + variable_id
# identity established by API v2.

namespace eval ::GX {
    variable datasetVariableSchemaApiVersion 3
}

proc ::GX::datasetSchemaV3FieldDefaults {} {
    return {
        dtype float64
        rank 1
        shape ""
        dimension_ids row
        coordinate_variable_ids ""
        coordinate_role data
        axis_kind explicit
        axis_origin ""
        axis_step ""
        axis_count ""
        component_ids ""
        group_id ""
    }
}

proc ::GX::datasetSchemaEnsureV3 {session id} {
    variable datasetRegistry
    if {[datasetField $id id ""] eq ""} { error "Unknown dataset: $id" }
    if {[datasetField $id variable_schema_api_version ""] ni {2 3}} {
        datasetSchemaEnsure $session $id
    }
    set count [datasetField $id var_count 0]
    if {![string is integer -strict $count] || $count < 0} { error "Invalid variable count for dataset $id" }
    set rows [datasetField $id row_count ""]
    for {set index 1} {$index <= $count} {incr index} {
        set prefix "var${index}_"
        foreach {field default} [datasetSchemaV3FieldDefaults] {
            if {![info exists datasetRegistry($id,${prefix}$field)]} {
                if {$field eq "dtype" && [datasetField $id ${prefix}value_kind number] eq "text"} { set default string }
                if {$field eq "shape" && [string is integer -strict $rows] && $rows >= 0} { set default $rows }
                set datasetRegistry($id,${prefix}$field) $default
            }
        }
    }
    set datasetRegistry($id,variable_schema_api_version) 3
}

proc ::GX::datasetVariableSchemaV3 {id} {
    variable currentSession
    datasetSchemaEnsureV3 $currentSession $id
    set v2 [datasetVariableSchema $id]
    set out {}
    set index 0
    foreach variable $v2 {
        incr index
        foreach {field default} [datasetSchemaV3FieldDefaults] {
            dict set variable $field [datasetField $id var${index}_$field $default]
        }
        lappend out $variable
    }
    return $out
}

proc ::GX::datasetVariableV3ById {id variableId} {
    foreach variable [datasetVariableSchemaV3 $id] {
        if {[dict get $variable variable_id] eq $variableId} { return $variable }
    }
    error "Dataset $id has no variable_id $variableId"
}

proc ::GX::datasetSchemaV3SplitIds {value} {
    set out {}
    foreach item [split [string map {"," ";"} $value] ";"] {
        set item [string trim $item]
        if {$item ne ""} { lappend out $item }
    }
    return $out
}

proc ::GX::datasetSchemaV3ValidateVariable {datasetId variable} {
    set rank [dict get $variable rank]
    if {![string is integer -strict $rank] || $rank < 0} { error "rank must be an integer >= 0" }
    set shape [datasetSchemaV3SplitIds [dict get $variable shape]]
    if {[llength $shape] != $rank} { error "shape must contain exactly rank dimensions" }
    foreach size $shape { if {![string is integer -strict $size] || $size < 0} { error "shape entries must be integers >= 0" } }
    set dimensions [datasetSchemaV3SplitIds [dict get $variable dimension_ids]]
    if {[llength $dimensions] != $rank} { error "dimension_ids must contain exactly rank IDs" }
    if {[dict get $variable coordinate_role] ni {data coordinate auxiliary}} { error "coordinate_role must be data, coordinate, or auxiliary" }
    if {[dict get $variable axis_kind] ni {explicit uniform none}} { error "axis_kind must be explicit, uniform, or none" }
    if {[dict get $variable axis_kind] eq "uniform"} {
        foreach field {axis_origin axis_step axis_count} {
            set value [dict get $variable $field]
            if {![string is double -strict $value]} { error "$field is required and numeric for a uniform axis" }
        }
        if {[dict get $variable axis_step] == 0.0} { error "axis_step must be non-zero for a uniform axis" }
        if {![string is integer -strict [dict get $variable axis_count]] || [dict get $variable axis_count] < 0} { error "axis_count must be an integer >= 0" }
    }
    set known {}
    foreach item [datasetVariableSchemaV3 $datasetId] { lappend known [dict get $item variable_id] }
    foreach field {coordinate_variable_ids component_ids} {
        foreach related [datasetSchemaV3SplitIds [dict get $variable $field]] {
            if {$related ni $known} { error "$field references unknown variable_id $related" }
        }
    }
}

proc ::GX::datasetVariableSchemaV3Update {id changes} {
    variable datasetRegistry
    variable currentSession
    if {$::GX::DatasetPrivate::activeContext ne {}} {_datasetNamespaceRequireModuleWrite $currentSession [dict get $::GX::DatasetPrivate::activeContext module_id] $id}
    datasetSchemaEnsureV3 $currentSession $id
    set allowed {dtype rank shape dimension_ids coordinate_variable_ids coordinate_role axis_kind axis_origin axis_step axis_count component_ids group_id}
    set slots [dict create]
    set index 0
    foreach variable [datasetVariableSchemaV3 $id] { incr index; dict set slots [dict get $variable variable_id] $index }
    set staged [dict create]
    dict for {variableId fields} $changes {
        if {![dict exists $slots $variableId]} { error "Unknown variable_id $variableId in dataset $id" }
        set variable [datasetVariableV3ById $id $variableId]
        dict for {field value} $fields {
            if {$field ni $allowed} { error "Field $field is not mutable through Dataset Variable Schema API v3" }
            if {[regexp {[\r\n]} $value]} { error "Schema fields must be single-line" }
            dict set variable $field $value
        }
        dict set staged $variableId $variable
    }
    dict for {variableId variable} $staged { datasetSchemaV3ValidateVariable $id $variable }
    dict for {variableId variable} $staged {
        set index [dict get $slots $variableId]
        foreach field $allowed { set datasetRegistry($id,var${index}_$field) [dict get $variable $field] }
    }
    set datasetRegistry($id,variable_schema_api_version) 3
    return [datasetVariableSchemaV3 $id]
}

# One public transaction across the v2 scientific and v3 typed fields.
proc ::GX::datasetVariableSchemaUpdateCombined {id changes} {
    if {![datasetAuthorityActive $::GX::currentSession]} {return [datasetAuthorityTransaction $::GX::currentSession ::GX::datasetVariableSchemaUpdateCombined $id $changes]}
    variable currentSession
    variable datasetRegistry
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {error "Open a Session before editing Dataset schema"}
    if {[catch {dict size $changes}]} {error "Schema changes must be a dictionary keyed by Variable ID"}
    loadDatasetRegistry $currentSession
    if {[datasetField $id id ""] eq ""} {error "Unknown Dataset $id"}
    set v2Fields {enabled canonical unit canonical_unit to_canonical from_canonical display_label semantic_role semantic_source instrument_id instrument_channel value_kind value_format decimal_separator time_origin time_reference}
    set v3Fields {dtype rank shape dimension_ids coordinate_variable_ids coordinate_role axis_kind axis_origin axis_step axis_count component_ids group_id}
    set v2 [dict create];set v3 [dict create]
    dict for {vid fields} $changes {
        datasetVariableV3ById $id $vid
        if {[catch {dict size $fields}]} {error "Changes for $vid must be a dictionary"}
        dict for {field value} $fields {
            if {$field in $v2Fields} {dict set v2 $vid $field $value
            } elseif {$field in $v3Fields} {dict set v3 $vid $field $value
            } else {error "Field $field is not mutable"}
        }
    }
    if {![dict size $v2] && ![dict size $v3]} {return [datasetVariableSchemaV3 $id]}
    # The v3 validator has no disk side effects. Run it against a temporary
    # registry view so malformed dimensions cannot follow a v2 CSV rewrite.
    set prior [array get datasetRegistry]
    if {[dict size $v3]} {
        try {datasetVariableSchemaV3Update $id $v3} finally {
            array unset datasetRegistry *;array set datasetRegistry $prior
        }
    }
    set registryPath [datasetRegistryPath $currentSession]
    set manifestPath [file join $currentSession metadata manifest.ini]
    set canonical [datasetResolvePath $currentSession $id]
    set snapshotBefore [datasetField $id schema_source_snapshot ""]
    set suffix ".schema-combined.[pid].[clock clicks].backup"
    set backups [dict create]
    lassign [_datasetMetadataPath $currentSession $id] metadataRelative metadataPath
    set metadataExisted [file isfile $metadataPath]
    foreach path [list $registryPath $manifestPath $canonical $metadataPath] {
        if {$path ne {} && [_datasetDeletePathWithin $path $currentSession]} {datasetAuthorityEnlist $path}
        if {$path ne "" && [file isfile $path]} {
            file copy -force -- $path "$path$suffix"
            dict set backups $path "$path$suffix"
        }
    }
    set bindingBefore [array get ::GX::moduleBinding]
    set bindingIdBefore [array get ::GX::moduleBindingIdentity]
    set configBefore [array get ::GX::moduleCfg]
    set repeatBefore [array get ::GX::repeatableValue]
    set referenceBefore [array get ::GX::variableReferenceIdentity]
    if {[catch {
        if {[dict size $v2]} {datasetVariableSchemaUpdate $id $v2}
        if {[dict size $v3]} {datasetVariableSchemaV3Update $id $v3}
        saveDatasetRegistry $currentSession
        set result [datasetVariableSchemaV3 $id]
    } failure options]} {
        if {!$metadataExisted} {catch {file delete -force -- $metadataPath}}
        set snapshotAfter [datasetField $id schema_source_snapshot ""]
        dict for {path backup} $backups {catch {file copy -force -- $backup $path}}
        if {$snapshotAfter ne "" && $snapshotAfter ne $snapshotBefore} {
            catch {file delete -- [file join $currentSession $snapshotAfter]}
        }
        array unset datasetRegistry *;array set datasetRegistry $prior
        foreach {name values} [list moduleBinding $bindingBefore moduleBindingIdentity $bindingIdBefore moduleCfg $configBefore repeatableValue $repeatBefore variableReferenceIdentity $referenceBefore] {
            upvar 0 ::GX::$name target
            array unset target *;array set target $values
        }
        dict for {path backup} $backups {catch {file delete -force -- $backup}}
        return -options $options $failure
    }
    dict for {path backup} $backups {catch {file delete -force -- $backup}}
    return $result
}

# CORE provider adapters use an opaque storage locator to bind a stable
# variable_id to a backend object. The locator is intentionally excluded from
# Dataset Variable Schema API v3 results and runtime metadata.
proc ::GX::datasetStorageMapVariable {id variableId locator} {
    variable datasetRegistry
    set index 0
    set current 0
    foreach variable [datasetVariableSchemaV3 $id] {
        incr current
        if {[dict get $variable variable_id] eq $variableId} { set index $current; break }
    }
    if {!$index} { error "Dataset $id has no variable_id $variableId" }
    set datasetRegistry($id,var${index}_storage_locator) $locator
    return $variableId
}

proc ::GX::datasetStorageVariableLocator {id variableId} {
    set index 0
    foreach variable [datasetVariableSchemaV3 $id] {
        incr index
        if {[dict get $variable variable_id] eq $variableId} { return [datasetField $id var${index}_storage_locator ""] }
    }
    error "Dataset $id has no variable_id $variableId"
}
