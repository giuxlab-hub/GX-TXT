# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveViewer {variable st;array set st {};variable version 0.4.0;variable sourceEpoch 0}
proc ::GX::CurveViewer::_safe {w command} {
    variable st
    try {
        if {[dict exists $::GX::ScientificHistory::viewers $w] && [lindex $command 0] ni {::GX::CurveViewer::_redraw ::GX::CurveViewer::_select ::GX::CurveViewer::_close ::GX::CurveViewer::_sourceBatchNext ::GX::CurveViewer::_sourceCancel}} {
            if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
        }
        uplevel #0 $command
    } on error {message options} {
        if {[info exists st($w,status)]} {set st($w,status) $message}
        tk_messageBox -parent $w -icon error -type ok -title "Curve Viewer" -message $message
        return
    }
}
proc ::GX::CurveViewer::_scope {w} {
    variable st
    if {$st($w,session_token) ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen Curve Viewer"}
}
proc ::GX::CurveViewer::datasetIds {} {
    set result {}
    foreach id [::GX::datasetRegistryIds] {
        set n 0
        foreach v [::GX::datasetVariableSchemaV3 $id] {if {[dict get $v rank]==1&&[dict get $v dtype] ne "string"} {incr n}}
        if {$n>=2} {lappend result $id}
    }
    return $result
}
proc ::GX::CurveViewer::_label {id} {
    set metadata [::GX::datasetMetadataRead $::GX::currentSession $id]
    return [::GX::datasetPublicationV2DictDefault $metadata dataset.display_name $id]
}
proc ::GX::CurveViewer::_axisText {spec} {
    set label [string trim [dict get $spec display_label]]
    if {$label eq ""} {set label [dict get $spec variable_id]}
    if {[dict get $spec unit] ne ""} {append label " ([dict get $spec unit])"}
    return $label
}
proc ::GX::CurveViewer::_sourceVariables {w} {
    variable st
    set d $w.source;set variables {};set mapping {}
    foreach v [::GX::datasetVariableSchemaV3 $st($w,dataset)] {
        if {[dict get $v rank]!=1||[dict get $v dtype] eq "string"} continue
        set label "[dict get $v display_label] ([dict get $v variable_id])"
        if {[dict get $v unit] ne ""} {append label " · [dict get $v unit]"}
        lappend variables $label;dict set mapping $label [dict get $v variable_id]
    }
    set st($w,variable_map) $mapping
    foreach axis {x y} {$d.$axis configure -values $variables}
    set st($w,x_label) [lindex $variables 0];set st($w,y_label) [lindex $variables 1]
    if {[winfo exists $d.family]} {
        set st($w,manualFamily) {};set ids {}
        foreach variable [::GX::datasetVariableSchemaV3 $st($w,dataset)] {if {[dict get $variable rank]==1 && [dict get $variable enabled]} {lappend ids [dict get $variable variable_id]}}
        $d.manual configure -values [linsert $ids 0 {}]
        $d.points.variable configure -values $ids
        set st($w,filterVariable) [lindex $ids 0];set st($w,pointFilters) {}
        ::GX::scientificDatasetFilterControls $d.family $st($w,dataset) ::GX::CurveViewer::st $w 1 {} 1
        $d.points.list delete 0 end
        $d.selection configure -values [linsert [::GX::datasetSelectionIds] 0 {}]
        if {$st($w,dimensions) eq {}} {grid remove $d.family} else {grid $d.family}
        _sourceAdvanced $w
    }
}
proc ::GX::CurveViewer::_sourceOpen {w} {
    variable st
    _scope $w
    set d $w.source
    if {[winfo exists $d]} {raise $d;return}
    set ids [datasetIds];if {$ids eq {}} {error "No Dataset contains two table-shaped numeric variables"}
    set st($w,dataset) [expr {$st($w,preferred) in $ids ? $st($w,preferred) : [lindex $ids 0]}]
    set st($w,editing) {};set st($w,sourceEpoch) [incr ::GX::CurveViewer::sourceEpoch];set st($w,advanced) 0
    toplevel $d;wm title $d "Add Dataset curve";wm geometry $d 730x680;wm transient $d $w
    grid columnconfigure $d 1 -weight 1
    foreach {key label row} {dataset Dataset 0 x X 1 y Y 2} {
        ttk::label $d.label$key -text $label;grid $d.label$key -row $row -column 0 -sticky w -padx 12 -pady 8
        set variable [expr {$key eq "dataset" ? "dataset" : "${key}_label"}]
        ttk::combobox $d.$key -textvariable ::GX::CurveViewer::st($w,$variable) -state readonly -width 50
        grid $d.$key -row $row -column 1 -sticky ew -padx 12 -pady 8
    }
    ::GX::datasetSelectorAttach $d.dataset ::GX::CurveViewer::datasetIds
    bind $d.dataset <<ComboboxSelected>> [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::_sourceVariables $w]]
    set st($w,manualFamily) {};set st($w,pointFilters) {};set st($w,filterPredicate) between_inclusive;set st($w,filterValue) {};set st($w,filterUpper) {};set st($w,selectionId) {}
    ttk::labelframe $d.family -text {Family members / categorical filters (AND)} -padding 5
    grid $d.family -row 3 -column 0 -columnspan 2 -sticky ew -padx 12 -pady 5
    ttk::label $d.manualLabel -text {Manual family Variable ID (optional)}
    ttk::combobox $d.manual -textvariable ::GX::CurveViewer::st($w,manualFamily) -state readonly
    grid $d.manualLabel -row 4 -column 0 -sticky w -padx 12
    grid $d.manual -row 4 -column 1 -sticky ew -padx 12
    bind $d.manual <<ComboboxSelected>> [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::_familyBinding $w]]
    ttk::labelframe $d.points -text {Optional point filters (AND; source stays unchanged)} -padding 5
    grid $d.points -row 5 -column 0 -columnspan 2 -sticky nsew -padx 12 -pady 5
    grid columnconfigure $d.points 1 -weight 1
    ttk::combobox $d.points.variable -textvariable ::GX::CurveViewer::st($w,filterVariable) -state readonly -width 20
    ttk::combobox $d.points.predicate -textvariable ::GX::CurveViewer::st($w,filterPredicate) -state readonly -values {between_inclusive exact_equal not_equal less_than less_equal greater_than greater_equal in_set is_finite is_nonfinite} -width 22
    ttk::entry $d.points.value -textvariable ::GX::CurveViewer::st($w,filterValue) -width 18
    ttk::entry $d.points.upper -textvariable ::GX::CurveViewer::st($w,filterUpper) -width 18
    foreach {widget row col} {variable 0 0 predicate 0 1 value 1 0 upper 1 1} {grid $d.points.$widget -row $row -column $col -sticky ew -padx 3 -pady 3}
    ttk::label $d.points.help -text {Value / lower bound and upper bound. In-set: enter a Tcl list of exact values; numeric IDs retain integer precision.} -wraplength 670
    grid $d.points.help -row 2 -column 0 -columnspan 2 -sticky ew
    listbox $d.points.list -height 3 -exportselection 0
    grid $d.points.list -row 3 -column 0 -columnspan 2 -sticky ew
    ttk::button $d.points.add -text {Add point filter} -command [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::_pointFilterAdd $w]]
    ttk::button $d.points.clear -text {Clear point filters} -command [list ::GX::CurveViewer::_pointFiltersClear $w]
    grid $d.points.add -row 4 -column 0 -sticky w;grid $d.points.clear -row 4 -column 1 -sticky w
    ttk::label $d.selectionLabel -text {Saved Dataset Selection ID (optional)}
    ttk::combobox $d.selection -textvariable ::GX::CurveViewer::st($w,selectionId) -state readonly
    grid $d.selectionLabel -row 6 -column 0 -sticky w -padx 12;grid $d.selection -row 6 -column 1 -sticky ew -padx 12
    ttk::label $d.info -text "Sources remain authoritative in the Dataset. Display is bounded; Preview reads exact rows." -wraplength 610
    grid $d.info -row 7 -column 0 -columnspan 2 -sticky ew -padx 12 -pady 8
    ttk::frame $d.actions;grid $d.actions -row 8 -column 0 -columnspan 2 -sticky e -padx 12 -pady 8
    ttk::checkbutton $d.actions.advanced -text {Point filters / manual binding} -variable ::GX::CurveViewer::st($w,advanced) -command [list ::GX::CurveViewer::_sourceAdvanced $w]
    ttk::button $d.actions.add -text "Add curve" -command [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::_sourceAdd $w]]
    ttk::button $d.actions.cancel -text Cancel -command [list ::GX::CurveViewer::_sourceCancel $w]
    pack $d.actions.advanced $d.actions.add $d.actions.cancel -side left -padx 5
    bind $d <Escape> [list ::GX::CurveViewer::_sourceCancel $w]
    wm protocol $d WM_DELETE_WINDOW [list ::GX::CurveViewer::_sourceCancel $w]
    _sourceVariables $w
}
proc ::GX::CurveViewer::_sourceAdvanced {w} {
    variable st
    foreach widget {manualLabel manual points selectionLabel selection} {
        if {$st($w,advanced)} {grid $w.source.$widget} else {grid remove $w.source.$widget}
    }
    wm geometry $w.source [expr {$st($w,advanced) ? "730x680" : ($st($w,dimensions) eq {} ? "730x300" : "730x460")}]
}
proc ::GX::CurveViewer::_sourceEdit {w} {
    variable st
    set ids [$w.sources selection]
    if {[llength $ids]!=1} {error {Select one source curve to edit its non-destructive filters}}
    set id [lindex $ids 0];set record [dict get $st($w,records) $id];set request [dict get $record request]
    _sourceOpen $w
    set st($w,editing) $id;set st($w,dataset) [dict get $request dataset_id]
    _sourceVariables $w
    set manual [::GX::datasetPublicationV2DictDefault $record manual_family {}]
    if {$manual ne {}} {set st($w,manualFamily) $manual;_familyBinding $w}
    dict for {label vid} $st($w,variable_map) {
        foreach axis {x y} {if {$vid eq [dict get $request ${axis}_variable_id]} {set st($w,${axis}_label) $label}}
    }
    set st($w,selectionId) [::GX::datasetPublicationV2DictDefault $request selection_id {}]
    foreach filter [::GX::datasetPublicationV2DictDefault $request filters {}] {
        set vid [dict get $filter filter_variable_id];set categorical 0
        foreach dimension $st($w,dimensions) {
            if {$vid eq [dict get $dimension variable_id] && [dict get $filter predicate] eq "in_set"} {
                dict set st($w,filters) $vid [dict get $filter values];set categorical 1
            }
        }
        if {!$categorical} {lappend st($w,pointFilters) $filter;$w.source.points.list insert end $filter}
    }
    ::GX::scientificDatasetFilterLabels ::GX::CurveViewer::st $w
    set st($w,advanced) 1;_sourceAdvanced $w
    wm title $w.source {Edit source filters — canonical Dataset unchanged}
    $w.source.actions.add configure -text {Apply filters}
    $w.source.dataset configure -state disabled
}
proc ::GX::CurveViewer::_familyBinding {w} {
    variable st
    ::GX::scientificDatasetFilterControls $w.source.family $st($w,dataset) ::GX::CurveViewer::st $w 1 $st($w,manualFamily) 1
    if {$st($w,dimensions) eq {}} {grid remove $w.source.family} else {grid $w.source.family}
}
proc ::GX::CurveViewer::_pointFilterAdd {w} {
    variable st
    set filter [dict create filter_variable_id $st($w,filterVariable) predicate $st($w,filterPredicate)]
    if {$st($w,filterPredicate) eq "between_inclusive"} {
        dict set filter lower $st($w,filterValue);dict set filter upper $st($w,filterUpper)
    } elseif {$st($w,filterPredicate) eq "in_set"} {
        if {[catch {llength $st($w,filterValue)}] || $st($w,filterValue) eq {}} {error {Enter at least one exact value}}
        dict set filter values $st($w,filterValue)
    } elseif {$st($w,filterPredicate) ni {is_finite is_nonfinite}} {dict set filter value $st($w,filterValue)}
    set filter [lindex [::GX::graphSeriesNormalizeFilters $st($w,dataset) [list $filter]] 0]
    lappend st($w,pointFilters) $filter
    $w.source.points.list insert end "$st($w,filterVariable) · $st($w,filterPredicate) · $st($w,filterValue) $st($w,filterUpper)"
}
proc ::GX::CurveViewer::_pointFiltersClear {w} {variable st;set st($w,pointFilters) {};$w.source.points.list delete 0 end}
proc ::GX::CurveViewer::_sourceAdd {w} {
    variable st
    _scope $w
    set base [dict create dataset_id $st($w,dataset) x_variable_id [dict get $st($w,variable_map) $st($w,x_label)] y_variable_id [dict get $st($w,variable_map) $st($w,y_label)]]
    set selections $st($w,filters);set separate $st($w,separate)
    set families [lmap dimension $st($w,dimensions) {if {[dict get $dimension type] ne "family"} continue;set dimension}]
    if {[llength $families]>1 && $st($w,manualFamily) eq {}} {error {Several semantic family variables are available. Bind the intended family Variable ID explicitly in Point filters / manual binding.}}
    foreach dimension $st($w,dimensions) {
        if {[dict get $dimension type] ne "family"} continue
        set vid [dict get $dimension variable_id]
        if {![dict exists $selections $vid]} {
            # Explicit exact values remain usable beyond bounded discovery.
            # CORE validates and evaluates them; the host performs no row scan.
            foreach filter $st($w,pointFilters) {
                if {[dict get $filter filter_variable_id] ne $vid} continue
                if {[dict get $filter predicate] eq "exact_equal"} {dict set selections $vid [list [dict get $filter value]];break}
                if {[dict get $filter predicate] eq "in_set"} {dict set selections $vid [dict get $filter values];break}
            }
        }
        if {![dict exists $selections $vid]} {
            if {![dict get $dimension complete]} {error {Family discovery is incomplete. Select explicit members or manually bind the intended family variable.}}
            dict set selections $vid [dict get $dimension values]
        }
        set separate 1
    }
    set requests [::GX::scientificDatasetFilterRequests $st($w,dimensions) $selections $separate]
    if {$st($w,editing) ne {} && [llength $requests]!=1} {error {Select one family member while editing a curve. Use Add curve for multiple independent members.}}
    set st($w,sourceQueue) {};set st($w,sourceLoaded) {}
    foreach filters $requests {
        set request $base;dict set request filters [concat $filters $st($w,pointFilters)]
        if {$st($w,selectionId) ne {}} {dict set request selection_id $st($w,selectionId)}
        set name [_label $st($w,dataset)]
        foreach filter $filters {append name " · [dict get $filter filter_variable_id]=[join [dict get $filter values] {, }]"}
        set record [dict create id "viewcurve[incr st($w,next)]" request $request name $name visible 1 color [lindex {#1479A8 #C05F30 #7654A8 #208861 #BB3C73 #AD8726} [expr {($st($w,next)-1)%6}]] width 2 direction {}]
        dict set record manual_family $st($w,manualFamily)
        if {$st($w,editing) ne {}} {
            set old [dict get $st($w,records) $st($w,editing)]
            foreach key {visible color width direction presentation_label line_style marker} {if {[dict exists $old $key]} {dict set record $key [dict get $old $key]}}
        }
        lappend st($w,sourceQueue) $record
    }
    $w.source.actions.add configure -state disabled
    _sourceBatchNext $w
}
proc ::GX::CurveViewer::_sourceBatchNext {w} {
    variable st
    if {$st($w,sourceQueue) eq {}} {
        set added {};set prior $st($w,records);set old {}
        try {
            foreach pair $st($w,sourceLoaded) {lassign $pair token record;add $w $record $token;lappend added [dict get $record id]}
            if {$st($w,editing) ne {}} {
                set id $st($w,editing);set old [dict get $prior $id]
                set temporary [lindex $added 0];set updated [dict get $st($w,records) $temporary]
                dict unset st($w,records) $temporary;dict set updated id $id;dict set st($w,records) $id $updated
                set added [list $id]
            }
            ::GX::Native2D::core fit $st($w,scene)
            _refresh $w;_redraw $w;_save $w
        } on error {message options} {
            foreach id $added {set record [dict get $st($w,records) $id];::GX::Native2D::core delete $st($w,scene) [dict get $record native];::GX::curveSourceClose [dict get $record token];dict unset st($w,records) $id}
            set st($w,records) $prior
            _sourceBatchCleanup $w
            _refresh $w;_redraw $w
            return -options $options $message
        }
        set st($w,sourceLoaded) {}
        if {$old ne {}} {::GX::Native2D::core delete $st($w,scene) [dict get $old native];::GX::curveSourceClose [dict get $old token];_redraw $w}
        destroy $w.source
        set st($w,status) "Added [llength $added] independent exact source curves. Family members are never joined."
        return
    }
    set record [lindex $st($w,sourceQueue) 0];set st($w,sourceQueue) [lrange $st($w,sourceQueue) 1 end]
    set token {}
    try {
        set token [::GX::curveSourceOpen $::GX::currentSession [dict get $record request]]
        set st($w,sourceJob) [::GX::curveSourceDisplayAsync $token [list ::GX::CurveViewer::_sourceDone $w $st($w,sourceEpoch) $token $record] [list ::GX::CurveViewer::_sourceProgress $w]]
    } on error {message options} {
        if {$token ne {}} {::GX::curveSourceClose $token}
        _sourceBatchCleanup $w
        return -options $options $message
    }
}
proc ::GX::CurveViewer::_sourceBatchCleanup {w} {
    variable st
    foreach pair $st($w,sourceLoaded) {lassign $pair token record;catch {::GX::curveSourceClose $token}}
    set st($w,sourceLoaded) {};set st($w,sourceQueue) {}
    if {[winfo exists $w.source]} {$w.source.actions.add configure -state normal}
}
proc ::GX::CurveViewer::_sourceProgress {w progress} {
    variable st
    if {[winfo exists $w]} {set st($w,status) "Loading exact source rows: [dict get $progress completed_rows] / [dict get $progress total_rows]. Cancel leaves the view unchanged."}
}
proc ::GX::CurveViewer::_sourceCancel {w} {
    variable st
    if {$st($w,sourceJob) ne ""} {::GX::curveSourceCancel $st($w,sourceJob)}
    if {[info exists st($w,restoring)] && $st($w,restoring)} {
        if {$st($w,restoreAfter) ne {}} {after cancel $st($w,restoreAfter)}
        set st($w,restoreEpoch) [incr ::GX::CurveViewer::sourceEpoch]
        set st($w,restoreQueue) {};set st($w,incomplete) 1;set st($w,restoring) 0
        set st($w,status) {Opening cancelled; saved Workspace remains unchanged. Reopen to finish.}
    }
    set st($w,sourceJob) {};set st($w,sourceEpoch) [incr ::GX::CurveViewer::sourceEpoch]
    _sourceBatchCleanup $w
    if {[winfo exists $w.source]} {destroy $w.source}
}
proc ::GX::CurveViewer::_sourceDone {w epoch token record result} {
    variable st
    if {![winfo exists $w] || ![info exists st($w,sourceEpoch)] || $epoch != $st($w,sourceEpoch)} {catch {::GX::curveSourceClose $token};return}
    set st($w,sourceJob) {}
    if {[dict get $result status] ne "ok" || ![winfo exists $w]} {
        ::GX::curveSourceClose $token
        _sourceBatchCleanup $w
        if {[winfo exists $w]} {set st($w,status) [::GX::datasetPublicationV2DictDefault $result message {Loading cancelled; existing curves preserved.}]}
        return
    }
    lappend st($w,sourceLoaded) [list $token $record]
    _safe $w [list ::GX::CurveViewer::_sourceBatchNext $w]
}
proc ::GX::CurveViewer::add {w record {token ""} {prepared {}}} {
    variable st
    _scope $w
    set native ""
    try {
        set cacheHit 0
        if {$token eq {} && $prepared ne {} && [dict exists $prepared native]} {
            set descriptor [dict get $prepared descriptor];set display [dict get $prepared display];set native [dict get $prepared native];set cacheHit 1
        } elseif {$token eq {} && [dict exists $record display_cache] && $st($w,document) ne {}} {
            if {![catch {::GX::curveSourceDisplayCacheRestore $::GX::currentSession $st($w,document) [dict get $record display_cache] [dict get $record id] [dict get $record request] $st($w,scene)} cached]} {
                set descriptor [dict get $cached descriptor];set display [dict get $cached display];set native [dict get $cached native];set cacheHit 1
            } else {dict unset record display_cache;set st($w,status) "Rebuilding display [dict get $record id]: $cached"}
        }
        if {!$cacheHit} {
            if {$token eq ""} {set token [::GX::curveSourceOpen $::GX::currentSession [dict get $record request]]}
            set descriptor [::GX::curveSourceDescribe $token]
            if {$prepared eq {}} {set display [::GX::curveSourceDisplay $token]} else {set display $prepared}
            set native [::GX::Native2D::core add $st($w,scene) [dict get $display points]]
            if {[dict get $display breaks] ne {}} {::GX::Native2D::core set_breaks $st($w,scene) $native [dict get $display breaks]}
        }
        set color [::GX::uiFieldColorToRGBA [dict get $record color]]
        ::GX::Native2D::core object_style $st($w,scene) $native [dict create color $color line_width [dict get $record width] marker [::GX::datasetPublicationV2DictDefault $record marker 0] line_style [::GX::datasetPublicationV2DictDefault $record line_style 0] visible [dict get $record visible] locked 1]
        ::GX::Native2D::core direction_marker $st($w,scene) $native [dict get $record direction]
        dict set record token $token;dict set record native $native;dict set record descriptor $descriptor
        dict set record source_id [dict get $descriptor source_id];dict set record display $display;dict set record status ready
        dict set st($w,records) [dict get $record id] $record
        set token "";set native ""
        return [dict get $record id]
    } finally {
        if {$native ne ""} {::GX::Native2D::core delete $st($w,scene) $native}
        if {$token ne ""} {::GX::curveSourceClose $token}
    }
}
proc ::GX::CurveViewer::_refresh {w} {
    variable st
    set chosen [_chosenLabels $w]
    foreach item [$w.sources children {}] {
        if {![dict exists $st($w,records) $item]} {$w.sources delete $item}
    }
    dict for {id record} $st($w,records) {
        set descriptor [dict get $record descriptor]
        set labels {}
        foreach v [dict get $descriptor variables] {lappend labels [_axisText $v]}
        set mode [expr {[dict get $record visible] ? "shown" : "hidden"}]
        if {[dict get $record status] ne "ready"} {set mode [dict get $record status]}
        set name [dict get $chosen $id]
        set predicates [llength [::GX::datasetPublicationV2DictDefault [dict get $record request] filters {}]]
        if {$predicates} {append name " · $predicates predicates"}
        set values [list $name [dict get $record request dataset_id] [join $labels { / }] [dict get $descriptor row_count] $mode]
        if {[$w.sources exists $id]} {
            if {[$w.sources item $id -values] ne $values} {$w.sources item $id -values $values}
        } else {$w.sources insert {} end -id $id -values $values}
    }
}
proc ::GX::CurveViewer::_select {w} {
    variable st
    ::GX::Native2D::core clear $st($w,scene)
    set count 0
    foreach id [$w.sources selection] {
        # A queued TreeviewSelect can arrive between incremental restore steps.
        # Its old row remains a UI item until the new source collection is ready.
        if {![dict exists $st($w,records) $id]} continue
        set record [dict get $st($w,records) $id]
        set native [dict get $record native]
        if {$native ne "" && [dict get $record visible]} {
            ::GX::Native2D::core select_object $st($w,scene) $native add
            incr count
        }
    }
    return $count
}
proc ::GX::CurveViewer::_fit {w selected} {
    variable st
    if {$selected} {
        if {[$w.sources selection] eq {}} {error "Select one or more source curves first"}
        if {![_select $w]} {error "Selected curves are hidden or unavailable; show or reload them first"}
        ::GX::Native2D::core fit_selected $st($w,scene)
    } else {::GX::Native2D::core fit $st($w,scene)}
    _redraw $w;_save $w [expr {$selected ? "Fit selected view" : "Fit all sources"}]
}
proc ::GX::CurveViewer::_visibility {w shown} {
    variable st
    foreach id [$w.sources selection] {
        dict set st($w,records) $id visible $shown
        set native [dict get $st($w,records) $id native]
        if {$native ne ""} {::GX::Native2D::core visible $st($w,scene) $native $shown}
    }
    _refresh $w;_redraw $w;_save $w [expr {$shown ? "Show selected sources" : "Hide selected sources"}]
}
proc ::GX::CurveViewer::_remove {w} {
    variable st
    foreach id [$w.sources selection] {
        set record [dict get $st($w,records) $id]
        if {[dict get $record native] ne ""} {::GX::Native2D::core delete $st($w,scene) [dict get $record native]}
        if {[dict get $record token] ne ""} {::GX::curveSourceClose [dict get $record token]}
        dict unset st($w,records) $id
    }
    _refresh $w;_redraw $w;_save $w {Remove displayed sources}
}
proc ::GX::CurveViewer::_preview {w} {
    variable st
    set selected [$w.sources selection]
    if {[llength $selected]!=1} {error "Select exactly one source curve for its Dataset Preview"}
    ::GX::curveSourceDescribe [_canonicalToken $w [lindex $selected 0]]
    ::GX::datasetPreviewOpenTable [dict get $st($w,records) [lindex $selected 0] request dataset_id]
}
proc ::GX::CurveViewer::_presentationChanged {w} {_redraw $w;_save $w {Change axes / grid presentation}}
proc ::GX::CurveViewer::_presentation {w} {
    variable st
    ::GX::native2DGridForm $w.grid $st($w,scene) [list ::GX::CurveViewer::_presentationChanged $w] $w
}
proc ::GX::CurveViewer::_properties {w} {
    variable st
    set selected [$w.sources selection]
    if {[llength $selected]!=1} {error "Select one curve to edit its presentation"}
    set id [lindex $selected 0];set r [dict get $st($w,records) $id]
    if {[dict get $r native] eq ""} {error "Source is unavailable; remove and re-add it"}
    set fields [dict create color [dict create type color alpha 1 label "Curve color / opacity"] width [dict create type number min .1 max 64 label "Line width (px)"] direction [dict create type boolean label "Show direction"]]
    set values [dict create color [dict get $r color] width [dict get $r width] direction [dict get [::GX::Native2D::core direction_marker $st($w,scene) [dict get $r native]] visible]]
    dict set fields line_style [dict create type choice label {Line pattern} values {solid dashed dotted}]
    dict set fields marker [dict create type choice label {Point markers} values {none circle square cross}]
    dict set values line_style [lindex {solid dashed dotted} [::GX::datasetPublicationV2DictDefault $r line_style 0]]
    dict set values marker [lindex {none circle square cross} [::GX::datasetPublicationV2DictDefault $r marker 0]]
    ::GX::uiFieldFormCreate $w.properties "Curve presentation" $fields $values [list ::GX::CurveViewer::_propertiesApply $w $id] $w
}
proc ::GX::CurveViewer::_propertiesApply {w id values} {
    variable st
    _scope $w
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    if {![dict exists $st($w,records) $id]} {error "The source curve was removed"}
    set native [dict get $st($w,records) $id native]
    set pattern [lsearch -exact {solid dashed dotted} [::GX::datasetPublicationV2DictDefault $values line_style [lindex {solid dashed dotted} [::GX::datasetPublicationV2DictDefault [dict get $st($w,records) $id] line_style 0]]]]
    set marker [lsearch -exact {none circle square cross} [::GX::datasetPublicationV2DictDefault $values marker [lindex {none circle square cross} [::GX::datasetPublicationV2DictDefault [dict get $st($w,records) $id] marker 0]]]]
    ::GX::Native2D::core object_style $st($w,scene) $native [dict create color [::GX::uiFieldColorToRGBA [dict get $values color]] line_width [dict get $values width] line_style $pattern marker $marker]
    dict set st($w,records) $id line_style $pattern;dict set st($w,records) $id marker $marker
    ::GX::Native2D::core direction_marker $st($w,scene) $native [dict create visible [dict get $values direction]]
    foreach key {color width} {dict set st($w,records) $id $key [dict get $values $key]}
    _redraw $w;_save $w "Change curve style: $id"
}
proc ::GX::CurveViewer::snapshot {w} {
    variable st
    set labels {};set axes [dict create x {} y {}];set chosen [_chosenLabels $w]
    dict for {id r} $st($w,records) {
        if {[dict get $r native] eq ""} continue
        dict set labels [dict get $r native] [dict get $chosen $id]
        if {![dict get $r visible]} continue
        foreach axis {x y} spec [dict get $r descriptor variables] {
            set label [_axisText $spec]
            dict lappend axes $axis $label
        }
    }
    foreach axis {x y} {
        set names [lsort -unique [dict get $axes $axis]]
        set label [expr {[llength $names]==1 ? [lindex $names 0] : [llength $names]>1 ? "[string toupper $axis] · mixed bindings/units (see table)" : [string toupper $axis]}]
        dict set axes $axis $label
    }
    return [::GX::native2DPresentationSnapshot $st($w,scene) [dict create object_labels $labels x_label [dict get $axes x] y_label [dict get $axes y] title "Dataset curves" font_size 13 legend [expr {[dict get $st($w,labelPreferences) legend_visible] ? "auto" : ""}]]]
}
proc ::GX::CurveViewer::_export {w} {
    variable st;variable version
    _scope $w;_save $w
    set document [::GX::interactiveDocumentRead $st($w,document)]
    set context [dict create workbench_id viewer.curve_viewer workbench_version $version document_id $st($w,document) revision [dict get $document revision] selection [$w.sources selection] presentation_snapshot [snapshot $w]]
    ::GX::workbenchExtensionExportDialog $w.export $context $w
}
proc ::GX::CurveViewer::_publicationContext {w} {
    variable st;variable version
    _scope $w
    set ids [$w.sources selection]
    if {[llength $ids]!=1} {error {Select exactly one visible source/member curve}}
    set record [dict get $st($w,records) [lindex $ids 0]]
    if {![dict get $record visible] || [dict get $record status] ne "ready"} {error {The selected source must be visible and available}}
    set descriptor [::GX::curveSourceDescribe [_canonicalToken $w [lindex $ids 0]]]
    _save $w
    set document [::GX::interactiveDocumentRead $st($w,document)]
    return [dict create workbench_id viewer.curve_viewer workbench_version $version document_id $st($w,document) revision [dict get $document revision] selection [dict create kind curve_source source_id [lindex $ids 0] request [dict get $record request] descriptor $descriptor session_token $st($w,session_token) document_generation [dict get $document generation]]]
}
proc ::GX::CurveViewer::_publish {w} {
    set context [_publicationContext $w]
    set selection [dict get $context selection]
    set dialog [::GX::workbenchExtensionActionDialog $w.publish [list ::GX::CurveViewer::_publicationContext $w] $w]
    $dialog.status configure -text "Scientific source: [dict get $selection request dataset_id]; X=[dict get $selection request x_variable_id], Y=[dict get $selection request y_variable_id]; filters=[::GX::datasetPublicationV2DictDefault [dict get $selection request] filters {}]. Exact rows only."
}
proc ::GX::CurveViewer::_publishAvailability {w} {
    if {[dict exists $::GX::ViewerCommands::windows $w]} {::GX::viewerCommandMenusRefresh $w}
}
proc ::GX::CurveViewer::_redraw {w} {
    variable st
    if {![winfo exists $w.canvas]||[winfo width $w.canvas]<160||[winfo height $w.canvas]<160} return
    set view [::GX::Native2D::core view_requested $st($w,scene)]
    lset view 0 [winfo width $w.canvas];lset view 1 [winfo height $w.canvas]
    set view [lreplace $view 2 5 80 32 52 58]
    ::GX::Native2D::core view $st($w,scene) $view
    ::GX::native2DCanvasSnapshot $w.canvas [snapshot $w]
}
proc ::GX::CurveViewer::_zoom {w factor x y} {
    variable st
    if {![_ready $w] || ![::GX::scientificHistoryViewerEditable $w]} return
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    ::GX::Native2D::core zoom $st($w,scene) $factor [list $x $y];_redraw $w;_save $w {Zoom view}
}
proc ::GX::CurveViewer::_panDown {w x y} {
    variable st
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set st($w,pan) [list $x $y]
}
proc ::GX::CurveViewer::_panMove {w x y} {
    variable st
    if {$st($w,pan) eq {}} return
    lassign $st($w,pan) oldX oldY
    ::GX::Native2D::core pan $st($w,scene) [expr {$x-$oldX}] [expr {$y-$oldY}]
    set st($w,pan) [list $x $y];_redraw $w
}
proc ::GX::CurveViewer::_panUp {w} {
    variable st
    if {[info exists st($w,legendPressed)] && $st($w,legendPressed)} {set st($w,legendPressed) 0;return}
    if {$st($w,pan) eq {}} return
    set st($w,pan) {};_save $w {Pan view}
}
proc ::GX::CurveViewer::_coordinates {w x y} {
    variable st
    if {[info exists st($w,scene)]} {set st($w,coordinates) [::GX::native2DCoordinateReadout $st($w,scene) [list $x $y]]}
}
proc ::GX::CurveViewer::_catalogChanged {w receipt} {
    variable st
    if {![winfo exists $w]} return
    dict for {id record} $st($w,records) {
        if {[catch {
            if {[dict get $record token] eq {}} {
                set validation [::GX::curveSourceValidateSnapshot $::GX::currentSession [dict get $record descriptor]]
                if {![dict get $validation valid]} {error {Source changed; reopen to rebuild its display}}
                set descriptor [dict get $record descriptor]
            } else {set descriptor [::GX::curveSourceDescribe [dict get $record token]]}
        } message]} {
            dict set st($w,records) $id status "changed: reload source"
            set st($w,status) $message
        } else {
            dict set st($w,records) $id descriptor $descriptor
            # Keep explicit family identity/user presentation on catalog refresh.
        }
    }
    _refresh $w;_redraw $w
}
proc ::GX::CurveViewer::_payload {w {captureResources 1}} {
    variable st
    _scope $w
    set records {}
    dict for {id r} $st($w,records) {
        if {[dict get $r native] ne ""} {dict set r direction [::GX::Native2D::core direction_marker $st($w,scene) [dict get $r native]]}
        if {$captureResources && ![dict exists $r display_cache] && [dict get $r token] ne {} && $st($w,document) ne {}} {
            if {[catch {::GX::curveSourceDisplayCacheStore $st($w,document) [dict get $r token] $id} cache]} {
                set st($w,status) "Display cache unavailable; canonical source remains active: $cache"
            } else {
                dict set r display_cache $cache
                dict set st($w,records) $id display_cache $cache
            }
        }
        lappend records [dict remove $r token native display status]
    }
    set payload [dict create version 1 records $records next $st($w,next) presentation [::GX::Native2D::core presentation $st($w,scene)] view_requested [::GX::Native2D::core view_requested $st($w,scene)]]
    set view [dict get $payload view_requested];lset view 0 1280;lset view 1 720
    dict set payload view_requested $view
    dict set payload selected_ids [$w.sources selection]
    dict set payload label_preferences $st($w,labelPreferences)
    return $payload
}
proc ::GX::CurveViewer::_currentWorkspace {w} {variable st;return $st($w,document)}
proc ::GX::CurveViewer::_save {w {description {Save Viewer state}}} {
    variable st
    if {[info exists st($w,restoring)] && $st($w,restoring)} return
    if {[info exists st($w,incomplete)] && $st($w,incomplete)} return
    if {$st($w,document) eq {}} {_writePayload $w [_payload $w]}
    if {[dict exists $::GX::ScientificHistory::viewers $w]} {
        if {$st($w,document) ne {}} {::GX::scientificHistoryViewerBindDocument $w $st($w,document)}
        if {![::GX::scientificHistoryViewerEditable $w]} return
        return [::GX::scientificHistoryViewerRecordOperation $w $description]
    }
    set payload [_payload $w]
    _writePayload $w $payload
}
proc ::GX::CurveViewer::_writePayload {w payload} {
    variable st
    if {$st($w,document) eq {}} {
        set name $st($w,workspaceName)
        if {$name eq {}} {set name "Curve Viewer [clock clicks]"}
        set doc [::GX::sessionWorkspaceCreate curve_viewer $name $payload]
        set st($w,document) [dict get $doc workspace_id]
    } else {
        set current [::GX::interactiveDocumentRead $st($w,document)]
        if {[dict get $current module_id] ne "viewer.curve_viewer" || [dict get $current generation] ne $st($w,documentGeneration) || ([dict get $current revision] ne $st($w,documentRevision) && [dict remove [dict get $current payload] workspace_metadata] ne $st($w,savedPayload))} {error {Workspace changed in another editor; reopen before saving}}
        ::GX::sessionWorkspacePromote $st($w,document)
        ::GX::sessionWorkspaceUpdate $st($w,document) $payload
    }
    set doc [::GX::interactiveDocumentRead $st($w,document)]
    set st($w,documentRevision) [dict get $doc revision];set st($w,documentGeneration) [dict get $doc generation]
    set st($w,savedPayload) [dict remove [dict get $doc payload] workspace_metadata]
    ::GX::sessionWorkspaceViewerTitlesRefresh
}
proc ::GX::CurveViewer::_close {w {saveChanges 1}} {
    variable st
    _sourceCancel $w
    if {[info exists st($w,configurationSubscription)]} {::GX::configurationUnsubscribe $st($w,configurationSubscription)}
    if {$saveChanges && ![catch {set token [::GX::interactiveDocumentSessionToken]}]&&$token eq $st($w,session_token)} {_save $w;if {[dict exists $::GX::ScientificHistory::viewers $w]} {::GX::scientificHistoryViewerFlush $w}}
    ::GX::datasetCatalogUnsubscribe $st($w,subscription)
    dict for {id r} $st($w,records) {if {[dict get $r token] ne ""} {::GX::curveSourceClose [dict get $r token]}}
    ::GX::Native2D::core destroy $st($w,scene)
    array unset st "$w,*";destroy $w
}
proc ::GX::CurveViewer::open {{context {}}} {
    variable st
    package require Tk;::GX::native2DEnsure
    set w .curve_viewer
    set requested [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {$requested ni {{} new}} {
        set workspace [::GX::sessionWorkspaceGet $requested]
        if {[dict get $workspace provider_id] ne "curve_viewer"} {error {Workspace belongs to another Viewer}}
        ::GX::sessionWorkspaceValidate $requested
    }
    if {[winfo exists $w] && $requested ne {} && $requested ne $st($w,document)} {
        set host [::GX::_workspaceHostContext curve_viewer [_workspaceCallbacks $w] $w]
        if {![::GX::sessionWorkspaceHostPrepare $host opening]} {return $w}
        _close $w 0
    }
    if {[winfo exists $w]} {
        raise $w
        if {[dict exists $context dataset_id]} {set st($w,preferred) [dict get $context dataset_id]}
        return $w
    }
    set st($w,scene) [::GX::Native2D::core scene];set st($w,records) {};set st($w,next) 0
    set st($w,labelPreferences) [_labelValidate [dict get [::GX::configurationResolve modules.curve_viewer.labels] effective]]
    set st($w,workspaceName) [::GX::datasetPublicationV2DictDefault $context workspace_name {}]
    set st($w,sourceQueue) {};set st($w,sourceLoaded) {};set st($w,sourceEpoch) [incr ::GX::CurveViewer::sourceEpoch];set st($w,editing) {}
    set st($w,document) "";set st($w,session_token) [::GX::interactiveDocumentSessionToken];set st($w,sourceJob) ""
    set st($w,preferred) [::GX::datasetPublicationV2DictDefault $context dataset_id ""]
    set st($w,status) "Add one or more Dataset curves. Display sampling does not alter scientific data.";set st($w,pan) {};set st($w,coordinates) ""
    toplevel $w;wm title $w "Curve Viewer";wm geometry $w 1320x850;wm minsize $w 720 480
    wm protocol $w WM_DELETE_WINDOW [list ::GX::sessionWorkspaceViewerAction curve_viewer [_workspaceCallbacks $w] $w close]
    ttk::frame $w.toolbar;pack $w.toolbar -fill x -padx 5 -pady 5
    ttk::menubutton $w.toolbar.workspace -text Workspace -menu $w.toolbar.workspace.menu
    menu $w.toolbar.workspace.menu -tearoff 0
    ::GX::sessionWorkspaceViewerMenu $w.toolbar.workspace.menu curve_viewer [_workspaceCallbacks $w] $w

    foreach {key label command} [list add "Add curve…" [list _sourceOpen $w] filters "Source filters…" [list _sourceEdit $w] fit_selected "Fit selected" [list _fit $w 1] fit_all "Fit all" [list _fit $w 0] show "Show" [list _visibility $w 1] hide "Hide" [list _visibility $w 0] remove "Remove from view" [list _remove $w] preview "Dataset Preview" [list _preview $w] properties "Curve style…" [list _properties $w] presentation "Grid / view…" [list _presentation $w] export "Export…" [list _export $w] save "Save view" [list _save $w]] {
        ttk::button $w.toolbar.$key -text $label -command [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::[lindex $command 0] {*}[lrange $command 1 end]]]
        pack $w.toolbar.$key -side left -padx 3
    }
    _publishAvailability $w
    bind $w <FocusIn> [list ::GX::CurveViewer::_publishAvailability $w]
    _menus $w
    ttk::label $w.status -textvariable ::GX::CurveViewer::st($w,status) -wraplength 1200
    pack $w.status -side bottom -fill x -padx 8 -pady 4
    ttk::label $w.coordinates -textvariable ::GX::CurveViewer::st($w,coordinates);pack $w.coordinates -side bottom -fill x -padx 8
    ttk::frame $w.browser;pack $w.browser -fill x -padx 8
    ttk::treeview $w.sources -columns {name dataset variables rows status} -show headings -height 5 -selectmode extended
    foreach {key title width} {name Curve 200 dataset {Dataset ID} 210 variables {Variables / units} 350 rows {Exact rows} 110 status Status 160} {$w.sources heading $key -text $title;$w.sources column $key -width $width -stretch 1}
    ttk::scrollbar $w.browser.x -orient horizontal -command [list $w.sources xview]
    ttk::scrollbar $w.browser.y -orient vertical -command [list $w.sources yview]
    $w.sources configure -xscrollcommand [list $w.browser.x set] -yscrollcommand [list $w.browser.y set]
    pack $w.browser.x -side bottom -fill x;pack $w.browser.y -side right -fill y;pack $w.sources -in $w.browser -fill both -expand 1
    canvas $w.canvas -highlightthickness 0 -background white;pack $w.canvas -fill both -expand 1 -padx 8 -pady 4
    bind $w.sources <<TreeviewSelect>> [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::_select $w]]
    bind $w.canvas <Configure> [list ::GX::CurveViewer::_safe $w [list ::GX::CurveViewer::_redraw $w]]
    bind $w.canvas <Button-4> [list ::GX::CurveViewer::_zoom $w .85 %x %y]
    bind $w.canvas <Button-5> [list ::GX::CurveViewer::_zoom $w 1.18 %x %y]
    bind $w.canvas <ButtonPress-1> [list ::GX::CurveViewer::_legendPress $w %x %y %s]
    bind $w.canvas <Button-3> [list ::GX::CurveViewer::_legendContext $w %x %y %X %Y]
    bind $w.canvas <B1-Motion> [list ::GX::CurveViewer::_panMove $w %x %y]
    bind $w.canvas <ButtonRelease-1> [list ::GX::CurveViewer::_panUp $w]
    bind $w.canvas <Motion> [list ::GX::CurveViewer::_coordinates $w %x %y]
    bind $w <Escape> [list set ::GX::CurveViewer::st($w,pan) {}]
    set st($w,subscription) [::GX::datasetCatalogSubscribe [list ::GX::CurveViewer::_catalogChanged $w]]
    set documents [::GX::interactiveDocumentList viewer.curve_viewer curve_viewer]
    if {$requested eq "new"} {set documents {}} elseif {$requested ne {}} {set documents [list [::GX::interactiveDocumentRead $requested]]}
    if {$documents ne {}} {
        set doc [::GX::interactiveDocumentRead [dict get [lindex $documents 0] id]];set payload [dict get $doc payload]
        if {[dict get $payload version]!=1} {error "Unsupported Curve Viewer document"}
        set st($w,document) [dict get $doc id]
        set st($w,documentRevision) [dict get $doc revision];set st($w,documentGeneration) [dict get $doc generation]
        set st($w,savedPayload) [dict remove [dict get $doc payload] workspace_metadata]
        _restoreStart $w $payload
    }
    # An empty named draft is not a saved Document until Save or a real edit.
    if {![info exists st($w,restoring)] || !$st($w,restoring)} {_historyAttach $w}
    ::GX::sessionWorkspaceViewerTitle $w {Curve Viewer} [list ::GX::CurveViewer::_currentWorkspace $w] [list set ::GX::CurveViewer::st($w,workspaceName)]
    return $w
}
proc ::GX::CurveViewer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported Curve Viewer action"}
    return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]
}
::GX::viewerBackendRegister curve_viewer_tk ::GX::CurveViewer::viewerDispatch

source [file join [file dirname [info script]] curve_viewer_settings.tcl]
source [file join [file dirname [info script]] curve_viewer_integrated.tcl]
