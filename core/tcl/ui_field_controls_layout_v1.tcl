# SPDX-License-Identifier: GPL-3.0-or-later
# Existing shared control-row layout, also usable by isolated Tk media readers.
namespace eval ::GX::UiField {variable controlsTrailing {};variable controlsStacked {}}
proc ::GX::uiFieldControlsLayout {frame width {children {}}} {
    if {$children eq {}} {set children [winfo children $frame]}
    if {[dict exists $::GX::UiField::controlsTrailing $frame]} {
        foreach child [dict get $::GX::UiField::controlsTrailing $frame] {
            if {![winfo exists $child]} continue
            set at [lsearch -exact $children $child]
            if {$at>=0} {set children [lreplace $children $at $at]}
            lappend children $child
        }
    }
    # Restore only the grid weight temporarily owned by the narrow fallback.
    # The normal layout retains the caller's original column policy.
    if {[dict exists $::GX::UiField::controlsStacked $frame]} {
        grid columnconfigure $frame 0 -weight [dict get $::GX::UiField::controlsStacked $frame]
        dict unset ::GX::UiField::controlsStacked $frame
    }
    foreach child $children {pack forget $child}
    # Keep each label next to its input when wrapping. Treating them as
    # unrelated cells split labels from fields at larger fonts/narrow widths.
    set groups {};set index 0
    while {$index<[llength $children]} {
        set child [lindex $children $index];incr index
        set next [lindex $children $index]
        if {[winfo class $child] in {TLabel Label}&&$next ne ""&&[winfo class $next] in {Entry TEntry Combobox TCombobox Spinbox TSpinbox Scale TScale}} {
            $child configure -wraplength [expr {max(64,$width-[winfo reqwidth $next]-18)}]
            lappend groups [list $child $next];incr index
        } else {
            if {[winfo class $child] in {TLabel Label}} {$child configure -wraplength [expr {max(64,$width-18)}]}
            lappend groups [list $child]
        }
    }
    # Use every available row width before adding another row. A fixed six-
    # group ceiling could push core editing controls below a Workbench pane.
    for {set columns [llength $groups]} {$columns>=1} {incr columns -1} {
        set sizes [lrepeat [expr {2*$columns}] 0];set i 0
        foreach group $groups {
            set col [expr {$i%$columns}]
            set part 0
            foreach child $group {
                set cell [expr {2*$col+$part}];incr part
                lset sizes $cell [expr {max([lindex $sizes $cell],[winfo reqwidth $child]+6)}]
            }
            incr i
        }
        set total 0;foreach size $sizes {incr total $size}
        if {$total<=$width || $columns==1} break
    }
    if {$columns==1 && $total>$width} {
        # A pair wider than its container cannot remain side by side. Give
        # each part a full row and let the existing entry shrink/scroll its
        # own text instead of placing it beyond the visible container edge.
        dict set ::GX::UiField::controlsStacked $frame [grid columnconfigure $frame 0 -weight]
        set cleanup [list ::GX::_uiFieldControlsDestroyed $frame %W]
        if {$cleanup ni [split [bind $frame <Destroy>] \n]} {bind $frame <Destroy> +$cleanup}
        grid columnconfigure $frame 0 -weight 1
        set height 0;set row 0
        foreach group $groups {
            foreach child $group {
                set label [expr {[winfo class $child] in {TLabel Label}}]
                if {$label} {$child configure -wraplength [expr {max(1,$width-6)}]}
                grid $child -row $row -column 0 -columnspan 1 -sticky [expr {$label ? {w} : {ew}}] -padx 3 -pady 2
                incr height [expr {[winfo reqheight $child]+4}];incr row
            }
        }
        return [dict create columns 1 rows $row height $height]
    }
    set heights {};set i 0
    foreach group $groups {
        set row [expr {$i/$columns}];set col [expr {2*($i%$columns)}];incr i
        set span [expr {[llength $group]==1 ? 2 : 1}]
        foreach child $group {
            set previous [expr {[dict exists $heights $row] ? [dict get $heights $row] : 0}]
            dict set heights $row [expr {max($previous,[winfo reqheight $child]+4)}]
            set info [grid info $child]
            if {$info eq {} || [dict get $info -row]!=$row || [dict get $info -column]!=$col||[dict get $info -columnspan]!=$span} {
                grid $child -row $row -column $col -columnspan $span -sticky w -padx 3 -pady 2
            }
            incr col
        }
    }
    set height 0;dict for {row pixels} $heights {incr height $pixels}
    return [dict create columns $columns rows [dict size $heights] height $height]
}
proc ::GX::uiFieldControlsAppend {frame widget} {
    if {![winfo exists $widget] || [winfo parent $widget] ne $frame} {error {Appended control must belong to its layout container}}
    set children {}
    if {[dict exists $::GX::UiField::controlsTrailing $frame]} {set children [dict get $::GX::UiField::controlsTrailing $frame]}
    if {$widget ni $children} {
        dict lappend ::GX::UiField::controlsTrailing $frame $widget
        if {$children eq {}} {bind $frame <Destroy> +[list ::GX::_uiFieldControlsDestroyed $frame %W]}
    }
    set visible {}
    foreach child [winfo children $frame] {if {[winfo manager $child] ne {}} {lappend visible $child}}
    uiFieldControlsLayout $frame [winfo width $frame] $visible
}
proc ::GX::_uiFieldControlsDestroyed {frame actual} {
    if {$frame ne $actual} return
    foreach state {controlsTrailing controlsStacked} {
        if {[dict exists [set ::GX::UiField::$state] $frame]} {dict unset ::GX::UiField::$state $frame}
    }
}
