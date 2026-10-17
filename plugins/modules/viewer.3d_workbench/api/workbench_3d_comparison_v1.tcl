# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::Workbench3D::comparisonState {record} {
    variable model
    if {![dict exists $record receipt statistics]} {return refresh_required}
    foreach side {reference target} {set id [dict get $record $side];if {![dict exists $model objects $id]} {return missing};if {[dict get $model objects $id geometry] ne [dict get $record ${side}_geometry]} {return stale}}
    return [expr {[dict get $record working_unit] eq [dict get $model working_unit] ? "current" : "stale"}]
}
proc ::GX::Workbench3D::comparisonPanel {} {
    set d $::GX::Engine3D::window.comparisons
    if {[winfo exists $d]} {raise $d;comparisonRefresh;return}
    toplevel $d;wm title $d "Scientific geometry / section comparison";wm transient $d $::GX::Engine3D::window
    ttk::label $d.note -text {Native compares bounded deterministic vertex samples against complete target triangles. RMS, Hausdorff and closest distances are sampled metrics; B-Rep queries record tessellation. Refresh explicitly after geometry changes.} -wraplength 830 -justify left -font TkDefaultFont;pack $d.note -fill x -padx 10 -pady 8
    bind $d.note <Configure> [list ::GX::_workbenchExtensionActionWrap $d.note %w]
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label action} {create {New comparison…} create refresh {Refresh selected…} refresh publish {Publish deviations as Dataset…} publish remove Remove remove} {ttk::button $d.actions.$key -text $label -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::comparisonAction $action]];pack $d.actions.$key -side left}
    bind $d.actions <Configure> [list ::GX::uiFieldControlsLayout $d.actions %w]
    ttk::label $d.summary -text {} -wraplength 830 -justify left -font TkDefaultFont;pack $d.summary -side bottom -fill x -padx 10 -pady 6
    bind $d.summary <Configure> [list ::GX::_workbenchExtensionActionWrap $d.summary %w]
    ttk::treeview $d.tree -columns {id name reference target status rms hausdorff closest unit} -show headings -height 7 -selectmode browse
    foreach {key label} {id ID name Name reference Reference target Target status Status rms {Reference RMS} hausdorff {Sampled Hausdorff} closest {Sampled closest} unit Unit} {$d.tree heading $key -text $label;$d.tree column $key -width 130 -stretch 0}
    ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview];$d.tree configure -xscrollcommand [list $d.x set];pack $d.x -side bottom -fill x;pack $d.tree -fill both -expand 1
    bind $d.tree <Configure> [list ::GX::uiFieldInspectionColumnsSchedule $d.tree]
    bind $d.tree <<TreeviewSelect>> ::GX::Workbench3D::comparisonSummary
    bind $d <Escape> [list destroy $d];wm geometry $d 1120x500;wm minsize $d 650 340;comparisonRefresh
}
proc ::GX::Workbench3D::comparisonRefresh {} {
    variable model
    if {![dict exists $model comparisons]} {dict set model comparisons {}}
    set d $::GX::Engine3D::window.comparisons;if {![winfo exists $d.tree]} return
    set chosen [$d.tree selection];$d.tree delete [$d.tree children {}]
    dict for {id record} [dict get $model comparisons] {
        set receipt [dict get $record receipt]
        $d.tree insert {} end -id $id -values [list $id [dict get $record name] [dict get $record reference] [dict get $record target] [comparisonState $record] [comparisonStatistic $record reference rmse] [comparisonStatistic $record bidirectional sampled_hausdorff_distance] [format %.9g [dict get $receipt closest_sampled]] [dict get $record working_unit]]
    }
    foreach id $chosen {if {[$d.tree exists $id]} {$d.tree selection add $id}}
    ::GX::uiFieldInspectionColumnsFit $d.tree;comparisonSummary
}
proc ::GX::Workbench3D::comparisonStatistic {record direction quantity} {
    if {![dict exists $record receipt statistics $direction]} {return {Refresh required}}
    set cell [lindex [::GX::StatisticsV1::scalarRows [dict get $record receipt statistics $direction] [dict create value $quantity]] 0]
    if {[dict get $cell status] ne "value"} {return [dict get $cell status]}
    return [format %.9g [dict get $cell value]]
}
proc ::GX::Workbench3D::comparisonSelected {} {set rows [$::GX::Engine3D::window.comparisons.tree selection];if {[llength $rows]!=1} {error "Select one captured comparison"};return [lindex $rows 0]}
proc ::GX::Workbench3D::comparisonSummary {} {
    variable model
    set d $::GX::Engine3D::window.comparisons;if {![winfo exists $d.summary]} return
    set ids [$d.tree selection];if {[llength $ids]!=1} {$d.summary configure -text {Select a captured result to inspect its science and sampling policy.};return}
    set record [dict get $model comparisons [lindex $ids 0]];set value [dict get $record receipt];set unit [dict get $record working_unit]
    if {![dict exists $value statistics]} {$d.summary configure -text {This historical receipt has no versioned statistical interpretation. Refresh the comparison to produce a current scientific report.};return}
    set statistics "Reference: [::GX::StatisticsV1::report [dict get $value statistics reference] {n rmse mae max_abs_error}]\nBoth directions: [::GX::StatisticsV1::report [dict get $value statistics bidirectional] {n rmse sampled_hausdorff_distance}]"
    if {[::GX::datasetPublicationV2DictDefault [dict get $record parameters] method surface] eq "section"} {
        $d.summary configure -text "[comparisonState $record]: $statistics\nShared-plane closest [format %.9g [dict get $value closest_distance]] $unit. Length difference [format %.9g [dict get $value length_difference]] $unit; signed area difference [format %.9g [dict get $value area_difference]] ${unit}^2. Coordinates are section-plane XY. Frame: [dict get $value plane]. Chaining tolerance [dict get $value tolerance] $unit; [dict get $value section_policy]."
        return
    }
    set volume [expr {[dict get $value volume_defined] ? "[format %.9g [dict get $value volume_difference]] ${unit}^3" : "undefined for an open surface"}]
    $d.summary configure -text "[comparisonState $record]: $statistics\nSampled closest [format %.9g [dict get $value closest_sampled]] $unit. Area difference [format %.9g [dict get $value area_difference]] ${unit}^2; volume difference $volume. [dict get $value reference_samples]/[dict get $value reference_vertices] and [dict get $value target_samples]/[dict get $value target_vertices] sampled vertices; full target triangle projection. Bounds delta: [dict get $value bounds_min_difference] / [dict get $value bounds_max_difference]."
}
proc ::GX::Workbench3D::comparisonAction {action} {
    variable model;variable selection
    set d $::GX::Engine3D::window.comparisons;set id {}
    if {$action ne "create"} {set id [comparisonSelected]}
    if {$action eq "remove"} {set before $model;dict unset model comparisons $id;commit $before delete_comparison [dict create comparison_id $id] {} {};comparisonRefresh;return}
    if {$action eq "publish"} {
        ::GX::uiFieldFormCreate $d.publication "Publish captured Native3D deviations" {dataset_id {type string label {Public Dataset name / ID} required 1} storage {type choice label Storage values {auto csv hdf5}}} {dataset_id surface_deviations storage auto} [list ::GX::Workbench3D::comparisonPublish $id] $d;return
    }
    set ids [dict keys [dict get $model objects]];if {[llength $ids]<2} {error "Accept at least two complete geometry objects"}
    set reference [lindex $ids 0];set target [lindex $ids 1]
    set values [dict create name {Geometry comparison} reference $reference target $target method surface sample_budget 257 linear_deflection .01 angular_deflection .3 weld_tolerance 1e-8 plane_origin {0 0 0} plane_normal {0 0 1} plane_u_axis {1 0 0} section_tolerance 1e-8]
    if {$id ne {}} {set values [dict merge $values [dict get $model comparisons $id parameters]]}
    set fields [dict create name {type string label {Comparison name} required 1} reference [dict create type choice label {Reference logical object ID} values $ids] target [dict create type choice label {Target logical object ID} values $ids] sample_budget {type integer label {Scientific vertex samples per direction} min 6 max 4096} linear_deflection [dict create type number label "B-Rep linear deflection ([dict get $model working_unit])" min 1e-300] angular_deflection {type number label {B-Rep angular deflection (radians)} min 1e-300 max 3.141592653589793} weld_tolerance [dict create type number label "Tessellation weld tolerance ([dict get $model working_unit])" min 1e-300]]
    dict set fields method {type choice label {Comparison geometry} values {surface section}}
    foreach {key label} {plane_origin {Section plane origin (working unit; X Y Z)} plane_normal {Section plane normal (X Y Z)} plane_u_axis {Section plane U axis (X Y Z)}} {dict set fields $key [dict create type string label $label required 1]}
    dict set fields section_tolerance [dict create type number label "Section chaining tolerance ([dict get $model working_unit])" min 1e-300]
    ::GX::uiFieldFormCreate $d.parameters "Native3D scientific comparison" $fields $values [list ::GX::Workbench3D::comparisonApply $id] $d
}
proc ::GX::Workbench3D::comparisonApply {id values} {
    variable model;variable tokens;variable scene
    set reference [dict get $values reference];set target [dict get $values target]
    if {$reference eq $target} {error "Choose two different accepted geometry objects"}
    foreach object [list $reference $target] {if {![dict exists $tokens $object]} {error "Comparison source is missing: $object"}}
    set captured [::GX::native3DGeometrySceneInfo $scene]
    set request [dict create base [dict get $tokens $reference] tool [dict get $tokens $target] working_unit [dict get $model working_unit] sample_budget [dict get $values sample_budget]]
    if {[dict get $values method] eq "section"} {
        dict set request plane [dict create origin [dict get $values plane_origin] normal [dict get $values plane_normal] u_axis [dict get $values plane_u_axis]]
        dict set request tolerance [dict get $values section_tolerance]
        set receipt [call compare_sections $request]
        dict set receipt reference_rms [dict get $receipt rmse]
        dict set receipt closest_sampled [dict get $receipt closest_distance]
    } else {
        foreach key {linear_deflection angular_deflection weld_tolerance} {dict set request $key [dict get $values $key]}
        dict set request max_triangles 1000000;dict set request max_output_bytes 134217728
        set receipt [call compare_geometry $request]
    }
    if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Geometry changed during comparison; retry explicitly"}
    set before $model;if {$id eq {}} {set id [nextId next_comparison comparison]}
    set record [dict create name [dict get $values name] reference $reference target $target reference_geometry [dict get $model objects $reference geometry] target_geometry [dict get $model objects $target geometry] working_unit [dict get $model working_unit] parameters $values receipt $receipt]
    dict set model comparisons $id $record
    try {commit $before compare_geometry $values [list $reference $target] [list $id]} on error {message options} {set model $before;return -options $options $message}
    comparisonRefresh;set d $::GX::Engine3D::window.comparisons;if {[winfo exists $d.tree]} {$d.tree selection set $id;comparisonSummary};return $id
}
proc ::GX::Workbench3D::comparisonPublish {id values} {
    variable model;variable document;variable scene
    if {![dict exists $model comparisons $id]||[comparisonState [dict get $model comparisons $id]] ne "current"} {error "Comparison is stale/missing; Refresh it explicitly before publication"}
    set record [dict get $model comparisons $id];set unit [dict get $record working_unit];set receipt [dict get $record receipt];set rows [dict get $receipt rows]
    set requested [::GX::datasetPublicationV2RequestedId [dict get $values dataset_id] comparison]
    set captured [::GX::native3DGeometrySceneInfo $scene]
    set metadata [dict create dataset.display_name $requested inspection.kind native3d_geometry_comparison inspection.document_id $document inspection.comparison_id $id inspection.reference [dict get $record reference] inspection.target [dict get $record target] inspection.reference_geometry [dict get $record reference_geometry] inspection.target_geometry [dict get $record target_geometry] inspection.parameters [dict get $record parameters] inspection.scientific_summary [dict remove $receipt rows] geometry.working_unit $unit]
    set sourceIds {};set sourceBindings {}
    foreach side {reference target} {
        set info [dict get $model objects [dict get $record $side]]
        foreach binding [dict get $info source_bindings] {
            lappend sourceBindings $binding
            if {[dict exists $binding source_descriptor]} {foreach identity [dict get $binding source_descriptor source_identities] {if {[dict exists $identity dataset_id]&&[dict get $identity dataset_id] ni $sourceIds} {lappend sourceIds [dict get $identity dataset_id]}}} elseif {[dict exists $binding source_dataset_id]&&[dict get $binding source_dataset_id] ni $sourceIds} {lappend sourceIds [dict get $binding source_dataset_id]}
        }
    }
    dict set metadata inspection.source_bindings $sourceBindings
    set metadata [dict merge $metadata [::GX::StatisticsV1::publicationMetadata [dict get $receipt statistics]]]
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession viewer.3d_workbench [dict create dataset_id $requested contract table.generic storage [dict get $values storage] expected_rows [llength $rows] expected_bytes [expr {128*[llength $rows]}] structured_metadata $metadata source_dataset_ids $sourceIds provenance "Explicit captured Native3D complete-triangle deviation report from $document" producer_version [::GX::moduleField viewer.3d_workbench version]]]
    set writer {}
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan];::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        set section [expr {[::GX::datasetPublicationV2DictDefault [dict get $record parameters] method surface] eq "section"}]
        set columns [list sample_index uint64 {Sample ordinal} {} distance float64 {Unsigned deviation} $unit source_x float64 {Query X} $unit source_y float64 {Query Y} $unit projected_x float64 {Projected X} $unit projected_y float64 {Projected Y} $unit]
        if {$section} {lappend columns position float64 {Section path distance} $unit signed_residual float64 {Unsigned nearest-curve distance (legacy field)} $unit} else {lappend columns direction uint64 {Direction:0 reference to target;1 reverse} {} source_vertex uint64 {Source vertex index (zero based)} {} source_z float64 {Query Z} $unit projected_z float64 {Projected Z} $unit}
        foreach {key type label units} $columns {::GX::datasetPublicationV2DeclareVariable $writer $key [dict create name $label dtype $type rank 1 dimension_ids row unit $units coordinate_role [expr {$key eq "sample_index" ? "coordinate" : "data"}]]}
        set data {};set ordinal 0;set count 0
        foreach row $rows {
            dict lappend data sample_index [incr ordinal]
            foreach key [expr {$section ? "position signed_residual distance" : "direction source_vertex distance"}] {dict lappend data $key [dict get $row $key]}
            foreach prefix {source projected} {foreach axis [expr {$section ? "x y" : "x y z"}] component [dict get $row $prefix] {dict lappend data ${prefix}_$axis $component}}
            if {[incr count]==512} {::GX::datasetPublicationV2Append $writer row $data;set data {};set count 0}
        }
        if {$count} {::GX::datasetPublicationV2Append $writer row $data}
        if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Comparison document changed during publication"}
        set published [::GX::datasetPublicationV2Finalize $writer];set writer {};return $published
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
}
rename ::GX::Workbench3D::refresh ::GX::Workbench3D::refresh_comparison_base
proc ::GX::Workbench3D::refresh {} {refresh_comparison_base;comparisonRefresh}
rename ::GX::Workbench3D::buildPanel ::GX::Workbench3D::buildPanel_comparison_base
proc ::GX::Workbench3D::buildPanel {window} {variable panel;buildPanel_comparison_base $window;ttk::button $panel.comparisons -text "Compare complete geometry / deviations…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::comparisonPanel];pack $panel.comparisons -fill x -before $panel.status}
