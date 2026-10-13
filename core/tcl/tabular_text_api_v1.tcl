# GX-TXT generic tabular text API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::TabularTextAPIv1 {
    variable handles
    variable nextId 0
    array set handles {}
}

proc ::GX::TabularTextAPIv1::_options {options} {
    set defaults [dict create delimiter auto header present header_row 1 skip_rows 0 \
        comment_prefixes {#} encoding utf-8 nonfinite error preview_rows 10 scan_all 0]
    if {[catch {dict size $options}]} {error "tabular text options must be a dictionary"}
    dict for {key value} $options {
        if {![dict exists $defaults $key]} {error "unknown tabular text option: $key"}
        dict set defaults $key $value
    }
    set delimiter [dict get $defaults delimiter]
    if {$delimiter ni {auto comma semicolon tab whitespace} && [string length $delimiter] != 1} {
        error "delimiter must be auto, comma, semicolon, tab, whitespace or one character"
    }
    if {[dict get $defaults header] ni {present absent}} {error "header must be present or absent"}
    foreach key {header_row skip_rows preview_rows} {
        set value [dict get $defaults $key]
        if {![string is integer -strict $value] || $value < 0} {error "$key must be a nonnegative integer"}
    }
    if {[dict get $defaults header] eq "present" && [dict get $defaults header_row] < 1} {
        error "header_row must be at least one when a header is present"
    }
    if {[dict get $defaults encoding] ne "utf-8"} {error "only UTF-8 text is supported"}
    if {[dict get $defaults nonfinite] ni {error allow}} {error "nonfinite must be error or allow"}
    if {[dict get $defaults scan_all] ni {0 1}} {error "scan_all must be 0 or 1"}
    return $defaults
}

proc ::GX::TabularTextAPIv1::_delimiter {name} {
    switch -- $name {
        comma {return ,}
        semicolon {return {;}}
        tab {return "\t"}
        default {return $name}
    }
}

proc ::GX::TabularTextAPIv1::_split {record delimiter} {
    if {$delimiter eq "whitespace"} {return [regexp -all -inline {\S+} [string trim $record]]}
    set fields {}; set field ""; set quoted 0; set closed 0; set atStart 1
    set n [string length $record]
    for {set i 0} {$i < $n} {incr i} {
        set char [string index $record $i]
        if {$quoted} {
            if {$char eq "\""} {
                if {$i+1 < $n && [string index $record [expr {$i+1}]] eq "\""} {
                    append field "\""; incr i
                } else {set quoted 0; set closed 1}
            } else {append field $char}
            continue
        }
        if {$char eq $delimiter} {
            lappend fields $field; set field ""; set closed 0; set atStart 1
        } elseif {$char eq "\"" && $atStart} {
            set quoted 1; set atStart 0
        } elseif {$closed && $char in {" " "\t"}} {
            continue
        } elseif {$closed || $char eq "\""} {
            error "invalid quoting in tabular record"
        } else {
            append field $char; set atStart 0
        }
    }
    if {$quoted} {error "unterminated quoted tabular field"}
    lappend fields $field
    return $fields
}

proc ::GX::TabularTextAPIv1::_complete {record} {
    set quoted 0; set n [string length $record]
    for {set i 0} {$i < $n} {incr i} {
        if {[string index $record $i] ne "\""} {continue}
        if {$quoted && $i+1 < $n && [string index $record [expr {$i+1}]] eq "\""} {incr i; continue}
        set quoted [expr {!$quoted}]
    }
    return [expr {!$quoted}]
}

proc ::GX::TabularTextAPIv1::_record {stateVar} {
    upvar 1 $stateVar state
    set channel [dict get $state channel]; set options [dict get $state options]
    while {1} {
        if {[gets $channel line] < 0} {return ""}
        dict incr state line_number
        if {[dict get $state line_number] == 1} {set line [string trimleft $line "\ufeff"]}
        if {[dict get $state line_number] <= [dict get $options skip_rows]} {continue}
        set trimmed [string trim $line]
        if {$trimmed eq ""} {continue}
        set comment 0
        foreach prefix [dict get $options comment_prefixes] {
            if {$prefix ne "" && [string first $prefix $trimmed] == 0} {set comment 1; break}
        }
        if {$comment} {continue}
        set record $line
        if {[dict get $state delimiter] ne "whitespace"} {
            while {![_complete $record]} {
                if {[gets $channel continuation] < 0} {error "unterminated quoted tabular record at line [dict get $state line_number]"}
                dict incr state line_number
                append record "\n" $continuation
            }
        }
        return $record
    }
}

proc ::GX::TabularTextAPIv1::_detect {record} {
    set matches {}
    foreach name {comma semicolon tab} {
        set delimiter [_delimiter $name]
        if {[string first $delimiter $record] < 0} {continue}
        if {![catch {set fields [_split $record $delimiter]}] && [llength $fields] > 1} {lappend matches $name}
    }
    if {[llength $matches] > 1} {error "ambiguous tabular delimiter; configure it explicitly"}
    if {[llength $matches] == 1} {
        set detected [lindex $matches 0]
        if {$detected eq "tab" && [llength [_split $record whitespace]] > [llength [_split $record "\t"]]} {
            error "ambiguous tab/whitespace delimiter; configure it explicitly"
        }
        return $detected
    }
    if {[llength [_split $record whitespace]] > 1} {return whitespace}
    error "cannot infer a tabular delimiter from the first record"
}

proc ::GX::TabularTextAPIv1::open {path {options {}}} {
    variable handles; variable nextId
    set options [_options $options]
    set path [file normalize $path]
    if {![file isfile $path] || ![file readable $path]} {error "tabular text source is unavailable: $path"}
    set channel [::open $path r]
    fconfigure $channel -encoding utf-8 -translation auto
    set state [dict create channel $channel options $options line_number 0 row_number 0 pending {} \
        delimiter [dict get $options delimiter]]
    set failed [catch {
        set delimiter [dict get $options delimiter]
        if {$delimiter eq "auto"} {
            set first [_record state]
            if {$first eq ""} {error "tabular text source is empty"}
            set delimiter [_detect $first]
            dict set state pending $first
        }
        dict set state delimiter $delimiter
        set actual [_delimiter $delimiter]
        if {[dict get $options header] eq "present"} {
            set n [dict get $options header_row]
            for {set i 1} {$i <= $n} {incr i} {
                if {[dict get $state pending] ne ""} {
                    set record [dict get $state pending]; dict set state pending {}
                } else {set record [_record state]}
                if {$record eq ""} {error "tabular text header is missing"}
            }
            set names [_split $record $actual]
            set width [llength $names]
            if {$width < 1} {error "tabular text header is empty"}
        } else {
            if {[dict get $state pending] ne ""} {
                set record [dict get $state pending]
            } else {
                set record [_record state]; dict set state pending $record
            }
            if {$record eq ""} {error "tabular text source contains no data rows"}
            set width [llength [_split $record $actual]]
            set names {}
            for {set i 1} {$i <= $width} {incr i} {lappend names $i}
        }
        dict set state width $width
        dict set state columns $names
    } reason opts]
    if {$failed} {::close $channel; return -options $opts $reason}
    set handle "tt_[pid]_[incr nextId]"
    set handles($handle) $state
    return [dict create handle $handle path $path delimiter $delimiter \
        column_count $width columns $names header [dict get $options header]]
}

proc ::GX::TabularTextAPIv1::_columns {columns width label {defaultAll 0}} {
    if {$columns eq "" && $defaultAll} {set columns {}; for {set i 1} {$i <= $width} {incr i} {lappend columns $i}}
    set seen {}
    foreach index $columns {
        if {![string is integer -strict $index] || $index < 1 || $index > $width} {error "$label column index is outside 1..$width"}
        if {$index in $seen} {error "$label column index is repeated"}
        lappend seen $index
    }
    return $columns
}

proc ::GX::TabularTextAPIv1::next {handle count {columns {}} {numericColumns {}}} {
    variable handles
    if {![info exists handles($handle)]} {error "unknown tabular text handle"}
    if {![string is integer -strict $count] || $count < 1} {error "chunk count must be positive"}
    set state $handles($handle); set width [dict get $state width]
    set columns [_columns $columns $width selected 1]
    set numericColumns [_columns $numericColumns $width numeric]
    foreach index $numericColumns {if {$index ni $columns} {error "numeric column must be selected"}}
    set options [dict get $state options]; set delimiter [_delimiter [dict get $state delimiter]]
    set rows {}; set eof 0
    for {set i 0} {$i < $count} {incr i} {
        if {[dict get $state pending] ne ""} {
            set record [dict get $state pending]; dict set state pending {}
        } else {set record [_record state]}
        if {$record eq ""} {set eof 1; break}
        set fields [_split $record $delimiter]
        if {[llength $fields] != $width} {error "tabular row [expr {[dict get $state row_number]+1}] has [llength $fields] fields; expected $width"}
        set row {}
        foreach index $columns {
            set value [lindex $fields [expr {$index-1}]]
            if {$index in $numericColumns} {
                if {![string is double -strict $value]} {error "tabular row [expr {[dict get $state row_number]+1}] column $index is not numeric: $value"}
                if {[regexp -nocase {^(\+|-)?(nan|inf|infinity)$} [string trim $value]]} {
                    if {[dict get $options nonfinite] eq "error"} {
                        error "tabular row [expr {[dict get $state row_number]+1}] column $index is non-finite"
                    }
                } elseif {[catch {set value [expr {double($value)}]}]} {
                    error "tabular row [expr {[dict get $state row_number]+1}] column $index is outside the supported real numeric range"
                }
            }
            lappend row $value
        }
        lappend rows $row
        dict incr state row_number
    }
    set handles($handle) $state
    return [dict create rows $rows count [llength $rows] eof $eof row_number [dict get $state row_number]]
}

proc ::GX::TabularTextAPIv1::close {handle} {
    variable handles
    if {![info exists handles($handle)]} {error "unknown tabular text handle"}
    ::close [dict get $handles($handle) channel]
    unset handles($handle)
}

proc ::GX::TabularTextAPIv1::inspect {path {options {}}} {
    set options [_options $options]
    set info [open $path $options]
    set handle [dict get $info handle]
    set rows {}; set total 0; set eof 0
    set failed [catch {
        set preview [dict get $options preview_rows]
        while {!$eof} {
            set count [expr {[dict get $options scan_all] ? 1024 : max(1,$preview)}]
            set chunk [next $handle $count]
            incr total [dict get $chunk count]
            foreach row [dict get $chunk rows] {
                if {[llength $rows] < $preview} {lappend rows $row}
            }
            set eof [dict get $chunk eof]
            if {![dict get $options scan_all]} {break}
        }
    } reason opts]
    close $handle
    if {$failed} {return -options $opts $reason}
    dict unset info handle
    dict set info preview_rows $rows
    dict set info rows_scanned $total
    dict set info exact_row_count [expr {$eof ? $total : ""}]
    dict set info warnings [expr {$eof ? {} : {Row count and structure beyond the preview were not scanned.}}]
    return $info
}
