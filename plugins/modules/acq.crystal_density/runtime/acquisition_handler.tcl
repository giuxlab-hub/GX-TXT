# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::AcqCrystalDensity {
    variable helper [file normalize [file join [file dirname [info script]] .. .. viewer.crystal_structure runtime crystal_data.py]]
}

proc ::AcqCrystalDensity::_helper {} {
    variable helper
    return $helper
}
proc ::AcqCrystalDensity::_inspect {path} {
    set python [::GX::runtimeToolRequired python]
    set command [list $python -B [_helper] inspect $path --tcl]
    set text [exec {*}$command]
    set lines [split [string trim $text] "\n"]
    if {[lindex $lines 0] ne "GXCRYSTAL1" || [lindex $lines end] ne "OK"} {
        error "Crystal inspection protocol is incomplete"
    }
    set md [dict create]
    foreach line [lrange $lines 1 end-1] {
        set fields [split $line "\t"]
        if {[lindex $fields 0] ne "M" || [llength $fields] != 3} continue
        set key [encoding convertfrom utf-8 [binary decode base64 [lindex $fields 1]]]
        set value [encoding convertfrom utf-8 [binary decode base64 [lindex $fields 2]]]
        dict set md $key $value
    }
    return $md
}
proc ::AcqCrystalDensity::inspect {request} {
    set path [dict get $request source_path]
    set md [_inspect $path]
    set format [dict get $md kind]
    if {$format ni {cif cube}} {error "Unsupported crystal/density source"}
    set preview [dict create Format [string toupper $format] {Source SHA-256} [dict get $md source_sha256]]
    foreach {key label} {formula Formula space_group {Space group} site_count {Site count} expanded_count {Expanded atoms} atom_count {Atoms} dimensions {Grid size} range {Field range} field_unit {Field unit}} {
        if {[dict exists $md $key]} {dict set preview $label [dict get $md $key]}
    }
    return [dict create recognized 1 format "chemistry.$format" detected_contract \
        [expr {$format eq "cif" ? "structure.crystal" : "field.scalar_3d"}] \
        preview_kind metadata preview_metadata $preview warnings {}]
}
proc ::AcqCrystalDensity::import {request} {
    set source [dict get $request raw_path]
    set md [_inspect $source]
    set format [dict get $md kind]
    set id [dict get $request dataset_id]
    set rel "[regsub -all {[^A-Za-z0-9_.-]} $id _].$format"
    set target [file join [dict get $request output_dir] $rel]
    if {[file exists $target]} {error "Canonical crystal/density destination already exists"}
    file copy -- $source $target
    if {[::GX::sha256File $target] ne [dict get $md source_sha256]} {
        file delete -- $target
        error "Crystal/density copy failed SHA-256 verification"
    }
    set metadata [dict create chemistry.format $format chemistry.source_sha256 [dict get $md source_sha256] \
        source.original_filename [file tail [dict get $request source_path]]]
    foreach key {source_id formula space_group space_group_number site_count expanded_count operator_count cell citation doi atom_count dimensions range field_unit description generator} {
        if {[dict exists $md $key]} {dict set metadata "chemistry.$key" [dict get $md $key]}
    }
    set contract [expr {$format eq "cif" ? "structure.crystal" : "field.scalar_3d"}]
    set media [expr {$format eq "cif" ? "chemical/x-cif" : "chemical/x-gaussian-cube"}]
    return [dict create datasets [list [dict create dataset_id $id contract $contract format $format \
        path $rel storage_kind binary media_type $media variables {} units {} semantic_roles {} \
        source [file tail [dict get $request source_path]] \
        provenance "Original CIF/CUBE source bytes preserved; scientific inspection metadata recorded without rewriting the source." \
        structured_metadata $metadata]]]
}
proc ::AcqCrystalDensity::datasetPreview {request} {
    set r [inspect [dict create source_path [dict get $request dataset_path]]]
    return [dict create preview_kind metadata preview_metadata [dict get $r preview_metadata] text ""]
}
