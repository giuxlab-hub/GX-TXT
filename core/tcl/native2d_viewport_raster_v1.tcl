# SPDX-License-Identifier: GPL-3.0-or-later
# Reusable raster gestures in the existing ViewportHost. Geometry, ROI storage,
# projection and transforms remain in the native scene; this is host dispatch.
proc ::GX::native2DViewportRasterAttach {host token object callback} {
    variable ::GX::ViewportHost::hosts
    set scene [_native2DGeometryRequire $token]
    _native2DRasterImage $scene $object
    if {[dict get $hosts $host scene] ne [dict get $scene native]} {error {Raster controller belongs to another viewport}}
    dict set hosts $host raster [dict create token $token object $object callback $callback tool select selected_roi {} selected_annotation {} annotation_generation {} gesture {} draft {} draft_view {} proposal {} hover {} size [list [winfo width $host] [winfo height $host]]]
    ::GX::Native2D::core select_object [dict get $scene native] [_native2DGeometryObject $scene $object] replace
    foreach {event action} {
        <ButtonPress-1> press <B1-Motion> motion <ButtonRelease-1> release
        <Motion> hover <Return> finish <Escape> cancel <Delete> delete_roi
        <ButtonPress-2> pan_begin <B2-Motion> pan <ButtonRelease-2> pan_end
        <Button-4> zoom_in <Button-5> zoom_out <Button-3> context
    } {bind $host $event [list ::GX::_native2DViewportRasterEvent $host $action %x %y]}
    bind $host <MouseWheel> [list ::GX::_native2DViewportRasterWheel $host %D %x %y]
    bind $host <Configure> +[list ::GX::_native2DViewportRasterResize $host %w %h]
    set panel [native2DViewportPanelCreate $host raster_tools {Image tools} top-left {orientation horizontal max_width 620 priority 20}]
    foreach {tool label icon} {select Select select rectangle {Rectangle ROI} roi_rectangle polygon {Polygon ROI} roi_polygon annotation {Add text annotation} text move Move transform rotate Rotate rotate pivot Pivot pivot pan Pan pan} {
        ttk::button $panel.$tool -image [native2DViewportGlyph $icon] -command [list ::GX::native2DViewportRasterTool $host $tool]
        pack $panel.$tool -side left
        native2DViewportTooltip $panel.$tool $label
    }
    native2DViewportRasterTool $host select
    return [native2DViewportRasterDescribe $host]
}
proc ::GX::_native2DViewportRasterRequire {host} {
    variable ::GX::ViewportHost::hosts
    if {![winfo exists $host] || ![dict exists $hosts $host raster]} {error {Raster viewport is closed}}
    set record [dict get $hosts $host raster]
    set scene [_native2DGeometryRequire [dict get $record token]]
    if {[dict get $scene native] ne [dict get $hosts $host scene]} {error {Raster viewport owner changed}}
    _native2DRasterImage $scene [dict get $record object]
    return $record
}
proc ::GX::native2DViewportRasterDescribe {host} {
    set record [_native2DViewportRasterRequire $host]
    return [dict create tool [dict get $record tool] object_token [dict get $record object] roi_id [dict get $record selected_roi] annotation_id [dict get $record selected_annotation] annotation_generation [dict get $record annotation_generation] gesture_active [expr {[dict get $record gesture] ne {}}] polygon_vertices [llength [dict get $record draft]] source_pixel_authority NATIVE_2D_GEOMETRY_API_v1]
}
proc ::GX::_native2DViewportRasterNotify {host event detail} {
    set record [_native2DViewportRasterRequire $host]
    set callback [dict get $record callback]
    if {$callback ne {}} {return [uplevel #0 [list {*}$callback $host $event $detail]]}
}
proc ::GX::_native2DViewportRasterCancelOwned {host} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host raster]} return
    set record [dict get $hosts $host raster];set gesture [dict get $record gesture]
    set token [dict get $record token]
    # Rollback is cleanup of this retained native owner, not a new scientific
    # request. It must remain possible after its Dataset/Document/Session guard
    # expires, and must never resolve a replacement owner or native scene.
    set failed 0
    if {$gesture ne {} && [dict get $gesture kind] eq {transform} && [dict exists $::GX::Native2DGeometry::scenes $token] && [dict get $::GX::Native2DGeometry::scenes $token native] eq [dict get $hosts $host scene]} {
        set failed [catch {::GX::Native2D::core drag_cancel [dict get $hosts $host scene]} message options]
    }
    dict set hosts $host raster gesture {};dict set hosts $host raster draft {};dict set hosts $host raster draft_view {};dict set hosts $host raster proposal {}
    set callback [dict get $record callback]
    if {$callback ne {}} {catch {uplevel #0 [list {*}$callback $host cancelled {}]}}
    if {$failed} {return -options $options $message}
}
proc ::GX::native2DViewportRasterTool {host tool} {
    variable ::GX::ViewportHost::hosts
    if {$tool ni {select rectangle polygon annotation move rotate pivot pan}} {error {Unsupported shared raster tool}}
    _native2DViewportRasterRequire $host
    native2DViewportRasterCommand $host cancel
    dict set hosts $host raster tool $tool
    set panel [native2DViewportPanelWidget $host raster_tools].body
    foreach name {select rectangle polygon annotation move rotate pivot pan} {native2DViewportToolState $panel.$name [expr {$name eq $tool}]}
    set native [dict get $hosts $host scene]
    ::GX::Native2D::core gizmo $native [dict create visible [expr {$tool in {move rotate pivot}}] mode [expr {$tool eq {rotate} ? {rotate} : {translate}}]]
    _native2DViewportRasterNotify $host tool_changed [dict create tool $tool]
    _native2DViewportRasterRedraw $host
    return [native2DViewportRasterDescribe $host]
}
proc ::GX::_native2DViewportRasterRedraw {host} {
    set record [_native2DViewportRasterRequire $host]
    return [native2DGeometryViewportDraw [dict get $record token] $host [list ::GX::native2DViewportRasterPaint $host]]
}
proc ::GX::native2DViewportRasterPaint {host} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host raster] || ![winfo exists $host]} return
    if {[catch {set record [_native2DViewportRasterRequire $host]}]} return
    set token [dict get $record token];set object [dict get $record object]
    $host delete raster_roi_overlay
    $host delete native_annotation
    native2DCanvasTextSweep $host
    if {![_native2DViewportPanelTargetVisible [_native2DGeometryRequire $token] $object]} return
    set rois [native2DGeometryCall $token raster_roi_get [dict create object_token $object]]
    dict for {id roi} [dict get $rois rois] {
        set projected [native2DGeometryCall $token raster_roi_geometry [dict create object_token $object roi_id $id]]
        set color [expr {$id eq [dict get $record selected_roi] ? {#145cbb} : ($id eq [dict get $record hover] ? {#b86508} : {#16824b})}]
        _native2DViewportRasterOutline $host [dict get $projected device_points] $color 0
        if {$id eq [dict get $record selected_roi]} {
            foreach point [dict get $projected handles] {
                lassign $point x y
                $host create rectangle [expr {$x-4}] [expr {$y-4}] [expr {$x+4}] [expr {$y+4}] -fill white -outline $color -width 2 -tags raster_roi_overlay
            }
        }
    }
    set proposal [dict get $record proposal]
    if {$proposal ne {}} {_native2DViewportRasterOutline $host [dict get $proposal device_points] [expr {[dict get $proposal valid] ? {#145cbb} : {#c22c35}}] 1}
    native2DCanvasClipItems $host [dict get $hosts $host scene] [$host find withtag raster_roi_overlay]
    set annotations [dict get [native2DGeometryCall $token raster_annotation_project [dict create object_token $object]] annotations]
    if {[llength $annotations]} {
        set native [dict get $hosts $host scene]
        set snapshot [native2DPresentationSnapshot $native [dict create axes_visible 0 legend 0 object_labels 0 annotations $annotations]]
        set background [uiFieldColorFromRGBA [dict get [::GX::Native2D::core presentation $native] background]]
        foreach text [dict get $snapshot texts] {if {[dict exists $text annotation_id]} {native2DCanvasTextDraw $host $text $background}}
        native2DCanvasClipItems $host $native [$host find withtag native_annotation]
        set id [dict get $record selected_annotation]
        if {$id ne {}} {
            # Use the existing renderer's actual text bounds; the controller
            # does not estimate font metrics or maintain a second label scene.
            set bounds [$host bbox native_annotation_$id]
            if {[llength $bounds]==4} {$host create rectangle {*}$bounds -outline #145cbb -dash {3 2} -tags raster_roi_overlay}
        }
    }
    native2DCanvasDrawGizmo $host [dict get $hosts $host scene] white
}
proc ::GX::_native2DViewportRasterResize {host width height} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host raster]} return
    if {[dict get $hosts $host raster size] eq [list $width $height]} return
    _native2DViewportRasterCancelOwned $host
    dict set hosts $host raster size [list $width $height]
    catch {_native2DViewportRasterRedraw $host}
}
proc ::GX::_native2DViewportRasterOutline {host points color draft} {
    if {[llength $points]<2} return
    set coordinates [concat {*}$points]
    if {[llength $points]>2} {lappend coordinates {*}[lindex $points 0]}
    set options [list -fill $color -width 2 -tags raster_roi_overlay]
    if {$draft} {lappend options -dash {5 3}}
    $host create line {*}$coordinates {*}$options
}
proc ::GX::_native2DViewportRasterCollection {record} {
    return [native2DGeometryCall [dict get $record token] raster_roi_get [dict create object_token [dict get $record object]]]
}
proc ::GX::_native2DViewportRasterPick {record point} {
    return [native2DGeometryCall [dict get $record token] raster_roi_pick [dict create object_token [dict get $record object] device $point tolerance 7]]
}
proc ::GX::_native2DViewportRasterAnnotationPick {host point} {
    set record [_native2DViewportRasterRequire $host]
    set picked [native2DAnnotationHit $host {*}$point]
    if {![dict get $picked hit]} {return $picked}
    set collection [native2DGeometryCall [dict get $record token] raster_annotation_get [dict create object_token [dict get $record object]]]
    set id [dict get $picked annotation_id]
    if {![dict exists $collection annotations $id]} {error {Rendered annotation no longer exists; redraw the current source}}
    dict set picked generation [dict get $collection generations $id]
    return $picked
}
proc ::GX::_native2DViewportRasterAnnotationSelect {host picked} {
    dict set ::GX::ViewportHost::hosts $host raster selected_annotation [expr {[dict get $picked hit] ? [dict get $picked annotation_id] : {}}]
    dict set ::GX::ViewportHost::hosts $host raster annotation_generation [expr {[dict get $picked hit] ? [dict get $picked generation] : {}}]
    if {[dict get $picked hit]} {dict set ::GX::ViewportHost::hosts $host raster selected_roi {}}
}
proc ::GX::native2DViewportRasterAnnotationEdit {host operation id expected generation {definition {}}} {
    if {$operation ni {set remove}} {error {Image annotation edit must set or remove}}
    set record [_native2DViewportRasterRequire $host]
    set token [dict get $record token];set object [dict get $record object]
    set selection [list [dict get $record selected_annotation] [dict get $record annotation_generation]]
    set request [dict create object_token $object annotation_id $id expected_revision $expected]
    set before [native2DGeometryCall $token raster_annotation_get [dict create object_token $object]]
    if {[dict get $before revision]!=$expected} {error {Image annotations changed; reopen the current editor}}
    if {$generation ne {} && (![dict exists $before generations $id] || [dict get $before generations $id]!=$generation)} {error {Annotation identity was replaced; reopen its current editor}}
    if {$operation eq {set}} {
        set definition [_native2DRasterAnnotationDefinition $definition]
        dict set request definition $definition
        if {[dict exists $before annotations $id] && [dict get $before annotations $id] eq $definition} {return $before}
    }
    _native2DRasterEditable [_native2DGeometryRequire $token] $object
    _native2DViewportRasterNotify $host before_edit [dict create operation annotation_$operation annotation_id $id]
    # PrepareEdit may yield to a History prompt. Do not apply the draft to a
    # replacement scene/image/annotation after that prompt returns.
    try {
        set current [_native2DViewportRasterRequire $host]
        if {[dict get $current token] ne $token || [dict get $current object] ne $object || [list [dict get $current selected_annotation] [dict get $current annotation_generation]] ne $selection || [native2DGeometryCall $token raster_annotation_get [dict create object_token $object]] ne $before} {error {Annotation target changed while preparing History; reopen its current editor}}
        set result [native2DGeometryCall $token raster_annotation_$operation $request]
        if {$operation eq {set}} {
            _native2DViewportRasterAnnotationSelect $host [dict create hit 1 annotation_id $id generation [dict get $result generations $id]]
        } else {_native2DViewportRasterAnnotationSelect $host {hit 0}}
        _native2DViewportRasterNotify $host committed [dict create operation annotation_$operation annotation_id $id]
        _native2DViewportRasterRedraw $host
        return $result
    } on error {message options} {
        catch {_native2DViewportRasterNotify $host cancelled {}}
        return -options $options $message
    }
}
proc ::GX::_native2DViewportRasterProposal {record request} {
    return [native2DGeometryCall [dict get $record token] raster_roi_propose [dict merge [dict create object_token [dict get $record object]] $request]]
}
proc ::GX::_native2DViewportRasterAccept {host proposal id} {
    if {![dict get $proposal valid]} {error "ROI not accepted: [dict get $proposal admission_status]; adjust the vertices or cancel"}
    set record [_native2DViewportRasterRequire $host]
    _native2DViewportRasterNotify $host before_edit [dict create operation roi_set roi_id $id]
    native2DGeometryCall [dict get $record token] raster_roi_set [dict create object_token [dict get $record object] roi_id $id expected_revision [dict get $proposal collection_revision] definition [dict get $proposal definition]]
    dict set ::GX::ViewportHost::hosts $host raster selected_roi $id
    _native2DViewportRasterNotify $host committed [dict create operation roi_set roi_id $id]
}
proc ::GX::native2DViewportRasterCommand {host command} {
    variable ::GX::ViewportHost::hosts
    if {$command eq {cancel}} {
        _native2DViewportRasterCancelOwned $host
        if {[catch {_native2DViewportRasterRedraw $host} message]} {return [dict create status stale_cancelled message $message]}
        return [native2DViewportRasterDescribe $host]
    }
    set record [_native2DViewportRasterRequire $host]
    set token [dict get $record token];set native [dict get $hosts $host scene]
    switch -- $command {
        fit {_native2DViewportRasterCancelOwned $host;native2DGeometryCall $token fit_all {};_native2DViewportRasterNotify $host view_changed {operation fit}}
        finish {
            if {[dict get $record tool] ne {polygon} || [llength [dict get $record draft]]<3} {error {A polygon needs at least three distinct vertices; click to add vertices, Return to finish, Escape to cancel}}
            if {[dict get $record draft_view] ne [::GX::Native2D::core view_state $native]} {
                _native2DViewportRasterCancelOwned $host
                error {Viewport changed during the polygon draft; start again in the current view}
            }
            set collection [_native2DViewportRasterCollection $record]
            set proposal [_native2DViewportRasterProposal $record [dict create operation create kind polygon device_points [dict get $record draft] expected_revision [dict get $collection revision]]]
            _native2DViewportRasterAccept $host $proposal roi_[clock microseconds]
            dict set hosts $host raster draft {};dict set hosts $host raster proposal {}
        }
        delete_roi {
            set id [dict get $record selected_roi]
            if {$id eq {}} {error {Select an existing ROI before deleting it}}
            _native2DViewportRasterCancelOwned $host
            set collection [_native2DViewportRasterCollection $record]
            _native2DViewportRasterNotify $host before_edit [dict create operation roi_remove roi_id $id]
            native2DGeometryCall $token raster_roi_remove [dict create object_token [dict get $record object] roi_id $id expected_revision [dict get $collection revision]]
            dict set hosts $host raster selected_roi {}
            _native2DViewportRasterNotify $host committed [dict create operation roi_remove roi_id $id]
        }
        delete_annotation {
            set id [dict get $record selected_annotation]
            if {$id eq {}} {error {Select an existing text annotation before deleting it}}
            set collection [native2DGeometryCall $token raster_annotation_get [dict create object_token [dict get $record object]]]
            return [native2DViewportRasterAnnotationEdit $host remove $id [dict get $collection revision] [dict get $record annotation_generation]]
        }
        default {error {Unsupported shared raster command}}
    }
    _native2DViewportRasterRedraw $host
    return [native2DViewportRasterDescribe $host]
}
proc ::GX::_native2DViewportRasterWheel {host delta x y} {
    # The existing native view computes the actual zoom and device mapping.
    if {$delta==0} return
    _native2DViewportRasterEvent $host [expr {$delta>0 ? {zoom_in} : {zoom_out}}] $x $y
}
proc ::GX::_native2DViewportRasterEvent {host action x y} {
    variable ::GX::ViewportHost::hosts
    if {[catch {_native2DViewportRasterDispatch $host $action [list $x $y]} message options]} {
        # A stale source never enters a repeated modal-error loop. Roll back
        # this owner's preview independently of scientific-current admission.
        if {[dict exists $hosts $host raster]} {
            set callback [dict get $hosts $host raster callback]
            catch {_native2DViewportRasterCancelOwned $host}
            if {[catch {_native2DViewportRasterRedraw $host}]} {
                # An expired source cannot be drawn as a current valid frame.
                # Hide its transient preview; do not silently resolve another
                # Dataset or write to the expired scientific Document.
                native2DRasterCanvasDispose $host
                $host delete all
                $host create text 14 14 -anchor nw -width [expr {max(120,[winfo width $host]-28)}] -text "Raster source unavailable: $message" -tags raster_source_status
            }
            if {$callback ne {}} {catch {uplevel #0 [list {*}$callback $host error [dict create operation $action message $message errorcode [datasetPublicationV2DictDefault $options -errorcode {}]]]}}
        }
    }
}
proc ::GX::_native2DViewportRasterDispatch {host action point} {
    variable ::GX::ViewportHost::hosts
    set record [_native2DViewportRasterRequire $host]
    set token [dict get $record token];set object [dict get $record object];set native [dict get $hosts $host scene]
    set tool [dict get $record tool];set gesture [dict get $record gesture]
    if {$action in {cancel finish delete_roi}} {return [native2DViewportRasterCommand $host $action]}
    set view [::GX::Native2D::core view_state $native]
    if {($gesture ne {} && [dict get $gesture kind] ne {pan} && [dict get $gesture view] ne $view) || ([llength [dict get $record draft]] && [dict get $record draft_view] ne $view)} {
        _native2DViewportRasterCancelOwned $host
        error {Viewport changed during the draft; the unaccepted gesture was cancelled. Start again in the current view}
    }
    if {$action in {zoom_in zoom_out}} {
        if {$gesture ne {} || [llength [dict get $record draft]]} {return}
        native2DGeometryCall $token zoom [dict create factor [expr {$action eq {zoom_in}?1.2:1/1.2}] point $point]
        _native2DViewportRasterNotify $host view_changed [dict create operation $action]
    } elseif {$action eq {pan_begin} || ($action eq {press} && $tool eq {pan})} {
        if {$gesture ne {} || [llength [dict get $record draft]]} return
        dict set hosts $host raster gesture [dict create kind pan previous $point]
    } elseif {$action eq {pan} || ($action eq {motion} && $gesture ne {} && [dict get $gesture kind] eq {pan})} {
        if {$gesture eq {} || [dict get $gesture kind] ne {pan}} return
        lassign [dict get $gesture previous] oldX oldY;lassign $point x y
        native2DGeometryCall $token pan [dict create delta [list [expr {$x-$oldX}] [expr {$y-$oldY}]]]
        dict set hosts $host raster gesture previous $point
    } elseif {$action eq {pan_end} || ($action eq {release} && $gesture ne {} && [dict get $gesture kind] eq {pan})} {
        if {$gesture ne {} && [dict get $gesture kind] eq {pan}} {dict set hosts $host raster gesture {};_native2DViewportRasterNotify $host view_changed {operation pan}}
    } elseif {$action eq {hover}} {
        if {$gesture ne {}} return
        set picked [_native2DViewportRasterPick $record $point]
        dict set hosts $host raster hover [expr {[dict get $picked hit] ? [dict get $picked roi_id] : {}}]
        if {$tool eq {polygon} && [llength [dict get $record draft]]} {
            set proposal [_native2DViewportRasterProposal $record [dict create operation create kind polygon device_points [concat [dict get $record draft] [list $point]]]]
            dict set hosts $host raster proposal $proposal
        }
    } elseif {$action eq {press}} {
        focus $host
        if {$tool eq {annotation}} {
            set picked [_native2DViewportRasterPick $record $point]
            if {![dict get $picked image_hit]} {error {Place a text annotation on the visible image}}
            set world [dict get [native2DGeometryCall $token device_to_world [dict create point $point]] point]
            set pixel [dict get [native2DGeometryCall $token image_map [dict create object_token $object point $world inverse 1]] point]
            set collection [native2DGeometryCall $token raster_annotation_get [dict create object_token $object]]
            set id annotation_[clock microseconds]
            native2DViewportRasterAnnotationEdit $host set $id [dict get $collection revision] {} [dict create point $pixel text Annotation]
            _native2DViewportRasterNotify $host selection_changed [native2DViewportRasterDescribe $host]
        } elseif {$tool eq {polygon}} {
            set draft [dict get $record draft];lappend draft $point
            set proposal [_native2DViewportRasterProposal $record [dict create operation create kind polygon device_points $draft]]
            dict set hosts $host raster draft $draft;dict set hosts $host raster proposal $proposal
            dict set hosts $host raster draft_view $view
        } elseif {$tool eq {rectangle}} {
            set collection [_native2DViewportRasterCollection $record]
            dict set hosts $host raster gesture [dict create kind create start $point revision [dict get $collection revision] view $view]
        } elseif {$tool eq {select}} {
            set annotation [_native2DViewportRasterAnnotationPick $host $point]
            _native2DViewportRasterAnnotationSelect $host $annotation
            if {[dict get $annotation hit]} {
                _native2DViewportRasterNotify $host selection_changed [native2DViewportRasterDescribe $host]
                _native2DViewportRasterRedraw $host
                return
            }
            set picked [_native2DViewportRasterPick $record $point]
            if {[dict get $picked image_hit]} {::GX::Native2D::core select_object $native [_native2DGeometryObject [_native2DGeometryRequire $token] $object] replace} else {::GX::Native2D::core clear $native}
            dict set hosts $host raster selected_roi [expr {[dict get $picked hit] ? [dict get $picked roi_id] : {}}]
            if {[dict get $picked hit]} {
                dict set hosts $host raster gesture [dict create kind roi operation [expr {[dict get $picked kind] eq {vertex} ? {vertex} : {translate}}] roi_id [dict get $picked roi_id] index [dict get $picked index] start $point revision [dict get $picked collection_revision] view $view]
            }
            _native2DViewportRasterNotify $host selection_changed [native2DViewportRasterDescribe $host]
        } elseif {$tool in {move rotate pivot}} {
            set scene [_native2DGeometryRequire $token];_native2DRasterEditable $scene $object
            ::GX::Native2D::core select_object $native [_native2DGeometryObject $scene $object] replace
            set handle [::GX::Native2D::core gizmo_hit $native $point 8]
            if {$tool eq {pivot}} {
                set world [dict get [native2DGeometryCall $token device_to_world [dict create point $point]] point]
                ::GX::Native2D::core pivot $native custom $world
                _native2DViewportRasterNotify $host view_changed {operation pivot}
            } else {
                if {$handle eq {none}} {set handle [expr {$tool eq {rotate} ? {rotate} : {free}}]}
                _native2DViewportRasterNotify $host before_edit [dict create operation $tool]
                set before [dict get [native2DGeometryCall $token image_get [dict create object_token $object]] image_state]
                ::GX::Native2D::core drag_begin $native
                dict set hosts $host raster gesture [dict create kind transform handle $handle start $point before $before view $view]
            }
        }
    } elseif {$action eq {motion}} {
        if {$gesture eq {}} return
        switch -- [dict get $gesture kind] {
            create {set request [dict create operation create kind rectangle device_points [list [dict get $gesture start] $point] expected_revision [dict get $gesture revision]]}
            roi {set request [dict create operation [dict get $gesture operation] roi_id [dict get $gesture roi_id] index [dict get $gesture index] start_device [dict get $gesture start] end_device $point expected_revision [dict get $gesture revision]]}
            transform {
                set parameters [::GX::Native2D::core gizmo_parameters $native [dict get $gesture handle] [dict get $gesture start] $point]
                if {[dict get $gesture handle] eq {pivot}} {::GX::Native2D::core pivot $native custom [dict get $parameters world_point]
                } elseif {$tool eq {rotate}} {::GX::Native2D::core drag_rotate $native [dict get $parameters pivot] [dict get $parameters radians]
                } else {::GX::Native2D::core drag_translate $native {*}[dict get $parameters translation]}
                set request {}
            }
        }
        if {$request ne {}} {dict set hosts $host raster proposal [_native2DViewportRasterProposal $record $request]}
    } elseif {$action eq {release}} {
        if {$gesture eq {}} return
        # Include the actual release position even when the platform coalesces
        # the last held-button Motion. It still belongs to this same gesture.
        _native2DViewportRasterDispatch $host motion $point
        set record [_native2DViewportRasterRequire $host]
        set proposal [dict get $record proposal]
        if {[dict get $gesture kind] in {create roi}} {
            if {$point ne [dict get $gesture start]} {
                set id [expr {[dict get $gesture kind] eq {roi} ? [dict get $gesture roi_id] : "roi_[clock microseconds]"}]
                _native2DViewportRasterAccept $host $proposal $id
            }
        } elseif {[dict get $gesture kind] eq {transform}} {
            ::GX::Native2D::core drag_commit $native
            set current [dict get [native2DGeometryCall $token image_get [dict create object_token $object]] image_state]
            if {$current ne [dict get $gesture before]} {_native2DViewportRasterNotify $host committed [dict create operation $tool]}
        }
        dict set hosts $host raster gesture {};dict set hosts $host raster proposal {}
    } elseif {$action eq {context}} {
        if {$gesture ne {}} return
        set annotation [_native2DViewportRasterAnnotationPick $host $point]
        _native2DViewportRasterAnnotationSelect $host $annotation
        set picked [_native2DViewportRasterPick $record $point]
        dict set hosts $host raster selected_roi [expr {![dict get $annotation hit] && [dict get $picked hit] ? [dict get $picked roi_id] : {}}]
        dict set picked annotation $annotation
        set declared [_native2DViewportRasterNotify $host context [dict create pick $picked point $point]]
        if {$declared ne {}} {
            lassign $point x y
            tk_popup $declared [expr {[winfo rootx $host]+$x}] [expr {[winfo rooty $host]+$y}]
            _native2DViewportRasterRedraw $host
            return
        }
        set target [dict create entity [expr {[dict get $picked hit] ? {roi} : {object}}] object_token $object]
        if {[dict get $picked hit]} {dict set target roi_id [dict get $picked roi_id]}
        set actions [dict create fit [list {Fit image} [list ::GX::native2DViewportRasterCommand $host fit]]]
        set allowed {fit}
        if {[dict get $picked hit]} {dict set actions delete [list {Delete selected ROI} [list ::GX::native2DViewportRasterCommand $host delete_roi]];lappend allowed delete}
        set domain {}
        if {$tool eq {polygon} && [llength [dict get $record draft]]>=3} {lappend domain [list {Finish polygon} [list ::GX::native2DViewportRasterCommand $host finish]]}
        set menu [native2DViewportContextMenu $host $target $actions $domain $allowed]
        lassign $point x y
        tk_popup $menu [expr {[winfo rootx $host]+$x}] [expr {[winfo rooty $host]+$y}]
    }
    _native2DViewportRasterRedraw $host
}
