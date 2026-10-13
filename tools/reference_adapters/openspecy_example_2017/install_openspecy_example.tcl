#!/usr/bin/env tclsh
# Import only the audited, source-declared-public-domain example; never a bulk OSF mirror.
if {[llength $argv] != 3} { error "usage: install_openspecy_example.tcl FRAMEWORK_ROOT ORIGINAL_JCAMP NEW_EXPORT_ZIP" }
lassign $argv framework sourcePath exportPath
set framework [file normalize $framework]
set sourcePath [file normalize $sourcePath]
set exportPath [file normalize $exportPath]
set expected 5dc366d7a86ac372a5328c33d94f87f210aee456cef6feed369ccec72379b1bf
if {![file isfile $sourcePath] || [file exists $exportPath]} { error "Original source missing or export target exists" }
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
if {[::GX::sha256File $sourcePath] ne $expected} { error "OpenSpecy example SHA-256 changed; re-audit source and rights" }
set api ::GX::ReferenceLibraryAPIv1
set id openspecy.example.nitrocellulose.2017
if {[file exists [${api}::libraryPath $id]]} { error "Reference library already exists" }
${api}::createLibrary [dict create library_id $id name {OpenSpecy package example: nitrocellulose} \
    version 2017.03.0 owner external_source source OpenSpecy-package source_version {sample header March 2017} \
    retrieval_date 2026-09-24 license {source-header: Public domain} \
    rights {single source-declared-public-domain example; OSF bulk-library rights not inferred} \
    citation {OpenSpecy package fitr_nitrocellulose.jdx; source header credits PNNL Under IARPA Contract}]
${api}::upsertEntity $id nitrocellulose [dict create display_name Nitrocellulose cas 9004-70-0 phase solid]
set spectrum [::GX::SpectrumImportAPIv1::parseJcamp $sourcePath [dict create \
    spectrum_id nitrocellulose-reflectance-2017 entity_id nitrocellulose \
    display_name {Nitrocellulose diffuse reflectance, PNNL/IARPA example} \
    provenance [dict create acquired_via {OpenSpecy package example} source_sha256 $expected]]]
if {[dict get $spectrum sample_count] != 7154 || [dict get $spectrum y_representation] ne "reflectance"} {
    error "Real example numerical/semantic audit failed"
}
${api}::addSpectrum $id $spectrum
set checked [${api}::validateLibrary $id]
if {[llength [${api}::listSpectra $id]] != 1} { error "Library spectrum count mismatch" }
${api}::exportLibrary $id $exportPath
puts "PASS installed one real OpenSpecy package example, content_hash=[dict get $checked content_hash], export=$exportPath"
