# SPDX-License-Identifier: GPL-3.0-or-later
# Configuration child presentation; all mutable state belongs to public owners.
namespace eval ::GX::MaintenanceUI {variable ui;variable rows {};variable generation 0;variable diagnosticRequest {};variable diagnosticTimer {}}
proc ::GX::frameworkMaintenanceBuild notebook {
    set f $notebook.maintenance
    ttk::frame $f
    $notebook add $f -text {Framework Maintenance}
    ttk::frame $f.navigation -padding 6
    ttk::frame $f.content -padding 8
    pack $f.navigation -side left -fill y
    pack $f.content -side left -fill both -expand 1
    set ::GX::MaintenanceUI::ui(frame) $f
    set ::GX::MaintenanceUI::ui(scope) user
    set ::GX::MaintenanceUI::ui(query) {}
    set ::GX::MaintenanceUI::ui(orphan_policy) {}
    set ::GX::MaintenanceUI::ui(log_filter) {}
    set ::GX::MaintenanceUI::ui(log_cursor) {}
    set ::GX::MaintenanceUI::ui(section) {}
    set ::GX::MaintenanceUI::ui(preview_epoch) 0
    set ::GX::MaintenanceUI::ui(cache_epoch) 0
    bind $f <Destroy> [list ::GX::_maintenanceGuiDestroyed $f %W]
    foreach {id title} {status {Framework Status} cache {Cache & Temporary Files} diagnostics {Logs & Diagnostics} backup {Backup & Restore} catalog {API Catalog} modules {Modules & Plugins} configuration {Configuration Browser}} {
        ttk::button $f.navigation.$id -text $title -width 25 -command [list ::GX::frameworkMaintenanceSelect $id]
        pack $f.navigation.$id -fill x -pady 3
    }
    frameworkMaintenanceSelect status
}
proc ::GX::_maintenanceGuiRetire {} {
    incr ::GX::MaintenanceUI::generation
    if {$::GX::MaintenanceUI::diagnosticTimer ne {}} {after cancel $::GX::MaintenanceUI::diagnosticTimer;set ::GX::MaintenanceUI::diagnosticTimer {}}
    if {$::GX::MaintenanceUI::diagnosticRequest ne {}} {
        set request $::GX::MaintenanceUI::diagnosticRequest;set ::GX::MaintenanceUI::diagnosticRequest {}
        catch {stderrDiagnostics cancel $request};after 0 [list ::GX::_maintenanceGuiDiagnosticReap $request]
    }
}
proc ::GX::_maintenanceGuiDestroyed {frame actual} {if {$frame eq $actual} {_maintenanceGuiRetire}}
proc ::GX::_maintenanceGuiInvalidatePreview {} {
    variable ::GX::MaintenanceUI::ui
    incr ui(preview_epoch);set ui(preview) {}
    set button $ui(frame).content.actions.confirm
    if {[winfo exists $button]} {$button state disabled}
}
proc ::GX::frameworkMaintenanceSelect section {
    variable ::GX::MaintenanceUI::ui
    if {$section ni {status cache diagnostics backup catalog modules configuration}} {error {Unknown Maintenance section}}
    _maintenanceGuiRetire
    _maintenanceGuiInvalidatePreview
    set ui(section) $section;set ui(preview) {};set ui(status) {Read-only inspection. Preview and confirmation precede changes.}
    set ::GX::MaintenanceUI::rows {}
    set p $ui(frame).content
    foreach child [winfo children $p] {destroy $child}
    foreach {id title} {status {Framework Status} cache {Cache & Temporary Files} diagnostics {Logs & Diagnostics} backup {Backup & Restore} catalog {API Catalog} modules {Modules & Plugins} configuration {Configuration Browser}} {
        $ui(frame).navigation.$id state [expr {$id eq $section ? {pressed} : {!pressed}}]
        if {$id eq $section} {set heading $title}
    }
    if {$section eq {catalog}} {
        if {[llength [info commands ::GX::frameworkMaintenanceCatalogBuild]]} {frameworkMaintenanceCatalogBuild $p} else {ttk::label $p.pending -text {API Catalog maintenance is unavailable in this source batch.};pack $p.pending -anchor w}
        return
    }
    ttk::label $p.title -text $heading -font TkHeadingFont
    pack $p.title -anchor w -pady {0 7}
    ttk::frame $p.actions
    pack $p.actions -fill x -pady 4
    ttk::label $p.status -textvariable ::GX::MaintenanceUI::ui(status) -wraplength 680 -justify left
    pack $p.status -side bottom -fill x -pady 5
    bind $p.status <Configure> [list ::GX::_maintenanceGuiStatusWrap $p.status %w]
    switch $section {
        status {frameworkMaintenanceStatusBuild $p}
        cache {frameworkMaintenanceCacheBuild $p}
        diagnostics {frameworkMaintenanceDiagnosticsBuild $p}
        backup {frameworkMaintenanceBackupBuild $p}
        modules {frameworkMaintenanceModulesBuild $p}
        configuration {frameworkMaintenanceConfigurationBuild $p}
    }
    bind $p.actions <Configure> [list ::GX::uiFieldControlsLayout $p.actions %w]
}
proc ::GX::_maintenanceGuiStatusWrap {label width} {
    # Sidebar allocation varies with root size/fonts; guidance must wrap inside
    # its actual label rather than retaining a wider nominal content width.
    if {![winfo exists $label] || $width<=1} return
    set length [expr {max(1,$width-4)}]
    if {[$label cget -wraplength]!=$length} {$label configure -wraplength $length}
}
proc ::GX::_maintenanceGuiButton {parent id text command} {
    ttk::button $parent.$id -text $text -command $command
    pack $parent.$id -side left -padx 3 -pady 3
    return $parent.$id
}
proc ::GX::_maintenanceGuiText parent {
    ttk::frame $parent.report
    text $parent.report.text -wrap word -height 10 -width 30 -state disabled
    ttk::scrollbar $parent.report.scroll -command [list $parent.report.text yview]
    $parent.report.text configure -yscrollcommand [list $parent.report.scroll set]
    pack $parent.report.scroll -side right -fill y
    pack $parent.report.text -fill both -expand 1
    pack $parent.report -fill both -expand 1 -pady 5
    set ::GX::MaintenanceUI::ui(report) $parent.report.text
}
proc ::GX::_maintenanceGuiReport {value {structured 1}} {
    set widget $::GX::MaintenanceUI::ui(report)
    if {![winfo exists $widget]} return
    $widget configure -state normal;$widget delete 1.0 end
    if {$structured && ![catch {dict size $value}]} {dict for {key content} $value {$widget insert end "$key:\n$content\n\n"}} else {$widget insert end $value}
    $widget configure -state disabled
}
proc ::GX::_maintenanceGuiTry command {
    # Every new receipt replaces the visible diff, including failed imports.
    # Never leave an earlier hidden plan confirmable behind that replacement.
    _maintenanceGuiInvalidatePreview
    unset -nocomplain ::GX::MaintenanceUI::ui(backup_preview)
    if {$::GX::MaintenanceUI::ui(section) eq {backup}} {
        set button $::GX::MaintenanceUI::ui(frame).content.actions.export
        if {[winfo exists $button]} {$button state disabled}
    }
    set code [catch {uplevel #0 $command} value]
    set ::GX::MaintenanceUI::ui(status) [expr {$code ? "Operation refused or failed: $value" : {Operation completed; inspect the receipt below.}}]
    _maintenanceGuiReport $value [expr {!$code}]
    return [list $code $value]
}
proc ::GX::_maintenanceGuiConfirm {title message} {
    return [expr {[tk_messageBox -parent $::GX::MaintenanceUI::ui(frame) -title $title -message $message -icon question -type okcancel -default cancel] eq {ok}}]
}
proc ::GX::_maintenanceGuiTree {parent columns} {
    ttk::frame $parent.list
    ttk::treeview $parent.list.tree -columns [dict keys $columns] -show headings -height 8 -selectmode extended
    dict for {key title} $columns {$parent.list.tree heading $key -text $title;$parent.list.tree column $key -width 135 -minwidth 80}
    ttk::scrollbar $parent.list.y -command [list $parent.list.tree yview]
    ttk::scrollbar $parent.list.x -orient horizontal -command [list $parent.list.tree xview]
    $parent.list.tree configure -yscrollcommand [list $parent.list.y set] -xscrollcommand [list $parent.list.x set]
    grid $parent.list.tree -row 0 -column 0 -sticky nsew
    grid $parent.list.y -row 0 -column 1 -sticky ns
    grid $parent.list.x -row 1 -column 0 -sticky ew
    grid rowconfigure $parent.list 0 -weight 1;grid columnconfigure $parent.list 0 -weight 1
    pack $parent.list -fill both -expand 1 -pady 4
    set ::GX::MaintenanceUI::ui(tree) $parent.list.tree
    bind $parent.list.tree <<TreeviewSelect>> ::GX::_maintenanceGuiSelected
}
proc ::GX::_maintenanceGuiSelected {} {
    variable ::GX::MaintenanceUI::ui
    if {$ui(section) in {cache configuration modules}} {_maintenanceGuiInvalidatePreview}
    if {$ui(section) eq {diagnostics}} {_maintenanceGuiInvalidateDiagnostics}
    set selected [$ui(tree) selection]
    if {[llength $selected]!=1} return
    set row [dict get $::GX::MaintenanceUI::rows [lindex $selected 0]]
    _maintenanceGuiReport $row
    if {$ui(section) eq {configuration}} {set ui(value) [dict get $row [expr {$ui(scope) eq {session} ? {effective} : {user}}]]}
}
proc ::GX::frameworkMaintenanceStatusBuild parent {
    _maintenanceGuiButton $parent.actions inspect {Inspect executed framework} {::GX::_maintenanceGuiTry ::GX::frameworkMaintenanceStatus}
    _maintenanceGuiText $parent
    _maintenanceGuiTry ::GX::frameworkMaintenanceStatus
}
proc ::GX::frameworkMaintenanceCacheBuild parent {
    _maintenanceGuiButton $parent.actions inspect {Inspect / measure} ::GX::frameworkMaintenanceCacheInspect
    _maintenanceGuiButton $parent.actions preview {Preview cleanup} ::GX::frameworkMaintenanceCachePlan
    _maintenanceGuiButton $parent.actions confirm {Confirm selected cleanup…} ::GX::frameworkMaintenanceCacheCommit
    $parent.actions.confirm state disabled
    _maintenanceGuiTree $parent {category Category state State owner_pid {Owner PID} bytes Bytes count Files eligible Eligible path Path}
    _maintenanceGuiText $parent
    _maintenanceGuiReport {policy {Only verified released reconstructible caches or owned disposable temporary allocations can be selected. Scientific/native Workspace data, active leases and unowned paths are protected. Unknown reference counts remain unknown.}}
}
proc ::GX::frameworkMaintenanceCacheInspect {} {
    _maintenanceGuiInvalidatePreview
    set epoch [incr ::GX::MaintenanceUI::ui(cache_epoch)]
    set ::GX::MaintenanceUI::ui(status) {Inspecting registered owner resources…}
    set items [resourceManagementLegacyPaths]
    ::GX::_maintenanceGuiCacheObserve $::GX::MaintenanceUI::generation $epoch $items 0 {}
}
proc ::GX::_maintenanceGuiCacheObserve {generation epoch items code output} {
    if {$generation!=$::GX::MaintenanceUI::generation || $epoch!=$::GX::MaintenanceUI::ui(cache_epoch)} return
    if {$code} {_maintenanceGuiAsyncResult $generation $code $output;return}
    if {[llength $items]} {
        set row [lindex $items 0]
        set args [list path [dict get $row path] subsystem [dict get $row subsystem] category [dict get $row category]]
        foreach key {recovery_required session} {if {[dict exists $row $key]} {lappend args $key [dict get $row $key]}}
        resourceManagementAsync observe $args [list ::GX::_maintenanceGuiCacheObserve $generation $epoch [lrange $items 1 end]]
    } else {resourceManagementAsync inventory {rescan 1} [list ::GX::_maintenanceGuiCacheLoaded $generation $epoch]}
}
proc ::GX::_maintenanceGuiCacheLoaded {generation epoch code output} {
    if {$generation!=$::GX::MaintenanceUI::generation || $epoch!=$::GX::MaintenanceUI::ui(cache_epoch)} return
    if {$code} {_maintenanceGuiAsyncResult $generation $code $output;return}
    _maintenanceGuiInvalidatePreview
    set tree $::GX::MaintenanceUI::ui(tree);$tree delete [$tree children {}]
    foreach row [dict get $output resources] {
        set id [dict get $row id];dict set ::GX::MaintenanceUI::rows $id $row
        set values {};foreach key {category state owner_pid bytes count eligible path} {lappend values [dict get $row $key]}
        $tree insert {} end -id $id -values $values
    }
    set ::GX::MaintenanceUI::ui(status) {Inventory measured. Select eligible owned disposable resources, then preview.}
    _maintenanceGuiReport [dict get $output summary]
}
proc ::GX::frameworkMaintenanceCachePlan {} {
    _maintenanceGuiInvalidatePreview
    set ids [$::GX::MaintenanceUI::ui(tree) selection]
    if {[catch {frameworkMaintenanceCachePreview $ids [list ::GX::_maintenanceGuiPlanDone $::GX::MaintenanceUI::generation $::GX::MaintenanceUI::ui(preview_epoch)]} reason]} {set ::GX::MaintenanceUI::ui(status) $reason}
}
proc ::GX::_maintenanceGuiPlanDone {generation epoch code output} {
    if {$generation!=$::GX::MaintenanceUI::generation || $epoch!=$::GX::MaintenanceUI::ui(preview_epoch)} return
    _maintenanceGuiAsyncResult $generation $code $output
    if {!$code} {set ::GX::MaintenanceUI::ui(preview) [dict get $output token];$::GX::MaintenanceUI::ui(frame).content.actions.confirm state !disabled}
}
proc ::GX::frameworkMaintenanceCacheCommit {} {
    set token $::GX::MaintenanceUI::ui(preview)
    if {$token eq {} || ![_maintenanceGuiConfirm {Clean selected cache resources} {Remove only the exact eligible allocations listed in the preview? Ownership and active leases will be checked again.}]} return
    if {[catch {frameworkMaintenanceCacheCleanup $token [list ::GX::_maintenanceGuiAsyncResult $::GX::MaintenanceUI::generation]} reason]} {set ::GX::MaintenanceUI::ui(status) $reason}
    set ::GX::MaintenanceUI::ui(preview) {};$::GX::MaintenanceUI::ui(frame).content.actions.confirm state disabled
}
proc ::GX::_maintenanceGuiAsyncResult {generation code output} {
    if {$generation!=$::GX::MaintenanceUI::generation} return
    set ::GX::MaintenanceUI::ui(status) [expr {$code ? "Operation refused or failed: $output" : {Owner operation completed. Inspect exact outcomes below.}}]
    set structured [expr {!$code}]
    if {$code && ![catch {dict size $output}] && ([dict exists $output state] || [dict exists $output error])} {set structured 1}
    _maintenanceGuiReport $output $structured
}
proc ::GX::frameworkMaintenanceDiagnosticsBuild parent {
    foreach {id title command} {read {Read next page} {::GX::frameworkMaintenanceDiagnosticsRead 0} first {Read first page} {::GX::frameworkMaintenanceDiagnosticsRead 1} meta {Inspect retained files} {::GX::frameworkMaintenanceDiagnosticsRequest meta} export {Export selected records…} ::GX::frameworkMaintenanceDiagnosticsExport preview {Preview diagnostic cleanup} {::GX::frameworkMaintenanceDiagnosticsRequest cleanup_preview} confirm {Confirm diagnostic cleanup…} ::GX::frameworkMaintenanceDiagnosticsCleanup} {_maintenanceGuiButton $parent.actions $id $title $command}
    $parent.actions.confirm state disabled
    ttk::frame $parent.filter
    ttk::label $parent.filter.label -text {Filter this bounded page:}
    ttk::entry $parent.filter.query -textvariable ::GX::MaintenanceUI::ui(log_filter)
    pack $parent.filter.label -side left;pack $parent.filter.query -fill x -expand 1
    pack $parent.filter -fill x
    bind $parent.filter.query <KeyRelease> ::GX::frameworkMaintenanceDiagnosticsFilter
    _maintenanceGuiTree $parent {id {Record ID} origin Component payload Message}
    _maintenanceGuiText $parent
    _maintenanceGuiReport [dict create diagnostics [stderrDiagnostics status] policy {Read/export and cleanup affect diagnostic STDERR records only. Stop capture explicitly before cleanup; active writers and unrecognized managed content are refused. Scientific Job logs, publication records and History are never cleanup targets.}]
}
proc ::GX::frameworkMaintenanceDiagnosticsRead first {
    if {$first} {set ::GX::MaintenanceUI::ui(log_cursor) {}}
    frameworkMaintenanceDiagnosticsRequest read $::GX::MaintenanceUI::ui(log_cursor) 100 524288
}
proc ::GX::frameworkMaintenanceDiagnosticsRequest {operation args} {
    if {$operation ne {cleanup}} {_maintenanceGuiInvalidateDiagnostics}
    if {$::GX::MaintenanceUI::diagnosticRequest ne {}} {set ::GX::MaintenanceUI::ui(status) {Wait for the active diagnostic request};return}
    if {[catch {set request [stderrDiagnostics $operation {*}$args]} reason]} {set ::GX::MaintenanceUI::ui(status) $reason;return}
    set ::GX::MaintenanceUI::diagnosticRequest $request
    set ::GX::MaintenanceUI::ui(status) "Diagnostics $operation is running…"
    set ::GX::MaintenanceUI::ui(diagnostic_started) [clock milliseconds]
    _maintenanceGuiDiagnosticPoll $::GX::MaintenanceUI::generation $operation $request
}
proc ::GX::_maintenanceGuiDiagnosticReap request {
    if {[catch {stderrDiagnostics request $request} result]} return
    if {[dict get $result state] eq {pending}} {after 50 [list ::GX::_maintenanceGuiDiagnosticReap $request]}
}
proc ::GX::_maintenanceGuiDiagnosticPoll {generation operation request} {
    if {$generation!=$::GX::MaintenanceUI::generation} return
    set ::GX::MaintenanceUI::diagnosticTimer {}
    if {[catch {set result [stderrDiagnostics request $request]} reason]} {set result [dict create state error message $reason]}
    if {[dict get $result state] eq {pending}} {
        if {[clock milliseconds]-$::GX::MaintenanceUI::ui(diagnostic_started)>60000} {catch {stderrDiagnostics cancel $request}}
        set ::GX::MaintenanceUI::diagnosticTimer [after 50 [list ::GX::_maintenanceGuiDiagnosticPoll $generation $operation $request]]
        return
    }
    set ::GX::MaintenanceUI::diagnosticRequest {}
    if {[dict get $result state] ne {done}} {_maintenanceGuiAsyncResult $generation 1 $result;return}
    set value [dict get $result result]
    if {$operation eq {read}} {
        set ::GX::MaintenanceUI::ui(log_cursor) [dict get $value cursor]
        set ::GX::MaintenanceUI::ui(log_records) [dict get $value records]
        frameworkMaintenanceDiagnosticsFilter
    }
    if {$operation eq {cleanup_preview}} {
        set guards {};foreach file [dict get $value files] {lappend guards [dict get $file guard]}
        set ::GX::MaintenanceUI::ui(log_guards) $guards;set ::GX::MaintenanceUI::ui(log_preview_time) [clock seconds]
        $::GX::MaintenanceUI::ui(frame).content.actions.confirm state !disabled
    }
    _maintenanceGuiAsyncResult $generation 0 $value
}
proc ::GX::frameworkMaintenanceDiagnosticsFilter {} {
    _maintenanceGuiInvalidateDiagnostics
    if {![info exists ::GX::MaintenanceUI::ui(log_records)]} return
    set tree $::GX::MaintenanceUI::ui(tree);$tree delete [$tree children {}]
    set query [string tolower $::GX::MaintenanceUI::ui(log_filter)]
    foreach record $::GX::MaintenanceUI::ui(log_records) {
        set payload [encoding convertfrom utf-8 [dict get $record payload]]
        if {$query ne {} && [string first $query [string tolower "$payload [dict get $record origin]"]]<0} continue
        set id [dict get $record record_id];dict set ::GX::MaintenanceUI::rows $id $record
        $tree insert {} end -id $id -values [list $id [datasetPublicationV2DictDefault [dict get $record origin] component unknown] [string range $payload 0 500]]
    }
}
proc ::GX::_maintenanceGuiInvalidateDiagnostics {} {
    unset -nocomplain ::GX::MaintenanceUI::ui(log_preview_time) ::GX::MaintenanceUI::ui(log_guards)
    set button $::GX::MaintenanceUI::ui(frame).content.actions.confirm
    if {[winfo exists $button]} {$button state disabled}
}
proc ::GX::frameworkMaintenanceDiagnosticsExport {} {
    set ids [$::GX::MaintenanceUI::ui(tree) selection]
    if {![llength $ids]} {set ::GX::MaintenanceUI::ui(status) {Select displayed records to export};return}
    set path [tk_getSaveFile -parent $::GX::MaintenanceUI::ui(frame) -title {Export diagnostic records} -defaultextension .jsonl]
    if {$path ne {}} {frameworkMaintenanceDiagnosticsRequest export [dict create record_ids $ids limit 4096 max_bytes 8388608] $path}
}
proc ::GX::frameworkMaintenanceDiagnosticsCleanup {} {
    if {![info exists ::GX::MaintenanceUI::ui(log_preview_time)] || [clock seconds]-$::GX::MaintenanceUI::ui(log_preview_time)>600} {set ::GX::MaintenanceUI::ui(status) {Inspect diagnostic cleanup again before confirming};return}
    if {![_maintenanceGuiConfirm {Clean diagnostic STDERR files} {Delete only the exact inactive diagnostic files listed in the preview? Changed files and active writers will be refused. Scientific Job logs and History are preserved.}]} return
    frameworkMaintenanceDiagnosticsRequest cleanup $::GX::MaintenanceUI::ui(log_guards)
    $::GX::MaintenanceUI::ui(frame).content.actions.confirm state disabled
}
proc ::GX::frameworkMaintenanceModulesBuild parent {
    _maintenanceGuiButton $parent.actions inspect Inspect ::GX::frameworkMaintenanceModulesInspect
    _maintenanceGuiButton $parent.actions disable {Preview minimal optional interface} {::GX::frameworkMaintenanceModulesPreview disable_optional}
    _maintenanceGuiButton $parent.actions restore {Preview previous states} {::GX::frameworkMaintenanceModulesPreview restore}
    _maintenanceGuiButton $parent.actions confirm {Confirm module changes…} ::GX::frameworkMaintenanceModulesCommit
    _maintenanceGuiButton $parent.actions manager {Plugin Manager…} ::GX::pluginManagerDialog
    $parent.actions.confirm state disabled
    _maintenanceGuiTree $parent {id Module version Version state State optional Optional depends Dependencies}
    _maintenanceGuiText $parent
    frameworkMaintenanceModulesInspect
}
proc ::GX::frameworkMaintenanceModulesInspect {} {
    _maintenanceGuiInvalidatePreview
    set tree $::GX::MaintenanceUI::ui(tree);$tree delete [$tree children {}]
    foreach row [frameworkMaintenanceModulesInventory] {
        set id [dict get $row module_id];dict set ::GX::MaintenanceUI::rows $id $row
        $tree insert {} end -id $id -values [list $id [dict get $row version] [dict get $row state] [dict get $row optional] [dict get $row depends]]
    }
    set ::GX::MaintenanceUI::ui(status) {CORE / ALWAYS and dependencies required by protected modules stay enabled. No installed packages are removed. Previous states are retained for this process.}
}
proc ::GX::frameworkMaintenanceModulesPreview operation {
    lassign [_maintenanceGuiTry [list ::GX::frameworkMaintenanceModulesPlan $operation]] code result
    if {!$code} {set ::GX::MaintenanceUI::ui(preview) [dict get $result token];$::GX::MaintenanceUI::ui(frame).content.actions.confirm state !disabled}
}
proc ::GX::frameworkMaintenanceModulesCommit {} {
    if {$::GX::MaintenanceUI::ui(preview) eq {} || ![_maintenanceGuiConfirm {Change optional module states} {Apply exactly the optional-module transitions listed in the preview? Dependencies and active operations will be checked again. This changes the current interface state, not installed packages.}]} return
    lassign [_maintenanceGuiTry [list ::GX::frameworkMaintenanceModulesApply $::GX::MaintenanceUI::ui(preview)]] code result
    set message $::GX::MaintenanceUI::ui(status)
    set ::GX::MaintenanceUI::ui(preview) {};$::GX::MaintenanceUI::ui(frame).content.actions.confirm state disabled
    frameworkMaintenanceModulesInspect
    set ::GX::MaintenanceUI::ui(status) $message
}
proc ::GX::frameworkMaintenanceBackupBuild parent {
    foreach {id text command} {inspect {Inspect ALL Projects / Sessions} {::GX::_maintenanceGuiTry ::GX::frameworkMaintenanceBackupInventory} preview {Preview complete backup} ::GX::frameworkMaintenanceBackupPreview export {Create one backup archive…} ::GX::frameworkMaintenanceBackupExportGui restore {Inspect backup for restore…} ::GX::frameworkMaintenanceBackupRestorePreview confirm {Confirm restore…} ::GX::frameworkMaintenanceBackupRestoreGui} {_maintenanceGuiButton $parent.actions $id $text $command}
    $parent.actions.export state disabled;$parent.actions.confirm state disabled
    ttk::labelframe $parent.policy -text {Explicit unassociated-Session policy}
    ttk::radiobutton $parent.policy.include -text {Include discovered unassociated Sessions} -variable ::GX::MaintenanceUI::ui(orphan_policy) -value include -command ::GX::_maintenanceGuiBackupPolicyChanged
    ttk::radiobutton $parent.policy.exclude -text {Exclude and list them in the backup manifest} -variable ::GX::MaintenanceUI::ui(orphan_policy) -value exclude -command ::GX::_maintenanceGuiBackupPolicyChanged
    pack $parent.policy.include $parent.policy.exclude -anchor w -padx 6 -pady 3
    pack $parent.policy -fill x -pady 5
    _maintenanceGuiText $parent
    _maintenanceGuiTry ::GX::frameworkMaintenanceBackupInventory
}
proc ::GX::_maintenanceGuiBackupPolicyChanged {} {
    unset -nocomplain ::GX::MaintenanceUI::ui(backup_preview)
    $::GX::MaintenanceUI::ui(frame).content.actions.export state disabled
    set ::GX::MaintenanceUI::ui(status) {Unassociated-Session policy changed. Inspect a new complete backup preview before export.}
}
proc ::GX::frameworkMaintenanceBackupPreview {} {
    lassign [_maintenanceGuiTry [list ::GX::frameworkMaintenanceBackupPlan $::GX::MaintenanceUI::ui(orphan_policy)]] code result
    if {!$code} {set ::GX::MaintenanceUI::ui(backup_preview) [dict get $result token];$::GX::MaintenanceUI::ui(frame).content.actions.export state !disabled}
}
proc ::GX::frameworkMaintenanceBackupProgress message {set ::GX::MaintenanceUI::ui(status) $message;update idletasks}
proc ::GX::frameworkMaintenanceBackupExportGui {} {
    if {![info exists ::GX::MaintenanceUI::ui(backup_preview)]} return
    set path [tk_getSaveFile -parent $::GX::MaintenanceUI::ui(frame) -title {Backup ALL Projects and associated Sessions} -defaultextension .zip]
    if {$path eq {} || ![_maintenanceGuiConfirm {Create complete backup} {Create one archive containing every Project and associated Session in the displayed preview, with the selected unassociated-Session policy? Foreign writers or changed sources will refuse publication.}]} return
    _maintenanceGuiTry [list ::GX::frameworkMaintenanceBackupExport $::GX::MaintenanceUI::ui(backup_preview) $path ::GX::frameworkMaintenanceBackupProgress]
    $::GX::MaintenanceUI::ui(frame).content.actions.export state disabled
}
proc ::GX::frameworkMaintenanceBackupRestorePreview {} {
    set path [tk_getOpenFile -parent $::GX::MaintenanceUI::ui(frame) -title {Inspect complete backup archive} -filetypes {{{ZIP archives} .zip}}]
    if {$path eq {}} return
    lassign [_maintenanceGuiTry [list ::GX::frameworkMaintenanceBackupRestorePlan $path]] code result
    if {!$code} {set ::GX::MaintenanceUI::ui(preview) [dict get $result token];$::GX::MaintenanceUI::ui(frame).content.actions.confirm state !disabled}
}
proc ::GX::frameworkMaintenanceBackupRestoreGui {} {
    if {$::GX::MaintenanceUI::ui(preview) eq {} || ![_maintenanceGuiConfirm {Restore backup into new identities} {Restore the inspected Projects and Sessions using new identities and non-overwriting destinations? All nested packages are validated first. If a later import fails, earlier committed imports are retained and identified in the receipt.}]} return
    _maintenanceGuiTry [list ::GX::frameworkMaintenanceBackupRestore $::GX::MaintenanceUI::ui(preview)]
    set ::GX::MaintenanceUI::ui(preview) {};$::GX::MaintenanceUI::ui(frame).content.actions.confirm state disabled
    catch {projectGuiRefresh};catch {projectRefreshExperimentUi}
}
proc ::GX::frameworkMaintenanceConfigurationBuild parent {
    ttk::frame $parent.filters
    ttk::label $parent.filters.searchL -text Search
    ttk::entry $parent.filters.search -textvariable ::GX::MaintenanceUI::ui(query)
    ttk::combobox $parent.filters.scope -state readonly -values {user session} -textvariable ::GX::MaintenanceUI::ui(scope) -width 10
    ttk::combobox $parent.filters.section -state readonly -textvariable ::GX::MaintenanceUI::ui(config_section) -width 20
    set groups {All};dict for {id field} [configurationFields] {lappend groups [dict get $field group]}
    $parent.filters.section configure -values [lsort -unique $groups];set ::GX::MaintenanceUI::ui(config_section) All
    pack $parent.filters.searchL $parent.filters.search $parent.filters.scope $parent.filters.section -side left -padx 3
    pack $parent.filters -fill x
    bind $parent.filters.search <KeyRelease> ::GX::frameworkMaintenanceConfigurationInspect
    bind $parent.filters.scope <<ComboboxSelected>> ::GX::frameworkMaintenanceConfigurationInspect
    bind $parent.filters.section <<ComboboxSelected>> ::GX::frameworkMaintenanceConfigurationInspect
    foreach {id text command} {inspect Inspect ::GX::frameworkMaintenanceConfigurationInspect export {Export scope…} ::GX::frameworkMaintenanceConfigurationExportGui import {Preview import…} ::GX::frameworkMaintenanceConfigurationImportGui field {Reset field…} {::GX::frameworkMaintenanceConfigurationReset field} section {Reset section…} {::GX::frameworkMaintenanceConfigurationReset section} all {Reset all in scope…} {::GX::frameworkMaintenanceConfigurationReset all} confirm {Confirm scoped changes…} ::GX::frameworkMaintenanceConfigurationCommit} {_maintenanceGuiButton $parent.actions $id $text $command}
    $parent.actions.confirm state disabled
    _maintenanceGuiTree $parent {id Field section Section effective Effective factory Factory user User override Session origin Origin scopes Scopes}
    ttk::frame $parent.edit
    ttk::label $parent.edit.label -text {Selected field value:}
    ttk::entry $parent.edit.value -textvariable ::GX::MaintenanceUI::ui(value)
    # A visible draft change retires its old diff, including clipboard edits
    # that need not produce a key event. Confirmation always requires re-preview.
    foreach event {<KeyRelease> <<Paste>> <<PasteSelection>> <<Cut>> <<Clear>>} {
        bind $parent.edit.value $event ::GX::_maintenanceGuiInvalidatePreview
    }
    ttk::button $parent.edit.preview -text {Preview value change} -command ::GX::frameworkMaintenanceConfigurationEdit
    pack $parent.edit.label $parent.edit.preview -side left -padx 3
    pack $parent.edit.value -fill x -expand 1 -padx 4
    pack $parent.edit -fill x -pady 4
    _maintenanceGuiText $parent
    frameworkMaintenanceConfigurationInspect
}
proc ::GX::frameworkMaintenanceConfigurationInspect {} {
    _maintenanceGuiInvalidatePreview
    set tree $::GX::MaintenanceUI::ui(tree);$tree delete [$tree children {}]
    foreach row [frameworkMaintenanceConfigurationInventory $::GX::MaintenanceUI::ui(query)] {
        if {$::GX::MaintenanceUI::ui(config_section) ne {All} && [dict get $row section] ne $::GX::MaintenanceUI::ui(config_section)} continue
        set id [dict get $row id];dict set ::GX::MaintenanceUI::rows $id $row
        set values {};foreach key {id section effective factory user override origin scopes} {lappend values [dict get $row $key]}
        $tree insert {} end -id $id -values $values
    }
    set ::GX::MaintenanceUI::ui(status) {User defaults and Session overrides are separate. Secrets and read-only fields cannot be exported or changed here. Preview captures current values and the Session identity.}
}
proc ::GX::_maintenanceGuiConfigurationPlan {operation ids values} {
    lassign [_maintenanceGuiTry [list ::GX::frameworkMaintenanceConfigurationPlan $operation $::GX::MaintenanceUI::ui(scope) $ids $values]] code result
    if {!$code} {set ::GX::MaintenanceUI::ui(preview) [dict get $result token];$::GX::MaintenanceUI::ui(frame).content.actions.confirm state !disabled}
}
proc ::GX::frameworkMaintenanceConfigurationEdit {} {
    set ids [$::GX::MaintenanceUI::ui(tree) selection]
    if {[llength $ids]!=1} {set ::GX::MaintenanceUI::ui(status) {Select one editable field};return}
    _maintenanceGuiConfigurationPlan edit $ids [dict create [lindex $ids 0] $::GX::MaintenanceUI::ui(value)]
}
proc ::GX::frameworkMaintenanceConfigurationReset which {
    set ids {}
    if {$which eq {field}} {set ids [$::GX::MaintenanceUI::ui(tree) selection]} else {
        foreach row [frameworkMaintenanceConfigurationInventory] {
            if {![dict get $row editable] || $::GX::MaintenanceUI::ui(scope) ni [dict get $row scopes]} continue
            if {$which eq {section} && ($::GX::MaintenanceUI::ui(config_section) eq {All} || [dict get $row section] ne $::GX::MaintenanceUI::ui(config_section))} continue
            lappend ids [dict get $row id]
        }
    }
    if {![llength $ids]} {set ::GX::MaintenanceUI::ui(status) {Select a field or a specific section with editable values};return}
    _maintenanceGuiConfigurationPlan reset $ids {}
}
proc ::GX::frameworkMaintenanceConfigurationExportGui {} {
    set path [tk_getSaveFile -parent $::GX::MaintenanceUI::ui(frame) -title {Export selected Configuration scope} -defaultextension .json]
    if {$path ne {}} {_maintenanceGuiTry [list ::GX::frameworkMaintenanceConfigurationExport $::GX::MaintenanceUI::ui(scope) $path]}
}
proc ::GX::frameworkMaintenanceConfigurationImportGui {} {
    set path [tk_getOpenFile -parent $::GX::MaintenanceUI::ui(frame) -title {Inspect Configuration import} -filetypes {{{JSON files} .json}}]
    if {$path ne {}} {_maintenanceGuiConfigurationPlan import {} $path}
}
proc ::GX::frameworkMaintenanceConfigurationCommit {} {
    if {$::GX::MaintenanceUI::ui(preview) eq {} || ![_maintenanceGuiConfirm {Apply scoped Configuration diff} {Commit only the displayed per-field changes in the selected scope? Changed values or a different current Session will refuse this preview.}]} return
    lassign [_maintenanceGuiTry [list ::GX::frameworkMaintenanceConfigurationApply $::GX::MaintenanceUI::ui(preview)]] code result
    if {!$code} {configurationGuiMaintenanceApplied [dict get $result diff]}
    set message $::GX::MaintenanceUI::ui(status)
    set ::GX::MaintenanceUI::ui(preview) {};$::GX::MaintenanceUI::ui(frame).content.actions.confirm state disabled
    frameworkMaintenanceConfigurationInspect
    set ::GX::MaintenanceUI::ui(status) $message
}
