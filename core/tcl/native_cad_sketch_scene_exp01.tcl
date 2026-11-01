# SPDX-License-Identifier: GPL-3.0-or-later
# Additive NATIVE2D_API_v1 / Native3D GUI Host display bindings. No second
# scientific scene, solver, selection authority, History or Document registry.
namespace eval ::GX::NativeCadSketchScene {variable bindings {};variable leases {};variable serial 0}
proc ::GX::NativeCadSketchScene::leaseAcquire {borrowed} {
    variable leases
    set canvas [$borrowed canvas]
    if {[dict exists $leases $canvas] && ![catch {[dict get $leases $canvas surface] guard}]} {
        set entry [dict get $leases $canvas];dict incr entry users;dict set leases $canvas $entry
        return [dict get $entry surface]
    }
    if {[dict exists $leases $canvas]} {catch {[dict get $leases $canvas surface] dispose};dict unset leases $canvas}
    set info [$borrowed info]
    if {[dict get $info owner_kind] eq {legacy}} {set surface [::GX::native3DGuiHostSurface]} else {set surface [::GX::native3DViewportSurface [dict get $info owner]]}
    dict set leases $canvas [dict create surface $surface users 1]
    return $surface
}
proc ::GX::NativeCadSketchScene::leaseRelease {canvas surface} {
    variable leases
    if {![dict exists $leases $canvas] || [dict get $leases $canvas surface] ne $surface} {catch {$surface dispose};return}
    set entry [dict get $leases $canvas];dict incr entry users -1
    if {[dict get $entry users]>0} {dict set leases $canvas $entry} else {dict unset leases $canvas;$surface dispose}
}
proc ::GX::nativeCadSketchSceneAttach {surface document {options {}}} {
    if {![native3DSurfaceIsManaged $surface]} {error {Sketch scene binding requires a public Native3D surface}}
    set key [list [$surface canvas] $document]
    if {[dict exists $::GX::NativeCadSketchScene::bindings $key]} {
        set binding [dict get $::GX::NativeCadSketchScene::bindings $key]
        if {[llength [info commands $binding]] && ![catch {$binding guard}]} {
            set info [$binding info];set current [interactiveDocumentMetadata $document]
            if {[dict get $info source generation] eq [dict get $current generation]} {
                if {[dict get $info source revision] ne [dict get $current revision] || [dict get $info source sha256] ne [dict get $current sha256]} {
                    if {[dict get $info editing] || [dict get $info pending]} {error {Live Sketch source changed; close and reopen its scientific editor}}
                    $binding saved
                }
                $binding configure $options;return $binding
            }
            $binding detach
        }
        if {[llength [info commands $binding]]} {$binding destroy}
    }
    return [::GX::NativeCadSketchScene::Binding new $surface $document $options]
}
proc ::GX::nativeCadSketchSceneResolvePick {surface pick} {
    if {![dict get $pick hit]} {return {}}
    dict for {key binding} $::GX::NativeCadSketchScene::bindings {
        if {[lindex $key 0] ne [$surface canvas] || ![llength [info commands $binding]]} continue
        set result [$binding resolve $pick]
        if {$result ne {}} {return $result}
    }
    return {}
}
oo::class create ::GX::NativeCadSketchScene::Binding {
    variable surface canvas document session scope resource snapshot options watch tag hidden liveRevision density qualityLimited pendingModel updateTimer desiredRevision updateError qualityMapping editMode overlayRequired geometryRevision
    constructor {borrowed id changes} {
        set document $id;set session [::GX::interactiveDocumentSessionToken];set watch {};set tag {};set hidden 0;set liveRevision {}
        set density 0;set qualityLimited 0
        set pendingModel {};set updateTimer {};set desiredRevision {};set updateError {}
        set qualityMapping {}
        set editMode 0;set overlayRequired 1
        set geometryRevision {}
        set options {working_unit {} edit_command {}};my configure $changes
        # A display binding owns only its GUI lease, independently of the
        # transient editor's input lease. Closing edit mode keeps native curves.
        set surface [::GX::NativeCadSketchScene::leaseAcquire $borrowed]
        set canvas [$surface canvas]
        set scope [::GX::interactiveDocumentMetadata $id]
        set resource ${id}_[string range [::GX::_nativeCadQuickDigest [list $session $id [dict get $scope generation]]] 0 23]
        set snapshot [::GX::nativeCadSketchQuickOpenPresentation $id [dict get $options working_unit]]
        if {[dict exists $snapshot descriptor pixels_per_unit]} {set density [dict get $snapshot descriptor pixels_per_unit]}
        if {[dict exists $snapshot descriptor editing_overlay_required]} {set overlayRequired [dict get $snapshot descriptor editing_overlay_required]}
        set tag GXSketchResident[incr ::GX::NativeCadSketchScene::serial]
        bindtags $canvas [linsert [bindtags $canvas] 0 $tag]
        bind $tag <Destroy> [list ::GX::Native3DSurface::ownerDestroyEvent [self] %W]
        set watch [::GX::interactiveDocumentLifecycleSubscribe [list [self] lifecycle] $canvas $id 1]
        dict set ::GX::NativeCadSketchScene::bindings [list $canvas $id] [self]
        set geometryRevision [::GX::_nativeCadQuickDigest [dict get $snapshot layers]]
        my submit $geometryRevision [dict get $snapshot layers]
    }
    destructor {
        if {$updateTimer ne {}} {after cancel $updateTimer}
        if {$watch ne {}} {::GX::interactiveDocumentLifecycleUnsubscribe $watch}
        if {[info exists canvas]} {
            if {[winfo exists $canvas]} {bindtags $canvas [lsearch -all -inline -not -exact [bindtags $canvas] $tag]}
            set key [list $canvas $document]
            if {[dict exists $::GX::NativeCadSketchScene::bindings $key] && [dict get $::GX::NativeCadSketchScene::bindings $key] eq [self]} {dict unset ::GX::NativeCadSketchScene::bindings $key}
        }
        if {$tag ne {}} {bind $tag <Destroy> {}}
        if {[info exists surface] && [llength [info commands $surface]]} {::GX::NativeCadSketchScene::leaseRelease $canvas $surface}
    }
    method configure {changes} {
        foreach key [dict keys $changes] {if {$key ni {working_unit edit_command}} {error {Unknown Sketch scene option}}}
        if {[dict exists $changes edit_command]} {llength [dict get $changes edit_command]}
        set oldUnit [dict get $options working_unit]
        set options [dict merge $options $changes]
        if {[info exists snapshot] && $oldUnit ne [dict get $options working_unit]} {my saved}
    }
    method guard {} {
        if {$session ne [::GX::interactiveDocumentSessionToken]} {error {Sketch scene Session expired}}
        $surface guard
        return 1
    }
    method info {} {my guard;return [dict create api_id NATIVE2D_API_v1 component resident_sketch resource $resource document_id $document source $scope session_token $session hidden $hidden editing $editMode live_revision $liveRevision geometry_revision $geometryRevision pending [expr {$pendingModel ne {} || $updateTimer ne {}}] update_error $updateError display_depth native_scene_occlusion exact_authority Native2D.C preview_authority 0 surface $surface]}
    method ready {} {
        if {[catch {my guard}] || $hidden || $qualityLimited || $pendingModel ne {} || $updateTimer ne {} || $updateError ne {}} {return 0}
        set info [$surface resourcesInfo]
        set revision $geometryRevision
        return [expr {[dict get $info error] eq {} && ![dict get $info pending] && [dict exists $info receipt resource_states $resource] && [dict get $info receipt resource_states $resource revision] eq $revision && [dict get $info receipt resource_states $resource visible]}]
    }
    method submit {revision layers} {
        return [$surface resources [dict create $resource [dict create revision $revision visible [expr {!$hidden && !$qualityLimited && $updateError eq {}}] layers $layers]]]
    }
    method qualityValid {} {return [expr {!$qualityLimited}]}
    method qualityLimit {resolution} {
        if {!$editMode} {return 0}
        if {$overlayRequired} {return 1}
        set limit [expr {$resolution<=0}]
        if {$resolution>0 && $qualityMapping ne {} && [llength [info commands $qualityMapping]]} {
            set scale [$qualityMapping scale]
            if {[dict get $scale valid] && [dict get $scale maximum_pixels_per_unit]>$resolution} {set limit 1}
        }
        return $limit
    }
    method editing {enabled} {
        my guard
        if {![string is boolean -strict $enabled]} {error {Sketch edit presentation must be boolean}}
        set editMode $enabled
        set qualityLimited [my qualityLimit $density]
        return [my show [expr {!$hidden}]]
    }
    method quality {mapping} {
        my guard;set qualityMapping $mapping
        set limit [my qualityLimit $density]
        if {$limit!=$qualityLimited} {set qualityLimited $limit;my show [expr {!$hidden}]}
        return [my qualityValid]
    }
    method show {{visible 1}} {
        my guard
        if {![string is boolean -strict $visible]} {error {Sketch visibility must be boolean}}
        set hidden [expr {!$visible}]
        return [$surface resources [dict create $resource [dict create revision $geometryRevision visible [expr {$visible && !$qualityLimited && $updateError eq {} && ($desiredRevision eq {} || $desiredRevision eq $liveRevision)}] layers [dict get $snapshot layers]]]]
    }
    method requestUpdate {model authority stamp} {
        my guard
        set desiredRevision $stamp;set updateError {}
        set pendingModel [dict create model $model authority $authority stamp $stamp]
        my show [expr {!$hidden}]
        if {$updateTimer eq {}} {set updateTimer [after idle [list [self] synchronize]]}
        return [dict create queued 1 revision $stamp]
    }
    method synchronize {} {
        set updateTimer {}
        if {[catch {my guard} error]} {set pendingModel {};set updateError $error;return}
        if {[$surface busy] || $::GX::Engine3D::workerBusy} {set updateTimer [after 16 [list [self] synchronize]];return}
        set pending $pendingModel;set pendingModel {}
        if {$pending eq {}} return
        if {[catch {my update [dict get $pending model] [dict get $pending authority] [dict get $pending stamp]} error]} {
            set updateError $error
            catch {$surface resourcesRetire [list $resource]}
        }
        if {$pendingModel ne {} && $updateTimer eq {}} {set updateTimer [after idle [list [self] synchronize]]}
    }
    method update {model authority stamp} {
        my guard
        set metadata [::GX::interactiveDocumentMetadata $document]
        if {[dict get $metadata generation] ne [dict get $scope generation]} {error {Sketch owner replaced}}
        if {$stamp eq $liveRevision} {return [dict create reused 1]}
        set geometry [::GX::_nativeCadSketchQuickGeometry $model $authority [dict get $options working_unit]]
        if {$desiredRevision ne {} && $stamp ne $desiredRevision} {return [dict create superseded 1]}
        set nextDensity [dict get $geometry pixels_per_unit]
        set overlayRequired [dict get $geometry editing_overlay_required]
        set qualityLimited [my qualityLimit $nextDensity]
        set shape [::GX::_nativeCadQuickDigest [dict get $geometry layers]]
        set receipt [my submit $shape [dict get $geometry layers]]
        set geometryRevision $shape
        set density $nextDensity;set liveRevision $stamp
        dict set snapshot layers [dict get $geometry layers];set scope $metadata
        return $receipt
    }
    method saved {} {
        my guard
        if {$updateTimer ne {}} {after cancel $updateTimer;set updateTimer {}}
        set pendingModel {};set desiredRevision {};set updateError {};set liveRevision {};set qualityLimited 0
        set snapshot [::GX::nativeCadSketchQuickOpenPresentation $document [dict get $options working_unit]]
        set density [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $snapshot descriptor {}] pixels_per_unit 0]
        set overlayRequired [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $snapshot descriptor {}] editing_overlay_required 1]
        set qualityLimited [my qualityLimit $density]
        set scope [::GX::interactiveDocumentMetadata $document]
        set geometryRevision [::GX::_nativeCadQuickDigest [dict get $snapshot layers]]
        return [my submit $geometryRevision [dict get $snapshot layers]]
    }
    method resolve {pick} {
        my guard
        set prefix sketch-resource/$resource/
        if {![dict get $pick hit] || [string first $prefix [dict get $pick layer_id]]!=0} {return {}}
        set current [::GX::interactiveDocumentMetadata $document]
        if {[dict get $scope generation] ne [dict get $current generation] || [dict get $scope revision] ne [dict get $current revision]} {error {Picked Sketch preview is stale; refresh it before editing}}
        # Selection is not a camera operation. Recheck the saved file boundary
        # before admitting a previously resident preview as an edit target.
        ::GX::interactiveDocumentReadCached $document
        return [dict create document_id $document generation [dict get $scope generation] revision [dict get $scope revision] sha256 [dict get $scope sha256] display_part [string range [dict get $pick layer_id] [string length $prefix] end] exact_subelement 0 binding [self]]
    }
    method edit {} {
        my guard
        # Entering edit always has a checked exact load, never a preview model.
        set saved [::GX::interactiveDocumentReadCached $document]
        if {[dict get $saved generation] ne [dict get $scope generation] || [dict get $saved revision] ne [dict get $scope revision]} {error {Sketch source changed before edit admission}}
        if {[dict get $options edit_command] eq {}} {error {The consuming Viewer has not supplied an edit-mode callback}}
        return [uplevel #0 [list {*}[dict get $options edit_command] [dict create document_id $document generation [dict get $scope generation] revision [dict get $scope revision]]]]
    }
    method lifecycle {event} {
        if {[dict get $event document_id] ne $document || [dict get $event session_token] ne $session} return
        if {[dict get $event event] eq {updated}} {
            if {[dict get $event revision] eq [dict get $scope revision]} return
            if {$editMode} {
                if {$updateTimer ne {}} {after cancel $updateTimer;set updateTimer {}}
                set pendingModel {};set updateError {Canonical Sketch changed outside this editor; close and reopen before editing}
                my show [expr {!$hidden}];return
            }
            # A live component owns its accepted unsaved proposal. Canonical
            # save is followed explicitly by saved(); no asynchronous overwrite.
            if {$liveRevision eq {}} {my saved}
        } else {
            $surface resourcesRetire [list $resource]
            my destroy
        }
    }
    method ownerDestroyed {actual} {if {$actual eq $canvas} {my destroy}}
    method detach {} {$surface resourcesRetire [list $resource];my destroy}
}
