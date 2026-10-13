# GX-TXT Scientific Spectrum API v1 — domain-neutral one-dimensional spectrum.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectrumAPIv1 {
    variable apiVersion 1
    variable contract spectrum.scientific
}

proc ::GX::SpectrumAPIv1::apiInfo {} {
    variable apiVersion
    variable contract
    return [dict create api_name SCIENTIFIC_SPECTRUM_API_v1 api_version $apiVersion contract $contract]
}

proc ::GX::SpectrumAPIv1::_required {spec key} {
    if {![dict exists $spec $key] || [string trim [dict get $spec $key]] eq ""} {
        error "Scientific Spectrum API v1: $key is required"
    }
    return [dict get $spec $key]
}

proc ::GX::SpectrumAPIv1::_finite {value label} {
    if {![string is double -strict $value] || [regexp -nocase {nan|inf} $value]} {
        error "Scientific Spectrum API v1: $label must be finite numeric"
    }
    if {[catch {set result [expr {double($value)}]}]} {
        error "Scientific Spectrum API v1: $label must be finite numeric"
    }
    if {[regexp -nocase {nan|inf} $result]} {
        error "Scientific Spectrum API v1: $label must be finite numeric"
    }
    return $result
}

proc ::GX::SpectrumAPIv1::_dict {value label} {
    if {[catch {dict size $value}]} { error "Scientific Spectrum API v1: $label must be a Tcl dict" }
    return $value
}

proc ::GX::SpectrumAPIv1::_hash {spec} {
    # The numerical hash excludes identity, names and provenance, so copies of
    # the same scientific trace can be detected across independent libraries.
    set channel [file tempfile path]
    fconfigure $channel -translation lf -encoding utf-8
    try {
        foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {
            puts $channel [dict get $spec $key]
        }
        foreach x [dict get $spec x] y [dict get $spec y] {
            puts $channel "[format %.17g $x]\t[format %.17g $y]"
        }
        close $channel
        set channel ""
        return [::GX::sha256File $path]
    } finally {
        if {$channel ne ""} { catch {close $channel} }
        catch {file delete -- $path}
    }
}

proc ::GX::SpectrumAPIv1::create {fields} {
    _dict $fields fields
    foreach key {spectrum_id display_name spectrum_kind x_quantity x_unit y_quantity y_representation y_unit x y} {
        _required $fields $key
    }
    set xRaw [dict get $fields x]
    set yRaw [dict get $fields y]
    set count [llength $xRaw]
    if {$count < 2 || [llength $yRaw] != $count} {
        error "Scientific Spectrum API v1: x and y must contain the same number of samples (at least two)"
    }
    set x {}; set y {}; set direction 0; set previous ""
    for {set i 0} {$i < $count} {incr i} {
        set xv [_finite [lindex $xRaw $i] "x sample $i"]
        set yv [_finite [lindex $yRaw $i] "y sample $i"]
        if {$i > 0} {
            if {$xv == $previous} { error "Scientific Spectrum API v1: X contains a duplicate at sample $i" }
            set step [expr {$xv > $previous ? 1 : -1}]
            if {$direction == 0} { set direction $step }
            if {$step != $direction} { error "Scientific Spectrum API v1: X must be strictly monotonic" }
        }
        lappend x $xv
        lappend y $yv
        set previous $xv
    }
    set metadata [expr {[dict exists $fields metadata] ? [dict get $fields metadata] : [dict create]}]
    set provenance [expr {[dict exists $fields provenance] ? [dict get $fields provenance] : [dict create]}]
    _dict $metadata metadata
    _dict $provenance provenance
    set result [dict create]
    foreach key {spectrum_id display_name spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {
        dict set result $key [dict get $fields $key]
    }
    dict set result contract spectrum.scientific
    dict set result x $x
    dict set result y $y
    dict set result sample_count $count
    dict set result x_ordering [expr {$direction == 1 ? "ascending" : "descending"}]
    dict set result x_min [expr {min([lindex $x 0], [lindex $x end])}]
    dict set result x_max [expr {max([lindex $x 0], [lindex $x end])}]
    dict set result metadata $metadata
    dict set result provenance $provenance
    foreach key {source_identity source_hash entity_id} {
        dict set result $key [expr {[dict exists $fields $key] ? [dict get $fields $key] : ""}]
    }
    dict set result spectrum_hash [_hash $result]
    return $result
}

proc ::GX::SpectrumAPIv1::validate {spectrum} {
    _dict $spectrum spectrum
    set rebuilt [create $spectrum]
    foreach key {sample_count x_ordering x_min x_max spectrum_hash} {
        if {![dict exists $spectrum $key] || [dict get $spectrum $key] ne [dict get $rebuilt $key]} {
            error "Scientific Spectrum API v1: $key does not match spectrum data"
        }
    }
    if {![dict exists $spectrum contract] || [dict get $spectrum contract] ne "spectrum.scientific"} {
        error "Scientific Spectrum API v1: wrong spectrum contract"
    }
    return 1
}

proc ::GX::SpectrumAPIv1::axisInfo {spectrum} {
    validate $spectrum
    set out [dict create]
    foreach key {sample_count x_ordering x_min x_max x_quantity x_unit y_quantity y_representation y_unit} {
        dict set out $key [dict get $spectrum $key]
    }
    return $out
}
