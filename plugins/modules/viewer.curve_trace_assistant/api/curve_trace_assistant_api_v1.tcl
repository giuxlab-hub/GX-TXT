# GX-TXT Curve Trace Assistant API v1 - native C desktop backend
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX::CurveTraceAssistant {
    variable moduleId viewer.curve_trace_assistant
    variable version 0.5.0
    variable digitizerModule viewer.curve_digitizer
    variable digitizerApi CURVE_DIGITIZER_COMPANION_API_v1
    variable moduleRoot [file normalize [file join [file dirname [info script]] ..]]
    variable processChannel ""
    variable processPid ""
}

proc ::GX::CurveTraceAssistant::_b64e {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}
proc ::GX::CurveTraceAssistant::_b64d {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}
proc ::GX::CurveTraceAssistant::_record {kind args} {
    set fields [list $kind]
    foreach arg $args { lappend fields [_b64e $arg] }
    return [join $fields "\t"]
}
proc ::GX::CurveTraceAssistant::_send {channel requestId status payload} {
    puts $channel [join [list RES $requestId $status [_b64e $payload]] "\t"]
    flush $channel
}

proc ::GX::CurveTraceAssistant::_activateDigitizerCompanion {} {
    variable digitizerModule
    variable digitizerApi
    if {[package vcompare [::GX::moduleField $digitizerModule version "0"] 1.2.0] < 0} {
        error "Curve Trace Assistant requires viewer.curve_digitizer 1.2.0 or newer."
    }
    ::GX::modulePublicApiActivate $digitizerModule $digitizerApi
    foreach command {
        ::GX::CurveDigitizerCompanion::sessionToken
        ::GX::CurveDigitizerCompanion::configurationList
        ::GX::CurveDigitizerCompanion::configurationRead
        ::GX::CurveDigitizerCompanion::curveContext
        ::GX::CurveDigitizerCompanion::sourceResolve
        ::GX::CurveDigitizerCompanion::commitPixelPoints
    } {
        if {![llength [info commands $command]]} {
            error "Curve Digitalizer Companion API did not provide required command '$command'."
        }
    }
    return 1
}

proc ::GX::CurveTraceAssistant::sessionToken {} {
    _activateDigitizerCompanion
    return [::GX::CurveDigitizerCompanion::sessionToken]
}
proc ::GX::CurveTraceAssistant::configurationList {} {
    _activateDigitizerCompanion
    return [::GX::CurveDigitizerCompanion::configurationList]
}
proc ::GX::CurveTraceAssistant::configurationRead {documentId} {
    _activateDigitizerCompanion
    return [::GX::CurveDigitizerCompanion::configurationRead $documentId]
}
proc ::GX::CurveTraceAssistant::curveContext {documentId curveId} {
    _activateDigitizerCompanion
    return [::GX::CurveDigitizerCompanion::curveContext $documentId $curveId]
}
proc ::GX::CurveTraceAssistant::sourceResolve {documentId} {
    _activateDigitizerCompanion
    return [::GX::CurveDigitizerCompanion::sourceResolve $documentId]
}
proc ::GX::CurveTraceAssistant::commitPixelPoints {documentId curveId expectedDocumentSha sessionToken pointsText} {
    _activateDigitizerCompanion
    return [::GX::CurveDigitizerCompanion::commitPixelPoints \
        $documentId $curveId $expectedDocumentSha $sessionToken $pointsText]
}

proc ::GX::CurveTraceAssistant::_bootstrap {} {
    set lines [list [_record SESSION [sessionToken]]]
    foreach item [configurationList] {
        lappend lines [_record CONFIG \
            [dict get $item document_id] \
            [dict get $item document_sha256] \
            [dict get $item configuration_id] \
            [dict get $item configuration_name] \
            [dict get $item source_dataset_id] \
            [dict get $item calibration_ready]]
    }
    return [join $lines "\n"]
}

proc ::GX::CurveTraceAssistant::_configurationPayload {documentId} {
    set config [configurationRead $documentId]
    set source [sourceResolve $documentId]
    set lines [list \
        [_record DOCUMENT_SHA [dict get $config document_sha256]] \
        [_record PAYLOAD [dict get $config payload]] \
        [_record SOURCE_DATASET [dict get $source dataset_id]] \
        [_record SOURCE_PATH [dict get $source path]] \
        [_record SOURCE_SHA [dict get $source sha256]]]
    dict for {key value} [dict get $source metadata] {
        lappend lines [_record METADATA $key $value]
    }
    return [join $lines "\n"]
}

proc ::GX::CurveTraceAssistant::_handleRequest {channel line} {
    set fields [split $line "\t"]
    if {[llength $fields] < 3 || [lindex $fields 0] ne "REQ"} {
        error "Malformed Curve Trace Assistant backend request."
    }
    set requestId [lindex $fields 1]
    set command [lindex $fields 2]
    set args {}
    foreach encoded [lrange $fields 3 end] { lappend args [_b64d $encoded] }
    set payload ""
    switch -- $command {
        BOOTSTRAP { set payload [_bootstrap] }
        CONFIG {
            if {[llength $args] != 1} { error "CONFIG requires one Curve Digitalizer document ID." }
            set payload [_configurationPayload [lindex $args 0]]
        }
        COMMIT {
            if {[llength $args] != 5} { error "COMMIT requires document ID, curve ID, expected document SHA-256, Session token and pixel points." }
            set result [commitPixelPoints {*}$args]
            set payload [join [list [dict get $result document_id] [dict get $result document_sha256] [dict get $result curve_id]] "\t"]
        }
        default { error "Unknown Curve Trace Assistant backend request '$command'." }
    }
    return [list $requestId $payload]
}

proc ::GX::CurveTraceAssistant::_readable {channel} {
    variable processChannel
    variable processPid
    if {[eof $channel]} {
        catch {close $channel}
        if {$processChannel eq $channel} { set processChannel ""; set processPid "" }
        return
    }
    if {[gets $channel line] < 0} { return }
    if {[catch {lassign [_handleRequest $channel $line] requestId payload} failure options]} {
        set fields [split $line "\t"]
        set requestId [expr {[llength $fields] >= 2 ? [lindex $fields 1] : "0"}]
        catch {_send $channel $requestId ERR $failure}
        return
    }
    _send $channel $requestId OK $payload
}

proc ::GX::CurveTraceAssistant::_nativeExecutable {} {
    variable moduleRoot
    set native [file join $moduleRoot bin gx_curve_trace_assistant]
    if {[file isfile $native] && [file executable $native]} {
        if {![catch {exec $native --self-test} probe] && [string match "PASS*" [string trim $probe]]} {
            return $native
        }
        error "The installed Curve Trace Assistant native binary failed its self-test. Rebuild it with build_native.sh."
    }

    set build [file join $moduleRoot build_native.sh]
    if {[file isfile $build]} {
        if {[catch {exec sh $build 2>@1} failure options]} {
            return -options $options "Curve Trace Assistant has source code but no usable native binary. Automatic build failed: $failure\nRun '$build' on the GX-TXT server after installing the required C/X11/image development packages."
        }
        if {[file isfile $native] && [file executable $native]} { return $native }
    }
    error "Curve Trace Assistant native backend is missing. Install a precompiled package or build the source package with build_native.sh."
}

proc ::GX::CurveTraceAssistant::_launch {} {
    variable processChannel
    variable processPid
    if {$processChannel ne ""} {
        if {![catch {puts $processChannel "CONTROL\tFOCUS"; flush $processChannel}]} {
            return [dict create status focused pid $processPid]
        }
        catch {close $processChannel}
        set processChannel ""
        set processPid ""
    }
    sessionToken
    set native [_nativeExecutable]
    set pipeline "|[list $native]"
    if {[catch {set channel [open $pipeline r+]} failure options]} {
        return -options $options "Unable to start Curve Trace Assistant native backend: $failure"
    }
    fconfigure $channel -encoding utf-8 -translation lf -buffering line -blocking 0
    set processChannel $channel
    set processPid [pid $channel]
    fileevent $channel readable [list ::GX::CurveTraceAssistant::_readable $channel]
    return [dict create status opened pid $processPid]
}

proc ::GX::CurveTraceAssistant::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender { return [_launch] }
        default { error "Unsupported Curve Trace Assistant viewer action '$action'." }
    }
}

::GX::viewerBackendRegister curve_trace_assistant_native ::GX::CurveTraceAssistant::viewerDispatch
