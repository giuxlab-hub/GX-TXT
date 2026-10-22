# Actual Preview callback/adoption and public Plot controller regression.
# Read CATALOG.md. No Tk, native library, canonical source or Session mutation.
if {[llength $argv]!=2 || [info exists ::env(DISPLAY)]} {
    puts stderr {Usage: env -u DISPLAY tclsh live_adoption.tcl FRAMEWORK NEW_OUTPUT};exit 2
}
lassign $argv framework output
set framework [file normalize $framework];set output [file normalize $output]
if {[file exists $output]} {error {NEW_OUTPUT already exists}}
file mkdir $output
namespace eval ::Harness {
    variable surfaces {};variable bindings {};variable models {};variable serial 0
    variable subscriptions {};variable subscriptionsSerial 0
    variable results {};variable result {};variable saved {};variable text {Accepted source view}
    variable mutations {};variable session current_document;variable cacheReads 0
    variable nativeViews {};variable nativeRetirements {}
}
namespace eval ::GX {variable currentSession inert_session;variable ui;array set ui {}}
namespace eval ::gx::native2d {}
proc ::GX::modulePublicApiActivate {args} {}
proc ::GX::native2DEnsure {} {}
proc ::GX::interactiveDocumentSessionToken {} {return $::Harness::session}
proc ::GX::datasetCatalogSubscribe {callback} {
    set token subscription[incr ::Harness::subscriptionsSerial]
    dict set ::Harness::subscriptions $token $callback;return $token
}
proc ::GX::datasetCatalogUnsubscribe {token} {dict unset ::Harness::subscriptions $token}
proc ::GX::curveSourceValidateSnapshot {args} {return {valid 0 status SOURCE_CHANGED}}
proc ::gx::native2d::plot_v4 {operation args} {
    switch -- $operation {
        create {set token native[incr ::Harness::serial];dict set ::Harness::models $token [lindex $args 0];return $token}
        configure {lassign $args token model;if {![dict exists $::Harness::models $token]} {error {Missing native token}};dict set ::Harness::models $token $model}
        destroy {dict unset ::Harness::models [lindex $args 0]}
        fit - view {lappend ::Harness::nativeViews [list $operation {*}$args]}
        default {error "Unexpected native operation $operation"}
    }
}
proc ::gx::native2d::surface {path} {
    if {[dict exists $::Harness::surfaces $path]} {error {Surface already exists}}
    dict set ::Harness::surfaces $path 1;return $path
}
proc bind {path event args} {
    if {[llength $args]} {dict set ::Harness::bindings $path $event [lindex $args 0];return}
    if {[dict exists $::Harness::bindings $path $event]} {return [dict get $::Harness::bindings $path $event]}
    return {}
}
proc winfo {operation path} {
    switch -- $operation {
        exists {expr {[dict exists $::Harness::surfaces $path] || $path eq {.top.nb.preview.live}}}
        children {set children {};foreach candidate [dict keys $::Harness::surfaces] {if {[string range $candidate 0 [string last . $candidate]-1] eq $path} {lappend children $candidate}};return $children}
        default {error "Unexpected winfo $operation"}
    }
}
proc destroy {path} {
    lappend ::Harness::mutations [list destroy $path]
    if {![dict exists $::Harness::surfaces $path]} return
    if {[dict exists $::Harness::bindings $path <Destroy>]} {uplevel #0 [dict get $::Harness::bindings $path <Destroy>]}
    dict unset ::Harness::surfaces $path
    if {[dict exists $::Harness::bindings $path]} {dict unset ::Harness::bindings $path}
}
proc pack {args} {}
proc raise {args} {}
proc .top.nb.preview.txt {operation args} {
    switch -- $operation {
        configure {}
        delete {set ::Harness::text {};lappend ::Harness::mutations text_delete}
        insert {append ::Harness::text [lindex $args 1]}
        default {error "Unexpected text $operation"}
    }
}
proc .top.nb.preview.live.panes {args} {}
foreach button {fit zoomIn zoomOut} {proc .top.nb.preview.live.actions.$button {args} {}}
proc ::GX::datasetPublicationV2DictDefault {value key default} {if {[dict exists $value $key]} {return [dict get $value $key]};return $default}
proc ::GX::datasetPreviewCacheRead {args} {incr ::Harness::cacheReads;return $::Harness::result}
proc ::GX::datasetPreviewConfigurationRead {args} {return {}}
proc ::GX::_datasetFrameworkMetadataUpdate {session id update} {lappend ::Harness::saved [list $session $id $update]}
proc ::GX::datasetDigitizerPreviewHasRecord {args} {return 0}
proc ::GX::datasetDigitizerPreviewAttachNative {args} {return 0}
proc ::GX::datasetDigitizerPreviewClear {} {lappend ::Harness::mutations digitizer_clear}
proc ::GX::previewDescriptorClearWidgetArtifact {args} {lappend ::Harness::mutations artifact_clear}
proc ::GX::datasetMetadataRead {args} {return {}}
proc ::GX::datasetResolvePath {args} {return /inert/source}
proc ::GX::datasetViewerStamp {args} {return inert_stamp}
proc check {name condition} {
    set ok [uplevel 1 [list expr $condition]]
    lappend ::Harness::results [dict create check $name pass $ok]
    puts [list CHECK $name [expr {$ok?{PASS}:{FAIL}}]]
}
source [file join $framework plugins modules plot.dataset api plot_dataset_api_v4.tcl]
source [file join $framework app gui dataset_preview_live.tcl]
# Mock the visible status/quality projection, retaining the actual adoption owner.
proc ::GX::datasetPreviewLiveSetStatus {text} {dict set ::GX::PreviewLive::active status_2d $text}
proc ::GX::datasetPreviewLiveQuality {args} {}
proc ::GX::datasetPreviewActionsState {} {}
proc ::GX::native3DPreviewRelease {args} {lappend ::Harness::nativeRetirements $args}

set path .top.nb.preview.live.panes.plot.retainedXY
set context {prepared_model 1 retain_presentation 1}
set valid [dict create panels [list [dict create id main series {}]]] 
set rejected [dict create panels [list [dict create id main series [list [dict create source_descriptor {source_identities {{dataset_id canonical_curve}}}]]]]]
set response {status ready key new_key cache_hit 0}
set ::GX::PreviewLive::active {id numeric_curve token current_document key old_key rendered_key old_key rendered_options {} source old_source status_2d {Accepted source view}}
set ::GX::PreviewLive::epoch 7
::GX::PlotDatasetAPIv4::widgetCreate $path $valid $context
set record [dict get $::GX::PlotDatasetAPIv4::widgets $path]
set oldToken [dict get $record token];set oldModel [dict get $::Harness::models $oldToken]
set preflight [::GX::PlotDatasetAPIv4::widgetValidateSources $valid $context]
check preflight_accepts_descriptor_free_model {[dict get $preflight valid] && [dict get $preflight source_count]==0}
set preflightCode [catch {::GX::PlotDatasetAPIv4::widgetValidateSources $rejected $context} preflightMessage]
check preflight_rejects_changed_source {$preflightCode && [string match {*SOURCE_CHANGED*} $preflightMessage]}
check preflight_preserves_controller_and_buffer {[dict get $::GX::PlotDatasetAPIv4::widgets $path] eq $record && [dict get $::Harness::models $oldToken] eq $oldModel}
check preflight_allocates_no_native_resources {$::Harness::serial==1 && [dict size $::Harness::models]==1 && [dict size $::Harness::surfaces]==1 && [dict size $::Harness::subscriptions]==1}
set ::Harness::result [dict create current 1 native_model $rejected key new_key source new_source options {} row_count 3 displayed_points 3]
set code [catch {::GX::_datasetPreviewLiveReady numeric_curve current_document 7 1 $response} message options]
set evidence [dict create late_source_rejection [dict create catch $code message $message options $options surfaces $::Harness::surfaces models $::Harness::models active $::GX::PreviewLive::active mutations $::Harness::mutations text $::Harness::text]]
check ready_reports_rejection_without_throwing {!$code}
check previous_surface_survives {[winfo exists $path]}
check previous_controller_survives {[dict exists $::GX::PlotDatasetAPIv4::widgets $path] && [dict get $::GX::PlotDatasetAPIv4::widgets $path] eq $record}
check previous_native_buffer_survives {[dict exists $::Harness::models $oldToken] && [dict get $::Harness::models $oldToken] eq $oldModel}
check previous_source_text_survives {$::Harness::text eq {Accepted source view}}
check no_destructive_ui_mutations {![llength $::Harness::mutations]}
check previous_render_identity_survives {[dict get $::GX::PreviewLive::active rendered_key] eq {old_key}}
check rejected_render_not_persisted {![llength $::Harness::saved]}
check rejection_status_is_explicit {[string match {*SOURCE_CHANGED*} [dict get $::GX::PreviewLive::active status_2d]]}
check rejected_admission_keeps_previous_3D_owner {![llength $::Harness::nativeRetirements]}

# Continue after a baseline failure so before/after reports retain the retry case.
if {![winfo exists $path]} {::GX::PlotDatasetAPIv4::widgetCreate $path $valid $context}
set retryToken [dict get $::GX::PlotDatasetAPIv4::widgets $path token]
dict set ::Harness::result native_model $valid
set code [catch {::GX::_datasetPreviewLiveReady numeric_curve current_document 7 1 $response} message options]
dict set evidence successful_retry [dict create catch $code message $message options $options]
check explicit_retry_succeeds {!$code}
check retry_reuses_controller {[dict get $::GX::PlotDatasetAPIv4::widgets $path token] eq $retryToken}
check retry_adopts_new_identity {[dict get $::GX::PreviewLive::active rendered_key] eq {new_key}}
check successful_retry_persisted_once {[llength $::Harness::saved]==1}
check admitted_replacement_retires_3D_owner_once {[llength $::Harness::nativeRetirements]==1 && [lindex $::Harness::nativeRetirements 0 0] eq {.top.nb.preview.live.panes.plot}}
set reads $::Harness::cacheReads;set active $::GX::PreviewLive::active
::GX::_datasetPreviewLiveReady numeric_curve current_document 6 1 $response
check cancelled_generation_never_reads_or_adopts {$::Harness::cacheReads==$reads && $::GX::PreviewLive::active eq $active}
set ::Harness::session next_document
::GX::_datasetPreviewLiveReady numeric_curve current_document 7 1 $response
check previous_session_never_reads_or_adopts {$::Harness::cacheReads==$reads && $::GX::PreviewLive::active eq $active}
destroy $path
check normal_destroy_releases_all {[dict size $::Harness::models]==0 && [dict size $::GX::PlotDatasetAPIv4::widgets]==0 && [dict size $::Harness::subscriptions]==0}

# Parent follow-up: the public guard must stay strict, while the actual ordinary
# Preview button notification must not turn that rejection into a Tk exception.
set ::Harness::session current_document
set ::Harness::sourceChanged 0
proc ::GX::curveSourceValidateSnapshot {args} {dict create valid [expr {!$::Harness::sourceChanged}] status [expr {$::Harness::sourceChanged?{SOURCE_CHANGED}:{CURRENT}}]}
proc ::GX::datasetViewerStamp {args} {return [list inert_stamp $::Harness::sourceChanged]}
proc ::GX::datasetRevisionToken {args} {return [list revision $::Harness::sourceChanged]}
proc ::GX::datasetViewerScientificIdentity {args} {return [list scientific_source $::Harness::sourceChanged]}
proc ::GX::datasetRegistryPath {args} {return /inert/registry}
proc ::GX::_datasetMetadataPath {args} {return {metadata /inert/metadata}}
::GX::PlotDatasetAPIv4::widgetCreate $path $rejected $context
set code [catch {::GX::datasetPreviewLiveView fit} message options]
check current_fit_reaches_native_owner {!$code && [llength $::Harness::nativeViews]==1}
set sourceRecord [dict get $::GX::PlotDatasetAPIv4::widgets $path]
set guardedToken [dict get $sourceRecord token]
set guardedModel [dict get $::Harness::models $guardedToken]
set ::Harness::sourceChanged 1
dict for {subscription callback} $::Harness::subscriptions {
    uplevel #0 [list {*}$callback {dataset_ids canonical_curve change_kind dataset}]
}
set code [catch {::GX::PlotDatasetAPIv4::widgetView $path fit} message options]
check public_view_still_rejects_changed_source {$code && [string match {*SOURCE_CHANGED*} $message]}
set views [llength $::Harness::nativeViews]
foreach operation {fit zoom_in zoom_out fit} {
    set code [catch {::GX::datasetPreviewLiveView $operation} message options]
    lappend toolbarEvidence [dict create operation $operation catch $code message $message options $options status [dict get $::GX::PreviewLive::active status_2d]]
    check toolbar_${operation}_[llength $toolbarEvidence]_notifies_without_throwing {!$code && [string match {*SOURCE_CHANGED*} [dict get $::GX::PreviewLive::active status_2d]]}
}
check rejected_toolbar_never_changes_buffers {[llength $::Harness::nativeViews]==$views && [dict get $::Harness::models $guardedToken] eq $guardedModel}
dict set evidence toolbar_source_rejection $toolbarEvidence
set ::Harness::sourceChanged 0
::GX::PlotDatasetAPIv4::widgetConfigure $path $rejected $context
set code [catch {::GX::datasetPreviewLiveView fit} message options]
check explicit_reconfigure_restores_normal_fit {!$code && [llength $::Harness::nativeViews]==$views+1}
destroy $path
check toolbar_normal_cleanup_complete {[dict size $::Harness::models]==0 && [dict size $::GX::PlotDatasetAPIv4::widgets]==0 && [dict size $::Harness::subscriptions]==0}
set failures 0;foreach row $::Harness::results {if {![dict get $row pass]} {incr failures}}
set fd [open [file join $output report.tcldict] {WRONLY CREAT EXCL}]
puts $fd [list [dict create scope {inert actual adoption/public-controller contract only} checks $::Harness::results failures $failures evidence $evidence]];close $fd
foreach relative {app/gui/dataset_preview_live.tcl plugins/modules/plot.dataset/api/plot_dataset_api_v4.tcl validation/main2_preview109/live_adoption.tcl} {
    set dest [file join $output sources $relative];file mkdir [file dirname $dest];file copy [file join $framework $relative] $dest
}
puts [list RESULT checks [llength $::Harness::results] failures $failures]
exit [expr {$failures?1:0}]
