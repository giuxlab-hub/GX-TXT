# SPDX-License-Identifier: GPL-3.0-or-later
# Optional PREVIEW_COMPONENT_GUI_API_v1 host adapter. UI Field, shared icons,
# ViewportHost and Plot retain widget, asset and scientific presentation authority.
namespace eval ::GX::PreviewGui {variable mounts {};variable serial 0;variable values;variable pageTasks {};variable pageSubscriptions {};variable pageDraining {};variable cacheSerial 0}
proc ::GX::datasetPreviewGuiApiInfo {} {
    return [dict create api_id PREVIEW_COMPONENT_GUI_API_v1 api_version 1 host_only 1 native_client_operations {scientific_preview_command scientific_frame_bind} opt_in preview_provider.gui_api_version=1 tab_kind gui callbacks {guiMount guiDispose} operations {datasetPreviewGuiCachedCurvesRequest datasetPreviewGuiCachedPageRequest datasetPreviewGuiCacheCancel datasetPreviewGuiContext datasetPreviewGuiControlCreate datasetPreviewGuiControlGet datasetPreviewGuiControlSet datasetPreviewGuiControlConfigure datasetPreviewGuiControlState datasetPreviewGuiPanelCreate datasetPreviewGuiPanelShow datasetPreviewGuiView datasetPreviewGuiSelectDataset datasetPreviewGuiSourceRequest datasetPreviewGuiChoicesSet datasetPreviewGuiPlotCreate datasetPreviewGuiPlotBind datasetPreviewGuiPlotView datasetPreviewGuiTableSet} numeric_context {current_canonical_Dataset rank1 sample_rows_max16 sample_variables_max16 sample_only1 json_bytes_max65536} owners {UI_FIELD_API_v1 VIEWER_GUI_HOST_API_v1 NATIVE2D_VIEWPORT_HOST_v1 PLOT_DATASET_API_v4} scientific_context {profile scientific_view_v1 native_operations {scientific_preview_command scientific_frame_bind} commands {discover page metadata source} admission actual_installed_compiled_preview roles scientific_preview_components canonical_page_cells_max 512 values_transport exact_text request_reply_bytes_max 49152 lifetime current_preview_module_session_dataset ephemeral_receipts 1 publication 0 arbitrary_paths 0 frame_integration canonical_explicit_plane} cached_context {profile cache_bridge_v1 canonical_page_bytes_max 4194304 native_model_bytes_max 16777216 page_tasks_max 8 subscribers_per_task_max 32 page_subscriptions_max 256 subscriptions_per_host_max 8 paths_exposed 0 data_preparation asynchronous widget_creation existing_synchronous_owner}]
}
proc ::GX::_datasetPreviewGuiRequire {host} {
    variable ::GX::PreviewGui::mounts
    if {![dict exists $mounts $host]} {error {Preview GUI mount has closed}}
    set record [dict get $mounts $host]
    set id [dict get $record module]
    if {[catch {
        set root [dict get $record root]
        if {![winfo exists $root] || [winfo id $root] ne [dict get $record window_id] || ![moduleIsEnabled $id] || [dict exists $::GX::pluginRuntimePending $id]} {error stale}
        if {![_datasetPreviewProviderContextCurrent [dict get $record dataset] [dict get $record context] [dict get $record identity]]} {error stale}
        if {[sha256File [moduleField $id descriptor]] ne [dict get $record descriptor_sha256]} {error stale}
        if {![uplevel #0 [dict get $record guard]]} {error stale}
    }]} {
        _datasetPreviewGuiDispose $host {Dataset, Session, package or Preview changed}
        error {Preview GUI belongs to a previous or disabled component; refresh Preview}
    }
    return $record
}
proc ::GX::datasetPreviewGuiContext {host} {return [dict get [_datasetPreviewGuiRequire $host] context]}
proc ::GX::_datasetPreviewGuiCacheCallback {record callback} {
    if {[catch {llength $callback} length] || $length<1 || $length>16 || [string bytelength $callback]>65536 ||
        ![string match [format {%s::*} [dict get $record namespace]] [lindex $callback 0]] ||
        ![llength [info commands [lindex $callback 0]]]} {error {Preview cache callback must belong to the mounted module}}
}
proc ::GX::_datasetPreviewGuiCacheDeliver {host callback receipt} {
    if {[catch {set record [_datasetPreviewGuiRequire $host]}]} return
    _datasetPreviewGuiCacheCallback $record $callback
    if {[catch {_datasetPrivateWithModule [dict get $record module] [list {*}$callback $receipt]} reason]} {puts stderr "Preview cache callback: $reason"}
}
proc ::GX::_datasetPreviewGuiCacheOptions {record} {return [datasetPublicationV2DictDefault $record cache_options {}]}
proc ::GX::_datasetPreviewGuiCachedCurvesPrepared {host generation callback response} {
    if {[dict exists $response status] && [dict get $response status] eq {preparing}} return
    if {[catch {set record [_datasetPreviewGuiRequire $host]}] ||
        [datasetPublicationV2DictDefault $record curve_generation -1]!=$generation} return
    dict set ::GX::PreviewGui::mounts $host curve_subscription {}
    if {[catch {
        if {[datasetPublicationV2DictDefault $response status error] ne {ready}} {error [datasetPublicationV2DictDefault $response message {Preview cache preparation failed}]}
        set id [dict get $record dataset]
        set key [datasetPreviewCacheKey $id [_datasetPreviewGuiCacheOptions $record]]
        if {[dict get $response key] ne $key} {error {Preview cache settings/source changed before delivery}}
        set retained [datasetPreviewCacheRead $id $key]
        if {$retained eq {} || ![dict get $retained current] || ![dict exists $retained native_model panels]} {error {CORE has no current retained Plot representation}}
        set result [dict create status ready dataset_id $id key $key cache_hit [datasetPublicationV2DictDefault $response cache_hit 0] model [dict get $retained native_model] total_rows [dict get $retained row_count] displayed_points [dict get $retained displayed_points]]
    } reason]} {set result [dict create status error message $reason]}
    _datasetPreviewGuiCacheDeliver $host $callback $result
}
proc ::GX::datasetPreviewGuiCachedCurvesRequest {host callback} {
    set record [_datasetPreviewGuiRequire $host];_datasetPreviewGuiCacheCallback $record $callback
    set previous [datasetPublicationV2DictDefault $record curve_subscription {}]
    if {$previous ne {}} {datasetPreviewGuiCacheCancel $host $previous}
    set generation [incr ::GX::PreviewGui::cacheSerial]
    dict set ::GX::PreviewGui::mounts $host curve_generation $generation
    set id [dict get $record dataset];set options [_datasetPreviewGuiCacheOptions $record]
    set key [datasetPreviewCacheKey $id $options];set retained [datasetPreviewCacheRead $id $key]
    if {$retained ne {} && [dict get $retained current] && [dict exists $retained native_model panels]} {
        set ticket preview-curve-hit-$generation
        dict set ::GX::PreviewGui::mounts $host curve_subscription $ticket
        after idle [list ::GX::_datasetPreviewGuiCachedCurvesPrepared $host $generation $callback [dict create status ready key $key cache_hit 1]]
        return [dict create status ready key $key cache_hit 1 ticket $ticket]
    }
    set sub [datasetPreviewCacheSubscribe $id $options [list ::GX::_datasetPreviewGuiCachedCurvesPrepared $host $generation $callback]]
    dict set ::GX::PreviewGui::mounts $host curve_subscription [dict get $sub ticket]
    return [dict create status preparing key [dict get $sub key] cache_hit 0 ticket [dict get $sub ticket]]
}
proc ::GX::_datasetPreviewGuiPageForget {ticket} {
    if {![dict exists $::GX::PreviewGui::pageSubscriptions $ticket]} {return {}}
    set sub [dict get $::GX::PreviewGui::pageSubscriptions $ticket]
    dict unset ::GX::PreviewGui::pageSubscriptions $ticket
    set host [dict get $sub host]
    if {[dict exists $::GX::PreviewGui::mounts $host]} {
        set tickets [datasetPublicationV2DictDefault [dict get $::GX::PreviewGui::mounts $host] page_subscriptions {}]
        set index [lsearch -exact $tickets $ticket]
        if {$index>=0} {dict set ::GX::PreviewGui::mounts $host page_subscriptions [lreplace $tickets $index $index]}
    }
    return $sub
}
proc ::GX::_datasetPreviewGuiPageDeliver {ticket result} {
    set sub [_datasetPreviewGuiPageForget $ticket]
    if {$sub eq {}} return
    set host [dict get $sub host]
    if {[catch {set record [_datasetPreviewGuiRequire $host]}]} return
    if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $sub token]} return
    if {[dict get $result status] eq {ready} &&
        [catch {expr {[datasetPreviewCacheKey [dict get $record dataset] [_datasetPreviewGuiCacheOptions $record]] eq [dict get $sub key]}} current]} {set current 0}
    if {[dict get $result status] eq {ready} && !$current} {set result [dict create status error message {Preview source/settings changed before page delivery}]}
    _datasetPreviewGuiCacheDeliver $host [dict get $sub callback] $result
}
proc ::GX::_datasetPreviewGuiPageFinish {taskKey generation result} {
    if {![dict exists $::GX::PreviewGui::pageTasks $taskKey] || [dict get $::GX::PreviewGui::pageTasks $taskKey generation]!=$generation} return
    set task [dict get $::GX::PreviewGui::pageTasks $taskKey]
    dict unset ::GX::PreviewGui::pageTasks $taskKey
    foreach ticket [dict get $task subscribers] {_datasetPreviewGuiPageDeliver $ticket $result}
}
proc ::GX::_datasetPreviewGuiCachedPageTaskDone {taskKey generation response} {
    if {[dict exists $::GX::PreviewGui::pageDraining $generation]} {dict unset ::GX::PreviewGui::pageDraining $generation;return}
    if {![dict exists $::GX::PreviewGui::pageTasks $taskKey] || [dict get $::GX::PreviewGui::pageTasks $taskKey generation]!=$generation} return
    set task [dict get $::GX::PreviewGui::pageTasks $taskKey]
    if {[catch {
        if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $task token] || $::GX::currentSession ne [dict get $task session]} {error {Preview page Session lifetime changed}}
        if {![dict get $response ok] || [dict get $response result key] ne [dict get $task key] ||
            [dict get $response result dataset_id] ne [dict get $task dataset_id]} {error [datasetPublicationV2DictDefault $response error {CORE asynchronous page worker failed}]}
        if {[datasetPreviewCacheKey [dict get $task dataset_id] [dict get $task cache_options]] ne [dict get $task key]} {error {Preview page source/settings changed}}
        set page [datasetPreviewCachedPageRead [dict get $task dataset_id] [dict get $task options] [dict get $task cache_options]]
        if {$page eq {}} {error {CORE asynchronous page was not verified}}
        set result [dict create status ready dataset_id [dict get $task dataset_id] key [dict get $task key] page $page cache_hit 0]
    } reason]} {set result [dict create status error message $reason]}
    _datasetPreviewGuiPageFinish $taskKey $generation $result
}
proc ::GX::_datasetPreviewGuiCachedPageBaseReady {taskKey generation response} {
    if {![dict exists $::GX::PreviewGui::pageTasks $taskKey] || [dict get $::GX::PreviewGui::pageTasks $taskKey generation]!=$generation} return
    if {[datasetPublicationV2DictDefault $response status error] eq {preparing}} return
    set task [dict get $::GX::PreviewGui::pageTasks $taskKey]
    if {[dict get $task request] ne {}} return
    dict set ::GX::PreviewGui::pageTasks $taskKey base_ticket {}
    if {[datasetPublicationV2DictDefault $response status error] ne {ready}} {
        _datasetPreviewGuiPageFinish $taskKey $generation [dict create status error message [datasetPublicationV2DictDefault $response message {CORE retained preparation failed}]]
        return
    }
    if {[catch {
        if {[catch {interactiveDocumentSessionToken} token] || $token ne [dict get $task token] || $::GX::currentSession ne [dict get $task session]} {error {Preview page Session lifetime changed}}
        if {[dict get $response key] ne [dict get $task key]} {error {Preview retained worker returned a different key}}
        if {[datasetPreviewCacheKey [dict get $task dataset_id] [dict get $task cache_options]] ne [dict get $task key]} {error {Preview page source/settings changed}}
        set payload [dict create schema gxtxt.preview_page_worker.v1 session [dict get $task session] dataset_id [dict get $task dataset_id] options [dict get $task cache_options] page_options [dict get $task options] expected_key [dict get $task key] preview_activation [_datasetPreviewActivationSnapshot]]
        if {[string bytelength $payload]>1048576} {error {Preview page request exceeds1MiB}}
        set command [list [auto_execok setsid] [auto_execok tclsh] [file join $::GX::scriptDir core tcl dataset_preview_worker_v1.tcl] $::GX::scriptDir]
        set request [scriptJobAsync $command $payload [list ::GX::_datasetPreviewGuiCachedPageTaskDone $taskKey $generation] {timeout_ms 120000 max_bytes 65536 process_group 1 ui_lifetime 1 separate_stderr 1 label {Dataset Preview canonical page}}]
    } reason]} {_datasetPreviewGuiPageFinish $taskKey $generation [dict create status error message $reason];return}
    dict set ::GX::PreviewGui::pageTasks $taskKey request $request
}
proc ::GX::datasetPreviewGuiCachedPageRequest {host options callback} {
    set record [_datasetPreviewGuiRequire $host];_datasetPreviewGuiCacheCallback $record $callback
    set options [_datasetPreviewCachedPageOptions $options]
    set id [dict get $record dataset];set cacheOptions [_datasetPreviewGuiCacheOptions $record]
    set key [datasetPreviewCacheKey $id $cacheOptions];set token [interactiveDocumentSessionToken]
    set taskKey [datasetStorageSha256Text $::GX::currentSession [list $::GX::currentSession $token $id $key $options]]
    if {[dict exists $::GX::PreviewGui::pageTasks $taskKey]} {
        foreach ticket [dict get $::GX::PreviewGui::pageTasks $taskKey subscribers] {
            set sub [dict get $::GX::PreviewGui::pageSubscriptions $ticket]
            if {[dict get $sub host] eq $host && [dict get $sub callback] eq $callback} {return [dict create status preparing key $key cache_hit 0 coalesced 1 ticket $ticket]}
        }
        if {[llength [dict get $::GX::PreviewGui::pageTasks $taskKey subscribers]]>=32} {error {Too many Preview page subscribers}}
    }
    set tickets [datasetPublicationV2DictDefault $record page_subscriptions {}]
    if {[llength $tickets]>=8 || [dict size $::GX::PreviewGui::pageSubscriptions]>=256} {error {Too many Preview page subscriptions}}
    set page [datasetPreviewCachedPageRead $id $options $cacheOptions]
    if {$page eq {} && ![dict exists $::GX::PreviewGui::pageTasks $taskKey] &&
        [dict size $::GX::PreviewGui::pageTasks]+[dict size $::GX::PreviewGui::pageDraining]>=8} {error {Preview page preparation capacity is busy}}
    set ticket preview-page-watch-[incr ::GX::PreviewGui::cacheSerial]
    dict set ::GX::PreviewGui::pageSubscriptions $ticket [dict create host $host callback $callback key $key token $token task_key $taskKey]
    lappend tickets $ticket;dict set ::GX::PreviewGui::mounts $host page_subscriptions $tickets
    if {$page ne {}} {
        # No scientific reread or new worker; cancellation still owns this idle delivery.
        dict set ::GX::PreviewGui::pageSubscriptions $ticket task_key {}
        after idle [list ::GX::_datasetPreviewGuiPageDeliver $ticket [dict create status ready dataset_id $id key $key page $page cache_hit 1]]
        return [dict create status ready key $key cache_hit 1 ticket $ticket]
    }
    if {[dict exists $::GX::PreviewGui::pageTasks $taskKey]} {
        set subscribers [dict get $::GX::PreviewGui::pageTasks $taskKey subscribers]
        lappend subscribers $ticket
        dict set ::GX::PreviewGui::pageTasks $taskKey subscribers $subscribers
        return [dict create status preparing key $key cache_hit 0 coalesced 1 ticket $ticket]
    }
    set generation [incr ::GX::PreviewGui::cacheSerial]
    dict set ::GX::PreviewGui::pageTasks $taskKey [dict create generation $generation key $key session $::GX::currentSession token $token dataset_id $id options $options cache_options $cacheOptions subscribers [list $ticket] request {} base_ticket {}]
    if {[catch {set sub [datasetPreviewCacheSubscribe $id $cacheOptions [list ::GX::_datasetPreviewGuiCachedPageBaseReady $taskKey $generation]]} reason]} {
        _datasetPreviewGuiPageFinish $taskKey $generation [dict create status error message $reason]
        return [dict create status error key $key message $reason ticket $ticket]
    }
    dict set ::GX::PreviewGui::pageTasks $taskKey base_ticket [dict get $sub ticket]
    return [dict create status preparing key $key cache_hit 0 coalesced 0 ticket $ticket]
}
proc ::GX::_datasetPreviewGuiPageCancel {host ticket} {
    if {![dict exists $::GX::PreviewGui::pageSubscriptions $ticket] || [dict get $::GX::PreviewGui::pageSubscriptions $ticket host] ne $host} {return 0}
    set sub [_datasetPreviewGuiPageForget $ticket];set key [dict get $sub task_key]
    if {$key eq {} || ![dict exists $::GX::PreviewGui::pageTasks $key]} {return 1}
    set task [dict get $::GX::PreviewGui::pageTasks $key];set tickets [dict get $task subscribers]
    set index [lsearch -exact $tickets $ticket];if {$index>=0} {set tickets [lreplace $tickets $index $index]}
    if {[llength $tickets]} {dict set ::GX::PreviewGui::pageTasks $key subscribers $tickets;return 1}
    dict unset ::GX::PreviewGui::pageTasks $key
    set base [dict get $task base_ticket];if {$base ne {}} {datasetPreviewCacheUnsubscribe $base}
    set request [dict get $task request]
    if {$request ne {}} {
        dict set ::GX::PreviewGui::pageDraining [dict get $task generation] $request
        catch {scriptJobRequestCancel $request}
    }
    return 1
}
proc ::GX::datasetPreviewGuiCacheCancel {host ticket} {
    set record [_datasetPreviewGuiRequire $host]
    if {[datasetPublicationV2DictDefault $record curve_subscription {}] eq $ticket && $ticket ne {}} {
        dict set ::GX::PreviewGui::mounts $host curve_generation [incr ::GX::PreviewGui::cacheSerial]
        dict set ::GX::PreviewGui::mounts $host curve_subscription {}
        datasetPreviewCacheUnsubscribe $ticket
        return 1
    }
    return [_datasetPreviewGuiPageCancel $host $ticket]
}
proc ::GX::_datasetPreviewGuiMount {module dataset parent representation plot guard {tabId {}}} {
    variable ::GX::PreviewGui::mounts;variable ::GX::PreviewGui::serial
    if {[llength [info commands ::tk]]==0 || [_datasetPreviewNativeWorker]} {error {Preview GUI requires the Tk host, never the native worker}}
    set declaration [_datasetPreviewProviderDescriptor $module]
    if {[dict get $declaration gui_api_version]!=1 || ![moduleIsEnabled $module]} {error {Preview component has not opted into the GUI API}}
    modulePublicApiActivate $module PREVIEW_COMPONENT_GUI_API_v1
    set ns [descriptorValue [moduleField $module dict] public_api.PREVIEW_COMPONENT_GUI_API_v1 namespace {}]
    foreach command {guiMount guiDispose} {if {![llength [info commands ${ns}::$command]]} {error "Preview GUI requires ${ns}::$command"}}
    if {[dict size $mounts]>=128} {error {Too many live Preview GUI panes}}
    set host preview-gui#[incr serial]
    set context [_datasetPreviewProviderContext $dataset $representation]
    if {$plot ne {} && [catch {::GX::PlotDatasetAPIv4::widgetReceipt $plot}]} {set plot {}}
    dict set context gui_api PREVIEW_COMPONENT_GUI_API_v1
    dict set context component_id $module
    dict set context tab_id $tabId
    if {[dict exists $representation options source_window]} {dict set context representation source_window [dict get $representation options source_window]}
    dict set context viewport_available [expr {$plot ne {}}]
    dict set mounts $host [dict create module $module dataset $dataset root $parent window_id [winfo id $parent] context $context identity [datasetViewerScientificIdentity $dataset] descriptor_sha256 [sha256File [moduleField $module descriptor]] guard $guard namespace $ns plot $plot controls {} panels {} cache_options [datasetPublicationV2DictDefault $representation options {}]]
    bind $parent <Destroy> +[list ::GX::_datasetPreviewGuiDestroyed $host $parent %W]
    set trace [list ::GX::_datasetPreviewGuiChanged $host]
    trace add variable ::GX::currentSession {write unset} $trace
    dict set mounts $host session_trace $trace
    dict set mounts $host subscription [datasetCatalogSubscribe [list ::GX::_datasetPreviewGuiChanged $host]]
    grid columnconfigure $parent 0 -weight 1
    try {
        _datasetPreviewGuiRequire $host
        _datasetPrivateWithModule $module [list ${ns}::guiMount $host $context]
        _datasetPreviewGuiRequire $host
    } on error {message options} {
        _datasetPreviewGuiDispose $host {Mount failed}
        return -options $options $message
    }
    return $host
}
proc ::GX::_datasetPreviewGuiDestroyed {host parent actual} {
    if {$parent eq $actual} {_datasetPreviewGuiDispose $host {Preview pane closed or replaced}}
}
proc ::GX::_datasetPreviewGuiChanged {host args} {catch {_datasetPreviewGuiRequire $host}}
proc ::GX::datasetPreviewGuiRefresh {} {
    foreach host [dict keys $::GX::PreviewGui::mounts] {_datasetPreviewGuiChanged $host}
}
proc ::GX::datasetPreviewGuiRelease {} {
    foreach host [dict keys $::GX::PreviewGui::mounts] {_datasetPreviewGuiDispose $host {Preview closed or replaced}}
}
proc ::GX::_datasetPreviewGuiDispose {host reason} {
    variable ::GX::PreviewGui::mounts
    if {![dict exists $mounts $host]} return
    set record [dict get $mounts $host]
    dict unset mounts $host
    if {[dict exists $record subscription]} {datasetCatalogUnsubscribe [dict get $record subscription]}
    set ticket [datasetPublicationV2DictDefault $record curve_subscription {}]
    if {$ticket ne {}} {catch {datasetPreviewCacheUnsubscribe $ticket}}
    foreach ticket [datasetPublicationV2DictDefault $record page_subscriptions {}] {_datasetPreviewGuiPageCancel $host $ticket}
    if {[dict exists $record session_trace]} {trace remove variable ::GX::currentSession {write unset} [dict get $record session_trace]}
    # GUI disposal is notification, not another authority to publish data or
    # resurrect widgets. Invalidate the handle before calling module code.
    set command [dict get $record namespace]::guiDispose
    if {[llength [info commands $command]] && [catch {_datasetPrivateWithModule [dict get $record module] [list $command $host [dict get $record context] $reason]} message]} {
        puts stderr "Preview GUI disposal: $message"
    }
    dict for {id panel} [dict get $record panels] {native2DViewportPanelDestroy [dict get $panel viewport] [dict get $panel panel_id]}
    dict for {id control} [dict get $record controls] {
        set widget [dict get $control widget]
        if {[winfo exists $widget]} {destroy $widget}
        unset -nocomplain ::GX::PreviewGui::values($host,$id)
    }
}
proc ::GX::_datasetPreviewGuiId {id} {
    if {![regexp {^[a-z][a-z0-9_]{0,47}$} $id]} {error {Use a stable lowercase Preview control ID}}
}
proc ::GX::_datasetPreviewGuiControl {host id} {
    set record [_datasetPreviewGuiRequire $host]
    if {![dict exists $record controls $id]} {error {Unknown Preview GUI control}}
    set control [dict get $record controls $id]
    if {![winfo exists [dict get $control widget]]} {error {Preview GUI control has closed}}
    return $control
}
proc ::GX::_datasetPreviewGuiIconProperties {type properties icons} {
    set id [datasetPublicationV2DictDefault $properties icon {}]
    if {$id eq {}} {
        foreach key {icon_disabled icon_hover icon_selected} {if {[datasetPublicationV2DictDefault $properties $key {}] ne {}} {error {Icon variants require a normal icon}}}
        return
    }
    if {$type ni {action label status checkbutton toggle}} {error {This UI Field component does not support icons}}
    if {$type ni {checkbutton toggle} && [datasetPublicationV2DictDefault $properties icon_selected {}] ne {}} {error {Selected icons require a control with boolean selection semantics}}
    set presentation {}
    foreach key {icon icon_disabled icon_hover icon_selected presentation icon_position icon_size icon_spacing} {if {[dict exists $properties $key]} {dict set presentation $key [dict get $properties $key]}}
    _viewerGuiCommandIconsValidate command_toolbar [dict create actions icon command_icons [dict create icon $presentation]] $icons
    set label [string trim [datasetPublicationV2DictDefault $properties label {}]]
    if {$label eq {}} {set label [string trim [datasetPublicationV2DictDefault $properties text {}]]}
    if {[datasetPublicationV2DictDefault $properties presentation icon_text] eq {icon_only} && $label eq {} && [string trim [datasetPublicationV2DictDefault $properties tooltip {}]] eq {}} {error {Icon-only controls require an accessible label or tooltip}}
}
proc ::GX::_datasetPreviewGuiIconApply {control} {
    set widget [dict get $control widget];set type [dict get $control type];set p [dict get $control properties]
    if {$type eq {toggle}} {append widget .entry}
    set icon [datasetPublicationV2DictDefault $p icon {}]
    if {$icon ne {}} {uiFieldIconApply $widget $p [dict get $control icons $icon] [dict get $control icons]}
    if {$type in {action label status checkbutton toggle}} {
        set tip [datasetPublicationV2DictDefault $p tooltip {}]
        if {$type eq {status}} {
            set tip [dict get $control status_text]
            if {[datasetPublicationV2DictDefault $p tooltip {}] ne {}} {append tip "\n\n[dict get $p tooltip]"}
            append tip "\n\nClick or press Enter for the complete status."
        }
        if {$tip eq {} && [datasetPublicationV2DictDefault $p presentation icon_text] eq {icon_only}} {set tip [datasetPublicationV2DictDefault $p label [datasetPublicationV2DictDefault $p text {}]]}
        # Use the existing tooltip owner with one replaceable bindtag, including
        # text+icon labels. Reconfiguring presentation must not accumulate binds.
        set tag GXPreviewTooltip$widget
        if {$tag ni [bindtags $widget]} {bindtags $widget [linsert [bindtags $widget] 0 $tag]}
        if {$type eq {action}} {bind $widget <Enter> {};bind $widget <Leave> {}}
        if {$type eq {status}} {
            bind $tag <Enter> [list ::GX::_datasetPreviewGuiStatusTip [dict get $control host] [dict get $control id] $tip]
        } else {bind $tag <Enter> [list ::GX::native2DViewportTooltipShow $widget $tip]}
        bind $tag <Leave> [list ::GX::native2DViewportTooltipHide $widget]
        bind $tag <Destroy> [list ::GX::_datasetPreviewGuiTooltipDispose $tag]
    }
}
proc ::GX::_datasetPreviewGuiTooltipDispose {tag} {foreach event [bind $tag] {bind $tag $event {}}}
proc ::GX::_datasetPreviewGuiStatusTip {host id text} {
    if {[catch {set control [_datasetPreviewGuiControl $host $id]}]} return
    native2DViewportTooltipShow [dict get $control widget] $text
}
# Status is a compact presentation output, not a variable-height document.
# Retain the complete value separately from the measured one-line projection;
# the existing tooltip/dialog/clipboard owners expose it without starving a
# flexible scientific table. Ordinary descriptive labels keep their wrapping.
proc ::GX::_datasetPreviewGuiStatusRefresh {host id} {
    if {[catch {set control [_datasetPreviewGuiControl $host $id]}]} return
    set widget [dict get $control widget]
    set style [$widget cget -style];if {$style eq {}} {set style TLabel}
    set font [$widget cget -font]
    if {$font eq {}} {set font [ttk::style lookup $style -font]}
    if {$font eq {}} {set font TkDefaultFont}
    set summary [string map [list \n { } \r { } \t { }] [dict get $control status_text]]
    # Match the existing UI Field distinction between stretched controls and
    # natural-size packed/grid labels. The latter must not collapse to one
    # character merely because their initial Configure has not run yet.
    set stretched 0
    if {[winfo manager $widget] eq {pack}} {
        set stretched [expr {[dict get [pack info $widget] -fill] in {x both}}]
    } elseif {[winfo manager $widget] eq {grid}} {
        set layout [grid info $widget];set sticky [dict get $layout -sticky]
        if {[string first e $sticky]>=0 && [string first w $sticky]>=0} {
            for {set col [dict get $layout -column]} {$col<[dict get $layout -column]+[dict get $layout -columnspan]} {incr col} {
                if {[grid columnconfigure [dict get $layout -in] $col -weight]>0} {set stretched 1;break}
            }
        }
    }
    set width [expr {$stretched?1:0}]
    if {[$widget cget -width]!=$width} {$widget configure -width $width}
    set available [expr {$stretched?[winfo width $widget]:min(400,[winfo width [winfo parent $widget]])}]
    if {!$stretched && $available<2} {set available 400}
    incr available -8
    set padding [$widget cget -padding]
    if {$padding eq {}} {set padding [ttk::style lookup $style -padding]}
    if {[llength $padding]} {
        incr available [expr {-[winfo pixels $widget [lindex $padding 0]]-[winfo pixels $widget [lindex $padding [expr {[llength $padding]>2?2:0}]]]}]
    }
    if {[$widget cget -compound] in {left right} && [llength [$widget cget -image]]} {
        set photo [lindex [$widget cget -image] 0]
        if {$photo in [image names]} {
            set gap [ttk::style lookup $style -space];if {![string is integer -strict $gap]} {set gap 4}
            incr available [expr {-[image width $photo]-$gap}]
        }
    }
    set available [expr {max(1,$available)}]
    # Bound measurement work for unusually large diagnostics; the original
    # text remains untouched in the control and the inspectable snapshot.
    if {[string length $summary]>256} {set summary "[string range $summary 0 254]…"}
    while {[string length $summary]>1 && [font measure $font $summary]>$available} {
        set summary "[string range $summary 0 end-2]…"
    }
    if {[datasetPublicationV2DictDefault [dict get $control properties] presentation icon_text] eq {icon_only}} {set summary {}}
    if {[$widget cget -text] ne $summary} {$widget configure -text $summary}
}
proc ::GX::_datasetPreviewGuiStatusClose {window owner} {
    uiFieldDialogClose $window
    if {[winfo exists $owner] && [winfo ismapped $owner]} {focus $owner}
}
proc ::GX::_datasetPreviewGuiStatusDestroyed {widget actual} {
    if {$actual ne $widget} return
    native2DViewportTooltipHide $widget
    set snapshot ${widget}_status_snapshot
    if {[winfo exists $snapshot]} {uiFieldDialogClose $snapshot}
}
proc ::GX::_datasetPreviewGuiStatusCopy {host id text} {
    if {[catch {_datasetPreviewGuiControl $host $id}]} return
    datasetPreviewLiveStatusCopy $text
}
proc ::GX::_datasetPreviewGuiStatusInspect {host id} {
    if {[catch {set control [_datasetPreviewGuiControl $host $id]}]} return
    set owner [dict get $control widget];set text [dict get $control status_text]
    set w ${owner}_status_snapshot
    if {[winfo exists $w]} {uiFieldDialogClose $w}
    native2DViewportTooltipHide $owner
    uiFieldDialogCreate $w $owner {Preview status snapshot} 760x420
    ttk::frame $w.body
    ::text $w.body.text -wrap word -font TkTextFont -width 1 -height 1 -yscrollcommand [list $w.body.scroll set]
    ttk::scrollbar $w.body.scroll -orient vertical -command [list $w.body.text yview]
    grid $w.body.text -row 0 -column 0 -sticky nsew
    grid $w.body.scroll -row 0 -column 1 -sticky ns
    grid columnconfigure $w.body 0 -weight 1;grid rowconfigure $w.body 0 -weight 1
    $w.body.text insert 1.0 $text;$w.body.text configure -state disabled
    bind $w.body.text <Control-a> [list $w.body.text tag add sel 1.0 end]
    ttk::frame $w.buttons
    ttk::button $w.buttons.copy -text {Copy status} -command [list ::GX::_datasetPreviewGuiStatusCopy $host $id $text]
    ttk::button $w.buttons.close -text Close -command [list ::GX::_datasetPreviewGuiStatusClose $w $owner]
    pack $w.buttons.copy $w.buttons.close -side left -padx 4
    pack $w.buttons -side bottom -anchor e -padx 6 -pady 6
    pack $w.body -fill both -expand 1 -padx 6 -pady 6
    bind $w <Escape> [list ::GX::_datasetPreviewGuiStatusClose $w $owner]
    wm protocol $w WM_DELETE_WINDOW [list ::GX::_datasetPreviewGuiStatusClose $w $owner]
    uiFieldDialogPresent $w $w.buttons.close
}
proc ::GX::datasetPreviewGuiControlCreate {host id type properties {options {}}} {
    variable ::GX::PreviewGui::mounts
    set record [_datasetPreviewGuiRequire $host]
    _datasetPreviewGuiId $id
    if {[dict exists $record controls $id] || [dict exists $record panels $id]} {error {Preview GUI ID already exists}}
    if {![dict exists [uiFieldComponentCapabilities] $type]} {error {Unknown UI Field component}}
    foreach key [dict keys $options] {if {$key ni {parent layout callback icons command_icons}} {error {Unknown Preview control option}}}
    set parentId [datasetPublicationV2DictDefault $options parent {}]
    set parent [dict get $record root];set parentType panel;set icons {};set commandIcons {}
    if {$parentId ne {}} {
        if {[dict exists $record panels $parentId]} {set parent [dict get $record panels $parentId body]} else {
            set container [_datasetPreviewGuiControl $host $parentId]
            set parentType [dict get $container type]
            if {$parentType ni {panel section tabs tab splitter}} {error {Parent is not a UI Field container}}
            set parent [dict get $container widget];set icons [dict get $container icons];set commandIcons [dict get $container command_icons]
        }
    }
    if {[dict exists $options icons]} {set icons [viewerGuiIconsValidate [dict get $options icons]]}
    if {[dict exists $commandIcons $id]} {set properties [dict merge [dict get $commandIcons $id] $properties]}
    _datasetPreviewGuiIconProperties $type $properties $icons
    set commandIcons [datasetPublicationV2DictDefault $options command_icons {}]
    if {$commandIcons ne {}} {
        if {$type ne {panel}} {error {command_icons belongs to a UI Field toolbar panel}}
        _viewerGuiCommandIconsValidate command_toolbar [dict create actions [dict keys $commandIcons] command_icons $commandIcons] $icons
    }
    set widget $parent.$id
    set variable ::GX::PreviewGui::values($host,$id)
    set $variable [datasetPublicationV2DictDefault $properties default [expr {$type in {checkbutton toggle} ? 0 : {}}]]
    set control [dict create widget $widget type $type properties $properties icons $icons command_icons $commandIcons callback [datasetPublicationV2DictDefault $options callback {}]]
    if {$type eq {status}} {
        dict set control status_text [datasetPublicationV2DictDefault $properties text {}]
        dict set control host $host;dict set control id $id
    }
    try {
        uiFieldComponentCreate $widget $type $properties $variable [list ::GX::_datasetPreviewGuiDispatch $host $id]
        if {$type eq {status}} {
            # Replace only this Preview status's inherited auto-wrap handler.
            $widget configure -wraplength 0 -width 1 -takefocus 1
            bind $widget <Configure> [list ::GX::_datasetPreviewGuiStatusRefresh $host $id]
            bind $widget <<ThemeChanged>> [list ::GX::_datasetPreviewGuiStatusRefresh $host $id]
            bind $widget <Destroy> [list ::GX::_datasetPreviewGuiStatusDestroyed $widget %W]
            foreach event {<Button-1> <Return> <KP_Enter> <space>} {bind $widget $event "[list ::GX::_datasetPreviewGuiStatusInspect $host $id];break"}
            foreach event {<FocusOut> <Escape>} {bind $widget $event [list ::GX::native2DViewportTooltipHide $widget]}
        }
        _datasetPreviewGuiIconApply $control
        if {$parentType in {tabs splitter}} {
            if {$parentType eq {tabs}} {$parent add $widget -text [datasetPublicationV2DictDefault $properties title $id]} else {$parent add $widget -weight 1}
        } else {uiFieldComponentLayout $widget $parent [datasetPublicationV2DictDefault $options layout {}]}
        dict set mounts $host controls $id $control
        if {$type eq {status}} {_datasetPreviewGuiStatusRefresh $host $id}
    } on error {message opts} {
        if {[winfo exists $widget]} {destroy $widget}
        unset -nocomplain $variable
        return -options $opts $message
    }
    return $widget
}
proc ::GX::_datasetPreviewGuiDispatch {host id args} {
    if {[catch {set control [_datasetPreviewGuiControl $host $id]}]} return
    set widget [dict get $control widget]
    if {[dict get $control type] in {toggle field choice dataset_selector}} {append widget .entry}
    if {[winfo class $widget] ni {Listbox Text} && [$widget instate disabled]} return
    set callback [dict get $control callback]
    if {$callback eq {}} return
    set module [dict get [_datasetPreviewGuiRequire $host] module]
    set value {}
    if {[catch {set value [datasetPreviewGuiControlGet $host $id]} message] && [dict get $control type] in {field choice}} {
        # Actions have no readable scalar value, but an invalid typed draft
        # must never masquerade as an empty successful change event.
        datasetPreviewLiveSetStatus "$module controls: $message" error
        return
    }
    set event [dict create control_id $id type [dict get $control type] event [expr {[dict get $control type] eq {action} ? {invoke} : {changed}}] value $value]
    if {[catch {_datasetPrivateWithModule $module [list {*}$callback $host $event]} message]} {
        datasetPreviewLiveSetStatus "$module controls: $message" error
    } else {
        # A corrected edit must not leave the previous validation error on
        # screen. Acceptance describes this callback, never a scientific Job.
        if {[catch {_datasetPreviewGuiRequire $host}]} return
        datasetPreviewLiveSetStatus "$module control [dict get $event control_id] accepted"
    }
}
proc ::GX::datasetPreviewGuiControlGet {host id} {
    set control [_datasetPreviewGuiControl $host $id]
    set widget [dict get $control widget];set type [dict get $control type]
    set value [uiFieldComponentRead $widget $type]
    # Entry inspection may expose an in-progress invalid draft. A Preview
    # callback must receive the existing field's canonical typed value or its
    # real validation error; reading must not synthesize a changed callback.
    if {$type in {field choice}} {return [uiFieldNormalize [dict get $::GX::UiField::widgets $widget descriptor] $value]}
    return $value
}
proc ::GX::datasetPreviewGuiControlSet {host id value} {
    set control [_datasetPreviewGuiControl $host $id]
    set type [dict get $control type];set widget [dict get $control widget]
    switch $type {
        checkbutton - toggle {if {![string is boolean -strict $value]} {error {Boolean control requires a boolean}};set ::GX::PreviewGui::values($host,$id) [expr {!!$value}]}
        field - choice {
            set value [uiFieldNormalize [dict get $::GX::UiField::widgets $widget descriptor] $value]
            set ::GX::PreviewGui::values($host,$id) $value
        }
        combobox - entry - dataset_selector - progress {set ::GX::PreviewGui::values($host,$id) $value}
        list {uiFieldComponentItemsSet $widget list $value}
        label {$widget configure -text $value}
        status {
            dict set control status_text $value
            dict set ::GX::PreviewGui::mounts $host controls $id $control
            _datasetPreviewGuiIconApply $control
            _datasetPreviewGuiStatusRefresh $host $id
        }
        default {error {This control has no writable public value}}
    }
    return $value
}
proc ::GX::datasetPreviewGuiControlConfigure {host id properties} {
    variable ::GX::PreviewGui::mounts
    set control [_datasetPreviewGuiControl $host $id]
    foreach key [dict keys $properties] {if {$key ni {label text tooltip icon icon_disabled icon_hover icon_selected presentation icon_position icon_size icon_spacing}} {error {Use ControlSet/ControlState for values and state; configure only presentation}}
    }
    set merged [dict merge [dict get $control properties] $properties]
    set type [dict get $control type];set widget [dict get $control widget]
    _datasetPreviewGuiIconProperties $type $merged [dict get $control icons]
    if {[dict exists $properties label]} {
        if {$type in {action checkbutton}} {$widget configure -text [dict get $properties label]} elseif {[winfo exists $widget.caption]} {$widget.caption configure -text [dict get $properties label]}
    }
    if {[dict exists $properties text] && $type in {label status}} {
        if {$type eq {status}} {dict set control status_text [dict get $properties text]} else {$widget configure -text [dict get $properties text]}
    }
    dict set control properties $merged
    if {[datasetPublicationV2DictDefault $merged icon {}] eq {} && $type in {action label status checkbutton toggle}} {
        set target $widget;if {$type eq {toggle}} {append target .entry}
        $target configure -image {} -compound none
        catch {dict unset ::GX::ViewerGui::iconBindings $target}
    }
    _datasetPreviewGuiIconApply $control
    dict set mounts $host controls $id $control
    if {$type eq {status}} {_datasetPreviewGuiStatusRefresh $host $id}
    return $widget
}
proc ::GX::datasetPreviewGuiControlState {host id {state {}}} {
    set control [_datasetPreviewGuiControl $host $id]
    set type [dict get $control type];set widget [dict get $control widget]
    if {$type in {toggle field choice dataset_selector}} {append widget .entry}
    if {$type in {panel section tabs tab splitter log list table}} {error {State applies to scalar/ttk controls}}
    dict for {key value} $state {
        if {$key ni {enabled selected} || ![string is boolean -strict $value]} {error {Expected enabled/selected boolean state}}
        if {$key eq {selected} && $type ni {checkbutton toggle}} {error {Selection belongs to boolean controls}}
    }
    if {[dict exists $state enabled]} {
        if {$type in {field entry choice combobox toggle checkbutton dataset_selector}} {uiFieldComponentEnabled [dict get $control widget] $type [dict get $state enabled]
        } else {$widget state [expr {[dict get $state enabled] ? {!disabled} : {disabled}}]}
    }
    if {[dict exists $state selected]} {datasetPreviewGuiControlSet $host $id [dict get $state selected]}
    return [dict create enabled [expr {![$widget instate disabled]}] selected [expr {$type in {checkbutton toggle} && [datasetPreviewGuiControlGet $host $id]}]]
}
proc ::GX::datasetPreviewGuiPanelCreate {host id title {anchor top-right} {options {}}} {
    variable ::GX::PreviewGui::mounts
    set record [_datasetPreviewGuiRequire $host];_datasetPreviewGuiId $id
    if {[dict exists $record panels $id] || [dict exists $record controls $id]} {error {Preview GUI ID already exists}}
    set plot [dict get $record plot]
    if {$plot eq {} || ![winfo exists $plot]} {error {This Preview has no supported Plot v4 viewport}}
    foreach key [dict keys $options] {if {$key ni {margin orientation priority max_width max_height min_width close scroll}} {error {Unknown shared viewport panel option}}}
    set viewport [::GX::PlotDatasetAPIv4::widgetChrome $plot]
    set panelId preview_gui_[string range $host 12 end]_$id
    set body [native2DViewportPanelCreate $viewport $panelId $title $anchor $options]
    dict set mounts $host panels $id [dict create viewport $viewport panel_id $panelId body $body]
    return $id
}
proc ::GX::datasetPreviewGuiPanelShow {host id visible} {
    set record [_datasetPreviewGuiRequire $host]
    if {![string is boolean -strict $visible] || ![dict exists $record panels $id]} {error {Expected an existing panel and boolean visibility}}
    set panel [dict get $record panels $id]
    native2DViewportPanelShow [dict get $panel viewport] [dict get $panel panel_id] $visible
}
proc ::GX::datasetPreviewGuiView {host operation} {
    set record [_datasetPreviewGuiRequire $host]
    set plot [dict get $record plot]
    if {$operation in {fit zoom_in zoom_out} && $plot eq {} && [dict exists $::GX::PreviewCpp::mounts $host scientific_frame_widget]} {
        set widget [dict get $::GX::PreviewCpp::mounts $host scientific_frame_widget]
        return [_previewScientificFrameView $host [dict get $::GX::PreviewCpp::mounts $host scientific_frame_form] $widget [dict get {fit fit zoom_in in zoom_out out} $operation]]
    }
    if {$plot eq {} || $operation ni {fit zoom_in zoom_out}} {error {Expected an available Plot viewport and fit/zoom_in/zoom_out}}
    if {$operation eq {fit}} {return [::GX::PlotDatasetAPIv4::widgetView $plot fit]}
    set factor [expr {$operation eq {zoom_in} ? 1.25 : .8}]
    foreach axis [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes] {
        if {[dict get $axis axis] eq {x}} {::GX::PlotDatasetAPIv4::widgetView $plot zoom [dict get $axis panel_id] $factor .5 .5}
    }
}

source [file join [file dirname [info script]] dataset_preview_source_request_v1.tcl]
source [file join [file dirname [info script]] dataset_preview_numeric_gui_v1.tcl]
