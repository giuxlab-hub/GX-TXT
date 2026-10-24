# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::P017Manual {variable checks {};variable input {};variable counts {};variable traced {};variable background {}}
proc ::P017Manual::emit {name value} {set f [open [file join $::out $name.tcldict] w];try {fconfigure $f -encoding utf-8;puts $f $value} finally {close $f}}
proc ::P017Manual::check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL: $label"};lappend ::P017Manual::checks $label;emit checks $::P017Manual::checks;puts "PASS: $label";flush stdout}
proc ::P017Manual::pause {{ms 90}} {set token ::P017Manual::tick[incr ::P017Manual::serial];set $token 0;after $ms [list set $token 1];vwait $token;unset $token;update idletasks}
set ::P017Manual::serial 0
proc ::P017Manual::activate {widget} {update;set w [winfo toplevel $widget];wm deiconify $w;raise $w;exec xdotool windowraise [winfo id $w] windowfocus --sync [winfo id $w];pause 40}
proc ::P017Manual::point {widget x y} {exec xdotool mousemove --sync [expr {[winfo rootx $widget]+int($x)}] [expr {[winfo rooty $widget]+int($y)}]}
proc ::P017Manual::click {widget {x {}} {y {}}} {activate $widget;if {![winfo ismapped $widget]} {error "Input target not mapped: $widget"};if {$x eq {}} {set x [expr {[winfo width $widget]/2}];set y [expr {[winfo height $widget]/2}]};lappend ::P017Manual::input [list click $widget $x $y];point $widget $x $y;exec xdotool click 1;pause}
proc ::P017Manual::key {keys} {lappend ::P017Manual::input [list key $keys];exec xdotool key --clearmodifiers $keys;pause}
proc ::P017Manual::type {text} {lappend ::P017Manual::input [list type $text];exec xdotool type --clearmodifiers --delay 1 -- $text;pause 35}
proc ::P017Manual::shot {name widget} {update;exec timeout 10 import -window [winfo id $widget] [file join $::out $name.png]}
proc ::P017Manual::waitFor {condition label {seconds 25}} {set deadline [expr {[clock milliseconds]+1000*$seconds}];while {![uplevel 1 [list expr $condition]]} {if {[clock milliseconds]>$deadline} {error "Timed out: $label"};pause 70};update}
proc ::P017Manual::menu {button label} {
    click $button;set m [$button cget -menu];check {[winfo ismapped $m]} "Menu mapped: $button"
    set found -1
    for {set i 0} {$i<=[$m index end]} {incr i} {if {[$m type $i] ni {tearoff separator} && [$m entrycget $i -label] eq $label} {set found $i;break}}
    if {$found<0} {error "Missing menu action '$label' in $m"}
    if {[$m entrycget $found -state] eq {disabled}} {error "Disabled menu action '$label'"}
    set next [expr {$found==[$m index end] ? [winfo height $m] : [$m yposition [expr {$found+1}]]}]
    point $m [expr {min(90,[winfo width $m]-8)}] [expr {([$m yposition $found]+$next)/2}]
    lappend ::P017Manual::input [list menu $button $label]
    exec xdotool click 1;pause
}
proc ::P017Manual::combo {widget index} {activate $widget;focus -force $widget;point $widget [expr {[winfo width $widget]-8}] [expr {[winfo height $widget]/2}];exec xdotool click 1;pause;key Home;for {set i 0} {$i<$index} {incr i} {key Down};key Return}
proc ::P017Manual::traceCall {name command operation} {
    if {$name eq {native}} {set name native:[lindex $command 1];if {$name ni {native:record native:flush native:checkpoint}} return}
    dict incr ::P017Manual::counts $name
    if {$name in {native:record native:flush}} {
        set chain {}
        for {set i 1} {$i<[info level] && $i<=30} {incr i} {lappend chain [lindex [info level -$i] 0]}
        lappend ::P017Manual::auditCallers [list $name $chain]
    }
}
proc ::P017Manual::auditStart {} {
    set ::P017Manual::counts [dict create public_record 0 native:record 0 native:flush 0 native:checkpoint 0 document_update 0 document_payload_write 0]
    set ::P017Manual::traced {};set ::P017Manual::auditCallers {}
    foreach {name label} {::GX::scientificHistoryViewerRecord public_record ::GX::historyNative native ::GX::interactiveDocumentUpdate document_update ::GX::_interactiveDocumentWritePayload document_payload_write} {
        trace add execution $name enter [list ::P017Manual::traceCall $label];lappend ::P017Manual::traced [list $name $label]
    }
}
proc ::P017Manual::auditEnd {label} {
    foreach pair $::P017Manual::traced {lassign $pair name tag;trace remove execution $name enter [list ::P017Manual::traceCall $tag]}
    set ::P017Manual::traced {};emit audit_$label $::P017Manual::counts;emit audit_callers_$label $::P017Manual::auditCallers
    check {[dict get $::P017Manual::counts public_record]==0 && [dict get $::P017Manual::counts native:record]==0} "$label ordinary edits/navigation do not export accumulated History"
    check {[dict get $::P017Manual::counts document_update]==0 && [dict get $::P017Manual::counts document_payload_write]==0} "$label ordinary edits/navigation do not synchronously project Document"
    check {[dict get $::P017Manual::counts native:flush]==0 && [dict get $::P017Manual::counts native:checkpoint]==0} "$label ordinary edits/navigation do not wait for persistence"
}
proc ::P017Manual::durable {w} {set s [::GX::scientificHistoryViewerStatus $w];check {![dict get $s failed] && [dict get $s durable_revision]==[dict get $s accepted_revision] && [dict get $s pending]==0} {Explicit Save reaches verified native durable revision};return $s}
proc ::P017Manual::publish {} {
    ::GX::datasetPublicationV2PublishSeries $::GX::currentSession math.numeric [dict create dataset_id qa_history_source contract table.generic storage csv x_values {0 1 2 3 4 5 6 7} y_values {1 3 5 7 9 11 13 15} x_variable {variable_id source_x unit s} y_variable {variable_id source_y unit V}]
    return [dict get [::GX::sessionInspectionDatasetPayload qa_history_source] sha256]
}
