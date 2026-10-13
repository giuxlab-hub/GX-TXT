# GX-TXT Plugin Progress API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
#
# Public framework-side progress contract.  Plugins never touch Tk widgets.
# External/Octave plugins emit reserved structured records; in-process Tcl code
# may call ::GX::progressPublish with a dict containing the same fields.

namespace eval ::GX {
    variable progressApiVersion 1
    variable progressProtocolPrefix "@@GXTXT_PROGRESS_V1@@"
    variable progressRunCounter 0
    variable progressLastEvent {}
}

proc ::GX::progressNewRunId {moduleId {operation run}} {
    variable progressRunCounter
    incr progressRunCounter
    set safe [string map {" " _ "/" _ "\\" _ ":" _} $moduleId]
    return [format "%s-%s-%d-%d-%d" $safe $operation [clock milliseconds] [pid] $progressRunCounter]
}

proc ::GX::progressDecodeValue {s} {
    set out ""
    set n [string length $s]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $s $i]
        if {$c ne "\\" || $i+1 >= $n} { append out $c; continue }
        incr i
        set e [string index $s $i]
        switch -- $e {
            n { append out "\n" }
            r { append out "\r" }
            t { append out "\t" }
            \\ { append out "\\" }
            default { append out "\\$e" }
        }
    }
    return $out
}

proc ::GX::progressParseLine {line} {
    variable progressProtocolPrefix
    if {![string match "${progressProtocolPrefix}*" $line]} { return {} }
    set body [string range $line [string length $progressProtocolPrefix] end]
    if {[string index $body 0] eq "\t"} { set body [string range $body 1 end] }
    set ev [dict create api_version 1]
    foreach field [split $body "\t"] {
        if {$field eq ""} continue
        set p [string first "=" $field]
        if {$p < 1} continue
        set k [string trim [string range $field 0 [expr {$p-1}]]]
        set v [progressDecodeValue [string range $field [expr {$p+1}] end]]
        if {$k ne ""} { dict set ev $k $v }
    }
    if {![dict exists $ev state]} { return {} }
    return $ev
}

proc ::GX::progressNormalize {ev} {
    set out $ev
    foreach {k def} {state running mode indeterminate stage {} message {} current {} total {} module_id {} run_id {}} {
        if {![dict exists $out $k]} { dict set out $k $def }
    }
    set state [string tolower [string trim [dict get $out state]]]
    if {$state eq ""} { set state running }
    dict set out state $state
    set mode [string tolower [string trim [dict get $out mode]]]
    if {$mode ni {determinate indeterminate}} { set mode indeterminate }

    set cur [dict get $out current]
    set tot [dict get $out total]
    set numeric 0
    if {$mode eq "determinate" && [string is double -strict $cur] && [string is double -strict $tot] && $tot > 0} {
        set numeric 1
        set displayCur $cur
        if {$displayCur < 0} { set displayCur 0 }
        if {$displayCur > $tot} { set displayCur $tot }
        set pct [expr {100.0 * double($displayCur) / double($tot)}]
        dict set out percent $pct
        dict set out display_current $displayCur
    } elseif {$state eq "completed"} {
        # Completion is semantic, not inferred from a numerical last update.
        dict set out percent 100.0
    } else {
        set mode indeterminate
    }
    dict set out mode $mode
    dict set out numeric_valid $numeric
    return $out
}

proc ::GX::progressModuleDisplayName {moduleId fallback} {
    if {$moduleId ne "" && [llength [info commands ::GX::moduleField]]} {
        set n [::GX::moduleField $moduleId name ""]
        if {$n ne ""} { return $n }
    }
    if {$fallback ne ""} { return $fallback }
    if {$moduleId ne ""} { return $moduleId }
    return "Plugin"
}

proc ::GX::progressUiStopAnimation {} {
    variable ui
    if {[info exists ui(progress)] && [llength [info commands winfo]] && [winfo exists $ui(progress)]} {
        catch {$ui(progress) stop}
    }
}

proc ::GX::progressUiApply {ev} {
    variable ui
    variable progressLastEvent
    set ev [progressNormalize $ev]
    set progressLastEvent $ev

    set moduleId [dict get $ev module_id]
    set fallback [expr {[info exists ui(analysisCurrentLabel)] ? $ui(analysisCurrentLabel) : ""}]
    set name [progressModuleDisplayName $moduleId $fallback]
    set stage [string trim [dict get $ev stage]]
    set message [string trim [dict get $ev message]]
    set state [dict get $ev state]
    set mode [dict get $ev mode]

    set pieces [list $name]
    if {$stage ne ""} { lappend pieces $stage }
    if {$message ne ""} { lappend pieces $message }
    set text [join $pieces " — "]

    if {$mode eq "determinate" && [dict exists $ev percent]} {
        set pct [dict get $ev percent]
        progressUiStopAnimation
        if {[info exists ui(progress)] && [llength [info commands winfo]] && [winfo exists $ui(progress)]} {
            $ui(progress) configure -mode determinate -maximum 100 -value $pct
        }
        if {[dict get $ev numeric_valid]} {
            append text [format "  (%s / %s, %.1f%%)" [dict get $ev current] [dict get $ev total] $pct]
        } elseif {$state eq "completed"} {
            append text "  (100%)"
        }
    } else {
        if {[info exists ui(progress)] && [llength [info commands winfo]] && [winfo exists $ui(progress)]} {
            progressUiStopAnimation
            $ui(progress) configure -mode indeterminate -maximum 100
            if {$state ni {completed failed cancelled}} { catch {$ui(progress) start 80} }
        }
    }

    if {$state eq "failed"} { append text " — FAILED" }
    if {$state eq "completed" && $message eq ""} { append text " — completed" }
    if {[info exists ui(status)]} { set ui(status) $text }
    if {[llength [info commands update]]} { catch {update idletasks} }
    return $ev
}

# Public in-process publisher.  This is intentionally GUI-agnostic: when Tk is
# absent it emits one controlled headless line instead of touching widgets.
proc ::GX::progressPublish {ev} {
    set ev [progressNormalize $ev]
    if {[llength [info commands winfo]] && [info exists ::GX::ui(progress)] && [winfo exists $::GX::ui(progress)]} {
        return [progressUiApply $ev]
    }
    # A detached script's CORE supervisor consumes the existing wire protocol.
    # Keep ordinary headless callers' historical human-readable output below.
    if {[info exists ::env(GXTXT_JOB_ID)]} {
        set fields [list $::GX::progressProtocolPrefix]
        dict for {key value} $ev {
            lappend fields "$key=[string map [list \\ \\\\ \t \\t \r \\r \n \\n] $value]"
        }
        puts [join $fields \t]
        flush stdout
        return $ev
    }
    set module [dict get $ev module_id]
    set stage [dict get $ev stage]
    set msg [dict get $ev message]
    set state [dict get $ev state]
    if {[dict get $ev mode] eq "determinate" && [dict get $ev numeric_valid]} {
        puts [format {[progress] %s %s %s/%s %s} $module $stage [dict get $ev current] [dict get $ev total] $msg]
    } else {
        puts [format {[progress] %s %s %s %s} $module $state $stage $msg]
    }
    flush stdout
    return $ev
}

proc ::GX::progressUiFallbackStart {label {moduleId ""}} {
    variable ui
    progressUiStopAnimation
    if {[info exists ui(progress)] && [llength [info commands winfo]] && [winfo exists $ui(progress)]} {
        $ui(progress) configure -mode indeterminate -maximum 100
        catch {$ui(progress) start 80}
    }
    set name [progressModuleDisplayName $moduleId $label]
    if {[info exists ui(status)]} { set ui(status) "$name — Running..." }
}

proc ::GX::progressUiReset {{text "Ready"}} {
    variable ui
    progressUiStopAnimation
    if {[info exists ui(progress)] && [llength [info commands winfo]] && [winfo exists $ui(progress)]} {
        $ui(progress) configure -mode determinate -maximum 100 -value 0
    }
    if {[info exists ui(status)]} { set ui(status) $text }
}
