# SPDX-License-Identifier: GPL-3.0-or-later
# Additive NATIVE2D_API_v1 host adapter. The Native3D public mapper supplies
# camera projection; Native2D C owns definitions, references, snapping and drags.
namespace eval ::GX::Native2DCadProjection {}
proc ::GX::native2DCadProjectionAttach {host mapping {options {}}} {
    if {[$host projection] ne {}} {error {A CAD projection is already attached}}
    return [::GX::Native2DCadProjection::Adapter new $host $mapping $options]
}
oo::class create ::GX::Native2DCadProjection::Adapter {
    variable host canvas scene cad mapping options cache references gizmos ready reason frame dirty hits tessellation generation selectionReferences localCache
    constructor {owner mapper opts} {
        set host $owner;set canvas [$host canvas];set scene [dict get [$host state] scene];set cad [$host context]
        set localCache {};set mapping {};set cache {};set references {};set gizmos {};set ready 0;set reason {};set frame {};set dirty 1;set hits {};set tessellation {};set generation [dict get [$host state] generation];set selectionReferences {}
        set options {mapping {} chrome_raise_command {} resident_base 0 base_ready_command {} quality_valid_command {}}
        ::GX::native2DSpriteSceneDetach $canvas
        my configure [dict merge $opts [dict create mapping $mapper]]
        $host configure [dict create projection [self] external_render 0]
    }
    destructor {
        if {[llength [info commands $host]] && [$host projection] eq [self]} {catch {$host configure {projection {}}}}
        if {[winfo exists $canvas]} {catch {::GX::native2DSpriteSceneDispose $canvas};$canvas delete cad_projection_status cad_projected_relation cad_projected_axes constraint_marker cad_relation_preview construction_placement cad_host_feedback}
    }
    method configure {changes} {
        foreach key [dict keys $changes] {if {![dict exists $options $key]} {error "Unknown CAD projection option: $key"}}
        if {[dict exists $changes mapping]} {
            set next [dict get $changes mapping]
            if {![llength [info commands $next]]} {error {CAD projection mapper is unavailable}}
            set metadata [$next info]
            # A scientific pointer transaction cannot cross camera generations.
            if {$mapping ne {} && $next ne $mapping && [$host pointerActive]} {$host cancel camera_changed}
            set mapping $next;set frame $metadata;set ready 0;set reason {};set cache {};set dirty 1
        }
        set options [dict merge $options $changes]
        return [my info]
    }
    method info {} {return [dict create api_id NATIVE2D_API_v1 host $host mapping $mapping ready $ready reason $reason frame $frame cached_objects [dict size $cache] scientific_authority Native2D.C overlay_depth always_on_top]}
    method invalidate {{why requested}} {
        # Navigation resubmits only projection; selection resubmits styles.
        # Native solver edits can affect linked objects, so mutation/interaction
        # clears all local samples. No Document traversal or geometry mirror.
        set mutate [expr {$why ni {navigation resize selection interaction}}]
        if {$why eq {interaction}} {
            set interaction [dict get [$host state] gesture]
            set mutate [expr {$interaction ne {} && [dict get $interaction operation] in {translate rotate mirror points}}]
        }
        if {$mutate} {set cache {};set localCache {}}
        set dirty 1
    }
    method mapped {direction rows} {
        set state [$host state]
        if {[dict get $state generation]!=$generation || [dict get $state scene]!=$scene} {error {CAD projection belongs to a previous scientific scene generation}}
        if {![llength [info commands $mapping]]} {error {CAD camera projection has expired}}
        set result [$mapping map $direction $rows]
        return [dict get $result points]
    }
    method world {xy} {
        if {!$ready} {my virtualView}
        set point [lindex [my mapped to_plane [list $xy]] 0]
        if {[llength $point]!=2} {error {Pointer ray does not meet the visible working plane}}
        return $point
    }
    method device {xy} {
        set point [lindex [my mapped to_screen [list $xy]] 0]
        if {[llength $point]!=2} {error {CAD point is behind the camera or outside the valid working plane}}
        return $point
    }
    method nativePoints {rows} {return [my mapped to_screen [::GX::Native2D::core world_points $scene $rows]]}
    method inside {xy} {
        lassign $xy x y
        if {$x<0 || $y<0 || $x>=[winfo width $canvas] || $y>=[winfo height $canvas]} {return 0}
        return [expr {![catch {my world $xy}]}]
    }
    method virtualView {} {
        set w [winfo width $canvas];set h [winfo height $canvas]
        if {$w<2 || $h<2} {error {CAD viewport has no drawable area}}
        set corners [my mapped to_plane [list {0 0} [list $w 0] [list $w $h] [list 0 $h]]]
        set xs {};set ys {}
        foreach p $corners {if {[llength $p]!=2} {error {Working plane crosses the camera horizon; orient the plane before editing}};lappend xs [lindex $p 0];lappend ys [lindex $p 1]}
        set xs [lsort -real $xs];set ys [lsort -real $ys]
        set bounds [list [lindex $xs 0] [lindex $ys 0] [lindex $xs end] [lindex $ys end]]
        lassign $bounds x0 y0 x1 y1
        if {$x1-$x0<=0 || $y1-$y0<=0} {error {Working plane is edge-on to the camera}}
        # Native scientific view is an internal planar projection, never a
        # second widget or a second scientific scene. Margins are deliberately
        # zero because the actual Native3D owner already controls its viewport.
        set view [list $w $h 0 0 0 0 $bounds]
        set previous [::GX::Native2D::core view_requested $scene];set changed 0
        foreach old [concat [lrange $previous 0 5] [lindex $previous 6]] new [concat [lrange $view 0 5] [lindex $view 6]] {if {$old!=$new} {set changed 1;break}}
        if {$changed} {
            if {[::GX::Native2D::core drag_active $scene]} {error {Cancel the native gesture before changing its camera projection}}
            ::GX::Native2D::core aspect $scene auto
            ::GX::Native2D::core view $scene $view
            set cache {}
        }
        set tessellation {}
        # The extra eight-pixel domain contains the local error neighborhood
        # of visible tessellation fragments. The bound is not incorrectly
        # asserted across the entire off-screen local AABB.
        set scale [$mapping scale [list -8 -8 [expr {$w+7}] [expr {$h+7}]]]
        if {$scale ne {}} {
            if {![dict get $scale valid]} {error "Working-plane tessellation is unavailable: [dict get $scale reason]"}
            set bound [dict get $scale maximum_pixels_per_unit]
            set tessellation [list [expr {max($w,ceil(($x1-$x0)*$bound))}] [expr {max($h,ceil(($y1-$y0)*$bound))}] 0 0 0 0 $bounds]
        }
        set ready 1;set reason {}
    }
    method labelColor {} {return [::GX::uiFieldColorReadableText [dict create rgb [$canvas cget -background] alpha 1]]}
    method color {rgba} {
        # Preserve scientific stroke alpha: Cairo composites against actual
        # solids/frame pixels, not a flattened nominal viewport background.
        return [::GX::uiFieldColorFromRGBA $rgba]
    }
    method projectedPaths {paths color width {dash {}}} {
        set geometry {}
        foreach path $paths {
            # A horizon gap starts a new primitive, never an invented bridge.
            set run {}
            foreach point [my mapped to_screen $path] {
                if {[llength $point]==2} {lappend run $point} else {
                    if {[llength $run]>1} {lappend geometry [dict create kind line points $run stroke $color width $width dash $dash]};set run {}
                }
            }
            if {[llength $run]>1} {lappend geometry [dict create kind line points $run stroke $color width $width dash $dash]}
        }
        return $geometry
    }
    method appendPaths {id paths color width {dash {}}} {::GX::native2DSpriteSceneAppend $canvas $id [my projectedPaths $paths $color $width $dash]}
    method snapshot {id} {
        set retain [dict get $options resident_base]
        if {$retain && [dict get $options quality_valid_command] ne {}} {set retain [uplevel #0 [dict get $options quality_valid_command]]}
        if {[dict exists $cache $id]} {return [dict get $cache $id]}
        if {$retain && [dict exists $localCache $id]} {dict set cache $id [dict get $localCache $id];return [dict get $cache $id]}
        set prior [::GX::Native2D::core view_requested $scene]
        try {
            # Public native view changes are synchronous and non-scientific.
            # No callback/event-loop entry occurs until the original view has
            # been restored. Native exact-definition tessellation remains the
            # sole curve sampler, at a conservative projected pixel tolerance.
            if {$retain && ![::GX::Native2D::core drag_active $scene]} {
                set box [::GX::Native2D::core bounds $scene $id]
                lassign $box x0 y0 x1 y1
                set pad [expr {max(1.e-8,max($x1-$x0,$y1-$y0)*.01)}]
                set box [list [expr {$x0-$pad}] [expr {$y0-$pad}] [expr {$x1+$pad}] [expr {$y1+$pad}]]
                ::GX::Native2D::core view $scene [list 16384 16384 0 0 0 0 $box]
            } elseif {$tessellation ne {}} {::GX::Native2D::core view $scene $tessellation}
            set object [::GX::native2DPresentationObjectSnapshot $scene $id 65536]
            if {$object eq {}} {return {}}
            set paths {};foreach path [dict get $object paths] {lappend paths [::GX::Native2D::core world_points $scene $path]}
            dict set object paths $paths
        } finally {if {$tessellation ne {} || [dict get $options resident_base]} {::GX::Native2D::core view $scene $prior}}
        # Marker glyph widths remain screen-space properties. Rebuild marker
        # projection each frame rather than cache camera-dependent arrowheads.
        dict set cache $id $object
        if {$retain && ![$host pointerActive]} {dict set localCache $id $object}
        return $object
    }
    method reference {id entity index} {
        set ref [$cad selection reference $id $entity $index]
        dict set ref semantic_kind $entity
        return $ref
    }
    method controls {id style} {
        set controls [::GX::Native2D::core interaction_controls $scene $id]
        set positions [my mapped to_screen [lmap control $controls {dict get $control point}]]
        foreach control $controls point $positions {
            set ref $control;dict set ref semantic_kind control
            set index [dict get $control index];set key control_${id}_$index
            if {[llength $point]!=2} continue
            lassign $point x y
            set selected 0
            foreach member $selectionReferences {if {[dict get $member object]==$id && [dict get $member semantic_kind] in {control point} && [dict get $member index]==$index} {set selected 1;break}}
            set color [expr {$selected?{#ffbd3a}:{#426cbb}}];set r [expr {$selected?5:3}]
            ::GX::native2DSpriteSceneAppend $canvas $key [list [dict create kind rectangle points [list [list [expr {$x-$r}] [expr {$y-$r}]] [list [expr {$x+$r}] [expr {$y+$r}]]] stroke $color fill $color width 1]]
            dict set references $key $ref
        }
    }
    method segments {id object} {
        if {![dict exists $cache $id segment_sprites]} {
        set definition [::GX::Native2D::core sketch_definition $scene $id]
        if {$definition eq {}} {return}
        set family [dict get $definition family];set n 0
        switch -- $family {
            line - construction_line {set n 1}
            rectangle {set n 4}
            path - polyline - spline {set n [expr {[llength [dict get $definition controls]]-1}];if {$family eq {path} && [::GX::datasetPublicationV2DictDefault $definition closed 0]} {incr n}}
        }
        set sprites {}
        for {set i 0} {$i<$n} {incr i} {
            if {[catch {set ref [my reference $id segment $i];set points [::GX::Native2D::core interaction_render $scene $ref]}]} continue
            dict set sprites $i [my projectedPaths [list [::GX::Native2D::core world_points $scene $points]] #000000 0]
        }
        # The existing object cache is invalidated by camera/view generations
        # and native mutations. Reuse unchanged screen-space hit primitives
        # during selection and separate defining-control proposals; refresh the
        # actual epoch-checked scientific reference on every presentation pass.
        dict set cache $id segment_sprites $sprites
        }
        dict for {index geometry} [dict get $cache $id segment_sprites] {
            set key segment_${id}_$index
            ::GX::native2DSpriteSceneAppend $canvas $key $geometry
            dict set references $key [my reference $id segment $index]
        }
    }
    method grid {} {
        set config [::GX::Native2D::core grid $scene]
        set geometry {};set index 0
        set spacing [expr {[::GX::configurationGet ui.adaptive_grid_density]?16:0}]
        foreach line [::GX::Native2D::core render_grid_presentation $scene $spacing] {
            lassign $line ax ay bx by classification
            set category [dict get {0 minor 1 major 2 axes} $classification]
            set color [my color [dict get $config ${category}_color]]
            set dash [dict get {0 {} 1 {6 3} 2 {1 3}} [dict get $config ${category}_style]]
            my appendPaths grid[incr index] [list [::GX::Native2D::core world_points $scene [list [list $ax $ay] [list $bx $by]]]] $color [dict get $config ${category}_width] $dash
        }
    }
    method markers {id} {
        set definition [::GX::Native2D::core sketch_definition $scene $id]
        set rows {}
        if {$definition ne {} && [dict get $definition family] in {compound composite_path}} {
            foreach part [::GX::Native2D::core composition_states $scene $id] {
                if {![dict get $part direction visible] || ![dict get $part direction present]} continue
                set geometry [::GX::Native2D::core part_marker_render $scene $id [dict get $part part_id]]
                if {$geometry ne {}} {lappend rows [dict create geometry $geometry style [dict get $part direction]]}
            }
        } else {
            set geometry [::GX::Native2D::core render_marker $scene $id]
            if {$geometry ne {}} {lappend rows [dict create geometry $geometry style [::GX::Native2D::core direction_marker $scene $id]]}
        }
        set ordinal 0
        foreach row $rows {
            set m [dict get $row geometry];set s [dict get $row style]
            set points [my nativePoints [list [dict get $m tail] [dict get $m tip] [dict get $m head_left] [dict get $m head_right]]]
            if {{} in $points} continue
            lassign $points tail tip left right
            ::GX::native2DSpriteSceneAppend $canvas marker_${id}_[incr ordinal] [list [dict create kind line points [list $tail $tip] stroke [my color [dict get $s color]] width [dict get $s line_width]] [dict create kind line points [list $left $tip $right] stroke [my color [dict get $s color]] width [dict get $s line_width]]]
        }
    }
    method drawGizmo {} {
        set gizmos {};set i 0
        foreach primitive [::GX::Native2D::core render_gizmo $scene] {
            set key gizmo[incr i];set geometry {};set kind [dict get $primitive kind]
            set points [my nativePoints [list [dict get $primitive a] [dict get $primitive b]]]
            if {{} in $points} continue
            lassign $points a b
            if {$kind eq {line}} {set geometry [list [dict create kind line points [list $a $b] stroke [my color [dict get $primitive color]] width [dict get $primitive width]]]} else {
                # Native glyphs use device-sized handles. Preserve their native
                # placement; labels/handles intentionally remain legible glyphs.
                set geometry [list [dict create kind [expr {$kind eq {circle}?{ellipse}:{rectangle}}] points [list $a $b] stroke [my color [dict get $primitive color]] fill [my color [dict get $primitive color]] width [dict get $primitive width]]]
            }
            ::GX::native2DSpriteSceneAppend $canvas $key $geometry
            dict set gizmos $key [dict get $primitive handle]
        }
    }
    method render {} {
        $canvas delete cad_projection_status
        if {[catch {my virtualView} message]} {
            set ready 0;set reason $message
            # An invalid domain has no meaningful projected raster. Retire the
            # display-only sprite item rather than retaining its previous pixels
            # beneath a replacement native frame. Valid recovery recreates only
            # this overlay; exact geometry, native body and History survive.
            ::GX::native2DSpriteSceneDispose $canvas
            # Every projected annotation belongs to this camera/plane mapping.
            # Stale axes must not survive an invalid (e.g. edge-on) projection.
            $canvas delete cad_projected_axes cad_projected_relation constraint_marker cad_relation_preview construction_placement cad_host_feedback
            $canvas create text 12 [expr {max(12,[winfo height $canvas]-12)}] -anchor sw -width [expr {max(120,[winfo width $canvas]-24)}] -text $message -fill #e99b35 -tags cad_projection_status
            $canvas raise cad_projection_status
            return
        }
        set references {};set snapshot [$cad selection snapshot];set selected [dict get $snapshot objects];set selectionReferences [dict get $snapshot references]
        set wholeSelected {};foreach ref $selectionReferences {if {[dict get $ref semantic_kind] eq {object}} {lappend wholeSelected [dict get $ref object]}}
        ::GX::native2DSpriteSceneBegin $canvas [list 0 0 [winfo width $canvas] [winfo height $canvas]]
        my grid
        set confirmed 1
        if {[dict get $options base_ready_command] ne {}} {set confirmed [uplevel #0 [dict get $options base_ready_command]]}
        set ids [concat [$host scope] [$host feedbackObjects]]
        foreach old [dict keys $cache] {if {$old ni $ids} {dict unset cache $old}}
        foreach id $ids {
            set object [my snapshot $id]
            if {$object eq {}} continue
            set style [::GX::Native2D::core object_style $scene $id]
            if {![dict get $style visible]} continue
            if {[dict get $style layer]} {
                set layer [::GX::Native2D::core layer_info $scene [dict get $style layer]]
                if {![dict get $layer visible]} continue
                dict set style color [lreplace [dict get $style color] 3 3 [expr {[lindex [dict get $style color] 3]*[dict get $layer opacity]}]]
            }
            if {[lindex [dict get $style color] 3]<=0 && $id ni $wholeSelected} continue
            set key object_$id
            set color [expr {$id in $wholeSelected?{#d88700}:[my color [dict get $style color]]}]
            set width [expr {$id in $wholeSelected?max(4,[dict get $style line_width]):[dict get $style line_width]}]
            set base [expr {$confirmed && [dict get $options resident_base] && ![$host pointerActive] && $id ni [$host feedbackObjects] && $id ni $wholeSelected && [dict get $style line_style]==0}]
            my appendPaths $key [dict get $object paths] $color [expr {$base?0:$width}] [dict get {0 {} 1 {6 3} 2 {1 3}} [dict get $style line_style]]
            if {[dict get $object kind] ne {curve} || [dict get $style marker]!=0} {
                set geometry {}
                foreach path [dict get $object paths] {
                    foreach point [my mapped to_screen $path] {
                        if {[llength $point]!=2} continue
                        lassign $point x y;set marker [dict get $style marker]
                        if {$marker==3} {
                            lappend geometry [dict create kind line points [list [list [expr {$x-3}] $y] [list [expr {$x+3}] $y]] stroke $color width 1]
                            lappend geometry [dict create kind line points [list [list $x [expr {$y-3}]] [list $x [expr {$y+3}]]] stroke $color width 1]
                        } else {
                            lappend geometry [dict create kind [expr {$marker==2?{rectangle}:{ellipse}}] points [list [list [expr {$x-3}] [expr {$y-3}]] [list [expr {$x+3}] [expr {$y+3}]]] fill $color stroke $color width 1]
                        }
                    }
                }
                ::GX::native2DSpriteSceneAppend $canvas $key $geometry
            }
            if {[dict get $style selectable] && $id ni [$host feedbackObjects]} {dict set references $key [my reference $id object 0];my segments $id $object;my controls $id $style}
            if {[dict get $object kind] eq {curve}} {my markers $id}
        }
        # A selected segment retains its exact semantic native reference.
        foreach ref $selectionReferences {
            if {[dict get $ref semantic_kind] ne {segment}} continue
            set points [::GX::Native2D::core interaction_render $scene $ref]
            my appendPaths selected_[dict get $ref object]_[dict get $ref index] [list [::GX::Native2D::core world_points $scene $points]] #d88700 5
        }
        my drawGizmo
        ::GX::native2DSpriteSceneEnd $canvas
        $canvas raise native_sprite_scene
        set presentation [$host callback presentation [dict create phase presentation projected 1]]
        my axes [::GX::datasetPublicationV2DictDefault $presentation plans [::GX::native2DAxisPlans $scene]]
        set dirty 0
    }
    method complete {} {if {[dict get $options chrome_raise_command] ne {}} {uplevel #0 [dict get $options chrome_raise_command]}}
    method axes {plans} {
        $canvas delete cad_projected_axes
        set grid [::GX::Native2D::core grid $scene]
        if {![dict get $grid enabled] || ![dict get $grid axes_visible]} return
        lassign [lindex [::GX::Native2D::core view $scene] 6] x0 y0 x1 y1
        set crossX [expr {max($x0,min($x1,0.0))}];set crossY [expr {max($y0,min($y1,0.0))}]
        set color [my labelColor]
        set descriptor [::GX::native2DAxisPresentation $scene]
        foreach axis {x y} {
            set plan [dict get $plans $axis];set last {}
            foreach tick [dict get $plan ticks] {
                set value [dict get $tick value]
                set point [expr {$axis eq {x}?[list $value $crossY]:[list $crossX $value]}]
                set point [lindex [my mapped to_screen [list $point]] 0]
                if {[llength $point]!=2} continue
                lassign $point x y
                if {$x<20 || $x>[winfo width $canvas]-20 || $y<20 || $y>[winfo height $canvas]-20} continue
                if {$axis eq {x}} {
                    $canvas create line $x [expr {$y-3}] $x [expr {$y+3}] -fill $color -tags cad_projected_axes
                    $canvas create text $x [expr {$y+6}] -anchor n -text [dict get $tick label] -font TkSmallCaptionFont -fill $color -tags cad_projected_axes
                } else {
                    $canvas create line [expr {$x-3}] $y [expr {$x+3}] $y -fill $color -tags cad_projected_axes
                    $canvas create text [expr {$x-6}] $y -anchor e -text [dict get $tick label] -font TkSmallCaptionFont -fill $color -tags cad_projected_axes
                }
                set last $point
            }
            if {$last ne {}} {
                set settings [::GX::datasetPublicationV2DictDefault $descriptor $axis {}]
                set title [::GX::datasetPublicationV2DictDefault $plan label [::GX::datasetPublicationV2DictDefault $settings title [string toupper $axis]]]
                set unit [dict get [::GX::native2DAxisCoordinatePlan $scene $axis $settings] unit]
                if {$unit ne {}} {append title " ($unit)"}
                lassign $last x y
                set item [$canvas create text [expr {$x+10}] [expr {$y-12}] -anchor sw -text $title -font TkSmallCaptionFont -fill $color -tags cad_projected_axes]
                # Keep the complete title/unit inside the actual viewport after
                # perspective projection. Scientific tick positions stay fixed.
                lassign [$canvas bbox $item] left top right bottom
                set dx [expr {$left<4?4-$left:($right>[winfo width $canvas]-4?[winfo width $canvas]-4-$right:0)}]
                set dy [expr {$top<4?4-$top:($bottom>[winfo height $canvas]-4?[winfo height $canvas]-4-$bottom:0)}]
                if {$dx || $dy} {$canvas move $item $dx $dy}
            }
        }
    }
    method pick {xy target tolerance} {
        if {!$ready || $dirty} {my render}
        if {!$ready} {error $reason}
        set found [::GX::native2DSpriteSceneHit $canvas $xy $tolerance]
        set fallback {}
        foreach key $found {
            if {![dict exists $references $key]} continue
            set ref [dict get $references $key];set id [dict get $ref object]
            if {$id ni [$host scope]} continue
            set style [::GX::Native2D::core object_style $scene $id]
            if {![dict get $style selectable] || ![dict get $style visible]} continue
            if {$target eq {object}} {return [my reference $id object 0]}
            if {[dict get $ref semantic_kind] eq {control}} {$cad control resolve $ref;return $ref}
            if {[dict get $ref semantic_kind] eq {segment}} {return $ref}
            if {$fallback eq {}} {set fallback $ref}
        }
        if {$fallback ne {}} {
            # For retained constituents the native controller resolves its own
            # topology/index convention. No private part-index layout enters
            # this adapter; the graphical hit has already admitted the object.
            set ref [$cad selection pick [list [dict get $fallback object]] [$host nativeDevice $xy] 256 $target]
            if {$ref ne {} && [dict get $ref semantic_kind] ne {control}} {return $ref}
        }
        return $fallback
    }
    method gizmoHit {xy} {
        if {$dirty} {my render}
        foreach key [::GX::native2DSpriteSceneHit $canvas $xy 5] {if {[dict exists $gizmos $key]} {return [dict get $gizmos $key]}}
        return none
    }
    method snapProposalVisible {snapped ordinary} {
        set probe [lmap pivot [dict get $ordinary pivot] delta [dict get $ordinary translation] {expr {$pivot+$delta}}]
        set pair [my mapped to_screen [list $probe [dict get $snapped snap_target point]]]
        if {{} in $pair} {return 0}
        lassign [lindex $pair 0] x y;lassign [lindex $pair 1] a b
        return [expr {hypot($a-$x,$b-$y)<=8}]
    }
    method snap {xy excluded objectSnap} {
        set world [my world $xy];set native [::GX::Native2D::core device $scene $world]
        # Native C proposes exact scientific snap references. The displayed
        # pixel distance, not virtual-plane pixels, admits the proposal.
        set snap [::GX::Native2D::core interaction_snap $scene $native 256 $excluded $objectSnap 1]
        if {[dict get $snap kind] ne {none}} {
            lassign [my device [dict get $snap point]] a b;lassign $xy x y
            if {hypot($a-$x,$b-$y)<=10} {return $snap}
        }
        return [dict create point $world kind none]
    }
    method constructionPick {xy places excluded} {
        set world [my world $xy]
        set candidate [::GX::Native2D::core construction_pick $scene [::GX::Native2D::core device $scene $world] 256 $places $excluded 1]
        lassign [my device [dict get $candidate point]] a b;lassign $xy x y
        if {hypot($a-$x,$b-$y)<=9} {return $candidate}
        return [dict create point $world]
    }
    method relationPick {xy regions} {
        # Tk label bounds are actual projected Canvas pixels. Native geometry
        # definitions remain untouched by this purely graphical hit test.
        lassign $xy x y
        foreach item [lreverse [$canvas find overlapping [expr {$x-5}] [expr {$y-5}] [expr {$x+5}] [expr {$y+5}]]] {
            foreach tag [$canvas gettags $item] {if {[regexp {^native_constraint_([0-9]+)$} $tag -> id] && [dict exists $regions $id]} {$cad relationship get $id;return $id}}
        }
        foreach id [lreverse [dict keys $regions]] {lassign [dict get $regions $id] a b c d;if {$x>=$a && $x<=$c && $y>=$b && $y<=$d} {$cad relationship get $id;return $id}}
        return {}
    }
    method dispose {} {my destroy}
}
