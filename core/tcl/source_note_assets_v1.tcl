# SPDX-License-Identifier: GPL-3.0-or-later
# Request-scoped transport admission subordinate to SOURCE_NOTE and existing
# ResourceManagement. No canonical store, Registry or portable path authority.
namespace eval ::GX::SourceNotes {variable assetPlans {};variable assetAllocations {}}
proc ::GX::_sourceNoteAssetSourcePins {source} {
    set result {}
    foreach key {owner_key file_key owner_revision authoring_revision source_sha256 source_revision} {dict set result $key [dict get $source $key]}
    return $result
}
proc ::GX::_sourceNoteAssetReferenceEqual {left right} {
    _sourceNoteReference $left;_sourceNoteReference $right
    if {[dict get $left owner] ne [dict get $right owner]} {return 0}
    set a [dict get $left reference];set b [dict get $right reference]
    if {[lsort [dict keys $a]] ne [lsort [dict keys $b]]} {return 0}
    dict for {key value} $a {if {$value ne [dict get $b $key]} {return 0}}
    return 1
}
proc ::GX::sourceNoteAssetPlanBuild {source sourceRef assets} {
    variable ::GX::SourceNotes::assetPlans
    variable ::GX::SourceNotes::assetAllocations
    _sourceNoteReference $sourceRef
    _documentAssetsValidate $assets
    set pins [_sourceNoteAssetSourcePins $source]
    set current [_sourceNoteOwner describe $sourceRef]
    if {[_sourceNoteAssetSourcePins $current] ne $pins} {error {Source changed before its image snapshot}}
    set allocation [resourceManagementAllocate source_note_assets [dict create kind directory category temporary lifetime request retention_seconds 0 expected_bytes 17825792]]
    set id [dict get $allocation id]
    dict set assetAllocations $id $allocation
    set channel {};set reader {};set receipt {}
    try {
        set root [dict get $allocation path]
        file mkdir [file join $root blobs];file attributes [file join $root blobs] -permissions 0700
        set rows {};set seen {};set total 0
        dict for {name reference} $assets {
            set info [interactiveDocumentResourceInfo $reference]
            set sha [dict get $info sha256];set count [dict get $info size_bytes]
            if {$count<24 || $count>4194304 || ![regexp {^[a-f0-9]{64}$} $sha]} {error {Source-note image must be a bounded PNG}}
            set path [file join $root blobs $sha.png]
            set head {}
            if {![dict exists $seen $sha]} {
                incr total $count
                if {$total>16777216} {error {Source-note images exceed the attachment budget}}
                set reader [interactiveDocumentResourceOpenReader $reference]
                set channel [open $path {WRONLY CREAT EXCL}];fconfigure $channel -translation binary -encoding binary
                set written 0
                while {$written<$count} {
                    set part [interactiveDocumentResourceNext $reader 1048576]
                    set chunk [dict get $part bytes]
                    if {[dict get $part count]<1 || [dict get $part offset]!=$written} {error {Source image reader made no consistent progress}}
                    if {$written==0} {set head [string range $chunk 0 23]}
                    puts -nonewline $channel $chunk;incr written [dict get $part count]
                }
                interactiveDocumentResourceCloseReader $reader;set reader {}
                close $channel;set channel {}
                file attributes $path -permissions 0444
                if {$written!=$count || [file size $path]!=$count || [sha256File $path] ne $sha} {error {Source-note image changed while staging its snapshot}}
                dict set seen $sha $head
            } else {set head [dict get $seen $sha]}
            binary scan $head H16@16II signature width height
            if {$signature ne {89504e470d0a1a0a} || $width<1 || $height<1 || $width>4096 || $height>4096} {error {Source-note PNG dimensions must be1..4096}}
            set metadata [format {{"format":"png","media_type":"image/png","filename":%s,"role":"markdown_image","width":%d,"height":%d,"scientific_authority":true,"disposable":false}} [viewerDevelopmentJsonString $name] $width $height]
            set origin {}
            if {[dict exists $reference metadata origin]} {
                set encoded [_viewerWorkspaceTypedJson [_nativeWorkspaceResourceOriginEncode [dict get $reference metadata origin]]]
                set hash [scriptRegistryHashBytes [encoding convertto utf-8 $encoded]]
                set origin ",\"origin_sha256\":[viewerDevelopmentJsonString $hash]"
            }
            lappend rows "[viewerDevelopmentJsonString $name]:\{\"sha256\":[viewerDevelopmentJsonString $sha],\"size_bytes\":$count,\"metadata\":$metadata$origin\}"
        }
        set index "\{\"schema\":\"gxtxt.source_asset_index.v1\",\"assets\":\{[join $rows ,]\}\}\n"
        set path [file join $root index.json]
        set channel [open $path {WRONLY CREAT EXCL}];fconfigure $channel -encoding utf-8 -translation lf
        puts -nonewline $channel $index;close $channel;set channel {};file attributes $path -permissions 0444
        if {[file size $path]>1048576} {error {Source image index exceeds1MiB}}
        set receipt [dict merge [dict create schema gxtxt.source_asset_plan.v1 allocation_id $id index_sha256 [sha256File $path] index_size [file size $path] source_ref $sourceRef] $pins]
        dict set assetPlans $id $receipt
        return $receipt
    } on error {message options} {
        if {$reader ne {}} {catch {interactiveDocumentResourceCloseReader $reader}}
        if {$channel ne {}} {catch {close $channel}}
        catch {sourceNoteAssetPlanClose [dict create allocation_id $id]}
        return -options $options $message
    }
}
proc ::GX::sourceNoteAssetPlanConsume {receipt source sourceRef} {
    variable ::GX::SourceNotes::assetPlans
    variable ::GX::SourceNotes::assetAllocations
    set id [dict get $receipt allocation_id]
    if {![dict exists $assetPlans $id] || ![dict exists $assetAllocations $id]} {error {Source image plan was not issued by this host or has already been consumed}}
    set expected [dict get $assetPlans $id]
    if {[lsort [dict keys $receipt]] ne [lsort [dict keys $expected]]} {error {Source image plan receipt fields changed}}
    dict for {key value} $expected {if {$key ne {source_ref} && [dict get $receipt $key] ne $value} {error {Source image plan receipt changed}}}
    if {![_sourceNoteAssetReferenceEqual [dict get $receipt source_ref] $sourceRef] || ![_sourceNoteAssetReferenceEqual [dict get $expected source_ref] $sourceRef]} {error {Source image plan belongs to a different source}}
    dict for {key value} [_sourceNoteAssetSourcePins $source] {if {[dict get $receipt $key] ne $value} {error {Source changed before image snapshot adoption}}}
    set allocation [resourceManagementInspect $id]
    if {![dict get $allocation managed] || [dict get $allocation kind] ne {directory} || [dict get $allocation subsystem] ne {source_note_assets} || [dict get $allocation owner_pid]!=[pid] || ![dict get $allocation owner_alive] || [dict get $allocation released] || [dict get $allocation removed]} {error {Source image plan requires this live host's request allocation}}
    set root [dict get $allocation path]
    file lstat $root stat
    if {$stat(type) ne {directory} || [list $stat(dev) $stat(ino)] ne [dict get $allocation identity] || $root ne [dict get $assetAllocations $id path]} {error {Source image allocation identity changed}}
    set path [file join $root index.json];file lstat $path stat
    if {$stat(type) ne {file} || $stat(nlink)!=1 || $stat(size)!=[dict get $receipt index_size] || [sha256File $path] ne [dict get $receipt index_sha256]} {error {Source image plan index changed}}
    dict unset assetPlans $id
    return [dict create directory $root index_sha256 [dict get $receipt index_sha256] index_size [dict get $receipt index_size]]
}
proc ::GX::sourceNoteAssetPlanClose {receipt} {
    variable ::GX::SourceNotes::assetPlans
    variable ::GX::SourceNotes::assetAllocations
    set id [dict get $receipt allocation_id]
    if {![dict exists $assetAllocations $id]} {error {Source image allocation is not owned by this request host}}
    set allocation [dict get $assetAllocations $id]
    if {[dict exists $assetPlans $id]} {dict unset assetPlans $id}
    resourceManagementRelease $id verified_orphan 0
    resourceManagementCleanup [list $id]
    if {![dict get [resourceManagementInspect $id] removed]} {error {Source image allocation cleanup requires review}}
    dict unset assetAllocations $id
    return closed
}
proc ::GX::sourceNoteAssetsMaterialize {capability sourceRef source expectedSession} {
    _sourceNoteActor $capability $sourceRef
    _documentSessionCheck $expectedSession
    set current [_sourceNoteOwner describe $sourceRef]
    if {[_sourceNoteAssetSourcePins $current] ne [_sourceNoteAssetSourcePins $source]} {error {Source changed before attaching its portable images}}
    set snapshots [datasetPublicationV2DictDefault $current asset_snapshots {}]
    if {[catch {dict size $snapshots}] || [dict size $snapshots]>32} {error {Invalid bounded source image snapshot roster}}
    if {![dict size $snapshots]} {return [dict create assets {} owner {}]}
    set total 0
    dict for {name record} $snapshots {
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,95}$} $name] || [dict get $record schema] ne {gxtxt.source_asset.v1} || ![regexp {^[a-f0-9]{64}$} [dict get $record sha256]] || [dict get $record blob_key] ne [dict get $record sha256]} {error {Invalid source image snapshot identity}}
        set size [dict get $record size_bytes]
        if {![string is entier -strict $size] || $size<24 || $size>4194304} {error {Source image exceeds4MiB}}
        incr total $size
        if {$total>16777216} {error {Source images exceed the canonical document's16MiB bound}}
    }
    set origin [dict create operation source_note_attachment owner [dict get $sourceRef owner] owner_key [dict get $current owner_key] file_key [dict get $current file_key]]
    set owner [datasetDocumentAssetOwnerCreate $capability $origin]
    set assets {}
    try {
        dict for {name record} $snapshots {
            set sha [dict get $record sha256];set size [dict get $record size_bytes]
            set request [dict create name $name count 1048576 expected_owner_revision [dict get $current owner_revision] expected_authoring_revision [dict get $current authoring_revision] expected_asset_sha256 $sha]
            set bytes {};set position 0
            while {$position<$size} {
                dict set request start $position
                set part [sourceNoteAssetRead $capability $sourceRef $request]
                if {[dict get $part size_bytes]!=$size} {error {Source image size changed during attachment}}
                append bytes [binary decode base64 [dict get $part bytes_base64]]
                incr position [dict get $part count]
            }
            if {[string length $bytes]!=$size || [scriptRegistryHashBytes $bytes] ne $sha} {error {Source image payload changed during attachment}}
            set metadata [dict get $record metadata]
            if {[lsort [dict keys $metadata]] ne {disposable filename format height media_type role scientific_authority width}
                || [dict get $metadata filename] ne $name || [dict get $metadata format] ne {png} || [dict get $metadata media_type] ne {image/png} || [dict get $metadata role] ne {markdown_image}} {error {Source image rendering metadata differs}}
            binary scan [string range $bytes 0 23] H16@16II signature width height
            if {$signature ne {89504e470d0a1a0a} || $width<1 || $height<1 || $width>4096 || $height>4096 || [dict get $metadata width]!=$width || [dict get $metadata height]!=$height} {error {Source image dimensions changed}}
            if {[dict exists $record origin_sha256]} {
                set hash [dict get $record origin_sha256]
                if {![regexp {^[a-f0-9]{64}$} $hash]} {error {Invalid inert source image origin digest}}
                dict set metadata source_snapshot_origin_sha256 $hash
            }
            dict set assets $name [datasetDocumentAssetWrite $capability $owner $name $metadata $bytes]
        }
        _documentSessionCheck $expectedSession
        set latest [_sourceNoteOwner describe $sourceRef]
        if {[_sourceNoteAssetSourcePins $latest] ne [_sourceNoteAssetSourcePins $current]} {error {Source changed before image attachment completed}}
        return [dict create assets $assets owner $owner]
    } on error {message options} {
        catch {datasetDocumentAssetOwnerClose $capability $owner}
        return -options $options $message
    }
}
