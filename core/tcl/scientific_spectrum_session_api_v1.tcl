# GX-TXT CORE experimental spectrum import into a normal Session Dataset.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectrumSessionAPIv1 { variable apiVersion 1 }

proc ::GX::SpectrumSessionAPIv1::apiInfo {} {
    variable apiVersion
    return [dict create api_name SCIENTIFIC_SPECTRUM_SESSION_API_v1 api_version $apiVersion contract spectrum.scientific]
}

proc ::GX::SpectrumSessionAPIv1::publishExperimental {session datasetId spectrum} {
    ::GX::SpectrumAPIv1::validate $spectrum
    set session [file normalize $session]
    if {![file isdirectory $session] || ![file isdirectory [file join $session metadata]]} {
        error "Scientific Spectrum Session API v1: existing GX-TXT Session required"
    }
    set n [dict get $spectrum sample_count]
    set provenance [dict create \
        source_identity [dict get $spectrum source_identity] \
        source_hash [dict get $spectrum source_hash] \
        spectrum_hash [dict get $spectrum spectrum_hash] \
        spectrum_kind [dict get $spectrum spectrum_kind] \
        x_quantity [dict get $spectrum x_quantity] \
        y_quantity [dict get $spectrum y_quantity] \
        y_representation [dict get $spectrum y_representation] \
        metadata [dict get $spectrum metadata] \
        provenance [dict get $spectrum provenance]]
    set definition [dict create dataset_id $datasetId contract spectrum.scientific \
        storage auto producer_version 1.0.0 source [dict get $spectrum source_identity] \
        provenance $provenance notes {Experimental spectrum imported through CORE Scientific Spectrum API v1; original source preserved.}]
    set plan [::GX::datasetPublicationV2Prepare $session acq.spectrum $definition]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer spectral_point 0 [dict create extendible 1]
        ::GX::datasetPublicationV2DeclareVariable $writer spectral_x [dict create \
            name [dict get $spectrum x_quantity] dtype float64 dimension_ids spectral_point \
            unit [dict get $spectrum x_unit] semantic_role independent \
            coordinate_role coordinate]
        ::GX::datasetPublicationV2DeclareVariable $writer spectral_y [dict create \
            name [dict get $spectrum y_quantity] dtype float64 dimension_ids spectral_point \
            unit [dict get $spectrum y_unit] semantic_role measured \
            coordinate_variable_ids spectral_x]
        set written [::GX::datasetPublicationV2Append $writer spectral_point \
            [dict create spectral_x [dict get $spectrum x] spectral_y [dict get $spectrum y]]]
        if {$written != $n} { error "Scientific Spectrum Session API v1: incomplete Dataset write" }
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {::GX::datasetPublicationV2Abort $writer}
        return -options $options $message
    }
}

proc ::GX::SpectrumSessionAPIv1::importExperimental {session datasetId format path options} {
    set spectrum [::GX::SpectrumImportAPIv1::parse $format $path $options]
    return [publishExperimental $session $datasetId $spectrum]
}
