# GX-TXT Dataset Curve Fit viewer. Data comes from canonical Dataset APIs;
# graphics/selection are backed by Native 2D; math is NUMERIC_API_v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::DatasetCurveFit {
    variable state
    variable serial 0
    variable version "0.44.0"
    variable root [file normalize [file join [file dirname [info script]] ../../../..]]
}

proc ::GX::DatasetCurveFit::_native {} {::GX::native2DEnsure}
proc ::GX::DatasetCurveFit::_finite {value label} {
    if {![string is double -strict $value] || [catch {set n [expr {double($value)}]}] || $n != $n || abs($n) == Inf} {error "$label must be finite"}
    return $n
}
proc ::GX::DatasetCurveFit::datasets {} {
    set result {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        if {[catch {set vars [variables $id]}]} continue
        if {[llength [dict get $vars numeric]] >= 2} {lappend result $id}
    }
    return [lsort -dictionary $result]
}
proc ::GX::DatasetCurveFit::variables {dataset} {
    set all {}; set numeric {}; set kinds [dict create];set labels [dict create]
    foreach v [::GX::datasetVariableSchema $dataset] {
        if {![dict get $v enabled] || ([dict exists $v rank] && [dict get $v rank] != 1)} continue
        set id [dict get $v variable_id]
        set kind [dict get $v value_kind]
        if {$kind ni {number text}} continue
        lappend all $id; dict set kinds $id $kind
        set label [expr {[dict exists $v display_label] && [string trim [dict get $v display_label]] ne "" ? [dict get $v display_label] : [dict get $v canonical]}]
        if {[string trim $label] eq ""} {set label $id}
        if {[dict exists $v unit] && [string trim [dict get $v unit]] ne ""} {append label " ([dict get $v unit])"}
        dict set labels $id $label
        if {$kind eq "number"} {lappend numeric $id}
    }
    return [dict create all $all numeric $numeric kinds $kinds labels $labels]
}
proc ::GX::DatasetCurveFit::_uiVariableChoices {w} {
    variable state
    set schema $state($w,schema)
    set counts [dict create]
    foreach id [dict get $schema all] {
        set label [dict get [dict get $schema labels] $id]
        dict incr counts $label
    }
    set displayToId [dict create]
    set idToDisplay [dict create]
    foreach id [dict get $schema all] {
        set label [dict get [dict get $schema labels] $id]
        if {$state($w,showIds) || [dict get $counts $label] > 1} {append label " \[$id\]"}
        dict set displayToId $label $id
        dict set idToDisplay $id $label
    }
    set state($w,displayToId) $displayToId
    set state($w,idToDisplay) $idToDisplay
    foreach {field widget candidates} [list x $w.left.viewport.content.source.body.x [dict get $schema numeric] y $w.left.viewport.content.source.body.y [dict get $schema numeric] filterVar $w.left.viewport.content.filters.controls.variable [dict get $schema all]] {
        $widget configure -values [lmap id $candidates {dict get $idToDisplay $id}]
        if {$field eq "filterVar"} {set displayField displayFilterVar} else {set displayField "display[string toupper [string index $field 0]][string range $field 1 end]"}
        set state($w,$displayField) [expr {$state($w,$field) ne "" && [dict exists $idToDisplay $state($w,$field)] ? [dict get $idToDisplay $state($w,$field)] : ""}]
    }
}
proc ::GX::DatasetCurveFit::_uiSelectVariable {w field} {
    variable state
    if {$field eq "filterVar"} {set displayField displayFilterVar} else {set displayField "display[string toupper [string index $field 0]][string range $field 1 end]"}
    set label $state($w,$displayField)
    if {![dict exists $state($w,displayToId) $label]} {error "Unknown variable selection: $label"}
    set state($w,$field) [dict get $state($w,displayToId) $label]
    if {$field eq "filterVar"} {_uiFilterOperator $w} else {_markSourceDirty $w}
}
proc ::GX::DatasetCurveFit::_like {value pattern} {
    set regex ^
    foreach ch [split $pattern ""] {
        if {$ch eq "%"} {append regex .*; continue}
        if {$ch eq "_"} {append regex .; continue}
        if {[regexp -- {[][\\.^$|?*+(){}]} $ch]} {append regex \\}
        append regex $ch
    }
    append regex {$}
    return [regexp -- $regex $value]
}
proc ::GX::DatasetCurveFit::filterMatch {kind observed op wanted} {
    if {$kind eq "number"} {
        if {$op ni {= != < <= > >= between}} {error "Invalid numeric filter operator $op"}
        if {[catch {set a [_finite $observed "Filtered value"]}]} {return 0}
        if {$op eq "between"} {
            if {[llength $wanted] != 2} {error "between needs two bounds"}
            lassign $wanted lo hi
            set lo [_finite $lo "Lower bound"];set hi [_finite $hi "Upper bound"]
            if {$lo > $hi} {error "between bounds are reversed"}
            return [expr {$a >= $lo && $a <= $hi}]
        }
        set b [_finite $wanted "Filter value"]
        switch -- $op {
            = {return [expr {$a == $b}]}
            != {return [expr {$a != $b}]}
            < {return [expr {$a < $b}]}
            <= {return [expr {$a <= $b}]}
            > {return [expr {$a > $b}]}
            >= {return [expr {$a >= $b}]}
        }
    }
    if {$kind ne "text" || $op ni {= != contains LIKE}} {error "Invalid text filter operator $op"}
    switch -- $op {
        = {return [string equal $observed $wanted]}
        != {return [expr {![string equal $observed $wanted]}]}
        contains {return [expr {[string first $wanted $observed] >= 0}]}
        LIKE {return [_like $observed $wanted]}
    }
}
proc ::GX::DatasetCurveFit::new {} {
    variable state
    variable serial
    _native
    set key "fit[incr serial]"
    set state($key,scene) [::GX::Native2D::core scene]
    if {[catch {set state($key,selectionScene) [::GX::Native2D::core scene]} err options]} {
        ::GX::Native2D::core destroy $state($key,scene)
        unset state($key,scene)
        return -options $options $err
    }
    set state($key,source) "";set state($key,accepted) "";set state($key,preview) {}
    set state($key,selectionObject) ""
    set state($key,previewAccepted) 0;set state($key,previewFitId) ""
    set state($key,rows) {};set state($key,filters) {}
    set state($key,loadedBinding) {};set state($key,sourceSha) ""
    set state($key,records) {};set state($key,rects) {};set state($key,viewBounds) {}
    set state($key,documentId) "";set state($key,sessionToken) [expr {$::GX::currentSession eq "" ? "" : [::GX::interactiveDocumentSessionToken]}]
    set state($key,sources) {};set state($key,activeSource) "";set state($key,nextSource) 0;set state($key,nextFit) 0
    set state($key,showResiduals) 1;set state($key,residualFraction) .60;set state($key,residualAxis) source
    set state($key,deferDispose) 0;set state($key,orientation) y_of_x
    set state($key,sourceStatus) ready;set state($key,sourceError) "";set state($key,savedSelection) {};set state($key,sourcePointCount) 0
    set state($key,polarFrame) [_defaultPolarFitFrame $state($key,scene)]
    set state($key,noiseModel) unspecified;set state($key,confidence) 0.95
    set state($key,bootstrapSettings) {};set state($key,profileSettings) {};set state($key,influenceDiagnostics) 0;set state($key,predictionBand) none;set state($key,predictionSigma) {};set state($key,predictionWeights) {}
    set state($key,covarianceSettings) {};set state($key,measurementKind) none;set state($key,measurementVariable) {};set state($key,measurementIndependentVariable) {};set state($key,measurementMissing) error
    set state($key,solverSettings) {}
    set state($key,smoothingSettings) {};set state($key,knotSettings) {}
    set state($key,componentRecipe) {}
    set state($key,regionRecipe) {}
    set state($key,formulaRecipe) {};set state($key,rationalRecipe) {};set state($key,rationalExtrapolation) error;set state($key,implicitRecipe) {};set state($key,implicitBranch) {};set state($key,complexRecipe) {};set state($key,complexData) {}
    foreach axis {U V} {set state($key,translation${axis}Mode) auto;set state($key,translation${axis}Delta) 0}
    return $key
}
proc ::GX::DatasetCurveFit::close {key} {
    variable state
    _parameterClear $key
    if {[info exists state($key,configurationSubscription)]} {::GX::configurationUnsubscribe $state($key,configurationSubscription)}
    if {[info exists state($key,catalogSubscription)]} {::GX::datasetCatalogUnsubscribe $state($key,catalogSubscription)}
    if {[info exists state($key,catalogAfter)]&&$state($key,catalogAfter) ne ""} {after cancel $state($key,catalogAfter)}
    _workspaceCapture $key
    foreach entry [dict values $state($key,sources)] {
        if {[dict exists $entry state sourceToken]&&[dict get $entry state sourceToken] ne ""} {::GX::curveSourceClose [dict get $entry state sourceToken]}
        set other [dict get $entry state selectionScene]
        if {$other ne $state($key,selectionScene)} {::GX::Native2D::core destroy $other}
    }
    if {[info exists state($key,scene)]} {::GX::Native2D::core destroy $state($key,scene)}
    if {[info exists state($key,selectionScene)]} {::GX::Native2D::core destroy $state($key,selectionScene)}
    if {[info exists state($key,residualViewScene)]} {::GX::Native2D::core destroy $state($key,residualViewScene)}
    foreach name [array names state "$key,*"] {unset state($name)}
}
proc ::GX::DatasetCurveFit::loadSource {key dataset xId yId filters} {
    variable state
    if {$xId eq $yId} {error "Choose distinct X and Y variables"}
    set schema [variables $dataset]
    if {$xId ni [dict get $schema numeric] || $yId ni [dict get $schema numeric]} {error "X and Y must be numeric Dataset variables"}
    set ids [list $xId $yId]
    foreach filter $filters {
        foreach field {variable operator value} {if {![dict exists $filter $field]} {error "Filter needs $field"}}
        set var [dict get $filter variable]
        if {![dict exists [dict get $schema kinds] $var]} {error "Unknown filter variable $var"}
        set kind [dict get [dict get $schema kinds] $var]
        set op [dict get $filter operator];set value [dict get $filter value]
        if {$kind eq "number"} {
            if {$op ni {= != < <= > >= between}} {error "Invalid numeric filter operator $op"}
            if {$op eq "between"} {
                if {[llength $value] != 2} {error "between needs two bounds"}
                lassign $value lo hi;_finite $lo "Lower bound";_finite $hi "Upper bound"
                if {$lo > $hi} {error "between bounds are reversed"}
            } else {_finite $value "Filter value"}
        } elseif {$op ni {= != contains LIKE}} {error "Invalid text filter operator $op"}
        if {$var ni $ids} {lappend ids $var}
    }
    set stream [::GX::tableStreamOpenDataset [::GX::sessionInspectionCurrentSession] $dataset $ids 4096]
    set rows {};set points {}
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]
            set values [dict get $chunk values]
            for {set i 0} {$i < [dict get $chunk nrows]} {incr i} {
                set include 1
                foreach filter $filters {
                    set var [dict get $filter variable]
                    if {![filterMatch [dict get [dict get $schema kinds] $var] [lindex [dict get $values $var] $i] [dict get $filter operator] [dict get $filter value]]} {set include 0;break}
                }
                if {!$include} continue
                if {[catch {set x [_finite [lindex [dict get $values $xId] $i] X];set y [_finite [lindex [dict get $values $yId] $i] Y]}]} continue
                lappend points [list $x $y]
                lappend rows [expr {[dict get $chunk offset]+$i}]
            }
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    if {[llength $points] < 2} {error "At least two finite Dataset rows must pass the filters"}
    return [_replaceSource $key $points $rows dataset $dataset $xId $yId $filters]
}
proc ::GX::DatasetCurveFit::_replaceSource {key points rows kind sourceId xId yId filters} {
    variable state
    # Build the new source first; preserve the prior scene if reading fails.
    set scene $state($key,scene)
    set selectionScene $state($key,selectionScene)
    set freshSelection [::GX::Native2D::core scene]
    set source ""
    if {[catch {
        set source [::GX::Native2D::core add $scene $points]
        ::GX::Native2D::core style $scene $source {0.12 0.38 0.82} 2
        set selectionObject [::GX::Native2D::core pointset $freshSelection $points]
    } err options]} {
        if {$source ne ""} {::GX::Native2D::core delete $scene $source}
        ::GX::Native2D::core destroy $freshSelection
        return -options $options $err
    }
    _workspaceCapture $key
    if {$state($key,activeSource) eq ""} {::GX::Native2D::core destroy $selectionScene}
    unset -nocomplain state($key,recipePointMask) state($key,influenceLinkedPoint) state($key,templateBinding)
    set state($key,source) $source
    set state($key,selectionScene) $freshSelection;set state($key,selectionObject) $selectionObject
    set state($key,accepted) "";set state($key,preview) {};set state($key,previewAccepted) 0;set state($key,previewFitId) ""
    set state($key,rows) $rows;set state($key,dataset) $sourceId
    set state($key,sourceStatus) ready;set state($key,sourceError) "";set state($key,savedSelection) {};set state($key,sourcePointCount) [llength $rows]
    set state($key,polarFrame) [_defaultPolarFitFrame $scene]
    set state($key,x) $xId;set state($key,y) $yId;set state($key,filters) $filters
    set state($key,sourceKind) $kind
    set state($key,sourceToken) "";set state($key,sourceDescriptor) {}
    set state($key,sourceTransformManifest) {}
    set state($key,sourceIdentities) {}
    set state($key,loadedBinding) [list $sourceId $xId $yId $filters]
    set state($key,sourceSha) [expr {$kind eq "dataset" ? [_datasetSha $sourceId] : ""}]
    set state($key,rects) {};set state($key,viewBounds) {}
    set state($key,activeSource) "source[incr state($key,nextSource)]"
    dict set state($key,sources) $state($key,activeSource) [dict create id $state($key,activeSource) visible 1 state {}]
    _workspaceCapture $key
    _workspaceRefresh $key
    return $source
}
proc ::GX::DatasetCurveFit::_datasetSha {dataset} {
    if {[catch {set record [::GX::sessionInspectionDataset $dataset]}]} {return ""}
    return [expr {[dict exists $record canonical_sha256] ? [dict get $record canonical_sha256] : ""}]
}
proc ::GX::DatasetCurveFit::sampleCatalog {} {
    return [dict create circular_arc "Exact quarter circle" noisy_arc "Noisy circular arc" quadratic_bezier "Quadratic Bézier" cubic_bezier "Cubic Bézier" pchip_step "Monotone PCHIP step" smoothing_wave "Noisy smoothing wave" fourier_wave "DC + sine + cosine"]
}
proc ::GX::DatasetCurveFit::sampleDescriptor {sampleId} {
    variable version
    if {![dict exists [sampleCatalog] $sampleId]} {error "Unknown Dataset Curve Fit sample '$sampleId'"}
    set geometry [expr {$sampleId in {circular_arc noisy_arc quadratic_bezier cubic_bezier}}]
    set axes [dict create x [dict create variable_id sample_x display_label [expr {$geometry ? "X coordinate" : "Normalized parameter"}] unit 1 semantic_role coordinate value_kind number] y [dict create variable_id sample_y display_label [expr {$geometry ? "Y coordinate" : "Signal amplitude"}] unit 1 semantic_role [expr {$geometry ? "coordinate" : "data"}] value_kind number]]
    set parameters [dict create count 41 index_first 0 index_last 40 parameter_rule {t=i/40} random_seed none]
    switch -- $sampleId {
        circular_arc - noisy_arc {
            dict set parameters center {1.0 -0.5};dict set parameters radius 2.0
            dict set parameters angle_interval {0 pi/2}
            dict set parameters radius_noise [expr {$sampleId eq "noisy_arc" ? "0.015*sin(17*i)" : "0"}]
            set description "Oriented quarter circle, center (1, -0.5), radius 2; deterministic radial perturbation is recorded in generator parameters."
            set expected [dict create model circular_arc center {1.0 -0.5} radius 2.0 metric radial_deviation_max tolerance [expr {$sampleId eq "noisy_arc" ? 0.015000000001 : 1e-12}]]
        }
        quadratic_bezier {
            dict set parameters control_points {{1 0} {2 3} {4 2}}
            set description "Quadratic Bezier sampled uniformly in parameter, retaining supplied control-point geometry and point order."
            set expected [dict create model quadratic_bezier control_points {{1 0} {2 3} {4 2}} metric generator_coordinate_max_error tolerance 1e-12]
        }
        cubic_bezier {
            dict set parameters control_points {{0 0} {1 3} {3 3} {6 0}}
            set description "Cubic Bezier sampled uniformly in parameter with an arch defined by four control points."
            set expected [dict create model cubic_bezier control_points {{0 0} {1 3} {3 3} {6 0}} metric generator_coordinate_max_error tolerance 1e-12]
        }
        pchip_step {
            dict set parameters breakpoint 0.45;dict set parameters slopes {0.3 0.75}
            dict set parameters function {t<0.45 ? 0.3*t : 0.135+0.75*(t-0.45)}
            set description "Continuous monotone piecewise linear data for shape-preserving PCHIP interpolation."
            set expected [dict create model pchip metric interpolation_knot_max_error tolerance 1e-12 monotonicity nondecreasing]
        }
        smoothing_wave {
            dict set parameters function {sin(2*pi*t)+0.06*sin(29*i)}
            set description "One sinusoidal period with deterministic high-frequency perturbation; smoothing strength is an explicit fit parameter."
            set expected [dict create model smoothing_spline reference_function {sin(2*pi*t)} metric noise_amplitude_max tolerance 0.060000000001]
        }
        fourier_wave {
            dict set parameters function {2+1.5*cos(2*pi*t)+0.7*sin(4*pi*t)}
            set description "Exactly representable Fourier signal with DC 2, fundamental cosine 1.5 and second-harmonic sine 0.7."
            set expected [dict create model fourier period 1 order_min 2 dc 2 cosine_coefficients {1.5 0} sine_coefficients {0 0.7} metric fitted_coordinate_max_error tolerance 1e-10]
        }
    }
    return [dict create sample_id $sampleId title [dict get [sampleCatalog] $sampleId] description $description axes $axes generator_id gxtxt.curve_fit.builtin generator_version 1 producer_module viewer.dataset_curve_fit producer_version $version generator_parameters $parameters model_provenance [dict create model_id [dict get $expected model] api_id NUMERIC_API_v1 module_id math.numeric module_version [::GX::moduleField math.numeric version ""]] expected_result $expected]
}
proc ::GX::DatasetCurveFit::_sampleMetadata {sampleId {prefix sample}} {
    set descriptor [sampleDescriptor $sampleId]
    set out [dict create]
    dict for {field value} $descriptor {dict set out $prefix.$field $value}
    dict set out $prefix.id $sampleId
    dict set out $prefix.point_count 41
    dict for {axis spec} [dict get $descriptor axes] {
        dict for {field value} $spec {dict set out $prefix.$axis.$field $value}
    }
    return $out
}
proc ::GX::DatasetCurveFit::_sourceProvenance {key} {
    variable state
    set kind [expr {[info exists state($key,sourceKind)] ? $state($key,sourceKind) : "dataset"}]
    if {$kind in {sample builtin_sample}} {
        set descriptor [sampleDescriptor $state($key,dataset)]
        return [dict create source_kind builtin_sample source_curve_id $state($key,activeSource) source_sample_id $state($key,dataset) source_sample_descriptor $descriptor source_axes [dict get $descriptor axes]]
    }
    set axes {}
    foreach axis {x y} {
        set descriptor [::GX::datasetVariableV3ById $state($key,dataset) $state($key,$axis)]
        if {[info exists state($key,sourceDescriptor)]&&[dict exists $state($key,sourceDescriptor) variables]} {
            foreach captured [dict get $state($key,sourceDescriptor) variables] {if {[dict get $captured variable_id] eq $state($key,$axis)} {set descriptor $captured;break}}
        }
        if {[string trim [dict get $descriptor display_label]] eq ""} {
            foreach field {canonical original_header variable_id} {
                if {[string trim [dict get $descriptor $field]] ne ""} {dict set descriptor display_label [dict get $descriptor $field];break}
            }
        }
        dict set axes $axis $descriptor
    }
    set provenance [dict create source_kind dataset source_curve_id $state($key,activeSource) source_dataset_id $state($key,dataset) source_x_variable_id $state($key,x) source_y_variable_id $state($key,y) source_sha256 $state($key,sourceSha) source_filters $state($key,filters) source_axes $axes]
    if {$state($key,sourceTransformManifest) ne {}} {dict set provenance source_transform_manifest $state($key,sourceTransformManifest)}
    if {$state($key,sourceToken) ne ""} {
        set descriptor [::GX::curveSourceDescribe $state($key,sourceToken)]
        dict set provenance source_curve_source_id [dict get $descriptor source_id]
        dict set provenance source_scientific_fingerprints [dict get $descriptor source_identities]
    }
    set logarithms [_logLineage $state($key,dataset) $state($key,x) $state($key,y)]
    if {$logarithms ne {}} {dict set provenance logarithm_lineage $logarithms}
    set smoothing [_smoothLineage $state($key,dataset) $state($key,x) $state($key,y)]
    if {$smoothing ne {}} {dict set provenance smoothing_lineage $smoothing}
    set transform [::GX::datasetTransformProvenance $::GX::currentSession $state($key,dataset)]
    set baseline [::GX::datasetPublicationV2DictDefault $transform baseline_lineage {}]
    if {$baseline eq {}&&[dict exists $transform effective baseline_receipt]} {set receipt [dict get $transform effective baseline_receipt];set baseline [list [dict create variable_id [dict get $receipt corrected_variable_id] correction $receipt]]}
    foreach binding $baseline {
        if {[dict get $binding variable_id] in [list $state($key,x) $state($key,y)]} {dict lappend provenance baseline_lineage $binding;dict set provenance baseline_correction [dict get $binding correction]}
    }
    return $provenance
}
proc ::GX::DatasetCurveFit::samplePoints {sampleId} {
    if {![dict exists [sampleCatalog] $sampleId]} {error "Unknown Dataset Curve Fit sample"}
    set points {}
    for {set i 0} {$i <= 40} {incr i} {
        set t [expr {$i/40.0}]
        switch -- $sampleId {
            circular_arc - noisy_arc {
                set angle [expr {acos(-1)*$t/2}]
                set radius [expr {$sampleId eq "noisy_arc" ? 2.0+0.015*sin(17*$i) : 2.0}]
                set x [expr {1.0+$radius*cos($angle)}];set y [expr {-0.5+$radius*sin($angle)}]
            }
            quadratic_bezier {
                set x [expr {(1-$t)*(1-$t)+4*(1-$t)*$t+4*$t*$t}]
                set y [expr {6*(1-$t)*$t+2*$t*$t}]
            }
            cubic_bezier {
                set x [expr {3*(1-$t)*(1-$t)*$t+9*(1-$t)*$t*$t+6*$t*$t*$t}]
                set y [expr {9*(1-$t)*(1-$t)*$t+9*(1-$t)*$t*$t}]
            }
            pchip_step {set x $t;set y [expr {$t<0.45 ? $t*0.3 : 0.135+0.75*($t-0.45)}]}
            smoothing_wave {set x $t;set y [expr {sin(2*acos(-1)*$t)+0.06*sin(29*$i)}]}
            fourier_wave {set x $t;set y [expr {2+1.5*cos(2*acos(-1)*$t)+0.7*sin(4*acos(-1)*$t)}]}
        }
        lappend points [list $x $y]
    }
    return $points
}
proc ::GX::DatasetCurveFit::loadSample {key sampleId} {
    set points [samplePoints $sampleId]
    set rows {}
    for {set i 0} {$i < [llength $points]} {incr i} {lappend rows $i}
    return [_replaceSource $key $points $rows builtin_sample $sampleId sample_x sample_y {}]
}
proc ::GX::DatasetCurveFit::_assertLoaded {key} {
    variable state
    if {$state($key,activeSource) ne ""&&$state($key,sourceStatus) ne "ready"} {error "Source '$state($key,activeSource)' is $state($key,sourceStatus): $state($key,sourceError). Reload it explicitly before fitting."}
    if {$state($key,source) eq ""} {error "Load a Dataset curve first"}
    if {[info exists state($key,sourceKind)] && $state($key,sourceKind) in {sample builtin_sample}} {
        if {$state($key,sessionToken) ne "" && $state($key,sessionToken) ne [::GX::interactiveDocumentSessionToken]} {
            error "Session changed; reopen the Dataset Curve Fit viewer"
        }
        return
    }
    if {[list $state($key,dataset) $state($key,x) $state($key,y) $state($key,filters)] ne $state($key,loadedBinding)} {
        error "Dataset, variables or filters changed; reload the source curve first"
    }
    if {$state($key,sourceSha) ne [_datasetSha $state($key,dataset)]} {error "Source Dataset changed; reload the curve first"}
    if {[info exists state($key,sourceToken)]&&$state($key,sourceToken) ne ""} {::GX::curveSourceDescribe $state($key,sourceToken)}
    if {$state($key,sessionToken) ne "" && $state($key,sessionToken) ne [::GX::interactiveDocumentSessionToken]} {
        error "Session changed; reopen the Dataset Curve Fit viewer"
    }
}
proc ::GX::DatasetCurveFit::selectPoint {key index {mode add}} {
    variable state
    ::GX::Native2D::core select $state($key,selectionScene) $state($key,selectionObject) $index $mode
    _influenceSyncSelection $key $mode
    return [selectedIndices $key]
}
proc ::GX::DatasetCurveFit::clearSelection {key} {
    variable state
    ::GX::Native2D::core clear $state($key,selectionScene)
    unset -nocomplain state($key,recipePointMask) state($key,influenceLinkedPoint)
}
proc ::GX::DatasetCurveFit::selectedIndices {key} {
    variable state
    return [::GX::Native2D::core selected $state($key,selectionScene) $state($key,selectionObject)]
}
proc ::GX::DatasetCurveFit::sourcePoints {key} {
    variable state
    return [::GX::Native2D::core points $state($key,scene) $state($key,source)]
}
proc ::GX::DatasetCurveFit::_csvRows {path rows} {
    set out [::open $path w]
    try {foreach row $rows {puts $out [join $row ,]}} finally {::close $out}
}
proc ::GX::DatasetCurveFit::_readCsv {path columns} {
    set in [::open $path r];set rows {}
    try {
        while {[gets $in line] >= 0} {
            set fields [split $line ,]
            if {[llength $fields] != $columns} {error "Invalid Numerical result row"}
            foreach v $fields {_finite $v "Numerical result"}
            lappend rows $fields
        }
    } finally {::close $in}
    return $rows
}
proc ::GX::DatasetCurveFit::_runNumeric {model degree initial training source domainSpec {options {}} {nativeScene ""} {document ""} {hostKey ""}} {
    variable root
    set runtime [file join $root plugins modules viewer.dataset_curve_fit runtime]
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set api [::GX::NumericAPIv1::octaveApiDir]
    if {![file exists [file join $api gxtxt_numeric_v1.m]]} {error "Public NUMERIC_API_v1 Octave binding is unavailable"}
    set holder [file tempfile temp];::close $holder;file delete $temp;file mkdir $temp
    set workerEnvironment [dict create GXDCF_CHARACTERISTICS_RESULT {}];set run ""
    try {
        if {[dict exists $options characteristics_only]} {
            dict set workerEnvironment GXDCF_CHARACTERISTICS_RESULT [file join $temp characteristics.ini]
            set fields {};dict for {key value} [dict get $options characteristic_thresholds] {dict set fields $key [::GX::ScientificTransportv1::array {1 1} [list $value]]}
            ::GX::ScientificTransportv1::writeResult [file join $temp characteristic-thresholds.ini] [dict create thresholds [::GX::ScientificTransportv1::struct $fields]]
            dict set workerEnvironment GXDCF_CHARACTERISTIC_THRESHOLDS [file join $temp characteristic-thresholds.ini]
        }
        if {[dict exists $options parameter_context]} {
            dict set workerEnvironment GXDCF_PARAMETER_ACTION prepare
            dict set workerEnvironment GXDCF_PARAMETER_CONTEXT [dict get $options parameter_context]
            dict set workerEnvironment GXDCF_PARAMETER_RESULT [file join $temp parameter-result.ini]
        }
        set binary [expr {$nativeScene ne ""}]
        set trainFile [file join $temp train.csv];set sourceFile [file join $temp source.csv]
        set trainFormat csv;set sourceFormat csv
        if {$binary} {
            set sourceFile [dict get $source xy_file];set sourceFormat [dict get $source xy_format]
            if {![catch {dict get $training api_id} marker]&&$marker eq "CURVE_SOURCE_NUMERIC_INPUT_v1"} {
                set trainFile [dict get $training xy_file];set trainFormat [dict get $training xy_format]
            } else {_csvRows $trainFile $training}
        } else {_csvRows $trainFile $training;_csvRows $sourceFile $source}
        if {[dict get [_measurementOptions $options] kind] eq "sigma_xy"&&$model in {linear polynomial}&&$initial eq {}} {
            set initial [lrepeat [expr {$model eq "linear"?2:$degree+1}] 0]
        }
        _csvRows [file join $temp initial.csv] [list $initial]
        if {$model eq "components"} {
            ::GX::ScientificTransportv1::writeResult [file join $temp components.ini] [dict create recipe [_componentRecipeNode [dict get $options component_recipe]]]
            dict set workerEnvironment GXDCF_COMPONENT_RECIPE [file join $temp components.ini]
        }
        dict set workerEnvironment GXDCF_COMPLEX_RECIPE {}
        if {$model eq "complex_response"} {
            set complexBinding [_complexStage [dict get $options complex_binding] [dict get $options complex_recipe] $training $source $temp]
            dict set workerEnvironment GXDCF_COMPLEX_RECIPE [file join $temp complex.ini]
        }
        if {$model eq "rational"} {
            ::GX::ScientificTransportv1::writeResult [file join $temp rational.ini] [dict create recipe [_rationalRecipeNode [dict get $options rational_recipe]]]
            dict set workerEnvironment GXDCF_RATIONAL_RECIPE [file join $temp rational.ini]
            dict set workerEnvironment GXDCF_RATIONAL_EXTRAPOLATION [::GX::datasetPublicationV2DictDefault $options rational_extrapolation error]
        }
        if {$model eq "implicit"} {
            ::GX::ScientificTransportv1::writeResult [file join $temp implicit.ini] [dict create recipe [_implicitRecipeNode [dict get $options implicit_recipe]] branch [_implicitBranchNode [dict get $options implicit_branch] [_fitOrientation $model $options]]]
            dict set workerEnvironment GXDCF_IMPLICIT_RECIPE [file join $temp implicit.ini]
        }
        if {$model eq "formula"} {
            ::GX::ScientificTransportv1::writeResult [file join $temp formula.ini] [dict create recipe [_formulaRecipeNode [dict get $options formula_recipe]]]
            dict set workerEnvironment GXDCF_FORMULA_RECIPE [file join $temp formula.ini]
        }
        if {$model eq "regions"} {
            ::GX::ScientificTransportv1::writeResult [file join $temp regions.ini] [dict create recipe [_regionRecipeNode [dict get $options region_recipe]]]
            dict set workerEnvironment GXDCF_REGION_RECIPE [file join $temp regions.ini]
        }
        if {$model in {akima bspline}} {
            ::GX::ScientificTransportv1::writeResult [file join $temp knots.ini] [dict create settings [_knotOptionNodes $model $options]]
            dict set workerEnvironment GXDCF_KNOT_SETTINGS [file join $temp knots.ini]
        }
        if {$model eq "smoothing_spline"} {
            ::GX::ScientificTransportv1::writeResult [file join $temp smoothing.ini] [dict create settings [_smoothingOptionNodes $model $options]]
            dict set workerEnvironment GXDCF_SMOOTHING_SETTINGS [file join $temp smoothing.ini]
        }
        if {$model eq "registered"&&[dict exists $options parameter_context]} {
            set policy [::GX::ScientificTransportv1::struct {}]
            ::GX::ScientificTransportv1::writeResult [file join $temp parameter-definition.ini] [dict create definition [_parameterRegisteredDefinitionNode [dict get $options registered_model definition]]]
            dict set workerEnvironment GXDCF_PARAMETER_DEFINITION [file join $temp parameter-definition.ini]
        } else {set policy [_solverOptionNodes $model $initial $options]}
        ::GX::ScientificTransportv1::writeResult [file join $temp solver.ini] [dict create solver $policy]
        dict set workerEnvironment GXDCF_SOLVER_SETTINGS [file join $temp solver.ini]
        dict set workerEnvironment GXDCF_INFLUENCE [_influenceOption $model $options]
        dict set workerEnvironment GXDCF_PROFILE_SETTINGS {}
        set profile [_profileOptions $model $options]
        if {$profile ne {}} {
            set nodes {};dict for {name value} $profile {
                if {$name eq "parameter_id"} {set node [::GX::ScientificTransportv1::text $value]} else {set node [::GX::ScientificTransportv1::array {1 1} [list $value]]}
                dict set nodes $name $node
            }
            ::GX::ScientificTransportv1::writeResult [file join $temp profile-settings.ini] [dict create settings [::GX::ScientificTransportv1::struct $nodes]]
            dict set workerEnvironment GXDCF_PROFILE_SETTINGS [file join $temp profile-settings.ini]
        }
        dict set workerEnvironment GXDCF_BOOTSTRAP_SETTINGS {}
        set bootstrap [_bootstrapOptions $model $options]
        if {$bootstrap ne {}} {
            set nodes {};dict for {name value} $bootstrap {
                if {$name eq "method"} {set node [::GX::ScientificTransportv1::text $value]} else {set node [::GX::ScientificTransportv1::array {1 1} [list $value]]}
                dict set nodes $name $node
            }
            ::GX::ScientificTransportv1::writeResult [file join $temp bootstrap-settings.ini] [dict create settings [::GX::ScientificTransportv1::struct $nodes]]
            dict set workerEnvironment GXDCF_BOOTSTRAP_SETTINGS [file join $temp bootstrap-settings.ini]
        }
        set predictionNodes {}
        foreach {field fallback} {prediction_band none noise_model unspecified confidence 0.95 prediction_sigma {} prediction_weights {}} {
            set value [::GX::datasetPublicationV2DictDefault $options $field $fallback]
            if {$field in {prediction_band noise_model}||$value eq {}} {set node [::GX::ScientificTransportv1::text $value]} else {set node [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]}
            dict set predictionNodes $field $node
        }
        set contextNodes {}
        dict for {field value} [::GX::datasetPublicationV2DictDefault $options prediction_context {x_unit unspecified y_unit unspecified radial_unit unspecified}] {
            if {$field in {baseline_correction response_transform smoothing}} {
                set fields {};dict for {name text} $value {dict set fields $name [::GX::ScientificTransportv1::text $text]}
                dict set contextNodes $field [::GX::ScientificTransportv1::struct $fields]
            } else {dict set contextNodes $field [::GX::ScientificTransportv1::text $value]}
        }
        dict set predictionNodes context [::GX::ScientificTransportv1::struct $contextNodes]
        ::GX::ScientificTransportv1::writeResult [file join $temp prediction-settings.ini] [dict create settings [::GX::ScientificTransportv1::struct $predictionNodes]]
        dict set workerEnvironment GXDCF_PREDICTION_SETTINGS [file join $temp prediction-settings.ini]
        dict set workerEnvironment GXDCF_PREDICTION_OUTPUT [file join $temp prediction.bin]
        foreach {name value} [list MEASUREMENT_KIND none MEASUREMENT_FILE {} MEASUREMENT_SCALE 1 INDEPENDENT_MEASUREMENT_FILE {} INDEPENDENT_MEASUREMENT_SCALE 1 MEASUREMENT_NONFINITE error MEASUREMENT_OUTPUT [file join $temp measurements.bin] MEASUREMENT_ROWS_OUTPUT [file join $temp measurement_rows.bin] MEASUREMENT_FIT_ROWS_OUTPUT [file join $temp measurement_fit_rows.bin] ORTHOGONAL_OUTPUT [file join $temp orthogonal.bin]] {dict set workerEnvironment GXDCF_$name $value}
        if {[dict exists $options measurement_binding]} {
            set binding [dict get $options measurement_binding]
            dict set workerEnvironment GXDCF_MEASUREMENT_KIND [dict get $binding kind]
            dict set workerEnvironment GXDCF_MEASUREMENT_FILE [dict get $training companion_columns measurement file]
            dict set workerEnvironment GXDCF_MEASUREMENT_SCALE [dict get $binding scale_factor]
            dict set workerEnvironment GXDCF_MEASUREMENT_NONFINITE [dict get $binding nonfinite]
            if {[dict get $binding kind] eq "sigma_xy"} {
                dict set workerEnvironment GXDCF_INDEPENDENT_MEASUREMENT_FILE [dict get $training companion_columns independent_measurement file]
                dict set workerEnvironment GXDCF_INDEPENDENT_MEASUREMENT_SCALE [dict get $binding independent_measurement scale_factor]
            }
        }
        dict set workerEnvironment GXDCF_COVARIANCE_INPUT {}
        if {[dict exists $options covariance_binding]} {
            set covariance [_covarianceStage [dict get $options covariance_binding] $temp]
            dict set workerEnvironment GXDCF_COVARIANCE_INPUT [file join $temp covariance-input.ini]
            dict set workerEnvironment GXDCF_COVARIANCE_SEMANTICS [dict get $covariance binding covariance_semantics]
            dict set workerEnvironment GXDCF_COVARIANCE_SINGULAR [dict get $covariance binding singular_policy]
        }
        set range [expr {$domainSpec ne "source"}]
        if {$range} {
            if {[llength $domainSpec] == 4} {lassign [lrange $domainSpec 1 end] domainMin domainMax domainSamples} else {lassign $domainSpec domainMin domainMax domainSamples}
        } else {lassign {0 0 0} domainMin domainMax domainSamples}
        set period [expr {[dict exists $options period] ? [dict get $options period] : ""}]
        set smoothing [expr {[dict exists $options smoothing_lambda] ? [dict get $options smoothing_lambda] : ""}]
        foreach {name value} [list TRAIN $trainFile SOURCE $sourceFile TRAIN_FORMAT $trainFormat SOURCE_FORMAT $sourceFormat BINARY_OUTPUT $binary INITIAL [file join $temp initial.csv] RESULT [file join $temp result.tsv] STATISTICS [file join $temp statistics.ini] CORE_OCTAVE_DIR [file join $root core octave] FITTED [file join $temp fitted.csv] RESIDUAL [file join $temp residual.csv] MODEL_STATE [file join $temp model_state.json] NUMERIC_API_DIR $api MODEL $model DEGREE $degree DOMAIN_MODE [expr {$range ? "range" : "source"}] DOMAIN_MIN $domainMin DOMAIN_MAX $domainMax DOMAIN_SAMPLES $domainSamples PERIOD $period SMOOTHING $smoothing ORIENTATION [_fitOrientation $model $options]] {dict set workerEnvironment GXDCF_$name $value}
        foreach {name field fallback} {PARAMETERIZATION parameterization row_order TOPOLOGY topology auto USER_PERIOD user_period "" CLOSURE_TOLERANCE closure_tolerance ""} {dict set workerEnvironment GXDCF_$name [::GX::datasetPublicationV2DictDefault $options $field $fallback]}
        foreach axis {u v} {
            # Old public v1 calls have no translation option. The GUI supplies
            # its explicit AUTO defaults through _uiFitOptions.
            set mapping [::GX::datasetPublicationV2DictDefault $options translation_$axis [dict create mode off delta 0]]
            set mode [::GX::datasetPublicationV2DictDefault $mapping mode off]
            if {$mode ni {auto manual off}} {error {Translation mode must be auto, manual or off}}
            set delta [::GX::datasetPublicationV2DictDefault $mapping delta 0]
            _finite $delta {Translation constant}
            dict set workerEnvironment GXDCF_TRANSLATION_[string toupper $axis]_MODE $mode
            dict set workerEnvironment GXDCF_TRANSLATION_[string toupper $axis]_DELTA $delta
        }
        if {[_fitOrientation $model $options] eq "r_of_theta"} {
            set frame [dict get $options polar_frame]
            foreach {name value} [list ORIGIN_X [lindex [dict get $frame origin] 0] ORIGIN_Y [lindex [dict get $frame origin] 1] ZERO [dict get $frame theta_zero] CLOCKWISE [dict get $frame clockwise] UNIT [dict get $frame angle_unit] POLICY [dict get $frame unwrap_policy] CUT [dict get $frame angle_cut]] {dict set workerEnvironment GXDCF_POLAR_$name $value}
        }
        foreach {name input} [list TRAIN_PARAMETER $training SOURCE_PARAMETER $source] {
            set path ""
            if {$binary&&[dict exists $input parameter_file]} {set path [dict get $input parameter_file]}
            dict set workerEnvironment GXDCF_$name $path
        }
        foreach {name input} [list TRAIN_ROW_IDS $training SOURCE_ROW_IDS $source] {
            set path ""
            if {$binary&&![catch {dict get $input source_rows_file} captured]} {set path $captured}
            dict set workerEnvironment GXDCF_$name $path
        }
        if {!$binary&&[dict exists $options comparison_row_ids]} {
            set rowFile [file join $temp comparison_rows.bin]
            set channel [::open $rowFile {WRONLY CREAT EXCL}]
            try {fconfigure $channel -translation binary -encoding binary;puts -nonewline $channel [binary format wu* [dict get $options comparison_row_ids]]} finally {::close $channel}
            dict set workerEnvironment GXDCF_TRAIN_ROW_IDS $rowFile
        }
        set executable [auto_execok octave-cli]
        if {$executable eq ""} {set executable [auto_execok octave]}
        if {$executable eq ""} {error "GNU Octave is required by NUMERIC_API_v1"}
        set run [::GX::parallelExecutionNewRunId curve_fit]
        set progress ""
        if {$hostKey ne ""} {
            variable state
            if {$state($hostKey,sourceCancelled)} {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} "Fitting cancelled"}
            set state($hostKey,numericRun) $run
            set progress [list [expr {[dict exists $options characteristics_only]?"::GX::DatasetCurveFit::_suggestionProgress":"::GX::DatasetCurveFit::_numericProgress"}] $hostKey]
        }
        set execution [::GX::parallelExecutionExecute [list [dict create id fit argv [list {*}$executable --quiet --no-gui --path $runtime --eval dataset_curve_fit_numeric]]] [dict create kind process command_builder ::GX::DatasetCurveFit::_numericCommand environment $workerEnvironment] [dict create workers 1 run_id $run progress_command $progress]]
        if {[dict get $execution state] eq "cancelled"} {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} "Fitting cancelled"}
        set result [lindex [dict get $execution results] 0]
        if {[dict get $result state] ne "success"} {
            set numericError [dict get $result stderr]
            if {$numericError eq ""} {set numericError [dict get $result error]}
            if {[regexp {error: ([^\n]+)} $numericError -> message]} {error $message}
            return -code error -errorcode [dict get $result error_code] [lindex [split $numericError \n] 0]
        }
        if {[dict exists $options characteristics_only]} {
            set raw [dict get [::GX::ScientificTransportv1::readResult [file join $temp characteristics.ini]] values characteristics]
            set captured [dict create numeric $raw]
            set rowFile [dict get $workerEnvironment GXDCF_TRAIN_ROW_IDS]
            if {$rowFile ne {}&&[file isfile $rowFile]} {dict set captured binding [dict create schema gxtxt.observation_binding.v1 source_sha256 [::GX::sha256File $sourceFile] rows_sha256 [::GX::sha256File $rowFile]]}
            return $captured
        }
        if {[dict exists $options parameter_context]} {return [dict get [::GX::ScientificTransportv1::readResult [file join $temp parameter-result.ini]] values view]}
        set report [dict create]
        set in [::open [file join $temp result.tsv] r]
        try {while {[gets $in line] >= 0} {set fields [split $line \t];dict set report [lindex $fields 0] [lindex $fields 1]}} finally {::close $in}
        set report [_outputDomainImport $report $temp $document]
        if {$binary} {
            set report [_numericNativeResult $nativeScene $document $temp $source $report]
        } else {
            dict set report fitted [_readCsv [file join $temp fitted.csv] 2]
            dict set report residual [_readCsv [file join $temp residual.csv] [::GX::datasetPublicationV2DictDefault $report residual_stride 4]]
        }
        dict set report numeric_statistics [dict get [::GX::ScientificTransportv1::readResult [file join $temp statistics.ini]] values]
        set rowFile [dict get $workerEnvironment GXDCF_TRAIN_ROW_IDS]
        if {[dict exists $report numeric_statistics region_selection]} {
            set rowFile [file join $temp region_training_rows.bin]
            dict set report region_selection [dict get $report numeric_statistics region_selection]
        }
        if {[dict exists $report numeric_statistics measurement]} {set rowFile [file join $temp measurement_fit_rows.bin]}
        if {$rowFile ne {}} {
            dict set report comparison_input [dict create source_sha256 [::GX::sha256File $sourceFile] rows_sha256 [::GX::sha256File $rowFile]]
            if {$document ne {}} {
                dict set report comparison_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document $rowFile [dict create format uint64_le row_count [expr {[file size $rowFile]/8}] role comparison_training_rows]]
            }
        }
        if {[dict exists $report numeric_statistics measurement]} {
            if {$document eq {}} {error {Measurement bindings require an owned Fitter Document}}
            set measurement [dict get $report numeric_statistics measurement]
            dict set report measurement_selection $measurement
            set count [dict get $measurement input_count]
            set columns {original_measurement converted_measurement effective_weight used_for_fit}
            if {[dict get $measurement kind] eq "sigma_xy"} {set columns {original_independent_sigma converted_independent_sigma original_response_sigma converted_response_sigma used_for_fit}}
            dict set report measurement_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temp measurements.bin] [dict create format float64_interleaved_le row_count $count columns $columns role fit_measurements]]
            dict set report measurement_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temp measurement_rows.bin] [dict create format uint64_le row_count $count role measurement_source_rows]]
            dict set report training_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temp measurement_fit_rows.bin] [dict create format uint64_le row_count [dict get $measurement fit_count] role positive_precision_training_rows]]
            if {[dict get $measurement kind] eq "sigma_xy"} {
                dict set report orthogonal_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temp orthogonal.bin] [dict create format float64_interleaved_le row_count [dict get $measurement fit_count] columns {adjusted_independent adjusted_response independent_correction response_correction normalized_independent_correction normalized_response_correction} role orthogonal_xy_corrections coordinate_space original_physical]]
            }
        }
        if {[dict exists $report region_selection]} {
            if {$document eq {}} {error {Regional membership requires an owned Fitter Document}}
            dict set report region_membership_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temp region_membership.bin] [dict create format float64_interleaved_le row_count [dict get $report numeric_statistics fit n] columns {region_index} role joint_fit_region_membership index_base 1 boundary_ownership right_region]]
        }
        if {[file exists [file join $temp prediction.bin]]} {
            if {$document eq {}} {error {Prediction bands require an owned Fitter Document}}
            set metadata [dict create format float64_interleaved_le row_count [dict get $report output_n] columns {prediction_query prediction_mean prediction_lower prediction_upper prediction_mean_se prediction_se prediction_noise_sd prediction_available} role prediction_uncertainty coefficient_space original_physical]
            dict set report prediction_resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $temp prediction.bin] $metadata]
        }
        if {[info exists covariance]} {set report [_covarianceImport $document $temp [dict get $covariance binding] $report]}
        if {[info exists complexBinding]} {set report [_complexImport $document $temp $complexBinding $report]}
        set report [_influenceImport $document $temp $report]
        set report [_bootstrapImport $document $temp $report]
        set report [_profileImport $document $temp $report]
        dict set report model_input_policy [dict get $report numeric_statistics input_policy]
        if {$binary} {
            set path [file join $temp model_input_rows.bin]
            if {[file exists $path]} {
                dict set report preprocessing_model_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document $path [dict create format uint64_le columns {source_row_ordinal} row_count [expr {[file size $path]/8}] role model_input_order]]
            } else {dict set report preprocessing_model_rows_resource [dict get $report comparison_rows_resource]}
            if {[dict exists $report region_selection]} {
                set path [file join $temp region_training_rows.bin]
                dict set report preprocessing_region_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document $path [dict create format uint64_le columns {source_row_ordinal} row_count [expr {[file size $path]/8}] role region_selection_rows]]
            }
            set report [dict merge $report [_preprocessingCapture $document $source $training $report [dict get $report model_input_policy]]]
        } elseif {[dict exists $options preprocessing_source]} {
            set f [::open $rowFile rb];try {binary scan [read $f] wu* fitRows} finally {::close $f}
            set modelRows $fitRows
            if {[file exists [file join $temp model_input_rows.bin]]} {set f [::open [file join $temp model_input_rows.bin] rb];try {binary scan [read $f] wu* modelRows} finally {::close $f}}
            set regionRows {}
            if {[dict exists $report region_selection]} {set f [::open [file join $temp region_training_rows.bin] rb];try {binary scan [read $f] wu* regionRows} finally {::close $f}}
            set report [dict merge $report [_preprocessingInline [dict get $options preprocessing_source] [llength $source] [dict get $options comparison_row_ids] $fitRows $modelRows [dict get $report model_input_policy] $regionRows]]
        }
        return $report
    } on error {message errorOptions} {
        # Native geometry may already exist when a later owned-resource import
        # fails. Release only this attempted result; the current preview remains
        # owned by the caller until a complete replacement has been returned.
        if {$nativeScene ne ""&&[info exists report]} {
            foreach field {fitted_native residual_native prediction_lower_native prediction_upper_native} {
                if {[dict exists $report $field]} {catch {::GX::Native2D::core delete $nativeScene [dict get $report $field]}}
            }
        }
        return -options $errorOptions $message
    } finally {
        if {$run ne ""} {::GX::parallelExecutionRelease $run}
        if {$hostKey ne ""} {set state($hostKey,numericRun) ""}
        file delete -force $temp
    }
}
proc ::GX::DatasetCurveFit::preview {key model scope domainSpec {degree 2} {initial {}} {options {}}} {
    variable state
    _assertLoaded $key
    set profile [_profileOptions $model $options]
    if {$profile ne {}} {
        dict set options profile $profile
        if {$state($key,sessionToken) eq {}} {error {Profile likelihood requires a Session-owned Fitter Workspace}}
        if {$state($key,documentId) eq {}} {_saveState $key}
    }
    set bootstrap [_bootstrapOptions $model $options]
    if {$bootstrap ne {}} {
        dict set options bootstrap $bootstrap
        if {$state($key,sessionToken) eq {}} {error {Bootstrap requires a Session-owned Fitter Workspace}}
        if {$state($key,documentId) eq {}} {_saveState $key}
    }
    set influence [_influenceOption $model $options]
    if {$influence&&$state($key,sessionToken) eq {}} {error {Influence diagnostics require a Session-owned Fitter Workspace}}
    if {$influence&&$state($key,documentId) eq {}} {_saveState $key}
    set noise [::GX::datasetPublicationV2DictDefault $options noise_model unspecified]
    if {$noise ni {unspecified independent_gaussian_estimated_variance independent_gaussian_known_sigma correlated_gaussian_known_covariance correlated_gaussian_estimated_scale}} {error {Unknown statistical noise assumption}}
    set covariance [_covarianceRequest $key $model $options]
    if {$covariance eq {}&&[string match correlated_gaussian_* $noise]} {error {Correlated Gaussian inference requires its full observation covariance binding}}
    set confidence [_finite [::GX::datasetPublicationV2DictDefault $options confidence 0.95] {Confidence level}]
    if {$confidence<=0||$confidence>=1} {error {Confidence level must be strictly between zero and one}}
    if {[::GX::datasetPublicationV2DictDefault $options prediction_band none] ni {none mean_confidence new_observation}} {error {Choose no band, pointwise mean confidence or future-observation prediction}}
    set sourceSnapshot [list $state($key,activeSource) $state($key,source) $state($key,loadedBinding)]
    set selectionSnapshot [_selectionDescriptor $key]
    set selectedSnapshot [selectedIndices $key]
    set sceneSnapshot $state($key,scene)
    if {$model ni {linear polynomial exponential power_law gaussian components regions formula rational implicit complex_response circular_arc quadratic_bezier cubic_bezier pchip smoothing_spline akima bspline fourier parametric_polynomial parametric_spline}} {error "Choose a supported model"}
    if {$scope ni {all selected}} {error "Fit scope must be all or selected"}
    set points [sourcePoints $key]
    if {$scope eq "all"} {set training $points} else {set training [::GX::Native2D::core export $state($key,selectionScene) $state($key,selectionObject)]}
    if {[llength $training] < 2 && ($scope eq "all" || $state($key,sourceToken) eq "")} {error "Select at least two fit points"}
    if {$model in {polynomial parametric_polynomial} && (![string is integer -strict $degree] || $degree < 1 || $degree > 12)} {error "Polynomial degree must be 1–12"}
    if {$model eq "fourier" && (![string is integer -strict $degree] || $degree < 1)} {error "Fourier order must be a positive integer"}
    if {$model eq "fourier" && [dict exists $options period] && [dict get $options period] ne "" &&
        [_finite [dict get $options period] "Fourier period"] <= 0} {error "Fourier period must be positive"}
    if {$model eq "smoothing_spline"} {
        _smoothingOptionNodes $model $options
        set smoothingPolicy [dict merge [_smoothingDefaults] [::GX::datasetPublicationV2DictDefault $options smoothing_options {}]]
        if {[dict get $smoothingPolicy smoothing_selection] eq "manual"&&(![dict exists $options smoothing_lambda]||[_finite [dict get $options smoothing_lambda] "Smoothing lambda"]<0)} {error {Smoothing lambda must be nonnegative}}
    }
    if {$model in {parametric_polynomial parametric_spline}&&[::GX::datasetPublicationV2DictDefault $options parameterization row_order] eq "user_parameter"&&$state($key,sourceToken) eq ""} {error "User parameter mode needs a real Dataset parameter variable"}
    if {$model eq "components"} {
        set resolved [_prepareComponents $key $options]
        dict set options component_recipe [dict get $resolved composition recipe]
        set initial [dict get $resolved initial_parameters]
    }
    if {$model eq "complex_response"} {
        foreach axis {u v} {if {![dict exists $options translation_$axis]} {dict set options translation_$axis {mode off delta 0}}}
        set resolved [_prepareComplex $key $options]
        dict set options complex_recipe [dict get $resolved recipe]
        set initial [dict get $resolved parameters]
    }
    if {$model in {akima bspline}} {
        foreach axis {u v} {if {![dict exists $options translation_$axis]} {dict set options translation_$axis {mode off delta 0}}}
        dict set options knot_options [_prepareKnots $key $model $options]
        set initial {}
    }
    if {$model eq "rational"} {
        foreach axis {u v} {if {![dict exists $options translation_$axis]} {dict set options translation_$axis {mode off delta 0}}}
        set resolved [_prepareRational $key $options]
        dict set options rational_recipe [dict get $resolved recipe]
        dict set options rational_extrapolation [::GX::datasetPublicationV2DictDefault $options rational_extrapolation error]
        set initial [dict get $resolved initial_parameters]
    }
    if {$model eq "implicit"} {
        foreach axis {u v} {if {![dict exists $options translation_$axis]} {dict set options translation_$axis {mode off delta 0}}}
        set resolved [_prepareImplicit $key $options]
        dict set options implicit_recipe [dict get $resolved recipe]
        set initial [dict get $resolved initial_parameters]
    }
    if {$model eq "formula"} {
        set resolved [_prepareFormula $key $options]
        dict set options formula_recipe [dict get $resolved formula_declaration recipe]
        set initial [dict get $resolved initial_parameters]
    }
    if {$model eq "regions"} {
        set resolved [_prepareRegions $key $options]
        dict set options region_recipe [dict get $resolved regional_composition recipe]
        set initial [dict get $resolved initial_parameters]
    }
    set required [dict get [dict create linear 0 polynomial 0 exponential 3 power_law 2 gaussian 4 components 0 regions 0 formula 0 rational 0 implicit 0 complex_response 0 circular_arc 0 quadratic_bezier 0 cubic_bezier 0 pchip 0 smoothing_spline 0 akima 0 bspline 0 fourier 0 parametric_polynomial 0 parametric_spline 0] $model]
    if {$required && [llength $initial] != $required} {error "$model needs $required initial parameters"}
    foreach v $initial {_finite $v "Initial parameter"}
    set orientation [_fitOrientation $model $options]
    if {$orientation eq "r_of_theta"} {
        if {![dict exists $options polar_frame]} {dict set options polar_frame $state($key,polarFrame)}
        set frame [dict get $options polar_frame]
        foreach field {origin theta_zero clockwise angle_unit unwrap_policy angle_cut} {if {![dict exists $frame $field]} {error "Radial fitting frame needs '$field'"}}
        if {[llength [dict get $frame origin]]!=2} {error "Radial origin needs X and Y"}
        foreach value [concat [dict get $frame origin] [list [dict get $frame theta_zero] [dict get $frame angle_cut]]] {_finite $value "Radial frame coordinate"}
        if {![string is boolean -strict [dict get $frame clockwise]]||[dict get $frame angle_unit] ni {rad deg}||[dict get $frame unwrap_policy] ni {cut continuous}} {error "Choose a valid radial angle unit, direction and branch policy"}
        dict set frame clockwise [expr {!![dict get $frame clockwise]}];dict set options polar_frame $frame
    }
    set parametric [expr {$orientation eq "parametric"}]
    if {$parametric||$orientation eq "r_of_theta"} {set metricUnit [_geometricMetricUnit $key]}
    set axes [dict get [_sourceProvenance $key] source_axes]
    dict set options prediction_context [dict create x_unit [dict get $axes x unit] y_unit [dict get $axes y unit] radial_unit [expr {[info exists metricUnit]?$metricUnit:{}}]]
    set smoothing [_smoothContext [_sourceProvenance $key]]
    if {$smoothing ne {}} {dict set options prediction_context smoothing $smoothing}
    set baseline [_baselineContext [_sourceProvenance $key]]
    if {$baseline ne {}} {dict set options prediction_context baseline_correction $baseline}
    foreach axis {x y} {dict set options prediction_context ${axis}_variable_id [dict get $axes $axis variable_id]}
    set logarithm [_logContext [_sourceProvenance $key] $orientation]
    if {$logarithm ne {}} {dict set options prediction_context response_transform $logarithm}
    if {$domainSpec ne "source"} {
        set parameterDomain [expr {[llength $domainSpec] == 4 && [lindex $domainSpec 0] eq "parameter"}]
        if {($parametric && !$parameterDomain) || (!$parametric && $parameterDomain)} {error "Output domain mode does not match model geometry"}
        if {$parameterDomain} {set triple [lrange $domainSpec 1 end]} else {set triple $domainSpec}
        if {[llength $triple] != 3} {error "Output domain needs minimum, maximum and samples"}
        lassign $triple lo hi n
        set lo [_finite $lo "Output minimum"];set hi [_finite $hi "Output maximum"]
        if {$hi <= $lo || ![string is integer -strict $n] || $n < 2 || $n > 10000} {error "Output domain needs increasing bounds and 2–10000 samples"}
        if {$parameterDomain && ($lo < 0 || $hi > 1)} {error "Parameter output domain must lie in [0,1]"}
        set domainSpec [expr {$parameterDomain ? [list parameter $lo $hi $n] : [list $lo $hi $n]}]
    }
    set companions [dict merge [_measurementCompanions $key $model $options] [_complexCompanions $key $model $options]]
    if {[info exists state($key,sourceToken)]&&$state($key,sourceToken) ne ""} {
        set mask [expr {$scope eq "selected" ? [_selectionDescriptor $key] : {}}]
        set progress [expr {[info exists state($key,loading)]&&$state($key,loading) ? [list ::GX::DatasetCurveFit::_stagingProgress $key] : ""}]
        set result [::GX::curveSourceWithNumericInput $state($key,sourceToken) [list ::GX::DatasetCurveFit::_numericSource $key $model $degree $initial $scope $training $domainSpec $options] $mask $progress [::GX::datasetPublicationV2DictDefault $options parameter_variable_id ""] $companions]
    } else {
        set hostKey [expr {[info exists state($key,loading)]&&$state($key,loading) ? $key : ""}]
        set localOptions $options
        set rowIds $state($key,rows)
        if {$scope eq "selected"} {set rowIds [lmap index $selectedSnapshot {lindex $state($key,rows) $index}]}
        dict set localOptions comparison_row_ids $rowIds
        if {$state($key,sourceKind) in {sample builtin_sample}} {dict set localOptions preprocessing_source [_sourceProvenance $key]}
        set result [_runNumeric $model $degree $initial $training $points $domainSpec $localOptions "" $state($key,documentId) $hostKey]
    }
    try {
        _assertLoaded $key
        if {[list $state($key,activeSource) $state($key,source) $state($key,loadedBinding)] ne $sourceSnapshot} {error "Active source changed while fitting; preview again"}
        if {$scope eq "selected"&&[_selectionDescriptor $key] ne $selectionSnapshot} {error "Fit selection changed while fitting; preview again"}
    } on error {message options} {
        _disposeReport $sceneSnapshot $result
        return -options $options $message
    }
    dict set result scope $scope;dict set result domain $domainSpec
    dict set result orientation $orientation
    if {$parametric||$orientation eq "r_of_theta"} {dict set result metric_unit $metricUnit}
    if {$orientation eq "r_of_theta"} {dict set result polar_frame $frame;dict set result coordinate_mode polar;dict set result independent_axis theta}
    dict set result degree $degree;dict set result initial $initial
    dict set result options [dict remove $options prediction_context]
    dict set result translation [_translationMetadata $key $result]
    try {set result [_interpretStatistics $key $result]} on error {message detail} {_disposeReport $sceneSnapshot $result;return -options $detail $message}
    # Structured Dataset metadata uses one field per line. Keep the same
    # physical expression in a portable single-line representation.
    dict set result physical_formula [string map [list \r {} \n {; }] [formula $result]]
    dict set result source_id $state($key,source)
    dict set result selected_indices $selectedSnapshot
    dict set result selection_descriptor $selectionSnapshot
    dict set result recipe_producers [_recipeProducers]
    if {[info exists state($key,templateBinding)]} {dict set result template_binding $state($key,templateBinding)}
    if {!$state($key,deferDispose)} {_disposePreview $key}
    set state($key,preview) $result
    set state($key,previewAccepted) 0
    set state($key,previewFitId) ""
    return $result
}
proc ::GX::DatasetCurveFit::accept {key {name {}}} {
    variable state
    _assertLoaded $key
    if {$state($key,preview) eq {}} {error "Preview a fit before accepting it"}
    if {$state($key,previewAccepted)} {error "This preview has already been accepted"}
    if {[dict get $state($key,preview) source_id] != $state($key,source)} {error "Source curve changed; preview again"}
    if {[dict get $state($key,preview) scope] eq "selected" && ![_selectionUnchanged $key $state($key,preview)]} {error "Fit-point selection changed; preview again"}
    if {$name ne {}} {set name [_acceptedName $name]}
    _validateStatisticsMetadata $state($key,preview)
    _requireConvergedNativeFit $state($key,preview)
    set scene $state($key,scene)
    set points [dict get $state($key,preview) fitted]
    if {[dict exists $state($key,preview) fitted_native]} {
        set id [::GX::Native2D::core extract $scene [dict get $state($key,preview) fitted_native] 0 [expr {[dict get $state($key,preview) output_n]-1}]]
        ::GX::Native2D::core visible $scene $id 1
    } else {set id [::GX::Native2D::core add $scene $points]}
    set palette {{0.05 0.55 0.25} {0.73 0.29 0.13} {0.45 0.27 0.72} {0.03 0.52 0.62} {0.70 0.38 0.05}}
    set color [lindex $palette [expr {[llength $state($key,records)] % [llength $palette]}]]
    ::GX::Native2D::core style $scene $id $color 2.5
    ::GX::Native2D::core object_style $scene $id {locked 1 selectable 0}
    set result $state($key,preview)
    try {set predictionNative [_predictionRestore $scene $result $color 1]} on error {message detail} {::GX::Native2D::core delete $scene $id;return -options $detail $message}
    set label [expr {$name ne {}?$name:"Fit $id: [dict get $result model] ([dict get $result train_n] points)"}]
    lappend state($key,records) [dict create id $id label $label color $color visible 1 points $points model [dict get $result model] parameters [dict get $result parameters] model_state_json [expr {[dict exists $result model_state_json] ? [dict get $result model_state_json] : ""}] scope [dict get $result scope] domain [dict get $result domain] rmse [dict get $result train_rmse] r2 [dict get $result train_r2]]
    set record [lindex $state($key,records) end]
    set provenance [dict remove $result fitted residual fitted_native residual_native prediction_lower_native prediction_upper_native residual_display fitted_breaks fitted_indices residual_rows source_id]
    set provenance [dict merge $provenance [_sourceProvenance $key]]
    dict set record provenance $provenance
    set record [dict merge $record $predictionNative]
    dict set record source_curve_id $state($key,activeSource)
    dict set record fit_curve_id "accepted[incr state($key,nextFit)]"
    dict set record provenance fit_curve_id [dict get $record fit_curve_id]
    dict set record provenance accepted_name $label
    dict set record point_count [dict get $result output_n]
    set state($key,records) [lreplace $state($key,records) end end $record]
    set state($key,accepted) $id
    set state($key,previewAccepted) 1
    set state($key,previewFitId) $id
    return $id
}
proc ::GX::DatasetCurveFit::_recordIndex {key id} {
    variable state
    set index 0
    foreach record $state($key,records) {
        if {[dict get $record id] eq $id || ([dict exists $record fit_curve_id]&&[dict get $record fit_curve_id] eq $id)} {return $index}
        incr index
    }
    error "Accepted fit $id is unavailable"
}
proc ::GX::DatasetCurveFit::setFitVisible {key id visible} {
    variable state
    _assertSession $key
    set index [_recordIndex $key $id];set record [lindex $state($key,records) $index]
    ::GX::Native2D::core visible $state($key,scene) [dict get $record id] $visible
    foreach field {prediction_lower_native prediction_upper_native} {if {[dict exists $record $field]} {::GX::Native2D::core visible $state($key,scene) [dict get $record $field] $visible}}
    dict set record visible [expr {!!$visible}]
    set state($key,records) [lreplace $state($key,records) $index $index $record]
}
proc ::GX::DatasetCurveFit::deleteFit {key id} {
    variable state
    _assertSession $key
    _workspaceCapture $key
    set index [_recordIndex $key $id];set record [lindex $state($key,records) $index]
    set native [dict get $record id];set owner [dict get $record source_curve_id]
    ::GX::Native2D::core delete $state($key,scene) $native
    foreach field {prediction_lower_native prediction_upper_native} {if {[dict exists $record $field]} {::GX::Native2D::core delete $state($key,scene) [dict get $record $field]}}
    set state($key,records) [lreplace $state($key,records) $index $index]
    if {[dict exists $state($key,sources) $owner state accepted]&&[dict get $state($key,sources) $owner state accepted] eq $native} {
        set replacement ""
        foreach remaining $state($key,records) {
            if {[dict get $remaining source_curve_id] eq $owner} {set replacement [dict get $remaining id]}
        }
        dict set state($key,sources) $owner state accepted $replacement
        dict set state($key,sources) $owner state previewAccepted 0
        dict set state($key,sources) $owner state previewFitId ""
        if {$owner eq $state($key,activeSource)} {
            set state($key,accepted) $replacement;set state($key,previewAccepted) 0;set state($key,previewFitId) ""
        }
    }
}
proc ::GX::DatasetCurveFit::_csvCell {value} {
    return "\"[string map {\" \"\"} $value]\""
}
proc ::GX::DatasetCurveFit::exportCsv {key path {fitId ""}} {
    variable state
    variable version
    _assertSession $key
    if {$fitId eq ""} {set fitId $state($key,accepted)}
    if {$fitId eq ""} {error "Accept a fit before exporting"}
    set record [lindex $state($key,records) [_recordIndex $key $fitId]]
    set native [dict get $record id]
    set count [::GX::Native2D::core count $state($key,scene) $native]
    set artifacts [list [dict create id csv destination $path writer [list ::GX::DatasetCurveFit::_exportCsvPoints $key $record $native $count]]]
    if {[dict exists $record provenance model_state_resource]} {
        lappend artifacts [dict create id model destination "${path}.model.json" writer [list ::GX::DatasetCurveFit::_exportModelResource [dict get $record provenance model_state_resource]]]
    }
    if {[dict exists $record provenance orthogonal_resource]} {
        _validateAcceptedStatistics $record
        foreach {id suffix data rows} {measurements measurements measurement_resource measurement_rows_resource orthogonal orthogonal orthogonal_resource training_rows_resource} {
            lappend artifacts [dict create id $id destination "${path}.${suffix}.csv" writer [list ::GX::DatasetCurveFit::_exportOwnedMeasurementRows [dict get $record provenance] $data $rows]]
        }
    }
    if {[dict get [_preprocessingInfo [dict get $record provenance]] status] eq "value"} {
        lappend artifacts [dict create id preprocessing destination "${path}.preprocessing.csv" writer [list ::GX::DatasetCurveFit::_exportPreprocessingRows [dict get $record provenance]]]
    }
    lappend artifacts [dict create id report destination "${path}.report.txt" writer [list ::GX::DatasetCurveFit::_exportScientificReport $record]]
    lappend artifacts [dict create id metadata destination "${path}.metadata.ini" writer [list ::GX::DatasetCurveFit::_exportCsvMetadata $record $version]]
    ::GX::filePublicationPublishBundle $artifacts replace
    return $count
}
proc ::GX::DatasetCurveFit::_exportCsvPoints {key record native count out context} {
    variable state
        fconfigure $out -encoding utf-8 -translation lf
        set lineage [dict get $record provenance]
        set kind [dict get $lineage source_kind]
        set identityField [expr {$kind eq "builtin_sample" ? "source_sample_id" : "source_dataset_id"}]
        set xId [dict get $lineage source_axes x variable_id];set yId [dict get $lineage source_axes y variable_id]
        set reverseFunctional [expr {[::GX::datasetPublicationV2DictDefault $lineage orientation y_of_x] eq "x_of_y"}]
        set geometric [expr {[::GX::datasetPublicationV2DictDefault $lineage parametric 0]||[::GX::datasetPublicationV2DictDefault $lineage orientation y_of_x] eq "r_of_theta"}]
        set xColumn [expr {$reverseFunctional||$geometric ? "fitted_$xId" : "x_$xId"}]
        set yColumn [expr {$reverseFunctional ? "y_$yId" : "fitted_$yId"}]
        set header [list [_csvCell $xColumn] [_csvCell $yColumn] source_kind $identityField fit_model fit_scope fit_core_id]
        set hasDomain [expr {[_outputDomainInfo $lineage] ne {}}]
        if {$hasDomain} {lappend header fit_query is_extrapolated}
        puts $out [join $header ,]
        set provenance [join [list [_csvCell $kind] [_csvCell [dict get $lineage $identityField]] [_csvCell [dict get $record model]] [_csvCell [dict get $record scope]] $native] ,]
        set reader {}
        try {
            if {$hasDomain&&[dict exists $lineage output_domain_resource]} {set reader [::GX::interactiveDocumentResourceOpenReader [dict get $lineage output_domain_resource]]}
            for {set start 0} {$start<$count} {incr start 4096} {
                set n [expr {min(4096,$count-$start)}];set page {}
                if {$hasDomain} {set page [_outputDomainNext $lineage $reader $start $n]}
                set i 0
                foreach point [::GX::Native2D::core points_page $state($key,scene) $native $start $n] {
                    lassign $point x y;set row "[format %.17g $x],[format %.17g $y],$provenance"
                    if {$hasDomain} {append row ,[format %.17g [lindex [dict get $page fit_query] $i]],[lindex [dict get $page is_extrapolated] $i]}
                    puts $out $row;incr i
                }
            }
        } finally {if {$reader ne {}} {::GX::interactiveDocumentResourceCloseReader $reader}}
}
proc ::GX::DatasetCurveFit::_exportModelResource {reference out context} {
    set reader [::GX::interactiveDocumentResourceOpenReader $reference]
    try {
        while {1} {
            set chunk [::GX::interactiveDocumentResourceNext $reader 65536]
            puts -nonewline $out [dict get $chunk bytes]
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::interactiveDocumentResourceCloseReader $reader}
}
proc ::GX::DatasetCurveFit::_exportOwnedMeasurementRows {metadata dataField rowsField out context} {
    set reference [dict get $metadata $dataField];set rowsReference [dict get $metadata $rowsField]
    set info [::GX::interactiveDocumentResourceInfo $reference];set count [dict get $info metadata row_count]
    set columns [dict get $info metadata columns];set width [llength $columns];set stride [expr {8*$width}]
    fconfigure $out -encoding utf-8 -translation lf
    puts $out [join [linsert $columns 0 original_source_row_index] ,]
    for {set first 0} {$first<$count} {incr first 4096} {
        set n [expr {min(4096,$count-$first)}]
        binary scan [lindex [::GX::interactiveDocumentResourceReadRanges $reference [list [list [expr {$stride*$first}] [expr {$stride*$n}]]]] 0] q* values
        binary scan [lindex [::GX::interactiveDocumentResourceReadRanges $rowsReference [list [list [expr {8*$first}] [expr {8*$n}]]]] 0] wu* identities
        set offset 0
        foreach row $identities {
            set line [list $row]
            foreach value [lrange $values $offset [expr {$offset+$width-1}]] {
                if {[string equal -nocase $value NaN]} {lappend line NaN} else {lappend line [format %.17g $value]}
            }
            puts $out [join $line ,];incr offset $width
        }
    }
}
proc ::GX::DatasetCurveFit::_exportCsvMetadata {record version out context} {
    set metadata [expr {[dict exists $record provenance] ? [dict get $record provenance] : [dict remove $record id points color visible label]}]
    _validateStatisticsMetadata $metadata
    dict set metadata producer_module viewer.dataset_curve_fit
    dict set metadata producer_version $version
    dict set metadata csv_sha256 [dict get $context completed csv sha256]
    foreach id {preprocessing report} {
        if {[dict exists $context completed $id]} {
            dict set metadata ${id}_file [file tail [dict get $context completed $id destination]]
            dict set metadata ${id}_sha256 [dict get $context completed $id sha256]
        }
    }
    if {[_outputDomainInfo $metadata] ne {}} {
        dict set metadata output_domain_columns {fit_query is_extrapolated}
        dict set metadata output_domain_storage csv_columns
        dict unset metadata output_domain_values
    } else {dict set metadata output_domain_status unavailable_historical_receipt}
    if {[dict exists $context completed model]} {
        dict set metadata model_state_file [file tail [dict get $context completed model destination]]
        dict set metadata model_state_sha256 [dict get $context completed model sha256]
        dict set metadata model_state_storage external_json_file
    }
    foreach {id prefix} {measurements measurement_values orthogonal orthogonal_corrections} {
        if {[dict exists $context completed $id]} {
            dict set metadata ${prefix}_file [file tail [dict get $context completed $id destination]]
            dict set metadata ${prefix}_sha256 [dict get $context completed $id sha256]
            dict set metadata ${prefix}_row_identity {Exact source row index from the captured Curve Source; retained uint64 values are not renumbered}
        }
    }
    fconfigure $out -encoding utf-8 -translation lf
    puts $out "; GX-TXT Dataset Curve Fit CSV metadata v1\n\[curve_fit\]"
    foreach field [lsort [dict keys $metadata]] {::GX::putKV $out $field [dict get $metadata $field]}
}
proc ::GX::DatasetCurveFit::_formulaBase {result} {
    set p [lmap v [split [dict get $result parameters] ,] {format %.7g $v}]
    set model [dict get $result model]
    switch -- $model {
        registered {return "Registered [dict get $result options registered_model reference]/[dict get $result options registered_model callable_id]: [dict get $result options registered_model definition description]"}
        formula {return "y = [dict get $result numeric_model_state formula_declaration original_expression]"}
        components - regions {return "y = [lindex [dict get $result numeric_model_state expression] 0]"}
        circular_arc {return "Circular arc: center, radius and oriented angle interval are saved in model state."}
        quadratic_bezier {return "Quadratic Bézier: P0, P1 and P2 are saved in model state."}
        cubic_bezier {return "Cubic Bézier: P0, P1, P2 and P3 are saved in model state."}
        parametric_polynomial {return "X=x(t), Y=y(t): independent polynomial coordinates, degree [dict get $result degree]."}
        parametric_spline {return "X=x(t), Y=y(t): ordered cubic interpolation; [dict get $result topology] topology."}
        pchip {return "Shape-preserving piecewise cubic interpolation (PCHIP)."}
        akima {return "C1 cubic Akima interpolation through original ordered observations; explicit endpoint conditions."}
        bspline {return "Fixed explicit knots: unweighted B-spline approximation with declared degree and boundary conditions."}
        smoothing_spline {return "Natural cubic smoothing spline; lambda controls squared curvature penalty."}
        fourier {return "Fourier series, order [dict get $result degree]; coefficients and basis are saved in model state."}
        linear {return "y = [lindex $p 0] x [expr {[lindex $p 1] < 0 ? "−" : "+"}] [format %.7g [expr {abs([lindex $p 1])}]]"}
        polynomial {
            set terms {};set degree [expr {[llength $p]-1}]
            for {set i 0} {$i <= $degree} {incr i} {
                set power [expr {$degree-$i}]
                set value [lindex $p $i]
                set factor [expr {$power == 0 ? "" : ($power == 1 ? " x" : " x^$power")}]
                lappend terms [list $value $factor]
            }
            set out "y = [lindex [lindex $terms 0] 0][lindex [lindex $terms 0] 1]"
            foreach term [lrange $terms 1 end] {
                lassign $term value factor
                append out " [expr {$value < 0 ? "−" : "+"}] [format %.7g [expr {abs($value)}]]$factor"
            }
            return $out
        }
        exponential {return "y = [lindex $p 0] exp([lindex $p 1] x) [expr {[lindex $p 2] < 0 ? "−" : "+"}] [format %.7g [expr {abs([lindex $p 2])}]]"}
        power_law {return "y = [lindex $p 0] x^[lindex $p 1]"}
        gaussian {return "y = [lindex $p 0] exp(−½ ((x − [lindex $p 1])/[lindex $p 2])²) [expr {[lindex $p 3] < 0 ? "−" : "+"}] [format %.7g [expr {abs([lindex $p 3])}]]"}
    }
}
proc ::GX::DatasetCurveFit::parameterReport {result} {
    if {![dict exists $result statistical_results training]} {return {Legacy result: statistics have no versioned interpretation. Refit to obtain a validated report.}}
    return [::GX::StatisticsV1::parameterReport [dict get $result statistical_results training]]
}
proc ::GX::DatasetCurveFit::_documentMatchesDataset {documentId dataset} {
    return [_documentMatchesSource $documentId dataset $dataset]
}
proc ::GX::DatasetCurveFit::_documentMatchesSource {documentId kind identity} {
    if {$documentId eq ""} {return 0}
    set document [::GX::interactiveDocumentRead $documentId]
    set payload [dict get $document payload]
    if {[dict exists $payload workspace_sources]} {
        foreach entry [dict get $payload workspace_sources] {
            set source [dict get $entry state]
            if {[dict get $source sourceKind] eq $kind && [dict get $source dataset] eq $identity} {return 1}
        }
        return 0
    }
    set savedKind [expr {[dict exists $payload source_kind] ? [dict get $payload source_kind] : "dataset"}]
    if {$savedKind eq "sample"} {set savedKind builtin_sample}
    if {$kind eq "sample"} {set kind builtin_sample}
    return [expr {$savedKind eq $kind && [dict exists $payload dataset] && [dict get $payload dataset] eq $identity}]
}
proc ::GX::DatasetCurveFit::_restoreLegacyState {w requestedDataset {exact {}}} {
    variable state
    if {$requestedDataset ne ""} {set state($w,documentId) ""}
    set docs [::GX::interactiveDocumentList viewer.dataset_curve_fit dataset_curve_fit]
    if {$exact ne {}} {set docs [list [::GX::interactiveDocumentRead $exact]]}
    if {![llength $docs]} return
    set document {}
    foreach item $docs {
        set candidate [::GX::interactiveDocumentRead [dict get $item id]]
        set payload [dict get $candidate payload]
        if {$requestedDataset ne "" && [dict exists $payload source_kind] && [dict get $payload source_kind] in {sample builtin_sample}} continue
        if {$requestedDataset ne "" && (![dict exists $payload dataset] ||
            [dict get $payload dataset] ne $requestedDataset)} continue
        set document $candidate
        break
    }
    if {$document eq ""} return
    set payload [dict get $document payload]
    if {![dict exists $payload version] || [dict get $payload version] ne "1"} {error "Saved Dataset Curve Fit state has an unsupported format"}
    set state($w,documentId) [dict get $document id]
    set state($w,documentRevision) [dict get $document revision]
    set state($w,documentGeneration) [dict get $document generation]
    set state($w,savedPayload) [dict remove $payload workspace_metadata]
    set dataset [dict get $payload dataset]
    set sample [expr {[dict exists $payload source_kind] && [dict get $payload source_kind] in {sample builtin_sample}}]
    if {$sample} {
        if {![dict exists [sampleCatalog] $dataset]} {set state($w,status) "Saved sample is unavailable.";return}
        set state($w,sample) $dataset
    } else {
        if {$dataset ni [datasets]} {set state($w,status) "Saved Dataset is unavailable; choose another Dataset.";return}
        set state($w,dataset) $dataset
        _uiDataset $w
    }
    foreach field {x y model scope domain min max samples degree initial period smoothing} {
        if {[dict exists $payload $field]} {set state($w,$field) [dict get $payload $field]}
    }
    if {!$sample} {_uiVariableChoices $w}
    set filters [dict get $payload filters]
    if {$sample} {
        loadSample $w $dataset
    } else {
        if {[dict get $payload source_sha] ne [_datasetSha $dataset]} {
            set state($w,status) "Saved source Dataset changed; reload it before fitting."
            return
        }
        loadSource $w $dataset $state($w,x) $state($w,y) $filters
    }
    $w.left.viewport.content.filters.list delete 0 end
    foreach filter $filters {$w.left.viewport.content.filters.list insert end "[dict get $filter variable] [dict get $filter operator] [join [dict get $filter value] ,]"}
    foreach index [dict get $payload selected] {selectPoint $w $index add}
    foreach record [dict get $payload records] {
        # Repair legacy dev-051 sample lineage when restoring an accepted curve.
        if {$sample} {
            set lineage [expr {[dict exists $record provenance] ? [dict get $record provenance] : {}}]
            foreach field {source_dataset_id source_x_variable_id source_y_variable_id source_sha256 source_filters} {dict unset lineage $field}
            dict set record provenance [dict merge $lineage [_sourceProvenance $w]]
        }
        set id [::GX::Native2D::core add $state($w,scene) [dict get $record points]]
        ::GX::Native2D::core style $state($w,scene) $id [dict get $record color] 2.5
        ::GX::Native2D::core visible $state($w,scene) $id [dict get $record visible]
        dict set record id $id
        dict set record source_curve_id $state($w,activeSource)
        dict set record fit_curve_id "accepted[incr state($w,nextFit)]"
        if {[dict exists $record label]} {dict set record label [regsub {^Fit [0-9]+:} [dict get $record label] "Fit $id:"]}
        lappend state($w,records) $record
        set state($w,accepted) $id
    }
    if {[dict exists $payload presentation]} {::GX::Native2D::core presentation $state($w,scene) [dict get $payload presentation]}
    if {[dict exists $payload view_bounds]} {set state($w,viewBounds) [dict get $payload view_bounds]}
    _uiModelFields $w
    _uiDomainFields $w
    _refreshFits $w
    if {[llength $state($w,records)]} {$w.left.viewport.content.accepted.list selection set end}
    $w.actions.preview configure -state normal
    $w.actions.accept configure -state disabled
    $w.actions.publish configure -state disabled
    $w.actions.export configure -state [expr {[llength $state($w,records)] ? "normal" : "disabled"}]
    set state($w,documentId) [dict get $document id]
    set state($w,status) "Restored [llength $state($w,records)] accepted fits from the Session."
    redraw $w
}

# Every internal GUI callback is a Tcl argument list with an explicit owner.
# Dispatch to literal procedures; never interpret a captured widget script.
proc ::GX::DatasetCurveFit::_invokeUiCommand {w command} {
    if {[llength $command]<2||[lindex $command 1] ne $w} {error {Invalid Fitter command owner}}
    set arguments [lrange $command 2 end]
    switch -- [lindex $command 0] {
        ::GX::DatasetCurveFit::_suggestionOpen {return [_suggestionOpen $w]}
        ::GX::DatasetCurveFit::_suggestionRefresh {return [_suggestionRefresh $w]}
        ::GX::DatasetCurveFit::_plausibilityOpen {return [_plausibilityOpen $w]}
        ::GX::DatasetCurveFit::_plausibilityAdd {return [_plausibilityAdd $w]}
        ::GX::DatasetCurveFit::_plausibilityReplace {return [_plausibilityReplace $w]}
        ::GX::DatasetCurveFit::_plausibilityRemove {return [_plausibilityRemove $w]}
        ::GX::DatasetCurveFit::_plausibilityEvaluate {return [_plausibilityEvaluate $w]}
        ::GX::DatasetCurveFit::_plausibilityPublish {return [_plausibilityPublish $w]}
        ::GX::DatasetCurveFit::_derivedOpen {return [_derivedOpen $w]}
        ::GX::DatasetCurveFit::_derivedEvaluate {return [_derivedEvaluate $w]}
        ::GX::DatasetCurveFit::_derivedPublish {return [_derivedPublish $w]}
        ::GX::DatasetCurveFit::_workbenchTransfer {return [_workbenchTransfer $w]}
        ::GX::DatasetCurveFit::_translationSettings {return [_translationSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_statisticalSettings {return [_statisticalSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_covarianceSettings {return [_covarianceSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_covarianceDetails {return [_covarianceDetails $w {*}$arguments]}
        ::GX::DatasetCurveFit::_bootstrapSettings {return [_bootstrapSettings $w]}
        ::GX::DatasetCurveFit::_profileSettings {return [_profileSettings $w]}
        ::GX::DatasetCurveFit::_influenceDialogSelect {return [_influenceDialogSelect $w]}
        ::GX::DatasetCurveFit::_sequenceRefresh {return [_sequenceRefresh $w]}
        ::GX::DatasetCurveFit::_solverSettings {return [_solverSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_knotSettings {return [_knotSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_smoothingSettings {return [_smoothingSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_componentSettings {return [_componentSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_registeredSettings {return [_registeredSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_registeredDeclareDialog {return [_registeredDeclareDialog $w {*}$arguments]}
        ::GX::DatasetCurveFit::_registeredCancel {return [_registeredCancel $w {*}$arguments]}
        ::GX::DatasetCurveFit::_componentAddChoice {return [_componentAddChoice $w {*}$arguments]}
        ::GX::DatasetCurveFit::_componentApply {return [_componentApply $w {*}$arguments]}
        ::GX::DatasetCurveFit::_rationalSettings {return [_rationalSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_rationalEditorDegrees {return [_rationalEditorDegrees $w {*}$arguments]}
        ::GX::DatasetCurveFit::_implicitSettings {return [_implicitSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_complexSettings {return [_complexSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_formulaSettings {return [_formulaSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_parameterSettings {return [_parameterSettings $w]}
        ::GX::DatasetCurveFit::_parameterSuggest {return [_parameterSuggest $w {*}$arguments]}
        ::GX::DatasetCurveFit::_parameterLive {return [_parameterLive $w {*}$arguments]}
        ::GX::DatasetCurveFit::_parameterApply {return [_parameterApply $w {*}$arguments]}
        ::GX::DatasetCurveFit::_formulaValidate {return [_formulaValidate $w {*}$arguments]}
        ::GX::DatasetCurveFit::_formulaApply {return [_formulaApply $w {*}$arguments]}
        ::GX::DatasetCurveFit::_formulaAddRow {return [_formulaAddRow $w {*}$arguments]}
        ::GX::DatasetCurveFit::_regionSettings {return [_regionSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_regionAddChoice {return [_regionAddChoice $w {*}$arguments]}
        ::GX::DatasetCurveFit::_regionApply {return [_regionApply $w {*}$arguments]}
        ::GX::DatasetCurveFit::_logSettings {return [_logSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_logPublishDialog {return [_logPublishDialog $w {*}$arguments]}
        ::GX::DatasetCurveFit::_smoothSettings {return [_smoothSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_baselineSettings {return [_baselineSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_baselineApply {return [_baselineApply $w {*}$arguments]}
        ::GX::DatasetCurveFit::_queryOpen {return [_queryOpen $w]}
        ::GX::DatasetCurveFit::_queryRefresh {return [_queryRefresh $w {*}$arguments]}
        ::GX::DatasetCurveFit::_modelExport {return [_modelExport $w]}
        ::GX::DatasetCurveFit::_recipeExport {return [_recipeExport $w {*}$arguments]}
        ::GX::DatasetCurveFit::_templateSaveDialog {return [_templateSaveDialog $w {*}$arguments]}
        ::GX::DatasetCurveFit::_templateDialog {return [_templateDialog $w {*}$arguments]}
        ::GX::DatasetCurveFit::_templateApply {return [_templateApply $w {*}$arguments]}
        ::GX::DatasetCurveFit::_workspaceSelect {return [_workspaceSelect $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiApplySetting {return [_uiApplySetting $w {*}$arguments]}
        ::GX::DatasetCurveFit::_workspaceShow {return [_workspaceShow $w {*}$arguments]}
        ::GX::DatasetCurveFit::_workspaceStyle {return [_workspaceStyle $w {*}$arguments]}
        ::GX::DatasetCurveFit::_workspaceRemove {return [_workspaceRemove $w {*}$arguments]}
        ::GX::DatasetCurveFit::_workspaceReload {return [_workspaceReload $w {*}$arguments]}
        ::GX::DatasetCurveFit::_workspaceBatch {return [_workspaceBatch $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiReverseSource {return [_uiReverseSource $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiDataset {return [_uiDataset $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiLoadSample {return [_uiLoadSample $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiPublishSample {return [_uiPublishSample $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiAddFilter {return [_uiAddFilter $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiRemoveFilter {return [_uiRemoveFilter $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiLoad {return [_uiLoad $w {*}$arguments]}
        ::GX::DatasetCurveFit::_parametricSettings {return [_parametricSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_polarSettings {return [_polarSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiClear {return [_uiClear $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiPreview {return [_uiPreview $w {*}$arguments]}
        ::GX::DatasetCurveFit::_acceptDialog {return [_acceptDialog $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiAccept {return [_uiAccept $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiPublish {return [_uiPublish $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiExport {return [_uiExport $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiRemoveLastRect {return [_uiRemoveLastRect $w {*}$arguments]}
        ::GX::DatasetCurveFit::_viewSettings {return [_viewSettings $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiFitAction {return [_uiFitAction $w {*}$arguments]}
        ::GX::DatasetCurveFit::_uiPublishAccepted {return [_uiPublishAccepted $w {*}$arguments]}
        ::GX::DatasetCurveFit::_familyDialog {return [_familyDialog $w]}
        ::GX::DatasetCurveFit::_globalFamilyDialog {return [_globalFamilyDialog $w]}
        ::GX::DatasetCurveFit::_parameterDatasetDialog {return [_parameterDatasetDialog $w {*}$arguments]}
        ::GX::DatasetCurveFit::_residualAxis {return [_residualAxis $w {*}$arguments]}
        ::GX::DatasetCurveFit::_residualReviewSelect {return [_residualReviewSelect $w {*}$arguments]}
        ::GX::DatasetCurveFit::_residualPageUi {return [_residualPageUi $w {*}$arguments]}
        ::GX::DatasetCurveFit::_restoreState {return [_restoreState $w {*}$arguments]}
        default {error {Unregistered Fitter UI procedure}}
    }
}
proc ::GX::DatasetCurveFit::_uiSafe {w script} {
    variable state
    try {
        set readOnly [expr {[lindex $script 0] in {::GX::DatasetCurveFit::_suggestionOpen ::GX::DatasetCurveFit::_suggestionRefresh ::GX::DatasetCurveFit::_plausibilityOpen ::GX::DatasetCurveFit::_plausibilityAdd ::GX::DatasetCurveFit::_plausibilityReplace ::GX::DatasetCurveFit::_plausibilityRemove ::GX::DatasetCurveFit::_plausibilityEvaluate ::GX::DatasetCurveFit::_plausibilityPublish ::GX::DatasetCurveFit::_derivedOpen ::GX::DatasetCurveFit::_derivedEvaluate ::GX::DatasetCurveFit::_derivedPublish ::GX::DatasetCurveFit::_workbenchTransfer ::GX::DatasetCurveFit::_queryOpen ::GX::DatasetCurveFit::_queryRefresh ::GX::DatasetCurveFit::_globalFamilyDialog ::GX::DatasetCurveFit::_familyDialog ::GX::DatasetCurveFit::_parameterDatasetDialog ::GX::DatasetCurveFit::_acceptDialog ::GX::DatasetCurveFit::_modelExport ::GX::DatasetCurveFit::_recipeExport ::GX::DatasetCurveFit::_templateSaveDialog ::GX::DatasetCurveFit::_templateDialog}}]
        if {[namespace tail [lindex $script 0]] eq "_workspaceBatch"&&[lindex $script 2]} {set readOnly 1}
        if {!$readOnly&&[namespace tail [lindex $script 0]] ne "_uiApplySetting" && ![_commitFocusedSetting $w]} return
        if {!$readOnly&&[dict exists $::GX::ScientificHistory::viewers $w] && ![::GX::scientificHistoryViewerPrepareEdit $w]} return
        set descriptions [dict create _uiPreview {Preview fit} _uiAccept {Accept fitted curve} _uiLoad {Add Dataset curve} _uiDataset {Choose Dataset axes} _uiOrientation {Choose fit orientation} _uiClear {Clear fitting point selection} _uiAddFilter {Add source filter} _uiRemoveFilter {Remove source filter} _uiFitAction {Edit accepted fit presentation} _uiRemoveLastRect {Remove fitting rectangle} _workspaceSelect {Activate source curve} _uiLoadSample {Load built-in sample}]
        set state($w,historyDescription) [::GX::datasetPublicationV2DictDefault $descriptions [namespace tail [lindex $script 0]] {Update fitter working context}]
        _invokeUiCommand $w $script
    } on error {err options} {
        set state($w,status) $err
        if {[dict get $options -errorcode] eq {GX CURVE_SOURCE CANCELLED}} return
        tk_messageBox -parent $w -icon error -type ok -title "Dataset Curve Fit" -message $err
    } finally {unset -nocomplain state($w,historyDescription)}
}
proc ::GX::DatasetCurveFit::_markSourceDirty {w} {
    variable state
    if {$state($w,source) eq ""} return
    if {[list $state($w,dataset) $state($w,x) $state($w,y) $state($w,filters)] eq $state($w,loadedBinding)} return
    set state($w,status) "Dataset, X, Y or filters changed. Reload the source before fitting or exporting."
    foreach button {preview accept export} {$w.actions.$button configure -state disabled}
}
proc ::GX::DatasetCurveFit::_uiDataset {w} {
    variable state
    set dataset $state($w,dataset)
    if {$dataset eq ""} return
    set schema [variables $dataset]
    set state($w,schema) $schema
    set numeric [dict get $schema numeric]
    foreach key {x y} {
        if {$state($w,$key) ni $numeric} {set state($w,$key) [lindex $numeric [expr {$key eq "x" ? 0 : 1}]]}
    }
    if {$state($w,filterVar) ni [dict get $schema all]} {set state($w,filterVar) [lindex [dict get $schema all] 0]}
    _uiVariableChoices $w
    set state($w,filters) {}
    $w.left.viewport.content.filters.list delete 0 end
    _uiFilterOperator $w
    if {$state($w,source) eq ""} {set state($w,status) "Choose filters, then load the Dataset curve."} else {_markSourceDirty $w}
}
proc ::GX::DatasetCurveFit::_uiFilterOperator {w} {
    variable state
    if {$state($w,filterVar) eq ""} return
    set kind [dict get [dict get $state($w,schema) kinds] $state($w,filterVar)]
    set ops [expr {$kind eq "number" ? {= != < <= > >= between} : {= != contains LIKE}}]
    $w.left.viewport.content.filters.controls.operator configure -values $ops
    if {$state($w,filterOp) ni $ops} {set state($w,filterOp) =}
}
proc ::GX::DatasetCurveFit::_uiAddFilter {w} {
    variable state
    set value $state($w,filterValue)
    if {$state($w,filterOp) eq "between"} {
        set value [lmap part [split $value ,] {string trim $part}]
        if {[llength $value] != 2} {error "Enter between bounds as lower,upper"}
    }
    set filter [dict create variable $state($w,filterVar) operator $state($w,filterOp) value $value]
    set kind [dict get [dict get $state($w,schema) kinds] $state($w,filterVar)]
    filterMatch $kind [expr {$kind eq "number" ? 0 : ""}] $state($w,filterOp) $value
    lappend state($w,filters) $filter
    $w.left.viewport.content.filters.list insert end "$state($w,filterVar) $state($w,filterOp) [join $value ,]"
    set state($w,status) "[llength $state($w,filters)] filters; reload the Dataset curve to apply."
    _markSourceDirty $w
}
proc ::GX::DatasetCurveFit::_uiRemoveFilter {w} {
    variable state
    set index [lindex [$w.left.viewport.content.filters.list curselection] 0]
    if {$index eq ""} return
    set state($w,filters) [lreplace $state($w,filters) $index $index]
    $w.left.viewport.content.filters.list delete $index
    _markSourceDirty $w
}
proc ::GX::DatasetCurveFit::_uiLoad {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {error "A Dataset source is already loading"}
    set state($w,loading) 1;set state($w,sourceJob) "";set state($w,sourceCancelled) 0;set state($w,closeRequested) 0
    set controls [_sourceControls $w 1]
    $w.left.viewport.content.filters.controls.cancel configure -state normal
    try {
        loadSource $w $state($w,dataset) $state($w,x) $state($w,y) $state($w,filters)
    } finally {
        set state($w,loading) 0;set state($w,sourceJob) ""
        _sourceControls $w 0 $controls
        _workspaceRefresh $w
        $w.left.viewport.content.filters.controls.cancel configure -state disabled
        if {$state($w,closeRequested)} {after idle [list ::GX::DatasetCurveFit::_closeWindow $w]}
    }
    set state($w,status) "Loaded [llength [sourcePoints $w]] Dataset points into Native 2D; click or drag to select fit points."
    if {[dict exists $state($w,sourceDescriptor) row_count]} {set state($w,status) "Added $state($w,activeSource): [dict get $state($w,sourceDescriptor) row_count] exact source rows; [llength [sourcePoints $w]] display points. Fit all reads exact data."}
    set state($w,report) ""
    $w.right.residuals.table delete [$w.right.residuals.table children {}]
    _refreshFits $w
    $w.actions.preview configure -state normal
    $w.actions.accept configure -state disabled
    $w.actions.publish configure -state disabled
    $w.actions.export configure -state disabled
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiLoadSample {w} {
    variable state
    loadSample $w $state($w,sample)
    set state($w,status) "Loaded built-in sample into Native 2D. It is local to the fitter until explicitly published."
    set state($w,report) ""
    $w.right.residuals.table delete [$w.right.residuals.table children {}]
    _refreshFits $w
    $w.actions.preview configure -state normal
    $w.actions.accept configure -state disabled
    $w.actions.publish configure -state disabled
    $w.actions.export configure -state disabled
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiModel {w} {
    variable state
    switch -- $state($w,model) {
        registered {if {[info exists state($w,registeredModel)]&&$state($w,registeredModel) ne {}} {set state($w,initial) [join [dict get $state($w,registeredModel) definition initial] ,]};set state($w,degree) 1}
        exponential {set state($w,initial) {1,-0.1,0}}
        power_law {set state($w,initial) {1,1}}
        gaussian {set state($w,initial) {1,0,1,0}}
        default {set state($w,initial) ""}
    }
    set parametric [expr {$state($w,model) in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial parametric_spline}}]
    if {$parametric && $state($w,domain) eq "range"} {set state($w,domain) parameter}
    if {!$parametric && $state($w,domain) eq "parameter"} {set state($w,domain) range}
    $w.left.viewport.content.settings.body.domain configure -values [expr {$parametric ? {source parameter} : {source range}}]
    if {$parametric && $state($w,domain) eq "parameter"} {
        if {$state($w,min) eq ""} {set state($w,min) 0}
        if {$state($w,max) eq ""} {set state($w,max) 1}
    }
    if {$parametric} {set state($w,orientation) parametric} elseif {$state($w,orientation) eq "parametric"} {set state($w,orientation) y_of_x}
    _orientationLabels $w
    _uiModelFields $w
    _uiDomainFields $w
    _invalidateSettings $w
    _workspaceCapture $w;_saveState $w
}
proc ::GX::DatasetCurveFit::_uiModelFields {w} {
    variable state
    $w.left.viewport.content.settings.body.components configure -state [expr {$state($w,model) eq "components"?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.formula configure -state [expr {$state($w,model) eq "formula"?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.knots configure -state [expr {$state($w,model) in {akima bspline}?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.rational configure -state [expr {$state($w,model) eq "rational"?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.implicit configure -state [expr {$state($w,model) eq "implicit"?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.complex_response configure -state [expr {$state($w,model) eq "complex_response"?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.regions configure -state [expr {$state($w,model) eq "regions"?"normal":"disabled"}]
    $w.left.viewport.content.settings.body.domain configure -values [expr {$state($w,model) in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial parametric_spline} ? {source parameter} : {source range}}]
    $w.left.viewport.content.settings.body.parametric configure -state [expr {$state($w,model) in {parametric_polynomial parametric_spline} ? "normal" : "disabled"}]
    $w.left.viewport.content.settings.body.polar configure -state [expr {$state($w,orientation) eq "r_of_theta" ? "normal" : "disabled"}]
    $w.left.viewport.content.settings.parameters.degree configure -state [expr {$state($w,model) in {polynomial parametric_polynomial fourier} ? "normal" : "disabled"}]
    $w.left.viewport.content.settings.parameters.initial configure -state [expr {$state($w,model) in {exponential power_law gaussian registered}||($state($w,model) in {linear polynomial}&&$state($w,measurementKind) eq "sigma_xy") ? "normal" : "disabled"}]
    $w.left.viewport.content.settings.parameters.period configure -state [expr {$state($w,model) eq "fourier" ? "normal" : "disabled"}]
    $w.left.viewport.content.settings.parameters.smoothing configure -state [expr {$state($w,model) eq "smoothing_spline" ? "normal" : "disabled"}]
    $w.left.viewport.content.settings.parameters.l_degree configure -text [expr {$state($w,model) eq "fourier" ? "Order N" : "Degree"}]
    _refreshSettingsControls $w
}
proc ::GX::DatasetCurveFit::_uiDomainFields {w} {
    variable state
    set enabled [expr {$state($w,domain) in {range parameter} ? "normal" : "disabled"}]
    foreach field {min max samples} {$w.left.viewport.content.settings.parameters.$field configure -state $enabled}
    set independent [expr {$state($w,orientation) eq "x_of_y" ? "Y" : ($state($w,orientation) eq "parametric" ? "t" : ($state($w,orientation) eq "r_of_theta" ? "theta" : "X"))}]
    foreach bound {min max} {$w.left.viewport.content.settings.parameters.l_$bound configure -text "$independent $bound"}
    _refreshSettingsControls $w
}
proc ::GX::DatasetCurveFit::_uiPreview {w} {
    variable state
    set domain source
    if {$state($w,domain) eq "range"} {set domain [list $state($w,min) $state($w,max) $state($w,samples)]}
    if {$state($w,domain) eq "parameter"} {set domain [list parameter $state($w,min) $state($w,max) $state($w,samples)]}
    set initial {}
    foreach part [split $state($w,initial) ,] {if {[string trim $part] ne ""} {lappend initial [string trim $part]}}
    set options [_uiFitOptions $w]
    if {$state($w,model) eq "registered"} {return [_registeredUiPreview $w $domain $initial $options]}
    set controls [_operationBegin $w]
    try {set result [preview $w $state($w,model) $state($w,scope) $domain $state($w,degree) $initial $options]} finally {_operationEnd $w $controls}
    _resultPresentation $w
    set state($w,residualStart) 0
    _residualPageUi $w 0
    set state($w,status) "Preview ready. Output X domain is independent of fit-point selection. Accept to add a new CORE curve."
    $w.actions.accept configure -state normal
    $w.actions.publish configure -state normal
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiAccept {w {name {}}} {
    variable state
    set preview $state($w,preview)
    if {$preview eq {}} {error "Preview a fit before accepting it"}
    set domain source
    if {$state($w,domain) eq "range"} {
        set domain [list [_finite $state($w,min) "Output minimum"] [_finite $state($w,max) "Output maximum"] $state($w,samples)]
    }
    if {$state($w,domain) eq "parameter"} {
        set domain [list parameter [_finite $state($w,min) "Parameter minimum"] [_finite $state($w,max) "Parameter maximum"] $state($w,samples)]
    }
    set initial {}
    foreach part [split $state($w,initial) ,] {if {[string trim $part] ne ""} {lappend initial [string trim $part]}}
    set currentOptions [_uiFitOptions $w]
    if {$state($w,model) eq "components"} {
        set resolved [_prepareComponents $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions component_recipe [dict get $resolved composition recipe]
    }
    if {$state($w,model) eq "complex_response"} {
        set resolved [_prepareComplex $w $currentOptions]
        set initial [dict get $resolved parameters]
        dict set currentOptions complex_recipe [dict get $resolved recipe]
    }
    if {$state($w,model) in {akima bspline}} {
        dict set currentOptions knot_options [_prepareKnots $w $state($w,model) $currentOptions]
        set initial {}
    }
    if {$state($w,model) eq "rational"} {
        set resolved [_prepareRational $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions rational_recipe [dict get $resolved recipe]
    }
    if {$state($w,model) eq "implicit"} {
        set resolved [_prepareImplicit $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions implicit_recipe [dict get $resolved recipe]
    }
    if {$state($w,model) eq "formula"} {
        set resolved [_prepareFormula $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions formula_recipe [dict get $resolved formula_declaration recipe]
    }
    if {$state($w,model) eq "regions"} {
        set resolved [_prepareRegions $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions region_recipe [dict get $resolved regional_composition recipe]
    }
    foreach {field value} [list model $state($w,model) scope $state($w,scope) domain $domain degree $state($w,degree) initial $initial options $currentOptions] {
        set captured [dict get $preview $field]
        if {$field eq "domain"&&$captured ne "source"} {
            set parameter [expr {[lindex $captured 0] eq "parameter"}]
            set triple [expr {$parameter?[lrange $captured 1 end]:$captured}]
            lassign $triple lo hi count
            set captured [list [_finite $lo {Captured output minimum}] [_finite $hi {Captured output maximum}] $count]
            if {$parameter} {set captured [linsert $captured 0 parameter]}
        }
        if {$captured ne $value} {error "Fit setting '$field' changed; preview again before accepting"}
    }
    _assertLoaded $w
    if {[dict get $preview scope] eq "selected" && ![_selectionUnchanged $w $preview]} {error "Fit-point selection changed; preview again"}
    set id [accept $w $name]
    set state($w,previewFitId) $id
    set state($w,status) "Accepted Native 2D CORE curve $id. Publish as Dataset separately if needed."
    _refreshFits $w
    $w.left.viewport.content.accepted.list selection clear 0 end
    $w.left.viewport.content.accepted.list selection set end
    $w.actions.accept configure -state disabled
    $w.actions.publish configure -state normal
    $w.actions.export configure -state normal
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiPublish {w} {
    variable state
    set preview $state($w,preview)
    if {$preview eq {}} {error "Preview a fit before publishing"}
    _assertLoaded $w
    if {[dict get $preview source_id] != $state($w,source)} {error "Source curve changed; preview again"}
    set domain source
    if {$state($w,domain) eq "range"} {
        set domain [list [_finite $state($w,min) "Output minimum"] [_finite $state($w,max) "Output maximum"] $state($w,samples)]
    }
    if {$state($w,domain) eq "parameter"} {
        set domain [list parameter [_finite $state($w,min) "Parameter minimum"] [_finite $state($w,max) "Parameter maximum"] $state($w,samples)]
    }
    set initial {}
    foreach part [split $state($w,initial) ,] {if {[string trim $part] ne ""} {lappend initial [string trim $part]}}
    set currentOptions [_uiFitOptions $w]
    if {$state($w,model) eq "components"} {
        set resolved [_prepareComponents $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions component_recipe [dict get $resolved composition recipe]
    }
    if {$state($w,model) eq "complex_response"} {
        set resolved [_prepareComplex $w $currentOptions]
        set initial [dict get $resolved parameters]
        dict set currentOptions complex_recipe [dict get $resolved recipe]
    }
    if {$state($w,model) in {akima bspline}} {
        dict set currentOptions knot_options [_prepareKnots $w $state($w,model) $currentOptions]
        set initial {}
    }
    if {$state($w,model) eq "rational"} {
        set resolved [_prepareRational $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions rational_recipe [dict get $resolved recipe]
    }
    if {$state($w,model) eq "implicit"} {
        set resolved [_prepareImplicit $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions implicit_recipe [dict get $resolved recipe]
    }
    if {$state($w,model) eq "formula"} {
        set resolved [_prepareFormula $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions formula_recipe [dict get $resolved formula_declaration recipe]
    }
    if {$state($w,model) eq "regions"} {
        set resolved [_prepareRegions $w $currentOptions]
        set initial [dict get $resolved initial_parameters]
        dict set currentOptions region_recipe [dict get $resolved regional_composition recipe]
    }
    foreach {field value} [list model $state($w,model) scope $state($w,scope) domain $domain degree $state($w,degree) initial $initial options $currentOptions] {
        if {[dict get $preview $field] ne $value} {error "Fit settings changed; preview again before publishing"}
    }
    if {[dict get $preview scope] eq "selected" && ![_selectionUnchanged $w $preview]} {error "Fit-point selection changed; preview again"}
    set suggested "$state($w,dataset)_[dict get $preview model]_fit"
    set name [_promptFitName $w $suggested]
    if {$name eq ""} return
    set publication [publishFitDataset $w $name]
    set state($w,status) "Published $name as GX-TXT Dataset [dict get $publication dataset_id]."
    _saveState $w
}
proc ::GX::DatasetCurveFit::_promptFitName {parent suggestion} {
    set w .dataset_curve_fit_name
    catch {destroy $w}
    toplevel $w
    wm title $w "Publish Dataset"
    wm transient $w $parent
    set ::GX::DatasetCurveFit::promptName $suggestion
    set ::GX::DatasetCurveFit::promptResult ""
    ttk::label $w.label -text "Public Dataset ID (letters, numbers, underscore, dot or dash)" -wraplength 420
    ttk::entry $w.entry -textvariable ::GX::DatasetCurveFit::promptName -width 48
    ttk::frame $w.actions
    ttk::button $w.actions.ok -text "Publish Dataset" -command {set ::GX::DatasetCurveFit::promptResult [string trim $::GX::DatasetCurveFit::promptName]; destroy .dataset_curve_fit_name}
    ttk::button $w.actions.cancel -text Cancel -command {destroy .dataset_curve_fit_name}
    pack $w.label $w.entry -fill x -padx 10 -pady 5
    pack $w.actions.ok $w.actions.cancel -side left -padx 5 -pady 5
    pack $w.actions -fill x
    bind $w.entry <Return> {set ::GX::DatasetCurveFit::promptResult [string trim $::GX::DatasetCurveFit::promptName]; destroy .dataset_curve_fit_name}
    bind $w <Escape> [list destroy $w]
    wm protocol $w WM_DELETE_WINDOW [list destroy $w]
    focus $w.entry
    grab $w
    tkwait window $w
    return $::GX::DatasetCurveFit::promptResult
}
proc ::GX::DatasetCurveFit::_uiPublishAccepted {w} {
    variable state
    set index [lindex [$w.left.viewport.content.accepted.list curselection] 0]
    if {$index eq ""} {error "Select an accepted fit to publish"}
    set record [lindex $state($w,records) $index]
    set lineage [dict get $record provenance]
    set identity [dict get $lineage [expr {[dict get $lineage source_kind] eq "builtin_sample" ? "source_sample_id" : "source_dataset_id"}]]
    set name [_promptFitName $w "${identity}_[dict get $record model]_fit"]
    if {$name eq ""} return
    set result [publishFitDataset $w $name [dict get $record fit_curve_id]]
    set state($w,status) "Published accepted [dict get $record fit_curve_id] as Dataset [dict get $result dataset_id]."
    _saveState $w
}
proc ::GX::DatasetCurveFit::publishFitDataset {key name {fitId ""}} {
    variable state
    variable version
    _assertSession $key
    set name [string trim $name]
    if {$name eq ""} {error "Fit Dataset needs a public name/ID"}
    if {$fitId ne ""} {
        set record [lindex $state($key,records) [_recordIndex $key $fitId]]
        set result [dict get $record provenance]
        dict set result fitted [dict get $record points]
        dict set result fitted_native [dict get $record id]
        set lineage [dict get $record provenance]
    } else {
        _assertLoaded $key
        if {$state($key,preview) eq {}} {error "Preview a fit first"}
        set result $state($key,preview)
        if {[dict get $result scope] eq "selected" && ![_selectionUnchanged $key $result]} {error "Fit-point selection changed; preview again"}
        set lineage [_sourceProvenance $key]
    }
    set session $::GX::currentSession
    set datasetId [::GX::datasetPublicationV2RequestedId $name fit]
    set sourceKind [dict get $lineage source_kind]
    set sourceIdentity [dict get $lineage [expr {$sourceKind eq "dataset" ? "source_dataset_id" : "source_sample_id"}]]
    set axes [dict get $lineage source_axes]
    set units {};set labels {};set bindings {}
    foreach axis {x y} {
        dict set units $axis [dict get $axes $axis unit]
        dict set labels $axis [dict get $axes $axis display_label]
        dict set bindings $axis [dict get $axes $axis variable_id]
    }
    set sourceSha [::GX::datasetPublicationV2DictDefault $lineage source_sha256 ""]
    set filters [::GX::datasetPublicationV2DictDefault $lineage source_filters {}]
    set points [dict get $result fitted]
    set xs [lmap point $points {lindex $point 0}]
    set ys [lmap point $points {lindex $point 1}]
    set provenance "Dataset Curve Fit; source $sourceIdentity ([dict get $bindings x], [dict get $bindings y]); model [dict get $result model]; scope [dict get $result scope]"
    set definition [dict create dataset_id $datasetId contract table.generic storage auto expected_rows [dict get $result output_n] estimated_numeric_bytes [expr {16*[dict get $result output_n]}] producer_version $version source "Dataset Curve Fit" provenance $provenance notes $name source_dataset_ids [expr {$sourceKind eq "dataset" ? [list $sourceIdentity] : {}}] source_variable_ids [expr {$sourceKind eq "dataset" ? [list [dict get $bindings x] [dict get $bindings y]] : {}}]]
    _validateStatisticsMetadata $result
    _requireConvergedNativeFit $result
    set hasPrediction [dict exists $result statistical_results prediction]
    if {$hasPrediction} {dict set definition estimated_numeric_bytes [expr {80*[dict get $result output_n]}]}
    set outputDomain [_outputDomainInfo $result];set hasOutputDomain [expr {$outputDomain ne {}}]
    if {$hasOutputDomain} {dict set definition estimated_numeric_bytes [expr {[dict get $definition estimated_numeric_bytes]+16*[dict get $result output_n]}]}
    set fitMetadata [dict create dataset.display_name $name curve_fit.producer viewer.dataset_curve_fit curve_fit.source_kind $sourceKind curve_fit.source_sha256 $sourceSha curve_fit.source_x_variable_id [dict get $bindings x] curve_fit.source_y_variable_id [dict get $bindings y] curve_fit.source_x_name [dict get $labels x] curve_fit.source_y_name [dict get $labels y] curve_fit.filters $filters curve_fit.model [dict get $result model] curve_fit.parameters [dict get $result parameters] curve_fit.scope [dict get $result scope] curve_fit.domain [dict get $result domain] curve_fit.grid_kind [dict get $result grid_kind] curve_fit.output_n [dict get $result output_n] curve_fit.selected_indices [dict get $result selected_indices] curve_fit.train_n [dict get $result train_n] curve_fit.train_rmse [dict get $result train_rmse] curve_fit.train_r2 [dict get $result train_r2] curve_fit.source_rmse [dict get $result source_rmse] curve_fit.source_r2 [dict get $result source_r2]]
    if {[dict exists $result model_state_json]} {dict set fitMetadata curve_fit.model_state_json [dict get $result model_state_json]}
    dict set fitMetadata curve_fit.parametric [dict get $result parametric]
    foreach field {knot_binding_sha256 rational_state_sha256 complex_binding complex_conversion complex_model_state complex_model_state_sha256 complex_training_observations_resource complex_source_observations_resource complex_training_covariance_resource complex_source_covariance_resource covariance_binding covariance_resource accepted_name export_domain training_domain training_domain_basis output_domain output_domain_resource recipe_producers template_binding statistical_results statistical_aliases observation_binding comparison_rows_resource profile_values_resource profile_parameters_resource profile_status_resource profile_messages_resource bootstrap_parameters_resource bootstrap_status_resource bootstrap_seed_resource influence_resource influence_input_rows_resource influence_source_rows_resource model_selection region_selection region_membership_resource measurement_binding measurement_selection measurement_resource measurement_rows_resource training_rows_resource orthogonal_resource prediction_resource prediction_lower_resource prediction_upper_resource prediction_gap_resource prediction_plan prediction_display_note numeric_model_state numeric_model_state_sha256 registered_model_state registered_model_state_sha256 registered_source_resource registered_execution translation physical_formula orientation metric_unit coordinate_mode independent_axis polar_frame angular_min angular_max angle_unit unwrap_policy topology parameterization parameter_variable_descriptor model_state_resource model_state_storage model_state_bytes parameters_storage parameter_count degree options residual_convention r2_convention zero_normal_sign_policy train_geometric_rmse source_geometric_rmse train_geometric_dispersion_score source_geometric_dispersion_score train_max_geometric_distance source_max_geometric_distance residual_stride residual_columns selection_descriptor} {
        if {[dict exists $result $field]} {dict set fitMetadata curve_fit.$field [dict get $result $field]}
    }
    dict for {field value} $lineage {dict set fitMetadata curve_fit.$field $value}
    set preprocessing [_preprocessingInfo $result]
    dict set fitMetadata curve_fit.preprocessing $preprocessing
    if {[dict get $preprocessing status] eq "value"} {
        foreach field [concat {model_input_policy} [dict values [dict get $preprocessing stages]]] {
            dict set fitMetadata curve_fit.$field [dict get $result $field]
        }
    }
    if {$hasOutputDomain} {
        dict set fitMetadata curve_fit.output_domain $outputDomain
        dict set fitMetadata curve_fit.output_domain_columns {fit_query is_extrapolated}
        dict unset fitMetadata curve_fit.output_domain_values
    } else {dict set fitMetadata curve_fit.output_domain_status unavailable_historical_receipt}
    if {$hasPrediction} {
        dict set fitMetadata curve_fit.prediction_columns {prediction_query query prediction_mean predicted prediction_lower lower prediction_upper upper prediction_mean_se mean_standard_error prediction_se standard_error prediction_noise_sd observation_standard_deviation prediction_available bounds_available}
        dict set fitMetadata curve_fit.prediction_coordinates [dict create space original_physical orientation [dict get $result orientation] query_offset [dict get $result translation u delta] response_offset [dict get $result translation v delta] inverse {physical = fit_coordinate - offset}]
        foreach field {prediction_plan prediction_display_note} {dict set fitMetadata curve_fit.$field [dict get $result $field]}
    }
    if {$sourceKind in {sample builtin_sample}} {set fitMetadata [dict merge $fitMetadata [_sampleMetadata $sourceIdentity curve_fit.sample]]}
    dict set definition structured_metadata $fitMetadata
    set plan [::GX::datasetPublicationV2Prepare $session viewer.dataset_curve_fit $definition]
    set writer "";set predictionReader "";set outputReader ""
    if {[catch {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach axis {x y} {
            set id "fitted_$axis"
            set derivedAxis [expr {[::GX::datasetPublicationV2DictDefault $result orientation y_of_x] eq "x_of_y" ? "x" : "y"}]
            set role [expr {$axis ne $derivedAxis||[::GX::datasetPublicationV2DictDefault $result parametric 0]||[::GX::datasetPublicationV2DictDefault $result orientation y_of_x] eq "r_of_theta" ? "coordinate" : "data"}]
            set spec [dict create name $id display_label [expr {$axis ne $derivedAxis ? [dict get $labels $axis] : "Fitted [dict get $labels $axis]"}] unit [dict get $units $axis] semantic_role $role dtype float64 rank 1 dimension_ids row coordinate_role $role axis_kind explicit]
            ::GX::datasetPublicationV2DeclareVariable $writer $id $spec
        }
        if {$hasOutputDomain} {
            set queryUnit [expr {[dict get $result parametric]?"1":[dict get $result translation u unit]}]
            ::GX::datasetPublicationV2DeclareVariable $writer fit_query [dict create name fit_query display_label {Original model query coordinate} unit $queryUnit dtype float64 rank 1 dimension_ids row coordinate_role data axis_kind explicit]
            ::GX::datasetPublicationV2DeclareVariable $writer is_extrapolated [dict create name is_extrapolated display_label {Outside retained training envelope} unit 1 dtype uint8 rank 1 dimension_ids row coordinate_role data axis_kind explicit]
            if {[dict exists $result output_domain_resource]} {set outputReader [::GX::interactiveDocumentResourceOpenReader [dict get $result output_domain_resource]]}
        }
        if {$hasPrediction} {
            set predictionReader [::GX::interactiveDocumentResourceOpenReader [dict get $result prediction_resource]]
            set contracts [dict get [::GX::StatisticsV1::numericDataFields [dict get $result statistical_results prediction]] fields]
            foreach {id field} [dict get $fitMetadata curve_fit.prediction_columns] {
                if {$field eq "query"} {
                    set unit [dict get $result translation u unit];set label {Original response-query coordinate}
                } else {set unit [dict get $contracts $field unit];set label [dict get $contracts $field label]}
                set spec [dict create name $id display_label $label unit $unit semantic_role data dtype float64 rank 1 dimension_ids row coordinate_role data axis_kind explicit]
                ::GX::datasetPublicationV2DeclareVariable $writer $id $spec
            }
        }
        set appended 0
        if {[dict exists $result fitted_native]} {
            set total [dict get $result output_n]
            set limit [expr {$hasPrediction?8192:65536}]
            for {set start 0} {$start<$total} {incr start $limit} {
                set count [expr {min($limit,$total-$start)}]
                set chunk [::GX::Native2D::core points_page $state($key,scene) [dict get $result fitted_native] $start $count]
                set columns [dict create fitted_x [lmap point $chunk {lindex $point 0}] fitted_y [lmap point $chunk {lindex $point 1}]]
                if {$hasOutputDomain} {set columns [dict merge $columns [_outputDomainNext $result $outputReader $start $count]]}
                if {$hasPrediction} {set columns [dict merge $columns [_predictionPublicationPage $predictionReader $count]]}
                incr appended [::GX::datasetPublicationV2Append $writer row $columns]
            }
        } else {
            if {$hasPrediction} {error {Prediction columns require exact owned fitted geometry}}
            set columns [dict create fitted_x $xs fitted_y $ys]
            if {$hasOutputDomain} {set columns [dict merge $columns [_outputDomainNext $result $outputReader 0 [llength $xs]]]}
            set appended [::GX::datasetPublicationV2Append $writer row $columns]
        }
        if {$appended != [dict get $result output_n]} {error "Incomplete fit Dataset publication"}
        if {$predictionReader ne {}} {::GX::interactiveDocumentResourceCloseReader $predictionReader;set predictionReader {}}
        if {$outputReader ne {}} {::GX::interactiveDocumentResourceCloseReader $outputReader;set outputReader {}}
        set published [::GX::datasetPublicationV2Finalize $writer]
    } failure options]} {
        if {$predictionReader ne {}} {catch {::GX::interactiveDocumentResourceCloseReader $predictionReader}}
        if {$outputReader ne {}} {catch {::GX::interactiveDocumentResourceCloseReader $outputReader}}
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        return -options $options $failure
    }
    catch {::GX::refreshDatasetInspectionChoices}
    catch {::GX::refreshNativeVariablesGui}
    return $published
}
proc ::GX::DatasetCurveFit::publishSampleDataset {sampleId name} {
    variable version
    set points [samplePoints $sampleId]
    set session $::GX::currentSession
    if {$session eq ""} {error "Open a Session before publishing a sample"}
    set name [string trim $name]
    if {$name eq ""} {error "Sample Dataset needs a name"}
    set datasetId [::GX::datasetPublicationV2RequestedId $name sample]
    set definition [dict create dataset_id $datasetId contract table.generic storage csv producer_version $version source "Dataset Curve Fit built-in sample" provenance "Explicit import of fitter sample $sampleId" notes $name]
    set descriptor [sampleDescriptor $sampleId]
    dict set definition structured_metadata [dict merge [_sampleMetadata $sampleId] [dict create dataset.display_name $name dataset.description [dict get $descriptor description] source_kind builtin_sample source_sample_id $sampleId sample.producer viewer.dataset_curve_fit]]
    set plan [::GX::datasetPublicationV2Prepare $session viewer.dataset_curve_fit $definition]
    set writer ""
    if {[catch {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        dict for {axis spec} [dict get $descriptor axes] {
            set id [dict get $spec variable_id]
            set spec [dict merge $spec [dict create name $id dtype float64 rank 1 dimension_ids row coordinate_role [dict get $spec semantic_role] axis_kind explicit]]
            ::GX::datasetPublicationV2DeclareVariable $writer $id $spec
        }
        ::GX::datasetPublicationV2Append $writer row [dict create sample_x [lmap p $points {lindex $p 0}] sample_y [lmap p $points {lindex $p 1}]]
        set published [::GX::datasetPublicationV2Finalize $writer]
    } failure options]} {
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        return -options $options $failure
    }
    catch {::GX::refreshDatasetInspectionChoices}
    return $published
}
proc ::GX::DatasetCurveFit::_uiPublishSample {w} {
    variable state
    set name [_promptFitName $w "$state($w,sample)_sample"]
    if {$name eq ""} return
    set published [publishSampleDataset $state($w,sample) $name]
    set state($w,status) "Published sample as Dataset [dict get $published dataset_id]."
}
proc ::GX::DatasetCurveFit::_uiClear {w} {
    variable state
    if {$state($w,source) eq ""} return
    clearSelection $w
    set state($w,rects) {}
    _invalidateSelectionPreview $w
    set state($w,status) "CORE fit-point selection cleared."
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiExport {w} {
    variable state
    set index [lindex [$w.left.viewport.content.accepted.list curselection] 0]
    set id [expr {$index eq "" ? $state($w,accepted) : [dict get [lindex $state($w,records) $index] fit_curve_id]}]
    set path [::GX::workspaceSaveFile export_dir -parent $w -defaultextension .csv -filetypes {{{CSV files} {.csv}} {{All files} {*}}}]
    if {$path eq ""} return
    set count [exportCsv $w $path $id]
    set state($w,status) "Exported $count accepted fit points to $path"
}
proc ::GX::DatasetCurveFit::_refreshFits {w} {
    variable state
    if {![winfo exists $w.left.viewport.content.accepted.list]} return
    $w.left.viewport.content.accepted.list delete 0 end
    set index 0
    foreach record $state($w,records) {
        $w.left.viewport.content.accepted.list insert end "[expr {[dict get $record visible] ? "●" : "○"}] [dict get $record label]"
        $w.left.viewport.content.accepted.list itemconfigure $index -foreground [_rgbHex [dict get $record color]]
        incr index
    }
}
proc ::GX::DatasetCurveFit::_uiFitAction {w action} {
    variable state
    set index [lindex [$w.left.viewport.content.accepted.list curselection] 0]
    if {$index eq ""} {error "Select an accepted fit first"}
    set record [lindex $state($w,records) $index]
    set id [dict get $record id]
    switch -- $action {
        visibility {setFitVisible $w $id [expr {![dict get $record visible]}]}
        delete {deleteFit $w $id}
        default {error "Unknown fit action"}
    }
    if {$action eq "delete" && $state($w,previewFitId) eq $id} {
        set state($w,preview) {};set state($w,previewAccepted) 0;set state($w,previewFitId) ""
        set state($w,report) ""
        $w.right.residuals.table delete [$w.right.residuals.table children {}]
    }
    _refreshFits $w
    if {$action eq "visibility"} {$w.left.viewport.content.accepted.list selection set $index}
    $w.actions.export configure -state [expr {[llength $state($w,records)] ? "normal" : "disabled"}]
    set state($w,status) "Updated accepted fit $id."
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiRemoveLastRect {w} {
    variable state
    if {![llength $state($w,rects)]} {error "There is no rectangular selection to remove"}
    set id [lindex $state($w,rects) end]
    ::GX::Native2D::core remove_rect $state($w,selectionScene) $id
    set state($w,rects) [lrange $state($w,rects) 0 end-1]
    _influenceSyncSelection $w add
    _invalidateSelectionPreview $w
    set state($w,status) "Removed the last selection rectangle; [llength [selectedIndices $w]] points remain selected."
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_plotTickTexts {low high count} {
    set values {}
    for {set i 0} {$i<=$count} {incr i} {lappend values [format %.5g [expr {$low+($high-$low)*$i/double($count)}]]}
    return $values
}
proc ::GX::DatasetCurveFit::_plotTickCount {low high pixels vertical} {
    set line [font metrics TkDefaultFont -linespace]
    for {set count 5} {$count>1} {incr count -1} {
        set needed [expr {$line+8}]
        if {!$vertical} {set needed 0;foreach text [_plotTickTexts $low $high $count] {set needed [expr {max($needed,1.5*[font measure TkDefaultFont $text]+12)}]}}
        if {$needed<=$pixels/double($count)} break
    }
    return $count
}
proc ::GX::DatasetCurveFit::_plotFrame {w} {
    variable state
    set width [winfo width $w.right.plot.canvas];set height [winfo height $w.right.plot.canvas]
    set line [font metrics TkDefaultFont -linespace];set digit [font measure TkDefaultFont 0]
    set bounds [expr {[info exists state($w,bounds)]?$state($w,bounds):{-1 1 -1 1}}]
    lassign $bounds xmin xmax ymin ymax
    set xWidth 0;set yWidth 0
    foreach text [_plotTickTexts $xmin $xmax 5] {set xWidth [expr {max($xWidth,[font measure TkDefaultFont $text])}]}
    foreach text [_plotTickTexts $ymin $ymax 5] {set yWidth [expr {max($yWidth,[font measure TkDefaultFont $text])}]}
    set left [expr {max(76,$yWidth+$digit+$line+12)}]
    set right [expr {$width-max(32,int(.5*$xWidth)+$digit+8)}]
    set top [expr {$line+10}];set axisBand [expr {2*$line+12}]
    set required [expr {$top+max(64,2*$line)+$axisBand+2*$line+12+max(50,2*$line)+12}]
    set state($w,residualPlotVisible) [expr {$state($w,showResiduals)&&$state($w,preview) ne {}&&$height>=max(230,$required)}]
    if {$state($w,residualPlotVisible)} {
        set bottom [expr {min($height-($axisBand+2*$line+12+max(50,2*$line)+12),max($top+64,round($height*$state($w,residualFraction))-$axisBand))}]
    } else {set bottom [expr {$height-$axisBand}]}
    set state($w,residualPlotTop) [expr {$bottom+$axisBand+2*$line+12}]
    return [list $left $right $top $bottom]
}
proc ::GX::DatasetCurveFit::_residualPanel {w} {
    variable state
    if {[winfo exists $w.right.residuals]} {_residualPanelLayout $w} elseif {$state($w,showResiduals)} {
        pack $w.right.residuals.table -after $w.footer.status -side bottom -fill x -padx 8
        pack $w.right.residuals.pager -after $w.right.residuals.table -side bottom -fill x -padx 8
    } else {pack forget $w.residuals;pack forget $w.right.residuals.pager}
    redraw $w;_saveState $w
}
proc ::GX::DatasetCurveFit::_residualResize {w value} {
    variable state
    set state($w,residualFraction) [::GX::uiFieldNormalize {type number min .3 max .9} $value]
    redraw $w;_saveState $w
}
proc ::GX::DatasetCurveFit::_residualPageUi {w step} {
    variable state
    if {$state($w,preview) eq {}} {error "Preview a fit to read exact residual pages"}
    set report $state($w,preview)
    set start [expr {max(0,min([dict get $report source_n]-200,$state($w,residualStart)+$step))}]
    set page [_residualRowsPage $w $start 200]
    _residualColumns $w $report
    $w.right.residuals.table delete [$w.right.residuals.table children {}]
    set index $start
    foreach row [dict get $page rows] id [dict get $page source_rows] {
        $w.right.residuals.table insert {} end -id residual_$index -values [list $id {*}[lmap v $row {format %.9g $v}]]
        incr index
    }
    set state($w,residualStart) $start
    set state($w,residualStatus) "Exact residual rows [expr {$start+1}]–[expr {$start+[llength [dict get $page rows]]}] / [dict get $page row_count]"
}
proc ::GX::DatasetCurveFit::_screen {w x y} {
    variable state
    return [::GX::Native2D::core device $state($w,scene) [list $x $y]]
}
proc ::GX::DatasetCurveFit::_world {w px py} {
    variable state
    return [::GX::Native2D::core world $state($w,scene) [list $px $py]]
}
proc ::GX::DatasetCurveFit::_hitTolerance {w} {
    variable state
    lassign [::GX::Native2D::core tolerance $state($w,scene) 8] tx ty
    return [expr {max($tx,$ty)}]
}
proc ::GX::DatasetCurveFit::_viewSettings {w} {
    variable state
    ::GX::native2DGridForm $w.grid $state($w,scene) [list ::GX::DatasetCurveFit::_viewChanged $w] $w
}
proc ::GX::DatasetCurveFit::_viewChanged {w} {redraw $w;_saveState $w}
proc ::GX::DatasetCurveFit::_coordinates {w x y} {
    variable state
    if {![info exists state($w,source)]} return
    if {$state($w,source) eq ""} return
    set state($w,coordinates) [::GX::native2DCoordinateReadout $state($w,scene) [list $x $y]]
}
proc ::GX::DatasetCurveFit::_rgbHex {color} {
    lassign $color r g b
    return [format #%02x%02x%02x [expr {round($r*255)}] [expr {round($g*255)}] [expr {round($b*255)}]]
}
proc ::GX::DatasetCurveFit::_axisLabel {w variable} {
    variable state
    if {$state($w,source) eq ""&&$state($w,records) ne {}} {
        set descriptor [dict get [lindex $state($w,records) 0] provenance source_axes $variable]
        set label [dict get $descriptor display_label]
        if {[dict get $descriptor unit] ne ""} {append label " ([dict get $descriptor unit])"}
        return $label
    }
    if {[info exists state($w,sourceKind)]&&$state($w,sourceKind) in {builtin_sample sample}} {
        set descriptor [dict get [sampleDescriptor [lindex $state($w,loadedBinding) 0]] axes $variable]
        return "[dict get $descriptor display_label] ([dict get $descriptor unit])"
    }
    if {[llength $state($w,loadedBinding)]==4} {
        lassign $state($w,loadedBinding) dataset x y filters
        set id [set $variable]
        if {![catch {set schema [variables $dataset]}]&&[dict exists $schema labels $id]} {return [dict get $schema labels $id]}
        return $id
    }
    return [string toupper $variable]
}
proc ::GX::DatasetCurveFit::redraw {w} {
    variable state
    if {![winfo exists $w.right.plot.canvas]} return
    set c $w.right.plot.canvas
    # Restore may run before Tk maps this canvas. Its Configure event performs
    # the first render once a valid native viewport is available.
    if {[winfo width $c]<120 || [winfo height $c]<160} {$c delete all;return}
    $c delete all
    if {$state($w,source) eq ""&&$state($w,records) eq {}} {
        $c create text 30 30 -anchor nw -text "Load a Dataset curve to begin." -fill #475569
        return
    }
    set hasSource [expr {$state($w,source) ne ""}]
    set points [expr {$hasSource ? [sourcePoints $w] : {}}]
    set sourceShown [expr {$hasSource ? [dict get $state($w,sources) $state($w,activeSource) visible] : 0}]
    set previewPoints [expr {$state($w,preview) eq {} ? {} : [dict get $state($w,preview) fitted]}]
    set manualPoints {}
    if {[info exists state($w,manualPoints)]} {
        if {[catch {_parameterFingerprint $w} current]||$current ne $state($w,parameterFingerprint)} {_parameterClear $w} else {set manualPoints $state($w,manualPoints)}
    }
    set queryDisplay [_queryDisplay $w];set queryPoints {}
    if {$queryDisplay ne {}} {set queryPoints [dict get $queryDisplay points]}
    set shown 0
    dict for {id entry} $state($w,sources) {if {[dict get $entry visible]} {set shown 1;break}}
    foreach record $state($w,records) {if {[dict get $record visible]} {set shown 1;break}}
    if {$shown} {set bounds [::GX::Native2D::core scene_bounds $state($w,scene)]} elseif {$state($w,viewBounds) ne {}} {
        lassign $state($w,viewBounds) bx0 bx1 by0 by1;set bounds [list $bx0 $by0 $bx1 $by1]
    } else {set bounds {-1 -1 1 1}}
    lassign $bounds xmin ymin xmax ymax
    foreach point [concat $previewPoints $manualPoints $queryPoints] {
        lassign $point x y
        set xmin [expr {min($xmin,$x)}];set xmax [expr {max($xmax,$x)}]
        set ymin [expr {min($ymin,$y)}];set ymax [expr {max($ymax,$y)}]
    }
    if {$state($w,preview) ne {}&&!$state($w,previewAccepted)} {
        foreach field {prediction_lower_native prediction_upper_native} {
            if {![dict exists $state($w,preview) $field]} continue
            lassign [::GX::Native2D::core bounds $state($w,scene) [dict get $state($w,preview) $field]] x0 y0 x1 y1
            set xmin [expr {min($xmin,$x0)}];set xmax [expr {max($xmax,$x1)}];set ymin [expr {min($ymin,$y0)}];set ymax [expr {max($ymax,$y1)}]
        }
    }
    if {$xmin == $xmax} {set xmin [expr {$xmin-1}];set xmax [expr {$xmax+1}]}
    if {$ymin == $ymax} {set ymin [expr {$ymin-1}];set ymax [expr {$ymax+1}]}
    set padx [expr {0.04*($xmax-$xmin)}];set pady [expr {0.08*($ymax-$ymin)}]
    set state($w,fullBounds) [list [expr {$xmin-$padx}] [expr {$xmax+$padx}] [expr {$ymin-$pady}] [expr {$ymax+$pady}]]
    set state($w,bounds) [expr {$state($w,viewBounds) eq {} ? $state($w,fullBounds) : $state($w,viewBounds)}]
    lassign $state($w,bounds) xmin xmax ymin ymax
    lassign [_plotFrame $w] left right top bottom
    set height [winfo height $c];set width [winfo width $c]
    ::GX::Native2D::core view $state($w,scene) [list $width $height $left $top [expr {$width-$right}] [expr {$height-$bottom}] [list $xmin $ymin $xmax $ymax]]
    set effective [lindex [::GX::Native2D::core view $state($w,scene)] 6]
    lassign $effective xmin ymin xmax ymax
    set state($w,bounds) [list $xmin $xmax $ymin $ymax]
    set background [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA [::GX::Native2D::core background $state($w,scene)]] #FFFFFF]
    $c configure -background [dict get $background rgb]
    ::GX::native2DCanvasGrid $state($w,scene) $c
    set line [font metrics TkDefaultFont -linespace]
    set xCount [_plotTickCount $xmin $xmax [expr {$right-$left}] 0]
    set yCount [_plotTickCount $ymin $ymax [expr {$bottom-$top}] 1]
    set i 0;foreach label [_plotTickTexts $xmin $xmax $xCount] {
        set tx [expr {$left+($right-$left)*$i/double($xCount)}]
        set anchor [expr {$i==0?"nw":($i==$xCount?"ne":"n")}];incr i
        $c create text $tx [expr {$bottom+4}] -anchor $anchor -text $label -fill #475569 -tags {axis_label x_tick}
    }
    set i 0;foreach label [_plotTickTexts $ymin $ymax $yCount] {
        set ty [expr {$bottom-($bottom-$top)*$i/double($yCount)}];incr i
        $c create text [expr {$left-7}] $ty -anchor e -text $label -fill #475569 -tags {axis_label y_tick}
    }
    $c create rectangle $left $top $right $bottom -outline #8796a8
    $c create text [expr {($left+$right)/2.0}] [expr {$bottom+$line+8}] -anchor n -text [_axisLabel $w x] -width [expr {$right-$left}] -fill #172a40 -tags {axis_label x_axis_title}
    $c create text [expr {$line/2.0+4}] [expr {($top+$bottom)/2.0}] -text [_axisLabel $w y] -angle 90 -fill #172a40 -tags {axis_label y_axis_title}
    dict for {sourceId entry} $state($w,sources) {
        if {![dict get $entry visible]||[dict get $entry state source] eq ""} continue
        set object [::GX::native2DPresentationObjectSnapshot $state($w,scene) [dict get $entry state source] 4096]
        set tags [expr {$sourceId eq $state($w,activeSource) ? "active_source" : "source_curve"}]
        ::GX::native2DCanvasDrawObject $c $object $background $tags
    }
    foreach record $state($w,records) {
        if {![dict get $record visible]} continue
        set object [::GX::native2DPresentationObjectSnapshot $state($w,scene) [dict get $record id] 4096]
        _outputDomainDraw $c $object [::GX::datasetPublicationV2DictDefault $record provenance {}] $background accepted_curve
        _predictionDraw $state($w,scene) $c $record $background accepted_prediction
    }
    if {[llength $previewPoints] >= 2 && !$state($w,previewAccepted)} {
        _predictionDraw $state($w,scene) $c $state($w,preview) $background preview_prediction
        _outputDomainPreviewDraw $w $c $state($w,preview) $background
    }
    if {[llength $manualPoints]>=2} {
        set coords {};foreach point $manualPoints {lassign $point x y;lappend coords {*}[_screen $w $x $y]}
        $c create line {*}$coords -fill #a855f7 -width 2 -dash {3 3} -tags manual_parameter_curve
    }
    if {$queryDisplay ne {}} {_queryDraw $w $c $queryDisplay}
    set sourceColor [expr {$hasSource ? [dict get [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA [dict get [::GX::Native2D::core object_style $state($w,scene) $state($w,source)] color]] $background] rgb] : "#2764C7"}]
    set selected [expr {$hasSource ? [selectedIndices $w] : {}}];set index 0
    foreach point [expr {$sourceShown ? $points : {}}] {
        lassign $point x y;lassign [_screen $w $x $y] px py
        set color [expr {$index in $selected ? "#e11d48" : $sourceColor}]
        set radius [expr {$index in $selected ? 5 : 3}]
        $c create oval [expr {$px-$radius}] [expr {$py-$radius}] [expr {$px+$radius}] [expr {$py+$radius}] -fill $color -outline white -tags source_point
        incr index
    }
    if {$sourceShown} {_influenceDrawLink $w}
    ::GX::native2DCanvasViewportClip $c $state($w,scene)
    $c create text $left 2 -anchor nw -text {Curves and fits} -width [expr {$right-$left}] -fill #334155 -tags plot_legend
    _drawResidualPanel $w $left $right $height $line

}
proc ::GX::DatasetCurveFit::_mouseDown {w x y stateBits} {
    variable state
    # Commit the focused parameter before starting a guarded gesture. Tk queues
    # FocusOut after this handler; starting the gesture first would reject the
    # pending field commit as an operation in progress.
    if {![_commitFocusedSetting $w]} return
    focus $w.right.plot.canvas
    if {![_historyEditable $w]} return
    if {[info exists state($w,loading)]&&$state($w,loading)} return
    if {[catch {_assertLoaded $w}]} return
    if {[_residualPick $w $x $y]} return
    if {[catch {::GX::scientificHistoryViewerPrepareEdit $w} accepted] || !$accepted} return
    set state($w,press) [list $x $y $stateBits]
}
proc ::GX::DatasetCurveFit::_mouseMove {w x y} {
    variable state
    if {![info exists state($w,press)]} return
    lassign $state($w,press) x0 y0 bits
    $w.right.plot.canvas delete selection_drag
    if {hypot($x-$x0,$y-$y0) > 5} {
        $w.right.plot.canvas create rectangle [expr {min($x0,$x)}] [expr {min($y0,$y)}] [expr {max($x0,$x)}] [expr {max($y0,$y)}] -outline #e87913 -width 2 -dash {5 3} -tags selection_drag
        ::GX::native2DCanvasClipItems $w.right.plot.canvas $state($w,scene) [$w.right.plot.canvas find withtag selection_drag]
    }
}
proc ::GX::DatasetCurveFit::_mouseUp {w x y stateBits} {
    variable state
    if {$state($w,source) eq "" || ![info exists state($w,press)]} return
    lassign $state($w,press) x0 y0 bits
    unset state($w,press)
    $w.right.plot.canvas delete selection_drag
    if {![dict get $state($w,sources) $state($w,activeSource) visible]} return
    if {[catch {_assertLoaded $w}]} return
    set extended [expr {($bits & 0x0001) || ($bits & 0x0004)}]
    set scene $state($w,selectionScene);set source $state($w,selectionObject)
    if {hypot($x-$x0,$y-$y0) > 5} {
        lassign [_world $w $x0 $y0] wx0 wy0
        lassign [_world $w $x $y] wx1 wy1
        set mode [string tolower $state($w,rectMode)]
        if {$extended} {set mode add}
        if {$bits & 0x0008} {set mode subtract}
        set id [::GX::Native2D::core rect $scene [list [expr {min($wx0,$wx1)}] [expr {min($wy0,$wy1)}] [expr {max($wx0,$wx1)}] [expr {max($wy0,$wy1)}]] $mode]
        if {$mode eq "replace"} {set state($w,rects) {}}
        lappend state($w,rects) $id
        _influenceSyncSelection $w $mode
    } else {
        set world [_world $w $x $y]
        set tolerance [_hitTolerance $w]
        set hit [::GX::Native2D::core nearest $scene $world $tolerance]
        if {$hit eq {} || [dict get $hit object] != $source} {set hit [::GX::Native2D::core hit $scene $source $world $tolerance]}
        if {$hit ne {}} {
            lassign [_screen $w {*}[dict get $hit point]] hx hy
            if {hypot($hx-$x,$hy-$y) > 8} {set hit {}}
        }
        if {$hit ne {}} {
            set index [dict get $hit index]
            set mode replace
            if {$extended} {set mode [expr {$index in [selectedIndices $w] ? "subtract" : "add"}]}
            selectPoint $w $index $mode
            _residualFocusSource $w $index
            if {$mode eq "replace"} {set state($w,rects) {}}
        } elseif {!$extended} {clearSelection $w;set state($w,rects) {}}
    }
    _invalidateSelectionPreview $w
    set state($w,status) "[llength [selectedIndices $w]] CORE points selected for fitting."
    _historyGestureSave $w {Select fitting points}
    redraw $w
}
proc ::GX::DatasetCurveFit::_historyGestureSave {w description} {
    variable state
    set state($w,historyDescription) $description
    try {_saveState $w} finally {unset -nocomplain state($w,historyDescription)}
}
proc ::GX::DatasetCurveFit::_rememberNativeView {w} {
    variable state
    lassign [lindex [::GX::Native2D::core view_requested $state($w,scene)] 6] xmin ymin xmax ymax
    set state($w,viewBounds) [list $xmin $xmax $ymin $ymax]
}
proc ::GX::DatasetCurveFit::_zoom {w factor {px ""} {py ""}} {
    variable state
    if {![_historyEditable $w]} return
    if {![_commitFocusedSetting $w]} return
    if {$state($w,source) eq ""&&$state($w,records) eq {}} return
    if {[catch {::GX::scientificHistoryViewerPrepareEdit $w} accepted] || !$accepted} return
    if {$px eq ""} {lassign [_plotFrame $w] left right top bottom;set px [expr {($left+$right)/2.0}];set py [expr {($top+$bottom)/2.0}]}
    ::GX::Native2D::core zoom $state($w,scene) $factor [list $px $py]
    _rememberNativeView $w
    redraw $w
    _historyGestureSave $w {Zoom chart view}
}
proc ::GX::DatasetCurveFit::_panDown {w x y} {
    variable state
    if {![_historyEditable $w]} return
    if {![_commitFocusedSetting $w]} return
    if {[catch {::GX::scientificHistoryViewerPrepareEdit $w} accepted] || !$accepted} return
    if {$state($w,source) ne ""||$state($w,records) ne {}} {set state($w,pan) [list $x $y]}
}
proc ::GX::DatasetCurveFit::_panMove {w x y} {
    variable state
    if {![info exists state($w,pan)]} return
    lassign $state($w,pan) x0 y0
    ::GX::Native2D::core pan $state($w,scene) [expr {$x-$x0}] [expr {$y-$y0}]
    set state($w,pan) [list $x $y]
    _rememberNativeView $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_panUp {w} {
    variable state
    if {![info exists state($w,pan)]} return
    unset state($w,pan)
    _historyGestureSave $w {Pan chart view}
}
proc ::GX::DatasetCurveFit::_resetView {w} {
    variable state
    if {![_historyEditable $w]} return
    if {![_commitFocusedSetting $w]} return
    if {[catch {::GX::scientificHistoryViewerPrepareEdit $w} accepted] || !$accepted} return
    set state($w,viewBounds) {}
    _historyGestureSave $w {Fit chart view}
    redraw $w
}
proc ::GX::DatasetCurveFit::_wheel {w delta x y} {
    if {$delta > 0} {_zoom $w 0.85 $x $y} elseif {$delta < 0} {_zoom $w 1.18 $x $y}
}
proc ::GX::DatasetCurveFit::_closeWindow {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {set state($w,closeRequested) 1;_sourceCancel $w;return}
    # A stale Viewer cannot write or collect resources in another Session.
    # Its already persisted Workspace remains with its original owner; release
    # only this window's live handles when closing after a Session switch.
    if {![catch {_assertSession $w}]} {
        if {[catch {
            _saveState $w
            if {$state($w,documentId) ne ""} {::GX::interactiveDocumentResourceCollect $state($w,documentId)}
        } err]} {
            tk_messageBox -parent $w -icon error -type ok -title "Dataset Curve Fit" -message "Could not save viewer state: $err"
            return
        }
    }
    close $w
    destroy $w
}
proc ::GX::DatasetCurveFit::open {{context {}}} {
    variable state
    package require Tk
    set w .dataset_curve_fit
    set requestedDataset ""
    foreach field {dataset_id source_dataset_id} {
        if {[dict exists $context $field] && [dict get $context $field] ne ""} {
            set requestedDataset [dict get $context $field]
        }
    }
    set requestedWorkspace [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {$requestedWorkspace ni {{} new}} {
        set workspace [::GX::sessionWorkspaceGet $requestedWorkspace]
        if {[dict get $workspace provider_id] ne "dataset_curve_fit"} {error {Workspace belongs to another Viewer}}
        ::GX::sessionWorkspaceValidate $requestedWorkspace
    }
    if {[winfo exists $w] && $requestedWorkspace ne {} && $requestedWorkspace ne $state($w,documentId)} {
        if {[info exists state($w,loading)] && $state($w,loading)} {error {Cancel the active source operation before switching Workspaces}}
        _closeWindow $w
        if {[winfo exists $w]} {error {Workspace could not close safely}}
    }
    if {[winfo exists $w]} {
        if {$requestedDataset ne "" &&
            ($requestedDataset ne $state($w,dataset) ||
             $requestedDataset ne [lindex $state($w,loadedBinding) 0] ||
             ($state($w,documentId) ne "" &&
              ![_documentMatchesDataset $state($w,documentId) $requestedDataset]))} {
            set state($w,dataset) $requestedDataset
            _uiSafe $w [list ::GX::DatasetCurveFit::_uiDataset $w]
        }
        raise $w;return $w
    }
    set key [new]
    foreach name [array names state "$key,*"] {set field [string range $name [expr {[string length $key]+1}] end];set state($w,$field) $state($name);unset state($name)}
    foreach {field value} {dataset "" sample circular_arc x "" y "" filterVar "" displayX "" displayY "" displayFilterVar "" showIds 0 filterOp = filterValue "" model linear degree 2 initial "" period "" smoothing 0.01 topology auto parameterization row_order parameterVariable "" userPeriod "" closureTolerance "" orientation y_of_x orientationLabel {Y = f(X)} scope all domain source min "" max "" samples 201 rectMode Replace report "" status "Choose a Dataset."} {set state($w,$field) $value}
    set state($w,openingWorkspace) $requestedWorkspace
    set state($w,workspaceName) [::GX::datasetPublicationV2DictDefault $context workspace_name {}]
    if {$requestedDataset ne ""} {set state($w,dataset) $requestedDataset}
    if {![catch {set token [::GX::interactiveDocumentSessionToken]}]} {set state($w,sessionToken) $token}
    toplevel $w;wm title $w "Dataset Curve Fit"
    _layoutPrepare $w
    ::GX::uiFieldWindowFit $w 1420 980
    wm protocol $w WM_DELETE_WINDOW [list ::GX::DatasetCurveFit::_closeWindow $w]
    bind $w <Escape> [list ::GX::DatasetCurveFit::_sourceCancel $w]
    ttk::frame $w.left.viewport.content.source.body -padding 5;pack $w.left.viewport.content.source.body -fill x
    foreach {field label width} {dataset Dataset 24 x X 18 y Y 18} {
        ttk::label $w.left.viewport.content.source.body.l_$field -text $label
        if {$field eq "dataset"} {set variable dataset} else {set variable "display[string toupper $field]"}
        ttk::combobox $w.left.viewport.content.source.body.$field -textvariable ::GX::DatasetCurveFit::state($w,$variable) -state readonly -width $width
        pack $w.left.viewport.content.source.body.l_$field $w.left.viewport.content.source.body.$field -side left -padx 4
    }
    ::GX::datasetSelectorAttach $w.left.viewport.content.source.body.dataset ::GX::DatasetCurveFit::datasets
    if {$state($w,dataset) ni [datasets]} {set state($w,dataset) [lindex [datasets] 0]}
    bind $w.left.viewport.content.source.body.dataset <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiDataset $w]]
    foreach field {x y} {bind $w.left.viewport.content.source.body.$field <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSelectVariable $w $field]}
    ttk::frame $w.left.viewport.content.samples.body -padding 5;pack $w.left.viewport.content.samples.body -fill x
    ttk::label $w.left.viewport.content.samples.body.label -text "Built-in / Test sample"
    ttk::combobox $w.left.viewport.content.samples.body.choice -textvariable ::GX::DatasetCurveFit::state($w,sample) -values [dict keys [sampleCatalog]] -state readonly -width 24
    ttk::button $w.left.viewport.content.samples.body.load -text "Open sample in fitter" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiLoadSample $w]]
    ttk::button $w.left.viewport.content.samples.body.publish -text "Publish sample as Dataset..." -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPublishSample $w]]
    pack $w.left.viewport.content.samples.body.label $w.left.viewport.content.samples.body.choice $w.left.viewport.content.samples.body.load $w.left.viewport.content.samples.body.publish -side left -padx 4
    ttk::checkbutton $w.left.viewport.content.source.body.ids -text "Show variable IDs" -variable ::GX::DatasetCurveFit::state($w,showIds) -command [list ::GX::DatasetCurveFit::_uiVariableChoices $w]
    pack $w.left.viewport.content.source.body.ids -side left -padx 4
    ttk::frame $w.left.viewport.content.filters.controls -padding 5;pack $w.left.viewport.content.filters.controls -fill x
    ttk::label $w.left.viewport.content.filters.controls.title -text "Filters (all conditions must match)"
    ttk::combobox $w.left.viewport.content.filters.controls.variable -textvariable ::GX::DatasetCurveFit::state($w,displayFilterVar) -state readonly -width 20
    ttk::combobox $w.left.viewport.content.filters.controls.operator -textvariable ::GX::DatasetCurveFit::state($w,filterOp) -state readonly -width 10
    ttk::entry $w.left.viewport.content.filters.controls.value -textvariable ::GX::DatasetCurveFit::state($w,filterValue) -width 27
    ttk::button $w.left.viewport.content.filters.controls.add -text "Add filter" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiAddFilter $w]]
    ttk::button $w.left.viewport.content.filters.controls.remove -text "Remove selected" -command [list ::GX::DatasetCurveFit::_uiRemoveFilter $w]
    ttk::button $w.left.viewport.content.filters.controls.load -text "Add Dataset curve" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiLoad $w]]
    ttk::button $w.left.viewport.content.filters.controls.cancel -text "Cancel operation" -state disabled -command [list ::GX::DatasetCurveFit::_sourceCancel $w]
    foreach item {title variable operator value add remove load cancel} {pack $w.left.viewport.content.filters.controls.$item -side left -padx 3}
    bind $w.left.viewport.content.filters.controls.variable <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSelectVariable $w filterVar]
    listbox $w.left.viewport.content.filters.list -height 1 -exportselection 0;pack $w.left.viewport.content.filters.list -fill x -padx 8
    ttk::frame $w.left.viewport.content.settings.body -padding 5;pack $w.left.viewport.content.settings.body -fill x
    ttk::label $w.left.viewport.content.settings.body.l_orientation -text "Fit orientation"
    ttk::combobox $w.left.viewport.content.settings.body.orientation -textvariable ::GX::DatasetCurveFit::state($w,orientationLabel) -state readonly -values {{Y = f(X)} {X = f(Y)} {R = f(theta) (experimental)}} -width 26
    pack $w.left.viewport.content.settings.body.l_orientation $w.left.viewport.content.settings.body.orientation -side left -padx 4
    bind $w.left.viewport.content.settings.body.orientation <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiBoundSetting $w orientationLabel]
    foreach {field label values width} {model Model {linear polynomial exponential power_law gaussian components regions formula rational implicit complex_response registered circular_arc quadratic_bezier cubic_bezier pchip smoothing_spline akima bspline fourier parametric_polynomial parametric_spline} 19 scope {Fit points} {all selected} 10 domain {Output domain} {source range} 12} {
        ttk::label $w.left.viewport.content.settings.body.l_$field -text $label
        ttk::combobox $w.left.viewport.content.settings.body.$field -textvariable ::GX::DatasetCurveFit::state($w,$field) -values $values -state readonly -width $width
        pack $w.left.viewport.content.settings.body.l_$field $w.left.viewport.content.settings.body.$field -side left -padx 3
    }
    foreach field {model scope domain} {
        bind $w.left.viewport.content.settings.body.$field <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiBoundSetting $w $field]
    }
    ttk::button $w.left.viewport.content.settings.body.parametric -text "Parametric settings…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_parametricSettings $w]]
    pack $w.left.viewport.content.settings.body.parametric -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.polar -text "Radial settings…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_polarSettings $w]]
    pack $w.left.viewport.content.settings.body.polar -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.components -text "Model components…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_componentSettings $w]]
    pack $w.left.viewport.content.settings.body.components -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.regions -text "Joint regions…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_regionSettings $w]]
    pack $w.left.viewport.content.settings.body.regions -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.knots -text "Knots / boundaries…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_knotSettings $w]]
    ttk::button $w.left.viewport.content.settings.body.rational -text "Rational / Padé…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_rationalSettings $w]]
    pack $w.left.viewport.content.settings.body.rational -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.formula -text "Safe formula…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_formulaSettings $w]]
    pack $w.left.viewport.content.settings.body.formula -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.implicit -text "Implicit equation…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_implicitSettings $w]]
    pack $w.left.viewport.content.settings.body.implicit -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.complex_response -text "Complex responses…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_complexSettings $w]]
    pack $w.left.viewport.content.settings.body.complex_response -side left -padx 4
    ttk::button $w.left.viewport.content.settings.body.registered -text "Registered model…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_registeredSettings $w]]
    pack $w.left.viewport.content.settings.body.registered -side left -padx 4
    ttk::frame $w.left.viewport.content.settings.parameters -padding 5;pack $w.left.viewport.content.settings.parameters -fill x
    foreach {field label width} {degree Degree 6 initial {Initial parameters} 18 period {Fourier period (blank = auto)} 15 smoothing {Smoothing lambda} 10 min {X / t min} 9 max {X / t max} 9 samples Samples 6} {
        ttk::label $w.left.viewport.content.settings.parameters.l_$field -text $label
        ttk::entry $w.left.viewport.content.settings.parameters.$field -textvariable ::GX::DatasetCurveFit::state($w,$field) -width $width
        foreach event {<Return> <FocusOut>} {bind $w.left.viewport.content.settings.parameters.$field $event [list ::GX::DatasetCurveFit::_uiBoundSetting $w $field]}
        pack $w.left.viewport.content.settings.parameters.l_$field $w.left.viewport.content.settings.parameters.$field -side left -padx 3
    }
    ttk::frame $w.actions -padding 5;pack $w.actions -fill x
    ttk::button $w.actions.clear -text "Clear point selection" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiClear $w]]
    ttk::button $w.actions.preview -text "Preview fit" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPreview $w]]
    ttk::button $w.actions.accept -text "Accept as new CORE curve" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_acceptDialog $w]]
    ttk::button $w.actions.publish -text "Publish as Dataset..." -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPublish $w]]
    ttk::button $w.actions.export -text "Export accepted fit CSV" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiExport $w]]
    foreach item {clear preview accept publish export} {pack $w.actions.$item -side left -padx 4}
    foreach item {preview accept publish export} {$w.actions.$item configure -state disabled}
    ttk::frame $w.left.viewport.content.selection.body -padding 5;pack $w.left.viewport.content.selection.body -fill x
    ttk::label $w.left.viewport.content.selection.body.l_mode -text "Rectangle mode"
    ttk::combobox $w.left.viewport.content.selection.body.mode -textvariable ::GX::DatasetCurveFit::state($w,rectMode) -values {Replace Add Subtract} -state readonly -width 10
    ttk::button $w.left.viewport.content.selection.body.remove -text "Remove last rectangle" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiRemoveLastRect $w]]
    ttk::button $w.left.viewport.content.selection.body.zoomin -text "Zoom in" -command [list ::GX::DatasetCurveFit::_zoom $w 0.7]
    ttk::button $w.left.viewport.content.selection.body.zoomout -text "Zoom out" -command [list ::GX::DatasetCurveFit::_zoom $w 1.4]
    ttk::button $w.left.viewport.content.selection.body.reset -text "Fit view" -command [list ::GX::DatasetCurveFit::_resetView $w]
    ttk::label $w.left.viewport.content.selection.body.help -text "Shift-drag adds; Alt-drag subtracts. Middle-drag pans; wheel zooms."
    foreach item {l_mode mode remove zoomin zoomout reset help} {pack $w.left.viewport.content.selection.body.$item -side left -padx 4}
    ttk::frame $w.left.viewport.content.presentation.body -padding 5;pack $w.left.viewport.content.presentation.body -fill x
    ttk::button $w.left.viewport.content.presentation.body.settings -text "Grid / background / aspect…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_viewSettings $w]]
    pack $w.left.viewport.content.presentation.body.settings -side left -padx 4
    ttk::checkbutton $w.left.viewport.content.presentation.body.residuals -text "Show residual panel" -variable ::GX::DatasetCurveFit::state($w,showResiduals) -command [list ::GX::DatasetCurveFit::_residualPanel $w]
    pack $w.left.viewport.content.presentation.body.residuals -side left -padx 4
    ttk::scale $w.left.viewport.content.presentation.body.split -from .3 -to .9 -orient horizontal -variable ::GX::DatasetCurveFit::state($w,residualFraction) -command [list ::GX::DatasetCurveFit::_residualResize $w]
    pack $w.left.viewport.content.presentation.body.split -side left -padx 4
    ttk::label $w.left.viewport.content.presentation.body.coordinates -textvariable ::GX::DatasetCurveFit::state($w,coordinates)
    pack $w.left.viewport.content.presentation.body.coordinates -side left -padx 8
    ttk::frame $w.left.viewport.content.accepted.actions -padding 5;pack $w.left.viewport.content.accepted.actions -fill x
    ttk::label $w.left.viewport.content.accepted.actions.title -text "Accepted fits"
    listbox $w.left.viewport.content.accepted.list -height 2 -exportselection 0;pack $w.left.viewport.content.accepted.actions.title -side left -padx 4
    ttk::button $w.left.viewport.content.accepted.actions.visibility -text "Show / Hide" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiFitAction $w visibility]]
    ttk::button $w.left.viewport.content.accepted.actions.delete -text "Delete fit" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiFitAction $w delete]]
    ttk::button $w.left.viewport.content.accepted.actions.publish -text "Publish selected fit as Dataset…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPublishAccepted $w]]
    pack $w.left.viewport.content.accepted.actions.visibility $w.left.viewport.content.accepted.actions.delete $w.left.viewport.content.accepted.actions.publish -side left -padx 4
    pack $w.left.viewport.content.accepted.list -fill x -padx 8
    _workspaceGui $w
    canvas $w.right.plot.canvas -background white -height 400;pack $w.right.plot.canvas -fill both -expand 1 -padx 8 -pady 4
    ttk::label $w.right.report.result -textvariable ::GX::DatasetCurveFit::state($w,report) -justify left -wraplength 1240;pack $w.right.report.result -fill x -padx 8
    ttk::treeview $w.right.report.parameters -columns {parameter estimate unit se interval role} -show headings -height 3
    foreach {column heading width} {parameter Parameter 110 estimate Estimate 115 unit Unit 80 se {Standard error} 110 interval {Confidence interval} 200 role Role 65} {
        $w.right.report.parameters heading $column -text $heading
        $w.right.report.parameters column $column -width $width -minwidth 55 -stretch 1
    }
    ttk::scrollbar $w.right.report.parameterScroll -orient horizontal -command [list $w.right.report.parameters xview]
    $w.right.report.parameters configure -xscrollcommand [list $w.right.report.parameterScroll set]
    pack $w.right.report.parameters -fill x -padx 8;pack $w.right.report.parameterScroll -fill x -padx 8
    set state($w,parameterDetail) {};set state($w,parameterRows) {}
    ttk::label $w.right.report.parameterDetail -textvariable ::GX::DatasetCurveFit::state($w,parameterDetail) -wraplength 650 -justify left
    pack $w.right.report.parameterDetail -fill x -padx 8
    set state($w,qualityReport) {}
    ttk::label $w.right.report.quality -textvariable ::GX::DatasetCurveFit::state($w,qualityReport) -wraplength 650 -justify left
    pack $w.right.report.quality -fill x -padx 8
    _technicalDetailsCreate $w
    bind $w.right.report.parameters <<TreeviewSelect>> [list ::GX::DatasetCurveFit::_parameterDetail $w]
    trace add variable ::GX::DatasetCurveFit::state($w,report) write [list ::GX::DatasetCurveFit::_parameterTableChanged $w]
    ttk::treeview $w.right.residuals.table -columns {row x observed fitted residual} -show headings -height 3
    foreach {column heading width} {row {Dataset row} 100 x X 140 observed {Observed Y} 140 fitted {Fitted Y} 140 residual {Residual (observed - fit)} 210} {
        $w.right.residuals.table heading $column -text $heading
        $w.right.residuals.table column $column -width $width -stretch 1
    }
    bind $w.right.residuals.table <<TreeviewSelect>> [list ::GX::DatasetCurveFit::_residualTableFocus $w]
    pack $w.right.residuals.table -fill x -padx 8
    set state($w,residualStart) 0;set state($w,residualStatus) "Exact residual data is retained when this panel is hidden."
    ttk::frame $w.right.residuals.pager
    foreach {key text step} {previous Previous -200 next Next 200 first First -100000000000 last Last 100000000000} {
        ttk::button $w.right.residuals.pager.$key -text $text -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_residualPageUi $w $step]]
        pack $w.right.residuals.pager.$key -side left -padx 4
    }
    ttk::button $w.right.residuals.pager.select -text {Use inspected row for fitting} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_residualReviewSelect $w]]
    pack $w.right.residuals.pager.select -side right -padx 4
    ttk::label $w.right.residuals.pager.status -textvariable ::GX::DatasetCurveFit::state($w,residualStatus);pack $w.right.residuals.pager.status -side left -padx 6
    pack $w.right.residuals.pager -after $w.right.residuals.table -side bottom -fill x -padx 8
    ttk::label $w.footer.status -textvariable ::GX::DatasetCurveFit::state($w,status) -anchor w;pack $w.footer.status -fill x -padx 8 -pady 4
    # Diagnostics have their own actual Tk parents, outside the plot viewport.
    bind $w.right.plot.canvas <ButtonPress-1> [list ::GX::DatasetCurveFit::_mouseDown $w %x %y %s]
    bind $w.right.plot.canvas <Motion> [list ::GX::DatasetCurveFit::_coordinates $w %x %y]
    bind $w.right.plot.canvas <B1-Motion> [list ::GX::DatasetCurveFit::_mouseMove $w %x %y]
    bind $w.right.plot.canvas <ButtonRelease-1> [list ::GX::DatasetCurveFit::_mouseUp $w %x %y %s]
    bind $w.right.plot.canvas <ButtonPress-2> [list ::GX::DatasetCurveFit::_panDown $w %x %y]
    bind $w.right.plot.canvas <B2-Motion> [list ::GX::DatasetCurveFit::_panMove $w %x %y]
    bind $w.right.plot.canvas <ButtonRelease-2> [list ::GX::DatasetCurveFit::_panUp $w]
    bind $w.right.plot.canvas <MouseWheel> [list ::GX::DatasetCurveFit::_wheel $w %D %x %y]
    bind $w.right.plot.canvas <Button-4> [list ::GX::DatasetCurveFit::_zoom $w 0.85 %x %y]
    bind $w.right.plot.canvas <Button-5> [list ::GX::DatasetCurveFit::_zoom $w 1.18 %x %y]
    bind $w.right.plot.canvas <Configure> [list ::GX::DatasetCurveFit::redraw $w]
    foreach frame {source samples filter settings parameters actions selection presentation accepted workspace.actions residualPager} {
        set widget [_widget $w $frame]
        bind $widget <Configure> [list ::GX::native2DToolbarLayout $widget %w]
    }
    _layout $w
    if {$state($w,dataset) ne ""} {_uiSafe $w [list ::GX::DatasetCurveFit::_uiDataset $w]}
    _uiModelFields $w
    _uiDomainFields $w
    if {$state($w,sessionToken) ne ""} {_uiSafe $w [list ::GX::DatasetCurveFit::_restoreState $w $requestedDataset]}
    _historyAttach $w
    if {$requestedWorkspace eq "new"} {_saveState $w}
    set state($w,catalogSubscription) [::GX::datasetCatalogSubscribe [list ::GX::DatasetCurveFit::_workspaceCatalog $w]]
    ::GX::sessionWorkspaceViewerTitle $w {Dataset Curve Fit} [list ::GX::DatasetCurveFit::_currentWorkspace $w] [list set ::GX::DatasetCurveFit::state($w,workspaceName)]
    return $w
}
proc ::GX::DatasetCurveFit::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported Dataset Curve Fit action $action"}
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : [dict create]}]
    return [open $context]
}
if {[llength [info commands ::GX::viewerBackendRegister]]} {
    ::GX::viewerBackendRegister dataset_curve_fit_tk ::GX::DatasetCurveFit::viewerDispatch
}
source [file join [file dirname [info script]] curve_fit_workspace_v2.tcl]
source [file join [file dirname [info script]] curve_fit_numeric_source_v2.tcl]
# Public additive Numerical conversion service. Uses the same Numerical models,
# residuals and Parallel Execution authority as the scientific fitter.
proc ::GX::DatasetCurveFit::fitPrimitive {points family unit} {
    if {$family ni {circle arc quadratic_bezier cubic_bezier}} {error "Supported retained fits: circle, arc, quadratic or cubic Bézier"}
    ::GX::unitRegistryConversionPlan $unit $unit
    if {![::GX::unitTclCompatible $unit m]} {error "Retained geometric conversion requires declared compatible length units"}
    if {[llength $points]<3||[llength $points]>65536} {error "Retained fit input requires 3..65536 complete points; choose an explicit range for larger sources"}
    set model [expr {$family in {circle arc}?"circular_arc":$family}]
    set report [_runNumeric $model 2 {} $points $points {parameter 0 1 257} [dict create orientation parametric translation_u {mode off delta 0} translation_v {mode off delta 0}]]
    set facts [dict get $report numeric_statistics];set raw [dict get $facts fit]
    foreach role {training evaluation} {
        set context [dict create orientation parametric x_unit $unit y_unit $unit coefficient_space original_physical constraints none sample_role $role \
            zero_normal_sign_policy [::GX::datasetPublicationV2DictDefault $report zero_normal_sign_policy unspecified]]
        dict set report statistical_results $role [::GX::StatisticsV1::fromNumeric math.numeric.$model [dict get $raw operation] $raw $context [dict get $facts $role] [dict create producer viewer.dataset_curve_fit source_identity explicit_point_input]]
    }
    dict unset report numeric_statistics
    set report [_applyStatisticsAliases $report]
    _native;set scene [::GX::Native2D::core scene]
    try {set definition [::GX::Native2D::core interaction_from_fit $scene $family [split [dict get $report parameters] ,]]} finally {::GX::Native2D::core destroy $scene}
    return [dict create definition $definition quality [dict remove $report fitted residual] working_unit $unit method scientific_fit numeric_api NUMERIC_API_v1 model $model approximation 1]
}

source [file join [file dirname [info script]] curve_fit_layout.tcl]
source [file join [file dirname [info script]] curve_fit_settings.tcl]
source [file join [file dirname [info script]] curve_fit_history.tcl]

source [file join [file dirname [info script]] curve_fit_statistics_v1.tcl]
source [file join [file dirname [info script]] curve_fit_model_comparison_v1.tcl]
source [file join [file dirname [info script]] curve_fit_solver_v1.tcl]
source [file join [file dirname [info script]] curve_fit_smoothing_v1.tcl]
source [file join [file dirname [info script]] curve_fit_conditional_controls_v1.tcl]
source [file join [file dirname [info script]] curve_fit_measurements_v1.tcl]
source [file join [file dirname [info script]] curve_fit_covariance_v1.tcl]
source [file join [file dirname [info script]] curve_fit_components_v1.tcl]
source [file join [file dirname [info script]] curve_fit_regions_v1.tcl]
source [file join [file dirname [info script]] curve_fit_formula_v1.tcl]
source [file join [file dirname [info script]] curve_fit_baseline_v1.tcl]
source [file join [file dirname [info script]] curve_fit_registered_models_v1.tcl]
source [file join [file dirname [info script]] curve_fit_recipe_v1.tcl]
source [file join [file dirname [info script]] curve_fit_templates_v1.tcl]
source [file join [file dirname [info script]] curve_fit_model_export_v1.tcl]

source [file join [file dirname [info script]] curve_fit_registered_gui_v1.tcl]
source [file join [file dirname [info script]] curve_fit_registered_solver_v1.tcl]

source [file join [file dirname [info script]] curve_fit_log_response_v1.tcl]

source [file join [file dirname [info script]] curve_fit_influence_v1.tcl]
source [file join [file dirname [info script]] curve_fit_bootstrap_v1.tcl]
source [file join [file dirname [info script]] curve_fit_profile_v1.tcl]

source [file join [file dirname [info script]] curve_fit_accept_v1.tcl]

source [file join [file dirname [info script]] curve_fit_residuals_v1.tcl]

source [file join [file dirname [info script]] curve_fit_parameter_dataset_v1.tcl]
source [file join [file dirname [info script]] curve_fit_family_v1.tcl]
source [file join [file dirname [info script]] curve_fit_global_family_v1.tcl]

source [file join [file dirname [info script]] curve_fit_smooth_source_v1.tcl]

source [file join [file dirname [info script]] curve_fit_residual_sequence_v1.tcl]
source [file join [file dirname [info script]] curve_fit_parameters_v1.tcl]
source [file join [file dirname [info script]] curve_fit_parameter_callbacks_v1.tcl]

source [file join [file dirname [info script]] curve_fit_query_v1.tcl]
source [file join [file dirname [info script]] curve_fit_query_callbacks_v1.tcl]
source [file join [file dirname [info script]] curve_fit_output_domain_v1.tcl]
source [file join [file dirname [info script]] curve_fit_preprocessing_v1.tcl]
source [file join [file dirname [info script]] curve_fit_report_v1.tcl]

source [file join [file dirname [info script]] curve_fit_model_cards_v1.tcl]

source [file join [file dirname [info script]] curve_fit_workbench_v1.tcl]

source [file join [file dirname [info script]] curve_fit_derived_v1.tcl]

source [file join [file dirname [info script]] curve_fit_physical_plausibility_v1.tcl]

source [file join [file dirname [info script]] curve_fit_suggestions_v1.tcl]

source [file join [file dirname [info script]] curve_fit_implicit_v1.tcl]

source [file join [file dirname [info script]] curve_fit_complex_v1.tcl]
source [file join [file dirname [info script]] curve_fit_complex_controls_v1.tcl]
source [file join [file dirname [info script]] curve_fit_surface_v1.tcl]
source [file join [file dirname [info script]] curve_fit_surface_gui_v1.tcl]

source [file join [file dirname [info script]] curve_fit_rational_v1.tcl]
source [file join [file dirname [info script]] curve_fit_knots_v1.tcl]
