# GX-TXT Dataset Publication API v2
# SPDX-License-Identifier: GPL-3.0-or-later
# Backend-neutral, transactional dataset creation over Dataset Variable Schema v3.

namespace eval ::GX {
    variable datasetPublicationApiV2Version 2
    variable datasetWriterProviderCommand
    variable datasetWriterProviderCaps
    variable datasetWriterProviderVersion
    variable datasetPublicationPlan
    variable datasetPublicationPlanCounter 0
    variable datasetPublicationWriter
    variable datasetPublicationWriterCounter 0
    variable csvWriterState
    variable csvWriterCounter 0
    variable hdf5WriterState
    variable hdf5WriterCounter 0
    array set datasetWriterProviderCommand {}
    array set datasetWriterProviderCaps {}
    array set datasetWriterProviderVersion {}
    array set datasetPublicationPlan {}
    array set datasetPublicationWriter {}
    array set csvWriterState {}
    array set hdf5WriterState {}
}

proc ::GX::datasetWriterCapabilityNames {} {
    return {complete_variable range_write append_write hyperslab_write multidimensional groups implicit_axis typed_numeric managed_binary_write sequential_chunks human_readable}
}

proc ::GX::datasetWriterProviderRegister {provider commandPrefix capabilities version} {
    variable datasetWriterProviderCommand
    variable datasetWriterProviderCaps
    variable datasetWriterProviderVersion
    set provider [string tolower [string trim $provider]]
    if {![regexp {^[a-z][a-z0-9_.-]*$} $provider]} { error "Invalid dataset writer provider ID: $provider" }
    if {![llength $commandPrefix]} { error "Dataset writer provider $provider requires a command" }
    set normalized [dict create]
    foreach name [datasetWriterCapabilityNames] { dict set normalized $name 0 }
    dict for {name value} $capabilities {
        if {$name ni [datasetWriterCapabilityNames]} { error "Unknown dataset writer capability: $name" }
        dict set normalized $name [expr {$value ? 1 : 0}]
    }
    set datasetWriterProviderCommand($provider) $commandPrefix
    set datasetWriterProviderCaps($provider) $normalized
    set datasetWriterProviderVersion($provider) $version
    return $provider
}

proc ::GX::datasetWriterProviderIds {} {
    variable datasetWriterProviderCommand
    return [lsort [array names datasetWriterProviderCommand]]
}

proc ::GX::datasetWriterProviderCapabilities {provider} {
    variable datasetWriterProviderCaps
    set provider [string tolower [string trim $provider]]
    if {![info exists datasetWriterProviderCaps($provider)]} { error "Dataset writer provider '$provider' is unavailable" }
    return $datasetWriterProviderCaps($provider)
}

proc ::GX::datasetPublicationV2DictDefault {dictionary key default} {
    return [expr {[dict exists $dictionary $key] ? [dict get $dictionary $key] : $default}]
}

proc ::GX::datasetPublicationV2ValidateId {kind value} {
    set value [string trim $value]
    if {$kind in {dataset source_dataset}} {
        if {![regexp {^[A-Za-z0-9_.-]+$} $value] || $value in {. ..}} { error "Invalid $kind ID '$value'" }
    } elseif {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $value]} {
        error "Invalid $kind ID '$value'"
    }
    return $value
}

# A supplied public identity is authoritative. Only an absent identity may be
# generated; an invalid supplied identity must never be sanitized or replaced.
proc ::GX::datasetPublicationV2RequestedId {requested {prefix dataset}} {
    set requested [string trim $requested]
    if {$requested ne ""} {return [datasetPublicationV2ValidateId dataset $requested]}
    set prefix [datasetPublicationV2ValidateId dataset $prefix]
    return "${prefix}_[pid]_[clock microseconds]"
}

proc ::GX::datasetPublicationV2Shape {value} {
    set out [expr {[llength $value] > 1 && [string first {;} $value] < 0 && [string first , $value] < 0 ? $value : [datasetSchemaV3SplitIds $value]}]
    foreach size $out { if {![string is integer -strict $size] || $size < 0} { error "Shape entries must be integers >= 0" } }
    return $out
}

proc ::GX::datasetPublicationV2ElementCount {shape} {
    set count 1
    foreach size $shape { set count [expr {$count*$size}] }
    return $count
}

proc ::GX::datasetPublicationV2SafeRelative {path} {
    set path [string trim $path]
    if {$path eq "" || [file pathtype $path] eq "absolute"} { error "Publication target must be a relative session path" }
    foreach part [file split $path] { if {$part eq ".."} { error "Publication target may not contain '..'" } }
    return $path
}

proc ::GX::datasetPublicationV2SelectProvider_before_storage_policy {request required preferred} {
    variable datasetWriterProviderCommand
    set request [string tolower [string trim $request]]
    if {$request eq ""} { set request auto }
    foreach capability [concat $required $preferred] {
        if {$capability ni [datasetWriterCapabilityNames]} { error "Unknown dataset writer capability: $capability" }
    }
    if {$request ne "auto"} {
        if {![info exists datasetWriterProviderCommand($request)]} { error "Requested dataset writer backend '$request' is unavailable" }
        set candidates [list $request]
    } else {
        set advanced {append_write hyperslab_write multidimensional groups typed_numeric}
        set needsAdvanced 0
        foreach name $required { if {$name in $advanced} { set needsAdvanced 1 } }
        set candidates [expr {$needsAdvanced ? {hdf5 csv} : {csv hdf5}}]
    }
    set available {}
    foreach provider $candidates {
        if {![info exists datasetWriterProviderCommand($provider)]} continue
        set caps [datasetWriterProviderCapabilities $provider]
        set suitable 1
        foreach name $required { if {![dict get $caps $name]} { set suitable 0; break } }
        if {$suitable} { lappend available $provider }
    }
    if {![llength $available]} { error "No dataset writer provider satisfies required capabilities: [join $required {, }]" }
    set best [lindex $available 0]; set bestScore -1
    foreach provider $available {
        set caps [datasetWriterProviderCapabilities $provider]; set score 0
        foreach name $preferred { if {[dict get $caps $name]} { incr score } }
        if {$score > $bestScore} { set best $provider; set bestScore $score }
    }
    set reason [expr {$request eq "auto" ? "deterministic auto selection: required capabilities satisfied; preferred score $bestScore" : "explicit storage request"}]
    return [dict create provider $best reason $reason]
}

proc ::GX::datasetPublicationV2Prepare {session moduleId definition} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetPublicationV2Prepare $session $moduleId $definition]}
    variable currentSession
    variable datasetPublicationPlan
    variable datasetPublicationPlanCounter
    variable datasetWriterProviderVersion
    if {$::GX::DatasetPrivate::activeContext ne {}} {set moduleId [dict get $::GX::DatasetPrivate::activeContext module_id]}
    set session [file normalize $session]
    if {![file isdirectory $session]} { error "Publication session directory does not exist: $session" }
    set moduleId [datasetPublicationV2ValidateId module $moduleId]
    foreach key {dataset_id contract} { if {![dict exists $definition $key] || [string trim [dict get $definition $key]] eq ""} { error "Publication definition is missing '$key'" } }
    set datasetId [datasetPublicationV2ValidateId dataset [dict get $definition dataset_id]]
    set contract [string trim [dict get $definition contract]]
    ::GX::StatisticsV1::validatePublication $moduleId $definition
    if {[dict exists $definition structured_metadata]} {
        if {[catch {dict size [dict get $definition structured_metadata]}]} {error "structured_metadata must be a dictionary"}
        dict for {key value} [dict get $definition structured_metadata] {_datasetMetadataUserKey $key}
        ::GX::StatisticsV1::validateMetadata [dict get $definition structured_metadata]
        _datasetMetadataPortableSerialize [dict get $definition structured_metadata]
    }
    set currentSession $session
    loadDatasetRegistry $session
    set replaceOwned [expr {[dict exists $definition replace_owned] && [string is true -strict [dict get $definition replace_owned]]}]
    set existing [datasetField $datasetId id ""]
    if {$existing ne ""} {
        if {[string is true -strict [datasetField $datasetId immutable 0]]} {error "Dataset '$datasetId' is immutable"}
        if {!$replaceOwned} { error "Dataset ID '$datasetId' already exists" }
        set owner [datasetField $datasetId source_module [datasetField $datasetId producer_module ""]]
        set publicationVersion [datasetField $datasetId publication_api_version ""]
        if {$owner ne $moduleId || $publicationVersion ne "2"} {
            error "Dataset ID '$datasetId' already exists and is not owned by this module through Dataset Publication API v2"
        }
    }
    set assignedNamespace [_datasetPublicationNamespace $session $moduleId $definition]
    if {$existing ne {}} {_datasetNamespaceRequireModuleWrite $session $moduleId $datasetId}
    dict set definition dataset_namespace $assignedNamespace
    set requested [datasetPublicationV2DictDefault $definition storage auto]
    set required [datasetPublicationV2DictDefault $definition capabilities_required {}]
    set preferred [datasetPublicationV2DictDefault $definition capabilities_preferred {}]
    set selection [datasetPublicationV2SelectProvider $requested $required $preferred $definition]
    if {$existing ne {} && [string tolower [string trim $requested]] in {{} auto}} {
        # Replacement retains the canonical provider, not the new-output size
        # policy. A provider change requires a separately authorized migration.
        set retained [datasetField $datasetId storage_provider [datasetField $datasetId format {}]]
        if {$retained eq "h5"} {set retained hdf5}
        if {[catch {set selection [datasetPublicationV2SelectProvider $retained $required $preferred $definition]} failure]} {
            error "Owned Dataset '$datasetId' cannot retain provider '$retained': $failure. Explicit storage migration is required; the existing Dataset has not changed."
        }
        dict set selection reason "automatic same-owner replacement retains canonical provider $retained"
    }
    set provider [dict get $selection provider]
    set extension [expr {$provider eq "hdf5" ? "h5" : "csv"}]
    # An owned Dataset may have been renamed while its immutable payload path
    # stayed in place. Reuse that canonical path for replacement by default.
    set defaultTarget [expr {$existing ne "" ? [datasetField $datasetId path ""] : [file join datasets publications "${datasetId}.${extension}"]}]
    set target [datasetPublicationV2DictDefault $definition relative_path $defaultTarget]
    set target [datasetPublicationV2SafeRelative $target]
    if {[string tolower [file extension $target]] ni [expr {$provider eq "hdf5" ? {.h5 .hdf5} : {.csv}}]} { error "Publication target extension is incompatible with provider $provider" }
    set final [file normalize [file join $session $target]]
    if {[string first "${session}/" "${final}/"] != 0} { error "Publication target escapes the session" }
    if {$existing ne ""} {
        set existingTarget [datasetField $datasetId path ""]
        if {$existingTarget ne $target} { error "Owned Dataset replacement must retain its existing publication target: $existingTarget" }
    } elseif {[file exists $final]} {
        error "Publication target already exists: $target"
    }
    file mkdir [file dirname $final]
    set plan "publication-plan#[incr datasetPublicationPlanCounter]"
    foreach {key value} [list status prepared session $session module_id $moduleId dataset_id $datasetId contract $contract requested_provider $requested provider $provider provider_version $datasetWriterProviderVersion($provider) selection_reason [dict get $selection reason] required $required preferred $preferred target_relative $target final_path $final replace_owned $replaceOwned definition $definition] {
        set datasetPublicationPlan($plan,$key) $value
    }
    set datasetPublicationPlan($plan,operation) [expr {$existing eq {} ? "creating" : "replacing"}]
    set datasetPublicationPlan($plan,expected_revision) [expr {$existing eq {} ? {} : [datasetRevisionToken $datasetId $session]}]
    return $plan
}

proc ::GX::datasetPublicationV2RequirePlan {plan} {
    variable datasetPublicationPlan
    if {![info exists datasetPublicationPlan($plan,status)]} { error "Unknown publication plan: $plan" }
}
proc ::GX::datasetPublicationV2PlanInfo {plan} {
    variable datasetPublicationPlan
    datasetPublicationV2RequirePlan $plan
    set result [dict create]
    foreach key {status module_id dataset_id contract requested_provider provider provider_version selection_reason required preferred replace_owned operation} {
        dict set result $key $datasetPublicationPlan($plan,$key)
    }
    return $result
}
proc ::GX::datasetPublicationV2SetPlanMetadata {plan metadata} {
    variable datasetPublicationPlan
    datasetPublicationV2RequirePlan $plan
    if {$datasetPublicationPlan($plan,status) ne "prepared"} {error "Publication plan metadata is immutable after opening a writer"}
    dict for {key value} $metadata {_datasetMetadataUserKey $key}
    ::GX::StatisticsV1::validatePublication $datasetPublicationPlan($plan,module_id) [dict create structured_metadata $metadata]
    _datasetMetadataPortableSerialize $metadata
    dict set datasetPublicationPlan($plan,definition) structured_metadata $metadata
}

proc ::GX::datasetPublicationV2OpenWriter {plan} {
    variable datasetPublicationPlan
    variable datasetPublicationWriter
    variable datasetPublicationWriterCounter
    variable datasetWriterProviderCommand
    datasetPublicationV2RequirePlan $plan
    if {$datasetPublicationPlan($plan,status) ne "prepared"} { error "Publication plan is not available for opening" }
    set final $datasetPublicationPlan($plan,final_path)
    set temp [file join [file dirname $final] ".[file tail $final].[pid].[clock clicks].partial"]
    if {[info commands ::GX::resourceManagementObserve] ne {}} {
        set options [dict create category temporary session $datasetPublicationPlan($plan,session) recovery_required 1 lifetime publication owner_pid [pid]]
        if {[info exists ::env(GXTXT_JOB_ID)]} {dict set options job $::env(GXTXT_JOB_ID)}
        catch {resourceManagementObserve $temp dataset_publication $options}
    }
    datasetPublicationStageTrack $datasetPublicationPlan($plan,session) $temp
    set provider $datasetPublicationPlan($plan,provider)
    set context [dict create temp_path $temp dataset_id $datasetPublicationPlan($plan,dataset_id) contract $datasetPublicationPlan($plan,contract)]
    if {[catch {set providerToken [uplevel #0 [list {*}$datasetWriterProviderCommand($provider) open {} $context]]} failure options]} {
        catch {file delete -force -- $temp}
        catch {datasetPublicationStageTrack $datasetPublicationPlan($plan,session) $temp {} 1}
        return -options $options $failure
    }
    set worker {}
    if {$provider eq "hdf5"} {set worker $::GX::hdf5WriterState($providerToken,pid)}
    datasetPublicationStageTrack $datasetPublicationPlan($plan,session) $temp $worker
    set writer "publication-writer#[incr datasetPublicationWriterCounter]"
    foreach {key value} [list status open plan $plan provider $provider provider_token $providerToken temp_path $temp dimension_ids {} variable_ids {}] { set datasetPublicationWriter($writer,$key) $value }
    set datasetPublicationPlan($plan,status) open
    return $writer
}

proc ::GX::datasetPublicationV2RequireWriter {writer} {
    variable datasetPublicationWriter
    if {![info exists datasetPublicationWriter($writer,status)]} { error "Unknown publication writer: $writer" }
    if {$datasetPublicationWriter($writer,status) ne "open"} { error "Publication writer is $datasetPublicationWriter($writer,status)" }
}

proc ::GX::datasetPublicationV2ProviderCall {writer operation args} {
    variable datasetPublicationWriter
    variable datasetWriterProviderCommand
    datasetPublicationV2RequireWriter $writer
    set provider $datasetPublicationWriter($writer,provider)
    if {[catch {set result [uplevel #0 [list {*}$datasetWriterProviderCommand($provider) $operation $datasetPublicationWriter($writer,provider_token) {*}$args]]} failure options]} {
        set datasetPublicationWriter($writer,status) failed
        if {$provider eq "hdf5" && ([string match -nocase {*channel*} $failure] || [string match -nocase {*broken pipe*} $failure])} {
            set failure "HDF5 writer worker terminated unexpectedly: $failure"
            dict set options -errorinfo $failure
        }
        return -options $options $failure
    }
    return $result
}

proc ::GX::datasetPublicationV2DeclareDimension {writer dimensionId size {options {}}} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    set dimensionId [datasetPublicationV2ValidateId dimension $dimensionId]
    if {$dimensionId in $datasetPublicationWriter($writer,dimension_ids)} { error "Duplicate dimension_id $dimensionId" }
    if {![string is integer -strict $size] || $size < 0} { error "Dimension size must be an integer >= 0" }
    set extendible [expr {[datasetPublicationV2DictDefault $options extendible 0] ? 1 : 0}]
    if {!$extendible && $size == 0 && ![datasetPublicationV2DictDefault $options allow_empty 1]} { error "Fixed dimension may not be empty" }
    lappend datasetPublicationWriter($writer,dimension_ids) $dimensionId
    set datasetPublicationWriter($writer,dimension,$dimensionId) [dict create size $size initial_size $size extendible $extendible]
    return $dimensionId
}

proc ::GX::datasetPublicationV2DeclareVariable {writer variableId spec} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    set variableId [datasetPublicationV2ValidateId variable $variableId]
    if {$variableId in $datasetPublicationWriter($writer,variable_ids)} { error "Duplicate variable_id $variableId" }
    set dimensionIds [datasetSchemaV3SplitIds [datasetPublicationV2DictDefault $spec dimension_ids ""]]
    set rank [datasetPublicationV2DictDefault $spec rank [llength $dimensionIds]]
    if {![string is integer -strict $rank] || $rank < 0 || [llength $dimensionIds] != $rank} { error "Variable $variableId has an invalid rank/dimension_ids combination" }
    set shape {}; set maxshape {}
    foreach dimensionId $dimensionIds {
        if {$dimensionId ni $datasetPublicationWriter($writer,dimension_ids)} { error "Variable $variableId references unknown dimension_id $dimensionId" }
        set dim $datasetPublicationWriter($writer,dimension,$dimensionId)
        lappend shape [dict get $dim size]
        lappend maxshape [expr {[dict get $dim extendible] ? "*" : [dict get $dim size]}]
    }
    if {[dict exists $spec shape] && [datasetPublicationV2Shape [dict get $spec shape]] ne $shape} { error "Variable $variableId shape contradicts its dimensions" }
    set dtype [string tolower [datasetPublicationV2DictDefault $spec dtype float64]]
    if {$dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool string}} { error "Unsupported dtype '$dtype'" }
    set axisKind [datasetPublicationV2DictDefault $spec axis_kind explicit]
    set coordinateRole [datasetPublicationV2DictDefault $spec coordinate_role data]
    if {$axisKind ni {explicit uniform none} || $coordinateRole ni {data coordinate auxiliary}} { error "Invalid coordinate metadata for $variableId" }
    if {$axisKind eq "uniform"} {
        if {$rank != 1 || $coordinateRole ne "coordinate"} { error "Implicit uniform coordinate $variableId must be a rank-1 coordinate" }
        foreach field {axis_origin axis_step} { if {![string is double -strict [datasetPublicationV2DictDefault $spec $field ""]]} { error "$field is required and numeric for uniform coordinate $variableId" } }
        if {[datasetPublicationV2DictDefault $spec axis_step 0] == 0.0} { error "axis_step must be non-zero" }
    }
    set normalized [dict create variable_id $variableId name [datasetPublicationV2DictDefault $spec name $variableId] canonical [datasetPublicationV2DictDefault $spec name $variableId] dtype $dtype rank $rank shape [join $shape {;}] maxshape [join $maxshape {;}] dimension_ids [join $dimensionIds {;}] coordinate_variable_ids [datasetPublicationV2DictDefault $spec coordinate_variable_ids ""] coordinate_role $coordinateRole axis_kind $axisKind axis_origin [datasetPublicationV2DictDefault $spec axis_origin ""] axis_step [datasetPublicationV2DictDefault $spec axis_step ""] axis_count [expr {$rank == 1 ? [lindex $shape 0] : ""}] component_ids [datasetPublicationV2DictDefault $spec component_ids ""] group_id [datasetPublicationV2DictDefault $spec group_id ""] unit [datasetPublicationV2DictDefault $spec unit ""] semantic_role [datasetPublicationV2DictDefault $spec semantic_role ""] value_kind [expr {$dtype eq "string" ? "text" : "number"}] chunks [datasetPublicationV2DictDefault $spec chunks ""]]
    foreach field {display_label semantic_source value_format decimal_separator canonical_unit to_canonical from_canonical time_origin time_reference instrument_id instrument_channel} {
        set default ""
        if {$field eq "decimal_separator"} {set default .}
        if {$field eq "time_reference"} {set default elapsed}
        if {$field eq "semantic_source"} {set default [expr {[dict get $normalized semantic_role] ne "" ? "plugin" : "default"}]}
        dict set normalized $field [datasetPublicationV2DictDefault $spec $field $default]
    }
    if {[dict get $normalized decimal_separator] ni {. ,}} {error "Invalid decimal_separator for $variableId"}
    if {[dict get $normalized time_reference] ni {elapsed absolute}} {error "Invalid time_reference for $variableId"}
    if {[dict get $normalized semantic_source] ni {user importer plugin inferred default}} {error "Invalid semantic_source for $variableId"}
    if {[dict exists $spec value_kind]} {dict set normalized value_kind [dict get $spec value_kind]}
    if {[dict get $normalized value_kind] ni {number text elapsed_time}} {error "Invalid value_kind for $variableId"}
    if {$dtype eq "string" && [dict get $normalized value_kind] ne "text"} {error "String variable $variableId requires text value_kind"}
    if {$dtype ne "string" && [dict get $normalized value_kind] eq "text"} {error "Numeric variable $variableId cannot use text value_kind"}
    foreach field {to_canonical from_canonical} {
        if {[dict get $normalized $field] ne ""} {unitFormulaValidate [dict get $normalized $field]}
    }
    if {[dict get $normalized canonical_unit] ne "" &&
        ([dict get $normalized to_canonical] eq "" || [dict get $normalized from_canonical] eq "")} {
        error "canonical_unit for $variableId requires both conversion formulas"
    }
    if {[dict get $normalized canonical_unit] eq "" &&
        ([dict get $normalized to_canonical] ne "" || [dict get $normalized from_canonical] ne "")} {
        error "conversion formulas for $variableId require canonical_unit"
    }
    if {[dict get $normalized value_kind] eq "elapsed_time" &&
        ([dict get $normalized value_format] ne "hms" || [dict get $normalized unit] ni {s min h})} {
        error "Elapsed-time variable $variableId requires HMS format and unit s, min or h"
    }
    if {[dict get $normalized value_kind] ne "elapsed_time" && [dict get $normalized value_format] ne ""} {
        error "value_format for $variableId requires elapsed_time"
    }
    dict for {field value} $normalized {
        if {[regexp {[\r\n]} $value]} {error "Variable $variableId field $field must be single-line"}
    }
    if {[dict get $normalized semantic_role] ne "" && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} [dict get $normalized semantic_role]]} {
        error "Invalid semantic_role for $variableId"
    }
    set caps [datasetWriterProviderCapabilities $datasetPublicationWriter($writer,provider)]
    if {$rank > 1 && ![dict get $caps multidimensional]} { error "Provider $datasetPublicationWriter($writer,provider) does not support multidimensional variables" }
    if {[dict get $normalized group_id] ne "" && ![dict get $caps groups]} { error "Provider $datasetPublicationWriter($writer,provider) does not support logical groups" }
    if {$axisKind eq "uniform" && ![dict get $caps implicit_axis]} { error "Provider $datasetPublicationWriter($writer,provider) does not support implicit axes" }
    set locator [datasetPublicationV2ProviderCall $writer declare_variable $normalized]
    dict set normalized storage_locator $locator
    lappend datasetPublicationWriter($writer,variable_ids) $variableId
    set datasetPublicationWriter($writer,variable,$variableId) $normalized
    return $variableId
}

proc ::GX::datasetPublicationV2DeclareUniformCoordinate {writer variableId dimensionId origin step {spec {}}} {
    dict set spec dimension_ids $dimensionId
    dict set spec rank 1
    dict set spec coordinate_role coordinate
    dict set spec axis_kind uniform
    dict set spec axis_origin $origin
    dict set spec axis_step $step
    return [datasetPublicationV2DeclareVariable $writer $variableId $spec]
}

proc ::GX::datasetPublicationV2IsBinaryBlock {values} {
    return [expr {![catch {dict get $values __gxtxt_binary_block} marker] && $marker eq "1"}]
}

proc ::GX::datasetPublicationV2IsResource {values} {
    return [expr {![catch {dict get $values __gxtxt_binary_resource} marker] && $marker eq "1"}]
}
proc ::GX::datasetPublicationV2WriterCapabilities {writer} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    return [datasetWriterProviderCapabilities $datasetPublicationWriter($writer,provider)]
}
proc ::GX::datasetPublicationV2ValidateResource {values} {
    set count [datasetPublicationV2ElementCount [datasetPublicationV2Shape [dict get $values shape]]]
    set resource [datasetBinaryResourceValidate [dict get $values resource] $count]
    if {![info exists ::env(GXTXT_BRIDGE_WORKSPACE)] || [file normalize [dict get $resource resource_root]] ne [file normalize $::env(GXTXT_BRIDGE_WORKSPACE)]} {
        error {Publication resource is outside its delegated execution scope}
    }
    return $resource
}
proc ::GX::datasetPublicationV2ResourceFields {values} {
    set r [datasetPublicationV2ValidateResource $values]
    set fields {}
    foreach key {version dtype endian order shape count byte_count resource_id resource_root} {lappend fields [datasetB64Encode [dict get $r $key]]}
    return [join $fields \t]
}

proc ::GX::datasetPublicationV2PayloadCount {values} {
    if {[datasetPublicationV2IsBinaryBlock $values] || [datasetPublicationV2IsResource $values]} {
        return [datasetPublicationV2ElementCount [datasetPublicationV2Shape [dict get $values shape]]]
    }
    return [llength $values]
}

proc ::GX::datasetPublicationV2ValidateBinaryBlock {variable values {expectedShape ""}} {
    foreach key {dtype endian shape base64} { if {![dict exists $values $key]} { error "Binary block is missing '$key'" } }
    set dtype [string tolower [dict get $values dtype]]
    if {$dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool}} { error "Unsupported binary transport dtype '$dtype'" }
    if {[dict get $variable dtype] eq "string"} { error "Binary numeric block is incompatible with dtype string" }
    set endian [string tolower [dict get $values endian]]
    if {$endian ni {little big}} { error "Unsupported binary transport endian '$endian'" }
    set shape [datasetPublicationV2Shape [dict get $values shape]]
    if {$expectedShape ne "" && $shape ne $expectedShape} { error "Binary block shape mismatch: expected [join $expectedShape {;}], received [join $shape {;}]" }
    set widths [dict create bool 1 int8 1 uint8 1 int16 2 uint16 2 int32 4 uint32 4 float32 4 int64 8 uint64 8 float64 8]
    set byteCount [expr {[datasetPublicationV2ElementCount $shape]*[dict get $widths $dtype]}]
    set encoded [dict get $values base64]
    set encodedLength [expr {(($byteCount+2)/3)*4}]
    if {[string length $encoded] != $encodedLength || [regexp {[^A-Za-z0-9+/=]} $encoded]} { error "Invalid Base64 binary block length or alphabet" }
    set padding [expr {(3-($byteCount%3))%3}]
    if {$padding} {
        set paddingStart [expr {[string length $encoded]-$padding}]
        if {[string range $encoded $paddingStart end] ne [string repeat = $padding] || [string first = [string range $encoded 0 [expr {$paddingStart-1}]]] >= 0} { error "Invalid Base64 binary block padding" }
    } elseif {[string first = $encoded] >= 0} { error "Invalid Base64 binary block padding" }
    return $byteCount
}

proc ::GX::datasetPublicationV2ValuesPayload {shape values} {
    set expected [datasetPublicationV2ElementCount $shape]
    set received [datasetPublicationV2PayloadCount $values]
    if {$received != $expected} { error "Value count mismatch: expected $expected, received $received" }
    if {[datasetPublicationV2IsBinaryBlock $values] || [datasetPublicationV2IsResource $values]} {
        set blockShape [datasetPublicationV2Shape [dict get $values shape]]
        if {$blockShape ne $shape} { error "Binary block shape mismatch: expected [join $shape {;}], received [join $blockShape {;}]" }
    }
    return [dict create shape $shape values $values]
}

proc ::GX::datasetPublicationV2ValidateTypedValues {variable values} {
    if {[datasetPublicationV2IsResource $values]} {
        datasetPublicationV2ValidateResource $values
        if {[dict get $variable dtype] eq "string"} {error {Numeric resource cannot write a string variable}}
        return
    }
    if {[datasetPublicationV2IsBinaryBlock $values]} { datasetPublicationV2ValidateBinaryBlock $variable $values; return }
    set dtype [dict get $variable dtype]
    if {$dtype eq "string"} { return }
    set bounds [dict create int8 {-128 127} int16 {-32768 32767} int32 {-2147483648 2147483647} int64 {-9223372036854775808 9223372036854775807} uint8 {0 255} uint16 {0 65535} uint32 {0 4294967295} uint64 {0 18446744073709551615}]
    foreach value $values {
        if {$dtype eq "bool"} {
            if {[string tolower $value] ni {0 1 false true}} { error "Value '$value' is incompatible with dtype $dtype" }
        } elseif {[dict exists $bounds $dtype]} {
            if {![string is entier -strict $value]} { error "Value '$value' is incompatible with dtype $dtype" }
            lassign [dict get $bounds $dtype] minimum maximum
            if {$value < $minimum || $value > $maximum} { error "Value '$value' is outside dtype $dtype" }
        } elseif {![string is double -strict $value]} {
            error "Value '$value' is incompatible with dtype $dtype"
        }
    }
}

proc ::GX::datasetPublicationV2MaterializeBinaryBlock {variable values} {
    datasetPublicationV2ValidateBinaryBlock $variable $values
    set raw [binary decode base64 [dict get $values base64]]
    set dtype [dict get $values dtype]; set endian [dict get $values endian]
    set little [expr {$endian eq "little"}]
    switch -- $dtype {
        bool - uint8 { binary scan $raw cu* out }
        int8 { binary scan $raw c* out }
        int16 - uint16 { binary scan $raw [expr {$little ? "s*" : "S*"}] out }
        int32 - uint32 { binary scan $raw [expr {$little ? "i*" : "I*"}] out }
        int64 - uint64 { binary scan $raw [expr {$little ? "w*" : "W*"}] out }
        float32 { binary scan $raw [expr {$little ? "r*" : "R*"}] out }
        float64 { binary scan $raw [expr {$little ? "q*" : "Q*"}] out }
        default { error "Unsupported binary transport dtype '$dtype'" }
    }
    if {$dtype in {uint16 uint32 uint64}} {
        set modulus [dict get [dict create uint16 65536 uint32 4294967296 uint64 18446744073709551616] $dtype]
        set converted {}; foreach value $out { lappend converted [expr {$value < 0 ? $value+$modulus : $value}] }; set out $converted
    }
    datasetPublicationV2ValidateTypedValues $variable $out
    set targetDtype [dict get $variable dtype]
    if {$targetDtype in {float32 float64}} {
        set precision [expr {$targetDtype eq "float32" ? 9 : 17}]
        set formatted {}
        foreach value $out {
            switch -- [string tolower [string trim $value]] {
                nan - +nan - -nan { lappend formatted NaN }
                inf - +inf - infinity - +infinity { lappend formatted Inf }
                -inf - -infinity { lappend formatted -Inf }
                default { lappend formatted [format "%.*g" $precision $value] }
            }
        }
        set out $formatted
    }
    return $out
}

proc ::GX::datasetPublicationV2MaterializeValues {variable values} {
    if {[datasetPublicationV2IsResource $values]} {error {This provider does not support managed binary resources}}
    if {[datasetPublicationV2IsBinaryBlock $values]} { return [datasetPublicationV2MaterializeBinaryBlock $variable $values] }
    return $values
}

proc ::GX::datasetPublicationV2BinaryFields {values} {
    return [list [dict get $values dtype] [dict get $values endian] [dict get $values shape] [dict get $values base64]]
}

proc ::GX::datasetPublicationV2WriteVariable {writer variableId values {shape ""}} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    if {$variableId ni $datasetPublicationWriter($writer,variable_ids)} { error "Unknown variable_id $variableId" }
    set variable $datasetPublicationWriter($writer,variable,$variableId)
    if {[dict get $variable axis_kind] eq "uniform"} { error "Implicit uniform coordinates do not accept stored values" }
    set declared [datasetPublicationV2Shape [dict get $variable shape]]
    if {$shape eq ""} { set shape $declared } else { set shape [datasetPublicationV2Shape $shape] }
    if {$shape ne $declared} { error "Complete variable shape mismatch for $variableId" }
    set payload [datasetPublicationV2ValuesPayload $shape $values]
    datasetPublicationV2ValidateTypedValues $variable $values
    return [datasetPublicationV2ProviderCall $writer write_variable $variableId $payload]
}

proc ::GX::datasetPublicationV2WriteRange {writer variableId start values} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    if {$variableId ni $datasetPublicationWriter($writer,variable_ids)} { error "Unknown variable_id $variableId" }
    set variable $datasetPublicationWriter($writer,variable,$variableId)
    if {[dict get $variable rank] != 1 || [dict get $variable axis_kind] eq "uniform"} { error "Range writes require a stored rank-1 variable" }
    set valueCount [datasetPublicationV2PayloadCount $values]
    if {![string is integer -strict $start] || $start < 0 || $start+$valueCount > [lindex [datasetPublicationV2Shape [dict get $variable shape]] 0]} { error "Range write is outside variable $variableId" }
    datasetPublicationV2ValidateTypedValues $variable $values
    return [datasetPublicationV2ProviderCall $writer write_range $variableId $start $values]
}

proc ::GX::datasetPublicationV2Append {writer dimensionId data} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    if {$dimensionId ni $datasetPublicationWriter($writer,dimension_ids)} { error "Unknown append dimension_id $dimensionId" }
    set dimension $datasetPublicationWriter($writer,dimension,$dimensionId)
    if {![dict get $dimension extendible]} { error "Dimension $dimensionId is not extendible" }
    set appendCount -1; set payloads [dict create]
    foreach variableId $datasetPublicationWriter($writer,variable_ids) {
        set variable $datasetPublicationWriter($writer,variable,$variableId)
        set dims [datasetSchemaV3SplitIds [dict get $variable dimension_ids]]
        set axis [lsearch -exact $dims $dimensionId]
        if {$axis < 0 || [dict get $variable axis_kind] eq "uniform"} continue
        if {![dict exists $data $variableId]} { error "Append requires values for variable_id $variableId" }
        set item [dict get $data $variableId]
        if {![catch {dict exists $item values} hasValues] && $hasValues && [dict exists $item shape]} {
            set values [dict get $item values]; set blockShape [datasetPublicationV2Shape [dict get $item shape]]
        } else {
            set values $item
            if {[dict get $variable rank] != 1} { error "Multidimensional append for $variableId requires shape and values" }
            set blockShape [list [datasetPublicationV2PayloadCount $values]]
        }
        if {[llength $blockShape] != [dict get $variable rank]} { error "Append block rank mismatch for $variableId" }
        set currentShape [datasetPublicationV2Shape [dict get $variable shape]]
        for {set index 0} {$index < [llength $blockShape]} {incr index} {
            if {$index != $axis && [lindex $blockShape $index] != [lindex $currentShape $index]} { error "Append block shape mismatch for $variableId" }
        }
        set count [lindex $blockShape $axis]
        if {$appendCount < 0} { set appendCount $count } elseif {$count != $appendCount} { error "Append variables use inconsistent dimension lengths" }
        datasetPublicationV2ValuesPayload $blockShape $values
        datasetPublicationV2ValidateTypedValues $variable $values
        dict set payloads $variableId [dict create axis $axis shape $blockShape values $values]
    }
    if {$appendCount < 0} { error "No stored variable uses append dimension $dimensionId" }
    set providerData $payloads
    if {$datasetPublicationWriter($writer,provider) eq "csv"} {
        set offset [dict get $dimension size]
        foreach variableId $datasetPublicationWriter($writer,variable_ids) {
            set variable $datasetPublicationWriter($writer,variable,$variableId)
            if {[dict get $variable axis_kind] ne "uniform"} continue
            set values {}
            for {set index 0} {$index < $appendCount} {incr index} { lappend values [expr {double([dict get $variable axis_origin])+($offset+$index)*double([dict get $variable axis_step])}] }
            dict set providerData $variableId [dict create axis 0 shape [list $appendCount] values $values]
        }
    }
    datasetPublicationV2ProviderCall $writer append $dimensionId $providerData
    dict set dimension size [expr {[dict get $dimension size]+$appendCount}]
    set datasetPublicationWriter($writer,dimension,$dimensionId) $dimension
    foreach variableId $datasetPublicationWriter($writer,variable_ids) {
        set variable $datasetPublicationWriter($writer,variable,$variableId)
        set dims [datasetSchemaV3SplitIds [dict get $variable dimension_ids]]; set axis [lsearch -exact $dims $dimensionId]
        if {$axis < 0} continue
        set shape [datasetPublicationV2Shape [dict get $variable shape]]; lset shape $axis [dict get $dimension size]
        dict set variable shape [join $shape {;}]
        if {[dict get $variable axis_kind] eq "uniform"} { dict set variable axis_count [dict get $dimension size] }
        set datasetPublicationWriter($writer,variable,$variableId) $variable
    }
    return $appendCount
}

proc ::GX::datasetPublicationV2WriteHyperslab {writer variableId starts counts values} {
    variable datasetPublicationWriter
    datasetPublicationV2RequireWriter $writer
    if {$variableId ni $datasetPublicationWriter($writer,variable_ids)} { error "Unknown variable_id $variableId" }
    set variable $datasetPublicationWriter($writer,variable,$variableId); set shape [datasetPublicationV2Shape [dict get $variable shape]]
    if {[llength $starts] != [dict get $variable rank] || [llength $counts] != [dict get $variable rank]} { error "Hyperslab rank mismatch for $variableId" }
    for {set index 0} {$index < [llength $shape]} {incr index} {
        set start [lindex $starts $index]; set count [lindex $counts $index]
        if {![string is integer -strict $start] || ![string is integer -strict $count] || $start < 0 || $count < 0 || $start+$count > [lindex $shape $index]} { error "Hyperslab is outside variable $variableId" }
    }
    datasetPublicationV2ValuesPayload $counts $values
    datasetPublicationV2ValidateTypedValues $variable $values
    return [datasetPublicationV2ProviderCall $writer write_hyperslab $variableId $starts $counts $values]
}

proc ::GX::datasetPublicationV2Flush {writer} { return [datasetPublicationV2ProviderCall $writer flush] }
proc ::GX::datasetPublicationV2Diagnostics {writer} { return [datasetPublicationV2ProviderCall $writer diagnostics] }

proc ::GX::datasetPublicationV2RegistryFields {writer sha integritySeconds} {
    variable datasetPublicationWriter
    variable datasetPublicationPlan
    set plan $datasetPublicationWriter($writer,plan); set provider $datasetPublicationWriter($writer,provider)
    set definition $datasetPublicationPlan($plan,definition); set variables {}; set units {}; set roles {}; set fields {}
    set index 0; set rowCount -1
    foreach variableId $datasetPublicationWriter($writer,variable_ids) {
        incr index; set variable $datasetPublicationWriter($writer,variable,$variableId)
        lappend variables [dict get $variable name]; lappend units [dict get $variable unit]; lappend roles [dict get $variable semantic_role]
        set prefix "var${index}_"
        foreach {field value} [list variable_id $variableId enabled 1 source_column [expr {$provider eq "csv" ? $index : ""}] canonical_position $index original_header [dict get $variable name] canonical [dict get $variable name] unit [dict get $variable unit] semantic_role [dict get $variable semantic_role] value_kind [dict get $variable value_kind] dtype [dict get $variable dtype] rank [dict get $variable rank] shape [dict get $variable shape] dimension_ids [dict get $variable dimension_ids] coordinate_variable_ids [dict get $variable coordinate_variable_ids] coordinate_role [dict get $variable coordinate_role] axis_kind [dict get $variable axis_kind] axis_origin [dict get $variable axis_origin] axis_step [dict get $variable axis_step] axis_count [dict get $variable axis_count] component_ids [dict get $variable component_ids] group_id [dict get $variable group_id] storage_locator [dict get $variable storage_locator]] { lappend fields "${prefix}$field" $value }
        foreach field {display_label semantic_source value_format decimal_separator canonical_unit to_canonical from_canonical time_origin time_reference instrument_id instrument_channel} {
            lappend fields "${prefix}$field" [dict get $variable $field]
        }
        set shape [datasetPublicationV2Shape [dict get $variable shape]]
        if {[llength $shape] && [lindex $shape 0] > $rowCount} { set rowCount [lindex $shape 0] }
    }
    set format [expr {$provider eq "hdf5" ? "hdf5" : "csv"}]
    set media [expr {$provider eq "hdf5" ? "application/x-hdf5" : "text/csv"}]
    set base [list kind $datasetPublicationPlan($plan,contract) contract $datasetPublicationPlan($plan,contract) format $format storage_kind [expr {$provider eq "hdf5" ? "binary" : "text"}] media_type $media path $datasetPublicationPlan($plan,target_relative) columns [join $variables {;}] variables [join $variables {;}] units [join $units {;}] semantic_roles [join $roles {;}] source_module $datasetPublicationPlan($plan,module_id) source [datasetPublicationV2DictDefault $definition source ""] provenance [datasetPublicationV2DictDefault $definition provenance ""] producer_module $datasetPublicationPlan($plan,module_id) producer_version [datasetPublicationV2DictDefault $definition producer_version ""] source_dataset_ids [join [datasetPublicationV2DictDefault $definition source_dataset_ids {}] {;}] source_variable_ids [join [datasetPublicationV2DictDefault $definition source_variable_ids {}] {;}] requested_storage_provider $datasetPublicationPlan($plan,requested_provider) storage_provider $provider storage_provider_version $datasetPublicationPlan($plan,provider_version) storage_selection_reason $datasetPublicationPlan($plan,selection_reason) publication_api_version 2 variable_schema_api_version 3 canonical_access_api_version 2 canonical_sha256 $sha sha256 $sha integrity_algorithm sha256 integrity_seconds $integritySeconds row_count $rowCount sample_count $rowCount var_count [llength $variables] created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] immutable 0 notes [datasetPublicationV2DictDefault $definition notes ""]]
    if {$provider eq "csv"} { lappend base canonical_delimiter comma }
    return [concat $base $fields]
}

proc ::GX::datasetPublicationV2Finalize {writer} {
    variable datasetPublicationWriter
    variable datasetPublicationPlan
    variable datasetRegistry
    datasetPublicationV2RequireWriter $writer
    if {![llength $datasetPublicationWriter($writer,variable_ids)]} { error "Publication has no variables" }
    foreach variableId $datasetPublicationWriter($writer,variable_ids) {
        set variable $datasetPublicationWriter($writer,variable,$variableId)
        foreach field {coordinate_variable_ids component_ids} {
            foreach related [datasetSchemaV3SplitIds [dict get $variable $field]] {
                if {$related ni $datasetPublicationWriter($writer,variable_ids)} { error "$field for $variableId references unknown variable_id $related" }
            }
        }
    }
    set final $datasetPublicationPlan($datasetPublicationWriter($writer,plan),final_path)
    set temp $datasetPublicationWriter($writer,temp_path)
    set session $datasetPublicationPlan($datasetPublicationWriter($writer,plan),session)
    set datasetId $datasetPublicationPlan($datasetPublicationWriter($writer,plan),dataset_id)
    set providerResult [datasetPublicationV2ProviderCall $writer finalize]
    if {![file isfile $temp]} { set datasetPublicationWriter($writer,status) failed; error "Provider did not produce a publication object" }
    set hashStart [clock microseconds]
    if {[catch {set sha [sha256File $temp]} failure options]} { set datasetPublicationWriter($writer,status) failed; catch {file delete -force -- $temp}; return -options $options "Publication integrity failure: $failure" }
    set integritySeconds [format %.6f [expr {([clock microseconds]-$hashStart)/1000000.0}]]
    return [datasetAuthorityTransaction $session ::GX::_datasetPublicationV2Commit $writer $sha $integritySeconds $providerResult]
}
proc ::GX::_datasetPublicationV2Commit {writer sha integritySeconds providerResult} {
    variable datasetPublicationWriter;variable datasetPublicationPlan;variable datasetRegistry
    set plan $datasetPublicationWriter($writer,plan)
    set session $datasetPublicationPlan($plan,session)
    set datasetId $datasetPublicationPlan($plan,dataset_id)
    set final $datasetPublicationPlan($plan,final_path)
    set temp $datasetPublicationWriter($writer,temp_path)
    loadDatasetRegistry $session
    if {$datasetPublicationPlan($plan,operation) eq "creating"} {
        if {[datasetField $datasetId id {}] ne {} || [file exists $final]} {error "Dataset '$datasetId' was created concurrently"}
    } else {
        if {[datasetField $datasetId id {}] eq {} || [datasetRevisionToken $datasetId $session] ne $datasetPublicationPlan($plan,expected_revision)} {error "Dataset '$datasetId' revision changed before commit"}
        if {[string is true -strict [datasetField $datasetId immutable 0]]} {error "Dataset '$datasetId' is immutable"}
        if {[datasetField $datasetId source_module {}] ne $datasetPublicationPlan($plan,module_id) || [datasetField $datasetId publication_api_version {}] ne "2"} {error {Dataset producer changed before commit}}
        _datasetNamespaceRequireModuleWrite $session $datasetPublicationPlan($plan,module_id) $datasetId
        if {[datasetField $datasetId path {}] ne $datasetPublicationPlan($plan,target_relative)} {error {Dataset publication target changed}}
    }
    datasetAuthorityEnlist $final
    datasetAuthorityEnlist [datasetRegistryPath $session]
    datasetAuthorityFault before_place
    set definition $datasetPublicationPlan($plan,definition)
    lassign [_datasetMetadataPath $session $datasetId] metadataRelative metadataPath
    datasetAuthorityEnlist $metadataPath
    try {
        # The durable undo preimage exists before this atomic replacement. A
        # crash cannot permanently remove the last complete owned payload.
        file rename -force -- $temp $final
        datasetAuthorityFault after_place
        datasetRegister $datasetId [datasetPublicationV2RegistryFields $writer $sha $integritySeconds]
        saveDatasetRegistry $session
        datasetAuthorityFault after_registry
        set statisticalSchema {}
        foreach variableId $datasetPublicationWriter($writer,variable_ids) {lappend statisticalSchema $datasetPublicationWriter($writer,variable,$variableId)}
        set publicationMetadata [::GX::StatisticsV1::sealPublicationBindings [datasetPublicationV2DictDefault $definition structured_metadata {}] $statisticalSchema $sha]
        _datasetMetadataPublicationWrite $session $datasetId [_scientificPublicationMetadata $session $datasetId $publicationMetadata [datasetPublicationV2DictDefault $definition source_dataset_ids {}] [expr {$datasetPublicationPlan($plan,operation) eq "replacing"}]] $datasetPublicationPlan($plan,module_id) [dict keys $publicationMetadata]
        _datasetFrameworkMetadataUpdate $session $datasetId [dict create dataset_namespace [dict get $definition dataset_namespace]]
        datasetAuthorityFault after_metadata
    } on error {failure options} {
        set datasetPublicationWriter($writer,status) failed
        catch {file delete -force -- $temp}
        return -options $options "Publication commit failure: $failure"
    }
    datasetPublicationStageTrack $session $temp {} 1
    set datasetPublicationWriter($writer,status) finalized
    set plan $datasetPublicationWriter($writer,plan); set datasetPublicationPlan($plan,status) finalized
    return [dict create dataset_id $datasetId path $datasetPublicationPlan($plan,target_relative) storage_provider $datasetPublicationWriter($writer,provider) sha256 $sha integrity_seconds $integritySeconds provider_diagnostics $providerResult]
}

proc ::GX::datasetPublicationV2Abort {writer} {
    variable datasetPublicationWriter
    variable datasetPublicationPlan
    variable datasetWriterProviderCommand
    if {![info exists datasetPublicationWriter($writer,status)]} { error "Unknown publication writer: $writer" }
    if {$datasetPublicationWriter($writer,status) eq "finalized"} { error "Cannot abort a finalized publication writer" }
    if {$datasetPublicationWriter($writer,status) eq "aborted"} { return }
    set provider $datasetPublicationWriter($writer,provider)
    catch {uplevel #0 [list {*}$datasetWriterProviderCommand($provider) abort $datasetPublicationWriter($writer,provider_token)]}
    catch {file delete -force -- $datasetPublicationWriter($writer,temp_path)}
    set plan $datasetPublicationWriter($writer,plan)
    catch {datasetPublicationStageTrack $datasetPublicationPlan($plan,session) $datasetPublicationWriter($writer,temp_path) {} 1}
    set datasetPublicationWriter($writer,status) aborted
    set plan $datasetPublicationWriter($writer,plan); set datasetPublicationPlan($plan,status) aborted
}

# One-dimensional X/Y convenience; the authoritative writer and registry
# transaction remain DATASET_PUBLICATION_API_v2.
proc ::GX::datasetPublicationV2PublishSeries {session moduleId request} {
    if {[catch {dict size $request}]} {error "publish_series requires a request dictionary"}
    foreach field {dataset_id contract x_values y_values x_variable y_variable} {
        if {![dict exists $request $field]} {error "publish_series requires $field"}
    }
    set xs [dict get $request x_values];set ys [dict get $request y_values]
    set n [llength $xs]
    if {$n == 0 || $n != [llength $ys]} {error "X and Y series need the same nonzero length"}
    set x [dict get $request x_variable];set y [dict get $request y_variable]
    if {[catch {dict size $x}] || [catch {dict size $y}]} {error "x_variable and y_variable must be descriptors"}
    foreach spec [list $x $y] {
        if {![dict exists $spec variable_id]} {error "Variable descriptor needs variable_id"}
    }
    set xId [dict get $x variable_id];set yId [dict get $y variable_id]
    if {$xId eq $yId} {error "X and Y variable IDs must differ"}
    set extras [datasetPublicationV2DictDefault $request extra_variables {}];set ids [list $xId $yId]
    foreach extra $extras {
        set descriptor [dict get $extra descriptor];set id [dict get $descriptor variable_id]
        if {$id in $ids||[llength [dict get $extra values]]!=$n} {error {Additional series variables require distinct IDs and the complete row count}}
        lappend ids $id
    }
    set definition [dict create dataset_id [dict get $request dataset_id] contract [dict get $request contract]]
    dict set definition expected_rows $n
    dict set definition estimated_numeric_bytes [expr {$n*16}]
    foreach field {storage structured_metadata dataset_namespace producer_version source source_dataset_ids source_variable_ids provenance notes replace_owned} {
        if {[dict exists $request $field]} {dict set definition $field [dict get $request $field]}
    }
    set plan [datasetPublicationV2Prepare $session $moduleId $definition]
    set writer ""
    if {[catch {
        set writer [datasetPublicationV2OpenWriter $plan]
        datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        dict set x dimension_ids row;dict set x rank 1
        dict set y dimension_ids row;dict set y rank 1
        if {![dict exists $x coordinate_role]} {dict set x coordinate_role coordinate}
        if {![dict exists $y coordinate_role]} {dict set y coordinate_role data}
        datasetPublicationV2DeclareVariable $writer $xId $x
        datasetPublicationV2DeclareVariable $writer $yId $y
        set values [dict create $xId $xs $yId $ys]
        foreach extra $extras {
            set descriptor [dict get $extra descriptor];set id [dict get $descriptor variable_id]
            dict set descriptor dimension_ids row;dict set descriptor rank 1
            datasetPublicationV2DeclareVariable $writer $id $descriptor
            dict set values $id [dict get $extra values]
        }
        datasetPublicationV2Append $writer row $values
        set result [datasetPublicationV2Finalize $writer]
    } failure options]} {
        if {$writer ne ""} {catch {datasetPublicationV2Abort $writer}}
        return -options $options $failure
    }
    return $result
}

proc ::GX::datasetPublicationV2CsvQuote {value} {
    if {[regexp {[",\r\n]} $value]} { return "\"[string map {\" \"\"} $value]\"" }
    return $value
}

proc ::GX::csvDatasetWriter {operation token args} {
    variable csvWriterState
    variable csvWriterCounter
    switch -- $operation {
        open {
            set context [lindex $args 0]; set token "csv-writer#[incr csvWriterCounter]"
            set channel [open [dict get $context temp_path] w]; fconfigure $channel -encoding utf-8 -translation lf -buffering line
            set csvWriterState($token,channel) $channel; set csvWriterState($token,order) {}; set csvWriterState($token,sealed) 0; set csvWriterState($token,rows) 0; set csvWriterState($token,max_request_elements) 0
            return $token
        }
        declare_variable {
            set variable [lindex $args 0]
            if {[dict get $variable rank] != 1 || [dict get $variable group_id] ne ""} { error "CSV writer accepts only ungrouped rank-1 variables" }
            lappend csvWriterState($token,order) [dict get $variable variable_id]
            set csvWriterState($token,name,[dict get $variable variable_id]) [dict get $variable name]
            set csvWriterState($token,variable,[dict get $variable variable_id]) $variable
            return "column:[llength $csvWriterState($token,order)]"
        }
        append {
            lassign $args dimensionId data
            set materialized [dict create]
            if {!$csvWriterState($token,sealed)} {
                set headers {}; foreach variableId $csvWriterState($token,order) { lappend headers [datasetPublicationV2CsvQuote $csvWriterState($token,name,$variableId)] }
                puts $csvWriterState($token,channel) [join $headers ,]; set csvWriterState($token,sealed) 1
            }
            set count -1
            foreach variableId $csvWriterState($token,order) {
                if {![dict exists $data $variableId]} { error "CSV append requires every declared variable" }
                set values [datasetPublicationV2MaterializeValues $csvWriterState($token,variable,$variableId) [dict get $data $variableId values]]
                dict set materialized $variableId $values
                set n [llength $values]
                if {$count < 0} { set count $n } elseif {$n != $count} { error "CSV append columns have inconsistent lengths" }
            }
            for {set row 0} {$row < $count} {incr row} {
                set fields {}; foreach variableId $csvWriterState($token,order) { lappend fields [datasetPublicationV2CsvQuote [lindex [dict get $materialized $variableId] $row]] }
                puts $csvWriterState($token,channel) [join $fields ,]
            }
            incr csvWriterState($token,rows) $count
            set elements [expr {$count*[llength $csvWriterState($token,order)]}]
            if {$elements > $csvWriterState($token,max_request_elements)} { set csvWriterState($token,max_request_elements) $elements }
            return $count
        }
        write_variable {
            if {[llength $csvWriterState($token,order)] != 1} { error "CSV complete-variable writes require a single-variable dataset; use append for tables" }
            lassign $args variableId payload
            return [csvDatasetWriter append $token row [dict create $variableId [dict create values [dict get $payload values]]]]
        }
        write_range { error "CSV random/range writes are unsupported; use sequential append" }
        write_hyperslab { error "CSV hyperslab writes are unsupported" }
        flush { flush $csvWriterState($token,channel); return }
        diagnostics { return [dict create process_id [pid] rows_written $csvWriterState($token,rows) max_request_elements $csvWriterState($token,max_request_elements)] }
        finalize {
            if {!$csvWriterState($token,sealed)} { set headers {}; foreach variableId $csvWriterState($token,order) { lappend headers [datasetPublicationV2CsvQuote $csvWriterState($token,name,$variableId)] }; puts $csvWriterState($token,channel) [join $headers ,] }
            flush $csvWriterState($token,channel); set result [csvDatasetWriter diagnostics $token]; close $csvWriterState($token,channel)
            foreach name [array names csvWriterState "$token,*"] { unset csvWriterState($name) }
            return $result
        }
        abort {
            if {[info exists csvWriterState($token,channel)]} { catch {close $csvWriterState($token,channel)} }
            foreach name [array names csvWriterState "$token,*"] { unset csvWriterState($name) }
            return
        }
        default { error "Unsupported CSV writer operation: $operation" }
    }
}

proc ::GX::datasetPublicationV2Hdf5Read {channel} { return [hdf5ProviderReadLine $channel] }
proc ::GX::datasetPublicationV2EncodeValues {values} { return [datasetB64Encode [join $values "\u001f"]] }
proc ::GX::datasetPublicationV2Hdf5Locator {variable} {
    set group [dict get $variable group_id]; set parts {data}
    if {$group ne ""} { foreach item [split $group .] { lappend parts [regsub -all {[^A-Za-z0-9_-]} $item _] } }
    lappend parts [regsub -all {[^A-Za-z0-9_.-]} [dict get $variable variable_id] _]
    return "/[join $parts /]"
}

proc ::GX::hdf5DatasetWriter {operation token args} {
    variable hdf5WriterState
    variable hdf5WriterCounter
    variable scriptDir
    switch -- $operation {
        open {
            set context [lindex $args 0]; set helper [file join $scriptDir core python gxtxt_hdf5_writer.py]
            if {![file isfile $helper]} { error "HDF5 writer helper is missing" }
            set python [runtimeToolRequired python]
            if {[catch {set channel [open [list | $python -u $helper --file [dict get $context temp_path]] r+]} failure]} { error "HDF5 writer could not start: $failure" }
            fconfigure $channel -encoding utf-8 -translation lf -buffering line
            if {[catch {set ready [datasetPublicationV2Hdf5Read $channel]} failure]} { catch {close $channel}; error $failure }
            if {[lindex $ready 1] ne "READY"} { catch {close $channel}; error "HDF5 writer did not become ready" }
            set token "hdf5-writer#[incr hdf5WriterCounter]"; set hdf5WriterState($token,channel) $channel; set hdf5WriterState($token,pid) [lindex $ready 2]
            return $token
        }
        declare_variable {
            set variable [lindex $args 0]
            if {[dict get $variable axis_kind] eq "uniform"} { return "" }
            set locator [datasetPublicationV2Hdf5Locator $variable]; set chunks [dict get $variable chunks]
            if {$chunks eq "" && [string first * [dict get $variable maxshape]] >= 0} { set chunks [string map {* 1} [dict get $variable maxshape]] }
            set fields [list $locator [dict get $variable dtype] [dict get $variable shape] [dict get $variable maxshape] $chunks [dict get $variable variable_id] [dict get $variable name] [dict get $variable unit] [dict get $variable semantic_role] [dict get $variable dimension_ids] [dict get $variable coordinate_role] [dict get $variable axis_kind] [dict get $variable axis_origin] [dict get $variable axis_step] [dict get $variable group_id]]
            set encoded {}; foreach field $fields { lappend encoded [datasetB64Encode $field] }
            puts $hdf5WriterState($token,channel) "CREATE\t[join $encoded \t]"; flush $hdf5WriterState($token,channel); datasetPublicationV2Hdf5Read $hdf5WriterState($token,channel)
            set hdf5WriterState($token,locator,[dict get $variable variable_id]) $locator
            return $locator
        }
        write_variable {
            lassign $args variableId payload; set channel $hdf5WriterState($token,channel); set locator $hdf5WriterState($token,locator,$variableId)
            set values [dict get $payload values]; set prefix "[datasetB64Encode $locator]\t[datasetB64Encode [join [dict get $payload shape] {;}]]"
            if {[datasetPublicationV2IsResource $values]} {puts $channel "RWRITE\t$prefix\t[datasetPublicationV2ResourceFields $values]"
            } elseif {[datasetPublicationV2IsBinaryBlock $values]} { puts $channel "BWRITE\t$prefix\t[join [datasetPublicationV2BinaryFields $values] \t]" } else { puts $channel "WRITE\t$prefix\t[datasetPublicationV2EncodeValues $values]" }
            flush $channel; datasetPublicationV2Hdf5Read $channel; return
        }
        write_range {
            lassign $args variableId start values; set channel $hdf5WriterState($token,channel); set prefix "[datasetB64Encode $hdf5WriterState($token,locator,$variableId)]\t$start"
            if {[datasetPublicationV2IsResource $values]} {puts $channel "RRANGE\t$prefix\t[datasetPublicationV2ResourceFields $values]"
            } elseif {[datasetPublicationV2IsBinaryBlock $values]} { puts $channel "BRANGE\t$prefix\t[join [datasetPublicationV2BinaryFields $values] \t]" } else { puts $channel "RANGE\t$prefix\t[datasetPublicationV2EncodeValues $values]" }
            flush $channel; datasetPublicationV2Hdf5Read $channel; return
        }
        append {
            lassign $args dimensionId data; set channel $hdf5WriterState($token,channel)
            dict for {variableId item} $data {
                set values [dict get $item values]; set prefix "[datasetB64Encode $hdf5WriterState($token,locator,$variableId)]\t[dict get $item axis]\t[datasetB64Encode [join [dict get $item shape] {;}]]"
                if {[datasetPublicationV2IsResource $values]} {puts $channel "RAPPEND\t$prefix\t[datasetPublicationV2ResourceFields $values]"
                } elseif {[datasetPublicationV2IsBinaryBlock $values]} { puts $channel "BAPPEND\t$prefix\t[join [datasetPublicationV2BinaryFields $values] \t]" } else { puts $channel "APPEND\t$prefix\t[datasetPublicationV2EncodeValues $values]" }
                flush $channel; datasetPublicationV2Hdf5Read $channel
            }
            return
        }
        write_hyperslab {
            lassign $args variableId starts counts values; set channel $hdf5WriterState($token,channel); set prefix "[datasetB64Encode $hdf5WriterState($token,locator,$variableId)]\t[datasetB64Encode [join $starts {;}]]\t[datasetB64Encode [join $counts {;}]]"
            if {[datasetPublicationV2IsResource $values]} {puts $channel "RHYPER\t$prefix\t[datasetPublicationV2ResourceFields $values]"
            } elseif {[datasetPublicationV2IsBinaryBlock $values]} { puts $channel "BHYPER\t$prefix\t[join [datasetPublicationV2BinaryFields $values] \t]" } else { puts $channel "HYPER\t$prefix\t[datasetPublicationV2EncodeValues $values]" }
            flush $channel; datasetPublicationV2Hdf5Read $channel; return
        }
        flush { puts $hdf5WriterState($token,channel) FLUSH; flush $hdf5WriterState($token,channel); datasetPublicationV2Hdf5Read $hdf5WriterState($token,channel); return }
        diagnostics {
            set channel $hdf5WriterState($token,channel); puts $channel STATS; flush $channel; set p [datasetPublicationV2Hdf5Read $channel]
            return [dict create process_id [lindex $p 2] elements_written [lindex $p 3] max_request_elements [lindex $p 4] append_calls [lindex $p 5] hyperslab_elements_written [lindex $p 6] binary_blocks [lindex $p 7] binary_bytes [lindex $p 8] resource_blocks [lindex $p 9] resource_bytes [lindex $p 10]]
        }
        finalize {
            set channel $hdf5WriterState($token,channel); puts $channel VALIDATE; flush $channel; datasetPublicationV2Hdf5Read $channel
            set result [hdf5DatasetWriter diagnostics $token]; puts $channel CLOSE; flush $channel; datasetPublicationV2Hdf5Read $channel; catch {close $channel}
            foreach name [array names hdf5WriterState "$token,*"] { unset hdf5WriterState($name) }
            return $result
        }
        abort {
            if {[info exists hdf5WriterState($token,channel)]} { set channel $hdf5WriterState($token,channel); catch {puts $channel CLOSE; flush $channel; datasetPublicationV2Hdf5Read $channel}; catch {close $channel} }
            foreach name [array names hdf5WriterState "$token,*"] { unset hdf5WriterState($name) }
            return
        }
        default { error "Unsupported HDF5 writer operation: $operation" }
    }
}

::GX::datasetWriterProviderRegister csv ::GX::csvDatasetWriter [dict create complete_variable 1 range_write 0 append_write 1 hyperslab_write 0 multidimensional 0 groups 0 implicit_axis 1 typed_numeric 0 sequential_chunks 1 human_readable 1] 1
::GX::datasetWriterProviderRegister hdf5 ::GX::hdf5DatasetWriter [dict create complete_variable 1 range_write 1 append_write 1 hyperslab_write 1 multidimensional 1 groups 1 implicit_axis 1 typed_numeric 1 managed_binary_write 1 sequential_chunks 1 human_readable 0] 1

# Additive runtime discovery; the v1 section and contract remain unchanged.
proc ::GX::datasetPublicationRuntimeAppend {runtime moduleId} {
    datasetPublicationRuntimeAppend_v1_base $runtime $moduleId
    set fd [open $runtime a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[dataset_publication_api_v2\]"
    putKV $fd api_version 2
    putKV $fd identity {dataset_id;variable_id;dimension_id}
    putKV $fd storage_providers [join [datasetWriterProviderIds] {;}]
    close $fd
}

# Reviewed, create-only batches reuse the existing Publication v2 writers and
# Canonical Catalog transaction. Callbacks are trusted host controllers; scripts
# use the existing typed publish_series contract through publish_series_batch.
proc ::GX::datasetPublicationV2BatchPreflight {session moduleId requests} {
    variable currentSession
    set session [file normalize $session]
    if {![file isdirectory $session]} {error {Batch publication Session is missing}}
    datasetPublicationV2ValidateId module $moduleId
    if {[llength $requests]<1||[llength $requests]>64} {error {Review 1..64 separate Dataset outputs}}
    set currentSession $session;loadDatasetRegistry $session
    set ids {};set targets {}
    foreach request $requests {
        datasetPublicationV2ValidateId module [datasetPublicationV2DictDefault $request publication_module $moduleId]
        set id [datasetPublicationV2ValidateId dataset [dict get $request dataset_id]]
        if {$id in $ids} {error "Duplicate reviewed Dataset ID '$id'"}
        if {[datasetField $id id {}] ne {}} {error "Dataset ID '$id' already exists; batch has not started"}
        if {[datasetPublicationV2DictDefault $request replace_owned 0]} {error {Batch publication is create-only}}
        if {[dict exists $request relative_path]} {set paths [list [datasetPublicationV2SafeRelative [dict get $request relative_path]]]} else {set paths [list [file join datasets publications $id.csv] [file join datasets publications $id.h5]]}
        lappend paths [_datasetMetadataRelativePath $id]
        foreach path $paths {
            set final [file normalize [file join $session $path]]
            if {[string first "${session}/" "${final}/"]!=0||$final in $targets} {error "Batch output path collides: $path"}
            if {[file exists $final]} {error "Batch output already exists: $path"}
            lappend targets $final
        }
        lappend ids $id
    }
    return [dict create dataset_ids $ids output_count [llength $ids] create_only 1]
}
proc ::GX::_datasetPublicationV2BatchExecute {session moduleId requests command} {
    variable datasetRegistry
    set prior [array get datasetRegistry];set previousIds [datasetRegistryIds]
    set registry [datasetRegistryPath $session]
    set existed [file isfile $registry];set backup "$registry.batch-v2.[pid].[clock clicks].backup"
    if {$existed} {file copy -- $registry $backup}
    set results {}
    try {
        foreach request $requests {
            set id [dict get $request dataset_id]
            set result [uplevel #0 [list {*}$command $session $moduleId $request]]
            if {![dict exists $result dataset_id]||[dict get $result dataset_id] ne $id||[datasetField $id id {}] ne $id} {error "Publication callback did not publish reviewed Dataset '$id'"}
            set owner [datasetField $id source_module [datasetField $id producer_module {}]]
            set expectedOwner [datasetPublicationV2DictDefault $request publication_module $moduleId]
            if {$owner ne $expectedOwner||[datasetField $id publication_api_version {}] ne "2"} {error {Batch output did not use the reviewed Publication v2 authority}}
            lappend results $result
        }
        set ids [lmap request $requests {dict get $request dataset_id}]
        foreach id [datasetRegistryIds] {if {$id ni $previousIds&&$id ni $ids} {error {Batch callback published an unreviewed Dataset}}}
    } on error {message options} {
        set rollbackErrors {}
        foreach id [datasetRegistryIds] {
            if {$id in $previousIds} continue
            foreach relative [list [datasetField $id path {}] [_datasetMetadataRelativePath $id]] {
                if {$relative eq {}} continue
                set path [file normalize [file join $session [datasetPublicationV2SafeRelative $relative]]]
                if {[catch {file delete -force -- $path} failure]} {lappend rollbackErrors $failure}
            }
        }
        array unset datasetRegistry *;array set datasetRegistry $prior
        if {$existed} {file rename -force -- $backup $registry} else {file delete -force -- $registry}
        if {$rollbackErrors ne {}} {return -code error "Batch failed: $message; rollback failed: $rollbackErrors"}
        return -options $options $message
    } finally {if {[file exists $backup]} {file delete -- $backup}}
    return [dict create output_count [llength $results] dataset_ids [lmap result $results {dict get $result dataset_id}] datasets $results atomic 1]
}
proc ::GX::datasetPublicationV2PublishBatch {session moduleId requests {command ::GX::datasetPublicationV2PublishSeries}} {
    datasetPublicationV2BatchPreflight $session $moduleId $requests
    return [datasetCatalogTransaction ::GX::_datasetPublicationV2BatchExecute [file normalize $session] $moduleId $requests $command]
}

source [file join [file dirname [info script]] dataset_publication_managed_columns_v2.tcl]
source [file join [file dirname [info script]] dataset_publication_managed_variables_v2.tcl]
