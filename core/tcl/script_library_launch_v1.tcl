# SPDX-License-Identifier: GPL-3.0-or-later
# Host entrypoint adapter to the single actual compiled Script Library client.
namespace eval ::GX::ScriptLibraryLaunch {variable requests {};variable serial 0;variable pending {};variable observed {}}
proc ::GX::scriptLibraryOpen {{reference {}}} {
    set expected {}
    if {$reference ne {}} {set expected [_scriptRegistryPinned [scriptRegistryDescribe $reference]]}
    set session [_viewerNativeClientSessionToken];set window {}
    dict for {key binding} $::GX::ScriptLibraryHost::bindings {
        lassign $key candidate form
        if {[dict get $binding context module_id] eq {viewer.script_library} && [winfo exists $candidate] && [dict get $binding context session_token] eq $session &&
            ![catch {_viewerGuiScriptLibraryGuard $candidate $form snapshot}]} {set window $candidate;break}
    }
    if {$window eq {} && $::GX::ScriptLibraryLaunch::pending ne {}} {
        lassign $::GX::ScriptLibraryLaunch::pending candidate token lifetime
        if {$token eq $session && [winfo exists $candidate] &&
            [dict exists $::GX::ViewerDevelopment::windows $candidate] && [dict get $::GX::ViewerDevelopment::windows $candidate lifetime]==$lifetime &&
            [dict get $::GX::ViewerDevelopment::windows $candidate status] ni {FAILED REJECTED SOURCE_CHANGED}} {set window $candidate}
    }
    if {$window eq {}} {
        set window [viewerOpen viewer.script_library script_library]
    }
    set lifetime [dict get $::GX::ViewerDevelopment::windows $window lifetime]
    set ::GX::ScriptLibraryLaunch::pending [list $window $session $lifetime]
    _scriptLibraryLaunchObserve $window
    raise $window;focus $window
    if {$reference ne {}} {
        set serial [incr ::GX::ScriptLibraryLaunch::serial]
        dict set ::GX::ScriptLibraryLaunch::requests $window [dict create serial $serial reference $reference expected $expected session $session lifetime $lifetime incarnation {} stage ready deadline [expr {[clock milliseconds]+30000}] status pending]
        after idle [list ::GX::_scriptLibraryLaunchPoll $window $serial]
    }
    return $window
}
proc ::GX::_scriptLibraryLaunchObserve {window} {
    set identity [winfo id $window]
    if {[datasetPublicationV2DictDefault $::GX::ScriptLibraryLaunch::observed $window {}] eq $identity} return
    dict set ::GX::ScriptLibraryLaunch::observed $window $identity
    bind $window <Destroy> +[list ::GX::_scriptLibraryLaunchDestroyed $window %W]
    foreach event {<KeyPress> <ButtonPress>} {bind $window $event +[list ::GX::_scriptLibraryLaunchCancel $window]}
}
proc ::GX::_scriptLibraryLaunchDestroyed {window actual} {
    if {$window ne $actual} return
    catch {dict unset ::GX::ScriptLibraryLaunch::requests $window}
    catch {dict unset ::GX::ScriptLibraryLaunch::observed $window}
    if {[lindex $::GX::ScriptLibraryLaunch::pending 0] eq $window} {set ::GX::ScriptLibraryLaunch::pending {}}
}
proc ::GX::_scriptLibraryLaunchCancel {window} {
    if {[dict exists $::GX::ScriptLibraryLaunch::requests $window] && [dict get $::GX::ScriptLibraryLaunch::requests $window status] eq {pending}} {dict set ::GX::ScriptLibraryLaunch::requests $window status cancelled}
}
proc ::GX::_scriptLibraryLaunchFailure {window message} {
    if {![dict exists $::GX::ScriptLibraryLaunch::requests $window]} return
    dict set ::GX::ScriptLibraryLaunch::requests $window status failed
    dict set ::GX::ScriptLibraryLaunch::requests $window message $message
    if {[dict exists $::GX::ViewerGui::instances $window slots status]} {
        set status [dict get $::GX::ViewerGui::instances $window slots status]
        if {[winfo exists $status]} {$status configure -text $message}
    } elseif {[winfo exists $window.loading]} {$window.loading configure -text $message}
}
proc ::GX::_scriptLibraryLaunchPoll {window serial} {
    variable ::GX::ScriptLibraryLaunch::requests
    if {![dict exists $requests $window] || [dict get $requests $window serial]!=$serial || [dict get $requests $window status] ne {pending}} return
    set request [dict get $requests $window]
    if {![winfo exists $window] || ![dict exists $::GX::ViewerDevelopment::windows $window] ||
        [dict get $::GX::ViewerDevelopment::windows $window lifetime]!=[dict get $request lifetime] ||
        ([dict get $request incarnation] ne {} && [winfo id $window] ne [dict get $request incarnation]) ||
        [_viewerNativeClientSessionToken] ne [dict get $request session]} {_scriptLibraryLaunchCancel $window;return}
    if {[clock milliseconds]>[dict get $request deadline]} {
        _scriptLibraryLaunchFailure $window {Script Library opening timed out; the existing draft is retained.}
        return
    }
    try {
        set native [dict get $::GX::ViewerDevelopment::windows $window]
        if {[dict get $native status] in {FAILED REJECTED SOURCE_CHANGED}} {error {Compiled Script Library admission or event failed; reopen the current module}}
        if {[dict get $native busy] ne {} || [dict get $native status] ne {COMPLETED}} {
            after 25 [list ::GX::_scriptLibraryLaunchPoll $window $serial];return
        }
        # The standard opening shell obtains its final native incarnation
        # during admitted GUI composition. Pin that actual widget only once;
        # the Development lifetime already pins the opening transaction.
        if {[dict get $request incarnation] eq {}} {dict set requests $window incarnation [winfo id $window]}
        _scriptLibraryLaunchObserve $window
        set key {};dict for {candidate binding} $::GX::ScriptLibraryHost::bindings {if {[lindex $candidate 0] eq $window} {set key $candidate;break}}
        if {$key eq {}} {error {Compiled Script Library has no admitted source controller}}
        lassign $key ignored form
        set context [_viewerGuiScriptLibraryGuard $window $form snapshot]
        set reference [dict get $request reference]
        _scriptRegistryExpectedCheck [scriptRegistryDescribe $reference] [dict get $request expected]
        set binding [_scriptLibraryHostGet $key]
        set stage [dict get $request stage]
        if {$stage eq {ready}} {
            foreach {role value} [list scope_filter [lindex [split $reference :] 0] language_filter all search_query {}] {
                viewerGuiDesignValueSet $window [dict get $context component_ids $role] $value
            }
            set action filter_changed;set next page
        } elseif {$stage eq {page}} {
            set tree [uiFieldComponentTableWidget [_scriptLibraryHostWidget $context records]]
            set row {}
            dict for {candidate item} [dict get $binding row_references] {if {$item eq $reference} {set row $candidate;break}}
            if {$row ne {}} {
                $tree selection set $row;$tree see $row
                dict set requests $window selection_sequence_before [dict get $native script_library_sequence]
                set action record_selected;set next selected
            } else {
                set inventory [dict get $binding inventory]
                if {[dict get $inventory offset]+[dict get $inventory limit]>=[dict get $inventory total]} {error {Reviewed Script identity is absent from the current inventory}}
                set action page_next;set next page
            }
        } else {
            set result [nativeWorkspaceDecode [dict get $native script_library_result]]
            if {[dict get $result sequence]<=[dict get $request selection_sequence_before]} {
                after 25 [list ::GX::_scriptLibraryLaunchPoll $window $serial];return
            }
            if {[dict get $result operation] ne {select}} {error {The compiled selection receipt changed; the existing draft is retained}}
            if {[dict get $result status] eq {cancelled}} {dict set requests $window status cancelled;return}
            if {[dict get $result status] ne {completed}} {error [dict get $result error]}
            if {[dict get $binding selected] eq $reference} {
                _scriptRegistryExpectedCheck [dict get $binding baseline] [dict get $request expected]
                dict set requests $window status completed
            } else {dict set requests $window status cancelled}
            return
        }
        set receipt [viewerGuiDesignAction $window $action]
        if {![dict exists $requests $window] || [dict get $requests $window serial]!=$serial || [dict get $requests $window status] ne {pending}} return
        if {[dict get $receipt status] in {failed rejected not_connected}} {error [datasetPublicationV2DictDefault $receipt message {Compiled Script Library command refused}]}
        if {[dict get $receipt status] ne {busy}} {dict set requests $window stage $next}
    } on error {message options} {
        if {[dict exists $requests $window] && [dict get $requests $window serial]==$serial} {_scriptLibraryLaunchFailure $window $message}
        return
    }
    after 25 [list ::GX::_scriptLibraryLaunchPoll $window $serial]
}
