# SPDX-License-Identifier: GPL-3.0-or-later
# UI routing/presentation. Geometry, equations, inference, witnesses and picking
# are Native2D queries. Existing document/relationship IDs own persistence.
proc ::GX::CurveWorkbench::_isDimension {kind} {expr {$kind in [::GX::native2DCadDimensionKinds]}}
proc ::GX::CurveWorkbench::_sketchIdle {w {message {Select — geometry, handles, constraints or dimensions.}}} {
    variable st
    set st($w,selectedRelationship) {};set st($w,hoverRelationship) {}
    # Cancellation can redraw from lower layers. Hide the old gizmo before
    # those draws; selection/pivot may no longer be valid for that tool.
    set st($w,cadTool) none
    _cancelGesture_sketch054_base $w
    set st($w,canvasTool) select;set st($w,tool) select
    foreach key {constraintTool dimRefs dimSpec dimAnnotation dimExisting annotationDrag selectedRelationship hoverRelationship sketchSelection} {set st($w,$key) {}}
    if {[winfo exists $w.inline]} {destroy $w.inline}
    ::GX::Native2D::core gizmo $st($w,scene) {visible 0}
    $w.right.viewport.canvas configure -cursor {};set st($w,toolLabel) $message;set st($w,status) {}
    _noticeHide $w
    _draw $w
}
rename ::GX::CurveWorkbench::_cancelGesture ::GX::CurveWorkbench::_cancelGesture_sketch054_base
proc ::GX::CurveWorkbench::_cancelGesture {w} {
    variable st;set requested $st($w,cadTool);set selection $st($w,sketchSelection)
    _sketchIdle $w;set st($w,cadTool) $requested;set st($w,sketchSelection) $selection
    if {$requested ne "none"} {::GX::Native2D::core gizmo $st($w,scene) [dict create visible 1 mode $requested];_draw $w}
}
# Canvas notices never take focus or a grab; an invalid command must leave the
# operator free to continue with the existing keyboard/pointer workflow.
proc ::GX::CurveWorkbench::_noticeHide {w} {
    if {[winfo exists $w.notice]} {place forget $w.notice}
}
proc ::GX::CurveWorkbench::_notice {w message} {
    variable st
    set st($w,status) $message
    if {![winfo exists $w.right.viewport.canvas]} return
    if {![winfo exists $w.notice]} {
        ttk::frame $w.notice -padding 6 -relief solid -borderwidth 1
        ttk::label $w.notice.message -wraplength 310 -justify left
        pack $w.notice.message
    }
    if {[info exists st($w,noticeAfter)]} {after cancel $st($w,noticeAfter)}
    $w.notice.message configure -text $message
    place $w.notice -in $w.right.viewport.canvas -relx .5 -y 16 -anchor n
    raise $w.notice
    set st($w,noticeAfter) [after 4500 [list ::GX::CurveWorkbench::_noticeHide $w]]
}
rename ::GX::CurveWorkbench::_safe ::GX::CurveWorkbench::_safe_sketch054_base
proc ::GX::CurveWorkbench::_safe {w command {interactive 0}} {
    variable st
    if {![winfo exists $w] || ![info exists st($w,token)]} return
    set incarnation [winfo id $w];set token $st($w,token)
    if {$st($w,publishBusy)} {tailcall _safe_sketch054_base $w $command}
    set geometric [expr {$interactive||$st($w,cadTool) ne "none"||[regexp {::_(constraint|dimension|sketchTool|create|cad|relationshipAction|command|operation|duplicate|transform)} [lindex $command 0]]}]
    if {[catch {uplevel #0 $command} message options]} {
        # Native work can dispatch an ordinary WM close while this callback is
        # waiting. Never address the closed (or same-path replacement) window.
        if {![_windowCurrent $w $incarnation $token]} return
        if {[dict exists $options -errorcode]&&[dict get $options -errorcode] in {{GX DATASET_TRANSFORM CANCELLED} {GX CURVE_SOURCE CANCELLED}}} {set st($w,status) $message;return}
        if {!$geometric} {
            set st($w,status) $message
            tk_messageBox -parent $w -icon error -type ok -title {Curve Workbench} -message $message
            return
        }
        if {$message eq "invalid input"} {set message {Select compatible geometry for this operation, or finish the current construction first.}}
        _notice $w "Operation unavailable: $message"
    }
}
proc ::GX::CurveWorkbench::_buildConstraintTools {w} {
    variable st
    ttk::button $w.sketchbar.parameters -text {Parameters...} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_parametersOpen $w]]
    pack $w.sketchbar.parameters -side left -padx 3 -before $w.sketchbar.finish
    ttk::button $w.sketchbar.dimension -text Dimension -command [list ::GX::CurveWorkbench::_dimensionTool $w]
    ttk::button $w.sketchbar.palette -text {Sketch palette} -command [list ::GX::CurveWorkbench::_constraintOpen $w]
    pack $w.sketchbar.dimension $w.sketchbar.palette -side left -padx 3 -before $w.sketchbar.finish
    bind $w.right.viewport.canvas <Double-Button-1> [list ::GX::CurveWorkbench::_relationshipDouble $w %x %y %s]
    bind $w.right.viewport.canvas <Button-3> [list ::GX::CurveWorkbench::_relationshipContext $w %x %y %X %Y]
    bind $w.right.viewport.canvas <Escape> [list ::GX::CurveWorkbench::_sketchIdle $w]
    bind $w <Escape> [list ::GX::CurveWorkbench::_sketchIdle $w]
    bind $w.right.viewport.canvas <Key-d> [list ::GX::CurveWorkbench::_dimensionTool $w]
    bind $w.right.viewport.canvas <Delete> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintAction $w remove]]
    bind $w.right.viewport.canvas <Tab> [list ::GX::CurveWorkbench::_relationshipNext $w]
}
proc ::GX::CurveWorkbench::_constraintOpen {w} {
    variable st
    set d [::GX::CurveWorkbench::_constraintPanel $w]
    if {![winfo exists $d]} {
        ttk::frame $d -padding 8 -relief ridge -borderwidth 2
        ttk::label $d.help -text {Sketch palette — select geometry or a relationship.} -wraplength 285
        pack $d.help -fill x
        ttk::label $d.available -text {} -wraplength 285;pack $d.available -fill x
        ttk::checkbutton $d.showc -text {Show constraints} -variable ::GX::CurveWorkbench::st($w,showConstraints) -command [list ::GX::CurveWorkbench::_draw $w]
        ttk::checkbutton $d.showd -text {Show dimensions} -variable ::GX::CurveWorkbench::st($w,showDimensions) -command [list ::GX::CurveWorkbench::_draw $w]
        pack $d.showc $d.showd -anchor w
        ttk::treeview $d.tree -columns {name state} -show headings -height 6 -selectmode browse
        $d.tree heading name -text Relationship;$d.tree heading state -text State
        $d.tree column name -width 205;$d.tree column state -width 70;pack $d.tree -fill both -expand 1
        bind $d.tree <<TreeviewSelect>> [list ::GX::CurveWorkbench::_paletteSelect $w]
        bind $d.tree <Double-Button-1> [list ::GX::CurveWorkbench::_dimensionEdit $w]
        ttk::frame $d.actions;pack $d.actions -fill x
        foreach {key title action} {edit Edit edit toggle Enable/Disable toggle remove Delete remove details Details details close Hide hide} {
            ttk::button $d.actions.$key -text $title -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_paletteAction $w $action]]
            pack $d.actions.$key -side left -padx 1
        }
        bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    }
    if {[winfo parent $d] eq $w} {place $d -in $w.right.viewport.canvas -relx 1 -x -12 -y 14 -anchor ne -width 310}
    raise $d;_constraintRefresh $w
}
proc ::GX::CurveWorkbench::_paletteAction {w action} {
    switch $action {hide {place forget [::GX::CurveWorkbench::_constraintPanel $w]} edit {_dimensionEdit $w} details {variable st;set id [_constraintSelected $w];set st($w,status) [_constraintDescription $w [dict get $st($w,constraints) $id]]} default {_constraintAction $w $action}}
}
proc ::GX::CurveWorkbench::_constraintSelected {w} {
    variable st
    if {$st($w,selectedRelationship) ne {}&&[dict exists $st($w,constraints) $st($w,selectedRelationship)]} {return $st($w,selectedRelationship)}
    if {[winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]&&[llength [[::GX::CurveWorkbench::_constraintPanel $w].tree selection]]==1} {return [lindex [[::GX::CurveWorkbench::_constraintPanel $w].tree selection] 0]}
    error {Select a constraint badge or dimension on the canvas.}
}
proc ::GX::CurveWorkbench::_paletteSelect {w} {
    if {![winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]} return
    set selection [[::GX::CurveWorkbench::_constraintPanel $w].tree selection];if {[llength $selection]!=1} return
    variable st;set id [lindex $selection 0]
    if {![dict exists $st($w,constraints) $id]} return
    if {$st($w,selectedRelationship) eq $id} return
    _constraintMarkerSelect $w $id
}
proc ::GX::CurveWorkbench::_constraintRefresh {w} {
    variable st
    if {![winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]} return
    set tree [::GX::CurveWorkbench::_constraintPanel $w].tree
    foreach id [$tree children {}] {if {![dict exists $st($w,constraints) $id]} {$tree delete $id}}
    dict for {id record} $st($w,constraints) {
        set receipt [[_cadController $w] relationship get [dict get $record native]]
        set state [expr {[dict get $receipt disabled]?"off":[dict get $receipt driven]?"reference":[dict get $receipt valid]?"active":"invalid"}]
        set values [list [_constraintTitle [dict get $receipt kind]] $state]
        if {![$tree exists $id]} {$tree insert {} end -id $id -values $values} elseif {[$tree item $id -values] ne $values} {$tree item $id -values $values}
    }
    set text {Select geometry to see local constraint status.}
    if {$st($w,active) ne {}&&[dict exists $st($w,curves) $st($w,active)]} {
        set r [_record $w $st($w,active)];set text [dict get $r name]
        if {[dict exists $r sketch_definition]} {
            if {[catch {set report [::GX::Native2D::core sketch_status $st($w,scene) [dict get $r native]]} reason]} {append text "\nStatus unavailable: $reason"} else {
                set dof [dict get $report dof];set rank [dict get $report rank]
                append text "\n[expr {![dict get $report valid]?"Conflicting/invalid":![dict get $report analysis_complete]?"Partial analysis (legacy geometry)":$dof==0?"Fully constrained (local)":$rank==0?"Unconstrained":"Partially constrained"}] · $dof local component DOF"
            }
        } else {append text { — scientific Dataset / Native point curve}}
        append text "\nRole: [::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get $r native]]"
    }
    [::GX::CurveWorkbench::_constraintPanel $w].help configure -text $text
    set titles {};foreach kind [dict keys [_constraintOptions $w]] {lappend titles [_constraintTitle $kind]}
    [::GX::CurveWorkbench::_constraintPanel $w].available configure -text "Available: [expr {$titles eq {}?"select compatible geometry":[join $titles { · }]}]"
}
proc ::GX::CurveWorkbench::_constraintMenu {w} {
    set menu $w.sketchbar.constraints.menu;$menu delete 0 end
    set options [_constraintOptions $w]
    foreach kind {horizontal vertical coincident parallel perpendicular tangent equal_length equal_radius fixed midpoint concentric collinear symmetry point_on_line point_on_curve curvature distance horizontal_distance vertical_distance point_line_distance line_distance angle axis_angle radius diameter lock_x lock_y} {
        $menu add command -label [_constraintTitle $kind] -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintSimple $w $kind]]
    }
    $menu add cascade -label {Start constraint tool} -menu $menu.tools
    if {[winfo exists $menu.tools]} {destroy $menu.tools}
    menu $menu.tools -tearoff 0
    foreach kind {horizontal vertical coincident parallel perpendicular tangent equal_length equal_radius fixed midpoint concentric collinear symmetry point_on_line point_on_curve curvature} {$menu.tools add command -label [_constraintTitle $kind] -command [list ::GX::CurveWorkbench::_constraintStart $w $kind]}
    $menu add command -label Unfix -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_unfix $w]]
    $menu add separator
    $menu add command -label {Inspector / dimensions…} -command [list ::GX::CurveWorkbench::_constraintOpen $w]
    $menu add command -label {Advanced reference editor…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintForm $w]]
}
proc ::GX::CurveWorkbench::_constraintSimple {w kind} {
    variable st
    if {[_isDimension $kind]} {_dimensionTool $w $kind;return}
    set options [_constraintOptions $w]
    if {[dict exists $options $kind]} {_constraintCommit $w {} [dict get $options $kind];return}
    _constraintStart $w $kind
}
proc ::GX::CurveWorkbench::_constraintStart {w kind} {
    variable st
    _sketchIdle $w
    [_advancedRelationships $w] constraint start $kind
    set st($w,constraintTool) $kind;_draw $w
    set expectation [expr {$kind in {horizontal vertical fixed}?{one object}:$kind eq {symmetry}?{two objects/points, then symmetry axis}:$kind in {midpoint point_on_line point_on_curve}?{a point, then its line/curve}:{two compatible objects or endpoint controls}}]
    set st($w,toolLabel) "[_constraintTitle $kind] — select $expectation. Esc cancels."
    set st($w,status) {};focus $w.right.viewport.canvas
}
proc ::GX::CurveWorkbench::_unfix {w} {
    if {![_timelineEditable $w]} return
    variable st;set selected [_constraintReferences $w];set ids [lmap ref $selected {dict get $ref logical}];set found {}
    dict for {id r} $st($w,constraints) {if {[dict get $r definition kind] eq "fixed"&&[dict get $r definition a] in $ids} {lappend found $id}}
    if {$found eq {}} {error {Select Fixed geometry first.}}
    set before [_snapshotIds $w {}]
    foreach id $found {[_advancedRelationships $w] constraint manage [dict get $st($w,constraints) $id native] remove;dict unset st($w,constraints) $id}
    _history $w $before {};_constraintRefresh $w;_draw $w
}
proc ::GX::CurveWorkbench::_constraintCommit {w id spec} {
    if {![_timelineEditable $w]} return
    variable st
    if {$id eq {}} {dict unset spec anchor}
    set unitsFor {};dict for {nativeId logical} [_logicalNativeMap $w] {
        set r [_record $w $logical]
        foreach key {a b axis} {if {[dict exists $spec $key]&&[dict get $spec $key]==[dict get $r native]} {lappend unitsFor $logical}}
    }
    foreach logical $unitsFor {if {[dict get [_record $w $logical] native]==[dict get $spec a]&&[dict get [_record $w $logical] locked]&&![::GX::datasetPublicationV2DictDefault $spec driven 0]} {error {Geometry is read-only. Unlock the retained primitive or use Representation to convert the Dataset first.}}}
    _constraintCoordinateGuard $w $spec
    set affected [_sketchAffected $w [lsort -unique $unitsFor]];set before [_snapshotIds $w $affected]
    set native [expr {$id eq {}?0:[dict get $st($w,constraints) $id native]}]
    set receipt [[_advancedRelationships $w] constraint apply $native $spec]
    return [_advancedConstraintAdopt $w $id $spec $receipt $affected $before]
}
proc ::GX::CurveWorkbench::_dimensionTool {w {forced {}}} {
    variable st;set refs [_constraintReferences $w]
    _sketchIdle $w
    set state [[_advancedRelationships $w] dimension start $forced $refs]
    set st($w,dimForced) $forced;set st($w,dimDriven) 0;set st($w,dimRefs) [dict get $state references]
    set st($w,dimNotice) {};set st($w,constraintTool) dimension
    set st($w,toolLabel) {Dimension — select geometry/points, move to preview, click to place; Enter commits. Esc cancels.}
    set st($w,status) {};focus $w.right.viewport.canvas
}
proc ::GX::CurveWorkbench::_dimensionPreview {w x y} {
    variable st
    set state [[_advancedRelationships $w] dimension preview [list $x $y]]
    set st($w,dimRefs) [dict get $state references];set st($w,dimSpec) {}
    if {[dict get $state references] eq {}} return
    if {[dict get $state status] eq {rejected}} {
        _draw $w
        set message "Dimension — [dict get $state error]. Select compatible geometry; Esc cancels."
        if {$st($w,dimNotice) ne $message} {_notice $w $message;set st($w,dimNotice) $message}
        return
    }
    set spec [dict get $state specification]
    _constraintCoordinateGuard $w $spec
    set st($w,dimNotice) {};_noticeHide $w
    set st($w,dimSpec) $spec;set st($w,dimAnnotation) [dict get $state annotation]
    _draw $w;_dimensionDraw $w [dict get $state geometry] $spec #237a6a dimension_preview
}
proc ::GX::CurveWorkbench::_dimensionText {w spec value driven} {
    set kind [dict get $spec kind];set unit [dict get [_dimensionCoordinateInfo $w $spec] display_unit]
    set value [_dimensionDisplayedValue $w $spec $value]
    set prefix [expr {$kind eq "radius"?"R ":$kind eq "diameter"?"Ø ":$kind eq "lock_x"?"X ":$kind eq "lock_y"?"Y ":$kind in {angle axis_angle}?"∠ ":{}}]
    set text "$prefix[format %.5g $value] $unit";if {$driven} {set text "($text)"};return $text
}
proc ::GX::CurveWorkbench::_dimensionDraw {w geometry spec color tags} {
    variable st
    set selected [expr {$st($w,selectedRelationship) ne {}&&"constraint_$st($w,selectedRelationship)" in $tags}]
    return [[_advancedRelationships $w] dimension draw $w.right.viewport.canvas $geometry [_dimensionText $w $spec [dict get $geometry value] [dict get $geometry driven]] $color [dict create selected $selected tags $tags]]
}
proc ::GX::CurveWorkbench::_inlineOpen {w spec annotation {id {}}} {
    variable st
    set st($w,dimSpec) $spec;set st($w,dimAnnotation) $annotation;set st($w,dimExisting) $id
    set value [format %.9g [_dimensionDisplayedValue $w $spec [dict get $spec value]]]
    set st($w,inlineCoordinateIds) [dict keys $st($w,curves)];set st($w,inlineCoordinateKey) [_coordinateControlKey $w $st($w,inlineCoordinateIds)]
    if {$id ne {}&&[dict exists $st($w,constraints) $id expression]&&![string is double -strict [dict get $st($w,constraints) $id expression]]} {set value [dict get $st($w,constraints) $id expression]}
    set referenceOnly 0
    foreach field {a b} {if {[dict exists $spec $field]&&[dict get $spec $field]!=0&&[::GX::Native2D::core image_get $st($w,scene) [dict get $spec $field]] ne {}} {set referenceOnly 1}}
    set native [expr {$id eq {}?0:[dict get $st($w,constraints) $id native]}]
    set message "Numbers use the displayed unit. An explicit unit is accepted. Parameter formulas retain native [dict get [_dimensionCoordinateInfo $w $spec] native_unit] coordinates."
    if {$referenceOnly} {set message {Measure the calibrated graphic. Recalibrate it to change its physical scale.}}
    return [[_advancedRelationships $w] dimension editor_create $w.inline [dict create specification $spec existing $native annotation $annotation value $value title "[_constraintTitle [dict get $spec kind]] · [dict get [_dimensionCoordinateInfo $w $spec] display_unit]" message $message canvas $w.right.viewport.canvas anchor_device [::GX::Native2D::core device $st($w,scene) $annotation] reference_only $referenceOnly parse_command [list ::GX::CurveWorkbench::_advancedDimensionParse $w $st($w,inlineCoordinateIds) $st($w,inlineCoordinateKey)] commit_command [list ::GX::CurveWorkbench::_advancedDimensionCommit $w $id] accepted_command [list ::GX::CurveWorkbench::_advancedDimensionAccepted $w] cancel_command [list ::GX::CurveWorkbench::_advancedDimensionCancelled $w] guard_command [list ::GX::CurveWorkbench::_advancedDimensionGuard $w $st($w,token) [winfo id $w]]]]
}
proc ::GX::CurveWorkbench::_inlineCommit {w {reference 0}} {return [[_advancedRelationships $w] dimension editor_commit $reference]}
proc ::GX::CurveWorkbench::_dimensionEdit {w} {
    variable st;set id [_constraintSelected $w];set record [dict get $st($w,constraints) $id]
    set receipt [[_advancedRelationships $w] constraint inspect [dict get $record native]]
    if {![_isDimension [dict get $receipt kind]]} {set st($w,status) [_constraintDescription $w $record];return}
    if {[dict get $receipt driven]} {set st($w,status) {Reference dimension is read-only. Use Toggle Driving to drive geometry.};return}
    [_advancedRelationships $w] dimension edit [dict get $record native]
    _inlineOpen $w $receipt [dict get $receipt annotation] $id
}
proc ::GX::CurveWorkbench::_constraintMarkers {w} {
    variable st
    set natives {};set reverse {}
    dict for {id record} $st($w,constraints) {lappend natives [dict get $record native];dict set reverse [dict get $record native] $id}
    set selected [expr {$st($w,selectedRelationship) ne {}&&[dict exists $st($w,constraints) $st($w,selectedRelationship)]?[dict get $st($w,constraints) $st($w,selectedRelationship) native]:{}}]
    set hover [expr {$st($w,hoverRelationship) ne {}&&[dict exists $st($w,constraints) $st($w,hoverRelationship)]?[dict get $st($w,constraints) $st($w,hoverRelationship) native]:{}}]
    set regions [[_advancedRelationships $w] constraint present $w.right.viewport.canvas $natives [dict create selected $selected hover $hover show_constraints $st($w,showConstraints) show_dimensions $st($w,showDimensions) format_command [list ::GX::CurveWorkbench::_dimensionText $w]]]
    set st($w,markerRegions) {}
    dict for {native region} $regions {dict set st($w,markerRegions) [dict get $reverse $native] $region}
    _constraintRefresh $w
}
proc ::GX::CurveWorkbench::_relationshipPick {w x y} {
    variable st
    set regions {};set reverse {}
    dict for {id region} $st($w,markerRegions) {set native [dict get $st($w,constraints) $id native];dict set regions $native $region;dict set reverse $native $id}
    set native [[_advancedRelationships $w] constraint pick [list $x $y] $regions]
    if {$native eq {}} {return {}}
    return [dict get $reverse $native]
}
proc ::GX::CurveWorkbench::_constraintMarkerSelect {w id} {
    variable st
    set st($w,selectedRelationship) $id;set spec [dict get $st($w,constraints) $id definition];set ids {}
    foreach key {a b axis} {if {[dict exists $spec $key]} {lappend ids [dict get $spec $key]}}
    _semanticClear $w;set st($w,active) [lindex $ids 0]
    _selectionScene $w;_curveList $w;_pointList $w;_draw $w
    # _drawRelationships paints the exact references from this selected spec.
    # Do not add a second whole-object highlight after the authoritative draw.
    ::GX::native2DCanvasViewportClip $w.right.viewport.canvas $st($w,scene)
    if {[winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]&&[[::GX::CurveWorkbench::_constraintPanel $w].tree exists $id]&&[[::GX::CurveWorkbench::_constraintPanel $w].tree selection] ne $id} {[::GX::CurveWorkbench::_constraintPanel $w].tree selection set $id;[::GX::CurveWorkbench::_constraintPanel $w].tree see $id}
    set st($w,status) [_constraintDescription $w [dict get $st($w,constraints) $id]]
}
proc ::GX::CurveWorkbench::_constraintHighlight {w} {_paletteSelect $w}
proc ::GX::CurveWorkbench::_relationshipDouble {w x y state} {
    variable st
    if {$st($w,canvasTool) ne "select"||$state&0x5||$st($w,constraintTool) ni {{} dimension}} {_mouseDown $w $x $y $state;return}
    set id [_relationshipPick $w $x $y]
    set geometry [_sketchPick $w $x $y]
    if {$geometry ne {}&&[dict get $geometry entity] eq "control"&&$id ne $st($w,selectedRelationship)} {_mouseDown $w $x $y $state;return}
    if {$id ne {}} {_constraintMarkerSelect $w $id;_dimensionEdit $w} else {_mouseDown $w $x $y $state}
}
proc ::GX::CurveWorkbench::_relationshipNext {w} {
    variable st;set ids [dict keys $st($w,markerRegions)];if {$ids eq {}} return
    set i [expr {([lsearch -exact $ids $st($w,selectedRelationship)]+1)%[llength $ids]}];_constraintMarkerSelect $w [lindex $ids $i]
}
proc ::GX::CurveWorkbench::_relationshipContext {w x y rootx rooty} {
    variable st;set id [_relationshipPick $w $x $y]
    if {$id eq {}} {
        set hit [_sketchPick $w $x $y]
        if {$hit ne {}} {
            set present 0;foreach ref $st($w,sketchSelection) {if {[dict get $ref object]==[dict get $hit object]&&[dict get $ref index]==[dict get $hit index]} {set present 1}}
            if {!$present} {set st($w,sketchSelection) [list $hit]}
            set options [_constraintOptions $w];set menu $w.sketchContext065;catch {destroy $menu};menu $menu -tearoff 0
            dict for {kind spec} $options {$menu add command -label [_constraintTitle $kind] -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintSimple $w $kind]]}
            $menu add separator;$menu add command -label {Inspect / remove constraints...} -command [list ::GX::CurveWorkbench::_constraintOpen $w]
            $menu add command -label {Parameters...} -command [list ::GX::CurveWorkbench::_parametersOpen $w]
            ::GX::uiMenuPopup $menu $rootx $rooty;return
        }
        _sketchContext $w $rootx $rooty;return
    }
    _constraintMarkerSelect $w $id
    if {[winfo exists $w.relationshipMenu]} {destroy $w.relationshipMenu}
    menu $w.relationshipMenu -tearoff 0
    foreach {label action} {{Edit value} edit {Enable / Disable} toggle Delete remove {Show details} details {Toggle Driving / Reference} driven {Reset annotation position} reset} {
        $w.relationshipMenu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_relationshipAction $w $action]]
    }
    ::GX::uiMenuPopup $w.relationshipMenu $rootx $rooty
}
proc ::GX::CurveWorkbench::_relationshipAction {w action} {
    variable st
    if {$action in {edit details toggle remove}} {_paletteAction $w $action;return}
    set id [_constraintSelected $w];set record [dict get $st($w,constraints) $id];set native [dict get $record native]
    set receipt [[_cadController $w] relationship get $native]
    if {![_isDimension [dict get $receipt kind]]} {error {This relationship is not a dimension.}}
    if {$action eq "driven"} {
        set proposal [[_advancedRelationships $w] constraint reference_proposal $native]
        _constraintCommit $w $id $proposal
    } else {
        set before [_snapshotIds $w {}]
        [_advancedRelationships $w] dimension annotation_reset $native
        _history $w $before {};_draw $w
    }
}
proc ::GX::CurveWorkbench::_pointerDownConstraint {w x y state} {
    variable st
    if {$st($w,publishBusy)} {return 1}
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {_sketchIdle $w {Session changed — reopen Workbench.};return 1}
    if {[winfo exists $w.inline]} {return 1}
    if {$st($w,constraintTool) eq "dimension"} {
        set state [[_advancedRelationships $w] dimension input [_sketchPick $w $x $y] $state]
        set st($w,dimRefs) [dict get $state references]
        if {[dict get $state selected]} {set st($w,dimSpec) {};_dimensionPreview $w $x $y;return 1}
        if {[dict get $state specification] ne {}} {_dimensionPreview $w $x $y;if {$st($w,dimSpec) ne {}} {_inlineOpen $w $st($w,dimSpec) $st($w,dimAnnotation)}}
        return 1
    }
    if {$st($w,constraintTool) ne {}} {
        set ref [_sketchPick $w $x $y];if {$ref eq {}} {return 1}
        set result [[_advancedRelationships $w] constraint input $ref [expr {$state&1?{subtract}:{add}}]]
        if {!($state&1)} {set st($w,active) [dict get $ref logical];_selectionScene $w;_curveList $w;_pointList $w}
        if {[dict get $result status] eq {ready}} {_safe $w [list ::GX::CurveWorkbench::_constraintCommit $w {} [dict get $result specification]];set st($w,toolLabel) {Select — relationship committed.};return 1}
        _draw $w
        if {[dict get $result status] eq {rejected}} {_notice $w "[_constraintTitle $st($w,constraintTool)] — [dict get $result error]. Select compatible references again; Esc cancels."} else {set st($w,status) "[_constraintTitle $st($w,constraintTool)] — select the next compatible reference. Esc cancels."}
        return 1
    }
    if {$st($w,canvasTool) eq "select"&&$st($w,cadTool) eq "none"} {
        set id [_relationshipPick $w $x $y]
        set geometry [_sketchPick $w $x $y]
        # A defining handle is the precise graphic target. It wins over a
        # nearby annotation/witness region; selected dimensions can still drag.
        if {$state&0x5||($geometry ne {}&&[dict get $geometry entity] eq "control"&&$id ne $st($w,selectedRelationship))} {set id {}}
        if {$id ne {}} {
            _constraintMarkerSelect $w $id
            set record [dict get $st($w,constraints) $id];set spec [dict get $record definition]
            if {[_isDimension [dict get $spec kind]]&&[dict get $spec placed]} {[_advancedRelationships $w] dimension annotation_start [dict get $record native] [list $x $y];set st($w,annotationDrag) [dict create id $id before [_snapshotIds $w {}] start [list $x $y] target [dict get $spec annotation] moved 0]}
            return 1
        }
        set st($w,selectedRelationship) {}
    }
    return 0

    return 1
}
rename ::GX::CurveWorkbench::_coordinates ::GX::CurveWorkbench::_coordinates_sketch054_base
proc ::GX::CurveWorkbench::_coordinates {w x y} {
    variable st
    _coordinates_sketch054_base $w $x $y
    if {$st($w,constraintTool) eq "dimension"&&![winfo exists $w.inline]} {
        if {[catch {_dimensionPreview $w $x $y} message]} {set st($w,status) "Dimension — $message. Select compatible geometry."};return
    }
    set hover [_relationshipPick $w $x $y]
    if {$hover ne $st($w,hoverRelationship)} {set st($w,hoverRelationship) $hover;_draw $w}
    if {$hover ne {}} {set st($w,status) [_constraintDescription $w [dict get $st($w,constraints) $hover]];$w.right.viewport.canvas configure -cursor hand2} elseif {$st($w,cadTool) eq "none"} {$w.right.viewport.canvas configure -cursor {}}
}
proc ::GX::CurveWorkbench::_pointerMoveAnnotation {w x y} {
    variable st
    if {$st($w,annotationDrag) ne {}} {
        set proposal [[_advancedRelationships $w] dimension annotation_move [list $x $y]]
        dict set st($w,annotationDrag) target [dict get $proposal target]
        dict set st($w,annotationDrag) moved [dict get $proposal changed]
        _draw $w;return 1
    }
    return 0
}
proc ::GX::CurveWorkbench::_pointerUpConstraint {w x y} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {_sketchIdle $w {Session changed — gesture cancelled; reopen Workbench.};return 1}
    if {$st($w,annotationDrag) ne {}} {
        set drag $st($w,annotationDrag);set st($w,annotationDrag) {}
        set receipt [[_advancedRelationships $w] dimension annotation_commit]
        if {[dict get $receipt changed]} {_history $w [dict get $drag before] {}}
        _draw $w;return 1
    }
    if {$st($w,constraintTool) ne {}} {return 1}
    return 0
}
# Tool activation is a transition: preserve the requested mode across cleanup.
proc ::GX::CurveWorkbench::_cadToolChoice {w} {
    variable st;set requested $st($w,cadTool)
    _sketchIdle $w;set st($w,cadTool) $requested
    if {$requested ne "none"} {
        _cadSelectNative $w
        if {[catch {::GX::Native2D::core pivot $st($w,scene)}]} {
            lassign [::GX::Native2D::core view $st($w,scene)] width height left top right bottom
            ::GX::Native2D::core pivot $st($w,scene) custom [::GX::Native2D::core world $st($w,scene) [list [expr {($left+$width-$right)/2.0}] [expr {($top+$height-$bottom)/2.0}]]]
        }
        set grid [::GX::Native2D::core grid $st($w,scene)]
        ::GX::Native2D::core gizmo $st($w,scene) [dict create visible 1 mode $requested axes_angle [dict get $grid angle]]
    }
    _draw $w;_save $w
}

proc ::GX::CurveWorkbench::_dimensionUnit {w spec} {
    variable st
    if {[dict get $spec kind] in {angle axis_angle}} {return rad}
    dict for {id record} $st($w,curves) {if {[dict get $record native]==[dict get $spec a]} {return [lindex [_coordinateUnits $record] [expr {[dict get $spec kind] in {lock_y vertical_distance}?1:0}]]}}
    return $st($w,sketchUnit)
}
proc ::GX::CurveWorkbench::_drawRelationships {w} {
    variable st
        if {![info exists st($w,selectedRelationship)]||![winfo exists $w.right.viewport.canvas]} return
    set id $st($w,selectedRelationship)
    if {$id ne {}&&[dict exists $st($w,constraints) $id]} {
        set spec [dict get $st($w,constraints) $id definition]
        foreach key {a b axis} {if {[dict exists $spec $key]&&([dict exists $st($w,curves) [dict get $spec $key]]||([info exists st($w,images)]&&[dict exists $st($w,images) [dict get $spec $key]]))} {
            _relationshipHighlightGeometry $w [dict get $spec $key] [::GX::datasetPublicationV2DictDefault $spec ${key}_index 0] #b45400 3
        }}
        $w.right.viewport.canvas raise constraint_marker
        ::GX::native2DCanvasViewportClip $w.right.viewport.canvas $st($w,scene)
    }
    set hover $st($w,hoverRelationship)
    if {$hover ne {}&&[dict exists $st($w,markerRegions) $hover]} {
        lassign [dict get $st($w,markerRegions) $hover] x0 y0 x1 y1
        set spec [dict get $st($w,constraints) $hover definition]
        if {$hover ne $id} {foreach key {a b axis} {if {[dict exists $spec $key]&&([dict exists $st($w,curves) [dict get $spec $key]]||([info exists st($w,images)]&&[dict exists $st($w,images) [dict get $spec $key]]))} {_relationshipHighlightGeometry $w [dict get $spec $key] [::GX::datasetPublicationV2DictDefault $spec ${key}_index 0] #146d9b 2}}}
        set text [_constraintTitle [dict get $st($w,constraints) $hover definition kind]]
        $w.right.viewport.canvas create text $x0 [expr {$y0-8}] -anchor sw -text $text -fill #146d9b -font TkDefaultFont -tags relationship_tooltip
    }
}

proc ::GX::CurveWorkbench::_relationshipHighlightGeometry {w logical index color width} {
    variable st;set native [dict get [_record $w $logical] native];set canvas $w.right.viewport.canvas
    set ref [::GX::Native2D::core interaction_reference_index $st($w,scene) $native $index]
    switch -- [dict get $ref entity] {
        control - point {
            lassign [::GX::Native2D::core device $st($w,scene) [::GX::Native2D::core interaction_resolve $st($w,scene) $ref]] x y
            $canvas create rectangle [expr {$x-7}] [expr {$y-7}] [expr {$x+7}] [expr {$y+7}] -outline $color -width $width -tags relationship_geometry
        }
        segment {
            set points [::GX::Native2D::core interaction_render $st($w,scene) $ref]
            if {[llength $points]>=2} {$canvas create line {*}[concat {*}$points] -fill $color -width $width -tags relationship_geometry}
        }
        object {foreach points [::GX::Native2D::core render_paths $st($w,scene) $native] {if {[llength $points]>=2} {$canvas create line {*}[concat {*}$points] -fill $color -width $width -tags relationship_geometry}}}
    }
}
proc ::GX::CurveWorkbench::_sketchAffected {w ids} {
    variable st;set nativeIds {};set result $ids
    foreach id $ids {if {[dict exists $st($w,curves) $id]&&[dict exists [_record $w $id] sketch_definition]} {
        foreach native [::GX::Native2D::core sketch_component $st($w,scene) [dict get [_record $w $id] native]] {lappend nativeIds $native}
    }}
    dict for {id record} $st($w,curves) {if {[dict get $record native] in $nativeIds&&$id ni $result} {lappend result $id}}
    return $result
}
rename ::GX::CurveWorkbench::_snapshotIds ::GX::CurveWorkbench::_snapshotIds_sketch054_base
proc ::GX::CurveWorkbench::_snapshotIds {w ids} {_snapshotIds_sketch054_base $w [_sketchAffected $w $ids]}
proc ::GX::CurveWorkbench::_constraintAction {w action} {
    variable st
    set id [_constraintSelected $w];set record [dict get $st($w,constraints) $id];set spec [dict get $record definition];set ids {}
    foreach key {a b axis} {if {[dict exists $spec $key]} {lappend ids [dict get $spec $key]}}
    _cancelGesture $w
    set before [_snapshotIds $w $ids]
    [_advancedRelationships $w] constraint manage [dict get $record native] [expr {$action eq {remove}?{remove}:{toggle}}]
    if {$action eq {remove}} {dict unset st($w,constraints) $id} else {set st($w,selectedRelationship) $id}
    foreach logical [_sketchAffected $w $ids] {if {[dict exists [_record $w $logical] sketch_definition]} {_syncSamples $w $logical}}
    _history $w $before $ids;_constraintRefresh $w;_draw $w
}
