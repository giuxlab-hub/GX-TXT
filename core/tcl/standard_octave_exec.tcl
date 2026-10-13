#!/usr/bin/env tclsh
# GX-TXT Standard Module API v1 - standard Octave process/output-contract wrapper
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it

proc usage {} {
    puts stderr "usage: standard_octave_exec.tcl --output-dir DIR --expected 'a;b;...' -- command args..."
    exit 2
}

set outputDir ""
set expected ""
set stampPath ""
set stampValue ""
set child {}
set i 0
while {$i < [llength $argv]} {
    set a [lindex $argv $i]
    if {$a eq "--"} {
        set child [lrange $argv [expr {$i+1}] end]
        break
    }
    if {$a eq "--output-dir"} {
        incr i; if {$i >= [llength $argv]} usage
        set outputDir [lindex $argv $i]
    } elseif {$a eq "--expected"} {
        incr i; if {$i >= [llength $argv]} usage
        set expected [lindex $argv $i]
    } elseif {$a eq "--stamp"} {
        incr i; if {$i >= [llength $argv]} usage
        set stampPath [lindex $argv $i]
        incr i; if {$i >= [llength $argv]} usage
        set stampValue [lindex $argv $i]
    } else {
        usage
    }
    incr i
}
if {$outputDir eq "" || [llength $child] == 0} usage

set pipeline [concat | $child [list 2>@1]]
if {[catch {set p [open $pipeline r]} err]} {
    puts stderr "standard_octave: cannot start child: $err"
    exit 1
}
fconfigure $p -encoding utf-8 -translation auto -buffering line
while {[gets $p line] >= 0} {
    puts $line
    flush stdout
}
if {[catch {close $p} err opts]} {
    puts stderr "standard_octave: Octave process failed: $err"
    exit 1
}

set missing {}
foreach rel [split $expected ";"] {
    set rel [string trim $rel]
    if {$rel eq ""} continue
    # Output contracts are relative file paths, never arbitrary absolute paths.
    if {[file pathtype $rel] eq "absolute" || [string first ".." [file split $rel]] >= 0} {
        puts stderr "standard_octave: invalid output contract path: $rel"
        exit 1
    }
    set pth [file join $outputDir $rel]
    if {![file isfile $pth]} { lappend missing $rel }
}
if {[llength $missing]} {
    puts stderr "standard_octave: module exited without required output(s): [join $missing {, }]"
    exit 1
}
if {$stampPath ne ""} {
    set root [file normalize $outputDir]
    set target [file normalize $stampPath]
    if {[string first "$root/" "$target/"] != 0} { puts stderr "standard_octave: stamp must be inside output directory"; exit 1 }
    set sf [open $target w]; puts $sf $stampValue; close $sf
}
puts "standard_octave: output contract satisfied ([llength [split $expected {;}]] declared files)."
exit 0
