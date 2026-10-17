# SPDX-License-Identifier: GPL-3.0-or-later
# Fitter UI and retained resource adaptation to public CORE/Numeric profiling.
proc ::GX::DatasetCurveFit::_profileOptions {model options} {
    set settings [::GX::datasetPublicationV2DictDefault $options profile {}]
    if {$settings eq {}} {return {}}
    set settings [::GX::StatisticsV1::profileSettings $settings]
    if {$model ni {exponential power_law gaussian components regions formula}} {error {This Fitter model has no declared native constrained-refit adapter}}
    set id math.numeric.$model;if {$model in {components regions formula}} {set id math.numeric.nonlinear}
    set context [dict create fit_geometry vertical_response]
    if {[_fitOrientation $model $options] ni {y_of_x x_of_y}} {dict set context fit_geometry parametric}
    if {[dict get [_measurementOptions $options] kind] eq "sigma_xy"} {dict set context fit_geometry orthogonal_xy}
    if {[::GX::datasetPublicationV2DictDefault $options covariance {}] ne {}} {dict set context fit_geometry full_response_covariance}
    dict set context loss [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $options solver_options {}] loss linear]
    set eligibility [::GX::StatisticsV1::profileEligibility $id nonlinear_fit $context]
    if {[dict get $eligibility status] ne "eligible"} {error [dict get $eligibility reason]}
    return $settings
}
proc ::GX::DatasetCurveFit::_profileParameterIds {w} {
    variable state;set model $state($w,model);set options [_uiFitOptions $w]
    switch -- $model {
        components {return [dict get [_prepareComponents $w $options] parameter_ids]}
        regions {return [dict get [_prepareRegions $w $options] parameter_ids]}
        formula {return [dict get [_prepareFormula $w $options] parameter_ids]}
        exponential - power_law - gaussian {return [dict get [::GX::StatisticsV1::model math.numeric.$model] parameter_ids]}
        default {return {}}
    }
}
proc ::GX::DatasetCurveFit::_profileSettings {w} {
    variable state;_assertLoaded $w
    set ids [_profileParameterIds $w];if {$ids eq {}} {set ids {unavailable}};set settings $state($w,profileSettings);set enabled Off
    if {$settings eq {}} {
        set id [lindex $ids 0];set value 0;set step .1
        if {[dict exists $state($w,preview) statistical_results training parameters]} {
            foreach parameter [dict get $state($w,preview) statistical_results training parameters] {if {[dict get $parameter id] eq $id&&[dict exists $parameter value]} {set value [dict get $parameter value]}}
            set step [expr {max(.1,abs($value)/10.0)}]
        }
        set settings [dict create parameter_id $id confidence .95 search_lower [expr {$value-10*$step}] search_upper [expr {$value+10*$step}] initial_step $step parameter_tolerance [expr {$step/10000.0}] max_refits 128 max_seconds 60]
    } else {set enabled On}
    set fields [dict create enabled [dict create type choice label {Constrained profile likelihood} values {Off On}] parameter_id [dict create type choice label {Canonical parameter identity} values $ids]]
    foreach {key label} {confidence {Marginal confidence level (asymptotic)} search_lower {Lower search limit in fitted parameter coordinates} search_upper {Upper search limit in fitted parameter coordinates} initial_step {Initial physical parameter step} parameter_tolerance {Absolute physical endpoint tolerance} max_refits {Maximum constrained refits (4–256)} max_seconds {Shared search time budget in seconds}} {dict set fields $key [dict create type number label $label required 1]}
    dict set settings enabled $enabled
    ::GX::uiFieldFormCreate $w.profileSettings {Profile likelihood settings} $fields $settings [list ::GX::DatasetCurveFit::_profileApply $w $state($w,activeSource) $state($w,model)] $w
    ttk::label $w.profileSettings.note -text {Limits refer to the displayed fitted model's parameter coordinates, including any declared input translation. Review limits and units explicitly. Declare Gaussian noise in Statistical assumptions. Each trial fixes this parameter and reoptimizes the others under the existing bounds. Open searches do not prove global unboundedness; Wald intervals remain separate.} -wraplength 600
    pack $w.profileSettings.note -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_profileApply {w owner model values} {
    variable state
    if {$owner ne $state($w,activeSource)||$model ne $state($w,model)} {error {Active source or model changed; reopen profile settings}}
    set enabled [dict get $values enabled];dict unset values enabled;set settings {}
    if {$enabled eq "On"} {if {[dict get $values parameter_id] ni [_profileParameterIds $w]} {error {Choose a canonical parameter from the current supported model}};set options [_uiFitOptions $w];dict set options profile $values;set settings [_profileOptions $model $options]} elseif {$enabled ne "Off"} {error {Choose On or Off}}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,profileSettings) $settings;_invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Profile settings saved. Preview again to run the explicit constrained search.}
}
proc ::GX::DatasetCurveFit::_profileResourceFields {} {return {profile_values_resource profile_parameters_resource profile_status_resource profile_messages_resource}}
proc ::GX::DatasetCurveFit::_profileImport {document directory result} {
    if {![dict exists $result numeric_statistics profile]} {return $result}
    if {$document eq {}} {error {Profile likelihood requires an owned Fitter Document}}
    set raw [dict get $result numeric_statistics profile];set n [dict get $raw attempted_count]
    foreach {field file dtype role columns} [list profile_values_resource profile_values.bin float64 parameter_profile_values {parameter_value weighted_sse likelihood_ratio direction} profile_parameters_resource profile_parameters.bin float64 parameter_profile_parameters [dict get $raw parameter_ids] profile_status_resource profile_status.bin uint8 parameter_profile_status {trial_status}] {
        set metadata [dict create format gxtxt.numeric_matrix_le_v1 dtype $dtype endian little order C row_count $n columns $columns role $role numeric_receipt_sha256 [_numericStateDigest $raw] source_sha256 [dict get $result comparison_input source_sha256] training_rows_sha256 [dict get $result comparison_input rows_sha256]]
        dict set result $field [::GX::interactiveDocumentResourceImportNumeric $document [file join $directory $file] $metadata]
    }
    set metadata [dict create format json encoding utf-8 row_count $n role parameter_profile_messages numeric_receipt_sha256 [_numericStateDigest $raw] source_sha256 [dict get $result comparison_input source_sha256] training_rows_sha256 [dict get $result comparison_input rows_sha256]]
    dict set result profile_messages_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $directory profile_messages.json] $metadata]
    return $result
}
proc ::GX::DatasetCurveFit::_validateProfileMetadata {result} {
    set fields [_profileResourceFields]
    if {![dict exists $result statistical_results profile]} {foreach field $fields {if {[dict exists $result $field]} {error {Profile resources lack captured CORE meaning}}};return}
    set meaning [dict get $result statistical_results profile];::GX::StatisticsV1::validate $meaning
    set expected [::GX::StatisticsV1::profileInterpretation [dict get $result statistical_results training] [dict get $meaning request numeric]]
    ::GX::StatisticsV1::validate [dict replace $meaning request [dict get $expected request]]
    set raw [dict get $meaning request numeric];set n [dict get $raw attempted_count];set p [dict get $raw p]
    set settings [_profileOptions [dict get $result model] [dict get $result options]]
    if {$settings eq {}} {error {Profile result lost its explicit search settings}}
    dict for {key value} $settings {
        set captured [dict get $raw settings $key]
        if {$key eq "parameter_id"} {if {$value ne $captured} {error {Profile parameter identity changed}}} elseif {$value!=$captured} {error "Profile search setting changed: $key"}
    }
    set context [dict get $meaning request source_request context]
    if {[dict get $result orientation] ne [dict get $context orientation]||[dict get $result translation] ne [dict get $context translation]} {error {Profile coordinate orientation or declared translation changed}}
    foreach field [lrange $fields 0 2] dtype {float64 float64 uint8} role {parameter_profile_values parameter_profile_parameters parameter_profile_status} width [list 32 [expr {8*$p}] 1] columns [list {parameter_value weighted_sse likelihood_ratio direction} [dict get $raw parameter_ids] {trial_status}] {
        if {![dict exists $result $field]} {error "Profile result lacks $field"}
        set info [::GX::interactiveDocumentResourceInfo [dict get $result $field]];set metadata [dict get $info metadata]
        if {[dict get $info size_bytes]!=$width*$n||[dict get $metadata row_count]!=$n||[dict get $metadata format] ne "gxtxt.numeric_matrix_le_v1"||[dict get $metadata dtype] ne $dtype||[dict get $metadata endian] ne "little"||[dict get $metadata order] ne "C"||[dict get $metadata role] ne $role||[dict get $metadata columns] ne $columns} {error {Profile resource identity, dtype or shape changed}}
    }
    set info [::GX::interactiveDocumentResourceInfo [dict get $result profile_messages_resource]];set metadata [dict get $info metadata]
    if {[dict get $info size_bytes]>1048576||[dict get $metadata format] ne "json"||[dict get $metadata encoding] ne "utf-8"||[dict get $metadata role] ne "parameter_profile_messages"||[dict get $metadata row_count]!=$n} {error {Profile message resource contract changed}}
    foreach field $fields {
        set metadata [dict get $result $field metadata]
        if {[dict get $metadata numeric_receipt_sha256] ne [_numericStateDigest $raw]||[dict get $metadata source_sha256] ne [dict get $result observation_binding source_sha256]||[dict get $metadata training_rows_sha256] ne [dict get $result observation_binding rows_sha256]} {error {Profile resource belongs to a different fit or original row population}}
    }
}
proc ::GX::DatasetCurveFit::_profilePage {result start count} {
    _validateProfileMetadata $result
    if {![dict exists $result statistical_results profile]} {error {This retained fit has no profile likelihood; request it in an explicit new fit}}
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$count>256} {error {Profile pages require a nonnegative offset and 1–256 trials}}
    set page [dict create api_id FITTER_PROFILE_PAGE_v1 api_version 1 meaning [dict get $result statistical_results profile]]
    foreach field {profile_values_resource profile_parameters_resource profile_status_resource} name {trial_values trial_parameters trial_status} {dict set page $name [::GX::managedResourceNumericPage [dict get $result $field] $start $count]}
    set ref [dict get $result profile_messages_resource]
    dict set page trial_messages_utf8 [encoding convertfrom utf-8 [::GX::interactiveDocumentResourceReadChunk $ref 0 [dict get $ref size_bytes]]]
    return $page
}
proc ::GX::DatasetCurveFit::resultProfilePage {reference start count} {return [_profilePage [dict get [_recipeResultRecord $reference] provenance] $start $count]}
proc ::GX::DatasetCurveFit::_profileDetails {w} {
    variable state;set chosen [$w.left.viewport.content.accepted.list curselection]
    if {[llength $chosen]==1} {set result [dict get [lindex $state($w,records) [lindex $chosen 0]] provenance]} else {_assertLoaded $w;set result [dict merge [_sourceProvenance $w] $state($w,preview)]}
    set page [_profilePage $result 0 256];set meaning [dict get $page meaning];set d $w.profileDetails
    if {[winfo exists $d]} {destroy $d};toplevel $d;wm title $d {Profile likelihood};wm transient $d $w
    text $d.report -height 17 -width 108 -wrap word -yscrollcommand [list $d.reportScroll set];ttk::scrollbar $d.reportScroll -command [list $d.report yview]
    $d.report insert end [::GX::StatisticsV1::profileReport $meaning];$d.report configure -state disabled
    grid $d.report -row 0 -column 0 -sticky nsew;grid $d.reportScroll -row 0 -column 1 -sticky ns
    set definitions [::GX::StatisticsV1::numericDataFields $meaning];set ids [dict get $meaning plan parameter_ids];set p [llength $ids]
    set columns [concat {trial status parameter_value weighted_sse likelihood_ratio direction} [lmap id $ids {set id "parameter:$id"}]]
    ttk::treeview $d.table -columns $columns -show headings -height 12
    set labels [list Trial Status "Profiled [dict get $meaning interval parameter_id] ([dict get $meaning interval unit])" {Weighted SSE} {Likelihood ratio} Direction]
    foreach id $ids unit [dict get $meaning plan parameter_units] {lappend labels "$id ($unit)"}
    foreach id $columns label $labels {$d.table heading $id -text $label;$d.table column $id -width [expr {max(105,[font measure TkHeadingFont $label]+18)}] -stretch 0}
    ttk::scrollbar $d.horizontal -orient horizontal -command [list $d.table xview];ttk::scrollbar $d.vertical -command [list $d.table yview];$d.table configure -xscrollcommand [list $d.horizontal set] -yscrollcommand [list $d.vertical set]
    grid $d.table -row 1 -column 0 -sticky nsew;grid $d.vertical -row 1 -column 1 -sticky ns;grid $d.horizontal -row 2 -column 0 -sticky ew
    binary scan [dict get $page trial_values bytes] q* values;binary scan [dict get $page trial_parameters bytes] q* parameters;binary scan [dict get $page trial_status bytes] cu* statuses
    for {set i 0} {$i<[dict get $page trial_values row_count]} {incr i} {
        set numbers [concat [lrange $values [expr {4*$i}] [expr {4*$i+3}]] [lrange $parameters [expr {$p*$i}] [expr {$p*$i+$p-1}]]]
        set display [lmap value $numbers {if {[string equal -nocase $value NaN]} {set value NaN} else {format %.9g $value}}]
        $d.table insert {} end -values [concat [list [expr {$i+1}] [lindex $statuses $i]] $display]
    }
    ttk::label $d.statusKey -text [dict get $definitions fields trial_status definition] -wraplength 950;grid $d.statusKey -row 3 -column 0 -sticky ew -padx 8 -pady 8
    grid rowconfigure $d 1 -weight 1;grid columnconfigure $d 0 -weight 1;wm geometry $d 1100x700;bind $d <Escape> [list destroy $d]
}
