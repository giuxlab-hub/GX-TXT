# SPDX-License-Identifier: GPL-3.0-or-later
# Owned column-major matrix -> existing binary-v2 Dataset writer; no statistics.
proc ::GX::datasetPublicationV2PublishManagedColumns {session moduleId definition reference schema} {
    interactiveDocumentResourceInfo $reference
    set metadata [dict get $reference metadata]
    if {[datasetPublicationV2DictDefault $metadata format {}] ne "gxtxt.numeric_matrix.float64_column_major_le.v1"} {error {Managed publication requires the versioned column-major binary64 matrix format}}
    set rows [datasetPublicationV2DictDefault $metadata row_count {}]
    set columns [datasetPublicationV2DictDefault $metadata column_ids {}]
    if {![string is wideinteger -strict $rows]||$rows<1||[llength $columns]<1||[llength $columns]>128||[llength [lsort -unique $columns]]!=[llength $columns]||[llength $schema]!=[llength $columns]||[dict get $reference size_bytes]!=8*$rows*[llength $columns]||[dict get $reference size_bytes]>536870912} {error {Managed publication matrix shape/column identity/size is invalid}}
    set index 0
    foreach variable $schema {
        if {[dict get $variable variable_id] ne [lindex $columns $index]||[dict get $variable dtype] ne "float64"} {error {Managed publication schema must follow the exact binary64 column identities}}
        foreach {field expected} {rank 1 dimension_ids row} {if {[dict exists $variable $field]&&[dict get $variable $field] ne $expected} {error {Managed publication schema must declare one row dimension}}}
        if {[dict exists $variable shape]&&[dict get $variable shape] ne [list $rows]} {error {Managed publication column shape differs from its resource}}
        incr index
    }
    dict set definition expected_rows $rows
    dict set definition estimated_numeric_bytes [dict get $reference size_bytes]
    if {[datasetPublicationV2DictDefault $definition storage auto] eq "auto"} {dict set definition storage hdf5}
    set plan [datasetPublicationV2Prepare $session $moduleId $definition]
    set allocation [resourceManagementAllocate managed_publication [dict create kind directory session $session lifetime computation]]
    set workspace [dict get $allocation path];set writer {};set reader {};set channel {}
    set hadScope [info exists ::env(GXTXT_BRIDGE_WORKSPACE)];if {$hadScope} {set previousScope $::env(GXTXT_BRIDGE_WORKSPACE)}
    try {
        # The writer captures delegated scope at startup, as well as checking
        # every resource request. Keep one scope for its complete lifetime.
        set ::env(GXTXT_BRIDGE_WORKSPACE) $workspace
        set writer [datasetPublicationV2OpenWriter $plan]
        if {![datasetPublicationV2DictDefault [datasetPublicationV2WriterCapabilities $writer] managed_binary_write 0]} {error {The selected Dataset writer does not support managed binary columns; choose HDF5}}
        datasetPublicationV2DeclareDimension $writer row $rows
        foreach variable $schema {
            set id [dict get $variable variable_id]
            set variable [dict merge $variable [dict create rank 1 dimension_ids row shape [list $rows] axis_kind explicit]]
            datasetPublicationV2DeclareVariable $writer $id $variable
        }
        set reader [interactiveDocumentResourceOpenReader $reference];set index 0
        foreach variable $schema {
            set name [format %032x.bin [incr index]];set path [file join $workspace $name]
            set channel [open $path {WRONLY CREAT EXCL}];fconfigure $channel -translation binary -encoding binary
            set remaining [expr {8*$rows}]
            while {$remaining>0} {
                set page [interactiveDocumentResourceNext $reader [expr {min(1048576,$remaining)}]]
                set bytes [dict get $page bytes];set count [string length $bytes]
                if {$count<1||$count>$remaining} {error {Managed publication resource ended inside a column}}
                puts -nonewline $channel $bytes;incr remaining -$count
            }
            close $channel;set channel {}
            set binary [dict create version 2 dtype float64 endian little order F shape [list $rows] count $rows byte_count [expr {8*$rows}] resource_id $name resource_root $workspace]
            # Scope is restored even when a writer rejects; nested Script Jobs
            # retain their original delegated binary workspace.
            datasetPublicationV2WriteVariable $writer [dict get $variable variable_id] [dict create __gxtxt_binary_resource 1 shape [list $rows] resource $binary] [list $rows]
            file delete -- $path
        }
        interactiveDocumentResourceCloseReader $reader;set reader {}
        set result [datasetPublicationV2Finalize $writer];set writer {}
        dict set result row_count $rows
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
