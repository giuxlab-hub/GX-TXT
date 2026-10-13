# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::NmrAcq {
    variable worker [file normalize [file join [file dirname [info script]] nmr_jcamp.py]]
}

proc ::GX::NmrAcq::_run {mode path {output ""} {settings {}}} {
    variable worker
    set python [::GX::runtimeToolRequired python]
    set command [list $python -B $worker $mode $path]
    if {$output ne ""} {lappend command $output}
    if {[dict exists $settings zero_fill_factor]} {
        lappend command --zero-fill [dict get $settings zero_fill_factor]
    }
    if {[dict exists $settings line_broadening_hz]} {
        lappend command --line-broadening-hz [dict get $settings line_broadening_hz]
    }
    if {[dict exists $settings phase_deg]} {
        lappend command --phase-deg [dict get $settings phase_deg]
    }
    lappend command --kv
    set lines [split [string trim [exec {*}$command]] "\n"]
    set result [dict create]
    foreach line $lines {
        if {$line eq ""} continue
        lassign [split $line "\t"] key encoded
        if {$key eq "" || $encoded eq ""} {error "NMR worker returned a malformed record"}
        dict set result $key [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
    }
    return $result
}

proc ::GX::NmrAcq::_setting {request name default} {
    foreach key [list $name "config.$name"] {
        if {[dict exists $request $key]} {return [dict get $request $key]}
    }
    if {[dict exists $request config $name]} {return [dict get $request config $name]}
    return $default
}

proc ::GX::NmrAcq::inspect {request} {
    set path [dict get $request source_path]
    if {[catch {set data [_run inspect $path]} problem]} {
        return [dict create recognized 0 format jcamp-dx.nmr.ntuple metadata {} \
            variables {} preview_rows {} warnings [list $problem]]
    }
    set metadata [dict create]
    dict for {key value} $data {dict set metadata "nmr.$key" $value}
    set variables [list \
        [dict create source_column 1 original_header chemical_shift_ppm canonical spectral_x unit ppm semantic_role independent] \
        [dict create source_column 2 original_header intensity canonical spectral_y unit 1 semantic_role measured]]
    return [dict create recognized 1 format jcamp-dx.nmr.ntuple metadata $metadata \
        variables $variables preview_rows {} warnings {} preview_kind metadata \
        preview_metadata [dict create Nucleus [dict get $data nucleus] \
            {Observed frequency [MHz]} [dict get $data observed_frequency_mhz] \
            Solvent [dict get $data solvent] {Data type} [dict get $data data_type] \
            {Sample points} [dict get $data sample_count]]]
}

proc ::GX::NmrAcq::import {request} {
    set id [dict get $request dataset_id]
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id]} {error "Invalid NMR Dataset ID"}
    set settings [dict create \
        zero_fill_factor [_setting $request zero_fill_factor 4] \
        line_broadening_hz [_setting $request line_broadening_hz 2.0] \
        phase_deg [_setting $request phase_deg 0]]
    set relative "${id}.csv"
    set data [_run convert [dict get $request raw_path] [file join [dict get $request output_dir] $relative] $settings]
    set metadata [dict create]
    dict for {key value} $data {dict set metadata "nmr.$key" $value}
    set schema [list \
        [dict create variable_id spectral_x canonical spectral_x source_column 1 dtype float64 unit ppm semantic_role independent coordinate_role coordinate axis_kind explicit] \
        [dict create variable_id spectral_y canonical spectral_y source_column 2 dtype float64 unit 1 semantic_role measured coordinate_variable_ids spectral_x]]
    set note "NMR [dict get $data nucleus] [dict get $data data_type]; [dict get $data observed_frequency_mhz] MHz; solvent [dict get $data solvent]; reference [dict get $data shift_reference]."
    set provenance "JCAMP-DX source SHA-256 [dict get $data source_sha256]; [dict get $data processing]"
    if {[dict get $data processing] eq "fid_fft"} {
        append provenance "; zero-fill [dict get $data zero_fill_factor]; line broadening [dict get $data line_broadening_hz] Hz; phase [dict get $data phase_deg] degrees"
    }
    set dataset [dict create dataset_id $id contract spectrum.scientific format csv path $relative \
        variables {spectral_x spectral_y} units {ppm 1} semantic_roles {independent measured} \
        variable_schema $schema structured_metadata $metadata source [dict get $request source_path] \
        provenance $provenance notes $note]
    return [dict create datasets [list $dataset]]
}
