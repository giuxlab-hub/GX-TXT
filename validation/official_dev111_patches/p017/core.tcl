# SPDX-License-Identifier: GPL-3.0-or-later
# Automated CORE contract with real Tcl/Tk windows and synthetic domain hooks.
# Modal answers are explicitly stubbed; this is not real GUI acceptance.
if {[llength $argv] != 2} {error {usage: core.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {
    set ::env($key) [file join $out $key];file mkdir $::env($key)
}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_CORE_CONTRACT__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_HISTORY_CORE
namespace eval ::Q {
    variable state;variable commits;variable accepted;variable restored;variable docs
    variable cancellations {};variable results {};variable errors {};variable trace {};variable timers {}
    variable checks {};variable modalAnswer ok;variable modalCalls {};variable backgroundErrors {}
    variable restoreFail 0;variable captureCount 0
}
proc ::Q::emit {name value} {
    set f [open [file join $::out $name] w]
    try {fconfigure $f -encoding utf-8;puts $f $value} finally {close $f}
}
proc ::Q::check {name condition} {
    if {![uplevel 1 [list expr $condition]]} {error "FAIL: $name"}
    lappend ::Q::checks [dict create name $name status PASS]
    puts "PASS $name";flush stdout
}
proc ::Q::pumpUntil {expression {milliseconds 5000}} {
    set deadline [expr {[clock milliseconds]+$milliseconds}]
    while {![uplevel 1 [list expr $expression]]} {
        if {[clock milliseconds]>=$deadline} {error "Timed out waiting for $expression"}
        after 5 [list set ::Q::tick 1];vwait ::Q::tick;update
    }
}
proc ::Q::validate {record} {
    if {![dict exists $record base value]} {error {Fixture base requires value}}
    return 1
}
proc ::Q::capture {w} {incr ::Q::captureCount;return $::Q::state($w)}
proc ::Q::guard {w} {return [expr {[winfo exists $w] && [info exists ::Q::state($w)]}]}
proc ::Q::restore {w snapshot} {
    lappend ::Q::trace [list restore $w]
    if {$::Q::restoreFail} {set ::Q::restoreFail 0;error {controlled domain restore failure}}
    set ::Q::state($w) $snapshot;incr ::Q::restored($w)
}
proc ::Q::commit {w record} {
    lappend ::Q::trace [list commit $w]
    incr ::Q::commits($w)
    if {[info exists ::Q::docs($w)]} {
        set payload [dict create state [::GX::scientificHistoryState $record] scientific_history $record]
        ::GX::interactiveDocumentUpdate $::Q::docs($w) $payload
    }
}
proc ::Q::accepted {w receipt} {
    # Calling Tk here proves these callbacks execute on the GUI interpreter.
    if {![winfo exists $w]} {error {Acceptance on a destroyed owning window}}
    lappend ::Q::trace [list accepted $w [dict get $receipt revision]]
    lappend ::Q::accepted($w) $receipt
}
proc ::Q::failure {w receipt} {dict set ::Q::errors $w $receipt}
proc ::Q::complete {label result} {dict set ::Q::results $label $result}
proc ::Q::prepare {token input} {
    lappend ::Q::trace [list prepare $token [dict get $input mode]]
    switch [dict get $input mode] {
        deferred {
            dict set ::Q::timers $token [after 15 [list ::GX::scientificHistoryHookComplete $token ok [dict get $input state]]]
        }
        throw {error {controlled asynchronous hook exception}}
        pending {return}
        default {error {Unknown synthetic hook mode}}
    }
}
proc ::Q::cancel {token} {
    lappend ::Q::cancellations $token
    if {[dict exists $::Q::timers $token]} {after cancel [dict get $::Q::timers $token];dict unset ::Q::timers $token}
}
proc ::Q::attach {w {document {}} {overrides {}}} {
    toplevel $w;wm geometry $w 640x360
    set ::Q::state($w) [dict create value 0 stable {inert scientific data café {x} [y]}]
    set ::Q::commits($w) 0;set ::Q::restored($w) 0;set ::Q::accepted($w) {}
    set callbacks [dict create capture [list ::Q::capture $w] restore [list ::Q::restore $w] guard [list ::Q::guard $w] commit [list ::Q::commit $w] accepted [list ::Q::accepted $w] error [list ::Q::failure $w] prepare_async ::Q::prepare cancel ::Q::cancel]
    if {$document ne {}} {dict set callbacks document_id $document;set ::Q::docs($w) $document}
    set callbacks [dict merge $callbacks $overrides]
    return [::GX::scientificHistoryViewerAttach $w fixture.core_history $callbacks]
}
proc ::Q::badNotification {receipt} {error {controlled post-acceptance notification failure}}
proc ::Q::badDescription {row} {error {controlled presentation description failure}}
proc ::Q::semanticDescription {row} {set ::Q::descriptionContext $row;return {}}
rename ::tk_messageBox ::Q::realMessageBox
proc ::tk_messageBox {args} {lappend ::Q::modalCalls $args;return $::Q::modalAnswer}
proc bgerror {message} {lappend ::Q::backgroundErrors $message}
::GX::scientificRecipeHostRegister fixture.core_history [dict create capture ::Q::capture validate ::Q::validate replay ::GX::scientificHistoryState]
set began [clock milliseconds]
try {
    set legacy [::GX::scientificHistoryCreate fixture.core_history {value 0}]
    set legacy [::GX::scientificHistoryAppend fixture.core_history $legacy {value 1} legacy]
    set legacy [::GX::scientificHistoryNavigate fixture.core_history $legacy 0]
    ::Q::check {public dictionary API compatibility} {[dict get [::GX::scientificHistoryState $legacy] value]==0 && [llength [dict get $legacy steps]]==1}
    set legacy [::GX::scientificHistoryBranch fixture.core_history $legacy 0]
    ::Q::check {public dictionary branch preserves base} {[dict get $legacy cursor]==0 && [dict get $legacy steps] eq {}}

    set initial [::Q::attach .core]
    set first [::GX::scientificHistoryViewerStatus .core]
    set ::Q::state(.core) [dict replace $::Q::state(.core) value 1]
    set start [clock microseconds]
    set a [::GX::scientificHistoryViewerRecordOperation .core {Move one}]
    set acceptUs [expr {[clock microseconds]-$start}]
    ::Q::check {fast submission returns explicit RAM acceptance} {[dict get $a accepted] && [dict get $a revision]>[dict get $first revision] && [dict get $a cursor]==1}
    ::Q::check {acceptance avoids legacy persistence commit} {$::Q::commits(.core)==0 && [llength $::Q::accepted(.core)]==1}
    ::Q::check {accepted state is immediately available} {[::GX::scientificHistoryViewerState .core] eq $::Q::state(.core)}
    ::GX::scientificHistoryViewerSubmitPatch .core [dict create value 2 extra 9] {Move two} {operation cad_translate group movement}
    set ::Q::state(.core) [::GX::scientificHistoryViewerState .core]
    set rec [::GX::scientificHistoryViewerRecord .core]
    ::Q::check {patch semantics description and ordering preserved} {[dict get [lindex [dict get $rec steps] 1] description] eq {Move two} && [dict get [lindex [dict get $rec steps] 1] group] eq {movement} && [dict get $rec cursor]==2}
    ::GX::scientificHistoryViewerNavigate .core undo
    ::Q::check {Undo before explicit flush uses RAM inverse} {[dict get $::Q::state(.core) value]==1 && ![dict exists $::Q::state(.core) extra] && [dict get [::GX::scientificHistoryViewerStatus .core] cursor]==1}
    ::GX::scientificHistoryViewerNavigate .core redo
    ::Q::check {Redo immediately restores scientific state} {[dict get $::Q::state(.core) value]==2 && [dict get $::Q::state(.core) extra]==9}
    set prior [::GX::scientificHistoryViewerStatus .core]
    set ::Q::restoreFail 1
    ::Q::check {failed domain restore leaves History cursor unchanged} {[catch {::GX::scientificHistoryViewerNavigate .core undo}] && [dict get [::GX::scientificHistoryViewerStatus .core] revision]==[dict get $prior revision] && [dict get $::Q::state(.core) value]==2}
    ::GX::scientificHistoryViewerBrowse .core 0
    ::Q::check {browse is read-only and does not commit cursor} {![::GX::scientificHistoryViewerEditable .core] && [dict get $::Q::state(.core) value]==0 && [dict get [::GX::scientificHistoryViewerStatus .core] cursor]==2}
    ::Q::check {submission rejected while browsing} {[catch {::GX::scientificHistoryViewerRecordOperation .core forbidden}]}
    ::GX::scientificHistoryViewerNavigate .core latest
    ::Q::check {Latest preserves future History} {[::GX::scientificHistoryViewerEditable .core] && [dict get $::Q::state(.core) value]==2 && [llength [dict get [::GX::scientificHistoryViewerSummary .core] steps]]==2}
    ::GX::scientificHistoryViewerBrowse .core 1
    set ::Q::modalAnswer cancel
    ::GX::scientificHistoryViewerNavigate .core branch
    ::Q::check {cancelled branch preserves future operations} {[dict get [::GX::scientificHistoryViewerStatus .core] count]==2}
    set ::Q::modalAnswer ok
    ::GX::scientificHistoryViewerNavigate .core branch
    ::Q::check {confirmed branch truncates only selected future} {[dict get [::GX::scientificHistoryViewerStatus .core] count]==1 && [::GX::scientificHistoryViewerEditable .core] && [dict get $::Q::state(.core) value]==1}
    ::GX::scientificHistoryViewerSubmitPatch .core {value 3} {Branch edit}
    set ::Q::state(.core) [::GX::scientificHistoryViewerState .core]
    ::Q::check {new branch keeps ordered prior operation} {[dict get [::GX::scientificHistoryViewerStatus .core] count]==2 && [dict get $::Q::state(.core) value]==3}

    set prepared [dict replace $::Q::state(.core) value 4]
    set pending [::GX::scientificHistoryViewerRequest .core [dict create mode deferred state $prepared] {Prepared operation} [list ::Q::complete prepared]]
    ::Q::check {async request returns before hook invocation} {[dict get $pending status] eq {pending} && ![dict exists $::Q::results prepared] && ![::GX::scientificHistoryViewerEditable .core]}
    ::Q::check {pending hook blocks Save and competing append} {[catch {::GX::scientificHistoryViewerFlush .core}] && [catch {::GX::scientificHistoryViewerSubmitPatch .core {value 99} forbidden}]}
    ::Q::pumpUntil {[dict exists $::Q::results prepared]}
    ::Q::check {CORE completes async hook and accepts ordered state} {[dict get $::Q::results prepared accepted] && [dict get [::GX::scientificHistoryViewerState .core] value]==4 && [::GX::scientificHistoryViewerEditable .core]}
    set ::Q::state(.core) [::GX::scientificHistoryViewerState .core]
    set pending [::GX::scientificHistoryViewerRequest .core [dict create mode pending] cancelled [list ::Q::complete cancelled]]
    ::GX::scientificHistoryHookCancel .core
    ::Q::check {CORE cancellation invokes hook and completion once} {[dict get $::Q::results cancelled status] eq {cancelled} && [lindex $::Q::cancellations end] eq [dict get $pending token] && [dict get [::GX::scientificHistoryHookComplete [dict get $pending token] ok {value 88}] status] eq {cancelled}}
    ::GX::scientificHistoryViewerRequest .core [dict create mode throw] failed [list ::Q::complete hookFailed]
    ::Q::pumpUntil {[dict exists $::Q::results hookFailed]}
    ::Q::check {hook exception is reported without scientific mutation} {[dict get $::Q::results hookFailed status] eq {failed} && [dict get [::GX::scientificHistoryViewerState .core] value]==4}

    set path [dict get $::GX::ScientificHistory::viewers .core path]
    set identity [::GX::_historyIdentity fixture.core_history {}]
    lappend identity draft [file tail $path]
    set durableStart [clock microseconds]
    set durable [::GX::scientificHistoryViewerFlush .core]
    set durableUs [expr {[clock microseconds]-$durableStart}]
    ::Q::check {Flush projects once and reports actual durable revision} {[dict get $durable pending]==0 && [dict get $durable accepted_revision]==[dict get $durable durable_revision] && $::Q::commits(.core)==1}
    set exported [::GX::scientificHistoryViewerRecord .core]
    ::Q::check {recovery refuses a journal with a live writer} {[catch {::GX::historyNative recover $path $identity}]}
    ::GX::scientificHistoryViewerFlush .core
    ::Q::check {clean flush does not repeat projection hook} {$::Q::commits(.core)==1}

    set doc [::GX::interactiveDocumentCreate fixture.core_history fixture_history gxtxt.core_history.fixture 1 {state {value 0}}]
    set id [dict get $doc id]
    ::Q::attach .document $id
    ::GX::scientificHistoryViewerSubmitPatch .document {value 8} {Document edit}
    set ::Q::state(.document) [::GX::scientificHistoryViewerState .document]
    ::Q::check {bound operation leaves saved Document untouched until barrier} {$::Q::commits(.document)==0}
    set stored [::GX::interactiveDocumentRead $id]
    ::Q::check {routine stored Document read does not drain History} {$::Q::commits(.document)==0}
    set projected [::GX::interactiveDocumentRead $id current]
    ::Q::check {Document read barrier drains and projects latest History} {[dict get $projected payload state value]==8 && [dict get $projected payload scientific_history cursor]==1 && $::Q::commits(.document)==1}
    set wrong [::GX::interactiveDocumentCreate other.owner fixture_history gxtxt.core_history.fixture 1 {value 0}]
    ::Q::check {Document ownership mismatch rejected} {[catch {::GX::scientificHistoryViewerBindDocument .core [dict get $wrong id]}]}
    ::Q::check {failed Document rebind preserves previous active History} {[::GX::scientificHistoryViewerRecord .core] eq $exported}
    destroy .core
    ::Q::check {recovery reads complete persisted scientific record after close} {[dict get [::GX::historyNative recover $path $identity] record] eq $exported}
    ::Q::attach .stale
    set stale [::GX::scientificHistoryViewerRequest .stale [dict create mode pending] stale [list ::Q::complete stale]]
    set session [file join $out alternate-session];file mkdir $session
    set priorSession $::GX::currentSession
    set ::GX::currentSession $session
    set staleResult [::GX::scientificHistoryHookComplete [dict get $stale token] ok {value 90}]
    ::Q::check {Session switch rejects stale hook completion and edits} {[dict get $staleResult status] eq {failed} && [catch {::GX::scientificHistoryViewerRecordOperation .stale stale}] && [dict get [::GX::scientificHistoryViewerStatus .stale] count]==0}
    set ::GX::currentSession $priorSession
    # A changed Session token remains stale even after returning to the path.
    ::Q::check {Session epoch prevents accidental callback revival} {[catch {::GX::scientificHistoryViewerPrepareEdit .stale}]}
    destroy .stale

    ::Q::attach .warning {} {accepted ::Q::badNotification describe ::Q::badDescription}
    dict set ::Q::state(.warning) value 31
    set warned [::GX::scientificHistoryViewerRecordOperation .warning {Accepted despite optional hook warning}]
    ::Q::check {post-acceptance hook errors do not reject or roll back scientific state} {[dict get $warned accepted] && [dict get $warned hook_failed] && [dict get [::GX::scientificHistoryViewerState .warning] value]==31 && [dict get $::Q::state(.warning) value]==31}
    ::Q::check {optional presentation failure retains fallback row and reports separately} {[dict get [lindex [dict get [::GX::scientificHistoryViewerSummary .warning] steps] end] description] eq {Accepted despite optional hook warning} && ![dict get [::GX::scientificHistoryViewerStatus .warning] failed] && [dict get $::Q::errors .warning stage] eq {callback}}
    ::GX::scientificHistoryViewerFlush .warning
    destroy .warning

    ::Q::attach .semantic {} {describe ::Q::semanticDescription}
    ::GX::scientificHistoryViewerSubmitPatch .semantic {value 41} {Semantic label} {kind domain.operation patch {value 41}}
    ::Q::check {description callback retains semantic patch instead of summary placeholder} {[dict get $::Q::descriptionContext patch value]==41 && [dict get $::Q::descriptionContext description] eq {Semantic label}}
    ::GX::scientificHistoryViewerFlush .semantic
    destroy .semantic

    # Force initial atomic checkpoint publication to fail using an owned
    # directory at the exact worker staging filename; no timing race required.
    set failedDoc [::GX::interactiveDocumentCreate fixture.core_history fixture_history gxtxt.core_history.fixture 1 {state {value 0}}]
    set failedId [dict get $failedDoc id]
    set failedPath [file join $::GX::currentSession metadata history "$failedId.gxh"]
    file mkdir "$failedPath.checkpoint.pending.[pid]"
    ::Q::attach .failed $failedId
    ::Q::check {failed worker I/O is explicit at flush boundary} {[catch {::GX::scientificHistoryViewerFlush .failed}]}
    ::Q::pumpUntil {[dict exists $::Q::errors .failed]}
    set failedStatus [::GX::scientificHistoryViewerStatus .failed]
    ::Q::check {CORE error hook reports failure without durability claim} {[dict get $failedStatus failed] && [dict get $failedStatus durable_revision]==0 && [dict get $::Q::errors .failed failed]}
    ::Q::check {failed worker retains scientific RAM export} {[dict get [::GX::scientificHistoryViewerRecord .failed] base value]==0 && [catch {::GX::scientificHistoryViewerSubmitPatch .failed {value 3} forbidden}]}

    ::Q::check {callbacks produced no unexpected background errors} {$::Q::backgroundErrors eq {}}
    ::Q::emit receipt.tcldict [dict create status PASS_CORE_CONTRACT checks $::Q::checks elapsed_ms [expr {[clock milliseconds]-$began}] acceptance_us $acceptUs durable_flush_us $durableUs callbacks $::Q::trace modal_calls $::Q::modalCalls scope {Automated CORE contract with actual Tcl/Tk windows; modal answers stubbed; not real GUI acceptance}]
    puts {PASS CORE P017 contract}
} on error {message options} {
    ::Q::emit FIRST_FAILURE.tcldict [dict create message $message options $options checks $::Q::checks callbacks $::Q::trace background_errors $::Q::backgroundErrors]
    puts stderr [dict get $options -errorinfo]
    exit 1
}
# Interpreter teardown owns worker drainage; failed worker ownership is retained
# until teardown so no public error is concealed by a destructive cleanup call.
exit 0
