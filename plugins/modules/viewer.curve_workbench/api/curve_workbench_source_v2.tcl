# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset authority is the shared Source/Transform API. Large exact geometry
# lives in Native2D and owned document resources, never in a Tcl point list.
proc ::GX::CurveWorkbench::_bulkRecord {record} {return [dict exists $record geometry_resource]}
proc ::GX::CurveWorkbench::_pointCount {record} {
    return [expr {[_bulkRecord $record] ? [dict get $record point_count] : [llength [dict get $record samples]]}]
}
proc ::GX::CurveWorkbench::_axisLabel {variable} {
    set label [::GX::datasetPublicationV2DictDefault $variable display_label ""]
    if {[string trim $label] eq ""} {set label [dict get $variable variable_id]}
    if {[dict get $variable unit] ne ""} {append label " ([dict get $variable unit])"}
    return $label
}
proc ::GX::CurveWorkbench::_sourceRequest {dataset x y filter value family member order} {
    set filters {}
    foreach {variable chosen} [list $filter $value $family $member] {
        if {$variable ne ""} {lappend filters [dict create filter_variable_id $variable predicate exact_equal value $chosen]}
    }
    set request [dict create dataset_id $dataset x_variable_id $x y_variable_id $y display_budget 65536]
    if {$filters ne {}} {dict set request filters $filters}
    if {$order ne ""} {dict set request order_variable_id $order}
    return $request
}
proc ::GX::CurveWorkbench::_sourceSamples {token dataset order {progress ""}} {
    if {$progress eq ""} {set display [::GX::curveSourceDisplay $token]} else {set display [::GX::curveSourceDisplayResponsive $token $progress]}
    if {[dict get $display reduced]} {error "This exact point-list API is bounded to 65536 rows; use Curve Source streaming or the paged Workbench"}
    set orders [dict get $display source_rows]
    if {$order ne ""} {
        set stream [::GX::curveSourceOpenStream $token [list $order] 65536 [dict create numeric_transport values]]
        try {
            set page [::GX::tableStreamNext $stream]
            set all [dict get $page values $order];set orders {}
            # The ordered view may contain nonfinite XY rows omitted from display.
            set request [dict get [::GX::curveSourceDescribe $token] request]
            set xyPage [::GX::curveSourceOpenStream $token {} 65536 [dict create numeric_transport values]]
            try {
                set pairs [::GX::tableStreamNext $xyPage];set i 0
                foreach x [dict get $pairs values [dict get $request x_variable_id]] y [dict get $pairs values [dict get $request y_variable_id]] {
                    if {![catch {_finite $x X;_finite $y Y}]} {lappend orders [lindex $all $i]};incr i
                }
            } finally {::GX::curveSourceCloseStream $token $xyPage}
        } finally {::GX::curveSourceCloseStream $token $stream}
    }
    set samples {}
    foreach xy [dict get $display points] row [dict get $display source_rows] position $orders {
        lassign $xy x y;lappend samples [dict create x $x y $y row $row order $position point_id "source:$dataset:$row"]
    }
    return [dict create samples $samples breaks [dict get $display breaks]]
}
proc ::GX::CurveWorkbench::loadCurves {dataset x y {filter ""} {value ""} {family ""} {order ""}} {
    set members [expr {$family eq "" ? [list ""] : [_familyValues $dataset $family $filter $value]}]
    set groups {}
    foreach member $members {
        set source [::GX::curveSourceOpen [_session] [_sourceRequest $dataset $x $y $filter $value $family $member $order]]
        try {
            if {[dict get [::GX::curveSourceDescribe $source] row_count]>65536} {error "Exact point-list loading is limited to 65536 source rows per curve; use the paged Workbench or Curve Source API"}
            dict set groups $member [dict get [_sourceSamples $source $dataset $order] samples]
        } finally {::GX::curveSourceClose $source}
    }
    return $groups
}
proc ::GX::CurveWorkbench::_ingestSource {w record input} {
    variable st
    set native 0
    try {
        set native [::GX::native2DLoadNumericRowsWithGaps $st($w,scene) [dict get $input xy_file] [dict get $input break_before_file] [list ::GX::CurveWorkbench::_sourceLoadProgress $w [dict get $record source_token]]]
        dict set record geometry_resource [::GX::interactiveDocumentResourceImportNumeric $st($w,document) [dict get $input xy_file] [dict create format native2d.float64_xy_le_v1 point_count [dict get $input row_count]]]
        dict set record row_resource [::GX::interactiveDocumentResourceImportNumeric $st($w,document) [dict get $input source_rows_file] [dict create format uint64_le row_count [dict get $input row_count]]]
        dict set record gap_resource [::GX::interactiveDocumentResourceImportNumeric $st($w,document) [dict get $input break_before_file] [dict create format native2d.uint8_break_before_v1 point_count [dict get $input row_count]]]
        dict set record point_count [dict get $input row_count];dict set record locked 1
        dict set record finite_policy [dict get $input finite_policy]
        _addRecord $w $record $native;set native 0
        return [dict get $record id]
    } finally {if {$native!=0} {::GX::Native2D::core delete $st($w,scene) $native}}
}
proc ::GX::CurveWorkbench::_sourceAdd {w} {
    variable st
    set dataset $st($w,source.dataset);set x [_sourceId $w x];set y [_sourceId $w y]
    set filter [_sourceId $w filter];set family [_sourceId $w family];set order [_sourceId $w order]
    set value $st($w,source.filterValue)
    set members [list ""]
    if {$family ne ""} {
        set members $st($w,source.familyValues);set choices [$w.source.familyPanel.list curselection]
        if {$choices ne {}} {set members [lmap i $choices {lindex $members $i}]}
    }
    set created {};set before [_snapshotIds $w {}];set source ""
    set priorConfiguration $st($w,coordinateConfiguration);set priorSketchUnit $st($w,sketchUnit)
    set adopt [_coordinateWorkspaceEmpty $w]
    try {
        foreach member $members {
            set request [_sourceRequest $dataset $x $y $filter $value $family $member $order]
            set source [::GX::curveSourceOpen [_session] $request]
            set descriptor [::GX::curveSourceDescribe $source]
            set name [expr {$family eq "" ? [_datasetName $dataset] : "[_datasetName $dataset] · $member"}]
            set record [_newRecord $w $name {} $dataset $x $y $filter $value $member $order {} [list "import:$dataset"]]
            dict set record source_request $request;dict set record source_descriptor $descriptor
            set targetFrame [_coordinateSourceFrame $w $record]
            if {$adopt && $created eq {}} {
                dict set st($w,coordinateConfiguration) x_unit [lindex $targetFrame 0]
                dict set st($w,coordinateConfiguration) y_unit [lindex $targetFrame 1]
                set st($w,sketchUnit) [lindex $targetFrame 0]
            }
            if {[dict get $descriptor row_count]>65536} {
                if {$st($w,document) eq {}} {_flushWorkspace $w}
                dict set record source_token $source
                set id [::GX::curveSourceWithNumericInput $source [list ::GX::CurveWorkbench::_ingestSource $w $record] {} [list ::GX::CurveWorkbench::_sourceLoadProgress $w $source]]
                set source ""
            } else {
                set exact [_sourceSamples $source $dataset $order [list ::GX::CurveWorkbench::_sourceLoadProgress $w $source]]
                dict set record samples [dict get $exact samples];dict set record breaks [dict get $exact breaks]
                set id [_addRecord $w $record]
                ::GX::curveSourceClose $source;set source ""
            }
            lappend created $id;dict set before $id ""
            _coordinateNormalizeSource $w $id $targetFrame
        }
        if {$created eq {}} {error "No curves match the source selection"}
    } on error {message options} {
        foreach id $created {_removeRecord $w $id}
        set st($w,coordinateConfiguration) $priorConfiguration;set st($w,sketchUnit) $priorSketchUnit
        return -options $options $message
    } finally {if {$source ne ""} {::GX::curveSourceClose $source}}
    set st($w,active) [lindex $created 0];_selectionScene $w
    _coordinateFrameSync $w 0
    ::GX::Native2D::core fit $st($w,scene)
    _coordinateMagnify $w 1
    _history $w $before $created
    set st($w,status) "Added [llength $created] exact Dataset curve(s). Large curves use paged points; Convert to Native creates an explicit editable subset."
    append st($w,status) " Native working axes: [join [_coordinateUnits [_record $w $st($w,active)]] { / }]; original Dataset values and units are preserved."
    destroy $w.source
}
proc ::GX::CurveWorkbench::_sampleAt {w id index} {
    variable st
    set record [_record $w $id]
    if {![_bulkRecord $record]} {return [lindex [dict get $record samples] $index]}
    if {![string is entier -strict $index]||$index<0||$index>=[_pointCount $record]} {error "Point index is outside the exact curve"}
    set xy [lindex [::GX::Native2D::core points_page $st($w,scene) [dict get $record native] $index 1] 0]
    binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $record row_resource] [expr {8*$index}] 8] wu row
    return [dict create x [lindex $xy 0] y [lindex $xy 1] row $row order $index point_id "source:[dict get $record source]:$row"]
}
proc ::GX::CurveWorkbench::_pointPagerGui {w} {
    variable st
    ttk::frame $w.leftScroll.viewport.content.pointPager;pack $w.leftScroll.viewport.content.pointPager -fill x
    foreach {id label action} {first First first previous Previous previous next Next next last Last last} {
        ttk::button $w.leftScroll.viewport.content.pointPager.$id -text $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_pointPage $w $action]]
        pack $w.leftScroll.viewport.content.pointPager.$id -side left -padx 2
    }
    ttk::entry $w.leftScroll.viewport.content.pointPager.page -textvariable ::GX::CurveWorkbench::st($w,pointPageInput) -width 6
    ttk::button $w.leftScroll.viewport.content.pointPager.go -text Go -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_pointPage $w go]]
    pack $w.leftScroll.viewport.content.pointPager.page $w.leftScroll.viewport.content.pointPager.go -side left -padx 2
    bind $w.leftScroll.viewport.content.pointPager.page <Return> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_pointPage $w go]]
    ttk::label $w.leftScroll.viewport.content.pointPageLabel -textvariable ::GX::CurveWorkbench::st($w,pointPageLabel);pack $w.leftScroll.viewport.content.pointPageLabel -fill x
}
proc ::GX::CurveWorkbench::_pointPage {w action} {
    variable st
    if {[::GX::Native2D::core drag_active $st($w,selectionScene)]} {error "Finish or cancel the point drag before changing pages"}
    _pointSyncApply $w
    set total [_pointCount [_record $w [_active $w]]];set last [expr {200*(($total-1)/200)}]
    switch -- $action {
        first {set start 0} previous {set start [expr {$st($w,pointPageStart)-200}]} next {set start [expr {$st($w,pointPageStart)+200}]} last {set start $last}
        go {if {![string is entier -strict $st($w,pointPageInput)]||$st($w,pointPageInput)<1||$st($w,pointPageInput)>($last/200+1)} {error "Page must be between 1 and [expr {$last/200+1}]"};set start [expr {200*($st($w,pointPageInput)-1)}]}
        default {error "Unknown point page action"}
    }
    set st($w,pointPageStart) [expr {min($last,max(0,$start))}];_pointList $w;_draw $w
}
proc ::GX::CurveWorkbench::_pointTableSelected {w} {
    variable st
    set total [_pointCount [_record $w [_active $w]]];set start $st($w,pointPageStart)
    return [::GX::Native2D::core selected $st($w,selectionScene) $st($w,selectionObject) $start [expr {min(200,$total-$start)}]]
}
rename ::GX::CurveWorkbench::_pointList ::GX::CurveWorkbench::_pointList_v1
proc ::GX::CurveWorkbench::_pointList {w} {
    variable st
    if {![winfo exists $w.leftScroll.viewport.content.points]} return
    if {$st($w,active) eq ""||![dict exists $st($w,curves) $st($w,active)]} {_pointList_v1 $w;set st($w,pointPageLabel) "";return}
    set record [_record $w $st($w,active)];set total [_pointCount $record]
    if {$total<=200} {_pointList_v1 $w;set st($w,pointPageLabel) "$total exact points";return}
    set start $st($w,pointPageStart);set count [expr {min(200,$total-$start)}]
    set tree $w.leftScroll.viewport.content.points;set signature [list $st($w,active) $start $record [_coordinateKey $w $st($w,active)]]
    set oldRunning $st($w,pointSyncRunning);set st($w,pointSyncRunning) 1
    try {
        if {$signature ne $st($w,pointTableSignature)} {
            set samples {}
            if {[_bulkRecord $record]} {
                set points [::GX::Native2D::core points_page $st($w,scene) [dict get $record native] $start $count]
                binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $record row_resource] [expr {8*$start}] [expr {8*$count}]] wu* rows
                foreach xy $points row $rows {lappend samples [dict create x [lindex $xy 0] y [lindex $xy 1] row $row]}
            } else {set samples [lrange [dict get $record samples] $start [expr {$start+$count-1}]]}
            $tree delete [$tree children {}];set i $start
            foreach point $samples {
                lassign [_coordinatePoint $w $st($w,active) [list [dict get $point x] [dict get $point y]]] dx dy
                $tree insert {} end -id p$i -values [list $i [format %.10g $dx] [format %.10g $dy] [dict get $point row]];incr i
            }
            set st($w,pointTableSignature) $signature
        }
        set selected [_pointTableSelected $w]
        set rows [lmap i $selected {format p%d $i}]
        if {[$tree selection] ne $rows} {$tree selection set $rows}
        set all [_semanticPointIndices $w $st($w,active)];set summary [dict create count [llength $all] first [lindex $all 0]]
        if {[dict get $summary count]==1} {set point [_sampleAt $w $st($w,active) [dict get $summary first]];lassign [_coordinatePoint $w $st($w,active) [list [dict get $point x] [dict get $point y]]] st($w,editX) st($w,editY)}
        set st($w,pointPageLabel) "Exact points $start–[expr {$start+$count-1}] / $total · [dict get $summary count] selected"
        set st($w,pointPageInput) [expr {$start/200+1}]
    } finally {set st($w,pointSyncRunning) $oldRunning}
}
proc ::GX::CurveWorkbench::_pointSelectionDescriptor {w} {
    variable st
    set count [_pointCount [_record $w [_active $w]]];set descriptor {};set manual {}
    for {set start 0} {$start<$count} {incr start 65536} {
        set page [::GX::Native2D::core selection_state $st($w,selectionScene) $st($w,selectionObject) $start [expr {min(65536,$count-$start)}]]
        if {$descriptor eq {}} {set descriptor [dict remove $page manual]}
        set manual [concat $manual [dict get $page manual]]
        if {[llength $manual]>65536} {error "Selection contains more than 65536 manual overrides; use rectangle selection for large sets"}
    }
    dict set descriptor manual $manual;return $descriptor
}
proc ::GX::CurveWorkbench::_restorePointSelectionDescriptor {w descriptor} {
    variable st
    if {[dict get $descriptor base_selected]} {::GX::Native2D::core select_object $st($w,selectionScene) $st($w,selectionObject) add}
    foreach region [dict get $descriptor regions] {::GX::Native2D::core rect $st($w,selectionScene) [dict get $region bounds] [dict get $region mode]}
    foreach pair [dict get $descriptor manual] {lassign $pair index mode;::GX::Native2D::core select $st($w,selectionScene) $st($w,selectionObject) $index [expr {$mode==1 ? "add" : "subtract"}]}
}
proc ::GX::CurveWorkbench::convertToNative {w start count {name ""}} {
    variable st
    set sourceId [_active $w];set record [_record $w $sourceId];set total [_pointCount $record]
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<2||$count>65536||$start+$count>$total} {error "Choose an exact range of 2..65536 points inside the curve; large sources remain authoritative and unchanged"}
    if {$name eq ""} {set name "[dict get $record name] · Native $start–[expr {$start+$count-1}]"}
    set coords [::GX::Native2D::core points_page $st($w,scene) [dict get $record native] $start $count]
    if {[_bulkRecord $record]} {
        _sourceSnapshotRequire $w $record
        ::GX::curveSourceDescribe [dict get $record source_token]
        binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $record row_resource] [expr {8*$start}] [expr {8*$count}]] wu* rows
        binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $record gap_resource] $start $count] cu* gaps
        set samples {};set breaks {};set index 0
        foreach point $coords row $rows gap $gaps {
            lappend samples [dict create x [lindex $point 0] y [lindex $point 1] row $row order [expr {$start+$index}] point_id "source:[dict get $record source]:$row"]
            if {$index>0&&$gap} {lappend breaks [expr {$index-1}]};incr index
        }
    } else {
        set samples [lrange [dict get $record samples] $start [expr {$start+$count-1}]]
        set breaks {};foreach at [dict get $record breaks] {if {$at>=$start&&$at<$start+$count-1} {lappend breaks [expr {$at-$start}]}}
    }
    set derived [_newRecord $w $name $samples [dict get $record source] [dict get $record x] [dict get $record y] [dict get $record filter] [dict get $record filter_value] [dict get $record family] [dict get $record order] [list $sourceId] [list [dict create operation convert_to_native start $start count $count policy exact_bounded_range]]]
    dict set derived breaks $breaks
    set id [dict get $derived id];set before [dict create $id ""]
    _addRecord $w $derived;set st($w,active) $id;_selectionScene $w;_history $w $before [list $id]
    return $id
}
proc ::GX::CurveWorkbench::_convertOpen {w} {
    variable st
    set record [_record $w [_active $w]];set total [_pointCount $record]
    set fields [dict create start [dict create type integer label {First exact point index} min 0 max [expr {$total-2}]] count [dict create type integer label {Exact point count (maximum 65536)} min 2 max [expr {min(65536,$total)}]] name [dict create type string label {New Native curve name}]]
    set values [dict create start $st($w,pointPageStart) count [expr {min(200,$total-$st($w,pointPageStart))}] name "[dict get $record name] · Native"]
    ::GX::uiFieldFormCreate $w.convert "Convert exact range to Native" $fields $values [list ::GX::CurveWorkbench::_convertApply $w [_active $w]] $w
}
proc ::GX::CurveWorkbench::_convertApply {w source values} {
    if {[_active $w] ne $source} {error "Active curve changed; reopen Convert to Native"}
    return [convertToNative $w [dict get $values start] [dict get $values count] [dict get $values name]]
}
rename ::GX::CurveWorkbench::publish ::GX::CurveWorkbench::publish_v1
proc ::GX::CurveWorkbench::publish {w requested {ids {}}} {
    variable st
    if {$ids eq {}} {set ids [list [_active $w]]}
    set bulk 0;set datasetOnly 1;set hasDataset 0
    foreach id $ids {set record [_record $w $id];if {[_bulkRecord $record]} {set bulk 1};if {[dict get $record source] ne {}} {set hasDataset 1};if {[dict get $record edited]||![dict exists $record source_request]} {set datasetOnly 0}}
    set outputMode [expr {[info exists st($w,publicationRepresentation)] ? $st($w,publicationRepresentation) : "cartesian"}]
    set arrangement [expr {[info exists st($w,publicationArrangement)] ? $st($w,publicationArrangement) : "table"}]
    if {$arrangement ni {table long wide}} {error "Choose table, long family or wide output"}
    if {$arrangement eq "wide"&&$outputMode ne "cartesian"} {error "Wide output has multiple Y axes. Choose Cartesian wide output, or table/long for one explicit polar coordinate pair."}
    if {$outputMode ni {cartesian polar both}} {error "Choose Cartesian, polar or both output coordinates"}
    if {!$bulk&&!$datasetOnly&&!$hasDataset&&$outputMode eq "cartesian"&&$arrangement eq "table"} {return [publish_v1 $w $requested $ids]}
    if {[string trim $requested] eq ""} {error "Enter the requested public Dataset ID"}
    set requested [::GX::datasetPublicationV2RequestedId $requested]
    if {$requested in [::GX::datasetRegistryIds]} {error "Dataset '$requested' already exists; choose a new Dataset ID"}
    set sources {};set provenance {}
    foreach id $ids {
        set record [_record $w $id]
        _sourceSnapshotRequire $w $record
        set role [::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get $record native]]
        if {$role ne "regular"} continue
        if {[_bulkRecord $record]} {::GX::curveSourceDescribe [dict get $record source_token]}
        set request [::GX::datasetPublicationV2DictDefault $record source_request {}]
        set source [dict create member_id $id x_variable_id [dict get $record x] y_variable_id [dict get $record y]]
        if {[dict get $record source] ne {}} {dict set source dataset_id [dict get $record source]}
        if {[dict exists $request filters]} {dict set source row_filters [dict get $request filters]}
        if {[dict exists $request order_variable_id]&&![dict get $record edited]} {dict set source order_variable_ids [list [dict get $request order_variable_id]]}
        if {[dict exists $record working_unit]} {dict set source convert_units [dict create [dict get $record x] [dict get $record working_unit] [dict get $record y] [dict get $record working_unit]]}
        if {[dict exists $record coordinate_units]} {foreach axis {x y} unit [dict get $record coordinate_units] {dict set source convert_units [dict get $record $axis] $unit}}
        if {[dict exists $record source_assumed_units]} {dict set source assume_units [dict get $record source_assumed_units]}
        set marker [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]]
        dict set source reverse [expr {![dict get $marker forward]}]
        if {[dict get $record edited]||![dict exists $record source_request]} {
            dict set source native_geometry [_publicationNativeSource $w $id]
        }
        lappend sources $source;lappend provenance [dict remove $record native samples source_token geometry_resource row_resource gap_resource]
    }
    if {$sources eq {}} {error "No regular geometry is selected for publication"}
    set prefix workbench_;set suffix 1;set existing {}
    foreach source $sources {if {[dict exists $source dataset_id]} {foreach v [::GX::datasetVariableSchemaV3 [dict get $source dataset_id]] {lappend existing [dict get $v variable_id]}}}
    while {1} {
        set collision 0;foreach key {member_id source_dataset_id source_sha256 source_row_ordinal source_x_variable_id source_y_variable_id auxiliary_valid break_before} {if {"$prefix$key" in $existing} {set collision 1;break}}
        if {!$collision} break
        set prefix workbench[incr suffix]_
    }
    set metadata [dict create curve_workbench.workspace_curve_ids [join $ids {;}] curve_workbench.provenance $provenance curve_workbench.exact_publication 1]
    set metadata [dict merge $metadata [_publicationSketchMetadata $w $ids]]
    set metadata [dict merge $metadata [_coordinatePublicationMetadata $w $ids]]
    set manifest [dict create api_version 1 operation concat_rows sources $sources output [dict create dataset_id $requested contract table.generic storage auto display_name "Curve Workbench: [dict get [_record $w [lindex $ids 0]] name]"] options [dict create include_lineage 1 lineage_prefix $prefix metadata_overrides $metadata]]
    if {$arrangement ne "table"} {
        dict set manifest operation curve_bundle
        dict set manifest options representation $arrangement
        dict set manifest options preserve_auxiliary 1
        if {$arrangement eq "long"} {dict set manifest output contract curve_family.table}
    }
    if {$outputMode ne "cartesian"} {
        set x x;set y y
        foreach source $sources {if {[dict exists $source dataset_id]} {set x [dict get $source x_variable_id];set y [dict get $source y_variable_id];break}}
        if {$arrangement eq "long"} {set x x;set y y}
        set polar [dict create representation $outputMode frame [::GX::Native2D::core polar $st($w,scene)] x_variable_id $x y_variable_id $y]
        foreach {key name} {theta_variable_id theta radius_variable_id r angle_defined_variable_id theta_defined} {dict set polar $key [expr {$name in $existing ? "$prefix$name" : $name}]}
        dict set manifest options polar_output $polar
    }
    set result [_publicationRunTransform $w $manifest]
    set action [expr {[info exists st($w,publicationPrepareOnly)] && $st($w,publicationPrepareOnly) ? {Prepared} : {Published}}]
    set st($w,status) "$action $requested: [dict get $result row_count] complete tuples / explicit Native samples with source lineage."
    return $result
}
proc ::GX::CurveWorkbench::_sourceSnapshotRequire {w record} {
    variable st
    foreach dependency [concat [list $record] [dict get $record ancestors]] {
        if {![dict exists $dependency source_descriptor]} continue
        set result [::GX::curveSourceValidateSnapshot [_session] [dict get $dependency source_descriptor]]
        if {![dict get $result valid]} {
            set id [dict get $record id];dict set st($w,curves) $id source_state [dict get $result status]
            set st($w,status) "Dataset source [dict get $result status]: [concat [dict get $result missing_dataset_ids] [dict get $result stale_dataset_ids]]. Cached local geometry is retained. Preview the source and reload it explicitly before source-tuple publication."
            return -code error $st($w,status)
        }
    }
}
proc ::GX::CurveWorkbench::_sourcePreviewActive {w} {
    variable st
    set record [_record $w [_active $w]];set id [dict get $record source]
    if {$id eq {}} {error "This is local Native geometry; it has no source Dataset"}
    if {[dict exists $record source_descriptor]} {
        set result [::GX::curveSourceValidateSnapshot [_session] [dict get $record source_descriptor]]
        dict set st($w,curves) [dict get $record id] source_state [dict get $result status]
        if {[dict get $result status] eq "missing"} {error "Source Dataset '$id' is missing. Cached local geometry remains available; restore or explicitly reload its Dataset source."}
        if {[dict get $result status] eq "stale"} {set st($w,status) "Previewing changed Dataset '$id'. Cached Workbench geometry is unchanged; reload explicitly before tuple publication."}
    }
    _curveList $w
    return [::GX::datasetPreviewOpenTable $id]
}
proc ::GX::CurveWorkbench::_installSourceControls {w} {
    variable st
    
    if {![info exists st($w,publicationRepresentation)]} {set st($w,publicationRepresentation) cartesian}
    if {![info exists st($w,publicationArrangement)]} {set st($w,publicationArrangement) table}
    if {![winfo exists $w.toolbar.sourcePreview]} {
        ttk::button $w.toolbar.sourcePreview -text "Source Dataset Preview…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_sourcePreviewActive $w]]
        ::GX::native2DToolbarLayout $w.toolbar [winfo width $w.toolbar]
    }
    if {![winfo exists $w.publish.coordinates]} {
        ttk::label $w.publish.coordinatesLabel -text Coordinates
        ttk::combobox $w.publish.coordinates -textvariable ::GX::CurveWorkbench::st($w,publicationRepresentation) -state readonly -values {cartesian polar both} -width 10
    }
    if {![winfo exists $w.publish.arrangement]} {
        ttk::label $w.publish.arrangementLabel -text Arrangement
        ttk::combobox $w.publish.arrangement -textvariable ::GX::CurveWorkbench::st($w,publicationArrangement) -state readonly -values {table long wide} -width 8
    }
    bind $w.publish <Configure> [list ::GX::CurveWorkbench::_publicationLayout $w %w]
    after idle [list ::GX::CurveWorkbench::_publicationLayout $w [winfo width $w.publish]]

}
proc ::GX::CurveWorkbench::_publicationNativeSource {w id} {
    variable st
    set record [_record $w $id]
    lassign [_coordinateUnits $record] xUnit yUnit
    if {[dict get $record representation] eq "spline"} {lassign [_evaluatedObject $w $id] native temporary} else {set native [dict get $record native];set temporary 0}
    try {set xy [::GX::interactiveDocumentNative2DStore $st($w,document) $st($w,scene) $native]} finally {if {$temporary} {::GX::Native2D::core delete $st($w,scene) $native}}
    set count [expr {[dict get $xy size_bytes]/16}]
    set geometry [dict create xy_resource $xy x_variable [dict create variable_id x name X display_label X dtype float64 rank 1 dimension_ids row coordinate_role coordinate semantic_role coordinate value_kind number unit $xUnit] y_variable [dict create variable_id y name Y display_label Y dtype float64 rank 1 dimension_ids row coordinate_role data semantic_role data value_kind number unit $yUnit]]
    set rowWriter [::GX::interactiveDocumentResourceOpenWriter $st($w,document) [dict create format uint64_le row_count $count]]
    set gapWriter {};set writers [list $rowWriter]
    try {
        set gapWriter [::GX::interactiveDocumentResourceOpenWriter $st($w,document) [dict create format native2d.uint8_break_before_v1 point_count $count]];lappend writers $gapWriter
        set explicit [expr {[dict get $record representation] ne "spline"&&$count==[_pointCount $record]}]
        set breaks [dict get $record breaks]
        for {set start 0} {$start<$count} {incr start 4096} {
            set rows {};set gaps {}
            for {set i $start} {$i<min($count,$start+4096)} {incr i} {
                set row -1;if {$explicit} {set row [dict get [_sampleAt $w $id $i] row]}
                lappend rows [expr {$row<0 ? 18446744073709551615 : $row}]
                lappend gaps [expr {$explicit&&$i>0&&($i-1) in $breaks}]
            }
            ::GX::interactiveDocumentResourceAppend $rowWriter [binary format wu* $rows]
            ::GX::interactiveDocumentResourceAppend $gapWriter [binary format c* $gaps]
        }
        dict set geometry row_resource [::GX::interactiveDocumentResourceFinalize $rowWriter];set writers [lrange $writers 1 end]
        dict set geometry gap_resource [::GX::interactiveDocumentResourceFinalize $gapWriter];set writers {}
        return $geometry
    } finally {foreach writer $writers {::GX::interactiveDocumentResourceAbort $writer}}
}
