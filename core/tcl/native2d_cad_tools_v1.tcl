# SPDX-License-Identifier: GPL-3.0-or-later
# Advanced GUI coordination over the same CAD Host/context. All definitions,
# attachment, topology, relationships and solving remain Native2D C operations.
proc ::GX::native2DCadConstructionCount {family} {
    set counts {point 1 line 2 construction_line 2 rectangle 2 circle 2 arc 3 ellipse 3 quadratic_bezier 3 cubic_bezier 4 path 0 polyline 0 spline 0}
    if {![dict exists $counts $family]} {error {Unsupported native construction family}}
    return [dict get $counts $family]
}
oo::class create ::GX::Native2DCadCanvas::Advanced {
    variable host generation construct last running topologyPlan directionDrag
    constructor {owner} {
        set host $owner;set generation [dict get [$host state] generation]
        set construct {};set topologyPlan {};set last {};set running 0;set directionDrag {}
    }
    destructor {catch {my cancel dispose}}
    method host {} {return $host}
    method context {} {return [$host context]}
    method scene {} {return [dict get [$host state] scene]}
    method busy {} {return $running}
    method state {} {return [dict create construction $construct topology $topologyPlan direction $directionDrag receipt $last busy $running]}
    method Require {} {
        $host valid
        if {[dict get [$host state] generation]!=$generation} {my cancel source_change;set generation [dict get [$host state] generation];error {Advanced CAD source generation changed; start the tool again}}
    }
    method Notify {phase operation data {fallback {}}} {
        # Proposal details may contain their native operation name. Callback
        # routing always uses the qualified controller identity and phase.
        return [$host callback advanced [dict merge $data [dict create phase $phase operation $operation]] $fallback]
    }
    method Run {operation objects command {data {}}} {
        my Require
        if {$running || ![$host targetsMutable]} {error {Finish or cancel the active CAD operation first}}
        set event [dict merge $data [dict create objects $objects]]
        if {![my Notify admit $operation $event 1]} {error {CAD operation was not admitted by its scientific owner}}
        set token [my Notify begin $operation $event]
        if {[string length $token]>256} {error {Advanced begin must return a bounded opaque token}}
        dict set event context $token
        # Admission/capture callbacks may open a reviewed domain form. Recheck
        # source/Session lifetime after they return, before any native mutation.
        my Require
        if {![$host targetsMutable]} {error {Another CAD operation acquired the scene during admission}}
        set running 1;set applied 0
        try {
            set receipt [uplevel #0 $command];set applied 1
            dict set event receipt $receipt
            set domain [my Notify committed $operation $event]
            set last [dict merge $event [dict create status committed operation $operation domain_receipt $domain]]
            return $receipt
        } on error {message options} {
            set last [dict merge $event [dict create status rejected operation $operation error $message]]
            if {$applied} {
                if {[catch {my Notify rollback $operation $last} recovery]} {
                    append message "; scientific owner recovery failed: $recovery"
                }
            } elseif {[catch {my Notify rejected $operation $last} notification]} {
                append message "; rejection notification failed: $notification"
            }
            return -options $options $message
        } finally {set running 0}
    }
    method Preview {operation data} {
        set handled [my Notify preview $operation $data]
        if {![dict exists $handled handled] || ![dict get $handled handled]} {
            if {[dict exists $data definition]} {$host preview $data}
        }
        return $data
    }
    method Excluded {} {
        set ids [$host feedbackObjects]
        lappend ids {*}[my Notify exclude construction {}]
        return [lsort -unique $ids]
    }
    method construction {action args} {
        my Require
        switch -- $action {
            count {return [::GX::native2DCadConstructionCount {*}$args]}
            start {
                lassign $args family options
                ::GX::native2DCadConstructionCount $family
                if {$running} {error {Finish the active scientific operation}}
                my cancel tool_change
                foreach key [dict keys $options] {if {$key ni {auto_commit samples chain symmetry placement_color}} {error {Unknown construction option}}}
                set options [dict merge {auto_commit 1 samples 257 chain {} symmetry {} placement_color #237a6a} $options]
                set samples [dict get $options samples]
                if {![string is integer -strict $samples] || $samples<2 || $samples>65536} {error {Construction samples must be2..65536}}
                set construct [dict create family $family places {} options $options proposal {} ready 0]
                set generation [dict get [$host state] generation]
                return $construct
            }
            state {return $construct}
            cancel {return [my cancel construction_cancel]}
            pick {
                if {$construct eq {}} {error {Start a construction first}}
                return [::GX::Native2D::core construction_pick [my scene] [lindex $args 0] 9 [dict get $construct places] [my Excluded] 1]
            }
            adopt {
                # Import only placements previously produced by the public native
                # construction contract, e.g. a scientific reviewed point form.
                if {$construct eq {}} {error {Start a construction first}}
                if {[llength [lindex $args 0]]>65536} {error {Too many construction placements}}
                ::GX::Native2D::core construction_points [my scene] [lindex $args 0]
                dict set construct places [lindex $args 0]
                return $construct
            }
            preview {
                if {$construct eq {}} {return {}}
                set places [dict get $construct places];if {$places eq {}} {return {}}
                set candidate [lindex $args 0];set family [dict get $construct family]
                if {$candidate ne {} && !([dict exists $candidate earlier] && [dict get $candidate earlier]==[llength $places]-1)} {set proposed [concat $places [list $candidate]]} else {set proposed $places}
                set definition {}
                if {[catch {set definition [::GX::Native2D::core construction_preview [my scene] $family $proposed]} message]} {
                    if {[catch {set definition [::GX::Native2D::core construction_preview [my scene] $family $places]}]} {set definition {}}
                }
                dict set construct proposal $definition
                set data [dict create family $family places $places candidate $candidate definition $definition]
                if {![my Notify admit construction.preview $data 1]} {error {Construction preview was not admitted}}
                my Preview construction $data
                return $data
            }
            click {
                lassign [lindex $args 0] x y
                lassign [::GX::Native2D::core view [my scene]] width height left top right bottom
                if {$x<$left || $y<$top || $x>$width-$right || $y>$height-$bottom} {return [dict create ready 0 outside 1]}
                set candidate [my construction pick [lindex $args 0]]
                set family [dict get $construct family];set places [dict get $construct places]
                if {$family eq {line} && [llength $places]==1 && [dict exists $candidate earlier] && [dict get $candidate earlier]==0} {return [dict create ready 0 finished 1]}
                if {[llength $places]>=65536} {error {Too many construction placements}}
                lappend places $candidate;dict set construct places $places
                set count [::GX::native2DCadConstructionCount $family]
                set attached [expr {$family in {path polyline spline} && [dict exists $candidate reference] && [llength $places]>=2}]
                set closed [expr {!$count && [dict exists $candidate earlier] && [dict get $candidate earlier]==0 && [llength $places]>=3}]
                set ready [expr {$attached || ($count && [llength $places]==$count) || $closed}]
                dict set construct ready $ready
                set data [dict create ready $ready placement $candidate places $places points [::GX::Native2D::core construction_points [my scene] $places]]
                if {$ready && [dict get $construct options auto_commit]} {dict set data receipt [my construction commit]} else {my construction preview}
                return $data
            }
            overlay {
                if {$construct eq {} || [dict get $construct places] eq {}} return
                set canvas [$host canvas];set color [dict get $construct options placement_color]
                foreach point [::GX::Native2D::core construction_points [my scene] [dict get $construct places]] {
                    lassign [::GX::Native2D::core device [my scene] $point] x y
                    $canvas create oval [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] -fill $color -outline white -tags construction_placement
                }
            }
            commit {
                if {$construct eq {}} {error {Start a construction first}}
                set family [dict get $construct family];set places [dict get $construct places];set options [dict get $construct options]
                if {[llength $args]} {set options [dict merge $options [lindex $args 0]]}
                set needed [::GX::native2DCadConstructionCount $family]
                if {($needed && [llength $places]!=$needed) || (!$needed && [llength $places]<2)} {error {Place the remaining defining controls first}}
                set parents {};foreach p $places {if {[dict exists $p reference]} {lappend parents [dict get $p reference object]}}
                set command [list ::GX::Native2D::core construction_create [my scene] $family $places [dict get $options samples] [dict get $options chain] {*}[dict get $options symmetry]]
                # Temporary presentation objects must never enter a domain's
                # before/after scientific History capture.
                $host clearPreview
                set receipt [my Run construction.create [lsort -unique $parents] $command [dict create family $family places $places]]
                dict set construct places {};dict set construct proposal {};dict set construct ready 0
                $host clearPreview
                my Notify preview construction [dict create family $family definition {} places {}]
                $host refresh final
                return $receipt
            }
            default {error {Unknown construction operation}}
        }
    }
    method control {action reference {target {}}} {
        my Require
        set cad [my context]
        switch -- $action {
            inspect {return [$cad control inspect $reference]}
            preview {return [$cad control preview $reference $target]}
            edit {
                set definition [$cad control preview $reference $target]
                return [my Run control.edit [list [dict get $reference object]] [list $cad control edit $reference $target] [dict create reference $reference target $target definition $definition]]
            }
            default {error {Unknown defining-control operation}}
        }
    }
    method topology {action args} {
        my Require
        switch -- $action {
            state {return $topologyPlan}
            connected {
                set eligible {}
                foreach object [::GX::native2DConnectedObjects [my scene] [lindex $args 0]] {
                    set cad [my context]
                    if {[catch {set definition [$cad object definition $object]}]} {return {}}
                    if {[dict get $definition family] ni {line path polyline spline quadratic_bezier cubic_bezier arc circle ellipse rectangle composite_path} || [dict get [$cad object style $object] locked]} {return {}}
                    lappend eligible $object
                }
                return $eligible
            }
            cancel {set topologyPlan {};return {}}
            prepare - apply {
                lassign $args operation objects options
                if {[llength $objects]<1 || [llength $objects]>65536} {error {Choose a bounded native topology target list}}
                foreach object $objects {
                    [my context] object style $object
                    if {$operation ne {join_points}} {[my context] object definition $object}
                }
                foreach key [dict keys $options] {if {$key ni {tolerance index target_index merge}} {error {Unknown topology option}}}
                set options [dict merge {tolerance 0 index 0 target_index 0 merge 0} $options]
                set references {};foreach object $objects {lappend references [[my context] selection reference $object object 0]}
                set plan [dict create operation $operation objects $objects options $options references $references]
                if {$operation ni {join_path compound separate split_path split_composition join_points}} {error {Unsupported native topology workflow}}
                if {$operation in {separate split_path split_composition} && [llength $objects]!=1} {error {Choose one retained Path or Compound}}
                if {$operation eq {join_points} && [llength $objects]!=2} {error {Choose two native point owners}}
                set topologyPlan $plan
                if {$action eq {prepare}} {return $plan}
                return [my topology commit]
            }
            commit {
                if {$topologyPlan eq {}} {error {Prepare a topology operation first}}
                set plan $topologyPlan;set operation [dict get $plan operation];set objects [dict get $plan objects];set options [dict get $plan options];set cad [my context]
                foreach ref [dict get $plan references] {$cad control resolve $ref}
                switch -- $operation {
                    join_path - compound {set command [list $cad object join $objects {} [expr {$operation eq {compound}?0:2}] [dict get $options tolerance]]}
                    separate {set command [list $cad object separate [lindex $objects 0]]}
                    split_path - split_composition {set command [list $cad object $operation [lindex $objects 0] [dict get $options index]]}
                    join_points {set command [list $cad relationship join [lindex $objects 0] [dict get $options index] [lindex $objects 1] [dict get $options target_index] [dict get $options merge] [dict get $options tolerance]]}
                }
                set receipt [my Run topology.$operation $objects $command $plan]
                set topologyPlan {};return $receipt
            }
            default {error {Unknown topology operation}}
        }
    }
    method DirectionGet {object part} {
        if {$part eq {}} {return [[my context] object direction $object]}
        return [[my context] component direction $object $part]
    }
    method DirectionSet {object part changes} {
        if {$part eq {}} {return [[my context] object direction $object $changes]}
        return [[my context] component direction $object $part $changes]
    }
    method direction {action args} {
        if {$action ni {state cancel}} {my Require}
        switch -- $action {
            state {return $directionDrag}
            get {return [my DirectionGet {*}$args]}
            properties {
                lassign $args object part changes
                if {$part eq {}} {set command [list [my context] object direction $object $changes]} else {set command [list [my context] component direction $object $part $changes]}
                return [my Run direction.properties [list $object] $command [dict create part $part changes $changes]]
            }
            start {
                lassign $args object part
                if {![$host targetsMutable]} {error {Finish the active CAD interaction first}}
                my cancel tool_change
                set before [my DirectionGet $object $part]
                set event [dict create objects [list $object] part $part before $before]
                if {![my Notify admit direction.place $event 1]} {error {Direction placement was not admitted}}
                set context [my Notify begin direction.place $event]
                if {[string length $context]>256} {error {Direction context token exceeds capacity}}
                set directionDrag [dict merge $event [dict create object $object context $context changed 0]]
                return $directionDrag
            }
            move {
                if {$directionDrag eq {}} {return 0}
                set event [dict merge $directionDrag [dict create device [lindex $args 0]]]
                if {![my Notify admit direction.preview $event 1]} {my direction cancel;error {Direction preview was not admitted}}
                set object [dict get $directionDrag object];set part [dict get $directionDrag part]
                if {$part eq {}} {::GX::Native2D::core marker_place [my scene] $object [lindex $args 0]} else {[my context] component place $object $part [lindex $args 0]}
                dict set directionDrag proposal [my DirectionGet $object $part]
                dict set directionDrag changed [expr {[dict get $directionDrag proposal] ne [dict get $directionDrag before]}]
                return $directionDrag
            }
            commit {
                if {$directionDrag eq {}} {return {changed 0}}
                set event $directionDrag
                if {![my Notify admit direction.place $event 1]} {my direction cancel;error {Direction commit was not admitted}}
                try {
                    if {[dict get $event changed]} {my Notify committed direction.place [dict merge $event [dict create receipt [my DirectionGet [dict get $event object] [dict get $event part]]]]}
                } on error {message options} {my direction cancel;return -options $options $message}
                set directionDrag {};set last [dict merge $event [dict create status committed operation direction.place]]
                return $last
            }
            cancel {
                set old $directionDrag;set directionDrag {}
                if {$old ne {}} {
                    set cad [my context]
                    if {$cad ne {} && [llength [info commands $cad]] && [dict get [$cad state] alive] && [dict get $old object] in [::GX::Native2D::core ids [my scene]]} {my DirectionSet [dict get $old object] [dict get $old part] [dict get $old before]}
                    my Notify cancelled direction.place [dict merge $old {reason cancelled}]
                }
                return {status cancelled}
            }
            default {error {Unknown direction operation}}
        }
    }
    method event {phase args} {
        if {$directionDrag ne {}} {
            switch -- $phase {
                down {return 1}
                move {my direction move [lrange $args 0 1];$host refresh interaction;return 1}
                up {my direction commit;$host refresh final;return 1}
                key {if {[lindex $args 0] eq {Escape}} {my direction cancel;$host refresh final;return 1}}
            }
        }
        if {$construct ne {}} {
            switch -- $phase {
                down {my construction click [lrange $args 0 1];$host refresh interaction;return 1}
                move {set placement [my construction pick [lrange $args 0 1]];my construction preview $placement;$host refresh interaction;return 1}
                up {return 1}
                key {
                    if {[lindex $args 0] eq {Escape}} {my cancel escape;$host refresh final;return 1}
                    if {[lindex $args 0] eq {Return}} {if {[dict get $construct places] ne {}} {my construction commit};return 1}
                }
            }
        }
        if {[lsearch -exact [info object methods [self] -all] relationEvent]>=0} {return [my relationEvent $phase {*}$args]}
        return 0
    }
    method overlays {} {
        if {[lsearch -exact [info object methods [self] -all] relationOverlay]>=0} {my relationOverlay}
    }
    method cancel {{reason cancel}} {
        if {$running} {error {A native advanced operation is being committed}}
        my direction cancel
        set old $construct;set construct {};set topologyPlan {}
        if {[lsearch -exact [info object methods [self] -all] relationCancel]>=0} {my relationCancel $reason}
        if {$old ne {}} {$host clearPreview;my Notify cancelled construction [dict create reason $reason state $old];my Notify preview construction [dict create definition {} places {}]}
        return [dict create status cancelled reason $reason]
    }
    method dispose {} {my destroy}
}
