# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::customCompareTypeLabel {type} {
    switch -- $type {
        full { return "Full command" }
        normalized { return "Normalized" }
        carrier { return "Carrier zoom" }
        amplitude { return "Amplitudes" }
        default { return $type }
    }
}

proc ::GX::refreshCustomCompareTree {} {
    variable ui
    variable customCompare
    variable customCompareCount
    if {![info exists ui(customCompareTree)] || ![winfo exists $ui(customCompareTree)]} return
    set t $ui(customCompareTree)
    foreach id [$t children {}] { $t delete $id }
    for {set i 1} {$i <= $customCompareCount} {incr i} {
        set en [expr {[info exists customCompare($i,enabled)] && $customCompare($i,enabled) ? "YES" : "NO"}]
        set ty [expr {[info exists customCompare($i,type)] ? $customCompare($i,type) : "full"}]
        set la [expr {[info exists customCompare($i,layout)] ? $customCompare($i,layout) : "overlay"}]
        set lm [expr {[info exists customCompare($i,legend_mode)] ? $customCompare($i,legend_mode) : "inherit"}]
        set ll [expr {[info exists customCompare($i,legend_location)] ? $customCompare($i,legend_location) : "northeast"}]
        if {$lm eq "inside"} { set leg "Inside: $ll" } elseif {$lm eq "none"} { set leg "Hidden" } elseif {$lm eq "inherit" || $lm eq ""} { set leg "Global" } else { set leg [string totitle $lm] }
        set no [expr {[info exists customCompare($i,nodes)] ? $customCompare($i,nodes) : ""}]
        set ti [expr {[info exists customCompare($i,title)] ? $customCompare($i,title) : ""}]
        $t insert {} end -id "cg$i" -values [list $en [customCompareTypeLabel $ty] $la $leg $no $ti]
    }
}

proc ::GX::customCompareSelectedIndex {} {
    variable ui
    if {![info exists ui(customCompareTree)]} { return 0 }
    set sel [$ui(customCompareTree) selection]
    if {[llength $sel] != 1} { return 0 }
    if {[regexp {^cg([0-9]+)$} [lindex $sel 0] -> i]} { return $i }
    return 0
}

proc ::GX::customLegendModeToUi {v} {
    switch -- [string tolower [string trim $v]] {
        none { return "Hidden" }
        inside { return "Inside plot" }
        below { return "Below plot" }
        above { return "Above plot" }
        right { return "Right" }
        left { return "Left" }
        default { return "Use global setting" }
    }
}

proc ::GX::customLegendModeFromUi {v} {
    switch -- $v {
        "Hidden" { return none }
        "Inside plot" { return inside }
        "Below plot" { return below }
        "Above plot" { return above }
        "Right" { return right }
        "Left" { return left }
        default { return inherit }
    }
}

proc ::GX::customLegendLocationToUi {v} {
    switch -- [string tolower [string trim $v]] {
        north { return "Upper center" }
        northeast { return "Upper right" }
        east { return "Center right" }
        southeast { return "Lower right" }
        south { return "Lower center" }
        southwest { return "Lower left" }
        west { return "Center left" }
        northwest { return "Upper left" }
        default { return "Upper right" }
    }
}

proc ::GX::customLegendLocationFromUi {v} {
    switch -- $v {
        "Upper center" { return north }
        "Upper right" { return northeast }
        "Center right" { return east }
        "Lower right" { return southeast }
        "Lower center" { return south }
        "Lower left" { return southwest }
        "Center left" { return west }
        "Upper left" { return northwest }
        default { return northeast }
    }
}

proc ::GX::customCompareDialogSave {w} {
    variable ui
    set m [string trim $ui(customEditLegendExternalMargin)]
    if {$m ne "" && (![string is double -strict $m] || $m < 0 || $m > 100)} {
        tk_messageBox -parent $w -icon error -message "External margin: enter a value between 0 and 100 px or leave blank to use the global value."
        return
    }
    set ui(customEditLegendMode) [customLegendModeFromUi $ui(customEditLegendModeUi)]
    set ui(customEditLegendLocation) [customLegendLocationFromUi $ui(customEditLegendLocationUi)]
    set sel [$w.nodes.lb curselection]
    if {[llength $sel] == 0} {
        tk_messageBox -parent $w -icon error -message "Select at least one curve/node."
        return
    }
    set nodes {}
    foreach j $sel { lappend nodes [$w.nodes.lb get $j] }
    set ui(customEditNodes) [join $nodes ","]
    set ui(customEditResult) 1
    destroy $w
}

proc ::GX::customCompareEditDialog {idx} {
    variable customCompare
    variable ui
    set w .gxCustomCompare
    catch {destroy $w}
    if {$idx > 0} {
        set ui(customEditEnabled) [expr {[info exists customCompare($idx,enabled)] ? $customCompare($idx,enabled) : 1}]
        set ui(customEditType) [expr {[info exists customCompare($idx,type)] ? $customCompare($idx,type) : "full"}]
        set ui(customEditLayout) [expr {[info exists customCompare($idx,layout)] ? $customCompare($idx,layout) : "overlay"}]
        set ui(customEditTitle) [expr {[info exists customCompare($idx,title)] ? $customCompare($idx,title) : ""}]
        set ui(customEditXLabel) [expr {[info exists customCompare($idx,xlabel)] ? $customCompare($idx,xlabel) : ""}]
        set ui(customEditYLabel) [expr {[info exists customCompare($idx,ylabel)] ? $customCompare($idx,ylabel) : ""}]
        set ui(customEditYLabelTemplate) [expr {[info exists customCompare($idx,ylabel_template)] ? $customCompare($idx,ylabel_template) : ""}]
        set ui(customEditTimeUnit) [expr {[info exists customCompare($idx,time_unit)] ? $customCompare($idx,time_unit) : "inherit"}]
        set ui(customEditLegendMode) [expr {[info exists customCompare($idx,legend_mode)] ? $customCompare($idx,legend_mode) : "inherit"}]
        set ui(customEditLegendLocation) [expr {[info exists customCompare($idx,legend_location)] ? $customCompare($idx,legend_location) : "northeast"}]
        set ui(customEditLegendOrientation) [expr {[info exists customCompare($idx,legend_orientation)] ? $customCompare($idx,legend_orientation) : "inherit"}]
        set ui(customEditLegendBorder) [expr {[info exists customCompare($idx,legend_border)] ? $customCompare($idx,legend_border) : "inherit"}]
        set ui(customEditLegendExternalMargin) [expr {[info exists customCompare($idx,legend_external_margin_px)] ? $customCompare($idx,legend_external_margin_px) : ""}]
        set initialNodes [expr {[info exists customCompare($idx,nodes)] ? $customCompare($idx,nodes) : ""}]
    } else {
        set ui(customEditEnabled) 1
        set ui(customEditType) full
        set ui(customEditLayout) overlay
        set ui(customEditTitle) ""
        set ui(customEditXLabel) ""
        set ui(customEditYLabel) ""
        set ui(customEditYLabelTemplate) ""
        set ui(customEditTimeUnit) inherit
        set ui(customEditLegendMode) inherit
        set ui(customEditLegendLocation) northeast
        set ui(customEditLegendOrientation) inherit
        set ui(customEditLegendBorder) inherit
        set ui(customEditLegendExternalMargin) ""
        set initialNodes [join [currentChannelNames] ","]
    }
    set ui(customEditLegendModeUi) [customLegendModeToUi $ui(customEditLegendMode)]
    set ui(customEditLegendLocationUi) [customLegendLocationToUi $ui(customEditLegendLocation)]
    set ui(customEditResult) 0
    set ui(customEditNodes) ""
    toplevel $w
    wm title $w [expr {$idx > 0 ? "Edit additional plot" : "New additional plot"}]
    wm transient $w .
    grid columnconfigure $w 1 -weight 1
    ttk::checkbutton $w.en -text "Plot enabled" -variable ::GX::ui(customEditEnabled)
    grid $w.en -row 0 -column 0 -columnspan 2 -sticky w -padx 8 -pady 6
    ttk::label $w.tl -text "Plot type"
    ttk::combobox $w.type -textvariable ::GX::ui(customEditType) -values {full normalized carrier amplitude} -state readonly -width 20
    ttk::label $w.ll -text "Layout"
    ttk::combobox $w.layout -textvariable ::GX::ui(customEditLayout) -values {overlay stacked} -state readonly -width 20
    ttk::label $w.titlel -text "Title (blank = automatic)"
    ttk::entry $w.title -textvariable ::GX::ui(customEditTitle) -width 56
    grid $w.tl -row 1 -column 0 -sticky e -padx 6 -pady 4; grid $w.type -row 1 -column 1 -sticky w -padx 6 -pady 4
    grid $w.ll -row 2 -column 0 -sticky e -padx 6 -pady 4; grid $w.layout -row 2 -column 1 -sticky w -padx 6 -pady 4
    grid $w.titlel -row 3 -column 0 -sticky e -padx 6 -pady 4; grid $w.title -row 3 -column 1 -sticky ew -padx 6 -pady 4
    ttk::label $w.tul -text "Time unit"
    ttk::combobox $w.tu -textvariable ::GX::ui(customEditTimeUnit) -values {inherit auto s ms us ns min h day} -state readonly -width 16
    ttk::label $w.xll -text "X label (blank = automatic)"
    ttk::entry $w.xl -textvariable ::GX::ui(customEditXLabel) -width 56
    ttk::label $w.yll -text "Y label for overlay (blank = automatic)"
    ttk::entry $w.yl -textvariable ::GX::ui(customEditYLabel) -width 56
    ttk::label $w.ytl -text "Y label template for stacked ({NODE})"
    ttk::entry $w.yt -textvariable ::GX::ui(customEditYLabelTemplate) -width 56
    grid $w.tul -row 4 -column 0 -sticky e -padx 6 -pady 3; grid $w.tu -row 4 -column 1 -sticky w -padx 6 -pady 3
    grid $w.xll -row 5 -column 0 -sticky e -padx 6 -pady 3; grid $w.xl -row 5 -column 1 -sticky ew -padx 6 -pady 3
    grid $w.yll -row 6 -column 0 -sticky e -padx 6 -pady 3; grid $w.yl -row 6 -column 1 -sticky ew -padx 6 -pady 3
    grid $w.ytl -row 7 -column 0 -sticky e -padx 6 -pady 3; grid $w.yt -row 7 -column 1 -sticky ew -padx 6 -pady 3

    ttk::labelframe $w.legend -text "Legend for this plot"
    ttk::label $w.legend.ml -text "Display"
    ttk::combobox $w.legend.mode -textvariable ::GX::ui(customEditLegendModeUi) -values {"Use global setting" "Hidden" "Inside plot" "Below plot" "Above plot" "Right" "Left"} -state readonly -width 25
    ttk::label $w.legend.ll -text "Inside position"
    ttk::combobox $w.legend.loc -textvariable ::GX::ui(customEditLegendLocationUi) -values {"Upper center" "Upper right" "Center right" "Lower right" "Lower center" "Lower left" "Center left" "Upper left"} -state readonly -width 18
    ttk::label $w.legend.ol -text "Orientation"
    ttk::combobox $w.legend.orient -textvariable ::GX::ui(customEditLegendOrientation) -values {inherit auto vertical horizontal} -state readonly -width 16
    ttk::label $w.legend.bl -text "Border"
    ttk::combobox $w.legend.border -textvariable ::GX::ui(customEditLegendBorder) -values {inherit 0 1} -state readonly -width 10
    ttk::label $w.legend.mgl -text {External margin [px]}
    ttk::entry $w.legend.margin -textvariable ::GX::ui(customEditLegendExternalMargin) -width 10
    grid $w.legend.ml -row 0 -column 0 -sticky e -padx 5 -pady 3
    grid $w.legend.mode -row 0 -column 1 -sticky w -padx 5 -pady 3
    grid $w.legend.ll -row 0 -column 2 -sticky e -padx 5 -pady 3
    grid $w.legend.loc -row 0 -column 3 -sticky w -padx 5 -pady 3
    grid $w.legend.ol -row 1 -column 0 -sticky e -padx 5 -pady 3
    grid $w.legend.orient -row 1 -column 1 -sticky w -padx 5 -pady 3
    grid $w.legend.bl -row 1 -column 2 -sticky e -padx 5 -pady 3
    grid $w.legend.border -row 1 -column 3 -sticky w -padx 5 -pady 3
    grid $w.legend.mgl -row 2 -column 0 -sticky e -padx 5 -pady 3
    grid $w.legend.margin -row 2 -column 1 -sticky w -padx 5 -pady 3
    ttk::label $w.legend.note -text "Above/below/right/left positions are outside the data area. For external legends the global border is disabled by default; force it here with 0/1 if required. External margin is the additional distance in pixels. Changes become visible after the next rerender." -wraplength 720 -justify left -foreground #555555
    grid $w.legend.note -row 3 -column 0 -columnspan 4 -sticky ew -padx 5 -pady {2 5}
    grid $w.legend -row 8 -column 0 -columnspan 2 -sticky ew -padx 8 -pady 6

    ttk::labelframe $w.nodes -text "Curves / nodes to include in plot"
    listbox $w.nodes.lb -selectmode extended -exportselection 0 -height 9
    ttk::scrollbar $w.nodes.sy -orient vertical -command [list $w.nodes.lb yview]
    $w.nodes.lb configure -yscrollcommand [list $w.nodes.sy set]
    pack $w.nodes.sy -side right -fill y
    pack $w.nodes.lb -side left -fill both -expand 1
    grid $w.nodes -row 9 -column 0 -columnspan 2 -sticky nsew -padx 8 -pady 6
    grid rowconfigure $w 9 -weight 1
    set wanted [split [string map [list ";" ","] $initialNodes] ","]
    set pos 0
    foreach n [currentChannelNames] {
        $w.nodes.lb insert end $n
        if {[lsearch -exact $wanted $n] >= 0} { $w.nodes.lb selection set $pos }
        incr pos
    }
    ttk::label $w.note -text "Each additional plot is independent: create plots with a single curve or any subset of available nodes." -wraplength 600 -justify left
    grid $w.note -row 10 -column 0 -columnspan 2 -sticky ew -padx 8 -pady 4
    ttk::frame $w.b
    ttk::button $w.b.ok -text "Save" -command [list ::GX::customCompareDialogSave $w]
    ttk::button $w.b.cancel -text "Cancel" -command [list destroy $w]
    pack $w.b.ok $w.b.cancel -side left -padx 5
    grid $w.b -row 11 -column 0 -columnspan 2 -pady 8
    tkwait window $w
    if {!$ui(customEditResult)} { return {} }
    return [dict create enabled $ui(customEditEnabled) type $ui(customEditType) layout $ui(customEditLayout) nodes $ui(customEditNodes) title $ui(customEditTitle) xlabel $ui(customEditXLabel) ylabel $ui(customEditYLabel) ylabel_template $ui(customEditYLabelTemplate) time_unit $ui(customEditTimeUnit) legend_mode $ui(customEditLegendMode) legend_location $ui(customEditLegendLocation) legend_orientation $ui(customEditLegendOrientation) legend_border $ui(customEditLegendBorder) legend_external_margin_px $ui(customEditLegendExternalMargin)]
}

proc ::GX::customCompareAdd {} {
    variable customCompare
    variable customCompareCount
    set d [customCompareEditDialog 0]
    if {[dict size $d] == 0} return
    incr customCompareCount
    foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} { set customCompare($customCompareCount,$f) [dict get $d $f] }
    refreshCustomCompareTree; refreshManifestPreview
}

proc ::GX::customCompareEdit {} {
    variable customCompare
    set i [customCompareSelectedIndex]
    if {$i <= 0} return
    set d [customCompareEditDialog $i]
    if {[dict size $d] == 0} return
    foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} { set customCompare($i,$f) [dict get $d $f] }
    refreshCustomCompareTree; refreshManifestPreview
}

proc ::GX::customCompareDuplicate {} {
    variable customCompare
    variable customCompareCount
    set i [customCompareSelectedIndex]
    if {$i <= 0} return
    incr customCompareCount
    foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} { set customCompare($customCompareCount,$f) $customCompare($i,$f) }
    refreshCustomCompareTree
    if {[info exists ::GX::ui(customCompareTree)]} { $::GX::ui(customCompareTree) selection set "cg$customCompareCount" }
    refreshManifestPreview
}

proc ::GX::copyGraphOverrides {oldKey newKey} {
    variable axisOverride
    variable legendOverride
    if {$oldKey eq "" || $newKey eq "" || $oldKey eq $newKey} { return }
    foreach k [array names axisOverride "$oldKey,*"] {
        set suffix [string range $k [string length $oldKey] end]
        set axisOverride($newKey$suffix) $axisOverride($k)
    }
    foreach k [array names legendOverride "$oldKey,*"] {
        set suffix [string range $k [string length $oldKey] end]
        set legendOverride($newKey$suffix) $legendOverride($k)
    }
}

proc ::GX::effectiveTimeUnitForClone {gk defaultUnit} {
    variable cfg
    variable axisOverride
    if {[info exists axisOverride($gk,enabled)] && $axisOverride($gk,enabled) && [info exists axisOverride($gk,time_unit)]} {
        set u [string trim $axisOverride($gk,time_unit)]
        if {$u ni {"" inherit auto}} { return $u }
    }
    set u [string trim $cfg(plot_time_unit)]
    if {$u ni {"" auto inherit}} { return $u }
    return $defaultUnit
}

proc ::GX::startRerenderCompareCustom {idx} {
    variable cfg
    variable currentSession
    variable scriptDir
    variable customCompare
    if {$currentSession eq ""} { tk_messageBox -message "Open a session first."; return }
    set dir [file join $currentSession analysis CONFRONTO_STADI]
    set cache [file join $dir render_cache.mat]
    if {![file isfile $cache]} {
        tk_messageBox -icon error -message "Stage comparison has no render_cache.mat yet. Run the module once before cloning/rerendering plots."
        return
    }
    if {![info exists customCompare($idx,type)]} { return }
    set type $customCompare($idx,type)
    set expected [format "10_custom_%03d_%s.png" $idx $type]
    set spec [writeCompareCustomPlotFileFiltered $dir [list $expected]]
    set common [concat [list OMP_NUM_THREADS=$cfg(cpu_count) OPENBLAS_NUM_THREADS=$cfg(cpu_count) MKL_NUM_THREADS=$cfg(cpu_count) NUMEXPR_NUM_THREADS=$cfg(cpu_count)] [graphicsEnv] [plotEnv]]
    set env2 [list GXTXT_COMPARE_GRAPH_FULL=0 GXTXT_COMPARE_GRAPH_NORMALIZED=0 GXTXT_COMPARE_GRAPH_CARRIER=0 GXTXT_COMPARE_GRAPH_AMPLITUDE=0 GXTXT_COMPARE_CUSTOM_FILE=$spec]
    set script [file join $scriptDir modules GXTXT_rerender_confronto_stadi_v1.m]
    set cmd [concat [list env] $common $env2 [list $cfg(octave_cmd) --quiet --no-gui $script --cache $cache --out $dir --dpi $cfg(analysis_png_dpi)]]
    startPreparedQueue [list [list "Render cloned plot" $cmd]] "Clone plot"
}

proc ::GX::cloneCurrentPlot_legacy_compare {} {
    variable cfg
    variable customCompare
    variable customCompareCount
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a plot first."; return }
    set gk [graphKeyForPath $p]
    if {![string match "compare.*" $gk]} {
        tk_messageBox -icon info -message "Clone plot currently supports Stage Comparison plots. The clone engine is intentionally based on the reusable comparison renderer because it can switch overlay/stacked layout and arbitrary node subsets."
        return
    }

    set fields {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px}
    array set seed {}
    foreach f $fields { set seed($f) "" }
    set seed(enabled) 1; set seed(layout) overlay; set seed(legend_mode) inherit; set seed(legend_location) northeast; set seed(legend_orientation) inherit; set seed(legend_border) inherit; set seed(time_unit) inherit

    if {[regexp {^compare\.custom\.([0-9]+)\.(full|normalized|carrier|amplitude)$} $gk -> srcIdx srcType]} {
        set srcIdx [expr {int($srcIdx)}]
        foreach f $fields {
            if {[info exists customCompare($srcIdx,$f)]} { set seed($f) $customCompare($srcIdx,$f) }
        }
    } else {
        switch -- $gk {
            compare.full {
                set seed(type) full; set seed(layout) $cfg(plot_compare_full_layout); set seed(nodes) $cfg(plot_compare_full_nodes)
                set seed(title) $cfg(plot_compare_full_title); set seed(xlabel) $cfg(plot_compare_full_xlabel); set seed(ylabel) $cfg(plot_compare_full_ylabel); set seed(ylabel_template) $cfg(plot_compare_full_ylabel_template)
                set seed(time_unit) [effectiveTimeUnitForClone $gk s]
            }
            compare.normalized {
                set seed(type) normalized; set seed(nodes) $cfg(plot_compare_normalized_nodes); set seed(title) $cfg(plot_compare_normalized_title); set seed(xlabel) $cfg(plot_compare_normalized_xlabel); set seed(ylabel) $cfg(plot_compare_normalized_ylabel); set seed(ylabel_template) "{NODE}"; set seed(time_unit) [effectiveTimeUnitForClone $gk s]
            }
            compare.carrier {
                set seed(type) carrier; set seed(nodes) $cfg(plot_compare_carrier_nodes); set seed(title) $cfg(plot_compare_carrier_title); set seed(xlabel) $cfg(plot_compare_carrier_xlabel); set seed(ylabel) $cfg(plot_compare_carrier_ylabel); set seed(ylabel_template) "{NODE}"; set seed(time_unit) [effectiveTimeUnitForClone $gk us]
            }
            compare.amplitude {
                set seed(type) amplitude; set seed(nodes) $cfg(plot_compare_amplitude_nodes); set seed(title) $cfg(plot_compare_amplitude_title); set seed(ylabel) $cfg(plot_compare_amplitude_ylabel); set seed(time_unit) inherit
            }
            default { tk_messageBox -message "The selected comparison plot cannot be cloned."; return }
        }
    }

    incr customCompareCount
    set newIdx $customCompareCount
    foreach f $fields { set customCompare($newIdx,$f) $seed($f) }
    set d [customCompareEditDialog $newIdx]
    if {[dict size $d] == 0} {
        foreach f $fields { catch {unset customCompare($newIdx,$f)} }
        incr customCompareCount -1
        return
    }
    foreach f $fields { set customCompare($newIdx,$f) [dict get $d $f] }
    set newKey [format "compare.custom.%03d.%s" $newIdx $customCompare($newIdx,type)]
    copyGraphOverrides $gk $newKey
    refreshCustomCompareTree
    refreshManifestPreview
    writeAxisOverrideFile
    writeLegendOverrideFile
    startRerenderCompareCustom $newIdx
}

proc ::GX::editCurrentClonedPlot_legacy_compare {} {
    variable customCompare
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a cloned plot first."; return }
    set oldKey [graphKeyForPath $p]
    if {![regexp {^compare\.custom\.([0-9]+)\.(full|normalized|carrier|amplitude)$} $oldKey -> idx oldType]} {
        tk_messageBox -icon info -message "The selected plot is not a Stage Comparison clone. Use Clone plot... first."
        return
    }
    set idx [expr {int($idx)}]
    if {![info exists customCompare($idx,type)]} {
        tk_messageBox -icon error -message "Clone definition $idx is missing from the current configuration."
        return
    }
    set d [customCompareEditDialog $idx]
    if {[dict size $d] == 0} { return }
    foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} {
        set customCompare($idx,$f) [dict get $d $f]
    }
    set newType $customCompare($idx,type)
    set newKey [format "compare.custom.%03d.%s" $idx $newType]
    if {$newKey ne $oldKey} {
        copyGraphOverrides $oldKey $newKey
        set oldFile [file join [file dirname $p] [format "10_custom_%03d_%s.png" $idx $oldType]]
        if {[file isfile $oldFile]} { catch {file delete -force $oldFile} }
    }
    refreshCustomCompareTree
    refreshManifestPreview
    writeAxisOverrideFile
    writeLegendOverrideFile
    startRerenderCompareCustom $idx
}

proc ::GX::customCompareDelete {} {
    variable customCompare
    variable customCompareCount
    set i [customCompareSelectedIndex]
    if {$i <= 0} return
    for {set j $i} {$j < $customCompareCount} {incr j} {
        foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} { set customCompare($j,$f) $customCompare([expr {$j+1}],$f) }
    }
    foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} { catch {unset customCompare($customCompareCount,$f)} }
    incr customCompareCount -1
    refreshCustomCompareTree; refreshManifestPreview
}

proc ::GX::customCompareMove {delta} {
    variable customCompare
    variable customCompareCount
    variable ui
    set i [customCompareSelectedIndex]
    if {$i <= 0} return
    set j [expr {$i+$delta}]
    if {$j < 1 || $j > $customCompareCount} return
    foreach f {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} {
        set tmp $customCompare($i,$f); set customCompare($i,$f) $customCompare($j,$f); set customCompare($j,$f) $tmp
    }
    refreshCustomCompareTree
    $ui(customCompareTree) selection set "cg$j"
    refreshManifestPreview
}

proc ::GX::chooseChannelColor {i} {
    variable ch
    set initial [string trim $ch($i,plot_color)]
    if {$initial eq "" || ![regexp {^#[0-9A-Fa-f]{6}$} $initial]} { set initial "#000000" }
    set c [tk_chooseColor -initialcolor $initial -title "Plot color - $ch($i,name)"]
    if {$c ne ""} { set ch($i,plot_color) [string toupper $c] }
}

proc ::GX::chooseConfigColor {key title} {
    variable cfg
    set initial [string trim $cfg($key)]
    if {$initial eq "" || ![regexp {^#[0-9A-Fa-f]{6}$} $initial]} { set initial "#808080" }
    set c [tk_chooseColor -initialcolor $initial -title $title]
    if {$c ne ""} { set cfg($key) [string toupper $c] }
}

proc ::GX::chooseAxisGridColor {} {
    variable ui
    set initial [string trim $ui(axisEdit,grid_color)]
    if {$initial eq "" || ![regexp {^#[0-9A-Fa-f]{6}$} $initial]} { set initial "#808080" }
    set c [tk_chooseColor -initialcolor $initial -title "Plot grid color"]
    if {$c ne ""} { set ui(axisEdit,grid_color) [string toupper $c] }
}

proc ::GX::choosePanelGridColor {i} {
    variable ui
    if {![info exists ui(axisEditPanel,$i,grid_color)]} { return }
    set initial [string trim $ui(axisEditPanel,$i,grid_color)]
    if {$initial eq "" || ![regexp {^#[0-9A-Fa-f]{6}$} $initial]} { set initial "#808080" }
    set c [tk_chooseColor -initialcolor $initial -title "Panel grid color"]
    if {$c ne ""} { set ui(axisEditPanel,$i,grid_color) [string toupper $c] }
}

