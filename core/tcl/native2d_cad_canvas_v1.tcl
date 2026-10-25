# SPDX-License-Identifier: GPL-3.0-or-later
# Embedded interaction owner in NATIVE2D_API_v1. Scientific state belongs to C;
# domains admit edits and record them through their existing Document/History.
namespace eval ::GX::Native2DCadCanvas {variable serial 0}
proc ::GX::native2DCadCanvasCreate {parent scene {options {}}} {
    if {![winfo exists $parent]} {error {CAD Canvas parent is unavailable}}
    set canvas $parent.cadCanvas[incr ::GX::Native2DCadCanvas::serial]
    canvas $canvas -width 640 -height 480 -background white -highlightthickness 0 -takefocus 1
    try {return [::GX::Native2DCadCanvas::Host new $canvas $scene $options 1]} on error {m o} {destroy $canvas;return -options $o $m}
}
proc ::GX::native2DCadCanvasAttach {canvas scene {options {}}} {
    if {[dict exists $::GX::ViewportHost::hosts $canvas cad_canvas]} {
        set h [dict get $::GX::ViewportHost::hosts $canvas cad_canvas]
        if {[llength [info commands $h]]} {$h associate $scene $options;return $h}
    }
    return [::GX::Native2DCadCanvas::Host new $canvas $scene $options 0]
}
oo::class create ::GX::Native2DCadCanvas::Host {
    variable c scene cad ownsCad ownsCanvas ownsViewport opts cb tool tools gesture polygon last scheduler tag dispatching generation preview advanced
    constructor {canvas source options created} {
        set c $canvas;set scene {};set cad {};set ownsCad 0;set ownsCanvas $created;set ownsViewport 0
        set tool select;set tools {select rectangle polygon translate rotate pivot mirror pan control points zoom fit};set gesture {};set polygon {};set last {};set scheduler {};set dispatching 0;set generation 0;set preview 0;set advanced {}
        set opts {bind_events 1 advanced_dispatch 1 external_render 0 selection_target local object_snap 0 tolerance_px 9}
        set cb {};set tag GXCadCanvas[incr ::GX::Native2DCadCanvas::serial]
        if {![winfo exists $c] || [winfo class $c] ne {Canvas}} {error {CAD host requires an existing Tk Canvas}}
        my associate $source $options
        bind $tag <Destroy> [list [self] ownerDestroyed %W]
        bindtags $c [linsert [bindtags $c] 0 $tag]
    }
    destructor {
        if {$advanced ne {} && [llength [info commands $advanced]]} {catch {$advanced dispose}}
        set advanced {}
        catch {my cancel dispose}
        if {$scheduler ne {}} {catch {::GX::guiUpdateSchedulerDispose $scheduler}}
        if {$cad ne {} && $ownsCad} {catch {::GX::native2DCadDispose $cad}}
        if {[winfo exists $c]} {bindtags $c [lsearch -all -inline -not -exact [bindtags $c] $tag]}
        foreach event [bind $tag] {bind $tag $event {}}
        if {[dict exists $::GX::ViewportHost::hosts $c cad_canvas] && [dict get $::GX::ViewportHost::hosts $c cad_canvas] eq [self]} {dict unset ::GX::ViewportHost::hosts $c cad_canvas}
        if {![dict get $opts external_render]} {catch {::GX::native2DSpriteSceneDispose $c};catch {::GX::native2DGridPresenterDispose $c}}
        if {$ownsViewport} {catch {::GX::native2DViewportDispose $c $c}}
        # The consumer owns scientific geometry and the selected widget's layout.
    }
    method canvas {} {return $c}
    method context {} {return $cad}
    method advanced {} {
        # Access/presentation is read-only, like context/state. Domain admission
        # belongs to each mutator's Require path: import/publication can redraw
        # while its owner intentionally forbids a new scientific edit.
        if {$cad eq {} || ![winfo exists $c] || ![llength [info commands $cad]] || ![dict get [$cad state] alive]} {error {CAD scientific source or widget has closed}}
        if {$advanced eq {} || ![llength [info commands $advanced]]} {set advanced [::GX::Native2DCadCanvas::Advanced new [self]]}
        return $advanced
    }
    method feedbackObjects {} {if {$preview} {return [list $preview]};return {}}
    method state {} {return [dict create api_id NATIVE2D_API_v1 canvas $c scene $scene context $cad attached [expr {$cad ne {} && [llength [info commands $cad]] && [dict get [$cad state] alive]}] generation $generation tool $tool enabled_tools $tools active [expr {$gesture ne {}}] target_flags_mutable [my targetsMutable] gesture $gesture polygon $polygon receipt $last]}
    method callback {key data {fallback {}}} {
        if {![dict exists $cb $key] || [dict get $cb $key] eq {}} {return $fallback}
        return [uplevel #0 [list {*}[dict get $cb $key] [dict merge [dict create host [self] canvas $c scene $scene generation $generation] $data]]]
    }
    method valid {} {
        if {$cad eq {} || ![winfo exists $c] || ![llength [info commands $cad]] || ![dict get [$cad state] alive]} {error {CAD scientific source or widget has closed}}
        if {![my callback guard [dict create phase guard] 1]} {error {CAD domain lifetime is stale or unavailable}}
    }
    method associate {source {options {}}} {
        if {$dispatching} {error {Cannot replace a CAD source from an interaction callback}}
        ::GX::native2DEnsure;::GX::Native2D::core view $source
        set incoming [::GX::datasetPublicationV2DictDefault $options context {}];dict unset options context
        set selection [::GX::datasetPublicationV2DictDefault $options selection __keep__];dict unset options selection
        set validated [my configuration $options]
        if {$incoming eq {} && $cad ne {} && [llength [info commands $cad]] && [dict get [$cad state] alive] && [dict get [$cad state] scene]==$source} {set incoming $cad}
        if {$incoming ne {} && (![llength [info commands $incoming]] || ![dict get [$incoming state] alive] || [dict get [$incoming state] scene]!=$source)} {error {CAD context belongs to another or closed scene}}
        my cancel source_change
        set ownNew 0
        if {$incoming eq {}} {set incoming [::GX::native2DCadCreate $source];set ownNew 1} elseif {$incoming eq $cad} {set ownNew $ownsCad}
        if {$cad ne {} && $ownsCad && $incoming ne $cad} {::GX::native2DCadDispose $cad}
        set scene $source;set cad $incoming;set ownsCad $ownNew;incr generation
        if {$selection ne {__keep__}} {$cad selection adopt $selection}
        lassign $validated opts cb
        if {![dict exists $::GX::ViewportHost::hosts $c]} {
            ::GX::native2DViewportHostCreate [winfo parent $c] $c $scene [list [self] refresh resize]
            set ownsViewport 1
        } else {::GX::native2DViewportHostScene $c $scene}
        dict set ::GX::ViewportHost::hosts $c cad_canvas [self]
        if {![dict get $opts external_render]} {::GX::native2DSpriteSceneAttach $c $scene}
        my bindings
        return [self]
    }
    method configuration {changes} {
        foreach key [dict keys $changes] {if {$key ni {bind_events advanced_dispatch external_render selection_target object_snap tolerance_px callbacks}} {error "Unknown CAD host option: $key"}}
        set nextCB $cb
        if {[dict exists $changes callbacks]} {
            set nextCB [dict get $changes callbacks]
            foreach key [dict keys $nextCB] {if {$key ni {guard scope targets admit begin selected preview committed cancelled rollback refresh navigation error presentation advanced}} {error "Unknown CAD callback: $key"};llength [dict get $nextCB $key]}
            dict unset changes callbacks
        }
        set next [dict merge $opts $changes]
        foreach key {bind_events advanced_dispatch external_render object_snap} {dict set next $key [::GX::uiFieldNormalize {type boolean} [dict get $next $key]]}
        if {[dict get $next selection_target] ni {detail local object}} {error {CAD selection target must be detail, local or object}}
        set tolerance [dict get $next tolerance_px];if {![string is double -strict $tolerance] || $tolerance<=0 || $tolerance>256} {error {CAD tolerance must be positive and bounded}}
        if {[dict get $next external_render] && (![dict exists $nextCB refresh] || [dict get $nextCB refresh] eq {})} {error {External CAD presentation requires its owner's refresh callback}}
        return [list $next $nextCB]
    }
    method configure {{changes {}}} {
        if {$gesture ne {}} {foreach key {callbacks bind_events advanced_dispatch external_render} {if {[dict exists $changes $key]} {error {Cancel before replacing CAD callbacks or GUI ownership}}}}
        set prior [dict get $opts bind_events]
        lassign [my configuration $changes] opts cb
        if {$prior!=[dict get $opts bind_events]} {my bindings}
        return $opts
    }
    method bindings {} {
        foreach event {<Button-1> <Motion> <B1-Motion> <ButtonRelease-1> <Escape> <Return> <MouseWheel> <Button-4> <Button-5> <Configure>} {bind $tag $event {}}
        if {![dict get $opts bind_events]} return
        foreach {event args} {<Button-1> {down %x %y %s} <Motion> {move %x %y %s} <B1-Motion> {move %x %y %s} <ButtonRelease-1> {up %x %y %s} <Escape> {key Escape} <Return> {key Return} <MouseWheel> {wheel %x %y %D} <Button-4> {wheel %x %y 120} <Button-5> {wheel %x %y -120} <Configure> {resize}} {
            set script "[list [self] bound] $args"
            if {$event eq {<Motion>}} {
                # New hover dispatch must not swallow a consumer's existing
                # coordinate/readout bindings when no CAD tool consumes it.
                set script [format {if {[%s]} {break}} $script]
            } elseif {$event ne {<Configure>}} {append script {;break}}
            bind $tag $event $script
        }
    }
    method ownerDestroyed {actual} {if {$actual eq $c} {my destroy}}
    method bound {args} {my event {*}$args}
    method tool {{value __query__}} {
        if {$value eq {__query__}} {return $tool}
        if {$value ni {select rectangle polygon translate rotate pivot mirror pan} || $value ni $tools} {error "CAD tool is disabled or unsupported: $value"}
        if {$value eq $tool} {
            # Explicitly choosing a basic tool also leaves a staged advanced
            # tool. A read-only query above never changes interaction state.
            if {$advanced ne {} && [llength [info commands $advanced]]} {my cancel tool_change}
            return $tool
        }
        my cancel tool_change;set tool $value
        if {$cad ne {} && [dict get [$cad state] alive]} {
            if {$value in {translate rotate pivot mirror}} {
                if {[catch {::GX::Native2D::core pivot $scene}]} {lassign [::GX::Native2D::core view $scene] w h l t r b;::GX::Native2D::core pivot $scene custom [::GX::Native2D::core world $scene [list [expr {($l+$w-$r)/2}] [expr {($t+$h-$b)/2}]]]}
                ::GX::Native2D::core gizmo $scene [dict create visible 1 mode [expr {$value eq {pivot}?{translate}:$value}]]
            } else {::GX::Native2D::core gizmo $scene {visible 0}}
        }
        return $tool
    }
    method tools {{enabled __query__}} {
        if {$enabled eq {__query__}} {return $tools}
        foreach value $enabled {if {$value ni {select rectangle polygon translate rotate pivot mirror pan control points zoom fit}} {error {Unsupported generic CAD tool}}}
        if {$gesture ne {}} {my cancel tools_changed}
        set tools [lsort -unique $enabled]
        return $tools
    }
    method scope {} {
        set ids [my callback scope [dict create phase scope] [::GX::Native2D::core ids $scene]]
        if {[llength $ids]>65536} {error {CAD scope exceeds65536 objects}}
        if {$preview} {set ids [lsearch -all -inline -not -exact $ids $preview]}
        return $ids
    }
    method pick {xy {target __default__}} {my valid;if {$target eq {__default__}} {set target [dict get $opts selection_target]};return [$cad selection pick [my scope] $xy [dict get $opts tolerance_px] $target]}
    method select {members {mode replace} {reference {}}} {
        my valid
        if {$gesture ne {}} {error {Finish or cancel the CAD operation before changing selection}}
        if {[llength $members]>65536} {error {CAD membership exceeds65536 entities}}
        $cad selection apply $members $mode
        set snapshot [$cad selection snapshot]
        my callback selected [dict create phase selected reference $reference selection $snapshot]
        set last [dict create status selected reference $reference selection $snapshot]
        return $last
    }
    method mode {state} {if {$state&1} {return subtract};if {$state&4} {return add};return replace}
    method targetsMutable {} {
        if {$cad eq {} || ![llength [info commands $cad]]} {return 0}
        set context [$cad state]
        if {![dict get $context alive]} {return 0}
        # Pan/control previews can own GUI interaction without a C drag. A
        # directly adopted C++ gesture also retains its own transaction scope.
        set advancedBusy [expr {$advanced ne {} && [llength [info commands $advanced]] && [$advanced busy]}]
        return [expr {!$advancedBusy && $gesture eq {} && ![dict get $context gesture] && ![::GX::Native2D::core drag_active $scene]}]
    }
    method activate {ids} {
        my valid
        if {![my targetsMutable]} {error {Finish the native drag before changing CAD target flags}}
        if {[llength $ids]>65536} {error {CAD targets exceed65536 objects}}
        ::GX::Native2D::core clear $scene
        foreach id $ids {::GX::Native2D::core object_style $scene $id {selected 1}}
    }
    method admit {event} {
        my valid
        if {![my callback admit $event 1]} {return 0}
        return 1
    }
    method begin {kind xy objects {handle {}} {reference {}}} {
        if {[llength $objects]>65536} {error {CAD operation exceeds65536 targets}}
        set event [dict create phase begin operation $kind objects $objects handle $handle reference $reference device $xy]
        if {![my admit $event]} {set last [dict create status denied operation $kind phase begin objects $objects];return 0}
        foreach id $objects {
            set style [::GX::Native2D::core object_style $scene $id]
            if {[dict get $style locked]} {error {CAD target is locked}}
            if {[dict get $style layer] && [dict get [::GX::Native2D::core layer_info $scene [dict get $style layer]] locked]} {error {CAD target layer is locked}}
        }
        set context [my callback begin $event]
        if {[string length $context]>256} {error {CAD begin must return a bounded opaque context token}}
        set gesture [dict merge $event [dict create context $context changed 0 proposal {}]]
        try {
            switch -- $kind {
                control {
                    dict set gesture origin [$cad control resolve $reference]
                    dict set gesture pointer [::GX::Native2D::core world $scene $xy]
                }
                points {$cad gesture begin_points $xy [$cad control resolve $reference]}
                translate - rotate - mirror - pivot {$cad gesture begin $handle $xy $objects}
            }
        } on error {m o} {my cancel rejected;return -options $o $m}
        return 1
    }
    method cancel {{reason cancel}} {
        if {$advanced ne {} && [llength [info commands $advanced]]} {$advanced cancel $reason}
        set old $gesture;set gesture {};set polygon {}
        if {$old ne {}} {
            if {$cad ne {} && [llength [info commands $cad]] && [dict get [$cad state] alive]} {catch {$cad gesture cancel}}
            my clearPreview
            my callback cancelled [dict merge $old [dict create phase cancelled reason $reason]]
        }
        if {[winfo exists $c]} {$c delete cad_host_feedback}
        set last [dict create status cancelled reason $reason]
        return $last
    }
    method clearPreview {} {
        if {$preview} {catch {::GX::Native2D::core delete $scene $preview};set preview 0}
    }
    method preview {event} {
        if {[dict exists $cb preview]} {my callback preview $event;return}
        my clearPreview
        if {[dict exists $event definition] && [dict get $event definition] ne {}} {
            set preview [$cad object create [dict get $event definition] 128]
            $cad object style $preview {selectable 0 color {0.1 0.65 0.48 1} line_style 1 line_width 2}
            ::GX::native2DSceneFeedback $scene [list $preview]
        }
    }
    method move {xy} {
        if {$gesture eq {}} {return 0}
        my valid;set kind [dict get $gesture operation]
        if {$kind eq {region}} {dict set gesture device_end $xy;my refresh interaction;return 1}
        if {$kind eq {pan}} {
            lassign [dict get $gesture device] px py;lassign $xy x y
            ::GX::Native2D::core pan $scene [expr {$x-$px}] [expr {$y-$py}]
            dict set gesture device $xy;dict set gesture changed 1;my refresh navigation;return 1
        }
        if {$kind eq {control}} {
            set ref [dict get $gesture reference]
            set snap [::GX::Native2D::core interaction_snap $scene $xy 10 [dict get $gesture objects] [dict get $opts object_snap] 1]
            set target [dict get $snap point]
            if {[dict get $snap kind] eq {none}} {set target [lmap now $target pointer [dict get $gesture pointer] origin [dict get $gesture origin] {expr {$origin+$now-$pointer}}]}
            set proposal [dict create target $target snap $snap]
            if {![my admit [dict merge $gesture [dict create phase plan proposal $proposal]]]} {my cancel denied;return 1}
            if {[catch {set definition [$cad control preview $ref $target]} message]} {
                dict set gesture proposal {};my preview [dict merge $gesture [dict create phase preview definition {}]]
                set last [dict create status preview_rejected error $message];my refresh interaction;return 1
            }
            dict set proposal definition $definition;dict set gesture proposal $proposal
            dict set gesture changed [expr {$target ne [dict get $gesture origin]}]
            my preview [dict merge $gesture [dict create phase preview definition $definition target $target]]
        } else {
            set proposal [$cad gesture plan $xy [dict get $opts object_snap]]
            if {![my admit [dict merge $gesture [dict create phase plan proposal $proposal]]]} {my cancel denied;return 1}
            $cad gesture apply;dict set gesture proposal $proposal;dict set gesture changed 1
        }
        set last [dict create status preview operation $kind proposal $proposal]
        my refresh interaction
        return 1
    }
    method finish {{xy {}}} {
        if {$polygon ne {}} {
            if {[llength $polygon]<3} {error {Polygon selection needs at least3 vertices}}
            my select [$cad selection region [my scope] $polygon 65536 object] [dict get $last selection_mode]
            set polygon {};my refresh final;return 1
        }
        if {$gesture eq {}} {return 0}
        set old $gesture;set kind [dict get $old operation]
        if {$kind eq {region}} {
            set gesture {};lassign [dict get $old device] ax ay;lassign $xy bx by
            if {hypot($bx-$ax,$by-$ay)>3} {
                lassign [::GX::Native2D::core world $scene [list $ax $ay]] x0 y0;lassign [::GX::Native2D::core world $scene [list $bx $by]] x1 y1
                my select [$cad selection region [my scope] [list [list $x0 $y0] [list $x1 $y0] [list $x1 $y1] [list $x0 $y1]] 65536 object] [dict get $old selection_mode]
            } elseif {[dict get $old selection_mode] eq {replace}} {my select {}}
            my refresh final;return 1
        }
        if {$kind eq {pan}} {set gesture {};my callback navigation [dict merge $old [dict create phase finished]];my refresh final;return 1}
        if {![my admit [dict merge $old [dict create phase commit]]]} {my cancel denied;return 1}
        try {
            if {$kind eq {control}} {
                if {[dict get $old changed] && [dict get $old proposal] ne {}} {$cad control edit [dict get $old reference] [dict get $old proposal target]}
            } else {$cad gesture commit}
        } on error {m o} {my cancel rejected;return -options $o $m}
        set gesture {};my clearPreview
        set event [dict merge $old [dict create phase committed status committed]]
        try {set domain [my callback committed $event]} on error {m o} {my callback rollback [dict merge $event [dict create error $m]];return -options $o $m}
        set last [dict merge [dict remove $event context] [dict create domain_receipt $domain]]
        my refresh final
        return 1
    }
    method down {xy state} {
        my valid
        if {$tool ni $tools} {error {Current CAD tool is disabled}}
        focus $c
        if {$gesture ne {}} {my cancel restarted}
        set mode [my mode $state]
        if {$tool eq {pan}} {set gesture [dict create operation pan device $xy changed 0];return 1}
        if {$tool eq {polygon}} {
            if {$polygon eq {}} {set last [dict create status polygon selection_mode $mode]}
            lappend polygon [::GX::Native2D::core world $scene $xy];my refresh interaction;return 1
        }
        if {$tool in {translate rotate mirror pivot}} {
            set ids [my callback targets [dict create phase targets] [dict get [$cad selection snapshot] objects]]
            my activate $ids
            set handle [::GX::Native2D::core gizmo_hit $scene $xy 5]
            if {$tool eq {pivot}} {set handle pivot}
            if {$handle eq {none}} {
                set ref [my pick $xy object]
                if {$ref ne {}} {my select [list [dict create kind object id [dict get $ref object] index 0]] $mode $ref;my refresh final;return 1}
                if {[my begin pivot $xy {} pivot]} {$cad gesture plan $xy;$cad gesture apply;dict set gesture changed 1;my finish $xy};return 1
            }
            my begin [expr {$handle in {pivot mirror_a mirror_b}?{pivot}:$tool}] $xy [expr {$handle in {pivot mirror_a mirror_b}?{}:$ids}] $handle
            return 1
        }
        set ref [expr {$tool eq {rectangle}?{}:[my pick $xy]}]
        if {$ref eq {}} {set gesture [dict create operation region device $xy device_end $xy selection_mode $mode];return 1}
        set kind [dict get $ref semantic_kind];set index [expr {$kind eq {object}?0:[dict get $ref index]}];set native [dict get $ref object]
        set selected 0
        foreach member [dict get [$cad selection get] members] {if {[dict get $member valid] && [dict get $member id]==$native && [dict get $member kind] eq $kind && [dict get $member index]==$index} {set selected 1;break}}
        if {$mode ne {replace} || !$selected} {my select [list [dict create kind $kind id $native index $index]] $mode $ref} else {my callback selected [dict create phase selected reference $ref selection [$cad selection snapshot]]}
        if {$mode eq {replace} && $kind in {control point} && [expr {$kind eq {control}?{control}:{points}}] in $tools} {my begin [expr {$kind eq {control}?{control}:{points}}] $xy [list $native] {} $ref}
        my refresh final
        return 1
    }
    method event {phase args} {
        if {$dispatching} {error {Reentrant CAD input dispatch is not permitted}}
        incr dispatching
        try {
            if {$phase in {down move up wheel pan_start pan_move pan_end}} {
                if {[llength $args]<2 || [llength $args]>3} {error {CAD pointer input needs two coordinates and optional state}}
                foreach value [lrange $args 0 1] {if {![string is double -strict $value] || ![expr {abs($value)<Inf && abs($value)<=1e12}]} {error {CAD pointer coordinates must be finite and bounded}}}
            }
            # Escape terminates every owned input scope, including navigation
            # temporarily overlapping a staged advanced proposal.
            if {$phase eq {key} && [lindex $args 0] eq {Escape}} {my cancel escape;my refresh final;return 1}
            # Advanced tools may consume pointer-down before the basic select
            # handler; keyboard Finish/Escape must still belong to this Canvas.
            if {$phase in {down pan_start}} {my valid;focus $c}
            if {[dict get $opts advanced_dispatch] && $advanced ne {} && [llength [info commands $advanced]] && [$advanced event $phase {*}$args]} {return 1}
            switch -- $phase {
                down {lassign $args x y state;return [my down [list $x $y] $state]}
                move {return [my move [lrange $args 0 1]]}
                up {if {$tool eq {polygon} && $gesture eq {}} {return 1};return [my finish [lrange $args 0 1]]}
                key {
                    if {[lindex $args 0] eq {Escape}} {my cancel escape;my refresh final;return 1}
                    if {[lindex $args 0] eq {Return}} {return [my finish]}
                    return 0
                }
                wheel {
                    my valid
                    if {{zoom} ni $tools} {error {CAD zoom is disabled}}
                    lassign $args x y delta
                    if {![string is double -strict $delta] || ![expr {abs($delta)<Inf}]} {error {CAD wheel delta must be finite}}
                    ::GX::Native2D::core zoom $scene [expr {$delta>0?0.82:1.22}] [list $x $y]
                    my callback navigation [dict create phase changed operation zoom];my refresh navigation;return 1
                }
                pan_start {my valid;if {{pan} ni $tools} {error {CAD pan is disabled}};if {$gesture ne {}} {error {Finish the active CAD operation before panning}};set gesture [dict create operation pan device [lrange $args 0 1] changed 0];return 1}
                pan_move {return [my move [lrange $args 0 1]]}
                pan_end {return [my finish [lrange $args 0 1]]}
                resize {my refresh resize;return 0}
                default {error {Unknown CAD input phase}}
            }
        } on error {m o} {
            catch {my cancel rejected}
            set last [dict create status rejected error $m errorcode [dict get $o -errorcode]]
            if {[catch {my callback error $last} notification]} {dict set last notification_error $notification}
            return 1
        } finally {incr dispatching -1}
    }
    method refresh {{reason requested}} {
        if {![my drawable]} {
            if {$scheduler ne {}} {catch {::GX::guiUpdateSchedulerDispose $scheduler};set scheduler {}}
            return
        }
        if {$scheduler ne {} && [catch {::GX::guiUpdateSchedulerDescribe $scheduler}]} {set scheduler {}}
        if {[dict get $opts external_render]} {my callback refresh [dict create phase refresh reason $reason final [expr {$reason eq {final}}]];return}
        if {$scheduler eq {}} {set scheduler [::GX::guiUpdateSchedulerCreate $c [list [self] render] [dict create profile global policy adaptive normal_ms 16 activity_window_ms 80 rapid_count 8 quiet_ms 80 guard [list [self] drawable]]]}
        ::GX::guiUpdateSchedulerRequest $scheduler
        if {$reason eq {final}} {::GX::guiUpdateSchedulerFinish $scheduler}
    }
    method overlays {} {
        $c delete cad_host_feedback
        if {$gesture ne {} && [dict get $gesture operation] eq {region}} {$c create rectangle {*}[dict get $gesture device] {*}[dict get $gesture device_end] -outline #426cbb -dash {4 3} -tags cad_host_feedback}
        if {$polygon ne {}} {
            set points {};foreach p $polygon {lappend points {*}[::GX::Native2D::core device $scene $p]}
            if {[llength $points]>=4} {$c create line {*}$points -fill #536fc1 -dash {4 3} -tags cad_host_feedback}
            foreach {x y} $points {$c create oval [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] -fill #536fc1 -tags cad_host_feedback}
        }
        if {$advanced ne {} && [llength [info commands $advanced]]} {$advanced overlays}
    }
    method drawable {} {
        if {$cad eq {} || ![winfo exists $c] || ![llength [info commands $cad]] || ![dict get [$cad state] alive]} {return 0}
        if {[catch {my callback guard [dict create phase guard] 1} accepted]} {return 0}
        return $accepted
    }
    method render {} {
        my valid
        set view [::GX::Native2D::core view_requested $scene]
        lset view 0 [expr {max(120,[winfo width $c])}];lset view 1 [expr {max(100,[winfo height $c])}]
        ::GX::Native2D::core view $scene $view
        set view [::GX::Native2D::core view $scene];lassign $view w h l t r b;lassign [lindex $view 6] x0 y0 x1 y1
        set data [my callback presentation [dict create phase presentation]]
        if {![dict exists $data plans]} {
            set plans [dict create x [dict merge [::GX::native2DAxisPlan $x0 $x1 [expr {$w-$l-$r}]] {label X}] y [dict merge [::GX::native2DAxisPlan $y0 $y1 [expr {$h-$t-$b}]] {label Y}]]
        } else {set plans [dict get $data plans]}
        set background [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA [::GX::Native2D::core background $scene]] #FFFFFF]
        set background [dict get $background rgb];$c configure -background $background
        ::GX::native2DGridPresenterBegin $c [list [self] refresh configuration]
        ::GX::native2DGridPresenterUpdate $c $scene $plans
        ::GX::native2DSpriteSceneBegin $c [list $l $t [expr {$w-$r}] [expr {$h-$b}]]
        set descriptors [::GX::datasetPublicationV2DictDefault $data descriptors {}]
        if {![dict exists $data descriptors]} {foreach id [my scope] {lappend descriptors [dict create id native$id object $id sample_markers 0 controls 1]}}
        if {$preview} {lappend descriptors [dict create id preview object $preview sample_markers 0]}
        ::GX::native2DSpriteSceneSync $c $scene $descriptors [dict create background $background]
        ::GX::native2DSpriteSceneEnd $c
        ::GX::native2DGridPresenterEnd $c
        # Public overlay helpers append transient items; this frame owns their
        # clearing. Scientific sprites/grid remain retained and are not deleted.
        $c delete semantic_object_selection semantic_segment_selection semantic_point_selection native_gizmo
        ::GX::native2DCadSelectionPresent $cad $c
        if {$tool in {translate rotate mirror pivot}} {::GX::native2DCanvasDrawGizmo $c $scene $background}
        my overlays
    }
    method fit {{selected 0}} {
        my valid
        if {{fit} ni $tools} {error {CAD Fit is disabled}}
        if {$selected} {set set [dict get [$cad selection get] id];::GX::Native2D::core fit_bounds $scene [::GX::Native2D::core selection_set_bounds $scene $set]} else {::GX::Native2D::core fit $scene}
        my callback navigation [dict create phase finished operation fit];my refresh final
    }
    method detach {} {
        my cancel detach
        if {$scheduler ne {}} {::GX::guiUpdateSchedulerDispose $scheduler;set scheduler {}}
        if {$ownsCad} {::GX::native2DCadDispose $cad}
        set cad {};catch {::GX::native2DSpriteSceneDetach $c};set scene {};incr generation
    }
    method dispose {} {my destroy}
}
