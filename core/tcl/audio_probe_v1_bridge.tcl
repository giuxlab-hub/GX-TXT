#!/usr/bin/env tclsh
set root [file normalize [file join [file dirname [info script]] .. ..]]
set argv0 __not_main__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
lassign $argv path stream inputFormat sampleRate channels
set options [dict create]
foreach {key value} [list input_format $inputFormat sample_rate $sampleRate channels $channels] {
    if {[string trim $value] ne ""} { dict set options $key $value }
}
if {[catch {set metadata [::GX::audioProbe $path $stream $options]} error]} {
    puts "ERROR\t[::GX::datasetB64Encode $error]"
    exit 2
}
puts "PROBE\t[::GX::datasetB64Encode $metadata]"
