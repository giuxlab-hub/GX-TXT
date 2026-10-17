# Data/UI adaptation for public CORE/Numeric parameter bootstrap.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_bootstrapOptions {model options} {
    set settings [::GX::datasetPublicationV2DictDefault $options bootstrap {}]
    if {$settings eq {}} {return {}}
    set settings [::GX::StatisticsV1::bootstrapSettings $settings]
    if {$model ni {linear polynomial exponential power_law gaussian components regions formula registered}||[_fitOrientation $model $options] ni {y_of_x x_of_y}||[dict get [_measurementOptions $options] kind] eq "sigma_xy"} {error {Parameter bootstrap requires a supported scalar response model in Y(X) or X(Y); this model/geometry has no registered refit adapter}}
    return $settings
}
proc ::GX::DatasetCurveFit::_bootstrapLabels {} {return {off {Off — no parameter bootstrap} pairs {Resample observation tuples} residual {Resample standardized residuals} parametric_gaussian {Simulate declared Gaussian errors}}}
proc ::GX::DatasetCurveFit::_bootstrapSettings {w} {
    variable state
    _assertLoaded $w
    set settings $state($w,bootstrapSettings);set method off
    if {$settings eq {}} {set settings [::GX::StatisticsV1::bootstrapSettings]} else {set method [dict get $settings method]}
    set fields [dict create method [dict create type choice label {Parameter bootstrap} values [dict values [_bootstrapLabels]]]]
    foreach {id label} {replicates {Requested refits (20–10,000)} seed {Random seed (1–2,147,483,646)} confidence {Marginal confidence level (0–1)} max_seconds {Shared time budget in seconds}} {dict set fields $id [dict create type number label $label required 1]}
    dict set settings method [dict get [_bootstrapLabels] $method]
    ::GX::uiFieldFormCreate $w.bootstrapSettings {Parameter bootstrap settings} $fields $settings [list ::GX::DatasetCurveFit::_bootstrapApply $w $state($w,activeSource)] $w
    ttk::label $w.bootstrapSettings.note -text {Refits use the exact retained observations and captured estimator. Pairs assumes independent observation tuples; residual/Gaussian methods keep the design fixed. Rank failures, active-bound events or unfinished trials withhold nominal intervals. More replicates reduce percentile Monte Carlo error.} -wraplength 540
    pack $w.bootstrapSettings.note -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_bootstrapApply {w owner values} {
    variable state
    if {$owner ne $state($w,activeSource)} {error {Active source changed; reopen bootstrap settings}}
    set method {};dict for {id label} [_bootstrapLabels] {if {[dict get $values method] eq $label} {set method $id}}
    if {$method eq {}} {error {Choose a registered bootstrap method}}
    set settings {}
    if {$method ne "off"} {
        dict set values method $method
        set options [_uiFitOptions $w];dict set options bootstrap $values
        set settings [_bootstrapOptions $state($w,model) $options]
    }
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,bootstrapSettings) $settings
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Bootstrap settings saved. Preview again to run the requested refits.}
}
proc ::GX::DatasetCurveFit::_bootstrapImport {document directory result} {
    if {![dict exists $result numeric_statistics bootstrap]} {return $result}
    if {$document eq {}} {error {Bootstrap requires an owned Fitter Document}}
    set raw [dict get $result numeric_statistics bootstrap];set n [dict get $raw replicates]
    foreach {field file dtype role columns} [list bootstrap_parameters_resource bootstrap_parameters.bin float64 parameter_bootstrap_draws [dict get $raw parameter_ids] bootstrap_status_resource bootstrap_status.bin uint8 parameter_bootstrap_status {replicate_status} bootstrap_seed_resource bootstrap_seed.bin uint32 parameter_bootstrap_seed {replicate_seed}] {
        set metadata [dict create format gxtxt.numeric_matrix_le_v1 dtype $dtype endian little order C row_count $n columns $columns role $role numeric_receipt_sha256 [_numericStateDigest $raw] source_sha256 [dict get $result comparison_input source_sha256] training_rows_sha256 [dict get $result comparison_input rows_sha256]]
        dict set result $field [::GX::interactiveDocumentResourceImportNumeric $document [file join $directory $file] $metadata]
    }
    return $result
}
proc ::GX::DatasetCurveFit::_validateBootstrapMetadata {result} {
    set fields {bootstrap_parameters_resource bootstrap_status_resource bootstrap_seed_resource}
    if {![dict exists $result statistical_results bootstrap]} {foreach field $fields {if {[dict exists $result $field]} {error {Bootstrap draws lack captured CORE meaning}}};return}
    set meaning [dict get $result statistical_results bootstrap];::GX::StatisticsV1::validate $meaning
    set expected [::GX::StatisticsV1::bootstrapInterpretation [dict get $result statistical_results training] [dict get $meaning request numeric]]
    ::GX::StatisticsV1::validate [dict replace $meaning request [dict get $expected request]]
    set raw [dict get $meaning request numeric];set n [dict get $raw replicates];set p [dict get $raw p]
    foreach field $fields dtype {float64 uint8 uint32} role {parameter_bootstrap_draws parameter_bootstrap_status parameter_bootstrap_seed} width [list [expr {8*$p}] 1 4] columns [list [dict get $raw parameter_ids] {replicate_status} {replicate_seed}] {
        if {![dict exists $result $field]} {error "Bootstrap result lacks $field"}
        set info [::GX::interactiveDocumentResourceInfo [dict get $result $field]];set metadata [dict get $info metadata]
        if {[dict get $info size_bytes]!=$width*$n||[dict get $metadata row_count]!=$n||[dict get $metadata format] ne "gxtxt.numeric_matrix_le_v1"||[dict get $metadata dtype] ne $dtype||[dict get $metadata endian] ne "little"||[dict get $metadata order] ne "C"||[dict get $metadata role] ne $role||[dict get $metadata columns] ne $columns} {error {Bootstrap resource identity, dtype or shape changed}}
        if {[dict get $metadata numeric_receipt_sha256] ne [_numericStateDigest $raw]||[dict get $metadata source_sha256] ne [dict get $result observation_binding source_sha256]||[dict get $metadata training_rows_sha256] ne [dict get $result observation_binding rows_sha256]} {error {Bootstrap resource belongs to a different fit or training population}}
    }
}
proc ::GX::DatasetCurveFit::_bootstrapPage {result start count} {
    _validateBootstrapMetadata $result
    if {![dict exists $result statistical_results bootstrap]} {error {This retained fit has no parameter bootstrap; request it in a new explicit fit}}
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$count>512} {error {Bootstrap pages require a nonnegative offset and 1..512 trials}}
    set page [dict create api_id FITTER_BOOTSTRAP_PAGE_v1 api_version 1 meaning [dict get $result statistical_results bootstrap]]
    foreach field {bootstrap_parameters_resource bootstrap_status_resource bootstrap_seed_resource} name {parameter_samples replicate_status replicate_seed} {dict set page $name [::GX::managedResourceNumericPage [dict get $result $field] $start $count]}
    return $page
}
proc ::GX::DatasetCurveFit::resultBootstrapPage {reference start count} {return [_bootstrapPage [dict get [_recipeResultRecord $reference] provenance] $start $count]}
proc ::GX::DatasetCurveFit::_bootstrapDetails {w} {
    variable state
    set chosen [$w.left.viewport.content.accepted.list curselection]
    if {[llength $chosen]==1} {set result [dict get [lindex $state($w,records) [lindex $chosen 0]] provenance]} else {_assertLoaded $w;set result [dict merge [_sourceProvenance $w] $state($w,preview)]}
    _validateBootstrapMetadata $result
    if {![dict exists $result statistical_results bootstrap]} {error {This fit has no parameter bootstrap; enable it in Parameter bootstrap settings and preview a supported model}}
    set d $w.bootstrapDetails;if {[winfo exists $d]} {destroy $d}
    set state($w,bootstrapDialogResult) $result;set state($w,bootstrapOffset) 0
    toplevel $d;wm title $d {Parameter bootstrap};wm transient $d $w
    text $d.report -height 14 -width 96 -wrap word -yscrollcommand [list $d.reportScroll set]
    ttk::scrollbar $d.reportScroll -command [list $d.report yview]
    $d.report insert end [::GX::StatisticsV1::report [dict get $result statistical_results bootstrap]];$d.report configure -state disabled
    grid $d.report -row 0 -column 0 -sticky nsew;grid $d.reportScroll -row 0 -column 1 -sticky ns
    set plan [dict get $result statistical_results bootstrap plan];set columns [concat {trial replicate_status replicate_seed} [dict get $plan parameter_ids]]
    ttk::treeview $d.table -columns $columns -show headings -height 10 -selectmode browse
    set labels [list Trial {Trial status code} {Starting seed}]
    foreach id [dict get $plan parameter_ids] unit [dict get $plan parameter_units] {lappend labels "$id ($unit)"}
    foreach id $columns label $labels {$d.table heading $id -text $label;$d.table column $id -width [expr {max(120,[font measure TkHeadingFont $label]+22)}] -stretch 0}
    ttk::scrollbar $d.horizontal -orient horizontal -command [list $d.table xview];ttk::scrollbar $d.vertical -command [list $d.table yview]
    $d.table configure -xscrollcommand [list $d.horizontal set] -yscrollcommand [list $d.vertical set]
    grid $d.table -row 1 -column 0 -sticky nsew;grid $d.vertical -row 1 -column 1 -sticky ns;grid $d.horizontal -row 2 -column 0 -sticky ew
    ttk::frame $d.controls;grid $d.controls -row 3 -column 0 -sticky ew
    foreach {id label delta} {previous Previous -100 next Next 100} {ttk::button $d.controls.$id -text $label -command [list ::GX::DatasetCurveFit::_bootstrapDialogPage $w $delta];pack $d.controls.$id -side left}
    ttk::label $d.controls.page -textvariable ::GX::DatasetCurveFit::state($w,bootstrapPageLabel);pack $d.controls.page -side left -padx 12
    set definitions [::GX::StatisticsV1::numericDataFields [dict get $result statistical_results bootstrap]]
    ttk::label $d.statusKey -text [dict get $definitions fields replicate_status definition] -wraplength 950;grid $d.statusKey -row 4 -column 0 -sticky ew -padx 8 -pady 8
    grid rowconfigure $d 1 -weight 1;grid columnconfigure $d 0 -weight 1;wm geometry $d 1050x650
    bind $d <Escape> [list destroy $d];_bootstrapDialogPage $w 0
}
proc ::GX::DatasetCurveFit::_bootstrapDialogPage {w delta} {
    variable state
    set result $state($w,bootstrapDialogResult);set total [dict get $result statistical_results bootstrap plan replicates];set p [dict get $result statistical_results bootstrap plan p]
    set start [expr {min(max(0,$state($w,bootstrapOffset)+$delta),100*int(($total-1)/100))}]
    set page [_bootstrapPage $result $start 100];set count [dict get $page parameter_samples row_count]
    binary scan [dict get $page parameter_samples bytes] q* values;binary scan [dict get $page replicate_status bytes] cu* statuses;binary scan [dict get $page replicate_seed bytes] iu* seeds
    set tree $w.bootstrapDetails.table;$tree delete [$tree children {}]
    for {set i 0} {$i<$count} {incr i} {
        set display [lmap value [lrange $values [expr {$p*$i}] [expr {$p*$i+$p-1}]] {if {[string equal -nocase $value NaN]} {set value NaN} else {format %.9g $value}}]
        $tree insert {} end -id [expr {$start+$i}] -values [concat [list [expr {$start+$i+1}] [lindex $statuses $i] [lindex $seeds $i]] $display]
    }
    set state($w,bootstrapOffset) $start;set state($w,bootstrapPageLabel) "Trials [expr {$start+1}]–[expr {$start+$count}] of $total"
    $w.bootstrapDetails.controls.previous configure -state [expr {$start>0?"normal":"disabled"}];$w.bootstrapDetails.controls.next configure -state [expr {$start+$count<$total?"normal":"disabled"}]
}
