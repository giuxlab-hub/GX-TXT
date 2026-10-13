# SPDX-License-Identifier: GPL-3.0-or-later
# Work is scheduled at bounded chunk boundaries, with no GUI polling timer.
namespace eval ::GX::CurveSource {variable jobs {};variable jobSerial 0;variable waits;array set waits {}}
proc ::GX::curveSourceCooperativeBoundary {progress receipt} {
    # One yield at a completed bounded transaction, with cancellation checked
    # on both sides. No repeated timer or nested Native callback is involved.
    variable ::GX::CurveSource::waits;variable ::GX::CurveSource::jobSerial
    uplevel #0 [list {*}$progress $receipt]
    set key "curve-source-boundary#[pid]-[incr jobSerial]"
    set pending [after 0 [list ::GX::_curveSourceWaitDone $key ready]]
    try {
        vwait ::GX::CurveSource::waits($key)
        uplevel #0 [list {*}$progress $receipt]
    } finally {after cancel $pending;unset -nocomplain waits($key)}
}
proc ::GX::curveSourceDisplayAsync {source completed {progress ""}} {
    variable ::GX::CurveSource::jobs;variable ::GX::CurveSource::jobSerial
    set record [_curveSourceRequire $source];set request [dict get $record request]
    native2DEnsure
    set scene "";set stream ""
    try {
        if {[dict get $record display] eq {}} {
            set scene [::GX::Native2D::core scene]
            set variables [list [dict get $request x_variable_id] [dict get $request y_variable_id]]
            if {[dict get $record lineage_variable] ne ""} {lappend variables [dict get $record lineage_variable]}
            # GUI work boundaries must be short even for value-based providers.
            # The Native accumulator still owns one complete ordered sampling
            # pass; changing stream chunks cannot change its extrema/row policy.
            set stream [curveSourceOpenStream $source $variables 4096]
            ::GX::Native2D::core sample_begin $scene [dict get $record row_count] [dict get $request display_budget] [expr {[dict get $record lineage_variable] eq "" ? [dict get $request start] : 0}]
        }
        set token "curve-source-job#[pid]-[incr jobSerial]"
        dict set jobs $token [dict create source $source scene $scene stream $stream record $record completed $completed progress $progress position 0 pending "" cached [dict get $record display]]
        dict set jobs $token pending [after 0 [list ::GX::_curveSourceAsyncStep $token]]
        set scene "";set stream "";return $token
    } finally {
        if {$stream ne ""} {curveSourceCloseStream $source $stream}
        if {$scene ne ""} {::GX::Native2D::core destroy $scene}
    }
}
proc ::GX::_curveSourceAsyncFinish {token result} {
    variable ::GX::CurveSource::jobs
    if {![dict exists $jobs $token]} return
    set job [dict get $jobs $token]
    dict unset jobs $token
    if {[dict get $job pending] ne ""} {after cancel [dict get $job pending]}
    if {[dict get $job stream] ne ""} {curveSourceCloseStream [dict get $job source] [dict get $job stream]}
    if {[dict get $job scene] ne ""} {::GX::Native2D::core destroy [dict get $job scene]}
    dict set result job_id $token
    uplevel #0 [list {*}[dict get $job completed] $result]
}
proc ::GX::curveSourceCancel {token} {
    variable ::GX::CurveSource::jobs
    if {![dict exists $jobs $token]} {error "Unknown or completed Curve Source job"}
    _curveSourceAsyncFinish $token [dict create status cancelled]
}
proc ::GX::_curveSourceWaitDone {key result} {variable ::GX::CurveSource::waits;set waits($key) $result}
proc ::GX::curveSourceDisplayResponsive {source {progress ""}} {
    # Host-only synchronous return contract with a cooperative event loop.
    # Reuses the same cancellable bounded display job; no nested source reader.
    variable ::GX::CurveSource::waits;variable ::GX::CurveSource::jobSerial
    set key "curve-source-wait#[pid]-[incr jobSerial]";set job ""
    try {
        set job [curveSourceDisplayAsync $source [list ::GX::_curveSourceWaitDone $key] $progress]
        vwait ::GX::CurveSource::waits($key)
        set result $waits($key);set job ""
        switch -- [dict get $result status] {
            ok {return [dict get $result display]}
            cancelled {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} "Curve loading cancelled"}
            error {return -code error -errorcode [dict get $result error_code] [dict get $result message]}
            default {error "Invalid Curve Source completion"}
        }
    } finally {
        if {$job ne ""} {curveSourceCancel $job}
        unset -nocomplain waits($key)
    }
}
proc ::GX::_curveSourceAsyncStep {token} {
    variable ::GX::CurveSource::jobs;variable ::GX::CurveSource::records
    if {![dict exists $jobs $token]} return
    dict set jobs $token pending ""
    set job [dict get $jobs $token];set source [dict get $job source]
    if {[catch {
        set record [_curveSourceRequire $source]
        if {[dict get $job cached] ne {}} {_curveSourceAsyncFinish $token [dict create status ok display [dict get $job cached]];return}
        if {[dict exists $job continuity]} {
            set continuation [_curveSourceContinuityStep [dict get $job continuity]]
            dict set job continuity $continuation
            if {[dict get $continuation done]} {
                set result [dict get $continuation display]
                dict set records($source) display $result
                _curveSourceAsyncFinish $token [dict create status ok display $result]
            } else {
                dict set job pending [after 0 [list ::GX::_curveSourceAsyncStep $token]]
                dict set jobs $token $job
            }
            return
        }
        set chunk [tableStreamNext [dict get $job stream]];set columns [dict get $chunk columns]
        set x [_curveSourceNativeColumn [lindex $columns 0]];set y [_curveSourceNativeColumn [lindex $columns 1]]
        if {[dict get $record lineage_variable] eq ""} {::GX::Native2D::core sample_push [dict get $job scene] [dict get $job position] $x $y} else {::GX::Native2D::core sample_push [dict get $job scene] [dict get $job position] $x $y [_curveSourceNativeColumn [lindex $columns 2]]]}
        dict incr job position [dict get $chunk row_count]
        dict set jobs $token $job
        if {[dict get $job progress] ne ""} {uplevel #0 [list {*}[dict get $job progress] [dict create job_id $token completed_rows [dict get $job position] total_rows [dict get $record row_count]]]}
        if {![dict exists $jobs $token]} return
        if {[dict get $chunk eof]} {
            set diagnostics [tableStreamDiagnostics [dict get $job stream]]
            set sampled [::GX::Native2D::core sample_finish [dict get $job scene]]
            set points [::GX::Native2D::core points [dict get $job scene] [dict get $sampled object]]
            set result [dict merge [dict remove $sampled object] [dict create points $points source_id [dict get $record source_id] row_count [dict get $record row_count] reduced [expr {[dict get $sampled display_rows]<[dict get $sampled finite_rows]}] display_is_scientific_data 0 diagnostics $diagnostics]]
            _curveSourceRequire $source
            set continuity [_curveSourceContinuityBegin $source $result]
            if {$continuity ne {}} {
                curveSourceCloseStream $source [dict get $job stream]
                dict set job stream [dict get $continuity stream]
                dict set job continuity $continuity
                dict set job pending [after 0 [list ::GX::_curveSourceAsyncStep $token]]
                dict set jobs $token $job
            } else {
                dict set records($source) display $result
                _curveSourceAsyncFinish $token [dict create status ok display $result]
            }
        } else {dict set jobs $token pending [after 0 [list ::GX::_curveSourceAsyncStep $token]]}
    } message options]} {
        if {[dict exists $jobs $token]} {_curveSourceAsyncFinish $token [dict create status error message $message error_code [dict get $options -errorcode]]} else {return -options $options $message}
    }
}
