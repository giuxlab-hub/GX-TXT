# SPDX-License-Identifier: GPL-3.0-or-later
# Versioned inert examples; existing public constructors own every rendered component.
namespace eval ::GX::ComponentDemo {variable specs {};variable trace {};variable selected;variable variant standalone;variable state default}
proc ::GX::viewerGuiComponentDemoApiInfo {} {return [dict create api_id VIEWER_COMPONENT_DEMO_API_v1 api_version 1 operations {catalog register open reset inspect} fixture_version 1 provenance demo_fixture domain_handlers 0 publication 0 modes {Design Demo Runtime_Test}]}
proc ::GX::viewerGuiComponentDemoRegister {type spec} {
    if {![dict exists [viewerGuiComponentCapabilities] $type]} {error {A demo requires an existing public component capability}}
    foreach key [dict keys $spec] {if {$key ni {properties instructions states}} {error {Demo specifications are inert properties/instructions/states only}}}
    if {[string bytelength $spec]>16384||![dict exists $spec properties]||![dict exists $spec instructions]} {error {Invalid bounded component demo specification}}
    if {![dict exists $spec states]} {dict set spec states {default}}
    set states [dict get $spec states]
    if {![llength $states]||[llength $states]>5} {error {A demo declares one to five supported sample states}}
    foreach state $states {if {$state ni {default selected disabled empty invalid}} {error {Unknown inert demo sample state}}}
    dict set ::GX::ComponentDemo::specs $type $spec
}
proc ::GX::_viewerGuiComponentDemoDefaults {} {
    if {[dict size $::GX::ComponentDemo::specs]} return
    foreach {type properties instructions} {
        panel {title {Synthetic instrument panel}} {A native panel contains a descriptive child. Compare standalone and composite layouts.}
        section {title {Synthetic sensor settings} padding 10} {A native labelled inspector section. Resize to see its normal layout constraints.}
        splitter {orientation horizontal} {Drag the native sash between two real child panels.}
        tabs {} {Select Acquisition and Summary tabs with mouse or Ctrl+Tab.}
        tab {title {Synthetic acquisition}} {A tab requires a real tabs parent. Select its sibling and return.}
        entry {default {Synthetic sample A} width 28} {Type a sample label. Return or focus change emits the component's changed contract.}
        combobox {default {Sensor A} choices {{Sensor A} {Sensor B} {Reference sensor}} width 24} {Choose a synthetic sensor with mouse or arrow keys. No Dataset lookup occurs.}
        checkbutton {label {Show synthetic calibration} default 1} {Toggle with pointer or Space; the local boolean changes only this demo.}
        field {label {Synthetic temperature (demo units)} datatype number default 23.5 min -50 max 100} {Enter a bounded value. Invalid input stays visible and its public validator refuses commit.}
        toggle {label {Synthetic acquisition enabled} default 1} {Toggle with pointer or Space. There is no real acquisition handler.}
        choice {label {Synthetic range} default Medium choices {Low Medium High}} {Choose Low, Medium or High. The value belongs only to this fixture.}
        dataset_selector {label {Synthetic source choices · no catalogue access}} {Select a demo-only label. These are not Dataset IDs and no scientific catalogue is queried.}
        label {text {DEMO · synthetic laboratory instrument} wraplength 420} {Display-only native label; no interactive event is declared.}
        status {text {DEMO · instrument ready (simulated)}} {Display-only status, not a scientific PASS or actual acquisition state.}
        progress {maximum 100} {Use the demo Advance command to move 25 percent at a time. No Job or timer is started.}
        log {text {DEMO / synthetic content
Instrument connected (simulated)
Calibration request queued (simulated)
No scientific action was executed.} height 8 width 45} {Read-only log with synthetic lines. Native text selection/copy remains available.}
        list {items {{Synthetic sample A} {Synthetic sample B} {Reference material} {Blank control}} height 7 selectmode browse} {Select rows with pointer or arrows; inspect the actual changed trace.}
        table {columns {Sample Value Unit}} {Read-only table. Select a row; no Worksheet editing or formula capability is implied.}
        action {label {Advance synthetic state} action demo_advance tooltip {Changes only the demo fixture}} {Invoke with pointer, Tab/Space or the menu. Only synthetic local state changes.}
        command_toolbar {actions {demo_advance demo_reset}} {Try the real ViewerCommands toolbar. Inspect state transitions; no domain handlers are connected.}
        menu {label {Demo commands} actions {demo_advance - demo_reset}} {Open the real menu and invoke Advance or Reset. No private menu stand-in.}
        context_menu {actions {demo_advance - demo_reset}} {Right-click the real Viewer canvas for its public command menu.}
        help {} {The public documentation owner supplies an inert Help sample and opens the actual Builder manual on request.}
        workspace {} {Sample Workspace controls are inert: no Session, Workspace registration or save occurs. Save is visibly disabled.}
        history {} {The History owner supplies an explicitly simulated local strip. Change Description/History and select a sample row. No canonical History receipt exists.}
        native2d {title {Synthetic Native2D interaction}} {Select/Move the orange shape by a native vertex. Drag changes RAM geometry; Pan, wheel zoom, Fit and Escape are separate presentation operations. Reset restores deterministic geometry.}
        plot {title {Synthetic native Plot}} {Real Plot v4/Cairo surface over a bounded RAM model. Wheel zoom, middle drag pan, double-click fit; no canonical identity or source file.}
        native3d {title {Synthetic Native3D cube} width 560 height 360 projection perspective axes_world 1 navigation_cube_visible 1 demo 1} {Real independent CORE Native3D v2 component. Drag orbit, Shift-drag pan, wheel zoom, Fit/Reset/Front/Top; no scientific Session or Dataset.}
    } {
        set states {default}
        if {$type in {entry combobox checkbutton field toggle choice dataset_selector list table action tabs}} {lappend states selected}
        if {$type in {entry combobox checkbutton field toggle choice dataset_selector action}} {lappend states disabled}
        if {$type in {entry combobox field choice dataset_selector list table}} {lappend states empty}
        if {$type eq {field}} {lappend states invalid}
        viewerGuiComponentDemoRegister $type [dict create properties $properties instructions $instructions states $states]
    }
}
proc ::GX::viewerGuiComponentDemoCatalog {} {
    _viewerGuiComponentDemoDefaults
    set result {}
    dict for {type cap} [viewerGuiComponentCapabilities] {
        set row [dict create capability $cap fixture_version 1 provenance demo_fixture source_identity {}]
        if {[dict exists $::GX::ComponentDemo::specs $type]} {dict set row example [dict get $::GX::ComponentDemo::specs $type]} else {dict set row gap {No registered deterministic public example specification}}
        dict set result $type $row
    }
    return $result
}
proc ::GX::_viewerGuiDemoItem {id type parent properties {row 0} {weight 0}} {return [dict create id $id type $type parent $parent properties $properties layout [dict create row $row column 0 weight $weight sticky nsew]]}
proc ::GX::viewerGuiComponentDemoDesign {type {variant standalone}} {
    if {$variant ni {standalone composite}} {error {Choose standalone or composite}}
    set catalog [viewerGuiComponentDemoCatalog]
    if {![dict exists $catalog $type example]||[dict get $catalog $type capability status] ne {AVAILABLE}} {error {This capability has no available real example}}
    set d [viewerGuiDesignNew];dict set d title "Demo / synthetic content · $type"
    dict set d geometry [expr {$type in {native2d plot native3d splitter tabs tab}||$variant eq {composite} ? {920x650} : {680x440}}]
    set components {};set parent canvas;set p [dict get $catalog $type example properties]
    if {$type in {menu}} {set parent menubar} elseif {$type eq {command_toolbar}} {set parent toolbar} elseif {$type in {workspace history help}} {set parent footer}
    if {$type eq {tab}} {lappend components [_viewerGuiDemoItem pages tabs canvas {} 0 1];set parent pages}
    set expand [expr {$type in {panel section splitter tabs tab log list table native2d plot native3d}}]
    lappend components [_viewerGuiDemoItem example $type $parent $p 0 $expand]
    if {$type in {panel section tab}} {
        lappend components [_viewerGuiDemoItem content label example {text {Synthetic sample A · demonstration content only} wraplength 400}]
        lappend components [_viewerGuiDemoItem sample_label entry example {default {Synthetic sample A}} 1]
        lappend components [_viewerGuiDemoItem calibration toggle example {label {Show synthetic calibration} default 1} 2]
        lappend components [_viewerGuiDemoItem sample_range choice example {label {Synthetic range} choices {Low Medium High} default Medium} 3]
    }
    if {$type in {tabs tab splitter}} {
        if {$type eq {tabs}} {set parent example} elseif {$type eq {tab}} {set parent pages} else {set parent example}
        set pages [expr {$type eq {tab} ? {second Summary} : {first Acquisition second Summary}}]
        foreach {id title} $pages {
            set childType [expr {$type eq {splitter} ? {panel} : {tab}}]
            lappend components [_viewerGuiDemoItem $id $childType $parent [dict create title $title] 0 1]
            lappend components [_viewerGuiDemoItem ${id}_label label $id [dict create text "DEMO · $title · local sample state"]]
            if {$id eq {first}} {
                lappend components [_viewerGuiDemoItem instrument_value field $id {label {Synthetic temperature} datatype number default 23.5 min -50 max 100} 1]
                lappend components [_viewerGuiDemoItem instrument_enabled toggle $id {label {Synthetic acquisition enabled} default 1} 2]
                lappend components [_viewerGuiDemoItem instrument_range choice $id {label {Synthetic range} choices {Low Medium High} default Medium} 3]
            } else {lappend components [_viewerGuiDemoItem summary_table table $id {columns {Sample Value Unit}} 1 1]}
        }
    }
    if {$type in {workspace history help menu context_menu command_toolbar}} {
        lappend components [_viewerGuiDemoItem demo_note label canvas [dict create text [dict get $catalog $type example instructions] wraplength 520]]
    }
    if {$variant eq {composite}} {
        lappend components [_viewerGuiDemoItem sample_info section inspector {title {Synthetic instrument}}]
        lappend components [_viewerGuiDemoItem sample_name entry sample_info {default {Sample A}}]
        lappend components [_viewerGuiDemoItem sample_status label sample_info {text {Display-only composition · no science}} 1]
    }
    if {$type ni {command_toolbar}} {lappend components [_viewerGuiDemoItem demo_tools command_toolbar toolbar {actions {demo_advance demo_reset}}]}
    dict set d components $components
    dict set d handlers demo_advance {arguments {window action} effect presentation label {Advance demo state}}
    dict set d handlers demo_reset {arguments {window action} effect presentation label {Reset demo}}
    set requirements {VIEWER_GUI_HOST_API_v1 1}
    foreach item $components {set cap [dict get [viewerGuiComponentCapabilities] [dict get $item type]];dict set requirements [dict get $cap api_id] [dict get $cap api_version]}
    dict set d requirements $requirements
    dict set d origin {kind demo_fixture fixture_version 1 scientific_source {}}
    dict set d shell status [expr {$type eq {table}?{DEMO / synthetic content · read-only table · no cell editing or scientific publication}:{DEMO / synthetic content · no scientific handlers, Jobs, Dataset or Workspace publication}}]
    return [viewerGuiDesignValidate $d]
}
proc ::GX::viewerGuiComponentDemoOpen {type {variant standalone} {state default}} {
    set d [viewerGuiComponentDemoDesign $type $variant]
    if {$state ni [dict get [viewerGuiComponentDemoCatalog] $type example states]} {error {This sample state is not available for the selected component}}
    catch {destroy .gxComponentDemo}
    set ::GX::ComponentDemo::trace {}
    if {[winfo exists .gxComponentGallery.body.right.eventsBox.text]} {set events .gxComponentGallery.body.right.eventsBox.text;$events configure -state normal;$events delete 1.0 end;$events configure -state disabled}
    viewerGuiDesignCompose $d .gxComponentDemo viewer.interface_builder interface_builder demo {} {command_catalog viewer.interface_builder.interface_builder.demo_commands}
    dict set ::GX::ViewerGui::instances .gxComponentDemo demo_type $type
    dict set ::GX::ViewerGui::instances .gxComponentDemo demo_variant $variant
    dict set ::GX::ViewerGui::instances .gxComponentDemo demo_state $state
    dict set ::GX::ViewerGui::instances .gxComponentDemo demo_count 0
    set widget [dict get $::GX::ViewerGui::instances .gxComponentDemo widgets example]
    if {$type eq {table}} {
        viewerGuiDesignTableSet .gxComponentDemo example {{{Synthetic A} 23.5 demo} {{Synthetic B} 24.1 demo} {Reference 20.0 demo} {Blank 0.0 demo}}
        bind $widget <<TreeviewSelect>> [list ::GX::viewerGuiDemoLifecycleEvent .gxComponentDemo example selection]
    }
    if {[dict exists $::GX::ViewerGui::instances .gxComponentDemo widgets summary_table]} {viewerGuiDesignTableSet .gxComponentDemo summary_table {{{Synthetic A} 23.5 demo} {{Synthetic B} 24.1 demo} {Reference 20.0 demo}}}
    if {$type eq {progress}} {set ::GX::ViewerGui::values(.gxComponentDemo,example) 25}
    if {$type eq {dataset_selector}} {set ::GX::ViewerGui::values(.gxComponentDemo,example) {Synthetic sensor A}}
    set target [expr {[winfo exists $widget.entry] ? "$widget.entry" : $widget}]
    if {$state eq {disabled}} {catch {$target state disabled}} elseif {$state eq {selected}} {after idle [list ::GX::uiFieldFocusWhenMapped .gxComponentDemo $target 0]} elseif {$state eq {empty}} {
        if {$type in {entry field combobox choice dataset_selector toggle checkbutton progress}} {set ::GX::ViewerGui::values(.gxComponentDemo,example) {}}
        if {$type eq {table}} {viewerGuiDesignTableSet .gxComponentDemo example {}}
        if {$type eq {list}} {$widget delete 0 end}
    } elseif {$state eq {invalid}&&$type eq {field}} {$target delete 0 end;$target insert 0 {invalid sample}}
    viewerGuiTraceSubscribe .gxComponentDemo ::GX::_viewerGuiDemoTrace
    return .gxComponentDemo
}
proc ::GX::viewerGuiDemoAction {window id} {
    if {![dict exists $::GX::ViewerGui::instances $window]||[dict get $::GX::ViewerGui::instances $window mode] ne {demo}} {error {Synthetic action requires a demo-owned instance}}
    if {$id eq {demo_reset}} {
        set instance [dict get $::GX::ViewerGui::instances $window]
        after idle [list ::GX::viewerGuiComponentDemoOpen [dict get $instance demo_type] [dict get $instance demo_variant] [dict get $instance demo_state]]
        return [dict create status demo_reset_queued author demo_fixture]
    }
    if {$id ne {demo_advance}} {return [dict create status not_connected author demo_fixture]}
    set count [expr {1+[dict get $::GX::ViewerGui::instances $window demo_count]}]
    dict set ::GX::ViewerGui::instances $window demo_count $count
    if {[dict get $::GX::ViewerGui::instances $window demo_type] eq {progress}} {set ::GX::ViewerGui::values($window,example) [expr {($count*25)%125}]}
    set result [dict create status synthetic_state_changed author demo_fixture count $count source_identity {}]
    viewerGuiTraceEmit $window example invoke $result
    [dict get $::GX::ViewerGui::instances $window slots status] configure -text "DEMO / synthetic content · local state $count · no scientific action"
    return $result
}
proc ::GX::viewerGuiDemoNativeEvent {window id widget event} {if {[viewerGuiDesignGuard $window]} {viewerGuiTraceEmit $window $id demo_fixture $event}}
proc ::GX::viewerGuiDemoLifecycleEvent {window id event args} {if {[viewerGuiDesignGuard $window]} {viewerGuiTraceEmit $window $id demo_fixture [dict create event $event author demo_fixture source_identity {}]}}
proc ::GX::_viewerGuiDemoTrace {record} {
    set ::GX::ComponentDemo::trace [lrange [linsert $::GX::ComponentDemo::trace end $record] end-127 end]
    if {[winfo exists .gxComponentGallery.body.right.eventsBox.text]} {
        set t .gxComponentGallery.body.right.eventsBox.text;$t configure -state normal;$t delete 1.0 end
        foreach event $::GX::ComponentDemo::trace {$t insert end "$event\n\n"}
        $t see end;$t configure -state disabled
    }
}
proc ::GX::viewerGuiDemoPlotModel {} {
    return {title {DEMO · synthetic laboratory response} panels {{id main title {RAM model · no Dataset} axes {x {label {Display time (demo units)}} left {label {Response (demo units)}}} annotations {} series {{id demo_signal kind line_marker label {Synthetic response} axis left points {{0 1} {1 1.4} {2 2.1} {3 2.6} {4 2.2} {5 3.1} {6 3.5} {7 3.3} {8 4.2} {9 4.5} {10 4.1}} source_rows {0 1 2 3 4 5 6 7 8 9 10} full_bounds {0 1 10 4.5} style {color #245caa marker circle}}}}}}
}
proc ::GX::viewerGuiLifecycleDemoCreate {widget type callback} {
    switch $type {
        workspace {return [sessionWorkspaceDemoCreate $widget $callback]}
        history {return [scientificHistoryDemoCreate $widget $callback]}
        help {return [documentationBrowserDemoCreate $widget $callback]}
    }
    error {Unknown public lifecycle sample}
}
proc ::GX::viewerGuiComponentGallerySelect {} {
    set type [lindex [.gxComponentGallery.body.list.types selection] 0]
    if {$type eq {}} return
    set ::GX::ComponentDemo::selected $type
    set row [dict get [viewerGuiComponentDemoCatalog] $type]
    set states [dict get $row example states]
    .gxComponentGallery.options.state configure -values $states
    if {$::GX::ComponentDemo::state ni $states} {set ::GX::ComponentDemo::state default}
    set t .gxComponentGallery.body.right.apiBox.text;$t configure -state normal;$t delete 1.0 end
    dict for {key value} [dict get $row capability] {$t insert end "$key: $value\n\n"}
    $t insert end "Fixture version: 1\nProvenance: demo_fixture\nScientific source: none\n\nIcons: supported properties are listed above for this component. Use Interface Builder Icon Library to import validated project resources, assign supported states and preview the generated appearance. Native menu limitations are documented in the public GUI Host guide. This synthetic Gallery fixture does not certify an authored project's icon bindings."
    $t configure -state disabled
    .gxComponentGallery.body.right.instructions configure -text [dict get $row example instructions]
}
proc ::GX::viewerGuiComponentGalleryShow {} {
    if {![info exists ::GX::ComponentDemo::selected]} {error {Choose a Gallery component}}
    set ::GX::ComponentDemo::trace {}
    viewerGuiComponentDemoOpen $::GX::ComponentDemo::selected $::GX::ComponentDemo::variant $::GX::ComponentDemo::state
}
proc ::GX::viewerGuiComponentGalleryOpen {{selected {}}} {
    set w .gxComponentGallery
    if {[winfo exists $w]} {raise $w;return $w}
    toplevel $w;wm title $w {Component Gallery · Demo / synthetic content};wm geometry $w 1000x740+60+60;wm minsize $w 760 560
    ttk::label $w.banner -text {Demo / synthetic content — public components, local sample state, no scientific handlers} -font TkHeadingFont -wraplength 900
    bind $w.banner <Configure> +[list ::GX::_uiFieldComponentTextWrap $w.banner 900 %W %w]
    pack $w.banner -fill x -padx 8 -pady 8
    ttk::frame $w.controls
    foreach {id label command} {show {Show example / Try interaction} ::GX::viewerGuiComponentGalleryShow reset Reset ::GX::viewerGuiComponentGalleryShow guide {Open public API guide} ::GX::viewerGuiComponentGalleryGuide close {Return to Design} ::GX::viewerGuiComponentGalleryClose} {ttk::button $w.controls.$id -text $label -command $command;pack $w.controls.$id -side left -padx 3}
    pack $w.controls -fill x -padx 5
    ttk::frame $w.options
    foreach {id label variable values} {variant Layout ::GX::ComponentDemo::variant {standalone composite} state {Sample state} ::GX::ComponentDemo::state {default selected disabled empty invalid}} {
        ttk::label $w.options.${id}label -text $label;ttk::combobox $w.options.$id -state readonly -textvariable $variable -values $values -width 14
        pack $w.options.${id}label $w.options.$id -side left -padx 5 -pady 5
    }
    pack $w.options -fill x
    ttk::panedwindow $w.body -orient horizontal;ttk::frame $w.body.list;ttk::frame $w.body.right
    $w.body add $w.body.list -weight 0;$w.body add $w.body.right -weight 1
    ttk::treeview $w.body.list.types -columns {status} -show {tree headings} -height 18 -selectmode browse
    $w.body.list.types heading #0 -text Component;$w.body.list.types column #0 -width 170 -minwidth 130
    $w.body.list.types heading status -text Status;$w.body.list.types column status -width 90
    ttk::scrollbar $w.body.list.bar -command [list $w.body.list.types yview];$w.body.list.types configure -yscrollcommand [list $w.body.list.bar set]
    pack $w.body.list.bar -side right -fill y;pack $w.body.list.types -fill both -expand 1
    set count 0
    dict for {type row} [viewerGuiComponentDemoCatalog] {$w.body.list.types insert {} end -id $type -text $type -values [dict get $row capability status];incr count}
    ttk::label $w.body.right.count -text "$count runtime capabilities · fixture version 1" -font TkHeadingFont
    ttk::label $w.body.right.instructions -wraplength 620 -justify left -padding 6
    bind $w.body.right.instructions <Configure> +[list ::GX::_uiFieldComponentTextWrap $w.body.right.instructions 620 %W %w]
    ttk::label $w.body.right.apiTitle -text {Exact public API / owner / supported properties and limitations}
    ttk::frame $w.body.right.apiBox
    text $w.body.right.apiBox.text -wrap word -height 12 -state disabled
    ttk::scrollbar $w.body.right.apiBox.bar -command [list $w.body.right.apiBox.text yview]
    $w.body.right.apiBox.text configure -yscrollcommand [list $w.body.right.apiBox.bar set]
    pack $w.body.right.apiBox.bar -side right -fill y;pack $w.body.right.apiBox.text -fill both -expand 1
    ttk::label $w.body.right.eventsTitle -text {Inspect events · bounded demo-fixture trace (no scientific provenance)}
    ttk::frame $w.body.right.eventsBox
    text $w.body.right.eventsBox.text -wrap word -height 8 -state disabled
    ttk::scrollbar $w.body.right.eventsBox.bar -command [list $w.body.right.eventsBox.text yview]
    $w.body.right.eventsBox.text configure -yscrollcommand [list $w.body.right.eventsBox.bar set]
    pack $w.body.right.eventsBox.bar -side right -fill y;pack $w.body.right.eventsBox.text -fill both -expand 1
    foreach id {count apiTitle eventsTitle} {
        $w.body.right.$id configure -wraplength 620
        bind $w.body.right.$id <Configure> +[list ::GX::_uiFieldComponentTextWrap $w.body.right.$id 620 %W %w]
    }
    foreach id {count instructions apiTitle apiBox eventsTitle eventsBox} {pack $w.body.right.$id -fill [expr {$id in {apiBox eventsBox} ? {both} : {x}}] -expand [expr {$id in {apiBox eventsBox}}] -padx 5 -pady 3}
    pack $w.body -fill both -expand 1 -padx 6 -pady 6
    bind $w.body.list.types <<TreeviewSelect>> ::GX::viewerGuiComponentGallerySelect
    bind $w.body.list.types <Return> {::GX::viewerGuiComponentGalleryShow;break}
    bind $w.body.list.types <Double-1> {::GX::viewerGuiComponentGalleryShow;break}
    wm protocol $w WM_DELETE_WINDOW ::GX::viewerGuiComponentGalleryClose
    if {$selected eq {}} {set selected [lindex [dict keys [viewerGuiComponentDemoCatalog]] 0]}
    $w.body.list.types selection set $selected;$w.body.list.types see $selected
    viewerGuiComponentGallerySelect
    return $w
}
proc ::GX::viewerGuiComponentGalleryGuide {} {set cap [dict get [viewerGuiComponentCapabilities] $::GX::ComponentDemo::selected];documentationBrowserOpenApi [dict get $cap api_id]}
proc ::GX::viewerGuiComponentGalleryClose {} {catch {destroy .gxComponentDemo};catch {destroy .gxComponentGallery};if {[winfo exists .gxInterfaceDesigner]} {set ::GX::InterfaceBuilder::s(presentationMode) Design}}
