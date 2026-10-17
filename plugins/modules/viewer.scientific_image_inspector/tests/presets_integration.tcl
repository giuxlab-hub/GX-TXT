# Basic Editor presets must be validated through the same ImageMagick CORE-aware adapter.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
set magick [expr {[info exists ::env(GXTXT_TEST_MAGICK)] ? $::env(GXTXT_TEST_MAGICK) : [auto_execok magick]}]
if {$magick eq {}} {puts {SKIP: ImageMagick unavailable}; exit 77}
set ch [file tempfile tmp]; close $ch;file delete $tmp;file mkdir $tmp
set ::testMagick $magick
set ::testDir $tmp
namespace eval ::GX {
    proc runtimeToolRequired {name} {return $::testMagick}
    proc configurationTempDirectory {} {return $::testDir}
}
source [file join $root runtime catalog.tcl]
source [file join $root runtime engine.tcl]
source [file join $root runtime article_gui.tcl]
set status 0
try {
    set fixture [file join $tmp colors.png]
    exec $magick -size 80x64 gradient:red-blue -depth 16 $fixture
    set initial [lindex [exec sha256sum -- $fixture] 0]
    set presets [::GX::SII::basicPresetCatalog]
    if {[llength $presets] < 12} {error {Too few task-specific presets}}
    set names {}
    set images {}
    foreach item $presets {
        lassign $item title about steps
        if {$title in $names} {error "Duplicate preset name $title"}
        lappend names $title
        if {$about eq {} || ![llength $steps]} {error "Unexplained or empty preset $title"}
        set recipe {}
        foreach item $steps {
            lassign $item op params
            if {[dict get [::GX::SII::operationStatus $op] state] ne {executable}} {error "Unsupported preset operation $op in $title"}
            lappend recipe [dict create op $op params $params scope all roi {}]
        }
        set validated [::GX::SII::validateSteps $recipe]
        set dest [file join $tmp "preset-[llength $images].png"]
        if {[catch {::GX::SII::processFile $fixture $validated $dest png16} message]} {
            error "Preset $title failed processing: $message"
        }
        if {![file isfile $dest] || [file size $dest] == 0} {error "No output from $title"}
        lappend images $dest
        puts "PASS: $title"
    }
    if {$initial ne [lindex [exec sha256sum -- $fixture] 0]} {error {Preset execution overwrote its source image}}
    # A contrast operation, an edge detector, and an invert operation
    # must not resolve to identical pixel output.
    set different 0
    set seen {}
    foreach file $images {
        set sum [lindex [exec sha256sum -- $file] 0]
        if {$sum ni $seen} {lappend seen $sum}
    }
    if {[llength $seen] < 7} {error "Presets did not produce enough meaningfully distinct outputs: [llength $seen]"}
    puts "PRESET TESTS PASSED: [llength $presets] distinct descriptive entries, [llength $seen] different results"
} on error {message opts} {
    puts stderr "PRESET TESTS FAILED: $message\n[dict get $opts -errorinfo]"
    set status 1
} finally {
    ::GX::SII::cleanTemps
    file delete -force $tmp
}
exit $status
