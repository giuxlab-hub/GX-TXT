#!/usr/bin/env tclsh
# GX-TXT private Octave bridge for Table Stream API v3.
# SPDX-License-Identifier: GPL-3.0-or-later

proc emitError {message} {
    puts "ERROR\t[::GX::datasetB64Encode $message]"
    flush stdout
}

proc emitMetadata {stream} {
    set metadata [::GX::tableStreamMetadata $stream]
    set variables [dict get $metadata variables]
    set flat [dict create]
    dict for {key value} $metadata {
        if {$key eq "variables"} continue
        if {$key eq "capabilities"} {
            dict for {capability enabled} $value { dict set flat "capability.$capability" $enabled }
        } else {
            dict set flat $key $value
        }
    }
    puts "META\t[dict size $flat]\t[llength $variables]"
    dict for {key value} $flat { puts "ITEM\t[::GX::datasetB64Encode $key]\t[::GX::datasetB64Encode $value]" }
    foreach variable $variables {
        set fields {}
        foreach field {variable_id canonical display_label dtype unit semantic_role value_kind value_format decimal_separator time_origin time_reference dimension_ids coordinate_role axis_kind axis_origin axis_step axis_count} {
            lappend fields [::GX::datasetB64Encode [dict get $variable $field]]
        }
        puts "VAR\t[join $fields \t]"
    }
    puts END
    flush stdout
}

proc emitChunk {chunk} {
    set columns [dict get $chunk columns]
    puts "CHUNK\t[dict get $chunk offset]\t[dict get $chunk nrows]\t[dict get $chunk eof]\t[llength $columns]"
    foreach column $columns {
        set fields {}
        foreach field {variable_id canonical dtype unit semantic_role axis_kind} {
            lappend fields [::GX::datasetB64Encode [dict get $column $field]]
        }
        if {[dict exists $column binary_block]} {
            set block [dict get $column binary_block]
            ::GX::datasetBinaryValidateBlock $block [dict get $column count]
            puts "BCOL\t[join $fields \t]\t[dict get $block endian]\t[::GX::datasetB64Encode [dict get $block shape]]\t[dict get $column count]\t[dict get $block base64]"
        } elseif {[dict get $column dtype] ne "string"} {
            # Typed numeric values cannot contain the column separator.
            # Keep text columns on the escaped transport.
            puts "NCOL\t[join $fields \t]\t[join [dict get $column values] ,]"
        } else {
            set encodedValues {}
            foreach value [dict get $column values] { lappend encodedValues [::GX::datasetB64Encode $value] }
            puts "COL\t[join $fields \t]\t[join $encodedValues ,]"
        }
    }
    puts END
    flush stdout
}

proc emitDiagnostics {stream} {
    set diagnostics [::GX::tableStreamDiagnostics $stream]
    set flat [dict create]
    dict for {key value} $diagnostics {
        if {$key eq "provider"} {
            dict for {providerKey providerValue} $value { dict set flat "provider.$providerKey" $providerValue }
        } else {
            dict set flat $key $value
        }
    }
    puts "DIAG\t[dict size $flat]"
    dict for {key value} $flat { puts "ITEM\t[::GX::datasetB64Encode $key]\t[::GX::datasetB64Encode $value]" }
    puts END
    flush stdout
}

set root [file normalize [file join [file dirname [info script]] .. ..]]
set argv0 __not_main__
if {[catch {
    source [file join $root gxtxt_pipeline.tcl]
    ::GX::defaults
    if {[llength $argv] ni {7 8}} { error "Table Stream bridge requires session, dataset, variables, chunk_rows, start, count, require_direct, and optional numeric_transport" }
    lassign $argv session datasetId variableText chunkRows start count requireDirect numericTransport
    if {$numericTransport eq ""} { set numericTransport auto }
    set variableIds {}
    foreach variableId [split $variableText {;}] { if {[string trim $variableId] ne ""} { lappend variableIds [string trim $variableId] } }
    set stream [::GX::tableStreamOpenDataset $session $datasetId $variableIds $chunkRows [dict create start $start count $count require_direct $requireDirect numeric_transport $numericTransport]]
    set metadata [::GX::tableStreamMetadata $stream]
} failure]} {
    if {[llength [info commands ::GX::datasetB64Encode]]} { emitError $failure } else { puts stderr $failure }
    exit 2
}

puts "READY\t[::GX::datasetB64Encode $stream]\t[::GX::datasetB64Encode [dict get $metadata dataset_id]]\t[::GX::datasetB64Encode [dict get $metadata storage_provider]]\t[::GX::datasetB64Encode [dict get $metadata row_dimension]]\t[dict get $metadata row_count]\t[dict get $metadata range_start]\t[dict get $metadata range_count]\t[dict get $metadata chunk_rows]\t[::GX::datasetB64Encode [dict get $metadata range_mode]]"
flush stdout

try {
    set done 0
    while {[gets stdin command] >= 0} {
        set command [string toupper [string trim $command]]
        if {$command eq ""} continue
        if {[catch {
            switch -- $command {
                META { emitMetadata $stream }
                NEXT { emitChunk [::GX::tableStreamNext $stream] }
                DIAG { emitDiagnostics $stream }
                CLOSE {
                    ::GX::tableStreamClose $stream
                    puts "CLOSED"; flush stdout
                    set done 1
                }
                default { error "Unknown Table Stream bridge command '$command'" }
            }
        } failure]} { emitError $failure }
        if {$done} break
    }
} finally {
    catch {::GX::tableStreamClose $stream}
}
