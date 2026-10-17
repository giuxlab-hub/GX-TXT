# SPDX-License-Identifier: GPL-3.0-or-later
# GX-TXT dev097 retained-covariance bridge, adapted to Curve Digitizer 2.0.
# The exact public CORE validation is intentionally kept at this boundary.
source [file join [file dirname [info script]] curve_digitizer_factor_guard.tcl]

proc ::GX::CurveDigitizerCompanion::validateUncertaintyBinding {binding} {
    if {![dict exists $binding schema] ||
        [dict get $binding schema] ne "gxtxt.digitizer_publication_binding.v1" ||
        ![regexp {^[a-f0-9]{64}$} [dict get $binding payload_sha256]]} {
        error {Invalid retained digitization publication identity}
    }
    set n [dict get $binding point_count]
    if {![string is integer -strict $n] || $n<1 || $n>4096} {error {Invalid retained digitization point count}}
    set resources [dict get $binding resources]
    foreach role {configuration points state values interpretation} {
        ::GX::interactiveDocumentResourceInfo [dict get $resources $role]
    }
    set reference [dict get $resources interpretation]
    if {[dict get $reference size_bytes]>1048576 ||
        [dict get $reference metadata format] ne "gxtxt.digitization_interpretation.tcldict.v1"} {
        error {Invalid retained digitization meaning resource}
    }
    set meaning [encoding convertfrom utf-8 [::GX::interactiveDocumentResourceReadChunk \
        $reference 0 [dict get $reference size_bytes]]]
    ::GX::StatisticsV1::validate $meaning
    if {[dict get $meaning schema] ne "gxtxt.digitization_interpretation.v1" ||
        [dict get $meaning summary point_count]!=$n ||
        [dict get $meaning context source_document_sha256] ne [dict get $resources configuration sha256] ||
        [dict get $meaning context point_ids_sha256] ne [dict get $resources points sha256] ||
        [dict get $resources values size_bytes]!=40*$n} {
        error {Retained digitization meaning lost its point/calibration binding}
    }
    foreach key {x_variable_id y_variable_id sigma_x_variable_id sigma_y_variable_id point_id_variable_id} {
        if {[dict get $binding $key] eq {}} {error {Retained digitization variable identity is missing}}
    }
    return $meaning
}

proc ::GX::CurveDigitizerCompanion::publicationUncertainty {dataset} {
    set metadata [::GX::datasetMetadataRead [_requireSession] $dataset]
    if {![dict exists $metadata curve_digitizer.uncertainty_binding]} {return {}}
    set binding [dict get $metadata curve_digitizer.uncertainty_binding]
    set meaning [validateUncertaintyBinding $binding]
    set identity [::GX::curveSourceDatasetIdentity [_requireSession] $dataset]
    if {[dict get $binding dataset_id] ne $dataset ||
        [dict get $binding payload_sha256] ne [dict get $identity sha256]} {
        error {Digitizer Dataset bytes changed after uncertainty publication}
    }
    set schema {}
    foreach variable [::GX::datasetVariableSchemaV3 $dataset] {
        dict set schema [dict get $variable variable_id] $variable
    }
    lassign [dict get $meaning summary coordinate_units] ux uy
    foreach {field unit} [list x_variable_id $ux y_variable_id $uy sigma_x_variable_id $ux sigma_y_variable_id $uy] {
        set variable [dict get $schema [dict get $binding $field]]
        if {![dict get $variable enabled] || [dict get $variable unit] ne $unit ||
            [dict get $variable rank]!=1} {
            error {Digitizer Variable units, availability or shape changed}
        }
    }
    set covarianceUnit [::GX::CurveDigitizerNumericCore::covarianceUnit $ux $uy]
    if {![dict exists $metadata curve_digitizer.uncertainty_covariance_xy_unit] ||
        [dict get $metadata curve_digitizer.uncertainty_covariance_xy_unit] ne $covarianceUnit ||
        ![dict exists $schema covariance_xy] ||
        ![dict get $schema covariance_xy enabled] ||
        [dict get $schema covariance_xy rank] != 1 ||
        [dict get $schema covariance_xy unit] ne $covarianceUnit} {
        error {Published XY covariance Variable Schema unit differs from the reviewed physical X*Y unit}
    }
    return [dict create binding $binding meaning $meaning source_identity $identity]
}

# Reconstruct typed state using the exact public NUMERIC_API_v1 operation
# schema, not private Octave/MAT files. This is a narrow, documented adapter:
# gxtxt.digitization_uncertainty.v1 outputs from Numeric/CORE are authoritative.
proc ::GX::CurveDigitizerCompanion::_uncertaintyNumericStateNode {state} {
    set numericFields {point_count coordinates standard_uncertainty independent_standard_uncertainty covariance_blocks independent_factor shared_factor pixel_scale pixel_standard_uncertainty calibration_standard_uncertainty override_standard_uncertainty maximum_absolute_xy_correlation correlation_roundoff_tolerance}
    set cellFields {coordinate_units calibration_ids calibration_units}
    proc ::GX::CurveDigitizerCompanion::_digitizationTypeNode {key value} {
        set cellFields {coordinate_units calibration_ids calibration_units}
        set numbers {point_count calibration_input_count maximum_absolute_xy_correlation correlation_roundoff_tolerance pixel_scale pixel_standard_uncertainty calibration_standard_uncertainty override_standard_uncertainty coordinates standard_uncertainty independent_standard_uncertainty covariance_blocks independent_factor shared_factor}
        if {$key in $cellFields} {
            set items {};foreach v $value {lappend items [::GX::ScientificTransportv1::text $v]}
            return [dict create kind cell items $items]
        }
        if {$key in $numbers || [string match has_* $key]} {
            # Numeric matrices arrive from the public result with row-major
            # Tcl lists. Typed scientific input is column-major by contract.
            set first [lindex $value 0]
            if {$key in {coordinates standard_uncertainty independent_standard_uncertainty covariance_blocks independent_factor shared_factor override_standard_uncertainty}} {
                if {[llength $first]>1 && [llength $value]>0} {
                    set rows [llength $value];set cols [llength $first];set flat {}
                    for {set c 0} {$c<$cols} {incr c} {
                        foreach row $value {if {[llength $row]!=$cols} {error {Numeric state matrix shape changed}};lappend flat [lindex $row $c]}
                    }
                    return [::GX::ScientificTransportv1::array [list $rows $cols] $flat]
                }
            }
            if {[llength $value]==0} {error {Empty Numeric state array}}
            return [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]
        }
        if {$key in {summary declaration}} {
            set fields {}
            dict for {subkey subval} $value {dict set fields $subkey [_digitizationTypeNode $subkey $subval]}
            return [::GX::ScientificTransportv1::struct $fields]
        }
        return [::GX::ScientificTransportv1::text $value]
    }
    set fields {};dict for {name value} $state {dict set fields $name [_digitizationTypeNode $name $value]}
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::CurveDigitizerCompanion::publishCovariance {dataset target axis} {
    set capture [publicationUncertainty $dataset]
    if {$capture eq {} || $axis ni {x y}} {error {Choose a reviewed digitizer Dataset and physical X or Y covariance}}
    set meaning [dict get $capture meaning]
    set n [dict get $meaning summary point_count]
    if {$n>512} {error {Full response covariance is bounded to 512 original points}}
    set orientation [expr {$axis eq "y" ? "y_of_x" : "x_of_y"}]
    set plan [::GX::StatisticsV1::digitizationFitPlan $meaning full_response_covariance $orientation]
    if {[dict get $plan status] ne {value}} {error "Public CORE Fitter plan disallows full covariance: [dict get $plan reason]"}
    set unit [dict get $meaning columns sigma_$axis unit];set squared "$unit*$unit"
    set conversion [::GX::unitRegistryDifferentialRatioPlan $squared $unit $unit]
    if {[dict get $conversion status] ne "value" || abs([dict get $conversion scale]-1)>1e-14} {
        error {The Unit Registry cannot validate squared physical response units}
    }
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set ref [dict get $capture binding resources state]
    if {[dict get $ref metadata format] ne {gxtxt.digitization_numeric_state.tcldict.v1} ||
        [dict get $ref size_bytes]>8388608} {error {Unknown or oversized CORE numeric state resource}}
    set stateBytes {}
    for {set offset 0} {$offset<[dict get $ref size_bytes]} {incr offset 65536} {
        append stateBytes [::GX::interactiveDocumentResourceReadChunk $ref $offset \
            [expr {min(65536,[dict get $ref size_bytes]-$offset)}]]
    }
    set state [encoding convertfrom utf-8 $stateBytes]
    if {[dict get $state state_sha256] ne [dict get $meaning summary state_sha256]} {error {CORE Numeric state changed after review}}
    set node [_uncertaintyNumericStateNode $state]
    # This public Numeric operation owns its solver invocation and scientific
    # result transport. We never call Octave, build MAT files or manage a work dir.
    set result [::GX::NumericAPIv1::callOperation digitization_covariance \
        [list $node [::GX::ScientificTransportv1::text $axis]]]
    if {[dict get $result source_state_sha256] ne [dict get $meaning summary state_sha256] ||
        [dict get $result point_count]!=$n ||
        [publicationUncertainty $dataset] ne $capture} {
        error {Public Numeric covariance result changed identity}
    }
    set matrix [dict get $result covariance]
    if {[llength $matrix]!=$n} {error {Invalid CORE covariance matrix row count}}
    # Serialise column-major float64 into a managed resource via the public
    # writer. Scientific files and temporary artifacts belong to GX-TXT CORE.
    set document [dict get $meaning context source_document_id]
    set writer [::GX::interactiveDocumentResourceOpenWriter $document [dict create \
        format gxtxt.numeric_array_le.v1 dtype float64 endian little order F shape [list $n $n] unit $squared]]
    try {
        for {set c 0} {$c<$n} {incr c} {
            set col {}
            foreach row $matrix {
                if {[llength $row]!=$n} {error {CORE covariance matrix column count changed}}
                lappend col [lindex $row $c]
            }
            ::GX::interactiveDocumentResourceAppend $writer [binary format q* $col]
        }
        set resource [::GX::interactiveDocumentResourceFinalize $writer]
        set writer {}
    } finally {if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
    set variables [list [dict create variable_id covariance schema \
        [dict create dtype float64 dimension_ids {source_row;source_column} unit $squared] resource $resource]]
    set published [::GX::datasetPublicationV2PublishManagedVariables $::GX::currentSession \
        viewer.curve_digitizer [dict create dataset_id $target contract table.generic \
        storage hdf5 producer_version 2.0.3 source_dataset_ids [list $dataset] \
        provenance {Original point order; public Numeric response-only covariance. Predictor uncertainty is excluded}] \
        [dict create source_row $n source_column $n] $variables]
    set binding [dict create schema gxtxt.digitizer_covariance_binding.v1 \
        source [dict get $capture binding] source_identity [dict get $capture source_identity] \
        axis $axis variable_id covariance resource $resource fit_plan $plan \
        covariance_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $target]]
    ::GX::datasetMetadataUpdate $::GX::currentSession $target [dict create curve_digitizer.covariance_binding $binding]
    return $published
}

proc ::GX::CurveDigitizerCompanion::covariancePublication {dataset} {
    set metadata [::GX::datasetMetadataRead [_requireSession] $dataset]
    if {![dict exists $metadata curve_digitizer.covariance_binding]} {return {}}
    set binding [dict get $metadata curve_digitizer.covariance_binding]
    set meaning [validateUncertaintyBinding [dict get $binding source]]
    if {[dict get $binding schema] ne "gxtxt.digitizer_covariance_binding.v1" ||
        [::GX::curveSourceDatasetIdentity [_requireSession] $dataset] ne [dict get $binding covariance_identity]} {
        error {Published digitizer covariance identity changed}
    }
    ::GX::interactiveDocumentResourceInfo [dict get $binding resource]
    set orientation [expr {[dict get $binding axis] eq "y" ? "y_of_x" : "x_of_y"}]
    if {[::GX::StatisticsV1::digitizationFitPlan $meaning full_response_covariance $orientation] ne [dict get $binding fit_plan]} {
        error {Published digitizer covariance interpretation changed}
    }
    return $binding
}
