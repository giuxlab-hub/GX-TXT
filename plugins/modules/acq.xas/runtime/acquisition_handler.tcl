# SPDX-License-Identifier: GPL-3.0-or-later
# XAS acquisition handler. External text parsing and reusable array mathematics
# are delegated to public GX-TXT APIs.

namespace eval ::XASAcq {
    variable moduleId acq.xas
}

proc ::XASAcq::_cfg {request key {default ""}} {
    if {[dict exists $request config $key]} { return [dict get $request config $key] }
    return $default
}
proc ::XASAcq::_int {value label {min 0}} {
    if {![string is integer -strict $value] || $value < $min} { error "$label must be an integer >= $min." }
    return $value
}
proc ::XASAcq::_finite {value} {
    expr {[string is double -strict $value] && ![regexp -nocase {nan|inf} [string trim $value]]}
}
proc ::XASAcq::_options {request {scanAll 0}} {
    set header [_cfg $request header absent]
    set opts [dict create delimiter [_cfg $request delimiter auto] header $header \
        header_row [_int [_cfg $request header_row 1] "Header row" 1] \
        skip_rows [_int [_cfg $request skip_rows 0] "Skip rows" 0] \
        comment_prefixes {#} encoding utf-8 nonfinite allow preview_rows 5 scan_all $scanAll]
    return $opts
}
proc ::XASAcq::_columnList {value label width} {
    set value [string map {"," ";" " " ";"} [string trim $value]]
    set out {}
    foreach item [split $value ";"] {
        set item [string trim $item]
        if {$item eq ""} continue
        _int $item $label 1
        if {$item > $width} { error "$label column $item is outside 1..$width." }
        if {$item in $out} { error "$label repeats column $item." }
        lappend out $item
    }
    if {![llength $out]} { error "$label requires at least one column." }
    return $out
}
proc ::XASAcq::_energyUnit {request preview energyIndex} {
    set configured [_cfg $request energy_unit auto]
    if {$configured ne "auto"} { return $configured }
    # Athena/Demeter-compatible practical inference: an increasing edge scan
    # near values <=100 is normally expressed in keV; larger values are eV.
    set vals {}
    foreach row $preview {
        if {[llength $row] < $energyIndex} continue
        set v [lindex $row [expr {$energyIndex-1}]]
        if {[_finite $v]} {lappend vals [expr {double($v)}]}
        if {[llength $vals] >= 5} break
    }
    if {[llength $vals] < 2} { error "Energy unit auto-detection needs at least two finite preview values." }
    set increasing 1
    for {set i 1} {$i < [llength $vals]} {incr i} {
        if {[lindex $vals $i] <= [lindex $vals [expr {$i-1}]]} {set increasing 0; break}
    }
    if {!$increasing} { error "Energy unit auto-detection requires an increasing energy scan; choose eV or keV explicitly." }
    return [expr {[lindex $vals 0] > 100.0 ? "eV" : "keV"}]
}
proc ::XASAcq::inspect {request} {
    set path [dict get $request source_path]
    set result [dict create recognized 0 format xas.text variables {} metadata [dict create] preview_rows {} warnings {}]
    if {![file isfile $path]} { return $result }
    if {[catch {set info [::GX::TabularTextAPIv1::inspect $path [_options $request 0]]} err]} {
        dict lappend result warnings $err
        return $result
    }
    set width [dict get $info column_count]
    set preview [dict get $info preview_rows]
    set energy [_int [_cfg $request energy_column 1] "Energy column" 1]
    if {$energy > $width} {dict lappend result warnings "Energy column $energy is outside the detected $width columns."; return $result}
    if {[catch {set unit [_energyUnit $request $preview $energy]} uerr]} {
        set unit unknown
        dict lappend result warnings $uerr
    }
    set shown {}
    foreach row $preview {lappend shown [lrange $row 0 [expr {min(7,[llength $row]-1)}]]}
    if {$width > 8} {dict lappend result warnings "Wide XAS table: preview shows the first 8 of $width columns."}
    dict set result recognized [expr {$width >= 2}]
    dict set result preview_rows $shown
    dict set result metadata [dict create source_file [file tail $path] column_count $width \
        input_mode [_cfg $request input_mode processed_family] energy_column $energy energy_unit $unit]
    return $result
}
proc ::XASAcq::_openAll {request path columns} {
    set opened [::GX::TabularTextAPIv1::open $path [_options $request 0]]
    set h [dict get $opened handle]
    set width [dict get $opened column_count]
    set rows {}
    try {
        set chunkRows [_int [_cfg $request chunk_rows 2048] "Chunk rows" 1]
        while {1} {
            set chunk [::GX::TabularTextAPIv1::next $h $chunkRows $columns $columns]
            foreach row [dict get $chunk rows] {lappend rows $row}
            if {[dict get $chunk eof]} break
        }
    } finally {
        ::GX::TabularTextAPIv1::close $h
    }
    return [list $width $rows]
}
proc ::XASAcq::_writeFamily {request width energyCol firstCol lastCol energyUnit} {
    set source [dict get $request raw_path]
    if {$lastCol == 0} {set lastCol $width}
    if {$firstCol < 1 || $lastCol < $firstCol || $lastCol > $width || $energyCol > $width} {
        error "Invalid processed-family column range."
    }
    set specCols {}
    for {set c $firstCol} {$c <= $lastCol} {incr c} {
        if {$c != $energyCol} {lappend specCols $c}
    }
    if {[llength $specCols] < 2} {error "A spectrum.family import requires at least two spectrum columns."}
    set selected [linsert $specCols 0 $energyCol]
    lassign [_openAll $request $source $selected] _ rows
    set base [dict get $request dataset_id]
    set outDir [dict get $request output_dir]
    set rel [file join $base xas_family.csv]
    set abs [file join $outDir $rel]
    file mkdir [file dirname $abs]
    set f [open $abs w]; fconfigure $f -encoding utf-8 -translation lf
    puts $f "member_id,parameter_value,spectral_x,spectral_y"
    set invalid [dict create]; set written [dict create]
    set omittedEnergyRows 0; set omittedSpectralSamples 0
    for {set j 0} {$j < [llength $specCols]} {incr j} {
        dict set written [format "spectrum_%03d" [expr {$j+1}]] 0
    }
    set policy [_cfg $request nonfinite_policy omit_samples]
    set previousEnergy ""; set energyDirection 0
    foreach row $rows {
        set energy [lindex $row 0]
        if {![_finite $energy]} {
            incr omittedEnergyRows
            if {$policy eq "error"} {close $f; error "Processed XAS energy contains NaN/Inf."}
            continue
        }
        set energy [expr {double($energy)}]
        if {$previousEnergy ne ""} {
            if {$energy == $previousEnergy} {close $f; error "Processed XAS energy contains duplicate samples."}
            set step [expr {$energy > $previousEnergy ? 1 : -1}]
            if {$energyDirection == 0} {set energyDirection $step}
            if {$step != $energyDirection} {close $f; error "Processed XAS energy must be strictly monotonic."}
        }
        set previousEnergy $energy
        for {set j 0} {$j < [llength $specCols]} {incr j} {
            set y [lindex $row [expr {$j+1}]]
            set member [format "spectrum_%03d" [expr {$j+1}]]
            if {![_finite $y]} {
                dict incr invalid $member
                incr omittedSpectralSamples
                if {$policy eq "error"} {close $f; error "Processed XAS member $member contains NaN/Inf."}
                continue
            }
            puts $f "$member,[expr {$j+1}],[format %.17g $energy],[format %.17g $y]"
            dict incr written $member
        }
    }
    close $f
    set unusable {}
    foreach member [lsort [dict keys $written]] {
        if {[dict get $written $member] < 2} {lappend unusable $member}
    }
    if {[llength $unusable]} {
        file delete -force -- $abs
        error "Processed XAS family contains members with fewer than two finite samples: [join $unusable {, }]."
    }
    set metadata [dict create source.original_filename [file tail [dict get $request source_path]] \
        xas.input_mode processed_family xas.energy_unit $energyUnit xas.energy_column $energyCol \
        xas.family_parameter_quantity spectrum_index xas.family_parameter_unit 1 \
        xas.member_count [llength $specCols] xas.nonfinite_policy $policy \
        xas.omitted_energy_rows $omittedEnergyRows xas.omitted_nonfinite_samples $omittedSpectralSamples]
    set schema [list \
        [dict create variable_id member_id canonical member_id source_column 1 dtype string semantic_role member_identity] \
        [dict create variable_id parameter_value canonical parameter_value source_column 2 dtype float64 unit 1 semantic_role parameter] \
        [dict create variable_id spectral_x canonical spectral_x source_column 3 dtype float64 unit $energyUnit semantic_role independent coordinate_role coordinate axis_kind explicit] \
        [dict create variable_id spectral_y canonical spectral_y source_column 4 dtype float64 unit 1 semantic_role measured coordinate_variable_ids spectral_x]]
    set notes "Processed XAS spectral family. Original energy and mu values are preserved; non-finite handling is explicit."
    if {[dict size $invalid]} {append notes " Omitted non-finite samples: $invalid."}
    return [dict create dataset_id $base contract spectrum.family format csv path $rel \
        variables {member_id parameter_value spectral_x spectral_y} units [list {} 1 $energyUnit 1] \
        semantic_roles {member_identity parameter independent measured} source [dict get $request source_path] \
        provenance "acq.xas 1.0.1 processed-family import; family coordinate=spectrum_index" \
        structured_metadata $metadata variable_schema $schema notes $notes]
}
proc ::XASAcq::_writeSingleProcessed {request width energyCol muCol energyUnit} {
    if {$energyCol > $width || $muCol > $width || $energyCol == $muCol} {error "Invalid processed-spectrum column mapping."}
    lassign [_openAll $request [dict get $request raw_path] [list $energyCol $muCol]] _ rows
    return [_writeSingleRows $request $rows $energyUnit processed_single "Imported processed mu(E)."]
}
proc ::XASAcq::_sumColumns {matrix} {
    if {![llength $matrix]} {return {}}
    set cols [llength [lindex $matrix 0]]
    if {$cols == 1} {
        set out {}; foreach row $matrix {lappend out [lindex $row 0]}; return $out
    }
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set r [::GX::NumericAPIv1::arrayReduce sum [dict create kind matrix value $matrix] [dict create axis 2]]
    return [dict get $r values]
}
proc ::XASAcq::_writeRaw {request width energyCol energyUnit mode} {
    set nums [_columnList [_cfg $request numerator_columns ""] "Numerator" $width]
    set dens [_columnList [_cfg $request denominator_columns ""] "Denominator" $width]
    if {$energyCol in $nums || $energyCol in $dens} {error "Energy column cannot also be a detector column."}
    set selected [concat [list $energyCol] $nums $dens]
    if {[llength [lsort -unique $selected]] != [llength $selected]} {error "Raw numerator and denominator column sets must not overlap."}
    lassign [_openAll $request [dict get $request raw_path] $selected] _ rows
    set energies {}; set nmat {}; set dmat {}; set invalidInput 0
    foreach row $rows {
        set ok 1
        foreach v $row {if {![_finite $v]} {set ok 0; break}}
        if {!$ok} {
            incr invalidInput
            if {[_cfg $request nonfinite_policy omit_samples] eq "error"} {error "Raw XAS selected columns contain NaN/Inf."}
            continue
        }
        lappend energies [lindex $row 0]
        set nend [llength $nums]
        lappend nmat [lrange $row 1 $nend]
        lappend dmat [lrange $row [expr {$nend+1}] end]
    }
    set nsum [_sumColumns $nmat]; set dsum [_sumColumns $dmat]
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set ratio [dict get [::GX::NumericAPIv1::arrayBinary divide \
        [dict create kind vector value $nsum] [dict create kind vector value $dsum] [dict create nonfinite ieee]] values]
    if {$mode eq "raw_transmission"} {
        set absr [dict get [::GX::NumericAPIv1::arrayUnary abs [dict create kind vector value $ratio] [dict create nonfinite ieee]] values]
        set mu [dict get [::GX::NumericAPIv1::arrayUnary log [dict create kind vector value $absr] [dict create nonfinite ieee]] values]
        set formula {mu(E)=ln(abs(sum(numerator)/sum(denominator)))}
    } else {
        set mu $ratio
        set formula {mu(E)=sum(numerator)/sum(denominator)}
    }
    set filtered {}; set omitted $invalidInput
    foreach e $energies y $mu {
        if {![_finite $e] || ![_finite $y]} {
            incr omitted
            if {[_cfg $request nonfinite_policy omit_samples] eq "error"} {error "Raw XAS formula produced NaN/Inf."}
            continue
        }
        lappend filtered [list $e $y]
    }
    if {[llength $filtered] < 2} {error "Raw XAS conversion produced fewer than two finite samples."}
    set extra [dict create xas.raw_numerator_columns [join $nums ";"] xas.raw_denominator_columns [join $dens ";"] \
        xas.raw_formula $formula xas.omitted_samples $omitted]
    return [_writeSingleRows $request $filtered $energyUnit $mode $formula $extra]
}
proc ::XASAcq::_writeSingleRows {request rows energyUnit mode note {extraMetadata {}}} {
    set base [dict get $request dataset_id]; set outDir [dict get $request output_dir]
    set rel [file join $base xas_spectrum.csv]; set abs [file join $outDir $rel]
    file mkdir [file dirname $abs]
    set f [open $abs w]; fconfigure $f -encoding utf-8 -translation lf
    puts $f "spectral_x,spectral_y"
    set n 0; set policy [_cfg $request nonfinite_policy omit_samples]; set omitted 0
    set previous ""; set direction 0
    foreach row $rows {
        lassign $row x y
        if {![_finite $x] || ![_finite $y]} {
            incr omitted
            if {$policy eq "error"} {close $f; error "XAS spectrum contains NaN/Inf."}
            continue
        }
        set x [expr {double($x)}]; set y [expr {double($y)}]
        if {$previous ne ""} {
            if {$x == $previous} {close $f; error "XAS energy contains duplicate samples."}
            set step [expr {$x > $previous ? 1 : -1}]
            if {$direction == 0} {set direction $step}
            if {$step != $direction} {close $f; error "XAS energy must be strictly monotonic."}
        }
        set previous $x
        puts $f "[format %.17g $x],[format %.17g $y]"
        incr n
    }
    close $f
    if {$n < 2} {error "XAS spectrum requires at least two finite samples."}
    set metadata [dict create source.original_filename [file tail [dict get $request source_path]] \
        xas.input_mode $mode xas.energy_unit $energyUnit xas.nonfinite_policy $policy xas.omitted_samples $omitted]
    if {$extraMetadata ne ""} {dict for {k v} $extraMetadata {dict set metadata $k $v}}
    set schema [list \
        [dict create variable_id spectral_x canonical spectral_x source_column 1 dtype float64 unit $energyUnit semantic_role independent coordinate_role coordinate axis_kind explicit] \
        [dict create variable_id spectral_y canonical spectral_y source_column 2 dtype float64 unit 1 semantic_role measured coordinate_variable_ids spectral_x]]
    return [dict create dataset_id $base contract spectrum.scientific format csv path $rel \
        variables {spectral_x spectral_y} units [list $energyUnit 1] semantic_roles {independent measured} \
        source [dict get $request source_path] provenance "acq.xas 1.0.1 $mode import" \
        structured_metadata $metadata variable_schema $schema notes $note]
}
proc ::XASAcq::import {request} {
    set info [::GX::TabularTextAPIv1::inspect [dict get $request raw_path] [_options $request 0]]
    set width [dict get $info column_count]
    set energyCol [_int [_cfg $request energy_column 1] "Energy column" 1]
    if {$energyCol > $width} {error "Energy column $energyCol is outside 1..$width."}
    set unit [_energyUnit $request [dict get $info preview_rows] $energyCol]
    set mode [_cfg $request input_mode processed_family]
    switch -- $mode {
        processed_family {
            set ds [_writeFamily $request $width $energyCol \
                [_int [_cfg $request first_spectrum_column 2] "First spectrum column" 1] \
                [_int [_cfg $request last_spectrum_column 0] "Last spectrum column" 0] $unit]
        }
        processed_single {
            set ds [_writeSingleProcessed $request $width $energyCol \
                [_int [_cfg $request single_mu_column 2] "mu(E) column" 1] $unit]
        }
        raw_transmission - raw_fluorescence - raw_ratio {
            set ds [_writeRaw $request $width $energyCol $unit $mode]
        }
        default {error "Unsupported XAS source layout '$mode'."}
    }
    return [dict create datasets [list $ds]]
}
