# SPDX-License-Identifier: GPL-3.0-or-later
# Scientific parsing/axis validation belongs to existing CORE Spectrum APIs.
namespace eval ::AcqScientificSpectrum {variable contextHelper [file join [file dirname [info script]] context_worker.py]}
proc ::AcqScientificSpectrum::_context {path} {
    variable contextHelper
    set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $path]]
    return [exec [::GX::runtimeToolRequired python] -I -B $contextHelper $encoded 2>@1]
}
proc ::AcqScientificSpectrum::_settings {request} {
    set path [dict get $request source_path]
    set context [_context $path]
    set options {x_column 1 y_column 2 header 1 delimiter auto}
    foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit x_column y_column header delimiter} {
        if {[dict exists $request config $key] && [dict get $request config $key] ne {}} {dict set options $key [dict get $request config $key]}
    }
    set format auto
    if {[dict exists $request config source_format] && [dict get $request config source_format] ne {}} {set format [dict get $request config source_format]}
    if {[dict get $context present]} {
        # Context carries scientific data only; integrity is checked by its
        # resource SHA, then by the host dispatch's exact context receipt SHA.
        set options [dict merge $options [dict get $context options]]
        set format [dict get $context format]
    }
    if {$format eq {auto}} {
        set stream [open $path r]
        try {set head [string trimleft [read $stream 512]]} finally {close $stream}
        set format [expr {[string match {##*} $head]?{jcamp}:{csv}}]
    }
    if {$format ni {csv jcamp}} {error {Choose an actual CSV or supported JCAMP source}}
    dict set options spectrum_id [::GX::datasetPublicationV2DictDefault $request dataset_id spectrum-preview]
    if {$format eq {csv} && ![dict exists $options display_name]} {dict set options display_name [file tail $path]}
    return [dict create options $options format $format context $context]
}
proc ::AcqScientificSpectrum::inspect {request} {
    if {[catch {
        set settings [_settings $request]
        set spectrum [::GX::SpectrumImportAPIv1::parse [dict get $settings format] [dict get $request source_path] [dict get $settings options]]
        set metadata [dict create spectrum.parser_options [dict get $settings options] spectrum.source_format [dict get $settings format] spectrum.spectrum_hash [dict get $spectrum spectrum_hash] spectrum.sample_count [dict get $spectrum sample_count]]
        if {[dict get $settings context present]} {dict set metadata spectrum.source_context_sha256 [dict get $settings context context_sha256]}
        foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {dict set metadata spectrum.$key [dict get $spectrum $key]}
    } problem]} {return [dict create recognized 0 warnings [list $problem] variables {} metadata {} preview_rows {}]}
    return [dict create recognized 1 format spectrum.[dict get $settings format] metadata $metadata variables {} preview_rows {} warnings {} preview_kind metadata preview_metadata $metadata]
}
proc ::AcqScientificSpectrum::import {request} {
    set metadata [dict get $request inspection metadata]
    set context [_context [dict get $request source_path]]
    if {[dict exists $metadata spectrum.source_context_sha256]} {
        if {![dict get $context present] || [dict get $context context_sha256] ne [dict get $metadata spectrum.source_context_sha256]} {error {Scientific source context changed after inspection}}
    } elseif {[dict get $context present]} {error {Orphan scientific source context appeared after inspection}}
    set options [dict get $metadata spectrum.parser_options]
    dict set options spectrum_id [dict get $request dataset_id]
    set spectrum [::GX::SpectrumImportAPIv1::parse [dict get $metadata spectrum.source_format] [dict get $request raw_path] $options]
    set relative "[dict get $request dataset_id].spectrum.csv"
    set path [file join [dict get $request output_dir] $relative]
    set stream [open $path {WRONLY CREAT EXCL}]
    fconfigure $stream -encoding utf-8 -translation lf
    try {
        puts $stream spectral_x,spectral_y
        foreach x [dict get $spectrum x] y [dict get $spectrum y] {puts $stream "[format %.17g $x],[format %.17g $y]"}
    } finally {close $stream}
    dict set metadata spectrum.parser_options $options
    dict set metadata spectrum.spectrum_hash [dict get $spectrum spectrum_hash]
    dict set metadata spectrum.original_source_sha256 [dict get $spectrum source_hash]
    set xunit [dict get $spectrum x_unit];set yunit [dict get $spectrum y_unit]
    set schema [list [dict create variable_id spectral_x canonical spectral_x source_column 1 dtype float64 unit $xunit semantic_role independent coordinate_role coordinate axis_kind explicit] [dict create variable_id spectral_y canonical spectral_y source_column 2 dtype float64 unit $yunit semantic_role measured coordinate_variable_ids spectral_x]]
    return [dict create datasets [list [dict create dataset_id [dict get $request dataset_id] contract spectrum.scientific format csv path $relative variables {spectral_x spectral_y} units [list $xunit $yunit] semantic_roles {independent measured} variable_schema $schema structured_metadata $metadata row_count [dict get $spectrum sample_count] source [dict get $spectrum source_identity] provenance {Parsed and validated through existing CORE SCIENTIFIC_SPECTRUM_IMPORT_API_v1 and Spectrum API; exact original RAW preserved by Acquisition; no fabricated trace or duplicated parser.}]]]
}
