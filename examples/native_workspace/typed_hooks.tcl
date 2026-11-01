# SPDX-License-Identifier: GPL-3.0-or-later
# Optional hooks for a model whose editor already has its own draft state.
# Supply [::WorkspaceExample::hooks] as Compose context.workspace_hooks.
namespace eval ::WorkspaceExample {variable models {};variable commits {}}
proc ::WorkspaceExample::capture {window} {
    variable models
    if {![dict exists $models $window]} {dict set models $window [list object [dict create label {text {001 {a b}}} count {int 0}]]}
    return [dict get $models $window]
}
proc ::WorkspaceExample::validate {typed} {
    if {[lindex $typed 0] ne {object}} {error {The note model must be a typed object}}
    set fields [lindex $typed 1]
    if {[lindex [dict get $fields label] 0] ne {text} || [lindex [dict get $fields count] 0] ne {int} || [lindex [dict get $fields count] 1]<0} {error {The note needs a text label and nonnegative integer count}}
}
proc ::WorkspaceExample::restore {window typed} {validate $typed;variable models;dict set models $window $typed}
proc ::WorkspaceExample::committed {window receipt} {
    if {[dict get $receipt pending] || [dict get $receipt durable_revision]<[dict get $receipt accepted_revision]} {error {Completion requires durable state}}
    variable commits;dict set commits $window $receipt
}
proc ::WorkspaceExample::hooks {} {return [dict create capture ::WorkspaceExample::capture validate ::WorkspaceExample::validate restore ::WorkspaceExample::restore committed ::WorkspaceExample::committed]}
