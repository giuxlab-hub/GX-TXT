# SPDX-License-Identifier: GPL-3.0-or-later
# Parametric containers persist logical identities separately from static groups.
rename ::GX::CurveWorkbench::_seriesApply ::GX::CurveWorkbench::_seriesApply_static_base
proc ::GX::CurveWorkbench::_seriesApply {w token ids values} {
    variable st
    if {[dict get $values circular]} {return [_seriesApply_static_base $w $token $ids $values]}
    set parameters [dict create rows [dict get $values rows] columns [dict get $values columns] step_u [list [dict get $values spacing_x] [::GX::datasetPublicationV2DictDefault $values column_y 0]] step_v [list [::GX::datasetPublicationV2DictDefault $values row_x 0] [dict get $values spacing_y]] include_origin [dict get $values include_origin]]
    return [_seriesCommit $w $token {} $ids [dict get $values name] $parameters]
}
proc ::GX::CurveWorkbench::_seriesCommit {w token container sources name parameters} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen series parameters"}
    if {[string trim $name] eq {}} {error "Enter a series name"}
    if {$container eq {}&&[dict size $st($w,seriesContainers)]>=256} {error "Series container limit is 256"}
    _cancelGesture $w;_pointSyncApply $w;_coordinatePlaneAdmit $w $sources
    set frame {1 0 0 1 0 0};set old {}
    if {$container ne {}} {set frame [dict get $st($w,seriesContainers) $container frame];set old [dict get $st($w,seriesContainers) $container members]}
    set nativeIds {};set map {}
    foreach source $sources {
        set record [_record $w $source]
        if {[_bulkRecord $record]} {error "Convert an explicit complete range to Native before series creation"}
        set native [dict get $record native];lappend nativeIds $native;dict set map $native $source
    }
    set before [_snapshotIds $w $old];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    set raw [::GX::native2DSeriesBuild $st($w,scene) $nativeIds $parameters $frame]
    set results {};set cells {};set ordinal 0
    try {
        foreach native [dict get $raw object_ids] sourceNative [dict get $raw source_ids] index [dict get $raw logical_indices] {
            set parent [dict get $map $sourceNative];set source [_record $w $parent]
            set record [_newRecord $w "$name \[[join $index ,]\] — [dict get $source name]" [dict get $source samples] [dict get $source source] [dict get $source x] [dict get $source y] [dict get $source filter] [dict get $source filter_value] [dict get $source family] [dict get $source order] [list $parent] [list [dict create operation parametric_rectangular_series parameters [dict get $raw parameters] frame $frame logical_index $index originals_preserved 1]] [dict get $source representation]]
            foreach key {working_unit attributes source_descriptor materialization_sampling} {if {[dict exists $source $key]} {dict set record $key [dict get $source $key]}}
            dict set record breaks [dict get $source breaks]
            set id [dict get $record id];dict set before $id {};lappend results $id;dict lappend cells [join $index ,] $id
            _addRecord $w $record $native;_syncSamples $w $id
        }
        foreach id $old {_removeRecord $w $id}
        if {$container eq {}} {set container "series[incr st($w,nextSeries)]"}
        dict set st($w,seriesContainers) $container [dict create name $name sources $sources members $results cells $cells parameters [dict get $raw parameters] frame $frame origin_policy [dict get $raw origin_policy]]
        if {$results ne {}} {set st($w,active) [lindex $results 0]}
        set st($w,objectSelection) $results;set st($w,cadTarget) selected;_selectionScene $w
        _history $w $before [concat $old $results]
    } on error {message options} {
        _restoreSnapshot $w $before
        set live [::GX::Native2D::core ids $st($w,scene)]
        foreach native [dict get $raw object_ids] {if {$native in $live} {::GX::Native2D::core delete $st($w,scene) $native}}
        set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;_curveList $w;_pointList $w;_draw $w
        return -options $options $message
    }
    set st($w,status) "Parametric series $container committed: [llength $results] generated members, independent originals; one Undo action."
    return $results
}
proc ::GX::CurveWorkbench::_seriesManagerRefresh {w} {
    variable st
    if {![winfo exists $w.seriesManager.tree]} return
    set tree $w.seriesManager.tree;set selected [$tree selection];$tree delete [$tree children {}]
    dict for {id record} $st($w,seriesContainers) {
        set p [dict get $record parameters];set status current
        foreach member [concat [dict get $record sources] [dict get $record members]] {if {![dict exists $st($w,curves) $member]} {set status {missing references}}}
        $tree insert {} end -id $id -values [list $id [dict get $record name] "[dict get $p columns] × [dict get $p rows]" [dict get $p step_u] [dict get $p step_v] [llength [dict get $record members]] $status]
    }
    _inspectionColumnsFit $tree;foreach id $selected {if {[$tree exists $id]} {$tree selection add $id}}
}
proc ::GX::CurveWorkbench::_seriesManagerOpen {w} {
    set d $w.seriesManager
    if {[winfo exists $d]} {raise $d;_seriesManagerRefresh $w;return}
    toplevel $d;wm title $d "Parametric rectangular series";wm transient $d $w;wm geometry $d 1000x460
    ttk::label $d.help -text {Series are parametric containers, distinct from groups. Edit counts/basis regenerates complete members from the independent current sources in the stored series frame. Origin is omitted unless explicitly copied. Preview uses a temporary Native scene. Explode keeps existing geometry as independent objects.} -wraplength 940 -padding 8
    bind $d.help <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $d.help %w];pack $d.help -side top -fill x
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 8
    foreach {key label callback} [list edit {Edit / Preview…} [list _seriesEditOpen $w] transform {Transform as unit…} [list _seriesTransformOpen $w] explode {Explode series} [list _seriesContainerRemove $w 1] remove {Delete series geometry} [list _seriesContainerRemove $w 0]] {
        set callback [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]];ttk::button $d.actions.$key -text $label -command [list ::GX::CurveWorkbench::_safe $w $callback];pack $d.actions.$key -side left -padx 4
    }
    ttk::button $d.actions.close -text Close -command [list destroy $d];pack $d.actions.close -side right;bind $d.actions <Configure> [list ::GX::native2DToolbarLayout $d.actions %w]
    ttk::frame $d.table;pack $d.table -fill both -expand 1
    ttk::treeview $d.tree -columns {id name shape step_u step_v members status} -show headings -selectmode browse
    foreach key {id name shape step_u step_v members status} {$d.tree heading $key -text [string totitle $key];$d.tree column $key -width 145 -minwidth 70}
    ttk::scrollbar $d.y -orient vertical -command [list $d.tree yview];ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview];$d.tree configure -yscrollcommand [list $d.y set] -xscrollcommand [list $d.x set]
    pack $d.x -in $d.table -side bottom -fill x;pack $d.y -in $d.table -side right -fill y;pack $d.tree -in $d.table -fill both -expand 1
    bind $d.tree <Configure> [list ::GX::CurveWorkbench::_inspectionColumnsSchedule $d.tree];bind $d <Escape> [list destroy $d];_seriesManagerRefresh $w
}
proc ::GX::CurveWorkbench::_seriesContainerSelected {w} {set selection [$w.seriesManager.tree selection];if {[llength $selection]!=1} {error "Select one series container"};return [lindex $selection 0]}
proc ::GX::CurveWorkbench::_seriesEditOpen {w} {
    variable st
    set id [_seriesContainerSelected $w];set record [dict get $st($w,seriesContainers) $id];set p [dict get $record parameters];lassign [dict get $p step_u] ux uy;lassign [dict get $p step_v] vx vy
    set fields {name {type string label {Series name}} rows {type integer min 1 max 10000 label {Count V / rows}} columns {type integer min 1 max 10000 label {Count U / columns}} ux {type number label {Step U: X}} uy {type number label {Step U: Y}} vx {type number label {Step V: X}} vy {type number label {Step V: Y}} include_origin {type boolean label {Generate a copy at index [0,0]}} preview {type boolean label {Preview only (temporary scene; no history change)}}}
    set sources [dict get $record sources];_coordinatePlaneAdmit $w $sources
    lassign [_coordinateUnits [_record $w [lindex $sources 0]]] xUnit yUnit
    foreach field {ux vx} {dict set fields $field label "[dict get $fields $field label]: native X ($xUnit)"}
    foreach field {uy vy} {dict set fields $field label "[dict get $fields $field label]: native Y ($yUnit)"}
    set st($w,seriesEditKey) [list $id $record [_coordinateControlKey $w $sources]]
    set values [dict create name [dict get $record name] rows [dict get $p rows] columns [dict get $p columns] ux $ux uy $uy vx $vx vy $vy include_origin [dict get $p include_origin] preview 0]
    ::GX::uiFieldFormCreate $w.seriesEdit "Edit parametric series $id" $fields $values [list ::GX::CurveWorkbench::_seriesEditApply $w $st($w,token) $id] $w.seriesManager
}
proc ::GX::CurveWorkbench::_seriesEditApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen series parameters"}
    set p [dict create rows [dict get $values rows] columns [dict get $values columns] step_u [list [dict get $values ux] [dict get $values uy]] step_v [list [dict get $values vx] [dict get $values vy]] include_origin [dict get $values include_origin]]
    set record [dict get $st($w,seriesContainers) $id]
    set sources [dict get $record sources];_coordinatePlaneAdmit $w $sources
    if {![info exists st($w,seriesEditKey)]||$st($w,seriesEditKey) ne [list $id $record [_coordinateControlKey $w $sources]]} {error {Series or coordinate frame changed; reopen series parameters}}
    if {![dict get $values preview]} {return [_seriesCommit $w $token $id [dict get $record sources] [dict get $values name] $p]}
    set preview [::GX::Native2D::core scene]
    try {
        set input {}
        foreach source [dict get $record sources] {set resource [::GX::interactiveDocumentNative2DStore $st($w,document) $st($w,scene) [dict get [_record $w $source] native]];lappend input [::GX::interactiveDocumentNative2DRestore $resource $preview]}
        set receipt [::GX::native2DSeriesBuild $preview $input $p [dict get $record frame]]
        foreach source $input {::GX::Native2D::core delete $preview $source}
        set d $w.seriesPreview;if {[winfo exists $d]} {destroy $d};toplevel $d;wm title $d "Series preview — no geometry committed"
        canvas $d.canvas -width 700 -height 500 -background white;pack $d.canvas -fill both -expand 1
        ::GX::Native2D::core view $preview {700 500 20 20 20 20 {0 0 1 1}};::GX::Native2D::core fit $preview
        foreach member [dict get $receipt object_ids] {foreach path [::GX::Native2D::core render_paths $preview $member] {if {[llength $path]>=2} {$d.canvas create line [concat {*}$path] -fill #245ba0 -width 2}}}
        ttk::button $d.close -text Close -command [list destroy $d];pack $d.close -side bottom
        bind $d <Escape> [list destroy $d]
    } finally {::GX::Native2D::core destroy $preview}
    set st($w,status) "Preview: [llength [dict get $receipt object_ids]] generated members; close preview and clear Preview only to commit."
}
proc ::GX::CurveWorkbench::_seriesTransformOpen {w} {
    variable st
    set id [_seriesContainerSelected $w]
    set record [dict get $st($w,seriesContainers) $id];set ids [concat [dict get $record sources] [dict get $record members]]
    _coordinatePlaneAdmit $w $ids
    lassign [_coordinateUnits [_record $w [lindex $ids 0]]] xUnit yUnit
    set fields [dict create dx [dict create type number label "Translate native X ($xUnit)"] dy [dict create type number label "Translate native Y ($yUnit)"] angle {type number label {Numeric plane rotation about origin (degrees)}}]
    set st($w,seriesTransformKey) [list $id $record [_coordinateControlKey $w $ids]]
    ::GX::uiFieldFormCreate $w.seriesTransform "Transform whole series $id" $fields {dx 0 dy 0 angle 0} [list ::GX::CurveWorkbench::_seriesTransformApply $w $st($w,token) $id] $w.seriesManager
}
proc ::GX::CurveWorkbench::_seriesTransformApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen series transform"}
    _cancelGesture $w;_pointSyncApply $w
    set record [dict get $st($w,seriesContainers) $id];set ids [dict get $record members];set before [_snapshotIds $w $ids];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    set all [concat [dict get $record sources] $ids];_coordinatePlaneAdmit $w $all
    if {![info exists st($w,seriesTransformKey)]||$st($w,seriesTransformKey) ne [list $id $record [_coordinateControlKey $w $all]]} {error {Series or coordinate frame changed; reopen series transform}}
    set matrix [::GX::Native2D::core rotation_matrix_degrees $st($w,scene) {0 0} [dict get $values angle]]
    lset matrix 4 [dict get $values dx];lset matrix 5 [dict get $values dy]
    set frame [::GX::native2DSeriesCompose $matrix [dict get $record frame]];set natives [lmap member $ids {dict get [_record $w $member] native}]
    if {$natives eq {}} {error "Empty series has no geometry to transform"}
    try {::GX::Native2D::core affine $st($w,scene) $natives $matrix 0;foreach member $ids {_syncSamples $w $member};dict set st($w,seriesContainers) $id frame $frame;_history $w $before $ids} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
}
proc ::GX::CurveWorkbench::_seriesContainerRemove {w explode} {
    variable st
    _cancelGesture $w;_pointSyncApply $w
    set id [_seriesContainerSelected $w];set members [dict get $st($w,seriesContainers) $id members];set ids [expr {$explode ? {} : $members}];set before [_snapshotIds $w $ids];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {if {!$explode} {foreach member $members {_removeRecord $w $member}};dict unset st($w,seriesContainers) $id;_history $w $before $ids} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
}
rename ::GX::CurveWorkbench::_changed ::GX::CurveWorkbench::_changed_series_base
proc ::GX::CurveWorkbench::_changed {w} {_changed_series_base $w;_seriesManagerRefresh $w}
proc ::GX::CurveWorkbench::_buildSeries {w} {
    variable st
    $w.cad.sketch.menu add command -label "Parametric series…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_seriesManagerOpen $w]]}
