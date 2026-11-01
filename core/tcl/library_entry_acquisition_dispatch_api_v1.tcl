# SPDX-License-Identifier: GPL-3.0-or-later
# Host-only explicit Library -> existing Acquisition dispatch. No Dataset writer.
namespace eval ::GX::LibraryEntryAcquisitionDispatchAPIv1 {}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::apiInfo {} {
    return [dict create api_name LIBRARY_ENTRY_ACQUISITION_DISPATCH_API_v1 api_version 1 operations {compatibleHandlers inspectSelection importSelected} session_import explicit source_owner SCIENTIFIC_LIBRARY_MANAGER_API_v1 publication_owner ACQUISITION_HANDLER_PLUGIN_API_v1]
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::_strings {fields} {
    set encoded {}
    dict for {key value} $fields {lappend encoded "[::GX::viewerDevelopmentJsonString $key]:[::GX::viewerDevelopmentJsonString $value]"}
    return \{[join $encoded ,]\}
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::_host {} {
    if {[info exists ::GX::DatasetPrivate::activeContext] && $::GX::DatasetPrivate::activeContext ne {}} {error {Library acquisition selection requires the user/admin host}}
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::compatibleHandlers {contract mediaType {recordType {}}} {
    set result {}
    foreach id $::GX::moduleOrder {
        if {[::GX::moduleField $id kind {}] ne {acquisition} || ![::GX::moduleIsEnabled $id] || ![::GX::acquisitionHandlerHasPluginDescriptor $id]} continue
        set fields $::GX::moduleCatalog($id,dict)
        set outputs [::GX::splitList [::GX::descriptorValue $fields outputs datasets {}]]
        set matches 0
        foreach output $outputs {if {[::GX::contractSatisfies $output $contract]} {set matches 1;break}}
        if {$contract eq {} || !$matches} continue
        set types [::GX::splitList [::GX::descriptorValue $fields library_acquisition record_types {}]]
        if {$types ne {} && $recordType ni $types} continue
        set media {}
        foreach format [::GX::splitList [::GX::descriptorValue $fields acquisition_handler formats {}]] {
            set mime [::GX::descriptorValue $fields acquisition_format.$format mime {}]
            if {$mime ne {}} {lappend media $mime}
        }
        if {$media eq {} && $types eq {}} continue
        if {$media ne {} && $mediaType ni $media} continue
        lappend result $id
    }
    return $result
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::_stage {selection allocation} {
    foreach key {reference resource_index} {if {![dict exists $selection $key]} {error "Library selection requires $key"}}
    set index [dict get $selection resource_index]
    if {![string is integer -strict $index] || $index < -1} {error {Invalid Library resource selection}}
    set parameters [format {{"reference":%s,"resource_index":%s,"output_dir":%s}} [_strings [dict get $selection reference]] $index [::GX::viewerDevelopmentJsonString [dict get $allocation path]]]
    set staged [::GX::ScientificLibraryManagerAPIv1::domainRequest stage $parameters]
    _verifyContext $staged
    return $staged
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::_verifyContext {staged} {
    if {![dict exists $staged context_path]} {
        if {[file exists [file join [file dirname [dict get $staged source_path]] gxtxt-library-entry.json]]} {error {Orphan Library acquisition context}}
        return
    }
    set path [file normalize [dict get $staged context_path]]
    set expected [file join [file dirname [file normalize [dict get $staged source_path]]] gxtxt-library-entry.json]
    if {$path ne $expected || ![file isfile $path] || [file size $path]>1048576 || [::GX::sha256File $path] ne [dict get $staged context_sha256]} {error {Pinned Library acquisition context changed}}
    if {[::GX::sha256File [dict get $staged source_path]] ne [dict get $staged sha256]} {error {Pinned Library acquisition source changed}}
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::inspectSelection {selection} {
    _host
    set allocation [::GX::resourceManagementAllocate scientific_library [dict create kind directory lifetime operation retention_seconds 0]]
    try {
        set staged [_stage $selection $allocation]
        set detail [::GX::ScientificLibraryManagerAPIv1::domainRequest detail [format {{"reference":%s}} [_strings [dict get $selection reference]]]]
        set handlers [compatibleHandlers [dict get $staged content_contract] [dict get $staged media_type] [dict get $detail record_type]]
        set inspections {};set recognized {}
        foreach handler $handlers {
            _verifyContext $staged
            set inspection [::GX::acquisitionHandlerInspect $handler [dict get $staged source_path]]
            _verifyContext $staged
            dict set inspections $handler $inspection
            if {[::GX::datasetPublicationV2DictDefault $inspection recognized 0]} {lappend recognized $handler}
        }
        return [dict merge [dict remove $staged source_path context_path result_json] [dict create compatible_handlers $recognized inspections $inspections]]
    } finally {
        ::GX::resourceManagementRelease [dict get $allocation id]
        ::GX::resourceManagementCleanup [list [dict get $allocation id]]
    }
}
proc ::GX::LibraryEntryAcquisitionDispatchAPIv1::importSelected {session selections {destinationNamespace {}}} {
    _host
    if {[llength $selections]<1 || [llength $selections]>100} {error {Explicitly select between 1 and 100 Library representations}}
    set session [file normalize $session]
    if {![file isdirectory $session]} {error {Choose an existing target Session}}
    # Optional seventh argument belongs to the existing Acquisition transaction.
    # Public privacy wrappers may be variadic; the actual owner admits the
    # seventh options argument. A six-argument predecessor refuses that call
    # before any import, instead of silently losing pinned provenance.
    set receipts {}
    foreach selection $selections {
        set allocation {};set imported {}
        if {[catch {
            foreach key {handler_id dataset_id expected_sha256} {if {![dict exists $selection $key]} {error "Reviewed selection requires $key"}}
            ::GX::acquisitionHandlerValidateDatasetId [dict get $selection dataset_id]
            set allocation [::GX::resourceManagementAllocate scientific_library [dict create kind directory lifetime operation session $session retention_seconds 0]]
            set staged [_stage $selection $allocation]
            if {[dict get $staged sha256] ne [dict get $selection expected_sha256]} {error {Library source bytes changed after review}}
            set detail [::GX::ScientificLibraryManagerAPIv1::domainRequest detail [format {{"reference":%s}} [_strings [dict get $selection reference]]]]
            set handlers [compatibleHandlers [dict get $staged content_contract] [dict get $staged media_type] [dict get $detail record_type]]
            set handler [dict get $selection handler_id]
            if {$handler ni $handlers} {error {Selected Acquisition Handler is absent, disabled or incompatible}}
            set provenance {}
            foreach key {library_id entry_id revision content_sha256 source_id sha256} {dict set provenance library.$key [dict get $staged $key]}
            if {[dict exists $staged context_sha256]} {dict set provenance library.context_sha256 [dict get $staged context_sha256]}
            _verifyContext $staged
            set imported [::GX::acquisitionHandlerImportSourceToSession $handler $session [dict get $staged source_path] [dict get $selection dataset_id] [dict get $staged content_contract] {} [dict create source_provenance $provenance destination_namespace $destinationNamespace]]
        } message options]} {
            lappend receipts [dict create status failed selection $selection error $message]
        } else {
            lappend receipts [dict create status completed selection $selection dataset_ids $imported source_sha256 [dict get $staged sha256] handler_id $handler]
        }
        if {$allocation ne {}} {::GX::resourceManagementRelease [dict get $allocation id];::GX::resourceManagementCleanup [list [dict get $allocation id]]}
    }
    return [dict create schema gxtxt.library_acquisition_batch.v1 receipts $receipts atomic_per_entry 1]
}
