# SPDX-License-Identifier: GPL-3.0-or-later
# Import-only declared source form. Document/Resource owns capture and commit.
# This child owns no parser, registry, writer, native scene or scientific model.
proc ::GX::_viewerGuiPCBDesignValidate {design} {
    set definitions {};set commands {};set controls {};set forms {}
    foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties];set present 0
        foreach key [dict keys $p] {if {[string match pcb_* $key]} {set present 1}}
        if {!$present} continue
        if {[dict get $c type] ne {section}} {error {PCB source properties require a declared section}}
        foreach key [dict keys $p] {if {[string match pcb_* $key] && $key ni {pcb_source_kind pcb_sources pcb_status pcb_inspector pcb_commands}} {error "Unknown PCB source property: $key"}}
        foreach key {pcb_source_kind pcb_sources pcb_status pcb_inspector pcb_commands} {if {![dict exists $p $key]} {error "Incomplete PCB source form: $key"}}
        if {[dict get $p pcb_source_kind] ne {eagle_pair_fixed_v1}} {error {Only the fixed-pair import-only PCB source kind is admitted}}
        foreach key {transform_kind numeric_kind numeric_expression scientific_provider em_parameters workbench_parameters tex_source catalog_owner plot_dataset plot_series viewport_anchor annotation_fields} {if {[dict exists $p $key]} {error {PCB source section cannot share another purpose-form owner}}}
        if {![dict exists $design requirements VIEWER_GUI_HOST_API_v1] || [dict get $design requirements VIEWER_GUI_HOST_API_v1]!=1} {error {PCB source form requires VIEWER_GUI_HOST_API_v1@1}}
        lappend forms [dict get $c id]
        foreach {key types} {pcb_sources choice pcb_status {label status} pcb_inspector log} {
            set id [dict get $p $key]
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni $types || $id in $controls || $id in $forms} {error "PCB source form needs a distinct declared inert $key control"}
            if {[dict exists $definitions $id properties change_action]} {error {PCB source controls cannot dispatch change callbacks}}
            lappend controls $id
        }
        set operations {}
        dict for {action operation} [dict get $p pcb_commands] {
            if {$operation ni {import_pair refresh inspect cancel} || $operation in $operations || $action in $commands || $action in {undo redo fit zoom_in zoom_out gui_inspect} || ![dict exists $design handlers $action]} {error {PCB source commands require four unique finite declared handlers}}
            set effect [expr {$operation eq {import_pair} ? {mutating} : {presentation}}]
            if {[dict get $design handlers $action effect] ne $effect || [dict get $design handlers $action arguments] ne {window action}} {error "PCB $operation requires the existing $effect handler contract"}
            if {[datasetPublicationV2DictDefault $design initial_action {}] eq $action} {error {PCB source actions require explicit user invocation}}
            lappend commands $action;lappend operations $operation
        }
        if {[lsort $operations] ne {cancel import_pair inspect refresh}} {error {Declare all four PCB source commands}}
    }
    if {$forms eq {}} return
    if {[llength $forms]>8} {error {At most eight bounded PCB source forms belong to one Viewer}}
    foreach form $forms {if {$form in $controls} {error {PCB forms and all form controls must be disjoint}}}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        foreach key {change_action scientific_netlist_action} {if {[datasetPublicationV2DictDefault $p $key {}] in $commands} {error {PCB commands cannot be implicit change/netlist callbacks}}}
        foreach key {transform_commands plot_series_commands visibility_commands} {
            dict for {action target} [datasetPublicationV2DictDefault $p $key {}] {if {$action in $commands} {error {PCB command is already owned by another form}}}
        }
        foreach key {em_actions catalog_actions} {
            dict for {operation action} [datasetPublicationV2DictDefault $p $key {}] {if {$action in $commands} {error {PCB command is already owned by another form}}}
        }
        if {[dict exists $p action] && [dict get $p action] in $commands} {
            foreach key {diagram_tool raster_tool raster_command component_visibility plot_navigation_target} {if {[dict exists $p $key]} {error {PCB commands cannot share tools, visibility or navigation targets}}}
        }
        # Other purpose forms cannot reinterpret a PCB control. Ordinary labels
        # and toolbar action lists are not interpreted as reference fields.
        dict for {key value} $p {
            if {[string match pcb_* $key]} continue
            if {![regexp {^(transform_|numeric_|scientific_|plot_|em_|workbench_|tex_|catalog_|annotation_fields$|viewport_anchor$|component_visibility$|visibility_commands$|diagram_tool$|raster_tool$|raster_command$)} $key]} continue
            set budget 0
            if {[_viewerGuiPCBReferenceOverlap $value [concat $controls $forms] 0 budget]} {error {PCB controls must be disjoint from other declared form targets}}
        }
    }
}
proc ::GX::_viewerGuiPCBReferenceOverlap {value controls depth budgetName} {
    upvar 1 $budgetName budget
    if {[incr budget]>100000 || $depth>32} {error {Declared form reference scan exceeds its finite bound}}
    if {$value in $controls} {return 1}
    if {[catch {llength $value} n] || $n<1} {return 0}
    foreach item $value {if {$item ne $value && [_viewerGuiPCBReferenceOverlap $item $controls [expr {$depth+1}] budget]} {return 1}}
    return 0
}
proc ::GX::_viewerGuiPCBProofValidate {design proof snapshot} {
    if {[lsort [dict keys $proof]] ne {backend_sha256 commands controls design_sha256 forms grants kind module_id profile project_sha256 provider_id schema source_sha256}} {error {Invalid PCB source admission fields}}
    if {[dict get $proof schema] ne {gxtxt.viewer_pcb_source_admission.v1} || [dict get $proof profile] ne {document_view_v1} || [dict get $proof kind] ne {eagle_pair_fixed_v1} || [dict get $proof module_id] ne [dict get $design module_id] || [dict get $proof provider_id] ne [dict get $design provider_id]} {error {PCB source admission has a different owner/profile}}
    foreach key {source_sha256 design_sha256 project_sha256} {if {[dict get $proof $key] ne [dict get $snapshot $key]} {error {PCB source admission differs from validated source/design/project}}}
    set backend [file join $::GX::scriptDir core python gxtxt_viewer_development.py]
    if {[sha256File $backend] ne [dict get $proof backend_sha256]} {error {PCB source admission backend changed; validate and reopen}}
    if {[dict get $proof grants] ne {VIEWER_GUI_HOST_API_v1 pcb_source_form}} {
        if {[lsort [dict keys [dict get $proof grants]]] ne {VIEWER_GUI_HOST_API_v1} || [dict get $proof grants VIEWER_GUI_HOST_API_v1] ne {pcb_source_form}} {error {PCB source admission requires its exact finite host grant}}
    }
    set forms {};set commands {};set controls {}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {![dict exists $p pcb_source_kind]} continue
        set form [dict get $c id];lappend forms $form
        dict set commands $form [dict get $p pcb_commands]
        set fields {};foreach key {pcb_sources pcb_status pcb_inspector} {dict set fields $key [dict get $p $key]}
        dict set controls $form $fields
    }
    if {$forms eq {} || [dict get $proof forms] ne $forms || [lsort [dict keys [dict get $proof commands]]] ne [lsort $forms] || [lsort [dict keys [dict get $proof controls]]] ne [lsort $forms]} {error {PCB proof does not cover exactly the declared forms}}
    foreach form $forms {
        foreach key {commands controls} {
            set expected [dict get [set $key] $form];set actual [dict get $proof $key $form]
            if {[lsort [dict keys $actual]] ne [lsort [dict keys $expected]]} {error {PCB proof has different form controls/commands}}
            dict for {name value} $expected {if {[dict get $actual $name] ne $value} {error {PCB proof has different form controls/commands}}}
        }
    }
    set metadata [viewerGuiHostApiInfo]
    foreach {key value} {pcb_source_form_kind eagle_pair_fixed_v1 pcb_source_form_profile document_view_v1 pcb_source_form_capability pcb_source_form pcb_source_form_commands {import_pair refresh inspect cancel} pcb_source_form_entrypoint viewerGuiDesignAction pcb_source_form_implicit_import 0 pcb_source_form_scope import_only_completed_canonical_snapshots pcb_source_form_native_projection 0} {
        if {![dict exists $metadata $key] || [dict get $metadata $key] ne $value} {error {Current CORE PCB form metadata is incompatible}}
    }
    return $proof
}
proc ::GX::_viewerGuiPCBAction {window action} {
    if {![dict exists $::GX::ViewerGui::instances $window]} {return {}}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {[dict exists $c properties pcb_commands $action]} {return [list [dict get $c id] [dict get $c properties pcb_commands $action]]}
    }
    return {}
}
proc ::GX::_viewerGuiPCBInitialize {window} {
    # Authored initial choices cannot masquerade as validated source records.
    # Refresh/Inspect are explicit; construction never starts an import.
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {![dict exists $c properties pcb_source_kind]} continue
        set p [dict get $c properties]
        foreach id [list [dict get $c id] [dict get $p pcb_sources] [dict get $p pcb_status] [dict get $p pcb_inspector]] {
            if {![dict exists $::GX::ViewerGui::instances $window pcb_component_incarnations $id]} {_viewerGuiPCBComponentMounted $window $id [dict get $::GX::ViewerGui::instances $window widgets $id]}
        }
        viewerGuiDesignChoicesSet $window [dict get $p pcb_sources] {}
        viewerGuiDesignValueSet $window [dict get $p pcb_sources] {}
        _viewerGuiPCBDisplay $window [dict get $c id] idle {Import the original pair explicitly, or Refresh completed canonical snapshots. Native projection is not provided by this import-only form.}
    }
}
proc ::GX::_viewerGuiPCBRestoreCheck {window state} {
    set i [dict get $::GX::ViewerGui::instances $window]
    set forms {};foreach c [dict get $i design components] {if {[dict exists $c properties pcb_source_kind]} {dict set forms [dict get $c id] [dict get $c properties pcb_sources]}}
    set bindings [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $state domain_state {}] pcb_source_bindings {}]
    if {[catch {dict size $bindings}]} {error {Saved PCB source references must be a bounded dictionary}}
    if {$forms eq {} && $bindings eq {}} return
    set referenced [expr {$bindings ne {}}]
    dict for {form control} $forms {if {[datasetPublicationV2DictDefault [dict get $state values] $control {}] ne {}} {set referenced 1}}
    if {$referenced} {
        if {[dict get $i mode] ne {runtime} || [dict get $i token] eq {} || [dict get $i token] ne [interactiveDocumentSessionToken] || ![dict exists $::GX::ViewerDevelopment::windows $window pcb_source_form_admission]} {error {Saved PCB sources require an admitted runtime Viewer and actual Session}}
        set host [dict get $::GX::ViewerDevelopment::windows $window]
        set snapshot [_viewerDevelopmentSnapshot [dict get $host project]]
        if {$snapshot ne [dict get $host validated_snapshot]} {error {Saved PCB sources belong to a changed project}}
        _viewerGuiPCBProofValidate [dict get $i design] [dict get $host pcb_source_form_admission] $snapshot
    }
    set owner [dict create module_id [dict get $i module] provider_id [dict get $i provider]]
    dict for {form binding} $bindings {
        if {![dict exists $forms $form] || [lsort [dict keys $binding]] ne {document_id stamp}} {error {Saved PCB reference targets an undeclared source form}}
        set record [_pcbPairDocumentRead [dict get $binding document_id] $owner]
        if {[dict get $binding stamp] ne [dict get $record stamp]} {error {Saved PCB canonical source identity changed; restore was refused}}
    }
    dict for {form control} $forms {
        set document [datasetPublicationV2DictDefault [dict get $state values] $control {}]
        if {$document ne {}} {_pcbPairDocumentRead $document $owner}
    }
}
proc ::GX::_viewerGuiPCBRestore {window} {
    set i [dict get $::GX::ViewerGui::instances $window]
    if {[dict get $i mode] ne {runtime} || [dict get $i token] eq {} || ![dict exists $::GX::ViewerDevelopment::windows $window pcb_source_form_admission]} {return}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {![dict exists $c properties pcb_source_kind]} continue
        set form [dict get $c id];set control [dict get $c properties pcb_sources]
        _viewerGuiPCBRefresh $window $form
        set document [dict get [viewerGuiDesignValues $window] $control]
        if {$document ne {}} {_viewerGuiPCBSelect $window $form $document}
    }
}
proc ::GX::_viewerGuiPCBRootIdentity {path} {
    file lstat $path s
    if {$s(type) ne {directory}} {error {PCB source form requires the actual Session directory}}
    return [list $s(dev) $s(ino) $s(mode) $s(uid) $s(gid)]
}
proc ::GX::_viewerGuiPCBWidgetIdentities {window form} {
    set i [dict get $::GX::ViewerGui::instances $window]
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    set result {}
    foreach id [list $form [dict get $p pcb_sources] [dict get $p pcb_status] [dict get $p pcb_inspector]] {
        set widget [dict get $i widgets $id]
        if {![winfo exists $widget] || [winfo toplevel $widget] ne $window} {error {PCB form component lifetime changed}}
        set xid [winfo id $widget]
        if {![dict exists $i pcb_component_incarnations $id]} {error {PCB component was removed or replaced}}
        set tracked [dict get $i pcb_component_incarnations $id]
        if {[dict get $tracked widget] ne $widget || [dict get $tracked xid] ne $xid} {error {PCB component identity changed}}
        dict set result $id $xid
    }
    return $result
}
proc ::GX::_viewerGuiPCBComponentMounted {window id widget} {
    # An instance's admitted design is immutable. Ordinary UIField mounts must
    # not rescan it; even the no-PCB empty membership set is cached once.
    if {![dict exists $::GX::ViewerGui::instances $window pcb_owned_components]} {
        set owned {}
        foreach c [dict get $::GX::ViewerGui::instances $window design components] {
            if {![dict exists $c properties pcb_source_kind]} continue
            set p [dict get $c properties]
            foreach component [list [dict get $c id] [dict get $p pcb_sources] [dict get $p pcb_status] [dict get $p pcb_inspector]] {dict set owned $component 1}
        }
        if {[dict size $owned]>32} {error {PCB component membership exceeds its admitted32-ID limit}}
        dict set ::GX::ViewerGui::instances $window pcb_owned_components $owned
    }
    if {![dict exists $::GX::ViewerGui::instances $window pcb_owned_components $id]} return
    set incarnation pcb_component_[incr ::GX::ViewerGui::serial]
    dict set ::GX::ViewerGui::instances $window pcb_component_incarnations $id [dict create widget $widget xid [winfo id $widget] incarnation $incarnation]
    bind $widget <Destroy> +[list ::GX::_viewerGuiPCBComponentDestroyed $window $id $widget $incarnation %W]
}
proc ::GX::_viewerGuiPCBComponentDestroyed {window id widget incarnation actual} {
    if {$actual ne $widget || ![dict exists $::GX::ViewerGui::instances $window pcb_component_incarnations $id]} return
    if {[dict get $::GX::ViewerGui::instances $window pcb_component_incarnations $id incarnation] ne $incarnation} return
    _viewerGuiPCBComponentReplacing $window $id
}
proc ::GX::_viewerGuiPCBComponentIncarnations {window form} {
    set result {}
    dict for {id xid} [_viewerGuiPCBWidgetIdentities $window $form] {dict set result $id [dict get $::GX::ViewerGui::instances $window pcb_component_incarnations $id incarnation]}
    return $result
}
proc ::GX::_viewerGuiPCBBinding {window form} {
    return [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [viewerGuiDesignContextGet $window] pcb_source_bindings {}] $form {}]
}
proc ::GX::_viewerGuiPCBAuthority {window form epoch} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerDevelopment::windows $window pcb_source_form_admission]} {error {PCB source form requires the currently admitted Development or installed Viewer}}
    set i [dict get $::GX::ViewerGui::instances $window];set host [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict get $i mode] ne {runtime} || [dict get $i restoring] || [dict get $host busy] ne {} || [dict get $host status] in {RUNNING VALIDATING REJECTED FAILED SOURCE_CHANGED}} {error {PCB source form is not currently admitted or its compiled event is busy}}
    if {[catch {_viewerDevelopmentSnapshot [dict get $host project]} snapshot] || $snapshot ne [dict get $host validated_snapshot]} {
        catch {dict unset ::GX::ViewerDevelopment::windows $window pcb_source_form_admission}
        error {PCB project changed; validate and reopen its matching Viewer}
    }
    set design [viewerGuiDesignRead [file join [dict get $host project] design.gxtxt-viewer]]
    if {$design ne [dict get $i design]} {error {PCB live design differs from the admitted design}}
    if {[catch {_viewerGuiPCBProofValidate $design [dict get $host pcb_source_form_admission] $snapshot} proof]} {
        catch {dict unset ::GX::ViewerDevelopment::windows $window pcb_source_form_admission}
        error {PCB source admission changed; validate and reopen its matching Viewer}
    }
    if {$form ni [dict get $proof forms]} {error {Select a currently admitted PCB source form}}
    set domain [viewerGuiDesignContextGet $window]
    if {![dict exists $domain restricted_cpp snapshot] || [dict get $domain restricted_cpp snapshot] ne $snapshot} {error {PCB Viewer context differs from its compiled source}}
    set token [interactiveDocumentSessionToken]
    if {$token eq {} || [dict get $i token] ne $token} {error {PCB form requires a current nonempty Session lifetime}}
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    set selected [dict get [viewerGuiDesignValues $window] [dict get $p pcb_sources]]
    if {$selected ne {} && ![interactiveDocumentIdValid $selected]} {error {Choose an admitted canonical PCB source Document}}
    set session [file normalize $::GX::currentSession]
    return [dict create epoch $epoch form $form module_id [dict get $i module] provider_id [dict get $i provider] project [dict get $host project] snapshot $snapshot proof $proof project_stamp [_viewerGuiTransformProjectStamp [dict get $host project]] xid [winfo id $window] component_xids [_viewerGuiPCBWidgetIdentities $window $form] component_incarnations [_viewerGuiPCBComponentIncarnations $window $form] opened_us [dict get $i opened_us] design $design token $token session $session session_root [_viewerGuiPCBRootIdentity $session] workspace_id [dict get $i workspace_id] workspace_stamp [dict get $i workspace_stamp] prior_binding [_viewerGuiPCBBinding $window $form] selected_document $selected]
}
proc ::GX::_viewerGuiPCBSame {window form epoch} {
    return [expr {[dict exists $::GX::ViewerGui::instances $window pcb_source_forms $form epoch] && [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form epoch] eq $epoch}]
}
proc ::GX::_viewerGuiPCBCurrent {window form epoch authority} {
    if {![_viewerGuiPCBSame $window $form $epoch]} {return 0}
    set r [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
    if {[dict get $r cancelled] || [dict get $r authority] ne $authority || [dict get $r state] in {CANCELLING CANCELLED FAILED STALE OUTCOME_UNKNOWN COMMITTED COMMITTED_DISPLAY_UNAVAILABLE}} {return 0}
    if {[catch {_viewerGuiPCBAuthority $window $form $epoch} current]} {return 0}
    return [expr {$current eq $authority}]
}
proc ::GX::_viewerGuiPCBCapturedHost {window form r} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} {return 0}
    set i [dict get $::GX::ViewerGui::instances $window];set a [dict get $r authority]
    if {[dict get $i opened_us] ne [dict get $a opened_us] || [winfo id $window] ne [dict get $a xid] || [dict get $i token] ne [dict get $a token] || [dict get $i design] ne [dict get $a design]} {return 0}
    if {[catch {_viewerGuiPCBWidgetIdentities $window $form} widgets]} {return 0}
    if {[catch {_viewerGuiPCBComponentIncarnations $window $form} incarnations]} {return 0}
    return [expr {$widgets eq [dict get $a component_xids] && $incarnations eq [dict get $a component_incarnations]}]
}
proc ::GX::_viewerGuiPCBDisplay {window form state text} {
    if {[string bytelength $text]>65536} {error {PCB inspector summary exceeds64KiB}}
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    viewerGuiDesignTextSet $window [dict get $p pcb_status] $state
    viewerGuiDesignTextSet $window [dict get $p pcb_inspector] $text
}
proc ::GX::_viewerGuiPCBStateValid {state} {
    return [expr {$state in {CHOOSING QUEUED RUNNING WORKER_RUNNING PREPARING STREAMING VALIDATING COMMITTING CANCELLING CANCELLED FAILED STALE OUTCOME_UNKNOWN COMMITTED COMMITTED_DISPLAY_UNAVAILABLE}}]
}
proc ::GX::_viewerGuiPCBProgress {window form epoch state detail} {
    if {![_viewerGuiPCBSame $window $form $epoch] || ![_viewerGuiPCBStateValid $state]} return
    set r [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
    if {[dict get $r cancelled] || ![_viewerGuiPCBCapturedHost $window $form $r]} return
    dict set r state $state;dict set r detail $detail
    dict set ::GX::ViewerGui::instances $window pcb_source_forms $form $r
    _viewerGuiPCBDisplay $window $form $state $detail
}
proc ::GX::_viewerGuiPCBSummary {record} {
    set summary [dict get $record summary]
    if {[string bytelength $summary]>65536 || [lsort [dict keys $summary]] ne {actual_point_count excluded limitations original_names pair_stamp resource_count structural_counts supported_counts unit_policy visible_point_budget}} {error {Invalid bounded canonical PCB summary}}
    set text "Canonical Document: [dict get $record document_id]\nGeneration: [dict get $record generation]\nRevision: [dict get $record revision]\nSHA256: [dict get $record sha256]\n"
    dict for {key value} $summary {append text "$key: $value\n"}
    if {[string bytelength $text]>65536} {error {Canonical PCB inspector page exceeds64KiB}}
    return $text
}
proc ::GX::_viewerGuiPCBSelect {window form document} {
    set i [dict get $::GX::ViewerGui::instances $window]
    set record [_pcbPairDocumentRead $document [dict create module_id [dict get $i module] provider_id [dict get $i provider]]]
    set text [_viewerGuiPCBSummary $record]
    set domain [viewerGuiDesignContextGet $window]
    dict set domain pcb_source_bindings $form [dict create document_id $document stamp [dict get $record stamp]]
    viewerGuiDesignContextSet $window $domain
    _viewerGuiPCBDisplay $window $form COMMITTED $text
    return $record
}
proc ::GX::_viewerGuiPCBRefresh {window form} {
    set i [dict get $::GX::ViewerGui::instances $window]
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    set rows [_pcbPairDocumentList [dict get $i module] [dict get $i provider]]
    if {[llength $rows]>128} {error {PCB source choice exceeds128 completed Documents}}
    set choices {};set records {}
    foreach row $rows {
        set id [dict get $row document_id]
        if {![interactiveDocumentIdValid $id] || [dict exists $records $id]} {error {Invalid or duplicate completed PCB source choice}}
        dict set records $id $row;lappend choices $id
    }
    set selected [dict get [viewerGuiDesignValues $window] [dict get $p pcb_sources]]
    viewerGuiDesignChoicesSet $window [dict get $p pcb_sources] $choices
    if {$selected ni $choices} {set selected {}}
    viewerGuiDesignValueSet $window [dict get $p pcb_sources] $selected
    dict set ::GX::ViewerGui::instances $window pcb_source_choices $form $records
    return [dict create status refreshed count [llength $choices] message {Completed canonical snapshots only; no import was started.}]
}
proc ::GX::_viewerGuiPCBComplete {window form epoch receipt} {
    if {![_viewerGuiPCBSame $window $form $epoch]} {
        set state STALE
        if {[dict get $receipt canonical_state] eq {COMMITTED}} {set state COMMITTED_DISPLAY_UNAVAILABLE}
        return [dict create state $state canonical_state [dict get $receipt canonical_state]]
    }
    set r [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
    set status [dict get $receipt state]
    if {![_viewerGuiPCBStateValid $status]} {error {Invalid PCB parent completion status}}
    set canDisplay [_viewerGuiPCBCapturedHost $window $form $r]
    set current 0
    if {![dict get $r cancelled] && $canDisplay && ![catch {_viewerGuiPCBAuthority $window $form $epoch} observed] && $observed eq [dict get $r authority]} {set current 1}
    dict set r state $status
    dict set r result [dict create state $status canonical_state [dict get $receipt canonical_state]]
    dict set r detail [datasetPublicationV2DictDefault $receipt detail $status]
    if {[dict get $receipt canonical_state] eq {COMMITTED}} {
        if {!$current} {
            dict set r state COMMITTED_DISPLAY_UNAVAILABLE
            dict set r detail {Canonical source committed; the captured form changed before display.}
        } elseif {[catch {
            set record [dict get $receipt document]
            _viewerGuiPCBRefresh $window $form
            set p [dict get [viewerGuiDesignComponent $window $form] properties]
            viewerGuiDesignValueSet $window [dict get $p pcb_sources] [dict get $record document_id]
            set record [_viewerGuiPCBSelect $window $form [dict get $record document_id]]
            dict set r detail [_viewerGuiPCBSummary $record]
        } message]} {
            dict set r state COMMITTED_DISPLAY_UNAVAILABLE
            dict set r detail "Canonical source committed; display unavailable: $message"
        }
    }
    dict set r result state [dict get $r state]
    dict set ::GX::ViewerGui::instances $window pcb_source_forms $form $r
    if {$canDisplay && [dict get $r state] ne {COMMITTED}} {catch {_viewerGuiPCBDisplay $window $form [dict get $r state] [dict get $r detail]}}
    catch {viewerGuiActionsRefresh $window}
    return [dict create state [dict get $r state] canonical_state [dict get $receipt canonical_state]]
}
proc ::GX::_viewerGuiPCBCancel {window form {dispose 0}} {
    if {![dict exists $::GX::ViewerGui::instances $window pcb_source_forms $form]} {return {status idle}}
    set r [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
    dict set r cancelled 1
    if {[dict get $r state] ni {CANCELLED FAILED STALE OUTCOME_UNKNOWN COMMITTED COMMITTED_DISPLAY_UNAVAILABLE}} {dict set r state CANCELLING}
    set packet [dict get $r parent]
    if {$dispose} {
        # Restore can reuse the same widgets and incarnations. Revoke this
        # presentation epoch before cleanup, whose callback owns its packet.
        dict unset ::GX::ViewerGui::instances $window pcb_source_forms $form
        _pcbPairImportDispose $packet
    } else {
        # Ordinary Cancel retains captured inspection until actual EOF.
        dict set ::GX::ViewerGui::instances $window pcb_source_forms $form $r
        _pcbPairImportCancel $packet
    }
    return [dict create status [dict get $r state] epoch [dict get $r epoch]]
}
proc ::GX::_viewerGuiPCBDispose {window} {
    if {![dict exists $::GX::ViewerGui::instances $window pcb_source_forms]} return
    foreach form [dict keys [dict get $::GX::ViewerGui::instances $window pcb_source_forms]] {catch {_viewerGuiPCBCancel $window $form 1}}
}
proc ::GX::_viewerGuiPCBComponentReplacing {window component} {
    dict for {form r} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] pcb_source_forms {}] {
        if {[dict exists [dict get $r authority] component_xids $component]} {catch {_viewerGuiPCBCancel $window $form 1}}
    }
    catch {dict unset ::GX::ViewerGui::instances $window pcb_component_incarnations $component}
}
proc ::GX::_viewerGuiPCBOwnedStop {window action} {
    set match [_viewerGuiPCBAction $window $action]
    if {$match eq {}} {return 0}
    lassign $match form operation
    if {$operation ni {cancel inspect} || ![dict exists $::GX::ViewerGui::instances $window pcb_source_forms $form]} {return 0}
    set r [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
    if {![_viewerGuiPCBCapturedHost $window $form $r] || ![dict exists $::GX::ViewerCommands::windows $window handlers $action command]} {return 0}
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    if {[dict get $adapter guard] ne {} || [dict get $adapter session_token] ne [dict get $r authority token] || [dict get $adapter handlers $action command] ne [list ::GX::viewerGuiDesignAction $window $action]} {return 0}
    if {$operation eq {cancel}} {return [expr {[dict get $r state] in {CHOOSING QUEUED RUNNING WORKER_RUNNING PREPARING STREAMING VALIDATING COMMITTING CANCELLING}}]}
    return 1
}
proc ::GX::_viewerGuiPCBActionEnabled {window action} {
    set match [_viewerGuiPCBAction $window $action]
    if {$match eq {}} {return {}}
    lassign $match form operation
    if {$operation eq {cancel}} {return [_viewerGuiPCBOwnedStop $window $action]}
    if {$operation eq {inspect} && [_viewerGuiPCBOwnedStop $window $action]} {return 1}
    if {[catch {_viewerGuiPCBAuthority $window $form {}}]} {return 0}
    if {$operation eq {import_pair} && [_viewerGuiPCBBusy $window]} {return 0}
    return 1
}
proc ::GX::_viewerGuiPCBBusy {window} {
    dict for {form r} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] pcb_source_forms {}] {
        if {[dict get $r state] in {CHOOSING QUEUED RUNNING WORKER_RUNNING PREPARING STREAMING VALIDATING COMMITTING CANCELLING}} {return 1}
    }
    return 0
}
proc ::GX::_viewerGuiPCBCommand {window form operation} {
    if {$operation eq {cancel}} {
        set allowed 0
        dict for {action target} [dict get [viewerGuiDesignComponent $window $form] properties pcb_commands] {if {$target eq {cancel} && [_viewerGuiPCBOwnedStop $window $action]} {set allowed 1}}
        if {!$allowed} {error {No captured owned PCB import can be cancelled}}
        return [_viewerGuiPCBCancel $window $form]
    }
    if {$operation eq {inspect} && ([catch {_viewerGuiPCBAuthority $window $form {}}] || [_viewerGuiPCBBusy $window])} {
        dict for {action target} [dict get [viewerGuiDesignComponent $window $form] properties pcb_commands] {
            if {$target eq {inspect} && [_viewerGuiPCBOwnedStop $window $action]} {
                set r [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
                _viewerGuiPCBDisplay $window $form [dict get $r state] [datasetPublicationV2DictDefault $r detail [dict get $r state]]
                return [dict create status [dict get $r state] epoch [dict get $r epoch]]
            }
        }
    }
    if {$operation ni {import_pair refresh inspect}} {error {Unsupported PCB source form operation}}
    set epoch pcb_source_form_[incr ::GX::ViewerGui::serial]
    set authority [_viewerGuiPCBAuthority $window $form $epoch]
    if {[_viewerGuiPCBBusy $window]} {error {Finish or cancel the captured PCB import before another form operation}}
    if {$operation eq {refresh}} {return [_viewerGuiPCBRefresh $window $form]}
    if {$operation eq {inspect}} {
        set document [dict get $authority selected_document]
        if {$document eq {}} {error {Choose a completed canonical PCB source Document}}
        _viewerGuiPCBSelect $window $form $document
        return [dict create status COMMITTED document_id $document]
    }
    set r [dict create epoch $epoch authority $authority state CHOOSING cancelled 0 parent {} detail {Explicit PCB source import: choose the original board and schematic.}]
    dict set ::GX::ViewerGui::instances $window pcb_source_forms $form $r
    if {[catch {_pcbPairImportBegin $window $form $authority} packet options]} {
        if {[_viewerGuiPCBSame $window $form $epoch]} {
            set failed [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form]
            set captured [dict get $failed parent]
            set canonical [datasetPublicationV2DictDefault $captured canonical_state NONE]
            set state FAILED
            if {$canonical eq {COMMITTED} || [dict get $failed state] in {COMMITTED COMMITTED_DISPLAY_UNAVAILABLE}} {set state COMMITTED_DISPLAY_UNAVAILABLE
            } elseif {$canonical in {COMMITTING OUTCOME_UNKNOWN} || [dict get $failed state] in {COMMITTING OUTCOME_UNKNOWN}} {set state OUTCOME_UNKNOWN}
            dict set failed cancelled 1;dict set failed state $state;dict set failed detail $packet
            dict set ::GX::ViewerGui::instances $window pcb_source_forms $form $failed
            catch {_pcbPairImportDispose $captured}
        }
        return -options $options $packet
    }
    if {![_viewerGuiPCBSame $window $form $epoch] || [dict get $::GX::ViewerGui::instances $window pcb_source_forms $form cancelled]} {
        _pcbPairImportDispose $packet
        return [dict create status CANCELLING epoch $epoch]
    }
    if {[dict get $packet epoch] ne $epoch || ![_viewerGuiPCBStateValid [dict get $packet state]]} {catch {_pcbPairImportDispose $packet};error {PCB parent returned a different operation identity}}
    dict set ::GX::ViewerGui::instances $window pcb_source_forms $form parent $packet
    dict set ::GX::ViewerGui::instances $window pcb_source_forms $form state [dict get $packet state]
    return [dict create status [dict get $packet state] epoch $epoch]
}
