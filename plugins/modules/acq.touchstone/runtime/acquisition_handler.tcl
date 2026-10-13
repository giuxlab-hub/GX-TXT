# Touchstone v1 acquisition handler. Port order is column-major, as in .s2p.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Touchstone {}
proc ::GX::Touchstone::_parse {path} {
    if {![file isfile $path]} {error "Touchstone source is missing"}
    if {![regexp -nocase {\.s([0-9]+)p$} $path -> ports] || $ports < 1 || $ports > 32} {
        error "Touchstone filename must end in .sNp with 1 to 32 ports"
    }
    set channel [open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set unit GHz; set format MA; set reference 50.0; set pending {}; set records {}; set previous -Inf
    try {
        while {[gets $channel line] >= 0} {
            set line [string trim [lindex [split $line !] 0]]
            if {$line eq ""} continue
            if {[string index $line 0] eq "#"} {
                set words [string toupper [string range $line 1 end]]
                set tokens [regexp -all -inline {\S+} $words]
                if {[llength $tokens] < 3 || [lindex $tokens 1] ne "S"} {error "Only Touchstone S parameters are supported"}
                set unit [lindex $tokens 0];set format [lindex $tokens 2]
                if {$unit ni {HZ KHZ MHZ GHZ} || $format ni {RI MA DB}} {error "Unsupported Touchstone unit or format"}
                set index [lsearch -exact $tokens R]
                if {$index >= 0} {
                    set reference [lindex $tokens [expr {$index+1}]]
                    if {![string is double -strict $reference] || $reference <= 0} {error "Invalid Touchstone reference impedance"}
                }
                continue
            }
            if {[string index $line 0] eq "\["} {error "Touchstone 2 keyword records require a dedicated importer"}
            foreach token [regexp -all -inline {\S+} $line] {
                set token [string map {D E d e} $token]
                if {![string is double -strict $token]} {error "Touchstone data contains a nonnumeric token"}
                lappend pending $token
            }
            set width [expr {1+2*$ports*$ports}]
            while {[llength $pending] >= $width} {
                set record [lrange $pending 0 [expr {$width-1}]]
                set pending [lrange $pending $width end]
                set f [expr {double([lindex $record 0])}]
                if {$f <= $previous} {error "Touchstone frequency must increase strictly"}
                set previous $f
                lappend records $record
            }
        }
    } finally {close $channel}
    if {[llength $pending]} {error "Incomplete Touchstone frequency record"}
    if {![llength $records]} {error "Touchstone source has no network records"}
    set scale [dict get [dict create HZ 1 KHZ 1e3 MHZ 1e6 GHZ 1e9] [string toupper $unit]]
    set converted {}
    foreach record $records {
        set row [list [format %.17g [expr {double([lindex $record 0])*$scale}]]]
        for {set column 1} {$column <= $ports} {incr column} {
            for {set r 1} {$r <= $ports} {incr r} {
                set k [expr {1+2*(($column-1)*$ports+$r-1)}]
                set first [expr {double([lindex $record $k])}]
                set second [expr {double([lindex $record [expr {$k+1}]])}]
                switch -- [string toupper $format] {
                    RI {set real $first;set imaginary $second}
                    MA {set real [expr {$first*cos($second*acos(-1)/180)}];set imaginary [expr {$first*sin($second*acos(-1)/180)}]}
                    DB {set magnitude [expr {pow(10,$first/20.0)}];set real [expr {$magnitude*cos($second*acos(-1)/180)}];set imaginary [expr {$magnitude*sin($second*acos(-1)/180)}]}
                }
                lappend row [format %.17g $real] [format %.17g $imaginary]
            }
        }
        lappend converted $row
    }
    set names {frequency_Hz};set units {Hz};set roles {frequency}
    for {set column 1} {$column <= $ports} {incr column} {
        for {set r 1} {$r <= $ports} {incr r} {
            lappend names "s${r}${column}_real" "s${r}${column}_imag"
            lappend units {} {};lappend roles network_real network_imaginary
        }
    }
    return [dict create ports $ports source_unit [string toupper $unit] source_format [string toupper $format] reference_ohm $reference names $names units $units roles $roles rows $converted]
}
proc ::GX::Touchstone::inspect {request} {
    set path [dict get $request source_path]
    if {[catch {set parsed [_parse $path]} problem]} {
        return [dict create recognized 0 format touchstone.sparameters metadata [dict create source_file [file tail $path]] variables {} preview_rows {} warnings [list $problem]]
    }
    set variables {};set index 0
    foreach name [dict get $parsed names] unit [dict get $parsed units] role [dict get $parsed roles] {
        incr index
        lappend variables [dict create source_column $index original_header $name canonical $name unit $unit semantic_role $role]
    }
    set metadata [dict create format touchstone.sparameters port_count [dict get $parsed ports] reference_impedance_ohm [dict get $parsed reference_ohm] source_representation [dict get $parsed source_format] source_frequency_unit [dict get $parsed source_unit] sample_count [llength [dict get $parsed rows]]]
    return [dict create recognized 1 format touchstone.sparameters metadata $metadata variables $variables preview_rows [lrange [dict get $parsed rows] 0 4] warnings {}]
}
proc ::GX::Touchstone::import {request} {
    set parsed [_parse [dict get $request raw_path]]
    set id [dict get $request dataset_id]
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id]} {error "Invalid Dataset ID"}
    set relative "${id}.csv"
    set destination [file join [dict get $request output_dir] $relative]
    set channel [open $destination w]
    fconfigure $channel -encoding utf-8 -translation lf
    try {
        puts $channel [join [dict get $parsed names] ,]
        foreach row [dict get $parsed rows] {puts $channel [join $row ,]}
    } finally {close $channel}
    set notes "Touchstone column-major port order; reference_impedance_ohm=[dict get $parsed reference_ohm]; source_format=[dict get $parsed source_format]; source_frequency_unit=[dict get $parsed source_unit]"
    set dataset [dict create dataset_id $id contract spectrum.table format csv path $relative variables [dict get $parsed names] units [dict get $parsed units] semantic_roles [dict get $parsed roles] source Touchstone provenance "Touchstone S-parameter acquisition; $notes" notes $notes]
    return [dict create datasets [list $dataset]]
}
