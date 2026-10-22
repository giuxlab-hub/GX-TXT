# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::analysisLog {msg} {
    # Tutti i messaggi operativi vengono mostrati nella scheda Esecuzione.
    # Il file logs/analysis.log resta separato per tracciabilita' su disco.
    guiLog "ANALYSIS: $msg"
}

proc ::GX::octaveQuote {s} {
    return [string map [list "'" "''"] $s]
}

proc ::GX::graphicsEnv {} {
    variable cfg
    set out [list \
        GXTXT_GRAPHICS_MODE=$cfg(graphics_mode) \
        GXTXT_GRAPHICS_TOOLKIT=$cfg(graphics_toolkit) \
        GXTXT_GRAPHICS_VISIBLE=$cfg(graphics_visible)]

    set mode [string tolower [string trim $cfg(graphics_mode)]]
    set disp [string trim $cfg(graphics_display)]
    if {$mode eq "headless"} {
        # Impedisce ai toolkit di appoggiarsi per errore alla sessione X inoltrata.
        lappend out DISPLAY=
    } elseif {$disp ne ""} {
        lappend out DISPLAY=$disp
    }
    return $out
}

proc ::GX::useCurrentDisplay {} {
    variable cfg
    if {[info exists ::env(DISPLAY)]} {
        set cfg(graphics_display) $::env(DISPLAY)
        setStatus "DISPLAY set to $cfg(graphics_display)"
    } else {
        set cfg(graphics_display) ""
        setStatus "No DISPLAY variable in the current session"
    }
}

proc ::GX::envNodeKey {name} {
    set k [string toupper $name]
    regsub -all {[^A-Z0-9_]} $k {_} k
    if {$k eq ""} { set k "NODE" }
    if {[regexp {^[0-9]} $k]} { set k "N_$k" }
    return $k
}

proc ::GX::nodePlotMeta {node} {
    variable ch
    for {set i 1} {$i <= 8} {incr i} {
        if {$ch($i,name) eq $node} {
            set label [string trim $ch($i,plot_label)]
            if {$label eq ""} { set label $node }
            return [list $label [string trim $ch($i,plot_color)]]
        }
    }
    return [list $node ""]
}


proc ::GX::stackedGraphPanels {path} {
    variable cfg
    variable customCompare
    # plot.dataset multi-panel: use public artifact state so Axes controls follow the effective rendered panel mode.
    catch {modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2}
    if {[llength [info commands ::GX::PlotDatasetAPIv2::plotRefForArtifact]] &&
        [llength [info commands ::GX::PlotDatasetAPIv2::multiPanelEnabled]] &&
        [llength [info commands ::GX::PlotDatasetAPIv2::panelIds]]} {
        if {![catch {set pdRef [::GX::PlotDatasetAPIv2::plotRefForArtifact $path]}] && $pdRef ne ""} {
            if {![catch {set pdEnabled [::GX::PlotDatasetAPIv2::multiPanelEnabled $pdRef]}] && $pdEnabled} {
                if {![catch {set pdPanels [::GX::PlotDatasetAPIv2::panelIds $pdRef]}] && [llength $pdPanels] > 1} {return $pdPanels}
            }
            return {}
        }
    } elseif {[llength [info commands ::GX::PlotDatasetAPIv2::panelIdsForArtifact]]} {
        if {![catch {set pdPanels [::GX::PlotDatasetAPIv2::panelIdsForArtifact $path]}] && [llength $pdPanels] > 1} {return $pdPanels}
    }
    set gk [graphKeyForPath $path]
    if {$gk eq "compare.full"} {
        if {![string equal -nocase $cfg(plot_compare_full_layout) "stacked"]} { return {} }
        set raw $cfg(plot_compare_full_nodes)
    } elseif {[regexp {^compare\.custom\.([0-9]+)\.(full|normalized|carrier)$} $gk -> idx type]} {
        set idx [expr {int($idx)}]
        if {![info exists customCompare($idx,layout)] || ![string equal -nocase $customCompare($idx,layout) "stacked"]} { return {} }
        set raw [expr {[info exists customCompare($idx,nodes)] ? $customCompare($idx,nodes) : ""}]
    } else {
        return {}
    }
    set out {}
    foreach n [split $raw ","] {
        set n [string trim $n]
        if {$n ne "" && [lsearch -exact $out $n] < 0} { lappend out $n }
    }
    return $out
}

proc ::GX::axisOverrideFieldDefaults {} {
    return {enabled 1 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color ""}
}
proc ::GX::axisOverrideEnsure_v0933_before_3d {gk panels} {
    variable axisOverride
    foreach {field def} [axisOverrideFieldDefaults] {
        if {![info exists axisOverride($gk,$field)]} { set axisOverride($gk,$field) $def }
    }
    set merged [expr {[info exists axisOverride($gk,panels)] ? $axisOverride($gk,panels) : {}}]
    foreach pn $panels {
        if {[lsearch -exact $merged $pn] < 0} { lappend merged $pn }
        foreach {field def} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x ""} {
            if {![info exists axisOverride($gk,$pn,$field)]} { set axisOverride($gk,$pn,$field) $def }
        }
    }
    set axisOverride($gk,panels) $merged
}
proc ::GX::axisOverrideEnsure {gk panels} {
    tailcall ::GX::axisOverrideEnsure_v0933_before_3d $gk $panels
}

proc ::GX::writeAxisOverrideFile_v0933_before_3d {} {
    variable currentSession
    variable axisOverride
    if {$currentSession eq ""} { return "" }
    set keys {}
    foreach k [array names axisOverride "*,enabled"] {
        set gk [string range $k 0 end-8]
        if {[lsearch -exact $keys $gk] < 0} { lappend keys $gk }
    }
    if {[llength $keys] == 0} { return "" }
    set d [file join $currentSession analysis]
    file mkdir $d
    set path [file join $d .plot_axis_overrides.tsv]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "key\tpanel\tenabled\ttime_unit\tx_unit\ty_unit\ty2_unit\talign_ylabels\tylabel_x\tx_min\tx_max\tx_step\tx_format\ty_min\ty_max\ty_step\ty_format\ty2_min\ty2_max\ty2_step\ty2_format\txgrid\tygrid\tgrid_color"
    foreach gk [lsort $keys] {
        set row [list $gk *]
        foreach {field def} {enabled 1 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color ""} {
            set v [expr {[info exists axisOverride($gk,$field)] ? $axisOverride($gk,$field) : $def}]
            set v [string map [list "\t" " " "\n" " " "\r" " "] $v]
            lappend row $v
        }
        puts $fd [join $row "\t"]
        set panels [expr {[info exists axisOverride($gk,panels)] ? $axisOverride($gk,panels) : {}}]
        foreach pn $panels {
            set pyx [expr {[info exists axisOverride($gk,$pn,ylabel_x)] ? $axisOverride($gk,$pn,ylabel_x) : ""}]
            set row [list $gk $pn 1 inherit inherit inherit inherit inherit $pyx "" "" "" inherit]
            foreach {field def} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color ""} {
                set v [expr {[info exists axisOverride($gk,$pn,$field)] ? $axisOverride($gk,$pn,$field) : $def}]
                set v [string map [list "\t" " " "\n" " " "\r" " "] $v]
                lappend row $v
            }
            puts $fd [join $row "\t"]
        }
    }
    close $fd
    return $path
}
proc ::GX::writeAxisOverrideFile {} { ::GX::writeAxisOverrideFile_v0933_before_3d }

proc ::GX::writeLegendOverrideFile {} {
    variable currentSession
    variable legendOverride
    if {$currentSession eq ""} { return "" }
    set keys {}
    foreach k [array names legendOverride "*,enabled"] {
        set gk [string range $k 0 end-8]
        if {[lsearch -exact $keys $gk] < 0} { lappend keys $gk }
    }
    if {[llength $keys] == 0} { return "" }
    set d [file join $currentSession analysis]
    file mkdir $d
    set path [file join $d .plot_legend_overrides.tsv]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "key\tenabled\tmode\tplacement\tlocation\talignment\torientation\tlayout\tcolumns\tbackground\tborder\tborder_color\tfont_unit\tfont_size\texternal_margin_px\tmanual_x\tmanual_y"
    foreach gk [lsort $keys] {
        set vals [list $gk]
        foreach {field def} {enabled 1 mode "" placement "" location "" alignment "" orientation "" layout "" columns "" background "" border "" border_color "" font_unit "" font_size "" external_margin_px "" manual_x "" manual_y ""} {
            set v [expr {[info exists legendOverride($gk,$field)] ? $legendOverride($gk,$field) : $def}]
            set v [string map [list "\t" " " "\n" " " "\r" " "] $v]
            lappend vals $v
        }
        puts $fd [join $vals "\t"]
    }
    close $fd
    return $path
}

proc ::GX::plotEnv_v060_legacy {} {
    variable cfg
    variable ch
    set out [list \
        GXTXT_PLOT_WIDTH_PX=$cfg(plot_width_px) \
        GXTXT_PLOT_HEIGHT_PX=$cfg(plot_height_px) \
        GXTXT_PNG_DPI=$cfg(analysis_png_dpi) \
        GXTXT_PLOT_FONT_UNIT=$cfg(plot_font_unit) \
        GXTXT_PLOT_FONT_SIZE=$cfg(plot_font_size) \
        GXTXT_PLOT_AXIS_LABEL_FONT_SIZE=$cfg(plot_axis_label_font_size) \
        GXTXT_PLOT_TITLE_FONT_SIZE=$cfg(plot_title_font_size) \
        GXTXT_PLOT_LINE_WIDTH=$cfg(plot_line_width) \
        GXTXT_PLOT_GRID=$cfg(plot_grid) \
        GXTXT_PLOT_GRID_MODE=$cfg(plot_grid_mode) \
        GXTXT_PLOT_GRID_COLOR=$cfg(plot_grid_color) \
        GXTXT_PLOT_TIME_UNIT=$cfg(plot_time_unit) \
        GXTXT_PLOT_STACKED_SHARED_X=$cfg(plot_stacked_shared_x) \
        GXTXT_PLOT_STACKED_BOTTOM_XTICKS_ONLY=$cfg(plot_stacked_bottom_xticks_only) \
        GXTXT_PLOT_STACKED_GRID_MODE=$cfg(plot_stacked_grid_mode) \
        GXTXT_PLOT_STACKED_MARGIN_LEFT_PCT=$cfg(plot_stacked_margin_left_pct) \
        GXTXT_PLOT_STACKED_MARGIN_RIGHT_PCT=$cfg(plot_stacked_margin_right_pct) \
        GXTXT_PLOT_STACKED_MARGIN_TOP_PCT=$cfg(plot_stacked_margin_top_pct) \
        GXTXT_PLOT_STACKED_MARGIN_BOTTOM_PCT=$cfg(plot_stacked_margin_bottom_pct) \
        GXTXT_PLOT_STACKED_GAP_PCT=$cfg(plot_stacked_gap_pct) \
        GXTXT_PLOT_STACKED_ALIGN_YLABELS=$cfg(plot_stacked_align_ylabels) \
        GXTXT_PLOT_STACKED_YLABEL_X=$cfg(plot_stacked_ylabel_x) \
        GXTXT_PLOT_LEGEND_MODE=$cfg(plot_legend_mode) \
        GXTXT_PLOT_LEGEND_LOCATION=$cfg(plot_legend_location) \
        GXTXT_PLOT_LEGEND_FONT_UNIT=$cfg(plot_legend_font_unit) \
        GXTXT_PLOT_LEGEND_FONT_SIZE=$cfg(plot_legend_font_size) \
        GXTXT_PLOT_LEGEND_ORIENTATION=$cfg(plot_legend_orientation) \
        GXTXT_PLOT_LEGEND_LAYOUT=$cfg(plot_legend_layout) \
        GXTXT_PLOT_LEGEND_ALIGNMENT=$cfg(plot_legend_alignment) \
        GXTXT_PLOT_LEGEND_COLUMNS=$cfg(plot_legend_columns) \
        GXTXT_PLOT_LEGEND_BACKGROUND=$cfg(plot_legend_background) \
        GXTXT_PLOT_LEGEND_BORDER=$cfg(plot_legend_border) \
        GXTXT_PLOT_LEGEND_EXTERNAL_BORDER=$cfg(plot_legend_external_border) \
        GXTXT_PLOT_LEGEND_BORDER_COLOR=$cfg(plot_legend_border_color) \
        GXTXT_PLOT_LEGEND_EXTERNAL_MARGIN_PX=$cfg(plot_legend_external_margin_px) \
        GXTXT_PLOT_LEGEND_MANUAL_X=$cfg(plot_legend_manual_x) \
        GXTXT_PLOT_LEGEND_MANUAL_Y=$cfg(plot_legend_manual_y) \
        GXTXT_PLOT_BACKGROUND=$cfg(plot_background) \
        GXTXT_COMPARE_GRAPH_FULL=$cfg(plot_compare_graph_full) \
        GXTXT_COMPARE_GRAPH_NORMALIZED=$cfg(plot_compare_graph_normalized) \
        GXTXT_COMPARE_GRAPH_CARRIER=$cfg(plot_compare_graph_carrier) \
        GXTXT_COMPARE_GRAPH_AMPLITUDE=$cfg(plot_compare_graph_amplitude) \
        GXTXT_COMPARE_FULL_LAYOUT=$cfg(plot_compare_full_layout) \
        GXTXT_COMPARE_FULL_NODES=$cfg(plot_compare_full_nodes) \
        GXTXT_COMPARE_NORMALIZED_NODES=$cfg(plot_compare_normalized_nodes) \
        GXTXT_COMPARE_CARRIER_NODES=$cfg(plot_compare_carrier_nodes) \
        GXTXT_COMPARE_AMPLITUDE_NODES=$cfg(plot_compare_amplitude_nodes) \
        GXTXT_COMPARE_FULL_TITLE=$cfg(plot_compare_full_title) \
        GXTXT_COMPARE_NORMALIZED_TITLE=$cfg(plot_compare_normalized_title) \
        GXTXT_COMPARE_CARRIER_TITLE=$cfg(plot_compare_carrier_title) \
        GXTXT_COMPARE_AMPLITUDE_TITLE=$cfg(plot_compare_amplitude_title) \
        GXTXT_COMPARE_FULL_XLABEL=$cfg(plot_compare_full_xlabel) \
        GXTXT_COMPARE_FULL_YLABEL=$cfg(plot_compare_full_ylabel) \
        GXTXT_COMPARE_FULL_YLABEL_TEMPLATE=$cfg(plot_compare_full_ylabel_template) \
        GXTXT_COMPARE_NORMALIZED_XLABEL=$cfg(plot_compare_normalized_xlabel) \
        GXTXT_COMPARE_NORMALIZED_YLABEL=$cfg(plot_compare_normalized_ylabel) \
        GXTXT_COMPARE_CARRIER_XLABEL=$cfg(plot_compare_carrier_xlabel) \
        GXTXT_COMPARE_CARRIER_YLABEL=$cfg(plot_compare_carrier_ylabel) \
        GXTXT_COMPARE_AMPLITUDE_YLABEL=$cfg(plot_compare_amplitude_ylabel) \
        GXTXT_IR_GRAPH_FULL=$cfg(plot_ir_graph_full) \
        GXTXT_IR_GRAPH_CARRIER=$cfg(plot_ir_graph_carrier) \
        GXTXT_IR_GRAPH_MARKSPACE=$cfg(plot_ir_graph_markspace) \
        GXTXT_IR_GRAPH_DURATIONS=$cfg(plot_ir_graph_durations) \
        GXTXT_IR_FULL_TITLE=$cfg(plot_ir_full_title) \
        GXTXT_IR_CARRIER_TITLE=$cfg(plot_ir_carrier_title) \
        GXTXT_IR_MARKSPACE_TITLE=$cfg(plot_ir_markspace_title) \
        GXTXT_IR_DURATIONS_TITLE=$cfg(plot_ir_durations_title) \
        GXTXT_IR_VOLTAGE_YLABEL=$cfg(plot_ir_voltage_ylabel) \
        GXTXT_IR_FULL_XLABEL=$cfg(plot_ir_full_xlabel) \
        GXTXT_IR_CARRIER_XLABEL=$cfg(plot_ir_carrier_xlabel) \
        GXTXT_IR_MARKSPACE_XLABEL=$cfg(plot_ir_markspace_xlabel) \
        GXTXT_IR_MARKSPACE_YLABEL=$cfg(plot_ir_markspace_ylabel) \
        GXTXT_IR_DURATIONS_XLABEL=$cfg(plot_ir_durations_xlabel) \
        GXTXT_IR_DURATIONS_YLABEL=$cfg(plot_ir_durations_ylabel)]
    for {set g 1} {$g <= 9} {incr g} {
        lappend out "GXTXT_HOLDLED_GRAPH_$g=$cfg(plot_holdled_g$g)"
    }
    for {set i 1} {$i <= 8} {incr i} {
        if {!$ch($i,enabled) || [string trim $ch($i,name)] eq ""} continue
        set key [envNodeKey $ch($i,name)]
        set label [string trim $ch($i,plot_label)]
        if {$label eq ""} { set label $ch($i,name) }
        lappend out "GXTXT_PLOT_LABEL_$key=$label"
        lappend out "GXTXT_PLOT_COLOR_$key=$ch($i,plot_color)"
    }
    set lof [writeLegendOverrideFile]
    if {$lof ne ""} { lappend out "GXTXT_PLOT_LEGEND_OVERRIDE_FILE=$lof" }
    set aof [writeAxisOverrideFile]
    if {$aof ne ""} { lappend out "GXTXT_PLOT_AXIS_OVERRIDE_FILE=$aof" }
    return $out
}

proc ::GX::writeOctaveLauncher {stem body} {
    variable currentSession
    variable scriptDir
    set d [file join $currentSession analysis .launchers]
    file mkdir $d
    set path [file join $d "[sanitize $stem].m"]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd {% SPDX-License-Identifier: GPL-3.0-or-later}
    puts $fd {% Auto-generated GX-TXT pipeline launcher.}
    puts $fd "addpath('[octaveQuote [file join $scriptDir core octave graphics]]');"
    puts $fd "addpath('[octaveQuote [file join $scriptDir core octave io]]');"
    puts $fd "addpath('[octaveQuote [file join $scriptDir core octave util]]');"
    puts $fd {try}
    puts $fd "  $body"
    puts $fd {catch err}
    puts $fd {  fprintf(2,'GXTXT_FATAL: %s\n',err.message);}
    puts $fd {  for __gx_i=1:numel(err.stack)}
    puts $fd {    fprintf(2,'  at %s:%d\n',err.stack(__gx_i).name,err.stack(__gx_i).line);}
    puts $fd {  endfor}
    puts $fd {  exit(1);}
    puts $fd {end_try_catch}
    puts $fd {exit(0);}
    close $fd
    return $path
}


proc ::GX::writeCompareCustomPlotFile {outDir} {
    variable customCompare
    variable customCompareCount
    if {$customCompareCount <= 0} { return "" }
    set path [file join $outDir custom_plots.tsv]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "index\tenabled\ttype\tlayout\tnodes\tlegend_mode\tlegend_location\tlegend_orientation\tlegend_border\tlegend_external_margin_px\ttitle\txlabel\tylabel\tylabel_template\ttime_unit"
    for {set i 1} {$i <= $customCompareCount} {incr i} {
        set vals [list $i]
        foreach {field def} {enabled 1 type full layout overlay nodes "" legend_mode inherit legend_location northeast legend_orientation inherit legend_border inherit legend_external_margin_px "" title "" xlabel "" ylabel "" ylabel_template "" time_unit inherit} {
            set v [expr {[info exists customCompare($i,$field)] ? $customCompare($i,$field) : $def}]
            set v [string map [list "\t" " " "\n" " " "\r" " "] $v]
            lappend vals $v
        }
        puts $fd [join $vals "\t"]
    }
    close $fd
    return $path
}


proc ::GX::writeCompareCustomPlotFileFiltered {outDir selectedFiles} {
    variable customCompare
    variable customCompareCount
    if {$customCompareCount <= 0} { return "" }
    set path [file join $outDir custom_plots_rerender.tsv]
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "index\tenabled\ttype\tlayout\tnodes\tlegend_mode\tlegend_location\tlegend_orientation\tlegend_border\tlegend_external_margin_px\ttitle\txlabel\tylabel\tylabel_template\ttime_unit"
    for {set i 1} {$i <= $customCompareCount} {incr i} {
        set type [expr {[info exists customCompare($i,type)] ? $customCompare($i,type) : "full"}]
        set expected [format "10_custom_%03d_%s.png" $i $type]
        set enabled [expr {[lsearch -exact $selectedFiles $expected] >= 0 ? 1 : 0}]
        set vals [list $i $enabled]
        foreach {field def} {type full layout overlay nodes "" legend_mode inherit legend_location northeast legend_orientation inherit legend_border inherit legend_external_margin_px "" title "" xlabel "" ylabel "" ylabel_template "" time_unit inherit} {
            set v [expr {[info exists customCompare($i,$field)] ? $customCompare($i,$field) : $def}]
            set v [string map [list "\t" " " "\n" " " "\r" " "] $v]
            lappend vals $v
        }
        puts $fd [join $vals "\t"]
    }
    close $fd
    return $path
}

proc ::GX::nodeNameFromFolder {folder} {
    variable ch
    for {set i 1} {$i <= 8} {incr i} {
        if {[sanitize $ch($i,name)] eq $folder} { return $ch($i,name) }
    }
    return $folder
}

proc ::GX::graphKeyForPath_v062_legacy {path} {
    variable currentSession
    if {$currentSession eq ""} { return "" }
    set rel [string range $path [expr {[string length $currentSession]+1}] end]
    set parts [file split $rel]
    if {[llength $parts] < 3 || [lindex $parts 0] ne "analysis"} { return "" }
    set module [lindex $parts 1]
    set base [file tail $path]
    if {$module eq "CONFRONTO_STADI"} {
        switch -glob -- $base {
            01_stadi_comando_completo.png { return "compare.full" }
            02_stadi_normalizzati.png { return "compare.normalized" }
            03_stadi_portante_zoom.png { return "compare.carrier" }
            04_stadi_ampiezze.png { return "compare.amplitude" }
            10_custom_*.png {
                if {[regexp {^10_custom_([0-9]+)_([^.]+)\.png$} $base -> n type]} {
                    return [format "compare.custom.%03d.%s" $n $type]
                }
            }
        }
    } elseif {$module eq "IR" && [llength $parts] >= 4} {
        set node [lindex $parts 2]
        switch -- $base {
            01_vir_comando_completo.png { return "ir.$node.full" }
            02_vir_portante_zoom.png { return "ir.$node.carrier" }
            03_mark_space_ricostruito.png { return "ir.$node.markspace" }
            04_durate_mark_space.png { return "ir.$node.durations" }
        }
    } elseif {$module eq "HOLD_LED"} {
        if {[regexp {^([0-9][0-9])_} $base -> n]} { return "holdled.[expr {int($n)}]" }
    }
    return ""
}

proc ::GX::graphKeyForPath {path} {
    return [::GX::graphKeyForPath_v062_legacy $path]
}

proc ::GX::legendEffectiveDescription {path} {
    variable cfg
    variable customCompare
    variable legendOverride
    set gk [graphKeyForPath $path]
    if {$gk eq "" || ![graphSupportsLegend $path]} { return "Legend: not used by this plot" }

    # Public model: placement and layout are independent.  mode/orientation are
    # retained only as migration aliases for older manifests.
    set placement $cfg(plot_legend_mode)
    set loc $cfg(plot_legend_location)
    set layout $cfg(plot_legend_layout)
    set alignment $cfg(plot_legend_alignment)
    set cols $cfg(plot_legend_columns)
    set margin $cfg(plot_legend_external_margin_px)
    set fontUnit $cfg(plot_font_unit)
    set fontSize $cfg(plot_legend_font_size)
    set borderOverride ""
    set source "global"

    if {[regexp {^compare\.custom\.([0-9]+)\.} $gk -> idx]} {
        set idx [expr {int($idx)}]
        if {[info exists customCompare($idx,legend_mode)] && $customCompare($idx,legend_mode) ni {"" inherit}} { set placement $customCompare($idx,legend_mode); set source "additional plot" }
        if {[info exists customCompare($idx,legend_location)] && $customCompare($idx,legend_location) ni {"" inherit}} { set loc $customCompare($idx,legend_location); set source "additional plot" }
        if {[info exists customCompare($idx,legend_orientation)] && $customCompare($idx,legend_orientation) ni {"" inherit}} {
            set oo $customCompare($idx,legend_orientation)
            if {$oo eq "horizontal"} { set layout row } elseif {$oo eq "vertical"} { set layout stacked }
            set source "additional plot"
        }
        if {[info exists customCompare($idx,legend_border)] && $customCompare($idx,legend_border) ni {"" inherit}} { set borderOverride $customCompare($idx,legend_border); set source "additional plot" }
        if {[info exists customCompare($idx,legend_external_margin_px)] && [string trim $customCompare($idx,legend_external_margin_px)] ne ""} { set margin $customCompare($idx,legend_external_margin_px); set source "additional plot" }
    }

    if {[info exists legendOverride($gk,enabled)] && $legendOverride($gk,enabled)} {
        if {[info exists legendOverride($gk,placement)] && [string trim $legendOverride($gk,placement)] ne ""} {
            set placement $legendOverride($gk,placement)
        } elseif {[info exists legendOverride($gk,mode)] && [string trim $legendOverride($gk,mode)] ne ""} {
            set placement $legendOverride($gk,mode)
        }
        if {[info exists legendOverride($gk,location)] && [string trim $legendOverride($gk,location)] ne ""} { set loc $legendOverride($gk,location) }
        if {[info exists legendOverride($gk,alignment)] && [string trim $legendOverride($gk,alignment)] ne ""} { set alignment $legendOverride($gk,alignment) }
        if {[info exists legendOverride($gk,layout)] && [string trim $legendOverride($gk,layout)] ne ""} {
            set layout $legendOverride($gk,layout)
        } elseif {[info exists legendOverride($gk,orientation)] && [string trim $legendOverride($gk,orientation)] ne ""} {
            set oo $legendOverride($gk,orientation)
            if {$oo eq "horizontal"} { set layout row } elseif {$oo eq "vertical"} { set layout stacked }
        }
        foreach {field var} {columns cols external_margin_px margin border borderOverride font_unit fontUnit font_size fontSize} {
            if {[info exists legendOverride($gk,$field)] && [string trim $legendOverride($gk,$field)] ne ""} { set $var $legendOverride($gk,$field) }
        }
        set source "Plots-tab override"
    }
    set external [expr {$placement in {below above right left}}]
    if {$borderOverride eq ""} { set border [expr {$external ? $cfg(plot_legend_external_border) : $cfg(plot_legend_border)}] } else { set border $borderOverride }
    return "Effective legend: placement=$placement, inside=$loc, alignment=$alignment, layout=$layout, columns=$cols, font=${fontSize}${fontUnit}, dpi=$cfg(analysis_png_dpi), border=$border, margin=${margin}px ($source)"
}

proc ::GX::graphSupportsLegend_v062_legacy {path} {
    variable cfg
    variable customCompare
    set gk [graphKeyForPath $path]
    if {$gk eq ""} { return 0 }
    if {$gk eq "compare.full"} { return [expr {[string equal -nocase $cfg(plot_compare_full_layout) "overlay"]}] }
    if {$gk in {compare.normalized compare.carrier}} { return 1 }
    if {$gk eq "compare.amplitude"} { return 0 }
    if {[regexp {^compare\.custom\.([0-9]+)\.(full|normalized|carrier|amplitude)$} $gk -> idx type]} {
        set idx [expr {int($idx)}]
        if {$type eq "amplitude"} { return 0 }
        if {[info exists customCompare($idx,layout)]} {
            return [expr {[string equal -nocase $customCompare($idx,layout) "overlay"]}]
        }
        return 1
    }
    if {[regexp {^ir\..+\.(full|durations)$} $gk]} { return 1 }
    if {[regexp {^holdled\.(1|5|8|9)$} $gk]} { return 1 }
    return 0
}

proc ::GX::buildRerenderQueue_v048 {paths {allConfigured 0}} {
    variable cfg
    variable currentSession
    variable scriptDir
    if {$currentSession eq ""} { error "Open a session first." }
    if {[llength $paths] == 0} { error "No plot selected for rerendering." }
    set byDir [dict create]
    foreach p $paths {
        if {![file isfile $p]} continue
        dict lappend byDir [file dirname $p] [file tail $p]
    }
    set q {}
    set common [concat [list OMP_NUM_THREADS=$cfg(cpu_count) OPENBLAS_NUM_THREADS=$cfg(cpu_count) MKL_NUM_THREADS=$cfg(cpu_count) NUMEXPR_NUM_THREADS=$cfg(cpu_count)] [graphicsEnv] [plotEnv]]
    set octave $cfg(octave_cmd)
    dict for {dir files} $byDir {
        set rel [string range $dir [expr {[string length $currentSession]+1}] end]
        set parts [file split $rel]
        if {[llength $parts] < 2 || [lindex $parts 0] ne "analysis"} continue
        set module [lindex $parts 1]
        set cache [file join $dir render_cache.mat]
        if {![file isfile $cache]} {
            error "Module $module does not yet have a render cache in:\n$dir\n\nRecalculate the module once; subsequent runs can rerender plots without repeating the numerical analysis."
        }
        if {$module eq "CONFRONTO_STADI"} {
            if {$allConfigured} {
                set efull $cfg(plot_compare_graph_full)
                set enorm $cfg(plot_compare_graph_normalized)
                set ecar $cfg(plot_compare_graph_carrier)
                set eamp $cfg(plot_compare_graph_amplitude)
                set custom [writeCompareCustomPlotFile $dir]
            } else {
                set efull [expr {[lsearch -exact $files 01_stadi_comando_completo.png] >= 0}]
                set enorm [expr {[lsearch -exact $files 02_stadi_normalizzati.png] >= 0}]
                set ecar [expr {[lsearch -exact $files 03_stadi_portante_zoom.png] >= 0}]
                set eamp [expr {[lsearch -exact $files 04_stadi_ampiezze.png] >= 0}]
                set custom [writeCompareCustomPlotFileFiltered $dir $files]
            }
            set env2 [list GXTXT_COMPARE_GRAPH_FULL=$efull GXTXT_COMPARE_GRAPH_NORMALIZED=$enorm GXTXT_COMPARE_GRAPH_CARRIER=$ecar GXTXT_COMPARE_GRAPH_AMPLITUDE=$eamp]
            if {$custom ne ""} { lappend env2 GXTXT_COMPARE_CUSTOM_FILE=$custom }
            set script [file join $scriptDir modules GXTXT_rerender_confronto_stadi_v1.m]
            set cmd [concat [list env] $common $env2 [list $octave --quiet --no-gui $script --cache $cache --out $dir --dpi $cfg(analysis_png_dpi)]]
            lappend q [list "Rerender STAGE_COMPARISON ([llength $files] plots)" $cmd]
        } elseif {$module eq "IR"} {
            set folder [file tail $dir]
            set node [nodeNameFromFolder $folder]
            lassign [nodePlotMeta $node] nodeLabel nodeColor
            if {$allConfigured} {
                set irFull $cfg(plot_ir_graph_full); set irCarrier $cfg(plot_ir_graph_carrier)
                set irMark $cfg(plot_ir_graph_markspace); set irDur $cfg(plot_ir_graph_durations)
            } else {
                set irFull [expr {[lsearch -exact $files 01_vir_comando_completo.png] >= 0}]
                set irCarrier [expr {[lsearch -exact $files 02_vir_portante_zoom.png] >= 0}]
                set irMark [expr {[lsearch -exact $files 03_mark_space_ricostruito.png] >= 0}]
                set irDur [expr {[lsearch -exact $files 04_durate_mark_space.png] >= 0}]
            }
            set env2 [list \
                GXTXT_IR_GRAPH_FULL=$irFull \
                GXTXT_IR_GRAPH_CARRIER=$irCarrier \
                GXTXT_IR_GRAPH_MARKSPACE=$irMark \
                GXTXT_IR_GRAPH_DURATIONS=$irDur \
                GXTXT_IR_SIGNAL_LABEL=$nodeLabel GXTXT_IR_SIGNAL_COLOR=$nodeColor]
            set script [file join $scriptDir modules GXTXT_rerender_IR_v1.m]
            set cmd [concat [list env] $common $env2 [list $octave --quiet --no-gui $script --cache $cache --out $dir --dpi $cfg(analysis_png_dpi) --prefix "ir.$folder"]]
            lappend q [list "Rerender IR - $node ([llength $files] plots)" $cmd]
        } elseif {$module eq "HOLD_LED"} {
            lassign [nodePlotMeta $cfg(analysis_hold_node)] holdLabel holdColor
            lassign [nodePlotMeta $cfg(analysis_led_node)] ledLabel ledColor
            set env2 [list GXTXT_HOLD_LABEL=$holdLabel GXTXT_LED_LABEL=$ledLabel GXTXT_HOLD_COLOR=$holdColor GXTXT_LED_COLOR=$ledColor]
            for {set g 1} {$g <= 9} {incr g} {
                if {$allConfigured} {
                    set found $cfg(plot_holdled_g$g)
                } else {
                    set found 0
                    foreach fn $files { if {[string match [format "%02d_*" $g] $fn]} { set found 1; break } }
                }
                lappend env2 "GXTXT_HOLDLED_GRAPH_$g=$found"
            }
            set script [file join $scriptDir modules GXTXT_rerender_HOLD_LED_v1.m]
            set cmd [concat [list env] $common $env2 [list $octave --quiet --no-gui $script --cache $cache --out $dir --dpi $cfg(analysis_png_dpi)]]
            lappend q [list "Rerender HOLD/LED ([llength $files] plots)" $cmd]
        }
    }
    if {[llength $q] == 0} { error "The selected plots do not belong to a module that supports rerendering." }
    return $q
}

proc ::GX::currentGraphPath_before_graph_workflow {} {
    variable ui
    if {![info exists ui(graphTree)]} { return "" }
    set sel [$ui(graphTree) selection]
    if {[llength $sel] != 1} { return "" }
    set id [lindex $sel 0]
    if {![info exists ui(graphPath,$id)]} { return "" }
    return $ui(graphPath,$id)
}
proc ::GX::currentGraphPath {} { ::GX::currentGraphPath_before_graph_workflow }

proc ::GX::validatePlotSettings {} {
    variable cfg
    foreach key {plot_width_px plot_height_px} {
        if {![string is double -strict $cfg($key)] || $cfg($key) <= 0} {
            error "$key must be > 0."
        }
    }
    if {![string is integer -strict $cfg(analysis_png_dpi)] || $cfg(analysis_png_dpi) < 72 || $cfg(analysis_png_dpi) > 1200} {
        error "Output DPI must be an integer between 72 and 1200."
    }
    if {$cfg(plot_font_unit) ni {px pt}} {
        error "Font unit must be px or pt."
    }
    if {$cfg(plot_legend_font_unit) ni {inherit px pt}} {
        error "Legend font unit must be inherit, px or pt."
    }
    if {$cfg(plot_time_unit) ni {auto s ms us ns min h day}} {
        error "Plot time unit must be auto, s, ms, us, ns, min, h or day."
    }
    if {$cfg(plot_grid_mode) ni {inherit both vertical horizontal none}} {
        error "Plot grid mode must be inherit, both, vertical, horizontal or none."
    }
    if {$cfg(plot_grid_color) ne "" && ![regexp {^#[0-9A-Fa-f]{6}$} $cfg(plot_grid_color)]} {
        error "Grid color must be blank or #RRGGBB."
    }
    foreach key {plot_font_size plot_legend_font_size} {
        if {![string is double -strict $cfg($key)] || $cfg($key) <= 0} {
            error "$key must be > 0 in the selected font unit."
        }
    }
    foreach key {plot_axis_label_font_size plot_title_font_size} {
        if {$cfg($key) ne "" && (![string is double -strict $cfg($key)] || $cfg($key) <= 0)} {
            error "$key must be blank (inherit) or > 0 in the selected font unit."
        }
    }
    if {![string is double -strict $cfg(plot_line_width)] || $cfg(plot_line_width) <= 0} {
        error "Line width must be > 0."
    }
}

proc ::GX::invalidateGraphPreviewForPaths {paths} {
    variable ui
    # PNG previews are cached in memory.  file mtime has one-second resolution
    # on the Tcl path used here and a rerender can replace a PNG within the
    # same second, sometimes even with the same compressed size.  Invalidate
    # the in-memory signature explicitly whenever a source plot is rerendered.
    if {![info exists ui(graphPreviewSourcePath)]} { return }
    set cur [file normalize $ui(graphPreviewSourcePath)]
    foreach p $paths {
        if {[file normalize $p] eq $cur} {
            catch {unset ui(graphPreviewLoadSig)}
            catch {unset ui(graphPreviewFitW)}
            catch {unset ui(graphPreviewFitH)}
            return
        }
    }
}

proc ::GX::startRerenderPaths_before_clones {paths {allConfigured 0}} {
    variable currentSession
    if {[catch {validatePlotSettings} verr]} {
        tk_messageBox -icon error -title "GX-TXT - Graphics parameters" -message "Invalid graphics setting:
$verr

You do not need to save the configuration before rerendering: values currently shown in the GUI are used immediately."
        return
    }
    # Invalidate both the disk thumbnail and the in-memory preview signature.
    # Otherwise a same-second rerender can leave the old image visible.
    invalidateGraphPreviewForPaths $paths
    if {$currentSession ne ""} {
        set pdir [file join $currentSession report previews]
        foreach p $paths {
            set prev [file join $pdir "preview_[format %08x [zlib crc32 $p]].png"]
            catch {file delete -force $prev}
        }
    }
    if {[catch {set q [buildRerenderQueue $paths $allConfigured]} err]} {
        tk_messageBox -icon error -title "GX-TXT - Rerender plots" -message $err
        return
    }
    startPreparedQueue $q "Plot rerendering"
}

proc ::GX::rerenderCurrentGraph {} {
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a plot."; return }
    startRerenderPaths [list $p]
}

proc ::GX::rerenderSelectedGraphs {} {
    set paths [selectedGraphPaths]
    if {[llength $paths] == 0} { tk_messageBox -message "Select at least one plot in the Use column."; return }
    startRerenderPaths $paths
}

proc ::GX::rerenderCurrentModule {} {
    variable ui
    set p [currentGraphPath]
    if {$p eq ""} { tk_messageBox -message "Select a plot from the module."; return }
    set t $ui(graphTree); set sel [$t selection]; set id [lindex $sel 0]
    set module [lindex [$t item $id -values] 1]
    set paths {}
    foreach gid [$t children {}] {
        set vals [$t item $gid -values]
        if {[lindex $vals 1] eq $module && [info exists ui(graphPath,$gid)]} { lappend paths $ui(graphPath,$gid) }
    }
    startRerenderPaths $paths 1
}
