# SPDX-License-Identifier: GPL-3.0-or-later
# Metadata discovery loads declarations only, never the live Workbench.
namespace eval ::GX::CurveWorkbench {}
if {![dict exists $::GX::WorkspaceScientificCodec::shapes fitter_accepted_record]} {
    source [file join [file dirname [info script]] .. .. viewer.dataset_curve_fit api workspace_native.tcl]
}
source [file join [file dirname [info script]] workspace_native.tcl]
