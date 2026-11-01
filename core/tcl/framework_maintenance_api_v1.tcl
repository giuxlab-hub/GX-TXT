# SPDX-License-Identifier: GPL-3.0-or-later
# Desktop maintenance orchestrates existing owners. Previews are expiring plans,
# never a second configuration, scientific registry or persistence authority.
namespace eval ::GX::Maintenance {variable previews {};variable serial 0;variable moduleRestore {};variable moduleRestoreToken {}}
proc ::GX::frameworkMaintenanceApiInfo {} {
    return [dict create api_id FRAMEWORK_MAINTENANCE_API_v1 api_version 1 authority core_host \
        operations {status cache_preview cache_cleanup configuration_inventory configuration_export configuration_plan configuration_apply modules_inventory modules_plan modules_apply backup_inventory backup_plan backup_export backup_validate backup_restore_plan backup_restore} \
        script_exposure host_only reason {Cross-Session desktop administration, installation paths and user settings require the trusted local host}]
}
proc ::GX::_maintenancePreview {kind data} {
    variable ::GX::Maintenance::previews;variable ::GX::Maintenance::serial
    dict for {id record} $previews {if {[dict get $record expires]<[clock seconds]} {dict unset previews $id}}
    if {[dict size $previews]>=64} {error {Too many maintenance previews; finish or wait for older previews to expire}}
    set token maintenance-[pid]-[incr serial]
    dict set previews $token [dict create kind $kind expires [expr {[clock seconds]+600}] data $data]
    return [dict create token $token kind $kind expires [dict get $previews $token expires] preview $data]
}
proc ::GX::_maintenancePreviewGet {token kind} {
    if {![dict exists $::GX::Maintenance::previews $token]} {error {Unknown or consumed maintenance preview}}
    set record [dict get $::GX::Maintenance::previews $token]
    if {[dict get $record kind] ne $kind || [dict get $record expires]<[clock seconds]} {error {Maintenance preview expired or belongs to another operation}}
    return [dict get $record data]
}
proc ::GX::_maintenanceConsume token {dict unset ::GX::Maintenance::previews $token}
proc ::GX::frameworkMaintenanceStatus {} {
    set result [dict create schema gxtxt.framework_maintenance.status.v1 framework_root [file normalize $::GX::scriptDir]]
    foreach {key command} {
        identity frameworkInstalledIdentity workspace nativeWorkspaceApiInfo history scientificRecipeApiInfo
        storage {datasetStoragePolicyProviders read} catalog apiCatalogStatus diagnostics {stderrDiagnostics status}
    } {
        if {[catch {uplevel #0 [list ::GX::[lindex $command 0] {*}[lrange $command 1 end]]} value]} {
            dict set result $key [dict create status unknown reason $value]
        } else {dict set result $key $value}
    }
    dict set result configuration_path [configurationPath]
    return $result
}
proc ::GX::_maintenanceSecret {id descriptor} {
    expr {[datasetPublicationV2DictDefault $descriptor secret 0] || [datasetPublicationV2DictDefault $descriptor sensitive 0] ||
        [regexp -nocase {(^|[_.])(password|passwd|secret|token|api_key|credential)([_.]|$)} $id]}
}
proc ::GX::frameworkMaintenanceConfigurationInventory {{query {}}} {
    set rows {};set query [string tolower $query]
    dict for {id descriptor} [configurationFields] {
        if {$query ne {} && [string first $query [string tolower "$id [dict get $descriptor label] [dict get $descriptor group]"]]<0} continue
        set resolved [configurationResolve $id]
        dict set resolved origin [dict get $resolved effective_origin]
        set secret [_maintenanceSecret $id $descriptor]
        if {$secret} {foreach key {factory user override effective} {dict set resolved $key {<redacted>}}}
        set editable [expr {!$secret && [dict get $descriptor scope] ni {framework runtime} && ![datasetPublicationV2DictDefault $descriptor readonly 0]}]
        lappend rows [dict merge $resolved [dict create id $id label [dict get $descriptor label] section [dict get $descriptor group] type [dict get $descriptor type] secret $secret editable $editable]]
    }
    return $rows
}
proc ::GX::_maintenanceJsonTextObject {values} {
    set fields {};dict for {key value} $values {dict set fields $key [list text $value]}
    return [list object $fields]
}
proc ::GX::_maintenanceWriteExclusive {path bytes} {
    set channel [open $path {WRONLY CREAT EXCL} 0600]
    try {fconfigure $channel -translation binary -encoding binary;puts -nonewline $channel [encoding convertto utf-8 $bytes]} finally {close $channel}
    return $path
}
proc ::GX::_maintenanceReadJson {path {maximum 4194304}} {
    file lstat $path before
    if {$before(type) ne {file} || $before(size)>$maximum} {error {Maintenance input must be a bounded regular JSON file}}
    set channel [open $path rb]
    try {set raw [read $channel [expr {$maximum+1}]]} finally {close $channel}
    file lstat $path after
    foreach key {dev ino size mtime ctime} {if {$before($key) ne $after($key)} {error {Maintenance input changed while reading}}}
    if {[string length $raw]>$maximum} {error {Maintenance input exceeds its bound}}
    # Binary channels preserve file bytes; convert UTF-8 before handing text to
    # the JSON owner so non-ASCII units and labels retain their exact values.
    return [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [encoding convertfrom utf-8 $raw]]]
}
proc ::GX::frameworkMaintenanceConfigurationExport {scope path} {
    if {$scope ni {user session}} {error {Choose User or Session scope}}
    if {$scope eq {session} && $::GX::currentSession eq {}} {error {Open a Session before exporting its overrides}}
    set fields {};set excluded {}
    foreach row [frameworkMaintenanceConfigurationInventory] {
        if {![dict get $row editable] || $scope ni [dict get $row scopes]} {lappend excluded [dict get $row id];continue}
        if {$scope eq {session} && [dict get $row origin] ne {session}} continue
        set id [dict get $row id]
        dict set fields $id [list text [configurationScopedValue $id $scope]]
    }
    set typed [list object [dict create schema {text gxtxt.maintenance.configuration.v1} scope [list text $scope] fields [list object $fields]]]
    _maintenanceWriteExclusive $path [nativeWorkspaceJsonEncode $typed]
    return [dict create status exported path $path scope $scope fields [dict size $fields] excluded $excluded]
}
proc ::GX::frameworkMaintenanceConfigurationPlan {operation scope ids {values {}}} {
    if {$operation ni {edit import reset} || $scope ni {user session}} {error {Invalid Configuration operation or scope}}
    if {$scope eq {session} && $::GX::currentSession eq {}} {error {Open a Session before editing Session overrides}}
    if {$operation eq {import}} {
        set input [_maintenanceReadJson $values]
        if {[lsort [dict keys $input]] ne {fields schema scope} || [dict get $input schema] ne {gxtxt.maintenance.configuration.v1} || [dict get $input scope] ne $scope} {error {Configuration import schema/scope differs; scopes cannot be merged}}
        set values [dict get $input fields];set ids [dict keys $values]
    }
    if {[llength $ids]>10000} {error {Configuration selection exceeds its bound}}
    set changes {};set diff {}
    foreach id [lsort -unique $ids] {
        if {![dict exists [configurationFields] $id]} {error "Unknown Configuration field: $id"}
        set descriptor [dict get [configurationFields] $id]
        if {[_maintenanceSecret $id $descriptor] || [dict get $descriptor scope] in {framework runtime} || [datasetPublicationV2DictDefault $descriptor readonly 0]} {error "Protected Configuration field: $id"}
        set resolved [configurationResolve $id]
        if {$scope ni [dict get $resolved scopes]} {error "Scope '$scope' is unavailable for $id"}
        set before [configurationScopedValue $id $scope]
        set clear 0
        if {$operation eq {reset}} {
            if {$scope eq {session} && {user} in [dict get $resolved scopes]} {set after [dict get $resolved user];set clear 1} else {set after [dict get $resolved factory]}
        } else {set after [dict get $values $id]}
        # Default pipeline selectors can name outputs not created in this
        # Session yet. An unchanged value needs no new binding admission;
        # already inherited values also have no override left to clear.
        if {$before eq $after && (!$clear || [dict get $resolved origin] ne {session})} continue
        set after [configurationValidate $id $after]
        set after [_configurationValidateBinding $descriptor $after]
        if {$before eq $after && !$clear} continue
        lappend changes [dict create id $id scope $scope value $after expected $before session_token [dict get $resolved session_token] clear $clear]
        lappend diff [dict create id $id scope $scope before $before after $after clear_override $clear]
    }
    return [_maintenancePreview configuration [dict create operation $operation scope $scope changes $changes diff $diff]]
}
proc ::GX::frameworkMaintenanceConfigurationApply token {
    set plan [_maintenancePreviewGet $token configuration]
    foreach change [dict get $plan changes] {
        if {[dict get $change clear] && [configurationGet [dict get $change id]] ne [dict get $change value]} {
            error {User default changed after the Session reset preview; inspect again}
        }
    }
    set result [configurationCommit [dict get $plan changes]]
    _maintenanceConsume $token
    return [dict merge $result [dict create scope [dict get $plan scope] diff [dict get $plan diff]]]
}
proc ::GX::_maintenanceIdleGuard {} {
    foreach name {pipe analysisPipe} {if {[info exists ::GX::$name] && [set ::GX::$name] ne {}} {error {Finish the active pipeline/analysis operation before maintenance}}}
    if {[info exists ::GX::scriptJobRequests] && [dict size $::GX::scriptJobRequests]} {error {Finish active managed requests before changing modules or creating a backup}}
    # The ordinary list is capped at recent user Jobs. The existing view's
    # lifecycle projection includes older active and CORE-service writers too.
    set jobs [scriptJobPresentationCall view_list {scope all filter Active hidden_ids {} watched_ids {} limit 1}]
    if {[llength [dict get $jobs lifecycle]]} {error {Finish active Script Jobs before changing modules or creating a backup}}
}
proc ::GX::frameworkMaintenanceModulesInventory {} {
    set rows {}
    foreach id $::GX::moduleOrder {
        set info [moduleOperationalInfo $id]
        dict set info version [moduleField $id version unknown]
        dict set info optional [expr {![dict get $info core_protected] && ![dict get $info always_available]}]
        dict set info depends [splitList [moduleField $id depends {}]]
        lappend rows $info
    }
    return $rows
}
proc ::GX::_maintenanceModuleSnapshot {} {
    set result {}
    foreach row [frameworkMaintenanceModulesInventory] {
        set id [dict get $row module_id]
        dict set result $id [dict create enabled [dict get $row enabled] run [moduleRunIsSelected $id] version [dict get $row version]]
    }
    return $result
}
proc ::GX::frameworkMaintenanceModulesPlan {{operation disable_optional}} {
    _maintenanceIdleGuard
    set before [_maintenanceModuleSnapshot];set targets {}
    if {$operation eq {restore}} {
        if {$::GX::Maintenance::moduleRestore eq {}} {error {No captured module state to restore in this process}}
        if {$::GX::Maintenance::moduleRestoreToken ne [_configurationSessionToken]} {error {Previous module states belong to another Session lifetime}}
        set saved $::GX::Maintenance::moduleRestore
        if {[dict keys $saved] ne [dict keys $before]} {error {Installed module inventory changed; review modules individually}}
        dict for {id prior} $saved {
            if {[dict get $prior version] ne [dict get $before $id version]} {error {A module version changed; bulk restore refused}}
            dict set targets $id [dict get $prior enabled]
        }
    } elseif {$operation eq {disable_optional}} {
        foreach row [frameworkMaintenanceModulesInventory] {if {[dict get $row optional] && [dict get $row enabled]} {dict set targets [dict get $row module_id] 0}}
    } else {error {Unknown module operation}}
    # Cascade may never cross a protected authority. Public enablement remains
    # the sole mutator, but its complete dependency effects are preflighted here.
    set kept {};set again 1
    while {$again} {
        set again 0
        foreach row [frameworkMaintenanceModulesInventory] {
            set id [dict get $row module_id]
            foreach dep [dict get $row depends] {
                set enabled [expr {[dict exists $targets $id] ? [dict get $targets $id] : [dict get $row enabled]}]
                set changingDependency [expr {[dict exists $before $dep] && [dict get $before $dep enabled]}]
                set enablingConsumer [expr {$enabled && ![dict get $row enabled]}]
                if {$enabled && [dict exists $targets $dep] && ![dict get $targets $dep] && ($changingDependency || $enablingConsumer)} {
                    if {$operation ne {disable_optional}} {error "Enabled module $id requires $dep; bulk change refused"}
                    # Optional dependencies of protected authorities remain ON.
                    # Repeat to preserve their transitive dependencies as well.
                    dict unset targets $dep;dict set kept $dep "Required by enabled $id";set again 1
                }
            }
        }
    }
    return [_maintenancePreview modules [dict create operation $operation before $before targets $targets kept $kept session_token [_configurationSessionToken]]]
}
proc ::GX::frameworkMaintenanceModulesApply token {
    set plan [_maintenancePreviewGet $token modules];_maintenanceIdleGuard
    if {[dict get $plan session_token] ne [_configurationSessionToken]} {error {Session changed after module preview; inspect again}}
    if {[_maintenanceModuleSnapshot] ne [dict get $plan before]} {error {Module states changed after preview; inspect again}}
    if {[dict get $plan operation] eq {disable_optional} && [dict size [dict get $plan targets]] && ($::GX::Maintenance::moduleRestore eq {} || $::GX::Maintenance::moduleRestoreToken ne [_configurationSessionToken])} {
        set ::GX::Maintenance::moduleRestore [dict get $plan before];set ::GX::Maintenance::moduleRestoreToken [_configurationSessionToken]
    }
    set changed {};set failed {}
    dict for {id enabled} [dict get $plan targets] {
        set info [moduleOperationalInfo $id]
        if {[dict get $info core_protected] || [dict get $info always_available]} continue
        if {[catch {moduleSetEnabled $id $enabled 0} message]} {dict set failed $id $message} else {lappend changed $id}
    }
    if {[dict get $plan operation] eq {restore} && $failed eq {}} {
        dict for {id prior} $::GX::Maintenance::moduleRestore {moduleSetRunSelected $id [dict get $prior run]}
        set ::GX::Maintenance::moduleRestore {}
        set ::GX::Maintenance::moduleRestoreToken {}
    }
    _maintenanceConsume $token
    foreach command {refreshModuleCatalog refreshStandardModuleControls refreshAnalysisStatus configurationModulesReload} {if {[llength [info commands ::GX::$command]]} {catch {::GX::$command}}}
    return [dict create status [expr {$failed eq {} ? {applied} : {partial}}] changed $changed failed $failed restore_available [expr {$::GX::Maintenance::moduleRestore ne {}}]]
}
proc ::GX::_maintenanceCacheAllowed row {
    expr {[dict get $row managed] && [dict get $row eligible] && [dict get $row category] in {cache_reusable temporary} &&
        ![dict get $row recovery_required] && ([dict get $row released] || ![dict get $row owner_alive])}
}
proc ::GX::frameworkMaintenanceCachePreview {ids callback} {
    if {![llength $ids] || [llength $ids]>256} {error {Select 1–256 owned disposable resources}}
    return [resourceManagementAsync inventory {rescan 1} [list ::GX::_maintenanceCachePreviewDone $ids $callback]]
}
proc ::GX::_maintenanceCachePreviewDone {ids callback code output} {
    if {!$code} {set code [catch {
        set selected {};foreach row [dict get $output resources] {if {[dict get $row id] in $ids} {if {![_maintenanceCacheAllowed $row]} {error {Selection includes protected, active or unowned resources}};dict set selected [dict get $row id] $row}}
        if {[lsort [dict keys $selected]] ne [lsort -unique $ids]} {error {Resource selection changed or disappeared}}
        set output [_maintenancePreview cache [dict create ids $ids resources $selected]]
    } output]}
    uplevel #0 [list {*}$callback $code $output]
}
proc ::GX::frameworkMaintenanceCacheCleanup {token callback} {
    set plan [_maintenancePreviewGet $token cache]
    # Resource Management revalidates ownership, lease and exact allocation
    # directory at commit. This preview never grants deletion to legacy paths.
    _maintenanceConsume $token
    return [resourceManagementAsync cleanup [dict get $plan ids] $callback]
}

source [file join [file dirname [info script]] framework_maintenance_backup_v1.tcl]
