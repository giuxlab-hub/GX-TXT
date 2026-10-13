# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::loadModuleCatalog {} {
    variable moduleCatalog
    variable moduleOrder
    variable scriptDir
    array unset moduleCatalog *
    set moduleOrder {}
    set path [file join $scriptDir modules module_catalog.ini]
    if {![file isfile $path]} { error "Module catalog missing: $path" }
    set d [parseIni $path]
    set aliases {}
    foreach k [dict keys $d] {
        if {[regexp {^module\.([^.]+)\.(.+)$} $k -> alias field]} {
            if {[lsearch -exact $aliases $alias] < 0} { lappend aliases $alias }
        }
    }
    set sortable {}
    foreach alias $aliases {
        set prefix "module.$alias."
        if {![dict exists $d "${prefix}id"]} continue
        set id [string trim [dict get $d "${prefix}id"]]
        if {$id eq ""} continue
        foreach {field def} {
            kind analysis group General name "" version "" selectable 1 enabled_key "" runner "" order 1000 depends "" description "" inputs "" outputs "" graphs "" config_hint ""
        } {
            set key "${prefix}$field"
            if {[dict exists $d $key]} { set moduleCatalog($id,$field) [dict get $d $key] } else { set moduleCatalog($id,$field) $def }
        }
        if {$moduleCatalog($id,name) eq ""} { set moduleCatalog($id,name) $id }
        set ord $moduleCatalog($id,order)
        if {![string is integer -strict $ord]} { set ord 1000 }
        lappend sortable [list $ord $id]
    }
    foreach pair [lsort -integer -index 0 $sortable] { lappend moduleOrder [lindex $pair 1] }
}

proc ::GX::moduleField {id field {default ""}} {
    variable moduleCatalog
    if {[info exists moduleCatalog($id,$field)]} { return $moduleCatalog($id,$field) }
    return $default
}

proc ::GX::moduleKindLabel {kind} {
    switch -- [string tolower $kind] {
        acquisition { return "Acquisition" }
        analysis { return "Analysis" }
        automation { return "Measurement automation" }
        default { return $kind }
    }
}

proc ::GX::moduleIsEnabled {id} {
    variable cfg
    set selectable [moduleField $id selectable 1]
    set key [moduleField $id enabled_key ""]
    if {!$selectable || $key eq ""} { return 1 }
    if {![info exists cfg($key)]} { return 0 }
    return [expr {$cfg($key) ? 1 : 0}]
}

proc ::GX::selectedModuleIds {} {
    variable moduleOrder
    set out {}
    foreach id $moduleOrder {
        if {![moduleField $id selectable 1]} continue
        if {[moduleIsEnabled $id]} { lappend out $id }
    }
    return $out
}

proc ::GX::moduleSetEnabled {id state {cascade 1}} {
    variable cfg
    variable moduleOrder
    set key [moduleField $id enabled_key ""]
    if {![moduleField $id selectable 1] || $key eq ""} { return }
    set cfg($key) [expr {$state ? 1 : 0}]
    set runKey "run_$key"
    if {[info exists cfg($runKey)]} { set cfg($runKey) [expr {$state ? 1 : 0}] }
    if {$state} {
        foreach dep [split [string map [list ";" ","] [moduleField $id depends ""]] ","] {
            set dep [string trim $dep]
            if {$dep ne ""} { moduleSetEnabled $dep 1 0 }
        }
    } elseif {$cascade} {
        foreach other $moduleOrder {
            foreach dep [split [string map [list ";" ","] [moduleField $other depends ""]] ","] {
                if {[string trim $dep] eq $id && [moduleIsEnabled $other]} { moduleSetEnabled $other 0 0 }
            }
        }
    }
}

proc ::GX::applyModuleSelection {raw} {
    variable moduleOrder
    foreach id $moduleOrder {
        if {[moduleField $id selectable 1]} { moduleSetEnabled $id 0 0 }
    }
    foreach id [split [string map [list ";" ","] $raw] ","] {
        set id [string trim $id]
        if {$id ne "" && [lsearch -exact $moduleOrder $id] >= 0} { moduleSetEnabled $id 1 0 }
    }
    foreach id $moduleOrder { if {[moduleIsEnabled $id]} { moduleSetEnabled $id 1 0 } }
}

proc ::GX::moduleHelpText_v083_before_documentation_api {id} {
    set kind [moduleKindLabel [moduleField $id kind]]
    set group [moduleField $id group]
    set name [moduleField $id name]
    set ver [moduleField $id version]
    set dep [string trim [moduleField $id depends]]
    if {[moduleIsAlwaysAvailable $id]} {
        set st [expr {[moduleIsCore $id] ? "CORE / ALWAYS" : "ALWAYS"}]
    } elseif {[moduleIsCore $id]} {
        set st [expr {[moduleIsEnabled $id] ? "CORE / active" : "CORE / inactive"}]
    } elseif {![moduleField $id selectable 1]} {
        set st "always available"
    } else {
        set st [expr {[moduleIsEnabled $id] ? "active" : "inactive"}]
    }
    set out "$name"
    if {$ver ne ""} { append out "  (v$ver)" }
    append out "\nID stabile: $id\nTipo: $kind\nGruppo: $group\nStatus: $st\n\n"
    append out "COSA FA\n[moduleField $id description]\n\n"
    append out "INPUTS\n[moduleField $id inputs]\n\n"
    append out "RESULTS / OUTPUT\n[moduleField $id outputs]\n\n"
    append out "PLOTS\n[moduleField $id graphs]\n\n"
    if {$dep ne ""} { append out "DIPENDENZE\n$dep\n\n" }
    append out "CONFIGURAZIONE\n[moduleField $id config_hint]\n"
    return $out
}

# The base help formatter is available before later CORE extensions load.
proc ::GX::moduleHelpText {id} {
    return [::GX::moduleHelpText_v083_before_documentation_api $id]
}

proc ::GX::loadManifest_v048 {path} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable customCompare
    variable customCompareCount
    variable legendOverride
    variable axisOverride
    # Un manifest è una configurazione completa: partire dai default evita
    # che campi assenti in manifest più vecchi ereditino valori della GUI corrente.
    defaults
    set d [parseIni $path]

    # I percorsi/eseguibili del runtime sono registrati nel manifest per
    # tracciabilita, ma NON vengono ripristinati quando si carica un manifest.
    # In questo modo un manifest creato con una versione precedente non puo
    # retrocedere silenziosamente il worker Octave alla vecchia release.
    foreach key {output_root session_name link_raw copy_raw} {
        if {[dict exists $d "runtime.$key"]} { set cfg($key) [dict get $d "runtime.$key"] }
    }
    foreach key {cpu_count chunk_rows preview_lines raw_fields drop_trailing_fields strict_sequence} {
        if {[dict exists $d "processing.$key"]} { set cfg($key) [dict get $d "processing.$key"] }
    }

    foreach key {input_csv parser delimiter header_lines sequence_col time_col manual_tstart manual_dt make_rigol_split make_canonical_split} {
        if {[dict exists $d "acquisition.$key"]} { set cfg($key) [dict get $d "acquisition.$key"] }
    }
    foreach key {project board test date remote button distance_cm p_gain_ohm p_sens_ohm supply_v experiment_notes} {
        if {[dict exists $d "experiment.$key"]} { set cfg($key) [dict get $d "experiment.$key"] }
    }
    foreach key {manufacturer model serial firmware memory_depth sample_rate bandwidth_limit coupling notes} {
        if {[dict exists $d "oscilloscope.$key"]} { set cfg(scope_$key) [dict get $d "oscilloscope.$key"] }
    }
    foreach key {analysis_ir analysis_identify analysis_compare analysis_holdled analysis_ir_nodes analysis_hold_node analysis_led_node analysis_verbosity analysis_nominal_carrier_hz analysis_ir_cluster_guard analysis_ir_cluster_max_ratio analysis_png_dpi graphics_mode graphics_toolkit graphics_display graphics_visible holdled_num_impulses holdled_vgen_v holdled_duty_pct holdled_ipd_ua holdled_mode holdled_trigger_reference holdled_rled_ohm holdled_rdischarge_ohm} {
        if {[dict exists $d "analysis.$key"]} { set cfg($key) [dict get $d "analysis.$key"] }
    }
    # v0.3.3: se presente, la selezione tramite ID stabili prevale sui flag legacy.
    # I manifest <=0.3.2 continuano a funzionare usando esclusivamente [analysis].
    if {[dict exists $d "modules.selected"]} {
        applyModuleSelection [dict get $d "modules.selected"]
    }
    foreach key {run_analysis_ir run_analysis_identify run_analysis_compare run_analysis_holdled} {
        if {[dict exists $d "execution.$key"]} { set cfg($key) [dict get $d "execution.$key"] }
    }
    # Manifest precedenti: la coda di esecuzione segue inizialmente i moduli attivi.
    if {![dict exists $d "execution.run_analysis_ir"]} {
        set cfg(run_analysis_ir) $cfg(analysis_ir)
        set cfg(run_analysis_identify) $cfg(analysis_identify)
        set cfg(run_analysis_compare) $cfg(analysis_compare)
        set cfg(run_analysis_holdled) $cfg(analysis_holdled)
    }
    foreach key {plot_width_px plot_height_px plot_font_unit plot_font_size plot_axis_label_font_size plot_title_font_size plot_line_width plot_grid plot_grid_mode plot_grid_color plot_time_unit plot_stacked_shared_x plot_stacked_bottom_xticks_only plot_stacked_grid_mode plot_stacked_margin_left_pct plot_stacked_margin_right_pct plot_stacked_margin_top_pct plot_stacked_margin_bottom_pct plot_stacked_gap_pct plot_stacked_align_ylabels plot_stacked_ylabel_x plot_legend_mode plot_legend_location plot_legend_font_unit plot_legend_font_size plot_legend_orientation plot_legend_layout plot_legend_alignment plot_legend_columns plot_legend_background plot_legend_border plot_legend_external_border plot_legend_border_color plot_legend_external_margin_px plot_legend_manual_x plot_legend_manual_y plot_background plot_compare_graph_full plot_compare_graph_normalized plot_compare_graph_carrier plot_compare_graph_amplitude plot_compare_full_layout plot_compare_full_nodes plot_compare_normalized_nodes plot_compare_carrier_nodes plot_compare_amplitude_nodes plot_compare_full_title plot_compare_normalized_title plot_compare_carrier_title plot_compare_amplitude_title plot_compare_full_xlabel plot_compare_full_ylabel plot_compare_full_ylabel_template plot_compare_normalized_xlabel plot_compare_normalized_ylabel plot_compare_carrier_xlabel plot_compare_carrier_ylabel plot_compare_amplitude_ylabel plot_ir_graph_full plot_ir_graph_carrier plot_ir_graph_markspace plot_ir_graph_durations plot_ir_full_title plot_ir_carrier_title plot_ir_markspace_title plot_ir_durations_title plot_ir_voltage_ylabel plot_ir_full_xlabel plot_ir_carrier_xlabel plot_ir_markspace_xlabel plot_ir_markspace_ylabel plot_ir_durations_xlabel plot_ir_durations_ylabel plot_holdled_g1 plot_holdled_g2 plot_holdled_g3 plot_holdled_g4 plot_holdled_g5 plot_holdled_g6 plot_holdled_g7 plot_holdled_g8 plot_holdled_g9} {
        if {[dict exists $d "plots.$key"]} { set cfg($key) [dict get $d "plots.$key"] }
    }
    # v0.4.8: migrate manifests written before explicit grid modes existed.
    # A global value of "inherit" has no useful parent, so resolve it from the
    # legacy boolean and keep new sessions explicit.
    if {$cfg(plot_grid_mode) eq "inherit"} {
        set cfg(plot_grid_mode) [expr {$cfg(plot_grid) ? "both" : "none"}]
    }
    array unset customCompare *
    set customCompareCount 0
    if {[dict exists $d "plot.compare.custom.count"]} {
        set n [dict get $d "plot.compare.custom.count"]
        if {[string is integer -strict $n] && $n >= 0} {
            if {$n > 100} { set n 100 }
            set customCompareCount $n
            for {set i 1} {$i <= $customCompareCount} {incr i} {
                foreach {field def} {enabled 1 type full layout overlay nodes "" title "" xlabel "" ylabel "" ylabel_template "" time_unit inherit legend_mode inherit legend_location northeast legend_orientation inherit legend_border inherit legend_external_margin_px ""} {
                    set k "plot.compare.custom.$i.$field"
                    if {[dict exists $d $k]} { set customCompare($i,$field) [dict get $d $k] } else { set customCompare($i,$field) $def }
                }
            }
        }
    }
    array unset legendOverride *
    if {[dict exists $d "plot.legend.overrides.keys"]} {
        foreach gk [split [dict get $d "plot.legend.overrides.keys"] ","] {
            set gk [string trim $gk]
            if {$gk eq ""} continue
            foreach {field def} {enabled 1 mode "" placement "" location "" alignment "" orientation "" layout "" columns "" background "" border "" border_color "" font_unit "" font_size "" external_margin_px "" manual_x "" manual_y ""} {
                set dk "plot.legend.$gk.$field"
                set legendOverride($gk,$field) [expr {[dict exists $d $dk] ? [dict get $d $dk] : $def}]
            }
        }
    }
    array unset axisOverride *
    if {[dict exists $d "plot.axis.overrides.keys"]} {
        foreach gk [split [dict get $d "plot.axis.overrides.keys"] ","] {
            set gk [string trim $gk]
            if {$gk eq ""} continue
            foreach {field def} {enabled 1 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" layout_auto 1 layout_margin_left "" layout_margin_right "" layout_margin_top "" layout_margin_bottom "" layout_gap "" layout_ylabel_dist ""} {
                set dk "plot.axis.$gk.$field"
                set axisOverride($gk,$field) [expr {[dict exists $d $dk] ? [dict get $d $dk] : $def}]
            }
            set panels {}
            set pck "plot.axis.$gk.panel_count"
            set pc [expr {[dict exists $d $pck] ? [dict get $d $pck] : 0}]
            if {![string is integer -strict $pc] || $pc < 0} { set pc 0 }
            if {$pc > 32} { set pc 32 }
            for {set pi 1} {$pi <= $pc} {incr pi} {
                set nk "plot.axis.$gk.panel${pi}_name"
                if {![dict exists $d $nk]} continue
                set pn [dict get $d $nk]
                if {[string trim $pn] eq ""} continue
                lappend panels $pn
                foreach {field def} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x ""} {
                    set dk "plot.axis.$gk.panel${pi}_$field"
                    set axisOverride($gk,$pn,$field) [expr {[dict exists $d $dk] ? [dict get $d $dk] : $def}]
                }
            }
            set axisOverride($gk,panels) $panels
        }
    }
    foreach key {print_page print_orientation print_rows print_cols print_margin_mm print_gap_mm print_captions print_title print_output_pdf print_printer print_copies print_duplex export_dir} {
        if {[dict exists $d "print.$key"]} { set cfg($key) [dict get $d "print.$key"] }
    }

    # I manifest salvano solo i canali abilitati: prima del caricamento
    # disabilitare tutti i canali, poi riattivare quelli presenti nel file.
    for {set i 1} {$i <= 8} {incr i} { set ch($i,enabled) 0 }
    for {set i 1} {$i <= 8} {incr i} {
        foreach key {enabled column scope name} {
            if {[dict exists $d "channels.channel$i.$key"]} { set ch($i,$key) [dict get $d "channels.channel$i.$key"] }
        }
        foreach key {manufacturer model attenuation bandwidth coupling notes} {
            if {[dict exists $d "probe.$i.$key"]} { set probe($i,$key) [dict get $d "probe.$i.$key"] }
        }
        if {[dict exists $d "plots.channel$i.label"]} {
            set ch($i,plot_label) [dict get $d "plots.channel$i.label"]
        } else {
            set ch($i,plot_label) $ch($i,name)
        }
        if {[dict exists $d "plots.channel$i.color"]} { set ch($i,plot_color) [dict get $d "plots.channel$i.color"] }
    }

    # Fill extra rows from whatever remains in [extra].
    for {set i 1} {$i <= 8} {incr i} { set extra($i,key) ""; set extra($i,value) "" }
    set n 0
    dict for {k v} $d {
        if {[string match "extra.*" $k]} {
            incr n
            if {$n <= 8} {
                set extra($n,key) [string range $k 6 end]
                set extra($n,value) $v
            }
        }
    }
}
