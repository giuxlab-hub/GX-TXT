# SPDX-License-Identifier: GPL-3.0-or-later
# Disposable representations owned by Dataset Preview. Dataset Authority,
# Configuration, Resource Management and Script Jobs keep their existing roles.
namespace eval ::GX::PreviewCache {variable tasks {};variable remoteVerified {};variable outcomes {};variable renderer {};variable worker 0;variable hits 0;variable misses 0}
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
proc ::GX::datasetPreviewCacheKey {id {options {}}} {
    variable ::GX::PreviewCache::renderer
    if {$renderer eq {}} {
        set renderer gxtxt.preview.retained.v1
        foreach relative {
            core/tcl/dataset_preview_cache.tcl core/tcl/scientific_dataset_filters_v1.tcl
            core/tcl/dataset_digitizer_preview_v1.tcl core/tcl/dataset_preview_api_v1.tcl core/tcl/scientific_dataset_preview_v1.tcl
            core/tcl/scientific_dataset_filter_configuration_v1.tcl core/tcl/dataset_viewer_api_v1.tcl
            core/tcl/curve_source_api_v1.tcl core/tcl/dataset_coordinate_context_v1.tcl
            core/tcl/mesh_dataset_viewer_v1.tcl core/native2d/bin/gx2dtcl.so
            core/native3d/renderer_worker.tcl core/native3d/bin/libgx3de_viewer_tcl.so
            plugins/modules/plot.dataset/api/plot_dataset_api_v4.tcl
        } {lappend renderer $relative [sha256File [file join $::GX::scriptDir $relative]]}
    }
    set settings {}
    foreach name [dict keys [previewSettingsDefaults]] {if {![string match *open* $name]} {lappend settings $name [previewSetting $name]}}
    if {[string tolower [datasetField $id format]] in {stl obj step stp vtp vtu vti}} {lappend settings native3d [native3dGraphicsPolicy]}
    return [datasetStorageSha256Text $::GX::currentSession [list [sessionOriginRead $::GX::currentSession] [datasetPreviewCacheSource $id] $options $renderer $settings]]
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
    if {[catch {dict get $result dataset_id} dataset] || $dataset ne $id || [dict get $result key] ne $key} {return {}}
    if {[dict exists $result artifacts]} {
        dict for {name expected} [dict get $result artifacts] {
            if {[file tail $name] ne $name} {return {}}
            set artifact [file join $dir $name]
            if {![file isfile $artifact] || [file type $artifact] eq "link" || [sha256File $artifact] ne $expected} {return {}}
        }
    }
    set current [expr {[dict get $result source] eq [datasetPreviewCacheSource $id]}]
    if {!$current && !$allowStale} {return {}}
    if {[datasetField $id storage_provider {}] eq "remote"} {
        if {![llength [info commands ::winfo]]} {datasetRemoteVerify $id} elseif {![dict exists $::GX::PreviewCache::remoteVerified $key] || [dict get $::GX::PreviewCache::remoteVerified $key] ne [interactiveDocumentSessionToken]} {
            set current 0;dict set result remote_unverified 1
        }
    }
    dict set result current $current
    incr hits
    return $result
}
proc ::GX::datasetPreviewCacheGenerate {id options {expectedKey {}}} {
    variable ::GX::PreviewCache::worker
    set prior $worker;set worker 1
    try {
        loadDatasetRegistry $::GX::currentSession
        set key [datasetPreviewCacheKey $id $options]
        if {$expectedKey ne {} && $key ne $expectedKey} {error {Preview source changed before preparation}}
        set cached [datasetPreviewCacheRead $id $key]
        if {$cached ne {}} {return $cached}
        set source [datasetPreviewCacheSource $id]
        set dir [datasetPreviewCachePath $::GX::currentSession $key];file mkdir $dir
        file delete -force [file join $dir PREPARE_ERROR.tcldict]
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
                set requests [scientificDatasetFilterRequests $dimensions [dict remove $selections @hidden_filters] 1]
                set receipt [scientificDatasetPreviewFiltered $id [dict get $axes x] [dict get $axes y] [file join $dir standard.png] $requests [dict merge {ordering {}} $options]]
                dict set result kind native2d
                foreach field {native_model row_count displayed_points} {dict set result $field [dict get $receipt $field]}
                dict set result selections $selections
                dict set result dimensions $dimensions
                if {[dict exists $options ordering]} {dict set result ordering [dict get $options ordering]}
                if {![catch {set digitizer [datasetDigitizerPreviewPrepare $id $selections $dimensions $dir [datasetPublicationV2DictDefault $options processed_image {}]]} message]} {dict set result digitizer $digitizer} else {dict set result description "Source raster/Quality unavailable: $message"}
            } else {
                if {!$mesh && ![dict exists $result media_artifact]} {
                    set arrayPath [file join $dir array-standard.png]
                    if {![catch {set arrayDescription [scientificDatasetArrayPreview $id $arrayPath]}] && $arrayDescription ne {}} {
                        dict set result media_artifact [dict create path $arrayPath media_type image/png label {Bounded original array cells}]
                        dict set result kind array;dict set result description $arrayDescription
                    }
                }
                if {![dict exists $result media_artifact] && ![dict exists $result description]} {dict set result description "Dataset $id: [datasetField $id kind]. Use Open Dataset for supported media, geometry or explicit multidimensional selection."}
                if {![catch {set page [datasetPreviewPage $::GX::currentSession $id {count 12}]}]} {dict set result table_page $page}
            }
        }
        if {[datasetPreviewCacheSource $id] ne $source} {error {Preview source changed during preparation}}
        set artifacts {}
        foreach path [glob -nocomplain -type f -directory $dir *] {
            if {[file tail $path] in {representation.tcldict SHA256}} continue
            if {[file type $path] eq "link"} {error {Derived Preview artifacts must not be symlinks}}
            dict set artifacts [file tail $path] [sha256File $path]
        }
        dict set result artifacts $artifacts
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
    if {[dict exists $tasks $key]} {if {$callback ne {}} {set callbacks [dict get $tasks $key callbacks];lappend callbacks $callback;dict set tasks $key callbacks $callbacks};return $key}
    incr misses
    dict unset ::GX::PreviewCache::outcomes $key
    set script {import gxtxt
p=gxtxt.gxtxt_context()['parameters']
gxtxt.gxtxt_api_call('DATASET_PREVIEW_API_v1','cache_generate',[p['dataset_id'],p['options'],p['expected_key']])
}
    set metadata [dict create language Python version 1.0.0 parameters [dict create dataset_id {type string required 1} options {type string default {}} expected_key {type string required 1}]]
    set name gx-core-dataset-preview
    if {[catch {set registered [scriptRegistryRead session $name]}]} {scriptRegistrySave session $name {CORE Dataset Preview preparation} $script $metadata} else {
        set f [open [dict get $registered source_path] r];try {set existing [read $f]} finally {close $f}
        if {$existing ne $script} {error {Reserved Preview script differs; inspect it before preparing previews}}
    }
    dict set tasks $key [dict create session $session id $id options $options callbacks [expr {$callback eq {}?{}:[list $callback]}] job_id {}]
    scriptJobSubmit session:$name [dict create dataset_id $id options $options expected_key $key] [dict create session $session] [list ::GX::_datasetPreviewCacheSubmitted $key]
    return $key
}
proc ::GX::_datasetPreviewCacheRemoteVerified {id key token callback response} {
    if {$token ne [interactiveDocumentSessionToken]} return
    if {[dict get $response ok]} {
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
    if {[dict exists $tasks $key cancelled]} {scriptJobCancel [dict get $response result id]}
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
    if {[datasetPublicationV2DictDefault $job error {}] eq {}} {dict set job error [dict get $job state]}
    _datasetPreviewCacheFinish $key [dict create status $status key $key job_id [dict get $entry job_id] message [datasetPublicationV2DictDefault $job error [dict get $job state]] cache_hit 0]
}
proc ::GX::_datasetPreviewCacheFinish {key response} {
    variable ::GX::PreviewCache::tasks
    if {![dict exists $tasks $key]} return
    set entry [dict get $tasks $key];dict unset tasks $key
    if {[dict get $response status] eq "ready" && [dict get $entry session] eq $::GX::currentSession && [datasetField [dict get $entry id] storage_provider {}] eq "remote"} {dict set ::GX::PreviewCache::remoteVerified $key [interactiveDocumentSessionToken]}
    if {[dict get $response status] eq "error"} {
        set dir [datasetPreviewCachePath [dict get $entry session] $key]
        file mkdir $dir
        resourceLifecycleWriteBytes [file join $dir PREPARE_ERROR.tcldict] [encoding convertto utf-8 [dict merge $response [dict create dataset_id [dict get $entry id] generated_at [clock format [clock seconds] -gmt 1 -format %Y-%m-%dT%H:%M:%SZ]]]]
    }
    dict set ::GX::PreviewCache::outcomes $key $response
    while {[dict size $::GX::PreviewCache::outcomes]>128} {dict unset ::GX::PreviewCache::outcomes [lindex [dict keys $::GX::PreviewCache::outcomes] 0]}
    foreach callback [dict get $entry callbacks] {uplevel #0 [list {*}$callback $response]}
}
proc ::GX::datasetPreviewCacheStatus {key} {
    if {[dict exists $::GX::PreviewCache::tasks $key]} {return [dict create status preparing key $key job_id [dict get $::GX::PreviewCache::tasks $key job_id]]}
    if {[dict exists $::GX::PreviewCache::outcomes $key]} {return [dict get $::GX::PreviewCache::outcomes $key]}
    return [dict create status missing key $key]
}
proc ::GX::datasetPreviewCacheCancel {key} {
    variable ::GX::PreviewCache::tasks
    if {[dict exists $tasks $key]} {set job [dict get $tasks $key job_id];if {$job ne {}} {scriptJobCancel $job};dict set tasks $key cancelled 1;dict set tasks $key callbacks {}}
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
proc ::GX::datasetPreviewCacheInventory {session} {
    set result {};set root [datasetPreviewCacheRoot $session]
    foreach dir [glob -nocomplain -type d -directory $root *] {
        if {[file type $dir] eq "link" || ![regexp {^[a-f0-9]{64}$} [file tail $dir]]} continue
        set bytes 0;foreach file [glob -nocomplain -type f -directory $dir *] {incr bytes [file size $file]}
        set path [file join $dir representation.tcldict];set item [dict create key [file tail $dir] size_bytes $bytes status preparing dataset_id {} generated_at {} kind descriptive error {} source_revision {}]
        if {[file isfile $path] && [file size $path]<=16777216} {set f [open $path r];try {set record [read $f]} finally {close $f};if {![catch {dict get $record dataset_id} id]} {dict set item dataset_id $id;dict set item generated_at [dict get $record generated_at];dict set item kind [dict get $record kind];dict set item source_revision [lindex [dict get $record source] 1];if {[catch {set prepared [datasetPreviewCacheRead $id [file tail $dir]]} message]} {dict set item status unavailable;dict set item error $message} else {dict set item status [expr {$prepared eq {} || ![dict get $prepared current]?"stale":"ready"}]}}}
        set errorPath [file join $dir PREPARE_ERROR.tcldict]
        if {[file isfile $errorPath] && [file type $errorPath] ne "link" && [file size $errorPath]<65536} {
            set f [open $errorPath r];try {set failure [read $f]} finally {close $f}
            if {![catch {dict get $failure message} error]} {dict set item status error;dict set item error $error;dict set item dataset_id [dict get $failure dataset_id];dict set item generated_at [dict get $failure generated_at]}
        }
        if {[dict exists $::GX::PreviewCache::outcomes [file tail $dir]]} {
            set outcome [dict get $::GX::PreviewCache::outcomes [file tail $dir]]
            if {[dict get $outcome status] eq "error"} {dict set item status error;dict set item error [dict get $outcome message]}
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
    foreach item [lsort -index 0 $entries] {
        if {$total<=[configurationGet preview.cache_mib]*1048576} break
        set key [dict get $item key]
        if {$key eq $keep} continue
        datasetPreviewCacheClear $session [list $key];incr total -[dict get $item size_bytes]
    }
}
