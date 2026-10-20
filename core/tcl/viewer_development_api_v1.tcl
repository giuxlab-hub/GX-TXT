# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted host for the common restricted author backend; no authored Tcl is evaluated.
namespace eval ::GX::ViewerDevelopment {variable windows {};variable serial 0}
source [file join [file dirname [info script]] viewer_development_gui_test_v1.tcl]
source [file join [file dirname [info script]] viewer_development_workspace_upgrade_v1.tcl]
proc ::GX::viewerDevelopmentApiInfo {} {
    return [dict create api_id VIEWER_DEVELOPMENT_API_v1 api_version 1 language cpp python_authoring 0 profiles {synthetic_view_v1 numeric_view_v1 document_view_v1 scientific_view_v1} operations {request inspect save check_source facility_request builder manual_asset debug debug_status debug_control preview invoke close installed_open installed_bindings workspace_upgrade_review workspace_review workspace_upgrade gui_test_attach gui_test_detach gui_test} backend core/python/gxtxt_viewer_development.py source_surface SOURCE_SURFACE_API_v1 gui_owner VIEWER_GUI_HOST_API_v1 renderer_owners {NATIVE2D_VIEWPORT_HOST_v1 NATIVE2D_TEMPORARY_DISPLAY_API_v1 NATIVE_PLOT_DISPLAY_API_v1 NATIVE_3D_GUI_HOST_API_v2} publication 0 install {candidate export; normal Plugin Manager promotion}]
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
    if {$operation ni {init validate build run test export api inspect manual_asset save check_source facility_request builder debug debug_control debug_status gui_test workspace_upgrade_review}} {error {Unknown restricted development operation}}
    foreach key [dict keys $options] {if {$key ni {module_id event state file source request_json breakpoints target document debug_token compile_token}} {error {Unknown restricted development option}}}
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
        if {$operation ne {api} || ![regexp {^[A-Z][A-Z0-9_]*_v[0-9]+(?:\.md)?$} [dict get $options document]]} {error {Choose a catalogued public API identity without a path}}
        lappend command --document [dict get $options document]
    }
    if {[dict exists $options compile_token]} {
        set token [dict get $options compile_token]
        if {$operation ne {run} || ![regexp {^[a-zA-Z0-9_-]{1,96}$} $token]} {error {Invalid GUI compile-notice token}}
        lappend command --compile-token $token
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
    if {[dict size $::GX::ViewerDevelopment::windows]>=8} {error {Close an existing development Preview before opening another}}
    foreach key [dict keys $context] {if {$key ne {workspace_id}} {error {Unsupported restricted Viewer open context}}}
    set project [file normalize $project]
    set w .gxViewerDevPreview[incr ::GX::ViewerDevelopment::serial]
    toplevel $w;wm title $w {C++ Demo · validating project};wm geometry $w 760x460
    ttk::label $w.loading -text {Validating C++ policy and Builder design before constructing the interface…} -wraplength 650 -padding 16
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -side bottom -pady 8;pack $w.loading -fill both -expand 1
    dict set ::GX::ViewerDevelopment::windows $w [dict create project $project module $module provider $provider open_context $context state [dict create values [lrepeat 16 0.0] counter 0] busy {} generation 0 status VALIDATING]
    bind $w <Destroy> +[list ::GX::_viewerDevelopmentDisposed $w %W]
    set request [viewerDevelopmentRequest validate $project [list ::GX::_viewerDevelopmentPreviewValidated $w]]
    dict set ::GX::ViewerDevelopment::windows $w busy $request
    return $w
}
proc ::GX::_viewerDevelopmentPreviewValidated {w response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $w]||![winfo exists $w]} return
    dict set ::GX::ViewerDevelopment::windows $w busy {}
    set r [dict get $::GX::ViewerDevelopment::windows $w]
    set project [dict get $r project];set module [dict get $r module];set provider [dict get $r provider]
    if {![dict get $response ok]||[dict get $response result status] ne {PASS}} {
        dict set ::GX::ViewerDevelopment::windows $w status REJECTED
        dict set ::GX::ViewerDevelopment::windows $w last_result $response
        set summary [datasetPublicationV2DictDefault $response error {Source policy rejected this project}]
        if {[dict exists $response result diagnostics]&&[llength [dict get $response result diagnostics]]} {
            set diagnostic [lindex [dict get $response result diagnostics] 0]
            set summary "[dict get $diagnostic file]:[dict get $diagnostic line]:[dict get $diagnostic column] — [dict get $diagnostic message]"
        }
        $w.loading configure -text "Preview refused before interface construction.\n\n[string range $summary 0 1400]\n\nUse Validate in the Development Workspace for the complete diagnostic report. No author code was generated or executed."
        return
    }
    set report [dict get $response result]
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
# Per-event, nonmodal Tk notice. No Script Job stderr/stdout changes.
proc ::GX::_viewerDevelopmentCompilePoll {window token} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window]} return
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {![dict exists $record compile_token] || [dict get $record compile_token] ne $token} return
    set marker [file join [dict get $record project] derived tmp viewer-compiling-${token}.marker]
    if {[file isfile $marker] && ![dict exists $record compile_notice_shown]} {
        dict set ::GX::ViewerDevelopment::windows $window compile_notice_shown 1
        set notice ${window}.cppBuildNotice
        if {![winfo exists $notice]} {
            toplevel $notice
            wm title $notice {GX-TXT - C++ compilation}
            wm transient $notice $window
            wm resizable $notice 0 0
            ttk::label $notice.message -text {Compilazione C++ del viewer in corso...} -padding {22 18}
            pack $notice.message -fill both -expand 1
        }
    }
    after 100 [list ::GX::_viewerDevelopmentCompilePoll $window $token]
}
proc ::GX::_viewerDevelopmentCompileFinish {window} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]} return
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict exists $record compile_token]} {
        set token [dict get $record compile_token]
        set marker [file join [dict get $record project] derived tmp viewer-compiling-${token}.marker]
        catch {file delete -- $marker}
        dict unset ::GX::ViewerDevelopment::windows $window compile_token
    }
    if {[dict exists $record compile_notice_shown]} {
        dict unset ::GX::ViewerDevelopment::windows $window compile_notice_shown
    }
    if {[winfo exists ${window}.cppBuildNotice]} {destroy ${window}.cppBuildNotice}
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
    if {$changed ne {}} {set value [uiFieldNormalize {type number} [dict get $values $changed]]} elseif {[dict exists $values temperature]} {set value [uiFieldNormalize {type number} [dict get $values temperature]]}
    dict incr r generation;set generation [dict get $r generation]
    set token [format {compile_%d_%d} [pid] [clock microseconds]]
    set request [viewerDevelopmentRequest run [dict get $r project] [list ::GX::_viewerDevelopmentRan $window $generation] [dict create event [dict create kind $kind component $component value $value] state [dict get $r state] compile_token $token]]
    dict set r busy $request;dict set r status RUNNING;dict set r compile_token $token
    dict set ::GX::ViewerDevelopment::windows $window $r
    [dict get $::GX::ViewerGui::instances $window slots status] configure -text {C++ Demo · native event running in its bounded worker…}
    after 100 [list ::GX::_viewerDevelopmentCompilePoll $window $token]
    return [dict create status submitted request $request]
}
proc ::GX::_viewerDevelopmentRan {window generation response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]||![winfo exists $window]||[dict get $::GX::ViewerDevelopment::windows $window generation]!=$generation} return
    ::GX::_viewerDevelopmentCompileFinish $window
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
    set compileDetail {}
    if {$status eq {COMPLETED} && [dict get $response ok]} {
        set result [dict get $response result]
        if {[dict exists $result compile_cache_hit]} {
            set compileDetail [expr {[dict get $result compile_cache_hit] ? { (C++ binary reused)} : { (C++ compiled)}}]
        }
    }
    [dict get $::GX::ViewerGui::instances $window slots status] configure -text "Restricted Viewer · $status$compileDetail"
    viewerGuiTraceEmit $window window cpp_event [dict create status $status author restricted_cpp]
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
    ::GX::_viewerDevelopmentCompileFinish $window
    if {$request ne {}} {scriptJobRequestCancel $request closed}
    set record [dict get $::GX::ViewerDevelopment::windows $window]
    dict unset ::GX::ViewerDevelopment::windows $window
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
    set parent [file join [configurationCacheDirectory] restricted_viewer_runtime]
    file mkdir $parent
    set project [file join $parent [string map {. _} $module]_[clock microseconds]]
    file mkdir $project
    foreach name {project.json handlers.cpp design.gxtxt-viewer} {
        set path [file join $root source $name]
        if {![file isfile $path]||[file type $path] eq {link}||[file size $path]>4194304} {error {Installed restricted source is unavailable or unbounded}}
        set f [open $path rb];try {set bytes [read $f 4194305]} finally {close $f}
        resourceLifecycleWriteBytes [file join $project $name] $bytes
    }
    set window [viewerDevelopmentPreview $project $module $provider $context]
    dict set ::GX::ViewerDevelopment::windows $window runtime_project 1
    dict set ::GX::ViewerDevelopment::windows $window runtime_module_root $root
    return $window
}
