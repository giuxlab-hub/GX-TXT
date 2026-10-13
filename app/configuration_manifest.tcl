# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::defaults_v048 {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable customCompare
    variable customCompareCount
    variable legendOverride
    variable axisOverride
    variable scriptDir

    array unset axisOverride *
    array unset cfg *
    array set cfg [list \
        input_csv "" \
        output_root "" \
        session_name "" \
        parser "rigol_ds1000z" \
        delimiter "," \
        header_lines 2 \
        sequence_col 1 \
        time_col 1 \
        manual_tstart "" \
        manual_dt "" \
        make_rigol_split 1 \
        make_canonical_split 0 \
        link_raw 1 \
        copy_raw 0 \
        octave_cmd "" \
        worker_file [file join $scriptDir plugins modules acq.rigol_csv runtime gxtxt_csv_worker.m] \
        post_per_channel "" \
        cpu_count [expr {[catch {exec nproc} _n] ? 1 : [string trim $_n]}] \
        chunk_rows 250000 \
        preview_lines 8 \
        raw_fields 0 \
        drop_trailing_fields 0 \
        strict_sequence 1 \
        project "GX-TXT" \
        board "GX-TXT-v3" \
        test "catena_veloce" \
        date [clock format [clock seconds] -format "%Y-%m-%d"] \
        remote "" \
        button "" \
        distance_cm "" \
        p_gain_ohm "" \
        p_sens_ohm "" \
        supply_v "" \
        experiment_notes "" \
        scope_manufacturer "Rigol" \
        scope_model "DS1104Z-S Plus" \
        scope_serial "" \
        scope_firmware "" \
        scope_memory_depth "" \
        scope_sample_rate "" \
        scope_bandwidth_limit "" \
        scope_coupling "DC" \
        scope_notes "" \
        analysis_ir 1 \
        analysis_identify 1 \
        analysis_compare 1 \
        analysis_holdled 0 \
        run_analysis_ir 1 \
        run_analysis_identify 1 \
        run_analysis_compare 1 \
        run_analysis_holdled 0 \
        analysis_ir_nodes "VIR" \
        analysis_hold_node "HOLD" \
        analysis_led_node "N_LED_ARANCIO" \
        analysis_verbosity 2 \
        analysis_nominal_carrier_hz 38000 \
        analysis_ir_cluster_guard 1 \
        analysis_ir_cluster_max_ratio 1.60 \
        analysis_png_dpi 200 \
        graphics_mode "headless" \
        graphics_toolkit "gnuplot" \
        graphics_display "" \
        graphics_visible 0 \
        plot_width_px 1600 \
        plot_height_px 900 \
        plot_font_unit "px" \
        plot_font_size 12 \
        plot_axis_label_font_size "" \
        plot_title_font_size "" \
        plot_line_width 1.4 \
        plot_grid 1 \
        plot_grid_mode "both" \
        plot_grid_color "" \
        plot_time_unit "auto" \
        plot_stacked_shared_x 1 \
        plot_stacked_bottom_xticks_only 1 \
        plot_stacked_grid_mode "inherit" \
        plot_stacked_margin_left_pct 10 \
        plot_stacked_margin_right_pct 4 \
        plot_stacked_margin_top_pct 10 \
        plot_stacked_margin_bottom_pct 10 \
        plot_stacked_gap_pct 2.5 \
        plot_stacked_align_ylabels 1 \
        plot_stacked_ylabel_x -0.085 \
        plot_legend_mode "inside" \
        plot_legend_location "northeast" \
        plot_legend_font_unit "inherit" \
        plot_legend_font_size 10 \
        plot_legend_orientation "auto" \
        plot_legend_layout "auto" \
        plot_legend_alignment "center" \
        plot_legend_columns 1 \
        plot_legend_background "#FFFFFF" \
        plot_legend_border 1 \
        plot_legend_external_border 0 \
        plot_legend_border_color "#808080" \
        plot_legend_external_margin_px 12 \
        plot_legend_manual_x 0.75 \
        plot_legend_manual_y 0.85 \
        plot_background "#FFFFFF" \
        plot_compare_graph_full 1 \
        plot_compare_graph_normalized 1 \
        plot_compare_graph_carrier 1 \
        plot_compare_graph_amplitude 1 \
        plot_compare_full_layout "stacked" \
        plot_compare_full_nodes "VIR,QIN_C,OUT_PRE,V_OUT_POT_SENS" \
        plot_compare_normalized_nodes "VIR,QIN_C,OUT_PRE,V_OUT_POT_SENS" \
        plot_compare_carrier_nodes "VIR,QIN_C,OUT_PRE,V_OUT_POT_SENS" \
        plot_compare_amplitude_nodes "VIR,QIN_C,OUT_PRE,V_OUT_POT_SENS" \
        plot_compare_full_title "GX-TXT-v3 - Synchronized analog signal chain" \
        plot_compare_normalized_title "GX-TXT-v3 - Normalized waveform comparison" \
        plot_compare_carrier_title "GX-TXT-v3 - Carrier detail along the signal chain" \
        plot_compare_amplitude_title "GX-TXT-v3 - Signal excursion at measured nodes" \
        plot_compare_full_xlabel "Time \[s\]" \
        plot_compare_full_ylabel "Voltage \[V\]" \
        plot_compare_full_ylabel_template "{NODE} \[V\]" \
        plot_compare_normalized_xlabel "Time \[s\]" \
        plot_compare_normalized_ylabel "Normalized excursion" \
        plot_compare_carrier_xlabel "Time \[us\]" \
        plot_compare_carrier_ylabel "Normalized excursion" \
        plot_compare_amplitude_ylabel "Excursion from baseline \[V\]" \
        plot_ir_graph_full 1 \
        plot_ir_graph_carrier 1 \
        plot_ir_graph_markspace 1 \
        plot_ir_graph_durations 1 \
        plot_ir_full_title "GX-TXT-v3 - {NODE} - Full command" \
        plot_ir_carrier_title "GX-TXT-v3 - {NODE} - Carrier detail" \
        plot_ir_markspace_title "GX-TXT-v3 - {NODE} - MARK / SPACE reconstruction" \
        plot_ir_durations_title "GX-TXT-v3 - {NODE} - MARK / SPACE durations" \
        plot_ir_voltage_ylabel "{NODE} \[V\]" \
        plot_ir_full_xlabel "Time \[ms\]" \
        plot_ir_carrier_xlabel "Time from first cycle \[us\]" \
        plot_ir_markspace_xlabel "Time from command start \[ms\]" \
        plot_ir_markspace_ylabel "Carrier present" \
        plot_ir_durations_xlabel "Sequence position" \
        plot_ir_durations_ylabel "Duration \[us\]" \
        plot_holdled_g1 1 \
        plot_holdled_g2 1 \
        plot_holdled_g3 1 \
        plot_holdled_g4 1 \
        plot_holdled_g5 1 \
        plot_holdled_g6 1 \
        plot_holdled_g7 1 \
        plot_holdled_g8 1 \
        plot_holdled_g9 1 \
        holdled_num_impulses 100 \
        holdled_vgen_v "" \
        holdled_duty_pct 50 \
        holdled_ipd_ua "" \
        holdled_mode "burst" \
        holdled_trigger_reference "burst_start" \
        holdled_rled_ohm 680 \
        holdled_rdischarge_ohm 100000 \
        print_page "A4" \
        print_orientation "portrait" \
        print_rows 2 \
        print_cols 2 \
        print_margin_mm 10 \
        print_gap_mm 5 \
        print_captions 1 \
        print_title "GX-TXT" \
        print_output_pdf "" \
        print_printer "" \
        print_copies 1 \
        print_duplex "auto" \
        export_dir "" \
    ]

    if {[auto_execok octave-cli] ne ""} {
        set cfg(octave_cmd) [auto_execok octave-cli]
    } elseif {[auto_execok octave] ne ""} {
        set cfg(octave_cmd) [auto_execok octave]
    } else {
        set cfg(octave_cmd) "octave-cli"
    }

    array unset ch *
    array unset probe *
    for {set i 1} {$i <= 8} {incr i} {
        set ch($i,enabled) [expr {$i <= 4 ? 1 : 0}]
        set ch($i,column) [expr {$i + 1}]
        set ch($i,scope) "CH$i"
        switch -- $i {
            1 { set ch($i,name) "VIR" }
            2 { set ch($i,name) "QIN_C" }
            3 { set ch($i,name) "OUT_PRE" }
            4 { set ch($i,name) "V_OUT_POT_SENS" }
            default { set ch($i,name) "" }
        }
        set ch($i,plot_label) $ch($i,name)
        set ch($i,plot_color) ""
        set probe($i,manufacturer) ""
        set probe($i,model) ""
        set probe($i,attenuation) "10x"
        set probe($i,bandwidth) ""
        set probe($i,coupling) "DC"
        set probe($i,notes) ""
    }

    array unset customCompare *
    set customCompareCount 0
    array unset legendOverride *

    array unset extra *
    for {set i 1} {$i <= 8} {incr i} {
        set extra($i,key) ""
        set extra($i,value) ""
    }
}

proc ::GX::sanitize {s} {
    set s [string trim $s]
    regsub -all {[^[:alnum:]_.-]+} $s {_} s
    regsub -all {_+} $s {_} s
    set s [string trim $s _]
    if {$s eq ""} { set s "session" }
    return $s
}

proc ::GX::iniEscape {s} {
    return [string map [list "\\" "\\\\" "\n" "\\n" "\r" "\\r"] $s]
}

proc ::GX::iniUnescape {s} {
    # Minimal, deterministic unescape for our manifests.
    set placeholder "\u0001"
    set s [string map [list "\\\\" $placeholder "\\n" "\n" "\\r" "\r"] $s]
    return [string map [list $placeholder "\\"] $s]
}

proc ::GX::putKV {fd key value} {
    puts $fd "$key=[::GX::iniEscape $value]"
}

proc ::GX::appendKV {varName key value} {
    upvar 1 $varName out
    append out "$key=[::GX::iniEscape $value]\n"
}

proc ::GX::manifestString_v048 {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable version

    set out "; GX-TXT measurement manifest\n; generated by gxtxt_pipeline.tcl v$version\n\n"
    append out "\[pipeline\]\n"
    appendKV out version $version
    appendKV out generated_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    append out "\n\[runtime\]\n"
    foreach key {output_root session_name octave_cmd worker_file post_per_channel link_raw copy_raw} {
        appendKV out $key $cfg($key)
    }
    append out "\n\[processing\]\n"
    foreach key {cpu_count chunk_rows preview_lines raw_fields drop_trailing_fields strict_sequence} { appendKV out $key $cfg($key) }

    append out "\n\[acquisition\]\n"
    foreach key {input_csv parser delimiter header_lines sequence_col time_col manual_tstart manual_dt make_rigol_split make_canonical_split} {
        appendKV out $key $cfg($key)
    }

    append out "\n\[experiment\]\n"
    foreach key {project board test date remote button distance_cm p_gain_ohm p_sens_ohm supply_v experiment_notes} {
        appendKV out $key $cfg($key)
    }

    append out "\n\[oscilloscope\]\n"
    foreach key {scope_manufacturer scope_model scope_serial scope_firmware scope_memory_depth scope_sample_rate scope_bandwidth_limit scope_coupling scope_notes} {
        set outkey [string range $key 6 end]
        appendKV out $outkey $cfg($key)
    }

    append out "\n\[analysis\]\n"
    foreach key {analysis_ir analysis_identify analysis_compare analysis_holdled analysis_ir_nodes analysis_hold_node analysis_led_node analysis_verbosity analysis_nominal_carrier_hz analysis_ir_cluster_guard analysis_ir_cluster_max_ratio analysis_png_dpi graphics_mode graphics_toolkit graphics_display graphics_visible holdled_num_impulses holdled_vgen_v holdled_duty_pct holdled_ipd_ua holdled_mode holdled_trigger_reference holdled_rled_ohm holdled_rdischarge_ohm} {
        appendKV out $key $cfg($key)
    }

    append out "\n\[modules\]\n"
    appendKV out catalog_version 1
    appendKV out selected [join [selectedModuleIds] ","]

    append out "\n\[execution\]\n"
    foreach key {run_analysis_ir run_analysis_identify run_analysis_compare run_analysis_holdled} { appendKV out $key $cfg($key) }

    append out "\n\[plots\]\n"
    foreach key {plot_width_px plot_height_px plot_font_unit plot_font_size plot_axis_label_font_size plot_title_font_size plot_line_width plot_grid plot_grid_mode plot_grid_color plot_time_unit plot_stacked_shared_x plot_stacked_bottom_xticks_only plot_stacked_grid_mode plot_stacked_margin_left_pct plot_stacked_margin_right_pct plot_stacked_margin_top_pct plot_stacked_margin_bottom_pct plot_stacked_gap_pct plot_stacked_align_ylabels plot_stacked_ylabel_x plot_legend_mode plot_legend_location plot_legend_font_unit plot_legend_font_size plot_legend_orientation plot_legend_layout plot_legend_alignment plot_legend_columns plot_legend_background plot_legend_border plot_legend_external_border plot_legend_border_color plot_legend_external_margin_px plot_legend_manual_x plot_legend_manual_y plot_background plot_compare_graph_full plot_compare_graph_normalized plot_compare_graph_carrier plot_compare_graph_amplitude plot_compare_full_layout plot_compare_full_nodes plot_compare_normalized_nodes plot_compare_carrier_nodes plot_compare_amplitude_nodes plot_compare_full_title plot_compare_normalized_title plot_compare_carrier_title plot_compare_amplitude_title plot_compare_full_xlabel plot_compare_full_ylabel plot_compare_full_ylabel_template plot_compare_normalized_xlabel plot_compare_normalized_ylabel plot_compare_carrier_xlabel plot_compare_carrier_ylabel plot_compare_amplitude_ylabel plot_ir_graph_full plot_ir_graph_carrier plot_ir_graph_markspace plot_ir_graph_durations plot_ir_full_title plot_ir_carrier_title plot_ir_markspace_title plot_ir_durations_title plot_ir_voltage_ylabel plot_ir_full_xlabel plot_ir_carrier_xlabel plot_ir_markspace_xlabel plot_ir_markspace_ylabel plot_ir_durations_xlabel plot_ir_durations_ylabel plot_holdled_g1 plot_holdled_g2 plot_holdled_g3 plot_holdled_g4 plot_holdled_g5 plot_holdled_g6 plot_holdled_g7 plot_holdled_g8 plot_holdled_g9} { appendKV out $key $cfg($key) }
    for {set i 1} {$i <= 8} {incr i} {
        appendKV out "channel$i.label" $ch($i,plot_label)
        appendKV out "channel$i.color" $ch($i,plot_color)
    }

    variable customCompare
    variable customCompareCount
    append out "
\[plot.compare.custom\]
"
    appendKV out count $customCompareCount
    for {set i 1} {$i <= $customCompareCount} {incr i} {
        foreach field {enabled type layout nodes title xlabel ylabel ylabel_template time_unit legend_mode legend_location legend_orientation legend_border legend_external_margin_px} {
            set v [expr {[info exists customCompare($i,$field)] ? $customCompare($i,$field) : ""}]
            appendKV out "$i.$field" $v
        }
    }

    variable legendOverride
    set legendKeys {}
    foreach k [array names legendOverride "*,enabled"] {
        set gk [string range $k 0 end-8]
        if {[lsearch -exact $legendKeys $gk] < 0} { lappend legendKeys $gk }
    }
    append out "\n\[plot.legend.overrides\]\n"
    appendKV out keys [join [lsort $legendKeys] ","]
    foreach gk [lsort $legendKeys] {
        append out "\n\[plot.legend.$gk\]\n"
        foreach field {enabled mode placement location alignment orientation layout columns background border border_color font_unit font_size external_margin_px manual_x manual_y} {
            set v [expr {[info exists legendOverride($gk,$field)] ? $legendOverride($gk,$field) : ""}]
            appendKV out $field $v
        }
    }

    variable axisOverride
    set axisKeys {}
    foreach k [array names axisOverride "*,enabled"] {
        set gk [string range $k 0 end-8]
        if {[lsearch -exact $axisKeys $gk] < 0} { lappend axisKeys $gk }
    }
    append out "\n\[plot.axis.overrides\]\n"
    appendKV out keys [join [lsort $axisKeys] ","]
    foreach gk [lsort $axisKeys] {
        append out "\n\[plot.axis.$gk\]\n"
        foreach field {enabled time_unit x_unit y_unit y2_unit align_ylabels ylabel_x x_min x_max x_step x_format y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color layout_auto layout_margin_left layout_margin_right layout_margin_top layout_margin_bottom layout_gap layout_ylabel_dist} {
            set v [expr {[info exists axisOverride($gk,$field)] ? $axisOverride($gk,$field) : ""}]
            appendKV out $field $v
        }
        set panels [expr {[info exists axisOverride($gk,panels)] ? $axisOverride($gk,panels) : {}}]
        appendKV out panel_count [llength $panels]
        set pi 0
        foreach pn $panels {
            incr pi
            appendKV out "panel${pi}_name" $pn
            foreach field {y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color ylabel_x} {
                set ak "$gk,$pn,$field"
                set v [expr {[info exists axisOverride($ak)] ? $axisOverride($ak) : ""}]
                appendKV out "panel${pi}_$field" $v
            }
        }
    }

    append out "\n\[print\]\n"
    foreach key {print_page print_orientation print_rows print_cols print_margin_mm print_gap_mm print_captions print_title print_output_pdf print_printer print_copies print_duplex export_dir} {
        appendKV out $key $cfg($key)
    }

    append out "\n\[channels\]\n"
    for {set i 1} {$i <= 8} {incr i} {
        if {!$ch($i,enabled)} continue
        appendKV out "channel$i.enabled" $ch($i,enabled)
        appendKV out "channel$i.column" $ch($i,column)
        appendKV out "channel$i.scope" $ch($i,scope)
        appendKV out "channel$i.name" $ch($i,name)
    }

    for {set i 1} {$i <= 8} {incr i} {
        if {!$ch($i,enabled)} continue
        append out "\n\[probe.$i\]\n"
        foreach key {manufacturer model attenuation bandwidth coupling notes} {
            appendKV out $key $probe($i,$key)
        }
    }

    append out "\n\[extra\]\n"
    for {set i 1} {$i <= 8} {incr i} {
        set k [string trim $extra($i,key)]
        if {$k eq ""} continue
        regsub -all {[^[:alnum:]_.-]+} $k {_} k
        appendKV out $k $extra($i,value)
    }
    return $out
}

proc ::GX::writeManifest {path} {
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts -nonewline $fd [manifestString]
    close $fd
}

proc ::GX::parseIni {path} {
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set section ""
    set d [dict create]
    while {[gets $fd line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match ";*" $line] || [string match "#*" $line]} continue
        if {[regexp {^\[(.+)\]$} $line -> sec]} {
            set section $sec
            continue
        }
        if {[regexp {^([^=]+)=(.*)$} $line -> k v]} {
            set k [string trim $k]
            set v [::GX::iniUnescape $v]
            dict set d "$section.$k" $v
        }
    }
    close $fd
    return $d
}
