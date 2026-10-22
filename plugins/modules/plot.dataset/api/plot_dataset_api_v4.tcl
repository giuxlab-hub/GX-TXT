# SPDX-License-Identifier: GPL-3.0-or-later
# Additive native Plot Dataset API. Canonical PlotSpec/Graph Series/Variants,
# Dataset access, units and resources retain their existing CORE owners.
namespace eval ::GX::PlotDatasetAPIv4 {
    variable apiDir [file dirname [file normalize [info script]]]
    variable widgets {}; variable serial 0
}
proc ::GX::PlotDatasetAPIv4::_ready {} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v1
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
    ::GX::native2DEnsure
    if {![llength [info commands ::gx::native2d::plot_v4]]} {error {The installed Native2D library does not provide Plot Dataset API v4}}
}
proc ::GX::PlotDatasetAPIv4::_get {d key default} {expr {[dict exists $d $key]?[dict get $d $key]:$default}}
proc ::GX::PlotDatasetAPIv4::_graphRef {ref} {dict create kind provider module_id plot.dataset graph_id [dict get $ref graph_id] variant_id [_get $ref variant_id {}]}
proc ::GX::PlotDatasetAPIv4::markOwned {ref} {
    ::GX::graphMetadataUpdate [_graphRef $ref] {renderer_owner PLOT_DATASET_API_v4 renderer_owner_api_version 1}
    return $ref
}
proc ::GX::PlotDatasetAPIv4::isOwned {ref} {
    set md [::GX::graphMetadataRead [_graphRef $ref]]
    expr {[_get $md renderer_owner {}] eq {PLOT_DATASET_API_v4}&&[_get $md renderer_owner_api_version 0]==1}
}
proc ::GX::PlotDatasetAPIv4::rendererOwnerForArtifact {path} {
    set ref [plotRefForArtifact $path]
    if {$ref ne {}&&[isOwned $ref]} {return [dict create api_version 1 owner PLOT_DATASET_API_v4]}
    return {}
}
proc ::GX::PlotDatasetAPIv4::capabilities {} {
    _ready
    set fields {};if {{native_cell_field} in [dict get [::GX::Native2D::core api_info] capabilities]} {set fields {exact_cell_field cell_field_binding}}
    return [lsort -unique [concat [::GX::PlotDatasetAPIv1::capabilities] [::GX::PlotDatasetAPIv2::capabilities] {cartesian_3d gridded_3d_streaming detached_scientific_capture detached_scientific_render source_row_point_index build_scene open_interactive refresh_interactive persistent_graph_source manual_interactive_sync interactive_sync_status independent_representation interactive_sources idempotent_plot_publication transient_2d_overlay transient_2d_curves readonly_native3d_preview_export transient_independent_2d_curves native_2d_cpp native_3d_cpp native_widget retained_series_visibility exact_source_bounds scientific_consultation equal_numeric_aspect retained_preparation scientific_3d_consultation canonical_xyz_consultation derived_comparison_display} $fields]]
}
proc ::GX::PlotDatasetAPIv4::supports {capability} {expr {$capability in [capabilities]}}
proc ::GX::PlotDatasetAPIv4::requireCapability {capability} {if {![supports $capability]} {error "Unsupported native Plot v4 capability '$capability'"};return 1}
proc ::GX::PlotDatasetAPIv4::apiInfo {} {
    _ready;set kinds {auto};foreach capability [::GX::PlotDatasetAPIv2::capabilities] {if {[string match series_kind_* $capability]} {lappend kinds [string range $capability 12 end]}}
    if {{native_cell_field} in [dict get [::GX::Native2D::core api_info] capabilities]} {lappend kinds cell_field}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_3D_API_v1
    return [dict replace [::GX::PlotDatasetAPIv2::apiInfo] api_name PLOT_DATASET_API_v4 api_version 4 capabilities [capabilities] host_operations {comparisonModel consultationSource consultationExportCommand consultationScene xyzConsultationSource xyzConsultationPrepare xyzConsultationChunk xyzCoordinatePresentation consultationReceipt scientificModel widgetPointer widgetRetain renderModel widgetValidateSources widgetCreate widgetConfigure widgetDraw widgetReceipt widgetView widgetHit widgetVisibility widgetExport widgetDestroy cellFieldSpec cellFieldProfileSpec cellFieldSourceIdentity cellFieldNativeScene} renderer_2d Native2D.C++ renderer_3d Native3D.C++.VTK supported_2d_kinds [lsort -unique $kinds] supported_3d_kinds [dict get [::GX::PlotDataset3DAPIv1::apiInfo] plot_types]]
}
# These delegates are persistence and specification authorities only. Every
# rendering/interactive/export path below is explicitly native-owned.
foreach name {newSpec reconcilePersistentPlots setSeriesPresentation multiPanelEnabled setMultiPanel panelIds panelInfo addPanel movePanel setPanelTitle setPanelAxis sharedXAxisGet sharedXAxisSet setSeriesPanel plotRefForArtifact panelIdsForArtifact removeSpec} {
    proc ::GX::PlotDatasetAPIv4::$name {args} [format {_ready;tailcall ::GX::PlotDatasetAPIv2::%s {*}$args} $name]
}
foreach name {openPlot deletePlot setPlotEnabled setConfig getConfig setTitle setSeries getSeries listSeries setSeriesEnabled moveSeries setSeriesOrder} {
    proc ::GX::PlotDatasetAPIv4::$name {args} [format {_ready;tailcall ::GX::PlotDatasetAPIv1::%s {*}$args} $name]
}
proc ::GX::PlotDatasetAPIv4::createPlot {graphId {kind base} {sourceVariant {}}} {_ready;markOwned [::GX::PlotDatasetAPIv1::createPlot $graphId $kind $sourceVariant]}
proc ::GX::PlotDatasetAPIv4::createPlotFromSpec {spec {kind base} {sourceVariant {}}} {_ready;validateSpec $spec;set ref [markOwned [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec $kind $sourceVariant]];_saveNativeAxes $ref $spec;return $ref}
proc ::GX::PlotDatasetAPIv4::applySpec {ref spec} {_ready;validateSpec $spec;set result [::GX::PlotDatasetAPIv2::applySpec $ref $spec];markOwned $ref;_saveNativeAxes $ref $spec;return $result}
proc ::GX::PlotDatasetAPIv4::saveSpec {ref spec} {_ready;validateSpec $spec;if {[dict get $ref graph_id] eq {plot.dataset.xyz}} {set result [::GX::PlotDatasetAPIv2::applySpec $ref $spec]} else {set result [::GX::PlotDatasetAPIv2::saveSpec $ref $spec]};markOwned $ref;_saveNativeAxes $ref $spec;return $result}
proc ::GX::PlotDatasetAPIv4::upsertPlotFromSpec {producer key spec} {
    _ready
    if {[::GX::moduleField $producer descriptor {}] eq {}} {error "Unknown plot producer '$producer'"}
    if {![string match "$producer:*" $key]||[regexp {[\r\n]} $key]} {error {Provider key must be owned by the producer}}
    validateSpec $spec
    set graph [dict get $spec graph_id];set id [::GX::plotVariantFindProviderKey plot.dataset $graph $key]
    if {$id eq {}} {set ref [createPlotFromSpec $spec variant];::GX::plotVariantSet plot.dataset $graph [dict get $ref variant_id] [dict create provider_key $key]} else {set ref [openPlot $graph $id];applySpec $ref $spec}
    return $ref
}
proc ::GX::PlotDatasetAPIv4::_request {series budget} {
    set source [dict create dataset_id [dict get $series dataset_id] x_variable_id [dict get $series x_variable_id] y_variable_id [dict get $series y_variable_id]]
    set transformed 0
    foreach {from to} {row_filters row_filters source_row_ordinals rows} {if {[dict exists $series $from]&&[dict get $series $from] ne {}} {dict set source $to [dict get $series $from];set transformed 1}}
    set order [_get $series ordering_variable_id {}]
    set request [dict remove $source rows row_filters]
    dict set request display_budget $budget
    if {$transformed||$order ne {}} {
        set options {include_lineage 1 lineage_prefix native_plot_v4_};set op concat_rows
        if {$order ne {}} {set op sort_rows;dict set options order_variable_ids [list $order]}
        dict set request transform_manifest [dict create api_version 1 operation $op sources [list $source] options $options]
    }
    return $request
}
proc ::GX::PlotDatasetAPIv4::_coordinate {context variable values target} {
    set result {}
    for {set i 0} {$i<[llength $values]} {incr i 4096} {
        set input [lrange $values $i [expr {$i+4095}]]
        set source [dict get $context variables $variable source]
        if {[_get $source value_kind {}] eq {elapsed_time}&&[_get $source value_format {}] eq {hms}} {set input [::GX::elapsedTimeConvert $input [dict get $source unit]]}
        set part [::GX::datasetCoordinateSnapshotValues $context $variable $input [dict create mode canonical unit $target]]
        lappend result {*}[dict get $part values]
    }
    return $result
}
# Presentation-only Level Scale contract, from the existing per-axis owner.
# Scientific values are never replaced. Unit conversion uses the public registry.
proc ::GX::PlotDatasetAPIv4::_levelValues {context id values target spec} {
    set spec [::GX::levelScaleValidate $spec];set scale [string tolower [dict get $spec scale]]
    if {$scale eq {linear}} {return $values}
    set unit $target;if {$unit in {source auto inherit {}}} {set unit [dict get $context variables $id source unit]}
    if {$unit in {{} dB dBFS FS}} {error {Level scale requires a physical, non-level axis unit}}
    set ref [lindex [::GX::unitRegistryConvertValues [dict get $spec reference_unit] $unit [list [dict get $spec reference_value]]] 0]
    if {$ref<=0} {error {Converted level reference must be positive}}
    set out {};foreach value $values {
        set transformed NaN
        if {[string is double -strict $value]&&[expr {abs($value)<Inf}]} {
            set magnitude [expr {[dict get $spec quantity_kind] eq {amplitude}?abs($value):$value}]
            if {$magnitude>=0} {
                if {$scale eq {fs}} {set transformed [expr {$value/$ref}]} elseif {$magnitude>0} {set transformed [expr {([dict get $spec quantity_kind] eq {amplitude}?20.:10.)*log10($magnitude/$ref)}]} elseif {[dict get $spec zero_policy] eq {negative_infinity}} {set transformed -Inf}
            }
        };lappend out $transformed
    };return $out
}
proc ::GX::PlotDatasetAPIv4::_distribution {series position context target input} {
    set id [dict get $series y_variable_id];set unit [dict get [::GX::datasetVariableV3ById [dict get $series dataset_id] $id] unit]
    set plan [::GX::datasetCoordinateSnapshotAffinePlan $context $id $unit [dict create unit $target]]
    if {![dict get $plan affine]} {error {Distribution display requires an affine physical unit relation; materialize a public Dataset Transform for nonlinear units}}
    return [::gx::native2d::plot_v4 distribution [dict merge $input $series $plan [dict create position $position]]]
}
proc ::GX::PlotDatasetAPIv4::_series {series axes budget position} {
    if {[dict exists $series cell_field]} {return [_cellFieldSeries $series $axes]}
    set session $::GX::currentSession;set ds [dict get $series dataset_id]
    if {[_get $series alignment_mode none] ne {none}} {error {Graph Series alignment_mode is declarative only; materialize alignment before plotting}}
    set token [::GX::curveSourceOpen $session [_request $series $budget]]
    try {
        set context [::GX::datasetCoordinateRead $session $ds]
        set xid [dict get $series x_variable_id];set yid [dict get $series y_variable_id];set side [_get $series axis left]
        set xtarget [_get [_get $axes x {}] display_unit source];set ytarget [_get [_get $axes $side {}] display_unit source]
        set kind [_get $series kind auto];set level [_get $series level_scale [::GX::levelScaleDefaults]]
        if {$kind in {histogram box_whisker}} {
            set display [::GX::curveSourceWithNumericInput $token [list ::GX::PlotDatasetAPIv4::_distribution $series $position $context $ytarget]]
        } else {
            set display [::GX::curveSourceDisplay $token];dict set display source_points [dict get $display points]
            if {[_get $series source_row_continuity 0]} {set breaks [dict get $display breaks];set previous {};set i 0;foreach row [dict get $display source_rows] {if {$previous ne {}&&$row!=$previous+1} {lappend breaks [expr {$i-1}]};set previous $row;incr i};dict set display breaks [lsort -integer -unique $breaks]}
            set xs {};set ys {};foreach point [dict get $display points] {lappend xs [lindex $point 0];lappend ys [lindex $point 1]}
            set xs [_coordinate $context $xid $xs $xtarget];set ys [_levelValues $context $yid [_coordinate $context $yid $ys $ytarget] $ytarget $level]
            set points {};foreach x $xs y $ys {lappend points [list $x $y]};dict set display points $points
            set exactScan [expr {[_get $level scale linear] ne {linear}}];dict set axes $side native_level_scale $level
            foreach id [list $xid $yid] target [list $xtarget $ytarget] axis [list x $side] {
                set source [dict get $context variables $id source];set nativeUnit [dict get $source unit]
                if {[_get $source value_kind {}] eq {elapsed_time}&&[_get $source value_format {}] eq {hms}} {set nativeUnit s}
                set plan [::GX::datasetCoordinateSnapshotAffinePlan $context $id $nativeUnit [dict create unit $target]]
                if {![dict get $plan affine]||[_get [_get $axes $axis {}] scale linear] eq {log}} {set exactScan 1}
            }
            dict set display source_full_bounds [dict get $display full_bounds]
            if {$exactScan} {set exact [_exactPresentationBounds $token $context $xtarget $ytarget $axes $side];dict set display full_bounds [dict get $exact bounds];dict set display presentation_bounds_receipt $exact} else {
                lassign [dict get $display full_bounds] xl yl xh yh
                lassign [_coordinate $context $xid [list $xl $xh] $xtarget] xl xh
                lassign [_coordinate $context $yid [list $yl $yh] $ytarget] yl yh
                dict set display full_bounds [list [expr {min($xl,$xh)}] [expr {min($yl,$yh)}] [expr {max($xl,$xh)}] [expr {max($yl,$yh)}]]
            }
            # Auxiliary uncertainty/bounds values are read through the SAME
            # public filtered/ordered stream and matched by exact source row.
            set aux {};foreach key {x_error y_error band bar_bounds} {if {[dict exists $series $key]} {foreach field {variable_id lower_variable_id upper_variable_id} {if {[dict exists $series $key $field]} {lappend aux [dict get $series $key $field]}}}}
            if {$aux ne {}} {set display [_auxiliary $token $series $display $context $xtarget $ytarget [lsort -unique $aux]]}
        }
        if {$kind eq {bar}} {
            if {![dict exists $series bar_bounds]} {
                set native [dict get $context variables $xid source unit]
                set plan [::GX::datasetCoordinateSnapshotAffinePlan $context $xid $native [dict create unit $xtarget]]
                if {![dict get $plan affine]} {error {Bar width on a nonlinear unit axis requires explicit Dataset-bound intervals}}
                set width [::GX::curveSourceWithNumericInput $token [list ::GX::PlotDatasetAPIv4::_barWidth $series [dict get $plan scale]]]
                dict set display bar_width [dict get $width bar_width]
            }
            set baseline [_get $series bar_baseline 0];if {$baseline in {auto {}}} {set baseline 0}
            dict set display bar_baseline [lindex [_levelValues $context $yid [_coordinate $context $yid [list $baseline] $ytarget] $ytarget $level] 0]
        }
        return [dict merge $series $display [dict create source_descriptor [::GX::curveSourceDescribe $token] coordinate_context $context]]
    } finally {::GX::curveSourceClose $token}
}
proc ::GX::PlotDatasetAPIv4::_auxiliary {token series display context xtarget ytarget aux} {
    set descriptor [::GX::curveSourceDescribe $token];set request [dict get $descriptor request]
    set xid [dict get $series x_variable_id];set yid [dict get $series y_variable_id]
    set ids [lsort -unique [concat [list $xid $yid] $aux]];set lineage {}
    if {[dict get $descriptor source_kind] eq {transform_view}} {set lineage native_plot_v4_source_row_ordinal;lappend ids $lineage}
    set wanted {};set i 0;foreach row [dict get $display source_rows] {dict set wanted $row $i;incr i}
    set count [llength [dict get $display points]];set channels {}
    foreach key {x_lower x_upper y_lower y_upper lower upper band_lower band_upper bar_lower bar_upper} {dict set channels $key [lrepeat $count NaN]}
    set stream [::GX::curveSourceOpenStream $token $ids 4096 {numeric_transport values}]
    set level [_get $series level_scale [::GX::levelScaleDefaults]]
    set position 0;set bounds [dict get $display full_bounds];set auxiliaryRun 0;set retainedRuns {}
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream];set n [dict get $chunk row_count]
            for {set i 0} {$i<$n} {incr i} {
                set row [expr {$lineage eq {}?$position+$i:[lindex [dict get $chunk values $lineage] $i]}]
                set raw {};foreach id $ids {dict set raw $id [lindex [dict get $chunk values $id] $i]}
                set x [dict get $raw $xid];set y [dict get $raw $yid]
                if {![string is double -strict $x]||![string is double -strict $y]||![expr {abs($x)<Inf&&abs($y)<Inf}]} continue
                set endpoints {}
                foreach axis {x y} id [list $xid $yid] target [list $xtarget $ytarget] value [list $x $y] {
                    set e [_get $series ${axis}_error {}];set mode [_get $e mode none]
                    if {$mode eq {symmetric}} {set aid [dict get $e variable_id];set bid $aid} elseif {$mode eq {asymmetric}} {set aid [dict get $e lower_variable_id];set bid [dict get $e upper_variable_id]} else continue
                    set a [dict get $raw $aid];set b [dict get $raw $bid]
                    if {![string is double -strict $a]||![string is double -strict $b]||![expr {abs($a)<Inf&&abs($b)<Inf}]} continue
                    set deltas {};foreach auxid [list $aid $bid] magnitude [list $a $b] {
                        set unit [dict get $context variables $auxid source unit]
                        set displacementTarget $target;if {$target eq {source}} {set displacementTarget [dict get $context variables $id source unit]}
                        set plan [::GX::datasetCoordinateSnapshotAffinePlan $context $auxid $unit [dict create unit $displacementTarget]]
                        if {![dict get $plan affine]} {error {Uncertainty requires an affine physical displacement relation}}
                        lassign [_coordinate $context $auxid [list 0 $magnitude] $displacementTarget] zero endpoint;lappend deltas [expr {abs($endpoint-$zero)}]
                    }
                    set center [lindex [_coordinate $context $id [list $value] $target] 0];lassign $deltas dl du
                    set low [expr {$center-$dl}];set high [expr {$center+$du}]
                    if {$axis eq {y}} {lassign [_levelValues $context $yid [list $low $high] $ytarget $level] low high}
                    dict set endpoints ${axis}_lower $low;dict set endpoints ${axis}_upper $high
                }
                foreach key {band bar_bounds} axis {y x} id [list $yid $xid] target [list $ytarget $xtarget] {
                    if {![dict exists $series $key]} continue
                    set lid [dict get $series $key lower_variable_id];set uid [dict get $series $key upper_variable_id]
                    set low [dict get $raw $lid];set high [dict get $raw $uid]
                    if {![string is double -strict $low]||![string is double -strict $high]||![expr {abs($low)<Inf&&abs($high)<Inf}]} {incr auxiliaryRun;continue}
                    set endpointTarget $target;if {$target eq {source}} {set endpointTarget [dict get $context variables $id source unit]}
                    set low [lindex [_coordinate $context $lid [list $low] $endpointTarget] 0];set high [lindex [_coordinate $context $uid [list $high] $endpointTarget] 0]
                    if {$axis eq {y}} {lassign [_levelValues $context $yid [list $low $high] $ytarget $level] low high}
                    set prefix [expr {$key eq {band}?{band}:{bar}}];dict set endpoints ${prefix}_lower $low;dict set endpoints ${prefix}_upper $high;dict set endpoints lower $low;dict set endpoints upper $high
                    if {$key eq {bar_bounds}} {lset bounds 0 [expr {min([lindex $bounds 0],$low,$high)}];lset bounds 2 [expr {max([lindex $bounds 2],$low,$high)}]}
                }
                if {[dict exists $wanted $row]} {dict set retainedRuns [dict get $wanted $row] $auxiliaryRun}
                dict for {key val} $endpoints {
                    if {![string is double -strict $val]||![expr {abs($val)<Inf}]} continue
                    if {[dict exists $wanted $row]} {set channel [dict get $channels $key];lset channel [dict get $wanted $row] $val;dict set channels $key $channel}
                    if {$key in {x_lower x_upper bar_lower bar_upper}} {set a 0;set b 2} elseif {$key in {lower upper}&&[dict exists $series bar_bounds]} {set a 0;set b 2} else {set a 1;set b 3}
                    lset bounds $a [expr {min([lindex $bounds $a],$val)}];lset bounds $b [expr {max([lindex $bounds $b],$val)}]
                }
            }
            incr position $n;if {[dict get $chunk eof]} break
        }
    } finally {::GX::curveSourceCloseStream $token $stream}
    set breaks [dict get $display breaks];set prior {};for {set i 0} {$i<$count} {incr i} {set run [_get $retainedRuns $i -1];if {$i&&$run!=$prior} {lappend breaks [expr {$i-1}]};set prior $run};dict set display breaks [lsort -integer -unique $breaks]
    return [dict merge $display $channels [dict create full_bounds $bounds]]
}
# A shared numeric axis needs one actual physical unit. Independently produced
# series are converted by their own Coordinate Context; source units never mix.
proc ::GX::PlotDatasetAPIv4::_commonAxes {series axes} {
    set baseline {};set units {}
    foreach s $series {
        if {![_get $s enabled 1]} continue
        set ds [dict get $s dataset_id];set x [::GX::datasetVariableV3ById $ds [dict get $s x_variable_id]]
        if {$baseline ne {}} {
            set a [string tolower [_get $baseline semantic_role {}]];set b [string tolower [_get $x semantic_role {}]]
            if {$a ne {}&&$b ne {}&&$a ne $b&&!($a in {independent peak_position}&&$b in {independent peak_position})} {error {Shared X semantic roles are incompatible}}
            set ak [_get $baseline value_kind number];set bk [_get $x value_kind number]
            if {$ak ne $bk&&!($a eq {elapsed_time}&&$b eq {elapsed_time}&&$ak in {elapsed_time number}&&$bk in {elapsed_time number})} {error {Shared X value kinds are incompatible}}
            set ar [_get $baseline time_reference {}];set br [_get $x time_reference {}]
            if {$ar ne {}&&$br ne {}&&$ar ne $br} {error {Shared X time references are incompatible}}
            if {$ar eq {absolute}&&$br eq {absolute}&&[_get $baseline time_origin {}] ne {}&&[_get $x time_origin {}] ne {}&&[dict get $baseline time_origin] ne [dict get $x time_origin]} {error {Absolute-time origins differ; materialize alignment before plotting}}
        } else {set baseline $x}
        foreach axis [list x [expr {[_get $s axis left] eq {right}?{y_right}:{y_left}}]] role {x y} {
            set v [::GX::datasetVariableV3ById $ds [dict get $s ${role}_variable_id]]
            if {![dict exists $units $axis]} {dict set units $axis [_get $v unit {}]}
        }
    }
    dict for {axis unit} $units {if {[_get [_get $axes $axis {}] display_unit source] in {source auto inherit {}}} {dict set axes $axis display_unit $unit}}
    return $axes
}
proc ::GX::PlotDatasetAPIv4::modelFromSpec {spec {context {}}} {
    _ready
    if {[_get $context prepared_model 0]} {return $spec}
    validateSpec $spec
    if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {error {A 3D Plot uses the Native3D scene authority}}
    set budget [_get $context display_budget 4096];set panels {};set position 0
    set np [_get $spec native_presentation {}];set plotConfig [_get $np plot_config {}];set effectiveAxes [_get $np axes {}]
    foreach panel [dict get $spec panels] {
        set axes [_commonAxes [dict get $panel series] [_get $panel axes {}]];foreach {canonical native} {y_left left y_right right} {if {[dict exists $axes $canonical]} {dict set axes $native [dict get $axes $canonical]}};set output {};set defaults [_get [_get $spec defaults {}] style {}]
        foreach series [dict get $panel series] {
            if {![_get $series enabled 1]} continue
            if {[_get $series kind auto] eq {auto}} {set kind [_get $plotConfig plot_style line];if {$kind eq {line_markers}} {set kind line_marker};if {$kind ni {line scatter line_marker}} {set kind line};dict set series kind $kind}
            set kind [dict get $series kind];set automatic [dict create color auto line_style [expr {$kind in {scatter errorbar bar histogram}?{none}:{solid}}] line_width [_get $plotConfig line_width [_get [_get $np graphics {}] line_width 1.5]] marker [expr {$kind in {scatter line_marker errorbar box_whisker}?{circle}:{none}}] marker_size [_get $plotConfig marker_size 4] marker_fill none opacity 1]
            set style $automatic;foreach layer [list $defaults [_get $series style {}]] {dict for {field value} $layer {if {$value in {{} inherit}} continue;if {$value eq {auto}} {dict set style $field [dict get $automatic $field]} else {dict set style $field $value}}};dict set series style $style
            if {[_get $plotConfig point_order dataset_order] eq {sort_x}&&[_get $series ordering_variable_id {}] eq {}} {dict set series ordering_variable_id [dict get $series x_variable_id]}
            dict set series level_scale [_get $effectiveAxes [expr {[_get $series axis left] eq {right}?{y2_level_scale}:{y_level_scale}}] [::GX::levelScaleDefaults]]
            set family [_get $series family_variable_id {}]
            if {$family ne {}} {
                set options [dict create dry_run 1 series_prefix [dict get $series id] label_template {\{member\}}]
                dict set options label_template {{member}}
                foreach key {row_filters ordering_variable_id source_row_ordinals} {if {[dict exists $series $key]} {dict set options $key [dict get $series $key]}}
                if {[_get $series secondary_variable_id {}] ne {}} {dict set options category_variable_id [dict get $series secondary_variable_id];dict set options category_behavior {Split into series}}
                set planned [::GX::graphSeriesExpandGroups plot.dataset [dict get $spec graph_id] [dict get $series dataset_id] [dict get $series x_variable_id] [dict get $series y_variable_id] $family $options]
                foreach member $planned {set member [dict merge $series $member];dict set member source_series_id [dict get $series id];dict set member id [dict get $member series_id];lappend output [_series $member $axes $budget [incr position]]}
            } else {lappend output [_series $series $axes $budget [incr position]]}
        }
        dict set panel series $output
        foreach axis {x left right} {
            if {[_get [_get $axes $axis {}] label {}] eq {}&&[llength $output]} {
                set member {}
                foreach candidate $output {if {$axis eq {x} || [_get $candidate axis left] eq $axis} {set member $candidate;break}}
                if {$member eq {}} continue
                set id [dict get $member [expr {$axis eq {x}?{x_variable_id}:{y_variable_id}}]]
                set variable [::GX::datasetVariableV3ById [dict get $member dataset_id] $id]
                set label [_get $variable display_label $id];if {$label eq {}} {set label [_get $variable name $id]};set unit [_get [_get $axes $axis {}] display_unit [_get $variable unit {}]];if {$unit in {source auto inherit}} {set unit [_get $variable unit {}]}
                if {$unit ne {}&&$unit ne {source}} {append label " ($unit)"};dict set axes $axis label $label
            }
        }
        foreach axis {left right} key {y_level_scale y2_level_scale} {set level [_get $effectiveAxes $key [::GX::levelScaleDefaults]];if {[dict get $level scale] ne {linear}} {set label [_get [_get $axes $axis {}] label {}];append label " ([dict get $level scale] re [format %.6g [dict get $level reference_value]] [dict get $level reference_unit]";if {[dict get $level quantity_kind] eq {amplitude}} {append label " [dict get $level amplitude_basis]"};append label ")";dict set axes $axis label $label}}
        set distributions {};foreach s $output {if {[dict get $s kind] in {histogram box_whisker}} {lappend distributions [dict get $s kind]}}
        if {$distributions ne {}} {set kind [lindex $distributions 0];set first [lindex $output 0];set variable [::GX::datasetVariableV3ById [dict get $first dataset_id] [dict get $first y_variable_id]];set label [_get $variable name [dict get $first y_variable_id]];set unit [_get [_get $axes left {}] display_unit [_get $variable unit {}]];if {$unit ne {}} {append label " ($unit)"};if {$kind eq {histogram}} {dict set axes x display_unit $unit;dict set axes left display_unit {};if {[_get [_get [_get $panel axes {}] x {}] label {}] eq {}} {dict set axes x label $label};if {[_get [_get [_get $panel axes {}] y_left {}] label {}] eq {}} {set norm [_get $first histogram_normalization count];dict set axes left label [expr {$norm eq {density}?{Probability density}:$norm eq {probability}?{Probability}:{Count}}]}} else {dict set axes x display_unit {};dict set axes x label Series;dict set axes left display_unit $unit;dict set axes left label $label;set ticks {};set labels {};set i 0;foreach s $output {lappend ticks [incr i];lappend labels [dict get $s label]};dict set axes x tick_positions $ticks;dict set axes x tick_labels $labels}}
        dict set panel axes $axes;lappend panels $panel
    }
    if {![dict exists $spec multi_panel]||[dict get $spec multi_panel]||[llength $panels]<2} {dict set spec panels $panels} else {set main [lindex $panels 0];set combined {};foreach panel $panels {lappend combined {*}[dict get $panel series]};dict set main series $combined;dict set spec panels [list $main]};return $spec
}
proc ::GX::PlotDatasetAPIv4::widgetValidateSources {spec {context {}}} {
    # Let hosts admit replacement sources before retiring their accepted UI.
    # Creation/configuration still revalidate at their own admission boundary.
    set model [modelFromSpec $spec $context]
    set checks [_modelChecks $model $context]
    return [dict create valid 1 source_count [llength $checks]]
}
proc ::GX::PlotDatasetAPIv4::widgetCreate {path spec {context {}}} {
    variable widgets;_ready
    if {[dict exists $widgets $path]} {error {Native Plot widget identity already exists}}
    # Source admission can reject a stale prepared model. Complete it before
    # allocating a controller/surface, as widgetConfigure already does, so an
    # aborted create leaves the widget path available for an explicit retry.
    set model [modelFromSpec $spec $context];set checks [_modelChecks $model $context]
    set token [::gx::native2d::plot_v4 create $model]
    try {::gx::native2d::surface $path;dict set widgets $path [dict create token $token spec $spec context $context session_token [::GX::interactiveDocumentSessionToken] source_checks $checks source_dirty 0 source_subscription [::GX::datasetCatalogSubscribe [list ::GX::PlotDatasetAPIv4::_sourceChanged $path]]]} on error {m o} {::gx::native2d::plot_v4 destroy $token;return -options $o $m}
    bind $path <Configure> [list ::GX::PlotDatasetAPIv4::_schedule $path]
    bind $path <Destroy> [list ::GX::PlotDatasetAPIv4::widgetDestroy $path]
    bind $path <Button-4> [list ::GX::PlotDatasetAPIv4::_wheel $path 1.25 %x %y]
    bind $path <Button-5> [list ::GX::PlotDatasetAPIv4::_wheel $path 0.8 %x %y]
    bind $path <MouseWheel> [list ::GX::PlotDatasetAPIv4::_wheelDelta $path %D %x %y]
    bind $path <ButtonPress-2> [list ::GX::PlotDatasetAPIv4::_dragStart $path %x %y]
    bind $path <B2-Motion> [list ::GX::PlotDatasetAPIv4::_drag $path %x %y]
    bind $path <Double-Button-1> [list ::GX::PlotDatasetAPIv4::_fit $path]
    _schedule $path;return $path
}
proc ::GX::PlotDatasetAPIv4::_widget {path {validate 1}} {variable widgets;if {![dict exists $widgets $path]} {error {Unknown native Plot widget}};set record [dict get $widgets $path];if {!$validate} {return $record};if {[dict get $record session_token] ne [::GX::interactiveDocumentSessionToken]} {error {Native Plot widget belongs to a previous Session}}
    # Local editable geometry can change without dirtying a Dataset file.
    # Derived scientific displays therefore consult their public owner on every
    # live operation, before the Dataset-only fast path.
    _comparisonValidate [dict get $record spec]
    set dirty [_get $record source_dirty 0]
    foreach check [_get $record source_checks {}] {
        foreach watch [_get $check watches {}] {lassign $watch file stamp;if {[_fileStamp $file] ne $stamp} {set dirty 1;break}}
    }
    if {!$dirty} {return $record}
    set updated {}
    foreach check [_get $record source_checks {}] {
        set id [dict get $check dataset_id]
        if {[dict exists $check coordinate_context] && [::GX::datasetCoordinateRead $::GX::currentSession $id] ne [dict get $check coordinate_context]} {
            error {Scientific coordinate context changed; reconfigure explicitly. The previous valid frame is preserved.}
        }
        set current [list [::GX::datasetViewerStamp $id [::GX::datasetResolvePath $::GX::currentSession $id]] [::GX::datasetRevisionToken $id]]
        if {$current ne [dict get $check stamp]} {
            if {[dict exists $check representation_source] && [dict get $check representation_source] eq [::GX::datasetViewerScientificIdentity $id]} {
                # An explicit retained view keeps its controls/camera when only
                # disposable Preview preferences change. Science still guards it.
                dict set check stamp $current
            } else {set valid [::GX::curveSourceValidateSnapshot $::GX::currentSession [dict get $check descriptor]];error "Native Plot source or presentation revision changed ($id, [dict get $valid status]); reconfigure explicitly. The previous valid frame is preserved."}
        }
        lappend updated $check
    }
    set checks {}
    foreach check $updated {
        set watches {};foreach watch [dict get $check watches] {set file [lindex $watch 0];lappend watches [list $file [_fileStamp $file]]}
        dict set check watches $watches;lappend checks $check
    }
    dict set record source_checks $checks;dict set record source_dirty 0;dict set widgets $path $record
    return $record}
proc ::GX::PlotDatasetAPIv4::_schedule {path} {variable widgets;if {![dict exists $widgets $path]||[dict exists $widgets $path interaction_error]} return;if {[dict exists $widgets $path pending]} {after cancel [dict get $widgets $path pending]};dict set widgets $path pending [after idle [list ::GX::PlotDatasetAPIv4::_drawSafe $path]]}
proc ::GX::PlotDatasetAPIv4::_drawSafe {path} {variable widgets;if {![dict exists $widgets $path]||![winfo exists $path]} return;catch {dict unset widgets $path pending};if {[catch {widgetDraw $path} message]} {dict set widgets $path last_error $message}}
proc ::GX::PlotDatasetAPIv4::widgetDraw {path} {set record [_widget $path];set result [::gx::native2d::plot_v4 draw [dict get $record token] [winfo width $path] [winfo height $path]];$path draw [dict get $result primitives];return [_scientificReceipt [dict get $record spec] [dict get $result receipt]]}
proc ::GX::PlotDatasetAPIv4::widgetConfigure {path spec {context {}}} {variable widgets;set record [_widget $path 0];set model [modelFromSpec $spec $context];set checks [_modelChecks $model $context];::gx::native2d::plot_v4 configure [dict get $record token] $model;dict set widgets $path spec $spec;dict set widgets $path context $context;dict set widgets $path source_checks $checks;dict set widgets $path source_dirty 0;dict set widgets $path session_token [::GX::interactiveDocumentSessionToken];foreach field {interaction_error last_error drag} {if {[dict exists $widgets $path $field]} {dict unset widgets $path $field}};_schedule $path;return $path}
# Native input is a notification boundary, not an explicit reconfiguration.
# A rejected source/controller retains its last frame and stops accepting input
# until a successful widgetConfigure. Public operations keep their strict guards.
proc ::GX::PlotDatasetAPIv4::_eventRecord {path} {
    variable widgets
    if {![dict exists $widgets $path] || ![winfo exists $path]} {return {}}
    if {[dict exists $widgets $path interaction_error]} {return {}}
    if {[catch {_widget $path} record options]} {
        dict set widgets $path interaction_error [dict create message $record options $options]
        dict set widgets $path last_error $record
        if {[dict exists $widgets $path drag]} {dict unset widgets $path drag}
        if {[dict exists $widgets $path pending]} {
            after cancel [dict get $widgets $path pending]
            dict unset widgets $path pending
        }
        set hint [_get [dict get $widgets $path context] refresh_hint {Select Render to refresh.}]
        ::GX::setStatus "Previous render — $record $hint" 100
        return {}
    }
    return $record
}
proc ::GX::PlotDatasetAPIv4::_fit {path} {
    set record [_eventRecord $path]
    if {$record eq {}} {return}
    ::gx::native2d::plot_v4 fit [dict get $record token]
    _schedule $path
}
proc ::GX::PlotDatasetAPIv4::widgetHit {path x y} {::gx::native2d::plot_v4 hit [dict get [_widget $path] token] $x $y}
proc ::GX::PlotDatasetAPIv4::widgetEdit {path spec} {widgetConfigure $path $spec [dict get [_widget $path] context]}
proc ::GX::PlotDatasetAPIv4::widgetView {path operation args} {set token [dict get [_widget $path] token];if {$operation eq {restore}} {if {[llength $args]!=1} {error {Expected receipt axes as restored view state}};::gx::native2d::plot_v4 restore $token [lindex $args 0]} elseif {$operation eq {fit}} {::gx::native2d::plot_v4 fit $token} else {::gx::native2d::plot_v4 view $token [lindex $args 0] $operation {*}[lrange $args 1 end]};_schedule $path}
proc ::GX::PlotDatasetAPIv4::_panelReceipt {record x y {id {}}} {
    set receipt [::gx::native2d::plot_v4 receipt [dict get $record token]];set result {}
    foreach axis [dict get $receipt axes] {if {[dict get $axis axis] ne {x}} continue;lassign [dict get $axis plot_rect] left top right bottom;if {$id ne {}?[dict get $axis panel_id] eq $id:($x>=$left&&$x<=$right&&$y>=$top&&$y<=$bottom)} {set result $axis;break}}
    if {$result eq {}} {return {}}
    set leftAxis {};foreach axis [dict get $receipt axes] {if {[dict get $axis panel_id] eq [dict get $result panel_id]&&[dict get $axis axis] eq {left}} {set leftAxis $axis;break}}
    dict set result y_direction [_get $leftAxis direction normal];return $result
}
proc ::GX::PlotDatasetAPIv4::_panelAt {path x y} {set panel [_panelReceipt [_widget $path] $x $y];return [_get $panel panel_id {}]}
proc ::GX::PlotDatasetAPIv4::_wheel {path factor x y} {
    set record [_eventRecord $path];if {$record eq {}} return;set panel [_panelReceipt $record $x $y];if {$panel eq {}} return
    lassign [dict get $panel plot_rect] left top right bottom
    set fx [expr {($x-$left)/double($right-$left)}];set fy [expr {($bottom-$y)/double($bottom-$top)}]
    if {[dict get $panel direction] eq {reverse}} {set fx [expr {1-$fx}]};if {[dict get $panel y_direction] eq {reverse}} {set fy [expr {1-$fy}]}
    ::gx::native2d::plot_v4 view [dict get $record token] [dict get $panel panel_id] zoom $factor $fx $fy;_schedule $path
}
proc ::GX::PlotDatasetAPIv4::_wheelDelta {path delta x y} {_wheel $path [expr {$delta>0?1.25:0.8}] $x $y}
proc ::GX::PlotDatasetAPIv4::_dragStart {path x y} {variable widgets;set record [_eventRecord $path];if {$record eq {}} return;set panel [_panelReceipt $record $x $y];if {$panel ne {}} {dict set widgets $path drag [list $x $y [dict get $panel panel_id]]}}
proc ::GX::PlotDatasetAPIv4::_drag {path x y} {
    variable widgets;set record [_eventRecord $path];if {$record eq {} || ![dict exists $record drag]} return
    lassign [dict get $record drag] oldx oldy id;set panel [_panelReceipt $record $x $y $id];if {$panel eq {}} return
    lassign [dict get $panel plot_rect] left top right bottom
    set dx [expr {($oldx-$x)/double($right-$left)}];set dy [expr {($y-$oldy)/double($bottom-$top)}]
    if {[dict get $panel direction] eq {reverse}} {set dx [expr {-$dx}]};if {[dict get $panel y_direction] eq {reverse}} {set dy [expr {-$dy}]}
    ::gx::native2d::plot_v4 view [dict get $record token] $id pan $dx $dy;dict set widgets $path drag [list $x $y $id];_schedule $path
}
proc ::GX::PlotDatasetAPIv4::widgetDestroy {path} {variable widgets;if {![dict exists $widgets $path]} return;set record [dict get $widgets $path];if {[dict exists $record pending]} {after cancel [dict get $record pending]};if {[dict exists $record source_subscription]} {::GX::datasetCatalogUnsubscribe [dict get $record source_subscription]};catch {::gx::native2d::plot_v4 destroy [dict get $record token]};dict unset widgets $path}
proc ::GX::PlotDatasetAPIv4::widgetReceipt {path} {set record [_widget $path];return [_scientificReceipt [dict get $record spec] [::gx::native2d::plot_v4 receipt [dict get $record token]]]}
proc ::GX::PlotDatasetAPIv4::widgetExport {path destination {width 1000} {height 720}} {set record [_widget $path];set result [::gx::native2d::plot_v4 draw [dict get $record token] $width $height];::gx::native2d::render $destination $width $height [dict get $result primitives];_schedule $path;return $destination}
proc ::GX::PlotDatasetAPIv4::renderModel {model destination {width 1000} {height 720}} {_ready;_modelChecks $model;set token [::gx::native2d::plot_v4 create $model];try {set result [::gx::native2d::plot_v4 draw $token $width $height];::gx::native2d::render $destination $width $height [dict get $result primitives];writeGeometry $model [dict get $result receipt] $destination;return [_scientificReceipt $model [dict get $result receipt]]} finally {::gx::native2d::plot_v4 destroy $token}}
# Existing Plot Region metadata, calibrated directly by the same native painter
# receipt. No raster guessing or second coordinate transformation is performed.
proc ::GX::PlotDatasetAPIv4::writeGeometry {model receipt destination} {
    if {[string tolower [file extension $destination]] ne {.png}} {return {}}
    set panels [dict get $model panels];set width [dict get $receipt width];set height [dict get $receipt height]
    set path [::GX::plotRegionMetadataPath $destination];file mkdir [file dirname $path]
    set fd [open "$path.tmp.[pid]" w];fconfigure $fd -encoding utf-8 -translation lf
    set topology [expr {[llength $panels]==1}];set calibrated 1;set overlay 0
    foreach p $panels {foreach s [dict get $p series] {if {[_get $s axis left] eq {right}} {incr overlay;break}}}
    try {
        puts $fd "\[plot_metadata\]";puts $fd {api_version=1};puts $fd {renderer_owner=PLOT_DATASET_API_v4}
        puts $fd "primary_axes_count=[llength $panels]";puts $fd "overlay_axes_count=$overlay";puts $fd {primary_axis_is_3d=0};puts $fd "image_width=$width";puts $fd "image_height=$height"
        # One primary 2D panel is the established rectangle-selection topology.
        set i 0;set sections {}
        foreach panel $panels {
            incr i;set axisRecords {};foreach record [dict get $receipt axes] {if {[dict get $record panel_id] eq [dict get $panel id]} {dict set axisRecords [dict get $record axis] $record}}
            if {![dict exists $axisRecords x]||![dict exists $axisRecords left]} {set calibrated 0;continue}
            set x [dict get $axisRecords x];set y [dict get $axisRecords left];lassign [dict get $x plot_rect] left top right bottom
            if {$left<0||$top<0||$right>=$width||$bottom>=$height||$right<=$left||$bottom<=$top} {set calibrated 0}
            set fields [dict create primary [expr {$i==1}] position [join [list [expr {$left/$width}] [expr {1.-$bottom/$height}] [expr {($right-$left)/$width}] [expr {($bottom-$top)/$height}]] {;}] pixel_rect [join [list $left $top $right $bottom] {;}] xlim [join [dict get $x limits] {;}] ylim [join [dict get $y limits] {;}] xscale [dict get $x scale] yscale [dict get $y scale] xdir [dict get $x direction] ydir [dict get $y direction] tag gxtxt_primary_axis]
            foreach axis {x y} side {x left} {
                set source {};foreach series [dict get $panel series] {if {$axis eq {x}||[_get $series axis left] eq {left}} {set source $series;break}}
                set transform affine;set inverseScale 1;set inverseOffset 0;set unit {};set native {};set target {};set id {}
                if {$source ne {}&&[_get $source kind {}] in {histogram box_whisker}} {
                    set transform derived_distribution
                    if {([dict get $source kind] eq {histogram}&&$axis eq {x})||([dict get $source kind] eq {box_whisker}&&$axis eq {y})} {set id [dict get $source y_variable_id];set unit [dict get $source coordinate_context variables $id source unit];set native $unit;set target [_get [_get [dict get $panel axes] $side {}] display_unit $unit]}
                } elseif {$source eq {}||![dict exists $source coordinate_context]} {set calibrated 0} else {
                    set id [dict get $source ${axis}_variable_id];set context [dict get $source coordinate_context]
                    if {![dict exists $context variables $id]} {
                        # Legacy/boolean axes remain drawable without claiming
                        # an unsupported physical inverse calibration.
                        set meta [::GX::datasetVariableV3ById [dict get $source dataset_id] $id]
                        set unit [dict get $meta unit];set native $unit;set target $unit
                        set transform unsupported_coordinate_contract;set calibrated 0
                    } else {
                        set meta [dict get $context variables $id source];set unit [dict get $meta unit];set native $unit
                        if {[_get $meta value_kind {}] eq {elapsed_time}&&[_get $meta value_format {}] eq {hms}} {set native s}
                        set target [_get [_get [dict get $panel axes] $side {}] display_unit source];if {$target in {source auto inherit {}}} {set target $unit}
                        set plan [::GX::datasetCoordinateSnapshotAffinePlan $context $id $native [dict create unit $target]]
                        if {[dict get $plan affine]&&[dict get $plan scale]!=0} {set inverseScale [expr {1./[dict get $plan scale]}];set inverseOffset [expr {-[dict get $plan offset]/[dict get $plan scale]}]} else {set transform non_affine_coordinate_relation}
                    }
                    set level [_get $source level_scale [::GX::levelScaleDefaults]];if {$axis eq {y}&&[dict get $level scale] ne {linear}} {set transform level_scale_v1;dict for {key value} $level {dict set fields ${axis}_level_$key $value}}
                    if {[_get $source kind {}] in {histogram box_whisker}} {set transform derived_distribution}
                }
                dict set fields ${axis}_source_variable $id;dict set fields ${axis}_source_unit $native;dict set fields ${axis}_display_unit $target;dict set fields ${axis}_display_to_source_scale $inverseScale;dict set fields ${axis}_display_to_source_offset $inverseOffset;dict set fields ${axis}_transform $transform
            }
            dict set sections $i $fields
        }
        puts $fd "selection_topology_supported=$topology";puts $fd "selection_calibration_valid=$calibrated";puts $fd "selection_supported=[expr {$topology&&$calibrated}]"
        dict for {index fields} $sections {puts $fd "\n\[axis.$index\]";dict for {key value} $fields {if {[regexp {[\r\n]} $value]} {error {Invalid multiline Plot geometry field}};puts $fd "$key=$value"}}
    } finally {close $fd}
    file rename -force -- "$path.tmp.[pid]" $path
    # Shared-X stacks retain their real multi-panel topology. The established
    # separate X-range calibration explicitly uses the first native data frame.
    if {!$topology&&$calibrated&&[dict exists $sections 1]} {
        set special [file join [file dirname $path] "[file rootname [file tail $destination]].xrange.ini"]
        set f [open "$special.tmp.[pid]" w];try {puts $f "\[plot_metadata\]\napi_version=1\nselection_supported=1\nselection_topology_supported=1\nselection_calibration_valid=1\nprimary_axis_is_3d=0\nprimary_axes_count=1\nimage_width=$width\nimage_height=$height\n\n\[axis.1\]";dict for {key value} [dict get $sections 1] {puts $f "$key=$value"}} finally {close $f};file rename -force -- "$special.tmp.[pid]" $special
    }
    return $path
}
proc ::GX::PlotDatasetAPIv4::artifacts {ref} {_ready;set a [::GX::PlotDatasetAPIv2::artifacts $ref];dict set a native_snapshot [file join [dict get $a output_dir] native_plot_v4.tcldict];dict set a renderer_owner PLOT_DATASET_API_v4;return $a}
proc ::GX::PlotDatasetAPIv4::render {ref} {
    _ready;set spec [loadSpec $ref];set a [artifacts $ref];set output [dict get $a graph_artifact];file mkdir [file dirname $output]
    if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {return [render3D $ref]}
    set model [modelFromSpec $spec];set temp "$output.native.[pid].png"
    try {set graphics [_get [_get $model native_presentation {}] graphics {}];set receipt [renderModel $model $temp [_get $graphics width_px 1000] [_get $graphics height_px 720]];set snapshot [dict get $a native_snapshot];set f [open "$snapshot.tmp" w];try {fconfigure $f -encoding utf-8 -translation lf;puts $f [list $model]} finally {close $f};file rename -force -- "$snapshot.tmp" $snapshot;file rename -force -- $temp $output;set tempMeta [::GX::plotRegionMetadataPath $temp];if {[file isfile $tempMeta]} {file rename -force -- $tempMeta [::GX::plotRegionMetadataPath $output]};set tempRange [file join [file dirname $tempMeta] "[file rootname [file tail $temp]].xrange.ini"];if {[file isfile $tempRange]} {file rename -force -- $tempRange [file join [file dirname $tempMeta] "[file rootname [file tail $output]].xrange.ini"]}} finally {catch {file delete -- $temp}}
    set extra [_get [_get $spec output {}] extra_format none]
    if {$extra in {svg pdf}} {renderModel $model [file rootname $output].$extra [_get $graphics width_px 1000] [_get $graphics height_px 720]}
    markOwned $ref;return [dict create execution native renderer_owner PLOT_DATASET_API_v4 artifacts [artifacts $ref] receipt $receipt]
}
proc ::GX::PlotDatasetAPIv4::rerender {ref} {render $ref}
proc ::GX::PlotDatasetAPIv4::renderCommand {ref {operation render}} {if {$operation ni {render rerender}} {error {Unknown native render operation}};return [list ::GX::PlotDatasetAPIv4::$operation $ref]}
proc ::GX::PlotDatasetAPIv4::openEditor {ref} {
    # Reuse the existing public specification editor; owner dispatch stays v4.
    markOwned $ref;::GX::PlotDatasetAPIv2::openEditor $ref
}
proc ::GX::PlotDatasetAPIv4::_exportRef {ref output} {if {[dict get $ref graph_id] eq {plot.dataset.xyz}} {return [export3D $ref $output]};renderModel [modelFromSpec [loadSpec $ref]] $output;return $output}
proc ::GX::PlotDatasetAPIv4::previewCompatibility {ref} {_ready;validateSpec [loadSpec $ref];if {[dict get $ref graph_id] eq {plot.dataset.xyz}} {interactiveSourceInfo $ref};dict create supported 1 plot_ref $ref compatible 1 owner PLOT_DATASET_API_v4 editable 1 graph_type [expr {[dict get $ref graph_id] eq {plot.dataset.xyz}?{cartesian_3d}:{cartesian_2d}}]}
# Native3D and clone lifecycle are additive components of this same facade.
source [file join $::GX::PlotDatasetAPIv4::apiDir plot_dataset_v4_snapshots.tcl]
source [file join $::GX::PlotDatasetAPIv4::apiDir plot_dataset_v4_native3d.tcl]

proc ::GX::PlotDatasetAPIv4::_saveNativeAxes {ref spec} {
    set fields [_cellFieldBindings $spec];set changes [dict create native_plot_v4_cell_fields $fields native_plot_v4_cell_field_required [expr {$fields ne {}}]];if {[dict get $ref graph_id] eq {plot.dataset.xyz}&&[dict exists $spec axes]} {dict set changes native_plot_v4_axes [dict get $spec axes]}
    if {[dict exists $spec native_presentation]} {set p [dict get $spec native_presentation];if {[_get $p schema {}] ne {GXTXT_NATIVE_GRAPH_PRESENTATION_v1}} {error {Unsupported native graph presentation schema}};dict set changes native_plot_v4_presentation $p}
    if {$changes ne {}} {::GX::graphMetadataUpdate [_graphRef $ref] $changes}
}

proc ::GX::PlotDatasetAPIv4::_exactPresentationBounds {token context xtarget ytarget axes side {progress {}}} {
    set request [dict get [::GX::curveSourceDescribe $token] request];set xid [dict get $request x_variable_id];set yid [dict get $request y_variable_id]
    set stream [::GX::curveSourceOpenStream $token [list $xid $yid] 4096 {numeric_transport values}]
    set lows {Inf Inf};set highs {-Inf -Inf};set excluded {0 0};set finite 0;set completed 0
    try {while {1} {set chunk [::GX::tableStreamNext $stream];set xs {};set ys {}
        foreach x [dict get $chunk values $xid] y [dict get $chunk values $yid] {if {![string is double -strict $x]||![string is double -strict $y]||![expr {abs($x)<Inf&&abs($y)<Inf}]} continue;lappend xs $x;lappend ys $y;incr finite}
        set index 0;foreach id [list $xid $yid] target [list $xtarget $ytarget] values [list $xs $ys] axis [list x $side] {
            set log [expr {[_get [_get $axes $axis {}] scale linear] eq {log}}]
            if {[dict exists $context variables $id]} {set converted [_coordinate $context $id $values $target]} else {set converted $values}
            if {$axis ne {x}} {set converted [_levelValues $context $id $converted $target [_get [_get $axes $axis {}] native_level_scale [::GX::levelScaleDefaults]]]}
            foreach v $converted {if {![string is double -strict $v]||![expr {abs($v)<Inf}]} continue;if {$log&&$v<=0} {lset excluded $index [expr {[lindex $excluded $index]+1}];continue};lset lows $index [expr {min([lindex $lows $index],$v)}];lset highs $index [expr {max([lindex $highs $index],$v)}]};incr index
        }
        incr completed [dict get $chunk row_count]
        if {$progress ne {}} {::GX::curveSourceCooperativeBoundary $progress [dict create stage coordinate_bounds completed_rows $completed total_rows [dict get [::GX::curveSourceDescribe $token] row_count]]}
        if {[dict get $chunk eof]} break
    }} finally {::GX::curveSourceCloseStream $token $stream}
    foreach low $lows high $highs {if {![expr {abs($low)<Inf&&abs($high)<Inf}]} {error {Selected scientific data have no valid coordinates for the requested axis scale}}}
    return [dict create authority complete_public_curve_source bounds [list [lindex $lows 0] [lindex $lows 1] [lindex $highs 0] [lindex $highs 1]] finite_pairs $finite excluded_nonpositive_by_axis $excluded display_reduction_used_for_bounds 0]
}

proc ::GX::PlotDatasetAPIv4::_barWidth {series scale input} {::gx::native2d::plot_v4 distribution [dict merge $input [dict create kind bar_width bar_width [_get $series bar_width .8] x_scale $scale]]}
proc ::GX::PlotDatasetAPIv4::readPlot {ref} {_ready;set result [::GX::PlotDatasetAPIv1::readPlot $ref];dict set result plotspec [loadSpec $ref];return $result}

proc ::GX::PlotDatasetAPIv4::_modelChecks {model {context {}}} {
    set checks {};set seen {}
    _comparisonValidate $model
    if {[dict exists $model scientific_consultation]} {
        set consultation [dict get $model scientific_consultation]
        if {[::GX::datasetCoordinateRead $::GX::currentSession [dict get $consultation dataset_id]] ne [dict get $consultation coordinate_context]} {
            error {Scientific coordinate context changed; prepare the selected source again}
        }
    }
    foreach panel [dict get $model panels] {foreach series [dict get $panel series] {
        if {[dict exists $model scientific_consultation] &&
            ([dict get $series dataset_id] ne [dict get $consultation dataset_id] ||
             [dict get $series coordinate_context] ne [dict get $consultation coordinate_context])} {
            error {Scientific trace belongs to a different Dataset or coordinate context}
        }
        set descriptors [_get $series source_descriptors {}];if {[dict exists $series source_descriptor]} {lappend descriptors [dict get $series source_descriptor]}
        foreach descriptor $descriptors {foreach identity [dict get $descriptor source_identities] {set id [dict get $identity dataset_id];if {$id in $seen} continue;lappend seen $id
            set validation [::GX::curveSourceValidateSnapshot $::GX::currentSession $descriptor]
            if {![dict get $validation valid]} {error "Prepared native Plot source is [dict get $validation status]; rebuild from its canonical source explicitly"}
            set stamp [list [::GX::datasetViewerStamp $id [::GX::datasetResolvePath $::GX::currentSession $id]] [::GX::datasetRevisionToken $id]]
            set watches {}
            foreach path [list [::GX::datasetResolvePath $::GX::currentSession $id] [::GX::datasetRegistryPath $::GX::currentSession] [lindex [::GX::_datasetMetadataPath $::GX::currentSession $id] 1]] {lappend watches [list $path [_fileStamp $path]]}
            set check [dict create dataset_id $id descriptor $descriptor stamp $stamp watches $watches]
            if {[dict exists $model scientific_consultation] && $id eq [dict get $model scientific_consultation dataset_id]} {
                dict set check coordinate_context [dict get $model scientific_consultation coordinate_context]
            }
            if {[_get $context retain_presentation 0]} {dict set check representation_source [::GX::datasetViewerScientificIdentity $id]}
            lappend checks $check
        }}
    }}
    return $checks
}

source [file join $::GX::PlotDatasetAPIv4::apiDir plot_dataset_v4_cell_field.tcl]

# Retained visibility changes no source binding, geometry buffer or axis fit.
proc ::GX::PlotDatasetAPIv4::widgetVisibility {path panel series visible} {
    set record [_widget $path]
    ::gx::native2d::plot_v4 visibility [dict get $record token] $panel $series $visible
    _schedule $path
    return [dict create widget $path model_token [dict get $record token] panel_id $panel series_id $series visible $visible]
}

proc ::GX::PlotDatasetAPIv4::_fileStamp {path} {
    if {![file isfile $path]} {return missing}
    file stat $path st
    return [list $st(ino) $st(size) $st(mtime) $st(ctime)]
}
proc ::GX::PlotDatasetAPIv4::_sourceChanged {path receipt} {
    variable widgets
    if {![dict exists $widgets $path]} return
    set ids [dict get $receipt dataset_ids]
    foreach check [dict get $widgets $path source_checks] {
        if {[dict get $receipt change_kind] eq "session" || [dict get $check dataset_id] in $ids} {dict set widgets $path source_dirty 1;return}
    }
}

source [file join $::GX::PlotDatasetAPIv4::apiDir plot_dataset_v4_consultation.tcl]
source [file join $::GX::PlotDatasetAPIv4::apiDir plot_dataset_v4_comparison.tcl]
