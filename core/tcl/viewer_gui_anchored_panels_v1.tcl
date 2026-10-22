# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative mounting into the existing Native2D panel/UI Field owners.
# Scientific annotations remain in the original native image Resource.
proc ::GX::_viewerGuiAnchoredDefinitions {design} {
    set definitions {};set result {};set members {}
    foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [_viewerGuiDesignParentOrder [dict get $design components]] {
        set id [dict get $c id];set p [dict get $c properties];set parent [dict get $c parent]
        if {[dict exists $p viewport_anchor]} {
            if {[dict get $c type] ne {section} || [dict exists $members $parent]} {error {A viewport anchored section cannot be nested in another anchored section}}
            set anchor [dict get $p viewport_anchor]
            foreach key [dict keys $anchor] {if {$key ni {viewport target offset}} {error {Unknown viewport anchor field}}}
            set viewport [dict get $anchor viewport];set target [dict get $anchor target]
            if {$target ni {object selection roi annotation} || ![dict exists $definitions $viewport] || [dict get $definitions $viewport type] ne {native2d} || [datasetPublicationV2DictDefault [dict get $definitions $viewport properties] source_kind {}] ne {raster}} {error {Viewport anchor requires a declared raster viewport and object/selection/roi/annotation target}}
            set offset [datasetPublicationV2DictDefault $anchor offset {12 12}]
            if {[llength $offset]!=2} {error {Viewport anchor needs two device offsets}}
            foreach value $offset {if {![string is double -strict $value] || ![expr {abs($value)<=1024}]} {error {Viewport anchor offsets must be finite and at most1024 pixels}}}
            dict set result $id [dict create viewport $viewport target $target offset $offset members {} fields [datasetPublicationV2DictDefault $p annotation_fields {}]]
            dict set members $id $id
        } elseif {[dict exists $p annotation_fields]} {error {Annotation fields require their own anchored section}}
        if {[dict exists $members $parent]} {
            set root [dict get $members $parent]
            if {[dict get $c type] ni {section panel label status field choice entry combobox toggle checkbutton action}} {error {Anchored sections compose existing UI Field controls only}}
            if {[dict exists $p change_action] || [dict exists $p component_visibility]} {error {Transient anchored fields cannot dispatch change actions or toggle persistent regions}}
            dict set members $id $root
            dict set result $root members [concat [dict get $result $root members] [list $id]]
        }
    }
    dict for {id spec} $result {
        set fields [dict get $spec fields]
        if {$fields eq {}} continue
        if {[dict get $spec target] ne {annotation}} {error {Annotation fields require an annotation anchor}}
        foreach required {text font_family font_size color} {if {![dict exists $fields $required]} {error {Annotation editor requires text/font_family/font_size/color fields}}}
        dict for {key child} $fields {
            if {$key ni {text font_family font_size color anchor} || $child ni [dict get $spec members]} {error {Annotation field must name its own declared child and an admitted property}}
            set c [dict get $definitions $child];set p [dict get $c properties];set type [dict get $c type]
            if {$type ni {field choice entry combobox}} {error {Annotation properties require existing typed UI Field values}}
            if {$key eq {font_size} && ($type ne {field} || [datasetPublicationV2DictDefault $p datatype string] ne {number})} {error {Annotation font_size requires a numeric field}}
            if {$key eq {color} && ($type ne {field} || [datasetPublicationV2DictDefault $p datatype string] ne {color})} {error {Annotation color requires an existing color field}}
            if {$key eq {color} && ![datasetPublicationV2DictDefault $p alpha 0]} {error {Annotation color fields must retain the existing native alpha value}}
            if {$key in {text font_family anchor} && $type eq {field} && [datasetPublicationV2DictDefault $p datatype string] ni {string choice}} {error {Annotation text/family/anchor requires a text or choice field}}
        }
        if {[llength [lsort -unique [dict values $fields]]]!=[dict size $fields]} {error {One annotation field cannot edit multiple properties}}
    }
    return $result
}
proc ::GX::_viewerGuiAnchoredInitialize {window} {
    set definitions [_viewerGuiAnchoredDefinitions [dict get $::GX::ViewerGui::instances $window design]]
    dict set ::GX::ViewerGui::instances $window anchored_definitions $definitions
    set members {}
    dict for {root spec} $definitions {foreach id [concat [list $root] [dict get $spec members]] {dict set members $id $root}}
    dict set ::GX::ViewerGui::instances $window anchored_members $members
}
proc ::GX::_viewerGuiAnchoredMember {window id} {
    if {[dict exists $::GX::ViewerGui::instances $window anchored_members $id]} {return [dict get $::GX::ViewerGui::instances $window anchored_members $id]}
    return {}
}
proc ::GX::_viewerGuiRasterCommandValidate {design viewport command} {
    if {$command in {fit cancel finish delete_roi delete_annotation}} {return}
    if {![regexp {^(panel_open|panel_close|editor_apply|editor_cancel):([a-z][a-z0-9_]*)$} $command -> operation id]} {error {Unsupported declared raster command}}
    set definitions [_viewerGuiAnchoredDefinitions $design]
    if {![dict exists $definitions $id] || [dict get $definitions $id viewport] ne $viewport} {error {Raster command must target its own declared anchored section}}
    if {$operation eq {editor_apply} && [dict get $definitions $id fields] eq {}} {error {Apply requires an annotation property binding}}
}
proc ::GX::viewerGuiDesignRasterCommandBindings {design} {
    set result {};set definitions {}
    foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {![dict exists $p raster_command]} continue
        if {[dict get $c type] ne {action} || [llength [dict get $p raster_command]]!=2 || [dict exists $p raster_tool] || [dict exists $p diagram_tool] || [dict exists $p component_visibility]} {error {Raster command binding requires one unambiguous viewport/command action}}
        lassign [dict get $p raster_command] viewport command
        if {![dict exists $definitions $viewport] || [dict get $definitions $viewport type] ne {native2d} || [datasetPublicationV2DictDefault [dict get $definitions $viewport properties] source_kind {}] ne {raster}} {error {Raster command requires its declared raster viewport}}
        _viewerGuiRasterCommandValidate $design $viewport $command
        set id [dict get $p action];set pair [list $viewport $command]
        if {[dict exists $result $id] && [dict get $result $id] ne $pair} {error {One action cannot execute conflicting local raster commands}}
        dict set result $id $pair
    }
    return $result
}
proc ::GX::_viewerGuiAnchoredFieldCallback {window id canvas action args} {
    set root [_viewerGuiAnchoredMember $window $id]
    if {$root eq {} || ![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window anchored_panels $root] || [dict get $::GX::ViewerGui::instances $window anchored_panels $root canvas] ne $canvas || ![winfo exists $canvas]} {
        if {$action eq {}} {return}
        error {Anchored control belongs to a previous viewport}
    }
    if {$action ne {}} {return [viewerCommandInvoke $window $action]}
    # Ordinary UI Field validates the draft. It is not a scientific edit until
    # the explicit owning Apply command accepts it.
    return
}
proc ::GX::_viewerGuiAnchoredEscape {window root canvas} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerGui::instances $window anchored_panels $root] || [dict get $::GX::ViewerGui::instances $window anchored_panels $root canvas] ne $canvas || [dict get $::GX::ViewerGui::instances $window anchored_panels $root capture] eq {}} {return}
    # The existing selector/color dialog keeps its own Escape/grab behavior.
    if {[grab current $window] ne {}} {return}
    _viewerGuiAnchoredClose $window $root
    return -code break
}
proc ::GX::_viewerGuiAnchoredEscapeDispose {tag widget actual} {
    if {$actual eq $widget} {foreach sequence [bind $tag] {bind $tag $sequence {}}}
}
proc ::GX::_viewerGuiAnchoredPrepare {window viewport canvas} {
    set instance [dict get $::GX::ViewerGui::instances $window]
    set widgets [dict get $instance widgets];set records {};set obsolete {}
    dict for {root spec} [dict get $instance anchored_definitions] {
        if {[dict get $spec viewport] ne $viewport} continue
        set definition [viewerGuiDesignComponent $window $root]
        set panel gx_editor_$root
        set body [native2DViewportPanelCreate $canvas $panel [datasetPublicationV2DictDefault [dict get $definition properties] title Properties] top-left {scroll 1 max_width 360 max_height 360 priority 20}]
        set prior [dict get $instance widgets $root]
        dict set records $root [dict create canvas $canvas viewport $viewport panel $panel body $body capture {}]
        dict set widgets $root $body
        foreach id [dict get $spec members] {
            set c [viewerGuiDesignComponent $window $id];set p [dict get $c properties];set type [dict get $c type]
            set host [dict get $widgets [dict get $c parent]];set widget $host.$id
            set action {};if {$type eq {action}} {set action [dict get $p action]}
            _viewerGuiDesignUIFieldMount $window $c $widget [dict get $instance mode] {} [list ::GX::_viewerGuiAnchoredFieldCallback $window $id $canvas $action]
            if {[dict exists $p icon] && [dict get $p icon] ne {}} {uiFieldIconApply $widget $p [dict get $instance design icons [dict get $p icon]] [dict get $instance design icons]}
            set layout [dict get $c layout]
            uiFieldComponentLayout $widget $host $layout
            if {[datasetPublicationV2DictDefault $layout manager grid] ne {pack}} {grid columnconfigure $host [datasetPublicationV2DictDefault $layout column 0] -weight 1}
            _viewerGuiDesignTraceMount $window $id $widget
            set tag GXAnchoredEscape[format %08x [zlib crc32 $canvas]].$id
            bind $tag <Escape> [list ::GX::_viewerGuiAnchoredEscape $window $root $canvas]
            bind $tag <Destroy> [list ::GX::_viewerGuiAnchoredEscapeDispose $tag $widget %W]
            set descendants [list $widget]
            for {set i 0} {$i<[llength $descendants]} {incr i} {
                set child [lindex $descendants $i]
                if {$tag ni [bindtags $child]} {bindtags $child [linsert [bindtags $child] 1 $tag]}
                lappend descendants {*}[winfo children $child]
            }
            dict set widgets $id $widget
        }
        native2DViewportPanelShow $canvas $panel 0
        if {$prior ne $body && [string first "$prior." $body]!=0} {lappend obsolete $prior}
    }
    set mapping {}
    foreach c [dict get $instance design components] {
        if {[dict get $c type] ne {action}} continue
        set id [dict get $c id];set widget [dict get $widgets $id]
        if {[winfo exists $widget]} {dict lappend mapping [dict get $c properties action] $widget}
    }
    viewerCommandWidgetsValidate $window $mapping
    return [dict create widgets $widgets records $records mapping $mapping obsolete $obsolete]
}
proc ::GX::_viewerGuiAnchoredCommit {window prepared} {
    dict set ::GX::ViewerGui::instances $window widgets [dict get $prepared widgets]
    dict for {root record} [dict get $prepared records] {dict set ::GX::ViewerGui::instances $window anchored_panels $root $record}
    viewerCommandWidgetsAttach $window [dict get $prepared mapping]
    foreach widget [dict get $prepared obsolete] {if {[winfo exists $widget]} {destroy $widget}}
}
proc ::GX::_viewerGuiAnchoredCaptureValues {window} {
    set values [viewerGuiDesignValues $window]
    dict for {id root} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] anchored_members {}] {
        set c [viewerGuiDesignComponent $window $id]
        dict set values $id [datasetPublicationV2DictDefault [dict get $c properties] default [expr {[dict get $c type] in {toggle checkbutton} ? 0 : {}}]]
    }
    return $values
}
proc ::GX::_viewerGuiAnchoredCurrent {window root} {
    if {![viewerGuiDesignGuard $window]} {error {Anchored editor belongs to a previous Session}}
    set panel [dict get $::GX::ViewerGui::instances $window anchored_panels $root]
    set viewport [dict get $panel viewport];set runtime [_viewerGuiRasterRuntime $window $viewport]
    if {[dict get $runtime canvas] ne [dict get $panel canvas]} {error {Anchored editor viewport was replaced}}
    set binding [dict get $::GX::ViewerGui::instances $window bindings $viewport]
    if {[dict remove [interactiveDocumentRead [dict get $binding document_id]] payload] ne [dict get $binding document_receipt]} {error {Anchored editor Document changed outside this Viewer}}
    return [list $panel $runtime]
}
proc ::GX::_viewerGuiAnchoredClose {window root} {
    if {![dict exists $::GX::ViewerGui::instances $window anchored_panels $root]} return
    set panel [dict get $::GX::ViewerGui::instances $window anchored_panels $root]
    set focused [focus];set body [dict get $panel body]
    if {$focused eq $body || [string first "$body." $focused]==0} {focus [dict get $panel canvas]}
    if {[winfo exists [dict get $panel canvas]]} {native2DViewportPanelShow [dict get $panel canvas] [dict get $panel panel] 0}
    dict set ::GX::ViewerGui::instances $window anchored_panels $root capture {}
    viewerGuiActionsRefresh $window
}
proc ::GX::_viewerGuiAnchoredOpen {window root} {
    lassign [_viewerGuiAnchoredCurrent $window $root] panel runtime
    # If populating any declared field fails, the previous target/draft cannot
    # remain an applicable Apply destination.
    _viewerGuiAnchoredClose $window $root
    set spec [dict get $::GX::ViewerGui::instances $window anchored_definitions $root]
    set canvas [dict get $runtime canvas];set record [_native2DViewportRasterRequire $canvas]
    set token [dict get $record token];set object [dict get $record object];set kind [dict get $spec target]
    set target [dict create scene_token $token kind $kind object_token $object offset [dict get $spec offset]]
    set capture [dict create token $token object $object kind $kind]
    if {$kind in {object selection}} {
        set scene [_native2DGeometryRequire $token]
        if {![dict get [::GX::Native2D::core selection_summary [dict get $scene native] [_native2DGeometryObject $scene $object]] count]} {error {Select an existing image before opening its controls}}
    }
    if {$kind eq {roi}} {
        set id [dict get $record selected_roi]
        if {$id eq {}} {error {Select an existing ROI before opening its controls}}
        dict set target roi_id $id;dict set capture roi_id $id
    } elseif {$kind eq {annotation}} {
        set id [dict get $record selected_annotation];set generation [dict get $record annotation_generation]
        if {$id eq {}} {error {Select an existing annotation before opening its properties}}
        set collection [native2DGeometryCall $token raster_annotation_get [dict create object_token $object]]
        if {![dict exists $collection generations $id] || [dict get $collection generations $id]!=$generation} {error {Selected annotation identity changed}}
        dict set target annotation_id $id;dict set target annotation_generation $generation
        dict set capture annotation_id $id;dict set capture generation $generation
        dict set capture revision [dict get $collection revision];dict set capture definition [dict get $collection annotations $id]
        dict for {key field} [dict get $spec fields] {viewerGuiDesignValueSet $window $field [dict get $capture definition $key]}
    }
    native2DViewportPanelTarget $canvas [dict get $panel panel] $target
    dict set ::GX::ViewerGui::instances $window anchored_panels $root capture $capture
    native2DViewportPanelCollapse $canvas [dict get $panel panel] 0
    native2DViewportPanelShow $canvas [dict get $panel panel] 1
    # Compiled Viewer callbacks can open editors outside viewerCommandInvoke.
    # Project the accepted target into the actual controls before returning.
    viewerGuiActionsRefresh $window
    return [dict create status opened target_kind $kind]
}
proc ::GX::_viewerGuiAnchoredActionEnabled {window action} {
    set bindings [viewerGuiDesignRasterCommandBindings [dict get $::GX::ViewerGui::instances $window design]]
    if {![dict exists $bindings $action]} {return {}}
    lassign [dict get $bindings $action] viewport command
    if {[catch {set runtime [_viewerGuiRasterRuntime $window $viewport]}]} {return 0}
    if {![regexp {^(panel_open|panel_close|editor_apply|editor_cancel):([a-z][a-z0-9_]*)$} $command -> operation root]} {return 1}
    if {[catch {lassign [_viewerGuiAnchoredCurrent $window $root] panel runtime}]} {return 0}
    if {$operation in {panel_close editor_cancel}} {return [expr {[dict get $panel capture] ne {}}]}
    set record [_native2DViewportRasterRequire [dict get $runtime canvas]]
    if {$operation eq {editor_apply}} {
        if {[dict get $panel capture] eq {}} {return 0}
        return [expr {![catch {_native2DRasterEditable [_native2DGeometryRequire [dict get $record token]] [dict get $record object]}]}]
    }
    set target [dict get $::GX::ViewerGui::instances $window anchored_definitions $root target]
    if {$target eq {annotation}} {return [expr {[dict get $record selected_annotation] ne {}}]}
    if {$target eq {roi}} {return [expr {[dict get $record selected_roi] ne {}}]}
    set scene [_native2DGeometryRequire [dict get $record token]]
    return [expr {[dict get [::GX::Native2D::core selection_summary [dict get $scene native] [_native2DGeometryObject $scene [dict get $record object]]] count]>0}]
}
proc ::GX::_viewerGuiAnchoredApply {window root} {
    lassign [_viewerGuiAnchoredCurrent $window $root] panel runtime
    set capture [dict get $panel capture]
    if {$capture eq {} || [dict get $capture kind] ne {annotation}} {error {Open the current annotation editor before applying}}
    set record [_native2DViewportRasterRequire [dict get $panel canvas]]
    if {[dict get $record selected_annotation] ne [dict get $capture annotation_id] || [dict get $record annotation_generation] ne [dict get $capture generation]} {error {Editor selection changed; reopen its current target}}
    set definition [dict get $capture definition]
    set fields [dict get $::GX::ViewerGui::instances $window anchored_definitions $root fields]
    dict for {key id} $fields {
        set component [viewerGuiDesignComponent $window $id];set widget [dict get $::GX::ViewerGui::instances $window widgets $id]
        # Read and normalize through the existing public UI Field owner, even
        # when the user pressed Apply without leaving the current entry.
        set value [viewerGuiDesignValueSet $window $id [uiFieldComponentRead $widget [dict get $component type]]]
        dict set definition $key $value
    }
    set result [native2DViewportRasterAnnotationEdit [dict get $runtime canvas] set [dict get $capture annotation_id] [dict get $capture revision] [dict get $capture generation] $definition]
    _viewerGuiAnchoredOpen $window $root
    return [dict create status applied revision [dict get $result revision]]
}
proc ::GX::_viewerGuiAnchoredSelectionChanged {window viewport} {
    dict for {root panel} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] anchored_panels {}] {
        if {[dict get $panel viewport] ne $viewport || [dict get $panel capture] eq {}} continue
        set capture [dict get $panel capture]
        set record [_native2DViewportRasterRequire [dict get $panel canvas]]
        set kind [dict get $capture kind];set keep 1
        if {$kind eq {annotation}} {set keep [expr {[dict get $record selected_annotation] eq [dict get $capture annotation_id] && [dict get $record annotation_generation] eq [dict get $capture generation]}]}
        if {$kind eq {roi}} {set keep [expr {[dict get $record selected_roi] eq [dict get $capture roi_id]}]}
        if {$kind in {object selection}} {
            set native [dict get [_native2DGeometryRequire [dict get $record token]] native]
            set keep [expr {[dict get [::GX::Native2D::core selection_summary $native [_native2DGeometryObject [_native2DGeometryRequire [dict get $record token]] [dict get $record object]]] count]>0}]
        }
        if {!$keep} {_viewerGuiAnchoredClose $window $root}
    }
}
