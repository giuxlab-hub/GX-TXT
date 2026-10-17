# Full-covariance source binding. CORE owns data/units; Numeric owns GLS.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_covarianceOptions {options} {
    set spec [::GX::datasetPublicationV2DictDefault $options covariance {}]
    if {$spec eq {}} {return {}}
    foreach key [dict keys $spec] {if {$key ni {dataset_id variable_id source_dataset_id response_variable_id row_binding covariance_semantics singular_policy}} {error "Unknown covariance binding field '$key'"}}
    foreach key {dataset_id variable_id source_dataset_id response_variable_id row_binding} {if {![dict exists $spec $key]||[dict get $spec $key] eq {}} {error "Covariance binding requires $key"}}
    set spec [dict merge {covariance_semantics absolute singular_policy reject} $spec]
    if {[dict get $spec row_binding] ne "original_source_rows"||[dict get $spec covariance_semantics] ni {absolute relative_scale}||[dict get $spec singular_policy] ni {reject exact_constraints}} {error {Declare covariance in original source-row order and an explicit scale/singularity policy}}
    if {[dict get [_measurementOptions $options] kind] ne "none"} {error {Full covariance cannot be combined with independent sigma or relative-precision columns}}
    return $spec
}
proc ::GX::DatasetCurveFit::_covarianceRequest {key model options} {
    variable state
    set spec [_covarianceOptions $options];if {$spec eq {}} {return {}}
    if {$model ni {linear polynomial}||[_fitOrientation $model $options] ni {y_of_x x_of_y}||$state($key,sourceKind) ne "dataset"||$state($key,sourceToken) eq {}} {error {Full covariance requires a real Dataset linear/polynomial response fit}}
    set source [_sourceProvenance $key];set axis [expr {[_fitOrientation $model $options] eq "x_of_y"?"x":"y"}]
    if {[dict get $spec source_dataset_id] ne $state($key,dataset)||[dict get $spec response_variable_id] ne $state($key,$axis)} {error {Covariance declaration belongs to a different source Dataset or response variable}}
    if {[_smoothContext $source] ne {}||[_baselineContext $source] ne {}||[_logContext $source [_fitOrientation $model $options]] ne {}} {error {Smoothing, estimated baseline and logarithmic responses require propagated covariance before GLS}}
    if {$state($key,sourceTransformManifest) ne {}&&[dict get $state($key,sourceTransformManifest) operation] ne "reverse_sequence"} {error {This transformed source has no declared full-covariance propagation contract}}
    if {[::GX::datasetPublicationV2DictDefault $options influence_diagnostics 0]||[::GX::datasetPublicationV2DictDefault $options bootstrap {}] ne {}||[::GX::datasetPublicationV2DictDefault $options prediction_band none] ne "none"} {error {Full-covariance bootstrap, influence and response bands require their own correlated-error contracts; disable these independent-error options}}
    set noise [::GX::datasetPublicationV2DictDefault $options noise_model unspecified]
    set expected [expr {[dict get $spec covariance_semantics] eq "absolute"?"correlated_gaussian_known_covariance":"correlated_gaussian_estimated_scale"}]
    if {$noise ni [list unspecified $expected]} {error {Choose unspecified or the correlated Gaussian assumption matching the covariance scale}}
    return $spec
}
proc ::GX::DatasetCurveFit::_covarianceBinding {key model options input} {
    variable state
    set spec [_covarianceRequest $key $model $options];if {$spec eq {}} {return {}}
    set preprocessing [dict get $input preprocessing]
    set n [dict get $preprocessing original_count]
    if {[dict get $preprocessing row_identity_kind] ne "dataset_row"||[dict get $preprocessing original_count_status] ne "value"||$n<2||$n>2048} {error {Full covariance needs exact original Dataset row identities and 2..2048 original rows}}
    set handle [::GX::datasetAccessOpen $::GX::currentSession [dict get $spec dataset_id]]
    try {
        set descriptor {};foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {if {[dict get $variable variable_id] eq [dict get $spec variable_id]} {set descriptor $variable;break}}
        if {$descriptor eq {}||![dict get $descriptor enabled]||[dict get $descriptor dtype] ni {float32 float64}||[dict get $descriptor rank]!=2||[string map {; { }} [dict get $descriptor shape]] ne [list $n $n]} {error {Covariance Variable must be a real floating N-by-N array covering every original source row}}
        if {![dict get [::GX::datasetAccessCapabilities $handle] managed_binary_read]} {error {Covariance storage requires the shared managed binary Dataset reader}}
    } finally {::GX::datasetAccessClose $handle}
    set source [_sourceProvenance $key];set axis [expr {[_fitOrientation $model $options] eq "x_of_y"?"x":"y"}]
    set unit [dict get $source source_axes $axis unit];set covarianceUnit [dict get $descriptor unit]
    if {$unit eq {}||$covarianceUnit eq {}} {error {Declare response and covariance physical units before fitting}}
    set conversion [::GX::unitRegistryDifferentialRatioPlan $covarianceUnit $unit $unit]
    if {[dict get $conversion status] ne "value"||abs([dict get $conversion scale]-1)>8*2.2204460492503131e-16} {error {Covariance values must already use squared response units; convert them explicitly upstream}}
    set binding [dict merge $spec [dict create schema gxtxt.fit_covariance_binding.v1 variable_descriptor $descriptor response_unit $unit covariance_unit $covarianceUnit original_count $n orientation [_fitOrientation $model $options] source_identity $source covariance_dataset_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $spec dataset_id]] row_index_base 0 training_rows_sha256 [::GX::sha256File [dict get $input source_rows_file]]]]
    set metadata [::GX::datasetMetadataRead $::GX::currentSession [dict get $spec dataset_id]]
    if {[dict exists $metadata curve_digitizer.covariance_binding]} {
        ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
        set digitization [::GX::CurveDigitizerCompanion::covariancePublication [dict get $spec dataset_id]]
        if {[dict get $digitization source_identity] ne [::GX::curveSourceDatasetIdentity $::GX::currentSession $state($key,dataset)]||[dict get $digitization axis] ne $axis||[dict get $digitization variable_id] ne [dict get $spec variable_id]||[dict get $digitization source ${axis}_variable_id] ne [dict get $spec response_variable_id]||[dict get $spec covariance_semantics] ne "absolute"} {error {Digitizer covariance belongs to a different original Dataset, physical response or absolute uncertainty model}}
        dict set binding digitization $digitization
    }
    return $binding
}
proc ::GX::DatasetCurveFit::_covarianceStage {binding workspace} {
    if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding dataset_id]] ne [dict get $binding covariance_dataset_identity]} {error {Covariance source changed after binding}}
    set handle [::GX::datasetAccessOpen $::GX::currentSession [dict get $binding dataset_id]];set lease {}
    try {
        set descriptor {};foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {if {[dict get $variable variable_id] eq [dict get $binding variable_id]} {set descriptor $variable;break}}
        if {$descriptor ne [dict get $binding variable_descriptor]} {error {Covariance Variable metadata changed after binding}}
        set n [dict get $binding original_count]
        set response [::GX::datasetAccessReadHyperslabResource $handle [dict get $binding variable_id] {0 0} [list $n $n]]
        set lease [dict get $response binary_resource]
        set staged [::GX::ScientificTransportv1::stageDatasetResource $lease $workspace]
        if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding dataset_id]] ne [dict get $binding covariance_dataset_identity]} {error {Covariance source changed during capture}}
        set descriptor [dict get $staged descriptor]
        set fields {};dict for {key value} $descriptor {
            if {$key in {version count byte_count shape}} {dict set fields $key [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]} else {dict set fields $key [::GX::ScientificTransportv1::text $value]}
        }
        ::GX::ScientificTransportv1::writeResult [file join $workspace covariance-input.ini] [dict create descriptor [::GX::ScientificTransportv1::struct $fields]]
        dict set binding input_bytes_sha256 [dict get $staged sha256]
        if {[dict exists $binding digitization]&&[dict get $staged sha256] ne [dict get $binding digitization resource sha256]} {error {Digitizer covariance no longer matches the retained numerical artifact}}
        dict set binding input_dtype [dict get $descriptor dtype]
        return [dict create binding $binding path [file join $workspace [dict get $descriptor resource_id]]]
    } finally {
        try {if {$lease ne {}} {::GX::datasetAccessReleaseResource $handle [dict get $lease resource_id]}} finally {::GX::datasetAccessClose $handle}
    }
}
proc ::GX::DatasetCurveFit::_covarianceImport {document workspace binding report} {
    if {$document eq {}} {error {Full covariance requires an owned Fitter Document}}
    set raw [dict get $report numeric_statistics fit gls_summary]
    set n [dict get $raw observation_count]
    set metadata [dict create format float64_column_major_le dtype float64 endian little shape [list $n $n] row_count $n role fit_observation_covariance unit [dict get $binding covariance_unit] row_index_base 0]
    dict set report covariance_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $workspace covariance-used.bin] $metadata]
    dict set binding used_bytes_sha256 [::GX::sha256File [file join $workspace covariance-used.bin]]
    dict set binding numeric_covariance_sha256 [dict get $raw covariance_sha256]
    dict set report covariance_binding $binding
    return $report
}
proc ::GX::DatasetCurveFit::_validateCovarianceMetadata {result} {
    if {![dict exists $result covariance_binding]} {
        if {[dict exists $result covariance_resource]||[dict exists $result statistical_results training context gls]} {error {Retained GLS lacks its captured covariance source binding}}
        return
    }
    set binding [dict get $result covariance_binding];set training [dict get $result statistical_results training]
    if {[dict exists $binding digitization]} {
        ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
        set captured [dict get $binding digitization]
        set meaning [::GX::CurveDigitizerCompanion::validateUncertaintyBinding [dict get $captured source]]
        set plan [::GX::StatisticsV1::digitizationFitPlan $meaning full_response_covariance [dict get $binding orientation]]
        if {$plan ne [dict get $captured fit_plan]||[dict get $captured resource sha256] ne [dict get $binding input_bytes_sha256]||[dict get $captured source dataset_id] ne [dict get $binding source_dataset_id]||[dict get $captured source point_count]!=[dict get $binding original_count]||[dict get $binding covariance_semantics] ne "absolute"} {error {Retained GLS lost its original digitization covariance meaning or row binding}}
    }
    set raw [dict get $training context gls request numeric]
    if {[dict get $binding schema] ne "gxtxt.fit_covariance_binding.v1"||[dict get $binding row_index_base]!=0||[dict get $binding row_binding] ne "original_source_rows"} {error {Retained covariance row contract changed}}
    set source [dict get $training provenance source_identity]
    set originalCount [dict get $binding original_count];set variable [dict get $binding variable_descriptor]
    set axis [expr {[dict get $binding orientation] eq "x_of_y"?"x":"y"}]
    if {[dict get $binding source_identity] ne $source||[dict get $binding source_dataset_id] ne [dict get $source source_dataset_id]||[dict get $binding response_variable_id] ne [dict get $source source_axes $axis variable_id]||[dict get $binding response_unit] ne [dict get $source source_axes $axis unit]||[dict get $binding orientation] ne [dict get $training context orientation]} {error {Retained covariance response identity changed}}
    if {$originalCount!=[dict get $result preprocessing original_count]||$originalCount<2||$originalCount>2048||[dict get $variable rank]!=2||![dict get $variable enabled]||[dict get $variable dtype] ne [dict get $binding input_dtype]||[string map {; { }} [dict get $variable shape]] ne [list $originalCount $originalCount]||[dict get $variable variable_id] ne [dict get $binding variable_id]||[dict get $variable unit] ne [dict get $binding covariance_unit]||[dict get $binding dataset_id] ne [dict get $binding covariance_dataset_identity dataset_id]} {error {Retained covariance Variable shape, type or Dataset identity changed}}
    set spec [_covarianceOptions [dict get $result options]]
    if {$spec eq {}} {error {Retained covariance binding has no declared settings}}
    dict for {key value} $spec {if {$value ne [dict get $binding $key]} {error {Retained covariance settings differ from their binding}}}
    foreach role {training evaluation} {if {[dict get $result statistical_results $role provenance covariance_binding] ne $binding} {error {Retained covariance provenance changed}}}
    foreach field {covariance_semantics singular_policy} {if {[dict get $binding $field] ne [dict get $raw $field]} {error {Retained covariance numerical policy changed}}}
    set info [::GX::interactiveDocumentResourceInfo [dict get $result covariance_resource]];set n [dict get $raw observation_count]
    if {[dict get $info sha256] ne [dict get $binding used_bytes_sha256]||[dict get $binding numeric_covariance_sha256] ne [dict get $raw covariance_sha256]} {error {Retained observation covariance fingerprint changed}}
    if {[dict get $info size_bytes]!=8*$n*$n||[dict get $info metadata shape] ne [list $n $n]||[dict get $info metadata unit] ne [dict get $binding covariance_unit]||[dict get $info metadata format] ne "float64_column_major_le"||[dict get $training context gls request context covariance_unit] ne [dict get $binding covariance_unit]||[dict get $training context gls request context response_unit] ne [dict get $binding response_unit]} {error {Retained observation covariance resource or unit changed}}
    if {[dict get $result observation_binding rows_sha256] ne [dict get $binding training_rows_sha256]} {error {Covariance axes lost exact training-row binding}}
}
proc ::GX::DatasetCurveFit::_covarianceChoices {} {
    set choices [dict create {No full covariance} {}]
    foreach dataset [::GX::sessionInspectionDatasetIds] {
        foreach variable [::GX::datasetVariableSchemaV3 $dataset] {
            if {[dict get $variable enabled]&&[dict get $variable rank]==2&&[dict get $variable dtype] in {float32 float64}} {
                set id [dict get $variable variable_id];set label "$dataset / $id ([dict get $variable unit])"
                dict set choices $label [dict create dataset_id $dataset variable_id $id]
            }
        }
    }
    return $choices
}
proc ::GX::DatasetCurveFit::_covarianceSettings {w} {
    variable state
    _assertLoaded $w
    set choices [_covarianceChoices];set current $state($w,covarianceSettings)
    set selected {No full covariance};set semantics absolute;set policy reject
    if {$current ne {}} {
        dict for {label spec} $choices {if {$spec ne {}&&[dict get $spec dataset_id] eq [dict get $current dataset_id]&&[dict get $spec variable_id] eq [dict get $current variable_id]} {set selected $label}}
        set semantics [dict get $current covariance_semantics];set policy [dict get $current singular_policy]
    }
    set fields [dict create source [dict create type choice label {Full observation covariance Variable} values [dict keys $choices]] rows [dict create type boolean label {Both matrix axes match every original source row in its original order}] covariance_semantics [dict create type choice label {Covariance scale} values {absolute relative_scale}] singular_policy [dict create type choice label {Zero-variance covariance modes} values {reject exact_constraints}] gaussian [dict create type boolean label {Declare correlated Gaussian errors for marginal coefficient intervals}]]
    set values [dict create source $selected rows [expr {$current ne {}}] covariance_semantics $semantics singular_policy $policy gaussian [string match correlated_gaussian_* $state($w,noiseModel)]]
    ::GX::uiFieldFormCreate $w.covariance {Correlated observation covariance} $fields $values [list ::GX::DatasetCurveFit::_covarianceApply $w $state($w,activeSource) $choices] $w
    ttk::label $w.covariance.note -text {Use an N × N real covariance array in squared response units, with N matching all original source rows (maximum 2048). Filters and point selection select both axes. Absolute means supplied measurement covariance; relative_scale estimates one common multiplier. Exact constraints make zero-variance modes exact equations. Independent sigma/precision and unpropagated preprocessing cannot be combined with this declaration.} -wraplength 560
    pack $w.covariance.note -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_covarianceApply {w owner choices values} {
    variable state
    if {$owner ne $state($w,activeSource)} {error {Active source changed; reopen covariance settings}}
    set selected [dict get $values source]
    if {![dict exists $choices $selected]} {error {Choose an available covariance Variable}}
    set spec [dict get $choices $selected];set noise $state($w,noiseModel)
    if {$spec ne {}} {
        if {![dict get $values rows]} {error {Confirm the original-row correspondence of both covariance axes}}
        set axis [expr {$state($w,orientation) eq "x_of_y"?"x":"y"}]
        dict set spec source_dataset_id $state($w,dataset);dict set spec response_variable_id $state($w,$axis);dict set spec row_binding original_source_rows
        foreach field {covariance_semantics singular_policy} {dict set spec $field [dict get $values $field]}
        set noise unspecified
        if {[dict get $values gaussian]} {set noise [expr {[dict get $spec covariance_semantics] eq "absolute"?"correlated_gaussian_known_covariance":"correlated_gaussian_estimated_scale"}]}
        set options [_uiFitOptions $w];dict set options covariance $spec;dict set options noise_model $noise
        _covarianceRequest $w $state($w,model) $options
    } elseif {[string match correlated_gaussian_* $noise]} {set noise unspecified}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,covarianceSettings) $spec;set state($w,noiseModel) $noise
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    $w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    set state($w,status) {Covariance declaration saved. Preview fits the exact selected observations; accepted results retain their captured covariance.}
}
proc ::GX::DatasetCurveFit::_covarianceDetails {w} {
    variable state
    set result $state($w,preview);_validateCovarianceMetadata $result
    set binding [dict get $result covariance_binding]
    set text "Covariance: [dict get $binding dataset_id] / [dict get $binding variable_id]\nResponse: [dict get $binding source_dataset_id] / [dict get $binding response_variable_id]\nOriginal rows: [dict get $binding original_count]\nBoth axes use the same captured original source rows.\nCovariance units: [dict get $binding covariance_unit]\n\n"
    append text [::GX::StatisticsV1::glsReport [dict get $result statistical_results training context gls]]
    if {[dict exists $binding digitization]} {append text "\n\n" [::GX::StatisticsV1::digitizationReport [::GX::CurveDigitizerCompanion::validateUncertaintyBinding [dict get $binding digitization source]]] "\n" [dict get $binding digitization fit_plan reason]}
    append text "\n\n" [::GX::StatisticsV1::parameterReport [dict get $result statistical_results training]]
    set dialog $w.covarianceDetails;catch {destroy $dialog};toplevel $dialog;wm title $dialog {Full covariance fit details};wm transient $dialog $w
    text $dialog.text -wrap word -width 88 -height 26 -yscrollcommand [list $dialog.scroll set];ttk::scrollbar $dialog.scroll -orient vertical -command [list $dialog.text yview]
    $dialog.text insert end $text;$dialog.text configure -state disabled
    ttk::button $dialog.close -text Close -command [list destroy $dialog];pack $dialog.close -side bottom -pady 6;pack $dialog.scroll -side right -fill y;pack $dialog.text -side left -fill both -expand 1
}
