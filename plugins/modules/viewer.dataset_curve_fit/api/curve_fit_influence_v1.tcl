# Fitter adapts owned rows and public CORE meaning; Numeric owns diagnostics.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_influenceOption {model options} {
    set enabled [::GX::datasetPublicationV2DictDefault $options influence_diagnostics 0]
    if {![string is boolean -strict $enabled]} {error {Influence diagnostics must be an explicit boolean}}
    if {!$enabled} {return 0}
    if {$model ni {linear polynomial}||[_fitOrientation $model $options] ni {y_of_x x_of_y}||[dict get [_measurementOptions $options] kind] eq "sigma_xy"} {error {Exact influence diagnostics require an ordinary or weighted linear/polynomial response fit; nonlinear, orthogonal and radial fits are not supported}}
    return 1
}
proc ::GX::DatasetCurveFit::_influenceColumns {} {
    return {leverage deleted_residual loo_prediction studentized_residual cooks_distance deletion_available scaled_available}
}
proc ::GX::DatasetCurveFit::_influenceImport {document directory result} {
    if {![dict exists $result numeric_statistics influence]} {return $result}
    if {$document eq {}} {error {Influence requires an owned Fitter Document}}
    set n [dict get $result numeric_statistics influence n]
    foreach {field file format role} {
        influence_resource influence.bin float64_interleaved_le regression_influence
        influence_input_rows_resource influence_input_rows.bin uint64_le influence_input_positions
        influence_source_rows_resource influence_source_rows.bin uint64_le influence_source_rows
    } {
        set metadata [dict create format $format row_count $n role $role numeric_receipt_sha256 [_numericStateDigest [dict get $result numeric_statistics influence]] source_sha256 [dict get $result comparison_input source_sha256] training_rows_sha256 [dict get $result comparison_input rows_sha256]]
        if {$format eq "float64_interleaved_le"} {dict set metadata columns [_influenceColumns]}
        dict set result $field [::GX::interactiveDocumentResourceImportNumeric $document [file join $directory $file] $metadata]
    }
    return $result
}
proc ::GX::DatasetCurveFit::_validateInfluenceMetadata {result} {
    set fields {influence_resource influence_input_rows_resource influence_source_rows_resource}
    if {![dict exists $result statistical_results influence]} {
        foreach field $fields {if {[dict exists $result $field]} {error {Influence columns lack their captured CORE interpretation}}}
        return
    }
    set meaning [dict get $result statistical_results influence];::GX::StatisticsV1::validate $meaning
    set expected [::GX::StatisticsV1::influenceInterpretation [dict get $result statistical_results training] [dict get $meaning request numeric]]
    if {$expected ne $meaning} {error {Influence interpretation differs from the retained fitted source}}
    set n [dict get $meaning row_count]
    foreach field $fields format {float64_interleaved_le uint64_le uint64_le} width {56 8 8} role {regression_influence influence_input_positions influence_source_rows} {
        if {![dict exists $result $field]} {error "Influence result lacks $field"}
        set info [::GX::interactiveDocumentResourceInfo [dict get $result $field]];set metadata [dict get $info metadata]
        if {[dict get $info size_bytes]!=$width*$n||[dict get $metadata row_count]!=$n||[dict get $metadata format] ne $format||[dict get $metadata role] ne $role} {error {Influence resource shape or row identity changed}}
        if {[dict exists $metadata numeric_receipt_sha256]} {
            if {[dict get $metadata numeric_receipt_sha256] ne [_numericStateDigest [dict get $meaning request numeric]]||[dict get $metadata source_sha256] ne [dict get $result observation_binding source_sha256]||[dict get $metadata training_rows_sha256] ne [dict get $result observation_binding rows_sha256]} {error {Influence resource belongs to a different fit or training population}}
        } else {error {Influence resource lacks its fitted-population binding}}
        if {$field eq "influence_resource"&&[dict get $metadata columns] ne [_influenceColumns]} {error {Influence canonical column identities changed}}
    }
}
proc ::GX::DatasetCurveFit::_influencePage {result start count} {
    _validateInfluenceMetadata $result
    if {![dict exists $result statistical_results influence]} {error {This retained fit has no influence diagnostics; request them in a new explicit fit}}
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$count>512} {error {Influence pages require a nonnegative offset and 1..512 rows}}
    set page [dict create api_id FITTER_INFLUENCE_PAGE_v1 api_version 1 meaning [dict get $result statistical_results influence]]
    foreach field {influence_resource influence_input_rows_resource influence_source_rows_resource} name {diagnostics input_rows source_rows} {
        dict set page $name [::GX::managedResourceNumericPage [dict get $result $field] $start $count]
    }
    return $page
}
proc ::GX::DatasetCurveFit::resultInfluencePage {reference start count} {
    return [_influencePage [dict get [_recipeResultRecord $reference] provenance] $start $count]
}
proc ::GX::DatasetCurveFit::_influenceSelectRow {w result offset} {
    variable state
    _assertLoaded $w
    set page [_influencePage $result $offset 1]
    if {[dict get $page source_rows row_count]!=1} {error {Choose an existing diagnostic row}}
    binary scan [dict get $page source_rows bytes] wu row
    return [_diagnosticSelectSourceRow $w $result $row]
}
proc ::GX::DatasetCurveFit::_diagnosticSelectSourceRow {w result row} {
    variable state
    _assertLoaded $w
    set current [_sourceProvenance $w]
    foreach field {source_kind source_dataset_id source_x_variable_id source_y_variable_id source_sha256 source_filters source_transform_manifest source_sample_id source_sample_descriptor} {
        if {[::GX::datasetPublicationV2DictDefault $result $field {}] ne [::GX::datasetPublicationV2DictDefault $current $field {}]} {error {Diagnostic row belongs to a different source; activate its original unchanged source first}}
    }
    if {[dict exists $result source_scientific_fingerprints]} {
        set check [::GX::curveSourceValidateSnapshot $::GX::currentSession [dict create api_id CURVE_SOURCE_API_v1 api_version 1 source_identities [dict get $result source_scientific_fingerprints]]]
        if {![dict get $check valid]} {error {Diagnostic source content or schema changed}}
    }
    if {$state($w,sourceToken) ne {}} {
        set location [::GX::curveSourceLocateRows $state($w,sourceToken) [list $row]]
        set exact [::GX::curveSourcePage $state($w,sourceToken) [lindex [dict get $location positions] 0] 1]
        if {[dict get $exact source_rows] ne [list $row]} {error {Diagnostic row lookup lost its original identity}}
        set point [lindex [dict get $exact rows] 0]
    } else {
        set index [lsearch -exact $state($w,rows) $row]
        if {$index<0} {error {Diagnostic row is unavailable in this source}}
        set point [lindex [sourcePoints $w] $index]
    }
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    clearSelection $w;set state($w,rects) {}
    set index [lsearch -exact $state($w,rows) $row]
    if {$index>=0} {selectPoint $w $index add}
    set state($w,recipePointMask) [dict create api_id CURVE_SOURCE_POINT_MASK_v1 base_selected 0 regions {} manual_rows [dict create $row 1]]
    set state($w,influenceLinkedPoint) [dict create row $row point $point]
    _invalidateSelectionPreview $w
    set state($w,status) "Exact source row $row selected for review; source data are unchanged."
    _saveState $w;redraw $w
    return [dict create source_row_ordinal $row display_index $index point $point]
}
proc ::GX::DatasetCurveFit::_influenceDrawLink {w} {
    variable state
    if {![info exists state($w,influenceLinkedPoint)]} return
    set point [dict get $state($w,influenceLinkedPoint) point]
    lassign [_screen $w {*}$point] x y
    set canvas $w.right.plot.canvas
    $canvas create oval [expr {$x-7}] [expr {$y-7}] [expr {$x+7}] [expr {$y+7}] -outline #b44700 -width 2 -tags influence_row_link
    $canvas create text [expr {$x+10}] [expr {$y-10}] -anchor sw -text "Row [dict get $state($w,influenceLinkedPoint) row]" -fill #b44700 -tags influence_row_link
}
proc ::GX::DatasetCurveFit::_influenceDetails {w} {
    variable state
    set chosen [$w.left.viewport.content.accepted.list curselection]
    if {[llength $chosen]==1} {
        set result [dict get [lindex $state($w,records) [lindex $chosen 0]] provenance]
    } else {
        _assertLoaded $w
        set result [dict merge [_sourceProvenance $w] $state($w,preview)]
    }
    _validateInfluenceMetadata $result
    if {![dict exists $result statistical_results influence]} {error {This fit has no influence diagnostics; enable them in Statistical assumptions and preview a supported model}}
    set d $w.influenceDetails;if {[winfo exists $d]} {destroy $d}
    set state($w,influenceDialogResult) $result;set state($w,influenceOffset) 0
    toplevel $d;wm title $d {Linear influence};wm transient $d $w
    text $d.report -height 10 -width 96 -wrap word -yscrollcommand [list $d.reportScroll set]
    ttk::scrollbar $d.reportScroll -command [list $d.report yview]
    $d.report insert end [::GX::StatisticsV1::report [dict get $result statistical_results influence]];$d.report configure -state disabled
    grid $d.report -row 0 -column 0 -sticky nsew;grid $d.reportScroll -row 0 -column 1 -sticky ns
    set columns [concat {source_row_ordinal input_row_index} [_influenceColumns]]
    ttk::treeview $d.table -columns $columns -show headings -height 12 -selectmode browse
    foreach id $columns {
        set label {Exact source row (zero based)}
        if {$id ne "source_row_ordinal"} {set label [dict get $result statistical_results influence columns $id label]}
        if {$id ni {source_row_ordinal input_row_index}} {append label " ([dict get $result statistical_results influence columns $id unit])"}
        $d.table heading $id -text $label;$d.table column $id -width [expr {max(130,[font measure TkHeadingFont $label]+22)}] -stretch 0
    }
    ttk::scrollbar $d.horizontal -orient horizontal -command [list $d.table xview]
    ttk::scrollbar $d.vertical -command [list $d.table yview]
    $d.table configure -xscrollcommand [list $d.horizontal set] -yscrollcommand [list $d.vertical set]
    grid $d.table -row 1 -column 0 -sticky nsew;grid $d.vertical -row 1 -column 1 -sticky ns;grid $d.horizontal -row 2 -column 0 -sticky ew
    ttk::frame $d.controls;grid $d.controls -row 3 -column 0 -sticky ew
    foreach {id label delta} {previous Previous -100 next Next 100} {ttk::button $d.controls.$id -text $label -command [list ::GX::DatasetCurveFit::_influenceDialogPage $w $delta];pack $d.controls.$id -side left}
    ttk::label $d.controls.page -textvariable ::GX::DatasetCurveFit::state($w,influencePageLabel);pack $d.controls.page -side left -padx 12
    ttk::button $d.controls.select -text {Select exact source row} -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_influenceDialogSelect $w]];pack $d.controls.select -side right
    grid rowconfigure $d 1 -weight 1;grid columnconfigure $d 0 -weight 1;wm geometry $d 1050x550
    bind $d <Escape> [list destroy $d]
    _influenceDialogPage $w 0
}
proc ::GX::DatasetCurveFit::_influenceDialogPage {w delta} {
    variable state
    set result $state($w,influenceDialogResult);set total [dict get $result statistical_results influence row_count]
    set start [expr {min(max(0,$state($w,influenceOffset)+$delta),100*int(($total-1)/100))}]
    set page [_influencePage $result $start 100];set count [dict get $page diagnostics row_count]
    binary scan [dict get $page diagnostics bytes] q* values
    binary scan [dict get $page input_rows bytes] wu* inputs
    binary scan [dict get $page source_rows bytes] wu* rows
    set tree $w.influenceDetails.table;$tree delete [$tree children {}]
    for {set i 0} {$i<$count} {incr i} {
        set display [lmap value [lrange $values [expr {7*$i}] [expr {7*$i+6}]] {if {[string equal -nocase $value NaN]} {set value NaN} else {format %.9g $value}}]
        $tree insert {} end -id [expr {$start+$i}] -values [concat [list [lindex $rows $i] [lindex $inputs $i]] $display]
    }
    set state($w,influenceOffset) $start;set state($w,influencePageLabel) "Rows [expr {$start+1}]–[expr {$start+$count}] of $total"
    $w.influenceDetails.controls.previous configure -state [expr {$start>0?"normal":"disabled"}]
    $w.influenceDetails.controls.next configure -state [expr {$start+$count<$total?"normal":"disabled"}]
}
proc ::GX::DatasetCurveFit::_influenceDialogSelect {w} {
    variable state
    set selection [$w.influenceDetails.table selection]
    if {[llength $selection]!=1} {error {Select one diagnostic row first}}
    return [_influenceSelectRow $w $state($w,influenceDialogResult) [lindex $selection 0]]
}

# Keep off-display exact picks when ordinary additive GUI selection changes.
proc ::GX::DatasetCurveFit::_influenceSyncSelection {key mode} {
    variable state
    if {![info exists state($key,recipePointMask)]} return
    set previous $state($key,recipePointMask)
    unset state($key,recipePointMask)
    set current [_selectionDescriptor $key]
    if {$mode ne "replace"} {
        dict for {row selected} [dict get $previous manual_rows] {
            if {[lsearch -exact $state($key,rows) $row]<0} {dict set current manual_rows $row $selected}
        }
    } else {unset -nocomplain state($key,influenceLinkedPoint)}
    set state($key,recipePointMask) $current
}
