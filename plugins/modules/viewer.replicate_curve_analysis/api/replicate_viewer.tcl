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
proc ::GX::ReplicateViewer::restore {w payload} {variable state;unset -nocomplain state($w,ticket);set state($w,payload) $payload;refresh $w}
proc ::GX::ReplicateViewer::historyCommit {w record} {variable state;dict set state($w,payload) history $record}
proc ::GX::ReplicateViewer::historyValidate {record} {if {[dict get $record workbench_id] ne "viewer.replicate_curve_analysis"} {error {History belongs to another Viewer}};return 1}
proc ::GX::ReplicateViewer::historyCapture {w} {return [::GX::scientificHistoryViewerRecord $w]}
proc ::GX::ReplicateViewer::historyReplay {context record} {error {Navigate History in the owning Replicate Workspace}}
::GX::scientificRecipeHostRegister viewer.replicate_curve_analysis [dict create capture ::GX::ReplicateViewer::historyCapture validate ::GX::ReplicateViewer::historyValidate replay ::GX::ReplicateViewer::historyReplay]
proc ::GX::ReplicateViewer::change {w payload description} {
    variable state
    guard $w
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    if {[dict get $payload request] ne [dict get $state($w,payload) request]} {
        set payload [dict remove $payload result result_resource published_dataset plot_ref view_axes]
        unset -nocomplain state($w,ticket)
    }
    set state($w,payload) $payload
    ::GX::scientificHistoryViewerChanged $w $description
    refresh $w
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
    set commands [dict create sources {label {Add source…} default Ctrl+o} analyze {label Analyze default F5} cancel {label Cancel} publish {label {Publish results}} graph {label {Publish Graph}} save {label Save default Ctrl+s} undo {label Undo default Ctrl+z} redo {label Redo default Ctrl+y} fit {label {Fit all}} edit_source {label {Edit selected source…}} remove_source {label {Remove selected source}} zoom_in {label {Zoom in}} zoom_out {label {Zoom out}}]
    ::GX::viewerCommandCatalogRegister viewer.replicate_curve_analysis $commands
    set handlers {}
    foreach {id method args} {sources sourceDialog {} analyze analyze {} cancel cancel {} publish publish {} graph publishGraph {} save save {} undo navigate undo redo navigate redo fit fit {} edit_source editSource {} remove_source removeSource {} zoom_in zoom 1.25 zoom_out zoom 0.8} {dict set handlers $id [dict create command [list [namespace current]::safe $w $method {*}$args] enabled [list [namespace current]::enabled $w $id]]}
    set manifest [dict create schema gxtxt.viewer_gui_manifest.v1 viewer_id viewer.replicate_curve_analysis provider_id replicate_consensus window $w title {Replicate / Consensus Curves} handlers $handlers guard [list [namespace current]::guard $w] workspace [callbacks $w] history [dict create capture [list [namespace current]::capture $w] restore [list [namespace current]::restore $w] commit [list [namespace current]::historyCommit $w] guard [list [namespace current]::guard $w]]]
    if {[dict exists $payload history]} {dict set manifest history_record [dict get $payload history]}
    dict set manifest canvas {api_id PLOT_DATASET_API_v4}
    dict set manifest toolbar_actions {sources analyze cancel undo redo fit zoom_in zoom_out save}
    dict set manifest menus [list [dict create label Sources actions {sources edit_source remove_source}] [dict create label Study actions {analyze cancel - publish graph}] [dict create label Edit actions {undo redo}] [dict create label View actions {fit zoom_in zoom_out}]]
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
        ttk::label $p.l$key -text $label;ttk::combobox $p.$key -state readonly -values $values -textvariable [namespace current]::input($w,$key)
        pack $p.l$key $p.$key -in $study -fill x -pady 3
        ::GX::uiFieldSelectorWithinViewer $p.$key $w
    }
    foreach {key label default} {analysis_id {Unique analysis ID} {} frame {Common physical frame ID} {} x_unit {X reference unit} mm y_unit {Y reference unit} mm} {
        set value $default
        if {$key eq "analysis_id"} {set value [dict get $payload request analysis_id]} elseif {$key eq "frame"} {set value [dict get $payload request reference_frame id]} else {set value [dict get $payload request reference_frame $key]}
        set input($w,$key) $value;ttk::label $p.l$key -text $label;ttk::entry $p.$key -textvariable [namespace current]::input($w,$key);pack $p.l$key $p.$key -in [expr {$key eq "analysis_id"?$study:$frame}] -fill x -pady 2
    }
    set input($w,verified) [expr {[dict get $payload request reference_frame declaration] eq "explicit_user_verified"}]
    ttk::checkbutton $p.verified -text {I verified a common physical frame} -variable [namespace current]::input($w,verified);pack $p.verified -in $frame -anchor w -pady 5
    listbox $p.sources -height 6 -exportselection 0;pack $p.sources -in $sources -fill x
    ::GX::viewerGuiSelectionAttach $w $p.sources
    ::GX::viewerGuiContextMount $w $p.sources
    ttk::button $p.remove -text {Remove selected source} -command [list ::GX::viewerCommandInvoke $w remove_source];pack $p.remove -in $sources -fill x -pady 3
    ttk::label $p.assumptions -wraplength 250 -text {XY paths require an explicit common start landmark, direction and normalized physical source arc-length correspondence. Shared calibrations are sensitivity studies. Missing uncertainty is not zero.};pack $p.assumptions -fill x -pady 6
    text $p.report -height 10 -width 28 -wrap word -state disabled;pack $p.report -fill x
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
}
proc ::GX::ReplicateViewer::sourceDialog {w} {
    variable state;if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}};unset -nocomplain state($w,editingSource)
    variable state;variable input
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
    variable input
    set schema [::GX::tableStreamCompatibleSchema $::GX::currentSession $input($w,source_dataset_id)]
    set variables [lmap v $schema {dict get $v variable_id}]
    foreach key {x_variable_id y_variable_id curve_variable_id order_variable_id} {$w.source.$key configure -values [linsert $variables 0 {}]}
    set input($w,source_x_variable_id) [lindex $variables 0];set input($w,source_y_variable_id) [lindex $variables 1]
    foreach variable $schema {
        set role [dict get $variable semantic_role]
        if {$role eq "independent"} {set input($w,source_x_variable_id) [dict get $variable variable_id]}
        if {$role eq "measured"} {set input($w,source_y_variable_id) [dict get $variable variable_id]}
    }
}
proc ::GX::ReplicateViewer::sourceAccept {w} {variable state;variable input;if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}};if {$input($w,frame) eq {}} {error {Declare the common physical frame before adding a source}};set trace {};foreach key {dataset_id x_variable_id y_variable_id curve_variable_id order_variable_id physical_feature_id curve_key observation_id point_set_id calibration_realization_id source_group_id topology landmark_id direction phase_index} {if {$input($w,source_$key) ne {}} {dict set trace $key $input($w,source_$key)}};dict set trace frame_id $input($w,frame);set payload $state($w,payload);set traces [dict get $payload request traces];if {[info exists state($w,editingSource)]} {set traces [lreplace $traces $state($w,editingSource) $state($w,editingSource) $trace]} else {lappend traces $trace};dict set payload request traces $traces;change $w $payload {Add scientific source observation};destroy $w.source}
proc ::GX::ReplicateViewer::removeSource {w} {variable state;if {$state($w,busy)} {error {Cancel or finish the current study before editing sources}};set selected [lindex [$w.body.inspector.scroll.content.sources curselection] 0];if {$selected eq {}} return;set payload $state($w,payload);dict set payload request traces [lreplace [dict get $payload request traces] $selected $selected];change $w $payload {Remove selected source}}
proc ::GX::ReplicateViewer::analyze {w} {
    variable state;variable input
    set request [dict get $state($w,payload) request]
    foreach key {analysis_id method design} {dict set request $key $input($w,$key)}
    dict set request reference_frame [dict create id $input($w,frame) x_unit $input($w,x_unit) y_unit $input($w,y_unit) declaration [expr {$input($w,verified)?"explicit_user_verified":"unverified"}]]
    if {[dict get $request method] eq "xy_path"} {dict set request correspondence anchored_source_arclength}
    set request [::GX::Replicate::preflight $request]
    set payload $state($w,payload);dict set payload request $request;change $w $payload {Configure scientific study}
    set state($w,ticket) [::GX::Replicate::submit $request];set state($w,busy) 1
    ::GX::viewerCommandToolbarRefresh $w
    poll $w
}
proc ::GX::ReplicateViewer::poll {w} {
    variable state
    if {![winfo exists $w] || ![info exists state($w,ticket)]} return
    if {[catch {guard $w;set job [::GX::Replicate::status $state($w,ticket)]} error]} {$w.footer.status configure -text $error;return}
    $w.footer.status configure -text "Replicate scientific Job: [dict get $job state]"
    if {[dict get $job state] ni {COMPLETED FAILED CANCELLED CANCELED}} {set state($w,timer) [after 300 [list [namespace current]::poll $w]];return}
    set state($w,busy) 0
    if {[dict get $job state] eq "COMPLETED"} {
        if {[catch {if {[dict get $state($w,ticket) request] ne [dict get $state($w,payload) request]} {error {Study configuration changed; the completed Job cannot replace it}};set result [::GX::Replicate::result $state($w,ticket)]} error]} {$w.footer.status configure -text $error} else {if {[catch {set payload [storeResult $w $state($w,payload) $result];change $w $payload {Adopt completed scientific study}} message]} {$w.footer.status configure -text $message}}
    }
    ::GX::viewerCommandToolbarRefresh $w
}
proc ::GX::ReplicateViewer::cancel {w} {variable state;if {[info exists state($w,ticket)]} {::GX::Replicate::cancel $state($w,ticket)}}
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
proc ::GX::ReplicateViewer::publish {w} {variable state;set result [::GX::Replicate::publish $state($w,ticket)];dict set state($w,payload) published_dataset [dict get $result dataset_id];$w.footer.status configure -text "Published canonical study Dataset: [dict get $result dataset_id]";return $result}
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
    sourceDialog $w;set state($w,editingSource) $index
    dict for {key value} $trace {if {[info exists input($w,source_$key)]} {set input($w,source_$key) $value}}
}
