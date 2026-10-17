# SPDX-License-Identifier: GPL-3.0-or-later
# View-scoped axis metadata; scene geometry and Dataset units are never edited.
proc ::GX::native2DAxisPresentationValidate {scene descriptor} {
    foreach axis [dict keys $descriptor] {if {$axis ni {x y}} {error "Unknown presentation axis '$axis'"}}
    set normalized {}
    dict for {axis settings} $descriptor {
        foreach key [dict keys $settings] {if {$key ni {title unit_label ticks context}} {error "Unknown axis presentation field '$key'"}}
        foreach key {title unit_label} {
            if {[dict exists $settings $key] && [string length [dict get $settings $key]]>256} {error {Axis title/unit label exceeds256 characters}}
        }
        set ticks [dict merge {placement auto step auto format auto} [datasetPublicationV2DictDefault $settings ticks {}]]
        foreach key [dict keys $ticks] {if {$key ni {placement step format precision}} {error "Unknown axis tick field '$key'"}}
        if {[dict get $ticks placement] ni {auto integer}} {error {Axis placement must be auto or integer}}
        set format [dict get $ticks format]
        if {$format ni {auto integer fixed_decimal significant_digits}} {error {Unsupported axis number format}}
        if {$format eq {integer} && [dict get $ticks placement] eq {auto}} {dict set ticks placement integer}
        if {$format in {fixed_decimal significant_digits}} {
            set precision [datasetPublicationV2DictDefault $ticks precision {}]
            if {![string is integer -strict $precision] || $precision<($format eq {significant_digits}) || $precision>15} {error {Axis precision must be0..15 decimals or1..15 significant digits}}
        } elseif {[dict exists $ticks precision]} {error {Axis precision applies only to fixed_decimal or significant_digits}}
        set step [dict get $ticks step]
        if {$step ne {auto}} {
            if {![string is double -strict $step] || ![expr {$step>0 && $step<Inf}]} {error {Explicit axis interval must be positive and finite}}
            if {[dict get $ticks placement] eq {integer} && $step!=floor($step)} {error {Integer axis placement requires an integral interval}}
        }
        dict set settings ticks $ticks
        # Mapping is checked now and on redraw, so an image transform cannot
        # leave a trusted pixel/physical label attached to an unrelated frame.
        native2DAxisCoordinatePlan $scene $axis $settings
        if {[dict exists $settings context image_id]} {
            set context [dict get $settings context]
            set actual [::GX::Native2D::core image_get $scene [dict get $context image_id]]
            dict unset context image_id;dict set context image_resource_id [dict get $actual resource_id]
            dict set settings context $context
            native2DAxisCoordinatePlan $scene $axis $settings
        }
        dict set normalized $axis $settings
    }
    return $normalized
}
proc ::GX::native2DAxisImage {scene context} {
    if {[dict exists $context image_id]} {return [dict get $context image_id]}
    set identity [dict get $context image_resource_id];set matches {}
    foreach id [::GX::Native2D::core ids $scene] {
        set image [::GX::Native2D::core image_get $scene $id]
        if {$image ne {} && [dict get $image resource_id] eq $identity} {lappend matches $id}
    }
    if {[llength $matches]!=1} {error {Axis image resource is missing or ambiguous; explicitly rebind its presentation}}
    return [lindex $matches 0]
}
proc ::GX::native2DAxisCoordinatePlan {scene axis settings} {
    set context [datasetPublicationV2DictDefault $settings context {kind world}]
    set kind [datasetPublicationV2DictDefault $context kind world]
    set label [datasetPublicationV2DictDefault $settings unit_label {}]
    set scale 1.0;set offset 0.0;set unit {}
    switch -- $kind {
        world {
            if {[dict keys $context] ne {kind}} {error {World axis context accepts only kind}}
            if {$label ne {}} {error {A unit label requires an explicit verified coordinate context}}
        }
        conversion {
            foreach key [dict keys $context] {if {$key ni {kind source_unit target_unit}} {error "Unknown unit context '$key'"}}
            set source [dict get $context source_unit];set unit [dict get $context target_unit]
            set plan [unitRegistryAffinePlan $source $unit]
            if {![dict get $plan affine]} {error {Axis display conversion requires a validated affine Unit Registry plan}}
            set scale [dict get $plan scale];set offset [dict get $plan offset]
        }
        image_pixel - image_physical {
            foreach key [dict keys $context] {if {$key ni {kind image_id image_resource_id target_unit}} {error "Unknown image-axis context '$key'"}}
            set image [native2DAxisImage $scene $context]
            set actual [::GX::Native2D::core image_get $scene $image]
            if {$actual eq {}} {error {Axis context does not identify a native reference image}}
            if {$kind eq {image_pixel}} {
                if {[dict exists $context target_unit]} {error {Pixel coordinates use px; physical units require calibrated image context}}
                set p0 [::GX::Native2D::core image_map $scene $image {0 0} 1]
                set px [::GX::Native2D::core image_map $scene $image {1 0} 1]
                set py [::GX::Native2D::core image_map $scene $image {0 1} 1]
                set dx [expr {[lindex $px 0]-[lindex $p0 0]}];set dy [expr {[lindex $py 1]-[lindex $p0 1]}]
                set xy [expr {[lindex $py 0]-[lindex $p0 0]}];set yx [expr {[lindex $px 1]-[lindex $p0 1]}]
                if {abs($xy)>1e-10*max(abs($dx),1e-300) || abs($yx)>1e-10*max(abs($dy),1e-300)} {error {Original pixel axis labels require an axis-aligned image mapping}}
                set scale [expr {$axis eq {x}?$dx:$dy}];set offset [lindex $p0 [expr {$axis eq {x}?0:1}]];set unit px
            } else {
                if {![dict get $actual calibrated]} {error {Physical image axis labels require actual native image calibration}}
                set unit [datasetPublicationV2DictDefault $context target_unit [dict get $actual length_unit]]
                set plan [unitRegistryAffinePlan [dict get $actual length_unit] $unit]
                if {![dict get $plan affine] || [dict get $plan offset]!=0} {error {Calibrated image axes require a proportional physical-unit conversion}}
                set scale [dict get $plan scale];set offset 0.0
            }
        }
        default {error "Unsupported axis coordinate context '$kind'"}
    }
    if {![expr {abs($scale)<Inf && $scale!=0 && abs($offset)<Inf}]} {error {Axis coordinate mapping must be finite and invertible}}
    if {$label ne {} && $label ne $unit} {error {Axis unit label disagrees with its verified coordinate mapping}}
    return [dict create kind $kind scale $scale offset $offset unit $unit]
}
proc ::GX::native2DAxisPresentationRescale {scene descriptor factor} {
    if {![string is double -strict $factor] || ![expr {$factor>0 && $factor<Inf}]} {error {View rescale factor must be finite and positive}}
    set result [native2DAxisPresentationValidate $scene $descriptor]
    dict for {axis settings} $result {
        set context [datasetPublicationV2DictDefault $settings context {kind world}]
        if {$factor!=1 && [dict get $context kind] ne {world}} {error {Rescaled unit/pixel presentation requires explicit revalidation against its new coordinate context}}
        set step [dict get $settings ticks step]
        if {$step ne {auto}} {dict set settings ticks step [expr {$step*$factor}]}
        dict set result $axis $settings
    }
    return [native2DAxisPresentationValidate $scene $result]
}
proc ::GX::native2DAxisPresentation {scene {descriptor __query__}} {
    if {$descriptor eq {__query__}} {return [::GX::Native2D::core axis_presentation $scene]}
    return [::GX::Native2D::core axis_presentation $scene $descriptor]
}
proc ::GX::native2DAxisPresentationDefault {scene} {
    # A sole visible uncalibrated image is unambiguous. Mixed geometry keeps
    # ordinary world axes unless the caller explicitly supplies a context.
    set ids [::GX::Native2D::core ids $scene]
    if {[llength $ids]!=1} {return {}}
    set image [::GX::Native2D::core image_get $scene [lindex $ids 0]]
    if {$image eq {} || ![dict get $image visible] || [dict get $image calibrated]} {return {}}
    set settings [dict create context [dict create kind image_pixel image_id [lindex $ids 0]] ticks {placement integer format integer}]
    if {[catch {set descriptor [native2DAxisPresentationValidate $scene [dict create x $settings y $settings]]}]} {return {}}
    return $descriptor
}
proc ::GX::native2DAxisPresentationPlan {scene axis lower upper pixels font settings} {
    if {$settings eq {}} {return [native2DAxisPlan $lower $upper $pixels $font]}
    set mapping [native2DAxisCoordinatePlan $scene $axis $settings]
    set scale [dict get $mapping scale];set offset [dict get $mapping offset]
    set a [expr {$lower*$scale+$offset}];set b [expr {$upper*$scale+$offset}]
    set lo [expr {min($a,$b)}];set hi [expr {max($a,$b)}]
    set plan [native2DAxisPlan $lo $hi $pixels $font]
    set policy [dict get $settings ticks];set explicit [expr {[dict get $policy step] ne {auto}}]
    set step [expr {$explicit?[dict get $policy step]:[dict get $plan step]}]
    set quantum 0.0;set format [dict get $policy format]
    if {[dict get $policy placement] eq {integer}} {set quantum 1.0}
    if {$format eq {fixed_decimal}} {set quantum [expr {pow(10.0,-[dict get $policy precision])}]}
    if {$format eq {significant_digits}} {set magnitude [expr {max(abs($lo),abs($hi))}];if {$magnitude>0} {set quantum [expr {pow(10.0,floor(log10($magnitude))-[dict get $policy precision]+1)}]}}
    if {$quantum>0} {
        if {$explicit && (abs($step/$quantum-round($step/$quantum))>1e-9 || $step<$quantum)} {error {Explicit interval is incompatible with the requested numerical precision}}
        if {!$explicit} {
            set step [expr {max($step,$quantum)}]
            if {abs($step/$quantum-round($step/$quantum))>1e-9} {set step [expr {pow(10.0,ceil(log10($step)))}]}
        }
    }
    set first [expr {entier(ceil($lo/$step))}];set last [expr {entier(floor($hi/$step))}]
    if {$explicit} {
        set widest [expr {max([string length [format %.16g $lo]],[string length [format %.16g $hi]])}]
        set countLimit [expr {max(1,min(64,int($pixels/max(45,$widest*.62*$font+12))))}]
        set multiple [expr {max(1,entier(ceil(($last-$first+1)/double($countLimit))))}]
        set step [expr {$step*$multiple}]
        set first [expr {entier(ceil($lo/$step))}];set last [expr {entier(floor($hi/$step))}]
    }
    set ticks {};set labels {}
    for {set n $first} {$n<=$last} {incr n} {
        set display [expr {$n*$step}];if {abs($display)<$step*1e-12} {set display 0.0}
        set world [expr {($display-$offset)/$scale}]
        if {$world<$lower || $world>$upper} continue
        switch -- $format {
            integer {set label [format %.0f $display]}
            fixed_decimal {set label [format %.*f [dict get $policy precision] $display]}
            significant_digits {set label [format %.*g [dict get $policy precision] $display]}
            default {
                set decimals [expr {max(0,min(16,int(ceil(-log10($step)))+1))}]
                if {$display==0} {set label 0
                } elseif {abs($display)>=1e7 || abs($display)<1e-4 || $decimals>=15} {
                    set significant [expr {max(1,min(17,int(floor(log10(abs($display)))-floor(log10($step)))+3))}]
                    set label [format %.*g $significant $display]
                } else {
                    set label [format %.*f $decimals $display]
                    if {[string first . $label]>=0} {set label [string trimright [string trimright $label 0] .]}
                }
            }
        }
        if {$label in $labels} {error {Axis precision produces duplicate tick labels}}
        lappend labels $label;lappend ticks [dict create value $world display_value $display label $label]
    }
    return [dict create lower $lower upper $upper step $step requested_step [dict get $policy step] ticks $ticks coordinate_plan $mapping display_limits [list $lo $hi]]
}
