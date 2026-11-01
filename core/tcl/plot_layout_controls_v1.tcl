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
proc ::GX::layoutOverrideFieldDefaults {} {
    variable cfg
    return [list layout_auto 1 layout_ylabel_allow_negative 0 \
        layout_margin_left   $cfg(plot_stacked_margin_left_pct) \
        layout_margin_right  $cfg(plot_stacked_margin_right_pct) \
        layout_margin_top    $cfg(plot_stacked_margin_top_pct) \
        layout_margin_bottom $cfg(plot_stacked_margin_bottom_pct) \
        layout_gap           $cfg(plot_stacked_gap_pct) \
        layout_ylabel_dist   8.5]
}
proc ::GX::layoutOverrideEnsure {gk} {
    variable axisOverride
    if {[string trim $gk] eq ""} { return }
    foreach {field def} [layoutOverrideFieldDefaults] {
        if {![info exists axisOverride($gk,$field)] || ($field ni {layout_auto layout_ylabel_allow_negative} && [string trim $axisOverride($gk,$field)] eq "")} {
            set axisOverride($gk,$field) $def
        }
    }
}

proc ::GX::layoutControlsPath {} {
    return .top.nb.graphs.preview.layout
}

# Object-specific inspector; numerical state remains ui/layoutVal + axisOverride.
proc ::GX::layoutControlsInspectorPath {} {return [layoutControlsPath].inspector}
proc ::GX::layoutControlsFieldsPath {} {return [layoutControlsInspectorPath].viewport.canvas.body}
proc ::GX::layoutControlsIdentityRefresh {path key} {
    variable ui
    set title {Select a plot in the Plots browser.}
    if {$key ne {}} {
        set title [graphDisplayTitle $path]
        set identity [graphUseIdentityForPath $path]
        if {[llength $identity]==3} {lassign $identity module graph variant;append title "\n$module · $graph · ";append title [expr {$variant eq {}?{Base plot}:"Variant $variant"}]
        } else {append title "\nPlot identity: $key"}
    }
    set ui(layoutInspectorIdentity) $title
    set window [layoutControlsInspectorPath]
    if {[winfo exists $window]} {wm title $window [expr {$key eq {}?{Plot layout — select a plot}:"Plot layout — $key"}]}
}
proc ::GX::layoutControlsInspectorHide {{actual {}}} {
    set panel [layoutControlsPath]
    if {$actual ne {} && $actual ne $panel} return
    set window [layoutControlsInspectorPath]
    if {[winfo exists $window]} {wm withdraw $window}
    if {[winfo exists $panel.show]} {$panel.show configure -text {Show controls}}
}
proc ::GX::layoutControlsInspectorToggle {} {
    set window [layoutControlsInspectorPath];set panel [layoutControlsPath]
    if {![winfo exists $window]} {layoutControlsInspectorBuild}
    if {[winfo viewable $window]} {layoutControlsInspectorHide;return}
    layoutControlsToggle
    $panel.show configure -text {Hide controls}
    uiFieldDialogPresent $window $window.b.auto
}
proc ::GX::layoutControlsInspectorBuild {} {
    variable ui
    set panel [layoutControlsPath];set window [layoutControlsInspectorPath]
    if {[winfo exists $window]} return
    set width [expr {min(840,max(500,[winfo screenwidth $panel]-60))}]
    set height [expr {min(560,max(360,[winfo screenheight $panel]-100))}]
    uiFieldDialogCreate $window $panel {Plot layout} ${width}x${height}
    set body [scrollableDialogBody $window]
    grid columnconfigure $body 1 -weight 1
    if {![info exists ui(layoutInspectorIdentity)]} {set ui(layoutInspectorIdentity) {Select a plot in the Plots browser.}}
    ttk::label $body.identity -textvariable ::GX::ui(layoutInspectorIdentity) -wraplength 720 -justify left
    grid $body.identity -row 0 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 6
    set r 0
    foreach {field label lo hi} [layoutFieldDefs] {
        ttk::label $body.l$r -text $label
        ttk::scale $body.s$r -from $lo -to $hi -orient horizontal -length 115 -variable ::GX::ui(layoutVal,$field) -command [list ::GX::layoutSliderChanged $field]
        ttk::entry $body.e$r -width 6 -textvariable ::GX::ui(layoutVal,$field)
        bind $body.e$r <Return> {::GX::layoutControlsApplyRender;break}
        set row [expr {$r+1}]
        grid $body.l$r -row $row -column 0 -sticky e -padx {6 2} -pady 3
        grid $body.s$r -row $row -column 1 -sticky ew -padx 2 -pady 3
        grid $body.e$r -row $row -column 2 -sticky w -padx {2 6} -pady 3
        incr r
    }
    ttk::label $body.note -text {Per plot. Manual margins apply to single- and multi-panel plots. Panel gap applies to multi-panel plots. External legends reserve an additional band.} -foreground #555555 -wraplength 680 -justify left
    grid $body.note -row 7 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 6
    ttk::frame $window.b
    ttk::checkbutton $window.b.auto -text Automatic -variable ::GX::ui(layoutAuto) -command ::GX::layoutControlsToggle
    ttk::checkbutton $window.b.negative -text {Allow negative Y-label offset} -variable ::GX::ui(layoutNegativeOffset) -command ::GX::layoutNegativeOffsetToggle
    ttk::button $window.b.apply -text {Apply and rerender} -command ::GX::layoutControlsApplyRender
    ttk::button $window.b.reset -text {Restore automatic} -command ::GX::layoutControlsReset
    pack $window.b -side bottom -fill x -padx 6 -pady 6
    bind $window.b <Configure> [list ::GX::uiFieldControlsLayout $window.b %w [winfo children $window.b]]
    uiFieldScrollAreaAttach $window.viewport.canvas $body
    bind $window <FocusIn> +[list ::GX::plotDialogFieldSee $window.viewport.canvas $body %W]
    wm protocol $window WM_DELETE_WINDOW ::GX::layoutControlsInspectorHide
    bind $window <Escape> {::GX::layoutControlsInspectorHide;break}
}

proc ::GX::layoutSliderChanged {field value} {
    variable ui
    if {![info exists ui(layoutVal,$field)]} { return }
    if {![string is double -strict $value]} { return }
    set rounded [format %.1f $value]
    if {$ui(layoutVal,$field) ne $rounded} { set ui(layoutVal,$field) $rounded }
}

proc ::GX::layoutControlsState {enabled} {
    set p [::GX::layoutControlsFieldsPath]
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
    set p [layoutControlsFieldsPath]
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
    layoutControlsIdentityRefresh $path $gk
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
    # The selection guard belongs to the mounted inspector. Existing headless
    # layout application remains available through its established state owner.
    if {[llength [info commands winfo]] && [winfo exists [layoutControlsInspectorPath]]} {
        set current {};catch {set current [graphKeyForPath [currentGraphPath]]}
        if {$current ne $gk} {tk_messageBox -icon error -message {Plot selection changed. Select the intended plot and reopen its layout controls before applying.};return 0}
    }
    set staged {}
    foreach {field label lo hi} [::GX::layoutFieldDefs] {
        set v [string trim $ui(layoutVal,$field)]
        if {$v eq ""} { set v 0 }
        if {![string is double -strict $v] || [catch {expr {abs($v)<Inf}} finite] || !$finite} {
            tk_messageBox -icon error -message "$label must be a finite numeric value."
            return 0
        }
        if {$field eq "layout_ylabel_dist" && $ui(layoutNegativeOffset)} {set lo -30}
        if {$v < $lo} { set v $lo }
        if {$v > $hi} { set v $hi }
        dict set staged $field $v
    }
    # Validate the complete form before changing any accepted per-plot setting.
    # An invalid later field must not silently commit earlier valid edits.
    dict for {field value} $staged {
        set ui(layoutVal,$field) $value
        set axisOverride($gk,$field) $value
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
    set parent .top.nb.graphs.preview
    if {![winfo exists $parent]} return
    set p [layoutControlsPath]
    if {[winfo exists $p]} return
    ttk::labelframe $p -text {Plot layout}
    ttk::button $p.show -text {Show controls} -command ::GX::layoutControlsInspectorToggle
    pack $p.show -side top -anchor w -padx 6 -pady 4
    if {[info exists ::GX::ui(graphPreview)] && [winfo exists $::GX::ui(graphPreview)]} {pack $p -side top -fill x -padx 2 -pady {2 4} -before $::GX::ui(graphPreview)
    } else {pack $p -side top -fill x -padx 2 -pady {2 4}}
    bind $p <Unmap> [list ::GX::layoutControlsInspectorHide %W]
    layoutControlsInspectorBuild
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
