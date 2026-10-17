# Owned nD arrays -> existing canonical writer and delegated binary transport.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::datasetPublicationV2PublishManagedVariables {session moduleId definition dimensions variables} {
    if {[dict size $dimensions]<1||[dict size $dimensions]>16||[llength $variables]<1||[llength $variables]>128} {error {Managed publication requires1..16 dimensions and1..128 Variables}}
    dict for {id size} $dimensions {
        datasetPublicationV2ValidateId dimension $id
        if {![string is entier -strict $size]||$size<1} {error {Managed dimensions must be positive integers}}
    }
    set prepared {};set ids {};set totalBytes 0
    foreach variable $variables {
        if {[lsort [dict keys $variable]] ne {resource schema variable_id}} {error {Managed Variable requires exactly variable_id, schema and resource}}
        set id [datasetPublicationV2ValidateId variable [dict get $variable variable_id]]
        if {$id in $ids} {error {Managed Variable identities must be unique}};lappend ids $id
        set schema [dict get $variable schema];set reference [dict get $variable resource]
        interactiveDocumentResourceInfo $reference
        set metadata [dict get $reference metadata]
        if {[datasetPublicationV2DictDefault $metadata format {}] ne "gxtxt.numeric_array_le.v1"||[datasetPublicationV2DictDefault $metadata endian {}] ne "little"||[datasetPublicationV2DictDefault $metadata order {}] ne "F"} {error {Managed nD publication requires the versioned little-endian column-major format}}
        set dtype [dict get $metadata dtype]
        if {$dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool}||[dict get $schema dtype] ne $dtype} {error {Managed nD publication preserves an explicitly matching canonical numeric dtype}}
        if {[dict exists $metadata unit]&&[dict get $metadata unit] ne [datasetPublicationV2DictDefault $schema unit {}]} {error {Managed publication cannot relabel a declared physical unit}}
        set dimIds [datasetSchemaV3SplitIds [dict get $schema dimension_ids]];set shape {}
        if {[llength $dimIds]<1||[llength $dimIds]>16} {error {Managed Variables require1..16 explicit dimensions}}
        foreach dim $dimIds {if {![dict exists $dimensions $dim]} {error {Managed Variable references an undeclared dimension}};lappend shape [dict get $dimensions $dim]}
        if {[datasetPublicationV2Shape [dict get $metadata shape]] ne $shape} {error {Managed resource shape differs from canonical dimensions}}
        if {[dict exists $schema variable_id]&&[dict get $schema variable_id] ne $id} {error {Managed schema Variable identity differs from its binding}}
        if {[dict exists $schema shape]&&[datasetPublicationV2Shape [dict get $schema shape]] ne $shape} {error {Managed schema shape contradicts its dimensions}}
        if {[dict exists $schema rank]&&[dict get $schema rank]!=[llength $shape]} {error {Managed schema rank contradicts its dimensions}}
        if {[dict exists $schema axis_kind]&&[dict get $schema axis_kind] eq "uniform"} {error {Managed arrays store explicit values; uniform coordinates use their own declaration}}
        set count [datasetPublicationV2ElementCount $shape];set bytes [expr {$count*[datasetBinaryTransportWidth $dtype]}]
        if {$bytes!=[dict get $reference size_bytes]||$bytes>536870912} {error {Managed array shape/dtype/byte length differs or exceeds512MiB}}
        incr totalBytes $bytes
        lappend prepared [dict create variable_id $id schema [dict merge $schema [dict create rank [llength $shape] shape $shape axis_kind explicit]] reference $reference shape $shape dtype $dtype count $count bytes $bytes]
    }
    dict set definition estimated_numeric_bytes $totalBytes
    if {[datasetPublicationV2DictDefault $definition storage auto] eq "auto"} {dict set definition storage hdf5}
    set plan [datasetPublicationV2Prepare $session $moduleId $definition]
    set allocation [resourceManagementAllocate managed_variable_publication [dict create kind directory session $session lifetime computation]]
    set workspace [dict get $allocation path];set writer {};set reader {};set channel {}
    set hadScope [info exists ::env(GXTXT_BRIDGE_WORKSPACE)];if {$hadScope} {set previousScope $::env(GXTXT_BRIDGE_WORKSPACE)}
    try {
        set ::env(GXTXT_BRIDGE_WORKSPACE) $workspace
        set writer [datasetPublicationV2OpenWriter $plan]
        if {![datasetPublicationV2DictDefault [datasetPublicationV2WriterCapabilities $writer] managed_binary_write 0]} {error {Managed nD publication requires a capable canonical writer; choose HDF5}}
        dict for {id size} $dimensions {datasetPublicationV2DeclareDimension $writer $id $size}
        foreach variable $prepared {datasetPublicationV2DeclareVariable $writer [dict get $variable variable_id] [dict get $variable schema]}
        set serial 0
        foreach variable $prepared {
            set reference [dict get $variable reference]
            set reader [interactiveDocumentResourceOpenReader $reference]
            set name [format %032x.bin [incr serial]];set path [file join $workspace $name]
            set channel [open $path {WRONLY CREAT EXCL}];fconfigure $channel -translation binary -encoding binary
            set remaining [dict get $variable bytes]
            while {$remaining>0} {
                set page [interactiveDocumentResourceNext $reader [expr {min(1048576,$remaining)}]];set bytes [dict get $page bytes];set count [string length $bytes]
                if {$count<1||$count>$remaining} {error {Managed nD resource ended inside its declared shape}}
                puts -nonewline $channel $bytes;incr remaining -$count
            }
            close $channel;set channel {};interactiveDocumentResourceCloseReader $reader;set reader {}
            if {[sha256File $path] ne [dict get $reference sha256]} {error {Managed array changed during publication}}
            set shape [dict get $variable shape]
            set binary [dict create version 2 dtype [dict get $variable dtype] endian little order F shape [join $shape {;}] count [dict get $variable count] byte_count [dict get $variable bytes] resource_id $name resource_root $workspace]
            datasetPublicationV2WriteVariable $writer [dict get $variable variable_id] [dict create __gxtxt_binary_resource 1 shape $shape resource $binary] $shape
            file delete -- $path
        }
        set result [datasetPublicationV2Finalize $writer];set writer {}
        dict set result variable_count [llength $prepared]
        return $result
    } finally {
        if {$channel ne {}} {close $channel}
        if {$reader ne {}} {interactiveDocumentResourceCloseReader $reader}
        if {$writer ne {}} {catch {datasetPublicationV2Abort $writer}}
        if {$hadScope} {set ::env(GXTXT_BRIDGE_WORKSPACE) $previousScope} else {unset -nocomplain ::env(GXTXT_BRIDGE_WORKSPACE)}
        resourceManagementRelease [dict get $allocation id]
        resourceManagementCleanup [list [dict get $allocation id]]
    }
}
