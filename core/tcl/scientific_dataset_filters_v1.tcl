# SPDX-License-Identifier: GPL-3.0-or-later
# Bounded categorical discovery through CORE Table Stream, no data changes.
proc ::GX::_datasetScientificProfileDimensions {id} {
    set dimensions {};set ids {}
    foreach v [datasetVariableSchemaV3 $id] {
        if {![dict get $v enabled] || [dict get $v rank]!=1} continue
        set vid [dict get $v variable_id];set role [dict get $v semantic_role];set type {}
        if {$role in {member_identity family family_identity group_identity} || $vid in {member_id family_value family_id group_id}} {set type family
        } elseif {$role in {trace_identity trace_index sweep_identity} || $vid in {trace_index trace_id sweep_index}} {set type trace
        } elseif {$role in {replicate_identity replicate_index} || $vid in {replicate_index replicate_id}} {set type replicate
        } elseif {$role in {category classification source_category} || ($vid eq "kind" && [dict get $v value_kind] eq "text")} {set type kind}
        if {$type eq {}} continue
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
    set unique {};set scanned 0;set done 0
    try {
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
            incr scanned $take
            set done [expr {[dict get $chunk eof] || $scanned>=$rowBudget}]
            if {$n>$take || ![dict get $chunk eof] && $done} {dict set unique @rows_truncated 1}
        }
    } finally {if {$stream ne {}} {tableStreamClose $stream};if {$access ne {}} {datasetAccessClose $access}}
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
proc ::GX::scientificDatasetFilterDimensions {id {rowBudget 100000} {valueBudget 1024} {manualFamily {}} {semanticOnly 0}} {
    if {$manualFamily ne {}} {set dimensions [_datasetScientificProfileScan $id $rowBudget $valueBudget $manualFamily]} else {
    set profile [datasetScientificProfileRead $::GX::currentSession $id]
    if {[dict get $profile status] eq "current" && $rowBudget==100000 && $valueBudget==1024} {set dimensions [dict get $profile variables]} else {set dimensions [dict get [datasetScientificProfileDiscover $::GX::currentSession $id $rowBudget $valueBudget] variables]}
    }
    if {!$semanticOnly} {return $dimensions}
    set result {}
    foreach dimension $dimensions {
        set vid [dict get $dimension variable_id]
        set role [dict get [datasetVariableV3ById $id $vid] semantic_role]
        if {$vid eq $manualFamily || $role in {member_identity family family_identity group_identity trace_identity trace_index sweep_identity replicate_identity replicate_index category classification source_category}} {lappend result $dimension}
    }
    return $result
}

proc ::GX::scientificDatasetFilterControls {parent id arrayName prefix {reset 0} {manualFamily {}} {semanticOnly 0}} {
    upvar #0 $arrayName state
    set dims [scientificDatasetFilterDimensions $id 100000 1024 $manualFamily $semanticOnly]
    if {![info exists state($prefix,filters)] || $reset} {set state($prefix,filters) {};set state($prefix,separate) 0}
    set valid {}
    foreach d $dims {
        set vid [dict get $d variable_id];set values [datasetPublicationV2DictDefault $state($prefix,filters) $vid {}];set kept {}
        foreach value $values {if {$value in [dict get $d values]} {lappend kept $value}}
        if {[llength $kept]} {dict set valid $vid $kept}
    }
    set state($prefix,filters) $valid;set state($prefix,dimensions) $dims
    foreach child [winfo children $parent] {destroy $child}
    set i 0
    foreach d $dims {
        set vid [dict get $d variable_id];set type [dict get $d type]
        set title [dict get {family {Family / group} trace {Trace / sweep} replicate Replicate kind {Source category}} $type]
        ttk::frame $parent.f$i
        ttk::label $parent.f$i.label -text "$title: [dict get $d label] ($vid)[expr {[dict get $d unit] eq {}?{}:", [dict get $d unit]"}]"
        ttk::button $parent.f$i.choose -command [list ::GX::scientificDatasetFilterDialog $parent $arrayName $prefix $vid]
        pack $parent.f$i.label $parent.f$i.choose -side left -padx 3
        grid $parent.f$i -row $i -column 0 -sticky w
        bind $parent.f$i.choose <Enter> [list ::GX::native2DViewportTooltipShow %W "Read-only equality filter on Variable ID $vid; Ctrl/Shift selects multiple exact source values. Filters combine with AND; no automatic grouping."]
        bind $parent.f$i.choose <Leave> {catch {destroy .gxViewportTip}}
        incr i
    }
    set state($prefix,filterParent) $parent
    scientificDatasetFilterLabels $arrayName $prefix
}
proc ::GX::scientificDatasetFilterLabels {arrayName prefix} {
    upvar #0 $arrayName state
    set i 0
    foreach d $state($prefix,dimensions) {
        set vid [dict get $d variable_id];set values [datasetPublicationV2DictDefault $state($prefix,filters) $vid {}]
        set total [llength [dict get $d values]];set limit [expr {[dict get $d complete]?"available":"sampled; bounded scan"}]
        set text [expr {![llength $values]?"All rows ($total $limit)…":"[llength $values] selected / $total $limit…"}]
        $state($prefix,filterParent).f$i.choose configure -text $text
        incr i
    }
}
proc ::GX::scientificDatasetFilterDialog {parent arrayName prefix vid} {
    upvar #0 $arrayName state
    set w $parent.choices
    catch {destroy $w};toplevel $w;wm transient $w [winfo toplevel $parent]
    wm title $w "Select exact values — $vid"
    foreach d $state($prefix,dimensions) {if {[dict get $d variable_id] eq $vid} break}
    ttk::label $w.note -text {Ctrl/Shift selects multiple values. No selection means unfiltered rows. Apply, then Render / Plot.} -wraplength 480
    pack $w.note -fill x -padx 8 -pady 8
    listbox $w.values -selectmode extended -exportselection 0 -height 12 -width 45
    ttk::scrollbar $w.scroll -command [list $w.values yview];$w.values configure -yscrollcommand [list $w.scroll set]
    pack $w.scroll -side right -fill y;pack $w.values -fill both -expand 1 -padx 8
    set selected [datasetPublicationV2DictDefault $state($prefix,filters) $vid {}];set i 0
    foreach value [dict get $d values] {$w.values insert end [expr {$value eq {}?{(empty text)}:$value}];if {$value in $selected} {$w.values selection set $i};incr i}
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
    foreach dimension $state($prefix,dimensions) {if {[dict get $dimension variable_id] eq $vid} break}
    set sourceValues [dict get $dimension values]
    set values {};foreach index [$w.values curselection] {lappend values [lindex $sourceValues $index]}
    if {$all} {set values $sourceValues}
    if {[llength $values]} {dict set state($prefix,filters) $vid $values} else {dict unset state($prefix,filters) $vid}
    # Explicit family selection requests distinct member series; all rows clears it.
    if {$type eq "family"} {set state($prefix,separate) [expr {[llength $values]>0}]}
    destroy $w
    scientificDatasetFilterLabels $arrayName $prefix
}
proc ::GX::scientificDatasetFilterRequests {dimensions selections separate} {
    set requests [list {}]
    foreach d $dimensions {
        set vid [dict get $d variable_id];set values [datasetPublicationV2DictDefault $selections $vid {}]
        if {![llength $values]} continue
        set next {}
        foreach filters $requests {
            if {$separate && [dict get $d type] eq "family"} {
                foreach value $values {lappend next [concat $filters [list [dict create filter_variable_id $vid predicate in_set values [list $value]]]]}
            } else {lappend next [concat $filters [list [dict create filter_variable_id $vid predicate in_set values $values]]]}
        }
        set requests $next
        if {[llength $requests]>16} {error {Select up to 16 separate family curves per view. Canonical data remain available in Table pages.}}
    }
    return $requests
}
proc ::GX::scientificDatasetFilterMode {dimensions selections separate} {
    if {![dict size $selections]} {return {Unfiltered XY (one series)}}
    set labels {}
    foreach d $dimensions {set vid [dict get $d variable_id];if {[dict exists $selections $vid]} {lappend labels "$vid = [join [dict get $selections $vid] {, }]"}}
    return "[join $labels {; }] ([expr {$separate?"explicit separate family curves":"filtered XY, one series"}])"
}
proc ::GX::scientificDatasetPreviewFiltered {id x y output requests} {
    set context [datasetCoordinateRead $::GX::currentSession $id]
    set scene {};set rows 0;set reduced 0;set traces {};set displayed 0
    try {
        foreach filters $requests {
            set source [curveSourceOpen $::GX::currentSession [dict create dataset_id $id x_variable_id $x y_variable_id $y display_budget 4096 filters $filters]]
            try {set display [curveSourceDisplayResponsive $source];set sourceIdentity [curveSourceDescribe $source]} finally {curveSourceClose $source}
            foreach identity [dict get $sourceIdentity source_identities] {if {[dict get $identity dataset_id] eq $id&&[dict get $identity sha256] ne [dict get $context source_sha256]} {error {Preview coordinate context belongs to changed source bytes}}}
            set display [scientificDatasetCoordinateDisplay $context $x $y $display]
            incr rows [dict get $display row_count];set reduced [expr {$reduced || [dict get $display reduced]}]
            lappend traces [dict remove $display points canonical_points]
            incr displayed [llength [dict get $display points]]
            if {![llength [dict get $display points]]} continue
            if {$scene eq {}} {set scene [scientificDatasetDisplayScene $display]} else {scientificDatasetCoordinateAddTrace $scene $display [expr {[llength $traces]-1}]}
        }
        if {$scene eq {}} {error {No finite X/Y pairs match the selected filters.}}
        if {[datasetCoordinateRead $::GX::currentSession $id] ne $context} {error {Preview coordinate settings changed during preparation; render again}}
        ::GX::Native2D::core view $scene [::GX::Native2D::core preview_view $scene 1 960 580 .03]
        set presentation [scientificDatasetCoordinateView $scene [dict get [lindex $traces 0] coordinate_presentation]]
        native2DCanvasPreview $scene {} current [dict create width 960 height 580 output_file $output background {1 1 1 1} annotations 1]
        set view [::GX::Native2D::core preview_view $scene 0 960 580 .03]
        return [dict merge [lindex $traces 0] [dict create row_count $rows reduced $reduced trace_count [llength $requests] traces $traces displayed_points $displayed view_bounds [lindex $view 6] axis_aspect auto coordinate_presentation $presentation]]
    } finally {if {$scene ne {}} {::GX::Native2D::core destroy $scene}}
}
