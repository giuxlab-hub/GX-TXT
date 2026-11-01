# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit, read-only display snapshots of saved exact Sketch Documents. Never
# used by pointer motion, scientific comparisons, constraints or History replay.
proc ::GX::_nativeCadSketchDisplayLayers {scene authority model {targetUnit {}}} {
    set parts {};set local {};set total 0
    set sample [::GX::Native2D::core scene]
    try {
        foreach native [::GX::Native2D::core ids $scene] {
            set style [::GX::Native2D::core object_style $scene $native]
            if {![dict get $style visible]} continue
            set definition [::GX::Native2D::core sketch_definition $scene $native]
            set definitions [list [dict create definition $definition]]
            if {[dict get $definition family] in {compound composite_path}} {
                set definitions {}
                for {set i 0} {$i<[llength [dict get $definition parts]]} {incr i} {lappend definitions [::GX::Native2D::core composition_part $scene $native $i]}
            }
            set ordinal 0
            foreach part $definitions {
                if {[incr total]>4096} {error {Sketch display exceeds4096 retained constituents}}
                set object [::GX::Native2D::core sketch_create $sample [dict get $part definition] 129]
                try {
                    if {[dict get $part definition family] eq {point}} {set points [list [dict get [::GX::Native2D::core sketch_evaluate $sample $object 0] point]]} else {
                        set points [::GX::Native2D::core sketch_sample $sample $object 0 1 129 0 129]
                    }
                } finally {::GX::Native2D::core delete $sample $object}
                lappend parts [dict create id sketch_${native}_[incr ordinal] offset [llength $local] count [llength $points] style $style order $total]
                lappend local {*}[lmap xy $points {concat $xy 0}]
            }
        }
    } finally {::GX::Native2D::core destroy $sample}
    # Batch the existing authoritative frame conversion, instead of one
    # synchronous Document/worker round trip per constituent.
    set world {}
    for {set i 0} {$i<[llength $local]} {incr i 65536} {
        set receipt [::GX::native3DGeometryCall $authority plane_frame [dict create plane [dict get $model plane] direction to_world points [lrange $local $i [expr {$i+65535}]]]]
        lappend world {*}[dict get $receipt points]
    }
    if {$targetUnit ne {} && $targetUnit ne [dict get $model working_unit]} {
        set coordinates [concat {*}$world];set flat {}
        for {set i 0} {$i<[llength $coordinates]} {incr i 4095} {
            lappend flat {*}[::GX::unitRegistryConvertCoordinates [dict get $model working_unit] $targetUnit [lrange $coordinates $i [expr {$i+4094}]]]
        }
        set world {};foreach {x y z} $flat {lappend world [list $x $y $z]}
    }
    set layers {}
    foreach part $parts {
        set count [dict get $part count];set offset [dict get $part offset];set style [dict get $part style]
        set indices {};for {set i 0} {$i<$count} {incr i} {lappend indices $i}
        set lines [list $indices];set points {}
        if {$count==1} {set lines {};set points {0}}
        set color [dict get $style color]
        dict set layers [dict get $part id] [dict create source_mode memory_geometry provenance cad_sketch_bounded_visual_sampling dataset_id {} layer_order [dict get $part order] visible 1 opacity [lindex $color 3] \
            representation wireframe base_color [join [lrange $color 0 2] {;}] line_width [dict get $style line_width] point_size 5 backface_culling 0 scalar_coloring 0 scalar_array {} local_transform {} texture {} \
            vertices [lrange $world $offset [expr {$offset+$count-1}]] polylines $lines points $points triangles {}]
    }
    return $layers
}
proc ::GX::nativeCadSketchDocumentPresentation {document {targetUnit {}}} {
    set scope [::GX::interactiveDocumentMetadata $document]
    set saved [::GX::interactiveDocumentRead $document]
    if {[dict get $saved format] ne {gxtxt.native_cad_sketch.v1}} {error {Display source is not an exact Sketch Document}}
    set model [dict get $saved payload model];::GX::NativeCadSketch::validate $model
    if {$targetUnit eq {}} {set targetUnit [dict get $model working_unit]}
    ::GX::unitRegistryConversionPlan [dict get $model working_unit] $targetUnit
    ::GX::native2DEnsure
    set scene [::GX::Native2D::core scene];set authority {}
    try {
        # Saved exact definitions are canonical. Solver state is not re-applied
        # to a display sample and no History context or editable GUI is created.
        dict for {key entry} $model {
            if {![string match object/* $key]} continue
            set object [::GX::Native2D::core sketch_create $scene [dict get $entry definition] 257]
            ::GX::Native2D::core object_style $scene $object [dict get $entry style]
        }
        set authority [::GX::native3DGeometryOpen $document]
        set layers [_nativeCadSketchDisplayLayers $scene $authority $model $targetUnit]
        if {$scope ne [::GX::interactiveDocumentMetadata $document]} {error {Sketch changed while preparing its saved display}}
        return [dict create document_id $document generation [dict get $scope generation] revision [dict get $scope revision] session_token [::GX::interactiveDocumentSessionToken] working_unit $targetUnit layers $layers display_policy bounded_visual_sampling scientific_owner Native2D]
    } finally {
        if {$authority ne {}} {::GX::native3DGeometryClose $authority}
        ::GX::Native2D::core destroy $scene
    }
}
