# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Workbench3D {variable lifecycleSubscription {};variable ownerSession {};variable invalidationAfter {}}
proc ::GX::Workbench3D::documentOwnerInvalidated {event} {
    variable document;variable ownerSession
    if {$document ne [dict get $event document_id]||$ownerSession ne [dict get $event session_token]} return
    disposeInvalidated
}
proc ::GX::Workbench3D::disposeInvalidated {} {
    variable busy;variable invalidationAfter
    if {$busy} {set invalidationAfter [after 50 ::GX::Workbench3D::disposeInvalidated];return}
    set invalidationAfter {};::GX::Engine3D::close
}
proc ::GX::Workbench3D::lifecycleAttach {} {
    variable document;variable lifecycleSubscription;variable ownerSession
    if {$lifecycleSubscription ne {}} {::GX::interactiveDocumentLifecycleUnsubscribe $lifecycleSubscription}
    set ownerSession [::GX::interactiveDocumentSessionToken]
    # The canonical owner survives widget mounting/suspension. Normal close
    # unsubscribes; Session/deletion/generation invalidation still disposes it.
    set lifecycleSubscription [::GX::interactiveDocumentLifecycleSubscribe ::GX::Workbench3D::documentOwnerInvalidated {} $document]
}
rename ::GX::Workbench3D::buildPanel ::GX::Workbench3D::buildPanel_lifecycle_base
proc ::GX::Workbench3D::buildPanel {args} {
    variable panel;variable document;variable lifecycleSubscription;variable ownerSession
    buildPanel_lifecycle_base {*}$args
    ttk::button $panel.documents -text "Interactive Documents…" -command [list ::GX::interactiveDocumentManagerDialog $::GX::Engine3D::window]
    pack $panel.documents -fill x
}
rename ::GX::Workbench3D::close ::GX::Workbench3D::close_lifecycle_base
proc ::GX::Workbench3D::close {} {
    variable lifecycleSubscription;variable invalidationAfter
    if {$lifecycleSubscription ne {}} {::GX::interactiveDocumentLifecycleUnsubscribe $lifecycleSubscription;set lifecycleSubscription {}}
    if {$invalidationAfter ne {}} {after cancel $invalidationAfter;set invalidationAfter {}}
    tailcall close_lifecycle_base
}
