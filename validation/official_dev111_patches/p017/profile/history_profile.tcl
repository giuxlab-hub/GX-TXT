# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework out mode
if {[llength $argv]!=3 || $mode ni {core curve}} {error {usage: history_profile.tcl FRAMEWORK NEW_OUTPUT core|curve}}
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_PROFILE__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_HISTORY_PROFILE
proc emit {name value} {set f [open [file join $::out $name] w];try {fconfigure $f -encoding utf-8;puts $f $value} finally {close $f}}
proc assert {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set measurements {}
proc measure {size stage script {iterations 3}} {
    set timings {};set result {}
    for {set i 0} {$i<$iterations} {incr i} {
        set begin [clock microseconds]
        set result [uplevel 1 $script]
        lappend timings [expr {[clock microseconds]-$begin}]
    }
    lappend ::measurements [dict create history_steps $size stage $stage microseconds $timings]
    puts "$size\t$stage\t$timings";flush stdout
    return $result
}
proc profileValidator {record} {return {}}
proc coreProfile {} {
    ::GX::scientificRecipeHostRegister fixture.history_profile [dict create capture {} validate profileValidator replay {}]
    set base [dict create curve1 [dict create id curve1 points {{0 0} {1 1}} operations {}] @cad [dict create groups {}]]
    set semantic [dict create api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 operation geometry_state parameters {} targets curve1 result_ids curve1 working_unit mm description {Translate curve} timestamp 1792860000]
    set all {}
    for {set i 1} {$i<=480} {incr i} {
        set curve [dict create id curve1 points [list [list $i 0] [list [expr {$i+1}] 1]] operations [list [list translate $i 0]]]
        lappend all [dict merge $semantic [dict create parameters [dict create retained_scientific_state [string repeat [format %04d $i] 4096]] patch [dict create curve1 $curve]]]
    }
    foreach n {0 64 256 480} {
        set record [::GX::scientificHistoryCreate fixture.history_profile $base]
        dict set record steps [lrange $all 0 [expr {$n-1}]]
        if {$n==0} {dict set record steps {}}
        dict set record cursor $n
        puts "BYTES $n [string bytelength $record]"
        measure $n validate {::GX::scientificHistoryValidate fixture.history_profile $record}
        set current [measure $n state {::GX::scientificHistoryState $record}]
        set after $current;dict set after curve1 points [list [list [expr {$n+2}] 0] [list [expr {$n+3}] 1]]
        measure $n delta_and_recipe_append {::GX::scientificRecipeAppend $record $current $after $semantic}
        measure $n public_history_append {::GX::scientificHistoryAppend fixture.history_profile $record $after {Translate curve}}
        measure $n encode {::GX::scientificRecipeEncode $record}
        set bytes [encoding convertto utf-8 $record]
        measure $n hash {::GX::_workbenchRecoveryDigest $bytes}
        set doc [::GX::interactiveDocumentCreate fixture.history_profile fixture_history gxtxt.history.profile 1 $record]
        set id [dict get $doc id]
        ::GX::workbenchRecoveryBegin $id
        set round 0
        measure $n document_update {incr round;dict set record profile_revision $round;::GX::interactiveDocumentUpdate $id $record}
        measure $n document_read {::GX::interactiveDocumentRead $id}
        measure $n recovery_write {::GX::workbenchRecoveryCheckpoint $id {operation translate}}
        # Every sample changes payload so this stage includes full read/verify/write.
        measure $n document_and_recovery {incr round;dict set record profile_revision $round;::GX::interactiveDocumentUpdate $id $record;::GX::workbenchRecoveryCheckpoint $id {operation translate}}
    }
}
try {
    if {$mode eq {core}} {coreProfile} else {source [file join [file dirname [info script]] curve_profile.tcl];curveProfile}
    emit measurements.tcldict $measurements
    emit receipt.tcldict [dict create status PASS_PROFILE mode $mode framework $framework framework_version [string trim [read [set versionFile [open [file join $framework VERSION.txt] r]]]] measurements $measurements scope {Automated timing experiment; no human GUI acceptance}];close $versionFile
} on error {m o} {
    emit measurements.partial.tcldict $measurements
    emit FIRST_FAILURE.tcldict [dict create message $m options $o]
    puts stderr [dict get $o -errorinfo]
    exit 1
} finally {catch {destroy .}}
exit 0
