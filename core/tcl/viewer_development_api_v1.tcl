# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted host for the common restricted author backend; no authored Tcl is evaluated.
namespace eval ::GX::ViewerDevelopment {variable windows {};variable serial 0}
source [file join [file dirname [info script]] viewer_development_api_browser_v1.tcl]
source [file join [file dirname [info script]] viewer_development_gui_test_v1.tcl]
source [file join [file dirname [info script]] viewer_development_workspace_upgrade_v1.tcl]
proc ::GX::viewerDevelopmentApiInfo {} {
    return [dict create api_id VIEWER_DEVELOPMENT_API_v1 api_version 1 language cpp python_authoring 0 profiles {synthetic_view_v1 numeric_view_v1 document_view_v1 scientific_view_v1} operations {request inspect save check_source facility_request builder manual_asset debug debug_status debug_control preview invoke close installed_open installed_bindings workspace_upgrade_review workspace_review workspace_upgrade gui_test_attach gui_test_detach gui_test} backend core/python/gxtxt_viewer_development.py source_surface SOURCE_SURFACE_API_v1 gui_owner VIEWER_GUI_HOST_API_v1 renderer_owners {NATIVE2D_VIEWPORT_HOST_v1 NATIVE2D_TEMPORARY_DISPLAY_API_v1 NATIVE_PLOT_DISPLAY_API_v1 NATIVE_3D_GUI_HOST_API_v2} publication 0 install {candidate export; normal Plugin Manager promotion}]
}
# Encode bounded control text without evaluating it or invoking a language host.
proc ::GX::viewerDevelopmentJsonString {text} {
    set result {"}
    foreach character [split $text {}] {
        scan $character %c code
        if {$code==34 || $code==92} {append result [format %c 92] $character
        } elseif {$code<32} {append result [format {\u%04x} $code]
        } else {append result $character}
    }
    append result {"}
    return $result
}
proc ::GX::viewerDevelopmentEventJson {event} {
    if {[lsort [dict keys $event]] ne {component kind value}} {error {Native event requires kind/component/value}}
    foreach key {kind component} {set value [dict get $event $key];if {![string is integer -strict $value]||$value<0||$value>1000} {error {Native event integer is outside bounds}}}
    set value [uiFieldNormalize {type number} [dict get $event value]]
    return [format {{"kind":%s,"component":%s,"value":%s}} [dict get $event kind] [dict get $event component] $value]
}
proc ::GX::viewerDevelopmentStateJson {state} {
    if {[lsort [dict keys $state]] ne {counter values}||[llength [dict get $state values]]!=16} {error {Native state requires sixteen values and a counter}}
    set counter [dict get $state counter]
    if {![string is integer -strict $counter]||$counter<0||$counter>=4294967296} {error {Native counter is outside uint32}}
    set values {};foreach value [dict get $state values] {lappend values [uiFieldNormalize {type number} $value]}
    return [format {{"values":[%s],"counter":%s}} [join $values ,] $counter]
}
proc ::GX::viewerDevelopmentRequest {operation project callback {options {}}} {
    if {$operation ni {init validate build prepare run test export api inspect manual_asset save check_source facility_request builder debug debug_control debug_status gui_test workspace_upgrade_review}} {error {Unknown restricted development operation}}
    foreach key [dict keys $options] {if {$key ni {module_id event state file source request_json breakpoints target document debug_token}} {error {Unknown restricted development option}}}
    set project [file normalize $project]
    set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_viewer_development.py] $operation $project --tcl]
    if {[dict exists $options module_id]} {lappend command --module-id [dict get $options module_id]}
    if {[dict exists $options event]} {lappend command --event [viewerDevelopmentEventJson [dict get $options event]]}
    if {[dict exists $options state]} {lappend command --state [viewerDevelopmentStateJson [dict get $options state]]}
    if {[dict exists $options target]} {
        if {$operation ne {inspect} || [dict get $options target] ni {handlers.cpp project.json MANUAL.md design.gxtxt-viewer sdk_v1}} {error {Choose a fixed read-only Workspace source target}}
        lappend command --target [dict get $options target]
    }
    if {[dict exists $options document]} {
        set document [dict get $options document]
        set companion [expr {$document in {CPP_SUPPORT_CATALOG CPP_SUPPORT_CATALOG.md NUMERIC_EXPRESSION_OPERATIONS NUMERIC_EXPRESSION_OPERATIONS.md}}]
        if {$operation ne {api} || (!$companion && ![regexp {^[A-Z][A-Z0-9_]*_v[0-9]+(?:\.md)?$} $document])} {error {Choose a catalogued public API identity without a path}}
        lappend command --document [dict get $options document]
    }
    if {[dict exists $options debug_token]} {
        if {$operation ni {debug debug_status debug_control} || ![regexp {^[a-zA-Z0-9_-]{1,96}$} [dict get $options debug_token]]} {error {Debugger token must be bounded opaque request text}}
        lappend command --debug-token [dict get $options debug_token]
    }
    if {[dict exists $options breakpoints]} {
        if {$operation ne {debug}||[llength [dict get $options breakpoints]]>128} {error {Breakpoints belong to a bounded Debug start}}
        foreach line [dict get $options breakpoints] {if {![string is integer -strict $line]||$line<1||$line>100000} {error {Invalid physical breakpoint line}}}
        lappend command --breakpoints \[[join [dict get $options breakpoints] ,]\]
    }
    set payload {}
    if {$operation in {facility_request builder debug_control gui_test manual_asset workspace_upgrade_review}} {
        if {![dict exists $options request_json] || ([dict keys [dict remove $options request_json debug_token]] ne {}) || ([dict exists $options debug_token] && $operation ne {debug_control}) || [string bytelength [dict get $options request_json]]>[expr {$operation eq {workspace_upgrade_review}?8388608:65536}]} {error {A bounded typed JSON author request is required}}
        set payload [dict get $options request_json]
    } elseif {[dict exists $options request_json]} {error {Typed request payload belongs to Builder/facility request only}}
    if {$operation in {save check_source}} {
        set manual [expr {$operation eq {save} && [datasetPublicationV2DictDefault $options file handlers.cpp] eq {MANUAL.md}}]
        set limit [expr {$manual?262144:65536}]
        if {![dict exists $options source]||[string bytelength [dict get $options source]]>$limit} {error {Transfer requires bounded UTF-8: manual256KiB, C++/metadata64KiB}}
        set payload [dict get $options source]
        if {[dict exists $options file]} {
            if {[dict get $options file] ni {handlers.cpp project.json MANUAL.md}} {error {Unsupported source transfer target}}
            lappend command --file [dict get $options file]
        }
    } elseif {[dict exists $options source]||[dict exists $options file]} {error {Source payload is accepted only for source transfer}}
    return [scriptJobAsync $command $payload $callback [dict create timeout_ms [expr {$operation eq {debug}?930000:120000}] max_bytes [expr {$operation eq {builder}?67108864:4194304}] process_group 1 ui_lifetime 1 label {Restricted C++ development}]]
}
proc ::GX::_viewerDevelopmentSnapshot {project} {
    if {![file isdirectory $project]||[file type $project] eq {link}} {error {Developer project root changed}}
    set result {}
    foreach {name key} {handlers.cpp source_sha256 design.gxtxt-viewer design_sha256 project.json project_sha256} {
        set path [file join $project $name];file lstat $path stat
        if {$stat(type) ne {file}||$stat(nlink)!=1||$stat(size)>4194304} {error {Developer project source is no longer an ordinary bounded file}}
        dict set result $key [sha256File $path]
    }
    return $result
}
proc ::GX::viewerDevelopmentPreview {project {module viewer.development_workspace} {provider development_workspace} {context {}}} {
    return [_viewerDevelopmentOpenWindow $project $module $provider $context]
}
proc ::GX::_viewerDevelopmentOpenWindow {project module provider context {runtimeRoot {}}} {
    if {[dict size $::GX::ViewerDevelopment::windows]>=8} {error {Close an existing development Preview before opening another}}
    foreach key [dict keys $context] {if {$key ni {workspace_id workspace_name dataset_id tex_document_id em_document_id}} {error {Unsupported restricted Viewer open context}}}
    if {[dict exists $context workspace_name]} {
        if {[datasetPublicationV2DictDefault $context workspace_id {}] ne {new}} {error {A Workspace name belongs only to a new Workspace}}
        dict set context workspace_name [_workspaceName [dict get $context workspace_name]]
    }
    if {[dict exists $context dataset_id]} {sessionInspectionDataset [dict get $context dataset_id]}
    if {[dict exists $context em_document_id]} {
        _viewerGuiEMStamp [dict get $context em_document_id]
        set forms {}
        foreach c [dict get [viewerGuiDesignRead [file join $project design.gxtxt-viewer]] components] {
            if {[dict get $c type] eq {section} && [dict exists $c properties em_parameters]} {lappend forms [dict get $c id]}
        }
        if {[llength $forms]!=1} {error {Opening an EM model requires exactly one complete declared electromagnetic form}}
    }
    if {[dict exists $context tex_document_id]} {
        set articleId [dict get $context tex_document_id]
        if {![interactiveDocumentIdValid $articleId]} {error {Use a canonical current-Session TeX article identity}}
        set article [interactiveDocumentTeXRead $articleId]
        set articleProvider [_workspaceProvider [dict get $article provider_id]]
        if {[dict get $article module_id] ne $module || [datasetPublicationV2DictDefault $articleProvider viewer_provider {}] ne $provider} {
            error {TeX article belongs to another installed Viewer provider}
        }
    }
    set project [file normalize $project]
    set w .gxViewerDevPreview[incr ::GX::ViewerDevelopment::serial]
    toplevel $w;wm title $w {Opening Viewer…};wm geometry $w 760x460
    ttk::label $w.loading -text {Preparing the Viewer and checking its compiled interface…} -wraplength 650 -padding 16
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -side bottom -pady 8;pack $w.loading -fill both -expand 1
    dict set ::GX::ViewerDevelopment::windows $w [dict create project $project module $module provider $provider open_context $context state [dict create values [lrepeat 16 0.0] counter 0] busy {} generation 0 status VALIDATING]
    bind $w <Destroy> +[list ::GX::_viewerDevelopmentDisposed $w %W]
    if {$runtimeRoot eq {}} {
        # The Build owner persists and reuses the source/dependency-bound artifact.
        set request [viewerDevelopmentRequest prepare $project [list ::GX::_viewerDevelopmentPreviewValidated $w]]
    } else {
        set allocation [resourceManagementAllocate compiled_viewer_runtime [dict create category temporary lifetime viewer retention_seconds 0]]
        dict set ::GX::ViewerDevelopment::windows $w runtime_module_root $runtimeRoot
        dict set ::GX::ViewerDevelopment::windows $w runtime_allocation $allocation
        set request [_viewerDevelopmentCompiledRequest $w runtime_inspect [list ::GX::_viewerDevelopmentPreviewValidated $w]]
    }
    dict set ::GX::ViewerDevelopment::windows $w busy $request
    return $w
}
proc ::GX::_viewerDevelopmentPreviewValidated {w response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $w]||![winfo exists $w]} return
    dict set ::GX::ViewerDevelopment::windows $w busy {}
    set r [dict get $::GX::ViewerDevelopment::windows $w]
    set project [dict get $r project];set module [dict get $r module];set provider [dict get $r provider]
    if {![dict get $response ok]||[dict get $response result status] ni {PASS BUILT}} {
        dict set ::GX::ViewerDevelopment::windows $w status REJECTED
        dict set ::GX::ViewerDevelopment::windows $w last_result $response
        set summary [datasetPublicationV2DictDefault $response error {Source policy rejected this project}]
        if {[dict exists $response result diagnostics]&&[llength [dict get $response result diagnostics]]} {
            set diagnostic [lindex [dict get $response result diagnostics] 0]
            set summary "[dict get $diagnostic file]:[dict get $diagnostic line]:[dict get $diagnostic column] — [dict get $diagnostic message]"
        }
        $w.loading configure -text "Viewer could not open.\n\n[string range $summary 0 1400]\n\nFor a development project, inspect the Build/Validate report. For an installed Viewer, install a compatible precompiled package."
        return
    }
    set report [dict get $response result]
    if {[dict get $report status] eq {BUILT}} {set report [dict get $report validation]}
    foreach {name key} {handlers.cpp source_sha256 design.gxtxt-viewer design_sha256 project.json project_sha256} {
        if {[sha256File [file join $project $name]] ne [dict get $report $key]} {$w.loading configure -text {Project changed after validation; close and reopen the Demo.};dict set ::GX::ViewerDevelopment::windows $w status SOURCE_CHANGED;return}
    }
    dict set ::GX::ViewerDevelopment::windows $w validated_snapshot [_viewerDevelopmentSnapshot $project]
    dict set ::GX::ViewerDevelopment::windows $w workspace_callback_contract [dict get $report workspace_callback_contract_sha256]
    set design [viewerGuiDesignRead [file join $project design.gxtxt-viewer]]
    set handlers {}
    dict for {id contract} [dict get $design handlers] {dict set handlers $id [dict create command ::GX::viewerDevelopmentInvoke]}
    set context [dict merge [dict get $r open_context] [dict create command_catalog $module.cpp_[format %08x [zlib crc32 $project]]]]
    if {[dict exists $r runtime_module_root]} {
        dict set context workspace_open [list ::GX::viewerDevelopmentInstalledOpen $module $provider [dict get $r runtime_module_root]]
    } else {
        dict set context workspace_open [list ::GX::viewerDevelopmentProjectWorkspaceOpen $project $module $provider]
        dict set context workspace_provider [string map {. _ - _} $module]_${provider}_project_[format %08x [zlib crc32 $project]]_interface_state
    }
    set restoredState [dict get $r state]
    set workspace [datasetPublicationV2DictDefault $context workspace_id {}]
    if {$workspace ni {{} new}} {
        if {[catch {
            set saved [dict get [sessionWorkspaceGet $workspace] payload]
            if {![dict exists $saved domain_state restricted_cpp]} {error {Workspace lacks a restricted C++ source identity; it cannot silently restore unverified callbacks}}
            set savedCpp [dict get $saved domain_state restricted_cpp]
            if {[dict get $savedCpp snapshot] ne [dict get $::GX::ViewerDevelopment::windows $w validated_snapshot]} {
                set contract [datasetPublicationV2DictDefault $savedCpp callback_contract {}]
                if {![regexp {^[0-9a-f]{64}$} $contract] || $contract ne [dict get $::GX::ViewerDevelopment::windows $w workspace_callback_contract] || [dict get $savedCpp snapshot source_sha256] ne [dict get $report source_sha256]} {error {Workspace source/design/profile differs from this validated project; reopen its matching project or module version}}
            }
            set restoredState [dict get $savedCpp state]
            viewerDevelopmentStateJson $restoredState
        } reason]} {wm title $w {Workspace restoration refused};$w.loading configure -text "Workspace restoration refused: $reason";dict set ::GX::ViewerDevelopment::windows $w status SOURCE_CHANGED;return}
    }
    bind $w <Destroy> {};destroy $w
    if {[catch {viewerGuiDesignCompose $design $w $module $provider runtime $handlers $context} message]} {
        catch {destroy $w};toplevel $w;ttk::label $w.error -text "Interface construction failed: $message" -wraplength 650 -padding 12;pack $w.error
        dict set ::GX::ViewerDevelopment::windows $w status FAILED
        bind $w <Destroy> +[list ::GX::_viewerDevelopmentDisposed $w %W]
        return
    }
    dict set ::GX::ViewerDevelopment::windows $w state $restoredState
    set domain [viewerGuiDesignContextGet $w]
    dict set domain restricted_cpp [_viewerDevelopmentStateEnvelope $w $restoredState]
    viewerGuiDesignContextSet $w $domain
    bind $w <Destroy> +[list ::GX::_viewerDevelopmentDisposed $w %W]
    wm title $w [dict get $design title]
    documentationBrowserAttachViewerHelp $module $provider $w
    viewerDevelopmentInvoke $w __open__
}
proc ::GX::viewerDevelopmentInvoke {window action} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]||![viewerGuiDesignGuard $window]} {return {status rejected message {Development Viewer lifetime ended}}}
    set r [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict get $r busy] ne {}} {return {status busy message {Wait or cancel the current native event}}}
    if {[dict get $r status] eq {RUNNING}} {return {status busy message {Wait for the current native event's trusted host operations}}}
    if {![dict exists $r validated_snapshot]||[catch {_viewerDevelopmentSnapshot [dict get $r project]} current]||$current ne [dict get $r validated_snapshot]} {
        dict set ::GX::ViewerDevelopment::windows $window status SOURCE_CHANGED
        [dict get $::GX::ViewerGui::instances $window slots status] configure -text {Project source/design/facilities changed; close and reopen Demo before executing another event.}
        return {status SOURCE_CHANGED message {Reopen Demo for the current project revision}}
    }
    set domain [viewerGuiDesignContextGet $window]
    if {[dict exists $domain restricted_cpp]} {
        if {[dict get $domain restricted_cpp snapshot] ne [dict get $r validated_snapshot]} {return {status SOURCE_CHANGED message {Saved native state belongs to another source revision}}}
        set restored [dict get $domain restricted_cpp state];viewerDevelopmentStateJson $restored
        dict set r state $restored
    } else {dict set r state [dict create values [lrepeat 16 0.0] counter 0]}
    set index 0;set component 0;set changed {};set actionValue 0.0
    set kind [expr {$action eq {__open__} ? 0 : 1}]
    foreach item [dict get $::GX::ViewerGui::instances $window design components] {
        incr index
        if {[dict exists $item properties action]&&[dict get $item properties action] eq $action} {set component $index;set actionValue [datasetPublicationV2DictDefault [dict get $item properties] event_value 0.0];break}
        if {[dict exists $item properties change_action]&&[dict get $item properties change_action] eq $action} {set component $index;set kind 2;set changed [dict get $item id];break}
    }
    set value $actionValue
    set values [viewerGuiDesignValues $window]
    if {$changed ne {}} {
        # Event.value is a scalar, not a canonical ID/string transport. Typed
        # Host operations inspect their declared selection through its owner.
        set selected [dict get $values $changed]
        if {[string is double -strict $selected]} {set value [uiFieldNormalize {type number} $selected]} else {set value 0.0}
    } elseif {[dict exists $values temperature]} {set value [uiFieldNormalize {type number} [dict get $values temperature]]}
    dict incr r generation;set generation [dict get $r generation]
    dict set ::GX::ViewerDevelopment::windows $window $r
    set started [clock microseconds]
    if {[catch {
        set service [_viewerDevelopmentCompiledService $window]
        set payload [format {{"event":%s,"state":%s}} [viewerDevelopmentEventJson [dict create kind $kind component $component value $value]] [viewerDevelopmentStateJson [dict get $r state]]]
        set response [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $service $payload]]]
        if {[catch {dict get $response ok}]} {error {Compiled Viewer returned an invalid typed response}}
        # Apply the real compiled event before dispatching the next native input.
        # Long-running scientific work remains an operation of its existing owner.
        dict set ::GX::ViewerDevelopment::windows $window status RUNNING
        _viewerDevelopmentRan $window $generation $response
    } problem]} {
        if {[dict exists $::GX::ViewerDevelopment::windows $window]} {
            if {[dict exists $::GX::ViewerDevelopment::windows $window compiled_service]} {scriptJobRequestCancel [dict get $::GX::ViewerDevelopment::windows $window compiled_service] closed}
            dict set ::GX::ViewerDevelopment::windows $window status FAILED
            dict set ::GX::ViewerDevelopment::windows $window last_result [dict create ok 0 error $problem]
            [dict get $::GX::ViewerGui::instances $window slots status] configure -text $problem
        }
        return [dict create status failed message $problem]
    }
    set reply [dict create status [expr {[dict exists $::GX::ViewerDevelopment::windows $window] && [dict get $::GX::ViewerDevelopment::windows $window status] eq {COMPLETED} ? {completed} : {failed}}] elapsed_us [expr {[clock microseconds]-$started}]]
    if {[dict get $reply status] eq {failed} && [dict exists $::GX::ViewerDevelopment::windows $window last_result]} {
        set last [dict get $::GX::ViewerDevelopment::windows $window last_result]
        foreach key {host_error error} {
            if {[dict exists $last $key] && [dict get $last $key] ne {}} {dict set reply message [dict get $last $key];break}
        }
    }
    return $reply
}
proc ::GX::_viewerDevelopmentRan {window generation response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]||![winfo exists $window]||[dict get $::GX::ViewerDevelopment::windows $window generation]!=$generation} return
    dict set ::GX::ViewerDevelopment::windows $window busy {}
    set status FAILED
    if {[dict get $response ok]} {
        set result [dict get $response result];set status [dict get $result status]
        if {$status eq {COMPLETED}} {
            set project [dict get $::GX::ViewerDevelopment::windows $window project]
            set expected [dict get $::GX::ViewerDevelopment::windows $window validated_snapshot]
            set observed {};foreach key {source_sha256 design_sha256 project_sha256} {dict set observed $key [dict get $result $key]}
            if {[catch {_viewerDevelopmentSnapshot $project} current]||$current ne $expected||$observed ne $expected} {set status SOURCE_CHANGED} else {
                if {[catch {
                    foreach operation [dict get $result operations] {
                        set component [dict get $operation component];set value [dict get $operation value]
                        switch [dict get $operation operation] {
                            text_set - number_set - flag_set {viewerGuiDesignValueSet $window $component $value}
                            demo_bind {viewerGuiDesignTemporarySceneSet $window $component [dict get {0 native2d 1 plot 2 native3d} [expr {int($value)}]]}
                            diagram_open {if {![dict exists $::GX::ViewerGui::instances $window bindings $component]} {viewerGuiDesignDiagramSet $window $component}}
                            diagram_tool {viewerGuiDesignDiagramCommand $window $component tool $value}
                            diagram_command {viewerGuiDesignDiagramCommand $window $component $value}
                            scientific_discover {viewerGuiDesignScientificDiscover $window $component}
                            scientific_prepare {viewerGuiDesignScientificPrepare $window $value $component}
                            scientific_submit {viewerGuiDesignScientificSubmit $window $component}
                            scientific_status {viewerGuiDesignScientificStatus $window $component}
                            scientific_cancel {viewerGuiDesignScientificCancel $window $component}
                            scientific_reconnect {viewerGuiDesignScientificReconnect $window $component}
                            scientific_log {viewerGuiDesignScientificLog $window $component}
                            scientific_import {viewerGuiDesignScientificImport $window $component $value}
                            plot_discover {viewerGuiDesignPlotDiscover $window $component}
                            plot_bind {viewerGuiDesignPlotBind $window $value $component}
                            document_bind {viewerGuiDesignDocumentBind $window $component $value}
                            raster_bind {viewerGuiDesignRasterBind $window $component $value}
                            raster_tool {viewerGuiDesignRasterTool $window $component $value}
                            raster_command {viewerGuiDesignRasterCommand $window $component $value}
                            tex_command {viewerGuiDesignTeXCommand $window $component $value}
                            em_command {viewerGuiDesignEMCommand $window $component $value}
                            workbench_command {viewerGuiDesignWorkbenchCommand $window $component $value}
                            catalog_refresh {viewerGuiDesignCatalogRefresh $window $component}
                            catalog_inspect {viewerGuiDesignCatalogInspect $window $component}
                            catalog_action {viewerGuiDesignCatalogAction $window $component $value}
                            numeric_discover {viewerGuiDesignNumericDiscover $window $component}
                            numeric_evaluate {viewerGuiDesignNumericEvaluate $window $component}
                            numeric_statistics {viewerGuiDesignNumericStatistics $window $component}
                            numeric_compare {viewerGuiDesignNumericCompare $window $component}
                            numeric_publish {viewerGuiDesignNumericPublish $window $component $value}
                            default {error {Unknown admitted SDK presentation operation}}
                        }
                    }
                    dict set ::GX::ViewerDevelopment::windows $window state [dict get $result state]
                    set domain [viewerGuiDesignContextGet $window]
                    dict set domain restricted_cpp [_viewerDevelopmentStateEnvelope $window [dict get $result state]]
                    viewerGuiDesignContextSet $window $domain
                } problem]} {set status FAILED;dict set response host_error $problem}
            }
        }
    }
    dict set ::GX::ViewerDevelopment::windows $window status $status
    dict set ::GX::ViewerDevelopment::windows $window last_result $response
    set message [expr {$status eq {COMPLETED} ? {Ready} : $status}]
    if {[dict exists $response host_error]} {append message ": [dict get $response host_error]"}
    [dict get $::GX::ViewerGui::instances $window slots status] configure -text $message
    viewerGuiTraceEmit $window window cpp_event [dict create status $status author restricted_cpp]
    # Native service actions finish after the initiating command returned.
    # Refresh shared command state from their actual resulting associations,
    # including a newly submitted/reconnected scientific Job.
    viewerGuiActionsRefresh $window
}
proc ::GX::_viewerDevelopmentStateEnvelope {window state} {
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    set envelope [dict create snapshot [dict get $record validated_snapshot] state $state]
    if {[dict exists $record workspace_callback_contract]} {dict set envelope callback_contract [dict get $record workspace_callback_contract]}
    return $envelope
}
proc ::GX::_viewerDevelopmentDisposed {window actual} {
    if {$window ne $actual||![dict exists $::GX::ViewerDevelopment::windows $window]} return
    set request [dict get $::GX::ViewerDevelopment::windows $window busy]
    if {$request ne {}} {scriptJobRequestCancel $request closed}
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict exists $record compiled_service]} {scriptJobRequestCancel [dict get $record compiled_service] closed}
    dict unset ::GX::ViewerDevelopment::windows $window
    if {[dict exists $record runtime_allocation]} {
        # Existing Resource owner retains diagnostics while the ordinary request
        # cancellation drains; no installed source or binary is ever removed.
        resourceManagementRelease [dict get $record runtime_allocation id] retained_diagnostic 3600
    }
    if {[dict exists $record runtime_project]} {after 100 [list ::GX::_viewerDevelopmentRuntimeCleanup [dict get $record project] $request 0]}
}
proc ::GX::_viewerDevelopmentRuntimeCleanup {project request attempt} {
    if {$request ne {}&&[dict exists $::GX::scriptJobRequests $request]} {
        if {$attempt<100} {after 100 [list ::GX::_viewerDevelopmentRuntimeCleanup $project $request [expr {$attempt+1}]]}
        return
    }
    set parent [file normalize [file join [configurationCacheDirectory] restricted_viewer_runtime]]
    set project [file normalize $project]
    if {[file dirname $project] ne $parent||![file isdirectory $project]||[file type $project] eq {link}} {return}
    # Only an explicitly recorded installed-source runtime copy reaches this owner.
    file delete -force -- $project
}
proc ::GX::viewerDevelopmentInstalledBindings {module provider root} {
    set design [viewerGuiDesignRead [file join $root gui design.tcldict]]
    set result {}
    dict for {id contract} [dict get $design handlers] {dict set result $id [dict create command ::GX::viewerDevelopmentInvoke]}
    return $result
}
proc ::GX::viewerDevelopmentProjectWorkspaceOpen {project module provider context} {
    if {$context ne {} && ![catch {sessionWorkspaceGet $context} item]} {set context [dict create workspace_id [dict get $item workspace_id]]}
    return [viewerDevelopmentPreview $project $module $provider $context]
}
proc ::GX::viewerDevelopmentInstalledOpen {module provider root {context {}}} {
    if {$context ne {} && ![catch {sessionWorkspaceGet $context} item]} {set context [dict create workspace_id [dict get $item workspace_id]]}
    if {[file normalize [file dirname [moduleField $module descriptor]]] ne [file normalize $root]} {error {Restricted Viewer package must be registered through the normal Plugin Manager}}
    if {![file isfile [file join $root native viewer.so]]} {error {Installed C++ Viewer has no native/viewer.so. Install a compatible precompiled package; runtime never compiles it.}}
    return [_viewerDevelopmentOpenWindow [file join $root source] $module $provider $context $root]
}
proc ::GX::_viewerDevelopmentCompiledRequest {window operation callback {options {}}} {
    if {$operation ni {runtime_inspect runtime_run}} {error {Unknown compiled Viewer runtime operation}}
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_viewer_development.py] $operation [dict get $record runtime_module_root] --runtime-work [dict get $record runtime_allocation path] --tcl]
    if {[dict exists $options event]} {lappend command --event [viewerDevelopmentEventJson [dict get $options event]]}
    if {[dict exists $options state]} {lappend command --state [viewerDevelopmentStateJson [dict get $options state]]}
    return [scriptJobAsync $command {} $callback [dict create timeout_ms 120000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Compiled C++ Viewer}]]
}
proc ::GX::_viewerDevelopmentCompiledService {window} {
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict exists $record compiled_service]} {
        set request [dict get $record compiled_service]
        if {![dict exists $::GX::scriptJobRequests $request] || [dict get $::GX::scriptJobRequests $request cancelled] ne {}} {error {Compiled Viewer worker ended; reopen this Viewer}}
        return $request
    }
    if {[dict exists $record runtime_module_root]} {
        set root [dict get $record runtime_module_root];set work [dict get $record runtime_allocation path]
    } else {set root [dict get $record project];set work $root}
    set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_viewer_development.py] runtime_serve $root --runtime-work $work]
    set request [scriptJobAsync $command {} [list ::GX::_viewerDevelopmentCompiledEnded $window] [dict create duplex 1 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Compiled Viewer lifetime}]]
    dict set ::GX::ViewerDevelopment::windows $window compiled_service $request
    set ready [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $request {} 5000]]]
    if {![dict get $ready ok] || [dict get $ready result status] ne {READY}} {scriptJobRequestCancel $request closed;error {Compiled Viewer worker could not load its precompiled binary}}
    dict set ::GX::ViewerDevelopment::windows $window compiled_service_receipt [dict get $ready result]
    return $request
}
proc ::GX::_viewerDevelopmentCompiledEnded {window response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window]} return
    dict set ::GX::ViewerDevelopment::windows $window status FAILED
    dict set ::GX::ViewerDevelopment::windows $window last_result $response
    if {[dict exists $::GX::ViewerGui::instances $window slots status]} {[dict get $::GX::ViewerGui::instances $window slots status] configure -text {Compiled Viewer worker ended; reopen this Viewer.}}
}
proc ::GX::viewerDevelopmentPackageVerify {root} {
    set allocation [resourceManagementAllocate compiled_viewer_admission [dict create category temporary lifetime operation retention_seconds 0]]
    set token admission_[incr ::GX::ViewerDevelopment::serial]
    set variable ::GX::ViewerDevelopment::packageAdmission($token)
    set request {}
    try {
        set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_viewer_development.py] runtime_inspect [file normalize $root] --runtime-work [dict get $allocation path] --tcl]
        set request [scriptJobAsync $command {} [list ::GX::_viewerDevelopmentPackageVerified $variable] [dict create timeout_ms 30000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Precompiled Viewer admission}]]
        vwait $variable
        set response [set $variable]
        if {[catch {dict get $response ok} ok]} {error "Precompiled Viewer admission failed: $response"}
        if {!$ok} {error [dict get $response error]}
        if {[dict get $response result status] ne {PASS}} {error {Precompiled Viewer admission did not complete}}
        return [dict get $response result]
    } finally {
        if {$request ne {} && [dict exists $::GX::scriptJobRequests $request]} {scriptJobRequestCancel $request closed}
        catch {unset $variable}
        resourceManagementRelease [dict get $allocation id] retained_diagnostic 600
    }
}
proc ::GX::_viewerDevelopmentPackageVerified {variable response} {set $variable $response}
