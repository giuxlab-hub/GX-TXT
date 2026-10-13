# GX-TXT Plot Dataset API v3: current facade over stable PlotSpec v2,
# detached snapshots, and the dedicated interactive 3D service.
namespace eval ::GX::PlotDatasetAPIv3 {
    variable apiDir [file dirname [file normalize [info script]]]
}

proc ::GX::PlotDatasetAPIv3::_service {name} {
    variable apiDir
    return [file join [file dirname $apiDir] runtime $name]
}

proc ::GX::PlotDatasetAPIv3::_octave {args} {
    set executable [expr {[info exists ::GX::cfg(octave_cmd)] && $::GX::cfg(octave_cmd) ne "" ? $::GX::cfg(octave_cmd) : "octave"}]
    set environment {}
    if {[lindex $args 0] eq "render"} {
        set cfg [::GX::parseIni [lindex $args 2]]
        dict for {key value} $cfg {
            if {![regexp {^graphics_effective\.(GXTXT_(PLOT(_|3D_).*|PNG_DPI))$} $key -> name]} continue
            if {$name eq "GXTXT_PLOT_GRAPH_MAP_FILE"} continue
            lappend environment "$name=$value"
        }
    }
    return [exec -- env {*}$environment DISPLAY= GXTXT_GRAPHICS_MODE=headless GXTXT_GRAPHICS_TOOLKIT=gnuplot \
        GXTXT_GRAPHICS_VISIBLE=0 $executable --quiet --no-gui \
        [_service plot_dataset_snapshot.m] {*}$args 2>@1]
}

proc ::GX::PlotDatasetAPIv3::_presentationRuntime {source target graph variant} {
    set stream [open $target w]
    fconfigure $stream -encoding utf-8 -translation lf
    puts $stream "\[runtime\]\nsession=private_session\noutput_dir=.\n"
    puts $stream "\[graph_provider\]\nenabled=$graph\n"
    puts $stream "\[plot_variant\]\ngraph_id=$graph\nvariant_id=$variant\n"
    set input [open $source r]
    fconfigure $input -encoding utf-8
    set keep 0
    foreach line [split [read $input] "\n"] {
        if {[regexp {^\[([^]]+)\]$} [string trim $line] -> section]} {
            set keep [expr {$section in {module_graphics graphics_effective} ||
                [string match "plot.plot.dataset.*" $section] ||
                [string match "legend.plot.dataset.*" $section] ||
                [string match "axis.plot.dataset.*" $section] ||
                [string match "level_scale.plot.dataset.*" $section]}]
        }
        if {$keep && ![regexp {^(GXTXT_PLOT_.*_FILE|GXTXT_UNIT_REGISTRY_FILE)=} $line]} {
            puts $stream $line
        }
    }
    close $input
    close $stream
}

proc ::GX::PlotDatasetAPIv3::_v2 {} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v1
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
}

proc ::GX::PlotDatasetAPIv3::_3d {} {
    _v2
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_3D_API_v1
}

proc ::GX::PlotDatasetAPIv3::capabilities {} {
    _v2
    return [lsort -unique [concat [::GX::PlotDatasetAPIv2::capabilities] {
        detached_scientific_capture detached_scientific_render source_row_point_index
        build_scene open_interactive refresh_interactive persistent_graph_source
        manual_interactive_sync interactive_sync_status independent_representation
        interactive_sources idempotent_plot_publication transient_2d_overlay
        transient_2d_curves readonly_native3d_preview_export
        transient_independent_2d_curves
    }]]
}

proc ::GX::PlotDatasetAPIv3::supports {capability} {
    expr {[lsearch -exact [capabilities] $capability] >= 0}
}

proc ::GX::PlotDatasetAPIv3::requireCapability {capability} {
    if {![supports $capability]} {error "plot.dataset API v3: unsupported capability '$capability'"}
    return 1
}

proc ::GX::PlotDatasetAPIv3::apiInfo {} {
    _v2
    return [dict replace [::GX::PlotDatasetAPIv2::apiInfo] \
        api_name PLOT_DATASET_API_v3 api_version 3 capabilities [capabilities]]
}

# These are explicit public v2 delegates. The PlotSpec schema stays v2.
foreach {name formal actual} {
    newSpec {args} {{*}$args}
    validateSpec {spec} {$spec}
    createPlotFromSpec {spec {kind base} {sourceVariant ""}} {$spec $kind $sourceVariant}
    applySpec {plotRef spec} {$plotRef $spec}
    saveSpec {plotRef spec} {$plotRef $spec}
    loadSpec {plotRef {deriveIfMissing 1}} {$plotRef $deriveIfMissing}
    reconcilePersistentPlots {} {}
    deriveSpec {plotRef} {$plotRef}
    removeSpec {plotRef} {$plotRef}
    readPlot {plotRef} {$plotRef}
    setSeriesPresentation {plotRef seriesId fields} {$plotRef $seriesId $fields}
    multiPanelEnabled {plotRef} {$plotRef}
    setMultiPanel {plotRef state} {$plotRef $state}
    panelIds {plotRef} {$plotRef}
    panelInfo {plotRef panelId} {$plotRef $panelId}
    addPanel {plotRef panelId} {$plotRef $panelId}
    removePanel {plotRef panelId} {$plotRef $panelId}
    movePanel {plotRef panelId delta} {$plotRef $panelId $delta}
    setPanelTitle {plotRef panelId title} {$plotRef $panelId $title}
    setPanelAxis {plotRef panelId axis fields} {$plotRef $panelId $axis $fields}
    sharedXAxisGet {plotRef} {$plotRef}
    sharedXAxisSet {plotRef fields} {$plotRef $fields}
    setSeriesPanel {plotRef seriesId panelId} {$plotRef $seriesId $panelId}
    plotRefForArtifact {path} {$path}
    panelIdsForArtifact {path} {$path}
    render {plotRef} {$plotRef}
    rerender {plotRef} {$plotRef}
    artifacts {plotRef} {$plotRef}
    openEditor {plotRef} {$plotRef}
} {
    set body [format {_v2; tailcall ::GX::PlotDatasetAPIv2::%s %s} $name $actual]
    proc ::GX::PlotDatasetAPIv3::$name $formal $body
}

# The stable v1 lifecycle remains useful when a caller starts from an
# existing persistent graph identity rather than a new PlotSpec.
foreach {name formal actual} {
    createPlot {graphId {kind base} {sourceVariant ""}} {$graphId $kind $sourceVariant}
    openPlot {graphId {variantId ""}} {$graphId $variantId}
    deletePlot {plotRef} {$plotRef}
    setPlotEnabled {plotRef state} {$plotRef $state}
    setConfig {plotRef key value} {$plotRef $key $value}
    getConfig {plotRef key} {$plotRef $key}
    setTitle {plotRef title} {$plotRef $title}
    setSeries {plotRef seriesId fields} {$plotRef $seriesId $fields}
    getSeries {plotRef seriesId} {$plotRef $seriesId}
    listSeries {plotRef {includeDisabled 1}} {$plotRef $includeDisabled}
    removeSeries {plotRef seriesId} {$plotRef $seriesId}
    setSeriesEnabled {plotRef seriesId state} {$plotRef $seriesId $state}
    moveSeries {plotRef seriesId direction} {$plotRef $seriesId $direction}
    setSeriesOrder {plotRef orderedIds} {$plotRef $orderedIds}
    renderCommand {plotRef {operation render}} {$plotRef $operation}
} {
    set body [format {_v2; tailcall ::GX::PlotDatasetAPIv1::%s %s} $name $actual]
    proc ::GX::PlotDatasetAPIv3::$name $formal $body
}

proc ::GX::PlotDatasetAPIv3::buildScene {plotRef {representationId ""}} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::buildScene $plotRef $representationId
}
proc ::GX::PlotDatasetAPIv3::openInteractive {plotRef} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::openInteractive $plotRef
}
proc ::GX::PlotDatasetAPIv3::refreshInteractive {plotRef} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::refreshInteractive $plotRef
}
proc ::GX::PlotDatasetAPIv3::interactiveSources {} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::sources
}
proc ::GX::PlotDatasetAPIv3::interactiveSourceInfo {plotRef} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::sourceInfo $plotRef
}
proc ::GX::PlotDatasetAPIv3::sourceFingerprint {plotRef} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::sourceFingerprint $plotRef
}
proc ::GX::PlotDatasetAPIv3::interactiveRepresentations {} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::representations
}
proc ::GX::PlotDatasetAPIv3::interactiveStatus {representationId} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::syncStatus $representationId
}
proc ::GX::PlotDatasetAPIv3::activateInteractive {representationId} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::activateRepresentation $representationId
}
proc ::GX::PlotDatasetAPIv3::syncInteractive {representationId} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::syncInteractive $representationId
}

# Idempotent graph publication for a named producer output. Plot Dataset owns
# the provider-key registry; callers never edit Plot Variant internals.
proc ::GX::PlotDatasetAPIv3::upsertPlotFromSpec {producerModuleId providerKey spec} {
    _v2
    if {[::GX::moduleField $producerModuleId descriptor ""] eq ""} {
        error "Unknown plot producer module '$producerModuleId'"
    }
    if {![string match "$producerModuleId:*" $providerKey] ||
        [regexp {[\r\n]} $providerKey]} {
        error "Plot provider key must be a single-line key owned by '$producerModuleId'"
    }
    ::GX::PlotDatasetAPIv2::validateSpec $spec
    set graphId [dict get $spec graph_id]
    set variant [::GX::plotVariantFindProviderKey plot.dataset $graphId $providerKey]
    if {$variant eq ""} {
        set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec variant]
        ::GX::plotVariantSet plot.dataset $graphId [dict get $ref variant_id] \
            [dict create provider_key $providerKey]
    } else {
        set ref [::GX::PlotDatasetAPIv1::openPlot $graphId $variant]
        ::GX::PlotDatasetAPIv2::applySpec $ref $spec
    }
    return $ref
}

# The point index is a presentation sample, with exact canonical source-row
# identities. Region operations must still scan the full source Dataset.
proc ::GX::PlotDatasetAPIv3::writePointIndex {artifact destination} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
    set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $artifact]
    if {$ref eq ""} { error "Plot Dataset does not own this graph artifact." }
    set graph [dict get $ref graph_id]
    if {$graph eq "plot.dataset.xyz"} { error "Graph point selection requires a 2D plot." }
    set resources [::GX::PlotDatasetAPIv2::artifacts $ref]
    set cache [dict get $resources render_cache]
    if {![file isfile $cache]} { error "Plot Dataset render cache is unavailable." }
    if {[file exists $destination]} { error "Point index destination already exists." }
    if {[catch {_octave points $cache $destination $graph} failure options]} {
        catch {file delete -- $destination}
        return -options $options $failure
    }
    if {![file isfile $destination]} { error "Plot Dataset did not create the point index." }
    return $destination
}

# The caller owns destinationDir and must keep it outside the visible Plots
# tree until this operation succeeds. No source Dataset is read during render.
proc ::GX::PlotDatasetAPIv3::captureForArtifact {artifact destinationDir} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
    set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $artifact]
    if {$ref eq ""} { error "Plot Dataset does not own this graph artifact." }
    set graph [dict get $ref graph_id]
    set variant [dict get $ref variant_id]
    set resources [::GX::PlotDatasetAPIv2::artifacts $ref]
    set cache [dict get $resources render_cache]
    set runtime [file join [dict get $resources output_dir] runtime.ini]
    if {![file isfile $cache] || ![file isfile $runtime]} {
        error "Resolved Plot Dataset runtime/cache is unavailable."
    }
    file mkdir $destinationDir
    set raw [file join $destinationDir snapshot_raw.h5]
    set packed [file join $destinationDir snapshot.h5]
    _octave capture $cache $raw $graph
    if {![file isfile $raw] || [file size $raw] < 100} { error "Scientific snapshot capture failed." }
    exec -- [::GX::runtimeToolRequired python] [_service repack_snapshot.py] $raw $packed
    file delete -- $raw
    set private [file join $destinationDir private_session metadata plot.dataset plotspec_v2]
    file mkdir $private
    if {$graph ne "plot.dataset.xyz"} {
        set specPath [::GX::PlotDatasetAPIv2::_specPath $ref]
        if {[file isfile $specPath]} { file copy -- $specPath [file join $private [file tail $specPath]] }
    }
    _presentationRuntime $runtime [file join $destinationDir presentation.ini] $graph $variant
    renderSnapshot $destinationDir $graph
    return [dict create graph_id $graph source_variant $variant snapshot snapshot.h5]
}

proc ::GX::PlotDatasetAPIv3::renderSnapshot {cloneDir graph} {
    set snapshot [file join $cloneDir snapshot.h5]
    set runtime [file join $cloneDir presentation.ini]
    if {![file isfile $snapshot] || ![file isfile $runtime]} {
        error "Clone-owned scientific snapshot or presentation state is missing."
    }
    _octave render $snapshot $runtime $graph
    set artifact [file join $cloneDir graph.png]
    if {![file isfile $artifact] || [file size $artifact] < 100} {
        error "Scientific Clone render did not create a graph."
    }
    return $artifact
}

# Render an unpublished numerical overlay using the same prepared scientific
# snapshot and Plot Dataset renderer as the source graph. The caller owns and
# eventually removes destinationDir; no Session registry entry is created.
proc ::GX::PlotDatasetAPIv3::renderTransientOverlay {artifact xValues yValues label destinationDir} {
    if {[llength $xValues] < 2 || [llength $xValues] != [llength $yValues]} {
        error "Transient overlay requires matching X/Y vectors with at least two points."
    }
    if {[regexp {[\r\n]} $label]} {error "Transient overlay label must be one line."}
    foreach value [concat $xValues $yValues] {
        if {![string is double -strict $value] || [catch {set n [expr {double($value)}]}] || [expr {abs($n)==Inf}]} {
            error "Transient overlay coordinates must be finite numbers."
        }
    }
    set info [captureForArtifact $artifact $destinationDir]
    set graph [dict get $info graph_id]
    if {$graph eq "plot.dataset.xyz"} {error "Use a 2-D Plot Dataset artifact for an XY transient overlay."}
    set request [file join $destinationDir transient_overlay.tsv]
    set fd [open $request w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd $label
        foreach x $xValues y $yValues {puts $fd "[format %.17g $x]\t[format %.17g $y]"}
    } finally {close $fd}
    try {
        _octave overlay [file join $destinationDir snapshot.h5] $request $graph
        set rendered [renderSnapshot $destinationDir $graph]
    } finally {file delete -- $request}
    return [dict create artifact $rendered graph_id $graph transient 1]
}

# Graphical preview for an unpublished ordered XYZ curve. This calls the same
# 3-D Plot Dataset renderer as canonical plots and creates no Session object.
proc ::GX::PlotDatasetAPIv3::renderTransientCurve3D {xValues yValues zValues label destinationDir} {
    set count [llength $xValues]
    if {$count < 2 || $count != [llength $yValues] || $count != [llength $zValues]} {
        error "3D transient curve requires matching X/Y/Z vectors with at least two points."
    }
    if {[regexp {[\r\n]} $label]} {error "Transient curve label must be one line."}
    foreach value [concat $xValues $yValues $zValues] {
        if {![string is double -strict $value] || [catch {set n [expr {double($value)}]}] || [expr {abs($n)==Inf}]} {
            error "3D transient curve coordinates must be finite numbers."
        }
    }
    file mkdir $destinationDir
    set request [file join $destinationDir transient_curve3d.tsv]
    set fd [open $request w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd $label
        foreach x $xValues y $yValues z $zValues {puts $fd "[format %.17g $x]\t[format %.17g $y]\t[format %.17g $z]"}
    } finally {close $fd}
    try {
        _octave transient3d $request $destinationDir plot.dataset.xyz
    } finally {file delete -- $request}
    set artifact [file join $destinationDir graph.png]
    if {![file isfile $artifact] || [file size $artifact] < 100} {error "3D transient Plot Dataset preview failed."}
    return [dict create artifact $artifact graph_id plot.dataset.xyz transient 1]
}

# Direct transient XY plotting uses the normal Plot Dataset 2-D renderer while
# keeping Worksheet/manual values outside all persistent Session registries.
proc ::GX::PlotDatasetAPIv3::renderTransientCurves2D {xValues series label destinationDir {xUnit ""}} {
    set count [llength $xValues]
    if {$count < 2 || $count > 200000} {
        error "2D transient preview requires between 2 and 200000 X points."
    }
    if {![llength $series] || [llength $series] > 16} {
        error "2D transient preview requires between 1 and 16 Y series."
    }
    foreach field [list $label $xUnit] {
        if {[regexp {[\r\n\t]} $field]} { error "Transient preview labels and units must be one line without tabs." }
    }
    set headings {}
    set units {}
    set columns [list $xValues]
    foreach item $series {
        if {[catch {dict size $item}] || ![dict exists $item values]} {
            error "Each Y series must provide a values list."
        }
        set values [dict get $item values]
        if {[llength $values] != $count} { error "Transient preview X/Y lengths differ." }
        set heading [expr {[dict exists $item label] ? [dict get $item label] : "Y"}]
        set unit [expr {[dict exists $item unit] ? [dict get $item unit] : ""}]
        if {[regexp {[\r\n\t]} "$heading$unit"]} {
            error "Transient preview labels and units must be one line without tabs."
        }
        lappend headings $heading
        lappend units $unit
        lappend columns $values
    }
    foreach column $columns {
        foreach value $column {
            if {![string is double -strict $value] || [catch {set n [expr {double($value)}]}] ||
                    [expr {abs($n)==Inf || $n!=$n}]} {
                error "Transient preview coordinates must be finite numbers."
            }
        }
    }
    file mkdir $destinationDir
    set request [file join $destinationDir transient_curves2d.tsv]
    set fd [open $request w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd $label
        puts $fd $xUnit
        puts $fd [join $headings "\t"]
        puts $fd [join $units "\t"]
        for {set row 0} {$row < $count} {incr row} {
            set values {}
            foreach column $columns { lappend values [format %.17g [lindex $column $row]] }
            puts $fd [join $values "\t"]
        }
    } finally {close $fd}
    try {
        _octave transient2d $request $destinationDir plot.dataset.xy
    } finally {catch {file delete -- $request}}
    set artifact [file join $destinationDir graph.png]
    if {![file isfile $artifact] || [file size $artifact] < 100} {
        error "2D transient Plot Dataset preview failed."
    }
    return [dict create artifact $artifact graph_id plot.dataset.xy transient 1 series_count [llength $series]]
}

proc ::GX::PlotDatasetAPIv3::previewExportCommand {plotRef output} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_3D_API_v1
    return [::GX::PlotDataset3DAPIv1::previewExportCommand $plotRef $output]
}

# Independently sampled transient traces, using the same prepared 2-D renderer.
# Each exact XY pair stays together; no alignment or source publication occurs.
proc ::GX::PlotDatasetAPIv3::renderTransientIndependentCurves2D {series label destinationDir} {
    if {[llength $series]<1 || [llength $series]>64} {error {Independent transient preview needs 1..64 series}}
    if {[regexp {[\r\n\t]} $label]} {error {Preview title must be one line}}
    file mkdir $destinationDir
    set request [file join $destinationDir transient_independent2d.tsv];set f [open $request w]
    fconfigure $f -encoding utf-8 -translation lf
    set total 0
    try {
        puts $f $label;puts $f [llength $series]
        foreach item $series {
            set x [dict get $item x_values];set y [dict get $item y_values];set n [llength $x];incr total $n
            if {$n<1 || $n!=[llength $y] || $total>200000} {error {Independent transient coordinates must match within 200000 total points}}
            set fields [list [dict get $item label] [::GX::datasetPublicationV2DictDefault $item x_unit {}] [::GX::datasetPublicationV2DictDefault $item y_unit {}]]
            foreach text $fields {if {[regexp {[\r\n\t]} $text]} {error {Series labels/units must be one line}}}
            puts $f [join $fields "\t"];puts $f $n
            foreach a $x b $y {
                foreach value [list $a $b] {if {![string is double -strict $value] || [catch {expr {double($value)}} number] || $number!=$number || abs($number)==Inf} {error {Independent transient points must be finite}}}
                puts $f "[format %.17g $a]\t[format %.17g $b]"
            }
        }
    } finally {close $f}
    try {_octave transient_independent2d $request $destinationDir plot.dataset.xy} finally {file delete -force $request}
    set artifact [file join $destinationDir graph.png]
    if {![file isfile $artifact] || [file size $artifact]<100} {error {Independent transient Plot Dataset render failed}}
    return [dict create artifact $artifact graph_id plot.dataset.xy transient 1 series_count [llength $series]]
}

proc ::GX::PlotDatasetAPIv3::previewCompatibility {plotRef} {
    _3d
    tailcall ::GX::PlotDataset3DAPIv1::previewCompatibility $plotRef
}
