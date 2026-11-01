# SPDX-License-Identifier: GPL-3.0-or-later
# Generic sealed prepared arrays -> existing scientific value owner. No parser,
# vendor policy, payload conversion or second Dataset publication engine.
proc ::GX::_acquisitionPreparedSpectrumPage {channels variables offset count} {
    set result {}
    foreach role {x y} {
        set variable [dict get $variables $role];set stream [dict get $channels $role]
        set width [dict get $variable width];set bytes [expr {$count*$width}]
        seek $stream [expr {$offset*$width}] start
        set raw [read $stream $bytes]
        if {[string length $raw]!=$bytes} {error {Prepared scientific array changed during page validation}}
        set block [dict create dtype [dict get $variable dtype] endian little shape [list $count] base64 [binary encode base64 -maxlen 0 $raw]]
        # Scientific hashing uses the actual promoted IEEE value, rather than
        # the default 9-digit float32 presentation used by textual consumers.
        dict set result $role [datasetPublicationV2MaterializeBinaryBlock [dict get $variable schema] $block 0]
    }
    return $result
}
proc ::GX::_acquisitionPreparedSpectrumValidate {definition variables} {
    set metadata [datasetPublicationV2DictDefault $definition structured_metadata {}]
    foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit spectral_x_variable_id spectral_y_variable_id} {
        if {![dict exists $metadata $key] || [string trim [dict get $metadata $key]] eq {}} {error "Prepared scientific spectrum requires declared '$key'"}
    }
    set byId {};foreach variable $variables {dict set byId [dict get $variable variable_id] $variable}
    set selected {};set handles {}
    foreach role {x y} {
        set id [dict get $metadata spectral_${role}_variable_id]
        if {![dict exists $byId $id]} {error {Scientific spectrum refers to an undeclared Variable}}
        set variable [dict get $byId $id];set schema [dict get $variable schema]
        if {[llength [dict get $variable shape]]!=1 || [dict get $variable count]<2} {error {Scientific spectrum requires real rank-one X/Y arrays with at least two samples}}
        if {[datasetPublicationV2DictDefault $schema unit {}] ne [dict get $metadata ${role}_unit]} {error {Scientific spectrum units differ from the actual Variable units}}
        set pin [dict get $variable sha256]
        if {$pin eq {}} {set pin [sha256File [dict get $variable path]];dict set variable sha256 $pin;dict set byId $id $variable}
        dict set selected $role $variable
    }
    set x [dict get $selected x];set y [dict get $selected y]
    if {[dict get $x variable_id] eq [dict get $y variable_id] || [dict get $x count]!=[dict get $y count] || [dict get $x schema dimension_ids] ne [dict get $y schema dimension_ids] ||
        [datasetPublicationV2DictDefault [dict get $x schema] coordinate_role {}] ne {coordinate} ||
        [dict get $x variable_id] ni [datasetSchemaV3SplitIds [datasetPublicationV2DictDefault [dict get $y schema] coordinate_variable_ids {}]]} {error {Scientific X/Y dimensions and coordinate association do not match}}
    try {
        foreach role {x y} {
            set variable [dict get $selected $role];set path [dict get $variable path]
            if {[sha256File $path] ne [dict get $variable sha256]} {error {Sealed scientific array SHA changed before value validation}}
            set stream [open $path rb];dict set handles $role $stream
        }
        set receipt [::GX::SpectrumAPIv1::validatePages $metadata [dict get $x count] [list ::GX::_acquisitionPreparedSpectrumPage $handles $selected]]
        foreach role {x y} {
            set variable [dict get $selected $role]
            if {[sha256File [dict get $variable path]] ne [dict get $variable sha256]} {error {Sealed scientific array SHA changed during value validation}}
        }
        dict set receipt spectrum_value_validation SCIENTIFIC_SPECTRUM_API_v1_VALIDATED
        dict for {key value} $receipt {
            if {[dict exists $metadata $key] && [dict get $metadata $key] ne $value} {error "Producer attempted to replace CORE spectrum validation '$key'"}
            dict set metadata $key $value
        }
        dict set definition structured_metadata $metadata
        set pinned {};foreach variable $variables {lappend pinned [dict get $byId [dict get $variable variable_id]]}
        return [dict create definition $definition variables $pinned]
    } finally {dict for {role stream} $handles {close $stream}}
}
