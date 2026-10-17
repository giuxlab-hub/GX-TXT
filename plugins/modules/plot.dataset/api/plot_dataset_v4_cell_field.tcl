# Generic exact cell-associated triangular field adapter. Uses existing canonical
# Datasets, coordinate snapshots and Graph Metadata; no FEM solver or store.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::PlotDatasetAPIv4::validateSpec {spec} {
    _ready;set result [::GX::PlotDatasetAPIv2::validateSpec $spec];_cellFieldBindings $spec;return $result
}
proc ::GX::PlotDatasetAPIv4::cellFieldSpec {dataset xVariable yVariable binding {title {Cell-associated field}}} {
    set s [dict create id cell_field dataset_id $dataset x_variable_id $xVariable y_variable_id $yVariable kind scatter axis left label $title cell_field $binding]
    _cellFieldValidate $s
    set spec [newSpec -title $title];dict set spec panels [list [dict create id main axes {} annotations {} series [list $s]]]
    return $spec
}
proc ::GX::PlotDatasetAPIv4::_cellFieldValidate {series} {
    set b [dict get $series cell_field]
    if {[_get $b schema {}] ne {GXTXT_CELL_FIELD_BINDING_v1}} {error {Unsupported cell-field binding schema}}
    foreach key {nodes_dataset_id node_id_variable_id x_variable_id y_variable_id cell_id_variable_id node_variable_ids scalar_variable_id} {if {![dict exists $b $key]||[dict get $b $key] eq {}} {error "Cell-field binding requires $key"}}
    foreach key [dict keys $b] {if {$key ni {schema nodes_dataset_id node_id_variable_id x_variable_id y_variable_id cell_id_variable_id node_variable_ids scalar_variable_id}} {error "Unknown cell-field binding field $key"}}
    if {[llength [dict get $b node_variable_ids]]!=3 || [llength [lsort -unique [dict get $b node_variable_ids]]]!=3} {error {Triangle connectivity requires exactly three stable node-reference variables}}
    foreach key {family_variable_id secondary_variable_id ordering_variable_id source_row_ordinals row_filters} {if {[_get $series $key {}] ne {}} {error {Cell-field topology is complete and unfiltered; publish an explicit canonical submesh before applying row/group transformations}}}
    set cell [dict get $series dataset_id];set nodes [dict get $b nodes_dataset_id]
    foreach ds [list $cell $nodes] ids [list [concat [list [dict get $b cell_id_variable_id] [dict get $b scalar_variable_id]] [dict get $b node_variable_ids]] [list [dict get $b node_id_variable_id] [dict get $b x_variable_id] [dict get $b y_variable_id]]] {
        foreach id $ids {set v [::GX::datasetVariableV3ById $ds $id];if {[dict get $v rank]!=1||[dict get $v dtype] ni {float16 float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64}} {error {Cell-field roles require real numeric rank-one canonical variables}}}
    }
    foreach ds [list $nodes $cell $cell $cell $cell] id [concat [list [dict get $b node_id_variable_id] [dict get $b cell_id_variable_id]] [dict get $b node_variable_ids]] {
        if {[dict get [::GX::datasetVariableV3ById $ds $id] dtype] ni {int8 int16 int32 int64 uint8 uint16 uint32 uint64}} {error {Node/cell/connectivity identities require true integer variable types}}
    }
    return $b
}
proc ::GX::PlotDatasetAPIv4::_cellFieldColumns {ds ids limit} {
    set token [::GX::tableStreamOpenDataset $::GX::currentSession $ds [lsort -unique $ids] 4096 {numeric_transport values}];set columns {};set count 0
    try {while {1} {set part [::GX::tableStreamNext $token];incr count [dict get $part row_count];if {$count>$limit} {error {Exact cell-field source exceeds native bounded topology capacity}}
        dict for {id values} [dict get $part values] {dict lappend columns $id {*}$values}
        if {[dict get $part eof]} break
    }} finally {::GX::tableStreamClose $token}
    return $columns
}
proc ::GX::PlotDatasetAPIv4::_cellFieldDescriptor {ds x y} {set token [::GX::curveSourceOpen $::GX::currentSession [dict create dataset_id $ds x_variable_id $x y_variable_id $y display_budget 16]];try {return [::GX::curveSourceDescribe $token]} finally {::GX::curveSourceClose $token}}
proc ::GX::PlotDatasetAPIv4::_cellFieldSeries {series axes} {
    if {{native_cell_field} ni [dict get [::GX::Native2D::core api_info] capabilities]} {error {The installed Native2D owner lacks exact cell-field support; no scatter fallback is allowed}}
    set b [_cellFieldValidate $series];set ds [dict get $series dataset_id];set nodes [dict get $b nodes_dataset_id]
    set ni [dict get $b node_id_variable_id];set nx [dict get $b x_variable_id];set ny [dict get $b y_variable_id]
    set ci [dict get $b cell_id_variable_id];set refs [dict get $b node_variable_ids];set scalar [dict get $b scalar_variable_id]
    set nd [_cellFieldColumns $nodes [list $ni $nx $ny] 60000];set cd [_cellFieldColumns $ds [concat [list $ci $scalar] $refs] 30000]
    set context [::GX::datasetCoordinateRead $::GX::currentSession $nodes]
    set xtarget [_get [_get $axes x {}] display_unit [dict get [::GX::datasetVariableV3ById $nodes $nx] unit]];set ytarget [_get [_get $axes left {}] display_unit [dict get [::GX::datasetVariableV3ById $nodes $ny] unit]]
    set xs [_coordinate $context $nx [dict get $nd $nx] $xtarget];set ys [_coordinate $context $ny [dict get $nd $ny] $ytarget]
    set meshNodes {};foreach id [dict get $nd $ni] x $xs y $ys {lappend meshNodes [list $id $x $y]}
    lassign $refs a b c;set meshCells {};set row 0
    foreach id [dict get $cd $ci] a0 [dict get $cd $a] a1 [dict get $cd $b] a2 [dict get $cd $c] value [dict get $cd $scalar] {lappend meshCells [list $id $a0 $a1 $a2 $value $row];incr row}
    set sources [list [_cellFieldDescriptor $ds [dict get $series x_variable_id] [dict get $series y_variable_id]] [_cellFieldDescriptor $nodes $nx $ny]]
    return [dict merge $series [dict create kind cell_field mesh_nodes $meshNodes mesh_cells $meshCells mesh_dataset_id $nodes scalar_variable_id $scalar scalar_unit [dict get [::GX::datasetVariableV3ById $ds $scalar] unit] points {} source_points {} source_rows {} point_identity_kind source_cell row_count $row coordinate_context [::GX::datasetCoordinateRead $::GX::currentSession $ds] source_descriptors $sources]]
}
proc ::GX::PlotDatasetAPIv4::_cellFieldBindings {spec} {
    set bindings {};if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {return $bindings}
    foreach p [dict get $spec panels] {foreach s [dict get $p series] {if {[dict exists $s cell_field]} {_cellFieldValidate $s;dict set bindings [dict get $s id] [dict get $s cell_field]}}}
    return $bindings
}
proc ::GX::PlotDatasetAPIv4::_cellFieldRestore {spec metadata} {
    if {[_get $metadata native_plot_v4_cell_field_required 0]&&(![dict exists $metadata native_plot_v4_cell_fields]||[dict get $metadata native_plot_v4_cell_fields] eq {})} {error {Required scientific cell-field binding is unavailable; refusing a centroid-scatter fallback}}
    if {![dict exists $metadata native_plot_v4_cell_fields]} {return $spec}
    set fields [dict get $metadata native_plot_v4_cell_fields];set panels {};set consumed {}
    foreach p [dict get $spec panels] {set series {};foreach s [dict get $p series] {set id [dict get $s id];if {[dict exists $fields $id]} {dict set s cell_field [dict get $fields $id];lappend consumed $id};lappend series $s};dict set p series $series;lappend panels $p}
    dict for {id binding} $fields {if {$id ni $consumed} {error {Persistent cell-field binding references a missing canonical series; reconcile explicitly before rendering}}}
    dict set spec panels $panels;return $spec
}
proc ::GX::PlotDatasetAPIv4::_specSourceVariables {spec} {
    set variables {};if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {set series [list $spec]} else {set series {};foreach p [dict get $spec panels] {lappend series {*}[dict get $p series]}}
    foreach s $series {
        set ds [dict get $s dataset_id]
        foreach id [_snapshotVariableIds [expr {[dict get $spec graph_id] eq {plot.dataset.xyz}?$spec:[dict create graph_id plot.dataset.xy panels [list [dict create series [list $s]]]]}]] {dict set variables "$ds:$id" [dict create dataset_id $ds variable_id $id]}
        if {[dict exists $s cell_field]} {set b [dict get $s cell_field];set nodes [dict get $b nodes_dataset_id]
            foreach id [list [dict get $b node_id_variable_id] [dict get $b x_variable_id] [dict get $b y_variable_id]] {dict set variables "$nodes:$id" [dict create dataset_id $nodes variable_id $id]}
            foreach id [concat [list [dict get $b cell_id_variable_id] [dict get $b scalar_variable_id]] [dict get $b node_variable_ids]] {dict set variables "$ds:$id" [dict create dataset_id $ds variable_id $id]}
        }
    };return $variables
}

# Existing public removal owners remain authoritative. Reconcile only this
# optional binding after an explicit canonical series/panel removal.
proc ::GX::PlotDatasetAPIv4::_cellFieldReconcile {ref} {
    set md [::GX::graphMetadataRead [_graphRef $ref]]
    if {![dict exists $md native_plot_v4_cell_fields]} return
    set spec [::GX::PlotDatasetAPIv2::loadSpec $ref];set ids {}
    foreach panel [dict get $spec panels] {foreach series [dict get $panel series] {lappend ids [dict get $series id]}}
    set fields {};dict for {id binding} [dict get $md native_plot_v4_cell_fields] {if {$id in $ids} {dict set fields $id $binding}}
    ::GX::graphMetadataUpdate [_graphRef $ref] [dict create native_plot_v4_cell_fields $fields native_plot_v4_cell_field_required [expr {[dict size $fields]>0}]]
}
proc ::GX::PlotDatasetAPIv4::removeSeries {ref seriesId} {
    _ready;set result [::GX::PlotDatasetAPIv1::removeSeries $ref $seriesId];_cellFieldReconcile $ref;return $result
}
proc ::GX::PlotDatasetAPIv4::removePanel {ref panelId} {
    _ready;set result [::GX::PlotDatasetAPIv2::removePanel $ref $panelId];_cellFieldReconcile $ref;return $result
}
