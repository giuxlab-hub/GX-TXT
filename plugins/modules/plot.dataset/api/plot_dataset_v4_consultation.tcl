# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical, asynchronously prepared Curve Source consultation uses the same
# public Plot v4 model, renderer, source guards and widget controller as plots.
proc ::GX::PlotDatasetAPIv4::scientificModel {datasetId xId series coordinateContext {options {}}} {
    _ready
    if {$datasetId eq {} || $xId eq {} || ![llength $series] || [llength $series]>16} {
        error {Scientific consultation requires a canonical Dataset, explicit X and one to sixteen prepared traces}
    }
    if {[dict get $coordinateContext dataset_id] ne $datasetId ||
        [::GX::datasetCoordinateRead $::GX::currentSession $datasetId] ne $coordinateContext} {
        error {Scientific coordinate context changed; prepare the selected source again}
    }
    ::GX::datasetVariableV3ById $datasetId $xId
    set output {};set ids {};set completeBounds {};set commonY {};set firstPresentation {}
    foreach trace $series {
        foreach field {id y_variable_id label source_descriptor display} {
            if {![dict exists $trace $field]} {error "Prepared scientific trace is missing $field"}
        }
        set id [dict get $trace id];set yId [dict get $trace y_variable_id]
        if {$id eq {} || $id in $ids} {error {Prepared scientific trace IDs must be nonempty and unique}}
        lappend ids $id
        ::GX::datasetVariableV3ById $datasetId $yId
        set descriptor [dict get $trace source_descriptor]
        foreach field {api_id api_version source_id row_identity_kind source_identities request} {
            if {![dict exists $descriptor $field]} {error "Prepared trace descriptor is missing $field"}
        }
        if {[dict get $descriptor api_id] ne {CURVE_SOURCE_API_v1} || [dict get $descriptor api_version]!=1 ||
            [dict get $descriptor row_identity_kind] ne {dataset_row}} {
            error {Scientific consultation requires a public Curve Source with canonical Dataset row identities}
        }
        set sourceIds [lmap identity [dict get $descriptor source_identities] {dict get $identity dataset_id}]
        if {$datasetId ni $sourceIds} {error {Prepared trace does not identify the selected canonical Dataset}}
        set validation [::GX::curveSourceValidateSnapshot $::GX::currentSession $descriptor]
        if {![dict get $validation valid]} {error "Prepared scientific source is [dict get $validation status]; prepare it again"}
        foreach key {dataset_id x_variable_id y_variable_id} expected [list $datasetId $xId $yId] {
            if {![dict exists $descriptor request $key] || [dict get $descriptor request $key] ne $expected} {
                error {Prepared scientific source Dataset/Variable identities differ from the selected trace}
            }
        }
        set display [dict get $trace display]
        foreach field {source_id points canonical_points source_rows breaks full_bounds coordinate_presentation} {
            if {![dict exists $display $field]} {error "Prepared scientific display is missing $field"}
        }
        if {[dict get $display source_id] ne [dict get $descriptor source_id]} {error {Prepared display belongs to a different Curve Source request}}
        set presentation [dict get $display coordinate_presentation]
        if {[dict get $presentation context] ne $coordinateContext ||
            [dict get $presentation variable_ids] ne [list $xId $yId]} {
            error {Prepared scientific coordinates do not belong to the selected context and Variables}
        }
        if {$firstPresentation eq {}} {set firstPresentation $presentation}
        # Overlay admission uses the declared coordinate policy, not matching
        # captions or dimensions alone. Do not mix different units or pivots.
        if {[dict exists $coordinateContext variables $yId]} {
            set settings [dict get $coordinateContext variables $yId];set policy {}
            foreach key {unit canonical_unit to_canonical from_canonical} {lappend policy [dict get $settings source $key]}
            foreach key {display_unit view_factor view_pivot} {lappend policy [dict get $settings $key]}
        } else {
            set meta [::GX::datasetVariableV3ById $datasetId $yId]
            set policy [list legacy [dict get $meta unit]]
        }
        if {$commonY ne {} && $commonY ne $policy} {error {Overlay Y variables require the same coordinate relation, display unit and magnification/pivot}}
        set commonY $policy
        set count [llength [dict get $display points]]
        if {!$count} {error {No finite X/Y pairs in the selected scientific source}}
        if {$count>4096 || $count!=[llength [dict get $display canonical_points]] ||
            $count!=[llength [dict get $display source_rows]]} {
            error {Prepared scientific point and canonical-row mappings must agree within the display budget}
        }
        foreach row [dict get $display source_rows] {
            if {![string is entier -strict $row] || $row<0} {error {Canonical source rows require exact nonnegative integer ordinals}}
        }
        foreach key {points canonical_points} {
            foreach point [dict get $display $key] {
                if {[llength $point]!=2} {error {Scientific display points require two coordinates}}
                foreach value $point {
                    if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {Prepared scientific point coordinates must be finite}}
                }
            }
        }
        set bounds [dict get $display full_bounds]
        # Endpoint conversion is sufficient only for an admitted affine map.
        # Reuse the existing exact public Curve Source pass for nonlinear maps;
        # a reduced display must never become the authority for fit bounds.
        set rescan 0
        foreach vid [list $xId $yId] target [dict get $presentation display_units] {
            if {![dict exists $coordinateContext variables $vid]} continue
            set source [dict get $coordinateContext variables $vid source]
            set native [dict get $source unit]
            if {[_get $source value_kind {}] eq {elapsed_time} && [_get $source value_format {}] eq {hms}} {set native s}
            if {![dict get [::GX::datasetCoordinateSnapshotAffinePlan $coordinateContext $vid $native [dict create unit $target]] affine]} {set rescan 1}
        }
        if {$rescan} {
            set progress [list ::GX::PlotDatasetAPIv4::_scientificBoundsProgress [::GX::interactiveDocumentSessionToken] $coordinateContext [_get $options progress {}]]
            set source [::GX::curveSourceOpen $::GX::currentSession [dict get $descriptor request] $progress]
            try {
                set exact [_exactPresentationBounds $source $coordinateContext {*}[dict get $presentation display_units] {} left $progress]
            } finally {::GX::curveSourceClose $source}
            set bounds [dict get $exact bounds]
            dict set display full_bounds $bounds
            dict set display coordinate_bounds_receipt $exact
        }
        if {[llength $bounds]!=4} {error {Scientific fit requires complete finite source bounds}}
        foreach value $bounds {
            if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {Scientific fit requires complete finite source bounds}}
        }
        if {[lindex $bounds 0]>[lindex $bounds 2] || [lindex $bounds 1]>[lindex $bounds 3]} {error {Scientific source bounds must be ordered}}
        if {$completeBounds eq {}} {set completeBounds $bounds} else {
            foreach lo {0 1} hi {2 3} {
                lset completeBounds $lo [expr {min([lindex $completeBounds $lo],[lindex $bounds $lo])}]
                lset completeBounds $hi [expr {max([lindex $completeBounds $hi],[lindex $bounds $hi])}]
            }
        }
        foreach gap [dict get $display breaks] {
            if {![string is entier -strict $gap] || $gap<0 || $gap>=$count} {error {Prepared scientific gap indices must address retained points}}
        }
        # A valid exact predicate can retain one observation. It needs the
        # existing point painter; a markerless one-vertex line is invisible.
        set item [dict merge $display [dict create id $id label [dict get $trace label] kind [expr {$count==1?{scatter}:{line}}] axis left \
            dataset_id $datasetId x_variable_id $xId y_variable_id $yId \
            source_descriptor $descriptor coordinate_context $coordinateContext \
            row_filters [_get $trace filters {}] \
            style [dict create color auto line_style [expr {$count==1?{none}:{solid}}] line_width 2 marker [expr {$count==1?{circle}:{none}}]]]]
        lappend output $item
    }
    set labels [_get $options axis_labels {}]
    set reference $completeBounds
    foreach lo {0 1} hi {2 3} {
        set a [lindex $reference $lo];set b [lindex $reference $hi]
        set pad [expr {$a==$b?max(abs($a)*.03,1e-12):($b-$a)*.03}]
        lset reference $lo [expr {$a-$pad}];lset reference $hi [expr {$b+$pad}]
    }
    set view $reference;set ranges {};set axes {}
    foreach lo {0 1} hi {2 3} vid [dict get $firstPresentation variable_ids] side {x left} labelKey {x y} unit [dict get $firstPresentation display_units] {
        if {[dict exists $coordinateContext variables $vid]} {
            set canonical [dict get [::GX::datasetCoordinateSnapshotValues $coordinateContext $vid [list [lindex $reference $lo] [lindex $reference $hi]] {direction inverse}] values]
            set range [::GX::datasetCoordinateSnapshotViewRange $coordinateContext $vid [lsort -real $canonical]]
            set converted [lsort -real [dict get [::GX::datasetCoordinateSnapshotValues $coordinateContext $vid [dict get $range canonical_range]] values]]
            if {[dict get $coordinateContext variables $vid view_factor]!=1} {
                lset view $lo [lindex $converted 0];lset view $hi [lindex $converted 1]
            }
            lappend ranges $range
        } else {lappend ranges [dict create variable_id $vid coordinate_policy applicable_false reason {Variable retains its canonical presentation}]}
        if {[lindex $view $lo]>=[lindex $view $hi]} {error {Coordinate display collapses the representable viewport}}
        dict set axes $side [dict create label [_get $labels $labelKey {}] display_unit $unit min [lindex $view $lo] max [lindex $view $hi]]
    }
    set firstPresentation [dict merge $firstPresentation [dict create reference_display_bounds $reference view_bounds $view ranges $ranges bounds_authority curve_source_full_finite_pass]]
    set aspect [_get $options aspect auto]
    if {$aspect ni {auto xy_equal}} {error {Scientific plot aspect must be auto or xy_equal}}
    set native [_get $options native_presentation {}]
    if {![dict exists $native legend placement]} {dict set native legend placement none}
    set model [dict create title [_get $options title {}] \
        panels [list [dict create id main title {} axes $axes aspect $aspect series $output]] \
        native_presentation $native \
        scientific_consultation [dict create dataset_id $datasetId x_variable_id $xId \
            coordinate_context $coordinateContext coordinate_presentation $firstPresentation \
            source_values_modified 0 calibration_applied 0]]
    _modelChecks $model {retain_presentation 1}
    return $model
}

proc ::GX::PlotDatasetAPIv4::_scientificBoundsProgress {sessionToken context progress receipt} {
    if {$sessionToken ne [::GX::interactiveDocumentSessionToken]} {error {Scientific bounds preparation cancelled by Session change}}
    if {[::GX::datasetCoordinateRead $::GX::currentSession [dict get $context dataset_id]] ne $context} {error {Coordinate settings changed during bounds preparation; select Plot again}}
    if {$progress ne {}} {uplevel #0 [list {*}$progress $receipt]}
}

# Retain the painter's real owner, limits and source identities. The extra
# coordinate receipt describes this consultation, never a second transform.
proc ::GX::PlotDatasetAPIv4::_scientificReceipt {model receipt} {
    if {[dict exists $model derived_comparison] && [dict exists $receipt axes]} {
        dict set receipt derived_comparison [dict get $model derived_comparison]
    }
    if {![dict exists $model scientific_consultation] || ![dict exists $receipt axes]} {return $receipt}
    set presentation [dict get $model scientific_consultation coordinate_presentation]
    set ranges {};foreach axis [dict get $receipt axes] {if {[dict get $axis panel_id] eq {main}} {dict set ranges [dict get $axis axis] [dict get $axis limits]}}
    if {[dict exists $ranges x] && [dict exists $ranges left]} {
        lassign [dict get $ranges x] x0 x1;lassign [dict get $ranges left] y0 y1
        dict set presentation view_bounds [list $x0 $y0 $x1 $y1]
    }
    dict set receipt coordinate_presentation $presentation
    dict set receipt scientific_consultation [dict get $model scientific_consultation]
    return $receipt
}

proc ::GX::PlotDatasetAPIv4::widgetPointer {path operation x y {factor {}}} {
    switch -- $operation {
        pan_start {_dragStart $path $x $y}
        pan {_drag $path $x $y}
        zoom {
            if {![string is double -strict $factor] || ![expr {$factor>0 && $factor<Inf}]} {error {Zoom requires a finite positive factor}}
            _wheel $path $factor $x $y
        }
        fit {_fit $path}
        default {error {Scientific Plot pointer operation must be pan_start, pan, zoom or fit}}
    }
}

proc ::GX::PlotDatasetAPIv4::widgetRetain {path reason} {
    variable widgets
    set record [_widget $path 0]
    if {[dict exists $record pending]} {after cancel [dict get $record pending];dict unset record pending}
    if {[dict exists $record drag]} {dict unset record drag}
    dict set record interaction_error [dict create message $reason retained 1]
    dict set record last_error $reason
    dict set widgets $path $record
    return [dict create widget $path state previous_render reason $reason]
}
