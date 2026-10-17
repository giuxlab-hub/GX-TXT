# SPDX-License-Identifier: GPL-3.0-or-later
# Isolated consultation host for the existing Native3D/VTK bridge. Its worker
# only receives read/render/camera commands. No Scene/Document/Dataset writes.
proc ::GX::meshDatasetViewerOpen {id {previewWidget {}} {request {}}} {
    variable ::GX::DatasetViewer::state
    set payload [sessionInspectionDatasetPayload $id]
    set structural [expr {[dict get [datasetViewerDescribe $id] target] eq "structure"||[dict get $payload format] in {cube cub}}]
    if {$request eq {}&&!$structural&&[string tolower [dict get $payload format]] ni {stl obj step stp vtp vtu vti}} {error {CORE Native3D intake cannot decode this payload format yet. Source bytes are preserved.}}
    set w [datasetViewerWindow $id {CORE Mesh Dataset Viewer}]
    if {$request ne {}} {
        wm withdraw $w
        dict for {key value} $request {set state($w,$key) $value}
    }
    if {$previewWidget ne {}} {wm withdraw $w;set state($w,previewWidget) $previewWidget;set state($w,previewChoice) $::GX::variableDatasetChoice;set state($w,previewStamp) [datasetPreviewStamp];set state($w,previewEpoch) $::GX::ui(previewEpoch);meshDatasetPreviewBuild $w}
    set f [file tempfile temp];close $f;file delete $temp;file mkdir $temp;set state($w,temp) $temp
    set state($w,view) [dict replace [viewerSceneDefaults] axes_world 1]
    set state($w,mode) surface;set state($w,scalar) {};set state($w,kind) surface;set state($w,levels) {};set state($w,colormap) viridis
    set state($w,image) {};set state($w,busy) 0;set state($w,pending) {};set state($w,ready) 0
    # Same presentation defaults used by Viewer Provider. These dictionaries
    # exist only in this window; no provider registration or activation required.
    set state($w,layer) [meshDatasetLayer $payload]
    ttk::frame $w.bar;pack $w.bar -fill x
    foreach {label preset} {Fit fit_scene Iso isometric Front front Back back Left left Right right Top top Bottom bottom} {
        ttk::button $w.bar.$preset -text $label -command [list ::GX::meshDatasetPreset $w $preset]
        pack $w.bar.$preset -side left -padx 3 -pady 5
    }
    ttk::button $w.bar.cancel -text {Cancel / Close} -command [list ::GX::datasetViewerClose $w];pack $w.bar.cancel -side right
    ttk::frame $w.fields;pack $w.fields -fill x
    foreach {key title values} {mode Representation {surface wireframe surface_edges points} scalar {Scalar array} {} kind {Field view} {surface isosurface} colormap {Color map} {viridis cool_warm grayscale}} {
        ttk::label $w.fields.${key}Label -text $title
        ttk::combobox $w.fields.$key -textvariable ::GX::DatasetViewer::state($w,$key) -values $values -state readonly -width 17
        pack $w.fields.${key}Label $w.fields.$key -side left -padx 3 -pady 4
    }
    ttk::frame $w.iso;pack $w.iso -fill x
    ttk::label $w.iso.label -text {Isovalues (semicolon separated):}
    ttk::entry $w.iso.levels -textvariable ::GX::DatasetViewer::state($w,levels) -width 35
    ttk::button $w.iso.apply -text {Apply display} -command [list ::GX::meshDatasetRender $w]
    pack $w.iso.label $w.iso.levels $w.iso.apply -side left -padx 4
    canvas $w.canvas -width 960 -height 440 -background #202732 -highlightthickness 0;pack $w.canvas -fill both -expand 1
    ttk::frame $w.details;pack $w.details -fill x
    text $w.summary -height 5 -wrap word -state disabled -yscrollcommand [list $w.details.scroll set]
    ttk::scrollbar $w.details.scroll -command [list $w.summary yview];pack $w.details.scroll -side right -fill y
    pack $w.summary -in $w.details -fill x
    bind $w.canvas <ButtonPress-1> [list ::GX::meshDatasetDrag $w start orbit %x %y]
    bind $w.canvas <B1-Motion> [list ::GX::meshDatasetDrag $w move orbit %x %y]
    bind $w.canvas <ButtonPress-2> [list ::GX::meshDatasetDrag $w start pan %x %y]
    bind $w.canvas <B2-Motion> [list ::GX::meshDatasetDrag $w move pan %x %y]
    bind $w.canvas <Button-4> [list ::GX::meshDatasetNavigate $w zoom 1 0]
    bind $w.canvas <Button-5> [list ::GX::meshDatasetNavigate $w zoom -1 0]
    set metadata [datasetMetadataRead $::GX::currentSession $id]
    set state($w,units) [datasetPublicationV2DictDefault $metadata geometry.working_unit {undeclared — raw coordinates}]
    if {[dict get $payload format] in {step stp}} {set state($w,units) {STEP units interpreted by OCCT; normalized coordinate unit is not exposed by the CORE summary}}
    if {$request ne {}} {
        set state($w,status) {Preparing read-only Native3D preview…}
    } elseif {$structural} {
        set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python structure_consultation.py] [dict get $payload path] $temp]
        set state($w,decoder) [open [concat [list |] $command [list 2>[file join $temp decoder.log]]] r]
        fconfigure $state($w,decoder) -blocking 0 -buffering line
        fileevent $state($w,decoder) readable [list ::GX::meshDatasetDecoded $w]
        set state($w,status) {Decoding canonical structure in an isolated worker…}
    } else {meshDatasetWorkerStart $w}
    return $w
}
proc ::GX::meshDatasetWorkerStart {w} {
    variable ::GX::DatasetViewer::state
    set temp $state($w,temp)
    if {[catch {
        set command [list [auto_execok tclsh] [file join $::GX::scriptDir core native3d renderer_worker.tcl] [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so] readonly]
        if {[auto_execok prlimit] ne {}} {set command [concat [list prlimit --as=[expr {[configurationGet viewers.native3d.worker_address_space_budget_mib]*1024*1024}] --] $command]}
        set command [concat [list env LIBGL_ALWAYS_INDIRECT=0] $command]
        set state($w,previewSoftware) [expr {([info exists state($w,previewWidget)] || [info exists state($w,compactCanvas)]) && [configurationGet viewers.native3d.execution] eq "Auto"}]
        if {[configurationGet viewers.native3d.execution] eq "Software" || $state($w,previewSoftware)} {set command [concat [list env LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=llvmpipe] $command]}
        set worker [open [concat [list |] $command [list 2>[file join $temp worker.log]]] r+]
        set state($w,worker) $worker
        fconfigure $worker -blocking 0 -buffering line -encoding utf-8 -translation lf
        fileevent $worker readable [list ::GX::meshDatasetReadable $w]
        set state($w,status) {Opening isolated CORE Native3D renderer…}
    } message]} {set state($w,status) $message}
}
proc ::GX::meshDatasetDecoded {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,decoder)]} return
    set channel $state($w,decoder)
    if {[gets $channel line]<0} {
        if {[eof $channel]} {fileevent $channel readable {};catch {close $channel};unset state($w,decoder);meshDatasetFailure $w {Structural decoder failed. Inspect source format/support; original bytes are unchanged.}}
        return
    }
    if {$line ne "STRUCTURE_READY"} return
    fileevent $channel readable {};catch {close $channel};unset state($w,decoder)
    set layers {}
    foreach name {atoms bonds cell density slice contour} {
        set path [file join $state($w,temp) $name.vtp]
        if {![file isfile $path]} continue
        set layer $state($w,layer);dict set layer absolute_path $path;dict set layer resource_path $path
        dict set layer format vtp;dict set layer sha256 [sha256File $path]
        if {$name in {bonds cell}} {dict set layer representation wireframe;dict set layer line_width 2}
        if {$name eq "atoms"&&[dict get $state($w,identity) format] eq "cif"} {dict set layer kind points;dict set layer representation points;dict set layer radius_array radius_A;dict set layer scalar_array atomic_number}
        if {$name eq "slice"} {dict set layer scalar_array electron_density;dict set layer scalar_coloring 1}
        dict set layers $name $layer
    }
    set state($w,structuralLayers) $layers
    foreach control {fields.mode fields.scalar fields.kind fields.colormap iso.levels iso.apply} {$w.$control state disabled}
    set state($w,units) {source structural coordinates; derived display, inferred bonds explicitly noncanonical}
    foreach p {inspection.json representation.json} {
        set path [file join $state($w,temp) $p]
        if {[file isfile $path]} {set f [open $path];set state($w,structureDetails) [read $f 262144];close $f;break}
    }
    meshDatasetWorkerStart $w
}
proc ::GX::meshDatasetRequest {w request} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,worker)]} return
    if {$state($w,busy)} {set state($w,pending) $request;return}
    if {[catch {datasetViewerCheck $w} reason]} {datasetViewerClose $w;setStatus $reason 100;return}
    set state($w,busy) 1;set state($w,status) {Rendering in isolated Native3D worker; Cancel remains available.}
    set state($w,lastRequest) [lindex $request 0]
    set state($w,requestStarted) [clock milliseconds]
    puts $state($w,worker) $request;flush $state($w,worker)
}
proc ::GX::meshDatasetRender {w} {
    variable ::GX::DatasetViewer::state
    unset -nocomplain state($w,drawJob)
    if {![info exists state($w,ready)]||!$state($w,ready)} return
    set layer $state($w,layer)
    dict set layer representation $state($w,mode);dict set layer scalar_array $state($w,scalar)
    dict set layer scalar_coloring [expr {$state($w,scalar) ne {}}]
    dict set layer kind $state($w,kind);dict set layer isovalues $state($w,levels);dict set layer colormap $state($w,colormap)
    set canvas $w.canvas
    if {[info exists state($w,compactCanvas)]} {set canvas $state($w,compactCanvas)}
    if {[info exists state($w,previewWidget)]} {set canvas .top.nb.preview.geometry}
    if {[info exists state($w,previewWidget)] && ![winfo ismapped $canvas]} return
    set limit [expr {[info exists state($w,compactCanvas)]?4096:1600}]
    set width [expr {max(320,min($limit,[winfo width $canvas]))}];set height [expr {max(240,min($limit,[winfo height $canvas]))}]
    if {[info exists state($w,compactCanvas)]} {
        if {![winfo exists $canvas] || ![winfo ismapped $canvas]} return
        set state($w,previewRenderSize) [list $width $height]
    }
    if {[info exists state($w,previewWidget)]} {set state($w,previewRenderSize) [list $width $height]}
    set layers [dict create data $layer]
    if {[info exists state($w,structuralLayers)]} {set layers $state($w,structuralLayers)}
    if {[info exists state($w,compactLayers)]} {set layers $state($w,compactLayers)}
    set policy [native3dGraphicsPolicy]
    if {[info exists state($w,previewSoftware)] && $state($w,previewSoftware)} {dict set policy execution Software}
    set scene [dict create layers $layers view $state($w,view) graphics_policy $policy cache_root [file join $state($w,temp) derived] session_namespace $::GX::currentSession]
    if {[info exists state($w,compactCanvas)]} {
        if {[info exists state($w,initialCamera)]} {meshDatasetRequest $w [list viewport $width $height [file join $state($w,temp) render.png]];return}
        if {[info exists state($w,scientificFigure)]} {dict set scene scientific_figure $state($w,scientificFigure)}
        incr state($w,geometryBuilds)
        meshDatasetRequest $w [list render $scene [file join $state($w,temp) render.png] $width $height compact]
        return
    }
    meshDatasetRequest $w [list render $scene [file join $state($w,temp) render.png] $width $height [expr {[info exists state($w,previewWidget)]?"preview":"full"}]]
}
proc ::GX::meshDatasetReadable {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,worker)]} return
    set worker $state($w,worker)
    if {[eof $worker]} {fileevent $worker readable {};meshDatasetFailure $w {Native3D worker stopped; close and reopen the Dataset.};return}
    if {[gets $worker line]<0} return
    if {$line eq "GX3DE_VIEWER_WORKER_READY"} {set state($w,ready) 1;meshDatasetRender $w;return}
    set state($w,busy) 0
    lassign $line status result
    if {[info exists state($w,previewWidget)] && ($state($w,previewEpoch)!=$::GX::ui(previewEpoch) || $state($w,previewStamp) ne [datasetPreviewStamp])} {datasetViewerClose $w;return}
    if {$state($w,lastRequest) eq "export_png"} {native3DPreviewExportReady $w $status $result;return}
    if {$status ne "ok"} {set state($w,pending) {};meshDatasetFailure $w "Native3D: $result";return}
    if {[catch {datasetViewerCheck $w} reason]} {datasetViewerClose $w;setStatus $reason 100;return}
    if {$state($w,lastRequest) eq "navcube_pick"} {
        if {$result>0} {meshDatasetRequest $w [list navcube_click {*}$state($w,cubePoint) [file join $state($w,temp) render.png]]}
        return
    }
    set state($w,lastReceipt) $result
    set state($w,lastResponseMs) [expr {[clock milliseconds]-$state($w,requestStarted)}]
    foreach key {projection vertical_fov_degrees near_clip far_clip} {if {[dict exists $result $key]} {dict set state($w,view) $key [dict get $result $key]}}
    foreach key {camera_position camera_target camera_up} {if {[dict exists $result $key]} {dict set state($w,view) $key [join [dict get $result $key] {;}]}}
    set path [file join $state($w,temp) render.png]
    if {[file isfile $path]} {
        if {$state($w,image) ne {}} {image delete $state($w,image)}
        set state($w,image) [image create photo -file $path]
        $w.canvas delete all;$w.canvas create image 0 0 -anchor nw -image $state($w,image)
    }
    if {[info exists state($w,compactCanvas)]} {
        if {![info exists state($w,initialCamera)]} {set state($w,initialCamera) $state($w,view)}
        native3DPreviewDisplay $w
        if {$state($w,pending) ne {}} {set request $state($w,pending);set state($w,pending) {};meshDatasetRequest $w $request}
        return
    }
    if {[dict exists $result geometry]} {
        set arrays {{}};set summary {}
        foreach geometry [dict get $result geometry] {
            append summary "Layer [dict get $geometry layer]: "
            foreach key {vertices triangles points cells} {if {[dict exists $geometry $key]} {append summary "$key [dict get $geometry $key]; "}}
            if {[dict exists $geometry bounds_min]} {append summary "bounds [lmap v [dict get $geometry bounds_min] {format %.6g $v}] to [lmap v [dict get $geometry bounds_max] {format %.6g $v}]."}
            append summary "\n"
            foreach array [datasetPublicationV2DictDefault $geometry arrays {}] {append summary "  [dict get $array name]: [dict get $array components] component(s), [dict get $array tuples] tuples, association [dict get $array association]\n"}
            foreach array [datasetPublicationV2DictDefault $geometry arrays {}] {if {[dict get $array components]==1} {lappend arrays [dict get $array name]}}
        }
        if {[info exists state($w,structureDetails)]} {append summary "\nStructural inspection: $state($w,structureDetails)"}
        $w.fields.scalar configure -values [lsort -unique $arrays]
        $w.summary configure -state normal;$w.summary delete 1.0 end;$w.summary insert end $summary;$w.summary configure -state disabled
    }
    if {[info exists state($w,previewWidget)]} {
        if {![info exists state($w,previewFitted)]} {
            set state($w,previewFitted) 1
            meshDatasetPreset $w fit_scene
            return
        }
        set widget $state($w,previewWidget)
        set canvas .top.nb.preview.geometry
        $canvas delete picture
        $canvas create image 0 0 -anchor nw -image $state($w,image) -tags picture
        $widget configure -state normal;$widget delete 1.0 end
        $widget insert end "$state($w,id) — CORE Native3D read-only preview. Units: $state($w,units)\n[$w.summary get 1.0 end-1c]"
        $widget configure -state disabled
        place $canvas -in $widget -relwidth 1 -relheight 1
        raise $canvas;raise $canvas.tools
        datasetPreviewActionsState
    }
    set state($w,status) "$state($w,id) · [dict get $state($w,identity) format] · Units: $state($w,units). Left drag: orbit; middle drag: Pan; wheel: zoom."
    if {$state($w,pending) ne {}} {set request $state($w,pending);set state($w,pending) {};meshDatasetRequest $w $request}
}
proc ::GX::meshDatasetPreset {w preset} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {$state($w,ready)&&$state($w,image) ne {}} {meshDatasetRequest $w [list preset $preset {} [file join $state($w,temp) render.png] [image width $state($w,image)] [image height $state($w,image)]]}
}
proc ::GX::meshDatasetNavigate {w mode x y} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {$state($w,ready)} {meshDatasetRequest $w [list navigate $mode $x $y [file join $state($w,temp) render.png]]}
}
proc ::GX::meshDatasetDrag {w phase mode x y} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {$phase eq "move"&&[info exists state($w,drag)]} {lassign $state($w,drag) px py;meshDatasetNavigate $w $mode [expr {$x-$px}] [expr {$y-$py}]}
    set state($w,drag) [list $x $y]
}

proc ::GX::meshDatasetFailure {w message} {
    variable ::GX::DatasetViewer::state
    set state($w,status) $message
    if {[info exists state($w,compactCanvas)]} {native3DPreviewFailure $w $message;return}
    if {[info exists state($w,previewWidget)]} {
        set widget $state($w,previewWidget)
        if {[winfo exists $widget]&&$state($w,previewChoice) eq $::GX::variableDatasetChoice} {$widget configure -state normal;$widget delete 1.0 end;$widget insert end $message;$widget configure -state disabled}
        datasetViewerClose $w
    }
}

# Stable viewport host; worker/scenes stay owned by the existing read-only viewer.
proc ::GX::meshDatasetPreviewBuild {w} {
    set canvas .top.nb.preview.geometry
    if {![winfo exists $canvas]} {
        canvas $canvas -highlightthickness 0 -background white
        ttk::frame $canvas.tools
        foreach {key glyph title} {plus zoom_in {Zoom +} minus zoom_out {Zoom −} fit fit_all {Fit All}} {
            ttk::button $canvas.tools.$key -image [native2DViewportGlyph $glyph] -text $title -compound left
            pack $canvas.tools.$key -side left -padx 2
        }
        place $canvas.tools -relx 1 -x -40 -y 5 -anchor ne
        bind $canvas <Configure> ::GX::meshDatasetPreviewResize
        bind $canvas <Map> ::GX::meshDatasetPreviewResize
    }
    foreach key {plus minus fit} {$canvas.tools.$key configure -command [list ::GX::meshDatasetPreviewCamera $w $key]}
    bind $canvas <ButtonPress-1> [list ::GX::meshDatasetPreviewClick $w %x %y]
    bind $canvas <B1-Motion> [list ::GX::meshDatasetPreviewMotion $w %x %y]
    bind $canvas <ButtonPress-2> [list ::GX::meshDatasetDrag $w start pan %x %y]
    bind $canvas <B2-Motion> [list ::GX::meshDatasetDrag $w move pan %x %y]
    bind $canvas <Button-4> [list ::GX::meshDatasetNavigate $w zoom 1 0]
    bind $canvas <Button-5> [list ::GX::meshDatasetNavigate $w zoom -1 0]
    place $canvas -in .top.nb.preview.txt -relwidth 1 -relheight 1
    raise $canvas
    datasetPreviewToolsPlace
}
proc ::GX::meshDatasetPreviewClick {w x y} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,image)] || $state($w,image) eq {}} return
    set width [image width $state($w,image)]
    set state($w,cubeGesture) [expr {$x>=$width-120 && $x<=$width-40 && $y>=40 && $y<=120}]
    if {$state($w,cubeGesture)} {
        set state($w,cubePoint) [list $x $y]
        meshDatasetRequest $w [list navcube_pick $x $y]
    } else {meshDatasetDrag $w start orbit $x $y}
}
proc ::GX::meshDatasetPreviewMotion {w x y} {
    variable ::GX::DatasetViewer::state
    if {[info exists state($w,cubeGesture)] && !$state($w,cubeGesture)} {meshDatasetDrag $w move orbit $x $y}
}
proc ::GX::meshDatasetPreviewCamera {w action} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    switch $action {plus {meshDatasetNavigate $w zoom 1 0} minus {meshDatasetNavigate $w zoom -1 0} fit {meshDatasetPreset $w fit_scene}}
}
proc ::GX::meshDatasetPreviewResize {} {
    variable ::GX::DatasetViewer::previewJob
    variable ::GX::DatasetViewer::state
    set w $previewJob
    if {$w eq {} || ![info exists state($w,id)]} return
    set canvas .top.nb.preview.geometry
    if {![winfo exists $canvas] || ![winfo ismapped $canvas]} return
    set size [list [expr {max(320,min(1600,[winfo width $canvas]))}] [expr {max(240,min(1200,[winfo height $canvas]))}]]
    if {[info exists state($w,previewRenderSize)] && $size eq $state($w,previewRenderSize)} return
    if {[info exists state($w,drawJob)]} {after cancel $state($w,drawJob)}
    set state($w,drawJob) [after 150 [list ::GX::meshDatasetRender $w]]
}

# Same standard layer contract for live consultation and managed preparation.
proc ::GX::meshDatasetLayer {payload} {
    return [dict create kind geometry source_mode artifact absolute_path [dict get $payload path] resource_path [dict get $payload path] format [dict get $payload format] sha256 [dict get $payload sha256] visible 1 opacity 1 colormap viridis scalar_range {} scalar_array {} vector_array {} radius_array {} opacity_array {} tube_radius 0 isovalues {} volume_transfer {} volume_sample_distance .05 layer_order 0 representation surface base_color {0.65;0.78;0.93} line_width 1 point_size 4 backface_culling 0 scalar_coloring 0 local_transform {}]
}
proc ::GX::meshDatasetPreviewArtifact {id directory} {
    if {![info exists ::GX::PreviewCache::worker] || !$::GX::PreviewCache::worker} {error {Native3D standard preparation belongs in a managed Preview Job}}
    set payload [sessionInspectionDatasetPayload $id]
    if {[string tolower [dict get $payload format]] ni {stl obj step stp vtp vtu vti}} {return {}}
    set command [list [auto_execok tclsh] [file join $::GX::scriptDir core native3d renderer_worker.tcl] [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so] readonly]
    set policy [native3dGraphicsPolicy];dict set policy execution Software
    if {[auto_execok prlimit] ne {}} {set command [concat [list prlimit --as=[expr {[dict get $policy worker_address_space_budget_mib]*1024*1024}] --] $command]}
    set command [concat [list env LIBGL_ALWAYS_INDIRECT=0 LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=llvmpipe] $command]
    set channel [open [concat [list |] $command [list 2>[file join $directory native3d-worker.log]]] r+]
    fconfigure $channel -buffering line -encoding utf-8 -translation lf
    try {
        if {[gets $channel ready]<0 || $ready ne "GX3DE_VIEWER_WORKER_READY"} {error {Native3D preparation worker did not initialize}}
        set png [file join $directory native3d-standard.png]
        set scene [dict create layers [dict create data [meshDatasetLayer $payload]] view [dict replace [viewerSceneDefaults] axes_world 1] graphics_policy $policy cache_root [file join $directory native3d-derived] session_namespace $::GX::currentSession]
        puts $channel [list render $scene $png 800 500 preview];flush $channel
        if {[gets $channel response]<0 || [lindex $response 0] ne "ok"} {error "Native3D preparation failed: $response"}
        if {![file isfile $png] || [file size $png]>2097152} {error {Native3D standard frame is unavailable or exceeds its 2 MiB bound}}
        puts $channel close;flush $channel;gets $channel closed
        file delete -force [file join $directory native3d-derived]
        return [dict create path $png media_type image/png label {Native3D standard view — open Dataset for live camera and resize}]
    } finally {catch {close $channel}}
}
