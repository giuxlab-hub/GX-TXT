# Replicate Curve Analysis graphics integration API v1 (v15 implementation)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Uses the public Series Editor Extension API v1. Scientific Series identity
# remains CORE Graph Series state; this provider stores only presentation.

namespace eval ::GX::CurveRepGraphicsV1 {
    variable apiVersion 1
    variable moduleId curve.replicate_analysis
    variable editor
    array set editor {}
}

proc ::GX::CurveRepGraphicsV1::_statePath {} {
    if {$::GX::currentSession eq ""} { return "" }
    return [file join $::GX::currentSession analysis curve.replicate_analysis series_presentation.ini]
}

proc ::GX::CurveRepGraphicsV1::_scope {graphId variantId seriesId} {
    set raw "$graphId|$variantId|$seriesId"
    regsub -all {[^A-Za-z0-9_-]} $raw _ out
    return $out
}

proc ::GX::CurveRepGraphicsV1::_readState {} {
    set path [_statePath]
    if {$path eq "" || ![file isfile $path]} { return [dict create] }
    return [::GX::parseIni $path]
}

proc ::GX::CurveRepGraphicsV1::_stateGet {graphId variantId seriesId} {
    set all [_readState]
    set out [dict create kind inherit color "" line_style inherit line_width "" marker inherit marker_size "" marker_fill inherit opacity ""]
    # Variant presentation inherits the base Series presentation until that
    # exact variant receives an explicit provider-owned override.
    set sections {}
    if {$variantId ne ""} {lappend sections "series.[_scope $graphId "" $seriesId]"}
    lappend sections "series.[_scope $graphId $variantId $seriesId]"
    foreach sec $sections {
        dict for {field default} $out {
            set key "$sec.$field"
            if {[dict exists $all $key]} { dict set out $field [dict get $all $key] }
        }
    }
    return $out
}

proc ::GX::CurveRepGraphicsV1::_writeState {graphId variantId seriesId fields} {
    set path [_statePath]
    if {$path eq ""} { error "No Session is open." }
    file mkdir [file dirname $path]
    set all [_readState]
    set scope [_scope $graphId $variantId $seriesId]
    set sec "series.$scope"
    dict for {field value} $fields { dict set all "$sec.$field" $value }

    # Rebuild deterministically. This is provider-owned presentation state,
    # separate from CORE Graph Series persistence.
    set scopes {}
    dict for {key value} $all {
        if {[regexp {^series\.([^.]+)\.(.+)$} $key -> s f]} {
            if {$s ni $scopes} { lappend scopes $s }
        }
    }
    set tmp "$path.tmp"
    set fd [open $tmp w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "; curve.replicate_analysis per-Series presentation"
        puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
        foreach s [lsort -dictionary $scopes] {
            puts $fd "\n\[series.$s\]"
            foreach field {kind color line_style line_width marker marker_size marker_fill opacity} {
                set key "series.$s.$field"
                set v [expr {[dict exists $all $key] ? [dict get $all $key] : ""}]
                ::GX::putKV $fd $field $v
            }
        }
    } finally { close $fd }
    file rename -force -- $tmp $path
    return $fields
}

proc ::GX::CurveRepGraphicsV1::_defaultSeries {graphId} {
    switch -- $graphId {
        curve.replicate.overlay {
            return [list [list replicate_traces [dict create \
                dataset_id curve.replicate.traces x_variable_id x y_variable_id y \
                family_variable_id trace_index secondary_variable_id family_value \
                axis left label "Replicate traces" enabled 1 order 1]]]
        }
        curve.replicate.consensus_uncertainty {
            return [list [list consensus [dict create \
                dataset_id curve.replicate.profiles x_variable_id x y_variable_id mean \
                family_variable_id family_value \
                axis left label "Consensus" enabled 1 order 1]]]
        }
        curve.replicate.uncertainty_components {
            return [list \
                [list within [dict create dataset_id curve.replicate.profiles x_variable_id x y_variable_id sigma_within family_variable_id family_value axis left label "Within-source" enabled 1 order 1]] \
                [list between [dict create dataset_id curve.replicate.profiles x_variable_id x y_variable_id sigma_between family_variable_id family_value axis left label "Between-source" enabled 1 order 2]] \
                [list total [dict create dataset_id curve.replicate.profiles x_variable_id x y_variable_id sigma_total family_variable_id family_value axis left label "Total" enabled 1 order 3]]]
        }
        curve.replicate.family_summary {
            return [list \
                [list within [dict create dataset_id curve.replicate.family_summary x_variable_id x_within y_variable_id within_rms axis left label "Within-source" enabled 1 order 1]] \
                [list between [dict create dataset_id curve.replicate.family_summary x_variable_id x_between y_variable_id between_rms axis left label "Between-source" enabled 1 order 2]] \
                [list total [dict create dataset_id curve.replicate.family_summary x_variable_id x_total y_variable_id total_rms axis left label "Total" enabled 1 order 3]]]
        }
    }
    return {}
}

proc ::GX::CurveRepGraphicsV1::ensureSeries {graphId {variantId ""}} {
    variable moduleId
    if {$::GX::currentSession eq ""} { return }
    catch {::GX::loadDatasetRegistry $::GX::currentSession}
    if {[llength [::GX::graphSeriesIds $moduleId $graphId $variantId]]} { return }

    # Plot Module variants normally copy Series automatically. If a historical
    # or partially migrated Session lacks them, copy the current base Series.
    if {$variantId ne "" && [llength [::GX::graphSeriesIds $moduleId $graphId ""]]} {
        foreach sid [::GX::graphSeriesIds $moduleId $graphId ""] {
            set fields [::GX::graphSeriesSnapshot $moduleId $graphId $sid ""]
            foreach k {module_id graph_id variant_id series_id} { catch {dict unset fields $k} }
            ::GX::graphSeriesSet $moduleId $graphId $sid $fields $variantId
        }
        return
    }

    foreach item [_defaultSeries $graphId] {
        lassign $item sid fields
        set ds [dict get $fields dataset_id]
        if {[::GX::datasetField $ds id ""] eq ""} { continue }
        ::GX::graphSeriesSet $moduleId $graphId $sid $fields $variantId
    }
}

proc ::GX::CurveRepGraphicsV1::seriesBuild {context} {
    variable editor
    set parent [dict get $context parent]
    set graphId [dict get $context graph_id]
    set variantId [dict get $context variant_id]
    ensureSeries $graphId $variantId

    foreach {field label values} {
        kind {Representation} {inherit line scatter line_marker step bar}
        color {Color} {}
        line_style {Line style} {inherit auto solid dashed dotted dashdot none}
        line_width {Line width (blank = Graphics)} {}
        marker {Marker} {inherit auto none circle square diamond triangle_up triangle_down plus x star}
        marker_size {Marker size (blank = graph default)} {}
        marker_fill {Marker fill} {inherit auto none full}
        opacity {Opacity} {}
    } {
        ttk::label $parent.l_$field -text $label
        if {[llength $values]} {
            ttk::combobox $parent.e_$field -state readonly -values $values \
                -textvariable ::GX::CurveRepGraphicsV1::editor($parent,$field) -width 20
        } else {
            ttk::entry $parent.e_$field -textvariable ::GX::CurveRepGraphicsV1::editor($parent,$field) -width 22
        }
        set row [llength [grid slaves $parent]]
        grid $parent.l_$field -row $row -column 0 -sticky e -padx 4 -pady 2
        grid $parent.e_$field -row $row -column 1 -sticky ew -padx 4 -pady 2
    }
    grid columnconfigure $parent 1 -weight 1
}

proc ::GX::CurveRepGraphicsV1::seriesLoad {context} {
    variable editor
    set parent [dict get $context parent]
    set sid [dict get $context series_id]
    if {$sid eq ""} {
        set state [dict create kind inherit color "" line_style inherit line_width "" marker inherit marker_size "" marker_fill inherit opacity ""]
    } else {
        set state [_stateGet [dict get $context graph_id] [dict get $context variant_id] $sid]
    }
    dict for {field value} $state { set editor($parent,$field) $value }
}

proc ::GX::CurveRepGraphicsV1::seriesValidate {context} {
    variable editor
    set parent [dict get $context parent]
    set kind $editor($parent,kind)
    if {$kind ni {inherit line scatter line_marker step bar}} { error "Unsupported representation '$kind'." }
    set ls $editor($parent,line_style)
    if {$ls ni {inherit auto solid dashed dotted dashdot none}} { error "Unsupported line style '$ls'." }
    set marker $editor($parent,marker)
    if {$marker ni {inherit auto none circle square diamond triangle_up triangle_down plus x star}} { error "Unsupported marker '$marker'." }
    set fill $editor($parent,marker_fill)
    if {$fill ni {inherit auto none full}} { error "Unsupported marker fill '$fill'." }
    set color [string trim $editor($parent,color)]
    if {$color ne "" && $color ne "auto" && ![regexp {^#[0-9A-Fa-f]{6}$} $color]} { error "Color must be blank, auto, or #RRGGBB." }
    foreach field {line_width marker_size} {
        set v [string trim $editor($parent,$field)]
        if {$v ne "" && (![string is double -strict $v] || $v <= 0)} { error "$field must be blank or a positive number." }
    }
    set opacity [string trim $editor($parent,opacity)]
    if {$opacity ne "" && (![string is double -strict $opacity] || $opacity < 0 || $opacity > 1)} { error "Opacity must be blank or between 0 and 1." }
    return [dict create kind $kind color $color line_style $ls \
        line_width [string trim $editor($parent,line_width)] marker $marker \
        marker_size [string trim $editor($parent,marker_size)] marker_fill $fill opacity $opacity]
}

proc ::GX::CurveRepGraphicsV1::seriesSave {context validated} {
    set sid [dict get $context series_id]
    if {$sid eq ""} { return }
    _writeState [dict get $context graph_id] [dict get $context variant_id] $sid $validated
}

proc ::GX::CurveRepGraphicsV1::seriesClose {context} {
    variable editor
    set parent [dict get $context parent]
    foreach key [array names editor "$parent,*"] { unset editor($key) }
}

proc ::GX::CurveRepGraphicsV1::seriesTableValues {context} {
    set sid [dict get $context series_id]
    if {$sid eq ""} { return [dict create kind ""] }
    set state [_stateGet [dict get $context graph_id] [dict get $context variant_id] $sid]
    return [dict create kind [dict get $state kind]]
}

proc ::GX::CurveRepGraphicsV1::activate {} {
    variable moduleId
    if {![llength [info commands ::GX::seriesEditorExtensionRegister]]} {
        error "Series Editor Extension API v1 is unavailable."
    }
    set provider curve.replicate_analysis.series_presentation
    catch {::GX::seriesEditorExtensionUnregister $provider}
    ::GX::seriesEditorExtensionRegister $provider [dict create \
        module_id $moduleId \
        graph_ids {curve.replicate.overlay;curve.replicate.consensus_uncertainty;curve.replicate.uncertainty_components;curve.replicate.family_summary} \
        build_proc ::GX::CurveRepGraphicsV1::seriesBuild \
        load_proc ::GX::CurveRepGraphicsV1::seriesLoad \
        validate_proc ::GX::CurveRepGraphicsV1::seriesValidate \
        save_proc ::GX::CurveRepGraphicsV1::seriesSave \
        close_proc ::GX::CurveRepGraphicsV1::seriesClose \
        table_columns [list [dict create id kind heading Kind width 95]] \
        table_values_proc ::GX::CurveRepGraphicsV1::seriesTableValues]
    return 1
}

::GX::CurveRepGraphicsV1::activate
