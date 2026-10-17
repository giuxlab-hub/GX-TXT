# Headless local Tk smoke with mocks; no real GX-TXT integration.
# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] test_isolated.tcl]
proc ::GX::sessionInspectionCurrentSession {} {return /isolated-fake-session}
proc ::GX::interactiveDocumentSessionToken {} {return fake-token}
namespace eval ::GX::PlotDatasetAPIv3 {}
proc ::GX::PlotDatasetAPIv3::requireCapability {cap} {
    if {$cap ne "transient_2d_curves"} {error "Wrong plotting capability"}
}
proc ::GX::PlotDatasetAPIv3::renderTransientCurves2D {x series title directory xunit} {
    package require Tk
    set path [file join $directory graph.png]
    set photo [image create photo -width 650 -height 360]
    $photo put #ffffff -to 0 0 650 360
    $photo put #dedede -to 20 20 640 340
    $photo write $path -format png
    image delete $photo
    return [dict create artifact $path]
}
package require Tk
set w [::GX::MathematicsExplorer::open]
update
if {![winfo exists $w.left.functions.f3.expr]} {error "Missing function expression editor"}
::GX::MathematicsExplorer::_uiPlot $w
if {$::GX::MathematicsExplorer::ui($w,computed) eq ""} {
    error "Mock GUI plotting failed: $::GX::MathematicsExplorer::ui($w,status)"
}
if {$::GX::MathematicsExplorer::ui($w,photo) eq ""} {error "Plot PNG was not loaded"}
::GX::MathematicsExplorer::_uiIntegral $w
if {![string match {*42*} $::GX::MathematicsExplorer::ui($w,integral)]} {error "Integral display missing"}
::GX::MathematicsExplorer::_uiClose $w
puts "ISOLATED Tk SMOKE: PASS (virtual display, fake rendering; NOT GX-TXT integration)"
exit 0
