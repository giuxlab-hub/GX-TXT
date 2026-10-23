# SPDX-License-Identifier: GPL-3.0-or-later
# Fixed headless public-owner operations for the shared development backend.
lassign $argv framework operation
set arguments [lrange $argv 2 end]
proc ::gxtxtViewerDevelopmentRequestPhase {phase} {
    # Developer diagnostics only; stdout remains the existing typed response.
    catch {puts stderr [list GXTXT_DEVELOPMENT_PHASE [clock microseconds] $phase];flush stderr}
}
set argv0 __gxtxt_viewer_development_core_request__
::gxtxtViewerDevelopmentRequestPhase source_begin
source [file join [file normalize $framework] gxtxt_pipeline.tcl]
::gxtxtViewerDevelopmentRequestPhase source_complete
::GX::defaults
::gxtxtViewerDevelopmentRequestPhase defaults_complete
::GX::loadModuleCatalog
::gxtxtViewerDevelopmentRequestPhase catalog_complete
proc ::GX::_viewerDevelopmentCatalogAdd {target api row} {
    upvar 1 $target result
    set prior [::GX::datasetPublicationV2DictDefault $result $api {}]
    set providers [::GX::datasetPublicationV2DictDefault $prior providers {}]
    set merged 0;set index 0
    foreach provider $providers {
        if {[dict get $provider provider] eq [dict get $row provider] && [dict get $provider version] eq [dict get $row version]} {lset providers $index [dict merge $provider $row];set merged 1;break}
        incr index
    }
    if {!$merged} {lappend providers $row}
    dict set result $api [dict merge $prior $row [dict create providers $providers]]
}
proc ::GX::_viewerDevelopmentRequestApiCatalog {} {
    set result {}
    foreach module $::GX::moduleOrder {
        set path [::GX::moduleField $module descriptor {}]
        if {$path eq {}} continue
        set d [::GX::parseIni $path]
        foreach api [::GX::splitList [::GX::descriptorValue $d public_apis ids {}]] {
            set section public_api.$api
            set documentation [::GX::descriptorValue $d $section documentation docs/api/$api.md]
            set manual [::GX::documentationResolveApiRef $api]
            if {[file isfile $manual] && [string first "$::GX::scriptDir/" "$manual/"]==0} {set documentation [string range $manual [expr {[string length $::GX::scriptDir]+1}] end]}
            set row [dict create api_id $api version [::GX::descriptorValue $d $section api_version {}] provider $module provider_version [::GX::moduleField $module version] enabled [::GX::moduleIsEnabled $module] name [::GX::descriptorValue $d $section name {}] capabilities [::GX::descriptorValue $d $section capabilities {}] documentation $documentation declaration_ref plugins/modules/$module/module.ini declaration_sha256 [::GX::sha256File $path] deprecated [::GX::descriptorValue $d $section deprecated 0] superseded_by [::GX::descriptorValue $d $section superseded_by {}] new_viewer_admission [::GX::descriptorValue $d $section new_viewer_admission reviewed_sdk_only]]
            if {[catch {set contract [::GX::modulePublicApiDocumentation $module $api]} reason]} {
                dict set row metadata_error $reason
            } elseif {$contract ne {}} {
                dict set row summary [dict get $contract purpose]
                dict set row host_operation_contracts [dict get $contract operations]
                dict set row operations [dict keys [dict get $contract operations]]
                dict set row host_context [::GX::datasetPublicationV2DictDefault $contract context {}]
            }
            ::GX::_viewerDevelopmentCatalogAdd result $api $row
        }
    }
    dict for {api command} [::GX::workbenchExtensionCoreApis] {
        regexp {_v([0-9]+)$} $api -> version
        set row [dict create api_id $api version $version provider CORE enabled [expr {[llength [info commands $command]]>0}] operations {} documentation docs/api/$api.md host_entrypoint $command]
        if {[llength [info procs $command]]} {
            set signature {}
            foreach argument [info args $command] {set optional [info default $command $argument default];lappend signature [dict create name $argument required [expr {!$optional && $argument ne {args}}] default [expr {$optional?$default:{}}]]}
            dict set row host_arguments $signature
        }
        if {[string match -nocase *apiinfo* $command] && [llength [info commands $command]]} {
            if {![catch {$command} metadata]} {set row [dict merge $row $metadata]} else {dict set row metadata_error $metadata}
        }
        ::GX::_viewerDevelopmentCatalogAdd result $api $row
    }
    foreach {api command} {STATISTICAL_RESULT_SEMANTICS_API_v1 ::GX::StatisticsV1::apiInfo VIEWER_DEVELOPMENT_API_v1 ::GX::viewerDevelopmentApiInfo NATIVE2D_VIEWPORT_HOST_v1 ::GX::native2DViewportHostApiInfo SCIENTIFIC_EXECUTION_API_v1 ::GX::scientificExecutionApiInfo SCRIPT_JOB_API_v1 ::GX::scriptJobApiInfo PARALLEL_EXECUTION_API_v1 ::GX::parallelExecutionApiInfo VIEWER_GUI_HOST_API_v1 ::GX::viewerGuiHostApiInfo VIEWER_COMPONENT_DEMO_API_v1 ::GX::viewerGuiComponentDemoApiInfo NATIVE_3D_GUI_HOST_API_v1 ::GX::native3DGuiHostApiInfo NATIVE_3D_GUI_HOST_API_v2 ::GX::native3DGuiHostApiInfoV2 NATIVE2D_TEMPORARY_DISPLAY_API_v1 ::GX::native2DTemporaryDisplayApiInfo NATIVE_PLOT_DISPLAY_API_v1 ::GX::nativePlotDisplayApiInfo SOURCE_SURFACE_API_v1 ::GX::sourceSurfaceApiInfo UI_FIELD_API_v1 ::GX::uiFieldApiInfo} {
        set meta [$command];::GX::_viewerDevelopmentCatalogAdd result $api [dict merge $meta [dict create api_id $api version [dict get $meta api_version] provider CORE enabled 1 documentation docs/api/$api.md]]
    }
    # Restricted declared forms project only existing host Transform operations.
    # Keep the general public registry/Script entrypoint unchanged.
    set meta [::GX::datasetTransformResponsiveApiInfo]
    dict set meta operations {execute_responsive cancel provenance}
    ::GX::_viewerDevelopmentCatalogAdd result DATASET_TRANSFORM_API_v1 [dict merge $meta [dict create api_id DATASET_TRANSFORM_API_v1 version 1 provider CORE enabled 1 documentation docs/api/DATASET_TRANSFORM_API_v1.md host_only 1]]
    # Analysis run selection does not disable the bundled Plot service.
    # Verify its real public activation; never set an analysis/config flag.
    if {[dict exists $result PLOT_DATASET_API_v4] && [file normalize [::GX::moduleField plot.dataset descriptor]] eq [file normalize [file join $::GX::scriptDir plugins modules plot.dataset module.ini]]} {
        dict set result PLOT_DATASET_API_v4 available [expr {![catch {::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4}]}]
        dict set result PLOT_DATASET_API_v4 availability_scope public_service_activation
    }
    if {[dict exists $result ELECTROMAGNETIC_SIMULATION_API_v1] && [file normalize [::GX::moduleField math.electromagnetic_simulation descriptor]] eq [file normalize [file join $::GX::scriptDir plugins modules math.electromagnetic_simulation module.ini]]} {
        dict set result ELECTROMAGNETIC_SIMULATION_API_v1 available [expr {![catch {::GX::modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1}]}]
        dict set result ELECTROMAGNETIC_SIMULATION_API_v1 availability_scope public_service_activation
    }
    return $result
}
::gxtxtViewerDevelopmentRequestPhase operation_begin
try {
    switch $operation {
        diagram_tool_validate {
            if {[llength $arguments]!=2} {error {Diagram tool validation requires catalog and tool}}
            lassign $arguments catalog tool
            set symbols [dict get [::GX::native2DGeometryDiagramCatalog $catalog] symbols]
            if {$tool ni {select wire junction label pan probe} && ![dict exists $symbols $tool]} {error {Tool is not exposed by the declared diagram catalog}}
            set result [dict create catalog $catalog tool $tool validated 1]
        }
        builder_edit {
            if {[llength $arguments]!=2} {error {Builder requires a project design path and typed request}}
            lassign $arguments path request
            if {[lsort [dict keys $request]] ne {arguments operation}} {error {Invalid Builder request fields}}
            set design [::GX::viewerGuiDesignRead $path]
            set op [dict get $request operation];set args [dict get $request arguments]
            if {$op eq {icon} && [lindex $args 0] eq {catalog}} {
                if {[llength $args]!=1} {error {Shared icon discovery accepts no path or arguments}}
                set result [dict create status INSPECTED operation icon_catalog catalog [::GX::viewerGuiIconCatalog]]
            } else {
            # The existing model retains fifty full design snapshots plus its
            # current/saved designs. Bound the whole serialized history, rather
            # than reusing one design's 4 MiB limit after writing larger files.
            set historyLimit 536870912
            set responseLimit 16777216
            set priorHistoryExists [file exists [file join [file dirname $path] derived builder-model.tcldict]]
            set priorHistoryBytes {}
            set f [open $path rb];try {set priorDesignBytes [read $f 4194305]} finally {close $f}
            set modelPath [file join [file dirname $path] derived builder-model.tcldict]
            set model [::GX::viewerGuiDesignModelCreate $design]
            if {$priorHistoryExists} {
                file lstat $modelPath info
                if {$info(type) ne {file} || $info(nlink)!=1 || $info(size)>$historyLimit} {error {Builder history must be an ordinary bounded file}}
                set f [open $modelPath rb];try {set priorHistoryBytes [read $f [expr {$historyLimit+1}]]} finally {close $f}
                if {[string length $priorHistoryBytes]>$historyLimit} {error {Builder history exceeds bound}}
                set saved [encoding convertfrom utf-8 $priorHistoryBytes]
                if {[lsort [dict keys $saved]] ne {design future past revision saved schema} || [dict get $saved schema] ne {gxtxt.viewer_design_model.v1} || ![string is integer -strict [dict get $saved revision]] || [dict get $saved revision]<0 || [llength [dict get $saved past]]+[llength [dict get $saved future]]>50} {error {Invalid Builder history schema/states}}
                foreach snapshot [concat [list [dict get $saved design] [dict get $saved saved]] [dict get $saved past] [dict get $saved future]] {
                    if {[string length [encoding convertto utf-8 $snapshot]]>4194304 || [dict get $snapshot schema] ne {gxtxt.viewer_design.v1}} {error {Invalid bounded Builder history snapshot}}
                }
                # External GUI edits invalidate only the CLI history, never the design.
                if {[string trim [dict get $saved design]] eq [string trim $design]} {set model $saved}
            }
            set op [dict get $request operation];set args [dict get $request arguments]
            if {$op in {undo redo}} {
                if {[llength $args]} {error {Undo/Redo take no arguments}}
                set model [::GX::viewerGuiDesignModelNavigate $model $op]
            } elseif {$op eq {icon_import}} {
                if {[llength $args]!=5} {error {Icon import requires five typed arguments}}
                lassign $args image id title category license
                if {![catch {dict size $image}] && [dict exists $image source_format]} {
                    if {[lsort [dict keys $image]] ne {source source_format} || [dict get $image source_format] ne {svg}} {error {Inline icon source requires SVG text}}
                    set asset [::GX::viewerGuiIconImportSvg [dict get $image source] $title $category $license]
                } else {set asset [::GX::viewerGuiIconImport $image $title $category $license]}
                set model [::GX::viewerGuiDesignModelEdit $model icon put $id $asset]
            } elseif {$op ne {inspect}} {
                if {$op ni {add property properties layout constraints bind remove duplicate reparent reorder metadata icon}} {error {Unsupported public Builder edit}}
                set model [::GX::viewerGuiDesignModelEdit $model $op {*}$args]
            }
            set design [::GX::viewerGuiDesignValidate [dict get $model design]]
            set result [dict create status SAVED operation $op revision [dict get $model revision] design $design capabilities [::GX::viewerGuiComponentCapabilities]]
            set designBytes [encoding convertto utf-8 $design]
            set historyBytes [encoding convertto utf-8 $model]
            if {[string length $designBytes]>4194304 || [string length $historyBytes]>$historyLimit || [string length [encoding convertto utf-8 [dict create ok 1 result $result]]]>$responseLimit} {error {Builder design/history/response exceeds its bounded contract; previous files retained}}
            if {$op ne {inspect}} {
                set f [open $path rb];try {set currentDesignBytes [read $f 4194305]} finally {close $f}
                if {$currentDesignBytes ne $priorDesignBytes || [file exists $modelPath]!=$priorHistoryExists} {error {Builder files changed during this request; retry from current state}}
                if {$priorHistoryExists} {
                    set f [open $modelPath rb];try {set currentHistoryBytes [read $f [expr {$historyLimit+1}]]} finally {close $f}
                    if {$currentHistoryBytes ne $priorHistoryBytes} {error {Builder history changed during this request; retry from current state}}
                }
                try {
                    ::GX::resourceLifecycleWriteBytes $path $designBytes
                    ::GX::resourceLifecycleWriteBytes $modelPath $historyBytes
                } on error {problem options} {
                    # Existing atomic-per-file writes, with ordinary-error
                    # rollback across the pair; no crash-atomicity is claimed.
                    set rollbackErrors {}
                    foreach {target existed previous} [list $path 1 $priorDesignBytes $modelPath $priorHistoryExists $priorHistoryBytes] {
                        if {$existed} {
                            set unchanged 0
                            catch {set f [open $target rb];try {set unchanged [expr {[read $f [expr {$historyLimit+1}]] eq $previous}]} finally {close $f}}
                            if {!$unchanged && [catch {::GX::resourceLifecycleWriteBytes $target $previous} reason]} {lappend rollbackErrors $reason}
                        } elseif {[file exists $target] && [catch {file delete -- $target} reason]} {lappend rollbackErrors $reason}
                    }
                    if {[llength $rollbackErrors]} {return -options $options "Builder commit failed; rollback incomplete: [join $rollbackErrors {; }]. Original failure: $problem"}
                    return -options $options $problem
                }
            }
            }
        }
        new_design {
            if {[llength $arguments]!=1} {error {new_design requires one module ID}}
            set module [lindex $arguments 0]
            set d [::GX::viewerGuiDesignNew];dict set d module_id $module;dict set d title {Restricted C++ demonstration};dict set d provider_id development_example
            dict set d requirements NATIVE2D_VIEWPORT_HOST_v1 1
            dict set d components {{id readout type status parent inspector properties {text {Synthetic temperature · ready}} layout {row 0 column 0 sticky ew}} {id description type label parent inspector properties {text {C++ handler output appears here. No scientific Dataset is created.} wraplength 250} layout {row 1 column 0 sticky ew}} {id graphics type native2d parent canvas properties {title {RAM native demo}} layout {row 0 column 0 weight 1 sticky nsew}} {id advance type action parent toolbar properties {label {Run C++ handler} action advance event_value 18} layout {row 0 column 0}}}
            dict set d handlers advance {arguments {window action} effect presentation label {Run C++ handler}}
            set result [::GX::viewerGuiDesignValidate $d]
        }
        runtime_design {
            if {[llength $arguments]!=1} {error {Compiled runtime admission requires its interface path}}
            set design [::GX::viewerGuiDesignRead [lindex $arguments 0]]
            set tools {}
            foreach component [dict get $design components] {
                if {[dict get $component type] ne {native2d}} continue
                set catalog [::GX::datasetPublicationV2DictDefault [dict get $component properties] diagram_catalog {}]
                if {$catalog ne {}} {dict set tools $catalog [concat {select wire junction label pan probe} [dict keys [dict get [::GX::native2DGeometryDiagramCatalog $catalog] symbols]]]}
            }
            set result [dict create design $design catalog [::GX::_viewerDevelopmentRequestApiCatalog] diagram_tools $tools]
        }
        validate_design {
            if {[llength $arguments] ni {1 2} || ([llength $arguments]==2 && [lindex $arguments 1] ne {with_catalog})} {error {validate_design requires one inert design path and optional with_catalog}}
            set result [::GX::viewerGuiDesignRead [lindex $arguments 0]]
            ::GX::_viewerGuiTeXDesignValidate $result 1
            if {[llength $arguments]==2} {set result [dict create design $result catalog [::GX::_viewerDevelopmentRequestApiCatalog]]}
        }
        numeric_add - numeric_sqrt - numeric_exp {
            if {[llength $arguments]!=($operation eq {numeric_add}?2:1)} {error {Numeric SDK scalar argument count differs}}
            foreach value $arguments {::GX::uiFieldNormalize {type number} $value}
            set descriptor [file normalize [::GX::moduleField math.numeric descriptor]]
            if {$descriptor ne [file normalize [file join $::GX::scriptDir plugins modules math.numeric module.ini]]} {error {Numerical provider must be the trusted bundled public owner}}
            ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
            if {$operation eq {numeric_add}} {
                set result [::GX::NumericAPIv1::arrayBinary add [dict create kind scalar value [lindex $arguments 0]] [dict create kind scalar value [lindex $arguments 1]]]
            } else {set result [::GX::NumericAPIv1::arrayUnary [expr {$operation eq {numeric_exp}?{exp}:{sqrt}}] [dict create kind scalar value [lindex $arguments 0]]]}
        }
        api_catalog {
            if {[llength $arguments]} {error {api_catalog takes no arguments}}
            set result [::GX::_viewerDevelopmentRequestApiCatalog]
        }
        default {error {Unknown fixed development CORE operation}}
    }
    ::gxtxtViewerDevelopmentRequestPhase operation_complete
    puts [dict create ok 1 result $result]
    flush stdout
    ::gxtxtViewerDevelopmentRequestPhase response_flushed
} on error {message options} {
    ::gxtxtViewerDevelopmentRequestPhase operation_failed
    puts [dict create ok 0 error $message code [expr {$operation in {numeric_add numeric_sqrt numeric_exp}?{NUMERIC_DOMAIN}:{CORE_API_GAP}}]]
    flush stdout
    ::gxtxtViewerDevelopmentRequestPhase failure_response_flushed
    exit 1
}
