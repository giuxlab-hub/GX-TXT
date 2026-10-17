# GX-TXT Dataset Selection API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Reusable, canonical dataset-coordinate selections built additively above
# Plot Region Selection API v1. A selection is metadata, not a dataset subset.

namespace eval ::GX {
    variable datasetSelectionApiVersion 1
    variable datasetSelection
    variable datasetSelectionCounter 0
    variable selectionWidgetDisplay
}

# Additive v1 resources keep the legacy scalar fields intact. A member is an
# independent canonical source binding, even when two members share a Dataset.
proc ::GX::datasetSelectionCreateMembers {session members {producer {}}} {
    if {![llength $members]} {error "Dataset Selection needs at least one source member"}
    loadDatasetRegistry $session
    set normalized {};set seen {};set ordinal 0
    foreach member $members {
        incr ordinal
        if {![dict exists $member dataset_id]} {error "Selection member needs a Dataset ID"}
        set ds [dict get $member dataset_id]
        datasetVariableSchema $ds
        set mid [datasetPublicationV2DictDefault $member member_id member_$ordinal]
        datasetPublicationV2RequestedId $mid
        if {$mid in $seen} {error "Duplicate Selection member ID '$mid'"}
        lappend seen $mid
        dict set member member_id $mid
        foreach axis {x y} {
            if {![dict exists $member ${axis}_variable_id]} {error "Member '$mid' needs an $axis variable ID"}
            datasetVariableById $ds [dict get $member ${axis}_variable_id]
        }
        foreach key [dict keys $member] {
            if {$key ni {dataset_id member_id x_variable_id y_variable_id variable_ids rows row_operation row_filters start count}} {error "Unknown Selection member field '$key'"}
        }
        if {[dict exists $member rows]} {
            set rows {}
            foreach row [dict get $member rows] {
                if {![string is entier -strict $row] || $row < 0} {error "Member '$mid' row ordinals must be nonnegative integers"}
                lappend rows $row
            }
            dict set member rows [lsort -unique -integer $rows]
        }
        set op [datasetPublicationV2DictDefault $member row_operation keep]
        if {$op ni {keep exclude}} {error "Member '$mid' row operation must be keep or exclude"}
        dict set member row_operation $op
        lappend normalized $member
    }
    datasetSelectionLoadRegistry $session
    set id [datasetSelectionNextId]
    set fields [dict merge [dict create type members members $normalized member_count [llength $normalized] created_at [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S%z]] $producer]
    # Only publication provenance keys are accepted; callers cannot overwrite
    # the resource's type, identity, or validated members through this argument.
    foreach key [dict keys $producer] {if {$key ni {producer_module producer_graph producer_variant}} {error "Unknown Selection producer field '$key'"}}
    variable datasetSelection
    set before [array get datasetSelection]
    try {
        datasetSelectionRegister $id $fields
        datasetSelectionSaveRegistry $session
    } on error {message options} {
        array unset datasetSelection *;array set datasetSelection $before
        return -options $options $message
    }
    return $id
}

proc ::GX::datasetSelectionMembers {session id {operation ""}} {
    set selection [sessionInspectionSelection $id $session]
    if {[dict get $selection type] eq "members"} {
        set members [dict get $selection members]
    } else {
        if {[datasetPublicationV2DictDefault $selection x_coordinate_space source] ne "source"} {error "Legacy display-domain Selection needs explicit per-source canonical bindings"}
        set filters {}
        foreach axis {x y} {
            if {$axis eq "y" && [dict get $selection type] ne "rectangle"} continue
            lappend filters [dict create filter_variable_id [dict get $selection ${axis}_variable_id] predicate between_inclusive lower [dict get $selection ${axis}_min] upper [dict get $selection ${axis}_max]]
        }
        set member [dict create dataset_id [dict get $selection source_dataset_id] member_id $id x_variable_id [dict get $selection x_variable_id] selection_filters $filters]
        if {[dict get $selection y_variable_id] ne ""} {dict set member y_variable_id [dict get $selection y_variable_id]}
        set members [list $member]
    }
    set result {}
    foreach member $members {
        if {$operation ne ""} {
            if {$operation ni {keep exclude}} {error "Selection operation must be keep or exclude"}
            if {[dict exists $member rows]} {
                dict set member row_operation $operation
            } elseif {$operation eq "exclude"} {
                # Complement only the selection predicate, leaving a series'
                # independent row filters intact. Transform owns this policy.
                dict set member selection_operation exclude
            }
        }
        lappend result $member
    }
    return $result
}

proc ::GX::datasetSelectionClear {} {
    variable datasetSelection
    variable datasetSelectionCounter
    array unset datasetSelection *
    set datasetSelectionCounter 0
}

proc ::GX::datasetSelectionIds {} {
    variable datasetSelection
    set ids {}
    foreach k [array names datasetSelection "*,id"] {
        set id [string range $k 0 end-3]
        if {[lsearch -exact $ids $id] < 0} { lappend ids $id }
    }
    return [lsort -dictionary $ids]
}

proc ::GX::datasetSelectionField {id field {default ""}} {
    variable datasetSelection
    if {[info exists datasetSelection($id,$field)]} { return $datasetSelection($id,$field) }
    return $default
}

proc ::GX::datasetSelectionRegister {id fields} {
    variable datasetSelection
    variable datasetSelectionCounter
    if {![regexp {^sel_([0-9]+)$} $id -> n]} { error "Invalid Dataset Selection ID '$id'." }
    # IDs are zero-padded text. Normalize before storing the counter because
    # Tcl interprets a later `incr 008` as an invalid legacy octal integer.
    set n [scan $n %d]
    foreach {k v} $fields { set datasetSelection($id,$k) $v }
    set datasetSelection($id,id) $id
    set datasetSelection($id,api_version) 1
    if {$n > $datasetSelectionCounter} { set datasetSelectionCounter $n }
    return $id
}

proc ::GX::datasetSelectionNextId {} {
    variable datasetSelectionCounter
    while 1 {
        incr datasetSelectionCounter
        set id [format "sel_%03d" $datasetSelectionCounter]
        if {[datasetSelectionField $id id ""] eq ""} { return $id }
    }
}

proc ::GX::datasetSelectionRegistryPath {session} {
    return [file join $session metadata dataset_selections.ini]
}

proc ::GX::datasetSelectionSaveRegistry {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { return "" }
    file mkdir [file join $session metadata]
    set p [datasetSelectionRegistryPath $session]
    set tmp "${p}.tmp.[pid]"
    set fd [open $tmp w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Dataset Selection API v1 registry"
    puts $fd "; Selections are metadata references in canonical dataset coordinates; no data is copied."
    puts $fd "\[dataset_selection_api\]"; putKV $fd api_version 1; putKV $fd ids [join [datasetSelectionIds] ";"]
    foreach id [datasetSelectionIds] {
        puts $fd "\n\[dataset_selection.$id\]"
        foreach f {api_version id type members member_count source_dataset_id source_role x_variable x_variable_id x_unit x_min x_max x_coordinate_space x_display_unit x_display_min x_display_max x_binding_count x_bindings y_variable y_variable_id y_unit y_min y_max producer_module producer_graph producer_variant created_at updated_at} {
            putKV $fd $f [datasetSelectionField $id $f ""]
        }
    }
    close $fd
    file rename -force -- $tmp $p
    return $p
}

proc ::GX::datasetSelectionLoadRegistry {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    datasetSelectionClear
    if {$session eq ""} { return {} }
    set p [datasetSelectionRegistryPath $session]
    if {![file isfile $p]} { return {} }
    set d [parseIni $p]
    set ids [expr {[dict exists $d dataset_selection_api.ids] ? [splitList [dict get $d dataset_selection_api.ids]] : {}}]
    if {![llength $ids]} {
        foreach k [dict keys $d] {
            if {[regexp {^dataset_selection\.(sel_[0-9]+)\.id$} $k -> id]} { lappend ids $id }
        }
        set ids [lsort -unique $ids]
    }
    foreach id $ids {
        set fields {}
        foreach f {api_version id type members member_count source_dataset_id source_role x_variable x_variable_id x_unit x_min x_max x_coordinate_space x_display_unit x_display_min x_display_max x_binding_count x_bindings y_variable y_variable_id y_unit y_min y_max producer_module producer_graph producer_variant created_at updated_at} {
            set k "dataset_selection.$id.$f"
            if {[dict exists $d $k]} { lappend fields $f [dict get $d $k] }
        }
        if {[llength $fields]} { datasetSelectionRegister $id $fields }
    }
    return [datasetSelectionIds]
}

proc ::GX::datasetSelectionFindProducer {moduleId graphId {variantId ""}} {
    foreach id [datasetSelectionIds] {
        if {[datasetSelectionField $id producer_module ""] eq $moduleId && [datasetSelectionField $id producer_graph ""] eq $graphId && [datasetSelectionField $id producer_variant ""] eq $variantId} { return $id }
    }
    return ""
}

proc ::GX::datasetSelectionMatchesBinding {id moduleId graphId variantId typ xmeta ymeta} {
    if {[datasetSelectionField $id producer_module ""] ne $moduleId ||
        [datasetSelectionField $id producer_graph ""] ne $graphId ||
        [datasetSelectionField $id producer_variant ""] ne $variantId ||
        [datasetSelectionField $id type ""] ne $typ} { return 0 }

    set mode [expr {[dict exists $xmeta binding_mode] ? [dict get $xmeta binding_mode] : "single_source"}]
    if {$mode eq "shared_display"} {
        set expected [lsort -unique [dict get $xmeta binding_tokens]]
        set actual [lsort -unique [splitList [datasetSelectionField $id x_bindings ""]]]
        if {[datasetSelectionField $id x_coordinate_space ""] ne "display" || $actual ne $expected} { return 0 }
    } else {
        if {[datasetSelectionField $id source_dataset_id ""] ne [dict get $xmeta dataset_id]} { return 0 }
        set xid [datasetSelectionField $id x_variable_id ""]
        if {$xid ne ""} {
            if {$xid ne [dict get $xmeta variable_id]} { return 0 }
        } elseif {[datasetSelectionField $id x_variable ""] ne [dict get $xmeta variable]} { return 0 }
    }
    if {$typ eq "rectangle"} {
        set yid [datasetSelectionField $id y_variable_id ""]
        if {$yid ne ""} {
            if {$yid ne [dict get $ymeta variable_id]} { return 0 }
        } elseif {[datasetSelectionField $id y_variable ""] ne [dict get $ymeta variable]} { return 0 }
    }
    return 1
}
proc ::GX::datasetSelectionForPlot {moduleId graphKey} {
    set decoded [plotVariantDecodeKey $moduleId $graphKey]
    set graphId $graphKey; set variantId ""
    if {[llength $decoded] == 2} { lassign $decoded graphId variantId }
    if {![plotRegionSupports $moduleId $graphId]} { return "" }
    set typ [plotRegionType $moduleId $graphId]
    set xmeta [datasetSelectionResolveAxisBinding $moduleId $graphId x $variantId]
    set ymeta [dict create]
    if {$typ eq "rectangle"} {
        set ymeta [datasetSelectionResolveAxisBinding $moduleId $graphId y $variantId]
        if {[dict exists $xmeta binding_mode] && [dict get $xmeta binding_mode] eq "shared_display"} {
            error "$moduleId/$graphId: rectangle selection requires one canonical X dataset and variable."
        }
        if {[dict get $xmeta dataset_id] ne [dict get $ymeta dataset_id]} {
            error "$moduleId/$graphId: rectangle axes resolve to different datasets."
        }
    }
    foreach id [datasetSelectionIds] {
        if {[datasetSelectionMatchesBinding $id $moduleId $graphId $variantId $typ $xmeta $ymeta]} { return $id }
    }
    return ""
}

proc ::GX::datasetSelectionSourceToDisplay {geom axis value} {
    if {[dict exists $geom axis.1.${axis}_transform] && [dict get $geom axis.1.${axis}_transform] ne "affine"} {error "Region selection cannot invert the rendered $axis coordinate relation."}
    set sk "axis.1.${axis}_display_to_source_scale"
    set ok "axis.1.${axis}_display_to_source_offset"
    set scale [expr {[dict exists $geom $sk] ? [dict get $geom $sk] : 1.0}]
    set offset [expr {[dict exists $geom $ok] ? [dict get $geom $ok] : 0.0}]
    if {![string is double -strict $scale] || ![string is double -strict $offset] || $scale == 0} {
        error "Invalid source-to-display mapping for $axis axis."
    }
    return [expr {(double($value)-double($offset))/double($scale)}]
}

proc ::GX::datasetVariableUnit {datasetId variable} {
    if {$datasetId eq "" || $variable eq ""} { return "" }
    if {[llength [info commands ::GX::analysisSourceDatasetVariables]]} {
        foreach v [analysisSourceDatasetVariables $datasetId] {
            if {[dict get $v name] eq $variable} { return [dict get $v unit] }
        }
    }
    set vars [datasetVariableNamesById $datasetId]
    set raw [string map {"," ";"} [datasetField $datasetId units ""]]
    set units [expr {$raw eq "" ? {} : [split $raw ";"]}]
    set i [lsearch -exact $vars $variable]
    if {$i >= 0 && $i < [llength $units]} { return [lindex $units $i] }
    return ""
}

proc ::GX::datasetSelectionSourceDataset {moduleId sourceRole} {
    variable moduleCfg
    set sourceRole [string trim $sourceRole]
    if {$sourceRole eq ""} { set sourceRole primary }
    if {[moduleSupportsAnalysisSources $moduleId]} { return [analysisSourceDatasetFor $moduleId $sourceRole] }
    if {[info exists moduleCfg($moduleId,dataset_id)]} { return [string trim $moduleCfg($moduleId,dataset_id)] }
    return ""
}

# Graph Series is authoritative whenever at least one enabled series exists.
# Y rectangles still require one canonical left-axis binding. X-range
# selections may describe multiple source bindings because every enabled
# series is drawn in one shared display-domain X interval.
proc ::GX::datasetSelectionActiveSeriesBinding {moduleId graphId axis variantId} {
    set rows [graphSeriesList $moduleId $graphId $variantId]
    if {![llength $rows]} { return {} }
    if {$axis eq "y"} {
        set left {}
        foreach row $rows { if {[dict get $row axis] eq "left"} { lappend left $row } }
        if {![llength $left]} { error "$moduleId/$graphId: no enabled left-axis Graph Series for rectangle Y selection." }
        set rows $left
    }
    set token [expr {$axis eq "x" ? "x_variable_id" : "y_variable_id"}]
    set bindings {}
    set bindingTokens {}
    set seen [dict create]
    foreach row $rows {
        set ds [dict get $row dataset_id]
        set vid [dict get $row $token]
        set key "$ds:$vid"
        if {[dict exists $seen $key]} continue
        dict set seen $key 1
        set var [datasetVariableById $ds $vid]
        lappend bindings [dict create source_role primary dataset_id $ds variable [dict get $var canonical] variable_id $vid unit [dict get $var unit]]
        lappend bindingTokens $key
    }
    if {$axis eq "y" && [llength $bindings] > 1} {
        error "$moduleId/$graphId: ambiguous Graph Series y binding; select a graph with one y dataset and variable."
    }
    set result [lindex $bindings 0]
    dict set result bindings $bindings
    dict set result binding_tokens [lsort -unique $bindingTokens]
    dict set result binding_mode [expr {[llength $bindings] > 1 ? "shared_display" : "single_source"}]
    return $result
}
proc ::GX::datasetSelectionResolveAxisBinding {moduleId graphId axis {variantId ""}} {
    set seriesBinding [datasetSelectionActiveSeriesBinding $moduleId $graphId $axis $variantId]
    if {$seriesBinding ne ""} { return $seriesBinding }
    if {$variantId ne ""} {
        set b [plotVariantResolvedBinding $moduleId $graphId $variantId $axis]
        if {$b eq ""} { error "$moduleId/$graphId/$variantId: no $axis binding for Dataset Selection." }
        return [dict create source_role primary dataset_id [dict get $b dataset_id] variable [dict get $b name] variable_id [dict get $b variable_id] unit [dict get $b unit]]
    }
    set sourceRole [string trim [moduleGraphField $moduleId $graphId region_source primary]]
    if {$sourceRole eq ""} { set sourceRole primary }
    set bindingRole [string trim [moduleGraphField $moduleId $graphId "region_${axis}_binding" $axis]]
    set explicitVar [string trim [moduleGraphField $moduleId $graphId "region_${axis}_variable" ""]]
    set resolved ""
    if {$bindingRole ne ""} { catch {set resolved [resolveModuleBinding $moduleId $bindingRole ""]} }
    if {$resolved eq "" || $resolved eq "auto"} { set resolved $explicitVar }
    if {$resolved eq ""} { error "$moduleId/$graphId: cannot resolve region_${axis}_binding '$bindingRole' to a canonical variable." }

    set variable $resolved
    set dot [string first "." $resolved]
    if {$dot > 0} {
        set maybeSource [string range $resolved 0 [expr {$dot-1}]]
        if {[moduleSupportsAnalysisSources $moduleId] && [analysisSourceFindRow $moduleId $maybeSource]} {
            set sourceRole $maybeSource
            set variable [string range $resolved [expr {$dot+1}] end]
        }
    }
    set datasetId [datasetSelectionSourceDataset $moduleId $sourceRole]
    if {$datasetId eq ""} { error "$moduleId/$graphId: source '$sourceRole' has no selected canonical dataset." }
    if {[lsearch -exact [datasetVariableNamesById $datasetId] $variable] < 0} {
        error "$moduleId/$graphId: variable '$variable' is not present in canonical dataset '$datasetId'."
    }
    set v [datasetVariableResolve $datasetId $variable]
    return [dict create source_role $sourceRole dataset_id $datasetId variable $variable variable_id [dict get $v variable_id] unit [datasetVariableUnit $datasetId $variable]]
}

proc ::GX::datasetSelectionDisplayToSource {geom axis value} {
    if {[dict exists $geom axis.1.${axis}_transform] && [dict get $geom axis.1.${axis}_transform] ne "affine"} {
        error "Region selection cannot invert the rendered $axis coordinate relation."
    }
    set sk "axis.1.${axis}_display_to_source_scale"
    set ok "axis.1.${axis}_display_to_source_offset"
    set scale [expr {[dict exists $geom $sk] ? [dict get $geom $sk] : 1.0}]
    set offset [expr {[dict exists $geom $ok] ? [dict get $geom $ok] : 0.0}]
    if {![string is double -strict $scale] || ![string is double -strict $offset]} { error "Invalid display-to-source mapping for $axis axis." }
    return [expr {double($value)*double($scale)+double($offset)}]
}

proc ::GX::datasetSelectionFromPlotRegion {moduleId graphId png {editingId ""}} {
    variable plotRegion
    set graphKey $graphId
    set decoded [plotVariantDecodeKey $moduleId $graphId]
    set variantId ""
    if {[llength $decoded] == 2} { lassign $decoded graphId variantId }
    variable currentSession
    if {![plotRegionSupports $moduleId $graphId]} { return "" }
    plotRegionEnsure $moduleId $graphKey
    if {!$plotRegion($moduleId,$graphKey,enabled)} { return "" }
    if {$currentSession ne "" && [file isdirectory $currentSession]} {
        loadDatasetRegistry $currentSession
        datasetSelectionLoadRegistry $currentSession
    }
    set typ [plotRegionType $moduleId $graphId]
    if {$typ ni {x_range rectangle}} { error "Unsupported Dataset Selection type '$typ'." }
    set xmeta [datasetSelectionResolveAxisBinding $moduleId $graphId x $variantId]
    set ymeta [dict create]
    if {$typ eq "rectangle"} { set ymeta [datasetSelectionResolveAxisBinding $moduleId $graphId y $variantId] }
    set xBindingMode [expr {[dict exists $xmeta binding_mode] ? [dict get $xmeta binding_mode] : "single_source"}]
    if {$typ eq "rectangle" && $xBindingMode eq "shared_display"} {
        error "$moduleId/$graphId: rectangle selection requires one canonical X dataset and variable."
    }
    if {$typ eq "rectangle" && [dict get $xmeta dataset_id] ne [dict get $ymeta dataset_id]} {
        error "$moduleId/$graphId: rectangle axes resolve to different datasets; Dataset Selection API v1 requires one canonical dataset."
    }
    set geom [plotRegionGeometry $png]
    set displayXMin $plotRegion($moduleId,$graphKey,x_min)
    set displayXMax $plotRegion($moduleId,$graphKey,x_max)
    if {$displayXMin > $displayXMax} { set q $displayXMin; set displayXMin $displayXMax; set displayXMax $q }
    set xmin [datasetSelectionDisplayToSource $geom x $displayXMin]
    set xmax [datasetSelectionDisplayToSource $geom x $displayXMax]
    if {$xmin > $xmax} { set q $xmin; set xmin $xmax; set xmax $q }
    set displayUnit [expr {[dict exists $geom axis.1.x_display_unit] ? [dict get $geom axis.1.x_display_unit] : [dict get $xmeta unit]}]
    set bindingTokens [expr {[dict exists $xmeta binding_tokens] ? [dict get $xmeta binding_tokens] : [list "[dict get $xmeta dataset_id]:[dict get $xmeta variable_id]"]}]

    if {$editingId ne ""} {
        if {![datasetSelectionMatchesBinding $editingId $moduleId $graphId $variantId $typ $xmeta $ymeta]} {
            error "Selection $editingId no longer matches the graph dataset, variables, or type."
        }
        set id $editingId
    } else {
        set id [datasetSelectionForPlot $moduleId $graphKey]
        # Preserve the legacy same-producer reconfiguration from X-range to
        # rectangle when the source dataset and X identity are unchanged.
        if {$id eq "" && $typ eq "rectangle"} {
            foreach candidate [datasetSelectionIds] {
                if {[datasetSelectionMatchesBinding $candidate $moduleId $graphId $variantId x_range $xmeta [dict create]]} {
                    set id $candidate; break
                }
            }
        }
        if {$id eq ""} { set id [datasetSelectionNextId] }
    }
    set created [datasetSelectionField $id created_at ""]
    if {$created eq ""} { set created [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] }
    set now [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    set fields [list type $typ source_dataset_id [dict get $xmeta dataset_id] source_role [dict get $xmeta source_role] \
        x_variable [dict get $xmeta variable] x_variable_id [dict get $xmeta variable_id] x_unit [dict get $xmeta unit] x_min [format %.17g $xmin] x_max [format %.17g $xmax] \
        x_coordinate_space [expr {$xBindingMode eq "shared_display" ? "display" : "source"}] x_display_unit $displayUnit \
        x_display_min [format %.17g $displayXMin] x_display_max [format %.17g $displayXMax] \
        x_binding_count [llength $bindingTokens] x_bindings [join $bindingTokens ";"] \
        y_variable "" y_variable_id "" y_unit "" y_min "" y_max "" producer_module $moduleId producer_graph $graphId producer_variant $variantId created_at $created updated_at $now]
    if {$typ eq "rectangle"} {
        set ymin [datasetSelectionDisplayToSource $geom y $plotRegion($moduleId,$graphKey,y_min)]
        set ymax [datasetSelectionDisplayToSource $geom y $plotRegion($moduleId,$graphKey,y_max)]
        if {$ymin > $ymax} { set q $ymin; set ymin $ymax; set ymax $q }
        lappend fields y_variable [dict get $ymeta variable] y_variable_id [dict get $ymeta variable_id] y_unit [dict get $ymeta unit] y_min [format %.17g $ymin] y_max [format %.17g $ymax]
    }
    variable datasetSelection
    set before [array get datasetSelection]
    if {[catch {
        datasetSelectionRegister $id $fields
        datasetSelectionSaveRegistry $currentSession
    } err opts]} {
        array unset datasetSelection *
        array set datasetSelection $before
        return -options $opts $err
    }
    catch {refreshManifestPreview}
    return $id
}

proc ::GX::datasetSelectionDescription {id} {
    set typ [datasetSelectionField $id type ""]
    if {$typ eq "members"} {return "$id — [datasetSelectionField $id member_count] source members (Dataset rows)"}
    set mode [datasetSelectionField $id x_coordinate_space "source"]
    if {$mode eq "display" && [datasetSelectionField $id x_binding_count 0] > 1} {
        set xa [datasetSelectionField $id x_display_min ""]
        set xb [datasetSelectionField $id x_display_max ""]
        set xu [datasetSelectionField $id x_display_unit ""]
        set out "$id — shared display X: $xa … $xb"
        if {$xu ne ""} { append out " $xu" }
        append out " ([datasetSelectionField $id x_binding_count] bindings)"
    } else {
        set ds [datasetSelectionField $id source_dataset_id ""]
        set xv [datasetSelectionField $id x_variable ""]
        set xu [datasetSelectionField $id x_unit ""]
        set xa [datasetSelectionField $id x_min ""]; set xb [datasetSelectionField $id x_max ""]
        set out "$id — $ds — $xv: $xa … $xb"
        if {$xu ne ""} { append out " $xu" }
    }
    if {$typ eq "rectangle"} {
        set yv [datasetSelectionField $id y_variable ""]; set yu [datasetSelectionField $id y_unit ""]
        append out " | $yv: [datasetSelectionField $id y_min ""] … [datasetSelectionField $id y_max ""]"
        if {$yu ne ""} { append out " $yu" }
    }
    return $out
}
proc ::GX::datasetSelectionCompatibleIds {moduleId configKey} {
    variable currentSession
    if {$currentSession ne "" && [file isdirectory $currentSession]} { catch {loadDatasetRegistry $currentSession}; catch {datasetSelectionLoadRegistry $currentSession} }
    set source [string trim [moduleConfigField $moduleId $configKey source_role primary]]
    if {$source eq ""} { set source primary }
    set target [datasetSelectionSourceDataset $moduleId $source]
    set multiple [moduleConfigField $moduleId $configKey multiple_sources 0]
    if {$target eq "" && !$multiple} { return {} }
    set allowed [splitList [moduleConfigField $moduleId $configKey selection_types "x_range;rectangle"]]
    set out {}
    foreach id [datasetSelectionIds] {
        if {[datasetSelectionField $id type ""] eq "members"} {
            if {$multiple} {lappend out $id}
            continue
        }
        if {[datasetSelectionField $id source_dataset_id ""] ne $target} continue
        if {[lsearch -exact $allowed [datasetSelectionField $id type ""]] < 0} continue
        lappend out $id
    }
    return $out
}

proc ::GX::datasetSelectionValidateConfig {moduleId configKey} {
    variable moduleCfg
    set value [expr {[info exists moduleCfg($moduleId,$configKey)] ? [string trim $moduleCfg($moduleId,$configKey)] : ""}]
    set required [expr {[moduleConfigField $moduleId $configKey required 0] ? 1 : 0}]
    if {$value eq "" || $value eq "None"} {
        if {$required} { error "$moduleId: configuration '$configKey' requires a Dataset Selection." }
        return ""
    }
    if {[datasetSelectionField $value id ""] eq ""} { error "$moduleId: unknown Dataset Selection '$value'." }
    if {[lsearch -exact [datasetSelectionCompatibleIds $moduleId $configKey] $value] < 0} {
        error "$moduleId: Dataset Selection '$value' is incompatible with the dataset/source configured for '$configKey'."
    }
    return $value
}

proc ::GX::datasetSelectionWidgetRefresh {moduleId configKey w} {
    variable moduleCfg
    variable selectionWidgetDisplay
    if {![winfo exists $w]} return
    set values {None}
    foreach id [datasetSelectionCompatibleIds $moduleId $configKey] { lappend values [datasetSelectionDescription $id] }
    $w configure -values $values
    set cur [expr {[info exists moduleCfg($moduleId,$configKey)] ? [string trim $moduleCfg($moduleId,$configKey)] : ""}]
    if {$cur eq "" || [lsearch -exact [datasetSelectionCompatibleIds $moduleId $configKey] $cur] < 0} {
        set selectionWidgetDisplay($moduleId,$configKey) "None"
    } else {
        set selectionWidgetDisplay($moduleId,$configKey) [datasetSelectionDescription $cur]
    }
}

proc ::GX::datasetSelectionWidgetChanged {moduleId configKey} {
    variable moduleCfg
    variable selectionWidgetDisplay
    set s [expr {[info exists selectionWidgetDisplay($moduleId,$configKey)] ? $selectionWidgetDisplay($moduleId,$configKey) : "None"}]
    if {$s eq "None" || [string trim $s] eq ""} { set moduleCfg($moduleId,$configKey) "" } else { set moduleCfg($moduleId,$configKey) [lindex $s 0] }
    catch {refreshManifestPreview}
}

# Descriptor-driven field type=selection. No plugin-private widget is needed.
proc ::GX::standardConfigWidget_v092_before_repeatable_config {parent id key row} {
    variable selectionWidgetDisplay
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ne "selection"} { return [::GX::standardConfigWidget_v091_before_dataset_selection $parent $id $key $row] }
    set label [moduleConfigField $id $key label $key]
    ttk::label $parent.l$row -text $label
    ttk::combobox $parent.w$row -textvariable ::GX::selectionWidgetDisplay($id,$key) -state readonly -width 68 \
        -postcommand [list ::GX::datasetSelectionWidgetRefresh $id $key $parent.w$row]
    bind $parent.w$row <<ComboboxSelected>> [list ::GX::datasetSelectionWidgetChanged $id $key]
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
    datasetSelectionWidgetRefresh $id $key $parent.w$row
}

# Runtime transport to any consumer module declaring type=selection.
proc ::GX::writeStandardRuntimeConfig_v092_before_repeatable_config {id} {
    variable moduleCfg
    variable currentSession
    if {$currentSession ne "" && [file isdirectory $currentSession]} { catch {datasetSelectionLoadRegistry $currentSession} }
    set p [::GX::writeStandardRuntimeConfig_v091_before_dataset_selection $id]
    set keys {}
    foreach key [moduleConfigKeys $id] { if {[string tolower [moduleConfigField $id $key type string]] eq "selection"} { lappend keys $key } }
    if {![llength $keys]} { return $p }
    set fd [open $p a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[dataset_selection_api\]"; putKV $fd api_version 1
    foreach key $keys {
        set sid ""
        if {[catch {set sid [datasetSelectionValidateConfig $id $key]} err]} { close $fd; error $err }
        puts $fd "\n\[selection.$key\]"; putKV $fd api_version 1; putKV $fd id $sid
        if {$sid eq ""} { putKV $fd enabled 0; continue }
        putKV $fd enabled 1
        foreach f {type members member_count source_dataset_id source_role x_variable x_variable_id x_unit x_min x_max x_coordinate_space x_display_unit x_display_min x_display_max x_binding_count x_bindings y_variable y_variable_id y_unit y_min y_max producer_module producer_graph producer_variant} { putKV $fd $f [datasetSelectionField $sid $f ""] }
    }
    close $fd
    return $p
}

# Keep a manifest snapshot for portability. The dedicated session registry is
# authoritative and lets selection resources survive independently of a run.
proc ::GX::manifestStringV2_v092_before_repeatable_config {} {
    set out [::GX::manifestStringV2_v091_before_dataset_selection]
    append out "\n\[dataset_selection_api\]\n"; appendKV out version 1; appendKV out ids [join [datasetSelectionIds] ";"]
    foreach id [datasetSelectionIds] {
        append out "\n\[dataset_selection.$id\]\n"
        foreach f {api_version id type members member_count source_dataset_id source_role x_variable x_variable_id x_unit x_min x_max x_coordinate_space x_display_unit x_display_min x_display_max x_binding_count x_bindings y_variable y_variable_id y_unit y_min y_max producer_module producer_graph producer_variant created_at updated_at} { appendKV out $f [datasetSelectionField $id $f ""] }
    }
    return $out
}

proc ::GX::loadManifestV2_v092_before_repeatable_config {path} {
    variable currentSession
    ::GX::loadManifestV2_v091_before_dataset_selection $path
    if {$currentSession ne "" && [file isfile [datasetSelectionRegistryPath $currentSession]]} {
        datasetSelectionLoadRegistry $currentSession
        return
    }
    datasetSelectionClear
    set d [parseIni $path]
    set ids [expr {[dict exists $d dataset_selection_api.ids] ? [splitList [dict get $d dataset_selection_api.ids]] : {}}]
    foreach id $ids {
        set fields {}
        foreach f {api_version id type members member_count source_dataset_id source_role x_variable x_variable_id x_unit x_min x_max x_coordinate_space x_display_unit x_display_min x_display_max x_binding_count x_bindings y_variable y_variable_id y_unit y_min y_max producer_module producer_graph producer_variant created_at updated_at} {
            set k "dataset_selection.$id.$f"; if {[dict exists $d $k]} { lappend fields $f [dict get $d $k] }
        }
        if {[llength $fields]} { datasetSelectionRegister $id $fields }
    }
    if {$currentSession ne "" && [file isdirectory $currentSession] && [llength [datasetSelectionIds]]} { catch {datasetSelectionSaveRegistry $currentSession} }
}

proc ::GX::defaults_v092_before_repeatable_config {} {
    variable selectionWidgetDisplay
    ::GX::defaults_v091_before_dataset_selection
    datasetSelectionClear
    array unset selectionWidgetDisplay *
}
