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


::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
set session [::GX::createNewSession p019_constrained_drag {} 0]
::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
package require Tk;wm withdraw .
set branchWatcher [after 70 branchWatch]
set wmPids [exec xfwm4 --replace --compositor=off --sm-client-disable >[file join $output wm.log] 2>@1 &];pause 300
set w {};set events {};set traceBusy 0;set invalidActivates {};set expectedRejections {};set expectActivate 0;set traces {};set constraints {};set paths {};set pathControls {}
proc stackFrames {} {set out {};set depth [info frame];for {set n 1} {$n<$depth} {incr n} {set frame [info frame -$n];dict set frame cmd [string range [::GX::datasetPublicationV2DictDefault $frame cmd {}] 0 4000];lappend out $frame};return $out}
proc stateSnapshot {} {
 set out {};if {![info exists ::w] || $::w eq {} || ![winfo exists $::w]} {return $out}
 foreach key {document historyRestoring importTransaction cadTool tool canvasTool selectedRelationship hoverRelationship cadTarget cadDrag handleDrag drag pointDrag semanticPointDrag annotationDrag selectionShape cadSelectionPending coordinates status} {if {[info exists ::GX::CurveWorkbench::st($::w,$key)]} {set val $::GX::CurveWorkbench::st($::w,$key);if {$key in {cadDrag handleDrag pointDrag semanticPointDrag}} {set val [expr {$val eq {}?{}:[dict remove $val before widgets]}]};dict set out $key $val}}
 if {[info exists ::scene]} {catch {dict set out native_drag [::GX::Native2D::core drag_active $::scene]}}
 if {[info exists ::GX::CurveWorkbench::st($::w,cadCanvas)]} {set h $::GX::CurveWorkbench::st($::w,cadCanvas);if {[llength [info commands $h]]} {catch {set hs [$h state];set g [dict get $hs gesture];if {[dict exists $g context]} {dict unset g context};dict set hs gesture $g;dict set out host $hs};catch {dict set out cad [[$h context] state]}}}
 return $out
}
proc diagnostic {name {extra {}}} {
 if {$::traceBusy} return
 set ::traceBusy 1
 try {set row [dict create time_us [clock microseconds] name $name state [stateSnapshot] extra $extra];lappend ::events $row;write [file join $::output events.tcllist] $::events} finally {set ::traceBusy 0}
}
proc hostTrace {cmd args} {
 if {$::traceBusy} return
 set phase [lindex $args end];set op [lindex $cmd 1]
 if {$op ni {event activate cancel begin finish move}} return
 set extra [dict create phase $phase operation $op arguments [lrange $cmd 2 end]]
 if {$phase eq {leave}} {dict set extra code [lindex $args 0];dict set extra result [string range [lindex $args 1] 0 4000]}
 if {$op eq {activate}} {dict set extra errorstack [info errorstack];dict set extra stack [stackFrames];if {$phase eq {leave} && [lindex $args 0]!=0} {if {$::expectActivate} {lappend ::expectedRejections $extra;write [file join $::output expected-rejections.tcllist] $::expectedRejections} else {lappend ::invalidActivates $extra;write [file join $::output invalid-activates.tcllist] $::invalidActivates}}}
 diagnostic host:$op:$phase $extra
}
proc cadTrace {cmd args} {
 if {$::traceBusy || [lindex $cmd 1] ne {gesture}} return
 diagnostic cad:[lindex $cmd 2]:[lindex $args end] [dict create arguments [lrange $cmd 3 end] return [expr {[lindex $args end] eq {leave}?[lrange $args 0 1]:{}}]]
}
proc procedureTrace {name cmd args} {
 if {$::traceBusy} return
 diagnostic $name:[lindex $args end] [dict create command [string range $cmd 0 4000] return [expr {[lindex $args end] eq {leave}?[lrange $args 0 1]:{}}]]
}
try {
 set w [::GX::viewerOpen viewer.curve_workbench curve_workbench {workspace_id new workspace_name {P019 dense compatible constrained drag}}]
 wm geometry $w 1480x940+20+20;raise $w;pause 220
 set canvas $w.right.viewport.canvas;set scene $::GX::CurveWorkbench::st($w,scene)
 source [file join [file dirname [info script]] gui_helpers.tcl]
 menuChoose $w.toolbar.workspace {Workspace Configuration*}
 typeInto $w.coordinateConfiguration.viewport.content.field0.entry mm;typeInto $w.coordinateConfiguration.viewport.content.field1.entry mm
 click $w.coordinateConfiguration.actions.apply;check {$::GX::UiField::formStatus($w.coordinateConfiguration) eq {Applied.}} {explicit homogeneous millimetre frame established};click $w.coordinateConfiguration.actions.close
 proc selectMany {values} {
  selectCurve [lindex $values 0];set tree $::w.leftScroll.viewport.content.curves
  foreach id [lrange $values 1 end] {$tree see $id;pause 45;lassign [$tree bbox $id name] x y width height;exec xdotool keydown Control_L mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1 keyup Control_L;pause 80}
 }
 foreach controls {{{0 0} {2 0} {2 2} {4 2} {4 4} {6 4}} {{6 4} {8 4} {8 6} {10 6} {10 8} {12 8}} {{0 -4} {2 -4} {2 -2} {4 -2} {4 0} {6 0}}} {
  set members {};set n 0;foreach a [lrange $controls 0 end-1] b [lrange $controls 1 end] {lappend members [fixture "Constituent[incr n]" line [list $a $b]]}
  selectMany $members;menuChoose $w.sketchbar.modify {Join Path*};click $w.pathJoin.actions.apply
  check {$::GX::UiField::formStatus($w.pathJoin) eq {Applied.}} {real reviewed Join Path creates exact connected retained constituents}
  click $w.pathJoin.actions.close;set path $::GX::CurveWorkbench::st($w,active);lappend paths $path;dict set pathControls $path $controls
 }
 set cad [::GX::CurveWorkbench::_cadController $w]
 proc installOption {references kind} {
  set options [$::cad relationship options $references]
  if {![dict exists $options $kind]} {error "Native relation $kind unsupported for references $references; available [dict keys $options]"}
  set spec [dict get $options $kind]
  set logical [::GX::CurveWorkbench::_constraintCommit $::w {} $spec]
  set receipt [$::cad relationship get [dict get $::GX::CurveWorkbench::st($::w,constraints) $logical native]]
  check {[dict get $receipt valid] && ![dict get $receipt driven]} "satisfied native $kind relationship installed"
  lappend ::constraints $receipt;return $logical
 }
 ::GX::CurveWorkbench::_fit $w;pause 100
 proc referenceAt {object point} {
  set ref [$::cad selection pick [list $object] [::GX::Native2D::core device $::scene $point] 5 local]
  if {$ref eq {}} {error "No authoritative Native reference at $point for $object"};return $ref
 }
 set segmentRefs {}
 foreach p $paths {
  set object [native $p];set coords [dict get $pathControls $p];set refs {};set ordinal 0
  foreach start [lrange $coords 0 end-1] end [lrange $coords 1 end] {
   set point [lmap a $start b $end {expr {($a+$b)/2.0}}];set ref [referenceAt $object $point]
   check {[dict get $ref semantic_kind] eq {segment}} {public Native pick returns actual constituent segment reference}
   lappend refs $ref;installOption [list $ref] [expr {$ordinal%2?{vertical}:{horizontal}}];incr ordinal
  }
  dict set segmentRefs $p $refs
  installOption [list [lindex $refs 0] [lindex $refs 2]] parallel
 }
 set a [lindex $paths 0];set b [lindex $paths 1]
 set aLast [referenceAt [native $a] {6 4}];set bFirst [referenceAt [native $b] {6 4}]
 check {[dict get $aLast semantic_kind] eq {control} && [dict get $bFirst semantic_kind] eq {control}} {actual shared endpoint controls resolved without sampled proxies}
 installOption [list $aLast $bFirst] coincident
 installOption [list [lindex [dict get $segmentRefs $a] 0] [lindex [dict get $segmentRefs $b] 0]] parallel
 check {[llength $constraints]>=20} {dense compatible intra-Path and inter-Path relationships installed}
 write [file join $output fixture-constraints.tcllist] $constraints
 selectMany $paths;::GX::CurveWorkbench::_fit $w;pause 160;menuChoose $w.sketchbar.modify Translate
 set host $::GX::CurveWorkbench::st($w,cadCanvas);set cad [$host context]
 trace add execution $host {enter leave} hostTrace;trace add execution $cad {enter leave} cadTrace
 foreach name {_mouseDown _mouseMove _mouseUp _middlePan _coordinates _coordinates_sketch054_base _draw _cadSelectNative _cadGestureBegin _cadCanvasBegin _cadCanvasAdmit _cadCanvasCommitted _cadCanvasCancelled _treeSelect _objectListClick _safe _notice} {set proc ::GX::CurveWorkbench::$name;if {[llength [info commands $proc]]} {set callback [list procedureTrace $name];trace add execution $proc {enter leave} $callback;lappend traces [list $proc $callback]}}
 diagnostic fixture_ready
 shot constrained-ready
 set before {};foreach p $paths {dict set before $p [curvePoints $p]}
 set beforeDefinitions {};foreach p $paths {dict set beforeDefinitions $p [dict create native [native $p] record [::GX::CurveWorkbench::_record $w $p] definition [::GX::Native2D::core sketch_definition $scene [native $p]]]}
 set historyBefore [::GX::scientificHistoryViewerStatus $w]
 set start {};foreach item [::GX::Native2D::core render_gizmo $scene] {if {[dict get $item handle] eq {x} && [dict get $item kind] eq {box}} {set start [dict get $item a];break}}
 check {$start ne {} && [::GX::Native2D::core gizmo_hit $scene $start 5] eq {x}} {existing dense constrained translation handle is hit}
 movePointer $start;exec xdotool mousedown 1;pause 50
 foreach dx {7 14 21 28} {movePointer [list [expr {[lindex $start 0]+$dx}] [lindex $start 1]];pause 80}
 exec xdotool mouseup 1;pause 160;diagnostic constrained_translation_finished
 set translated {};foreach p $paths {dict set translated $p [curvePoints $p]}
 write [file join $output geometry.tcldict] [dict create before $before translated $translated]
 check {$before ne $translated && ![dict get [$host state] active] && ![::GX::Native2D::core drag_active $scene] && [dict get [::GX::scientificHistoryViewerStatus $w] count]==[dict get $historyBefore count]+1} {compatible constrained native translation commits one History operation and releases gesture}
 set afterRelations [$cad relationship list];foreach relationship $afterRelations {check {[dict get $relationship valid]} {translated dense native constraint remains valid}}
 write [file join $output translated-constraints.tcllist] $afterRelations
 set selectedBeforePan [lsort [::GX::CurveWorkbench::_cadSelected $w]]
 set countBeforePan [dict get [::GX::scientificHistoryViewerStatus $w] count]
 # Keep Translate active. The existing native middle-button pan must coexist.
 set pointer [list [expr {int([winfo width $canvas]*.64)}] [expr {int([winfo height $canvas]*.57)}]]
 movePointer $pointer;exec xdotool mousedown 2;pause 55;diagnostic middle_pan_started
 check {![$host targetsMutable] && ![dict get [$host state] target_flags_mutable]} {public host rejects target mutation for active Pan despite no scientific drag}
 set expectActivate 1;set rejected [catch {$host activate [lmap p $paths {native $p}]} message rejectionOptions];set expectActivate 0
 check {$rejected && $message eq {Finish the native drag before changing CAD target flags} && [dict get [$host state] active]} {explicit protected activate is still rejected during active Pan without clearing it}
 foreach delta {{8 4} {16 9} {24 14} {32 18}} {lassign $delta dx dy;movePointer [list [expr {[lindex $pointer 0]+$dx}] [expr {[lindex $pointer 1]+$dy}]];pause 90}
 diagnostic middle_pan_before_release;shot constrained-middle-pan
 exec xdotool mouseup 2;pause 200;diagnostic middle_pan_finished
 set final {};foreach p $paths {dict set final $p [curvePoints $p]}
 write [file join $output result.tcldict] [dict create invalid_activates $invalidActivates errors $errors geometry_unchanged_by_pan [expr {$final eq $translated}] state [stateSnapshot] history [::GX::scientificHistoryViewerStatus $w]]
 check {$invalidActivates eq {} && $errors eq {}} {no illegal target-flag reactivation during actual constrained drag or middle pan}
 check {$final eq $translated && ![dict get [$host state] active] && ![::GX::Native2D::core drag_active $scene] && [$host targetsMutable] && [lsort [::GX::CurveWorkbench::_cadSelected $w]] eq $selectedBeforePan && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$countBeforePan} {middle pan preserves geometry selection and History and releases every owner}
 write [file join $output draft-document-before-undo.tcldict] [dict create document $::GX::CurveWorkbench::st($w,document) history [::GX::scientificHistoryViewerStatus $w] state [stateSnapshot]]
 check {$::GX::CurveWorkbench::st($w,document) eq {}} {test retains actual unsaved draft before History restore}
 click $w.toolbar.undo;set undone {};foreach p $paths {dict set undone $p [curvePoints $p]}
 set undoDefinitions {};foreach p $paths {dict set undoDefinitions $p [dict create native [native $p] record [::GX::CurveWorkbench::_record $w $p] definition [::GX::Native2D::core sketch_definition $scene [native $p]]]}
 write [file join $output undo-diagnostic.tcldict] [dict create before $before translated $translated undone $undone definitions_before $beforeDefinitions definitions_after $undoDefinitions history_before $historyBefore history_after [::GX::scientificHistoryViewerStatus $w] selected_before $selectedBeforePan selected_after [::GX::CurveWorkbench::_cadSelected $w] scene $scene view [::GX::Native2D::core view_requested $scene] state [stateSnapshot]]
 check {$undone eq $before} {actual constrained translation Undo restores all exact scientific coordinates}
 click $w.toolbar.redo;set redone {};foreach p $paths {dict set redone $p [curvePoints $p]}
 check {$redone eq $translated} {actual constrained translation Redo restores all exact scientific coordinates}
 set cad [$host context];menuChoose $w.sketchbar.modify Translate
 set cancelStart {};foreach item [::GX::Native2D::core render_gizmo $scene] {if {[dict get $item handle] eq {x} && [dict get $item kind] eq {box}} {set cancelStart [dict get $item a];break}}
 check {$cancelStart ne {}} {constrained Translate can start again after Pan and UndoRedo}
 set cancelCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
 movePointer $cancelStart;exec xdotool mousedown 1;pause 50;movePointer [list [expr {[lindex $cancelStart 0]+17}] [lindex $cancelStart 1]];pause 90
 set preview {};foreach p $paths {dict set preview $p [curvePoints $p]}
 check {$preview ne $translated && [dict get [$host state] active]} {cancel scenario contains a genuine changed constrained Native preview}
 exec xdotool key Escape;pause 60;exec xdotool mouseup 1;pause 150
 set cancelled {};foreach p $paths {dict set cancelled $p [curvePoints $p]}
 check {$cancelled eq $translated && ![dict get [$host state] active] && ![::GX::Native2D::core drag_active $scene] && [$host targetsMutable] && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$cancelCount} {actual Escape restores dense geometry History and all native host transaction owners}
 set finalRelations [$cad relationship list];foreach relationship $finalRelations {check {[dict get $relationship valid]} {constraint remains valid after UndoRedo and cancellation}}
 check {$::GX::CurveWorkbench::st($w,document) eq {}} {UndoRedo and cancellation do not implicitly materialize draft Document}
 write [file join $output final-regression.tcldict] [dict create expected_rejections $expectedRejections unexpected_rejections $invalidActivates initial $before translated $translated undone $undone redone $redone cancelled $cancelled constraints $finalRelations selected [::GX::CurveWorkbench::_cadSelected $w] history [::GX::scientificHistoryViewerStatus $w] state [stateSnapshot]]
 check {$invalidActivates eq {} && $errors eq {}} {all actual constrained editing and Pan callbacks remain error-free apart from explicit guard test}
 write [file join $output RESULT.txt] {PASS: dense compatible constrained translation and Translate-mode middle pan have coherent lifecycle.}
} on error {message options} {
 puts stderr [dict get $options -errorinfo];catch {diagnostic test_failure [dict create message $message options $options]};if {$w ne {} && [winfo exists $w]} {catch {shot failure}};set exitStatus 1
} finally {
 catch {trace remove execution $host {enter leave} hostTrace};catch {trace remove execution $cad {enter leave} cadTrace}
 foreach pair $traces {lassign $pair proc callback;catch {trace remove execution $proc {enter leave} $callback}}
 catch {after cancel $branchWatcher};write [file join $output errors.tcllist] $errors;write [file join $output input.tcllist] $inputTrace
 if {$w ne {} && [winfo exists $w]} {catch {exec xdotool mouseup 1 mouseup 2};catch {$host cancel};catch {::GX::CurveWorkbench::_close $w}};catch {destroy .};foreach pid $wmPids {catch {exec kill -TERM -- $pid}}
}
if {[info exists exitStatus]} {exit $exitStatus};exit 0
