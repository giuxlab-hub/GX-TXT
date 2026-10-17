# Optional broad ImageMagick adapter smoke (one small RGBA fixture for each enabled operation).
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
set magick [expr {[info exists ::env(GXTXT_TEST_MAGICK)] ? $::env(GXTXT_TEST_MAGICK) : [auto_execok magick]}]
if {$magick eq ""} {puts stderr {ImageMagick not available}; exit 77}
set ch [file tempfile work]; close $ch; file delete -- $work; file mkdir $work
set ::testMagick $magick
set ::testWork $work
namespace eval ::GX {
    proc runtimeToolRequired {name} {return $::testMagick}
    proc configurationTempDirectory {} {return $::testWork}
}
source [file join $root runtime catalog.tcl]
source [file join $root runtime engine.tcl]
set failed {}
set passed 0
try {
    exec $magick -size 68x52 xc:none -fill #3399DD88 -draw {rectangle 8,6 54,44} [file join $work rgba.png]
    dict for {id spec} $::GX::SII::catalog {
        if {[dict get $spec support] ne "executable"} continue
        set step [dict create op $id params {} scope all roi {}]
        if {[catch {::GX::SII::processFile [file join $work rgba.png] [list $step] [file join $work result.png] png16} err]} {
            lappend failed [list $id $err]
        } else {incr passed}
    }
    puts "Catalog executable operations passing: $passed"
    puts "Failures: [llength $failed]"
    foreach item $failed {puts "FAIL: $item"}
} finally {
    ::GX::SII::cleanTemps
    file delete -force -- $work
}
exit [expr {[llength $failed] == 0 ? 0 : 1}]
