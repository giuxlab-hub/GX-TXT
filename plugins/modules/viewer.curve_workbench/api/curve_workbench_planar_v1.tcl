# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation and editing only; scientific commit belongs to the source owner.
proc ::GX::CurveWorkbench::_planarIntake {w document mode} {
    variable st
    set begin [::GX::native3DPlanarEditBegin $document $mode]
    set payload [dict get $begin payload]
    set st($w,planarToken) [dict get $begin token]
    set st($w,planarContext) [dict get $begin context]
    set st($w,sketchUnit) [dict get $payload working_unit]
    set st($w,importTransaction) 1
    try {
        dict for {logical definition} [dict get $payload $mode definitions] {
            set native [::GX::Native2D::core sketch_create $st($w,scene) [dict get $definition definition] 257]
            set record [_newRecord $w [dict get $definition name] [_sketchSamples $w $native] {} x y {} {} {} {} {} [list [dict create operation $mode source_document $document source_feature $logical]]]
            dict set record working_unit $st($w,sketchUnit);dict set record sketch_provenance [dict get $definition provenance]
            dict set record sketch_attributes gx.source_feature $logical
            dict set record sketch_attributes gx.native3d.logical_cell_id [dict get $definition provenance source_contour]
            _addRecord $w $record $native
        }
    } finally {set st($w,importTransaction) 0}
    _save $w
    set ref [dict get $payload reference];set public [::GX::native2DGeometryOpen $st($w,document)]
    try {
        set image [::GX::native2DGeometryCall $public image_attach [dict create resource [dict get $ref resource] working_unit $st($w,sketchUnit) state [dict create scale [dict get $ref scale] translation [dict get $ref translation] opacity [dict get $payload presentation reference_opacity]]]]
        set handle [dict get $image object_token]
        ::GX::native2DGeometryCall $public image_calibrate [dict create object_token $handle point_a {0 0} point_b [list [dict get $ref width] 0] distance [expr {[dict get $ref scale]*[dict get $ref width]}]]
        set state [dict get [::GX::native2DGeometryCall $public image_get [dict create object_token $handle]] image_state]
        dict set state locked 1;dict set state visible [dict get $payload presentation reference_visible]
        set native [::GX::Native2D::core image_create $st($w,scene) $state]
        ::GX::native2DReferenceImageBind $st($w,scene) $native [dict get $ref resource]
        set id image[incr st($w,nextImage)]
        dict set st($w,images) $id [dict create id $id name {3D Reference Image} native $native resource [dict get $ref resource] planar_reference $ref]
        set st($w,planarImage) $id
    } finally {::GX::native2DGeometryClose $public}
    ::GX::Native2D::core aspect $st($w,scene) xy_equal
    ::GX::Native2D::core fit $st($w,scene)
    _curveList $w;_draw $w;_save $w;_planarControls $w
}
proc ::GX::CurveWorkbench::_planarControls {w} {
    variable st
    if {![info exists st($w,planarContext)]} return
    # Reopen a saved draft only against its original durable owner revision.
    # Session/worker tokens are deliberately reacquired, never deserialized.
    set stale {}
    if {![info exists st($w,planarToken)] && ![::GX::datasetPublicationV2DictDefault $st($w,planarContext) staged_origin 0]} {
        if {[catch {
            set context $st($w,planarContext)
            set owner [::GX::interactiveDocumentRead [dict get $context document_id]]
            foreach key {revision generation sha256} {if {[dict get $owner $key] ne [dict get $context $key]} {error {Source changed; cancel this draft and reopen the current source}}}
            set begin [::GX::native3DPlanarEditBegin [dict get $context document_id] [dict get $context mode]]
            set st($w,planarToken) [dict get $begin token]
            set st($w,planarContext) [dict get $begin context]
        } stale]} {set st($w,status) "3D draft unavailable: $stale"} else {set stale {}}
    }
    if {[winfo exists $w.planar]} {destroy $w.planar}
    set st($w,planarImage) {}
    dict for {id r} $st($w,images) {if {[dict exists $r planar_reference]} {set st($w,planarImage) $id;break}}
    if {$st($w,planarImage) eq {}} return
    set image [::GX::Native2D::core image_get $st($w,scene) [dict get $st($w,images) $st($w,planarImage) native]]
    set st($w,referenceVisible) [dict get $image visible];set st($w,referenceOpacity) [expr {100*[dict get $image opacity]}]
    ttk::frame $w.planar
    pack $w.planar -before $w.main -fill x -padx 5 -pady 4
    ttk::checkbutton $w.planar.visible -text {Show 3D Reference Image} -variable ::GX::CurveWorkbench::st($w,referenceVisible) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_planarPresentation $w]]
    ttk::label $w.planar.label -text {Reference Image Opacity 0–100%}
    ttk::scale $w.planar.opacity -from 0 -to 100 -variable ::GX::CurveWorkbench::st($w,referenceOpacity) -command [list ::GX::CurveWorkbench::_planarOpacity $w]
    ttk::button $w.planar.accept -text {Accept → 3D} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_planarFinish $w 1]]
    ttk::button $w.planar.cancel -text {Cancel 3D Edit} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_planarFinish $w 0]]
    if {$stale ne {}} {$w.planar.accept state disabled}
    pack $w.planar.visible $w.planar.label $w.planar.opacity $w.planar.accept $w.planar.cancel -side left -padx 5
}
proc ::GX::CurveWorkbench::_planarOpacity {w value} {_safe $w [list ::GX::CurveWorkbench::_planarPresentation $w]}
proc ::GX::CurveWorkbench::_planarPresentation {w} {
    variable st
    set id $st($w,planarImage);set native [dict get $st($w,images) $id native]
    set state [::GX::Native2D::core image_get $st($w,scene) $native]
    dict set state visible $st($w,referenceVisible);dict set state opacity [expr {$st($w,referenceOpacity)/100.0}]
    ::GX::Native2D::core image_update $st($w,scene) $native $state
    _draw $w;_save $w
}
proc ::GX::CurveWorkbench::_planarFinish {w accept} {
    variable st
    set context $st($w,planarContext);set document [dict get $context document_id]
    set staged [::GX::datasetPublicationV2DictDefault $context staged_origin 0]
    set origin [dict exists [dict get [::GX::_native3DPlanarOwner $document] payload] origin_workspace]
    if {$accept && !$staged} {
        if {![info exists st($w,planarToken)]} {
            set owner [::GX::interactiveDocumentRead $document]
            foreach key {revision generation sha256} {if {[dict get $context $key] ne [dict get $owner $key]} {error {Saved edit source is stale; reopen a new section/projection from the modern Viewer}}}
            set st($w,planarToken) [dict get [::GX::native3DPlanarEditBegin $document [dict get $context mode]] token]
        }
        set definitions {}
        dict for {id record} $st($w,curves) {
            set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
            if {$definition eq {}} {error {Return requires retained editable curve definitions}}
            dict set definitions $id [dict create name [dict get $record name] definition $definition units [list [dict get $record working_unit] [dict get $record working_unit]]]
        }
        ::GX::native3DPlanarEditAccept $st($w,planarToken) $definitions $st($w,sketchUnit) [dict create reference_opacity [expr {$st($w,referenceOpacity)/100.0}] reference_visible $st($w,referenceVisible)]
        unset st($w,planarToken)
        if {$origin} {
            # The planar owner committed. Retain a durable retry state before
            # asking the independent destination owner to commit its profile.
            dict set st($w,planarContext) staged_origin 1
            set owner [::GX::interactiveDocumentRead $document]
            foreach key {revision generation sha256} {dict set st($w,planarContext) $key [dict get $owner $key]}
            _save $w
        }
    }
    if {$accept && $origin} {
        if {[catch {set returned [::GX::native3DPlanarOriginCommit $document]} message opts]} {
            _planarControls $w
            $w.planar.accept configure -text {Commit staged result → 3D}
            set st($w,status) "Planar result retained; originating3D commit is pending: $message"
            return -options $opts $message
        }
    } elseif {!$accept && [info exists st($w,planarToken)]} {::GX::native3DPlanarEditCancel $st($w,planarToken)}
    unset -nocomplain st($w,planarToken) st($w,planarContext)
    destroy $w.planar;_save $w
    if {!($accept && $origin)} {
        if {$accept} {::GX::native3DPlanarShow $document accepted} else {catch {::GX::native3DPlanarShow $document all}}
    }
    if {$accept && $origin} {set st($w,status) "Accepted profile in original3D Workspace [dict get $returned document_id]; source body preserved."} elseif {$accept} {set st($w,status) {Accepted: new curve on the working plane; original3D source preserved.}} else {set st($w,status) {Cancelled: originating scientific source unchanged; any already staged planar result remains retained.}}
}

# Existing selection authority invokes this optional adapter, never a second
# selection store. The saved correspondence is scoped by document revision.
proc ::GX::CurveWorkbench::_planarSelectionChanged {w} {
    variable st
    if {![info exists st($w,planarContext)]||[info exists st($w,planarSelectionEcho)]} return
    if {[info exists st($w,planarFocusJob)]} {after cancel $st($w,planarFocusJob)}
    set st($w,planarFocusJob) [after 90 [list ::GX::CurveWorkbench::_planarFocusSelection $w]]
}
proc ::GX::CurveWorkbench::_planarFocusSelection {w} {
    variable st
    unset -nocomplain st($w,planarFocusJob)
    if {![winfo exists $w]||![info exists st($w,planarContext)]||$st($w,objectSelection) eq {}} return
    set context $st($w,planarContext);set document [dict get $context document_id]
    if {[catch {
        set owner [::GX::interactiveDocumentRead $document]
        foreach key {revision generation sha256} {if {[dict get $owner $key] ne [dict get $context $key]} {error {Source selection is stale}}}
        set record [dict get $st($w,curves) [lindex $st($w,objectSelection) end]]
        set st($w,planarFocusReceipt) [::GX::native3DPlanarFocus $document [dict get $context mode] [dict get $record sketch_attributes gx.native3d.logical_cell_id]]
    } message]} {set st($w,planarFocusReceipt) [dict create unavailable $message]}
}
proc ::GX::CurveWorkbench::planarSelectFrom3D {document pick} {
    variable st;set w .curve_workbench
    if {![winfo exists $w]||![info exists st($w,planarContext)]||[dict get $st($w,planarContext) document_id] ne $document||![dict exists $pick logical_cell_id]} return
    set mode [dict get $st($w,planarContext) mode]
    if {[dict get $pick layer_id] ne "${document}_$mode"} return
    set owner [::GX::interactiveDocumentRead $document]
    foreach key {revision generation sha256} {if {[dict get $owner $key] ne [dict get $st($w,planarContext) $key]} return}
    dict for {id record} $st($w,curves) {
        if {[dict exists $record sketch_attributes gx.native3d.logical_cell_id]&&[dict get $record sketch_attributes gx.native3d.logical_cell_id]==[dict get $pick logical_cell_id]} {
            set st($w,planarSelectionEcho) 1
            try {_semanticApply $w [list [dict create kind object id [dict get $record native] index 0]];_curveList $w;_draw $w} finally {unset st($w,planarSelectionEcho)}
            return
        }
    }
}
