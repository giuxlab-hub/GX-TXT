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
 proc near {before after {tol 1e-9}} {if {[llength $before]!=[llength $after]} {return 0};set d 0;foreach a $before b $after {foreach x $a y $b {set d [expr {max($d,abs($x-$y))}]}};return [expr {$d<$tol}]}
 proc selectMany {values} {
  selectCurve [lindex $values 0];set tree $::w.leftScroll.viewport.content.curves
  foreach id [lrange $values 1 end] {$tree see $id;pause 60;lassign [$tree bbox $id name] x y width height;exec xdotool keydown Control_L mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1 keyup Control_L;pause 100}
 }
 proc cascadeChoose {button parent label} {
  click $button;set menu [$button cget -menu];set i [menuIndex $menu $parent];set sub [$menu entrycget $i -menu]
  exec xdotool mousemove [expr {[winfo rootx $menu]+70}] [expr {[winfo rooty $menu]+[$menu yposition $i]+10}];pause 400
  check {[winfo ismapped $sub]} {constraint submenu actually visible};popupEntry $sub $label
 }
 proc relationship {logical} {return [::GX::Native2D::core constraint_get $::scene [dict get $::GX::CurveWorkbench::st($::w,constraints) $logical native]]}
 proc inspectorSelect {id} {
  menuChoose $::w.sketchbar.constraints {Inspector / dimensions*};set panel [::GX::CurveWorkbench::_constraintPanel $::w];set tree $panel.tree
  $tree see $id;pause 50;lassign [$tree bbox $id] x y width height
  exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 100
  return $panel
 }
 set a [lindex $ids 0];set b [lindex $ids 2];set gestures {};set translationPixels 30
 selectMany [list $a $b];::GX::CurveWorkbench::_fit $w;pause 120
 set beforeA [curvePoints $a];set beforeB [curvePoints $b];set unrelated [curvePoints [lindex $ids 4]]
 set historyBefore [dict get [::GX::scientificHistoryViewerStatus $w] count]
 set g [gizmoDrag translate]
 set afterA [curvePoints $a];set afterB [curvePoints $b]
 set dx [expr {[lindex $afterA 0 0]-[lindex $beforeA 0 0]}];set dy [expr {[lindex $afterA 0 1]-[lindex $beforeA 0 1]}]
 set expectedB [lmap p $beforeB {list [expr {[lindex $p 0]+$dx}] [expr {[lindex $p 1]+$dy}]}]
 check {[near $afterB $expectedB] && [curvePoints [lindex $ids 4]] eq $unrelated && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$historyBefore+1} {actual multiple selection translates both exact objects once and leaves unrelated curve unchanged}
 click $w.toolbar.undo;check {[near [curvePoints $a] $beforeA] && [near [curvePoints $b] $beforeB]} {multi-object Translate Undo restores both scientific objects}
 click $w.toolbar.redo;check {[near [curvePoints $a] $afterA] && [near [curvePoints $b] $afterB]} {multi-object Translate Redo restores both scientific objects}
 # Unequal visual scale alone must not forbid physically valid mm/mm rotation.
 selectCurve $a;::GX::Native2D::core aspect $scene auto
 set wide [::GX::Native2D::core view_requested $scene];lset wide 6 {-8 -1.5 12 1.5};::GX::Native2D::core view $scene $wide;::GX::CurveWorkbench::_draw $w;pause 100
 set g [gizmoDrag rotate]
 check {[dict get $g before] ne [dict get $g after] && ![dict get $g active_after] && [::GX::CurveWorkbench::_coordinateUnits [::GX::CurveWorkbench::_record $w $a]] eq {mm mm}} {non-square viewport still admits scientific rotation in one common physical mm frame}
 click $w.toolbar.undo;check {[near [curvePoints $a] [dict get $g before]]} {unequal visual-scale rotation Undo restores exact geometry}
 click $w.toolbar.redo
 ::GX::Native2D::core aspect $scene xy_equal
 selectCurve $a;::GX::CurveWorkbench::_fit $w 1;pause 120
 menuChoose $w.sketchbar.modify Translate
 set pivot [::GX::Native2D::core pivot $scene];set pivotXY [::GX::Native2D::core device $scene [dict get $pivot point]]
 set before [points];set end [list [expr {[lindex $pivotXY 0]+17}] [expr {[lindex $pivotXY 1]+14}]]
 movePointer $pivotXY;exec xdotool mousedown 1;pause 60;movePointer $end;pause 80;exec xdotool mouseup 1;pause 130
 set now [::GX::Native2D::core pivot $scene]
 check {[dict get $now mode] eq {custom} && [dict get $now point] ne [dict get $pivot point] && [points] eq $before} {actual pivot handle moves pivot without moving scientific geometry}
 foreach operation {translate rotate} {
  set original [points];set count [dict get [::GX::scientificHistoryViewerStatus $w] count];set g [gizmoDrag $operation escape]
  check {[near [points] $original] && ![::GX::Native2D::core drag_active $scene] && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$count} "Escape $operation preserves exact geometry and P017 History"
 }
 exec xdotool key Escape;pause 80
 set bezier [fixture {Editable cubic} cubic_bezier {{20 0} {21 2} {22 -1} {23 0}}]
 selectCurve $bezier;::GX::CurveWorkbench::_fit $w 1;pause 100;selectMode {Local Geometry*}
 set definition [dict get [::GX::CurveWorkbench::_record $w $bezier] sketch_definition]
 set start [xy [lindex [dict get $definition controls] 1]];movePointer $start;exec xdotool mousedown 1;pause 60
 movePointer [list [expr {[lindex $start 0]+18}] [expr {[lindex $start 1]-20}]];pause 100
 set preview $::GX::CurveWorkbench::st($w,previewDefinition)
 if {$mode eq {patched}} {
  set hostState [$::GX::CurveWorkbench::st($w,cadCanvas) state]
  set preview [dict get $hostState gesture proposal definition]
  check {[dict get [::GX::Native2D::core sketch_definition $scene [native $bezier]] controls] eq [dict get $definition controls] && [dict get $preview controls] ne [dict get $definition controls]} {CORE host preview exposes changed defining controls while authoritative definition stays uncommitted}
 }
 exec xdotool mouseup 1;pause 120
 set edited [dict get [::GX::CurveWorkbench::_record $w $bezier] sketch_definition]
 if {$mode eq {patched}} {check {[dict get $edited controls] eq [dict get $preview controls]} {released Bezier definition exactly matches admitted shared-host preview}}
 check {$edited ne $definition && [lindex [dict get $edited controls] 0] eq [lindex [dict get $definition controls] 0]} {actual Bezier defining-control drag changes intended definition while preserving unrelated endpoint}
 click $w.toolbar.undo;check {[dict get [::GX::CurveWorkbench::_record $w $bezier] sketch_definition] eq $definition} {Bezier defining edit Undo restores exact definition}
 click $w.toolbar.redo
 # Invalid numeric editing is rejected without geometry or History mutation.
 set tree $w.leftScroll.viewport.content.points;$tree see h1;pause 40;lassign [$tree bbox h1] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 80
 set invalidBefore [dict get [::GX::CurveWorkbench::_record $w $bezier] sketch_definition];set invalidCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
 typeInto $w.leftScroll.viewport.content.numeric.editX not-a-number
 click $w.leftScroll.viewport.content.numeric.apply
 check {[dict get [::GX::CurveWorkbench::_record $w $bezier] sketch_definition] eq $invalidBefore && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$invalidCount} {actual invalid numeric defining edit is rejected with exact rollback and no History step}
 # A vertical relationship uses the same native constraint owner as horizontal.
 set verticalLine [fixture {Vertical candidate} line {{28 0} {28 3}}]
 selectCurve $verticalLine;::GX::CurveWorkbench::_fit $w 1;pause 100;selectMode {Local Geometry*};canvasClick [xy {28 1.5}]
 cascadeChoose $w.sketchbar.constraints Directions Vertical
 set verticalId [lindex [dict keys $::GX::CurveWorkbench::st($w,constraints)] end]
 check {[dict get [relationship $verticalId] kind] eq {vertical} && [dict get [relationship $verticalId] valid]} {actual Vertical constraint native receipt is valid}
 set panel [inspectorSelect $verticalId];click $panel.actions.toggle
 check {[dict get [relationship $verticalId] disabled]} {actual Inspector disables Vertical relationship}
 click $panel.actions.remove;check {![dict exists $::GX::CurveWorkbench::st($w,constraints) $verticalId]} {actual Inspector removes Vertical relationship}
 click [::GX::native2DViewportPanelWidget $canvas palette].header.toggle
 # Whole line and circle references are a supported tangent pair.
 set tangentLine [fixture {Tangent line} line {{32 1} {36 1}}]
 set tangentCircle [fixture {Tangent circle} circle {{34 0}}]
 selectMany [list $tangentLine $tangentCircle];::GX::CurveWorkbench::_fit $w;pause 130
 cascadeChoose $w.sketchbar.constraints Connections Tangent
 set tangentId [lindex [dict keys $::GX::CurveWorkbench::st($w,constraints)] end]
 check {[dict get [relationship $tangentId] kind] eq {tangent} && [dict get [relationship $tangentId] valid]} {actual compatible line-circle Tangent uses native solver}
 shot tangent
 # Distinct dimensional workflow: driving value edit, then reference semantics.
 set dimensionLine [fixture {Dimension line} line {{40 0} {43 0}}]
 selectCurve $dimensionLine;::GX::CurveWorkbench::_fit $w 1;pause 100;selectMode {Local Geometry*};canvasClick [xy {41.5 0}]
 click $w.sketchbar.dimension;movePointer [xy {41.5 1}];pause 100;exec xdotool click 1;pause 100
 check {[winfo exists $w.inline.value]} {Dimension tool opens actual inline value editor}
 typeInto $w.inline.value 3;click $w.inline.commit
 set dimensionId $::GX::CurveWorkbench::st($w,selectedRelationship)
 check {[dict get [relationship $dimensionId] valid] && abs([dict get [relationship $dimensionId] measured_value]-3)<1e-8} {driving dimension initial value is scientifically measured}
 exec xdotool key Escape;pause 80
 set panel [inspectorSelect $dimensionId];click $panel.actions.edit
 check {[winfo exists $w.inline.value]} {Inspector Edit opens existing dimension inline editor}
 typeInto $w.inline.value 4;click $w.inline.commit
 check {[dict get [relationship $dimensionId] valid] && abs([dict get [relationship $dimensionId] measured_value]-4)<1e-7} {real edited driving dimension changes exact geometry to expected value}
 click [::GX::native2DViewportPanelWidget $canvas palette].header.toggle
 exec xdotool key Escape;pause 80
 set nativeConstraint [dict get $::GX::CurveWorkbench::st($w,constraints) $dimensionId native]
 set label [dict get [::GX::Native2D::core sketch_dimension_geometry $scene $nativeConstraint] label]
 movePointer $label;exec xdotool click 3;pause 100;popupEntry $w.relationshipMenu {Toggle Driving / Reference}
 check {[dict get [relationship $dimensionId] driven]} {actual relationship context toggles dimension to reference behavior}
 set panel [inspectorSelect $dimensionId];click $panel.actions.edit
 check {![winfo exists $w.inline] && [string match {*read-only*} $::GX::CurveWorkbench::st($w,status)]} {reference dimension refuses driving value editor without changing geometry}
 click [::GX::native2DViewportPanelWidget $canvas palette].header.toggle
 shot reference-dimension
 # Compound keeps exact inputs; Split Path keeps exact source and produces two.
 set compoundA [fixture {Compound A} line {{48 0} {50 0}}];set compoundB [fixture {Compound B} line {{52 1} {54 1}}]
 set originals [list [curvePoints $compoundA] [curvePoints $compoundB]]
 selectMany [list $compoundA $compoundB];menuChoose $w.sketchbar.modify {Combine / Compound*};click $w.pathJoin.actions.apply
 check {$::GX::UiField::formStatus($w.pathJoin) eq {Applied.}} {actual Compound review applies}
 click $w.pathJoin.actions.close;set compound $::GX::CurveWorkbench::st($w,active)
 check {[dict get [::GX::CurveWorkbench::_record $w $compound] sketch_definition family] eq {compound} && [curvePoints $compoundA] eq [lindex $originals 0] && [curvePoints $compoundB] eq [lindex $originals 1]} {Compound preserves both independent source objects and exact constituent topology}
 set splitA [fixture {Split A} line {{58 0} {60 0}}];set splitB [fixture {Split B} line {{60 0} {62 1}}]
 selectMany [list $splitA $splitB];menuChoose $w.sketchbar.modify {Join Path*};click $w.pathJoin.actions.apply;click $w.pathJoin.actions.close
 set path $::GX::CurveWorkbench::st($w,active);set sourcePath [dict get [::GX::CurveWorkbench::_record $w $path] sketch_definition]
 menuChoose $w.sketchbar.modify {Split selected Path*}
 check {[winfo exists $w.pathSplit]} {Split Path opens actual junction review}
 click $w.pathSplit.actions.apply
 check {$::GX::UiField::formStatus($w.pathSplit) eq {Applied.}} {actual Split Path junction committed}
 click $w.pathSplit.actions.close
 set splitIds $::GX::CurveWorkbench::st($w,objectSelection)
 check {[llength $splitIds]==2 && [dict get [::GX::CurveWorkbench::_record $w $path] sketch_definition] eq $sourcePath} {Split Path creates two exact topologies and preserves original source}
 click $w.toolbar.undo;foreach id $splitIds {check {![dict exists $::GX::CurveWorkbench::st($w,curves) $id]} {Split Undo removes only new split objects}}
 click $w.toolbar.redo
 # Direction state remains independent of source sample order and survives Save.
 set a $bezier;selectCurve $a;::GX::CurveWorkbench::_fit $w 1;pause 100;exec xdotool key Escape;pause 60
 set originalDefinition [dict get [::GX::CurveWorkbench::_record $w $a] sketch_definition]
 set marker [::GX::Native2D::core direction_marker $scene [native $a]]
 set control [lindex [dict get $originalDefinition controls] 0]
 if {![dict get $marker visible]} {movePointer [xy $control];exec xdotool click 3;pause 100;popupEntry $w.right.viewport.canvasContext {Show direction arrow}}
 movePointer [xy $control];exec xdotool click 3;pause 100;popupEntry $w.right.viewport.canvasContext {Hide direction arrow}
 check {![dict get [::GX::Native2D::core direction_marker $scene [native $a]] visible]} {actual Hide direction command disables marker}
 movePointer [xy $control];exec xdotool click 3;pause 100;popupEntry $w.right.viewport.canvasContext {Show direction arrow}
 set marker [::GX::Native2D::core direction_marker $scene [native $a]]
 check {[dict get $marker visible]} {actual Show direction command restores marker}
 movePointer [xy $control];exec xdotool click 3;pause 100;popupEntry $w.right.viewport.canvasContext {Flip direction}
 set beforeMove [::GX::Native2D::core direction_marker $scene [native $a]]
 set painted [::GX::Native2D::core render_marker $scene [native $a]]
 set target [xy [lindex [dict get $originalDefinition controls] 2]]
 movePointer [dict get $painted tip];exec xdotool mousedown 1;pause 60;movePointer $target;pause 100;exec xdotool mouseup 1;pause 100
 set direction [::GX::Native2D::core direction_marker $scene [native $a]]
 check {[dict get $direction fraction] ne [dict get $beforeMove fraction] && [dict get $direction forward] ne [dict get $marker forward] && [dict get [::GX::CurveWorkbench::_record $w $a] sketch_definition] eq $originalDefinition} {actual marker drag and Flip preserve exact defining control order}
 menuChoose $w.toolbar.workspace {Save*}
 set document $::GX::CurveWorkbench::st($w,document);set status [::GX::scientificHistoryViewerStatus $w]
 write [file join $output saved-history.tcldict] $status
 check {[dict get $status durable_revision]==[dict get $status accepted_revision]} {explicit Workspace Save drains accepted P017 History to durable state}
 set saved [dict get [::GX::CurveWorkbench::_record $w $a] sketch_definition]
 ::GX::CurveWorkbench::_close $w
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench [dict create workspace_id $document]];wm geometry $w 1480x940+20+20;pause 250
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 check {[dict get [::GX::CurveWorkbench::_record $w $a] sketch_definition] eq $saved && [::GX::Native2D::core direction_marker $scene [native $a]] eq $direction} {Save Close Reopen restores exact retained definition and intended direction properties}
 check {[dict exists $::GX::CurveWorkbench::st($w,curves) $datasetCurve] && [dict get [::GX::CurveWorkbench::_record $w $datasetCurve] source] eq {source018}} {reopened Workspace preserves Dataset logical identity}
 shot reopened
 set branchBefore [llength $modalEvents];set statusBefore [::GX::scientificHistoryViewerStatus $w]
 click $w.toolbar.undo
 set branchStatus [::GX::scientificHistoryViewerStatus $w]
 check {[dict get $branchStatus cursor]<[dict get $branchStatus count]} {actual immediate Undo exposes retained future before explicit branch}
 selectCurve $a;::GX::CurveWorkbench::_fit $w 1;pause 80
 set control [lindex [dict get [::GX::CurveWorkbench::_record $w $a] sketch_definition controls] 0]
 movePointer [xy $control];exec xdotool click 3;pause 100;popupEntry $w.right.viewport.canvasContext {Flip direction}
 set statusAfter [::GX::scientificHistoryViewerStatus $w]
 check {[llength $modalEvents]>$branchBefore && [dict get $statusAfter cursor]==[dict get $statusAfter count]} {real branch confirmation replaces future through P017 public History with no private timeline}
 write [file join $output branch-history.tcldict] [dict create before $statusBefore older $branchStatus after $statusAfter dialogs $modalEvents]
 menuChoose $w.toolbar.workspace {Save*}
 set sourceToken [::GX::curveSourceOpen $session $sourceRequest]
 set afterPage [::GX::curveSourcePage $sourceToken 0 1000];::GX::curveSourceClose $sourceToken
 foreach field {rows source_rows columns} {check {[dict get $afterPage $field] eq [dict get $sourcePage $field]} "immutable Dataset actual readback unchanged: $field"}
 check {[::GX::sessionInspectionDatasetPayload source018] eq $sourceBefore} {imported scientific source Dataset unchanged after all interactions}
 write [file join $output source-receipt.tcldict] [dict create before $sourceBefore after [::GX::sessionInspectionDatasetPayload source018] source_page_before $sourcePage source_page_after $afterPage]
 write [file join $output history-receipt.tcldict] [dict create final [::GX::scientificHistoryViewerStatus $w] branch_modals $modalEvents]
 check {$errors eq {}} "no GUI background errors: $errors"
 write [file join $output RESULT.txt] {PASS: actual multi-object/pivot/Bezier/Vertical/Tangent/dimensional/Compound/Split/direction/persistence GUI workflow.}
} on error {message options} {puts stderr [dict get $options -errorinfo];if {$w ne {} && [winfo exists $w]} {catch {shot failure}};set exitStatus 1} finally {
 catch {after cancel $branchWatcher}
 write [file join $output errors.tcllist] $errors
 write [file join $output input.tcllist] $inputTrace
 if {$w ne {} && [winfo exists $w]} {catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
