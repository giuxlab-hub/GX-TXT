# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::channelSpec {} {
    variable ch
    set items {}
    for {set i 1} {$i <= 8} {incr i} {
        if {!$ch($i,enabled)} continue
        set col [string trim $ch($i,column)]
        set scope [string trim $ch($i,scope)]
        set name [string trim $ch($i,name)]
        if {$col eq "" || $scope eq "" || $name eq ""} {
            error "Channel $i: CSV column, physical channel, and logical name are required when the channel is enabled."
        }
        if {![string is integer -strict $col] || $col < 1} {
            error "Channel $i: the CSV column must be an integer >= 1."
        }
        if {[regexp {[|;]} "$scope$name"]} {
            error "Channel $i: characters | and ; are not allowed in names."
        }
        lappend items "$col|$scope|$name"
    }
    if {[llength $items] == 0} { error "Enable at least one channel." }
    return [join $items ";"]
}

proc ::GX::validate_v048 {} {
    variable cfg
    if {$cfg(input_csv) eq ""} { error "Select an acquisition CSV." }
    if {![file isfile $cfg(input_csv)]} { error "CSV not found: $cfg(input_csv)" }
    if {$cfg(output_root) eq ""} { error "Specify the session root folder." }
    if {$cfg(worker_file) eq "" || ![file isfile $cfg(worker_file)]} { error "Octave worker not found: $cfg(worker_file)" }
    if {$cfg(octave_cmd) eq ""} { error "Specify octave-cli/octave." }
    if {[auto_execok $cfg(octave_cmd)] eq "" && ![file executable $cfg(octave_cmd)]} {
        error "Octave command not found or not executable: $cfg(octave_cmd)"
    }
    if {![string is integer -strict $cfg(header_lines)] || $cfg(header_lines) < 0} { error "header_lines must be >= 0." }
    if {![string is integer -strict $cfg(cpu_count)] || $cfg(cpu_count) < 1} { error "CPU count must be an integer >= 1." }
    if {![string is integer -strict $cfg(chunk_rows)] || $cfg(chunk_rows) < 1000} { error "Rows per block must be an integer >= 1000." }
    if {![string is integer -strict $cfg(raw_fields)] || $cfg(raw_fields) < 0} { error "Raw fields per record must be 0 (auto) or an integer >= 1." }
    if {![string is integer -strict $cfg(drop_trailing_fields)] || $cfg(drop_trailing_fields) < 0} { error "Trailing fields to ignore must be an integer >= 0." }
    if {$cfg(raw_fields) > 0 && $cfg(drop_trailing_fields) >= $cfg(raw_fields)} { error "Trailing fields to ignore must be fewer than raw fields per record." }
    if {$cfg(parser) eq "generic_sequence"} {
        if {$cfg(manual_tstart) eq "" || $cfg(manual_dt) eq ""} { error "generic_sequence requires manual tStart and dt." }
    }
    if {![string is integer -strict $cfg(analysis_verbosity)] || $cfg(analysis_verbosity) < 0 || $cfg(analysis_verbosity) > 3} { error "Analysis verbosity must be 0..3." }
    if {![string is double -strict $cfg(analysis_nominal_carrier_hz)] || $cfg(analysis_nominal_carrier_hz) <= 0} { error "Nominal carrier must be > 0." }
    if {![string is integer -strict $cfg(analysis_ir_cluster_guard)] || $cfg(analysis_ir_cluster_guard) ni {0 1}} { error "IR cluster span guard must be 0 or 1." }
    if {![string is double -strict $cfg(analysis_ir_cluster_max_ratio)] || $cfg(analysis_ir_cluster_max_ratio) < 1.0} { error "IR cluster maximum ratio must be >= 1." }
    foreach key {holdled_rled_ohm holdled_rdischarge_ohm} {
        if {![string is double -strict $cfg($key)] || $cfg($key) <= 0} { error "$key must be > 0 ohm." }
    }
    if {$cfg(plot_time_unit) ni {auto s ms us ns min h day}} { error "Plot time unit must be auto, s, ms, us, ns, min, h or day." }
    if {$cfg(plot_grid_mode) ni {inherit both vertical horizontal none}} { error "Plot grid mode must be inherit, both, vertical, horizontal or none." }
    if {$cfg(plot_grid_color) ne "" && ![regexp {^#[0-9A-Fa-f]{6}$} $cfg(plot_grid_color)]} { error "Grid color must be blank or #RRGGBB." }
    if {![string is integer -strict $cfg(analysis_png_dpi)] || $cfg(analysis_png_dpi) < 72 || $cfg(analysis_png_dpi) > 1200} { error "Plot DPI must be an integer between 72 and 1200." }
    foreach key {plot_width_px plot_height_px} {
        if {![string is double -strict $cfg($key)] || $cfg($key) <= 0} { error "$key must be > 0." }
    }
    if {$cfg(plot_font_unit) ni {px pt}} { error "Font unit must be px or pt." }
    foreach key {plot_font_size plot_legend_font_size} {
        if {![string is double -strict $cfg($key)] || $cfg($key) <= 0} { error "$key must be > 0 in the selected font unit." }
    }
    foreach key {plot_axis_label_font_size plot_title_font_size} {
        if {$cfg($key) ne "" && (![string is double -strict $cfg($key)] || $cfg($key) <= 0)} { error "$key must be blank or > 0 in the selected font unit." }
    }
    foreach key {plot_stacked_margin_left_pct plot_stacked_margin_right_pct plot_stacked_margin_top_pct plot_stacked_margin_bottom_pct plot_stacked_gap_pct} {
        if {![string is double -strict $cfg($key)] || $cfg($key) < 0 || $cfg($key) > 30} { error "$key must be between 0 and 30%." }
    }
    if {![string is double -strict $cfg(plot_stacked_ylabel_x)] || $cfg(plot_stacked_ylabel_x) < -0.5 || $cfg(plot_stacked_ylabel_x) > 0.2} { error "plot_stacked_ylabel_x must be between -0.5 and 0.2." }
    if {![string is double -strict $cfg(plot_line_width)] || $cfg(plot_line_width) <= 0} { error "Line width must be > 0." }
    if {$cfg(plot_legend_layout) ni {auto row stacked wrapped}} { error "Legend layout must be auto, row, stacked or wrapped." }
    if {$cfg(plot_legend_alignment) ni {start center end}} { error "Legend alignment must be start, center or end." }
    if {![string is integer -strict $cfg(plot_legend_columns)] || $cfg(plot_legend_columns) < 1} { error "Legend columns must be an integer >= 1." }
    if {![string is double -strict $cfg(plot_legend_external_margin_px)] || $cfg(plot_legend_external_margin_px) < 0 || $cfg(plot_legend_external_margin_px) > 100} { error "External legend margin must be between 0 and 100 px." }
    foreach key {plot_legend_manual_x plot_legend_manual_y} {
        if {![string is double -strict $cfg($key)] || $cfg($key) < 0 || $cfg($key) > 1} { error "$key must be between 0 and 1." }
    }
    channelSpec
}

proc ::GX::validate {} {
    return [::GX::validate_v048]
}

proc ::GX::makeSession_v092_before_note_files {} {
    variable cfg
    variable currentSession
    file mkdir $cfg(output_root)
    if {[string trim $cfg(session_name)] ne ""} {
        set name [sanitize $cfg(session_name)]
    } else {
        set stem [sanitize [file rootname [file tail $cfg(input_csv)]]]
        set name "[clock format [clock seconds] -format %Y%m%d_%H%M%S]_$stem"
    }
    set currentSession [file join [file normalize $cfg(output_root)] $name]
    if {[file exists $currentSession]} {
        append currentSession "_[clock clicks]"
    }
    foreach d {raw metadata channels analysis report logs} {
        file mkdir [file join $currentSession $d]
    }
    return $currentSession
}

proc ::GX::prepareRawReference {session} {
    variable cfg
    set rawdir [file join $session raw]
    set src [file normalize $cfg(input_csv)]
    set dst [file join $rawdir [file tail $src]]

    if {$cfg(copy_raw)} {
        file copy -force $src $dst
        return $dst
    }
    if {$cfg(link_raw)} {
        catch {file delete -force $dst}
        if {[catch {file link -symbolic $dst $src} err]} {
            # Symlink is convenience only; the manifest still points at the original.
            set f [open [file join $rawdir RAW_SOURCE.txt] w]
            fconfigure $f -encoding utf-8 -translation lf
            puts $f $src
            puts $f "Symlink non creato: $err"
            close $f
            return $src
        }
        return $dst
    }
    set f [open [file join $rawdir RAW_SOURCE.txt] w]
    fconfigure $f -encoding utf-8 -translation lf
    puts $f $src
    close $f
    return $src
}

proc ::GX::buildWorkerCommand_v052_native {session} {
    variable cfg
    set spec [channelSpec]
    set outdir [file join $session channels]
    set manifest [file join $session metadata manifest.ini]
    set ncpu $cfg(cpu_count)
    set cmd [list env \
        OMP_NUM_THREADS=$ncpu \
        OPENBLAS_NUM_THREADS=$ncpu \
        MKL_NUM_THREADS=$ncpu \
        NUMEXPR_NUM_THREADS=$ncpu \
        $cfg(octave_cmd) --quiet --no-gui $cfg(worker_file) \
        --input [file normalize $cfg(input_csv)] \
        --out $outdir \
        --parser $cfg(parser) \
        --delimiter $cfg(delimiter) \
        --header-lines $cfg(header_lines) \
        --sequence-col $cfg(sequence_col) \
        --time-col $cfg(time_col) \
        --tstart $cfg(manual_tstart) \
        --dt $cfg(manual_dt) \
        --channels $spec \
        --make-rigol $cfg(make_rigol_split) \
        --make-canonical $cfg(make_canonical_split) \
        --workers $cfg(cpu_count) \
        --chunk-rows $cfg(chunk_rows) \
        --raw-fields $cfg(raw_fields) \
        --drop-trailing-fields $cfg(drop_trailing_fields) \
        --strict-sequence $cfg(strict_sequence) \
        --manifest $manifest]
    return $cmd
}

proc ::GX::runSync_v048 {manifestPath} {
    variable cfg
    variable cliMode
    set cliMode 1
    loadManifest $manifestPath
    if {$cfg(output_root) eq ""} {
        set cfg(output_root) [file join [pwd] GXTXT_sessions]
    }
    validate
    set session [makeSession]
    prepareRawReference $session
    writeManifest [file join $session metadata manifest.ini]
    set cmd [buildWorkerCommand $session]
    puts "Session: $session"
    puts "Command: $cmd"
    flush stdout
    if {[catch {exec {*}$cmd 2>@1} output opts]} {
        puts stderr $output
        return -options $opts $output
    }
    puts $output
    return $session
}
