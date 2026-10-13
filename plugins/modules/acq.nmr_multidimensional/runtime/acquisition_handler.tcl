# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::NmrMultiAcq {
    variable worker [file normalize [file join [file dirname [info script]] nmr_pipe_worker.py]]
}

proc ::GX::NmrMultiAcq::_run {path} {
    variable worker
    set python [::GX::runtimeToolRequired python]
    set lines [split [string trim [exec $python -B $worker inspect $path]] "\n"]
    set result [dict create]
    foreach line $lines {
        if {$line eq ""} continue
        lassign [split $line "\t"] key encoded
        if {$key eq "" || $encoded eq ""} {error "NMRPipe worker returned a malformed record"}
        dict set result $key [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    }
    return $result
}

proc ::GX::NmrMultiAcq::_setting {request name} {
    if {[dict exists $request config $name]} {return [dict get $request config $name]}
    if {[dict exists $request $name]} {return [dict get $request $name]}
    return ""
}

proc ::GX::NmrMultiAcq::inspect {request} {
    if {[catch {set parsed [_run [dict get $request source_path]]} problem]} {
        return [dict create recognized 0 format nmrpipe.spectrum metadata {} variables {} preview_rows {} warnings [list $problem]]
    }
    set metadata [dict create]
    dict for {key value} $parsed {dict set metadata "nmr_multi.$key" $value}
    return [dict create recognized 1 format nmrpipe.spectrum metadata $metadata \
        variables [list [dict create source_column 1 original_header intensity canonical intensity unit 1 semantic_role measured]] \
        preview_rows {} warnings {} preview_kind metadata \
        preview_metadata [dict create Dimensions [dict get $parsed dimensions] \
            Shape [dict get $parsed shape] {F1 nucleus} [dict get $parsed axis_1_nucleus] \
            {F2 nucleus} [dict get $parsed axis_2_nucleus] \
            {Source SHA-256} [dict get $parsed source_sha256]]]
}

proc ::GX::NmrMultiAcq::import {request} {
    set id [dict get $request dataset_id]
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id]} {error "Invalid multidimensional NMR Dataset ID"}
    set raw [dict get $request raw_path]
    set data [_run $raw]
    set relative "${id}.nmrpipe"
    set output [file join [dict get $request output_dir] $relative]
    file copy -force -- $raw $output
    set metadata [dict create]
    dict for {key value} $data {dict set metadata "nmr_multi.$key" $value}
    set citation [_setting $request citation]
    set license [_setting $request license]
    dict set metadata nmr_multi.source_citation $citation
    dict set metadata nmr_multi.source_license $license
    dict set metadata nmr_multi.original_filename [file tail [dict get $request source_path]]
    set note "Acquired [dict get $data dimensions]-D NMRPipe spectrum; shape [dict get $data shape]; F1 [dict get $data axis_1_nucleus], F2 [dict get $data axis_2_nucleus]."
    set ds [dict create dataset_id $id contract spectrum.nmr_multidimensional format nmrpipe \
        storage_kind binary media_type application/x-nmrpipe path $relative \
        variables {intensity} units {1} semantic_roles {measured} \
        structured_metadata $metadata source [dict get $request source_path] \
        provenance "Processed NMRPipe source SHA-256 [dict get $data source_sha256]; $citation; rights $license" notes $note]
    return [dict create datasets [list $ds]]
}

proc ::GX::NmrMultiAcq::preview {request} {
    set data [_run [dict get $request dataset_path]]
    set text "Acquired [dict get $data dimensions]-D NMRPipe spectrum\nShape: [dict get $data shape]\n"
    for {set i 1} {$i <= [dict get $data dimensions]} {incr i} {
        append text "F$i: [dict get $data axis_${i}_nucleus] ([dict get $data axis_${i}_label]), [dict get $data axis_${i}_ppm_first] to [dict get $data axis_${i}_ppm_last] ppm\n"
    }
    append text "Source SHA-256: [dict get $data source_sha256]"
    return [dict create text $text]
}
