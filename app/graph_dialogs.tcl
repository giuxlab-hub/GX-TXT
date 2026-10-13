# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::plotFontUnitChanged {} {
    variable cfg
    variable ui
    variable legendOverride
    set newUnit [string tolower [string trim $cfg(plot_font_unit)]]
    if {$newUnit ni {px pt}} { return }
    set oldUnit [expr {[info exists ui(plotFontUnitLast)] ? $ui(plotFontUnitLast) : $newUnit}]
    if {$oldUnit ni {px pt}} { set oldUnit $newUnit }
    if {$oldUnit eq $newUnit} { set ui(plotFontUnitLast) $newUnit; return }
    set dpi $cfg(analysis_png_dpi)
    if {![string is double -strict $dpi] || $dpi <= 0} { set dpi 200.0 }

    # Preserve the rendered visual size while switching the unit displayed in
    # the GUI.  Octave ultimately receives points: px -> pt uses 72 / DPI.
    foreach key {plot_font_size plot_axis_label_font_size plot_title_font_size} {
        set v [string trim $cfg($key)]
        if {$v eq "" || ![string is double -strict $v] || $v <= 0} { continue }
        if {$oldUnit eq "px"} { set pt [expr {$v * 72.0 / $dpi}] } else { set pt $v }
        if {$newUnit eq "px"} { set nv [expr {$pt * $dpi / 72.0}] } else { set nv $pt }
        set cfg($key) [format %.6g $nv]
    }

    # The global legend size follows the default plot unit only when its own
    # unit is set to inherit.  Explicit px/pt legend units are independent.
    set lfu [expr {[info exists cfg(plot_legend_font_unit)] ? [string tolower [string trim $cfg(plot_legend_font_unit)]] : "inherit"}]
    if {$lfu eq "" || $lfu eq "inherit"} {
        set v [string trim $cfg(plot_legend_font_size)]
        if {$v ne "" && [string is double -strict $v] && $v > 0} {
            if {$oldUnit eq "px"} { set pt [expr {$v * 72.0 / $dpi}] } else { set pt $v }
            if {$newUnit eq "px"} { set nv [expr {$pt * $dpi / 72.0}] } else { set nv $pt }
            set cfg(plot_legend_font_size) [format %.6g $nv]
        }
    }

    # Plot-specific legend overrides are converted only when they inherit the
    # effective global/module legend unit. An explicit per-plot px/pt override is independent.
    foreach name [array names legendOverride "*,font_size"] {
        set prefix [string range $name 0 end-9]
        set fu [expr {[info exists legendOverride(${prefix}font_unit)] ? [string trim $legendOverride(${prefix}font_unit)] : ""}]
        if {$fu ne "" && $fu ne "inherit"} { continue }
        set graphId [string range $name 0 end-10]
        set oldParent $oldUnit
        set newParent $newUnit
        if {[llength [info commands ::GX::moduleGraphicsParentLegendUnitForGraph]]} {
            set oldParent [::GX::moduleGraphicsParentLegendUnitForGraph $graphId $oldUnit]
            set newParent [::GX::moduleGraphicsParentLegendUnitForGraph $graphId $newUnit]
        }
        if {$oldParent eq $newParent} { continue }
        set v [string trim $legendOverride($name)]
        if {$v eq "" || ![string is double -strict $v] || $v <= 0} { continue }
        if {$oldParent eq "px"} { set pt [expr {$v * 72.0 / $dpi}] } else { set pt $v }
        if {$newParent eq "px"} { set nv [expr {$pt * $dpi / 72.0}] } else { set nv $pt }
        set legendOverride($name) [format %.6g $nv]
    }
    set ui(plotFontUnitLast) $newUnit
    refreshManifestPreview
}

proc ::GX::legendFontUnitChanged {} {
    variable cfg
    variable ui
    set newRaw [string tolower [string trim $cfg(plot_legend_font_unit)]]
    if {$newRaw ni {inherit px pt}} { return }
    set oldRaw [expr {[info exists ui(plotLegendFontUnitLast)] ? $ui(plotLegendFontUnitLast) : $newRaw}]
    if {$oldRaw ni {inherit px pt}} { set oldRaw $newRaw }
    set base [string tolower [string trim $cfg(plot_font_unit)]]
    if {$base ni {px pt}} { set base px }
    set oldUnit [expr {$oldRaw eq "inherit" ? $base : $oldRaw}]
    set newUnit [expr {$newRaw eq "inherit" ? $base : $newRaw}]
    if {$oldUnit ne $newUnit} {
        set dpi $cfg(analysis_png_dpi)
        if {![string is double -strict $dpi] || $dpi <= 0} { set dpi 200.0 }
        set v [string trim $cfg(plot_legend_font_size)]
        if {$v ne "" && [string is double -strict $v] && $v > 0} {
            if {$oldUnit eq "px"} { set pt [expr {$v * 72.0 / $dpi}] } else { set pt $v }
            if {$newUnit eq "px"} { set nv [expr {$pt * $dpi / 72.0}] } else { set nv $pt }
            set cfg(plot_legend_font_size) [format %.6g $nv]
        }
    }
    set ui(plotLegendFontUnitLast) $newRaw
    refreshManifestPreview
}

proc ::GX::globalGridEnabledChanged {} {
    variable cfg
    if {![info exists cfg(plot_grid)]} { set cfg(plot_grid) 1 }
    if {![info exists cfg(plot_grid_mode)] || $cfg(plot_grid_mode) eq ""} { set cfg(plot_grid_mode) "both" }
    if {$cfg(plot_grid)} {
        if {$cfg(plot_grid_mode) eq "none" || $cfg(plot_grid_mode) eq "inherit"} { set cfg(plot_grid_mode) "both" }
    } else {
        set cfg(plot_grid_mode) "none"
    }
    refreshManifestPreview
}

proc ::GX::globalGridModeChanged {} {
    variable cfg
    if {![info exists cfg(plot_grid_mode)] || $cfg(plot_grid_mode) eq ""} { set cfg(plot_grid_mode) "both" }
    set cfg(plot_grid) [expr {$cfg(plot_grid_mode) eq "none" ? 0 : 1}]
    refreshManifestPreview
}

proc ::GX::globalGraphicsApply_v0933_before_3d_validation {{rerender 0}} {
    variable cfg
    if {[catch {validatePlotSettings} err]} {
        tk_messageBox -icon error -title "Global graphics" -message $err
        return
    }
    refreshManifestPreview
    catch {writeLegendOverrideFile}
    catch {destroy .globalgfx}
    if {$rerender} {
        set p [currentGraphPath]
        if {$p eq ""} {
            tk_messageBox -message "Global graphics settings were applied. Select a plot before requesting a rerender."
        } else {
            startRerenderPaths [list $p]
        }
    }
}
proc ::GX::globalGraphicsApply {{rerender 0}} {
    tailcall ::GX::globalGraphicsApply_v0933_before_3d_validation $rerender
}

proc ::GX::globalGraphicsDialog_v0933_before_3d {} {
    variable cfg
    variable ui
    # Keep the legacy master flag and explicit mode coherent in the editor.
    if {![info exists cfg(plot_grid)]} { set cfg(plot_grid) 1 }
    if {![info exists cfg(plot_grid_mode)] || $cfg(plot_grid_mode) eq ""} { set cfg(plot_grid_mode) "both" }
    if {!$cfg(plot_grid)} { set cfg(plot_grid_mode) "none" }
    if {$cfg(plot_grid_mode) eq "none"} { set cfg(plot_grid) 0 }
    set w .globalgfx
    catch {destroy $w}
    toplevel $w
    wm title $w "Global graphics"
    wm transient $w .
    grid columnconfigure $w 1 -weight 1

    ttk::label $w.intro -text "Global settings used by every native plot. Per-plot settings may override presentation details. Output DPI, font defaults and the global grid default originate here." -wraplength 720 -justify left
    grid $w.intro -row 0 -column 0 -columnspan 3 -sticky ew -padx 10 -pady {10 8}

    set r 1
    foreach {label key width} {
        "Output width [px]" plot_width_px 12
        "Output height [px]" plot_height_px 12
        "Output DPI" analysis_png_dpi 12
        "Axis tick font size" plot_font_size 12
        "Axis-label font size (blank = inherit)" plot_axis_label_font_size 12
        "Title font size (blank = inherit)" plot_title_font_size 12
        "Line width" plot_line_width 12
    } {
        ttk::label $w.l$r -text $label
        ttk::entry $w.e$r -textvariable ::GX::cfg($key) -width $width
        grid $w.l$r -row $r -column 0 -sticky e -padx 6 -pady 3
        grid $w.e$r -row $r -column 1 -sticky w -padx 6 -pady 3
        incr r
    }

    ttk::label $w.ful -text "Font unit"
    ttk::combobox $w.fu -textvariable ::GX::cfg(plot_font_unit) -values {px pt} -state readonly -width 10
    set ui(plotFontUnitLast) $cfg(plot_font_unit)
    bind $w.fu <<ComboboxSelected>> {::GX::plotFontUnitChanged}
    grid $w.ful -row $r -column 0 -sticky e -padx 6 -pady 3
    grid $w.fu -row $r -column 1 -sticky w -padx 6 -pady 3
    incr r

    ttk::label $w.gridlabel -text "Global grid"
    ttk::frame $w.grid
    ttk::checkbutton $w.grid.enabled -text "Enabled" -variable ::GX::cfg(plot_grid) -command ::GX::globalGridEnabledChanged
    ttk::combobox $w.grid.mode -textvariable ::GX::cfg(plot_grid_mode) -values {both vertical horizontal none} -state readonly -width 12
    bind $w.grid.mode <<ComboboxSelected>> {::GX::globalGridModeChanged}
    ttk::entry $w.grid.color -textvariable ::GX::cfg(plot_grid_color) -width 12
    ttk::button $w.grid.pick -text "Color..." -command [list ::GX::chooseConfigColor plot_grid_color "Grid color"]
    pack $w.grid.enabled $w.grid.mode $w.grid.color $w.grid.pick -side left -padx {0 5}
    grid $w.gridlabel -row $r -column 0 -sticky e -padx 6 -pady 3
    grid $w.grid -row $r -column 1 -columnspan 2 -sticky w -padx 6 -pady 3
    incr r

    ttk::label $w.lfslabel -text "Default legend font"
    ttk::frame $w.lfs
    ttk::entry $w.lfs.size -textvariable ::GX::cfg(plot_legend_font_size) -width 10
    ttk::combobox $w.lfs.unit -textvariable ::GX::cfg(plot_legend_font_unit) -values {inherit px pt} -state readonly -width 8
    set ui(plotLegendFontUnitLast) $cfg(plot_legend_font_unit)
    bind $w.lfs.unit <<ComboboxSelected>> {::GX::legendFontUnitChanged}
    pack $w.lfs.size $w.lfs.unit -side left -padx {0 5}
    grid $w.lfslabel -row $r -column 0 -sticky e -padx 6 -pady 3
    grid $w.lfs -row $r -column 1 -sticky w -padx 6 -pady 3
    incr r

    ttk::label $w.bglabel -text "Background"
    ttk::entry $w.bg -textvariable ::GX::cfg(plot_background) -width 14
    ttk::button $w.bgb -text "Choose..." -command [list ::GX::chooseConfigColor plot_background "Plot background"]
    grid $w.bglabel -row $r -column 0 -sticky e -padx 6 -pady 3
    grid $w.bg -row $r -column 1 -sticky w -padx 6 -pady 3
    grid $w.bgb -row $r -column 2 -sticky w -padx 3 -pady 3
    incr r

    ttk::label $w.note -text "px means a size referenced to the final PNG. pt means typographic points. Switching the default font unit converts inherited global text sizes using the current DPI so the apparent size is preserved. The legend can inherit that unit or use its own px/pt unit. Global grid Enabled/Mode/Color define the inherited grid style; per-module and per-plot Axes/grid overrides may replace it. Output DPI is global and must be 72..1200. Module graphics overrides inherit these values unless explicitly changed." -wraplength 720 -justify left
    grid $w.note -row $r -column 0 -columnspan 3 -sticky ew -padx 10 -pady 8
    incr r

    ttk::frame $w.buttons
    ttk::button $w.buttons.apply -text "Apply" -command [list ::GX::globalGraphicsApply 0]
    ttk::button $w.buttons.rerender -text "Apply + rerender current plot" -command [list ::GX::globalGraphicsApply 1]
    ttk::button $w.buttons.cancel -text "Close" -command [list destroy $w]
    pack $w.buttons.apply $w.buttons.rerender $w.buttons.cancel -side left -padx 5
    grid $w.buttons -row $r -column 0 -columnspan 3 -sticky e -padx 8 -pady {4 10}
}

proc ::GX::globalGraphicsDialog {} { ::GX::globalGraphicsDialog_v0933_before_3d }
proc ::GX::legendOverrideEnsure {gk} {
    variable legendOverride
    foreach {field def} {enabled 1 mode "" placement "" location "" alignment "" orientation "" layout "" columns "" background "" border "" border_color "" font_unit "" font_size "" external_margin_px "" manual_x "" manual_y ""} {
        if {![info exists legendOverride($gk,$field)]} { set legendOverride($gk,$field) $def }
    }
    # Migrate old session state in memory without changing the source manifest.
    if {[string trim $legendOverride($gk,placement)] eq "" && [string trim $legendOverride($gk,mode)] ne ""} {
        set legendOverride($gk,placement) $legendOverride($gk,mode)
    }
    if {[string trim $legendOverride($gk,layout)] eq "" && [string trim $legendOverride($gk,orientation)] ne ""} {
        switch -- $legendOverride($gk,orientation) {
            horizontal { set legendOverride($gk,layout) row }
            vertical { set legendOverride($gk,layout) stacked }
            default { set legendOverride($gk,layout) auto }
        }
    }
    if {[string trim $legendOverride($gk,alignment)] eq ""} { set legendOverride($gk,alignment) center }
}

proc ::GX::legendConfigDialog {} {
    variable ui
    variable cfg
    variable legendOverride
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a plot."; return }
    set gk [graphKeyForPath $p]
    if {$gk eq ""} { tk_messageBox -message "The selected plot does not expose plot-specific legend configuration."; return }
    if {![graphSupportsLegend $p]} { tk_messageBox -message "The selected plot has no legend."; return }
    legendOverrideEnsure $gk
    set w .legendcfg
    catch {destroy $w}
    toplevel $w
    wm title $w "Legend - $gk"
    wm transient $w .
    set ui(legendEditEnabled) $legendOverride($gk,enabled)
    foreach f {placement location alignment layout columns background border border_color font_unit font_size external_margin_px manual_x manual_y} {
        set ui(legendEdit,$f) $legendOverride($gk,$f)
    }
    if {$ui(legendEdit,placement) eq ""} { set ui(legendEdit,placement) inherit }
    if {$ui(legendEdit,location) eq ""} { set ui(legendEdit,location) inherit }
    if {$ui(legendEdit,alignment) eq ""} { set ui(legendEdit,alignment) inherit }
    if {$ui(legendEdit,layout) eq ""} { set ui(legendEdit,layout) inherit }
    if {$ui(legendEdit,border) eq ""} { set ui(legendEdit,border) inherit }
    if {$ui(legendEdit,font_unit) eq ""} { set ui(legendEdit,font_unit) inherit }
    grid columnconfigure $w 1 -weight 1
    ttk::label $w.title -text "Legend override for: [file tail $p]\nPlot ID: $gk" -justify left
    grid $w.title -row 0 -column 0 -columnspan 3 -sticky w -padx 8 -pady 7
    ttk::checkbutton $w.en -text "Use plot-specific configuration" -variable ::GX::ui(legendEditEnabled)
    grid $w.en -row 1 -column 0 -columnspan 3 -sticky w -padx 8 -pady 4
    set r 2
    foreach {label field values width} {
        "Placement" placement {inherit none inside below above right left manual} 16
        "Legend layout" layout {inherit auto row stacked wrapped} 16
        "Inside preset" location {inherit north northeast east southeast south southwest west northwest} 16
        "External alignment" alignment {inherit start center end} 16
    } {
        ttk::label $w.l$r -text $label
        ttk::combobox $w.e$r -textvariable ::GX::ui(legendEdit,$field) -values $values -state readonly -width $width
        grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 3
        grid $w.e$r -row $r -column 1 -sticky w -padx 5 -pady 3
        incr r
    }
    ttk::label $w.l$r -text "Legend font size"
    ttk::frame $w.fontrow
    ttk::entry $w.fontrow.size -textvariable ::GX::ui(legendEdit,font_size) -width 10
    ttk::combobox $w.fontrow.unit -textvariable ::GX::ui(legendEdit,font_unit) -values {inherit px pt} -state readonly -width 8
    pack $w.fontrow.size $w.fontrow.unit -side left -padx {0 5}
    ttk::label $w.h$r -text "size + unit; inherit uses module/global legend defaults" -foreground #555555
    grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 3
    grid $w.fontrow -row $r -column 1 -sticky w -padx 5 -pady 3
    grid $w.h$r -row $r -column 2 -sticky w -padx 5 -pady 3
    incr r
    foreach {label field hint} [list \
        "Wrapped columns" columns "used only by wrapped layout; blank = global" \
        "Background" background "#RRGGBB, none or blank = global" \
        "Border" border "inherit / 1 / 0" \
        "Border color" border_color "#RRGGBB or blank = global" \
        "External margin (px)" external_margin_px "blank = global; 0..100" \
        "Manual center X (0..1)" manual_x "used only with manual placement" \
        "Manual center Y (0..1)" manual_y "used only with manual placement"] {
        ttk::label $w.l$r -text $label
        ttk::entry $w.e$r -textvariable ::GX::ui(legendEdit,$field) -width 18
        ttk::label $w.h$r -text $hint -foreground #555555
        grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 3
        grid $w.e$r -row $r -column 1 -sticky w -padx 5 -pady 3
        grid $w.h$r -row $r -column 2 -sticky w -padx 5 -pady 3
        incr r
    }
    ttk::label $w.note -text "Placement and layout are independent. Examples: below + row, below + wrapped (4 columns), right + stacked, inside + row. Inside preset is used only for inside placement. External alignment means left/center/right for above/below and top/center/bottom for left/right. Manual X/Y are the CENTER of the legend. Legend font size and unit are edited together; unit may inherit the effective module/global legend unit or override px/pt for this plot. GNUplot uses the common custom legend renderer for deterministic placement and automatic overflow protection." -wraplength 700 -justify left
    grid $w.note -row $r -column 0 -columnspan 3 -sticky ew -padx 8 -pady 5; incr r
    ttk::frame $w.b
    ttk::button $w.b.save -text "Save" -command [list ::GX::legendConfigSave $w $gk $p 0]
    ttk::button $w.b.render -text "Save and rerender plot" -command [list ::GX::legendConfigSave $w $gk $p 1]
    ttk::button $w.b.cancel -text "Cancel" -command [list destroy $w]
    pack $w.b.save $w.b.render $w.b.cancel -side left -padx 4
    grid $w.b -row $r -column 0 -columnspan 3 -pady 8
}

proc ::GX::legendConfigSave {w gk path rerender} {
    variable ui
    variable legendOverride
    set m [string trim $ui(legendEdit,external_margin_px)]
    if {$m ne "" && (![string is double -strict $m] || $m < 0 || $m > 100)} {
        tk_messageBox -parent $w -icon error -message "External margin: enter a value between 0 and 100 px, or leave blank to inherit the global value."
        return
    }
    set c [string trim $ui(legendEdit,columns)]
    if {$c ne "" && (![string is integer -strict $c] || $c < 1 || $c > 64)} {
        tk_messageBox -parent $w -icon error -message "Wrapped columns: enter an integer from 1 to 64, or leave blank to inherit the global value."
        return
    }
    set fs [string trim $ui(legendEdit,font_size)]
    if {$fs ne "" && (![string is double -strict $fs] || $fs <= 0)} {
        tk_messageBox -parent $w -icon error -message "Legend font size must be a positive number, or blank to inherit the global value."
        return
    }
    set legendOverride($gk,enabled) [expr {$ui(legendEditEnabled) ? 1 : 0}]
    foreach f {placement location alignment layout columns background border border_color font_unit font_size external_margin_px manual_x manual_y} {
        set v [string trim $ui(legendEdit,$f)]
        if {$v eq "inherit"} { set v "" }
        set legendOverride($gk,$f) $v
    }
    # Compatibility aliases for old sessions/renderers.  New code reads the
    # explicit fields above first.
    set legendOverride($gk,mode) $legendOverride($gk,placement)
    switch -- $legendOverride($gk,layout) {
        row { set legendOverride($gk,orientation) horizontal }
        stacked { set legendOverride($gk,orientation) vertical }
        wrapped { set legendOverride($gk,orientation) horizontal }
        default { set legendOverride($gk,orientation) "" }
    }
    destroy $w
    refreshManifestPreview
    writeLegendOverrideFile
    if {$rerender} { startRerenderPaths [list $path] }
}

proc ::GX::gridModeFromXY {x y} {
    set x [string tolower [string trim $x]]
    set y [string tolower [string trim $y]]
    if {$x in {"" inherit} && $y in {"" inherit}} { return inherit }
    if {$x eq "on" && $y eq "on"} { return both }
    if {$x eq "on" && $y eq "off"} { return vertical }
    if {$x eq "off" && $y eq "on"} { return horizontal }
    if {$x eq "off" && $y eq "off"} { return none }
    return inherit
}

proc ::GX::gridModeToXY {mode} {
    switch -- [string tolower [string trim $mode]] {
        both { return [list on on] }
        vertical { return [list on off] }
        horizontal { return [list off on] }
        none { return [list off off] }
        default { return [list "" ""] }
    }
}

proc ::GX::plotDisplayUnitValues {} {
    return {inherit auto none s ms us ns min h day A mA uA nA pA V mV uV nV kV Hz kHz MHz GHz W mW uW J mJ uJ m cm mm um nm g mg ug K}
}

proc ::GX::axisConfigDialog_v0933_before_3d {} {
    variable ui
    variable axisOverride
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a plot."; return }
    set gk [graphKeyForPath $p]
    set panels [stackedGraphPanels $p]
    if {$gk eq ""} {
        tk_messageBox -message "The selected plot does not expose a configurable axes/grid ID."
        return
    }
    set isStacked [expr {[llength $panels] > 0}]
    axisOverrideEnsure $gk $panels
    # Compatibility: v0.9.1 stored only time_unit. Seed the new generic X unit
    # from it without destroying the old field.
    if {[string trim $axisOverride($gk,x_unit)] in {"" inherit} && [string trim $axisOverride($gk,time_unit)] ni {"" inherit}} {
        set axisOverride($gk,x_unit) $axisOverride($gk,time_unit)
    }
    set w .axiscfg
    catch {destroy $w}
    toplevel $w
    wm title $w "Axes / grid / display units - $gk"
    wm transient $w .
    grid columnconfigure $w 0 -weight 1

    set ui(axisEditEnabled) $axisOverride($gk,enabled)
    foreach f {time_unit x_unit y_unit y2_unit align_ylabels ylabel_x x_min x_max x_step x_format y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color} {
        set ui(axisEdit,$f) $axisOverride($gk,$f)
    }
    set ui(axisEdit,grid_mode) [gridModeFromXY $ui(axisEdit,xgrid) $ui(axisEdit,ygrid)]
    foreach f {time_unit x_unit y_unit y2_unit align_ylabels x_format y_format y2_format xgrid ygrid} {
        if {[string trim $ui(axisEdit,$f)] eq ""} { set ui(axisEdit,$f) inherit }
    }

    ttk::label $w.title -text "Axes/grid override for: [file tail $p]\nPlot ID: $gk\nDisplay-unit conversion changes only presentation; canonical dataset values are never modified." -justify left
    grid $w.title -row 0 -column 0 -sticky ew -padx 8 -pady 7
    ttk::checkbutton $w.en -text "Use plot-specific configuration" -variable ::GX::ui(axisEditEnabled)
    grid $w.en -row 1 -column 0 -sticky w -padx 8 -pady 3

    ttk::labelframe $w.x -text "X axis"
    grid $w.x -row 2 -column 0 -sticky ew -padx 8 -pady 4
    foreach c {1 3 5 7} { grid columnconfigure $w.x $c -weight 1 }
    ttk::label $w.x.ul -text "Display unit"
    ttk::combobox $w.x.u -textvariable ::GX::ui(axisEdit,x_unit) -values [plotDisplayUnitValues] -width 12
    grid $w.x.ul -row 0 -column 0 -sticky e -padx 3 -pady 3; grid $w.x.u -row 0 -column 1 -sticky w -padx 3
    foreach {col label field width} {2 "Min" x_min 11 4 "Max" x_max 11 6 "Step" x_step 11} {
        ttk::label $w.x.l$field -text $label; ttk::entry $w.x.e$field -textvariable ::GX::ui(axisEdit,$field) -width $width
        grid $w.x.l$field -row 0 -column $col -sticky e -padx 3; grid $w.x.e$field -row 0 -column [expr {$col+1}] -sticky w -padx 3
    }
    ttk::label $w.x.fl -text "Format"; ttk::combobox $w.x.f -textvariable ::GX::ui(axisEdit,x_format) -values {inherit auto %g %.0f %.1f %.2f %.3f %.4f} -width 12
    grid $w.x.fl -row 1 -column 0 -sticky e -padx 3 -pady 3; grid $w.x.f -row 1 -column 1 -sticky w -padx 3

    ttk::labelframe $w.y -text "Y axes"
    grid $w.y -row 3 -column 0 -sticky ew -padx 8 -pady 4
    foreach c {1 2 3 4 5} { grid columnconfigure $w.y $c -weight 1 }
    foreach {c h} {0 "Axis" 1 "Display unit" 2 "Min" 3 "Max" 4 "Step" 5 "Format"} { ttk::label $w.y.h$c -text $h; grid $w.y.h$c -row 0 -column $c -sticky w -padx 3 -pady 2 }
    foreach {r side prefix unitField} {1 "Left" y y_unit 2 "Right" y2 y2_unit} {
        ttk::label $w.y.n$r -text $side
        ttk::combobox $w.y.u$r -textvariable ::GX::ui(axisEdit,$unitField) -values [plotDisplayUnitValues] -width 12
        ttk::entry $w.y.min$r -textvariable ::GX::ui(axisEdit,${prefix}_min) -width 11
        ttk::entry $w.y.max$r -textvariable ::GX::ui(axisEdit,${prefix}_max) -width 11
        ttk::entry $w.y.step$r -textvariable ::GX::ui(axisEdit,${prefix}_step) -width 11
        ttk::combobox $w.y.fmt$r -textvariable ::GX::ui(axisEdit,${prefix}_format) -values {inherit auto %g %.0f %.1f %.2f %.3f %.4f} -width 12
        grid $w.y.n$r -row $r -column 0 -sticky w -padx 3 -pady 2
        grid $w.y.u$r -row $r -column 1 -sticky ew -padx 3 -pady 2
        grid $w.y.min$r -row $r -column 2 -sticky ew -padx 3 -pady 2
        grid $w.y.max$r -row $r -column 3 -sticky ew -padx 3 -pady 2
        grid $w.y.step$r -row $r -column 4 -sticky ew -padx 3 -pady 2
        grid $w.y.fmt$r -row $r -column 5 -sticky ew -padx 3 -pady 2
    }
    ttk::label $w.y.hint -text "Right-axis settings are ignored when the graph has no secondary Y axis. Units are editable: choose a common unit or type any unit compatible with the source metadata." -foreground #555555 -wraplength 950 -justify left
    grid $w.y.hint -row 3 -column 0 -columnspan 6 -sticky w -padx 3 -pady 3

    ttk::labelframe $w.common -text "Grid and labels"
    grid $w.common -row 4 -column 0 -sticky ew -padx 8 -pady 4
    foreach c {1 3 5 7} { grid columnconfigure $w.common $c -weight 1 }
    ttk::label $w.common.al -text "Align Y labels"; ttk::combobox $w.common.a -textvariable ::GX::ui(axisEdit,align_ylabels) -values {inherit 1 0} -state readonly -width 10
    ttk::label $w.common.yxl -text "Common Y-label X"; ttk::entry $w.common.yx -textvariable ::GX::ui(axisEdit,ylabel_x) -width 10
    ttk::label $w.common.gml -text "Grid mode"; ttk::combobox $w.common.gm -textvariable ::GX::ui(axisEdit,grid_mode) -values {both vertical horizontal none inherit} -state readonly -width 12
    ttk::label $w.common.gcl -text "Grid color"; ttk::entry $w.common.gc -textvariable ::GX::ui(axisEdit,grid_color) -width 12
    ttk::button $w.common.gcb -text "Choose..." -command ::GX::chooseAxisGridColor
    grid $w.common.al -row 0 -column 0 -sticky e -padx 3 -pady 3; grid $w.common.a -row 0 -column 1 -sticky w -padx 3
    grid $w.common.yxl -row 0 -column 2 -sticky e -padx 3; grid $w.common.yx -row 0 -column 3 -sticky w -padx 3
    grid $w.common.gml -row 0 -column 4 -sticky e -padx 3; grid $w.common.gm -row 0 -column 5 -sticky w -padx 3
    grid $w.common.gcl -row 0 -column 6 -sticky e -padx 3; grid $w.common.gc -row 0 -column 7 -sticky w -padx {3 1}; grid $w.common.gcb -row 0 -column 8 -sticky w -padx 2

    ttk::labelframe $w.pan -text "Per-panel overrides for stacked plots"
    grid $w.pan -row 5 -column 0 -sticky ew -padx 8 -pady 5
    foreach {c text} {0 "Panel" 1 "Y min" 2 "Y max" 3 "Y step" 4 "Y format" 5 "Y2 min" 6 "Y2 max" 7 "Y2 step" 8 "Y2 format" 9 "Grid mode" 10 "Y-label X"} {
        ttk::label $w.pan.h$c -text $text; grid $w.pan.h$c -row 0 -column $c -sticky w -padx 2 -pady 3
    }
    set i 0
    foreach pn $panels {
        incr i; ttk::label $w.pan.n$i -text $pn; grid $w.pan.n$i -row $i -column 0 -sticky w -padx 2 -pady 2
        set ui(axisEditPanel,$i,name) $pn
        foreach f {y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color ylabel_x} { set ui(axisEditPanel,$i,$f) $axisOverride($gk,$pn,$f) }
        foreach f {y_format y2_format xgrid ygrid} { if {[string trim $ui(axisEditPanel,$i,$f)] eq ""} { set ui(axisEditPanel,$i,$f) inherit } }
        set ui(axisEditPanel,$i,grid_mode) [gridModeFromXY $ui(axisEditPanel,$i,xgrid) $ui(axisEditPanel,$i,ygrid)]
        foreach {c f width} {1 y_min 9 2 y_max 9 3 y_step 9 5 y2_min 9 6 y2_max 9 7 y2_step 9} { ttk::entry $w.pan.e${i}_$f -textvariable ::GX::ui(axisEditPanel,$i,$f) -width $width; grid $w.pan.e${i}_$f -row $i -column $c -sticky ew -padx 2 -pady 2 }
        ttk::combobox $w.pan.e${i}_yf -textvariable ::GX::ui(axisEditPanel,$i,y_format) -values {inherit auto %g %.0f %.1f %.2f %.3f} -width 9
        ttk::combobox $w.pan.e${i}_y2f -textvariable ::GX::ui(axisEditPanel,$i,y2_format) -values {inherit auto %g %.0f %.1f %.2f %.3f} -width 9
        ttk::combobox $w.pan.e${i}_gm -textvariable ::GX::ui(axisEditPanel,$i,grid_mode) -values {inherit both vertical horizontal none} -state readonly -width 10
        ttk::entry $w.pan.e${i}_yx -textvariable ::GX::ui(axisEditPanel,$i,ylabel_x) -width 9
        grid $w.pan.e${i}_yf -row $i -column 4 -sticky ew -padx 2 -pady 2
        grid $w.pan.e${i}_y2f -row $i -column 8 -sticky ew -padx 2 -pady 2
        grid $w.pan.e${i}_gm -row $i -column 9 -sticky ew -padx 2 -pady 2
        grid $w.pan.e${i}_yx -row $i -column 10 -sticky ew -padx 2 -pady 2
    }
    set ui(axisEditPanelCount) $i
    if {!$isStacked} { ttk::label $w.pan.single -text "Single-panel plot: use X / Y settings above." -foreground #555555; grid $w.pan.single -row 1 -column 0 -columnspan 11 -sticky w -padx 4 -pady 6 }

    ttk::label $w.note -text "Limits and tick steps are expressed in the displayed unit. 'auto' chooses an engineering/time unit; 'none' keeps the source unit. X/Y/Y2 display conversion is presentation-only and is recorded in plot metadata so Dataset Selection API can convert selections back to canonical units." -wraplength 1000 -justify left
    grid $w.note -row 6 -column 0 -sticky ew -padx 8 -pady 5
    ttk::frame $w.b
    ttk::button $w.b.save -text "Save" -command [list ::GX::axisConfigSave $w $gk $p 0]
    ttk::button $w.b.render -text "Save and rerender plot" -command [list ::GX::axisConfigSave $w $gk $p 1]
    ttk::button $w.b.auto -text "Restore automatic" -command [list ::GX::axisConfigResetUi $w]
    ttk::button $w.b.cancel -text "Cancel" -command [list destroy $w]
    pack $w.b.save $w.b.render $w.b.auto $w.b.cancel -side left -padx 4
    grid $w.b -row 7 -column 0 -pady 8
}

proc ::GX::axisConfigDialog {} { ::GX::axisConfigDialog_v0933_before_3d }

proc ::GX::axisConfigResetUi_v0933_before_3d {w} {
    variable ui
    set ui(axisEditEnabled) 0
    foreach {f v} {time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" grid_mode inherit} { set ui(axisEdit,$f) $v }
    for {set i 1} {$i <= $ui(axisEditPanelCount)} {incr i} {
        foreach {f v} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x "" grid_mode inherit} { set ui(axisEditPanel,$i,$f) $v }
    }
}
proc ::GX::axisConfigResetUi {w} { ::GX::axisConfigResetUi_v0933_before_3d $w }

proc ::GX::axisConfigSave_v0933_before_3d {w gk path rerender} {
    variable ui
    variable axisOverride
    foreach f {ylabel_x x_min x_max x_step y_min y_max y_step y2_min y2_max y2_step} {
        set v [string trim $ui(axisEdit,$f)]
        if {$v ne "" && ![string is double -strict $v]} { tk_messageBox -parent $w -icon error -message "$f must be numeric or blank."; return }
    }
    foreach s {x y y2} {
        if {[string trim $ui(axisEdit,${s}_step)] ne "" && $ui(axisEdit,${s}_step) <= 0} { tk_messageBox -parent $w -icon error -message "[string toupper $s] step must be > 0."; return }
        if {[string trim $ui(axisEdit,${s}_min)] ne "" && [string trim $ui(axisEdit,${s}_max)] ne "" && $ui(axisEdit,${s}_min) >= $ui(axisEdit,${s}_max)} { tk_messageBox -parent $w -icon error -message "[string toupper $s] min must be lower than max."; return }
    }
    if {[string trim $ui(axisEdit,ylabel_x)] ne "" && ($ui(axisEdit,ylabel_x) < -0.5 || $ui(axisEdit,ylabel_x) > 0.2)} { tk_messageBox -parent $w -icon error -message "Y-label X should be approximately between -0.5 and 0.2."; return }
    set gc [string trim $ui(axisEdit,grid_color)]
    if {$gc ne "" && ![regexp {^#[0-9A-Fa-f]{6}$} $gc]} { tk_messageBox -parent $w -icon error -message "Grid color must be blank or #RRGGBB."; return }
    for {set i 1} {$i <= $ui(axisEditPanelCount)} {incr i} {
        foreach f {y_min y_max y_step y2_min y2_max y2_step ylabel_x} {
            set v [string trim $ui(axisEditPanel,$i,$f)]
            if {$v ne "" && ![string is double -strict $v]} { tk_messageBox -parent $w -icon error -message "Panel $ui(axisEditPanel,$i,name): $f must be numeric or blank."; return }
        }
        foreach s {y y2} {
            if {[string trim $ui(axisEditPanel,$i,${s}_step)] ne "" && $ui(axisEditPanel,$i,${s}_step) <= 0} { tk_messageBox -parent $w -icon error -message "Panel $ui(axisEditPanel,$i,name): $s step must be > 0."; return }
            if {[string trim $ui(axisEditPanel,$i,${s}_min)] ne "" && [string trim $ui(axisEditPanel,$i,${s}_max)] ne "" && $ui(axisEditPanel,$i,${s}_min) >= $ui(axisEditPanel,$i,${s}_max)} { tk_messageBox -parent $w -icon error -message "Panel $ui(axisEditPanel,$i,name): $s min must be lower than max."; return }
        }
    }
    set axisOverride($gk,enabled) [expr {$ui(axisEditEnabled) ? 1 : 0}]
    lassign [gridModeToXY $ui(axisEdit,grid_mode)] ui(axisEdit,xgrid) ui(axisEdit,ygrid)
    # Keep the v0.9.1 time_unit transport as an alias when X is a time unit.
    set xu [string trim $ui(axisEdit,x_unit)]
    if {$xu in {s ms us ns min h day auto inherit}} { set ui(axisEdit,time_unit) $xu } else { set ui(axisEdit,time_unit) inherit }
    foreach f {time_unit x_unit y_unit y2_unit align_ylabels ylabel_x x_min x_max x_step x_format y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color} {
        set v [string trim $ui(axisEdit,$f)]
        if {$v eq "inherit"} { set v "" }
        set axisOverride($gk,$f) $v
    }
    set panels {}
    for {set i 1} {$i <= $ui(axisEditPanelCount)} {incr i} {
        set pn $ui(axisEditPanel,$i,name); lappend panels $pn
        lassign [gridModeToXY $ui(axisEditPanel,$i,grid_mode)] ui(axisEditPanel,$i,xgrid) ui(axisEditPanel,$i,ygrid)
        foreach f {y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color ylabel_x} {
            set v [string trim $ui(axisEditPanel,$i,$f)]; if {$v eq "inherit"} { set v "" }; set axisOverride($gk,$pn,$f) $v
        }
    }
    set axisOverride($gk,panels) $panels
    destroy $w
    refreshManifestPreview
    writeAxisOverrideFile
    if {$rerender} { startRerenderPaths [list $path] }
}

proc ::GX::axisConfigSave {w gk path rerender} {
    tailcall ::GX::axisConfigSave_v0933_before_3d $w $gk $path $rerender
}
proc ::GX::beginLegendPick {} {
    variable ui
    variable legendOverride
    variable legendPickActive
    variable cfg
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a plot in the list first."; return }
    set gk [graphKeyForPath $p]
    if {$gk eq ""} { tk_messageBox -message "This plot does not support a plot-specific legend position."; return }
    if {![graphSupportsLegend $p]} { tk_messageBox -message "The selected plot has no legend to position."; return }
    legendOverrideEnsure $gk
    set legendPickActive 1
    set ui(legendPickPath) $p
    set ui(legendPickKey) $gk
    set px [expr {[string trim $legendOverride($gk,manual_x)] ne "" ? $legendOverride($gk,manual_x) : $cfg(plot_legend_manual_x)}]
    set py [expr {[string trim $legendOverride($gk,manual_y)] ne "" ? $legendOverride($gk,manual_y) : $cfg(plot_legend_manual_y)}]
    if {![string is double -strict $px]} { set px 0.75 }
    if {![string is double -strict $py]} { set py 0.85 }
    set ui(legendOverlayX) [expr {min(1,max(0,$px))}]
    set ui(legendOverlayY) [expr {min(1,max(0,$py))}]
    $ui(graphPreview) configure -cursor crosshair
    bind $ui(graphPreview) <Motion> {::GX::legendPreviewMotion %W %x %y}
    bind $ui(graphPreview) <Button-1> {::GX::legendPreviewClick %W %x %y}
    bind $ui(graphPreview) <Button-3> {::GX::cancelLegendPick}
    drawGraphPreview
    set ui(graphInfo) "LEGEND MANUAL PLACEMENT: click where the CENTER of the legend should be. Coordinates refer to the exported figure (X left->right, Y bottom->top). The final box is kept inside the figure if you click near an edge. Left click = apply + rerender; right click = cancel."
}

proc ::GX::legendPreviewClick {w x y} {
    variable ui
    variable legendOverride
    variable legendPickActive
    if {!$legendPickActive} return
    set geom [previewImageGeometry]
    if {[llength $geom] != 4} { return }
    lassign $geom ox oy iw ih
    if {$x < $ox || $x > ($ox+$iw) || $y < $oy || $y > ($oy+$ih)} {
        set ui(graphInfo) "The click is outside the plot image: choose a point inside the preview. Placement remains active."
        return
    }
    set px [expr {($x-$ox)/double($iw)}]
    set py [expr {1.0-($y-$oy)/double($ih)}]
    set gk $ui(legendPickKey); set path $ui(legendPickPath)
    legendOverrideEnsure $gk
    set legendOverride($gk,enabled) 1
    set legendOverride($gk,placement) manual
    set legendOverride($gk,mode) manual
    set legendOverride($gk,manual_x) [format %.4f $px]
    set legendOverride($gk,manual_y) [format %.4f $py]
    set legendPickActive 0
    bind $w <Button-1> {}
    bind $w <Motion> {}
    bind $w <Button-3> {}
    $w configure -cursor {}
    $w delete legendPickOverlay
    catch {unset ui(legendOverlayX)}
    catch {unset ui(legendOverlayY)}
    refreshManifestPreview
    writeLegendOverrideFile
    set ui(graphInfo) "Legend $gk: manual CENTER X=[format %.3f $px], Y=[format %.3f $py] (figure coordinates). Mode set to manual; rerendering..."
    startRerenderPaths [list $path]
}
