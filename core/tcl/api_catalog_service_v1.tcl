# SPDX-License-Identifier: GPL-3.0-or-later
# Derived installed reference only. Public owners retain execution/admission.
namespace eval ::GX::ApiCatalog {
    variable handle {};variable request {};variable waiters {};variable serial 0
    variable retries 0
    variable target {};variable freshness unavailable;variable error {};variable pending {}
    variable directory {};variable snapshot {};variable initialized 0;variable manifest {};variable adopt 0
    variable progress idle;variable pendingMetadata {};variable exitHook 0;variable shippedManifest {};variable closed 0;variable staging {};variable countsKey {};variable counts {}
}
proc ::GX::apiCatalogApiInfo {} {
    return [dict create api_id API_CATALOG_SERVICE_API_v1 api_version 1 authority native_cpp_sqlite operations {request query get status refresh cancel invalidate provider_state diagnostics manual_inspect manual_open} host_only_operations {diagnostics manual_inspect manual_open} execution metadata_only session_required 0]
}
proc ::GX::_apiCatalogRequire {} {
    variable ::GX::ApiCatalog::handle
    if {$::GX::ApiCatalog::closed} {return -code error -errorcode {GX API_CATALOG CLOSED} {API catalog service is closed until interpreter restart}}
    if {![llength [info commands ::GX::apiCatalogNative]]} {load [file join $::GX::scriptDir core api_catalog libgxtxt_api_catalog[info sharedlibextension]] Gxtxt_api_catalog}
    if {$handle ne {}} {return $handle}
    set identity [list [file normalize $::GX::scriptDir] [file normalize [configurationPath]]]
    if {[info exists ::env(XDG_CACHE_HOME)] && [file pathtype $::env(XDG_CACHE_HOME)] eq {absolute}} {set cache $::env(XDG_CACHE_HOME)} else {set cache [file join ~ .cache]}
    set directory [file join $cache gxtxt api-catalog-v2 [apiCatalogNative digest $identity]]
    file mkdir $directory;catch {file attributes $directory -permissions 0700}
    set ::GX::ApiCatalog::directory $directory
    set packaged [file join $::GX::scriptDir core api_catalog]
    set manifest [_apiCatalogJsonRead [file join $packaged source_manifest.json]]
    if {[dict get $manifest schema] ne {gxtxt.api_catalog.sources.v2} || [apiCatalogNative file_digest [file join $packaged catalog.sqlite]] ne [dict get $manifest database_sha256]} {error {Packaged API catalog is missing, corrupt or incompatible; previous user cache preserved}}
    set ::GX::ApiCatalog::manifest $manifest;set ::GX::ApiCatalog::shippedManifest $manifest
    set snapshot [file join $directory snapshot.[pid].[clock clicks].sqlite]
    file copy [file join $packaged catalog.sqlite] $snapshot
    _apiCatalogSnapshotWritable $snapshot
    set ::GX::ApiCatalog::snapshot $snapshot
    set handle [apiCatalogNative open $snapshot gxtxt.api_catalog.distribution.v2]
    if {[dict get [apiCatalogNative status $handle] fingerprint] ne [dict get $manifest fingerprint]} {apiCatalogNative close $handle;set handle {};error {Packaged API catalog source identity differs}}
    set ::GX::ApiCatalog::freshness packaged
    if {!$::GX::ApiCatalog::exitHook} {trace add execution ::exit enter ::GX::_apiCatalogExit;set ::GX::ApiCatalog::exitHook 1}
    return $handle
}
proc ::GX::_apiCatalogSnapshotWritable {path} {
    # Only a newly owned per-user snapshot is writable. Seed permissions and
    # the read-only installation are never changed.
    if {$::tcl_platform(platform) eq {unix}} {file attributes $path -permissions 0600} else {file attributes $path -readonly 0}
}
proc ::GX::_apiCatalogAdopt {database manifest} {
    set snapshot [file join $::GX::ApiCatalog::directory snapshot.[pid].[clock clicks].sqlite]
    set next {}
    try {
        file copy $database $snapshot
        _apiCatalogSnapshotWritable $snapshot
        set next [apiCatalogNative open $snapshot gxtxt.api_catalog.distribution.v2]
        set status [apiCatalogNative validate $next]
        if {[dict get $status fingerprint] ne [dict get $manifest fingerprint] || [dict get $status count]<1 || [dict get $status count]!=[dict get $manifest counts records]} {error {Staged API catalog identity/count differs}}
    } on error {message options} {
        if {$next ne {}} {catch {apiCatalogNative close $next}}
        foreach suffix {{} -wal -shm} {catch {file delete -- $snapshot$suffix}}
        return -options $options $message
    }
    set prior $::GX::ApiCatalog::handle;set oldPath $::GX::ApiCatalog::snapshot
    set ::GX::ApiCatalog::handle $next;set ::GX::ApiCatalog::snapshot $snapshot;set ::GX::ApiCatalog::manifest $manifest
    if {$prior ne {}} {catch {apiCatalogNative close $prior}}
    if {$oldPath ne {}} {foreach suffix {{} -wal -shm} {catch {file delete -- $oldPath$suffix}}}
}
proc ::GX::_apiCatalogExit {args} {apiCatalogClose}
proc ::GX::apiCatalogClose {} {
    if {$::GX::ApiCatalog::closed} return
    set ::GX::ApiCatalog::closed 1
    if {$::GX::ApiCatalog::pending ne {}} {after cancel $::GX::ApiCatalog::pending;set ::GX::ApiCatalog::pending {}}
    if {$::GX::ApiCatalog::request ne {}} {set request $::GX::ApiCatalog::request;set ::GX::ApiCatalog::request {};catch {scriptJobRequestCancel $request}}
    set ::GX::ApiCatalog::progress closed;set ::GX::ApiCatalog::freshness closed
    _apiCatalogNotify {ok 0 error {API catalog service is closed until interpreter restart} code {GX API_CATALOG CLOSED}}
    if {$::GX::ApiCatalog::handle ne {}} {catch {apiCatalogNative close $::GX::ApiCatalog::handle};set ::GX::ApiCatalog::handle {}}
    if {$::GX::ApiCatalog::snapshot ne {}} {foreach suffix {{} -wal -shm} {catch {file delete -- $::GX::ApiCatalog::snapshot$suffix}};set ::GX::ApiCatalog::snapshot {}}
}
proc ::GX::_apiCatalogSourceFiles {directory depth} {
    if {$depth>8} {error {API catalog source inventory exceeds depth bound}}
    set files {}
    foreach path [lsort [glob -nocomplain -directory $directory *]] {
        if {[file type $path] eq {link}} continue
        if {[file isdirectory $path]} {if {[file tail $path] ni {__pycache__ images resources native review}} {lappend files {*}[_apiCatalogSourceFiles $path [expr {$depth+1}]]}} elseif {[file extension $path] in {.tcl .py .json .hpp .h .ini}} {lappend files $path}
    }
    return $files
}
proc ::GX::_apiCatalogFingerprint {{manifest {}}} {
    _apiCatalogRequire
    if {$manifest eq {}} {set manifest $::GX::ApiCatalog::manifest}
    set root [file normalize $::GX::scriptDir];set files {}
    # Shipped identities are manifest-driven: no recursive CORE discovery on
    # ordinary startup. Enumerate current plugin declaration roots for lifecycle
    # additions/removals; read exact referenced documents only.
    dict for {relative entry} [dict get $manifest files] {
        if {[file pathtype $relative] ne {relative} || {..} in [file split $relative]} {error {Invalid packaged API source identity}}
        if {[string match plugins/modules/* $relative] && $relative ni [dict get $manifest documentation]} continue
        lappend files [file join $root $relative]
    }
    foreach directory [lsort [glob -nocomplain -types d -directory [file join $root plugins modules] *]] {
        if {[file type $directory] eq {link}} continue
        set descriptor [file join $directory module.ini]
        lappend files $descriptor [file join $directory SHA256SUMS.txt] [file join $directory SHA256SUMS]
        if {[file isdirectory [file join $directory api]]} {lappend files {*}[_apiCatalogSourceFiles [file join $directory api] 0]}
        if {![file isfile $descriptor]} continue
        if {[file type $descriptor] eq {link} || [file size $descriptor]>16777216} {error {Module API descriptor exceeds its regular-file bound}}
        set d [parseIni $descriptor]
        foreach api [splitList [descriptorValue $d public_apis ids {}]] {
            set reference [descriptorValue $d public_api.$api documentation docs/api/$api.md]
            if {[file pathtype $reference] ne {relative} || {..} in [file split $reference]} {error {Invalid module API documentation identity}}
            set candidates [list [file join $root $reference] [file join $directory $reference] [file join $directory docs $reference]]
            set selected [lindex $candidates 0]
            foreach candidate $candidates {if {[file isfile $candidate] && [file type $candidate] ne {link}} {set selected $candidate;break}}
            lappend files $selected
        }
    }
    return [apiCatalogNative fingerprint [lsort -unique $files] $root]
}
proc ::GX::apiCatalogStatus {} {
    variable ::GX::ApiCatalog::freshness;variable ::GX::ApiCatalog::error
    set status [apiCatalogNative status [_apiCatalogRequire]]
    set identity [dict create version $::GX::version patch {} display_version $::GX::version framework_root [file normalize $::GX::scriptDir]]
    if {[llength [info commands ::GX::frameworkInstalledIdentity]]} {
        if {[catch {set identity [frameworkInstalledIdentity]} reason]} {dict set identity metadata_error $reason}
    }
    return [dict merge $status [dict create freshness $freshness error $error progress $::GX::ApiCatalog::progress request_active [expr {$::GX::ApiCatalog::request ne {}}] target_fingerprint $::GX::ApiCatalog::target pending_metadata $::GX::ApiCatalog::pendingMetadata framework_root [file normalize $::GX::scriptDir] framework_identity $identity source_manifest_schema [dict get $::GX::ApiCatalog::manifest schema] source_manifest_fingerprint [dict get $::GX::ApiCatalog::manifest fingerprint] loaded_packaged_database_sha256 [dict get $::GX::ApiCatalog::shippedManifest database_sha256]]]
}
proc ::GX::_apiCatalogDefinitionRequire {} {
    if {$::GX::ApiCatalog::closed} {return -code error -errorcode {GX API_CATALOG CLOSED} {API catalog service is closed until interpreter restart}}
    if {!$::GX::ApiCatalog::initialized || ($::GX::ApiCatalog::adopt && $::GX::ApiCatalog::progress eq {staging_metadata})} {
        return -code error -errorcode {GX API_CATALOG INITIALIZING} {Request the API catalog and wait for its initial definition snapshot}
    }
}
proc ::GX::apiCatalogQuery {{filters {}}} {
    _apiCatalogDefinitionRequire
    set result [apiCatalogNative query [_apiCatalogRequire] $filters]
    set rows {};set owners {}
    foreach row [dict get $result rows] {
        set owner [dict get $row provider_id]
        set core [expr {$owner eq {CORE} || [string match core/* [datasetPublicationV2DictDefault [dict get $row payload catalog_meta] declaration_ref {}]]}]
        if {![dict exists $owners $owner]} {dict set owners $owner [apiCatalogProviderState $owner $core]}
        dict set row runtime_state [dict get $owners $owner];lappend rows $row
    }
    dict set result rows $rows
    return [dict merge $result [dict create freshness $::GX::ApiCatalog::freshness error $::GX::ApiCatalog::error]]
}
proc ::GX::apiCatalogProviderState {owner {core 0}} {
    if {$owner eq {CORE}} {set core 1}
    if {$owner ni $::GX::moduleOrder} {
        return [dict create installed $core enabled $core active [expr {$owner eq {CORE}}] pending 0 admission reference_only]
    }
    set runtimeError {}
    if {[catch {set active [pluginRuntimeModuleLoaded $owner]} reason]} {set active 0;set runtimeError [string range $reason 0 2047]}
    set pending [dict exists $::GX::pluginRuntimePending $owner]
    return [dict create installed 1 installed_version [moduleField $owner version {}] enabled [moduleIsEnabled $owner] active $active active_status [expr {$runtimeError eq {}?{known}:{unknown}}] runtime_error $runtimeError pending $pending admission reference_only]
}
proc ::GX::apiCatalogGet {id} {
    _apiCatalogDefinitionRequire
    set record [apiCatalogNative get [_apiCatalogRequire] $id]
    set payload [dict get $record payload]
    if {[dict get $record surface] eq {family}} {
        set providers {};set installed 0;set enabled 0;set active 0;set pending 0
        foreach provider [datasetPublicationV2DictDefault $payload providers {}] {
            set owner [dict get $provider provider]
            set core [expr {$owner eq {CORE}}]
            foreach source [datasetPublicationV2DictDefault [dict get $payload catalog_meta] source_members {}] {
                if {[dict get $source provider_id] eq $owner && [string match core/* [dict get $source declaration_ref]]} {set core 1}
            }
            set state [apiCatalogProviderState $owner $core]
            dict set providers $owner $state
            foreach key {installed enabled active pending} {if {[dict get $state $key]} {set $key 1}}
        }
        if {![dict size $providers] && [dict exists $payload script_descriptor]} {
            set owner [dict get $payload script_descriptor provider_id]
            set state [apiCatalogProviderState $owner [string match core/* [dict get $payload catalog_meta declaration_ref]]]
            dict set providers $owner $state
            foreach key {installed enabled active pending} {set $key [dict get $state $key]}
        }
        dict set record runtime_state [dict create providers $providers installed $installed enabled $enabled active $active pending $pending admission reference_only]
    } else {
        set core [expr {[dict get $record provider_id] eq {CORE} || [string match core/* [dict get $payload catalog_meta declaration_ref]]}]
        dict set record runtime_state [apiCatalogProviderState [dict get $record provider_id] $core]
    }
    return $record
}
proc ::GX::_apiCatalogJsonRead {path {typedVariable {}}} {
    if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {Saved project metadata is unavailable or exceeds its bound}}
    set channel [open $path rb];try {set json [read $channel]} finally {close $channel}
    set typed [nativeWorkspaceJsonDecode $json]
    if {$typedVariable ne {}} {upvar 1 $typedVariable target;set target $typed}
    return [nativeWorkspaceDecode $typed]
}
proc ::GX::apiCatalogProjectContext {project} {
    set result [dict create status NO_PROJECT source_validation not_checked_by_metadata_browser runtime_grants not_activated_by_metadata_browser requests {}]
    if {$project eq {}} {return $result}
    if {![catch {set hint [_apiCatalogJsonRead [file join $project project.json]]}] && [datasetPublicationV2DictDefault $hint schema {}] eq {gxtxt.acquisition_development_project.v1}} {
        return [_apiCatalogAcquisitionProjectContext $project]
    }
    if {[catch {
        set paths {};foreach name {project.json handlers.cpp design.gxtxt-viewer} {
            set path [file join $project $name]
            if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {Saved project requires ordinary bounded source files}}
            file stat $path st;if {$st(nlink)!=1} {error {Saved project source hardlinks are unavailable for reference admission}}
            lappend paths $path
        }
        set before [apiCatalogNative fingerprint $paths]
        set meta [_apiCatalogJsonRead [lindex $paths 0] typedProject]
        set expected {schema module_id version profile language source design capabilities provenance tests}
        if {[lindex $typedProject 0] ne {object} || [lsort [dict keys $meta]] ne [lsort $expected]} {error {Saved project metadata schema fields differ}}
        set fields [lindex $typedProject 1]
        foreach name {schema profile language source design} {if {[lindex [dict get $fields $name] 0] ne {text}} {error {Saved project metadata requires explicit JSON strings}}}
        if {[dict get $meta source] ne {handlers.cpp} || [dict get $meta design] ne {design.gxtxt-viewer} || [lindex [dict get $fields provenance] 0] ne {object} || [string bytelength [dict get $meta provenance]]>8192} {error {Saved project source/design/provenance differs}}
        set capabilities [dict get $fields capabilities]
        if {[lindex $capabilities 0] ne {array} || [llength [lindex $capabilities 1]]>16} {error {Saved capability requests require a bounded JSON array}}
        foreach request [lindex $capabilities 1] {
            if {[lindex $request 0] ne {object}} {error {Saved capability request must be a JSON object}}
            set request [lindex $request 1]
            if {[lsort [dict keys $request]] ne [lsort {api_id version operations}] || [lindex [dict get $request api_id] 0] ne {text} || [lindex [dict get $request version] 0] ne {int} || [lindex [dict get $request operations] 0] ne {array}} {error {Saved capability request has invalid typed fields}}
            foreach operation [lindex [dict get $request operations] 1] {if {[lindex $operation 0] ne {text}} {error {Saved capability operations require explicit JSON strings}}}
        }
        set policy [_apiCatalogJsonRead [file join $::GX::scriptDir core development policy_v1.json]]
        set profile [dict get $meta profile]
        if {[dict get $meta schema] ne {gxtxt.viewer_development_project.v1} || [dict get $meta language] ne {cpp} || ![dict exists $policy profiles $profile]} {error {Saved project schema/profile is unavailable}}
        set requests {}
        foreach request [dict get $meta capabilities] {
            set api [dict get $request api_id]
            set state CAPABILITY_DENIED
            if {[dict exists $requests $api]} {error {Duplicate saved capability request}}
            if {[dict exists $policy capabilities $api] && $api in [dict get $policy profiles $profile]} {
                set allowed [dict get $policy capabilities $api]
                if {[dict get $request version]==[dict get $allowed version]} {
                    set state ADMITTED_REQUEST
                    foreach operation [dict get $request operations] {if {$operation ni [dict get $allowed operations]} {set state CAPABILITY_DENIED}}
                }
            }
            if {[catch {set familyRecord [apiCatalogGet family:$api];set family [dict get $familyRecord payload]}] || [datasetPublicationV2DictDefault $family version_conflict 0] || ![dict get $familyRecord runtime_state installed] || ![dict get $familyRecord runtime_state enabled] || [dict get $familyRecord runtime_state pending] || [datasetPublicationV2DictDefault $family version {}] ne [dict get $request version]} {set state CORE_API_GAP}
            if {$state eq {ADMITTED_REQUEST} && $api eq {VIEWER_GUI_HOST_API_v1} && {pcb_source_form} in [dict get $request operations] && $profile ne {document_view_v1}} {set state CAPABILITY_DENIED}
            if {$api eq {PLOT_DATASET_API_v3} || ([string match PLOT_DATASET* $api] && [dict get $request version]==3)} {set state DEPRECATED_PLOT_API}
            dict set requests $api [dict create status $state request $request]
        }
        if {$before ne [apiCatalogNative fingerprint $paths]} {error {Project changed during reference discovery}}
        dict set result status SAVED_PROJECT_METADATA;dict set result profile $profile;dict set result project $project;dict set result requests $requests
    } reason]} {dict set result status PROJECT_UNAVAILABLE;dict set result reason $reason}
    return $result
}
proc ::GX::_apiCatalogAcquisitionProjectContext {project} {
    set result [dict create status PROJECT_UNAVAILABLE target acquisition source_validation not_checked_by_metadata_browser runtime_grants not_activated_by_metadata_browser requests {}]
    if {[catch {
        set meta [_apiCatalogJsonRead [file join $project project.json] typed]
        if {[lindex $typed 0] ne {object} || [dict get $meta schema] ne {gxtxt.acquisition_development_project.v1} || [dict get $meta profile] ne {acquisition_v1} || [dict get $meta language] ne {cpp} || [dict get $meta source] ne {handlers.cpp}} {error {Saved Acquisition target metadata differs}}
        set paths [list [file join $project project.json]]
        foreach name [viewerDevelopmentSourceFiles $project] {
            set path [file join $project $name];file lstat $path st
            if {$st(type) ne {file} || $st(nlink)!=1 || $st(size)>65536 || [file normalize $path] ne $path} {error {Saved Acquisition source must be an ordinary bounded registered file}}
            lappend paths $path
        }
        set before [apiCatalogNative fingerprint $paths]
        set fields [lindex $typed 1]
        set declarations [dict get $fields capabilities]
        if {[lindex $declarations 0] ne {array} || [llength [lindex $declarations 1]]>16} {error {Acquisition capability requests require a bounded typed array}}
        set policy [_apiCatalogJsonRead [file join $::GX::scriptDir core development acquisition_policy_v1.json]]
        set requests {}
        foreach declaration [lindex $declarations 1] {
            if {[lindex $declaration 0] ne {object}} {error {Capability declaration must be an object}}
            set declaration [lindex $declaration 1]
            if {[lsort [dict keys $declaration]] ne {api_id operations version} || [lindex [dict get $declaration api_id] 0] ne {text} || [lindex [dict get $declaration version] 0] ne {int} || [lindex [dict get $declaration operations] 0] ne {array}} {error {Invalid typed Acquisition capability request}}
            foreach operation [lindex [dict get $declaration operations] 1] {if {[lindex $operation 0] ne {text}} {error {Capability operations must be explicit strings}}}
            set request [nativeWorkspaceDecode [list object $declaration]];set api [dict get $request api_id]
            if {[dict exists $requests $api]} {error {Duplicate saved Acquisition capability request}}
            set state CAPABILITY_DENIED
            if {$api eq [dict get $policy capability_owner] && [dict get $request version]==[dict get $policy sdk_version]} {
                set state ADMITTED_REQUEST
                foreach operation [dict get $request operations] {if {$operation ni [dict get $policy sdk_calls]} {set state CAPABILITY_DENIED}}
            }
            if {[catch {set record [apiCatalogGet family:$api];set family [dict get $record payload]}] || [datasetPublicationV2DictDefault $family version_conflict 0] || ![dict get $record runtime_state installed] || ![dict get $record runtime_state enabled] || [dict get $record runtime_state pending] || [datasetPublicationV2DictDefault $family version {}] ne [dict get $request version]} {set state CORE_API_GAP}
            dict set requests $api [dict create status $state request $request]
        }
        if {$meta ne [_apiCatalogJsonRead [file join $project project.json]] || $before ne [apiCatalogNative fingerprint $paths]} {error {Acquisition project changed during reference discovery}}
        dict set result status SAVED_PROJECT_METADATA;dict set result project $project;dict set result profile acquisition_v1;dict set result requests $requests
    } reason]} {dict set result reason $reason}
    return $result
}
proc ::GX::apiCatalogProjectMethod {contract context} {
    set missing {}
    foreach grant [dict get $contract required_capabilities] {
        lassign [split $grant /] api operation
        if {![dict exists $context requests $api] || [dict get $context requests $api status] ne {ADMITTED_REQUEST} || $operation ni [dict get $context requests $api request operations]} {lappend missing $grant}
    }
    if {[dict exists $contract required_target] && [dict get $contract required_target] ne [datasetPublicationV2DictDefault $context target viewer]} {lappend missing target:[dict get $contract required_target]}
    dict set contract missing_capabilities $missing
    dict set contract project_status [expr {[dict get $context status] eq {SAVED_PROJECT_METADATA}?([llength $missing]?{NOT_ADMITTED}:{ADMITTED_REQUEST}):[dict get $context status]}]
    return $contract
}
proc ::GX::apiCatalogInvalidate {} {
    set ::GX::ApiCatalog::freshness stale
    if {$::GX::ApiCatalog::initialized && $::GX::ApiCatalog::pending eq {}} {set ::GX::ApiCatalog::pending [after idle ::GX::_apiCatalogStart]}
}
proc ::GX::apiCatalogRefresh {callback} {
    set ticket catalog[incr ::GX::ApiCatalog::serial]
    dict set ::GX::ApiCatalog::waiters $ticket $callback
    if {$::GX::ApiCatalog::pending eq {}} {set ::GX::ApiCatalog::pending [after idle ::GX::_apiCatalogStart]}
    return $ticket
}
proc ::GX::apiCatalogCancel {ticket} {catch {dict unset ::GX::ApiCatalog::waiters $ticket}}
proc ::GX::apiCatalogRequest {callback} {
    if {$::GX::ApiCatalog::closed} {return [apiCatalogRefresh $callback]}
    set ticket catalog[incr ::GX::ApiCatalog::serial]
    dict set ::GX::ApiCatalog::waiters $ticket $callback
    if {$::GX::ApiCatalog::initialized && !($::GX::ApiCatalog::adopt && $::GX::ApiCatalog::progress eq {staging_metadata})} {
        after idle [list ::GX::_apiCatalogReply $ticket [dict create ok 1 result [apiCatalogStatus]]]
    } elseif {$::GX::ApiCatalog::pending eq {}} {set ::GX::ApiCatalog::pending [after idle ::GX::_apiCatalogStart]}
    return $ticket
}
proc ::GX::_apiCatalogReply {ticket response} {
    if {![dict exists $::GX::ApiCatalog::waiters $ticket]} return
    set callback [dict get $::GX::ApiCatalog::waiters $ticket];dict unset ::GX::ApiCatalog::waiters $ticket
    catch {{*}$callback $response}
}
proc ::GX::_apiCatalogNotify {response} {
    set callbacks $::GX::ApiCatalog::waiters;set ::GX::ApiCatalog::waiters {}
    dict for {ticket callback} $callbacks {catch {{*}$callback $response}}
    if {[llength [info commands ::GX::apiBrowserCatalogStatusChanged]]} {apiBrowserCatalogStatusChanged}
}
proc ::GX::_apiCatalogStart {} {
    set ::GX::ApiCatalog::pending {}
    if {$::GX::ApiCatalog::closed} {_apiCatalogNotify {ok 0 error {API catalog service is closed until interpreter restart} code {GX API_CATALOG CLOSED}};return}
    if {$::GX::ApiCatalog::request ne {}} return
    set ::GX::ApiCatalog::progress validating_identity
    if {[catch {
        set fingerprint [_apiCatalogFingerprint];set status [apiCatalogNative validate [_apiCatalogRequire]]
        set packaged [file join $::GX::scriptDir core api_catalog]
        set shipped [_apiCatalogJsonRead [file join $packaged source_manifest.json]]
        if {[apiCatalogNative file_digest [file join $packaged catalog.sqlite]] ne [dict get $shipped database_sha256]} {error {Packaged API catalog integrity changed; previous snapshot preserved}}
    } reason]} {
        set ::GX::ApiCatalog::freshness [expr {$::GX::ApiCatalog::handle eq {}?{unavailable}:{stale}}];set ::GX::ApiCatalog::error $reason;set ::GX::ApiCatalog::progress failed
        _apiCatalogNotify [dict create ok 0 error $reason];return
    }
    if {[dict get $status fingerprint] eq $fingerprint} {
        set ::GX::ApiCatalog::initialized 1
        set ::GX::ApiCatalog::freshness current;set ::GX::ApiCatalog::error {};set ::GX::ApiCatalog::progress complete
        _apiCatalogNotify [dict create ok 1 result [apiCatalogStatus]];return
    }
    # A process retains one definition snapshot. A matching prior staged index
    # may be admitted only at this first initialization, before Browser use.
    set staged [file join $::GX::ApiCatalog::directory pending]
    if {!$::GX::ApiCatalog::initialized && [file isfile [file join $staged source_manifest.json]]} {
        if {![catch {set m [_apiCatalogJsonRead [file join $staged source_manifest.json]];set valid [expr {[dict get $m fingerprint] eq [_apiCatalogFingerprint $m] && [apiCatalogNative file_digest [file join $staged catalog.sqlite]] eq [dict get $m database_sha256]}]}] && $valid} {
            if {[catch {_apiCatalogAdopt [file join $staged catalog.sqlite] $m} reason]} {
                set ::GX::ApiCatalog::initialized 1;set ::GX::ApiCatalog::freshness stale;set ::GX::ApiCatalog::error $reason;set ::GX::ApiCatalog::progress failed
                _apiCatalogNotify [dict create ok 0 error $reason];return
            }
            set ::GX::ApiCatalog::initialized 1;set ::GX::ApiCatalog::freshness current;set ::GX::ApiCatalog::progress complete
            _apiCatalogNotify [dict create ok 1 result [apiCatalogStatus]];return
        }
    }
    set ::GX::ApiCatalog::adopt [expr {!$::GX::ApiCatalog::initialized}]
    set ::GX::ApiCatalog::initialized 1
    set ::GX::ApiCatalog::target $fingerprint;set ::GX::ApiCatalog::freshness stale;set ::GX::ApiCatalog::progress staging_metadata
    set output [file join $::GX::ApiCatalog::directory stage.[pid].[clock clicks]]
    set ::GX::ApiCatalog::staging $output
    set command [list [runtimeToolRequired python] -I -B [file join $::GX::scriptDir core python gxtxt_api_catalog.py] stage [file normalize $::GX::scriptDir] $output]
    if {[catch {set ::GX::ApiCatalog::request [scriptJobAsync $command {} [list ::GX::_apiCatalogReceived $fingerprint $output] {timeout_ms 25000 max_bytes 1048576 process_group 1 ui_lifetime 1 label {API catalog metadata reconciliation}}]} reason]} {
        set ::GX::ApiCatalog::error $reason;set ::GX::ApiCatalog::progress failed;_apiCatalogNotify [dict create ok 0 error $reason]
    }
}
proc ::GX::_apiCatalogReceived {fingerprint output response} {
    if {$::GX::ApiCatalog::closed} return
    set ::GX::ApiCatalog::request {}
    if {[catch {
        if {![dict get $response ok]} {
            set reason [dict get $response error]
            if {[string trim $reason] eq {}} {
                set reason {API catalog metadata reconciliation worker exited without a diagnostic; previous snapshot preserved}
            }
            error $reason
        }
        set result [dict get $response result]
        set m [_apiCatalogJsonRead [file join $output source_manifest.json]]
        # The inert worker may discover binding-owned manuals absent from the
        # previous definition snapshot. Verify both inventories: the originally
        # scheduled installed sources must remain unchanged, and the completed
        # manifest (including those manuals) must still match the worker's
        # before/after identity. A newly referenced manual is not a source race.
        if {[_apiCatalogFingerprint] ne $fingerprint || [dict get $result fingerprint] ne [dict get $m fingerprint] || [_apiCatalogFingerprint $m] ne [dict get $m fingerprint]} {error {Installed sources changed during reconciliation; previous snapshot preserved}}
        if {[apiCatalogNative file_digest [file join $output catalog.sqlite]] ne [dict get $m database_sha256]} {error {Staged catalog integrity differs}}
        set pending [file join $::GX::ApiCatalog::directory pending]
        if {[file exists $pending]} {file rename $pending [file join $::GX::ApiCatalog::directory retained.[clock clicks]]}
        file rename $output $pending
    } reason]} {
        set ::GX::ApiCatalog::freshness stale;set ::GX::ApiCatalog::error $reason;set ::GX::ApiCatalog::progress failed
        _apiCatalogNotify [dict create ok 0 error $reason];return
    }
    if {$::GX::ApiCatalog::adopt} {
        if {[catch {_apiCatalogAdopt [file join $pending catalog.sqlite] $m} reason]} {
            set ::GX::ApiCatalog::freshness stale;set ::GX::ApiCatalog::error $reason;set ::GX::ApiCatalog::progress failed
            _apiCatalogNotify [dict create ok 0 error $reason];return
        }
        set ::GX::ApiCatalog::freshness current
    } else {set ::GX::ApiCatalog::freshness pending_restart}
    set ::GX::ApiCatalog::error {};set ::GX::ApiCatalog::progress complete
    set ::GX::ApiCatalog::target [dict get $m fingerprint]
    set ::GX::ApiCatalog::pendingMetadata [datasetPublicationV2DictDefault $m pending_metadata {}]
    _apiCatalogNotify [dict create ok 1 result [apiCatalogStatus]]
}

proc ::GX::_apiCatalogInspectionFile {path {verify 0} {maximum 1073741824}} {
    set result [dict create path $path present 0 type missing size 0 sha256 {} error {}]
    if {$path eq {} || [catch {file lstat $path st}]} {return $result}
    dict set result present 1;dict set result type $st(type);dict set result size $st(size)
    if {$st(type) ne {file}} {dict set result error {An ordinary non-linked file is required.};return $result}
    if {$st(size)>$maximum} {dict set result error {File exceeds the inspection byte bound.};return $result}
    if {$verify && [catch {dict set result sha256 [apiCatalogNative file_digest $path]} message]} {dict set result error [string range $message 0 2047]}
    return $result
}
proc ::GX::apiCatalogDiagnostics {{verify_sources 0}} {
    if {![string is boolean -strict $verify_sources]} {error {verify_sources must be a boolean}}
    set status [apiCatalogStatus]
    set root [file normalize $::GX::scriptDir];set packaged [file join $root core api_catalog]
    set manifestFile [file join $packaged source_manifest.json]
    set seed [dict create database [_apiCatalogInspectionFile [file join $packaged catalog.sqlite] $verify_sources] manifest [_apiCatalogInspectionFile $manifestFile $verify_sources 4194304] loaded_expected_database_sha256 [dict get $::GX::ApiCatalog::shippedManifest database_sha256] loaded_manifest_fingerprint [dict get $::GX::ApiCatalog::shippedManifest fingerprint]]
    set loaded [dict create cache_directory $::GX::ApiCatalog::directory snapshot [_apiCatalogInspectionFile $::GX::ApiCatalog::snapshot $verify_sources] fingerprint [dict get $status fingerprint] generation [dict get $status generation] manifest_fingerprint [dict get $::GX::ApiCatalog::manifest fingerprint] immutable_definition 1]
    set key [list [dict get $status fingerprint] [dict get $status generation]]
    if {$::GX::ApiCatalog::countsKey ne $key} {
        set summary [apiCatalogNative summary [_apiCatalogRequire]]
        if {[dict get $summary fingerprint] ne [dict get $status fingerprint] || [dict get $summary generation]!=[dict get $status generation]} {error {Catalog summary identity differs from the loaded snapshot.}}
        set counts [dict create total [dict get $summary count] providers [dict get $summary providers]]
        foreach surface {family host script_bridge cpp_sdk} {dict set counts $surface [datasetPublicationV2DictDefault [dict get $summary surfaces] $surface 0]}
        # The native grouping reads no declaration payloads, including when a
        # removed provider remains in the immutable process definition.
        set ::GX::ApiCatalog::counts $counts;set ::GX::ApiCatalog::countsKey $key
    }
    set counts $::GX::ApiCatalog::counts
    set pending [file join $::GX::ApiCatalog::directory pending]
    set next [dict create path $pending manifest [_apiCatalogInspectionFile [file join $pending source_manifest.json] $verify_sources 4194304] database [_apiCatalogInspectionFile [file join $pending catalog.sqlite] $verify_sources] adoption next_process fingerprint {} error {}]
    if {[dict get $next manifest present]} {
        if {[catch {set m [_apiCatalogJsonRead [file join $pending source_manifest.json]];dict set next fingerprint [dict get $m fingerprint];dict set next expected_database_sha256 [dict get $m database_sha256];dict set next pending_metadata [datasetPublicationV2DictDefault $m pending_metadata {}]} message]} {dict set next error [string range $message 0 2047]}
    }
    set verification [dict create attempted [expr {!!$verify_sources}] state not_checked fingerprint {} error {}]
    if {$verify_sources} {
        if {[catch {
            set current [_apiCatalogJsonRead $manifestFile]
            dict set seed current_manifest_fingerprint [dict get $current fingerprint]
            dict set seed current_expected_database_sha256 [dict get $current database_sha256]
            dict set seed database_matches_manifest [expr {[dict get $seed database sha256] eq [dict get $current database_sha256]}]
            set fingerprint [_apiCatalogFingerprint]
            dict set verification fingerprint $fingerprint
            dict set verification state [expr {$fingerprint eq [dict get $status fingerprint]?{current}:{catalog_stale}}]
            if {![dict get $seed database_matches_manifest]} {error {Packaged database checksum differs from the current packaged manifest.}}
        } message]} {dict set verification state failed;dict set verification error [string range $message 0 2047]}
    }
    return [dict create schema gxtxt.api_catalog.diagnostics.v1 status $status framework_root $root framework_identity [dict get $status framework_identity] packaged $seed loaded $loaded active_stage [dict create path $::GX::ApiCatalog::staging request_active [dict get $status request_active] progress [dict get $status progress]] pending_stage $next counts $counts source_verification $verification]
}
proc ::GX::_apiCatalogManualSource {record provider} {
    set meta [dict get $record payload catalog_meta]
    set sources [datasetPublicationV2DictDefault $meta source_members {}]
    set owners {};foreach source $sources {lappend owners [dict get $source provider_id]}
    set owners [lsort -unique $owners]
    if {$provider eq {}} {
        if {[dict get $record surface] ne {family}} {set provider [dict get $record provider_id]} elseif {[llength $owners]==1} {set provider [lindex $owners 0]} else {error {Select an exact provider for this aggregate API family.}}
    }
    set selected {}
    foreach source $sources {
        if {[dict get $source provider_id] ne $provider} continue
        if {$selected eq {} || [dict get $source source_role] eq {host}} {set selected $source}
    }
    if {$selected eq {}} {error {The selected provider does not declare this indexed API.}}
    return [list $provider $selected]
}
proc ::GX::_apiCatalogManualFile {reference moduleRoot} {
    set result [dict create reference $reference path {} present 0 type missing size 0 sha256 {} status invalid_path error {}]
    # Preflight supplies a truthful missing/type diagnosis. Actual file admission
    # remains with the existing Documentation Browser containment owner.
    if {$reference eq {} || [string length $reference]>4096 || [file pathtype $reference] ne {relative} || [string first \\ $reference]>=0 || [string first % $reference]>=0 || [string first \x00 $reference]>=0} {dict set result error {Manual reference must be an ordinary confined relative path.};return $result}
    foreach part [file split $reference] {if {$part in {{} . ..}} {dict set result error {Manual reference contains traversal.};return $result}}
    set roots [list [file normalize $::GX::scriptDir]]
    if {$moduleRoot ne {}} {lappend roots $moduleRoot [file join $moduleRoot docs]}
    set chosen {};set chosenRoot {}
    foreach root $roots {
        set candidate [file join $root $reference];set unsafe 0;set component $root
        foreach part [file split $reference] {set component [file join $component $part];if {![catch {file lstat $component st}] && $st(type) eq {link}} {set unsafe 1;break}}
        if {$unsafe} {dict set result path $candidate;dict set result error {Linked manual path components are unsupported.};return $result}
        if {$chosen eq {}} {set chosen $candidate;set chosenRoot $root}
        if {[file exists $candidate]} {set chosen $candidate;set chosenRoot $root;break}
    }
    set result [dict merge $result [_apiCatalogInspectionFile $chosen 0 2097152]]
    if {![dict get $result present]} {dict set result status file_missing;return $result}
    if {[dict get $result error] ne {} || [string tolower [file extension $chosen]] ni {.md .markdown .txt .html .htm}} {dict set result status invalid_path;dict set result error {Manual must be an ordinary supported document no larger than 2 MiB.};return $result}
    if {[catch {set path [documentationBrowserContainedFile $chosenRoot $reference];dict set result path $path;dict set result sha256 [apiCatalogNative file_digest $path]} message]} {dict set result error [string range $message 0 2047];dict set result status invalid_path;return $result}
    dict set result status available
    return $result
}
proc ::GX::apiCatalogManualInspect {record_id {provider {}} {window {}}} {
    set record [apiCatalogGet $record_id];lassign [_apiCatalogManualSource $record $provider] provider source
    set api [dict get $record api_id];set root [file normalize $::GX::scriptDir]
    set status [apiCatalogStatus];set descriptor [moduleField $provider descriptor {}];set moduleRoot {}
    set sourcePath [file join $root [dict get $source declaration_ref]]
    set core [expr {$provider eq {CORE} || [string match core/* [dict get $source declaration_ref]]}]
    set runtime [apiCatalogProviderState $provider $core]
    set declaration [dict create indexed_reference [dict get $source declaration_ref] indexed_sha256 [dict get $source declaration_sha256] reference [dict get $source declaration_ref] current_sha256 {} explicit_documentation 0 documentation [dict get $source documentation] error {}]
    set currentRef [dict get $source documentation];set reasons {};set primary available;set descriptorSource 0
    dict set declaration current_reference_state indexed_source
    if {$descriptor ne {}} {
        set moduleRoot [file normalize [file dirname $descriptor]]
        set descriptorSource [expr {[file normalize $sourcePath] eq [file normalize $descriptor]}]
        dict set declaration descriptor_reference [file join plugins modules $provider module.ini]
        # A registered Bridge source may deliberately own a different manual.
        # Its exact unchanged snapshot remains authoritative; do not import or
        # reinterpret Python metadata in this presentation inspection path.
    }
    if {$descriptorSource} {
        if {[catch {
            if {![file isfile $descriptor] || [file type $descriptor] eq {link} || [file size $descriptor]>16777216} {error {Installed module descriptor is not an ordinary bounded file.}}
            set d [parseIni $descriptor]
            if {$api ni [splitList [descriptorValue $d public_apis ids {}]]} {error {The installed provider no longer declares this API.}}
            set explicit [dict exists $d public_api.$api.documentation]
            dict set declaration explicit_documentation $explicit
            set currentRef [descriptorValue $d public_api.$api documentation docs/api/$api.md]
            dict set declaration documentation $currentRef
        } message]} {dict set declaration error [string range $message 0 2047];lappend reasons wrong_reference;set primary wrong_reference}
    }
    if {![catch {set info [_apiCatalogInspectionFile $sourcePath 1 16777216]}] && [dict get $info sha256] ne {}} {
        dict set declaration current_sha256 [dict get $info sha256]
        if {[dict get $info sha256] ne [dict get $source declaration_sha256]} {lappend reasons catalog_stale;set primary catalog_stale;dict set declaration current_reference_state requires_reconciliation} else {dict set declaration current_reference_state verified_source}
    } else {lappend reasons catalog_stale;set primary catalog_stale}
    set indexed [_apiCatalogManualFile [dict get $source documentation] {}]
    dict set indexed indexed_status [dict get $source documentation_status]
    set expected [datasetPublicationV2DictDefault [dict get $::GX::ApiCatalog::manifest files] [dict get $source documentation] {}]
    if {$expected ne {} && [dict exists $expected sha256]} {
        dict set indexed indexed_sha256 [dict get $expected sha256]
        if {[dict get $expected sha256] ne [dict get $indexed sha256]} {lappend reasons catalog_stale;if {$primary eq {available}} {set primary catalog_stale}}
    }
    set installed [_apiCatalogManualFile $currentRef $moduleRoot]
    if {[dict get $installed status] ne {available}} {
        set code [dict get $installed status]
        if {$code eq {file_missing} && $descriptorSource && ![dict get $declaration explicit_documentation]} {set code wrong_reference}
        lappend reasons $code
        if {$primary in {available catalog_stale} || $code eq {invalid_path}} {set primary $code}
    }
    set resolver [dict create document_id api:$api path {} status unavailable error {}]
    if {[catch {
        documentationBrowserRefresh
        set resolved [documentationBrowserResolve api:$api]
        dict set resolver path [dict get $resolved path];dict set resolver source_sha256 [dict get $resolved source_sha256];dict set resolver status available
        dict set resolver relation [expr {[dict get $resolved path] eq [dict get $installed path]?{declared_reference}:{different_family_reference}}]
    } message]} {dict set resolver error [string range $message 0 2047]}
    if {[dict get $installed status] eq {available}} {
        set host [expr {$descriptor eq {}?{viewer.interface_builder}:$provider}]
        if {[catch {documentationBrowserManualPathAllowed $host [dict get $installed path]} message]} {
            dict set installed status invalid_path;dict set installed error [string range $message 0 2047]
            lappend reasons invalid_path;set primary invalid_path
        }
    }
    if {![dict get $runtime installed] || ![dict get $runtime enabled]} {lappend reasons module_disabled_or_missing;if {$primary eq {available}} {set primary module_disabled_or_missing}}
    set presentation [dict create state not_attempted correlated 0 rendering_verified 0 error {}]
    if {$window ne {}} {
        if {[catch {set receipt [documentationBrowserManualInspect $window]} message]} {dict set presentation state unavailable;dict set presentation error [string range $message 0 2047]} else {
            set presentation $receipt;dict set presentation correlated 0
            # A reused manual window can now show another document. Its last
            # result is evidence only for this exact source and generation.
            if {[dict get $installed status] eq {available} && [dict get $receipt path] eq [dict get $installed path] && [dict get $receipt source_sha256] eq [dict get $installed sha256] && [dict get $receipt generation]>0} {
                dict set presentation correlated 1
                if {[dict get $receipt state] eq {error}} {lappend reasons document_viewer_error;set primary document_viewer_error}
            }
        }
    }
    return [dict create schema gxtxt.api_catalog.manual_inspection.v1 status $primary reasons [lsort -unique $reasons] record_id $record_id api_id $api provider_id $provider framework_root $root fingerprint [dict get $status fingerprint] generation [dict get $status generation] declaration $declaration indexed_document $indexed installed_document $installed resolver $resolver runtime_state $runtime presentation $presentation]
}
proc ::GX::apiCatalogManualOpen {record_id {provider {}} {parent {}}} {
    set result [apiCatalogManualInspect $record_id $provider]
    if {[dict get $result installed_document status] ne {available}} {return $result}
    set module [dict get $result provider_id]
    if {[moduleField $module descriptor {}] eq {}} {set module viewer.interface_builder}
    if {[catch {
        if {[dict get $result resolver status] eq {available} && [dict get $result installed_document path] eq [dict get $result resolver path]} {
            set window [documentationBrowserOpenApiWindow [dict get $result api_id] $module $parent]
        } else {
            set window [documentationBrowserOpenReferenceWindow [dict get $result installed_document path] $module $parent]
        }
    } message]} {
        dict set result status document_viewer_error;dict lappend result reasons document_viewer_error
        dict set result presentation [dict create state error correlated 0 rendering_verified 0 error [string range $message 0 2047]]
        return $result
    }
    set result [apiCatalogManualInspect $record_id [dict get $result provider_id] $window]
    dict set result window $window
    return $result
}

proc ::GX::apiCatalogStartup {} {
    if {![info exists ::GX::moduleOrder] || $::GX::ApiCatalog::initialized} return
    apiCatalogRefresh [list ::GX::_apiCatalogStartupResult]
}
proc ::GX::_apiCatalogStartupResult {response} {
    # Diagnostics remain public status; browsing can retain a marked old snapshot.
    return $response
}
after idle ::GX::apiCatalogStartup
