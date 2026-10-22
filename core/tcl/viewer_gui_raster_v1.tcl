# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical raster binding within the existing Viewer GUI / Native2D owners.
proc ::GX::viewerGuiDesignRasterToolBindings {design} {
    set definitions {};set result {}
    foreach component [dict get $design components] {dict set definitions [dict get $component id] $component}
    foreach component [dict get $design components] {
        set properties [dict get $component properties]
        if {![dict exists $properties raster_tool]} continue
        if {[dict get $component type] ne {action} || [llength [dict get $properties raster_tool]]!=2} {error {Raster tool binding requires an action and a Native2D component/tool pair}}
        lassign [dict get $properties raster_tool] target tool
        if {![dict exists $definitions $target] || [dict get $definitions $target type] ne {native2d} || [datasetPublicationV2DictDefault [dict get $definitions $target properties] source_kind {}] ne {raster}} {error {Raster tool binding must target a declared canonical raster component}}
        if {$tool ni {select rectangle polygon annotation move rotate pivot pan}} {error {Unsupported declarative raster tool}}
        if {[dict exists $properties diagram_tool] || [dict exists $properties component_visibility]} {error {A raster tool action cannot also select a diagram tool or toggle component visibility}}
        set action [dict get $properties action];set pair [list $target $tool]
        if {[dict exists $result $action] && [dict get $result $action] ne $pair} {error {One action cannot select conflicting raster tools}}
        dict set result $action $pair
    }
    return $result
}
proc ::GX::viewerGuiDesignRasterToolChecked {window component tool} {
    if {[catch {set runtime [_viewerGuiRasterRuntime $window $component]}]} {return 0}
    return [expr {[dict get [native2DViewportRasterDescribe [dict get $runtime canvas]] tool] eq $tool}]
}
proc ::GX::_viewerGuiRasterDefinition {window component} {
    if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen the raster Viewer}}
    set definition [viewerGuiDesignComponent $window $component]
    if {[dict get $definition type] ne {native2d} || [datasetPublicationV2DictDefault [dict get $definition properties] source_kind {}] ne {raster}} {error {Declare a Native2D source_kind raster component in Interface Builder}}
    return $definition
}
proc ::GX::viewerGuiDesignRasterBind {window component selector} {
    _viewerGuiRasterDefinition $window $component
    set choice [viewerGuiDesignComponent $window $selector]
    if {[dict get $choice type] ne {dataset_selector} || [datasetPublicationV2DictDefault [dict get $choice properties] content_kind {}] ne {raster}} {error {Raster binding requires a declared canonical raster Dataset selector}}
    set dataset $::GX::ViewerGui::values($window,$selector)
    if {$dataset eq {}} {return [dict create status awaiting_selection content_kind raster]}
    return [_viewerGuiRasterBindDataset $window $component $dataset]
}
proc ::GX::_viewerGuiRasterSourceCheck {source} {
    set dataset [dict get $source dataset_id]
    if {[datasetField $dataset contract [datasetField $dataset kind {}]] ne {image.raster} || [sessionInspectionDataset $dataset] ne [dict get $source dataset_identity] || [datasetVariableSchemaV3 $dataset] ne [dict get $source variable_schema]} {error {Saved raster Dataset identity or schema changed; explicitly bind the current source}}
    if {[dict get [sessionInspectionDatasetPayload $dataset] sha256] ne [dict get $source source_sha256]} {error {Saved raster Dataset content changed; explicitly bind the current source}}
}
proc ::GX::_viewerGuiRasterRestoreCheck {window component binding} {
    _viewerGuiRasterDefinition $window $component
    _viewerGuiRasterSourceCheck [dict get $binding source]
    set owner [interactiveDocumentRead [dict get $binding document_id]]
    set instance [dict get $::GX::ViewerGui::instances $window]
    if {[dict get $owner generation] ne [dict get $binding document_receipt generation] || [dict get $owner module_id] ne [dict get $instance module] || [dict get $owner provider_id] ne [dict get $instance provider] || [dict get $owner format] ne {gxtxt.native2d.raster_scene.v1}} {error {Saved raster Document ownership changed}}
    set current [dict remove $owner payload]
    if {$current ne [dict get $binding document_receipt]} {
        # History may restore an earlier accepted image state, but only from
        # the controller that still owns the actual current Document revision.
        if {![dict exists $instance bindings $component document_receipt] || $current ne [dict get $instance bindings $component document_receipt]} {error {Raster Document changed outside this Viewer; reopen its current state explicitly}}
    }
}
proc ::GX::_viewerGuiRasterBindDataset {window component dataset {binding {}}} {
    _viewerGuiRasterDefinition $window $component
    set instance [dict get $::GX::ViewerGui::instances $window]
    set created [expr {$binding eq {}}]
    if {$created} {
        if {[datasetField $dataset contract [datasetField $dataset kind {}]] ne {image.raster}} {error {Select a canonical image.raster Dataset}}
        # Verify the source before creating its ordinary Document resource owner.
        set payload [sessionInspectionDatasetPayload $dataset]
        if {![dict get $instance restoring] && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {error {Raster binding cancelled before creating a document}}
        _viewerGuiRasterDefinition $window $component
        set owner [interactiveDocumentCreate [dict get $instance module] [dict get $instance provider] gxtxt.native2d.raster_scene.v1 1 {}]
        set owner [interactiveDocumentRead [dict get $owner id]]
    } else {
        _viewerGuiRasterRestoreCheck $window $component $binding
        set owner [interactiveDocumentRead [dict get $binding document_id]]
    }
    set token {};set canvas {};set stage {};set installed 0
    try {
        set document [dict get $owner id]
        set token [native2DGeometryOpen $document]
        if {$created} {
            set admitted [native2DGeometryRasterDatasetBind $token $dataset [dict create expected_source_sha256 [dict get $payload sha256]]]
            set objects [list [dict get $admitted object_token]]
            set source [dict get $admitted source]
            native2DGeometryCall $token fit_all {}
        } else {
            set restored [native2DGeometryCall $token raster_restore [dict create snapshot [dict get $binding snapshot]]]
            set objects [dict get $restored object_tokens]
            set source [dict get $binding source]
            if {![llength $objects]} {error {Saved canonical raster has no image}}
            foreach object $objects {native2DGeometryCall $token raster_layer_get [dict create object_token $object]}
            if {[dict exists $binding presentation_view_state]} {native2DGeometryCall $token view_state [dict create view_state [dict get $binding presentation_view_state]]}
        }
        if {$created} {
            set snapshot [native2DGeometryCall $token raster_snapshot {}]
        } else {
            # Restore already verified these exact retained resources/native
            # definitions. Re-exporting an unchanged image would mint a new
            # resource-origin timestamp and falsely revise its Document.
            set snapshot [dict get $binding snapshot]
        }
        set widget [dict get $instance widgets $component]
        # Each candidate has its own normal geometry container. Its toolbar
        # and semantic panels cannot collide with the still-valid old host.
        set stage $widget.raster[incr ::GX::ViewerGui::serial]
        ttk::frame $stage
        set canvas $stage.canvas
        canvas $canvas -background white -highlightthickness 0 -width 500 -height 350
        native2DGeometryViewportAttach $token $stage $canvas [list ::GX::native2DViewportRasterPaint $canvas]
        pack $canvas -fill both -expand 1
        set interaction [datasetPublicationV2DictDefault $binding interaction {}]
        native2DViewportRasterAttach $canvas $token [lindex $objects 0] {}
        if {$interaction ne {}} {
            foreach key [dict keys $interaction] {if {$key ni {tool roi_id annotation_id annotation_generation pivot}} {error {Unsupported saved raster interaction field}}}
            if {[dict exists $interaction pivot]} {
                set pivot [dict get $interaction pivot]
                set native [dict get [_native2DGeometryRequire $token] native]
                if {[dict get $pivot mode] eq {custom}} {::GX::Native2D::core pivot $native custom [dict get $pivot point]} else {::GX::Native2D::core pivot $native [dict get $pivot mode]}
            }
            if {[dict exists $interaction tool]} {native2DViewportRasterTool $canvas [dict get $interaction tool]}
            if {[dict exists $interaction roi_id] && [dict get $interaction roi_id] ne {}} {
                dict get [native2DGeometryCall $token raster_roi_get [dict create object_token [lindex $objects 0]]] rois [dict get $interaction roi_id]
                dict set ::GX::ViewportHost::hosts $canvas raster selected_roi [dict get $interaction roi_id]
            }
            if {[datasetPublicationV2DictDefault $interaction annotation_id {}] ne {}} {
                set id [dict get $interaction annotation_id]
                set collection [native2DGeometryCall $token raster_annotation_get [dict create object_token [lindex $objects 0]]]
                if {![dict exists $interaction annotation_generation] || ![dict exists $collection generations $id] || [dict get $collection generations $id]!=[dict get $interaction annotation_generation]} {error {Saved annotation selection identity changed}}
                _native2DViewportRasterAnnotationSelect $canvas [dict create hit 1 annotation_id $id generation [dict get $collection generations $id]]
            }
        }
        set preparedPanels [_viewerGuiAnchoredPrepare $window $component $canvas]
        # All source, geometry, interaction and widget admission succeeded.
        # A reopened presentation does not revise scientific geometry. Earlier
        # captures embedded the current camera in snapshot.view_state; accept
        # that presentation without replacing its unchanged canonical snapshot.
        # Genuine History restoration of different images/layers still commits
        # through this original Document owner.
        set documentPayload [dict get $owner payload]
        set canonical [datasetPublicationV2DictDefault $documentPayload native2d_raster {}]
        if {!$created && $canonical ne {} && [dict remove $canonical view_state] eq [dict remove $snapshot view_state]} {
            set snapshot $canonical
        } else {
            dict set documentPayload native2d_raster $snapshot
            set owner [native2DGeometryCheckpoint $token $documentPayload]
        }
        set binding [dict create kind raster document_id $document document_receipt [dict remove $owner payload] source $source snapshot $snapshot]
        dict set ::GX::ViewerGui::instances $window raster_slots $component [dict create scene_token $token canvas $canvas object_tokens $objects]
        dict set ::GX::ViewerGui::instances $window bindings $component $binding
        dict set ::GX::ViewerGui::instances $window token [interactiveDocumentSessionToken]
        dict set ::GX::ViewportHost::hosts $canvas raster callback [list ::GX::_viewerGuiRasterEvent $window $component]
        _viewerGuiAnchoredCommit $window $preparedPanels
        pack $stage -fill both -expand 1
        foreach child [winfo children $widget] {if {$child ne $stage} {destroy $child}}
        set installed 1
        viewerGuiSourceScopeAttach $window $component $canvas
        if {[dict exists $::GX::ViewerGui::instances $window demo_bindings $component]} {dict unset ::GX::ViewerGui::instances $window demo_bindings $component}
        if {$created && ![dict get $instance restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Bind canonical raster $component"}
        viewerGuiTraceEmit $window $component source_bound [dict create status ready dataset_id $dataset source_sha256 [dict get $source source_sha256] coordinate_kind source_pixel]
        viewerGuiActionsRefresh $window
        return [viewerGuiDesignRasterDescribe $window $component]
    } on error {message options} {
        if {!$installed} {
            if {$stage ne {} && [winfo exists $stage]} {destroy $stage}
            if {$token ne {}} {catch {native2DGeometryClose $token}}
            if {$created} {catch {interactiveDocumentDelete [dict get $owner id]}}
        }
        return -options $options $message
    }
}
proc ::GX::_viewerGuiRasterRuntime {window component} {
    _viewerGuiRasterDefinition $window $component
    if {![dict exists $::GX::ViewerGui::instances $window bindings $component] || [dict get $::GX::ViewerGui::instances $window bindings $component kind] ne {raster}} {error {Bind a canonical raster Dataset before using image tools}}
    set runtime [dict get $::GX::ViewerGui::instances $window raster_slots $component]
    _native2DViewportRasterRequire [dict get $runtime canvas]
    return $runtime
}
proc ::GX::viewerGuiDesignRasterTool {window component tool} {
    set runtime [_viewerGuiRasterRuntime $window $component]
    return [native2DViewportRasterTool [dict get $runtime canvas] $tool]
}
proc ::GX::viewerGuiDesignRasterCommand {window component command} {
    _viewerGuiSemanticDispatchCheck $window $component
    _viewerGuiRasterCommandValidate [dict get $::GX::ViewerGui::instances $window design] $component $command
    if {[regexp {^(panel_open|panel_close|editor_apply|editor_cancel):([a-z][a-z0-9_]*)$} $command -> operation root]} {
        switch -- $operation {
            panel_open {return [_viewerGuiAnchoredOpen $window $root]}
            editor_apply {return [_viewerGuiAnchoredApply $window $root]}
            panel_close - editor_cancel {_viewerGuiAnchoredClose $window $root;return {status cancelled}}
        }
    }
    set runtime [_viewerGuiRasterRuntime $window $component]
    return [native2DViewportRasterCommand [dict get $runtime canvas] $command]
}
proc ::GX::_viewerGuiRasterCapture {window component binding} {
    set runtime [_viewerGuiRasterRuntime $window $component]
    set token [dict get $runtime scene_token];set canvas [dict get $runtime canvas]
    # View capture references the last accepted resources. It never exports an
    # image, hashes a file or creates an origin/resource on a pointer frame.
    set view [dict get [native2DGeometryCall $token view_state {}] view_state]
    # Pixel extent is disposable widget layout, not a saved scientific change.
    # Retain valid accepted dimensions while capturing the actual world domain,
    # grid, axes and other view settings. Native layout supplies current pixels
    # again on mounting; no geometry/projection calculation is performed here.
    set dimensions [lrange [dict get $binding snapshot view_state viewport] 0 1]
    dict set view viewport [lreplace [dict get $view viewport] 0 1 {*}$dimensions]
    dict set binding presentation_view_state $view
    set state [native2DViewportRasterDescribe $canvas]
    dict set binding interaction [dict create tool [dict get $state tool] roi_id [dict get $state roi_id] pivot [::GX::Native2D::core pivot [dict get [_native2DGeometryRequire $token] native]]]
    # Keep old unannotated captures byte-equivalent. Annotation identity is
    # retained only when an actual canonical annotation is selected.
    if {[dict get $state annotation_id] ne {}} {
        dict set binding interaction annotation_id [dict get $state annotation_id]
        dict set binding interaction annotation_generation [dict get $state annotation_generation]
    }
    return $binding
}
proc ::GX::_viewerGuiRasterEvent {window component canvas event detail} {
    if {![winfo exists $window] || ![dict exists $::GX::ViewerGui::instances $window raster_slots $component] || [dict get $::GX::ViewerGui::instances $window raster_slots $component canvas] ne $canvas} {error {Raster gesture belongs to a previous Viewer}}
    if {$event eq {cancelled}} {
        if {[dict exists $::GX::ViewerGui::instances $window raster_pending $component]} {dict unset ::GX::ViewerGui::instances $window raster_pending $component}
        return
    }
    if {$event eq {error}} {
        [dict get $::GX::ViewerGui::instances $window slots status] configure -text [dict get $detail message]
        viewerGuiTraceEmit $window $component raster_error $detail
        return
    }
    if {![viewerGuiDesignGuard $window]} {error {Raster gesture belongs to a previous Session}}
    switch -- $event {
        context {_viewerGuiAnchoredSelectionChanged $window $component;return [_viewerGuiRasterSemanticMenu $window $component $canvas $detail]}
        selection_changed {_viewerGuiAnchoredSelectionChanged $window $component}
        before_edit {
            _viewerGuiSemanticDispatchCheck $window $component
            _viewerGuiRasterRestoreCheck $window $component [dict get $::GX::ViewerGui::instances $window bindings $component]
            if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {error {Raster edit cancelled before changing its document}}
            _viewerGuiSemanticDispatchCheck $window $component
            _viewerGuiRasterRestoreCheck $window $component [dict get $::GX::ViewerGui::instances $window bindings $component]
            dict set ::GX::ViewerGui::instances $window raster_pending $component [dict get $::GX::ViewerGui::instances $window bindings $component]
        }
        committed {
            set prior [dict get $::GX::ViewerGui::instances $window raster_pending $component]
            set token [dict get $::GX::ViewerGui::instances $window raster_slots $component scene_token]
            set committed 0
            try {
                set snapshot [native2DGeometryCall $token raster_snapshot {}]
                set owner [interactiveDocumentRead [dict get $prior document_id]]
                set payload [dict get $owner payload];dict set payload native2d_raster $snapshot
                set owner [native2DGeometryCheckpoint $token $payload]
                set committed 1
                dict set prior snapshot $snapshot
                dict set prior document_receipt [dict remove $owner payload]
                dict set ::GX::ViewerGui::instances $window bindings $component $prior
                if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window "Raster [dict get $detail operation]"}
            } on error {message options} {
                if {!$committed} {
                    # The canonical owner is unchanged. Restore the retained
                    # accepted resources through the same normal binding path.
                    catch {_viewerGuiRasterBindDataset $window $component [dict get $prior source dataset_id] $prior}
                }
                return -options $options $message
            } finally {
                if {[dict exists $::GX::ViewerGui::instances $window raster_pending $component]} {dict unset ::GX::ViewerGui::instances $window raster_pending $component}
            }
        }
        cancelled {
            if {[dict exists $::GX::ViewerGui::instances $window raster_pending $component]} {dict unset ::GX::ViewerGui::instances $window raster_pending $component}
        }
        error {
            [dict get $::GX::ViewerGui::instances $window slots status] configure -text [dict get $detail message]
        }
    }
    viewerGuiTraceEmit $window $component raster_$event $detail
    if {$event in {tool_changed selection_changed committed cancelled}} {viewerGuiActionsRefresh $window}
}
proc ::GX::viewerGuiDesignRasterDescribe {window component} {
    _viewerGuiRasterDefinition $window $component
    if {![dict exists $::GX::ViewerGui::instances $window bindings $component] || [dict get $::GX::ViewerGui::instances $window bindings $component kind] ne {raster}} {return [dict create status unbound content_kind raster]}
    set binding [dict get $::GX::ViewerGui::instances $window bindings $component]
    set runtime [dict get $::GX::ViewerGui::instances $window raster_slots $component]
    set token [dict get $runtime scene_token]
    set images {}
    foreach object [dict get $runtime object_tokens] {
        set image [dict get [native2DGeometryCall $token image_get [dict create object_token $object]] image_state]
        set rois [native2DGeometryCall $token raster_roi_get [dict create object_token $object]]
        lappend images [dict create object_token $object image_state $image rois $rois]
    }
    return [dict create status ready document_id [dict get $binding document_id] source [dict get $binding source] images $images interaction [native2DViewportRasterDescribe [dict get $runtime canvas]] implicit_dataset_publication 0]
}
