# SPDX-License-Identifier: GPL-3.0-or-later
# One descriptor/discovery authority for exporter and other view/workbench actions.
namespace eval ::GX::WorkbenchExtension {variable hosts {}}
proc ::GX::moduleEffectiveConfigSnapshot {module} {
    variable moduleCfg
    ensureModuleConfigDefaults
    set result {}
    foreach key [moduleConfigKeys $module] {dict set result $key $moduleCfg($module,$key)}
    return $result
}
proc ::GX::workbenchExtensionCoreApis {} {
    set result [dict create CONFIGURATION_API_v1 ::GX::configurationApiInfo DOCUMENTATION_BROWSER_API_v1 ::GX::documentationBrowserApiInfo SCIENTIFIC_RECIPE_API_v1 ::GX::scientificRecipeApiInfo NATIVE2D_VIEWPORT_HOST_v1 ::GX::native2DViewportHostApiInfo VIEWER_DEVELOPMENT_API_v1 ::GX::viewerDevelopmentApiInfo VIEWER_COMPONENT_DEMO_API_v1 ::GX::viewerGuiComponentDemoApiInfo NATIVE2D_TEMPORARY_DISPLAY_API_v1 ::GX::native2DTemporaryDisplayApiInfo NATIVE_PLOT_DISPLAY_API_v1 ::GX::nativePlotDisplayApiInfo NATIVE_3D_GUI_HOST_API_v1 ::GX::native3DGuiHostApiInfo NATIVE_3D_GUI_HOST_API_v2 ::GX::native3DGuiHostApiInfoV2 SOURCE_SURFACE_API_v1 ::GX::sourceSurfaceApiInfo XML_DOCUMENT_API_v1 ::GX::xmlDocumentApiInfo PYTHON_ENVIRONMENT_API_v1 ::GX::pythonEnvironmentApiInfo PRINT_DOCUMENT_API_v1 ::GX::printDocumentApiInfo VIEWER_GUI_HOST_API_v1 ::GX::viewerGuiHostApiInfo DATASET_PUBLICATION_API_v2 ::GX::datasetPublicationV2Prepare DATASET_SCIENTIFIC_PROFILE_API_v1 ::GX::datasetProfileApiInfo GEOMETRY_EXCHANGE_API_v1 ::GX::geometryExchangeApiInfo SCIENTIFIC_MULTIVIEW_HOST_API_v1 ::GX::scientificMultiviewHostCapabilities SESSION_WORKSPACE_API_v1 ::GX::sessionWorkspaceApiInfo NOTE_DOCUMENT_API_v1 ::GX::noteDocumentApiInfo MANAGED_RESOURCE_API_v1 ::GX::managedResourceApiInfo NATIVE_2D_GEOMETRY_API_v1 ::GX::native2DGeometryApiInfo NATIVE_3D_GEOMETRY_API_v1 ::GX::native3DGeometryApiInfo DATASET_TRANSFORM_API_v1 ::GX::datasetTransformOperations WORKBENCH_EXTENSION_API_v1 ::GX::workbenchExtensionApiInfo UI_FIELD_API_v1 ::GX::uiFieldApiInfo CURVE_SOURCE_API_v1 ::GX::curveSourceApiInfo NATIVE2D_PRESENTATION_SNAPSHOT_v1 ::GX::native2DPresentationSnapshot]
    # Existing public owners also participate in the same discovery authority.
    # Presence here does not grant a restricted SDK capability.
    return [dict merge $result {
        FILE_PUBLICATION_API_v1 ::GX::filePublicationApiInfo
        DATASET_VIEWER_API_v1 ::GX::datasetViewerApiInfo
        INTERACTIVE_DOCUMENT_API_v1 ::GX::interactiveDocumentApiInfo
        OCR_LAYOUT_API_v1 ::GX::OCRLayoutAPIv1::apiInfo
        RESOURCE_MANAGEMENT_API_v1 ::GX::resourceManagementApiInfo
        SCIENTIFIC_LIBRARY_MANAGER_API_v1 ::GX::ScientificLibraryManagerAPIv1::apiInfo
        SCIENTIFIC_SPECTRUM_API_v1 ::GX::SpectrumAPIv1::apiInfo
        SCIENTIFIC_SPECTRUM_IMPORT_API_v1 ::GX::SpectrumImportAPIv1::apiInfo
        SCIENTIFIC_SPECTRUM_SESSION_API_v1 ::GX::SpectrumSessionAPIv1::apiInfo
        SPECTRAL_FAMILY_API_v1 ::GX::SpectralFamilyAPIv1::apiInfo
        TABLE_EXTRACTOR_API_v1 ::GX::TableExtractorAPIv1::apiInfo
        WORKBENCH_RECOVERY_API_v1 ::GX::workbenchRecoveryApiInfo
        GUI_UPDATE_SCHEDULER_API_v1 ::GX::guiUpdateSchedulerApiInfo
        NATIVE2D_GRID_PRESENTER_API_v1 ::GX::native2DGridPresenterApiInfo
    }]
}
proc ::GX::workbenchExtensionRequireApi {api} {
    if {$api eq "SCIENTIFIC_RECIPE_API_v1"&&[llength [info commands ::GX::scientificRecipeApiInfo]]} {return}
    set core [workbenchExtensionCoreApis]
    if {[dict exists $core $api]} {
        if {![llength [info commands [dict get $core $api]]]} {error "Required CORE API '$api' is unavailable"}
        return
    }
    foreach module $::GX::moduleOrder {
        if {$api in [modulePublicApiIds $module]} {modulePublicApiActivate $module $api;return}
    }
    error "Required public API '$api' is unavailable"
}
proc ::GX::workbenchExtensionApiInfo {} {
    return [dict create api_id WORKBENCH_EXTENSION_API_v1 api_version 1 categories {exporter importer tool operation measurement geometry_generator transform validator repair analysis utility} operations {list describe invoke export script_context return_result} arbitrary_tk 0]
}
proc ::GX::workbenchExtensionProviderList {{workbench ""} {category ""}} {
    variable moduleOrder
    set result {}
    foreach module $moduleOrder {
        if {![moduleIsEnabled $module]} continue
        set path [moduleField $module descriptor ""]
        if {$path eq ""} continue
        set descriptor [parseIni $path]
        set ids [splitList [descriptorValue $descriptor extensions ids ""]]
        if {$ids eq {}} continue
        if {[descriptorValue $descriptor extensions api_version ""] ne "1"} {error "$module: unsupported Workbench Extension API version"}
        foreach id $ids {
            if {![viewerIdValid $id]} {error "$module: invalid extension ID"}
            set section "extension.$id"
            set action [dict create module_id $module action_id $id plugin_version [moduleField $module version ""]]
            foreach {key default} {name {} category {} workbenches {} selection_kinds {} mutates 0 public_api {} command {} parameters {} required_apis {} output_format {}} {
                dict set action $key [descriptorValue $descriptor $section $key $default]
            }
            foreach key {workbenches selection_kinds parameters required_apis} {dict set action $key [splitList [dict get $action $key]]}
            if {[dict get $action category] ni [dict get [workbenchExtensionApiInfo] categories]} {error "$module/$id: invalid category"}
            if {[dict get $action mutates] ni {0 1}} {error "$module/$id: mutates must be 0 or 1"}
            if {[dict get $action public_api] ni [splitList [descriptorValue $descriptor public_apis ids ""]] || ![regexp {^::[A-Za-z_][A-Za-z0-9_:]*$} [dict get $action command]]} {error "$module/$id: extension must declare a public API command"}
            set fields {}
            foreach key [dict get $action parameters] {
                if {![viewerIdValid $key]} {error "$module/$id: invalid parameter ID"}
                set spec {}
                foreach {field default} {type string label {} default {} required 0 min {} max {} values {} alpha 0 allow_inherit 0} {
                    set value [descriptorValue $descriptor "extension.$id.parameter.$key" $field $default]
                    if {$value ne ""} {dict set spec $field $value}
                }
                if {[dict exists $spec values]} {dict set spec values [splitList [dict get $spec values]]}
                if {[dict get $spec type] ni [dict get [uiFieldApiInfo] types]} {error "$module/$id: unknown UI field type"}
                dict set fields $key $spec
            }
            dict set action fields $fields
            if {$workbench ne "" && $workbench ni [dict get $action workbenches]} continue
            if {$category ne "" && $category ne [dict get $action category]} continue
            lappend result $action
        }
    }
    return $result
}
proc ::GX::workbenchExtensionDescribe {module action} {
    foreach definition [workbenchExtensionProviderList] {
        if {[dict get $definition module_id] eq $module && [dict get $definition action_id] eq $action} {return $definition}
    }
    error "Extension '$module/$action' is unavailable or disabled"
}
proc ::GX::workbenchExtensionHostRegister {workbench callbacks} {
    variable ::GX::WorkbenchExtension::hosts
    foreach key {begin apply commit rollback} {
        if {![dict exists $callbacks $key] || [llength [dict get $callbacks $key]]==0} {error "Mutating extension host needs $key callback"}
    }
    dict set hosts $workbench $callbacks
}
proc ::GX::workbenchExtensionInvoke {module action context} {
    variable ::GX::WorkbenchExtension::hosts
    set definition [workbenchExtensionDescribe $module $action]
    foreach key [dict keys $context] {
        if {$key ni {workbench_id workbench_version document_id revision selection active_object active_group working_plane units parameters config_snapshot presentation_snapshot}} {error "Unknown extension context field '$key'"}
    }
    foreach key {workbench_id workbench_version document_id revision} {if {![dict exists $context $key]} {error "Extension context needs $key"}}
    set workbench [dict get $context workbench_id]
    if {$workbench ni [dict get $definition workbenches]} {error "$module/$action does not support $workbench"}
    if {![string is entier -strict [dict get $context revision]] || [dict get $context revision]<0} {error "Invalid document revision"}
    set document [interactiveDocumentRead [dict get $context document_id]]
    if {[dict get $document module_id] ne $workbench || [dict get $document revision]!=[dict get $context revision]} {error "Extension context belongs to a different owner or stale document revision"}
    set supplied [datasetPublicationV2DictDefault $context parameters {}];set parameters {}
    foreach key [dict keys $supplied] {if {![dict exists $definition fields $key]} {error "Unknown extension parameter '$key'"}}
    dict for {key field} [dict get $definition fields] {
        dict set parameters $key [uiFieldNormalize $field [datasetPublicationV2DictDefault $supplied $key [datasetPublicationV2DictDefault $field default ""]]]
    }
    dict set context parameters $parameters
    dict set context config_snapshot [moduleEffectiveConfigSnapshot $module]
    modulePublicApiActivate $module [dict get $definition public_api]
    foreach api [dict get $definition required_apis] {workbenchExtensionRequireApi $api}
    set command [dict get $definition command]
    if {![llength [info commands $command]]} {error "Extension command is unavailable after activation"}
    if {[dict get $definition selection_kinds] ne {}&&[dict exists $context selection kind]&&[dict get $context selection kind] ni [dict get $definition selection_kinds]} {error "Extension does not support this selection kind"}
    set transaction "";set callbacks {}
    if {[dict get $definition mutates]} {
        if {![dict exists $hosts $workbench]} {error "Workbench has no transactional extension host"}
        set callbacks [dict get $hosts $workbench]
        set transaction [uplevel #0 [list {*}[dict get $callbacks begin] $context]]
    }
    try {
        set result [uplevel #0 [list $command $context]]
        if {![dict exists $result status] || [dict get $result status] ne "ok"} {error "Extension did not return a successful structured result"}
        set provenance [dict merge [datasetPublicationV2DictDefault $result provenance {}] [dict create module_id $module action_id $action plugin_version [dict get $definition plugin_version] api_id WORKBENCH_EXTENSION_API_v1 parameters $parameters config_snapshot [dict get $context config_snapshot]]]
        dict set result provenance $provenance
        set before [dict get $context revision];set after $before
        if {$transaction ne ""} {
            set applied [uplevel #0 [list {*}[dict get $callbacks apply] $transaction $result]]
            set committed [uplevel #0 [list {*}[dict get $callbacks commit] $transaction $applied]]
            if {![catch {dict get $committed revision} revision]} {set after $revision;dict set result warnings [concat [datasetPublicationV2DictDefault $result warnings {}] [datasetPublicationV2DictDefault $committed warnings {}]]} else {set after $committed}
            set result [dict merge $result $applied]
            set transaction ""
        }
        set provenance [dict merge [datasetPublicationV2DictDefault $result provenance {}] [dict create module_id $module action_id $action plugin_version [dict get $definition plugin_version] api_id WORKBENCH_EXTENSION_API_v1 parameters $parameters config_snapshot [dict get $context config_snapshot]]]
        return [dict merge [dict create created_ids {} modified_ids {} deleted_ids {} warnings {}] $result [dict create status ok revision_before $before revision_after $after provenance $provenance]]
    } finally {
        if {$transaction ne ""} {uplevel #0 [list {*}[dict get $callbacks rollback] $transaction]}
    }
}
proc ::GX::workbenchExtensionExport {module action context destination} {
    set definition [workbenchExtensionDescribe $module $action]
    if {[dict get $definition category] ne "exporter" || [dict get $definition mutates]} {error "Action is not a read-only exporter"}
    set destination [file normalize $destination]
    if {[file exists $destination]} {error "Export destination already exists: $destination"}
    set result [workbenchExtensionInvoke $module $action $context]
    if {![dict exists $result bytes] || [dict get $result format] ne [dict get $definition output_format]} {error "Exporter returned an invalid output contract"}
    set files [list [dict create id export destination $destination writer [list ::GX::_workbenchExtensionWriteExport [dict get $result bytes]]]]
    set index 0;set seen {}
    foreach sidecar [datasetPublicationV2DictDefault $result sidecars {}] {
        set suffix [dict get $sidecar suffix]
        if {![regexp {^\.[A-Za-z0-9_.-]+$} $suffix]||$suffix in $seen} {error "Exporter returned an invalid/duplicate sidecar suffix"}
        lappend seen $suffix
        lappend files [dict create id sidecar[incr index] destination "$destination$suffix" writer [list ::GX::_workbenchExtensionWriteExport [dict get $sidecar bytes]]]
    }
    set publication [filePublicationPublishBundle $files]
    return [dict merge [dict remove $result bytes sidecars] [dict get $publication files export] [dict create published_files [dict get $publication files]]]
}
proc ::GX::_workbenchExtensionWriteExport {bytes channel context} {puts -nonewline $channel $bytes}

# Host-owned inert result transport; scripts never supply an output path.
proc ::GX::workbenchExtensionScriptResultWrite {executionRoot result} {
    if {[string bytelength $result]>8388608||[catch {dict size $result}]} {error "Extension result limit is 8 MiB of structured data"}
    if {![dict exists $result status]||[dict get $result status] ne "ok"} {error "Extension result needs status=ok"}
    set path [file join $executionRoot workbench-extension-result.tcldata]
    set ch [open $path {WRONLY CREAT EXCL}]
    try {fconfigure $ch -encoding utf-8 -translation lf;puts -nonewline $ch $result} finally {close $ch}
    return [dict create status ok byte_count [file size $path]]
}
proc ::GX::workbenchExtensionScriptInvoke {module action context} {
    if {![moduleIsEnabled $module]} {error "Extension module is disabled"}
    set info [scriptModuleDescriptor $module]
    set descriptor [dict get $info descriptor]
    if {[descriptorValue $descriptor script profile {}] ne "W"} {error "This package is not a Workbench extension script profile"}
    set root [file join $::GX::currentSession analysis extensions "action-[pid]-[clock clicks]"];file mkdir $root
    set template [file join $root runtime.ini];set ch [open $template {WRONLY CREAT EXCL}]
    try {
        fconfigure $ch -encoding utf-8 -translation lf
        puts $ch "\[config\]"
        foreach key [moduleConfigKeys $module] {putKV $ch $key [dict get $context config_snapshot $key]}
        puts $ch "\n\[workbench_extension\]"
        putKV $ch context [binary encode base64 -maxlen 0 [encoding convertto utf-8 $context]]
        putKV $ch action_id $action
    } finally {close $ch}
    set execution [scriptExecutionRunPackaged $module $template $root $action]
    set file [file join [dict get $execution output_dir] workbench-extension-result.tcldata]
    if {![file isfile $file]||[file type $file] eq "link"||[file size $file]>8388608} {error "Extension script did not return a bounded structured result through WORKBENCH_EXTENSION_API_v1.return_result"}
    set ch [open $file r];try {fconfigure $ch -encoding utf-8 -translation lf;set result [read $ch]} finally {close $ch}
    if {[catch {dict size $result}]} {error "Extension script returned malformed inert result data"}
    dict set result provenance script_sha256 [dict get $info sha256];dict set result provenance script_language [dict get $info language];dict set result provenance execution_run_id [dict get $execution run_id]
    return $result
}
