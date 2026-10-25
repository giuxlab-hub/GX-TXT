# SPDX-License-Identifier: GPL-3.0-or-later
# Additive GUI-host CAD context in the established NATIVE2D_API_v1 family.
# Document-scoped NATIVE_2D_GEOMETRY_API_v1 keeps its own token/unit authority.
proc ::GX::native2DCadApiInfo {} {
    native2DEnsure
    set info [::GX::Native2D::core api_info]
    dict set info host_commands {native2DCadCreate native2DCadDispose native2DCadSelectionPresent native2DCadComponentPresent native2DCadCanvasCreate native2DCadCanvasAttach native2DCadConstructionCount native2DCadDimensionKinds}
    dict set info cad_families {selection object component control relationship gesture}
    dict set info host_tool_families {construction topology constraint dimension control direction}
    dict set info advanced_tools_host_only 1
    dict set info cad_raw_pointers 0
    dict set info cad_scientific_authority Native2D.C
    return $info
}
proc ::GX::native2DCadCreate {scene {selectionSet 0} {owner {}}} {
    native2DEnsure
    if {$owner ne {} && ![winfo exists $owner]} {error {CAD GUI owner has closed}}
    set cad [::GX::Native2D::core cad_controller $scene $selectionSet]
    if {$owner ne {}} {bind $owner <Destroy> +[list ::GX::_native2DCadDestroyed $cad $owner %W]}
    return $cad
}
proc ::GX::_native2DCadDestroyed {cad owner actual} {if {$actual eq $owner} {native2DCadDispose $cad}}
proc ::GX::native2DCadDispose {cad} {if {[llength [info commands $cad]]} {$cad dispose}}
proc ::GX::native2DCadSelectionPresent {cad canvas {options {}}} {
    foreach key [dict keys $options] {if {$key ni {exclude_objects point_objects}} {error {Unknown CAD highlight option}}}
    set exclude [datasetPublicationV2DictDefault $options exclude_objects {}]
    set pointsOnly [datasetPublicationV2DictDefault $options point_objects {}]
    set scene [dict get [$cad state] scene];set references [dict get [$cad selection snapshot] references]
    foreach ref $references {
        set id [dict get $ref object]
        if {$id in $exclude} continue
        set style [::GX::Native2D::core object_style $scene $id]
        if {![dict get $style visible]} continue
        if {[dict get $style layer] && ![dict get [::GX::Native2D::core layer_info $scene [dict get $style layer]] visible]} continue
        if {[dict get $ref semantic_kind] eq {object}} {
            set object [native2DPresentationObjectSnapshot $scene $id 4096]
            if {$object eq {}} continue
            dict set object style color {0.847 0.529 0 1};dict set object style line_width 5
            if {[dict get $object kind] eq {curve}} {dict set object style marker 0}
            if {$id in $pointsOnly} {
                set paths {};foreach path [dict get $object paths] {foreach point $path {lappend paths [list $point]}}
                dict set object paths $paths;dict set object style marker 2
            }
            dict unset object marker;dict unset object part_markers
            native2DCanvasDrawObject $canvas $object [$canvas cget -background] semantic_object_selection
        } elseif {[dict get $ref semantic_kind] eq {segment}} {
            set points [::GX::Native2D::core interaction_render $scene $ref]
            if {[llength $points]>=2} {$canvas create line {*}[concat {*}$points] -fill #d88700 -width 5 -tags semantic_segment_selection}
        }
    }
    foreach ref $references {
        if {[dict get $ref object] in $exclude || [dict get $ref semantic_kind] ni {control point}} continue
        lassign [::GX::Native2D::core device $scene [$cad control resolve $ref]] x y
        $canvas create rectangle [expr {$x-6}] [expr {$y-6}] [expr {$x+6}] [expr {$y+6}] -fill #ffbd3a -outline #573700 -width 2 -tags semantic_point_selection
    }
    native2DCanvasViewportClip $canvas $scene
}
proc ::GX::native2DCadComponentPresent {cad canvas object part} {
    set points [$cad component render $object $part]
    if {[llength $points]>=2} {$canvas create line {*}[concat {*}$points] -fill #c97800 -width 4 -tags part_highlight}
}
