# Optional retained-result review. CORE owns conditions/meaning; Fitter only
# adapts frozen model metadata, GUI controls and create-only Dataset publication.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::plausibilityDefinitions {reference} {
    set p [dict get [_recipeResultRecord $reference] provenance];set source [dict get $p statistical_results training]
    set parameters [dict get $source parameters];set byId {};foreach item $parameters {dict set byId [dict get $item id] $item}
    set context {};set rules {}
    if {[dict exists $p training_domain]&&[dict exists $p translation u unit]} {
        lassign [split [dict get $p training_domain] ,] lo hi
        dict set context domain [dict create minimum $lo maximum $hi unit [dict get $p translation u unit]]
    }
    if {[dict get $p model] eq "gaussian"&&[dict exists $byId width]} {
        set unit [dict get $byId width unit]
        lappend rules [dict create id gaussian_positive_width label {Positive Gaussian width} parameter_id width unit $unit kind interval severity domain_requirement enabled 1 lower 0 lower_inclusive 0 rationale {The Gaussian model declares a strictly positive standard-width parameter}]
        lappend rules [dict create id gaussian_width_domain label {Width within observed domain} parameter_id width unit $unit kind domain_fraction severity advisory enabled 1 maximum_fraction 1 rationale {A width larger than the observed predictor range may be poorly constrained; review coverage and parameter correlation}]
    }
    if {[dict get $p model] eq "exponential"&&[dict exists $byId rate]} {
        lappend rules [dict create id expected_decay label {Expected exponential decay} parameter_id rate unit [dict get $byId rate unit] kind interval severity advisory enabled 1 upper 0 upper_inclusive 0 rationale {Use this optional condition only when the physical process is expected to decay; the mathematical model also permits growth}]
    }
    if {[dict exists $p numeric_model_state composition]} {
        set composition [dict get $p numeric_model_state composition];set cards {}
        foreach card [dict get $composition cards] {dict set cards [dict get $card id] $card}
        set seen {}
        foreach component [dict get $composition recipe components] {
            set card [dict get $cards [dict get $component model_id]]
            foreach local [dict get $card parameter_ids] domain [dict get $card parameter_domains] {
                set id [dict get $component bindings $local]
                if {$domain eq "real"||$id in $seen} continue
                lappend seen $id
                lappend rules [dict create id domain_[llength $rules] label "Declared physical domain: $id" parameter_id $id unit [dict get $byId $id unit] kind interval severity domain_requirement enabled 1 lower 0 lower_inclusive [expr {$domain eq "nonnegative"}] rationale "Frozen model [dict get $card id] declares $local as $domain; descriptor SHA [dict get $card descriptor_sha256]"]
            }
        }
    }
    set omitted [expr {max(0,[llength $rules]-32)}];set rules [lrange $rules 0 31]
    return [dict create schema gxtxt.fitter_physical_rule_definitions.v1 parameters $parameters rules $rules context $context omitted_suggestion_count $omitted coefficient_space [::GX::datasetPublicationV2DictDefault [dict get $source context] coefficient_space original_physical]]
}
proc ::GX::DatasetCurveFit::resultPlausibility {reference rules} {
    set source [dict get [_recipeResultRecord $reference] provenance statistical_results training]
    set context [dict get [plausibilityDefinitions $reference] context]
    set meaning [::GX::StatisticsV1::physicalPlausibility $source $rules $context]
    _recipeResultRecord $reference
    set receipt [dict create schema gxtxt.fitter_physical_review_receipt.v1 reference $reference interpretation $meaning]
    return [dict create schema gxtxt.fitter_physical_review.v1 interpretation $meaning report [::GX::StatisticsV1::physicalPlausibilityReport $meaning] receipt_utf8 [encoding convertto utf-8 $receipt]]
}
proc ::GX::DatasetCurveFit::resultPlausibilityPublishText {text datasetId} {return [resultPlausibilityPublish [encoding convertto utf-8 $text] $datasetId]}
proc ::GX::DatasetCurveFit::resultPlausibilityPublish {encoded datasetId} {
    variable version
    ::GX::datasetPublicationV2ValidateId dataset $datasetId
    if {[string length $encoded]>16777216} {error {Physical review receipt exceeds 16 MiB}}
    set receipt [encoding convertfrom utf-8 $encoded]
    if {[dict get $receipt schema] ne "gxtxt.fitter_physical_review_receipt.v1"} {error {Invalid physical review receipt}}
    set reference [dict get $receipt reference];set source [dict get [_recipeResultRecord $reference] provenance statistical_results training]
    set meaning [dict get $receipt interpretation];::GX::StatisticsV1::validate $meaning
    if {[dict get $meaning schema] ne "gxtxt.physical_plausibility_review.v1"||[dict get $meaning request source] ne $source||[dict get $meaning request context] ne [dict get [plausibilityDefinitions $reference] context]} {error {Physical review belongs to a different retained result or domain}}
    if {![dict get $meaning rule_count]} {error {There are no reviewed rules to publish}}
    set definitions {};set columns {}
    foreach item [dict get $meaning checks] {
        set rule [dict get $item rule];set id [dict get $rule id];set label [dict get $rule label]
        dict set definitions rule_${id}_violation [dict create display_label "$label — violation (1=yes, 0=no, NaN=not assessed)" dtype float64 unit 1]
        set flag NaN;if {[dict get $item status] eq "value"} {set flag [expr {[dict get $item outcome] eq "violation"}]}
        dict set columns rule_${id}_violation [list $flag]
        if {[dict exists $item value]} {
            dict set definitions rule_${id}_value [dict create display_label "$label — captured parameter" dtype float64 unit [dict get $rule unit]]
            dict set columns rule_${id}_value [list [dict get $item value]]
        }
    }
    set report [::GX::StatisticsV1::physicalPlausibilityReport $meaning]
    set metadata [dict create physical_plausibility $meaning physical_plausibility.source_reference $reference physical_plausibility.report_lines [split $report \n]]
    set definition [dict create dataset_id $datasetId contract table.generic storage hdf5 replace_owned 0 display_name $datasetId structured_metadata $metadata provenance [dict create producer viewer.dataset_curve_fit producer_version $version operation physical_plausibility]]
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession viewer.dataset_curve_fit $definition];set writer {}
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan];::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        dict for {id spec} $definitions {::GX::datasetPublicationV2DeclareVariable $writer $id [dict merge $spec {rank 1 dimension_ids row coordinate_role data axis_kind explicit}]}
        ::GX::datasetPublicationV2Append $writer row $columns
        set result [::GX::datasetPublicationV2Finalize $writer];set writer {};return $result
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
}
proc ::GX::DatasetCurveFit::_plausibilityOpen {w} {
    variable state
    set selection [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selection]!=1} {error {Select one accepted fit}}
    set record [lindex $state($w,records) [lindex $selection 0]]
    set state($w,physicalReference) [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set data [plausibilityDefinitions $state($w,physicalReference)];set parameters [dict get $data parameters]
    if {![llength $parameters]} {error {This result has no scalar fitted parameters to review}}
    set state($w,physicalDefinitions) $data;set state($w,physicalRules) [dict get $data rules];set state($w,physicalResult) {};set state($w,physicalDataset) fit_physical_review
    set d $w.physicalReview;catch {destroy $d};toplevel $d;wm title $d {Physical plausibility review};wm transient $d $w
    set note "Optional point-value conditions in the captured coefficient coordinates ([dict get $data coefficient_space]). This review does not change the accepted fit. Intrinsic model domains remain enforced."
    if {[dict get $data omitted_suggestion_count]>0} {append note " Only the first 32 suggested conditions are shown; additional parameters can be reviewed separately."}
    ttk::label $d.note -text $note -wraplength 800
    grid $d.note -row 0 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 6
    listbox $d.rules -height 5 -exportselection 0;grid $d.rules -row 1 -column 0 -columnspan 3 -sticky ew -padx 8
    bind $d.rules <<ListboxSelect>> [list ::GX::DatasetCurveFit::_plausibilitySelect $w]
    set ids [lmap item $parameters {dict get $item id}]
    set row 2
    foreach field {Parameter Kind Severity Lower Upper Fraction Rationale} label {{Parameter} {Condition} {Meaning} {Lower bound (blank if unused)} {Upper bound (blank if unused)} {Maximum domain fraction} {Physical reason}} {
        ttk::label $d.l$field -text $label
        if {$field in {Parameter Kind Severity}} {
            set choices [dict get [dict create Parameter $ids Kind {{Parameter interval} {Maximum domain fraction}} Severity {{Advisory warning} {Physical domain requirement}}] $field]
            ttk::combobox $d.e$field -state readonly -values $choices -textvariable ::GX::DatasetCurveFit::state($w,physical$field)
        } else {ttk::entry $d.e$field -textvariable ::GX::DatasetCurveFit::state($w,physical$field)}
        grid $d.l$field -row $row -column 0 -sticky w -padx 8;grid $d.e$field -row $row -column 1 -columnspan 2 -sticky ew -padx 8;incr row
    }
    bind $d.eParameter <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_plausibilityUnit $w]
    ttk::label $d.unit -textvariable ::GX::DatasetCurveFit::state($w,physicalUnitLabel);grid $d.unit -row $row -column 0 -columnspan 3 -sticky w -padx 8;incr row
    ttk::frame $d.flags;grid $d.flags -row $row -column 0 -columnspan 3 -sticky ew;incr row
    foreach field {Enabled LowerInclusive UpperInclusive} label {{Enable rule} {Include lower endpoint} {Include upper endpoint}} {
        set widget $d.flags.[string tolower $field];ttk::checkbutton $widget -text $label -variable ::GX::DatasetCurveFit::state($w,physical$field);pack $widget -side left -padx 8
    }
    ttk::frame $d.actions;grid $d.actions -row $row -column 0 -columnspan 3 -sticky ew;incr row
    foreach name {add replace remove review} label {{Add rule} {Replace selected rule} {Remove selected rule} {Review rules}} command {_plausibilityAdd _plausibilityReplace _plausibilityRemove _plausibilityEvaluate} {
        ttk::button $d.actions.$name -text $label -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::$command $w]];pack $d.actions.$name -side left -padx 4 -pady 6
    }
    text $d.report -height 12 -width 95 -wrap word -state disabled -yscrollcommand [list $d.scroll set];ttk::scrollbar $d.scroll -command [list $d.report yview]
    grid $d.report -row $row -column 0 -columnspan 2 -sticky nsew;grid $d.scroll -row $row -column 2 -sticky ns;grid rowconfigure $d $row -weight 1;incr row
    ttk::label $d.publishLabel -text {New review Dataset};ttk::entry $d.dataset -textvariable ::GX::DatasetCurveFit::state($w,physicalDataset)
    ttk::button $d.publish -text {Publish reviewed result} -state disabled -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_plausibilityPublish $w]]
    grid $d.publishLabel -row $row -column 0 -sticky w;grid $d.dataset -row $row -column 1 -sticky ew;grid $d.publish -row $row -column 2 -sticky ew
    grid columnconfigure $d 1 -weight 1;wm geometry $d 950x820;bind $d <Escape> [list destroy $d]
    foreach {field value} [list Parameter [lindex $ids 0] Kind {Parameter interval} Severity {Advisory warning} Lower {} Upper {} Fraction 1 Rationale {} Enabled 1 LowerInclusive 1 UpperInclusive 1] {set state($w,physical$field) $value}
    _plausibilityList $w;_plausibilityUnit $w
}
proc ::GX::DatasetCurveFit::_plausibilityUnit {w} {
    variable state
    foreach item [dict get $state($w,physicalDefinitions) parameters] {if {[dict get $item id] eq $state($w,physicalParameter)} {set state($w,physicalUnit) [dict get $item unit];set state($w,physicalUnitLabel) "Bounds use the captured unit: [dict get $item unit]. Parameter role: [dict get $item role].";return}}
}
proc ::GX::DatasetCurveFit::_plausibilityList {w} {
    variable state
    set state($w,physicalResult) {}
    $w.physicalReview.publish configure -state disabled
    set text $w.physicalReview.report;$text configure -state normal;$text delete 1.0 end;$text insert end {Review the current rules to see their result.};$text configure -state disabled
    set list $w.physicalReview.rules;$list delete 0 end
    foreach rule $state($w,physicalRules) {$list insert end "[dict get $rule label] — [dict get $rule parameter_id] — [dict get {advisory {Advisory warning} domain_requirement {Physical domain requirement}} [dict get $rule severity]]"}
}
proc ::GX::DatasetCurveFit::_plausibilitySelect {w} {
    variable state
    set chosen [$w.physicalReview.rules curselection];if {[llength $chosen]!=1} return
    set rule [lindex $state($w,physicalRules) [lindex $chosen 0]]
    foreach {field key default} {Parameter parameter_id {} Kind kind interval Severity severity advisory Lower lower {} Upper upper {} Fraction maximum_fraction 1 Rationale rationale {} Enabled enabled 1 LowerInclusive lower_inclusive 1 UpperInclusive upper_inclusive 1} {set state($w,physical$field) [::GX::datasetPublicationV2DictDefault $rule $key $default]}
    set state($w,physicalKind) [dict get {interval {Parameter interval} domain_fraction {Maximum domain fraction}} $state($w,physicalKind)]
    set state($w,physicalSeverity) [dict get {advisory {Advisory warning} domain_requirement {Physical domain requirement}} $state($w,physicalSeverity)]
    _plausibilityUnit $w
}
proc ::GX::DatasetCurveFit::_plausibilityRule {w id} {
    variable state
    _plausibilityUnit $w
    set kind [dict get {{Parameter interval} interval {Maximum domain fraction} domain_fraction} $state($w,physicalKind)]
    set severity [dict get {{Advisory warning} advisory {Physical domain requirement} domain_requirement} $state($w,physicalSeverity)]
    set rule [dict create id $id label "Physical condition: $state($w,physicalParameter)" parameter_id $state($w,physicalParameter) unit $state($w,physicalUnit) kind $kind severity $severity enabled $state($w,physicalEnabled) rationale $state($w,physicalRationale)]
    if {$kind eq "domain_fraction"} {dict set rule maximum_fraction $state($w,physicalFraction)} else {
        foreach side {Lower Upper} {if {$state($w,physical$side) ne {}} {dict set rule [string tolower $side] $state($w,physical$side);dict set rule [string tolower $side]_inclusive $state($w,physical${side}Inclusive)}}
    }
    resultPlausibility $state($w,physicalReference) [list $rule]
    return $rule
}
proc ::GX::DatasetCurveFit::_plausibilityAdd {w} {
    variable state
    if {[llength $state($w,physicalRules)]>=32} {error {At most 32 review rules are supported}}
    set ids [lmap rule $state($w,physicalRules) {dict get $rule id}];set index 1;while {"user_rule_$index" in $ids} {incr index}
    lappend state($w,physicalRules) [_plausibilityRule $w user_rule_$index];_plausibilityList $w
}
proc ::GX::DatasetCurveFit::_plausibilityReplace {w} {
    variable state
    set chosen [$w.physicalReview.rules curselection];if {[llength $chosen]!=1} {error {Select one rule to replace}}
    set index [lindex $chosen 0];set old [lindex $state($w,physicalRules) $index];set rule [_plausibilityRule $w [dict get $old id]]
    set state($w,physicalRules) [lreplace $state($w,physicalRules) $index $index $rule];_plausibilityList $w
}
proc ::GX::DatasetCurveFit::_plausibilityRemove {w} {
    variable state
    set chosen [$w.physicalReview.rules curselection];if {[llength $chosen]!=1} {error {Select one rule to remove}}
    set index [lindex $chosen 0];set state($w,physicalRules) [lreplace $state($w,physicalRules) $index $index];_plausibilityList $w
}
proc ::GX::DatasetCurveFit::_plausibilityEvaluate {w} {
    variable state
    set result [resultPlausibility $state($w,physicalReference) $state($w,physicalRules)];set state($w,physicalResult) $result
    set text $w.physicalReview.report;$text configure -state normal;$text delete 1.0 end;$text insert end [dict get $result report];$text configure -state disabled
    $w.physicalReview.publish configure -state [expr {[llength $state($w,physicalRules)]?"normal":"disabled"}];return $result
}
proc ::GX::DatasetCurveFit::_plausibilityPublish {w} {
    variable state
    if {$state($w,physicalResult) eq {}} {error {Review rules first}}
    set result [resultPlausibilityPublish [dict get $state($w,physicalResult) receipt_utf8] $state($w,physicalDataset)]
    set state($w,status) "Published captured physical review as [dict get $result dataset_id].";return $result
}
