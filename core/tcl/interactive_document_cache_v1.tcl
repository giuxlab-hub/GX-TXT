# SPDX-License-Identifier: GPL-3.0-or-later
# Derived process-local resources inside the existing Document owner. Neither
# cached bytes nor metadata replace canonical payload SHA/revision authority.
namespace eval ::GX::DocumentSnapshotCache {variable session {};variable registries {};variable fallbacks 0;variable lastFallback {}}
proc ::GX::_interactiveDocumentCacheEnsure {} {
    if {$::tcl_platform(os) ne {Linux} || ![llength [info commands ::GX::documentNativeEnsure]]} {return 0}
    # Caching is additive. Legacy Document operations still work if this
    # optional native capability is unavailable on a different platform/build.
    if {[catch {documentNativeEnsure}]} {return 0}
    return [expr {[llength [info commands ::GX::NativeDocument::snapshotCache]]>0}]
}
proc ::GX::_interactiveDocumentCacheScope {} {
    variable ::GX::DocumentSnapshotCache::session
    variable ::GX::DocumentSnapshotCache::registries
    _interactiveDocumentSessionChanged
    set current $::GX::DocumentSessionScope::token
    if {$current ne $session} {
        set session $current;set registries {}
        if {[llength [info commands ::GX::NativeDocument::snapshotCache]]} {::GX::NativeDocument::snapshotCache clear}
    }
}
proc ::GX::_interactiveDocumentRegistryCacheProbe {path} {
    variable ::GX::DocumentSnapshotCache::registries
    if {![_interactiveDocumentCacheEnsure]} {return {}}
    _interactiveDocumentCacheScope
    # Legacy linked/oversized registries retain their existing uncached reader.
    # A successful probe validates the complete current native file identity.
    if {[catch {set identity [::GX::NativeDocument::snapshotCache identity $path]}]} {return {}}
    if {[dict get $identity size]>4194304} {return {}}
    if {[dict exists $registries $path] && [dict get $registries $path identity] eq $identity} {return [dict get $registries $path]}
    return [dict create identity $identity]
}
proc ::GX::_interactiveDocumentRegistryCacheAdmit {path captured registry} {
    variable ::GX::DocumentSnapshotCache::registries
    set after [::GX::NativeDocument::snapshotCache identity $path]
    if {$after ne [dict get $captured identity]} {error {Interactive Document registry changed during metadata validation; retry}}
    # Never associate parse results with a different captured source identity.
    # Session switching clears this map; one canonical registry is retained.
    set registries [dict create $path [dict create identity $after registry $registry]]
}
proc ::GX::interactiveDocumentMetadataBatch {documents} {
    if {[llength $documents]>4096} {error {Document metadata batch exceeds4096 identities}}
    set registry [_interactiveDocumentRegistryRead [_interactiveDocumentRequireSession]];set result {}
    foreach document $documents {
        if {![interactiveDocumentIdValid $document] || ![dict exists $registry $document]} {error {Document owner is unavailable}}
        dict set result $document [_interactiveDocumentPublicMetadata [dict get $registry $document]]
    }
    return $result
}
proc ::GX::interactiveDocumentSourceIdentities {documents} {
    if {[llength $documents]>4096} {error {Document identity batch exceeds4096 entries}}
    if {![_interactiveDocumentCacheEnsure]} {error {Checked native Document identity is unavailable}}
    _interactiveDocumentCacheScope
    set session [_interactiveDocumentRequireSession];set registry [_interactiveDocumentRegistryRead $session];set result {}
    foreach document $documents {
        if {![interactiveDocumentIdValid $document] || ![dict exists $registry $document]} {error {Document owner is unavailable}}
        set item [dict get $registry $document]
        set metadata [_interactiveDocumentPublicMetadata $item]
        if {[datasetPublicationV2DictDefault $item native_workspace 0]} {
            dict set metadata source_identity [dict create api_id NATIVE_WORKSPACE_API_v1 id $document generation [dict get $item generation] revision [dict get $item revision] sha256 [dict get $item sha256]]
        } else {dict set metadata source_identity [::GX::NativeDocument::snapshotCache identity [_interactiveDocumentPayloadPath $session $item]]}
        dict set result $document $metadata
    }
    return $result
}
proc ::GX::interactiveDocumentReadCached {document {historyPolicy stored}} {
    if {[_nativeWorkspaceExists $document]} {return [interactiveDocumentRead $document $historyPolicy]}
    if {$historyPolicy ni {stored current}} {error {Unknown Document History read policy}}
    if {$historyPolicy eq {current} && [llength [info commands _historyDocumentBarrier]]} {_historyDocumentBarrier $document}
    if {![_interactiveDocumentCacheEnsure]} {return [interactiveDocumentRead $document $historyPolicy]}
    _interactiveDocumentCacheScope
    set session [_interactiveDocumentRequireSession];set registry [_interactiveDocumentRegistryRead $session]
    if {![interactiveDocumentIdValid $document] || ![dict exists $registry $document]} {error {Document owner is unavailable}}
    set item [dict get $registry $document]
    if {[_sessionWorkspaceKnownObsolete $item]} {error {Obsolete Workspace body cache reads are unsupported}}
    set path [_interactiveDocumentPayloadPath $session $item]
    if {[catch {set captured [::GX::NativeDocument::snapshotCache read $path [string tolower [dict get $item sha256]]]} message options]} {
        if {[dict exists $options -errorcode] && [dict get $options -errorcode] eq {GXTXT DOCUMENT CACHE SHA_MISMATCH}} {return -options $options $message}
        # An optional cache bound / platform limitation must not impose a new
        # payload-size or filesystem restriction on the established public API.
        incr ::GX::DocumentSnapshotCache::fallbacks
        set ::GX::DocumentSnapshotCache::lastFallback $message
        return [interactiveDocumentRead $document stored]
    }
    set payload [encoding convertfrom utf-8 [dict get $captured bytes]]
    # Existing canonical text uses LF; preserve the public reader's translation.
    set payload [string map [list \r\n \n \r \n] $payload]
    if {[llength [info commands _parameterWorkspaceMetadataSeed]]} {_parameterWorkspaceMetadataSeed $session $item $payload}
    set out [_interactiveDocumentPublicMetadata $item];dict set out payload $payload
    return $out
}
proc ::GX::interactiveDocumentCacheStatus {} {
    if {![_interactiveDocumentCacheEnsure]} {return [dict create available 0 policy uncached]}
    _interactiveDocumentCacheScope
    set metadataBytes 0
    dict for {path entry} $::GX::DocumentSnapshotCache::registries {incr metadataBytes [dict get $entry identity size]}
    return [dict merge [::GX::NativeDocument::snapshotCache status] [dict create available 1 session_token $::GX::DocumentSnapshotCache::session metadata_entries [dict size $::GX::DocumentSnapshotCache::registries] metadata_source_bytes $metadataBytes metadata_limit_bytes 4194304 fallback_reads $::GX::DocumentSnapshotCache::fallbacks last_fallback $::GX::DocumentSnapshotCache::lastFallback]]
}
proc ::GX::interactiveDocumentCacheConfigure {options} {
    if {![_interactiveDocumentCacheEnsure]} {error {Native Document cache is unavailable}}
    foreach key [dict keys $options] {if {$key ni {byte_budget entry_budget}} {error {Unknown Document cache policy}}}
    set status [interactiveDocumentCacheStatus]
    set bytes [datasetPublicationV2DictDefault $options byte_budget [dict get $status byte_budget]]
    set entries [datasetPublicationV2DictDefault $options entry_budget [dict get $status entry_budget]]
    return [::GX::NativeDocument::snapshotCache configure $bytes $entries]
}
proc ::GX::interactiveDocumentCacheClear {} {
    set ::GX::DocumentSnapshotCache::registries {}
    if {[_interactiveDocumentCacheEnsure]} {::GX::NativeDocument::snapshotCache clear}
    return [dict create cleared 1 scientific_mutation 0]
}
