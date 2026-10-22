# SPDX-License-Identifier: GPL-3.0-or-later
# One process owns one Native2D command/engine implementation for every viewer.
proc ::GX::native2DEnsure {} {
    variable scriptDir
    if {[llength [info commands ::GX::Native2D::core]]} {return [native2DRequireAdapter]}
    set libraries {}
    if {[info exists ::env(GX2D_TCL_LIBRARY)]} {lappend libraries $::env(GX2D_TCL_LIBRARY)}
    lappend libraries [file join $scriptDir core native2d bin gx2dtcl[info sharedlibextension]]
    foreach library $libraries {
        if {[file isfile $library]} {load $library Gx2dtcl;return [native2DRequireAdapter]}
    }
    error "The shared Native2D CORE adapter is missing from this GX-TXT installation"
}
proc ::GX::native2DRequireAdapter {} {
    if {[catch {set info [::GX::Native2D::core api_info]} reason]} {
        error "The loaded Native2D adapter does not support this framework; restart with the installed shared CORE adapter. $reason"
    }
    foreach capability {retained_spline_tangents calibrated_reference_images scene_preview_views atomic_symmetric_construction retained_component_solver graphical_dimensions driven_dimensions local_sketch_rank relationship_hit_regions canvas_construction native_viewport_clip retained_control_descriptors epoch_checked_references selection_constraint_compatibility atomic_constraint_driving endpoint_frame point_frame point_distance bridge_c0_c1 bounded_spline_range native_spline_object selection_replace selection_state selection_paged device_point_hit bounded_compare drag_active aspect requested_view direction_marker grid background polar display_sample numeric_pack numeric_companions numeric_gaps binary_points bounded_points object_sample render_lod curve_render object_style fit_selected} {
        if {$capability ni [dict get $info capabilities]} {error "The loaded Native2D adapter lacks required capability '$capability'"}
    }
    return $info
}
proc ::GX::native2DLoadNumericRows {scene file {columns 2} {xColumn 0} {yColumn 1} {progress ""}} {
    # Explicit Numeric-owned temporary output; no Dataset/provider path lookup.
    set channel [open $file rb];set object 0;set rows 0
    try {
        while {1} {
            set bytes [read $channel [expr {65536*$columns*8}]]
            if {$bytes eq ""} break
            set object [::GX::Native2D::core append_binary_xy $scene $object $bytes $columns $xColumn $yColumn]
            incr rows [expr {[string length $bytes]/($columns*8)}]
            if {$progress ne ""} {curveSourceCooperativeBoundary $progress [dict create stage native_geometry completed_rows $rows total_rows [expr {[file size $file]/($columns*8)}]]}
        }
        if {$object==0} {error "Numeric output contains no curve rows"}
        return $object
    } on error {message options} {
        if {$object!=0} {::GX::Native2D::core delete $scene $object}
        return -options $options $message
    } finally {close $channel}
}
proc ::GX::native2DLoadNumericRowsWithGaps {scene xyFile gapFile {progress ""}} {
    # Both files are explicit, newly owned CURVE_SOURCE_NUMERIC_INPUT artifacts.
    set xy [open $xyFile rb];set gaps "";set object 0;set rows 0
    try {
        set gaps [open $gapFile rb]
        while {1} {
            set bytes [read $xy 1048576]
            if {$bytes eq ""} break
            if {[string length $bytes]%16} {error "Incomplete Numeric XY input"}
            set mask [read $gaps [expr {[string length $bytes]/16}]]
            set object [::GX::Native2D::core append_binary_xy_gaps $scene $object $bytes $mask]
            incr rows [expr {[string length $bytes]/16}]
            if {$progress ne ""} {curveSourceCooperativeBoundary $progress [dict create stage native_geometry completed_rows $rows total_rows [expr {[file size $xyFile]/16}]]}
        }
        if {$object==0||[read $gaps 1] ne ""} {error "Numeric XY/gap input shape mismatch"}
        return $object
    } on error {message options} {
        if {$object!=0} {::GX::Native2D::core delete $scene $object}
        return -options $options $message
    } finally {close $xy;if {$gaps ne ""} {close $gaps}}
}

proc ::GX::_native2DGridPresentation {presentation} {
    if {$presentation eq {}} {return {}}
    foreach key [dict keys $presentation] {if {$key ni {x y guard note polar_compatible}} {error "Unknown grid presentation field '$key'"}}
    foreach axis {x y} {
        set plan [dict get $presentation $axis]
        foreach key {scale offset inverse_scale inverse_offset unit} {if {![dict exists $plan $key]} {error "Grid axis $axis requires '$key'"}}
        foreach key {scale offset inverse_scale inverse_offset} {dict set plan $key [uiFieldNormalize {type number} [dict get $plan $key]]}
        if {[dict get $plan scale]==0||[dict get $plan inverse_scale]==0} {error {Grid presentation scales must be nonzero}}
        if {[string length [dict get $plan unit]]>256} {error {Grid unit label is too long}}
        dict set presentation $axis $plan
    }
    dict set presentation polar_compatible [uiFieldNormalize {type boolean} [datasetPublicationV2DictDefault $presentation polar_compatible 0]]
    return $presentation
}
proc ::GX::_native2DGridPresentedValue {value plan inverse displacement} {
    set prefix [expr {$inverse?"inverse_":""}]
    set scale [dict get $plan ${prefix}scale];set offset [dict get $plan ${prefix}offset]
    if {$displacement} {set scale [expr {abs($scale)}];set offset 0.0}
    if {$scale==1&&$offset==0} {return $value}
    return [uiFieldNormalize {type number} [expr {$scale*$value+$offset}]]
}
proc ::GX::_native2DGridPresentationValues {values presentation inverse} {
    if {$presentation eq {}} {return $values}
    foreach axis {x y} {
        set plan [dict get $presentation $axis]
        foreach key [list origin_$axis polar_origin_$axis spacing_$axis] {
            dict set values $key [_native2DGridPresentedValue [dict get $values $key] $plan $inverse [string match spacing_* $key]]
        }
    }
    if {[dict get $presentation polar_compatible]} {
        foreach key {radius_min radius_max radial_spacing} {dict set values $key [_native2DGridPresentedValue [dict get $values $key] [dict get $presentation x] $inverse 1]}
    }
    return $values
}
proc ::GX::_native2DGridPresentationGuard {presentation} {
    set guard [datasetPublicationV2DictDefault $presentation guard {}]
    if {$guard ne {}} {uplevel #0 $guard}
}
proc ::GX::native2DGridPresentationApply {scene changed presentation values} {
    set presentation [_native2DGridPresentation $presentation]
    _native2DGridPresentationGuard $presentation
    if {$presentation ne {}&&![dict get $presentation polar_compatible]&&[dict get $values coordinate_mode] ne "cartesian"} {error {Polar readout requires compatible axis presentation}}
    native2DGridApply $scene $changed [_native2DGridPresentationValues $values $presentation 1]
}
proc ::GX::native2DGridForm {window scene changed {parent ""} {presentation {}}} {
    set presentation [_native2DGridPresentation $presentation]
    _native2DGridPresentationGuard $presentation
    set grid [::GX::Native2D::core grid $scene]
    set fields {};set values {}
    foreach {key label} {visible {Show grid} snap_enabled {Snap to grid} major_visible {Major lines} minor_visible {Minor lines} axes_visible {Origin axes}} {
        dict set fields $key [dict create type boolean label $label]
        dict set values $key [dict get $grid $key]
    }
    foreach {key label value} [list origin_x "Origin X" [lindex [dict get $grid origin] 0] origin_y "Origin Y" [lindex [dict get $grid origin] 1] spacing_x "Spacing X" [dict get $grid spacing_x] spacing_y "Spacing Y" [dict get $grid spacing_y] rotation "Grid rotation (degrees)" [expr {[dict get $grid angle]*180/acos(-1)}] major_interval "Major interval" [dict get $grid major_interval]] {
        set descriptor [dict create type number label $label default $value]
        if {$key in {spacing_x spacing_y}} {dict set descriptor min 0}
        if {$key eq "major_interval"} {dict set descriptor type integer;dict set descriptor min 1;dict set descriptor max 1000000}
        dict set fields $key $descriptor;dict set values $key $value
    }
    foreach kind {major minor axes} {
        dict set fields ${kind}_color [dict create type color alpha 1 label "[string totitle $kind] color / opacity"]
        dict set values ${kind}_color [::GX::uiFieldColorFromRGBA [dict get $grid ${kind}_color]]
        dict set fields ${kind}_width [dict create type number min .1 max 64 label "[string totitle $kind] width (px)"]
        dict set values ${kind}_width [dict get $grid ${kind}_width]
        dict set fields ${kind}_style [dict create type choice values {Solid Dash Dot} label "[string totitle $kind] line style"]
        dict set values ${kind}_style [lindex {Solid Dash Dot} [dict get $grid ${kind}_style]]
    }
    dict set fields background [dict create type color alpha 1 label "Background color / opacity" default #FFFFFF]
    dict set values background [::GX::uiFieldColorFromRGBA [::GX::Native2D::core background $scene]]
    dict set fields coordinate_mode [dict create type choice values {cartesian polar} label "Coordinate presentation (Polar is experimental)" default cartesian]
    dict set values coordinate_mode [::GX::Native2D::core coordinate_mode $scene]
    set polar [::GX::Native2D::core polar $scene]
    foreach {key label value} [list polar_origin_x "Polar origin X" [lindex [dict get $polar origin] 0] polar_origin_y "Polar origin Y" [lindex [dict get $polar origin] 1] theta_zero "Polar theta-zero direction (degrees)" [expr {[dict get $polar theta_zero]*180/acos(-1)}] radius_min "Polar minimum radius" [dict get $polar radius_min] radius_max "Polar maximum radius" [dict get $polar radius_max] angle_min "Polar start angle (degrees)" [expr {[dict get $polar angle_min]*180/acos(-1)}] angle_span "Polar angular span (degrees)" [expr {[dict get $polar angle_span]*180/acos(-1)}] radial_spacing "Polar radial spacing" [dict get $polar radial_spacing] angular_spacing "Polar angular spacing (degrees)" [expr {[dict get $polar angular_spacing]*180/acos(-1)}]] {
        dict set fields $key [dict create type number label $label]
        dict set values $key $value
    }
    foreach {key label} {clockwise {Polar clockwise angles} degrees {Polar readout in degrees}} {
        dict set fields $key [dict create type boolean label $label]
        dict set values $key [dict get $polar $key]
    }
    foreach key {radial_major_interval angular_major_interval} {
        dict set fields $key [dict create type integer min 1 max 1000000 label "Polar [string map {_ { }} $key]"]
        dict set values $key [dict get $polar $key]
    }
    dict for {key descriptor} $fields {
        if {$key in {visible snap_enabled major_visible minor_visible axes_visible}} {set section visibility
        } elseif {$key in {origin_x origin_y spacing_x spacing_y rotation major_interval}} {set section grid
        } elseif {[string match axes_* $key]} {set section axes
        } elseif {[string match major_* $key]||[string match minor_* $key]} {set section lines
        } elseif {$key eq "background"} {set section background
        } else {set section polar}
        dict set fields $key section $section
    }
    set values [_native2DGridPresentationValues $values $presentation 0]
    if {$presentation ne {}} {
        foreach axis {x y} {
            foreach key [list origin_$axis spacing_$axis polar_origin_$axis] {
                dict set fields $key label "[dict get $fields $key label] ([dict get $presentation $axis unit])"
                if {[dict exists $fields $key default]} {dict set fields $key default [dict get $values $key]}
            }
        }
        if {[dict get $presentation polar_compatible]} {
            foreach key {radius_min radius_max radial_spacing} {dict set fields $key label "[dict get $fields $key label] ([dict get $presentation x unit])"}
        } else {
            dict set fields coordinate_mode values {cartesian};dict set values coordinate_mode cartesian
        }
        dict set fields rotation label {Grid rotation in geometry coordinates (degrees)}
    }
    set d [::GX::uiFieldFormCreate $window "Construction grid / view" $fields $values [list ::GX::native2DGridPresentationApply $scene $changed $presentation] $parent {visibility Visibility grid Grid lines Lines axes Axes background Background polar {Polar / advanced}}]
    if {$presentation ne {}&&![dict get $presentation polar_compatible]} {uiFieldFormSectionEnabled $d polar 0}
    set note [datasetPublicationV2DictDefault $presentation note {}]
    if {$note ne {}} {
        ttk::label $d.coordinateNote -text $note -wraplength 690 -justify left
        pack $d.coordinateNote -side top -fill x -before $d.viewport -padx 10 -pady 6
    }
    wm geometry $d 760x490
    ttk::button $d.actions.reset -text "Reset grid" -command [list ::GX::native2DGridReset $window $scene $changed $parent $presentation]
    pack $d.actions.reset -side left -before $d.actions.close -padx 4
}
proc ::GX::native2DGridApply {scene changed values} {
    set grid [dict create enabled 1 origin [list [dict get $values origin_x] [dict get $values origin_y]] angle [expr {[dict get $values rotation]*acos(-1)/180}]]
    foreach key {visible snap_enabled major_visible minor_visible axes_visible spacing_x spacing_y major_interval major_width minor_width axes_width} {dict set grid $key [dict get $values $key]}
    foreach key {major minor axes} {
        dict set grid ${key}_color [::GX::uiFieldColorToRGBA [dict get $values ${key}_color]]
        dict set grid ${key}_style [lsearch -exact {Solid Dash Dot} [dict get $values ${key}_style]]
    }
    foreach key {spacing_x spacing_y} {if {[dict get $grid $key]<=0} {error "Grid $key must be positive"}}
    set polar [dict create origin [list [dict get $values polar_origin_x] [dict get $values polar_origin_y]]]
    foreach key {clockwise degrees radius_min radius_max radial_spacing radial_major_interval angular_major_interval} {dict set polar $key [dict get $values $key]}
    foreach key {theta_zero angle_min angle_span angular_spacing} {dict set polar $key [expr {[dict get $values $key]*acos(-1)/180}]}
    if {[dict get $polar radius_min]<0||[dict get $polar radius_max]<=[dict get $polar radius_min]} {error "Polar radius bounds require 0 <= minimum < maximum"}
    if {[dict get $polar radial_spacing]<=0} {error "Polar radial spacing must be positive"}
    foreach key {angle_span angular_spacing} {if {[dict get $values $key]<=0||[dict get $values $key]>360} {error "Polar [string map {_ { }} $key] must be greater than 0 and at most 360 degrees"}}
    # All field validation occurs before the first native presentation change.
    # Aspect is a host/module API policy, not a user-facing grid override.
    ::GX::Native2D::core presentation $scene [dict create grid $grid background [::GX::uiFieldColorToRGBA [dict get $values background]] polar $polar coordinate_mode [dict get $values coordinate_mode]]
    if {$changed ne ""} {uplevel #0 $changed}
}
proc ::GX::native2DGridReset {window scene changed parent {presentation {}}} {
    _native2DGridPresentationGuard $presentation
    set empty [::GX::Native2D::core scene]
    try {set grid [::GX::Native2D::core grid $empty]} finally {::GX::Native2D::core destroy $empty}
    ::GX::Native2D::core grid $scene $grid
    if {$changed ne ""} {uplevel #0 $changed}
    native2DGridForm $window $scene $changed $parent $presentation
}
proc ::GX::native2DCanvasGrid {scene canvas {tag construction_grid} {minimumSpacing 0}} {
    if {![string is double -strict $minimumSpacing] || $minimumSpacing<0 || $minimumSpacing>128} {error {Grid presentation spacing must be 0..128 pixels}}
    set grid [::GX::Native2D::core grid $scene]
    set background [uiFieldColorFromRGBA [::GX::Native2D::core background $scene]]
    set background [uiFieldColorComposite $background #FFFFFF]
    set lines [::GX::Native2D::core render_grid $scene]
    # Select presentation detail from the native owner's actual lines. Snap
    # spacing and all authored grid state stay unchanged.
    set coordinates {};set suppressed {}
    if {$minimumSpacing>0} {
        foreach line $lines {
            set classification [dict get $line classification]
            if {$classification==2} continue
            lassign [dict get $line a] ax ay;lassign [dict get $line b] bx by
            set orientation [expr {abs($ax-$bx)<0.5?{x}:{y}}]
            dict lappend coordinates [list $classification $orientation] [expr {$orientation eq {x}?$ax:$ay}]
        }
        dict for {key values} $coordinates {
            set previous {};foreach value [lsort -real -unique $values] {
                if {$previous ne {} && $value-$previous<$minimumSpacing} {dict set suppressed $key 1;break}
                set previous $value
            }
        }
    }
    foreach line $lines {
        lassign [dict get $line a] ax ay;lassign [dict get $line b] bx by
        set orientation [expr {abs($ax-$bx)<0.5?{x}:{y}}]
        if {[dict exists $suppressed [list [dict get $line classification] $orientation]]} continue
        set kind [lindex {minor major axes} [dict get $line classification]]
        set color [uiFieldColorComposite [uiFieldColorFromRGBA [dict get $grid ${kind}_color]] $background]
        set options [list -fill [dict get $color rgb] -width [dict get $grid ${kind}_width] -tags $tag]
        set style [dict get $grid ${kind}_style]
        if {$style==1} {lappend options -dash {6 3}} elseif {$style==2} {lappend options -dash {1 3}}
        $canvas create line {*}[dict get $line a] {*}[dict get $line b] {*}$options
    }
}
proc ::GX::native2DCoordinateReadout {scene device} {
    set world [::GX::Native2D::core world $scene $device]
    if {[::GX::Native2D::core coordinate_mode $scene] eq "polar"} {
        lassign [::GX::Native2D::core to_polar $scene $world] radius theta
        set unit [expr {[dict get [::GX::Native2D::core polar $scene] degrees] ? "deg" : "rad"}]
        return [format "Polar: r %.7g, theta %.7g %s" $radius $theta $unit]
    }
    return [format "X %.7g, Y %.7g" {*}$world]
}
proc ::GX::native2DToolbarLayout {frame width {children {}}} {tailcall ::GX::uiFieldControlsLayout $frame $width $children}
source [file join [file dirname [info script]] native2d_virtual_grid_v1.tcl]
