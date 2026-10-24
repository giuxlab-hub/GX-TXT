# SPDX-License-Identifier: GPL-3.0-or-later
# Optional GUI-host presentation. The C geometry engine remains authoritative.
namespace eval ::GX::Native2DSprite {variable hosts {};variable pending {}}
proc ::GX::native2DSpriteSceneApiInfo {} {
    return [dict create api_id NATIVE2D_SPRITE_SCENE_API_v1 api_version 1 host_only 1 operations {native2DSpriteSceneCreate native2DSpriteSceneBegin native2DSpriteSceneBatch native2DSpriteSceneEnd native2DSpriteSceneDescribe native2DSpriteSceneAnchor native2DSpriteSceneHit native2DSpriteSceneRemove native2DSpriteSceneDispose native2DSpriteSceneObject native2DSpriteSceneAppend native2DSpriteSceneControls native2DSpriteSceneAttach native2DSpriteSceneSync native2DSpriteSceneDetach native2DSpriteSceneDiagnostics}]
}
proc ::GX::native2DSpriteSceneCreate {canvas} {
    variable ::GX::Native2DSprite::hosts
    if {![dict exists $hosts $canvas]} {
        native2DEnsure
        set handle [::gx::native2d::sprite_scene $canvas]
        dict set hosts $canvas $handle
        set script [list ::GX::_native2DSpriteDestroyed $canvas %W]
        if {$script ni [split [bind $canvas <Destroy>] \n]} {bind $canvas <Destroy> +$script}
    }
    return [dict get $hosts $canvas]
}
proc ::GX::_native2DSpriteDestroyed {canvas actual} {if {$actual eq $canvas} {native2DSpriteSceneDispose $canvas}}
proc ::GX::native2DSpriteSceneDispose {canvas} {
    variable ::GX::Native2DSprite::hosts
    catch {dict unset ::GX::Native2DSprite::pending $canvas}
    if {![dict exists $hosts $canvas]} return
    set native [dict get $hosts $canvas];dict unset hosts $canvas
    if {[llength [info commands $native]]} {$native destroy}
}
proc ::GX::native2DSpriteSceneBatch {canvas updates} {set native [native2DSpriteSceneCreate $canvas];$native batch $updates}
proc ::GX::native2DSpriteSceneDescribe {canvas {id {}}} {set n [native2DSpriteSceneCreate $canvas];if {$id eq {}} {return [$n describe]};return [$n describe $id]}
proc ::GX::native2DSpriteSceneAnchor {canvas id name} {set n [native2DSpriteSceneCreate $canvas];return [$n anchor $id $name]}
proc ::GX::native2DSpriteSceneHit {canvas position {tolerance 0}} {set n [native2DSpriteSceneCreate $canvas];return [$n hit $position $tolerance]}
proc ::GX::native2DSpriteSceneRemove {canvas ids} {set n [native2DSpriteSceneCreate $canvas];$n remove $ids}
proc ::GX::native2DSpriteSceneBegin {canvas {clip {}}} {
    set n [native2DSpriteSceneCreate $canvas]
    if {$clip eq {}} {$n begin} else {$n begin $clip}
    dict set ::GX::Native2DSprite::pending $canvas {}
    # This layer belongs between the existing grid and all interactive overlays.
    if {[$canvas find withtag native_grid_presenter] ne {}} {$canvas raise native_sprite_scene native_grid_presenter}
}
proc ::GX::native2DSpriteSceneAppend {canvas id geometry {anchors {}}} {
    variable ::GX::Native2DSprite::pending
    if {![dict exists $pending $canvas]} {error {Begin the sprite presentation frame first}}
    if {![dict exists $pending $canvas $id]} {dict set pending $canvas $id [dict create id $id geometry {} anchors {} z [dict size [dict get $pending $canvas]]]}
    set row [dict get $pending $canvas $id]
    dict set row geometry [concat [dict get $row geometry] $geometry]
    dict set row anchors [dict merge [dict get $row anchors] $anchors]
    dict set pending $canvas $id $row
}
proc ::GX::native2DSpriteSceneEnd {canvas} {
    set rows {};dict for {id row} [dict get $::GX::Native2DSprite::pending $canvas] {lappend rows $row}
    set n [native2DSpriteSceneCreate $canvas];if {$rows ne {}} {$n batch $rows};$n end
    dict unset ::GX::Native2DSprite::pending $canvas
}
proc ::GX::native2DSpriteSceneObject {canvas id object background} {
    if {$object eq {} || [lindex [dict get $object style color] 3]<=0} return
    set style [dict get $object style]
    set color [dict get [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $style color]] $background] rgb]
    set dash [dict get {0 {} 1 {6 3} 2 {1 3}} [dict get $style line_style]]
    set geometry {}
    foreach path [dict get $object paths] {
        if {[dict get $object kind] eq {curve} && [llength $path]>1} {lappend geometry [dict create kind line points $path stroke $color width [dict get $style line_width] dash $dash]}
        if {[dict get $object kind] ne {curve} || [dict get $style marker]!=0} {
            foreach point $path {
                lassign $point x y
                if {[dict get $style marker]==3} {
                    lappend geometry [dict create kind line points [list [list [expr {$x-3}] $y] [list [expr {$x+3}] $y]] stroke $color]
                    lappend geometry [dict create kind line points [list [list $x [expr {$y-3}]] [list $x [expr {$y+3}]]] stroke $color]
                } else {
                    lappend geometry [dict create kind [expr {[dict get $style marker]==2?{rectangle}:{ellipse}}] points [list [list [expr {$x-3}] [expr {$y-3}]] [list [expr {$x+3}] [expr {$y+3}]]] stroke $color fill $color]
                }
            }
        }
    }
    set anchors {}
    foreach entry [native2DPresentationMarkers $object] {
        set m [dict get $entry geometry];set ms [dict get $entry style]
        set rgb [dict get [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $ms color]] $background] rgb]
        lappend geometry [dict create kind line points [list [dict get $m tail] [dict get $m tip]] stroke $rgb width [dict get $ms line_width]]
        lappend geometry [dict create kind line points [list [dict get $m head_left] [dict get $m tip] [dict get $m head_right]] stroke $rgb width [dict get $ms line_width]]
        set prefix [expr {[dict exists $entry part_id]?"part_[dict get $entry part_id]":"direction"}]
        lassign [dict get $m tail] ax ay;lassign [dict get $m tip] bx by
        dict set anchors ${prefix}_tip [dict create position [dict get $m tip] direction [list [expr {$bx-$ax}] [expr {$by-$ay}]]]
        dict set anchors ${prefix}_tail [dict create position [dict get $m tail] direction [list [expr {$bx-$ax}] [expr {$by-$ay}]]]
    }
    native2DSpriteSceneAppend $canvas $id $geometry $anchors
}
proc ::GX::native2DSpriteSceneControls {canvas scene object selected color id} {
    set geometry [::GX::Native2D::core sprite_controls $scene $object $selected $color]
    native2DSpriteSceneAppend $canvas $id $geometry
}

# Scientific source leases remain internal to the native bridge. Scripts pass
# ordinary public scene/object IDs, never process addresses or borrowed arrays.
proc ::GX::native2DSpriteSceneAttach {canvas scene} {
    set n [native2DSpriteSceneCreate $canvas]
    ::GX::Native2D::core sprite_attach $scene $n
}
proc ::GX::native2DSpriteSceneSync {canvas scene descriptors {options {}}} {
    set n [native2DSpriteSceneCreate $canvas]
    return [::GX::Native2D::core sprite_sync $scene $n $descriptors $options]
}
proc ::GX::native2DSpriteSceneDetach {canvas} {set n [native2DSpriteSceneCreate $canvas];$n detach}
proc ::GX::native2DSpriteSceneDiagnostics {operation} {
    if {$operation ni {on off reset get}} {error {Use on, off, reset or get}}
    native2DEnsure;return [::gx::native2d::sprite_diagnostics $operation]
}
