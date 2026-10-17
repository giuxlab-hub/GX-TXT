# GX-TXT CORE Graph Selection API v1.
# Publish selected source rows through the ordinary Dataset publication path.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::GraphSelectionAPIv1 {}

proc ::GX::GraphSelectionAPIv1::publishMembers {session members requestedId {metadata {}}} {
    if {[string trim $requestedId] eq ""} {error "Enter an output Dataset ID"}
    set requestedId [::GX::datasetPublicationV2RequestedId $requestedId]
    set manifest [dict create api_version 1 operation combine_selection sources $members output [dict create dataset_id $requestedId contract auto storage auto] options [dict create metadata $metadata] schema_policy {} metadata_policy explicit]
    return [::GX::datasetTransformExecute $session $manifest]
}

proc ::GX::GraphSelectionAPIv1::_field {dictionary key default} {
    if {[dict exists $dictionary $key]} { return [dict get $dictionary $key] }
    return $default
}

proc ::GX::GraphSelectionAPIv1::_number {value} {
    if {![string is double -strict $value]} { return "" }
    if {[catch {set number [expr {double($value)}]}]} { return "" }
    if {[expr {abs($number) == Inf || $number != $number}]} { return "" }
    return $number
}

proc ::GX::GraphSelectionAPIv1::_matchesFilter {value filter} {
    set predicate [dict get $filter predicate]
    set dtype [_field $filter dtype float64]
    if {$dtype ne "string"} {
        # Typed canonicalization preserves int64/uint64 identities above 2^53.
        if {[catch {set value [::GX::graphSeriesCanonicalMember $dtype $value]}]} {return [expr {$predicate eq "is_nonfinite"}]}
    }
    switch -- $predicate {
        is_finite { return 1 }
        is_nonfinite { return 0 }
        exact_equal {
            if {$dtype eq "string"} { return [expr {$value eq [dict get $filter value]}] }
            return [expr {$value == [dict get $filter value]}]
        }
        not_equal {
            if {$dtype eq "string"} { return [expr {$value ne [dict get $filter value]}] }
            return [expr {$value != [dict get $filter value]}]
        }
        less_than { return [expr {$value < [dict get $filter value]}] }
        less_equal { return [expr {$value <= [dict get $filter value]}] }
        greater_than { return [expr {$value > [dict get $filter value]}] }
        greater_equal { return [expr {$value >= [dict get $filter value]}] }
        between_inclusive { return [expr {$value >= [dict get $filter lower] && $value <= [dict get $filter upper]}] }
        in_set {
            foreach candidate [dict get $filter values] {
                if {$dtype eq "string" && $value eq $candidate} { return 1 }
                if {$dtype ne "string" && $value == $candidate} { return 1 }
            }
            return 0
        }
        default { error "Unsupported Graph Series row filter: $predicate" }
    }
}

# Region membership scans complete canonical rows. The rendered point index
# cannot be used here because its display reducer may omit valid source rows.
proc ::GX::GraphSelectionAPIv1::selectRegionRows {session datasetId xId yId filters bounds} {
    foreach field {x_min x_max} {
        if {![dict exists $bounds $field] || [_number [dict get $bounds $field]] eq ""} {
            error "Graph selection needs a finite $field bound."
        }
    }
    set rectangle [expr {[dict exists $bounds y_min] && [dict exists $bounds y_max]}]
    if {$rectangle} {
        foreach field {y_min y_max} {
            if {[_number [dict get $bounds $field]] eq ""} { error "Graph selection needs a finite $field bound." }
        }
    }
    set ids [list $xId $yId]
    foreach filter $filters { lappend ids [dict get $filter filter_variable_id] }
    set ids [lsort -unique $ids]
    set stream [::GX::tableStreamOpenDataset $session $datasetId $ids 4096]
    set selected {}
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]
            set n [dict get $chunk nrows]
            set values [dict get $chunk values]
            set xColumn [dict get $values $xId]
            set yColumn [dict get $values $yId]
            for {set i 0} {$i < $n} {incr i} {
                set x [_number [lindex $xColumn $i]]
                set y [_number [lindex $yColumn $i]]
                if {$x eq "" || $y eq ""} continue
                if {$x < [dict get $bounds x_min] || $x > [dict get $bounds x_max]} continue
                if {$rectangle && ($y < [dict get $bounds y_min] || $y > [dict get $bounds y_max])} continue
                set accepted 1
                foreach filter $filters {
                    set value [lindex [dict get $values [dict get $filter filter_variable_id]] $i]
                    if {![_matchesFilter $value $filter]} { set accepted 0; break }
                }
                if {$accepted} { lappend selected [expr {[dict get $chunk offset]+$i}] }
            }
            if {[dict get $chunk eof]} break
        }
    } finally {
        ::GX::tableStreamClose $stream
    }
    return $selected
}

proc ::GX::GraphSelectionAPIv1::publishRows {session sourceId rowNumbers operation resultId provenance} {
    if {$operation ni {keep exclude}} {error "Graph selection operation must be keep or exclude"}
    if {![llength $rowNumbers]} {error "Select at least one source row first"}
    if {[string trim $resultId] eq ""} {error "Enter an output Dataset ID"}
    set source [dict create dataset_id $sourceId rows $rowNumbers row_operation $operation]
    set metadata [dict create selection.producer core.graph_selection selection.operation $operation selection.source_dataset_id $sourceId selection.provenance $provenance]
    set manifest [dict create api_version 1 operation subset_rows sources [list $source] output [dict create dataset_id [::GX::datasetPublicationV2RequestedId $resultId] contract table.generic storage auto] options [dict create metadata $metadata] schema_policy {} metadata_policy explicit]
    return [::GX::datasetTransformExecute $session $manifest]
}
