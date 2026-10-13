# SPDX-License-Identifier: GPL-3.0-or-later
# Logical IDs persist; Native2D owns names, attributes and fragment references.
proc ::GX::CurveWorkbench::_identitySetAttributes {w native attributes} {
    variable st
    set current [::GX::Native2D::core identity_attributes $st($w,scene) $native]
    foreach key [dict keys $current] {if {![dict exists $attributes $key]} {::GX::Native2D::core identity_attribute_remove $st($w,scene) $native $key}}
    dict for {key value} $attributes {if {![dict exists $current $key]||[dict get $current $key] ne $value} {::GX::Native2D::core identity_attribute $st($w,scene) $native $key $value}}
}
proc ::GX::CurveWorkbench::_identitySync {w} {
    variable st
    if {[::GX::Native2D::core drag_active $st($w,scene)]} return
    _identitySetAttributes $w 0 $st($w,sketchAttributes)
    dict for {id record} $st($w,curves) {
        set attrs [::GX::datasetPublicationV2DictDefault $record sketch_attributes {}];dict set attrs gx.name [dict get $record name]
        _identitySetAttributes $w [dict get $record native] $attrs
    }
    dict for {id record} $st($w,groups) {
        if {![dict exists $st($w,groupNative) $id]} continue
        set attrs [::GX::datasetPublicationV2DictDefault $record sketch_attributes {}];dict set attrs gx.name [dict get $record name]
        _identitySetAttributes $w [dict get $st($w,groupNative) $id] $attrs
    }
}
proc ::GX::CurveWorkbench::_fragmentCapture {w} {
    variable st
    set result {}
    dict for {id record} $st($w,sketchFragments) {
        set saved [dict remove $record native]
        if {[dict exists $record native]} {
            set receipt [::GX::Native2D::core fragment_get $st($w,scene) [dict get $record native]]
            dict set saved state [expr {[dict get $receipt missing] ? "missing" : [dict get $receipt valid] ? "current" : "stale"}]
        } else {
            set parent [dict get $record definition parent]
            if {![dict exists $st($w,curves) $parent]} {dict set saved state missing}
        }
        dict set result $id $saved
    }
    return $result
}
proc ::GX::CurveWorkbench::_fragmentCloseNative {w} {
    variable st
    foreach receipt [::GX::Native2D::core fragment_list $st($w,scene)] {::GX::Native2D::core fragment_delete $st($w,scene) [dict get $receipt id]}
    set st($w,sketchFragments) {}
}
proc ::GX::CurveWorkbench::_fragmentNativeSpec {w definition} {
    dict set definition parent [dict get [_record $w [dict get $definition parent]] native];return $definition
}
proc ::GX::CurveWorkbench::_identityOpen {w} {
    variable st
    set targets [concat {document} [dict keys $st($w,curves)] [dict keys $st($w,groups)] [dict keys $st($w,sketchFragments)]]
    set initial [dict create target [expr {$st($w,active) eq {} ? "document" : $st($w,active)}] name {} key user.comment value {} remove 0]
    if {$st($w,active) ne {}} {dict set initial name [dict get [_record $w $st($w,active)] name]}
    ::GX::uiFieldFormCreate $w.identity "Names and namespaced sketch attributes" [dict create target [dict create type choice label {Logical sketch entity} values $targets] name {type string label {Name (empty preserves current)}} key {type string label {Namespaced attribute key (empty skips attribute)}} value {type string label {Attribute text value}} remove {type boolean label {Remove this attribute}}] $initial [list ::GX::CurveWorkbench::_identityApply $w $st($w,token)] $w
}
proc ::GX::CurveWorkbench::_identityApply {w token values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen identity parameters"}
    _cancelGesture $w
    set target [dict get $values target];set ids {}
    if {[dict exists $st($w,curves) $target]} {set ids [list $target]}
    set before [_snapshotIds $w $ids];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {$target eq "document"} {set native 0} elseif {$ids ne {}} {set native [dict get [_record $w $target] native]} elseif {[dict exists $st($w,groups) $target]} {set native [dict get $st($w,groupNative) $target]} elseif {[dict exists $st($w,sketchFragments) $target native]} {set native [dict get $st($w,sketchFragments) $target native]} else {error "The selected entity is missing/stale; update its fragment interval first"}
    set name [string trim [dict get $values name]];set key [string trim [dict get $values key]]
    try {
        if {$key ne {}} {
            if {[dict get $values remove]} {::GX::Native2D::core identity_attribute_remove $st($w,scene) $native $key} else {::GX::Native2D::core identity_attribute $st($w,scene) $native $key [dict get $values value]}
        }
        if {$name ne {}} {::GX::Native2D::core identity_name $st($w,scene) $native $name}
        set attributes [::GX::Native2D::core identity_attributes $st($w,scene) $native]
        if {$target eq "document"} {set st($w,sketchAttributes) $attributes} else {
            set container [expr {$ids ne {} ? "curves" : [dict exists $st($w,groups) $target] ? "groups" : "sketchFragments"}]
            dict set st($w,$container) $target sketch_attributes $attributes
            if {$name ne {}} {dict set st($w,$container) $target name $name}
        }
        _history $w $before $ids
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _fragmentRefresh $w;return $target
}
proc ::GX::CurveWorkbench::_fragmentRefresh {w} {
    variable st
    if {![winfo exists $w.fragments.tree]} return
    set tree $w.fragments.tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} [_fragmentCapture $w] {
        set definition [dict get $record definition]
        $tree insert {} end -id $id -values [list $id [dict get $record name] [dict get $definition parent] [dict get $record state] [expr {[dict get $definition parameter] ? "parameter" : "point ordinals"}] [dict get $definition first] [dict get $definition last]]
    }
    _inspectionColumnsFit $tree
    foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
}
proc ::GX::CurveWorkbench::_fragmentOpen {w} {
    set d $w.fragments
    if {[winfo exists $d]} {raise $d;_fragmentRefresh $w;return}
    toplevel $d;wm title $d "Named parent-linked fragments";wm transient $d $w;wm geometry $d 1000x450
    ttk::label $d.help -text {Fragments reference geometry without copying it. Ordinary transforms and retained parameter edits preserve identity. Reordered points or changed topology mark references stale; explicitly update the interval to rebind. Sampling creates independent geometry; publication is a separate action.} -wraplength 920 -padding 8
    bind $d.help <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $d.help %w];pack $d.help -side top -fill x
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label callback} [list create {Create…} [list _fragmentForm $w] edit {Update interval…} [list _fragmentForm $w 1] sample {Sample to Native…} [list _fragmentSampleForm $w] remove Remove [list _fragmentRemove $w]] {
        set callback [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]]
        ttk::button $d.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $callback];pack $d.actions.$key -side left -padx 4
    }
    ttk::button $d.actions.close -text Close -command [list destroy $d];pack $d.actions.close -side right;bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    ttk::frame $d.table;pack $d.table -fill both -expand 1
    ttk::treeview $d.tree -columns {id name parent status interval first last} -show headings -selectmode browse
    foreach key {id name parent status interval first last} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 140 -minwidth [expr {[font measure TkHeadingFont [string totitle $key]]+22}]}
    ttk::scrollbar $d.y -orient vertical -command [list $d.tree yview];ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview];$d.tree configure -yscrollcommand [list $d.y set] -xscrollcommand [list $d.x set]
    pack $d.x -in $d.table -side bottom -fill x;pack $d.y -in $d.table -side right -fill y;pack $d.tree -in $d.table -fill both -expand 1
    bind $d.tree <Configure> [list ::GX::CurveWorkbench::_inspectionColumnsSchedule $d.tree]
    bind $d <Escape> [list destroy $d];_fragmentRefresh $w
}
proc ::GX::CurveWorkbench::_fragmentSelected {w} {set ids [$w.fragments.tree selection];if {[llength $ids]!=1} {error "Select one fragment"};return [lindex $ids 0]}
proc ::GX::CurveWorkbench::_fragmentForm {w {edit 0}} {
    variable st
    set curves [dict keys $st($w,curves)];if {$curves eq {}} {error "Create or load geometry first"}
    set parent [_active $w];set record [_record $w $parent];set parameter [dict exists $record sketch_definition]
    set initial [dict create name fragment parent $parent parameter $parameter first 0 last [expr {$parameter ? 1 : [_pointCount $record]-1}]];set id {}
    if {$edit} {set id [_fragmentSelected $w];set record [dict get $st($w,sketchFragments) $id];set initial [dict merge [dict get $record definition] [dict create name [dict get $record name]]]}
    ::GX::uiFieldFormCreate $w.fragmentForm "Named fragment interval" [dict create name {type string label {Fragment name}} parent [dict create type choice label {Parent logical curve ID} values $curves] parameter {type boolean label {Use retained parameter interval (otherwise inclusive point ordinals)}} first {type number label {First parameter / point ordinal}} last {type number label {Last parameter / point ordinal}}] $initial [list ::GX::CurveWorkbench::_fragmentApply $w $st($w,token) $id] $w.fragments
}
proc ::GX::CurveWorkbench::_fragmentApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen fragment parameters"}
    _cancelGesture $w;set name [string trim [dict get $values name]];if {$name eq {}} {error "Enter a fragment name"}
    set definition [dict remove $values name];set spec [_fragmentNativeSpec $w $definition]
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {$id eq {}||![dict exists $st($w,sketchFragments) $id native]} {
        set receipt [::GX::Native2D::core fragment_create $st($w,scene) $spec]
        if {$id eq {}} {set id "fragment[incr st($w,nextFragment)]"}
    } else {set receipt [::GX::Native2D::core fragment_update $st($w,scene) [dict get $st($w,sketchFragments) $id native] $spec]}
    set attributes {};if {[dict exists $st($w,sketchFragments) $id sketch_attributes]} {set attributes [dict get $st($w,sketchFragments) $id sketch_attributes]};dict set attributes gx.name $name
    set native [dict get $receipt id];_identitySetAttributes $w $native $attributes
    dict set st($w,sketchFragments) $id [dict create id $id name $name definition $definition native $native state current sketch_attributes $attributes]
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _fragmentRefresh $w;return $id
}
proc ::GX::CurveWorkbench::_fragmentRemove {w} {
    variable st
    _cancelGesture $w;set id [_fragmentSelected $w];set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {[dict exists $st($w,sketchFragments) $id native]} {::GX::Native2D::core fragment_delete $st($w,scene) [dict get $st($w,sketchFragments) $id native]};dict unset st($w,sketchFragments) $id
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _fragmentRefresh $w
}
proc ::GX::CurveWorkbench::_fragmentSampleForm {w} {
    variable st
    set id [_fragmentSelected $w]
    if {[dict get [_fragmentCapture $w] $id state] ne "current"} {error "Fragment is stale/missing; update its interval explicitly before sampling"}
    ::GX::uiFieldFormCreate $w.fragmentSample "Explicit Native fragment sampling" {name {type string label {New geometry name}} total {type integer min 1 max 65536 label {Uniform fragment sample count}}} [dict create name [dict get $st($w,sketchFragments) $id name] total 257] [list ::GX::CurveWorkbench::_fragmentSampleApply $w $st($w,token) $id] $w.fragments
}
proc ::GX::CurveWorkbench::_fragmentSampleApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen fragment sampling"}
    _cancelGesture $w
    if {[dict get [_fragmentCapture $w] $id state] ne "current"} {error "Fragment is stale/missing; update its interval first"}
    set fragment [dict get $st($w,sketchFragments) $id];set parent [dict get $fragment definition parent]
    set native [::GX::Native2D::core fragment_materialize $st($w,scene) [dict get $fragment native] [dict get $values total]]
    try {
        set record [_newRecord $w [dict get $values name] [_sketchSamples $w $native] {} x y {} {} {} {} [list $parent] [list [dict create operation fragment_materialization fragment_id $id definition [dict get $fragment definition]]]]
        dict set record sketch_attributes [dict get $fragment sketch_attributes];dict set record materialization_sampling [dict create method uniform_fragment total [dict get $values total] fragment_id $id definition [dict get $fragment definition]]
        set created [dict get $record id];set before [_snapshotIds $w [list $created]];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
        _addRecord $w $record $native;set st($w,active) $created;set st($w,objectSelection) [list $created]
        _identitySync $w;_selectionScene $w;_history $w $before [list $created]
    } on error {message options} {
        if {[info exists before]} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo} elseif {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}
        return -options $options $message
    }
    return $created
}
rename ::GX::CurveWorkbench::_restoreSnapshot ::GX::CurveWorkbench::_restoreSnapshot_identity_base
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {_cancelGesture $w;_fragmentCloseNative $w;_restoreSnapshot_identity_base $w $snapshot}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_identity_base
proc ::GX::CurveWorkbench::_changed {w} {_identitySync $w;_changed_identity_base $w;_fragmentRefresh $w}
proc ::GX::CurveWorkbench::_buildIdentity {w} {
    variable st
    foreach {label callback} {{Names / Attributes…} _identityOpen {Fragments…} _fragmentOpen} {$w.cad.sketch.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::$callback $w]]}
}

proc ::GX::CurveWorkbench::_publicationSketchMetadata {w ids} {
    variable st
    set entities {}
    foreach id $ids {
        set record [_record $w $id]
        dict set entities $id [dict create name [dict get $record name] attributes [dict remove [::GX::datasetPublicationV2DictDefault $record sketch_attributes {}] gx.name]]
    }
    return [dict create sketch.attributes [dict remove $st($w,sketchAttributes) gx.name] sketch.entity_descriptors $entities sketch.attribute_mapping {Explicit user attributes under sketch.attributes and sketch.entity_descriptors; names are entity labels; internal UI fields are excluded} curve_workbench.output_representation [expr {[info exists st($w,publicationRepresentation)] ? $st($w,publicationRepresentation) : "cartesian"}] curve_workbench.polar_frame [::GX::Native2D::core polar $st($w,scene)] curve_workbench.coordinate_orientation ordered_geometry curve_workbench.sampling_policy explicit_native_samples_or_complete_source_tuples]
}
rename ::GX::CurveWorkbench::_newRecord ::GX::CurveWorkbench::_newRecord_identity_base
proc ::GX::CurveWorkbench::_newRecord {w name samples source x y filter value family order parents operations {representation linear}} {
    set record [_newRecord_identity_base $w $name $samples $source $x $y $filter $value $family $order $parents $operations $representation]
    if {$parents ne {}} {dict set record sketch_attributes [dict remove [::GX::datasetPublicationV2DictDefault [_record $w [lindex $parents 0]] sketch_attributes {}] gx.name]}
    return $record
}
