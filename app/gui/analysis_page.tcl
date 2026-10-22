# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildAnalysisPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Analysis tab: selezione e configurazione. L'avvio resta in Esecuzione.
    set f .top.nb.analysis
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 0 -weight 1

    ttk::notebook $f.sub
    grid $f.sub -row 0 -column 0 -sticky nsew -padx 4 -pady 4
    foreach {name text} {params "Module parameters" gfx "Server graphics" plots "Plot content" labels "Node labels/colors (global)"} {
        ttk::frame $f.sub.$name
        $f.sub add $f.sub.$name -text $text
    }

    # Parametri e selezione della sola esecuzione corrente. La presenza del modulo
    # nell'esperimento resta gestita dalla scheda Moduli.
    set a $f.sub.params
    grid columnconfigure $a 1 -weight 1
    ttk::labelframe $a.run -text "Modules to run / recalculate NOW"
    grid $a.run -row 0 -column 0 -columnspan 3 -sticky ew -padx 6 -pady 6
    ttk::label $a.run.h0 -text "Run"; ttk::label $a.run.h1 -text "Module"; ttk::label $a.run.h2 -text "Status"
    grid $a.run.h0 -row 0 -column 0 -padx 4 -pady 3; grid $a.run.h1 -row 0 -column 1 -sticky w -padx 4; grid $a.run.h2 -row 0 -column 2 -sticky w -padx 4
    set rr 1
    foreach {short label runKey} {
        ir "IR Analysis v2.4" run_analysis_ir
        identify "IR protocol identification" run_analysis_identify
        compare "Stage comparison" run_analysis_compare
        holdled "HOLD / LED v6" run_analysis_holdled
    } {
        ttk::checkbutton $a.run.c$short -variable ::GX::cfg($runKey) -command {::GX::refreshAnalysisStatus; ::GX::refreshManifestPreview}
        set ui(runCheck,$short) $a.run.c$short
        ttk::label $a.run.l$short -text $label
        ttk::label $a.run.s$short -textvariable ::GX::ui(runState,$short)
        ttk::button $a.run.o$short -text "Only this" -command [list ::GX::setRunSelections only $runKey]
        grid $a.run.c$short -row $rr -column 0 -padx 4 -pady 2
        grid $a.run.l$short -row $rr -column 1 -sticky w -padx 4 -pady 2
        grid $a.run.s$short -row $rr -column 2 -sticky w -padx 12 -pady 2
        grid $a.run.o$short -row $rr -column 3 -padx 4 -pady 2
        incr rr
    }
    ttk::frame $a.run.buttons
    ttk::button $a.run.buttons.all -text "Select all active" -command [list ::GX::setRunSelections all_active]
    ttk::button $a.run.buttons.none -text "Clear all" -command [list ::GX::setRunSelections none]
    ttk::label $a.run.buttons.note -text "Clearing a module does NOT delete existing results or plots."
    pack $a.run.buttons.all $a.run.buttons.none $a.run.buttons.note -side left -padx 4
    grid $a.run.buttons -row $rr -column 0 -columnspan 4 -sticky w -padx 4 -pady 5
    ttk::label $a.info -text "These checkboxes select modules for the next Run. The Modules tab lists enabled Analysis modules and their Run selections. Enable or disable modules in Configuration > Modules." -wraplength 900 -justify left
    grid $a.info -row 1 -column 0 -columnspan 3 -sticky ew -padx 6 -pady 6
    set row 2
    foreach {label key} {
        "IR nodes to analyze (comma-separated)" analysis_ir_nodes
        "HOLD node" analysis_hold_node
        "N_LED node" analysis_led_node
        "Nominal carrier [Hz]" analysis_nominal_carrier_hz
        "IR cluster span guard [0/1]" analysis_ir_cluster_guard
        "IR cluster max/min ratio" analysis_ir_cluster_max_ratio
        "Plot DPI" analysis_png_dpi
        "HOLD/LED pulse count" holdled_num_impulses
        "LED current resistor R_LED [ohm]" holdled_rled_ohm
        "HOLD discharge resistance [ohm]" holdled_rdischarge_ohm
        "VGEN HOLD/LED [V, blank=NaN]" holdled_vgen_v
        "Duty HOLD/LED [%]" holdled_duty_pct
        "IPD HOLD/LED [uA, blank=NaN]" holdled_ipd_ua
    } {
        addLabeledEntry $a $row $label ::GX::cfg($key) 46
        incr row
    }
    ttk::label $a.vl -text "Analysis verbosity"
    ttk::combobox $a.v -textvariable ::GX::cfg(analysis_verbosity) -values {0 1 2 3} -state readonly -width 8
    grid $a.vl -row $row -column 0 -sticky e -padx 5 -pady 3
    grid $a.v -row $row -column 1 -sticky w -padx 5 -pady 3

    # Grafica server + stile global
    set a $f.sub.gfx
    grid columnconfigure $a 1 -weight 1
    ttk::labelframe $a.server -text "Octave graphics backend"
    grid $a.server -row 0 -column 0 -columnspan 4 -sticky ew -padx 6 -pady 6
    ttk::label $a.server.ml -text "Mode"
    ttk::combobox $a.server.m -textvariable ::GX::cfg(graphics_mode) -values {headless x11 auto} -state readonly -width 14
    ttk::label $a.server.tl -text "Toolkit"
    ttk::combobox $a.server.t -textvariable ::GX::cfg(graphics_toolkit) -values {auto gnuplot qt fltk} -state readonly -width 14
    ttk::label $a.server.dl -text "DISPLAY X11"
    ttk::entry $a.server.d -textvariable ::GX::cfg(graphics_display) -width 28
    ttk::button $a.server.dc -text "Use current DISPLAY" -command ::GX::useCurrentDisplay
    ttk::checkbutton $a.server.vis -text "Visible figures" -variable ::GX::cfg(graphics_visible)
    grid $a.server.ml -row 0 -column 0 -sticky e -padx 4 -pady 3
    grid $a.server.m  -row 0 -column 1 -sticky w -padx 4 -pady 3
    grid $a.server.tl -row 0 -column 2 -sticky e -padx 4 -pady 3
    grid $a.server.t  -row 0 -column 3 -sticky w -padx 4 -pady 3
    grid $a.server.dl -row 1 -column 0 -sticky e -padx 4 -pady 3
    grid $a.server.d  -row 1 -column 1 -sticky ew -padx 4 -pady 3
    grid $a.server.dc -row 1 -column 2 -sticky w -padx 4 -pady 3
    grid $a.server.vis -row 1 -column 3 -sticky w -padx 4 -pady 3
    grid columnconfigure $a.server 1 -weight 1

    ttk::labelframe $a.style -text "Global plot style"
    grid $a.style -row 1 -column 0 -columnspan 4 -sticky ew -padx 6 -pady 6
    set sr 0
    foreach {label key width} {
        "Width X [px]" plot_width_px 12
        "Height Y [px]" plot_height_px 12
        "Output DPI" analysis_png_dpi 12
        "Axis tick font" plot_font_size 12
        "Line width" plot_line_width 12
        "Legend font size" plot_legend_font_size 12
        "Background (#RRGGBB)" plot_background 14
    } {
        ttk::label $a.style.l$sr -text $label
        ttk::entry $a.style.e$sr -textvariable ::GX::cfg($key) -width $width
        grid $a.style.l$sr -row $sr -column 0 -sticky e -padx 4 -pady 3
        grid $a.style.e$sr -row $sr -column 1 -sticky w -padx 4 -pady 3
        incr sr
    }
    ttk::label $a.style.axisfl -text {Axis-label font}
    ttk::entry $a.style.axisf -textvariable ::GX::cfg(plot_axis_label_font_size) -width 12
    ttk::label $a.style.titlefl -text {Title font}
    ttk::entry $a.style.titlef -textvariable ::GX::cfg(plot_title_font_size) -width 12
    grid $a.style.axisfl -row $sr -column 0 -sticky e -padx 4 -pady 3
    grid $a.style.axisf  -row $sr -column 1 -sticky w -padx 4 -pady 3
    incr sr
    grid $a.style.titlefl -row $sr -column 0 -sticky e -padx 4 -pady 3
    grid $a.style.titlef  -row $sr -column 1 -sticky w -padx 4 -pady 3
    incr sr
    ttk::label $a.style.fontul -text "Default font unit"
    ttk::combobox $a.style.fontu -textvariable ::GX::cfg(plot_font_unit) -values {px pt} -state readonly -width 8
    set ui(plotFontUnitLast) $cfg(plot_font_unit)
    bind $a.style.fontu <<ComboboxSelected>> {::GX::plotFontUnitChanged}
    grid $a.style.fontul -row $sr -column 0 -sticky e -padx 4 -pady 3
    grid $a.style.fontu  -row $sr -column 1 -sticky w -padx 4 -pady 3
    incr sr
    ttk::label $a.style.legendful -text "Legend font unit"
    ttk::combobox $a.style.legendfu -textvariable ::GX::cfg(plot_legend_font_unit) -values {inherit px pt} -state readonly -width 8
    set ui(plotLegendFontUnitLast) $cfg(plot_legend_font_unit)
    bind $a.style.legendfu <<ComboboxSelected>> {::GX::legendFontUnitChanged}
    grid $a.style.legendful -row $sr -column 0 -sticky e -padx 4 -pady 3
    grid $a.style.legendfu  -row $sr -column 1 -sticky w -padx 4 -pady 3
    incr sr
    ttk::label $a.style.timeul -text "Default time unit"
    ttk::combobox $a.style.timeu -textvariable ::GX::cfg(plot_time_unit) -values {auto s ms us ns min h day} -state readonly -width 8
    grid $a.style.timeul -row $sr -column 0 -sticky e -padx 4 -pady 3
    grid $a.style.timeu  -row $sr -column 1 -sticky w -padx 4 -pady 3
    ttk::label $a.style.gridml -text "Default grid mode"
    ttk::combobox $a.style.gridm -textvariable ::GX::cfg(plot_grid_mode) -values {both vertical horizontal none} -state readonly -width 12
    grid $a.style.gridml -row 0 -column 2 -sticky e -padx 4
    grid $a.style.gridm -row 0 -column 3 -sticky w -padx 4
    ttk::label $a.style.gridcl -text "Grid color"
    ttk::entry $a.style.gridc -textvariable ::GX::cfg(plot_grid_color) -width 14
    ttk::button $a.style.gridcb -text "Choose..." -command [list ::GX::chooseConfigColor plot_grid_color "Grid color"]
    grid $a.style.gridcl -row 1 -column 2 -sticky e -padx 4 -pady 3
    grid $a.style.gridc -row 1 -column 3 -sticky w -padx 4 -pady 3
    grid $a.style.gridcb -row 1 -column 4 -sticky w -padx 3 -pady 3
    ttk::label $a.style.lm -text "Legend placement"
    ttk::combobox $a.style.mode -textvariable ::GX::cfg(plot_legend_mode) -values {none inside below above right left manual} -state readonly -width 12
    ttk::label $a.style.ll -text "Inside preset"
    ttk::combobox $a.style.loc -textvariable ::GX::cfg(plot_legend_location) -values {north northeast east southeast south southwest west northwest} -state readonly -width 12
    ttk::label $a.style.layl -text "Legend layout"
    ttk::combobox $a.style.layout -textvariable ::GX::cfg(plot_legend_layout) -values {auto row stacked wrapped} -state readonly -width 12
    ttk::label $a.style.alignl -text "External alignment"
    ttk::combobox $a.style.align -textvariable ::GX::cfg(plot_legend_alignment) -values {start center end} -state readonly -width 12
    ttk::label $a.style.lc -text "Wrapped columns"
    ttk::spinbox $a.style.cols -from 1 -to 64 -textvariable ::GX::cfg(plot_legend_columns) -width 6
    ttk::label $a.style.lb -text "Legend background"
    ttk::entry $a.style.bg -textvariable ::GX::cfg(plot_legend_background) -width 14
    ttk::checkbutton $a.style.border -text "Border" -variable ::GX::cfg(plot_legend_border)
    ttk::label $a.style.le -text "Border color"
    ttk::entry $a.style.edge -textvariable ::GX::cfg(plot_legend_border_color) -width 14
    grid $a.style.lm -row 1 -column 2 -sticky e -padx 4; grid $a.style.mode -row 1 -column 3 -sticky w -padx 4
    grid $a.style.ll -row 2 -column 2 -sticky e -padx 4; grid $a.style.loc -row 2 -column 3 -sticky w -padx 4
    grid $a.style.layl -row 3 -column 2 -sticky e -padx 4; grid $a.style.layout -row 3 -column 3 -sticky w -padx 4
    grid $a.style.alignl -row 4 -column 2 -sticky e -padx 4; grid $a.style.align -row 4 -column 3 -sticky w -padx 4
    grid $a.style.lc -row 5 -column 2 -sticky e -padx 4; grid $a.style.cols -row 5 -column 3 -sticky w -padx 4
    grid $a.style.lb -row 6 -column 2 -sticky e -padx 4; grid $a.style.bg -row 6 -column 3 -sticky w -padx 4
    grid $a.style.border -row 7 -column 2 -sticky e -padx 4; grid $a.style.le -row 7 -column 3 -sticky e -padx 4; grid $a.style.edge -row 7 -column 4 -sticky w -padx 4
    ttk::checkbutton $a.style.extborder -text "External legend border" -variable ::GX::cfg(plot_legend_external_border)
    ttk::label $a.style.extmarginl -text {Legend/plot distance [px]}
    ttk::spinbox $a.style.extmargin -from 0 -to 100 -increment 1 -textvariable ::GX::cfg(plot_legend_external_margin_px) -width 7
    grid $a.style.extborder -row 8 -column 2 -sticky e -padx 4 -pady 3
    grid $a.style.extmarginl -row 8 -column 3 -sticky e -padx 4 -pady 3
    grid $a.style.extmargin -row 8 -column 4 -sticky w -padx 4 -pady 3
    ttk::label $a.note -text "APPLICATION: values shown here are used directly by the next Rerender; saving first is NOT required. PERSISTENCE: Save Config only stores them in the manifest. DPI: Output DPI is a global graphics setting used by every native plot. FONT UNITS: px = size referenced to the final PNG; pt = typographic points. Default font unit controls ordinary plot text. Legend font unit may inherit that default or explicitly use px/pt. A plot-specific legend can inherit again or override px/pt locally. LEGEND: placement and layout are independent (for example below+row or right+stacked). GRID: both = X+Y lines; vertical = X-axis grid lines; horizontal = Y-axis grid lines; none = no grid. X/Y tick steps control grid spacing. Plot and stacked-panel overrides may inherit these global settings. Axis-label and title fonts: blank = inherit. Open server PNG 1:1 reads the file directly from the session." -wraplength 1450 -justify left
    grid $a.note -row 11 -column 0 -columnspan 6 -sticky ew -padx 8 -pady 5

    # Contenuto dei grafici
    set a $f.sub.plots
    grid columnconfigure $a 0 -weight 1
    grid rowconfigure $a 0 -weight 1
    ttk::notebook $a.pn
    grid $a.pn -row 0 -column 0 -sticky nsew -padx 4 -pady 4
    foreach {n t} {comp "Stage comparison" ir "IR v2.4" hl "HOLD / LED v6"} {
        ttk::frame $a.pn.$n
        $a.pn add $a.pn.$n -text $t
    }
    set pc $a.pn.comp
    set pi $a.pn.ir
    set ph $a.pn.hl
    grid columnconfigure $pi 1 -weight 1

    # Stage comparison: i quattro grafici storici restano invariati; gli aggiuntivi sono arbitrari.
    grid columnconfigure $pc 0 -weight 1
    grid rowconfigure $pc 0 -weight 1
    ttk::notebook $pc.cn
    grid $pc.cn -row 0 -column 0 -sticky nsew
    ttk::frame $pc.cn.defaults
    ttk::frame $pc.cn.extra
    $pc.cn add $pc.cn.defaults -text "Defaults"
    $pc.cn add $pc.cn.extra -text "Additional plots"
    set pd $pc.cn.defaults
    set pe $pc.cn.extra
    grid columnconfigure $pd 1 -weight 1

    ttk::checkbutton $pd.g1 -text "Full command" -variable ::GX::cfg(plot_compare_graph_full)
    ttk::checkbutton $pd.g2 -text "Normalized comparison" -variable ::GX::cfg(plot_compare_graph_normalized)
    ttk::checkbutton $pd.g3 -text "Carrier zoom" -variable ::GX::cfg(plot_compare_graph_carrier)
    ttk::checkbutton $pd.g4 -text "Ampiezze" -variable ::GX::cfg(plot_compare_graph_amplitude)
    grid $pd.g1 -row 0 -column 0 -sticky w -padx 4; grid $pd.g2 -row 0 -column 1 -sticky w -padx 4
    grid $pd.g3 -row 0 -column 2 -sticky w -padx 4; grid $pd.g4 -row 0 -column 3 -sticky w -padx 4
    ttk::label $pd.fl -text "Full-command layout"
    ttk::combobox $pd.fm -textvariable ::GX::cfg(plot_compare_full_layout) -values {stacked overlay} -state readonly -width 12
    grid $pd.fl -row 1 -column 0 -sticky e -padx 4 -pady 3; grid $pd.fm -row 1 -column 1 -sticky w -padx 4 -pady 3

    ttk::labelframe $pd.stack -text "Stacked layout / vertically aligned panels"
    grid $pd.stack -row 2 -column 0 -columnspan 4 -sticky ew -padx 4 -pady {4 7}
    ttk::checkbutton $pd.stack.shared -text "Shared X axis" -variable ::GX::cfg(plot_stacked_shared_x)
    ttk::checkbutton $pd.stack.bottom -text "X values/ticks only on bottom panel" -variable ::GX::cfg(plot_stacked_bottom_xticks_only)
    ttk::label $pd.stack.gl -text "Stacked grid"
    ttk::combobox $pd.stack.grid -textvariable ::GX::cfg(plot_stacked_grid_mode) -values {inherit both vertical horizontal none} -state readonly -width 12
    grid $pd.stack.shared -row 0 -column 0 -sticky w -padx 5 -pady 3
    grid $pd.stack.bottom -row 0 -column 1 -sticky w -padx 5 -pady 3
    grid $pd.stack.gl -row 0 -column 2 -sticky e -padx 5 -pady 3
    grid $pd.stack.grid -row 0 -column 3 -sticky w -padx 5 -pady 3
    foreach {c label key} {
        0 "Left margin [%]" plot_stacked_margin_left_pct
        1 "Right margin [%]" plot_stacked_margin_right_pct
        2 "Top margin [%]" plot_stacked_margin_top_pct
        3 "Bottom margin [%]" plot_stacked_margin_bottom_pct
        4 "Panel gap [%]" plot_stacked_gap_pct
    } {
        ttk::label $pd.stack.ml$c -text $label
        ttk::spinbox $pd.stack.me$c -from 0 -to 30 -increment 0.5 -textvariable ::GX::cfg($key) -width 7
        grid $pd.stack.ml$c -row 1 -column [expr {$c*2}] -sticky e -padx {5 2} -pady 3
        grid $pd.stack.me$c -row 1 -column [expr {$c*2+1}] -sticky w -padx {2 5} -pady 3
    }
    ttk::checkbutton $pd.stack.ylalign -text "Allinea tutte le label Y" -variable ::GX::cfg(plot_stacked_align_ylabels)
    ttk::label $pd.stack.yxl -text "Y-label X position (normalized axes)"
    ttk::spinbox $pd.stack.yx -from -0.50 -to 0.20 -increment 0.005 -textvariable ::GX::cfg(plot_stacked_ylabel_x) -width 8
    grid $pd.stack.ylalign -row 2 -column 0 -columnspan 2 -sticky w -padx 5 -pady 3
    grid $pd.stack.yxl -row 2 -column 2 -columnspan 2 -sticky e -padx 5 -pady 3
    grid $pd.stack.yx -row 2 -column 4 -sticky w -padx 5 -pady 3
    ttk::label $pd.stack.note -text "These are the automatic defaults for stacked plots. Y-label X position uses normalized axis coordinates: 0 is the left edge of the axes area; negative values move the label left, while values closer to 0 move it toward the axis (for example -0.04 / -0.05). After reviewing the result, use Axes / grid... in the Plots tab to override limits, tick step/format, grid, and label position for an individual plot or panel." -wraplength 1150 -justify left
    grid $pd.stack.note -row 3 -column 0 -columnspan 10 -sticky ew -padx 5 -pady {2 4}
    set cr 4
    foreach {label key} {
        "Nodes - full command" plot_compare_full_nodes
        "Nodes - normalized" plot_compare_normalized_nodes
        "Nodes - carrier zoom" plot_compare_carrier_nodes
        "Nodes - amplitudes" plot_compare_amplitude_nodes
        "Title - full command" plot_compare_full_title
        "Title - normalized" plot_compare_normalized_title
        "Title - carrier zoom" plot_compare_carrier_title
        "Title - amplitudes" plot_compare_amplitude_title
        "X label - full command" plot_compare_full_xlabel
        "Y label - full overlay" plot_compare_full_ylabel
        "Y label - stacked ({NODE})" plot_compare_full_ylabel_template
        "X label - normalizzato" plot_compare_normalized_xlabel
        "Y label - normalizzato" plot_compare_normalized_ylabel
        "X label - carrier" plot_compare_carrier_xlabel
        "Y label - carrier" plot_compare_carrier_ylabel
        "Y label - amplitudes" plot_compare_amplitude_ylabel
    } {
        ttk::label $pd.l$cr -text $label
        ttk::entry $pd.e$cr -textvariable ::GX::cfg($key) -width 62
        grid $pd.l$cr -row $cr -column 0 -sticky e -padx 4 -pady 2
        grid $pd.e$cr -row $cr -column 1 -columnspan 3 -sticky ew -padx 4 -pady 2
        incr cr
    }
    grid columnconfigure $pd 1 -weight 1

    grid columnconfigure $pe 0 -weight 1
    grid rowconfigure $pe 2 -weight 1
    ttk::label $pe.info -text "Add as many plots as needed. Each plot may contain one curve or any combination of available nodes; if no additional plots are added, the default behavior is unchanged." -wraplength 900 -justify left
    grid $pe.info -row 0 -column 0 -sticky ew -padx 6 -pady 6
    ttk::frame $pe.b
    ttk::button $pe.b.add -text "Add..." -command ::GX::customCompareAdd
    ttk::button $pe.b.edit -text "Edit..." -command ::GX::customCompareEdit
    ttk::button $pe.b.dup -text "Duplicate" -command ::GX::customCompareDuplicate
    ttk::button $pe.b.del -text "Delete" -command ::GX::customCompareDelete
    ttk::button $pe.b.up -text "Up" -command [list ::GX::customCompareMove -1]
    ttk::button $pe.b.down -text "Down" -command [list ::GX::customCompareMove 1]
    pack $pe.b.add $pe.b.edit $pe.b.dup $pe.b.del $pe.b.up $pe.b.down -side left -padx 3
    grid $pe.b -row 1 -column 0 -sticky w -padx 5 -pady 4
    ttk::treeview $pe.tree -columns {enabled type layout legend nodes title} -show headings -selectmode browse
    foreach {c title width} {enabled "Use" 45 type "Type" 130 layout "Layout" 75 legend "Legend" 105 nodes "Curves / nodes" 260 title "Title" 300} {
        $pe.tree heading $c -text $title; $pe.tree column $c -width $width
    }
    ttk::scrollbar $pe.sy -orient vertical -command [list $pe.tree yview]
    $pe.tree configure -yscrollcommand [list $pe.sy set]
    grid $pe.tree -row 2 -column 0 -sticky nsew -padx {5 0} -pady 5
    grid $pe.sy -row 2 -column 0 -sticky nse -pady 5
    set ui(customCompareTree) $pe.tree
    bind $pe.tree <Double-1> {::GX::customCompareEdit}

    ttk::checkbutton $pi.g1 -text "Full command" -variable ::GX::cfg(plot_ir_graph_full)
    ttk::checkbutton $pi.g2 -text "Carrier" -variable ::GX::cfg(plot_ir_graph_carrier)
    ttk::checkbutton $pi.g3 -text "MARK/SPACE" -variable ::GX::cfg(plot_ir_graph_markspace)
    ttk::checkbutton $pi.g4 -text "Durations" -variable ::GX::cfg(plot_ir_graph_durations)
    grid $pi.g1 -row 0 -column 0 -sticky w -padx 4; grid $pi.g2 -row 0 -column 1 -sticky w -padx 4
    grid $pi.g3 -row 0 -column 2 -sticky w -padx 4; grid $pi.g4 -row 0 -column 3 -sticky w -padx 4
    set rr 1
    foreach {label key} {
        "Full title ({NODE})" plot_ir_full_title
        "Carrier title ({NODE})" plot_ir_carrier_title
        "MARK/SPACE title ({NODE})" plot_ir_markspace_title
        "Durations title ({NODE})" plot_ir_durations_title
        "Voltage Y label ({NODE})" plot_ir_voltage_ylabel
        "Full X label" plot_ir_full_xlabel
        "Carrier X label" plot_ir_carrier_xlabel
        "X label MARK/SPACE" plot_ir_markspace_xlabel
        "Y label MARK/SPACE" plot_ir_markspace_ylabel
        "X label durations" plot_ir_durations_xlabel
        "Y label durations" plot_ir_durations_ylabel
    } {
        ttk::label $pi.l$rr -text $label
        ttk::entry $pi.e$rr -textvariable ::GX::cfg($key) -width 62
        grid $pi.l$rr -row $rr -column 0 -sticky e -padx 4 -pady 2
        grid $pi.e$rr -row $rr -column 1 -columnspan 3 -sticky ew -padx 4 -pady 2
        incr rr
    }
    grid columnconfigure $pi 1 -weight 1

    set namesHL {"1 HOLD + fit" "2 Full N_LED" "3 LED turn-on" "4 LED current" "5 LED derivative" "6 HOLD charge" "7 HOLD charge derivative" "8 HOLD discharge derivative" "9 I_LED vs HOLD"}
    for {set i 1} {$i <= 9} {incr i} {
        ttk::checkbutton $ph.g$i -text [lindex $namesHL [expr {$i-1}]] -variable ::GX::cfg(plot_holdled_g$i)
        grid $ph.g$i -row [expr {($i-1)/3}] -column [expr {($i-1)%3}] -sticky w -padx 5 -pady 2
    }

    # Label e colori dei nodi: metadati GLOBALI della sessione grafica, non di un
    # singolo modulo. Tutti i moduli che usano lo stesso nodo ereditano alias e colore.
    set a $f.sub.labels
    # Mantiene la tabella leggibile anche su monitor molto larghi: i campi hanno
    # una larghezza utile, lo spazio residuo rimane a destra invece di deformarli.
    grid columnconfigure $a 5 -weight 1
    ttk::labelframe $a.scope -text "Scope of these settings"
    ttk::label $a.scope.txt -text "GLOBAL FOR THE SESSION: aliases and base colors are associated with logical nodes and are used by every module/plot that displays that node. They do not depend on the selected module." -wraplength 1100 -justify left
    pack $a.scope.txt -fill x -padx 8 -pady 6
    grid $a.scope -row 0 -column 0 -columnspan 6 -sticky ew -padx 6 -pady 6
    ttk::label $a.h0 -text "Channel"
    ttk::label $a.h1 -text "Logical node"
    ttk::label $a.h2 -text "Alias shown in plots"
    ttk::label $a.h3 -text "Base color (#RRGGBB, blank=auto)"
    grid $a.h0 -row 1 -column 0 -padx 4 -pady 4; grid $a.h1 -row 1 -column 1 -padx 4 -pady 4
    grid $a.h2 -row 1 -column 2 -padx 4 -pady 4 -sticky w; grid $a.h3 -row 1 -column 3 -padx 4 -pady 4
    for {set i 1} {$i <= 8} {incr i} {
        ttk::label $a.c$i -text "C$i"
        ttk::label $a.n$i -textvariable ::GX::ch($i,name)
        ttk::entry $a.l$i -textvariable ::GX::ch($i,plot_label) -width 48
        ttk::entry $a.e$i -textvariable ::GX::ch($i,plot_color) -width 16
        ttk::button $a.b$i -text "Choose..." -command [list ::GX::chooseChannelColor $i]
        grid $a.c$i -row [expr {$i+1}] -column 0 -padx 4 -pady 3
        grid $a.n$i -row [expr {$i+1}] -column 1 -sticky w -padx 4 -pady 3
        grid $a.l$i -row [expr {$i+1}] -column 2 -sticky w -padx 4 -pady 3
        grid $a.e$i -row [expr {$i+1}] -column 3 -padx 4 -pady 3
        grid $a.b$i -row [expr {$i+1}] -column 4 -padx 4 -pady 3
    }
    ttk::label $a.note -text "These settings are global per node within the session. Labels are literal text: underscores and other characters are not interpreted as TeX. Blank colors let Octave choose automatically." -wraplength 900 -justify left
    grid $a.note -row 11 -column 0 -columnspan 6 -sticky ew -padx 6 -pady 8

    ttk::frame $f.bottom
    ttk::button $f.bottom.refresh -text "Refresh compatibility" -command ::GX::refreshAnalysisStatus
    ttk::label $f.bottom.note -text "To run: use the Run tab -> PHASE 2 or PHASE 1 + PHASE 2."
    pack $f.bottom.refresh $f.bottom.note -side left -padx 4
    grid $f.bottom -row 1 -column 0 -sticky ew -padx 5 -pady 3
    text $f.status -wrap word -height 6 -font TkFixedFont -state disabled
    grid $f.status -row 2 -column 0 -sticky ew -padx 5 -pady 4
    set ui(analysisStatus) $f.status

}
