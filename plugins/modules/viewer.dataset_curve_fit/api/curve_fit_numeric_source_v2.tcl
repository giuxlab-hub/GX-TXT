# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset reading/display and exact Numeric input share the CORE Source API.
proc ::GX::DatasetCurveFit::_fitOrientation {model options} {
    set geometric [expr {$model in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial parametric_spline}}]
    set orientation [::GX::datasetPublicationV2DictDefault $options orientation [expr {$geometric ? "parametric" : "y_of_x"}]]
    if {$orientation ni {y_of_x x_of_y r_of_theta parametric}} {error "Unknown fit orientation '$orientation'"}
    if {$geometric&&$orientation ne "parametric"} {error "$model requires parametric X=x(t), Y=y(t) orientation"}
    if {!$geometric&&$orientation eq "parametric"} {error "$model requires Y=f(X), X=f(Y) or experimental R=f(theta) orientation"}
    return $orientation
}
proc ::GX::DatasetCurveFit::_defaultPolarFitFrame {scene} {
    set frame [::GX::Native2D::core polar $scene]
    return [dict create origin [dict get $frame origin] theta_zero [dict get $frame theta_zero] clockwise [dict get $frame clockwise] angle_unit [expr {[dict get $frame degrees] ? "deg" : "rad"}] unwrap_policy continuous angle_cut 0]
}
proc ::GX::DatasetCurveFit::_polarSettings {w} {
    variable state
    _assertLoaded $w
    set frame $state($w,polarFrame)
    set fields [dict create ox [dict create type number label {Fitting origin X} required 1] oy [dict create type number label {Fitting origin Y} required 1] zero [dict create type number label {Theta-zero direction (degrees)} required 1] clockwise [dict create type boolean label {Clockwise fitting angles}] unit [dict create type choice values {rad deg} label {Angle unit}] policy [dict create type choice values {continuous cut} label {Angular branch policy}] cut [dict create type number label {Angular cut in chosen angle unit} required 1]]
    set values [dict create ox [lindex [dict get $frame origin] 0] oy [lindex [dict get $frame origin] 1] zero [expr {[dict get $frame theta_zero]*180/acos(-1)}] clockwise [dict get $frame clockwise] unit [dict get $frame angle_unit] policy [dict get $frame unwrap_policy] cut [dict get $frame angle_cut]]
    ::GX::uiFieldFormCreate $w.polarFit "Experimental radial fitting frame" $fields $values [list ::GX::DatasetCurveFit::_polarApply $w $state($w,activeSource)] $w
}
proc ::GX::DatasetCurveFit::_polarApply {w owner values} {
    variable state
    if {$owner ne $state($w,activeSource)} {error "Active source changed; reopen radial settings"}
    _assertLoaded $w
    set state($w,polarFrame) [dict create origin [list [dict get $values ox] [dict get $values oy]] theta_zero [expr {[dict get $values zero]*acos(-1)/180}] clockwise [dict get $values clockwise] angle_unit [dict get $values unit] unwrap_policy [dict get $values policy] angle_cut [dict get $values cut]]
    _workspaceCapture $w;_saveState $w
    $w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    set state($w,status) "Radial fitting frame and angular branch saved. Preview again to apply; accepted geometry retains its original frame."
}
proc ::GX::DatasetCurveFit::_geometricMetricUnit {key} {
    variable state
    if {$state($key,sourceKind) in {builtin_sample sample}} {
        set axes [dict get [sampleDescriptor $state($key,dataset)] axes]
        set xUnit [dict get $axes x unit];set yUnit [dict get $axes y unit]
    } else {
        set variables [dict get [::GX::curveSourceDescribe $state($key,sourceToken)] variables]
        set xUnit [dict get [lindex $variables 0] unit];set yUnit [dict get [lindex $variables 1] unit]
    }
    if {$xUnit ne $yUnit} {error "Geometric fitting requires X/Y in the same declared unit ($xUnit versus $yUnit). Apply an explicit Unit Registry/Dataset Transform conversion first."}
    return $xUnit
}
proc ::GX::DatasetCurveFit::_uiFitOptions {w} {
    variable state
    set options [dict create smoothing_lambda $state($w,smoothing) period $state($w,period) orientation $state($w,orientation)]
    if {$state($w,orientation) eq "r_of_theta"} {dict set options polar_frame $state($w,polarFrame)}
    if {$state($w,model) in {parametric_polynomial parametric_spline}} {
        dict set options topology $state($w,topology);dict set options parameterization $state($w,parameterization)
        if {$state($w,parameterization) eq "user_parameter"} {dict set options parameter_variable_id $state($w,parameterVariable);if {$state($w,userPeriod) ne ""} {dict set options user_period $state($w,userPeriod)}}
        if {$state($w,closureTolerance) ne ""} {dict set options closure_tolerance $state($w,closureTolerance)}
    }
    return $options
}
proc ::GX::DatasetCurveFit::_orientationLabels {w} {
    variable state
    set state($w,orientationLabel) [dict get {y_of_x {Y = f(X)} x_of_y {X = f(Y)} r_of_theta {R = f(theta) (experimental)} parametric {X=x(t), Y=y(t)}} $state($w,orientation)]
    if {$state($w,model) in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial parametric_spline}} {
        $w.settings.orientation configure -values {{X=x(t), Y=y(t)}}
    } else {$w.settings.orientation configure -values {{Y = f(X)} {X = f(Y)} {R = f(theta) (experimental)}}}
}
proc ::GX::DatasetCurveFit::_uiOrientation {w} {
    variable state
    set state($w,orientation) [dict get {{Y = f(X)} y_of_x {X = f(Y)} x_of_y {R = f(theta) (experimental)} r_of_theta {X=x(t), Y=y(t)} parametric} $state($w,orientationLabel)]
    _uiDomainFields $w;_workspaceCapture $w;_saveState $w
    set state($w,status) "Fit orientation: $state($w,orientationLabel). Preview again to apply."
    _uiModelFields $w
    $w.actions.accept configure -state disabled
    $w.actions.publish configure -state disabled
}
proc ::GX::DatasetCurveFit::_parametricSettings {w} {
    variable state
    _assertLoaded $w
    set ids {}
    if {$state($w,sourceKind) eq "dataset"} {set ids [dict get [variables $state($w,dataset)] numeric]}
    set fields [dict create topology [dict create type choice label Topology values {auto open closed}] parameterization [dict create type choice label Parameterization values {{Row order} {Path length} {Dataset variable}}] parameterVariable [dict create type choice label {Dataset parameter Variable ID} values [linsert $ids 0 ""]] userPeriod [dict create type number label {Closed user-parameter period (blank = none)} min 0 allow_inherit 1] closureTolerance [dict create type number label {Endpoint closure tolerance (blank = scale default)} min 0 allow_inherit 1]]
    set values [dict create topology $state($w,topology) parameterization [dict get {row_order {Row order} path_length {Path length} user_parameter {Dataset variable}} $state($w,parameterization)] parameterVariable $state($w,parameterVariable) userPeriod $state($w,userPeriod) closureTolerance $state($w,closureTolerance)]
    ::GX::uiFieldFormCreate $w.parametric "Parametric curve settings" $fields $values [list ::GX::DatasetCurveFit::_parametricApply $w $state($w,activeSource)] $w
}
proc ::GX::DatasetCurveFit::_parametricApply {w owner values} {
    variable state
    if {$state($w,activeSource) ne $owner} {error "Active source changed; reopen parametric settings"}
    set mode [dict get {{Row order} row_order {Path length} path_length {Dataset variable} user_parameter} [dict get $values parameterization]]
    if {$mode eq "user_parameter"} {
        if {$state($w,sourceKind) ne "dataset"} {error "User parameters need a real Dataset variable"}
        if {[dict get $values parameterVariable] ni [dict get [variables $state($w,dataset)] numeric]} {error "Choose a numeric Dataset parameter variable"}
    }
    if {$state($w,model) eq "parametric_polynomial"&&[dict get $values topology] eq "closed"} {error "Closed interpolation requires the periodic parametric_spline model"}
    dict set values parameterization $mode
    dict for {field value} $values {set state($w,$field) $value}
    _workspaceCapture $w;_saveState $w
    $w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    set state($w,status) "Parametric settings applied. Preview again to fit exact source rows."
}
proc ::GX::DatasetCurveFit::_swapFormulaAxes {text} {
    set text [regsub -all {\mx\M} $text __GX_CURVE_AXIS__]
    set text [regsub -all {\my\M} $text x]
    return [string map {__GX_CURVE_AXIS__ y} $text]
}
proc ::GX::DatasetCurveFit::formula {result} {
    set text [_formulaBase $result]
    if {[::GX::datasetPublicationV2DictDefault $result orientation y_of_x] eq "r_of_theta"} {regsub -all {\my\M} $text R text;return [regsub -all {\mx\M} $text theta]}
    set orientation [::GX::datasetPublicationV2DictDefault $result orientation y_of_x]
    if {$orientation eq "x_of_y"} {set text [_swapFormulaAxes $text]}
    if {[dict get $result model] in {pchip smoothing_spline fourier}} {set text "[expr {$orientation eq "x_of_y" ? "X=f(Y)" : "Y=f(X)"}]: $text"}
    return $text
}
proc ::GX::DatasetCurveFit::_assertSession {key} {
    variable state
    if {$state($key,sessionToken) ne "" && $state($key,sessionToken) ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen Curve Fit"}
}
proc ::GX::DatasetCurveFit::_disposePreview {key} {
    variable state
    if {$state($key,preview) eq {}} return
    _disposeReport $state($key,scene) $state($key,preview)
}
proc ::GX::DatasetCurveFit::_disposeReport {scene report} {
    foreach field {fitted_native residual_native} {if {[dict exists $report $field]} {::GX::Native2D::core delete $scene [dict get $report $field]}}
}
rename ::GX::DatasetCurveFit::loadSource ::GX::DatasetCurveFit::loadSource_v1
proc ::GX::DatasetCurveFit::loadSource {key dataset x y filters {transformManifest {}} {expectedIdentities {}}} {
    variable state
    if {$x eq $y} {error "Choose distinct X and Y variables"}
    set schema [variables $dataset]
    if {$x ni [dict get $schema numeric]||$y ni [dict get $schema numeric]} {error "X and Y must be numeric Dataset variables"}
    set mapped {};set operations [dict create = exact_equal != not_equal < less_than <= less_equal > greater_than >= greater_equal contains contains LIKE like]
    foreach filter $filters {
        foreach field {variable operator value} {if {![dict exists $filter $field]} {error "Filter needs $field"}}
        set variable [dict get $filter variable];set operator [dict get $filter operator];set value [dict get $filter value]
        if {![dict exists $schema kinds $variable]} {error "Unknown filter variable '$variable'"}
        if {[dict get $schema kinds $variable] eq "number"} {
            if {$operator ni {= != < <= > >= between}} {error "Invalid numeric filter operator '$operator'"}
            if {$operator eq "between"} {
                if {[llength $value]!=2} {error "between needs two bounds"}
                lassign $value lo hi;_finite $lo "Lower bound";_finite $hi "Upper bound"
                if {$lo>$hi} {error "between bounds are reversed"}
            } else {_finite $value "Filter value"}
        } elseif {$operator ni {= != contains LIKE}} {error "Invalid text filter operator '$operator'"}
        if {$operator eq "between"} {set converted [dict create filter_variable_id $variable predicate between_inclusive lower $lo upper $hi]} else {set converted [dict create filter_variable_id $variable predicate [dict get $operations $operator] value $value]}
        lappend mapped $converted
    }
    set request [dict create dataset_id $dataset x_variable_id $x y_variable_id $y display_budget 4096]
    if {$transformManifest ne {}} {dict set request transform_manifest $transformManifest} else {dict set request filters $mapped}
    set token [::GX::curveSourceOpen $::GX::currentSession $request]
    try {
        set descriptor [::GX::curveSourceDescribe $token]
        if {$expectedIdentities ne {}&&[dict get $descriptor source_identities] ne $expectedIdentities} {error "Saved source scientific schema or content changed; reload explicitly"}
        if {[info exists state($key,loading)]&&$state($key,loading)} {set display [::GX::curveSourceDisplayResponsive $token [list ::GX::DatasetCurveFit::_sourceProgress $key]]} else {set display [::GX::curveSourceDisplay $token]}
        if {[dict get $display finite_rows]<2} {error "At least two finite Dataset rows must pass the filters"}
        set source [_replaceSource $key [dict get $display points] [dict get $display source_rows] dataset $dataset $x $y $filters]
        if {[dict get $display breaks] ne {}} {::GX::Native2D::core set_breaks $state($key,scene) $source [dict get $display breaks]}
        set state($key,sourceToken) $token;set state($key,sourceDescriptor) $descriptor
        set state($key,sourceTransformManifest) $transformManifest
        set state($key,sourceIdentities) [dict get $descriptor source_identities]
        _workspaceCapture $key;_workspaceRefresh $key
        set token "";return $source
    } finally {if {$token ne ""} {::GX::curveSourceClose $token}}
}
proc ::GX::DatasetCurveFit::_sourceProgress {w progress} {
    variable state
    set state($w,sourceJob) [dict get $progress job_id]
    set state($w,status) "Loading exact Dataset source: [dict get $progress completed_rows] / [dict get $progress total_rows] rows. Escape cancels."
    if {$state($w,sourceCancelled)} {::GX::curveSourceCancel $state($w,sourceJob);set state($w,sourceJob) ""}
}
proc ::GX::DatasetCurveFit::_sourceCancel {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {
        set state($w,sourceCancelled) 1
        if {$state($w,sourceJob) ne ""} {::GX::curveSourceCancel $state($w,sourceJob);set state($w,sourceJob) ""}
        if {[info exists state($w,numericRun)]&&$state($w,numericRun) ne ""} {::GX::parallelExecutionCancel $state($w,numericRun)}
        return 1
    }
    return 0
}
proc ::GX::DatasetCurveFit::_operationBegin {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {error "Another Curve Fit operation is active"}
    set state($w,loading) 1;set state($w,sourceJob) "";set state($w,numericRun) ""
    set state($w,sourceCancelled) 0;set state($w,closeRequested) 0
    unset -nocomplain state($w,press)
    $w.canvas delete selection_drag
    set saved [_sourceControls $w 1]
    $w.filter.cancel configure -state normal
    return $saved
}
proc ::GX::DatasetCurveFit::_operationEnd {w saved} {
    variable state
    set state($w,loading) 0;set state($w,sourceJob) "";set state($w,numericRun) ""
    _sourceControls $w 0 $saved
    _workspaceRefresh $w
    $w.filter.cancel configure -state disabled
    if {$state($w,closeRequested)} {after idle [list ::GX::DatasetCurveFit::_closeWindow $w]}
}
proc ::GX::DatasetCurveFit::reverseSource {key {span {}}} {
    variable state
    _assertLoaded $key
    if {$state($key,sourceKind) ne "dataset"} {error "Dataset source reversal needs a real Session Dataset"}
    set total [dict get $state($key,sourceDescriptor) row_count]
    if {$span eq {}} {set span [list 0 $total]}
    if {[llength $span]!=2} {error "Reverse span needs exact start/count"}
    lassign $span start count
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$start+$count>$total} {error "Reverse span is outside exact source rows"}
    set manifest $state($key,sourceTransformManifest)
    if {$manifest eq {}} {
        set source [dict create dataset_id $state($key,dataset) x_variable_id $state($key,x) y_variable_id $state($key,y)]
        set filters [::GX::datasetPublicationV2DictDefault [dict get $state($key,sourceDescriptor) request] filters {}]
        if {$filters ne {}} {dict set source row_filters $filters}
        set ids [lmap variable [::GX::datasetVariableSchemaV3 $state($key,dataset)] {dict get $variable variable_id}]
        set suffix 0
        while {1} {
            set prefix "curve_fit_reverse${suffix}_";set collision 0
            foreach field {member_id source_dataset_id source_sha256 source_row_ordinal source_x_variable_id source_y_variable_id} {if {"$prefix$field" in $ids} {set collision 1;break}}
            if {!$collision} break
            incr suffix
        }
        set manifest [dict create api_version 1 operation reverse_sequence sources [list $source] options [dict create steps {} include_lineage 1 lineage_prefix $prefix]]
    }
    if {[dict get $manifest operation] ne "reverse_sequence"} {error "This source needs an explicit compatible reversal recipe"}
    set steps [dict get $manifest options steps];lappend steps $span;dict set manifest options steps $steps
    set owner $state($key,activeSource)
    loadSource $key $state($key,dataset) $state($key,x) $state($key,y) $state($key,filters) $manifest
    dict set state($key,sources) $state($key,activeSource) derived_from_source $owner
    return $state($key,activeSource)
}
proc ::GX::DatasetCurveFit::_uiReverseSource {w selected} {
    variable state
    _assertLoaded $w
    set controls [_operationBegin $w]
    try {
        set span {}
        if {$selected} {
            set indices [selectedIndices $w]
            if {[llength $indices]<2} {error "Select at least two span endpoints"}
            set endpoints [list [lindex $state($w,rows) [lindex $indices 0]] [lindex $state($w,rows) [lindex $indices end]]]
            set positions [dict get [::GX::curveSourceLocateRows $state($w,sourceToken) $endpoints [list ::GX::DatasetCurveFit::_stagingProgress $w]] positions]
            lassign [lsort -integer $positions] start last
            set span [list $start [expr {$last-$start+1}]]
        }
        set source [reverseSource $w $span]
    } finally {_operationEnd $w $controls}
    set state($w,report) "";$w.residuals delete [$w.residuals children {}]
    $w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    set state($w,status) "Added $source with exact complete rows reversed through Dataset Transform; the previous source and its fits remain available."
    _saveState $w;redraw $w
}
proc ::GX::DatasetCurveFit::_stagingProgress {w progress} {
    variable state
    if {$state($w,sourceCancelled)} {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} "Fitting cancelled"}
    set state($w,status) "Preparing exact Numeric input: [dict get $progress completed_rows] / [dict get $progress total_rows] rows. Escape cancels."
}
proc ::GX::DatasetCurveFit::_numericCommand {item context} {return [dict get $item argv]}
proc ::GX::DatasetCurveFit::_numericProgress {w progress} {
    variable state
    if {$state($w,sourceCancelled)} {::GX::parallelExecutionCancel [dict get $progress run_id]}
    set state($w,status) "Numerical fit: [dict get $progress message]. Escape cancels."
}
proc ::GX::DatasetCurveFit::_sourceControls {w disabled {saved {}}} {
    if {!$disabled} {
        foreach {widget state} $saved {if {[winfo exists $widget]} {$widget configure -state $state}}
        $w.workspace.sources configure -selectmode extended
        return
    }
    set pending [list $w];set saved {}
    while {$pending ne {}} {
        set widget [lindex $pending 0];set pending [concat [lrange $pending 1 end] [winfo children $widget]]
        if {![catch {$widget cget -state} state]&&[winfo class $widget] ni {Canvas TLabel}} {
            lappend saved $widget $state;$widget configure -state disabled
        }
    }
    $w.workspace.sources configure -selectmode none
    return $saved
}
proc ::GX::DatasetCurveFit::_numericSource {key model degree initial scope selected domain options input} {
    variable state
    if {$state($key,documentId) eq ""} {
        set state($key,documentId) [dict get [::GX::interactiveDocumentCreate viewer.dataset_curve_fit dataset_curve_fit gxtxt.dataset_curve_fit.viewer 2.0 [dict create version 2 workspace_sources {} active_source "" next_source 0 next_fit 0 records {} view_bounds {} presentation [::GX::Native2D::core presentation $state($key,scene)]]] id]
    }
    set training [expr {$scope eq "all" ? $input : [dict get $input training]}]
    set hostKey [expr {[info exists state($key,loading)]&&$state($key,loading) ? $key : ""}]
    set parameter [::GX::datasetPublicationV2DictDefault $options parameter_variable_id ""]
    if {$parameter ne ""} {set parameterDescriptor [::GX::datasetVariableV3ById $state($key,dataset) $parameter]}
    set result [_runNumeric $model $degree $initial $training $input $domain $options $state($key,scene) $state($key,documentId) $hostKey]
    if {$parameter ne ""} {dict set result parameter_variable_descriptor $parameterDescriptor}
    return $result
}
proc ::GX::DatasetCurveFit::_selectionDescriptor {key} {
    variable state
    set descriptor [::GX::Native2D::core selection_state $state($key,selectionScene) $state($key,selectionObject) 0 [llength $state($key,rows)]]
    set overrides {}
    foreach pair [dict get $descriptor manual] {lassign $pair index mode;dict set overrides [lindex $state($key,rows) $index] $mode}
    return [dict create api_id CURVE_SOURCE_POINT_MASK_v1 base_selected [dict get $descriptor base_selected] regions [dict get $descriptor regions] manual_rows $overrides]
}
proc ::GX::DatasetCurveFit::_selectionUnchanged {key report} {
    if {[dict exists $report selection_descriptor]} {return [expr {[dict get $report selection_descriptor] eq [_selectionDescriptor $key]}]}
    return [expr {[dict get $report selected_indices] eq [selectedIndices $key]}]
}
proc ::GX::DatasetCurveFit::_restoreSelectionDescriptor {key descriptor} {
    variable state
    set scene $state($key,selectionScene);set object $state($key,selectionObject)
    ::GX::Native2D::core clear $scene
    set state($key,rects) {}
    if {[dict get $descriptor base_selected]} {::GX::Native2D::core select_object $scene $object add}
    foreach region [dict get $descriptor regions] {
        lappend state($key,rects) [::GX::Native2D::core rect $scene [dict get $region bounds] [dict get $region mode]]
    }
    foreach pair [dict get $descriptor manual] {
        lassign $pair index mode
        ::GX::Native2D::core select $scene $object $index [expr {$mode==1 ? "add" : "subtract"}]
    }
}
proc ::GX::DatasetCurveFit::_numericNativeResult {scene document temporary input report} {
    set fitted "";set residual ""
    try {
        if {[::GX::datasetPublicationV2DictDefault $report model_state_storage inline] eq "document_resource"} {
            dict set report model_state_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temporary model_state.json] [dict create format gxtxt.numeric_curve_model_json_v1 encoding utf-8 model [dict get $report model]]]
        }
        set fitted [::GX::native2DLoadNumericRows $scene [file join $temporary fitted.csv]]
        ::GX::Native2D::core object_style $scene $fitted {visible 0 selectable 0}
        set sampled [::GX::Native2D::core object_sample $scene $fitted 4096]
        dict set report fitted [dict get $sampled points]
        dict set report fitted_native $fitted
        dict set report fitted_breaks [dict get $sampled breaks]
        set stride [::GX::datasetPublicationV2DictDefault $report residual_stride 4]
        set xColumn [expr {[dict get $report parametric]||[dict get $report orientation] eq "r_of_theta" ? 5 : ([dict get $report orientation] eq "x_of_y" ? 1 : 0)}]
        set residual [::GX::native2DLoadNumericRows $scene [file join $temporary residual.csv] $stride $xColumn 3]
        ::GX::Native2D::core object_style $scene $residual {visible 0 selectable 0}
        dict set report residual_native $residual
        dict set report residual_display [dict get [::GX::Native2D::core object_sample $scene $residual 4096] points]
        dict set report residual_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temporary residual.csv] [dict create format float64_interleaved_le columns [split [dict get $report residual_columns] ,] row_count [dict get $report source_n]]]
        dict set report source_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document [dict get $input source_rows_file] [dict create format uint64_le row_count [dict get $input row_count]]]
        set page [_numericResidualPage $report 0 200]
        dict set report residual [dict get $page rows];dict set report residual_rows [dict get $page source_rows]
        dict set report exact_source_rows [dict get $input row_count]
        dict set report display_is_scientific_data 0
        return $report
    } on error {message options} {
        foreach id [list $fitted $residual] {if {$id ne ""} {::GX::Native2D::core delete $scene $id}}
        return -options $options $message
    }
}
proc ::GX::DatasetCurveFit::_numericResidualPage {report start count} {
    set total [dict get $report source_n]
    if {![string is entier -strict $start]||$start<0||$start>$total||![string is entier -strict $count]||$count<1||$count>1000} {error "Residual page is outside its bounded range"}
    set n [expr {min($count,$total-$start)}]
    set stride [llength [dict get $report residual_resource metadata columns]]
    binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $report residual_resource] [expr {8*$stride*$start}] [expr {8*$stride*$n}]] q* values
    binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $report source_rows_resource] [expr {8*$start}] [expr {8*$n}]] wu* rows
    set result {};for {set i 0} {$i<$n} {incr i} {lappend result [lrange $values [expr {$stride*$i}] [expr {$stride*$i+$stride-1}]]}
    return [dict create start $start row_count $total source_rows $rows rows $result]
}
proc ::GX::DatasetCurveFit::_residualColumns {w report} {
    variable state
    set geometric [dict get $report parametric]
    if {[dict get $report orientation] eq "r_of_theta"} {
        set columns {row x observed fitted residual radius theta};$w.residuals configure -columns $columns
        foreach {column heading} {row {Original source row} x {Source X} observed {Source Y} fitted {Fitted radius} residual {Radial residual (observed − fitted)} radius {Observed radius} theta Theta} {
            $w.residuals heading $column -text $heading;$w.residuals column $column -width [expr {$column eq "residual" ? 230 : 135}] -stretch 1
        }
        return
    }
    set columns [expr {$geometric ? {row x observed fitted residual projected_x parameter} : {row x observed fitted residual}}]
    $w.residuals configure -columns $columns
    set rowLabel [expr {$state($w,sourceKind) eq "dataset" ? "Dataset row" : "Sample row"}]
    set derived [expr {[::GX::datasetPublicationV2DictDefault $report orientation y_of_x] eq "x_of_y" ? "X" : "Y"}]
    foreach {column heading} [list row $rowLabel x {Source X} observed {Source Y} fitted [expr {$geometric ? "Projection Y" : "Fitted $derived"}] residual [expr {$geometric ? "Signed geometric distance" : "$derived residual (observed − fitted)"}] projected_x {Projection X} parameter {Normalized parameter}] {
        if {$column ni $columns} continue
        $w.residuals heading $column -text $heading
        $w.residuals column $column -width [expr {$column eq "residual" ? 210 : 135}] -stretch 1
    }
}
