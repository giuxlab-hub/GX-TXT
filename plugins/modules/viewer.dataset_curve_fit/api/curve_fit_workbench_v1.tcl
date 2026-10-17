# Retained scientific state stays separate from editable Workbench geometry.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_workbenchDefinition {definition} {
    if {[dict get $definition family] eq "composite_path"} {
        set parts {}
        foreach part [dict get $definition parts] {
            dict set part definition [_workbenchDefinition [dict get $part definition]]
            lappend parts $part
        }
        dict set definition parts $parts
    } elseif {[dict get $definition family] eq "arc"} {
        # The scientific envelope collapses a 1-by-2 matrix to a vector.
        dict set definition controls [list [dict get $definition controls]]
    }
    return $definition
}
proc ::GX::DatasetCurveFit::_workbenchDomain {p} {
    if {[dict exists $p export_domain]} {return [split [dict get $p export_domain] ,]}
    set domain [dict get $p domain]
    if {$domain eq "source"} {
        if {[dict get $p orientation] eq "parametric"} {return {0 1}}
        if {[dict get $p orientation] eq "r_of_theta"} {return [list [dict get $p angular_min] [dict get $p angular_max]]}
        return [split [dict get $p translation u original_bounds] ,]
    }
    if {[lindex $domain 0] eq "parameter"} {set domain [lrange $domain 1 end]}
    return [lrange $domain 0 1]
}
proc ::GX::DatasetCurveFit::_workbenchGeometry {reference} {
    set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    set domain [_workbenchDomain $p]
    set geometry [dict create schema gxtxt.model_geometry.v1 status sampled_required reason registered_callback_has_no_native_primitive parameter_domain $domain fit_performed 0]
    if {![dict exists $p registered_model_state]} {
        set queryOptions [dict create extrapolation allow]
        # Geometry has a captured output interval even when historical inference
        # did not retain a training-domain receipt. Do not invent that receipt.
        if {![dict exists $p training_domain]} {dict set queryOptions reference_domain $domain}
        set context [_queryOptions $p query $queryOptions]
        set options [dict get $context node]
        dict set options fields domain [::GX::ScientificTransportv1::array {2 1} $domain]
        # Unit scaling is for derivative presentation, not physical geometry.
        foreach field {derivative_scale inverse_derivative_scale} {dict unset options fields $field}
        set result [_queryExecute geometry [_queryCapturedModel $p] [::GX::ScientificTransportv1::empty] [::GX::ScientificTransportv1::empty] $options {}]
        set geometry [dict get $result values]
    }
    dict set geometry domain_basis captured_output_interval
    dict set geometry training_domain_status [expr {[dict exists $p training_domain]?"value":"unavailable_not_recorded"}]
    if {[dict get $geometry status] eq "exact"} {
        dict set geometry definition [_workbenchDefinition [dict get $geometry definition]]
    } else {
        # Bounded, explicitly indexed materialization of already accepted output.
        # The original complete model, output and resources are copied separately.
        set n [dict get $p output_n];set count [expr {min(257,$n)}]
        set indices {};set ranges {};set points {}
        for {set i 0} {$i<$count} {incr i} {
            set index [expr {wide(round(double($i)*($n-1)/($count-1)))}]
            lappend indices $index;lappend ranges [list [expr {16*$index}] 16]
            if {![dict exists $record geometry_resource]} {lappend points [lindex [dict get $record points] $index]}
        }
        if {[dict exists $record geometry_resource]} {
            foreach bytes [::GX::interactiveDocumentResourceReadRanges [dict get $record geometry_resource] $ranges] {binary scan $bytes q* point;lappend points $point}
        }
        dict set geometry definition [dict create family polyline controls $points]
        dict set geometry sampling [dict create method retained_output_uniform_row_indices source_count $n indices $indices point_count $count error_bound unavailable]
    }
    _recipeResultRecord $reference
    return [dict create schema gxtxt.fitter_workbench_transfer.v1 source_reference $reference source_record $record geometry $geometry coordinate_units [list [dict get $p source_axes x unit] [dict get $p source_axes y unit]]]
}
proc ::GX::DatasetCurveFit::resultWorkbench {reference name} {
    set transfer [_workbenchGeometry $reference]
    ::GX::modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
    return [::GX::CurveWorkbench::importFitGeometry $name $transfer]
}
proc ::GX::DatasetCurveFit::_workbenchTransfer {w} {
    variable state
    set selection [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selection]!=1} {error {Select one accepted fit to transfer}}
    set record [lindex $state($w,records) [lindex $selection 0]]
    set reference [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set receipt [resultWorkbench $reference "[dict get $record label] — Workbench"]
    set state($w,status) "Transferred [dict get $receipt representation]: [dict get $receipt reason]"
    ::GX::CurveWorkbench::openFitTransfer [dict get $receipt workspace_id]
    return $receipt
}
