# SPDX-License-Identifier: GPL-3.0-or-later
# Plots-tab per-plot layout controls.
#
# The renderer computes an automatic stacked layout from the measured tick,
# label and title extents. These controls sit above the plot preview and let
# one plot override that automatic result: multi-panel margins, the distance
# between stacked panels, and the distance of the Y label from its axis.
#
# State lives in the existing per-graph axisOverride store, so it is written to
# the manifest and to the module runtime with the rest of the per-plot state.
# It deliberately does not switch axis.<graph>.enabled on: the Axes dialog and
# the layout controls stay independent.

namespace eval ::GX {}

proc ::GX::layoutFieldDefs {} {
    return [list \
        layout_margin_left   "Left \[%\]"      0 30 \
        layout_margin_right  "Right \[%\]"     0 30 \
        layout_margin_top    "Top \[%\]"       0 30 \
        layout_margin_bottom "Bottom \[%\]"    0 30 \
        layout_gap           "Panel gap \[%\]" 0 25 \
        layout_ylabel_dist   "Y-label offset \[%\]" 0 30]
}

proc ::GX::layoutFieldNames {} {
    set out {}
    foreach {field label lo hi} [::GX::layoutFieldDefs] { lappend out $field }
    return $out
}

# Seed the per-graph layout state from the global stacked defaults, so the
# sliders start from the values the automatic layout is anchored to.
proc ::GX::layoutOverrideEnsure {gk} {
    variable axisOverride
    variable cfg
    if {[string trim $gk] eq ""} { return }
    if {![info exists axisOverride($gk,layout_auto)]} { set axisOverride($gk,layout_auto) 1 }
    if {![info exists axisOverride($gk,layout_ylabel_allow_negative)]} {set axisOverride($gk,layout_ylabel_allow_negative) 0}
    set seed [list \
        layout_margin_left   $cfg(plot_stacked_margin_left_pct) \
        layout_margin_right  $cfg(plot_stacked_margin_right_pct) \
        layout_margin_top    $cfg(plot_stacked_margin_top_pct) \
        layout_margin_bottom $cfg(plot_stacked_margin_bottom_pct) \
        layout_gap           $cfg(plot_stacked_gap_pct) \
        layout_ylabel_dist   8.5]
    foreach {field def} $seed {
        if {![info exists axisOverride($gk,$field)] || [string trim $axisOverride($gk,$field)] eq ""} {
            set axisOverride($gk,$field) $def
        }
    }
}

proc ::GX::layoutControlsPath {} {
    return .top.nb.graphs.preview.layout
}

proc ::GX::layoutSliderChanged {field value} {
    variable ui
    if {![info exists ui(layoutVal,$field)]} { return }
    if {![string is double -strict $value]} { return }
    set rounded [format %.1f $value]
    if {$ui(layoutVal,$field) ne $rounded} { set ui(layoutVal,$field) $rounded }
}

proc ::GX::layoutControlsState {enabled} {
    set p [::GX::layoutControlsPath]
    if {![winfo exists $p]} { return }
    for {set r 0} {$r < 6} {incr r} {
        if {$enabled} {
            catch {$p.s$r state !disabled}
            catch {$p.e$r configure -state normal}
        } else {
            catch {$p.s$r state disabled}
            catch {$p.e$r configure -state disabled}
        }
    }
}

proc ::GX::layoutControlsToggle {} {
    variable ui
    if {![info exists ui(layoutGraphKey)] || $ui(layoutGraphKey) eq ""} {
        ::GX::layoutControlsState 0
        return
    }
    ::GX::layoutControlsState [expr {$ui(layoutAuto) ? 0 : 1}]
}

proc ::GX::layoutNegativeOffsetToggle {} {
    variable ui
    set p [layoutControlsPath]
    if {![winfo exists $p.s5]} return
    if {$ui(layoutNegativeOffset)} {
        $p.s5 configure -from -30 -to 30
    } else {
        $p.s5 configure -from 0 -to 30
        if {![string is double -strict $ui(layoutVal,layout_ylabel_dist)] || $ui(layoutVal,layout_ylabel_dist) < 0} {
            set ui(layoutVal,layout_ylabel_dist) 0
        }
    }
}

proc ::GX::layoutControlsLoad {} {
    variable ui
    variable axisOverride
    set p [::GX::layoutControlsPath]
    if {![winfo exists $p]} { return }
    set path ""
    catch {set path [::GX::currentGraphPath]}
    set gk ""
    if {$path ne ""} { catch {set gk [::GX::graphKeyForPath $path]} }
    set ui(layoutGraphKey) $gk
    if {$gk eq ""} {
        foreach field [::GX::layoutFieldNames] { set ui(layoutVal,$field) 0 }
        set ui(layoutAuto) 1
        set ui(layoutNegativeOffset) 0
        ::GX::layoutNegativeOffsetToggle
        ::GX::layoutControlsState 0
        return
    }
    ::GX::layoutOverrideEnsure $gk
    foreach field [::GX::layoutFieldNames] { set ui(layoutVal,$field) $axisOverride($gk,$field) }
    set ui(layoutAuto) [expr {[string trim $axisOverride($gk,layout_auto)] eq "0" ? 0 : 1}]
    set ui(layoutNegativeOffset) [expr {$axisOverride($gk,layout_ylabel_allow_negative) ? 1 : 0}]
    ::GX::layoutNegativeOffsetToggle
    ::GX::layoutControlsToggle
}

proc ::GX::layoutControlsApply {} {
    variable ui
    variable axisOverride
    if {![info exists ui(layoutGraphKey)] || $ui(layoutGraphKey) eq ""} { return 0 }
    set gk $ui(layoutGraphKey)
    foreach {field label lo hi} [::GX::layoutFieldDefs] {
        set v [string trim $ui(layoutVal,$field)]
        if {$v eq ""} { set v 0 }
        if {![string is double -strict $v]} {
            tk_messageBox -icon error -message "$label must be numeric."
            return 0
        }
        if {$field eq "layout_ylabel_dist" && $ui(layoutNegativeOffset)} {set lo -30}
        if {$v < $lo} { set v $lo }
        if {$v > $hi} { set v $hi }
        set ui(layoutVal,$field) $v
        set axisOverride($gk,$field) $v
    }
    set axisOverride($gk,layout_auto) [expr {$ui(layoutAuto) ? 1 : 0}]
    set axisOverride($gk,layout_ylabel_allow_negative) [expr {$ui(layoutNegativeOffset) ? 1 : 0}]
    catch {::GX::refreshManifestPreview}
    return 1
}

proc ::GX::layoutControlsApplyRender {} {
    if {![::GX::layoutControlsApply]} { return }
    set path ""
    catch {set path [::GX::currentGraphPath]}
    if {$path ne ""} { catch {::GX::startRerenderPaths [list $path]} }
}

proc ::GX::layoutControlsReset {} {
    variable ui
    variable axisOverride
    if {![info exists ui(layoutGraphKey)] || $ui(layoutGraphKey) eq ""} { return }
    set gk $ui(layoutGraphKey)
    foreach field [::GX::layoutFieldNames] { catch {unset axisOverride($gk,$field)} }
    set axisOverride($gk,layout_auto) 1
    set axisOverride($gk,layout_ylabel_allow_negative) 0
    ::GX::layoutControlsLoad
}

proc ::GX::layoutControlsBuild {} {
    variable ui
    set parent .top.nb.graphs.preview
    if {![winfo exists $parent]} { return }
    set p [::GX::layoutControlsPath]
    if {[winfo exists $p]} { return }
    ttk::labelframe $p -text "Plot layout"
    # Two control groups per row fit normal notebook windows without forcing
    # the preview pane wider than the application. Buttons and explanatory
    # text get separate rows so neither can squeeze the numeric fields.
    set r 0
    foreach {field label lo hi} [::GX::layoutFieldDefs] {
        set row [expr {$r / 2}]
        set col [expr {($r % 2) * 3}]
        ttk::label $p.l$r -text $label
        ttk::scale $p.s$r -from $lo -to $hi -orient horizontal -length 115 \
            -variable ::GX::ui(layoutVal,$field) -command [list ::GX::layoutSliderChanged $field]
        ttk::entry $p.e$r -width 6 -textvariable ::GX::ui(layoutVal,$field)
        bind $p.e$r <Return> {::GX::layoutControlsApplyRender; break}
        grid $p.l$r -row $row -column $col -sticky e -padx {6 2} -pady 2
        grid $p.s$r -row $row -column [expr {$col + 1}] -sticky ew -padx 2 -pady 2
        grid $p.e$r -row $row -column [expr {$col + 2}] -sticky w -padx {2 6} -pady 2
        incr r
    }
    foreach col {1 4} { grid columnconfigure $p $col -weight 1 }
    ttk::frame $p.b
    ttk::checkbutton $p.b.auto -text "Automatic" -variable ::GX::ui(layoutAuto) -command ::GX::layoutControlsToggle
    ttk::checkbutton $p.b.negative -text "Allow negative Y-label offset" -variable ::GX::ui(layoutNegativeOffset) -command ::GX::layoutNegativeOffsetToggle
    ttk::button $p.b.apply -text "Apply and rerender" -command ::GX::layoutControlsApplyRender
    ttk::button $p.b.reset -text "Restore automatic" -command ::GX::layoutControlsReset
    pack $p.b.auto $p.b.negative $p.b.apply $p.b.reset -side left -padx 4
    grid $p.b -row 3 -column 0 -columnspan 6 -sticky w -padx 4 -pady {4 2}
    ttk::label $p.note -text "Per plot. Manual margins apply to single- and multi-panel plots. Panel gap applies to multi-panel plots. External legends reserve an additional band." -foreground #555555 -wraplength 680 -justify left
    grid $p.note -row 4 -column 0 -columnspan 6 -sticky ew -padx 8 -pady {0 5}
    if {[info exists ui(graphPreview)] && [winfo exists $ui(graphPreview)]} {
        pack $p -side top -fill x -padx 2 -pady {2 4} -before $ui(graphPreview)
    } else {
        pack $p -side top -fill x -padx 2 -pady {2 4}
    }
}

proc ::GX::layoutControlsEnsure {} {
    catch {::GX::layoutControlsBuild}
    catch {::GX::layoutControlsLoad}
}

# The controls follow the plot selected in the Plots tab.
proc ::GX::previewGraph_v090_before_plot_region {} {
    ::GX::previewGraph_before_layout_controls
    catch {::GX::layoutControlsEnsure}
}
