# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted-host presentation export. Scientific sources, Resources, subprocesses
# and complete-file publication retain their existing CORE owners.
namespace eval ::GX::ScientificVideo {variable operations {}; variable serial 0}

proc ::GX::native3DAnimationDescribe {moduleId providerId timelineId} {
    set source [_native3DAnimationDescribeSource $moduleId $providerId $timelineId]
    return [dict get $source description]
}

proc ::GX::ScientificVideo::options {input count} {
    set allowed {first_index last_index width height fps playback_duration_seconds quality policy}
    dict for {key value} $input {if {$key ni $allowed} {error "Unknown scientific video option: $key"}}
    if {![string is integer -strict $count] || $count<1 || $count>256} {error {Scientific video requires 1..256 original samples}}
    set result [dict merge [dict create first_index 0 last_index [expr {$count-1}] width 1280 height 720 quality normal policy create_only] $input]
    foreach key {first_index last_index width height} {
        if {![string is integer -strict [dict get $result $key]]} {error "Scientific video $key must be an integer"}
    }
    set first [dict get $result first_index];set last [dict get $result last_index]
    if {$first<0 || $last<$first || $last>=$count} {error {Scientific video range is outside the original samples}}
    foreach key {width height} {set value [dict get $result $key];if {$value<16 || $value>4096 || $value%2} {error {H.264 video dimensions must be even and within16..4096}}}
    if {[dict get $result quality] ni {draft normal high} || [dict get $result policy] ne {create_only}} {error {Unsupported scientific video quality or publication policy}}
    set n [expr {$last-$first+1}]
    if {[dict exists $input fps] && [dict exists $input playback_duration_seconds]} {error {Choose FPS or playback duration, not both}}
    if {[dict exists $input playback_duration_seconds]} {
        set duration [dict get $input playback_duration_seconds]
        if {![string is double -strict $duration] || [catch {expr {double($duration)>0 && double($duration)<=86400 && abs(double($duration))<Inf}} valid] || !$valid} {error {Playback duration must be finite and within0..86400 seconds}}
        # A documented microsecond playback grid; scientific sample times are
        # retained independently and are never resampled by this rounding.
        set numerator [expr {$n*1000000}];set denominator [expr {round(double($duration)*1000000)}]
        if {$denominator<1} {error {Playback duration is below the microsecond grid}}
    } else {
        set rate [::GX::datasetPublicationV2DictDefault $input fps {24 1}]
        if {[llength $rate]!=2} {error {FPS requires numerator and denominator}}
        lassign $rate numerator denominator
        foreach value $rate {if {![string is integer -strict $value] || $value<1 || $value>1000000} {error {FPS terms must be integers within1..1000000}}}
    }
    if {[expr {double($numerator)/$denominator}]>120} {error {Video FPS exceeds120}}
    set a $numerator;set b $denominator
    while {$b} {set remainder [expr {$a%$b}];set a $b;set b $remainder}
    set numerator [expr {$numerator/$a}];set denominator [expr {$denominator/$a}]
    dict set result fps [list $numerator $denominator]
    dict set result frame_count $n
    set duration [expr {double($n)*$denominator/$numerator}]
    if {$duration>86400} {error {Sample-order video duration exceeds86400 seconds}}
    dict set result playback_duration_seconds $duration
    dict set result timing_policy original_sample_order
    dict set result max_source_bytes 268435456
    dict set result max_video_bytes 2147483648
    dict set result max_manifest_bytes 4194304
    # Source copies, selected frames PLUS native initialization frame, staged
    # video and16MiB for bounded requests/tool logs/working receipts. Retained
    # diagnostic allocation is admitted separately. This is admission, not RSS.
    dict set result expected_temporary_bytes [expr {268435456+($n+1)*([dict get $result width]*[dict get $result height]*5+65536)+2147483648+16777216}]
    return $result
}

proc ::GX::ScientificVideo::destination {path session} {
    if {[string first \x00 $path]>=0 || [string bytelength $path]>4096 || [file pathtype $path] ne {absolute}} {error {Choose an absolute external video destination}}
    set path [file normalize $path]
    if {[string tolower [file extension $path]] ne {.mp4} || ![file isdirectory [file dirname $path]]} {error {Choose an MP4 in an existing external directory}}
    # lstat also detects dangling links. Create-only publication rechecks races.
    if {![catch {file lstat $path info}]} {error {Video destination already exists}}
    set protectedRoots [list $session $::GX::scriptDir [::GX::resourceManagementRoot] [file join [::GX::configurationTempDirectory] resources-v1]]
    if {[info exists ::env(GXTXT_RESOURCE_STORAGE)]} {lappend protectedRoots $::env(GXTXT_RESOURCE_STORAGE)}
    foreach protected $protectedRoots {
        if {$protected eq {}} continue
        set protected [file normalize $protected]
        if {$path eq $protected || [string first "$protected/" "$path/"]==0} {error {Video destination must be outside scientific Session, framework and Resource storage}}
    }
    return $path
}

proc ::GX::ScientificVideo::encode {value} {
    return [list GXTXT_SCIENTIFIC_VIDEO_V1 [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]]
}
proc ::GX::ScientificVideo::decode {line} {
    if {[string bytelength $line]>65536 || [llength $line]!=2 || [lindex $line 0] ne {GXTXT_SCIENTIFIC_VIDEO_V1}} {error {Invalid scientific video control frame}}
    set bytes [binary decode base64 -strict [lindex $line 1]]
    if {[string length $bytes]>32768} {error {Scientific video control receipt exceeds32KiB}}
    set value [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $value] ne $bytes} {error {Scientific video control is not canonical UTF-8}}
    dict size $value
    return $value
}
proc ::GX::ScientificVideo::writeData {path value} {
    set channel [open $path {WRONLY CREAT EXCL}]
    try {fconfigure $channel -encoding utf-8 -translation lf;puts -nonewline $channel $value} finally {close $channel}
    file attributes $path -permissions 0600
}

proc ::GX::native3DAnimationExportAsync {moduleId providerId timelineId destination options callback} {
    variable ::GX::ScientificVideo::operations;variable ::GX::ScientificVideo::serial
    if {![llength $callback]} {error {Scientific video requires a trusted-host terminal callback}}
    if {$::GX::currentSession eq {}} {error {Open a scientific Session before exporting animation}}
    set session [file normalize $::GX::currentSession]
    set source [_native3DAnimationDescribeSource $moduleId $providerId $timelineId]
    set expected [dict get $source expected_source]
    if {[string length [encoding convertto utf-8 $expected]]>1048576} {error {Scientific animation source description exceeds1MiB}}
    set description [dict get $source description]
    set settings [::GX::ScientificVideo::options $options [dict get $description source_frame_count]]
    set destination [::GX::ScientificVideo::destination $destination $session]
    set token [interactiveDocumentSessionToken]
    set rootIdentity {}
    if {[llength [info commands winfo]]} {
        if {![winfo exists .]} {error {Scientific video cannot start after its host root closed}}
        set rootIdentity [winfo id .]
    }
    set operation video-[pid]-[clock microseconds]-[incr serial]
    set work {};set diagnostic {};set request {}
    try {
        set work [resourceManagementAllocate scientific_video [dict create kind directory lifetime operation session $session job_id $operation descendant_lease 1 expected_bytes [dict get $settings expected_temporary_bytes]]]
        set diagnostic [resourceManagementAllocate scientific_video_receipt [dict create category retained_diagnostic kind directory lifetime diagnostic session $session job_id $operation expected_bytes 4259840]]
        set root [dict get $work path]
        set requestFile [file join $root request.tcldict]
        set fixed [dict create schema gxtxt.scientific_video_request.v1 operation_id $operation session $session module_id $moduleId provider_id $providerId timeline_id $timelineId expected_source $expected options $settings destination $destination work_resource $work diagnostic_resource $diagnostic configuration_file [configurationPath]]
        ::GX::ScientificVideo::writeData $requestFile $fixed
        set interpreter [auto_execok tclsh]
        if {$interpreter eq {}} {error {Scientific video export requires the installed Tcl interpreter}}
        set argv [list {*}$interpreter [file join $::GX::scriptDir core native3d scientific_video_export_worker.tcl] $::GX::scriptDir $requestFile]
        set launcher [file join $root launch.txt]
        set channel [open $launcher {WRONLY CREAT EXCL}]
        try {
            fconfigure $channel -encoding ascii -translation lf
            puts $channel GXTXT_PARALLEL_EXEC_V1;puts $channel "GROUP\t1"
            foreach arg $argv {puts $channel "ARG\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $arg]]"}
            foreach {name value} [list GXTXT_RESOURCE_ROOT [resourceManagementRoot] GXTXT_RESOURCE_LEASE [dict get $work id]] {
                puts $channel "ENV\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $name]]\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]"
            }
        } finally {close $channel}
        file attributes $launcher -permissions 0600
        dict set operations $operation [dict create session $session session_token $token root_identity $rootIdentity module $moduleId provider $providerId timeline $timelineId expected_source $expected destination $destination callback $callback settings $settings work $work diagnostic $diagnostic authorized 0 outcome {} messages 0 timer {} request {} launcher $launcher request_file $requestFile]
        set command [list [runtimeToolRequired python] -I -B [file join $::GX::scriptDir core python parallel_process_exec_v1.py] $launcher]
        set request [scriptJobAsync $command {} [list ::GX::ScientificVideo::transportDone $operation] [dict create timeout_ms 3600000 max_bytes 65536 process_group 1 ui_lifetime 1 duplex 1 label {Scientific video export}]]
        dict set operations $operation request $request
        dict set operations $operation timer [after 25 [list ::GX::ScientificVideo::poll $operation]]
        return $request
    } on error {message context} {
        if {$request ne {}} {catch {scriptJobRequestCancel $request closed}}
        if {[dict exists $operations $operation]} {dict unset operations $operation}
        if {$work ne {}} {catch {resourceManagementRelease [dict get $work id] verified_orphan}}
        if {$diagnostic ne {}} {catch {resourceManagementRelease [dict get $diagnostic id] retained_diagnostic [dict get $diagnostic retention_seconds]}}
        return -options $context $message
    }
}

proc ::GX::ScientificVideo::current {entry} {
    if {$::GX::currentSession eq {} || [file normalize $::GX::currentSession] ne [dict get $entry session] || [::GX::interactiveDocumentSessionToken] ne [dict get $entry session_token]} {error {Scientific video source Session changed}}
    set now [::GX::_native3DAnimationDescribeSource [dict get $entry module] [dict get $entry provider] [dict get $entry timeline]]
    if {[dict get $now expected_source] ne [dict get $entry expected_source]} {error {Scientific animation source or render settings changed}}
    destination [dict get $entry destination] [dict get $entry session]
}

proc ::GX::ScientificVideo::poll {operation} {
    variable operations
    if {![dict exists $operations $operation]} return
    set entry [dict get $operations $operation];set request [dict get $entry request]
    dict set operations $operation timer {}
    if {[catch {
        set drained [::GX::scriptJobRequestDrain $request 8]
        if {![dict exists $operations $operation]} return
        foreach line [dict get $drained messages] {
            set message [decode $line]
            if {[dict get $message operation_id] ne $operation} {error {Scientific video receipt belongs to another operation}}
            set count [expr {[dict get $operations $operation messages]+1}]
            if {$count>8} {error {Scientific video emitted more than8 controls}}
            dict set operations $operation messages $count
            switch -- [dict get $message kind] {
                prepared {
                    if {[dict get $operations $operation authorized]} {error {Duplicate scientific video commit request}}
                    if {[lsort [dict keys $message]] ne {byte_count kind manifest_sha256 operation_id sha256} || ![regexp {^[0-9a-f]{64}$} [dict get $message sha256]] || ![regexp {^[0-9a-f]{64}$} [dict get $message manifest_sha256]] || ![string is integer -strict [dict get $message byte_count]] || [dict get $message byte_count]<1 || [dict get $message byte_count]>[dict get $entry settings max_video_bytes]} {error {Invalid scientific video prepared identity}}
                    current [dict get $operations $operation]
                    # A partly written authorization may have reached the
                    # worker. Record uncertainty BEFORE attempting Send.
                    dict set operations $operation authorized 1
                    dict set operations $operation prepared $message
                    ::GX::scriptJobRequestSend $request [encode [dict create operation_id $operation action authorize]]
                }
                terminal {
                    if {[dict get $operations $operation outcome] ne {}} {error {Duplicate scientific video terminal outcome}}
                    if {[dict get $message status] ni {published failed finalization_outcome_unknown} || ![string is boolean -strict [dict get $message ok]]} {error {Invalid scientific video terminal status}}
                    if {[dict get $message status] eq {published} && ![dict get $operations $operation authorized]} {error {Scientific video published without host authorization}}
                    if {[dict get $message status] eq {published}} {
                        set prepared [dict get $operations $operation prepared]
                        foreach key {sha256 byte_count} {if {[dict get $message video $key] ne [dict get $prepared $key]} {error {Scientific video terminal identity differs from its authorized file}}}
                        if {![dict get $message ok] || [dict get $message destination] ne [dict get $entry destination] || [dict get $message manifest_sha256] ne [dict get $prepared manifest_sha256]} {error {Scientific video terminal publication differs from authorization}}
                    } elseif {[dict get $message ok]} {error {Failed scientific video result claims success}}
                    dict set operations $operation outcome $message
                    ::GX::scriptJobRequestSend $request [encode [dict create operation_id $operation action acknowledge]]
                }
                default {error {Unknown scientific video worker control}}
            }
        }
        if {[dict exists $operations $operation] && [dict get $drained active]} {dict set operations $operation timer [after 25 [list ::GX::ScientificVideo::poll $operation]]}
    } message context]} {
        if {[dict exists $operations $operation]} {dict set operations $operation protocol_error $message;catch {::GX::scriptJobRequestCancel $request read_error}}
    }
}

proc ::GX::ScientificVideo::transportDone {operation transport} {
    variable operations
    if {![dict exists $operations $operation]} return
    set entry [dict get $operations $operation]
    if {[dict get $entry timer] ne {}} {after cancel [dict get $entry timer]}
    set outcome [dict get $entry outcome]
    if {$outcome eq {}} {
        set status [expr {[dict get $entry authorized]?{finalization_outcome_unknown}:{failed}}]
        if {![dict get $entry authorized] && [::GX::datasetPublicationV2DictDefault $transport error_type {}] in {cancelled closed}} {set status cancelled}
        set outcome [dict create ok 0 status $status error [::GX::datasetPublicationV2DictDefault $entry protocol_error [::GX::datasetPublicationV2DictDefault $transport error {Scientific video transport ended without a verified outcome}]]]
    }
    set canReconcile 1
    if {[dict get $entry root_identity] ne {} && (![llength [info commands winfo]] || ![winfo exists .] || [winfo id .] ne [dict get $entry root_identity])} {set canReconcile 0}
    if {[dict get $outcome status] eq {finalization_outcome_unknown} && [dict exists $entry prepared] && $canReconcile} {
        # A second fixed, read-only worker examines only the exact destination
        # and expected SHA captured BEFORE authorization. This never retries
        # publication or invokes a scientific provider/renderer/encoder.
        dict set operations $operation outcome $outcome
        if {![catch {
            set input [open [dict get $entry launcher] r]
            try {set launch [read $input 16385]} finally {close $input}
            if {[string length $launch]>16384} {error {Scientific video launcher exceeded its bound}}
            append launch "ARG\t[binary encode base64 -maxlen 0 reconcile]\n"
            set launcher [file join [dict get $entry work path] reconcile-launch.txt]
            writeData $launcher $launch
            set command [list [::GX::runtimeToolRequired python] -I -B [file join $::GX::scriptDir core python parallel_process_exec_v1.py] $launcher]
            set payload [encode [dict create action reconcile operation_id $operation expected [dict get $entry prepared]]]
            set reconcile [::GX::scriptJobAsync $command "$payload\n" [list ::GX::ScientificVideo::reconciled $operation] [dict create timeout_ms 120000 max_bytes 32768 process_group 1 ui_lifetime 1 label {Scientific video destination reconciliation}]]
            dict set operations $operation reconciliation_request $reconcile
        } message]} {return}
        dict set outcome reconciliation_error $message
    }
    finish $operation $outcome
}

proc ::GX::ScientificVideo::reconciled {operation response} {
    variable operations
    if {![dict exists $operations $operation]} return
    set entry [dict get $operations $operation]
    set outcome [dict get $entry outcome]
    if {![catch {expr {[::GX::datasetPublicationV2DictDefault $response ok 0] && [dict exists $response result] && [dict get $response result operation_id] eq $operation && [dict get $response result status] in {published_reconciled absent_reconciled conflict_reconciled}}} valid] && $valid} {
        set outcome [dict merge $outcome [dict get $response result]]
        if {[dict get $outcome status] eq {published_reconciled}} {
            dict set outcome manifest_sha256 [dict get $entry prepared manifest_sha256]
            foreach key {frame_count fps playback_duration_seconds timing_policy} {dict set outcome $key [dict get $entry settings $key]}
            dict set outcome publication_receipt_status unavailable_after_interruption
            dict set outcome reconciliation_qualification {Matching authorized encoded bytes are present; the interrupted original publication receipt is unavailable}
            dict unset outcome error
        }
    } else {dict set outcome reconciliation_error [::GX::datasetPublicationV2DictDefault $response error {No verified destination reconciliation receipt}]}
    finish $operation $outcome
}

proc ::GX::ScientificVideo::finish {operation outcome} {
    variable operations
    if {![dict exists $operations $operation]} return
    set entry [dict get $operations $operation]
    dict unset operations $operation
    # Generic EOF/cancellation cannot erase an observed terminal publication.
    # Unknown publication is retained for exact read-only reconciliation; no
    # committed destination is removed by this adapter.
    dict set outcome request_id [dict get $entry request]
    dict set outcome source [dict create module_id [dict get $entry module] provider_id [dict get $entry provider] timeline_id [dict get $entry timeline]]
    dict set outcome diagnostic_resource_id [dict get $entry diagnostic id]
    set cleanup {}
    foreach {key state} {work verified_orphan diagnostic retained_diagnostic} {
        if {[dict get $outcome status] in {finalization_outcome_unknown conflict_reconciled}} {set state retained_diagnostic}
        set resource [dict get $entry $key]
        set retention [expr {$state eq {retained_diagnostic}?[dict get $entry diagnostic retention_seconds]:{}}]
        if {[catch {::GX::resourceManagementRelease [dict get $resource id] $state $retention} message]} {dict set cleanup $key [dict create status recovery_required reason $message]} else {dict set cleanup $key [dict create status released resource_id [dict get $resource id] state $state]}
    }
    dict set outcome resource_release $cleanup
    # No cleanup sweep or all-descendant certificate follows from this receipt.
    uplevel #0 [list {*}[dict get $entry callback] $outcome]
}
