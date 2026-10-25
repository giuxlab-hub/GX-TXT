# P018 focused mapped Native2D/Curve Workbench verification; private data only.
lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
set framework [file normalize $framework];file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1;set argv0 __p019_constrained_drag__
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
proc bgerror {message} {lappend ::errors $message;puts stderr "BACKGROUND: $message";catch {diagnostic background_error [dict create message $message errorinfo $::errorInfo errorstack [info errorstack]]}}
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



::GX::configurationSet storage.session_root [file join $output Sessions];::GX::configurationSet storage.temp_dir [file join $output tmp];::GX::configurationSave {storage.session_root storage.temp_dir}
set session [::GX::createNewSession p019_controlled {} 0]
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
package require Tk;wm withdraw .;set branchWatcher [after 70 branchWatch]
set wmPids [exec xfwm4 --replace --compositor=off --sm-client-disable >[file join $output wm.log] 2>@1 &];pause 300
set w {};set sharedEvents {};set sharedBusy 0;set created {}
proc sharedTrace {cmd args} {
 if {$::sharedBusy || [lindex $cmd 1] ni {construction topology constraint dimension}} return
 set ::sharedBusy 1
 try {lappend ::sharedEvents [dict create time_us [clock microseconds] phase [lindex $args end] code [expr {[lindex $args end] eq {leave}?[lindex $args 0]:0}] command [string range $cmd 0 8000] result [expr {[lindex $args end] eq {leave}?[string range [lindex $args 1] 0 8000]:{}}] state [$::tools state]];write [file join $::output shared-events.tcllist] $::sharedEvents} finally {set ::sharedBusy 0}
}
proc controllerProof {label} {set state [$::tools state];write [file join $::output $label.tcldict] [dict create controller $::tools state $state construction [$::tools construction state] host [$::host state]];return $state}
proc clickWorld {point} {
 set device [::GX::Native2D::core device $::scene $point];set pixel [lmap c $device {expr {int(round($c))}}]
 set actual [::GX::Native2D::core world $::scene $pixel];canvasClick $pixel;return $actual
}
proc exactWorldControls {id} {return [lmap entry [$::cad object controls [native $id]] {dict get $entry point}]}
proc closePoints {a b {tolerance 1e-10}} {if {[llength $a]!=[llength $b]} {return 0};foreach p $a q $b {foreach x $p y $q {if {abs($x-$y)>$tolerance} {return 0}}};return 1}
proc createByCanvas {family label points finish} {
 set oldIds [dict keys $::GX::CurveWorkbench::st($::w,curves)];set count [dict get [::GX::scientificHistoryViewerStatus $::w] count]
 menuChoose $::w.sketchbar.create $label;set actual {};set n 0
 foreach point $points {
  lappend actual [clickWorld $point];incr n
  if {$n==1} {
   set state [$::tools construction state]
   check {[dict get $state family] eq $family && [llength [dict get $state places]]==1} "actual $family first click is retained by shared CORE construction owner"
   check {[dict keys $::GX::CurveWorkbench::st($::w,curves)] eq $oldIds && [dict get [::GX::scientificHistoryViewerStatus $::w] count]==$count} "$family first placement has not published scientific geometry or History"
   movePointer [xy [lindex $points 1]];pause 90;controllerProof $family-preview
  }
 }
 if {$finish eq {return}} {exec xdotool key Return;pause 160}
 set id $::GX::CurveWorkbench::st($::w,active);set definition [$::cad object definition [native $id]]
 check {$id ni $oldIds && [dict get $definition family] eq $family && [closePoints [exactWorldControls $id] $actual]} "actual $family GUI commits correct authoritative defining geometry"
 check {[dict get [::GX::scientificHistoryViewerStatus $::w] count]==$count+1} "$family GUI commit records exactly one scientific History step"
 controllerProof $family-committed
 exec xdotool key Escape;pause 90
 check {![dict get [$::host state] active]} "$family tool termination leaves no common gesture"
 lappend ::created $id;return $id
}
proc formChoice {widget value} {
 see $widget;exec xdotool mousemove [expr {[winfo rootx $widget]+[winfo width $widget]-8}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1;pause 90
 set popup [::GX::_uiFieldSelectorPanel $widget [winfo toplevel $widget]];set list $popup.options
 if {![winfo exists $popup] || ![winfo ismapped $popup]} {set popup [::ttk::combobox::PopdownWindow $widget];set list $popup.f.l}
 check {[winfo ismapped $popup]} {actual form choice popup is mapped}
 set n [lsearch -exact [$list get 0 end] $value];check {$n>=0} "actual form offers $value";$list see $n;pause 50;lassign [$list bbox $n] x y width height
 exec xdotool mousemove [expr {[winfo rootx $list]+$x+20}] [expr {[winfo rooty $list]+$y+$height/2}] click 1;pause 90
 check {[$widget get] eq $value} "actual form chose $value"
}
proc numericPolyline {name controls} {
 menuChoose $::w.sketchbar.create {Exact numeric creation*}
 typeInto $::w.sketch.viewport.content.field0.entry $name;formChoice $::w.sketch.viewport.content.field1.entry polyline
 typeInto $::w.sketch.viewport.content.field3.entry $controls;click $::w.sketch.actions.apply
 check {$::GX::UiField::formStatus($::w.sketch) eq {Applied.}} {actual reviewed numeric retained creation is applied}
 set id $::GX::CurveWorkbench::st($::w,active);click $::w.sketch.actions.close
 check {[dict get [$::cad object definition [native $id]] family] eq {polyline} && [closePoints [exactWorldControls $id] $controls]} {numeric GUI retains exact declared controls through authoritative native owner}
 return $id
}
proc requireReceipt {operation} {set receipt [dict get [$::tools state] receipt];check {[dict get $receipt status] eq {committed} && [dict get $receipt operation] eq "topology.$operation"} "actual GUI operation uses public shared CORE topology.$operation receipt"}
proc selectMany {ids} {
 selectCurve [lindex $ids 0];set tree $::w.leftScroll.viewport.content.curves
 foreach id [lrange $ids 1 end] {$tree see $id;pause 50;lassign [$tree bbox $id name] x y width height;exec xdotool keydown Control_L mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1 keyup Control_L;pause 90}
}
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P019 controlled shared topology}}];wm geometry $w 1480x940+20+20;raise $w;pause 220
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 source [file join [file dirname [info script]] gui_helpers.tcl]
 menuChoose $w.toolbar.workspace {Workspace Configuration*};typeInto $w.coordinateConfiguration.viewport.content.field0.entry mm;typeInto $w.coordinateConfiguration.viewport.content.field1.entry mm;click $w.coordinateConfiguration.actions.apply
 check {$::GX::UiField::formStatus($w.coordinateConfiguration) eq {Applied.}} {explicit homogeneous scientific frame configured};click $w.coordinateConfiguration.actions.close
 set host [::GX::CurveWorkbench::_cadCanvas $w];set cad [$host context];set tools [$host advanced];trace add execution $tools {enter leave} sharedTrace
 set a [numericPolyline {Exact A} {{0 0} {2 0}}];set b [numericPolyline {Exact B} {{2 0} {4 1}}]
 set sourceA [$cad object definition [native $a]];set sourceB [$cad object definition [native $b]]
 selectMany [list $a $b];menuChoose $w.sketchbar.modify {Join Path*}
 check {[$cad object definition [native $a]] eq $sourceA && [$cad object definition [native $b]] eq $sourceB} {opening Join Path review does not change source geometry}
 click $w.pathJoin.actions.apply;check {$::GX::UiField::formStatus($w.pathJoin) eq {Applied.}} {actual Join Path review commits through shared topology owner};click $w.pathJoin.actions.close
 set joined $::GX::CurveWorkbench::st($w,active);set joinedDef [$cad object definition [native $joined]]
 check {[dict get $joinedDef family] eq {composite_path} && [llength [$cad component list [native $joined]]]==2 && ![dict exists $::GX::CurveWorkbench::st($w,curves) $a] && ![dict exists $::GX::CurveWorkbench::st($w,curves) $b]} {Join Path creates one exact logical connected Path with two retained constituents}
 controllerProof join-path;requireReceipt join_path;::GX::CurveWorkbench::_fit $w 1;pause 100;shot joined-path
 menuChoose $w.sketchbar.modify {Separate exact constituents};set separated $::GX::CurveWorkbench::st($w,objectSelection)
 check {[llength $separated]==2 && [$cad object definition [native $joined]] eq $joinedDef} {Separate creates exact constituents while preserving original Path}
 controllerProof separate;requireReceipt separate
 set member [lindex $separated 0];selectCurve $member;set original [$cad object definition [native $member]]
 set tree $w.leftScroll.viewport.content.points;$tree see h1;pause 50;lassign [$tree bbox h1] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 90
 typeInto $w.leftScroll.viewport.content.numeric.editY 0.3;click $w.leftScroll.viewport.content.numeric.apply
 check {[$cad object definition [native $member]] ne $original && [$cad object definition [native $joined]] eq $joinedDef} {actual separated-constituent modification leaves original retained topology unchanged}
 click $w.toolbar.undo;check {[$cad object definition [native $member]] eq $original} {separated-constituent edit Undo restores exact definition}
 selectCurve $joined;menuChoose $w.sketchbar.modify {Split selected Path*};check {[winfo exists $w.pathSplit]} {actual Split Path review opens}
 click $w.pathSplit.actions.apply;check {$::GX::UiField::formStatus($w.pathSplit) eq {Applied.}} {actual Split Path review applies};click $w.pathSplit.actions.close
 set split $::GX::CurveWorkbench::st($w,objectSelection)
 check {[llength $split]==2 && [$cad object definition [native $joined]] eq $joinedDef} {Split yields two native topologies and preserves original exact source}
 controllerProof split;requireReceipt split_composition;click $w.toolbar.undo;foreach id $split {check {![dict exists $::GX::CurveWorkbench::st($w,curves) $id]} {Split Undo removes only created outputs}};click $w.toolbar.redo
 set c [numericPolyline {Disconnected C} {{6 3} {8 3}}]
 set first [lindex $separated 0];set firstDef [$cad object definition [native $first]];set cDef [$cad object definition [native $c]]
 selectMany [list $first $c];menuChoose $w.sketchbar.modify {Combine / Compound*};click $w.pathJoin.actions.apply
 check {$::GX::UiField::formStatus($w.pathJoin) eq {Applied.}} {actual Compound review applies};click $w.pathJoin.actions.close
 set compound $::GX::CurveWorkbench::st($w,active)
 check {[dict get [$cad object definition [native $compound]] family] eq {compound} && [$cad object definition [native $first]] eq $firstDef && [$cad object definition [native $c]] eq $cDef} {Compound retains both independent source objects without rewriting scientific geometry}
 controllerProof compound;requireReceipt compound
 # Join point is explicitly a native coincidence, not logical path composition.
 set first [lindex $separated 0];set second [lindex $separated 1];selectCurve $first;::GX::CurveWorkbench::_fit $w 1;pause 90;selectMode {Local Geometry*}
 set pointTree $w.leftScroll.viewport.content.points;$pointTree see h2;pause 50;lassign [$pointTree bbox h2] x y width height
 exec xdotool mousemove [expr {[winfo rootx $pointTree]+$x+20}] [expr {[winfo rooty $pointTree]+$y+$height/2}] click 1;pause 100
 check {$::GX::CurveWorkbench::st($w,active) eq $first} {explicit defining-point table selection retains intended source logical identity}
 menuChoose $w.sketchbar.modify {Native point operations*};click $w.cad.sketch;popupEntry [$w.cad.sketch cget -menu] {Join point numerically*}
 check {[winfo exists $w.join]} {actual Join point numeric review opens};formChoice $w.join.viewport.content.field1.entry $second;typeInto $w.join.viewport.content.field2.entry 0
 click $w.join.actions.apply;check {$::GX::UiField::formStatus($w.join) eq {Applied.}} {actual Join point commits existing native coincidence};click $w.join.actions.close
 set logical [lindex [dict keys $::GX::CurveWorkbench::st($w,constraints)] end];set receipt [$cad relationship get [dict get $::GX::CurveWorkbench::st($w,constraints) $logical native]]
 check {[dict get $::GX::CurveWorkbench::st($w,constraints) $logical definition a] eq $first && [dict get $::GX::CurveWorkbench::st($w,constraints) $logical definition b] eq $second && [dict get $receipt kind] eq {coincident} && [dict get $receipt valid] && [dict exists $::GX::CurveWorkbench::st($w,curves) $first] && [dict exists $::GX::CurveWorkbench::st($w,curves) $second]} {Join point records a valid coincidence without replacing logical topology}
 controllerProof join-point;requireReceipt join_points
 check {$errors eq {}} {shared topology actual GUI callbacks have no unexpected background errors}
 write [file join $output topology-receipt.tcldict] [dict create joined $joined definition $joinedDef separated $separated split $split compound $compound coincidence $receipt advanced [$tools state] history [::GX::scientificHistoryViewerStatus $w]]
 shot topology-final;write [file join $output RESULT.txt] {PASS: actual GUI Join Path Separate constituent edit Split Compound and distinct Join point through shared CORE topology.}
} on error {message options} {puts stderr [dict get $options -errorinfo];if {$w ne {}&&[winfo exists $w]} {catch {shot failure}};set exitStatus 1} finally {
 catch {trace remove execution $tools {enter leave} sharedTrace};catch {after cancel $branchWatcher};write [file join $output errors.tcllist] $errors;write [file join $output input.tcllist] $inputTrace
 if {$w ne {}&&[winfo exists $w]} {catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
