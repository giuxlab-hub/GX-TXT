# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit scientific continuity uses public row identities, never display gaps
# inferred from the distance between sampled points. Memory stays budget-bounded.
proc ::GX::_curveSourceContinuityBegin {source display} {
    set record [_curveSourceRequire $source];set request [dict get $record request]
    set metadata [datasetMetadataRead [dict get $record session] [dict get $request dataset_id]]
    set policy [datasetPublicationV2DictDefault $metadata curve_source.continuity_policy {}]
    if {$policy eq {}} {return {}}
    if {$policy ne "source_row_adjacency"} {error {Unsupported declared Curve Source continuity policy}}
    set variable [dict get $metadata curve_source.continuity_variable_id]
    set schema [datasetVariableV3ById [dict get $request dataset_id] $variable]
    if {[dict get $schema dtype] ni {int8 uint8 int16 uint16 int32 uint32 int64 uint64} || [dict get $schema rank]!=1} {error {Scientific continuity requires a rank-one integer row-identity Variable}}
    set ids [list $variable];set lineage [dict get $record lineage_variable]
    if {$lineage ne {} && $lineage ni $ids} {lappend ids $lineage}
    set stream [curveSourceOpenStream $source $ids 8192 [dict create numeric_transport values]]
    return [dict create source $source stream $stream variable $variable lineage $lineage \
        targets [dict get $display source_rows] index 0 position [dict get $request start] \
        previous {} pending 0 breaks [dict get $display breaks] display $display]
}
proc ::GX::_curveSourceContinuityStep {state} {
    set source [dict get $state source];_curveSourceRequire $source
    set chunk [tableStreamNext [dict get $state stream]]
    set values [dict get $chunk values [dict get $state variable]]
    set lineage [dict get $state lineage];set rowIds {}
    if {$lineage ne {}} {set rowIds [dict get $chunk values $lineage]}
    set targets [dict get $state targets];set index [dict get $state index]
    set previous [dict get $state previous];set pending [dict get $state pending]
    set position [dict get $state position];set breaks [dict get $state breaks];set offset 0
    foreach ordinal $values {
        if {![string is entier -strict $ordinal] || $ordinal<0} {error {Invalid scientific continuity row identity}}
        if {$previous ne {} && $ordinal!=$previous+1} {set pending 1}
        set identity [expr {$lineage eq {} ? $position : [lindex $rowIds $offset]}]
        if {$index<[llength $targets] && $identity eq [lindex $targets $index]} {
            if {$index>0 && $pending} {lappend breaks [expr {$index-1}]}
            set pending 0;incr index
        }
        set previous $ordinal;incr position;incr offset
    }
    set display [dict get $state display];dict set display breaks [lsort -integer -unique $breaks]
    dict set display continuity_policy source_row_adjacency
    return [dict replace $state index $index position $position previous $previous pending $pending breaks $breaks display $display done [dict get $chunk eof]]
}
proc ::GX::_curveSourceContinuityDisplay {source display} {
    set state [_curveSourceContinuityBegin $source $display]
    if {$state eq {}} {return $display}
    try {
        while {1} {set state [_curveSourceContinuityStep $state];if {[dict get $state done]} break}
        return [dict get $state display]
    } finally {curveSourceCloseStream $source [dict get $state stream]}
}
