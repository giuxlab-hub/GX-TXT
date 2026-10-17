# Stable JSON view of editable overlay definitions for external consumers.
# The canonical Workspace owner remains SESSION_WORKSPACE_API_v1; JSON is an
# interop projection, not a parallel project store or mutable registry.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {}
proc ::GX::SII::jsonQuote {text} {
    set result "\""
    foreach char [split $text {}] {
        scan $char %c code
        switch -- $char {
            "\\" {append result "\\\\"}
            "\"" {append result "\\\""}
            "\n" {append result "\\n"}
            "\r" {append result "\\r"}
            "\t" {append result "\\t"}
            default {
                if {$code < 32} {append result [format {\u%04x} $code]} else {append result $char}
            }
        }
    }
    append result "\""
    return $result
}
proc ::GX::SII::annotationsJson {annotations} {
    set entries {}
    set ordinal 0
    foreach item $annotations {
        set kind [dict get $item kind]
        if {$kind ni {text arrow line rectangle ellipse}} {error {Unsupported JSON annotation type}}
        set id [expr {[dict exists $item id] ? [dict get $item id] : "ann[incr ordinal]"}]
        if {![regexp {^ann[0-9]+$} $id]} {error {Invalid annotation identifier}}
        set fields [list \"id\":[jsonQuote $id] \"kind\":[jsonQuote $kind]]
        foreach key {x1 y1 x2 y2 stroke size box_width box_height font_dpi} {
            if {![dict exists $item $key]} continue
            set value [dict get $item $key]
            if {![string is integer -strict $value] || $value<0 || $value>1000000} {error "Invalid $key in annotation JSON"}
            lappend fields \"$key\":$value
        }
        foreach key {rotation pivot_x pivot_y} {
            if {![dict exists $item $key]} continue
            set value [dict get $item $key]
            if {![string is double -strict $value] || ![expr {abs(double($value))<=1000000}]} {error "Invalid $key in annotation JSON"}
            lappend fields "\"$key\":$value"
        }
        foreach key {color text name font_family font_unit} {if {[dict exists $item $key]} {lappend fields \"$key\":[jsonQuote [dict get $item $key]]}}
        if {[dict exists $item font_value]} {
            set value [dict get $item font_value]
            if {![string is double -strict $value] || $value<1 || $value>1200} {error {Invalid font value}}
            lappend fields "\"font_value\":$value"
        }
        lappend entries "{[join $fields ,]}"
    }
    return "{\"schema\":\"scientific_image_inspector.annotations.v1\",\"coordinate_system\":\"image-pixels-top-left\",\"objects\":\[[join $entries ,]\]}"
}
