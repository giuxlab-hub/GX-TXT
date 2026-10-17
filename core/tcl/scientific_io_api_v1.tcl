# SPDX-License-Identifier: GPL-3.0-or-later
# Opaque local source transport, backed by existing Dataset/Document authorities.
namespace eval ::GX::ScientificIO {variable scopes {};variable entries {};variable entryTokens {};variable serial 0}
proc ::GX::scientificIoApiInfo {} {return [dict create api_id SCIENTIFIC_IO_API_v1 api_version 1 operations {capabilities browse import describe read export} authorization host_user_admin scope_lifetime current_Session transport local codecs opaque_file remote_backends not_implemented]}
proc ::GX::scientificIoCapabilities {} {return [dict create transport local identity canonical_Dataset location_opaque 1 formats_independent 1 metadata_browse 1 copy 1 verified_reference 1 random_read 1 bounded_read 1 offline_identity_preserved 1 remote 0 hostile_code_sandbox 0]}
proc ::GX::_scientificIoCall {root operation relative offset count {expected {}} {destination {}}} {
    set rc [catch {exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_scientific_io.py] $root $operation $relative $offset $count $expected $destination} response]
    if {[catch {dict get $response ok} ok]||!$ok} {if {![catch {dict get $response error} message]} {error $message};error $response}
    return [dict get $response result]
}
# Host-only explicit user/admin grant, never a Script Bridge operation.
proc ::GX::scientificIoAuthorize {root producers {allowImport 0} {allowExport 0}} {
    variable ::GX::ScientificIO::scopes;variable ::GX::ScientificIO::entries;variable ::GX::ScientificIO::entryTokens;variable ::GX::ScientificIO::serial
    dict for {old entry} $scopes {if {[dict get $entry session_token] ne [interactiveDocumentSessionToken]} {dict unset scopes $old}}
    if {![dict size $scopes]} {set entries {};set entryTokens {}}
    if {[dict size $scopes]>=32} {error {Authorized source scope budget is32 per host Session}}
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Only user/admin may authorize source scopes}}
    if {![string is boolean -strict $allowImport]||![string is boolean -strict $allowExport]} {error {Invalid content authorization}}
    set root [file normalize $root]
    if {![file isdirectory $root]||[file type $root] eq {link}} {error {Choose an existing ordinary source directory}}
    foreach producer $producers {datasetPublicationV2ValidateId module $producer}
    _scientificIoCall $root list {} 0 1
    set token "scientific-scope#[pid]-[incr serial]"
    dict set scopes $token [dict create root $root producers $producers allow_import $allowImport allow_export $allowExport session_token [interactiveDocumentSessionToken]]
    return $token
}
proc ::GX::_scientificIoScope {token producer} {
    variable ::GX::ScientificIO::scopes
    if {![dict exists $scopes $token]} {error {Unknown authorized source scope}}
    set scope [dict get $scopes $token]
    if {[dict get $scope session_token] ne [interactiveDocumentSessionToken]||$producer ni [dict get $scope producers]} {error {Source scope is unavailable to this producer/Session}}
    if {$::GX::DatasetPrivate::activeContext ne {}&&[dict get $::GX::DatasetPrivate::activeContext module_id] ne $producer} {error {Source producer identity mismatch}}
    return $scope
}
proc ::GX::scientificIoBrowse {scopeToken producer {directoryToken {}} {offset 0} {count 100}} {
    variable ::GX::ScientificIO::entries;variable ::GX::ScientificIO::entryTokens;variable ::GX::ScientificIO::serial
    set scope [_scientificIoScope $scopeToken $producer];set relative {}
    if {$directoryToken ne {}} {
        if {![dict exists $entries $directoryToken]||[dict get $entries $directoryToken scope] ne $scopeToken||[dict get $entries $directoryToken kind] ne {directory}} {error {Unknown directory entry token}}
        set relative [dict get $entries $directoryToken relative]
    }
    set page [_scientificIoCall [dict get $scope root] list $relative $offset $count]
    set public {}
    foreach entry [dict get $page entries] {
        set identityKey [list $scopeToken [dict get $entry relative] [dict get $entry identity]]
        if {[dict exists $entryTokens $identityKey]} {set token [dict get $entryTokens $identityKey]} else {
            if {[dict size $entryTokens]>=20000} {error {Source entry budget is20000 per host Session; use a narrower authorized scope}}
            set token "scientific-entry#[pid]-[incr serial]"
            dict set entryTokens $identityKey $token
        }
        dict set entry scope $scopeToken
        dict set entries $token $entry
        lappend public [dict merge [dict remove $entry scope relative identity] [dict create entry_token $token availability metadata_only]]
    }
    dict set page entries $public
    return $page
}
proc ::GX::scientificIoImport {scopeToken producer entryToken request} {
    variable ::GX::ScientificIO::entries
    set scope [_scientificIoScope $scopeToken $producer]
    if {![dict get $scope allow_import]} {error {Browsing does not authorize content import}}
    if {![dict exists $entries $entryToken]||[dict get $entries $entryToken scope] ne $scopeToken||[dict get $entries $entryToken kind] ne {file}} {error {Unknown authorized file entry}}
    set entry [dict get $entries $entryToken]
    foreach key [dict keys $request] {if {$key ni {dataset_id contract format storage_kind media_type policy expected_sha256 dataset_namespace}} {error "Unknown scientific import option '$key'"}}
    foreach key {dataset_id contract format storage_kind media_type policy} {if {![dict exists $request $key]} {error "Scientific import requires '$key'"}}
    if {[dict get $request policy] ni {copy reference}} {error {Scientific import supports copy or verified reference}}
    set verification [expr {[dict get $request storage_kind] eq {text}?{text}:{read}}]
    set source [_scientificIoCall [dict get $scope root] $verification [dict get $entry relative] 0 1 [datasetPublicationV2DictDefault $request expected_sha256 {}]]
    if {[dict get $source identity] ne [dict get $entry identity]} {error {Source entry changed after browsing; browse again}}
    set session [_interactiveDocumentRequireSession]
    set definition [dict remove $request policy expected_sha256]
    dict set definition immutable 1
    dict set definition source_file [file join [dict get $scope root] [dict get $entry relative]]
    dict set definition provenance "CORE authorized source import; source SHA [dict get $source sha256]; policy [dict get $request policy]"
    if {[dict get $request policy] eq {reference}} {
        dict set definition verified_reference [dict create source_root [dict get $scope root] source_relative [dict get $entry relative] identity [dict get $source identity] sha256 [dict get $source sha256]]
    }
    set allocation {}
    try {
        if {[dict get $request policy] eq {copy}} {
            set allocation [resourceManagementAllocate scientific_io [dict create kind directory session $session lifetime operation expected_bytes [dict get $source size_bytes]]]
            set materialized [file join [dict get $allocation path] imported-source]
            set copied [_scientificIoCall [dict get $scope root] copy [dict get $entry relative] 0 1 [dict get $source sha256] $materialized]
            if {[dict get $copied identity] ne [dict get $entry identity]} {error {Source changed during copy}}
            dict set definition source_file $materialized
            dict set definition verified_source_sha256 [dict get $source sha256]
        }
        set receipt [datasetFilePublicationPublish $session $producer $definition]
    } finally {
        if {$allocation ne {}} {resourceManagementRelease [dict get $allocation id];resourceManagementCleanup [list [dict get $allocation id]]}
    }
    return [dict remove $receipt path]
}
proc ::GX::scientificIoDescribeDataset {id} {
    set session [_interactiveDocumentRequireSession];loadDatasetRegistry $session
    if {[datasetField $id id {}] eq {}} {error {Unknown canonical Dataset}}
    set result [dict create dataset_id $id format [datasetField $id format {}] contract [datasetField $id contract {}] content_sha256 [datasetField $id sha256 [datasetField $id canonical_sha256 {}]] policy [datasetField $id source_storage_policy copy] availability available readonly 1]
    set path [datasetResolvePath $session $id]
    if {![file isfile $path]} {dict set result availability unavailable}
    return $result
}
proc ::GX::scientificIoReadDataset {id {offset 0} {count 65536}} {
    set description [scientificIoDescribeDataset $id]
    if {[dict get $description availability] ne {available}} {return $description}
    set path [datasetResolvePath [_interactiveDocumentRequireSession] $id]
    set root [datasetField $id external_source_root [file dirname $path]]
    set relative [datasetField $id external_source_relative [file tail $path]]
    set page [_scientificIoCall $root read $relative $offset $count [dict get $description content_sha256]]
    return [dict merge $description [dict remove $page identity]]
}

proc ::GX::scientificIoExportDataset {scopeToken producer id filename} {
    set scope [_scientificIoScope $scopeToken $producer]
    if {![dict get $scope allow_export]} {error {This scope does not authorize export}}
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]{0,191}$} $filename]} {error {Export requires a single safe leaf name}}
    set descriptor [scientificIoDescribeDataset $id]
    if {[dict get $descriptor availability] ne {available}} {error {Canonical source is unavailable}}
    set destination [file join [dict get $scope root] $filename]
    set receipt [filePublicationPublishBundle [list [dict create id export destination $destination writer [list ::GX::_scientificIoExportWriter $id [dict get $descriptor content_sha256]]]]]
    set public [dict get $receipt files export]
    return [dict merge [dict remove $public destination] [dict create dataset_id $id filename $filename]]
}
proc ::GX::_scientificIoExportWriter {id expected channel context} {
    set offset 0
    while {1} {
        set page [scientificIoReadDataset $id $offset 1048576]
        if {![dict exists $page sha256]||[dict get $page sha256] ne $expected} {error {Source changed during export}}
        set bytes [binary decode base64 [dict get $page bytes_base64]]
        puts -nonewline $channel $bytes
        if {[string length $bytes]<1048576} break
        set offset [dict get $page next_offset]
    }
}
