# SPDX-License-Identifier: GPL-3.0-or-later
# Persisted receipts use logical geometry IDs. Native2D alone evaluates values.
proc ::GX::CurveWorkbench::_measurementFingerprint {w id} {
    variable st
    set record [_record $w $id];set geometry {}
    foreach key {samples sketch_definition sketch_samples geometry_resource row_resource gap_resource source_descriptor source_request operations working_unit sketch_units source_assumed_units source x y representation} {
        if {[dict exists $record $key]} {
            set value [dict get $record $key]
            if {$key in {geometry_resource row_resource gap_resource}} {set identity {};foreach field {sha256 size_bytes} {if {[dict exists $value $field]} {dict set identity $field [dict get $value $field]}};set value $identity}
            dict set geometry $key $value
        }
    }
    dict set geometry coordinate_units [_coordinateUnits $record]
    if {[info exists st($w,geometryFingerprint,$id)]&&[lindex $st($w,geometryFingerprint,$id) 0] eq $geometry} {return [lindex $st($w,geometryFingerprint,$id) 1]}
    set sha [::GX::datasetStorageSha256Text [_session] $geometry];set st($w,geometryFingerprint,$id) [list $geometry $sha];return $sha
}
proc ::GX::CurveWorkbench::_measurementState {w record} {
    variable st
    dict for {id fingerprint} [dict get $record fingerprints] {
        if {![dict exists $st($w,curves) $id]} {return missing}
        if {[_measurementFingerprint $w $id] ne $fingerprint} {return stale}
    }
    return current
}
proc ::GX::CurveWorkbench::_measurementEvaluate {w definition} {
    variable st
    set spec $definition;set fingerprints {};set units {};set sources {}
    foreach field {a b} {
        if {![dict exists $definition $field]||[dict get $definition $field] eq {}} {dict unset spec $field;continue}
        set id [dict get $definition $field];set record [_record $w $id]
        dict set spec $field [dict get $record native]
        set xy [_coordinateUnits $record]
        if {[lindex $xy 0] ne [lindex $xy 1]} {error "Measurement geometry $id has incompatible X/Y units; normalize its coordinate frame first"}
        lappend units [lindex $xy 0]
        dict set fingerprints $id [_measurementFingerprint $w $id]
        if {[dict get $record source] ne {}} {dict set sources $id [dict create dataset_id [dict get $record source] descriptor [::GX::datasetPublicationV2DictDefault $record source_descriptor {}]]}
    }
    if {[llength [lsort -unique $units]]>1} {error "Measurements require common declared units; normalize or explicitly declare each geometry first"}
    set receipt [::GX::Native2D::core measure $st($w,scene) $spec]
    set unit [lindex $units 0]
    dict set receipt unit [expr {[dict get $receipt angular] ? "rad" : $unit eq {} ? {} : [dict get $receipt unit_power]==2 ? "${unit}^2" : $unit}]
    dict set receipt unit_declared [expr {$unit ne {}}]
    return [dict create definition $definition receipt $receipt fingerprints $fingerprints sources $sources]
}
proc ::GX::CurveWorkbench::_measurementRefresh {w} {
    variable st
    if {![winfo exists $w.measurements.tree]} return
    set tree $w.measurements.tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} $st($w,measurements) {
        set receipt [dict get $record receipt];set unit [dict get $receipt unit]
        if {$unit eq {}} {set unit undeclared}
        $tree insert {} end -id $id -values [list $id [dict get $record name] [dict get $record definition kind] [_measurementState $w $record] [dict get $receipt value] $unit [dict get $receipt exact] [dict get $receipt policy]]
    }
    _inspectionColumnsFit $tree
    foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
}
proc ::GX::CurveWorkbench::_measurementOpen {w} {
    set d $w.measurements
    if {[winfo exists $d]} {raise $d;_measurementRefresh $w;return}
    toplevel $d;wm title $d "Native2D measurement inspection";wm transient $d $w;wm geometry $d 1100x500
    ttk::label $d.help -text {Native scientific values retain their captured geometry and units. Changed or missing geometry marks a receipt stale/missing; refresh explicitly before publishing. Unsupported geometry or pair budgets report an error.} -wraplength 1020 -padding 8
    bind $d.help <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $d.help %w];pack $d.help -side top -fill x
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label callback} [list create {Create…} [list _measurementForm $w] refresh {Refresh selected} [list _measurementAction $w refresh] remove {Remove selected} [list _measurementAction $w remove] publish {Publish report as Dataset…} [list _measurementPublishForm $w]] {
        set callback [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]]
        ttk::button $d.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $callback];pack $d.actions.$key -side left -padx 4
    }
    ttk::button $d.actions.close -text Close -command [list destroy $d];pack $d.actions.close -side right
    bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    ttk::frame $d.table;pack $d.table -fill both -expand 1
    ttk::treeview $d.tree -columns {id name kind status value unit exact policy} -show headings -selectmode extended
    foreach key {id name kind status value unit exact policy} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 135 -minwidth [expr {[font measure TkHeadingFont [string totitle $key]]+22}]}
    $d.tree column policy -width 340
    ttk::scrollbar $d.y -orient vertical -command [list $d.tree yview];ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview]
    $d.tree configure -yscrollcommand [list $d.y set] -xscrollcommand [list $d.x set]
    pack $d.x -in $d.table -side bottom -fill x;pack $d.y -in $d.table -side right -fill y;pack $d.tree -in $d.table -fill both -expand 1
    bind $d.tree <Configure> [list ::GX::CurveWorkbench::_inspectionColumnsSchedule $d.tree]
    bind $d <Escape> [list destroy $d];_measurementRefresh $w
}
proc ::GX::CurveWorkbench::_measurementForm {w} {
    variable st
    set curves [dict keys $st($w,curves)];if {$curves eq {}} {error "Create or load geometry first"}
    set kinds {point_distance horizontal_distance vertical_distance segment_length segment_angle tangent_angle path_length radius diameter arc_angle bounding_width bounding_height signed_area point_curve_distance object_distance geometric_rmse hausdorff_sampled curve_length_difference curve_area_difference closest_curve_distance}
    set fields [dict create sample_budget {type integer min 6 max 4096 label {Geometric comparison scientific samples (new comparison kinds only)}} name {type string label {Measurement name}} kind [dict create type choice label {Native measurement kind} values $kinds] a [dict create type choice label {Geometry A logical ID} values $curves] a_index {type integer min 0 label {Point/segment index A}} b [dict create type choice label {Geometry B (when required)} values [linsert $curves 0 {}]] b_index {type integer min 0 label {Point/segment index B}} pair_budget {type integer min 1 max 1000000 label {Maximum exact segment-pair evaluations}}]
    ::GX::uiFieldFormCreate $w.measurementForm "Capture a Native2D measurement" $fields [dict create sample_budget 257 name measurement kind path_length a [_active $w] a_index 0 b {} b_index 0 pair_budget 1000000] [list ::GX::CurveWorkbench::_measurementApply $w $st($w,token)] $w.measurements
}
proc ::GX::CurveWorkbench::_measurementApply {w token values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen measurement parameters"}
    set name [string trim [dict get $values name]];if {$name eq {}} {error "Enter a measurement name"}
    _cancelGesture $w;_pointSyncApply $w
    if {[dict size $st($w,measurements)]>=4096} {error "Measurement limit is 4096; remove unused receipts first"}
    set record [_measurementEvaluate $w [dict remove $values name]]
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    set id "measurement[incr st($w,nextMeasurement)]";dict set record id $id;dict set record name $name
    dict set st($w,measurements) $id $record
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _measurementRefresh $w;return $id
}
proc ::GX::CurveWorkbench::_measurementAction {w action} {
    variable st
    set ids [$w.measurements.tree selection];if {$ids eq {}} {error "Select measurement rows first"}
    _cancelGesture $w;set after $st($w,measurements)
    foreach id $ids {
        if {$action eq "remove"} {dict unset after $id} else {
            set record [dict get $after $id]
            dict set after $id [dict merge $record [_measurementEvaluate $w [dict get $record definition]]]
        }
    }
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo);set st($w,measurements) $after
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _measurementRefresh $w
}
proc ::GX::CurveWorkbench::_measurementPublishForm {w} {
    variable st
    set ids [$w.measurements.tree selection];if {$ids eq {}} {error "Select measurements to publish"}
    ::GX::uiFieldFormCreate $w.measurementPublication "Publish Native2D measurement report" {dataset_id {type string label {Public Dataset ID}} storage {type choice label Storage values {auto CSV HDF5}}} {dataset_id measurement_report storage auto} [list ::GX::CurveWorkbench::_measurementPublishApply $w $st($w,token) $ids] $w.measurements
}
proc ::GX::CurveWorkbench::_measurementPublishApply {w token ids values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen report publication"}
    set requested [::GX::datasetPublicationV2RequestedId [dict get $values dataset_id] measurements]
    set rows {};set sources {};set commonUnit __unset__;set bytes 0
    foreach id $ids {
        set record [dict get $st($w,measurements) $id]
        if {[_measurementState $w $record] ne "current"} {error "Measurement $id is stale or missing; refresh explicitly before publication"}
        set receipt [dict get $record receipt];set definition [dict get $record definition];set unit [dict get $receipt unit]
        if {$commonUnit eq "__unset__"} {set commonUnit $unit} elseif {$unit ne $commonUnit} {set commonUnit {}}
        set row [dict create measurement_id $id name [dict get $record name] kind [dict get $definition kind] value [dict get $receipt value] unit $unit status current object_a [dict get $definition a] object_b [::GX::datasetPublicationV2DictDefault $definition b {}] source_geometry_sha256 [dict get $record fingerprints] anchor_specification $definition exact [dict get $receipt exact] policy [dict get $receipt policy] point_a [dict get $receipt point_a] point_b [dict get $receipt point_b]]
        lappend rows $row;incr bytes [string bytelength $row]
        dict for {object binding} [dict get $record sources] {lappend sources [dict get $binding dataset_id]}
    }
    set definition [dict create dataset_id $requested contract table.generic storage [dict get $values storage] expected_rows [llength $rows] expected_bytes $bytes producer_version [::GX::moduleField viewer.curve_workbench version] source_dataset_ids [lsort -unique $sources] provenance [dict create operation native2d_measurement_report records [lmap id $ids {dict get $st($w,measurements) $id}]] structured_metadata [dict create dataset.display_name $requested inspection.kind native2d_measurements inspection.value_units_column unit inspection.anchor_specification_encoding tcl_list_dict_data_v1 inspection.source_dataset_id_policy none_unless_dataset_source]]
    set plan [::GX::datasetPublicationV2Prepare [_session] viewer.curve_workbench $definition];set writer {}
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan];::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        foreach key [dict keys [lindex $rows 0]] {
            set dtype [expr {$key eq "value" ? "float64" : $key eq "exact" ? "uint8" : "string"}]
            set schema [dict create name [string totitle [string map {_ { }} $key]] dtype $dtype rank 1 dimension_ids row coordinate_role data semantic_role "measurement.$key"]
            if {$key eq "value"} {dict set schema unit $commonUnit}
            ::GX::datasetPublicationV2DeclareVariable $writer $key $schema
        }
        set data {};set n 0
        foreach row $rows {
            dict for {key value} $row {dict lappend data $key $value}
            if {[incr n]==512} {::GX::datasetPublicationV2Append $writer row $data;set data {};set n 0}
        }
        if {$n} {::GX::datasetPublicationV2Append $writer row $data}
        foreach id $ids {if {[_measurementState $w [dict get $st($w,measurements) $id]] ne "current"} {error "Geometry changed during publication"}}
        set result [::GX::datasetPublicationV2Finalize $writer];set writer {}
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
    set st($w,status) "Published measurement Dataset [dict get $result dataset_id].";return $result
}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_measurements_base
proc ::GX::CurveWorkbench::_changed {w} {_changed_measurements_base $w;_measurementRefresh $w}
proc ::GX::CurveWorkbench::_buildMeasurements {w} {
    variable st
    $w.cad.sketch.menu add command -label "Measurements…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_measurementOpen $w]]
}
proc ::GX::CurveWorkbench::_drawMeasurements {w} {
    variable st
        if {![info exists st($w,measurements)]} return
    dict for {id record} $st($w,measurements) {
        if {[dict get $record definition kind] ni {point_distance horizontal_distance vertical_distance point_curve_distance object_distance}||[_measurementState $w $record] ne "current"} continue
        set receipt [dict get $record receipt]
        lassign [::GX::Native2D::core device $st($w,scene) [dict get $receipt point_a]] ax ay
        lassign [::GX::Native2D::core device $st($w,scene) [dict get $receipt point_b]] bx by
        $w.right.viewport.canvas create line $ax $ay $bx $by -fill #6b3aa0 -width 2 -dash {5 3} -tags [list measurement $id]
        foreach x [list $ax $bx] y [list $ay $by] {$w.right.viewport.canvas create oval [expr {$x-4}] [expr {$y-4}] [expr {$x+4}] [expr {$y+4}] -outline #6b3aa0 -width 2 -tags [list measurement $id]}
        $w.right.viewport.canvas create text [expr {($ax+$bx)/2}] [expr {($ay+$by)/2-12}] -text "[dict get $record name]: [format %.6g [dict get $receipt value]] [dict get $receipt unit]" -fill #6b3aa0 -font TkDefaultFont -tags [list measurement $id]
    }
}

proc ::GX::CurveWorkbench::_inspectionColumnsFit {tree} {
    tailcall ::GX::uiFieldInspectionColumnsFit $tree
}

proc ::GX::CurveWorkbench::_inspectionColumnsSchedule {tree} {
    tailcall ::GX::uiFieldInspectionColumnsSchedule $tree
}
proc ::GX::CurveWorkbench::_inspectionColumnsApply {tree} {
    tailcall ::GX::_uiFieldInspectionColumnsApply $tree
}
