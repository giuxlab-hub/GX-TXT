# SPDX-License-Identifier: GPL-3.0-or-later
# Current-Session adapter for Rigol/CSV acquisition files.
#
# The inspector is deliberately lightweight: it reads only the configured
# header plus a small data sample, so very large oscilloscope exports can be
# previewed without loading the acquisition into memory.
namespace eval ::RigolCsv {
    variable runtimeDir [file dirname [file normalize [info script]]]
    variable previewRowLimit 8
}

proc ::RigolCsv::_config {request key default} {
    if {[dict exists $request config $key]} { return [dict get $request config $key] }
    return $default
}

proc ::RigolCsv::_delimiter {value} {
    switch -- $value {
        comma - "," { return , }
        semicolon - ";" { return {;} }
        tab { return "\t" }
        default { error "Rigol CSV delimiter must be comma, semicolon or tab." }
    }
}

proc ::RigolCsv::_cell {value} {
    set value [string trim $value " \t\r\n\""]
    if {[string length $value] && [scan [string index $value 0] %c code] == 1 && $code == 65279} {
        set value [string range $value 1 end]
    }
    return $value
}

proc ::RigolCsv::_canonical {value fallback usedVar} {
    upvar 1 $usedVar used
    set value [_cell $value]
    if {$value eq ""} { set value $fallback }
    set name [regsub -all {[^A-Za-z0-9_.-]} $value _]
    regsub -all {_+} $name _ name
    set name [string trim $name _]
    if {$name eq ""} { set name $fallback }
    if {![regexp {^[A-Za-z_]} $name]} { set name "C_$name" }
    set base $name
    set suffix 2
    while {[dict exists $used $name]} {
        set name "${base}_$suffix"
        incr suffix
    }
    dict set used $name 1
    return $name
}

proc ::RigolCsv::_unit {value} {
    set u [_cell $value]
    switch -nocase -- $u {
        volt - volts { return V }
        amp - amps - ampere - amperes { return A }
        second - seconds - sec { return s }
        default { return $u }
    }
}

proc ::RigolCsv::_trimTrailingEmpty {cells} {
    while {[llength $cells] && [_cell [lindex $cells end]] eq ""} {
        set cells [lrange $cells 0 end-1]
    }
    return $cells
}

proc ::RigolCsv::_numeric {value} {
    set value [_cell $value]
    return [expr {[string is double -strict $value] ? $value : ""}]
}

proc ::RigolCsv::inspect {request} {
    variable previewRowLimit
    set path [dict get $request source_path]
    set result [dict create recognized 0 format rigol.csv variables {} metadata [dict create] preview_rows {} warnings {}]
    if {![file isfile $path]} { return $result }

    set parser [_config $request parser rigol_ds1000z]
    set headerRows [_config $request header_rows 2]
    set delim [_delimiter [_config $request delimiter comma]]
    set seqCol [_config $request sequence_col 1]
    set timeCol [_config $request time_col 1]
    set configuredRaw [_config $request raw_fields 0]
    set configuredDrop [_config $request drop_trailing_fields 0]

    if {![string is integer -strict $headerRows] || $headerRows < 0} {
        error "Rigol header rows must be >= 0."
    }
    if {![string is integer -strict $configuredRaw] || $configuredRaw < 0} {
        error "Rigol raw fields must be 0 (auto) or an integer >= 2."
    }
    if {![string is integer -strict $configuredDrop] || $configuredDrop < 0} {
        error "Rigol trailing fields to ignore must be >= 0."
    }

    set headers {}
    set sampleLines {}
    set f [open $path r]
    fconfigure $f -encoding utf-8 -translation auto
    try {
        for {set i 0} {$i < $headerRows} {incr i} {
            if {[gets $f line] < 0} { return $result }
            lappend headers $line
        }
        while {[llength $sampleLines] < $previewRowLimit && [gets $f line] >= 0} {
            if {[string trim $line] eq ""} continue
            lappend sampleLines $line
        }
    } finally {
        close $f
    }
    if {![llength $sampleLines]} { return $result }

    set firstRaw [split [lindex $sampleLines 0] $delim]
    set detectedRaw [llength $firstRaw]
    set trimmed [_trimTrailingEmpty $firstRaw]
    set trailingEmpty [expr {$detectedRaw - [llength $trimmed]}]
    set rawUsed [expr {$configuredRaw > 0 ? $configuredRaw : $detectedRaw}]
    if {$rawUsed < 2} {
        dict lappend result warnings "The first data row has fewer than two CSV fields."
        return $result
    }
    if {$configuredDrop >= $rawUsed} {
        error "Rigol trailing fields to ignore must be smaller than the raw field count."
    }
    set effectiveCols [expr {$rawUsed - $configuredDrop}]

    set h1 {}
    set h2 {}
    if {$headerRows >= 1} { set h1 [split [lindex $headers 0] $delim] }
    if {$headerRows >= 2} { set h2 [split [lindex $headers 1] $delim] }

    set startVal ""
    set incrementVal ""
    if {$parser eq "rigol_ds1000z"} {
        if {$headerRows < 2} {
            dict lappend result warnings "The rigol_ds1000z parser requires at least two header rows."
        } else {
            set nmeta [expr {min([llength $h1], [llength $h2])}]
            for {set i 0} {$i < $nmeta} {incr i} {
                set key [_cell [lindex $h1 $i]]
                set val [_cell [lindex $h2 $i]]
                if {[string equal -nocase $key Start]} { set startVal [_numeric $val] }
                if {[string equal -nocase $key Increment]} { set incrementVal [_numeric $val] }
            }
            if {$startVal eq ""} { dict lappend result warnings "Rigol Start metadata was not found or is not numeric." }
            if {$incrementVal eq "" || $incrementVal <= 0} { dict lappend result warnings "Rigol Increment metadata was not found or is not a positive number." }
        }
    }

    set skipCol [expr {$parser eq "generic_time" ? $timeCol : $seqCol}]
    set vars {}
    set used [dict create]
    set signalCols {}
    for {set col 1} {$col <= $effectiveCols} {incr col} {
        if {$col == $skipCol} continue

        set primary ""
        set secondary ""
        if {$parser eq "rigol_ds1000z"} {
            if {$col <= [llength $h1]} { set primary [_cell [lindex $h1 [expr {$col-1}]]] }
            if {$col <= [llength $h2]} { set secondary [_cell [lindex $h2 [expr {$col-1}]]] }
            if {$primary eq "" || [string equal -nocase $primary Start] || [string equal -nocase $primary Increment]} continue
        } else {
            if {$headerRows > 0} {
                set lastHeader [split [lindex $headers end] $delim]
                if {$col <= [llength $lastHeader]} { set primary [_cell [lindex $lastHeader [expr {$col-1}]]] }
            }
        }

        if {$primary eq ""} { set primary "C$col" }
        set canonical [_canonical $primary "C$col" used]
        set unit [expr {$parser eq "rigol_ds1000z" ? [_unit $secondary] : ""}]
        if {$unit eq "" && $parser eq "rigol_ds1000z"} { set unit V }
        lappend signalCols $col
        lappend vars [dict create source_column $col source_channel $primary original_header $primary canonical $canonical unit $unit semantic_role signal]
    }

    set previewRows {}
    foreach line $sampleLines {
        set row [split $line $delim]
        set out {}
        if {$skipCol >= 1 && $skipCol <= [llength $row]} { lappend out [_cell [lindex $row [expr {$skipCol-1}]]] }
        foreach col $signalCols {
            if {$col <= [llength $row]} {
                lappend out [_cell [lindex $row [expr {$col-1}]]]
            } else {
                lappend out ""
            }
        }
        lappend previewRows $out
    }

    set metadata [dict create \
        parser $parser \
        source_file [file tail $path] \
        file_size_bytes [file size $path] \
        header_rows $headerRows \
        raw_fields_detected $detectedRaw \
        trailing_empty_fields_detected $trailingEmpty \
        raw_fields_used $rawUsed \
        effective_data_columns $effectiveCols]
    if {$parser eq "rigol_ds1000z" && $startVal ne ""} { dict set metadata start_s $startVal }
    if {$parser eq "rigol_ds1000z" && $incrementVal ne "" && $incrementVal > 0} {
        dict set metadata increment_s $incrementVal
        dict set metadata sample_rate_sa_s [expr {1.0 / double($incrementVal)}]
    }

    if {$configuredRaw > 0 && $configuredRaw != $detectedRaw} {
        dict lappend result warnings "Configured raw field count ($configuredRaw) differs from the first data row ($detectedRaw)."
    }
    if {$configuredDrop > 0 && $configuredDrop != $trailingEmpty} {
        dict lappend result warnings "Configured trailing-field drop count ($configuredDrop) differs from the first data row ($trailingEmpty)."
    }

    set recognized [expr {[llength $vars] > 0}]
    if {$parser eq "rigol_ds1000z" && ($startVal eq "" || $incrementVal eq "" || $incrementVal <= 0)} {
        set recognized 0
    }
    dict set result recognized $recognized
    dict set result variables $vars
    dict set result metadata $metadata
    dict set result preview_rows $previewRows
    return $result
}

proc ::RigolCsv::import {request} {
    variable runtimeDir
    set base [dict get $request dataset_id]
    set outDir [dict get $request output_dir]
    set workOut [file join $outDir $base]
    set cfg [dict get $request config]
    set variables [dict get $request variables]
    if {![llength $variables]} { error "Rigol import requires at least one enabled signal variable." }
    set channels {}; set names {}; set paths {}
    foreach v $variables {
        set col [dict get $v source_column]
        set name [string trim [dict get $v canonical]]
        set scope [string trim [expr {[dict exists $v source_channel] ? [dict get $v source_channel] : ""}]]
        if {![string is integer -strict $col] || $col < 1 || ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $name] ||
            [regexp {[|;]} $scope]} { error "Invalid Rigol signal mapping: column=$col name=$name scope=$scope" }
        if {$scope eq ""} { set scope $name }
        if {[lsearch -exact $names $name] >= 0} { error "Duplicate Rigol signal '$name'." }
        lappend names $name
        lappend channels "$col|$scope|$name"
        lappend paths [file join $base "${name}_canonical.csv"]
    }
    set worker [file join $runtimeDir gxtxt_csv_worker.m]
    set octave [::GX::runtimeToolRequired octave]
    set delimiter [_delimiter [dict get $cfg delimiter]]
    if {$delimiter eq "\t"} { set delimiter tab }
    set workers [::GX::configurationGet computation.default_workers]
    set tstart [dict get $cfg tstart]
    set dt [dict get $cfg dt]
    if {$tstart eq ""} { set tstart NaN }
    if {$dt eq ""} { set dt NaN }
    set cmd [list $octave --quiet --no-gui $worker \
        --input [dict get $request raw_path] --out $workOut \
        --parser [dict get $cfg parser] --delimiter $delimiter \
        --header-lines [dict get $cfg header_rows] \
        --sequence-col [dict get $cfg sequence_col] --time-col [dict get $cfg time_col] \
        --tstart $tstart --dt $dt \
        --channels [join $channels {;}] --make-rigol 0 --make-canonical 1 \
        --workers $workers --chunk-rows [dict get $cfg chunk_rows] \
        --raw-fields [dict get $cfg raw_fields] \
        --drop-trailing-fields [dict get $cfg drop_trailing_fields] \
        --strict-sequence [dict get $cfg strict_sequence]]
    if {[catch {exec {*}$cmd 2>@1} output]} { error "Rigol CSV worker failed: $output" }
    set datasets {}
    set index 0
    foreach v $variables path $paths {
        incr index
        if {![file isfile [file join $outDir $path]]} { error "Rigol worker did not publish '$path'." }
        set name [dict get $v canonical]
        set id [expr {$index == 1 ? $base : "$base.$name"}]
        lappend datasets [dict create dataset_id $id contract [dict get $request contract] \
            format csv path $path variables [list time_s $name] \
            units [list s [dict get $v unit]] semantic_roles [list time [dict get $v semantic_role]] \
            source [dict get $request source_path] \
            provenance "Rigol streaming CSV worker; source column [dict get $v source_column]" \
            notes "parser=[dict get $cfg parser]; worker_verified=1"]
    }
    return [dict create datasets $datasets]
}
