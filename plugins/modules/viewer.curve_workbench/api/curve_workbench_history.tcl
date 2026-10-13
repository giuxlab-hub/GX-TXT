# SPDX-License-Identifier: GPL-3.0-or-later
# Timeline is a projection of Scientific Recipe patches. Native reconstruction,
# CORE parameter contexts and Interactive Documents remain authoritative.
proc ::GX::CurveWorkbench::_timelineState {w index} {
    variable st
    set record $st($w,scientificRecipe)
    if {$record eq {}} {return [_recipeState $w]}
    set steps [dict get $record steps]
    if {![string is integer -strict $index]||$index<0||$index>[llength $steps]} {error {History index is outside the retained timeline.}}
    set state [dict get $record base]
    for {set i 0} {$i<$index} {incr i} {set state [::GX::scientificRecipeApplyPatch $state [dict get [lindex $steps $i] patch]]}
    return $state
}
proc ::GX::CurveWorkbench::_timelineBuild {w} {
    variable st
    $w.toolbar.workspace.menu add command -label {Clear History…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_clearHistory $w]]
    set st($w,historyBrowsing) 0;set st($w,historyCursor) -1;set st($w,historyExpanded) {};set st($w,stripVisible) 1;set st($w,stripView) Description
    set height [expr {[winfo reqheight $w.status]+10}]
    pack forget $w.status
    ttk::frame $w.strip -height $height
    pack propagate $w.strip 0
    pack $w.strip -side bottom -fill x -before $w.main
    ttk::combobox $w.strip.choice -values {Description History} -state readonly -width 12 -textvariable ::GX::CurveWorkbench::st($w,stripView)
    pack $w.strip.choice -side left -fill y
    pack $w.status -in $w.strip -side left -fill x -expand 1;raise $w.status
    canvas $w.strip.timeline -height [expr {$height-2}] -highlightthickness 0 -background #edf1f5
    bind $w.strip.choice <<ComboboxSelected>> [list ::GX::CurveWorkbench::_timelineSwitch $w]
    bind $w.strip.timeline <Button-1> [list ::GX::CurveWorkbench::_timelineClick $w %x %y]
    bind $w.strip.timeline <Button-3> [list ::GX::CurveWorkbench::_timelineContext $w %x %y %X %Y]
    bind $w.strip.timeline <Button-4> [list $w.strip.timeline xview scroll -3 units]
    bind $w.strip.timeline <Button-5> [list $w.strip.timeline xview scroll 3 units]
    $w.strip.timeline configure -xscrollincrement 20
    $w.toolbar.settings.menu add checkbutton -label {Show Description / History strip} -variable ::GX::CurveWorkbench::st($w,stripVisible) -command [list ::GX::CurveWorkbench::_timelineShow $w]
    _timelineRender $w
}
proc ::GX::CurveWorkbench::_timelineShow {w} {
    variable st
    if {$st($w,stripVisible)} {pack $w.strip -side bottom -fill x -before $w.main} else {pack forget $w.strip}
}
proc ::GX::CurveWorkbench::_timelineSwitch {w} {
    variable st
    pack forget $w.status $w.strip.timeline
    if {$st($w,stripView) eq "History"} {pack $w.strip.timeline -fill both -expand 1;_timelineRender $w} else {pack $w.status -in $w.strip -fill both -expand 1;raise $w.status}
}
proc ::GX::CurveWorkbench::_timelineKind {before after step} {
    set old [::GX::datasetPublicationV2DictDefault [dict get $before @cad] constraints {}]
    set new [::GX::datasetPublicationV2DictDefault [dict get $after @cad] constraints {}]
    if {$old ne $new} {return [expr {[dict size $new]>[dict size $old]?"constraint_add":"constraint_edit"}]}
    if {[::GX::datasetPublicationV2DictDefault [dict get $before @cad] parameter_definitions {}] ne [::GX::datasetPublicationV2DictDefault [dict get $after @cad] parameter_definitions {}]} {return parameter}
    if {[dict size $after]>[dict size $before]} {return create}
    if {[dict size $after]<[dict size $before]} {return delete}
    set operations [dict get $step parameters];set names {}
    dict for {id list} $operations {if {[llength $list]} {set last [lindex $list end];if {[catch {dict size $last}]} {lappend names [lindex $last 0]} else {lappend names [::GX::datasetPublicationV2DictDefault $last operation edit]}}}
    set names [lsort -unique $names]
    if {[llength $names]==1} {return [lindex $names 0]}
    return edit
}
proc ::GX::CurveWorkbench::_timelineRender {w} {
    variable st
    if {![winfo exists $w.strip.timeline]} return
    set c $w.strip.timeline;$c delete all
    set record $st($w,scientificRecipe);set groups {};set index 0;set previousKind {}
    if {$record ne {}} {
        set before [dict get $record base]
        foreach step [dict get $record steps] {
            incr index;set after [::GX::scientificRecipeApplyPatch $before [dict get $step patch]]
            set kind [_timelineKind $before $after $step]
            # Only consecutive operations with the same semantic class group.
            if {$kind eq $previousKind&&$kind in {create constraint_add translate rotate scale}} {
                set group [lindex $groups end];lappend group $index;lset groups end $group
            } else {lappend groups [list $kind $index]}
            set previousKind $kind;set before $after
        }
    }
    set st($w,historyCount) $index
    if {!$st($w,historyBrowsing)} {set st($w,historyCursor) $index}
    set groups [linsert $groups 0 [list base 0]]
    set lane [expr {max(24,[font metrics TkDefaultFont -linespace]+8)}]
    $w.strip configure -height [expr {max($lane+4,[winfo reqheight $w.strip.choice]+2)}]
    set x 3
    foreach group $groups {
        set kind [lindex $group 0];set members [lrange $group 1 end]
        set first [lindex $members 0];set last [lindex $members end]
        if {$first in $st($w,historyExpanded)} {set sets [lmap member $members {list $member}]} else {set sets [list $members]}
        foreach set $sets {
            set target [lindex $set end]
            set color [expr {$target>$st($w,historyCursor)?"#a8b0ba":"#213c57"}]
            set fill [expr {$target==$st($w,historyCursor)?"#c5dff4":"#edf1f5"}]
            set tag step$target
            $c create rectangle $x 1 [expr {$x+47}] [expr {$lane-1}] -fill $fill -outline #c7cdd5 -tags [list $tag]
            set symbol [expr {$kind eq "create"?"+":$kind eq "delete"?"−":$kind eq "constraint_add"?"⊥":$kind eq "parameter"?"ƒ":$kind eq "base"?"○":"↔"}]
            $c create text [expr {$x+23}] [expr {$lane/2}] -text "$symbol [expr {[llength $set]>1?"[llength $set]×":$target}]" -fill $color -tags [list $tag]
            set st($w,timeline,$target) [dict create kind $kind members $set group $first]
            $c bind $tag <Enter> [list set ::GX::CurveWorkbench::st($w,status) "History $kind: steps [join $set {, }]. Click to inspect; right-click for members or explicit restart."]
            incr x 51
        }
    }
    $c configure -scrollregion [list 0 0 $x $lane]
}
proc ::GX::CurveWorkbench::_timelineHit {w x y} {
    set c $w.strip.timeline
    set item [$c find closest [$c canvasx $x] [$c canvasy $y]]
    foreach tag [$c gettags $item] {if {[regexp {^step([0-9]+)$} $tag -> index]} {return $index}}
    return -1
}
proc ::GX::CurveWorkbench::_timelineClick {w x y} {
    set index [_timelineHit $w $x $y]
    if {$index>=0} {_safe $w [list ::GX::CurveWorkbench::_timelineBrowse $w $index] 1}
}
proc ::GX::CurveWorkbench::_timelineBrowse {w index} {
    variable st
    _cancelGesture $w
    set record $st($w,scientificRecipe);if {$record eq {}} return
    set count [llength [dict get $record steps]]
    if {!$st($w,historyBrowsing)} {set st($w,historyLive) [_recipeState $w]}
    set wasBrowsing $st($w,historyBrowsing)
    set previous [_recipeState $w];set oldCursor $st($w,historyCursor)
    set st($w,historyBrowsing) 1;set st($w,historyRestoring) 1
    set desired [_timelineState $w $index]
    try {
        _recipeValidate [dict create base $desired steps {}]
        set token [_parameterBind $w]
        set parameters [::GX::datasetPublicationV2DictDefault [dict get $desired @cad] parameter_definitions [::GX::parameterDefinitions $token]]
        ::GX::parameterReadView $token $parameters [::GX::datasetPublicationV2DictDefault [dict get $desired @cad] session_parameters [::GX::parameterSessionDefinitions]]
        _recipeApplyState $w [dict create base $desired steps {}]
        set st($w,historyCursor) $index
        if {$index==$count} {
            _recipeApplyState $w [dict create base $st($w,historyLive) steps {}]
            ::GX::parameterReadViewClose $token
            set st($w,historyBrowsing) 0
        }
    } on error {message options} {
        if {$wasBrowsing} {::GX::parameterReadView $token [dict get $previous @cad parameter_definitions] [::GX::datasetPublicationV2DictDefault [dict get $previous @cad] session_parameters {}]} else {::GX::parameterReadViewClose $token}
        _recipeApplyState $w [dict create base $previous steps {}]
        set st($w,historyBrowsing) $wasBrowsing
        set st($w,historyCursor) $oldCursor
        return -options $options $message
    } finally {unset -nocomplain st($w,historyRestoring);set st($w,scientificRecipe) $record}
    _curveList $w;_pointList $w;_draw $w;_timelineRender $w
    set st($w,status) "History: $index / $count. Browsing preserves the saved Workspace and all future steps."
}
proc ::GX::CurveWorkbench::_timelineRestart {w index} {
    variable st
    if {$index>=$st($w,historyCount)} return
    if {[tk_messageBox -parent $w -type okcancel -icon warning -title {Restart from History} -message "Discard all [expr {$st($w,historyCount)-$index}] future history steps and restart editing at step $index? The saved Workspace will change."] ne "ok"} return
    set desired [_timelineState $w $index]
    if {[dict exists $desired @cad session_parameters]&&[dict get $desired @cad session_parameters] ne [::GX::parameterSessionDefinitions]} {error {Historical Session parameters differ from the live shared scope. Restore or reconcile them explicitly before restarting; no other Workspace will be changed implicitly.}}
    _timelineBrowse $w $index
    set record $st($w,scientificRecipe);set desired [_timelineState $w $index]
    set previous $st($w,historyLive)
    set savedPayload [dict get [::GX::interactiveDocumentRead $st($w,document)] payload]
    set st($w,historyRestoring) 1
    try {
        ::GX::parameterReadViewClose [_parameterBind $w]
        dict set st($w,scientificRecipe) steps [lrange [dict get $record steps] 0 [expr {$index-1}]]
        if {$index==0} {dict set st($w,scientificRecipe) steps {}}
        set st($w,historyBrowsing) 0
        ::GX::_parameterWrite [_parameterBind $w] [::GX::datasetPublicationV2DictDefault [dict get $desired @cad] parameter_definitions {}]
        set st($w,undo) {};set st($w,redo) {}
        _save $w
    } on error {message options} {
        set st($w,scientificRecipe) $record
        set st($w,historyBrowsing) 0
        ::GX::parameterReadViewClose [_parameterBind $w]
        catch {::GX::interactiveDocumentUpdate $st($w,document) $savedPayload}
        _recipeApplyState $w [dict create base $previous steps {}]
        return -options $options $message
    } finally {unset -nocomplain st($w,historyRestoring)}
    _timelineRender $w
}
proc ::GX::CurveWorkbench::_timelineContext {w x y X Y} {
    variable st
    set index [_timelineHit $w $x $y];if {$index<0} return
    set data $st($w,timeline,$index);set m $w.timelineMenu;catch {destroy $m};menu $m -tearoff 0
    $m add command -label "Inspect step $index" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_timelineBrowse $w $index] 1]
    $m add command -label {Return to latest state} -command [list ::GX::CurveWorkbench::_timelineBrowse $w $st($w,historyCount)]
    if {[llength [dict get $data members]]>1} {$m add command -label {Expand individual operations} -command [list ::GX::CurveWorkbench::_timelineExpand $w [dict get $data group]]}
    foreach member [dict get $data members] {$m add command -label "Step $member — [dict get $data kind]" -command [list ::GX::CurveWorkbench::_timelineBrowse $w $member]}
    foreach member [dict get $data members] {
        foreach id [_timelineConstraints $w $member] {
            foreach {action title} {inspect {Select / inspect} edit {Restart here, then edit} remove {Restart here, then remove}} {
                $m add command -label "$title constraint $id (step $member)…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_timelineConstraint $w $member $id $action] 1]
            }
        }
    }
    $m add separator
    $m add command -label {Inspect constraints / dimensions…} -command [list ::GX::CurveWorkbench::_constraintOpen $w]
    $m add command -label {Restart editing here; discard future…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_timelineRestart $w $index] 1]
    ::GX::uiMenuPopup $m $X $Y
}
proc ::GX::CurveWorkbench::_timelineExpand {w first} {variable st;lappend st($w,historyExpanded) $first;_timelineRender $w}

proc ::GX::CurveWorkbench::_clearHistoryPreflight {w} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen the Workspace}}
    if {$st($w,publishBusy) || $st($w,document) eq {}} {error {Save the Workspace and finish publication before clearing History}}
    foreach key {historyBrowsing restoreFailed importTransaction} {
        if {[info exists st($w,$key)] && $st($w,$key)} {error {Return to Latest and finish source restore before clearing History}}
    }
    foreach key {drag pointDrag directionDrag annotationDrag handleDrag tangentDrag cadDrag toolPoints toolPreview calibrationPoints} {
        if {[info exists st($w,$key)] && $st($w,$key) ne {}} {error {Finish or cancel the active gesture before clearing History}}
    }
    foreach scene [list $st($w,scene) $st($w,selectionScene)] {
        if {$scene ne {} && [::GX::Native2D::core drag_active $scene]} {error {Finish the active drag before clearing History}}
    }
    set doc [::GX::interactiveDocumentRead $st($w,document)]
    if {[dict get $doc module_id] ne "viewer.curve_workbench" || [dict get $doc generation] ne $st($w,ownerGeneration)} {error {Workspace owner was replaced}}
    if {[info exists st($w,ownerRevision)] && [dict get $doc revision] ne $st($w,ownerRevision) && [dict remove [dict get $doc payload] workspace_metadata] ne $st($w,ownerPayload)} {error {Workspace changed in another editor; reopen before clearing History}}
    set state [_recipeState $w]
    set candidate [::GX::scientificRecipeRebase $st($w,scientificRecipe) $state [dict create owner viewer.curve_workbench document_id $st($w,document) retention complete]]
    return [dict create candidate $candidate state $state document $doc]
}
proc ::GX::CurveWorkbench::_clearHistory {w} {
    variable st
    set preflight [_clearHistoryPreflight $w]
    set answer [tk_messageBox -parent $w -type yesnocancel -default cancel -icon warning -title {Clear History} -message {Previous History navigation and Undo/Redo will be permanently discarded. All current curves, exact geometry, constraints, parameters, images, styles, selections, view, Dataset bindings and notes are preserved.

Yes: clear History now.
No: export a protected Workspace backup first, then return here.
Cancel: leave everything unchanged.}]
    if {$answer eq "cancel"} return
    if {$answer eq "no"} {::GX::sessionWorkspaceDialog $w;set st($w,status) {Use Export to save a protected Workspace copy, then choose Clear History again.};return}
    _clearHistoryCommit $w $preflight
}
proc ::GX::CurveWorkbench::_clearHistoryCommit {w preflight} {
    variable st
    set current [_clearHistoryPreflight $w]
    foreach field {revision generation} {
        if {[dict get $current document $field] ne [dict get $preflight document $field]} {error {Workspace changed while confirming; History was preserved}}
    }
    if {[dict get $current state] ne [dict get $preflight state]} {error {Scientific state changed while confirming; History was preserved}}
    set previous $st($w,scientificRecipe);set undo $st($w,undo);set redo $st($w,redo)
    try {
        set st($w,scientificRecipe) [dict get $preflight candidate]
        set st($w,undo) {};set st($w,redo) {}
        _save $w
    } on error {message options} {
        set doc [::GX::interactiveDocumentRead $st($w,document)]
        if {[dict get $doc revision] eq [dict get $preflight document revision]} {
            set st($w,scientificRecipe) $previous;set st($w,undo) $undo;set st($w,redo) $redo
            return -options $options $message
        }
        # A postcommit auxiliary failure cannot roll back only the live history.
        set st($w,status) "History reset committed; auxiliary save warning: $message"
    }
    if {[catch {
        ::GX::workbenchRecoveryCheckpoint $st($w,document) [dict create operation clear_history]
        ::GX::workbenchRecoveryMarkSaved $st($w,document)
    } message]} {set st($w,recoveryNotice) "History reset committed; recovery checkpoint warning: $message"}
    set st($w,historyExpanded) {};set st($w,historyCursor) 0
    unset -nocomplain st($w,historyLive)
    _timelineRender $w
    set st($w,status) {History cleared. Current scientific state preserved; new edits start at this checkpoint.}
    return [dict create status committed retained_steps 0 document_id $st($w,document)]
}
proc ::GX::CurveWorkbench::_replaceDecision {w} {
    variable st
    if {$st($w,historyBrowsing)} {_timelineBrowse $w $st($w,historyCount)}
    if {$st($w,document) eq {}} {return 1}
    set recovery [::GX::workbenchRecoveryInspect $st($w,document)]
    if {[dict get $recovery status] eq "clean"} {return 1}
    set answer [tk_messageBox -parent $w -type yesnocancel -default cancel -icon question -title {Save current Workspace?} -message {Yes: Save, then continue.
No: discard unsaved changes and restore the last saved state.
Cancel: keep the existing Workbench open.}]
    if {$answer eq "cancel"} {return 0}
    if {$answer eq "yes"} {_saveExplicit $w;return 1}
    if {[tk_messageBox -parent $w -type okcancel -default cancel -icon warning -message {Discard the unsaved changes in this Workspace?}] ne "ok"} {return 0}
    ::GX::workbenchRecoveryResolve $st($w,document) saved
    set payload [dict get [::GX::interactiveDocumentRead $st($w,document)] payload]
    set snapshot [dict get $payload curves];dict set snapshot @cad [dict get $payload cad_workspace]
    foreach id [dict keys $st($w,curves)] {if {![dict exists $snapshot $id]} {dict set snapshot $id {}}}
    _restoreSnapshot $w $snapshot
    set st($w,scientificRecipe) [::GX::datasetPublicationV2DictDefault [dict get $payload cad_workspace] scientific_recipe {}]
    return 1
}

# Guard mutation entry points before Native state or document state changes.
proc ::GX::CurveWorkbench::_timelineEditable {w} {
    variable st
    if {[info exists st($w,historyBrowsing)]&&$st($w,historyBrowsing)&&![info exists st($w,historyRestoring)]} {
        _notice $w {History is read-only. Return to Latest, or explicitly restart here to discard future steps.}
        return 0
    }
    return 1
}
foreach command {_sketchTool _sketchModifyTool _dimensionTool _dimensionEdit _transformStart _duplicate _operation _constraintAction _datasetCommit _datasetImport _parameterRecalculate} {
    if {[info commands ::GX::CurveWorkbench::$command] eq {}} continue
    rename ::GX::CurveWorkbench::$command ::GX::CurveWorkbench::${command}_history_guard_base
    proc ::GX::CurveWorkbench::$command {w args} [format {
        if {![_timelineEditable $w]} return
        tailcall %s_history_guard_base $w {*}$args
    } $command]
}
foreach command {undo redo} {
    rename ::GX::CurveWorkbench::$command ::GX::CurveWorkbench::${command}_history_base
    proc ::GX::CurveWorkbench::$command {w} [format {
        variable st
        if {$st($w,historyBrowsing)} {
            _timelineBrowse $w [expr {max(0,min($st($w,historyCount),$st($w,historyCursor)+%d))}]
            return
        }
        set before [_recipeState $w];set record $st($w,scientificRecipe)
        set undo $st($w,undo);set redo $st($w,redo)
        set st($w,importTransaction) 1
        try {
            %s_history_base $w
            set after [_recipeState $w]
            if {$record eq {}} {set record [dict create base $before steps {} retention complete]}
            dict set record retention complete
            set st($w,scientificRecipe) [::GX::scientificRecipeAppend $record $before $after {api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 operation %s parameters {} targets {} result_ids {} working_unit {}}]
        } on error {message options} {
            _recipeApplyState $w [dict create base $before steps {}]
            set st($w,undo) $undo;set st($w,redo) $redo;set st($w,scientificRecipe) $record
            return -options $options $message
        } finally {unset -nocomplain st($w,importTransaction)}
        _save $w;_timelineRender $w
    } [expr {$command eq "undo"?-1:1}] $command $command]
}

# Direct identities are obtained from the immutable recipe patch, never guessed
# from displayed labels. Browsing is read-only; editing requires explicit restart.
proc ::GX::CurveWorkbench::_timelineConstraints {w index} {
    set after [::GX::datasetPublicationV2DictDefault [dict get [_timelineState $w $index] @cad] constraints {}]
    if {$index==0} {return [dict keys $after]}
    set before [::GX::datasetPublicationV2DictDefault [dict get [_timelineState $w [expr {$index-1}]] @cad] constraints {}]
    set changed {}
    dict for {id value} $after {if {![dict exists $before $id] || [dict get $before $id] ne $value} {lappend changed $id}}
    return $changed
}
proc ::GX::CurveWorkbench::_timelineConstraint {w index id action} {
    variable st
    if {$action eq "inspect"} {
        _timelineBrowse $w $index
    } else {
        if {$index<$st($w,historyCount)} {
            _timelineRestart $w $index
            if {$st($w,historyBrowsing) || $st($w,historyCount)!=$index} return
        } elseif {$st($w,historyBrowsing)} {_timelineBrowse $w $st($w,historyCount)}
        if {![_timelineEditable $w]} return
    }
    if {![dict exists $st($w,constraints) $id]} {error "Constraint $id is unavailable in this state."}
    _constraintOpen $w
    set tree [::GX::CurveWorkbench::_constraintPanel $w].tree
    $tree selection set $id;$tree see $id
    _constraintMarkerSelect $w $id
    switch $action {
        inspect {set st($w,status) "History step $index; $id: [_constraintDescription $w [dict get $st($w,constraints) $id]]. Read-only; use Restart to edit."}
        edit {_dimensionEdit $w}
        remove {_constraintAction $w remove}
    }
    if {$action ne "inspect" && ![winfo exists $w.inline]} {focus $w.right.viewport.canvas}
}
