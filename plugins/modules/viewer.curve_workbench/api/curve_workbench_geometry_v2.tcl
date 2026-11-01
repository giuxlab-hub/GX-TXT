# SPDX-License-Identifier: GPL-3.0-or-later
# Exact bounded editing and explicit Native2D topology/bridge workflow.
proc ::GX::CurveWorkbench::_publicationWidgets {root} {
    set result {}
    foreach child [winfo children $root] {
        if {[winfo class $child] in {TButton TEntry TCombobox TCheckbutton TRadiobutton Treeview}} {lappend result $child}
        set result [concat $result [_publicationWidgets $child]]
    }
    return $result
}
proc ::GX::CurveWorkbench::_publicationProgress {w event} {
    variable st
    set st($w,publishJob) [dict get $event job_id]
    set stage [dict get $event stage]
    set st($w,publishStage) $stage;set st($w,publishRows) [dict get $event current]
    if {[dict get $event total]>0} {set detail "[dict get $event current]/[dict get $event total] exact rows"} else {set detail "exact source planning"}
    set st($w,status) "Dataset publication: $stage · $detail · Escape cancels before commit"
}
proc ::GX::CurveWorkbench::_publicationCancelled {w} {variable st;return $st($w,publishCancelled)}
proc ::GX::CurveWorkbench::_publicationCancel {w} {
    variable st
    set st($w,publishCancelled) 1
    if {$st($w,publishJob) ne ""} {
        if {[string match curve-source-job#* $st($w,publishJob)]} {::GX::curveSourceCancel $st($w,publishJob)} else {::GX::datasetTransformCancel $st($w,publishJob)}
    }
    set st($w,status) "Cancelling $st($w,busyLabel) before commit…"
}
proc ::GX::CurveWorkbench::_cooperativeBegin {w label} {
    variable st
    if {$st($w,publishBusy)} {error "Finish or cancel the current Workbench operation"}
    _cancelGesture $w;_save $w
    if {$st($w,document) eq {}} {_flushWorkspace $w}
    set widgets [_publicationWidgets $w];set saved [dict create]
    foreach widget $widgets {
        if {$widget eq "$w.source.buttons.cancel"} continue
        dict set saved $widget [$widget state];$widget state disabled
    }
    set oldCursor [$w cget -cursor];$w configure -cursor watch
    set st($w,publishBusy) 1;set st($w,publishCancelled) 0;set st($w,publishJob) ""
    set st($w,busyLabel) $label
    return [list $saved $oldCursor]
}
proc ::GX::CurveWorkbench::_cooperativeEnd {w frozen} {
    variable st
    lassign $frozen saved oldCursor
    set st($w,publishBusy) 0;set st($w,publishJob) ""
    dict for {widget state} $saved {if {[winfo exists $widget]} {$widget state !disabled;$widget state $state}}
    if {[winfo exists $w]} {$w configure -cursor $oldCursor}
}
proc ::GX::CurveWorkbench::_publicationRunTransform {w manifest} {
    variable st
    set outer [expr {[info exists st($w,publicationBatchActive)] && $st($w,publicationBatchActive)}]
    if {!$outer} {set frozen [_cooperativeBegin $w {Dataset publication}]}
    try {
        set command ::GX::datasetTransformExecuteResponsive
        if {[info exists st($w,publicationPrepareOnly)] && $st($w,publicationPrepareOnly)} {set command ::GX::datasetTransformPlanResponsive}
        return [$command [_session] $manifest [dict create progress_command [list ::GX::CurveWorkbench::_publicationProgress $w] cancel_command [list ::GX::CurveWorkbench::_publicationCancelled $w] chunk_rows 8192]]
    } finally {
        if {!$outer} {_cooperativeEnd $w $frozen}
    }
}
proc ::GX::CurveWorkbench::_sourceLoadProgress {w source event} {
    variable st
    if {$st($w,publishCancelled)} {return -code error -errorcode {GX CURVE_SOURCE CANCELLED} "Curve loading cancelled; previous workspace geometry is retained"}
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error "Session lifetime changed during curve loading; reopen Curve Workbench"}
    ::GX::curveSourceDescribe $source
    set st($w,publishJob) [::GX::datasetPublicationV2DictDefault $event job_id ""]
    set stage [::GX::datasetPublicationV2DictDefault $event stage display]
    set st($w,publishStage) $stage;set st($w,publishRows) [dict get $event completed_rows]
    set st($w,status) "Curve loading: $stage · [dict get $event completed_rows]/[dict get $event total_rows] exact rows · Escape cancels"
}
proc ::GX::CurveWorkbench::_sourceClose {w} {
    variable st
    if {$st($w,publishBusy)} {_publicationCancel $w;return}
    destroy $w.source
}
rename ::GX::CurveWorkbench::_sourceAdd ::GX::CurveWorkbench::_sourceAdd_geometry_base
proc ::GX::CurveWorkbench::_sourceAdd {w} {
    if {![_timelineEditable $w]} return
    variable st
    set frozen [_cooperativeBegin $w {curve loading}]
    try {_sourceAdd_geometry_base $w} on error {message options} {
        if {$st($w,document) ne ""&&$st($w,token) eq [::GX::interactiveDocumentSessionToken]} {::GX::interactiveDocumentResourceCollect $st($w,document)}
        return -options $options $message
    } finally {_cooperativeEnd $w $frozen}
}
rename ::GX::CurveWorkbench::_cancelGesture ::GX::CurveWorkbench::_cancelGesture_geometry_base
proc ::GX::CurveWorkbench::_cancelGesture {w} {
    variable st
    if {[info exists st($w,publishBusy)]&&$st($w,publishBusy)} {_publicationCancel $w;return}
    _cancelGesture_geometry_base $w
}
foreach operation {_wheel _coordinates _pointTreeSelect} {
    rename ::GX::CurveWorkbench::$operation ::GX::CurveWorkbench::${operation}_geometry_base
    proc ::GX::CurveWorkbench::$operation {w args} [format {
        variable st
        if {[info exists st($w,publishBusy)]&&$st($w,publishBusy)} return
        tailcall ::GX::CurveWorkbench::%s_geometry_base $w {*}$args
    } $operation]
}
proc ::GX::CurveWorkbench::_rangeSamples {w id first count} {
    variable st
    set r [_record $w $id];set total [_pointCount $r]
    if {$first<0||$count<1||$count>65536||$first+$count>$total} {
        error "Choose an exact range of at most 65536 points; Convert to Native keeps the complete Dataset source unchanged"
    }
    if {![_bulkRecord $r]} {return [lrange [dict get $r samples] $first [expr {$first+$count-1}]]}
    _sourceSnapshotRequire $w $r
    ::GX::curveSourceDescribe [dict get $r source_token]
    set xy [::GX::Native2D::core points_page $st($w,scene) [dict get $r native] $first $count]
    binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $r row_resource] [expr {8*$first}] [expr {8*$count}]] wu* rows
    set samples {};set index $first
    foreach point $xy row $rows {
        lappend samples [dict create x [lindex $point 0] y [lindex $point 1] row $row order $index point_id "source:[dict get $r source]:$row"]
        incr index
    }
    return $samples
}
proc ::GX::CurveWorkbench::_selectedControls {w maximum} {
    variable st
    _pointSyncApply $w
    set summary [::GX::Native2D::core selection_summary $st($w,selectionScene) $st($w,selectionObject)]
    set count [dict get $summary count]
    if {$count<2||$count>$maximum} {error "Select 2..$maximum exact control points; use an explicit smaller selection or Convert to Native"}
    set indices {};set controls {};set id [_active $w]
    for {set start [dict get $summary first]} {$start<=[dict get $summary last]} {incr start 65536} {
        set n [expr {min(65536,[dict get $summary last]-$start+1)}]
        set selected [::GX::Native2D::core selected $st($w,selectionScene) $st($w,selectionObject) $start $n]
        foreach index $selected {lappend indices $index;lappend controls [_sampleAt $w $id $index]}
    }
    return [list $indices $controls]
}
proc ::GX::CurveWorkbench::_selectedRange {w} {
    variable st
    _pointSyncApply $w
    set summary [::GX::Native2D::core selection_summary $st($w,selectionScene) $st($w,selectionObject)]
    if {[dict get $summary count]<2} {error "Select two or more points to define a range"}
    return [list [dict get $summary first] [dict get $summary last]]
}
proc ::GX::CurveWorkbench::_deriveControls {w representation maximum} {
    variable st
    set source [_active $w];set r [_record $w $source]
    lassign [_selectedControls $w $maximum] indices controls
    foreach break [dict get $r breaks] {
        if {$break>=[lindex $indices 0]&&$break<[lindex $indices end]} {error "Controls cannot cross a disconnected gap"}
    }
    if {[_bulkRecord $r]} {
        set first [lindex $indices 0];set last [lindex $indices end]
        for {set start [expr {$first+1}]} {$start<=$last} {incr start 65536} {
            set bytes [::GX::interactiveDocumentResourceReadChunk [dict get $r gap_resource] $start [expr {min(65536,$last-$start+1)}]]
            if {[string first \x01 $bytes]>=0} {error "Controls cannot cross a disconnected gap"}
        }
    }
    set suffix [expr {$representation eq "spline" ? "spline" : "simplified"}]
    set derived [_newRecord $w "[dict get $r name] $suffix" $controls [dict get $r source] [dict get $r x] [dict get $r y] [dict get $r filter] [dict get $r filter_value] [dict get $r family] [dict get $r order] [list $source] [list [dict create operation ${representation}_controls indices $indices source_authority unchanged sampling_policy exact_selected_points]] $representation]
    set id [dict get $derived id];set before [dict create $id ""]
    _addRecord $w $derived;set st($w,active) $id;set st($w,reference) $source
    _selectionScene $w;_history $w $before [list $id]
    return $id
}
proc ::GX::CurveWorkbench::_makeSpline {w} {_deriveControls $w spline 4096}
proc ::GX::CurveWorkbench::_makeLinear {w} {_deriveControls $w linear 65536}
proc ::GX::CurveWorkbench::_fragmentMaterialize {w fragment} {
    variable st
    lassign $fragment id first last reversed
    set r [_record $w $id];set count [expr {$last-$first+1}]
    if {$first<0||$last>=[_pointCount $r]||$count<2} {error "A composition fragment is stale; remove and add it again"}
    set controls [_rangeSamples $w $id $first $count]
    if {[dict get $r representation] ne "spline"} {
        return [list [::GX::Native2D::core extract $st($w,scene) [dict get $r native] $first $last] $controls]
    }
    set per 16
    if {($count-1)*$per+1>65536} {error "A spline composition fragment supports at most 4096 controls at 16 subdivisions; select a smaller exact range"}
    set coords [::GX::Native2D::core spline_range $st($w,scene) [dict get $r native] $first [expr {$count-1}] $per]
    set samples {};set i 0
    foreach xy $coords {
        if {$i%$per==0} {set p [lindex $controls [expr {$i/$per}]]} else {set p [dict create row -1 order "" point_id "spline_sample:$id:$first:$i"]}
        dict set p x [lindex $xy 0];dict set p y [lindex $xy 1];lappend samples $p;incr i
    }
    return [list [::GX::Native2D::core add $st($w,scene) $coords] $samples]
}
proc ::GX::CurveWorkbench::_evaluatedObject {w id} {
    variable st
    set r [_record $w $id]
    if {[dict get $r breaks] ne {}} {error "Compare disconnected curve fragments separately"}
    if {[dict get $r representation] ne "spline"} {return [list [dict get $r native] 0]}
    return [list [::GX::Native2D::core spline_object $st($w,scene) [dict get $r native] 16] 1]
}
proc ::GX::CurveWorkbench::_fragmentFrame {w fragment end} {
    variable st
    lassign $fragment id first last reverse
    set r [_record $w $id];set incoming [expr {$end!=$reverse}]
    set index [expr {$incoming ? $last : $first}]
    return [::GX::Native2D::core point_frame $st($w,scene) [dict get $r native] $index $incoming $reverse [expr {[dict get $r representation] eq "spline"}]]
}
proc ::GX::CurveWorkbench::_compositionBuild {w} {
    variable st
    set pieces {};set samples {};set parents {};set operations {};set bridges {};set created {};set previous {};set output ""
    set mode $st($w,bridgeKind)
    if {$mode ni {none straight quadratic cubic smooth}} {error "Choose a supported explicit bridge kind"}
    set fragmentParents [lsort -unique [lmap fragment $st($w,fragments) {lindex $fragment 0}]]
    _coordinatePlaneAdmit $w $fragmentParents
    try {
        foreach fragment $st($w,fragments) {
            lassign $fragment id first last reversed
            lassign [_fragmentMaterialize $w $fragment] native part;lappend created $native
            if {$reversed} {set part [lreverse $part]}
            if {$previous ne {}&&$mode ne "none"} {
                set start [_fragmentFrame $w $previous 1];set end [_fragmentFrame $w $fragment 0]
                if {[::GX::Native2D::core distance $st($w,scene) [dict get $start point] [dict get $end point]]>0} {
                    if {[catch {set receipt [::GX::Native2D::core bridge_frames $st($w,scene) $start $end $mode $st($w,bridgeSubdivisions) $st($w,bridgeTolerance)]} message options]} {
                        return -options $options "Bridge $mode failed: $message. Quadratic tangent rays must meet forward; cubic/smooth support independent endpoint tangents."
                    }
                    set bridge [dict get $receipt native];lappend created $bridge
                    set n [::GX::Native2D::core count $st($w,scene) $bridge]
                    if {$n>2} {
                        set interior [::GX::Native2D::core extract $st($w,scene) $bridge 1 [expr {$n-2}]];lappend created $interior
                        lappend pieces [list $interior 0 0]
                        set ordinal 0
                        foreach xy [::GX::Native2D::core points_page $st($w,scene) $interior 0 [expr {$n-2}]] {
                            lappend samples [dict create x [lindex $xy 0] y [lindex $xy 1] row -1 order "" point_id "bridge:[llength $bridges]:[incr ordinal]"]
                        }
                    }
                    dict set receipt from_fragment $previous;dict set receipt to_fragment $fragment
                    lappend bridges [dict remove $receipt native]
                } else {lappend bridges [dict create kind shared_endpoint point [dict get $start point] c0 1 from_fragment $previous to_fragment $fragment]}
            }
            if {[llength $samples]+[llength $part]>65536} {error "Editable composition is bounded to 65536 exact samples; select smaller fragments. Complete Dataset sources remain unchanged."}
            lappend pieces [list $native $reversed [expr {[llength $pieces]>0&&$mode eq "none"}]]
            set samples [concat $samples $part];lappend parents $id
            lappend operations [dict create operation fragment source $id first $first last $last reversed $reversed representation [dict get [_record $w $id] representation]]
            set previous $fragment
        }
        if {$pieces eq {}} {return {}}
        set output [::GX::Native2D::core concat $st($w,scene) $pieces]
        return [dict create native $output samples $samples parents $parents operations $operations bridges $bridges]
    } finally {foreach native $created {::GX::Native2D::core delete $st($w,scene) $native}}
}
proc ::GX::CurveWorkbench::_updateCompositionPreview {w} {
    variable st
    set signature [list $st($w,fragments) $st($w,bridgeKind) $st($w,bridgeSubdivisions) $st($w,bridgeTolerance)]
    foreach fragment $st($w,fragments) {lappend signature [dict remove [_record $w [lindex $fragment 0]] source_token]}
    if {$st($w,previewSignature) eq $signature} return
    if {[catch {set built [_compositionBuild $w]} message options]} {
        if {$st($w,previewNative) ne ""} {::GX::Native2D::core delete $st($w,scene) $st($w,previewNative)}
        set st($w,previewNative) "";set st($w,previewBuild) {};set st($w,previewSignature) {};set st($w,previewBreaks) {}
        return -options $options $message
    }
    if {$built ne {}} {::GX::Native2D::core visible $st($w,scene) [dict get $built native] 0}
    if {$st($w,previewNative) ne ""} {::GX::Native2D::core delete $st($w,scene) $st($w,previewNative)}
    set st($w,previewBuild) $built;set st($w,previewSignature) $signature;set st($w,previewNative) "";set st($w,previewBreaks) {}
    if {$built ne {}} {set st($w,previewNative) [dict get $built native];set st($w,previewBreaks) [::GX::Native2D::core breaks $st($w,scene) $st($w,previewNative)]}
}
proc ::GX::CurveWorkbench::_bridgeChanged {w} {
    variable st
    set st($w,bridge) [expr {$st($w,bridgeKind) eq "straight"}]
    _updateCompositionPreview $w;_draw $w
}
proc ::GX::CurveWorkbench::_bridgeLegacyToggle {w} {
    variable st
    set st($w,bridgeKind) [expr {$st($w,bridge) ? "straight" : "none"}]
    _bridgeChanged $w
}
proc ::GX::CurveWorkbench::_bridgeSettings {w} {
    variable st
    set ids {};foreach fragment $st($w,fragments) {set id [lindex $fragment 0];if {$id ni $ids} {lappend ids $id}}
    if {$ids eq {} && $st($w,active) ne {}} {set ids [list $st($w,active)]}
    set units [list [dict get $st($w,coordinateConfiguration) x_unit] [dict get $st($w,coordinateConfiguration) y_unit]]
    if {$ids ne {}} {set units [_coordinateUnits [_record $w [lindex $ids 0]]]}
    set label [_coordinatePlaneParameterLabel $units {Endpoint derivative tolerance (numeric plane)}]
    set fields [dict create subdivisions [dict create type integer label {Bridge subdivisions (explicit sampling)} min 3 max 4096] tolerance [dict create type number label $label min 1e-15 max 1]]
    ::GX::uiFieldFormCreate $w.bridgeSettings "Native2D bridge sampling and continuity" $fields [dict create subdivisions $st($w,bridgeSubdivisions) tolerance $st($w,bridgeTolerance)] [list ::GX::CurveWorkbench::_bridgeSettingsApply $w $st($w,token) $ids [_coordinateControlKey $w $ids] $st($w,coordinateConfiguration) $st($w,fragments)] $w
}
proc ::GX::CurveWorkbench::_bridgeSettingsApply {w token ids key configuration fragments fields} {
    variable st
    if {$token ne $st($w,token) || $configuration ne $st($w,coordinateConfiguration) || $fragments ne $st($w,fragments)} {error {Composition or coordinate frame changed; reopen bridge settings}}
    _coordinateControlCheck $w $ids $key
    set old [list $st($w,bridgeSubdivisions) $st($w,bridgeTolerance)]
    set st($w,bridgeSubdivisions) [dict get $fields subdivisions];set st($w,bridgeTolerance) [dict get $fields tolerance]
    try {_bridgeChanged $w} on error {message options} {
        lassign $old st($w,bridgeSubdivisions) st($w,bridgeTolerance)
        return -options $options $message
    }
}
proc ::GX::CurveWorkbench::_compose {w} {
    variable st
    _updateCompositionPreview $w;set built $st($w,previewBuild)
    if {$built eq {}} {error "Add at least one selected fragment"}
    set native [dict get $built native];set base [_record $w [lindex [dict get $built parents] 0]]
    set r [_newRecord $w $st($w,composeName) [dict get $built samples] [dict get $base source] [dict get $base x] [dict get $base y] "" "" "" "" [dict get $built parents] [dict get $built operations]]
    dict set r bridge_descriptors [dict get $built bridges]
    dict set r materialization_policy [dict create source_samples exact bridge_subdivisions $st($w,bridgeSubdivisions) spline_subdivisions 16 analytic_bridge_controls_retained 1]
    dict set r breaks [::GX::Native2D::core breaks $st($w,scene) $native]
    set id [dict get $r id];set before [dict create $id ""]
    ::GX::Native2D::core visible $st($w,scene) $native 1
    _addRecord $w $r $native
    set st($w,previewNative) "";set st($w,previewBuild) {};set st($w,previewSignature) {}
    set st($w,active) $id;set st($w,fragments) {};_fragmentList $w;_selectionScene $w
    _history $w $before [list $id]
    set st($w,status) "Committed preview: [llength [dict get $built bridges]] explicit bridge(s); Native2D continuity and analytic controls retained."
    return $id
}
