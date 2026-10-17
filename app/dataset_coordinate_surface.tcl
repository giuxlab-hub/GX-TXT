# SPDX-License-Identifier: GPL-3.0-or-later
# Shared user editor. Scientific state belongs to Dataset Metadata/Transform;
# this array holds only captured GUI lifetime, draft revisions and cancellation.
namespace eval ::GX::DatasetCoordinateUI {variable state;array set state {}}
proc ::GX::datasetCoordinatesOpenSelected {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"||$id eq {}} {error {Select a canonical Dataset first}}
    return [datasetCoordinateEditorOpen $id .top]
}
proc ::GX::_datasetCoordinateUiRequire {w} {
    variable ::GX::DatasetCoordinateUI::state
    if {![info exists state($w,session)]||![winfo exists $w]} {error {Coordinate editor is closed}}
    if {$state($w,session) ne $::GX::currentSession||$state($w,token) ne [interactiveDocumentSessionToken]} {error {Session changed; reopen coordinate settings}}
    if {[datasetField $state($w,id) id {}] ne $state($w,id)} {error {Dataset identity changed; reopen coordinate settings}}
}
proc ::GX::_datasetCoordinateUiSafe {w command args} {
    variable ::GX::DatasetCoordinateUI::state
    if {[catch {_datasetCoordinateUiRequire $w;uplevel #0 [list {*}$command {*}$args]} reason]} {
        if {[winfo exists $w]} {set state($w,status) $reason}
        return 0
    }
    return 1
}
proc ::GX::_datasetCoordinateUiRefresh {w} {
    variable ::GX::DatasetCoordinateUI::state
    _datasetCoordinateUiRequire $w
    set selected [$w.table selection]
    set inspection [datasetCoordinateInspect $state($w,session) $state($w,id)]
    set state($w,revision) [dict get $inspection revision]
    $w.table delete [$w.table children {}]
    set valid [dict exists $inspection context]
    foreach name {edit reset materialize} {$w.actions.$name state [expr {$valid?"!disabled":"disabled"}]}
    if {!$valid} {set state($w,status) [dict get $inspection reason];return}
    set state($w,context) [dict get $inspection context]
    dict for {vid settings} [dict get $state($w,context) variables] {
        set variable [datasetVariableV3ById $state($w,id) $vid]
        set label [dict get $variable display_label];if {$label eq {}} {set label [dict get $variable canonical]}
        set unit [dict get $settings source unit];if {$unit eq {}} {set unit undeclared}
        set display [dict get $settings display_unit];if {$display eq {}} {set display undeclared}
        set calibration "[dict get $settings output_origin] + [dict get $settings calibration_factor] × (value − [dict get $settings input_origin])"
        $w.table insert {} end -id $vid -values [list $label $vid $unit $display [dict get $settings view_factor] [dict get $settings view_pivot] $calibration]
    }
    if {[llength $selected]&&[$w.table exists [lindex $selected 0]]} {$w.table selection set [lindex $selected 0]} elseif {[llength [$w.table children {}]]} {$w.table selection set [lindex [$w.table children {}] 0]}
    set state($w,status) "Saved settings, revision $state($w,revision). Coordinate calculations use canonical values unless effective mode is explicitly selected."
}
proc ::GX::_datasetCoordinateUiSelected {w} {
    _datasetCoordinateUiRequire $w
    set selection [$w.table selection]
    if {[llength $selection]!=1} {error {Select one Variable}}
    return [lindex $selection 0]
}
proc ::GX::_datasetCoordinateUiNotify {w} {
    variable ::GX::DatasetCoordinateUI::state
    _datasetCoordinateUiRefresh $w
    if {$state($w,changed) ne {}} {
        if {[catch {uplevel #0 [list {*}$state($w,changed) $state($w,id)]} reason]} {set state($w,status) "Settings saved. Viewer refresh: $reason"}
    }
}
proc ::GX::_datasetCoordinateUiEdit {w} {
    variable ::GX::DatasetCoordinateUI::state
    set vid [_datasetCoordinateUiSelected $w]
    if {[winfo exists $w.edit]} {raise $w.edit;return}
    set context [datasetCoordinateRead $state($w,session) $state($w,id)]
    set state($w,edit_revision) [dict get $context revision]
    set settings [dict get $context variables $vid];set source [dict get $settings source]
    set unit [dict get $source unit];set choices [list $unit]
    if {$unit ne {}} {
        foreach target [unitSelectorCandidates] {
            if {![catch {unitRegistryConversionPlan $unit $target [_datasetCoordinateOverride $source]}]} {lappend choices $target}
        }
    }
    set fields [dict create display_unit [dict create type choice label {Display unit} values [lsort -unique $choices] section display] \
        view_factor {type number required 1 min 0 label {Magnification factor (> 0)} section view} \
        view_pivot [dict create type number required 1 label "Pivot ($unit, canonical)" section view] \
        calibration_factor {type number required 1 min 0 label {Calibration factor (> 0)} section calibration} \
        input_origin [dict create type number required 1 label "Input origin ($unit)" section calibration] \
        output_origin [dict create type number required 1 label "Output origin ($unit)" section calibration]]
    uiFieldFormCreate $w.edit "Coordinate settings — $state($w,id) / $vid" $fields $settings [list ::GX::_datasetCoordinateUiApply $w $vid] $w {display {Display units} view {View magnification} calibration {Effective calibration}}
    ttk::label $w.edit.explanation -text "Source unit: [expr {$unit eq {}?{undeclared}:$unit}].\nDisplay units re-express readouts. Magnification sets a persistent view range. Calibration defines effective values only when explicitly requested." -wraplength 570 -justify left
    pack $w.edit.explanation -side top -fill x -before $w.edit.viewport -padx 12 -pady 8
}
proc ::GX::_datasetCoordinateUiApply {w vid values} {
    variable ::GX::DatasetCoordinateUI::state
    _datasetCoordinateUiRequire $w
    set result [datasetCoordinateUpdate $state($w,session) $state($w,id) [dict create $vid $values] $state($w,edit_revision)]
    set state($w,edit_revision) [dict get $result revision]
    _datasetCoordinateUiNotify $w
}
proc ::GX::_datasetCoordinateUiReset {w {all 0}} {
    variable ::GX::DatasetCoordinateUI::state
    if {$all} {
        datasetCoordinateReset $state($w,session) $state($w,id) $state($w,revision)
    } else {
        set vid [_datasetCoordinateUiSelected $w]
        set source [dict get $state($w,context) variables $vid source]
        datasetCoordinateUpdate $state($w,session) $state($w,id) [dict create $vid [dict remove [_datasetCoordinateDefaults $source] source]] $state($w,revision)
    }
    _datasetCoordinateUiNotify $w
}
proc ::GX::_datasetCoordinateUiDerived {w} {
    variable ::GX::DatasetCoordinateUI::state
    set vid [_datasetCoordinateUiSelected $w]
    if {[winfo exists $w.derived]} {raise $w.derived;return}
    set state($w,materialize_revision) $state($w,revision)
    set fields {dataset_id {type string required 1 label {New Derived Dataset ID}} variable_ids {type string required 1 label {Variable IDs to calibrate (space-separated)}} storage {type choice values {auto csv hdf5} label {Storage}}}
    uiFieldFormCreate $w.derived {Materialize explicit calibration} $fields [dict create dataset_id "$state($w,id)_calibrated" variable_ids $vid storage auto] [list ::GX::_datasetCoordinateUiMaterialize $w] $w
    $w.derived.actions.apply configure -text {Create Derived Dataset}
    ttk::button $w.derived.actions.cancel -text {Cancel processing} -state disabled -command [list set ::GX::DatasetCoordinateUI::state($w,cancel) 1]
    pack $w.derived.actions.cancel -side left -padx 4
}
proc ::GX::_datasetCoordinateUiCancelled {w} {
    variable ::GX::DatasetCoordinateUI::state
    expr {![winfo exists $w.derived]||![info exists state($w,cancel)]||$state($w,cancel)}
}
proc ::GX::_datasetCoordinateUiProgress {w receipt} {
    variable ::GX::DatasetCoordinateUI::state
    if {![winfo exists $w.derived]} return
    set state($w,status) "Calibration: [dict get $receipt stage], [dict get $receipt current] / [dict get $receipt total] rows."
    set ::GX::UiField::formStatus($w.derived) $state($w,status)
}
proc ::GX::_datasetCoordinateUiMaterialize {w values} {
    variable ::GX::DatasetCoordinateUI::state
    _datasetCoordinateUiRequire $w
    if {$state($w,busy)} {error {Calibration is already running}}
    set requested [dict get $values variable_ids]
    if {[catch {llength $requested}]} {error {Enter a space-separated list of Variable IDs}}
    set manifest [dict create api_version 1 operation calibrate_variables sources [list [dict create dataset_id $state($w,id)]] output [dict create dataset_id [dict get $values dataset_id] storage [dict get $values storage]] options [dict create calibration_variable_ids $requested expected_coordinate_revision $state($w,materialize_revision)]]
    set state($w,busy) 1;set state($w,cancel) 0
    $w.derived.actions.apply state disabled;$w.derived.actions.cancel state !disabled
    try {
        set result [datasetTransformExecuteResponsive $state($w,session) $manifest [dict create progress_command [list ::GX::_datasetCoordinateUiProgress $w] cancel_command [list ::GX::_datasetCoordinateUiCancelled $w]]]
        if {[winfo exists $w]} {set state($w,status) "Created [dict get $result dataset_id]. Selected calibration is consumed on the new Dataset; source values and settings are preserved."}
    } on error {message options} {
        if {[winfo exists $w]} {set state($w,status) "Calibration did not complete: $message"}
        return -options $options $message
    } finally {
        if {[winfo exists $w]} {set state($w,busy) 0}
        if {[winfo exists $w.derived]} {$w.derived.actions.apply state !disabled;$w.derived.actions.cancel state disabled}
    }
}
proc ::GX::_datasetCoordinateUiClose {w actual} {
    if {$w ne $actual} return
    array unset ::GX::DatasetCoordinateUI::state "$w,*"
}
proc ::GX::_datasetCoordinateUiLayout {w width} {
    if {![winfo exists $w.actions]} return
    foreach name {help status} {if {[winfo exists $w.$name]} {$w.$name configure -wraplength [expr {max(200,$width-24)}]}}
    set columns [expr {$width<850?2:3}];set i 0
    foreach name {edit reset resetall materialize reload source} {
        grid $w.actions.$name -row [expr {$i/$columns}] -column [expr {$i%$columns}] -sticky ew -padx 3 -pady 3
        incr i
    }
    for {set i 0} {$i<3} {incr i} {grid columnconfigure $w.actions $i -weight [expr {$i<$columns}]}
}
proc ::GX::datasetCoordinateEditorOpen {id {parent {}} {changed {}}} {
    variable currentSession;variable ::GX::DatasetCoordinateUI::state
    set session [_sessionInspectionRequire $currentSession]
    datasetCoordinateInspect $session $id
    set w .dataset_coordinates_[format %08x [zlib crc32 [encoding convertto utf-8 [list $session $id]]]]
    if {[winfo exists $w]} {raise $w;return $w}
    set state($w,id) $id;set state($w,session) $session;set state($w,token) [interactiveDocumentSessionToken]
    set state($w,changed) $changed;set state($w,busy) 0;set state($w,cancel) 0;set state($w,status) {}
    toplevel $w;wm title $w "Dataset coordinates — $id";wm geometry $w 1040x480;wm minsize $w 620 320
    if {$parent ne {}&&[winfo exists $parent]} {wm transient $w $parent}
    ttk::label $w.help -text "Select a Variable to set its display unit, persistent view magnification or explicit calibration. Create a Derived Dataset to apply calibration to stored values." -wraplength 940 -justify left
    pack $w.help -side top -fill x -padx 10 -pady 8
    ttk::frame $w.actions
    foreach {name label command} [list edit {Edit selected…} [list ::GX::_datasetCoordinateUiEdit $w] reset {Reset selected} [list ::GX::_datasetCoordinateUiReset $w] resetall {Reset all Dataset settings} [list ::GX::_datasetCoordinateUiReset $w 1] materialize {Create Derived Dataset…} [list ::GX::_datasetCoordinateUiDerived $w] reload Reload [list ::GX::_datasetCoordinateUiRefresh $w] source {Canonical table…} [list ::GX::datasetPreviewOpenTable $id]] {
        ttk::button $w.actions.$name -text $label -command [list ::GX::_datasetCoordinateUiSafe $w $command]
    }
    pack $w.actions -side bottom -fill x -padx 6 -pady 7
    bind $w.actions <Configure> [list ::GX::_datasetCoordinateUiLayout $w %w]
    _datasetCoordinateUiLayout $w 1040
    ttk::label $w.status -textvariable ::GX::DatasetCoordinateUI::state($w,status) -wraplength 940 -justify left
    pack $w.status -side bottom -fill x -padx 10 -pady 6
    ttk::treeview $w.table -columns {name id source display view pivot calibration} -show headings -selectmode browse
    foreach {key title width} {name Variable 150 id {Variable ID} 110 source {Source unit} 90 display {Display unit} 90 view {View ×} 65 pivot {View pivot} 85 calibration {Effective calibration (source unit)} 255} {
        set minimum [expr {max(55,[font measure TkHeadingFont $title]+18)}]
        $w.table heading $key -text $title;$w.table column $key -width [expr {max($width,$minimum)}] -minwidth $minimum -stretch 1
    }
    ttk::scrollbar $w.sy -orient vertical -command [list $w.table yview];$w.table configure -yscrollcommand [list $w.sy set]
    ttk::scrollbar $w.sx -orient horizontal -command [list $w.table xview];$w.table configure -xscrollcommand [list $w.sx set]
    pack $w.sx -side bottom -fill x;pack $w.sy -side right -fill y;pack $w.table -fill both -expand 1 -padx 8
    bind $w.table <Double-1> [list ::GX::_datasetCoordinateUiSafe $w [list ::GX::_datasetCoordinateUiEdit $w]]
    bind $w <Destroy> [list ::GX::_datasetCoordinateUiClose $w %W]
    _datasetCoordinateUiRefresh $w
    return $w
}
