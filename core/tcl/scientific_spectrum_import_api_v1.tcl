# GX-TXT Scientific Spectrum Import API v1 (CORE).
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectrumImportAPIv1 { variable apiVersion 1 }

proc ::GX::SpectrumImportAPIv1::apiInfo {} {
    variable apiVersion
    return [dict create api_name SCIENTIFIC_SPECTRUM_IMPORT_API_v1 api_version $apiVersion formats {csv jcamp}]
}

proc ::GX::SpectrumImportAPIv1::_helper {} {
    set path [file join $::GX::scriptDir core python scientific_spectrum_import.py]
    if {![file isfile $path]} { error "Scientific Spectrum Import CORE helper is missing" }
    return $path
}

proc ::GX::SpectrumImportAPIv1::parse {format path options} {
    set format [string tolower [string trim $format]]
    if {$format ni {csv jcamp}} { error "Scientific Spectrum Import API v1: format must be csv or jcamp" }
    if {![file isfile $path]} { error "Scientific Spectrum Import API v1: source file does not exist" }
    if {[catch {dict size $options}]} { error "Scientific Spectrum Import API v1: options must be a Tcl dict" }
    set metadata [expr {[dict exists $options metadata] ? [dict get $options metadata] : [dict create]}]
    set provenance [expr {[dict exists $options provenance] ? [dict get $options provenance] : [dict create]}]
    set fields [dict remove $options metadata provenance]
    set request [::GX::ReferenceLibraryAPIv1::_wireTemp $fields $metadata $provenance]
    try {
        set argv [list [::GX::ReferenceLibraryAPIv1::_python] [_helper] $format [file normalize $path] $request]
        if {[catch {set raw [exec {*}$argv 2>@1]} failure settings]} {
            return -options $settings "Scientific Spectrum Import API v1: $failure"
        }
        set fields [::GX::ReferenceLibraryAPIv1::_parseWire $raw]
        return [::GX::SpectrumAPIv1::create $fields]
    } finally {
        catch {file delete -- $request}
    }
}

proc ::GX::SpectrumImportAPIv1::parseCsv {path options} { return [parse csv $path $options] }
proc ::GX::SpectrumImportAPIv1::parseJcamp {path options} { return [parse jcamp $path $options] }

proc ::GX::SpectrumImportAPIv1::importOneToLibrary {libraryId format path options} {
    set spectrum [parse $format $path $options]
    ::GX::ReferenceLibraryAPIv1::addSpectrum $libraryId $spectrum
    return [dict create library_id $libraryId spectrum_id [dict get $spectrum spectrum_id] spectrum_hash [dict get $spectrum spectrum_hash] sample_count [dict get $spectrum sample_count] source_hash [dict get $spectrum source_hash]]
}

proc ::GX::SpectrumImportAPIv1::importBatchToLibrary {libraryId jobs} {
    set report {}
    foreach job $jobs {
        foreach key {format path options} {
            if {![dict exists $job $key]} { error "Scientific Spectrum Import API v1: batch job missing $key" }
        }
        set path [dict get $job path]
        if {[catch {
            set result [importOneToLibrary $libraryId [dict get $job format] $path [dict get $job options]]
        } problem]} {
            lappend report [dict create path $path status failed message $problem]
        } else {
            lappend report [dict merge [dict create path $path status imported] $result]
        }
    }
    return $report
}
