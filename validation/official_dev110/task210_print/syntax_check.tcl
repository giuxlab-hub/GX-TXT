# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=1 || [file tail [lindex $argv 0]] ne [lindex $argv 0]} {error {Pass one helper basename}}
set path [file join [file dirname [info script]] [lindex $argv 0]]
set f [open $path r];try {set code [read $f]} finally {close $f}
if {![info complete $code]} {error {Incomplete Tcl source}}
puts "SYNTAX_COMPLETE [file tail $path]; GUI NOT EXECUTED"
