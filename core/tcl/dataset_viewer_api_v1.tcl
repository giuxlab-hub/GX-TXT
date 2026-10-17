# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only consultation of canonical identities; no publication/write callback.
namespace eval ::GX::DatasetViewer {variable serial 0;variable state;variable previewImage {};variable previewJob {}}
proc ::GX::datasetViewerDescribe {datasetId} {
    set payload [sessionInspectionDatasetPayload $datasetId]
    set contract [datasetField $datasetId contract [datasetField $datasetId kind {}]]
    set format [string tolower [dict get $payload format]]
    set media [datasetField $datasetId media_type {}]
    set kind unsupported
    if {$contract eq "geometry.sketch"} {set kind sketch
    } elseif {$format eq "pdf"||$contract eq "document.pdf"} {set kind pdf
    } elseif {$format in {stl obj step stp vtp vtu vti}||$contract in {geometry.mesh model.cad field.scalar_3d field.scalar_grid}} {set kind mesh
    } elseif {$contract in {molecular.structure structure.crystal}} {set kind structure
    } elseif {[string match image/* $media]||$contract eq "image.raster"} {set kind image
    } elseif {($contract eq "audio.waveform"&&$format in {csv hdf5 h5})} {set kind scientific
    } elseif {[string match audio/* $media]||$contract in {audio.source audio.waveform}} {set kind audio
    } elseif {$contract in {document.text code.source}||[string match text/* $media]&&$format ni {csv tsv}} {set kind text
    } elseif {$contract in {table.generic timeseries.table curve_family.table curve3d.table}||[string match spectrum.* $contract]||$format in {csv hdf5 h5}} {set kind scientific}
    return [dict create api_id DATASET_VIEWER_API_v1 dataset_id $datasetId contract $contract format $format media_type $media target $kind read_only [expr {$kind ne "sketch"}] implicit_publication 0 revision [dict get $payload sha256]]
}
proc ::GX::datasetViewerOpen {datasetId} {
    set info [datasetViewerDescribe $datasetId]
    switch [dict get $info target] {
        scientific {return [scientificDatasetViewerOpen $datasetId]}
        mesh - structure {return [meshDatasetViewerOpen $datasetId]}
        pdf - image - audio {return [datasetMediaViewerOpen $datasetId [dict get $info target]]}
        sketch {return [viewerOpen viewer.curve_workbench curve_workbench [dict create sketch_dataset_id $datasetId]]}
        default {return [datasetConsultationOpen $datasetId $info]}
    }
}
proc ::GX::datasetPreviewOpenCurrent {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"||$id eq {}} {error {Activate an imported canonical Dataset. Pending sources support Preview only.}}
    return [datasetViewerOpen $id]
}
proc ::GX::datasetPreviewUpdateOpenButton {} {
    set w .top.nb.channels.browser.tools.open
    if {![winfo exists $w]} return
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    $w state [expr {$mode eq "imported"&&$id ne {}?"!disabled":"disabled"}]
}
proc ::GX::scientificDatasetAxes {id} {
    set numeric {};set axes {};set values {}
    foreach v [datasetVariableSchemaV3 $id] {
        if {![dict get $v enabled]||[dict get $v value_kind] eq "text"||[dict get $v rank]!=1} continue
        set vid [dict get $v variable_id];lappend numeric $vid
        if {[dict get $v coordinate_role] eq "coordinate"||[dict get $v value_kind] eq "elapsed_time"||[dict get $v semantic_role] in {time elapsed_time frequency energy wavelength wavenumber chemical_shift}} {lappend axes $vid} else {lappend values $vid}
    }
    set x {};set y {}
    if {[llength $axes]==1} {set x [lindex $axes 0];if {[llength $values]==1} {set y [lindex $values 0]}}
    if {![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {
        set x [dict get $manifest columns x];set y [dict get $manifest columns y]
    }
    return [dict create numeric $numeric x $x y $y]
}
proc ::GX::scientificDatasetDisplayScene {display} {
    native2DEnsure
    set scene [::GX::Native2D::core scene]
    try {
        set points [dict get $display points]
        if {![llength $points]} {error {No finite X/Y pairs in the selected source.}}
        set object [::GX::Native2D::core [expr {[llength $points]==1?"point":"add"}] $scene $points]
        if {[dict exists $display breaks]} {::GX::Native2D::core set_breaks $scene $object [dict get $display breaks]}
        ::GX::Native2D::core object_style $scene $object {color {0.04 0.35 0.65 1} line_width 2 marker 0}
        ::GX::Native2D::core background $scene {1 1 1 1}
        ::GX::Native2D::core grid $scene {visible 1 enabled 1}
        # Independent scientific dimensions must not inherit calibrated geometry.
        ::GX::Native2D::core aspect $scene auto
        if {[dict exists $display full_bounds]} {scientificDatasetFitBounds $scene [list $display]} else {::GX::Native2D::core fit $scene}
        _scientificDatasetGrid $scene
        return $scene
    } on error {message options} {::GX::Native2D::core destroy $scene;return -options $options $message}
}
proc ::GX::_scientificDatasetGrid {scene} {
    set plans [native2DAxisPlans $scene]
    ::GX::Native2D::core grid $scene [dict create origin {0 0} spacing_x [dict get $plans x step] spacing_y [dict get $plans y step] major_interval 1]
}
proc ::GX::scientificDatasetPreview {datasetId xId yId output {member {}}} {
    set filters {}
    if {$member ne {}} {
        foreach v [datasetVariableSchemaV3 $datasetId] {
            if {[dict get $v semantic_role] eq "member_identity" || [dict get $v variable_id] eq "member_id"} {
                set filters [list [dict create filter_variable_id [dict get $v variable_id] predicate in_set values [list $member]]];break
            }
        }
    }
    return [dict merge [scientificDatasetPreviewFiltered $datasetId $xId $yId $output [list $filters]] [dict create dataset_id $datasetId x_variable_id $xId y_variable_id $yId]]
}

proc ::GX::datasetViewerStamp {id path} {
    file stat $path stat
    return [list [sessionInspectionDataset $id] [datasetVariableSchemaV3 $id] $stat(size) $stat(mtime) $stat(ctime) $stat(ino)]
}
proc ::GX::datasetViewerCheck {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,identity)]} {error {Viewer is closed.}}
    if {$state($w,session) ne [interactiveDocumentSessionToken]} {error {Session changed; reopen this Dataset.}}
    if {[info exists state($w,sourceCheck)]} {
        if {[uplevel #0 $state($w,sourceCheck)] ne $state($w,sourceKey)} {error {Native3D preview source/configuration changed; activate again.}}
    }
    set current [datasetViewerStamp $state($w,id) $state($w,path)]
    if {$current ne $state($w,stamp)} {
        # Scientific display policy may change without touching the source or
        # schema. Keep every other revision check, including filesystem identity.
        if {![info exists state($w,coordinateContext)]||[scientificDatasetCoordinateSourceStamp $current] ne [scientificDatasetCoordinateSourceStamp $state($w,stamp)]} {error {Dataset revision changed; reopen it explicitly.}}
        set state($w,stamp) $current
    }
}
proc ::GX::datasetViewerWatch {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[info exists state($w,previewChoice)]&&$state($w,previewChoice) ne $::GX::variableDatasetChoice} {datasetViewerClose $w;return}
    if {[catch {datasetViewerCheck $w;scientificDatasetViewerCoordinateRefresh $w} reason]} {datasetViewerClose $w;setStatus $reason 100;return}
    set state($w,watch) [after 1000 [list ::GX::datasetViewerWatch $w]]
}
proc ::GX::datasetViewerClose {w} {
    variable ::GX::DatasetViewer::state
    foreach timer {watch drawJob memberScan externalWatch prepareAfter} {if {[info exists state($w,$timer)]} {after cancel $state($w,$timer)}}
    if {[info exists state($w,job)]&&$state($w,job) ne {}} {catch {curveSourceCancel $state($w,job)}}
    if {[info exists state($w,source)]&&$state($w,source) ne {}} {curveSourceClose $state($w,source)}
    if {[info exists state($w,scene)]&&$state($w,scene) ne {}} {::GX::Native2D::core destroy $state($w,scene)}
    if {[info exists state($w,preparePipe)]} {
        fileevent $state($w,preparePipe) readable {};foreach pid [pid $state($w,preparePipe)] {
            if {[info exists state($w,prepareGroup)]} {catch {exec kill -TERM -- -$pid}} else {catch {exec kill -TERM -- $pid}}
        };catch {close $state($w,preparePipe)}
    }
    if {[info exists state($w,xyzStream)]} {catch {tableStreamClose $state($w,xyzStream)}}
    if {[info exists state($w,compactCanvas)]} {native3DPreviewClosed $w}
    if {[info exists state($w,worker)]} {catch {puts $state($w,worker) close;flush $state($w,worker)};foreach pid [pid $state($w,worker)] {catch {exec kill -TERM -- $pid}};catch {close $state($w,worker)}}
    if {[info exists state($w,externalPipe)]} {fileevent $state($w,externalPipe) readable {};catch {close $state($w,externalPipe)}}
    if {[info exists state($w,externalPids)]} {foreach pid $state($w,externalPids) {catch {exec kill -TERM -- $pid}}}
    if {[info exists state($w,decoder)]} {foreach pid [pid $state($w,decoder)] {catch {exec kill -TERM -- $pid}};catch {close $state($w,decoder)}}
    if {[info exists state($w,image)]&&$state($w,image) ne {}} {catch {image delete $state($w,image)}}
    if {[info exists state($w,temp)]} {file delete -force -- $state($w,temp)}
    if {[info exists state($w,memberStream)]} {catch {tableStreamClose $state($w,memberStream)}}
    if {[info exists state($w,previewWidget)] && $::GX::DatasetViewer::previewJob eq $w} {
        set ::GX::DatasetViewer::previewJob {}
        if {[winfo exists .top.nb.preview.geometry]} {place forget .top.nb.preview.geometry}
    }
    # Tk listvariables reinstall their values during widget destruction.
    # Destroy widgets first, then remove every per-window value.
    catch {destroy $w}
    array unset state $w,*
}
proc ::GX::datasetViewerWindow {id title} {
    variable ::GX::DatasetViewer::state;variable ::GX::DatasetViewer::serial
    set w .datasetViewer[incr serial]
    set state($w,id) $id;set state($w,identity) [datasetViewerDescribe $id];set state($w,session) [interactiveDocumentSessionToken]
    set state($w,path) [dict get [sessionInspectionDatasetPayload $id] path]
    set state($w,stamp) [datasetViewerStamp $id $state($w,path)]
    toplevel $w;wm title $w "$title — $id (read-only)";wm geometry $w 1100x760
    wm protocol $w WM_DELETE_WINDOW [list ::GX::datasetViewerClose $w]
    set state($w,status) "$id — canonical values, no publication"
    ttk::label $w.status -textvariable ::GX::DatasetViewer::state($w,status) -wraplength 1000
    pack $w.status -side bottom -fill x -padx 8 -pady 5
    datasetViewerWatch $w
    return $w
}
proc ::GX::scientificDatasetViewerOpen {id} {
    variable ::GX::DatasetViewer::state
    set w [datasetViewerWindow $id {CORE Scientific Dataset Viewer}]
    set state($w,scene) {};set state($w,source) {};set state($w,job) {};set state($w,start) 0;set state($w,epoch) 0
    ttk::notebook $w.views;pack $w.views -fill both -expand 1
    ttk::frame $w.views.plot;$w.views add $w.views.plot -text Plot
    set p $w.views.plot
    ttk::frame $p.bar;pack $p.bar -fill x
    set axes [scientificDatasetAxes $id]
    foreach key {x y} {
        set state($w,$key) [dict get $axes $key]
        ttk::label $p.bar.${key}Label -text [string toupper $key]
        ttk::combobox $p.bar.$key -values [dict get $axes numeric] -textvariable ::GX::DatasetViewer::state($w,$key) -state readonly -width 22
        pack $p.bar.${key}Label $p.bar.$key -side left -padx 5 -pady 6
    }
    foreach {name title action} {plot Plot scientificDatasetViewerPlot fit Fit scientificDatasetViewerFit cancel Cancel scientificDatasetViewerCancel} {
        ttk::button $p.bar.$name -text $title -command [list ::GX::$action $w];pack $p.bar.$name -side left -padx 5
    }
    scientificDatasetSeriesBuild $w [dict get $axes numeric]
    set state($w,aspect) auto
    ttk::checkbutton $p.bar.aspect -text {Calibrated equal aspect} -variable ::GX::DatasetViewer::state($w,aspect) -onvalue xy_equal -offvalue auto -command [list ::GX::scientificDatasetViewerAspect $w]
    pack $p.bar.aspect -side left -padx 5
    set state($w,legend) {Select explicit X and Y variables, then Plot.}
    ttk::label $p.legend -textvariable ::GX::DatasetViewer::state($w,legend);pack $p.legend -fill x -padx 8
    canvas $p.canvas -background white -highlightthickness 0;pack $p.canvas -fill both -expand 1
    bind $p.canvas <Configure> [list ::GX::scientificDatasetViewerDrawLater $w]
    bind $p.canvas <ButtonPress-1> [list ::GX::scientificDatasetViewerPan $w start %x %y]
    bind $p.canvas <B1-Motion> [list ::GX::scientificDatasetViewerPan $w move %x %y]
    bind $p.canvas <Button-4> [list ::GX::scientificDatasetViewerZoom $w 1.25 %x %y]
    bind $p.canvas <Button-5> [list ::GX::scientificDatasetViewerZoom $w 0.8 %x %y]
    bind $p.canvas <Motion> [list ::GX::scientificDatasetViewerPoint $w %x %y]
    set tableVariables {};foreach v [datasetVariableSchemaV3 $id] {if {[dict get $v rank]==1} {lappend tableVariables [dict get $v variable_id]}}
    if {[llength $tableVariables]} {
        datasetPreviewCreateTable $w.views.table $::GX::currentSession $id
        $w.views add $w.views.table -text {Canonical table}
    }
    set arrays {}
    foreach v [datasetVariableSchemaV3 $id] {if {[dict get $v enabled]&&[dict get $v rank]>=2} {lappend arrays [dict get $v variable_id]}}
    if {[llength $arrays]} {scientificDatasetMatrixBuild $w $arrays}
    ttk::frame $w.views.infoPage
    text $w.views.info -wrap word -state normal -yscrollcommand [list $w.views.infoPage.scroll set]
    ttk::scrollbar $w.views.infoPage.scroll -command [list $w.views.info yview]
    pack $w.views.infoPage.scroll -side right -fill y
    pack $w.views.info -in $w.views.infoPage -fill both -expand 1
    $w.views add $w.views.infoPage -text {Schema and provenance}
    $w.views.info insert end "[sessionInspectionDataset $id]\n\n"
    foreach v [datasetVariableSchemaV3 $id] {$w.views.info insert end "$v\n\n"}
    $w.views.info insert end [datasetMetadataRead $::GX::currentSession $id];$w.views.info configure -state disabled
    if {$state($w,x) ne {}&&$state($w,y) ne {}&&$state($w,memberVariable) eq {}} {after idle [list ::GX::scientificDatasetViewerPlot $w]}
    return $w
}
proc ::GX::scientificDatasetViewerCancel {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    incr state($w,epoch)
    set state($w,queue) {}
    if {$state($w,job) ne {}} {curveSourceCancel $state($w,job);set state($w,job) {}}
}
proc ::GX::scientificDatasetViewerPlot {w} {
    variable ::GX::DatasetViewer::state
    if {[catch {
        datasetViewerCheck $w;scientificDatasetViewerCancel $w
        if {$state($w,source) ne {}} {curveSourceClose $state($w,source);set state($w,source) {}}
        if {$state($w,x) eq {}||$state($w,y) eq {}} {error {Choose explicit X and Y variables.}}
        set state($w,source) [curveSourceOpen $::GX::currentSession [dict create dataset_id $state($w,id) x_variable_id $state($w,x) y_variable_id $state($w,y) display_budget 4096]]
        set state($w,job) [curveSourceDisplayAsync $state($w,source) [list ::GX::scientificDatasetViewerReady $w] [list ::GX::scientificDatasetViewerProgress $w]]
    } message]} {set state($w,status) $message}
}
proc ::GX::scientificDatasetViewerProgress {w receipt} {
    variable ::GX::DatasetViewer::state
    if {[info exists state($w,id)]} {set state($w,status) "Loading canonical rows: [dict get $receipt completed_rows] / [dict get $receipt total_rows]"}
}
proc ::GX::scientificDatasetViewerReady {w receipt} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set state($w,job) {}
    if {[dict get $receipt status] ne "ok"} {set state($w,status) [datasetPublicationV2DictDefault $receipt message {Loading cancelled}];return}
    if {[catch {
        datasetViewerCheck $w
        set display [dict get $receipt display]
        set scene [scientificDatasetDisplayScene $display]
        if {$state($w,scene) ne {}} {::GX::Native2D::core destroy $state($w,scene)}
        set state($w,scene) $scene;set state($w,display) $display
        set labels {}
        foreach key {x y} {
            set v [datasetVariableV3ById $state($w,id) $state($w,$key)]
            lappend labels "[dict get $v canonical] ([dict get $v unit]) — $state($w,$key)"
        }
        set state($w,legend) "X: [lindex $labels 0]     Y: [lindex $labels 1]"
        set state($w,status) "[dict get $display row_count] canonical rows; [llength [dict get $display points]] displayed points. Gaps retained; display reduction: [dict get $display reduced]. Drag to Pan; wheel zooms."
        scientificDatasetViewerDraw $w
    } message]} {set state($w,status) $message}
}
proc ::GX::scientificDatasetViewerDrawLater {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[info exists state($w,drawJob)]} {after cancel $state($w,drawJob)}
    set state($w,drawJob) [after idle [list ::GX::scientificDatasetViewerDraw $w]]
}
proc ::GX::scientificDatasetViewerDraw {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,scene)]||$state($w,scene) eq {}} return
    set s $state($w,scene);set c $w.views.plot.canvas
    set width [winfo width $c];set height [winfo height $c]
    if {$width<120||$height<100} return
    set view [::GX::Native2D::core view_requested $s];lset view 0 $width;lset view 1 $height;lset view 2 85;lset view 3 20;lset view 4 25;lset view 5 50
    ::GX::Native2D::core view $s $view
    lset view 2 [expr {min($width/3.0,max(85,[native2DAxisLabelMargin $s]))}]
    ::GX::Native2D::core view $s $view
    _scientificDatasetGrid $s
    native2DCanvasSnapshot $c [native2DPresentationSnapshot $s]
}
proc ::GX::scientificDatasetViewerFit {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[catch {set selection [scientificDatasetViewerSelection $w]} reason]} {set state($w,status) $reason;return}
    if {![info exists state($w,plottedRequest)] || $state($w,plottedRequest) ne $selection} {scientificDatasetViewerPlot $w;return}
    if {$state($w,job) ne {}} return
    if {$state($w,scene) ne {}} {
        scientificDatasetFitBounds $state($w,scene) [lmap series $state($w,series) {dict get $series display}]
        if {[llength $state($w,series)]} {
            set presentation [scientificDatasetCoordinateView $state($w,scene) [dict get [lindex $state($w,series) 0] display coordinate_presentation]]
            set state($w,status) [scientificDatasetCoordinateNotice $presentation]
        }
        scientificDatasetViewerDraw $w
    }
}
proc ::GX::scientificDatasetViewerAspect {w} {
    variable ::GX::DatasetViewer::state
    if {$state($w,scene) ne {}} {::GX::Native2D::core aspect $state($w,scene) $state($w,aspect);scientificDatasetViewerDraw $w}
}
proc ::GX::scientificDatasetViewerPan {w phase x y} {
    variable ::GX::DatasetViewer::state
    if {$phase eq "move"&&[info exists state($w,drag)]&&$state($w,scene) ne {}} {lassign $state($w,drag) px py;::GX::Native2D::core pan $state($w,scene) [expr {$x-$px}] [expr {$y-$py}];scientificDatasetViewerDraw $w}
    set state($w,drag) [list $x $y]
}
proc ::GX::scientificDatasetViewerZoom {w factor x y} {variable ::GX::DatasetViewer::state;if {$state($w,scene) ne {}} {::GX::Native2D::core zoom $state($w,scene) $factor [list $x $y];scientificDatasetViewerDraw $w}}
proc ::GX::scientificDatasetViewerPoint {w x y} {
    variable ::GX::DatasetViewer::state
    if {$state($w,scene) eq {}} return
    set s $state($w,scene);set nearest -1;set distance 100
    set i 0
    foreach p [dict get $state($w,display) points] {
        lassign [::GX::Native2D::core device $s $p] px py
        set d [expr {hypot($px-$x,$py-$y)}]
        if {$d<$distance} {set distance $d;set nearest $i}
        incr i
    }
    if {$nearest>=0&&$distance<12} {set state($w,status) "Canonical source row (1-based): [expr {1+[lindex [dict get $state($w,display) source_rows] $nearest]}]    X/Y: [lindex [dict get $state($w,display) points] $nearest]"}
}
proc ::GX::scientificDatasetMatrixBuild {w arrays} {
    variable ::GX::DatasetViewer::state
    set p $w.views.matrix;ttk::frame $p;$w.views add $p -text {Array plane}
    ttk::frame $p.bar;pack $p.bar -fill x
    set state($w,array) [lindex $arrays 0];set state($w,starts) {};set state($w,counts) {}
    ttk::combobox $p.bar.variable -values $arrays -state readonly -textvariable ::GX::DatasetViewer::state($w,array)
    ttk::label $p.bar.label -text {Starts / counts (storage order):}
    ttk::entry $p.bar.starts -textvariable ::GX::DatasetViewer::state($w,starts) -width 20
    ttk::entry $p.bar.counts -textvariable ::GX::DatasetViewer::state($w,counts) -width 20
    ttk::button $p.bar.show -text {Read plane} -command [list ::GX::scientificDatasetMatrixRead $w]
    pack $p.bar.variable $p.bar.label $p.bar.starts $p.bar.counts $p.bar.show -side left -padx 4 -pady 6
    canvas $p.canvas -background white;pack $p.canvas -fill both -expand 1
    bind $p.bar.variable <<ComboboxSelected>> [list ::GX::scientificDatasetMatrixDefaults $w]
    scientificDatasetMatrixDefaults $w
}
proc ::GX::scientificDatasetMatrixDefaults {w} {
    variable ::GX::DatasetViewer::state
    set v [datasetVariableV3ById $state($w,id) $state($w,array)]
    set shape [split [dict get $v shape] {;}];set starts {};set counts {}
    for {set i 0} {$i<[llength $shape]} {incr i} {lappend starts 0;lappend counts [expr {$i<[llength $shape]-2?1:min(128,[lindex $shape $i])}]}
    set state($w,starts) $starts;set state($w,counts) $counts
    set state($w,status) "Shape: $shape; dimensions: [dict get $v dimension_ids]; coordinates: [dict get $v coordinate_variable_ids]. Select at most two non-singleton dimensions; up to 16384 original cells, no aggregation."
}
proc ::GX::scientificDatasetMatrixRead {w} {
    variable ::GX::DatasetViewer::state
    if {[catch {
        datasetViewerCheck $w
        set starts $state($w,starts);set counts $state($w,counts)
        set v [datasetVariableV3ById $state($w,id) $state($w,array)]
        set shape [split [dict get $v shape] {;}]
        if {[llength $starts]!=[llength $shape]||[llength $counts]!=[llength $shape]} {error {Starts and counts must match rank.}}
        set elements 1;set axes {};set i 0
        foreach start $starts count $counts limit $shape {
            if {![string is integer -strict $start]||![string is integer -strict $count]||$start<0||$count<1||$start+$count>$limit} {error {Plane range is outside its dimension.}}
            set elements [expr {$elements*$count}];if {$count>1} {lappend axes $i};incr i
        }
        if {$elements>16384||[llength $axes]!=2} {error {Choose a plane with two non-singleton dimensions and at most 16384 cells.}}
        set handle [datasetAccessOpen $::GX::currentSession $state($w,id)]
        try {set slab [datasetAccessReadHyperslab $handle $state($w,array) $starts $counts]} finally {datasetAccessClose $handle}
        set values [dict get $slab values];set lo Inf;set hi -Inf
        foreach value $values {if {[string is double -strict $value]&&![catch {expr {abs($value)<Inf}} finite]&&$finite} {set lo [expr {min($lo,$value)}];set hi [expr {max($hi,$value)}]}}
        if {$lo eq "Inf"} {error {Plane has no finite values.}}
        lassign $axes ay ax;set ny [lindex $counts $ay];set nx [lindex $counts $ax]
        set c $w.views.matrix.canvas;$c delete all
        set dx [expr {max(1.0,([winfo width $c]-110.0)/$nx)}];set dy [expr {max(1.0,([winfo height $c]-70.0)/$ny)}]
        set n 0
        foreach value $values {
            set color #b8b8b8
            if {[string is double -strict $value]&&![catch {expr {abs($value)<Inf}} finite]&&$finite} {
                set t [expr {$hi==$lo?.5:($value-$lo)/($hi-$lo)}]
                set color [format #%02x%02x%02x [expr {int(255*$t)}] [expr {int(180*(1-abs(2*$t-1)))}] [expr {int(255*(1-$t))}]]
            }
            set x [expr {70+($n%$nx)*$dx}];set y [expr {20+($n/$nx)*$dy}]
            set item [$c create rectangle $x $y [expr {$x+$dx}] [expr {$y+$dy}] -fill $color -outline {}]
            set row [expr {[lindex $starts $ay]+$n/$nx}];set col [expr {[lindex $starts $ax]+$n%$nx}]
            $c bind $item <Enter> [list set ::GX::DatasetViewer::state($w,status) "Storage indices: $row, $col; canonical value: $value [dict get $v unit]"]
            incr n
        }
        set dimensions [datasetSchemaV3SplitIds [dict get $v dimension_ids]]
        set coordinateIds [datasetSchemaV3SplitIds [dict get $v coordinate_variable_ids]]
        foreach axis [list $ax $ay] orientation {x y} {
            set dimension [lindex $dimensions $axis];set label "$dimension (storage index)";set ticks {}
            foreach coordinate $coordinateIds {
                set cv [datasetVariableV3ById $state($w,id) $coordinate]
                if {[dict get $cv rank]==1&&[datasetSchemaV3SplitIds [dict get $cv dimension_ids]] eq [list $dimension]} {
                    set handle [datasetAccessOpen $::GX::currentSession $state($w,id)]
                    try {set ticks [dict get [datasetAccessReadHyperslab $handle $coordinate [list [lindex $starts $axis]] [list [lindex $counts $axis]]] values]} finally {datasetAccessClose $handle}
                    set label "[dict get $cv canonical] ([dict get $cv unit])";break
                }
            }
            for {set i 0} {$i<=4} {incr i} {
                set n [expr {int(([lindex $counts $axis]-1)*$i/4.0)}]
                set value [expr {$ticks eq {}?[lindex $starts $axis]+$n:[lindex $ticks $n]}]
                if {[string is double -strict $value]} {set value [format %.6g $value]}
                if {$orientation eq "x"} {$c create text [expr {70+($n+.5)*$dx}] [expr {[winfo height $c]-40}] -text $value} else {$c create text 65 [expr {20+($n+.5)*$dy}] -text $value -anchor e}
            }
            if {$orientation eq "x"} {$c create text 70 [expr {[winfo height $c]-15}] -anchor w -text $label} else {$c create text 8 8 -anchor nw -text $label}
        }
        set state($w,status) "Exact plane: $starts / $counts. Range $lo to $hi [dict get $v unit]; gray = nonfinite. No interpolation or publication."
    } message]} {set state($w,status) $message}
}
proc ::GX::datasetConsultationOpen {id info} {
    variable ::GX::DatasetViewer::state
    set w [datasetViewerWindow $id {CORE Dataset consultation}]
    set path [dict get [sessionInspectionDatasetPayload $id] path]
    text $w.content -wrap word -font TkFixedFont -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -command [list $w.content yview];pack $w.scroll -side right -fill y
    pack $w.content -fill both -expand 1
    set type [dict get $info target]
    if {$type in {image audio}} {
        set f [file tempfile temp];close $f;file delete $temp;file mkdir $temp;set state($w,temp) $temp
        if {[catch {set artifact [datasetPreviewMediaArtifact $path [dict get $info media_type] [dict get $info format] [dict get $info contract] $temp]} reason]} {$w.content insert end $reason
        } elseif {$artifact ne {}&&[dict exists $artifact path]&&[file isfile [dict get $artifact path]]} {
            set state($w,image) [image create photo -file [dict get $artifact path]]
            $w.content image create end -image $state($w,image)
        }
    } elseif {$type in {text structure}} {
        set f [open $path r];fconfigure $f -encoding utf-8
        try {set content [read $f 262144];set complete [eof $f]} finally {close $f}
        $w.content insert end $content
        if {!$complete} {$w.content insert end "\n\nBounded content inspection: first 256 KiB shown."}
    } else {$w.content insert end "No CORE semantic decoder is registered for this contract/format. The original Dataset is preserved.\n"}
    $w.content insert end "\n\n$info\n\n[datasetMetadataRead $::GX::currentSession $id]"
    $w.content configure -state disabled
    return $w
}
# Integrated Preview continues to use the existing media renderers and table
# descriptors; scientific PNGs use the same Curve Source + Native authority.
rename ::GX::datasetInspectionRenderPreview ::GX::datasetInspectionRenderPreview_before_core_viewers
proc ::GX::datasetInspectionRenderPreview {w choice} {
    datasetDigitizerPreviewClear
    datasetPreviewUpdateOpenButton
    set expected [datasetPreviewStamp]
    set epoch $::GX::ui(previewEpoch)
    variable ::GX::DatasetViewer::previewImage
    variable ::GX::DatasetViewer::previewJob
    if {$previewJob ne {}} {catch {datasetViewerClose $previewJob};set previewJob {}}
    if {[winfo exists .top.nb.preview.mapping]} {grid remove .top.nb.preview.mapping}
    if {$previewImage ne {}} {catch {image delete $previewImage};set previewImage {}}
    lassign [datasetInspectionParseChoice $choice] mode id
    if {$mode ne "imported"} {return [datasetInspectionRenderPreview_before_core_viewers $w $choice]}
    if {[catch {set info [datasetViewerDescribe $id]} reason]} {
        $w configure -state normal;$w delete 1.0 end;$w insert end "Canonical Dataset unavailable: $reason";$w configure -state disabled;return 0
    }
    if {[dict get $info target] in {mesh structure}} {
        $w configure -state normal;$w delete 1.0 end;$w insert end "Rendering canonical geometry through CORE Native3D…";$w configure -state disabled
        set previewJob [meshDatasetViewerOpen $id $w]
        return 1
    }
    if {[dict get $info target] ne "scientific"} {return [datasetInspectionRenderPreview_before_core_viewers $w $choice]}
    $w configure -state normal;$w delete 1.0 end
    $w insert end "Dataset: $id — [dict get $info contract]\nCanonical scientific data; display-only preview.\n\n"
    set axes [scientificDatasetPreviewControls $id [scientificDatasetAxes $id]]
    if {[catch {datasetDigitizerPreviewRender $w $id} reason]} {$w insert end "Source raster preview unavailable: $reason\n"}
    set f [file tempfile planePath];close $f
    try {set plane [scientificDatasetArrayPreview $id $planePath]
        if {$plane ne {}} {
            grid remove .top.nb.preview.mapping
            set previewImage [image create photo -file $planePath];$w image create end -image $previewImage;$w insert end "\n$plane\n";$w configure -state disabled;return 1
        }
    } on error {message options} {$w insert end "Array preview: $message\n"} finally {file delete -force $planePath}
    if {[dict get $axes x] eq {}||[dict get $axes y] eq {}} {
        $w insert end "X/Y mapping is ambiguous or multidimensional. Open Dataset to select explicit variables or a plane.\n"
        datasetPreviewRenderSchema $w $id
    } else {
        set f [file tempfile path];close $f
        try {
            set displayFilters $::GX::ui(previewMap,filters)
            if {[datasetDigitizerPreviewHasRecord $id]} {set displayFilters [dict remove $displayFilters @hidden_filters]}
            set requests [scientificDatasetFilterRequests $::GX::ui(previewMap,dimensions) $displayFilters $::GX::ui(previewMap,separate)]
            set receipt [scientificDatasetPreviewFiltered $id [dict get $axes x] [dict get $axes y] $path $requests]
            if {$choice ne $::GX::variableDatasetChoice || $epoch!=$::GX::ui(previewEpoch) || $expected ne [datasetPreviewStamp]} return
            set ::GX::ui(previewMap,status) "[scientificDatasetFilterMode $::GX::ui(previewMap,dimensions) $::GX::ui(previewMap,filters) $::GX::ui(previewMap,separate)] — [dict get $receipt trace_count] trace(s), [dict get $receipt row_count] source rows"
            foreach key {x y} {set vid [dict get $axes $key];set v [datasetVariableV3ById $id $vid];$w insert end "[string toupper $key]: [dict get $v canonical] ([scientificDatasetCoordinateLabel [dict get $receipt coordinate_presentation context] $vid])   "}
            $w insert end "\n"
            if {![datasetDigitizerPreviewAttachNative $id $w [dict get $receipt native_model]]} {
                set previewImage [image create photo -file $path]
                $w image create end -image $previewImage
            }
            $w insert end "\n[scientificDatasetFilterMode $::GX::ui(previewMap,dimensions) $::GX::ui(previewMap,filters) $::GX::ui(previewMap,separate)] — [dict get $receipt trace_count] trace(s)\nX: [dict get $axes x]   Y: [dict get $axes y]\nRows: [dict get $receipt row_count]; reduced display: [dict get $receipt reduced]. Original source ordering and gaps retained.\n"
            $w insert end "[scientificDatasetCoordinateNotice [dict get $receipt coordinate_presentation]]\n"
            lassign [dict get $receipt view_bounds] x0 y0 x1 y1
            $w insert end "Independent axes — X view: [format %.8g $x0] .. [format %.8g $x1]; Y view: [format %.8g $y0] .. [format %.8g $y1]. [dict get $receipt displayed_points] drawn points.\n"
        } on error {message options} {if {$epoch==$::GX::ui(previewEpoch) && $expected eq [datasetPreviewStamp]} {$w insert end "Scientific preview unavailable: $message\n"}} finally {file delete -force $path}
    }
    if {[catch {datasetDigitizerPreviewFinish $w $id} reason]} {$w insert end "Original image unavailable: $reason\n"}
    $w configure -state disabled
    return 1
}

proc ::GX::datasetMediaViewerOpen {id kind} {
    variable ::GX::DatasetViewer::state
    set w [datasetViewerWindow $id {CORE media lifecycle}];wm withdraw $w
    set path $state($w,path)
    if {$kind eq "pdf"} {set script pdf_dataset_viewer.py;set args [list $path $id]} else {set script media_dataset_viewer.py;set args [list $path $id $kind]}
    if {$kind eq "audio"} {
        set metadata [datasetMetadataRead $::GX::currentSession $id]
        foreach key {audio.raw_input_format audio.raw_sample_rate_hz audio.raw_channels audio.selected_stream_index} {lappend args [datasetPublicationV2DictDefault $metadata $key {}]}
    }
    set state($w,externalPipe) [open [concat [list | [runtimeToolRequired python] -B [file join $::GX::scriptDir core python $script]] $args [list 2>@stderr]] r]
    fconfigure $state($w,externalPipe) -blocking 0 -buffering none
    set state($w,externalPids) [pid $state($w,externalPipe)]
    fileevent $state($w,externalPipe) readable [list ::GX::datasetMediaViewerWatch $w]
    return $w
}
proc ::GX::datasetMediaViewerWatch {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,externalPipe)]} return
    set channel $state($w,externalPipe)
    catch {read $channel 4096}
    if {[eof $channel]} {fileevent $channel readable {};catch {close $channel};unset state($w,externalPipe) state($w,externalPids);datasetViewerClose $w}
}

rename ::GX::openSessionPath ::GX::openSessionPath_before_dataset_edit_guard
proc ::GX::openSessionPath {path} {
    if {[info exists ::GX::datasetPageEditors]&&[dict size $::GX::datasetPageEditors]} {error {Save or Cancel the open Dataset editor before switching Sessions. Draft input remains in its section.}}
    tailcall openSessionPath_before_dataset_edit_guard $path
}
source [file join [file dirname [info script]] dataset_digitizer_preview_v1.tcl]
