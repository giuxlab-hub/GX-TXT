# P019 public CORE advanced CAD consumer; fixture/validation only.
lassign $argv framework output variant
if {[file exists $output]} {error {Fresh isolated output required}}
file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __p019_independent_advanced__
set loadedPins {}
set pinPaths [concat {gxtxt_pipeline.tcl core/native2d/bin/gx2dtcl.so core/history/libgxtxt_history.so} [lmap path [glob -nocomplain [file join $framework core tcl native2d_cad*.tcl]] {file join core tcl [file tail $path]}]]
foreach path $pinPaths {dict set loadedPins $path [lindex [exec sha256sum [file join $framework $path]] 0]}
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
foreach path [dict keys $loadedPins] {if {[lindex [exec sha256sum [file join $framework $path]] 0] ne [dict get $loadedPins $path]} {error {Source changed while loading public CORE consumer}}}
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
set session [::GX::createNewSession p019_independent_advanced {} 0]
package require Tk
wm geometry . 1500x1000+10+10;wm title . {P019 independent public CORE advanced CAD consumer}
namespace eval ::P019 {
 variable out $::output;variable session $::session
 variable token [::GX::interactiveDocumentSessionToken]
 variable scene {};variable host {};variable cad {};variable a {};variable c {};variable history {}
 variable objects {};variable relations {};variable nextObject 0;variable nextRelation 0
 variable before {};variable checks {};variable inputs {};variable errors {};variable opErrors {};variable receipts {}
 variable status {Choose a native construction or interaction tool. Units: native mm; dimension editor cm.}
 variable activeRelation {};variable lastReceipt {};variable lastOperation {};variable lastObject {};variable pendingTopology {}
 variable advancedCommits {};variable editor {};variable dimensionProposal {};variable domainGeneration 1;variable expectedGeneration 1
}
proc ::P019::write {name data} {variable out;set f [open [file join $out $name] w];puts -nonewline $f $data;close $f}
proc ::P019::pause {{ms 90}} {set ::P019::waiting 1;after $ms {set ::P019::waiting 0};vwait ::P019::waiting}
proc ::P019::check {test label} {if {![uplevel 1 [list expr $test]]} {error "FAIL: $label"};lappend ::P019::checks $label;write checks.tcllist $::P019::checks;puts "PASS: $label";flush stdout}
proc ::P019::xt {args} {lappend ::P019::inputs [list [clock microseconds] {*}$args];write input.tcllist $::P019::inputs;exec xdotool {*}$args}
proc ::P019::at {device} {variable c;lassign $device x y;xt mousemove [expr {[winfo rootx $c]+int(round($x))}] [expr {[winfo rooty $c]+int(round($y))}]}
proc ::P019::worldAt {world} {at [::GX::Native2D::core device $::P019::scene $world]}
proc ::P019::canvasClick {world} {worldAt $world;xt click 1;pause}
proc ::P019::click {widget} {check {[winfo viewable $widget]} "mapped independent control $widget";xt mousemove [expr {[winfo rootx $widget]+[winfo width $widget]/2}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1;pause}
proc ::P019::type {widget value} {click $widget;xt key Home shift+End BackSpace;xt type --clearmodifiers -- $value;pause 40}
proc ::P019::shot {name} {pause 120;exec timeout 8s import -silent -window root [file join $::P019::out $name.png]}
proc bgerror {m} {lappend ::P019::errors $m;::P019::write background-errors.tcllist $::P019::errors;puts stderr "BACKGROUND: $m"}
proc ::P019::safe {command} {if {[catch {uplevel #0 $command} m o]} {set ::P019::status $m;lappend ::P019::opErrors [dict create error $m options $o];write operation-errors.tcllist $::P019::opErrors;puts stderr "OPERATION REJECTED: $m"}}
proc ::P019::guard {event} {expr {$::P019::token eq [::GX::interactiveDocumentSessionToken] && $::P019::domainGeneration==$::P019::expectedGeneration && [dict get $event scene]==$::P019::scene}}
proc ::P019::historyGuard {} {expr {$::P019::token eq [::GX::interactiveDocumentSessionToken]}}
proc ::P019::scope {event} {set result {};foreach id [::GX::Native2D::core ids $::P019::scene] {if {$id ni [$::P019::host feedbackObjects]} {lappend result $id}};return $result}
proc ::P019::aliasFor {native} {dict for {alias id} $::P019::objects {if {$id==$native} {return $alias}};error {Unmapped native object in fixture scientific model}}
proc ::P019::capture {} {
 variable objects;variable relations;variable nextObject;variable nextRelation;variable cad;variable scene;variable host
 set nativeIds [::GX::Native2D::core ids $scene];set current {};set records {}
 foreach id $nativeIds {
  if {$id in [$host feedbackObjects]} continue
  set alias {};dict for {key value} $objects {if {$value==$id} {set alias $key;break}}
  if {$alias eq {}} {set alias shape[incr nextObject]}
  dict set current $alias $id
  set style [$cad object style $id];dict set style selected 0
  dict set records $alias [dict create definition [$cad object definition $id] style $style direction [$cad object direction $id]]
 }
 set objects $current;set currentRelations {};set relationRecords {}
 foreach row [$cad relationship list] {
  set native [dict get $row id];set alias {};dict for {key value} $relations {if {$value==$native} {set alias $key;break}}
  if {$alias eq {}} {set alias relation[incr nextRelation]}
  dict set currentRelations $alias $native
  foreach key {a b axis} {if {[dict get $row $key]!=0} {dict set row $key [aliasFor [dict get $row $key]]}}
  dict unset row id
  # Native diagnostics are readouts, not captured scientific relationship fields.
  foreach key {valid geometry_supported measured_value residual angular_residual enforcement general_solver} {dict unset row $key}
  dict set relationRecords $alias $row
 }
 set relations $currentRelations
 return [dict create objects $records relationships $relationRecords pivot [::GX::Native2D::core pivot $scene]]
}
proc ::P019::restore {record} {
 variable host;variable a;variable cad;variable scene;variable objects;variable relations
 $a cancel history_restore;$cad gesture cancel;$cad selection apply {}
 foreach r [$cad relationship list] {$cad relationship remove [dict get $r id]}
 foreach id [::GX::Native2D::core ids $scene] {$cad object delete $id}
 set objects {};set relations {}
 dict for {alias row} [dict get $record objects] {
  set id [$cad object create [dict get $row definition] 257];dict set objects $alias $id
  $cad object style $id [dict get $row style]
  if {[dict get $row direction present]} {$cad object direction $id [dict get $row direction]}
 }
 dict for {alias row} [dict get $record relationships] {
  foreach key {a b axis} {if {[dict get $row $key] ne {0}} {dict set row $key [dict get $objects [dict get $row $key]]}}
  set r [$cad relationship create $row];dict set relations $alias [dict get $r id]
 }
 set p [dict get $record pivot];::GX::Native2D::core pivot $scene [dict get $p mode] {*}[expr {[dict get $p mode] eq {custom}?[list [dict get $p point]]:{}}]
 refreshObjects;$host refresh final
}
proc ::P019::projected {record} {write projected-history.tcldict $record}
proc ::P019::begin {event} {set ::P019::before [capture];return independent_operation}
proc ::P019::recordChange {operation} {
 set after [capture]
 if {$after ne $::P019::before} {set receipt [::GX::scientificHistoryViewerRecordOperation $::P019::history $operation];lappend ::P019::receipts $receipt;write history-receipts.tcllist $::P019::receipts}
 refreshObjects
}
proc ::P019::committed {event} {recordChange [dict get $event operation]}
proc ::P019::rollback {event} {restore $::P019::before}
proc ::P019::selected {event} {set ::P019::status {Native selection updated; scientific History unchanged.}}
proc ::P019::errorReceipt {event} {set ::P019::status [dict get $event error];lappend ::P019::opErrors $event;write operation-errors.tcllist $::P019::opErrors}
proc ::P019::advancedCallback {event} {
 set phase [dict get $event phase];set operation [dict get $event operation]
 switch -- $phase {
  admit {return 1}
  begin {return [begin $event]}
  committed {
   lappend ::P019::advancedCommits [dict create operation $operation phase $phase receipt [dict get $event receipt]]
   write advanced-commits.tcllist $::P019::advancedCommits
   set ::P019::lastReceipt [dict get $event receipt];set ::P019::lastOperation $operation
   # This consumer owns its presentation palette. Native geometry defaults white
   # for dark hosts; a white Canvas needs an explicit contrasting object style.
   foreach id [scope $event] {
    if {$id ni [dict values $::P019::objects]} {$::P019::cad object style $id {color {0.12 0.32 0.72 1} line_width 2 marker 0}}
   }
   recordChange $operation
   if {$operation eq {construction.create}} {set ::P019::lastObject [aliasFor [dict get $::P019::lastReceipt id]]}
   if {$operation in {topology.join_path topology.compound}} {set ::P019::lastObject [aliasFor $::P019::lastReceipt]}
   set ::P019::status "Accepted native $operation through shared controller."
  }
  rollback {rollback $event}
  rejected {set ::P019::status [dict get $event error]}
  cancelled {set ::P019::status {Advanced proposal cancelled; scientific state retained.}}
  preview {return {}}
  exclude {return {}}
 }
 return {}
}
proc ::P019::refreshObjects {} {
 variable objects;variable relations;variable cad
 foreach row [.property.objects children {}] {.property.objects delete $row}
 dict for {alias native} $objects {.property.objects insert {} end -id $alias -text $alias -values [list [dict get [$cad object definition $native] family] $native]}
 foreach row [.property.relationships children {}] {.property.relationships delete $row}
 dict for {alias native} $relations {set r [$cad relationship get $native];.property.relationships insert {} end -id $alias -text $alias -values [list [dict get $r kind] [dict get $r disabled]]}
}
proc ::P019::treeSelect {} {
 set members {};foreach alias [.property.objects selection] {if {[dict exists $::P019::objects $alias]} {lappend members [dict create kind object id [dict get $::P019::objects $alias] index 0]}}
 $::P019::host select $members;$::P019::host refresh final
}
proc ::P019::relationshipSelect {} {set ::P019::activeRelation [lindex [.property.relationships selection] 0]}
proc ::P019::choose {family} {
 if {$family eq {select}} {$::P019::host tool select} else {$::P019::host cancel tool_change;$::P019::host tool select;$::P019::a construction start $family}
 set ::P019::status "Tool: $family"
}
proc ::P019::navigate {direction} {$::P019::host cancel history_navigation;::GX::scientificHistoryViewerNavigate $::P019::history $direction;$::P019::host refresh final}
proc ::P019::prepareTopology {operation} {
 set ids [dict get [$::P019::cad selection snapshot] objects]
 set ::P019::pendingTopology [$::P019::a topology prepare $operation $ids {index 1 tolerance 1e-8}]
 set ::P019::status "Review $operation on [llength $ids] native objects. Apply is explicit."
}
proc ::P019::applyTopology {} {$::P019::a topology commit;$::P019::host refresh final}
proc ::P019::constraintStart {} {$::P019::a constraint start horizontal [dict get [$::P019::cad selection snapshot] references];set ::P019::status {Horizontal proposal uses actual native selected references.}}
proc ::P019::constraintApply {} {set state [$::P019::a constraint state];$::P019::a constraint apply 0 [dict get $state specification];$::P019::host refresh final}
proc ::P019::disableRelation {} {set id [dict get $::P019::relations $::P019::activeRelation];$::P019::a constraint manage $id disable;$::P019::host refresh final}
proc ::P019::dimensionStart {} {$::P019::a dimension start distance [dict get [$::P019::cad selection snapshot] references];set ::P019::status {Move over the Canvas to preview the native dimension, then open its external editor.}}
proc ::P019::dimensionEditor {{referenceOnly 0} {existing 0}} {
 variable a;variable scene;variable dimensionProposal;variable editor
 set dimensionProposal [$a dimension preview [::GX::Native2D::core device $scene {1.5 3.5}]]
 set spec [dict get $dimensionProposal specification]
 if {[winfo exists .property.editor]} {destroy .property.editor}
 set editor [$a dimension editor_create .property.editor [dict create specification $spec existing $existing annotation [dict get $dimensionProposal annotation] value [format %.6g [expr {[dict get $spec value]/10.0}]] title {Native length — display cm} message {Existing CORE Unit Registry converts display cm to native mm.} native_unit mm display_unit cm reference_only $referenceOnly width 285]]
 pack .property.editor -side bottom -fill x -pady 8
}
proc ::P019::native {alias} {dict get $::P019::objects $alias}
proc ::P019::family {alias} {dict get [$::P019::cad object definition [native $alias]] family}
proc ::P019::selectObject {alias {add 0}} {
 .property.objects see $alias;pause 30;lassign [.property.objects bbox $alias #0] x y width height
 if {$add} {xt keydown Control_L}
 xt mousemove [expr {[winfo rootx .property.objects]+$x+30}] [expr {[winfo rooty .property.objects]+$y+$height/2}] click 1
 if {$add} {xt keyup Control_L};pause
}
proc ::P019::selectRelation {alias} {
 .property.relationships see $alias;pause 30;lassign [.property.relationships bbox $alias #0] x y width height
 xt mousemove [expr {[winfo rootx .property.relationships]+$x+25}] [expr {[winfo rooty .property.relationships]+$y+$height/2}] click 1;pause
}
proc ::P019::construct {family points {finish 0}} {
 click .tools.$family
 foreach point $points {canvasClick $point}
 if {$finish} {
  write focus-before-return.tcldict [dict create family $family focus [focus] canvas $::P019::c state [$::P019::a state]]
  check {[focus] eq $::P019::c} {actual advanced Canvas input owns keyboard focus before Return}
  xt key Return;pause 120
 }
 set alias $::P019::lastObject
 check {[family $alias] eq $family} "real GUI constructs retained $family"
 return $alias
}
::GX::native2DEnsure
set ::P019::scene [::GX::Native2D::core scene]
::GX::Native2D::core pivot $::P019::scene custom {0 0}
::GX::Native2D::core view $::P019::scene {1100 850 60 20 20 50 {-1 -6 17 12}}
frame .tools;pack .tools -side top -fill x
frame .actions;pack .actions -side top -fill x
frame .property -width 300;pack .property -side right -fill y
frame .embed;pack .embed -side left -fill both -expand 1
set callbacks {};foreach {key prefix} {guard guard scope scope begin begin committed committed rollback rollback selected selected error errorReceipt advanced advancedCallback} {dict set callbacks $key ::P019::$prefix}
set ::P019::host [::GX::native2DCadCanvasCreate .embed $::P019::scene [dict create callbacks $callbacks]]
set ::P019::c [$::P019::host canvas];pack $::P019::c -fill both -expand 1
set ::P019::cad [$::P019::host context];set ::P019::a [$::P019::host advanced]
# Consumer-chosen middle-button routing uses the same public event owner, no pan implementation.
foreach {pattern phase} {<Button-2> pan_start <B2-Motion> pan_move <ButtonRelease-2> pan_end} {bind $::P019::c $pattern [list $::P019::host event $phase %x %y]}
foreach family {select line path spline quadratic_bezier cubic_bezier arc} {ttk::button .tools.$family -text $family -command [list ::P019::safe [list ::P019::choose $family]];pack .tools.$family -side left -padx 2}
foreach direction {undo redo} {ttk::button .tools.$direction -text $direction -command [list ::P019::safe [list ::P019::navigate $direction]];pack .tools.$direction -side left -padx 2}
foreach {name label cmd} {join {Review Join Path} {::P019::prepareTopology join_path} split {Review Split} {::P019::prepareTopology split_composition} separate {Review Separate} {::P019::prepareTopology separate} apply {Apply reviewed topology} ::P019::applyTopology horizontal {Horizontal} ::P019::constraintStart constraintApply {Apply relationship} ::P019::constraintApply disable {Disable relation} ::P019::disableRelation dimension {Dimension} ::P019::dimensionStart editor {External editor} ::P019::dimensionEditor reference {Reference editor} {::P019::dimensionEditor 1}} {
 ttk::button .actions.$name -text $label -command [list ::P019::safe $cmd];pack .actions.$name -side left -padx 1
}
ttk::label .property.objectLabel -text {Consumer-owned object browser};pack .property.objectLabel -fill x
ttk::treeview .property.objects -columns {family native} -height 12 -selectmode extended
.property.objects heading #0 -text Logical;.property.objects column #0 -width 80
foreach {id text width} {family Family 130 native NativeID 65} {.property.objects heading $id -text $text;.property.objects column $id -width $width}
pack .property.objects -fill x;bind .property.objects <ButtonRelease-1> {::P019::safe ::P019::treeSelect}
ttk::label .property.relLabel -text {Native relationships};pack .property.relLabel -fill x
ttk::treeview .property.relationships -columns {kind disabled} -height 7
.property.relationships heading #0 -text Logical;.property.relationships column #0 -width 80
foreach {id text width} {kind Kind 130 disabled Disabled 65} {.property.relationships heading $id -text $text;.property.relationships column $id -width $width}
pack .property.relationships -fill x;bind .property.relationships <ButtonRelease-1> ::P019::relationshipSelect
ttk::label .status -textvariable ::P019::status -anchor w -wraplength 1450;pack .status -side bottom -fill x
proc ::P019::validate {record} {if {![dict exists $record base objects]} {error {Missing fixture scientific state}}}
::GX::scientificRecipeHostRegister fixture.p019_independent [dict create capture ::P019::capture validate ::P019::validate replay ::GX::scientificHistoryState]
set ::P019::history [::GX::scientificHistoryContextAttach fixture.p019_independent [dict create capture ::P019::capture restore ::P019::restore commit ::P019::projected guard ::P019::historyGuard]]
set exitCode 0
try {
 namespace eval ::P019 {
  pause 180;$host refresh final;pause
  check {![llength [info commands ::GX::CurveWorkbench::open]]} {no Curve Workbench runtime imported}
  check {[winfo parent $c] eq {.embed} && [winfo toplevel $c] eq {.}} {chosen Canvas container and external toolbar use one application window}
  if {$::variant ni {qualification preview motion}} {
  set metric [construct line {{0 1} {3 2}}]
  set path [construct path {{5 1} {7 1} {7 3} {9 3}} 1]
  set spline [construct spline {{0 5} {2 7} {4 5} {5 7}} 1]
  set quadratic [construct quadratic_bezier {{11 6} {13 8} {15 6}}]
  set cubic [construct cubic_bezier {{6 6} {7 9} {9 4} {10 7}}]
  set arc [construct arc {{11 1} {12 3} {14 1}}]
  shot constructed
  # Preview cancellation uses the actual shared bound Canvas route.
  set beforeCancel [capture];set historyBefore [dict get [::GX::scientificHistoryViewerStatus $history] count]
  click .tools.line;canvasClick {0 -3};worldAt {3 -2};pause 130
  check {[capture] eq $beforeCancel && [$host feedbackObjects] ne {}} {construction preview does not mutate committed scientific objects}
  xt key Escape;pause
  check {[capture] eq $beforeCancel && [$host feedbackObjects] eq {} && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$historyBefore} {Escape discards staged construction without a History step}
  # Actual spline defining control, not a sampled rendering point.
  click .tools.select
  set ref [lindex [$a control inspect [native $spline]] 1];set at [::GX::Native2D::core device $scene [dict get $ref point]]
  set beforeEdit [capture];set original [$cad object definition [native $spline]]
  at $at;xt mousedown 1;pause 40;at [list [expr {[lindex $at 0]+20}] [expr {[lindex $at 1]-15}]];pause 130
  set proposal [dict get [$host state] gesture proposal definition]
  check {[$cad object definition [native $spline]] eq $original && [dict get $proposal controls] ne [dict get $original controls]} {true spline control preview changes the proposal while committed geometry remains unchanged}
  xt mouseup 1;pause
  check {[dict get [$cad object definition [native $spline]] controls] eq [dict get $proposal controls]} {released spline control equals exact native proposal}
  set edited [capture];click .tools.undo;check {[capture] eq $beforeEdit} {public P017 Undo restores exact logical geometry}
  click .tools.redo;check {[capture] eq $edited} {public P017 Redo preserves exact native definition with explicit identity mapping}
  # Constraint discovery/application and management are driven by external UI.
  selectObject $metric;set hproposedBefore [capture];set hcount [dict get [::GX::scientificHistoryViewerStatus $history] count];click .actions.horizontal
  check {[capture] eq $hproposedBefore && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$hcount} {constraint discovery/proposal leaves scientific state and History unchanged}
  check {[dict get [$a constraint state] status] eq {ready}} {shared native compatibility discovers Horizontal for selected line}
  click .actions.constraintApply
  set hrel [lindex [dict keys $relations] end];set hrow [$cad relationship get [dict get $relations $hrel]]
  check {[dict get $hrow kind] eq {horizontal} && [dict get $hrow valid]} {actual Apply creates valid authoritative Horizontal relationship}
  selectRelation $hrel;set hbefore [capture];click .actions.disable
  check {[dict get [$cad relationship get [dict get $relations $hrel]] disabled]} {actual management control disables native relationship}
  click .tools.undo;check {[capture] eq $hbefore} {relationship management Undo uses native P017 state owner}
  click .tools.redo
  # Shared editor under a consumer-selected external parent; cm -> native mm.
  selectObject $metric;click .actions.dimension;worldAt {1.5 3.5};pause 90;click .actions.editor
  check {[winfo parent .property.editor] eq {.property} && [winfo toplevel .property.editor] eq {.}} {shared dimension editor embeds without imposing an application window}
  set invalidBefore [capture];set invalidCount [dict get [::GX::scientificHistoryViewerStatus $history] count]
  type .property.editor.value NaN;click .property.editor.commit
  check {[capture] eq $invalidBefore && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$invalidCount && [.property.editor.value get] eq {NaN}} {invalid shared dimension input preserves geometry, History and entered text}
  type .property.editor.value 0.5;click .property.editor.commit;pause 130
  set dimension [lindex [dict keys $relations] end];set dimrow [$cad relationship get [dict get $relations $dimension]]
  check {![dict get $dimrow driven] && [dict get $dimrow valid] && abs([dict get $dimrow value]-5)<1e-9 && abs([dict get $dimrow measured_value]-5)<1e-7} {actual driving editor converts0.5cm to5mm and native geometry solves correctly}
  set dimensional [capture];click .tools.undo;click .tools.redo;check {[capture] eq $dimensional} {dimension geometry and relationship survive Undo/Redo}
  click .tools.select;selectObject $metric;click .actions.dimension;click .actions.reference
  check {[winfo viewable .property.editor.commit] && [winfo rooty .property.editor.commit]+[winfo height .property.editor.commit]<=[winfo rooty .property]+[winfo height .property]} {configured reference commit control remains fully inside consumer parent}
  type .property.editor.value 0.5;click .property.editor.commit;pause 130
  set rrel [lindex [dict keys $relations] end];check {[dict get [$cad relationship get [dict get $relations $rrel]] driven]} {reference dimension remains an actual non-driving native measurement}
  shot dimensions
  click .tools.select
  set first [construct line {{2 -3} {4 -3}}]
  set second [construct line {{4 -3} {6 -2}}]
  click .tools.select;selectObject $first;selectObject $second 1
  set firstDef [$cad object definition [native $first]];set secondDef [$cad object definition [native $second]]
  set beforeJoin [capture];click .actions.join
  check {[capture] eq $beforeJoin && [$a topology state] ne {}} {topology review does not commit or consume scientific objects}
  click .actions.apply
  set joinedNative [dict get [$a state] receipt receipt]
  set joined [aliasFor $joinedNative]
  write topology-join-receipt.tcldict [dict create controller_receipt [dict get [$a state] receipt] consumer_last_object $lastObject authoritative_new_native $joinedNative logical_result $joined native_definition [$cad object definition $joinedNative]]
  check {[family $joined] eq {composite_path} && [llength [dict get [$cad object definition [native $joined]] parts]]==2} {actual reviewed Join Path creates exact connected retained constituents}
  check {[$cad object definition [native $first]] eq $firstDef && [$cad object definition [native $second]] eq $secondDef} {independent consumer explicitly preserves source geometry}
  selectObject $joined;click .actions.split;click .actions.apply
  set splitReceipt [dict get [$a state] receipt receipt]
  check {[llength $splitReceipt]==2 && [family $joined] eq {composite_path}} {actual shared Split creates two native exact outputs and preserves source}
  selectObject $joined;click .actions.separate;click .actions.apply
  set separateReceipt [dict get [$a state] receipt receipt]
  check {[llength $separateReceipt]==2 && [family $joined] eq {composite_path}} {actual Separate is distinct and returns exact constituent copies}
  shot topology
  } elseif {$::variant eq {qualification}} {
   # Targeted final owner-contract cases; earlier full03 workflow remains evidence.
   set beforeTool [capture];set toolHistory [dict get [::GX::scientificHistoryViewerStatus $history] count]
   click .tools.line;canvasClick {0 1};worldAt {3 2};pause 100
   check {[$a construction state] ne {} && [$host feedbackObjects] ne {}} {actual staged construction exists before direct Select}
   click .tools.select
   check {[$a construction state] eq {} && [$host feedbackObjects] eq {} && [capture] eq $beforeTool && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$toolHistory} {explicit same-value public Select cancels advanced scope without caller cancellation}
   click .tools.line;canvasClick {0 1};worldAt {3 2};pause 90
   worldAt {8 0};xt mousedown 2;pause 40
   set panAt [::GX::Native2D::core device $scene {8 0}];at [list [expr {[lindex $panAt 0]+24}] [expr {[lindex $panAt 1]+10}]];pause 90
   check {[dict get [$host state] active] && [$a construction state] ne {}} {actual middle Pan and advanced construction are both owned before Escape}
   xt key Escape mouseup 2;pause 100
   check {![dict get [$host state] active] && [$a construction state] eq {} && [$host feedbackObjects] eq {} && ![::GX::Native2D::core drag_active $scene] && [capture] eq $beforeTool && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$toolHistory} {Escape clears both owned scopes with geometry and History intact}
   set first [construct line {{2 -3} {4 -3}}]
   set second [construct line {{4 -3} {6 -2}}]
   click .tools.select;selectObject $first;selectObject $second 1
   set beforeJoin [capture];set joinHistory [dict get [::GX::scientificHistoryViewerStatus $history] count]
   click .actions.join;click .actions.apply
   set receipt [dict get [$a state] receipt];set joinedNative [dict get $receipt receipt];set joined [aliasFor $joinedNative]
   check {$lastObject eq $joined && $lastOperation eq {topology.join_path} && [dict get [lindex $advancedCommits end] operation] eq {topology.join_path}} {reserved callback operation remains qualified and matches native result identity}
   check {[family $joined] eq {composite_path} && [llength [dict get [$cad object definition $joinedNative] parts]]==2 && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$joinHistory+1} {actual qualified Join records one exact native topology change}
   set joinedState [capture];click .tools.undo;check {[capture] eq $beforeJoin} {actual Join Undo restores exact logical sources and relationships}
   click .tools.redo;check {[capture] eq $joinedState} {actual Join Redo restores exact constituent identities and topology}
   shot final-qualified
  } elseif {$::variant eq {preview}} {
   set metric [construct line {{0 1} {3 1}}]
   click .tools.select;selectObject $metric;click .actions.dimension
   set initial [capture];set initialHistory [dict get [::GX::scientificHistoryViewerStatus $history] count]
   worldAt {1.5 3.5};pause 150
   set proposal [$a dimension state]
   write dimension-hover-state.tcldict $proposal
   check {[dict get $proposal geometry] ne {} && [llength [$c find withtag cad_relation_preview]]>0} {actual ordinary pointer Motion paints native dimension proposal through default shared Host}
   check {[capture] eq $initial && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$initialHistory} {painted dimension preview changes neither committed geometry nor History}
   set markers [llength [$c find withtag cad_relation_preview]]
   for {set i 0} {$i<4} {incr i} {$host refresh final;pause 30}
   check {[llength [$c find withtag cad_relation_preview]]==$markers} {repeated refresh replaces owned proposal items without accumulation}
   shot dimension-hover
   # Application routes Escape from its external toolbars to the public Host.
   # No private cancellation controller and no forced focus are introduced.
   bind . <Escape> [list $host event key Escape]
   xt key Escape;pause 100
   check {[$c find withtag cad_relation_preview] eq {} && [capture] eq $initial && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$initialHistory} {actual Escape clears painted dimension proposal with scientific state intact}
   selectObject $metric;click .actions.dimension;click .actions.reference
   type .property.editor.value 0.3;click .property.editor.commit;pause 100
   set alias [lindex [dict keys $relations] end];set rid [dict get $relations $alias]
   check {[dict get [$cad relationship get $rid] driven] && [$c find withtag cad_relation_preview] eq {}} {reference commit removes transient preview and preserves native reference semantics}
   click .tools.select
   set initial [capture];set initialHistory [dict get [::GX::scientificHistoryViewerStatus $history] count]
   set nativeGeometry [$cad relationship dimension_geometry $rid]
   at [dict get $nativeGeometry label];xt mousedown 1;pause 50
   set target [lmap x [dict get $nativeGeometry label] d {40 35} {expr {$x+$d}}]
   at $target;pause 140
   set drag [dict get [$a dimension state] annotation_drag]
   check {$drag ne {} && [dict get $drag changed] && [capture] eq $initial} {actual reference annotation drag previews without mutating committed relationship}
   set expected [$cad relationship dimension_preview [$cad relationship get $rid] [dict get $drag target]]
   set painted {};set text {}
   foreach item [$c find withtag native_constraint_$rid] {if {[$c type $item] eq {text}} {set painted [$c coords $item];set text [$c itemcget $item -text]}}
   check {$painted eq [dict get $expected label] && [string match {(*)} $text]} {annotation preview uses exact native label position and preserves reference parentheses}
   shot annotation-hover
   xt key Escape mouseup 1;pause 100
   check {[capture] eq $initial && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$initialHistory && [dict get [$a dimension state] annotation_drag] eq {} && ![::GX::Native2D::core drag_active $scene]} {annotation Escape restores geometry and History with no owned native transaction}
   set count [llength [$c find all]]
   for {set i 0} {$i<4} {incr i} {$host refresh final;pause 30}
   check {[llength [$c find all]]==$count && [$c find withtag cad_relation_preview] eq {}} {post-cancel refresh leaves no extra preview or retained Tk items}
   shot preview-final
  } else {
   set motionCounter 0
   bind $c <Motion> {+incr ::P019::motionCounter}
   worldAt {8 0};pause 100
   set idleCounter $motionCounter
   worldAt {9 0};pause 100
   check {$motionCounter>$idleCounter} {idle default Host Motion preserves the consumer widget readout binding}
   set metric [construct line {{0 1} {3 1}}]
   set original [capture];set originalHistory [dict get [::GX::scientificHistoryViewerStatus $history] count]
   click .tools.line;canvasClick {6 3}
   set consumedBefore $motionCounter
   worldAt {8 4};pause 140
   check {$motionCounter==$consumedBefore && [$host feedbackObjects] ne {}} {staged construction consumes actual Motion and paints through the shared Host}
   bind . <Escape> [list $host event key Escape]
   xt key Escape;pause 100
   check {[capture] eq $original && [$host feedbackObjects] eq {} && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$originalHistory} {construction Motion qualification Escape preserves exact science and History}
   click .tools.select;selectObject $metric;click .actions.dimension
   set consumedBefore $motionCounter
   worldAt {1.5 3.5};pause 140
   check {$motionCounter==$consumedBefore && [llength [$c find withtag cad_relation_preview]]>0} {staged dimension consumes actual Motion and paints native geometry}
   set viewBefore [::GX::Native2D::core view_requested $scene]
   xt click 4;pause 180
   check {[::GX::Native2D::core view_requested $scene] ne $viewBefore} {actual X11 wheel input changes the public native viewport}
   set state [$a dimension state]
   set expected [$cad relationship dimension_preview [dict get $state specification] [dict get $state annotation]]
   set paintedLines {};set paintedLabel {}
   foreach item [$c find withtag cad_relation_preview] {switch -- [$c type $item] {line {lappend paintedLines [$c coords $item]} text {set paintedLabel [$c coords $item]}}}
   set nativeLines [lmap line [dict get $expected lines] {concat {*}$line}]
   set matches [expr {[llength $paintedLines]==[llength $nativeLines] && [llength $nativeLines]==7}]
   foreach got $paintedLines wanted $nativeLines {if {[llength $got]!=[llength $wanted]} {set matches 0};foreach gotCoordinate $got wantedCoordinate $wanted {if {abs($gotCoordinate-$wantedCoordinate)>1e-8} {set matches 0}}}
   foreach gotCoordinate $paintedLabel wantedCoordinate [dict get $expected label] {if {abs($gotCoordinate-$wantedCoordinate)>1e-8} {set matches 0}}
   write motion-wheel-projection.tcldict [dict create motion_counter $motionCounter consumer_counter_before_consumed $consumedBefore viewport_before $viewBefore viewport_after [::GX::Native2D::core view_requested $scene] native_expected $expected painted_lines $paintedLines painted_label $paintedLabel]
   check {$matches} {post-wheel dimension label and all seven line coordinates equal current native projection}
   check {[capture] eq $original && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$originalHistory} {view change and painted advanced proposals leave science and History unchanged}
   shot motion-wheel-preview
   xt key Escape;pause 100
   check {[$c find withtag cad_relation_preview] eq {} && [$host feedbackObjects] eq {} && [capture] eq $original && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$originalHistory} {actual Escape removes all advanced presentation without a scientific History step}
   set resumedBefore $motionCounter;worldAt {8 0};pause 90
   check {$motionCounter>$resumedBefore} {idle consumer Motion binding resumes after advanced cancellation}
   write consumer-motion-counter.tcldict [dict create final $motionCounter initial_idle $idleCounter construction_before_consumed $consumedBefore resumed_before $resumedBefore]
  }
  check {$errors eq {} && $opErrors eq {}} {no unexpected application or Tk callback failures}
  write final-scientific-state.tcldict [capture]
  write final-history-status.tcldict [::GX::scientificHistoryViewerStatus $history]
  # Disposal owns tools/editor/resources, not the scientific scene.
  $host cancel final_check;set originalCount [llength [::GX::Native2D::core ids $scene]]
  ::GX::scientificHistoryContextClose $history 0;set history {}
  destroy $c;pause 100
  check {![llength [info commands $host]] && ![llength [info commands $a]] && [llength [::GX::Native2D::core ids $scene]]==$originalCount} {Canvas disposal releases shared advanced controller and preserves scientific source}
  check {$errors eq {}} {no orphan callback error after disposal}
  foreach path [dict keys $::loadedPins] {check {[lindex [exec sha256sum [file join $::framework $path]] 0] eq [dict get $::loadedPins $path]} "loaded public source identity retained: $path"}
  write source-pins.tcldict $::loadedPins
  write RESULT.txt PASS
 }
} on error {m o} {
 puts stderr [dict get $o -errorinfo]
 catch {::P019::write failure-scientific-state.tcldict [::P019::capture]}
 catch {::P019::write failure-tool-state.tcldict [$::P019::a state]}
 catch {::P019::write failure-focus.tcldict [dict create focus [focus] canvas $::P019::c]}
 catch {::P019::write failure-application-readout.tcldict [dict create lastObject $::P019::lastObject lastReceipt $::P019::lastReceipt lastOperation $::P019::lastOperation objects $::P019::objects]}
 catch {::P019::shot failure};set exitCode 1
} finally {
 ::P019::write errors.tcllist $::P019::errors
 if {$::P019::history ne {}} {catch {::GX::scientificHistoryContextClose $::P019::history 0}}
 if {[llength [info commands $::P019::host]]} {catch {$::P019::host dispose}}
 catch {::GX::Native2D::core destroy $::P019::scene};catch {destroy .}
}
::P019::write EXIT_CODE.txt $exitCode
exit $exitCode
