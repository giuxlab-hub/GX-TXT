# SPDX-License-Identifier: GPL-3.0-or-later
# Disposable representations owned by Dataset Preview. Dataset Authority,
# Configuration, Resource Management and Script Jobs keep their existing roles.
namespace eval ::GX::PreviewCache {variable tasks {};variable remoteVerified {};variable outcomes {};variable renderer {};variable worker 0;variable hits 0;variable misses 0;variable watches {};variable watchSerial 0;variable watchCalling 0;variable managedSerial 0}
proc ::GX::datasetPreviewCacheInit {} {
    foreach {id type default label} {preview.cache_enabled boolean 1 {Prepare Dataset previews after publication} preview.cache_mib integer 64 {Session Preview cache limit (MiB)}} {
        if {![dict exists [configurationFields] $id]} {configurationRegister $id [dict create group Viewers label $label type $type default $default scope user]}
    }
}
proc ::GX::datasetPreviewCacheRoot {session} {
    set session [_sessionInspectionRequire $session]
    set root $session
    foreach part {cache dataset_previews} {
        set root [file join $root $part]
        if {![catch {file lstat $root status}] && $status(type) eq "link"} {error {Preview cache symlinks are forbidden}}
    }
    return $root
}
proc ::GX::datasetPreviewCacheSource {id} {return [datasetViewerScientificIdentity $id]}
proc ::GX::_datasetPreviewCacheScientificOptions {options} {
    # Retained preparation keeps all curves; visibility only changes the
    # presentation of that geometry. Preserve every scientific selection and
    # reject malformed maps rather than masking them with an empty default.
    if {[dict exists $options selections]} {
        dict set options selections [dict remove [dict get $options selections] @hidden_filters]
    }
    return $options
}
proc ::GX::datasetPreviewCacheKey {id {options {}}} {
    variable ::GX::PreviewCache::renderer
    set configured [_datasetPreviewConfiguredOptions $id]
    set options [dict merge $configured $options]
    # Project both terms: captured render options can override current defaults,
    # but genuine saved scientific configuration changes must still invalidate.
    set configured [_datasetPreviewCacheScientificOptions $configured]
    set options [_datasetPreviewCacheScientificOptions $options]
    if {$renderer eq {}} {
        set renderer gxtxt.preview.retained.v1
        foreach relative {
            core/tcl/dataset_preview_cache.tcl core/tcl/dataset_preview_worker_v1.tcl core/tcl/scientific_dataset_filters_v1.tcl
            core/tcl/dataset_digitizer_preview_v1.tcl core/python/dataset_digitizer_quality_summary_v1.py
            core/tcl/dataset_preview_api_v1.tcl core/tcl/scientific_dataset_preview_v1.tcl
            core/tcl/dataset_preview_provider_v1.tcl core/tcl/dataset_preview_native_v1.tcl core/tcl/preview_descriptor_api_v1.tcl
            core/tcl/scientific_dataset_filter_configuration_v1.tcl core/tcl/dataset_viewer_api_v1.tcl
            core/tcl/curve_source_api_v1.tcl core/tcl/dataset_coordinate_context_v1.tcl
            core/tcl/scientific_dataset_coordinates_v1.tcl
            core/tcl/mesh_dataset_viewer_v1.tcl core/native2d/bin/gx2dtcl.so
            core/tcl/native2d_presentation_v1.tcl core/tcl/native2d_axis_presentation_v1.tcl
            core/native3d/renderer_worker.tcl core/native3d/bin/libgx3de_viewer_tcl.so
            plugins/modules/plot.dataset/api/plot_dataset_api_v4.tcl
            plugins/modules/plot.dataset/api/plot_dataset_v4_consultation.tcl
            plugins/modules/viewer.curve_digitizer/api/curve_digitizer_quality_api_v2.tcl
            plugins/modules/viewer.curve_digitizer/api/curve_digitizer_image_processing_api_v1.tcl
        } {lappend renderer $relative [sha256File [file join $::GX::scriptDir $relative]]}
    }
    set settings {}
    foreach name [dict keys [previewSettingsDefaults]] {if {![string match *open* $name]} {lappend settings $name [previewSetting $name]}}
    if {[string tolower [datasetField $id format]] in {stl obj step stp vtp vtu vti}} {lappend settings native3d [native3dGraphicsPolicy]}
    set linked {}
    if {[dict exists $options processed_image dataset_id]} {
        set linked [datasetViewerLinkedSourceIdentity $::GX::currentSession [dict get $options processed_image dataset_id]]
    }
    # Options are a map: insertion order must not trigger another preparation.
    # Keep values intact, including scientifically meaningful grouping lists.
    set orderedOptions {}
    foreach name [lsort [dict keys $options]] {dict set orderedOptions $name [dict get $options $name]}
    return [datasetStorageSha256Text $::GX::currentSession [list [sessionOriginRead $::GX::currentSession] [datasetPreviewCacheSource $id] $orderedOptions $linked $renderer $settings $configured [datasetPreviewProviderIdentity $id]]]
}
proc ::GX::datasetPreviewCachePath {session key} {
    if {![regexp {^[0-9a-f]{64}$} $key]} {error {Invalid Preview cache key}}
    set path [file join [datasetPreviewCacheRoot $session] $key]
    if {![catch {file lstat $path status}] && $status(type) eq "link"} {error {Preview cache entry symlinks are forbidden}}
    return $path
}
proc ::GX::datasetPreviewCacheRead {id key {allowStale 0}} {
    variable ::GX::PreviewCache::hits
    set dir [datasetPreviewCachePath $::GX::currentSession $key]
    set path [file join $dir representation.tcldict]
    if {![file isfile $path] || [file type $path] eq "link" || [file size $path]>16777216} {return {}}
    set digest [file join $dir SHA256]
    if {![file isfile $digest] || [file type $digest] eq "link"} {return {}}
    set f [open $digest r];try {set expected [string trim [read $f 128]]} finally {close $f}
    if {[sha256File $path] ne $expected} {return {}}
    set f [open $path r];fconfigure $f -encoding utf-8;try {set result [read $f 16777217]} finally {close $f}
    # A matching digest verifies bytes, not the representation's structure.
    # Disposable cache damage/unsupported records must be a cache miss, never a
    # missing-dictionary-key error that prevents normal Preview preparation.
    if {[catch {dict size $result}]} {return {}}
    foreach field {schema dataset_id key source options} {
        if {![dict exists $result $field]} {return {}}
    }
    if {[dict get $result schema] ne {gxtxt.session_preview.v1} ||
        [dict get $result dataset_id] ne $id || [dict get $result key] ne $key ||
        [catch {dict size [dict get $result options]}]} {return {}}
    # The native consumer needs both the prepared model envelope and its row
    # counts. Admit neither a partial native record nor invalid count text as a
    # hit: preparation must get a chance to replace the disposable record.
    set native [dict exists $result native_model]
    if {[dict exists $result kind] && [dict get $result kind] eq {native2d}} {set native 1}
    if {$native} {
        foreach field {native_model row_count displayed_points} {
            if {![dict exists $result $field]} {return {}}
        }
        set model [dict get $result native_model]
        if {[catch {dict size $model}] || ![dict exists $model panels] ||
            [catch {llength [dict get $model panels]}]} {return {}}
        foreach field {row_count displayed_points} {
            set value [dict get $result $field]
            if {![string is entier -strict $value] || $value<0} {return {}}
        }
    }
    if {[dict exists $result artifacts]} {
        if {[catch {dict size [dict get $result artifacts]}]} {return {}}
        dict for {name expected} [dict get $result artifacts] {
            if {[file tail $name] ne $name} {return {}}
            set artifact [file join $dir $name]
            if {![file isfile $artifact] || [file type $artifact] eq "link" || [sha256File $artifact] ne $expected} {return {}}
        }
    }
    set currentKey [datasetPreviewCacheKey $id [dict get $result options]]
    set current [expr {[dict get $result source] eq [datasetPreviewCacheSource $id] && $key eq $currentKey}]
    if {!$current && !$allowStale} {return {}}
    if {[datasetField $id storage_provider {}] eq "remote"} {
        if {![llength [info commands ::winfo]]} {datasetRemoteVerify $id} elseif {![dict exists $::GX::PreviewCache::remoteVerified $key] || [dict get $::GX::PreviewCache::remoteVerified $key] ne [interactiveDocumentSessionToken]} {
            set current 0;dict set result remote_unverified 1
        }
    }
    dict set result current $current
    if {$key ne $currentKey} {dict set result invalidation_reason {Scientific source, render options, renderer implementation or configured preparation settings changed}}
    incr hits
    return $result
}
proc ::GX::datasetPreviewCacheGenerate {id options {expectedKey {}}} {
    variable ::GX::PreviewCache::worker
    set prior $worker;set worker 1
    try {
        loadDatasetRegistry $::GX::currentSession
        set options [dict merge [_datasetPreviewConfiguredOptions $id] $options]
        set key [datasetPreviewCacheKey $id $options]
        if {$expectedKey ne {} && $key ne $expectedKey} {error {Preview source changed before preparation}}
        set cached [datasetPreviewCacheRead $id $key]
        if {$cached ne {}} {return $cached}
        set source [datasetPreviewCacheSource $id]
        set dir [datasetPreviewCachePath $::GX::currentSession $key];file mkdir $dir
        file delete -force [file join $dir PREPARE_ERROR.tcldict]
        set result [_datasetPreviewCachePrepare $id $options $key $source $dir]
        set bytes [encoding convertto utf-8 $result]
        if {[string length $bytes]>16777216} {error {Prepared Preview exceeds the 16 MiB representation bound}}
        set path [file join $dir representation.tcldict]
        resourceLifecycleWriteBytes $path $bytes
        resourceLifecycleWriteBytes [file join $dir SHA256] [encoding convertto utf-8 [sha256File $path]]
        resourceManagementObserve $dir dataset_preview [dict create category cache_reusable session $::GX::currentSession]
        datasetPreviewCacheEvict $::GX::currentSession $key
        return $result
    } finally {set worker $prior}
}
# One preparation body for the normal cache writer and the reviewed future
# managed-worker publication owner. The caller owns the destination and captures
# source/options/key; this helper neither publishes a representation nor grants
# native admission. No worker request can select a destination through this API.
proc ::GX::_datasetPreviewCachePrepare {id options key source dir} {
    variable ::GX::PreviewCache::worker
    set prior $worker;set worker 1
    try {
        set result [dict create schema gxtxt.session_preview.v1 dataset_id $id key $key source $source options $options generated_at [clock format [clock seconds] -gmt 1 -format %Y-%m-%dT%H:%M:%SZ] kind descriptive status ready]
        if {[datasetProviderFor $id] eq "remote"} {
            set remote [scientificExecutionRemoteCall [datasetField $id remote_node_id] [datasetField $id remote_session_id] dataset.preview $id [datasetField $id remote_revision] $options $dir]
            foreach field {native_model axes dimensions selections row_count displayed_points digitizer media_artifact description} {if {[dict exists $remote $field]} {dict set result $field [dict get $remote $field]}}
            dict set result kind [dict get $remote kind]
        } else {
            set payload [sessionInspectionDatasetPayload $id $::GX::currentSession]
            set mesh [expr {[string tolower [dict get $payload format]] in {stl obj step stp vtp vtu vti}}]
            set artifact {}
            if {$mesh} {
                if {[catch {set artifact [meshDatasetPreviewArtifact $id $dir]} reason]} {dict set result description "Native3D standard frame unavailable: $reason. Canonical geometry remains available for explicit live consultation."}
            } else {set artifact [datasetPreviewMediaArtifact [dict get $payload path] [datasetField $id media_type] [datasetField $id format] [datasetField $id contract [datasetField $id kind]] $dir]}
            if {$artifact ne {}} {dict set result media_artifact $artifact;dict set result kind [expr {$mesh?"native3d":"media"}]}
            if {[catch {set axes [scientificDatasetAxes $id]}]} {set axes {numeric {} x {} y {}}}
            set numeric [dict get $axes numeric]
            if {[dict get $axes x] eq {} && [llength $numeric]>=2} {dict set axes x [lindex $numeric 0];dict set axes y [lindex $numeric 1]}
            foreach axis {x y z} {if {[dict exists $options $axis]} {dict set axes $axis [dict get $options $axis]}}
            dict set result axes $axes
            set dimensions {}
            if {[dict get $axes x] ne {} && [dict get $axes y] ne {}} {
                puts "Preparing canonical Preview: $id"
                set dimensions [scientificDatasetFilterDimensions $id]
                set selections [datasetPublicationV2DictDefault $options selections {}]
                if {$selections eq {}} {
                    set groups {};foreach dimension $dimensions {if {[dict get $dimension type] in {family curve calibration trace replicate}} {lappend groups [dict get $dimension variable_id]}}
                    set selections [dict create @grouping $groups @predicates {} @single_series 0]
                }
                set renderOptions $options
                native2DEnsure
                if {[llength [info commands ::gx::native2d::_preview_batch]]} {
                    # Resolve the existing grouping policy without a separate
                    # per-row discovery pass or one Transform scan per series.
                    set plan [_scientificDatasetFilterPlan $dimensions [dict remove $selections @hidden_filters] 1]
                    dict set plan dataset_id $id
                    dict set renderOptions batch_plan $plan
                    set requests {}
                } else {
                    set requests [scientificDatasetFilterRequests $dimensions [dict remove $selections @hidden_filters] 1]
                }
                set receipt [scientificDatasetPreviewFiltered $id [dict get $axes x] [dict get $axes y] [file join $dir standard.png] $requests $renderOptions]
                dict set result kind native2d
                foreach field {native_model row_count displayed_points} {dict set result $field [dict get $receipt $field]}
                if {[dict exists $receipt native_provider]} {dict set result native_provider [dict get $receipt native_provider]}
                dict set result selections $selections
                dict set result dimensions $dimensions
                if {[dict exists $options ordering]} {dict set result ordering [dict get $options ordering]}
                set nativeOverlay [datasetPublicationV2DictDefault $receipt native_overlay {}]
                if {$nativeOverlay ne {} && ([catch {dict get $nativeOverlay native_provider receipt source_receipt cache_key} overlayKey] || $overlayKey ne $key)} {set nativeOverlay {}}
                if {![catch {set digitizer [datasetDigitizerPreviewPrepare $id $selections $dimensions $dir [datasetPublicationV2DictDefault $options processed_image {}] $nativeOverlay]} message]} {dict set result digitizer $digitizer} else {dict set result description "Source raster/Quality unavailable: $message"}
            } else {
                if {!$mesh && ![dict exists $result media_artifact]} {
                    set arrayPath [file join $dir array-standard.png]
                    if {![catch {set arrayDescription [scientificDatasetArrayPreview $id $arrayPath nativeReceipt]}] && $arrayDescription ne {}} {
                        dict set result media_artifact [dict create path $arrayPath media_type image/png label {Bounded original array cells}]
                        dict set result kind array;dict set result description $arrayDescription
                        if {$nativeReceipt ne {}} {dict set result native_provider $nativeReceipt}
                    }
                }
                if {![dict exists $result media_artifact] && ![dict exists $result description]} {dict set result description "Dataset $id: [datasetField $id kind]. Use Open Dataset for supported media, geometry or explicit multidimensional selection."}
                if {![catch {set page [datasetPreviewPage $::GX::currentSession $id {count 12}]}]} {dict set result table_page $page}
            }
        }
        if {[datasetPreviewCacheSource $id] ne $source || [datasetPreviewCacheKey $id $options] ne $key} {error {Preview source or linked image changed during preparation}}
        set artifacts {}
        foreach path [glob -nocomplain -type f -directory $dir *] {
            if {[file tail $path] in {representation.tcldict SHA256}} continue
            if {[file type $path] eq "link"} {error {Derived Preview artifacts must not be symlinks}}
            dict set artifacts [file tail $path] [sha256File $path]
        }
        dict set result artifacts $artifacts
        return $result
    } finally {set worker $prior}
}
proc ::GX::datasetPreviewCacheRequest {id {options {}} {callback {}}} {
    variable ::GX::PreviewCache::tasks;variable ::GX::PreviewCache::misses
    set session $::GX::currentSession;set key [datasetPreviewCacheKey $id $options]
    set cached [datasetPreviewCacheRead $id $key]
    if {$cached ne {}} {
        if {[datasetField $id storage_provider {}] eq "remote" && [llength [info commands ::winfo]]} {
            dict unset ::GX::PreviewCache::remoteVerified $key
            set node [dict get [scientificExecutionNodes] [datasetField $id remote_node_id]]
            set request [dict create node $node session_id [datasetField $id remote_session_id] operation dataset.metadata arguments [list $id [datasetField $id remote_revision]]]
            scriptJobAsync [list [runtimeToolResolve python] -B [file join $::GX::scriptDir core python gxtxt_remote_transport.py]] $request [list ::GX::_datasetPreviewCacheRemoteVerified $id $key [interactiveDocumentSessionToken] $callback]
        } elseif {$callback ne {}} {after idle [list {*}$callback [dict create status ready key $key cache_hit 1]]}
        return $key
    }
    if {[dict exists $tasks $key]} {
        if {[dict exists $tasks $key cancelled]} {
            # A new Render is not a subscriber to the cancelled generation.
            # Drain that Job first, then request the same source/options again.
            if {![dict exists $tasks $key retry]} {
                dict set tasks $key retry [dict create id $id options $options session_token [interactiveDocumentSessionToken] callbacks {} legacy_joined 0]
            }
            if {!$::GX::PreviewCache::watchCalling} {dict set tasks $key retry legacy_joined 1}
            if {$callback ne {}} {set callbacks [dict get $tasks $key retry callbacks];lappend callbacks $callback;dict set tasks $key retry callbacks $callbacks}
        } else {
            if {!$::GX::PreviewCache::watchCalling} {dict set tasks $key legacy_joined 1}
            if {$callback ne {}} {set callbacks [dict get $tasks $key callbacks];lappend callbacks $callback;dict set tasks $key callbacks $callbacks}
        }
        return $key
    }
    incr misses
    dict unset ::GX::PreviewCache::outcomes $key
    dict set tasks $key [dict create session $session session_token [interactiveDocumentSessionToken] id $id options $options callbacks [expr {$callback eq {}?{}:[list $callback]}] job_id {} creator [expr {$::GX::PreviewCache::watchCalling ? {watch} : {legacy}}] legacy_joined [expr {!$::GX::PreviewCache::watchCalling}]]
    if {$::GX::PreviewCache::watchCalling && [auto_execok setsid] ne {} && [auto_execok tclsh] ne {}} {
        _datasetPreviewCacheManagedStart $key
    } else {
        dict set tasks $key execution_kind durable_job
        _scriptJobSubmitCore dataset-preview [dict create dataset_id $id options $options expected_key $key] [dict create session $session] [list ::GX::_datasetPreviewCacheSubmitted $key]
    }
    return $key
}
proc ::GX::_datasetPreviewCacheManagedStart {key} {
    variable ::GX::PreviewCache::tasks
    set entry [dict get $tasks $key]
    set generation [incr ::GX::PreviewCache::managedSerial]
    dict set tasks $key execution_kind managed_request
    dict set tasks $key managed_generation $generation
    dict set tasks $key request_id {}
    set payload [dict create schema gxtxt.preview_worker.v1 session [dict get $entry session] dataset_id [dict get $entry id] options [dict get $entry options] expected_key $key]
    set command [list [auto_execok setsid] [auto_execok tclsh] [file join $::GX::scriptDir core tcl dataset_preview_worker_v1.tcl] $::GX::scriptDir]
    if {[catch {
        if {[string bytelength $payload]>1048576} {error {Preview worker request exceeds1MiB}}
        set request [scriptJobAsync $command $payload [list ::GX::_datasetPreviewCacheManagedDone $key $generation] {timeout_ms 120000 max_bytes 65536 process_group 1 ui_lifetime 1 label {Dataset Preview preparation}}]
    } reason]} {
        after idle [list ::GX::_datasetPreviewCacheFinish $key [dict create status error key $key execution_kind managed_request job_id {} request_id {} message $reason]]
        return
    }
    dict set tasks $key request_id $request
    after idle [list ::GX::_datasetPreviewCacheManagedPreparing $key $generation]
}
proc ::GX::_datasetPreviewCacheManagedPreparing {key generation} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key managed_generation] || [dict get $tasks $key managed_generation]!=$generation || [dict exists $tasks $key cancelled]} return
    set entry [dict get $tasks $key]
    set response [dict create status preparing state RUNNING key $key execution_kind managed_request request_id [dict get $entry request_id] job_id {}]
    foreach callback [dict get $entry callbacks] {uplevel #0 [list {*}$callback $response]}
}
proc ::GX::_datasetPreviewCacheManagedDone {key generation response} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key managed_generation] || [dict get $tasks $key managed_generation]!=$generation} return
    set entry [dict get $tasks $key]
    if {[catch {dict get $response ok} ok] || ![string is boolean -strict $ok] || (!$ok && ![dict exists $response error])} {set response [dict create ok 0 error {Preview worker returned a malformed control envelope}]}
    set result [dict create status error key $key execution_kind managed_request request_id [dict get $entry request_id] job_id {} cache_hit 0]
    if {[dict exists $entry cancelled]} {dict set result message {Preview preparation cancelled}
    } elseif {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $entry session_token] || $::GX::currentSession ne [dict get $entry session]} {
        dict set result message {Preview preparation cancelled: Session lifetime changed}
    } elseif {![dict get $response ok]} {dict set result message [dict get $response error]
    } elseif {[catch {
        if {[dict get $response result key] ne $key || [dict get $response result dataset_id] ne [dict get $entry id]} {error {Preview worker returned a mismatched source/key}}
        _datasetPreviewCacheValidateCompletion $key $entry
    } reason]} {dict set result message $reason
    } else {dict set result status ready}
    if {[dict exists $response diagnostic_tail]} {dict set result diagnostic_tail [dict get $response diagnostic_tail]}
    _datasetPreviewCacheFinish $key $result
}
proc ::GX::_datasetPreviewCacheRemoteVerified {id key token callback response} {
    if {[catch {interactiveDocumentSessionToken} current] || $token ne $current} {
        # A terminal notification still owns subscription cleanup even when its
        # Session has gone. Do not grant verification to the old lifetime.
        set result [dict create status error key $key message {Preview verification cancelled: Session lifetime changed}]
    } elseif {[dict get $response ok]} {
        dict set ::GX::PreviewCache::remoteVerified $key $token
        set result [dict create status ready key $key cache_hit 1]
    } else {set result [dict create status error key $key message [dict get $response error]]}
    if {$callback ne {}} {uplevel #0 [list {*}$callback $result]}
}
proc ::GX::_datasetPreviewCacheSubmitted {key response} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key]} return
    if {![dict get $response ok]} {_datasetPreviewCacheFinish $key [dict create status error message [dict get $response error]];return}
    dict set tasks $key job_id [dict get $response result id]
    if {[dict exists $tasks $key cancelled]} {_datasetPreviewCacheCancelJob [dict get $response result id]}
    after 150 [list ::GX::_datasetPreviewCachePoll $key]
}
proc ::GX::_datasetPreviewCachePoll {key} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key]} return
    set entry [dict get $tasks $key]
    scriptJobAsync [scriptJobCommand describe [dict get $entry job_id]] {} [list ::GX::_datasetPreviewCachePolled $key]
}
proc ::GX::_datasetPreviewCachePolled {key response} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key]} return
    set entry [dict get $tasks $key]
    if {![dict get $response ok]} {_datasetPreviewCacheFinish $key [dict create status error message [dict get $response error]];return}
    set job [dict get $response result]
    if {[dict get $job state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {
        foreach callback [dict get $entry callbacks] {uplevel #0 [list {*}$callback [dict create status preparing state [dict get $job state] key $key job_id [dict get $entry job_id]]]}
        after 200 [list ::GX::_datasetPreviewCachePoll $key];return
    }
    set status [expr {[dict get $job state] eq "COMPLETED"?"ready":"error"}]
    if {$status eq {ready} && [catch {_datasetPreviewCacheValidateCompletion $key $entry} reason]} {
        set status error
        dict set job error $reason
    }
    if {[datasetPublicationV2DictDefault $job error {}] eq {}} {dict set job error [dict get $job state]}
    _datasetPreviewCacheFinish $key [dict create status $status key $key job_id [dict get $entry job_id] message [datasetPublicationV2DictDefault $job error [dict get $job state]] cache_hit 0]
}
# Job completion proves execution ended; current usable Preview state belongs to
# the cache owner. Both execution routes apply the same existing source/key/read
# guards before notifying ready. This does not grant native-provider admission.
proc ::GX::_datasetPreviewCacheValidateCompletion {key entry} {
    if {[dict exists $entry cancelled]} {error {Preview preparation cancelled}}
    if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $entry session_token] || $::GX::currentSession ne [dict get $entry session]} {error {Preview preparation cancelled: Session lifetime changed}}
    set id [dict get $entry id]
    if {[datasetPreviewCacheKey $id [dict get $entry options]] ne $key} {error {Preview source or preparation settings changed before completion}}
    set prepared [datasetPreviewCacheRead $id $key]
    if {$prepared eq {}} {error {Preview worker output is absent, damaged or stale}}
    return $prepared
}
proc ::GX::_datasetPreviewCacheFinish {key response} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key]} return
    set entry [dict get $tasks $key];dict unset tasks $key
    dict set response key $key
    if {![dict exists $response execution_kind]} {dict set response execution_kind [datasetPublicationV2DictDefault $entry execution_kind durable_job]}
    if {![dict exists $response job_id]} {dict set response job_id [dict get $entry job_id]}
    if {![dict exists $response request_id]} {dict set response request_id [datasetPublicationV2DictDefault $entry request_id {}]}
    if {[dict get $response status] eq "ready" && [dict get $entry session] eq $::GX::currentSession && [datasetField [dict get $entry id] storage_provider {}] eq "remote" && ![catch {interactiveDocumentSessionToken} token]} {dict set ::GX::PreviewCache::remoteVerified $key $token}
    if {[dict get $response status] eq "error"} {
        # This diagnostic is disposable. Failure to write it must not lose the
        # terminal outcome or prevent existing subscribers from draining.
        if {[catch {
            set dir [datasetPreviewCachePath [dict get $entry session] $key]
            file mkdir $dir
            resourceLifecycleWriteBytes [file join $dir PREPARE_ERROR.tcldict] [encoding convertto utf-8 [dict merge $response [dict create dataset_id [dict get $entry id] generated_at [clock format [clock seconds] -gmt 1 -format %Y-%m-%dT%H:%M:%SZ]]]]
        } reason]} {dict set response cache_record_error $reason}
    }
    dict set ::GX::PreviewCache::outcomes $key $response
    while {[dict size $::GX::PreviewCache::outcomes]>128} {dict unset ::GX::PreviewCache::outcomes [lindex [dict keys $::GX::PreviewCache::outcomes] 0]}
    foreach callback [dict get $entry callbacks] {uplevel #0 [list {*}$callback $response]}
    if {[dict exists $entry retry]} {
        set retry [dict get $entry retry]
        set callbacks [dict get $retry callbacks]
        set reason {}
        if {[dict get $entry session] ne $::GX::currentSession || [catch {interactiveDocumentSessionToken} token] || [dict get $retry session_token] ne $token} {
            set reason {Preview retry cancelled: Session lifetime changed}
        } elseif {[catch {datasetPreviewCacheKey [dict get $retry id] [dict get $retry options]} currentKey] || $currentKey ne $key} {
            set reason {Preview retry cancelled: scientific source or preparation settings changed; select Render again}
        }
        if {$reason ne {}} {
            # Complete subscription bookkeeping without starting work for a
            # closed/reopened Session. Its consumer retains its own token guard.
            foreach callback $callbacks {uplevel #0 [list {*}$callback [dict create status error key $key message $reason]]}
            return
        }
        if {![llength $callbacks]} {set callbacks [list {}]}
        set prior $::GX::PreviewCache::watchCalling
        set ::GX::PreviewCache::watchCalling [expr {![dict get $retry legacy_joined]}]
        try {
            foreach callback $callbacks {datasetPreviewCacheRequest [dict get $retry id] [dict get $retry options] $callback}
        } finally {set ::GX::PreviewCache::watchCalling $prior}
    }
}
proc ::GX::datasetPreviewCacheStatus {key} {
    if {[dict exists $::GX::PreviewCache::tasks $key]} {
        set task [dict get $::GX::PreviewCache::tasks $key]
        return [dict create status preparing key $key job_id [dict get $task job_id] execution_kind [datasetPublicationV2DictDefault $task execution_kind durable_job] request_id [datasetPublicationV2DictDefault $task request_id {}]]
    }
    if {[dict exists $::GX::PreviewCache::outcomes $key]} {return [dict get $::GX::PreviewCache::outcomes $key]}
    return [dict create status missing key $key]
}
proc ::GX::datasetPreviewCacheCancel {key} {
    variable ::GX::PreviewCache::tasks
    if {[dict exists $tasks $key]} {set job [dict get $tasks $key job_id];if {$job ne {}} {_datasetPreviewCacheCancelJob $job};if {[dict exists $tasks $key request_id] && [dict get $tasks $key request_id] ne {}} {scriptJobRequestCancel [dict get $tasks $key request_id]};dict set tasks $key cancelled 1;dict set tasks $key callbacks {};dict unset tasks $key retry}
}
proc ::GX::_datasetPreviewCacheCancelJob {job} {
    if {[llength [info commands winfo]]} {scriptJobAsync [scriptJobCommand cancel $job] {} {} {timeout_ms 5000 max_bytes 1048576 label {Dataset Preview cancellation}}} else {scriptJobCancel $job}
}
proc ::GX::datasetPreviewCacheSubscribe {id options callback} {
    set ticket preview-watch-[incr ::GX::PreviewCache::watchSerial]
    set prior $::GX::PreviewCache::watchCalling;set ::GX::PreviewCache::watchCalling 1
    try {set key [datasetPreviewCacheRequest $id $options [list ::GX::_datasetPreviewCacheSubscriptionDone $ticket]]} finally {set ::GX::PreviewCache::watchCalling $prior}
    dict set ::GX::PreviewCache::watches $ticket [dict create key $key callback $callback session [interactiveDocumentSessionToken]]
    return [dict create ticket $ticket key $key]
}
proc ::GX::_datasetPreviewCacheSubscriptionDone {ticket response} {
    if {![dict exists $::GX::PreviewCache::watches $ticket]} return
    set watch [dict get $::GX::PreviewCache::watches $ticket]
    if {[dict get $response status] ne {preparing}} {dict unset ::GX::PreviewCache::watches $ticket}
    if {[catch {interactiveDocumentSessionToken} current] || [dict get $watch session] ne $current} return
    if {[dict get $watch callback] ne {}} {uplevel #0 [list {*}[dict get $watch callback] $response]}
}
proc ::GX::datasetPreviewCacheUnsubscribe {ticket} {
    if {![dict exists $::GX::PreviewCache::watches $ticket]} {return 0}
    set key [dict get $::GX::PreviewCache::watches $ticket key];dict unset ::GX::PreviewCache::watches $ticket
    dict for {other watch} $::GX::PreviewCache::watches {if {[dict get $watch key] eq $key} {return 1}}
    if {[dict exists $::GX::PreviewCache::tasks $key]} {
        set task [dict get $::GX::PreviewCache::tasks $key]
        set legacy [datasetPublicationV2DictDefault $task legacy_joined 1]
        if {[dict exists $task retry] && [dict get $task retry legacy_joined]} {set legacy 1}
        if {[datasetPublicationV2DictDefault $task creator legacy] eq {watch} && !$legacy} {datasetPreviewCacheCancel $key}
    }
    return 1
}
proc ::GX::datasetPreviewCachePublished {session receipt} {
    variable ::GX::PreviewCache::worker
    if {$worker || [info exists ::env(GXTXT_PREVIEW_WORKER)] || $session ne $::GX::currentSession || [dict get $receipt change_kind] in {session namespace}} return
    datasetPreviewCacheInit
    if {![configurationGet preview.cache_enabled]} return
    foreach id [lsort -unique [concat [dict get $receipt added] [dict get $receipt changed]]] {
        if {[datasetField $id id {}] ne {}} {catch {datasetPreviewCacheRequest $id}}
    }
}
proc ::GX::_datasetPreviewCacheDiagnosticIdentity {record} {
    # Public engineering identity only: never forward arbitrary failure fields.
    set result [dict create execution_kind {} job_id {} request_id {}]
    if {![dict exists $record execution_kind]} {return $result}
    set kind [dict get $record execution_kind]
    if {$kind ni {durable_job managed_request}} {return $result}
    dict set result execution_kind $kind
    if {$kind eq {durable_job} && [dict exists $record job_id]} {
        set value [dict get $record job_id]
        if {[string length $value]<=192 && [regexp {^[A-Za-z0-9][A-Za-z0-9_.:-]*$} $value]} {dict set result job_id $value}
    } elseif {$kind eq {managed_request} && [dict exists $record request_id]} {
        set value [dict get $record request_id]
        if {[string length $value]<=192 && [regexp {^job-request-[0-9]+$} $value]} {dict set result request_id $value}
    }
    return $result
}
proc ::GX::datasetPreviewCacheInventory {session} {
    set result {};set root [datasetPreviewCacheRoot $session]
    foreach dir [glob -nocomplain -type d -directory $root *] {
        if {[file type $dir] eq "link" || ![regexp {^[a-f0-9]{64}$} [file tail $dir]]} continue
        set bytes 0;foreach file [glob -nocomplain -type f -directory $dir *] {incr bytes [file size $file]}
        set path [file join $dir representation.tcldict];set item [dict create key [file tail $dir] size_bytes $bytes status preparing dataset_id {} generated_at {} kind descriptive error {} source_revision {} execution_kind {} job_id {} request_id {}]
        if {[file isfile $path] && [file type $path] ne "link" && [file size $path]<=16777216} {
            # Inventory is also used by eviction and Clear all. A damaged
            # disposable record must remain removable, not abort management
            # of every other entry before the normal reader can reject it.
            if {[catch {
                set f [open $path r];fconfigure $f -encoding utf-8
                try {set record [read $f]} finally {close $f}
                dict size $record
                set id [dict get $record dataset_id]
                set generated [dict get $record generated_at]
                set kind [dict get $record kind]
                set revision [lindex [dict get $record source] 1]
            } message]} {
                dict set item status unavailable
                dict set item error "Invalid cached representation metadata: $message"
            } else {
                dict set item dataset_id $id;dict set item generated_at $generated
                dict set item kind $kind;dict set item source_revision $revision
                if {[catch {set prepared [datasetPreviewCacheRead $id [file tail $dir]]} message]} {
                    dict set item status unavailable;dict set item error $message
                } else {dict set item status [expr {$prepared eq {} || ![dict get $prepared current]?"stale":"ready"}]}
            }
        }
        set errorPath [file join $dir PREPARE_ERROR.tcldict]
        if {[file isfile $errorPath] && [file type $errorPath] ne "link" && [file size $errorPath]<65536} {
            if {[catch {
                set f [open $errorPath r];try {set failure [read $f]} finally {close $f}
                set error [dict get $failure message]
            } message]} {
                dict set item status unavailable
                dict set item error "Invalid cached preparation failure: $message"
            } else {
                dict set item status error;dict set item error $error
                foreach field {dataset_id generated_at} {
                    if {[dict exists $failure $field]} {dict set item $field [dict get $failure $field]}
                }
                set item [dict merge $item [_datasetPreviewCacheDiagnosticIdentity $failure]]
            }
        }
        if {[dict exists $::GX::PreviewCache::outcomes [file tail $dir]]} {
            set outcome [dict get $::GX::PreviewCache::outcomes [file tail $dir]]
            if {[dict get $outcome status] eq "error"} {
                dict set item status error;dict set item error [dict get $outcome message]
                set item [dict merge $item [_datasetPreviewCacheDiagnosticIdentity $outcome]]
            }
        }
        lappend result $item
    }
    return $result
}
proc ::GX::datasetPreviewCacheClear {session {keys {}}} {
    set root [datasetPreviewCacheRoot $session]
    if {$keys eq {}} {set keys [lmap item [datasetPreviewCacheInventory $session] {dict get $item key}]}
    foreach key $keys {datasetPreviewCacheCancel $key;set dir [datasetPreviewCachePath $session $key];if {[file exists $dir] && [file type $dir] ne "link"} {file delete -force $dir}}
}
proc ::GX::datasetPreviewCacheEvict {session keep} {
    datasetPreviewCacheInit;set total 0;set entries [datasetPreviewCacheInventory $session]
    foreach item $entries {incr total [dict get $item size_bytes]}
    set ordered {}
    foreach item $entries {
        set path [file join [datasetPreviewCachePath $session [dict get $item key]] representation.tcldict]
        set modified 0;if {[file isfile $path]} {set modified [file mtime $path]}
        lappend ordered [list $modified [dict get $item key] $item]
    }
    foreach entry [lsort -integer -index 0 $ordered] {
        set item [lindex $entry 2]
        if {$total<=[configurationGet preview.cache_mib]*1048576} break
        set key [dict get $item key]
        if {$key eq $keep} continue
        datasetPreviewCacheClear $session [list $key];incr total -[dict get $item size_bytes]
    }
}
