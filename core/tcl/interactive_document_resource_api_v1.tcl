# SPDX-License-Identifier: GPL-3.0-or-later
# Content-addressed bulk resources owned by a real Interactive Document.
namespace eval ::GX::DocumentResource {variable writers {};variable readers {};variable serial 0}
proc ::GX::interactiveDocumentResourceApiInfo {} {
    return [dict create api_id INTERACTIVE_DOCUMENT_RESOURCE_API_v1 api_version 1 operations {open_writer append finalize abort info read_chunk read_ranges open_reader reader_info next close_reader references remap_references collect import_numeric native2d_store native2d_restore native2d_restore_with_gaps} chunk_bytes_max 1048576 implicit_dataset_publication 0]
}
proc ::GX::_documentResourceRoot {document {allowRetired 0}} {
    if {![interactiveDocumentIdValid $document]} {error "Invalid Document resource owner"}
    set root [file join [_interactiveDocumentRequireSession] metadata interactive_document_resources $document]
    set probe [_interactiveDocumentRequireSession]
    foreach part [list metadata interactive_document_resources $document] {
        set probe [file join $probe $part]
        if {![catch {file lstat $probe status}]&&$status(type) eq "link"} {error "Document resource symlinks are forbidden"}
    }
    # Resource ownership is registry identity/generation authority. Reading and
    # hashing the complete scientific payload for every resource reference
    # makes history/recipe collection quadratic in document size.
    if {[interactiveDocumentExists $document]} {} elseif {$allowRetired} {
        set marker [file join $root .retired.ini]
        if {![file isfile $marker]||[file type $marker] eq "link"} {error "Document resource owner does not exist"}
        set retired [parseIni $marker]
        if {![dict exists $retired resource_owner.document_id]||[dict get $retired resource_owner.document_id] ne $document||![dict exists $retired resource_owner.generation]} {error "Retired Document resource owner is corrupt"}
    } else {error "Interactive Document '$document' does not exist in the current Session"}
    return $root
}
proc ::GX::_documentResourceOwnerGeneration {document} {
    set registry [_interactiveDocumentRegistryRead [_interactiveDocumentRequireSession]]
    if {[dict exists $registry $document]} {return [dict get $registry $document generation]}
    return [dict get [parseIni [file join [_documentResourceRoot $document 1] .retired.ini]] resource_owner.generation]
}
proc ::GX::interactiveDocumentResourceOpenWriter {document metadata} {
    if {![dict exists $metadata origin]} {dict set metadata origin [_scientificResourceOrigin $document managed_resource]}
    variable ::GX::DocumentResource::writers;variable ::GX::DocumentResource::serial
    if {[catch {dict size $metadata}]||![dict exists $metadata format]} {error "Document resource metadata needs a format"}
    set root [_documentResourceRoot $document];file mkdir $root
    set channel [file tempfile temporary [file join $root .pending-]]
    fconfigure $channel -translation binary -encoding binary
    file stat $temporary temporaryStatus
    set token "document-resource-writer#[pid]-[incr serial]"
    dict set writers $token [dict create channel $channel temporary $temporary temporary_identity [list $temporaryStatus(dev) $temporaryStatus(ino)] session [_interactiveDocumentRequireSession] session_token [interactiveDocumentSessionToken] owner_generation [_documentResourceOwnerGeneration $document] document $document metadata $metadata bytes 0]
    return $token
}
proc ::GX::_documentResourceWriter {token} {
    variable ::GX::DocumentResource::writers
    if {![dict exists $writers $token]} {error "Unknown or closed Document resource writer"}
    set writer [dict get $writers $token]
    if {[dict get $writer session_token] ne [interactiveDocumentSessionToken]} {error "Document resource writer belongs to another Session lifetime"}
    _documentResourceRoot [dict get $writer document]
    if {[dict get $writer owner_generation] ne [_documentResourceOwnerGeneration [dict get $writer document]]} {error "Document resource writer owner was replaced"}
    return $writer
}
proc ::GX::interactiveDocumentResourceAppend {token bytes} {
    variable ::GX::DocumentResource::writers
    set writer [_documentResourceWriter $token]
    set raw [binary format a* $bytes]
    if {$raw ne $bytes} {error "Document resource input must contain binary bytes; encode Unicode explicitly"}
    set bytes $raw
    set size [string length $bytes]
    if {$size>1048576} {error "Document resource chunk exceeds 1 MiB"}
    puts -nonewline [dict get $writer channel] $bytes
    dict incr writer bytes $size;dict set writers $token $writer
    return $size
}
proc ::GX::interactiveDocumentResourceAbort {token} {
    variable ::GX::DocumentResource::writers
    if {![dict exists $writers $token]} {error "Unknown or closed Document resource writer"}
    set writer [dict get $writers $token]
    if {[dict get $writer channel] ne ""} {close [dict get $writer channel]}
    set temporary [dict get $writer temporary]
    # A Session directory can be replaced at the same path while a writer's
    # descriptor still addresses the old inode. Cleanup must never unlink the
    # replacement Session's copied pending file.
    if {![catch {file lstat $temporary status}]&&$status(type) eq "file"&&[list $status(dev) $status(ino)] eq [dict get $writer temporary_identity]} {file delete -- $temporary}
    dict unset writers $token
}
proc ::GX::interactiveDocumentResourceFinalize {token {repairDisposable 0}} {
    variable ::GX::DocumentResource::writers
    set writer [_documentResourceWriter $token]
    set temporary [dict get $writer temporary]
    flush [dict get $writer channel]
    if {[file size $temporary]!=[dict get $writer bytes]} {error "Pending Document resource size changed"}
    set sha [sha256File $temporary]
    set target [file join [_documentResourceRoot [dict get $writer document]] ${sha}.blob]
    if {[file exists $target]&&[file type $target] eq "link"} {error {Document resource symlinks are forbidden}}
    set corrupt [expr {[file exists $target] && [sha256File $target] ne $sha}]
    if {$corrupt && (!$repairDisposable || ![_documentResourceDisposable [dict get $writer metadata]])} {error "Existing Document resource is corrupt"}
    close [dict get $writer channel]
    dict set writer channel "";dict set writers $token $writer
    if {$corrupt} {file rename -force -- $temporary $target} elseif {[file exists $target]} {file delete -force -- $temporary} else {file rename -- $temporary $target}
    dict unset writers $token
    return [dict create api_id INTERACTIVE_DOCUMENT_RESOURCE_API_v1 document_id [dict get $writer document] owner_generation [dict get $writer owner_generation] sha256 $sha size_bytes [dict get $writer bytes] metadata [dict get $writer metadata]]
}
proc ::GX::interactiveDocumentResourceInfo {reference} {
    set path [_documentResourceIdentity $reference]
    if {![file isfile $path]||[file type $path] eq "link"||[file size $path]!=[dict get $reference size_bytes]||[sha256File $path] ne [dict get $reference sha256]} {error "Document resource is missing or corrupt"}
    return $reference
}
proc ::GX::_documentResourceDisposable {metadata} {
    return [expr {[datasetPublicationV2DictDefault $metadata disposable 0] eq "1" && [datasetPublicationV2DictDefault $metadata scientific_authority 1] eq "0"}]
}
proc ::GX::_documentResourceIdentity {reference} {
    foreach key {api_id document_id sha256 size_bytes metadata} {if {![dict exists $reference $key]} {error "Invalid Document resource reference"}}
    set sha [dict get $reference sha256]
    if {[dict get $reference api_id] ne "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"||![regexp {^[a-f0-9]{64}$} $sha]||![string is entier -strict [dict get $reference size_bytes]]||[dict get $reference size_bytes]<0||[catch {dict size [dict get $reference metadata]}]} {error "Invalid Document resource identity"}
    set document [dict get $reference document_id]
    set path [file join [_documentResourceRoot $document 1] ${sha}.blob]
    if {[dict exists $reference owner_generation]&&[dict get $reference owner_generation] ne [_documentResourceOwnerGeneration $document]} {error "Document resource owner was replaced"}
    if {[file exists $path] && [file type $path] eq "link"} {error {Document resource symlinks are forbidden}}
    return $path
}
proc ::GX::interactiveDocumentResourceImportNumeric {document file metadata} {
    if {![dict exists $metadata origin]} {dict set metadata origin [_scientificImportedOrigin]}
    # Import an explicit, owned Numeric runtime artifact; callers do not derive
    # a private Session target. CORE owns the streaming and destination.
    set writer [interactiveDocumentResourceOpenWriter $document $metadata]
    set channel ""
    try {
        set channel [open $file rb]
        while {1} {
            set bytes [read $channel 1048576]
            if {$bytes eq ""} break
            interactiveDocumentResourceAppend $writer $bytes
        }
        close $channel;set channel ""
        set reference [interactiveDocumentResourceFinalize $writer];set writer ""
        return $reference
    } finally {
        if {$channel ne ""} {close $channel}
        if {$writer ne ""} {interactiveDocumentResourceAbort $writer}
    }
}
proc ::GX::interactiveDocumentResourceReadChunk {reference start count} {
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<0||$count>1048576||$start+$count>[dict get $reference size_bytes]} {error "Document resource read is outside its bounded range"}
    interactiveDocumentResourceInfo $reference
    set path [file join [_documentResourceRoot [dict get $reference document_id] 1] [dict get $reference sha256].blob]
    set channel [open $path rb]
    try {seek $channel $start;return [read $channel $count]} finally {close $channel}
}
proc ::GX::interactiveDocumentResourceReadRanges {reference ranges} {
    # One verified read transaction for a bounded sparse page/locator mapping.
    if {[llength $ranges]>65536} {error "Document resource ranges exceed 65536 entries"}
    interactiveDocumentResourceInfo $reference
    set total 0
    foreach range $ranges {
        if {[llength $range]!=2} {error "Document resource range needs start/count"}
        lassign $range start count
        if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<0||$start+$count>[dict get $reference size_bytes]} {error "Document resource range is outside its resource"}
        incr total $count
        if {$total>1048576} {error "Document resource ranges exceed 1 MiB"}
    }
    set path [file join [_documentResourceRoot [dict get $reference document_id] 1] [dict get $reference sha256].blob]
    set channel [open $path rb];set result {}
    try {
        foreach range $ranges {lassign $range start count;seek $channel $start;set bytes [read $channel $count];if {[string length $bytes]!=$count} {error "Document resource changed during ranged read"};lappend result $bytes}
        return $result
    } finally {close $channel}
}
proc ::GX::interactiveDocumentResourceOpenReader {reference} {
    variable ::GX::DocumentResource::readers;variable ::GX::DocumentResource::serial
    set path [_documentResourceIdentity $reference]
    set version [_documentResourceFileVersion $path]
    interactiveDocumentResourceInfo $reference
    if {[_documentResourceFileVersion $path] ne $version} {error {Document resource changed during reader admission}}
    set channel [open $path rb]
    if {[_documentResourceFileVersion $path] ne $version} {close $channel;error {Document resource changed while opening its reader}}
    set token "document-resource-reader#[pid]-[incr serial]"
    dict set readers $token [dict create channel $channel session [_interactiveDocumentRequireSession] session_token [interactiveDocumentSessionToken] reference $reference file_version $version position 0]
    return $token
}
proc ::GX::_documentResourceFileVersion {path} {
    file lstat $path status
    if {$status(type) ne {file}} {error {Document resource must remain a regular managed file}}
    return [list $status(dev) $status(ino) $status(size) $status(mtime) $status(ctime)]
}
proc ::GX::_documentResourceReader {token} {
    variable ::GX::DocumentResource::readers
    if {![dict exists $readers $token]} {error "Unknown or closed Document resource reader"}
    set reader [dict get $readers $token]
    if {[dict get $reader session_token] ne [interactiveDocumentSessionToken]} {error "Document resource reader belongs to another Session lifetime"}
    set path [_documentResourceIdentity [dict get $reader reference]]
    if {[_documentResourceFileVersion $path] ne [dict get $reader file_version]} {error {Document resource file changed; reopen and verify it explicitly}}
    return $reader
}
proc ::GX::interactiveDocumentResourceReaderInfo {token} {
    set reader [_documentResourceReader $token]
    return [dict create reference [dict get $reader reference] offset [dict get $reader position]]
}
proc ::GX::interactiveDocumentResourceNext {token {count 1048576}} {
    variable ::GX::DocumentResource::readers
    set reader [_documentResourceReader $token]
    if {![string is entier -strict $count]||$count<1||$count>1048576} {error "Document resource read must be 1..1048576 bytes"}
    set reference [dict get $reader reference]
    set n [expr {min($count,[dict get $reference size_bytes]-[dict get $reader position])}]
    set bytes [read [dict get $reader channel] $n]
    if {[string length $bytes]!=$n} {error "Document resource changed during read"}
    dict incr reader position $n;dict set readers $token $reader
    set eof [expr {[dict get $reader position]==[dict get $reference size_bytes]}]
    if {$eof} {interactiveDocumentResourceInfo $reference}
    return [dict create bytes $bytes offset [expr {[dict get $reader position]-$n}] count $n eof $eof]
}
proc ::GX::interactiveDocumentResourceCloseReader {token} {
    variable ::GX::DocumentResource::readers
    if {![dict exists $readers $token]} {error "Unknown or closed Document resource reader"}
    close [dict get $readers $token channel];dict unset readers $token
}
proc ::GX::_documentResourceProvenanceReference {reference} {
    if {[dict exists $reference metadata]} {return $reference}
    if {[lsort [dict keys $reference]] ne {api_id document_id owner_generation sha256 size_bytes}} {error {Invalid compact Document resource provenance identity}}
    set expanded [dict merge $reference [dict create metadata {}]]
    _documentResourceIdentity $expanded
    return $expanded
}
proc ::GX::_documentResourceReferences {value document depth budgetName referencesName} {
    upvar 1 $budgetName budget $referencesName references
    # Scientific arrays and history snapshots can contain millions of scalars,
    # none of which can be resource receipts. Prune only when neither a literal
    # marker nor Tcl escapes could encode one; escaped list values still need
    # decoding so collection never discards a live resource by inspection alone.
    if {[string first INTERACTIVE_DOCUMENT_RESOURCE_API_v1 $value]<0&&[string first \\ $value]<0} return
    if {[incr budget]>1000000||$depth>64} {error "Document resource reference scan exceeds its bounded limit"}
    if {![catch {dict get $value api_id} marker]&&$marker eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        set compact [expr {![dict exists $value metadata]}]
        set value [_documentResourceProvenanceReference $value]
        if {[dict get $value document_id] eq $document} {
            set sha [dict get $value sha256];set identity [dict remove $value metadata]
            if {$compact} {
                # Scientific Job provenance intentionally retains an immutable
                # content identity without resource metadata. It still pins the
                # original blob: verify full generation/size/hash conservatively
                # as scientific data. Do not invent disposable-cache semantics.
                interactiveDocumentResourceInfo $value
            } elseif {![dict exists $references $sha]||[dict get $references $sha] ne $identity} {
                if {[_documentResourceDisposable [dict get $value metadata]]} {_documentResourceIdentity $value} else {interactiveDocumentResourceInfo $value}
            }
            dict set references $sha $identity
        }
        # Retained image resources can themselves own a managed raster receipt.
        # Follow metadata even when the outer resource belongs to another owner.
        if {!$compact} {_documentResourceReferences [dict get $value metadata] $document [expr {$depth+1}] budget references}
        return
    }
    if {[catch {llength $value} count]||$count<1} return
    # A one-record list still owns its nested resources. Stop only at a scalar
    # whose list representation would recurse into exactly the same value.
    foreach item $value {
        if {$item ne $value} {_documentResourceReferences $item $document [expr {$depth+1}] budget references}
    }
}
proc ::GX::_documentResourceExternalReferences {document budgetName referencesName} {
    upvar 1 $budgetName budget $referencesName references
    foreach item [interactiveDocumentList] {
        if {[dict get $item id] ne $document} {_documentResourceReferences [dict get [interactiveDocumentRead [dict get $item id]] payload] $document 0 budget references}
    }
    foreach dataset [datasetRegistryIds] {_documentResourceReferences [_datasetMetadataReadAll [_interactiveDocumentRequireSession] $dataset] $document 0 budget references}
    if {[llength [info commands _workbenchRecoveryResourceReferences]]} {_documentResourceReferences [_workbenchRecoveryResourceReferences $document 1] $document 0 budget references}
}
proc ::GX::interactiveDocumentResourceCollect {document {liveReferences {}}} {
    # Collect only complete, unreferenced blobs. Pending writers and resources
    # retained in document history/payload or a caller's live previews survive.
    set root [_documentResourceRoot $document 1]
    set references {};set budget 0
    if {[interactiveDocumentExists $document]} {_documentResourceReferences [dict get [interactiveDocumentRead $document] payload] $document 0 budget references}
    _documentResourceReferences $liveReferences $document 0 budget references
    if {[llength [info commands _workbenchRecoveryResourceReferences]]} {_documentResourceReferences [_workbenchRecoveryResourceReferences $document] $document 0 budget references}
    dict for {token reader} $::GX::DocumentResource::readers {
        if {[dict get $reader session_token] eq [interactiveDocumentSessionToken]} {_documentResourceReferences [dict get $reader reference] $document 0 budget references}
    }
    # Explicit publication can retain scientific model/residual provenance.
    # Other documents can also hold this owner's references. Scan committed
    # public metadata before deciding that a blob is unreferenced.
    _documentResourceExternalReferences $document budget references
    set paths [glob -nocomplain -directory $root *.blob];set removed 0;set bytes 0
    # Validate the complete deletion set before changing any file.
    set unreferenced {}
    foreach path $paths {
        if {[file type $path] eq "link"} {error "Document resource symlinks are forbidden"}
        if {![regexp {^([a-f0-9]{64})\.blob$} [file tail $path] -> sha]} {error "Unexpected Document resource file"}
        if {![dict exists $references $sha]} {lappend unreferenced $path}
    }
    foreach path $unreferenced {incr bytes [file size $path];file delete -- $path;incr removed}
    if {![interactiveDocumentExists $document]&&![dict size $references]} {file delete -force -- $root}
    return [dict create removed_blobs $removed removed_bytes $bytes retained_blobs [expr {[llength $paths]-$removed}]]
}
proc ::GX::_documentResourceDeletePlan {document} {
    set root [_documentResourceRoot $document]
    if {![file exists $root]} {return {}}
    set references {};set budget 0
    _documentResourceExternalReferences $document budget references
    set unreferenced {}
    foreach path [glob -nocomplain -directory $root * .*] {
        set name [file tail $path]
        if {$name in {. ..}} continue
        if {[file type $path] eq "link"||![file isfile $path]} {error "Unsafe Document resource cleanup target"}
        if {[regexp {^([a-f0-9]{64})\.blob$} $name -> sha]} {
            if {![dict exists $references $sha]} {lappend unreferenced $path}
        } elseif {[string match .pending-* $name]||[regexp {^tcl_[A-Za-z0-9_]+\.pending-$} $name]} {lappend unreferenced $path} else {error "Unexpected Document resource cleanup file '$name'"}
    }
    set marker ""
    if {[dict size $references]} {
        set marker [file join $root .retired.ini]
        set f [open $marker {WRONLY CREAT EXCL}]
        try {puts $f "\[resource_owner\]";putKV $f document_id $document;putKV $f generation [_documentResourceOwnerGeneration $document]} on error {message options} {
            close $f;set f "";file delete -- $marker
            return -options $options $message
        } finally {if {$f ne ""} {close $f}}
    }
    return [dict create root $root marker $marker unreferenced $unreferenced retained [dict size $references] session [_interactiveDocumentRequireSession]]
}
proc ::GX::_documentResourceDeleteRollback {plan} {
    if {[dict get $plan marker] ne ""} {file delete -- [dict get $plan marker]}
}
proc ::GX::_documentResourceDeleteCommit {document plan} {
    variable ::GX::DocumentResource::writers;variable ::GX::DocumentResource::readers
    dict for {token writer} $writers {
        if {[dict get $writer document] eq $document&&[dict get $writer session_token] eq [interactiveDocumentSessionToken]} {interactiveDocumentResourceAbort $token}
    }
    dict for {token reader} $readers {
        if {[dict get $reader reference document_id] eq $document&&[dict get $reader session_token] eq [interactiveDocumentSessionToken]} {interactiveDocumentResourceCloseReader $token}
    }
    foreach path [dict get $plan unreferenced] {file delete -- $path}
    if {![dict get $plan retained]} {file delete -force -- [dict get $plan root]}
}
proc ::GX::interactiveDocumentNative2DStore {document scene object {metadata {}} {repairDisposable 0}} {
    native2DEnsure
    set count [::GX::Native2D::core count $scene $object]
    dict set metadata sketch_attributes [::GX::Native2D::core identity_attributes $scene $object]
    dict set metadata native_kind [::GX::Native2D::core kind $scene $object]
    dict set metadata native_direction [::GX::Native2D::core direction_marker $scene $object]
    set image [::GX::Native2D::core image_get $scene $object]
    if {$image ne {}} {dict set metadata reference_image $image;dict set metadata image_resource [dict get $::GX::Native2DRaster::resources $scene $object]}
    set definition [::GX::Native2D::core sketch_definition $scene $object]
    if {$definition ne {}} {dict set metadata sketch_definition $definition;dict set metadata geometry_authority retained_sketch}
    set writer [interactiveDocumentResourceOpenWriter $document [dict merge $metadata [dict create format native2d.float64_xy_le_v1 point_count $count]]]
    try {
        for {set start 0} {$start<$count} {incr start 65536} {
            set n [expr {min(65536,$count-$start)}]
            interactiveDocumentResourceAppend $writer [::GX::Native2D::core points_binary $scene $object $start $n]
        }
        set result [interactiveDocumentResourceFinalize $writer $repairDisposable];set writer ""
        return $result
    } finally {if {$writer ne ""} {interactiveDocumentResourceAbort $writer}}
}
proc ::GX::interactiveDocumentNative2DRestore {reference scene {kind auto}} {
    if {$kind eq "auto"} {set kind [datasetPublicationV2DictDefault [dict get $reference metadata] native_kind curve]}
    if {$kind ni {curve point_set point}} {error "Native2D restore kind must be curve, point_set or point"}
    native2DEnsure
    interactiveDocumentResourceInfo $reference
    if {[dict get $reference metadata format] ne "native2d.float64_xy_le_v1"||[dict get $reference size_bytes]!=16*[dict get $reference metadata point_count]} {error "Invalid Native2D resource shape/format"}
    if {[dict exists $reference metadata reference_image]} {
        set object [::GX::Native2D::core image_create $scene [dict get $reference metadata reference_image]]
        try {native2DReferenceImageBind $scene $object [dict get $reference metadata image_resource];return $object} on error {message options} {::GX::Native2D::core delete $scene $object;return -options $options $message}
    }
    if {[dict exists $reference metadata sketch_definition]} {
        # ResourceInfo verifies complete cache bytes/hash; the defining parameters
        # remain the mathematical authority rather than a flattened polyline.
        return [::GX::Native2D::core sketch_create $scene [dict get $reference metadata sketch_definition] [dict get $reference metadata point_count]]
    }
    set object 0;set reader [interactiveDocumentResourceOpenReader $reference]
    try {
        while {1} {
            set chunk [interactiveDocumentResourceNext $reader]
            set object [::GX::Native2D::core [expr {$kind eq "point_set" ? "append_binary_pointset" : $kind eq "point" ? "append_binary_point" : "append_binary_xy"}] $scene $object [dict get $chunk bytes]]
            if {[dict get $chunk eof]} break
        }
        return $object
    } on error {message options} {
        if {$object!=0} {::GX::Native2D::core delete $scene $object}
        return -options $options $message
    } finally {interactiveDocumentResourceCloseReader $reader}
}
proc ::GX::interactiveDocumentNative2DRestoreWithGaps {reference gapReference scene} {
    native2DEnsure
    interactiveDocumentResourceInfo $reference;interactiveDocumentResourceInfo $gapReference
    set n [dict get $reference metadata point_count]
    if {![string is entier -strict $n]||$n<2||[dict get $reference metadata format] ne "native2d.float64_xy_le_v1"||[dict get $reference size_bytes]!=16*$n||[dict get $gapReference metadata format] ne "native2d.uint8_break_before_v1"||[dict get $gapReference size_bytes]!=$n} {error "Invalid Native2D XY/gap resource shape"}
    set xy "";set gaps "";set object 0
    try {
        set xy [interactiveDocumentResourceOpenReader $reference];set gaps [interactiveDocumentResourceOpenReader $gapReference]
        while {1} {
            set chunk [interactiveDocumentResourceNext $xy]
            set mask [interactiveDocumentResourceNext $gaps [expr {max(1,[dict get $chunk count]/16)}]]
            set object [::GX::Native2D::core append_binary_xy_gaps $scene $object [dict get $chunk bytes] [dict get $mask bytes]]
            if {[dict get $chunk eof]} {if {![dict get $mask eof]} {error "Native2D gap resource has trailing data"};break}
        }
        return $object
    } on error {message options} {
        if {$object!=0} {::GX::Native2D::core delete $scene $object}
        return -options $options $message
    } finally {
        if {$xy ne ""} {interactiveDocumentResourceCloseReader $xy}
        if {$gaps ne ""} {interactiveDocumentResourceCloseReader $gaps}
    }
}

proc ::GX::_interactiveDocumentNative2DRestoreIdentity {reference scene object} {
    try {
        if {[dict exists $reference metadata sketch_attributes]} {
            dict for {key value} [dict get $reference metadata sketch_attributes] {::GX::Native2D::core identity_attribute $scene $object $key $value}
        }
        if {[dict exists $reference metadata native_direction]} {::GX::Native2D::core direction_marker $scene $object [dict get $reference metadata native_direction]}
        return $object
    } on error {message options} {::GX::Native2D::core delete $scene $object;return -options $options $message}
}
rename ::GX::interactiveDocumentNative2DRestore ::GX::interactiveDocumentNative2DRestore_identity_base
proc ::GX::interactiveDocumentNative2DRestore {reference scene {kind auto}} {
    return [_interactiveDocumentNative2DRestoreIdentity $reference $scene [interactiveDocumentNative2DRestore_identity_base $reference $scene $kind]]
}
rename ::GX::interactiveDocumentNative2DRestoreWithGaps ::GX::interactiveDocumentNative2DRestoreWithGaps_identity_base
proc ::GX::interactiveDocumentNative2DRestoreWithGaps {reference gapReference scene} {
    return [_interactiveDocumentNative2DRestoreIdentity $reference $scene [interactiveDocumentNative2DRestoreWithGaps_identity_base $reference $gapReference $scene]]
}

# Public read-only dependency projection over the SAME scanners used by GC
# and portable Workspaces. No parallel reference grammar or registry exists.
proc ::GX::interactiveDocumentResourceReferences {value {document {}}} {
    if {$document ne {}} {_documentResourceRoot $document 1}
    if {[string first INTERACTIVE_DOCUMENT_RESOURCE_API_v1 $value]<0 && [string first \\ $value]<0} {return {}}
    set found {};_workspacePackageReferences $value 0 found
    set result {};set checked {};set budget 0
    dict for {sha reference} $found {
        set owner [dict get $reference document_id]
        if {$document ne {} && $owner ne $document} continue
        _documentResourceReferences $reference $owner 0 budget checked
        lappend result $reference
    }
    return $result
}
proc ::GX::interactiveDocumentResourceRemapReferences {value references} {
    set mapping {};set checked {};set budget 0
    foreach reference $references {
        _documentResourceReferences $reference [dict get $reference document_id] 0 budget checked
        dict set mapping [dict get $reference sha256] $reference
    }
    return [_workspaceRemapResources $value $mapping 0]
}

# Fixed paired-source intake is a private format-specific child of this owner.
# The existing public Resource/CRUD signatures and registry remain unchanged.
source [file join [file dirname [info script]] document_pcb_paired_source_v1.tcl]
