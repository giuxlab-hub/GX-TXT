# SPDX-License-Identifier: GPL-3.0-or-later
# Workspace presentation is distinct from Native geometry and Dataset policy.
# The only cached Dataset object is an explicitly verified CORE read snapshot.
proc ::GX::CurveWorkbench::_coordinateContext {w id} {
    variable st
    set record [_record $w $id]
    set signature [list [dict get $record source] [dict get $record x] [dict get $record y] [_coordinateUnits $record] [::GX::datasetPublicationV2DictDefault $record source_descriptor {}] [::GX::datasetPublicationV2DictDefault $record source_assumed_units {}]]
    if {[dict exists $st($w,coordinateCache) $id]&&[dict get $st($w,coordinateCache) $id signature] eq $signature} {return [dict get $st($w,coordinateCache) $id]}
    set result [dict create signature $signature context {} reason {}]
    if {[dict get $record source] ne {}} {
        if {[catch {
            set context [::GX::datasetCoordinateRead [_session] [dict get $record source]]
            if {[dict exists $record source_descriptor]} {
                foreach identity [dict get $record source_descriptor source_identities] {
                    if {[dict get $identity dataset_id] eq [dict get $record source]&&[dict get $identity sha256] ne [dict get $context source_sha256]} {error {Coordinate policy belongs to changed source bytes; reload the source binding}}
                }
                foreach variable [dict get $record source_descriptor variables] {
                    set vid [dict get $variable variable_id]
                    if {$vid ni [list [dict get $record x] [dict get $record y]]} continue
                    dict for {key value} [dict get $context variables $vid source] {
                        if {[dict get $variable $key] ne $value} {error {Coordinate source schema changed; reload the source binding}}
                    }
                }
            }
            dict set result context $context
        } reason]} {dict set result reason $reason}
    }
    dict set st($w,coordinateCache) $id $result
    return $result
}
proc ::GX::CurveWorkbench::_coordinateAxis {w id axis} {
    variable st
    set record [_record $w $id];set vid [dict get $record $axis]
    set unit [lindex [_coordinateUnits $record] [expr {$axis eq "x"?0:1}]]
    set label [::GX::datasetPublicationV2DictDefault $record source_${axis}_name $vid]
    set cache [_coordinateContext $w $id];set context [dict get $cache context]
    set assumptions [::GX::datasetPublicationV2DictDefault $record source_assumed_units {}]
    set assumption [::GX::datasetPublicationV2DictDefault $assumptions $vid {}]
    set target $unit
    if {$context ne {}} {set target [dict get $context variables $vid display_unit]}
    if {$target eq {}&&$assumption ne {}} {set target $unit}
    if {[dict exists $st($w,coordinatePresentation) $id $axis]&&[dict get $cache reason] eq {}} {set target [dict get $st($w,coordinatePresentation) $id $axis]}
    return [dict create context $context variable_id $vid native_unit $unit display_unit $target source_unit_assumption $assumption label $label reason [dict get $cache reason]]
}
proc ::GX::CurveWorkbench::_coordinateOptions {info options} {
    if {[dict get $info source_unit_assumption] ne {}} {dict set options source_unit_assumption [dict get $info source_unit_assumption]}
    return $options
}
proc ::GX::CurveWorkbench::_coordinateValues {w id axis values {direction forward}} {
    set info [_coordinateAxis $w $id $axis]
    set context [dict get $info context];set vid [dict get $info variable_id]
    set native [dict get $info native_unit];set target [dict get $info display_unit]
    if {$context eq {}} {
        if {$native eq $target} {return $values}
        if {$direction eq "inverse"} {return [::GX::unitRegistryConvertValues $target $native $values]}
        return [::GX::unitRegistryConvertValues $native $target $values]
    }
    # Geometry may have undergone an explicit whole-frame physical conversion.
    # Invert the Variable's declared relation back to source units first.
    if {$direction eq "inverse"} {set from $target;set to $native} else {set from $native;set to $target}
    set values [dict get [::GX::datasetCoordinateSnapshotValues $context $vid $values [_coordinateOptions $info [dict create unit $from direction inverse]]] values]
    return [dict get [::GX::datasetCoordinateSnapshotValues $context $vid $values [_coordinateOptions $info [dict create unit $to]]] values]
}
proc ::GX::CurveWorkbench::_coordinatePoint {w id point {direction forward}} {
    set result {}
    foreach axis {x y} value $point {lappend result [lindex [_coordinateValues $w $id $axis [list $value] $direction] 0]}
    return $result
}
proc ::GX::CurveWorkbench::_coordinateLabel {w id axis} {
    set info [_coordinateAxis $w $id $axis];set unit [dict get $info display_unit]
    return "[dict get $info label] ([expr {$unit eq {}?{undeclared}:$unit}])"
}
proc ::GX::CurveWorkbench::_coordinateKey {w id} {
    variable st
    return [list [_coordinateContext $w $id] [::GX::datasetPublicationV2DictDefault $st($w,coordinatePresentation) $id {}]]
}
proc ::GX::CurveWorkbench::_coordinateTick {w axis value} {
    variable st
    if {$st($w,active) ne {}&&[dict exists $st($w,curves) $st($w,active)]} {
        if {[catch {set value [lindex [_coordinateValues $w $st($w,active) $axis [list $value]] 0]}]} {return undefined}
    }
    return [format %.4g $value]
}
proc ::GX::CurveWorkbench::_coordinateReadout {w device} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} {return [::GX::native2DCoordinateReadout $st($w,scene) $device]}
    set id $st($w,active);set point [::GX::Native2D::core world $st($w,scene) $device]
    if {[::GX::Native2D::core coordinate_mode $st($w,scene)] eq "polar"} {
        set ux [_coordinateAxis $w $id x];set uy [_coordinateAxis $w $id y]
        if {[dict get $ux native_unit] eq [dict get $uy native_unit]&&[dict get $ux display_unit] eq [dict get $uy display_unit]} {
            set plan [::GX::unitRegistryAffinePlan [dict get $ux native_unit] [dict get $ux display_unit]]
            if {[dict get $plan affine]&&[dict get $plan offset]==0&&[dict get $plan scale]>0} {
                lassign [::GX::Native2D::core to_polar $st($w,scene) $point] radius theta
                set angle [expr {[dict get [::GX::Native2D::core polar $st($w,scene)] degrees]?"deg":"rad"}]
                return [format "Polar: r %.7g %s, theta %.7g %s" [expr {$radius*[dict get $plan scale]}] [dict get $ux display_unit] $theta $angle]
            }
        }
    }
    if {[catch {set displayed [_coordinatePoint $w $id $point]} reason]} {return "Coordinate conversion unavailable: $reason"}
    set text {};foreach axis {x y} value $displayed {lappend text "[string toupper $axis] [format %.7g $value] [dict get [_coordinateAxis $w $id $axis] display_unit]"}
    set reason [dict get [_coordinateContext $w $id] reason]
    if {$reason ne {}} {lappend text "canonical frozen frame; $reason"}
    # Cartesian axes remain meaningful when unlike dimensions forbid a radius.
    return [join $text {, }]
}
proc ::GX::CurveWorkbench::_coordinatePolicy {w} {
    variable st
    set st($w,coordinatePolicy) {Canonical coordinates}
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} return
    set cache [_coordinateContext $w $st($w,active)]
    append st($w,coordinatePolicy) " · display: [_coordinateLabel $w $st($w,active) x], [_coordinateLabel $w $st($w,active) y]"
    set outside 0;dict for {id record} $st($w,curves) {if {![_coordinateInFrame $w $record]} {incr outside}}
    if {$outside} {append st($w,coordinatePolicy) " · $outside curve(s) in other axis frames; select one to switch frames"}
    if {[dict get $cache reason] ne {}} {append st($w,coordinatePolicy) " · [dict get $cache reason]"}
    if {$st($w,coordinateView) ne {}} {
        set basis [dict get $st($w,coordinateView) basis]
        if {[dict exists $st($w,curves) $basis]} {
            set c [dict get [_coordinateContext $w $basis] context]
            if {$c ne {}} {
                set record [_record $w $basis];set x [dict get $record x];set y [dict get $record y]
                append st($w,coordinatePolicy) " · view basis: [dict get $record name], X ×[dict get $c variables $x view_factor], Y ×[dict get $c variables $y view_factor]"
            }
        }
    }
}
proc ::GX::CurveWorkbench::_coordinateOpen {w} {
    variable st
    set id [_active $w];set fields {};set initial {};set labels {}
    foreach axis {x y} {
        set info [_coordinateAxis $w $id $axis];set unit [dict get $info native_unit]
        if {[dict get $info reason] ne {}} {error [dict get $info reason]}
        set choices [list $unit [dict get $info display_unit]]
        foreach target [::GX::unitSelectorCandidates] {
            if {$unit eq {}} continue
            if {[dict get $info context] ne {}} {
                set context [dict get $info context];set vid [dict get $info variable_id]
                if {[catch {::GX::datasetCoordinateSnapshotValues $context $vid {} [_coordinateOptions $info [dict create unit $target]]}]} continue
            } elseif {[catch {::GX::unitRegistryConversionPlan $unit $target}]} continue
            lappend choices $target
        }
        dict set fields $axis [dict create type choice label "[string toupper $axis] display unit" values [lsort -unique $choices]]
        dict set initial $axis [dict get $info display_unit]
        lappend labels "[string toupper $axis] geometry: [expr {$unit eq {}?{undeclared}:$unit}]"
    }
    set st($w,coordinateDraftKey) [_coordinateKey $w $id]
    ::GX::uiFieldFormCreate $w.axisunits {Independent scientific axis display} $fields $initial [list ::GX::CurveWorkbench::_coordinateApply $w $st($w,token) $id] $w
    ttk::label $w.axisunits.explanation -text "[join $labels {; }]. Coordinates and calculations remain canonical. Dataset magnification and calibration are separate settings." -wraplength 580
    pack $w.axisunits.explanation -side top -fill x -before $w.axisunits.viewport -padx 12 -pady 8
    ttk::button $w.axisunits.actions.defaults -text {Use Dataset defaults} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateDefaults $w $id]]
    pack $w.axisunits.actions.defaults -side left -padx 4
}
proc ::GX::CurveWorkbench::_coordinateApply {w token id values} {
    variable st
    if {$token ne [::GX::interactiveDocumentSessionToken]||$token ne $st($w,token)||![dict exists $st($w,curves) $id]} {error {Source or Session changed; reopen axis settings}}
    if {$st($w,coordinateDraftKey) ne [_coordinateKey $w $id]} {error {Coordinate settings changed; reopen axis settings}}
    set old $st($w,coordinatePresentation)
    try {
        dict set st($w,coordinatePresentation) $id $values
        foreach axis {x y} {_coordinateValues $w $id $axis {}}
    } on error {message options} {set st($w,coordinatePresentation) $old;return -options $options $message}
    set st($w,coordinateDraftKey) [_coordinateKey $w $id]
    set st($w,pointTableSignature) {};_pointList $w;_comparisonRefresh $w;_draw $w;_save $w
}
proc ::GX::CurveWorkbench::_coordinateDefaults {w id} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen Workbench}}
    dict unset st($w,coordinatePresentation) $id
    destroy $w.axisunits;set st($w,pointTableSignature) {};_pointList $w;_comparisonRefresh $w;_draw $w;_save $w
}
proc ::GX::CurveWorkbench::_coordinateDatasetOpen {w} {
    variable st
    set id [dict get [_record $w [_active $w]] source]
    if {$id eq {}} {error {Select geometry bound to a canonical Dataset}}
    ::GX::datasetCoordinateEditorOpen $id $w
}
proc ::GX::CurveWorkbench::_coordinateCatalogChanged {w receipt} {
    variable st
    if {![info exists st($w,coordinateCache)]} return
    set st($w,coordinateCache) {}
    if {[info exists st($w,coordinateRefresh)]} {after cancel $st($w,coordinateRefresh)}
    set st($w,coordinateRefresh) [after idle [list ::GX::CurveWorkbench::_coordinateRefresh $w]]
}
proc ::GX::CurveWorkbench::_coordinateRefresh {w} {
    variable st
    if {![winfo exists $w]||![info exists st($w,token)]||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} return
    unset -nocomplain st($w,coordinateRefresh)
    if {[catch {
        _coordinateMagnify $w 0
        set st($w,pointTableSignature) {};_pointList $w;_comparisonRefresh $w;_draw $w
    } message]} {set st($w,status) "Coordinate refresh: $message"}
}
proc ::GX::CurveWorkbench::_coordinateMagnify {w capture} {
    variable st
    if {$capture} {set st($w,coordinateView) [dict create basis $st($w,active) reference [lindex [::GX::Native2D::core view_requested $st($w,scene)] 6] applied {}]}
    if {$st($w,coordinateView) eq {}} return
    set id [dict get $st($w,coordinateView) basis]
    if {![dict exists $st($w,curves) $id]} return
    set cache [_coordinateContext $w $id];set context [dict get $cache context]
    if {$context eq {}} {
        if {$capture&&[dict get [_record $w $id] source] eq {}} {
            lassign [_coordinateUnits [_record $w $id]] ux uy
            ::GX::Native2D::core aspect $st($w,scene) [expr {$ux eq $uy?"xy_equal":"auto"}]
        }
        return
    }
    set record [_record $w $id];set policy {}
    foreach axis {x y} {set settings [dict get $context variables [dict get $record $axis]];lappend policy [dict get $settings view_factor] [dict get $settings view_pivot]}
    set signature [list [dict get $context source_sha256] [_coordinateUnits $record] $policy]
    if {!$capture&&[dict get $st($w,coordinateView) applied] eq $signature} return
    set bounds [dict get $st($w,coordinateView) reference];set next $bounds
    set record [_record $w $id];set independent 0
    lassign [_coordinateUnits $record] ux uy
    if {$ux ne $uy} {set independent 1}
    if {[dict get $context variables [dict get $record x] view_factor]!=[dict get $context variables [dict get $record y] view_factor]} {set independent 1}
    foreach axis {x y} lo {0 1} hi {2 3} {
        set info [_coordinateAxis $w $id $axis];set vid [dict get $info variable_id];set native [dict get $info native_unit]
        set range [dict get [::GX::datasetCoordinateSnapshotValues $context $vid [list [lindex $bounds $lo] [lindex $bounds $hi]] [_coordinateOptions $info [dict create unit $native direction inverse]]] values]
        set range [dict get [::GX::datasetCoordinateSnapshotViewRange $context $vid $range] canonical_range]
        set range [dict get [::GX::datasetCoordinateSnapshotValues $context $vid $range [_coordinateOptions $info [dict create unit $native]]] values]
        lset next $lo [lindex $range 0];lset next $hi [lindex $range 1]
    }
    set view [::GX::Native2D::core view_requested $st($w,scene)];lset view 6 $next
    # Existing host-level Native authority permits scientific axis frames;
    # the legacy CAD default remains equal scale. No geometry is rescaled.
    ::GX::Native2D::core aspect $st($w,scene) [expr {$independent?"auto":"xy_equal"}]
    ::GX::Native2D::core view $st($w,scene) $view
    dict set st($w,coordinateView) applied $signature
}
proc ::GX::CurveWorkbench::_coordinateRescaleView {w factor} {
    variable st
    if {$st($w,coordinateView) eq {}} return
    dict set st($w,coordinateView) reference [lmap value [dict get $st($w,coordinateView) reference] {expr {$value*$factor}}]
    dict set st($w,coordinateView) applied {}
    # Native has already rescaled the transient viewport. Refresh the policy
    # signature without discarding a subsequent user pan or zoom.
    set current [::GX::Native2D::core view_requested $st($w,scene)]
    _coordinateMagnify $w 0
    ::GX::Native2D::core view $st($w,scene) $current
}
proc ::GX::CurveWorkbench::_coordinateMetricLabel {id} {
    return [dict get {length {Geometric length} span_x {X span} span_y {Y span} signed_area {Signed area} length_span_ratio {Length / X span} signed_y_residual {Signed Y residual}} $id]
}
proc ::GX::CurveWorkbench::_coordinateMetricSelect {w} {
    variable st
    foreach id $st($w,metricAllowed) {if {[_coordinateMetricLabel $id] eq $st($w,metricLabel)} {set st($w,metric) $id;_metrics $w;return}}
    error {Unsupported metric selection}
}
proc ::GX::CurveWorkbench::_coordinateMetricPolicy {w} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} return
    lassign [_coordinateUnits [_record $w $st($w,active)]] x y
    set geometric [expr {$x ne {}&&$y ne {}&&![catch {::GX::native2DComparisonFrame path [list $x $y] [list $x $y]}]}]
    if {[_coordinateSourceRelations [_record $w $st($w,active)]] ne {}||[dict get [::GX::unitRegistryDefinition $x] conversion_kind] eq "opaque"||[dict get [::GX::unitRegistryDefinition $y] conversion_kind] eq "opaque"} {set geometric 0}
    set metrics [expr {$geometric?{length span_x span_y signed_area length_span_ratio signed_y_residual}:{signed_y_residual span_x span_y}}]
    if {$st($w,metric) ni $metrics} {set st($w,metric) [lindex $metrics 0]}
    set st($w,metricAllowed) $metrics;set st($w,metricLabel) [_coordinateMetricLabel $st($w,metric)]
    if {[winfo exists $w.validation.metric]} {$w.validation.metric configure -values [lmap id $metrics {_coordinateMetricLabel $id}]}
    set methods [expr {$geometric?{x path geometry}:{x}}]
    if {$st($w,compareMethod) ni $methods} {set st($w,compareMethod) x}
    if {[winfo exists $w.validation.method]} {$w.validation.method configure -values $methods}
}
proc ::GX::CurveWorkbench::_coordinateComparisonOptions {w reference target method} {
    foreach id [list $reference $target] {if {[_coordinateSourceRelations [_record $w $id]] ne {}} {error {Variable-specific coordinate relations require explicit Dataset Transform normalization before physical comparison}}}
    set output {}
    foreach axis {x y} {lappend output [dict get [_coordinateAxis $w $target $axis] display_unit]}
    if {$method ne "x"} {set output [lrepeat 2 [lindex $output 0]]}
    # Validate the complete frame before the Native owner allocates any copies.
    ::GX::native2DComparisonFrame $method [_coordinateUnits [_record $w $reference]] [_coordinateUnits [_record $w $target]] [dict create output_units $output]
    return [dict create output_units $output]
}
proc ::GX::CurveWorkbench::_coordinateComparisonSignature {w config} {
    return [list [_coordinateKey $w [dict get $config reference]] [_coordinateKey $w [dict get $config target]]]
}
proc ::GX::CurveWorkbench::_coordinatePublicationMetadata {w ids} {
    variable st
    set records {}
    foreach id $ids {
        set record [_record $w $id];set axes {}
        foreach axis {x y} {dict set axes $axis [dict remove [_coordinateAxis $w $id $axis] context]}
        dict set records $id [dict create axes $axes dataset_context [dict get [_coordinateContext $w $id] context] calibration_applied 0 display_conversion_applied 0]
    }
    set metadata [dict create curve_workbench.coordinate_presentation $records curve_workbench.coordinate_view $st($w,coordinateView)]
    if {[llength $ids]==1&&$st($w,comparisonConfig) ne {}&&[dict get $st($w,comparisonConfig) target] eq [lindex $ids 0]&&$st($w,comparisonRecord) ne {}&&[_measurementState $w $st($w,comparisonRecord)] eq "current"&&[dict exists $st($w,comparisonRecord) coordinate_presentation_signature]&&[dict get $st($w,comparisonRecord) coordinate_presentation_signature] eq [_coordinateComparisonSignature $w $st($w,comparisonConfig)]&&$st($w,residual) ne {}} {
        dict set metadata curve_workbench.comparison_summary [dict remove $st($w,residual) rows]
        set metadata [dict merge $metadata [::GX::StatisticsV1::publicationMetadata [dict get $st($w,residual) statistics]]]
    }
    return $metadata
}
proc ::GX::CurveWorkbench::_coordinateDispose {w} {
    variable st
    if {[info exists st($w,coordinateSubscription)]} {::GX::datasetCatalogUnsubscribe $st($w,coordinateSubscription);unset st($w,coordinateSubscription)}
    if {[info exists st($w,coordinateRefresh)]} {after cancel $st($w,coordinateRefresh);unset st($w,coordinateRefresh)}
}
proc ::GX::CurveWorkbench::_coordinateAffinePlan {w id axis {direction forward}} {
    set info [_coordinateAxis $w $id $axis]
    if {[dict get $info context] ne {}} {
        return [::GX::datasetCoordinateSnapshotAffinePlan [dict get $info context] [dict get $info variable_id] [dict get $info native_unit] [_coordinateOptions $info [dict create unit [dict get $info display_unit] direction $direction]]]
    }
    return [::GX::unitRegistryAffinePlan [dict get $info native_unit] [dict get $info display_unit] {} $direction]
}
proc ::GX::CurveWorkbench::_coordinateGridGuard {w token id signature} {
    variable st
    if {![info exists st($w,token)]||$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]||$st($w,active) ne $id||![dict exists $st($w,curves) $id]||$signature ne [_coordinateKey $w $id]} {error {Coordinate frame changed; reopen grid settings}}
}
proc ::GX::CurveWorkbench::_coordinateGridPresentation {w} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} {return {}}
    set id $st($w,active);set presentation {};set notes {}
    foreach axis {x y} {
        set forward [_coordinateAffinePlan $w $id $axis];set inverse [_coordinateAffinePlan $w $id $axis inverse]
        set info [_coordinateAxis $w $id $axis];set unit [dict get $info display_unit]
        if {![dict get $forward affine]||![dict get $inverse affine]} {
            set forward {scale 1.0 offset 0.0};set inverse $forward;set unit [dict get $info native_unit]
            lappend notes "[string toupper $axis] grid retains geometry units ($unit): its display relation is nonlinear."
        }
        dict set presentation $axis [dict create unit [expr {$unit eq {}?{undeclared}:$unit}] scale [dict get $forward scale] offset [dict get $forward offset] inverse_scale [dict get $inverse scale] inverse_offset [dict get $inverse offset]]
    }
    set px [dict get $presentation x];set py [dict get $presentation y]
    set compatible [expr {[dict get $px unit] ne "undeclared"&&[dict get $px unit] eq [dict get $py unit]&&[dict get $px scale]==[dict get $py scale]&&[dict get $px inverse_scale]==[dict get $py inverse_scale]&&[dict get $px scale]>0}]
    dict set presentation polar_compatible $compatible
    if {!$compatible} {lappend notes {Polar controls require a common physical axis frame and are unavailable here.}}
    lappend notes {Origins and spacing use the labelled units. Rotation refers to the underlying geometry frame.}
    dict set presentation note [join $notes { }]
    dict set presentation guard [list ::GX::CurveWorkbench::_coordinateGridGuard $w $st($w,token) $id [_coordinateKey $w $id]]
    return $presentation
}
proc ::GX::CurveWorkbench::_coordinateCurveStyle {w id index background} {
    variable st
    set palette {#1479a8 #c05f30 #7654a8 #208861 #bb3c73 #ad8726 #2f858b #536dba}
    set color [lindex $palette [expr {$index%[llength $palette]}]]
    if {$id eq $st($w,reference)} {set color #525d68}
    if {$id eq $st($w,active)} {set color #0c72b5}
    set color [_curvePresentationColor $w [_record $w $id] $color $background]
    return [dict create color [::GX::uiFieldColorToRGBA $color] line_width [expr {$id eq $st($w,active)?3:1.8}]]
}
proc ::GX::CurveWorkbench::_coordinateExportContext {w} {
    variable st
    set context [_extensionContext $w];set labels {};set options [dict create point_budget 4096 legend auto font_size 11 title {Curve Workbench sketch}]
    dict for {id record} $st($w,curves) {dict set labels [dict get $record native] [dict get $record name]}
    dict set options object_labels $labels
    if {$st($w,active) ne {}} {
        lassign [lindex [::GX::Native2D::core view $st($w,scene)] 6] x0 y0 x1 y1
        foreach axis {x y} lower [list $x0 $y0] upper [list $x1 $y1] {
            dict set options ${axis}_label [_coordinateLabel $w $st($w,active) $axis]
            set ticks {};for {set i 0} {$i<=5} {incr i} {lappend ticks [_coordinateTick $w $axis [expr {$lower+($upper-$lower)*$i/5.0}]]}
            dict set options ${axis}_tick_labels $ticks
        }
    }
    set snapshot [::GX::native2DPresentationSnapshot $st($w,scene) $options]
    set background [::GX::uiFieldColorFromRGBA [dict get $snapshot presentation background]]
    set background [::GX::uiFieldColorComposite $background #FFFFFF]
    set styles {};set visible {};set index 0
    dict for {id record} $st($w,curves) {
        if {![_curveVisible $w $record]} continue
        set native [dict get $record native]
        dict set visible $native $record
        dict set styles $native [_coordinateCurveStyle $w $id $index $background];incr index
    }
    set objects {}
    foreach object [dict get $snapshot objects] {
        set native [dict get $object id]
        if {![dict exists $visible $native]} continue
        set record [dict get $visible $native]
        dict set object style [dict merge [dict get $object style] [dict get $styles $native]]
        # Native render_lod supplies actual source/control points, distinct from
        # retained curve display samples. Export does not invent control markers.
        set pointsOnly [expr {[::GX::datasetPublicationV2DictDefault $record display_style straight] eq "points"}]
        if {[dict get $object kind] eq "curve"} {
            dict set object style marker 0
            if {[dict get $object style selectable]||$pointsOnly} {dict set object point_markers [dict get [::GX::Native2D::core render_lod $st($w,scene) $native 4096] points]}
            if {$pointsOnly} {dict set object paths {}}
        }
        lappend objects $object
    }
    dict set snapshot objects $objects
    set legends {}
    foreach legend [dict get $snapshot legend_primitives] {
        set native [dict get $legend object_id]
        if {![dict exists $visible $native]} continue
        dict set legend color [dict get $styles $native color]
        dict set legend width [dict get $styles $native line_width]
        lappend legends $legend
    }
    dict set snapshot legend_primitives $legends
    set texts {};foreach item [dict get $snapshot texts] {
        if {[dict exists $item object_id]&&![dict exists $visible [dict get $item object_id]]} continue
        lappend texts $item
    }
    dict set snapshot texts $texts
    dict set context presentation_snapshot $snapshot
    return $context
}
