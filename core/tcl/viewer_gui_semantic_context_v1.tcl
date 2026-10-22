# SPDX-License-Identifier: GPL-3.0-or-later
# Typed context policy within the existing Viewer Commands / ViewportHost.
# Designs contain inert conditions and declared command IDs, never callbacks.
proc ::GX::_viewerGuiSemanticConditionsValidate {conditions} {
    if {[catch {dict size $conditions}]} {error {Semantic conditions require a field/value dictionary}}
    dict for {field values} $conditions {
        if {$field ni {entity selection_present roi_present annotation_present layer_visible layer_locked editable}} {error "Unknown semantic context field: $field"}
        if {![llength $values] || [llength $values]>6} {error {A semantic condition needs one or more finite admitted values}}
        foreach value $values {
            if {$field eq {entity}} {
                if {$value ni {background object roi annotation selection layer}} {error {Unknown semantic target entity}}
            } elseif {$value ni {0 1}} {error {Semantic state conditions use exact booleans 0 or 1}}
        }
    }
}
proc ::GX::_viewerGuiSemanticContextDesignValidate {design} {
    set components {}
    foreach component [dict get $design components] {dict set components [dict get $component id] $component}
    foreach definition [dict get $design components] {
        set p [dict get $definition properties]
        if {![dict exists $p semantic_viewport] && ![dict exists $p semantic_rules]} continue
        if {[dict get $definition type] ne {context_menu} || ![dict exists $p semantic_viewport] || ![dict exists $p semantic_rules]} {error {A semantic context menu requires both semantic_viewport and semantic_rules}}
        set target [dict get $p semantic_viewport]
        if {![dict exists $components $target] || [dict get $components $target type] ne {native2d}} {error {Semantic context must name a declared Native2D viewport}}
        # Current raster admission is automatic; other Native2D domain owners
        # retain their actual semantic pick dispatch rather than faking a hit.
        if {[datasetPublicationV2DictDefault [dict get $components $target properties] source_kind {}] ne {raster}} {error {This semantic binding requires the canonical raster controller}}
        if {[catch {dict size [dict get $p semantic_rules]}]} {error {Semantic rules require a command dictionary}}
        dict for {action rule} [dict get $p semantic_rules] {
            if {$action eq {-} || $action ni [dict get $p actions]} {error {Semantic rule must name its own declared command}}
            if {[catch {dict size $rule}]} {error {Semantic command policy must be a dictionary}}
            dict for {kind conditions} $rule {
                if {$kind ni {visible enabled}} {error {Semantic policy supports visible and enabled conditions}}
                _viewerGuiSemanticConditionsValidate $conditions
            }
        }
    }
}
proc ::GX::_viewerGuiSemanticMatches {values conditions} {
    dict for {key admitted} $conditions {if {[dict get $values $key] ni $admitted} {return 0}}
    return 1
}
proc ::GX::_viewerGuiRasterSemanticState {window component entity roi} {
    set runtime [_viewerGuiRasterRuntime $window $component]
    set token [dict get $runtime scene_token];set canvas [dict get $runtime canvas]
    set record [_native2DViewportRasterRequire $canvas];set object [dict get $record object]
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    set image [_native2DRasterImage $scene $object]
    set style [::GX::Native2D::core object_style $native [dict get $image id]]
    set layer [_native2DRasterLayer $native $style]
    set collection [_native2DViewportRasterCollection $record]
    if {$entity eq {roi} && ![dict exists $collection rois $roi]} {error {Context ROI no longer exists; open its current context}}
    set annotations [native2DGeometryCall $token raster_annotation_get [dict create object_token $object]]
    set annotation [dict get $record selected_annotation]
    if {$entity eq {annotation} && ($annotation eq {} || ![dict exists $annotations generations $annotation] || [dict get $annotations generations $annotation]!=[dict get $record annotation_generation])} {error {Context annotation identity changed; open its current context}}
    set visible [expr {[dict get $image state visible] && [dict get $style visible] && [dict get $layer visible]}]
    set locked [expr {[dict get $image state locked] || [dict get $layer locked]}]
    set selected [dict get [::GX::Native2D::core selection_summary $native [dict get $image id]] count]
    set values [dict create entity $entity selection_present [expr {$selected>0 || [dict get $record selected_roi] ne {} || $annotation ne {}}] roi_present [expr {$entity eq {roi}}] annotation_present [expr {$entity eq {annotation}}] layer_visible [dict get $layer visible] layer_locked [dict get $layer locked] editable [expr {$visible && !$locked && [dict get $layer selectable]}]]
    set binding [dict get $::GX::ViewerGui::instances $window bindings $component]
    set owner [interactiveDocumentRead [dict get $binding document_id]]
    if {[dict remove $owner payload] ne [dict get $binding document_receipt]} {error {Context Document changed outside this Viewer; reopen its current state}}
    set guard [list $token $object [dict remove $owner payload] [dict get $image state] $style $layer [dict get $collection revision] [dict get $record selected_roi] [dict get $annotations revision] $annotation [dict get $record annotation_generation] [::GX::Native2D::core view_state $native]]
    return [dict create values $values guard $guard entity $entity roi_id $roi component $component]
}
proc ::GX::_viewerGuiSemanticDispatchCheck {window component} {
    if {![dict exists $::GX::ViewerGui::instances $window semantic_dispatch]} return
    set captured [dict get $::GX::ViewerGui::instances $window semantic_dispatch]
    if {[dict get $captured component] ne $component} {error {Context command targets a different viewport}}
    set current [_viewerGuiRasterSemanticState $window $component [dict get $captured entity] [dict get $captured roi_id]]
    if {[dict get $current guard] ne [dict get $captured guard]} {error {Scientific context changed; reopen its current menu}}
}
proc ::GX::_viewerGuiSemanticInvoke {window definition action captured} {
    if {![viewerGuiDesignGuard $window]} {return 0}
    if {[dict exists $::GX::ViewerGui::instances $window semantic_dispatch]} {return 0}
    try {
        set current [_viewerGuiRasterSemanticState $window [dict get $captured component] [dict get $captured entity] [dict get $captured roi_id]]
        if {[dict get $current guard] ne [dict get $captured guard]} {error {Scientific context changed; reopen its current menu}}
        set rule [datasetPublicationV2DictDefault [dict get $definition properties semantic_rules] $action {}]
        foreach kind {visible enabled} {if {![_viewerGuiSemanticMatches [dict get $current values] [datasetPublicationV2DictDefault $rule $kind {}]]} {error {Context command is no longer applicable}}}
        if {![viewerCommandApplicable $window $action] || ![viewerCommandEnabled $window $action]} {return 0}
        dict set ::GX::ViewerGui::instances $window semantic_dispatch $captured
        return [viewerCommandInvoke $window $action]
    } on error {message options} {
        if {[winfo exists $window]} {[dict get $::GX::ViewerGui::instances $window slots status] configure -text $message}
        return 0
    } finally {
        if {[dict exists $::GX::ViewerGui::instances $window semantic_dispatch]} {dict unset ::GX::ViewerGui::instances $window semantic_dispatch}
    }
}
proc ::GX::_viewerGuiRasterSemanticMenu {window component canvas detail} {
    set instance [dict get $::GX::ViewerGui::instances $window]
    foreach definition [dict get $instance design components] {
        set p [dict get $definition properties]
        if {[dict get $definition type] ne {context_menu} || [datasetPublicationV2DictDefault $p semantic_viewport {}] ne $component} continue
        set pick [dict get $detail pick]
        set entity [expr {[dict get $pick hit] ? {roi} : ([dict get $pick image_hit] ? {object} : {background})}]
        if {[dict exists $pick annotation] && [dict get $pick annotation hit]} {set entity annotation}
        set roi [datasetPublicationV2DictDefault $pick roi_id {}]
        set captured [_viewerGuiRasterSemanticState $window $component $entity $roi]
        set actions {};set order {};set enabled {}
        set catalog [viewerCommandCatalog [dict get $::GX::ViewerCommands::windows $window module]]
        foreach action [dict get $p actions] {
            if {$action eq {-}} continue
            set rule [datasetPublicationV2DictDefault [dict get $p semantic_rules] $action {}]
            if {![_viewerGuiSemanticMatches [dict get $captured values] [datasetPublicationV2DictDefault $rule visible {}]] || ![viewerCommandApplicable $window $action]} continue
            dict set actions $action [list [dict get $catalog $action label] [list ::GX::_viewerGuiSemanticInvoke $window $definition $action $captured]]
            lappend order $action
            dict set enabled $action [expr {[viewerCommandEnabled $window $action] && [_viewerGuiSemanticMatches [dict get $captured values] [datasetPublicationV2DictDefault $rule enabled {}]]}]
        }
        set menu [native2DViewportContextMenu $canvas [dict create entity $entity] $actions {} $order]
        set index -1
        foreach action $order {
            incr index
            $menu entryconfigure $index -state [expr {[dict get $enabled $action] ? {normal} : {disabled}}]
            if {[dict exists $p command_icons $action]} {
                set icon [dict get $p command_icons $action];set icons [dict get $instance design icons]
                uiFieldMenuIconApply $menu $index $icon [dict get $icons [dict get $icon icon]] $icons
            }
        }
        viewerGuiTraceEmit $window [dict get $definition id] semantic_context [dict get $captured values]
        return $menu
    }
    return {}
}
