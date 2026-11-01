# SPDX-License-Identifier: GPL-3.0-or-later
# Aggregate transport delegates every scientific snapshot/import to its owner.
proc ::GX::frameworkMaintenanceBackupInventory {} {
    if {$::GX::projectTransactionDepth} {error {Finish the current Project transaction before backup inspection}}
    # Registry bytes may still match while another owner holds its pending
    # organization journal. Reuse the Project owner's read barrier before and
    # after the census rather than accepting that uncommitted membership state.
    projectOrganizationCatalog
    set registryBefore [expr {[file isfile [projectRegistryPath]] ? [sha256File [projectRegistryPath]] : {absent}}]
    # Public Project reads cache their loaded registry. Refresh through that
    # owner and bind the census to disk, including foreign commits before review.
    projectLoadRegistry
    set loaded [expr {[file isfile [projectRegistryPath]] ? [sha256File [projectRegistryPath]] : {absent}}]
    if {$loaded ne $registryBefore} {error {Project registry changed during backup inspection; inspect again}}
    set projects {};set associated {};set sessions {};set orphans {}
    foreach id [projectIds] {
        set members [projectListExperiments $id]
        foreach record $members {
            set path [file normalize [dict get $record session_path]]
            if {[dict exists $associated $path]} {error "Session has conflicting Project membership: $path"}
            dict set associated $path $id;dict set sessions $path 1
        }
        lappend projects [dict create id $id name [projectField $id name] path [projectStoragePath $id] sessions $members]
    }
    foreach row [resourceLifecycleSessionCandidates] {
        set path [dict get $row path]
        if {![dict exists $associated $path]} {
            set resolved [sessionInspectionResolveResource metadata/manifest.ini $path]
            set manifest [parseIni [dict get $resolved path]]
            dict set row source_experiment_id [datasetPublicationV2DictDefault $manifest project_link.experiment_id {}]
            dict set row source_project_id [datasetPublicationV2DictDefault $manifest project_link.project_id {}]
            lappend orphans $row;dict set sessions $path 1
        }
    }
    set registryAfter [expr {[file isfile [projectRegistryPath]] ? [sha256File [projectRegistryPath]] : {absent}}]
    if {$registryAfter ne $registryBefore} {error {Project membership changed during backup inspection; inspect again}}
    projectOrganizationCatalog
    return [dict create schema gxtxt.maintenance.backup_inventory.v1 projects $projects orphans $orphans sessions [dict keys $sessions] \
        discovery {Configured Session roots, registered Project members and current Session only; unregistered paths outside these roots are unknown} \
        registry_sha256 $registryAfter]
}
proc ::GX::_maintenanceBackupHost {operation args} {
    return [_sessionPortableParseOutput [exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python framework_maintenance_v1.py] $operation {*}$args 2>@1]]
}
proc ::GX::_maintenanceBackupStage {} {
    set directory [file join [file dirname [projectRegistryPath]] .gxtxt-maintenance-[pid]-[clock clicks]]
    if {[file exists $directory]} {error {Maintenance staging collision}}
    file mkdir $directory
    if {$::tcl_platform(platform) eq {unix}} {file attributes $directory -permissions 0700}
    return $directory
}
proc ::GX::frameworkMaintenanceBackupPlan {orphanPolicy} {
    if {$orphanPolicy ni {include exclude}} {error {Explicitly choose whether unassociated Sessions are included}}
    _maintenanceIdleGuard
    return [_maintenancePreview backup [dict create orphan_policy $orphanPolicy inventory [frameworkMaintenanceBackupInventory]]]
}
proc ::GX::frameworkMaintenanceBackupExport {token archive {progress {}}} {
    set plan [_maintenancePreviewGet $token backup];_maintenanceIdleGuard
    set inventory [dict get $plan inventory]
    if {[frameworkMaintenanceBackupInventory] ne $inventory} {error {Projects or Session inventory changed after preview}}
    set archive [file normalize $archive]
    if {[file exists $archive]} {error {Backup destination already exists}}
    set sessions {};set projectPaths {}
    foreach row [dict get $inventory projects] {
        lappend projectPaths [dict get $row path]
        foreach member [dict get $row sessions] {lappend sessions [dict get $member session_path]}
    }
    if {[dict get $plan orphan_policy] eq {include}} {foreach row [dict get $inventory orphans] {lappend sessions [dict get $row path]}}
    set sessions [lsort -unique $sessions]
    foreach path [concat [dict get $inventory sessions] $projectPaths [list $::GX::scriptDir]] {if {[_datasetDeletePathWithin $archive $path]} {error {Backup destination must be outside all source Projects, Sessions and the framework}}}
    # Existing owners checkpoint their own handles. Foreign active writers are
    # refused by Portable locks; no arbitrary WAL/checkpoint manipulation occurs.
    foreach path $sessions {nativeWorkspacePortableDrain $path;set drained [scientificHistoryPortableDrain $path];scientificHistoryPortableVerifySession $path [dict get $drained owned]}
    set stage [_maintenanceBackupStage];set index 0;set packages {}
    try {
        set orphanPaths [lmap row [dict get $inventory orphans] {dict get $row path}]
        set roots [list object [dict create sessions [list array [lmap p $sessions {list text $p}]] projects [list array [lmap p $projectPaths {list text $p}]] excluded_sessions [list array [lmap p $orphanPaths {list text $p}]]]]
        _maintenanceWriteExclusive [file join $stage sources.json] [nativeWorkspaceJsonEncode $roots]
        set stamp [dict get [_maintenanceBackupHost stamp [file join $stage sources.json]] stamp]
        foreach row [dict get $inventory projects] {
            if {$progress ne {}} {uplevel #0 [list {*}$progress "Exporting Project [dict get $row name]"]}
            set path [file join $stage $index.zip]
            set excluded {}
            foreach orphan $orphanPaths {if {[file dirname $orphan] eq [file normalize [file join [dict get $row path] Sessions]]} {lappend excluded $orphan}}
            projectPortableExport [dict get $row id] $path $excluded;projectPortableValidate $path
            set members [lmap member [dict get $row sessions] {_maintenanceJsonTextObject $member}]
            lappend packages [list object [dict create kind {text project} source_id [list text [dict get $row id]] name [list text [dict get $row name]] source_path [list text [dict get $row path]] sessions [list array $members]]]
            incr index
        }
        if {[dict get $plan orphan_policy] eq {include}} {
            foreach row [dict get $inventory orphans] {
                set path [file join $stage $index.zip]
                sessionPortableExport [dict get $row path] $path;sessionPortableValidate $path
                lappend packages [list object [dict create kind {text orphan_session} source_id [list text [dict get $row path]] name [list text [dict get $row name]] source_path [list text [dict get $row path]] sessions [list array [list [_maintenanceJsonTextObject $row]]]]]
                incr index
            }
        }
        if {[dict get [_maintenanceBackupHost stamp [file join $stage sources.json]] stamp] ne $stamp || [frameworkMaintenanceBackupInventory] ne $inventory} {error {Source data or membership changed during backup; package was not published}}
        set excluded [expr {[dict get $plan orphan_policy] eq {exclude} ? [dict get $inventory orphans] : {}}]
        set spec [list object [dict create schema {text gxtxt.maintenance.backup.v1} orphan_policy [list text [dict get $plan orphan_policy]] \
            discovery [list text [dict get $inventory discovery]] excluded_orphans [list array [lmap row $excluded {_maintenanceJsonTextObject $row}]] \
            carrier_installation [list text [installationIdentityCurrent]] packages [list array $packages]]]
        _maintenanceWriteExclusive [file join $stage spec.json] [nativeWorkspaceJsonEncode $spec]
        if {$progress ne {}} {uplevel #0 [list {*}$progress {Validating all nested packages and publishing one archive}]}
        set result [_maintenanceBackupHost pack [file join $stage spec.json] $archive]
        dict set result manifest [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [dict get $result manifest_json]]]
        dict unset result manifest_json
        _maintenanceConsume $token
        return [dict merge $result [dict create status exported]]
    } finally {file delete -force -- $stage}
}
proc ::GX::frameworkMaintenanceBackupValidate archive {
    set result [_maintenanceBackupHost validate [file normalize $archive]]
    dict set result manifest [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [dict get $result manifest_json]]]
    dict unset result manifest_json
    return $result
}
proc ::GX::frameworkMaintenanceBackupRestorePlan archive {
    set result [frameworkMaintenanceBackupValidate $archive]
    return [_maintenancePreview restore $result]
}
proc ::GX::frameworkMaintenanceBackupRestore token {
    set plan [_maintenancePreviewGet $token restore];_maintenanceIdleGuard
    set archive [dict get $plan archive]
    if {[dict get [frameworkMaintenanceBackupValidate $archive] sha256] ne [dict get $plan sha256]} {error {Backup changed after preview}}
    set stage [_maintenanceBackupStage];set extract [file join $stage verified]
    set committed {};set failed {};set ordinal 0
    try {
        set extracted [_maintenanceBackupHost extract $archive $extract]
        set verified [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [dict get $extracted manifest_json]]]
        if {[dict get $extracted sha256] ne [dict get $plan sha256] || $verified ne [dict get $plan manifest]} {error {Backup changed during restore inspection; no owner import was attempted}}
        foreach record [dict get $verified packages] {
            set nested [file join $extract {*}[split [dict get $record archive] /]]
            set code [catch {
                if {[dict get $record kind] eq {project}} {
                    set receipt [projectPortableImport $nested "[dict get $record name] (restored)"]
                } else {
                    set root [string trim $::GX::cfg(output_root)]
                    if {$root eq {}} {error {Set a Session root before restoring unassociated Sessions}}
                    set destination [file join [file normalize $root] restored-[pid]-[clock clicks]-$ordinal]
                    set receipt [sessionPortableImport $nested $destination]
                }
            } message]
            if {$code} {set failed [dict create source_id [dict get $record source_id] reason $message];break}
            lappend committed [dict create kind [dict get $record kind] source_id [dict get $record source_id] source_sessions [dict get $record sessions] receipt $receipt]
            incr ordinal
        }
        _maintenanceConsume $token
        return [dict create status [expr {$failed eq {} ? {restored} : {partial}}] committed $committed failure $failed \
            policy {Existing Projects/Sessions never overwritten; committed owner imports are retained if a later import fails}]
    } finally {file delete -force -- $stage}
}
