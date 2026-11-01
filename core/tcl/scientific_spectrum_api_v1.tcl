# GX-TXT Scientific Spectrum API v1 — domain-neutral one-dimensional spectrum.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectrumAPIv1 {
    variable apiVersion 1
    variable contract spectrum.scientific
}

proc ::GX::SpectrumAPIv1::apiInfo {} {
    variable apiVersion
    variable contract
    return [dict create api_name SCIENTIFIC_SPECTRUM_API_v1 api_version $apiVersion contract $contract host_validation_operations {validatePages} page_samples_max 4096]
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

proc ::GX::SpectrumAPIv1::_hashHeader {channel spec} {
    foreach key {spectrum_kind x_quantity x_unit y_quantity y_representation y_unit} {puts $channel [_required $spec $key]}
}
proc ::GX::SpectrumAPIv1::_hashRows {channel xValues yValues} {
    foreach x $xValues y $yValues {puts $channel "[format %.17g $x]\t[format %.17g $y]"}
}
proc ::GX::SpectrumAPIv1::_samplePage {state xRaw yRaw} {
    if {[llength $xRaw]!=[llength $yRaw]} {error {Scientific Spectrum API v1: X/Y page lengths differ}}
    set x {};set y {};set i [dict get $state index];set direction [dict get $state direction];set previous [dict get $state previous]
    foreach xv $xRaw yv $yRaw {
        set xv [_finite $xv "x sample $i"];set yv [_finite $yv "y sample $i"]
        if {$i>0} {
            if {$xv==$previous} {error "Scientific Spectrum API v1: X contains a duplicate at sample $i"}
            set step [expr {$xv>$previous?1:-1}]
            if {$direction==0} {set direction $step}
            if {$step!=$direction} {error {Scientific Spectrum API v1: X must be strictly monotonic}}
        } else {dict set state first $xv}
        lappend x $xv;lappend y $yv;set previous $xv;incr i
    }
    dict set state index $i;dict set state direction $direction;dict set state previous $previous
    return [dict create state $state x $x y $y]
}
proc ::GX::SpectrumAPIv1::_sampleInitial {} {return {index 0 direction 0 previous {} first {}}}
proc ::GX::SpectrumAPIv1::_hash {spec} {
    # The numerical hash excludes identity, names and provenance, so copies of
    # the same scientific trace can be detected across independent libraries.
    set channel [file tempfile path]
    fconfigure $channel -translation lf -encoding utf-8
    try {
        _hashHeader $channel $spec
        _hashRows $channel [dict get $spec x] [dict get $spec y]
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
    set page [_samplePage [_sampleInitial] $xRaw $yRaw]
    set x [dict get $page x];set y [dict get $page y];set direction [dict get $page state direction]
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

# Trusted host page reader only, not an authored Tcl/Script Bridge/native grant.
# It returns real X/Y samples by offset/count from an already admitted owner.
# All value rules and the numerical hash are the same implementation as create.
proc ::GX::SpectrumAPIv1::validatePages {fields count reader} {
    _dict $fields fields
    if {![string is wideinteger -strict $count] || $count<2 || $count>536870912} {error {Scientific Spectrum API v1: invalid bounded sample count}}
    if {[catch {llength $reader}] || ![llength $reader]} {error {Scientific Spectrum API v1: a trusted page reader is required}}
    set channel [file tempfile path];fconfigure $channel -translation lf -encoding utf-8
    try {
        _hashHeader $channel $fields
        set state [_sampleInitial]
        for {set offset 0} {$offset<$count} {incr offset $n} {
            set n [expr {min(4096,$count-$offset)}]
            set raw [uplevel #0 [list {*}$reader $offset $n]]
            if {[catch {dict size $raw}] || [lsort [dict keys $raw]] ne {x y} || [llength [dict get $raw x]]!=$n || [llength [dict get $raw y]]!=$n} {error {Scientific Spectrum API v1: page reader returned a different exact sample count/schema}}
            set page [_samplePage $state [dict get $raw x] [dict get $raw y]]
            set state [dict get $page state]
            _hashRows $channel [dict get $page x] [dict get $page y]
        }
        close $channel;set channel {}
        return [dict create sample_count $count spectrum_hash [::GX::sha256File $path] x_ordering [expr {[dict get $state direction]==1?{ascending}:{descending}}] x_min [expr {min([dict get $state first],[dict get $state previous])}] x_max [expr {max([dict get $state first],[dict get $state previous])}]]
    } finally {if {$channel ne {}} {catch {close $channel}};catch {file delete -- $path}}
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
