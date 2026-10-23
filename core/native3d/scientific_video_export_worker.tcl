#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Fixed trusted CORE entry. No user Script, shell, free-path frame list, solver
# or canonical Dataset writer is exposed by this adapter.
namespace eval ::GXScientificVideoWorker {variable emitted 0;variable operation {};variable request {};variable renderer {};variable rendererLog {};variable commitStarted 0}
proc ::GXScientificVideoWorker::readData {path maximum} {
    file lstat $path info
    if {$info(type) ne {file} || $info(nlink)!=1 || $info(size)>$maximum} {error {Invalid bounded scientific video data file}}
    set channel [open $path rb]
    try {set bytes [read $channel [expr {$maximum+1}]]} finally {close $channel}
    if {[string length $bytes]>$maximum} {error {Scientific video data file grew beyond its bound}}
    set value [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $value] ne $bytes} {error {Scientific video data is not canonical UTF-8}}
    dict size $value
    return $value
}
proc ::GXScientificVideoWorker::writeData {path value maximum} {
    set bytes [encoding convertto utf-8 $value]
    if {[string length $bytes]>$maximum} {error {Scientific video receipt exceeds its explicit bound}}
    set channel [open $path {WRONLY CREAT EXCL}]
    try {fconfigure $channel -translation binary -encoding binary;puts -nonewline $channel $bytes} finally {close $channel}
    file attributes $path -permissions 0600
}
proc ::GXScientificVideoWorker::send {kind fields} {
    variable emitted;variable operation
    if {[incr emitted]>8} {error {Scientific video control count exceeded}}
    set payload [dict merge $fields [dict create operation_id $operation kind $kind]]
    if {[string length [encoding convertto utf-8 $payload]]>32768} {error {Scientific video control exceeds32KiB}}
    puts stdout [::GX::ScientificVideo::encode $payload];flush stdout
}
proc ::GXScientificVideoWorker::receive {action} {
    variable operation
    if {[gets stdin line]<0} {error {Scientific video owner closed its control channel}}
    set value [::GX::ScientificVideo::decode $line]
    if {[lsort [dict keys $value]] ne {action operation_id} || [dict get $value operation_id] ne $operation || [dict get $value action] ne $action} {error {Invalid scientific video owner acknowledgement}}
}
proc ::GXScientificVideoWorker::fileIdentity {path {maximum 2147483648}} {
    file lstat $path before
    if {$before(type) ne {file} || $before(nlink)!=1 || $before(size)>$maximum} {error {Scientific video input must be a bounded unlinked regular file}}
    set hash [::GX::sha256File $path]
    file lstat $path after
    foreach key {type dev ino size mtime ctime nlink} {if {$before($key) ne $after($key)} {error {Scientific video source changed during verification}}}
    return [dict create sha256 $hash byte_count $after(size)]
}
proc ::GXScientificVideoWorker::dependenciesCurrent {dependencies} {
    foreach dependency $dependencies {
        set current [fileIdentity [dict get $dependency path] 536870912]
        foreach key {sha256 byte_count} {if {[dict get $current $key] ne [dict get $dependency $key]} {error {Captured scientific source changed during export}}}
    }
}
proc ::GXScientificVideoWorker::revisionsCurrent {revisions} {
    dict for {dataset expected} $revisions {
        if {[::GX::datasetRevisionToken $dataset] ne $expected} {error {Scientific Dataset registry or metadata changed during export}}
    }
}
proc ::GXScientificVideoWorker::requireCaptureProvenance {receipt expected} {
    # Refuse an older/mixed private capture owner rather than retaining a
    # superficially successful manifest without its verified source identities.
    foreach key {dataset_identities render_bindings dependency_identities} {
        if {![dict exists $receipt $key]} {error {Scientific video capture lacks complete retained provenance}}
    }
    set identities [dict get $receipt dataset_identities]
    set records [dict get $expected dataset_records]
    if {[lsort [dict keys $identities]] ne [lsort [dict keys $records]]} {error {Scientific video captured Dataset identity set differs}}
    dict for {dataset record} $records {
        set identity [dict get $identities $dataset]
        if {[dict get $identity dataset_id] ne $dataset || ![string equal -nocase [dict get $identity canonical_sha256] [dict get $record canonical_sha256]] ||
            ![string is entier -strict [dict get $identity byte_count]] || [dict get $identity byte_count]<0 || [dict get $identity byte_count]>268435456 ||
            [file pathtype [dict get $identity payload_reference]] ne {relative}} {error {Scientific video captured canonical Dataset identity differs}}
        set schema [dict get $identity schema]
        if {[dict get $schema api_version] ne [dict get $record variable_schema_api_version] ||
            [llength [dict get $schema variables]] != [dict get $record var_count]} {error {Scientific video captured Dataset schema is incomplete}}
    }
}
proc ::GXScientificVideoWorker::rendererStart {bridge root width height} {
    variable renderer;variable rendererLog
    set command [list {*}[auto_execok tclsh] [file join $::GX::scriptDir core native3d renderer_worker.tcl] $bridge]
    set budget [::GX::configurationGet viewers.native3d.worker_address_space_budget_mib]
    if {![string is integer -strict $budget] || $budget<128 || $budget>65536 || [auto_execok prlimit] eq {}} {error {Scientific video requires the existing bounded native process policy}}
    set command [concat [list [auto_execok prlimit] --as=[expr {$budget*1024*1024}] --fsize=[expr {$width*$height*5+65536}] --] $command]
    if {[::GX::configurationGet viewers.native3d.execution] eq {Software}} {
        set ::env(LIBGL_ALWAYS_SOFTWARE) 1;set ::env(LIBGL_ALWAYS_INDIRECT) 0
        set ::env(MESA_LOADER_DRIVER_OVERRIDE) llvmpipe;set ::env(GALLIUM_DRIVER) llvmpipe
    } else {
        unset -nocomplain ::env(LIBGL_ALWAYS_SOFTWARE) ::env(MESA_LOADER_DRIVER_OVERRIDE) ::env(GALLIUM_DRIVER)
        set ::env(LIBGL_ALWAYS_INDIRECT) 0
    }
    set rendererLog [file join $root native-renderer.log]
    set renderer [open [list | {*}$command 2>$rendererLog] r+]
    fconfigure $renderer -encoding utf-8 -translation lf -buffering line
    if {[gets $renderer ready]<0 || $ready ne {GX3DE_VIEWER_WORKER_READY}} {error {Native scientific renderer did not start its existing protocol}}
}
proc ::GXScientificVideoWorker::rendererCall {args} {
    variable renderer;variable rendererLog
    set request $args
    if {[string first \n $request]>=0 || [string first \r $request]>=0 || [string length [encoding convertto utf-8 $request]]>2097152} {error {Scientific scene cannot be represented by the existing bounded renderer protocol}}
    puts $renderer $request;flush $renderer
    if {[gets $renderer response]<0 || [string length [encoding convertto utf-8 $response]]>65536 || [llength $response]!=2 || [lindex $response 0] ne {ok}} {error {Native scientific renderer failed its frame request}}
    if {[file size $rendererLog]>65536} {error {Native scientific renderer diagnostic exceeded64KiB}}
    return [lindex $response 1]
}
proc ::GXScientificVideoWorker::rendererClose {} {
    variable renderer
    if {$renderer eq {}} return
    set pipe $renderer
    try {rendererCall close} finally {set renderer {};close $pipe}
}
proc ::GXScientificVideoWorker::reconcile {control} {
    variable request;variable operation
    if {[lsort [dict keys $control]] ne {action expected operation_id} || [dict get $control action] ne {reconcile} || [dict get $control operation_id] ne $operation} {error {Invalid scientific video reconciliation request}}
    set expected [dict get $control expected]
    set destination [dict get $request destination]
    if {[catch {file lstat $destination info} message context]} {
        if {[lrange [dict get $context -errorcode] 0 1] ne {POSIX ENOENT}} {error {Video destination cannot be inspected}}
        return [dict create operation_id $operation ok 0 status absent_reconciled destination $destination]
    }
    if {$info(type) ne {file}} {return [dict create operation_id $operation ok 0 status conflict_reconciled destination $destination reason {Destination is no longer an ordinary file}]}
    set identity [::GX::_filePublicationIdentity $destination]
    file lstat $destination after
    foreach key {type dev ino size mtime ctime} {if {$info($key) ne $after($key)} {error {Video destination changed during read-only reconciliation}}}
    if {[lindex $identity 2] eq [dict get $expected byte_count] && [lindex $identity 3] eq [dict get $expected sha256]} {
        return [dict create operation_id $operation ok 1 status published_reconciled destination $destination video [dict create byte_count [lindex $identity 2] sha256 [lindex $identity 3]] reconciliation_policy readonly_exact_destination]
    }
    return [dict create operation_id $operation ok 0 status conflict_reconciled destination $destination reason {Destination identity differs from the authorized staged video}]
}
proc ::GXScientificVideoWorker::runTool {argv log maximum} {
    if {[file exists $log] || ![catch {file lstat $log present}]} {error {Scientific video tool log already exists}}
    set rc [catch {exec -- {*}$argv >$log 2>@1} message context]
    file lstat $log info
    if {$info(type) ne {file} || $info(size)>$maximum} {error {Scientific video backend output exceeded its bound}}
    set channel [open $log rb]
    try {set result [read $channel [expr {$maximum+1}]]} finally {close $channel}
    if {$rc} {return -code error "Scientific video backend failed: [string range $result 0 4095]"}
    return $result
}
proc ::GXScientificVideoWorker::backend {name root} {
    set command [::GX::runtimeToolResolve $name]
    set executable [auto_execok $command]
    if {[llength $executable]!=1} {error "Configured $name is unavailable as one installed executable"}
    set path [file normalize [lindex $executable 0]]
    if {![file executable $path]} {error "Configured $name is not executable"}
    set identity [fileIdentity $path 134217728]
    set version [runTool [list $path -hide_banner -version] [file join $root $name-version.log] 65536]
    return [dict merge $identity [dict create path $path version [lindex [split $version \n] 0]]]
}
proc ::GXScientificVideoWorker::probe {backend video settings root} {
    set text [runTool [list [dict get $backend path] -v error -select_streams v:0 -count_frames -show_entries stream=codec_name,codec_type,width,height,avg_frame_rate,nb_read_frames,duration:format=format_name,duration -of default=noprint_wrappers=1 $video] [file join $root ffprobe-output.log] 65536]
    set fields {}
    foreach line [split $text \n] {
        if {$line eq {}} continue
        if {![regexp {^([a-z_]+)=(.*)$} $line -> key value] || $key ni {codec_name codec_type width height avg_frame_rate nb_read_frames duration format_name}} {error {Unexpected FFprobe output}}
        dict lappend fields $key $value
    }
    foreach {key expected} [list codec_name h264 codec_type video width [dict get $settings width] height [dict get $settings height] nb_read_frames [dict get $settings frame_count]] {
        if {![dict exists $fields $key] || [dict get $fields $key] ne [list $expected]} {error "Encoded video $key differs from the requested frame contract"}
    }
    if {![dict exists $fields format_name] || [string first mp4 [lindex [dict get $fields format_name] 0]]<0} {error {Encoded derivative is not an MP4 container}}
    if {![dict exists $fields avg_frame_rate] || [llength [dict get $fields avg_frame_rate]]!=1 || ![regexp {^([0-9]+)/([0-9]+)$} [lindex [dict get $fields avg_frame_rate] 0] -> numerator denominator] || $denominator==0} {error {Encoded video has no valid rational frame rate}}
    lassign [dict get $settings fps] expectedNumerator expectedDenominator
    if {$numerator*$expectedDenominator!=$expectedNumerator*$denominator} {error {Encoded video FPS differs from the requested sample-order playback}}
    if {![dict exists $fields duration]} {error {Encoded video has no duration}}
    set measured 0
    foreach duration [dict get $fields duration] {
        if {$duration eq {N/A}} continue
        if {![string is double -strict $duration] || [catch {expr {abs(double($duration)-[dict get $settings playback_duration_seconds])<=.002}} valid] || !$valid} {error {Encoded video duration differs from N/FPS}}
        incr measured
    }
    if {!$measured} {error {Encoded video duration was not measurable}}
    return $fields
}

proc ::GXScientificVideoWorker::export {} {
    variable request
    set root [dict get $request work_resource path]
    set diagnostic [dict get $request diagnostic_resource path]
    set settings [dict get $request options]
    set module [dict get $request module_id];set provider [dict get $request provider_id];set timeline [dict get $request timeline_id]
    set captureOptions [dict merge $settings [dict create expected_source [dict get $request expected_source]]]
    set capture [::GX::_native3DAnimationCaptureSource $module $provider $timeline $captureOptions $root]
    set dependencies [dict get $capture dependencies]
    set revisions [dict get $capture dataset_revisions]
    set scene [dict get $capture scene]
    # Fresh engines default to disabled disk caches. An empty scene cache_root
    # keeps those existing defaults; do not reserve an unbounded extra on-disk
    # scientific/mesh cache merely to render this one presentation derivative.
    dict set scene cache_root {}
    set sourceReceipt [dict get $capture source_receipt]
    requireCaptureProvenance $sourceReceipt [dict get $request expected_source]
    set ffmpeg [backend ffmpeg $root];set ffprobe [backend ffprobe $root]
    set encoder [runTool [list [dict get $ffmpeg path] -hide_banner -h encoder=libx264] [file join $root encoder-info.log] 65536]
    if {[string first {Encoder libx264} $encoder]<0 || ![regexp {(^|[\t\r\n ])yuv420p([\t\r\n ]|$)} $encoder]} {error {Installed FFmpeg does not advertise the required libx264/yuv420p encoder}}
    set bridge [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so]
    set bridgeIdentity [fileIdentity $bridge 134217728]
    set engine [file join $::GX::scriptDir core native3d lib libgx3de.so]
    set engineIdentity [fileIdentity $engine 134217728]
    set width [dict get $settings width];set height [dict get $settings height]
    # A separate native owner is initialized from the captured PRIVATE scene.
    # No Engine3D live worker, viewerSceneSet save or GUI timelineAction occurs.
    rendererStart $bridge $root $width $height
    rendererCall render $scene [file join $root initial.png] $width $height full
    set label "$module / $provider / $timeline"
    set frames {};set firstCamera {};set first [dict get $settings first_index];set last [dict get $settings last_index]
    lassign [dict get $settings fps] fpsNumerator fpsDenominator
    set times [dict get $sourceReceipt sample_times];set unit [dict get $sourceReceipt time_unit]
    for {set index $first} {$index<=$last} {incr index} {
        set ordinal [expr {$index-$first}]
        set png [file join $root [format frame-%06d.png $ordinal]]
        set frame [rendererCall timeline_capture $index $label $png]
        if {[dict get $frame current_frame]!=$index || [dict get $frame time_unit] ne $unit || [expr {double([dict get $frame current_time])!=double([lindex $times $index])}]} {error {Native frame/time identity differs from the original selected sample}}
        if {[dict get $frame width]!=$width || [dict get $frame height]!=$height || ![::GX::Engine3D::pngComplete $png]} {error {Native scientific video frame is incomplete or has incorrect dimensions}}
        set camera {}
        foreach key {camera_position camera_target camera_up projection} {dict set camera $key [dict get $frame $key]}
        if {$firstCamera eq {}} {set firstCamera $camera} elseif {$camera ne $firstCamera} {error {Initial scientific video export requires a fixed captured camera across samples}}
        set identity [fileIdentity $png [expr {$width*$height*5+65536}]]
        lappend frames [dict merge $frame $identity [dict create ordinal $ordinal source_index $index video_pts [list [expr {$ordinal*$fpsDenominator}] $fpsNumerator]]]
    }
    rendererClose
    dependenciesCurrent $dependencies
    revisionsCurrent $revisions
    set crf [dict get {draft 28 normal 23 high 18} [dict get $settings quality]]
    set video [file join $root video.mp4]
    set command [list [dict get $ffmpeg path] -nostdin -hide_banner -loglevel error -n -framerate $fpsNumerator/$fpsDenominator -start_number 0 -i [file join $root frame-%06d.png] -frames:v [dict get $settings frame_count] -an -c:v libx264 -pix_fmt yuv420p -preset medium -crf $crf -threads 1 -fps_mode passthrough -video_track_timescale $fpsNumerator -movflags +faststart -fs [dict get $settings max_video_bytes] $video]
    runTool $command [file join $root ffmpeg-output.log] 65536
    set probed [probe $ffprobe $video $settings $root]
    set videoIdentity [fileIdentity $video [dict get $settings max_video_bytes]]
    set manifest [dict create schema gxtxt.scientific_video_derivative.v1 operation_id [dict get $request operation_id] source $sourceReceipt settings $settings presentation_policy {disk_cache disabled_fresh_engine camera fixed_captioned_capture} frames $frames native_bridge $bridgeIdentity native_engine $engineIdentity ffmpeg $ffmpeg ffprobe $ffprobe probe $probed video $videoIdentity publication_policy create_only canonical_dataset 0]
    set manifestFile [file join $diagnostic manifest.tcldict]
    writeData $manifestFile $manifest [dict get $settings max_manifest_bytes]
    set manifestIdentity [fileIdentity $manifestFile [dict get $settings max_manifest_bytes]]
    set prepared [dict create video $videoIdentity manifest $manifestIdentity destination [dict get $request destination] diagnostic_resource_id [dict get $request diagnostic_resource id]]
    writeData [file join $diagnostic prepared.tcldict] $prepared 32768
    send prepared [dict merge $videoIdentity [dict create manifest_sha256 [dict get $manifestIdentity sha256]]]
    receive authorize
    dependenciesCurrent $dependencies
    revisionsCurrent $revisions
    # Recheck executable/library bytes before accepting the derivative receipt.
    foreach backend [list $ffmpeg $ffprobe] {set actual [fileIdentity [dict get $backend path] 134217728];foreach key {sha256 byte_count} {if {[dict get $actual $key] ne [dict get $backend $key]} {error {Installed scientific video backend changed during export}}}}
    if {[fileIdentity $bridge 134217728] ne $bridgeIdentity} {error {Native scientific renderer changed during export}}
    if {[fileIdentity $engine 134217728] ne $engineIdentity} {error {Native scientific engine changed during export}}
    ::GX::ScientificVideo::destination [dict get $request destination] [dict get $request session]
    set ::GXScientificVideoWorker::commitStarted 1
    set publication [::GX::filePublicationCopy $video [dict get $request destination] [dict get $videoIdentity sha256] create_only]
    foreach {publicationKey sourceKey} {sha256 sha256 byte_count byte_count} {
        if {[dict get $publication files document $publicationKey] ne [dict get $videoIdentity $sourceKey]} {error {Actual file publication receipt differs from the authorized staged video}}
    }
    set outcome [dict create ok 1 status published destination [dict get $request destination] publication $publication video $videoIdentity manifest_sha256 [dict get $manifestIdentity sha256] frame_count [dict get $settings frame_count] fps [dict get $settings fps] playback_duration_seconds [dict get $settings playback_duration_seconds] timing_policy original_sample_order]
    writeData [file join $diagnostic outcome.tcldict] $outcome 32768
    send terminal $outcome
    receive acknowledge
}

if {[llength $argv] ni {2 3} || ([llength $argv]==3 && [lindex $argv 2] ne {reconcile})} {puts stderr {Usage: scientific_video_export_worker.tcl FRAMEWORK OWNED_REQUEST ?reconcile?};exit 2}
set reconciliation [expr {[llength $argv]==3}]
set framework [file normalize [lindex $argv 0]]
set requestPath [file normalize [lindex $argv 1]]
set argv0 __not_main__
if {[catch {
    set ::GXScientificVideoWorker::request [::GXScientificVideoWorker::readData $requestPath 2097152]
    set ::GXScientificVideoWorker::operation [dict get $::GXScientificVideoWorker::request operation_id]
    source [file join $framework gxtxt_pipeline.tcl]
    # Central loader adoption belongs to MAIN. Explicit fixed owner source is
    # required for this independently reviewable worker, never a caller path.
    source [file join $framework core tcl scientific_video_export_api_v1.tcl]
    ::GX::defaults
    if {[::GX::configurationPath] ne [dict get $::GXScientificVideoWorker::request configuration_file]} {error {Scientific video configuration owner changed}}
    ::GX::configurationLoad
    if {$reconciliation} {
        if {[gets stdin line]<0} {error {Missing scientific video reconciliation request}}
        set control [::GX::ScientificVideo::decode $line]
        puts [dict create ok 1 result [::GXScientificVideoWorker::reconcile $control]]
        exit 0
    }
    ::GX::loadModuleCatalog
    set ::GX::currentSession [dict get $::GXScientificVideoWorker::request session]
    ::GX::loadManifest [file join $::GX::currentSession metadata manifest.ini]
    ::GX::loadDatasetRegistry $::GX::currentSession
    fconfigure stdin -encoding utf-8 -translation lf -buffering line
    fconfigure stdout -encoding utf-8 -translation lf -buffering line
    ::GXScientificVideoWorker::export
} message context]} {
    catch {::GXScientificVideoWorker::rendererClose}
    # If publication began, the retained prepared receipt allows exact read-only
    # reconciliation. An exception/kill must never certify 'nothing published'.
    set retained {}
    if {[info exists ::GXScientificVideoWorker::request] && $::GXScientificVideoWorker::request ne {}} {
        catch {set retained [file join [dict get $::GXScientificVideoWorker::request diagnostic_resource path] prepared.tcldict]}
    }
    if {$reconciliation} {puts [dict create ok 0 error [string range $message 0 4095]];exit 1}
    set status [expr {$::GXScientificVideoWorker::commitStarted?{finalization_outcome_unknown}:{failed}}]
    catch {
        ::GXScientificVideoWorker::send terminal [dict create ok 0 status $status error [string range $message 0 4095]]
        ::GXScientificVideoWorker::receive acknowledge
    }
    exit 1
}
