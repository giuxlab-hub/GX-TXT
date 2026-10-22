# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::DocumentManager {variable state}
proc ::GX::interactiveDocumentManagerDialog {{parent .}} {
    variable ::GX::DocumentManager::state
    set w .interactiveDocumentManager
    if {[winfo exists $w]} {raise $w;return $w}
    set state(token) [interactiveDocumentSessionToken];set state(rows) {};set state(status) "Select a document to inspect its owner and deletion scope."
    toplevel $w;wm title $w "Interactive Documents";wm geometry $w 950x470;wm minsize $w 520 320
    if {[winfo exists $parent]&&[winfo viewable $parent]} {wm transient $w $parent}
    ttk::label $w.intro -text "Documents belong to this Session. Deleting one closes its live views and removes its unreferenced owned resources." -wraplength 900
    pack $w.intro -fill x -padx 12 -pady 12
    ttk::frame $w.actions;pack $w.actions -side bottom -fill x -padx 12 -pady 12
    foreach {key label command} {refresh Refresh ::GX::_interactiveDocumentManagerRefresh delete {Delete selected document…} ::GX::_interactiveDocumentManagerDelete} {ttk::button $w.actions.$key -text $label -command $command;pack $w.actions.$key -side left -padx 4}
    ttk::button $w.actions.close -text Close -command [list destroy $w];pack $w.actions.close -side right
    ttk::label $w.status -textvariable ::GX::DocumentManager::state(status) -wraplength 900;pack $w.status -side bottom -fill x -padx 12 -pady 8
    ttk::frame $w.list;pack $w.list -fill both -expand 1 -padx 12
    ttk::treeview $w.tree -columns {id owner provider revision format} -show headings -selectmode browse
    foreach {key label width} {id {Document ID} 140 owner {Owner module} 240 provider Provider 160 revision Revision 80 format Format 220} {
        set minimum [expr {[font measure TkHeadingFont $label]+24}]
        $w.tree heading $key -text $label;$w.tree column $key -width [expr {max($width,$minimum)}] -minwidth $minimum
    }
    ttk::scrollbar $w.sy -orient vertical -command [list $w.tree yview];ttk::scrollbar $w.sx -orient horizontal -command [list $w.tree xview]
    $w.tree configure -yscrollcommand [list $w.sy set] -xscrollcommand [list $w.sx set]
    grid $w.tree -in $w.list -row 0 -column 0 -sticky nsew;grid $w.sy -in $w.list -row 0 -column 1 -sticky ns;grid $w.sx -in $w.list -row 1 -column 0 -sticky ew
    grid columnconfigure $w.list 0 -weight 1;grid rowconfigure $w.list 0 -weight 1
    bind $w.tree <<TreeviewSelect>> ::GX::_interactiveDocumentManagerSelected
    bind $w <Escape> [list destroy $w]
    bind $w <Configure> [list ::GX::_interactiveDocumentManagerLayout %W %w]
    bind $w <Destroy> [list ::GX::_interactiveDocumentManagerDestroy %W]
    _interactiveDocumentManagerRefresh;return $w
}
proc ::GX::_interactiveDocumentManagerLayout {widget width} {
    if {$widget ne ".interactiveDocumentManager"} return
    set wrap [expr {max(100,$width-24)}]
    $widget.intro configure -wraplength $wrap;$widget.status configure -wraplength $wrap
}
proc ::GX::_interactiveDocumentManagerDestroy {widget} {
    variable ::GX::DocumentManager::state
    if {$widget eq ".interactiveDocumentManager"} {array unset state}
}
proc ::GX::_interactiveDocumentManagerRefresh {} {
    variable ::GX::DocumentManager::state
    set w .interactiveDocumentManager;if {![winfo exists $w]} return
    set state(token) [interactiveDocumentSessionToken];set state(rows) {}
    foreach column [$w.tree cget -columns] {
        set minimum [expr {[font measure TkHeadingFont [$w.tree heading $column -text]]+24}]
        $w.tree column $column -minwidth $minimum
        if {[$w.tree column $column -width]<$minimum} {$w.tree column $column -width $minimum}
    }
    $w.tree delete [$w.tree children {}]
    foreach item [interactiveDocumentList] {
        set id [dict get $item id];dict set state(rows) $id $item
        $w.tree insert {} end -id $id -values [list $id [dict get $item module_id] [dict get $item provider_id] [dict get $item revision] [dict get $item format]]
    }
    set state(status) "[dict size $state(rows)] Interactive Document(s) in the current Session."
}
proc ::GX::_interactiveDocumentManagerSelected {} {
    variable ::GX::DocumentManager::state
    set selected [.interactiveDocumentManager.tree selection];if {[llength $selected]!=1} return
    set item [dict get $state(rows) [lindex $selected 0]]
    set state(status) "[dict get $item id] — [dict get $item module_id] / [dict get $item provider_id] — revision [dict get $item revision]. Source Datasets and published scientific results are retained."
}
proc ::GX::_interactiveDocumentManagerDelete {} {
    variable ::GX::DocumentManager::state
    set w .interactiveDocumentManager;set selected [$w.tree selection]
    if {[llength $selected]!=1} {set state(status) "Select one document to delete.";return}
    set id [lindex $selected 0]
    if {[catch {
        set reviewedToken $state(token)
        if {$reviewedToken ne [interactiveDocumentSessionToken]} {error "Session lifetime changed; refresh the document list before deleting"}
        set captured [dict get $state(rows) $id];set current [interactiveDocumentRead $id]
        foreach field {generation revision} {if {[dict get $captured $field] ne [dict get $current $field]} {error "Document changed; refresh and review its current revision before deleting"}}
    } message]} {set state(status) $message;return}
    set message "Delete document '$id' owned by [dict get $captured module_id]?\n\nIts live views will close. Unreferenced owned geometry/resources and its recovery journal will be removed. Source Datasets and already published results remain available; their retained provenance resources are preserved."
    if {[tk_messageBox -parent $w -title "Delete Interactive Document" -type yesno -default no -icon warning -message $message] ne "yes"} return
    # The confirmation runs a nested event loop. Refresh may replace manager
    # state, so compare the immutable review snapshot before deleting anything.
    if {![winfo exists $w] || ![winfo exists $w.tree] || ![info exists state(token)]} return
    if {[catch {
        if {$reviewedToken ne [interactiveDocumentSessionToken]} {error "Session lifetime changed; refresh the document list before deleting"}
        set current [interactiveDocumentRead $id]
        foreach field {generation revision} {if {[dict get $captured $field] ne [dict get $current $field]} {error "Document changed; refresh and review its current revision before deleting"}}
    } message]} {set state(status) $message;return}
    wm transient $w {}
    if {[catch {interactiveDocumentDelete $id} message options]} {
        if {[dict get $options -errorcode] eq {GX DOCUMENT DELETE_COMMITTED}} {_interactiveDocumentManagerRefresh;set state(status) $message} else {set state(status) "Deletion failed: $message"}
        return
    }
    _interactiveDocumentManagerRefresh;set state(status) "Deleted $id. Source Datasets and published results are preserved."
}
