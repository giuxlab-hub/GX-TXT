# SPDX-License-Identifier: GPL-3.0-or-later
# Private CORE Library management UI. No Viewer, credential store or transport.
# MAIN owns loader/Configuration adoption. Protected facade F3 remains its gate.
namespace eval ::GX::LibraryCredentialsGUI {
    variable serial 0
    variable dialogs {}
    # One non-secret caller receipt for explicit unknown-outcome reconciliation.
    # Ephemeral UI state only; never a credential, file, Session or Job registry.
    variable lastMutation {}
}
proc ::GX::LibraryCredentialsGUI::_context {} {
    set session {};set token {}
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne {}} {
        set session [file normalize $::GX::currentSession]
        set token [::GX::interactiveDocumentSessionToken]
    }
    return [list [file normalize [::GX::configurationPath]] $session $token]
}
proc ::GX::LibraryCredentialsGUI::_own {w epoch} {
    variable dialogs
    return [expr {[dict exists $dialogs $w] && [dict get $dialogs $w epoch] eq $epoch && [winfo exists $w] && [winfo id $w] eq [dict get $dialogs $w xid]}]
}
proc ::GX::LibraryCredentialsGUI::_alive {w epoch} {
    variable dialogs
    if {![_own $w $epoch]} {return 0}
    set r [dict get $dialogs $w]
    if {[dict get $r invalidated]} {return 0}
    if {![winfo exists [dict get $r parent]] || [winfo id [dict get $r parent]] ne [dict get $r parent_xid]} {return 0}
    if {[catch {_context} context] || $context ne [dict get $r context]} {return 0}
    return 1
}
proc ::GX::LibraryCredentialsGUI::_clear {w {epoch {}}} {
    if {$epoch ne {} && ![_own $w $epoch]} return
    foreach entry [list $w.profile.password $w.profile.confirm $w.profile.secret $w.runtime.password] {
        if {[winfo exists $entry]} {catch {$entry delete 0 end}}
    }
}
proc ::GX::LibraryCredentialsGUI::_message {w epoch message} {
    if {![_own $w $epoch]} return
    if {![_alive $w $epoch]} {set message {Configuration, Session or parent changed. Close and reopen Credential profiles.}}
    $w.status configure -text $message
}
proc ::GX::LibraryCredentialsGUI::_report {w epoch text} {
    if {![_alive $w $epoch]} return
    $w.report configure -state normal
    $w.report delete 1.0 end
    $w.report insert end [string range $text 0 16383]
    $w.report configure -state disabled
}
proc ::GX::LibraryCredentialsGUI::_buttons {w epoch} {
    variable dialogs;variable lastMutation
    if {![_own $w $epoch]} return
    set r [dict get $dialogs $w]
    set enabled [expr {[_alive $w $epoch] && ![dict get $r busy]}]
    foreach button [dict get $r buttons] {$button state [expr {$enabled ? {!disabled} : {disabled}}]}
    set heldUnknown [expr {$lastMutation ne {} && [dict get $lastMutation outcome] eq {unknown}}]
    set unknown [expr {$heldUnknown && [dict get $lastMutation context] eq [dict get $r context]}]
    set pending [expr {$lastMutation ne {} && [dict get $lastMutation outcome] in {prepared dispatched}}]
    if {$heldUnknown || $pending} {foreach button [dict get $r mutating_buttons] {$button state disabled}}
    $w.actions.ack state [expr {$enabled && $unknown && [dict get $r reconciled] eq [dict get $lastMutation operation_id] ? {!disabled} : {disabled}}]
    $w.actions.reconcile state [expr {$enabled && $unknown ? {!disabled} : {disabled}}]
}
proc ::GX::LibraryCredentialsGUI::_invalidate {w epoch} {
    variable dialogs
    if {![_own $w $epoch]} return
    _clear $w $epoch
    dict set dialogs $w invalidated 1
    foreach entry [list $w.profile.password $w.profile.confirm $w.profile.secret $w.runtime.password] {
        if {[winfo exists $entry]} {$entry configure -state disabled}
    }
    if {![dict get $dialogs $w epilogue_pending] && [dict get $dialogs $w operation_ref] ne {}} {
        # A started Finish runs only after the protected action has returned.
        # Before that point only the prearmed epilogue may initiate cleanup.
        catch {::GX::ScientificLibraryManagerAPIv1::_credentialQuarantine [dict get $dialogs $w operation_ref]}
    }
    _message $w $epoch {Configuration, Session or parent changed. Close and reopen Credential profiles.}
    _buttons $w $epoch
}
proc ::GX::LibraryCredentialsGUI::_sessionChanged {args} {
    variable dialogs
    # Actual variable write/unset notification, not a timer or Document watch.
    # Each captured window is checked before clearing its own sensitive inputs.
    dict for {w record} $dialogs {
        catch {
            set epoch [dict get $record epoch]
            if {[_own $w $epoch] && ([lindex $args 2] eq {unset} || [catch {_context} context] || $context ne [dict get $record context])} {_invalidate $w $epoch}
        }
    }
}
proc ::GX::LibraryCredentialsGUI::_sessionTrace {} {
    set callback [list ::GX::LibraryCredentialsGUI::_sessionChanged]
    foreach trace [trace info variable ::GX::currentSession] {
        if {[lsort [lindex $trace 0]] eq {unset write} && [lindex $trace 1] eq $callback} return
    }
    trace add variable ::GX::currentSession {write unset} $callback
}
proc ::GX::LibraryCredentialsGUI::_parentDestroyed {w epoch actual xid} {
    variable dialogs
    if {![dict exists $dialogs $w] || [dict get $dialogs $w epoch] ne $epoch} return
    set record [dict get $dialogs $w]
    if {$actual eq [dict get $record parent] && $xid == [dict get $record parent_xid]} {_close $w $epoch}
}
proc ::GX::LibraryCredentialsGUI::_destroy {w epoch actual} {
    variable dialogs
    if {$actual ne $w || ![dict exists $dialogs $w] || [dict get $dialogs $w epoch] ne $epoch} return
    if {[dict get $dialogs $w closed]} return
    _clear $w $epoch
    set record [dict get $dialogs $w];set parent [dict get $record parent];set tag [dict get $record parent_tag]
    if {[winfo exists $parent] && [winfo id $parent] eq [dict get $record parent_xid]} {
        set tags [bindtags $parent];set index [lsearch -exact $tags $tag]
        if {$index>=0} {bindtags $parent [lreplace $tags $index $index]}
    }
    bind $tag <Destroy> {}
    if {[dict get $record pending_operation] ne {} && [dict get $record operation_ref] ne {}} {
        # Retain only a bounded nonsecret tombstone through final delivery so a
        # bad unlock result can still quarantine its exact captured generation.
        set retained {}
        foreach key {epoch xid parent context pending_operation operation_ref submit_receipt submit_returned epilogue_pending} {dict set retained $key [dict get $record $key]}
        dict set retained closed 1
        dict set dialogs $w $retained
        if {![dict get $record epilogue_pending]} {
            catch {::GX::ScientificLibraryManagerAPIv1::_credentialQuarantine [dict get $record operation_ref]}
        }
    } else {dict unset dialogs $w}
    if {[dict size $dialogs]==0} {
        catch {trace remove variable ::GX::currentSession {write unset} [list ::GX::LibraryCredentialsGUI::_sessionChanged]}
    }
}
proc ::GX::LibraryCredentialsGUI::_close {w epoch} {
    if {![_own $w $epoch]} return
    _clear $w $epoch
    destroy $w
}
proc ::GX::LibraryCredentialsGUI::_profileId {value} {
    return [expr {[string bytelength $value]>=1 && [string bytelength $value]<=64 && [regexp {^[A-Za-z0-9][A-Za-z0-9_.-]*$} $value] && $value ni {. ..}}]
}
proc ::GX::LibraryCredentialsGUI::_libraryId {value} {
    # Existing Library SAFE IDs have no64-byte contract. This private UI admits
    # up to the protected raw-argument bound; the owner checks complete framing.
    return [expr {[string length $value]>=1 && [string length $value]<=32768 && [regexp {^[A-Za-z0-9][A-Za-z0-9_.-]*$} $value] && $value ni {. ..}}]
}
proc ::GX::LibraryCredentialsGUI::_revision {value} {return [regexp {^[0-9a-f]{64}$} $value]}
proc ::GX::LibraryCredentialsGUI::_metadata {value} {
    set out {}
    foreach key {profile_id provider_id generation revision} {
        if {![dict exists $value $key]} {return {}}
        dict set out $key [dict get $value $key]
    }
    if {![_profileId [dict get $out profile_id]] || ![_profileId [dict get $out provider_id]] || ![regexp {^[0-9a-f]{32}$} [dict get $out generation]] || ![_revision [dict get $out revision]]} {return {}}
    return $out
}
proc ::GX::LibraryCredentialsGUI::_binding {value library} {
    set out {}
    foreach key {library_id provider_id authentication credential_profile_id library_revision profile_revision profile_generation profile_state} {
        if {![dict exists $value $key]} {return {}}
        dict set out $key [dict get $value $key]
    }
    if {[dict get $out library_id] ne $library || ![_profileId [dict get $out provider_id]] || ![_revision [dict get $out library_revision]] || [dict get $out authentication] ni {none credential_profile unknown} || [dict get $out profile_state] ni {bound unconfigured unavailable}} {return {}}
    if {[dict get $out credential_profile_id] ne {} && ![_profileId [dict get $out credential_profile_id]]} {return {}}
    foreach key {profile_revision profile_generation} {
        set item [dict get $out $key]
        if {$item in {{} null}} {dict set out $key {};continue}
        if {$key eq {profile_revision} && ![_revision $item]} {return {}}
        if {$key eq {profile_generation} && ![regexp {^[0-9a-f]{32}$} $item]} {return {}}
    }
    return $out
}
proc ::GX::LibraryCredentialsGUI::_failureText {code} {
    switch -- $code {
        invalid_request {return {Check the selected IDs, matching unlock credentials and input bounds.}}
        library_not_found {return {The selected Library is unavailable.}}
        credentials_locked {return {The credential grant is locked.}}
        authentication_required {return {Credentials are required.}}
        authentication_failed {return {Credential authentication failed.}}
        temporarily_unavailable {return {Credential operation is busy or temporarily unavailable.}}
        invalid_provider_configuration {return {The provider or credential configuration is unavailable.}}
        policy_restricted {return {This credential operation is not permitted.}}
        integrity_failure {return {Credential metadata or response integrity could not be verified.}}
        provider_failure - invalid_provider_response {return {The credential provider operation failed.}}
        provider_unavailable - unsupported_operation {return {Protected credential operations are unavailable.}}
        default {return {Protected credential operations are unavailable.}}
    }
}
proc ::GX::LibraryCredentialsGUI::_selected {w epoch} {
    variable dialogs
    if {![_alive $w $epoch]} {_invalidate $w $epoch;return}
    set selection [$w.list selection]
    if {[llength $selection]!=1 || ![dict exists $dialogs $w profiles [lindex $selection 0]]} return
    set profile [dict get $dialogs $w profiles [lindex $selection 0]]
    foreach key {profile_id provider_id} widget {id provider} {
        $w.profile.$widget delete 0 end
        $w.profile.$widget insert 0 [dict get $profile $key]
    }
    dict set dialogs $w profile {}
    _clear $w $epoch
    _message $w $epoch {Profile selected. Inspect it before Replace, Delete or Bind.}
}
proc ::GX::LibraryCredentialsGUI::_operationRef {value} {
    if {[catch {
        if {[lsort [dict keys $value]] ne {context_id generation operation_id}} {return 0}
        if {![regexp {^credential-context-[1-9][0-9]*$} [dict get $value context_id]] || [string length [dict get $value context_id]]>64} {return 0}
        if {![regexp {^[0-9a-f]{32}$} [dict get $value generation]]} {return 0}
        if {![regexp {^credential-operation-[1-9][0-9]*$} [dict get $value operation_id]] || [string length [dict get $value operation_id]]>64} {return 0}
    }]} {return 0}
    return 1
}
proc ::GX::LibraryCredentialsGUI::_sameRef {left right} {
    if {![_operationRef $left] || ![_operationRef $right]} {return 0}
    foreach key {context_id generation operation_id} {if {[dict get $left $key] ne [dict get $right $key]} {return 0}}
    return 1
}
proc ::GX::LibraryCredentialsGUI::_quarantine {packet} {
    if {[dict exists $packet operation_ref]} {
        catch {::GX::ScientificLibraryManagerAPIv1::_credentialQuarantine [dict get $packet operation_ref]}
    }
}
proc ::GX::LibraryCredentialsGUI::_refreshButtons {} {
    variable dialogs
    dict for {w record} $dialogs {catch {_buttons $w [dict get $record epoch]}}
}
# The queued script contains only captured nonsecret caller state. It is armed
# BEFORE getters and is deliberately not cancelled when its window is destroyed.
proc ::GX::LibraryCredentialsGUI::_finishPrepared {packet} {
    variable dialogs
    set w [dict get $packet w];set epoch [dict get $packet epoch]
    set reference [dict get $packet operation_ref]
    set admitted 0
    if {[dict exists $dialogs $w] && [dict get $dialogs $w epoch] eq $epoch && [dict get $dialogs $w xid] eq [dict get $packet xid] && [dict get $dialogs $w pending_operation] eq [dict get $packet gui_operation]} {
        set record [dict get $dialogs $w]
        set receipt [dict get $record submit_receipt]
        if {[dict get $record submit_returned]} {
            if {[catch {
                set admitted [expr {[lsort [dict keys $receipt]] eq {ok operation_ref schema state} &&
                [dict get $receipt schema] eq {gxtxt.library_credential_operation.v1} &&
                [dict get $receipt ok] in {1 true} && [dict get $receipt state] eq {submitted} &&
                [_sameRef [dict get $receipt operation_ref] $reference]}]
            }]} {set admitted 0}
        }
        dict set dialogs $w epilogue_pending 0
        dict set dialogs $w submit_receipt {}
    }
    unset -nocomplain receipt record
    # Every failure/abort uses the independently captured REF, never a field
    # from Submit output. Quarantine preserves the owner's prewrite proof.
    if {!$admitted || [catch {_alive $w $epoch} current] || !$current} {_quarantine $packet}
    set failed [catch {
        set reply [::GX::ScientificLibraryManagerAPIv1::credentialFinish $reference [list ::GX::LibraryCredentialsGUI::_complete $packet]]
    }]
    if {!$failed && ![catch {
        set pending [expr {[lsort [dict keys $reply]] eq {ok operation_ref schema state} &&
            [dict get $reply schema] eq {gxtxt.library_credential_operation.v1} &&
            [dict get $reply ok] in {1 true} && [_sameRef [dict get $reply operation_ref] $reference] &&
            [dict get $reply state] eq {pending}}]
    }] && $pending} {return}
    # A normal immediate refusal is final ordinary data. A malformed/absent
    # receipt cannot choose a cleanup target or certify a mutation's absence.
    if {$failed || [catch {dict get $reply schema} schema] || $schema ne {gxtxt.library_credential_response.v1} ||
        [catch {dict get $reply ok} replyOK] || $replyOK ni {0 false}} {
        _quarantine $packet
        set reply [dict create schema gxtxt.library_credential_response.v1 ok 0 code transport_failure message {The credential operation did not return a verified result.}]
        if {[dict get $packet mutation]} {dict set reply mutation_outcome unknown}
    }
    # Immediate Finish refusal can precede completion ownership (for example a
    # callback-bound refusal). It must not leave an accepted Submit reusable.
    _quarantine $packet
    _complete $packet $reply
}
# Only nonsecret packet/reference arguments enter this helper. No event pump,
# modal UI, scheduling, Tcl encoding/list/B64 helper or response decoding occurs
# from the first getter until this invocation has returned completely.
proc ::GX::LibraryCredentialsGUI::_submitPrepared {packet} {
    variable dialogs
    set w [dict get $packet w];set epoch [dict get $packet epoch]
    set reference [dict get $packet operation_ref]
    set password {};set confirmation {};set secret {};set receipt {};set returned 0
    try {
        if {[dict get $packet action] in {create replace}} {
            set password [$w.profile.password get]
            set confirmation [$w.profile.confirm get]
            set secret [$w.profile.secret get]
            _clear $w $epoch
            if {$password ne $confirmation} {return}
            set receipt [::GX::ScientificLibraryManagerAPIv1::credentialSubmit $reference $password $secret]
        } else {
            set password [$w.runtime.password get]
            _clear $w $epoch
            set receipt [::GX::ScientificLibraryManagerAPIv1::credentialSubmit $reference $password]
        }
        set returned 1
    } on error {ignored} {
        # The already-armed epilogue finishes the independently captured REF.
        # No raw error/options are published, interpreted or used as a target.
    } finally {
        unset -nocomplain password confirmation secret ignored
        # Only the qualified native command's closed metadata result is kept;
        # no caught exception/options or protocol payload enters UI state.
        # Semantic receipt validation is deferred until the whole action ends.
        if {[dict exists $dialogs $w] && [dict get $dialogs $w epoch] eq $epoch && [dict get $dialogs $w pending_operation] eq [dict get $packet gui_operation]} {
            if {$returned && [string length $receipt]<=4096} {
                dict set dialogs $w submit_receipt $receipt
                dict set dialogs $w submit_returned 1
            }
        }
        unset -nocomplain receipt
    }
}
proc ::GX::LibraryCredentialsGUI::_complete {packet response} {
    variable dialogs;variable lastMutation
    set w [dict get $packet w];set epoch [dict get $packet epoch]
    set ownRecord [expr {[dict exists $dialogs $w] && [dict get $dialogs $w epoch] eq $epoch &&
        [dict get $dialogs $w xid] eq [dict get $packet xid] && [dict get $dialogs $w pending_operation] eq [dict get $packet gui_operation]}]
    set ownMutation [expr {[dict get $packet mutation] && $lastMutation ne {} &&
        [dict get $lastMutation operation_id] eq [dict get $packet mutation_id] && ![dict get $lastMutation completed]}]
    if {!$ownRecord && !$ownMutation} {return}
    if {$ownMutation} {dict set lastMutation completed 1}
    try {
        if {![dict get $packet mutation] || $ownMutation} {_applyResult $packet $response}
    } on error {ignored} {
        _quarantine $packet
        if {$ownMutation && [dict get $lastMutation outcome] in {prepared dispatched}} {dict set lastMutation outcome unknown}
        catch {_message $w $epoch {Credential response could not be verified. Inspect current metadata; no rollback is implied.}}
    } finally {
        if {$ownRecord && [dict exists $dialogs $w] && [dict get $dialogs $w epoch] eq $epoch && [dict get $dialogs $w pending_operation] eq [dict get $packet gui_operation]} {
            if {[dict get $dialogs $w closed]} {
                dict unset dialogs $w
                if {[dict size $dialogs]==0} {catch {trace remove variable ::GX::currentSession {write unset} [list ::GX::LibraryCredentialsGUI::_sessionChanged]}}
            } else {
                _clear $w $epoch
                dict set dialogs $w busy 0
                dict set dialogs $w pending_operation {}
                dict set dialogs $w operation_ref {}
            }
        }
        _refreshButtons
    }
}
# This callback receives only widget identity/action. Passwords are never in
# callback arguments, textvariables, dialogs state, labels or diagnostic text.
proc ::GX::LibraryCredentialsGUI::_action {w epoch action} {
    variable dialogs;variable lastMutation;variable serial
    if {![_alive $w $epoch]} {_invalidate $w $epoch;return}
    if {[dict get $dialogs $w busy]} return
    if {$action eq {ack}} {
        if {$lastMutation ne {} && [dict get $lastMutation context] eq [dict get $dialogs $w context] && [dict get $lastMutation outcome] eq {unknown} && [dict get $dialogs $w reconciled] eq [dict get $lastMutation operation_id]} {
            dict set lastMutation outcome unknown_reviewed
            _message $w $epoch {Current inspection observation acknowledged. The prior outcome remains unknown; Replace, Delete or Bind still require successful fresh revision inspection.}
            _refreshButtons
        }
        return
    }
    set originalAction $action;set mutation 0;set target {};set expected {};set provider {};set reconcileId {};set metadata {};set binding {}
    set library [$w.binding.library get];set profile [$w.profile.id get]
    if {$action in {create replace delete bind unbind} && $lastMutation ne {} && [dict get $lastMutation outcome] in {prepared dispatched}} {
        _clear $w $epoch
        _message $w $epoch {Another profile or binding change is awaiting its result.};return
    }
    if {$action in {create replace delete bind unbind} && $lastMutation ne {} && [dict get $lastMutation outcome] eq {unknown}} {
        _clear $w $epoch
        _message $w $epoch {Reconcile the prior unknown mutation in its captured context and acknowledge the observation first.};return
    }
    if {$action eq {reconcile}} {
        if {$lastMutation eq {} || [dict get $lastMutation context] ne [dict get $dialogs $w context] || [dict get $lastMutation outcome] ne {unknown}} return
        set target [dict get $lastMutation target]
        set reconcileId [dict get $lastMutation operation_id]
        if {[dict get $lastMutation action] in {bind unbind}} {set action inspect_binding;set library $target} else {set action inspect;set profile $target}
    }
    if {$action in {inspect create replace delete} && ![_profileId $profile]} {_clear $w $epoch;_message $w $epoch {Enter a valid profile ID (1–64 UTF-8 bytes).};return}
    if {$action in {inspect_binding bind unbind status unlock lock} && ![_libraryId $library]} {_clear $w $epoch;_message $w $epoch {Enter an existing Library ID within the protected input bound.};return}
    if {$action in {replace delete bind}} {
        set metadata [dict get $dialogs $w profile]
        if {$metadata eq {} || [dict get $metadata profile_id] ne $profile} {_clear $w $epoch;_message $w $epoch {Inspect the selected profile to capture its current revision.};return}
        set expected [dict get $metadata revision]
        set provider [dict get $metadata provider_id]
    }
    if {$action in {bind unbind}} {
        set binding [dict get $dialogs $w binding]
        if {$binding eq {} || [dict get $binding library_id] ne $library} {_clear $w $epoch;_message $w $epoch {Inspect this Library binding to capture its current revision.};return}
        if {$action eq {bind} && [dict get $binding provider_id] ne $provider} {_clear $w $epoch;_message $w $epoch {Profile and Library must have the same inspected provider.};return}
        set provider [dict get $binding provider_id]
        set expected [dict create library_revision [dict get $binding library_revision] profile_revision [expr {$action eq {bind} ? $expected : {none}}]]
    }
    if {$action eq {delete}} {
        _clear $w $epoch
        set answer [tk_messageBox -parent $w -type okcancel -default cancel -icon warning -message {Delete this encrypted profile? Existing Library references may become unconfigured.}]
        if {![_alive $w $epoch]} {_invalidate $w $epoch;return}
        if {$answer ne {ok} || [$w.profile.id get] ne $profile} return
    }
    dict set dialogs $w busy 1
    _buttons $w $epoch
    set packet {};set armed 0;set reference {}
    try {
        foreach method {credentialStatus credentialProfileAdmin bindLibraryCredentialProfile credentialLock} {
            if {![llength [info commands ::GX::ScientificLibraryManagerAPIv1::$method]]} {_message $w $epoch {Protected credential operations are unavailable.};return}
        }
        set protected [expr {$action in {create replace unlock}}]
        if {$action in {create replace}} {
            set provider [$w.profile.provider get]
            if {![_profileId $provider]} {_message $w $epoch {Enter a valid installed provider ID.};return}
            if {$action eq {replace} && $provider ne [dict get $metadata provider_id]} {_message $w $epoch {Replacement must retain the inspected provider ID.};return}
        } elseif {$action eq {unlock}} {
            set ttl [$w.runtime.ttl get]
            if {![string is integer -strict $ttl] || $ttl<1 || $ttl>900} {_message $w $epoch {Enter a lifetime of 1–900 seconds.};return}
        }
        if {![_alive $w $epoch]} {_invalidate $w $epoch;return}
        if {$action in {create replace delete bind unbind} && $lastMutation ne {} && [dict get $lastMutation outcome] eq {unknown}} {
            _message $w $epoch {A mutation outcome is unknown. Reconcile that exact operation before another administrative change.};return
        }
        set mutation [expr {$action in {create replace delete bind unbind}}]
        if {$mutation} {
            set target [expr {$action in {bind unbind} ? $library : $profile}]
            set preimage absent
            if {$action eq {create}} {set expected absent
            } elseif {$action in {bind unbind}} {set preimage $binding
            } else {set preimage $metadata}
            set intendedProfile [expr {$action eq {unbind} ? {} : $profile}]
            set lastMutation [dict create operation_id credentials_mutation_[incr serial] context [dict get $dialogs $w context] action $action target $target profile_id $intendedProfile provider_id $provider expected $expected preimage $preimage outcome prepared receipt {} completed 0]
            dict set dialogs $w reconciled {}
        }
        set mutationId [expr {$mutation ? [dict get $lastMutation operation_id] : {}}]
        if {$protected} {
            # Do not carry unrelated editable fields into an owned callback.
            if {$action eq {unlock}} {set profile {}
            } else {set library {}}
        }
        set guiOperation credentials_gui_operation_[incr serial]
        dict set dialogs $w pending_operation $guiOperation
        set packet [dict create w $w epoch $epoch xid [dict get $dialogs $w xid] parent_xid [dict get $dialogs $w parent_xid] context [dict get $dialogs $w context] gui_operation $guiOperation action $action original_action $originalAction mutation $mutation mutation_id $mutationId library $library profile $profile expected $expected provider $provider metadata $metadata reconcile_id $reconcileId]
        if {$protected} {
            foreach method {credentialPrepare credentialSubmit credentialFinish _credentialQuarantine} {
                if {![llength [info commands ::GX::ScientificLibraryManagerAPIv1::$method]]} {
                    _complete $packet [dict create ok 0 code unavailable];return
                }
            }
            if {$action eq {unlock}} {
                set operation unlock;set preparation [dict create library_id $library lifetime_seconds $ttl]
            } else {
                set operation profile_$action
                set preparation [dict create profile_id $profile expected_revision $expected provider_id $provider]
            }
            # All setup/capability/metadata work occurs before any secret getter.
            set prepared [::GX::ScientificLibraryManagerAPIv1::credentialPrepare $operation $preparation]
            if {[catch {
                set valid [expr {[lsort [dict keys $prepared]] eq {ok operation_ref schema state} &&
                    [dict get $prepared schema] eq {gxtxt.library_credential_operation.v1} &&
                    [dict get $prepared ok] in {1 true} && [dict get $prepared state] eq {prepared} &&
                    [_operationRef [dict get $prepared operation_ref]]}]
            }] || !$valid} {
                if {![catch {dict get $prepared schema} schema] && $schema eq {gxtxt.library_credential_response.v1} && ![catch {dict get $prepared ok} ok] && $ok in {0 false}} {
                    _complete $packet $prepared
                } else {_complete $packet [dict create ok 0 code unavailable]}
                return
            }
            set reference [dict get $prepared operation_ref]
            dict set packet operation_ref $reference
            set completion [list ::GX::LibraryCredentialsGUI::_complete $packet]
            if {[string bytelength $completion]>32768} {
                _quarantine $packet
                catch {::GX::ScientificLibraryManagerAPIv1::credentialFinish $reference}
                _complete $packet [dict create schema gxtxt.library_credential_response.v1 ok 0 code invalid_request]
                return
            }
            dict set dialogs $w operation_ref $reference
            dict set dialogs $w submit_receipt {}
            dict set dialogs $w submit_returned 0
            dict set dialogs $w epilogue_pending 1
            # This one script outlives its window. No yielding/reentrant work is
            # permitted after arming until the entire action callback returns.
            after 0 [list ::GX::LibraryCredentialsGUI::_finishPrepared $packet]
            set armed 1
            if {$mutation} {dict set lastMutation outcome dispatched}
            _submitPrepared $packet
            return
        }
        _clear $w $epoch
        if {$mutation} {dict set lastMutation outcome dispatched}
        set failed [catch {
            switch -- $action {
                list {set response [::GX::ScientificLibraryManagerAPIv1::credentialProfileAdmin list]}
                inspect {set response [::GX::ScientificLibraryManagerAPIv1::credentialProfileAdmin inspect $profile]}
                inspect_binding {set response [::GX::ScientificLibraryManagerAPIv1::credentialProfileAdmin inspect_binding $library]}
                delete {set response [::GX::ScientificLibraryManagerAPIv1::credentialProfileAdmin delete $profile $expected]}
                bind {set response [::GX::ScientificLibraryManagerAPIv1::bindLibraryCredentialProfile $library $profile [dict get $expected library_revision] [dict get $expected profile_revision]]}
                unbind {set response [::GX::ScientificLibraryManagerAPIv1::bindLibraryCredentialProfile $library {} [dict get $expected library_revision] none]}
                status {set response [::GX::ScientificLibraryManagerAPIv1::credentialStatus $library]}
                lock {set response [::GX::ScientificLibraryManagerAPIv1::credentialLock $library]}
                default {set response {ok 0 code invalid_request message {Invalid credential request.}}}
            }
        }]
        if {$failed} {
            set response [dict create ok 0 code transport_failure]
            if {$mutation} {dict set response mutation_outcome unknown}
        }
        _complete $packet $response
    } on error {ignored} {
        if {!$armed} {
            if {$reference ne {}} {
                _quarantine $packet
                catch {::GX::ScientificLibraryManagerAPIv1::credentialFinish $reference}
                if {[_own $w $epoch]} {dict set dialogs $w epilogue_pending 0}
            }
            if {$packet ne {}} {
                set failure [dict create ok 0 code transport_failure]
                if {$mutation} {dict set failure mutation_outcome unknown}
                _complete $packet $failure
            } else {_message $w $epoch {Credential operation could not be prepared.}}
        }
    } finally {
        if {!$armed} {
            _clear $w $epoch
            if {[_own $w $epoch]} {dict set dialogs $w busy 0}
            _refreshButtons
        }
    }
}
# This handler receives only an immutable nonsecret caller packet and the final
# response. It is never invoked under a protected Submit Tcl invocation.
proc ::GX::LibraryCredentialsGUI::_applyResult {packet response} {
    variable dialogs;variable lastMutation
    foreach key {w epoch action library profile expected provider metadata mutation} {set $key [dict get $packet $key]}
    set originalAction [dict get $packet original_action];set reconcileId [dict get $packet reconcile_id]
    try {
        set invalid 0
        if {[dict exists $packet operation_ref]} {
            if {[catch {
                if {[dict get $response schema] ne {gxtxt.library_credential_response.v1}} {set invalid 1}
                if {![string is boolean -strict [dict get $response ok]]} {set invalid 1
                } elseif {[dict get $response ok]} {
                    if {[lsort [dict keys $response]] ne {ok result schema}} {set invalid 1}
                } else {
                    foreach key [dict keys $response] {if {$key ni {schema ok code message mutation_outcome}} {set invalid 1}}
                    if {[dict get $response code] ni {invalid_request unavailable credentials_locked busy transport_failure stale_context library_not_found unsupported_operation authentication_required authentication_failed provider_unavailable temporarily_unavailable invalid_provider_configuration integrity_failure policy_restricted provider_failure invalid_provider_response rate_limited read_only entry_not_found}} {set invalid 1}
                    if {[dict exists $response mutation_outcome] && [dict get $response mutation_outcome] ne {unknown}} {set invalid 1}
                }
            }]} {set invalid 1}
        }
        if {$invalid || [catch {dict get $response ok} ok] || ![string is boolean -strict $ok]} {
            _quarantine $packet
            set response {};set ok 0
            if {$mutation} {dict set lastMutation outcome unknown}
            _message $w $epoch [expr {$mutation ? {Mutation outcome unknown. Reconcile current metadata; do not retry or reverse the operation.} : {Protected credential operations are unavailable.}}]
            return
        }
        if {!$ok} {
            set code [expr {[dict exists $response code] ? [dict get $response code] : {integrity_failure}}]
            if {$mutation && [dict exists $response mutation_outcome] && [dict get $response mutation_outcome] eq {unknown}} {
                dict set lastMutation outcome unknown
                _message $w $epoch {Mutation outcome unknown. Use Reconcile; no retry, rollback or absence is implied.}
            } else {
                if {$mutation} {dict set lastMutation outcome acknowledged_refusal}
                _message $w $epoch [_failureText $code]
            }
            if {$originalAction eq {reconcile} && [_alive $w $epoch] && [dict get $lastMutation operation_id] eq $reconcileId} {
                dict set dialogs $w profile {}
                dict set dialogs $w binding {}
                dict set dialogs $w reconciled $reconcileId
                _report $w $epoch [dict create inspection refused code [expr {$code in {invalid_request library_not_found unsupported_operation credentials_locked authentication_required authentication_failed provider_unavailable temporarily_unavailable invalid_provider_configuration integrity_failure policy_restricted provider_failure invalid_provider_response} ? $code : {integrity_failure}}] original_outcome unknown]
                _message $w $epoch {Read-only inspection was refused; current state and prior outcome remain unknown. Acknowledge only this observation. No absence, rollback or retry is implied.}
            }
            return
        }
        if {![dict exists $response result]} {
            _quarantine $packet
            if {$mutation} {dict set lastMutation outcome unknown}
            _message $w $epoch {Credential response could not be verified. Mutation outcome may be unknown; inspect current metadata.};return
        }
        set value [dict get $response result];set safe {}
        switch -- $action {
            create - replace - inspect {
                set safe [_metadata $value]
                if {$action in {create replace} && ([lsort [dict keys $value]] ne {generation profile_id provider_id result_json revision} || [string length [dict get $value result_json]]>16384)} {set safe {}}
                if {$safe ne {} && [dict get $safe profile_id] ne $profile} {set safe {}}
                if {$safe ne {} && $action in {create replace} && [dict get $safe provider_id] ne $provider} {set safe {}}
                if {$safe ne {} && $action eq {replace} && ([dict get $safe revision] eq $expected || [dict get $safe generation] eq [dict get $metadata generation])} {set safe {}}
            }
            inspect_binding {set safe [_binding $value $library]}
            delete {
                if {[dict get $value profile_id] eq $profile && [dict get $value deleted] in {1 true} && [dict get $value previous_revision] eq $expected} {set safe [dict create profile_id $profile deleted 1 previous_revision $expected]}
            }
            bind - unbind {
                set selected [expr {$action eq {bind} ? $profile : {}}]
                if {[dict get $value library_id] eq $library && [dict get $value credential_profile_id] eq $selected && [_revision [dict get $value library_revision]]} {set safe [dict create library_id $library credential_profile_id $selected library_revision [dict get $value library_revision]]}
            }
            list {
                if {[dict exists $value records] && [llength [dict get $value records]]<=64} {
                    set records {};set ids {}
                    foreach item [dict get $value records] {
                        set item [_metadata $item]
                        if {$item eq {} || [dict get $item profile_id] in $ids} {set records {};set ids {};break}
                        lappend records $item;lappend ids [dict get $item profile_id]
                    }
                    if {[llength $records]==[llength [dict get $value records]]} {set safe [dict create records $records]}
                }
            }
            status - unlock - lock {
                if {[lsort [dict keys $value]] eq {authentication_required authentication_status cleanup_pending configured expires_in_seconds library_id result_json} && [string length [dict get $value result_json]]<=16384 && [dict get $value library_id] eq $library && [dict get $value authentication_status] in {not_required unconfigured locked unlocked failed unavailable unknown revoking} && [string is integer -strict [dict get $value expires_in_seconds]] && [dict get $value expires_in_seconds]>=0 && [dict get $value expires_in_seconds]<=900 && [string is boolean -strict [dict get $value cleanup_pending]] && ([dict get $value authentication_status] eq {unlocked} || [dict get $value expires_in_seconds]==0)} {
                    foreach key {configured authentication_required} {
                        set flag [dict get $value $key]
                        if {$flag in {{} null}} {dict set safe $key unknown} elseif {[string is boolean -strict $flag]} {dict set safe $key [expr {$flag ? {yes} : {no}}]} else {set safe {};break}
                    }
                    if {$safe ne {}} {foreach key {library_id authentication_status expires_in_seconds cleanup_pending} {dict set safe $key [dict get $value $key]}}
                    if {$safe ne {} && [dict get $safe authentication_status] eq {unlocked} && ([dict get $safe configured] ne {yes} || [dict get $safe authentication_required] ne {yes} || [dict get $safe cleanup_pending])} {set safe {}}
                }
            }
        }
        if {$safe eq {}} {
            _quarantine $packet
            if {$mutation} {dict set lastMutation outcome unknown}
            _message $w $epoch {Credential response could not be verified. Inspect current metadata before any further mutation.};return
        }
        if {$mutation} {dict set lastMutation outcome committed;dict set lastMutation receipt $safe}
        if {![_alive $w $epoch]} {_invalidate $w $epoch;return}
        if {$action eq {list}} {
            $w.list delete [$w.list children {}]
            dict set dialogs $w profiles {}
            foreach item [dict get $safe records] {
                set row [$w.list insert {} end -values [list [dict get $item profile_id] [dict get $item provider_id] [dict get $item revision]]]
                dict set dialogs $w profiles $row $item
            }
        } elseif {$action in {inspect create replace}} {
            dict set dialogs $w profile $safe
            foreach key {profile_id provider_id} widget {id provider} {
                $w.profile.$widget delete 0 end
                $w.profile.$widget insert 0 [dict get $safe $key]
            }
        } elseif {$action eq {delete}} {dict set dialogs $w profile {}
        } elseif {$action eq {inspect_binding}} {dict set dialogs $w binding $safe
        } elseif {$action in {bind unbind}} {dict set dialogs $w binding {}}
        _report $w $epoch $safe
        if {$originalAction eq {reconcile} && [dict get $lastMutation operation_id] eq $reconcileId} {
            dict set dialogs $w reconciled $reconcileId
            _message $w $epoch {Current metadata read. It cannot prove who caused a change or resolve the old outcome. Review it, then acknowledge before a new explicit action.}
        } elseif {$action eq {unlock}} {
            _message $w $epoch {Credential status returned. Unlock does not test remote sign-in.}
        } elseif {$action in {status lock}} {
            _message $w $epoch {Credential status returned. Revoking or cleanup_pending is not completed cleanup.}
        } elseif {$mutation} {_message $w $epoch {The acknowledged change committed. A later display failure does not roll it back.}
        } else {_message $w $epoch {Current non-secret metadata returned.}}
    } on error {ignored} {
        # Never publish a raw Tcl error/options/provider message. This does not
        # assert that catch clears Tcl internals; the facade's F3 gate owns that.
        _quarantine $packet
        if {$mutation && $lastMutation ne {} && [dict get $lastMutation operation_id] eq [dict get $packet mutation_id] && [dict get $lastMutation outcome] in {prepared dispatched}} {dict set lastMutation outcome unknown}
        _message $w $epoch {Credential UI operation could not be completed. Inspect current metadata; do not assume a mutation was rolled back.}
    } finally {
        unset -nocomplain response value ignored
    }
}
proc ::GX::_scientificLibraryCredentialsDialog {{parent .}} {
    variable ::GX::LibraryCredentialsGUI::serial
    variable ::GX::LibraryCredentialsGUI::dialogs
    variable ::GX::LibraryCredentialsGUI::lastMutation
    if {![winfo exists $parent]} {return {}}
    set context [::GX::LibraryCredentialsGUI::_context]
    ::GX::LibraryCredentialsGUI::_sessionTrace
    dict for {existing record} $dialogs {
        if {[dict get $record parent] eq $parent && [dict get $record context] eq $context && [::GX::LibraryCredentialsGUI::_alive $existing [dict get $record epoch]]} {
            wm deiconify $existing
            raise $existing
            return $existing
        }
    }
    if {[dict size $dialogs]>=4} {return {}}
    set w .gxLibraryCredentialProfiles[incr serial];set epoch credentials_gui_$serial
    toplevel $w
    try {
        wm title $w {Scientific Library credential profiles}
        wm transient $w [winfo toplevel $parent]
        wm minsize $w 720 640
        ttk::label $w.notice -text {Create and manage encrypted profiles, then unlock a Library for a limited time. Stored provider secrets are never displayed.} -wraplength 760
        pack $w.notice -fill x -padx 10 -pady 8
        ttk::treeview $w.list -columns {profile provider revision} -show headings -height 5 -selectmode browse
        foreach {column label width} {profile Profile 160 provider Provider 170 revision Revision 380} {$w.list heading $column -text $label;$w.list column $column -width $width}
        pack $w.list -fill x -padx 10
        ttk::labelframe $w.profile -text {Profile administration — inspect current revision before changing}
        pack $w.profile -fill x -padx 10 -pady 6
        foreach {id label masked} {id {Profile ID} 0 provider {Installed provider ID} 0 password {New unlock credential} 1 confirm {Confirm unlock credential} 1 secret {Provider secret (whole replacement)} 1} {
            set row [expr {[llength [grid slaves $w.profile]]/2}]
            ttk::label $w.profile.${id}Label -text $label
            ttk::entry $w.profile.$id -width 54 -exportselection 0 -validate none
            if {$masked} {
                $w.profile.$id configure -show {*}
                foreach event {<Control-c> <Control-C> <Control-x> <Control-X> <Control-Insert> <Shift-Delete>} {bind $w.profile.$id $event break}
            }
            grid $w.profile.${id}Label -row $row -column 0 -sticky w -padx 5 -pady 2
            grid $w.profile.$id -row $row -column 1 -sticky ew -padx 5 -pady 2
        }
        grid columnconfigure $w.profile 1 -weight 1
        ttk::frame $w.profileActions
        pack $w.profileActions -fill x -padx 10
        set buttons {};set mutations {}
        foreach {id label action} {refresh {Refresh profiles} list inspect Inspect inspect create Create create replace Replace replace delete Delete delete} {
            ttk::button $w.profileActions.$id -text $label -command [list ::GX::LibraryCredentialsGUI::_action $w $epoch $action]
            pack $w.profileActions.$id -side left -padx 3
            lappend buttons $w.profileActions.$id
            if {$action in {create replace delete}} {lappend mutations $w.profileActions.$id}
        }
        ttk::labelframe $w.binding -text {Existing Library binding — explicit revision checks}
        pack $w.binding -fill x -padx 10 -pady 6
        ttk::label $w.binding.label -text {Library ID}
        ttk::entry $w.binding.library -width 35
        pack $w.binding.label $w.binding.library -side left -padx 5
        foreach {id label action} {inspect {Inspect binding} inspect_binding bind {Bind inspected profile} bind unbind Unbind unbind} {
            ttk::button $w.binding.$id -text $label -command [list ::GX::LibraryCredentialsGUI::_action $w $epoch $action]
            pack $w.binding.$id -side left -padx 3
            lappend buttons $w.binding.$id
            if {$action in {bind unbind}} {lappend mutations $w.binding.$id}
        }
        ttk::labelframe $w.runtime -text {Temporary Library access — does not test remote sign-in}
        pack $w.runtime -fill x -padx 10 -pady 6
        ttk::label $w.runtime.label -text {Unlock credential}
        ttk::entry $w.runtime.password -show {*} -exportselection 0 -width 28 -validate none
        foreach event {<Control-c> <Control-C> <Control-x> <Control-X> <Control-Insert> <Shift-Delete>} {bind $w.runtime.password $event break}
        ttk::label $w.runtime.ttlLabel -text {Seconds}
        ttk::entry $w.runtime.ttl -width 5
        $w.runtime.ttl insert 0 300
        pack $w.runtime.label $w.runtime.password $w.runtime.ttlLabel $w.runtime.ttl -side left -padx 4
        foreach {id label} {status Status unlock Unlock lock Lock} {
            ttk::button $w.runtime.$id -text $label -command [list ::GX::LibraryCredentialsGUI::_action $w $epoch $id]
            pack $w.runtime.$id -side left -padx 3
            lappend buttons $w.runtime.$id
        }
        ttk::label $w.status -text {Press Refresh or inspect an existing Library. No operation has run.} -wraplength 760
        pack $w.status -fill x -padx 10 -pady 5
        text $w.report -height 6 -wrap word -state disabled -undo 0 -exportselection 0
        pack $w.report -fill both -expand 1 -padx 10 -pady 4
        ttk::frame $w.actions
        pack $w.actions -fill x -padx 10 -pady 8
        foreach {id label action} {reconcile {Reconcile unknown outcome} reconcile ack {Acknowledge inspection observation} ack} {
            ttk::button $w.actions.$id -text $label -command [list ::GX::LibraryCredentialsGUI::_action $w $epoch $action]
            pack $w.actions.$id -side left -padx 4
        }
        ttk::button $w.actions.close -text Close -command [list ::GX::LibraryCredentialsGUI::_close $w $epoch]
        pack $w.actions.close -side right
        set parentTag GXLibraryCredentialsParent$serial
        dict set dialogs $w [dict create epoch $epoch xid [winfo id $w] parent $parent parent_xid [winfo id $parent] parent_tag $parentTag context $context invalidated 0 closed 0 busy 0 pending_operation {} operation_ref {} submit_receipt {} submit_returned 0 epilogue_pending 0 profile {} binding {} profiles {} reconciled {} buttons $buttons mutating_buttons $mutations]
        bind $w <Destroy> [list ::GX::LibraryCredentialsGUI::_destroy $w $epoch %W]
        bind $parentTag <Destroy> [list ::GX::LibraryCredentialsGUI::_parentDestroyed $w $epoch %W %i]
        bindtags $parent [linsert [bindtags $parent] 0 $parentTag]
        bind $w.list <<TreeviewSelect>> [list ::GX::LibraryCredentialsGUI::_selected $w $epoch]
        wm protocol $w WM_DELETE_WINDOW [list ::GX::LibraryCredentialsGUI::_close $w $epoch]
        if {$lastMutation ne {} && [dict get $lastMutation context] eq $context} {
            ::GX::LibraryCredentialsGUI::_report $w $epoch [dict remove $lastMutation context]
            ::GX::LibraryCredentialsGUI::_message $w $epoch {Last administrative receipt retained in this process. Unknown outcome requires explicit reconciliation; no action was replayed.}
        }
        ::GX::LibraryCredentialsGUI::_buttons $w $epoch
        return $w
    } on error {ignored} {
        ::GX::LibraryCredentialsGUI::_clear $w
        catch {destroy $w}
        catch {dict unset dialogs $w}
        return {}
    }
}
