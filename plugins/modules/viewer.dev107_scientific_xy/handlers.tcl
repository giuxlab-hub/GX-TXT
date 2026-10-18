# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Generated_viewer_dev107_scientific_xy::Handlers {}
proc ::GX::Generated_viewer_dev107_scientific_xy::Handlers::load {window action} {
 set values [::GX::viewerGuiDesignValues $window]
 set request [dict create dataset_id [dict get $values dataset] x_variable_id [dict get $values x_variable] y_variable_id [dict get $values y_variable] display_budget 4096]
 ::GX::viewerGuiDesignSourceSet $window xy $request
 return {status completed}
}
