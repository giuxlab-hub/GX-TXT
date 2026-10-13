# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::AcqMolecule {
    variable helper [file join [file dirname [info script]] molecule_io.py]
}

proc ::AcqMolecule::readStructure {path} {
    variable helper
    set python [::GX::runtimeToolRequired python]
    set output [exec $python -B $helper inspect $path]
    set metadata [dict create]
    foreach line [split $output "\n"] {
        set fields [split $line "\t"]
        if {[lindex $fields 0] ne "META" || [llength $fields] != 3} continue
        set key [encoding convertfrom utf-8 [binary decode base64 -strict [lindex $fields 1]]]
        set value [encoding convertfrom utf-8 [binary decode base64 -strict [lindex $fields 2]]]
        dict set metadata $key $value
    }
    if {![dict exists $metadata molecule.format]} {error "Molecular inspector returned no format"}
    return $metadata
}

proc ::AcqMolecule::inspect {request} {
    if {[catch {set metadata [readStructure [dict get $request source_path]]} problem]} {
        return [dict create recognized 0 format "" metadata {} variables {} preview_rows {} \
            warnings [list $problem] preview_kind metadata \
            preview_metadata [dict create Diagnostic $problem]]
    }
    set preview [dict create Name [dict get $metadata molecule.name] \
        Atoms [dict get $metadata molecule.atom_count] Bonds [dict get $metadata molecule.bond_count] \
        Conformers [dict get $metadata molecule.conformer_count] \
        Elements [dict get $metadata molecule.elements]]
    return [dict create recognized 1 format [dict get $metadata molecule.format] \
        metadata $metadata variables {} preview_rows {} warnings {} \
        preview_kind metadata preview_metadata $preview]
}

proc ::AcqMolecule::import {request} {
    set raw [dict get $request raw_path]
    set metadata [readStructure $raw]
    set fmt [dict get $metadata molecule.format]
    set id [dict get $request dataset_id]
    set ext [string tolower [file extension $raw]]
    set output [file join [dict get $request output_dir] "${id}${ext}"]
    file copy -force -- $raw $output
    dict set metadata molecule.source_filename [file tail [dict get $request source_path]]
    dict set metadata molecule.source_sha256 [::GX::sha256File $raw]
    return [dict create datasets [list [dict create dataset_id $id \
        contract molecular.structure format $fmt path [file tail $output] \
        storage_kind binary media_type "chemical/x-$fmt" variables {} units {} \
        semantic_roles {} source [dict get $metadata molecule.name] \
        notes "" structured_metadata $metadata \
        provenance "Source molecular bytes preserved exactly; coordinates in angstrom; derived display geometry is not a scientific source."]]]
}

proc ::AcqMolecule::datasetPreview {request} {
    set result [inspect [dict create source_path [dict get $request dataset_path]]]
    return [dict create preview_kind metadata preview_metadata [dict get $result preview_metadata] \
        text [join [dict get $result warnings] "\n"]]
}
