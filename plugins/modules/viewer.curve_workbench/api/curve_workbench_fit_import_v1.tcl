# Workbench owns its payload; Fitter/Numeric own the captured scientific model.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::CurveWorkbench::openFitTransfer {workspace} {
    variable st
    set saved [::GX::sessionWorkspaceGet $workspace]
    set record [dict get $saved payload curves curve1]
    if {![dict exists $record retained_fit]||![dict exists $record conversion_provenance]} {error {Workspace is not an imported fit}}
    set w [::GX::sessionWorkspaceOpen $workspace]
    set status [dict get $record conversion_provenance geometry status]
    set label [expr {$status eq "exact"?"Exact retained model":"Sampled approximation"}]
    set st($w,status) "$label — original scientific model preserved separately in this Workspace."
    return $w
}
proc ::GX::CurveWorkbench::importFitGeometry {name transfer} {
    if {[dict get $transfer schema] ne "gxtxt.fitter_workbench_transfer.v1"} {error {Unsupported fit transfer contract}}
    set units [dict get $transfer coordinate_units]
    if {[llength $units]!=2} {error {Fit transfer requires independent X/Y unit declarations}}
    foreach unit $units {if {$unit ne {}} {::GX::unitRegistryConversionPlan $unit $unit}}
    set geometry [dict get $transfer geometry];set status [dict get $geometry status]
    if {$status ni {exact sampled_required}} {error {Unknown fit geometry representation}}
    set representation [expr {$status eq "exact"?"exact retained model":"sampled approximation"}]
    set label "[dict get $transfer source_record label] ($representation)"
    ::GX::native2DEnsure;set scene [::GX::Native2D::core scene];set document {}
    try {
        set native [::GX::Native2D::core sketch_create $scene [dict get $geometry definition] 257]
        set definition [::GX::Native2D::core sketch_definition $scene $native]
        set samples {};set i 0
        foreach point [::GX::Native2D::core points $scene $native] {
            lappend samples [dict create row -1 order $i point_id "fit:[incr i]" x [lindex $point 0] y [lindex $point 1]]
        }
        set record [dict create id curve1 name $label samples $samples source {} x x y y source_x_name X source_y_name Y filter {} filter_value {} family {} order {} parents {} ancestors {} operations {} representation linear visible 1 locked 0 edited 0 breaks [::GX::Native2D::core breaks $scene $native] coordinate_units $units sketch_definition $definition sketch_samples [llength $samples] geometry_authority retained_sketch]
        ::GX::Native2D::core fit $scene
        set payload [dict create version 2 curves [dict create curve1 $record] next 1 active curve1 selected_indices {} view [::GX::Native2D::core view $scene] reference {} target {} external_feedback {}]
        set created [::GX::sessionWorkspaceCreate curve_workbench $name $payload];set document [dict get $created id]
        # No reference to another owner's generation survives in the scientific
        # archive. The original source_reference remains an identity receipt only.
        set archived [::GX::managedResourceCopyTree $document [dict get $transfer source_record]]
        dict set record retained_fit [dict create schema gxtxt.retained_fit_archive.v1 source_reference [dict get $transfer source_reference] record $archived immutable_import_snapshot 1]
        dict set record conversion_provenance [dict remove $transfer source_record]
        dict set record operations [list [dict create operation import_accepted_fit representation $representation source_reference [dict get $transfer source_reference]]]
        dict set payload curves curve1 $record
        ::GX::sessionWorkspaceUpdate $document $payload
        ::GX::sessionWorkspaceValidate $document
        return [dict create schema gxtxt.fit_workbench_receipt.v1 workspace_id $document curve_id curve1 representation $representation reason [dict get $geometry reason] parameter_domain [dict get $geometry parameter_domain] coordinate_units $units source_reference [dict get $transfer source_reference] independent_resources 1 fit_performed 0]
    } on error {message options} {
        if {$document ne {}} {::GX::sessionWorkspaceDelete $document}
        return -options $options $message
    } finally {::GX::Native2D::core destroy $scene}
}
