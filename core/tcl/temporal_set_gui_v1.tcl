# GX-TXT Temporal Set editor GUI v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Dataset-scoped Variables-workspace editor for the existing Temporal Set API v1.
# The editor does not introduce a second temporal model or persistence layer.

namespace eval ::GX {
    variable temporalSetGuiActive 0
    variable temporalSetGuiDataset ""
    variable temporalSetGuiEditingId ""
    variable temporalSetGuiEditingType ""
    variable temporalSetGuiVarDisplay ""
    variable temporalSetGuiParentDisplay "All dataset"
    variable temporalSetGuiBasis "Samples"
    variable temporalSetGuiLabel ""
    variable temporalSetGuiWindowSize ""
    variable temporalSetGuiStep ""
    variable temporalSetGuiPartial "Drop"
    variable temporalSetGuiDurationUnit "s"
    variable temporalSetGuiDurationUnitPrevious "s"
    variable temporalSetGuiSegmentUnit "s"
    variable temporalSetGuiSegmentUnitPrevious "s"
    variable temporalSetGuiSegmentLabel ""
    variable temporalSetGuiSegmentStart ""
    variable temporalSetGuiSegmentEnd ""
    variable temporalSetGuiSegments {}
    variable temporalSetGuiVariableMap
    variable temporalSetGuiParentMap
    array set temporalSetGuiVariableMap {}
    array set temporalSetGuiParentMap {}
}

proc ::GX::temporalSetGuiCurrentDataset {} {
    variable variableDatasetChoice
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode id
    if {$mode ne "imported" || $id eq ""} {
        error "Temporal Sets require an imported canonical Dataset."
    }
    return $id
}

proc ::GX::temporalSetGuiTemporalCompatibility {variable} {
    foreach field {enabled rank semantic_role value_kind value_format unit time_reference} {
        if {![dict exists $variable $field]} { dict set variable $field "" }
    }
    if {![dict get $variable enabled]} { return [dict create compatible 0 reason "Variable is disabled."] }
    if {[dict get $variable rank] ne "1"} { return [dict create compatible 0 reason "Temporal variables must be one-dimensional."] }
    set role [dict get $variable semantic_role]
    if {$role ne "elapsed_time" && !($role eq "independent" && [dict get $variable time_reference] eq "elapsed")} {
        return [dict create compatible 0 reason "Semantic role must be elapsed_time, or independent with an elapsed time reference."]
    }
    if {[dict get $variable value_kind] ni {number elapsed_time}} {
        return [dict create compatible 0 reason "Elapsed-time semantics require a numeric or elapsed_time value representation."]
    }
    if {[dict get $variable time_reference] ne "" && [dict get $variable time_reference] ne "elapsed"} {
        return [dict create compatible 0 reason "Elapsed-time semantics require an elapsed time reference."]
    }
    if {[catch {set numericUnit [temporalSetNumericUnitForVariable $variable]} err]} {
        return [dict create compatible 0 reason $err]
    }
    if {$numericUnit eq "" || ![unitTclCompatible $numericUnit s]} {
        return [dict create compatible 0 reason "Variable unit is not compatible with elapsed time."]
    }
    return [dict create compatible 1 reason "" numeric_unit $numericUnit]
}

proc ::GX::temporalSetGuiEligibleVariables {datasetId} {
    set out {}
    foreach variable [datasetVariableSchemaV3 $datasetId] {
        set compatibility [temporalSetGuiTemporalCompatibility $variable]
        if {[dict get $compatibility compatible]} { lappend out $variable }
    }
    return $out
}

proc ::GX::temporalSetGuiVariableLabel {variable} {
    set label [string trim [dict get $variable display_label]]
    if {$label eq ""} { set label "Elapsed Time" }
    set name [dict get $variable canonical]
    set numericUnit [temporalSetNumericUnitForVariable $variable]
    return "$label — $name — \[$numericUnit\]"
}

proc ::GX::temporalSetGuiRefreshVariableChoices {datasetId {currentId ""}} {
    variable temporalSetGuiVariableMap
    variable temporalSetGuiVarDisplay
    array unset temporalSetGuiVariableMap *
    set choices {}
    foreach variable [temporalSetGuiEligibleVariables $datasetId] {
        set display [temporalSetGuiVariableLabel $variable]
        # Keep labels unique without changing the stable persisted identity.
        if {[info exists temporalSetGuiVariableMap($display)]} {
            append display " — [dict get $variable variable_id]"
        }
        set temporalSetGuiVariableMap($display) [dict get $variable variable_id]
        lappend choices $display
        if {[dict get $variable variable_id] eq $currentId} { set temporalSetGuiVarDisplay $display }
    }
    if {$currentId ne "" && $temporalSetGuiVarDisplay eq ""} {
        if {![catch {set variable [datasetVariableV3ById $datasetId $currentId]}]} {
            set display "Incompatible — [dict get $variable canonical] — $currentId"
        } else {
            set display "Missing temporal variable — $currentId"
        }
        set temporalSetGuiVariableMap($display) $currentId
        lappend choices $display
        set temporalSetGuiVarDisplay $display
    }
    if {$temporalSetGuiVarDisplay eq "" && [llength $choices]} { set temporalSetGuiVarDisplay [lindex $choices 0] }
    return $choices
}

proc ::GX::temporalSetGuiSelectedVariableId {} {
    variable temporalSetGuiVariableMap
    variable temporalSetGuiVarDisplay
    if {$temporalSetGuiVarDisplay eq "" || ![info exists temporalSetGuiVariableMap($temporalSetGuiVarDisplay)]} { return "" }
    return $temporalSetGuiVariableMap($temporalSetGuiVarDisplay)
}

proc ::GX::temporalSetGuiDurationUnits {} {
    set out {}
    foreach unit [unitRegistryList] {
        if {![catch {elapsedTimeRequestedUnit $unit}]} { lappend out $unit }
    }
    return [lsort -dictionary -unique $out]
}

proc ::GX::temporalSetGuiConvertDuration {value fromUnit toUnit} {
    if {$value eq ""} { return "" }
    if {![string is double -strict $value]} { error "Duration value '$value' is not numeric." }
    set converted [temporalUnitConvertLinear $value $fromUnit $toUnit]
    return [format %.15g $converted]
}

proc ::GX::temporalSetGuiSelectionLabel {id} {
    if {$id eq ""} { return "All dataset" }
    set xmin [datasetSelectionField $id x_min ""]
    set xmax [datasetSelectionField $id x_max ""]
    set unit [datasetSelectionField $id x_unit ""]
    set suffix ""
    if {$xmin ne "" && $xmax ne ""} { set suffix " — $xmin … $xmax${unit}" }
    return "$id$suffix"
}

proc ::GX::temporalSetGuiRefreshParentChoices {datasetId variableId {currentId ""}} {
    variable currentSession
    variable temporalSetGuiParentMap
    variable temporalSetGuiParentDisplay
    array unset temporalSetGuiParentMap *
    set allDataset "All dataset"
    set choices [list $allDataset]
    set temporalSetGuiParentMap($allDataset) ""
    if {$currentSession ne "" && [file isdirectory $currentSession]} { datasetSelectionLoadRegistry $currentSession }
    set variableName ""
    set axisUnit ""
    if {$variableId ne "" && ![catch {set variable [datasetVariableV3ById $datasetId $variableId]}]} {
        set variableName [dict get $variable canonical]
        set axisUnit [temporalSetNumericUnitForVariable $variable]
    }
    foreach id [datasetSelectionIds] {
        if {[datasetSelectionField $id type ""] ne "x_range"} continue
        if {[datasetSelectionField $id source_dataset_id ""] ne $datasetId} continue
        if {[datasetSelectionField $id x_coordinate_space source] ne "source"} continue
        set sid [datasetSelectionField $id x_variable_id ""]
        if {$sid ne ""} {
            if {$sid ne $variableId} continue
        } elseif {[datasetSelectionField $id x_variable ""] ne $variableName} {
            continue
        }
        set selectionUnit [datasetSelectionField $id x_unit $axisUnit]
        if {$selectionUnit ne "" && $axisUnit ne "" && [catch {temporalUnitConvertLinear 1 $selectionUnit $axisUnit}]} continue
        set display [temporalSetGuiSelectionLabel $id]
        set temporalSetGuiParentMap($display) $id
        lappend choices $display
        if {$id eq $currentId} { set temporalSetGuiParentDisplay $display }
    }
    if {$currentId ne "" && $temporalSetGuiParentDisplay eq "All dataset"} {
        set display "Missing or incompatible Selection — $currentId"
        set temporalSetGuiParentMap($display) $currentId
        lappend choices $display
        set temporalSetGuiParentDisplay $display
    }
    if {$currentId eq ""} { set temporalSetGuiParentDisplay "All dataset" }
    return $choices
}

proc ::GX::temporalSetGuiSelectedParentId {} {
    variable temporalSetGuiParentMap
    variable temporalSetGuiParentDisplay
    if {$temporalSetGuiParentDisplay eq "All dataset"} { return "" }
    if {![info exists temporalSetGuiParentMap($temporalSetGuiParentDisplay)]} { return "" }
    return $temporalSetGuiParentMap($temporalSetGuiParentDisplay)
}

proc ::GX::temporalSetGuiParentChanged {} {
    # No derived state is cached here. The Temporal Set API validates the
    # authoritative Selection when the definition is saved/resolved.
}

proc ::GX::temporalSetGuiVariableChanged {} {
    variable temporalSetGuiDataset
    variable temporalSetGuiParentDisplay
    set temporalSetGuiParentDisplay "All dataset"
    set variableId [temporalSetGuiSelectedVariableId]
    set choices [temporalSetGuiRefreshParentChoices $temporalSetGuiDataset $variableId ""]
    if {[winfo exists .top.nb.channels.temporal.body.editor.parent]} {
        .top.nb.channels.temporal.body.editor.parent configure -values $choices
    }
}

proc ::GX::temporalSetGuiWindowBasisChanged {} {
    variable temporalSetGuiBasis
    set f .top.nb.channels.temporal.body.editor
    if {![winfo exists $f]} return
    set duration [expr {$temporalSetGuiBasis eq "Duration"}]
    $f.durationUnit configure -state [expr {$duration ? "readonly" : "disabled"}]
}

proc ::GX::temporalSetGuiDurationUnitChanged {} {
    variable temporalSetGuiDurationUnit
    variable temporalSetGuiDurationUnitPrevious
    variable temporalSetGuiWindowSize
    variable temporalSetGuiStep
    set old $temporalSetGuiDurationUnitPrevious
    set new $temporalSetGuiDurationUnit
    if {$old ne "" && $new ne "" && $old ne $new} {
        if {$temporalSetGuiWindowSize ne ""} { set temporalSetGuiWindowSize [temporalSetGuiConvertDuration $temporalSetGuiWindowSize $old $new] }
        if {$temporalSetGuiStep ne ""} { set temporalSetGuiStep [temporalSetGuiConvertDuration $temporalSetGuiStep $old $new] }
    }
    set temporalSetGuiDurationUnitPrevious $new
}

proc ::GX::temporalSetGuiSegmentUnitChanged {} {
    variable temporalSetGuiSegmentUnit
    variable temporalSetGuiSegmentUnitPrevious
    variable temporalSetGuiSegments
    variable temporalSetGuiSegmentStart
    variable temporalSetGuiSegmentEnd
    set old $temporalSetGuiSegmentUnitPrevious
    set new $temporalSetGuiSegmentUnit
    if {$old ne "" && $new ne "" && $old ne $new} {
        set converted {}
        foreach segment $temporalSetGuiSegments {
            dict set segment start [temporalSetGuiConvertDuration [dict get $segment start] $old $new]
            dict set segment end [temporalSetGuiConvertDuration [dict get $segment end] $old $new]
            lappend converted $segment
        }
        set temporalSetGuiSegments $converted
        if {$temporalSetGuiSegmentStart ne ""} { set temporalSetGuiSegmentStart [temporalSetGuiConvertDuration $temporalSetGuiSegmentStart $old $new] }
        if {$temporalSetGuiSegmentEnd ne ""} { set temporalSetGuiSegmentEnd [temporalSetGuiConvertDuration $temporalSetGuiSegmentEnd $old $new] }
    }
    set temporalSetGuiSegmentUnitPrevious $new
    temporalSetGuiRenderSegments
}

proc ::GX::temporalSetGuiSetStatus {message} {
    catch {setStatus $message 100}
}

proc ::GX::temporalSetGuiError {message} {
    tk_messageBox -icon error -type ok -title "Temporal Sets" -message $message
    return 0
}

proc ::GX::temporalSetGuiOpen {} {
    variable temporalSetGuiActive
    variable temporalSetGuiDataset
    if {[catch {set datasetId [temporalSetGuiCurrentDataset]} err]} { return [temporalSetGuiError $err] }
    set temporalSetGuiActive 1
    set f .top.nb.channels
    if {[winfo exists $f.temporal]} {$f.views select $f.views.temporal;return 1}
    datasetPageEditorBegin temporal $datasetId
    set temporalSetGuiDataset $datasetId
    pack forget $f.temporalSets
    ttk::frame $f.temporal
    pack $f.temporal -in $f.views.temporal -fill both -expand 1
    raise $f.temporal
    $f.views select $f.views.temporal
    grid columnconfigure $f.temporal 0 -weight 1
    grid rowconfigure $f.temporal 1 -weight 1
    ttk::frame $f.temporal.header
    ttk::button $f.temporal.header.back -text "Back to Temporal Sets" -command ::GX::temporalSetGuiBack
    ttk::label $f.temporal.header.title -text "Temporal Sets — Dataset: $datasetId"
    pack $f.temporal.header.back -side left -padx {0 12}
    pack $f.temporal.header.title -side left
    grid $f.temporal.header -row 0 -column 0 -sticky ew -pady {0 6}
    ttk::frame $f.temporal.body
    grid $f.temporal.body -row 1 -column 0 -sticky nsew
    grid columnconfigure $f.temporal.body 0 -weight 1
    grid rowconfigure $f.temporal.body 0 -weight 1
    temporalSetGuiShowList
    return 1
}

proc ::GX::temporalSetGuiBack {} {
    variable temporalSetGuiActive
    set temporalSetGuiActive 0
    datasetPageEditorEnd temporal
    refreshNativeVariablesGui
}

proc ::GX::temporalSetGuiShowList {} {
    variable temporalSetGuiDataset
    set body .top.nb.channels.temporal.body
    if {![winfo exists $body]} return
    destroyChildren $body
    ttk::frame $body.list
    grid $body.list -row 0 -column 0 -sticky nsew
    grid columnconfigure $body.list 0 -weight 1
    grid rowconfigure $body.list 1 -weight 1

    ttk::frame $body.list.actions
    foreach {name text command} {
        newWindow "New Window Set..." ::GX::temporalSetGuiNewWindow
        newSegment "New Segment Set..." ::GX::temporalSetGuiNewSegment
        edit "Edit..." ::GX::temporalSetGuiEditSelected
        delete "Delete" ::GX::temporalSetGuiDeleteSelected
        refresh "Refresh" ::GX::temporalSetGuiShowList
    } {
        ttk::button $body.list.actions.$name -text $text -command $command
        pack $body.list.actions.$name -side left -padx 4
    }
    grid $body.list.actions -row 0 -column 0 -sticky w -pady {0 5}

    ttk::treeview $body.list.tree -columns {id label type temporal basis} -show headings -selectmode browse -height 10
    foreach {col text width} {id ID 90 label Label 250 type Type 110 temporal {Temporal variable} 190 basis Basis 100} {
        $body.list.tree heading $col -text $text
        $body.list.tree column $col -width $width -stretch [expr {$col eq "label" || $col eq "temporal"}]
    }
    ttk::scrollbar $body.list.sy -orient vertical -command [list $body.list.tree yview]
    $body.list.tree configure -yscrollcommand [list $body.list.sy set]
    grid $body.list.tree -row 1 -column 0 -sticky nsew
    grid $body.list.sy -row 1 -column 1 -sticky ns
    bind $body.list.tree <<TreeviewSelect>> ::GX::temporalSetGuiUpdatePreview

    ttk::labelframe $body.list.preview -text "Resolution summary"
    ttk::label $body.list.preview.text -textvariable ::GX::temporalSetGuiPreviewText -justify left -anchor nw -wraplength 1050
    pack $body.list.preview.text -fill both -expand 1 -padx 8 -pady 6
    grid $body.list.preview -row 2 -column 0 -columnspan 2 -sticky ew -pady {7 0}

    temporalSetGuiPopulateList
}

proc ::GX::temporalSetGuiPopulateList {} {
    variable currentSession
    variable temporalSetGuiDataset
    variable temporalSetGuiPreviewText
    set tree .top.nb.channels.temporal.body.list.tree
    if {![winfo exists $tree]} return
    foreach iid [$tree children {}] { $tree delete $iid }
    set temporalSetGuiPreviewText "Select a Temporal Set to inspect its resolved definition."
    if {$currentSession ne "" && [file isdirectory $currentSession]} { temporalSetLoadRegistry $currentSession }
    foreach definition [temporalSetList $temporalSetGuiDataset] {
        set id [dict get $definition id]
        set variableId [dict get $definition temporal_variable_id]
        set variableName $variableId
        catch { set variableName [dict get [datasetVariableV3ById $temporalSetGuiDataset $variableId] canonical] }
        set type [dict get $definition type]
        set basis [expr {$type eq "window_set" ? [dict get $definition generator_basis] : "segments"}]
        $tree insert {} end -id $id -values [list $id [dict get $definition label] $type $variableName $basis]
    }
}

proc ::GX::temporalSetGuiSelectedSetId {} {
    set tree .top.nb.channels.temporal.body.list.tree
    if {![winfo exists $tree]} { return "" }
    set selection [$tree selection]
    return [expr {[llength $selection] ? [lindex $selection 0] : ""}]
}

proc ::GX::temporalSetGuiUpdatePreview {} {
    variable temporalSetGuiPreviewText
    set id [temporalSetGuiSelectedSetId]
    if {$id eq ""} { set temporalSetGuiPreviewText "Select a Temporal Set to inspect its resolved definition."; return }
    if {[catch {set info [temporalSetResolveInfo $id]} err]} {
        set temporalSetGuiPreviewText "Cannot resolve $id:\n$err"
        return
    }
    set parent [dict get $info parent_selection_id]
    set parentText [expr {$parent eq "" ? "All dataset" : $parent}]
    set lines [list \
        "ID: [dict get $info id]" \
        "Type: [dict get $info type]" \
        "Temporal variable: [dict get $info temporal_variable] ([dict get $info temporal_variable_id])" \
        "Temporal unit: [dict get $info temporal_unit]" \
        "Source rows: [dict get $info axis_count]" \
        "Effective rows: [dict get $info effective_row_count]" \
        "Resolved members: [dict get $info member_count]" \
        "Parent: $parentText"]
    if {[dict get $info type] eq "window_set"} {
        set widthRows [dict get $info resolved_window_rows]
        set stepRows [dict get $info resolved_step_rows]
        set overlap [expr {$widthRows > 0 && $stepRows < $widthRows ? 100.0*(1.0-double($stepRows)/double($widthRows)) : 0.0}]
        lappend lines "Basis: [dict get $info generator_basis]"
        if {[dict get $info generator_basis] eq "samples"} {
            lappend lines "Window size: $widthRows samples" "Step: $stepRows samples"
        } else {
            lappend lines "Window size: [dict get $info window_size] [dict get $info duration_unit]" "Step: [dict get $info step] [dict get $info duration_unit]"
        }
        lappend lines "Overlap: [format %.3g $overlap] %" "Partial policy: [dict get $info partial_policy]"
    }
    set temporalSetGuiPreviewText [join $lines "\n"]
}

proc ::GX::temporalSetGuiNewWindow {} { temporalSetGuiEdit window_set "" }
proc ::GX::temporalSetGuiNewSegment {} { temporalSetGuiEdit segment_set "" }

proc ::GX::temporalSetGuiEditSelected {} {
    set id [temporalSetGuiSelectedSetId]
    if {$id eq ""} { return [temporalSetGuiError "Select a Temporal Set to edit."] }
    if {[catch {set definition [temporalSetRead $id]} err]} { return [temporalSetGuiError $err] }
    temporalSetGuiEdit [dict get $definition type] $id
}

proc ::GX::temporalSetGuiEditorReset {} {
    variable temporalSetGuiEditingId ""
    variable temporalSetGuiEditingType ""
    variable temporalSetGuiVarDisplay ""
    variable temporalSetGuiParentDisplay "All dataset"
    variable temporalSetGuiBasis "Samples"
    variable temporalSetGuiLabel ""
    variable temporalSetGuiWindowSize ""
    variable temporalSetGuiStep ""
    variable temporalSetGuiPartial "Drop"
    variable temporalSetGuiDurationUnit "s"
    variable temporalSetGuiDurationUnitPrevious "s"
    variable temporalSetGuiSegmentUnit "s"
    variable temporalSetGuiSegmentUnitPrevious "s"
    variable temporalSetGuiSegmentLabel ""
    variable temporalSetGuiSegmentStart ""
    variable temporalSetGuiSegmentEnd ""
    variable temporalSetGuiSegments {}
}

proc ::GX::temporalSetGuiEdit {type {id ""}} {
    variable temporalSetGuiDataset
    variable temporalSetGuiEditingId
    variable temporalSetGuiEditingType
    variable temporalSetGuiVarDisplay
    variable temporalSetGuiParentDisplay
    variable temporalSetGuiBasis
    variable temporalSetGuiLabel
    variable temporalSetGuiWindowSize
    variable temporalSetGuiStep
    variable temporalSetGuiPartial
    variable temporalSetGuiDurationUnit
    variable temporalSetGuiDurationUnitPrevious
    variable temporalSetGuiSegmentUnit
    variable temporalSetGuiSegmentUnitPrevious
    variable temporalSetGuiSegments

    temporalSetGuiEditorReset
    set temporalSetGuiEditingId $id
    set temporalSetGuiEditingType $type
    set currentVariableId ""
    set currentParent ""
    if {$id ne ""} {
        if {[catch {set definition [temporalSetRead $id]} err]} { return [temporalSetGuiError $err] }
        set temporalSetGuiLabel [dict get $definition label]
        set currentVariableId [dict get $definition temporal_variable_id]
        set currentParent [dict get $definition parent_selection_id]
        if {$type eq "window_set"} {
            set temporalSetGuiBasis [expr {[dict get $definition generator_basis] eq "duration" ? "Duration" : "Samples"}]
            set temporalSetGuiWindowSize [dict get $definition window_size]
            set temporalSetGuiStep [dict get $definition step]
            set temporalSetGuiPartial [string totitle [dict get $definition partial_policy]]
            if {$temporalSetGuiBasis eq "Duration"} {
                set temporalSetGuiDurationUnit [dict get $definition duration_unit]
                if {$temporalSetGuiDurationUnit eq ""} {
                    catch { set temporalSetGuiDurationUnit [temporalSetNumericUnitForVariable [datasetVariableV3ById $temporalSetGuiDataset $currentVariableId]] }
                }
                if {$temporalSetGuiDurationUnit eq ""} { set temporalSetGuiDurationUnit s }
                set temporalSetGuiDurationUnitPrevious $temporalSetGuiDurationUnit
            }
        } else {
            set temporalSetGuiSegments [dict get $definition segments]
        }
    }

    set variableChoices [temporalSetGuiRefreshVariableChoices $temporalSetGuiDataset $currentVariableId]
    set variableId [temporalSetGuiSelectedVariableId]
    set parentChoices [temporalSetGuiRefreshParentChoices $temporalSetGuiDataset $variableId $currentParent]
    set units [temporalSetGuiDurationUnits]
    if {[llength $units] && [lsearch -exact $units $temporalSetGuiDurationUnit] < 0} {
        set temporalSetGuiDurationUnit [expr {[lsearch -exact $units s] >= 0 ? "s" : [lindex $units 0]}]
        set temporalSetGuiDurationUnitPrevious $temporalSetGuiDurationUnit
    }

    if {$type eq "segment_set"} {
        set axisUnit s
        if {$variableId ne "" && ![catch {set axisVar [datasetVariableV3ById $temporalSetGuiDataset $variableId]}]} {
            set axisUnit [temporalSetNumericUnitForVariable $axisVar]
        }
        set temporalSetGuiSegmentUnit [expr {[lsearch -exact $units $axisUnit] >= 0 ? $axisUnit : ([lsearch -exact $units s] >= 0 ? "s" : [lindex $units 0])}]
        set temporalSetGuiSegmentUnitPrevious $temporalSetGuiSegmentUnit
        if {$id ne "" && $temporalSetGuiSegmentUnit ne $axisUnit} {
            set converted {}
            foreach segment $temporalSetGuiSegments {
                dict set segment start [temporalSetGuiConvertDuration [dict get $segment start] $axisUnit $temporalSetGuiSegmentUnit]
                dict set segment end [temporalSetGuiConvertDuration [dict get $segment end] $axisUnit $temporalSetGuiSegmentUnit]
                lappend converted $segment
            }
            set temporalSetGuiSegments $converted
        }
    }

    set body .top.nb.channels.temporal.body
    destroyChildren $body
    ttk::frame $body.editor
    grid $body.editor -row 0 -column 0 -sticky nsew
    grid columnconfigure $body.editor 1 -weight 1

    set title [expr {$id eq "" ? ($type eq "window_set" ? "New Window Set" : "New Segment Set") : "Edit $id"}]
    ttk::label $body.editor.title -text $title
    grid $body.editor.title -row 0 -column 0 -columnspan 4 -sticky w -pady {0 8}

    ttk::label $body.editor.ll -text "Label"
    ttk::entry $body.editor.label -textvariable ::GX::temporalSetGuiLabel
    grid $body.editor.ll -row 1 -column 0 -sticky e -padx 4 -pady 3
    grid $body.editor.label -row 1 -column 1 -columnspan 3 -sticky ew -padx 4 -pady 3

    ttk::label $body.editor.lv -text "Temporal variable"
    ttk::combobox $body.editor.variable -textvariable ::GX::temporalSetGuiVarDisplay -values $variableChoices -state readonly -width 54
    bind $body.editor.variable <<ComboboxSelected>> ::GX::temporalSetGuiVariableChanged
    grid $body.editor.lv -row 2 -column 0 -sticky e -padx 4 -pady 3
    grid $body.editor.variable -row 2 -column 1 -columnspan 3 -sticky ew -padx 4 -pady 3

    ttk::label $body.editor.lp -text "Parent Selection"
    ttk::combobox $body.editor.parent -textvariable ::GX::temporalSetGuiParentDisplay -values $parentChoices -state readonly -width 54
    bind $body.editor.parent <<ComboboxSelected>> ::GX::temporalSetGuiParentChanged
    grid $body.editor.lp -row 3 -column 0 -sticky e -padx 4 -pady 3
    grid $body.editor.parent -row 3 -column 1 -columnspan 3 -sticky ew -padx 4 -pady 3

    if {$type eq "window_set"} {
        ttk::label $body.editor.lb -text "Basis"
        ttk::combobox $body.editor.basis -textvariable ::GX::temporalSetGuiBasis -values {Samples Duration} -state readonly
        bind $body.editor.basis <<ComboboxSelected>> ::GX::temporalSetGuiWindowBasisChanged
        ttk::label $body.editor.lw -text "Window size"
        ttk::entry $body.editor.window -textvariable ::GX::temporalSetGuiWindowSize -width 18
        ttk::label $body.editor.ls -text "Step"
        ttk::entry $body.editor.step -textvariable ::GX::temporalSetGuiStep -width 18
        ttk::label $body.editor.lu -text "Duration unit"
        ttk::combobox $body.editor.durationUnit -textvariable ::GX::temporalSetGuiDurationUnit -values $units -state readonly -width 16
        bind $body.editor.durationUnit <<ComboboxSelected>> ::GX::temporalSetGuiDurationUnitChanged
        ttk::label $body.editor.lpart -text "Partial window"
        ttk::combobox $body.editor.partial -textvariable ::GX::temporalSetGuiPartial -values {Drop Include} -state readonly -width 16
        grid $body.editor.lb -row 4 -column 0 -sticky e -padx 4 -pady 3
        grid $body.editor.basis -row 4 -column 1 -sticky w -padx 4 -pady 3
        grid $body.editor.lw -row 5 -column 0 -sticky e -padx 4 -pady 3
        grid $body.editor.window -row 5 -column 1 -sticky w -padx 4 -pady 3
        grid $body.editor.ls -row 6 -column 0 -sticky e -padx 4 -pady 3
        grid $body.editor.step -row 6 -column 1 -sticky w -padx 4 -pady 3
        grid $body.editor.lu -row 5 -column 2 -sticky e -padx 4 -pady 3
        grid $body.editor.durationUnit -row 5 -column 3 -sticky w -padx 4 -pady 3
        grid $body.editor.lpart -row 6 -column 2 -sticky e -padx 4 -pady 3
        grid $body.editor.partial -row 6 -column 3 -sticky w -padx 4 -pady 3
        temporalSetGuiWindowBasisChanged
    } else {
        ttk::label $body.editor.lsu -text "Display unit"
        ttk::combobox $body.editor.segmentUnit -textvariable ::GX::temporalSetGuiSegmentUnit -values $units -state readonly -width 16
        bind $body.editor.segmentUnit <<ComboboxSelected>> ::GX::temporalSetGuiSegmentUnitChanged
        grid $body.editor.lsu -row 4 -column 0 -sticky e -padx 4 -pady 3
        grid $body.editor.segmentUnit -row 4 -column 1 -sticky w -padx 4 -pady 3

        ttk::labelframe $body.editor.segments -text "Segments"
        grid $body.editor.segments -row 5 -column 0 -columnspan 4 -sticky nsew -padx 4 -pady 6
        grid columnconfigure $body.editor.segments 0 -weight 1
        ttk::treeview $body.editor.segments.tree -columns {label start end} -show headings -height 7 -selectmode browse
        foreach {col text width} {label Label 300 start Start 160 end End 160} {
            $body.editor.segments.tree heading $col -text $text
            $body.editor.segments.tree column $col -width $width -stretch [expr {$col eq "label"}]
        }
        grid $body.editor.segments.tree -row 0 -column 0 -columnspan 6 -sticky ew -padx 3 -pady 3
        bind $body.editor.segments.tree <<TreeviewSelect>> ::GX::temporalSetGuiSegmentSelected
        ttk::label $body.editor.segments.ll -text "Label"
        ttk::entry $body.editor.segments.label -textvariable ::GX::temporalSetGuiSegmentLabel -width 28
        ttk::label $body.editor.segments.ls -text "Start"
        ttk::entry $body.editor.segments.start -textvariable ::GX::temporalSetGuiSegmentStart -width 14
        ttk::label $body.editor.segments.le -text "End"
        ttk::entry $body.editor.segments.end -textvariable ::GX::temporalSetGuiSegmentEnd -width 14
        grid $body.editor.segments.ll -row 1 -column 0 -padx 3 -pady 3
        grid $body.editor.segments.label -row 1 -column 1 -padx 3 -pady 3
        grid $body.editor.segments.ls -row 1 -column 2 -padx 3 -pady 3
        grid $body.editor.segments.start -row 1 -column 3 -padx 3 -pady 3
        grid $body.editor.segments.le -row 1 -column 4 -padx 3 -pady 3
        grid $body.editor.segments.end -row 1 -column 5 -padx 3 -pady 3
        ttk::frame $body.editor.segments.actions
        ttk::button $body.editor.segments.actions.add -text "Add segment" -command ::GX::temporalSetGuiAddSegment
        ttk::button $body.editor.segments.actions.update -text "Update selected" -command ::GX::temporalSetGuiUpdateSegment
        ttk::button $body.editor.segments.actions.remove -text "Remove segment" -command ::GX::temporalSetGuiRemoveSegment
        pack $body.editor.segments.actions.add $body.editor.segments.actions.update $body.editor.segments.actions.remove -side left -padx 4
        grid $body.editor.segments.actions -row 2 -column 0 -columnspan 6 -sticky w -padx 3 -pady 4
        temporalSetGuiRenderSegments
    }

    ttk::frame $body.editor.actions
    ttk::button $body.editor.actions.save -text "Save" -command ::GX::temporalSetGuiSave
    ttk::button $body.editor.actions.cancel -text "Cancel" -command ::GX::temporalSetGuiShowList
    pack $body.editor.actions.save $body.editor.actions.cancel -side left -padx 5
    grid $body.editor.actions -row 20 -column 0 -columnspan 4 -sticky w -pady 10
    dict set ::GX::datasetPageEditorBaselines temporal [datasetPageTemporalDraft]
}

proc ::GX::temporalSetGuiRenderSegments {} {
    variable temporalSetGuiSegments
    set tree .top.nb.channels.temporal.body.editor.segments.tree
    if {![winfo exists $tree]} return
    foreach iid [$tree children {}] { $tree delete $iid }
    set index 0
    foreach segment $temporalSetGuiSegments {
        incr index
        $tree insert {} end -id "row_$index" -values [list [dict get $segment label] [dict get $segment start] [dict get $segment end]]
    }
}

proc ::GX::temporalSetGuiSegmentSelected {} {
    variable temporalSetGuiSegments
    variable temporalSetGuiSegmentLabel
    variable temporalSetGuiSegmentStart
    variable temporalSetGuiSegmentEnd
    set tree .top.nb.channels.temporal.body.editor.segments.tree
    if {![winfo exists $tree]} return
    set selection [$tree selection]
    if {![llength $selection]} return
    if {![regexp {^row_([0-9]+)$} [lindex $selection 0] -> index]} return
    set segment [lindex $temporalSetGuiSegments [expr {$index-1}]]
    set temporalSetGuiSegmentLabel [dict get $segment label]
    set temporalSetGuiSegmentStart [dict get $segment start]
    set temporalSetGuiSegmentEnd [dict get $segment end]
}

proc ::GX::temporalSetGuiValidateSegmentInput {} {
    variable temporalSetGuiSegmentStart
    variable temporalSetGuiSegmentEnd
    if {![string is double -strict $temporalSetGuiSegmentStart] || ![string is double -strict $temporalSetGuiSegmentEnd]} {
        error "Segment start and end must be numeric values."
    }
    if {double($temporalSetGuiSegmentEnd) <= double($temporalSetGuiSegmentStart)} {
        error "Segment end must be greater than start."
    }
}

proc ::GX::temporalSetGuiAddSegment {} {
    variable temporalSetGuiSegments
    variable temporalSetGuiSegmentLabel
    variable temporalSetGuiSegmentStart
    variable temporalSetGuiSegmentEnd
    if {[catch {temporalSetGuiValidateSegmentInput} err]} { return [temporalSetGuiError $err] }
    lappend temporalSetGuiSegments [dict create id "" label $temporalSetGuiSegmentLabel start $temporalSetGuiSegmentStart end $temporalSetGuiSegmentEnd]
    set temporalSetGuiSegmentLabel ""; set temporalSetGuiSegmentStart ""; set temporalSetGuiSegmentEnd ""
    temporalSetGuiRenderSegments
    return 1
}

proc ::GX::temporalSetGuiUpdateSegment {} {
    variable temporalSetGuiSegments
    variable temporalSetGuiSegmentLabel
    variable temporalSetGuiSegmentStart
    variable temporalSetGuiSegmentEnd
    set tree .top.nb.channels.temporal.body.editor.segments.tree
    set selection [$tree selection]
    if {![llength $selection] || ![regexp {^row_([0-9]+)$} [lindex $selection 0] -> index]} { return [temporalSetGuiError "Select a segment to update."] }
    if {[catch {temporalSetGuiValidateSegmentInput} err]} { return [temporalSetGuiError $err] }
    set old [lindex $temporalSetGuiSegments [expr {$index-1}]]
    set replacement [dict create id [dict get $old id] label $temporalSetGuiSegmentLabel start $temporalSetGuiSegmentStart end $temporalSetGuiSegmentEnd]
    lset temporalSetGuiSegments [expr {$index-1}] $replacement
    temporalSetGuiRenderSegments
    $tree selection set row_$index
    return 1
}

proc ::GX::temporalSetGuiRemoveSegment {} {
    variable temporalSetGuiSegments
    set tree .top.nb.channels.temporal.body.editor.segments.tree
    set selection [$tree selection]
    if {![llength $selection] || ![regexp {^row_([0-9]+)$} [lindex $selection 0] -> index]} { return [temporalSetGuiError "Select a segment to remove."] }
    set temporalSetGuiSegments [lreplace $temporalSetGuiSegments [expr {$index-1}] [expr {$index-1}]]
    temporalSetGuiRenderSegments
    return 1
}

proc ::GX::temporalSetGuiDefinitionFromEditor {} {
    variable temporalSetGuiDataset
    variable temporalSetGuiEditingType
    variable temporalSetGuiLabel
    variable temporalSetGuiBasis
    variable temporalSetGuiWindowSize
    variable temporalSetGuiStep
    variable temporalSetGuiPartial
    variable temporalSetGuiDurationUnit
    variable temporalSetGuiSegmentUnit
    variable temporalSetGuiSegments

    set variableId [temporalSetGuiSelectedVariableId]
    if {$variableId eq ""} { error "No compatible temporal variable is selected." }
    set variable [datasetVariableV3ById $temporalSetGuiDataset $variableId]
    set compatibility [temporalSetGuiTemporalCompatibility $variable]
    if {![dict get $compatibility compatible]} { error "Temporal variable '$variableId' is incompatible: [dict get $compatibility reason]" }
    set parentId [temporalSetGuiSelectedParentId]
    set definition [dict create type $temporalSetGuiEditingType source_dataset_id $temporalSetGuiDataset temporal_variable_id $variableId parent_selection_id $parentId label [string trim $temporalSetGuiLabel]]

    if {$temporalSetGuiEditingType eq "window_set"} {
        set basis [string tolower $temporalSetGuiBasis]
        dict set definition generator_basis $basis
        dict set definition window_size [string trim $temporalSetGuiWindowSize]
        dict set definition step [string trim $temporalSetGuiStep]
        dict set definition partial_policy [string tolower $temporalSetGuiPartial]
        if {$basis eq "duration"} {
            elapsedTimeRequestedUnit $temporalSetGuiDurationUnit
            dict set definition duration_unit $temporalSetGuiDurationUnit
        } else {
            dict set definition duration_unit ""
        }
        return $definition
    }

    if {![llength $temporalSetGuiSegments]} { error "A Temporal Segment Set must contain at least one segment." }
    set axisUnit [temporalSetNumericUnitForVariable $variable]
    set segments {}
    foreach segment $temporalSetGuiSegments {
        set start [temporalUnitConvertLinear [dict get $segment start] $temporalSetGuiSegmentUnit $axisUnit]
        set end [temporalUnitConvertLinear [dict get $segment end] $temporalSetGuiSegmentUnit $axisUnit]
        set item [dict create label [dict get $segment label] start [format %.17g $start] end [format %.17g $end]]
        if {[dict exists $segment id] && [dict get $segment id] ne ""} { dict set item id [dict get $segment id] }
        lappend segments $item
    }
    dict set definition segments $segments
    return $definition
}

proc ::GX::temporalSetGuiSave {} {
    if {[catch {datasetPageEditorRequire temporal} message]} {setStatus $message 100;return 0}
    variable temporalSetGuiEditingId
    if {[catch {set definition [temporalSetGuiDefinitionFromEditor]} err]} { return [temporalSetGuiError $err] }
    if {[catch {
        if {$temporalSetGuiEditingId eq ""} {
            set id [temporalSetCreate $definition]
        } else {
            set id $temporalSetGuiEditingId
            temporalSetUpdate $id $definition
        }
        temporalSetResolveInfo $id
    } err]} { return [temporalSetGuiError $err] }
    catch {temporalSetWidgetRefreshAll}
    temporalSetGuiSetStatus "Temporal Set $id saved."
    temporalSetGuiShowList
    set tree .top.nb.channels.temporal.body.list.tree
    if {[winfo exists $tree] && [$tree exists $id]} { $tree selection set $id; $tree see $id; temporalSetGuiUpdatePreview }
    return $id
}

proc ::GX::temporalSetGuiDeleteSelected {{confirm 1}} {
    set id [temporalSetGuiSelectedSetId]
    if {$id eq ""} { return [temporalSetGuiError "Select a Temporal Set to delete."] }
    if {$confirm} {
        set answer [tk_messageBox -icon question -type yesno -title "Delete Temporal Set" -message "Delete Temporal Set '$id'?\n\nThis removes the persistent Temporal Set definition. Source Dataset values are not modified."]
        if {$answer ne "yes"} { return 0 }
    }
    if {[catch {temporalSetDelete $id} err]} { return [temporalSetGuiError $err] }
    catch {temporalSetWidgetRefreshAll}
    temporalSetGuiSetStatus "Temporal Set $id deleted."
    temporalSetGuiPopulateList
    return 1
}

# Add the Dataset-scoped entry point beside Metadata while preserving the
# existing Variables workspace implementation and all of its controls.
proc ::GX::refreshNativeVariablesGui_before_dataset_page_actions {} {
    variable temporalSetGuiActive
    ::GX::refreshNativeVariablesGui_before_temporal_set_gui_v1
    set f .top.nb.channels
    if {![winfo exists $f.bar]} { return }
    variable variableDatasetChoice
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode id
    if {$mode ne "imported"} { set temporalSetGuiActive 0 }
    if {![winfo exists $f.bar.temporal]} {
    ttk::button $f.bar.temporal -text "Temporal Sets..." -command ::GX::temporalSetGuiOpen
    if {[winfo exists $f.bar.delete]} {
        pack $f.bar.temporal -side left -padx 8 -before $f.bar.delete
    } else {
        pack $f.bar.temporal -side left -padx 8
    }
    }
    $f.bar.temporal state [expr {$mode eq "imported"?"!disabled":"disabled"}]
    # Keep a live embedded editor intact across catalog refresh.
}

proc ::GX::defaults_before_project_api_v1 {} {
    variable temporalSetGuiActive
    variable temporalSetGuiDataset
    variable temporalSetGuiVariableMap
    variable temporalSetGuiParentMap
    ::GX::defaults_before_temporal_set_gui_v1
    set temporalSetGuiActive 0
    set temporalSetGuiDataset ""
    array unset temporalSetGuiVariableMap *
    array unset temporalSetGuiParentMap *
}
