# P018 focused mapped Native2D/Curve Workbench verification; private data only.
lassign $argv framework output mode
if {$mode ni {baseline patched}} {error {Require measure, verify or preserve}}
if {[file exists $output]} {error {Fresh output required}}
set framework [file normalize $framework];file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1;set argv0 __p018_stress__
set catalog [file join $output framework];file mkdir [file join $catalog plugins modules]
foreach name {core app docs services gxtxt_pipeline.tcl} {file copy [file join $framework $name] [file join $catalog $name]}
foreach name {math.numeric plot.dataset viewer.curve_workbench} {file copy [file join $framework plugins modules $name] [file join $catalog plugins modules $name]}
source [file join $catalog gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc write {path text} {set f [open $path w];puts -nonewline $f $text;close $f}
proc pause {{ms 120}} {set ::waiting 1;after $ms {set ::waiting 0};vwait ::waiting;update idletasks}
proc check {test label} {
 if {![uplevel 1 [list expr $test]]} {error "FAIL: $label"}
 lappend ::checks [dict create name $label status PASS];write [file join $::output checks.tcllist] $::checks
 puts "PASS: $label";flush stdout
}
set checks {};set inputTrace {};set errors {};set evaluations {};set publications 0;set nativeEvents {};set modalEvents {};set inTrace 0
proc bgerror {message} {lappend ::errors $message;puts stderr "BACKGROUND: $message"}
proc traceEvaluate {command op} {lappend ::evaluations [lindex $command 2]}
proc tracePublish {command op} {incr ::publications}
proc traceInput {cmd op} {
 if {[lindex $cmd 1] eq {xdotool}} {lappend ::inputTrace [list [clock milliseconds] {*}[lrange $cmd 1 end]];write [file join $::output input.tcllist] $::inputTrace}
}
trace add execution exec enter traceInput
proc stockChoice {widget value} {
 click $widget;set i [lsearch -exact [$widget cget -values] $value]
 if {$i<0} {error "Missing actual choice $value in $widget"}
 exec xdotool key Home
 for {set n 0} {$n<$i} {incr n} {exec xdotool key Down}
 exec xdotool key Return;pause 100
 check {[$widget get] eq $value} "actual keyboard choice $value"
}
proc branchWatch {} {
 if {[winfo exists .]} {
  foreach top [guiWidgets .] {
   if {![winfo exists $top]} continue
   if {[winfo toplevel $top] ne $top || [wm title $top] ne {Branch Workspace History}} continue
   foreach button [guiWidgets $top] {
    if {[winfo class $button] in {Button TButton} && [winfo viewable $button] && [$button cget -text] eq {OK}} {
     lappend ::modalEvents [list branch_confirmation [clock milliseconds]]
     exec xdotool mousemove [expr {[winfo rootx $button]+[winfo width $button]/2}] [expr {[winfo rooty $button]+[winfo height $button]/2}] click 1
     break
    }
   }
  }
  set ::branchWatcher [after 70 branchWatch]
 }
}
proc guiWidgets {w} {set all [list $w];foreach c [winfo children $w] {lappend all {*}[guiWidgets $c]};return $all}
proc see {widget} {::GX::native2DViewportSeeWidget $::canvas $widget;pause 60}
proc click {widget} {
    see $widget
    check {[winfo ismapped $widget]} "mapped control $widget"
    exec xdotool mousemove [expr {[winfo rootx $widget]+[winfo width $widget]/2}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1
    pause
}
proc combo {widget pattern} {
    click $widget
    set popup [::GX::_uiFieldSelectorPanel $widget [winfo toplevel $widget]];set list $popup.options
    check {[winfo ismapped $popup]} {public Viewer-bounded selector opens}
    set wanted -1;set i 0;foreach label [$list get 0 end] {if {[string match $pattern $label]} {set wanted $i;break};incr i}
    check {$wanted>=0} "choice exists: $pattern"
    $list see $wanted;pause 50
    lassign [$list bbox $wanted] x y width height
    exec xdotool mousemove [expr {[winfo rootx $list]+$x+20}] [expr {[winfo rooty $list]+$y+$height/2}] click 1
    pause
}
proc typeInto {widget text} {click $widget;exec xdotool key Home shift+End BackSpace;exec xdotool type --clearmodifiers -- $text;pause 80}
proc shot {name} {::GX::native2DViewportTooltipHide;pause 80;exec timeout 8s import -silent -window root [file join $::output $name.png]}
proc menuIndex {menu pattern} {for {set i 0} {$i<=[$menu index end]} {incr i} {if {[$menu type $i] ne {separator} && [string match $pattern [$menu entrycget $i -label]]} {return $i}};error "Missing menu $pattern"}
proc menuChoose {button pattern} {
    click $button;set m [$button cget -menu];set i [menuIndex $m $pattern]
    set height [expr {[font metrics [$m cget -font] -linespace]+6}]
    if {$i<[$m index end]} {set height [expr {[$m yposition [expr {$i+1}]]-[$m yposition $i]}]}
    exec xdotool mousemove [expr {[winfo rootx $m]+40}] [expr {[winfo rooty $m]+[$m yposition $i]+$height/2}] click 1
    pause
}
proc selectCurve {id} {
    set tree $::w.leftScroll.viewport.content.curves
    $tree see $id;pause 50;lassign [$tree bbox $id name] x y width height
    exec xdotool mousemove [expr {[winfo rootx $tree]+$x+25}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1
    pause
}


proc points {} {::GX::Native2D::core points $::scene [dict get $::GX::CurveWorkbench::st($::w,curves) $::a native]}
proc movePointer {xy} {lassign $xy x y;exec xdotool mousemove [expr {[winfo rootx $::canvas]+int(round($x))}] [expr {[winfo rooty $::canvas]+int(round($y))}]}
proc gizmoDrag {mode {finish release}} {
    menuChoose $::w.sketchbar.modify [string totitle $mode]
    set items [::GX::Native2D::core render_gizmo $::scene]
    set start {};set end {}
    foreach item $items {
        if {$mode eq {translate} && [dict get $item handle] eq {x} && [dict get $item kind] eq {line}} {
            lassign [dict get $item a] ax ay;lassign [dict get $item b] bx by
            set start [list [expr {($ax+$bx)/2.0}] [expr {($ay+$by)/2.0}]]
            set end [list [expr {[lindex $start 0]+$::translationPixels}] [lindex $start 1]];break
        }
        if {$mode eq {rotate} && [dict get $item handle] eq {rotate}} {
            set start [dict get $item a]
            set pivot [dict get [::GX::Native2D::core pivot $::scene] point]
            lassign [::GX::Native2D::core device $::scene $pivot] cx cy
            set radius [expr {[lindex $start 0]-$cx}]
            set end [list $cx [expr {$cy-$radius}]];break
        }
    }
    check {$start ne {} && $end ne {}} "existing $mode gizmo geometry available"
    set expectedHandle [expr {$mode eq {translate}?{x}:{rotate}}]
    check {[::GX::Native2D::core gizmo_hit $::scene $start 5] eq $expectedHandle} "actual $mode handle hit"
    set before [points]
    if {$finish eq {reject}} {set end [::GX::Native2D::core device $::scene [dict get [::GX::Native2D::core pivot $::scene] point]]}
    movePointer $start;exec xdotool mousedown 1;pause 70
    set activeBegin [::GX::Native2D::core drag_active $::scene]
    movePointer $end;pause 120
    set preview [points];set activePreview [::GX::Native2D::core drag_active $::scene]
    if {$finish eq {escape}} {exec xdotool key Escape;pause 80}
    exec xdotool mouseup 1;pause 150
    set after [points];set activeAfter [::GX::Native2D::core drag_active $::scene]
    set record [dict create mode $mode finish $finish before $before preview $preview after $after start $start end $end active_begin $activeBegin active_preview $activePreview active_after $activeAfter]
    lappend ::gestures $record
    write [file join $::output gestures.tcllist] $::gestures
    shot $mode-$finish-[llength $::gestures]
    puts "GESTURE: $record";flush stdout
    return $record
}

::GX::configurationSet storage.session_root [file join $output Sessions];::GX::configurationSave {storage.session_root}
set session [::GX::createNewSession p018_stress {} 0]
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
package require Tk;wm withdraw .
set branchWatcher [after 70 branchWatch]
set wmPids [exec xfwm4 --replace --compositor=off --sm-client-disable >[file join $output wm.log] 2>@1 &];pause 300
set w {};set timings {};set snapshots {};set ids {};set segmentCount 0
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P018 Phase A representative objects}}]
 wm geometry $w 1480x940+20+20;raise $w;pause 200
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 set xs {};set ys {};for {set j 0} {$j<750} {incr j} {lappend xs [expr {20.0*$j/749}];lappend ys [expr {4+sin($j*.03)}]}
 ::GX::datasetPublicationV2PublishSeries $session math.numeric [dict create dataset_id source018 contract table.generic storage csv x_values $xs y_values $ys x_variable {variable_id x canonical x unit mm} y_variable {variable_id y canonical y unit mm}]
 set sourceBefore [::GX::sessionInspectionDatasetPayload source018]
 set ::GX::CurveWorkbench::st($w,preferredDataset) source018
 click $w.toolbar.add
 check {[winfo ismapped $w.source]} {actual Add curve source dialog opens}
 set datasetLabel {};dict for {label did} $::GX::CurveWorkbench::st($w,source.datasetMap) {if {$did eq {source018}} {set datasetLabel $label}}
 stockChoice $w.source.dataset $datasetLabel
 foreach {axis vid} {x x y y} {set label {};dict for {text actual} $::GX::CurveWorkbench::st($w,source.varMap) {if {$actual eq $vid} {set label $text}};stockChoice $w.source.$axis $label}
 check {[::GX::CurveWorkbench::_sourceId $w x] eq {x} && [::GX::CurveWorkbench::_sourceId $w y] eq {y}} {actual source selectors retain explicit Variable IDs}
 click $w.source.buttons.add
 set datasetCurve $::GX::CurveWorkbench::st($w,active)
 set rec [::GX::CurveWorkbench::_record $w $datasetCurve]
 set sourceRequest [dict get $rec source_request]
 set sourceToken [::GX::curveSourceOpen $session $sourceRequest]
 set sourcePage [::GX::curveSourcePage $sourceToken 0 1000];::GX::curveSourceClose $sourceToken
 check {[dict get $rec source] eq {source018} && [llength [dict get $rec samples]]==750} {actual Add to workspace imports750 numerical XY rows through Curve Source}
 check {[::GX::CurveWorkbench::_coordinateUnits $rec] eq {mm mm}} {Dataset physical units preserved}
 shot imported
 for {set i 0} {$i<8} {incr i} {
  set controls {};set ox [expr {($i%10)*2.0}];set oy [expr {int($i/10)*2.0}]
  for {set j 0} {$j<=10} {incr j} {
   set t [expr {$j/10.0}]
   switch [expr {$i%4}] {
    0 {set xy [list [expr {$ox+1.4*$t}] [expr {$oy+.5*sin(6.28*$t)}]]}
    1 {set xy [list [expr {$ox+.7+.6*cos(6.28*$t)}] [expr {$oy+.6*sin(6.28*$t)}]]}
    2 {set xy [list [expr {$ox+1.4*$t}] [expr {$oy+.5*(($j%2)*2-1)}]]}
    3 {set xy [list [expr {$ox+1.4*$t}] [expr {$oy+$t*$t}]]}
   };lappend controls $xy
  }
  set family [expr {$i%2?{spline}:{polyline}}]
  ::GX::CurveWorkbench::_sketchApply $w $::GX::CurveWorkbench::st($w,token) {} [dict create family $family controls $controls radius_x 1 radius_y 1 rotation 0 angle_start 0 angle_sweep 360 closed 0 samples 64 name "Path[format %02d $i] $family"]
  set id $::GX::CurveWorkbench::st($w,active);lappend ids $id;incr segmentCount [expr {[llength $controls]-1}]
 }
 check {[dict size $::GX::CurveWorkbench::st($w,curves)]==9 && $segmentCount>=80} {8 genuine varied retained paths, at least10spans each /80total}
 selectCurve [lindex $ids 0]
 ::GX::CurveWorkbench::_fit $w;pause 400
 set initial [::GX::Native2D::core view_requested $scene]
 source [file join [file dirname [info script]] gui_helpers.tcl]
 if {![info exists ::env(P018_SKIP_SCENARIOS)]} {source [file join [file dirname [info script]] gui_scenarios.tcl]}
 set a [lindex $ids 0];set b [lindex $ids 2];selectCurve $a;set gestures {};set translationPixels 32
 ::GX::CurveWorkbench::_fit $w 1;pause 150
 proc marker {} {return [::GX::Native2D::core render_marker $::scene [dict get $::GX::CurveWorkbench::st($::w,curves) $::a native]]}
 proc arrowCheck {label} {
  set m [marker];set expected [concat [dict get $m tail] [dict get $m tip]];set found 0
  if {[llength [info commands ::GX::native2DSpriteSceneAnchor]]} {
   set anchor [::GX::native2DSpriteSceneAnchor $::canvas $::a direction_tip]
   set tail [::GX::native2DSpriteSceneAnchor $::canvas $::a direction_tail]
   set actual [concat [dict get $tail position] [dict get $anchor position]]
   set error 0;foreach x $actual y $expected {set error [expr {max($error,abs($x-$y))}]};set found [expr {$error<1e-9}]
  } else {
   foreach item [$::canvas find withtag direction_$::a] {if {[$::canvas coords $item] eq $expected} {set found 1}}
  }
  check {$found} "$label: actual arrow tail/tip follows authoritative direction marker"
 }
 set initialArrow [::GX::Native2D::core direction_marker $scene [dict get [::GX::CurveWorkbench::_record $w $a] native]]
 if {![dict get $initialArrow visible]} {
  exec xdotool key Escape;pause 80
  set control [dict get [lindex [::GX::Native2D::core interaction_controls $scene [dict get [::GX::CurveWorkbench::_record $w $a] native]] 0] point]
  movePointer [xy $control];exec xdotool click 3;pause 100;popupEntry $w.right.viewport.canvasContext {Show direction arrow}
 }
 arrowCheck initial
 proc nearPoints {a b} {
  if {[llength $a]!=[llength $b]} {return 0}
  set error 0;foreach p $a q $b {foreach x $p y $q {set error [expr {max($error,abs($x-$y))}]}}
  puts "Coordinate comparison maximum absolute error: $error";return [expr {$error<1e-12}]
 }
 set operations {translate rotate}
 foreach op $operations {
  set old [marker];set oldStyle [::GX::Native2D::core direction_marker $scene [dict get [::GX::CurveWorkbench::_record $w $a] native]];set oldView [::GX::Native2D::core view_requested $scene];set g [gizmoDrag $op]
  check {[dict get $g before] ne [dict get $g preview] && [dict get $g preview] eq [dict get $g after] && ![dict get $g active_after]} "$op previews and commits real geometry"
  check {[marker] ne $old} "$op changes direction-arrow presentation"
  arrowCheck $op
  click $w.toolbar.undo
  set undoStyle [::GX::Native2D::core direction_marker $scene [dict get [::GX::CurveWorkbench::_record $w $a] native]]
  write [file join $output $op-undo.tcldict] [dict create before [dict get $g before] after [points] marker_before $old marker_after [marker] direction_before $oldStyle direction_after $undoStyle view_before $oldView view_after [::GX::Native2D::core view_requested $scene] record [::GX::CurveWorkbench::_record $w $a] history [::GX::scientificHistoryViewerStatus $w]]
  check {[points] eq [dict get $g before]} "$op Undo restores exact native coordinates"
  check {[marker] eq $old && $undoStyle eq $oldStyle} "$op Undo restores exact native direction presentation"
  click $w.toolbar.redo;check {[nearPoints [points] [dict get $g after]]} "$op Redo restores geometry";arrowCheck redo
  click $w.toolbar.undo
 }
 # Representative retained defining-control edit through actual table/entries.
 set tree $w.leftScroll.viewport.content.points
 $tree see h2;pause 50;lassign [$tree bbox h2] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+25}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 100
 set before [points]
 typeInto $w.leftScroll.viewport.content.numeric.editY 0.4
 click $w.leftScroll.viewport.content.numeric.apply
 check {[points] ne $before} {numeric defining-handle edit changes retained geometry}
 arrowCheck edited
 click $w.toolbar.undo;check {[points] eq $before} {handle edit Undo}
 selectCurve $a
 menuChoose $w.toolbar.objects {Hide selection};check {[llength [info commands ::GX::native2DSpriteSceneDescribe]]?[catch {::GX::native2DSpriteSceneDescribe $canvas $a}]:[llength [$canvas find withtag direction_$a]]==0} {hidden path has no arrow}
 menuChoose $w.toolbar.objects {Show selection};arrowCheck shown
 set controls [::GX::native2DViewportPanelWidget $canvas controls]
 set grid [::GX::Native2D::core grid $scene]
 ::GX::Native2D::core grid $scene {spacing_x .25 spacing_y .25}
 click $controls.body.grid_snap
 ::GX::Native2D::core pivot $scene custom {0 0};set translationPixels 128
 set g [gizmoDrag translate]
 set dx [expr {[lindex [lindex [dict get $g after] 0] 0]-[lindex [lindex [dict get $g before] 0] 0]}]
 check {abs($dx)>.01 && abs($dx/.25-round($dx/.25))<1e-9} {real transform retains authored grid snapping}
 click $w.toolbar.undo;click $controls.body.grid_snap
 ::GX::Native2D::core grid $scene $grid
 ::GX::CurveWorkbench::_fit $w;pause 150
 menuChoose $w.sketchbar.modify Translate
 set origin [lindex [points] 0];::GX::Native2D::core pivot $scene custom $origin;::GX::CurveWorkbench::_draw $w
 click $controls.body.object_snap
 set start {};foreach i [::GX::Native2D::core render_gizmo $scene] {if {[dict get $i handle] eq {free} && [dict get $i kind] eq {box}} {set start [dict get $i a];break}}
 set target [lindex [::GX::Native2D::core points $scene [dict get $::GX::CurveWorkbench::st($w,curves) $b native]] 0]
 lassign [::GX::Native2D::core device $scene $origin] ox oy;lassign [::GX::Native2D::core device $scene $target] tx ty
 set end [list [expr {[lindex $start 0]+$tx-$ox+1}] [expr {[lindex $start 1]+$ty-$oy-1}]]
 movePointer $start;exec xdotool mousedown 1;pause 60;movePointer $end;pause 100
 set hostSnap [$::GX::CurveWorkbench::st($w,cadCanvas) state]
 write [file join $output object-snap-preview.tcldict] [dict create host $hostSnap status $::GX::CurveWorkbench::st($w,status) origin $origin target $target]
 set snapProposal [dict get $hostSnap gesture proposal]
 check {[dict exists $snapProposal snap_target] && [dict get $snapProposal snap_target object]==[native $b]} {native object-snap proposal identifies the actual target object}
 set expectedDelta [lmap t $target o $origin {expr {$t-$o}}]
 check {[lmap got [dict get $snapProposal translation] want $expectedDelta {expr {abs($got-$want)<1e-9}}] eq {1 1}} {native object-snap proposal retains exact scientific target delta}
 exec xdotool mouseup 1;pause 120;arrowCheck snapped
 set committedOrigin [lindex [points] 0]
 check {[lmap got $committedOrigin want $target {expr {abs($got-$want)<1e-9}}] eq {1 1}} {committed snapped origin exactly equals authoritative target point}
 click $w.toolbar.undo;click $controls.body.object_snap
 set panel [::GX::native2DViewportPanelWidget $canvas compare];set p [::GX::CurveWorkbench::_comparisonControls $w]
 click $panel.header.toggle
 combo $p.curves.reference {Path02*};combo $p.curves.targetPath {Path00*};combo $p.curves.method geometry;click $p.curves.compare
 check {[string match {Completed*} $::GX::CurveWorkbench::st($w,comparisonText)] && ![$p.curves.publish instate disabled] && $::GX::CurveWorkbench::st($w,residualWidget) ne {}} {comparison, actual residual and publication remain available}
 shot comparison
 click $p.curves.publish;typeInto $w.comparisonReport.viewport.content.field0.entry p018_deviations;click $w.comparisonReport.actions.apply
 check {$::GX::UiField::formStatus($w.comparisonReport) eq {Applied.} && {p018_deviations} in [::GX::sessionInspectionDatasetIds]} {original Dataset owner publishes real deviations in private Session}
 click $w.comparisonReport.actions.close;click $panel.header.close
 set sourceToken [::GX::curveSourceOpen $session $sourceRequest]
 set afterPage [::GX::curveSourcePage $sourceToken 0 1000];::GX::curveSourceClose $sourceToken
 foreach field {rows source_rows columns} {check {[dict get $afterPage $field] eq [dict get $sourcePage $field]} "immutable Dataset actual readback unchanged: $field"}
 check {[::GX::sessionInspectionDatasetPayload source018] eq $sourceBefore} {imported scientific source Dataset unchanged after all interactions}
 write [file join $output source-receipt.tcldict] [dict create before $sourceBefore after [::GX::sessionInspectionDatasetPayload source018] source_page_before $sourcePage source_page_after $afterPage]
 write [file join $output history-receipt.tcldict] [dict create final [::GX::scientificHistoryViewerStatus $w] branch_modals $modalEvents]
 check {$errors eq {}} "no GUI background errors: $errors"
 write [file join $output RESULT.txt] {PASS: focused actual GUI selection, transform, topology, constraints, spline, arrows, source, comparison and publication workflow.}
} on error {message options} {puts stderr [dict get $options -errorinfo];if {$w ne {} && [winfo exists $w]} {catch {shot failure};catch {write [file join $output failure-state.tcldict] [dict create status $::GX::CurveWorkbench::st($w,status) history [::GX::scientificHistoryViewerStatus $w] active $::GX::CurveWorkbench::st($w,active)]}};set exitStatus 1} finally {
 catch {after cancel $branchWatcher}
 write [file join $output errors.tcllist] $errors
 write [file join $output input.tcllist] $inputTrace
 if {$w ne {} && [winfo exists $w]} {catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
