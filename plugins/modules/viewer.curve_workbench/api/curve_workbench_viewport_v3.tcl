proc ::GX::CurveWorkbench::_constraintPanel {w} {
    variable st
    if {[info exists st($w,constraintPanel)]} {return $st($w,constraintPanel)}
    return $w.constraints
}
# SPDX-License-Identifier: GPL-3.0-or-later
# Viewer orchestration only: shared chrome owns placement and Native owns every
# scientific coordinate, spline arm, transform and semantic reference.
proc ::GX::CurveWorkbench::_buildViewport {w} {
    variable st
    foreach {key value} {leftVisible 1 listVisible 1 pointsVisible 1 composeVisible 1 compareVisible 0 utilityOverride 0 tangentDrag {} zoomBox {} viewportReady 0} {set st($w,$key) $value}
    pack forget $w.right.viewport.canvas
    pack $w.right.viewport -fill both -expand 1 -before $w.right.residualLabel
    pack $w.right.viewport.canvas -in $w.right.viewport -fill both -expand 1
    ::GX::native2DViewportHostCreate $w.right.viewport $w.right.viewport.canvas $st($w,scene) [list ::GX::CurveWorkbench::_viewportChanged $w]
    set actions [dict create fit_all [list ::GX::CurveWorkbench::_fit $w 0] reset [list ::GX::CurveWorkbench::_fit $w 0] fit_selected [list ::GX::CurveWorkbench::_fit $w 1] pan [list ::GX::CurveWorkbench::_scienceTool $w pan] object_snap [list ::GX::CurveWorkbench::_objectSnapToggle $w] zoom_box [list ::GX::CurveWorkbench::_zoomBoxStart $w]]
    set st($w,viewportControls) [::GX::native2DViewportControls $w.right.viewport.canvas {select transform fit_all fit_selected zoom_in zoom_out zoom_box pan reset grid grid_snap object_snap} $actions]
    set body [::GX::native2DViewportPanelCreate $w.right.viewport.canvas compare {Compare / residuals} bottom-right {max_width 360 max_height 480 min_width 220 priority 5 scroll 1 close 1}]
    set st($w,comparisonControls) $body
    set panel [::GX::native2DViewportPanelWidget $w.right.viewport.canvas compare]
    $panel.header.toggle configure -command [list ::GX::CurveWorkbench::_compareToggle $w]
    $panel.header.close configure -command [list ::GX::CurveWorkbench::_comparisonPanelHide $w]
    ::GX::native2DViewportPanelCollapse $w.right.viewport.canvas compare 1
    ttk::menubutton $w.toolbar.settings -text Settings -menu $w.toolbar.settings.menu
    set menu $w.toolbar.settings.menu;menu $menu -tearoff 0
    foreach {key label} {leftVisible {Left utility area} listVisible {Objects list} pointsVisible {Defining handles / points} composeVisible {Ordered composition}} {
        $menu add checkbutton -label $label -variable ::GX::CurveWorkbench::st($w,$key) -command [list ::GX::CurveWorkbench::_utilityVisibility $w]
    }
    $menu add separator
    $menu add command -label {Grid / background / view…} -command [list ::GX::CurveWorkbench::_gridOpen $w]
    $menu add command -label {Direction presentation…} -command [list ::GX::CurveWorkbench::_directionOpen $w]
    $menu add command -label {Composition settings…} -command [list ::GX::CurveWorkbench::_bridgeSettings $w]
    pack forget $w.right.display
    set st($w,viewportReady) 1
    bind $w.right.viewport.canvas <Configure> +[list after 10 [list ::GX::CurveWorkbench::_responsiveCompare $w]]
    bind $w.right.viewport.canvas <Button-3> [list ::GX::CurveWorkbench::_viewportContext $w %x %y %X %Y]
    _commandLayout $w [winfo width $w.toolbar]
    _sketchBarLayout $w [winfo width $w.sketchbar]
}
rename ::GX::CurveWorkbench::_commandLayout ::GX::CurveWorkbench::_commandLayout_viewport056_base
proc ::GX::CurveWorkbench::_commandLayout {w width} {
    variable st
    if {![winfo exists $w.toolbar.settings]} {tailcall _commandLayout_viewport056_base $w $width}
    set children {};foreach key {add undo redo objects points view settings workspace} {if {[winfo exists $w.toolbar.$key]} {lappend children $w.toolbar.$key}}
    if {$st($w,moreControls)} {foreach key {duplicate split reverse visibility lock remove insert pan sourcePreview} {if {[winfo exists $w.toolbar.$key]} {lappend children $w.toolbar.$key}}}
    foreach child [winfo children $w.toolbar] {if {$child ni $children} {pack forget $child;grid forget $child}}
    ::GX::native2DToolbarLayout $w.toolbar $width $children
}
rename ::GX::CurveWorkbench::_sketchBarLayout ::GX::CurveWorkbench::_sketchBarLayout_viewport056_base
proc ::GX::CurveWorkbench::_sketchBarLayout {w width} {
    _sketchBarLayout_viewport056_base $w $width

}
proc ::GX::CurveWorkbench::_viewportChanged {w} {_draw $w;_viewPersistLater $w}
proc ::GX::CurveWorkbench::_objectSnapToggle {w} {variable st;set st($w,cadObjectSnap) [expr {!$st($w,cadObjectSnap)}]}
proc ::GX::CurveWorkbench::_utilityVisibility {w {automatic 0}} {
    variable st
    if {!$automatic} {set st($w,utilityOverride) 1}
    if {$st($w,leftVisible)} {if {"${w}.leftScroll" ni [$w.main panes]} {$w.main insert 0 $w.leftScroll -weight 0}} elseif {"${w}.leftScroll" in [$w.main panes]} {$w.main forget $w.leftScroll}
    foreach {key widgets} {listVisible {active curveFrame renameRow} pointsVisible {pointFrame pager numeric interval} composeVisible {compose}} {
        foreach name $widgets {
            set widget $w.leftScroll.viewport.content.$name
            if {![winfo exists $widget]} continue
            if {$st($w,$key)} {pack $widget -fill x -pady 3} else {pack forget $widget}
        }
    }
    _save $w
}
proc ::GX::CurveWorkbench::_compareToggle {w} {
    variable st
    ::GX::native2DViewportPanelToggle $w.right.viewport.canvas compare
    set st($w,compareVisible) [expr {![dict get $::GX::ViewportHost::hosts $w.right.viewport.canvas panels compare collapsed]}]
    _viewportChanged $w
}
proc ::GX::CurveWorkbench::_comparisonPanelOpen {w} {
    variable st
    set st($w,compareVisible) 1
    ::GX::native2DViewportPanelShow $w.right.viewport.canvas compare 1
    ::GX::native2DViewportPanelCollapse $w.right.viewport.canvas compare 0
    _comparisonRefresh $w
    _viewportChanged $w
}
proc ::GX::CurveWorkbench::_comparisonPanelHide {w} {
    variable st
    set st($w,compareVisible) 0
    ::GX::native2DViewportPanelShow $w.right.viewport.canvas compare 0
    _viewportChanged $w
}
rename ::GX::CurveWorkbench::_constraintOpen ::GX::CurveWorkbench::_constraintOpen_viewport056_base
proc ::GX::CurveWorkbench::_constraintOpen {w} {
    variable st
    set panel [::GX::native2DViewportPanelWidget $w.right.viewport.canvas palette]
    if {![winfo exists $panel]} {
        set body [::GX::native2DViewportPanelCreate $w.right.viewport.canvas palette {Sketch palette} top-right {max_width 350 max_height 420 scroll 1}]
        # The inspector is an actual descendant of the scrolling canvas. A
        # toplevel sibling in a canvas window item can remain mapped outside
        # the panel and intercept geometry clicks after collapse.
        set st($w,constraintPanel) $body.inspector
    }
    _constraintOpen_viewport056_base $w
    place forget [_constraintPanel $w]
    pack [_constraintPanel $w] -in $panel.body.scroll.content -fill both -expand 1
    ::GX::native2DViewportPanelShow $w.right.viewport.canvas palette 1
    ::GX::native2DViewportPanelCollapse $w.right.viewport.canvas palette 0
}
rename ::GX::CurveWorkbench::_paletteAction ::GX::CurveWorkbench::_paletteAction_viewport056_base
proc ::GX::CurveWorkbench::_paletteAction {w action} {
    if {$action eq "hide"} {::GX::native2DViewportPanelCollapse $w.right.viewport.canvas palette 1;return}
    tailcall _paletteAction_viewport056_base $w $action
}
proc ::GX::CurveWorkbench::_viewportContext {w x y X Y} {
    variable st
    set relationship [_relationshipPick $w $x $y]
    if {$relationship ne {}} {tailcall _relationshipContext $w $x $y $X $Y}
    set arrow [_partHit $w $x $y]
    set target [_sketchPick $w $x $y]
    if {$arrow ne {}} {set logical [lindex $arrow 0];set target [::GX::Native2D::core interaction_reference $st($w,scene) [dict get [_record $w $logical] native] object 0];dict set target logical $logical}
    set menu $w.right.viewport.canvasContext
    if {![winfo exists $menu]} {menu $menu -tearoff 0}
    if {$target ne {}} {
        _semanticSync $w
        set selected 0
        foreach ref $st($w,sketchSelection) {if {[dict get $ref object]==[dict get $target object]&&[dict get $ref index]==[dict get $target index]} {set selected 1}}
        if {!$selected} {_selectReference $w $target 0}
        _commandMenu $w $menu {object.duplicate object.delete object.split - object.join object.combine object.separate - object.show object.hide object.lock object.unlock - transform transform.translate transform.rotate - object.publish object.promote - view.fit_selection}
        set constraints $menu.constraints
        if {![winfo exists $constraints]} {menu $constraints -tearoff 0}
        set ids {};dict for {kind definition} [_constraintOptions $w] {if {[dict exists $st($w,commands) constraint.$kind]} {lappend ids constraint.$kind}}
        if {$ids ne {}} {_commandMenu $w $constraints $ids;$menu add cascade -label Constraints -menu $constraints}
        $menu add command -label {Inspect / remove constraints...} -command [list ::GX::CurveWorkbench::_constraintOpen $w]
        $menu add command -label {Parameters...} -command [list ::GX::CurveWorkbench::_parametersOpen $w]
        _directionMenu $w $menu [dict get $target logical] $x $y
    } else {
        _commandMenu $w $menu {select select.window select.polygon - create.line create.rectangle create.circle create.arc create.spline create.cubic_bezier - view.fit_all view.fit_selection view.pan - object.duplicate}
    }
    ::GX::uiMenuPopup $menu $X $Y
}

proc ::GX::CurveWorkbench::_zoomBoxStart {w} {_sketchIdle $w;variable st;set st($w,zoomBox) ready;set st($w,toolLabel) {Zoom box — drag a rectangle. Esc cancels.}}
proc ::GX::CurveWorkbench::_tangentHandles {w} {
    variable st;set handles {}
    if {![info exists st($w,sketchSelection)]} {return {}}
    foreach ref $st($w,sketchSelection) {
        if {[dict get $ref entity] ne "control"} continue
        set record [_record $w [dict get $ref logical]]
        if {![dict exists $record sketch_definition]} continue
        # CORE resolves Spline constituents from the Path's defining-control
        # ordinal; Tcl does not maintain a second part/transform mapping.
        set knot [expr {[dict get $ref index]-1000000000}]
        foreach incoming {1 0} {
            if {[catch {set handle [::GX::Native2D::core spline_tangent $st($w,scene) [dict get $record native] $knot $incoming]}]} continue
            dict set handle logical [dict get $ref logical];dict set handle knot $knot;dict set handle incoming $incoming
            dict set handle device [::GX::Native2D::core device $st($w,scene) [dict get $handle point]]
            lappend handles $handle
        }
    }
    return $handles
}
proc ::GX::CurveWorkbench::_drawTangentHandles {w} {
    variable st;    foreach handle [_tangentHandles $w] {
        lassign [dict get $handle device] x y
        set anchor [::GX::Native2D::core device $st($w,scene) [dict get $handle anchor]]
        $w.right.viewport.canvas create line {*}$anchor $x $y -fill #7952b3 -width 1.5 -tags spline_tangent_arm
        $w.right.viewport.canvas create oval [expr {$x-6}] [expr {$y-6}] [expr {$x+6}] [expr {$y+6}] -fill #ffdb72 -outline #59328c -width 2 -tags spline_tangent_handle
    }
    if {[info exists st($w,viewportReady)]&&$st($w,viewportReady)} {::GX::native2DViewportSyncControls $w.right.viewport.canvas}
}
proc ::GX::CurveWorkbench::_pointerDownViewport {w x y state} {
    variable st
    if {$st($w,zoomBox) eq "ready"} {set st($w,zoomBox) [list $x $y];return 1}
    if {$st($w,canvasTool) eq "select"&&$st($w,cadTool) eq "none"} {
        foreach handle [_tangentHandles $w] {
            lassign [dict get $handle device] hx hy
            if {hypot($x-$hx,$y-$hy)>11} continue
            set id [dict get $handle logical];if {[dict get [_record $w $id] locked]} {return 1}
            set st($w,tangentDrag) [dict merge $handle [dict create before [_snapshotIds $w [list $id]] moved 0]]
            return 1
        }
    }
    return 0

    return 1
}
proc ::GX::CurveWorkbench::_pointerMoveViewport {w x y} {
    variable st
    if {$st($w,zoomBox) ne {}&&$st($w,zoomBox) ne "ready"} {$w.right.viewport.canvas delete zoom_box;$w.right.viewport.canvas create rectangle {*}$st($w,zoomBox) $x $y -outline #426cbb -dash {4 3} -tags zoom_box;return 1}
    if {$st($w,tangentDrag) eq {}} {return 0}
    set drag $st($w,tangentDrag);set id [dict get $drag logical]
    set point [::GX::Native2D::core world $st($w,scene) [list $x $y]]
    if {[catch {::GX::Native2D::core spline_tangent $st($w,scene) [dict get [_record $w $id] native] [dict get $drag knot] [dict get $drag incoming] $point} message]} {set st($w,status) "Tangent edit rejected: $message";return 1}
    dict set st($w,tangentDrag) moved 1;_syncSamples $w $id;_draw $w

    return 1
}
proc ::GX::CurveWorkbench::_pointerUpViewport {w x y} {
    variable st
    if {$st($w,zoomBox) ne {}&&$st($w,zoomBox) ne "ready"} {
        lassign $st($w,zoomBox) ax ay;set st($w,zoomBox) {};$w.right.viewport.canvas delete zoom_box
        if {abs($ax-$x)>4&&abs($ay-$y)>4} {
            lassign [::GX::Native2D::core world $st($w,scene) [list $ax $ay]] x0 y0
            lassign [::GX::Native2D::core world $st($w,scene) [list $x $y]] x1 y1
            ::GX::Native2D::core fit_bounds $st($w,scene) [list [expr {min($x0,$x1)}] [expr {min($y0,$y1)}] [expr {max($x0,$x1)}] [expr {max($y0,$y1)}]];_viewportChanged $w
        };return 1
    }
    if {$st($w,tangentDrag) eq {}} {return 0}
    set drag $st($w,tangentDrag);set st($w,tangentDrag) {}
    if {[dict get $drag moved]} {_history $w [dict get $drag before] [list [dict get $drag logical]]}

    return 1
}
rename ::GX::CurveWorkbench::_sketchIdle ::GX::CurveWorkbench::_sketchIdle_viewport056_base
proc ::GX::CurveWorkbench::_sketchIdle {w {message {Select — geometry, handles, constraints or dimensions.}}} {
    variable st
    if {[info exists st($w,tangentDrag)]&&$st($w,tangentDrag) ne {}} {set before [dict get $st($w,tangentDrag) before];set st($w,tangentDrag) {};_restoreSnapshot $w $before}
    set st($w,zoomBox) {};tailcall _sketchIdle_viewport056_base $w $message
}
rename ::GX::CurveWorkbench::_sketchTool ::GX::CurveWorkbench::_sketchTool_viewport056_base
proc ::GX::CurveWorkbench::_sketchTool {w family} {
    _sketchTool_viewport056_base $w $family
    if {$family eq "polyline"} {variable st;set st($w,toolLabel) {Segmented curve — successive vertices make ONE Polyline. Enter / Finish commits; click start to close.}}
}

proc ::GX::CurveWorkbench::_buildWorkspace {w} {
    variable st;variable openingName
    set st($w,workspaceName) $openingName
    ttk::menubutton $w.toolbar.workspace -text Workspace -menu $w.toolbar.workspace.menu
    set menu $w.toolbar.workspace.menu;menu $menu -tearoff 0
    foreach {label command} [list {New named workspace…} [list ::GX::CurveWorkbench::_newWorkspace $w] {Rename workspace…} [list ::GX::CurveWorkbench::_renameWorkspace $w] {Session Workspaces…} [list ::GX::sessionWorkspaceDialog $w] {View notes} [list ::GX::CurveWorkbench::_workspaceNotes $w view] {Edit notes} [list ::GX::CurveWorkbench::_workspaceNotes $w edit]] {$menu add command -label $label -command $command}
    $menu add command -label {Workspace Configuration…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_coordinateConfigurationOpen $w]]
    _commandLayout $w [winfo width $w.toolbar]
}
proc ::GX::CurveWorkbench::_newWorkspace {w} {
    set fields [dict merge {name {type string required 1 label Name}} [_coordinateConfigurationFields]]
    set values [dict merge {name {New curve workspace}} [dict remove [_coordinateConfigurationDefault] schema]]
    ::GX::uiFieldFormCreate $w.newWorkspace {New workspace — physical Configuration} $fields $values [list ::GX::CurveWorkbench::_newWorkspaceApply $w] $w
}
proc ::GX::CurveWorkbench::_newWorkspaceApply {w values} {
    set name [::GX::_workspaceName [dict get $values name]]
    set configuration [_coordinateConfigurationNormalize [dict remove $values name]]
    _close $w
    set next [open [dict create workspace_id new workspace_name $name coordinate_configuration $configuration]]
    _save $next
}
proc ::GX::CurveWorkbench::_renameWorkspace {w} {
    variable st;_save $w
    ::GX::uiFieldFormCreate $w.renameWorkspace {Rename Session workspace} {name {type string required 1 label Name}} [dict create name [dict get [::GX::sessionWorkspaceGet $st($w,document)] name]] [list ::GX::CurveWorkbench::_renameWorkspaceApply $w] $w
}
proc ::GX::CurveWorkbench::_renameWorkspaceApply {w values} {variable st;::GX::sessionWorkspaceRename $st($w,document) [dict get $values name];set st($w,workspaceName) [dict get $values name]}
proc ::GX::CurveWorkbench::_workspaceNotes {w mode} {variable st;_save $w;::GX::noteDocumentOpen $st($w,document) $mode}
proc ::GX::CurveWorkbench::_restoreViewportPreferences {w} {
    variable st;if {![winfo exists $w]} return
    # Responsive layout may already have removed this pane before the idle
    # saved-preference callback. Reapplying hidden state must be idempotent.
    if {!$st($w,leftVisible)&&"${w}.leftScroll" in [$w.main panes]} {$w.main forget $w.leftScroll}
    foreach {key widgets} {listVisible {active curveFrame renameRow} pointsVisible {pointFrame pager numeric interval} composeVisible {compose}} {if {!$st($w,$key)} {foreach name $widgets {set widget $w.leftScroll.viewport.content.$name;if {[winfo exists $widget]} {pack forget $widget}}}}
    ::GX::native2DViewportPanelCollapse $w.right.viewport.canvas compare [expr {!$st($w,compareVisible)}]
}
proc ::GX::CurveWorkbench::_buildImages {w} {
    variable st
    set st($w,images) {};set st($w,nextImage) 0;set st($w,imageCalibration) {};set st($w,symmetryAxis) {};set st($w,symmetryEnabled) 0;set st($w,mirrorPreview) {}
    $w.toolbar.workspace.menu add separator
    foreach {label command} [list {Background image / reference graphic…} [list _imageAttach $w] {Reference images…} [list _imagesOpen $w] {Refresh scene preview} [list _workspacePreview $w]] {
        set callback [lreplace $command 0 0 ::GX::CurveWorkbench::[lindex $command 0]]
        $w.toolbar.workspace.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w $callback]
    }
    $w.publish.save configure -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_workspaceSaveReviewed $w]]
    $w.sketchbar.create.menu add separator
    $w.sketchbar.create.menu add checkbutton -label {Draw with selected symmetry axis} -variable ::GX::CurveWorkbench::st($w,symmetryEnabled) -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_symmetryActivate $w]]
}
proc ::GX::CurveWorkbench::_imageAttach {w} {
    variable st
    set file [::GX::workspaceOpenFile acquisition_dir -title {Attach calibrated reference image} -filetypes {{{Raster images} {.png .jpg .jpeg .gif .bmp .tif .tiff}} {{All files} *}}]
    if {$file eq {}} return
    ::GX::unitRegistryConversionPlan $st($w,sketchUnit) m
    _save $w
    set path [file normalize $file];lassign [::GX::_native2DRasterHelper info $path] width height
    set resource [::GX::interactiveDocumentResourceImportNumeric $st($w,document) $path {format image.raster}]
    set state [dict create resource_id [dict get $resource sha256] length_unit $st($w,sketchUnit) width $width height $height scale 1 rotation 0 translation {0 0} opacity .7 visible 1 locked 0]
    set before [_snapshotIds $w {}];set native [::GX::Native2D::core image_create $st($w,scene) $state]
    try {
        ::GX::native2DReferenceImageBind $st($w,scene) $native $resource
        set id image[incr st($w,nextImage)]
        dict set st($w,images) $id [dict create id $id name [file tail $file] native $native resource $resource]
        ::GX::Native2D::core aspect $st($w,scene) xy_equal
        _history $w $before {};::GX::Native2D::core fit $st($w,scene);_viewportChanged $w
        _imagesOpen $w
    } on error {message options} {if {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native};return -options $options $message}
}
proc ::GX::CurveWorkbench::_imagesOpen {w} {
    variable st
    set d $w.referenceImages;catch {destroy $d};toplevel $d;wm title $d {Reference images};wm transient $d $w
    ttk::treeview $d.tree -columns {name calibration opacity visible locked} -show headings -selectmode browse -height 6
    foreach key {name calibration opacity visible locked} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 100}
    pack $d.tree -fill both -expand 1
    bind $d.tree <<TreeviewSelect>> [list ::GX::CurveWorkbench::_imageSummary $w]
    dict for {id record} $st($w,images) {
        set image [::GX::Native2D::core image_get $st($w,scene) [dict get $record native]]
        $d.tree insert {} end -id $id -values [list [dict get $record name] [expr {[dict get $image calibrated]?"calibrated":"not calibrated"}] [format %.0f [expr {100*[dict get $image opacity]}]] [dict get $image visible] [dict get $image locked]]
    }
    $d.tree heading opacity -text {Opacity (%)}
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -before $d.tree
    bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    foreach {key title action} {calibrate {Pick calibration points} calibrate reset {Reset calibration} reset state {Transform / opacity / lock…} state delete Remove delete} {
        ttk::button $d.actions.$key -text $title -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_imageAction $w $action]];pack $d.actions.$key -side left -padx 3
    }
    set st($w,imageSummary) {Select an image to inspect calibration, units and transform. Two reference points define a uniform physical scale.}
    ttk::label $d.help -textvariable ::GX::CurveWorkbench::st($w,imageSummary) -wraplength 600;pack $d.help -side bottom -fill x -before $d.tree -padx 6 -pady 5
    wm geometry $d 680x270
}
proc ::GX::CurveWorkbench::_imageAction {w action} {
    variable st
    set id [$w.referenceImages.tree selection];if {[llength $id]!=1} {error {Select one reference image}}
    set native [dict get $st($w,images) $id native]
    set state [::GX::Native2D::core image_get $st($w,scene) $native]
    set st($w,status) "Image: [expr {[dict get $state calibrated]?{calibrated}:{unscaled — calibrate before dimensioning}}]; unit [dict get $state length_unit]; scale [dict get $state scale]; rotation [dict get $state rotation] rad; translation [dict get $state translation]."
    if {$action eq "calibrate"} {
        if {[dict get $state locked]} {error {Unlock the reference image before calibration}}
        destroy $w.referenceImages;_sketchIdle $w
        set st($w,imageCalibration) [dict create id $id points {} before [_snapshotIds $w {}]]
        set st($w,toolLabel) {Calibration — pick two recognizable reference points on the image.}
        return
    }
    if {$action eq "reset"} {set before [_snapshotIds $w {}];dict set state calibrated 0;::GX::Native2D::core image_update $st($w,scene) $native $state;_history $w $before {};_imagesOpen $w;return}
    if {$action eq "delete"} {set before [_snapshotIds $w {}];::GX::Native2D::core delete $st($w,scene) $native;dict unset st($w,images) $id;_history $w $before {};_imagesOpen $w;return}
    set fields [dict create x {type number label {Translation X}} y {type number label {Translation Y}} rotation {type number label {Rotation (degrees)}} scale {type number min 0 label {Uniform scale}} opacity {type number min 0 max 100 label {Opacity (%)}} visible {type boolean label Visible} locked {type boolean label Locked}]
    set values [dict merge $state [dict create x [lindex [dict get $state translation] 0] y [lindex [dict get $state translation] 1] rotation [expr {[dict get $state rotation]*180/acos(-1)}]]]
    dict set values opacity [expr {100*[dict get $state opacity]}]
    ::GX::uiFieldFormCreate $w.imageState {Reference image — uniform transform} $fields $values [list ::GX::CurveWorkbench::_imageStateApply $w $id] $w
    if {[dict get $state calibrated]} {
        set scaleField [dict get $::GX::UiField::forms $w.imageState widgets scale]
        $scaleField.entry configure -state readonly
        set ::GX::UiField::formStatus($w.imageState) {Scale comes from physical calibration. Use Reset calibration or Pick calibration points to change it.}
    }
}
proc ::GX::CurveWorkbench::_imageStateApply {w id values} {
    variable st
    set before [_snapshotIds $w {}];set native [dict get $st($w,images) $id native]
    set state [::GX::Native2D::core image_get $st($w,scene) $native]
    set changes [dict create translation [list [dict get $values x] [dict get $values y]] rotation [expr {[dict get $values rotation]*acos(-1)/180}]]
    foreach key {scale visible locked} {dict set changes $key [dict get $values $key]}
    dict set changes opacity [expr {[dict get $values opacity]/100.0}]
    ::GX::Native2D::core image_update $st($w,scene) $native [dict merge $state $changes]
    _history $w $before {};_imagesRefresh $w
}
proc ::GX::CurveWorkbench::_imageCalibrationApply {w id points before values} {
    variable st
    set native [dict get $st($w,images) $id native]
    set image [::GX::Native2D::core image_get $st($w,scene) $native]
    set distance [lindex [::GX::unitRegistryConvertCoordinates [dict get $values unit] [dict get $image length_unit] [list [dict get $values distance]]] 0]
    ::GX::Native2D::core image_calibrate $st($w,scene) $native {*}$points $distance
    set st($w,imageCalibration) {};_history $w $before {};_draw $w
    set st($w,status) {Reference image uniformly calibrated. Its reference points are Native controls usable by snapping and construction.}
}
proc ::GX::CurveWorkbench::_workspacePreview {w} {
    variable st;_save $w
    set resource [::GX::native2DCanvasPreview $st($w,scene) $st($w,document) fit {width 480 height 300}]
    ::GX::sessionWorkspacePreviewSet $st($w,document) $resource
    set st($w,status) {Session workspace scene preview refreshed; UI chrome and transient feedback are excluded.}
    return $resource
}
proc ::GX::CurveWorkbench::_workspaceSaveReviewed {w} {
    _workspacePreview $w
    # Mark the complete payload plus preview association as the explicit saved
    # snapshot; an ordinary autosave must never replace this recovery choice.
    _saveExplicit $w
}
proc ::GX::CurveWorkbench::_imageSnapshot {w} {
    variable st;set records {}
    dict for {id record} $st($w,images) {dict set record state [::GX::Native2D::core image_get $st($w,scene) [dict get $record native]];dict set records $id [dict remove $record native]}
    return $records
}
proc ::GX::CurveWorkbench::_imageRestore {w records} {
    variable st
    dict for {id record} $st($w,images) {set native [dict get $record native];if {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}}
    set st($w,images) {}
    dict for {id record} $records {
        set native [::GX::Native2D::core image_create $st($w,scene) [dict get $record state]]
        ::GX::native2DReferenceImageBind $st($w,scene) $native [dict get $record resource]
        dict set record native $native;dict set st($w,images) $id $record
    }
}
proc ::GX::CurveWorkbench::_drawReferenceImages {w} {
    variable st;    if {[info exists st($w,images)]&&$st($w,images) ne {}} {
        ::GX::native2DCanvasReferenceImages $st($w,scene) $w.right.viewport.canvas
        dict for {id record} $st($w,images) {
            set native [dict get $record native];set image [::GX::Native2D::core image_get $st($w,scene) $native]
            if {![dict get $image calibrated]||![dict get $image visible]} continue
            foreach handle [lrange [::GX::Native2D::core interaction_controls $st($w,scene) $native] 2 3] {
                lassign [::GX::Native2D::core device $st($w,scene) [dict get $handle point]] x y
                $w.right.viewport.canvas create rectangle [expr {$x-4}] [expr {$y-4}] [expr {$x+4}] [expr {$y+4}] -outline #8e4d20 -width 2 -tags image_calibration_reference
            }
        }
    }
    if {[info exists st($w,mirrorPreview)]&&$st($w,mirrorPreview) ne {}} {::GX::native2DCanvasDrawObject $w.right.viewport.canvas [::GX::native2DPresentationObjectSnapshot $st($w,scene) $st($w,mirrorPreview)] #FFFFFF symmetry_preview}
}
proc ::GX::CurveWorkbench::_pointerDownImage {w x y state} {
    variable st
    if {$st($w,imageCalibration) eq {}} {return 0}
    set id [dict get $st($w,imageCalibration) id];set native [dict get $st($w,images) $id native]
    set world [::GX::Native2D::core world $st($w,scene) [list $x $y]]
    set pixel [::GX::Native2D::core image_map $st($w,scene) $native $world 1]
    set image [::GX::Native2D::core image_get $st($w,scene) $native]
    if {[lindex $pixel 0]<0||[lindex $pixel 1]<0||[lindex $pixel 0]>[dict get $image width]||[lindex $pixel 1]>[dict get $image height]} {set st($w,status) {Pick a point inside the reference image};return 1}
    dict lappend st($w,imageCalibration) points $pixel
    if {[llength [dict get $st($w,imageCalibration) points]]==2} {
        set context $st($w,imageCalibration);set st($w,imageCalibration) {}
        ::GX::uiFieldFormCreate $w.calibration {Reference image calibration} [dict create distance {type number min 0 label {Known physical distance}} unit {type string required 1 label {Compatible length unit}}] [dict create distance 10 unit [dict get $image length_unit]] [list ::GX::CurveWorkbench::_imageCalibrationApply $w $id [dict get $context points] [dict get $context before]] $w
    } else {set st($w,toolLabel) {Calibration — pick the second recognizable point.}}

    return 1
}

# One logical/native resolver includes image objects without treating their
# raster pixels as scientific curve samples or giving them a Dataset identity.
proc ::GX::CurveWorkbench::_logicalNativeMap {w} {
    variable st;set reverse {}
    dict for {id record} $st($w,curves) {dict set reverse [dict get $record native] $id}
    if {[info exists st($w,images)]} {dict for {id record} $st($w,images) {dict set reverse [dict get $record native] $id}}
    return $reverse
}
rename ::GX::CurveWorkbench::_record ::GX::CurveWorkbench::_record_images056_base
proc ::GX::CurveWorkbench::_record {w id} {
    variable st
    if {[info exists st($w,images)]&&[dict exists $st($w,images) $id]} {
        set record [dict get $st($w,images) $id];set image [::GX::Native2D::core image_get $st($w,scene) [dict get $record native]]
        return [dict merge $record [dict create working_unit [dict get $image length_unit] locked 1 visible [dict get $image visible] samples {} source {} x x y y]]
    }
    tailcall _record_images056_base $w $id
}
rename ::GX::CurveWorkbench::_sketchPick ::GX::CurveWorkbench::_sketchPick_images056_base
proc ::GX::CurveWorkbench::_sketchPick {w x y} {
    variable st
    set ref [_sketchPick_images056_base $w $x $y];if {$ref ne {}} {return $ref}
    if {$st($w,constraintTool) ne "dimension"} {return {}}
    dict for {id record} $st($w,images) {
        set ref [::GX::Native2D::core interaction_pick $st($w,scene) [dict get $record native] [list $x $y] 10]
        if {$ref ne {}&&[dict get $ref entity] eq "control"&&[dict get $ref index]>=1000000002} {dict set ref logical $id;return $ref}
    }
    return {}
}
proc ::GX::CurveWorkbench::_symmetryActivate {w} {
    variable st
    if {!$st($w,symmetryEnabled)} {set st($w,symmetryAxis) {};_toolPreviewClear $w;return}
    set id [_active $w];set record [_record $w $id]
    if {![dict exists $record sketch_definition]||[dict get $record sketch_definition family] ni {line construction_line}} {set st($w,symmetryEnabled) 0;error {Select a retained Line or Construction line as the symmetry axis}}
    set st($w,symmetryAxis) $id
    set st($w,toolLabel) "Symmetry axis: [dict get $record name]. Choose a supported drawing tool; source and mirror will stay related."
}
rename ::GX::CurveWorkbench::_toolPreview ::GX::CurveWorkbench::_toolPreview_symmetry056_base
proc ::GX::CurveWorkbench::_toolPreview {w definition} {
    variable st
    _toolPreview_symmetry056_base $w $definition
    if {!$st($w,symmetryEnabled)||$st($w,symmetryAxis) eq {}} return
    set axis [::GX::Native2D::core interaction_reference $st($w,scene) [dict get [_record $w $st($w,symmetryAxis)] native] segment 0]
    if {[catch {set reflected [dict get [::GX::Native2D::core symmetry_preview $st($w,scene) $axis $definition] definition]} message]} {set st($w,status) "Symmetry preview: unsupported construction — $message";return}
    set st($w,mirrorPreview) [::GX::Native2D::core sketch_create $st($w,scene) $reflected 257]
    ::GX::Native2D::core object_style $st($w,scene) $st($w,mirrorPreview) {selectable 0 color {.6 .3 .8 .7}}
}
rename ::GX::CurveWorkbench::_toolPreviewClear ::GX::CurveWorkbench::_toolPreviewClear_symmetry056_base
proc ::GX::CurveWorkbench::_toolPreviewClear {w} {
    variable st
    if {[info exists st($w,mirrorPreview)]&&$st($w,mirrorPreview) ne {}} {::GX::Native2D::core delete $st($w,scene) $st($w,mirrorPreview);set st($w,mirrorPreview) {}}
    tailcall _toolPreviewClear_symmetry056_base $w
}
rename ::GX::CurveWorkbench::_sketchIdle ::GX::CurveWorkbench::_sketchIdle_images056_base
proc ::GX::CurveWorkbench::_sketchIdle {w {message {Select — geometry, handles, constraints or dimensions.}}} {
    variable st;_partCancel $w;set st($w,imageCalibration) {}
    tailcall _sketchIdle_images056_base $w $message
}


proc ::GX::CurveWorkbench::_responsiveCompare {w} {
    variable st
    if {![winfo exists $w.right.viewport.canvas]||![info exists st($w,viewportReady)]||!$st($w,viewportReady)} return
    if {[winfo width $w]<1000&&$st($w,leftVisible)&&!$st($w,utilityOverride)} {set st($w,leftVisible) 0;_utilityVisibility $w 1}
    if {[winfo height $w.right.viewport.canvas]<170&&$st($w,compareVisible)} {set st($w,compareVisible) 0;::GX::native2DViewportPanelCollapse $w.right.viewport.canvas compare 1}
}

proc ::GX::CurveWorkbench::_imagesRefresh {w} {
    variable st
    set tree $w.referenceImages.tree
    if {![winfo exists $tree]} return
    set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} $st($w,images) {
        set image [::GX::Native2D::core image_get $st($w,scene) [dict get $record native]]
        $tree insert {} end -id $id -values [list [dict get $record name] [expr {[dict get $image calibrated]?"calibrated":"not calibrated"}] [format %.0f [expr {100*[dict get $image opacity]}]] [dict get $image visible] [dict get $image locked]]
    }
    if {[llength $selected]==1&&[$tree exists $selected]} {$tree selection set $selected}
}

proc ::GX::CurveWorkbench::_imageSummary {w} {
    variable st;set tree $w.referenceImages.tree
    if {![winfo exists $tree]||[llength [$tree selection]]!=1} return
    set id [lindex [$tree selection] 0]
    if {![dict exists $st($w,images) $id]} return
    set image [::GX::Native2D::core image_get $st($w,scene) [dict get $st($w,images) $id native]]
    set st($w,imageSummary) "[expr {[dict get $image calibrated]?{Calibrated}:{Unscaled — calibrate before dimensioning}}]. Unit: [dict get $image length_unit]; uniform scale: [dict get $image scale] / pixel; rotation: [dict get $image rotation] rad; translation: [dict get $image translation]."
}
