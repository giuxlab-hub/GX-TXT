# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::StatisticalAnalysisViewer {variable root [file dirname [info script]];variable state}
proc ::GX::StatisticalAnalysisViewer::apiInfo {} {return [dict create api_id STATISTICAL_ANALYSIS_VIEWER_API_v1 api_version 1 scope {headless_service optional_gui} execution_owner MODULE_TARGETED_ANALYSIS_API_v1]}
proc ::GX::StatisticalAnalysisViewer::providers {} {
    set result {}
    foreach id $::GX::moduleOrder {if {[string match analysis.statistics.* $id] && [::GX::moduleField $id kind {}] eq {analysis}} {lappend result [dict merge [::GX::moduleAnalysisCapabilities $id] [dict create name [::GX::moduleField $id name] analysis_visible [::GX::moduleIsEnabled $id] fields [::GX::configurationModuleFields $id]]]}}
    return $result
}
proc ::GX::StatisticalAnalysisViewer::submit {module request} {return [::GX::moduleAnalysisSubmit viewer.statistical_analysis $module $request]}
proc ::GX::StatisticalAnalysisViewer::status {module run} {return [::GX::moduleAnalysisStatus viewer.statistical_analysis $module $run]}
proc ::GX::StatisticalAnalysisViewer::cancel {module run} {return [::GX::moduleAnalysisCancel viewer.statistical_analysis $module $run]}
proc ::GX::StatisticalAnalysisViewer::design {} {variable root;return [::GX::viewerGuiDesignRead [file join $root gui design.tcldict]]}
proc ::GX::StatisticalAnalysisViewer::handlers {} {set result {};foreach id {initialize source_changed method_changed run cancel inspect preview plot settings} {dict set result $id [dict create command ::GX::StatisticalAnalysisViewer::action]};return $result}
proc ::GX::StatisticalAnalysisViewer::open {{context {}}} {
    if {![::GX::viewerProviderEnabled viewer.statistical_analysis statistical_analysis]} {error {Statistical Viewer graphical presentation is disabled}}
    set w .gxtxt_statistical_analysis
    if {[winfo exists $w]} {raise $w;return $w}
    ::GX::viewerGuiDesignCompose [design] $w viewer.statistical_analysis statistical_analysis runtime [handlers] $context
    action $w method_changed
    return $w
}
proc ::GX::StatisticalAnalysisViewer::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.statistical_analysis statistical_analysis [design] runtime [handlers] $context]}
proc ::GX::StatisticalAnalysisViewer::table {variables} {
    set rows {};set n 0
    foreach variable $variables {lappend rows [dict create id row[incr n] values [dict create variable $variable]]}
    return [dict create api_id REPEATABLE_CONFIG_API_v1 rows $rows]
}
proc ::GX::StatisticalAnalysisViewer::action {w action} {
    variable state
    if {![::GX::viewerGuiDesignGuard $w]} {error {Statistical Viewer belongs to a previous Session}}
    set values [::GX::viewerGuiDesignValues $w];set module [dict get $values method]
    switch -- $action {
        initialize - method_changed {
            set methods {};foreach provider [providers] {lappend methods [dict get $provider module_id]}
            ::GX::viewerGuiDesignChoicesSet $w method $methods
            if {$module ni $methods} {if {$methods eq {}} {error {No compatible statistical Analysis provider is installed}};set module [lindex $methods 0];::GX::viewerGuiDesignValueSet $w method $module;set values [::GX::viewerGuiDesignValues $w]}
            set keys [::GX::moduleConfigKeys $module]
            foreach component [dict get [design] components] {
                set id [dict get $component id]
                if {![string match param_* $id]} continue
                set key [string range $id 6 end]
                ::GX::viewerGuiDesignComponentVisible $w $id [expr {$key in $keys}]
                if {$action ne {initialize} && $key in $keys && [info exists ::GX::moduleCfg($module,$key)]} {::GX::viewerGuiDesignValueSet $w $id $::GX::moduleCfg($module,$key)}
            }
            set reason [::GX::moduleField $module config_hint {}]
            ::GX::viewerGuiDesignTextSet $w report "[::GX::moduleField $module name]\n$reason\nSelect the scientific Dataset and stable Variable IDs. Analysis-page visibility does not control this authorized service call."
            if {[dict get $values dataset] ne {}} {action $w source_changed}
        }
        source_changed {
            set ids {};foreach variable [::GX::datasetVariableSchemaV3 [dict get $values dataset]] {if {[dict get $variable enabled]} {lappend ids [dict get $variable variable_id]}}
            foreach key [::GX::moduleConfigKeys $module] {
                if {[::GX::moduleConfigField $module $key type {}] eq {variable}} {::GX::viewerGuiDesignChoicesSet $w param_$key [linsert $ids 0 {}]}
            }
            foreach axis {x_variable y_variable} {::GX::viewerGuiDesignChoicesSet $w $axis [linsert $ids 0 {}]}
        }
        run {
            set request [dict create session_token [::GX::interactiveDocumentSessionToken] sources [dict create primary [dict get $values dataset]] config {} tables {}]
            foreach key [::GX::moduleConfigKeys $module] {
                if {![dict exists $values param_$key]} continue
                set value [dict get $values param_$key];set type [::GX::moduleConfigField $module $key type string]
                if {$type eq {table}} {
                    set variables [::GX::splitList $value];if {$variables ne {}} {dict set request tables $key [table $variables]}
                } else {dict set request config $key $value}
            }
            set receipt [submit $module $request];set state($w,receipt) $receipt
            ::GX::viewerGuiDesignContextSet $w [dict create module_id $module run_id [dict get $receipt run_id]]
            ::GX::viewerGuiDesignTextSet $w report "Started exactly $module. Run-tab selections remain unchanged.\n$receipt"
            after 350 [list ::GX::StatisticalAnalysisViewer::poll $w $module [dict get $receipt run_id]]
        }
        cancel {if {[info exists state($w,receipt)]} {cancel [dict get $state($w,receipt) module_id] [dict get $state($w,receipt) run_id]}}
        inspect {::GX::viewerGuiDesignTextSet $w report [::GX::sessionInspectionResults $::GX::currentSession]}
        plot {
            ::GX::viewerGuiDesignSourceSet $w scatter [dict create dataset_id [dict get $values dataset] x_variable_id [dict get $values x_variable] y_variable_id [dict get $values y_variable] display_budget 4096]
        }
        settings {::GX::configurationModuleDialog $module $w}
        preview {
            ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
            set source [dict get $values dataset];set variable [dict get $values y_variable]
            set raw [::GX::NumericAPIv1::statisticsDataset $::GX::currentSession $source $variable {nonfinite omit}]
            set semantic [::GX::StatisticsV1::fromNumeric math.numeric.summary dataset_statistics $raw {mean_se_model none sampling_model unspecified} {} [dict create producer viewer.statistical_analysis source_dataset_id $source source_variable_id $variable]]
            set result [::GX::StatisticsV1::report $semantic {n mean minimum maximum median standard_deviation_population standard_deviation}]
            ::GX::viewerGuiDesignTextSet $w report "Nonpublishing descriptive preview; no sampling or uncertainty model is assumed.\n$result"
        }
    }
    return [dict create status completed]
}
proc ::GX::StatisticalAnalysisViewer::poll {w module run} {
    if {![winfo exists $w] || ![::GX::viewerGuiDesignGuard $w]} return
    set receipt [status $module $run]
    ::GX::viewerGuiDesignTextSet $w report "[::GX::moduleField $module name]\n$receipt"
    if {[dict get $receipt state] eq {RUNNING}} {after 500 [list ::GX::StatisticalAnalysisViewer::poll $w $module $run]} else {::GX::refreshResults}
}
proc ::GX::StatisticalAnalysisViewer::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister gxtxt_statistical_analysis ::GX::StatisticalAnalysisViewer::dispatch

# Official Builder exports preserve these scientific callbacks.
namespace eval ::GX::Generated_viewer_statistical_analysis::Handlers {}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::source_changed {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::method_changed {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::run {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::cancel {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::inspect {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::preview {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::plot {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::settings {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_statistical_analysis::Handlers::initialize {window action} {tailcall ::GX::StatisticalAnalysisViewer::action $window initialize}
