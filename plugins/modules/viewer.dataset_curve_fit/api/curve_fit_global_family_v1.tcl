# Fitter entry to the existing global family scientific owner and CORE Jobs.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_globalRecipeSource {source variable model config scope} {
    if {$scope ne "complete_canonical_dataset"} {error {Global family fitting requires explicit complete_canonical_dataset scope}}
    if {[dict get $source source_kind] ne "dataset"||[::GX::datasetPublicationV2DictDefault $source source_transform_manifest {}] ne {}} {error {Global family fitting needs an original canonical Dataset; materialize edited coordinates first}}
    set snapshot [dict create api_id CURVE_SOURCE_API_v1 api_version 1 source_identities [dict get $source source_scientific_fingerprints]]
    if {![dict get [::GX::curveSourceValidateSnapshot $::GX::currentSession $snapshot] valid]} {error {The loaded scientific source changed; reload it before global fitting}}
    ::GX::modulePublicApiActivate curvefit.family_global CURVE_FAMILY_API_v1
    return [::GX::CurveFamilyV1::recipe [dict get $source source_dataset_id] $model [dict create x [dict get $source source_x_variable_id] family $variable y [dict get $source source_y_variable_id]] $config]
}
proc ::GX::DatasetCurveFit::globalFamilyRecipe {encodedFitterRecipe variable model config scope} {
    recipeValidate $encodedFitterRecipe
    return [_globalRecipeSource [dict get [_recipeDecode $encodedFitterRecipe] source] $variable $model $config $scope]
}
proc ::GX::DatasetCurveFit::_globalFamilyDialog {w} {
    variable state
    set context [_familyContext $w];set source [_sourceProvenance $w]
    if {[dict get $source source_kind] ne "dataset"||[::GX::datasetPublicationV2DictDefault $source source_transform_manifest {}] ne {}} {error {Global family fitting needs an original canonical Dataset; materialize edited coordinates first}}
    ::GX::modulePublicApiActivate curvefit.family_global CURVE_FAMILY_API_v1
    set models [::GX::CurveFamilyV1::models];if {$models eq {}} {error {No callable family model is installed}}
    set variables {};foreach spec [::GX::datasetVariableSchemaV3 $state($w,dataset)] {if {[dict get $spec enabled]&&[dict get $spec rank]==1&&[dict get $spec dtype] in {bool int8 uint8 int16 uint16 int32 uint32 int64 uint64 float32 float64}} {lappend variables [dict get $spec variable_id]}}
    set fields [dict create variable [dict create type choice label {Physical family Variable} values $variables required 1] model [dict create type choice label {Mathematical model} values [lmap item $models {dict get $item model_id}] required 1] whole_dataset [dict create type boolean label {Use the complete Dataset, including rows outside current filters and selections}]]
    set variable [lindex $variables end];foreach preferred {family_value family g group} {if {$preferred in $variables} {set variable $preferred;break}}
    ::GX::uiFieldFormCreate $w.globalFamilySource {Global family fit — original physical coordinates} $fields [dict create variable $variable model [dict get [lindex $models 0] model_id] whole_dataset 0] [list ::GX::DatasetCurveFit::_globalFamilyChoose $w $context] $w
    $w.globalFamilySource.actions.apply configure -text {Review parameters}
}
proc ::GX::DatasetCurveFit::_globalFamilyChoose {w context values} {
    if {[_familyContext $w] ne $context} {error {Active source changed; reopen global family fitting}}
    if {![dict get $values whole_dataset]} {error {Choose complete Dataset scope explicitly to continue}}
    set model [dict get $values model];set variable [dict get $values variable]
    set fields {};set defaults {};set index 0
    foreach parameter [::GX::modelResourceParameterNames $model] {
        set key scope[incr index];dict set fields $key [dict create type choice label "$parameter scope" values {shared local fixed} required 1];dict set defaults $key shared
    }
    foreach {key label default type} {
        parameter_initial_values {Expanded initial values (blank uses model declarations)} {} string
        parameter_lower_bounds {Expanded lower bounds (blank uses model declarations)} {} string
        parameter_upper_bounds {Expanded upper bounds (blank uses model declarations)} {} string
        parameter_fixed_mask {Expanded fixed mask (optional 0/1 values)} {} string
        solver Solver lsqnonlin choice
        max_iter {Maximum iterations} 1000 integer
        tolerance Tolerance 1e-10 double
        name {Result Job name} {Global family fit} string
    } {
        set field [dict create type $type label $label];if {$key eq "solver"} {dict set field values {lsqnonlin fminsearch}}
        dict set fields $key $field;dict set defaults $key $default
    }
    destroy $w.globalFamilySource
    ::GX::uiFieldFormCreate $w.globalFamilyParameters {One joint fit — local values follow ascending family order; use semicolons} $fields $defaults [list ::GX::DatasetCurveFit::_globalFamilyApply $w $context $variable $model $index] $w
    $w.globalFamilyParameters.actions.apply configure -text {Run global fit}
}
proc ::GX::DatasetCurveFit::_globalFamilyApply {w context variable model count values} {
    variable state
    if {[_familyContext $w] ne $context} {error {Active source changed; reopen global family fitting}}
    set scopes {};for {set i 1} {$i<=$count} {incr i} {lappend scopes [dict get $values scope$i]}
    set config [dict create parameter_scopes [join $scopes {;}]]
    foreach key {parameter_initial_values parameter_lower_bounds parameter_upper_bounds parameter_fixed_mask solver max_iter tolerance} {dict set config $key [dict get $values $key]}
    set recipe [_globalRecipeSource [_sourceProvenance $w] $variable $model $config complete_canonical_dataset]
    set job [::GX::CurveFamilyV1::submit $recipe [dict get $values name]]
    set state($w,globalFamilyJob) [dict get $job id]
    set state($w,status) {Global family fit is running. Follow or cancel it in Session Jobs.}
    destroy $w.globalFamilyParameters
    after 250 [list ::GX::DatasetCurveFit::_globalFamilyPoll $w $state($w,sessionToken) [dict get $job id]]
    return $job
}
proc ::GX::DatasetCurveFit::_globalFamilyPoll {w token job} {
    variable state
    if {![winfo exists $w]||![info exists state($w,globalFamilyJob)]||$state($w,globalFamilyJob) ne $job||$state($w,sessionToken) ne $token} return
    if {[catch {set info [::GX::scriptJobDescribe $job]} reason]} {set state($w,status) "Global family Job status unavailable: $reason";return}
    set status [dict get $info state]
    if {$status ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {after 500 [list ::GX::DatasetCurveFit::_globalFamilyPoll $w $token $job];return}
    set state($w,globalFamilyJob) {}
    if {$status ne "COMPLETED"} {set state($w,status) "Global family fit: $status. Inspect its Session Job log.";return}
    if {[catch {set result [::GX::CurveFamilyV1::jobResult $job];_globalResultWindow $w [dict get $result reference]} reason]} {set state($w,status) "Global result retained; opening its report failed: $reason";return}
    set state($w,status) {Global family fit completed. Its joint report and parameter table are available in Results → Global family results.}
}
proc ::GX::DatasetCurveFit::_globalResults {w} {
    _assertSession $w
    ::GX::modulePublicApiActivate curvefit.family_global CURVE_FAMILY_API_v1
    set entries [::GX::CurveFamilyV1::results];if {$entries eq {}} {error {This Session has no retained global family results}}
    set labels {};set mapping {};set index 0
    foreach entry $entries {set label "[incr index]. [dict get $entry label]";lappend labels $label;dict set mapping $label [dict get $entry reference]}
    ::GX::uiFieldFormCreate $w.globalFamilyResults {Retained global family results} [dict create result [dict create type choice label {Joint result} values $labels required 1]] [dict create result [lindex $labels 0]] [list ::GX::DatasetCurveFit::_globalResultChoose $w $mapping] $w
    $w.globalFamilyResults.actions.apply configure -text {Open report}
}
proc ::GX::DatasetCurveFit::_globalResultChoose {w mapping values} {
    _globalResultWindow $w [dict get $mapping [dict get $values result]]
    destroy $w.globalFamilyResults
}
proc ::GX::DatasetCurveFit::_globalResultWindow {w reference} {
    _assertSession $w
    set result [::GX::CurveFamilyV1::resultInfo $reference];set global [dict get $result statistical_results global]
    set dialog $w.globalFamilyReport;if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog {Global family result — one joint model};wm transient $dialog $w
    text $dialog.text -wrap word -width 90 -height 26 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end "Model: [dict get $result model_id]\nScope: complete canonical Dataset, original physical coordinates\n\n[::GX::StatisticsV1::parameterReport $global]\n\n[::GX::StatisticsV1::report $global]"
    $dialog.text configure -state disabled
    ttk::frame $dialog.actions;grid $dialog.actions -row 1 -column 0 -columnspan 2 -sticky ew
    foreach {name label dataset} {parameters {Open parameter table} curvefit.family.parameters predictions {Open prediction table} curvefit.family.result} {
        ttk::button $dialog.actions.$name -text $label -command [list ::GX::DatasetCurveFit::_globalDatasetOpen $w $reference $dataset]
        pack $dialog.actions.$name -side left -padx 4 -pady 4
    }
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
proc ::GX::DatasetCurveFit::_globalDatasetOpen {w reference dataset} {
    if {[catch {
        _assertSession $w
        set result [::GX::CurveFamilyV1::resultInfo $reference];::GX::loadDatasetRegistry $::GX::currentSession
        if {[dict get [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset] sha256] ne [dict get $result publications $dataset sha256]} {error {A later run replaced this Dataset. The selected run's saved report and files remain available.}}
        ::GX::datasetViewerOpen $dataset
    } reason]} {tk_messageBox -parent $w -icon error -message $reason}
}
