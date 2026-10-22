# SPDX-License-Identifier: GPL-3.0-or-later
# Typed model form composition in the existing Viewer GUI Host. The original
# EM service retains models, native validation, Jobs, publication and fields.
proc ::GX::_viewerGuiEMDesignValidate {design} {
    set definitions {};set mappedActions {};foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    set keys {kind model_id half_width_m height_m mesh_size_m radius_m current_density_A_m2 mu_r voltage_V eps_r}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {[dict exists $p em_actions] && ![dict exists $p em_parameters]} {error {EM action availability requires a complete declared model form}}
        if {![dict exists $p em_parameters]} continue
        if {![dict exists $design requirements ELECTROMAGNETIC_SIMULATION_API_v1] || [dict get $design requirements ELECTROMAGNETIC_SIMULATION_API_v1]!=1} {error {EM model form requires its declared ELECTROMAGNETIC_SIMULATION_API_v1@1 contract}}
        if {[dict get $c type] ne {section} || [lsort [dict keys [dict get $p em_parameters]]] ne [lsort $keys]} {error {EM model form requires its complete typed native model parameter mapping}}
        dict for {field id} [dict get $p em_parameters] {
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni {field entry choice combobox}} {error "Invalid EM parameter component: $field"}
            if {$field eq {kind} && [dict get $definitions $id type] ni {choice combobox}} {error {EM physics requires a declared choice component}}
        }
        foreach {key types} {em_models {choice combobox} em_status {label status log} em_log log em_output_id {field entry} em_dataset dataset_selector} {
            if {![dict exists $p $key] || ![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types} {error "Missing or invalid EM form reference: $key"}
        }
        if {[dict exists $p em_field_plot] && (![dict exists $definitions [dict get $p em_field_plot]] || [dict get $definitions [dict get $p em_field_plot] type] ne {plot})} {error {EM field presentation requires a declared Plot component}}
        if {[dict exists $p em_profile_plot] && (![dict exists $definitions [dict get $p em_profile_plot]] || [dict get $definitions [dict get $p em_profile_plot] type] ne {plot})} {error {EM sample profile requires a declared Plot component}}
        if {[dict exists $p em_field_native3d] && (![dict exists $definitions [dict get $p em_field_native3d]] || [dict get $definitions [dict get $p em_field_native3d] type] ne {native3d})} {error {EM planar 3D presentation requires a declared Native3D component}}
        if {[dict exists $p em_jobs] && (![dict exists $definitions [dict get $p em_jobs]] || [dict get $definitions [dict get $p em_jobs] type] ni {choice combobox})} {error {EM retained Job selection requires a declared choice component}}
        if {[dict exists $p em_report] && (![dict exists $definitions [dict get $p em_report]] || [dict get $definitions [dict get $p em_report] type] ni {log label status})} {error {EM result report requires an existing read-only text component}}
        dict for {operation command} [datasetPublicationV2DictDefault $p em_actions {}] {
            if {$operation ni {refresh new_electric new_magnetic validate open save duplicate workspaces rename run jobs reconnect status cancel log results publish field field_3d profile publish_charts export_field runtime} || ![dict exists $design handlers $command] || $command in $mappedActions} {error {EM action mapping requires unique declared handlers and supported operations}}
            lappend mappedActions $command
        }
    }
}
proc ::GX::_viewerGuiEMActionEnabled {window command} {
    if {![dict exists $::GX::ViewerGui::instances $window]} {return {}}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        set p [dict get $c properties]
        dict for {operation id} [datasetPublicationV2DictDefault $p em_actions {}] {
            if {$id ne $command} continue
            return [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] em_availability {}] [list [dict get $c id] $operation] 0]
        }
    }
    return {}
}
proc ::GX::_viewerGuiEMAvailabilityPoll {window token} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window] || ![viewerGuiDesignGuard $window] || [dict get $::GX::ViewerGui::instances $window token] ne $token} return
    viewerGuiActionsRefresh $window
}
proc ::GX::_viewerGuiEMCapturedChoices {window choices} {
    # Model/Job inventories are live projections from their existing owners.
    # Another available model is not an edit to this saved scientific interface.
    # Selected IDs, scientific bindings, drafts and History remain captured.
    dict for {form record} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] em_forms {}] {
        set p [dict get [viewerGuiDesignComponent $window $form] properties]
        foreach key {em_models em_jobs} {
            if {[dict exists $p $key]} {dict unset choices [dict get $p $key]}
        }
    }
    return $choices
}
proc ::GX::_viewerGuiEMRefreshAvailability {window} {
    if {![dict exists $::GX::ViewerGui::instances $window em_forms]} return
    if {[dict exists $::GX::ViewerGui::instances $window em_availability_timer]} {
        after cancel [dict get $::GX::ViewerGui::instances $window em_availability_timer]
        dict unset ::GX::ViewerGui::instances $window em_availability_timer
    }
    set availability {};set poll 0;set instance [dict get $::GX::ViewerGui::instances $window]
    set token [dict get $instance token];set values [viewerGuiDesignValues $window]
    dict for {form r} [dict get $instance em_forms] {
        set p [dict get [viewerGuiDesignComponent $window $form] properties]
        set usable [expr {$token ne {} && [viewerGuiDesignGuard $window]}]
        set document [dict get $r document_id];set job [dict get $r job_id];set status {};set now [clock milliseconds]
        if {$usable && $job ne {}} {
            set cached [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $instance em_job_projection {}] $form {}]
            if {$cached ne {} && [dict get $cached job_id] eq $job && $now-[dict get $cached read_ms]<250} {
                set status [dict get $cached status]
            } else {
                if {[catch {::GX::ElectromagneticSimulation::jobStatus $job} status]} {set status {}}
                dict set ::GX::ViewerGui::instances $window em_job_projection $form [dict create job_id $job read_ms $now status $status]
            }
        }
        set state [datasetPublicationV2DictDefault $status state {}]
        set active [expr {$state in {QUEUED PREPARING RUNNING FINALIZING CANCELLING}}]
        # Unknown retained-Job status is not evidence that editing/resubmission
        # is available. Status/Log remain reachable for the precise diagnostic.
        set busy [expr {$active || ($usable && $job ne {} && $status eq {})}]
        if {$active} {set poll 1}
        set sourceCurrent 0
        if {$document ne {} && ![catch {_viewerGuiEMStamp $document} stamp] && $stamp eq [dict get $r stamp] && [datasetPublicationV2DictDefault $status provider_id {}] eq {math.electromagnetic_simulation.fem2d} && [dict exists $status source_identities workspace id] && [dict exists $status source_identities workspace generation] && [dict exists $status source_identities workspace revision] && [dict exists $status source_identities workspace sha256]} {
            set source [dict get $status source_identities workspace]
            set sourceCurrent [expr {[dict get $source id] eq $document && [list [dict get $source generation] [dict get $source revision] [dict get $source sha256]] eq $stamp}]
        }
        set selectedModel [dict get $values [dict get $p em_models]]
        set selectedJob [expr {[dict exists $p em_jobs]?[dict get $values [dict get $p em_jobs]]:{}}]
        set dataset [dict get $values [dict get $p em_dataset]]
        set field [expr {$usable && $dataset ne {} && ![catch {::GX::ElectromagneticSimulation::fieldDescribe $dataset}]}]
        foreach operation {refresh new_electric new_magnetic validate save workspaces run} {dict set availability [list $form $operation] [expr {$usable&&!$busy}]}
        foreach operation {duplicate rename jobs} {dict set availability [list $form $operation] [expr {$usable&&!$busy&&$document ne {}}]}
        dict set availability [list $form open] [expr {$usable&&!$busy&&$selectedModel ne {}}]
        dict set availability [list $form reconnect] [expr {$usable&&!$busy&&$document ne {}&&$selectedJob ne {}}]
        foreach operation {status log} {dict set availability [list $form $operation] [expr {$usable&&$document ne {}&&$job ne {}}]}
        dict set availability [list $form cancel] [expr {$usable&&$active}]
        foreach operation {results publish} {dict set availability [list $form $operation] [expr {$usable&&$state eq {COMPLETED}&&$sourceCurrent}]}
        foreach operation {field field_3d profile publish_charts} {dict set availability [list $form $operation] $field}
        set shown 0
        if {$field && [dict exists $p em_field_plot]} {
            set target [dict get $p em_field_plot]
            if {[dict exists $instance bindings $target spec panels]} {
                set series [dict get [lindex [dict get $instance bindings $target spec panels] 0] series]
                if {[llength $series]==1 && [dict exists [lindex $series 0] cell_field] && [dict get [lindex $series 0] dataset_id] eq $dataset} {set shown 1}
            }
        }
        dict set availability [list $form export_field] $shown
        dict set availability [list $form runtime] [viewerGuiDesignGuard $window]
        set magnetic [expr {[dict get $values [dict get $p em_parameters kind]] eq {magnetostatic_2d}}]
        dict for {parameter id} [dict get $p em_parameters] {
            set enabled [expr {$usable&&!$busy}]
            if {$parameter in {radius_m current_density_A_m2 mu_r}} {set enabled [expr {$enabled&&$magnetic}]}
            if {$parameter in {voltage_V eps_r}} {set enabled [expr {$enabled&&!$magnetic}]}
            if {[dict exists $instance widgets $id]} {uiFieldComponentEnabled [dict get $instance widgets $id] [dict get [viewerGuiDesignComponent $window $id] type] $enabled}
        }
    }
    dict set ::GX::ViewerGui::instances $window em_availability $availability
    if {$poll} {dict set ::GX::ViewerGui::instances $window em_availability_timer [after 250 [list ::GX::_viewerGuiEMAvailabilityPoll $window $token]]}
}
proc ::GX::_viewerGuiEMForm {window form} {
    if {![viewerGuiDesignGuard $window] || [dict get $::GX::ViewerGui::instances $window token] eq {}} {error {Open a Session and reopen this model Viewer}}
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || ![dict exists $c properties em_parameters]} {error {Declare the complete electromagnetic model form}}
    modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1
    return [dict get $c properties]
}
proc ::GX::_viewerGuiEMStamp {id} {
    set d [interactiveDocumentRead $id]
    if {[dict get $d module_id] ne {math.electromagnetic_simulation} || [dict get $d provider_id] ne {em_models} || [dict get $d format] ne {gxtxt.em_model}} {error {Foreign electromagnetic model owner}}
    return [list [dict get $d generation] [dict get $d revision] [dict get $d sha256]]
}
proc ::GX::_viewerGuiEMCurrent {window form} {
    _viewerGuiEMForm $window $form
    set r [dict get $::GX::ViewerGui::instances $window em_forms $form]
    if {[dict get $r document_id] eq {}} {error {Save or open an electromagnetic model first}}
    if {[_viewerGuiEMStamp [dict get $r document_id]] ne [dict get $r stamp]} {error {Electromagnetic model changed in another window; preserve the draft and reopen it}}
    return $r
}
proc ::GX::_viewerGuiEMModel {window form} {
    set p [_viewerGuiEMForm $window $form];set values [viewerGuiDesignValues $window]
    set kind [dict get $values [dict get $p em_parameters kind]]
    set model [::GX::ElectromagneticSimulation::defaultModel $kind]
    dict for {field id} [dict get $p em_parameters] {dict set model $field [dict get $values $id]}
    return [dict get [::GX::ElectromagneticSimulation::validate $model] model]
}
proc ::GX::_viewerGuiEMSetModel {window form model} {
    set p [_viewerGuiEMForm $window $form]
    dict for {field id} [dict get $p em_parameters] {viewerGuiDesignValueSet $window $id [dict get $model $field]}
    dict set ::GX::ViewerGui::instances $window em_forms $form baseline [_viewerGuiEMDraft $window $form]
}
proc ::GX::_viewerGuiEMDraft {window form} {
    set p [_viewerGuiEMForm $window $form];set values [viewerGuiDesignValues $window];set draft {}
    dict for {field id} [dict get $p em_parameters] {dict set draft $field [dict get $values $id]}
    return $draft
}
proc ::GX::_viewerGuiEMDirty {window form} {
    set r [dict get $::GX::ViewerGui::instances $window em_forms $form]
    if {[dict get $::GX::ViewerGui::instances $window token] eq {} || ![dict exists $r baseline]} {return 0}
    return [expr {[_viewerGuiEMDraft $window $form] ne [dict get $r baseline]}]
}
proc ::GX::_viewerGuiEMWorkspaceCheck {window form action} {
    _viewerGuiEMForm $window $form
    if {[dict get $::GX::ViewerGui::instances $window em_forms $form document_id] ne {}} {_viewerGuiEMCurrent $window $form}
}
proc ::GX::_viewerGuiEMWorkspaceCurrent {window form} {return [dict get $::GX::ViewerGui::instances $window em_forms $form document_id]}
proc ::GX::_viewerGuiEMWorkspaceRename {window form id name} {
    set context [_workspaceHostContext em_models [_viewerGuiEMCallbacks $window $form] $window]
    set prior [_viewerGuiEMCurrent $window $form]
    if {[dict get $prior document_id] ne $id} {error {The selected Workspace is not this electromagnetic model}}
    _viewerGuiEMPrepareEdit $window
    # History preparation can yield. Revalidate the same window, Session and
    # model before writing; never adopt another window's newer revision.
    _workspaceHostCheck $context
    set current [_viewerGuiEMCurrent $window $form]
    if {[dict get $current document_id] ne $id || [dict get $current stamp] ne [dict get $prior stamp]} {error {Electromagnetic model changed while preparing Rename; reopen it}}
    sessionWorkspaceRename $id $name
    # Rename changes presentation metadata only. Preserve the draft, baseline,
    # retained Job and History association; refresh only this owner's receipt.
    dict set ::GX::ViewerGui::instances $window em_forms $form stamp [_viewerGuiEMStamp $id]
    return $id
}
proc ::GX::_viewerGuiEMDetach {window form} {
    if {![dict exists $::GX::ViewerGui::instances $window em_forms $form]} return
    dict set ::GX::ViewerGui::instances $window em_forms $form document_id {}
    dict set ::GX::ViewerGui::instances $window em_forms $form stamp {}
    dict set ::GX::ViewerGui::instances $window em_forms $form job_id {}
    set domain [viewerGuiDesignContextGet $window]
    if {[dict exists $domain em_models $form]} {dict unset domain em_models $form;viewerGuiDesignContextSet $window $domain}
}
proc ::GX::_viewerGuiEMWorkspaceOpen {window form request} {
    if {[dict get $request workspace_id] ne {new}} {return [_viewerGuiEMOpen $window $form [dict get $request workspace_id]]}
    _viewerGuiEMPrepareEdit $window
    set p [_viewerGuiEMForm $window $form]
    set kind [dict get [viewerGuiDesignValues $window] [dict get $p em_parameters kind]]
    set model [::GX::ElectromagneticSimulation::defaultModel $kind]
    set saved [::GX::ElectromagneticSimulation::saveModel $model {} [dict get $request workspace_name]]
    return [_viewerGuiEMOpen $window $form [dict get $saved workspace_id]]
}
proc ::GX::_viewerGuiEMCallbacks {window form} {
    set callbacks {}
    foreach {key operation} {current WorkspaceCurrent dirty Dirty save Save prepare WorkspaceCheck open WorkspaceOpen rename WorkspaceRename close Detach discard Detach} {
        dict set callbacks $key [list ::GX::_viewerGuiEM$operation $window $form]
    }
    return $callbacks
}
proc ::GX::_viewerGuiEMText {window form key message} {
    set p [_viewerGuiEMForm $window $form]
    viewerGuiDesignTextSet $window [dict get $p $key] $message
}
proc ::GX::_viewerGuiEMRemember {window form model} {
    set r [dict get $::GX::ViewerGui::instances $window em_forms $form]
    set context [viewerGuiDesignContextGet $window]
    # A shared History/Workspace snapshot, never a second canonical model.
    set association [dict create document_id [dict get $r document_id] model $model job_id [dict get $r job_id]]
    if {[dict get $r document_id] ne {}} {dict set association generation [lindex [dict get $r stamp] 0]}
    set before $context
    dict set context em_models $form $association
    viewerGuiDesignContextSet $window $context
    if {$before ne $context && ![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window]} {scientificHistoryViewerChanged $window {Electromagnetic model association}}
}
proc ::GX::_viewerGuiEMPrepareEdit {window} {
    if {![dict get $::GX::ViewerGui::instances $window restoring] && [dict exists $::GX::ScientificHistory::viewers $window] && ![scientificHistoryViewerPrepareEdit $window]} {return -code error -errorcode {GX HISTORY EDIT_CANCELLED} {Model operation cancelled before changing the authoritative model}}
}
proc ::GX::_viewerGuiEMOpen {window form id} {
    _viewerGuiEMForm $window $form
    set stamp [_viewerGuiEMStamp $id]
    set model [::GX::ElectromagneticSimulation::loadModel $id]
    _viewerGuiEMPrepareEdit $window
    dict set ::GX::ViewerGui::instances $window em_forms $form [dict create document_id $id stamp $stamp job_id {}]
    _viewerGuiEMSetModel $window $form $model
    _viewerGuiEMRemember $window $form $model
    _viewerGuiEMText $window $form em_status "Opened original electromagnetic model $id."
    return $id
}
proc ::GX::_viewerGuiEMSave {window form} {
    set model [_viewerGuiEMModel $window $form]
    set r [dict get $::GX::ViewerGui::instances $window em_forms $form]
    set id [dict get $r document_id]
    if {$id ne {}} {_viewerGuiEMCurrent $window $form}
    set context [_workspaceHostContext em_models [_viewerGuiEMCallbacks $window $form] $window]
    _viewerGuiEMPrepareEdit $window
    _workspaceHostCheck $context
    set current [dict get $::GX::ViewerGui::instances $window em_forms $form]
    if {[dict get $current document_id] ne $id || [dict get $current stamp] ne [dict get $r stamp]} {error {Electromagnetic model changed while preparing Save; preserve the draft and reopen it}}
    if {$id ne {}} {_viewerGuiEMCurrent $window $form}
    set saved [::GX::ElectromagneticSimulation::saveModel $model $id [dict get $model model_id]]
    set id [dict get $saved workspace_id]
    dict set ::GX::ViewerGui::instances $window em_forms $form document_id $id
    dict set ::GX::ViewerGui::instances $window em_forms $form stamp [_viewerGuiEMStamp $id]
    dict set ::GX::ViewerGui::instances $window em_forms $form baseline [_viewerGuiEMDraft $window $form]
    _viewerGuiEMRemember $window $form $model
    _viewerGuiEMText $window $form em_status "Saved original electromagnetic model $id."
    return $id
}
proc ::GX::_viewerGuiEMPrepare {window form} {
    return [sessionWorkspaceHostPrepare [_workspaceHostContext em_models [_viewerGuiEMCallbacks $window $form] $window] {changing models}]
}
proc ::GX::_viewerGuiEMInitialize {window context} {
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {[dict get $c type] ne {section} || ![dict exists $c properties em_parameters]} continue
        set form [dict get $c id]
        dict set ::GX::ViewerGui::instances $window em_forms $form [dict create document_id {} stamp {} job_id {}]
        if {[dict get $::GX::ViewerGui::instances $window token] eq {} || [dict get $::GX::ViewerGui::instances $window mode] eq {demo}} {
            viewerGuiDesignTextSet $window [dict get $c properties em_status] {Open a Session and reopen this Viewer to edit or solve a model.}
            continue
        }
        dict set ::GX::ViewerGui::instances $window em_forms $form baseline [_viewerGuiEMDraft $window $form]
        viewerGuiDesignEMCommand $window $form refresh
        if {[dict exists $context em_document_id]} {_viewerGuiEMOpen $window $form [dict get $context em_document_id]}
    }
}
# Read-only association admission. History may describe an earlier valid model
# in the SAME generation; reviewing it must never replay or save that model.
proc ::GX::_viewerGuiEMAssociationCheck {definition association {current 1}} {
    if {[dict get $definition type] ne {section} || ![dict exists $definition properties em_parameters]} {error {Saved electromagnetic state names an undeclared EM form}}
    modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1
    ::GX::ElectromagneticSimulation::validate [dict get $association model]
    set id [dict get $association document_id]
    set result {}
    if {$id ne {}} {
        set stamp [_viewerGuiEMStamp $id]
        if {[lindex $stamp 0] ne [dict get $association generation]} {error {Saved EM model generation no longer exists}}
        if {$current && [::GX::ElectromagneticSimulation::loadModel $id] ne [dict get $association model]} {error {Saved interface refers to a changed EM model; open the current model explicitly}}
        dict set result document_id $id
        dict set result stamp $stamp
    }
    set job [dict get $association job_id]
    if {$job ne {}} {
        if {$id eq {}} {error {Saved electromagnetic Job has no canonical model association}}
        set status [::GX::ElectromagneticSimulation::jobStatus $job]
        if {[dict get $status provider_id] ne {math.electromagnetic_simulation.fem2d} || ![dict exists $status source_identities workspace]} {error {Saved Job is not an owned electromagnetic model execution}}
        set source [dict get $status source_identities workspace]
        if {[dict get $source id] ne $id || [dict get $source generation] ne [dict get $association generation]} {error {Saved electromagnetic Job refers to a different model generation}}
        # A retained Job may legitimately precede a later model edit. Preserve
        # that exact source receipt rather than relabeling its result current.
        dict set result job_id $job
        dict set result job_source [dict get $status source_identities]
    }
    return $result
}
proc ::GX::_viewerGuiEMRestoreCheck {window context} {
    dict for {form association} [datasetPublicationV2DictDefault $context em_models {}] {
        _viewerGuiEMForm $window $form
        set id [dict get $association document_id]
        if {$id eq {}} continue
        if {[lindex [_viewerGuiEMStamp $id] 0] ne [dict get $association generation]} {error {Saved EM model generation no longer exists}}
        set r [dict get $::GX::ViewerGui::instances $window em_forms $form]
        if {[dict get $r document_id] eq $id} {
            _viewerGuiEMCurrent $window $form
        } elseif {[::GX::ElectromagneticSimulation::loadModel $id] ne [dict get $association model]} {
            error {Saved interface refers to a changed EM model; open the current model explicitly}
        }
    }
}
proc ::GX::_viewerGuiEMRestore {window values} {
    set context [viewerGuiDesignContextGet $window]
    foreach form [dict keys [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] em_forms {}]] {
        set association [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $context em_models {}] $form {}]
        if {$association eq {}} {
            set p [_viewerGuiEMForm $window $form];set baseline {}
            dict for {field id} [dict get $p em_parameters] {dict set baseline $field [dict get $values $id]}
            dict set ::GX::ViewerGui::instances $window em_forms $form [dict create document_id {} stamp {} job_id {} baseline $baseline]
            continue
        }
        set id [dict get $association document_id];set model [dict get $association model]
        if {$id ne {}} {
            if {[::GX::ElectromagneticSimulation::loadModel $id] ne $model} {::GX::ElectromagneticSimulation::saveModel $model $id}
            set stamp [_viewerGuiEMStamp $id]
        } else {set stamp {}}
        dict set ::GX::ViewerGui::instances $window em_forms $form [dict create document_id $id stamp $stamp job_id [dict get $association job_id]]
        _viewerGuiEMSetModel $window $form $model
    }
}
proc ::GX::viewerGuiDesignEMCommand {window form action} {
    if {$action eq {runtime}} {
        if {![viewerGuiDesignGuard $window]} {error {Session changed; reopen this Viewer}}
        return [configurationOpenPage runtime]
    }
    set p [_viewerGuiEMForm $window $form]
    set r [dict get $::GX::ViewerGui::instances $window em_forms $form]
    switch -- $action {
        refresh {
            set ids {};set descriptions {}
            foreach item [::GX::ElectromagneticSimulation::listModels] {lappend ids [dict get $item id];lappend descriptions "[dict get $item id]: [dict get [sessionWorkspaceGet [dict get $item id]] name]"}
            viewerGuiDesignChoicesSet $window [dict get $p em_models] $ids
            _viewerGuiEMText $window $form em_status "[llength $ids] original electromagnetic model(s) in this Session."
            _viewerGuiEMText $window $form em_log [join $descriptions \n]
            return [dict create status inspected models $ids]
        }
        new_electric - new_magnetic {
            if {![_viewerGuiEMPrepare $window $form]} {return [dict create status cancelled]}
            _viewerGuiEMPrepareEdit $window
            set kind [expr {$action eq {new_electric}?{electrostatic_2d}:{magnetostatic_2d}}]
            set model [::GX::ElectromagneticSimulation::defaultModel $kind]
            dict set ::GX::ViewerGui::instances $window em_forms $form [dict create document_id {} stamp {} job_id {}]
            _viewerGuiEMSetModel $window $form $model;_viewerGuiEMRemember $window $form $model
            _viewerGuiEMText $window $form em_status {New unsaved native model draft. Validate or Save before solving.}
            return [dict create status draft kind $kind]
        }
        validate {
            set model [_viewerGuiEMModel $window $form]
            _viewerGuiEMText $window $form em_log $model
            _viewerGuiEMText $window $form em_status {Native EM model validation succeeded; no solver ran.}
            return [dict create status validated model $model]
        }
        open {
            set id [dict get [viewerGuiDesignValues $window] [dict get $p em_models]]
            if {$id eq {}} {error {Choose a saved electromagnetic model first}}
            if {![_viewerGuiEMPrepare $window $form]} {return [dict create status cancelled]}
            return [dict create status opened document_id [_viewerGuiEMOpen $window $form $id]]
        }
        save {return [dict create status saved document_id [_viewerGuiEMSave $window $form]]}
        duplicate {
            set current [_viewerGuiEMCurrent $window $form]
            if {![_viewerGuiEMPrepare $window $form]} {return [dict create status cancelled]}
            _viewerGuiEMPrepareEdit $window
            set id [dict get $current document_id]
            set name [sessionWorkspaceAvailableName "[dict get [sessionWorkspaceGet $id] name] copy"]
            set copy [sessionWorkspaceImport [sessionWorkspaceExport $id] $name]
            return [dict create status duplicated document_id [_viewerGuiEMOpen $window $form [dict get $copy workspace_id]]]
        }
        workspaces - rename {
            return [sessionWorkspaceViewerAction em_models [_viewerGuiEMCallbacks $window $form] $window [expr {$action eq {workspaces}?{manager}:{rename}}] propagate]
        }
        run {
            if {[dict get $r job_id] ne {}} {
                set prior [::GX::ElectromagneticSimulation::jobStatus [dict get $r job_id]]
                if {[dict get $prior state] in {QUEUED PREPARING RUNNING FINALIZING CANCELLING}} {error {This form already has an active managed FEM Job}}
            }
            set id [_viewerGuiEMSave $window $form]
            set job [::GX::ElectromagneticSimulation::runAsync [::GX::ElectromagneticSimulation::loadModel $id] {} $id]
            dict set ::GX::ViewerGui::instances $window em_forms $form job_id $job
            _viewerGuiEMRemember $window $form [::GX::ElectromagneticSimulation::loadModel $id]
            _viewerGuiEMText $window $form em_status "Managed real Gmsh/GetDP Job submitted: $job."
            return [dict create status submitted job_id $job]
        }
        jobs - reconnect {
            set current [_viewerGuiEMCurrent $window $form];set found {}
            foreach job [scriptJobList] {
                if {[catch {scientificExecutionStatus [dict get $job id]} status]} continue
                if {[dict get $status provider_id] eq {math.electromagnetic_simulation.fem2d} && [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $status source_identities {}] workspace {}] ne {} && [dict get $status source_identities workspace id] eq [dict get $current document_id]} {lappend found [dict get $job id]}
            }
            if {[dict exists $p em_jobs]} {
                set selector [dict get $p em_jobs];set selected [dict get [viewerGuiDesignValues $window] $selector]
                viewerGuiDesignChoicesSet $window $selector $found
                if {$action eq {jobs}} {
                    if {$selected ni $found && [llength $found]==1} {viewerGuiDesignValueSet $window $selector [lindex $found 0]}
                    return [dict create status inspected document_id [dict get $current document_id] jobs $found]
                }
                if {$selected ni $found} {error {Choose one of this model's actual retained FEM Jobs, then Reconnect}}
            } elseif {[llength $found]==1} {set selected [lindex $found 0]} else {error {Declare the retained Job selector to choose between this model's FEM Jobs}}
            dict set ::GX::ViewerGui::instances $window em_forms $form job_id $selected
            _viewerGuiEMRemember $window $form [::GX::ElectromagneticSimulation::loadModel [dict get $current document_id]]
            return [viewerGuiDesignEMCommand $window $form status]
        }
        status - cancel - log - results - publish {
            set r [_viewerGuiEMCurrent $window $form];set job [dict get $r job_id]
            if {$job eq {}} {error {Run or reconnect an actual managed FEM Job first}}
            set status [::GX::ElectromagneticSimulation::jobStatus $job]
            if {[dict get $status provider_id] ne {math.electromagnetic_simulation.fem2d} || ![dict exists $status source_identities workspace id] || [dict get $status source_identities workspace id] ne [dict get $r document_id]} {error {FEM Job does not belong to the current original model}}
            switch -- $action {
                status {_viewerGuiEMText $window $form em_status "FEM Job $job: [dict get $status state]";return $status}
                cancel {set result [::GX::ElectromagneticSimulation::cancel $job];_viewerGuiEMText $window $form em_status {Cancellation requested; terminal cancellation is not yet confirmed.};return $result}
                log {
                    set page [::GX::ElectromagneticSimulation::jobLog $job 0 65536]
                    set text [dict get $page content]
                    if {[dict exists $page diagnostic] && [dict get $page diagnostic] ne {}} {append text "\n[dict get $page diagnostic]"}
                    if {[dict exists $page next_offset] && [dict exists $page size] && [dict get $page next_offset]<[dict get $page size]} {append text "\nFirst 64 KiB shown; the complete retained log remains in the shared Jobs workspace."}
                    _viewerGuiEMText $window $form em_log $text
                    return [dict create status inspected job_id $job page $page]
                }
                results {
                    set receipt [::GX::ElectromagneticSimulation::resultDescribe $job]
                    set preview [::GX::ElectromagneticSimulation::resultPreview $job 0 20]
                    set report [expr {[dict exists $p em_report]?{em_report}:{em_log}}]
                    _viewerGuiEMText $window $form $report "$receipt\n\nCell preview (not a substituted nodal field):\n$preview"
                    return [dict create status inspected receipt $receipt preview $preview]
                }
                publish {
                    set id [dict get [viewerGuiDesignValues $window] [dict get $p em_output_id]]
                    set result [::GX::ElectromagneticSimulation::publish $job $id]
                    dict set ::GX::ViewerGui::instances $window em_forms $form stamp [_viewerGuiEMStamp [dict get $r document_id]]
                    _viewerGuiEMRemember $window $form [::GX::ElectromagneticSimulation::loadModel [dict get $r document_id]]
                    viewerGuiDesignValueSet $window [dict get $p em_dataset] [dict get $result dataset_id]
                    _viewerGuiEMText $window $form em_status "Published exact canonical node/cell fields: [dict get $result dataset_id]."
                    return $result
                }
            }
        }
        field - field_3d - profile - publish_charts - export_field {
            set id [dict get [viewerGuiDesignValues $window] [dict get $p em_dataset]]
            set info [::GX::ElectromagneticSimulation::fieldDescribe $id];set roles [dict get $info roles]
            modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
            set binding [dict create schema GXTXT_CELL_FIELD_BINDING_v1 nodes_dataset_id [dict get $info nodes_dataset_id] node_id_variable_id [dict get $roles node_id_variable_id] x_variable_id [dict get $roles node_x_variable_id] y_variable_id [dict get $roles node_y_variable_id] cell_id_variable_id [dict get $roles cell_id_variable_id] node_variable_ids [dict get $roles node_variable_ids] scalar_variable_id [dict get $roles scalar_variable_id]]
            set spec [::GX::PlotDatasetAPIv4::cellFieldSpec $id [dict get $roles cell_x_variable_id] [dict get $roles cell_y_variable_id] $binding {Actual FEM cell field — exact source topology}]
            if {$action eq {profile}} {
                if {![dict exists $p em_profile_plot]} {error {Declare the actual cell-sample Plot component}}
                set spec [::GX::PlotDatasetAPIv4::cellFieldProfileSpec $spec]
                viewerGuiDesignPlotSet $window [dict get $p em_profile_plot] $spec
                _viewerGuiEMText $window $form em_status {Actual cell-centroid samples at all Y values; this scatter is not an interpolated centerline.}
            } elseif {$action eq {publish_charts}} {
                _viewerGuiEMPrepareEdit $window
                set producer [dict get $::GX::ViewerGui::instances $window module]
                set graphs {}
                foreach suffix {field profile} chart [list $spec [::GX::PlotDatasetAPIv4::cellFieldProfileSpec $spec]] {
                    set ref [::GX::PlotDatasetAPIv4::upsertPlotFromSpec $producer "$producer:$id:$suffix" $chart]
                    ::GX::PlotDatasetAPIv4::render $ref
                    dict set graphs $suffix $ref
                }
                sessionPersistenceCommit
                _viewerGuiEMText $window $form em_status {Published two independent source-bound charts to Plots: exact cell field and actual centroid samples.}
                return [dict create status published dataset_id $id graphs $graphs]
            } elseif {$action eq {export_field}} {
                if {![dict exists $p em_field_plot]} {error {Declare an EM field Plot component}}
                set target [dict get $p em_field_plot]
                if {![dict exists $::GX::ViewerGui::instances $window bindings $target spec]} {error {Show the exact cell field before exporting it}}
                set shown [dict get $::GX::ViewerGui::instances $window bindings $target spec]
                set series [dict get [lindex [dict get $shown panels] 0] series]
                if {[llength $series]!=1 || ![dict exists [lindex $series 0] cell_field] || [dict get [lindex $series 0] dataset_id] ne $id} {error {Show the selected Dataset's exact cell field before exporting it}}
                ::GX::PlotDatasetAPIv4::cellFieldSourceIdentity $shown
                set destination [workspaceSaveFile export_dir -parent $window -title {Export native field figure} -defaultextension .png -filetypes {{{PNG} {.png}} {{SVG} {.svg}} {{PDF} {.pdf}}}]
                if {$destination eq {}} {return [dict create status cancelled]}
                if {[string tolower [file extension $destination]] ni {.png .svg .pdf}} {error {Choose PNG, SVG or PDF for native field export}}
                set plot [dict get $::GX::ViewerGui::instances $window widgets $target].plot
                set exported [filePublicationPublishBundle [list [dict create id field destination $destination writer [list ::GX::_viewerGuiEMExportWriter $plot [string tolower [file extension $destination]]]]] replace]
                _viewerGuiEMText $window $form em_status {Exported the current native field through File Publication.}
                return [dict create status exported files $exported]
            } elseif {$action eq {field_3d}} {
                if {![dict exists $p em_field_native3d]} {error {Declare the planar field Native3D component}}
                viewerGuiDesignNative3DSet $window [dict get $p em_field_native3d] [dict create kind cell_field spec $spec]
                _viewerGuiEMText $window $form em_status {Actual planar FEM triangles in Native3D; Z=0 is a display embedding, not a 3D solve or CAD volume.}
            } else {
                if {![dict exists $p em_field_plot]} {error {Declare an EM field Plot component}}
                viewerGuiDesignPlotSet $window [dict get $p em_field_plot] $spec
            }
            return [dict create status bound dataset_id $id source $info spec $spec]
        }
        default {error {Unsupported electromagnetic model form command}}
    }
}
proc ::GX::_viewerGuiEMExportWriter {plot extension channel context} {
    set handle [file tempfile path];close $handle
    set figure $path$extension
    try {
        ::GX::PlotDatasetAPIv4::widgetExport $plot $figure
        set input [open $figure rb]
        try {fcopy $input $channel} finally {close $input}
    } finally {file delete -force -- $path $figure}
}
