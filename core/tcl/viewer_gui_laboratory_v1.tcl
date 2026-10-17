# SPDX-License-Identifier: GPL-3.0-or-later
# Bounded GUI diagnostics over Viewer GUI Host objects and command hooks.
# No scientific registry, renderer, execution supervisor or widget toolkit.
namespace eval ::GX::ViewerGui {variable recordings {};variable laboratories {};variable monitors {};variable labSerial 0}
proc ::GX::viewerGuiMonitorStart {window duration callback {interval 50}} {
    if {![winfo exists $window] || ![dict exists $::GX::ViewerGui::instances $window]} {error {A live declared Viewer is required.}}
    if {![string is integer -strict $duration] || $duration<100 || $duration>10000 || ![string is integer -strict $interval] || $interval<20 || $interval>500} {error {Monitor duration is 100–10000 ms; interval is 20–500 ms.}}
    if {[dict size $::GX::ViewerGui::monitors]>=4} {error {Finish or cancel an active monitor first.}}
    set id monitor-[incr ::GX::ViewerGui::labSerial];set now [clock microseconds]
    dict set ::GX::ViewerGui::monitors $id [dict create window $window callback $callback interval $interval started_us $now previous_us $now deadline_us [expr {$now+1000*$duration}] samples {}]
    _viewerGuiMonitorTick $id
    return $id
}
proc ::GX::viewerGuiMonitorCancel {id} {
    if {[dict exists $::GX::ViewerGui::monitors $id]} {_viewerGuiMonitorFinish $id CANCELLED}
}
proc ::GX::_viewerGuiMonitorTick {id} {
    if {![dict exists $::GX::ViewerGui::monitors $id]} return
    set monitor [dict get $::GX::ViewerGui::monitors $id];set window [dict get $monitor window]
    if {![winfo exists $window] || ![dict exists $::GX::ViewerGui::instances $window]} {_viewerGuiMonitorFinish $id CLOSED;return}
    set now [clock microseconds];set instance [dict get $::GX::ViewerGui::instances $window]
    set sample [dict create elapsed_ms [expr {($now-[dict get $monitor started_us])/1000.0}] interval_ms [expr {($now-[dict get $monitor previous_us])/1000.0}] mapped [winfo ismapped $window] global_auxiliary_requests [dict size $::GX::scriptJobRequests] declared_components [dict size [dict get $instance widgets]]]
    foreach {name path} [list process_memory /proc/[pid]/status process_io /proc/[pid]/io] {
        if {[file readable $path]} {
            set f [open $path];try {set text [read $f 16384]} finally {close $f}
            foreach line [split $text \n] {if {[regexp {^(VmRSS|VmHWM|read_bytes|write_bytes|syscr|syscw):\s+([0-9]+)} $line -> key value]} {dict set sample $name $key $value}}
        }
    }
    set native {}
    dict for {component widget} [dict get $instance widgets] {
        if {[winfo exists $widget.curve] && ![catch {native2DViewportCurveDescribe $widget.curve} description]} {dict set native $component [dict get $description metrics]}
    }
    dict set sample native2d_metrics $native
    dict lappend monitor samples $sample;dict set monitor previous_us $now
    dict set ::GX::ViewerGui::monitors $id $monitor
    if {$now>=[dict get $monitor deadline_us]} {_viewerGuiMonitorFinish $id COMPLETE;return}
    dict set ::GX::ViewerGui::monitors $id timer [after [dict get $monitor interval] [list ::GX::_viewerGuiMonitorTick $id]]
}
proc ::GX::_viewerGuiMonitorFinish {id status} {
    set monitor [dict get $::GX::ViewerGui::monitors $id];dict unset ::GX::ViewerGui::monitors $id
    if {[dict exists $monitor timer]} {after cancel [dict get $monitor timer]}
    set worst 0;foreach sample [dict get $monitor samples] {set worst [expr {max($worst,[dict get $sample interval_ms])}]}
    set report [dict create schema gxtxt.viewer_gui_monitor.v1 id $id status $status window [dict get $monitor window] requested_interval_ms [dict get $monitor interval] max_callback_interval_ms $worst samples [dict get $monitor samples] scope {Actual Tk event-loop intervals and native-owner counters. Memory/I/O and auxiliary counts are process-wide, not attributed to this Viewer. No scientific payload or source reread is sampled.}]
    uplevel #0 [list {*}[dict get $monitor callback] $report]
}
proc ::GX::_viewerGuiLabPrune {} {
    foreach variable {recordings laboratories} {
        upvar #0 ::GX::ViewerGui::$variable records
        foreach key [dict keys $records] {
            if {[dict size $records]<20} break
            set item [dict get $records $key]
            if {[dict exists $item finished] || ([dict exists $item active] && ![dict get $item active])} {dict unset records $key}
        }
        if {[dict size $records]>=20} {error {Too many active GUI laboratory runs. Finish or cancel an earlier run.}}
    }
}
proc ::GX::viewerGuiRecordingStart {window {filter {}}} {
    _viewerGuiLabPrune
    viewerGuiRuntimeInspect $window
    foreach key [dict keys $filter] {if {$key ni {component event}} {error {Recording filter accepts component and event glob patterns.}}}
    set id recording-[incr ::GX::ViewerGui::labSerial]
    set instance [dict get $::GX::ViewerGui::instances $window]
    set design [dict get $instance design];set components {}
    foreach component [dict get $design components] {lappend components [dict get $component id]}
    set identity [dict create module_id [dict get $design module_id] provider_id [dict get $design provider_id] version [dict get $design version] components $components requirements [dict get $design requirements]]
    dict set ::GX::ViewerGui::recordings $id [dict create schema gxtxt.viewer_gui_scenario.v1 id $id window $window active 1 filter $filter actions {} pending {} environment [viewerGuiEnvironment $window] design_identity $identity redaction {Field values, project defaults and scientific payloads are excluded. Select actions restore component focus, not scientific point selection.}]
    set observer [viewerGuiTraceSubscribe $window [list ::GX::_viewerGuiRecordingEvent $id]]
    dict set ::GX::ViewerGui::recordings $id observer $observer
    return $id
}
proc ::GX::_viewerGuiRecordingEvent {id record} {
    if {![dict exists $::GX::ViewerGui::recordings $id] || ![dict get $::GX::ViewerGui::recordings $id active]} return
    set capture [dict get $::GX::ViewerGui::recordings $id]
    dict for {key pattern} [dict get $capture filter] {if {![string match $pattern [dict get $record $key]]} return}
    if {[dict get $record event] eq {invoke}} {dict set capture pending [dict get $record correlation_id] [dict get $record component]}
    if {[dict get $record event] eq {result} && [dict exists $capture pending [dict get $record correlation_id]]} {
        set command [dict get $capture pending [dict get $record correlation_id]]
        dict unset capture pending [dict get $record correlation_id]
        dict lappend capture actions [dict create operation invoke command $command expected_status [dict get $record detail status] timeout_ms 2000]
    }
    if {[dict get $record event] eq {selected}} {
        set component [dict get $record component];set window [dict get $capture window]
        set type {};catch {set type [dict get [viewerGuiDesignComponent $window $component] type]}
        if {$type in {entry combobox field toggle choice checkbutton dataset_selector list table native2d plot}} {
            set action [dict create operation select component $component timeout_ms 2000]
            if {[lindex [dict get $capture actions] end] ne $action} {dict lappend capture actions $action}
        }
    } elseif {[dict get $record event] eq {resized}} {
        dict lappend capture actions [dict create operation resize geometry [dict get $record detail geometry] timeout_ms 2000]
    }
    if {[llength [dict get $capture actions]]>200} {dict set capture active 0;viewerGuiTraceUnsubscribe [dict get $capture observer]}
    dict set ::GX::ViewerGui::recordings $id $capture
}
proc ::GX::viewerGuiRecordingStop {id} {
    set capture [dict get $::GX::ViewerGui::recordings $id]
    viewerGuiTraceUnsubscribe [dict get $capture observer]
    dict set capture active 0;dict set ::GX::ViewerGui::recordings $id $capture
    return [dict remove $capture observer pending active]
}
proc ::GX::viewerGuiScenarioValidate {scenario} {
    if {[dict get $scenario schema] ne {gxtxt.viewer_gui_scenario.v1} || [llength [dict get $scenario actions]]>200 || [string bytelength $scenario]>4194304} {error {Invalid or oversized GUI scenario.}}
    foreach action [dict get $scenario actions] {
        set operation [dict get $action operation]
        if {$operation ni {invoke resize select checkpoint dialog_absent}} {error {Unsupported logical GUI action.}}
        set timeout [datasetPublicationV2DictDefault $action timeout_ms 2000]
        if {![string is integer -strict $timeout] || $timeout<50 || $timeout>10000} {error {Scenario waits must be bounded to 50–10000 ms.}}
        if {$operation eq {resize} && ![regexp {^[0-9]{3,4}x[0-9]{3,4}$} [dict get $action geometry]]} {error {Invalid replay geometry.}}
    }
    return $scenario
}
proc ::GX::viewerGuiEnvironment {window} {
    return [dict create platform $::tcl_platform(os) tcl [info patchlevel] tk [package provide Tk] framework $::GX::version theme [ttk::style theme use] scaling [tk scaling] font [font actual TkDefaultFont] geometry [wm geometry $window]]
}
proc ::GX::viewerGuiTestFixtureValidate {window options} {
    if {![dict exists $options fixture_root] || ![dict exists $options permitted_commands]} {return 0}
    set root [file normalize [dict get $options fixture_root]]
    if {![file isfile [file join $root .gxtxt-gui-test-fixture]] || $::GX::currentSession eq {}} {return 0}
    set session [file normalize $::GX::currentSession]
    return [string match $root/* $session]
}
proc ::GX::viewerGuiReplayStart {window scenario callback {options {}}} {
    _viewerGuiLabPrune
    set scenario [viewerGuiScenarioValidate $scenario]
    if {![dict exists $::GX::ViewerGui::instances $window]} {error {Replay requires a declared live Viewer GUI Host instance.}}
    if {[dict get $::GX::ViewerGui::instances $window mode] ne {preview} && ![viewerGuiTestFixtureValidate $window $options]} {error {Runtime replay requires an explicitly marked private test fixture and permitted commands.}}
    set id replay-[incr ::GX::ViewerGui::labSerial]
    dict set ::GX::ViewerGui::laboratories $id [dict create schema gxtxt.viewer_gui_replay.v1 id $id window $window scenario $scenario callback $callback options $options index 0 cases {} phase ready environment [viewerGuiEnvironment $window] started_ms [clock milliseconds] cancelled 0]
    after 0 [list ::GX::_viewerGuiReplayStep $id]
    return $id
}
proc ::GX::viewerGuiReplayCancel {id} {if {[dict exists $::GX::ViewerGui::laboratories $id]} {dict set ::GX::ViewerGui::laboratories $id cancelled 1}}
proc ::GX::_viewerGuiLabFinish {id} {
    set run [dict get $::GX::ViewerGui::laboratories $id]
    set status PASS;foreach row [dict get $run cases] {if {[dict get $row status] ne {PASS}} {set status [dict get $row status];break}}
    if {[dict get $run cancelled]} {set status CANCELLED}
    dict set run status $status;dict set run elapsed_ms [expr {[clock milliseconds]-[dict get $run started_ms]}]
    dict set run finished 1
    set coverage {}
    foreach row [dict get $run cases] {
        lappend coverage [dict create case [dict get $row id] status [dict get $row status] owner [dict get $row owner] capability [datasetPublicationV2DictDefault $row component [datasetPublicationV2DictDefault $row family [datasetPublicationV2DictDefault $row action {}]]] scope {Only the assertion and events recorded in this case were exercised.}]
    }
    dict set run coverage $coverage
    dict set ::GX::ViewerGui::laboratories $id $run
    if {[dict get $run callback] ne {}} {uplevel #0 [list {*}[dict get $run callback] [dict remove $run callback]]}
}
proc ::GX::_viewerGuiReplayStep {id} {
    if {![dict exists $::GX::ViewerGui::laboratories $id]} return
    set run [dict get $::GX::ViewerGui::laboratories $id];set w [dict get $run window]
    set index [dict get $run index];set actions [dict get $run scenario actions]
    if {[dict get $run cancelled] || $index>=[llength $actions]} {_viewerGuiLabFinish $id;return}
    set action [lindex $actions $index];set op [dict get $action operation]
    if {[dict get $run phase] eq {ready}} {
        dict set run deadline [expr {[clock milliseconds]+[datasetPublicationV2DictDefault $action timeout_ms 2000]}]
        dict set run trace_start [expr {[dict exists $::GX::ViewerGui::instances $w] ? [llength [dict get $::GX::ViewerGui::instances $w traces]] : 0}]
        dict set run phase waiting
    }
    set ready [expr {[winfo exists $w] && [winfo viewable $w] && [viewerGuiDesignGuard $w]}]
    set completed 0;set observed {};set status PASS
    if {$ready && ![dict exists $run fired]} {
        if {[catch {
            switch $op {
                invoke {
                    set command [dict get $action command]
                    if {[dict get $::GX::ViewerGui::instances $w mode] ne {preview} && $command ni [dict get $run options permitted_commands]} {error {Command is not permitted by the private-fixture scenario.}}
                    if {![viewerCommandEnabled $w $command] || ![viewerCommandApplicable $w $command]} {error {Command is disabled or inapplicable.}}
                    set widget {}
                    dict for {component path} [dict get $::GX::ViewerGui::instances $w widgets] {
                        set definition [viewerGuiDesignComponent $w $component]
                        if {[dict get $definition type] eq {action} && [dict get $definition properties action] eq $command && [winfo viewable $path]} {set widget $path;break}
                    }
                    if {$widget eq {} && [dict exists $::GX::ViewerCommands::windows $w toolbar buttons $command]} {
                        set candidate [dict get $::GX::ViewerCommands::windows $w toolbar buttons $command]
                        if {[winfo viewable $candidate]} {set widget $candidate}
                    }
                    if {$widget eq {}} {error {No mapped action button represents this command; add a declared action component before pointer replay.}}
                    focus $widget
                    event generate $widget <Enter> -when tail
                    event generate $widget <ButtonPress-1> -x [expr {[winfo width $widget]/2}] -y [expr {[winfo height $widget]/2}] -when tail
                    event generate $widget <ButtonRelease-1> -x [expr {[winfo width $widget]/2}] -y [expr {[winfo height $widget]/2}] -when tail
                }
                resize {wm geometry $w [dict get $action geometry]}
                select {
                    set widget [dict get $::GX::ViewerGui::instances $w widgets [dict get $action component]]
                    if {![winfo viewable $widget]} {error {Selected component is not viewable.}}
                    focus $widget
                }
                checkpoint {}
                dialog_absent {if {[grab current] ne {}} {set ready 0}}
            }
        } message options]} {set status FAIL;set observed $message;set completed 1} else {dict set run fired 1}
    }
    if {$ready && [dict exists $run fired] && !$completed} {
        switch $op {
            invoke {
                foreach trace [lrange [dict get $::GX::ViewerGui::instances $w traces] [dict get $run trace_start] end] {
                    if {[dict get $trace event] eq {result} && [dict get $trace component] eq [dict get $action command]} {
                        set observed [dict get $trace detail status];set completed 1
                        if {$observed ne [dict get $action expected_status]} {set status FAIL}
                        break
                    }
                }
            }
            resize {set observed [lindex [split [wm geometry $w] +] 0];set completed [expr {$observed eq [dict get $action geometry]}]}
            select {set widget [dict get $::GX::ViewerGui::instances $w widgets [dict get $action component]];set observed [focus];set completed [expr {$observed eq $widget}]}
            checkpoint {set observed [dict create viewable [winfo viewable $w] grab [grab current]];set completed 1}
            dialog_absent {set observed [grab current];set completed [expr {$observed eq {}}]}
        }
    }
    if {!$completed && [clock milliseconds]>=[dict get $run deadline]} {set completed 1;set status FAIL;set observed {State-ready wait timed out; window, source, command or dialog did not reach the expected state.}}
    if {$completed} {
        dict lappend run cases [dict create id action_$index status $status action $action observed $observed owner VIEWER_GUI_HOST_API_v1 input_method {Tk queued pointer/focus events on actual mapped widgets}]
        dict incr run index;dict set run phase ready;if {[dict exists $run fired]} {dict unset run fired}
    }
    dict set ::GX::ViewerGui::laboratories $id $run
    after 20 [list ::GX::_viewerGuiReplayStep $id]
}
proc ::GX::viewerGuiTestPlan {window {families {structure negative lifecycle}}} {
    set plan {};set capabilities [viewerGuiComponentCapabilities]
    foreach family $families {
        switch $family {
            structure {
                lappend plan [dict create id structure family structure label {Declared components and actual CORE mounts}]
                foreach component [dict get $::GX::ViewerGui::instances $window design components] {lappend plan [dict create id component:[dict get $component id] family structure component [dict get $component id] label {Actual component contract} ]}
            }
            negative {foreach kind {duplicate invalid_parent missing_handler bad_version bad_callback bad_property} {lappend plan [dict create id negative:$kind family negative label "Reject $kind"]}}
            lifecycle {foreach kind {mapped geometry focus grab} {lappend plan [dict create id lifecycle:$kind family lifecycle label "Observe $kind"]}}
            scientific {foreach component [dict get $::GX::ViewerGui::instances $window design components] {if {[dict get $component type] in {native2d plot native3d}} {lappend plan [dict create id source:[dict get $component id] family scientific component [dict get $component id] label {Scientific binding readiness; navigation requires an explicit scenario}]}}}
            default {error "Unknown finite GUI test family '$family'."}
        }
    }
    return [dict create schema gxtxt.viewer_gui_test_plan.v1 cases $plan count [llength $plan] families $families fixture_requirements {Read-only mount/contract checks. Scientific actions and runtime replay require an explicitly marked private fixture.}]
}
proc ::GX::viewerGuiTestsStart {window plan callback} {
    _viewerGuiLabPrune
    if {[dict get $plan schema] ne {gxtxt.viewer_gui_test_plan.v1} || [llength [dict get $plan cases]]>1100} {error {Invalid finite GUI test plan.}}
    set id suite-[incr ::GX::ViewerGui::labSerial]
    dict set ::GX::ViewerGui::laboratories $id [dict create schema gxtxt.viewer_gui_tests.v1 id $id window $window plan $plan callback $callback index 0 cases {} environment [viewerGuiEnvironment $window] started_ms [clock milliseconds] cancelled 0]
    after 0 [list ::GX::_viewerGuiTestStep $id]
    return $id
}
proc ::GX::_viewerGuiTestStep {id} {
    set run [dict get $::GX::ViewerGui::laboratories $id];set w [dict get $run window];set at [dict get $run index]
    set now [clock milliseconds]
    if {[dict exists $run last_tick_ms]} {dict set run max_callback_interval_ms [expr {max([dict get $run max_callback_interval_ms],$now-[dict get $run last_tick_ms])}]} else {dict set run max_callback_interval_ms 0}
    dict set run last_tick_ms $now;dict set ::GX::ViewerGui::laboratories $id $run
    if {[dict get $run cancelled] || $at>=[llength [dict get $run plan cases]]} {_viewerGuiLabFinish $id;return}
    set case [lindex [dict get $run plan cases] $at];set observed {};set status PASS
    if {[catch {
        if {![dict exists $::GX::ViewerGui::instances $w]} {error {Viewer closed during the suite.}}
        set inspection [viewerGuiRuntimeInspect $w];set design [dict get $::GX::ViewerGui::instances $w design]
        set kind [dict get $case id]
        if {$kind eq {structure}} {viewerGuiDesignValidate $design;set observed [dict create declared [llength [dict get $design components]] mounted [dict size [dict get $inspection components]]];if {[dict get $observed declared]!=[dict get $observed mounted]} {error {Component inventory mismatch.}}} elseif {[string match component:* $kind]} {
            set row [dict get $inspection components [dict get $case component]];set observed $row
            if {[dict get $row status] eq {SESSION_REQUIRED}} {set status BLOCKED} elseif {[dict get $row status] eq {MISSING}} {error {Declared component is missing.}}
            set p [dict get $row declared_properties]
            set key [expr {[dict get $row type] eq {action} ? {label} : {text}}]
            if {[dict exists $row effective_text] && [dict exists $p $key] && [dict get $row effective_text] ne [dict get $p $key]} {error {Declared and actual component text differ.}}
        } elseif {[string match negative:* $kind]} {
            set invalid [viewerGuiDesignNew];set item {id probe type action parent toolbar properties {label Probe action probe} layout {row 0 column 0}}
            dict set invalid handlers probe {arguments {window action} effect unbound};dict set invalid components [list $item]
            switch [string range $kind 9 end] {
                duplicate {dict lappend invalid components $item}
                invalid_parent {dict set item parent absent;dict set invalid components [list $item]}
                missing_handler {dict set invalid handlers {}}
                bad_version {dict set invalid requirements UI_FIELD_API_v1 999}
                bad_callback {dict set invalid handlers probe {arguments wrong effect unbound}}
                bad_property {dict set item properties invented 1;dict set invalid components [list $item]}
            }
            if {![catch {viewerGuiDesignValidate $invalid} observed]} {error {Malformed design was accepted.}}
        } elseif {[string match lifecycle:* $kind]} {
            switch [string range $kind 10 end] {
                mapped {set observed [dict get $inspection viewable];if {!$observed} {error {Viewer is not viewable.}}}
                geometry {set observed [dict get $inspection geometry];if {[winfo width $w]<100 || [winfo height $w]<100} {error {Viewer geometry is not usable.}}}
                focus {set observed [dict get $inspection focus];if {$observed eq {} || ![winfo exists $observed]} {set status BLOCKED}}
                grab {set observed [dict get $inspection grab];if {$observed ne {}} {error {A dialog grab is active; this is not a valid unobstructed comparison.}}}
            }
        } elseif {[string match source:* $kind]} {
            set observed [dict get $inspection components [dict get $case component]]
            if {[dict get $observed status] ne {SOURCE_BOUND}} {set status BLOCKED}
        } else {error {Unknown test case.}}
    } message options]} {set status FAIL;set observed $message}
    dict lappend run cases [dict merge $case [dict create status $status observed $observed owner VIEWER_GUI_HOST_API_v1]]
    dict incr run index;dict set ::GX::ViewerGui::laboratories $id $run
    after 10 [list ::GX::_viewerGuiTestStep $id]
}
proc ::GX::viewerGuiDiagnosticExport {report output callback} {
    if {[file exists $output] || [string bytelength $report]>16777216} {error {Choose a new diagnostic JSON output within the 16 MiB report bound.}}
    set temporary [file join [configurationTempDirectory] viewer-interface-reports [pid]-[clock microseconds].tcldict]
    file mkdir [file dirname $temporary]
    resourceLifecycleWriteBytes $temporary [encoding convertto utf-8 $report]
    return [scriptJobAsync [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python viewer_gui_request.py]] [dict create operation diagnostic_export input $temporary output [file normalize $output]] $callback {timeout_ms 10000 max_bytes 1048576 process_group 1 ui_lifetime 1 label {GUI diagnostic export}}]
}

proc ::GX::viewerGuiLaboratoryDispose {window} {
    dict for {id monitor} $::GX::ViewerGui::monitors {if {[dict get $monitor window] eq $window} {_viewerGuiMonitorFinish $id CLOSED}}
    dict for {id recording} $::GX::ViewerGui::recordings {
        if {[dict get $recording window] ne $window || ![dict get $recording active]} continue
        viewerGuiTraceUnsubscribe [dict get $recording observer]
        dict set ::GX::ViewerGui::recordings $id active 0
        dict set ::GX::ViewerGui::recordings $id termination viewer_closed
    }
    dict for {id run} $::GX::ViewerGui::laboratories {
        if {[dict get $run window] eq $window && ![dict exists $run finished]} {dict set ::GX::ViewerGui::laboratories $id cancelled 1}
    }
}
