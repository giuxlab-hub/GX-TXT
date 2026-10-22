# SPDX-License-Identifier: GPL-3.0-or-later
# Component lifetime over the existing isolated CORE VTK renderer, never Engine3D state.
namespace eval ::GX::Native3DCanvas {variable instances {};variable retiring {};variable serial 0;variable events {ready view_changed selected error released source_changed}}
proc ::GX::native3DGuiHostApiInfoV2 {} {
    return [dict create api_id NATIVE_3D_GUI_HOST_API_v2 api_version 2 operations {create configure bind unbind update navigate camera command pick subscribe unsubscribe inspect release} commands {native3DViewportCreate native3DViewportConfigure native3DViewportBind native3DViewportUnbind native3DViewportUpdate native3DViewportNavigate native3DViewportCamera native3DViewportCommand native3DViewportPick native3DViewportSubscribe native3DViewportUnsubscribe native3DViewportInspect native3DViewportRelease native3DScenePrepare} source_kinds {demo scientific cell_field} instance_limit 4 retiring_workers [dict size $::GX::Native3DCanvas::retiring] worker_ownership per_instance renderer NATIVE_3D_ENGINE_API_v1 events $::GX::Native3DCanvas::events demo display_only_RAM scientific_source VIEWER_PROVIDER_API_v1 cell_field_source PLOT_DATASET_API_v4 publication 0]
}
proc ::GX::native3DViewportCreate {widget {options {}}} {
    variable ::GX::Native3DCanvas::instances
    if {[dict size $instances]+[dict size $::GX::Native3DCanvas::retiring]>=4} {error {Native3D component limit reached (four independent viewports)}}
    if {[winfo exists $widget]} {error {Native3D widget already exists}}
    set handle n3d:[pid]:[incr ::GX::Native3DCanvas::serial]:[clock clicks]
    ttk::frame $widget
    ttk::frame $widget.tools
    foreach {id label action} {fit Fit fit_scene reset Reset isometric front Front front top Top top} {
        ttk::button $widget.tools.$id -text $label -command [list ::GX::native3DViewportCommand $handle preset $action]
        $widget.tools.$id state disabled
        pack $widget.tools.$id -side left -padx 2 -pady 3
    }
    ttk::label $widget.tools.hint -text {Drag: orbit · Shift-drag: pan · Wheel: zoom}
    pack $widget.tools.hint -side left -padx 8 -fill x -expand 1
    bind $widget.tools <Configure> [list ::GX::_native3DViewportHint $handle %w]
    # Keep source context independent of transient activity. Alternating a long
    # wrapped source caption with "Rendering…" changes the canvas height and
    # can start an endless Configure -> resize -> Ready -> Configure cycle.
    ttk::label $widget.sourceCaption -text {No source — bind a scientific scene or a display-only RAM demo} -anchor w -wraplength 480
    ttk::label $widget.status -text {} -anchor w -wraplength 480
    canvas $widget.canvas -background #1f242e -highlightthickness 1 -highlightbackground #777777 -takefocus 1 -width 560 -height 360
    pack $widget.tools -side top -fill x
    pack $widget.status -side bottom -fill x -padx 4 -pady 3
    pack $widget.sourceCaption -side bottom -fill x -padx 4
    pack $widget.canvas -fill both -expand 1
    set dir [file join [configurationCacheDirectory] native3d_components [string map {: _} $handle]]
    file mkdir $dir
    dict set instances $handle [dict create widget $widget status empty generation 0 worker {} ready 0 busy {} queue {} timer {} resize {} guard {} start {} scene {} source {} context {} subscribers {} photo {} directory $dir camera {} result {} error {} options {}]
    bind $widget <Destroy> [list ::GX::_native3DViewportDestroyed $handle %W]
    bind $widget.canvas <Configure> [list ::GX::_native3DViewportResize $handle]
    bind $widget.canvas <ButtonPress-1> [list ::GX::_native3DViewportPress $handle %x %y]
    bind $widget.canvas <ButtonRelease-1> [list ::GX::_native3DViewportDrag $handle orbit %x %y]
    bind $widget.canvas <Shift-ButtonRelease-1> [list ::GX::_native3DViewportDrag $handle pan %x %y]
    bind $widget.canvas <Button-4> [list ::GX::native3DViewportNavigate $handle zoom -1 0]
    bind $widget.canvas <Button-5> [list ::GX::native3DViewportNavigate $handle zoom 1 0]
    bind $widget.canvas <Key-f> [list ::GX::native3DViewportCommand $handle preset fit_scene]
    bind $widget.canvas <Key-r> [list ::GX::native3DViewportCommand $handle preset isometric]
    bind $widget.canvas <Left> [list ::GX::native3DViewportNavigate $handle orbit -20 0]
    bind $widget.canvas <Right> [list ::GX::native3DViewportNavigate $handle orbit 20 0]
    try {native3DViewportConfigure $handle $options} on error {message opts} {native3DViewportRelease $handle;return -options $opts $message}
    return $handle
}
proc ::GX::_native3DViewportHint {h width} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    set w [dict get $::GX::Native3DCanvas::instances $h widget]
    set buttons 0;foreach id {fit reset front top} {incr buttons [expr {[winfo reqwidth $w.tools.$id]+4}]}
    $w.tools.hint configure -wraplength [expr {max(80,$width-$buttons-20)}]
}
proc ::GX::_native3DViewportRecord {h} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} {error {Released or unknown Native3D component handle}}
    return [dict get $::GX::Native3DCanvas::instances $h]
}
proc ::GX::native3DViewportConfigure {h options} {
    set r [_native3DViewportRecord $h];set w [dict get $r widget]
    dict for {key value} $options {
        switch -- $key {
            width - height {if {![string is integer -strict $value]||$value<160||$value>4096} {error {Native3D dimensions must be 160..4096}};$w.canvas configure -$key $value}
            projection {if {$value ni {perspective orthographic}} {error {Projection must be perspective or orthographic}}}
            axes_world - navigation_cube_visible {if {![string is boolean -strict $value]} {error "$key must be boolean"};set value [expr {!!$value}]}
            camera_position - camera_target - camera_up {viewerTriple $value $key}
            default {error "Unknown Native3D component property: $key"}
        }
        dict set r options $key $value
    }
    dict set ::GX::Native3DCanvas::instances $h $r
    if {[dict get $r scene] ne {}} {native3DViewportUpdate $h}
    return [dict get $r options]
}
proc ::GX::_native3DViewportDemo {} {
    set view [viewerSceneDefaults];dict set view axes_world 1
    set layer [dict create source_mode memory_geometry provenance display_only_RAM dataset_id {} layer_order 0 visible 1 opacity 1 representation surface_edges base_color {0.16;0.58;0.91} line_width 1.5 point_size 4 backface_culling 0 scalar_coloring 0 scalar_array {} local_transform {} texture {} vertices {{-1 -1 -1} {1 -1 -1} {1 1 -1} {-1 1 -1} {-1 -1 1} {1 -1 1} {1 1 1} {-1 1 1}} triangles {{0 2 1} {0 3 2} {4 5 6} {4 6 7} {0 1 5} {0 5 4} {1 2 6} {1 6 5} {2 3 7} {2 7 6} {3 0 4} {3 4 7}}]
    return [dict create layers [dict create ram_cube $layer] view $view provenance display_only_RAM publication 0]
}
proc ::GX::_native3DViewportScientificIdentity {scene} {
    set result [dict create layers [dict get $scene layers]]
    foreach key {field_definitions timeline_definitions} {dict set result $key [dict get $scene view $key]}
    set datasets {}
    dict for {id layer} [dict get $scene layers] {
        foreach key {dataset_id source_dataset_id} {
            set dataset [datasetPublicationV2DictDefault $layer $key {}]
            if {$dataset ne {}} {dict set datasets $dataset [datasetViewerScientificIdentity $dataset]}
        }
    }
    dict set result datasets $datasets
    return $result
}
proc ::GX::native3DViewportBind {h source} {
    set r [_native3DViewportRecord $h]
    set mode [dict get $source kind]
    if {$mode eq {demo}} {
        if {[lsort [dict keys $source]] ne {kind}} {error {Demo binding accepts only kind=demo; no scientific identities}}
        set scene [_native3DViewportDemo];set context {}
    } elseif {$mode eq {scientific}} {
        if {[lsort [dict keys $source]] ne {kind module provider}} {error {Scientific binding requires public module/provider identity}}
        set context [interactiveDocumentSessionToken]
        set scientificSnapshot [viewerSceneResolve [dict get $source module] [dict get $source provider]]
        set scene [native3DScenePrepare $scientificSnapshot]
    } elseif {$mode eq {cell_field}} {
        if {[lsort [dict keys $source]] ne {kind spec}} {error {Cell-field binding requires its complete public Plot v4 spec}}
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
        set context [interactiveDocumentSessionToken]
        set scene [::GX::PlotDatasetAPIv4::cellFieldNativeScene [dict get $source spec]]
        set scientificSnapshot [dict get $scene source_identity]
    } else {error {Native3D source kind must be demo, scientific or cell_field}}
    _native3DViewportStop $h
    set r [_native3DViewportRecord $h]
    dict incr r generation;dict set r scene $scene;dict set r source $source;dict set r context $context;dict set r camera {};dict set r result {};dict set r error {}
    dict set r scientific_snapshot [expr {$mode eq {scientific} ? [_native3DViewportScientificIdentity $scientificSnapshot] : ($mode eq {cell_field} ? $scientificSnapshot : {})}]
    dict set ::GX::Native3DCanvas::instances $h $r
    [dict get $r widget].sourceCaption configure -text [_native3DViewportSourceLabel $r]
    if {$mode eq {cell_field}} {_native3DViewportQueue $h capabilities [list capabilities]}
    native3DViewportUpdate $h
    _native3DViewportEmit $h source_changed [dict create kind $mode generation [dict get $r generation]]
    return [native3DViewportInspect $h]
}
proc ::GX::native3DViewportUnbind {h} {
    _native3DViewportStop $h
    set r [_native3DViewportRecord $h];dict incr r generation
    foreach key {scene source context camera result error} {dict set r $key {}}
    dict set r status empty;set w [dict get $r widget];$w.canvas delete all
    $w.sourceCaption configure -text {No source — bind a scientific scene or a display-only RAM demo}
    $w.status configure -text {}
    foreach id {fit reset front top} {$w.tools.$id state disabled}
    dict set ::GX::Native3DCanvas::instances $h $r
}
proc ::GX::_native3DViewportValid {h} {
    set r [_native3DViewportRecord $h]
    if {[dict get $r context] eq {}} {return 1}
    if {[catch {set token [interactiveDocumentSessionToken]}]||$token ne [dict get $r context]} {
        _native3DViewportFail $h {Scientific source belongs to a previous Session; explicitly rebind the viewport.} stale_source
        return 0
    }
    set source [dict get $r source]
    if {[dict get $source kind] eq {cell_field}} {
        set failed [catch {set current [::GX::PlotDatasetAPIv4::cellFieldSourceIdentity [dict get $source spec]]}]
    } else {
        set failed [catch {set current [_native3DViewportScientificIdentity [viewerSceneResolve [dict get $source module] [dict get $source provider]]]}]
    }
    if {$failed||$current ne [dict get $r scientific_snapshot]} {
        _native3DViewportFail $h {Scientific source or scene changed; explicitly rebind the viewport.} stale_source
        return 0
    }
    return 1
}
proc ::GX::native3DViewportUpdate {h} {
    set r [_native3DViewportRecord $h]
    if {[dict get $r scene] eq {}||![_native3DViewportValid $h]} {return}
    set scene [dict get $r scene];set options [dict get $r options]
    foreach key {projection camera_position camera_target camera_up axes_world navigation_cube_visible} {if {[dict exists $options $key]} {dict set scene view $key [dict get $options $key]}}
    dict set scene graphics_policy [native3dGraphicsPolicy]
    set w [dict get $r widget];set width [expr {max(160,min(4096,[winfo width $w.canvas]))}];set height [expr {max(160,min(4096,[winfo height $w.canvas]))}]
    set png [file join [dict get $r directory] frame.png]
    _native3DViewportQueue $h render [list render $scene $png $width $height full]
}
proc ::GX::native3DViewportNavigate {h mode dx dy} {
    if {$mode ni {orbit pan zoom roll}} {error {Unsupported Native3D camera navigation}}
    foreach value [list $dx $dy] {if {![string is double -strict $value]||abs($value)>4096} {error {Native3D navigation delta exceeds bounds}}}
    set r [_native3DViewportRecord $h]
    if {[dict get $r scene] eq {}||![_native3DViewportValid $h]} {return}
    _native3DViewportQueue $h navigate [list navigate $mode $dx $dy [file join [dict get $r directory] frame.png]]
}
proc ::GX::native3DViewportCamera {h {camera {}}} {
    set r [_native3DViewportRecord $h]
    if {$camera eq {}} {return [dict get $r camera]}
    if {![_native3DViewportValid $h]||[dict get $r scene] eq {}} {error {Bind a current source before restoring a camera}}
    if {[lsort [dict keys $camera]] ne {camera_position camera_target camera_up far_clip near_clip projection vertical_fov_degrees}} {error {Camera requires the complete public camera receipt}}
    foreach key {camera_position camera_target camera_up} {viewerTriple [join [dict get $camera $key] {;}] $key;dict set camera $key [join [dict get $camera $key] {;}]}
    if {[dict get $camera projection] ni {perspective orthographic}} {error {Invalid camera projection}}
    foreach key {near_clip far_clip vertical_fov_degrees} {set n [dict get $camera $key];if {![string is double -strict $n]||[catch {expr {$n>0&&$n<1e15}} ok]||!$ok} {error {Camera numeric fields must be finite positive values}}}
    _native3DViewportQueue $h camera [list camera $camera [file join [dict get $r directory] frame.png]]
}
proc ::GX::native3DViewportCommand {h operation value} {
    set r [_native3DViewportRecord $h]
    if {[dict get $r scene] eq {}||![_native3DViewportValid $h]} return
    if {$operation ne {preset}||$value ni {fit_scene isometric front top}} {error {Unsupported Native3D component command}}
    set w [dict get $r widget]
    _native3DViewportQueue $h camera [list preset $value {} [file join [dict get $r directory] frame.png] [winfo width $w.canvas] [winfo height $w.canvas]]
}
proc ::GX::_native3DViewportCommand {h operation value} {return [native3DViewportCommand $h $operation $value]}
proc ::GX::native3DViewportPick {h x y} {
    set r [_native3DViewportRecord $h];set w [dict get $r widget]
    foreach value [list $x $y] {if {![string is integer -strict $value]||$value<0||$value>4096} {error {Pick coordinates must be bounded viewport pixels}}}
    if {[dict get $r scene] eq {}||![_native3DViewportValid $h]} {return}
    if {$x>=[winfo width $w.canvas]||$y>=[winfo height $w.canvas]} {error {Pick lies outside the native viewport}}
    _native3DViewportQueue $h pick [list pick $x $y [file join [dict get $r directory] frame.png]]
}
proc ::GX::_native3DViewportQueue {h kind request} {
    set r [_native3DViewportRecord $h]
    if {[llength [dict get $r queue]]>=8} {error {Native3D input queue is full; wait for rendering}}
    dict lappend r queue [list $kind $request]
    dict set ::GX::Native3DCanvas::instances $h $r
    if {[dict get $r worker] eq {}} {_native3DViewportStart $h} else {_native3DViewportNext $h}
}
proc ::GX::_native3DViewportStart {h {generation {}}} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    set r [_native3DViewportRecord $h]
    if {$generation ne {}&&$generation!=[dict get $r generation]} return
    if {[dict get $r start] ne {}} {after cancel [dict get $r start];dict set r start {};dict set ::GX::Native3DCanvas::instances $h $r}
    if {[dict get $r worker] ne {}||[dict get $r scene] eq {}} return
    set workers [dict size $::GX::Native3DCanvas::retiring];set sameDirectory 0
    dict for {other record} $::GX::Native3DCanvas::instances {if {[dict get $record worker] ne {}} {incr workers}}
    dict for {token record} $::GX::Native3DCanvas::retiring {if {[dict get $record directory] eq [dict get $r directory]} {set sameDirectory 1}}
    if {$workers>=4||$sameDirectory} {
        dict set r start [after 25 [list ::GX::_native3DViewportStart $h [dict get $r generation]]]
        dict set r status loading;dict set ::GX::Native3DCanvas::instances $h $r
        [dict get $r widget].status configure -text {Waiting for owned native renderer cleanup…}
        return
    }
    set tool [auto_execok tclsh];if {$tool eq {}} {error {Native3D requires Tcl worker runtime}}
    set command [list env LIBGL_ALWAYS_INDIRECT=0 $tool [file join $::GX::scriptDir core native3d renderer_worker.tcl] [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so] readonly]
    set policy [native3dGraphicsPolicy]
    if {[dict get $policy execution] eq {Software}} {set command [concat [list env LIBGL_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_INDIRECT=0 MESA_LOADER_DRIVER_OVERRIDE=llvmpipe GALLIUM_DRIVER=llvmpipe] $command]}
    if {[auto_execok prlimit] ne {}} {set command [concat [list [auto_execok prlimit] --as=[expr {[dict get $policy worker_address_space_budget_mib]*1048576}] --] $command]}
    set log [file join [dict get $r directory] worker.log]
    if {[catch {set ch [open [concat | $command [list 2>$log]] r+]} message]} {_native3DViewportFail $h $message;return}
    fconfigure $ch -blocking 0 -buffering line -encoding utf-8 -translation lf
    dict set r worker $ch;dict set r ready 0;dict set r status loading
    dict set r timer [after 45000 [list ::GX::_native3DViewportTimeout $h [dict get $r generation]]]
    dict set r guard [after 1000 [list ::GX::_native3DViewportGuard $h]]
    dict set ::GX::Native3DCanvas::instances $h $r
    fileevent $ch readable [list ::GX::_native3DViewportReadable $h [dict get $r generation]]
    [dict get $r widget].status configure -text {Loading native renderer…}
}
proc ::GX::_native3DViewportNext {h} {
    set r [_native3DViewportRecord $h]
    if {![dict get $r ready]||[dict get $r busy] ne {}||![llength [dict get $r queue]]} return
    lassign [lindex [dict get $r queue] 0] kind request
    dict set r queue [lrange [dict get $r queue] 1 end];dict set r busy $kind;dict set r status rendering
    after cancel [dict get $r timer]
    dict set r timer [after 45000 [list ::GX::_native3DViewportTimeout $h [dict get $r generation]]]
    dict set ::GX::Native3DCanvas::instances $h $r
    [dict get $r widget].status configure -text {Rendering…}
    if {[catch {puts [dict get $r worker] $request;flush [dict get $r worker]} message]} {_native3DViewportFail $h $message}
}
proc ::GX::_native3DViewportReadable {h generation} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    set r [_native3DViewportRecord $h]
    if {$generation!=[dict get $r generation]||[dict get $r worker] eq {}} return
    set ch [dict get $r worker]
    if {[catch {set count [gets $ch line]} message]} {_native3DViewportFail $h $message;return}
    if {$count<0} {if {[eof $ch]} {_native3DViewportFail $h {Native3D renderer exited; rebind to recover.}};return}
    after cancel [dict get $r timer];dict set r timer {}
    if {![dict get $r ready]} {
        if {$line ne {GX3DE_VIEWER_WORKER_READY}} {_native3DViewportFail $h {Invalid Native3D worker greeting};return}
        dict set r ready 1;dict set ::GX::Native3DCanvas::instances $h $r
        _native3DViewportNext $h;return
    }
    if {[string length $line]>4194304||[catch {llength $line} n]||$n!=2||[lindex $line 0] ne {ok}} {_native3DViewportFail $h "Native renderer: [string range [lindex $line 1] 0 1800]";return}
    if {![_native3DViewportValid $h]} return
    set result [lindex $line 1];set kind [dict get $r busy];set w [dict get $r widget]
    if {$kind eq {capabilities}} {
        if {{exact_planar_cell_field} ni $result} {_native3DViewportFail $h {The installed Native3D binary lacks exact planar cell-field support; install a compatible precompiled CORE.};return}
        dict set r busy {};dict set ::GX::Native3DCanvas::instances $h $r
        _native3DViewportNext $h;return
    }
    if {$kind eq {pick}} {
        if {[dict get $r source kind] eq {cell_field} && [dict get $result hit]} {
            set layer [dict get $r scene layers canonical_cell_field]
            foreach {native rows idkey datasetkey} {cell_index mesh_cells source_cell_id dataset_id point_index mesh_nodes source_node_id source_dataset_id} {
                if {![dict exists $result $native] || [dict get $result $native]<0} continue
                set index [dict get $result $native];set records [dict get $layer $rows]
                if {$index>=[llength $records]} {_native3DViewportFail $h {Native pick exceeds the retained canonical mesh; rebind explicitly.};return}
                dict set result $idkey [lindex [lindex $records $index] 0]
                dict set result ${idkey}_dataset_id [dict get $layer $datasetkey]
                dict set result ${idkey}_row_ordinal $index
            }
        }
        if {[catch {set r [_native3DViewportPresentFrame $r]} message]} {_native3DViewportFail $h $message;return}
        dict set r selection $result;dict set r busy {};dict set r status ready
        dict set ::GX::Native3DCanvas::instances $h $r
        $w.status configure -text [expr {[dict get $result hit]?{Geometry selected}:{No geometry at pointer}}]
        _native3DViewportEmit $h selected [dict create native_pick $result generation $generation source [dict get $r source]]
        if {[dict exists $::GX::Native3DCanvas::instances $h]} {_native3DViewportNext $h}
        return
    }
    if {[catch {set r [_native3DViewportPresentFrame $r]} message]} {_native3DViewportFail $h $message;return}
    foreach key {camera_position camera_target camera_up projection vertical_fov_degrees near_clip far_clip} {if {[dict exists $result $key]} {dict set r camera $key [dict get $result $key]}}
    if {$kind eq {render}} {dict set r render_receipt $result}
    dict set r result $result;dict set r busy {};dict set r status ready
    dict set ::GX::Native3DCanvas::instances $h $r
    $w.status configure -text {Ready}
    foreach id {fit reset front top} {$w.tools.$id state !disabled}
    _native3DViewportEmit $h [expr {$kind eq {render} ? {ready} : {view_changed}}] [dict create camera [dict get $r camera] generation $generation]
    if {[dict exists $::GX::Native3DCanvas::instances $h]} {_native3DViewportNext $h}
}
proc ::GX::_native3DViewportPresentFrame {r} {
    set png [file join [dict get $r directory] frame.png]
    if {![::GX::Engine3D::pngComplete $png]} {error {Renderer returned an incomplete frame}}
    if {[dict get $r photo] eq {}} {dict set r photo [image create photo]}
    [dict get $r photo] configure -file $png
    set w [dict get $r widget]
    $w.canvas delete native_frame
    $w.canvas create image 0 0 -anchor nw -image [dict get $r photo] -tags native_frame
    return $r
}
proc ::GX::_native3DViewportSourceLabel {record} {
    switch -- [dict get $record source kind] {
        demo {return {RAM demo · display only · no Dataset}}
        cell_field {return [dict get $record scene caption]}
        default {return {Scientific scene · public Viewer Provider binding}}
    }
}
proc ::GX::_native3DViewportStop {h} {
    set r [_native3DViewportRecord $h]
    foreach key {timer resize guard start} {if {[dict get $r $key] ne {}} {after cancel [dict get $r $key];dict set r $key {}}}
    set ch [dict get $r worker]
    if {$ch ne {}} {
        fileevent $ch readable {}
        # The channel owns exactly this component's isolated worker processes.
        set token retiring:[incr ::GX::Native3DCanvas::serial]
        set processes [pid $ch]
        dict set ::GX::Native3DCanvas::retiring $token [dict create channel $ch pids $processes directory [dict get $r directory] cleanup 0 timer [after 1000 [list ::GX::_native3DViewportRetireKill $token]]]
        foreach process $processes {catch {exec kill -TERM -- $process}}
        fileevent $ch readable [list ::GX::_native3DViewportRetireReadable $token]
    }
    dict set r worker {};dict set r ready 0;dict set r busy {};dict set r queue {}
    dict set ::GX::Native3DCanvas::instances $h $r
}
proc ::GX::_native3DViewportRetireKill {token} {
    if {![dict exists $::GX::Native3DCanvas::retiring $token]} return
    set record [dict get $::GX::Native3DCanvas::retiring $token]
    foreach process [dict get $record pids] {catch {exec kill -KILL -- $process}}
}
proc ::GX::_native3DViewportRetireReadable {token} {
    if {![dict exists $::GX::Native3DCanvas::retiring $token]} return
    set record [dict get $::GX::Native3DCanvas::retiring $token];set ch [dict get $record channel]
    catch {read $ch 65536}
    if {![eof $ch]} return
    fileevent $ch readable {};after cancel [dict get $record timer]
    # Same existing CORE process-channel pattern: EOF makes the blocking close
    # a wait/reap of an exited child, never a wait on native computation.
    fconfigure $ch -blocking 1;catch {close $ch}
    dict unset ::GX::Native3DCanvas::retiring $token
    if {[dict get $record cleanup]} {
        set pending 0
        dict for {other item} $::GX::Native3DCanvas::retiring {if {[dict get $item directory] eq [dict get $record directory]} {set pending 1}}
        if {!$pending} {catch {file delete -force -- [dict get $record directory]}}
    }
}
proc ::GX::_native3DViewportFail {h message {status error}} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    _native3DViewportStop $h
    dict set ::GX::Native3DCanvas::instances $h status $status
    dict set ::GX::Native3DCanvas::instances $h error $message
    set w [dict get $::GX::Native3DCanvas::instances $h widget]
    if {[winfo exists $w]} {$w.status configure -text $message;foreach id {fit reset front top} {$w.tools.$id state disabled}}
    _native3DViewportEmit $h error [dict create message $message status $status]
}
proc ::GX::_native3DViewportTimeout {h generation} {if {[dict exists $::GX::Native3DCanvas::instances $h]&&[dict get $::GX::Native3DCanvas::instances $h generation]==$generation} {_native3DViewportFail $h {Native3D request timed out after 45 seconds; rebind to recover.}}}
proc ::GX::_native3DViewportGuard {h} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]||![_native3DViewportValid $h]} return
    set r [_native3DViewportRecord $h]
    if {[dict get $r worker] ne {}} {
        foreach process [pid [dict get $r worker]] {
            set path /proc/$process/status
            if {[file readable $path]} {set f [open $path r];set text [read $f 65536];close $f
                if {[regexp {VmRSS:\s+([0-9]+)} $text -> kib]&&$kib>[configurationGet viewers.native3d.worker_rss_budget_mib]*1024} {_native3DViewportFail $h {Native3D worker exceeded its configured RSS budget};return}}
        }
        set log [file join [dict get $r directory] worker.log]
        if {[file exists $log]&&[file size $log]>4194304} {_native3DViewportFail $h {Native3D worker exceeded the diagnostic output budget};return}
        dict set ::GX::Native3DCanvas::instances $h guard [after 1000 [list ::GX::_native3DViewportGuard $h]]
    }
}
proc ::GX::_native3DViewportResize {h} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    set r [_native3DViewportRecord $h]
    if {[dict get $r resize] ne {}} {after cancel [dict get $r resize]}
    dict set ::GX::Native3DCanvas::instances $h resize [after 180 [list ::GX::_native3DViewportSized $h]]
}
proc ::GX::_native3DViewportSized {h} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    dict set ::GX::Native3DCanvas::instances $h resize {}
    set r [_native3DViewportRecord $h];set w [dict get $r widget]
    if {[dict get $r scene] eq {}||![winfo ismapped $w]||[dict get $r status] in {error stale_source}} return
    if {[dict get $r busy] ne {}||[llength [dict get $r queue]]} {_native3DViewportResize $h;return}
    if {[dict get $r ready]} {_native3DViewportQueue $h resize [list viewport [expr {max(160,min(4096,[winfo width $w.canvas]))}] [expr {max(160,min(4096,[winfo height $w.canvas]))}] [file join [dict get $r directory] frame.png]]}
}
proc ::GX::_native3DViewportPress {h x y} {set r [_native3DViewportRecord $h];focus [dict get $r widget].canvas;dict set ::GX::Native3DCanvas::instances $h press [list $x $y]}
proc ::GX::_native3DViewportDrag {h mode x y} {set r [_native3DViewportRecord $h];if {[dict exists $r press]} {lassign [dict get $r press] px py;dict unset ::GX::Native3DCanvas::instances $h press;if {abs($x-$px)+abs($y-$py)<4} {native3DViewportPick $h $x $y} else {native3DViewportNavigate $h $mode [expr {$x-$px}] [expr {$y-$py}]}}}
proc ::GX::native3DViewportSubscribe {h event callback} {
    _native3DViewportRecord $h
    if {$event ni $::GX::Native3DCanvas::events||![llength $callback]} {error {Invalid Native3D event or callback prefix}}
    set token sub:[incr ::GX::Native3DCanvas::serial]
    dict set ::GX::Native3DCanvas::instances $h subscribers $token [list $event $callback]
    return $token
}
proc ::GX::native3DViewportUnsubscribe {h token} {_native3DViewportRecord $h;dict unset ::GX::Native3DCanvas::instances $h subscribers $token}
proc ::GX::_native3DViewportEmit {h event detail} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    dict for {token subscriber} [dict get $::GX::Native3DCanvas::instances $h subscribers] {
        lassign $subscriber wanted callback
        if {$wanted eq $event} {catch {{*}$callback $h $event $detail}}
    }
}
proc ::GX::native3DViewportInspect {h} {
    set r [_native3DViewportRecord $h];set worker [dict get $r worker]
    return [dict create api_id NATIVE_3D_GUI_HOST_API_v2 handle $h widget [dict get $r widget] status [dict get $r status] generation [dict get $r generation] source [dict get $r source] camera [dict get $r camera] selection [datasetPublicationV2DictDefault $r selection {}] result [dict get $r result] error [dict get $r error] pending [llength [dict get $r queue]] busy [dict get $r busy] worker_pids [expr {$worker eq {} ? {} : [pid $worker]}] publication 0]
}
proc ::GX::_native3DViewportDestroyed {h widget} {if {[dict exists $::GX::Native3DCanvas::instances $h]&&$widget eq [dict get $::GX::Native3DCanvas::instances $h widget]} {native3DViewportRelease $h}}
proc ::GX::native3DViewportRelease {h} {
    if {![dict exists $::GX::Native3DCanvas::instances $h]} return
    if {[dict exists $::GX::Native3DCanvas::instances $h closing]} return
    dict set ::GX::Native3DCanvas::instances $h closing 1
    _native3DViewportStop $h
    set r [_native3DViewportRecord $h]
    _native3DViewportEmit $h released [dict create generation [dict get $r generation]]
    dict unset ::GX::Native3DCanvas::instances $h
    if {[dict get $r photo] ne {}} {catch {image delete [dict get $r photo]}}
    set pending 0
    dict for {token record} $::GX::Native3DCanvas::retiring {
        if {[dict get $record directory] eq [dict get $r directory]} {dict set ::GX::Native3DCanvas::retiring $token cleanup 1;set pending 1}
    }
    if {!$pending} {catch {file delete -force -- [dict get $r directory]}}
    catch {destroy [dict get $r widget]}
}
