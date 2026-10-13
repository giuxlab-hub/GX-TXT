# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical geometry.sketch, UTF-8 Tcl dictionary data (never sourced/evaluated).
# No Workspace state or scientific Dataset payload is part of this schema.
proc ::GX::sketchDatasetValidate {sketch} {
    if {[string length $sketch]>64000000} {error {Sketch exceeds 64 MB}}
    foreach field {schema version objects constraints parameters provenance} {if {![dict exists $sketch $field]} {error "Sketch missing $field"}}
    if {[dict get $sketch schema] ne "gxtxt.geometry.sketch" || [dict get $sketch version] ne "1.0"} {error {Unsupported Sketch schema/version}}
    foreach field [dict keys $sketch] {if {$field ni {schema version objects constraints parameters provenance}} {error "Unsupported Sketch field $field"}}
    native2DEnsure
    set scene [::GX::Native2D::core scene];set ids {}
    try {
        dict for {id record} [dict get $sketch objects] {
            foreach key [dict keys $record] {if {$key ni {name definition units metadata provenance}} {error "Unsupported geometric object field $key"}}
            foreach key {name definition units} {if {![dict exists $record $key]} {error "Sketch object $id missing $key"}}
            foreach unit [dict get $record units] {if {$unit ne {}} {unitRegistryConversionPlan $unit $unit}}
            dict set ids $id [::GX::Native2D::core sketch_create $scene [dict get $record definition] 257]
        }
        if {![dict size $ids]} {error {Sketch contains no geometry}}
        _parameterEvaluate [dict get $sketch parameters] {}
        dict for {id record} [dict get $sketch constraints] {
            set spec [dict get $record definition]
            foreach field {a b axis} {if {[dict exists $spec $field] && [dict get $spec $field] ne {}} {dict set spec $field [dict get $ids [dict get $spec $field]]}}
            ::GX::Native2D::core constraint_create $scene $spec
            if {[dict exists $record expression]} {_parameterEvaluate [dict get $sketch parameters] {} [dict get $record expression]}
        }
    } finally {::GX::Native2D::core destroy $scene}
    return $sketch
}
proc ::GX::sketchDatasetReadFile {path} {
    if {[file size $path]>64000000} {error {Sketch exceeds 64 MB}}
    return [sketchDatasetValidate [noteReadUtf8 $path]]
}
proc ::GX::sketchDatasetRead {session datasetId} {
    loadDatasetRegistry $session
    if {[datasetField $datasetId contract {}] ne "geometry.sketch"} {error {Dataset is not a canonical Sketch}}
    set path [file join $session [datasetField $datasetId path {}]]
    if {[sha256File $path] ne [datasetField $datasetId sha256 [datasetField $datasetId canonical_sha256 {}]]} {error {Sketch Dataset integrity mismatch}}
    return [sketchDatasetReadFile $path]
}
proc ::GX::sketchDatasetPublish {session moduleId datasetId sketch {options {}}} {
    sketchDatasetValidate $sketch
    set channel [file tempfile path];fconfigure $channel -encoding utf-8 -translation lf
    try {
        puts -nonewline $channel $sketch;close $channel;set channel {}
        set request [dict merge $options [dict create dataset_id $datasetId contract geometry.sketch format gxsketch storage_kind text media_type application/vnd.gxtxt.sketch source_file $path provenance [dict get $sketch provenance]]]
        return [datasetFilePublicationPublish $session $moduleId $request]
    } finally {if {$channel ne {}} {close $channel};file delete -force $path}
}
proc ::GX::sketchDatasetPreview {path output} {
    set sketch [sketchDatasetReadFile $path];set scene [::GX::Native2D::core scene]
    try {
        dict for {id record} [dict get $sketch objects] {set native [::GX::Native2D::core sketch_create $scene [dict get $record definition] 257];::GX::Native2D::core object_style $scene $native {color {0.05 0.25 0.5 1} line_width 2 marker 0}}
        return [native2DCanvasPreview $scene {} fit [dict create width 960 height 600 output_file $output background {1 1 1 1}]]
    } finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::pdfDatasetOpen {path identity} {
    variable scriptDir
    foreach command {pdfinfo pdftoppm} {if {[auto_execok $command] eq {}} {error "Integrated PDF viewing requires Poppler ($command)"}}
    if {[catch {exec [runtimeToolRequired python] -B -c {import tkinter; from PIL import Image, ImageTk}} problem]} {error "Integrated PDF viewing requires Python Tk and Pillow: $problem"}
    return [exec [runtimeToolRequired python] -B [file join $scriptDir core python pdf_dataset_viewer.py] $path $identity &]
}
# Freeze external Session dependencies as named local values while retaining
# their original formula in the description. Local formulas stay evaluable.
proc ::GX::sketchDatasetParameters {token} {
    set definitions [parameterDefinitions $token];set substitutions {}
    dict for {name record} [parameterSessionList] {
        set local gx_session_$name
        while {[dict exists $definitions $local]} {append local _}
        lappend substitutions session.$name $local
        dict set definitions $local [dict create formula [dict get $record value] description "Captured Session parameter $name; original expression: [dict get $record formula]"]
    }
    dict for {name record} $definitions {dict set definitions $name formula [sketchDatasetParameterExpression [dict get $record formula] $substitutions]}
    return [dict create definitions $definitions substitutions $substitutions]
}
proc ::GX::sketchDatasetParameterExpression {expression substitutions} {
    # Replace complete parameter tokens; session.a must not rewrite session.ab.
    foreach bounds [lreverse [regexp -all -inline -indices {\msession\.[A-Za-z_][A-Za-z_0-9]*\M} $expression]] {
        lassign $bounds first last
        set token [string range $expression $first $last]
        if {[dict exists $substitutions $token]} {set expression [string replace $expression $first $last [dict get $substitutions $token]]}
    }
    return $expression
}
# Exact native XY rows and breaks, never display LOD or inferred interpolation.
proc ::GX::sketchDatasetPointGeometry {scene native {kind object} {index 0}} {
    if {$kind in {control point}} {return [list [dict create family point controls [::GX::Native2D::core points_page $scene $native $index 1]]]}
    if {$kind eq "segment"} {return [list [dict create family line controls [::GX::Native2D::core points_page $scene $native $index 2]]]}
    set n [::GX::Native2D::core count $scene $native]
    set cuts [::GX::Native2D::core breaks $scene $native];set start 0;set definitions {}
    foreach end [concat $cuts [list [expr {$n-1}]]] {
        while {$start<=$end} {
            set size [expr {min(65536,$end-$start+1)}]
            set points [::GX::Native2D::core points_page $scene $native $start $size]
            lappend definitions [dict create family [expr {$size==1?"point":"polyline"}] controls $points]
            incr start [expr {$size==65536&&$start+$size<=$end?$size-1:$size}]
        }
    }
    return $definitions
}
# Remap semantic references for an exported subset. Shared controls are linked
# by the existing retained coincidence solver, not by coordinate proximity.
proc ::GX::sketchDatasetSubsetRelations {scene extracted constraints} {
    set mapping {};set whole {};set natives {};set result {};set serial 0
    foreach item $extracted {
        dict with item {}
        dict set natives $source $native
        if {$kind eq "object"} {dict set whole $source $key}
        if {$kind eq "segment"} {dict set mapping [list $source $index] [list $key 2000000000]}
        set ordinal 0
        foreach origin [::GX::Native2D::core selection_control_sources $scene $native [expr {$kind eq "object"?3000000000:$index}]] {
            set destination [list $key [expr {1000000000+$ordinal}]];incr ordinal
            set old [_sketchDatasetMappedReference $scene $natives $mapping $source $origin]
            if {[dict exists $mapping $old] && [lindex [dict get $mapping $old] 0] ne $key} {
                lassign [dict get $mapping $old] a ai;lassign $destination b bi
                dict set result topology[incr serial] [dict create name {Preserved shared node} definition [dict create kind coincident a $a a_index $ai b $b b_index $bi solved 1 tolerance 1e-8]]
            } else {dict set mapping $old $destination}
        }
    }
    dict for {id record} $constraints {
        set spec [dict get $record definition];set count 0;set missing 0
        foreach field {a b axis} {
            if {![dict exists $spec $field]||[dict get $spec $field] eq {}} continue
            set source [dict get $spec $field];set index [::GX::datasetPublicationV2DictDefault $spec ${field}_index 0]
            if {[dict exists $whole $source]} {dict set spec $field [dict get $whole $source];incr count;continue}
            set reference [list $source $index]
            if {$index>=1000000000&&$index<2000000000&&[dict exists $natives $source]} {
                set canonical [lindex [::GX::Native2D::core selection_control_sources $scene [dict get $natives $source] $index] 0]
                set reference [list $source $canonical]
            }
            set reference [_sketchDatasetMappedReference $scene $natives $mapping {*}$reference]
            if {[dict exists $mapping $reference]} {
                lassign [dict get $mapping $reference] object ordinal
                dict set spec $field $object;dict set spec ${field}_index $ordinal;incr count
            } else {incr missing}
        }
        if {!$count} continue
        if {$missing} {error "Constraint $id crosses the selected geometry boundary. Include its other referenced geometry."}
        # A shared node already represented by the same defining control needs
        # no self-equation; it remains one authoritative topological identity.
        if {[dict get $spec kind] eq "coincident"&&[dict get $spec a] eq [dict get $spec b]&&[dict get $spec a_index]==[dict get $spec b_index]} continue
        dict set record definition $spec;dict set result $id $record
    }
    return $result
}

proc ::GX::_sketchDatasetMappedReference {scene natives mapping source index} {
    set key [list $source $index]
    if {[dict exists $mapping $key]||$index<1000000000||$index>=2000000000||![dict exists $natives $source]} {return $key}
    set a [::GX::Native2D::core interaction_reference_index $scene [dict get $natives $source] $index]
    dict for {candidate destination} $mapping {
        lassign $candidate other ordinal
        if {$ordinal<1000000000||$ordinal>=2000000000||![dict exists $natives $other]} continue
        set b [::GX::Native2D::core interaction_reference_index $scene [dict get $natives $other] $ordinal]
        if {[::GX::Native2D::core construction_connected $scene $a $b]} {return $candidate}
    }
    return $key
}
