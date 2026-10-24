# SPDX-License-Identifier: GPL-3.0-or-later
# Named CORE contexts own scientific state independently of presentation widgets.
if {[llength $argv]!=2} {error {usage: contexts.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_NAMED_CONTEXTS__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_NAMED_HISTORY_CONTEXTS
namespace eval ::TC {variable state;variable context;variable commits;variable accepted;variable restored;variable callbacks;variable checks {};variable events {};variable errors {};variable background {};variable live {}}
proc ::TC::emit {name value} {set f [open [file join $::out $name.tcldict] w];try {fconfigure $f -encoding utf-8;puts $f $value} finally {::close $f}}
proc ::TC::check {condition message} {if {![uplevel 1 [list expr $condition]]} {error "FAIL: $message"};lappend ::TC::checks $message;emit checks $::TC::checks;puts "PASS: $message";flush stdout}
proc ::TC::validate {record} {if {![dict exists $record base value]} {error {Synthetic domain requires value}};return 1}
proc ::TC::capture {label} {return $::TC::state($label)}
proc ::TC::guard {label} {return [info exists ::TC::state($label)]}
proc ::TC::restore {label value} {
    set ::TC::state($label) $value;incr ::TC::restored($label)
    set mode attach
    if {[info exists ::TC::context($label)] && [dict exists $::GX::ScientificHistory::viewers $::TC::context($label)]} {set mode [dict get [::GX::scientificHistoryViewerRestoreContext $::TC::context($label)] mode]}
    lappend ::TC::events [list restore $label $mode]
}
proc ::TC::accepted {label receipt} {lappend ::TC::accepted($label) [list [dict get $receipt revision] [dict get $receipt cursor] [dict get $receipt count]]}
proc ::TC::failure {label receipt} {dict set ::TC::errors $label $receipt}
proc ::TC::commit {label document channel record} {
    incr ::TC::commits($label)
    if {$document ne {}} {
        set payload [dict get [::GX::interactiveDocumentRead $document] payload]
        dict set payload channels $channel [dict create state [::GX::scientificHistoryState $record] history $record]
        ::GX::interactiveDocumentUpdate $document $payload
    }
}
proc ::TC::callbacks {label document channel} {
    set ::TC::state($label) [dict create value 0 retained {inert scientific identity café {x} [y]}]
    set ::TC::commits($label) 0;set ::TC::accepted($label) {};set ::TC::restored($label) 0
    set result [dict create capture [list ::TC::capture $label] restore [list ::TC::restore $label] guard [list ::TC::guard $label] commit [list ::TC::commit $label $document $channel] accepted [list ::TC::accepted $label] error [list ::TC::failure $label] channel $channel recovery_choice recover]
    if {$document ne {}} {dict set result document_id $document}
    set ::TC::callbacks($label) $result
    return $result
}
proc ::TC::attach {label document channel {record {}}} {
    set cb [callbacks $label $document $channel]
    set ::TC::context($label) [::GX::scientificHistoryContextAttach fixture.named_history $cb $record]
    lappend ::TC::live $::TC::context($label)
    return $::TC::context($label)
}
proc ::TC::append {label value} {
    dict set ::TC::state($label) value $value
    return [::GX::scientificHistoryViewerRecordOperation $::TC::context($label) "Set $label to $value"]
}
proc ::TC::closeContext {label {project 1}} {::GX::scientificHistoryContextClose $::TC::context($label) $project}
proc ::TC::pumpUntil {condition {milliseconds 5000}} {set deadline [expr {[clock milliseconds]+$milliseconds}];while {![uplevel 1 [list expr $condition]]} {if {[clock milliseconds]>$deadline} {error "Timed out: $condition"};set ::TC::tick 0;after 10 {set ::TC::tick 1};vwait ::TC::tick;update}}
proc bgerror {message} {lappend ::TC::background [dict create message $message details $::errorInfo]}
::GX::scientificRecipeHostRegister fixture.named_history [dict create capture ::TC::capture validate ::TC::validate replay ::GX::scientificHistoryState]
set pins {}
foreach relative {core/history/libgxtxt_history.so core/tcl/scientific_history_native.tcl core/tcl/scientific_recipe_history.tcl core/tcl/interactive_document_api_v1.tcl} {dict set pins $relative [::GX::sha256File [file join $framework $relative]]}
::TC::emit source_pins $pins
try {
    ::TC::check {![llength [info commands winfo]] && [package provide Tk] eq {}} {Initial named-context contract starts without Tk or hidden widgets}
    set doc [::GX::interactiveDocumentCreate fixture.named_history fixture_context gxtxt.context.fixture.v1 1 {channels {}}];set document [dict get $doc id]
    set a [::TC::attach A $document alpha];set b [::TC::attach B $document beta]
    ::TC::check {[string match history-context#* $a] && [string match history-context#* $b] && $a ne $b} {CORE creates distinct nonwindow context identities}
    ::TC::append A 1;::TC::append B 10;::TC::append A 2;::TC::append B 11
    ::TC::check {[dict get [::GX::scientificHistoryViewerStatus $a] count]==2 && [dict get [::GX::scientificHistoryViewerStatus $b] count]==2} {Two channels on one Document keep independent operation ordering}
    ::TC::check {[dict get [::GX::scientificHistoryViewerState $a] value]==2 && [dict get [::GX::scientificHistoryViewerState $b] value]==11} {Same-Document channels retain independent authoritative scientific states}
    ::TC::check {$::TC::commits(A)==0 && $::TC::commits(B)==0} {Headless acceptance avoids synchronous Document projection}
    update
    ::TC::check {![llength [info commands winfo]] && $::TC::background eq {}} {Headless lifecycle callbacks do not require a hidden Tk host}
    set betaBefore [::GX::scientificHistoryViewerStatus $b]
    for {set value 3} {$value<=42} {incr value} {::TC::append A $value}
    set closingStatus [::GX::scientificHistoryViewerStatus $a]
    set recordA [::GX::scientificHistoryViewerRecord $a];set recordB [::GX::scientificHistoryViewerRecord $b]
    set pathA [file join $::GX::currentSession metadata history "$document.alpha.gxh"]
    set pathB [file join $::GX::currentSession metadata history "$document.beta.gxh"]
    ::TC::closeContext A
    ::TC::check {![dict exists $::GX::ScientificHistory::viewers $a] && [dict get [::GX::scientificHistoryViewerStatus $b] revision]==[dict get $betaBefore revision]} {Close drains its accepted queue without changing the other channel}
    set recoveredA [::GX::historyNative recover $pathA [::GX::_historyIdentity fixture.named_history $document alpha]]
    ::TC::check {[dict get $recoveredA record] eq $recordA && [dict get $recoveredA durable_revision]==[dict get $closingStatus accepted_revision]} {Close preserves every accepted operation and reports verifiable durable recovery}
    ::TC::closeContext B
    set recoveredB [::GX::historyNative recover $pathB [::GX::_historyIdentity fixture.named_history $document beta]]
    ::TC::check {[dict get $recoveredB record] eq $recordB && [dict get [::GX::scientificHistoryState [dict get $recoveredB record]] value]==11} {The second channel recovers its own sequence independently}
    set stored [dict get [::GX::interactiveDocumentRead $document] payload]
    ::TC::check {[dict get $stored channels alpha state value]==42 && [dict get $stored channels beta state value]==11} {Ordered channel projection preserves both scientific ownership contracts}
    set a [::TC::attach A $document alpha $recordA]
    ::TC::check {[dict get [::GX::scientificHistoryViewerState $a] value]==42} {A named context reopens its verified channel without GUI intervention}
    set foreign [::GX::interactiveDocumentCreate foreign.owner fixture_context gxtxt.context.fixture.v1 1 {channels {}}]
    set before [::GX::scientificHistoryViewerStatus $a]
    ::TC::check {[catch {::GX::scientificHistoryViewerBindDocument $a [dict get $foreign id]}] && [::GX::scientificHistoryViewerRecord $a] eq $recordA && [dict get [::GX::scientificHistoryViewerStatus $a] revision]==[dict get $before revision]} {Wrong-owner bind leaves the original named History active and unchanged}
    ::TC::append A 43;set latestA [::GX::scientificHistoryViewerRecord $a];::TC::closeContext A 0
    set a [::TC::attach A $document alpha $recordA]
    ::TC::check {[::GX::scientificHistoryViewerRecord $a] eq $latestA && [dict get $::TC::state(A) value]==43} {Explicit headless recovery choice adopts the newer channel and restores its domain state}
    ::TC::closeContext A

    set d [::TC::attach Draft {} draftCase]
    set draftPath [dict get $::GX::ScientificHistory::viewers $d path]
    ::TC::append Draft 1;::TC::append Draft 3
    ::TC::check {[::GX::scientificHistoryDrafts fixture.named_history draftCase] eq {}} {Discovery does not offer a draft that still has an active writer}
    ::GX::scientificHistoryViewerBindDocument $d $document
    ::GX::scientificHistoryViewerFlush $d 30000 0
    ::TC::check {![file exists $draftPath] && ![file exists "$draftPath.checkpoint"] && [llength [glob -nocomplain "$draftPath.bound-*" "$draftPath.checkpoint.bound-*"]]>0} {Successful Document bind retires the former draft journals as evidence}
    ::TC::check {[::GX::scientificHistoryDrafts fixture.named_history draftCase] eq {}} {Bound draft is absent from future unsaved-draft recovery discovery}
    set cb [::TC::callbacks Fresh {} draftCase];dict set cb recovery_choice cancel
    set fresh [::GX::scientificHistoryContextAttach fixture.named_history $cb]
    set ::TC::context(Fresh) $fresh;lappend ::TC::live $fresh
    ::TC::check {[dict get [::GX::scientificHistoryViewerStatus $fresh] count]==0 && [dict get [::GX::scientificHistoryViewerState $fresh] value]==0} {A genuinely new draft starts without a false recovery offer from the bound draft}
    ::TC::closeContext Fresh 0;::TC::closeContext Draft 0
    ::TC::check {![llength [info commands winfo]] && [package provide Tk] eq {}} {All channel/draft operations and drainage remain genuinely headless}

    package require Tk;wm withdraw .
    toplevel .parentA;wm geometry .parentA 400x220;update
    set beforeWidgets [winfo children .]
    set p [::TC::attach Parent $document parentCase]
    ::GX::scientificHistoryContextSetParent $p .parentA
    ::TC::check {[winfo children .] eq $beforeWidgets && ![winfo exists $p]} {Attaching a presentation parent creates no hidden context widgets}
    ::TC::check {[::GX::_historyDialogParent $p] eq {.parentA}} {Named context uses its explicit owning presentation parent}
    ::TC::append Parent 5;destroy .parentA;update
    ::TC::check {[dict get [::GX::scientificHistoryViewerStatus $p] count]==1 && [dict get [::GX::scientificHistoryViewerState $p] value]==5} {Destroying presentation leaves scientific context and accepted state alive}
    toplevel .parentB
    ::GX::scientificHistoryContextSetParent $p .parentB
    ::TC::check {[::GX::_historyDialogParent $p] eq {.parentB} && [catch {::GX::scientificHistoryContextSetParent $p .missing}] && [::GX::_historyDialogParent $p] eq {.parentB}} {Reparenting is explicit and rejects a missing parent without corrupting ownership}
    ::GX::scientificHistoryViewerDetach $p 0;destroy .parentB
    ::TC::check {![dict exists $::GX::ScientificHistory::viewers $p]} {ViewerDetach releases a named context without a hidden-window lifetime}

    toplevel .actual
    set cb [::TC::callbacks Actual $document actualWindow];dict set cb parent .actual
    ::GX::scientificHistoryViewerAttach .actual fixture.named_history $cb
    set ::TC::context(Actual) .actual;lappend ::TC::live .actual
    ::TC::append Actual 1
    set status [::GX::scientificHistoryViewerStatus .actual];set restoreCount $::TC::restored(Actual)
    ::TC::check {[catch {::GX::scientificHistoryViewerSeek .actual 0 0}] && [dict get [::GX::scientificHistoryViewerStatus .actual] revision]==[dict get $status revision]} {Seek without restoration rejects a mismatched live scientific state atomically}
    dict set ::TC::state(Actual) value 0
    ::GX::scientificHistoryViewerSeek .actual 0 0
    ::TC::check {[dict get [::GX::scientificHistoryViewerStatus .actual] cursor]==0 && $::TC::restored(Actual)==$restoreCount} {Seek can adopt an already restored checkpoint without rerunning a domain hook}
    ::GX::scientificHistoryViewerSeek .actual 1
    ::TC::check {[dict get $::TC::state(Actual) value]==1 && [lindex [lindex $::TC::events end] 2] eq {seek}} {Restoring Seek invokes the owning-thread hook with explicit CORE mode}
    dict set ::TC::state(Actual) value 9
    ::GX::scientificHistoryViewerReset .actual $::TC::state(Actual)
    ::TC::check {[dict get [::GX::scientificHistoryViewerStatus .actual] count]==0 && [dict get [::GX::scientificHistoryViewerState .actual] value]==9} {Reset creates a single retained current checkpoint through CORE}
    ::GX::scientificHistoryViewerDetach .actual 0
    ::TC::check {[winfo exists .actual] && ![dict exists $::GX::ScientificHistory::viewers .actual]} {ViewerDetach releases History independently of its real GUI widget}
    destroy .actual;update

    set s [::TC::attach Session $document sessionCase];::TC::append Session 7
    set originalSession $::GX::currentSession
    set alternate [file join $out alternate-session];file mkdir $alternate
    set ::GX::currentSession $alternate
    ::TC::check {[catch {::TC::append Session 8}] && [dict get [::GX::scientificHistoryViewerState $s] value]==7} {Session change rejects named-context edits while retaining the old accepted state}
    ::TC::check {[catch {::GX::scientificHistoryContextClose $s}] && [dict exists $::GX::ScientificHistory::viewers $s]} {Close refuses stale-Session projection and retains the accepted context}
    set ::GX::currentSession $originalSession
    ::TC::check {[catch {::GX::scientificHistoryViewerPrepareEdit $s}]} {Returning to the same path does not revive a stale Session epoch}
    ::TC::closeContext Session 0
    ::TC::check {![dict exists $::GX::ScientificHistory::viewers $s]} {Nonprojecting Close safely drains the original Session journal}

    set f [::TC::attach Failed $document failedClose]
    ::GX::scientificHistoryViewerFlush $f 30000 0
    ::TC::append Failed 17
    set path [dict get $::GX::ScientificHistory::viewers $f path]
    set fault "$path.checkpoint.pending.[pid]";file mkdir $fault
    set h [dict get $::GX::ScientificHistory::viewers $f handle]
    ::GX::historyNative checkpoint $h
    ::TC::check {[catch {::GX::scientificHistoryContextClose $f} errorMessage] && [dict exists $::GX::ScientificHistory::viewers $f]} {Failed I/O on Close is explicit and keeps its context available for recovery}
    ::TC::pumpUntil {[dict exists $::TC::errors Failed]}
    set failure [::GX::scientificHistoryViewerStatus $f]
    ::TC::check {[dict get $failure failed] && [dict get $failure durable_revision]<[dict get $failure accepted_revision]} {Failed checkpoint never claims durability of its accepted revision}
    ::TC::check {[dict get [::GX::scientificHistoryViewerState $f] value]==17 && [dict get [::GX::scientificHistoryState [::GX::scientificHistoryViewerRecord $f]] value]==17} {Failed Close preserves authoritative scientific RAM state and explicit export}
    ::TC::check {[winfo children .] eq {} && $::TC::background eq {}} {Named lifecycle tests leave no hidden widgets or Tcl/Tk background failures}
    ::TC::emit receipt [dict create status PASS_NAMED_CONTEXTS framework $framework checks $::TC::checks close_pending_observed [dict get $closingStatus pending] accepted_before_close [dict get $closingStatus accepted_revision] recovered_after_close [dict get $recoveredA durable_revision] failed_close $failure callbacks $::TC::events failed_RAM [::GX::scientificHistoryViewerRecord $f] scope {Focused named-context/channel/lifecycle contract; no native framing stress or Curve Workbench execution}]
    puts {PASS NAMED CORE CONTEXTS}
} on error {message options} {
    ::TC::emit FIRST_FAILURE [dict create message $message options $options checks $::TC::checks callbacks $::TC::events errors $::TC::errors background $::TC::background]
    puts stderr [dict get $options -errorinfo]
    exit 1
}
# Keep failed scientific RAM inspectable until interpreter teardown; worker errors
# are evidence, not permission to discard accepted operations or claim durability.
exit 0
