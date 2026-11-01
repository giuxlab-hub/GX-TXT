# SPDX-License-Identifier: GPL-3.0-or-later
# Public host adapter: the native object owns all presentation resources.
namespace eval ::GX::Native2DGridPresenter {variable hosts {}}
proc ::GX::native2DGridPresenterApiInfo {} {
    return [dict create api_id NATIVE2D_GRID_PRESENTER_API_v1 api_version 1 host_only 1 operations {native2DGridPresenterCreate native2DGridPresenterBegin native2DGridPresenterUpdate native2DGridPresenterConfigure native2DGridPresenterInvalidate native2DGridPresenterDescribe native2DGridPresenterPosition native2DGridPresenterControls native2DGridPresenterEnd native2DGridPresenterDispose}]
}
proc ::GX::native2DGridPresenterCreate {canvas {changed __keep__}} {
    variable ::GX::Native2DGridPresenter::hosts
    if {![winfo exists $canvas] || [winfo class $canvas] ne {Canvas}} {error {Native grid presenter requires an existing Canvas}}
    if {![dict exists $hosts $canvas]} {
        native2DEnsure
        set native [::gx::native2d::grid_presenter $canvas]
        set sub [configurationSubscribe [list ::GX::_native2DGridConfiguration $canvas]]
        dict set hosts $canvas [dict create native $native subscription $sub changed {}]
        bind $canvas <Destroy> +[list ::GX::_native2DGridDestroyed $canvas %W]
    }
    if {$changed ne {__keep__}} {llength $changed;dict set hosts $canvas changed $changed}
    return [dict get $hosts $canvas native]
}
proc ::GX::native2DGridPresenterBegin {canvas {changed __keep__}} {
    set native [native2DGridPresenterCreate $canvas $changed]
    $native begin
}
proc ::GX::native2DGridPresenterUpdate {canvas scene plans {options {}}} {
    set native [native2DGridPresenterCreate $canvas]
    foreach key [dict keys $options] {if {$key ni {background text_color font}} {error "Unknown grid presentation option '$key'"}}
    set background [uiFieldColorComposite [uiFieldColorFromRGBA [::GX::Native2D::core background $scene]] #FFFFFF]
    set data [dict merge [dict create background [dict get $background rgb] text_color [uiFieldColorReadableText $background] font TkSmallCaptionFont] $options]
    set font [dict get $data font]
    dict set data font_signature [list [font actual $font] [font metrics $font]]
    dict set data text_rgba [uiFieldColorToRGBA [dict create rgb [dict get $data text_color] alpha 1]]
    dict set data adaptive_density [configurationGet ui.adaptive_grid_density]
    dict set data plans $plans
    ::GX::Native2D::core grid_presenter_update $scene $native $data
}
proc ::GX::native2DGridPresenterConfigure {canvas density} {
    set native [native2DGridPresenterCreate $canvas];$native configure $density
    native2DGridPresenterInvalidate $canvas
}
proc ::GX::native2DGridPresenterInvalidate {canvas} {
    variable ::GX::Native2DGridPresenter::hosts
    if {![dict exists $hosts $canvas]} return
    set native [dict get $hosts $canvas native]
    if {[llength [info commands $native]]} {$native invalidate}
    set changed [dict get $hosts $canvas changed]
    if {$changed ne {} && [winfo exists $canvas]} {uplevel #0 $changed}
}
proc ::GX::_native2DGridConfiguration {canvas id} {
    if {$id eq {ui.adaptive_grid_density}} {native2DGridPresenterInvalidate $canvas}
}
proc ::GX::native2DGridPresenterDescribe {canvas} {set native [native2DGridPresenterCreate $canvas];return [$native describe]}
proc ::GX::native2DGridPresenterPosition {canvas updates} {set native [native2DGridPresenterCreate $canvas];$native position $updates}
proc ::GX::_native2DGridDestroyed {canvas widget} {if {$widget eq $canvas} {native2DGridPresenterDispose $canvas}}
proc ::GX::native2DGridPresenterDispose {canvas} {
    variable ::GX::Native2DGridPresenter::hosts
    if {![dict exists $hosts $canvas]} return
    set owner [dict get $hosts $canvas];dict unset hosts $canvas
    configurationUnsubscribe [dict get $owner subscription]
    set native [dict get $owner native]
    if {[llength [info commands $native]]} {$native destroy}
}

proc ::GX::native2DGridPresenterEnd {canvas} {set native [native2DGridPresenterCreate $canvas];$native end}
proc ::GX::native2DGridPresenterControls {canvas scene object selected color} {
    set native [native2DGridPresenterCreate $canvas]
    ::GX::Native2D::core grid_presenter_controls $scene $native $object $selected $color
}
