# Complex source declarations and captured transport; Numeric/CORE own science.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_complexRecipeNode {recipe} {
    foreach key [dict keys $recipe] {if {$key ni {predictor_id predictor_unit channels parameters}} {error "Unknown complex recipe field: $key"}}
    set fields {};foreach key {predictor_id predictor_unit} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $recipe $key]]}
    set channels {}
    foreach channel [dict get $recipe channels] {
        set item {}
        foreach key [dict keys $channel] {if {$key ni {id unit real_expression imaginary_expression}} {error "Unknown complex channel field: $key"}}
        foreach key {id unit real_expression imaginary_expression} {dict set item $key [::GX::ScientificTransportv1::text [dict get $channel $key]]}
        lappend channels [::GX::ScientificTransportv1::struct $item]
    }
    dict set fields channels [dict create kind cell items $channels]
    # Reuse the existing parameter-node owner; dummy expression fields are data
    # placeholders only and never compiled or used as a scientific declaration.
    set parameterNode [_formulaRecipeNode [dict create expression {} predictor_ids {} predictor_units {} response_unit {} parameters [dict get $recipe parameters]]]
    dict set fields parameters [dict get $parameterNode fields parameters]
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_resolveComplex {recipe} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [::GX::NumericAPIv1::callOperation complex_model_compose [list [_complexRecipeNode $recipe]]]
}
proc ::GX::DatasetCurveFit::_complexData {options} {
    set data [dict get $options complex_data]
    foreach key [dict keys $data] {if {$key ni {channels covariance display}} {error "Unknown complex source field: $key"}}
    set channels [dict get $data channels]
    if {[llength $channels]<1||[llength $channels]>3} {error {Bind one to three physical complex channels}}
    foreach channel $channels {
        foreach key [dict keys $channel] {if {$key ni {channel_id representation first_variable_id second_variable_id phase_unit reference}} {error "Unknown complex observation field: $key"}}
        foreach key {channel_id representation first_variable_id second_variable_id} {if {[dict get $channel $key] eq {}} {error "Complex channel requires $key"}}
        set representation [dict get $channel representation]
        if {$representation ni {cartesian polar_linear polar_db20}} {error {Choose Cartesian, linear amplitude/phase or db20 amplitude/phase observations}}
        if {$representation eq "cartesian"} {
            if {[dict exists $channel phase_unit]||[dict exists $channel reference]} {error {Cartesian channels cannot acquire a phase unit or amplitude reference}}
        } else {
            if {[dict get $channel phase_unit] ni {rad deg}} {error {Polar observations need explicit rad or deg phase units}}
            if {$representation eq "polar_db20"} {
                if {[_finite [dict get $channel reference] {Physical amplitude reference}]<=0} {error {db20 amplitude reference must be positive}}
            } elseif {[dict exists $channel reference]} {error {Linear amplitude does not use a dB reference}}
        }
    }
    set display [dict get $data display]
    foreach key [dict keys $display] {if {$key ni {channel_id projection reference}} {error "Unknown complex display field: $key"}}
    if {[dict get $display projection] ni {real imaginary magnitude db20}} {error {Choose a real, imaginary, magnitude or db20 physical display projection}}
    if {[dict get $display projection] eq "db20"} {
        set reference [dict get $display reference]
        if {[lsort [dict keys $reference]] ne {unit value}||[_finite [dict get $reference value] {Display amplitude reference}]<=0||[dict get $reference unit] eq {}} {error {db20 display requires a positive physical reference and its channel unit}}
    } elseif {[dict exists $display reference]} {error {A linear display cannot acquire a dB reference}}
    set covariance [dict get $data covariance]
    if {[dict get $covariance layout] eq "shared"} {
        set allowed {layout values component_units}
        set m [expr {2*[llength $channels]}];set rows [dict get $covariance values]
        if {[llength $rows]!=$m} {error {Shared Cartesian covariance must have one row per real/imaginary component}}
        foreach row $rows {if {[llength $row]!=$m} {error {Shared Cartesian covariance must be square}};foreach value $row {_finite $value {Cartesian covariance entry}}}
    } elseif {[dict get $covariance layout] eq "per_observation"} {
        set allowed {layout dataset_id variable_id source_dataset_id row_binding component_units}
        foreach key {dataset_id variable_id source_dataset_id} {if {[dict get $covariance $key] eq {}} {error "Per-observation covariance requires $key"}}
        if {[dict get $covariance row_binding] ne "original_source_rows"} {error {Covariance third axis must identify every original source row}}
    } else {error {Cartesian covariance layout must be shared or per_observation}}
    foreach key [dict keys $covariance] {if {$key ni $allowed} {error "Unknown complex covariance field: $key"}}
    if {[llength [dict get $covariance component_units]]!=2*[llength $channels]} {error {Declare covariance component units in real/imaginary channel order}}
    return $data
}
proc ::GX::DatasetCurveFit::_prepareComplex {w options} {
    variable state
    if {$state($w,sourceKind) ne "dataset"||$state($w,sourceToken) eq {}||[_fitOrientation complex_response $options] ne "y_of_x"} {error {Complex responses require an exact Dataset source with physical frequency on X}}
    set source [_sourceProvenance $w];set axes [dict get $source source_axes]
    set recipe [dict get $options complex_recipe];set data [_complexData $options]
    if {[dict get $recipe predictor_unit] ne [dict get $axes x unit]} {error {Complex frequency unit must match the physical source X unit}}
    if {[_smoothContext $source] ne {}||[_baselineContext $source] ne {}||[_logContext $source y_of_x] ne {}} {error {Complex observations require their original declared physical channels, without unpropagated smoothing, baseline or log transforms}}
    if {$state($w,sourceTransformManifest) ne {}&&[dict get $state($w,sourceTransformManifest) operation] ne "reverse_sequence"} {error {This source transform has no declared complex covariance propagation contract}}
    foreach axis {u v} {set t [::GX::datasetPublicationV2DictDefault $options translation_$axis {mode off delta 0}];if {[dict get $t mode] ne "off"||[dict get $t delta]!=0} {error {Complex frequency responses require physical coordinates with translation off}}}
    if {[dict get [_measurementOptions $options] kind] ne "none"||[::GX::datasetPublicationV2DictDefault $options covariance {}] ne {}} {error {Complex Cartesian covariance cannot be combined with separate scalar or XY measurement weights}}
    if {[::GX::datasetPublicationV2DictDefault $options prediction_band none] ne "none"||[::GX::datasetPublicationV2DictDefault $options bootstrap {}] ne {}||[::GX::datasetPublicationV2DictDefault $options influence_diagnostics 0]} {error {Complex response bands, bootstrap and scalar influence require separately declared inference contracts}}
    if {[::GX::datasetPublicationV2DictDefault $options noise_model unspecified] ni {unspecified independent_gaussian_known_sigma}} {error {Declare unspecified or Gaussian independent innovations under the absolute Cartesian covariance}}
    set model [_resolveComplex $recipe]
    set ids {};set units {}
    foreach channel [dict get $data channels] physical [dict get $recipe channels] {
        if {$channel eq {}||$physical eq {}||[dict get $channel channel_id] ne [dict get $physical id]} {error {Observation channels must match the ordered physical model identities}}
        lappend ids [dict get $physical id];lappend units [dict get $physical unit] [dict get $physical unit]
    }
    if {$units ne [dict get $data covariance component_units]} {error {Covariance component units differ from the ordered physical model}}
    set selected [lsearch -exact $ids [dict get $data display channel_id]]
    if {$selected<0} {error {Choose a physical channel declared by this model}}
    set unit [dict get [lindex [dict get $recipe channels] $selected] unit]
    if {[dict get $data display projection] eq "db20"} {
        if {[dict get $data display reference unit] ne $unit} {error {Display reference unit differs from its physical channel}}
        set unit dB
    }
    if {[dict get $axes y unit] ne $unit} {error {The displayed source Y unit must match the selected complex projection; choose or explicitly convert the source Variable}}
    return $model
}
proc ::GX::DatasetCurveFit::_complexCompanions {key model options} {
    if {$model ne "complex_response"} {return {}}
    set data [_complexData $options];set result {};set index 0
    foreach channel [dict get $data channels] {
        incr index
        dict set result complex_${index}_first [dict get $channel first_variable_id]
        dict set result complex_${index}_second [dict get $channel second_variable_id]
    }
    return $result
}
proc ::GX::DatasetCurveFit::_complexBinding {key options input} {
    variable state
    set data [_complexData $options];set recipe [dict get $options complex_recipe];set preprocessing [dict get $input preprocessing]
    set n [dict get $preprocessing original_count]
    if {[dict get $preprocessing row_identity_kind] ne "dataset_row"||[dict get $preprocessing original_count_status] ne "value"||$n<2||$n>65536||[dict get $input row_count]>65536} {error {Complex binding requires exact original Dataset row identities and2..65536 original rows}}
    set index 0;set bindings {}
    foreach channel [dict get $data channels] physical [dict get $recipe channels] {
        incr index;set captured $channel
        foreach part {first second} {
            set role complex_${index}_$part;set column [dict get $input companion_columns $role]
            set unit [dict get $physical unit];set representation [dict get $channel representation]
            if {$representation ne "cartesian"&&$part eq "second"} {set unit [dict get $channel phase_unit]}
            if {$representation eq "polar_db20"&&$part eq "first"} {set unit dB}
            if {[dict get $column variable_id] ne [dict get $channel ${part}_variable_id]||[dict get $column variable_descriptor unit] ne $unit} {error {Complex observations require exact channel Variable identities and declared units; convert units explicitly upstream}}
            dict set captured ${part}_descriptor [dict get $column variable_descriptor]
        }
        lappend bindings $captured
    }
    set result [dict create schema gxtxt.fit_complex_binding.v1 source_identity [_sourceProvenance $key] input_dataset_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $state($key,dataset)] original_count $n channels $bindings covariance [dict get $data covariance] display [dict get $data display] row_index_base 0 training_rows_sha256 [::GX::sha256File [dict get $input source_rows_file]]]
    if {[dict get $data covariance layout] eq "per_observation"} {
        set covariance [dict get $data covariance]
        if {[dict get $covariance source_dataset_id] ne $state($key,dataset)} {error {Complex covariance belongs to another source Dataset}}
        set handle [::GX::datasetAccessOpen $::GX::currentSession [dict get $covariance dataset_id]]
        try {
            set descriptor {};foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {if {[dict get $variable variable_id] eq [dict get $covariance variable_id]} {set descriptor $variable;break}}
            set m [expr {2*[llength $bindings]}]
            if {$descriptor eq {}||![dict get $descriptor enabled]||[dict get $descriptor dtype] ni {float32 float64}||[dict get $descriptor rank]!=3||[string map {; { }} [dict get $descriptor shape]] ne [list $m $m $n]} {error {Per-observation covariance must be a real M-by-M-by-N Variable covering every original source row}}
            if {![dict get [::GX::datasetAccessCapabilities $handle] managed_binary_read]} {error {Complex covariance requires the shared managed binary Dataset reader}}
        } finally {::GX::datasetAccessClose $handle}
        set componentUnits [dict get $covariance component_units];set unit [dict get $descriptor unit]
        if {[llength [lsort -unique $componentUnits]]==1} {
            set component [lindex $componentUnits 0];set plan [::GX::unitRegistryDifferentialRatioPlan $unit $component $component]
            if {[dict get $plan status] ne "value"||abs([dict get $plan scale]-1)>8*2.2204460492503131e-16} {error {Covariance values must already use the physical channel's squared unit}}
        } elseif {$unit ne {}} {error {Mixed-unit covariance has no single physical unit: use an unlabelled matrix with this explicit ordered component-product unit declaration}}
        dict set result covariance_variable_descriptor $descriptor
        dict set result covariance_dataset_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $covariance dataset_id]]
    }
    return $result
}
proc ::GX::DatasetCurveFit::_complexStage {binding recipe training source workspace} {
    if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding source_identity source_dataset_id]] ne [dict get $binding input_dataset_identity]} {error {Complex observation Dataset changed after binding}}
    set fields [dict create recipe [_complexRecipeNode $recipe]];set channels {};set index 0
    foreach channel [dict get $binding channels] {
        incr index;set item {}
        foreach key {channel_id representation phase_unit reference} {
            if {![dict exists $channel $key]} continue
            set value [dict get $channel $key]
            if {$key eq "reference"} {set node [::GX::ScientificTransportv1::array {1 1} [list $value]]} else {set node [::GX::ScientificTransportv1::text $value]}
            dict set item $key $node
        }
        foreach sample {training source} input [list $training $source] {
            foreach part {first second} {
                set column [dict get $input companion_columns complex_${index}_$part]
                if {[dict get $column variable_id] ne [dict get $channel ${part}_variable_id]||[dict get $column variable_descriptor] ne [dict get $channel ${part}_descriptor]} {error {Complex channel binding changed during exact input capture}}
                set path [dict get $column file]
                if {[file size $path]!=8*[dict get $input row_count]} {error {Complex channel input lost exact row alignment}}
                dict set item ${sample}_${part}_file [::GX::ScientificTransportv1::text $path]
                dict set binding input_sha256 ${sample}_${index}_$part [::GX::sha256File $path]
            }
        }
        lappend channels [::GX::ScientificTransportv1::struct $item]
    }
    dict set fields channels [dict create kind cell items $channels]
    set display [dict get $binding display];set nodes {}
    foreach key {channel_id projection} {dict set nodes $key [::GX::ScientificTransportv1::text [dict get $display $key]]}
    if {[dict exists $display reference]} {
        dict set nodes reference [::GX::ScientificTransportv1::struct [dict create value [::GX::ScientificTransportv1::array {1 1} [list [dict get $display reference value]]] unit [::GX::ScientificTransportv1::text [dict get $display reference unit]]]]
    }
    dict set fields display [::GX::ScientificTransportv1::struct $nodes]
    set covariance [dict get $binding covariance];set units {};foreach unit [dict get $covariance component_units] {lappend units [::GX::ScientificTransportv1::text $unit]}
    set measurement [dict create layout [::GX::ScientificTransportv1::text [dict get $covariance layout]] component_units [dict create kind cell items $units] semantics [::GX::ScientificTransportv1::text absolute]]
    if {[dict get $covariance layout] eq "shared"} {
        set rows [dict get $covariance values];set m [llength $rows];set values {}
        for {set column 0} {$column<$m} {incr column} {foreach row $rows {lappend values [lindex $row $column]}}
        dict set measurement covariance [::GX::ScientificTransportv1::array [list $m $m] $values]
    } else {
        if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $covariance dataset_id]] ne [dict get $binding covariance_dataset_identity]} {error {Complex covariance Dataset changed after binding}}
        set handle [::GX::datasetAccessOpen $::GX::currentSession [dict get $covariance dataset_id]];set lease {}
        try {
            set descriptor {};foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {if {[dict get $variable variable_id] eq [dict get $covariance variable_id]} {set descriptor $variable;break}}
            if {$descriptor ne [dict get $binding covariance_variable_descriptor]} {error {Complex covariance Variable changed after binding}}
            set shape [string map {; { }} [dict get $descriptor shape]]
            set response [::GX::datasetAccessReadHyperslabResource $handle [dict get $covariance variable_id] {0 0 0} $shape]
            set lease [dict get $response binary_resource];set staged [::GX::ScientificTransportv1::stageDatasetResource $lease $workspace]
            if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $covariance dataset_id]] ne [dict get $binding covariance_dataset_identity]} {error {Complex covariance Dataset changed during capture}}
            set nodes {};dict for {key value} [dict get $staged descriptor] {
                if {$key in {version count byte_count shape}} {set node [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]} else {set node [::GX::ScientificTransportv1::text $value]}
                dict set nodes $key $node
            }
            dict set fields covariance_descriptor [::GX::ScientificTransportv1::struct $nodes]
            dict set binding covariance_input_sha256 [dict get $staged sha256]
        } finally {
            try {if {$lease ne {}} {::GX::datasetAccessReleaseResource $handle [dict get $lease resource_id]}} finally {::GX::datasetAccessClose $handle}
        }
    }
    dict set fields measurement [::GX::ScientificTransportv1::struct $measurement]
    foreach sample {training source} input [list $training $source] {
        dict set fields ${sample}_rows_file [::GX::ScientificTransportv1::text [dict get $input source_rows_file]]
        dict set binding ${sample}_rows_sha256 [::GX::sha256File [dict get $input source_rows_file]]
    }
    ::GX::ScientificTransportv1::writeResult [file join $workspace complex.ini] $fields
    if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding source_identity source_dataset_id]] ne [dict get $binding input_dataset_identity]} {error {Complex observation Dataset changed during capture}}
    return $binding
}
proc ::GX::DatasetCurveFit::_complexImport {document workspace binding report} {
    if {$document eq {}} {error {Complex observations and covariance require an owned Fitter Document}}
    set facts [dict get $report numeric_statistics];set summary [dict get $facts fit complex_summary]
    dict set report train_n [dict get $summary observation_rows]
    set components [dict get $summary component_ids];set units [dict get $summary component_units];set m [llength $components]
    foreach sample {training source} raw [list [dict get $facts fit] [dict get $facts complex_evaluation]] {
        set summary [dict get $raw complex_summary];set n [dict get $summary observation_rows]
        set metadata [dict create format float64_interleaved_le dtype float64 endian little row_count $n shape [list $n $m] columns $components column_units $units role complex_physical_observations sample_role $sample]
        set file [file join $workspace complex-$sample-observations.bin]
        if {[file size $file]!=8*$n*$m} {error {Complex observation resource lost its physical shape}}
        dict set report complex_${sample}_observations_resource [::GX::interactiveDocumentResourceImportNumeric $document $file $metadata]
        dict set binding owned_sha256 ${sample}_observations [::GX::sha256File $file]
        set shape [list $m $m];if {[dict get $binding covariance layout] eq "per_observation"} {lappend shape $n}
        set count [expr {$m*$m*([llength $shape]==3?$n:1)}]
        set file [file join $workspace complex-$sample-covariance.bin]
        if {[file size $file]!=8*$count} {error {Complex covariance resource lost its physical shape}}
        set metadata [dict create format float64_column_major_le dtype float64 endian little shape $shape component_ids $components component_units $units entry_units component_unit_products role complex_cartesian_covariance sample_role $sample]
        dict set report complex_${sample}_covariance_resource [::GX::interactiveDocumentResourceImportNumeric $document $file $metadata]
        dict set binding owned_sha256 ${sample}_covariance [::GX::sha256File $file]
        dict set binding numeric_covariance_sha256 $sample [dict get $summary covariance_sha256]
    }
    dict set report complex_binding $binding
    dict set report complex_conversion [dict get $facts complex_conversion]
    return $report
}
proc ::GX::DatasetCurveFit::_complexSavedNode {p} {
    _validateComplexMetadata $p
    set physical [dict get $p complex_model_state];set display [dict get $p options complex_data display]
    set fields [dict create schema [::GX::ScientificTransportv1::text gxtxt.complex_projection_model.v1] kind [::GX::ScientificTransportv1::text complex_projection] recipe [_complexRecipeNode [dict get $physical recipe]] parameters [::GX::ScientificTransportv1::array [list [llength [dict get $physical parameters]] 1] [dict get $physical parameters]] declaration_sha256 [::GX::ScientificTransportv1::text [dict get $physical declaration_sha256]]]
    foreach key {channel_id projection} {dict set fields $key [::GX::ScientificTransportv1::text [dict get $display $key]]}
    if {[dict exists $display reference]} {dict set fields reference [::GX::ScientificTransportv1::struct [dict create value [::GX::ScientificTransportv1::array {1 1} [list [dict get $display reference value]]] unit [::GX::ScientificTransportv1::text [dict get $display reference unit]]]]}
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_validateComplexMetadata {p} {
    if {[dict get $p model] ne "complex_response"} return
    set physical [dict get $p complex_model_state];set numeric [dict get $p numeric_model_state]
    set binding [dict get $p complex_binding];set data [_complexData [dict get $p options]]
    if {[_numericStateDigest $physical] ne [dict get $p complex_model_state_sha256]} {error {Retained complex physical model changed}}
    if {[dict get $physical recipe] ne [dict get $p options complex_recipe]||[dict get $physical parameters] ne [dict get $numeric parameters]||[dict get $physical parameter_ids] ne [dict get $numeric parameter_ids]||[dict get $physical parameter_units] ne [dict get $numeric parameter_units]} {error {Retained complex physical declaration differs from its fitted parameter identity}}
    if {[dict get $binding schema] ne "gxtxt.fit_complex_binding.v1"||[dict get $binding row_index_base]!=0||[dict get $binding covariance] ne [dict get $data covariance]||[dict get $binding display] ne [dict get $data display]} {error {Retained complex source/covariance/display declaration changed}}
    if {[dict get $binding training_rows_sha256] ne [dict get $p observation_binding rows_sha256]} {error {Complex covariance lost exact training-row identity}}
    set sourceRows [::GX::interactiveDocumentResourceInfo [dict get $p source_rows_resource]]
    if {[dict get $sourceRows sha256] ne [dict get $binding source_rows_sha256]||[dict get $sourceRows metadata format] ne "uint64_le"||[dict get $sourceRows metadata row_count]!=[dict get $p source_n]} {error {Complex covariance lost exact evaluation-row identity}}
    foreach saved [dict get $binding channels] declared [dict get $data channels] {
        if {$saved eq {}||$declared eq {}} {error {Retained complex channel count changed}}
        dict for {key value} $declared {if {![dict exists $saved $key]||[dict get $saved $key] ne $value} {error {Retained complex observation binding changed}}}
    }
    foreach role {training evaluation} sample {training source} {
        set meaning [dict get $p statistical_results $role];set summary [dict get $meaning context complex]
        if {[dict get $meaning provenance source_identity] ne [dict get $binding source_identity]||[dict get $meaning provenance complex_binding] ne $binding||[dict get $summary declaration_sha256] ne [dict get $physical declaration_sha256]||[dict get $summary component_units] ne [dict get $physical component_units]} {error {Retained complex statistical provenance changed}}
        set n [dict get $summary observation_rows];set m [dict get $summary response_count]
        foreach kind {observations covariance} {
            set info [::GX::interactiveDocumentResourceInfo [dict get $p complex_${sample}_${kind}_resource]]
            if {[dict get $info sha256] ne [dict get $binding owned_sha256 ${sample}_$kind]} {error {Retained complex scientific resource changed}}
            if {$kind eq "observations"} {
                if {[dict get $info size_bytes]!=8*$n*$m||[dict get $info metadata shape] ne [list $n $m]||[dict get $info metadata column_units] ne [dict get $summary component_units]} {error {Retained complex observation shape or units changed}}
            } else {
                set shape [list $m $m];set count [expr {$m*$m}]
                if {[dict get $binding covariance layout] eq "per_observation"} {lappend shape $n;set count [expr {$count*$n}]}
                if {[dict get $info size_bytes]!=8*$count||[dict get $info metadata shape] ne $shape||[dict get $info metadata component_units] ne [dict get $summary component_units]||[dict get $summary covariance_sha256] ne [dict get $binding numeric_covariance_sha256 $sample]} {error {Retained complex covariance shape, units or numerical identity changed}}
            }
        }
    }
    set summary [dict get $p statistical_results training context complex]
    if {[dict get $p train_n]!=[dict get $summary observation_rows]||[dict get $p source_n]!=[dict get $p statistical_results evaluation context complex observation_rows]} {error {Complex physical row counts differ from captured training/evaluation observations}}
    foreach key {source_sha256 binding_sha256} {if {[dict get $numeric $key] ne [dict get $summary normalized_formula_$key]} {error {Retained complex normalized solver expression changed}}}
    if {[dict get $p orientation] ne "y_of_x"} {error {Complex frequency response orientation changed}}
    foreach axis {u v} {if {[dict get $p translation $axis mode] ne "off"||[dict get $p translation $axis delta]!=0} {error {Complex physical coordinates acquired a translation}}}
}
proc ::GX::DatasetCurveFit::_complexResidualUnits {p} {
    set binding [dict get $p complex_binding];set axes [dict get $binding source_identity source_axes]
    set result [list [dict get $axes x unit] [dict get $axes y unit] [dict get $axes y unit] [dict get $axes y unit]]
    foreach unit [dict get $p statistical_results evaluation context complex channel_units] {lappend result $unit $unit $unit $unit $unit $unit rad 1}
    return $result
}
