# SPDX-License-Identifier: GPL-3.0-or-later
# Groups edit geometry; sets remember references; layers organize presentation.
proc ::GX::CurveWorkbench::_collectionNativeRefs {w refs} {
    variable st
    set result {}
    foreach ref $refs {
        set kind [dict get $ref kind];set id [dict get $ref id]
        if {$kind eq "fragment"} {
            if {[dict get [_fragmentCapture $w] $id state] ne "current"} {error "Fragment $id is stale/missing; explicitly update its interval"}
            dict set ref id [dict get $st($w,sketchFragments) $id native]
        } elseif {$kind in {object point control segment}} {dict set ref id [dict get [_record $w $id] native]} else {error "Reference kind must be object, point, control, segment or fragment"}
        lappend result $ref
    }
    return $result
}
proc ::GX::CurveWorkbench::_collectionCaptureSets {w} {
    variable st
    set result {}
    dict for {id record} $st($w,selectionSets) {
        set saved [dict remove $record native]
        if {[dict exists $record native]} {
            set native [::GX::Native2D::core selection_set_get $st($w,scene) [dict get $record native]]
            dict set saved states [lmap member [dict get $native members] {dict create valid [dict get $member valid] missing [dict get $member missing]}]
        } else {
            set states {}
            foreach ref [dict get $saved members] previous [dict get $saved states] {
                set owner [dict get $ref id];set state $previous
                if {[dict get $ref kind] eq "fragment"} {
                    if {![dict exists $st($w,sketchFragments) $owner]} {set state {valid 0 missing 1}} elseif {[dict get [_fragmentCapture $w] $owner state] ne "current"} {dict set state valid 0}
                } elseif {![dict exists $st($w,curves) $owner]} {set state {valid 0 missing 1}} elseif {[dict get $ref kind] in {point control segment}&&[dict exists $ref topology_identity]&&[dict get $ref topology_identity] ne [_collectionTopologyIdentity $w $owner]} {dict set state valid 0}
                lappend states $state
            }
            dict set saved states $states;dict set st($w,selectionSets) $id states $states
        }
        dict set result $id $saved
    }
    return $result
}
proc ::GX::CurveWorkbench::_collectionCloseNative {w} {
    variable st
    foreach id [::GX::Native2D::core selection_set_list $st($w,scene)] {::GX::Native2D::core selection_set_delete $st($w,scene) $id}
    foreach id [::GX::Native2D::core layer_list $st($w,scene)] {::GX::Native2D::core layer_delete $st($w,scene) $id}
    set st($w,selectionSets) {};set st($w,layers) {};set st($w,layerNative) {}
}
proc ::GX::CurveWorkbench::_collectionSyncLayers {w} {
    variable st
    if {[::GX::Native2D::core drag_active $st($w,scene)]} return
    foreach receipt [::GX::Native2D::core layer_list $st($w,scene)] {
        if {$receipt ni [dict values $st($w,layerNative)]} {::GX::Native2D::core layer_delete $st($w,scene) $receipt}
    }
    dict for {id record} $st($w,curves) {::GX::Native2D::core object_style $st($w,scene) [dict get $record native] {layer 0}}
    dict for {id record} $st($w,layers) {
        if {[dict exists $st($w,layerNative) $id]} {set native [dict get $st($w,layerNative) $id];::GX::Native2D::core layer_update $st($w,scene) $native [dict get $record properties]} else {set receipt [::GX::Native2D::core layer_create $st($w,scene) [dict get $record properties]];set native [dict get $receipt id];dict set st($w,layerNative) $id $native}
        ::GX::Native2D::core identity_name $st($w,scene) $native [dict get $record name]
        foreach member [dict get $record members] {if {[dict exists $st($w,curves) $member]} {::GX::Native2D::core object_style $st($w,scene) [dict get [_record $w $member] native] [dict create layer $native]}}
    }
}
proc ::GX::CurveWorkbench::_curveVisible {w record} {
    variable st
    if {![dict get $record visible]} {return 0}
    if {![_coordinateInFrame $w $record]} {return 0}
    set style [::GX::Native2D::core object_style $st($w,scene) [dict get $record native]]
    if {[dict get $style layer]!=0&&![dict get [::GX::Native2D::core layer_info $st($w,scene) [dict get $style layer]] visible]} {return 0}
    dict for {id group} $st($w,groups) {if {[dict get $record id] in [dict get $group members]&&![dict get $group visible]} {return 0}}
    return 1
}
proc ::GX::CurveWorkbench::_collectionState {record} {
    foreach state [dict get $record states] {if {![dict get $state valid]} {return [expr {[dict get $state missing] ? "missing members" : "stale members"}]}}
    return current
}
proc ::GX::CurveWorkbench::_collectionRefresh {w} {
    variable st
    if {![winfo exists $w.collections.tree]} return
    set tree $w.collections.tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} [_collectionCaptureSets $w] {$tree insert {} end -id $id -values [list {Selection Set} $id [dict get $record name] [_collectionState $record] [_collectionDisplayRefs [dict get $record members]]]}
    dict for {id record} $st($w,layers) {$tree insert {} end -id $id -values [list Layer $id [dict get $record name] [expr {[dict get $record properties visible] ? "visible" : "hidden"}] [dict get $record members]]}
    _inspectionColumnsFit $tree;foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
}
proc ::GX::CurveWorkbench::_collectionOpen {w} {
    set d $w.collections
    if {[winfo exists $d]} {raise $d;_collectionRefresh $w;return}
    toplevel $d;wm title $d "Selection Sets and Layers";wm transient $d $w;wm geometry $d 1050x450
    ttk::label $d.help -text {Sets remember stable object/point/fragment references. Layers control presentation, independently of editing Groups. Names such as inlet or walls do not impose solver semantics. Stale point references require explicit rebind.} -wraplength 980 -padding 8
    bind $d.help <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $d.help %w];pack $d.help -side top -fill x
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label callback} [list set {Create Set…} [list _collectionForm $w set] rename {Rename Set…} [list _collectionMemberForm $w rename] add {Add member…} [list _collectionMemberForm $w add] member {Remove member…} [list _collectionMemberForm $w remove] layer {Create Layer…} [list _collectionForm $w layer] edit {Edit / Rebind…} [list _collectionForm $w edit] activate {Activate Set} [list _collectionActivate $w] toggle {Show / Hide Layer} [list _collectionToggle $w] remove Remove [list _collectionRemove $w]] {
        set callback [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]];ttk::button $d.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $callback];pack $d.actions.$key -side left -padx 4
    }
    ttk::button $d.actions.close -text Close -command [list destroy $d];pack $d.actions.close -side right;bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    ttk::frame $d.table;pack $d.table -fill both -expand 1
    ttk::treeview $d.tree -columns {type id name status members} -show headings -selectmode browse
    foreach key {type id name status members} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 160 -minwidth [expr {[font measure TkHeadingFont [string totitle $key]]+22}]}
    ttk::scrollbar $d.y -orient vertical -command [list $d.tree yview];ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview];$d.tree configure -yscrollcommand [list $d.y set] -xscrollcommand [list $d.x set]
    pack $d.x -in $d.table -side bottom -fill x;pack $d.y -in $d.table -side right -fill y;pack $d.tree -in $d.table -fill both -expand 1
    bind $d.tree <Configure> [list ::GX::CurveWorkbench::_inspectionColumnsSchedule $d.tree]
    bind $d <Escape> [list destroy $d];_collectionRefresh $w
}
proc ::GX::CurveWorkbench::_collectionSelected {w} {set selected [$w.collections.tree selection];if {[llength $selected]!=1} {error "Select one Set or Layer"};return [lindex $selected 0]}
proc ::GX::CurveWorkbench::_collectionForm {w kind} {
    variable st
    set id {};set initial [dict create name selection members {}]
    if {$kind eq "edit"} {set id [_collectionSelected $w];set kind [expr {[dict exists $st($w,layers) $id] ? "layer" : "set"}];set record [dict get $st($w,[expr {$kind eq "layer" ? "layers" : "selectionSets"}]) $id];dict set initial name [dict get $record name];dict set initial members [dict get $record members]}
    if {$kind eq "set"} {
        if {$id eq {}} {
            set refs {};set reverse [_logicalNativeMap $w]
            foreach member [_semanticMembers $w] {
                if {![dict get $member valid]} continue
                set refKind [dict get $member kind];set native [dict get $member id]
                if {$refKind eq "fragment"} {dict for {logical fragment} $st($w,sketchFragments) {if {[dict exists $fragment native]&&[dict get $fragment native]==$native} {lappend refs [dict create kind fragment id $logical];break}}} elseif {[dict exists $reverse $native]} {lappend refs [dict create kind $refKind id [dict get $reverse $native] index [dict get $member index]]}
            }
            dict set initial members $refs
        }
        set fields {name {type string label {Selection Set name}} members {type string label {Logical references: {kind object id curve1} / {kind point id curve1 index 0} / {kind fragment id fragment1}}}}
    } else {
        if {$id eq {}} {dict set initial members [_cadSelected $w];dict set initial name layer;dict set initial visible 1;dict set initial selectable 1;dict set initial locked 0;dict set initial opacity 1} else {set initial [dict merge $initial [dict get $record properties]]}
        set fields {name {type string label {Layer name}} members {type string label {Presentation member curve IDs (space separated)}} visible {type boolean label Visible} selectable {type boolean label Selectable} locked {type boolean label Locked} opacity {type number min 0 max 1 label Opacity}}
    }
    ::GX::uiFieldFormCreate $w.collectionForm "[string totitle $kind] — explicit logical membership" $fields $initial [list ::GX::CurveWorkbench::_collectionApply $w $st($w,token) $kind $id] $w.collections
}
proc ::GX::CurveWorkbench::_collectionApply {w token kind id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen collection parameters"}
    _cancelGesture $w;_pointSyncApply $w;set name [string trim [dict get $values name]];if {$name eq {}} {error "Enter a collection name"}
    set members [dict get $values members];if {$members eq {}} {error "Choose at least one member"}
    if {$kind eq "set"} {set members [_collectionStampRefs $w $members];set nativeRefs [_collectionNativeRefs $w $members]} else {foreach curve $members {_record $w $curve}}
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {
        if {$kind eq "set"} {
            if {$id eq {}||![dict exists $st($w,selectionSets) $id native]} {set receipt [::GX::Native2D::core selection_set_create $st($w,scene) $nativeRefs];if {$id eq {}} {set id "selectionSet[incr st($w,nextSelectionSet)]"}} else {set receipt [::GX::Native2D::core selection_set_update $st($w,scene) [dict get $st($w,selectionSets) $id native] $nativeRefs]}
            set native [dict get $receipt id];::GX::Native2D::core identity_name $st($w,scene) $native $name
            dict set st($w,selectionSets) $id [dict create id $id name $name native $native members $members states [lmap member [dict get $receipt members] {dict create valid 1 missing 0}]]
        } else {
            if {$id eq {}} {set id "layer[incr st($w,nextLayer)]"}
            set properties [dict remove $values name members];dict set properties order 0
            # One presentation layer per curve. Explicit reassignment removes
            # the curve from previous layer membership instead of duplicating it.
            dict for {other record} $st($w,layers) {if {$other eq $id} continue;dict set record members [lmap curve [dict get $record members] {if {$curve in $members} continue;set curve}];dict set st($w,layers) $other $record}
            dict set st($w,layers) $id [dict create id $id name $name properties $properties members [lsort -unique $members]];_collectionSyncLayers $w
        }
        _history $w $before {}
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _collectionRefresh $w;return $id
}
proc ::GX::CurveWorkbench::_collectionActivate {w} {
    variable st
    _cancelGesture $w;_pointSyncApply $w;set id [_collectionSelected $w]
    if {![dict exists $st($w,selectionSets) $id]} {error "Choose a Selection Set"}
    set record [dict get [_collectionCaptureSets $w] $id]
    if {[_collectionState $record] ne "current"} {error "Set contains stale/missing members; edit/rebind explicitly"}
    set native [dict get $st($w,selectionSets) $id native]
    # Named collections feed the same semantic authority as pointer selection.
    # No active-curve sampled scene or second selection mask is constructed.
    _semanticApply $w [_collectionNativeRefs $w [dict get $record members]]
    set curves {};foreach ref [dict get $record members] {
        if {[dict get $ref kind] eq "fragment"} {lappend curves [dict get $st($w,sketchFragments) [dict get $ref id] definition parent]} else {lappend curves [dict get $ref id]}
    }
    set st($w,active) [lindex $curves 0];set st($w,cadTool) none
    ::GX::Native2D::core gizmo $st($w,scene) {visible 0};_selectionScene $w

    _curveList $w;_pointList $w;_draw $w;_save $w
}
proc ::GX::CurveWorkbench::_collectionToggle {w} {
    variable st
    _cancelGesture $w;set id [_collectionSelected $w];if {![dict exists $st($w,layers) $id]} {error "Choose a Layer"}
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    dict set st($w,layers) $id properties visible [expr {![dict get $st($w,layers) $id properties visible]}]
    try {_collectionSyncLayers $w;_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _collectionRefresh $w
}
proc ::GX::CurveWorkbench::_collectionRemove {w} {
    variable st
    _cancelGesture $w;set id [_collectionSelected $w];set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {[dict exists $st($w,layers) $id]} {::GX::Native2D::core layer_delete $st($w,scene) [dict get $st($w,layerNative) $id];dict unset st($w,layerNative) $id;dict unset st($w,layers) $id} else {if {[dict exists $st($w,selectionSets) $id native]} {::GX::Native2D::core selection_set_delete $st($w,scene) [dict get $st($w,selectionSets) $id native]};dict unset st($w,selectionSets) $id}
    try {_history $w $before {}} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _collectionRefresh $w
}
rename ::GX::CurveWorkbench::_restoreSnapshot ::GX::CurveWorkbench::_restoreSnapshot_collections_base
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {_cancelGesture $w;_collectionCloseNative $w;_restoreSnapshot_collections_base $w $snapshot}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_collections_base
proc ::GX::CurveWorkbench::_changed {w} {_collectionSyncLayers $w;_changed_collections_base $w;_collectionRefresh $w}
proc ::GX::CurveWorkbench::_buildCollections {w} {
    variable st
    $w.cad.sketch.menu add command -label "Selection Sets / Layers…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_collectionOpen $w]]
}

proc ::GX::CurveWorkbench::_curvePresentationColor {w record color background} {
    variable st
    set style [::GX::Native2D::core object_style $st($w,scene) [dict get $record native]];set alpha [lindex [dict get $style color] 3]
    if {[dict get $style layer]} {set alpha [expr {$alpha*[dict get [::GX::Native2D::core layer_info $st($w,scene) [dict get $style layer]] opacity]}]}
    set rgba [::GX::uiFieldColorToRGBA $color];lset rgba 3 $alpha
    return [dict get [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA $rgba] $background] rgb]
}
proc ::GX::CurveWorkbench::_collectionTopologyIdentity {w id} {
    set record [_record $w $id]
    if {[dict exists $record sketch_definition]} {
        # Retained reference identity follows real topology. Display sampling
        # density and defining-coordinate edits cannot turn controls into rows.
        set definition [dict get $record sketch_definition]
        set description [dict create family [dict get $definition family] control_count [llength [dict get $definition controls]]]
        foreach key {closed segments} {if {[dict exists $definition $key]} {dict set description $key [dict get $definition $key]}}
    } else {
        set description [dict create count [_pointCount $record] representation [dict get $record representation]]
        if {[dict exists $record row_resource]} {dict set description rows_sha256 [dict get $record row_resource sha256]} else {dict set description point_ids [lmap point [dict get $record samples] {dict get $point point_id}]}
    }
    return [::GX::datasetStorageSha256Text [_session] $description]
}
proc ::GX::CurveWorkbench::_collectionStampRefs {w refs} {
    set result {}
    foreach ref $refs {if {[dict get $ref kind] in {point control segment}} {dict set ref topology_identity [_collectionTopologyIdentity $w [dict get $ref id]]};lappend result $ref}
    return $result
}
proc ::GX::CurveWorkbench::_collectionMemberForm {w action} {
    variable st
    set id [_collectionSelected $w];if {![dict exists $st($w,selectionSets) $id]} {error "Choose a Selection Set"}
    if {$action eq "rename"} {set fields {name {type string label {Selection Set name}}};set initial [dict create name [dict get $st($w,selectionSets) $id name]]} elseif {$action eq "remove"} {
        set count [llength [dict get $st($w,selectionSets) $id members]]
        if {$count<=1} {error "The last member requires Remove Set; empty sets are not retained"}
        set fields [dict create index [dict create type integer min 0 max [expr {$count-1}] label {Zero-based member ordinal to remove (see membership column)}]];set initial {index 0}
    } else {
        set targets [concat [dict keys $st($w,curves)] [dict keys $st($w,sketchFragments)]]
        set fields [dict create kind {type choice label {Reference kind} values {object point control segment fragment}} target [dict create type choice label {Logical geometry / fragment ID} values $targets] index {type integer min 0 label {Native reference index (point / control / segment)}}];set initial [dict create kind point target [_active $w] index [expr {[_selected $w] eq {} ? 0 : [lindex [_selected $w] 0]}]]
    }
    ::GX::uiFieldFormCreate $w.collectionMember "[string totitle $action] — preserve captured references" $fields $initial [list ::GX::CurveWorkbench::_collectionMemberApply $w $st($w,token) $id $action] $w.collections
}
proc ::GX::CurveWorkbench::_collectionMemberApply {w token id action values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen member parameters"}
    _cancelGesture $w;set record [dict get [_collectionCaptureSets $w] $id]
    if {[dict exists $st($w,selectionSets) $id native]} {dict set record native [dict get $st($w,selectionSets) $id native]}
    set before [_snapshotIds $w {}];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {
        if {$action eq "rename"} {
            set name [string trim [dict get $values name]];if {$name eq {}} {error "Enter a Set name"};dict set record name $name
            if {[dict exists $record native]} {::GX::Native2D::core identity_name $st($w,scene) [dict get $record native] $name}
        } elseif {$action eq "remove"} {
            set index [dict get $values index];set refs [dict get $record members]
            if {[llength $refs]<=1||$index<0||$index>=[llength $refs]} {error "Choose an existing member; use Remove Set for the last member"}
            if {[dict exists $record native]} {::GX::Native2D::core selection_set_remove_member $st($w,scene) [dict get $record native] $index}
            dict set record members [lreplace $refs $index $index];dict set record states [lreplace [dict get $record states] $index $index]
        } else {
            set kind [dict get $values kind];set ref [dict create kind $kind id [dict get $values target]]
            if {$kind in {point control segment}} {dict set ref index [dict get $values index]}
            set ref [lindex [_collectionStampRefs $w [list $ref]] 0];set nativeRefs [_collectionNativeRefs $w [list $ref]]
            foreach old [dict get $record members] {if {[dict get $old kind] eq $kind&&[dict get $old id] eq [dict get $ref id]&&($kind ni {point control segment}||[dict get $old index]==[dict get $ref index])} {error "That reference already belongs to this Set"}}
            if {[dict exists $record native]} {::GX::Native2D::core selection_set_add_member $st($w,scene) [dict get $record native] $nativeRefs} else {
                # Validate only the new member; existing stale references retain
                # their captured state and cannot be silently rebound.
                set receipt [::GX::Native2D::core selection_set_create $st($w,scene) $nativeRefs]
                ::GX::Native2D::core selection_set_delete $st($w,scene) [dict get $receipt id]
            }
            dict lappend record members $ref;dict lappend record states {valid 1 missing 0}
        }
        if {![dict exists $record native]&&[_collectionState $record] eq "current"} {
            set receipt [::GX::Native2D::core selection_set_create $st($w,scene) [_collectionNativeRefs $w [dict get $record members]]]
            dict set record native [dict get $receipt id];::GX::Native2D::core identity_name $st($w,scene) [dict get $receipt id] [dict get $record name]
        }
        dict set st($w,selectionSets) $id $record;_history $w $before {}
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    _collectionRefresh $w;return $id
}

proc ::GX::CurveWorkbench::_collectionDisplayRefs {refs} {
    set result {}
    foreach ref $refs {
        set kind [dict get $ref kind];set target [dict get $ref id]
        if {$kind eq "point"} {lappend result "$target point [dict get $ref index]"} elseif {$kind eq "fragment"} {lappend result "fragment $target"} else {lappend result $target}
    }
    return $result
}
