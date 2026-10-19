# SPDX-License-Identifier: GPL-3.0-or-later
# Optional typed sweep profile of the existing Scientific form. This file owns
# only Viewer requests/presentation; Parallel and Script Job own all execution.
proc ::GX::_viewerGuiScientificSweepEnabled {window properties} {
    if {![dict exists $properties scientific_sweep_axes]} {return 0}
    set values [viewerGuiDesignValues $window]
    return [uiFieldNormalize {type boolean} [dict get $values [dict get $properties scientific_sweep_enabled]]]
}
proc ::GX::_viewerGuiScientificSweepValidate {definitions properties} {
    if {![dict exists $properties scientific_sweep_axes]} {
        foreach key {scientific_sweep_enabled scientific_sweep_case scientific_sweep_workers scientific_sweep_fail_fast} {if {[dict exists $properties $key]} {error {Declare complete scientific sweep axes before its controls}}}
        return
    }
    foreach {key types} {scientific_sweep_enabled {toggle checkbutton} scientific_sweep_case {choice combobox} scientific_sweep_workers {field entry} scientific_sweep_fail_fast {toggle checkbutton}} {
        if {![dict exists $properties $key]} {error "Sweep form requires $key"}
        set id [dict get $properties $key]
        if {![dict exists $definitions $id] || [dict get $definitions $id type] ni $types} {error "Invalid typed sweep control $key"}
    }
    set axes [dict get $properties scientific_sweep_axes]
    if {[dict size $axes]<1 || [dict size $axes]>2} {error {Declare one or two bounded physical sweep axes}}
    dict for {axis spec} $axes {
        if {![regexp {^[a-z][a-z0-9_]{0,31}$} $axis]} {error {Sweep axis name must match [a-z][a-z0-9_]{0,31}; use lowercase stable names such as resistance or capacitance}}
        if {[lsort [dict keys $spec]] ne {component count start stop unit}} {error {Sweep axis requires exactly component/start/stop/count/unit control IDs}}
        foreach {key types} {component {choice combobox} start {field entry} stop {field entry} count {field entry} unit {status label}} {
            set id [dict get $spec $key]
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni $types} {error "Invalid sweep axis $axis control $key"}
        }
    }
}
proc ::GX::_viewerGuiScientificPreparationDiscard {receipt} {
    if {[dict exists $receipt items]} {
        foreach item [dict get $receipt items] {catch {scientificExecutionDiscard [dict get $item preparation]}}
    } elseif {[dict exists $receipt preparation]} {catch {scientificExecutionDiscard [dict get $receipt preparation]}}
}
proc ::GX::_viewerGuiScientificSweepFingerprint {window properties} {
    set values [viewerGuiDesignValues $window];set keys [dict values [dict get $properties scientific_parameters]]
    foreach key {scientific_destination scientific_sweep_enabled scientific_sweep_workers scientific_sweep_fail_fast} {lappend keys [dict get $properties $key]}
    dict for {axis spec} [dict get $properties scientific_sweep_axes] {foreach key {component start stop count} {lappend keys [dict get $spec $key]}}
    set result {};foreach key $keys {dict set result $key [dict get $values $key]}
    return $result
}
proc ::GX::_viewerGuiScientificSweepDiscover {window form diagram} {
    set p [_viewerGuiScientificForm $window $form]
    if {![dict exists $p scientific_sweep_axes]} return
    set id [dict get $::GX::ViewerGui::instances $window bindings $diagram document_id]
    set owner [native2DGeometryDiagramRead $id];set catalog [native2DGeometryDiagramCatalog [dict get $owner payload catalog]]
    set choices {};set text {Physical sweep component values use the catalog's canonical SI units:}
    dict for {id item} [dict get $owner payload components] {
        if {[dict get $item kind] ni {resistor capacitor inductor voltage current}} continue
        lappend choices $id
        set unit [dict get $catalog symbols [dict get $item kind] attributes value unit]
        append text "\n$id · [dict get $item name] · $unit"
    }
    dict for {axis spec} [dict get $p scientific_sweep_axes] {
        viewerGuiDesignChoicesSet $window [dict get $spec component] $choices
        set selected [dict get [viewerGuiDesignValues $window] [dict get $spec component]]
        set unitText {Select a component; Prepare reports its catalog SI unit.}
        if {[dict exists $owner payload components $selected]} {
            set item [dict get $owner payload components $selected]
            if {[dict exists $catalog symbols [dict get $item kind] attributes value unit]} {set unitText "[dict get $item name] ($selected): [dict get $catalog symbols [dict get $item kind] attributes value unit]"}
        }
        viewerGuiDesignTextSet $window [dict get $spec unit] $unitText
    }
    # Discovery refreshes selectors; it does not supersede an existing Job or
    # the honest RESTORED_SWEEP status established before compiled open runs.
    set domain [viewerGuiDesignContextGet $window]
    if {![dict exists $domain scientific_campaigns $form] && ![dict exists $domain scientific_jobs $form]} {_viewerGuiScientificDisplay $window $form DISCOVERED $text}
}
proc ::GX::_viewerGuiScientificSweepPrepare {window diagram form parameters destination} {
    set p [_viewerGuiScientificForm $window $form];set values [viewerGuiDesignValues $window]
    set document [dict get $::GX::ViewerGui::instances $window bindings $diagram document_id]
    set owner [native2DGeometryDiagramRead $document];set catalog [native2DGeometryDiagramCatalog [dict get $owner payload catalog]]
    set items [list [dict create component_values {}]];set seen {};set axes {}
    modulePublicApiActivate math.numeric NUMERIC_API_v1
    dict for {axis spec} [dict get $p scientific_sweep_axes] {
        set component [dict get $values [dict get $spec component]]
        if {$component in $seen || ![dict exists $owner payload components $component]} {error {Sweep axes require distinct existing circuit component IDs}}
        set item [dict get $owner payload components $component];set kind [dict get $item kind]
        if {$kind ni {resistor capacitor inductor voltage current}} {error {Only R/C/L and independent V/I component values support physical sweeps}}
        lappend seen $component
        set unit [dict get $catalog symbols $kind attributes value unit]
        set start [uiFieldNormalize {type number} [dict get $values [dict get $spec start]]]
        set stop [uiFieldNormalize {type number} [dict get $values [dict get $spec stop]]]
        set count [uiFieldNormalize {type integer min 1 max 4} [dict get $values [dict get $spec count]]]
        # Scientific parameter values are generated exclusively by public Numeric.
        set grid [::GX::NumericAPIv1::uniformGrid $start $stop $count {mode count}]
        set next {}
        foreach previous $items {foreach value [dict get $grid x] {set case $previous;dict set case component_values $component $value;lappend next $case}}
        if {[llength $next]>16} {error {Physical sweep exceeds sixteen explicit cases}}
        set items $next
        dict set axes $axis [dict create component_id $component name [dict get $item name] unit $unit grid $grid]
        viewerGuiDesignTextSet $window [dict get $spec unit] "[dict get $item name] ($component): $unit"
    }
    set cases {};set ordinal 0
    foreach item $items {lappend cases [dict create id case[incr ordinal] parameters $item]}
    set receipt [scientificExecutionCircuitSweepPrepare $document $parameters $cases [dict create node_id $destination expected_generation [dict get $owner generation] expected_revision [dict get $owner revision] expected_sha256 [dict get $owner sha256]]]
    dict set receipt kind sweep;dict set receipt parameters [_viewerGuiScientificParameters $window $p]
    dict set receipt destination $destination;dict set receipt fingerprint [_viewerGuiScientificSweepFingerprint $window $p];dict set receipt axes $axes
    if {[dict exists $::GX::ViewerGui::instances $window scientific_preparations $form]} {_viewerGuiScientificPreparationDiscard [dict get $::GX::ViewerGui::instances $window scientific_preparations $form]}
    dict set ::GX::ViewerGui::instances $window scientific_preparations $form $receipt
    _viewerGuiScientificDisplay $window $form SWEEP_PREPARED "Prepared [llength $cases] immutable physical cases\nDestination: $destination\nSource: [dict get $owner sha256]\nAxes: $axes\n\nSubmit admits ordinary CORE Jobs. Admission completion is not simulation completion."
    return [dict remove $receipt items source_resource]
}
proc ::GX::_viewerGuiScientificSweepCampaign {window form} {
    set domain [viewerGuiDesignContextGet $window]
    if {![dict exists $domain scientific_campaigns $form]} {error {Submit a physical sweep before inspecting its cases}}
    return [dict get $domain scientific_campaigns $form]
}
proc ::GX::_viewerGuiScientificSweepActive {window form} {
    set p [_viewerGuiScientificForm $window $form]
    return [expr {[_viewerGuiScientificSweepEnabled $window $p] && [dict exists [viewerGuiDesignContextGet $window] scientific_campaigns $form]}]
}
proc ::GX::_viewerGuiScientificSweepSubmit {window form prepared} {
    set p [_viewerGuiScientificForm $window $form]
    if {![_viewerGuiScientificSweepEnabled $window $p] || [_viewerGuiScientificSweepFingerprint $window $p] ne [dict get $prepared fingerprint]} {error {Sweep form or destination changed; Prepare again before submitting}}
    set values [viewerGuiDesignValues $window]
    set workers [uiFieldNormalize {type integer min 1 max 16} [dict get $values [dict get $p scientific_sweep_workers]]]
    set failFast [uiFieldNormalize {type boolean} [dict get $values [dict get $p scientific_sweep_fail_fast]]]
    set admitted [scientificExecutionCircuitSweepSubmit $prepared [dict create workers $workers fail_fast $failFast]]
    set jobs {};set failures {};set submitted {};set guard [dict get $prepared source_guard]
    foreach row [dict get $admitted coordination results] {
        if {[dict get $row state] ne {success}} {lappend failures $row;continue}
        set value [dict get $row value];set case [dict get $value item_id];set job [dict get $value submitted]
        dict set job source_guard $guard;dict set job parameters [dict get $value parameters]
        dict set job circuit_sha256 [dict get $guard sha256];dict set job destination [dict get $prepared destination]
        dict set job provider_version [dict get $prepared provider_version];dict set job sweep_case $case
        dict set jobs $case $job;lappend submitted $case
    }
    set retained {};foreach item [dict get $prepared items] {
        if {[dict get $item id] ni $submitted} {lappend retained $item
        } elseif {[dict get $prepared destination] ne {local}} {catch {scientificExecutionDiscard [dict get $item preparation]}}
    }
    dict unset ::GX::ViewerGui::instances $window scientific_preparations $form
    if {[llength $retained]} {
        # Preserve every uncertain admission's original handle until lifecycle
        # disposal. A later partial campaign must not orphan an older nonce.
        if {[dict exists $::GX::ViewerGui::instances $window scientific_retained_preparations $form]} {
            set earlier [dict get $::GX::ViewerGui::instances $window scientific_retained_preparations $form items]
            set retained [concat $earlier $retained]
        }
        dict set ::GX::ViewerGui::instances $window scientific_retained_preparations $form [dict create items $retained]
    }
    set campaign [dict create identity [clock microseconds] source_guard $guard axes [dict get $prepared axes] destination [dict get $prepared destination] expected_cases [llength [dict get $prepared items]] jobs $jobs admission_failures $failures coordination [dict remove [dict get $admitted coordination] results]]
    set domain [viewerGuiDesignContextGet $window];dict set domain scientific_campaigns $form $campaign
    viewerGuiDesignContextSet $window $domain
    viewerGuiDesignChoicesSet $window [dict get $p scientific_sweep_case] [dict keys $jobs]
    if {[dict size $jobs]} {viewerGuiDesignValueSet $window [dict get $p scientific_sweep_case] [lindex [dict keys $jobs] 0]}
    _viewerGuiScientificSweepStatus $window $form
    after 300 [list ::GX::_viewerGuiScientificSweepPoll $window $form [dict get $campaign identity]]
    return $campaign
}
proc ::GX::_viewerGuiScientificSweepStatus {window form} {
    set campaign [_viewerGuiScientificSweepCampaign $window $form];set terminal 1;set complete 0;set problems 0
    set detail "Physical sweep: [dict get $campaign destination]\nSource: [dict get $campaign source_guard sha256]\nAdmission coordinator: [dict get $campaign coordination worker_count] worker; ordinary Job supervisor owns actual simulation concurrency.\n"
    dict for {case job} [dict get $campaign jobs] {
        if {[catch {scientificExecutionStatus [dict get $job job_id]} status]} {
            dict set job last_status UNAVAILABLE;dict set job last_error $status;set terminal 0
        } else {dict set job last_status [dict get $status state];dict unset job last_error}
        # Durable Job identity/parameters belong in the Workspace, while full
        # protocol status belongs to its local/remote Job owner. In particular,
        # remote provenance contains node-local resource IDs and cannot be
        # interpreted as resources of this client's Session. Reconnect always
        # reads the same canonical Job rather than restoring a shadow journal.
        dict unset job status
        set state [dict get $job last_status]
        if {$state ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {set terminal 0}
        if {$state eq {COMPLETED}} {incr complete}
        if {$state in {FAILED CANCELLED INTERRUPTED UNAVAILABLE}} {incr problems}
        dict set campaign jobs $case $job
        append detail "\n$case: $state\nJob: [dict get $job job_id]\nValues (SI): [dict get $job parameters component_values]\n"
        if {[dict exists $job last_error]} {append detail "[dict get $job last_error]\n"}
    }
    if {[llength [dict get $campaign admission_failures]]} {incr problems;append detail "\nAdmission failures: [dict get $campaign admission_failures]\nKnown submitted Jobs and previous publications remain. No uncertain admission is automatically retried.\n"}
    set state [expr {$terminal ? ($problems ? {SWEEP_FINISHED_WITH_ERRORS} : {SWEEP_COMPLETED}) : ($problems ? {SWEEP_PARTIAL_OR_UNAVAILABLE} : {SWEEP_RUNNING})}]
    append detail "\nCompleted: $complete / [dict get $campaign expected_cases]\nSelect a case, then Read Log or Publish Dataset for that exact Job. Cancel requests cancellation of all admitted cases; Reconnect reads the same original Jobs."
    set domain [viewerGuiDesignContextGet $window];dict set domain scientific_campaigns $form $campaign
    if {[dict exists $domain scientific_jobs $form status]} {dict unset domain scientific_jobs $form status}
    viewerGuiDesignContextSet $window $domain
    _viewerGuiScientificDisplay $window $form $state $detail
    return [dict create state $state terminal $terminal completed $complete expected [dict get $campaign expected_cases] campaign $campaign]
}
proc ::GX::_viewerGuiScientificSweepPoll {window form identity} {
    if {![viewerGuiDesignGuard $window] || [catch {_viewerGuiScientificSweepCampaign $window $form} campaign] || [dict get $campaign identity] ne $identity || ![_viewerGuiScientificSweepActive $window $form]} return
    if {[catch {_viewerGuiScientificSweepStatus $window $form} status]} return
    if {![dict get $status terminal]} {after 700 [list ::GX::_viewerGuiScientificSweepPoll $window $form $identity]}
}
proc ::GX::_viewerGuiScientificSweepControl {window form operation} {
    set campaign [_viewerGuiScientificSweepCampaign $window $form];set errors {}
    dict for {case job} [dict get $campaign jobs] {
        if {$operation eq {cancel} && [datasetPublicationV2DictDefault $job last_status {}] in {COMPLETED FAILED CANCELLED INTERRUPTED}} continue
        set command [expr {$operation eq {cancel} ? {::GX::scientificExecutionCancel} : {::GX::scientificExecutionReconnect}}]
        if {[catch {{*}$command [dict get $job job_id]} reason]} {dict set errors $case $reason}
    }
    set status [_viewerGuiScientificSweepStatus $window $form]
    if {[dict size $errors]} {_viewerGuiScientificDisplay $window $form SWEEP_CONTROL_FAILED "$operation errors: $errors\nOriginal child Jobs and published Datasets are retained."}
    after 300 [list ::GX::_viewerGuiScientificSweepPoll $window $form [dict get $campaign identity]]
    return [dict merge $status [dict create control_errors $errors]]
}
