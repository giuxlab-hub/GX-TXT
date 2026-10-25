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
 if {$::sharedBusy || [lindex $cmd 1] ni {construction topology constraint dimension direction}} return
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
proc cascadePath {button labels} {
 click $button;set menu [$button cget -menu]
 foreach label [lrange $labels 0 end-1] {set i [menuIndex $menu $label];set sub [$menu entrycget $i -menu];exec xdotool mousemove [expr {[winfo rootx $menu]+70}] [expr {[winfo rooty $menu]+[$menu yposition $i]+10}];pause 300;check {[winfo ismapped $sub]} "actual cascade $label opens";set menu $sub}
 popupEntry $menu [lindex $labels end]
}
proc numericPrimitive {name family controls} {
 menuChoose $::w.sketchbar.create {Exact numeric creation*};typeInto $::w.sketch.viewport.content.field0.entry $name;formChoice $::w.sketch.viewport.content.field1.entry $family
 typeInto $::w.sketch.viewport.content.field3.entry $controls
 if {$family eq {circle}} {typeInto $::w.sketch.viewport.content.field4.entry 1}
 click $::w.sketch.actions.apply;check {$::GX::UiField::formStatus($::w.sketch) eq {Applied.}} "actual numeric $family creation applies"
 set id $::GX::CurveWorkbench::st($::w,active);click $::w.sketch.actions.close;return $id
}
proc relationship {logical} {return [::GX::Native2D::core constraint_get $::scene [dict get $::GX::CurveWorkbench::st($::w,constraints) $logical native]]}
proc latestRelationship {} {return [lindex [dict keys $::GX::CurveWorkbench::st($::w,constraints)] end]}
proc inspectorSelect {id} {
 menuChoose $::w.sketchbar.constraints {Inspector / dimensions*};set panel [::GX::CurveWorkbench::_constraintPanel $::w];set tree $panel.tree
 $tree see $id;pause 50;lassign [$tree bbox $id] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 100;return $panel
}
proc collapseInspector {} {click [::GX::native2DViewportPanelWidget $::canvas palette].header.toggle}
proc relationReceipt {} {set r [dict get [$::tools state] receipt];check {[dict get $r status] eq {committed} && [dict get $r operation] eq {constraint.apply}} {actual relationship mutation uses shared CORE admission/apply/receipt}}
proc startRadius {id point} {
 selectMode {Select Entire Curve / Path};selectCurve $id
 cascadePath $::w.sketchbar.constraints {Dimensional Radius};movePointer [xy $point];pause 120;exec xdotool click 1;pause 120
 check {[winfo exists $::w.inline.value]} {actual Radius tool opens shared CORE inline editor};controllerProof radius-editor
}
set rootCalls {};set aboutTexts {};set aboutShot 0
proc rootTrace {cmd args} {lappend ::rootCalls [dict create command $cmd phase [lindex $args end] time [clock microseconds]];write [file join $::output root-events.tcllist] $::rootCalls}
proc aboutWatch {} {
 foreach widget [guiWidgets .] {if {![winfo exists $widget] || [winfo toplevel $widget] ne $widget || [wm title $widget] ne {About Curve Workbench}} continue
  foreach child [guiWidgets $widget] {if {[winfo class $child] in {Label TLabel Message} && ![catch {$child cget -text} text]} {lappend ::aboutTexts $text}}
  if {!$::aboutShot} {set ::aboutShot 1;shot actual-about}
  foreach child [guiWidgets $widget] {if {[winfo class $child] in {Button TButton} && [$child cget -text] eq {OK}} {exec xdotool mousemove [expr {[winfo rootx $child]+[winfo width $child]/2}] [expr {[winfo rooty $child]+[winfo height $child]/2}] click 1;break}}
 };set ::aboutWatcher [after 80 aboutWatch]
}
proc marker {id} {return [::GX::Native2D::core direction_marker $::scene [native $id]]}
proc rootFlipClick {} {
 set items [$::canvas find withtag direction_flip];check {[llength $items]==1} {actual Canvas root Flip command is visible}
 lassign [$::canvas bbox [lindex $items 0]] x0 y0 x1 y1;movePointer [list [expr {($x0+$x1)/2}] [expr {($y0+$y1)/2}]];exec xdotool click 1;pause 160
}
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P019 P019 final source smoke}}];wm geometry $w 1480x940+20+20;raise $w;pause 220
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 source [file join [file dirname [info script]] gui_helpers.tcl]
 menuChoose $w.toolbar.workspace {Workspace Configuration*};typeInto $w.coordinateConfiguration.viewport.content.field0.entry mm;typeInto $w.coordinateConfiguration.viewport.content.field1.entry mm;click $w.coordinateConfiguration.actions.apply
 check {$::GX::UiField::formStatus($w.coordinateConfiguration) eq {Applied.}} {explicit homogeneous scientific frame configured};click $w.coordinateConfiguration.actions.close
 set host [::GX::CurveWorkbench::_cadCanvas $w];set cad [$host context];set tools [$host advanced];trace add execution $tools {enter leave} sharedTrace
 set module [file join $catalog plugins modules viewer.curve_workbench];set rows [split [string trim [read [set ch [open [file join $module SHA256SUMS]]]]] \n];close $ch
 check {[llength $rows]==59 && [read [set ch [open [file join $module SHA256SUMS]]]] eq [read [set ch2 [open [file join $module SHA256SUMS.txt]]]]} {all59 current module files have matching checksum manifests};close $ch;close $ch2
 set oldpwd [pwd];cd $module;try {set sums [exec sha256sum -c SHA256SUMS]} finally {cd $oldpwd};write [file join $output module-checksums.txt] $sums
 check {[::GX::moduleField viewer.curve_workbench version {}] eq {2.21.18} && $::GX::CurveWorkbench::version eq {2.21.18}} {actual loaded module and runtime version are2.21.18}
 set mixin [lindex [exec sha256sum [file join $catalog core tcl native2d_cad_tools_constraints_v1.tcl]] 0];check {$mixin eq {cfcdb54b907be4045e632a0717b315d01f4b8b63759392ad4783aed990307a25}} {latest verified shared relationship projection owner is loaded}
 foreach owner {_unfix _directionToggle _directionFlip _directionApply} {trace add execution ::GX::CurveWorkbench::$owner {enter leave} rootTrace}
 set view [::GX::Native2D::core view_requested $scene];lset view 6 {-2 -3 14 10};::GX::Native2D::core view $scene $view;::GX::CurveWorkbench::_draw $w
 set bezier [createByCanvas cubic_bezier {Cubic Bézier} {{0 0} {1 3} {3 -1} {4 1}} auto]
 set circle [numericPrimitive {Final Fixed} circle {{9 1}}];selectMode {Select Entire Curve / Path};selectCurve $circle;cascadePath $w.sketchbar.constraints {Fixing Fix}
 set fixed [latestRelationship];check {[dict get [relationship $fixed] kind] eq {fixed}} {actual Fixed relationship prepared for Unfix}
 set exactCircle [$cad object definition [native $circle]];cascadePath $w.sketchbar.constraints {Fixing Unfix}
 set receipt [dict get [$tools state] receipt];check {![dict exists $::GX::CurveWorkbench::st($w,constraints) $fixed] && [dict get $receipt operation] eq {constraint.remove} && [dict get $receipt status] eq {committed}} {actual Unfix calls shared CORE constraint.remove}
 click $w.toolbar.undo;check {[dict exists $::GX::CurveWorkbench::st($w,constraints) $fixed] && [$cad object definition [native $circle]] eq $exactCircle} {Unfix Undo restores valid native Fixed without geometry drift};click $w.toolbar.redo;check {![dict exists $::GX::CurveWorkbench::st($w,constraints) $fixed]} {Unfix Redo removes only relationship}
 click $w.toolbar.undo;set modalBefore [llength $modalEvents];cascadePath $w.sketchbar.constraints {Fixing Unfix}
 check {[llength $modalEvents]>$modalBefore && ![dict exists $::GX::CurveWorkbench::st($w,constraints) $fixed] && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==[dict get [::GX::scientificHistoryViewerStatus $w] count]} {actual older-Undo Unfix requests public History branch before shared mutation}
 selectCurve $bezier;exec xdotool key Escape;pause 80
 menuChoose $w.toolbar.settings {Direction presentation*};check {[winfo exists $w.direction.f0.entry]} {existing Settings opens actual root Direction presentation dialog}
 if {!$::GX::CurveWorkbench::st($w,direction.visible)} {click $w.direction.f0.entry};typeInto $w.direction.f2.entry 70;typeInto $w.direction.f4.entry 36
 set before [marker $bezier];set exactBezier [$cad object definition [native $bezier]];click $w.direction.actions.apply;set applied [marker $bezier];click $w.direction.actions.close
 check {[dict get $applied visible] && abs([dict get $applied fraction]-.7)<1e-10 && [dict get $applied length_px]==36 && [$cad object definition [native $bezier]] eq $exactBezier} {actual root Apply sets scientific-owner direction properties without modifying Bezier definition}
 set receipt [dict get [$tools state] receipt];check {[dict get $receipt operation] eq {direction.properties} && [dict get $receipt status] eq {committed}} {root Direction dialog Apply uses shared CORE properties receipt}
 click $w.toolbar.undo;check {[marker $bezier] eq $before} {root Apply Undo restores exact prior direction style};click $w.toolbar.redo;check {[marker $bezier] eq $applied} {root Apply Redo restores requested style}
 set beforeFlip [marker $bezier];rootFlipClick;set flipped [marker $bezier];check {[dict get $flipped forward]!=[dict get $beforeFlip forward]} {actual Canvas Flip calls root direction operation};click $w.toolbar.undo;check {[marker $bezier] eq $beforeFlip} {root Flip Undo restores intended direction};click $w.toolbar.redo;check {[marker $bezier] eq $flipped} {root Flip Redo restores intended direction}
 click $w.toolbar.undo;set modalBefore [llength $modalEvents];rootFlipClick
 check {[llength $modalEvents]>$modalBefore && [dict get [marker $bezier] forward]==[dict get $flipped forward]} {actual older-Undo root Flip branches through public History before shared mutation}
 check {![winfo ismapped $w.right.display.direction]} {legacy root visibility checkbox is intentionally unmapped by accepted Viewport layout}
 set beforeToggle [marker $bezier];$w.right.display.direction invoke;pause 120
 check {[dict get [marker $bezier] visible]!=[dict get $beforeToggle visible]} {supplementary hidden-widget command invokes root Toggle shared properties compatibility}
 click $w.toolbar.undo;check {[marker $bezier] eq $beforeToggle} {supplementary Toggle Undo restores exact direction state};click $w.toolbar.redo;click $w.toolbar.undo
 selectCurve $bezier;selectMode {Local Geometry*};set before [$cad object definition [native $bezier]];set handles [$cad object controls [native $bezier]];set start [xy [dict get [lindex $handles 1] point]]
 movePointer $start;exec xdotool mousedown 1;pause 60;movePointer [list [expr {[lindex $start 0]+18}] [expr {[lindex $start 1]-14}]];pause 120
 set proposed [dict get [$host state] gesture proposal definition];check {$proposed ne $before && [$cad object definition [native $bezier]] eq $before} {actual Bezier defining-control preview is shared and leaves authoritative definition unchanged}
 exec xdotool mouseup 1;pause 150;check {[$cad object definition [native $bezier]] eq $proposed} {Bezier release commits exact admitted shared control proposal}
 click $w.toolbar.undo;check {[$cad object definition [native $bezier]] eq $before} {Bezier control Undo restores exact definition};click $w.toolbar.redo;check {[$cad object definition [native $bezier]] eq $proposed} {Bezier control Redo restores exact edited definition}
 set aboutWatcher [after 80 aboutWatch];menuChoose $w.toolbar.help {About Curve Workbench*};check {{Curve Workbench 2.21.18} in $aboutTexts} {actual About GUI reports installed2.21.18 version}
 check {![dict get [$host state] active] && ![::GX::Native2D::core drag_active $scene] && [$host targetsMutable] && $errors eq {}} {final current source has no active native transaction or background callback error}
 write [file join $output final-receipt.tcldict] [dict create version $::GX::CurveWorkbench::version mixin $mixin about $aboutTexts roots $rootCalls history [::GX::scientificHistoryViewerStatus $w] shared [$tools state] host [$host state] bezier [$cad object definition [native $bezier]]]
 shot final-current;movePointer [xy {2 1}];exec xdotool click 4;exec xdotool key alt+F4;pause 500
 check {![winfo exists $w] && ![llength [info commands $host]] && $errors eq {}} {normal current-source closure disposes pending redraw and shared resources}
 write [file join $output RESULT.txt] {PASS: actual current root Direction Apply/Flip/Unfix branch UndoRedo, Bezier edit, version About checksums and lifecycle; hidden Toggle explicitly API-level only.}
} on error {message options} {puts stderr [dict get $options -errorinfo];if {$w ne {}&&[winfo exists $w]} {catch {shot failure}};set exitStatus 1} finally {
 catch {after cancel $aboutWatcher};foreach owner {_unfix _directionToggle _directionFlip _directionApply} {catch {trace remove execution ::GX::CurveWorkbench::$owner {enter leave} rootTrace}};
 catch {trace remove execution $tools {enter leave} sharedTrace};catch {after cancel $branchWatcher};write [file join $output errors.tcllist] $errors;write [file join $output input.tcllist] $inputTrace
 if {$w ne {}&&[winfo exists $w]} {catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
