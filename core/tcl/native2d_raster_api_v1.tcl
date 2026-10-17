# Native2D retained image geometry/attributes + existing supervised IM execution.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::_native2DRasterImage {scene object} {
    set native [dict get $scene native];set id [_native2DGeometryObject $scene $object]
    set state [::GX::Native2D::core image_get $native $id]
    if {$state eq {}} {error {Raster operation requires an owned reference image}}
    set resource [dict get $scene objects $object metadata image_resource]
    interactiveDocumentResourceInfo $resource
    if {[dict get $state resource_id] ne [dict get $resource sha256]} {error {Raster image resource identity changed}}
    return [dict create id $id state $state resource $resource]
}
proc ::GX::_native2DRasterLayer {native style} {
    # Native layer zero means unlayered: the existing renderer applies no layer
    # visibility/opacity modification and has no editable collection identity.
    if {[dict get $style layer]==0} {return {visible 1 selectable 1 locked 0 order 0 opacity 1}}
    return [::GX::Native2D::core layer_info $native [dict get $style layer]]
}
proc ::GX::_native2DRasterEditable {scene object} {
    set image [_native2DRasterImage $scene $object];set native [dict get $scene native]
    set style [::GX::Native2D::core object_style $native [dict get $image id]]
    set layer [_native2DRasterLayer $native $style]
    if {[dict get $image state locked]||[dict get $layer locked]} {error {Raster image or its existing Native2D layer is locked}}
}
proc ::GX::_native2DRasterProperties {scene object} {
    set image [_native2DRasterImage $scene $object];set native [dict get $scene native]
    set attrs [::GX::Native2D::core identity_attributes $native [dict get $image id]]
    return [dict merge {blend Over mask_uuid {} mask_channel luminance mask_invert 0 mask_only 0 roi_id {}} [datasetPublicationV2DictDefault $attrs gx.raster.layer {}]]
}
proc ::GX::_native2DRasterUUID {scene object} {
    set image [_native2DRasterImage $scene $object];set native [dict get $scene native];set id [dict get $image id]
    set attrs [::GX::Native2D::core identity_attributes $native $id]
    if {[dict exists $attrs gx.raster.uuid]} {return [dict get $attrs gx.raster.uuid]}
    set uuid "raster-[pid]-[clock microseconds]";::GX::Native2D::core identity_attribute $native $id gx.raster.uuid $uuid;return $uuid
}
proc ::GX::_native2DRasterUUIDObject {scene uuid} {
    set found {};dict for {object entry} [dict get $scene objects] {
        set attrs [::GX::Native2D::core identity_attributes [dict get $scene native] [_native2DGeometryObject $scene $object]]
        if {[dict exists $attrs gx.raster.uuid]&&[dict get $attrs gx.raster.uuid] eq $uuid} {lappend found $object}
    }
    if {[llength $found]!=1} {error {Mask image identity is absent or ambiguous; explicitly rebind the mask}}
    return [lindex $found 0]
}
proc ::GX::_native2DRasterMatrix {scene object base} {
    set native [dict get $scene native];set id [_native2DGeometryObject $scene $object];set destination [_native2DGeometryObject $scene $base]
    set sourceState [::GX::Native2D::core image_get $native $id];set targetState [::GX::Native2D::core image_get $native $destination]
    if {[dict get $sourceState length_unit] ne [dict get $targetState length_unit]} {error {Raster images must share an explicit scene working unit; normalize incoming calibration and translation through Unit Registry before composition}}
    set points {};foreach p {{0 0} {1 0} {0 1}} {
        set world [::GX::Native2D::core image_map $native $id $p 0]
        lappend points [::GX::Native2D::core image_map $native $destination $world 1]
    }
    lassign [lindex $points 0] x y;lassign [lindex $points 1] xx xy;lassign [lindex $points 2] yx yy
    return [list [expr {$xx-$x}] [expr {$xy-$y}] [expr {$yx-$x}] [expr {$yy-$y}] $x $y]
}
proc ::GX::_native2DRasterSnapshot {token request} {
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native];set base [dict get $request base_object_token]
    set baseImage [_native2DRasterImage $scene $base];set state [dict get $baseImage state]
    set roi {};set operation [dict get $request operation]
    if {$operation in {mask extract effect}} {
        set collection [::GX::Native2D::core image_roi_get $native [dict get $baseImage id]]
        set roi [dict get $collection rois [dict get $request roi_id]]
        dict set roi source_resource_id [dict get $collection source_resource_id]
        if {[dict get $roi source_resource_id] ne [dict get $state resource_id]} {error {ROI refers to a replaced image resource}}
        dict set roi vertices [dict get $roi points]
    }
    set ordered {};set resources {};set position 0
    dict for {object entry} [dict get $scene objects] {
        set id [_native2DGeometryObject $scene $object];set image [::GX::Native2D::core image_get $native $id]
        if {$image eq {}} continue
        set receipt [_native2DRasterImage $scene $object];set props [_native2DRasterProperties $scene $object]
        set style [::GX::Native2D::core object_style $native $id];set layer [_native2DRasterLayer $native $style]
        set alias image_[incr position];dict set resources $alias [dict get $receipt resource]
        set record [dict create object_token $object alias $alias source_sha256 [dict get $receipt resource sha256] image_state $image \
            layer_id [dict get $style layer] layer_order [dict get $layer order] visible [expr {[dict get $image visible]&&[dict get $layer visible]}] \
            locked [expr {[dict get $image locked]||[dict get $layer locked]}] opacity [expr {[dict get $image opacity]*[dict get $layer opacity]*[datasetPublicationV2DictDefault $style opacity 1]}] \
            blend [dict get $props blend] mask_only [dict get $props mask_only] matrix [_native2DRasterMatrix $scene $object $base]]
        if {[dict get $props mask_uuid] ne {}} {
            set mask [_native2DRasterUUIDObject $scene [dict get $props mask_uuid]];set mr [_native2DRasterImage $scene $mask]
            set ma mask_$position;dict set resources $ma [dict get $mr resource]
            dict set record mask_alias $ma;dict set record mask_sha256 [dict get $mr resource sha256]
            dict set record mask_matrix [_native2DRasterMatrix $scene $mask $base];dict set record mask_invert [dict get $props mask_invert];dict set record mask_channel [dict get $props mask_channel]
        }
        if {[dict get $props roi_id] ne {}} {
            set r [dict get [::GX::Native2D::core image_roi_get $native $id] rois [dict get $props roi_id]]
            set vertices {};foreach point [dict get $r points] {
                set world [::GX::Native2D::core image_map $native $id $point 0]
                lappend vertices [::GX::Native2D::core image_map $native [dict get $baseImage id] $world 1]
            }
            dict set record roi_mask [dict merge $r [dict create vertices $vertices]]
        }
        lappend ordered [list [dict get $layer order] $position $record]
    }
    if {[llength $ordered]>16} {error {Raster composition supports at most16 owned image layers}}
    set layers {};foreach item [lsort -real -index 0 $ordered] {lappend layers [lindex $item 2]}
    set manifest [dict create schema gxtxt.native2d.raster_composition.v1 document_id [dict get $scene document_id] \
        document_generation [dict get $scene generation] document_revision [dict get $scene revision] \
        base_object_token $base width [dict get $state width] height [dict get $state height] \
        base_image_state $state base_resource [dict get $baseImage resource] roi $roi layers $layers]
    return [dict create manifest $manifest resources $resources]
}
proc ::GX::_native2DRasterCall {token operation request} {
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native]
    if {$operation in {raster_snapshot raster_save raster_restore}} {return [_native2DRasterPersistence $token $operation $request]}
    switch -- $operation {
        raster_roi_set - raster_roi_get - raster_roi_remove {
            set image [_native2DRasterImage $scene [dict get $request object_token]];set args [list $native [dict get $image id]]
            if {$operation ne {raster_roi_get}} {_native2DRasterEditable $scene [dict get $request object_token];lappend args [dict get $request roi_id]}
            if {$operation eq {raster_roi_set}} {lappend args [dict get $request definition]}
            return [::GX::Native2D::core [dict get {raster_roi_set image_roi_set raster_roi_get image_roi_get raster_roi_remove image_roi_remove} $operation] {*}$args]
        }
        raster_layer_get {return [_native2DRasterProperties $scene [dict get $request object_token]]}
        raster_layer_update {
            set object [dict get $request object_token];set image [_native2DRasterImage $scene $object];_native2DRasterEditable $scene $object
            set before [_native2DRasterProperties $scene $object];set changes [dict get $request changes]
            foreach key [dict keys $changes] {if {$key ni {blend mask_object_token mask_channel mask_invert mask_only roi_id}} {error "Unsupported raster layer field '$key'; use existing layer/image operations for order, opacity, visibility, transform and lock"}}
            set props $before
            foreach key {blend mask_channel mask_invert mask_only roi_id} {if {[dict exists $changes $key]} {dict set props $key [dict get $changes $key]}}
            if {[dict get $props blend] ni {Over Multiply Screen Overlay SoftLight DstIn}} {error {Unsupported fixed ImageMagick blend mode}}
            if {[dict get $props mask_channel] ni {luminance alpha}} {error {Mask channel must be luminance or alpha}}
            foreach key {mask_invert mask_only} {dict set props $key [uiFieldNormalize {type boolean} [dict get $props $key]]}
            if {[dict exists $changes mask_object_token]} {
                set other [dict get $changes mask_object_token]
                if {$other eq {}} {dict set props mask_uuid {}} else {
                    set seen [list $object];set cursor $other
                    while {$cursor ne {}} {
                        if {$cursor in $seen} {error {Cyclic raster alpha-mask dependency}}
                        lappend seen $cursor;_native2DRasterImage $scene $cursor
                        set next [dict get [_native2DRasterProperties $scene $cursor] mask_uuid]
                        set cursor [expr {$next eq {}?{}:[_native2DRasterUUIDObject $scene $next]}]
                    }
                    if {[dict get [_native2DRasterProperties $scene $other] mask_uuid] ne {}} {error {Chained raster alpha masks are unsupported; materialize the explicit derived grayscale mask first}}
                    set selfAttributes [::GX::Native2D::core identity_attributes $native [dict get $image id]]
                    if {[dict exists $selfAttributes gx.raster.uuid]} {
                        set selfUUID [dict get $selfAttributes gx.raster.uuid]
                        dict for {dependent entry} [dict get $scene objects] {
                            if {[::GX::Native2D::core image_get $native [dict get $entry native]] eq {}} continue
                            if {[dict get [_native2DRasterProperties $scene $dependent] mask_uuid] eq $selfUUID} {error {Chained raster alpha masks are unsupported; materialize the explicit derived grayscale mask first}}
                        }
                    }
                    dict set props mask_uuid [_native2DRasterUUID $scene $other]
                }
            }
            if {[dict get $props roi_id] ne {}} {dict get [::GX::Native2D::core image_roi_get $native [dict get $image id]] rois [dict get $props roi_id]}
            _native2DRasterUUID $scene $object
            ::GX::Native2D::core identity_attribute $native [dict get $image id] gx.raster.layer $props
            return $props
        }
        raster_prepare {
            set op [dict get $request operation]
            if {$op ni {mask extract composite effect}} {error {Unknown fixed raster operation}}
            set snapshot [_native2DRasterSnapshot $token $request];set document [dict get $scene document_id]
            set manifest [managedResourceWrite $document {format native2d.raster_composition.v1 origin native2d_raster scientific_authority 1} [encoding convertto utf-8 [dict get $snapshot manifest]]]
            set resources [dict get $snapshot resources];dict set resources composition $manifest
            set params [dict merge {feather 0 antialias 1 invert 0 effect negate effect_radius 1} [datasetPublicationV2DictDefault $request options {}] [dict create operation $op]]
            set preparation [scientificExecutionPrepare core.native2d.raster $params $resources [dict create document_id $document expected_revision [dict get $scene revision]]]
            return [dict create prepared_token $preparation manifest_resource $manifest source_snapshot [dict get $snapshot manifest] request $request]
        }
        raster_submit {
            set ticket [dict get $request ticket];set now [_native2DRasterSnapshot $token [dict get $ticket request]]
            if {[dict get $now manifest] ne [dict get $ticket source_snapshot]} {error {Raster ROI/layers/transforms changed after preparation; prepare again}}
            return [scientificExecutionSubmit [dict get $ticket prepared_token]]
        }
        raster_freeze {return [scientificExecutionFreezeResource [dict get $request job_id] [dict get $request output_token] [dict get $scene document_id]]}
    }
    error {Unknown Native2D raster operation}
}
proc ::GX::_native2DRasterRegister {} {
    if {![llength [info commands ::GX::scientificExecutionRegister]]} {error {Native2D raster processing requires the existing Scientific Execution authority}}
    scientificExecutionRegister core.native2d.raster [dict create module_id core.native2d version 1.0.0 worker core/python/gxtxt_native2d_raster.py tools magick parameters [dict create \
        operation {type choice values {mask extract composite effect} required 1} feather {type number default 0 min 0 max 16} \
        antialias {type boolean default 1} invert {type boolean default 0} effect {type choice values {negate grayscale blur} default negate} effect_radius {type number default 1 min 0 max 16}]]
}
::GX::_native2DRasterRegister

# Persistence is an ordinary Interactive Document payload containing references
# to existing native geometry resources, not an additional scene/layer store.
proc ::GX::_native2DRasterSnapshotResource {token} {
    set scene [_native2DGeometryRequire $token];set native [dict get $scene native];set layers {};set images {}
    dict for {key entry} [datasetPublicationV2DictDefault $scene layers {}] {
        set id [dict get $entry native]
        lappend layers [dict create key $id properties [dict remove [::GX::Native2D::core layer_info $native $id] id] \
            name [::GX::Native2D::core identity_name $native $id] attributes [::GX::Native2D::core identity_attributes $native $id]]
    }
    dict for {object entry} [dict get $scene objects] {
        set id [_native2DGeometryObject $scene $object];if {[::GX::Native2D::core image_get $native $id] eq {}} continue
        _native2DRasterImage $scene $object
        lappend images [dict create resource [native2DGeometryCall $token export_resource [dict create object_token $object]] \
            style [::GX::Native2D::core object_style $native $id] name [::GX::Native2D::core identity_name $native $id]]
    }
    return [dict create schema gxtxt.native2d.raster_scene.v1 document_id [dict get $scene document_id] \
        generation [dict get $scene generation] layers $layers images $images view_state [::GX::Native2D::core view_state $native]]
}
proc ::GX::_native2DRasterPersistence {token operation request} {
    set scene [_native2DGeometryRequire $token]
    if {$operation eq {raster_snapshot}} {return [_native2DRasterSnapshotResource $token]}
    if {$operation eq {raster_save}} {
        set snapshot [_native2DRasterSnapshotResource $token]
        set payload [dict get [interactiveDocumentRead [dict get $scene document_id]] payload]
        dict set payload native2d_raster $snapshot
        if {[dict exists $request retained_resources]} {dict set payload raster_exports [dict get $request retained_resources]}
        return [native2DGeometryCheckpoint $token $payload]
    }
    if {$operation ne {raster_restore}} {error {Unknown raster persistence operation}}
    if {[dict size [dict get $scene objects]]||[dict size [datasetPublicationV2DictDefault $scene layers {}]]} {error {Restore requires an empty existing Native2D scene; open a fresh scoped scene and replace the old one only after successful restoration}}
    set snapshot [datasetPublicationV2DictDefault $request snapshot [datasetPublicationV2DictDefault [dict get [interactiveDocumentRead [dict get $scene document_id]] payload] native2d_raster {}]]
    if {[dict get $snapshot schema] ne {gxtxt.native2d.raster_scene.v1}||[dict get $snapshot document_id] ne [dict get $scene document_id]||[dict get $snapshot generation] ne [dict get $scene generation]} {error {Raster snapshot belongs to a foreign or replaced Document}}
    set layerMap {};set objects {};set layers {}
    try {
        foreach record [dict get $snapshot layers] {
            set layer [dict get [native2DGeometryCall $token layer_create [dict create properties [dict get $record properties]]] layer_token]
            lappend layers $layer;dict set layerMap [dict get $record key] $layer
            if {[dict get $record name] ne {}} {native2DGeometryCall $token identity [dict create layer_token $layer name [dict get $record name]]}
            dict for {key value} [dict get $record attributes] {native2DGeometryCall $token identity [dict create layer_token $layer key $key value $value]}
        }
        foreach record [dict get $snapshot images] {
            set object [dict get [native2DGeometryCall $token restore_resource [dict create resource [dict get $record resource]]] object_token]
            lappend objects $object;if {[dict get $record name] ne {}} {native2DGeometryCall $token identity [dict create object_token $object name [dict get $record name]]}
            set style [dict get $record style];set layer [dict get $style layer];dict unset style layer
            native2DGeometryCall $token style [dict create object_token $object properties $style]
            if {$layer!=0} {native2DGeometryCall $token layer_assign [dict create object_tokens [list $object] layer_token [dict get $layerMap $layer]]}
        }
        native2DGeometryCall $token view_state [dict create view_state [dict get $snapshot view_state]]
        return [dict create object_tokens $objects layer_tokens $layers source_modified 0]
    } on error {message options} {
        foreach object [lreverse $objects] {catch {native2DGeometryCall $token delete [dict create object_token $object]}}
        foreach layer [lreverse $layers] {catch {native2DGeometryCall $token layer_delete [dict create layer_token $layer]}}
        return -options $options $message
    }
}

# Host-only adapter: the existing scoped geometry owner performs its own
# lifetime checks and passes its native scene to the existing viewport owner.
proc ::GX::native2DGeometryViewportAttach {token container canvas changed} {
    set scene [_native2DGeometryRequire $token]
    if {![winfo exists $canvas]||[winfo class $canvas] ne {Canvas}} {error {Attach requires an existing Tk canvas}}
    native2DViewportHostCreate $container $canvas [dict get $scene native] $changed
    bind $canvas <Configure> +[list ::GX::native2DGeometryViewportDraw $token $canvas $changed]
    bind $canvas <Destroy> +[list ::GX::_native2DGeometryViewportDestroyed $token $canvas %W]
    native2DGeometryViewportDraw $token $canvas $changed
    return $canvas
}
proc ::GX::_native2DGeometryViewportDestroyed {token canvas destroyed} {
    if {$destroyed eq $canvas} {catch {native2DGeometryClose $token}}
}
proc ::GX::native2DGeometryViewportDraw {token canvas {changed {}}} {
    if {![winfo exists $canvas]} {return [dict create status detached]}
    if {[catch {set scene [_native2DGeometryRequire $token]} message]} {return [dict create status stale diagnostic $message]}
    if {[winfo width $canvas]<64||[winfo height $canvas]<64} {return [dict create status pending_layout]}
    set native [dict get $scene native];set view [::GX::Native2D::core view_requested $native]
    lset view 0 [winfo width $canvas];lset view 1 [winfo height $canvas];set view [lreplace $view 2 5 42 24 24 42]
    ::GX::Native2D::core view $native $view
    native2DCanvasSnapshot $canvas [native2DPresentationSnapshot $native {point_budget 4096 legend 0}]
    native2DCanvasReferenceImages $native $canvas
    if {$changed ne {}} {uplevel #0 $changed}
    return [dict create status ready]
}
