# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set out [file normalize $out]
if {![string match */_private_dev108/icon-theme* $out] || [file exists $out]} {error {Requires new private icon theme evidence}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev108_icon_theme_contract__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
wm withdraw .
set asset [::GX::viewerGuiIconImport [file join $root core assets icons play.svg] Play Controls GPL-3.0-or-later]
ttk::button .sample -text {Native icon style}
::GX::uiFieldIconApply .sample {icon_spacing 12} $asset
set ::themeEvents 0
proc themeEventTrace {args} {incr ::themeEvents}
trace add execution ::GX::_uiFieldIconThemeChanged enter themeEventTrace
after 5000 {error {Theme event loop did not settle};exit 1}
ttk::style theme use clam
after 500 {
    set gap [ttk::style lookup [.sample cget -style] -space]
    set f [open [file join $::out result.tcldict] w];puts $f [dict create theme clam gap $gap events $::themeEvents];close $f
    if {$gap!=12 || $::themeEvents>100} {puts stderr {FAIL native icon theme handling};exit 1}
    puts {PASS bounded native icon theme refresh and preserved relative gap};exit 0
}
vwait forever
