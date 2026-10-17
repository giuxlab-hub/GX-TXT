# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SignalAnalysisViewer {variable root [file dirname [info script]];variable state}
proc ::GX::SignalAnalysisViewer::apiInfo {} {return [dict create api_id SIGNAL_ANALYSIS_VIEWER_API_v1 api_version 1 scope {headless_service optional_gui} execution_owner SCIENTIFIC_EXECUTION_API_v1]}
proc ::GX::SignalAnalysisViewer::methods {} {::GX::modulePublicApiActivate math.signal SIGNAL_API_v1;return [::GX::SignalAPIv1::datasetMethods]}
proc ::GX::SignalAnalysisViewer::submit {parameters} {::GX::modulePublicApiActivate math.signal SIGNAL_API_v1;return [::GX::SignalAPIv1::datasetSubmit $parameters]}
proc ::GX::SignalAnalysisViewer::status {job} {return [::GX::scientificExecutionStatus $job]}
proc ::GX::SignalAnalysisViewer::cancel {job} {return [::GX::scientificExecutionCancel $job]}
proc ::GX::SignalAnalysisViewer::design {} {variable root;return [::GX::viewerGuiDesignRead [file join $root gui design.tcldict]]}
proc ::GX::SignalAnalysisViewer::handlers {} {set result {};foreach action {initialize load analyze publish cancel fit zoom_in zoom_out source_changed method_changed} {dict set result $action [dict create command ::GX::SignalAnalysisViewer::action]};return $result}
proc ::GX::SignalAnalysisViewer::open {{context {}}} {
    if {![::GX::viewerProviderEnabled viewer.signal_analysis signal_analysis]} {error {Signal Viewer graphical presentation is disabled}}
    set w .gxtxt_signal_analysis
    if {[winfo exists $w]} {raise $w;return $w}
    ::GX::viewerGuiDesignCompose [design] $w viewer.signal_analysis signal_analysis runtime [handlers] $context
    variable state;set state($w,session) [::GX::interactiveDocumentSessionToken]
    action $w method_changed
    return $w
}
proc ::GX::SignalAnalysisViewer::workspaceOpen {context} {return [::GX::viewerGuiDesignWorkspaceOpen viewer.signal_analysis signal_analysis [design] runtime [handlers] $context]}
proc ::GX::SignalAnalysisViewer::action {w action} {
    variable state
    if {![::GX::viewerGuiDesignGuard $w]} {error {This Signal Viewer belongs to a previous Session}}
    set values [::GX::viewerGuiDesignValues $w]
    switch -- $action {
        source_changed {
            set ids {};foreach v [::GX::datasetVariableSchemaV3 [dict get $values dataset]] {if {[dict get $v rank]==1 && [dict get $v dtype] ne {string} && [dict get $v enabled]} {lappend ids [dict get $v variable_id]}}
            foreach id {primary secondary time} {::GX::viewerGuiDesignChoicesSet $w $id [linsert $ids 0 {}]}
        }
        initialize - method_changed {
            set saved [::GX::viewerGuiDesignContextGet $w];if {[dict exists $saved job_id]} {set state($w,job) [dict get $saved job_id]}
            set operation [dict get $values operation];::GX::modulePublicApiActivate math.signal SIGNAL_API_v1
            set metadata [::GX::SignalAPIv1::operationSchema $operation]
            foreach id {window overlap} {::GX::viewerGuiDesignComponentVisible $w $id [expr {[string match spectral.* $operation] && $operation ne {spectral.periodogram}}]}
            foreach id {cutoff order} {::GX::viewerGuiDesignComponentVisible $w $id [string match filter.* $operation]}
            ::GX::viewerGuiDesignComponentVisible $w decimation [expr {$operation eq {multirate.decimate}}]
            ::GX::viewerGuiDesignComponentVisible $w normalization [string match correlation.* $operation]
            ::GX::viewerGuiDesignTextSet $w report "Provider-owned fields: [dict keys [dict get $metadata fields]]\nChoose data, then the scientific question. Time coordinates or an explicit sample rate are required for frequency/rate methods."
        }
        load {
            set dataset [dict get $values dataset];set x [dict get $values time];set y [dict get $values primary]
            if {$x eq {} || $y eq {}} {error {Choose explicit time and primary signal Variables for the interactive display}}
            ::GX::viewerGuiDesignSourceSet $w signal [dict create dataset_id $dataset x_variable_id $x y_variable_id $y display_budget 4096]
        }
        analyze {
            set parameters {};foreach {key component} {dataset_id dataset primary primary secondary secondary time time operation operation sample_rate sample_rate window window overlap overlap normalization normalization cutoff cutoff order order decimation decimation} {dict set parameters $key [dict get $values $component]}
            set receipt [submit $parameters];set state($w,job) [dict get $receipt job_id]
            ::GX::viewerGuiDesignContextSet $w [dict create job_id $state($w,job)]
            ::GX::viewerGuiDesignTextSet $w report "Submitted [dict get $receipt job_id]. Full-resolution scientific computation uses the managed CORE Job, independent of display LOD."
            after 350 [list ::GX::SignalAnalysisViewer::poll $w $state($w,job)]
        }
        cancel {if {[info exists state($w,publication)] && [dict exists $::GX::ScientificTableImport::tasks $state($w,publication)]} {::GX::scientificExecutionImportTableCancel $state($w,publication)} elseif {[info exists state($w,job)]} {set job [::GX::scientificExecutionStatus $state($w,job)];if {[dict get $job state] in {QUEUED PREPARING RUNNING FINALIZING}} {cancel $state($w,job)}}}
        publish {
            if {![info exists state($w,job)]} {error {Analyze a source first}}
            set output {}
            foreach item [dict get [::GX::scientificExecutionOutputs $state($w,job)] outputs] {if {[dict get $item role] eq {signal_result}} {set output $item}}
            if {$output eq {}} {error {This operation has no vector table. Its scalar report remains available in Job outputs.}}
            set job [::GX::_scientificExecutionJob $state($w,job)]
            set source [dict get $job scientific_request parameters dataset_id]
            set definition [dict create dataset_id [dict get $values output_id] contract table.generic storage hdf5 source_dataset_ids [list $source] provenance "Signal [dict get $job scientific_request parameters operation]; managed Job $state($w,job); unchanged public provider columns" notes {Complex components retain explicit real/imaginary identities. Blank units are unavailable.}]
            set state($w,publication) [::GX::scientificExecutionImportTable $state($w,job) [dict get $output token] viewer.signal_analysis $definition [list ::GX::SignalAnalysisViewer::published $w]]
        }
        fit - zoom_in - zoom_out {return [::GX::viewerGuiDesignAction $w $action]}
    }
    return [dict create status completed]
}
proc ::GX::SignalAnalysisViewer::poll {w id} {
    if {![winfo exists $w] || ![::GX::viewerGuiDesignGuard $w]} return
    ::GX::scriptJobAsync [::GX::scriptJobCommand describe $id] {} [list ::GX::SignalAnalysisViewer::polled $w $id]
}
proc ::GX::SignalAnalysisViewer::polled {w id response} {
    if {![winfo exists $w] || ![::GX::viewerGuiDesignGuard $w]} return
    if {![dict get $response ok]} {::GX::viewerGuiDesignTextSet $w report [dict get $response error];return}
    set job [dict get $response result];set status [dict get $job state]
    ::GX::viewerGuiDesignTextSet $w report "Job $id: $status\n[::GX::datasetPublicationV2DictDefault $job error {}]"
    if {$status in {QUEUED PREPARING RUNNING FINALIZING}} {after 500 [list ::GX::SignalAnalysisViewer::poll $w $id]} else {
        if {$status eq {COMPLETED}} {foreach item [dict get [::GX::scientificExecutionOutputs $id] outputs] {if {[dict get $item role] eq {summary}} {set page [::GX::scientificExecutionReadOutput $id [dict get $item token] 0 65536];::GX::viewerGuiDesignTextSet $w report [encoding convertfrom utf-8 [binary decode base64 [dict get $page bytes_base64]]]}}}
    }
}
proc ::GX::SignalAnalysisViewer::published {w response} {
    if {![winfo exists $w] || ![::GX::viewerGuiDesignGuard $w]} return
    if {[dict get $response ok]} {
        if {[catch {
            set dataset [dict get [::GX::viewerGuiDesignValues $w] output_id]
            set schema [::GX::datasetVariableSchemaV3 $dataset]
            if {[llength $schema]>=2} {
                ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
                set x [dict get [lindex $schema 0] variable_id];set y [dict get [lindex $schema 1] variable_id]
                set spec [::GX::PlotDatasetAPIv4::newSpec -title "Signal result: $dataset"]
                set panel [lindex [dict get $spec panels] 0]
                dict set panel series [list [dict create id signal_result dataset_id $dataset x_variable_id $x y_variable_id $y axis left kind line label $y]]
                dict set spec panels [list $panel]
                set ref [::GX::PlotDatasetAPIv4::upsertPlotFromSpec viewer.signal_analysis "viewer.signal_analysis:$dataset" $spec]
                ::GX::PlotDatasetAPIv4::render $ref
                dict set response plot $ref
                ::GX::viewerGuiDesignSourceSet $w signal [dict create dataset_id $dataset x_variable_id $x y_variable_id $y display_budget 4096]
            }
        } reason]} {dict set response plot_diagnostic $reason}
    }
    ::GX::viewerGuiDesignTextSet $w report $response;::GX::refreshResults
}
proc ::GX::SignalAnalysisViewer::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister gxtxt_signal_analysis ::GX::SignalAnalysisViewer::dispatch

# Official Builder exports preserve these scientific callbacks.
namespace eval ::GX::Generated_viewer_signal_analysis::Handlers {}
proc ::GX::Generated_viewer_signal_analysis::Handlers::load {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::analyze {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::publish {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::cancel {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::fit {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::zoom_in {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::zoom_out {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::source_changed {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::method_changed {window action} {tailcall ::GX::SignalAnalysisViewer::action $window $action}
proc ::GX::Generated_viewer_signal_analysis::Handlers::initialize {window action} {tailcall ::GX::SignalAnalysisViewer::action $window initialize}
