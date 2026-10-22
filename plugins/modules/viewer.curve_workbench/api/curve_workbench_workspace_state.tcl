# SPDX-License-Identifier: GPL-3.0-or-later
# One workspace/Undo payload authority. Feature controllers own their Native
# resources; this module orders their capture and restoration explicitly.
proc ::GX::CurveWorkbench::_cadState {w} {
    variable st
    _identitySync $w
    set coordinatePresentation $st($w,coordinatePresentation)
    set state [dict create publication_arrangement [expr {[info exists st($w,publicationArrangement)] ? $st($w,publicationArrangement) : "table"}] publication_representation [expr {[info exists st($w,publicationRepresentation)] ? $st($w,publicationRepresentation) : "cartesian"}] groups $st($w,groups) next_group $st($w,nextGroup) active $st($w,active) selection $st($w,objectSelection) target_group $st($w,cadGroup) target_scope $st($w,cadTarget) tool $st($w,cadTool) object_snap $st($w,cadObjectSnap) pivot [::GX::Native2D::core pivot $st($w,scene)] gizmo [::GX::Native2D::core gizmo $st($w,scene)]]
    foreach property {grid presentation view_requested} {dict set state $property [::GX::Native2D::core $property $st($w,scene)]}
    dict set state coordinate_presentation $coordinatePresentation
    dict set state coordinate_view $st($w,coordinateView)
    dict set state coordinate_frame_views $st($w,coordinateFrameViews)
    dict set state coordinate_configuration $st($w,coordinateConfiguration)
    dict set state coordinate_metric $st($w,metric)
    if {[info exists st($w,planarContext)]} {dict set state planar_context $st($w,planarContext)}
    dict set state bridge_tolerance $st($w,bridgeTolerance)
    if {$st($w,active) ne ""&&$st($w,selectionObject) ne ""} {dict set state point_selection [_pointSelectionDescriptor $w]}
    if {[info exists st($w,sketchDataset)]} {dict set state sketch_dataset $st($w,sketchDataset)}
    dict set state constraints [_constraintCapture $w]
    dict set state next_constraint $st($w,nextConstraint)
    dict set state measurements $st($w,measurements)
    dict set state next_measurement $st($w,nextMeasurement)
    dict set state sketch_attributes $st($w,sketchAttributes)
    dict set state fragments [_fragmentCapture $w]
    dict set state next_fragment $st($w,nextFragment)
    dict set state selection_sets [_collectionCaptureSets $w]
    dict set state next_selection_set $st($w,nextSelectionSet)
    dict set state layers $st($w,layers)
    dict set state next_layer $st($w,nextLayer)
    dict set state curve_visibility [dict get [_savedViewCapture $w] curve_visibility]
    dict set state saved_views $st($w,savedViews)
    dict set state next_saved_view $st($w,nextSavedView)
    dict set state series_containers $st($w,seriesContainers)
    dict set state next_series $st($w,nextSeries)
    dict set state geometric_comparison $st($w,lastGeometricComparison)
    dict set state comparison_method $st($w,compareMethod)
    dict set state scientific_recipe [expr {[info exists st($w,scientificRecipe)] ? $st($w,scientificRecipe) : {}}]
    dict set state show_constraints $st($w,showConstraints)
    dict set state show_dimensions $st($w,showDimensions)
    foreach key {leftVisible listVisible pointsVisible composeVisible compareVisible} {
        if {[info exists st($w,$key)]} {dict set state viewport_preferences $key $st($w,$key)}
    }
    if {[info exists st($w,images)]} {
        dict set state reference_images [_imageSnapshot $w]
        dict set state next_image $st($w,nextImage)
    }
    set selected {};set reverse [_logicalNativeMap $w]
    foreach member [_semanticMembers $w] {
        if {![dict get $member valid]} continue
        if {[dict get $member kind] eq "fragment"} {
            dict for {logical record} $st($w,sketchFragments) {
                if {[dict exists $record native]&&[dict get $record native]==[dict get $member id]} {
                    lappend selected [dict create logical $logical kind fragment index 0];break
                }
            }
            continue
        }
        if {![dict exists $reverse [dict get $member id]]} continue
        lappend selected [dict create logical [dict get $reverse [dict get $member id]] kind [dict get $member kind] index [dict get $member index]]
    }
    dict set state semantic_selection $selected
    foreach {key field} {enabled comparisonEnabled config comparisonConfig record comparisonRecord} {
        dict set state explicit_comparison $key $st($w,$field)
    }
    return $state
}

proc ::GX::CurveWorkbench::_cadRestoreState {w state} {
    variable st
    set st($w,coordinatePresentation) [::GX::datasetPublicationV2DictDefault $state coordinate_presentation {}]
    set st($w,coordinateView) [::GX::datasetPublicationV2DictDefault $state coordinate_view {}]
    set st($w,coordinateFrameViews) [::GX::datasetPublicationV2DictDefault $state coordinate_frame_views {}]
    set st($w,coordinateConfiguration) [::GX::datasetPublicationV2DictDefault $state coordinate_configuration [_coordinateConfigurationDefault]]
    if {![dict exists $state coordinate_configuration] && $st($w,active) ne {} && [dict exists $st($w,curves) $st($w,active)]} {
        # Preserve the actual legacy frame. Incompatible dimensions do not
        # silently acquire consent for new heterogeneous geometry/imports.
        lassign [_coordinateUnits [_record $w $st($w,active)]] xUnit yUnit
        dict set st($w,coordinateConfiguration) x_unit $xUnit
        dict set st($w,coordinateConfiguration) y_unit $yUnit
    }
    set st($w,sketchUnit) [dict get $st($w,coordinateConfiguration) x_unit]
    unset -nocomplain st($w,coordinateFrameKey)
    set st($w,coordinateCache) {}
    set st($w,metric) [::GX::datasetPublicationV2DictDefault $state coordinate_metric length]
    unset -nocomplain st($w,planarContext)
    if {[dict exists $state planar_context]} {set st($w,planarContext) [dict get $state planar_context]}
    unset -nocomplain st($w,sketchDataset)
    if {[dict exists $state sketch_dataset]} {set st($w,sketchDataset) [dict get $state sketch_dataset]}
    # Constraints can refer to image calibration geometry. Release them before
    # images, then restore images before any constraint is reconstructed.
    _constraintCloseNative $w
    if {[dict exists $state reference_images]} {
        _imageRestore $w [dict get $state reference_images]
        set st($w,nextImage) [expr {max($st($w,nextImage),[dict get $state next_image])}]
    }
    set st($w,showConstraints) [::GX::datasetPublicationV2DictDefault $state show_constraints 1]
    set st($w,showDimensions) [::GX::datasetPublicationV2DictDefault $state show_dimensions 1]
    _collectionCloseNative $w
    _fragmentCloseNative $w
    _constraintCloseNative $w
    set st($w,publicationRepresentation) [::GX::datasetPublicationV2DictDefault $state publication_representation cartesian]
    set st($w,publicationArrangement) [::GX::datasetPublicationV2DictDefault $state publication_arrangement table]
    _cadCloseGroups $w
    set st($w,groups) [dict get $state groups]
    set st($w,nextGroup) [expr {max($st($w,nextGroup),[dict get $state next_group])}]
    set st($w,objectSelection) [dict get $state selection]
    set st($w,cadGroup) [dict get $state target_group]
    if {[dict exists $state active]&&[dict exists $st($w,curves) [dict get $state active]]} {set st($w,active) [dict get $state active]}
    set st($w,cadTarget) [dict get $state target_scope]
    set st($w,cadTool) [dict get $state tool]
    set st($w,cadObjectSnap) [::GX::datasetPublicationV2DictDefault $state object_snap 0]
    set pivot [dict get $state pivot]
    if {[dict get $pivot mode] eq "custom"} {
        ::GX::Native2D::core pivot $st($w,scene) custom [dict get $pivot point]
    } else {::GX::Native2D::core pivot $st($w,scene) [dict get $pivot mode]}
    ::GX::Native2D::core gizmo $st($w,scene) [dict get $state gizmo]
    _cadSyncGroups $w
    foreach property {grid presentation} {
        if {[dict exists $state $property]} {::GX::Native2D::core $property $st($w,scene) [dict get $state $property]}
    }
    if {[dict exists $state view_requested]} {::GX::Native2D::core view $st($w,scene) [dict get $state view_requested]}
    if {[dict exists $state bridge_tolerance]} {set st($w,bridgeTolerance) [dict get $state bridge_tolerance]}
    if {[dict exists $state constraints]} {
        dict for {id record} [dict get $state constraints] {
            set receipt [::GX::Native2D::core constraint_create $st($w,scene) [_constraintNativeSpec $w [dict get $record definition]]]
            dict set record native [dict get $receipt id];dict set st($w,constraints) $id $record
        }
        set st($w,nextConstraint) [expr {max($st($w,nextConstraint),[dict get $state next_constraint])}]
    }
    _constraintRefresh $w
    set st($w,measurements) [::GX::datasetPublicationV2DictDefault $state measurements {}]
    set st($w,nextMeasurement) [expr {max($st($w,nextMeasurement),[::GX::datasetPublicationV2DictDefault $state next_measurement 0])}]
    _measurementRefresh $w
    set st($w,sketchAttributes) [::GX::datasetPublicationV2DictDefault $state sketch_attributes {}]
    set st($w,sketchFragments) [::GX::datasetPublicationV2DictDefault $state fragments {}]
    set st($w,nextFragment) [expr {max($st($w,nextFragment),[::GX::datasetPublicationV2DictDefault $state next_fragment 0])}]
    dict for {id record} $st($w,sketchFragments) {
        if {[dict get $record state] ne "current"} continue
        set receipt [::GX::Native2D::core fragment_create $st($w,scene) [_fragmentNativeSpec $w [dict get $record definition]]]
        dict set st($w,sketchFragments) $id native [dict get $receipt id]
        _identitySetAttributes $w [dict get $receipt id] [dict get $record sketch_attributes]
    }
    _identitySync $w;_fragmentRefresh $w
    set st($w,layers) [::GX::datasetPublicationV2DictDefault $state layers {}]
    set st($w,selectionSets) [::GX::datasetPublicationV2DictDefault $state selection_sets {}]
    foreach {field key} {nextLayer next_layer nextSelectionSet next_selection_set} {
        set st($w,$field) [expr {max($st($w,$field),[::GX::datasetPublicationV2DictDefault $state $key 0])}]
    }
    _collectionSyncLayers $w
    dict for {id record} $st($w,selectionSets) {
        if {[_collectionState $record] ne "current"} continue
        set receipt [::GX::Native2D::core selection_set_create $st($w,scene) [_collectionNativeRefs $w [dict get $record members]]]
        dict set st($w,selectionSets) $id native [dict get $receipt id]
        ::GX::Native2D::core identity_name $st($w,scene) [dict get $receipt id] [dict get $record name]
    }
    _collectionRefresh $w
    set st($w,savedViews) [::GX::datasetPublicationV2DictDefault $state saved_views {}]
    set st($w,nextSavedView) [expr {max($st($w,nextSavedView),[::GX::datasetPublicationV2DictDefault $state next_saved_view 0])}]
    if {[dict exists $state curve_visibility]} {
        dict for {id visible} [dict get $state curve_visibility] {
            if {[dict exists $st($w,curves) $id]} {
                dict set st($w,curves) $id visible $visible
                ::GX::Native2D::core visible $st($w,scene) [dict get [_record $w $id] native] $visible
            }
        }
    }
    _savedViewRefresh $w
    set st($w,seriesContainers) [::GX::datasetPublicationV2DictDefault $state series_containers {}]
    set st($w,nextSeries) [expr {max($st($w,nextSeries),[::GX::datasetPublicationV2DictDefault $state next_series 0])}]
    _seriesManagerRefresh $w
    set st($w,lastGeometricComparison) [::GX::datasetPublicationV2DictDefault $state geometric_comparison {}]
    set st($w,compareMethod) [::GX::datasetPublicationV2DictDefault $state comparison_method x]
    if {$st($w,compareMethod) eq "geometry"&&$st($w,lastGeometricComparison) ne {}&&[_measurementState $w $st($w,lastGeometricComparison)] eq "current"} {
        set st($w,residual) [dict get $st($w,lastGeometricComparison) receipt]
    } elseif {$st($w,compareMethod) eq "geometry"} {set st($w,residual) {}}
    if {$st($w,active) ne {}} {
        set units [_coordinateUnits [_record $w $st($w,active)]]
        if {[lindex $units 0] ne {}&&[lindex $units 0] eq [lindex $units 1]&&![catch {::GX::unitRegistryConversionPlan [lindex $units 0] m}]} {set st($w,sketchUnit) [lindex $units 0]}
    }
    if {[dict exists $state viewport_preferences]} {
        dict for {key value} [dict get $state viewport_preferences] {set st($w,$key) $value}
        # Layout must wait until the remaining curves/view have been restored;
        # it must never save a partially deserialized document.
        after idle [list ::GX::CurveWorkbench::_restoreViewportPreferences $w]
    }
    set st($w,semanticSet) 0;set members {}
    foreach member [::GX::datasetPublicationV2DictDefault $state semantic_selection {}] {
        set logical [dict get $member logical]
        if {[dict get $member kind] eq "fragment"} {
            if {[dict exists $st($w,sketchFragments) $logical native]&&[dict get [_fragmentCapture $w] $logical state] eq "current"} {
                lappend members [dict create kind fragment id [dict get $st($w,sketchFragments) $logical native] index 0]
            }
            continue
        }
        if {![dict exists $st($w,curves) $logical]} continue
        set record [_record $w $logical]
        set style [::GX::Native2D::core object_style $st($w,scene) [dict get $record native]]
        lappend members [dict create kind [dict get $member kind] id [dict get $record native] index [dict get $member index]]
    }
    set st($w,semanticSet) [::GX::Native2D::core selection_set_restore $st($w,scene) 0 $members replace]
    _semanticSync $w
    set saved [::GX::datasetPublicationV2DictDefault $state explicit_comparison {enabled 0 config {} record {}}]
    foreach {key field} {enabled comparisonEnabled config comparisonConfig record comparisonRecord} {set st($w,$field) [dict get $saved $key]}
    # A legacy residual receipt alone cannot activate comparison on restore.
    _comparisonRefresh $w
}
