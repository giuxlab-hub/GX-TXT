# GX-TXT Acquisition Handler Plugin API v1
# Tektronix current log importer
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it

namespace eval ::TektronixCurrentLog {
    variable apiVersion 1
    variable defaultTimezone "Europe/Rome"
    variable defaultMarker "Adc"
}

proc ::TektronixCurrentLog::_trimField {s} {
    set s [string trim $s]
    if {[string length $s] >= 2 && [string index $s 0] eq "\"" && [string index $s end] eq "\""} {
        set s [string range $s 1 end-1]
    }
    return [string trim $s]
}

proc ::TektronixCurrentLog::_fields {line} {
    set out {}
    foreach f [split [string trimright $line "\r\n"] ","] {
        lappend out [_trimField $f]
    }
    return $out
}

proc ::TektronixCurrentLog::_isNumber {s} {
    set s [string trim $s]
    if {$s eq ""} { return 0 }
    return [string is double -strict $s]
}

proc ::TektronixCurrentLog::_monthNumber {mon} {
    array set months {
        JAN 01 FEB 02 MAR 03 APR 04 MAY 05 JUN 06
        JUL 07 AUG 08 SEP 09 OCT 10 NOV 11 DEC 12
    }
    set key [string toupper [string trim $mon]]
    if {![info exists months($key)]} { error "Unsupported month abbreviation '$mon'." }
    return $months($key)
}

proc ::TektronixCurrentLog::_normalizeDate {dateText} {
    set d [string trim $dateText]
    if {![regexp {^([0-9]{1,2})-([A-Za-z]{3})-([0-9]{4})$} $d -> day mon year]} {
        error "Invalid Tektronix date '$dateText'."
    }
    set month [_monthNumber $mon]
    return [format "%04d-%02d-%02d" $year $month $day]
}

proc ::TektronixCurrentLog::_parseEpoch {dateText timeText timezone} {
    set isoDate [_normalizeDate $dateText]
    set t [string trim $timeText]
    if {![regexp {^[0-9]{1,2}:[0-9]{2}:[0-9]{2}$} $t]} {
        error "Invalid Tektronix time '$timeText'."
    }
    if {[catch {
        clock scan "$isoDate $t" -format "%Y-%m-%d %H:%M:%S" -timezone $timezone
    } epoch]} {
        error "Unable to parse Tektronix timestamp '$dateText $timeText' in time zone '$timezone': $epoch"
    }
    return $epoch
}

proc ::TektronixCurrentLog::_findTimestampInFields {fields} {
    set n [llength $fields]
    for {set i 0} {$i < $n-1} {incr i} {
        set d [lindex $fields $i]
        set t [lindex $fields [expr {$i+1}]]
        if {[regexp {^[0-9]{1,2}-[A-Za-z]{3}-[0-9]{4}$} $d] && [regexp {^[0-9]{1,2}:[0-9]{2}:[0-9]{2}$} $t]} {
            set extra ""
            if {$i+2 < $n} { set extra [lindex $fields [expr {$i+2}]] }
            return [dict create found 1 date $d time $t extra $extra field_index [expr {$i+1}]]
        }
    }
    return [dict create found 0]
}

proc ::TektronixCurrentLog::_parseFile {path {marker ""}} {
    if {![file isfile $path]} { error "Input file does not exist: $path" }
    set f [open $path r]
    fconfigure $f -encoding utf-8 -translation auto

    set timestampRecords {}
    set values {}
    set markersSeen {}
    set detectedMarker ""
    set lineNo 0

    try {
        while {[gets $f line] >= 0} {
            incr lineNo
            if {[string trim $line] eq ""} continue
            set fields [_fields $line]

            set ts [_findTimestampInFields $fields]
            if {[dict get $ts found]} {
                dict set ts line_no $lineNo
                lappend timestampRecords $ts
            }

            if {[llength $fields] >= 3} {
                set valueText [lindex $fields 1]
                set rowMarker [lindex $fields 2]
                if {[_isNumber $valueText] && $rowMarker ne ""} {
                    if {[lsearch -nocase -exact $markersSeen $rowMarker] < 0} { lappend markersSeen $rowMarker }
                    if {$detectedMarker eq ""} { set detectedMarker $rowMarker }
                    set useMarker [expr {[string trim $marker] eq "" ? $detectedMarker : [string trim $marker]}]
                    if {[string equal -nocase $rowMarker $useMarker]} {
                        lappend values [expr {double($valueText)}]
                    }
                }
            }
        }
    } finally {
        close $f
    }

    set recognized [expr {[llength $timestampRecords] >= 2 && [llength $values] >= 1 && $detectedMarker ne ""}]
    return [dict create \
        recognized $recognized \
        timestamp_records $timestampRecords \
        values $values \
        detected_marker $detectedMarker \
        markers_seen $markersSeen]
}

proc ::TektronixCurrentLog::_seriesInfo {parsed timezone} {
    set records [dict get $parsed timestamp_records]
    set values [dict get $parsed values]
    if {[llength $records] < 2} { error "Tektronix current log requires at least two timestamp records (start/end)." }
    if {[llength $values] < 1} { error "Tektronix current log contains no measurement samples." }

    set first [lindex $records 0]
    set last [lindex $records end]
    set startEpoch [_parseEpoch [dict get $first date] [dict get $first time] $timezone]
    set endEpoch [_parseEpoch [dict get $last date] [dict get $last time] $timezone]
    if {$endEpoch < $startEpoch} { error "Tektronix end timestamp precedes start timestamp." }

    set n [llength $values]
    set duration [expr {double($endEpoch - $startEpoch)}]
    if {$n == 1} {
        set dt 0.0
    } else {
        set dt [expr {$duration / double($n - 1)}]
    }

    return [dict create \
        start_epoch $startEpoch end_epoch $endEpoch duration_s $duration \
        sample_count $n dt_s $dt \
        start_record $first end_record $last]
}

proc ::TektronixCurrentLog::_sampleTriple {info values index} {
    set n [dict get $info sample_count]
    if {$index < 0 || $index >= $n} { error "Sample index out of range: $index" }
    if {$n == 1} {
        set elapsed 0.0
    } elseif {$index == $n-1} {
        set elapsed [dict get $info duration_s]
    } else {
        set elapsed [expr {$index * [dict get $info dt_s]}]
    }
    set epoch [expr {[dict get $info start_epoch] + $elapsed}]
    return [list $epoch $elapsed [lindex $values $index]]
}

proc ::TektronixCurrentLog::_previewRows {info values {limit 12}} {
    set rows {}
    set n [dict get $info sample_count]
    set take [expr {$n < $limit ? $n : $limit}]
    for {set i 0} {$i < $take} {incr i} {
        lappend rows [_sampleTriple $info $values $i]
    }
    return $rows
}

proc ::TektronixCurrentLog::_configValue {request key default} {
    if {[dict exists $request config $key]} {
        set v [string trim [dict get $request config $key]]
        if {$v ne ""} { return $v }
    }
    return $default
}

proc ::TektronixCurrentLog::_variableMap {request} {
    # source_column is a stable plug-in ordinal for the three canonicalized fields:
    # 1=absolute epoch time, 2=file-local elapsed time, 3=current.
    set defaults [dict create \
        1 [dict create canonical timestamp_s unit s semantic_role timestamp] \
        2 [dict create canonical time_s unit s semantic_role time] \
        3 [dict create canonical current_A unit A semantic_role measure]]

    set selected [dict create]
    if {[dict exists $request variables]} {
        foreach v [dict get $request variables] {
            if {![dict exists $v source_column]} continue
            set col [dict get $v source_column]
            if {![dict exists $defaults $col]} continue
            set d [dict get $defaults $col]
            foreach k {canonical unit semantic_role} {
                if {[dict exists $v $k] && [string trim [dict get $v $k]] ne ""} {
                    dict set d $k [string trim [dict get $v $k]]
                }
            }
            dict set selected $col $d
        }
    }

    # A canonical time axis and current are mandatory for timeseries.table.
    foreach required {2 3} {
        if {![dict exists $selected $required]} {
            error "Tektronix current log import requires source variable $required ([dict get $defaults $required canonical]) to remain enabled."
        }
    }
    return $selected
}

proc ::TektronixCurrentLog::_csvQuote {s} {
    set s [string map [list "\"" "\"\""] $s]
    return "\"$s\""
}

proc ::TektronixCurrentLog::inspect {request} {
    set source [dict get $request source_path]
    set parsed [_parseFile $source]

    if {![dict get $parsed recognized]} {
        return [dict create \
            recognized 0 format tektronix.current_log \
            metadata [dict create source_file [file tail $source]] \
            variables {} preview_rows {} \
            warnings [list "File does not match the expected Tektronix current-log structure (start/end timestamps plus numeric measurement rows)."]]
    }

    variable defaultTimezone
    set warnings {}
    if {[catch {set info [_seriesInfo $parsed $defaultTimezone]} err]} {
        return [dict create recognized 0 format tektronix.current_log metadata [dict create source_file [file tail $source]] variables {} preview_rows {} warnings [list $err]]
    }

    set values [dict get $parsed values]
    set marker [dict get $parsed detected_marker]
    set first [dict get $info start_record]
    set last [dict get $info end_record]
    if {[llength [dict get $parsed markers_seen]] > 1} {
        lappend warnings "Multiple measurement markers were found: [join [dict get $parsed markers_seen] {, }]. Preview uses '$marker'."
    }
    if {[dict get $info sample_count] == 1} {
        lappend warnings "Only one measurement sample was found; reconstructed sample interval is 0 s."
    }

    set metadata [dict create \
        vendor Tektronix \
        format tektronix.current_log \
        source_file [file tail $source] \
        measurement_marker $marker \
        sample_count [dict get $info sample_count] \
        start_timestamp "[dict get $first date] [dict get $first time]" \
        end_timestamp "[dict get $last date] [dict get $last time]" \
        duration_s [format %.12g [dict get $info duration_s]] \
        reconstructed_dt_s [format %.12g [dict get $info dt_s]] \
        preview_timezone $defaultTimezone]
    if {[dict get $first extra] ne ""} {
        dict set metadata start_record_extra [dict get $first extra]
    }

    set variables [list \
        [dict create source_column 1 original_header reconstructed_timestamp canonical timestamp_s unit s semantic_role timestamp] \
        [dict create source_column 2 original_header reconstructed_elapsed canonical time_s unit s semantic_role time] \
        [dict create source_column 3 original_header $marker canonical current_A unit A semantic_role measure]]

    return [dict create \
        recognized 1 \
        format tektronix.current_log \
        metadata $metadata \
        variables $variables \
        preview_rows [_previewRows $info $values] \
        warnings $warnings]
}

proc ::TektronixCurrentLog::import {request} {
    set rawPath [dict get $request raw_path]
    set outDir [dict get $request output_dir]
    set datasetId [string trim [dict get $request dataset_id]]
    if {$datasetId eq ""} { error "Dataset ID is required." }

    variable defaultTimezone
    variable defaultMarker
    set timezone [_configValue $request source_timezone $defaultTimezone]
    set marker [_configValue $request measurement_marker $defaultMarker]
    set campaign [_configValue $request campaign_id ""]
    set series [_configValue $request series_id ""]

    set parsed [_parseFile $rawPath $marker]
    if {![dict get $parsed recognized]} {
        error "Selected RAW snapshot does not match the expected Tektronix current-log format."
    }
    set info [_seriesInfo $parsed $timezone]
    set values [dict get $parsed values]
    set n [dict get $info sample_count]

    set selected [_variableMap $request]
    set order {}
    foreach col {1 2 3} { if {[dict exists $selected $col]} { lappend order $col } }

    set names {}; set units {}; set roles {}
    foreach col $order {
        set d [dict get $selected $col]
        lappend names [dict get $d canonical]
        lappend units [dict get $d unit]
        lappend roles [dict get $d semantic_role]
    }

    set rel "${datasetId}.csv"
    set dst [file join $outDir $rel]
    set f [open $dst w]
    fconfigure $f -encoding utf-8 -translation lf
    try {
        puts $f [join $names ,]
        for {set i 0} {$i < $n} {incr i} {
            lassign [_sampleTriple $info $values $i] epoch elapsed current
            set row {}
            foreach col $order {
                switch -- $col {
                    1 { lappend row [format %.12g $epoch] }
                    2 { lappend row [format %.12g $elapsed] }
                    3 { lappend row [format %.12g $current] }
                }
            }
            puts $f [join $row ,]
        }
    } finally {
        close $f
    }

    set first [dict get $info start_record]
    set last [dict get $info end_record]
    set notesParts [list \
        "campaign_id=$campaign" \
        "series_id=$series" \
        "source_timezone=$timezone" \
        "measurement_marker=$marker" \
        "start_timestamp=[dict get $first date] [dict get $first time]" \
        "end_timestamp=[dict get $last date] [dict get $last time]" \
        "sample_count=$n" \
        "reconstructed_dt_s=[format %.12g [dict get $info dt_s]]"]
    if {[dict get $first extra] ne ""} { lappend notesParts "start_record_extra=[dict get $first extra]" }
    set notes [join $notesParts "; "]

    set provenance "Tektronix current log; one RAW file -> one canonical timeseries.table; inclusive start/end timestamp reconstruction; $notes"

    set dataset [dict create \
        dataset_id $datasetId \
        contract timeseries.table \
        format csv \
        path $rel \
        variables $names \
        units $units \
        semantic_roles $roles \
        source "Tektronix current log ($marker)" \
        provenance $provenance \
        notes $notes]

    return [dict create datasets [list $dataset]]
}
