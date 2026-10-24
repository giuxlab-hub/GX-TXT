# SPDX-License-Identifier: GPL-3.0-or-later
# Workbench command dispatch and atomic object workflows. Geometry, Dataset
# bindings, history and user preferences retain their existing CORE owners.
proc ::GX::CurveWorkbench::_commandSelection {w} {
    variable st
    _semanticSync $w
    if {$st($w,objectSelection) eq {}} {error {Select one or more objects.}}
    return $st($w,objectSelection)
}
proc ::GX::CurveWorkbench::_deleteCurve {w} {
    variable st
    set ids [_commandSelection $w];set before [_snapshotIds $w $ids]

    try {
        foreach id $ids {_removeRecord $w $id}
        _semanticApply $w {} add
        if {$st($w,active) eq {}} {set st($w,active) [lindex [dict keys $st($w,curves)] 0]}
        _selectionScene $w;_history $w $before $ids
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
    set st($w,status) "Deleted [llength $ids] selected objects."
}
proc ::GX::CurveWorkbench::_duplicate {w} {
    variable st
    set parents [_commandSelection $w];set before [_snapshotIds $w {}]
    set ids {};set members {}
    foreach parent $parents {_sourceSnapshotRequire $w [_record $w $parent]}
    try {
        foreach parent $parents {
            set record [_record $w $parent];set id [_newId $w];dict set before $id {}
            # _persistCurve discards Dataset acceleration caches; _addRecord
            # reopens that canonical binding or reconstructs the exact sketch.
            set copy [_persistCurve $w $record]
            dict set copy id $id;dict set copy name "[dict get $record name] copy"
            dict set copy parents [list $parent]
            dict lappend copy operations [dict create operation duplicate source_object $parent]
            if {[dict get $record source] eq {}||[dict get $record edited]} {dict set copy locked 0}
            _addRecord $w $copy
            lappend ids $id;lappend members [dict create kind object id [dict get [_record $w $id] native] index 0]
        }
        _semanticApply $w $members
        set st($w,active) [lindex $ids 0];_selectionScene $w
        _history $w $before $ids
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
    set st($w,status) "Duplicated [llength $ids] objects; exact retained definitions and Dataset bindings preserved."
}
proc ::GX::CurveWorkbench::_reverseSelection {w} {
    variable st
    set ids [_commandSelection $w]
    foreach id $ids {
        set record [_record $w $id]
        if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] in {point construction_line}} {error {Select finite curves with a traversal direction. No objects changed.}}
    }
    set before [_snapshotIds $w $ids];
    try {
        foreach id $ids {
            set native [dict get [_record $w $id] native]
            set marker [::GX::Native2D::core direction_marker $st($w,scene) $native]
            ::GX::Native2D::core direction_marker $st($w,scene) $native [dict create forward [expr {![dict get $marker forward]}]]
        }
        _history $w $before $ids
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
    set st($w,status) "Reversed the intended traversal of [llength $ids] objects. Publication follows this direction; definitions and source data are preserved."
}
proc ::GX::CurveWorkbench::_setVisibility {w {visible {}}} {
    variable st
    set ids [_commandSelection $w]
    if {$visible eq {}} {set visible 1;foreach id $ids {if {[dict get [_record $w $id] visible]} {set visible 0;break}}}
    _objectFlag $w $ids visible $visible
    set st($w,status) "[expr {$visible?"Shown":"Hidden"}] [llength $ids] selected objects."
}
proc ::GX::CurveWorkbench::_setLock {w {locked {}}} {
    variable st
    set ids [_commandSelection $w]
    if {$locked eq {}} {set locked 1;foreach id $ids {if {[dict get [_record $w $id] locked]} {set locked 0;break}}}
    if {!$locked} {
        foreach id $ids {
            set record [_record $w $id]
            if {[dict get $record source] ne {}&&![dict get $record edited]} {error {The selection contains an immutable Dataset binding. Use Representation > Dataset to retained geometry (review) before unlocking. No objects changed.}}
        }
    }
    _objectFlag $w $ids locked $locked
    set st($w,status) "[expr {$locked?"Locked":"Unlocked"}] [llength $ids] selected objects."
}
proc ::GX::CurveWorkbench::_objectFlag {w ids flag value} {
    variable st
    set before [_snapshotIds $w $ids];
    try {
        foreach id $ids {
            set record [_record $w $id]
            ::GX::Native2D::core $flag $st($w,scene) [dict get $record native] $value
            dict set record $flag $value;dict set st($w,curves) $id $record
        }
        _history $w $before $ids
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
}
proc ::GX::CurveWorkbench::_commandRegister {w id label shortcut requirement handler {icon {}}} {
    variable st
    dict set st($w,commands) $id [dict create label $label default_shortcut $shortcut shortcut $shortcut requirement $requirement handler $handler icon $icon]
}
proc ::GX::CurveWorkbench::_commandEnabled {w id} {
    variable st
    if {$st($w,publishBusy)||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {return 0}
    set requirement [dict get $st($w,commands) $id requirement]
    switch $requirement {
        selection {return [expr {[llength $st($w,objectSelection)]>0}]}
        undo - redo {
            if {![info exists st($w,historyReady)] || !$st($w,historyReady)} {return 0}
            set state [::GX::scientificHistoryViewerStatus $w]
            if {[_historyBrowsing $w]} {
                set index [dict get [::GX::scientificHistoryViewerRestoreContext $w] cursor]
                return [expr {$requirement eq {undo} ? $index>0 : $index<[dict get $state count]}]
            }
            return [expr {$requirement eq {undo} ? [dict get $state cursor]>0 : [dict get $state cursor]<[dict get $state count]}]
        }
        default {return 1}
    }
}
proc ::GX::CurveWorkbench::_commandInvoke {w id} {
    variable st
    _semanticSync $w
    if {![_commandEnabled $w $id]} {_notice $w {Command unavailable: select the required objects or finish the current operation.};return}
    _safe $w [dict get $st($w,commands) $id handler] 1
}
proc ::GX::CurveWorkbench::_commandMenu {w menu ids} {
    variable st
    $menu delete 0 end
    foreach id $ids {
        if {$id eq "-"} {$menu add separator;continue}
        set command [dict get $st($w,commands) $id]
        if {[dict exists $command submenu]} {
            $menu add cascade -label [dict get $command label] -menu [dict get $command submenu] -state [expr {[_commandEnabled $w $id]?"normal":"disabled"}]
            continue
        }
        $menu add command -label [dict get $command label] -accelerator [dict get $command shortcut] -state [expr {[_commandEnabled $w $id]?"normal":"disabled"}] -command [list ::GX::CurveWorkbench::_commandInvoke $w $id]
    }
}
proc ::GX::CurveWorkbench::_objectContextMenu {w X Y} {
    set menu $w.objectContext
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    _commandMenu $w $menu {object.select - object.duplicate object.delete object.split object.reverse - object.join object.combine object.separate - object.show object.hide object.lock object.unlock - object.publish object.promote - view.fit_selection}
    ::GX::uiMenuPopup $menu $X $Y
}
proc ::GX::CurveWorkbench::_installCommands {w} {
    variable st
    set st($w,commands) {}
    bind $w.right.viewport.canvas <Key-d> {}
    bind $w.right.viewport.canvas <Delete> {}
    foreach {id label key requirement handler icon} [_commandRows] {
        set handler [linsert [lreplace $handler 0 0 ::GX::CurveWorkbench::[lindex $handler 0]] 1 $w]
        _commandRegister $w $id $label $key $requirement $handler $icon
    }
    foreach {family label shortcut} [_creationRows] {
        _commandRegister $w create.$family $label $shortcut none [list ::GX::CurveWorkbench::_sketchTool $w $family]
    }
    dict for {group kinds} [_constraintGroups] {
        foreach kind $kinds {
            _commandRegister $w constraint.$kind [_constraintTitle $kind] {} selection [list ::GX::CurveWorkbench::_constraintSimple $w $kind]
            if {$group ne "Dimensional"} {_commandRegister $w constraint.start.$kind "Start [_constraintTitle $kind]" {} none [list ::GX::CurveWorkbench::_constraintStart $w $kind]}
        }
    }
    set menu $w.toolbar.objects.menu
    $menu configure -postcommand [list ::GX::CurveWorkbench::_commandMenu $w $menu {object.select - object.duplicate object.delete object.split object.reverse - object.join object.combine object.separate - object.show object.hide object.lock object.unlock - object.publish object.promote - object.selectable object.reference}]
    foreach widget {undo redo} id {history.undo history.redo} {$w.toolbar.$widget configure -command [list ::GX::CurveWorkbench::_commandInvoke $w $id]}
    $w.sketchbar.select configure -command [list ::GX::CurveWorkbench::_commandInvoke $w select]
    $w.sketchbar.dimension configure -command [list ::GX::CurveWorkbench::_commandInvoke $w constraint.dimension]
    $w.toolbar.workspace.menu insert 0 command -label [dict get $st($w,commands) workspace.save label] -accelerator [dict get $st($w,commands) workspace.save shortcut] -command [list ::GX::CurveWorkbench::_commandInvoke $w workspace.save]
    # Retain every existing publication choice/callback. The registered
    # object.publish command remains the separate-output operation and its
    # enabled-state owner; the menu entry now exposes all choices as a cascade.
    set publication $w.toolbar.objects.menu.publish
    menu $publication -tearoff 0
    set source $w.publish.batch.menu
    for {set i 0} {$i<=[$source index end]} {incr i} {
        set callback [$source entrycget $i -command]
        if {[lindex [lindex $callback end] 0] eq {::GX::CurveWorkbench::_publishBatchOpen}} {set callback [list ::GX::CurveWorkbench::_commandInvoke $w object.publish]}
        $publication add command -label [$source entrycget $i -label] -command $callback
    }
    dict set st($w,commands) object.publish submenu $publication
    $w.toolbar.settings.menu add command -label {Publication settings…} -command [$w.publish.options cget -command]
    destroy $w.publish
    $w.sketchbar.create.menu configure -postcommand [list ::GX::CurveWorkbench::_commandMenu $w $w.sketchbar.create.menu {create.line create.rectangle create.circle create.arc create.spline create.quadratic_bezier create.cubic_bezier create.polyline create.ellipse create.point create.construction_line - create.numeric create.scientific}]
    $w.sketchbar.modify.menu configure -postcommand [list ::GX::CurveWorkbench::_commandMenu $w $w.sketchbar.modify.menu {transform.translate transform.rotate object.parameters object.units object.declare_axes object.spline_line - object.duplicate object.reverse object.split - object.join object.combine object.separate - object.native_tools}]
}

proc ::GX::CurveWorkbench::_shortcutsValidate {w overrides} {return [_shortcutSettingsValidate $overrides]}
proc ::GX::CurveWorkbench::_shortcutsLoad {w} {
    set bindings [dict get [::GX::configurationResolve modules.curve_workbench.shortcuts] effective]
    _shortcutsInstall $w [_shortcutSettingsValidate $bindings]
}
proc ::GX::CurveWorkbench::_shortcutsInstall {w bindings} {
    variable st
    dict for {id shortcut} $bindings {dict set st($w,commands) $id shortcut $shortcut}
    if {![dict exists $::GX::ViewerCommands::windows $w]} {
        set handlers {}
        foreach id [dict keys $bindings] {
            dict set handlers $id [dict create command [list ::GX::CurveWorkbench::_commandInvoke $w $id] enabled [list ::GX::CurveWorkbench::_commandEnabled $w $id]]
        }
        ::GX::viewerCommandsAttach $w viewer.curve_workbench $handlers {} [list $w.right.viewport.canvas $w.leftScroll.viewport.content.curves]
    }
}
proc ::GX::CurveWorkbench::_commandKey {w key state} {
    return [::GX::viewerCommandKey $w [focus] $key $state]
}
proc ::GX::CurveWorkbench::_shortcutsOpen {w} {
    ::GX::configurationModuleDialog viewer.curve_workbench $w
}
proc ::GX::CurveWorkbench::_shortcutsApply {w values} {
    set id modules.curve_workbench.shortcuts
    ::GX::configurationCommit [list [dict create id $id scope user value $values expected [::GX::configurationGet $id]]]
    _shortcutsLoad $w
}
proc ::GX::CurveWorkbench::_shortcutsDefaults {w} {_shortcutsApply $w {}}
proc ::GX::CurveWorkbench::_settingsChanged {w id} {
    if {$id eq "modules.curve_workbench.shortcuts" && [winfo exists $w]} {_shortcutsLoad $w}
}
proc ::GX::CurveWorkbench::_commandTooltip {w widget id} {
    variable st
    set command [dict get $st($w,commands) $id];set label [dict get $command label]
    if {[dict get $command shortcut] ne {}} {append label " ([dict get $command shortcut])"}
    if {$id eq "select"} {append label " — [expr {$st($w,selectionTarget) eq "object"?"Entire Curve / Path":"Local Geometry"}]; right-click to choose mode."}
    ::GX::native2DViewportTooltipShow $widget $label
}
proc ::GX::CurveWorkbench::_transformStart {w {mode {}}} {
    variable st
    _sketchIdle $w
    if {$mode ne {}} {set st($w,transformMode) $mode}
    if {![info exists st($w,transformMode)]} {set st($w,transformMode) translate}
    set st($w,cadTool) $st($w,transformMode)
    _cadToolChoice $w
    set st($w,toolLabel) "[string totitle $st($w,transformMode)] — drag gizmo handles; drag its center to place the pivot. Escape selects."
    focus $w.right.viewport.canvas
}
proc ::GX::CurveWorkbench::_toolPopup {w kind X Y} {
    set menu $w.toolContext
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    if {$kind eq "select"} {
        variable st
        $menu delete 0 end
        foreach {label target} {{Local Geometry Selection (default)} local {Select Entire Curve / Path} object} {
            $menu add radiobutton -label $label -variable ::GX::CurveWorkbench::st($w,selectionTarget) -value $target -command [list ::GX::CurveWorkbench::_commandInvoke $w select.$target]
        }
        $menu add separator
        foreach id {select.window select.polygon} {
            set command [dict get $st($w,commands) $id]
            $menu add command -label [dict get $command label] -command [list ::GX::CurveWorkbench::_commandInvoke $w $id]
        }
    } else {_commandMenu $w $menu {transform.translate transform.rotate}}
    ::GX::uiMenuPopup $menu $X $Y
}
proc ::GX::CurveWorkbench::_installCommandTools {w} {
    variable st
    _commandRegister $w transform {Transform / pivot} m none [list ::GX::CurveWorkbench::_transformStart $w] transform
    _commandRegister $w transform.translate Translate {} none [list ::GX::CurveWorkbench::_transformStart $w translate]
    _commandRegister $w transform.rotate Rotate {} none [list ::GX::CurveWorkbench::_transformStart $w rotate]
    foreach id {select transform} {
        # Reuse the shared icon toolbar's buttons; no second command copy is
        # created in either mixed/text toolbar.
        set widget [::GX::native2DViewportPanelWidget $w.right.viewport.canvas controls].body.$id
        $widget configure -command [list ::GX::CurveWorkbench::_commandInvoke $w $id]
        bind $widget <Button-3> [list ::GX::CurveWorkbench::_toolPopup $w $id %X %Y]
        bind $widget <Enter> [list ::GX::CurveWorkbench::_commandTooltip $w $widget $id]
        # native2DViewportTooltipShow installs the shared target lifecycle.
        # Keep its ownership instead of destroying its window independently.
    }
    set pan [::GX::native2DViewportPanelWidget $w.right.viewport.canvas controls].body.pan
    bind $pan <Enter> [list ::GX::CurveWorkbench::_commandTooltip $w $pan view.pan]
    pack forget $w.right.readout.coordinates
    ttk::label $w.right.readout.tool -textvariable ::GX::CurveWorkbench::st($w,toolLabel) -anchor w
    pack $w.right.readout.coordinates -in $w.right.readout -side right -padx 5
    pack $w.right.readout.tool -in $w.right.readout -side left -fill x -expand 1
    bind $w.right.readout <Configure> [list ::GX::CurveWorkbench::_readoutLayout $w %w]
    $w.toolbar.settings.menu add separator
    $w.toolbar.settings.menu add command -label {Keyboard shortcuts…} -command [list ::GX::CurveWorkbench::_shortcutsOpen $w]
    $w.toolbar.settings.menu add command -label {Restore default shortcuts} -command [list ::GX::CurveWorkbench::_shortcutsDefaults $w]
    _shortcutsLoad $w
    set st($w,configurationSubscription) [::GX::configurationSubscribe [list ::GX::CurveWorkbench::_settingsChanged $w]]
    _commandLayout $w [winfo width $w.toolbar]
}

# Wrap the tool instruction beside coordinates rather than clipping it.
proc ::GX::CurveWorkbench::_readoutLayout {w width} {
    if {![winfo exists $w.right.readout.tool]} return
    set wrap [expr {max(100,$width-[winfo reqwidth $w.right.readout.coordinates]-20)}]
    if {[$w.right.readout.tool cget -wraplength]!=$wrap} {$w.right.readout.tool configure -wraplength $wrap}
}
