# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Workbench3D {variable recoveryNotice ""}
proc ::GX::Workbench3D::saveExplicit {} {
    variable document;variable recoveryNotice;variable status
    checkpoint
    if {[catch {set result [::GX::workbenchRecoveryMarkSaved $document]} message]} {set result [dict create status corrupt reason $message]}
    if {[dict get $result status] eq "corrupt"} {set recoveryNotice "Workbench saved; recovery journal remains unavailable: [dict get $result reason]";set status $recoveryNotice} else {set recoveryNotice "";set status "Workbench saved; recovery journal compacted and marked clean."}
}
rename ::GX::Workbench3D::buildPanel ::GX::Workbench3D::buildPanel_recovery_base
proc ::GX::Workbench3D::buildPanel {args} {
    variable panel
    buildPanel_recovery_base {*}$args
    $panel.save configure -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::saveExplicit]
    ttk::label $panel.recoveryWarning -textvariable ::GX::Workbench3D::recoveryNotice -foreground #A32B20 -wraplength 425
    pack $panel.recoveryWarning -fill x
}
