# Actual existing-owner transport checks. No replacement owner or mock channel.
if {[llength $argv]!=2} {error {usage: contracts.tcl FRAMEWORK OUTPUT}}
lassign $argv framework output
source [file join $framework core tcl dataset_publication_api_v2.tcl]
source [file join $framework core tcl script_job_api_v1.tcl]
set helper [file dirname [info script]]
set python [auto_execok python3]
set setsid [auto_execok setsid]
if {$python eq {} || $setsid eq {}} {error {Actual Python and setsid are required}}
set ::checks 0
set ::callbacks {}
set ::backgroundErrors {}
set ::tick 0
proc bgerror {message} {lappend ::backgroundErrors [list $message $::errorInfo]}
proc record {name condition {detail {}}} {
    incr ::checks
    set state [expr {$condition ? "PASS" : "FAIL"}]
    puts "CHECK\t$name\t$state\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $detail]]"
    flush stdout
    if {!$condition} {error "Check failed: $name: $detail"}
}
proc callback {tag response} {dict lappend ::callbacks $tag $response}
proc exists {request} {dict exists $::GX::scriptJobRequests $request}
proc waitFor {condition {timeout 4000}} {
    set deadline [expr {[clock milliseconds]+$timeout}]
    while {![uplevel 1 $condition]} {
        if {[clock milliseconds]>=$deadline} {error "Timed out: $condition"}
        after 5 {incr ::tick};vwait ::tick
    }
}
proc start {mode {options {}} {callbackPrefix {}}} {
    if {$callbackPrefix eq {}} {set callbackPrefix [list callback "worker-[incr ::tag]"]}
    ::GX::scriptJobAsync [list {*}$::setsid {*}$::python -B [file join $::helper worker.py] $mode] {} $callbackPrefix [dict merge {duplex 1 process_group 1 max_bytes 200000} $options]
}
proc ready {request} {
    waitFor {expr {[exists $request] && [llength [::GX::datasetPublicationV2DictDefault [dict get $::GX::scriptJobRequests $request] messages {}]]>0}}
    set got [::GX::scriptJobRequestDrain $request]
    if {[dict get $got messages] ne {ready}} {error "Missing actual child readiness: $got"}
}
proc finish {request} {
    ::GX::scriptJobRequestCancel $request
    waitFor {expr {![exists $request]}}
}
proc rejected {name script expectedCode} {
    set rc [catch {uplevel 1 $script} message context]
    record $name [expr {$rc==1 && [dict get $context -errorcode] eq $expectedCode}] [list rc $rc message $message context $context]
}
proc terminalPeer {peer response} {
    callback eof $response
    set ::callbackInsideDrain $::insideDrain
    ::GX::scriptJobRequestCancel $peer
}
set ::tag 0
set ::insideDrain 0
set ::callbackInsideDrain 0
try {
    set info [::GX::scriptJobApiInfo]
    record metadata [expr {"scriptJobRequestSend" in [dict get $info auxiliary_operations] && "scriptJobRequestDrain" in [dict get $info auxiliary_operations] && [dict get $info auxiliary_send_pending_bytes]==65536 && [dict get $info auxiliary_drain_maximum] eq {default 16 min 1 max 16}}] $info
    set inactive [::GX::scriptJobRequestDrain never-existed]
    record unknown_drain [expr {$inactive eq {request_id never-existed active 0 cancelled {} messages {}}}] $inactive
    rejected unknown_send {::GX::scriptJobRequestSend never-existed x} {GXTXT SCRIPT_JOB INACTIVE}
    foreach bad {0 17 1.5 x {}} {rejected "invalid_maximum_[string map {{ } _} $bad]" {::GX::scriptJobRequestDrain never-existed $bad} {GXTXT SCRIPT_JOB MAXIMUM}}

    set request [start ready {timeout_ms 20000}]
    ready $request
    set before [dict get $::GX::scriptJobRequests $request]
    set started [clock microseconds]
    set empty [::GX::scriptJobRequestDrain $request]
    set elapsed [expr {[clock microseconds]-$started}]
    set after [dict get $::GX::scriptJobRequests $request]
    record no_response_no_wait [expr {[dict get $empty active] && [dict get $empty messages] eq {} && [dict get $empty cancelled] eq {} && [dict get $before timer] eq [dict get $after timer] && $elapsed<1000000}] [list microseconds $elapsed result $empty timer [dict get $after timer]]
    foreach bad [list "a\x00b" "a\rb" "a\nb"] {
        set before [dict get $::GX::scriptJobRequests $request]
        set pending [chan pending output [dict get $before pipe]]
        rejected forbidden_frame {::GX::scriptJobRequestSend $request $bad} {GXTXT SCRIPT_JOB FRAME}
        record forbidden_no_mutation [expr {$before eq [dict get $::GX::scriptJobRequests $request] && $pending==[chan pending output [dict get $before pipe]]}]
    }
    set sent [::GX::scriptJobRequestSend $request {}]
    waitFor {expr {[llength [::GX::datasetPublicationV2DictDefault [dict get $::GX::scriptJobRequests $request] messages {}]]==1}}
    set got [::GX::scriptJobRequestDrain $request]
    record empty_is_frame [expr {[dict get $sent payload_bytes]==0 && [dict get $sent accepted] && [llength [dict get $got messages]]==1 && [lindex [dict get $got messages] 0] eq {}}] [list sent $sent got $got]
    ::GX::scriptJobRequestSend $request !burst3
    waitFor {expr {[llength [::GX::datasetPublicationV2DictDefault [dict get $::GX::scriptJobRequests $request] messages {}]]==3}}
    set first [::GX::scriptJobRequestDrain $request 1]
    set residual [dict get $::GX::scriptJobRequests $request messages]
    set second [::GX::scriptJobRequestDrain $request 1]
    set third [::GX::scriptJobRequestDrain $request 1]
    record fifo_residual_empty [expr {[dict get $first messages] eq {first} && $residual eq {{} third} && [llength [dict get $second messages]]==1 && [lindex [dict get $second messages] 0] eq {} && [dict get $third messages] eq {third}}] [list first $first residual $residual second $second third $third]

    # encoding convertfrom creates the actual supplementary Unicode character;
    # Tcl's encoding is measured rather than assuming 4 or 6 wire bytes.
    set supplementary [encoding convertfrom utf-8 [binary decode hex f09f9880]]
    set utf8 [encoding convertto utf-8 $supplementary]
    set charBytes [string length $utf8]
    set boundary "[string repeat a [expr {65535-$charBytes}]]$supplementary"
    set admitted [::GX::scriptJobRequestSend $request $boundary]
    waitFor {expr {[llength [::GX::datasetPublicationV2DictDefault [dict get $::GX::scriptJobRequests $request] messages {}]]==1}}
    set echoed [lindex [dict get [::GX::scriptJobRequestDrain $request 1] messages] 0]
    record utf8_exact_boundary [expr {[dict get $admitted payload_bytes]==65535 && $echoed eq $boundary}] [list encoded_supplementary_hex [binary encode hex $utf8] supplementary_bytes $charBytes admitted $admitted]
    set before [dict get $::GX::scriptJobRequests $request]
    rejected utf8_over_boundary {::GX::scriptJobRequestSend $request "${boundary}a"} {GXTXT SCRIPT_JOB BUSY}
    record oversize_preserves_owner [expr {$before eq [dict get $::GX::scriptJobRequests $request]}]
    finish $request

    set sink [start sink]
    ready $sink
    set pipe [dict get $::GX::scriptJobRequests $sink pipe]
    set sawBusy 0
    set sends 0
    for {set i 0} {$i<32} {incr i} {
        set before [dict get $::GX::scriptJobRequests $sink]
        set pending [chan pending output $pipe]
        set rc [catch {::GX::scriptJobRequestSend $sink [string repeat q 32767]} response context]
        if {$rc} {
            record nonreader_busy_code [expr {[dict get $context -errorcode] eq {GXTXT SCRIPT_JOB BUSY}}] [list pending $pending accepted_frames $sends error $response]
            record nonreader_busy_no_mutation [expr {$pending>0 && $pending==[chan pending output $pipe] && $before eq [dict get $::GX::scriptJobRequests $sink] && [dict get $before cancelled] eq {}}]
            set sawBusy 1;break
        }
        incr sends
        record nonreader_bounded_queue [expr {[chan pending output $pipe]<=65536}] [list iteration $i pending [chan pending output $pipe]]
    }
    record nonreader_reached_backpressure $sawBusy
    set sinkPid [lindex [dict get $::GX::scriptJobRequests $sink pids] 0]
    finish $sink
    record sink_group_reaped [expr {[catch {exec kill -0 -- -$sinkPid 2>/dev/null}]}] [list process_group $sinkPid]

    set cancelled [start ready]
    ready $cancelled
    ::GX::scriptJobRequestSend $cancelled !burst3
    waitFor {expr {[llength [::GX::datasetPublicationV2DictDefault [dict get $::GX::scriptJobRequests $cancelled] messages {}]]==3}}
    ::GX::scriptJobRequestCancel $cancelled
    set drained [::GX::scriptJobRequestDrain $cancelled]
    record cancelled_frames_not_authoritative [expr {[dict get $drained active] && [dict get $drained cancelled] eq {cancelled} && [dict get $drained messages] eq {}}] $drained
    rejected cancelled_send {::GX::scriptJobRequestSend $cancelled x} {GXTXT SCRIPT_JOB INACTIVE}
    waitFor {expr {![exists $cancelled]}}

    set peer [start ready]
    ready $peer
    set eof [start ready {} [list terminalPeer $peer]]
    ready $eof
    # A real cancellation with its readable event held creates a deterministic
    # EOF/callback barrier. No request record, result or channel is fabricated.
    fileevent [dict get $::GX::scriptJobRequests $eof pipe] readable {}
    ::GX::scriptJobRequestCancel $eof
    waitFor {dict exists $::GX::scriptJobRequests $eof escalated}
    set ::insideDrain 1
    set drained [::GX::scriptJobRequestDrain $eof]
    set ::insideDrain 0
    record eof_callback_state_recheck [expr {![dict get $drained active] && [dict get $drained messages] eq {} && ![exists $eof] && $::callbackInsideDrain && [dict get $::GX::scriptJobRequests $peer cancelled] eq {cancelled} && [llength [dict get $::callbacks eof]]==1}] [list drained $drained callback_inside_drain $::callbackInsideDrain callback [dict get $::callbacks eof]]
    waitFor {expr {![exists $peer]}}

    set natural [start ready {} [list callback natural]]
    ready $natural
    ::GX::scriptJobRequestSend $natural !exit
    waitFor {expr {![exists $natural]}}
    record natural_eof_callback_once [expr {[llength [dict get $::callbacks natural]]==1 && [dict get [lindex [dict get $::callbacks natural] 0] error_type] eq {closed} && ![dict get [::GX::scriptJobRequestDrain $natural] active]}] [dict get $::callbacks natural]

    set broken [start ready {} [list callback read_error]]
    ready $broken
    chan close [dict get $::GX::scriptJobRequests $broken pipe] read
    set result [::GX::scriptJobRequestDrain $broken]
    record real_read_error_owned [expr {[dict get $result cancelled] eq {read_error} && [dict get $result messages] eq {}}] $result
    waitFor {expr {![exists $broken]}}
    record read_error_terminal_once [expr {[llength [dict get $::callbacks read_error]]==1 && [dict get [lindex [dict get $::callbacks read_error] 0] error_type] eq {read_error}}] [dict get $::callbacks read_error]
    set broken [start ready {} [list callback write_error]]
    ready $broken
    chan close [dict get $::GX::scriptJobRequests $broken pipe] write
    rejected real_write_error {::GX::scriptJobRequestSend $broken x} {GXTXT SCRIPT_JOB WRITE_FAILED}
    record write_error_same_request [expr {[exists $broken] && [dict get $::GX::scriptJobRequests $broken cancelled] eq {write_error}}]
    waitFor {expr {![exists $broken]}}
    record write_error_terminal_once [expr {[llength [dict get $::callbacks write_error]]==1 && [dict get [lindex [dict get $::callbacks write_error] 0] error_type] eq {write_error}}] [dict get $::callbacks write_error]

    foreach command {!burst17 !long !partial} {
        set limit [expr {$command eq "!burst17" ? 100 : 8}]
        set limited [start ready [dict create max_bytes $limit] [list callback $command]]
        ready $limited
        ::GX::scriptJobRequestSend $limited $command
        waitFor {expr {[dict get $::GX::scriptJobRequests $limited cancelled] ne {}}}
        set got [::GX::scriptJobRequestDrain $limited]
        record "output_limit_$command" [expr {[dict get $got cancelled] eq {output_limit} && [dict get $got messages] eq {}}] $got
        waitFor {expr {![exists $limited]}}
        record "output_limit_terminal_$command" [expr {[dict get [lindex [dict get $::callbacks $command] 0] error_type] eq {output_limit}}]
    }

    set legacy [start ready]
    record exchange_initial_receive [expr {[::GX::scriptJobRequestExchange $legacy {}] eq {ready}}]
    record exchange_payload [expr {[::GX::scriptJobRequestExchange $legacy old-frame] eq {old-frame}}]
    rejected exchange_timeout_bounds {::GX::scriptJobRequestExchange $legacy x 0} {NONE}
    set rc [catch {::GX::scriptJobRequestExchange $legacy {} 20} message]
    record exchange_timeout [expr {$rc==1 && $message eq {Compiled local event exceeded its bounded response time} && [dict get $::GX::scriptJobRequests $legacy cancelled] eq {timeout}}] $message
    waitFor {expr {![exists $legacy]}}
    set normal [start one-shot {duplex 0} [list callback normal]]
    rejected nonduplex_send {::GX::scriptJobRequestSend $normal x} {GXTXT SCRIPT_JOB INACTIVE}
    rejected nonduplex_drain {::GX::scriptJobRequestDrain $normal} {GXTXT SCRIPT_JOB INACTIVE}
    waitFor {expr {![exists $normal]}}
    record ordinary_async_unchanged [expr {[dict get [lindex [dict get $::callbacks normal] 0] ok] && [dict get [lindex [dict get $::callbacks normal] 0] result] eq {legacy}}] [dict get $::callbacks normal]
    record no_background_errors [expr {![llength $::backgroundErrors]}] $::backgroundErrors
    record all_requests_retired [expr {[dict size $::GX::scriptJobRequests]==0}] [dict keys $::GX::scriptJobRequests]
} on error {message context} {
    puts stderr [dict get $context -errorinfo]
    set failed 1
} finally {
    foreach request [dict keys $::GX::scriptJobRequests] {catch {::GX::scriptJobRequestCancel $request}}
    if {[catch {waitFor {expr {[dict size $::GX::scriptJobRequests]==0}} 5000} cleanup]} {puts stderr "Owned cleanup failed: $cleanup";set failed 1}
}
if {[info exists failed]} {exit 1}
puts "SUMMARY\t$::checks\tPASS"
