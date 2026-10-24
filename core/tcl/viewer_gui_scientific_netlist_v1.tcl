# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only canonical circuit inspection. Existing Scientific Execution owns
# conversion; the declared log and ordinary Workspace own presentation/cache.
proc ::GX::_viewerGuiScientificNetlistDesignValidate {design} {
    set ids {};foreach component [dict get $design components] {dict set ids [dict get $component id] $component}
    set commands {}
    foreach component [dict get $design components] {
        set p [dict get $component properties];set present 0
        foreach key {scientific_netlist scientific_netlist_diagram scientific_netlist_action} {if {[dict exists $p $key]} {incr present}}
        if {!$present} continue
        if {$present!=3 || [dict get $component type] ne {section} || ![dict exists $p scientific_provider] || [dict get $p scientific_provider] ne {core.ngspice.circuit}} {error {Source/netlist needs a complete declared circuit Scientific section and three references}}
        if {![dict exists $ids [dict get $p scientific_netlist]] || [dict get $ids [dict get $p scientific_netlist] type] ne {log} || [dict get $p scientific_netlist] eq [dict get $p scientific_log]} {error {Source/netlist requires a separately declared read-only log}}
        set diagram [dict get $p scientific_netlist_diagram]
        if {![dict exists $ids $diagram] || [dict get $ids $diagram type] ne {native2d} || [datasetPublicationV2DictDefault [dict get $ids $diagram properties] diagram_catalog {}] ne {electrical.basic}} {error {Source/netlist requires the declared electrical diagram}}
        set action [dict get $p scientific_netlist_action]
        if {$action in {undo redo fit zoom_in zoom_out} || $action in $commands || [dict exists [viewerGuiDesignVisibilityCommands $design] $action] || ![dict exists $design handlers $action] || [dict get $design handlers $action effect] ne {presentation}} {error {Source/netlist requires its own distinct presentation command}}
        lappend commands $action
    }
}
proc ::GX::_viewerGuiScientificNetlistAction {window action} {
    foreach component [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $component properties]
        if {[dict exists $p scientific_netlist_action] && [dict get $p scientific_netlist_action] eq $action} {return [dict get $component id]}
    }
    return {}
}
proc ::GX::_viewerGuiScientificNetlistContext {window form} {
    set p [_viewerGuiScientificForm $window $form]
    set binding [dict get $::GX::ViewerGui::instances $window bindings [dict get $p scientific_netlist_diagram]]
    if {[dict get $binding kind] ne {diagram}} {error {Bind the canonical electrical diagram before inspecting its netlist}}
    set doc [native2DGeometryDiagramRead [dict get $binding document_id]]
    foreach key {generation revision sha256} {if {[dict get $doc $key] ne [dict get $binding document_receipt $key]} {error {Bound circuit changed; reopen or bind its current canonical source}}}
    set guard [dict create document_id [dict get $doc id] generation [dict get $doc generation] revision [dict get $doc revision] sha256 [dict get $doc sha256]]
    set domain [viewerGuiDesignContextGet $window];set job {};set parameters {};set dataset {};set datasetSha {}
    if {[dict exists $domain scientific_campaigns $form] || [dict exists $domain scientific_jobs $form]} {
        set job [_viewerGuiScientificJob $window $form]
        _scientificExecutionPublicationGuard [dict get $job source_guard]
        if {[dict get $job source_guard] ne $guard || [dict get $job provider_id] ne [dict get $p scientific_provider] || [dict get $job circuit_sha256] ne [dict get $doc sha256]} {error {Selected Job/case belongs to a different circuit/provider snapshot}}
        set parameters [dict get $job parameters]
        set dataset [datasetPublicationV2DictDefault $job dataset_id {}]
        if {$dataset ne {}} {
            set metadata [datasetMetadataRead $::GX::currentSession $dataset]
            foreach {key expected} [list scientific_execution.job_id [dict get $job job_id] scientific_execution.circuit_sha256 [dict get $job circuit_sha256] scientific_execution.provider_id [dict get $p scientific_provider] scientific_execution.parameters $parameters] {
                if {![dict exists $metadata $key] || [dict get $metadata $key] ne $expected} {error "Published source/netlist provenance differs: $key"}
            }
            set datasetSha [dict get [sessionInspectionDatasetPayload $dataset] sha256]
        }
    } else {
        set values [viewerGuiDesignValues $window]
        dict for {key control} [dict get $p scientific_parameters] {dict set parameters $key [dict get $values $control]}
    }
    return [dict create source_guard $guard parameters $parameters job_id [datasetPublicationV2DictDefault $job job_id {}] dataset_id $dataset dataset_sha256 $datasetSha provider_id [dict get $p scientific_provider] provider_version [datasetPublicationV2DictDefault $job provider_version {}]]
}
proc ::GX::viewerGuiDesignScientificNetlist {window form} {
    set p [_viewerGuiScientificForm $window $form]
    foreach key {scientific_netlist scientific_netlist_diagram scientific_netlist_action} {if {![dict exists $p $key]} {error {Declare the complete read-only source/netlist binding}}}
    try {
        set context [_viewerGuiScientificNetlistContext $window $form]
        set inspection [scientificExecutionCircuitInspect [dict get $context source_guard document_id] [dict get $context parameters]]
        _scientificExecutionPublicationGuard [dict get $context source_guard]
        if {[dict get $inspection source_sha256] ne [dict get $context source_guard sha256] || ([dict get $context provider_version] ne {} && [dict get $inspection provider_version] ne [dict get $context provider_version])} {error {Inspected source/provider differs from the selected Job snapshot}}
        set netlist [dict get $inspection netlist]
        if {[string bytelength $netlist]>32768} {error {Canonical netlist exceeds this 32 KiB inline view; no truncated deck is accepted}}
        set text "Validated canonical circuit netlist (read-only inspection; no simulation)\nSource: [dict get $context source_guard document_id]\nGeneration: [dict get $context source_guard generation]\nRevision: [dict get $context source_guard revision]\nSHA256: [dict get $context source_guard sha256]\nProvider: [dict get $inspection provider_id]@[dict get $inspection provider_version]\nJob: [dict get $context job_id]\nDataset: [dict get $context dataset_id]\nParameters: [dict get $inspection parameters]\n\n$netlist"
        set record [dict merge $context [dict create text $text provider_version [dict get $inspection provider_version] normalized_parameters [dict get $inspection parameters]]]
        set domain [viewerGuiDesignContextGet $window];dict set domain scientific_netlists $form $record
        viewerGuiDesignContextSet $window $domain
        viewerGuiDesignTextSet $window [dict get $p scientific_netlist] $text
        if {[dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerRecordOperation $window "Inspect source/netlist $form"}
        return [dict remove $record text]
    } on error {message options} {
        viewerGuiDesignTextSet $window [dict get $p scientific_netlist] "Source/netlist unavailable: $message\nExisting scientific Jobs, Dataset, Plot and cached provenance are retained. Correct the source/case context and inspect again."
        return -options $options $message
    }
}
proc ::GX::_viewerGuiScientificNetlistRestore {window} {
    set domain [viewerGuiDesignContextGet $window]
    foreach component [dict get $::GX::ViewerGui::instances $window design components] {
        set form [dict get $component id];set p [dict get $component properties]
        if {![dict exists $p scientific_netlist]} continue
        if {![dict exists $domain scientific_netlists $form]} {
            viewerGuiDesignTextSet $window [dict get $p scientific_netlist] {No saved source/netlist inspection exists in this Workspace state. Inspect explicitly to reconstruct the current canonical circuit; no simulation is submitted.}
            continue
        }
        set saved [dict get $domain scientific_netlists $form]
        if {[catch {
            set current [_viewerGuiScientificNetlistContext $window $form]
            foreach key {source_guard parameters job_id dataset_id dataset_sha256 provider_id} {if {[dict get $saved $key] ne [dict get $current $key]} {error {Saved source/netlist differs from the current source or selected Job/case; inspect explicitly}}}
        } message]} {
            viewerGuiDesignTextSet $window [dict get $p scientific_netlist] "Saved source/netlist is stale or unavailable: $message\nNo simulation or reconstruction was performed."
        } else {viewerGuiDesignTextSet $window [dict get $p scientific_netlist] [dict get $saved text]}
    }
}
