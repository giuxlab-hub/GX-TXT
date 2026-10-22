# SPDX-License-Identifier: GPL-3.0-or-later
# Actual callback regression; no CORE substitution or canonical acceptance claim.
if {[llength $argv] != 5} {
    error "Usage: FRAMEWORK VALID_CDF BAD_CDF_1 BAD_CDF_2 NEW_RAID_OUTPUT"
}
lassign $argv framework valid bad1 bad2 output
set framework [file normalize $framework]
set output [file normalize $output]
if {![string match /srv/gxtxt/agents/* $output] || [file exists $output]} {
    error "Output must be a fresh directory under RAID /srv/gxtxt/agents"
}
file mkdir $output
foreach {key sub} {
    XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache
    XDG_STATE_HOME state XDG_RUNTIME_DIR runtime GXTXT_INSTALLATION_ROOT installation
    GXTXT_JOB_ROOT jobs GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE storage TMPDIR tmp
} {
    set ::env($key) [file join $output $sub]
    file mkdir $::env($key)
}
set ::env(PYTHONDONTWRITEBYTECODE) 1
unset -nocomplain ::env(DISPLAY) ::env(WAYLAND_DISPLAY)
set module [file normalize [file join [file dirname [info script]] ..]]
set argv0 __task210_aia_callbacks__
set argv {}
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
source [file join $module runtime acquisition_handler.tcl]
set inspection [::AcqAiaAndi::inspect [dict create source_path $valid]]
if {![dict get $inspection recognized]} {error "Valid fixture not recognized"}
set hasPeaks [expr {[dict get $inspection metadata chromatography.peak_count] > 0}]
foreach profile {trace_only trace_and_peaks complete} {
    set dir [file join $output $profile]
    file mkdir $dir
    set reply [::AcqAiaAndi::import [dict create source_path $valid raw_path $valid \
        output_dir $dir dataset_id "aia.$profile" config [dict create output_profile $profile]]]
    set count [expr {1 + ($hasPeaks && $profile ne "trace_only") + ($profile eq "complete")}]
    if {[llength [dict get $reply datasets]] != $count} {error "Wrong profile output count"}
    foreach ds [dict get $reply datasets] {
        if {![file isfile [file join $dir [dict get $ds path]]]} {error "Missing returned payload"}
    }
    puts "PASS $profile: $count outputs"
}
set ordinal 0
foreach bad [list $bad1 $bad2] {
    incr ordinal
    set i [::AcqAiaAndi::inspect [dict create source_path $bad]]
    if {[dict get $i recognized]} {error "Invalid precision fixture recognized"}
    set diagnostic [dict get $i preview_metadata Diagnostic]
    if {![string match {AIA/ANDI parser: Computed retention axis must be strictly increasing*} $diagnostic] ||
        [string first GXANDI1 $diagnostic] >= 0 || [string first "\t" $diagnostic] >= 0} {
        error "Invalid or internal-protocol diagnostic: $diagnostic"
    }
    set dir [file join $output "negative$ordinal"]
    file mkdir $dir
    if {![catch {::AcqAiaAndi::import [dict create source_path $bad raw_path $bad \
        output_dir $dir dataset_id invalid config [dict create output_profile complete]]} message]} {
        error "Invalid precision fixture imported"
    }
    if {$message ne $diagnostic || [llength [glob -nocomplain -directory $dir *]]} {
        error "Failure left output residue or inconsistent diagnostic"
    }
    puts "PASS negative$ordinal: $diagnostic"
}
puts "PASS actual AIA callbacks; canonical/GUI acceptance is separate."
