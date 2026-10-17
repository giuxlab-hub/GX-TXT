# SPDX-License-Identifier: GPL-3.0-or-later
# Native2D owns device drawing, scrolling and input. Consumers own scientific
# cells and validate their live Session/document revision on every bounded fetch.
proc ::GX::native2DVirtualGridCreate {path options} {
    native2DEnsure
    if {![llength [info commands ::gx::native2d::grid]]} {error {The installed Native2D adapter has no virtual-grid capability}}
    if {[catch {dict size $options}]} {error {Native grid options must be a dictionary}}
    return [::gx::native2d::grid $path {*}$options]
}
proc ::GX::native2DDeviceSurfaceCreate {path} {
    native2DEnsure
    return [::gx::native2d::surface $path]
}
