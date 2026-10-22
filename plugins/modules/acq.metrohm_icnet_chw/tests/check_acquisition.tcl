# Real native callback smoke test; no CORE transaction/registry/GUI acceptance.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 3} {
    error {Usage: tclsh check_acquisition.tcl MODULE_ROOT ORIGINAL_CHW NEW_OUTPUT}
}
lassign $argv packageRoot source output
set source [file normalize $source]
set output [file normalize $output]
if {![file isfile $source]} {error "Fixture not found: $source"}
if {[file exists $output]} {error "Fresh output directory required: $output"}
file mkdir $output
set raw [file join $output RAW_001.snapshot.chw]
file copy -- $source $raw
source [file join $packageRoot runtime acquisition_handler.tcl]
set inspected [::AcqMetrohmCHW::inspect [dict create source_path $source]]
if {![dict get $inspected recognized]} {error "Inspect rejected fixture: [dict get $inspected warnings]"}
set md [dict get $inspected metadata]
set peakCount [dict get $md chromatography.integration_peak_count]
set unit [dict get $md chromatography.signal_unit]
foreach profile {complete trace_and_peaks trace_only} {
    set dir [file join $output $profile]
    file mkdir $dir
    set result [::AcqMetrohmCHW::import [dict create source_path $source raw_path $raw raw_paths [list $raw] \
        output_dir $dir dataset_id "test_${profile}" config [dict create output_profile $profile]]]
    set datasets [dict get $result datasets]
    set expected [expr {1 + ($profile eq "complete") + ($peakCount > 0 && $profile ne "trace_only")}]
    if {[llength $datasets] != $expected} {error "Wrong output count for $profile"}
    set traceFound 0
    foreach ds $datasets {
        set path [file join $dir [dict get $ds path]]
        if {![file isfile $path]} {error "Missing staged payload: $path"}
        if {[dict get $ds structured_metadata source.original_filename] ne [file tail $source]} {
            error {Renamed RAW snapshot replaced original source identity}
        }
        if {[dict get $ds contract] eq "timeseries.table"} {
            set traceFound 1
            if {[dict get $ds variables] ne {time_s time_min signal_value adc_count} || \
                [dict get $ds units] ne [list s min $unit 1]} {error {Trace schema/units differ}}
            if {[dict get [lindex [dict get $ds variable_schema] 3] dtype] ne "int32"} {error {ADC dtype differs}}
        }
        if {[dict get $ds contract] eq "chromatography.icnet.raw" && \
            [lindex [exec sha256sum -- $path] 0] ne [lindex [exec sha256sum -- $source] 0]} {
            error {Complete profile changed original bytes}
        }
    }
    if {!$traceFound} {error {Profile omitted trace}}
    puts "PASS CALLBACK_ONLY $profile: $expected staged outputs"
}
puts {PASS CALLBACK_ONLY; canonical registration and installed GUI not tested}
