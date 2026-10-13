# GX-TXT Graph Series API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset-scoped variable identities for independent multi-dataset plot series.
namespace eval ::GX {
    variable graphSeriesApiVersion 1
    variable graphSeries
    array set graphSeries {}
    variable graphSeriesDistinctCache
    array set graphSeriesDistinctCache {}
}


# plot.dataset robustness: dataset deletion can leave stale Graph Series references;
# prune missing datasets/variables so editors and runtimes remain usable.
proc ::GX::graphSeriesRecordStale {fields} {
    variable currentSession
    if {$currentSession eq ""} { return 0 }
    set ds [dict get $fields dataset_id]
    # An explicitly disabled, unbound series is reusable preparation (New
    # Experiment). It has no source to become stale and must survive reopen/save.
    if {$ds eq "" && [dict exists $fields enabled] && ![dict get $fields enabled]} {return 0}
    if {[datasetField $ds id ""] eq ""} { return 1 }
    foreach field {x_variable_id y_variable_id} {
        if {![dict exists $fields $field] || [catch {datasetVariableById $ds [dict get $fields $field]}]} { return 1 }
    }
    return 0
}

proc ::GX::graphSeriesPruneInvalid {} {
    variable graphSeries
    variable datasetRegistry
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return {} }
    if {![array size datasetRegistry]} {catch {loadDatasetRegistry $currentSession}}
    set removed {}
    foreach key [array names graphSeries] {
        if {![graphSeriesRecordStale $graphSeries($key)]} continue
        lappend removed $key
        unset graphSeries($key)
    }
    return $removed
}

proc ::GX::graphSeriesPruneDatasetReferences {datasetId} {
    variable graphSeries
    set removed {}
    foreach key [array names graphSeries] {
        if {[dict exists $graphSeries($key) dataset_id] && [dict get $graphSeries($key) dataset_id] eq $datasetId} {
            lappend removed $key
            unset graphSeries($key)
        }
    }
    return $removed
}

proc ::GX::graphSeriesVariablesUnavailable {fields} {
    set ds [dict get $fields dataset_id]
    set unavailable 0
    foreach token {x y} {
        set v [datasetVariableById $ds [dict get $fields [format "%s_variable_id" $token]]]
        if {![dict get $v enabled]} { set unavailable 1 }
    }
    foreach filter [dict get $fields row_filters] {
        set v [datasetVariableById $ds [dict get $filter filter_variable_id]]
        if {![dict get $v enabled]} {set unavailable 1}
    }
    return $unavailable
}

proc ::GX::graphSeriesNormalizeFilters {datasetId filters} {
    set normalized {}
    foreach filter $filters {
        if {[catch {dict size $filter}]} {error "each Graph Series row filter must be a dictionary"}
        foreach key {filter_variable_id predicate} {
            if {![dict exists $filter $key] || [string trim [dict get $filter $key]] eq ""} {error "Graph Series row filter requires $key"}
        }
        set predicate [dict get $filter predicate]
        if {$predicate ni {exact_equal not_equal less_than less_equal greater_than greater_equal between_inclusive in_set is_finite is_nonfinite}} {
            error "unsupported Graph Series row predicate: $predicate"
        }
        set id [dict get $filter filter_variable_id]
        set variable [datasetVariableResolve $datasetId $id]
        set id [dict get $variable variable_id]
        dict set filter filter_variable_id $id
        set variable [datasetVariableV3ById $datasetId $id]
        set dtype [dict get $variable dtype]
        set numeric [expr {$dtype ne "string"}]
        if {!$numeric && $predicate ni {exact_equal not_equal in_set}} {
            error "Graph Series predicate $predicate requires a numeric variable"
        }
        set required {}
        switch -- $predicate {
            exact_equal - not_equal - less_than - less_equal - greater_than - greater_equal {set required {value}}
            between_inclusive {set required {lower upper}}
            in_set {set required {values}}
        }
        foreach key $required {if {![dict exists $filter $key]} {error "Graph Series predicate $predicate requires $key"}}
        set allowed [concat {filter_variable_id predicate dtype} $required]
        dict for {key value} $filter {
            if {$key ni $allowed} {error "unknown Graph Series row filter field: $key"}
            if {[regexp {[\r\n]} $value]} {error "Graph Series filter values must be single-line"}
        }
        if {$predicate eq "in_set" && ![llength [dict get $filter values]]} {error "Graph Series in_set requires values"}
        if {$numeric} {
            foreach key $required {
                set values [expr {$key eq "values" ? [dict get $filter $key] : [list [dict get $filter $key]]}]
                foreach value $values {
                    if {![string is double -strict $value] || [catch {set numericValue [expr {double($value)}]}] || [expr {abs($numericValue) == Inf}]} {
                        error "Graph Series filter $key must contain finite numeric values"
                    }
                }
            }
        }
        if {$predicate eq "between_inclusive" && [dict get $filter lower] > [dict get $filter upper]} {
            error "Graph Series filter lower exceeds upper"
        }
        dict set filter dtype $dtype
        lappend normalized $filter
    }
    return $normalized
}

proc ::GX::graphSeriesCheckFilterBindings {fields} {
    set ds [dict get $fields dataset_id]
    foreach filter [dict get $fields row_filters] {
        set id [dict get $filter filter_variable_id]
        if {[catch {set variable [datasetVariableV3ById $ds $id]}]} {
            error "Graph Series row filter has stale variable ID $id"
        }
        if {[dict get $variable dtype] ne [dict get $filter dtype]} {
            error "Graph Series row filter variable $id changed dtype"
        }
        if {![dict get $variable enabled]} {
            error "Graph Series row filter variable $id is Use=no"
        }
    }
}

# Pure validation/normalization used by the editor before any provider-owned
# extension state or Graph Series state is committed.
proc ::GX::graphSeriesValidate {moduleId graphId seriesId fields {variantId ""} {mergeExisting 1}} {
    variable graphSeries
    if {[lsearch -exact [moduleGraphIds $moduleId] $graphId] < 0} { error "Unknown graph provider ID: $moduleId/$graphId" }
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $seriesId]} { error "Invalid graph series ID" }
    foreach key {dataset_id x_variable_id y_variable_id axis} {
        if {![dict exists $fields $key]} { error "Graph series requires $key" }
    }
    dict for {key value} $fields {
        if {$key ni {dataset_id x_variable_id y_variable_id family_variable_id secondary_variable_id ordering_variable_id axis label enabled order alignment_mode manual_offset_seconds row_filters source_row_ordinals style_color style_line_style}} { error "Unknown graph series field: $key" }
        if {[regexp {[
]} $value]} { error "Graph series fields must be single-line" }
    }
    if {[dict get $fields axis] ni {left right}} { error "axis must be left or right" }
    set key [graphSeriesKey $moduleId $graphId $seriesId $variantId]
    if {$mergeExisting && [info exists graphSeries($key)]} { set fields [dict merge $graphSeries($key) $fields] }
    if {![dict exists $fields label]} { dict set fields label "" }
    if {![dict exists $fields style_color]} {dict set fields style_color ""}
    if {![dict exists $fields style_line_style]} {dict set fields style_line_style ""}
    if {[dict get $fields style_color] ne "" && ![regexp {^#[0-9A-Fa-f]{6}$} [dict get $fields style_color]]} {error "Graph series style_color must be #RRGGBB"}
    if {[dict get $fields style_line_style] ni {{} solid dashed dotted dashdot}} {error "Graph series style_line_style is invalid"}
    if {![dict exists $fields row_filters]} {dict set fields row_filters {}}
    if {[dict exists $fields source_row_ordinals]} {dict set fields source_row_ordinals [graphSeriesNormalizeRowOrdinals [dict get $fields source_row_ordinals]]}
    if {![dict exists $fields enabled]} { dict set fields enabled 1 }
    if {[dict get $fields enabled] ni {0 1}} { error "enabled must be 0 or 1" }
    if {![dict exists $fields order]} { dict set fields order 0 }
    if {![string is integer -strict [dict get $fields order]] || [dict get $fields order] < 0} { error "order must be a nonnegative integer" }
    if {![dict exists $fields alignment_mode]} { dict set fields alignment_mode none }
    if {![dict exists $fields manual_offset_seconds]} { dict set fields manual_offset_seconds 0 }
    if {[dict get $fields alignment_mode] ni {none common_elapsed_zero absolute_origin manual_offset}} { error "Unknown time alignment mode" }
    if {![string is double -strict [dict get $fields manual_offset_seconds]]} { error "manual_offset_seconds must be numeric" }
    set ds [dict get $fields dataset_id]
    if {[datasetField $ds id ""] eq "" && $::GX::currentSession ne ""} { loadDatasetRegistry $::GX::currentSession }
    foreach field {family_variable_id secondary_variable_id ordering_variable_id} {
        if {![dict exists $fields $field]} {dict set fields $field ""}
        set variableId [string trim [dict get $fields $field]]
        if {$variableId eq ""} continue
        set variable [datasetVariableResolve $ds $variableId]
        if {![dict get $variable enabled]} {error "Graph Series $field references a Use=no variable"}
        dict set fields $field [dict get $variable variable_id]
        if {$field eq "ordering_variable_id"} {
            set schema [datasetVariableV3ById $ds [dict get $variable variable_id]]
            if {[dict get $schema dtype] eq "string"} {error "Graph Series ordering variable must be numeric"}
        }
    }
    dict set fields row_filters [graphSeriesNormalizeFilters $ds [dict get $fields row_filters]]
    set unavailable [graphSeriesVariablesUnavailable $fields]
    if {$variantId eq "" && [dict get $fields enabled] && $unavailable} { error "Graph series cannot bind Use=no variable" }
    if {$variantId ne "" && (![llength [info commands ::GX::plotVariantExists]] || ![plotVariantExists $moduleId $graphId $variantId])} { error "Unknown plot variant" }
    return $fields
}

proc ::GX::graphSeriesSet {moduleId graphId seriesId fields {variantId ""}} {
    variable graphSeries
    set fields [graphSeriesValidate $moduleId $graphId $seriesId $fields $variantId]
    set unavailable [graphSeriesVariablesUnavailable $fields]
    set key [graphSeriesKey $moduleId $graphId $seriesId $variantId]
    set graphSeries($key) $fields
    if {$unavailable} { return [dict merge $fields [dict create module_id $moduleId graph_id $graphId variant_id $variantId series_id $seriesId available 0]] }
    return [graphSeriesResolve $moduleId $graphId $seriesId $variantId]
}

# Read-only generic state for public editor extensions. Unlike Resolve, this
# does not expose paths or require provider code to inspect CORE arrays.
proc ::GX::graphSeriesSnapshot {moduleId graphId seriesId {variantId ""}} {
    variable graphSeries
    set key [graphSeriesKey $moduleId $graphId $seriesId $variantId]
    if {![info exists graphSeries($key)]} { error "Unknown graph series" }
    return [dict merge $graphSeries($key) [dict create         module_id $moduleId graph_id $graphId variant_id $variantId series_id $seriesId]]
}
proc ::GX::graphSeriesKey {moduleId graphId seriesId {variantId ""}} {
    if {$variantId eq ""} { return "$moduleId,$graphId,$seriesId" }
    return "$moduleId,$graphId,$variantId,$seriesId"
}
proc ::GX::graphSeriesRemove {moduleId graphId seriesId {variantId ""}} {
    variable graphSeries
    catch {unset graphSeries([graphSeriesKey $moduleId $graphId $seriesId $variantId])}
}
proc ::GX::graphSeriesOrderCompare {a b} {
    lassign $a ao aid
    lassign $b bo bid
    if {$ao != $bo} { return [expr {$ao < $bo ? -1 : 1}] }
    return [string compare $aid $bid]
}
proc ::GX::graphSeriesIds {moduleId graphId {variantId ""}} {
    variable graphSeries
    graphSeriesPruneInvalid
    set out {}
    set prefix "$moduleId,$graphId,"
    if {$variantId ne ""} { append prefix "$variantId," }
    foreach key [array names graphSeries "$prefix*"] {
        set tail [string range $key [string length $prefix] end]
        if {[string first , $tail] >= 0} continue
        set order [expr {[dict exists $graphSeries($key) order] ? [dict get $graphSeries($key) order] : 0}]
        lappend out [list $order $tail]
    }
    set ids {}
    foreach item [lsort -command ::GX::graphSeriesOrderCompare $out] { lappend ids [lindex $item 1] }
    return $ids
}
proc ::GX::graphSeriesMove {moduleId graphId seriesId delta {variantId ""}} {
    variable graphSeries
    if {$delta ni {-1 1}} { error "Graph series move must be -1 or 1" }
    set ids [graphSeriesIds $moduleId $graphId $variantId]
    set i [lsearch -exact $ids $seriesId]
    if {$i < 0} { error "Unknown graph series" }
    set j [expr {$i+$delta}]
    if {$j < 0 || $j >= [llength $ids]} { return $ids }
    set other [lindex $ids $j]
    lset ids $j $seriesId
    lset ids $i $other
    set rank 0
    foreach id $ids {
        incr rank
        set key [graphSeriesKey $moduleId $graphId $id $variantId]
        dict set graphSeries($key) order $rank
    }
    return $ids
}
proc ::GX::graphSeriesResolve {moduleId graphId seriesId {variantId ""}} {
    variable graphSeries
    set key [graphSeriesKey $moduleId $graphId $seriesId $variantId]
    if {![info exists graphSeries($key)]} { error "Unknown graph series" }
    set d $graphSeries($key)
    if {![dict exists $d row_filters]} {dict set d row_filters {}}
    if {[dict get $d dataset_id] eq "" && [dict exists $d enabled] && ![dict get $d enabled]} {
        # Editors and inspection may list a prepared series before binding it.
        # Return an honest unavailable descriptor; runtime lists exclude it.
        set result [dict merge $d [dict create series_id $seriesId module_id $moduleId graph_id $graphId variant_id $variantId available 0 binding_status unbound]]
        foreach field {path x_name y_name x_unit y_unit x_semantic_role y_semantic_role x_value_kind x_value_format x_decimal_separator y_value_kind y_value_format y_decimal_separator time_reference time_origin x_time_reference x_time_origin y_time_reference y_time_origin} {dict set result $field ""}
        return $result
    }
    if {[graphSeriesRecordStale $d]} {
        unset graphSeries($key)
        error "Graph series references a dataset or variable that no longer exists"
    }
    graphSeriesCheckFilterBindings $d
    set ds [dict get $d dataset_id]
    set x [datasetVariableById $ds [dict get $d x_variable_id]]
    set y [datasetVariableById $ds [dict get $d y_variable_id]]
    if {[dict get $d enabled] && (![dict get $x enabled] || ![dict get $y enabled])} { error "Graph series variable is Use=no" }
    return [dict merge $d [dict create series_id $seriesId module_id $moduleId graph_id $graphId variant_id $variantId path [datasetResolvePath $::GX::currentSession $ds] x_name [dict get $x canonical] y_name [dict get $y canonical] x_unit [dict get $x unit] y_unit [dict get $y unit] x_semantic_role [dict get $x semantic_role] y_semantic_role [dict get $y semantic_role] x_value_kind [dict get $x value_kind] x_value_format [dict get $x value_format] x_decimal_separator [dict get $x decimal_separator] y_value_kind [dict get $y value_kind] y_value_format [dict get $y value_format] y_decimal_separator [dict get $y decimal_separator] time_reference [dict get $x time_reference] time_origin [dict get $x time_origin] x_time_reference [dict get $x time_reference] x_time_origin [dict get $x time_origin] y_time_reference [dict get $y time_reference] y_time_origin [dict get $y time_origin]]]
}
proc ::GX::graphSeriesList {moduleId graphId {variantId ""} {includeDisabled 0}} {
    set out {}
    foreach id [graphSeriesIds $moduleId $graphId $variantId] {
        set key [graphSeriesKey $moduleId $graphId $id $variantId]
        if {!$includeDisabled && [dict exists $::GX::graphSeries($key) enabled] && ![dict get $::GX::graphSeries($key) enabled]} { continue }
        lappend out [graphSeriesResolve $moduleId $graphId $id $variantId]
    }
    return $out
}

proc ::GX::graphSeriesCanonicalMember {dtype value} {
    if {$dtype eq "string"} {return $value}
    if {![string is double -strict $value] || [catch {set n [expr {double($value)}]}] || [expr {abs($n) == Inf}]} {
        error "Graph Series family member must be a finite numeric source value"
    }
    return [format %.17g $n]
}

# Return distinct source values in encounter order. Keep their original text
# (including numeric formatting) for display and exact row-filter construction.
proc ::GX::graphSeriesDistinctValues {datasetId variableId {chunkRows 4096} {refresh 0} {maxValues 2000}} {
    variable graphSeriesDistinctCache
    if {!$refresh && [info commands ::GX::datasetScientificProfileRead] ne {}} {
        set profile [datasetScientificProfileRead $::GX::currentSession $datasetId]
        if {[dict get $profile status] eq "current"} {
            foreach dimension [dict get $profile variables] {
                if {[dict get $dimension variable_id] eq $variableId && [dict get $dimension complete]} {
                    set values [dict get $dimension values]
                    if {[llength $values]>$maxValues} {error "Too many distinct values for a list ($maxValues maximum); use a typed filter"}
                    return $values
                }
            }
        }
    }
    set path [datasetResolvePath $::GX::currentSession $datasetId]
    if {$path eq "" || ![file isfile $path]} {error "Dataset source is unavailable"}
    set variable [datasetVariableV3ById $datasetId $variableId]
    file stat $path sourceStat
    set signature [list $::GX::currentSession $datasetId $variableId $sourceStat(size) $sourceStat(mtime) $sourceStat(ino) $variable [datasetField $datasetId canonical_sha256 ""]]
    set cacheKey [list $::GX::currentSession $datasetId $variableId]
    if {!$refresh && [info exists graphSeriesDistinctCache($cacheKey)] &&
        [lindex $graphSeriesDistinctCache($cacheKey) 0] eq $signature} {
        return [lindex $graphSeriesDistinctCache($cacheKey) 1]
    }
    set stream [tableStreamOpenDataset $::GX::currentSession $datasetId [list $variableId] $chunkRows]
    set seen [dict create]; set out {}
    try {
        while {1} {
            set chunk [tableStreamNext $stream]
            foreach value [dict get $chunk values $variableId] {
                if {[dict get $variable dtype] ne "string"} {
                    if {[catch {graphSeriesCanonicalMember [dict get $variable dtype] $value}]} continue
                }
                if {![dict exists $seen $value]} {
                    if {[llength $out] >= $maxValues} {error "Too many distinct values for a list ($maxValues maximum); use a typed filter"}
                    dict set seen $value 1; lappend out $value
                }
            }
            if {[dict get $chunk eof]} break
        }
    } finally {tableStreamClose $stream}
    set graphSeriesDistinctCache($cacheKey) [list $signature $out]
    return $out
}

proc ::GX::graphSeriesFilterRowMatch {filter value} {
    set predicate [dict get $filter predicate]
    set numeric [expr {[dict get $filter dtype] ne "string"}]
    if {$numeric && (![string is double -strict $value] || [catch {set value [expr {double($value)}]}])} {return 0}
    switch -- $predicate {
        exact_equal {return [expr {$numeric ? $value == double([dict get $filter value]) : $value eq [dict get $filter value]}]}
        not_equal {return [expr {$numeric ? $value != double([dict get $filter value]) : $value ne [dict get $filter value]}]}
        in_set {
            foreach candidate [dict get $filter values] {
                if {$numeric ? $value == double($candidate) : $value eq $candidate} {return 1}
            }
            return 0
        }
        less_than {return [expr {$value < double([dict get $filter value])}]}
        less_equal {return [expr {$value <= double([dict get $filter value])}]}
        greater_than {return [expr {$value > double([dict get $filter value])}]}
        greater_equal {return [expr {$value >= double([dict get $filter value])}]}
        between_inclusive {return [expr {$value >= double([dict get $filter lower]) && $value <= double([dict get $filter upper])}]}
        is_finite {return [expr {abs($value) != Inf}]}
        is_nonfinite {return [expr {abs($value) == Inf}]}
    }
    return 0
}

proc ::GX::graphSeriesNormalizeRowOrdinals {rows} {
    if {[llength $rows]>200000} {error {Graph Series explicit row selection exceeds 200000 rows}}
    set seen {}
    foreach row $rows {
        if {![string is entier -strict $row] || $row<0 || $row>9007199254740991} {error {Graph Series needs exact nonnegative row ordinals within its Octave index range}}
        if {[dict exists $seen $row]} {error {Graph Series row selection contains duplicate ordinals}}
        dict set seen $row 1
    }
    return [lsort -integer $rows]
}
proc ::GX::graphSeriesExpandGroups {moduleId graphId datasetId xVariableId yVariableId groupVariableId {options {}} {variantId ""} {progress {}}} {
    if {[catch {dict size $options}]} {error "Graph Series family options must be a dictionary"}
    set defaults [dict create chunk_rows 4096 max_members 1000 series_prefix family label_template {{member}} member_order {} label_variable_id {} category_variable_id {} family_values {} category_values {} category_behavior Filter row_filters {} ordering_variable_id {} dry_run 0 source_row_ordinals {}]
    dict for {key value} $options {
        if {![dict exists $defaults $key]} {error "unknown Graph Series family option: $key"}
        dict set defaults $key $value
    }
    set chunkRows [dict get $defaults chunk_rows]
    set maxMembers [dict get $defaults max_members]
    if {![string is integer -strict $chunkRows] || $chunkRows < 1} {error "chunk_rows must be positive"}
    if {![string is integer -strict $maxMembers] || $maxMembers < 1} {error "max_members must be positive"}
    set prefix [dict get $defaults series_prefix]
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $prefix]} {error "invalid family series prefix"}
    set group [datasetVariableV3ById $datasetId $groupVariableId]
    set baseFilters [graphSeriesNormalizeFilters $datasetId [dict get $defaults row_filters]]
    set dtype [dict get $group dtype]
    set wanted {}
    foreach row [graphSeriesNormalizeRowOrdinals [dict get $defaults source_row_ordinals]] {dict set wanted $row 1}
    set selectedFamilies {}
    foreach requested [dict get $defaults family_values] {lappend selectedFamilies [graphSeriesCanonicalMember $dtype $requested]}
    foreach id [list $xVariableId $yVariableId] {datasetVariableById $datasetId $id}
    set labelId [dict get $defaults label_variable_id]
    set ids [list $groupVariableId]
    foreach filter $baseFilters {lappend ids [dict get $filter filter_variable_id]}
    if {$labelId ne ""} {datasetVariableById $datasetId $labelId; lappend ids $labelId}
    set categoryId [dict get $defaults category_variable_id]
    set behavior [dict get $defaults category_behavior]
    if {$behavior ni {Filter {Style category} {Split into series}}} {error "category_behavior must be Filter, Style category, or Split into series"}
    if {$categoryId eq "" && [llength [dict get $defaults category_values]]} {error "category_values require category_variable_id"}
    if {$categoryId ne ""} {
        set categoryVariable [datasetVariableV3ById $datasetId $categoryId]
        if {$categoryId eq $groupVariableId} {error "category variable must differ from the family variable"}
        lappend ids $categoryId
    }
    set selectedCategories {}
    if {$categoryId ne ""} {
        foreach requested [dict get $defaults category_values] {lappend selectedCategories [graphSeriesCanonicalMember [dict get $categoryVariable dtype] $requested]}
    }
    set stream [tableStreamOpenDataset $::GX::currentSession $datasetId $ids $chunkRows]
    set encountered {};set labels [dict create]
    try {
        while {1} {
            set chunk [tableStreamNext $stream]
            set members [dict get $chunk values $groupVariableId]
            if {$labelId ne ""} {set labelValues [dict get $chunk values $labelId]}
            if {$categoryId ne ""} {set categoryValues [dict get $chunk values $categoryId]}
            set count [dict get $chunk nrows]
            for {set i 0} {$i < $count} {incr i} {
                if {$wanted ne {} && ![dict exists $wanted [expr {[dict get $chunk offset]+$i}]]} continue
                set eligible 1
                foreach filter $baseFilters {
                    set value [lindex [dict get $chunk values [dict get $filter filter_variable_id]] $i]
                    if {![graphSeriesFilterRowMatch $filter $value]} {set eligible 0; break}
                }
                if {!$eligible} continue
                set member [graphSeriesCanonicalMember $dtype [lindex $members $i]]
                set category [expr {$categoryId eq "" ? "" : [graphSeriesCanonicalMember [dict get $categoryVariable dtype] [lindex $categoryValues $i]]}]
                if {[llength $selectedFamilies] && $member ni $selectedFamilies} continue
                if {$categoryId ne "" && [llength $selectedCategories] && $category ni $selectedCategories} continue
                set identity [list $member [expr {$behavior eq "Filter" ? "" : $category}]]
                if {![dict exists $labels $identity]} {
                    if {[llength $encountered] >= $maxMembers} {error "Graph Series family exceeds max_members=$maxMembers"}
                    lappend encountered $identity
                    dict set labels $identity [expr {$labelId eq "" ? $member : [lindex $labelValues $i]}]
                } elseif {$labelId ne "" && [dict get $labels $identity] ne [lindex $labelValues $i]} {
                    error "Graph Series family label changes within member $member / $category"
                }
            }
            if {$progress ne {}} {curveSourceCooperativeBoundary $progress [dict create stage group_rows completed_rows [expr {[dict get $chunk offset]+$count}] total_rows -1]}
            if {[dict get $chunk eof]} {break}
        }
    } finally {tableStreamClose $stream}
    if {![llength $encountered]} {error "Graph Series family has no members"}
    set order [dict get $defaults member_order]
    if {[llength $order]} {
        if {$categoryId ne "" && $behavior ne "Filter"} {error "member_order is available only without category splitting"}
        set requested {};foreach item $order {lappend requested [list [graphSeriesCanonicalMember $dtype $item] ""]}
        if {[llength [lsort -unique $requested]] != [llength $encountered] || [lsort $requested] ne [lsort $encountered]} {
            error "member_order must name every encountered member exactly once"
        }
        set encountered $requested
    }
    set records {};set nextOrder [llength [graphSeriesIds $moduleId $graphId $variantId]]
    set styleCategories {}
    if {$behavior eq "Style category"} {
        foreach identity $encountered {set category [lindex $identity 1];if {$category ni $styleCategories} {lappend styleCategories $category}}
    }
    set index 0
    foreach identity $encountered {
        lassign $identity member category
        set seriesId [format "%s_%04d" $prefix [incr index]]
        set key [graphSeriesKey $moduleId $graphId $seriesId $variantId]
        if {![dict get $defaults dry_run] && [info exists ::GX::graphSeries($key)]} {error "family series ID already exists: $seriesId"}
        set label [string map [list {{member}} $member {{label}} [dict get $labels $identity] {{category}} $category] [dict get $defaults label_template]]
        set filter [dict create filter_variable_id $groupVariableId predicate exact_equal value $member]
        set filters [concat $baseFilters [list $filter]]
        if {$categoryId ne ""} {
            if {$behavior eq "Filter"} {
                set selected [dict get $defaults category_values]
                if {[llength $selected] == 1} {lappend filters [dict create filter_variable_id $categoryId predicate exact_equal value [lindex $selected 0]]}
                if {[llength $selected] > 1} {lappend filters [dict create filter_variable_id $categoryId predicate in_set values $selected]}
            } else {
                lappend filters [dict create filter_variable_id $categoryId predicate exact_equal value $category]
            }
        }
        set fields [dict create dataset_id $datasetId x_variable_id $xVariableId y_variable_id $yVariableId family_variable_id $groupVariableId secondary_variable_id $categoryId ordering_variable_id [dict get $defaults ordering_variable_id] axis left enabled 1 order [incr nextOrder] label $label row_filters $filters]
        if {$wanted ne {}} {dict set fields source_row_ordinals [dict keys $wanted]}
        if {$behavior eq "Style category"} {
            set palette {#1f77b4 #ff7f0e #2ca02c #d62728 #9467bd #8c564b #e377c2 #7f7f7f #bcbd22 #17becf}
            set styles {solid dashed dotted dashdot}
            set categoryIndex [lsearch -exact $styleCategories $category]
            dict set fields style_color [lindex $palette [expr {$categoryIndex % [llength $palette]}]]
            dict set fields style_line_style [lindex $styles [expr {($categoryIndex / [llength $palette]) % [llength $styles]}]]
        }
        lappend records [list $seriesId [graphSeriesValidate $moduleId $graphId $seriesId $fields $variantId [expr {![dict get $defaults dry_run]}]] $member $category]
    }
    if {[dict get $defaults dry_run]} {
        set planned {}
        foreach record $records {lassign $record seriesId fields member category;lappend planned [dict merge $fields [dict create series_id $seriesId member_value $member category_value $category]]}
        return $planned
    }
    set created {}
    try {
        foreach record $records {
            lassign $record seriesId fields member category
            graphSeriesSet $moduleId $graphId $seriesId $fields $variantId
            lappend created $seriesId
        }
    } on error {reason opts} {
        foreach seriesId $created {graphSeriesRemove $moduleId $graphId $seriesId $variantId}
        return -options $opts $reason
    }
    set out {}
    foreach record $records {lassign $record seriesId fields member category;lappend out [dict create series_id $seriesId member_value $member category_value $category label [dict get $fields label]]}
    return $out
}

proc ::GX::manifestStringV2_before_level_scale {} {
    variable graphSeries
    set out [::GX::manifestStringV2_before_graph_series]
    set n 0
    foreach key [lsort [array names graphSeries]] {
        if {[llength [split $key ,]] == 4} { lassign [split $key ,] module graph variant series } else { lassign [split $key ,] module graph series; set variant "" }
        incr n
        append out "\n\[graph_series.$n\]\n"
        foreach {field value} [concat [list module_id $module graph_id $graph variant_id $variant series_id $series] $graphSeries($key)] { appendKV out $field $value }
    }
    append out "\n\[graph_series_api\]\n"; appendKV out version 1; appendKV out count $n
    return $out
}
proc ::GX::loadManifestV2_before_level_scale {path} {
    variable graphSeries
    array unset graphSeries *
    ::GX::loadManifestV2_before_graph_series $path
    set d [parseIni $path]
    set n [expr {[dict exists $d graph_series_api.count] ? [dict get $d graph_series_api.count] : 0}]
    if {![string is integer -strict $n] || $n < 0} { error "Invalid graph series count" }
    for {set i 1} {$i <= $n} {incr i} {
        set prefix "graph_series.$i."
        set fields [dict create]
        foreach field {module_id graph_id variant_id series_id dataset_id x_variable_id y_variable_id family_variable_id secondary_variable_id ordering_variable_id axis label enabled order alignment_mode manual_offset_seconds row_filters source_row_ordinals style_color style_line_style} {
            if {[dict exists $d $prefix$field]} { dict set fields $field [dict get $d $prefix$field] }
        }
        foreach key {module_id graph_id series_id} {
            if {![dict exists $fields $key]} { error "Incomplete graph series manifest" }
        }
        set module [dict get $fields module_id];set graph [dict get $fields graph_id];set series [dict get $fields series_id]
        set variant [expr {[dict exists $fields variant_id] ? [dict get $fields variant_id] : ""}]
        foreach key {module_id graph_id variant_id series_id} { catch {dict unset fields $key} }
        if {![dict exists $fields enabled]} { dict set fields enabled 1 }
        if {![dict exists $fields order]} { dict set fields order 0 }
        if {![dict exists $fields row_filters]} {dict set fields row_filters {}}
        if {![dict exists $fields style_color]} {dict set fields style_color ""}
        if {![dict exists $fields style_line_style]} {dict set fields style_line_style ""}
        # Resolve stable IDs when the session becomes available.
        set graphSeries([graphSeriesKey $module $graph $series $variant]) $fields
    }
}
proc ::GX::graphSeriesPreparationIdentity {datasetId} {
    set identity [list $datasetId]
    foreach field {format storage_provider path canonical_sha256 sha256 row_count variable_schema_api_version} {lappend identity $field [datasetField $datasetId $field ""]}
    set index 0
    foreach variable [datasetVariableSchemaV3 $datasetId] {
        incr index
        set variable [dict remove $variable display_label semantic_source semantic_reason]
        dict set variable storage_locator [datasetField $datasetId var${index}_storage_locator ""]
        lappend identity $variable
    }
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $identity]]
}
proc ::GX::writeStandardRuntimeConfig_before_level_scale {moduleId} {
    set path [::GX::writeStandardRuntimeConfig_before_graph_series $moduleId]
    set series {}
    foreach graph [moduleGraphIds $moduleId] {
        foreach item [graphSeriesList $moduleId $graph "" 1] { lappend series $item }
    }
    if {![llength $series]} { return $path }
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[graph_series\]"; putKV $fd api_version 1; putKV $fd count [llength $series]
    set i 0
    foreach item $series {
        incr i; puts $fd "\n\[graph_series.$i\]"
        putKV $fd scientific_dataset_identity [graphSeriesPreparationIdentity [dict get $item dataset_id]]
        putKV $fd dataset_row_count [datasetField [dict get $item dataset_id] row_count ""]
        foreach field {module_id graph_id variant_id series_id dataset_id path x_variable_id y_variable_id x_name y_name x_unit y_unit x_semantic_role y_semantic_role x_value_kind x_value_format x_decimal_separator y_value_kind y_value_format y_decimal_separator axis label enabled order time_reference time_origin x_time_reference x_time_origin y_time_reference y_time_origin alignment_mode manual_offset_seconds style_color style_line_style} {
            putKV $fd $field [dict get $item $field]
        }
        foreach field {family_variable_id secondary_variable_id ordering_variable_id} {
            putKV $fd $field [expr {[dict exists $item $field] ? [dict get $item $field] : ""}]
        }
        putKV $fd source_row_ordinals [datasetPublicationV2DictDefault $item source_row_ordinals {}]
        set filters [dict get $item row_filters]
        putKV $fd filter_count [llength $filters]
        set j 0
        foreach filter $filters {
            incr j
            dict for {field value} $filter {
                if {$field ne "values"} {putKV $fd "filter_${j}_$field" $value}
            }
            if {[dict exists $filter values]} {
                set values [dict get $filter values]
                putKV $fd "filter_${j}_value_count" [llength $values]
                set k 0
                foreach value $values {putKV $fd "filter_${j}_value_[incr k]" $value}
            }
        }
    }
    close $fd
    return $path
}

proc ::GX::defaults_before_level_scale {} {
    ::GX::defaults_before_graph_series
    array unset ::GX::graphSeries *
}
