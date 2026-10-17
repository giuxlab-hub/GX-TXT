# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Native2DRaster {variable resources {};variable cache {};variable feedback {};variable dimensions {};variable workers {}}
proc ::GX::native2DReferenceImageBind {scene object resource} {
    variable ::GX::Native2DRaster::resources
    interactiveDocumentResourceInfo $resource
    set state [::GX::Native2D::core image_get $scene $object]
    lassign [_native2DImageDimensions $resource] width height
    if {$state ne {}&&($width!=[dict get $state width]||$height!=[dict get $state height])} {error {Managed raster dimensions differ from Native image state}}
    if {$state eq {}||[dict get $state resource_id] ne [dict get $resource sha256]} {error {Reference image resource identity mismatch}}
    dict set resources $scene $object $resource
}
proc ::GX::_native2DImagePath {scene object} {
    variable ::GX::Native2DRaster::resources
    if {![dict exists $resources $scene $object]} {error {Reference image has no managed raster binding}}
    set resource [dict get $resources $scene $object]
    return [file join [_documentResourceRoot [dict get $resource document_id] 1] [dict get $resource sha256].blob]
}
proc ::GX::_native2DRasterHelper {args} {
    variable scriptDir
    return [exec [runtimeToolRequired python] [file join $scriptDir core python native2d_scene_renderer_v1.py] {*}$args 2>@1]
}
proc ::GX::_native2DImagePlan {scene object} {
    set state [::GX::Native2D::core image_get $scene $object]
    if {$state eq {}||![dict get $state visible]||[dict get $state opacity]<=0} {return {}}
    set opacity [dict get $state opacity]
    set style [::GX::Native2D::core object_style $scene $object]
    if {[dict get $style layer]!=0} {
        set layer [::GX::Native2D::core layer_info $scene [dict get $style layer]]
        if {![dict get $layer visible]} {return {}}
        set opacity [expr {$opacity*[dict get $layer opacity]}]
    }
    if {$opacity<=0} {return {}}
    set height [dict get $state height]
    set points {}
    foreach pixel [list [list 0 $height] [list 1 $height] [list 0 [expr {$height-1}]]] {lappend points [::GX::Native2D::core device $scene [::GX::Native2D::core image_map $scene $object $pixel 0]]}
    lassign [lindex $points 0] x y;lassign [lindex $points 1] ax ay;lassign [lindex $points 2] bx by
    set frame [list $x $y [expr {$ax-$x}] [expr {$ay-$y}] [expr {$bx-$x}] [expr {$by-$y}]]
    return "image\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 [_native2DImagePath $scene $object]]]\t$opacity\t$frame"
}
proc ::GX::native2DCanvasReferenceImages {scene canvas} {
    variable ::GX::Native2DRaster::cache
    lassign [::GX::Native2D::core view $scene] width height left top right bottom
    set width [expr {int($width)}];set height [expr {int($height)}]
    if {$width<16||$height<16||$width>4096||$height>4096} return
    set rows [_native2DImageRows $scene]
    if {$rows eq {}} {if {[dict exists $::GX::Native2DRaster::workers $canvas]} {dict set ::GX::Native2DRaster::workers $canvas desired {};dict set ::GX::Native2DRaster::workers $canvas pending {}};return}
    set plan "size\t$width\t$height\t0 0 0 0\t[list $left $top [expr {$width-$right}] [expr {$height-$bottom}]]\n[join $rows \n]\n"
    set signature [list $scene $plan]
    _native2DRasterRequest $canvas $signature $plan
    _native2DRasterPresent $canvas
}
# The interactive presenter never starts a synchronous Python process. Each
# canvas owns one worker and one replaceable pending plan, so input cannot build
# a render queue. The synchronous preview/export path below remains guarded.
proc ::GX::_native2DRasterRequest {canvas signature plan} {
    variable scriptDir
    variable ::GX::Native2DRaster::workers
    variable ::GX::Native2DRaster::cache
    if {![dict exists $workers $canvas]} {
        set channel [open [list | [runtimeToolRequired python] -B [file join $scriptDir core python native2d_scene_renderer_v1.py] worker] r+]
        fconfigure $channel -blocking 0 -buffering line -encoding ascii -translation lf
        dict set workers $canvas [dict create channel $channel busy 0 pending {} scene [lindex $signature 0]]
        fileevent $channel readable [list ::GX::_native2DRasterReady $canvas]
    }
    dict set workers $canvas desired $signature
    if {[dict get $workers $canvas busy]} {
        dict set workers $canvas pending [list $signature $plan]
        return
    }
    if {[dict exists $cache $canvas signature]&&[dict get $cache $canvas signature] eq $signature} return
    dict set workers $canvas busy 1
    dict set workers $canvas signature $signature
    puts [dict get $workers $canvas channel] [binary encode base64 -maxlen 0 [encoding convertto utf-8 $plan]]
}
proc ::GX::_native2DRasterReady {canvas} {
    variable ::GX::Native2DRaster::workers
    variable ::GX::Native2DRaster::cache
    if {![dict exists $workers $canvas]} return
    set channel [dict get $workers $canvas channel]
    if {[gets $channel result]<0} {
        if {[eof $channel]} {native2DRasterCanvasDispose $canvas;bgerror {Native2D reference raster worker ended unexpectedly}}
        return
    }
    if {[string match {ERROR *} $result]} {
        native2DRasterCanvasDispose $canvas
        bgerror "Reference image rendering failed: [encoding convertfrom utf-8 [binary decode base64 [string range $result 6 end]]]"
        return
    }
    if {![winfo exists $canvas]} {native2DRasterCanvasDispose $canvas;return}
    # An obsolete frame never replaces pixels for a newer desired view or a
    # hidden image. Keep the previous complete raster until the latest is ready.
    if {[dict get $workers $canvas desired] eq [dict get $workers $canvas signature]} {
        if {![dict exists $cache $canvas image]} {dict set cache $canvas image [image create photo]}
        [dict get $cache $canvas image] configure -data $result -format png
        dict set cache $canvas signature [dict get $workers $canvas signature]
        _native2DRasterPresent $canvas
    }
    dict set workers $canvas busy 0
    set pending [dict get $workers $canvas pending]
    dict set workers $canvas pending {}
    if {$pending ne {}} {_native2DRasterRequest $canvas {*}$pending}
}
proc ::GX::_native2DRasterPresent {canvas} {
    variable ::GX::Native2DRaster::cache
    if {![dict exists $cache $canvas image]||![winfo exists $canvas]} return
    set x 0;set y 0
    if {[dict exists $cache $canvas signature]&&[dict exists $::GX::Native2DRaster::workers $canvas desired]} {
        set oldPlan [lindex [dict get $cache $canvas signature] 1]
        set newPlan [lindex [dict get $::GX::Native2DRaster::workers $canvas desired] 1]
        set oldRows [split [string trim $oldPlan] \n];set newRows [split [string trim $newPlan] \n]
        if {[llength $oldRows]==[llength $newRows]&&[llength $oldRows]>1} {
            set old [split [lindex $oldRows 1] \t];set new [split [lindex $newRows 1] \t]
            set a [lindex $old 3];set b [lindex $new 3];set translation 1
            if {[lrange $old 0 2] ne [lrange $new 0 2]} {set translation 0}
            foreach previous [lrange $a 2 5] current [lrange $b 2 5] {if {abs($previous-$current)>1e-8*max(1,abs($previous))} {set translation 0}}
            # All rasters share Native's camera translation. Move the complete
            # previous image immediately during pan; the worker fills exposed
            # edge pixels and publishes the latest complete frame asynchronously.
            if {$translation} {set x [expr {[lindex $b 0]-[lindex $a 0]}];set y [expr {[lindex $b 1]-[lindex $a 1]}]}
        }
    }
    set items [$canvas find withtag native_reference_images]
    if {$items eq {}} {set item [$canvas create image $x $y -anchor nw -image [dict get $cache $canvas image] -tags native_reference_images]} else {set item [lindex $items 0];$canvas coords $item $x $y}
    $canvas lower $item
    if {[llength [$canvas find withtag native_plot_background]]} {$canvas raise $item native_plot_background}
}

proc ::GX::native2DCanvasPreview {scene document mode {options {}}} {
    if {$mode ni {current fit}} {error {Preview mode must be current or fit}}
    foreach key [dict keys $options] {if {$key ni {width height padding background grid axes reference_images dimensions constraints annotations point_budget output_format output_file include_construction_reference}} {error "Unknown preview option '$key'"}}
    set saved [::GX::Native2D::core view_state $scene]
    set feedback [datasetPublicationV2DictDefault $::GX::Native2DRaster::feedback $scene {}]
    set visibility {}
    foreach id $feedback {if {$id in [::GX::Native2D::core ids $scene]} {dict set visibility $id [dict get [::GX::Native2D::core object_style $scene $id] visible]}}

    set width [datasetPublicationV2DictDefault $options width 640]
    lassign [::GX::Native2D::core view $scene] sourceWidth sourceHeight
    set height [datasetPublicationV2DictDefault $options height [expr {int(round($width*$sourceHeight/$sourceWidth))}]]
    # Feedback is hidden only inside the guarded synchronous rendering below.
    set view [::GX::Native2D::core preview_view $scene [expr {$mode eq "fit"}] $width $height [datasetPublicationV2DictDefault $options padding .03]]
    set format [datasetPublicationV2DictDefault $options output_format png]
    if {$format ni {png pdf}} {error {Preview output_format must be png or pdf}}
    set destination [datasetPublicationV2DictDefault $options output_file {}]
    if {$destination eq {}} {set root [_documentResourceRoot $document]} else {set root [file dirname [file normalize $destination]]}
    file mkdir $root
    set channel [file tempfile plan [file join $root .preview-plan-]];set png $plan.png
    try {
        dict for {id visible} $visibility {::GX::Native2D::core visible $scene $id 0}
        set view [::GX::Native2D::core preview_view $scene [expr {$mode eq "fit"}] $width $height [datasetPublicationV2DictDefault $options padding .03]]
        ::GX::Native2D::core view $scene $view
        set background [datasetPublicationV2DictDefault $options background [::GX::Native2D::core background $scene]]
        lassign [::GX::Native2D::core view $scene] unused unused left top right bottom
        fconfigure $channel -encoding utf-8 -translation lf
        puts $channel "size\t$width\t$height\t$background\t[list $left $top [expr {$width-$right}] [expr {$height-$bottom}]]"
        if {[datasetPublicationV2DictDefault $options reference_images 1]} {foreach row [_native2DImageRows $scene] {puts $channel $row}}
        set snapshot [native2DPresentationSnapshot $scene [dict create point_budget [datasetPublicationV2DictDefault $options point_budget 4096] include_construction_reference [datasetPublicationV2DictDefault $options include_construction_reference 1]]]
        foreach primitive [dict get $snapshot grid_primitives] {
            set axes [expr {[dict get $primitive classification]==2}]
            if {![datasetPublicationV2DictDefault $options [expr {$axes?"axes":"grid"}] 1]} continue
            puts $channel "line\t[dict get $primitive color]\t[dict get $primitive width]\t[concat [dict get $primitive a] [dict get $primitive b]]\t[dict get $primitive style]"
        }
        foreach object [dict get $snapshot objects] {
            if {[::GX::Native2D::core image_get $scene [dict get $object id]] ne {}} continue
            set style [dict get $object style]
            foreach path [dict get $object paths] {
                if {[llength $path]>1} {puts $channel "line\t[dict get $style color]\t[dict get $style line_width]\t[concat {*}$path]\t[dict get $style line_style]"} elseif {[llength $path]==1} {puts $channel "point\t[dict get $style color]\t3\t[lindex $path 0]"}
            }
            foreach entry [native2DPresentationMarkers $object] {
                set marker [dict get $entry geometry];set markerStyle [dict get $entry style]
                foreach keys {{tail tip} {head_left tip head_right}} {
                    set points {};foreach key $keys {lappend points [dict get $marker $key]}
                    puts $channel "line\t[dict get $markerStyle color]\t[dict get $markerStyle line_width]\t[concat {*}$points]"
                }
            }
        }
        set readable [uiFieldColorToRGBA [uiFieldColorReadableText [uiFieldColorFromRGBA $background]]]
        if {[datasetPublicationV2DictDefault $options annotations 0]} {
            foreach text [dict get $snapshot texts] {puts $channel "label\t$readable\t[dict get $text position]\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 [dict get $text text]]]\t[dict get $text anchor]\t[dict get $text font_size]\t[dict get $text rotation]"}
        }
        foreach relationship [::GX::Native2D::core constraint_list $scene] {
            if {[dict get $relationship disabled]} continue
            if {[catch {set geometry [::GX::Native2D::core sketch_dimension_geometry $scene [dict get $relationship id]]}]} {
                if {[datasetPublicationV2DictDefault $options constraints 0]} {
                    set anchor [::GX::Native2D::core device $scene [::GX::Native2D::core interaction_constraint_location $scene [dict get $relationship id]]]
                    puts $channel "text\t$readable\t$anchor\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 [dict get $relationship kind]]]"
                }
                continue
            }
            if {![datasetPublicationV2DictDefault $options dimensions 1]} continue
            foreach line [dict get $geometry lines] {puts $channel "line\t$readable\t.75\t[concat {*}$line]"}
            puts $channel "text\t$readable\t[dict get $geometry label]\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 [format %.7g [dict get $geometry value]]]]"
        }
        close $channel;set channel {}
        _native2DRasterHelper [expr {$format eq "pdf"?"pdf":"render"}] $plan $png
        set metadata [dict create format [expr {$format eq "pdf"?"document.pdf":"image.png"}] width $width height $height mode $mode]
        if {$destination ne {}} {file rename -force -- $png $destination;return [dict merge $metadata [dict create path $destination]]}
        return [interactiveDocumentResourceImportNumeric $document $png $metadata]
    } finally {
        dict for {id visible} $visibility {::GX::Native2D::core visible $scene $id $visible}
        ::GX::Native2D::core view_state $scene $saved
        if {$channel ne {}} {close $channel}
        file delete -force -- $plan $png
    }
}

# Host-only feedback identity list; geometry and all transforms still belong to
# Native. It is never saved and never exposed as an alternate scene authority.
proc ::GX::native2DSceneFeedback {scene ids} {dict set ::GX::Native2DRaster::feedback $scene $ids}
proc ::GX::native2DRasterSceneDispose {scene} {
    foreach variable {resources feedback} {if {[dict exists [set ::GX::Native2DRaster::$variable] $scene]} {dict unset ::GX::Native2DRaster::$variable $scene}}
    # A newly started worker may not have produced its first cache entry yet.
    dict for {canvas value} $::GX::Native2DRaster::workers {if {[dict get $value scene] eq $scene} {native2DRasterCanvasDispose $canvas}}
    dict for {canvas value} $::GX::Native2DRaster::cache {if {[lindex [dict get $value signature] 0] eq $scene} {native2DRasterCanvasDispose $canvas}}
}
proc ::GX::native2DRasterCanvasDispose {canvas} {
    if {[dict exists $::GX::Native2DRaster::workers $canvas]} {
        set channel [dict get $::GX::Native2DRaster::workers $canvas channel]
        fileevent $channel readable {}
        # Closing stdin ends the private worker; no later callback retains the
        # canvas/document owner or can reattach pixels to a reopened workspace.
        catch {close $channel}
        dict unset ::GX::Native2DRaster::workers $canvas
    }
    if {[dict exists $::GX::Native2DRaster::cache $canvas]} {catch {image delete [dict get $::GX::Native2DRaster::cache $canvas image]};dict unset ::GX::Native2DRaster::cache $canvas}
}

proc ::GX::_native2DImageRows {scene} {
    set rows {}
    foreach object [::GX::Native2D::core ids $scene] {
        set row [_native2DImagePlan $scene $object]
        if {$row ne {}} {lappend rows [list [dict get [::GX::Native2D::core object_style $scene $object] order] $row]}
    }
    return [lmap item [lsort -integer -index 0 $rows] {lindex $item 1}]
}

proc ::GX::_native2DImageDimensions {resource} {
    set key [list [interactiveDocumentSessionToken] [dict get $resource document_id] [datasetPublicationV2DictDefault $resource owner_generation {}] [dict get $resource sha256]]
    if {![dict exists $::GX::Native2DRaster::dimensions $key]} {
        interactiveDocumentResourceInfo $resource
        set path [file join [_documentResourceRoot [dict get $resource document_id] 1] [dict get $resource sha256].blob]
        if {[dict size $::GX::Native2DRaster::dimensions]>=256} {set ::GX::Native2DRaster::dimensions {}}
        dict set ::GX::Native2DRaster::dimensions $key [_native2DRasterHelper info $path]
    }
    return [dict get $::GX::Native2DRaster::dimensions $key]
}
