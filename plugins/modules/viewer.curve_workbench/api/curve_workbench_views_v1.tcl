# SPDX-License-Identifier: GPL-3.0-or-later
# Native snapshots own coordinate/presentation validation and dimensional scaling.
proc ::GX::CurveWorkbench::_savedViewCapture {w} {
    variable st
    set visibility {};set units {};set groups {};set layers {}
    dict for {id record} $st($w,curves) {dict set visibility $id [dict get $record visible];dict set units $id [_coordinateUnits $record]}
    dict for {id record} $st($w,groups) {dict set groups $id [dict get $record visible]}
    dict for {id record} $st($w,layers) {dict set layers $id [dict get $record properties visible]}
    return [dict create view_state [::GX::Native2D::core view_state $st($w,scene)] curve_visibility $visibility group_visibility $groups layer_visibility $layers coordinate_units $units]
}
proc ::GX::CurveWorkbench::_savedViewRefresh {w} {
    variable st
    if {![winfo exists $w.savedViews.tree]} return
    set tree $w.savedViews.tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} $st($w,savedViews) {
        set state [dict get $record snapshot view_state]
        $tree insert {} end -id $id -values [list $id [dict get $record name] [dict get $state coordinate_mode] [dict get $state aspect] [lindex [dict get $state viewport] 6]]
    }
    _inspectionColumnsFit $tree;foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
}
proc ::GX::CurveWorkbench::_savedViewOpen {w} {
    set d $w.savedViews
    if {[winfo exists $d]} {raise $d;_savedViewRefresh $w;return}
    toplevel $d;wm title $d "Saved views / bookmarks";wm transient $d $w;wm geometry $d 1000x430
    ttk::label $d.help -text {Capture bounds, zoom/pan, coordinate frame, grid, aspect, background and curve/group/layer visibility. Restore preserves geometry, point identities and selection. Changed coordinate units require an explicit view update; missing presentation references are reported.} -wraplength 920 -padding 8
    bind $d.help <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $d.help %w];pack $d.help -side top -fill x
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label callback} [list create {Capture current view…} [list _savedViewForm $w create] update {Update from current view…} [list _savedViewForm $w update] rename {Rename…} [list _savedViewForm $w rename] restore Restore [list _savedViewRestore $w] remove Remove [list _savedViewRemove $w]] {
        set callback [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]];ttk::button $d.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $callback];pack $d.actions.$key -side left -padx 4
    }
    ttk::button $d.actions.close -text Close -command [list destroy $d];pack $d.actions.close -side right;bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    ttk::frame $d.table;pack $d.table -fill both -expand 1
    ttk::treeview $d.tree -columns {id name mode aspect bounds} -show headings -selectmode browse
    foreach key {id name mode aspect bounds} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 150 -minwidth [expr {[font measure TkHeadingFont [string totitle $key]]+22}]}
    ttk::scrollbar $d.y -orient vertical -command [list $d.tree yview];ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview];$d.tree configure -yscrollcommand [list $d.y set] -xscrollcommand [list $d.x set]
    pack $d.x -in $d.table -side bottom -fill x;pack $d.y -in $d.table -side right -fill y;pack $d.tree -in $d.table -fill both -expand 1
    bind $d.tree <Configure> [list ::GX::CurveWorkbench::_inspectionColumnsSchedule $d.tree]
    bind $d <Escape> [list destroy $d];_savedViewRefresh $w
}
proc ::GX::CurveWorkbench::_savedViewSelected {w} {set selected [$w.savedViews.tree selection];if {[llength $selected]!=1} {error "Select one saved view"};return [lindex $selected 0]}
proc ::GX::CurveWorkbench::_savedViewForm {w action} {
    variable st
    set id {};set name view
    if {$action ne "create"} {set id [_savedViewSelected $w];set name [dict get $st($w,savedViews) $id name]}
    ::GX::uiFieldFormCreate $w.savedViewForm "[string totitle $action] saved view" {name {type string label {Saved view name}}} [dict create name $name] [list ::GX::CurveWorkbench::_savedViewApply $w $st($w,token) $action $id] $w.savedViews
}
proc ::GX::CurveWorkbench::_savedViewApply {w token action id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen saved-view parameters"}
    _cancelGesture $w;_pointSyncApply $w
    set name [string trim [dict get $values name]];if {$name eq {}} {error "Enter a saved view name"}
    if {$action eq "create"&&[dict size $st($w,savedViews)]>=256} {error "Saved view limit is 256; remove unused bookmarks"}
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {$id eq {}} {set id "view[incr st($w,nextSavedView)]"}
    if {$action ne "rename"} {dict set st($w,savedViews) $id snapshot [_savedViewCapture $w]}
    dict set st($w,savedViews) $id name $name
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _savedViewRefresh $w;return $id
}
proc ::GX::CurveWorkbench::_savedViewRestore {w} {
    variable st
    _cancelGesture $w;_pointSyncApply $w;set id [_savedViewSelected $w];set snapshot [dict get $st($w,savedViews) $id snapshot];set missing {}
    dict for {curve units} [dict get $snapshot coordinate_units] {if {[dict exists $st($w,curves) $curve]&&[_coordinateUnits [_record $w $curve]] ne $units} {error "Saved view coordinate units changed for $curve; explicitly update the view from the current frame before restoring"}}
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {
        set state [dict get $snapshot view_state]
        # Preserve the live widget size/margins while restoring logical bounds.
        set viewport [::GX::Native2D::core view_requested $st($w,scene)];lset viewport 6 [lindex [dict get $state viewport] 6];dict set state viewport $viewport
        ::GX::Native2D::core view_state $st($w,scene) $state
        dict for {curve visible} [dict get $snapshot curve_visibility] {
            if {![dict exists $st($w,curves) $curve]} {lappend missing $curve;continue}
            dict set st($w,curves) $curve visible $visible;::GX::Native2D::core visible $st($w,scene) [dict get [_record $w $curve] native] $visible
        }
        dict for {group visible} [dict get $snapshot group_visibility] {if {[dict exists $st($w,groups) $group]} {dict set st($w,groups) $group visible $visible} else {lappend missing $group}}
        dict for {layer visible} [dict get $snapshot layer_visibility] {if {[dict exists $st($w,layers) $layer]} {dict set st($w,layers) $layer properties visible $visible} else {lappend missing $layer}}
        _cadSyncGroups $w;_collectionSyncLayers $w;_history $w $before {}
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    set st($w,status) "Restored saved view [dict get $st($w,savedViews) $id name]; geometry unchanged[expr {$missing eq {} ? {.} : "; missing presentation references: [join $missing {, }]."}]"
}
proc ::GX::CurveWorkbench::_savedViewRemove {w} {
    variable st
    set id [_savedViewSelected $w];set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo);dict unset st($w,savedViews) $id
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _savedViewRefresh $w
}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_views_base
proc ::GX::CurveWorkbench::_changed {w} {_changed_views_base $w;_savedViewRefresh $w}
proc ::GX::CurveWorkbench::_buildViews {w} {
    variable st
    $w.cad.sketch.menu add command -label "Saved views…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_savedViewOpen $w]]
}
