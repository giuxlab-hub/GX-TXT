# P019 focused current-source Dataset, heterogeneous-axis and persistence GUI verification; private data only.
# Adapted inspected P018 validation paths; no historical deployment/source replacement.
lassign $argv framework output
set mode patched
if {[file exists $output]} {error {Fresh output required}}
set framework [file normalize $framework];file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1;set argv0 __p019_stress__
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
    see $widget
    exec xdotool mousemove [expr {[winfo rootx $widget]+[winfo width $widget]-8}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1
    pause
    set popup [::GX::_uiFieldSelectorPanel $widget [winfo toplevel $widget]];set list $popup.options
    if {![winfo exists $popup] || ![winfo ismapped $popup]} {set popup [::ttk::combobox::PopdownWindow $widget];set list $popup.f.l}
    check {[winfo ismapped $popup]} {actual unit-selector popup opens}
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
set session [::GX::createNewSession p019_stress {} 0]
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
package require Tk;wm withdraw .
set branchWatcher [after 70 branchWatch]
set wmPids [exec xfwm4 --replace --compositor=off --sm-client-disable >[file join $output wm.log] 2>@1 &];pause 300
set w {};set timings {};set snapshots {};set ids {};set segmentCount 0
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P019 Heterogeneous time-voltage}}]
 wm geometry $w 1480x940+20+20;raise $w;pause 200
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 set host [::GX::CurveWorkbench::_cadCanvas $w];set tools [$host advanced]

 source [file join [file dirname [info script]] gui_helpers.tcl]
 proc near {before after {tol 1e-8}} {if {[llength $before]!=[llength $after]} {return 0};set d 0;foreach a $before b $after {foreach x $a y $b {set d [expr {max($d,abs($x-$y))}]}};return [expr {$d<$tol}]}
 proc sourcePage {rec} {set token [::GX::curveSourceOpen $::session [dict get $rec source_request]];try {return [::GX::curveSourcePage $token 0 1000]} finally {::GX::curveSourceClose $token}}
 proc cascadeChoose {button parent label} {
  click $button;set menu [$button cget -menu];set i [menuIndex $menu $parent];set sub [$menu entrycget $i -menu]
  exec xdotool mousemove [expr {[winfo rootx $menu]+70}] [expr {[winfo rooty $menu]+[$menu yposition $i]+10}];pause 400;popupEntry $sub $label
 }
 menuChoose $w.toolbar.workspace {Workspace Configuration*}
 typeInto $w.coordinateConfiguration.viewport.content.field0.entry ms
 typeInto $w.coordinateConfiguration.viewport.content.field1.entry mV
 click $w.coordinateConfiguration.viewport.content.field2.entry
 click $w.coordinateConfiguration.actions.apply
 check {$::GX::UiField::formStatus($w.coordinateConfiguration) eq {Applied.}} {actual empty Workspace Configuration admits explicit heterogeneous ms and mV axes}
 click $w.coordinateConfiguration.actions.close
 set xs {};set ys {};for {set j 0} {$j<32} {incr j} {lappend xs [expr {500.0*$j}];lappend ys [expr {100.0*sin(.4*$j)}]}
 ::GX::datasetPublicationV2PublishSeries $session math.numeric [dict create dataset_id time_voltage contract table.generic storage csv x_values $xs y_values $ys x_variable {variable_id time_ms canonical time_ms unit ms} y_variable {variable_id voltage_mV canonical voltage_mV unit mV}]
 set sourceBefore [::GX::sessionInspectionDatasetPayload time_voltage]
 write [file join $output source-baseline.tcldict] $sourceBefore
 set ::GX::CurveWorkbench::st($w,preferredDataset) time_voltage
 click $w.toolbar.add
 set label {};dict for {text did} $::GX::CurveWorkbench::st($w,source.datasetMap) {if {$did eq {time_voltage}} {set label $text}}
 stockChoice $w.source.dataset $label
 foreach {axis vid} {x time_ms y voltage_mV} {set label {};dict for {text actual} $::GX::CurveWorkbench::st($w,source.varMap) {if {$actual eq $vid} {set label $text}};stockChoice $w.source.$axis $label}
 check {[::GX::CurveWorkbench::_sourceId $w x] eq {time_ms} && [::GX::CurveWorkbench::_sourceId $w y] eq {voltage_mV}} {actual selectors retain scientific X and Y variable identities}
 set guardEvents {};set expectedModal 0
 proc admissionTrace {cmd args} {set event [dict create time [clock microseconds] phase [lindex $args end] command $cmd busy $::GX::CurveWorkbench::st($::w,publishBusy) document $::GX::CurveWorkbench::st($::w,document) token $::GX::CurveWorkbench::st($::w,token)];if {[lindex $args end] eq {leave}} {dict set event code [lindex $args 0];dict set event result [lindex $args 1]};lappend ::guardEvents $event;write [file join $::output guard-events.tcllist] $::guardEvents}
 proc expectedModalWatch {} {
  foreach widget [guiWidgets .] {if {![winfo exists $widget] || ![winfo viewable $widget] || [winfo class $widget] ni {Label TLabel Message}} continue;if {[catch {$widget cget -text} text] || $text ne {CAD domain lifetime is stale or unavailable}} continue
   set top [winfo toplevel $widget];set ::expectedModal 1;shot actual-source-admission-error
   foreach b [guiWidgets $top] {if {[winfo class $b] in {Button TButton} && [$b cget -text] eq {OK}} {exec xdotool mousemove [expr {[winfo rootx $b]+[winfo width $b]/2}] [expr {[winfo rooty $b]+[winfo height $b]/2}] click 1;break}}
  };set ::modalWatcher [after 80 expectedModalWatch]
 }
 trace add execution ::GX::CurveWorkbench::_cadCanvasGuard {enter leave} admissionTrace;set modalWatcher [after 80 expectedModalWatch]
 click $w.source.buttons.add;pause 100
 set busyDenied 0;foreach event $guardEvents {if {[dict get $event phase] eq {leave} && [dict get $event busy] && [dict get $event result] eq {0}} {set busyDenied 1}}
 check {$expectedModal && $busyDenied} {actual Source Add redraw is rejected by shared guard solely during existing publication busy scope}
 write [file join $output RESULT.txt] {REPRODUCED: actual GUI Source Add calls readonly relationship presentation while publication busy; old advanced accessor incorrectly applies edit admission.}
} on error {message options} {puts stderr [dict get $options -errorinfo];if {$w ne {} && [winfo exists $w]} {catch {shot failure}};set exitStatus 1} finally {
 catch {after cancel $modalWatcher};catch {trace remove execution ::GX::CurveWorkbench::_cadCanvasGuard {enter leave} admissionTrace};
 catch {after cancel $branchWatcher}
 write [file join $output errors.tcllist] $errors
 write [file join $output input.tcllist] $inputTrace
 if {$w ne {} && [winfo exists $w]} {catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
