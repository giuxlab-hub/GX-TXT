# SPDX-License-Identifier: GPL-3.0-or-later
# Bounded categorical discovery through CORE Table Stream, no data changes.
proc ::GX::_datasetScientificProfileDimensions {id} {
    set dimensions {};set ids {}
    foreach v [datasetVariableSchemaV3 $id] {
        if {![dict get $v enabled] || [dict get $v rank]!=1} continue
        set vid [dict get $v variable_id];set role [dict get $v semantic_role];set type variable
        if {[dict get $v dtype] ni {string bool int8 uint8 int16 uint16 int32 uint32 int64 uint64 float32 float64}} continue
        if {$role in {member_identity family_identity group_identity} && [dict get $v dtype] eq "string"} {set type curve
        } elseif {$role in {member_identity family family_identity group_identity} && [dict get $v dtype] ne "string"} {set type family
        } elseif {$role in {trace_identity trace_index sweep_identity}} {set type trace
        } elseif {$role eq "calibration_identity"} {set type calibration
        } elseif {$role in {replicate_identity replicate_index}} {set type replicate
        } elseif {$role in {category classification source_category}} {set type kind}
        lappend ids $vid
        lappend dimensions [dict create variable_id $vid label [dict get $v canonical] unit [dict get $v unit] type $type values {} complete 1]
    }
    return $dimensions
}

proc ::GX::_datasetScientificProfileScan {id rowBudget valueBudget {manualFamily {}}} {
    set allDimensions [_datasetScientificProfileDimensions $id]
    if {$manualFamily ne {}} {
        set variable [datasetVariableV3ById $id $manualFamily]
        if {[dict get $variable rank]!=1 || ![dict get $variable enabled]} {error {Family binding requires an enabled rank-one Variable}}
        set allDimensions [lmap dimension $allDimensions {if {[dict get $dimension type] eq "family" || [dict get $dimension variable_id] eq $manualFamily} continue;set dimension}]
        lappend allDimensions [dict create variable_id $manualFamily label [dict get $variable canonical] unit [dict get $variable unit] type family values {} complete 1]
    }
    set groups {};set output {};set retainedBytes 0;set remaining $rowBudget
    foreach d [lrange $allDimensions 0 31] {
        set v [datasetVariableV3ById $id [dict get $d variable_id]]
        dict lappend groups [list [dict get $v dimension_ids] [dict get $v shape]] $d
    }
    dict for {key dimensions} $groups {
        set scanned 0
        if {$remaining<1 || [catch {set values [_datasetScientificProfileScanGroup $id $dimensions $remaining $valueBudget retainedBytes]} reason]} {
            if {$remaining<1} {set reason {Shared 100000-row discovery budget}}
            set values {}
            foreach d $dimensions {dict set d complete 0;dict set d truncated 1;dict set d scanned_rows 0;dict set d reason $reason;lappend values $d}
        }
        foreach d $values {dict set output [dict get $d variable_id] $d;set scanned [expr {max($scanned,[dict get $d scanned_rows])}]}
        incr remaining -$scanned
    }
    set result {}
    foreach d $allDimensions {
        set vid [dict get $d variable_id]
        if {[dict exists $output $vid]} {lappend result [dict get $output $vid]} else {
            dict set d complete 0;dict set d truncated 1;dict set d scanned_rows 0;dict set d reason {32-variable discovery budget};lappend result $d
        }
    }
    return $result
}
proc ::GX::_datasetScientificProfileNativeAvailable {} {
    variable profileNativeLoadAttempted
    if {![llength [info commands ::GX::PreviewCategories::native]]} {
        if {[info exists profileNativeLoadAttempted]} {return 0}
        set profileNativeLoadAttempted 1
        set library [file join $::GX::scriptDir core native2d bin gx2dtcl[info sharedlibextension]]
        if {![file isfile $library] || [catch {load $library Gx2dtcl}]} {return 0}
    }
    if {[catch {set info [::GX::PreviewCategories::native api_info]}]} {return 0}
    if {[catch {expr {[dict exists $info abi_version] && [dict get $info abi_version]==1}} available]} {return 0}
    return $available
}
proc ::GX::_datasetScientificProfileScanGroup {id dimensions rowBudget valueBudget bytesName} {
    upvar 1 $bytesName retainedBytes
    set ids [lmap d $dimensions {dict get $d variable_id}]
    if {![llength $ids]} {return {}}
    set stream {};set access {}
    if {[catch {set stream [tableStreamOpenDataset $::GX::currentSession $id $ids 2048 [dict create start 0 count -1 numeric_transport values]]}]} {
        # Independent rank-one axes can have a different count from Dataset rows.
        # Dataset Access owns that variable range; Table Stream stays unchanged.
        set access [datasetAccessOpen $::GX::currentSession $id]
        set shape [datasetSchemaV3SplitIds [dict get [datasetVariableV3ById $id [lindex $ids 0]] shape]]
        set total [lindex $shape 0]
        if {![string is integer -strict $total] || $total<0} {datasetAccessClose $access;error {Categorical variable has no bounded rank-one shape.}}
    }
    set unique {};set scanned 0;set done 0;set native {}
    try {
        # Only the repeated collection loop changes ownership. The existing
        # canonical reader, Graph Series numeric validator and discovery limits
        # remain authoritative; unsupported private argument shapes fall back.
        if {[llength $ids]<=32 && [string is wideinteger -strict $rowBudget] && $rowBudget>=0 &&
            [string is wideinteger -strict $valueBudget] && [string is wideinteger -strict $retainedBytes] &&
            $retainedBytes>=0 && $retainedBytes<=2097152 && [_datasetScientificProfileNativeAvailable]} {
            set specifications {}
            foreach vid $ids {lappend specifications [dict create variable_id $vid dtype [dict get [datasetVariableV3ById $id $vid] dtype]]}
            set native [::GX::PreviewCategories::native begin $specifications $valueBudget $retainedBytes]
        }
        while {!$done} {
            if {$stream ne {}} {set chunk [tableStreamNext $stream]} else {
                set count [expr {min(2048,$rowBudget-$scanned,$total-$scanned)}]
                set data [datasetAccessReadRange $access $ids $scanned $count]
                set columns {};foreach vid $ids {lappend columns [dict create values [dict get $data $vid values]]}
                set chunk [dict create columns $columns eof [expr {$scanned+$count>=$total}]]
            }
            set columns [dict get $chunk columns]
            set n [llength [dict get [lindex $columns 0] values]]
            set take [expr {min($n,$rowBudget-$scanned)}]
            if {$native ne {}} {
                set retainedBytes [::GX::PreviewCategories::native push $native $columns $take]
            } else {
            foreach column $columns vid $ids {
                set dtype [dict get [datasetVariableV3ById $id $vid] dtype]
                foreach value [lrange [dict get $column values] 0 [expr {$take-1}]] {
                    if {$take==0} continue
                    if {$dtype ne "string" && [catch {graphSeriesCanonicalMember $dtype $value}]} continue
                    if {[string bytelength $value]>1024} {dict set unique @truncated $vid 1;continue}
                    if {[dict exists $unique $vid $value]} continue
                    if {[dict exists $unique $vid] && [dict size [dict get $unique $vid]]>=$valueBudget} {dict set unique @truncated $vid 1;continue}
                    if {$retainedBytes+[string bytelength $value]>2097152} {dict set unique @truncated $vid 1;continue}
                    incr retainedBytes [string bytelength $value]
                    dict set unique $vid $value 1
                }
            }
            }
            incr scanned $take
            set done [expr {[dict get $chunk eof] || $scanned>=$rowBudget}]
            if {$n>$take || ![dict get $chunk eof] && $done} {dict set unique @rows_truncated 1}
        }
        if {$native ne {}} {set unique [dict merge [::GX::PreviewCategories::native finish $native] $unique]}
    } finally {
        if {$native ne {}} {catch {::GX::PreviewCategories::native destroy $native}}
        if {$stream ne {}} {tableStreamClose $stream};if {$access ne {}} {datasetAccessClose $access}
    }
    set result {}
    foreach d $dimensions {
        set vid [dict get $d variable_id]
        if {[dict exists $unique $vid]} {dict set d values [dict keys [dict get $unique $vid]]}
        dict set d complete [expr {![dict exists $unique @truncated $vid] && ![dict exists $unique @rows_truncated]}]
        dict set d truncated [expr {![dict get $d complete]}]
        dict set d scanned_rows $scanned
        lappend result $d
    }
    return $result
}
proc ::GX::scientificDatasetFilterDialog {parent arrayName prefix vid} {
    upvar #0 $arrayName state
    set w $parent.choices
    catch {destroy $w};toplevel $w;wm transient $w [winfo toplevel $parent]
    wm title $w "Select exact values — $vid"
    set state($prefix,shortcutIdentity) [list [interactiveDocumentSessionToken] $state($prefix,dataset) [_datasetScientificProfileIdentity $state($prefix,dataset)]]
    foreach d $state($prefix,dimensions) {if {[dict get $d variable_id] eq $vid} break}
    ttk::label $w.note -text {Ctrl/Shift selects multiple values. No selection means unfiltered rows. Apply, then Render / Plot.} -wraplength 480
    pack $w.note -fill x -padx 8 -pady 8
    listbox $w.values -selectmode extended -exportselection 0 -height 12 -width 45
    ttk::scrollbar $w.scroll -command [list $w.values yview];$w.values configure -yscrollcommand [list $w.scroll set]
    pack $w.scroll -side right -fill y;pack $w.values -fill both -expand 1 -padx 8
    set selected [datasetPublicationV2DictDefault $state($prefix,filters) $vid {}];set i 0
    set labels {}
    if {[dict exists $d label_variable]} {
        set stream [tableStreamOpenDataset $::GX::currentSession $state($prefix,dataset) [list $vid [dict get $d label_variable]] 2048 {numeric_transport values}]
        try {
            while 1 {
                set chunk [tableStreamNext $stream]
                foreach value [dict get $chunk values $vid] label [dict get $chunk values [dict get $d label_variable]] {
                    if {![dict exists $labels $value] && [dict size $labels]<1024} {dict set labels $value $label}
                }
                if {[dict get $chunk eof]} break
            }
        } finally {tableStreamClose $stream}
    }
    foreach value [dict get $d values] {
        set label [expr {$value eq {}?{(empty text)}:$value}]
        if {[dict exists $labels $value]} {set label "[dict get $labels $value] — $value"}
        $w.values insert end $label;if {$value in $selected} {$w.values selection set $i};incr i
    }
    ttk::frame $w.bar;pack $w.bar -fill x -padx 8 -pady 8
    ttk::button $w.bar.all -text {All rows (unfiltered)} -command [list $w.values selection clear 0 end]
    ttk::button $w.bar.apply -text Apply -command [list ::GX::scientificDatasetFilterApply $w $arrayName $prefix $vid [dict get $d type] 0]
    pack $w.bar.all $w.bar.apply -side left -padx 3
    if {[dict get $d type] eq "family"} {
        ttk::button $w.bar.separate -text {All members as separate curves} -command [list ::GX::scientificDatasetFilterApply $w $arrayName $prefix $vid family 1]
        pack $w.bar.separate -side left -padx 3
        if {![dict get $d complete]} {$w.bar.separate state disabled}
    }
    focus $w.values
}
proc ::GX::scientificDatasetFilterApply {w arrayName prefix vid type all} {
    upvar #0 $arrayName state
    set identity [list [interactiveDocumentSessionToken] $state($prefix,dataset) [_datasetScientificProfileIdentity $state($prefix,dataset)]]
    if {$identity ne $state($prefix,shortcutIdentity)} {tk_messageBox -parent $w -icon warning -message {Dataset, schema or Session changed. Reopen the selector before applying.};return}
    foreach dimension $state($prefix,dimensions) {if {[dict get $dimension variable_id] eq $vid} break}
    set sourceValues [dict get $dimension values]
    set values {};foreach index [$w.values curselection] {lappend values [lindex $sourceValues $index]}
    if {$all} {set values $sourceValues}
    if {[llength $values]} {dict set state($prefix,filters) $vid $values} else {dict unset state($prefix,filters) $vid}
    # Explicit family selection requests distinct member series; all rows clears it.
    set state($prefix,separate) 1
    scientificDatasetFilterPersist $arrayName $prefix
    destroy $w
    scientificDatasetFilterLabels $arrayName $prefix
}
# Metadata is read from the public Plot receipt; no frontend viewport math.
proc ::GX::scientificDatasetPlotReceiptBounds {receipt} {
    set limits {}
    foreach axis [dict get $receipt axes] {
        if {[dict get $axis panel_id] eq {main} && [dict get $axis axis] in {x left}} {
            dict set limits [dict get $axis axis] [dict get $axis limits]
        }
    }
    if {![dict exists $limits x] || ![dict exists $limits left]} {error {Public Plot receipt has no complete main X/Y limits}}
    lassign [dict get $limits x] x0 x1
    lassign [dict get $limits left] y0 y1
    return [list $x0 $y0 $x1 $y1]
}
proc ::GX::scientificDatasetPreviewFiltered {id x y output requests {options {}}} {
    scientificDatasetPlotRequire
    set context [datasetCoordinateRead $::GX::currentSession $id]
    set rows 0;set reduced 0;set traces {};set displayed 0;set prepared {}
    set ordering [datasetPublicationV2DictDefault [dict merge [_datasetPreviewConfiguredOptions $id] $options] ordering {}]
    set sources {}
    if {[dict exists $options batch_plan]} {
        set plan [dict get $options batch_plan]
        if {[dict get $plan dataset_id] ne $id} {error {Preview grouping plan belongs to another Dataset}}
        set request [dict create dataset_id $id x_variable_id $x y_variable_id $y display_budget 4096 filters [dict get $plan filters]]
        if {$ordering ne {}} {dict set request order_variable_id $ordering}
        set batch [curveSourceDisplayBatch $::GX::currentSession $request [dict create group_variable_ids [dict get $plan group_variable_ids]]]
        set sources [dict get $batch series]
    } else {
        foreach filters $requests {
            set request [dict create dataset_id $id x_variable_id $x y_variable_id $y display_budget 4096 filters $filters]
            if {$ordering ne {}} {dict set request order_variable_id $ordering}
            set source [curveSourceOpen $::GX::currentSession $request]
            try {set display [curveSourceDisplayResponsive $source];set descriptor [curveSourceDescribe $source]} finally {curveSourceClose $source}
            lappend sources [dict create filters $filters display $display source_descriptor $descriptor]
        }
    }
    foreach source $sources {
        set filters [dict get $source filters];set display [dict get $source display];set descriptor [dict get $source source_descriptor]
        foreach identity [dict get $descriptor source_identities] {
            if {[dict get $identity dataset_id] eq $id && [dict get $identity sha256] ne [dict get $context source_sha256]} {error {Preview coordinate context belongs to changed source bytes}}
        }
        set display [scientificDatasetCoordinateDisplay $context $x $y $display]
        incr rows [dict get $display row_count]
        set reduced [expr {$reduced || [dict get $display reduced]}]
        lappend traces [dict remove $display points canonical_points]
        incr displayed [llength [dict get $display points]]
        if {![llength [dict get $display points]]} continue
        set index [llength $prepared]
        lappend prepared [dict create id preview_$index y_variable_id $y label "Trace [expr {$index+1}]" filters $filters source_descriptor $descriptor display $display]
    }
    if {![llength $prepared]} {error {No finite X/Y pairs match the selected filters.}}
    if {[datasetCoordinateRead $::GX::currentSession $id] ne $context} {error {Preview coordinate settings changed during preparation; render again}}
    set labels {}
    foreach axis {x y} vid [list $x $y] {
        set variable [datasetVariableV3ById $id $vid]
        set label [string trim [dict get $variable display_label]]
        if {$label eq {}} {set label [string trim [dict get $variable canonical]]}
        if {$label eq {}} {set label $vid}
        dict set labels $axis "$label ([scientificDatasetCoordinateLabel $context $vid])"
    }
    set presentationOptions [dict create title {Scientific curves} axis_labels $labels aspect auto \
        native_presentation {schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1 graphics {} axes {} panels {} layout {} legend {placement none}}]
    set model [::GX::PlotDatasetAPIv4::scientificModel $id $x $prepared $context $presentationOptions]
    set receipt [::GX::PlotDatasetAPIv4::renderModel $model $output 960 580]
    set bounds [scientificDatasetPlotReceiptBounds $receipt]
    set presentation [dict get $receipt coordinate_presentation]
    return [dict merge [lindex $traces 0] [dict create row_count $rows reduced $reduced trace_count [llength $sources] traces $traces displayed_points $displayed view_bounds $bounds axis_aspect auto coordinate_presentation $presentation native_model $model]]
}

source [file join [file dirname [info script]] scientific_dataset_filter_configuration_v1.tcl]
