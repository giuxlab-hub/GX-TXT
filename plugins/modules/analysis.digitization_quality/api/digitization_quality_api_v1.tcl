# GX-TXT Digitization Quality backend API v1
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::DigitizationQuality {
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
    variable processChannel ""; variable processPid ""
}
proc ::GX::DigitizationQuality::_b64e {v} {binary encode base64 -maxlen 0 [encoding convertto utf-8 $v]}
proc ::GX::DigitizationQuality::_b64d {v} {encoding convertfrom utf-8 [binary decode base64 $v]}
proc ::GX::DigitizationQuality::_record {k args} {set f [list $k]; foreach a $args {lappend f [_b64e $a]}; join $f "\t"}
proc ::GX::DigitizationQuality::_send {c id status payload} {puts $c [join [list RES $id $status [_b64e $payload]] "\t"]; flush $c}
proc ::GX::DigitizationQuality::_ensureCompanion {} {
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
    if {![llength [info commands ::GX::CurveDigitizerCompanion::configurationList]]} {error "Curve Digitalizer Companion API v1 is unavailable."}
}
proc ::GX::DigitizationQuality::_bootstrap {} {
    _ensureCompanion
    set lines {}
    foreach item [::GX::CurveDigitizerCompanion::configurationList] {
        lappend lines [_record CONFIG [dict get $item document_id] [dict get $item configuration_name] [dict get $item source_dataset_id] [dict get $item calibration_ready]]
    }
    return [join $lines "\n"]
}
proc ::GX::DigitizationQuality::_tmp {text varName} {upvar 1 $varName p; set c [file tempfile p]; fconfigure $c -encoding utf-8 -translation lf; puts -nonewline $c $text; close $c}
proc ::GX::DigitizationQuality::_diagnostics {documentId} {
    variable moduleRoot
    _ensureCompanion
    set cfg [::GX::CurveDigitizerCompanion::configurationRead $documentId]
    set context [dict get $cfg configuration]
    set axes [dict get $context axes_json]
    set cal [dict get $context calibration_json]
    set sourceStatus VERIFIED
    set sourceMessage "Source Image Dataset verified by Dataset ID and SHA-256."
    set width 0; set height 0
    if {[catch {set src [::GX::CurveDigitizerCompanion::sourceResolve $documentId]} err]} {
        set sourceStatus ERROR; set sourceMessage $err
    } else {
        set meta [dict get $src metadata]
        if {[dict exists $meta image.width_px]} {set width [dict get $meta image.width_px]}
        if {[dict exists $meta image.height_px]} {set height [dict get $meta image.height_px]}
    }
    set ap ""; set cp ""
    try {
        _tmp $axes ap; _tmp $cal cp
        set py [::GX::runtimeToolRequired python]
        set cmd [list $py [file join $moduleRoot python calibration_diagnostics.py] --axes $ap --calibration $cp --image-width $width --image-height $height]
        set json [exec {*}$cmd]
    } finally {
        foreach p [list $ap $cp] {if {$p ne ""} {catch {file delete -force $p}}}
    }
    return [join [list [_record DOCUMENT $documentId [dict get $cfg document_sha256]] [_record SOURCE_STATUS $sourceStatus $sourceMessage] [_record RESULT_JSON $json]] "\n"]
}
proc ::GX::DigitizationQuality::_handle {line} {
    set f [split $line "\t"]; if {[llength $f] < 3 || [lindex $f 0] ne "REQ"} {error "Malformed request."}
    set id [lindex $f 1]; set cmd [lindex $f 2]; set args {}; foreach e [lrange $f 3 end] {lappend args [_b64d $e]}
    switch -- $cmd {BOOTSTRAP {set p [_bootstrap]} DIAGNOSTICS {if {[llength $args]!=1} {error "DIAGNOSTICS requires a document ID."}; set p [_diagnostics [lindex $args 0]]} default {error "Unknown request '$cmd'."}}
    list $id $p
}
proc ::GX::DigitizationQuality::_readable {c} {variable processChannel; variable processPid; if {[eof $c]} {catch {close $c}; set processChannel ""; set processPid ""; return}; if {[gets $c line] < 0} {return}; if {[catch {lassign [_handle $line] id p} e]} {set f [split $line "\t"]; set id [expr {[llength $f]>1?[lindex $f 1]:0}]; catch {_send $c $id ERR $e}; return}; _send $c $id OK $p}
proc ::GX::DigitizationQuality::_launch {} {variable processChannel; variable processPid; variable moduleRoot; if {$processChannel ne ""} {if {![catch {puts $processChannel "CONTROL\tFOCUS"; flush $processChannel}]} {return [dict create status focused pid $processPid]}; catch {close $processChannel}}; _ensureCompanion; set py [::GX::runtimeToolRequired python]; if {[catch {exec $py -c {import tkinter; import numpy}} e]} {error "Digitization Quality requires Python 3 with tkinter and NumPy: $e"}; set ch [open "|[list $py [file join $moduleRoot python gxtxt_digitization_quality.py]]" r+]; fconfigure $ch -encoding utf-8 -translation lf -buffering line -blocking 0; set processChannel $ch; set processPid [pid $ch]; fileevent $ch readable [list ::GX::DigitizationQuality::_readable $ch]; dict create status opened pid $processPid}
proc ::GX::DigitizationQuality::viewerDispatch {action scene} {switch -- $action {open - rerender {return [_launch]} default {error "Unsupported action '$action'."}}}
::GX::viewerBackendRegister digitization_quality_tk ::GX::DigitizationQuality::viewerDispatch
