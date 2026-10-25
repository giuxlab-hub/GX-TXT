lassign $argv framework output variant
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p018_independent__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
set session [::GX::createNewSession p018_independent {} 0]
set token [::GX::interactiveDocumentSessionToken]
package require Tk;wm geometry . 1100x800+10+10;wm title . {Independent public CORE CAD Canvas consumer}
set errors {};set checks {};set input {};set operationErrors {};set receipts {};set generation 1;set expectedGeneration 1
proc write {name data} {set f [open [file join $::output $name] w];puts -nonewline $f $data;close $f}
proc bgerror {m} {lappend ::errors $m;puts stderr "BACKGROUND: $m"}
proc check {expr label} {if {![uplevel 1 [list expr $expr]]} {error "FAIL: $label"};lappend ::checks $label;write checks.tcllist $::checks;puts "PASS: $label";flush stdout}
proc pause {{ms 90}} {set ::wait 1;after $ms {set ::wait 0};vwait ::wait}
proc xt {args} {lappend ::input [list [clock microseconds] {*}$args];write input.tcllist $::input;exec xdotool {*}$args}
proc point {xy} {lassign $xy x y;xt mousemove [expr {[winfo rootx $::c]+int(round($x))}] [expr {[winfo rooty $::c]+int(round($y))}]}
proc click {widget} {xt mousemove [expr {[winfo rootx $widget]+[winfo width $widget]/2}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1;pause}
proc canvasClick {xy {modifier {}}} {point $xy;if {$modifier ne {}} {xt keydown $modifier};xt click 1;if {$modifier ne {}} {xt keyup $modifier};pause}
proc shot {name} {pause;exec import -silent -window root [file join $::output $name.png]}
proc guard {event} {expr {$::generation==$::expectedGeneration && $::token eq [::GX::interactiveDocumentSessionToken]}}
proc errorReceipt {event} {lappend ::operationErrors $event;write operation-errors.tcllist $::operationErrors}
proc capture {} {
 set objects {};foreach id $::ids {dict set objects $id [::GX::Native2D::core sketch_definition $::scene $id]}
 return [dict create objects $objects pivot [::GX::Native2D::core pivot $::scene]]
}
proc restore {state} {dict for {id definition} [dict get $state objects] {::GX::Native2D::core sketch_update $::scene $id $definition 128};set p [dict get $state pivot];::GX::Native2D::core pivot $::scene [dict get $p mode] {*}[expr {[dict get $p mode] eq {custom}?[list [dict get $p point]]:{}}];$::host refresh final}
proc projected {record} {write projected-history.tcldict $record}
proc historyGuard {} {expr {$::token eq [::GX::interactiveDocumentSessionToken]}}
proc begin {event} {set ::before [capture];return operation}
proc committed {event} {
 if {[dict get $event changed]} {set r [::GX::scientificHistoryViewerRecordOperation $::history [dict get $event operation]];lappend ::receipts $r;write history-receipts.tcllist $::receipts;return $r}
 return {}
}
proc rollback {event} {restore $::before}
proc nav {what} {$::host cancel navigation;::GX::scientificHistoryViewerNavigate $::history $what;$::host refresh final}
proc tool {what} {$::host tool $what;$::host refresh final}
::GX::native2DEnsure
set scene [::GX::Native2D::core scene]
set ids {}
foreach definition {{family line controls {{0 0} {3 0}}} {family cubic_bezier controls {{0 2} {1 4} {2 1} {4 3}}} {family spline controls {{5 0} {6 1} {7 0} {8 2}}}} {
 set id [::GX::Native2D::core sketch_create $scene $definition 128];lappend ids $id
 ::GX::Native2D::core object_style $scene $id {color {0.15 0.3 0.7 1} line_width 2 marker 0}
}
::GX::Native2D::core pivot $scene custom {1.5 0}
frame .outside;pack .outside -side top -fill x
frame .domain;pack .domain -fill both -expand 1
set host [::GX::native2DCadCanvasCreate .domain $scene [dict create callbacks [dict create guard guard begin begin committed committed rollback rollback error errorReceipt]]]
set c [$host canvas];pack $c -fill both -expand 1
foreach t {select rectangle polygon translate rotate pivot pan} {ttk::button .outside.$t -text $t -command [list tool $t];pack .outside.$t -side left}
foreach t {undo redo} {ttk::button .outside.$t -text $t -command [list nav $t];pack .outside.$t -side left}
ttk::button .outside.fit -text Fit -command [list $host fit];pack .outside.fit -side left
proc validateRecord {record} {if {![dict exists $record base objects]} {error {Missing native definitions}}}
::GX::scientificRecipeHostRegister fixture.cad_canvas [dict create capture capture validate validateRecord replay ::GX::scientificHistoryState]
set history [::GX::scientificHistoryContextAttach fixture.cad_canvas [dict create capture capture restore restore commit projected guard historyGuard]]
set exitCode 0
try {
 pause 150;click .outside.fit
 if {$variant ne {lifecycle}} {
 check {![llength [info commands ::GX::CurveWorkbench::open]]} {consumer loads no Curve Workbench runtime}
 check {[winfo parent $c] eq {.domain} && [winfo toplevel $c] eq {.}} {host embeds in chosen container without a new toplevel}
 canvasClick [::GX::Native2D::core device $scene {1.5 0}]
 check {[llength [dict get [[$host context] selection snapshot] objects]]==1} {actual canvas selects native object}
 canvasClick [::GX::Native2D::core device $scene {6 1}] Control_L
 check {[llength [dict get [[$host context] selection snapshot] objects]]==2} {actual additive native selection}
 canvasClick [::GX::Native2D::core device $scene {6 1}] Shift_L
 check {[llength [dict get [[$host context] selection snapshot] objects]]==1} {actual subtractive native selection}
 check {[dict get [::GX::scientificHistoryViewerStatus $history] count]==0} {selection/repaint creates no History operation}
 click .outside.translate
 set gizmo [::GX::Native2D::core render_gizmo $scene];set start {}
 foreach g $gizmo {if {[dict get $g handle] eq {x} && [dict get $g kind] eq {line}} {lassign [dict get $g a] ax ay;lassign [dict get $g b] bx by;set start [list [expr {($ax+$bx)/2}] [expr {($ay+$by)/2}]];break}}
 check {$start ne {}} {shared native translation gizmo available}
 set before [capture];point $start;xt mousedown 1;pause 50;point [list [expr {[lindex $start 0]+35}] [lindex $start 1]];pause 100;xt mouseup 1;pause 150
 check {[capture] ne $before && ![::GX::Native2D::core drag_active $scene]} {actual GUI translation commits native scientific state}
 set moved [capture];click .outside.undo;check {[capture] eq $before} {public P017 immediate Undo restores exact geometry}
 click .outside.redo;check {[capture] eq $moved} {public P017 Redo restores exact geometry}
 # Escape cancels the same native engine, not a duplicate consumer implementation.
 set start {}
 foreach g [::GX::Native2D::core render_gizmo $scene] {if {[dict get $g handle] eq {x} && [dict get $g kind] eq {line}} {lassign [dict get $g a] ax ay;lassign [dict get $g b] bx by;set start [list [expr {($ax+$bx)/2}] [expr {($ay+$by)/2}]];break}}
 set hist [dict get [::GX::scientificHistoryViewerStatus $history] count]
 point $start;xt mousedown 1;pause 30;point [list [expr {[lindex $start 0]+20}] [lindex $start 1]];pause 70;check {[::GX::Native2D::core drag_active $scene] && [capture] ne $moved} {Escape test has a real active native preview};xt key Escape mouseup 1;pause
 check {[capture] eq $moved && ![::GX::Native2D::core drag_active $scene] && [dict get [::GX::scientificHistoryViewerStatus $history] count]==$hist} {Escape preserves geometry and History with no active drag}
 click .outside.select
 set id [lindex $ids 1];set ref [lindex [::GX::Native2D::core interaction_controls $scene $id] 1];set at [::GX::Native2D::core device $scene [dict get $ref point]]
 set original [::GX::Native2D::core sketch_definition $scene $id]
 point $at;xt mousedown 1;pause 40;point [list [expr {[lindex $at 0]+20}] [expr {[lindex $at 1]-15}]];pause 100
 set state [$host state]
 check {[::GX::Native2D::core sketch_definition $scene $id] eq $original && [dict exists $state gesture proposal definition]} {real Bezier control preview preserves scientific definition until release}
 set proposed [dict get $state gesture proposal definition]
 xt mouseup 1;pause 150
 check {[dict get [::GX::Native2D::core sketch_definition $scene $id] controls] eq [dict get $proposed controls]} {released control edit equals exact native preview}
 # The same class exposes region, rotation, policy and lifecycle facilities.
 click .outside.select
 set lineId [lindex $ids 0]
 set descriptors [::GX::Native2D::core interaction_controls $scene $lineId]
 lassign [dict get [lindex $descriptors 0] point] ax ay;lassign [dict get [lindex $descriptors 1] point] bx by
 canvasClick [::GX::Native2D::core device $scene [list [expr {($ax+$bx)/2}] [expr {($ay+$by)/2}]]]
 click .outside.rotate
 set circle {};foreach g [::GX::Native2D::core render_gizmo $scene] {if {[dict get $g handle] eq {rotate}} {set circle [dict get $g a];break}}
 check {$circle ne {}} {independent host exposes existing native Rotate gizmo}
 set beforeRotate [capture]
 set pivot [dict get [::GX::Native2D::core pivot $scene] point];lassign [::GX::Native2D::core device $scene $pivot] px py
 set radius [expr {[lindex $circle 0]-$px}]
 point $circle;xt mousedown 1;pause 50;point [list $px [expr {$py-$radius}]];pause 100;xt mouseup 1;pause 120
 check {[capture] ne $beforeRotate && ![::GX::Native2D::core drag_active $scene] && [dict get [$host state] receipt operation] eq {rotate}} {real independent Rotate commits through same native controller}
 click .outside.undo;check {[capture] eq $beforeRotate} {independent Rotate Undo uses P017 authority}
 click .outside.redo
 click .outside.fit
 click .outside.rectangle
 lassign [::GX::Native2D::core view $scene] cw ch l t r b
 set corners [list [list [expr {$l+2}] [expr {$t+2}]] [list [expr {$cw-$r-2}] [expr {$ch-$b-2}]]]
 point [lindex $corners 0];xt mousedown 1;point [lindex $corners 1];pause 60;xt mouseup 1;pause
 check {[llength [dict get [[$host context] selection snapshot] objects]]==3} {real rectangle selection uses shared native region authority}
 click .outside.polygon
 foreach at [list [list [expr {$l+1}] [expr {$t+1}]] [list [expr {$cw-$r-1}] [expr {$t+1}]] [list [expr {$cw-$r-1}] [expr {$ch-$b-1}]] [list [expr {$l+1}] [expr {$ch-$b-1}]]] {canvasClick $at}
 check {[llength [dict get [$host state] polygon]]==4} {polygon vertices survive ordinary releases}
 xt key Return;pause
 check {[llength [dict get [[$host context] selection snapshot] objects]]==3 && [dict get [$host state] polygon] eq {}} {real Enter completes shared native polygon selection}
 click .outside.select
 set beforeDisable [capture];set enabled [$host tools]
 $host tools [lsearch -all -inline -not -exact $enabled rotate]
 .outside.rotate state disabled;click .outside.rotate
 check {[capture] eq $beforeDisable && [catch {$host tool rotate}]} {consumer controls externally placed disabled tool without mutation}
 $host tools [lsearch -all -inline -not -exact $enabled pan]
 $host event pan_start 100 100
 check {[dict get [$host state] receipt status] eq {rejected} && ![dict get [$host state] active]} {disabled Pan rejects middle-button dispatch as well as its tool selector}
 $host tools $enabled;.outside.rotate state !disabled
 set existing [$host context]
 check {[catch {$host associate 999999999}] && [$host context] eq $existing && [dict get [$existing state] alive]} {invalid source association preserves existing context}
 check {[catch {$host configure {callbacks {unexpected bad}}}] && [dict get [$host state] attached]} {invalid callback configuration preserves existing host}
 ::GX::Native2D::core background $scene {0.94 0.96 1 1};$host refresh final;pause
 set itemCount [llength [$c find all]]
 for {set repeat 0} {$repeat<4} {incr repeat} {$host refresh final;pause 25}
 check {[llength [$c find all]]==$itemCount} {repeated host frames replace transient selection and gizmo overlays}
 shot independent
 }
 set oldContext [$host context]
 set second [::GX::Native2D::core scene]
 $host associate $second
 check {![llength [info commands $oldContext]] && [llength [::GX::Native2D::core ids $scene]]==3} {scene reassociation releases context without destroying consumer geometry}
 ::GX::Native2D::core destroy $second
 $host event down 100 100 0
 check {[dict get [$host state] receipt status] eq {rejected}} {destroyed scene rejects stale interaction}
 $host associate $scene
 set generation 2;$host event down 100 100 0
 check {[dict get [$host state] receipt status] eq {rejected}} {domain generation guard rejects stale Document callbacks}
 set generation 1
 ::GX::scientificHistoryContextClose $history 0
 set session2 [::GX::createNewSession p018_independent_second {} 0]
 $host event down 100 100 0
 check {[dict get [$host state] receipt status] eq {rejected}} {actual Session change rejects old Canvas callbacks}
 set pending [$host refresh resize]
 destroy $c;pause 120
 check {![llength [info commands $host]] && [llength [::GX::Native2D::core ids $scene]]==3} {Canvas disposal cancels work and preserves scientific scene}
 check {$errors eq {}} {no unexpected Tcl/Tk background exceptions}
 write RESULT.txt PASS
} on error {m o} {puts stderr [dict get $o -errorinfo];catch {shot failure};set exitCode 1} finally {
 write errors.tcllist $errors
 catch {::GX::scientificHistoryContextClose $history 0}
 if {[llength [info commands $host]]} {catch {$host dispose}}
 catch {::GX::Native2D::core destroy $scene};catch {destroy .}
}
write EXIT_CODE.txt $exitCode
exit $exitCode
