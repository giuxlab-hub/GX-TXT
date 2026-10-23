# SOURCE ONLY. Public owners and bounded reconciliation adapted from Step5 registered.tcl.
if {$argc!=3} {error {Usage: registered.tcl FRAMEWORK PRIVATE_OUTPUT ORIGINAL_DEADLINE_MS}}
namespace eval ::GX210NullQA {
    lassign $::argv framework output deadline
    variable here [file dirname [file normalize [info script]]]
    variable phase admission;variable status FAIL;variable checks {};variable runs {}
    variable session {};variable cleanup {};variable active {};variable hashes {}
}
proc ::GX210NullQA::require {yes} {if {!$yes} {error {TASK210 explicit-null qualification assertion}}}
proc ::GX210NullQA::admit {{reserve 0}} {
    variable deadline
    require [expr {[clock milliseconds]+$reserve<$deadline}]
}
proc ::GX210NullQA::write {path value} {
    set f [open $path {WRONLY CREAT EXCL} 0600]
    try {fconfigure $f -encoding utf-8 -translation lf;puts $f $value} finally {close $f}
}
proc ::GX210NullQA::read {path maximum} {
    file lstat $path info
    require [expr {$info(type) eq {file} && $info(nlink)==1 && [file owned $path] && $info(size)<=$maximum}]
    set f [open $path rb]
    try {set data [::read $f [expr {$maximum+1}]]} finally {close $f}
    require [expr {[string length $data]<=$maximum}]
    return $data
}
proc ::GX210NullQA::projection {row} {
    set result {}
    foreach key {id run_id state reference language source_sha256 output_dir worker_pid pid_start process_identities} {
        if {[dict exists $row $key]} {dict set result $key [dict get $row $key]}
    }
    return $result
}
# Existing registered qualifier PID/start/boot identity checks, no global scan or signals.
proc ::GX210NullQA::processStart {pid} {
    require [expr {[regexp {^[1-9][0-9]*$} $pid] && [string length $pid]<=12}]
    set path /proc/$pid/stat
    if {![file exists $path]} {return {}}
    if {[catch {set text [read $path 16384]}]} {
        if {![file exists $path]} {return {}}
        error {Owned process identity unverifiable}
    }
    set split [string last {) } $text]
    require [expr {$split>=0}]
    set fields [regexp -all -inline {\S+} [string range $text [expr {$split+2}] end]]
    require [expr {[llength $fields]>=20 && [regexp {^[0-9]{1,32}$} [lindex $fields 19]]}]
    if {[lindex $fields 0] eq {Z}} {return {}}
    # Fixed public root-owned procfs identity only; private read guards stay intact.
    set bootPath /proc/sys/kernel/random/boot_id
    file lstat $bootPath bootInfo
    require [expr {$bootInfo(type) eq {file} && $bootInfo(nlink)==1 && $bootInfo(size)<=64}]
    set channel [open $bootPath rb]
    try {set rawBoot [::read $channel 65]} finally {close $channel}
    require [expr {[string length $rawBoot]<=64}]
    set boot [string trim $rawBoot]
    require [regexp {^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$} $boot]
    return "${boot}:[lindex $fields 19]"
}
proc ::GX210NullQA::retired {row} {
    set identities [dict get $row process_identities]
    if {[dict exists $row worker_pid] && [dict exists $row pid_start]} {dict set identities [dict get $row worker_pid] [dict get $row pid_start]}
    require [expr {[dict size $identities]>0 && [dict size $identities]<=256}]
    set result {}
    dict for {pid expected} $identities {
        require [regexp {^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9]{1,32}$} $expected]
        set actual [processStart $pid]
        dict set result $pid [dict create expected_start $expected observed_start $actual]
        require [expr {$actual ne $expected}]
    }
    return $result
}
proc ::GX210NullQA::survey {} {
    variable session;variable hashes
    admit
    set view [dict replace [::GX::scriptJobViewDefault] scope $session filter All show_hidden 1 sort jobid descending 0]
    set page [::GX::scriptJobViewList $view 0]
    set jobs [dict get $page jobs];set count [llength $jobs]
    require [expr {$count<=2 && [dict get $page offset]==0 && [dict get $page limit]==500 &&
        [dict get $page matching]==$count && [dict get $page total_scoped]==$count}]
    set result {};set references {}
    foreach row $jobs {
        set ref [dict get $row reference]
        require [expr {$ref in {session:null-wire-python session:null-wire-octave} && $ref ni $references}]
        lappend references $ref
        set key [expr {$ref eq {session:null-wire-python}?{python}:{octave}}]
        set id [dict get $row id]
        require [expr {[regexp {^script-[A-Za-z0-9-]+$} $id] && [string length $id]<=160 && ![dict exists $result $id]}]
        set inspected [::GX::scriptJobInspect $id]
        foreach item [list $row $inspected] {
            require [expr {[dict get $item id] eq $id && [dict get $item run_id] eq $id &&
                [dict get $item session] eq $session && [dict get $item reference] eq $ref &&
                [dict get $item language] eq [string totitle $key] &&
                [dict get $item source_sha256] eq [dict get $hashes $key] &&
                [dict get $item origin] eq {user_script} &&
                [dict get $item output_dir] eq [file join $session analysis scripts $id]}]
        }
        dict set result $id [projection $inspected]
    }
    return [dict create complete 1 offset 0 limit 500 matching $count total_scoped $count returned $count jobs $result]
}
proc ::GX210NullQA::reconcile {} {
    variable cleanup;variable deadline
    set cleanup [dict create status UNKNOWN scope exact_new_private_session_references jobs {}]
    set before [survey]
    dict set cleanup survey_before $before
    dict for {id row} [dict get $before jobs] {
        admit 2000
        if {[dict get $row state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {::GX::scriptJobCancel $id}
        set current [::GX::scriptJobDescribe $id]
        while {[dict get $current state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {
            admit 2000;after 100
            set current [::GX::scriptJobDescribe $id]
        }
        set final [::GX::scriptJobWait $id 1]
        foreach key {id run_id reference language source_sha256 output_dir} {require [expr {[dict get $final $key] eq [dict get $row $key]}]}
        dict set cleanup jobs $id [dict create terminal [projection $final] retired [retired $final]]
    }
    set after [survey]
    require [expr {[lsort [dict keys [dict get $before jobs]]] eq [lsort [dict keys [dict get $after jobs]]]}]
    dict set cleanup survey_after $after
    if {$::GX210NullQA::status eq {PASS}} {
        set expected [lmap key {python octave} {dict get $::GX210NullQA::runs $key id}]
        require [expr {[lsort [dict keys [dict get $after jobs]]] eq [lsort $expected]}]
    }
    dict set cleanup status PASS
}
set argv0 __task210_explicit_null_registered__
namespace eval ::GX210NullQA {
try {
    require [expr {[string is wideinteger -strict $deadline] && $deadline<[clock milliseconds]+180000}]
    admit 140000
    require [expr {[file normalize $framework] eq $framework && [file normalize $output] eq $output &&
        [file isdirectory $output] && ([file attributes $output -permissions]&0777)==0700}]
    foreach {name leaf} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {
        require [expr {[info exists ::env($name)] && $::env($name) eq [file join $output $leaf]}]
    }
    set phase initialize_entry_global_source
    uplevel #0 [list source [file join $framework gxtxt_pipeline.tcl]]
    set phase initialize_defaults
    ::GX::defaults
    set phase initialize_configuration_load
    ::GX::configurationLoad
    set phase initialize_catalog
    ::GX::loadModuleCatalog
    set phase initialize_noTk
    require [expr {![llength [info commands winfo]]}]
    set phase initialize_noSession
    require [expr {$::GX::currentSession eq {}}]
    set sessionRoot [file join $output Sessions];file mkdir $sessionRoot;file attributes $sessionRoot -permissions 0700
    ::GX::configurationSet storage.session_root $sessionRoot
    foreach {key leaf} {storage.temp_dir config_tmp storage.cache_dir config_cache storage.export_dir Exports scripts.user_root user_scripts} {
        set target [file join $output $leaf];file mkdir $target;file attributes $target -permissions 0700
        ::GX::configurationSet $key $target
    }
    ::GX::configurationSet libraries.scientific_root [file join $output Library]
    ::GX::configurationSet runtime.python /usr/bin/python3
    ::GX::configurationSet runtime.octave /usr/bin/octave-cli
    ::GX::configurationSave {storage.session_root storage.temp_dir storage.cache_dir storage.export_dir scripts.user_root libraries.scientific_root runtime.python runtime.octave}
    require [expr {[string first "${output}/" [file normalize [::GX::configurationPath]]]==0}]
    set phase create_session
    set session [::GX::createNewSession TASK210_NULL_WIRE_SYNTHETIC {} 0]
    require [expr {[string first "${sessionRoot}/" $session]==0 && [::GX::sessionInspectionCurrentSession] eq $session}]
    foreach {key ext} {python py octave m} {dict set hashes $key [::GX::sha256File [file join $here caller.$ext]]}
    require [expr {[dict size [dict get [survey] jobs]]==0}]
    foreach {key language ext} {python Python py octave Octave m} {
        set phase ${key}_import;admit 75000
        set imported [::GX::scriptRegistryImportSource $session [file join $here caller.$ext] null-wire-$key "Explicit null $language QA" $language {Synthetic null transport qualification only; no scientific producer.}]
        require [expr {[dict get $imported outcome] eq {registered_session_script} && ![dict get $imported executed] && [dict get $imported sha256] eq [dict get $hashes $key]}]
        set ref [dict get $imported reference]
        set metadata [::GX::scriptRegistryDescribe $ref $session]
        require [expr {[dict get $metadata language] eq $language && [dict get $metadata sha256] eq [dict get $hashes $key] && [dict size [dict get $metadata parameters]]==0}]
        set phase ${key}_submit;admit 70000
        set submitted [::GX::scriptJobSubmit $ref {} [dict create session $session]]
        set active [dict get $submitted id]
        require [expr {![dict exists $submitted deduplicated] && [dict get $submitted run_id] eq $active}]
        dict set runs $key [projection $submitted]
        write [file join $output ${key}_SUBMITTED.tcldict] [projection $submitted]
        set phase ${key}_wait
        set terminal [::GX::scriptJobWait $active 60]
        dict set runs $key [projection $terminal]
        require [expr {[dict get $terminal state] eq {COMPLETED} && ![dict get $terminal wait_cancel_requested]}]
        set phase ${key}_inspect
        set inspected [::GX::scriptExecutionInspectRun $session $active]
        require [expr {[dict get $inspected id] eq $active && [dict get $inspected state] eq {COMPLETED} &&
            [dict get $inspected reference] eq $ref && [dict get $inspected language] eq $language &&
            [dict get $inspected source_sha256] eq [dict get $hashes $key] &&
            [dict get $inspected snapshot_validation] eq {verified} && [dict get $inspected origin] eq {user_script} &&
            [dict get $inspected output_dir] eq [file join $session analysis scripts $active]}]
        set folder [dict get $inspected output_dir]
        read [file join $folder execution.ini] 65536
        set execution [::GX::parseIni [file join $folder execution.ini]]
        require [expr {[string trim [dict get $execution execution.status]] eq {PASS} &&
            [string trim [dict get $execution execution.run_id]] eq $active}]
        set summary [read [file join $folder null_${key}.summary.tcldict] 4096]
        require [expr {[lsort [dict keys $summary]] eq {identity language nulls scalar_types schema sidecar status} &&
            [dict get $summary schema] eq {gxtxt.task210.script_bridge_null.caller.v1} &&
            [dict get $summary status] eq {PASS} && [dict get $summary language] eq $language}]
        foreach check {nulls identity scalar_types sidecar} {require [expr {[dict get $summary $check]==1}]}
        read [file join $folder null_${key}.json] 32768
        dict set runs $key summary $summary
        dict set runs $key report_sha256 [::GX::sha256File [file join $folder null_${key}.json]]
        dict set runs $key identities_retired [retired $terminal]
        dict set checks $key 1
        set active {}
    }
    set status PASS;set phase complete
} on error {message options} {
    # Finite phase only, never caught text/options/errorinfo/private data.
    set status FAIL
} finally {
    if {$session ne {}} {
        if {[catch {reconcile}]} {if {$status eq {PASS}} {set phase cleanup};set status FAIL}
    }
    if {$cleanup eq {} || ![dict exists $cleanup status] || [dict get $cleanup status] ne {PASS}} {set status FAIL}
    write [file join $output REGISTERED_RESULT.tcldict] [dict create schema gxtxt.task210.script_bridge_null.registered.v1 status $status failure_phase $phase checks $checks session $session runs $runs cleanup $cleanup whole_step5_accepted 0 GUI_accepted 0]
}
exit [expr {$status eq {PASS}?0:1}]
}
