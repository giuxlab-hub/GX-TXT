# SPDX-License-Identifier: GPL-3.0-or-later
# Additive workspace around the existing fitter, selection and numeric methods.
proc ::GX::DatasetCurveFit::_workspaceCapture {key} {
    variable state
    if {$state($key,activeSource) eq ""} return
    set saved {}
    foreach field {source selectionScene selectionObject accepted preview previewAccepted previewFitId rows dataset x y filters loadedBinding sourceSha sourceKind rects viewBounds model scope domain min max samples degree initial period smoothing orientation topology parameterization parameterVariable userPeriod closureTolerance polarFrame sourceToken sourceDescriptor sourceTransformManifest sourceIdentities sourceStatus sourceError savedSelection sourcePointCount} {
        if {[info exists state($key,$field)]} {dict set saved $field $state($key,$field)}
    }
    # Dataset chooser edits prepare a new input; they never rewrite the source
    # identity belonging to an already loaded curve or its accepted fits.
    lassign $state($key,loadedBinding) dataset x y filters
    foreach field {dataset x y filters} {dict set saved $field [set $field]}
    if {$state($key,source) ne ""} {
        dict set saved sourceStyle [::GX::Native2D::core object_style $state($key,scene) $state($key,source)]
    } elseif {[dict exists $state($key,sources) $state($key,activeSource) state sourceStyle]} {
        dict set saved sourceStyle [dict get $state($key,sources) $state($key,activeSource) state sourceStyle]
    }
    if {[dict exists $saved sourceDescriptor source_id]} {dict set saved scientific_source_id [dict get $saved sourceDescriptor source_id]}
    dict set state($key,sources) $state($key,activeSource) state $saved
}
proc ::GX::DatasetCurveFit::workspaceSources {key} {
    variable state
    _workspaceCapture $key
    set result {}
    dict for {id entry} $state($key,sources) {
        set source [dict get $entry state]
        dict set result $id [dict create source_curve_id $id source_kind [dict get $source sourceKind] source_identity [dict get $source dataset] x_variable_id [dict get $source x] y_variable_id [dict get $source y] filters [dict get $source filters] visible [dict get $entry visible] active [expr {$id eq $state($key,activeSource)}] point_count [::GX::datasetPublicationV2DictDefault $source sourcePointCount [llength [dict get $source rows]]] status [::GX::datasetPublicationV2DictDefault $source sourceStatus ready] diagnostic [::GX::datasetPublicationV2DictDefault $source sourceError ""]]
    }
    return $result
}
proc ::GX::DatasetCurveFit::activateSource {key id} {
    variable state
    if {![dict exists $state($key,sources) $id]} {error "Unknown source curve '$id'"}
    if {$id eq $state($key,activeSource)} return
    _workspaceCapture $key
    dict for {field value} [dict get $state($key,sources) $id state] {set state($key,$field) $value}
    set state($key,activeSource) $id
    if {[llength [info commands winfo]] && [winfo exists $key.workspace.sources]} {
        set available [expr {$state($key,source) ne ""&&$state($key,sourceStatus) eq "ready"}]
        if {$state($key,sourceKind) eq "dataset"&&$available} {
            set state($key,schema) [variables $state($key,dataset)];_uiVariableChoices $key
        } elseif {$state($key,sourceKind) in {sample builtin_sample}} {set state($key,sample) $state($key,dataset)}
        $key.filters delete 0 end
        foreach filter $state($key,filters) {$key.filters insert end "[dict get $filter variable] [dict get $filter operator] [join [dict get $filter value] ,]"}
        $key.residuals delete [$key.residuals children {}]
        $key.actions.preview configure -state [expr {$available ? "normal" : "disabled"}]
        $key.actions.export configure -state normal
        $key.actions.accept configure -state [expr {$available&&$state($key,preview) ne {}&&!$state($key,previewAccepted) ? "normal" : "disabled"}]
        $key.actions.publish configure -state [expr {$available&&$state($key,preview) ne {} ? "normal" : "disabled"}]
        set state($key,status) [expr {$available ? "Active source: $id · $state($key,dataset). Accepted curves keep their original source ownership." : "Source $id is $state($key,sourceStatus): $state($key,sourceError). Use Reload active source after restoring or updating its Dataset."}]
        _workspaceRefresh $key;_orientationLabels $key;_uiModelFields $key;_uiDomainFields $key;redraw $key
    }
}
proc ::GX::DatasetCurveFit::setSourceVisible {key id visible} {
    variable state
    if {![dict exists $state($key,sources) $id]} {error "Unknown source curve '$id'"}
    set object [dict get $state($key,sources) $id state source]
    if {$object ne ""} {::GX::Native2D::core visible $state($key,scene) $object $visible}
    dict set state($key,sources) $id visible [expr {!!$visible}]
    _workspaceRefresh $key
}
proc ::GX::DatasetCurveFit::_workspaceRefresh {key} {
    variable state
    if {![llength [info commands winfo]] || ![winfo exists $key.workspace.sources]} return
    set tree $key.workspace.sources
    foreach item [$tree children {}] {if {![dict exists $state($key,sources) $item]} {$tree delete $item}}
    dict for {id entry} $state($key,sources) {
        set r [dict get $entry state]
        set availability [::GX::datasetPublicationV2DictDefault $r sourceStatus ready]
        set values [list $id [dict get $r sourceKind] [dict get $r dataset] "[dict get $r x] / [dict get $r y]" [::GX::datasetPublicationV2DictDefault $r sourcePointCount [llength [dict get $r rows]]] "$availability · [expr {[dict get $entry visible] ? "shown" : "hidden"}]"]
        if {[$tree exists $id]} {$tree item $id -values $values} else {$tree insert {} end -id $id -values $values}
    }
    if {$state($key,activeSource) ne ""} {$tree focus $state($key,activeSource)}
    if {![info exists state($key,loading)]||!$state($key,loading)} {
        set enabled [expr {$state($key,activeSource) ne ""&&$state($key,sourceKind) eq "dataset"&&$state($key,sourceStatus) eq "ready" ? "normal" : "disabled"}]
        foreach button {reverse span} {if {[winfo exists $key.workspace.actions.$button]} {$key.workspace.actions.$button configure -state $enabled}}
        if {[winfo exists $key.workspace.actions.reload]} {$key.workspace.actions.reload configure -state [expr {$state($key,activeSource) ne "" ? "normal" : "disabled"}]}
    }
}
proc ::GX::DatasetCurveFit::_workspaceSelect {w} {
    variable state
    if {[info exists state($w,loading)]&&$state($w,loading)} return
    set id [$w.workspace.sources focus]
    if {$id ne "" && $id in [$w.workspace.sources selection]} {activateSource $w $id}
}
proc ::GX::DatasetCurveFit::_workspaceCatalog {w receipt} {
    variable state
    if {![info exists state($w,sources)]} return
    set ids [::GX::datasetPublicationV2DictDefault $receipt dataset_ids {}]
    if {![info exists state($w,catalogPendingIds)]} {set state($w,catalogPendingIds) {}}
    set state($w,catalogPendingIds) [lsort -unique [concat $state($w,catalogPendingIds) $ids]]
    if {[info exists state($w,catalogAfter)]&&$state($w,catalogAfter) ne ""} return
    set state($w,catalogAfter) [after idle [list ::GX::DatasetCurveFit::_workspaceHealth $w]]
}
proc ::GX::DatasetCurveFit::_workspaceHealth {w} {
    variable state
    if {![info exists state($w,sources)]} return
    set state($w,catalogAfter) ""
    if {[info exists state($w,loading)]&&$state($w,loading)} {
        set state($w,catalogAfter) [after 100 [list ::GX::DatasetCurveFit::_workspaceHealth $w]];return
    }
    set ids $state($w,catalogPendingIds);set state($w,catalogPendingIds) {}
    if {[catch {::GX::interactiveDocumentSessionToken} currentToken]||$state($w,sessionToken) ne $currentToken} {
        set state($w,status) "Session changed; reopen Curve Fit to use the current Session."
        foreach button {preview accept publish} {$w.actions.$button configure -state disabled}
        return
    }
    _workspaceCapture $w
    dict for {id entry} $state($w,sources) {
        set saved [dict get $entry state]
        if {[dict get $saved sourceKind] ne "dataset"||[dict get $saved dataset] ni $ids||[dict get $saved sourceStatus] ne "ready"} continue
        if {[catch {::GX::curveSourceDescribe [dict get $saved sourceToken]} diagnostic]} {
            set status [expr {[dict get $saved dataset] in [::GX::datasetRegistryIds] ? "stale" : "missing"}]
            dict set state($w,sources) $id state sourceStatus $status
            dict set state($w,sources) $id state sourceError $diagnostic
            if {$id eq $state($w,activeSource)} {
                set state($w,sourceStatus) $status;set state($w,sourceError) $diagnostic
                set state($w,status) "Source $id is $status: $diagnostic. Use Reload active source. Accepted curves retain their original provenance."
                foreach button {preview accept publish} {$w.actions.$button configure -state disabled}
            }
        }
    }
    _workspaceRefresh $w
}
proc ::GX::DatasetCurveFit::_workspaceShow {w visible} {
    foreach id [$w.workspace.sources selection] {setSourceVisible $w $id $visible}
    redraw $w;_saveState $w
}
proc ::GX::DatasetCurveFit::_unavailableSource {key entry diagnostic} {
    variable state
    _workspaceCapture $key
    if {$state($key,activeSource) eq ""} {::GX::Native2D::core destroy $state($key,selectionScene)}
    set saved [dict get $entry state];set id [dict get $entry id]
    if {![dict exists $saved polarFrame]} {dict set saved polarFrame [_defaultPolarFitFrame $state($key,scene)]}
    dict set saved savedSelection [::GX::datasetPublicationV2DictDefault $saved selection_state {}]
    foreach field {source selectionObject accepted previewFitId sourceToken} {dict set saved $field ""}
    foreach field {rows preview sourceDescriptor rects} {dict set saved $field {}}
    dict set saved selectionScene [::GX::Native2D::core scene]
    dict set saved previewAccepted 0
    dict set saved loadedBinding [list [dict get $saved dataset] [dict get $saved x] [dict get $saved y] [dict get $saved filters]]
    dict set saved sourceStatus [expr {[dict get $saved sourceKind] eq "dataset"&&[dict get $saved dataset] ni [::GX::datasetRegistryIds] ? "missing" : "stale"}]
    dict set saved sourceError $diagnostic
    dict set saved sourcePointCount [::GX::datasetPublicationV2DictDefault $saved sourcePointCount 0]
    dict set entry state $saved;dict set state($key,sources) $id $entry
    dict for {field value} $saved {set state($key,$field) $value}
    set state($key,activeSource) $id
}
proc ::GX::DatasetCurveFit::reloadSource {key id} {
    variable state
    _assertSession $key
    _workspaceCapture $key
    if {![dict exists $state($key,sources) $id]} {error "Unknown source curve '$id'"}
    set previous [dict get $state($key,sources) $id];set saved [dict get $previous state]
    if {[::GX::Native2D::core drag_active $state($key,scene)]||[::GX::Native2D::core drag_active [dict get $saved selectionScene]]} {error "Finish or cancel the current gesture before reloading"}
    if {[dict get $saved sourceKind] in {sample builtin_sample}} {loadSample $key [dict get $saved dataset]} else {
        loadSource $key [dict get $saved dataset] [dict get $saved x] [dict get $saved y] [dict get $saved filters] [::GX::datasetPublicationV2DictDefault $saved sourceTransformManifest {}]
    }
    # Loading completes before retiring the old input. Accepted curves keep the
    # same stable owner ID and frozen model/provenance; no automatic refitting.
    set created $state($key,activeSource)
    removeSources $key [list $id]
    set replacement [dict get $state($key,sources) $created]
    dict unset state($key,sources) $created
    dict set replacement id $id;dict set replacement visible [dict get $previous visible]
    foreach field {model scope domain min max samples degree initial period smoothing orientation topology parameterization parameterVariable userPeriod closureTolerance polarFrame viewBounds sourceStyle} {
        if {[dict exists $saved $field]} {dict set replacement state $field [dict get $saved $field]}
    }
    if {[dict exists $saved sourceStyle]} {::GX::Native2D::core object_style $state($key,scene) $state($key,source) [dict get $saved sourceStyle]}
    dict set state($key,sources) $id $replacement
    set state($key,activeSource) "";activateSource $key $id
    setSourceVisible $key $id [dict get $previous visible]
    _workspaceCapture $key
    return $id
}
proc ::GX::DatasetCurveFit::_workspaceReload {w} {
    variable state
    if {$state($w,activeSource) eq ""} {error "Select a source curve to reload"}
    set controls [_operationBegin $w]
    try {set id [reloadSource $w $state($w,activeSource)]} finally {_operationEnd $w $controls}
    set state($w,report) "";$w.residuals delete [$w.residuals children {}]
    $w.actions.preview configure -state normal
    $w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    _workspaceRefresh $w;_saveState $w;redraw $w
    set state($w,status) "Reloaded $id from its current source. Point selection and preview were reset; accepted curves retain their original provenance."
}
proc ::GX::DatasetCurveFit::removeSources {key ids} {
    variable state
    _assertSession $key
    if {$ids eq {}||[llength $ids]!=[llength [lsort -unique $ids]]} {error "Choose distinct sources to remove"}
    _workspaceCapture $key
    if {[::GX::Native2D::core drag_active $state($key,scene)]} {error "Finish or cancel the active gesture before removing sources"}
    foreach id $ids {
        if {![dict exists $state($key,sources) $id]} {error "Source '$id' no longer exists"}
        set saved [dict get $state($key,sources) $id state]
        if {[dict get $saved source] ne ""} {::GX::Native2D::core kind $state($key,scene) [dict get $saved source]}
        if {[::GX::Native2D::core drag_active [dict get $saved selectionScene]]} {error "Finish or cancel the active selection gesture before removing sources"}
    }
    set activeRemoved [expr {$state($key,activeSource) in $ids}]
    foreach id $ids {
        set saved [dict get $state($key,sources) $id state]
        _disposeReport $state($key,scene) [dict get $saved preview]
        if {[dict get $saved sourceToken] ne ""} {::GX::curveSourceClose [dict get $saved sourceToken]}
        if {[dict get $saved source] ne ""} {::GX::Native2D::core delete $state($key,scene) [dict get $saved source]}
        ::GX::Native2D::core destroy [dict get $saved selectionScene]
        dict unset state($key,sources) $id
    }
    if {$activeRemoved} {
        set state($key,activeSource) ""
        if {[dict size $state($key,sources)]} {
            activateSource $key [lindex [dict keys $state($key,sources)] 0]
        } else {
            set state($key,selectionScene) [::GX::Native2D::core scene]
            foreach field {source selectionObject accepted previewFitId sourceToken sourceSha sourceKind} {set state($key,$field) ""}
            foreach field {preview rows filters loadedBinding sourceDescriptor sourceTransformManifest sourceIdentities rects viewBounds} {set state($key,$field) {}}
            set state($key,previewAccepted) 0
        }
    }
    _workspaceRefresh $key
    return $ids
}
proc ::GX::DatasetCurveFit::_workspaceRemove {w} {
    variable state
    set ids [$w.workspace.sources selection]
    if {$ids eq {}&&$state($w,activeSource) ne ""} {set ids [list $state($w,activeSource)]}
    set removed [removeSources $w $ids]
    set state($w,report) "";$w.residuals delete [$w.residuals children {}]
    $w.actions.preview configure -state [expr {$state($w,source) ne "" ? "normal" : "disabled"}]
    $w.actions.accept configure -state disabled;$w.actions.publish configure -state disabled
    _saveState $w;redraw $w
    set state($w,status) "Removed [llength $removed] local source curves; accepted curves and their frozen provenance remain available."
}
proc ::GX::DatasetCurveFit::setSourceStyle {key ids changes} {
    variable state
    _assertSession $key
    if {$ids eq {}||[llength $ids]!=[llength [lsort -unique $ids]]} {error "Choose distinct source curve IDs"}
    foreach field [dict keys $changes] {if {$field ni {color line_width line_style marker}} {error "Unsupported source presentation field '$field'"}}
    foreach id $ids {
        if {![dict exists $state($key,sources) $id]} {error "Source '$id' no longer exists"}
        if {[dict get $state($key,sources) $id state source] eq ""} {error "Source '$id' is unavailable; reload it before changing its style"}
    }
    if {[::GX::Native2D::core drag_active $state($key,scene)]} {error "Finish or cancel the active gesture before changing source style"}
    foreach id $ids {
        set object [dict get $state($key,sources) $id state source]
        dict set state($key,sources) $id state sourceStyle [::GX::Native2D::core object_style $state($key,scene) $object $changes]
    }
    _workspaceCapture $key
}
proc ::GX::DatasetCurveFit::_workspaceStyle {w} {
    variable state
    set ids [$w.workspace.sources selection]
    if {$ids eq {}} {set ids [list $state($w,activeSource)]}
    if {[lindex $ids 0] eq ""} {error "Load a source curve first"}
    set style [::GX::Native2D::core object_style $state($w,scene) [dict get $state($w,sources) [lindex $ids 0] state source]]
    set fields [dict create color [dict create type color alpha 1 label {Source color and opacity} default #1F61D1] width [dict create type number label {Line width (pixels)} min 0.5 max 16 required 1] pattern [dict create type choice label {Line pattern} values {Solid Dashed Dotted}]]
    set values [dict create color [::GX::uiFieldColorFromRGBA [dict get $style color]] width [dict get $style line_width] pattern [lindex {Solid Dashed Dotted} [dict get $style line_style]]]
    ::GX::uiFieldFormCreate $w.sourceStyle "Style selected sources" $fields $values [list ::GX::DatasetCurveFit::_workspaceStyleApply $w $ids] $w
}
proc ::GX::DatasetCurveFit::_workspaceStyleApply {w ids values} {
    variable state
    setSourceStyle $w $ids [dict create color [::GX::uiFieldColorToRGBA [dict get $values color]] line_width [dict get $values width] line_style [lsearch -exact {Solid Dashed Dotted} [dict get $values pattern]]]
    _saveState $w;redraw $w
    set state($w,status) "Source presentation updated. Scientific data and fits are unchanged."
}
proc ::GX::DatasetCurveFit::previewSources {key ids model scope domain {degree 2} {initial {}} {options {}}} {
    variable state
    if {$ids eq {}||[llength $ids]!=[llength [lsort -unique $ids]]} {error "Batch targets must contain distinct source curve IDs"}
    _workspaceCapture $key
    set active $state($key,activeSource);set pending {};set before {}
    foreach id $ids {
        if {![dict exists $state($key,sources) $id]} {error "Unknown source curve '$id'"}
        dict set before $id [dict get $state($key,sources) $id state]
    }
    set state($key,deferDispose) 1
    try {
        foreach id $ids {
            activateSource $key $id
            dict set pending $id [preview $key $model $scope $domain $degree $initial $options]
            _workspaceCapture $key
        }
    } on error {message options} {
        foreach report [dict values $pending] {_disposeReport $state($key,scene) $report}
        dict for {id saved} $before {dict set state($key,sources) $id state $saved}
        # Prevent activateSource from recapturing a failed partial preview.
        set state($key,activeSource) ""
        return -options $options $message
    } finally {
        set state($key,deferDispose) 0
        if {$active ne ""} {activateSource $key $active}
    }
    foreach saved [dict values $before] {_disposeReport $state($key,scene) [dict get $saved preview]}
    return $pending
}
proc ::GX::DatasetCurveFit::acceptSources {key ids} {
    variable state
    if {$ids eq {}||[llength $ids]!=[llength [lsort -unique $ids]]} {error "Batch targets must contain distinct source curve IDs"}
    _workspaceCapture $key
    foreach id $ids {
        if {![dict exists $state($key,sources) $id] || [dict get $state($key,sources) $id state preview] eq {} || [dict get $state($key,sources) $id state previewAccepted]} {error "Source '$id' needs an unaccepted preview"}
    }
    set active $state($key,activeSource);set accepted {};set saved $state($key,sources)
    set records $state($key,records)
    try {
        foreach id $ids {activateSource $key $id;lappend accepted [accept $key];_workspaceCapture $key}
    } on error {message options} {
        foreach id $accepted {::GX::Native2D::core delete $state($key,scene) $id}
        set state($key,sources) $saved;set state($key,records) $records;set state($key,activeSource) ""
        return -options $options $message
    } finally {if {$active ne ""} {activateSource $key $active}}
    return $accepted
}
proc ::GX::DatasetCurveFit::_workspaceBatch {w accept} {
    variable state
    set ids [$w.workspace.sources selection]
    if {$ids eq {}} {error "Select one or more source curves in the workspace"}
    if {$accept} {set result [acceptSources $w $ids];_refreshFits $w;set state($w,status) "Accepted [llength $result] local CORE curves; publish Datasets explicitly."} else {
        set domain source
        if {$state($w,domain) eq "range"} {set domain [list $state($w,min) $state($w,max) $state($w,samples)]}
        if {$state($w,domain) eq "parameter"} {set domain [list parameter $state($w,min) $state($w,max) $state($w,samples)]}
        set initial {};foreach value [split $state($w,initial) ,] {if {[string trim $value] ne ""} {lappend initial [string trim $value]}}
        set controls [_operationBegin $w]
        try {set result [previewSources $w $ids $state($w,model) $state($w,scope) $domain $state($w,degree) $initial [_uiFitOptions $w]]} finally {_operationEnd $w $controls}
        set state($w,status) "Previewed [dict size $result] independent source curves with the same model settings."
    }
    _workspaceCapture $w;_saveState $w;redraw $w
}
proc ::GX::DatasetCurveFit::_workspaceGui {w} {
    ttk::frame $w.workspace -padding 5;pack $w.workspace -fill x
    ttk::treeview $w.workspace.sources -columns {id kind identity variables rows visible} -show headings -height 3 -selectmode extended
    foreach {column label width} {id Curve 90 kind Kind 120 identity {Source ID} 220 variables {X / Y} 240 rows {Display points} 110 visible Status 100} {$w.workspace.sources heading $column -text $label;$w.workspace.sources column $column -width $width}
    ttk::scrollbar $w.workspace.scroll -orient horizontal -command [list $w.workspace.sources xview]
    $w.workspace.sources configure -xscrollcommand [list $w.workspace.scroll set]
    pack $w.workspace.sources -fill x;pack $w.workspace.scroll -fill x
    ttk::frame $w.workspace.actions;pack $w.workspace.actions -fill x
    foreach {id label command} [list show Show [list _workspaceShow $w 1] hide Hide [list _workspaceShow $w 0] style "Style sources…" [list _workspaceStyle $w] remove "Remove sources" [list _workspaceRemove $w] reload "Reload active source" [list _workspaceReload $w] preview "Fit selected curves" [list _workspaceBatch $w 0] accept "Accept all selected previews" [list _workspaceBatch $w 1] reverse "Reverse whole to new source" [list _uiReverseSource $w 0] span "Reverse span to new source" [list _uiReverseSource $w 1]] {
        ttk::button $w.workspace.actions.$id -text $label -command [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::[lindex $command 0] {*}[lrange $command 1 end]]]
        if {$id in {reverse span}} {$w.workspace.actions.$id configure -state disabled}
        pack $w.workspace.actions.$id -side left -padx 5
    }
    bind $w.workspace.sources <<TreeviewSelect>> [list ::GX::DatasetCurveFit::_uiSafe $w [list ::GX::DatasetCurveFit::_workspaceSelect $w]]
}

proc ::GX::DatasetCurveFit::_saveState {key} {
    variable state
    if {[info exists state($key,restoringWorkspace)] && $state($key,restoringWorkspace)} return
    if {$state($key,sessionToken) eq ""} return
    if {$state($key,activeSource) eq ""&&$state($key,records) eq {}&&$state($key,documentId) eq "" && (![info exists state($key,openingWorkspace)] || $state($key,openingWorkspace) ne "new")} return
    if {$state($key,sessionToken) ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen Curve Fit"}
    _workspaceCapture $key
    set sources {}
    dict for {id entry} $state($key,sources) {
        set source [dict get $entry state]
        if {[dict get $source selectionObject] ne ""} {
            dict set source selected [::GX::Native2D::core selected [dict get $source selectionScene] [dict get $source selectionObject]]
            dict set source selection_state [::GX::Native2D::core selection_state [dict get $source selectionScene] [dict get $source selectionObject] 0 [llength [dict get $source rows]]]
        } else {dict set source selection_state [::GX::datasetPublicationV2DictDefault $source savedSelection {}];dict set source selected {}}
        dict set entry state [dict remove $source source selectionScene selectionObject accepted preview previewAccepted previewFitId rows rects sourceToken sourceDescriptor]
        lappend sources $entry
    }
    set records {};set cached {}
    foreach record $state($key,records) {
        if {[dict exists $record point_count]&&[dict get $record point_count]>[llength [dict get $record points]]} {
            if {$state($key,documentId) eq ""} {error "Large accepted curves need a Session-owned Interactive Document"}
            if {![dict exists $record geometry_resource]} {dict set record geometry_resource [::GX::interactiveDocumentNative2DStore $state($key,documentId) $state($key,scene) [dict get $record id] [dict create source_curve_id [dict get $record source_curve_id] fit_curve_id [dict get $record fit_curve_id]]]}
        }
        lappend cached $record
        lappend records [dict remove $record id]
    }
    set state($key,records) $cached
    set payload [dict create version 2 workspace_sources $sources active_source $state($key,activeSource) next_source $state($key,nextSource) next_fit $state($key,nextFit) records $records presentation [::GX::Native2D::core presentation $state($key,scene)] view_bounds $state($key,viewBounds)]
    dict set payload panel [dict create visible $state($key,showResiduals) fraction $state($key,residualFraction)]
    if {$state($key,documentId) eq {}} {
        set name [expr {[info exists state($key,workspaceName)] && $state($key,workspaceName) ne {} ? $state($key,workspaceName) : "Dataset Curve Fit [clock clicks]"}]
        set workspace [::GX::sessionWorkspaceCreate dataset_curve_fit $name $payload]
        set state($key,documentId) [dict get $workspace workspace_id]
    } else {
        set current [::GX::interactiveDocumentRead $state($key,documentId)]
        if {[dict get $current module_id] ne "viewer.dataset_curve_fit"} {error {Document belongs to another Viewer}}
        if {[info exists state($key,documentGeneration)] && [dict get $current generation] ne $state($key,documentGeneration)} {error {Workspace owner was replaced}}
        if {[info exists state($key,documentRevision)] && [dict get $current revision] ne $state($key,documentRevision) && [dict remove [dict get $current payload] workspace_metadata] ne $state($key,savedPayload)} {error {Workspace changed in another editor; reopen before saving}}
        if {[dict get $current format_version] ne "2.0"} {
            if {[dict exists $current payload workspace_metadata]} {dict set payload workspace_metadata [dict get $current payload workspace_metadata]}
            ::GX::interactiveDocumentUpdate $state($key,documentId) $payload {} 2.0
        }
        ::GX::sessionWorkspacePromote $state($key,documentId)
        ::GX::sessionWorkspaceUpdate $state($key,documentId) $payload
    }
    set doc [::GX::interactiveDocumentRead $state($key,documentId)]
    set state($key,documentGeneration) [dict get $doc generation];set state($key,documentRevision) [dict get $doc revision]
    set state($key,savedPayload) [dict remove [dict get $doc payload] workspace_metadata]
    if {[llength [info commands winfo]] && [winfo exists $key]} {wm title $key "Dataset Curve Fit — [dict get [::GX::sessionWorkspaceGet $state($key,documentId)] name]"}
}
proc ::GX::DatasetCurveFit::_restoreState {w requested} {
    variable state
    set state($w,restoringWorkspace) 1
    try {
        set document {}
        if {[info exists state($w,openingWorkspace)] && $state($w,openingWorkspace) eq "new"} return
        set exact [expr {[info exists state($w,openingWorkspace)] ? $state($w,openingWorkspace) : {}}]
        set documents [::GX::interactiveDocumentList viewer.dataset_curve_fit dataset_curve_fit]
        if {$exact ne {}} {set documents [list [::GX::interactiveDocumentRead $exact]];set requested {}}
        foreach item $documents {
            set candidate [::GX::interactiveDocumentRead [dict get $item id]];set payload [dict get $candidate payload]
            if {![dict exists $payload version] || [dict get $payload version]!=2} continue
            set matches [expr {$requested eq ""}]
            foreach entry [dict get $payload workspace_sources] {
                if {[dict get $entry state sourceKind] eq "dataset" && [dict get $entry state dataset] eq $requested} {set matches 1}
            }
            foreach record [dict get $payload records] {
                if {[::GX::datasetPublicationV2DictDefault [dict get $record provenance] source_dataset_id ""] eq $requested} {set matches 1}
            }
            if {$matches} {set document $candidate;break}
        }
        if {$document eq {}} {
            return [_restoreLegacyState $w $requested $exact]
        }
        set state($w,documentId) [dict get $document id]
        set state($w,documentRevision) [dict get $document revision];set state($w,documentGeneration) [dict get $document generation]
        set state($w,savedPayload) [dict remove [dict get $document payload] workspace_metadata]
        set payload [dict get $document payload];set restored {}
        foreach entry [dict get $payload workspace_sources] {
            set saved [dict get $entry state];set id [dict get $entry id]
            if {[catch {
                if {[dict get $saved sourceKind] in {sample builtin_sample}} {loadSample $w [dict get $saved dataset]} else {
                    if {[dict get $saved sourceSha] ne [_datasetSha [dict get $saved dataset]]} {error "Source content changed since this workspace was saved"}
                    loadSource $w [dict get $saved dataset] [dict get $saved x] [dict get $saved y] [dict get $saved filters] [::GX::datasetPublicationV2DictDefault $saved sourceTransformManifest {}] [::GX::datasetPublicationV2DictDefault $saved sourceIdentities {}]
                }
            } diagnostic]} {
                _unavailableSource $w $entry $diagnostic
                lappend restored $id
                continue
            }
            set created $state($w,activeSource);set local [dict get $state($w,sources) $created]
            dict unset state($w,sources) $created
            dict set local id $id;dict set state($w,sources) $id $local;set state($w,activeSource) $id
            foreach field {model scope domain min max samples degree initial period smoothing orientation topology parameterization parameterVariable userPeriod closureTolerance polarFrame viewBounds} {if {[dict exists $saved $field]} {set state($w,$field) [dict get $saved $field]}}
            if {[dict exists $saved sourceStyle]} {::GX::Native2D::core object_style $state($w,scene) $state($w,source) [dict get $saved sourceStyle]}
            if {[dict exists $saved selection_state]} {
                _restoreSelectionDescriptor $w [dict get $saved selection_state]
            } else {foreach index [dict get $saved selected] {selectPoint $w $index add}}
            _workspaceCapture $w;setSourceVisible $w $id [dict get $entry visible]
            lappend restored $id
        }
        foreach record [dict get $payload records] {
            if {[dict exists $record geometry_resource]} {set id [::GX::interactiveDocumentNative2DRestore [dict get $record geometry_resource] $state($w,scene)]} else {set id [::GX::Native2D::core add $state($w,scene) [dict get $record points]]}
            ::GX::Native2D::core style $state($w,scene) $id [dict get $record color] 2.5
            ::GX::Native2D::core visible $state($w,scene) $id [dict get $record visible]
            ::GX::Native2D::core object_style $state($w,scene) $id {locked 1 selectable 0}
            dict set record id $id;lappend state($w,records) $record
            set owner [dict get $record source_curve_id]
            if {[dict exists $state($w,sources) $owner]} {dict set state($w,sources) $owner state accepted $id}
        }
        set active [dict get $payload active_source]
        if {$requested ne ""&&(![dict exists $state($w,sources) $active]||[dict get $state($w,sources) $active state dataset] ne $requested)} {
            foreach id $restored {if {[dict get $state($w,sources) $id state dataset] eq $requested} {set active $id;break}}
        }
        set state($w,activeSource) ""
        if {$active ne ""&&[dict exists $state($w,sources) $active]} {activateSource $w $active}
        set state($w,nextSource) [dict get $payload next_source];set state($w,documentId) [dict get $document id]
        set state($w,nextFit) [::GX::datasetPublicationV2DictDefault $payload next_fit [llength $state($w,records)]]
        set state($w,viewBounds) [dict get $payload view_bounds]
        ::GX::Native2D::core presentation $state($w,scene) [dict get $payload presentation]
        if {[dict exists $payload panel]} {set state($w,showResiduals) [dict get $payload panel visible];set state($w,residualFraction) [dict get $payload panel fraction];_residualPanel $w}
        _workspaceRefresh $w;_refreshFits $w;redraw $w
        set unavailable 0
        foreach entry [dict values $state($w,sources)] {if {[dict get $entry state sourceStatus] ne "ready"} {incr unavailable}}
        set state($w,status) "Restored [llength $restored] source entries and [llength $state($w,records)] accepted local fits. $unavailable unavailable sources require explicit reload."
    } finally {unset -nocomplain state($w,restoringWorkspace)}
}

proc ::GX::DatasetCurveFit::_currentWorkspace {w} {variable state;return $state($w,documentId)}
