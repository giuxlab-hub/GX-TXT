set ::env(GXTXT_PREVIEW_TEST_LEGACY) 1
# SPDX-License-Identifier: GPL-3.0-or-later
# Actual Tk public UI Field components and pack layout on an isolated X server.
# No GX-TXT Session or installation is used.
package require Tk
if {![info exists ::env(GXTXT_FRAMEWORK_ROOT)]} {error {Set GXTXT_FRAMEWORK_ROOT}}
namespace eval ::GX {}
namespace eval ::GX::UiField {variable componentTableFonts {}}
proc ::GX::datasetPublicationV2DictDefault {d k fallback} {
    if {[dict exists $d $k]} {return [dict get $d $k]}
    return $fallback
}
proc ::GX::uiFieldSelectorWithinViewer {args} {}
source [file join $::env(GXTXT_FRAMEWORK_ROOT) core tcl ui_field_viewer_regions_v1.tcl]
set file [file join [file dirname [info script]] .. gui table_design.tcldict]
set fd [open $file rb]
set design [encoding convertfrom utf-8 [read $fd]]
close $fd
set widgets {}
set components {}
foreach c [dict get $design components] {
    if {[dict get $c parent] eq {toolbar}} {lappend components $c}
}
set expected {first previous next toolbar_spacer precision_label precision}
set actual [lmap c $components {dict get $c id}]
if {$actual ne $expected} {error "Incorrect toolbar order: $actual"}
foreach c $components {
    if {[dict get $c layout manager] ne {pack}} {error {Toolbar must use compact pack layout}}
}
wm title . {Preview 0.1.8 compact toolbar — isolated native Tk test}
wm geometry . 1250x490+50+50
ttk::frame .toolbar
pack .toolbar -side top -fill x
ttk::frame .content
pack .content -fill both -expand 1
ttk::notebook .content.tabs
pack .content.tabs -fill both -expand 1
ttk::frame .content.tabs.scientific
.content.tabs add .content.tabs.scientific -text {Scientific values}
ttk::frame .content.tabs.trace
.content.tabs add .content.tabs.trace -text {Point traceability}
ttk::treeview .content.tabs.scientific.table -show headings -columns {{Row} {Curve} {Point} {X (physical)} {Y (physical)} {Axis}}
pack .content.tabs.scientific.table -fill both -expand 1
foreach name [.content.tabs.scientific.table cget -columns] {
    .content.tabs.scientific.table heading $name -text $name
}
foreach i {1 2 3 4 5} {
    .content.tabs.scientific.table insert {} end -values [list $i Gain [expr {$i-1}] [expr {100*$i}] [expr {-0.12*$i}] Y1]
}
set ::GX::UiField::widgets {}
foreach c $components {
    set id [dict get $c id]
    set type [dict get $c type]
    set props [dict get $c properties]
    set varName "::control_$id"
    set $varName [::GX::datasetPublicationV2DictDefault $props default {}]
    set w .toolbar.$id
    ::GX::uiFieldComponentCreate $w $type $props $varName [list ::test_callback $id]
    ::GX::uiFieldComponentLayout $w .toolbar [dict get $c layout]
    dict set widgets $id $w
}
proc ::test_callback {args} {}
update
set panelWidth [winfo width .toolbar]
set buttonWidths {}
foreach id {first previous next} {lappend buttonWidths [winfo width [dict get $widgets $id]]}
set precisionWidth [winfo width [dict get $widgets precision]]
set toolbarHeight [winfo height .toolbar]
set spacerWidth [winfo width [dict get $widgets toolbar_spacer]]
puts "GEOMETRY toolbar=${panelWidth}x${toolbarHeight} buttons=$buttonWidths precision=$precisionWidth spacer=$spacerWidth"
foreach w $buttonWidths {
    if {$w>125 || $w<35} {error "Button unreasonably wide: $w"}
}
if {$precisionWidth>180 || $precisionWidth<60} {error "Precision selector unreasonably wide: $precisionWidth"}
if {$spacerWidth<100} {error "Missing flexible spacer: $spacerWidth"}
if {$toolbarHeight>65} {error "Toolbar excessively tall: $toolbarHeight"}
if {[winfo exists .toolbar.precision.reset]} {error {The old Reset button still exists}}
set choice [dict get $widgets precision]
if {[$choice cget -values] ne {{6 digits} {10 digits} {Full precision}}} {
    error {Precision choices changed}
}
if {[info exists ::env(GXTXT_COMPACT_SCREENSHOT)] && $::env(GXTXT_COMPACT_SCREENSHOT) ne {}} {
    update
    exec import -window root $::env(GXTXT_COMPACT_SCREENSHOT)
}
puts "PASS 0.1.8 native Tk compact toolbar, real UIField layout, short controls, preserved table."
destroy .
