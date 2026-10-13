# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CacheStorage {variable ui; variable rows {}; variable pending {}; variable busy 0}
proc ::GX::cacheStoragePanelBuild {notebook} {
    variable ::GX::CacheStorage::ui
    set f $notebook.cache_storage
    ttk::frame $f -padding 8
    $notebook add $f -text {Cache & Temporary Storage}
    set ui(frame) $f
    set ui(summary) {Refresh to inspect registered framework resources. Rescan also measures known subsystem storage.}
    set ui(status) {Cleanup is selective: active resources, unknown ownership and scientific data are protected.}
    ttk::label $f.summary -textvariable ::GX::CacheStorage::ui(summary) -justify left -wraplength 1000
    pack $f.summary -fill x -pady 4
    ttk::frame $f.actions
    ttk::button $f.actions.refresh -text Refresh -command {::GX::cacheStoragePanelRefresh 0}
    ttk::button $f.actions.rescan -text {Refresh / rescan} -command {::GX::cacheStoragePanelRefresh 1}
    ttk::button $f.actions.clean -text {Clean eligible selection} -command ::GX::cacheStoragePanelClean
    ttk::button $f.actions.jobs -text {Script Jobs…} -command ::GX::scriptJobsDialog
    pack $f.actions.refresh $f.actions.rescan $f.actions.clean $f.actions.jobs -side left -padx 3
    pack $f.actions -fill x -pady 5
    ttk::frame $f.list
    ttk::treeview $f.list.tree -columns {state subsystem bytes count job session age retention cleanup} -show headings -selectmode extended
    foreach {key title width} {state State 135 subsystem Subsystem 140 bytes Bytes 100 count Files 65 job Job 150 session Session 170 age {Age (s)} 85 retention {Retention (s)} 95 cleanup Cleanup 80} {
        $f.list.tree heading $key -text $title
        $f.list.tree column $key -width $width -stretch 1
    }
    ttk::scrollbar $f.list.sy -orient vertical -command [list $f.list.tree yview]
    ttk::scrollbar $f.list.sx -orient horizontal -command [list $f.list.tree xview]
    $f.list.tree configure -yscrollcommand [list $f.list.sy set] -xscrollcommand [list $f.list.sx set]
    grid $f.list.tree -row 0 -column 0 -sticky nsew
    grid $f.list.sy -row 0 -column 1 -sticky ns
    grid $f.list.sx -row 1 -column 0 -sticky ew
    grid rowconfigure $f.list 0 -weight 1
    grid columnconfigure $f.list 0 -weight 1
    pack $f.list -fill both -expand 1
    bind $f.list.tree <<TreeviewSelect>> ::GX::cacheStoragePanelSelection
    ttk::label $f.details -textvariable ::GX::CacheStorage::ui(details) -wraplength 1000 -justify left
    set ui(details) {Select a resource for its exact path, owner and cleanup decision.}
    pack $f.details -fill x -pady 5
    ttk::labelframe $f.policy -text {Allocation and retention policy} -padding 6
    set ui(max_mib) 10240
    set ui(retention_days) 7
    ttk::label $f.policy.limitLabel -text {Known allocation budget (MiB; 0 = unlimited)}
    ttk::entry $f.policy.limit -textvariable ::GX::CacheStorage::ui(max_mib) -width 10
    ttk::label $f.policy.retentionLabel -text {Diagnostic default retention (days)}
    ttk::entry $f.policy.retention -textvariable ::GX::CacheStorage::ui(retention_days) -width 8
    ttk::button $f.policy.save -text {Save storage policy} -command ::GX::cacheStoragePanelSavePolicy
    pack $f.policy.limitLabel $f.policy.limit $f.policy.retentionLabel $f.policy.retention $f.policy.save -side left -padx 4
    pack $f.policy -fill x -pady 5
    ttk::label $f.note -text {Only CORE-created allocations with a verified release or dead owner can be cleaned. Legacy caches and authoritative records use their subsystem's own cleanup. No automatic disk cleanup runs. Counts include known resources; native in-memory graphics remain with their viewers.} -wraplength 1000 -justify left
    pack $f.note -fill x -pady 4
    ttk::label $f.status -textvariable ::GX::CacheStorage::ui(status) -wraplength 1000 -justify left
    pack $f.status -fill x
    bind $f <Map> {if {!$::GX::CacheStorage::busy} {::GX::cacheStoragePanelRefresh 0}}
    bind $f <Configure> [list ::GX::cacheStoragePanelResize $f %w]
}
proc ::GX::cacheStoragePanelResize {f width} {
    foreach widget {summary details note status} {$f.$widget configure -wraplength [expr {max(240,$width-30)}]}
}
proc ::GX::cacheStoragePanelBusy {busy} {
    set ::GX::CacheStorage::busy $busy
    set f $::GX::CacheStorage::ui(frame)
    foreach widget [list $f.actions.refresh $f.actions.rescan $f.actions.clean $f.policy.save] {
        if {[winfo exists $widget]} {$widget configure -state [expr {$busy ? "disabled" : "normal"}]}
    }
}
proc ::GX::cacheStoragePanelRefresh {{rescan 0}} {
    if {$::GX::CacheStorage::busy} return
    cacheStoragePanelBusy 1
    set ::GX::CacheStorage::ui(status) {Reading resource ownership and storage...}
    set ::GX::CacheStorage::pending [expr {$rescan ? [resourceManagementLegacyPaths] : {}}]
    set ::GX::CacheStorage::ui(rescan) $rescan
    cacheStoragePanelNextObservation 0 {}
}
proc ::GX::cacheStoragePanelNextObservation {code output} {
    variable ::GX::CacheStorage::pending
    if {$code} {set ::GX::CacheStorage::ui(status) "Inventory warning: $output"}
    if {[llength $pending]} {
        set item [lindex $pending 0]
        set pending [lrange $pending 1 end]
        if {[catch {resourceManagementAsync observe $item ::GX::cacheStoragePanelNextObservation} error]} {cacheStoragePanelLoaded 1 $error}
    } else {
        if {[catch {resourceManagementAsync inventory [list rescan $::GX::CacheStorage::ui(rescan)] ::GX::cacheStoragePanelLoaded} error]} {cacheStoragePanelLoaded 1 $error}
    }
}
proc ::GX::cacheStoragePanelLoaded {code output} {
    variable ::GX::CacheStorage::ui
    variable ::GX::CacheStorage::rows
    cacheStoragePanelBusy 0
    if {$code || [catch {dict get $output resources} resources]} {set ui(status) "Resource inspection failed: $output"; return}
    set tree $ui(frame).list.tree
    $tree delete [$tree children {}]
    set rows {}
    foreach record $resources {
        set id [dict get $record id]
        dict set rows $id $record
        set age [expr {int([clock seconds]-[dict get $record created])}]
        $tree insert {} end -id $id -values [list [dict get $record state] [dict get $record subsystem] [dict get $record bytes] [dict get $record count] \
            [dict get $record job_id] [dict get $record session] $age [dict get $record retention_seconds] [expr {[dict get $record eligible] ? "Eligible" : "Protected"}]]
    }
    set summary [dict get $output summary]
    set groups {}
    dict for {name values} [dict get $summary categories] {lappend groups "$name: [dict get $values resources] ([dict get $values bytes] bytes)"}
    set ui(summary) "Known: [dict get $summary resources] resources, [dict get $summary count] files, [dict get $summary bytes] bytes. Recoverable: [dict get $summary reclaimable_bytes] bytes.\n[join $groups {; }]"
    set ui(status) "Inspection complete. Resource registry: [dict get $output root]. Cleanup rechecks ownership and filesystem identity."
    catch {resourceManagementAsync policy {} ::GX::cacheStoragePanelPolicyLoaded}
}
proc ::GX::cacheStoragePanelPolicyLoaded {code output} {
    if {$code} return
    if {[dict exists $output max_bytes]} {set ::GX::CacheStorage::ui(max_mib) [expr {[dict get $output max_bytes]/1048576}]}
    if {[dict exists $output retention_seconds]} {set ::GX::CacheStorage::ui(retention_days) [expr {[dict get $output retention_seconds]/86400}]}
}
proc ::GX::cacheStoragePanelSelection {} {
    variable ::GX::CacheStorage::ui
    set ids [$ui(frame).list.tree selection]
    if {![llength $ids]} return
    set record [dict get $::GX::CacheStorage::rows [lindex $ids 0]]
    set ui(details) "[dict get $record path]\nOwner: [dict get $record subsystem], PID [dict get $record owner_pid]; lifetime: [dict get $record lifetime]. [dict get $record reason]"
}
proc ::GX::cacheStoragePanelClean {} {
    variable ::GX::CacheStorage::ui
    if {$::GX::CacheStorage::busy} return
    set ids [$ui(frame).list.tree selection]
    if {![llength $ids]} {set ui(status) {Select verified eligible resources to clean.}; return}
    foreach id $ids {
        if {![dict get $::GX::CacheStorage::rows $id eligible]} {set ui(status) {Selection contains active, retained, recovery or unknown resources. Select only eligible rows.}; return}
    }
    cacheStoragePanelBusy 1
    if {[catch {resourceManagementAsync cleanup $ids ::GX::cacheStoragePanelCleaned} error]} {cacheStoragePanelCleaned 1 $error}
}
proc ::GX::cacheStoragePanelCleaned {code output} {
    cacheStoragePanelBusy 0
    set ::GX::CacheStorage::ui(status) [expr {$code ? "Cleanup failed: $output" : "Cleanup recorded: $output"}]
    if {!$code} {cacheStoragePanelRefresh 0}
}
proc ::GX::cacheStoragePanelSavePolicy {} {
    variable ::GX::CacheStorage::ui
    foreach key {max_mib retention_days} {
        if {![string is entier -strict $ui($key)] || $ui($key)<0} {set ui(status) {Budget and retention must be nonnegative integers.}; return}
    }
    if {[catch {resourceManagementPolicy [list max_bytes [expr {$ui(max_mib)*1048576}] retention_seconds [expr {$ui(retention_days)*86400}]]} error]} {
        set ui(status) "Storage policy was not saved: $error"
    } else {set ui(status) {Storage policy saved. Applies to new allocations; existing resource retention remains explicit.}}
}
