# SPDX-License-Identifier: GPL-3.0-or-later
# Public logical series authority. Original objects remain independent;
# generated members belong to a parametric container, never to a static group.
proc ::GX::native2DSeriesParameters {parameters} {
    set p [dict merge {rows 2 columns 2 step_u {5 0} step_v {0 5} include_origin 0} $parameters]
    foreach key [dict keys $p] {if {$key ni {rows columns step_u step_v include_origin}} {error "Unknown rectangular series parameter: $key"}}
    foreach key {rows columns} {set n [dict get $p $key];if {![string is integer -strict $n]||$n<1||$n>10000} {error "Series $key must be an integer from 1 to 10000"}}
    if {[dict get $p rows]*[dict get $p columns]>10000} {error "Series limit is 10000 logical positions"}
    foreach key {step_u step_v} {
        if {[llength [dict get $p $key]]!=2} {error "Series $key requires two finite coordinates"}
        foreach v [dict get $p $key] {if {![string is double -strict $v]||!([expr {abs(double($v))}]<=1.7976931348623157e308)} {error "Series $key requires finite coordinates"}}
    }
    if {![string is boolean -strict [dict get $p include_origin]]} {error "include_origin must be boolean"}
    dict set p include_origin [expr {!![dict get $p include_origin]}]
    return $p
}
proc ::GX::native2DSeriesCompose {a b} {
    lassign $a a0 a1 a2 a3 a4 a5;lassign $b b0 b1 b2 b3 b4 b5
    return [list [expr {$a0*$b0+$a1*$b2}] [expr {$a0*$b1+$a1*$b3}] [expr {$a2*$b0+$a3*$b2}] [expr {$a2*$b1+$a3*$b3}] [expr {$a0*$b4+$a1*$b5+$a4}] [expr {$a2*$b4+$a3*$b5+$a5}]]
}
proc ::GX::native2DSeriesBuild {scene sources parameters {frame {1 0 0 1 0 0}}} {
    set p [native2DSeriesParameters $parameters]
    if {[llength $frame]!=6} {error "Series frame requires a six-number affine matrix"}
    if {[::GX::Native2D::core drag_active $scene]} {error "Finish the current Native2D gesture before updating a series"}
    set leaves {};set vertices 0
    foreach source $sources {
        if {[::GX::Native2D::core kind $scene $source] eq "group"} {set input [::GX::Native2D::core group_members $scene $source]} else {set input [list $source]}
        foreach member $input {if {$member ni $leaves} {lappend leaves $member;incr vertices [::GX::Native2D::core count $scene $member]}}
    }
    if {$leaves eq {}} {error "Choose at least one series source"}
    set positions [expr {[dict get $p rows]*[dict get $p columns]-![dict get $p include_origin]}]
    if {$positions*[llength $leaves]>10000||$positions*$vertices>8000000} {error "Series exceeds 10000 objects or 8000000 complete vertices"}
    set created {};set parents {};set indices {};set cells {}
    lassign [dict get $p step_u] ux uy;lassign [dict get $p step_v] vx vy
    try {
        for {set v 0} {$v<[dict get $p rows]} {incr v} {
            for {set u 0} {$u<[dict get $p columns]} {incr u} {
                if {!$u&&!$v&&![dict get $p include_origin]} {dict set cells "$u,$v" {};continue}
                set matrix [native2DSeriesCompose $frame [list 1 0 0 1 [expr {$u*$ux+$v*$vx}] [expr {$u*$uy+$v*$vy}]]]
                set receipt [::GX::Native2D::core affine $scene $leaves $matrix 1]
                set ids [dict get $receipt object_ids];set created [concat $created $ids];set parents [concat $parents [dict get $receipt source_ids]]
                foreach id $ids {lappend indices [list $u $v]}
                dict set cells "$u,$v" $ids
            }
        }
    } on error {message options} {
        foreach id $created {::GX::Native2D::core delete $scene $id}
        return -options $options $message
    }
    return [dict create parameters $p frame $frame object_ids $created source_ids $parents logical_indices $indices cells $cells originals_preserved 1 origin_policy [expr {[dict get $p include_origin] ? "generated_copy" : "omitted_independent_original"}]]
}
proc ::GX::native2DSeriesRescaleRecord {record factor} {
    foreach key {step_u step_v} {dict set record parameters $key [lmap n [dict get $record parameters $key] {expr {$n*$factor}}]}
    set frame [dict get $record frame];lset frame 4 [expr {[lindex $frame 4]*$factor}];lset frame 5 [expr {[lindex $frame 5]*$factor}];dict set record frame $frame
    return $record
}
