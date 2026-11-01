# SPDX-License-Identifier: GPL-3.0-or-later
# Managed exact planar Sketch. Native2D owns definitions/constraints; the
# existing Interactive Document and CORE History own durability and navigation.
namespace eval ::GX::NativeCadSketch {variable serial 0}
proc ::GX::nativeCadSketchApiInfo {} {
    return [dict create api_id NATIVE2D_API_v1 api_version 1 component cad_sketch factory nativeCadSketchCreate \
        methods {widget get state dirty world_scene presentation_scene pending command actions actionState invoke menu palette canvasControls present transform save close} \
        options {document_id working_unit plane presentation changed_command recovery_choice viewport} display_snapshot nativeCadSketchDocumentPresentation \
        scientific_format gxtxt.native_cad_sketch.v1 history CORE_P017 exact_owner Native2D display_policy resident_native_depth_overlay_handles \
        experimental 1 scene_commands {nativeCadSketchSceneAttach nativeCadSketchSceneResolvePick} quick_open_commands {nativeCadSketchQuickOpenPublish nativeCadSketchQuickOpenList nativeCadSketchQuickOpenPresentation nativeCadSketchQuickOpenStatus}]
}
proc ::GX::nativeCadSketchCreate {parent {options {}}} {
    if {![winfo exists $parent]} {error {Sketch parent is unavailable}}
    return [::GX::NativeCadSketch::Component new $parent $options]
}
proc ::GX::NativeCadSketch::validate {record} {
    set state [expr {[dict exists $record base] ? [dict get $record base] : $record}]
    if {![dict exists $state format] || [dict get $state format] ne {gxtxt.native_cad_sketch.v1}} {error {Unsupported exact Sketch model}}
    foreach key {working_unit plane} {dict get $state $key}
    ::GX::unitRegistryConversionPlan [dict get $state working_unit] mm
    return 1
}
proc ::GX::NativeCadSketch::unavailable {args} {error {Use the managed Sketch component for scientific replay}}
::GX::scientificRecipeHostRegister core.native2d [dict create capture ::GX::NativeCadSketch::unavailable validate ::GX::NativeCadSketch::validate replay ::GX::NativeCadSketch::unavailable]

oo::class create ::GX::NativeCadSketch::Component {
    variable w host scene scene3d document generation revision session history model opts objects relations counter before status closing viewport timer failedConstruction newDocument worldCache worldBuilding worldDirty worldStamp rendererError savedHistoryRevision surface mapping projected ownsViewport planeFrame frameId initialFit resident geometryStamp
    constructor {parent options} {
        set w {};set host {};set scene {};set scene3d {};set history {};set viewport {};set timer {};set closing 0;set failedConstruction 1;set newDocument {}
        set objects {};set relations {};set counter 0;set before {};set status Ready
        set worldCache {};set worldBuilding 0;set worldDirty 1;set worldStamp 0;set rendererError {}
        set resident {};set geometryStamp 0
        set savedHistoryRevision 0;set surface {};set mapping {};set projected {};set ownsViewport 0;set planeFrame {};set frameId {};set initialFit 0
        set opts [dict create document_id new working_unit mm plane {origin {0 0 0} normal {0 0 1} u_axis {1 0 0}} presentation canvas changed_command {} viewport {}]
        foreach key [dict keys $options] {if {$key ni {document_id working_unit plane presentation changed_command recovery_choice viewport}} {error "Unknown Sketch option: $key"}}
        set opts [dict merge $opts $options]
        if {[dict get $opts presentation] ni {canvas viewer}} {error {Sketch presentation must be canvas or viewer}}
        llength [dict get $opts changed_command]
        ::GX::unitRegistryConversionPlan [dict get $opts working_unit] mm
        ::GX::native2DEnsure
        set scene [::GX::Native2D::core scene]
        # Present the actual working plane. Native spacing, styles and snapping
        # remain authoritative; enabling display does not enable grid snapping.
        ::GX::Native2D::core grid $scene {enabled 1 visible 1}
        set model [dict create format gxtxt.native_cad_sketch.v1 working_unit [dict get $opts working_unit] plane [dict get $opts plane]]
        set document [dict get $opts document_id];set record {}
        if {$document eq {new} || $document eq {}} {
            set document [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict create model $model allocation_counter 0]] id]
            set newDocument $document
        } else {
            set saved [::GX::interactiveDocumentReadCached $document]
            if {[dict get $saved format] ne {gxtxt.native_cad_sketch.v1}} {error {Document is not an exact Sketch}}
            set payload [dict get $saved payload];set model [dict get $payload model]
            set counter [::GX::datasetPublicationV2DictDefault $payload allocation_counter 0]
            set record [::GX::datasetPublicationV2DictDefault $payload scientific_history {}]
        }
        ::GX::NativeCadSketch::validate $model
        if {[dict get $opts viewport] ne {}} {
            set conversion [::GX::unitRegistryHomogeneousCoordinatePlan [dict get $model working_unit] [dict get $opts working_unit]]
            if {[dict get $conversion scale]!=1} {error {Sketch and borrowed 3D viewport must use the same working coordinate unit for editing. Restore the Workbench unit before opening this Sketch; its saved display can be converted without editing its source.}}
        }
        set metadata [::GX::interactiveDocumentMetadata $document]
        set generation [dict get $metadata generation];set revision [dict get $metadata revision];set session [::GX::interactiveDocumentSessionToken]
        set scene3d [::GX::native3DGeometryOpen $document]
        # Existing Native3D validates/normalizes every physical frame. No Tcl
        # cross products or independent coordinate implementation belongs here.
        set frame [::GX::native3DGeometryCall $scene3d plane_frame [dict create plane [dict get $model plane]]]
        set planeFrame {};foreach key {origin normal u_axis v_axis} {dict set planeFrame $key [dict get $frame $key]}
        dict set model plane [dict remove $planeFrame v_axis]
        set w $parent.sketch[incr ::GX::NativeCadSketch::serial]
        ttk::frame $w
        ttk::label $w.caption -text {Sketch on the working plane · Space-drag: orbit · Space+Shift-drag: pan · Wheel: zoom}
        ttk::label $w.status -text $status -anchor w
        ttk::frame $w.surface
        pack $w.caption -side top -fill x
        pack $w.status -side bottom -fill x
        pack $w.surface -fill both -expand 1
        set callbacks {}
        foreach key {guard admit begin committed cancelled rollback advanced selected error presentation refresh navigation} {dict set callbacks $key [list [self] callback $key]}
        if {[dict get $opts viewport] eq {}} {
            set viewport [::GX::native3DViewportCreate $w.surface.view [dict create projection orthographic axes_world 1]]
            set ownsViewport 1;set initialFit 1
            pack $w.surface.view -fill both -expand 1
            ::GX::native3DViewportBind $viewport [dict create kind cad_sketch sketch [self]]
            set surface [::GX::native3DViewportSurface $viewport]
        } else {
            set requested [dict get $opts viewport]
            if {[::GX::native3DSurfaceIsManaged $requested]} {set surface $requested} else {set viewport $requested;set surface [::GX::native3DViewportSurface $viewport]}
            set initialFit 1
        }
        # Borrow the actual renderer Canvas. Until a matching native camera
        # snapshot arrives, no planar renderer or input interpretation is used.
        set host [::GX::native2DCadCanvasAttach [$surface canvas] $scene [dict create bind_events 0 external_render 1 selection_target detail callbacks $callbacks]]
        set unit [dict get $model working_unit]
        ::GX::native2DAxisPresentation $scene [dict create x [dict create title U context [dict create kind conversion source_unit $unit target_unit $unit]] y [dict create title V context [dict create kind conversion source_unit $unit target_unit $unit]]]
        my restore $model
        set callbacks [dict create capture [list [self] capture] restore [list [self] restore] commit [list [self] project] guard [list [self] historyGuard] document_id $document parent [winfo toplevel $w]]
        if {[dict exists $opts recovery_choice]} {dict set callbacks recovery_choice [dict get $opts recovery_choice]}
        set history [::GX::scientificHistoryContextAttach core.native2d $callbacks $record]
        set savedHistoryRevision [dict get [::GX::scientificHistoryViewerStatus $history] revision]
        bind $w <Destroy> [list [self] destroyed %W]
        set resident [::GX::nativeCadSketchSceneAttach $surface $document [dict create working_unit [dict get $model working_unit]]]
        $resident editing 1
        $surface attach $host [list [self] projectionChanged] [list [self] invoke]
        # A revision-matched closed presentation is already resident. Entering
        # edit binds controls; it does not reconstruct the same derived body.
        my changed {Editor attached}
        $host refresh final
        set failedConstruction 0
    }
    destructor {
        set closing 1
        if {$timer ne {}} {after cancel $timer}
        if {$history ne {}} {catch {::GX::scientificHistoryContextClose $history 0}}
        if {$host ne {} && [llength [info commands $host]]} {catch {::GX::native2DViewportPanelDestroy [$host canvas] cad_tools}}
        if {$resident ne {} && [llength [info commands $resident]]} {catch {$resident editing 0}}
        if {$projected ne {} && [llength [info commands $projected]]} {catch {$projected dispose}}
        if {$mapping ne {} && [llength [info commands $mapping]]} {catch {$mapping dispose}}
        if {$surface ne {} && [llength [info commands $surface]]} {catch {$surface dispose}}
        if {$ownsViewport && $viewport ne {}} {catch {::GX::native3DViewportRelease $viewport}}
        if {$host ne {} && [llength [info commands $host]]} {catch {$host dispose}}
        if {$scene ne {}} {catch {::GX::Native2D::core destroy $scene}}
        if {$scene3d ne {}} {catch {::GX::native3DGeometryClose $scene3d}}
        if {$failedConstruction && $newDocument ne {}} {catch {::GX::interactiveDocumentDelete $newDocument}}
        if {$w ne {} && [winfo exists $w]} {destroy $w}
    }
    method widget {} {return $w}
    method get {key} {
        switch -- $key {
            resident {return $resident} scene {return $scene} host {return $host} context {return [$host context]} advanced {return [$host advanced]}
            document_id {return $document} plane {return [dict get $model plane]} working_unit {return [dict get $model working_unit]}
            history_context {return $history} viewport {return $viewport} surface {return $surface} projection {return $projected} widget {return $w} model {return [my capture]}
            default {error {Unknown Sketch property}}
        }
    }
    method guard {} {
        if {$closing || $session ne [::GX::interactiveDocumentSessionToken]} {error {Sketch Session lifetime is stale}}
        if {$surface ne {}} {$surface guard}
        set owner [::GX::interactiveDocumentMetadata $document]
        if {[dict get $owner generation] ne $generation || [dict get $owner revision]!=$revision} {error {Sketch Document scope changed; reopen it}}
        # Metadata guards ownership without re-reading/hashing all exact
        # geometry through the unrelated 3D scientific worker on pointer input.
        return 1
    }
    method historyGuard {} {my guard;return 1}
    method state {} {
        my guard
        return [dict create api_id NATIVE2D_API_v1 component cad_sketch widget $w document_id $document revision $revision generation $generation session_token $session \
            working_unit [dict get $model working_unit] plane [dict get $model plane] object_map $objects relationship_map $relations \
            host [$host state] advanced [[$host advanced] state] history_context $history history [::GX::scientificHistoryViewerStatus $history] \
            presentation [dict get $opts presentation] viewport $viewport status $status renderer_error $rendererError display_policy resident_native_depth_overlay_handles]
    }
    method logical {native mapping prefix} {
        dict for {id value} $mapping {if {$native==$value} {return $id}}
        return ${prefix}[incr counter]
    }
    method capture {} {
        set next [dict create format gxtxt.native_cad_sketch.v1 working_unit [dict get $model working_unit] plane [dict get $model plane]]
        set map {};set excluded [$host feedbackObjects]
        foreach native [::GX::Native2D::core ids $scene] {
            if {$native in $excluded} continue
            set id [my logical $native $objects s];dict set map $id $native
            set entry [dict create definition [::GX::Native2D::core sketch_definition $scene $native] style [::GX::Native2D::core object_style $scene $native] \
                direction [::GX::Native2D::core direction_marker $scene $native] role [::GX::Native2D::core identity_geometry_role $scene $native] \
                name [::GX::Native2D::core identity_name $scene $native] attributes [::GX::Native2D::core identity_attributes $scene $native]]
            # Selection is presentation state and never creates a scientific step.
            dict set entry style selected 0
            dict set next object/$id $entry
        }
        set objects $map;set map {}
        foreach rule [::GX::Native2D::core constraint_list $scene] {
            set native [dict get $rule id];set id [my logical $native $relations r];dict set map $id $native
            set rule [dict remove $rule id valid geometry_supported measured_value residual angular_residual enforcement general_solver]
            foreach field {a b axis} {
                if {[dict get $rule $field]==0} continue
                set found 0
                dict for {logical value} $objects {if {$value==[dict get $rule $field]} {dict set rule $field $logical;set found 1;break}}
                if {!$found} {error {Relationship references geometry outside this Sketch}}
            }
            dict set next relationship/$id $rule
        }
        set relations $map;set model $next
        return $next
    }
    method hydrate {staged snapshot} {
        set nextObjects {};set nextRelations {}
        try {
            dict for {key entry} $snapshot {
                if {![string match object/* $key]} continue
                set native [::GX::Native2D::core sketch_create $staged [dict get $entry definition] 257]
                set id [string range $key 7 end];dict set nextObjects $id $native
                ::GX::Native2D::core object_style $staged $native [dict get $entry style]
                ::GX::Native2D::core direction_marker $staged $native [dict get $entry direction]
                dict for {name value} [dict get $entry attributes] {::GX::Native2D::core identity_attribute $staged $native $name $value}
                # Role/name getters have implicit defaults. Writing those
                # defaults would invent identity attributes on first reopen.
                if {[::GX::Native2D::core identity_geometry_role $staged $native] ne [dict get $entry role] || [::GX::Native2D::core identity_name $staged $native] ne [dict get $entry name]} {error {Sketch identity fields disagree with their exact retained attributes}}
            }
            dict for {key rule} $snapshot {
                if {![string match relationship/* $key]} continue
                foreach field {a b axis} {if {[dict get $rule $field] ne {0}} {dict set rule $field [dict get $nextObjects [dict get $rule $field]]}}
                set receipt [::GX::Native2D::core constraint_create $staged $rule]
                dict set nextRelations [string range $key 13 end] [dict get $receipt id]
            }
            return [list $nextObjects $nextRelations]
        } on error {message options} {
            foreach native [dict values $nextObjects] {catch {::GX::Native2D::core delete $staged $native}}
            return -options $options $message
        }
    }
    method restore {snapshot} {
        ::GX::NativeCadSketch::validate $snapshot
        set staged [::GX::Native2D::core scene]
        try {my hydrate $staged $snapshot} finally {::GX::Native2D::core destroy $staged}
        # Preserve the native scene's monotonic ID allocation. Replacing it
        # would allow an old raw object/epoch reference to alias a restored ID.
        # Append/validate all new owners before removing any current science.
        [$host advanced] dispose
        $host cancel restore
        set prior [::GX::Native2D::core ids $scene]
        lassign [my hydrate $scene $snapshot] nextObjects nextRelations
        $host select {}
        foreach native $prior {::GX::Native2D::core delete $scene $native}
        set objects $nextObjects;set relations $nextRelations;set model $snapshot
        my scientificChanged {Sketch restored}
    }
    method project {record} {
        my guard
        set result [::GX::native3DGeometryCheckpoint $scene3d [dict create model [my capture] allocation_counter $counter scientific_history $record]]
        set revision [dict get $result revision]
        set savedHistoryRevision [dict get [::GX::scientificHistoryViewerStatus $history] revision]
        return $result
    }
    method begin {} {
        my guard
        ::GX::interactiveDocumentReadCached $document
        if {![::GX::scientificHistoryViewerPrepareEdit $history]} {error {Sketch History edit cancelled}}
        set before [my capture]
        if {$resident ne {}} {$resident show 0}
        return sketch-edit
    }
    method committed {operation} {
        my guard;::GX::interactiveDocumentReadCached $document
        foreach native [::GX::Native2D::core ids $scene] {
            if {$native in [dict values $objects] || $native in [$host feedbackObjects]} continue
            set style [::GX::Native2D::core object_style $scene $native]
            if {[dict get $style color] eq {1.0 1.0 1.0 1.0}} {::GX::Native2D::core object_style $scene $native {color {0.1 0.45 0.75 1} line_width 2}}
        }
        set after [my capture];set patch {}
        dict for {key value} $after {if {![dict exists $before $key] || [dict get $before $key] ne $value} {dict set patch $key $value}}
        foreach key [dict keys $before] {if {![dict exists $after $key]} {dict set patch $key @gxtxt.recipe.delete}}
        if {$patch eq {}} {set before {};if {$resident ne {}} {$resident show 1};return {changed 0}}
        set semantic [dict create api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 operation $operation parameters {} targets {} result_ids {} working_unit [dict get $model working_unit]]
        set receipt [::GX::scientificHistoryViewerSubmitPatch $history $patch $operation $semantic]
        set before {};my scientificChanged $operation
        return $receipt
    }
    method callback {kind event} {
        switch -- $kind {
            guard - admit {return [my guard]}
            begin {return [my begin]}
            committed {return [my committed [dict get $event operation]]}
            cancelled {set before {};if {$resident ne {}} {$resident show 1};my changed Cancelled}
            rollback {if {$before ne {}} {my restore $before};set before {};return}
            advanced {
                switch -- [dict get $event phase] {
                    admit {return [my guard]}
                    begin {return [my begin]}
                    committed {return [my committed [dict get $event operation]]}
                    rollback {if {$before ne {}} {my restore $before};set before {}}
                    rejected - cancelled {set before {};if {$resident ne {}} {$resident show 1};my changed Cancelled}
                }
            }
            selected {my changed {Selection changed}}
            error {my changed [dict get $event error]}
            presentation {my changed $status;return [dict create plans [::GX::native2DAxisPlans $scene]]}
            refresh {return {}}
            navigation {
                set operation [dict get $event operation]
                switch -- $operation {
                    fit {set bounds [dict get $event local_bounds];if {$bounds eq {}} {set bounds {0 0 1 1}};$surface fit $planeFrame $bounds}
                    pan {if {[dict exists $event dx]} {$surface navigation pan [dict get $event dx] [dict get $event dy]}}
                    zoom {$surface navigation zoom [expr {-[dict get $event delta]/120.0}] 0}
                }
            }
        }
        return {}
    }
    method scientificChanged {message} {
        incr geometryStamp
        if {$resident ne {} && [llength [info commands $resident]]} {
            if {[catch {
                $resident show 1
                $resident requestUpdate $model $scene3d [list live [self] $geometryStamp]
                if {$mapping ne {}} {$resident quality $mapping}
            } error]} {
                # A derived presentation failure must never roll back an edit
                # that the authoritative Native2D / P017 owners already accepted.
                set rendererError $error
                catch {$resident show 0}
                if {$projected ne {}} {$projected configure {resident_base 0}}
                append message " · native display unavailable; overlay retained: $error"
            } else {
                set rendererError {}
                if {$projected ne {}} {$projected configure {resident_base 1}}
            }
        }
        my changed $message
    }
    method changed {message} {
        set status $message
        set worldDirty 1;incr worldStamp
        if {$w ne {} && [winfo exists $w.status]} {$w.status configure -text $message}
        if {$timer eq {} && !$closing} {set timer [after idle [list [self] notify]]}
    }
    method notify {} {
        set timer {}
        if {$closing || $failedConstruction} return
        set callback {}
        if {[dict get $opts changed_command] ne {} && ![catch {my state} state]} {set callback [list {*}[dict get $opts changed_command] $state]}
        ::GX::native2DCadPresentationRefresh [self] $callback
    }
    method presentationIdentity {} {
        if {$closing || $session ne [::GX::interactiveDocumentSessionToken]} {error {Sketch display lifetime ended}}
        # An owned viewport validates its source during Bind, before the
        # constructor can acquire that viewport's surface. The exact Document
        # has already been checked; only this bounded construction phase may
        # omit the not-yet-created display lease.
        if {$surface ne {}} {$surface guard} elseif {!$failedConstruction} {error {Sketch display lease ended}}
        return [dict create document_id $document generation $generation revision $revision session_token $session]
    }
    method identity {} {my guard;return [dict create document_id $document generation $generation revision $revision session_token $session]}
    method projectionChanged {owner snapshot} {
        if {$closing || $host eq {}} return
        set id [dict get $snapshot frame_id]
        if {$mapping ne {} && $id eq $frameId} {$host refresh selection;return}
        if {$initialFit} {
            # A declared plane can be outside/behind the previous scene camera.
            # Fit through native authority before admitting any pointer mapping.
            set initialFit 0;my fitSurface;return
        }
        ::GX::native3DProjectionEnsure
        set next [::GX3DEProjection::create $snapshot $planeFrame]
        try {
            if {$projected eq {}} {set projected [::GX::native2DCadProjectionAttach $host $next [dict create chrome_raise_command [list $surface raiseChrome] resident_base 1 base_ready_command [list $resident ready] quality_valid_command [list $resident qualityValid]]]} else {$projected configure [dict create mapping $next]}
        } on error {message options} {$next dispose;return -options $options $message}
        if {$mapping ne {}} {$mapping dispose}
        set mapping $next;set frameId $id
        if {$resident ne {}} {$resident quality $mapping}
        $host refresh navigation
    }
    method fitSurface {} {
        set bounds {};foreach id [::GX::Native2D::core ids $scene] {set box [[$host context] object bounds $id];if {$bounds eq {}} {set bounds $box} else {lassign $bounds x0 y0 x1 y1;lassign $box a b d e;set bounds [list [expr {min($x0,$a)}] [expr {min($y0,$b)}] [expr {max($x1,$d)}] [expr {max($y1,$e)}]]}}
        if {[llength $bounds]!=4} {set bounds {0 0 1 1}}
        return [$surface fit $planeFrame $bounds]
    }
    method worldBase {} {
        set view [::GX::viewerSceneDefaults]
        dict set view projection orthographic;dict set view working_plane_visible 0
        return [dict create layers {} view $view caption {Sketch on the selected scientific plane} document_id $document generation $generation session_token $session revision $revision publication 0]
    }
    # Legacy explicit snapshot remains callable; normal frame updates use only
    # presentation_scene and never reconstruct a mirrored scientific scene.
    method presentation_scene {} {my guard;return [my worldBase]}
    method world_scene {} {
        my guard
        if {$worldCache eq {}} {set worldCache [my worldBase]}
        if {$worldBuilding || ([info exists ::GX::Engine3D::workerBusy] && $::GX::Engine3D::workerBusy)} {return [dict merge $worldCache {display_pending 1}]}
        if {$worldDirty} {
            set stamp $worldStamp;set worldBuilding 1
            try {set worldCache [my buildWorldScene];set worldDirty [expr {$stamp!=$worldStamp}]} finally {set worldBuilding 0}
        }
        return [dict merge $worldCache [dict create display_pending $worldDirty]]
    }
    method buildWorldScene {} {
        set base [my worldBase]
        dict set base view working_plane_visible 1
        foreach {key target} {origin working_plane_origin normal working_plane_normal u_axis working_plane_u_axis} {dict set base view $target [join [dict get $model plane $key] {;}]}
        return [dict merge $base [dict create layers [::GX::_nativeCadSketchDisplayLayers $scene $scene3d $model] display_policy bounded_visual_sampling]]
    }
    method transform {direction points} {
        my guard
        if {[llength $points]>65536} {error {Sketch transform batch exceeds65536 points}}
        if {$direction in {local_to_device device_to_local}} {
            set op [expr {$direction eq {local_to_device}?{device}:{world}}];set result {}
            foreach point $points {lappend result [$host $op $point]}
            return [dict create direction $direction points $result working_unit [dict get $model working_unit] owner Native2D]
        }
        if {$direction ni {to_world to_plane}} {error {Choose to_world, to_plane, local_to_device or device_to_local}}
        set source {}
        foreach point $points {
            if {$direction eq {to_world} && [llength $point]==2} {lappend point 0}
            if {[llength $point]!=3} {error {World frame mapping requires explicit XYZ; local XY is accepted only for to_world}}
            lappend source $point
        }
        set receipt [::GX::native3DGeometryCall $scene3d plane_frame [dict create plane [dict get $model plane] points $source direction $direction]]
        return [dict merge $receipt [dict create direction $direction working_unit [dict get $model working_unit] owner Native3D.plane_frame]]
    }
    method command {action} {return [my invoke $action]}
    method actions {} {return [::GX::native2DCadActions]}
    method actionState {action} {return [::GX::native2DCadActionState [self] $action]}
    method invoke {action} {
        my guard
        return [::GX::native2DCadActionInvoke [self] $action]
    }
    method menu {menu} {return [::GX::native2DCadMenu [self] $menu]}
    method palette {parent} {return [::GX::native2DCadPalette [self] $parent]}
    method canvasControls {{parent {}}} {if {$parent eq {}} {set parent $w};return [::GX::native2DCadCanvasControls [self] $parent]}
    method present {mode parent} {
        switch -- $mode {menu {return [my menu $parent]} palette {return [my palette $parent]} canvas {return [my canvasControls $parent]} default {error {Choose menu, palette or canvas}}}
    }
    method dirty {} {my guard;return [expr {[dict get [::GX::scientificHistoryViewerStatus $history] revision]!=$savedHistoryRevision}]}
    method pending {} {
        if {[$host pointerActive]} {return 1}
        set construction [dict get [[$host advanced] state] construction]
        return [expr {$construction ne {} && [llength [dict get $construction places]]>0}]
    }
    method save {} {
        my guard
        if {[my pending]} {error {Finish or Cancel the pending Sketch edit before saving}}
        set receipt [::GX::scientificHistoryViewerFlush $history]
        if {$resident ne {} && [catch {$resident saved} error]} {
            set rendererError $error
            catch {$resident show 0}
            if {$projected ne {}} {$projected configure {resident_base 0}}
            my changed "Saved · native display unavailable: $error"
        }
        return $receipt
    }
    method close {{displayUnit {}}} {
        my guard
        if {$displayUnit ne {}} {::GX::unitRegistryConversionPlan [dict get $model working_unit] $displayUnit}
        if {[my pending]} {
            set answer [tk_messageBox -parent [winfo toplevel [$surface canvas]] -icon question -type yesnocancel -title {Close Sketch} -message {Finish the pending construction before closing?} -detail {Yes: finish it. No: discard only the staged edit. Cancel: keep the Sketch open. Committed geometry is preserved.}]
            if {$answer eq {cancel}} {return [dict create status cancelled document_id $document]}
            if {$answer eq {yes}} {my invoke finish;if {[my pending]} {return [dict create status cancelled document_id $document]}} else {$host cancel explicit_close_discard}
        }
        my save
        set receipt [dict create status closed document_id $document]
        # Explicit lifecycle snapshot only. If preparation fails the editor
        # stays alive; accepted science and its History are never discarded.
        if {$displayUnit ne {}} {dict set receipt display_snapshot [::GX::nativeCadSketchDocumentPresentation $document $displayUnit]}
        my destroy;return $receipt
    }
    method destroyed {actual} {if {$actual eq $w && !$closing} {my destroy}}
}
source [file join [file dirname [info script]] native2d_cad_presentation_v1.tcl]

source [file join [file dirname [info script]] native_cad_sketch_display_v1.tcl]
if {![llength [info commands ::GX::nativeCadSketchQuickOpenPublish]]} {source [file join [file dirname [info script]] native_cad_sketch_quick_open_exp01.tcl]}
source [file join [file dirname [info script]] native_cad_sketch_scene_exp01.tcl]
