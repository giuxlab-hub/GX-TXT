# SPDX-License-Identifier: GPL-3.0-or-later
# Native2D owns relationships and validation. Controller IDs persist independently
# of regenerated native handles across Undo, recovery and Session restore.
proc ::GX::CurveWorkbench::_constraintNativeSpec {w definition} {
    variable st
    set spec $definition
    foreach field {a b axis} {
        if {[dict exists $definition $field]&&[dict get $definition $field] ne {}} {dict set spec $field [dict get [_record $w [dict get $definition $field]] native]} else {dict unset spec $field}
    }
    return $spec
}
proc ::GX::CurveWorkbench::_constraintCapture {w} {
    variable st
    set reverse [_logicalNativeMap $w]
    set native {};foreach receipt [::GX::Native2D::core constraint_list $st($w,scene)] {dict set native [dict get $receipt id] $receipt}
    set result {}
    dict for {id record} $st($w,constraints) {
        if {![dict exists $native [dict get $record native]]} continue
        set receipt [dict get $native [dict get $record native]]
        set definition [dict remove $receipt id valid geometry_supported measured_value residual angular_residual enforcement general_solver]
        foreach field {a b axis} {
            set number [dict get $definition $field]
            if {$number==0} {dict unset definition $field} elseif {[dict exists $reverse $number]} {dict set definition $field [dict get $reverse $number]} else {error "Constraint references geometry outside this workspace"}
        }
        dict set record definition $definition
        dict set result $id [dict remove $record native]
        dict set st($w,constraints) $id $record
    }
    foreach id [dict keys $st($w,constraints)] {if {![dict exists $result $id]} {dict unset st($w,constraints) $id}}
    return $result
}
proc ::GX::CurveWorkbench::_constraintCloseNative {w} {
    variable st
    foreach receipt [::GX::Native2D::core constraint_list $st($w,scene)] {::GX::Native2D::core constraint_delete $st($w,scene) [dict get $receipt id]}
    set st($w,constraints) {}
}
rename ::GX::CurveWorkbench::_restoreSnapshot ::GX::CurveWorkbench::_restoreSnapshot_constraints_base
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {
    _cancelGesture $w
    _constraintCloseNative $w
    _restoreSnapshot_constraints_base $w $snapshot
}
proc ::GX::CurveWorkbench::_constraintRefresh {w} {
    variable st
    if {![winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]} return
    set tree [::GX::CurveWorkbench::_constraintPanel $w].tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} $st($w,constraints) {
        set receipt [::GX::Native2D::core constraint_get $st($w,scene) [dict get $record native]]
        set kind [dict get $receipt kind];set unit [lindex [_coordinateUnits [_record $w [dict get $record definition a]]] 0]
        if {$kind in {angle parallel perpendicular}} {set unit rad}
        $tree insert {} end -id $id -values [list $id [dict get $record name] $kind [expr {[dict get $receipt valid] ? "valid" : "violated/unsupported"}] [expr {[dict get $receipt disabled] ? "disabled" : "enforced"}] [dict get $receipt value] [dict get $receipt residual] $unit]
    }
    foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
}
proc ::GX::CurveWorkbench::_constraintOpen {w} {
    variable st
    set d [::GX::CurveWorkbench::_constraintPanel $w]
    if {[winfo exists $d]} {raise $d;_constraintRefresh $w;return}
    toplevel $d;wm title $d "Native2D constraints — validation and enforcement";wm transient $d $w;wm geometry $d 950x500
    ttk::label $d.help -text {Active relationships validate Native edits atomically. There is no general parametric solver. Create a satisfied relation or disable it for inspection; exact endpoint Join is a separate action.} -wraplength 880 -padding 8
    bind $d.help <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $d.help %w]
    pack $d.help -side top -fill x
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label callback} [list create {Create…} [list _constraintForm $w] edit {Edit parameters…} [list _constraintForm $w 1] toggle {Enable / Disable} [list _constraintAction $w toggle] remove Remove [list _constraintAction $w remove] refresh Refresh [list _constraintRefresh $w]] {
        set callback [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]]
        ttk::button $d.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $callback];pack $d.actions.$key -side left -padx 4
    }
    ttk::button $d.actions.close -text Close -command [list destroy $d];pack $d.actions.close -side right
    bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    ttk::frame $d.table;pack $d.table -fill both -expand 1
    ttk::treeview $d.tree -columns {id name kind valid state value residual unit} -show headings -selectmode browse
    foreach key {id name kind valid state value residual unit} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 125 -minwidth [expr {[font measure TkHeadingFont [string totitle $key]]+22}]}
    ttk::scrollbar $d.y -orient vertical -command [list $d.tree yview];ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview]
    $d.tree configure -yscrollcommand [list $d.y set] -xscrollcommand [list $d.x set]
    pack $d.x -in $d.table -side bottom -fill x;pack $d.y -in $d.table -side right -fill y;pack $d.tree -in $d.table -fill both -expand 1
    bind $d <Escape> [list destroy $d];_constraintRefresh $w
}
proc ::GX::CurveWorkbench::_constraintSelected {w} {
    set selected [[::GX::CurveWorkbench::_constraintPanel $w].tree selection]
    if {[llength $selected]!=1} {error "Select one constraint"};return [lindex $selected 0]
}
proc ::GX::CurveWorkbench::_constraintForm {w {edit 0}} {
    variable st
    set curves [dict keys $st($w,curves)];if {$curves eq {}} {error "Create or load geometry first"}
    set kinds {fixed distance angle parallel perpendicular coincident horizontal vertical equal_length equal_radius tangent concentric collinear midpoint point_on_line point_on_curve symmetry radius diameter lock_x lock_y horizontal_distance vertical_distance point_line_distance line_distance axis_angle curvature}
    set fields [dict create name {type string label {Constraint name}} kind [dict create type choice label Relationship values $kinds] a [dict create type choice label {Geometry A (logical ID)} values $curves] a_index {type integer min 0 label {Point/segment index A}} b [dict create type choice label {Geometry B (when required)} values [linsert $curves 0 {}]] b_index {type integer min 0 label {Point/segment index B}} axis [dict create type choice label {Symmetry axis geometry (when required)} values [linsert $curves 0 {}]] axis_index {type integer min 0 label {Symmetry axis segment index}} value {type string label {Dimension: numeric display value or value with explicit unit}} tolerance {type number min 1e-15 label {Native coordinate tolerance (angles: radians; directional residuals: normalized)}} angular_tolerance {type number min 1e-15 label {Tangent/collinear angular tolerance (radians)}} disabled {type boolean label {Disable enforcement; retain diagnostics}}]
    set id {};set initial [dict create name constraint kind fixed a [_active $w] a_index 0 b {} b_index 0 axis {} axis_index 0 value 0 tolerance 1e-8 angular_tolerance 1e-9 disabled 0]
    if {$edit} {set id [_constraintSelected $w];set record [dict get $st($w,constraints) $id];set initial [dict merge $initial [dict get $record definition] [dict create name [dict get $record name]]]}
    if {[_isDimension [dict get $initial kind]]} {set spec [_constraintNativeSpec $w [dict remove $initial name]];dict set initial value [_dimensionDisplayedValue $w $spec [dict get $initial value]]}
    ::GX::uiFieldFormCreate $w.constraintForm "Native relationship — current geometry must satisfy enabled parameters" $fields $initial [list ::GX::CurveWorkbench::_constraintDisplayedApply $w $st($w,token) $id $curves [_coordinateControlKey $w $curves]] $w
}
proc ::GX::CurveWorkbench::_constraintApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen constraint parameters"}
    _cancelGesture $w;_pointSyncApply $w
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {[string trim [dict get $values name]] eq {}} {error "Enter a constraint name"}
    set definition [dict remove $values name]
    set refs {};foreach field {a b axis} {if {[dict exists $definition $field]&&[dict get $definition $field] ne {}} {lappend refs [dict get $definition $field]}}
    _constraintCoordinateGuard $w [_constraintNativeSpec $w $definition]
    if {$id ne {}} {
        set record [dict get $st($w,constraints) $id]
        if {[dict exists $record definition anchor]} {dict set definition anchor [dict get $record definition anchor]}
    }
    set spec [_constraintNativeSpec $w $definition]
    if {$id eq {}} {set receipt [::GX::Native2D::core constraint_create $st($w,scene) $spec];set id "constraint[incr st($w,nextConstraint)]"} else {set receipt [::GX::Native2D::core constraint_update $st($w,scene) [dict get $record native] $spec]}
    dict set st($w,constraints) $id [dict create id $id name [dict get $values name] native [dict get $receipt id] definition $definition]
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _constraintRefresh $w;return $id
}
proc ::GX::CurveWorkbench::_constraintAction {w action} {
    variable st
    _cancelGesture $w;set id [_constraintSelected $w];set record [dict get $st($w,constraints) $id]
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {$action eq "remove"} {::GX::Native2D::core constraint_delete $st($w,scene) [dict get $record native];dict unset st($w,constraints) $id} else {::GX::Native2D::core constraint_enable $st($w,scene) [dict get $record native] [dict get $record definition disabled]}
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _constraintRefresh $w
}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_constraints_base
proc ::GX::CurveWorkbench::_changed {w} {_changed_constraints_base $w;_constraintRefresh $w}
proc ::GX::CurveWorkbench::_buildConstraints {w} {
    variable st
    $w.cad.sketch.menu add command -label "Constraints…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintOpen $w]]
}
proc ::GX::CurveWorkbench::_joinSource {w} {
    variable st
    set source [_active $w];set indices [_selected $w]
    if {[llength $indices]!=1} {error "Select exactly one source point row or canvas point before Join"}
    if {[_bulkRecord [_record $w $source]]} {error "Convert an explicit exact range to Native before merging Dataset-backed bulk points"}
    return [list $source [lindex $indices 0]]
}
proc ::GX::CurveWorkbench::_joinOpen {w} {
    variable st
    lassign [_joinSource $w] source index
    set curves [dict keys $st($w,curves)];set target [lindex $curves 0]
    foreach id $curves {if {$id ne $source} {set target $id;break}}
    ::GX::uiFieldFormCreate $w.join "Join $source point $index — Native coincidence relationship" [dict create name {type string label {Relationship name}} target [dict create type choice label {Target geometry logical ID} values $curves] target_index {type integer min 0 label {Target point index}} merge {type boolean label {Move source onto target (supported endpoints/points)}} tolerance {type number min 1e-15 label {Coincidence tolerance in working units}}] [dict create name join target $target target_index 0 merge 1 tolerance 1e-8] [list ::GX::CurveWorkbench::_joinApply $w $st($w,token) $source $index] $w
}
proc ::GX::CurveWorkbench::_joinApply {w token source index values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen Join"}
    set target [dict get $values target];set targetIndex [dict get $values target_index]
    _cadUnits $w [lsort -unique [list $source $target]]
    _cancelGesture $w;_pointSyncApply $w
    set before [_snapshotIds $w [list $source]];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    set receipt [::GX::Native2D::core constraint_join $st($w,scene) [dict get [_record $w $source] native] $index [dict get [_record $w $target] native] $targetIndex [dict get $values merge] [dict get $values tolerance]]
    set id "constraint[incr st($w,nextConstraint)]"
    set definition [dict remove $receipt id valid geometry_supported measured_value residual angular_residual enforcement general_solver]
    dict set definition a $source;dict set definition b $target;dict unset definition axis
    dict set st($w,constraints) $id [dict create id $id name [dict get $values name] native [dict get $receipt id] definition $definition]
    _syncSamples $w $source
    set record [_record $w $source];dict lappend record operations [dict create operation native_join source_index $index target_curve $target target_index $targetIndex relationship $id merge [dict get $values merge]];dict set st($w,curves) $source $record
    set st($w,active) $source;set st($w,joinPending) {}
    try {_selectionScene $w;::GX::Native2D::core selection_replace $st($w,selectionScene) $st($w,selectionObject) [list $index];_history $w $before [list $source]} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    set st($w,status) "Joined $source point $index to $target point $targetIndex; persistent Native coincidence $id."
    return $id
}
proc ::GX::CurveWorkbench::_joinStart {w} {
    variable st
    lassign [_joinSource $w] source index
    _cancelGesture $w
    set st($w,tool) select;set st($w,cadTool) none
    set st($w,joinPending) [dict create source $source index $index]
    set st($w,status) "Join: move over another curve endpoint, then click the highlighted target. Escape cancels."
    _draw $w
}
proc ::GX::CurveWorkbench::_joinTarget {w x y} {
    variable st
    set source [dict get $st($w,joinPending) source];set excluded [list [dict get [_record $w $source] native]];set reverse {}
    dict for {id record} $st($w,curves) {dict set reverse [dict get $record native] $id}
    foreach native [::GX::Native2D::core ids $st($w,scene)] {if {![dict exists $reverse $native]&&[::GX::Native2D::core kind $st($w,scene) $native] ne "group"} {lappend excluded $native}}
    set hit [::GX::Native2D::core scene_nearest_vertex_device $st($w,scene) [list $x $y] 12 $excluded 1]
    if {$hit eq {}} {return {}}
    set target [dict get $reverse [dict get $hit object]];dict unset hit object;dict set hit target $target
    dict set hit compatible 1
    if {[catch {_cadUnits $w [list $source $target]} reason]} {dict set hit compatible 0;dict set hit reason $reason}
    return $hit
}
rename ::GX::CurveWorkbench::_coordinates ::GX::CurveWorkbench::_coordinates_join_base
proc ::GX::CurveWorkbench::_coordinates {w x y} {
    variable st
    _coordinates_join_base $w $x $y
    if {[info exists st($w,joinPending)]&&$st($w,joinPending) ne {}} {
        set target [_joinTarget $w $x $y];dict set st($w,joinPending) candidate $target
        if {$target ne {}&&! [dict get $target compatible]} {set st($w,status) [dict get $target reason]}
        _draw $w
    }
}
proc ::GX::CurveWorkbench::_drawJoinTarget {w} {
    variable st
        if {[info exists st($w,joinPending)]&&[dict exists $st($w,joinPending) candidate]&&[dict get $st($w,joinPending) candidate] ne {}} {
        set candidate [dict get $st($w,joinPending) candidate]
        lassign [::GX::Native2D::core device $st($w,scene) [dict get $candidate point]] x y
        set color [expr {[dict get $candidate compatible] ? "#16803c" : "#c97600"}]
        $w.right.viewport.canvas create oval [expr {$x-12}] [expr {$y-12}] [expr {$x+12}] [expr {$y+12}] -outline $color -width 3 -tags join_target
    }
}
proc ::GX::CurveWorkbench::_pointerDownJoin {w x y state} {
    variable st
    if {$st($w,joinPending) eq {}} {return 0}
    set target [_joinTarget $w $x $y]
    if {$target eq {}} {set st($w,status) "No compatible endpoint at this position; move to a highlighted target or use numeric Join";return 1}
    set source [dict get $st($w,joinPending) source];set index [dict get $st($w,joinPending) index]
    _safe $w [list ::GX::CurveWorkbench::_joinApply $w $st($w,token) $source $index [dict create name join target [dict get $target target] target_index [dict get $target index] merge 1 tolerance 1e-8]]

    return 1
}
rename ::GX::CurveWorkbench::_cancelGesture ::GX::CurveWorkbench::_cancelGesture_join_base
proc ::GX::CurveWorkbench::_cancelGesture {w} {
    variable st
    if {[info exists st($w,joinPending)]} {set st($w,joinPending) {}}
    _cancelGesture_join_base $w
}
proc ::GX::CurveWorkbench::_buildJoin {w} {
    variable st
    $w.cad.sketch.menu add command -label "Join point numerically…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_joinOpen $w]]
    $w.cad.sketch.menu add command -label "Join point on canvas" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_joinStart $w]]
}
