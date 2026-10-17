# SPDX-License-Identifier: GPL-3.0-or-later
# Additive public coordinate operations of DATASET_METADATA_API_v1. Persistence
# remains the existing framework namespace in each Dataset's metadata resource.
namespace eval ::GX::DatasetCoordinates {
    variable key _gxtxt.framework.coordinate_context_v1
}
source [file join [file dirname [info script]] dataset_coordinate_transform_v1.tcl]
proc ::GX::_datasetCoordinateFields {value required label} {
    if {[catch {dict size $value}]} {error "$label must be a dictionary"}
    foreach k [dict keys $value] {if {$k ni $required} {error "Unknown $label field '$k'"}}
    foreach k $required {if {![dict exists $value $k]} {error "$label requires '$k'"}}
}
proc ::GX::_datasetCoordinateSource {variable} {
    set result {}
    foreach key {unit dtype value_kind value_format decimal_separator time_origin time_reference canonical_unit to_canonical from_canonical} {dict set result $key [dict get $variable $key]}
    if {[dict get $result dtype] ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64} || [dict get $result value_kind] ni {number elapsed_time}} {error {Coordinate settings require a real numeric Variable}}
    return $result
}
proc ::GX::_datasetCoordinateOverride {source} {
    if {[dict get $source canonical_unit] eq {}} {return {}}
    set result {};foreach key {canonical_unit to_canonical from_canonical} {dict set result $key [dict get $source $key]}
    return $result
}
proc ::GX::_datasetCoordinateDefaults {source} {
    return [dict create source $source display_unit [dict get $source unit] view_factor 1.0 view_pivot 0.0 calibration_factor 1.0 input_origin 0.0 output_origin 0.0]
}
proc ::GX::_datasetCoordinateVariable {variable settings} {
    _datasetCoordinateFields $settings {source display_unit view_factor view_pivot calibration_factor input_origin output_origin} {coordinate Variable}
    set source [_datasetCoordinateSource $variable]
    _datasetCoordinateFields [dict get $settings source] [dict keys $source] {coordinate source}
    dict for {key value} $source {
        if {[dict get $settings source $key] ne $value} {error "Coordinate source schema changed for [dict get $variable variable_id] ($key); reset or explicitly redefine the settings"}
    }
    foreach key {view_factor view_pivot calibration_factor input_origin output_origin} {
        set value [_unitFiniteValue [dict get $settings $key]]
        if {$key in {view_factor calibration_factor}&&$value<=0} {error "$key must be positive"}
        dict set settings $key $value
    }
    set display [dict get $settings display_unit];set unit [dict get $source unit]
    if {$display ne $unit} {
        if {$display eq {}||$unit eq {}} {error {Declare a source unit before choosing a different display unit}}
        unitRegistryConversionPlan $unit $display [_datasetCoordinateOverride $source]
    }
    return $settings
}
proc ::GX::_datasetCoordinateStored {session id} {
    variable ::GX::DatasetCoordinates::key
    if {[datasetField $id storage_provider {}] eq "remote"} {return [datasetField $id remote_coordinate_context {}]}
    set metadata [_datasetMetadataReadAll $session $id]
    if {![dict exists $metadata $key]} {return {}}
    set value [dict get $metadata $key]
    if {[string bytelength $value]>1048576} {error {Coordinate context exceeds bounded storage}}
    return $value
}
proc ::GX::_datasetCoordinateRevision {stored} {
    if {$stored eq {}} {return 0}
    set revision [dict get $stored revision]
    if {![string is entier -strict $revision]||$revision<1||$revision>=9007199254740991} {error {Invalid coordinate revision}}
    return $revision
}
proc ::GX::_datasetCoordinateValidate {id context sha} {
    _datasetCoordinateFields $context {schema_version revision source_sha256 variables} {coordinate context}
    if {[dict get $context schema_version] ne "1"} {error {Unsupported coordinate context schema}}
    _datasetCoordinateRevision $context
    if {[dict get $context source_sha256] ne $sha} {error {Coordinate source payload changed; reset or explicitly redefine the settings}}
    if {[dict size [dict get $context variables]]>1024} {error {Coordinate context supports at most 1024 configured Variables}}
    dict for {vid settings} [dict get $context variables] {
        dict set context variables $vid [_datasetCoordinateVariable [datasetVariableV3ById $id $vid] $settings]
    }
    return $context
}
proc ::GX::datasetCoordinateValidate {session id context} {
    set payload [sessionInspectionDatasetPayload $id $session]
    return [_datasetCoordinateValidate $id $context [dict get $payload sha256]]
}
proc ::GX::_datasetCoordinateResolved {id context} {
    set result [dict merge $context [dict create dataset_id $id persistent [expr {[dict get $context revision]>0}]]]
    # Return all real numeric Variables, while persisting only configured ones.
    # Names and labels are not identities and are deliberately not stored here.
    foreach variable [datasetVariableSchemaV3 $id] {
        set vid [dict get $variable variable_id]
        if {[catch {set source [_datasetCoordinateSource $variable]}]} continue
        if {![dict exists $result variables $vid]} {dict set result variables $vid [_datasetCoordinateDefaults $source]}
    }
    return $result
}
proc ::GX::datasetCoordinateRead {session id} {
    set payload [sessionInspectionDatasetPayload $id $session]
    set sha [dict get $payload sha256];set stored [_datasetCoordinateStored $session $id]
    if {$stored eq {}} {set context [dict create schema_version 1 revision 0 source_sha256 $sha variables {}]} else {set context [_datasetCoordinateValidate $id $stored $sha]}
    return [_datasetCoordinateResolved $id $context]
}
proc ::GX::datasetCoordinateInspect {session id} {
    # Diagnostics permit an explicit reset after a legitimate source/schema
    # revision. Applying settings always goes through the strict read above.
    set stored [_datasetCoordinateStored $session $id]
    set revision [_datasetCoordinateRevision $stored]
    if {[catch {set context [datasetCoordinateRead $session $id]} reason]} {
        return [dict create dataset_id $id revision $revision status stale reason $reason]
    }
    return [dict create dataset_id $id revision $revision status [expr {$revision?"current":"identity"}] reason {} context $context]
}
proc ::GX::_datasetCoordinateWrite {session id context} {
    if {[string bytelength $context]>1048576} {error {Coordinate context exceeds bounded storage}}
    if {$::GX::DatasetPrivate::activeContext ne {}} {_datasetNamespaceRequireModuleWrite $session [dict get $::GX::DatasetPrivate::activeContext module_id] $id}
    _datasetFrameworkMetadataUpdate $session $id [dict create coordinate_context_v1 $context]
    return [_datasetCoordinateResolved $id $context]
}
proc ::GX::_datasetCoordinateExpected {stored expected} {
    set current [_datasetCoordinateRevision $stored]
    if {![string is entier -strict $expected]||$expected<0||$expected!=$current} {error {Coordinate context changed; reload before saving}}
    return $current
}
proc ::GX::_datasetCoordinateSchemaRebind {session id prior} {
    # Called ONLY by the schema owner's successful source-verified regeneration.
    # Cosmetic names / enabled columns may change CSV bytes. Numeric parsing,
    # unit and dtype changes must instead leave an explicitly stale context.
    if {$prior eq {}||![dict get $prior revision]} {return}
    set next [dict remove $prior dataset_id persistent]
    dict for {vid settings} [dict get $next variables] {
        if {[catch {_datasetCoordinateVariable [datasetVariableV3ById $id $vid] $settings}]} {return}
    }
    set sha [dict get [sessionInspectionDatasetPayload $id $session] sha256]
    if {$sha eq [dict get $next source_sha256]} {return}
    dict set next source_sha256 $sha
    dict incr next revision
    _datasetCoordinateWrite $session $id $next
}
proc ::GX::datasetCoordinateUpdate {session id updates expectedRevision} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetCoordinateUpdate $session $id $updates $expectedRevision]}
    set context [datasetCoordinateRead $session $id]
    _datasetCoordinateExpected [_datasetCoordinateStored $session $id] $expectedRevision
    if {[dict size $updates]>1024} {error {Coordinate update exceeds Variable limit}}
    # Keep only explicitly configured Variables, with identity defaults for new ones.
    set stored [_datasetCoordinateStored $session $id]
    set variables [expr {$stored eq {}?{}:[dict get $stored variables]}]
    dict for {vid fields} $updates {
        if {![dict exists $context variables $vid]} {error "Unknown or nonnumeric coordinate Variable '$vid'"}
        foreach field [dict keys $fields] {if {$field ni {display_unit view_factor view_pivot calibration_factor input_origin output_origin}} {error "Unknown editable coordinate field '$field'"}}
        dict set variables $vid [_datasetCoordinateVariable [datasetVariableV3ById $id $vid] [dict merge [dict get $context variables $vid] $fields]]
    }
    set next [dict create schema_version 1 revision [expr {$expectedRevision+1}] source_sha256 [dict get $context source_sha256] variables $variables]
    _datasetCoordinateValidate $id $next [dict get $context source_sha256]
    return [_datasetCoordinateWrite $session $id $next]
}
proc ::GX::datasetCoordinateReset {session id expectedRevision} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetCoordinateReset $session $id $expectedRevision]}
    set payload [sessionInspectionDatasetPayload $id $session]
    _datasetCoordinateExpected [_datasetCoordinateStored $session $id] $expectedRevision
    return [_datasetCoordinateWrite $session $id [dict create schema_version 1 revision [expr {$expectedRevision+1}] source_sha256 [dict get $payload sha256] variables {}]]
}
proc ::GX::_datasetCoordinateValues {settings values mode target direction} {
    if {$mode ni {canonical effective}||$direction ni {forward inverse}} {error {Coordinates require canonical/effective mode and forward/inverse direction}}
    if {[llength $values]>4096} {error {Coordinate presentation accepts at most 4096 values; use Dataset Transform for materialization}}
    set source [dict get $settings source];set sourceUnit [dict get $source unit]
    if {$target eq "source"} {set unit $sourceUnit} elseif {$target eq "display"} {set unit [dict get $settings display_unit]} else {set unit $target}
    set override [_datasetCoordinateOverride $source]
    set result {};foreach value $values {lappend result [_unitFiniteValue $value]}
    if {$direction eq "inverse"&&$unit ne $sourceUnit} {
        # Inverse of the SAME variable-specific relation; the global symbol's
        # inverse must not replace a declared per-variable calibration relation.
        set plan [unitRegistryConversionPlan $sourceUnit $unit $override]
        set a [dict get $plan source_definition];set b [dict get $plan target_definition]
        set forward [expr {[dict get $b canonical_unit] eq {}?"x":[dict get $b to_canonical]}]
        set inverse [expr {[dict get $a canonical_unit] eq {}?"x":[dict get $a from_canonical]}]
        set ratio [dict get $plan base_scale_ratio];set converted {}
        foreach value $result {
            set canonical [unitFormulaEvaluate $forward $value]
            lappend converted [unitFormulaEvaluate $inverse [_unitFiniteValue [expr {$canonical/$ratio}]]]
        }
        set result $converted
    }
    if {$mode eq "effective"} {
        set factor [dict get $settings calibration_factor];set origin [dict get $settings input_origin];set output [dict get $settings output_origin]
        set converted {}
        # Exact identity must preserve signed zero and values near a large
        # common origin; subtract/add would introduce avoidable cancellation.
        foreach value [expr {$factor==1&&$origin==$output?{}:$result}] {
            if {$direction eq "forward"} {set value [expr {$output+$factor*($value-$origin)}]} else {set value [expr {$origin+($value-$output)/$factor}]}
            lappend converted [_unitFiniteValue $value]
        }
        if {$factor!=1||$origin!=$output} {set result $converted}
    }
    if {$direction eq "forward"&&$unit ne $sourceUnit} {set result [unitRegistryConvertValues $sourceUnit $unit $result $override]}
    return [dict create values $result unit [expr {$direction eq "inverse"?$sourceUnit:$unit}] coordinate_mode $mode direction $direction]
}
proc ::GX::datasetCoordinateValues {session id vid values {options {}}} {
    set result [datasetCoordinateSnapshotValues [datasetCoordinateRead $session $id] $vid $values $options]
    dict set result verification source_verified
    return $result
}
proc ::GX::_datasetCoordinateSnapshotSettings {context vid} {
    # Pure presentation of an explicit captured context. This never asserts
    # that a current Dataset or its payload still matches the snapshot.
    if {[string bytelength $context]>1048576} {error {Coordinate snapshot exceeds bounded presentation storage}}
    _datasetCoordinateFields $context {schema_version revision source_sha256 variables dataset_id persistent} {resolved coordinate snapshot}
    if {[dict get $context schema_version] ne "1"||![regexp {^[a-fA-F0-9]{64}$} [dict get $context source_sha256]]||[dict get $context dataset_id] eq {}} {error {Invalid coordinate snapshot identity}}
    set revision [dict get $context revision]
    if {![string is entier -strict $revision]||$revision<0||$revision>=9007199254740991||![string is boolean -strict [dict get $context persistent]]||!![dict get $context persistent]!=($revision>0)} {error {Invalid coordinate snapshot revision}}
    if {![dict exists $context variables $vid]} {error "Unknown or nonnumeric coordinate Variable '$vid'"}
    set settings [dict get $context variables $vid]
    return [_datasetCoordinateVariable [dict merge [dict get $settings source] [dict create variable_id $vid]] $settings]
}
proc ::GX::_datasetCoordinatePresentationSettings {context vid options} {
    foreach key [dict keys $options] {if {$key ni {mode unit direction source_unit_assumption}} {error "Unknown coordinate presentation option '$key'"}}
    set settings [_datasetCoordinateSnapshotSettings $context $vid]
    if {[dict exists $options source_unit_assumption]} {
        set assumption [dict get $options source_unit_assumption]
        if {[dict get $settings source unit] ne {}} {error {A source-unit assumption cannot override a declared source unit}}
        if {$assumption eq {}||[string length $assumption]>256} {error {A source-unit assumption requires a nonempty registered physical unit}}
        set definition [unitRegistryDefinition $assumption]
        if {[dict get $definition conversion_kind] eq "opaque"} {error {An opaque unit cannot define a physical source-unit assumption}}
        # Interpretation of explicitly undeclared source numbers only. The
        # captured context and canonical Dataset schema remain untouched.
        dict set settings source unit $assumption
        foreach field {canonical_unit to_canonical from_canonical} {dict set settings source $field [dict get $definition $field]}
        dict set settings display_unit $assumption
    }
    return $settings
}
proc ::GX::datasetCoordinateSnapshotValues {context vid values {options {}}} {
    set settings [_datasetCoordinatePresentationSettings $context $vid $options]
    set result [_datasetCoordinateValues $settings $values [datasetPublicationV2DictDefault $options mode canonical] [datasetPublicationV2DictDefault $options unit display] [datasetPublicationV2DictDefault $options direction forward]]
    if {[dict exists $options source_unit_assumption]} {dict set result source_unit_assumption [dict get $options source_unit_assumption]}
    return [dict merge $result [dict create dataset_id [dict get $context dataset_id] variable_id $vid revision [dict get $context revision] source_sha256 [dict get $context source_sha256] verification snapshot_only]]
}
proc ::GX::datasetCoordinateViewRange {session id vid referenceRange} {
    set result [datasetCoordinateSnapshotViewRange [datasetCoordinateRead $session $id] $vid $referenceRange]
    dict set result verification source_verified
    return $result
}
proc ::GX::datasetCoordinateSnapshotViewRange {context vid referenceRange} {
    if {[llength $referenceRange]!=2} {error {Reference range requires two canonical endpoints}}
    lassign $referenceRange lower upper
    set lower [_unitFiniteValue $lower];set upper [_unitFiniteValue $upper]
    if {$lower>=$upper} {error {Reference range must be increasing}}
    set settings [_datasetCoordinateSnapshotSettings $context $vid]
    set pivot [dict get $settings view_pivot];set factor [dict get $settings view_factor]
    if {$factor==1} {set range [list $lower $upper]} else {
        set range [list [_unitFiniteValue [expr {$pivot+($lower-$pivot)/$factor}]] [_unitFiniteValue [expr {$pivot+($upper-$pivot)/$factor}]]]
    }
    if {[lindex $range 0]>=[lindex $range 1]} {error {Magnification collapses the representable viewport}}
    return [dict create dataset_id [dict get $context dataset_id] variable_id $vid revision [dict get $context revision] source_sha256 [dict get $context source_sha256] verification snapshot_only canonical_range $range source_unit [dict get $settings source unit] view_factor $factor view_pivot $pivot reference_range [list $lower $upper]]
}
proc ::GX::datasetCoordinateSnapshotAffinePlan {context vid nativeUnit {options {}}} {
    set settings [_datasetCoordinatePresentationSettings $context $vid $options]
    set mode [datasetPublicationV2DictDefault $options mode canonical];set direction [datasetPublicationV2DictDefault $options direction forward]
    if {$mode ni {canonical effective}||$direction ni {forward inverse}} {error {Coordinates require canonical/effective mode and forward/inverse direction}}
    set source [dict get $settings source];set unit [dict get $source unit]
    set target [datasetPublicationV2DictDefault $options unit display]
    if {$target eq "display"} {set target [dict get $settings display_unit]} elseif {$target eq "source"} {set target $unit}
    if {$direction eq "forward"} {set from $nativeUnit;set to $target} else {set from $target;set to $nativeUnit}
    set result [dict create dataset_id [dict get $context dataset_id] variable_id $vid revision [dict get $context revision] source_sha256 [dict get $context source_sha256] verification snapshot_only coordinate_mode $mode direction $direction input_unit $from output_unit $to]
    if {[dict exists $options source_unit_assumption]} {dict set result source_unit_assumption [dict get $options source_unit_assumption]}
    set override [_datasetCoordinateOverride $source]
    set first {affine 1 scale 1.0 offset 0.0};set last $first
    if {$from ne $unit} {set first [unitRegistryAffinePlan $unit $from $override inverse]}
    if {$to ne $unit} {set last [unitRegistryAffinePlan $unit $to $override]}
    if {![dict get $first affine]||![dict get $last affine]} {return [dict merge $result {affine 0 reason {Declared coordinate relation requires pointwise conversion}}]}
    set scale [dict get $first scale];set offset [dict get $first offset]
    if {[catch {
        if {$mode eq "effective"} {
            set f [dict get $settings calibration_factor];set a [dict get $settings input_origin];set b [dict get $settings output_origin]
            if {$f!=1||$a!=$b} {
                if {$direction eq "forward"} {set scale [_unitFiniteValue [expr {$scale*$f}]];set offset [_unitFiniteValue [expr {$b+$f*($offset-$a)}]]} else {set scale [_unitFiniteValue [expr {$scale/$f}]];set offset [_unitFiniteValue [expr {$a+($offset-$b)/$f}]]}
            }
        }
        set scale [_unitFiniteValue [expr {$scale*[dict get $last scale]}]]
        set offset [_unitFiniteValue [expr {$offset*[dict get $last scale]+[dict get $last offset]}]]
        if {$scale==0} {error {Collapsed finite coordinate coefficient}}
    } reason]} {return [dict merge $result [dict create affine 0 reason "Finite affine coefficients unavailable: $reason"]]}
    return [dict merge $result [dict create affine 1 scale $scale offset $offset reason {}]]
}
