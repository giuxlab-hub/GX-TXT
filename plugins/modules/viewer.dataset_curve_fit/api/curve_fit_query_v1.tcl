# Retained query control/data adaptation. Scientific algorithms stay at Numeric.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_queryNumbers {values maximum label} {
    if {[llength $values]<1||[llength $values]>$maximum} {error "$label requires one to $maximum values"}
    set result {}
    foreach value $values {
        if {[string is entier -strict $value]&&abs($value)>9007199254740992} {error {Integer query values outside the exact binary64 range require an explicit scientific conversion}}
        lappend result [_finite $value $label]
    }
    return $result
}
proc ::GX::DatasetCurveFit::_queryCapturedModel {p} {
    if {[dict get $p model] eq "rational"} {return [dict create node [::GX::ScientificTransportv1::struct [dict create restore [::GX::ScientificTransportv1::text rational_model_restore] state [_rationalSavedNode $p]]] resource {} json {}]}
    if {[dict get $p model] eq "complex_response"} {
        return [dict create node [::GX::ScientificTransportv1::struct [dict create restore [::GX::ScientificTransportv1::text model] model [_complexSavedNode $p]]] resource {} json {}]
    }
    if {[dict get $p model] eq "implicit"} {
        return [dict create node [::GX::ScientificTransportv1::struct [dict create restore [::GX::ScientificTransportv1::text model] model [_implicitSavedNode $p]]] resource {} json {}]
    }
    if {[dict exists $p registered_model_state]} {error {This retained callback requires its supervised callable query adapter; scalar native reconstruction is unavailable}}
    set fields {};set resource {};set json {}
    if {[dict exists $p numeric_model_state]} {
        set saved [dict get $p numeric_model_state]
        foreach {field operation encoder} {formula_declaration fit_formula_compose _formulaRecipeNode composition fit_model_compose _componentRecipeNode regional_composition fit_region_compose _regionRecipeNode} {
            if {![dict exists $saved $field]} continue
            dict set fields restore [::GX::ScientificTransportv1::text $operation]
            dict set fields recipe [::GX::DatasetCurveFit::$encoder [dict get $saved $field recipe]]
            dict set fields parameters [::GX::ScientificTransportv1::array [list [llength [dict get $saved parameters]] 1] [dict get $saved parameters]]
            foreach identity {source_sha256 binding_sha256} {dict set fields $identity [::GX::ScientificTransportv1::text [dict get $saved $identity]]}
            return [dict create node [::GX::ScientificTransportv1::struct $fields] resource {} json {}]
        }
        set model [dict create kind [::GX::ScientificTransportv1::text [dict get $saved kind]]]
        foreach field {expression parameter_ids predictor_ids} {
            if {[dict exists $saved $field]} {dict set model $field [dict create kind cell items [lmap value [dict get $saved $field] {::GX::ScientificTransportv1::text $value}]]}
        }
        foreach field {source_sha256 binding_sha256} {dict set model $field [::GX::ScientificTransportv1::text [dict get $saved $field]]}
        dict set model parameters [::GX::ScientificTransportv1::array [list [llength [dict get $saved parameters]] 1] [dict get $saved parameters]]
        dict set fields restore [::GX::ScientificTransportv1::text model];dict set fields model [::GX::ScientificTransportv1::struct $model]
    } else {
        if {[dict exists $p model_state_resource]} {
            set resource [dict get $p model_state_resource];set info [::GX::interactiveDocumentResourceInfo $resource]
            if {[dict get $info size_bytes]>134217728} {error {Retained model JSON exceeds the 128 MiB decoder budget; no sampled substitute is used}}
        } elseif {[dict exists $p model_state_json]} {set json [dict get $p model_state_json]}
        if {$json ne {}||$resource ne {}} {
            if {[string length [encoding convertto utf-8 $json]]>134217728} {error {Retained model JSON exceeds the 128 MiB decoder budget}}
            dict set fields restore [::GX::ScientificTransportv1::text saved_json_file]
        } elseif {[dict get $p model] eq "linear"} {
            set values [split [dict get $p parameters] ,]
            set model [::GX::ScientificTransportv1::struct [dict create kind [::GX::ScientificTransportv1::text polynomial_export] coefficients [::GX::ScientificTransportv1::array [list [llength $values] 1] $values]]]
            dict set fields restore [::GX::ScientificTransportv1::text model];dict set fields model $model
        } else {error {This retained fit has no verified exact evaluation state}}
    }
    return [dict create node [::GX::ScientificTransportv1::struct $fields] resource $resource json $json]
}
proc ::GX::DatasetCurveFit::_queryOptions {p action options} {
    set allowed {extrapolation reference_domain}
    if {$action eq "query"} {lappend allowed derivative tangent_floors derivative_unit inverse_derivative_unit} else {lappend allowed x_tolerance response_tolerance max_iterations}
    if {$action eq "query"&&[dict exists $p registered_model_state]} {lappend allowed difference_step difference_relative_tolerance}
    foreach key [dict keys $options] {if {$key ni $allowed} {error "Unknown retained $action option: $key"}}
    if {[dict exists $p training_domain]} {
        set domain [split [dict get $p training_domain] ,];set basis [dict get $p training_domain_basis]
        if {[dict exists $options reference_domain]} {
            set stated [_queryNumbers [dict get $options reference_domain] 2 {Reference domain}]
            if {[llength $stated]!=2||[lindex $stated 0]!=[lindex $domain 0]||[lindex $stated 1]!=[lindex $domain 1]} {error {An explicit reference domain cannot replace the retained eligible training domain}}
        }
    } else {
        if {![dict exists $options reference_domain]} {error {Historical fit has no verified training-domain receipt; supply reference_domain explicitly to label queries against a user-declared interval}}
        set domain [dict get $options reference_domain];set basis user_declared_not_verified_training
    }
    set domain [_queryNumbers $domain 2 {Reference domain}]
    if {[llength $domain]!=2||[lindex $domain 0]>=[lindex $domain 1]} {error {Reference domain requires two increasing finite values}}
    set orientation [dict get $p orientation]
    set translation [list [dict get $p translation u delta] [dict get $p translation v delta]]
    set fields [dict create domain [::GX::ScientificTransportv1::array {2 1} $domain] orientation [::GX::ScientificTransportv1::text $orientation] translation [::GX::ScientificTransportv1::array {2 1} $translation]]
    foreach field {extrapolation} {if {[dict exists $options $field]} {dict set fields $field [::GX::ScientificTransportv1::text [dict get $options $field]]}}
    foreach field {derivative tangent_floors x_tolerance response_tolerance max_iterations difference_step difference_relative_tolerance} {
        if {[dict exists $options $field]} {
            set values [_queryNumbers [dict get $options $field] 2 $field]
            dict set fields $field [::GX::ScientificTransportv1::array [list [llength $values] 1] $values]
        }
    }
    if {$orientation eq "r_of_theta"} {
        set frame {};dict for {key value} [dict get $p polar_frame] {
            if {$key in {origin theta_zero clockwise angle_cut}} {set node [::GX::ScientificTransportv1::array [list 1 [llength $value]] $value]} else {set node [::GX::ScientificTransportv1::text $value]}
            dict set frame $key $node
        };dict set fields polar_frame [::GX::ScientificTransportv1::struct $frame]
    }
    set x [dict get $p source_axes x unit];set y [dict get $p source_axes y unit]
    set target [::GX::datasetPublicationV2DictDefault $options derivative_unit {}]
    set inverseTarget [::GX::datasetPublicationV2DictDefault $options inverse_derivative_unit {}]
    set derivativePlan [::GX::unitRegistryDifferentialRatioPlan $y $x $target]
    set inversePlan [::GX::unitRegistryDifferentialRatioPlan $x $y $inverseTarget]
    if {$action eq "query"} {
        foreach plan [list $derivativePlan $inversePlan] field {derivative_scale inverse_derivative_scale} {
            if {[dict get $plan status] eq "value"} {dict set fields $field [::GX::ScientificTransportv1::array {1 1} [list [dict get $plan scale]]]}
        }
    }
    set queryUnit [dict get $p translation u unit];set responseUnit [dict get $p translation v unit]
    if {$orientation eq "parametric"} {set queryUnit 1}
    return [dict create node [::GX::ScientificTransportv1::struct $fields] domain_basis $basis query_unit $queryUnit response_unit $responseUnit x_unit $x y_unit $y derivative_unit_plan $derivativePlan inverse_derivative_unit_plan $inversePlan]
}
proc ::GX::DatasetCurveFit::_resultQuery {reference action values bracket options {host {}}} {
    set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    set limit [expr {$action eq "query"&&[dict get $p model] ne "implicit"?4096:64}]
    set values [_queryNumbers $values $limit {Exact query values}]
    set context [_queryOptions $p $action $options]
    set bracketNode [::GX::ScientificTransportv1::empty]
    if {$action eq "inverse"} {
        set bracket [_queryNumbers $bracket 2 {Continuous branch bracket}]
        if {[llength $bracket]!=2} {error {The inverse requires two bracket endpoints}}
        set bracketNode [::GX::ScientificTransportv1::array {2 1} $bracket]
    }
    if {[dict exists $p registered_model_state]} {
        set result [_queryRegisteredExecute $reference $action $values $bracket $context $host]
    } else {
        set captured [_queryCapturedModel $p]
        set output [_queryExecute $action $captured [::GX::ScientificTransportv1::array [list [llength $values] 1] $values] $bracketNode [dict get $context node] $host]
        set result [dict get $output values]
    }
    _recipeResultRecord $reference
    # The bounded Octave result envelope represents a 1-by-2 row as a vector.
    # Restore this API's declared N-by-2 points shape at its semantic boundary.
    if {$action eq "query"&&[llength $values]==1&&[llength [dict get $result points]]==2} {
        dict set result points [list [dict get $result points]]
    }
    dict set result reference $reference;dict set result accepted_name [dict get $record label]
    dict set result context [dict remove $context node]
    dict set result exact_query_count [llength $values]
    return $result
}
proc ::GX::DatasetCurveFit::resultQuery {reference values {options {}}} {return [_resultQuery $reference query $values {} $options]}
proc ::GX::DatasetCurveFit::resultInverse {reference targets bracket {options {}}} {return [_resultQuery $reference inverse $targets $bracket $options]}
proc ::GX::DatasetCurveFit::_queryExecute {action captured query bracket options host} {
    variable root;variable state
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set allocation [::GX::resourceManagementAllocate retained_fit_query [dict create kind directory session $::GX::currentSession lifetime computation]]
    set directory [dict get $allocation path];set run {}
    try {
        set model [dict get $captured node]
        if {[dict get $model fields restore value] eq "saved_json_file"} {
            set path [file join $directory retained_model.json];set channel [::open $path {WRONLY CREAT EXCL}]
            try {
                fconfigure $channel -translation binary -encoding binary
                if {[dict get $captured resource] ne {}} {
                    _exportModelResource [dict get $captured resource] $channel {}
                } else {puts -nonewline $channel [encoding convertto utf-8 [dict get $captured json]]}
            } finally {::close $channel}
            dict set model fields model [::GX::ScientificTransportv1::text $path]
        }
        set request [file join $directory request.ini];set response [file join $directory response.ini]
        ::GX::ScientificTransportv1::writeResult $request [dict create action [::GX::ScientificTransportv1::text $action] model $model query $query bracket $bracket options $options]
        set environment [dict create GXDCF_QUERY_REQUEST $request GXDCF_QUERY_RESULT $response GXDCF_NUMERIC_API_DIR [::GX::NumericAPIv1::octaveApiDir] GXDCF_CORE_OCTAVE_DIR [file join $root core octave]]
        set run [::GX::parallelExecutionNewRunId retained_fit_query];set progress {}
        if {$host ne {}} {set state($host,numericRun) $run;set progress [list ::GX::DatasetCurveFit::_numericProgress $host]}
        set executable [::GX::runtimeToolRequired octave]
        set task [dict create id query argv [list $executable --quiet --no-gui --path [file join $root plugins modules viewer.dataset_curve_fit api octave] --eval {dataset_curve_fit_query_v1('file')}]]
        set execution [::GX::parallelExecutionExecute [list $task] [dict create kind process command_builder ::GX::DatasetCurveFit::_numericCommand environment $environment] [dict create workers 1 run_id $run progress_command $progress]]
        if {[dict get $execution state] eq "cancelled"} {error {Retained model query cancelled}}
        set result [lindex [dict get $execution results] 0]
        if {[dict get $result state] ne "success"} {error "Retained model query failed: [dict get $result stderr] [dict get $result error]"}
        return [::GX::ScientificTransportv1::readResult $response]
    } finally {
        if {$run ne {}} {::GX::parallelExecutionRelease $run}
        if {$host ne {}&&[info exists state($host,numericRun)]} {set state($host,numericRun) {}}
        ::GX::resourceManagementRelease [dict get $allocation id]
        ::GX::resourceManagementCleanup [list [dict get $allocation id]]
    }
}
proc ::GX::DatasetCurveFit::_queryUnitLabel {plan} {
    if {[dict get $plan status] ne "value"} {return "unavailable: [dict get $plan reason]"}
    set unit [dict get $plan output_unit]
    if {![catch {::GX::unitTclCompatible $unit Ohm} compatible]&&$compatible} {append unit { (differential resistance dimensions)}}
    return $unit
}
proc ::GX::DatasetCurveFit::_queryReport {result} {
    set context [dict get $result context]
    set lines [list "Retained model: [dict get $result accepted_name]" "Exact requested rows: [dict get $result exact_query_count]" "Reference domain: [dict get $result domain]; [dict get $context domain_basis]" {No refit or confidence interval is implied.}]
    if {[dict exists $result points]} {
        lappend lines "Query unit: [dict get $context query_unit]; model response unit: [dict get $context response_unit]" "Derivative method: [dict get $result derivative_method]"
        if {[dict exists $result derivative_reason]} {lappend lines [dict get $result derivative_reason]}
        lappend lines "Physical X unit: [dict get $context x_unit]; physical Y unit: [dict get $context y_unit]" "dY/dX: [_queryUnitLabel [dict get $context derivative_unit_plan]]" "dX/dY: [_queryUnitLabel [dict get $context inverse_derivative_unit_plan]]" {Orange display segments touch an extrapolated query; markers show exact requested rows.} {} "query\tX\tY\tdY/dX\tdX/dY\textrapolated"
        foreach q [dict get $result query] point [dict get $result points] slope [dict get $result interpreted_derivative] inverse [dict get $result interpreted_inverse_derivative] valid [dict get $result interpreted_derivative_valid] inverseValid [dict get $result interpreted_inverse_derivative_valid] outside [dict get $result is_extrapolated] {
            set derivative unavailable;set reciprocal unavailable
            if {$valid} {set derivative [format %.10g $slope]};if {$inverseValid} {set reciprocal [format %.10g $inverse]}
            lassign $point x y;lappend lines "[format %.10g $q]\t[format %.10g $x]\t[format %.10g $y]\t$derivative\t$reciprocal\t$outside"
        }
    } else {
        lappend lines "Targets: [dict get $context response_unit]; roots: [dict get $context query_unit]" {Caller declares a continuous local branch; global uniqueness is not certified.} {} "target\troot\tresidual\tstatus"
        foreach target [dict get $result targets] root [dict get $result roots] residual [dict get $result residual] valid [dict get $result valid] reason [dict get $result reasons] {
            set value unavailable;set error unavailable
            if {$valid} {set value [format %.10g $root];set error [format %.10g $residual]}
            lappend lines "[format %.10g $target]\t$value\t$error\t$reason"
        }
    }
    return [join $lines \n]
}
proc ::GX::DatasetCurveFit::_queryOpen {w} {
    variable state
    set selected [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selected]!=1} {error {Select one accepted fit to query}}
    set record [lindex $state($w,records) [lindex $selected 0]]
    set state($w,queryReference) [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set p [dict get $record provenance];set domain {}
    if {[dict exists $p training_domain]} {set domain [split [dict get $p training_domain] ,]}
    set state($w,queryValues) $domain;set state($w,queryBracket) $domain;set state($w,queryLegacyDomain) {};set state($w,queryExtrapolate) 0
    set d $w.retainedQuery;if {[winfo exists $d]} {destroy $d}
    toplevel $d;wm title $d {Retained model queries and derivatives};wm transient $d $w
    wm protocol $d WM_DELETE_WINDOW [list ::GX::DatasetCurveFit::_queryClose $w]
    ttk::frame $d.controls -padding 8;pack $d.controls -side top -fill x
    foreach {id label} {queryValues {Values (queries or inverse response targets)} queryBracket {Continuous branch bracket for inverse} queryLegacyDomain {Explicit reference domain for historical fits only}} {
        ttk::label $d.controls.${id}Label -text $label;pack $d.controls.${id}Label -anchor w
        ttk::entry $d.controls.$id -textvariable ::GX::DatasetCurveFit::state($w,$id);pack $d.controls.$id -fill x -pady 2
    }
    ttk::checkbutton $d.controls.extrapolate -text {Explicitly allow queries outside the retained domain} -variable ::GX::DatasetCurveFit::state($w,queryExtrapolate);pack $d.controls.extrapolate -anchor w
    ttk::frame $d.actions;pack $d.actions -side top -fill x -padx 8
    foreach {id label} {query {Evaluate and differentiate} inverse {Find local inverse}} {
        ttk::button $d.actions.$id -text $label -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_queryRefresh $w $id]];pack $d.actions.$id -side left -padx 4
    }
    ttk::scrollbar $d.scroll -command [list $d.report yview];pack $d.scroll -side right -fill y
    text $d.report -wrap none -width 110 -height 24 -yscrollcommand [list $d.scroll set];pack $d.report -fill both -expand 1
    $d.report insert end {Enter exact values separated by spaces or commas. Queries return physical coordinates, derivatives with their declared method, inverse slopes and extrapolation flags. An inverse requires a continuous branch bracket and verifies its response residual. Unknown units and singular slopes remain unavailable.};$d.report configure -state disabled
    wm geometry $d 1100x650;bind $d <Escape> [list ::GX::DatasetCurveFit::_queryClose $w]
}
proc ::GX::DatasetCurveFit::_queryRefresh {w action} {
    variable state
    set options [dict create extrapolation [expr {$state($w,queryExtrapolate)?"allow":"error"}]]
    if {[string trim $state($w,queryLegacyDomain)] ne {}} {dict set options reference_domain [string map {, " "} $state($w,queryLegacyDomain)]}
    set saved [_operationBegin $w]
    try {
        set result [_resultQuery $state($w,queryReference) $action [string map {, " "} $state($w,queryValues)] [string map {, " "} $state($w,queryBracket)] $options $w]
        set d $w.retainedQuery;if {![winfo exists $d]} return
        $d.report configure -state normal;$d.report delete 1.0 end;$d.report insert end [_queryReport $result];$d.report configure -state disabled
        set state($w,queryResult) $result;set state($w,querySource) $state($w,activeSource);set state($w,querySession) [::GX::interactiveDocumentSessionToken]
        redraw $w
    } finally {_operationEnd $w $saved}
}
proc ::GX::DatasetCurveFit::_queryClose {w} {
    variable state
    unset -nocomplain state($w,queryResult) state($w,querySource)
    if {[winfo exists $w.retainedQuery]} {destroy $w.retainedQuery}
    if {[winfo exists $w]} {redraw $w}
}
proc ::GX::DatasetCurveFit::_queryDisplay {w} {
    variable state
    if {![info exists state($w,queryResult)]||![dict exists $state($w,queryResult) points]} {return {}}
    if {$state($w,querySource) ne $state($w,activeSource)||[catch {::GX::interactiveDocumentSessionToken} token]||$token ne $state($w,querySession)} {
        unset -nocomplain state($w,queryResult);return {}
    }
    set reference [dict get $state($w,queryResult) reference]
    if {[catch {::GX::interactiveDocumentRead [dict get $reference document_id]} document]||[dict get $document generation] ne [dict get $reference generation]} {
        unset -nocomplain state($w,queryResult);return {}
    }
    return $state($w,queryResult)
}
proc ::GX::DatasetCurveFit::_queryDraw {w canvas result} {
    set connect 1;set previous {}
    foreach q [dict get $result query] {if {$previous ne {}&&$q<$previous} {set connect 0};set previous $q}
    set previous {};set previousOutside 0
    foreach point [dict get $result points] outside [dict get $result is_extrapolated] {
        lassign $point x y;set screen [_screen $w $x $y];lassign $screen px py
        set color [expr {$outside?"#f59e0b":"#0ea5e9"}]
        if {$connect&&$previous ne {}} {
            set extrapolated [expr {$outside||$previousOutside}]
            set dash {};set lineColor #0ea5e9;set tags {retained_query_curve}
            if {$extrapolated} {set dash {6 4};set lineColor #f59e0b;lappend tags extrapolated_query}
            $canvas create line {*}$previous {*}$screen -fill $lineColor -width 2 -dash $dash -tags $tags
        }
        $canvas create oval [expr {$px-2.5}] [expr {$py-2.5}] [expr {$px+2.5}] [expr {$py+2.5}] -outline $color -fill $color -tags retained_query_marker
        set previous $screen;set previousOutside $outside
    }
}
