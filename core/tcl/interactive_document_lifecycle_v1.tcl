# SPDX-License-Identifier: GPL-3.0-or-later
# Lifecycle notifications are delivered only after canonical deletion, at idle,
# outside Native callback/render transactions. Receipts carry owner identity.
namespace eval ::GX::DocumentLifecycle {variable subscribers {};variable serial 0;variable deliveries {};variable timer ""}
proc ::GX::interactiveDocumentLifecycleSubscribe {callback {ownerWindow ""} {document ""}} {
    variable ::GX::DocumentLifecycle::subscribers;variable ::GX::DocumentLifecycle::serial
    if {$callback eq {}} {error "Document lifecycle callback is required"}
    set token "document-lifecycle#[pid]-[incr serial]"
    set generation "";if {$document ne ""} {set generation [dict get [interactiveDocumentRead $document] generation]}
    dict set subscribers $token [dict create callback $callback session_token [interactiveDocumentSessionToken] owner_window $ownerWindow document_id $document owner_generation $generation notified 0]
    _interactiveDocumentLifecycleWatchStart
    return $token
}
proc ::GX::interactiveDocumentLifecycleUnsubscribe {token} {
    variable ::GX::DocumentLifecycle::subscribers
    if {[dict exists $subscribers $token]} {dict unset subscribers $token}
    if {$subscribers eq {}} {variable ::GX::DocumentLifecycle::timer;if {$timer ne ""} {after cancel $timer;set timer ""}}
}
proc ::GX::_interactiveDocumentLifecycleWatchStart {} {
    variable ::GX::DocumentLifecycle::timer
    if {$timer eq ""} {set timer [after 250 ::GX::_interactiveDocumentLifecycleWatch]}
}
proc ::GX::_interactiveDocumentLifecycleWatch {} {
    variable ::GX::DocumentLifecycle::timer;variable ::GX::DocumentLifecycle::subscribers
    set timer "";_interactiveDocumentSessionChanged
    set lifetime $::GX::DocumentSessionScope::token;set registry {}
    if {$::GX::currentSession ne ""&&[file isdirectory $::GX::currentSession]} {
        if {[catch {set registry [_interactiveDocumentRegistryRead $::GX::currentSession]} message options]} {
            _interactiveDocumentLifecycleWatchStart
            return -options $options "Document lifecycle cannot read the current registry: $message"
        }
    }
    dict for {token subscriber} $subscribers {
        set window [dict get $subscriber owner_window]
        if {$window ne ""&&(![llength [info commands winfo]]||![winfo exists $window])} {dict unset subscribers $token;continue}
        set document [dict get $subscriber document_id]
        if {$document eq ""||[dict get $subscriber notified]} continue
        set event ""
        if {[dict get $subscriber session_token] ne $lifetime} {set event session_changed} elseif {![dict exists $registry $document]} {set event deleted} elseif {[dict get $registry $document generation] ne [dict get $subscriber owner_generation]} {set event owner_replaced}
        if {$event ne ""} {
            dict set subscribers $token notified 1
            _interactiveDocumentDeletedNotify [dict create api_id INTERACTIVE_DOCUMENT_API_v1 api_version 1 event $event document_id $document owner_generation [dict get $subscriber owner_generation] session_token [dict get $subscriber session_token]]
        }
    }
    if {$subscribers ne {}} {_interactiveDocumentLifecycleWatchStart}
}
proc ::GX::_interactiveDocumentDeletedNotify {receipt} {
    variable ::GX::DocumentLifecycle::deliveries;variable ::GX::DocumentLifecycle::serial
    set token "deleted-delivery#[incr serial]"
    dict set deliveries $token $receipt
    after idle [list ::GX::_interactiveDocumentDeletedDeliver $token]
}
proc ::GX::_interactiveDocumentDeletedDeliver {delivery} {
    variable ::GX::DocumentLifecycle::subscribers;variable ::GX::DocumentLifecycle::deliveries
    if {![dict exists $deliveries $delivery]} return
    set event [dict get $deliveries $delivery];dict unset deliveries $delivery
    set current [dict keys $subscribers]
    set failures {};set failureOptions {}
    foreach token $current {
        if {![dict exists $subscribers $token]} continue
        set subscriber [dict get $subscribers $token]
        if {[dict get $subscriber session_token] ne [dict get $event session_token]} continue
        set owner [dict get $subscriber owner_window]
        if {$owner ne ""&&(![llength [info commands winfo]]||![winfo exists $owner])} {dict unset subscribers $token;continue}
        if {[catch {uplevel #0 [list {*}[dict get $subscriber callback] $event]} message options]} {
            # The scientific deletion is already committed. Make a failed view
            # cleanup explicit without reporting a false deletion rollback.
            lappend failures $message;set failureOptions $options
        }
    }
    if {$failures ne {}} {return -options $failureOptions "Document [dict get $event document_id] owner was invalidated; view cleanup failed: [join $failures {; }]"}
}
