# SPDX-License-Identifier: GPL-3.0-or-later
# First scientific consumer of the public Viewer GUI integration manifest.
namespace eval ::GX::ReplicateViewer {variable state;variable input}
::GX::modulePublicApiActivate curve.replicate_analysis CURVE_REPLICATE_ANALYSIS_API_v1
::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
proc ::GX::ReplicateViewer::guard {w} {
    variable state
    if {![winfo exists $w] || $state($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen the Replicate Viewer}}
    if {$state($w,id) ne {}} {
        set current [::GX::sessionWorkspaceGet $state($w,id)]
        if {[dict get $current generation] ne $state($w,generation) || [dict get $current revision]!=$state($w,revision)} {error {Workspace changed in another editor; reopen it}}
    }
    return 1
}
proc ::GX::ReplicateViewer::safe {w method args} {
    variable state
    if {[catch {guard $w;[namespace current]::$method $w {*}$args} message options]} {$w.footer.status configure -text $message;return 0}
    return 1
}
proc ::GX::ReplicateViewer::capture {w} {
    variable state
    if {[winfo exists $w.body.canvas.plot]} {rememberView $w}
    return [dict remove $state($w,payload) history]
}
proc ::GX::ReplicateViewer::resultValue {payload} {
    if {![dict exists $payload result_resource]} {return [dict get $payload result]}
    set reference [dict get $payload result_resource];set total [dict get $reference size_bytes]
    if {$total>33554432} {error {Saved study resource exceeds the scientific receipt bound}}
    set bytes {};for {set offset 0} {$offset<$total} {incr offset 1048576} {append bytes [::GX::interactiveDocumentResourceReadChunk $reference $offset [expr {min(1048576,$total-$offset)}]]}
    return [encoding convertfrom utf-8 $bytes]
}
proc ::GX::ReplicateViewer::storeResult {w payload result} {
    variable state
    if {[dict exists $payload result_resource]} {dict unset payload result_resource}
    if {[string bytelength $result]<=524288} {dict set payload result $result;return $payload}
    if {$state($w,id) eq {}} {error {Save this Workspace before adopting a large study. The completed Job remains available; Analyze can be repeated explicitly.}}
    set writer [::GX::interactiveDocumentResourceOpenWriter $state($w,id) {format gxtxt.replicate.scientific_result.v1 scientific_authority 1}]
    try {
        set bytes [encoding convertto utf-8 $result]
        for {set offset 0} {$offset<[string length $bytes]} {incr offset 1048576} {::GX::interactiveDocumentResourceAppend $writer [string range $bytes $offset [expr {$offset+1048575}]]}
        set reference [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
    } finally {if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
    if {[dict exists $payload result]} {dict unset payload result}
    dict set payload result_resource $reference;return $payload
}
proc ::GX::ReplicateViewer::restore {w payload} {variable state;unset -nocomplain state($w,ticket) state($w,rejectedTicket);set state($w,payload) $payload;refresh $w}
proc ::GX::ReplicateViewer::historyCommit {w record} {variable state;dict set state($w,payload) history $record}
proc ::GX::ReplicateViewer::historyValidate {record} {if {[dict get $record workbench_id] ne "viewer.replicate_curve_analysis"} {error {History belongs to another Viewer}};return 1}
proc ::GX::ReplicateViewer::historyCapture {w} {return [::GX::scientificHistoryViewerRecord $w]}
proc ::GX::ReplicateViewer::historyReplay {context record} {error {Navigate History in the owning Replicate Workspace}}
::GX::scientificRecipeHostRegister viewer.replicate_curve_analysis [dict create capture ::GX::ReplicateViewer::historyCapture validate ::GX::ReplicateViewer::historyValidate replay ::GX::ReplicateViewer::historyReplay]
proc ::GX::ReplicateViewer::change {w payload description {expectedSourcePayload {}} {expectedTicket {}}} {
    variable state
    guard $w
    set bound [expr {$expectedSourcePayload ne {} && [_hasSourceBinding [dict get $payload request]]}]
    if {$bound} {set historyBefore [_boundHistoryLatest $w];_validateRequestBindings [dict get $payload request]}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} {return 0}
    # History confirmation may run a nested event loop. Recheck before adoption.
    guard $w
    if {$expectedSourcePayload ne {} && ($state($w,busy) || [dict remove $state($w,payload) history] ne $expectedSourcePayload)} {
        error {Study changed while confirming the source edit; reopen the source editor}
    }
    if {$bound} {
        _validateRequestBindings [dict get $payload request]
        guard $w
        if {$state($w,busy) || [dict remove $state($w,payload) history] ne $expectedSourcePayload || [_boundHistoryLatest $w] ne $historyBefore} {_sourceFail SOURCE_CHANGED {Study or History changed during bound source admission}}
    }
    if {$expectedTicket ne {} && (![info exists state($w,ticket)] || $state($w,ticket) ne $expectedTicket)} {_sourceFail SOURCE_CHANGED {Managed study changed while adopting its result}}
    if {[dict get $payload request] ne [dict get $state($w,payload) request]} {
        set payload [dict remove $payload result result_resource published_dataset plot_ref view_axes]
        unset -nocomplain state($w,ticket)
    }
    set state($w,payload) $payload
    ::GX::scientificHistoryViewerChanged $w $description
    refresh $w
    return 1
}
proc ::GX::ReplicateViewer::current {w} {variable state;return $state($w,id)}
proc ::GX::ReplicateViewer::dirty {w} {variable state;return [expr {[capture $w] ne $state($w,saved)}]}
proc ::GX::ReplicateViewer::prepare {w action} {variable state;guard $w;if {$state($w,busy) && $action ne "query"} {error {Cancel or finish the current study before switching Workspace}};return 1}
proc ::GX::ReplicateViewer::discard {w} {destroy $w}
proc ::GX::ReplicateViewer::close {w} {safe $w closeWorkspace}
proc ::GX::ReplicateViewer::closeWorkspace {w} {::GX::sessionWorkspaceViewerAction replicate_consensus [callbacks $w] $w close}
proc ::GX::ReplicateViewer::callbacks {w} {return [dict create current [list [namespace current]::current $w] save [list [namespace current]::save $w] open [list [namespace current]::open] close [list [namespace current]::close $w] dirty [list [namespace current]::dirty $w] prepare [list [namespace current]::prepare $w] discard [list [namespace current]::discard $w]]}
proc ::GX::ReplicateViewer::save {w} {
    variable state;guard $w
    set payload [capture $w];dict set payload history [::GX::scientificHistoryViewerRecord $w]
    if {$state($w,id) eq {}} {set item [::GX::sessionWorkspaceCreate replicate_consensus [::GX::sessionWorkspaceAvailableName $state($w,workspaceName)] $payload]} else {set item [::GX::sessionWorkspaceUpdate $state($w,id) $payload]}
    set state($w,id) [dict get $item workspace_id];set state($w,generation) [dict get $item generation];set state($w,revision) [dict get $item revision]
    set state($w,saved) [capture $w]
    $w.footer.status configure -text {Workspace saved; scientific sources remain unchanged}
    return $state($w,id)
}
proc ::GX::ReplicateViewer::open {{context {}}} {
    variable state;variable input
    package require Tk
    set w .replicate_consensus
    if {[winfo exists $w]} {if {![::GX::sessionWorkspaceHostPrepare [dict get $::GX::SessionWorkspace::adapters $w] opening]} {raise $w;return $w};destroy $w}
    set state($w,token) [::GX::interactiveDocumentSessionToken];set state($w,id) {}
    set request [::GX::datasetPublicationV2DictDefault $context request [dict create analysis_id study_[clock seconds] method yx design repeatability grid_points 200 reference_frame {id {} declaration {} x_unit mm y_unit mm} traces {}]]
    set payload [dict create format gxtxt.replicate_viewer.v1 request $request hidden {}]
    set id [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {$id ni {{} new}} {set item [::GX::sessionWorkspaceGet $id];set payload [dict get $item payload];set state($w,id) $id;set state($w,generation) [dict get $item generation];set state($w,revision) [dict get $item revision]}
    set state($w,workspaceName) [::GX::datasetPublicationV2DictDefault $context workspace_name {Replicate study}]
    set state($w,payload) $payload;set state($w,saved) [dict remove $payload history];set state($w,busy) 0
    set commands [dict create sources {label {Add source…} default Ctrl+o} analyze {label Analyze default F5} cancel {label Cancel} publish {label {Publish results}} graph {label {Publish Graph}} save {label Save default Ctrl+s} undo {label Undo default Ctrl+z} redo {label Redo default Ctrl+y} fit {label {Fit all}} edit_source {label {Edit selected source…}} remove_source {label {Remove selected source}} zoom_in {label {Zoom in}} zoom_out {label {Zoom out}} digitizer_source {label {Add Digitizer source…}}]
    ::GX::viewerCommandCatalogRegister viewer.replicate_curve_analysis $commands
    set handlers {}
    foreach {id method args} {sources sourceDialog {} analyze analyze {} cancel cancel {} publish publish {} graph publishGraph {} save save {} undo navigate undo redo navigate redo fit fit {} edit_source editSource {} remove_source removeSource {} zoom_in zoom 1.25 zoom_out zoom 0.8 digitizer_source digitizerDialog {}} {dict set handlers $id [dict create command [list [namespace current]::safe $w $method {*}$args] enabled [list [namespace current]::enabled $w $id]]}
    set manifest [dict create schema gxtxt.viewer_gui_manifest.v1 viewer_id viewer.replicate_curve_analysis provider_id replicate_consensus window $w title {Replicate / Consensus Curves} handlers $handlers guard [list [namespace current]::guard $w] workspace [callbacks $w] history [dict create capture [list [namespace current]::capture $w] restore [list [namespace current]::restore $w] commit [list [namespace current]::historyCommit $w] guard [list [namespace current]::guard $w]]]
    if {[dict exists $payload history]} {dict set manifest history_record [dict get $payload history]}
    dict set manifest canvas {api_id PLOT_DATASET_API_v4}
    dict set manifest toolbar_actions {sources analyze cancel undo redo fit zoom_in zoom_out save}
    dict set manifest menus [list [dict create label Sources actions {sources digitizer_source edit_source remove_source}] [dict create label Study actions {analyze cancel - publish graph}] [dict create label Edit actions {undo redo}] [dict create label View actions {fit zoom_in zoom_out}]]
    dict set manifest context_actions {edit_source remove_source - fit zoom_in zoom_out - analyze publish graph save}
    dict set manifest inspector_width 330
    set slots [::GX::viewerGuiCompose $manifest]
    set p [dict get $slots inspector]
    set study [::GX::uiFieldViewerSection $p study {Scientific study}]
    set frame [::GX::uiFieldViewerSection $p frameSection {Physical reference frame}]
    set sources [::GX::uiFieldViewerSection $p sourceSection {Source observations}]
    ttk::label $p.heading -text {Scientific study};pack $p.heading -anchor w
    pack forget $p.heading
    foreach {key label values} {method Method {yx xy_path} design {Study design} {repeatability calibration_sensitivity hierarchical}} {
        set input($w,$key) [dict get $payload request $key]
        ::GX::uiFieldComponentCreate $p.l$key label [dict create text $label wraplength 0] {} {};::GX::uiFieldComponentCreate $p.$key combobox [dict create choices $values] [namespace current]::input($w,$key) {}
        pack $p.l$key $p.$key -in $study -fill x -pady 3
        ::GX::uiFieldSelectorWithinViewer $p.$key $w
    }
    foreach {key label default} {analysis_id {Unique analysis ID} {} frame {Common physical frame ID} {} x_unit {X reference unit} mm y_unit {Y reference unit} mm} {
        set value $default
        if {$key eq "analysis_id"} {set value [dict get $payload request analysis_id]} elseif {$key eq "frame"} {set value [dict get $payload request reference_frame id]} else {set value [dict get $payload request reference_frame $key]}
        set input($w,$key) $value;::GX::uiFieldComponentCreate $p.l$key label [dict create text $label wraplength 0] {} {};::GX::uiFieldComponentCreate $p.$key entry {} [namespace current]::input($w,$key) {};pack $p.l$key $p.$key -in [expr {$key eq "analysis_id"?$study:$frame}] -fill x -pady 2
    }
    set input($w,verified) [expr {[dict get $payload request reference_frame declaration] eq "explicit_user_verified"}]
    ::GX::uiFieldComponentCreate $p.verified checkbutton {label {I verified a common physical frame}} [namespace current]::input($w,verified) {};pack $p.verified -in $frame -anchor w -pady 5
    ::GX::uiFieldComponentCreate $p.sources list {height 6} {} {};pack $p.sources -in $sources -fill x
    ::GX::viewerGuiSelectionAttach $w $p.sources
    ::GX::viewerGuiContextMount $w $p.sources
    ::GX::uiFieldComponentCreate $p.remove action {label {Remove selected source}} {} [list ::GX::viewerCommandInvoke $w remove_source];pack $p.remove -in $sources -fill x -pady 3
    ::GX::uiFieldComponentCreate $p.assumptions label {wraplength 250 text {XY paths require an explicit common start landmark, direction and normalized physical source arc-length correspondence. Shared calibrations are sensitivity studies. Missing uncertainty is not zero.}} {} {};pack $p.assumptions -fill x -pady 6
    ::GX::uiFieldComponentCreate $p.report log {height 10 width 28} {} {};pack $p.report -fill x
    $w.footer.status configure -text {Add exact source observations, verify their physical frame, then Analyze. Wheel: zoom · Middle drag: pan · Double click: fit}
    wm protocol $w WM_DELETE_WINDOW [list [namespace current]::close $w]
    bind $w <Destroy> +[list [namespace current]::destroyed $w %W]
    refresh $w
    return $w
}
proc ::GX::ReplicateViewer::enabled {w action} {
    variable state
    if {$action eq "cancel"} {return $state($w,busy)}
    if {$action in {fit zoom_in zoom_out}} {return [winfo exists $w.body.canvas.plot]}
    if {$state($w,busy)} {return [expr {$action in {fit save}}]}
    if {$action in {edit_source remove_source}} {return [expr {[$w.body.inspector.scroll.content.sources curselection] ne {}}]}
    if {$action eq "publish" && [info exists state($w,rejectedTicket)]} {return 0}
    if {$action eq "publish"} {return [expr {[info exists state($w,ticket)] && [dict exists $state($w,payload) result] || [info exists state($w,ticket)] && [dict exists $state($w,payload) result_resource]}]}
    if {$action eq "graph"} {return [expr {[info exists state($w,ticket)] || [dict exists $state($w,payload) published_dataset]}]}
    return 1
}
proc ::GX::ReplicateViewer::refresh {w} {
    variable state
    set p $w.body.inspector.scroll.content
    if {![winfo exists $p.sources]} return
    $p.sources delete 0 end
    foreach trace [dict get $state($w,payload) request traces] {$p.sources insert end "[dict get $trace dataset_id] · [dict get $trace observation_id] · [dict get $trace calibration_realization_id]"}
    if {[dict exists $state($w,payload) result] || [dict exists $state($w,payload) result_resource]} {draw $w [resultValue $state($w,payload)]} else {
        catch {destroy $w.body.canvas.plot}
        catch {destroy $w.body.inspector.scroll.content.visibility}
    }
    ::GX::viewerGuiActionsRefresh $w
    publishGui $w
}
proc ::GX::ReplicateViewer::sourceDialog {w} {
    variable state;if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}};unset -nocomplain state($w,editingSource) state($w,editingTrace) state($w,editingInputs) state($w,sourceVariablesDataset)
    variable state;variable input
    if {[winfo exists $w.digitizer]} {error {Finish or cancel the Digitizer source dialog first}}
    set d $w.source
    if {[winfo exists $d]} {::GX::uiFieldDialogClose $d}
    ::GX::uiFieldDialogCreate $d $w {Add exact scientific observation}
    set ids {};foreach item [dict get [::GX::datasetCatalogSnapshot] datasets] {set id [dict get $item dataset_id];if {![catch {set schema [::GX::tableStreamCompatibleSchema $::GX::currentSession $id]}] && [llength $schema]>=2} {lappend ids $id}}
    if {$ids eq {}} {destroy $d;error {No compatible canonical table source is available}}
    set n [expr {[llength [dict get $state($w,payload) request traces]]+1}]
    foreach {key label default} [list dataset_id Dataset [lindex $ids 0] x_variable_id {X Variable} {} y_variable_id {Y Variable} {} curve_variable_id {Curve identity Variable (optional)} {} order_variable_id {Point-order Variable (XY required)} {} physical_feature_id {Physical feature ID} feature_1 curve_key {Curve key} curve_1 observation_id {Independent observation ID} observation_$n point_set_id {Original point-set ID} points_$n calibration_realization_id {Calibration realization ID} calibration_$n source_group_id {Independent source group ID} source_1 topology Topology open landmark_id {Corresponding physical start landmark} start direction Direction forward phase_index {Closed start landmark source index (0-based)} 0] {
        set input($w,source_$key) $default
        ttk::label $d.l$key -text $label
        if {$key in {dataset_id x_variable_id y_variable_id curve_variable_id order_variable_id topology direction}} {ttk::combobox $d.$key -state readonly -textvariable [namespace current]::input($w,source_$key);::GX::uiFieldSelectorWithinViewer $d.$key $d} else {ttk::entry $d.$key -textvariable [namespace current]::input($w,source_$key)}
        grid $d.l$key -row $n -column 0 -sticky w -padx 6 -pady 2;grid $d.$key -row $n -column 1 -sticky ew -padx 6 -pady 2;incr n
    }
    $d.dataset_id configure -values $ids;$d.topology configure -values {open closed};$d.direction configure -values {forward reverse}
    bind $d.dataset_id <<ComboboxSelected>> [list [namespace current]::sourceVariables $w]
    ttk::button $d.add -text {Add observation} -command [list [namespace current]::safe $w sourceAccept];grid $d.add -row $n -column 0 -columnspan 2 -sticky ew -pady 8
    grid columnconfigure $d 1 -weight 1
    sourceVariables $w
    ttk::button $d.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $d]
    grid $d.cancel -row [expr {$n+1}] -column 0 -columnspan 2 -pady 5
    ::GX::uiFieldDialogPresent $d $d.dataset_id
}
proc ::GX::ReplicateViewer::sourceVariables {w} {
    variable state;variable input
    set schema [::GX::tableStreamCompatibleSchema $::GX::currentSession $input($w,source_dataset_id)]
    set variables [lmap v $schema {dict get $v variable_id}]
    foreach key {x_variable_id y_variable_id curve_variable_id order_variable_id} {$w.source.$key configure -values [linsert $variables 0 {}]}
    if {![info exists state($w,sourceVariablesDataset)] || $state($w,sourceVariablesDataset) ne $input($w,source_dataset_id)} {
        set input($w,source_curve_variable_id) {};set input($w,source_order_variable_id) {}
    }
    set state($w,sourceVariablesDataset) $input($w,source_dataset_id)
    set input($w,source_x_variable_id) [lindex $variables 0];set input($w,source_y_variable_id) [lindex $variables 1]
    foreach variable $schema {
        set role [dict get $variable semantic_role]
        if {$role eq "independent"} {set input($w,source_x_variable_id) [dict get $variable variable_id]}
        if {$role eq "measured"} {set input($w,source_y_variable_id) [dict get $variable variable_id]}
    }
}
# Internal editor helpers; public scientific/preparation contracts are unchanged.
proc ::GX::ReplicateViewer::sourceInputSnapshot {w} {
    variable input
    set values {}
    foreach key {dataset_id x_variable_id y_variable_id curve_variable_id order_variable_id physical_feature_id curve_key observation_id point_set_id calibration_realization_id source_group_id topology landmark_id direction phase_index} {
        dict set values $key $input($w,source_$key)
    }
    dict set values frame_id $input($w,frame)
    return $values
}
proc ::GX::ReplicateViewer::sourceEditMerge {original baseline values} {
    set changed {}
    dict for {key value} $values {
        if {$value ne [dict get $baseline $key]} {lappend changed $key}
    }
    if {$changed eq {}} {return $original}
    # Only the known optional binding shape can proceed to fresh-owner guards.
    # Preserve unfamiliar recipes on open/save/no-op; never strip their binding.
    if {[dict exists $original source_binding]} {
        set binding [dict get $original source_binding]
        if {[catch {dict get $binding schema} schema] || $schema ne {gxtxt.replicate.source_binding.v1} || ![dict exists $binding kind] || [dict get $binding kind] ne {curve_digitizer}} {
            error {This source binding requires its supported source-preparation editor; Cancel preserves the original recipe}
        }
    }
    foreach key {dataset_id x_variable_id y_variable_id curve_variable_id order_variable_id curve_key calibration_realization_id frame_id} {
        if {$key ni $changed} continue
        foreach marker {filters coordinate_context source_revision} {
            if {[dict exists $original $marker]} {
                error {Changing this prepared source requires explicit CORE source re-resolution; Cancel preserves its filters and binding}
            }
        }
    }
    set trace $original
    foreach key $changed {
        set value [dict get $values $key]
        if {$value eq {}} {dict unset trace $key} else {dict set trace $key $value}
    }
    return $trace
}
proc ::GX::ReplicateViewer::sourceAccept {w} {
    variable state;variable input
    guard $w
    if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}}
    set payload $state($w,payload)
    set expected [dict remove $payload history]
    set traces [dict get $payload request traces]
    set values [sourceInputSnapshot $w]
    if {[info exists state($w,editingSource)]} {
        set index $state($w,editingSource)
        if {![info exists state($w,editingTrace)] || ![info exists state($w,editingInputs)] ||
            $index<0 || $index>=[llength $traces] || [lindex $traces $index] ne $state($w,editingTrace)} {
            error {Source changed while the editor was open; reopen the source editor}
        }
        set trace [sourceEditMerge $state($w,editingTrace) $state($w,editingInputs) $values]
        if {$trace eq $state($w,editingTrace)} {
            unset -nocomplain state($w,editingSource) state($w,editingTrace) state($w,editingInputs)
            destroy $w.source
            return
        }
        set traces [lreplace $traces $index $index $trace]
        set description {Edit scientific source observation}
    } else {
        set trace {}
        dict for {key value} $values {if {$value ne {}} {dict set trace $key $value}}
        lappend traces $trace
        set description {Add scientific source observation}
    }
    if {$input($w,frame) eq {}} {error {Declare the common physical frame before adding a source}}
    dict set payload request traces $traces
    if {![change $w $payload $description $expected]} return
    unset -nocomplain state($w,editingSource) state($w,editingTrace) state($w,editingInputs)
    destroy $w.source
}
proc ::GX::ReplicateViewer::removeSource {w} {variable state;if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}};set selected [lindex [$w.body.inspector.scroll.content.sources curselection] 0];if {$selected eq {}} return;set payload $state($w,payload);dict set payload request traces [lreplace [dict get $payload request traces] $selected $selected];change $w $payload {Remove selected source}}
proc ::GX::ReplicateViewer::analyze {w} {
    variable state;variable input
    set request [dict get $state($w,payload) request]
    foreach key {analysis_id method design} {dict set request $key $input($w,$key)}
    dict set request reference_frame [dict create id $input($w,frame) x_unit $input($w,x_unit) y_unit $input($w,y_unit) declaration [expr {$input($w,verified)?"explicit_user_verified":"unverified"}]]
    if {[dict get $request method] eq "xy_path"} {dict set request correspondence anchored_source_arclength}
    _validateRequestBindings $request
    set request [::GX::Replicate::preflight $request]
    _validateRequestBindings $request
    set payload $state($w,payload);set expected [dict remove $payload history];dict set payload request $request
    if {![change $w $payload {Configure scientific study} $expected]} return
    _validateRequestBindings $request
    set state($w,busy) 1;::GX::viewerCommandToolbarRefresh $w
    if {[catch {set ticket [::GX::Replicate::submit $request]} message options]} {set state($w,busy) 0;::GX::viewerCommandToolbarRefresh $w;return -options $options $message}
    if {[catch {_validateRequestBindings [dict get $ticket request]} message options]} {
        set state($w,ticket) $ticket;set state($w,busy) 1
        set cancelCode [catch {::GX::Replicate::cancel $ticket} cancelResult]
        set detail "$message; managed Job [dict get $ticket job_id]; cancellation request [expr {$cancelCode ? {failed} : {returned}}]: $cancelResult"
        set state($w,rejectedTicket) $detail
        ::GX::viewerCommandToolbarRefresh $w;poll $w
        return -options $options $detail
    }
    unset -nocomplain state($w,rejectedTicket)
    set state($w,ticket) $ticket;set state($w,busy) 1
    ::GX::viewerCommandToolbarRefresh $w
    poll $w
}
proc ::GX::ReplicateViewer::poll {w} {
    variable state
    if {![winfo exists $w] || ![info exists state($w,ticket)]} return
    set ticket $state($w,ticket)
    if {[catch {guard $w} error]} {$w.footer.status configure -text "Managed Job [dict get $ticket job_id]: $error";return}
    if {[catch {set job [::GX::Replicate::status $ticket]} error]} {
        if {[info exists state($w,rejectedTicket)]} {
            if {![info exists state($w,rejectedStatusRetries)]} {set state($w,rejectedStatusRetries) 0}
            incr state($w,rejectedStatusRetries)
            if {$state($w,rejectedStatusRetries)<=5} {set state($w,timer) [after 1000 [list [namespace current]::poll $w]]}
            $w.footer.status configure -text "$state($w,rejectedTicket); status read failed: $error. After bounded retries, Cancel retries the cancellation/status request; Job state is unconfirmed."
        } else {$w.footer.status configure -text $error}
        return
    }
    unset -nocomplain state($w,rejectedStatusRetries)
    if {[info exists state($w,rejectedTicket)]} {
        $w.footer.status configure -text "$state($w,rejectedTicket); observed Job state: [dict get $job state]"
    } else {$w.footer.status configure -text "Replicate scientific Job: [dict get $job state]"}
    # Exact terminal enum from the authoritative Script Job supervisor.
    if {[dict get $job state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {set state($w,timer) [after 300 [list [namespace current]::poll $w]];return}
    set state($w,busy) 0
    if {[dict get $job state] ne {COMPLETED}} {
        set ending "Managed Job [dict get $ticket job_id] ended in [dict get $job state]"
        if {[dict exists $job error] && [dict get $job error] ne {}} {append ending ": " [dict get $job error]}
        if {[info exists state($w,rejectedTicket)]} {set ending "$state($w,rejectedTicket); $ending"}
        $w.footer.status configure -text $ending
    }
    if {[dict get $job state] eq {COMPLETED} && ![info exists state($w,rejectedTicket)]} {
        # Capture before fallible result/resource work; change checks after History.
        set expected [dict remove $state($w,payload) history]
        if {[catch {
            if {[dict get $ticket request] ne [dict get $state($w,payload) request]} {error {Study configuration changed; the completed Job cannot replace it}}
            _validateRequestBindings [dict get $ticket request]
            set result [::GX::Replicate::result $ticket]
            _validateRequestBindings [dict get $ticket request]
            if {![info exists state($w,ticket)] || $state($w,ticket) ne $ticket} {error {Managed study changed during result resolution}}
            set payload [storeResult $w $state($w,payload) $result]
            change $w $payload {Adopt completed scientific study} $expected $ticket
        } message]} {$w.footer.status configure -text $message}
    }
    ::GX::viewerCommandToolbarRefresh $w
}
proc ::GX::ReplicateViewer::cancel {w} {
    variable state
    if {![info exists state($w,ticket)]} return
    set code [catch {::GX::Replicate::cancel $state($w,ticket)} result options]
    if {[info exists state($w,rejectedTicket)]} {
        if {[info exists state($w,timer)]} {after cancel $state($w,timer);unset state($w,timer)}
        unset -nocomplain state($w,rejectedStatusRetries);poll $w
    }
    if {$code} {return -options $options $result}
    return $result
}
proc ::GX::ReplicateViewer::navigate {w direction} {::GX::scientificHistoryViewerNavigate $w $direction}
proc ::GX::ReplicateViewer::fit {w} {if {[winfo exists $w.body.canvas.plot]} {::GX::PlotDatasetAPIv4::widgetView $w.body.canvas.plot fit;rememberView $w}}
proc ::GX::ReplicateViewer::zoom {w factor} {::GX::PlotDatasetAPIv4::widgetView $w.body.canvas.plot zoom main $factor .5 .5;rememberView $w}
proc ::GX::ReplicateViewer::draw {w result} {
    set columns [dict get $result columns];set points {};set bounds {Inf Inf -Inf -Inf}
    foreach x [dict get $columns x_mean] y [dict get $columns y_mean] {lappend points [list $x $y];foreach index {0 1 2 3} value [list $x $y $x $y] {lset bounds $index [expr {$index<2?min([lindex $bounds $index],$value):max([lindex $bounds $index],$value)}]}}
    set series [dict create id consensus label Consensus axis left kind line style {color #0072B2 line_width 2 marker none} points $points breaks {} full_bounds $bounds row_count [llength $points]]
    set axes [dict create x [dict create label "X ([dict get $result units x_mean])"] left [dict create label "Y ([dict get $result units y_mean])"]]
    set allSeries [list $series]
    set index 0
    dict for {key trace} [::GX::datasetPublicationV2DictDefault $result original_traces {}] {
        set identity [dict get $trace identity];set points [dict get $trace points];set sourceRows [dict get $trace source_rows]
        if {[::GX::datasetPublicationV2DictDefault $identity topology open] eq "closed" && [lindex $points 0] ne [lindex $points end]} {lappend points [lindex $points 0];lappend sourceRows [lindex $sourceRows 0]}
        set full {Inf Inf -Inf -Inf}
        foreach point $points {lassign $point x y;foreach i {0 1 2 3} value [list $x $y $x $y] {lset full $i [expr {$i<2?min([lindex $full $i],$value):max([lindex $full $i],$value)}]}}
        set palette {#C84427 #238B45 #8849A3 #A67513 #008B8B}
        lappend allSeries [dict create id trace_$key label "[dict get $identity observation_id] · original" axis left kind line style [dict create color [lindex $palette [expr {$index%5}]] line_width 1 marker none] points $points source_rows $sourceRows breaks {} full_bounds $full source_descriptor [dict get $trace descriptor] row_count [llength $points]]
        incr index
    }
    # Aligned coordinates are explicitly derived samples, never original row
    # picks. Dispersion limits are sample spread, not confidence intervals.
    dict for {key points} [::GX::datasetPublicationV2DictDefault $result aligned_traces {}] {
        set full {Inf Inf -Inf -Inf}
        foreach point $points {lassign $point x y;foreach i {0 1 2 3} value [list $x $y $x $y] {lset full $i [expr {$i<2?min([lindex $full $i],$value):max([lindex $full $i],$value)}]}}
        lappend allSeries [dict create id aligned_$key label "Observation [expr {$key+1}] · aligned" axis left kind line style {color #7295AA line_width 1 marker none} points $points source_rows [lrepeat [llength $points] -1] breaks {} full_bounds $full row_count [llength $points]]
        if {![dict exists $::GX::ReplicateViewer::state($w,payload) visibility_initialized]} {dict set ::GX::ReplicateViewer::state($w,payload) hidden aligned_$key 1}
    }
    foreach {name sign} {spread_lower -1 spread_upper 1} {
        set points {};set full {Inf Inf -Inf -Inf}
        foreach x [dict get $columns x_mean] y [dict get $columns y_mean] spread [dict get $columns y_std] {
            if {![string is double -strict $spread] || [catch {expr {abs($spread)<Inf}} finite] || !$finite} {set points {};break}
            set y [expr {$y+$sign*$spread}];lappend points [list $x $y]
            foreach i {0 1 2 3} value [list $x $y $x $y] {lset full $i [expr {$i<2?min([lindex $full $i],$value):max([lindex $full $i],$value)}]}
        }
        if {$points ne {}} {
            lappend allSeries [dict create id $name label [expr {$sign<0?"Mean − sample SD":"Mean + sample SD"}] axis left kind line style {color #AA7650 line_width 1 marker none} points $points source_rows [lrepeat [llength $points] -1] breaks {} full_bounds $full row_count [llength $points]]
            if {![dict exists $::GX::ReplicateViewer::state($w,payload) visibility_initialized]} {dict set ::GX::ReplicateViewer::state($w,payload) hidden $name 1}
        }
    }
    dict set ::GX::ReplicateViewer::state($w,payload) visibility_initialized 1
    set model [dict create title {Replicate / Consensus} panels [list [dict create id main axes $axes series $allSeries annotations {}]] native_presentation [dict create schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1 graphics {} axes {} panels {} layout {} legend {placement inside}]]
    set ::GX::ReplicateViewer::state($w,view_model) $model
    set p $w.body.inspector.scroll.content
    if {![winfo exists $p.visibility]} {ttk::labelframe $p.visibility -text {Retained curve visibility};pack $p.visibility -fill x -pady 4}
    foreach child [winfo children $p.visibility] {destroy $child}
    set i 0
    foreach series $allSeries {
        set id [dict get $series id];set ::GX::ReplicateViewer::input($w,visible,$id) [expr {![dict exists $::GX::ReplicateViewer::state($w,payload) hidden $id]}]
        ttk::checkbutton $p.visibility.s[incr i] -text [dict get $series label] -variable ::GX::ReplicateViewer::input($w,visible,$id) -command [list [namespace current]::safe $w visibility $id]
        pack $p.visibility.s$i -anchor w
    }
    set path $w.body.canvas.plot
    if {[winfo exists $path]} {::GX::PlotDatasetAPIv4::widgetConfigure $path $model {prepared_model 1}} else {::GX::PlotDatasetAPIv4::widgetCreate $path $model {prepared_model 1};pack $path -fill both -expand 1;::GX::viewerGuiContextMount $w $path}
    bind $path <Button-1> [list [namespace current]::pick $w %x %y]
    bind $path <ButtonRelease-2> +[list [namespace current]::rememberView $w]
    bind $path <ButtonRelease-4> +[list [namespace current]::rememberView $w]
    bind $path <ButtonRelease-5> +[list [namespace current]::rememberView $w]
    if {[dict exists $::GX::ReplicateViewer::state($w,payload) view_axes]} {::GX::PlotDatasetAPIv4::widgetView $path restore [dict get $::GX::ReplicateViewer::state($w,payload) view_axes]}
    dict for {id ignored} [dict get $::GX::ReplicateViewer::state($w,payload) hidden] {::GX::PlotDatasetAPIv4::widgetVisibility $path main $id 0}
    set p $w.body.inspector.scroll.content.report;$p configure -state normal;$p delete 1.0 end;set qualifications [dict get $result qualifications]
    $p insert end "Study: [dict get $result analysis_id]\n"
    foreach {key label} {design {Study design} independent_observations {Declared independent observations} shared_calibration_covariance {Shared calibration covariance} confidence_interval {Confidence interval} prediction_interval {Prediction interval} localization_uncertainty {Localization uncertainty} calibration_uncertainty {Calibration uncertainty} topology {Correspondence}} {
        if {[dict exists $qualifications $key]} {$p insert end "$label: [string map {_ { }} [dict get $qualifications $key]]\n"}
    }
    $p insert end "Sample spread is descriptive; missing uncertainty does not imply zero.\n"
    $p configure -state disabled
    $w.footer.status configure -text "Study [dict get $result analysis_id] · [llength [dict get $columns x_mean]] consensus points · original sources retained"
}
proc ::GX::ReplicateViewer::publish {w} {variable state;if {[info exists state($w,rejectedTicket)]} {error $state($w,rejectedTicket)};_validateRequestBindings [dict get $state($w,ticket) request];set result [::GX::Replicate::publish $state($w,ticket)];dict set state($w,payload) published_dataset [dict get $result dataset_id];$w.footer.status configure -text "Published canonical study Dataset: [dict get $result dataset_id]";return $result}
proc ::GX::ReplicateViewer::publishGraph {w} {
    variable state
    if {![dict exists $state($w,payload) published_dataset]} {publish $w}
    set id [dict get $state($w,payload) published_dataset]
    set spec [::GX::PlotDatasetAPIv4::newSpec -title {Replicate / Consensus study}]
    dict set spec panels [list [dict create id main axes {} annotations {} series [list [dict create id consensus dataset_id $id x_variable_id x_mean y_variable_id y_mean axis left kind line label Consensus]]]]
    set ref [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
    dict set state($w,payload) plot_ref $ref
    $w.footer.status configure -text "Published native editable Plot v4 Graph: $ref"
    return $ref
}
proc ::GX::ReplicateViewer::destroyed {w actual} {variable state;variable input;if {$w ne $actual} return;if {[info exists state($w,timer)]} {after cancel $state($w,timer)};array unset state "$w,*";array unset input "$w,*"}
proc ::GX::ReplicateViewer::dispatch {action scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister replicate_consensus_tk ::GX::ReplicateViewer::dispatch

proc ::GX::ReplicateViewer::visibility {w id} {
    variable state;variable input
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    ::GX::PlotDatasetAPIv4::widgetVisibility $w.body.canvas.plot main $id $input($w,visible,$id)
    if {$input($w,visible,$id)} {if {[dict exists $state($w,payload) hidden $id]} {dict unset state($w,payload) hidden $id}} else {dict set state($w,payload) hidden $id 1}
    ::GX::scientificHistoryViewerChanged $w {Change retained curve visibility}
}
proc ::GX::ReplicateViewer::pick {w x y} {
    set hit [::GX::PlotDatasetAPIv4::widgetHit $w.body.canvas.plot $x $y]
    variable state
    set state($w,selection) $hit
    if {[dict exists $hit series_id] && [regexp {^trace_([0-9]+)$} [dict get $hit series_id] -> index]} {
        set list $w.body.inspector.scroll.content.sources;$list selection clear 0 end;$list selection set $index;$list see $index
    }
    ::GX::viewerCommandToolbarRefresh $w
    $w.footer.status configure -text "Native scientific selection: $hit"
}

proc ::GX::ReplicateViewer::rememberView {w} {
    variable state
    if {[catch {guard $w}]} return
    set receipt [::GX::PlotDatasetAPIv4::widgetReceipt $w.body.canvas.plot]
    if {[dict exists $receipt axes]} {dict set state($w,payload) view_axes [dict get $receipt axes]}
}

proc ::GX::ReplicateViewer::editSource {w} {
    variable state;variable input
    set selected [$w.body.inspector.scroll.content.sources curselection];if {$selected eq {}} return
    set index [lindex $selected 0];set trace [lindex [dict get $state($w,payload) request traces] $index]
    if {[dict exists $trace source_binding]} {
        set binding [dict get $trace source_binding]
        if {![catch {dict get $binding schema} schema] && $schema eq {gxtxt.replicate.source_binding.v1} && ![catch {dict get $binding kind} kind] && $kind eq {curve_digitizer}} {digitizerDialog $w $index;return}
    }
    try {
        sourceDialog $w
        # Populate choices from the edited Dataset, then restore its actual fields.
        set input($w,source_dataset_id) [dict get $trace dataset_id]
        sourceVariables $w
        foreach key {dataset_id x_variable_id y_variable_id curve_variable_id order_variable_id physical_feature_id curve_key observation_id point_set_id calibration_realization_id source_group_id topology landmark_id direction phase_index} {
            if {[dict exists $trace $key]} {set input($w,source_$key) [dict get $trace $key]}
        }
        set state($w,editingSource) $index
        set state($w,editingTrace) $trace
        # Defaults displayed for absent optional fields are not implicit edits.
        set state($w,editingInputs) [sourceInputSnapshot $w]
    } on error {message options} {
        # Failed Edit setup must never leave an actionable Add dialog.
        unset -nocomplain state($w,editingSource) state($w,editingTrace) state($w,editingInputs) state($w,sourceVariablesDataset)
        catch {::GX::uiFieldDialogClose $w.source}
        catch {destroy $w.source}
        if {[winfo exists $w.source]} {set state($w,editingSource) -1}
        return -options $options $message
    }
}

# Explicit read-only generic GUI declaration. Scientific callbacks, Jobs and
# Workspace payloads remain under this Viewer and its existing CORE owners.
proc ::GX::ReplicateViewer::publishGui {w} {
    variable state;variable input
    set shell [dict get $::GX::ViewerGui::shells $w];set manifest [dict get $shell manifest]
    set design [::GX::viewerGuiDesignNew {Replicate / Consensus Curves}]
    dict set design module_id viewer.replicate_curve_analysis;dict set design provider_id replicate_consensus
    dict set design version 1.2.0;dict set design shell inspector_width 330;dict set design shell status [$w.footer.status cget -text]
    dict set design origin [dict create module viewer.replicate_curve_analysis provider replicate_consensus scope main_viewer_interface]
    set components {};set widgets {};set values {};set handlers {};set bindings {}
    dict for {id descriptor} [::GX::viewerCommandCatalog viewer.replicate_curve_analysis] {
        dict set handlers $id [dict create arguments {window action} effect [expr {$id in {fit zoom_in zoom_out undo redo} ? {presentation} : {mutating}}] label [dict get $descriptor label] default [::GX::datasetPublicationV2DictDefault $descriptor default {}] available [::GX::viewerCommandEnabled $w $id]]
    }
    lappend components [dict create id commands type command_toolbar parent toolbar properties [dict create actions [dict get $manifest toolbar_actions]] layout {}]
    dict set widgets commands $w.toolbar
    set n 0
    foreach menu [dict get $manifest menus] {incr n;set id menu_$n;lappend components [dict create id $id type menu parent menubar properties $menu layout {}];dict set widgets $id $w.menus.actions$n}
    lappend components [dict create id context_commands type context_menu parent canvas properties [dict create actions [dict get $manifest context_actions]] layout {}]
    dict set widgets context_commands $w.context
    set p $w.body.inspector.scroll.content
    foreach {id actual title} {study study {Scientific study} physical_frame frameSection {Physical reference frame} observations sourceSection {Source observations}} {
        lappend components [dict create id $id type section parent inspector properties [dict create title $title padding 8] layout {manager pack fill x pady 5}]
        dict set widgets $id $p.$actual
    }
    foreach {key title type parent choices} {
        method Method combobox study {yx xy_path}
        design {Study design} combobox study {repeatability calibration_sensitivity hierarchical}
        analysis_id {Unique analysis ID} entry study {}
        frame {Common physical frame ID} entry physical_frame {}
        x_unit {X reference unit} entry physical_frame {}
        y_unit {Y reference unit} entry physical_frame {}
    } {
        set padding [expr {$type eq {combobox} ? 3 : 2}]
        lappend components [dict create id label_$key type label parent $parent properties [dict create text $title wraplength 0] layout [dict create manager pack fill x pady $padding]]
        set properties [dict create default $input($w,$key)];if {$choices ne {}} {dict set properties choices $choices}
        lappend components [dict create id value_$key type $type parent $parent properties $properties layout [dict create manager pack fill x pady $padding]]
        dict set widgets label_$key $p.l$key;dict set widgets value_$key $p.$key
        dict set values value_$key $input($w,$key)
    }
    foreach {id type parent properties layout widget} [list \
        verified checkbutton physical_frame [dict create label {I verified a common physical frame} default $input($w,verified)] {manager pack anchor w pady 5} $p.verified \
        source_list list observations [dict create items [$p.sources get 0 end] height 6] {manager pack fill x} $p.sources \
        remove_source action observations {label {Remove selected source} action remove_source} {manager pack fill x pady 3} $p.remove \
        assumptions label inspector [dict create text [$p.assumptions cget -text] wraplength 250] {manager pack fill x pady 6} $p.assumptions \
        result_report log inspector [dict create text [$p.report get 1.0 end-1c] height 10 width 28] {manager pack fill x} $p.report \
        scientific_view plot canvas {empty_style blank} {manager pack fill both expand 1} $w.body.canvas \
        history history footer {} {} $w.footer.historyStrip \
        workspace workspace footer {} {} $w.menus.workspace \
        help help footer {} {} $w.menus] {
        lappend components [dict create id $id type $type parent $parent properties $properties layout $layout]
        dict set widgets $id $widget
    }
    dict set values verified $input($w,verified);dict set values source_list [$p.sources curselection]
    if {[winfo exists $p.visibility]} {
        lappend components [dict create id visibility type section parent inspector properties {title {Retained curve visibility} padding 0} layout {manager pack fill x pady 4}]
        dict set widgets visibility $p.visibility;set i 0
        foreach series [dict get [lindex [dict get $state($w,view_model) panels] 0] series] {
            incr i;set id visible_$i;set key [dict get $series id]
            set properties [dict create label [dict get $series label] default $input($w,visible,$key) plot_visibility [dict create component scientific_view panel main series $key]]
            lappend components [dict create id $id type checkbutton parent visibility properties $properties layout {manager pack anchor w}]
            dict set widgets $id $p.visibility.s$i;dict set values $id $input($w,visible,$key)
        }
        set model $state($w,view_model)
        set visibility {};foreach series [dict get [lindex [dict get $model panels] 0] series] {dict set visibility main [dict get $series id] [expr {![dict exists $state($w,payload) hidden [dict get $series id]]}]}
        set binding [dict create kind plot spec $model context {prepared_model 1} visibility $visibility]
        set receipt [::GX::PlotDatasetAPIv4::widgetReceipt $w.body.canvas.plot]
        if {[dict exists $receipt axes]} {dict set binding view_axes [dict get $receipt axes]}
        dict set bindings scientific_view $binding
    }
    dict set design components $components;dict set design handlers $handlers
    foreach component $components {set cap [dict get [::GX::viewerGuiComponentCapabilities] [dict get $component type]];dict set design requirements [dict get $cap api_id] [dict get $cap api_version]}
    set boundaries [list [dict create classification domain_handler owner viewer.replicate_curve_analysis scope {Source observation editor, Analyze, Publish and Save remain domain callback contracts; importing the generic interface does not execute or duplicate them.}]]
    return [::GX::viewerGuiDesignPublish $w $design $widgets $values $bindings $boundaries]
}
proc ::GX::ReplicateViewer::describeGui {} {
    if {![winfo exists .replicate_consensus]} {return [dict create status OPEN_REQUIRED reason {Open the original Replicate Viewer for an explicit read-only declaration of its current visible interface.}]}
    return [dict merge [publishGui .replicate_consensus] [dict create status DECLARED_MAIN_INTERFACE]]
}

# Thin optional producer adapter. Canonical source/science owners remain sole authorities.
proc ::GX::ReplicateViewer::_sourceFail {code message} {return -code error -errorcode [list REPLICATE SOURCE $code] $message}
proc ::GX::ReplicateViewer::_sourceDictEqual {a b} {
    if {[catch {dict keys $a} ak] || [catch {dict keys $b} bk] || [lsort $ak] ne [lsort $bk]} {return 0}
    foreach k $ak {if {[dict get $a $k] ne [dict get $b $k]} {return 0}}
    return 1
}
proc ::GX::ReplicateViewer::sourceCapabilities {} {
    set required {CURVE_DIGITIZER_DATASET_SCHEMA_API_v1 CURVE_DIGITIZER_CALIBRATION_API_v1 CURVE_DIGITIZER_UNCERTAINTY_API_v1}
    set declared [::GX::modulePublicApiIds viewer.curve_digitizer]
    set missing {};foreach api $required {if {$api ni $declared} {lappend missing $api}}
    return [dict create api_id REPLICATE_VIEWER_API_v1 api_version 1 operations {sourceCapabilities describeDigitizerSource prepareDigitizerTrace} source_description_schema gxtxt.replicate.source_description.v1 trace_binding_schema gxtxt.replicate.source_binding.v1 source_kinds {generic curve_digitizer} producer [dict create module_id viewer.curve_digitizer declared [expr {$missing eq {}}] enabled [::GX::moduleIsEnabled viewer.curve_digitizer] version [::GX::moduleField viewer.curve_digitizer version {}] missing_apis $missing activation not_requested] page_rows_max 4096 pagination_identity_guard compare_each_page_to_first_public_identity shared_factor_covariance unavailable implicit_analysis 0]
}
proc ::GX::ReplicateViewer::_sourceSnapshot {dataset} {
    set session [::GX::sessionInspectionCurrentSession];set token [::GX::interactiveDocumentSessionToken]
    set revision [::GX::datasetRevisionToken $dataset $session]
    set identity [::GX::curveSourceDatasetIdentity $session $dataset]
    if {$token ne [::GX::interactiveDocumentSessionToken] || $session ne [::GX::sessionInspectionCurrentSession]} {_sourceFail SESSION_CHANGED {Session changed while reading source identity}}
    if {$revision ne [::GX::datasetRevisionToken $dataset $session]} {_sourceFail SOURCE_CHANGED {Dataset changed while reading its public snapshot}}
    if {$token ne [::GX::interactiveDocumentSessionToken]} {_sourceFail SESSION_CHANGED {Session changed while completing source identity}}
    return [dict create session $session session_token $token source_revision $revision source_identity $identity]
}
proc ::GX::ReplicateViewer::_sourceCheck {dataset expected} {
    set now [_sourceSnapshot $dataset]
    if {[dict get $now session_token] ne [dict get $expected session_token] || ([dict exists $expected session] && [dict get $now session] ne [dict get $expected session])} {_sourceFail SESSION_CHANGED {Session changed; resolve the source again}}
    if {[dict get $now source_revision] ne [dict get $expected source_revision] || ![_sourceDictEqual [dict get $now source_identity] [dict get $expected source_identity]]} {_sourceFail SOURCE_CHANGED {Dataset identity or revision changed; explicit source rebind is required}}
    return $now
}
proc ::GX::ReplicateViewer::_sourceProducer {dataset expected} {
    foreach api {CURVE_DIGITIZER_DATASET_SCHEMA_API_v1 CURVE_DIGITIZER_CALIBRATION_API_v1} {::GX::modulePublicApiActivate viewer.curve_digitizer $api}
    _sourceCheck $dataset $expected
    set session [dict get $expected session]
    set manifest [::GX::CurveDigitizerDataset::read $dataset $session]
    set roles [dict get $manifest columns]
    dict for {role variable} [dict get $manifest variables] {if {![dict get $variable enabled]} {_sourceFail UNSUPPORTED_SCHEMA {A producer role Variable is disabled}}}
    set metadata [::GX::datasetMetadataRead $session $dataset]
    set base [::GX::CurveDigitizerCalibration::read $dataset $session]
    set records {};set active {}
    foreach entry [::GX::CurveDigitizerCalibration::replicates $dataset] {
        set mid [dict get $entry measurement_id]
        if {$mid eq {} || [dict exists $records $mid]} {_sourceFail UNAVAILABLE_BINDING {Invalid calibration measurement identity}}
        dict set records $mid $entry
        if {[dict get $entry active]} {set active $mid}
    }
    set present 0;foreach field {publication_calibration_mode publication_calibration_ids publication_measurement_id} {if {[dict exists $metadata curve_digitizer.$field]} {incr present}}
    set mode [dict get $manifest publication_calibration_mode]
    if {$present==0 && ![dict exists $metadata curve_digitizer.measurement_count] && $mode eq {separate} && [dict keys $records] eq {legacy_active}} {
        set ids {legacy_active};set primary legacy_active;set provenance legacy_primary_only
    } else {
        if {$present!=3 || [dict get $metadata curve_digitizer.publication_calibration_mode] ne $mode} {_sourceFail UNAVAILABLE_BINDING {Published calibration subset or layout provenance is missing or inconsistent}}
        set encoded [dict get $metadata curve_digitizer.publication_calibration_ids]
        if {[string bytelength $encoded]>16384 || ![regexp {^\["meas_[a-f0-9]{32}"(,"meas_[a-f0-9]{32}")*\]$} $encoded]} {_sourceFail UNAVAILABLE_BINDING {Unsupported published calibration ID array; expected the producer's bounded compact JSON}}
        set ids [regexp -all -inline {meas_[a-f0-9]{32}} $encoded]
        set primary [dict get $metadata curve_digitizer.publication_measurement_id]
        if {[llength $ids]>200 || [llength $ids]!=[llength [lsort -unique $ids]] || $primary ne [lindex $ids 0] || ($mode eq {separate} && [llength $ids]!=1)} {_sourceFail UNAVAILABLE_BINDING {Published calibration subset or primary measurement is invalid}}
        set provenance published_measurement_subset
    }
    foreach mid $ids {
        if {![dict exists $records $mid] || [dict get $records $mid valid] ne {1} || [dict get $records $mid state] ne {accepted}} {_sourceFail UNAVAILABLE_BINDING {Published measurement is missing, invalid or not accepted}}
    }
    if {$active ne $primary || ([dict exists $metadata curve_digitizer.active_measurement_id] && [dict get $metadata curve_digitizer.active_measurement_id] ne $primary)} {_sourceFail UNAVAILABLE_BINDING {Published primary and active calibration provenance disagree}}
    _sourceCheck $dataset $expected
    set context [dict create manifest $manifest roles $roles base $base records $records publication [dict create mode $mode selected_ids $ids primary_id $primary provenance $provenance]]
    # Validate the primary even when direct preparation selects a secondary MID.
    _sourceCalibration $dataset $context $primary
    _sourceCheck $dataset $expected
    return $context
}
proc ::GX::ReplicateViewer::_sourceCalibration {dataset context mid} {
    if {$mid ni [dict get $context publication selected_ids]} {_sourceFail INVALID_SELECTION {Measurement is outside the published calibration subset}}
    set entry [dict get $context records $mid]
    if {[dict get $entry valid] ne {1} || [dict get $entry state] ne {accepted}} {_sourceFail INVALID_SELECTION {Calibration must be accepted and valid}}
    set legacy [expr {[dict get $context publication provenance] eq {legacy_primary_only}}]
    set identity [expr {$legacy ? [::GX::CurveDigitizerCalibration::identity $dataset] : [::GX::CurveDigitizerCalibration::identity $dataset $mid]}]
    if {$mid eq [dict get $context publication primary_id] && ![_sourceDictEqual $identity [::GX::CurveDigitizerCalibration::identity $dataset]]} {_sourceFail UNAVAILABLE_BINDING {Primary calibration identity disagrees with its published measurement}}
    foreach axis {x y} {
        if {[dict get $entry transform ${axis}_axis unit] ne [dict get $context manifest variables $axis unit]} {_sourceFail UNSUPPORTED_SCHEMA {Published scientific axis units disagree with the selected calibration}}
    }
    set base [dict get $context base]
    return [dict create measurement_id $mid identity $identity configuration_id [dict get $base configuration_id] source_dataset_id [dict get $base source_dataset_id] source_sha256 [dict get $base source_sha256]]
}
proc ::GX::ReplicateViewer::_sourceUncertainty {dataset session} {
    set md [::GX::datasetMetadataRead $session $dataset]
    if {![dict exists $md curve_digitizer.uncertainty_schema_version]} {
        set retained 0
        foreach key {curve_digitizer.uncertainty_binding curve_digitizer.uncertainty_report_json curve_digitizer.uncertainty_factors_json curve_digitizer.uncertainty_dataset_sha256 curve_digitizer.uncertainty_point_count curve_digitizer.uncertainty_source_sha256 curve_digitizer.uncertainty_covariance_xy_unit} {if {[dict exists $md $key]} {set retained 1}}
        return [dict create status [expr {$retained ? {incomplete_publication} : {not_published}}] reason uncertainty_schema_absent scope whole_published_dataset]
    }
    if {[dict get $md curve_digitizer.uncertainty_schema_version] ne {2}} {return {status unsupported_schema reason expected_uncertainty_schema2 scope whole_published_dataset}}
    if {[catch {::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_UNCERTAINTY_API_v1;set report [::GX::CurveDigitizerUncertainty::read $dataset]} message options]} {return [dict create status refused reason [string range $message 0 2047] owner_errorcode [dict get $options -errorcode] scope whole_published_dataset]}
    set count [dict get $report point_count]
    if {![string is integer -strict $count] || $count<1 || $count>4096 || $count ne [dict get $report core_binding point_count] || $count ne [dict get $report core_meaning summary point_count]} {return {status refused reason uncertainty_point_count_mismatch scope whole_published_dataset}}
    return [dict create status readable schema [dict get $report schema] point_count $count dataset_sha256 [dict get $report dataset_sha256] source_dataset_id [dict get $report source_dataset_id] source_integrity [dict get $report source_integrity] scope whole_published_dataset selected_subset_mapping not_admitted shared_factor_covariance unavailable]
}
proc ::GX::ReplicateViewer::describeDigitizerSource {datasetId {options {}}} {
    foreach key [dict keys $options] {if {$key ni {start count expected_revision expected_session_token}} {_sourceFail INVALID_SELECTION {Unknown source-description option}}}
    set start [::GX::datasetPublicationV2DictDefault $options start 0];set count [::GX::datasetPublicationV2DictDefault $options count 4096]
    if {![string is entier -strict $start] || $start<0 || ![string is integer -strict $count] || $count<1 || $count>4096} {_sourceFail RANGE_OUTSIDE_DATASET {Source page requires start>=0 and count1..4096}}
    if {$start>0 && (![dict exists $options expected_revision] || ![dict exists $options expected_session_token])} {_sourceFail SOURCE_CHANGED {Subsequent pages require the first page's revision and Session token}}
    set expected [_sourceSnapshot $datasetId]
    foreach {option field} {expected_revision source_revision expected_session_token session_token} {if {[dict exists $options $option] && [dict get $options $option] ne [dict get $expected $field]} {_sourceFail SOURCE_CHANGED {Source page expectation is stale}}}
    set context [_sourceProducer $datasetId $expected];set roles [dict get $context roles];set combined [expr {[dict get $context publication mode] eq {combined}}]
    set projected {curve_key curve_name};if {$combined} {lappend projected calibration_key calibration_name}
    set ids [lmap role $projected {dict get $roles $role}];set session [dict get $expected session]
    set stream [::GX::tableStreamOpenDataset $session $datasetId $ids 1 {start 0 count 0 numeric_transport values}]
    try {set total [dict get [::GX::tableStreamMetadata $stream] row_count]} finally {::GX::tableStreamClose $stream}
    _sourceCheck $datasetId $expected
    if {![string is entier -strict $total] || $total<0} {_sourceFail UNKNOWN_ROW_COUNT {Bounded source discovery requires a known canonical row count}}
    if {$start>$total} {_sourceFail RANGE_OUTSIDE_DATASET {Source page starts outside the Dataset}}
    set page [expr {min($count,$total-$start)}];set groups {};set order {};set consumed 0
    if {$page>0} {
        set stream [::GX::tableStreamOpenDataset $session $datasetId $ids $page [dict create start $start count $page numeric_transport values]]
        try {
            set chunk [::GX::tableStreamNext $stream];set consumed [dict get $chunk row_count]
            if {$consumed!=$page || [dict get $chunk offset]!=$start} {_sourceFail UNSUPPORTED_SCHEMA {Canonical source page returned an inconsistent range}}
            foreach id $ids {if {[llength [dict get $chunk values $id]]!=$page} {_sourceFail UNSUPPORTED_SCHEMA {Canonical source columns have inconsistent lengths}}}
            for {set row 0} {$row<$page} {incr row} {
                set curve [lindex [dict get $chunk values [dict get $roles curve_key]] $row]
                set label [lindex [dict get $chunk values [dict get $roles curve_name]] $row]
                set mid [dict get $context publication primary_id];set calLabel [dict get $context records $mid label]
                set selection [dict create curve_key $curve]
                if {$combined} {set mid [lindex [dict get $chunk values [dict get $roles calibration_key]] $row];set calLabel [lindex [dict get $chunk values [dict get $roles calibration_name]] $row];dict set selection calibration_key $mid}
                if {$curve eq {} || $mid ni [dict get $context publication selected_ids]} {_sourceFail INVALID_SELECTION {Canonical row has an empty curve or unpublished calibration identity}}
                set key [list $curve $mid]
                if {![dict exists $groups $key]} {lappend order $key;dict set groups $key [dict create selection $selection curve_key $curve curve_name $label calibration_key $mid calibration_name $calLabel page_row_count 0]}
                set group [dict get $groups $key]
                if {[dict get $group curve_name] ne $label || [dict get $group calibration_name] ne $calLabel} {dict set group labels_vary_within_page 1}
                dict set group label_policy first_observed_on_this_page
                dict incr group page_row_count;dict set groups $key $group
            }
        } finally {::GX::tableStreamClose $stream}
    }
    set calibration [_sourceCalibration $datasetId $context [dict get $context publication primary_id]]
    set uncertainty [_sourceUncertainty $datasetId $session]
    _sourceCheck $datasetId $expected
    set result [dict merge [dict remove $expected session] [dict create schema gxtxt.replicate.source_description.v1 api_id REPLICATE_VIEWER_API_v1 api_version 1 dataset_id $datasetId columns $roles grouping_roles [dict get $context manifest grouping_roles] publication_calibration_mode [dict get $context publication mode] publication [dict get $context publication] order_scope within_actual_joint_group groups [lmap key $order {dict get $groups $key}] calibration $calibration uncertainty $uncertainty total_rows $total start $start requested_count $count page_count $page consumed_rows $consumed next_start [expr {$start+$consumed<$total ? $start+$consumed : {}}] enumeration_complete [expr {$start+$consumed==$total}] qualifications {page_counts_only caller_must_compare_each_page_to_first_public_source_identity calibration_identity_is_recorded_not_image_byte_proof no_independence_or_covariance_inference}]]
    if {[string bytelength $result]>2097152} {_sourceFail UNSUPPORTED_SCHEMA {Source description exceeds its2MiB response bound}}
    return $result
}
proc ::GX::ReplicateViewer::_sourceDescriptor {dataset request expected} {
    set token [::GX::curveSourceOpen [dict get $expected session] $request]
    try {
        set descriptor [::GX::curveSourceDescribe $token]
        if {[dict get $descriptor row_count]<1 || [dict get $descriptor row_count]>65536 || [dict get $descriptor row_identity_kind] ne {dataset_row}} {_sourceFail UNSUPPORTED_SCHEMA {Selected source requires1..65536 canonical rows with original Dataset row identity}}
        if {![dict get [::GX::curveSourceValidateSnapshot [dict get $expected session] $descriptor] valid]} {_sourceFail SOURCE_CHANGED {Prepared source snapshot is stale}}
    } finally {::GX::curveSourceClose $token}
    _sourceCheck $dataset $expected
    return $descriptor
}
proc ::GX::ReplicateViewer::prepareDigitizerTrace {datasetId selection identities expectation} {
    if {[lsort [dict keys $expectation]] ne {session_token source_identity source_revision}} {_sourceFail INVALID_SELECTION {Preparation requires current public identity, revision and Session token}}
    set expected [_sourceCheck $datasetId $expectation];set context [_sourceProducer $datasetId $expected];set roles [dict get $context roles]
    set combined [expr {[dict get $context publication mode] eq {combined}}]
    foreach key [dict keys $selection] {if {$key ni {curve_key calibration_key}} {_sourceFail INVALID_SELECTION {Unknown Digitizer selection field}}}
    if {![dict exists $selection curve_key] || [dict get $selection curve_key] eq {} || ($combined && ![dict exists $selection calibration_key])} {_sourceFail INVALID_SELECTION {Choose an actual curve/calibration joint group}}
    set mid [expr {$combined ? [dict get $selection calibration_key] : [dict get $context publication primary_id]}]
    if {[dict exists $selection calibration_key] && [dict get $selection calibration_key] ne $mid} {_sourceFail INVALID_SELECTION {Separate publication uses its actual primary measurement only}}
    set calibration [_sourceCalibration $datasetId $context $mid]
    set allowed {physical_feature_id observation_id point_set_id calibration_realization_id source_group_id frame_id topology landmark_id direction phase_index additional_filters}
    foreach key [dict keys $identities] {if {$key ni $allowed} {_sourceFail INVALID_IDENTITY {Unknown scientific identity/preparation option}}}
    set trace [dict create dataset_id $datasetId x_variable_id [dict get $roles x] y_variable_id [dict get $roles y] curve_variable_id [dict get $roles curve_key] curve_key [dict get $selection curve_key] order_variable_id [dict get $roles point_order]]
    foreach key {physical_feature_id observation_id point_set_id calibration_realization_id source_group_id frame_id} {if {![dict exists $identities $key] || [string trim [dict get $identities $key]] eq {}} {_sourceFail INVALID_IDENTITY {Declare genuine observation/point-set/calibration/source-group/feature/frame identities explicitly}};dict set trace $key [dict get $identities $key]}
    foreach key {topology landmark_id direction phase_index} {if {[dict exists $identities $key]} {dict set trace $key [dict get $identities $key]}}
    set filters [list [dict create filter_variable_id [dict get $roles curve_key] predicate exact_equal value [dict get $selection curve_key]]]
    if {$combined} {lappend filters [dict create filter_variable_id [dict get $roles calibration_key] predicate exact_equal value $mid]}
    set selected [::GX::graphSeriesNormalizeFilters $datasetId $filters]
    set additional [::GX::datasetPublicationV2DictDefault $identities additional_filters {}]
    if {[llength $additional]>64 || [string bytelength $additional]>16384} {_sourceFail INVALID_SELECTION {Additional predicates exceed the64-filter/16KiB bound}}
    set additional [::GX::graphSeriesNormalizeFilters $datasetId $additional]
    dict set trace filters [lsort -unique [concat $selected $additional]]
    set request [dict create dataset_id $datasetId x_variable_id [dict get $roles x] y_variable_id [dict get $roles y] order_variable_id [dict get $roles point_order] filters [dict get $trace filters]]
    set descriptor [_sourceDescriptor $datasetId $request $expected]
    set uncertainty [_sourceUncertainty $datasetId [dict get $expected session]]
    dict set trace coordinate_context [::GX::datasetCoordinateRead [dict get $expected session] $datasetId]
    dict set trace source_revision [dict get $expected source_revision]
    set binding [dict create schema gxtxt.replicate.source_binding.v1 kind curve_digitizer dataset_id $datasetId source_revision [dict get $expected source_revision] source_identity [dict get $expected source_identity] roles $roles publication [dict get $context publication] selection $selection selection_filters $selected additional_filters $additional calibration_identity $calibration declared_calibration_realization_id [dict get $identities calibration_realization_id] uncertainty $uncertainty source_descriptor $descriptor qualifications {recorded_calibration_not_current_image_proof uncertainty_not_sliced_into_selected_group no_independence_or_covariance_inference}]
    dict set trace source_binding $binding
    _sourceCheck $datasetId $expected
    return [dict create schema gxtxt.replicate.prepared_trace.v1 trace $trace source_descriptor $descriptor source_binding $binding qualifications [dict get $binding qualifications] scientific_preflight required]
}
proc ::GX::ReplicateViewer::_validateSourceBinding {trace} {
    if {![dict exists $trace source_binding]} {return}
    set binding [dict get $trace source_binding]
    if {[catch {dict get $binding schema} schema] || $schema ne {gxtxt.replicate.source_binding.v1} || ![dict exists $binding kind] || [dict get $binding kind] ne {curve_digitizer}} {_sourceFail UNSUPPORTED_BINDING_VERSION {Saved source binding is preserved but unsupported for analysis or editing}}
    foreach key {dataset_id source_revision source_identity roles publication selection selection_filters additional_filters calibration_identity declared_calibration_realization_id uncertainty source_descriptor} {if {![dict exists $binding $key]} {_sourceFail UNAVAILABLE_BINDING {Saved source binding is incomplete; explicit rebind is required}}}
    set dataset [dict get $binding dataset_id];set expected [_sourceSnapshot $dataset]
    if {[dict get $trace dataset_id] ne $dataset || [dict get $trace source_revision] ne [dict get $binding source_revision]} {_sourceFail SOURCE_CHANGED {Trace and durable source revision disagree}}
    _sourceCheck $dataset [dict merge $expected [dict create source_revision [dict get $binding source_revision] source_identity [dict get $binding source_identity]]]
    set identities {}
    foreach key {physical_feature_id observation_id point_set_id calibration_realization_id source_group_id frame_id topology landmark_id direction phase_index} {if {[dict exists $trace $key]} {dict set identities $key [dict get $trace $key]}}
    dict set identities additional_filters [dict get $binding additional_filters]
    set fresh [prepareDigitizerTrace $dataset [dict get $binding selection] $identities [dict remove $expected session]]
    set actual [dict get $fresh source_binding]
    foreach key {roles publication selection_filters additional_filters calibration_identity declared_calibration_realization_id uncertainty} {if {[dict get $actual $key] ne [dict get $binding $key]} {_sourceFail SOURCE_CHANGED "Saved $key binding no longer matches its public owner; explicit rebind is required"}}
    foreach key {dataset_id x_variable_id y_variable_id curve_variable_id curve_key order_variable_id filters coordinate_context source_revision} {if {![dict exists $trace $key] || [dict get $trace $key] ne [dict get $fresh trace $key]} {_sourceFail SOURCE_CHANGED "Trace $key differs from the prepared scientific recipe"}}
    set saved [dict get $binding source_descriptor]
    if {![dict get [::GX::curveSourceValidateSnapshot [dict get $expected session] $saved] valid]} {_sourceFail SOURCE_CHANGED {Prepared full source descriptor changed}}
    foreach field {api_id api_version source_id source_kind row_identity_kind request row_count variables source_identities display_is_scientific_data} {
        if {![dict exists $saved $field] || [dict get $saved $field] ne [dict get $fresh source_descriptor $field]} {_sourceFail SOURCE_CHANGED "Saved descriptor $field differs from its current full scientific recipe"}
    }
    _sourceCheck $dataset $expected
}
proc ::GX::ReplicateViewer::_validateRequestBindings {request} {foreach trace [dict get $request traces] {_validateSourceBinding $trace}}
proc ::GX::ReplicateViewer::_hasSourceBinding {request} {foreach trace [dict get $request traces] {if {[dict exists $trace source_binding]} {return 1}};return 0}
proc ::GX::ReplicateViewer::_boundHistoryLatest {w} {
    set record [::GX::scientificHistoryViewerRecord $w]
    if {![::GX::scientificHistoryViewerEditable $w] || [dict get $record cursor]!=[llength [dict get $record steps]]} {_sourceFail UNAVAILABLE_BINDING {Return to the latest History checkpoint before editing a bound source}}
    return $record
}

# Ordinary optional source-selection dialog. Prepared recipes are inert until Accept.
proc ::GX::ReplicateViewer::_digitizerValues {w} {
    variable input
    set values {}
    foreach key {physical_feature_id observation_id point_set_id calibration_realization_id source_group_id frame_id topology landmark_id direction phase_index} {dict set values $key $input($w,dg_$key)}
    return $values
}
proc ::GX::ReplicateViewer::digitizerDialog {w {index {}}} {
    variable state;variable input
    guard $w
    if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}}
    if {[winfo exists $w.source]} {error {Finish or cancel the current source dialog first}}
    set d $w.digitizer
    if {[winfo exists $d]} {raise $d;return}
    set capabilities [sourceCapabilities]
    if {![dict get $capabilities producer declared] || ![dict get $capabilities producer enabled]} {error {The optional Curve Digitizer public source APIs are unavailable or disabled; generic sources remain available}}
    foreach key {dg_original dg_index dg_first dg_dataset dg_page dg_groups dg_selection dg_candidate dg_prepared_values dg_prepared_dataset dg_prepared_selection dg_initial_values} {unset -nocomplain state($w,$key)}
    set ids {};set session [::GX::sessionInspectionCurrentSession]
    foreach item [dict get [::GX::datasetCatalogSnapshot] datasets] {
        set id [dict get $item dataset_id]
        if {![catch {set md [::GX::datasetMetadataRead $session $id]}] && [dict exists $md curve_digitizer.plugin_id] && [dict get $md curve_digitizer.plugin_id] eq {viewer.curve_digitizer}} {lappend ids $id}
    }
    set original {}
    if {$index ne {}} {
        set original [lindex [dict get $state($w,payload) request traces] $index]
        set state($w,dg_original) $original;set state($w,dg_index) $index
    }
    if {$ids eq {} && $original eq {}} {error {No published Curve Digitizer Dataset is available in this Session}}
    ::GX::uiFieldDialogCreate $d $w {Published Digitizer source — prepare and review}
    try {
        set input($w,dg_dataset) [expr {$original eq {} ? [lindex $ids 0] : [dict get $original dataset_id]}]
        foreach {key label default} [list physical_feature_id {Physical feature ID} {} observation_id {Independent observation ID} {} point_set_id {Original point-set ID} {} calibration_realization_id {Study calibration realization ID} {} source_group_id {Independent source group ID} {} frame_id {Common physical frame ID} $input($w,frame) topology Topology open landmark_id {Corresponding physical start landmark} start direction Direction forward phase_index {Closed start source index (0-based)} 0] {
            set input($w,dg_$key) [expr {[dict exists $original $key] ? [dict get $original $key] : $default}]
        }
        set state($w,dg_initial_values) [_digitizerValues $w]
        ttk::label $d.datasetLabel -text Dataset
        ttk::combobox $d.dataset -state readonly -values $ids -textvariable [namespace current]::input($w,dg_dataset)
        ::GX::uiFieldSelectorWithinViewer $d.dataset $d
        grid $d.datasetLabel -row 0 -column 0 -sticky w -padx 6 -pady 3;grid $d.dataset -row 0 -column 1 -sticky ew -padx 6 -pady 3
        ttk::label $d.groupLabel -text {Actual curve / calibration pair}
        ttk::combobox $d.group -state readonly -textvariable [namespace current]::input($w,dg_group)
        ::GX::uiFieldSelectorWithinViewer $d.group $d
        grid $d.groupLabel -row 1 -column 0 -sticky w -padx 6 -pady 3;grid $d.group -row 1 -column 1 -sticky ew -padx 6 -pady 3
        ttk::frame $d.navigation
        foreach {id label command} [list previous {Previous page} [list [namespace current]::safe $w digitizerPageStep -1] next {Next page} [list [namespace current]::safe $w digitizerPageStep 1] refresh {Re-read source / explicit rebind} [list [namespace current]::safe $w digitizerPage 0 1]] {
            ttk::button $d.navigation.$id -text $label -command $command;pack $d.navigation.$id -side left -padx 3
        }
        grid $d.navigation -row 2 -column 0 -columnspan 2 -sticky ew -padx 6 -pady 3
        ttk::label $d.summary -text {No prepared source.} -wraplength 560 -justify left
        grid $d.summary -row 3 -column 0 -columnspan 2 -sticky ew -padx 6 -pady 5
        set row 4
        foreach {key label} {physical_feature_id {Physical feature ID} observation_id {Independent observation ID} point_set_id {Original point-set ID} calibration_realization_id {Study calibration realization ID} source_group_id {Independent source group ID} frame_id {Common physical frame ID} topology Topology landmark_id {Corresponding physical start landmark} direction Direction phase_index {Closed start source index (0-based)}} {
            ttk::label $d.l$key -text $label
            if {$key in {topology direction}} {
                ttk::combobox $d.$key -state readonly -values [expr {$key eq {topology} ? {open closed} : {forward reverse}}] -textvariable [namespace current]::input($w,dg_$key)
                ::GX::uiFieldSelectorWithinViewer $d.$key $d
            } else {ttk::entry $d.$key -textvariable [namespace current]::input($w,dg_$key)}
            grid $d.l$key -row $row -column 0 -sticky w -padx 6 -pady 2;grid $d.$key -row $row -column 1 -sticky ew -padx 6 -pady 2;incr row
        }
        ttk::label $d.notice -wraplength 560 -justify left -text {Declare genuine observation and point-set identities. Repeated calibrations of the same points share them; they are sensitivity, not independent repeats. Page counts are not full-curve totals.}
        grid $d.notice -row $row -column 0 -columnspan 2 -sticky ew -padx 6 -pady 5;incr row
        ttk::frame $d.actions
        ttk::button $d.actions.prepare -text {Prepare selected source} -command [list [namespace current]::safe $w digitizerPrepare]
        ttk::button $d.actions.accept -text [expr {$original eq {} ? {Add prepared observation} : {Accept prepared edit / rebind}}] -state disabled -command [list [namespace current]::safe $w digitizerAccept]
        ttk::button $d.actions.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $d]
        pack $d.actions.prepare $d.actions.accept $d.actions.cancel -side left -padx 3
        grid $d.actions -row $row -column 0 -columnspan 2 -sticky ew -padx 6 -pady 7
        grid columnconfigure $d 1 -weight 1
        bind $d.dataset <<ComboboxSelected>> [list [namespace current]::safe $w digitizerPage 0]
        bind $d.group <<ComboboxSelected>> [list [namespace current]::safe $w digitizerGroupChanged]
        if {$original ne {}} {set state($w,dg_selection) [dict get $original source_binding selection]}
        # An unavailable/stale source leaves the old recipe intact for Cancel or rebind.
        if {[catch {digitizerPage $w 0} message]} {$d.summary configure -text "Source inspection refused: $message. The saved recipe is unchanged."}
        ::GX::uiFieldDialogPresent $d $d.dataset
    } on error {message options} {catch {::GX::uiFieldDialogClose $d};catch {destroy $d};return -options $options $message}
}
proc ::GX::ReplicateViewer::digitizerPageStep {w direction} {
    variable state
    if {![info exists state($w,dg_page)]} {error {Resolve a current source page first}}
    set page $state($w,dg_page)
    if {$direction>0} {set start [dict get $page next_start];if {$start eq {}} return} else {set start [expr {max(0,[dict get $page start]-256)}]}
    digitizerPage $w $start
}
proc ::GX::ReplicateViewer::digitizerPage {w start {fresh 0}} {
    variable state;variable input
    guard $w
    set d $w.digitizer;set dataset $input($w,dg_dataset)
    unset -nocomplain state($w,dg_candidate)
    $d.actions.accept state disabled
    set changed [expr {![info exists state($w,dg_dataset)] || $state($w,dg_dataset) ne $dataset}]
    if {$changed || $fresh} {unset -nocomplain state($w,dg_first)}
    if {$changed && [info exists state($w,dg_dataset)]} {foreach key {physical_feature_id observation_id point_set_id source_group_id} {set input($w,dg_$key) {}};unset -nocomplain state($w,dg_selection)}
    set options [dict create start $start count 256]
    if {[info exists state($w,dg_first)]} {dict set options expected_revision [dict get $state($w,dg_first) source_revision];dict set options expected_session_token [dict get $state($w,dg_first) session_token]}
    unset -nocomplain state($w,dg_page) state($w,dg_groups)
    try {
        set page [describeDigitizerSource $dataset $options]
        guard $w
        if {$dataset ne $input($w,dg_dataset)} {_sourceFail SOURCE_CHANGED {Dataset selection changed during page discovery}}
        if {[info exists state($w,dg_first)]} {
            set first $state($w,dg_first)
            if {![_sourceDictEqual [dict get $first source_identity] [dict get $page source_identity]] || [dict get $first source_revision] ne [dict get $page source_revision] || [dict get $first session_token] ne [dict get $page session_token]} {_sourceFail SOURCE_CHANGED {Page identity differs from the first accepted page}}
        } else {
            if {[info exists state($w,dg_original)]} {
                set savedBinding [dict get $state($w,dg_original) source_binding]
                if {$dataset ne [dict get $state($w,dg_original) dataset_id] || [dict get $savedBinding source_revision] ne [dict get $page source_revision] || ![_sourceDictEqual [dict get $savedBinding source_identity] [dict get $page source_identity]]} {foreach key {physical_feature_id observation_id point_set_id source_group_id} {set input($w,dg_$key) {}}}
            }
            set state($w,dg_first) $page
        }
        set state($w,dg_dataset) $dataset;set state($w,dg_page) $page
        set groups [dict get $page groups];set selected 0
        if {[info exists state($w,dg_selection)]} {
            set found -1;set n 0
            foreach group $groups {if {[_sourceDictEqual [dict get $group selection] $state($w,dg_selection)]} {set found $n};incr n}
            if {$found>=0} {set selected $found} else {
                # Preserve the current choice across pages; never replace it with the original edit choice.
                set choice $state($w,dg_selection)
                set mid [expr {[dict exists $choice calibration_key] ? [dict get $choice calibration_key] : [dict get $page publication primary_id]}]
                set saved [dict create selection $choice curve_name {Current choice outside this page — requires preparation} calibration_name $mid calibration_key $mid page_row_count 0]
                set groups [linsert $groups 0 $saved];set selected 0
            }
        }
        set state($w,dg_groups) $groups
        set labels [lmap group $groups {format {%s / %s · curve ID %s · measurement ID %s · %s rows on this page} [string range [dict get $group curve_name] 0 47] [string range [dict get $group calibration_name] 0 47] [dict get $group selection curve_key] [dict get $group calibration_key] [dict get $group page_row_count]}]
        $d.group configure -values $labels
        $d.navigation.previous state [expr {$start>0 ? {!disabled} : {disabled}}]
        $d.navigation.next state [expr {[dict get $page next_start] ne {} ? {!disabled} : {disabled}}]
        if {$groups eq {}} {$d.actions.prepare state disabled;$d.summary configure -text {This page has no groups. No source is prepared.};return}
        $d.group current $selected;$d.actions.prepare state !disabled
        digitizerGroupChanged $w
        $d.summary configure -text "Canonical rows $start + [dict get $page consumed_rows] of [dict get $page total_rows]. Labels are first-observed on this page. Choose genuine identities, then Prepare and review. Uncertainty: [dict get $page uncertainty status]."
    } on error {message options} {
        unset -nocomplain state($w,dg_page) state($w,dg_groups) state($w,dg_candidate)
        $d.group configure -values {};$d.actions.prepare state disabled;$d.actions.accept state disabled
        $d.summary configure -text "Source inspection refused: $message. No recipe was changed."
        return -options $options $message
    }
}
proc ::GX::ReplicateViewer::digitizerGroupChanged {w} {
    variable state;variable input
    set d $w.digitizer;set index [$d.group current]
    if {![info exists state($w,dg_groups)] || $index<0 || $index>=[llength $state($w,dg_groups)]} {error {Choose an actual source group}}
    set group [lindex $state($w,dg_groups) $index];set selection [dict get $group selection]
    if {[info exists state($w,dg_selection)] && [dict get $state($w,dg_selection) curve_key] ne [dict get $selection curve_key]} {foreach key {physical_feature_id observation_id point_set_id source_group_id} {set input($w,dg_$key) {}}}
    set same [expr {[info exists state($w,dg_selection)] && [_sourceDictEqual $state($w,dg_selection) $selection]}]
    set state($w,dg_selection) $selection
    if {!$same || $input($w,dg_calibration_realization_id) eq {}} {set input($w,dg_calibration_realization_id) [dict get $group calibration_key]}
    unset -nocomplain state($w,dg_candidate);$d.actions.accept state disabled
    $d.summary configure -text {Selection changed. Prepare this source before Accept.}
}
proc ::GX::ReplicateViewer::digitizerPrepare {w} {
    variable state;variable input
    guard $w
    set d $w.digitizer
    unset -nocomplain state($w,dg_candidate);$d.actions.accept state disabled
    $d.summary configure -text {No source is prepared. Preparation must succeed before Accept.}
    if {![info exists state($w,dg_first)] || ![info exists state($w,dg_page)] || ![info exists state($w,dg_selection)]} {error {Inspect a current Dataset page and choose a group first}}
    set dataset $input($w,dg_dataset);set values [_digitizerValues $w];set identities $values;set selection $state($w,dg_selection)
    set additional {};set original {}
    if {[info exists state($w,dg_original)]} {
        set original $state($w,dg_original);set binding [dict get $original source_binding]
        set additional [dict get $binding additional_filters]
        set rebound [expr {$dataset ne [dict get $original dataset_id] || ![_sourceDictEqual $selection [dict get $binding selection]] || [dict get $binding source_revision] ne [dict get $state($w,dg_first) source_revision] || ![_sourceDictEqual [dict get $binding source_identity] [dict get $state($w,dg_first) source_identity]]}]
        if {$rebound} {
            if {$additional ne {}} {error {Rebind with additional generic predicates requires an explicit reviewed replacement through source preparation; no old predicate was copied}}
            foreach key [dict keys $binding] {if {$key ni {schema kind dataset_id source_revision source_identity roles publication selection selection_filters additional_filters calibration_identity declared_calibration_realization_id uncertainty source_descriptor qualifications}} {error {Source rebind with unknown binding extensions requires their owner review; no extension was discarded}}}
            foreach key [dict keys $original] {if {$key ni {dataset_id x_variable_id y_variable_id curve_variable_id order_variable_id curve_key physical_feature_id observation_id point_set_id calibration_realization_id source_group_id frame_id topology landmark_id direction phase_index filters coordinate_context source_revision source_binding}} {error {Source rebind with unknown retained metadata requires its owner review; the original recipe is unchanged}}}
        } else {
            foreach key {topology landmark_id direction phase_index} {if {![dict exists $original $key] && [dict get $values $key] eq [expr {$key eq {topology} ? {open} : $key eq {landmark_id} ? {start} : $key eq {direction} ? {forward} : {0}}]} {dict unset identities $key}}
        }
    }
    dict set identities additional_filters $additional
    set first $state($w,dg_first)
    set expectation [dict create source_revision [dict get $first source_revision] source_identity [dict get $first source_identity] session_token [dict get $first session_token]]
    set prepared [prepareDigitizerTrace $dataset $selection $identities $expectation]
    guard $w
    if {$dataset ne $input($w,dg_dataset) || ![_sourceDictEqual $values [_digitizerValues $w]] || ![_sourceDictEqual $selection $state($w,dg_selection)]} {_sourceFail SOURCE_CHANGED {Source choice or declarations changed during preparation}}
    set trace [dict get $prepared trace]
    if {$original ne {}} {
        set merged $original
        dict for {key value} $trace {dict set merged $key $value}
        # Preserve unknown binding extensions only for unchanged source selection.
        if {!$rebound} {set binding [dict get $original source_binding];dict for {key value} [dict get $trace source_binding] {dict set binding $key $value};dict set merged source_binding $binding}
        set trace $merged
        # Revalidate before retaining the exact original representation for unchanged declarations.
        if {!$rebound && [_sourceDictEqual $values $state($w,dg_initial_values)]} {_validateSourceBinding $original;set trace $original}
    }
    _sourceCheck $dataset $expectation
    guard $w
    if {![winfo exists $d] || $state($w,busy) || $dataset ne $input($w,dg_dataset) || ![_sourceDictEqual $values [_digitizerValues $w]] || ![info exists state($w,dg_selection)] || ![_sourceDictEqual $selection $state($w,dg_selection)]} {_sourceFail SOURCE_CHANGED {Source dialog changed during final preparation validation}}
    set state($w,dg_candidate) $trace;set state($w,dg_prepared_values) $values;set state($w,dg_prepared_dataset) $dataset;set state($w,dg_prepared_selection) $selection
    $d.summary configure -text "Prepared [dict get $prepared source_descriptor row_count] original source rows. Measurement binding retained; no analysis or publication. Uncertainty [dict get $prepared source_binding uncertainty status], whole-Dataset scope; no covariance/weights inferred. Review before Accept."
    $d.actions.accept state !disabled
}
proc ::GX::ReplicateViewer::digitizerAccept {w} {
    variable state;variable input
    guard $w
    if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}}
    if {![info exists state($w,dg_candidate)] || $input($w,dg_dataset) ne $state($w,dg_prepared_dataset) || ![_sourceDictEqual [_digitizerValues $w] $state($w,dg_prepared_values)] || ![_sourceDictEqual $state($w,dg_selection) $state($w,dg_prepared_selection)]} {error {Source declarations changed; Prepare the source again before Accept}}
    set payload $state($w,payload);set expected [dict remove $payload history];set traces [dict get $payload request traces];set trace $state($w,dg_candidate)
    if {[info exists state($w,dg_original)]} {
        set index $state($w,dg_index)
        if {$index<0 || $index>=[llength $traces] || [lindex $traces $index] ne $state($w,dg_original)} {_sourceFail SOURCE_CHANGED {The original source recipe changed while the dialog was open}}
        if {$trace eq $state($w,dg_original)} {
            set first $state($w,dg_first)
            set expectation [dict create source_revision [dict get $first source_revision] source_identity [dict get $first source_identity] session_token [dict get $first session_token]]
            _validateSourceBinding $trace
            _sourceCheck [dict get $trace dataset_id] $expectation
            guard $w
            if {![winfo exists $w.digitizer] || $state($w,busy) || ![info exists state($w,dg_candidate)] || $state($w,dg_candidate) ne $trace || $input($w,dg_dataset) ne $state($w,dg_prepared_dataset) || ![_sourceDictEqual [_digitizerValues $w] $state($w,dg_prepared_values)] || ![info exists state($w,dg_selection)] || ![_sourceDictEqual $state($w,dg_selection) $state($w,dg_prepared_selection)]} {_sourceFail SOURCE_CHANGED {Source dialog changed while accepting its unchanged recipe}}
            set currentTraces [dict get $state($w,payload) request traces]
            if {![info exists state($w,dg_original)] || $state($w,dg_original) ne $trace || ![info exists state($w,dg_index)] || $state($w,dg_index)!=$index || $index<0 || $index>=[llength $currentTraces] || [lindex $currentTraces $index] ne $trace} {_sourceFail SOURCE_CHANGED {Original recipe changed while validating the unchanged edit}}
            ::GX::uiFieldDialogClose $w.digitizer;return
        }
        set traces [lreplace $traces $index $index $trace];set description {Explicitly prepare/rebind Digitizer observation}
    } else {lappend traces $trace;set description {Add prepared Digitizer observation}}
    if {$input($w,frame) eq {} || [dict get $trace frame_id] ne $input($w,frame)} {error {Declare the same common physical frame in the study and prepared source before Accept}}
    dict set payload request traces $traces
    if {![change $w $payload $description $expected]} return
    ::GX::uiFieldDialogClose $w.digitizer
}
