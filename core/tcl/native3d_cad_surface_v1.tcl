# SPDX-License-Identifier: GPL-3.0-or-later
# Borrow the established Native3D GUI owner. No scene or camera is duplicated.
namespace eval ::GX::Native3DSurface {variable serial 0;variable legacyUsers 0;variable legacyPending {};variable legacyFrame {};variable disableTimer {}}
# Tk snapshots bindtag scripts before dispatching Destroy. A prior handler may
# legitimately retire a shared display lease in that same event; admit only a
# still-live owner, without suppressing errors from an existing owner.
proc ::GX::Native3DSurface::ownerDestroyEvent {handle actual} {
    if {[info object isa object $handle]} {$handle ownerDestroyed $actual}
}
proc ::GX::native3DViewportSurface {handle} {return [::GX::Native3DSurface::Surface new component $handle]}
proc ::GX::native3DGuiHostSurface {} {return [::GX::Native3DSurface::Surface new legacy {}]}
proc ::GX::native3DSurfaceIsManaged {value} {return [expr {[info object isa object $value] && [info object isa typeof $value ::GX::Native3DSurface::Surface]}]}
proc ::GX::native3DProjectionEnsure {} {
    if {![llength [info commands ::GX3DEProjection::create]]} {load [file join $::GX::scriptDir core native3d bin gx3de_projection_tcl_v1.so] Gx3deprojection}
}
proc ::GX::Native3DSurface::legacyReply {result} {
    variable legacyUsers;variable legacyPending
    if {$legacyUsers && ![catch {dict get $result projection_snapshot} snapshot]} {set legacyPending $snapshot}
}
proc ::GX::Native3DSurface::legacyPresented {} {
    variable legacyUsers;variable legacyPending;variable legacyFrame
    if {!$legacyUsers || $legacyPending eq {}} return
    set legacyFrame $legacyPending
    set c $::GX::Engine3D::window.canvas
    if {[winfo exists $c]} {$c lower native_image;event generate $c <<GXNative3DFrame>>}
}
proc ::GX::Native3DSurface::disableLegacy {generation} {
    variable legacyUsers;variable disableTimer
    set disableTimer {}
    if {$legacyUsers || $generation!=$::GX::Engine3D::workerGeneration || $::GX::Engine3D::worker eq {}} return
    if {$::GX::Engine3D::workerBusy} {set disableTimer [after 25 [list ::GX::Native3DSurface::disableLegacy $generation]];return}
    catch {::GX::Engine3D::rpc {projection disable}}
}
oo::class create ::GX::Native3DSurface::Surface {
    variable kind owner c stamp session host changed actions tag timer route space chrome photo closed claimed resourcePending resourceTimer resourceError resourceOwned resourceRetiring resourceBytes
    constructor {backend handle} {
        set kind $backend;set owner $handle;set c {};set stamp {};set tag {};set chrome {};set claimed 0;set host {};set changed {};set actions {};set timer {};set route {};set space 0;set photo {};set closed 0
        set session [::GX::interactiveDocumentSessionToken]
        set resourcePending {};set resourceTimer {};set resourceError {};set resourceOwned {};set resourceRetiring 0;set resourceBytes {}
        if {$kind eq {legacy}} {
            set c $::GX::Engine3D::window.canvas
            set stamp [list $::GX::Engine3D::mountGeneration $::GX::Engine3D::workerGeneration $::GX::Engine3D::scientificPresentationGeneration]
        } else {
            set r [::GX::_native3DViewportRecord $owner];set c [dict get $r widget].canvas
            set stamp [dict get $r generation]
        }
        if {![winfo exists $c] || [winfo class $c] ne {Canvas}} {error {Native3D surface has no current Canvas}}
        if {$kind eq {legacy}} {
            incr ::GX::Native3DSurface::legacyUsers
            if {$::GX::Native3DSurface::disableTimer ne {}} {after cancel $::GX::Native3DSurface::disableTimer;set ::GX::Native3DSurface::disableTimer {}}
        } else {dict set ::GX::Native3DCanvas::instances $owner projection_users [expr {1+[::GX::datasetPublicationV2DictDefault $r projection_users 0]}]}
        set claimed 1
        set chrome cad_native_chrome[incr ::GX::Native3DSurface::serial];set tag GXNative3DCad$::GX::Native3DSurface::serial
        bindtags $c [linsert [bindtags $c] 0 $tag]
        bind $tag <<GXNative3DFrame>> [list [self] frameChanged]
        bind $tag <Destroy> [list ::GX::Native3DSurface::ownerDestroyEvent [self] %W]
        foreach {sequence phase} {<ButtonPress-1> down <ButtonRelease-1> up <B1-Motion> move <Motion> move} {
            bind $tag $sequence [format {if {[%s %s %%x %%y %%s]} {break}} [list [self] pointer] $phase]
        }
        foreach {sequence delta} {<Button-4> -1 <Button-5> 1} {bind $tag $sequence [format {if {[%s zoom %s]} {break}} [list [self] navigation] $delta]}
        bind $tag <MouseWheel> [format {if {[%s zoom [expr {-%%D/120.0}]]} {break}} [list [self] navigation]]
        foreach key {Escape Return} {bind $tag <$key> [format {if {[%s %s]} {break}} [list [self] key] $key]}
        foreach {sequence key} {<Control-z> undo <Control-y> redo <Control-s> save} {bind $tag $sequence [format {if {[%s %s]} {break}} [list [self] key] $key]}
        bind $tag <KeyPress-space> [list [self] space 1];bind $tag <KeyRelease-space> [list [self] space 0]
        my enable
    }
    destructor {
        set closed 1
        if {$resourceTimer ne {}} {after cancel $resourceTimer}
        if {$timer ne {}} {after cancel $timer}
        if {[winfo exists $c]} {
            bindtags $c [lsearch -all -inline -not -exact [bindtags $c] $tag]
            $c delete $chrome
        }
        if {$tag ne {}} {foreach sequence [bind $tag] {bind $tag $sequence {}}}
        if {$photo ne {}} {catch {image delete $photo}}
        if {!$claimed} return
        if {$kind eq {legacy}} {
            incr ::GX::Native3DSurface::legacyUsers -1
            if {!$::GX::Native3DSurface::legacyUsers} {::GX::Native3DSurface::disableLegacy [lindex $stamp 1]}
        } elseif {[dict exists $::GX::Native3DCanvas::instances $owner]} {
            set r [::GX::_native3DViewportRecord $owner]
            dict set ::GX::Native3DCanvas::instances $owner projection_users [expr {max(0,[::GX::datasetPublicationV2DictDefault $r projection_users 1]-1)}]
            if {![dict get $::GX::Native3DCanvas::instances $owner projection_users]} {catch {::GX::_native3DViewportQueue $owner projection {projection disable}}}
        }
    }
    method canvas {} {return $c}
    method resourceOwnerAlive {} {
        if {$closed || ![winfo exists $c]} {return 0}
        if {$kind eq {legacy}} {return [expr {[lindex $stamp 0]==$::GX::Engine3D::mountGeneration && [lindex $stamp 1]==$::GX::Engine3D::workerGeneration}]}
        return [expr {[dict exists $::GX::Native3DCanvas::instances $owner] && [dict get $::GX::Native3DCanvas::instances $owner generation]==$stamp}]
    }
    method resources {changes} {
        my guard
        if {[dict size $changes]>512} {error {Sketch display batch exceeds512 resources}}
        set next [dict merge $resourcePending $changes]
        if {[dict size $next]>512} {error {Pending Sketch display budget exceeds512 resources}}
        set allocation $resourceBytes
        dict for {key value} $changes {
            if {$value eq {remove}} {dict unset allocation $key} elseif {[dict exists $value layers]} {
                set bytes [string bytelength [dict get $value layers]]
                if {$bytes>33554432} {error {Sketch display descriptor exceeds32 MiB}}
                dict set allocation $key $bytes
            }
        }
        set total 0;foreach bytes [dict values $allocation] {incr total $bytes}
        if {$total>67108864} {error {Viewport Sketch display descriptors exceed64 MiB; detach unused saved displays}}
        dict for {key value} $changes {dict set resourceOwned $key 1}
        set resourceBytes $allocation
        set resourcePending $next
        if {$resourceTimer eq {}} {set resourceTimer [after idle [list [self] resourcesFlush]]}
        return [dict create queued [dict size $resourcePending] camera_unchanged 1]
    }
    method resourcesRetire {keys} {
        if {![my resourceOwnerAlive]} {return}
        foreach key $keys {
            if {![dict exists $resourceOwned $key]} {error {Cannot retire another surface's display resource}}
            dict set resourcePending $key remove
        }
        # Removal is safe after Session expiry: only opaque display keys this
        # GUI lease previously admitted can be retired; no science is accessed.
        if {$resourceTimer eq {}} {set resourceTimer [after idle [list [self] resourcesFlush]]}
    }
    method resourcesInfo {} {
        my guard
        set receipt {}
        if {$kind eq {legacy}} {if {[info exists ::GX::Native3DSurface::legacyResourceReceipt]} {set receipt $::GX::Native3DSurface::legacyResourceReceipt}} else {set receipt [::GX::datasetPublicationV2DictDefault [::GX::_native3DViewportRecord $owner] sketch_resource_receipt {}]}
        set bytes 0;foreach n [dict values $resourceBytes] {incr bytes $n}
        return [dict create pending [dict size $resourcePending] error $resourceError descriptor_bytes $bytes descriptor_budget 67108864 receipt $receipt]
    }
    method resourcesFlush {} {
        set resourceTimer {}
        set onlyRemove [expr {$resourcePending ne {}}]
        dict for {key value} $resourcePending {if {$value ne {remove}} {set onlyRemove 0;break}}
        if {![my resourceOwnerAlive] || (!$onlyRemove && [catch {my guard}])} {set resourcePending {};if {$resourceRetiring} {my destroy};return}
        if {$kind eq {legacy}} {
            set frame $::GX::Native3DSurface::legacyFrame
            set busy [expr {$::GX::Engine3D::workerBusy || [llength $::GX::Engine3D::cameraQueue]}]
        } else {
            set record [::GX::_native3DViewportRecord $owner]
            if {[dict get $record status] in {error stale_source}} {set resourceError {Native3D resource owner is unavailable; explicitly rebind};set resourcePending {};if {$resourceRetiring} {my destroy};return}
            set frame [::GX::datasetPublicationV2DictDefault $record projection_snapshot {}]
            set busy [expr {[dict get $record busy] ne {} || [llength [dict get $record queue]] || ![dict get $record ready]}]
        }
        if {$frame eq {} || $busy} {set resourceTimer [after 16 [list [self] resourcesFlush]];return}
        set changes $resourcePending;set resourcePending {}
        if {$changes eq {}} return
        if {[catch {
            if {$kind eq {legacy}} {
                set result [::GX::Engine3D::gizmoImageRequest [list sketch_resources sync $changes]]
                set ::GX::Native3DSurface::legacyResourceReceipt $result
            } else {
                set record [::GX::_native3DViewportRecord $owner]
                ::GX::_native3DViewportQueue $owner sketch_resources [list sketch_resources sync $changes [file join [dict get $record directory] frame.png]]
            }
        } error]} {
            set resourceError $error
            if {$kind eq {legacy}} {set ::GX::Engine3D::status "Sketch display failed; scientific geometry is retained: $error"}
            if {$resourceRetiring} {my destroy}
            return
        }
        set resourceError {}
        dict for {key value} $changes {if {$value eq {remove}} {dict unset resourceOwned $key;dict unset resourceBytes $key}}
        if {$resourceRetiring} {my destroy}
    }
    method ownerDestroyed {actual} {if {$actual eq $c} {my destroy}}
    method guard {} {
        if {$closed || ![winfo exists $c] || $session ne [::GX::interactiveDocumentSessionToken]} {error {Native3D surface lifetime ended}}
        if {$kind eq {legacy}} {
            if {$stamp ne [list $::GX::Engine3D::mountGeneration $::GX::Engine3D::workerGeneration $::GX::Engine3D::scientificPresentationGeneration]} {error {Native3D scientific source was replaced}}
        } else {if {[dict get [::GX::_native3DViewportRecord $owner] generation] ne $stamp} {error {Native3D component source was replaced}}}
        return 1
    }
    method busy {} {
        my guard
        if {$kind eq {legacy}} {return [expr {$::GX::Engine3D::workerBusy || [llength $::GX::Engine3D::cameraQueue]}]}
        set r [::GX::_native3DViewportRecord $owner]
        return [expr {[dict get $r busy] ne {} || [llength [dict get $r queue]] || ![dict get $r ready]}]
    }
    method frame {} {
        my guard
        if {$kind eq {legacy}} {return $::GX::Native3DSurface::legacyFrame}
        return [::GX::datasetPublicationV2DictDefault [::GX::_native3DViewportRecord $owner] projection_snapshot {}]
    }
    method info {} {return [dict create canvas $c owner_kind $kind owner $owner source_stamp $stamp frame [my frame] busy [my busy] scientific_owner borrowed]}
    method enable {} {
        set timer {}
        if {[catch {my guard}]} return
        if {$kind eq {legacy}} {
            if {$::GX::Engine3D::workerBusy} {set timer [after 25 [list [self] enable]];return}
            set result [::GX::Engine3D::rpc {projection enable 1}]
            if {[dict exists $result projection_snapshot]} {set ::GX::Native3DSurface::legacyFrame [dict get $result projection_snapshot]}
        } else {::GX::_native3DViewportQueue $owner projection {projection enable 1}}
        my frameChanged
    }
    method attach {cad callback {actionCallback {}}} {set host $cad;set changed $callback;set actions $actionCallback;my frameChanged;return [self]}
    method frameChanged {} {
        if {$closed || $changed eq {} || [catch {my frame} frame] || $frame eq {}} return
        if {$kind eq {legacy}} {set view [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]} else {set view [dict get [::GX::_native3DViewportRecord $owner] scene view]}
        if {[dict exists $view background_rgb]} {$c configure -background [dict get [::GX::uiFieldColorFromRGBA [concat [split [dict get $view background_rgb] {;}] 1]] rgb]}
        uplevel #0 [list {*}$changed [self] $frame]
        my raiseChrome
    }
    method cubeRect {} {
        set frame [my frame]
        if {$frame eq {} || ![dict exists $frame navigation_cube]} {return {}}
        set spec [dict get $frame navigation_cube]
        if {![dict get $spec visible]} {return {}}
        set width [dict get $frame width];set height [dict get $frame height]
        set margin [dict get $spec margin_pixels];set size [expr {min([dict get $spec size_pixels],$width-2*$margin,$height-2*$margin)}]
        if {$size<=0} {return {}}
        set corner [dict get $spec corner]
        set left [expr {$corner&1?$width-$margin-$size:$margin}];set top [expr {$corner&2?$height-$margin-$size:$margin}]
        return [list $left $top [expr {$left+$size}] [expr {$top+$size}]]
    }
    method inCube {x y} {set rect [my cubeRect];if {$rect eq {}} {return 0};lassign $rect l t r b;return [expr {$x>=$l && $x<$r && $y>=$t && $y<$b}]}
    method raiseChrome {} {
        if {[catch {my guard}] || [catch {my cubeRect} rect] || $rect eq {}} return
        if {$kind eq {legacy}} {set native $::GX::Engine3D::photo} else {set native [dict get [::GX::_native3DViewportRecord $owner] photo]}
        if {$native eq {}} return
        if {$photo eq {}} {set photo [image create photo]}
        lassign $rect l t r b
        $photo blank;$photo copy $native -from $l $t $r $b
        $c delete $chrome;$c create image $l $t -anchor nw -image $photo -tags $chrome
    }
    method space {value} {set space $value}
    method key {name} {
        if {$host eq {} || ![llength [info commands $host]]} {return 0}
        if {$route in {navigation camera_orbit camera_pan} && $name eq {Escape}} {set route {};return 0}
        if {$actions ne {}} {set action [dict get {Return finish Escape cancel undo undo redo redo save save} $name];uplevel #0 [list {*}$actions $action]} else {$host event key $name}
        return 1
    }
    method pointer {phase x y state} {
        if {$host eq {} || ![llength [info commands $host]] || [catch {my guard}]} {return 0}
        if {$phase eq {down}} {
            if {[my inCube $x $y]} {if {[$host pointerActive]} {$host cancel navigation};set route navigation;return 0}
            if {$space || ($state&8) || [$host tool] eq {pan}} {
                if {[$host pointerActive]} {$host cancel navigation}
                set mode [expr {($state&1) || [$host tool] eq {pan}?{pan}:{orbit}}]
                set route camera_$mode
                if {$kind eq {legacy}} {::GX::Engine3D::beginDrag $mode $x $y 1} else {::GX::_native3DViewportPress $owner $x $y}
                return 1
            }
            if {[my busy] || [my frame] eq {}} {set route blocked;return 1}
            set route cad;focus $c
        }
        if {$route in {camera_orbit camera_pan}} {
            if {$kind eq {legacy}} {
                if {$phase eq {move}} {::GX::Engine3D::cameraMotion $x $y}
                if {$phase eq {up}} {::GX::Engine3D::endDrag $x $y}
            } elseif {$phase eq {up}} {::GX::_native3DViewportDrag $owner [string range $route 7 end] $x $y}
            if {$phase eq {up}} {set route {}}
            return 1
        }
        if {$route in {navigation blocked}} {set consume [expr {$route eq {blocked}}];if {$phase eq {up}} {set route {}};return $consume}
        set projection [$host projection]
        if {$projection ne {} && ![dict get [$projection info] ready]} {
            # Horizon/edge-on views are a presentation state. Do not send an
            # unmappable hover/click into the CAD rejection path: that path
            # rightly cancels invalid scientific proposals, whereas an ordinary
            # camera view must preserve staged construction and exact geometry.
            # Navigation was admitted above and remains unrestricted.
            if {$phase eq {up}} {set route {}} elseif {$phase eq {down}} {set route blocked}
            return 1
        }
        if {$phase eq {move} && $route eq {cad} && !($state&256)} {
            # A reviewed modal admission can consume the initiating release.
            # Do not move a native preview under an unpressed physical pointer.
            set pending [dict get [$host state] gesture]
            if {$pending ne {} && [dict get $pending operation] ne {pan}} {
                $host cancel pointer_released_outside;set route {};return 1
            }
        }
        if {$phase eq {move} && ($space || ($state&8))} {return 0}
        if {$phase eq {move} && [my busy]} {return 1}
        set result [$host event $phase $x $y $state]
        if {$phase eq {up}} {set route {}}
        return [expr {$phase in {down up} || $result}]
    }
    method navigation {mode {x 0} {y 0}} {
        if {$host eq {} || [catch {my guard}]} {return 0}
        if {[$host pointerActive]} {$host cancel navigation}
        if {$kind eq {legacy}} {::GX::Engine3D::cameraNavigate $mode $x $y} else {::GX::native3DViewportNavigate $owner $mode $x $y}
        return 1
    }
    method fit {plane bounds} {
        my guard
        if {$kind eq {legacy}} {
            set result [::GX::Engine3D::gizmoImageRequest [list projection fit_plane $plane $bounds]]
            set fields {};foreach key {camera_position camera_target camera_up} {dict set fields $key [join [dict get $result $key] {;}]}
            ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $fields]
            foreach {key var} {camera_position cameraPosition camera_target cameraTarget camera_up cameraUp} {set ::GX::Engine3D::$var [dict get $fields $key]}
            return $result
        }
        set r [::GX::_native3DViewportRecord $owner]
        ::GX::_native3DViewportQueue $owner camera [list projection fit_plane $plane $bounds [file join [dict get $r directory] frame.png]]
    }
    method dispose {} {
        if {$resourcePending ne {} && [my resourceOwnerAlive]} {
            # The owning native queue must receive pending removals before the
            # last display lease disappears. No dead editor callbacks survive.
            set resourceRetiring 1;set host {};set changed {};set actions {}
            if {$resourceTimer eq {}} {set resourceTimer [after idle [list [self] resourcesFlush]]}
        } else {my destroy}
    }
}
