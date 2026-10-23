# SPDX-License-Identifier: GPL-3.0-or-later
# Finite declared actions; Dataset Transform/Numeric/Publication/Plot own science.
# Only ephemeral operation state belongs to the existing Viewer instance.
proc ::GX::_viewerGuiTransformDesignValidate {design} {
    set definitions {};set commands {};set controls {};set plots {}
    foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties];set present 0
        foreach key [dict keys $p] {if {[string match transform_* $key]} {set present 1}}
        if {!$present} continue
        set required {transform_kind transform_dataset transform_x transform_y transform_method transform_grid_policy transform_nonfinite transform_output transform_baseline transform_corrected transform_row transform_options transform_commands transform_status transform_report transform_plot}
        foreach key $required {if {![dict exists $p $key]} {error "Incomplete Transform form: $key"}}
        if {[dict get $c type] ne {section} || [dict get $p transform_kind] ne {baseline_correct}} {error {Only a declared baseline_correct section is supported}}
        foreach api {VIEWER_GUI_HOST_API_v1 DATASET_TRANSFORM_API_v1 PLOT_DATASET_API_v4} version {1 1 4} {
            if {![dict exists $design requirements $api] || [dict get $design requirements $api]!=$version} {error "Transform form requires $api@$version"}
        }
        foreach {key types} {transform_dataset dataset_selector transform_x {choice combobox} transform_y {choice combobox} transform_method {choice combobox} transform_grid_policy {choice combobox} transform_nonfinite {choice combobox} transform_output {field entry} transform_baseline {field entry} transform_corrected {field entry} transform_row {field entry} transform_status {label status} transform_report log transform_plot plot} {
            set id [dict get $p $key]
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni $types || [dict exists $definitions $id properties change_action]} {error "Invalid inert Transform control $key"}
            if {$key eq {transform_plot}} {
                if {$id in $plots || [dict exists $definitions $id properties plot_form]} {error {Transform requires its own declared Plot without a second form binding}}
                lappend plots $id
            } else {
                if {$id in $controls} {error {Transform controls must be distinct across all forms}}
                lappend controls $id
            }
            if {$key in {transform_output transform_baseline transform_corrected transform_row} && [dict get $definitions $id type] eq {field} && [datasetPublicationV2DictDefault [dict get $definitions $id properties] datatype string] ne {string}} {error {Transform output IDs require string fields}}
        }
        foreach {key choices} {transform_method {asls constant linear polynomial} transform_grid_policy {uniform_x sample_index} transform_nonfinite {error omit}} {
            if {[dict get $definitions [dict get $p $key] properties choices] ne $choices} {error "Transform $key requires the exact finite choices $choices"}
        }
        if {[lsort [dict keys [dict get $p transform_options]]] ne {degree lambda max_iterations p tolerance value}} {error {Baseline options require the finite declared scalar controls}}
        dict for {key id} [dict get $p transform_options] {
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ne {field} || [dict exists $definitions $id properties change_action] || [datasetPublicationV2DictDefault [dict get $definitions $id properties] datatype string] ni {number integer} || $id in $controls} {error "Invalid distinct typed baseline option $key"}
            if {$key in {degree max_iterations} && [dict get $definitions $id properties datatype] ne {integer}} {error "Baseline $key requires an integer field"}
            lappend controls $id
        }
        set operations {}
        dict for {action operation} [dict get $p transform_commands] {
            if {$operation ni {discover create_corrected cancel inspect} || $operation in $operations || $action in $commands || $action in {undo redo fit zoom_in zoom_out gui_inspect} || ![dict exists $design handlers $action]} {error {Transform commands require unique finite declared handlers}}
            set effect [expr {$operation eq {create_corrected} ? {mutating} : {presentation}}]
            if {[dict get $design handlers $action effect] ne $effect} {error "Transform $operation requires effect $effect"}
            if {[datasetPublicationV2DictDefault $design initial_action {}] eq $action} {error {Transform actions require explicit user invocation}}
            lappend commands $action;lappend operations $operation
        }
        if {[lsort $operations] ne {cancel create_corrected discover inspect}} {error {Declare all four Transform operations including owned Cancel and inspect}}
    }
    if {$commands eq {}} return
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        foreach key {change_action scientific_netlist_action} {
            if {[datasetPublicationV2DictDefault $p $key {}] in $commands} {error {Transform actions cannot be source-change or netlist callbacks}}
        }
        foreach key {plot_series_commands visibility_commands} {
            dict for {action target} [datasetPublicationV2DictDefault $p $key {}] {if {$action in $commands} {error {Transform action conflicts with another declared owner}}}
        }
        foreach key {em_actions catalog_actions} {
            dict for {operation action} [datasetPublicationV2DictDefault $p $key {}] {if {$action in $commands} {error {Transform action conflicts with another form owner}}}
        }
        if {[dict exists $p action] && [dict get $p action] in $commands} {
            foreach key {diagram_tool raster_tool raster_command component_visibility} {if {[dict exists $p $key]} {error {Transform actions cannot be scientific tools or visibility controls}}}
        }
    }
}
proc ::GX::_viewerGuiTransformAction {window action} {
    if {![dict exists $::GX::ViewerGui::instances $window]} {return {}}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {[dict exists $c properties transform_commands $action]} {return [list [dict get $c id] [dict get $c properties transform_commands $action]]}
    }
    return {}
}
proc ::GX::_viewerGuiTransformInputs {window form} {
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    set values [viewerGuiDesignValues $window];set input {}
    foreach key {transform_dataset transform_x transform_y transform_method transform_grid_policy transform_nonfinite transform_output transform_baseline transform_corrected transform_row} {dict set input $key [dict get $values [dict get $p $key]]}
    set options {};dict for {key id} [dict get $p transform_options] {dict set options $key [dict get $values $id]}
    dict set input transform_options $options
    return $input
}
proc ::GX::_viewerGuiTransformProjectStamp {project} {
    set stamp {}
    foreach name {handlers.cpp design.gxtxt-viewer project.json} {
        file lstat [file join $project $name] s
        if {$s(type) ne {file} || $s(nlink)!=1 || $s(size)>4194304} {error {Transform project is no longer an ordinary bounded source}}
        dict set stamp $name [list $s(dev) $s(ino) $s(size) $s(mtime) $s(ctime)]
    }
    return $stamp
}
proc ::GX::_viewerGuiTransformAuthority {window form} {
    if {![viewerGuiDesignGuard $window] || ![dict exists $::GX::ViewerDevelopment::windows $window transform_form_admission]} {error {Transform requires the currently admitted Development/installed Viewer}}
    set host [dict get $::GX::ViewerDevelopment::windows $window]
    set proof [dict get $host transform_form_admission]
    if {[dict get $proof schema] ne {gxtxt.viewer_transform_admission.v1} || [dict get $proof profile] ne {scientific_view_v1} || $form ni [dict get $proof forms] || [dict get $host busy] ne {} || [dict get $host status] in {RUNNING VALIDATING REJECTED FAILED SOURCE_CHANGED}} {error {Transform form is not currently admitted or the compiled event is busy}}
    foreach {api operations} {VIEWER_GUI_HOST_API_v1 transform_form DATASET_TRANSFORM_API_v1 {execute_responsive cancel provenance} PLOT_DATASET_API_v4 widgetCreate} {
        foreach operation $operations {if {$operation ni [dict get $proof grants $api]} {error {Missing admitted Transform grant}}}
    }
    set snapshot [_viewerDevelopmentSnapshot [dict get $host project]]
    if {$snapshot ne [dict get $host validated_snapshot]} {error {Transform project changed; reopen its matching source}}
    foreach key {source_sha256 design_sha256 project_sha256} {if {[dict get $proof $key] ne [dict get $snapshot $key]} {error {Transform admission differs from source/design/profile snapshot}}}
    set i [dict get $::GX::ViewerGui::instances $window]
    set domain [viewerGuiDesignContextGet $window]
    if {![dict exists $domain restricted_cpp snapshot] || [dict get $domain restricted_cpp snapshot] ne $snapshot} {error {Transform Viewer context differs from its admitted source}}
    set design [dict get $i design]
    if {$design ne [viewerGuiDesignRead [file join [dict get $host project] design.gxtxt-viewer]]} {error {Transform live design differs from its admitted design}}
    if {[dict get $i mode] ne {runtime} || [dict get $i token] eq {} || [dict get $i token] ne [interactiveDocumentSessionToken]} {error {Transform requires a current nonempty Session lifetime}}
    return [dict create form $form project [dict get $host project] snapshot $snapshot proof $proof project_stamp [_viewerGuiTransformProjectStamp [dict get $host project]] xid [winfo id $window] opened_us [dict get $i opened_us] design $design token [dict get $i token] session [file normalize $::GX::currentSession] workspace_id [dict get $i workspace_id] workspace_stamp [dict get $i workspace_stamp]]
}
proc ::GX::_viewerGuiTransformSource {session input} {
    set id [dict get $input transform_dataset]
    set source [sessionInspectionDatasetLocation $id $session]
    set schema [datasetVariableSchemaV3 $id]
    if {[llength $schema]>4096} {error {Baseline form supports at most4096 original Variables}}
    set x [dict get $input transform_x];set y [dict get $input transform_y]
    if {$x eq $y} {error {Select distinct enabled floating X/Y Variables}}
    foreach vid [list $x $y] {
        set v [datasetVariableV3ById $id $vid]
        if {![dict get $v enabled] || [dict get $v rank]!=1 || [dict get $v dtype] ni {float32 float64} || [dict get $v value_kind] ne {number} || [dict get $v unit] eq {}} {error {Baseline axes require enabled rank-one float32/float64 numeric Variables with explicit units}}
        foreach key {canonical_unit to_canonical from_canonical} {if {[dict get $v $key] ne {}} {error {Baseline form does not reinterpret custom coordinate unit formulas; materialize an explicit supported unit transform first}}}
    }
    set rows [datasetField $id row_count {}]
    if {![string is entier -strict $rows] || $rows<1 || $rows>2000000 || ([dict get $input transform_method] eq {asls} && $rows<3)} {error {Baseline requires1..2000000 original rows; AsLS requires at least3}}
    # The public revision token includes persisted registry/schema identity and
    # the metadata SHA, including coordinate bindings. Do not re-hash the full
    # canonical payload here; Transform captures/verifies its coordinate context.
    return [dict create dataset_id $id declared_sha256 [dict get $source expected_sha256] revision [datasetRevisionToken $id $session] schema $schema rows $rows]
}
proc ::GX::_viewerGuiTransformManifest {input source} {
    set dataset [dict get $input transform_output]
    if {$dataset eq {} || [string length $dataset]>128 || $dataset eq [dict get $source dataset_id]} {error {Declare an explicit fresh output Dataset ID of at most128 characters}}
    if {[datasetPublicationV2ValidateId dataset $dataset] ne $dataset} {error {Output Dataset ID must not contain surrounding whitespace}}
    set new {};set old [lmap v [dict get $source schema] {dict get $v variable_id}]
    foreach key {transform_baseline transform_corrected transform_row} {
        set id [dict get $input $key]
        if {[datasetPublicationV2ValidateId variable $id] ne $id} {error {Output Variable IDs must not contain surrounding whitespace}}
        if {$id eq {} || [string length $id]>128 || $id in $new || $id in $old} {error {Declare three distinct new output Variable IDs of at most128 characters}}
        lappend new $id
    }
    set method [dict get $input transform_method]
    if {$method ni {asls constant linear polynomial} || [dict get $input transform_grid_policy] ni {uniform_x sample_index} || [dict get $input transform_nonfinite] ni {error omit}} {error {Unsupported finite baseline method/options}}
    set options [dict create method $method nonfinite [dict get $input transform_nonfinite]]
    set keys [dict get {asls {lambda p max_iterations tolerance} constant value linear {} polynomial degree} $method]
    foreach key $keys {
        set v [dict get $input transform_options $key]
        if {$key in {degree max_iterations}} {set v [uiFieldNormalize {type integer} $v]} else {set v [uiFieldNormalize {type number} $v]}
        dict set options $key $v
    }
    if {$method eq {asls}} {dict set options grid_policy [dict get $input transform_grid_policy]}
    return [dict create api_version 1 operation baseline_correct sources [list [dict create dataset_id [dict get $source dataset_id]]] output [dict create dataset_id $dataset storage auto contract auto] options [dict create x_variable_id [dict get $input transform_x] y_variable_id [dict get $input transform_y] baseline_options $options baseline_variable_id [lindex $new 0] corrected_variable_id [lindex $new 1] row_variable_id [lindex $new 2]] schema_policy {dtype_policy strict unit_policy explicit} metadata_policy inherit_single_source]
}
proc ::GX::_viewerGuiTransformSame {window form epoch} {
    return [expr {[dict exists $::GX::ViewerGui::instances $window transform_forms $form epoch] && [dict get $::GX::ViewerGui::instances $window transform_forms $form epoch] eq $epoch}]
}
proc ::GX::_viewerGuiTransformBusy {window} {
    dict for {form r} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] transform_forms {}] {if {[dict get $r state] in {QUEUED RUNNING CANCELLING}} {return 1}}
    return 0
}
proc ::GX::_viewerGuiTransformCurrent {window form r} {
    set a [dict get $r authority]
    if {![_viewerGuiTransformSame $window $form [dict get $r epoch]] || [dict get $r epoch] ne [dict get $r captured_epoch] || [dict get $a form] ne $form || ![winfo exists $window] || ![viewerGuiDesignGuard $window]} {return 0}
    set i [dict get $::GX::ViewerGui::instances $window]
    if {[winfo id $window] ne [dict get $a xid] || [dict get $i opened_us] ne [dict get $a opened_us] || [interactiveDocumentSessionToken] ne [dict get $a token] || [file normalize $::GX::currentSession] ne [dict get $a session] || [dict get $i design] ne [dict get $a design] || [dict get $i workspace_id] ne [dict get $a workspace_id] || [dict get $i workspace_stamp] ne [dict get $a workspace_stamp] || [_viewerGuiTransformInputs $window $form] ne [dict get $r input]} {return 0}
    if {![dict exists $::GX::ViewerDevelopment::windows $window]} {return 0}
    set host [dict get $::GX::ViewerDevelopment::windows $window]
    if {[dict get $host project] ne [dict get $a project] || [dict get $host validated_snapshot] ne [dict get $a snapshot] || ![dict exists $host transform_form_admission] || [dict get $host transform_form_admission] ne [dict get $a proof] || [_viewerGuiTransformProjectStamp [dict get $a project]] ne [dict get $a project_stamp]} {return 0}
    # Canonical payload hashes/precommit validation stay in Transform's owner.
    # Public revision/schema/context checks happen at queue/start, not50ms pulses.
    return 1
}
proc ::GX::_viewerGuiTransformDisplay {window form r} {
    if {![_viewerGuiTransformSame $window $form [dict get $r epoch]] || ![winfo exists $window]} return
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    viewerGuiDesignTextSet $window [dict get $p transform_status] [dict get $r state]
    viewerGuiDesignTextSet $window [dict get $p transform_report] [string range [datasetPublicationV2DictDefault $r detail {}] 0 32767]
}
proc ::GX::_viewerGuiTransformControls {window form enabled} {
    if {![dict exists $::GX::ViewerGui::instances $window] || ![winfo exists $window]} return
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    set ids [dict values [dict get $p transform_options]]
    foreach key {transform_dataset transform_x transform_y transform_method transform_grid_policy transform_nonfinite transform_output transform_baseline transform_corrected transform_row} {lappend ids [dict get $p $key]}
    foreach id $ids {uiFieldComponentEnabled [dict get $::GX::ViewerGui::instances $window widgets $id] [dict get [viewerGuiDesignComponent $window $id] type] $enabled}
}
proc ::GX::_viewerGuiTransformCancel {window form} {
    if {![dict exists $::GX::ViewerGui::instances $window transform_forms $form]} {return {status idle}}
    set r [dict get $::GX::ViewerGui::instances $window transform_forms $form]
    if {[dict get $r state] ni {QUEUED RUNNING CANCELLING}} {return [dict create status [dict get $r state]]}
    dict set r cancelled 1
    if {[dict get $r state] eq {QUEUED}} {
        if {[dict get $r after] ne {}} {after cancel [dict get $r after]}
        dict set r state CANCELLED
        dict set r detail {Queued correction cancelled; Transform was not started.}
        _viewerGuiTransformControls $window $form 1
    } else {
        dict set r state CANCELLING
        if {[dict get $r execution] ne {}} {catch {datasetTransformCancel [dict get $r execution]}}
        dict set r detail {Cancellation requested for this captured execution before canonical commit.}
    }
    dict set ::GX::ViewerGui::instances $window transform_forms $form $r
    catch {_viewerGuiTransformDisplay $window $form $r}
    catch {viewerGuiActionsRefresh $window}
    return [dict create status [dict get $r state] epoch [dict get $r epoch]]
}
proc ::GX::_viewerGuiTransformCancelled {window form epoch} {
    if {![_viewerGuiTransformSame $window $form $epoch]} {return 1}
    set r [dict get $::GX::ViewerGui::instances $window transform_forms $form]
    if {[dict get $r cancelled]} {return 1}
    if {[catch {_viewerGuiTransformCurrent $window $form $r} current] || !$current} {
        _viewerGuiTransformCancel $window $form
        return 1
    }
    # The final precommit boundary yields AFTER its progress callback. Its
    # post-yield cancellation check must re-hash the captured project admission;
    # second-resolution lstat stamps alone can miss a same-size in-place edit.
    # This phase is never enabled by ordinary50ms planning progress pulses.
    if {[dict get $r precommit_phase] && ([catch {_viewerGuiTransformAuthority $window $form} authority] || $authority ne [dict get $r authority])} {
        _viewerGuiTransformCancel $window $form
        return 1
    }
    return 0
}
proc ::GX::_viewerGuiTransformProgress {window form epoch event} {
    if {![_viewerGuiTransformSame $window $form $epoch]} return
    set r [dict get $::GX::ViewerGui::instances $window transform_forms $form]
    set job [dict get $event job_id]
    if {[dict get $r execution] ne {} && [dict get $r execution] ne $job} {error {Transform execution identity changed}}
    dict set r execution $job
    if {[dict get $event stage] eq {precommit}} {dict set r precommit_phase 1}
    dict set ::GX::ViewerGui::instances $window transform_forms $form $r
    if {[_viewerGuiTransformCancelled $window $form $epoch]} return
    dict set r detail "[dict get $event stage]: [dict get $event current] / [dict get $event total]\nCanonical commit has not occurred."
    dict set ::GX::ViewerGui::instances $window transform_forms $form $r
    _viewerGuiTransformDisplay $window $form $r
}
proc ::GX::_viewerGuiTransformOverlay {window form r receipt} {
    set input [dict get $r input];set output [dict get $input transform_output]
    set schema [datasetVariableSchemaV3 $output]
    set byid {};foreach v $schema {dict set byid [dict get $v variable_id] $v}
    set y [dict get $input transform_y];set unit [dict get $byid $y unit]
    foreach key {transform_baseline transform_corrected} {set v [dict get $byid [dict get $input $key]];if {[dict get $v dtype] ne {float64} || [dict get $v unit] ne $unit} {error {Committed baseline output schema/units differ from the requested contract}}}
    if {[dict get $byid [dict get $input transform_row] dtype] ne {uint64} || [dict get $receipt row_identity] ne {original_dataset_zero_based_uint64}} {error {Committed row identity differs from exact zero-based uint64 contract}}
    set expected [list {*}[lmap v [dict get $r source schema] {dict get $v variable_id}] [dict get $input transform_baseline] [dict get $input transform_corrected] [dict get $input transform_row]]
    if {[dict keys $byid] ne $expected || [datasetField $output row_count {}] ne [dict get $r source rows]} {error {Committed original columns/row count differ from the full source}}
    foreach original [dict get $r source schema] {
        set actual [dict get $byid [dict get $original variable_id]]
        foreach key {dtype rank shape unit} {if {[dict get $actual $key] ne [dict get $original $key]} {error {Committed original column type/shape/unit differs from the source}}}
    }
    if {[dict get $receipt original_n] ne [dict get $r source rows] || [dict get $receipt uncertainty_policy] ne {baseline_treated_as_fixed_no_baseline_estimation_uncertainty}} {error {Committed baseline row/uncertainty receipt differs from the supported contract}}
    foreach {key field} {transform_dataset source_dataset_id transform_x x_variable_id transform_y original_y_variable_id transform_baseline baseline_variable_id transform_corrected corrected_variable_id transform_row row_variable_id transform_method method} {if {[dict get $receipt $field] ne [dict get $input $key]} {error {Committed baseline receipt differs from the explicit source/output selection}}}
    if {[dict get $receipt source_sha256] ne [dict get $r source declared_sha256]} {error {Committed source hash differs from the captured canonical identity}}
    set samples {};set rowid [dict get $input transform_row]
    foreach index [lsort -integer -unique [list 0 [expr {[dict get $r source rows]-1}]]] {
        set stream [tableStreamOpenDataset [dict get $r authority session] $output [list $rowid] 1 [dict create start $index count 1 numeric_transport values]]
        try {set chunk [tableStreamNext $stream]} finally {tableStreamClose $stream}
        set ordinal [lindex [dict get $chunk values $rowid] 0]
        if {[dict get $chunk nrows]!=1 || ![string is entier -strict $ordinal] || $ordinal!=$index} {error {Committed canonical source-row boundary differs from exact original uint64 ordinal}}
        lappend samples [dict create output_row $index source_row $ordinal]
    }
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set spec [::GX::PlotDatasetAPIv4::newSpec -title {Raw, estimated baseline and corrected response}]
    set panel [lindex [dict get $spec panels] 0];set series {}
    foreach key {transform_y transform_baseline transform_corrected} label {{Original response} {Estimated baseline (uncertainty unpropagated)} {Corrected response}} {
        lappend series [dict create id $key kind line dataset_id $output x_variable_id [dict get $input transform_x] y_variable_id [dict get $input $key] axis left label $label]
    }
    dict set panel series $series;dict set spec panels [list $panel]
    set target [dict get [viewerGuiDesignComponent $window $form] properties transform_plot]
    if {![_viewerGuiTransformCurrent $window $form $r]} {error {Output committed; original Viewer/source changed before Plot application}}
    return [dict create plot [viewerGuiDesignPlotSet $window $target $spec] source_row_boundary_samples $samples sample_scope {first/last canonical row only; full row identity remains the Transform contract}]
}
proc ::GX::_viewerGuiTransformRun {window form epoch} {
    if {![_viewerGuiTransformSame $window $form $epoch]} return
    set r [dict get $::GX::ViewerGui::instances $window transform_forms $form]
    if {[dict get $r state] ne {QUEUED} || [dict get $r cancelled]} return
    set committed 0
    try {
        if {![_viewerGuiTransformCurrent $window $form $r]} {error {Transform host/source selection changed before start}}
        if {[_viewerGuiTransformAuthority $window $form] ne [dict get $r authority]} {error {Transform admission changed before start}}
        set session [dict get $r authority session]
        if {[_viewerGuiTransformSource $session [dict get $r input]] ne [dict get $r source]} {error {Canonical source revision/schema/context changed before start}}
        # This first slice operates on original canonical coordinates. Resolve
        # context only through its public owner, after the explicit deferred
        # start; never transfer display calibration into a baseline estimate.
        set coordinates [datasetCoordinateRead $session [dict get $r source dataset_id]]
        foreach key {transform_x transform_y} {
            set settings [dict get $coordinates variables [dict get $r input $key]]
            if {[dict get $settings view_factor]!=1 || [dict get $settings view_pivot]!=0 || [dict get $settings calibration_factor]!=1 || [dict get $settings input_origin]!=0 || [dict get $settings output_origin]!=0 || [dict get $settings display_unit] ne [dict get $settings source unit]} {error {Baseline form requires original coordinate units and identity display/calibration settings; use an explicit supported transform first}}
        }
        dict set r coordinate_context $coordinates
        dict set r state RUNNING;dict set r after {}
        dict set ::GX::ViewerGui::instances $window transform_forms $form $r
        set result [datasetTransformExecuteResponsive $session [dict get $r manifest] [dict create progress_command [list ::GX::_viewerGuiTransformProgress $window $form $epoch] cancel_command [list ::GX::_viewerGuiTransformCancelled $window $form $epoch]]]
        # Successful return means canonical commit already happened. Never turn
        # later UI/provenance/Plot failure into cancellation or claimed rollback.
        set committed 1;dict set r result $result;dict set r state COMMITTED
        set provenance [datasetTransformProvenance $session [dict get $r input transform_output]]
        dict set r provenance $provenance
        set receipt [dict get $provenance effective baseline_receipt]
        dict set r baseline_receipt $receipt
        dict set r detail "Committed Dataset: [dict get $r input transform_output]\n$receipt\nBaseline estimation uncertainty is not propagated."
        if {![_viewerGuiTransformCurrent $window $form $r]} {error {Output committed; original Viewer/source lifetime changed, so no Plot was applied}}
        dict set r plot_receipt [_viewerGuiTransformOverlay $window $form $r $receipt]
    } on error {message options} {
        if {$committed} {dict set r state COMMITTED_DISPLAY_FAILED} elseif {[datasetPublicationV2DictDefault $options -errorcode {}] eq {GX DATASET_TRANSFORM CANCELLED}} {dict set r state CANCELLED} else {dict set r state FAILED}
        dict set r detail "[dict get $r state]: $message"
        dict set r error_options $options
    }
    if {[_viewerGuiTransformSame $window $form $epoch]} {
        dict set ::GX::ViewerGui::instances $window transform_forms $form $r
        catch {_viewerGuiTransformControls $window $form 1}
        catch {_viewerGuiTransformDisplay $window $form $r}
        catch {viewerGuiActionsRefresh $window}
    }
    # Closed-window diagnostics retain the genuine commit identity. Durable
    # scientific truth remains the canonical Dataset/provenance, not this form.
    if {$committed} {puts [list GXTXT_VIEWER_TRANSFORM_COMMITTED [dict create dataset_id [dict get $r input transform_output] session [dict get $r authority session] status [dict get $r state] result [dict get $r result] baseline_receipt [datasetPublicationV2DictDefault $r baseline_receipt {}] detail [string range [dict get $r detail] 0 32767]]]}
}
proc ::GX::_viewerGuiTransformActionEnabled {window action} {
    set match [_viewerGuiTransformAction $window $action]
    if {$match eq {}} {return {}}
    lassign $match form operation
    if {$operation in {cancel inspect}} {return [_viewerGuiTransformOwnedStopEnabled $window $action]}
    return [expr {![_viewerGuiTransformBusy $window] && [viewerGuiDesignGuard $window] && [dict exists $::GX::ViewerDevelopment::windows $window transform_form_admission]}]
}
proc ::GX::_viewerGuiTransformOwnedStopEnabled {window action} {
    set match [_viewerGuiTransformAction $window $action]
    if {$match eq {} || ![winfo exists $window]} {return 0}
    lassign $match form operation
    if {$operation ni {cancel inspect} || ![dict exists $::GX::ViewerGui::instances $window transform_forms $form]} {return 0}
    set i [dict get $::GX::ViewerGui::instances $window]
    set r [dict get $i transform_forms $form];set a [dict get $r authority]
    if {![dict exists $::GX::ViewerCommands::windows $window handlers $action command]} {return 0}
    set adapter [dict get $::GX::ViewerCommands::windows $window]
    if {[dict get $adapter guard] ne {} || [dict get $adapter session_token] ne [dict get $a token] || [dict get $adapter handlers $action command] ne [list ::GX::viewerGuiDesignAction $window $action]} {return 0}
    if {[dict get $r epoch] eq {} || [dict get $r epoch] ne [dict get $r captured_epoch] || [dict get $a form] ne $form || [winfo id $window] ne [dict get $a xid] || [dict get $i opened_us] ne [dict get $a opened_us] || [dict get $i design] ne [dict get $a design] || [dict get $i token] ne [dict get $a token] || $form ni [dict get $a proof forms]} {return 0}
    if {$operation eq {cancel}} {return [expr {[dict get $r state] in {QUEUED RUNNING CANCELLING}}]}
    return [expr {[dict get $r state] in {QUEUED RUNNING CANCELLING CANCELLED FAILED COMMITTED COMMITTED_DISPLAY_FAILED}}]
}
proc ::GX::viewerGuiDesignTransform {window form operation} {
    if {$operation in {cancel inspect}} {
        set owned 0
        if {[dict exists $::GX::ViewerGui::instances $window]} {
            set p [dict get [viewerGuiDesignComponent $window $form] properties]
            dict for {action target} [datasetPublicationV2DictDefault $p transform_commands {}] {if {$target eq $operation && [_viewerGuiTransformOwnedStopEnabled $window $action]} {set owned 1}}
        }
        if {!$owned} {error {No captured owned Transform operation is available for this command}}
    }
    if {$operation eq {cancel}} {return [_viewerGuiTransformCancel $window $form]}
    if {$operation eq {inspect}} {
        if {![dict exists $::GX::ViewerGui::instances $window transform_forms $form]} {return {status idle}}
        set r [dict get $::GX::ViewerGui::instances $window transform_forms $form]
        _viewerGuiTransformDisplay $window $form $r
        return [dict create status [dict get $r state] epoch [dict get $r epoch] detail [datasetPublicationV2DictDefault $r detail {}] result [datasetPublicationV2DictDefault $r result {}] baseline_receipt [datasetPublicationV2DictDefault $r baseline_receipt {}]]
    }
    if {$operation ni {discover create_corrected}} {error {Unsupported declared Transform action}}
    set a [_viewerGuiTransformAuthority $window $form]
    set p [dict get [viewerGuiDesignComponent $window $form] properties]
    if {![dict exists $p transform_kind] || [dict get $p transform_kind] ne {baseline_correct}} {error {Choose a declared baseline_correct form}}
    if {[_viewerGuiTransformBusy $window]} {error {Finish or cancel this Viewer's captured correction first}}
    set input [_viewerGuiTransformInputs $window $form]
    if {$operation eq {discover}} {
        set choices {}
        foreach v [datasetVariableSchemaV3 [dict get $input transform_dataset]] {if {[dict get $v enabled] && [dict get $v rank]==1 && [dict get $v dtype] in {float32 float64} && [dict get $v value_kind] eq {number} && [dict get $v unit] ne {}} {lappend choices [dict get $v variable_id]}}
        if {[llength $choices]<2 || [llength $choices]>4096} {error {Source needs2..4096 enabled floating scalar Variables}}
        foreach key {transform_x transform_y} {viewerGuiDesignChoicesSet $window [dict get $p $key] $choices}
        return [dict create status discovered variables $choices message {Choose explicit X/Y; no correction or publication ran.}]
    }
    set source [_viewerGuiTransformSource [dict get $a session] $input]
    set manifest [_viewerGuiTransformManifest $input $source]
    set epoch transform_form_[incr ::GX::ViewerGui::serial]
    set r [dict create epoch $epoch captured_epoch $epoch authority $a input $input source $source manifest $manifest state QUEUED execution {} cancelled 0 precommit_phase 0 after {} detail {Correction queued by explicit Create corrected Dataset; no canonical commit yet.}]
    dict set ::GX::ViewerGui::instances $window transform_forms $form $r
    try {
        _viewerGuiTransformControls $window $form 0
        _viewerGuiTransformDisplay $window $form $r
        viewerGuiActionsRefresh $window
        if {[dict get $::GX::ViewerGui::instances $window transform_forms $form state] ne {QUEUED}} {return [dict create status CANCELLED epoch $epoch]}
        dict set r after [after 0 [list ::GX::_viewerGuiTransformRun $window $form $epoch]]
        dict set ::GX::ViewerGui::instances $window transform_forms $form $r
    } on error {message options} {
        if {[dict get $r after] ne {}} {after cancel [dict get $r after]}
        dict set r state FAILED;dict set r detail $message
        dict set ::GX::ViewerGui::instances $window transform_forms $form $r
        catch {_viewerGuiTransformControls $window $form 1}
        return -options $options $message
    }
    return [dict create status QUEUED epoch $epoch]
}
proc ::GX::_viewerGuiTransformDispose {window} {
    if {![dict exists $::GX::ViewerGui::instances $window transform_forms]} return
    foreach form [dict keys [dict get $::GX::ViewerGui::instances $window transform_forms]] {catch {_viewerGuiTransformCancel $window $form}}
}
