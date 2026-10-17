# SPDX-License-Identifier: GPL-3.0-or-later
# Renderer-neutral CORE object/scene presentation adapters.
proc ::GX::native2DCanvasDrawGizmo {canvas scene background {tags {}}} {
    foreach primitive [::GX::Native2D::core render_gizmo $scene] {
        set color [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $primitive color]] $background]
        set args [list {*}[dict get $primitive a] {*}[dict get $primitive b] -width [dict get $primitive width] -tags [concat {native_gizmo} $tags [list gizmo_[dict get $primitive handle]]]]
        switch -- [dict get $primitive kind] {
            line {$canvas create line {*}$args -fill [dict get $color rgb]}
            circle {$canvas create oval {*}$args -outline [dict get $color rgb] -fill [dict get $color rgb]}
            box {$canvas create rectangle {*}$args -outline [dict get $color rgb] -fill [dict get $color rgb]}
        }
    }
}
proc ::GX::native2DPresentationObjectSnapshot {scene id {budget 4096} {label ""}} {
    if {![string is entier -strict $budget]||$budget<6||$budget>65536} {error "Object snapshot budget must be 6..65536"}
    if {$label eq ""} {set label "Object $id"}
        set kind [::GX::Native2D::core kind $scene $id]
        if {$kind eq "group"} {return {}}
        set style [::GX::Native2D::core object_style $scene $id]
        if {![dict get $style visible]} {return {}}
        set opacity [lindex [dict get $style color] 3]
        if {[dict get $style layer]!=0} {
            set layer [::GX::Native2D::core layer_info $scene [dict get $style layer]]
            if {![dict get $layer visible]} {return {}}
            set opacity [expr {$opacity*[dict get $layer opacity]}]
        }
        dict set style color [lreplace [dict get $style color] 3 3 $opacity]
        set sampled [::GX::Native2D::core [expr {$kind eq "curve" ? "render_curve_lod" : "render_lod"}] $scene $id $budget]
        set points [dict get $sampled points];set paths {};set start 0
        foreach cut [dict get $sampled breaks] {
            lappend paths [lrange $points $start $cut];set start [expr {$cut+1}]
        }
        lappend paths [lrange $points $start end]
        set object [dict create id $id kind $kind style $style paths $paths point_indices [dict get $sampled point_indices] label $label]
        set definition [::GX::Native2D::core sketch_definition $scene $id]
        if {$kind eq "curve"&&$definition ne {}&&[dict get $definition family] in {compound composite_path}} {
            set markers {}
            foreach part [::GX::Native2D::core composition_states $scene $id] {
                if {![dict get $part direction visible]||![dict get $part direction present]} continue
                set marker [::GX::Native2D::core part_marker_render $scene $id [dict get $part part_id]]
                if {$marker eq {}} continue
                set markerStyle [dict get $part direction]
                dict set markerStyle color [lreplace [dict get $markerStyle color] 3 3 [expr {[lindex [dict get $markerStyle color] 3]*$opacity}]]
                lappend markers [dict create part_id [dict get $part part_id] geometry $marker style $markerStyle]
            }
            dict set object part_markers $markers
        } elseif {$kind eq "curve"} {
            set marker [::GX::Native2D::core render_marker $scene $id]
            if {$marker ne {}} {
                dict set object marker $marker
                set markerStyle [::GX::Native2D::core direction_marker $scene $id]
                dict set markerStyle color [lreplace [dict get $markerStyle color] 3 3 [expr {[lindex [dict get $markerStyle color] 3]*$opacity}]]
                dict set object marker_style $markerStyle
            }
        }
    return $object
}
proc ::GX::native2DCanvasDrawObject {canvas object background {tags {}}} {
    if {$object eq {}} return
    if {[lindex [dict get $object style color] 3]<=0} return
    set objectTags [concat [list geometry object_[dict get $object id]] $tags]
        set style [dict get $object style];set color [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $style color]] $background]
        set options [list -fill [dict get $color rgb] -width [dict get $style line_width] -tags $objectTags]
        if {[dict get $style line_style]==1} {lappend options -dash {6 3}} elseif {[dict get $style line_style]==2} {lappend options -dash {1 3}}
        foreach path [dict get $object paths] {
            if {[dict get $object kind] eq "curve"&&[llength $path]>1} {$canvas create line {*}[concat {*}$path] {*}$options}
            if {[dict get $object kind] ne "curve"||[dict get $style marker]!=0} {
                foreach point $path {
                    lassign $point x y;set pointTags [concat $objectTags native_point]
                    if {[dict get $style marker]==3} {
                        $canvas create line [expr {$x-3}] $y [expr {$x+3}] $y -fill [dict get $color rgb] -tags $pointTags
                        $canvas create line $x [expr {$y-3}] $x [expr {$y+3}] -fill [dict get $color rgb] -tags $pointTags
                    } elseif {[dict get $style marker]==2} {
                        $canvas create rectangle [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] -fill [dict get $color rgb] -outline [dict get $color rgb] -tags $pointTags
                    } else {$canvas create oval [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] -fill [dict get $color rgb] -outline [dict get $color rgb] -tags $pointTags}
                }
            }
        }
        foreach entry [native2DPresentationMarkers $object] {
            set marker [dict get $entry geometry];set markerStyle [dict get $entry style]
            set markerTags [concat direction_marker $tags]
            if {[dict exists $entry part_id]} {lappend markerTags part_direction_marker}
            set rgb [dict get [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $markerStyle color]] $background] rgb]
            $canvas create line {*}[dict get $marker tail] {*}[dict get $marker tip] -fill $rgb -width [dict get $markerStyle line_width] -tags $markerTags
            $canvas create line {*}[dict get $marker head_left] {*}[dict get $marker tip] {*}[dict get $marker head_right] -fill $rgb -width [dict get $markerStyle line_width] -tags $markerTags
        }
}
# SPDX-License-Identifier: GPL-3.0-or-later
# Renderer-neutral presentation data. No Tk item inspection or geometry math.
proc ::GX::native2DPresentationSnapshot {scene {options {}}} {
    foreach key [dict keys $options] {if {$key ni {point_budget x_label y_label x_tick_labels y_tick_labels title legend object_labels font_size include_construction_reference}} {error "Unknown Native2D snapshot option '$key'"}}
    foreach axis {x y} {
        if {[dict exists $options ${axis}_tick_labels]} {
            set labels [dict get $options ${axis}_tick_labels]
            if {[llength $labels]!=6} {error {Snapshot tick labels require exactly six values per axis}}
            foreach label $labels {if {[string length $label]>256} {error {Snapshot tick label exceeds 256 characters}}}
        }
    }
    set budget [datasetPublicationV2DictDefault $options point_budget 4096]
    if {![string is entier -strict $budget]||$budget<6||$budget>65536} {error "Snapshot point budget must be 6..65536"}
    set font [datasetPublicationV2DictDefault $options font_size 14]
    uiFieldNormalize [dict create type number min 6 max 96] $font
    set presentation [::GX::Native2D::core presentation $scene]
    set textColor [::GX::uiFieldColorToRGBA [::GX::uiFieldColorReadableText [::GX::uiFieldColorFromRGBA [dict get $presentation background]]]]
    set grid [dict get $presentation grid];set gridLines {}
    foreach line [::GX::Native2D::core render_grid $scene] {
        set kind [lindex {minor major axes} [dict get $line classification]]
        lappend gridLines [dict merge $line [dict create color [dict get $grid ${kind}_color] width [dict get $grid ${kind}_width] style [dict get $grid ${kind}_style]]]
    }
    set includeReference [uiFieldNormalize {type boolean} [datasetPublicationV2DictDefault $options include_construction_reference 0]]
    set excluded {};set objects {};set ordered {}
    foreach id [::GX::Native2D::core ids $scene] {
        if {[::GX::Native2D::core kind $scene $id] ne "group"&&[::GX::Native2D::core identity_geometry_role $scene $id] ne "regular"&&!$includeReference} {lappend excluded $id;continue}
        set label [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $options object_labels {}] $id "Object $id"]
        set object [native2DPresentationObjectSnapshot $scene $id $budget $label]
        if {$object eq {}} continue
        set style [dict get $object style]
        lappend ordered [list [dict get $style order] $object]
    }
    foreach item [lsort -integer -index 0 $ordered] {lappend objects [lindex $item 1]}
    set view [::GX::Native2D::core view $scene]
    lassign $view width height left top right bottom bounds
    lassign $bounds x0 y0 x1 y1
    set texts {}
    for {set i 0} {$i<=5} {incr i} {
        set x [expr {$x0+($x1-$x0)*$i/5.0}];set y [expr {$y0+($y1-$y0)*$i/5.0}]
        if {$x==0} {set x 0};if {$y==0} {set y 0}
        lassign [::GX::Native2D::core device $scene [list $x $y0]] px unused
        lassign [::GX::Native2D::core device $scene [list $x0 $y]] unused py
        set xt [format %.5g $x];set yt [format %.5g $y]
        if {[dict exists $options x_tick_labels]} {set xt [lindex [dict get $options x_tick_labels] $i]}
        if {[dict exists $options y_tick_labels]} {set yt [lindex [dict get $options y_tick_labels] $i]}
        lappend texts [dict create position [list $px [expr {$height-$bottom+14}]] text $xt anchor n rotation 0 font_size $font color $textColor]
        lappend texts [dict create position [list [expr {$left-7}] $py] text $yt anchor e rotation 0 font_size $font color $textColor]
    }
    foreach {key position anchor rotation} [list x_label [list [expr {($left+$width-$right)/2}] [expr {$height-12}]] s 0 y_label [list 14 [expr {($top+$height-$bottom)/2}]] center 90 title [list [expr {$width/2}] 5] n 0] {
        set text [datasetPublicationV2DictDefault $options $key ""]
        if {$text ne ""} {lappend texts [dict create position $position text $text anchor $anchor rotation $rotation font_size $font color $textColor]}
    }
    set legend [datasetPublicationV2DictDefault $options legend {}];set legendLines {};set legendObjects {}
    foreach object $objects {
        if {$legend eq "auto"||[dict get $object id] in $legend} {lappend legendObjects $object}
    }
    set y [expr {$top+12}];set limit [expr {max(0,min(28,int(($height-$top-$bottom-30)/($font+5))))}]
    set total [llength $legendObjects];set row 0
    foreach object $legendObjects {
        if {$row>=$limit} break
        set style [dict get $object style]
        lappend legendLines [dict create object_id [dict get $object id] a [list [expr {$left+10}] $y] b [list [expr {$left+35}] $y] color [dict get $style color] width [dict get $style line_width] style [dict get $style line_style]]
        lappend texts [dict create object_id [dict get $object id] position [list [expr {$left+42}] $y] text [dict get $object label] anchor w rotation 0 font_size $font color $textColor]
        incr row;set y [expr {$y+$font+5}]
    }
    if {$total>$row} {lappend texts [dict create position [list [expr {$left+42}] $y] text "+[expr {$total-$row}] more curves (see table)" anchor w rotation 0 font_size $font color $textColor]}
    return [dict create api_id NATIVE2D_PRESENTATION_SNAPSHOT_v1 api_version 1 presentation $presentation view $view point_budget $budget include_construction_reference $includeReference excluded_object_ids $excluded objects $objects grid_primitives $gridLines legend_primitives $legendLines texts $texts legend $legend]
}
proc ::GX::native2DCanvasSnapshot {canvas snapshot} {
    set background [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $snapshot presentation background]] #FFFFFF]
    $canvas configure -background [dict get $background rgb]
    $canvas delete all
    foreach line [dict get $snapshot grid_primitives] {
        set color [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $line color]] $background]
        set options [list -fill [dict get $color rgb] -width [dict get $line width] -tags construction_grid]
        if {[dict get $line style]==1} {lappend options -dash {6 3}} elseif {[dict get $line style]==2} {lappend options -dash {1 3}}
        $canvas create line {*}[dict get $line a] {*}[dict get $line b] {*}$options
    }
    foreach object [dict get $snapshot objects] {native2DCanvasDrawObject $canvas $object $background}
    foreach line [dict get $snapshot legend_primitives] {
        set color [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $line color]] $background]
        set options [list -fill [dict get $color rgb] -width [dict get $line width] -tags legend_swatch]
        if {[dict exists $line object_id]} {lappend options -tags [list legend_swatch native_legend legend_object_[dict get $line object_id]]}
        if {[dict get $line style]==1} {lappend options -dash {6 3}} elseif {[dict get $line style]==2} {lappend options -dash {1 3}}
        $canvas create line {*}[dict get $line a] {*}[dict get $line b] {*}$options
    }
    # A detached snapshot needs only a temporary Native view for actual
    # clipping; no scientific geometry or document is reconstructed here.
    native2DEnsure;set clipScene [::GX::Native2D::core scene]
    try {
        ::GX::Native2D::core view $clipScene [dict get $snapshot view]
        native2DCanvasClipItems $canvas $clipScene [$canvas find all]
    } finally {::GX::Native2D::core destroy $clipScene}
    lassign [dict get $snapshot view] width height left top right bottom bounds
    $canvas create rectangle $left $top [expr {$width-$right}] [expr {$height-$bottom}] -outline #8393A5 -tags plot_border
    foreach text [dict get $snapshot texts] {
        set rgb [dict get [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $text color]] $background] rgb]
        set tags axis_label
        if {[dict exists $text object_id]} {set tags [list legend_label native_legend legend_object_[dict get $text object_id]]}
        $canvas create text {*}[dict get $text position] -text [dict get $text text] -anchor [dict get $text anchor] -angle [dict get $text rotation] -fill $rgb -font [list Sans [expr {-round([dict get $text font_size])}]] -tags $tags
    }
}
proc ::GX::native2DLegendHit {canvas x y} {
    # Exact regions come from this renderer's actual Tk items, including font,
    # resize and clipping. Identical labels never participate in identity.
    set seen {};set x [$canvas canvasx $x];set y [$canvas canvasy $y]
    foreach item [$canvas find withtag native_legend] {
        foreach tag [$canvas gettags $item] {
            if {![regexp {^legend_object_([0-9]+)$} $tag -> id] || $id in $seen} continue
            lappend seen $id
            set bounds [$canvas bbox $tag]
            if {[llength $bounds]!=4} continue
            lassign $bounds left top right bottom
            if {$x>=$left-3 && $x<=$right+3 && $y>=$top-3 && $y<=$bottom+3} {return [dict create hit 1 object_id $id bounds $bounds]}
        }
    }
    return [dict create hit 0]
}
proc ::GX::native2DCanvasClipItems {canvas scene items} {
    lassign [::GX::Native2D::core view $scene] width height left top right bottom bounds
    set x1 [expr {$width-$right}];set y1 [expr {$height-$bottom}]
    foreach item $items {
        set type [$canvas type $item];set tags [$canvas gettags $item]
        if {$type eq "line"} {
            set xy {};foreach {x y} [$canvas coords $item] {lappend xy [list $x $y]}
            set inset [expr {[$canvas itemcget $item -width]/2.0}]
            set paths [::GX::Native2D::core interaction_clip $scene $xy $inset]
            set options {};foreach option {-fill -width -dash -capstyle -joinstyle -stipple -arrow -arrowshape -state} {lappend options $option [$canvas itemcget $item $option]}
            if {[llength $paths]==1} {
                $canvas coords $item {*}[concat {*}[lindex $paths 0]]
            } else {
                $canvas delete $item
                foreach path $paths {$canvas create line {*}[concat {*}$path] {*}$options -tags $tags}
            }
        } elseif {$type in {oval polygon text}} {
            # A marker/label crossing the viewport is omitted; never translate
            # the geometry to make it appear on the viewport boundary.
            lassign [$canvas bbox $item] a b c d
            if {$a<$left||$b<$top||$c>$x1||$d>$y1} {$canvas delete $item}
        } elseif {$type eq "rectangle"} {
            lassign [$canvas coords $item] a b c d
            set inset [expr {[$canvas itemcget $item -width]/2.0}]
            set a [expr {max($a,$left+$inset)}];set b [expr {max($b,$top+$inset)}]
            set c [expr {min($c,$x1-$inset)}];set d [expr {min($d,$y1-$inset)}]
            if {$a>$c||$b>$d} {$canvas delete $item} else {$canvas coords $item $a $b $c $d}
        }
    }
}
proc ::GX::native2DCanvasViewportClip {canvas scene {textTags {axis_label}}} {
    # Actual clipping, using CORE segment semantics. No margin masks. Preserve
    # axes labels explicitly; all other scientific presentation stays bounded.
    set items {}
    foreach item [$canvas find all] {
        set skip 0;set tags [$canvas gettags $item]
        foreach tag [concat $textTags {plot_border viewport_margin}] {if {$tag in $tags} {set skip 1;break}}
        if {!$skip} {lappend items $item}
    }
    native2DCanvasClipItems $canvas $scene $items
}

# One renderer-neutral marker list for native canvas and raster preview clients.
proc ::GX::native2DPresentationMarkers {object} {
    set result [datasetPublicationV2DictDefault $object part_markers {}]
    if {[dict exists $object marker]} {lappend result [dict create geometry [dict get $object marker] style [dict get $object marker_style]]}
    return $result
}
