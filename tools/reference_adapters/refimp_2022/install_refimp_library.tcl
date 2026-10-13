#!/usr/bin/env tclsh
# Install only the specifically audited RefIMP reference CSV, not arbitrary data.
if {[llength $argv] != 3} {
    error "usage: install_refimp_library.tcl FRAMEWORK_ROOT FTIR_MP_references.csv NEW_EXPORT_ZIP"
}
set framework [file normalize [lindex $argv 0]]
set sourceCsv [file normalize [lindex $argv 1]]
set exportZip [file normalize [lindex $argv 2]]
if {![file isfile $sourceCsv] || [file tail $sourceCsv] ne "FTIR_MP_references.csv"} {
    error "the official RefIMP FTIR_MP_references.csv is required"
}
if {[file exists $exportZip]} { error "export target already exists: $exportZip" }
set expectedHash 3ec55d86481da93b73f5f9f46e0c6d7c3d941165fd45beefeb84fb1305a0d19c
set actualHash [lindex [split [exec sha256sum -- $sourceCsv]] 0]
if {$actualHash ne $expectedHash} { error "RefIMP source SHA-256 mismatch" }
set libraryId tum.refimp.ftir.2022
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set api ::GX::ReferenceLibraryAPIv1
if {[file exists [${api}::libraryPath $libraryId]]} {
    error "reference library already exists: [${api}::libraryPath $libraryId]"
}
set sourceUrl https://mediatum.ub.tum.de/1656656
set citation {Weisser, Jana; Pohl, Teresa (2022), RefIMP µFTIR reference spectra, Technical University of Munich, mediaTUM 1656656}
${api}::createLibrary [dict create \
    library_id $libraryId name {RefIMP transmission micro-FTIR reference spectra} \
    version 2022-04-21 owner {Technical University of Munich} \
    source_identity $sourceUrl source_version 2022-04-21 \
    license CC-BY-SA-4.0 citation $citation \
    description {Fifteen RefIMP reference traces from FTIR_MP_references.csv. Values are retained as a relative transmission signal; the published source does not establish absolute ordinate calibration.}]
set labels {PP sand PE PS PLA PC PMMA cellulose PA PVC PUR protein varnish-like anodisc PET}
foreach label $labels {
    set id [string tolower $label]
    ${api}::upsertEntity $libraryId $id [dict create \
        display_name $label class {RefIMP reference material} \
        source_column $label source_identity $sourceUrl]
    set options [dict create \
        spectrum_id "$id-transmission-ftir" entity_id $id \
        display_name "$label transmission micro-FTIR" spectrum_kind IR \
        x_quantity wavenumber x_unit cm^-1 \
        y_quantity relative_transmission_signal y_representation transmission_signal y_unit 1 \
        x_column {wavenumbers [1/cm]} y_column $label delimiter {;} header 1 \
        source_identity "$sourceUrl#FTIR_MP_references.csv:$label" \
        metadata [dict create technique {transmission micro-FTIR} nominal_resolution {8 cm^-1} source_column $label ordinate_note {relative signal; no asserted absolute transmittance scale}] \
        provenance [dict create publisher {Technical University of Munich} source_url $sourceUrl license CC-BY-SA-4.0 citation $citation]]
    set imported [::GX::SpectrumImportAPIv1::importOneToLibrary $libraryId csv $sourceCsv $options]
    puts "IMPORTED $label [dict get $imported sample_count] samples [dict get $imported spectrum_hash]"
}
if {[llength [${api}::listEntities $libraryId]] != 15 || [llength [${api}::listSpectra $libraryId]] != 15} {
    error "RefIMP library does not contain exactly 15 entities and spectra"
}
set info [${api}::validateLibrary $libraryId]
${api}::exportLibrary $libraryId $exportZip
puts "PASS RefIMP library=$libraryId content_hash=[dict get $info content_hash] export=$exportZip"
