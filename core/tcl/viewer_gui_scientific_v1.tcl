# SPDX-License-Identifier: GPL-3.0-or-later
# Typed declared form bindings; existing Scientific Execution owns every Job.
source [file join [file dirname [info script]] viewer_gui_scientific_netlist_v1.tcl]
proc ::GX::_viewerGuiScientificDesignValidate {design} {
    _viewerGuiScientificNetlistDesignValidate $design
    set definitions {};foreach component [dict get $design components] {dict set definitions [dict get $component id] $component}
    foreach definition [dict get $design components] {
        set p [dict get $definition properties]
        foreach key {scientific_probe_diagram scientific_probe_plot scientific_probe_mode scientific_probe_ac_form} {
            if {[dict exists $p $key] && ![dict exists $p scientific_provider]} {error {Scientific probe references belong to a complete declared Scientific section}}
        }
        if {[dict get $definition type] ne {section} || ![dict exists $p scientific_provider]} continue
        foreach key {scientific_parameters scientific_destination scientific_status scientific_log} {if {![dict exists $p $key]} {error "Scientific form requires $key"}}
        foreach {key types} {scientific_destination {choice combobox} scientific_status {status label} scientific_log {log}} {
            set target [dict get $p $key]
            if {![dict exists $definitions $target] || [dict get $definitions $target type] ni $types} {error "Invalid declared scientific control $key"}
        }
        if {[dict size [dict get $p scientific_parameters]]>32} {error {Scientific parameter form exceeds32 fields}}
        set schema [dict get $::GX::ScientificExecution::providers [dict get $p scientific_provider] parameters]
        dict for {key target} [dict get $p scientific_parameters] {
            if {![dict exists $schema $key] || ![dict exists $definitions $target] || [dict get $definitions $target type] ni {field choice entry combobox toggle checkbutton}} {error "Invalid scientific parameter/control binding $key"}
        }
        _viewerGuiScientificSweepValidate $definitions $p
        set probeKeys {scientific_probe_diagram scientific_probe_plot scientific_probe_mode}
        set probePresent 0;foreach key $probeKeys {if {[dict exists $p $key]} {incr probePresent}}
        if {[dict exists $p scientific_probe_ac_form] && $probePresent!=3} {error {An explicit AC probe form requires the complete diagram/Plot/mode probe references}}
        if {$probePresent} {
            if {$probePresent!=3} {error {Scientific probing requires diagram, Plot and voltage/current mode references}}
            foreach {key type} {scientific_probe_diagram native2d scientific_probe_plot plot} {
                if {![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ne $type} {error "Invalid scientific probe target $key"}
            }
            if {[datasetPublicationV2DictDefault [dict get $definitions [dict get $p scientific_probe_diagram] properties] diagram_catalog {}] ne {electrical.basic} || ![dict exists $definitions [dict get $p scientific_probe_plot] properties plot_form]} {error {Scientific probe needs the declared electrical diagram and canonical Plot form}}
            set mode [dict get $p scientific_probe_mode]
            if {![dict exists $definitions $mode] || [dict get $definitions $mode type] ni {choice combobox} || ![dict exists $definitions $mode properties choices] || [lrange [dict get $definitions $mode properties choices] 0 end] ne {voltage current}} {error {Scientific probe mode requires an explicit voltage/current choice}}
            if {[dict exists $p scientific_probe_ac_form]} {
                set target [dict get $p scientific_probe_ac_form]
                if {![dict exists $definitions $target] || [dict get $definitions $target type] ne {section} || [datasetPublicationV2DictDefault [dict get $definitions $target properties] numeric_kind {}] ne {complex_projection}} {error {AC probe form must reference a declared complex_projection Numeric section}}
                if {[dict exists $definitions $target properties numeric_source] && [dict get $definitions $target properties numeric_source] ne [dict get $p scientific_probe_diagram]} {error {AC probe form must belong to the same declared diagram}}
            }
        }
        if {[dict exists $p scientific_sweep_axes]} {foreach api {NUMERIC_API_v1 PARALLEL_EXECUTION_API_v1} {if {![dict exists $design requirements $api] || [dict get $design requirements $api]!=1} {error "Physical sweep form requires $api@1"}}}
    }
}
proc ::GX::_viewerGuiScientificForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Scientific Viewer belongs to a previous Session lifetime}}
    set definition [viewerGuiDesignComponent $window $form]
    set properties [dict get $definition properties]
    if {[dict get $definition type] ne {section} || [datasetPublicationV2DictDefault $properties scientific_provider {}] ne {core.ngspice.circuit}} {error {Declare the supported registered scientific provider on a section}}
    foreach key {scientific_parameters scientific_destination scientific_status scientific_log} {if {![dict exists $properties $key]} {error "Scientific form requires $key"}}
    return $properties
}
proc ::GX::viewerGuiDesignScientificProbe {window form endpoint {hitContext {}}} {
    try {
        set p [_viewerGuiScientificForm $window $form]
        foreach key {scientific_probe_diagram scientific_probe_plot scientific_probe_mode} {if {![dict exists $p $key]} {error {Declare diagram, Plot and mode references for scientific probing}}}
        set diagram [dict get $p scientific_probe_diagram];set plot [dict get $p scientific_probe_plot]
        set plotDefinition [viewerGuiDesignComponent $window $plot]
        set plotForm [dict get $plotDefinition properties plot_form]
        set plotProperties [_viewerGuiPlotForm $window $plotForm]
        set values [viewerGuiDesignValues $window]
        set mode [dict get $values [dict get $p scientific_probe_mode]]
        if {$mode ni {voltage current}} {error {Select voltage or current probe mode}}
        if {$mode eq {current} && [datasetPublicationV2DictDefault $hitContext hit_kind terminal] eq {wire}} {error {An arbitrary ideal-wire location has no defined branch-current observable. Select a supported device terminal; this solver exposes independent voltage-source branch current.}}
        set binding [dict get $::GX::ViewerGui::instances $window bindings $diagram]
        if {[dict get $binding kind] ne {diagram}} {error {Scientific probe needs the canonical electrical diagram}}
        if {[datasetPublicationV2DictDefault $hitContext hit_kind terminal] eq {wire}} {
            set owner [native2DGeometryDiagramRead [dict get $binding document_id]]
            if {![dict exists $owner payload wires [dict get $hitContext wire_id]] || [dict get $owner payload wires [dict get $hitContext wire_id] start] ne $endpoint} {error {Wire probe no longer refers to the current canonical electrical wire}}
            _native2DDiagramWireTargets [dict get $owner payload] [list [dict create kind wire wire_id [dict get $hitContext wire_id] point [dict get $hitContext point]]]
        }
        set job [_viewerGuiScientificJob $window $form]
        _scientificExecutionPublicationGuard [dict get $job source_guard]
        if {[dict get $job source_guard document_id] ne [dict get $binding document_id] || [datasetPublicationV2DictDefault $job last_status {}] ne {COMPLETED}} {error {Probe requires this source's completed published Job or selected sweep case}}
        set dataset [dict get $values [dict get $plotProperties plot_dataset]]
        if {[datasetPublicationV2DictDefault $job dataset_id {}] ne $dataset} {error {Selected Dataset does not belong to this published Job or selected sweep case}}
        set metadata [datasetMetadataRead $::GX::currentSession $dataset]
        foreach {key expected} [list scientific_execution.job_id [dict get $job job_id] scientific_execution.circuit_sha256 [dict get $job circuit_sha256] scientific_execution.provider_id [dict get $p scientific_provider] scientific_execution.parameters [dict get $job parameters]] {
            if {![dict exists $metadata $key] || [dict get $metadata $key] ne $expected} {error "Published Dataset provenance differs: $key"}
        }
        set inspected [scientificExecutionCircuitInspect [dict get $binding document_id] [dict get $job parameters]]
        _scientificExecutionPublicationGuard [dict get $job source_guard]
        if {[dict get $inspected source_sha256] ne [dict get $job circuit_sha256]} {error {Inspected source differs from the published scientific snapshot}}
        if {![dict exists $inspected net_mapping $endpoint]} {error {Probe requires an existing mapped electrical terminal or junction}}
        if {$mode eq {voltage}} {
            set node [dict get $inspected net_mapping $endpoint]
            if {$node eq {0}} {error {Ground is the reference node; this Dataset has no computed ground-voltage variable}}
            set expression "v($node)";set unit V
        } else {
            if {[llength $endpoint]!=2} {error {Branch-current probing requires a device terminal}}
            set owner [native2DGeometryDiagramRead [dict get $binding document_id]]
            set component [lindex $endpoint 0]
            if {![dict exists $owner payload components $component] || [dict get $owner payload components $component kind] ne {voltage}} {error {This solver output exposes branch current only for independent voltage sources; this device current is unavailable}}
            set expression "i([dict get $owner payload components $component name])";set unit A
        }
        set selected {}
        foreach probe [dict get $inspected probes] {
            if {[dict get $probe expression] eq $expression && [dict get $probe unit] eq $unit} {set selected [dict get $probe id];break}
        }
        if {$selected eq {}} {error {The registered provider exposes no computed variable for this probe}}
        if {[dict get $job parameters analysis] eq {ac}} {
            set receipt [_viewerGuiScientificAcProbe $window $form $p $diagram $dataset $job $mode $endpoint $selected $unit]
            if {[dict exists $plotProperties plot_probe]} {viewerGuiDesignTextSet $window [dict get $plotProperties plot_probe] "AC [string totitle $mode] source selected: $endpoint\n[dict get $receipt real_variable_id] / [dict get $receipt imaginary_variable_id] ($unit), frequency (Hz)\nNumeric form: [dict get $receipt numeric_form]. Choose AC result, then explicit Evaluate / Publish / Bind.\nPrevious valid waveform and computed results retained; no calculation or publication was performed."}
            viewerGuiTraceEmit $window $form scientific_probe [dict merge {status ac_form_selected} $receipt]
            return $receipt
        }
        set variable [datasetVariableV3ById $dataset $selected]
        if {[dict get $variable unit] ne $unit} {error {Canonical probe variable has incompatible units}}
        set axis [dict get $inspected independent_variable]
        set x [dict get $axis id];set xVariable [datasetVariableV3ById $dataset $x]
        if {[dict get $xVariable unit] ne [dict get $axis unit] || [dict get $xVariable dtype] ne [dict get $axis dtype] || [dict get $xVariable shape] ne [dict get $variable shape] || [llength [dict get $variable shape]]!=1} {error {Canonical probe coordinate and observable must have the provider's declared units, dtype and aligned rows}}
        _scientificExecutionPublicationGuard [dict get $job source_guard]
        set result [viewerGuiDesignPlotBind $window $plot $plotForm [dict create x_variable_id $x y_variable_id $selected]]
        set receipt [dict create mode $mode endpoint $endpoint variable_id $selected unit $unit x_variable_id $x x_unit [dict get $axis unit] dataset_id $dataset job_id [dict get $job job_id] source_guard [dict get $job source_guard] authority SCIENTIFIC_EXECUTION_API_v1]
        if {[dict exists $plotProperties plot_probe]} {viewerGuiDesignTextSet $window [dict get $plotProperties plot_probe] "[string totitle $mode] probe: $endpoint\n$selected ($unit)\nDataset: $dataset\nOriginal Job: [dict get $job job_id]\nRelease the pointer on a computed Plot point for its exact source row."}
        viewerGuiTraceEmit $window $form scientific_probe [dict merge {status selected} $receipt]
        return $receipt
    } on error {message options} {
        if {[info exists plotProperties] && [dict exists $plotProperties plot_probe]} {catch {viewerGuiDesignTextSet $window [dict get $plotProperties plot_probe] "Scientific probe unavailable: $message\nPrevious waveform selection and valid frame retained."}}
        return -options $options $message
    }
}
proc ::GX::_viewerGuiScientificAcProbe {window form properties diagram dataset job mode endpoint selected unit} {
    # Mapping only: existing Numeric form controls own explicit computation,
    # immutable captured results and publication. Never synthesize an unsplit
    # magnitude Variable or relabel a real component as an amplitude.
    set real ${selected}_real;set imaginary ${selected}_imag
    set frequency [datasetVariableV3ById $dataset frequency]
    set a [datasetVariableV3ById $dataset $real];set b [datasetVariableV3ById $dataset $imaginary]
    if {[dict get $frequency unit] ne {Hz} || [dict get $a unit] ne $unit || [dict get $b unit] ne $unit || [dict get $frequency shape] ne [dict get $a shape] || [dict get $a shape] ne [dict get $b shape] || [llength [dict get $a shape]]!=1} {error {AC frequency and split-complex Variables must have aligned canonical rows and Hz/V/A units}}
    set candidates {}
    foreach definition [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $definition properties]
        if {[dict get $definition type] ne {section} || [datasetPublicationV2DictDefault $p numeric_kind {}] ne {complex_projection}} continue
        if {[dict exists $p numeric_source] && [dict get $p numeric_source] ne $diagram} continue
        lappend candidates [dict get $definition id]
    }
    if {[dict exists $properties scientific_probe_ac_form]} {
        set target [dict get $properties scientific_probe_ac_form]
        if {$target ni $candidates} {error {Declared AC probe form does not belong to this diagram}}
    } elseif {[llength $candidates]==1} {set target [lindex $candidates 0]} else {error {AC probing needs one compatible declared complex_projection form, or an explicit scientific_probe_ac_form reference}}
    set p [_viewerGuiNumericForm $window $target]
    set before [viewerGuiDesignCapture $window];set priorValues [dict get $before values];set priorChoices [dict get $before choices]
    set targets {};foreach key {numeric_dataset numeric_x numeric_real numeric_imaginary} {lappend targets [dict get $p $key]}
    _scientificExecutionPublicationGuard [dict get $job source_guard]
    if {[dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {return -code error -errorcode {GX HISTORY EDIT_CANCELLED} {AC source selection cancelled before changing controls}}
    try {
        viewerGuiDesignValueSet $window [dict get $p numeric_dataset] $dataset
        viewerGuiDesignNumericDiscover $window $target
        foreach {key value} [list numeric_x frequency numeric_real $real numeric_imaginary $imaginary] {viewerGuiDesignValueSet $window [dict get $p $key] $value}
        _scientificExecutionPublicationGuard [dict get $job source_guard]
        set values [viewerGuiDesignValues $window]
        _viewerGuiNumericDisplay $window $target AC_SOURCE_SELECTED "Physical $mode endpoint: $endpoint\nDataset: $dataset\nOriginal Job: [dict get $job job_id]\nFrequency: frequency (Hz)\nReal: $real ($unit)\nImaginary: $imaginary ($unit)\n\nExplicit row start/count and projection retained: [dict get $values [dict get $p numeric_start]] / [dict get $values [dict get $p numeric_count]], [dict get $values [dict get $p numeric_projection]].\nChoose Evaluate to compute through public Numeric, then Publish and Bind. Previous immutable result and waveform are unchanged."
    } on error {message options} {
        if {[viewerGuiDesignGuard $window]} {
            foreach targetId $targets {
                if {[dict exists $priorChoices $targetId]} {catch {viewerGuiDesignChoicesSet $window $targetId [dict get $priorChoices $targetId]}}
                catch {viewerGuiDesignValueSet $window $targetId [dict get $priorValues $targetId]}
            }
        }
        return -options $options $message
    }
    if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window {Select AC probe source}}
    return [dict create mode $mode endpoint $endpoint dataset_id $dataset job_id [dict get $job job_id] source_guard [dict get $job source_guard] numeric_form $target real_variable_id $real imaginary_variable_id $imaginary frequency_variable_id frequency unit $unit representation canonical_split_complex explicit_evaluate_required 1 computation none publication none authority SCIENTIFIC_EXECUTION_API_v1]
}
proc ::GX::_viewerGuiScientificState {window form value} {
    # Store durable identity/publication only, matching single-Job semantics.
    # Full node-local status is read from the actual Job owner when requested.
    dict unset value status
    set domain [viewerGuiDesignContextGet $window]
    if {[dict exists $value sweep_case] && [dict exists $domain scientific_campaigns $form jobs [dict get $value sweep_case]]} {dict set domain scientific_campaigns $form jobs [dict get $value sweep_case] $value}
    dict set domain scientific_jobs $form $value
    viewerGuiDesignContextSet $window $domain
}
proc ::GX::_viewerGuiScientificParameters {window properties} {
    set values [viewerGuiDesignValues $window];set parameters {}
    dict for {parameter component} [dict get $properties scientific_parameters] {dict set parameters $parameter [dict get $values $component]}
    set schema [dict get $::GX::ScientificExecution::providers [dict get $properties scientific_provider] parameters]
    return [_scientificExecutionParameters $schema $parameters]
}
proc ::GX::_viewerGuiScientificJob {window form} {
    _viewerGuiScientificForm $window $form
    set domain [viewerGuiDesignContextGet $window]
    if {[_viewerGuiScientificSweepActive $window $form]} {
        set p [_viewerGuiScientificForm $window $form];set values [viewerGuiDesignValues $window]
        set case [dict get $values [dict get $p scientific_sweep_case]]
        if {![dict exists $domain scientific_campaigns $form jobs $case]} {error {Select an actually admitted sweep case}}
        return [dict get $domain scientific_campaigns $form jobs $case]
    }
    if {![dict exists $domain scientific_jobs $form job_id]} {error {No submitted scientific Job is bound to this form}}
    return [dict get $domain scientific_jobs $form]
}
proc ::GX::_viewerGuiScientificDisplay {window form state {detail {}}} {
    set properties [_viewerGuiScientificForm $window $form]
    viewerGuiDesignTextSet $window [dict get $properties scientific_status] $state
    if {$detail ne {}} {viewerGuiDesignTextSet $window [dict get $properties scientific_log] $detail}
    viewerGuiTraceEmit $window $form scientific_state [dict create status $state]
    return $state
}
proc ::GX::viewerGuiDesignScientificDiscover {window form} {
    set properties [_viewerGuiScientificForm $window $form]
    set choices {local}
    foreach node [scientificExecutionNodeList] {if {[dict get $node enabled]} {lappend choices [dict get $node node_id]}}
    viewerGuiDesignChoicesSet $window [dict get $properties scientific_destination] $choices
    if {[dict exists $properties scientific_sweep_axes]} {
        dict for {id binding} [dict get $::GX::ViewerGui::instances $window bindings] {if {[dict get $binding kind] eq {diagram}} {_viewerGuiScientificSweepDiscover $window $form $id;break}}
    }
    return [dict create destinations $choices provider [scientificExecutionDescribe [dict get $properties scientific_provider]]]
}
proc ::GX::viewerGuiDesignScientificPrepare {window diagram form} {
    try {
        set properties [_viewerGuiScientificForm $window $form]
        if {![dict exists $::GX::ViewerGui::instances $window bindings $diagram] || [dict get $::GX::ViewerGui::instances $window bindings $diagram kind] ne {diagram}} {error {Bind the canonical diagram before preparing a scientific Job}}
        set values [viewerGuiDesignValues $window];set parameters {}
        dict for {parameter component} [dict get $properties scientific_parameters] {
            set definition [viewerGuiDesignComponent $window $component]
            if {[dict get $definition type] ni {field choice entry combobox toggle checkbutton}} {error {Scientific parameters require declared scalar value controls}}
            dict set parameters $parameter [dict get $values $component]
        }
        set destination [dict get $values [dict get $properties scientific_destination]]
        if {$destination ne {local}} {
            set available 0
            set capabilities [scientificExecutionNodeInspect $destination]
            foreach provider [dict get $capabilities providers] {if {[dict get $provider provider_id] eq [dict get $properties scientific_provider] && [dict get $provider available]} {set available 1}}
            if {!$available} {error {Selected node does not advertise the required scientific provider/tool}}
        }
        if {[_viewerGuiScientificSweepEnabled $window $properties]} {return [_viewerGuiScientificSweepPrepare $window $diagram $form $parameters $destination]}
        if {[dict exists $::GX::ViewerGui::instances $window scientific_preparations $form]} {
            set old [dict get $::GX::ViewerGui::instances $window scientific_preparations $form]
            _viewerGuiScientificPreparationDiscard $old
            dict unset ::GX::ViewerGui::instances $window scientific_preparations $form
        }
        set document [dict get $::GX::ViewerGui::instances $window bindings $diagram document_id]
        set receipt [scientificExecutionCircuitPrepare $document $parameters [dict create node_id $destination]]
        dict set receipt destination $destination
        dict set ::GX::ViewerGui::instances $window scientific_preparations $form $receipt
        _viewerGuiScientificDisplay $window $form PREPARED "Circuit snapshot [dict get $receipt source_sha256]\nDestination: $destination\nProvider: [dict get $receipt provider_id]@[dict get $receipt provider_version]\nParameters: [dict get $receipt parameters]\n\n[dict get $receipt netlist]"
        return [dict remove $receipt preparation source_resource]
    } on error {message errorOptions} {
        catch {_viewerGuiScientificDisplay $window $form PREPARATION_FAILED "Preparation failed: $message\n\nExisting submitted Job, published Dataset and Plot bindings are retained."}
        return -options $errorOptions $message
    }
}
proc ::GX::viewerGuiDesignScientificSubmit {window form} {
    try {
        _viewerGuiScientificForm $window $form
        if {![dict exists $::GX::ViewerGui::instances $window scientific_preparations $form]} {error {Prepare this exact circuit and form before submission}}
        set prepared [dict get $::GX::ViewerGui::instances $window scientific_preparations $form]
        set properties [_viewerGuiScientificForm $window $form]
        if {[datasetPublicationV2DictDefault $prepared kind {}] eq {sweep}} {return [_viewerGuiScientificSweepSubmit $window $form $prepared]}
        if {[_viewerGuiScientificSweepEnabled $window $properties]} {error {Sweep mode changed; Prepare again before submitting}}
        if {[_viewerGuiScientificParameters $window $properties] ne [dict get $prepared parameters] || [dict get [viewerGuiDesignValues $window] [dict get $properties scientific_destination]] ne [dict get $prepared destination]} {error {Scientific parameters or destination changed; Prepare again before submitting}}
        set submitted [scientificExecutionSubmit [dict get $prepared preparation]]
        set document [dict get $prepared document]
        set guard [dict create document_id [dict get $document id] generation [dict get $document generation] revision [dict get $document revision] sha256 [dict get $document sha256]]
        _viewerGuiScientificState $window $form [dict merge $submitted [dict create source_guard $guard parameters [dict get $prepared parameters] circuit_sha256 [dict get $prepared source_sha256] destination [dict get $prepared destination] provider_version [dict get $prepared provider_version]]]
        if {[scientificExecutionRemoteId [dict get $submitted job_id]]} {scientificExecutionDiscard [dict get $prepared preparation]}
        dict unset ::GX::ViewerGui::instances $window scientific_preparations $form
        _viewerGuiScientificDisplay $window $form [dict get $submitted state] "Job: [dict get $submitted job_id]\nDestination: [dict get $prepared destination]"
        after 300 [list ::GX::_viewerGuiScientificPoll $window $form [dict get $submitted job_id]]
        return $submitted
    } on error {message errorOptions} {
        catch {_viewerGuiScientificDisplay $window $form SUBMISSION_FAILED "Submission failed: $message\n\nExisting submitted Job, published Dataset and Plot bindings are retained."}
        return -options $errorOptions $message
    }
}
proc ::GX::viewerGuiDesignScientificStatus {window form} {
    try {
        if {[_viewerGuiScientificSweepActive $window $form]} {return [_viewerGuiScientificSweepStatus $window $form]}
        set job [_viewerGuiScientificJob $window $form]
        set status [scientificExecutionStatus [dict get $job job_id]]
        dict set job last_status [dict get $status state]
        _viewerGuiScientificState $window $form $job
        _viewerGuiScientificDisplay $window $form [dict get $status state]
        return $status
    } on error {message options} {_viewerGuiScientificActionFailed $window $form STATUS $message;return -options $options $message}
}
proc ::GX::_viewerGuiScientificActionFailed {window form action message} {
    catch {_viewerGuiScientificDisplay $window $form ${action}_FAILED "$action failed: $message\n\nThe original Job, published Dataset and Plot are retained. Restore the destination connection and reconnect the same Job; no replacement is submitted."}
}
proc ::GX::_viewerGuiScientificPoll {window form expected} {
    if {![viewerGuiDesignGuard $window]} return
    if {[catch {_viewerGuiScientificJob $window $form} job] || [dict get $job job_id] ne $expected} return
    if {[catch {viewerGuiDesignScientificStatus $window $form} status]} {
        _viewerGuiScientificDisplay $window $form UNAVAILABLE $status
        return
    }
    if {[dict get $status state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {after 700 [list ::GX::_viewerGuiScientificPoll $window $form $expected]}
}
proc ::GX::viewerGuiDesignScientificCancel {window form} {
    try {
        if {[_viewerGuiScientificSweepActive $window $form]} {return [_viewerGuiScientificSweepControl $window $form cancel]}
        set job [_viewerGuiScientificJob $window $form]
        scientificExecutionCancel [dict get $job job_id]
        return [viewerGuiDesignScientificStatus $window $form]
    } on error {message options} {_viewerGuiScientificActionFailed $window $form CANCEL $message;return -options $options $message}
}
proc ::GX::viewerGuiDesignScientificReconnect {window form} {
    try {
        if {[_viewerGuiScientificSweepActive $window $form]} {return [_viewerGuiScientificSweepControl $window $form reconnect]}
        set job [_viewerGuiScientificJob $window $form]
        set status [scientificExecutionReconnect [dict get $job job_id]]
        _viewerGuiScientificDisplay $window $form [datasetPublicationV2DictDefault $status state RECONNECTED] "Reconnected original Job: [dict get $job job_id]\nPublished Dataset and Plot bindings are retained."
        after 1 [list ::GX::_viewerGuiScientificPoll $window $form [dict get $job job_id]]
        return $status
    } on error {message options} {_viewerGuiScientificActionFailed $window $form RECONNECT $message;return -options $options $message}
}
proc ::GX::viewerGuiDesignScientificLog {window form} {
    try {
        set job [_viewerGuiScientificJob $window $form]
        set page [scientificExecutionLog [dict get $job job_id] 0 65536]
        set prefix {};if {[dict exists $job sweep_case]} {set prefix "Case: [dict get $job sweep_case]\nOriginal Job: [dict get $job job_id]\nParameters: [dict get $job parameters]\n\n"}
        _viewerGuiScientificDisplay $window $form [datasetPublicationV2DictDefault $job last_status SUBMITTED] $prefix[dict get $page content]
        return $page
    } on error {message options} {_viewerGuiScientificActionFailed $window $form LOG $message;return -options $options $message}
}
proc ::GX::viewerGuiDesignScientificImport {window form datasetComponent} {
    set job [_viewerGuiScientificJob $window $form]
    set definition [viewerGuiDesignComponent $window $datasetComponent]
    if {[dict get $definition type] ne {dataset_selector}} {error {Select a declared canonical Dataset selector}}
    set token {}
    foreach output [dict get [scientificExecutionOutputs [dict get $job job_id]] outputs] {if {[dict get $output role] eq {waveform}} {set token [dict get $output token]}}
    if {$token eq {}} {error {Job has no available waveform output}}
    set dataset scientific_result_[clock microseconds]
    set definition [dict create dataset_id $dataset contract table.generic storage csv provenance "Scientific Job [dict get $job job_id]; provider [dict get $job provider_id]@[dict get $job provider_version]; circuit [dict get $job circuit_sha256]; parameters [dict get $job parameters]" structured_metadata [dict create scientific_execution.job_id [dict get $job job_id] scientific_execution.circuit_sha256 [dict get $job circuit_sha256] scientific_execution.provider_id [dict get $job provider_id]]]
    dict set definition structured_metadata scientific_execution.parameters [dict get $job parameters]
    if {[dict exists $job sweep_case]} {dict set definition structured_metadata scientific_execution.sweep_case [dict get $job sweep_case]}
    set ticket [scientificExecutionImportTable [dict get $job job_id] $token [dict get $::GX::ViewerGui::instances $window module] $definition [list ::GX::_viewerGuiScientificImported $window $form $datasetComponent [dict get $job job_id]] [dict get $job source_guard]]
    _viewerGuiScientificDisplay $window $form PUBLISHING
    return $ticket
}
proc ::GX::_viewerGuiScientificImported {window form component expected response} {
    if {![viewerGuiDesignGuard $window]} return
    if {[catch {_viewerGuiScientificJob $window $form} active]} return
    set job $active
    if {[dict get $job job_id] ne $expected} {
        set found 0;set domain [viewerGuiDesignContextGet $window]
        set jobs {};if {[dict exists $domain scientific_campaigns $form jobs]} {set jobs [dict get $domain scientific_campaigns $form jobs]}
        dict for {case candidate} $jobs {
            if {[dict get $candidate job_id] eq $expected} {set job $candidate;set found 1;break}
        }
        if {!$found} return
    }
    if {![dict get $response ok]} {
        dict set job publication_error [dict get $response error];_viewerGuiScientificState $window $form $job
        if {[dict get $active job_id] eq $expected} {_viewerGuiScientificDisplay $window $form PUBLICATION_FAILED [dict get $response error]}
        return
    }
    dict set job dataset_id [dict get $response result dataset_id]
    _viewerGuiScientificState $window $form $job
    if {[dict get $active job_id] eq $expected} {
        viewerGuiDesignValueSet $window $component [dict get $job dataset_id]
        _viewerGuiScientificDisplay $window $form PUBLISHED "Canonical Dataset: [dict get $job dataset_id]\nOriginal Job: $expected"
    }
}
source [file join [file dirname [info script]] viewer_gui_scientific_sweep_v1.tcl]
proc ::GX::_viewerGuiScientificRestore {window} {
    set domain [viewerGuiDesignContextGet $window]
    foreach component [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $component properties];set form [dict get $component id]
        if {[dict get $component type] ne {section} || ![dict exists $p scientific_provider]} continue
        if {[dict exists $domain scientific_campaigns $form]} {
            set campaign [dict get $domain scientific_campaigns $form]
            set detail "Saved physical sweep: [dict get $campaign destination]\nSource: [dict get $campaign source_guard sha256]\n"
            dict for {case job} [dict get $campaign jobs] {
                append detail "\n$case: last observed [datasetPublicationV2DictDefault $job last_status unknown]\nJob: [dict get $job job_id]\n"
            }
            append detail "\nSaved associations restored without simulation or submission. Reconnect reads these same Jobs for their current authoritative states; select a case for Log or completed Dataset publication."
            _viewerGuiScientificDisplay $window $form RESTORED_SWEEP $detail
        } elseif {[dict exists $domain scientific_jobs $form]} {
            set job [dict get $domain scientific_jobs $form]
            _viewerGuiScientificDisplay $window $form RESTORED_JOB "Saved Job: [dict get $job job_id]\nLast observed: [datasetPublicationV2DictDefault $job last_status unknown]\n\nSaved reference restored without submission. Reconnect reads this same Job for its current authoritative state."
        }
    }
    _viewerGuiScientificNetlistRestore $window
}
