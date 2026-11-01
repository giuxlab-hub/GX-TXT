# SPDX-License-Identifier: GPL-3.0-or-later
# Inert source snapshots use the existing editor/renderer. This bounded cache is
# unsaved UI memory only; the immutable Registry/Project remains the authority.
namespace eval ::GX::SourceNoteEditor {variable assetProviders {};variable assetProviderSerial 0}
proc ::GX::_sourceNoteAssetProviderCreate {capability sourceRef note} {
    variable ::GX::SourceNoteEditor::assetProviders
    variable ::GX::SourceNoteEditor::assetProviderSerial
    if {[dict get $note state] eq {canonical}} {return {}}
    set assets [datasetPublicationV2DictDefault [dict get $note source] asset_snapshots {}]
    if {![dict size $assets]} {return {}}
    set token source-note-assets#[incr assetProviderSerial]
    dict set assetProviders $token [dict create capability $capability source_ref $sourceRef source [dict get $note source] assets $assets cache {}]
    return $token
}
proc ::GX::_sourceNoteAssetProviderDelete {token} {
    variable ::GX::SourceNoteEditor::assetProviders
    if {$token ne {}} {catch {dict unset assetProviders $token}}
}
proc ::GX::_sourceNoteAssetProvider {token operation {name {}}} {
    variable ::GX::SourceNoteEditor::assetProviders
    if {![dict exists $assetProviders $token]} {error {Source image snapshot host has closed}}
    set record [dict get $assetProviders $token]
    if {$operation eq {catalog}} {return [dict get $record assets]}
    if {$operation ne {read} || ![dict exists $record assets $name]} {error {Choose an exact source snapshot image}}
    if {[dict exists $record cache $name]} {return [dict get $record cache $name]}
    set asset [dict get $record assets $name];set source [dict get $record source]
    set size [dict get $asset size_bytes];set sha [dict get $asset sha256]
    if {![string is entier -strict $size] || $size<24 || $size>4194304 || ![regexp {^[a-f0-9]{64}$} $sha]} {error {Invalid bounded source PNG identity}}
    set request [dict create name $name count 1048576 expected_owner_revision [dict get $source owner_revision] expected_authoring_revision [dict get $source authoring_revision] expected_asset_sha256 $sha]
    set bytes {};set offset 0
    while {$offset<$size} {
        dict set request start $offset
        set chunk [sourceNoteAssetRead [dict get $record capability] [dict get $record source_ref] $request]
        set raw [binary decode base64 -strict [dict get $chunk bytes_base64]]
        if {[dict get $chunk sha256] ne $sha || [dict get $chunk size_bytes]!=$size || [dict get $chunk offset]!=$offset || [dict get $chunk count]!=[string length $raw] || [string length $raw]<1 || [string length $raw]>1048576 || $offset+[string length $raw]>$size} {error {Source image chunk identity changed}}
        append bytes $raw;incr offset [string length $raw]
        if {[dict get $chunk eof] != ($offset==$size)} {error {Source image stream completeness changed}}
    }
    if {[scriptRegistryHashBytes $bytes] ne $sha} {error {Source image snapshot bytes changed}}
    set total [string length $bytes]
    dict for {key raw} [dict get $record cache] {incr total [string length $raw]}
    if {$total>16777216} {error {Source snapshot preview cache exceeds16MiB}}
    dict set assetProviders $token cache $name $bytes
    return $bytes
}
proc ::GX::_sourceNoteEditorAssetProviderRefresh {handle} {
    variable ::GX::SourceNoteEditor::bindings
    variable ::GX::SourceNoteEditor::assetProviders
    variable ::GX::DocumentSource::editors
    set binding [dict get $bindings $handle];set token [datasetPublicationV2DictDefault $binding asset_provider {}]
    set note [dict get $binding receipt]
    if {[dict get $note state] eq {canonical}} {
        _sourceNoteAssetProviderDelete $token
        dict set bindings $handle asset_provider {}
        dict set editors $handle options asset_provider {}
        return
    }
    if {$token eq {}} {
        set token [_sourceNoteAssetProviderCreate [dict get $binding capability] [dict get $binding source_ref] $note]
        dict set bindings $handle asset_provider $token
    } elseif {[dict exists $assetProviders $token]} {
        set assets [datasetPublicationV2DictDefault [dict get $note source] asset_snapshots {}]
        set cache [dict get $assetProviders $token cache]
        foreach name [dict keys $cache] {
            if {![dict exists $assets $name] || ![dict exists $assetProviders $token assets $name] || [dict get $assets $name sha256] ne [dict get $assetProviders $token assets $name sha256]} {dict unset cache $name}
        }
        dict set assetProviders $token assets $assets;dict set assetProviders $token cache $cache
        dict set assetProviders $token source [dict get $note source];dict set assetProviders $token source_ref [dict get $binding source_ref]
    }
    dict set editors $handle options asset_provider [expr {$token eq {}?{}:[list ::GX::_sourceNoteAssetProvider $token]}]
}
