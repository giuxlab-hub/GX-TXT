# Metadata-driven operation browser for Dataset Expression.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::numericExpressionOperations {} {
    if {![llength [info commands ::GX::NumericAPIv1::listOperations]]} {
        source [file join $::GX::scriptDir plugins modules math.numeric api numeric_api_v1.tcl]
    }
    set out {}
    foreach id [::GX::NumericAPIv1::listOperations] {
        set meta [::GX::NumericAPIv1::operationMetadata $id]
        if {[lsearch -exact [dict get $meta flags] expression] < 0} continue
        set name [dict get $meta expression_name]
        if {$name eq ""} continue
        lappend out $meta
    }
    return [lsort -command ::GX::numericExpressionCompare $out]
}
proc ::GX::numericExpressionCompare {a b} {
    set x [dict get $a expression_name];set y [dict get $b expression_name]
    set cmp [string compare -nocase $x $y]
    if {$cmp != 0} {return $cmp}
    return [string compare [dict get $a id] [dict get $b id]]
}
proc ::GX::numericExpressionBrowserSelect {window moduleId} {
    if {![winfo exists $window.pane.list.tree]} return
    set selected [$window.pane.list.tree selection]
    if {![llength $selected]} return
    set id [lindex $selected 0]
    set meta [::GX::NumericAPIv1::operationMetadata $id]
    set detail "[dict get $meta expression_name]  —  [dict get $meta id]\n\n"
    append detail "[dict get $meta summary]\n\n"
    append detail "Arguments: [join [dict get $meta arguments] {, }]\n"
    append detail "Arity: [dict get $meta arity_min]–[dict get $meta arity_max]\n"
    append detail "Accepted kinds: [join [dict get $meta accepted_kinds] {, }]\n"
    append detail "Shape: [dict get $meta shape_semantics]\n"
    append detail "Broadcast: [dict get $meta broadcast_semantics]\n"
    append detail "Result: [dict get $meta result_kind] / [dict get $meta result_shape]\n"
    append detail "Unit behavior: [dict get $meta unit_behavior]\n"
    append detail "Nonfinite policies: [join [dict get $meta nonfinite_policies] {, }]\n"
    set opts [dict get $meta options]
    if {[dict size $opts]} {
        append detail "Options:\n"
        dict for {key vals} $opts {append detail "  $key: [join $vals {, }]\n"}
    }
    $window.pane.info.detail configure -state normal
    $window.pane.info.detail delete 1.0 end
    $window.pane.info.detail insert 1.0 $detail
    $window.pane.info.detail configure -state disabled
}
proc ::GX::numericExpressionBrowserInsert {window moduleId} {
    variable moduleCfg
    if {![winfo exists $window.pane.list.tree]} return
    set selected [$window.pane.list.tree selection]
    if {![llength $selected]} return
    set meta [::GX::NumericAPIv1::operationMetadata [lindex $selected 0]]
    set name [dict get $meta expression_name]
    if {![info exists moduleCfg($moduleId,expression)]} {set moduleCfg($moduleId,expression) ""}
    append moduleCfg($moduleId,expression) "${name}("
}
proc ::GX::numericExpressionBrowserOpen {moduleId} {
    set w .numericExpressionBrowser
    catch {destroy $w}
    toplevel $w
    wm title $w "GX-TXT numerical expression operations"
    wm geometry $w 1040x650
    grid rowconfigure $w 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    ttk::panedwindow $w.pane -orient horizontal
    grid $w.pane -row 0 -column 0 -sticky nsew -padx 8 -pady 8
    ttk::frame $w.pane.list
    ttk::frame $w.pane.info
    $w.pane add $w.pane.list -weight 2
    $w.pane add $w.pane.info -weight 3
    grid rowconfigure $w.pane.list 0 -weight 1;grid columnconfigure $w.pane.list 0 -weight 1
    ttk::treeview $w.pane.list.tree -columns {category arity summary} -show {tree headings} -selectmode browse
    $w.pane.list.tree heading #0 -text Function
    $w.pane.list.tree heading category -text Category
    $w.pane.list.tree heading arity -text Arguments
    $w.pane.list.tree heading summary -text Summary
    $w.pane.list.tree column #0 -width 160
    $w.pane.list.tree column category -width 100
    $w.pane.list.tree column arity -width 75
    $w.pane.list.tree column summary -width 240
    ttk::scrollbar $w.pane.list.sy -orient vertical -command [list $w.pane.list.tree yview]
    $w.pane.list.tree configure -yscrollcommand [list $w.pane.list.sy set]
    grid $w.pane.list.tree -row 0 -column 0 -sticky nsew
    grid $w.pane.list.sy -row 0 -column 1 -sticky ns
    grid rowconfigure $w.pane.info 0 -weight 1;grid columnconfigure $w.pane.info 0 -weight 1
    text $w.pane.info.detail -wrap word -state disabled
    grid $w.pane.info.detail -row 0 -column 0 -sticky nsew
    ttk::button $w.pane.info.insert -text "Insert function name" -command [list ::GX::numericExpressionBrowserInsert $w $moduleId]
    grid $w.pane.info.insert -row 1 -column 0 -sticky e -pady 8
    foreach meta [numericExpressionOperations] {
        set id [dict get $meta id]
        set arity "[dict get $meta arity_min]–[dict get $meta arity_max]"
        $w.pane.list.tree insert {} end -id $id -text [dict get $meta expression_name] -values [list [dict get $meta category] $arity [dict get $meta summary]]
    }
    bind $w.pane.list.tree <<TreeviewSelect>> [list ::GX::numericExpressionBrowserSelect $w $moduleId]
}
proc ::GX::standardConfigWidget_v0933_before_unit_selector {parent id key row} {
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ne "numeric_operation_browser"} {
        return [::GX::standardConfigWidget_before_numeric_expression_browser $parent $id $key $row]
    }
    ttk::label $parent.l$row -text [moduleConfigField $id $key label $key]
    ttk::button $parent.w$row -text "Browse NUMERIC_API operations..." -command [list ::GX::numericExpressionBrowserOpen $id]
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky w -padx 4 -pady 2
}
