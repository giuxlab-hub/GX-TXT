# SPDX-License-Identifier: GPL-3.0-or-later
# Optional Tk composition; discovery loads neither Tk nor VTK. Scientific model
# writes remain with owners. Native2D presentation and Native3D worker are reused.
namespace eval ::GX::Multiview {variable hosts {};variable serial 0}
proc ::GX::scientificMultiviewHostCapabilities {} {
    return {api_id SCIENTIFIC_MULTIVIEW_HOST_API_v1 api_version 1 headless_operations capabilities desktop_operations {create attach bind_identity selection model_changed configure info destroy} backends {native2d native3d} selection_mapping explicit_logical_to_object_layer_or_element native3d_picking logical_point_or_cell native3d_focus cell_center_or_point identity_scope document_generation implicit_reconstruction 0 implicit_dataset_publication 0}
}
proc ::GX::_multiviewRequire {host {allowRevision 0}} {
    variable ::GX::Multiview::hosts
    if {![dict exists $hosts $host]} {error {Unknown or destroyed scientific host}}
    set h [dict get $hosts $host]
    if {[dict get $h session_token] ne [interactiveDocumentSessionToken]} {error {Scientific host Session expired}}
    set owner [interactiveDocumentRead [dict get $h document]]
    if {[dict get $owner generation] ne [dict get $h generation]} {error {Scientific host document owner replaced}}
    if {!$allowRevision && [dict get $owner revision]!=[dict get $h revision]} {error {Scientific host model changed; supply an explicit model refresh}}
    return $h
}
proc ::GX::scientificMultiviewHostCreate {parent document {options {}}} {
    variable ::GX::Multiview::hosts;variable ::GX::Multiview::serial
    set owner [interactiveDocumentRead $document]
    foreach k [dict keys $options] {if {$k ni {layout selection_command refresh_command}} {error "Unknown host option $k"}}
    set layout [datasetPublicationV2DictDefault $options layout horizontal]
    if {$layout ni {horizontal vertical}} {error {Layout must be horizontal or vertical}}
    package require Tk
    if {![winfo exists $parent]} {error {Missing host parent container}}
    if {[dict size $hosts]>=16} {error {Scientific host budget reached}}
    set host "scientific-multiview#[pid]-[incr serial]"
    set root $parent.gxmultiview$serial
    ttk::frame $root;pack $root -fill both -expand 1
    ttk::panedwindow $root.views -orient $layout;pack $root.views -fill both -expand 1
    ttk::label $root.status -text {Attach scientific views} -wraplength 900;pack $root.status -fill x
    set f [file tempfile temp];close $f;file delete $temp;file mkdir $temp
    dict set hosts $host [dict create root $root pane $root.views document $document generation [dict get $owner generation] revision [dict get $owner revision] session_token [interactiveDocumentSessionToken] epoch 0 views {} mapping {} selection {} options $options temp $temp pending {} layout $layout]
    bind $root <Destroy> [list ::GX::_multiviewDestroyed $host $root %W]
    dict set hosts $host subscription [interactiveDocumentLifecycleSubscribe [list ::GX::_multiviewInvalidated $host] $root $document]
    return $host
}
proc ::GX::_multiviewDestroyed {host root widget} {if {$root eq $widget} {scientificMultiviewHostDestroy $host}}
proc ::GX::_multiviewInvalidated {host receipt} {
    if {![dict exists $::GX::Multiview::hosts $host]} return
    if {[dict get $receipt document_id] eq [dict get $::GX::Multiview::hosts $host document]} {scientificMultiviewHostDestroy $host}
}
proc ::GX::scientificMultiviewHostInfo {host} {
    set h [_multiviewRequire $host 1]
    set views {}
    dict for {slot v} [dict get $h views] {dict set views $slot [dict remove $v worker layers paths image drag timer]}
    return [dict replace [dict remove $h temp subscription pending] views $views]
}
proc ::GX::scientificMultiviewHostAttach {host slot backend options} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host]
    if {![regexp {^[a-z][a-z0-9_]{0,31}$} $slot] || $backend ni {native2d native3d}} {error {Invalid view slot/backend}}
    if {[dict exists $h views $slot] || [dict size [dict get $h views]]>=4} {error {Occupied slot or host view budget}}
    foreach k [dict keys $options] {if {$k ni {scene_token owned layers title axis_presentation}} {error "Unknown adapter option $k"}}
    if {$backend eq "native2d"} {
        set scene [_native2DGeometryRequire [dict get $options scene_token]]
        if {[dict get $scene document_id] ne [dict get $h document]} {error {Native2D view requires the bound document}}
        dict for {otherHost other} $hosts {dict for {otherSlot view} [dict get $other views] {
            if {[dict get $view backend] eq "native2d" && [dict get $view scene_token] eq [dict get $options scene_token]} {error {Each viewport requires an independent Native2D scene instance}}
        }}
    } else {
        if {![file isfile [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so]]} {error {Native3D provider unavailable}}
        _multiviewValidateLayers $host [dict get $options layers]
        if {[dict exists $options axis_presentation]} {error {Axis presentation applies to Native2D viewports}}
    }
    if {$backend eq {native2d} && [dict exists $options axis_presentation]} {
        dict set options axis_presentation [native2DAxisPresentationValidate [dict get $scene native] [dict get $options axis_presentation]]
    }
    set frame [dict get $h root].$slot
    ttk::frame $frame
    ttk::frame $frame.bar;pack $frame.bar -fill x
    ttk::label $frame.bar.title -text [datasetPublicationV2DictDefault $options title $backend];pack $frame.bar.title -side left
    foreach {action title} {fit Fit plus + minus − front Front iso Iso} {
        if {$backend eq "native2d" && $action in {front iso}} continue
        ttk::button $frame.bar.$action -text $title -width 5 -command [list ::GX::_multiviewControl $host $slot $action]
        pack $frame.bar.$action -side left
    }
    canvas $frame.canvas -width 480 -height 360 -background white -highlightthickness 0 -takefocus 1
    pack $frame.canvas -fill both -expand 1
    [dict get $h pane] add $frame -weight 1
    dict set hosts $host views $slot [dict create backend $backend frame $frame canvas $frame.canvas options $options ready 0 busy 0 pending {} image {} paths {} status attached model_ready 1 rendered_epoch -1]
    bind $frame.canvas <Configure> [list ::GX::_multiviewSchedule $host $slot]
    bind $frame.canvas <ButtonPress-1> [list ::GX::_multiviewClick $host $slot %x %y]
    bind $frame.canvas <ButtonPress-2> [list ::GX::_multiviewDrag $host $slot start %x %y]
    bind $frame.canvas <B2-Motion> [list ::GX::_multiviewDrag $host $slot move %x %y]
    if {$backend eq "native3d"} {bind $frame.canvas <B1-Motion> [list ::GX::_multiviewDrag $host $slot orbit %x %y]}
    bind $frame.canvas <Button-4> [list ::GX::_multiviewControl $host $slot plus]
    bind $frame.canvas <Button-5> [list ::GX::_multiviewControl $host $slot minus]
    if {$backend eq "native2d"} {
        set token [dict get $options scene_token];set native [dict get $scene native]
        dict set hosts $host views $slot scene_token $token
        if {[dict exists $options axis_presentation]} {native2DAxisPresentation $native [dict get $options axis_presentation]}
        native2DViewportHostCreate $frame $frame.canvas $native [list ::GX::_multiviewSchedule $host $slot]
        dict set hosts $host views $slot ready 1
        native2DGeometryCall $token fit_all {}
        _multiviewSchedule $host $slot
    } else {
        try {
            _multiviewStageLayers $host $slot [dict get $options layers]
            set temp [dict get $h temp]
            set cmd [list env LIBGL_ALWAYS_INDIRECT=0 LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=llvmpipe [auto_execok tclsh] [file join $::GX::scriptDir core native3d renderer_worker.tcl] [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so] readonly]
            if {[auto_execok prlimit] ne {}} {set cmd [concat [list prlimit --as=[expr {[configurationGet viewers.native3d.worker_address_space_budget_mib]*1024*1024}] --] $cmd]}
            set worker [open [concat [list |] $cmd [list 2>[file join $temp $slot-worker.log]]] r+]
            fconfigure $worker -blocking 0 -buffering line -encoding utf-8 -translation lf
            dict set hosts $host views $slot worker $worker
            dict set hosts $host views $slot view [viewerSceneDefaults]
            fileevent $worker readable [list ::GX::_multiviewReadable $host $slot]
        } on error {m o} {dict set hosts $host views $slot status "unavailable: $m";_multiviewStatus $host $m;return -options $o $m}
    }
    return [dict create host $host slot $slot backend $backend canvas $frame.canvas capabilities [expr {$backend eq "native2d"?"pan zoom fit exact_pick retained_geometry calibrated_image":"orbit pan zoom fit camera_presets layer_pick"}]]
}
proc ::GX::_multiviewValidateLayers {host layers} {
    set h [_multiviewRequire $host 1]
    if {[dict size $layers]<1 || [dict size $layers]>64 || [string bytelength $layers]>1048576} {error {Native3D layer budget exceeded}}
    dict for {id d} $layers {
        if {![regexp {^[A-Za-z0-9_:-]{1,128}$} $id]} {error {Invalid logical layer ID}}
        foreach k [dict keys $d] {if {$k ni {resource representation color unit derivation}} {error "Unknown managed layer property $k"}}
        set r [dict get $d resource];interactiveDocumentResourceInfo $r
        if {[dict get $r document_id] ne [dict get $h document]} {error {Native3D resources must belong to bound document}}
        if {[dict get $r metadata format] ni {native3d.vtp.v1 native3d.stl.v1 native3d.step.v1}} {error {Unsupported managed Native3D resource format}}
        if {![dict exists $d unit] || [dict get $d unit] eq {}} {error {Scientific layer must declare coordinates unit}}
        unitRegistryConvertCoordinates [dict get $d unit] [dict get $d unit] {0 1}
        if {[dict get $r size_bytes]>67108864} {error {Native3D resource exceeds host 64 MiB limit}}
        if {[datasetPublicationV2DictDefault $d representation surface] ni {surface wireframe surface_edges points}} {error {Unsupported layer representation}}
        set color [datasetPublicationV2DictDefault $d color {0.2 0.5 0.8}]
        if {[llength $color]!=3} {error {Expected RGB color}}
        foreach v $color {if {![string is double -strict $v] || !($v>=0&&$v<=1)} {error {Invalid layer RGB color}}}
    }
}
proc ::GX::_multiviewStageLayers {host slot descriptors} {
    variable ::GX::Multiview::hosts
    _multiviewValidateLayers $host $descriptors
    set total 0
    foreach p [dict get $hosts $host views $slot paths] {if {[file exists $p]} {incr total [file size $p]}}
    dict for {id d} $descriptors {incr total [dict get $d resource size_bytes]}
    if {$total>268435456} {error {Host staged-resource budget exceeds 256 MiB}}
    set paths {};set layers {}
    try {
        dict for {id d} $descriptors {
            set r [dict get $d resource];set path [_native3DGeometryStageResource $r paths]
            set format [lindex [split [dict get $r metadata format] .] 1]
            # Existing scientific importer checks the declared filename suffix.
            file rename -- $path $path.$format
            set path $path.$format;set paths [lreplace $paths end end $path]
            dict set layers $id [dict create kind geometry source_mode artifact absolute_path $path resource_path $path format $format sha256 [dict get $r sha256] visible 1 opacity 1 layer_order 0 representation [datasetPublicationV2DictDefault $d representation surface] base_color [join [datasetPublicationV2DictDefault $d color {0.2 0.5 0.8}] {;}] colormap viridis scalar_range {} scalar_array {} vector_array {} radius_array {} opacity_array {} tube_radius 0 isovalues {} volume_transfer {} volume_sample_distance .05 line_width 3 point_size 5 backface_culling 0 scalar_coloring 0 local_transform {}]
        }
    } on error {m o} {foreach path $paths {file delete -force -- $path};return -options $o $m}
    # Old staged paths stay until worker shutdown: an in-flight older frame can
    # still be reading them. Size is bounded by host refresh count (32).
    set old [dict get $hosts $host views $slot paths]
    if {[llength $old]+[llength $paths]>2048} {foreach p $paths {file delete -force -- $p};error {Refresh resource budget reached; recreate host}}
    dict set hosts $host views $slot paths [concat $old $paths]
    dict set hosts $host views $slot layers $layers
    dict set hosts $host views $slot options layers $descriptors
}
proc ::GX::scientificMultiviewHostBindIdentity {host mapping {frames {}}} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host]
    if {[dict size $mapping]>4096 || [string bytelength $mapping]>1048576} {error {Identity map budget exceeded}}
    dict for {logical refs} $mapping {
        if {$logical eq {} || [string length $logical]>128} {error {Invalid logical identity}}
        set units {}
        dict for {slot object} $refs {
            set v [dict get $h views $slot]
            if {[dict get $v backend] eq "native2d"} {
                native2DGeometryCall [dict get $v scene_token] describe [dict create object_token $object]
                lappend units [_native2DGeometryWorkingUnit [_native2DGeometryRequire [dict get $v scene_token]] $object]
            } else {
                set layer $object
                if {![catch {dict get $object layer_id} layer]} {
                    if {[lsort [dict keys $object]] ne {association layer_id logical_id} || [dict get $object association] ni {point cell} || ![string is entier -strict [dict get $object logical_id]] || [dict get $object logical_id]<0 || [dict get $object logical_id]>9007199254740991} {error {Invalid durable scientific element reference}}
                } else {set layer $object}
                if {![dict exists $v layers $layer]} {error {Identity map refers to an unknown 3D layer}}
                lappend units [dict get $v options layers $layer unit]
            }
        }
        if {[llength [lsort -unique $units]]!=1 || [lindex $units 0] eq {}} {error {Mapped objects require a common declared scientific coordinate unit}}
    }
    # Frame declarations describe correspondence; they confer no implicit
    # transform. Images must be calibrated through Native2D's existing API.
    dict set hosts $host mapping $mapping;dict set hosts $host frames $frames
    return [dict create mapped [dict size $mapping] policy explicit]
}
proc ::GX::scientificMultiviewHostSetSelection {host logicalIds {origin external}} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host];set ids [lsort -unique $logicalIds];set unmapped {}
    foreach id $ids {if {![dict exists $h mapping $id]} {lappend unmapped $id}}
    set accepted {};foreach id $ids {if {$id ni $unmapped} {lappend accepted $id}}
    set receipt [dict create logical_ids $accepted unmapped $unmapped origin $origin document [dict get $h document] revision [dict get $h revision] epoch [dict get $h epoch]]
    if {$accepted eq [dict get $h selection]} {dict set receipt echo_suppressed 1;return $receipt}
    dict set hosts $host selection $accepted
    dict for {slot v} [dict get $h views] {_multiviewSchedule $host $slot}
    _multiviewStatus $host [expr {$unmapped ne {}?"Unmapped selection: $unmapped":"Selection: $accepted"}]
    # Store before callback, so a synchronous echo is suppressed.
    if {[dict exists $h options selection_command]} {uplevel #0 [list {*}[dict get $h options selection_command] $receipt]}
    return $receipt
}
proc ::GX::_multiviewSchedule {host slot} {
    variable ::GX::Multiview::hosts
    if {![dict exists $hosts $host views $slot]} return
    if {[dict exists $hosts $host views $slot timer]} {after cancel [dict get $hosts $host views $slot timer]}
    dict set hosts $host views $slot timer [after 35 [list ::GX::_multiviewDraw $host $slot]]
}
proc ::GX::_multiviewDraw {host slot} {
    variable ::GX::Multiview::hosts
    if {![dict exists $hosts $host views $slot]} return
    catch {dict unset hosts $host views $slot timer}
    if {[catch {set h [_multiviewRequire $host]} m]} {_multiviewStatus $host $m;return}
    set v [dict get $h views $slot];set canvas [dict get $v canvas]
    if {![winfo exists $canvas] || ![winfo ismapped $canvas] || ![dict get $v ready] || ![dict get $v model_ready]} return
    set width [expr {max(160,min(1920,[winfo width $canvas]))}];set height [expr {max(120,min(1080,[winfo height $canvas]))}]
    if {[dict get $v backend] eq "native2d"} {
        if {[catch {
            set scene [_native2DGeometryRequire [dict get $v scene_token]];set native [dict get $scene native]
            set oldView [::GX::Native2D::core view_requested $native]
            if {[lrange $oldView 0 5] ne [list $width $height 75 20 15 45]} {::GX::Native2D::core view $native [list $width $height 75 20 15 45 [lindex $oldView 6]]}
            if {![dict exists $v fitted]} {native2DGeometryCall [dict get $v scene_token] fit_all {};dict set hosts $host views $slot fitted 1}
            native2DCanvasSnapshot $canvas [native2DPresentationSnapshot $native {point_budget 4096 include_construction_reference 1}]
            native2DCanvasReferenceImages $native $canvas
            foreach logical [dict get $h selection] {
                if {![dict exists $h mapping $logical $slot]} continue
                set object [_native2DGeometryObject $scene [dict get $h mapping $logical $slot]]
                foreach path [::GX::Native2D::core render_paths $native $object] {if {[llength $path]>1} {$canvas create line {*}[concat {*}$path] -fill #d87900 -width 4 -tags host_selection}}
            }
            native2DCanvasViewportClip $canvas $native
            dict set hosts $host views $slot status ready
            dict set hosts $host views $slot rendered_epoch [dict get $h epoch]
        } m]} {_multiviewStatus $host "Native2D: $m";dict set hosts $host views $slot status $m}
    } else {
        set layers [dict get $v layers]
        set logicalFocus {}
        foreach logical [dict get $h selection] {if {[dict exists $h mapping $logical $slot]} {
            set reference [dict get $h mapping $logical $slot]
            if {![catch {dict get $reference layer_id}]} {set logicalFocus $reference} else {dict set layers $reference base_color {1;.55;0}}
        }}
        set policy [native3dGraphicsPolicy];dict set policy execution Software
        set scene [dict create layers $layers view [dict get $v view] graphics_policy $policy cache_root [file join [dict get $h temp] derived_$slot] session_namespace [dict get $h session_token]]
        if {$logicalFocus ne {}} {dict set scene logical_focus $logicalFocus}
        _multiviewRequest $host $slot [list render $scene [file join [dict get $h temp] $slot.png] $width $height preview]
    }
}
proc ::GX::_multiviewStatus {host message} {
    if {![dict exists $::GX::Multiview::hosts $host]} return
    set root [dict get $::GX::Multiview::hosts $host root]
    if {[winfo exists $root.status]} {$root.status configure -text $message}
}
proc ::GX::_multiviewRequest {host slot request} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host];set v [dict get $h views $slot]
    if {![dict get $v ready] || ![dict get $v model_ready]} return
    # Keep only latest request; camera/pick commands wait for matching epoch.
    if {[dict get $v busy]} {dict set hosts $host views $slot pending $request;return}
    dict set hosts $host views $slot busy 1
    dict set hosts $host views $slot request_epoch [dict get $h epoch]
    dict set hosts $host views $slot request_kind [lindex $request 0]
    puts [dict get $v worker] $request;flush [dict get $v worker]
}
proc ::GX::_multiviewReadable {host slot} {
    variable ::GX::Multiview::hosts
    if {![dict exists $hosts $host views $slot worker]} return
    set v [dict get $hosts $host views $slot];set ch [dict get $v worker]
    if {[gets $ch line]<0} {
        if {[eof $ch]} {fileevent $ch readable {};dict set hosts $host views $slot ready 0;dict set hosts $host views $slot status worker_stopped;_multiviewStatus $host {Native3D worker stopped}}
        return
    }
    # Lifetime/generation expiry destroys the host. An owner revision instead
    # waits for ModelChanged; a late frame must not destroy unrelated views.
    if {[catch {set h [_multiviewRequire $host 1]} m]} {scientificMultiviewHostDestroy $host;return}
    set revisionPending [expr {[dict get [interactiveDocumentRead [dict get $h document]] revision]!=[dict get $h revision]}]
    if {$line eq "GX3DE_VIEWER_WORKER_READY"} {
        dict set hosts $host views $slot ready 1
        if {!$revisionPending} {_multiviewSchedule $host $slot}
        return
    }
    dict set hosts $host views $slot busy 0
    if {[dict get $v request_kind] eq "render"} {
        set live [lmap layer [dict values [dict get $hosts $host views $slot layers]] {dict get $layer absolute_path}]
        set retained {}
        foreach p [dict get $hosts $host views $slot paths] {if {$p in $live} {lappend retained $p} else {catch {file delete -force -- $p}}}
        dict set hosts $host views $slot paths $retained
    }
    lassign $line status result
    if {$revisionPending} {
        dict set hosts $host views $slot stale_rejected 1
        dict set hosts $host views $slot pending {}
        dict set hosts $host views $slot status model_refresh_required
        _multiviewStatus $host {Scientific host model changed; supply an explicit model refresh}
        return
    } elseif {[dict get $v request_epoch]!=[dict get $h epoch]} {
        dict set hosts $host views $slot stale_rejected 1
    } elseif {$status ne "ok"} {
        dict set hosts $host views $slot status $result;_multiviewStatus $host "Native3D: $result"
    } elseif {[dict get $v request_kind] eq "pick"} {
        dict set hosts $host views $slot last_pick $result
        set logical {}
        if {[dict get $result hit]} {dict for {id refs} [dict get $h mapping] {
            if {![dict exists $refs $slot]} continue
            set reference [dict get $refs $slot]
            if {![catch {dict get $reference layer_id} layer]} {
                set key logical_[dict get $reference association]_id
                if {$layer eq [dict get $result layer_id] && [dict exists $result $key] && [dict get $result $key]==[dict get $reference logical_id]} {lappend logical $id}
            } elseif {$reference eq [dict get $result layer_id]} {lappend logical $id}
        }}
        scientificMultiviewHostSetSelection $host $logical $slot
    } else {
        foreach k {camera_position camera_target camera_up} {if {[dict exists $result $k]} {dict set hosts $host views $slot view $k [join [dict get $result $k] {;}]}}
        set path [file join [dict get $h temp] $slot.png]
        if {[file isfile $path] && [winfo exists [dict get $v canvas]]} {
            set picture [image create photo -file $path]
            [dict get $v canvas] delete all
            [dict get $v canvas] create image 0 0 -anchor nw -image $picture
            if {[dict get $v image] ne {}} {image delete [dict get $v image]}
            dict set hosts $host views $slot image $picture
            dict set hosts $host views $slot last_receipt $result
            dict set hosts $host views $slot status ready
            dict set hosts $host views $slot rendered_epoch [dict get $h epoch]
            if {![dict exists $v fitted]} {
                dict set hosts $host views $slot fitted 1
                _multiviewControl $host $slot fit
            }
        }
    }
    set pending [dict get $hosts $host views $slot pending]
    dict set hosts $host views $slot pending {}
    if {$pending ne {}} {_multiviewRequest $host $slot $pending}
}
proc ::GX::_multiviewControl {host slot action} {
    set h [_multiviewRequire $host];set v [dict get $h views $slot]
    if {[dict get $v backend] eq "native2d"} {
        set s [dict get $v scene_token]
        if {$action eq "fit"} {native2DGeometryCall $s fit_all {}} else {
            native2DGeometryCall $s zoom [dict create factor [expr {$action eq "plus"?1/1.3:1.3}] point [list [expr {[winfo width [dict get $v canvas]]/2}] [expr {[winfo height [dict get $v canvas]]/2}]]]
        }
        _multiviewSchedule $host $slot
    } else {
        set path [file join [dict get $h temp] $slot.png]
        if {$action in {plus minus}} {_multiviewRequest $host $slot [list navigate zoom [expr {$action eq "plus"?1:-1}] 0 $path]} else {
            set preset [dict get {fit fit_scene front front iso isometric} $action]
            _multiviewRequest $host $slot [list preset $preset {} $path [expr {max(160,[winfo width [dict get $v canvas]])}] [expr {max(120,[winfo height [dict get $v canvas]])}]]
        }
    }
}
proc ::GX::_multiviewClick {host slot x y} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host];set v [dict get $h views $slot];focus [dict get $v canvas]
    dict set hosts $host views $slot drag [list $x $y]
    if {[dict get $v backend] eq "native3d"} {
        if {[dict get $v rendered_epoch]==[dict get $h epoch]} {_multiviewRequest $host $slot [list pick $x $y]}
        return
    }
    set objects {};dict for {id refs} [dict get $h mapping] {if {[dict exists $refs $slot]} {lappend objects [dict get $refs $slot]}}
    set hit [native2DGeometryCall [dict get $v scene_token] selection_pick [dict create object_tokens $objects device [list $x $y] target object]]
    set logical {}
    if {[dict get $hit hit]} {dict for {id refs} [dict get $h mapping] {if {[dict exists $refs $slot] && [dict get $refs $slot] eq [dict get $hit member object_token]} {lappend logical $id}}}
    scientificMultiviewHostSetSelection $host $logical $slot
}
proc ::GX::_multiviewDrag {host slot phase x y} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host];set v [dict get $h views $slot]
    if {$phase ne "start" && [dict exists $v drag]} {
        lassign [dict get $v drag] px py;set dx [expr {$x-$px}];set dy [expr {$y-$py}]
        if {[dict get $v backend] eq "native2d"} {native2DGeometryCall [dict get $v scene_token] pan [dict create delta [list $dx $dy]];_multiviewSchedule $host $slot} else {_multiviewRequest $host $slot [list navigate [expr {$phase eq "orbit"?"orbit":"pan"}] $dx $dy [file join [dict get $h temp] $slot.png]]}
    }
    dict set hosts $host views $slot drag [list $x $y]
}
proc ::GX::scientificMultiviewHostModelChanged {host revision changedIds reason} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host 1];set owner [interactiveDocumentRead [dict get $h document]]
    if {$revision!=[dict get $owner revision] || $revision<[dict get $h revision]} {error {Model revision does not match authoritative document}}
    if {$revision==[dict get $h revision]} {return [dict create refreshed 0 reason no_revision_change]}
    dict incr h epoch;dict set h revision $revision;dict set h selection {};dict set h mapping {}
    dict set hosts $host $h
    dict for {slot v} [dict get $h views] {dict set hosts $host views $slot pending {};dict set hosts $host views $slot model_ready 0;dict set hosts $host views $slot status model_refresh_required;if {[dict exists $v timer]} {after cancel [dict get $v timer]}}
    if {![dict exists $h options refresh_command]} {_multiviewStatus $host {Model changed; explicit regeneration procedure unavailable};return [dict create refreshed 0 status regeneration_unavailable]}
    # Trusted owner adapter returns bindings only. It must explicitly declare
    # its generation procedure; coordinator never invents a 3D reconstruction.
    set binding [uplevel #0 [list {*}[dict get $h options refresh_command] $owner $changedIds $reason]]
    dict for {slot options} [dict get $binding views] {
        set v [dict get $hosts $host views $slot]
        if {[dict get $v backend] eq "native2d"} {
            set scene [_native2DGeometryRequire [dict get $options scene_token]]
            if {[dict get $scene document_id] ne [dict get $h document]} {error {Refresh returned foreign scene}}
            set old [dict get $v scene_token]
            dict set hosts $host views $slot scene_token [dict get $options scene_token]
            dict set ::GX::ViewportHost::hosts [dict get $v canvas] scene [dict get $scene native]
            if {$old ne [dict get $options scene_token] && [datasetPublicationV2DictDefault [dict get $v options] owned 0]} {catch {native2DGeometryClose $old}}
        } else {_multiviewStageLayers $host $slot [dict get $options layers]}
    }
    scientificMultiviewHostBindIdentity $host [dict get $binding mapping]
    foreach slot [dict keys [dict get $binding views]] {dict set hosts $host views $slot model_ready 1}
    dict for {slot v} [dict get $hosts $host views] {_multiviewSchedule $host $slot}
    return [dict create refreshed 1 revision $revision epoch [dict get $hosts $host epoch] changed_ids $changedIds]
}
proc ::GX::scientificMultiviewHostConfigure {host options} {
    variable ::GX::Multiview::hosts
    set h [_multiviewRequire $host]
    foreach k [dict keys $options] {if {$k ni {layout order axis_presentation}} {error "Unknown host layout option $k"}}
    set axisChanges {}
    if {[dict exists $options axis_presentation]} {
        dict for {slot descriptor} [dict get $options axis_presentation] {
            if {![dict exists $h views $slot] || [dict get $h views $slot backend] ne {native2d}} {error {Axis presentation requires an attached Native2D slot}}
            set scene [_native2DGeometryRequire [dict get $h views $slot scene_token]]
            dict set axisChanges $slot [native2DAxisPresentationValidate [dict get $scene native] $descriptor]
        }
    }
    set pane [dict get $h pane]
    if {[dict exists $options layout]} {
        set layout [dict get $options layout];if {$layout ni {horizontal vertical}} {error {Unsupported layout}}
        # ttk panedwindow orientation is immutable; reparent by pack -in a new
        # sibling pane while preserving every viewport and backend instance.
        if {$layout ne [dict get $h layout]} {
            set frames [$pane panes];foreach f $frames {$pane forget $f}
            pack forget $pane
            set replacement [dict get $h root].layout[incr ::GX::Multiview::serial]
            ttk::panedwindow $replacement -orient $layout
            pack $replacement -before [dict get $h root].status -fill both -expand 1
            # Tk panes must be children of pane or its parent: frames originally
            # under old pane cannot move to a sibling. Use stable root children.
            foreach f $frames {$replacement add $f -weight 1;raise $f}
            destroy $pane
            dict set hosts $host pane $replacement;dict set hosts $host layout $layout
        }
    }
    if {[dict exists $hosts $host pane]} {set pane [dict get $hosts $host pane]}
    if {[dict exists $options order]} {
        set order [dict get $options order]
        if {[lsort $order] ne [lsort [dict keys [dict get $h views]]]} {error {Order must name each slot once}}
        foreach f [$pane panes] {$pane forget $f}
        foreach slot $order {set f [dict get $h views $slot frame];$pane add $f -weight 1;raise $f}
    }
    dict for {slot descriptor} $axisChanges {
        native2DGeometryCall [dict get $h views $slot scene_token] axis_presentation [dict create axis_presentation $descriptor]
        dict set hosts $host views $slot options axis_presentation $descriptor
    }
    dict for {slot v} [dict get $h views] {_multiviewSchedule $host $slot}
}
proc ::GX::scientificMultiviewHostDestroy {host} {
    variable ::GX::Multiview::hosts
    if {![dict exists $hosts $host]} {return 0}
    set h [dict get $hosts $host];dict unset hosts $host
    interactiveDocumentLifecycleUnsubscribe [dict get $h subscription]
    dict for {slot v} [dict get $h views] {
        if {[dict exists $v timer]} {after cancel [dict get $v timer]}
        if {[dict exists $v worker]} {
            set worker [dict get $v worker];fileevent $worker readable {}
            # Kill in-flight renderer before unlinking staged files; channel
            # close is nonblocking and never waits for a VTK rendering call.
            foreach pid [pid $worker] {catch {exec kill -TERM -- $pid}}
            catch {close $worker}
        }
        if {[dict get $v image] ne {}} {catch {image delete [dict get $v image]}}
        if {[dict get $v backend] eq "native2d"} {
            native2DViewportDispose [dict get $v canvas] [dict get $v canvas]
            if {[datasetPublicationV2DictDefault [dict get $v options] owned 0]} {catch {native2DGeometryClose [dict get $v scene_token]}}
        }
        foreach path [dict get $v paths] {catch {file delete -force -- $path}}
    }
    catch {destroy [dict get $h root]}
    catch {file delete -force -- [dict get $h temp]}
    return 1
}
