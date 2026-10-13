# GX-TXT Dataset Curve Fit viewer. Data comes from canonical Dataset APIs;
# graphics/selection are backed by Native 2D; math is NUMERIC_API_v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::DatasetCurveFit {
    variable state
    variable serial 0
    variable version "0.4.0"
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
    foreach {field widget candidates} [list x $w.source.x [dict get $schema numeric] y $w.source.y [dict get $schema numeric] filterVar $w.filter.variable [dict get $schema all]] {
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
    set state($key,showResiduals) 1;set state($key,residualFraction) .60
    set state($key,deferDispose) 0;set state($key,orientation) y_of_x
    set state($key,sourceStatus) ready;set state($key,sourceError) "";set state($key,savedSelection) {};set state($key,sourcePointCount) 0
    set state($key,polarFrame) [_defaultPolarFitFrame $state($key,scene)]
    return $key
}
proc ::GX::DatasetCurveFit::close {key} {
    variable state
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
    return [selectedIndices $key]
}
proc ::GX::DatasetCurveFit::clearSelection {key} {
    variable state
    ::GX::Native2D::core clear $state($key,selectionScene)
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
    set api [file join $root plugins modules math.numeric api octave]
    if {![file exists [file join $api gxtxt_numeric_v1.m]]} {error "Public NUMERIC_API_v1 Octave binding is unavailable"}
    set holder [file tempfile temp];::close $holder;file delete $temp;file mkdir $temp
    set workerEnvironment {};set run ""
    try {
        set binary [expr {$nativeScene ne ""}]
        set trainFile [file join $temp train.csv];set sourceFile [file join $temp source.csv]
        set trainFormat csv;set sourceFormat csv
        if {$binary} {
            set sourceFile [dict get $source xy_file];set sourceFormat [dict get $source xy_format]
            if {![catch {dict get $training api_id} marker]&&$marker eq "CURVE_SOURCE_NUMERIC_INPUT_v1"} {
                set trainFile [dict get $training xy_file];set trainFormat [dict get $training xy_format]
            } else {_csvRows $trainFile $training}
        } else {_csvRows $trainFile $training;_csvRows $sourceFile $source}
        _csvRows [file join $temp initial.csv] [list $initial]
        set range [expr {$domainSpec ne "source"}]
        if {$range} {
            if {[llength $domainSpec] == 4} {lassign [lrange $domainSpec 1 end] domainMin domainMax domainSamples} else {lassign $domainSpec domainMin domainMax domainSamples}
        } else {lassign {0 0 0} domainMin domainMax domainSamples}
        set period [expr {[dict exists $options period] ? [dict get $options period] : ""}]
        set smoothing [expr {[dict exists $options smoothing_lambda] ? [dict get $options smoothing_lambda] : ""}]
        foreach {name value} [list TRAIN $trainFile SOURCE $sourceFile TRAIN_FORMAT $trainFormat SOURCE_FORMAT $sourceFormat BINARY_OUTPUT $binary INITIAL [file join $temp initial.csv] RESULT [file join $temp result.tsv] FITTED [file join $temp fitted.csv] RESIDUAL [file join $temp residual.csv] MODEL_STATE [file join $temp model_state.json] NUMERIC_API_DIR $api MODEL $model DEGREE $degree DOMAIN_MODE [expr {$range ? "range" : "source"}] DOMAIN_MIN $domainMin DOMAIN_MAX $domainMax DOMAIN_SAMPLES $domainSamples PERIOD $period SMOOTHING $smoothing ORIENTATION [_fitOrientation $model $options]] {dict set workerEnvironment GXDCF_$name $value}
        foreach {name field fallback} {PARAMETERIZATION parameterization row_order TOPOLOGY topology auto USER_PERIOD user_period "" CLOSURE_TOLERANCE closure_tolerance ""} {dict set workerEnvironment GXDCF_$name [::GX::datasetPublicationV2DictDefault $options $field $fallback]}
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
        set executable [auto_execok octave-cli]
        if {$executable eq ""} {set executable [auto_execok octave]}
        if {$executable eq ""} {error "GNU Octave is required by NUMERIC_API_v1"}
        set run [::GX::parallelExecutionNewRunId curve_fit]
        set progress ""
        if {$hostKey ne ""} {
            variable state
            if {$state($hostKey,sourceCancelled)} {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} "Fitting cancelled"}
            set state($hostKey,numericRun) $run
            set progress [list ::GX::DatasetCurveFit::_numericProgress $hostKey]
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
        set report [dict create]
        set in [::open [file join $temp result.tsv] r]
        try {while {[gets $in line] >= 0} {set fields [split $line \t];dict set report [lindex $fields 0] [lindex $fields 1]}} finally {::close $in}
        if {$binary} {
            set report [_numericNativeResult $nativeScene $document $temp $source $report]
        } else {
            dict set report fitted [_readCsv [file join $temp fitted.csv] 2]
            dict set report residual [_readCsv [file join $temp residual.csv] [::GX::datasetPublicationV2DictDefault $report residual_stride 4]]
        }
        return $report
    } finally {
        if {$run ne ""} {::GX::parallelExecutionRelease $run}
        if {$hostKey ne ""} {set state($hostKey,numericRun) ""}
        file delete -force $temp
    }
}
proc ::GX::DatasetCurveFit::preview {key model scope domainSpec {degree 2} {initial {}} {options {}}} {
    variable state
    _assertLoaded $key
    set sourceSnapshot [list $state($key,activeSource) $state($key,source) $state($key,loadedBinding)]
    set selectionSnapshot [_selectionDescriptor $key]
    set selectedSnapshot [selectedIndices $key]
    set sceneSnapshot $state($key,scene)
    if {$model ni {linear polynomial exponential power_law gaussian circular_arc quadratic_bezier cubic_bezier pchip smoothing_spline fourier parametric_polynomial parametric_spline}} {error "Choose a supported model"}
    if {$scope ni {all selected}} {error "Fit scope must be all or selected"}
    set points [sourcePoints $key]
    if {$scope eq "all"} {set training $points} else {set training [::GX::Native2D::core export $state($key,selectionScene) $state($key,selectionObject)]}
    if {[llength $training] < 2 && ($scope eq "all" || $state($key,sourceToken) eq "")} {error "Select at least two fit points"}
    if {$model in {polynomial parametric_polynomial} && (![string is integer -strict $degree] || $degree < 1 || $degree > 12)} {error "Polynomial degree must be 1–12"}
    if {$model eq "fourier" && (![string is integer -strict $degree] || $degree < 1)} {error "Fourier order must be a positive integer"}
    if {$model eq "fourier" && [dict exists $options period] && [dict get $options period] ne "" &&
        [_finite [dict get $options period] "Fourier period"] <= 0} {error "Fourier period must be positive"}
    if {$model eq "smoothing_spline" && (![dict exists $options smoothing_lambda] ||
        [_finite [dict get $options smoothing_lambda] "Smoothing lambda"] < 0)} {error "Smoothing lambda must be nonnegative"}
    if {$model in {parametric_polynomial parametric_spline}&&[::GX::datasetPublicationV2DictDefault $options parameterization row_order] eq "user_parameter"&&$state($key,sourceToken) eq ""} {error "User parameter mode needs a real Dataset parameter variable"}
    set required [dict get [dict create linear 0 polynomial 0 exponential 3 power_law 2 gaussian 4 circular_arc 0 quadratic_bezier 0 cubic_bezier 0 pchip 0 smoothing_spline 0 fourier 0 parametric_polynomial 0 parametric_spline 0] $model]
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
    if {[info exists state($key,sourceToken)]&&$state($key,sourceToken) ne ""} {
        set mask [expr {$scope eq "selected" ? [_selectionDescriptor $key] : {}}]
        set progress [expr {[info exists state($key,loading)]&&$state($key,loading) ? [list ::GX::DatasetCurveFit::_stagingProgress $key] : ""}]
        set result [::GX::curveSourceWithNumericInput $state($key,sourceToken) [list ::GX::DatasetCurveFit::_numericSource $key $model $degree $initial $scope $training $domainSpec $options] $mask $progress [::GX::datasetPublicationV2DictDefault $options parameter_variable_id ""]]
    } else {
        set hostKey [expr {[info exists state($key,loading)]&&$state($key,loading) ? $key : ""}]
        set result [_runNumeric $model $degree $initial $training $points $domainSpec $options "" "" $hostKey]
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
    dict set result options $options
    dict set result source_id $state($key,source)
    dict set result selected_indices $selectedSnapshot
    dict set result selection_descriptor $selectionSnapshot
    if {!$state($key,deferDispose)} {_disposePreview $key}
    set state($key,preview) $result
    set state($key,previewAccepted) 0
    set state($key,previewFitId) ""
    return $result
}
proc ::GX::DatasetCurveFit::accept {key} {
    variable state
    _assertLoaded $key
    if {$state($key,preview) eq {}} {error "Preview a fit before accepting it"}
    if {$state($key,previewAccepted)} {error "This preview has already been accepted"}
    if {[dict get $state($key,preview) source_id] != $state($key,source)} {error "Source curve changed; preview again"}
    if {[dict get $state($key,preview) scope] eq "selected" && ![_selectionUnchanged $key $state($key,preview)]} {error "Fit-point selection changed; preview again"}
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
    set label "Fit $id: [dict get $result model] ([dict get $result train_n] points, RMSE [format %.4g [dict get $result train_rmse]])"
    lappend state($key,records) [dict create id $id label $label color $color visible 1 points $points model [dict get $result model] parameters [dict get $result parameters] model_state_json [expr {[dict exists $result model_state_json] ? [dict get $result model_state_json] : ""}] scope [dict get $result scope] domain [dict get $result domain] rmse [dict get $result train_rmse] r2 [dict get $result train_r2]]
    set record [lindex $state($key,records) end]
    set provenance [dict remove $result fitted residual fitted_native residual_native residual_display fitted_breaks residual_rows source_id]
    set provenance [dict merge $provenance [_sourceProvenance $key]]
    dict set record provenance $provenance
    dict set record source_curve_id $state($key,activeSource)
    dict set record fit_curve_id "accepted[incr state($key,nextFit)]"
    dict set record provenance fit_curve_id [dict get $record fit_curve_id]
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
        puts $out [join [list [_csvCell $xColumn] [_csvCell $yColumn] source_kind $identityField fit_model fit_scope fit_core_id] ,]
        set provenance [join [list [_csvCell $kind] [_csvCell [dict get $lineage $identityField]] [_csvCell [dict get $record model]] [_csvCell [dict get $record scope]] $native] ,]
        for {set start 0} {$start<$count} {incr start 4096} {
            foreach point [::GX::Native2D::core points_page $state($key,scene) $native $start [expr {min(4096,$count-$start)}]] {lassign $point x y;puts $out "[format %.17g $x],[format %.17g $y],$provenance"}
        }
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
proc ::GX::DatasetCurveFit::_exportCsvMetadata {record version out context} {
    set metadata [expr {[dict exists $record provenance] ? [dict get $record provenance] : [dict remove $record id points color visible label]}]
    dict set metadata producer_module viewer.dataset_curve_fit
    dict set metadata producer_version $version
    dict set metadata csv_sha256 [dict get $context completed csv sha256]
    if {[dict exists $context completed model]} {
        dict set metadata model_state_file [file tail [dict get $context completed model destination]]
        dict set metadata model_state_sha256 [dict get $context completed model sha256]
        dict set metadata model_state_storage external_json_file
    }
    fconfigure $out -encoding utf-8 -translation lf
    puts $out "; GX-TXT Dataset Curve Fit CSV metadata v1\n\[curve_fit\]"
    foreach field [lsort [dict keys $metadata]] {::GX::putKV $out $field [dict get $metadata $field]}
}
proc ::GX::DatasetCurveFit::_formulaBase {result} {
    set p [lmap v [split [dict get $result parameters] ,] {format %.7g $v}]
    set model [dict get $result model]
    switch -- $model {
        circular_arc {return "Circular arc: center, radius and oriented angle interval are saved in model state."}
        quadratic_bezier {return "Quadratic Bézier: P0, P1 and P2 are saved in model state."}
        cubic_bezier {return "Cubic Bézier: P0, P1, P2 and P3 are saved in model state."}
        parametric_polynomial {return "X=x(t), Y=y(t): independent polynomial coordinates, degree [dict get $result degree]."}
        parametric_spline {return "X=x(t), Y=y(t): ordered cubic interpolation; [dict get $result topology] topology."}
        pchip {return "Shape-preserving piecewise cubic interpolation (PCHIP)."}
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
    if {[dict get $result model] in {circular_arc quadratic_bezier cubic_bezier pchip smoothing_spline fourier parametric_polynomial parametric_spline}} {
        set bytes [::GX::datasetPublicationV2DictDefault $result model_state_bytes [expr {[dict exists $result model_state_json] ? [string length [dict get $result model_state_json]] : 0}]]
        set storage [expr {[dict exists $result model_state_resource] ? "owned document resource" : "inline"}]
        return "Model state: $bytes JSON bytes ($storage); output [dict get $result output_n] points."
    }
    set names [dict get [dict create linear {slope intercept} polynomial {} exponential {amplitude rate offset} power_law {scale exponent} gaussian {amplitude center width offset}] [dict get $result model]]
    set values [split [dict get $result parameters] ,]
    if {[dict get $result model] eq "polynomial"} {
        set degree [expr {[llength $values]-1}]
        set names {}
        for {set i $degree} {$i >= 0} {incr i -1} {lappend names "x^$i"}
    }
    set out {}
    foreach name $names value $values {lappend out "$name = [format %.7g $value]"}
    set text [join $out {,  }]
    if {[::GX::datasetPublicationV2DictDefault $result orientation y_of_x] eq "x_of_y"} {set text [_swapFormulaAxes $text]}
    return $text
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
    $w.filters delete 0 end
    foreach filter $filters {$w.filters insert end "[dict get $filter variable] [dict get $filter operator] [join [dict get $filter value] ,]"}
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
    if {[llength $state($w,records)]} {$w.fits selection set end}
    $w.actions.preview configure -state normal
    $w.actions.accept configure -state disabled
    $w.actions.publish configure -state disabled
    $w.actions.export configure -state [expr {[llength $state($w,records)] ? "normal" : "disabled"}]
    set state($w,documentId) [dict get $document id]
    set state($w,status) "Restored [llength $state($w,records)] accepted fits from the Session."
    redraw $w
}

proc ::GX::DatasetCurveFit::_uiSafe {w script} {
    variable state
    if {[catch {uplevel #0 $script} err options]} {
        set state($w,status) $err
        if {[dict get $options -errorcode] eq {GX CURVE_SOURCE CANCELLED}} return
        tk_messageBox -parent $w -icon error -type ok -title "Dataset Curve Fit" -message $err
    }
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
    $w.filters delete 0 end
    _uiFilterOperator $w
    if {$state($w,source) eq ""} {set state($w,status) "Choose filters, then load the Dataset curve."} else {_markSourceDirty $w}
}
proc ::GX::DatasetCurveFit::_uiFilterOperator {w} {
    variable state
    if {$state($w,filterVar) eq ""} return
    set kind [dict get [dict get $state($w,schema) kinds] $state($w,filterVar)]
    set ops [expr {$kind eq "number" ? {= != < <= > >= between} : {= != contains LIKE}}]
    $w.filter.operator configure -values $ops
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
    $w.filters insert end "$state($w,filterVar) $state($w,filterOp) [join $value ,]"
    set state($w,status) "[llength $state($w,filters)] filters; reload the Dataset curve to apply."
    _markSourceDirty $w
}
proc ::GX::DatasetCurveFit::_uiRemoveFilter {w} {
    variable state
    set index [lindex [$w.filters curselection] 0]
    if {$index eq ""} return
    set state($w,filters) [lreplace $state($w,filters) $index $index]
    $w.filters delete $index
    _markSourceDirty $w
}
proc ::GX::DatasetCurveFit::_uiLoad {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {error "A Dataset source is already loading"}
    set state($w,loading) 1;set state($w,sourceJob) "";set state($w,sourceCancelled) 0;set state($w,closeRequested) 0
    set controls [_sourceControls $w 1]
    $w.filter.cancel configure -state normal
    try {
        loadSource $w $state($w,dataset) $state($w,x) $state($w,y) $state($w,filters)
    } finally {
        set state($w,loading) 0;set state($w,sourceJob) ""
        _sourceControls $w 0 $controls
        _workspaceRefresh $w
        $w.filter.cancel configure -state disabled
        if {$state($w,closeRequested)} {after idle [list ::GX::DatasetCurveFit::_closeWindow $w]}
    }
    set state($w,status) "Loaded [llength [sourcePoints $w]] Dataset points into Native 2D; click or drag to select fit points."
    if {[dict exists $state($w,sourceDescriptor) row_count]} {set state($w,status) "Added $state($w,activeSource): [dict get $state($w,sourceDescriptor) row_count] exact source rows; [llength [sourcePoints $w]] display points. Fit all reads exact data."}
    set state($w,report) ""
    $w.residuals delete [$w.residuals children {}]
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
    $w.residuals delete [$w.residuals children {}]
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
        exponential {set state($w,initial) {1,-0.1,0}}
        power_law {set state($w,initial) {1,1}}
        gaussian {set state($w,initial) {1,0,1,0}}
        default {set state($w,initial) ""}
    }
    set parametric [expr {$state($w,model) in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial parametric_spline}}]
    if {$parametric && $state($w,domain) eq "range"} {set state($w,domain) parameter}
    if {!$parametric && $state($w,domain) eq "parameter"} {set state($w,domain) range}
    $w.settings.domain configure -values [expr {$parametric ? {source parameter} : {source range}}]
    if {$parametric && $state($w,domain) eq "parameter"} {
        if {$state($w,min) eq ""} {set state($w,min) 0}
        if {$state($w,max) eq ""} {set state($w,max) 1}
    }
    if {$parametric} {set state($w,orientation) parametric} elseif {$state($w,orientation) eq "parametric"} {set state($w,orientation) y_of_x}
    _orientationLabels $w
    _uiModelFields $w
    _uiDomainFields $w
}
proc ::GX::DatasetCurveFit::_uiModelFields {w} {
    variable state
    $w.settings.parametric configure -state [expr {$state($w,model) in {parametric_polynomial parametric_spline} ? "normal" : "disabled"}]
    $w.settings.polar configure -state [expr {$state($w,orientation) eq "r_of_theta" ? "normal" : "disabled"}]
    $w.parameters.degree configure -state [expr {$state($w,model) in {polynomial parametric_polynomial fourier} ? "normal" : "disabled"}]
    $w.parameters.initial configure -state [expr {$state($w,model) in {exponential power_law gaussian} ? "normal" : "disabled"}]
    $w.parameters.period configure -state [expr {$state($w,model) eq "fourier" ? "normal" : "disabled"}]
    $w.parameters.smoothing configure -state [expr {$state($w,model) eq "smoothing_spline" ? "normal" : "disabled"}]
    $w.parameters.l_degree configure -text [expr {$state($w,model) eq "fourier" ? "Order N" : "Degree"}]
}
proc ::GX::DatasetCurveFit::_uiDomainFields {w} {
    variable state
    set enabled [expr {$state($w,domain) in {range parameter} ? "normal" : "disabled"}]
    foreach field {min max samples} {$w.parameters.$field configure -state $enabled}
    set independent [expr {$state($w,orientation) eq "x_of_y" ? "Y" : ($state($w,orientation) eq "parametric" ? "t" : ($state($w,orientation) eq "r_of_theta" ? "theta" : "X"))}]
    foreach bound {min max} {$w.parameters.l_$bound configure -text "$independent $bound"}
}
proc ::GX::DatasetCurveFit::_uiPreview {w} {
    variable state
    set domain source
    if {$state($w,domain) eq "range"} {set domain [list $state($w,min) $state($w,max) $state($w,samples)]}
    if {$state($w,domain) eq "parameter"} {set domain [list parameter $state($w,min) $state($w,max) $state($w,samples)]}
    set initial {}
    foreach part [split $state($w,initial) ,] {if {[string trim $part] ne ""} {lappend initial [string trim $part]}}
    set options [_uiFitOptions $w]
    set controls [_operationBegin $w]
    try {set result [preview $w $state($w,model) $state($w,scope) $domain $state($w,degree) $initial $options]} finally {_operationEnd $w $controls}
    set metric [expr {[dict get $result parametric] ? "Geometric RMSE" : "RMSE"}]
    set r2 [expr {[dict get $result parametric] ? "XY dispersion R²" : "R²"}]
    set state($w,report) "[formula $result]\n[parameterReport $result]\nFit points: [dict get $result train_n]  $metric: [format %.6g [dict get $result train_rmse]]  $r2: [format %.6g [dict get $result train_r2]]\nAll source points: $metric [format %.6g [dict get $result source_rmse]]  $r2 [format %.6g [dict get $result source_r2]]  Converged: [dict get $result converged]"
    _residualColumns $w $result
    set state($w,residualStart) 0
    $w.residuals delete [$w.residuals children {}]
    set index 0
    foreach row [dict get $result residual] {
        lassign $row x observed fitted residual
        set sourceRows [expr {[dict exists $result residual_rows] ? [dict get $result residual_rows] : $state($w,rows)}]
        set values [list [lindex $sourceRows $index] [format %.9g $x] [format %.9g $observed] [format %.9g $fitted] [format %.9g $residual]]
        if {[dict get $result parametric]} {lappend values [format %.9g [lindex $row 4]] [format %.9g [lindex $row 5]]}
        $w.residuals insert {} end -values $values
        incr index
    }
    set state($w,status) "Preview ready. Output X domain is independent of fit-point selection. Accept to add a new CORE curve."
    $w.actions.accept configure -state normal
    $w.actions.publish configure -state normal
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiAccept {w} {
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
    foreach {field value} [list model $state($w,model) scope $state($w,scope) domain $domain degree $state($w,degree) initial $initial options [_uiFitOptions $w]] {
        if {[dict get $preview $field] ne $value} {error "Fit settings changed; preview again before accepting"}
    }
    _assertLoaded $w
    if {[dict get $preview scope] eq "selected" && ![_selectionUnchanged $w $preview]} {error "Fit-point selection changed; preview again"}
    set id [accept $w]
    set state($w,previewFitId) $id
    set state($w,status) "Accepted Native 2D CORE curve $id. Publish as Dataset separately if needed."
    _refreshFits $w
    $w.fits selection clear 0 end
    $w.fits selection set end
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
    foreach {field value} [list model $state($w,model) scope $state($w,scope) domain $domain degree $state($w,degree) initial $initial options [_uiFitOptions $w]] {
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
    set index [lindex [$w.fits curselection] 0]
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
    set fitMetadata [dict create dataset.display_name $name curve_fit.producer viewer.dataset_curve_fit curve_fit.source_kind $sourceKind curve_fit.source_sha256 $sourceSha curve_fit.source_x_variable_id [dict get $bindings x] curve_fit.source_y_variable_id [dict get $bindings y] curve_fit.source_x_name [dict get $labels x] curve_fit.source_y_name [dict get $labels y] curve_fit.filters $filters curve_fit.model [dict get $result model] curve_fit.parameters [dict get $result parameters] curve_fit.scope [dict get $result scope] curve_fit.domain [dict get $result domain] curve_fit.grid_kind [dict get $result grid_kind] curve_fit.output_n [dict get $result output_n] curve_fit.selected_indices [dict get $result selected_indices] curve_fit.train_n [dict get $result train_n] curve_fit.train_rmse [dict get $result train_rmse] curve_fit.train_r2 [dict get $result train_r2] curve_fit.source_rmse [dict get $result source_rmse] curve_fit.source_r2 [dict get $result source_r2]]
    if {[dict exists $result model_state_json]} {dict set fitMetadata curve_fit.model_state_json [dict get $result model_state_json]}
    foreach field {orientation metric_unit coordinate_mode independent_axis polar_frame angular_min angular_max angle_unit unwrap_policy topology parameterization parameter_variable_descriptor model_state_resource model_state_storage model_state_bytes parameters_storage parameter_count degree options residual_convention r2_convention zero_normal_sign_policy train_geometric_rmse source_geometric_rmse train_max_geometric_distance source_max_geometric_distance residual_stride residual_columns selection_descriptor} {
        if {[dict exists $result $field]} {dict set fitMetadata curve_fit.$field [dict get $result $field]}
    }
    dict for {field value} $lineage {dict set fitMetadata curve_fit.$field $value}
    if {$sourceKind in {sample builtin_sample}} {set fitMetadata [dict merge $fitMetadata [_sampleMetadata $sourceIdentity curve_fit.sample]]}
    dict set definition structured_metadata $fitMetadata
    set plan [::GX::datasetPublicationV2Prepare $session viewer.dataset_curve_fit $definition]
    set writer ""
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
        set appended 0
        if {[dict exists $result fitted_native]} {
            set total [dict get $result output_n]
            for {set start 0} {$start<$total} {incr start 65536} {
                set chunk [::GX::Native2D::core points_page $state($key,scene) [dict get $result fitted_native] $start [expr {min(65536,$total-$start)}]]
                incr appended [::GX::datasetPublicationV2Append $writer row [dict create fitted_x [lmap point $chunk {lindex $point 0}] fitted_y [lmap point $chunk {lindex $point 1}]]]
            }
        } else {set appended [::GX::datasetPublicationV2Append $writer row [dict create fitted_x $xs fitted_y $ys]]}
        if {$appended != [dict get $result output_n]} {error "Incomplete fit Dataset publication"}
        set published [::GX::datasetPublicationV2Finalize $writer]
    } failure options]} {
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
    set state($w,status) "CORE fit-point selection cleared."
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_uiExport {w} {
    variable state
    set index [lindex [$w.fits curselection] 0]
    set id [expr {$index eq "" ? $state($w,accepted) : [dict get [lindex $state($w,records) $index] fit_curve_id]}]
    set path [::GX::workspaceSaveFile export_dir -parent $w -defaultextension .csv -filetypes {{{CSV files} {.csv}} {{All files} {*}}}]
    if {$path eq ""} return
    set count [exportCsv $w $path $id]
    set state($w,status) "Exported $count accepted fit points to $path"
}
proc ::GX::DatasetCurveFit::_refreshFits {w} {
    variable state
    if {![winfo exists $w.fits]} return
    $w.fits delete 0 end
    set index 0
    foreach record $state($w,records) {
        $w.fits insert end "[expr {[dict get $record visible] ? "●" : "○"}] [dict get $record label]"
        $w.fits itemconfigure $index -foreground [_rgbHex [dict get $record color]]
        incr index
    }
}
proc ::GX::DatasetCurveFit::_uiFitAction {w action} {
    variable state
    set index [lindex [$w.fits curselection] 0]
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
        $w.residuals delete [$w.residuals children {}]
    }
    _refreshFits $w
    if {$action eq "visibility"} {$w.fits selection set $index}
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
    set state($w,status) "Removed the last selection rectangle; [llength [selectedIndices $w]] points remain selected."
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_plotFrame {w} {
    variable state
    set width [winfo width $w.canvas]
    set height [winfo height $w.canvas]
    set state($w,residualPlotVisible) [expr {$state($w,showResiduals)&&$state($w,preview) ne {}&&$height>=230}]
    set bottom [expr {$state($w,residualPlotVisible) ? min($height-131,max(80,round($height*$state($w,residualFraction))-30)) : $height-55}]
    return [list 76 [expr {max(100,$width-64)}] 24 $bottom]
}
proc ::GX::DatasetCurveFit::_residualPanel {w} {
    variable state
    if {[winfo exists $w.right.residuals]} {_residualPanelLayout $w} elseif {$state($w,showResiduals)} {
        pack $w.residuals -after $w.status -side bottom -fill x -padx 8
        pack $w.residualPager -after $w.residuals -side bottom -fill x -padx 8
    } else {pack forget $w.residuals;pack forget $w.residualPager}
    redraw $w;_saveState $w
}
proc ::GX::DatasetCurveFit::_residualResize {w value} {
    variable state
    set state($w,residualFraction) [::GX::uiFieldNormalize {type number min .3 max .9} $value]
    redraw $w;_saveState $w
}
proc ::GX::DatasetCurveFit::_residualPageUi {w step} {
    variable state
    if {$state($w,preview) eq {}||![dict exists $state($w,preview) residual_resource]} {error "Preview a Dataset fit to read exact residual pages"}
    set report $state($w,preview)
    set start [expr {max(0,min([dict get $report source_n]-200,$state($w,residualStart)+$step))}]
    set page [_numericResidualPage $report $start 200]
    _residualColumns $w $report
    $w.residuals delete [$w.residuals children {}]
    foreach row [dict get $page rows] id [dict get $page source_rows] {
        $w.residuals insert {} end -values [list $id {*}[lmap v $row {format %.9g $v}]]
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
    if {![winfo exists $w.canvas]} return
    set c $w.canvas
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
    set shown 0
    dict for {id entry} $state($w,sources) {if {[dict get $entry visible]} {set shown 1;break}}
    foreach record $state($w,records) {if {[dict get $record visible]} {set shown 1;break}}
    if {$shown} {set bounds [::GX::Native2D::core scene_bounds $state($w,scene)]} elseif {$state($w,viewBounds) ne {}} {
        lassign $state($w,viewBounds) bx0 bx1 by0 by1;set bounds [list $bx0 $by0 $bx1 $by1]
    } else {set bounds {-1 -1 1 1}}
    lassign $bounds xmin ymin xmax ymax
    foreach point $previewPoints {
        lassign $point x y
        set xmin [expr {min($xmin,$x)}];set xmax [expr {max($xmax,$x)}]
        set ymin [expr {min($ymin,$y)}];set ymax [expr {max($ymax,$y)}]
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
    for {set i 0} {$i <= 5} {incr i} {
        set tx [expr {$left+($right-$left)*$i/5.0}]
        set ty [expr {$bottom-($bottom-$top)*$i/5.0}]
        $c create text $tx [expr {$bottom+5}] -anchor n -text [format %.5g [expr {$xmin+($xmax-$xmin)*$i/5.0}]] -fill #475569 -tags axis_label
        $c create text [expr {$left-7}] $ty -anchor e -text [format %.5g [expr {$ymin+($ymax-$ymin)*$i/5.0}]] -fill #475569 -tags axis_label -tags axis_label
    }
    $c create rectangle $left $top $right $bottom -outline #8796a8
    $c create text [expr {($left+$right)/2.0}] [expr {$bottom+29}] -text [_axisLabel $w x] -fill #172a40 -tags axis_label
    $c create text 13 [expr {($top+$bottom)/2.0}] -text [_axisLabel $w y] -angle 90 -fill #172a40 -tags axis_label
    dict for {sourceId entry} $state($w,sources) {
        if {![dict get $entry visible]||[dict get $entry state source] eq ""} continue
        set object [::GX::native2DPresentationObjectSnapshot $state($w,scene) [dict get $entry state source] 4096]
        set tags [expr {$sourceId eq $state($w,activeSource) ? "active_source" : "source_curve"}]
        ::GX::native2DCanvasDrawObject $c $object $background $tags
    }
    foreach record $state($w,records) {
        if {![dict get $record visible]} continue
        set object [::GX::native2DPresentationObjectSnapshot $state($w,scene) [dict get $record id] 4096]
        ::GX::native2DCanvasDrawObject $c $object $background accepted_curve
    }
    if {[llength $previewPoints] >= 2 && !$state($w,previewAccepted)} {
        set coords {}
        foreach point $previewPoints {lassign $point x y;lappend coords {*}[_screen $w $x $y]}
        $c create line {*}$coords -fill #16a34a -width 2.5 -dash {6 3} -tags preview_curve
    }
    set sourceColor [expr {$hasSource ? [dict get [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA [dict get [::GX::Native2D::core object_style $state($w,scene) $state($w,source)] color]] $background] rgb] : "#2764C7"}]
    set selected [expr {$hasSource ? [selectedIndices $w] : {}}];set index 0
    foreach point [expr {$sourceShown ? $points : {}}] {
        lassign $point x y;lassign [_screen $w $x $y] px py
        set color [expr {$index in $selected ? "#e11d48" : $sourceColor}]
        set radius [expr {$index in $selected ? 5 : 3}]
        $c create oval [expr {$px-$radius}] [expr {$py-$radius}] [expr {$px+$radius}] [expr {$py+$radius}] -fill $color -outline white -tags source_point
        incr index
    }
    ::GX::native2DCanvasViewportClip $c $state($w,scene)
    $c create text [expr {$left+4}] [expr {$top+4}] -anchor nw -text "Sources: chosen styles   Selected: red   Preview: dashed   Accepted: colors below" -fill #334155
    if {$state($w,preview) ne {}&&$state($w,showResiduals)&&!$state($w,residualPlotVisible)} {
        $c create text $left [expr {$height-8}] -anchor sw -text "Residual table available below; enlarge the canvas for the residual plot." -fill #475569
    }
    if {$state($w,preview) ne {}&&$state($w,residualPlotVisible)} {
        set residual [dict get $state($w,preview) residual]
        set parametric [dict get $state($w,preview) parametric]
        set polar [expr {[dict get $state($w,preview) orientation] eq "r_of_theta"}]
        set reverseFunctional [expr {[::GX::datasetPublicationV2DictDefault $state($w,preview) orientation y_of_x] eq "x_of_y"}]
        set displayed [expr {[dict exists $state($w,preview) residual_display] ? [dict get $state($w,preview) residual_display] : [lmap row $residual {list [lindex $row [expr {$parametric||$polar ? 5 : ($reverseFunctional ? 1 : 0)}]] [lindex $row 3]}]}]
        set values [lmap row $displayed {lindex $row 1}]
        set rmin [lindex [lsort -real $values] 0];set rmax [lindex [lsort -real $values] end]
        set maxabs [expr {max(abs($rmin),abs($rmax),1e-12)}]
        set rtop [expr {$bottom+63}];set rbottom [expr {$height-20}]
        set zero [expr {($rtop+$rbottom)/2.0}]
        $c create line $left $zero $right $zero -fill #94a3b8 -dash {3 3}
        set label [expr {$parametric ? "Signed geometric distance by normalized parameter, all source points" : "[expr {$reverseFunctional ? "X" : "Y"}] residual by source [expr {$reverseFunctional ? "Y" : "X"}], all source points"}]
        if {$polar} {set label "Radial residual by theta ([dict get $state($w,preview) angle_unit]), all source points"}
        $c create text $left [expr {$rtop-14}] -anchor nw -text $label -fill #475569
        if {![info exists state($w,residualViewScene)]} {set state($w,residualViewScene) [::GX::Native2D::core scene]}
        set mainBounds [lindex [::GX::Native2D::core view $state($w,scene)] 6]
        set residualBounds [expr {$parametric ? {0 1} : [list [lindex $mainBounds [expr {$reverseFunctional ? 1 : 0}]] [lindex $mainBounds [expr {$reverseFunctional ? 3 : 2}]]]}]
        if {$polar} {set residualBounds [list [dict get $state($w,preview) angular_min] [dict get $state($w,preview) angular_max]]}
        ::GX::Native2D::core view $state($w,residualViewScene) [list $width $height $left $rtop [expr {$width-$right}] [expr {$height-$rbottom}] [list [lindex $residualBounds 0] [expr {-$maxabs}] [lindex $residualBounds 1] $maxabs]]
        foreach row $displayed {
            lassign $row x residualValue
            lassign [::GX::Native2D::core device $state($w,residualViewScene) [list $x $residualValue]] px py
            $c create oval [expr {$px-2}] [expr {$py-2}] [expr {$px+2}] [expr {$py+2}] -fill #9a3412 -outline {} -tags residual_point
        }
        ::GX::native2DCanvasClipItems $c $state($w,residualViewScene) [$c find withtag residual_point]
    }
}
proc ::GX::DatasetCurveFit::_mouseDown {w x y stateBits} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} return
    if {[catch {_assertLoaded $w}]} return
    set state($w,press) [list $x $y $stateBits]
}
proc ::GX::DatasetCurveFit::_mouseMove {w x y} {
    variable state
    if {![info exists state($w,press)]} return
    lassign $state($w,press) x0 y0 bits
    $w.canvas delete selection_drag
    if {hypot($x-$x0,$y-$y0) > 5} {
        $w.canvas create rectangle [expr {min($x0,$x)}] [expr {min($y0,$y)}] [expr {max($x0,$x)}] [expr {max($y0,$y)}] -outline #e87913 -width 2 -dash {5 3} -tags selection_drag
        ::GX::native2DCanvasClipItems $w.canvas $state($w,scene) [$w.canvas find withtag selection_drag]
    }
}
proc ::GX::DatasetCurveFit::_mouseUp {w x y stateBits} {
    variable state
    if {$state($w,source) eq "" || ![info exists state($w,press)]} return
    lassign $state($w,press) x0 y0 bits
    unset state($w,press)
    $w.canvas delete selection_drag
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
            ::GX::Native2D::core select $scene $source $index $mode
            if {$mode eq "replace"} {set state($w,rects) {}}
        } elseif {!$extended} {::GX::Native2D::core clear $scene;set state($w,rects) {}}
    }
    set state($w,status) "[llength [selectedIndices $w]] CORE points selected for fitting."
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_rememberNativeView {w} {
    variable state
    lassign [lindex [::GX::Native2D::core view_requested $state($w,scene)] 6] xmin ymin xmax ymax
    set state($w,viewBounds) [list $xmin $xmax $ymin $ymax]
}
proc ::GX::DatasetCurveFit::_zoom {w factor {px ""} {py ""}} {
    variable state
    if {$state($w,source) eq ""&&$state($w,records) eq {}} return
    if {$px eq ""} {lassign [_plotFrame $w] left right top bottom;set px [expr {($left+$right)/2.0}];set py [expr {($top+$bottom)/2.0}]}
    ::GX::Native2D::core zoom $state($w,scene) $factor [list $px $py]
    _rememberNativeView $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_panDown {w x y} {
    variable state
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
    unset -nocomplain state($w,pan)
    _saveState $w
}
proc ::GX::DatasetCurveFit::_resetView {w} {
    variable state
    set state($w,viewBounds) {}
    _saveState $w
    redraw $w
}
proc ::GX::DatasetCurveFit::_wheel {w delta x y} {
    if {$delta > 0} {_zoom $w 0.85 $x $y} elseif {$delta < 0} {_zoom $w 1.18 $x $y}
}
proc ::GX::DatasetCurveFit::_closeWindow {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} {set state($w,closeRequested) 1;_sourceCancel $w;return}
    if {[catch {
        _saveState $w
        if {$state($w,documentId) ne ""} {::GX::interactiveDocumentResourceCollect $state($w,documentId)}
    } err]} {
        tk_messageBox -parent $w -icon error -type ok -title "Dataset Curve Fit" -message "Could not save viewer state: $err"
        return
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
    ::GX::uiFieldWindowFit $w 1420 980
    wm protocol $w WM_DELETE_WINDOW [list ::GX::DatasetCurveFit::_closeWindow $w]
    bind $w <Escape> [list ::GX::DatasetCurveFit::_sourceCancel $w]
    ttk::frame $w.source -padding 5;pack $w.source -fill x
    foreach {field label width} {dataset Dataset 24 x X 18 y Y 18} {
        ttk::label $w.source.l_$field -text $label
        if {$field eq "dataset"} {set variable dataset} else {set variable "display[string toupper $field]"}
        ttk::combobox $w.source.$field -textvariable ::GX::DatasetCurveFit::state($w,$variable) -state readonly -width $width
        pack $w.source.l_$field $w.source.$field -side left -padx 4
    }
    ::GX::datasetSelectorAttach $w.source.dataset ::GX::DatasetCurveFit::datasets
    if {$state($w,dataset) ni [datasets]} {set state($w,dataset) [lindex [datasets] 0]}
    bind $w.source.dataset <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiDataset $w]]
    foreach field {x y} {bind $w.source.$field <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSelectVariable $w $field]}
    ttk::frame $w.samples -padding 5;pack $w.samples -fill x
    ttk::label $w.samples.label -text "Built-in / Test sample"
    ttk::combobox $w.samples.choice -textvariable ::GX::DatasetCurveFit::state($w,sample) -values [dict keys [sampleCatalog]] -state readonly -width 24
    ttk::button $w.samples.load -text "Open sample in fitter" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiLoadSample $w]]
    ttk::button $w.samples.publish -text "Publish sample as Dataset..." -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPublishSample $w]]
    pack $w.samples.label $w.samples.choice $w.samples.load $w.samples.publish -side left -padx 4
    ttk::checkbutton $w.source.ids -text "Show variable IDs" -variable ::GX::DatasetCurveFit::state($w,showIds) -command [list ::GX::DatasetCurveFit::_uiVariableChoices $w]
    pack $w.source.ids -side left -padx 4
    ttk::frame $w.filter -padding 5;pack $w.filter -fill x
    ttk::label $w.filter.title -text "Filters (all conditions must match)"
    ttk::combobox $w.filter.variable -textvariable ::GX::DatasetCurveFit::state($w,displayFilterVar) -state readonly -width 20
    ttk::combobox $w.filter.operator -textvariable ::GX::DatasetCurveFit::state($w,filterOp) -state readonly -width 10
    ttk::entry $w.filter.value -textvariable ::GX::DatasetCurveFit::state($w,filterValue) -width 27
    ttk::button $w.filter.add -text "Add filter" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiAddFilter $w]]
    ttk::button $w.filter.remove -text "Remove selected" -command [list ::GX::DatasetCurveFit::_uiRemoveFilter $w]
    ttk::button $w.filter.load -text "Add Dataset curve" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiLoad $w]]
    ttk::button $w.filter.cancel -text "Cancel operation" -state disabled -command [list ::GX::DatasetCurveFit::_sourceCancel $w]
    foreach item {title variable operator value add remove load cancel} {pack $w.filter.$item -side left -padx 3}
    bind $w.filter.variable <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSelectVariable $w filterVar]
    listbox $w.filters -height 1 -exportselection 0;pack $w.filters -fill x -padx 8
    ttk::frame $w.settings -padding 5;pack $w.settings -fill x
    ttk::label $w.settings.l_orientation -text "Fit orientation"
    ttk::combobox $w.settings.orientation -textvariable ::GX::DatasetCurveFit::state($w,orientationLabel) -state readonly -values {{Y = f(X)} {X = f(Y)} {R = f(theta) (experimental)}} -width 26
    pack $w.settings.l_orientation $w.settings.orientation -side left -padx 4
    bind $w.settings.orientation <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiOrientation $w]]
    foreach {field label values width} {model Model {linear polynomial exponential power_law gaussian circular_arc quadratic_bezier cubic_bezier pchip smoothing_spline fourier parametric_polynomial parametric_spline} 19 scope {Fit points} {all selected} 10 domain {Output domain} {source range} 12} {
        ttk::label $w.settings.l_$field -text $label
        ttk::combobox $w.settings.$field -textvariable ::GX::DatasetCurveFit::state($w,$field) -values $values -state readonly -width $width
        pack $w.settings.l_$field $w.settings.$field -side left -padx 3
    }
    bind $w.settings.model <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiModel $w]
    bind $w.settings.domain <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_uiDomainFields $w]
    ttk::button $w.settings.parametric -text "Parametric settings…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_parametricSettings $w]]
    pack $w.settings.parametric -side left -padx 4
    ttk::button $w.settings.polar -text "Radial settings…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_polarSettings $w]]
    pack $w.settings.polar -side left -padx 4
    ttk::frame $w.parameters -padding 5;pack $w.parameters -fill x
    foreach {field label width} {degree Degree 6 initial {Initial parameters} 18 period {Fourier period (blank = auto)} 15 smoothing {Smoothing lambda} 10 min {X / t min} 9 max {X / t max} 9 samples Samples 6} {
        ttk::label $w.parameters.l_$field -text $label
        ttk::entry $w.parameters.$field -textvariable ::GX::DatasetCurveFit::state($w,$field) -width $width
        pack $w.parameters.l_$field $w.parameters.$field -side left -padx 3
    }
    ttk::frame $w.actions -padding 5;pack $w.actions -fill x
    ttk::button $w.actions.clear -text "Clear point selection" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiClear $w]]
    ttk::button $w.actions.preview -text "Preview fit" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPreview $w]]
    ttk::button $w.actions.accept -text "Accept as new CORE curve" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiAccept $w]]
    ttk::button $w.actions.publish -text "Publish as Dataset..." -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPublish $w]]
    ttk::button $w.actions.export -text "Export accepted fit CSV" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiExport $w]]
    foreach item {clear preview accept publish export} {pack $w.actions.$item -side left -padx 4}
    foreach item {preview accept publish export} {$w.actions.$item configure -state disabled}
    ttk::frame $w.selection -padding 5;pack $w.selection -fill x
    ttk::label $w.selection.l_mode -text "Rectangle mode"
    ttk::combobox $w.selection.mode -textvariable ::GX::DatasetCurveFit::state($w,rectMode) -values {Replace Add Subtract} -state readonly -width 10
    ttk::button $w.selection.remove -text "Remove last rectangle" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiRemoveLastRect $w]]
    ttk::button $w.selection.zoomin -text "Zoom in" -command [list ::GX::DatasetCurveFit::_zoom $w 0.7]
    ttk::button $w.selection.zoomout -text "Zoom out" -command [list ::GX::DatasetCurveFit::_zoom $w 1.4]
    ttk::button $w.selection.reset -text "Fit view" -command [list ::GX::DatasetCurveFit::_resetView $w]
    ttk::label $w.selection.help -text "Shift-drag adds; Alt-drag subtracts. Middle-drag pans; wheel zooms."
    foreach item {l_mode mode remove zoomin zoomout reset help} {pack $w.selection.$item -side left -padx 4}
    ttk::frame $w.presentation -padding 5;pack $w.presentation -fill x
    ttk::button $w.presentation.settings -text "Grid / background / aspect…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_viewSettings $w]]
    pack $w.presentation.settings -side left -padx 4
    ttk::checkbutton $w.presentation.residuals -text "Show residual panel" -variable ::GX::DatasetCurveFit::state($w,showResiduals) -command [list ::GX::DatasetCurveFit::_residualPanel $w]
    pack $w.presentation.residuals -side left -padx 4
    ttk::scale $w.presentation.split -from .3 -to .9 -orient horizontal -variable ::GX::DatasetCurveFit::state($w,residualFraction) -command [list ::GX::DatasetCurveFit::_residualResize $w]
    pack $w.presentation.split -side left -padx 4
    ttk::label $w.presentation.coordinates -textvariable ::GX::DatasetCurveFit::state($w,coordinates)
    pack $w.presentation.coordinates -side left -padx 8
    ttk::frame $w.accepted -padding 5;pack $w.accepted -fill x
    ttk::label $w.accepted.title -text "Accepted fits"
    listbox $w.fits -height 2 -exportselection 0;pack $w.accepted.title -side left -padx 4
    ttk::button $w.accepted.visibility -text "Show / Hide" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiFitAction $w visibility]]
    ttk::button $w.accepted.delete -text "Delete fit" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiFitAction $w delete]]
    ttk::button $w.accepted.publish -text "Publish selected fit as Dataset…" -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_uiPublishAccepted $w]]
    pack $w.accepted.visibility $w.accepted.delete $w.accepted.publish -side left -padx 4
    pack $w.fits -fill x -padx 8
    _workspaceGui $w
    canvas $w.canvas -background white -height 400;pack $w.canvas -fill both -expand 1 -padx 8 -pady 4
    ttk::label $w.result -textvariable ::GX::DatasetCurveFit::state($w,report) -justify left -wraplength 1240;pack $w.result -fill x -padx 8
    ttk::treeview $w.residuals -columns {row x observed fitted residual} -show headings -height 3
    foreach {column heading width} {row {Dataset row} 100 x X 140 observed {Observed Y} 140 fitted {Fitted Y} 140 residual {Residual (observed - fit)} 210} {
        $w.residuals heading $column -text $heading
        $w.residuals column $column -width $width -stretch 1
    }
    pack $w.residuals -fill x -padx 8
    set state($w,residualStart) 0;set state($w,residualStatus) "Exact residual data is retained when this panel is hidden."
    ttk::frame $w.residualPager
    foreach {key text step} {previous Previous -200 next Next 200 first First -100000000000 last Last 100000000000} {
        ttk::button $w.residualPager.$key -text $text -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_residualPageUi $w $step]]
        pack $w.residualPager.$key -side left -padx 4
    }
    ttk::label $w.residualPager.status -textvariable ::GX::DatasetCurveFit::state($w,residualStatus);pack $w.residualPager.status -side left -padx 6
    pack $w.residualPager -after $w.residuals -side bottom -fill x -padx 8
    ttk::label $w.status -textvariable ::GX::DatasetCurveFit::state($w,status) -anchor w;pack $w.status -fill x -padx 8 -pady 4
    # Reserve diagnostics before allocating the expanding plot; otherwise a
    # remote screen clamp can leave report/status and residual paging unmapped.
    pack $w.status $w.residuals $w.residualPager $w.result -before $w.canvas -side bottom -fill x -padx 8
    bind $w.canvas <ButtonPress-1> [list ::GX::DatasetCurveFit::_mouseDown $w %x %y %s]
    bind $w.canvas <Motion> [list ::GX::DatasetCurveFit::_coordinates $w %x %y]
    bind $w.canvas <B1-Motion> [list ::GX::DatasetCurveFit::_mouseMove $w %x %y]
    bind $w.canvas <ButtonRelease-1> [list ::GX::DatasetCurveFit::_mouseUp $w %x %y %s]
    bind $w.canvas <ButtonPress-2> [list ::GX::DatasetCurveFit::_panDown $w %x %y]
    bind $w.canvas <B2-Motion> [list ::GX::DatasetCurveFit::_panMove $w %x %y]
    bind $w.canvas <ButtonRelease-2> [list ::GX::DatasetCurveFit::_panUp $w]
    bind $w.canvas <MouseWheel> [list ::GX::DatasetCurveFit::_wheel $w %D %x %y]
    bind $w.canvas <Button-4> [list ::GX::DatasetCurveFit::_zoom $w 0.85 %x %y]
    bind $w.canvas <Button-5> [list ::GX::DatasetCurveFit::_zoom $w 1.18 %x %y]
    bind $w.canvas <Configure> [list ::GX::DatasetCurveFit::redraw $w]
    foreach frame {source samples filter settings parameters actions selection presentation accepted workspace.actions residualPager} {
        bind $w.$frame <Configure> [list ::GX::native2DToolbarLayout $w.$frame %w]
    }
    _layout $w
    if {$state($w,dataset) ne ""} {_uiSafe $w [list ::GX::DatasetCurveFit::_uiDataset $w]}
    _uiModelFields $w
    _uiDomainFields $w
    if {$state($w,sessionToken) ne ""} {_uiSafe $w [list ::GX::DatasetCurveFit::_restoreState $w $requestedDataset]}
    if {$requestedWorkspace eq "new"} {_saveState $w}
    set state($w,catalogSubscription) [::GX::datasetCatalogSubscribe [list ::GX::DatasetCurveFit::_workspaceCatalog $w]]
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
    set report [_runNumeric $model 2 {} $points $points {parameter 0 1 257} [dict create orientation parametric]]
    _native;set scene [::GX::Native2D::core scene]
    try {set definition [::GX::Native2D::core interaction_from_fit $scene $family [split [dict get $report parameters] ,]]} finally {::GX::Native2D::core destroy $scene}
    return [dict create definition $definition quality [dict remove $report fitted residual] working_unit $unit method scientific_fit numeric_api NUMERIC_API_v1 model $model approximation 1]
}

source [file join [file dirname [info script]] curve_fit_layout.tcl]
