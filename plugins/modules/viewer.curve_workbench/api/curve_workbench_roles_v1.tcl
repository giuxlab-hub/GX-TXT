# SPDX-License-Identifier: GPL-3.0-or-later
# Native owns the single geometry role; workflows consume its output policy.
proc ::GX::CurveWorkbench::_geometryRoleOpen {w} {
    variable st
    set ids [_cadTargets $w];set role [::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get [_record $w [lindex $ids 0]] native]]
    ::GX::uiFieldFormCreate $w.geometryRole "Geometry role — coordinates and measurements unchanged" {role {type choice label {Role for selected geometry} values {regular construction reference}}} [dict create role $role] [list ::GX::CurveWorkbench::_geometryRoleApply $w $st($w,token) $ids] $w
}
proc ::GX::CurveWorkbench::_geometryRoleApply {w token ids values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen geometry role parameters"}
    _cancelGesture $w;_pointSyncApply $w
    if {$ids ne [_cadTargets $w]} {error "Geometry targets changed; reopen role parameters"}
    set role [dict get $values role];if {$role ni {regular construction reference}} {error "Unknown geometry role"}
    set before [_snapshotIds $w $ids];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {
        foreach id $ids {set record [_record $w $id];::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get $record native] $role;dict set record sketch_attributes gx.geometry_role $role;dict set st($w,curves) $id $record}
        _history $w $before $ids
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    set st($w,status) "Geometry role $role committed; construction/reference entities assist editing and are excluded from normal publication/export. Explicit finite samples are regular independent geometry."
}
rename ::GX::CurveWorkbench::publish ::GX::CurveWorkbench::publish_roles_base
proc ::GX::CurveWorkbench::publish {w requested {ids {}}} {
    variable st
    if {$ids eq {}} {set ids [list [_active $w]]}
    set chosen {};set excluded {}
    foreach id $ids {if {[::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get [_record $w $id] native]] eq "regular"} {lappend chosen $id} else {lappend excluded $id}}
    if {$chosen eq {}} {error "Selected geometry is construction/reference only. Create an explicit finite sample or change its role to regular before Dataset publication."}
    set result [publish_roles_base $w $requested $chosen]
    if {$excluded ne {}} {append st($w,status) " Construction/reference excluded: [join $excluded {, }]."}
    return $result
}
proc ::GX::CurveWorkbench::_buildRoles {w} {
    
    $w.cad.sketch.menu add command -label "Construction / reference role…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_geometryRoleOpen $w]]}
proc ::GX::CurveWorkbench::_sketchExportOpen {w} {
    ::GX::workbenchExtensionExportDialog $w.sketchExport [_coordinateExportContext $w] $w
}
proc ::GX::CurveWorkbench::_buildExport {w} {
    
    ttk::button $w.cad.sketchExport -text "Export sketch…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_sketchExportOpen $w]];pack $w.cad.sketchExport -side left -padx 3}
