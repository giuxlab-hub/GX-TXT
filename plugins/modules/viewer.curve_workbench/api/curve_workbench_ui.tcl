# SPDX-License-Identifier: GPL-3.0-or-later
# UI construction has one owner. Initialize feature state in dependency order,
# then build each surface once. Builders never call preceding UI versions.
proc ::GX::CurveWorkbench::_sketchOpenReviewCheck {guard {checkParent 1}} {
    if {$guard eq {}} return
    set session [dict get $guard session];set dataset [dict get $guard dataset]
    if {[dict get $guard token] ne [::GX::interactiveDocumentSessionToken] || $session ne [_session]} {error {Session changed while reviewing Sketch axes; reopen the Dataset.}}
    if {$checkParent} {
        set parent [dict get $guard parent]
        if {![winfo exists $parent] || [winfo id $parent] ne [dict get $guard incarnation]} {error {Workspace changed while reviewing Sketch axes; reopen the Dataset.}}
    }
    if {[::GX::sessionInspectionDatasetPayload $dataset] ne [dict get $guard source] || [::GX::sketchDatasetRead $session $dataset] ne [dict get $guard sketch]} {error {Sketch source changed while reviewing its axes; reopen the Dataset.}}
}
proc ::GX::CurveWorkbench::_sketchOpenReview {dataset sketch context} {
    # Trusted callers can already supply their explicit creation policy. The
    # ordinary Dataset/Preview Open action supplies only the canonical ID.
    if {[dict exists $context coordinate_configuration]} {return [list 1 $context {}]}
    set example {}
    dict for {id object} [dict get $sketch objects] {
        set units [dict get $object units]
        set metadata [::GX::datasetPublicationV2DictDefault $object metadata {}]
        set frame [::GX::_native2DCoordinateFrame $units [::GX::datasetPublicationV2DictDefault $metadata gx.coordinate_relations {}]]
        set dimensions [_coordinateDimensions $units [dict get $frame coordinate_relations]]
        if {[lindex $dimensions 0] eq [lindex $dimensions 1]} continue
        foreach axis {x y} unit $units {
            set effective [::GX::datasetPublicationV2DictDefault [dict get $frame coordinate_relations] $axis {}]
            set effective [::GX::datasetPublicationV2DictDefault $effective canonical_unit $unit]
            if {$unit eq {}} {set unit {undeclared numeric}}
            if {$effective eq {}} {set effective {undeclared numeric}}
            lappend example "[string toupper $axis]: $unit (effective $effective)"
        }
        break
    }
    if {$example eq {}} {return [list 1 $context {}]}
    set session [_session];set token [::GX::interactiveDocumentSessionToken]
    set source [::GX::sessionInspectionDatasetPayload $dataset]
    set parent [expr {[winfo exists .curve_workbench] ? {.curve_workbench} : {.}}]
    set incarnation [winfo id $parent]
    set guard [dict create session $session token $token dataset $dataset source $source sketch $sketch parent $parent incarnation $incarnation]
    set answer [tk_messageBox -parent $parent -type yesno -default no -icon question -title {Review Sketch coordinate plane} -message "This Sketch contains X and Y quantities with different physical dimensions. Example: [join $example {; }].\n\nEnable Allow dimensionally heterogeneous axes explicitly for its new Workspace? Numeric plane editing does not establish a physical distance or angle between unlike axes. The source Sketch is preserved.\n\nNo leaves the current Workspace unchanged."]
    if {$answer ne {yes}} {return [list 0 $context {}]}
    _sketchOpenReviewCheck $guard
    dict set context coordinate_configuration [dict replace [_coordinateConfigurationDefault] allow_heterogeneous 1]
    return [list 1 $context $guard]
}
proc ::GX::CurveWorkbench::open {{context {}}} {
    variable st;variable openingWorkspace;variable openingName
    set reviewGuard {}
    set sketch [::GX::datasetPublicationV2DictDefault $context sketch_dataset_id {}]
    if {$sketch ne {}} {
        set content [::GX::sketchDatasetRead [_session] $sketch]
        lassign [_sketchOpenReview $sketch $content $context] proceed context reviewGuard
        if {!$proceed} {return [expr {[winfo exists .curve_workbench] ? {.curve_workbench} : {}}]}
        set base "Sketch $sketch draft";set name $base;set names {};set serial 1
        foreach workspace [::GX::sessionWorkspaceList] {lappend names [dict get $workspace name]}
        while {$name in $names} {set name "$base ([incr serial])"}
        dict set context workspace_id new;dict set context workspace_name $name
    }
    if {[dict exists $context planar_document]} {
        set base "3D [dict get $context planar_document] [dict get $context planar_mode]";set name $base;set names {};set serial 1
        foreach workspace [::GX::sessionWorkspaceList] {lappend names [dict get $workspace name]}
        while {$name in $names} {set name "$base ([incr serial])"}
        dict set context workspace_id new;dict set context workspace_name $name
    }
    set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {[winfo exists .curve_workbench]&&$id ne {}&&($id eq "new"||$st(.curve_workbench,document) ne $id)} {
        if {![_replaceDecision .curve_workbench]} {return .curve_workbench}
        # Replacement can ask further Save/discard questions after axis review.
        _sketchOpenReviewCheck $reviewGuard
        _close .curve_workbench
    }
    if {[winfo exists .curve_workbench]} {raise .curve_workbench;return .curve_workbench}
    set openingWorkspace $id
    if {$id ne {}&&$id ne "new"} {
        set openingName [dict get [::GX::sessionWorkspaceGet $id] name]
    } else {
        set openingName [::GX::datasetPublicationV2DictDefault $context workspace_name "Curve Workbench [expr {[llength [::GX::sessionWorkspaceList]]+1}]"]
    }
    try {
        set w [_openWindow $context]
        if {[dict exists $context coordinate_configuration]} {
            if {![_coordinateWorkspaceEmpty $w]} {error {A creation Configuration cannot reinterpret restored geometry}}
            set st($w,coordinateConfiguration) [_coordinateConfigurationNormalize [dict get $context coordinate_configuration]]
            set st($w,sketchUnit) [dict get $st($w,coordinateConfiguration) x_unit]
        }
        # Default viewer opening resolves its persisted document during restore.
        # Its canonical name is available only after that resolution.
        if {$st($w,document) ne {}} {set st($w,workspaceName) [dict get [::GX::sessionWorkspaceGet $st($w,document)] name]}
        _installSourceControls $w
        _installCommandLayout $w
        # Install these after base bindings; resizing must retain host layout
        # invalidation without forcing layout during scientific redraw.
        bind $w.right.viewport.canvas <Configure> +[list after 10 [list ::GX::CurveWorkbench::_responsiveCompare $w]]
        bind $w.right.viewport.canvas <Button-3> [list ::GX::CurveWorkbench::_viewportContext $w %x %y %X %Y]
        after 10 [list ::GX::CurveWorkbench::_responsiveCompare $w]
    } finally {unset openingWorkspace openingName}
    bind $w.right.viewport.canvas <Configure> +[list ::GX::native2DViewportInvalidate $w.right.viewport.canvas]
    ::GX::native2DViewportInvalidate $w.right.viewport.canvas
    _installSelectionCommands $w
    _installRepresentationCommands $w
    _installCommands $w
    _installCommandTools $w
    _installDatasetCommands $w
    _timelineBuild $w
    bind $w.right.viewport.canvas <ButtonPress-2> [list ::GX::CurveWorkbench::_middlePan $w start %x %y]
    bind $w.right.viewport.canvas <B2-Motion> [list ::GX::CurveWorkbench::_middlePan $w move %x %y]
    bind $w.right.viewport.canvas <ButtonRelease-2> [list ::GX::CurveWorkbench::_middlePan $w end %x %y]
    # Never recalculate/save a partially restored document. Keep the original
    # restore cause visible after command installation resets the tool prompt.
    if {[info exists st($w,restoreFailed)]&&$st($w,restoreFailed)} {
        set st($w,status) $st($w,restoreError)
    } elseif {$st($w,document) ne {}} {_parameterRecalculate $w [_parameterBind $w]}
    if {$sketch ne {}} {
        # The reviewed old parent may now be deliberately closed/replaced.
        _sketchOpenReviewCheck $reviewGuard 0
        _datasetImport $w $sketch
        # The window's tables were built before canonical Sketch intake.
        # Project the completed import through the existing selection owners.
        _curveList $w
        _pointList $w
    }
    if {[dict exists $context planar_document]} {_planarIntake $w [dict get $context planar_document] [dict get $context planar_mode]} else {_planarControls $w}
    _coordinateMagnify $w 0
    ::GX::sessionWorkspaceViewerTitle $w {Curve Workbench · planar 2-D} [list set ::GX::CurveWorkbench::st($w,document)] [list set ::GX::CurveWorkbench::st($w,workspaceName)]
    return $w
}

proc ::GX::CurveWorkbench::_cadGui {w} {
    _initWorkbenchState $w
    _buildCad $w
    _buildUnits $w
    _buildRecovery $w
    _buildDocuments $w
    _buildSketchMenu $w
    _buildConstraints $w
    _buildJoin $w
    _buildMeasurements $w
    _buildIdentity $w
    _buildCollections $w
    _buildViews $w
    _buildSeries $w
    _buildExtensions $w
    _buildRoles $w
    _buildExport $w
    _buildComparison $w
    _buildRecipe $w
    _buildConstruction $w
    _buildConstraintTools $w
    _buildCommandMenus $w
    _buildViewport $w
    _buildWorkspace $w
    _buildImages $w
    _buildComparisonActivation $w
}
proc ::GX::CurveWorkbench::_initWorkbenchState {w} {
    variable st
    set st($w,coordinatePresentation) {};set st($w,coordinateCache) {};set st($w,coordinateView) {}
    set st($w,coordinateFrameViews) {}
    set st($w,coordinateConfiguration) [_coordinateConfigurationDefault]
    set st($w,coordinateSubscription) [::GX::datasetCatalogSubscribe [list ::GX::CurveWorkbench::_coordinateCatalogChanged $w]]
    set st($w,comparisonEnabled) 0;set st($w,comparisonConfig) {};set st($w,comparisonRecord) {};set st($w,comparisonText) {Comparison inactive}
    set st($w,constructionPlaces) {};set st($w,chainReferences) {};set st($w,moreControls) 0
    foreach key {constraintTool dimRefs dimSpec dimAnnotation dimExisting annotationDrag selectedRelationship hoverRelationship markerRegions} {set st($w,$key) {}}
    set st($w,showConstraints) 1;set st($w,showDimensions) 1;set st($w,dimForced) {};set st($w,dimDriven) 0
    set st($w,canvasTool) select;set st($w,placements) {};set st($w,toolPreview) {};set st($w,previewDefinition) {};set st($w,handleDrag) {};set st($w,snapCandidate) {};set st($w,sketchSelection) {};set st($w,sketchUnit) mm
    set st($w,toolLabel) {Select — click geometry or defining handles. Ctrl adds; Shift subtracts.}
    set st($w,scientificRecipe) {}
    set st($w,lastGeometricComparison) {};set st($w,comparisonImplicit) 0;set st($w,residualPanelShown) -1
    set st($w,extensionBusy) 0
    set st($w,seriesContainers) {};set st($w,nextSeries) 0
    set st($w,savedViews) {};set st($w,nextSavedView) 0
    foreach {field value} {selectionSets {} nextSelectionSet 0 layers {} layerNative {} nextLayer 0} {set st($w,$field) $value}
    set st($w,sketchAttributes) {};set st($w,sketchFragments) {};set st($w,nextFragment) 0
    set st($w,measurements) {};set st($w,nextMeasurement) 0
    set st($w,joinPending) {}
    set st($w,constraints) {};set st($w,nextConstraint) 0
    set st($w,recoveryNotice) ""
}

proc ::GX::CurveWorkbench::_openWindow {{context {}}} {
    variable st
    package require Tk
    _native
    set w .curve_workbench
    if {[winfo exists $w]} {
        if {$st($w,token) eq [::GX::interactiveDocumentSessionToken]} {raise $w;return $w}
        _close $w
        if {[winfo exists $w]} {error "The previous Session's operation is cancelling; reopen Curve Workbench when it finishes."}
    }
    toplevel $w;wm title $w "Curve Workbench · planar 2-D";::GX::uiFieldWindowFit $w 1520 930
    set st($w,scene) [::GX::Native2D::core scene]
    # A new Workspace starts with useful drawing room. Restoring a saved
    # Workspace below still restores its explicit view and grid preferences.
    ::GX::Native2D::core grid $st($w,scene) [dict create enabled 1 visible 1]
    set initialView [::GX::Native2D::core view_requested $st($w,scene)]
    lset initialView 6 {-10 -10 10 10}
    ::GX::Native2D::core view $st($w,scene) $initialView
    set st($w,selectionScene) "";set st($w,selectionObject) "";set st($w,residualWidget) {};set st($w,residualBinding) {}
    set st($w,selectionEpoch) 0;set st($w,pointSyncAfter) "";set st($w,pointSyncPending) {}
    set st($w,pointSyncRunning) 0;set st($w,pointSyncCommits) 0;set st($w,pointTableSignature) {}
    set st($w,pointPageStart) 0;set st($w,pointPageLabel) "";set st($w,pointPageInput) 1
    set st($w,curves) [dict create];set st($w,active) "";set st($w,next) 0
    set st($w,document) "";set st($w,token) [::GX::interactiveDocumentSessionToken]
    set st($w,publishBusy) 0;set st($w,publishCancelled) 0;set st($w,publishJob) ""
    set st($w,groups) {};set st($w,groupNative) {};set st($w,nextGroup) 0;set st($w,objectSelection) {}
    set st($w,cadGroup) "";set st($w,cadGroupName) Group;set st($w,cadTarget) selected;set st($w,cadTool) none;set st($w,cadDrag) {}
    set st($w,cadObjectSnap) 0
    set st($w,undo) {};set st($w,redo) {};set st($w,fragments) {};set st($w,bridge) 0
    set st($w,bridgeKind) none;set st($w,bridgeSubdivisions) 32;set st($w,bridgeTolerance) 1e-9
    set st($w,previewBuild) {};set st($w,previewSignature) {}
    set st($w,previewNative) "";set st($w,previewBreaks) {}
    set st($w,box) {};set st($w,drag) {};set st($w,residual) {};set st($w,reference) ""
    set st($w,tool) select;set st($w,directionShown) 0;set st($w,gridShown) 1;set st($w,gridSnap) 0;set st($w,compareMethod) x;set st($w,metric) length
    set st($w,target) "";set st($w,externalFeedback) "";set st($w,metricText) "No active curve"
    set st($w,activeLabel) "ACTIVE: none";set st($w,referenceLabel) "";set st($w,referenceMap) [dict create]
    set st($w,rename) "";set st($w,editX) "";set st($w,editY) "";set st($w,xMin) "";set st($w,xMax) ""
    set st($w,composeName) "Composed curve";set st($w,resultId) "edited_curve";set st($w,status) "Add an X/Y Dataset to begin."
    set st($w,preferredDataset) ""
    foreach key {dataset_id source_dataset_id} {if {[dict exists $context $key]} {set st($w,preferredDataset) [dict get $context $key]}}
    # Keep the existing control frames and callbacks; share upper width with
    # Workspace publication actions rather than reserving bottom toolbar rows.
    ttk::frame $w.upper
    pack $w.upper -side top -fill x
    grid columnconfigure $w.upper 0 -weight 1
    ttk::frame $w.toolbar -padding 5
    grid $w.toolbar -in $w.upper -row 0 -column 0 -sticky new
    foreach {key label command} [list add "Add curve…" [list _sourceOpen $w] fit "Fit all" [list _fit $w 0] fitSelected "Fit active" [list _fit $w 1] undo Undo [list undo $w] redo Redo [list redo $w] duplicate Duplicate [list _duplicate $w] split Split [list _split $w] reverse Reverse [list _operation $w reverse] visibility Show/Hide [list _setVisibility $w] lock Lock/Unlock [list _setLock $w] remove "Remove curve" [list _deleteCurve $w]] {
        set command [lreplace $command 0 0 "::GX::CurveWorkbench::[lindex $command 0]"]
        ttk::button $w.toolbar.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $command]
        pack $w.toolbar.$key -side left -padx 2
    }
    ttk::radiobutton $w.toolbar.select -text Select -variable ::GX::CurveWorkbench::st($w,tool) -value select
    ttk::radiobutton $w.toolbar.insert -text "Insert point" -variable ::GX::CurveWorkbench::st($w,tool) -value add
    ttk::radiobutton $w.toolbar.pan -text Pan -variable ::GX::CurveWorkbench::st($w,tool) -value pan
    pack $w.toolbar.select $w.toolbar.insert $w.toolbar.pan -side right -padx 3
    bind $w.toolbar <Configure> [list ::GX::native2DToolbarLayout $w.toolbar %w]
    ttk::frame $w.editbar -padding 5;pack $w.editbar -side top -fill x
    foreach {key label action} {keep "Keep range" keep remove "Remove range" remove before "Trim before" before after "Trim after" after delete "Delete points" delete_points} {
        ttk::button $w.editbar.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_operation $w $action]]
        pack $w.editbar.$key -side left -padx 2
    }
    ttk::button $w.editbar.spline -text "Spline from selection" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_makeSpline $w]]
    ttk::button $w.editbar.linear -text "Linear from selection" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_makeLinear $w]]
    ttk::button $w.editbar.fragment -text "Add selected fragment ↓" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_addFragment $w]]
    ttk::button $w.editbar.earlier -text "Point earlier" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_reorder $w -1]]
    ttk::button $w.editbar.later -text "Point later" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_reorder $w 1]]
    ttk::button $w.editbar.snap -text "Snap to reference" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_snapToReference $w]]
    foreach key {spline linear fragment earlier later snap} {pack $w.editbar.$key -side left -padx 3}
    ttk::button $w.editbar.convert -text "Convert to Native…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_convertOpen $w]]
    pack $w.editbar.convert -side left -padx 3
    bind $w.editbar <Configure> [list ::GX::native2DToolbarLayout $w.editbar %w]
    ttk::panedwindow $w.main -orient horizontal;pack $w.main -side top -fill both -expand 1
    ttk::frame $w.right -padding 4
    ttk::frame $w.leftScroll
    canvas $w.leftScroll.viewport -highlightthickness 0 -width 640 -height 700
    ttk::frame $w.leftScroll.viewport.content -padding 6
    ttk::scrollbar $w.leftScroll.scroll -orient vertical -command [list $w.leftScroll.viewport yview]
    $w.leftScroll.viewport configure -yscrollcommand [list $w.leftScroll.scroll set]
    pack $w.leftScroll.scroll -side right -fill y;pack $w.leftScroll.viewport -fill both -expand 1
    $w.leftScroll.viewport create window 0 0 -anchor nw -window $w.leftScroll.viewport.content -tags content
    bind $w.leftScroll.viewport <Configure> [list ::GX::CurveWorkbench::_sidebarLayout $w %w]
    bind $w.leftScroll.viewport.content <Configure> [list ::GX::CurveWorkbench::_sidebarLayout $w]
    $w.main add $w.leftScroll -weight 0;$w.main add $w.right -weight 1
    ttk::label $w.leftScroll.viewport.content.active -textvariable ::GX::CurveWorkbench::st($w,activeLabel) -font TkHeadingFont
    pack $w.leftScroll.viewport.content.active -fill x -pady 3
    ttk::frame $w.leftScroll.viewport.content.curveFrame;pack $w.leftScroll.viewport.content.curveFrame -fill x
    ttk::treeview $w.leftScroll.viewport.content.curves -columns {visible name source points state} -show headings -selectmode extended -height 6
    foreach {key label width stretch} {visible V 30 0 name "Curve name" 210 1 source "Source Dataset" 115 1 points Points 55 0 state State 105 0} {
        $w.leftScroll.viewport.content.curves heading $key -text $label
        $w.leftScroll.viewport.content.curves column $key -width $width -stretch $stretch
    }
    ttk::scrollbar $w.leftScroll.viewport.content.curvesScroll -orient vertical -command [list $w.leftScroll.viewport.content.curves yview]
    ttk::scrollbar $w.leftScroll.viewport.content.curvesXScroll -orient horizontal -command [list $w.leftScroll.viewport.content.curves xview]
    $w.leftScroll.viewport.content.curves configure -yscrollcommand [list $w.leftScroll.viewport.content.curvesScroll set] -xscrollcommand [list $w.leftScroll.viewport.content.curvesXScroll set]
    pack $w.leftScroll.viewport.content.curvesXScroll -in $w.leftScroll.viewport.content.curveFrame -side bottom -fill x
    pack $w.leftScroll.viewport.content.curvesScroll -in $w.leftScroll.viewport.content.curveFrame -side right -fill y
    pack $w.leftScroll.viewport.content.curves -in $w.leftScroll.viewport.content.curveFrame -fill x
    bind $w.leftScroll.viewport.content.curves <<TreeviewSelect>> [list ::GX::CurveWorkbench::_treeSelect $w]
    ttk::frame $w.leftScroll.viewport.content.renameRow;pack $w.leftScroll.viewport.content.renameRow -fill x -pady 4
    ttk::entry $w.leftScroll.viewport.content.renameRow.name -textvariable ::GX::CurveWorkbench::st($w,rename)
    ttk::button $w.leftScroll.viewport.content.renameRow.go -text Rename -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_rename $w]]
    pack $w.leftScroll.viewport.content.renameRow.go -side right;pack $w.leftScroll.viewport.content.renameRow.name -side left -fill x -expand 1
    ttk::labelframe $w.leftScroll.viewport.content.pointFrame -text "Active curve points" -padding 3;pack $w.leftScroll.viewport.content.pointFrame -fill x -pady 5
    ttk::treeview $w.leftScroll.viewport.content.points -columns {index x y source_row} -show headings -selectmode extended -height 5
    foreach {key label width} {index Index 52 x X 105 y Y 105 source_row "Source row" 83} {$w.leftScroll.viewport.content.points heading $key -text $label;$w.leftScroll.viewport.content.points column $key -width $width -stretch 1}
    ttk::scrollbar $w.leftScroll.viewport.content.pointsScroll -orient vertical -command [list $w.leftScroll.viewport.content.points yview]
    ttk::scrollbar $w.leftScroll.viewport.content.pointsXScroll -orient horizontal -command [list $w.leftScroll.viewport.content.points xview]
    $w.leftScroll.viewport.content.points configure -yscrollcommand [list $w.leftScroll.viewport.content.pointsScroll set] -xscrollcommand [list $w.leftScroll.viewport.content.pointsXScroll set]
    pack $w.leftScroll.viewport.content.pointsXScroll -in $w.leftScroll.viewport.content.pointFrame -side bottom -fill x
    pack $w.leftScroll.viewport.content.pointsScroll -in $w.leftScroll.viewport.content.pointFrame -side right -fill y
    pack $w.leftScroll.viewport.content.points -in $w.leftScroll.viewport.content.pointFrame -side left -fill x -expand 1
    bind $w.leftScroll.viewport.content.points <<TreeviewSelect>> [list ::GX::CurveWorkbench::_pointTreeSelect $w]
    _pointPagerGui $w
    ttk::frame $w.leftScroll.viewport.content.numeric;pack $w.leftScroll.viewport.content.numeric -fill x -pady 3
    foreach {key label col} {editX X 0 editY Y 2} {
        ttk::label $w.leftScroll.viewport.content.numeric.l$key -text $label;ttk::entry $w.leftScroll.viewport.content.numeric.$key -textvariable ::GX::CurveWorkbench::st($w,$key) -width 13
        grid $w.leftScroll.viewport.content.numeric.l$key -row 0 -column $col -padx 2
        grid $w.leftScroll.viewport.content.numeric.$key -row 0 -column [expr {$col+1}] -sticky ew -padx 2
    }
    ttk::button $w.leftScroll.viewport.content.numeric.apply -text "Apply X/Y" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_numericEdit $w]]
    grid $w.leftScroll.viewport.content.numeric.apply -row 1 -column 0 -columnspan 4 -sticky ew -pady 3
    ttk::frame $w.leftScroll.viewport.content.interval;pack $w.leftScroll.viewport.content.interval -fill x -pady 3
    ttk::label $w.leftScroll.viewport.content.interval.label -text "Select X interval"
    ttk::entry $w.leftScroll.viewport.content.interval.min -textvariable ::GX::CurveWorkbench::st($w,xMin) -width 9
    ttk::label $w.leftScroll.viewport.content.interval.to -text to
    ttk::entry $w.leftScroll.viewport.content.interval.max -textvariable ::GX::CurveWorkbench::st($w,xMax) -width 9
    ttk::button $w.leftScroll.viewport.content.interval.go -text Select -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_selectX $w]]
    foreach key {label min to max go} {pack $w.leftScroll.viewport.content.interval.$key -side left -padx 2}
    ttk::labelframe $w.leftScroll.viewport.content.compose -text "Ordered composition" -padding 5;pack $w.leftScroll.viewport.content.compose -in $w.leftScroll.viewport.content -fill x -pady 5
    listbox $w.leftScroll.viewport.content.compose.list -height 3 -exportselection 0;pack $w.leftScroll.viewport.content.compose.list -fill x
    ttk::frame $w.leftScroll.viewport.content.compose.actions;pack $w.leftScroll.viewport.content.compose.actions -fill x
    foreach {key label action} {up ↑ up down ↓ down reverse Reverse reverse remove Remove remove} {
        ttk::button $w.leftScroll.viewport.content.compose.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_fragmentEdit $w $action]]
        pack $w.leftScroll.viewport.content.compose.actions.$key -side left -padx 2
    }
    ttk::entry $w.leftScroll.viewport.content.compose.name -textvariable ::GX::CurveWorkbench::st($w,composeName);pack $w.leftScroll.viewport.content.compose.name -fill x -pady 3
    ttk::checkbutton $w.leftScroll.viewport.content.compose.bridge -text "Straight bridge shortcut" -variable ::GX::CurveWorkbench::st($w,bridge) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_bridgeLegacyToggle $w]]
    pack $w.leftScroll.viewport.content.compose.bridge -anchor w
    ttk::frame $w.leftScroll.viewport.content.compose.bridgeOptions;pack $w.leftScroll.viewport.content.compose.bridgeOptions -fill x
    ttk::label $w.leftScroll.viewport.content.compose.bridgeOptions.label -text "Gap bridge"
    ttk::combobox $w.leftScroll.viewport.content.compose.bridgeOptions.kind -state readonly -values {none straight quadratic cubic smooth} -width 11 -textvariable ::GX::CurveWorkbench::st($w,bridgeKind)
    ttk::button $w.leftScroll.viewport.content.compose.bridgeOptions.settings -text "Settings…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_bridgeSettings $w]]
    pack $w.leftScroll.viewport.content.compose.bridgeOptions.label $w.leftScroll.viewport.content.compose.bridgeOptions.kind $w.leftScroll.viewport.content.compose.bridgeOptions.settings -side left -padx 3
    bind $w.leftScroll.viewport.content.compose.bridgeOptions.kind <<ComboboxSelected>> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_bridgeChanged $w]]
    ttk::button $w.leftScroll.viewport.content.compose.commit -text "Previewed fragments → new curve" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_compose $w]]
    pack $w.leftScroll.viewport.content.compose.commit -fill x -pady 3
    ttk::frame $w.right.display
    ttk::checkbutton $w.right.display.direction -text "Show direction" -variable ::GX::CurveWorkbench::st($w,directionShown) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_directionToggle $w]]
    ttk::button $w.right.display.flip -text "Flip" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_directionFlip $w]]
    ttk::button $w.right.display.settings -text "Direction…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_directionOpen $w]]
    ttk::checkbutton $w.right.display.grid -text "Show grid" -variable ::GX::CurveWorkbench::st($w,gridShown) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_gridToggle $w visible]]
    ttk::checkbutton $w.right.display.snap -text "Snap to grid" -variable ::GX::CurveWorkbench::st($w,gridSnap) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_gridToggle $w snap_enabled]]
    ttk::button $w.right.display.gridSettings -text "Grid / view…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_gridOpen $w]]
    pack $w.right.display.direction $w.right.display.flip $w.right.display.settings $w.right.display.grid $w.right.display.snap $w.right.display.gridSettings -side left -padx 3
    pack $w.right.display -fill x -pady 3
    ttk::label $w.right.coordinatePolicy -textvariable ::GX::CurveWorkbench::st($w,coordinatePolicy) -wraplength 800 -justify left
    pack $w.right.coordinatePolicy -fill x -pady 2
    bind $w.right.coordinatePolicy <Configure> [list $w.right.coordinatePolicy configure -wraplength %w]
    bind $w.right.display <Configure> [list ::GX::native2DToolbarLayout $w.right.display %w]
    ttk::frame $w.right.readout
    pack $w.right.readout -fill x
    ttk::label $w.right.readout.coordinates -textvariable ::GX::CurveWorkbench::st($w,coordinates)
    pack $w.right.readout.coordinates -fill x
    # Canvas and chrome share real Tk ancestry, including on remote X11.
    ttk::frame $w.right.viewport;pack $w.right.viewport -fill both -expand 1
    canvas $w.right.viewport.canvas -background white -height 580 -highlightthickness 0;pack $w.right.viewport.canvas -fill both -expand 1
    ttk::label $w.right.residualLabel -text "Signed residual by reference X or path distance (maximum highlighted)";pack $w.right.residualLabel -fill x
    ttk::frame $w.right.residual -height 220;pack propagate $w.right.residual 0;pack $w.right.residual -in $w.right -fill x
    ttk::frame $w.validation -padding 5
    grid $w.validation -in $w.upper -row 2 -column 0 -columnspan 2 -sticky ew
    ttk::label $w.validation.refLabel -text "Reference"
    ttk::combobox $w.validation.reference -textvariable ::GX::CurveWorkbench::st($w,referenceLabel) -state readonly -width 32
    ttk::combobox $w.validation.method -textvariable ::GX::CurveWorkbench::st($w,compareMethod) -values {x path} -state readonly -width 7
    ttk::button $w.validation.compare -text "Compare / residuals" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_compare $w]]
    ttk::label $w.validation.metricLabel -text "Metric"
    ttk::combobox $w.validation.metric -textvariable ::GX::CurveWorkbench::st($w,metricLabel) -state readonly -width 20
    bind $w.validation.metric <<ComboboxSelected>> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateMetricSelect $w]]
    ttk::label $w.validation.targetLabel -text "Target"
    ttk::entry $w.validation.target -textvariable ::GX::CurveWorkbench::st($w,target) -width 12
    ttk::button $w.validation.evaluate -text Evaluate -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_metrics $w]]
    foreach key {refLabel reference method compare metricLabel metric targetLabel target evaluate} {pack $w.validation.$key -side left -padx 3}
    bind $w.validation.reference <<ComboboxSelected>> [list ::GX::CurveWorkbench::_referenceSelect $w]
    ttk::label $w.metric -textvariable ::GX::CurveWorkbench::st($w,metricText) -anchor w;pack $w.metric -fill x -padx 8
    ttk::frame $w.publish -padding 5
    grid $w.publish -in $w.upper -row 0 -column 1 -sticky ne
    ttk::label $w.publish.idLabel -text "New Dataset ID"
    ttk::entry $w.publish.id -textvariable ::GX::CurveWorkbench::st($w,resultId) -width 22
    ttk::button $w.publish.go -text "Publish selected curve(s)" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_publishSelected $w]]
    ttk::label $w.publish.externalLabel -text "External downstream feedback"
    ttk::entry $w.publish.external -textvariable ::GX::CurveWorkbench::st($w,externalFeedback) -width 35
    ttk::button $w.publish.save -text "Save workspace" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_save $w]]
    foreach key {idLabel id go externalLabel external save} {pack $w.publish.$key -side left -padx 4}
    ttk::label $w.status -textvariable ::GX::CurveWorkbench::st($w,status) -anchor w -wraplength 1450
    bind $w.status <Configure> [list $w.status configure -wraplength %w]
    pack $w.status -side bottom -fill x -padx 8 -pady 5
    # Only lightweight read-only feedback remains below the expanding pane.
    # Upper control frames retain their original widget paths and own layouts.
    pack forget $w.main $w.metric $w.status
    pack $w.status -side bottom -fill x -padx 8 -pady 5
    pack $w.metric -side bottom -fill x -padx 8
    pack $w.main -side top -fill both -expand 1
    _cadGui $w
    bind $w.publish <Configure> [list ::GX::native2DToolbarLayout $w.publish %w]
    bind $w.right.viewport.canvas <ButtonPress-1> [list ::GX::CurveWorkbench::_mouseDown $w %x %y %s]
    bind $w.right.viewport.canvas <Motion> [list ::GX::CurveWorkbench::_coordinates $w %x %y]
    bind $w.right.viewport.canvas <B1-Motion> [list ::GX::CurveWorkbench::_mouseMove $w %x %y]
    bind $w.right.viewport.canvas <ButtonRelease-1> [list ::GX::CurveWorkbench::_mouseUp $w %x %y]
    bind $w <Escape> [list ::GX::CurveWorkbench::_cancelGesture $w]
    bind $w.right.viewport.canvas <MouseWheel> [list ::GX::CurveWorkbench::_wheel $w %x %y %D]
    bind $w.right.viewport.canvas <Button-4> [list ::GX::CurveWorkbench::_wheel $w %x %y 120]
    bind $w.right.viewport.canvas <Button-5> [list ::GX::CurveWorkbench::_wheel $w %x %y -120]
    bind $w.right.viewport.canvas <Configure> [list ::GX::CurveWorkbench::_draw $w]
    bind $w.publish.external <Return> [list ::GX::CurveWorkbench::_save $w]
    wm protocol $w WM_DELETE_WINDOW [list ::GX::CurveWorkbench::_close $w]
    _selectionScene $w
    if {[catch {_load $w} err]} {
        set st($w,restoreFailed) 1
        set st($w,restoreError) "Workspace restore failed: $err. Saved workspace preserved; restore the source and reopen."
        set st($w,status) $st($w,restoreError)
    }
    _curveList $w;_pointList $w;_draw $w
    _sidebarFocusBindings $w $w.leftScroll.viewport.content
    _sidebarFocusBindings $w $w.leftScroll.viewport.content.compose
    return $w
}
