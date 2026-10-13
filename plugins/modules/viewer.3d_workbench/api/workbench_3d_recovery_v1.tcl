# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Workbench3D {variable recoveryNotice ""}
rename ::GX::Workbench3D::checkpoint ::GX::Workbench3D::checkpoint_recovery_base
proc ::GX::Workbench3D::checkpoint {} {
    variable document;variable model;variable recoveryNotice
    set result [checkpoint_recovery_base]
    set receipt [dict create module_id viewer.3d_workbench module_version 0.1.0 api_id NATIVE_3D_GEOMETRY_API_v1 api_version 1]
    if {[dict get $model recipe] ne {}} {dict set receipt operation [lindex [dict get $model recipe] end]}
    if {[catch {::GX::workbenchRecoveryCheckpoint $document $receipt} message]} {set recoveryNotice "Action committed; recovery checkpoint unavailable: $message"} else {set recoveryNotice ""}
    return $result
}
proc ::GX::Workbench3D::saveExplicit {} {
    variable document;variable recoveryNotice;variable status
    checkpoint
    if {[catch {set result [::GX::workbenchRecoveryMarkSaved $document]} message]} {set result [dict create status corrupt reason $message]}
    if {[dict get $result status] eq "corrupt"} {set recoveryNotice "Workbench saved; recovery journal remains unavailable: [dict get $result reason]";set status "Workbench saved."} else {set recoveryNotice "";set status "Workbench saved; recovery journal compacted and marked clean."}
}
rename ::GX::Workbench3D::buildPanel ::GX::Workbench3D::buildPanel_recovery_base
proc ::GX::Workbench3D::buildPanel {args} {
    variable panel
    buildPanel_recovery_base {*}$args
    $panel.save configure -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::saveExplicit]
    ttk::label $panel.recoveryWarning -textvariable ::GX::Workbench3D::recoveryNotice -foreground #A32B20 -wraplength 425
    pack $panel.recoveryWarning -fill x
}
rename ::GX::Workbench3D::close ::GX::Workbench3D::close_recovery_base
proc ::GX::Workbench3D::close {} {
    variable scene;variable document;variable recoveryNotice
    if {$scene ne {}&&![catch {::GX::native3DGeometrySceneInfo $scene}]} {
        if {[catch {::GX::workbenchRecoveryClose $document} message]} {set recoveryNotice "Closing Workbench; recovery journal could not be marked clean: $message"}
    }
    tailcall close_recovery_base
}
