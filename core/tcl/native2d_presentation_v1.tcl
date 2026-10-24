# SPDX-License-Identifier: GPL-3.0-or-later
# Renderer-neutral CORE object/scene presentation adapters.
source [file join [file dirname [info script]] native2d_axis_presentation_v1.tcl]
namespace eval ::GX::Native2DText {variable photos;if {![info exists photos]} {set photos {}}}
proc ::GX::native2DAxisPlan {lower upper pixels {font 14}} {
    foreach value [list $lower $upper $pixels] {if {![string is double -strict $value] || ![expr {abs($value)<Inf}]} {error {Axis limits and size must be finite}}}
    if {$upper<=$lower || $pixels<=0} {error {Axis planner needs an increasing range and positive size}}
    set range [expr {$upper-$lower}]
    if {![expr {$range<Inf}]} {error {Axis range exceeds finite presentation capacity}}
    set target [expr {max(1,min(30,int($pixels/max(45,5*$font))))}]
    for {set attempt 0} {$attempt<8} {incr attempt} {
        set raw [expr {$range/$target}]
        set power [expr {pow(10.0,floor(log10($raw)))}]
        if {$power==0} {set power $raw}
        set step [expr {10*$power}]
        foreach factor {1 2 2.5 5 10} {if {$factor*$power>=$raw*(1-1e-14)} {set step [expr {$factor*$power}];break}}
        set first [expr {entier(ceil($lower/$step))}];set last [expr {entier(floor($upper/$step))}]
        set digits [expr {max(0,min(16,int(ceil(-log10($step)))+1))}]
        set ticks {};set labels {};set widest 1
        set previous {}
        for {set i $first} {$i<=$last && [llength $ticks]<64} {incr i} {
            set value [expr {$i*$step}]
            if {$value<$lower || $value>$upper} continue
            if {$previous ne {} && $value==$previous} continue
            set previous $value
            if {abs($value)<$step*1e-12} {set value 0.0}
            if {$value==0} {set label 0
            } elseif {abs($value)>=1e7 || abs($value)<1e-4 || $digits>=15} {set label [format %.16g $value]
            } else {set label [format %.*f $digits $value];if {[string first . $label]>=0} {set label [string trimright [string trimright $label 0] .]}}
            if {$label in $labels} {set label [format %.17g $value]}
            lappend labels $label;set widest [expr {max($widest,[string length $label])}]
            lappend ticks [dict create value $value label $label]
        }
        set needed [expr {($widest*.62*$font+12)*max(1,[llength $ticks]-1)}]
        # Rounding the requested interval up to a nice value can leave only
        # one interior graduation, even when two readable labels fit. Refine
        # the same planner's target before accepting that sparse result.
        if {[llength $ticks]<2 && $target>=2 && $target<30 && $attempt<7} {incr target;continue}
        if {$needed<=$pixels || $target<=1} break
        set target [expr {max(1,int($target*$pixels/$needed))}]
    }
    return [dict create lower $lower upper $upper step $step ticks $ticks]
}
proc ::GX::native2DAxisPlans {scene {font 14} {descriptor __scene__}} {
    lassign [::GX::Native2D::core view $scene] width height left top right bottom bounds
    lassign $bounds x0 y0 x1 y1
    if {$descriptor eq {__scene__}} {
        # Empty/default compatibility also permits an older binary to load
        # while an isolated Native2D extension is being built.
        if {[catch {set descriptor [native2DAxisPresentation $scene]}]} {set descriptor {}}
        if {$descriptor eq {}} {set descriptor [native2DAxisPresentationDefault $scene]}
    }
    set descriptor [native2DAxisPresentationValidate $scene $descriptor]
    return [dict create x [native2DAxisPresentationPlan $scene x $x0 $x1 [expr {$width-$left-$right}] $font [datasetPublicationV2DictDefault $descriptor x {}]] y [native2DAxisPresentationPlan $scene y $y0 $y1 [expr {$height-$top-$bottom}] $font [datasetPublicationV2DictDefault $descriptor y {}]]]
}
proc ::GX::native2DAxisLabelMargin {scene {font 14}} {
    set plans [native2DAxisPlans $scene $font];set width 60
    foreach tick [dict get $plans y ticks] {
        set label [dict get $tick label]
        if {[llength [info commands font]]} {set size [font measure [list Sans [expr {-$font}]] $label]} else {set size [expr {[string length $label]*$font*.62}]}
        set width [expr {max($width,$size+20)}]
    }
    return [expr {ceil($width)}]
}
proc ::GX::native2DAxisTitleView {scene titles {font 14}} {
    # Return a requested view for the caller to apply, never mutate a scene
    # during snapshot/read operations. Bounds and calibrated aspect stay owned
    # by the existing native view service.
    set view [::GX::Native2D::core view_requested $scene]
    lassign [::GX::Native2D::core view $scene] width height left top right bottom bounds
    if {![llength [info commands font]]} {return $view}
    set xTitle [datasetPublicationV2DictDefault $titles x_label {}]
    set yTitle [datasetPublicationV2DictDefault $titles y_label {}]
    set tkfont [list Sans [expr {-$font}]]
    set lineHeight [font metrics $tkfont -linespace]
    # Account for margins added by the authoritative calibrated view without
    # changing its bounds or duplicating its aspect calculation. X and Y title
    # bands can affect each other's available span, so grow them together.
    set extraLeft [expr {$left-[lindex $view 2]}]
    set extraBottom [expr {$bottom-[lindex $view 5]}]
    set tickMargin [native2DAxisLabelMargin $scene $font]
    for {set attempt 0} {$attempt<8} {incr attempt} {
        set previous $view
        if {$xTitle ne {}} {
            set effectiveLeft [expr {[lindex $view 2]+$extraLeft}]
            set span [expr {max(1,min($width-$effectiveLeft+$right,$width+$effectiveLeft-$right)-6)}]
            set lines [llength [split [native2DCanvasTextWrap $xTitle $tkfont $span] \n]]
            # Leave a complete graduation line below the plot.
            set required [expr {($lines+1)*$lineHeight+14}]
            lset view 5 [expr {max([lindex $view 5],min($required,$height-$top-20))}]
        }
        if {$yTitle ne {}} {
            set effectiveBottom [expr {[lindex $view 5]+$extraBottom}]
            set span [expr {max(1,$height-abs($top-$effectiveBottom)-6)}]
            set lines [llength [split [native2DCanvasTextWrap $yTitle $tkfont $span] \n]]
            # After rotation, the multiline height becomes the title's width.
            # Keep the complete band separate from the existing tick labels.
            set required [expr {$tickMargin+$lines*$lineHeight+8}]
            lset view 2 [expr {max([lindex $view 2],min($required,$width-$right-20))}]
        }
        if {$view eq $previous} break
    }
    return $view
}
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
# The existing presentation owner validates per-annotation text styles. These
# are UI values; geometry and source-to-world mapping remain Native2D-owned.
proc ::GX::native2DAnnotationStyleNormalize {annotation} {
    if {[dict exists $annotation font_family]} {
        set family [string trim [dict get $annotation font_family]]
        if {$family eq {} || [string bytelength $family]>128 || [regexp {[\x00\r\n]} $family]} {error {Annotation font family requires a nonempty bounded font name}}
        dict set annotation font_family $family
    }
    if {[dict exists $annotation font_size]} {dict set annotation font_size [uiFieldNormalize {type number min 6 max 96 required 1} [dict get $annotation font_size]]}
    if {[dict exists $annotation color]} {dict set annotation color [uiFieldColor [uiFieldColorComponents [dict get $annotation color]] 1]}
    return $annotation
}
# Renderer-neutral presentation data. No Tk item inspection or geometry math.
proc ::GX::native2DPresentationSnapshot {scene {options {}}} {
    foreach key [dict keys $options] {if {$key ni {point_budget x_label y_label x_tick_labels y_tick_labels title legend object_labels font_size include_construction_reference axis_presentation axis_plans annotations axes_visible}} {error "Unknown Native2D snapshot option '$key'"}}
    set axesVisible [uiFieldNormalize {type boolean} [datasetPublicationV2DictDefault $options axes_visible 1]]
    set annotations [datasetPublicationV2DictDefault $options annotations {}]
    if {[llength $annotations]>512 || [string bytelength $annotations]>131072} {error {Native2D annotations exceed bounded presentation contract}}
    set normalizedAnnotations {}
    foreach annotation $annotations {
        foreach key [dict keys $annotation] {if {$key ni {point text anchor id font_family font_size color}} {error {Unknown Native2D annotation field}}}
        if {[dict exists $annotation id] && ![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,63}$} [dict get $annotation id]]} {error {Invalid stable Native2D annotation identifier}}
        if {[llength [dict get $annotation point]]!=2 || [string bytelength [dict get $annotation text]]>256 || [string first \x00 [dict get $annotation text]]>=0} {error {Invalid bounded Native2D annotation}}
        foreach coordinate [dict get $annotation point] {uiFieldNormalize {type number} $coordinate}
        if {[datasetPublicationV2DictDefault $annotation anchor sw] ni {n ne e se s sw w nw center}} {error {Invalid Native2D annotation anchor}}
        lappend normalizedAnnotations [native2DAnnotationStyleNormalize $annotation]
    }
    set annotations $normalizedAnnotations
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
    set descriptor [datasetPublicationV2DictDefault $options axis_presentation __scene__]
    if {$descriptor eq {__scene__}} {if {[catch {set descriptor [native2DAxisPresentation $scene]}]} {set descriptor {}};if {$descriptor eq {}} {set descriptor [native2DAxisPresentationDefault $scene]}}
    set descriptor [native2DAxisPresentationValidate $scene $descriptor]
    set texts {};set plans [native2DAxisPlans $scene $font $descriptor]
    if {[dict exists $options axis_plans]} {
        set supplied [dict get $options axis_plans]
        if {[lsort [dict keys $supplied]] ne {x y}} {error {Axis plans require exactly X and Y}}
        foreach axis {x y} lower [list $x0 $y0] upper [list $x1 $y1] {
            set plan [dict get $supplied $axis]
            if {[dict get $plan lower]!=$lower || [dict get $plan upper]!=$upper || [llength [dict get $plan ticks]]>64} {error {Axis plan is stale or exceeds64 ticks}}
            set seen {}
            foreach tick [dict get $plan ticks] {
                set value [uiFieldNormalize {type number} [dict get $tick value]]
                if {$value<$lower || $value>$upper || [dict exists $seen $value] || [string length [dict get $tick label]]>256} {error {Invalid bounded axis tick position or label}}
                dict set seen $value 1
            }
            dict set plans $axis $plan
        }
    }
    # Construction references retain their authored grid. Scientific axes use
    # the same numeric positions for both labels and grid primitives.
    if {!$includeReference && ![dict exists $options x_tick_labels] && ![dict exists $options y_tick_labels]} {set gridLines {}}
    foreach axis {x y} {
        if {!$axesVisible} continue
        set ticks [dict get $plans $axis ticks]
        if {[dict exists $options ${axis}_tick_labels]} {
            set ticks {};set i 0
            foreach label [dict get $options ${axis}_tick_labels] {
                set value [expr {$axis eq "x"?$x0+($x1-$x0)*$i/5.0:$y0+($y1-$y0)*$i/5.0}]
                lappend ticks [dict create value $value label $label];incr i
            }
        }
        foreach tick $ticks {
            set value [dict get $tick value]
            if {$axis eq "x"} {
                lassign [::GX::Native2D::core device $scene [list $value $y0]] px unused
                set a [list $px $top];set b [list $px [expr {$height-$bottom}]]
                set position [list $px [expr {$height-$bottom+4}]];set anchor n
                set half [expr {[string length [dict get $tick label]]*$font*.31+4}]
                if {$px-$half<2} {set anchor nw}
                if {$px+$half>$width-2} {set anchor ne}
            } else {
                lassign [::GX::Native2D::core device $scene [list $x0 $value]] unused py
                set a [list $left $py];set b [list [expr {$width-$right}] $py]
                set position [list [expr {$left-7}] $py];set anchor e
            }
            lappend texts [dict create axis $axis value $value position $position text [dict get $tick label] anchor $anchor rotation 0 font_size $font color $textColor]
            if {!$includeReference && ![dict exists $options x_tick_labels] && ![dict exists $options y_tick_labels] && [dict get $grid visible]} {
                lappend gridLines [dict create axis $axis value $value a $a b $b classification 1 color [dict get $grid major_color] width [dict get $grid major_width] style [dict get $grid major_style]]
            }
        }
    }
    foreach {key position anchor rotation} [list x_label [list [expr {($left+$width-$right)/2}] [expr {$height-3}]] s 0 y_label [list 14 [expr {($top+$height-$bottom)/2}]] center 90 title [list [expr {$width/2}] 5] n 0] {
        set text [datasetPublicationV2DictDefault $options $key ""]
        if {![dict exists $options $key] && $key in {x_label y_label}} {
            set axis [string index $key 0];set settings [datasetPublicationV2DictDefault $descriptor $axis {}]
            set text [datasetPublicationV2DictDefault $settings title {}]
            set unit [dict get [native2DAxisCoordinatePlan $scene $axis $settings] unit]
            if {$unit ne {}} {if {$text ne {}} {append text " ($unit)"} else {set text $unit}}
        }
        if {$text ne ""} {
            set item [dict create position $position text $text anchor $anchor rotation $rotation font_size $font color $textColor]
            # Wrap presentation titles using their actual available span. The
            # canonical name/unit string and all scene coordinates stay intact.
            lassign $position px py
            if {$key eq {x_label}} {
                set span [expr {2*min($px,$width-$px)-6}]
                dict set item wrap_width [expr {max(1,int($span))}]
            } elseif {$key eq {y_label}} {
                set span [expr {max(1,int(2*min($py,$height-$py)-6))}]
                dict set item wrap_width $span
                if {[llength [info commands font]]} {
                    set tkfont [list Sans [expr {-$font}]]
                    set lines [llength [split [native2DCanvasTextWrap $text $tkfont $span] \n]]
                    set band [expr {$lines*[font metrics $tkfont -linespace]+4}]
                    dict set item position [list [expr {max(14,$band/2.0+3)}] $py]
                }
            }
            lappend texts $item
        }
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
    foreach annotation $annotations {
        set position [::GX::Native2D::core device $scene [dict get $annotation point]]
        lassign $position px py
        if {$px<$left || $px>$width-$right || $py<$top || $py>$height-$bottom} continue
        set text [dict create position $position text [dict get $annotation text] anchor [datasetPublicationV2DictDefault $annotation anchor sw] rotation 0 font_size $font color $textColor role annotation]
        foreach key {font_family font_size} {if {[dict exists $annotation $key]} {dict set text $key [dict get $annotation $key]}}
        if {[dict exists $annotation color]} {dict set text color [uiFieldColorToRGBA [dict get $annotation color]]}
        if {[dict exists $annotation id]} {dict set text annotation_id [dict get $annotation id]}
        lappend texts $text
    }
    return [dict create api_id NATIVE2D_PRESENTATION_SNAPSHOT_v1 api_version 1 presentation $presentation view $view axis_plans $plans axis_presentation $descriptor axes_visible $axesVisible point_budget $budget include_construction_reference $includeReference excluded_object_ids $excluded objects $objects grid_primitives $gridLines legend_primitives $legendLines texts $texts legend $legend]
}
proc ::GX::native2DCanvasSnapshot {canvas snapshot} {
    set background [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $snapshot presentation background]] #FFFFFF]
    $canvas configure -background [dict get $background rgb]
    $canvas delete all
    native2DCanvasTextSweep $canvas
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
        native2DCanvasTextDraw $canvas $text $background
    }
}
proc ::GX::native2DCanvasTextDispose {canvas actual} {
    if {$actual ne $canvas} return
    variable ::GX::Native2DText::photos
    if {![dict exists $photos $canvas]} return
    dict for {photo item} [dict get $photos $canvas] {catch {image delete $photo}}
    dict unset photos $canvas
}
proc ::GX::native2DCanvasTextSweep {canvas} {
    variable ::GX::Native2DText::photos
    if {![dict exists $photos $canvas]} return
    dict for {photo item} [dict get $photos $canvas] {
        if {![winfo exists $canvas] || [$canvas type $item] eq {}} {
            catch {image delete $photo};dict unset photos $canvas $photo
        }
    }
}
proc ::GX::native2DCanvasTextDraw {canvas text background} {
    native2DCanvasTextSweep $canvas
    set rgb [dict get [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $text color]] $background] rgb]
    set tags axis_label
    if {[dict exists $text object_id]} {set tags [list legend_label native_legend legend_object_[dict get $text object_id]]}
    if {[dict exists $text annotation_id]} {set tags [list native_annotation native_annotation_[dict get $text annotation_id]]}
    set font [list [datasetPublicationV2DictDefault $text font_family Sans] [expr {-round([dict get $text font_size])}]]
    set wrap [datasetPublicationV2DictDefault $text wrap_width 0]
    if {[lindex [dict get $text color] 3]<1} {
        native2DEnsure
        if {![llength [info commands ::gx::native2d::text_photo]]} {error {Native2D text alpha requires the matching precompiled device adapter}}
        set photo [image create photo]
        try {
            set displayText [dict get $text text]
            if {$wrap>0} {set displayText [native2DCanvasTextWrap $displayText $font $wrap]}
            set receipt [::gx::native2d::text_photo $photo $font $displayText [dict get $text anchor] [dict get $text rotation] [dict get $text color]]
            lassign [dict get $text position] x y;lassign [dict get $receipt offset] dx dy
            set item [$canvas create image [expr {$x+$dx}] [expr {$y+$dy}] -anchor nw -image $photo -tags $tags]
        } on error {message options} {image delete $photo;return -options $options $message}
        variable ::GX::Native2DText::photos
        if {![dict exists $photos $canvas]} {bind $canvas <Destroy> +[list ::GX::native2DCanvasTextDispose $canvas %W]}
        dict set photos $canvas $photo $item
        return $item
    }
    return [$canvas create text {*}[dict get $text position] -text [dict get $text text] -width $wrap -justify [expr {$wrap>0?{center}:{left}}] -anchor [dict get $text anchor] -angle [dict get $text rotation] -fill $rgb -font $font -tags $tags]
}
proc ::GX::native2DCanvasTextWrap {text font width} {
    # The precompiled alpha-text adapter accepts explicit line breaks. Measure
    # with the same Tk font, retaining every original character and paragraph.
    set lines {}
    foreach paragraph [split $text \n] {
        while {[font measure $font $paragraph]>$width && [string length $paragraph]>1} {
            set low 1;set high [string length $paragraph]
            while {$low<$high} {
                set mid [expr {($low+$high+1)/2}]
                if {[font measure $font [string range $paragraph 0 [expr {$mid-1}]]]<=$width} {set low $mid} else {set high [expr {$mid-1}]}
            }
            set count $low
            set space [string last { } [string range $paragraph 0 [expr {$count-1}]]]
            if {$space>0} {set count [expr {$space+1}]}
            lappend lines [string range $paragraph 0 [expr {$count-1}]]
            set paragraph [string range $paragraph $count end]
        }
        lappend lines $paragraph
    }
    return [join $lines \n]
}
proc ::GX::native2DAnnotationHit {canvas x y} {
    # Identity and hit regions come from actual rendered text, including font
    # metrics and resize. Text content is never an identity or geometry oracle.
    set x [$canvas canvasx $x];set y [$canvas canvasy $y]
    foreach item [lreverse [$canvas find withtag native_annotation]] {
        set bounds [$canvas bbox $item]
        if {[llength $bounds]!=4} continue
        lassign $bounds left top right bottom
        if {$x<$left || $x>$right || $y<$top || $y>$bottom} continue
        foreach tag [$canvas gettags $item] {
            if {[regexp {^native_annotation_([A-Za-z][A-Za-z0-9_.-]{0,63})$} $tag -> id]} {return [dict create hit 1 annotation_id $id bounds $bounds]}
        }
    }
    return [dict create hit 0]
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
    # Batch actual Tk bounds/coordinates in CORE, reusing gx2d segment semantics.
    # Managed alpha-text images retain their existing photo lifecycle owner.
    set photos [datasetPublicationV2DictDefault $::GX::Native2DText::photos $canvas {}]
    ::GX::Native2D::core canvas_clip $scene $canvas {} $photos $items
    native2DCanvasTextSweep $canvas
}
proc ::GX::native2DCanvasViewportClip {canvas scene {textTags {axis_label}}} {
    set photos [datasetPublicationV2DictDefault $::GX::Native2DText::photos $canvas {}]
    ::GX::Native2D::core canvas_clip $scene $canvas [concat $textTags {axis_graduation plot_border viewport_margin native_batch_item native_grid_presenter native_sprite_scene}] $photos
    native2DCanvasTextSweep $canvas
}

# One renderer-neutral marker list for native canvas and raster preview clients.
proc ::GX::native2DPresentationMarkers {object} {
    set result [datasetPublicationV2DictDefault $object part_markers {}]
    if {[dict exists $object marker]} {lappend result [dict create geometry [dict get $object marker] style [dict get $object marker_style]]}
    return $result
}
