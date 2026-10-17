# SPDX-License-Identifier: GPL-3.0-or-later
# Preview configuration belongs to the existing Dataset metadata authority.
# Predicate normalization/execution belongs to Graph Series / Graph Selection.
proc ::GX::datasetPreviewCurveManifest {id} {
    set md [datasetMetadataRead $::GX::currentSession $id]
    if {[datasetPublicationV2DictDefault $md curve_digitizer.plugin_id {}] ne {viewer.curve_digitizer}} {return {}}
    modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_DATASET_SCHEMA_API_v1
    return [::GX::CurveDigitizerDataset::read $id]
}
proc ::GX::scientificDatasetFilterDimensions {id {rowBudget 100000} {valueBudget 1024} {manualFamily {}} {semanticOnly 0}} {
    # Every compatible enabled Variable is selectable, regardless of its ID or
    # semantic role. Automatic hints never determine manual eligibility.
    set dimensions [_datasetScientificProfileScan $id $rowBudget $valueBudget $manualFamily]
    set columns {}
    if {![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {set columns [dict get $manifest columns]}
    set result {}
    foreach d $dimensions {
        set vid [dict get $d variable_id]
        dict set d dataset_id $id
        dict set d dtype [dict get [datasetVariableV3ById $id $vid] dtype]
        foreach {role type} {family_parameter family curve_key curve calibration_key calibration} {
            if {[dict exists $columns $role] && [dict get $columns $role] eq $vid} {dict set d type $type}
        }
        if {[dict get $d type] eq "curve" && [dict exists $columns curve_name]} {
            dict set d label_variable [dict get $columns curve_name]
        }
        lappend result $d
    }
    return $result
}
proc ::GX::datasetPreviewConfigurationRead {id} {
    set md [datasetPrivateMetadataRead $::GX::currentSession $id]
    set saved [datasetPublicationV2DictDefault $md _gxtxt.framework.dataset_preview {}]
    if {[catch {dict get $saved version} v] || $v!=1} {return {}}
    return $saved
}
proc ::GX::scientificDatasetFilterPersist {arrayName prefix} {
    upvar #0 $arrayName state
    set filters [dict remove $state($prefix,filters) @hidden_filters]
    dict set filters @predicates [datasetPublicationV2DictDefault $filters @predicates {}]
    set config [dict merge [datasetPreviewConfigurationRead $state($prefix,dataset)] [dict create version 1 selections $filters ordering $state($prefix,ordering) types $state($prefix,filterTypes) schema_identity [_datasetScientificProfileIdentity $state($prefix,dataset)]]]
    foreach axis {x y z} {if {[info exists state($prefix,$axis)]} {dict set config $axis $state($prefix,$axis)}}
    _datasetFrameworkMetadataUpdate $::GX::currentSession $state($prefix,dataset) [dict create dataset_preview $config]
}
proc ::GX::scientificDatasetFilterControls {parent id arrayName prefix {reset 0} {manualFamily {}} {semanticOnly 0}} {
    upvar #0 $arrayName state
    set dims [scientificDatasetFilterDimensions $id 100000 1024 $manualFamily $semanticOnly]
    set saved [datasetPreviewConfigurationRead $id]
    set state($prefix,dataset) $id
    set priorTypes [expr {[info exists state($prefix,filterTypes)]?$state($prefix,filterTypes):{}}]
    if {![info exists state($prefix,filters)] || $reset} {
        set saved [datasetPreviewConfigurationRead $id]
        if {$saved ne {}} {
            set state($prefix,filters) [dict get $saved selections]
            set state($prefix,ordering) [dict get $saved ordering]
            set priorTypes [datasetPublicationV2DictDefault $saved types {}]
        } else {
            set groups {}
            foreach d $dims {if {[dict get $d type] in {family curve calibration trace replicate}} {lappend groups [dict get $d variable_id]}}
            set state($prefix,filters) [dict create @grouping $groups @predicates {} @single_series 0]
            set state($prefix,ordering) {}
            if {![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {set state($prefix,ordering) [dict get $manifest columns point_order]}
        }
    }
    set state($prefix,separate) 1
    set ids [lmap d $dims {dict get $d variable_id}]
    set valid {};set types {}
    foreach d $dims {dict set types [dict get $d variable_id] [dict get $d dtype]}
    dict for {vid values} $state($prefix,filters) {
        if {[string match @* $vid] || $vid ni $ids} continue
        set variable [datasetVariableV3ById $id $vid]
        if {[dict exists $priorTypes $vid] && [dict get $priorTypes $vid] ne [dict get $variable dtype]} continue
        if {![catch {graphSeriesNormalizeFilters $id [list [dict create filter_variable_id $vid predicate in_set values $values]]}]} {
            foreach d $dims {if {[dict get $d variable_id] eq $vid} break}
            if {[dict get $d complete]} {
                set available {};set kept {}
                foreach value [dict get $d values] {
                    if {[dict get $variable dtype] ne "string"} {set value [graphSeriesCanonicalMember [dict get $variable dtype] $value]}
                    dict set available $value 1
                }
                foreach value $values {
                    set canonical $value
                    if {[dict get $variable dtype] ne "string"} {set canonical [graphSeriesCanonicalMember [dict get $variable dtype] $value]}
                    if {[dict exists $available $canonical]} {lappend kept $value}
                }
                set values $kept
            }
            if {[llength $values]} {dict set valid $vid $values}
        }
    }
    set predicates {}
    foreach filter [datasetPublicationV2DictDefault $state($prefix,filters) @predicates {}] {
        set vid [dict get $filter filter_variable_id]
        if {$vid ni $ids || [dict get $filter dtype] ne [dict get [datasetVariableV3ById $id $vid] dtype]} continue
        if {![catch {set normalized [graphSeriesNormalizeFilters $id [list $filter]]}]} {lappend predicates {*}$normalized}
    }
    dict set valid @predicates $predicates
    dict set valid @grouping [lmap vid [datasetPublicationV2DictDefault $state($prefix,filters) @grouping {}] {if {$vid ni $ids} continue;set vid}]
    dict set valid @single_series [datasetPublicationV2DictDefault $state($prefix,filters) @single_series 0]
    set state($prefix,filters) $valid
    set state($prefix,filterTypes) $types
    if {$state($prefix,ordering) ni $ids} {set state($prefix,ordering) {}}
    set state($prefix,dimensions) $dims
    if {$saved ne {} && [datasetPublicationV2DictDefault $saved schema_identity {}] ne [_datasetScientificProfileIdentity $id]} {scientificDatasetFilterPersist $arrayName $prefix}
    foreach child [winfo children $parent] {if {[winfo toplevel $child] ne $child} {destroy $child}}
    ttk::button $parent.configure -text {Configure filters / grouping…} -command [list ::GX::scientificDatasetFilterConfigure $parent $arrayName $prefix]
    grid $parent.configure -row 0 -column 0 -sticky w -padx 3
    set i 0
    foreach d $dims {
        if {[dict get $d type] ni {family curve calibration}} continue
        set vid [dict get $d variable_id]
        set title [dict get {family Family curve Curve calibration Calibration} [dict get $d type]]
        ttk::frame $parent.f$i
        ttk::label $parent.f$i.label -text "$title: [dict get $d label] ($vid)[expr {[dict get $d unit] eq {}?{}:", source [dict get $d unit]"}]"
        ttk::button $parent.f$i.choose -text {Select values…} -command [list ::GX::scientificDatasetFilterDialog $parent $arrayName $prefix $vid]
        pack $parent.f$i.label $parent.f$i.choose -side left -padx 3
        grid $parent.f$i -row [expr {$i+1}] -column 0 -sticky w
        incr i
    }
    set state($prefix,filterParent) $parent
    scientificDatasetFilterLabels $arrayName $prefix
}
proc ::GX::scientificDatasetFilterLabels {arrayName prefix} {
    upvar #0 $arrayName state
    set i 0
    foreach d $state($prefix,dimensions) {
        if {[dict get $d type] ni {family curve calibration}} continue
        set values [datasetPublicationV2DictDefault $state($prefix,filters) [dict get $d variable_id] {}]
        set text [expr {[llength $values]?"[llength $values] selected…":"All values…"}]
        $state($prefix,filterParent).f$i.choose configure -text $text
        incr i
    }
}
proc ::GX::scientificDatasetFilterConfigure {parent arrayName prefix} {
    upvar #0 $arrayName state
    set w $parent.configureDialog;catch {destroy $w};toplevel $w;wm title $w {Dataset filters and independent series grouping};wm transient $w [winfo toplevel $parent]
    set state($prefix,draftIdentity) [list [interactiveDocumentSessionToken] $state($prefix,dataset) [_datasetScientificProfileIdentity $state($prefix,dataset)]]
    set state($prefix,draftPredicates) [datasetPublicationV2DictDefault $state($prefix,filters) @predicates {}]
    set state($prefix,draftSingle) [datasetPublicationV2DictDefault $state($prefix,filters) @single_series 0]
    ttk::label $w.help -text {All predicates combine with AND. Membership uses a Tcl list of exact values. Grouping is independent of filters.} -wraplength 680
    pack $w.help -fill x -padx 8 -pady 8
    ttk::frame $w.add;pack $w.add -fill x
    set labels [lmap d $state($prefix,dimensions) {format {%s — %s [%s]} [dict get $d label] [dict get $d variable_id] [dict get $d dtype]}]
    ttk::combobox $w.add.variable -values $labels -state readonly -width 35
    ttk::combobox $w.add.predicate -state readonly -width 20
    ttk::entry $w.add.value -width 24
    ttk::entry $w.add.upper -width 14
    ttk::button $w.add.go -text {Add predicate} -command [list ::GX::scientificDatasetFilterAdd $w $arrayName $prefix]
    foreach widget {variable predicate value upper go} {pack $w.add.$widget -side left -padx 3}
    bind $w.add.variable <<ComboboxSelected>> [list ::GX::scientificDatasetFilterPredicates $w $arrayName $prefix]
    ttk::label $w.syntax -text {Value / membership list; the last field is the upper bound for between_inclusive.}
    pack $w.syntax -anchor w -padx 8
    listbox $w.predicates -height 5 -width 95 -exportselection 0
    pack $w.predicates -fill both -expand 1 -padx 8 -pady 6
    foreach filter $state($prefix,draftPredicates) {$w.predicates insert end $filter}
    ttk::button $w.remove -text {Remove selected predicate} -command [list ::GX::scientificDatasetFilterRemove $w $arrayName $prefix]
    pack $w.remove -anchor w -padx 8
    ttk::label $w.groupLabel -text {Separate series by (Ctrl/Shift selects several variables):}
    pack $w.groupLabel -anchor w -padx 8 -pady 6
    listbox $w.groups -selectmode extended -exportselection 0 -height 6 -width 75
    pack $w.groups -fill both -expand 1 -padx 8
    set i 0
    foreach d $state($prefix,dimensions) {
        $w.groups insert end [lindex $labels $i]
        if {[dict get $d variable_id] in [datasetPublicationV2DictDefault $state($prefix,filters) @grouping {}]} {$w.groups selection set $i}
        incr i
    }
    ttk::checkbutton $w.single -text {I confirm that ungrouped rows represent one continuous scientific series} -variable ${arrayName}($prefix,draftSingle)
    pack $w.single -anchor w -padx 8 -pady 6
    ttk::frame $w.order;pack $w.order -fill x -padx 8
    ttk::label $w.order.label -text {Within-series order:}
    ttk::combobox $w.order.variable -values [linsert $labels 0 {Source row order}] -state readonly -width 48
    set idx [lsearch -exact [lmap d $state($prefix,dimensions) {dict get $d variable_id}] $state($prefix,ordering)]
    $w.order.variable current [expr {$idx+1}]
    pack $w.order.label $w.order.variable -side left -padx 3
    ttk::label $w.error -text {} -foreground #a02020 -wraplength 680;pack $w.error -fill x -padx 8
    ttk::button $w.apply -text {Apply configuration} -command [list ::GX::scientificDatasetFilterConfigureApply $w $arrayName $prefix]
    pack $w.apply -anchor e -padx 8 -pady 8
    # Existing Preview controls are ancestors of this toplevel. Keep its nested
    # form frames above their background after the shared appearance pass.
    raise $w.add;raise $w.order
    if {[llength $labels]} {$w.add.variable current 0;scientificDatasetFilterPredicates $w $arrayName $prefix}
}
proc ::GX::scientificDatasetFilterPredicates {w arrayName prefix} {
    upvar #0 $arrayName state
    set d [lindex $state($prefix,dimensions) [$w.add.variable current]]
    set predicates {exact_equal not_equal in_set}
    if {[dict get $d dtype] ne "string"} {lappend predicates less_than less_equal greater_than greater_equal between_inclusive is_finite is_nonfinite}
    $w.add.predicate configure -values $predicates;$w.add.predicate current 0
}
proc ::GX::scientificDatasetFilterAdd {w arrayName prefix} {
    upvar #0 $arrayName state
    if {[catch {
        scientificDatasetFilterDraftRequire $arrayName $prefix
        set d [lindex $state($prefix,dimensions) [$w.add.variable current]]
        set predicate [$w.add.predicate get]
        set filter [dict create filter_variable_id [dict get $d variable_id] predicate $predicate]
        switch $predicate {
            in_set {dict set filter values [$w.add.value get]}
            between_inclusive {dict set filter lower [$w.add.value get];dict set filter upper [$w.add.upper get]}
            is_finite - is_nonfinite {}
            default {dict set filter value [$w.add.value get]}
        }
        set filter [lindex [graphSeriesNormalizeFilters $state($prefix,dataset) [list $filter]] 0]
        lappend state($prefix,draftPredicates) $filter;$w.predicates insert end $filter
    } reason]} {$w.error configure -text $reason} else {$w.error configure -text {}}
}
proc ::GX::scientificDatasetFilterRemove {w arrayName prefix} {
    upvar #0 $arrayName state
    set i [lindex [$w.predicates curselection] 0]
    if {$i eq {}} return
    set state($prefix,draftPredicates) [lreplace $state($prefix,draftPredicates) $i $i];$w.predicates delete $i
}
proc ::GX::scientificDatasetFilterConfigureApply {w arrayName prefix} {
    upvar #0 $arrayName state
    if {[catch {scientificDatasetFilterDraftRequire $arrayName $prefix} reason]} {$w.error configure -text $reason;return}
    set groups [lmap i [$w.groups curselection] {dict get [lindex $state($prefix,dimensions) $i] variable_id}]
    dict set state($prefix,filters) @grouping $groups
    dict set state($prefix,filters) @predicates $state($prefix,draftPredicates)
    dict set state($prefix,filters) @single_series $state($prefix,draftSingle)
    set i [expr {[$w.order.variable current]-1}]
    set state($prefix,ordering) [expr {$i<0?{}:[dict get [lindex $state($prefix,dimensions) $i] variable_id]}]
    scientificDatasetFilterPersist $arrayName $prefix
    destroy $w
}
proc ::GX::scientificDatasetFilterDraftRequire {arrayName prefix} {
    upvar #0 $arrayName state
    set now [list [interactiveDocumentSessionToken] $state($prefix,dataset) [_datasetScientificProfileIdentity $state($prefix,dataset)]]
    if {$now ne $state($prefix,draftIdentity)} {error {Dataset, schema or Session changed. Reopen filter configuration before applying.}}
}
proc ::GX::scientificDatasetFilterRequests {dimensions selections separate} {
    set filters [concat [datasetPublicationV2DictDefault $selections @predicates {}] [datasetPublicationV2DictDefault $selections @hidden_filters {}]]
    set id [expr {[llength $dimensions]?[dict get [lindex $dimensions 0] dataset_id]:{}}]
    foreach d $dimensions {
        set vid [dict get $d variable_id];set values [datasetPublicationV2DictDefault $selections $vid {}]
        if {[llength $values]} {lappend filters [dict create filter_variable_id $vid predicate in_set values $values]}
    }
    set groups [datasetPublicationV2DictDefault $selections @grouping {}]
    if {$id ne {} && ![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {
        foreach role [dict get $manifest grouping_roles] {
            set vid [dict get $manifest columns $role]
            if {$vid ni $groups} {lappend groups $vid}
        }
    }
    if {![dict exists $selections @grouping] && $separate} {foreach d $dimensions {if {[dict get $d type] eq "family"} {lappend groups [dict get $d variable_id]}}}
    if {$groups eq {}} {
        set uncertain 0
        foreach d $dimensions {if {[dict get $d dtype] eq "string"} {set uncertain 1}}
        if {$uncertain && ![datasetPublicationV2DictDefault $selections @single_series 0]} {error {Curve membership is ambiguous. Configure independent grouping variables or explicitly confirm a single scientific series.}}
        return [list $filters]
    }
    set filters [graphSeriesNormalizeFilters $id $filters]
    set ids $groups
    foreach f $filters {set vid [dict get $f filter_variable_id];if {$vid ni $ids} {lappend ids $vid}}
    set stream [tableStreamOpenDataset $::GX::currentSession $id $ids 2048 {numeric_transport values}]
    set combinations {}
    try {
        while 1 {
            set chunk [tableStreamNext $stream];set values [dict get $chunk values]
            for {set row 0} {$row<[dict get $chunk row_count]} {incr row} {
                set accepted 1
                foreach f $filters {if {![::GX::GraphSelectionAPIv1::_matchesFilter [lindex [dict get $values [dict get $f filter_variable_id]] $row] $f]} {set accepted 0;break}}
                if {!$accepted} continue
                set key {};set valid 1
                foreach vid $groups {
                    set value [lindex [dict get $values $vid] $row]
                    set dtype [dict get [datasetVariableV3ById $id $vid] dtype]
                    if {$dtype ne "string" && [catch {set value [graphSeriesCanonicalMember $dtype $value]}]} {set valid 0;break}
                    lappend key $value
                }
                if {!$valid} {error {Grouping contains missing/nonfinite identities. Filter them explicitly before connecting points.}}
                dict set combinations $key 1
                if {[dict size $combinations]>64} {error {More than 64 visible series; narrow the filters or choose other grouping variables.}}
            }
            if {[dict get $chunk eof]} break
        }
    } finally {tableStreamClose $stream}
    set requests {}
    foreach key [dict keys $combinations] {
        set request $filters
        foreach vid $groups value $key {lappend request [dict create filter_variable_id $vid predicate exact_equal value $value]}
        lappend requests $request
    }
    if {$requests eq {}} {error {No rows match the selected filters}}
    return $requests
}
proc ::GX::scientificDatasetFilterMode {dimensions selections separate} {
    set groups [datasetPublicationV2DictDefault $selections @grouping {}]
    if {[llength $dimensions]} {
        set id [dict get [lindex $dimensions 0] dataset_id]
        if {![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {
            foreach role [dict get $manifest grouping_roles] {set vid [dict get $manifest columns $role];if {$vid ni $groups} {lappend groups $vid}}
        }
    }
    return "[llength [datasetPublicationV2DictDefault $selections @predicates {}]] configured predicates; separate series by [expr {$groups eq {}?{explicit single series}:$groups}]"
}
