# SPDX-License-Identifier: GPL-3.0-or-later
# Target-specific transport only. Existing Module/Job/Resource/Acquisition and
# Publication owners retain admission, lifetime, RAW and atomic commit authority.
namespace eval ::GX::AcquisitionNative {variable calls {};variable serial 0}
proc ::GX::acquisitionHandlerNativeHelperAvailable {} {
    foreach relative {core/python/gxtxt_acquisition_helper_broker_v1.py core/python/gxtxt_acquisition_helper_worker_v1.py core/tcl/acquisition_helper_worker_v1.tcl core/tcl/native_workspace_api_v1.tcl core/workspace/libgxtxt_workspace.so} {
        if {![file isfile [file join $::GX::scriptDir $relative]]} {return 0}
    }
    return 1
}
proc ::GX::_acquisitionNativeSessionToken {} {return [expr {$::GX::currentSession eq {}?{}:[interactiveDocumentSessionToken]}]}
proc ::GX::_acquisitionNativeDefinition {module definition} {
    set version [moduleField $module version {}]
    if {[dict exists $definition producer_version] && [dict get $definition producer_version] ne $version} {error {Native output producer version differs from the admitted package}}
    if {[dict exists $definition publication_module] && [dict get $definition publication_module] ne $module} {error {Native output cannot select a different producer}}
    dict set definition producer_version $version
    return $definition
}

proc ::GX::_acquisitionNativeMetadata {module} {
    set root [file normalize [file dirname [moduleField $module descriptor {}]]]
    set path [file join $root source project.json]
    file lstat $path st
    if {$st(type) ne {file} || $st(nlink)!=1 || $st(size)>65536} {error {Invalid native Acquisition metadata}}
    set f [open $path rb];try {set raw [read $f 65537]} finally {close $f}
    set meta [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [encoding convertfrom utf-8 $raw]]]
    if {[dict get $meta schema] ne {gxtxt.acquisition_development_project.v1} || [dict get $meta module_id] ne $module} {error {Native Acquisition identity differs from its registered module}}
    return $meta
}
proc ::GX::_acquisitionNativeProfile {module {meta {}}} {
    if {$meta eq {}} {set meta [_acquisitionNativeMetadata $module]}
    set id [expr {[info exists ::GX::moduleCfg($module,format_profile)]?$::GX::moduleCfg($module,format_profile):[moduleConfigField $module format_profile default {}]}]
    foreach profile [dict get $meta formats] {if {[dict get $profile id] eq $id} {return $profile}}
    error {Select a declared native Acquisition format profile}
}
proc ::GX::acquisitionHandlerNativeLoad {module} {
    if {[moduleField $module kind {}] ne {acquisition} || [moduleField $module runner {}] ne {standard_tcl}} {error {Native Acquisition requires an ordinary registered Acquisition module}}
    pluginRuntimeGuardNewLoad $module
    set hid [moduleRunnerHandler $module]
    if {$hid ne "[string map {. _} $module]_managed_cpp_v1"} {error {Native handler identity must match its registered module}}
    if {[acquisitionHandlerRegistered $hid] && [acquisitionHandlerField $hid runtime {}] eq {managed_cpp}} {
        if {[acquisitionHandlerField $hid module_id {}] ne $module} {error {Native handler belongs to a different producer}}
        return $hid
    }
    set receipt [viewerDevelopmentPackageVerify [file dirname [moduleField $module descriptor {}]]]
    if {[dict get $receipt schema] ne {gxtxt.acquisition_runtime_admission.v1} || [dict get $receipt module_id] ne $module} {error {Native Acquisition admission identity differs}}
    acquisitionHandlerRegister $hid [dict create module_id $module kind plugin runtime managed_cpp \
        inspect_proc ::GX::_acquisitionNativeInspect group_inspect_proc ::GX::_acquisitionNativeInspect \
        import_proc ::GX::_acquisitionNativeImport supports_batch 1 variable_mapping optional source_kind text \
        capabilities [join [acquisitionHandlerDeclaredCapabilities $module] {;}] \
        formats [acquisitionHandlerSectionField $module formats {}] _extensions_validated 1]
    pluginRuntimeNoteLoaded $module
    return $hid
}
proc ::GX::_acquisitionNativeConfigInt64 {value} {
    # UI Field's general integer domain includes Tcl bignums. The Acquisition
    # JSON/SDK field is explicitly signed64; check before native conversion,
    # whose Tcl wide-integer adapter can retain only the low64 bits.
    if {![string is entier -strict $value] || $value < -9223372036854775808 || $value > 9223372036854775807} {error {Acquisition integer configuration exceeds the signed 64-bit range}}
    return [expr {$value+0}]
}
proc ::GX::_acquisitionNativeConfig {module} {
    set fields {}
    foreach key [moduleConfigKeys $module] {
        set d [dict create type [moduleConfigField $module $key type string] label [moduleConfigField $module $key label $key] required [moduleConfigField $module $key required 0]]
        foreach name {min max} {set value [moduleConfigField $module $key $name {}];if {$value ne {}} {dict set d $name $value}}
        if {[dict get $d type] eq {choice}} {dict set d values [splitList [moduleConfigField $module $key values {}]]}
        set value [expr {[info exists ::GX::moduleCfg($module,$key)]?$::GX::moduleCfg($module,$key):[moduleConfigField $module $key default {}]}]
        set value [uiFieldNormalize $d $value]
        set kind [dict get $d type]
        if {$kind eq {integer}} {set value [_acquisitionNativeConfigInt64 $value]}
        set kind [expr {$kind eq {integer}?{int}:($kind eq {boolean}?{bool}:($kind in {number double}?{real}:{text}))}]
        dict set fields $key [list $kind $value]
    }
    return [list object $fields]
}
proc ::GX::_acquisitionNativePins {module receipt meta {operations {}}} {
    set root [file normalize [file dirname [moduleField $module descriptor {}]]]
    set pins {}
    set names {module.ini native/acquisition.so native/gxtxt_acquisition_sdk_v1.hpp native/trusted_acquisition_adapter_v1.cpp native/ACQUISITION_SDK_CONTRACT.json native/acquisition-factory.cpp review/build.json source/project.json source/SOURCE_MANIFEST.json}
    foreach name [viewerDevelopmentSourceFiles [file join $root source]] {lappend names source/$name}
    foreach name $names {
        set path [file join $root $name];file lstat $path st
        if {$st(type) ne {file} || $st(nlink)!=1 || [file normalize $path] ne $path} {error {Native Acquisition closure is no longer ordinary}}
        dict set pins $path [sha256File $path]
    }
    dict for {path sha} [dict get $receipt runtime_contract] {dict set pins $path $sha}
    foreach name {gxtxt_acquisition_host_service_v1.py gxtxt_acquisition_broker_v1.py gxtxt_acquisition_source_v1.py gxtxt_acquisition_output_v1.py gxtxt_acquisition_native_worker_v1.py gxtxt_native_read_policy_v1.py gxtxt_acquisition_project_v1.py gxtxt_acquisition_cpp_v1.py gxtxt_cpp_policy.py gxtxt_job_supervisor.py gxtxt_acquisition_spectrum_v1.py scientific_spectrum_import.py gxtxt_acquisition_development_v1.py gxtxt_acquisition_sdk_compat_v1.py} {
        set path [file join $::GX::scriptDir core python $name];dict set pins $path [sha256File $path]
    }
    foreach name {scientific_spectrum_api_v1.tcl scientific_spectrum_import_api_v1.tcl scientific_reference_library_api_v1.tcl} {
        set path [file join $::GX::scriptDir core tcl $name];dict set pins $path [sha256File $path]
    }
    if {{helper_call} in $operations} {
        foreach relative {core/python/gxtxt_acquisition_helper_broker_v1.py core/python/gxtxt_acquisition_helper_worker_v1.py core/tcl/acquisition_helper_worker_v1.tcl core/tcl/native_workspace_api_v1.tcl core/workspace/libgxtxt_workspace.so} {
            set path [file join $::GX::scriptDir $relative];dict set pins $path [sha256File $path]
        }
    }
    foreach {path key} {module.ini manifest_sha256 native/acquisition.so binary_sha256 source/project.json project_sha256 review/build.json build_receipt_sha256} {
        if {[dict get $pins [file join $root $path]] ne [dict get $receipt $key]} {error {Native package changed after admission}}
    }
    return $pins
}
proc ::GX::_acquisitionNativeLive {marker} {
    variable ::GX::AcquisitionNative::calls
    set call [dict get $calls $marker]
    if {[dict get $call token] ne [_acquisitionNativeSessionToken]} {error {Session incarnation changed during native Acquisition}}
    _acquisitionManagedCheck
    set module [dict get $call module]
    pluginRuntimeGuardNewLoad $module
    if {![moduleIsEnabled $module]} {error {Native Acquisition module was disabled}}
    foreach dependency [dict get $call profile dependencies] {if {![moduleIsEnabled $dependency]} {error "Native profile dependency '$dependency' is unavailable"}}
    if {[moduleField $module descriptor {}] ne [dict get $call descriptor] ||
        [moduleField $module version {}] ne [dict get $call version] ||
        [_acquisitionNativeProfile $module] ne [dict get $call profile]} {error {Native Acquisition module/profile admission changed}}
    set namespace [expr {$::GX::currentSession eq {}?{}:[datasetNamespaceCurrentGet $::GX::currentSession]}]
    if {$namespace ne [dict get $call namespace]} {error {Acquisition Namespace changed; review and retry}}
    if {[_acquisitionNativeConfig $module] ne [dict get $call config]} {error {Acquisition settings changed; review and retry}}
    return 1
}
proc ::GX::_acquisitionNativeDone {marker response} {
    variable ::GX::AcquisitionNative::calls
    if {![dict exists $calls $marker]} return
    dict set calls $marker done 1
    if {![dict exists $calls $marker response]} {dict set calls $marker response [dict create ok 0 error {Native CORE service ended before handoff}]}
    set ::GX::AcquisitionNative::wake [clock clicks]
}
proc ::GX::_acquisitionNativePoll {marker} {
    variable ::GX::AcquisitionNative::calls
    if {![dict exists $calls $marker] || [dict get $calls $marker done] || [dict exists $calls $marker response]} return
    set id [dict get $calls $marker job]
    if {[catch {
        _acquisitionNativeLive $marker
        set drained [scriptJobRequestDrain $id]
        foreach line [dict get $drained messages] {
            if {[string bytelength $line]>1398104} {error {Native CORE frame exceeded its bound}}
            set message [encoding convertfrom utf-8 [binary decode base64 -strict $line]]
            if {[dict get $message kind] eq {complete}} {
                dict set calls $marker response $message
                scriptJobRequestSend $id {{"done":true}}
                set ::GX::AcquisitionNative::wake [clock clicks]
                break
            }
            if {[dict get $message kind] ne {core_call} || [dict get $message sequence] != [dict get $calls $marker sequence]+1} {error {Native CORE callback sequence differs}}
            dict set calls $marker sequence [dict get $message sequence]
            set operation [dict get $message operation]
            set payload [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [dict get $message payload_json]]]
            set replyResult [list bool 1]
            switch -- $operation {
                live {_acquisitionNativeLive $marker}
                scientific_spectrum_validate {
                    set call [dict get $calls $marker]
                    if {[lsort [dict keys $payload]] ne {format options row_count source_identity source_index source_sha256}} {error {Scientific source validation shape differs}}
                    set index [dict get $payload source_index]
                    if {![string is integer -strict $index] || $index<0 || $index>=[llength [dict get $call sources]]} {error {Scientific source is outside the actual request}}
                    set source [lindex [dict get $call sources] $index]
                    if {[dict get $payload source_identity] ne "acquisition-source:[dict get $call request_id]:$index" || ([dict get $source sha256] ne {} && [dict get $source sha256] ne [dict get $payload source_sha256])} {error {Scientific source validation identity differs}}
                    set options [dict get $payload options];dict set options source_identity [dict get $payload source_identity]
                    set validated [::GX::SpectrumImportAPIv1::validateSource [dict get $payload format] [dict get $source path] $options [dict get $payload source_sha256] [dict get $payload row_count]]
                    _acquisitionNativeLive $marker
                    set replyResult [nativeWorkspaceEncode {map text} $validated]
                }
                preflight {
                    set call [dict get $calls $marker]
                    if {[dict get $call phase] ni {test import}} {error {Inspection cannot publish}}
                    set definition [_acquisitionNativeDefinition [dict get $call module] [dict get $payload definition]]
                    if {[datasetPublicationV2DictDefault $definition replace_owned 0]} {error {Native Acquisition creates new outputs; replacement is not admitted}}
                    dict set definition capabilities_required [lsort -unique [concat typed_numeric [datasetPublicationV2DictDefault $definition capabilities_required {}]]]
                    if {[dict get $definition contract] ni [dict get $call profile output_contracts]} {error {Output contract was not admitted for this profile}}
                    if {[dict get $call phase] eq {import}} {
                        datasetPublicationV2BatchPreflight $::GX::currentSession [dict get $call module] [list $definition]
                    } else {
                        datasetPublicationV2ValidateId dataset [dict get $definition dataset_id]
                        if {![contractRegistryKnown [dict get $definition contract]]} {error {Test output contract is unknown}}
                    }
                }
                progress {acquisitionHandlerInvokeCallback [dict get $calls $marker callbacks progress_callback] $payload}
                default {error {Unsupported CORE native callback}}
            }
            scriptJobRequestSend $id [format {{"sequence":%s,"ok":true,"result":%s}} [dict get $message sequence] [nativeWorkspaceJsonEncode $replyResult]]
        }
        if {![dict exists $calls $marker response] && (![dict get $drained active] || [dict get $drained cancelled] ne {})} {error {Native managed request was retired}}
    } reason]} {
        if {[dict exists $calls $marker]} {dict set calls $marker response [dict create ok 0 error $reason];scriptJobRequestCancel $id cancelled;set ::GX::AcquisitionNative::wake [clock clicks]}
        return
    }
    if {[dict exists $calls $marker] && ![dict get $calls $marker done] && ![dict exists $calls $marker response]} {dict set calls $marker timer [after 10 [list ::GX::_acquisitionNativePoll $marker]]}
}
proc ::GX::acquisitionHandlerNativeInvoke {module phase request} {
    variable ::GX::AcquisitionNative::calls
    if {$phase ni {recognize inspect test import}} {error {Unsupported native Acquisition phase}}
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Native source dispatch requires explicit host Acquisition authority}}
    acquisitionHandlerNativeLoad $module
    if {![moduleIsEnabled $module]} {error {Enable the registered Acquisition module before execution}}
    set root [file normalize [file dirname [moduleField $module descriptor {}]]]
    set receipt [viewerDevelopmentPackageVerify $root]
    if {[dict get $receipt schema] ne {gxtxt.acquisition_runtime_admission.v1} || [dict get $receipt module_id] ne $module} {error {Native Acquisition admission identity differs}}
    set meta [_acquisitionNativeMetadata $module];set profile [_acquisitionNativeProfile $module $meta]
    set config [_acquisitionNativeConfig $module]
    set ops {}
    foreach row [dict get $profile capabilities] {
        if {[dict get $row api_id] ne {ACQUISITION_HANDLER_PLUGIN_API_v1} || [dict get $row version] ne {1}} continue
        foreach operation [dict get $row operations] {if {$operation ni [dict get $receipt requested ACQUISITION_HANDLER_PLUGIN_API_v1]} {error {Profile exceeds module capabilities}};lappend ops $operation}
    }
    if {{helper_call} in $ops && ![acquisitionHandlerNativeHelperAvailable]} {error {Managed helper runtime is unavailable}}
    set pins [_acquisitionNativePins $module $receipt $meta $ops]
    set allocation [resourceManagementAllocate acquisition_publication [dict create kind directory session $::GX::currentSession lifetime computation]]
    _acquisitionManagedResourceTrack $allocation
    set resource [dict get $allocation path]
    set marker native-[pid]-[incr ::GX::AcquisitionNative::serial]
    set job {}
    try {
        set buffer [file join $resource buffers];file mkdir $buffer;file attributes $buffer -permissions 0700
        set f [open /dev/urandom rb];try {set opaque [binary encode hex [read $f 32]]} finally {close $f}
        if {[string length $opaque]!=64} {error {Secure CORE request identity unavailable}}
        set token [_acquisitionNativeSessionToken]
        set snapshot [dict create manifest_sha256 [dict get $receipt manifest_sha256] binary_sha256 [dict get $receipt binary_sha256] project_sha256 [dict get $receipt project_sha256] source_tree_sha256 [dict get $receipt source_tree_sha256] profile_sha256 [dict get $receipt profile_sha256 [dict get $profile id]]]
        if {[dict exists $receipt config_schema_sha256]} {dict set snapshot config_schema_sha256 [dict get $receipt config_schema_sha256]}
        set scope [dict create request_id $opaque phase $phase module_id $module qualified_profile $module/[dict get $profile id] module_snapshot $snapshot session_token $token]
        set paths [expr {[dict exists $request source_paths]?[dict get $request source_paths]:[list [dict get $request source_path]]}]
        set sources {};foreach path $paths {lappend sources [dict create path [file normalize $path] logical_name [file tail $path] sha256 [expr {$phase in {test import}?[sha256File $path]:{}}]]}
        set typedSources {};foreach source $sources {set fields {};dict for {key value} $source {dict set fields $key [expr {$key eq {sha256} && $value eq {}?[list null {}]:[list text $value]}]};lappend typedSources [list object $fields]}
        set runtime [dict create library [dict get $receipt library] binary_sha256 [dict get $receipt binary_sha256] sdk_sha256 [dict get $receipt sdk_sha256] buffer_root $buffer native_output_path [file join $buffer native.log]]
        set lease {};if {$::GX::AcquisitionManaged::worker ne {}} {set lease [dict create path [dict get $::GX::AcquisitionManaged::worker lease] session_token [dict get $::GX::AcquisitionManaged::worker session_token]]}
        set mapping [dict create variables [nativeWorkspaceEncode {array {map text}} [datasetPublicationV2DictDefault $request variables {}]] dataset_id [list text [datasetPublicationV2DictDefault $request dataset_id {}]] contract [list text [datasetPublicationV2DictDefault $request contract {}]]]
        set typed [dict create schema [list text gxtxt.core_acquisition_bootstrap.v1] scope [nativeWorkspaceEncode {record {request_id text phase text module_id text qualified_profile text module_snapshot {map text} session_token text}} $scope] sources [list array $typedSources] runtime [nativeWorkspaceEncode {map text} $runtime] config $config mapping [list object $mapping] limits [nativeWorkspaceEncode {record {slice_bytes int datasets int variables int}} {slice_bytes 65536 datasets 64 variables 128}] admitted_operations [nativeWorkspaceEncode {array text} $ops] pins [nativeWorkspaceEncode {map text} $pins] lease [nativeWorkspaceEncode {map text} $lease]]
        set namespace [expr {$::GX::currentSession eq {}?{}:[datasetNamespaceCurrentGet $::GX::currentSession]}]
        dict set calls $marker [dict create module $module descriptor [moduleField $module descriptor {}] version [moduleField $module version {}] phase $phase token $token namespace $namespace profile $profile config $config sources $sources request_id $opaque callbacks [acquisitionHandlerRequestCallbacks $module] sequence 0 done 0 timer {}]
        set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_acquisition_host_service_v1.py]]
        set job [scriptJobAsync $command "[nativeWorkspaceJsonEncode [list object $typed]]\n" [list ::GX::_acquisitionNativeDone $marker] {timeout_ms 3600000 max_bytes 1398104 process_group 1 duplex 1 ui_lifetime 1 send_pending_bytes 1048576 label {Native Acquisition}}]
        dict set calls $marker job $job
        _acquisitionNativePoll $marker
        while {![dict exists $calls $marker response]} {vwait ::GX::AcquisitionNative::wake}
        set response [dict get $calls $marker response]
        if {![dict get $response ok]} {error [dict get $response error]}
        set result [dict get $response result]
        if {![dict get $result actor_reaped]} {error {Native actor was not reaped}}
        set declarations {}
        foreach item [dict get $result prepared_publications] {
            set definition [_acquisitionNativeDefinition $module [dict get $item definition]]
            set metadata [datasetPublicationV2DictDefault $definition structured_metadata {}]
            set provenance [dict create acquisition.native_result_json [dict get $result native_result_json] acquisition.config_json [dict get $result config_json] acquisition.config_sha256 [dict get $result config_sha256] acquisition.module_manifest_sha256 [dict get $receipt manifest_sha256] acquisition.binary_sha256 [dict get $receipt binary_sha256] acquisition.profile $module/[dict get $profile id] acquisition.profile_sha256 [dict get $receipt profile_sha256 [dict get $profile id]]]
            dict set provenance acquisition.source_kind [dict get $profile source_kind]
            if {[dict exists $receipt config_schema_sha256]} {dict set provenance acquisition.config_schema_sha256 [dict get $receipt config_schema_sha256]}
            dict for {key value} $provenance {if {[dict exists $metadata $key] && [dict get $metadata $key] ne $value} {error {Producer attempted to replace CORE provenance}};dict set metadata $key $value}
            dict set definition structured_metadata $metadata;dict set item definition $definition
            set variables {}
            foreach variable [dict get $item variables] {
                set source [dict get $variable path];set pin [dict get $variable sha256]
                if {[file dirname $source] ne $buffer || [file type $source] ne {file} || [sha256File $source] ne $pin} {error {Sealed native output identity or SHA changed}}
                if {$phase eq {import}} {
                    set name native-[file tail $source];set dest [file join [dict get $request output_dir] $name]
                    file copy -- $source $dest
                    if {[sha256File $dest] ne $pin || [sha256File $source] ne $pin} {error {Native output changed during transaction adoption}}
                    dict set variable path $name
                }
                lappend variables $variable
            }
            dict set item variables $variables;lappend declarations $item
        }
        set actual [dict get $result result]
        if {$phase eq {import}} {
            set actual [dict remove $actual prepared_outputs]
            foreach key [dict keys $actual] {if {$key ni {dataset_group warnings metadata}} {error {Native import returned an unsupported publication field}}}
            set actual [dict remove $actual metadata]
            dict set actual datasets {};dict set actual prepared_publications $declarations
            dict set actual prepared_buffers_consumable 1
            dict set actual source_kind [dict get $profile source_kind]
        } elseif {$phase eq {test}} {
            set actual [dict create status PASS actor_reaped 1 discarded_outputs [llength $declarations] scientific_acceptance 0]
        } else {
            dict set actual source_kind [dict get $profile source_kind]
        }
        _acquisitionNativeLive $marker
        return $actual
    } finally {
        if {[dict exists $calls $marker timer] && [dict get $calls $marker timer] ne {}} {after cancel [dict get $calls $marker timer]}
        if {$job ne {} && [dict exists $::GX::scriptJobRequests $job]} {
            scriptJobRequestCancel $job closed
            while {[dict exists $::GX::scriptJobRequests $job]} {vwait ::GX::AcquisitionNative::wake}
        }
        if {[dict exists $calls $marker]} {dict unset calls $marker}
        resourceManagementRelease [dict get $allocation id]
        resourceManagementCleanup [list [dict get $allocation id]]
    }
}
proc ::GX::_acquisitionNativeInspect {request} {return [acquisitionHandlerNativeInvoke [dict get $request module_id] inspect $request]}
proc ::GX::_acquisitionNativeImport {request} {return [acquisitionHandlerNativeInvoke [dict get $request module_id] import $request]}
