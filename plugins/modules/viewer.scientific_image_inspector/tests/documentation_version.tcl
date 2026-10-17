# Documentation and release-descriptor consistency checks.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
proc readText {name} {
    global root
    set ch [open [file join $root $name] r]
    fconfigure $ch -encoding utf-8
    try {return [read $ch]} finally {close $ch}
}
proc requiredLine {file pattern} {
    set value [readText $file]
    if {![regexp -line -- $pattern $value -> found]} {
        error "$file: expected declaration matching '$pattern'"
    }
    return $found
}
set moduleVersion [requiredLine module.ini {^version=([0-9]+\.[0-9]+\.[0-9]+)$}]
set packageVersion [requiredLine plugin-package.ini {^version=([0-9]+\.[0-9]+\.[0-9]+)$}]
set runtimeVersion [requiredLine api/scientific_image_inspector_api_v1.tcl {^\s+variable version ([0-9]+\.[0-9]+\.[0-9]+)$}]
if {$moduleVersion ne $packageVersion || $moduleVersion ne $runtimeVersion} {
    error "Version mismatch: module=$moduleVersion package=$packageVersion api=$runtimeVersion"
}
if {[string first {guide=MANUAL.md} [readText module.ini]] < 0} {
    error {Module documentation descriptor must point at MANUAL.md}
}
if {[string first "Version $moduleVersion" [readText tests/gui_smoke.tcl]] < 0} {
    error "About GUI smoke test does not expect $moduleVersion"
}
set manual [readText MANUAL.md]
foreach section {{Five-minute start} {Basic Editor and all 15 task presets} {Advanced Editor and the operation catalog} {Select a pixel ROI and use its context menu} {Create and edit annotations} {Figure Studio: multi-panel compositions} {Session Workspaces and persistence} {Publish a derived image Dataset and inspect its manifest} {Scientific integrity, limitations and security}} {
    if {[string first $section $manual]<0} {error "Manual misses required topic: $section"}
}
if {[string first {Operations → Advanced operation catalog} $manual]>=0} {
    error {Manual describes removed top-level Operations menu}
}
if {[string first {Save user defaults} $manual]>=0} {
    error {Manual describes removed sidebar Save user defaults command}
}
# Confirm presets documented using the *current executable catalog*, not a
# stale list copied from a historical release. GUI code only declares procs.
source [file join $root runtime catalog.tcl]
source [file join $root runtime article_gui.tcl]
set presets [::GX::SII::basicPresetCatalog]
if {[llength $presets]!=15} {error "Expected exactly 15 current presets, got [llength $presets]"}
foreach preset $presets {
    set title [lindex $preset 0]
    if {[string first $title $manual]<0} {
        # Markdown tables escape their literal separator between task and name.
        set escaped [string map {| {\|}} $title]
        if {[string first $escaped $manual]<0} {error "Manual misses current preset: $title"}
    }
}
set specs [::GX::SII::catalogList]
if {[llength $specs] != 69} {error "Expected catalog with 69 entries, got [llength $specs]"}
foreach support {executable recognized disabled} count {46 17 6} {
    set found [llength [lsearch -all -inline -exact [lmap spec $specs {dict get $spec support}] $support]]
    if {$found!=$count} {error "Catalog $support count $found differs from documented $count"}
}
# A historical dead GUI Export callback contradicted Dataset-only delivery.
if {[string first {$f.buttons.export} [readText runtime/gui.tcl]] >= 0} {
    error {Dead technical-report Export control returned}
}
puts "PASS documentation + current catalog/preset coverage + release consistency: $moduleVersion"
