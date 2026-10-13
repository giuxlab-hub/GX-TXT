# SPDX-License-Identifier: GPL-3.0-or-later
# Shared extension of the existing read-only Dataset host, worker and RAM frame.
# Two embedded owners at most; one retained source per owner. No Documents.
namespace eval ::GX::Native3DPreview {variable hosts {};variable serial 0}
proc ::GX::native3DPreviewLayer {} {
    return [dict create kind surface source_mode artifact format vtp visible 1 opacity 1 colormap viridis scalar_range {} scalar_array {} vector_array {} radius_array {} opacity_array {} color_array {} sphere_glyphs 0 tube_radius 0 isovalues {} volume_transfer {} volume_sample_distance .05 layer_order 0 representation surface base_color {0.0;0.447;0.741} line_width 1 point_size 4 backface_culling 0 scalar_coloring 0 local_transform {}]
}
proc ::GX::native3DPreviewAcquire {parent id key check prepare {options {}}} {
    variable ::GX::Native3DPreview::hosts
    variable ::GX::DatasetViewer::state
    if {[dict exists $hosts $parent]} {
        set w [dict get $hosts $parent]
        if {[info exists state($w,id)] && $state($w,sourceKey) eq $key && ![catch {datasetViewerCheck $w}]} {
            set state($w,active) 1
            native3DPreviewShow $w
            incr state($w,warmReturns)
            return $w
        }
        datasetViewerClose $w
    }
    if {[dict size $hosts]>=2} {datasetViewerClose [dict get $hosts [lindex [dict keys $hosts] 0]]}
    catch {destroy $parent.native3dError}
    set canvas $parent.native3d
    if {![winfo exists $canvas]} {canvas $canvas -background white -highlightthickness 0}
    set w [meshDatasetViewerOpen $id {} [dict create compactCanvas $canvas sourceKey $key sourceCheck $check active 1 geometryBuilds 0 warmReturns 0 caption {Preparing interactive preview…} toolsY [datasetPublicationV2DictDefault $options tools_y 8]]]
    dict set hosts $parent $w
    set state($w,embeddedCanvas) $canvas;set state($w,hostParent) $parent
    set state($w,started) [clock milliseconds]
    native3DPreviewControls $w
    native3DPreviewShow $w
    if {[catch {uplevel #0 [list {*}$prepare $w]} message]} {native3DPreviewFailure $w $message}
    return $w
}
proc ::GX::native3DPreviewControls {w} {
    variable ::GX::DatasetViewer::state
    set c $state($w,compactCanvas)
    catch {destroy $c.tools}
    ttk::frame $c.tools
    foreach {name glyph row col action tip} {
        ccw ↶ 0 0 ccw {Roll counterclockwise}
        up ▲ 0 1 up {Rotate upward}
        cw ↷ 0 2 cw {Roll clockwise}
        left ◀ 1 0 left {Rotate left}
        reset ■ 1 1 reset {Restore original camera, roll and projection}
        right ▶ 1 2 right {Rotate right}
        down ▼ 2 1 down {Rotate downward}
    } {
        ttk::button $c.tools.$name -text $glyph -width 3 -command [list ::GX::native3DPreviewCamera $w $action]
        grid $c.tools.$name -row $row -column $col -padx 1 -pady 1
        native2DViewportTooltip $c.tools.$name $tip
    }
    ttk::button $c.tools.axes -text ▦ -width 3 -command [list ::GX::native3DPreviewAxes $w]
    grid $c.tools.axes -row 2 -column 0 -padx 1 -pady 1
    native2DViewportTooltip $c.tools.axes {Show / Hide Scientific Axes & Grid}
    ttk::button $c.tools.exit -text ✕ -width 3 -command [list ::GX::native3DPreviewExit $w]
    grid $c.tools.exit -row 2 -column 2 -padx 1 -pady 1
    native2DViewportTooltip $c.tools.exit {Exit / Close interactive view}
    if {![info exists state($w,scientificFigure)]} {$c.tools.axes configure -state disabled}
    bind $c <ButtonPress-1> [list ::GX::meshDatasetDrag $w start orbit %x %y]
    bind $c <B1-Motion> [list ::GX::meshDatasetDrag $w move orbit %x %y]
    bind $c <ButtonPress-2> [list ::GX::meshDatasetDrag $w start pan %x %y]
    bind $c <B2-Motion> [list ::GX::meshDatasetDrag $w move pan %x %y]
    bind $c <Button-4> [list ::GX::meshDatasetNavigate $w zoom 1 0]
    bind $c <Button-5> [list ::GX::meshDatasetNavigate $w zoom -1 0]
    bind $c <Double-1> [list ::GX::native3DPreviewEnlarge $w]
    place $c.tools -relx 1 -x -8 -y $state($w,toolsY) -anchor ne
    bind $c <Map> [list ::GX::native3DPreviewMap $w]
    bind $c <Configure> [list ::GX::native3DPreviewResize $w]
    bind $c <Destroy> [list ::GX::native3DPreviewDestroyed $w %W]
}
proc ::GX::native3DPreviewShow {w} {
    variable ::GX::DatasetViewer::state
    set c $state($w,compactCanvas)
    if {[info exists state($w,largeWindow)]} {raise $state($w,largeWindow);return}
    place $c -relwidth 1 -relheight 1
    if {[info exists state($w,hostParent)] && [winfo exists $state($w,hostParent).interactive]} {place forget $state($w,hostParent).interactive}
    raise $c;raise $c.tools
    native3DPreviewDisplay $w
}
proc ::GX::native3DPreviewMap {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)] || !$state($w,active)} return
    if {[catch {datasetViewerCheck $w} message]} {native3DPreviewFailure $w $message;return}
    native3DPreviewDisplay $w
    if {$state($w,ready) && $state($w,image) eq {}} {meshDatasetRender $w}
}
proc ::GX::native3DPreviewResize {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)] || !$state($w,active) || !$state($w,ready)} return
    set c $state($w,compactCanvas)
    set size [list [expr {max(320,min(4096,[winfo width $c]))}] [expr {max(240,min(4096,[winfo height $c]))}]]
    if {[info exists state($w,previewRenderSize)] && $size eq $state($w,previewRenderSize)} return
    if {[info exists state($w,drawJob)]} {after cancel $state($w,drawJob)}
    set state($w,drawJob) [after 150 [list ::GX::meshDatasetRender $w]]
}
proc ::GX::native3DPreviewDisplay {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set c $state($w,compactCanvas)
    if {![winfo exists $c]} return
    $c delete all
    if {$state($w,image) ne {}} {$c create image 0 0 -anchor nw -image $state($w,image);set state($w,frameReadyMs) [expr {[clock milliseconds]-$state($w,started)}]}
    if {[info exists state($w,scientificFigure)]} {raise $c.tools;return}
    $c create text 8 8 -anchor nw -text $state($w,caption) -width [expr {max(140,[winfo width $c]-150)}] -fill #202020 -tags caption
    if {[info exists state($w,colorbar)] && [dict get $state($w,colorbar) visible]} {
        set bar $state($w,colorbar);set colors [dict get $bar palette]
        set height [expr {max(40,min(180,[winfo height $c]-210))}];set x [expr {[winfo width $c]-76}];set y [expr {[winfo height $c]-$height-30}]
        set n [llength $colors];set i 0
        foreach color $colors {
            set top [expr {$y+$height*(1.0-($i+1.0)/$n)}];set bottom [expr {$y+$height*(1.0-$i/double($n))}]
            $c create rectangle $x $top [expr {$x+14}] $bottom -fill $color -outline {};incr i
        }
        lassign [dict get $bar range] lo hi
        $c create text [expr {$x+18}] $y -anchor nw -text [format %.5g $hi]
        $c create text [expr {$x+18}] [expr {$y+$height}] -anchor sw -text [format %.5g $lo]
        $c create text [expr {$x+14}] [expr {$y+$height+8}] -anchor n -text [dict get $bar label] -width 140
    }
    raise $c.tools
}
proc ::GX::native3DPreviewCamera {w action} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,initialCamera)]} return
    switch $action {
        left {meshDatasetNavigate $w orbit -24 0}
        right {meshDatasetNavigate $w orbit 24 0}
        up {meshDatasetNavigate $w orbit 0 -24}
        down {meshDatasetNavigate $w orbit 0 24}
        cw {meshDatasetNavigate $w roll 24 0}
        ccw {meshDatasetNavigate $w roll -24 0}
        reset {meshDatasetRequest $w [list camera $state($w,initialCamera) [file join $state($w,temp) render.png]]}
    }
}
proc ::GX::native3DPreviewExit {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[info exists state($w,largeWindow)]} {native3DPreviewLargeClose $w;return}
    set state($w,active) 0
    place forget $state($w,compactCanvas)
    # An in-flight preparation is cancelled; completed frames/scenes are retained.
    if {![info exists state($w,initialCamera)]} {datasetViewerClose $w}
    native3DPreviewPlotIcon
}
proc ::GX::native3DPreviewClosed {w} {
    variable ::GX::Native3DPreview::hosts
    variable ::GX::DatasetViewer::state
    if {[info exists state($w,largeWindow)]} {set large $state($w,largeWindow);unset state($w,largeWindow);catch {destroy $large}}
    if {[info exists state($w,exportDialog)]} {catch {destroy $state($w,exportDialog)}}
    set c $state($w,compactCanvas)
    if {[info exists state($w,embeddedCanvas)]} {set c $state($w,embeddedCanvas)}
    if {[winfo exists $c]} {place forget $c;catch {destroy $c.tools};$c delete all}
    if {[info exists state($w,hostParent)]} {after idle ::GX::native3DPreviewPlotIcon}
    dict for {parent host} $hosts {if {$host eq $w} {dict unset hosts $parent}}
}
proc ::GX::native3DPreviewRelease {parent} {
    variable ::GX::Native3DPreview::hosts
    if {[dict exists $hosts $parent]} {datasetViewerClose [dict get $hosts $parent]}
}
proc ::GX::native3DPreviewFailure {w message} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set c $state($w,compactCanvas);set parent [winfo parent $c]
    datasetViewerClose $w
    native3DPreviewDiagnostic $parent $message
}
proc ::GX::native3DPreviewDiagnostic {parent message} {
    if {[winfo exists $parent]} {
        catch {destroy $parent.native3dError}
        ttk::label $parent.native3dError -text "Interactive preview unavailable: $message" -wraplength 650
        place $parent.native3dError -x 8 -y 8
    }
    setStatus "Native3D preview: $message" 100
}
proc ::GX::native3DPreviewDestroyed {w widget} {
    variable ::GX::DatasetViewer::state
    if {[info exists state($w,embeddedCanvas)] && $state($w,embeddedCanvas) eq $widget} {datasetViewerClose $w}
}
proc ::GX::native3DPreviewPrepared {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,preparePipe)]} return
    set pipe $state($w,preparePipe)
    while {[gets $pipe line]>=0} {append state($w,prepareLog) "$line\n"}
    if {![eof $pipe]} return
    fileevent $pipe readable {}
    unset state($w,preparePipe)
    if {[catch {close $pipe} message] || ![file isfile [file join $state($w,temp) scene.tcldict]]} {
        native3DPreviewFailure $w "Scientific scene export failed: $state($w,prepareLog) $message";return
    }
    if {[catch {
        datasetViewerCheck $w
        set f [open [file join $state($w,temp) scene.tcldict]]
        try {set descriptor [read $f 8388608]} finally {close $f}
        set state($w,compactLayers) [dict get $descriptor layers]
        set state($w,view) [dict merge [viewerSceneDefaults] [dict get $descriptor view]]
        set state($w,caption) [dict get $descriptor caption]
        if {[info exists state($w,sourceInfo)]} {
            append state($w,caption) "\nDataset: $state($w,id) · Variant: [dict get $state($w,sourceInfo) plot_ref variant_id]"
        }
        if {[dict exists $descriptor scientific_figure]} {set state($w,scientificFigure) [dict get $descriptor scientific_figure];set state($w,presentation) [dict get $descriptor presentation];$state($w,compactCanvas).tools.axes configure -state normal}
        if {[dict exists $descriptor colorbar]} {set state($w,colorbar) [dict get $descriptor colorbar]}
        meshDatasetWorkerStart $w
    } message]} {native3DPreviewFailure $w $message}
}
proc ::GX::native3DPreviewPlotKey {ref} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set artifact [dict get [::GX::PlotDatasetAPIv3::artifacts $ref] graph_artifact]
    file stat $artifact st
    set key [plotVariantKey [dict get $ref graph_id] [dict get $ref variant_id]]
    set presentation {}
    foreach array {axisOverride legendOverride levelScale plotVariantGraphics} {
        upvar #0 ::GX::$array a
        foreach name [lsort [array names a]] {
            if {[string match "$key,*" $name] || [string match "plot.dataset,[dict get $ref graph_id],[dict get $ref variant_id],*" $name]} {lappend presentation $array $name $a($name)}
        }
    }
    set sources {}
    foreach role {x y z family color} {
        set b [plotVariantBindingGet plot.dataset plot.dataset.xyz [dict get $ref variant_id] $role]
        if {$b eq {}} continue
        set id [dict get $b dataset_id]
        lappend sources $role $b [datasetViewerStamp $id [datasetResolvePath $::GX::currentSession $id]]
    }
    set config {}
    foreach field [moduleConfigKeys plot.dataset] {if {[info exists ::GX::moduleCfg(plot.dataset,$field)]} {lappend config $field $::GX::moduleCfg(plot.dataset,$field)}}
    set resources {}
    set artifacts [::GX::PlotDatasetAPIv3::artifacts $ref]
    foreach path [list [dict get $artifacts render_cache] [file join [dict get $artifacts output_dir] runtime.ini]] {
        if {[file isfile $path]} {file stat $path r; lappend resources $path $r(ino) $r(size) $r(mtime) $r(ctime)} else {lappend resources $path missing}
    }
    return [list $resources $config [interactiveDocumentSessionToken] $ref [::GX::PlotDatasetAPIv3::readPlot $ref] $sources $st(ino) $st(mtime) $st(ctime) $st(size) $presentation [plotEnv plot.dataset]]
}
proc ::GX::native3DPreviewPlotPrepare {ref w} {
    variable ::GX::DatasetViewer::state
    set state($w,sourceInfo) [::GX::PlotDatasetAPIv3::interactiveSourceInfo $ref]
    set command [::GX::PlotDatasetAPIv3::previewExportCommand $ref $state($w,temp)]
    set state($w,prepareLog) {}
    if {[auto_execok prlimit] ne {}} {set command [concat [list [auto_execok prlimit] --as=[expr {[configurationGet viewers.native3d.worker_address_space_budget_mib]*1024*1024}] --] $command]}
    if {[auto_execok setsid] ne {}} {set command [concat [list [auto_execok setsid]] $command];set state($w,prepareGroup) 1}
    set state($w,preparePipe) [open [concat [list |] $command [list 2>@1]] r]
    fconfigure $state($w,preparePipe) -blocking 0 -buffering line
    fileevent $state($w,preparePipe) readable [list ::GX::native3DPreviewPrepared $w]
}
proc ::GX::native3DPreviewPlotActivate {} {
    if {[catch {
        set ref [graphResourceRefForPath [currentGraphPath]]
        if {[dict get $ref module_id] ne "plot.dataset" || [dict get $ref graph_id] ne "plot.dataset.xyz"} {error {Select an existing Plot Dataset 3D graph/Variant.}}
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        set info [::GX::PlotDatasetAPIv3::interactiveSourceInfo $ref]
        set key [native3DPreviewPlotKey $ref]
        native3DPreviewAcquire .top.nb.graphs.preview.img [dict get $info source_dataset_id] $key [list ::GX::native3DPreviewPlotKey $ref] [list ::GX::native3DPreviewPlotPrepare $ref]
    } message]} {native3DPreviewDiagnostic .top.nb.graphs.preview.img $message}
}
proc ::GX::native3DPreviewPlotSelection {} {
    variable ::GX::Native3DPreview::hosts
    set parent .top.nb.graphs.preview.img
    native3DPreviewPlotIcon
    if {![dict exists $hosts $parent]} return
    set w [dict get $hosts $parent]
    variable ::GX::DatasetViewer::state
    if {[catch {set ref [graphResourceRefForPath [currentGraphPath]]}] || $ref ne [lindex $state($w,sourceCheck) 1]} {native3DPreviewRelease $parent}
}
proc ::GX::native3DPreviewXYZKey {id axes} {
    set selectors {}
    foreach axis {x y z} {if {[info exists ::GX::ui(previewMap,$axis)]} {lappend selectors $::GX::ui(previewMap,$axis)}}
    return [list $selectors [interactiveDocumentSessionToken] [datasetViewerStamp $id [datasetResolvePath $::GX::currentSession $id]] [datasetMetadataRead $::GX::currentSession $id] $axes]
}
proc ::GX::native3DPreviewXYZActivate {} {
    if {[catch {
        lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
        if {$mode ne "imported"} {error {Activate a canonical numerical Dataset.}}
        set axes [list $::GX::ui(previewMap,x) $::GX::ui(previewMap,y) $::GX::ui(previewMap,z)]
        if {{} in $axes || [llength [lsort -unique $axes]]!=3} {error {Select three explicit, distinct canonical X/Y/Z variable IDs.}}
        if {[dict size $::GX::ui(previewMap,filters)] || $::GX::ui(previewMap,separate)} {error {XYZ scatter currently requires the unfiltered Dataset; clear the 2D family filters first.}}
        # XYZ activation owns the current mapping. Keep the last static 2D
        # content intact; an explicit 2D Render remains its generation action.
        # Source changes still invalidate through the common stamp/watch.
        set ::GX::ui(previewSignature) [datasetPreviewCacheSignature]
        set key [native3DPreviewXYZKey $id $axes]
        native3DPreviewAcquire .top.nb.preview.txt $id $key [list ::GX::native3DPreviewXYZKey $id $axes] [list ::GX::native3DPreviewXYZPrepare $id $axes] [dict create tools_y 50]
    } message]} {native3DPreviewDiagnostic .top.nb.preview.txt $message}
}
proc ::GX::native3DPreviewXYZPrepare {id axes w} {
    variable ::GX::DatasetViewer::state
    set labels {}
    foreach axis {X Y Z} vid $axes {
        set v [datasetVariableV3ById $id $vid]
        if {![dict get $v enabled] || [dict get $v rank]!=1 || [dict get $v value_kind] eq "text"} {error "Variable $vid is not an enabled rank-one numerical variable."}
        lappend labels "$axis: $vid — [dict get $v canonical] ([dict get $v unit])"
    }
    set access [datasetAccessOpen $::GX::currentSession $id]
    try {set rows [dict get [datasetAccessMetadata $access] row_count]} finally {datasetAccessClose $access}
    set limit [expr {$rows<0?100000:min(100000,$rows)}]
    set stream [tableStreamOpenDataset $::GX::currentSession $id $axes 2048 [dict create count $limit]]
    set total [dict get [tableStreamMetadata $stream] row_count]
    set state($w,xyzStream) $stream;set state($w,xyzAxes) $axes
    set state($w,xyzTotal) $total;set state($w,xyzRows) 0;set state($w,xyzPoints) {};set state($w,xyzSourceRows) {}
    set state($w,xyzStride) [expr {max(1,int(ceil(($total<0?100000:min(100000,$total))/12000.0)))}]
    set state($w,caption) "$id · read-only 3D scatter\n[join $labels { · }]"
    set state($w,prepareAfter) [after idle [list ::GX::native3DPreviewXYZChunk $w]]
}
proc ::GX::native3DPreviewXYZChunk {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,xyzStream)]} return
    if {[catch {
        datasetViewerCheck $w
        set chunk [tableStreamNext $state($w,xyzStream)]
        lassign $state($w,xyzAxes) x y z
        set n 0
        foreach xv [dict get $chunk values $x] yv [dict get $chunk values $y] zv [dict get $chunk values $z] {
            set row [expr {[dict get $chunk offset]+$n}];incr n
            if {$row%$state($w,xyzStride) || [llength $state($w,xyzPoints)]>=12000} continue
            if {[catch {expr {abs(double($xv))<Inf && abs(double($yv))<Inf && abs(double($zv))<Inf}} finite] || !$finite} continue
            lappend state($w,xyzPoints) [list $xv $yv $zv]
            lappend state($w,xyzSourceRows) [expr {$row+1}]
        }
        incr state($w,xyzRows) [dict get $chunk nrows]
        if {![dict get $chunk eof]} {
            set state($w,prepareAfter) [after 1 [list ::GX::native3DPreviewXYZChunk $w]]
            return
        }
        tableStreamClose $state($w,xyzStream);unset state($w,xyzStream)
        set points $state($w,xyzPoints);set count [llength $points]
        if {!$count} {error {No finite XYZ triples in the bounded display selection.}}
        set path [file join $state($w,temp) xyz.vtp]
        set f [open $path w]
        try {
            puts $f "<?xml version=\"1.0\"?><VTKFile type=\"PolyData\" version=\"0.1\" byte_order=\"LittleEndian\"><PolyData><Piece NumberOfPoints=\"$count\" NumberOfVerts=\"$count\" NumberOfLines=\"0\" NumberOfStrips=\"0\" NumberOfPolys=\"0\">"
            puts $f {<PointData><DataArray type="Int64" Name="source_row" format="ascii">}
            puts $f $state($w,xyzSourceRows);puts $f {</DataArray></PointData><Points><DataArray type="Float64" NumberOfComponents="3" format="ascii">}
            foreach point $points {puts $f $point}
            puts $f {</DataArray></Points><Verts><DataArray type="Int64" Name="connectivity" format="ascii">}
            for {set i 0} {$i<$count} {incr i} {puts -nonewline $f "$i "}
            puts $f {</DataArray><DataArray type="Int64" Name="offsets" format="ascii">}
            for {set i 1} {$i<=$count} {incr i} {puts -nonewline $f "$i "}
            puts $f {</DataArray></Verts></Piece></PolyData></VTKFile>}
        } finally {close $f}
        set layer [dict merge [native3DPreviewLayer] [dict create absolute_path $path resource_path $path sha256 [sha256File $path] kind points representation points]]
        set state($w,compactLayers) [dict create scatter $layer]
        set state($w,view) [dict replace [viewerSceneDefaults] background_rgb {1;1;1} lighting 0 axes_world 0 orientation_indicator_visible 1]
        append state($w,caption) "\n$count finite points; [expr {$state($w,xyzTotal)<0?{unknown}:$state($w,xyzTotal)}] canonical rows. Display scan: first $state($w,xyzRows) rows (limit 100000); stride $state($w,xyzStride), point limit 12000. No connectivity or interpolation."
        set state($w,xyzDisplayReceipt) [dict create dataset_id $state($w,id) variable_ids $state($w,xyzAxes) total_rows $state($w,xyzTotal) scanned_rows $state($w,xyzRows) displayed_points $count stride $state($w,xyzStride) source_rows $state($w,xyzSourceRows)]
        unset state($w,xyzPoints) state($w,xyzSourceRows)
        meshDatasetWorkerStart $w
    } message]==1} {native3DPreviewFailure $w $message}
}

# Same shared host/worker/source; an enlarged viewport never prepares another scene.
proc ::GX::native3DPreviewPlotIcon {} {
    set parent .top.nb.graphs.preview.img
    if {![winfo exists $parent.interactive]} return
    place forget $parent.interactive
    if {[dict exists $::GX::Native3DPreview::hosts $parent]} {
        set w [dict get $::GX::Native3DPreview::hosts $parent]
        if {[info exists ::GX::DatasetViewer::state($w,active)] && $::GX::DatasetViewer::state($w,active)} return
    }
    if {[catch {
        set ref [graphResourceRefForPath [currentGraphPath]]
        if {[dict get $ref module_id] ne "plot.dataset" || [dict get $ref graph_id] ne "plot.dataset.xyz"} {error unsupported}
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        ::GX::PlotDatasetAPIv3::previewCompatibility $ref
    } message]} {set ::GX::ui(native3DEligibility) $message;return}
    set ::GX::ui(native3DEligibility) supported
    place $parent.interactive -relx 1 -x -8 -y 8 -anchor ne
    raise $parent.interactive
}
proc ::GX::native3DPreviewAxes {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,scientificFigure)] || $state($w,busy)} return
    set visible [expr {![dict get $state($w,scientificFigure) axes_grid_visible]}]
    dict set state($w,scientificFigure) axes_grid_visible $visible
    meshDatasetRequest $w [list scientific_axes $visible [file join $state($w,temp) render.png]]
}
proc ::GX::native3DPreviewEnlarge {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,initialCamera)] || $state($w,busy)} return
    datasetViewerCheck $w
    if {[info exists state($w,largeWindow)]} {raise $state($w,largeWindow);return}
    set large .gxNative3DLarge[incr ::GX::Native3DPreview::serial]
    toplevel $large;wm title $large {GX-TXT — Interactive scientific 3D}
    wm geometry $large 1200x820;wm minsize $large 720 480
    wm protocol $large WM_DELETE_WINDOW [list ::GX::native3DPreviewLargeClose $w]
    ttk::frame $large.bar;pack $large.bar -side bottom -fill x
    ttk::button $large.bar.save -text {Save High-Resolution Image as Dataset…} -command [list ::GX::native3DPreviewSaveDialog $w]
    pack $large.bar.save -side left -padx 8 -pady 5
    ttk::label $large.bar.hint -text {Drag: orbit · Middle drag: pan · Wheel: zoom}
    pack $large.bar.hint -side right -padx 8
    canvas $large.canvas -background white -highlightthickness 0;pack $large.canvas -fill both -expand 1
    set state($w,largeWindow) $large
    place forget $state($w,embeddedCanvas)
    set state($w,compactCanvas) $large.canvas
    native3DPreviewControls $w
    native3DPreviewDisplay $w
    after idle [list ::GX::native3DPreviewResize $w]
}
proc ::GX::native3DPreviewLargeClose {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,largeWindow)]} return
    set large $state($w,largeWindow);unset state($w,largeWindow)
    if {[info exists state($w,exportDialog)]} {catch {destroy $state($w,exportDialog)};unset state($w,exportDialog)}
    set state($w,compactCanvas) $state($w,embeddedCanvas)
    destroy $large
    native3DPreviewShow $w
    native3DPreviewResize $w
}
proc ::GX::native3DPreviewSaveDialog {w} {
    variable ::GX::DatasetViewer::state
    if {$state($w,busy)} {setStatus {Wait for the current Native3D render before saving.} 100;return}
    if {![info exists state($w,sourceInfo)] || ![info exists state($w,scientificFigure)]} {setStatus {High-resolution Dataset publication requires an identified scientific graph.} 100;return}
    if {[info exists state($w,exportDialog)] && [winfo exists $state($w,exportDialog)]} {raise $state($w,exportDialog);return}
    set d $state($w,largeWindow).save
    toplevel $d;wm title $d {Save Native3D image Dataset};wm transient $d $state($w,largeWindow)
    set state($w,exportDialog) $d
    set state($w,exportId) "native3d.[dict get $state($w,sourceInfo) plot_ref variant_id].[clock seconds]"
    set state($w,exportResolution) {Full HD — 1920 × 1080}
    set state($w,exportStatus) {}
    ttk::label $d.idLabel -text {New Dataset ID:};ttk::entry $d.id -textvariable ::GX::DatasetViewer::state($w,exportId) -width 40
    ttk::label $d.resLabel -text {Image resolution:}
    ttk::combobox $d.resolution -textvariable ::GX::DatasetViewer::state($w,exportResolution) -state readonly -values {{Full HD — 1920 × 1080} {4K — 3840 × 2160}} -width 32
    ttk::label $d.info -text "Current camera, scientific presentation and graphics supersampling policy.\nExisting Dataset IDs are preserved. Native3D resource budgets apply." -wraplength 460
    ttk::label $d.status -textvariable ::GX::DatasetViewer::state($w,exportStatus) -wraplength 460
    ttk::button $d.save -text {Render & Publish Dataset} -command [list ::GX::native3DPreviewSave $w]
    ttk::button $d.close -text Close -command [list destroy $d]
    grid $d.idLabel $d.id -sticky ew -padx 8 -pady 6
    grid $d.resLabel $d.resolution -sticky ew -padx 8 -pady 6
    grid $d.info -columnspan 2 -sticky ew -padx 8 -pady 6
    grid $d.status -columnspan 2 -sticky ew -padx 8 -pady 6
    grid $d.save $d.close -padx 8 -pady 8
}
proc ::GX::native3DPreviewSave {w} {
    variable ::GX::DatasetViewer::state
    if {$state($w,busy)} return
    if {[catch {
        datasetViewerCheck $w
        set id [datasetPublicationV2ValidateId dataset [string trim $state($w,exportId)]]
        if {[datasetField $id id {}] ne {}} {error "Dataset '$id' already exists; choose a new ID."}
        set size [expr {[string match {4K*} $state($w,exportResolution)]?{3840 2160}:{1920 1080}}]
        set requestedPolicy [native3dGraphicsPolicy];set policy $requestedPolicy
        if {[info exists state($w,previewSoftware)] && $state($w,previewSoftware)} {dict set policy execution Software}
        set factor [dict get $policy export_supersampling]
        lassign $size width height
        if {$width*$height*4*$factor*$factor>268435456} {error "Requested image exceeds Native3D's 256 MiB pixel budget at ${factor}× supersampling; choose Full HD or change the existing graphics export policy."}
        set source $state($w,sourceInfo)
        set sources {};set hashes {}
        dict for {role binding} [dict get $source bindings] {
            if {$binding eq {}} continue
            set ds [dict get $binding dataset_id]
            lappend sources $ds
            dict set hashes $ds [dict get [sessionInspectionDatasetPayload $ds] sha256]
        }
        set state($w,exportRequest) [dict create dataset_id $id dimensions $size camera $state($w,view) scientific_figure $state($w,scientificFigure) presentation $state($w,presentation) source $source source_dataset_ids [lsort -unique $sources] source_sha256 $hashes graphics_policy $policy requested_graphics_policy $requestedPolicy]
        set state($w,exportStatus) {Rendering high-resolution scientific image…}
        file delete -force [file join $state($w,temp) screenshot.png]
        meshDatasetRequest $w [list export_png [file join $state($w,temp) screenshot.png] $width $height $policy]
    } message]} {set state($w,exportStatus) $message}
}
proc ::GX::native3DPreviewExportReady {w status result} {
    variable ::GX::DatasetViewer::state
    if {$status ne "ok"} {
        set state($w,exportStatus) "Image rendering failed: $result";unset -nocomplain state($w,exportRequest)
        file delete -force [file join $state($w,temp) screenshot.png]
        if {$state($w,pending) ne {}} {set request $state($w,pending);set state($w,pending) {};meshDatasetRequest $w $request}
        return
    }
    if {[catch {
        datasetViewerCheck $w
        set request $state($w,exportRequest);unset state($w,exportRequest)
        set path [file join $state($w,temp) screenshot.png]
        set photo [image create photo -file $path]
        set dimensions [list [image width $photo] [image height $photo]];image delete $photo
        if {$dimensions ne [dict get $request dimensions]} {error {Native3D image dimensions do not match the completed export.}}
        set metadata [dict create image.width [lindex $dimensions 0] image.height [lindex $dimensions 1] rendering.engine Native3D rendering.settings [dict get $request graphics_policy] rendering.requested_settings [dict get $request requested_graphics_policy] rendering.camera [dict get $request camera] rendering.scientific_figure [dict get $request scientific_figure] rendering.plot_presentation [dict get $request presentation] source.plot_reference [dict get $request source plot_ref] source.plot_fingerprint [dict get $request source fingerprint] source.dataset_sha256 [dict get $request source_sha256] source.bindings [dict get $request source bindings]]
        set before [sha256File $path]
        set receipt [datasetFilePublicationPublish $::GX::currentSession core.native3d [dict create dataset_id [dict get $request dataset_id] contract image.raster format png source_file $path storage_kind binary media_type image/png producer_version $::GX::version source_dataset_ids [dict get $request source_dataset_ids] source {Native3D scientific graph screenshot} provenance "Current Native3D camera and calibrated presentation of [dict get $request source plot_ref]" structured_metadata $metadata]]
        if {[dict get $receipt sha256] ne $before} {error {Published image SHA-256 verification failed.}}
        set state($w,lastPublication) $receipt
        set state($w,exportStatus) "Published Dataset [dict get $receipt dataset_id] — [join $dimensions ×] PNG; SHA-256 verified."
        catch {refreshDatasetInspectionChoices};catch {refreshNativeVariablesGui}
        setStatus $state($w,exportStatus) 100
    } message]} {set state($w,exportStatus) "Image publication failed: $message"}
    if {$state($w,pending) ne {}} {set request $state($w,pending);set state($w,pending) {};meshDatasetRequest $w $request}
}
