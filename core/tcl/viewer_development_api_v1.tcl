# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted host for the common restricted author backend; no authored Tcl is evaluated.
namespace eval ::GX::ViewerDevelopment {variable windows {};variable serial 0}
source [file join [file dirname [info script]] viewer_development_api_browser_v1.tcl]
source [file join [file dirname [info script]] viewer_development_gui_test_v1.tcl]
source [file join [file dirname [info script]] viewer_development_workspace_upgrade_v1.tcl]
source [file join [file dirname [info script]] viewer_development_preview_v1.tcl]
source [file join [file dirname [info script]] viewer_dataset_producer_v1.tcl]
source [file join [file dirname [info script]] script_library_host_v1.tcl]
source [file join [file dirname [info script]] viewer_native_clients_v1.tcl]
source [file join [file dirname [info script]] viewer_development_project_workspace_v1.tcl]
source [file join [file dirname [info script]] viewer_development_acquisition_test_v1.tcl]
proc ::GX::viewerDevelopmentApiInfo {} {
    return [dict create api_id VIEWER_DEVELOPMENT_API_v1 api_version 1 language cpp python_authoring 0 acquisition_project_api [dict create schema gxtxt.acquisition_development_project.v1 description_schema gxtxt.development_project_description.v1 edit_schema gxtxt.development_project_edit.v1 operations {project_init describe read add remove rename save_all profile_put profile_remove metadata_set} build_operations {validate build test export runtime_inspect} sdk_header core/development/sdk/gxtxt_acquisition_sdk_v1.hpp native_protocol gxtxt.native_acquisition_request.v1 config_field_types {string integer number double boolean choice} config_field_limit 32 config_owner MODULE_API_v1 contract_declaration_fields {input_contracts provided_contracts} contract_declaration_owner CONTRACT_REGISTRY_API_v1 source_note_local_languages {cpp python} source_note_operations {note_read note_identity note_write note_asset_read} project_import source_only native_runtime [expr {[llength [info commands ::GX::acquisitionHandlerNativeInvoke]]>0}] project_test_available [expr {[llength [info commands ::GX::viewerDevelopmentAcquisitionTestChoose]]>0}] helper_runtime [expr {[llength [info commands ::GX::acquisitionHandlerNativeHelperAvailable]]>0 && [acquisitionHandlerNativeHelperAvailable]}]] profiles {synthetic_view_v1 numeric_view_v1 document_view_v1 scientific_view_v1} operations {request inspect project_init project_files import_project save check_source facility_request builder manual_asset debug debug_status debug_control preview invoke close installed_open installed_test_open installed_bindings workspace_upgrade_review workspace_review workspace_upgrade gui_test_attach gui_test_detach gui_test maintenance_modules maintenance_create maintenance_init maintenance_inspect maintenance_save maintenance_validate maintenance_export} managed_preview_host_operations {viewerDevelopmentPreviewTabs viewerDevelopmentPreviewMount viewerDevelopmentPreviewDispose} managed_preview_runtime distributed_cpp_worker backend core/python/gxtxt_viewer_development.py source_surface SOURCE_SURFACE_API_v1 gui_owner VIEWER_GUI_HOST_API_v1 renderer_owners {NATIVE2D_VIEWPORT_HOST_v1 NATIVE2D_TEMPORARY_DISPLAY_API_v1 NATIVE_PLOT_DISPLAY_API_v1 NATIVE_3D_GUI_HOST_API_v2} publication 0 dataset_producer_api [dict create owner DATASET_GROUP_PRODUCER_API_v1 sdk_methods {dataset_group_review dataset_group_create dataset_publish_batch dataset_producer_result} request_bytes_max 49152 result_bytes_max 1048576 capabilities {DATASET_GROUP_API_v1 DATASET_PUBLICATION_API_v2} result_scope transient_next_event] install {candidate export; normal Plugin Manager promotion}]
}
proc ::GX::viewerDevelopmentMaintenanceModules {} {
    set result {}
    foreach {module provider backend} {viewer.curve_workbench curve_workbench curve_workbench_tk viewer.replicate_curve_analysis replicate_consensus replicate_consensus_tk viewer.interface_builder interface_builder viewer_interface_builder_tk} {
        if {[catch {set definition [viewerProviderDefinition $module $provider 1]}]} continue
        set expected [file normalize [file join $::GX::scriptDir plugins modules $module module.ini]]
        if {![info exists ::GX::moduleCatalog($module,descriptor)] || [file normalize $::GX::moduleCatalog($module,descriptor)] ne $expected || [dict get $definition backend] ne $backend} continue
        dict set result $module [dict create provider $provider name [dict get $definition name] backend $backend]
    }
    return $result
}
proc ::GX::viewerDevelopmentMaintenanceCreate {module provider project callback} {
    set approved [viewerDevelopmentMaintenanceModules]
    if {![dict exists $approved $module] || [dict get $approved $module provider] ne $provider} {error {Select an installed registered Viewer admitted by the CORE maintenance policy}}
    set payload [format {{"module":%s,"provider":%s}} [viewerDevelopmentJsonString $module] [viewerDevelopmentJsonString $provider]]
    return [viewerDevelopmentRequest maintenance_init $project $callback [dict create request_json $payload]]
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
    set noteRequest 0
    if {$operation ni {init project_init import_project validate build prepare run test export api inspect project_files manual_asset save check_source facility_request builder debug debug_control debug_status gui_test workspace_upgrade_review maintenance_init maintenance_inspect maintenance_save maintenance_validate maintenance_export}} {error {Unknown restricted development operation}}
    foreach key [dict keys $options] {if {$key ni {module_id source_package event state file source request_json breakpoints target document debug_token}} {error {Unknown restricted development option}}}
    set project [file normalize $project]
    set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_viewer_development.py] $operation $project --tcl]
    if {[dict exists $options module_id]} {lappend command --module-id [dict get $options module_id]}
    if {[dict exists $options source_package]} {
        if {$operation ne {import_project}} {error {A source package belongs only to Import project}}
        lappend command --package [dict get $options source_package]
    }
    if {[dict exists $options event]} {lappend command --event [viewerDevelopmentEventJson [dict get $options event]]}
    if {[dict exists $options state]} {lappend command --state [viewerDevelopmentStateJson [dict get $options state]]}
    if {[dict exists $options target]} {
        if {$operation ne {inspect} || ([dict get $options target] ni {project.json MANUAL.md design.gxtxt-viewer sdk_v1} && [dict get $options target] ni [viewerDevelopmentSourceFiles $project])} {error {Choose a declared Workspace source target}}
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
        set points {}
        foreach point [dict get $options breakpoints] {
            if {[string is integer -strict $point]} {set point [dict create file handlers.cpp line $point]}
            if {[lsort [dict keys $point]] ne {file line} || [dict get $point file] ni [viewerDevelopmentSourceFiles $project]} {error {Breakpoint file is not declared}}
            set line [dict get $point line]
            if {![string is integer -strict $line]||$line<1||$line>100000} {error {Invalid physical breakpoint line}}
            lappend points [format {{"file":%s,"line":%s}} [viewerDevelopmentJsonString [dict get $point file]] $line]
        }
        lappend command --breakpoints \[[join $points ,]\]
    }
    set payload {}
    if {$operation in {project_init project_files facility_request builder debug_control gui_test manual_asset workspace_upgrade_review maintenance_init maintenance_inspect maintenance_save maintenance_validate maintenance_export}} {
        if {$operation eq {project_files} && [dict exists $options request_json]} {
            set raw [dict get $options request_json]
            if {[string bytelength $raw]>8388608} {error {Project note request exceeds8MiB}}
            lassign [nativeWorkspaceJsonDecode $raw] kind fields
            if {$kind ne {object}} {error {Project request must be a JSON object}}
            if {[dict exists $fields operation]} {
                lassign [dict get $fields operation] type actual
                if {$type ne {text}} {error {Project operation must be text}}
                set noteRequest [expr {$actual in {note_read note_identity note_write note_asset_read}}]
            }
        }
        set requestLimit [expr {[string match maintenance_* $operation]?1048576:($operation eq {workspace_upgrade_review}?8388608:($operation eq {project_files}?($noteRequest?8388608:2097152):65536))}]
        if {![dict exists $options request_json] || ([dict keys [dict remove $options request_json debug_token]] ne {}) || ([dict exists $options debug_token] && $operation ne {debug_control}) || [string bytelength [dict get $options request_json]]>$requestLimit} {error {A bounded typed JSON author request is required}}
        set payload [dict get $options request_json]
    } elseif {$operation eq {test} && [dict exists $options request_json]} {
        set payload [dict get $options request_json]
        if {[string bytelength $payload]>65536} {error {Acquisition Test selection exceeds64KiB}}
        lassign [nativeWorkspaceJsonDecode $payload] kind fields
        if {$kind ne {object} || ![dict exists $fields schema] || [dict get $fields schema] ne {text gxtxt.acquisition_project_test.v1}} {error {Explicit Acquisition project Test request required}}
    } elseif {[dict exists $options request_json]} {error {Typed request payload belongs to Builder/facility request only}}
    if {$operation in {save check_source}} {
        set manual [expr {$operation eq {save} && [datasetPublicationV2DictDefault $options file handlers.cpp] eq {MANUAL.md}}]
        set limit [expr {$manual?262144:65536}]
        if {![dict exists $options source]||[string bytelength [dict get $options source]]>$limit} {error {Transfer requires bounded UTF-8: manual256KiB, C++/metadata64KiB}}
        set payload [dict get $options source]
        if {[dict exists $options file]} {
            if {[dict get $options file] ni {project.json MANUAL.md} && [dict get $options file] ni [viewerDevelopmentSourceFiles $project]} {error {Unsupported source transfer target}}
            lappend command --file [dict get $options file]
        }
    } elseif {[dict exists $options source]||[dict exists $options file]} {error {Source payload is accepted only for source transfer}}
    return [scriptJobAsync $command $payload $callback [dict create timeout_ms [expr {$operation eq {debug}?930000:120000}] max_bytes [expr {$operation eq {builder}?67108864:($noteRequest?12582912:4194304)}] process_group 1 ui_lifetime 1 label {Restricted C++ development}]]
}
proc ::GX::viewerDevelopmentSourceFiles {project} {
    set path [file join $project project.json]
    if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>65536} {error {Project metadata is unavailable}}
    set stream [open $path rb];try {set raw [read $stream 65537]} finally {close $stream}
    set meta [nativeWorkspaceDecode [nativeWorkspaceJsonDecode [encoding convertfrom utf-8 $raw]]]
    set names [datasetPublicationV2DictDefault $meta source_files {handlers.cpp}]
    if {[llength $names]<1 || [llength $names]>32 || [lindex $names 0] ne {handlers.cpp} || [llength [lsort -unique $names]]!=[llength $names]} {error {Invalid project source manifest}}
    foreach name $names {
        if {$name ne {handlers.cpp} && ![regexp {^(src/[A-Za-z0-9_./-]+\.cpp|include/[A-Za-z0-9_./-]+\.hpp)$} $name]} {error {Invalid project source name}}
        foreach part [split $name /] {if {$part in {{} . ..}} {error {Project path traversal is forbidden}}}
    }
    if {[datasetPublicationV2DictDefault $meta schema {}] eq {gxtxt.acquisition_development_project.v1}} {
        set helpers [dict get $meta helpers]
        if {[llength $helpers]>32} {error {Acquisition helper roster exceeds 32 files}}
        foreach helper $helpers {
            set language [dict get $helper language];set name [dict get $helper path]
            if {$language ni {Tcl Python} || [dict get $helper role] ne {runtime_helper} || ![regexp {^helpers/[A-Za-z0-9_./-]+\.(tcl|py)$} $name]} {error {Invalid typed Acquisition helper file}}
            if {[file extension $name] ne [expr {$language eq {Tcl}?{.tcl}:{.py}}]} {error {Helper path does not match language}}
            foreach part [split $name /] {if {$part in {{} . ..}} {error {Helper path traversal is forbidden}}}
            if {$name in $names} {error {Duplicate Acquisition source/helper path}}
            lappend names $name
        }
    }
    return $names
}
proc ::GX::_viewerDevelopmentSnapshot {project} {
    if {![file isdirectory $project]||[file type $project] eq {link}} {error {Developer project root changed}}
    set result {}
    foreach {name key} {handlers.cpp source_sha256 design.gxtxt-viewer design_sha256 project.json project_sha256} {
        set path [file join $project $name];file lstat $path stat
        if {$stat(type) ne {file}||$stat(nlink)!=1||$stat(size)>4194304} {error {Developer project source is no longer an ordinary bounded file}}
        dict set result $key [sha256File $path]
    }
    set names [viewerDevelopmentSourceFiles $project]
    if {[llength $names]>1} {
        set files {}
        foreach name $names {
            set path [file join $project $name];file lstat $path stat
            if {$stat(type) ne {file} || $stat(nlink)!=1 || $stat(size)>65536 || [file normalize $path] ne $path} {error {Project source changed: $name}}
            dict set files $name [sha256File $path]
        }
        dict set result source_file_sha256 $files
    }
    return $result
}
proc ::GX::viewerDevelopmentPreview {project {module viewer.development_workspace} {provider development_workspace} {context {}}} {
    return [_viewerDevelopmentOpenWindow $project $module $provider $context]
}
proc ::GX::_viewerDevelopmentOpenWindow {project module provider context {runtimeRoot {}} {testOptions {}}} {
    if {[dict size $::GX::ViewerDevelopment::windows]>=8 && ($testOptions eq {} || ![dict exists $::GX::ViewerDevelopment::windows [dict get $testOptions window]])} {error {Close an existing development Preview before opening another}}
    foreach key [dict keys $context] {if {$key ni {workspace_id workspace_name dataset_id dataset_reference open_role tex_document_id em_document_id library_id entry_id}} {error {Unsupported restricted Viewer open context}}}
    if {[dict exists $context entry_id] && ![dict exists $context library_id]} {error {A Library entry requires its actual Library identity}}
    if {[dict exists $context library_id]} {
        set library [::GX::ScientificLibraryManagerAPIv1::getLibraryInfo [dict get $context library_id]]
        if {[datasetPublicationV2DictDefault $library mode managed] ne {managed} || [datasetPublicationV2DictDefault $library state installed] ne {installed}} {error {Viewer opening requires a current managed Library}}
        if {[dict exists $context entry_id]} {comparisonPlotSourceLibrary [dict get $context library_id] [dict get $context entry_id]}
    }
    if {$runtimeRoot eq {} && $::GX::currentSession eq {} && [datasetPublicationV2DictDefault $context workspace_id {}] ne {}} {error {A Session Workspace selection requires a Session; open the Development project without a Session Workspace ID to retain its local draft}}
    if {[dict exists $context dataset_reference]} {
        set reference [_datasetViewerReferenceValidate [dict get $context dataset_reference]]
        if {![dict exists $context dataset_id] || [dict get $context dataset_id] ne [dict get $reference dataset_id]} {error {Viewer context Dataset differs from its canonical reference}}
    }
    if {[dict exists $context open_role] && [dict get $context open_role] ne {contract_visualizer}} {error {Unknown Viewer Open role}}
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
    set lifetime [incr ::GX::ViewerDevelopment::serial]
    set w .gxViewerDevPreview$lifetime
    if {$testOptions ne {}} {
        set w [dict get $testOptions window]
        if {[winfo exists $w]} {destroy $w}
    }
    toplevel $w;wm title $w {Opening Viewer…};wm geometry $w 760x460
    ttk::label $w.loading -text {Preparing the Viewer and checking its compiled interface…} -wraplength 650 -padding 16
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -side bottom -pady 8;pack $w.loading -fill both -expand 1
    dict set ::GX::ViewerDevelopment::windows $w [dict create project $project module $module provider $provider open_context $context state [dict create values [lrepeat 16 0.0] counter 0] busy {} generation 0 status VALIDATING]
    dict set ::GX::ViewerDevelopment::windows $w lifetime $lifetime
    if {$testOptions ne {}} {dict set ::GX::ViewerDevelopment::windows $w installed_test $testOptions}
    bind $w <Destroy> +[list ::GX::_viewerDevelopmentDisposed $w %W]
    if {$runtimeRoot eq {}} {
        # The Build owner persists and reuses the source/dependency-bound artifact.
        set request [viewerDevelopmentRequest prepare $project [list ::GX::_viewerDevelopmentPreviewValidated $w $lifetime]]
    } else {
        set allocation [resourceManagementAllocate compiled_viewer_runtime [dict create category temporary lifetime viewer retention_seconds 0]]
        dict set ::GX::ViewerDevelopment::windows $w runtime_module_root $runtimeRoot
        dict set ::GX::ViewerDevelopment::windows $w runtime_allocation $allocation
        set request [_viewerDevelopmentCompiledRequest $w runtime_inspect [list ::GX::_viewerDevelopmentPreviewValidated $w $lifetime]]
    }
    dict set ::GX::ViewerDevelopment::windows $w busy $request
    return $w
}
proc ::GX::_viewerDevelopmentPreviewValidated {w lifetime response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $w] || [dict get $::GX::ViewerDevelopment::windows $w lifetime] != $lifetime || ![winfo exists $w]} return
    if {[catch {_viewerDevelopmentPreviewAdmit $w $response} message options]} {
        if {![dict exists $::GX::ViewerDevelopment::windows $w] || [dict get $::GX::ViewerDevelopment::windows $w lifetime] != $lifetime} return
        dict set ::GX::ViewerDevelopment::windows $w status REJECTED
        dict set ::GX::ViewerDevelopment::windows $w last_result [dict create ok 0 error $message]
        if {[winfo exists $w.loading]} {$w.loading configure -text "Viewer could not open: $message"}
    }
    if {![dict exists $::GX::ViewerDevelopment::windows $w] || [dict get $::GX::ViewerDevelopment::windows $w lifetime] != $lifetime} return
    set record [dict get $::GX::ViewerDevelopment::windows $w]
    if {[dict exists $record installed_test]} {
        set status [expr {[dict get $record status] eq {COMPLETED} ? {ready} : {rejected}}]
        set message [expr {$status eq {ready} ? {Installed compiled test handlers ready} : {Installed compiled test admission failed}}]
        if {[dict exists $record last_result error]} {set message [dict get $record last_result error]}
        if {[dict exists $record last_result host_error]} {set message [dict get $record last_result host_error]}
        _viewerDevelopmentTestNotify $w $status $message
    }
}
proc ::GX::_viewerDevelopmentPreviewAdmit {w response} {
    if {![dict exists $::GX::ViewerDevelopment::windows $w]||![winfo exists $w]} return
    # Refusal/source change cannot leave an older form proof reachable.
    catch {dict unset ::GX::ViewerDevelopment::windows $w pcb_source_form_admission}
    dict set ::GX::ViewerDevelopment::windows $w busy {}
    set r [dict get $::GX::ViewerDevelopment::windows $w]
    set project [dict get $r project];set module [dict get $r module];set provider [dict get $r provider]
    if {[dict exists $r installed_test] && ([interactiveDocumentSessionToken] ne [dict get $r installed_test session_token] ||
        ![viewerGuiTestFixtureValidate $w [dict get $r installed_test fixture_options]])} {
        dict set ::GX::ViewerDevelopment::windows $w status REJECTED
        $w.loading configure -text {Private test Session changed during compiled admission. Reconnect within the marked fixture.}
        return
    }
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
    dict set ::GX::ViewerDevelopment::windows $w typed_input [expr {{input} in [dict get $report sdk_calls] || {data} in [dict get $report sdk_calls]}]
    dict set ::GX::ViewerDevelopment::windows $w workspace_input [expr {{workspace} in [dict get $report sdk_calls] || [datasetPublicationV2DictDefault $report workspace_hooks {}] ne {}}]
    dict set ::GX::ViewerDevelopment::windows $w producer_input [expr {{dataset_producer_result} in [dict get $report sdk_calls]}]
    dict set ::GX::ViewerDevelopment::windows $w analysis_input [expr {{analysis_result} in [dict get $report sdk_calls] || {analysis_command} in [dict get $report sdk_calls]}]
    dict set ::GX::ViewerDevelopment::windows $w comparison_input [expr {{comparison_result} in [dict get $report sdk_calls] || {comparison_command} in [dict get $report sdk_calls]}]
    dict set ::GX::ViewerDevelopment::windows $w script_library_input [expr {{script_library_result} in [dict get $report sdk_calls] || {script_library_command} in [dict get $report sdk_calls]}]
    foreach key {dataset_producer_module dataset_producer_grants native_client_module native_client_grants} {
        if {[dict exists $report $key]} {dict set ::GX::ViewerDevelopment::windows $w $key [dict get $report $key]}
    }
    foreach {name key} {handlers.cpp source_sha256 design.gxtxt-viewer design_sha256 project.json project_sha256} {
        if {[sha256File [file join $project $name]] ne [dict get $report $key]} {$w.loading configure -text {Project changed after validation; close and reopen the Demo.};dict set ::GX::ViewerDevelopment::windows $w status SOURCE_CHANGED;return}
    }
    if {[dict exists $report source_manifest]} {
        foreach item [dict get $report source_manifest] {
            if {[sha256File [file join $project [dict get $item path]]] ne [dict get $item sha256]} {$w.loading configure -text {Project source tree changed; close and reopen the Preview.};dict set ::GX::ViewerDevelopment::windows $w status SOURCE_CHANGED;return}
        }
    }
    dict set ::GX::ViewerDevelopment::windows $w validated_snapshot [_viewerDevelopmentSnapshot $project]
    if {[dict exists $report native_client_grants] && [dict exists $r runtime_module_root]} {
        if {[catch {
            set package [_viewerNativeClientPackageSnapshot [dict get $r runtime_module_root]]
            set snapshot [dict get $::GX::ViewerDevelopment::windows $w validated_snapshot]
            if {[dict get $package source] ne $snapshot || [dict get $package design] ne [dict get $snapshot design_sha256] || ![dict exists $report binary_sha256] || [dict get $package binary] ne [dict get $report binary_sha256]} {error {Native client package changed during admission}}
        } problem]} {$w.loading configure -text $problem;dict set ::GX::ViewerDevelopment::windows $w status REJECTED;return}
        dict set ::GX::ViewerDevelopment::windows $w native_client_package_snapshot $package
    }
    # Only the current backend's admitted form/profile/grants supply authority.
    # Installed admission recomputes this too; never read an author JSON report.
    if {[dict exists $report transform_form_admission]} {
        set proof [dict get $report transform_form_admission]
        if {[catch {
            if {[dict get $proof schema] ne {gxtxt.viewer_transform_admission.v1} || [dict get $proof profile] ne {scientific_view_v1}} {error {Invalid Transform form admission}}
            foreach key {source_sha256 design_sha256 project_sha256} {
                if {[dict get $proof $key] ne [dict get $::GX::ViewerDevelopment::windows $w validated_snapshot $key]} {error {Transform admission differs from the validated project}}
            }
        } reason]} {
            dict set ::GX::ViewerDevelopment::windows $w status REJECTED
            $w.loading configure -text $reason
            return
        }
        dict set ::GX::ViewerDevelopment::windows $w transform_form_admission $proof
    } else {catch {dict unset ::GX::ViewerDevelopment::windows $w transform_form_admission}}
    if {[dict exists $report pcb_source_form_admission]} {
        if {[catch {
            set pcbDesign [viewerGuiDesignRead [file join $project design.gxtxt-viewer]]
            set proof [_viewerGuiPCBProofValidate $pcbDesign [dict get $report pcb_source_form_admission] [dict get $::GX::ViewerDevelopment::windows $w validated_snapshot]]
        } reason]} {
            dict set ::GX::ViewerDevelopment::windows $w status REJECTED
            $w.loading configure -text $reason
            return
        }
        dict set ::GX::ViewerDevelopment::windows $w pcb_source_form_admission $proof
    }
    dict set ::GX::ViewerDevelopment::windows $w workspace_callback_contract [dict get $report workspace_callback_contract_sha256]
    set design [viewerGuiDesignRead [file join $project design.gxtxt-viewer]]
    set handlers {}
    dict for {id contract} [dict get $design handlers] {dict set handlers $id [dict create command ::GX::viewerDevelopmentInvoke]}
    set context [dict merge [dict get $r open_context] [dict create command_catalog $module.cpp_[format %08x [zlib crc32 $project]]]]
    dict set context uml_operations [datasetPublicationV2DictDefault $report uml_operations {}]
    if {[dict exists $r runtime_module_root]} {
        dict set context workspace_open [list ::GX::viewerDevelopmentInstalledOpen $module $provider [dict get $r runtime_module_root]]
    } else {
        dict set context workspace_open [list ::GX::viewerDevelopmentProjectWorkspaceOpen $project $module $provider]
        dict set context workspace_provider [string map {. _ - _} $module]_${provider}_project_[format %08x [zlib crc32 $project]]_interface_state
    }
    set restoredState [dict get $r state]
    # Saved project providers are scoped by the admitted source project. They
    # must exist before the first saved-ID read, including a fresh process.
    viewerGuiWorkspaceProviderEnsure $module $provider $design runtime $handlers $context
    set projectDraft {}
    if {![dict exists $r runtime_module_root] && $::GX::currentSession eq {} && [dict exists $::GX::NativeWorkspace::providers [dict get $context workspace_provider]]} {
        set projectDraft [_viewerDevelopmentProjectDraftPrepare $w $context]
        if {[dict get $projectDraft item] ne {}} {set restoredState [dict get $projectDraft item payload domain_state restricted_cpp state]}
    }
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
    bind $w <Destroy> +[list ::GX::_viewerDevelopmentDisposed $w %W]
    if {[dict exists $r installed_test]} {
        set retained [dict get $r installed_test retained]
        if {[dict exists $retained domain_state restricted_cpp]} {
            set cpp [dict get $retained domain_state restricted_cpp]
            if {[datasetPublicationV2DictDefault $cpp snapshot {}] eq [dict get $::GX::ViewerDevelopment::windows $w validated_snapshot] &&
                [datasetPublicationV2DictDefault $cpp callback_contract {}] eq [dict get $::GX::ViewerDevelopment::windows $w workspace_callback_contract]} {
                set restoredState [dict get $cpp state];viewerDevelopmentStateJson $restoredState
            } else {dict unset retained domain_state restricted_cpp}
        }
        if {$retained ne {}} {viewerGuiDesignRestore $w $retained}
        dict set ::GX::ViewerDevelopment::windows $w state $restoredState
        if {[dict get $r installed_test geometry] ne {}} {wm geometry $w [dict get $r installed_test geometry]}
    }
    if {$projectDraft ne {}} {_viewerDevelopmentProjectDraftAttach $w $projectDraft}
    set domain [viewerGuiDesignContextGet $w]
    dict set domain restricted_cpp [_viewerDevelopmentStateEnvelope $w $restoredState]
    viewerGuiDesignContextSet $w $domain
    # This envelope initializes a newly composed native client. Include that
    # same starting identity in its clean baseline without replacing any draft
    # or an existing Workspace's independently retained state.
    if {![dict exists $::GX::ViewerGui::instances $w saved domain_state restricted_cpp]} {
        dict set ::GX::ViewerGui::instances $w saved domain_state restricted_cpp [dict get $domain restricted_cpp]
    }
    wm title $w [dict get $design title]
    if {$projectDraft ne {}} {wm title $w "[dict get $design title] — [file tail [dict get $projectDraft project]] (local project)"}
    documentationBrowserAttachViewerHelp $module $provider $w
    viewerDevelopmentInvoke $w __open__
}
proc ::GX::viewerDevelopmentInvoke {window action} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]||![viewerGuiDesignGuard $window]} {return {status rejected message {Development Viewer lifetime ended}}}
    set r [dict get $::GX::ViewerDevelopment::windows $window]
    set incarnation [winfo id $window]
    set eventScope {}
    if {[dict exists $r dataset_producer_module] && $::GX::currentSession ne {}} {
        set eventScope [dict create incarnation $incarnation lifetime [dict get $r lifetime] module [dict get $r module] session_token [interactiveDocumentSessionToken]]
    }
    if {[dict get $r busy] ne {}} {return {status busy message {Wait or cancel the current native event}}}
    if {[dict get $r status] eq {RUNNING}} {return {status busy message {Wait for the current native event's trusted host operations}}}
    if {![dict exists $r validated_snapshot]||[catch {_viewerDevelopmentSnapshot [dict get $r project]} current]||$current ne [dict get $r validated_snapshot]} {
        catch {dict unset ::GX::ViewerDevelopment::windows $window pcb_source_form_admission}
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
        if {[dict exists $item properties diagnostics_changed] && [dict get $item properties diagnostics_changed] eq $action} {set component $index;set kind 2;break}
        if {[dict exists $item properties action]&&[dict get $item properties action] eq $action} {set component $index;set actionValue [datasetPublicationV2DictDefault [dict get $item properties] event_value 0.0];break}
        if {[dict exists $item properties change_action]&&[dict get $item properties change_action] eq $action} {set component $index;set kind 2;set changed [dict get $item id];break}
    }
    set sourceEvent 0
    if {$action eq {__script_library_source_select__} && [dict exists $r script_library_source_event]} {
        set index 0;set sourceId [dict get $r script_library_source_event]
        foreach item [dict get $::GX::ViewerGui::instances $window design components] {incr index;if {[dict get $item id] eq $sourceId} {set component $index;set kind 2;set sourceEvent 1;break}}
        dict unset r script_library_source_event
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
    if {$eventScope ne {}} {dict set eventScope generation $generation}
    if {[dict exists $r native_client_grants]} {
        set declared [dict exists $::GX::ViewerGui::instances $window design handlers $action]
        set effect [expr {$declared?[dict get $::GX::ViewerGui::instances $window design handlers $action effect]:{presentation}}]
        dict set r native_client_event_scope [dict create incarnation $incarnation lifetime [dict get $r lifetime] module [dict get $r module] session_token [_viewerNativeClientSessionToken] generation $generation action $action effect $effect user_action [expr {$declared||$sourceEvent}]]
    }
    # The managed exchange runs a Tk event loop while the native callback is
    # executing. Reserve this lifetime BEFORE the exchange, so asynchronous
    # public data notifications cannot start a second callback on that worker.
    dict set r status RUNNING
    dict set ::GX::ViewerDevelopment::windows $window $r
    set started [clock microseconds]
    if {[catch {
        set service [_viewerDevelopmentCompiledService $window]
        set payload [format {{"event":%s,"state":%s}} [viewerDevelopmentEventJson [dict create kind $kind component $component value $value]] [viewerDevelopmentStateJson [dict get $r state]]]
        set contextFields {}
        if {[datasetPublicationV2DictDefault $r typed_input 0]} {
            set inputs {}
            foreach item [dict get $::GX::ViewerGui::instances $window design components] {
                set text [datasetPublicationV2DictDefault $values [dict get $item id] {}]
                if {[string length [encoding convertto utf-8 $text]]>4096} {set text {}}
                lappend inputs [viewerDevelopmentJsonString $text]
            }
            set data [datasetPublicationV2DictDefault $r event_data {}]
            if {$data eq {} && $component == 0 && $action ne {__open__} && [dict exists $::GX::ViewerGui::instances $window design handlers $action]} {set data $action}
            lappend contextFields [format {"inputs":[%s]} [join $inputs ,]] [format {"data":%s} [viewerDevelopmentJsonString $data]]
            catch {dict unset ::GX::ViewerDevelopment::windows $window event_data}
        }
        if {[datasetPublicationV2DictDefault $r workspace_input 0]} {lappend contextFields [format {"workspace":%s} [_viewerWorkspaceSdkSnapshot $window]]}
        if {[datasetPublicationV2DictDefault $r producer_input 0]} {lappend contextFields [format {"producer":%s} [_viewerDatasetProducerSnapshot $window]]}
        if {[datasetPublicationV2DictDefault $r script_library_input 0]} {lappend contextFields [format {"script_library_result":%s} [_viewerNativeClientLibrarySnapshot $window]]}
        if {[datasetPublicationV2DictDefault $r analysis_input 0]} {lappend contextFields [format {"analysis_result":%s} [_viewerAnalysisSnapshot $window]]}
        if {[datasetPublicationV2DictDefault $r comparison_input 0]} {lappend contextFields [format {"comparison_result":%s} [_viewerComparisonSnapshot $window]]}
        if {$contextFields ne {}} {set payload [format {{"event":%s,"state":%s,"context":{%s}}} [viewerDevelopmentEventJson [dict create kind $kind component $component value $value]] [viewerDevelopmentStateJson [dict get $r state]] [join $contextFields ,]]}
        set response [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $service $payload]]]
        if {[catch {dict get $response ok}]} {error {Compiled Viewer returned an invalid typed response}}
        # Apply the real compiled event before dispatching the next native input.
        # Long-running scientific work remains an operation of its existing owner.
        if {[dict exists $::GX::ViewerDevelopment::windows $window] && [winfo exists $window] &&
            [winfo id $window] eq $incarnation && [dict get $::GX::ViewerDevelopment::windows $window lifetime] eq [dict get $r lifetime]} {
            dict set ::GX::ViewerDevelopment::windows $window status RUNNING
            _viewerDevelopmentRan $window $generation $response $eventScope
        }
    } problem]} {
        if {[dict exists $::GX::ViewerDevelopment::windows $window]} {
            if {[dict exists $::GX::ViewerDevelopment::windows $window compiled_service]} {scriptJobRequestCancel [dict get $::GX::ViewerDevelopment::windows $window compiled_service] closed}
            dict set ::GX::ViewerDevelopment::windows $window status FAILED
            dict set ::GX::ViewerDevelopment::windows $window last_result [dict create ok 0 error $problem]
            _viewerNativeClientEventFailed $window [dict create error $problem]
            catch {dict unset ::GX::ViewerDevelopment::windows $window native_client_event_scope}
            [dict get $::GX::ViewerGui::instances $window slots status] configure -text $problem
            if {[llength [info commands ::GX::_viewerDiagnosticsDispose]]} {_viewerDiagnosticsDispose $window}
        }
        return [dict create status failed message $problem]
    }
    if {[dict exists $::GX::ViewerDevelopment::windows $window]} {catch {dict unset ::GX::ViewerDevelopment::windows $window native_client_event_scope}}
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window] || [winfo id $window] ne $incarnation} {return [dict create status completed window_closed 1 elapsed_us [expr {[clock microseconds]-$started}]]}
    set reply [dict create status [expr {[dict get $::GX::ViewerDevelopment::windows $window status] eq {COMPLETED} ? {completed} : {failed}}] elapsed_us [expr {[clock microseconds]-$started}]]
    if {[dict get $reply status] eq {failed} && [dict exists $::GX::ViewerDevelopment::windows $window last_result]} {
        set last [dict get $::GX::ViewerDevelopment::windows $window last_result]
        foreach key {host_error error} {
            if {[dict exists $last $key] && [dict get $last $key] ne {}} {dict set reply message [dict get $last $key];break}
        }
    }
    return $reply
}
proc ::GX::_viewerDevelopmentRan {window generation response {eventScope {}}} {
    if {![dict exists $::GX::ViewerDevelopment::windows $window]||![winfo exists $window]||[dict get $::GX::ViewerDevelopment::windows $window generation]!=$generation} return
    dict set ::GX::ViewerDevelopment::windows $window busy {}
    set incarnation [winfo id $window]
    set lifetime [dict get $::GX::ViewerDevelopment::windows $window lifetime]
    set status FAILED
    if {[dict get $response ok]} {
        set result [dict get $response result];set status [dict get $result status]
        if {$status eq {COMPLETED}} {
            set project [dict get $::GX::ViewerDevelopment::windows $window project]
            set expected [dict get $::GX::ViewerDevelopment::windows $window validated_snapshot]
            set observed {};foreach key {source_sha256 design_sha256 project_sha256} {dict set observed $key [dict get $result $key]}
            if {[dict exists $expected source_file_sha256]} {
                set files {}
                foreach item [datasetPublicationV2DictDefault $result source_manifest {}] {dict set files [dict get $item path] [dict get $item sha256]}
                dict set observed source_file_sha256 $files
            }
            if {[catch {_viewerDevelopmentSnapshot $project} current]||$current ne $expected||$observed ne $expected} {set status SOURCE_CHANGED} else {
                if {[catch {
                    set workspaceOperations {};set ownerCurrent 1
                    foreach operation [dict get $result operations] {
                        set component [dict get $operation component];set value [dict get $operation value]
                        switch [dict get $operation operation] {
                            workspace_command {lappend workspaceOperations $value}
                            dataset_producer_command {_viewerDatasetProducerCommand $window $eventScope $value}
                            script_library_command {_viewerNativeClientLibraryCommand $window $component $value}
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
                            comparison_command {_viewerComparisonNativeCommand $window $component $value}
                            analysis_command {_viewerAnalysisNativeCommand $window $component $value}
                            plot_discover {viewerGuiDesignPlotDiscover $window $component}
                            plot_bind {viewerGuiDesignPlotBind $window $value $component}
                            document_bind {viewerGuiDesignDocumentBind $window $component $value}
                            document_command {viewerGuiDesignDocumentCommand $window $component $value}
                            raster_bind {viewerGuiDesignRasterBind $window $component $value}
                            raster_tool {viewerGuiDesignRasterTool $window $component $value}
                            raster_command {viewerGuiDesignRasterCommand $window $component $value}
                            tex_command {viewerGuiDesignTeXCommand $window $component $value}
                            em_command {viewerGuiDesignEMCommand $window $component $value}
                            workbench_command {viewerGuiDesignWorkbenchCommand $window $component $value}
                            cad_command {viewerGuiDesignCadCommand $window $component $value}
                            diagnostics_command {viewerGuiDesignDiagnosticsCommand $window $component $value}
                            text_runs {viewerGuiDesignTextRuns $window $component $value}
                            table_set {viewerGuiDesignTableSet $window $component $value}
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
                        # A trusted host operation may close this Viewer. Do
                        # not recreate a partial record while applying the rest
                        # of the worker reply or touch a replacement incarnation.
                        if {![winfo exists $window] || [winfo id $window] ne $incarnation || ![dict exists $::GX::ViewerDevelopment::windows $window lifetime] || [dict get $::GX::ViewerDevelopment::windows $window lifetime] ne $lifetime} {set ownerCurrent 0;break}
                    }
                    if {$ownerCurrent} {
                    dict set ::GX::ViewerDevelopment::windows $window state [dict get $result state]
                    dict set ::GX::ViewerDevelopment::windows $window workspace_hook_mask [datasetPublicationV2DictDefault $result workspace_hook_mask 0]
                    if {[dict exists $result workspace_capture]} {
                        if {[dict exists [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] workspace_hooks {}] capture]} {error {A Viewer model cannot have both host and C++ capture owners}}
                        dict set ::GX::ViewerGui::instances $window cpp_workspace_state [_viewerWorkspaceSdkValue [dict get $result workspace_capture]]
                    }
                    set domain [viewerGuiDesignContextGet $window]
                    dict set domain restricted_cpp [_viewerDevelopmentStateEnvelope $window [dict get $result state]]
                    viewerGuiDesignContextSet $window $domain
                    # Save captures this event's completed native state. Close
                    # and Open may replace the window only after that handoff.
                    foreach request $workspaceOperations {_viewerGuiWorkspaceSdkCommand $window $request;if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window] || [winfo id $window] ne $incarnation} {break}}
                    }
                } problem]} {set status FAILED;dict set response host_error $problem}
            }
        }
    }
    # Exiting inside catch would become TCL_RETURN and be treated as failure.
    # A lifecycle request may have recreated the same Tk path for a new Viewer.
    if {![dict exists $::GX::ViewerDevelopment::windows $window] || ![winfo exists $window] || [winfo id $window] ne $incarnation} return
    if {$status ne {COMPLETED} && [dict exists $::GX::ViewerDevelopment::windows $window dataset_producer_module]} {_viewerDatasetProducerEventFailed $window $eventScope $response}
    if {$status ne {COMPLETED}} {_viewerNativeClientEventFailed $window $response}
    if {$status eq {SOURCE_CHANGED}} {catch {dict unset ::GX::ViewerDevelopment::windows $window pcb_source_form_admission}}
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
    if {[llength [info commands ::GX::_viewerDiagnosticsResume]]} {_viewerDiagnosticsResume $window}
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
    if {[dict exists $record installed_test]} {_viewerDevelopmentTestNotify $window rejected {Installed test window closed before admission}}
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
proc ::GX::viewerDevelopmentInstalledTestOpen {window module provider moduleRoot fixtureRoot retained onReady {geometry {}}} {
    # This is a trusted host connection, never a portable/authored callback.
    if {$window ne {.gxInterfacePreview} || ![viewerGuiDesignGuard $window]} {error {Installed tests require the existing Builder Preview}}
    if {![llength $onReady] || ![llength [info commands [lindex $onReady 0]]]} {error {Installed tests require a trusted live completion callback}}
    if {$geometry ne {} && ![regexp {^[0-9]{3,4}x[0-9]{3,4}(?:[+-][0-9]{1,5}){0,2}$} $geometry]} {error {Invalid installed test window geometry}}
    set design [dict get $::GX::ViewerGui::instances $window design]
    set options [dict create fixture_root $fixtureRoot permitted_commands [dict keys [dict get $design handlers]]]
    if {![viewerGuiTestFixtureValidate $window $options]} {error {Installed tests require a marked private fixture containing the current Session}}
    # Bundled and Plugin-Manager-managed providers are both normal installed
    # modules. Registered root/design and PackageVerify remain authoritative;
    # the removable-plugin registry is not a prerequisite for bundled clients.
    if {{RESTRICTED_VIEWER_CLIENT_API_v1} ni [modulePublicApiIds $module]} {error {Select a registered restricted C++ Viewer before connecting its test handlers}}
    set root [file normalize $moduleRoot]
    if {[file normalize [file dirname [moduleField $module descriptor]]] ne $root || ![file isfile [file join $root native viewer.so]]} {error {Installed test package root or native binary does not match the registered module}}
    set descriptor [viewerProviderDefinition $module $provider]
    if {![moduleIsEnabled $module] || $descriptor eq {} || [dict get $descriptor activation_api] ne {RESTRICTED_VIEWER_CLIENT_API_v1} || [dict get $design module_id] ne $module || [dict get $design provider_id] ne $provider} {error {Installed test provider differs from the Builder design}}
    set installed [viewerGuiDesignRead [file join $root gui design.tcldict]]
    if {[dict remove $installed origin] ne [dict remove $design origin]} {error {Install the exact matching Builder design before connecting test handlers}}
    if {$retained ne {}} {_viewerGuiDesignRestoreCheck $window $retained}
    set incarnation [winfo id $window];set session [interactiveDocumentSessionToken]
    set fallback [viewerGuiDesignCapture $window]
    viewerDevelopmentPackageVerify $root
    # Package admission pumps Tk. Recheck the exact old owner before replacing it.
    if {![viewerGuiDesignGuard $window] || [winfo id $window] ne $incarnation || [interactiveDocumentSessionToken] ne $session ||
        [dict remove [dict get $::GX::ViewerGui::instances $window design] origin] ne [dict remove $design origin] || ![viewerGuiTestFixtureValidate $window $options]} {error {Builder design or Session changed during installed test admission}}
    if {[dict remove [viewerGuiDesignCapture $window] gui_properties] ne [dict remove $fallback gui_properties]} {error {Preview draft changed during installed test admission; reconnect without replacing the current draft}}
    if {![moduleIsEnabled $module] || {RESTRICTED_VIEWER_CLIENT_API_v1} ni [modulePublicApiIds $module] ||
        [file normalize [file dirname [moduleField $module descriptor]]] ne $root || ![file isfile [file join $root native viewer.so]] ||
        [viewerProviderDefinition $module $provider] ne $descriptor || [viewerGuiDesignRead [file join $root gui design.tcldict]] ne $installed} {error {Installed module/provider changed during test admission}}
    modulePublicApiActivate $module RESTRICTED_VIEWER_CLIENT_API_v1
    set resources [viewerGuiDesignResourceLeaseAcquire $window]
    set test [dict create window $window retained $retained fallback $fallback on_ready $onReady geometry $geometry resources $resources fixture_options $options session_token $session]
    # If construction fails synchronously, hand the carriers back before error;
    # callers keep them through their own retained-state recovery.
    if {[catch {_viewerDevelopmentOpenWindow [file join $root source] $module $provider {} $root $test} result options]} {
        # A partially allocated host may still be disposed by caller recovery.
        # Transfer these carriers once, rather than notifying again on Destroy.
        if {[dict exists $::GX::ViewerDevelopment::windows $window installed_test]} {
            dict unset ::GX::ViewerDevelopment::windows $window installed_test
            catch {destroy $window}
        }
        after idle [list {*}$onReady $window [dict create status rejected message $result resources $resources retained $fallback]]
        return -options $options $result
    }
    return $result
}
proc ::GX::_viewerDevelopmentTestNotify {window status message} {
    set test [dict get $::GX::ViewerDevelopment::windows $window installed_test]
    dict unset ::GX::ViewerDevelopment::windows $window installed_test
    set resources [dict get $test resources]
    if {$status eq {ready}} {viewerGuiDesignResourceLeaseRelease $resources;set resources {}}
    set receipt [dict create status $status message $message resources $resources retained [dict get $test fallback]]
    after idle [list {*}[dict get $test on_ready] $window $receipt]
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
    set request [scriptJobAsync $command {} [list ::GX::_viewerDevelopmentCompiledEnded $window [dict get $record lifetime]] [dict create duplex 1 send_pending_bytes 2097152 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Compiled Viewer lifetime}]]
    dict set ::GX::ViewerDevelopment::windows $window compiled_service $request
    set ready [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $request {} 5000]]]
    if {![dict get $ready ok] || [dict get $ready result status] ne {READY}} {scriptJobRequestCancel $request closed;error {Compiled Viewer worker could not load its precompiled binary}}
    dict set ::GX::ViewerDevelopment::windows $window compiled_service_receipt [dict get $ready result]
    dict set ::GX::ViewerDevelopment::windows $window compiled_service_diagnostics [datasetPublicationV2DictDefault [dict get $ready result] stderr_diagnostics_active 0]
    if {[info exists ::GX::StderrDiagnostics::desired] && !$::GX::StderrDiagnostics::desired} {_stderrDiagnosticsStopNativeRoutes}
    return $request
}
proc ::GX::_viewerDevelopmentCompiledEnded {window lifetime response} {
    if {![winfo exists $window] || ![dict exists $::GX::ViewerDevelopment::windows $window lifetime] || [dict get $::GX::ViewerDevelopment::windows $window lifetime] != $lifetime} return
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
