lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output
set ::env(XDG_CONFIG_HOME) [file join $output config];set argv0 __native016__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
package require Tk
proc pause {{ms 100}} {set ::wait 1;after $ms {set ::wait 0};vwait ::wait}
proc check {value name} {if {![uplevel 1 [list expr $value]]} {error $name};puts "PASS: $name";flush stdout}
proc bgerror {m} {lappend ::errors $m}
set errors {}
canvas .c -width 500 -height 400 -background white;pack .c
button .b -text {Tooltip target};pack .b
wm geometry . 550x500+20+20
pause 200
focus -force .b
set n [::GX::native2DSpriteSceneCreate .c]
set g [list [dict create kind rectangle points {{0 0} {80 40}} fill blue stroke black width 2]]
::GX::native2DSpriteSceneBatch .c [list [dict create id box geometry $g position {100 100} anchors {tip {position {80 20} direction {1 0}}}]]
check {[::GX::native2DSpriteSceneHit .c {120 120}] eq {box}} {native hit on actual mapped sprite}
::GX::native2DSpriteSceneBatch .c {{id box position {180 160} pivot {40 20} angle 90 scale {2 1}}}
set a [::GX::native2DSpriteSceneAnchor .c box tip]
lassign [dict get $a position] x y;lassign [dict get $a direction] dx dy
check {abs($x-220)<1e-9 && abs($y-260)<1e-9 && abs($dx)<1e-9 && abs($dy-1)<1e-9} {combined native position rotation pivot scale and transformed anchor direction}
check {[::GX::native2DSpriteSceneHit .c {220 230}] eq {box}} {transformed bounds and hit test}
::GX::native2DSpriteSceneBatch .c [list [dict create id top geometry $g position {180 200} z 2]]
check {[lindex [::GX::native2DSpriteSceneHit .c {220 230}] 0] eq {top}} {Z-order controls topmost hit}
pause;exec import -silent -window root [file join $output z-top.png]
::GX::native2DSpriteSceneBatch .c {{id top z -1}}
check {[lindex [::GX::native2DSpriteSceneHit .c {220 230}] 0] eq {box}} {Z-order change applied}
pause;exec import -silent -window root [file join $output z-bottom.png]
set before [::GX::native2DSpriteSceneDescribe .c box]
check {[catch {::GX::native2DSpriteSceneBatch .c {{id box position {1 2}} {id bad scale {0 1}}}}] && [::GX::native2DSpriteSceneDescribe .c box] eq $before} {invalid batch is atomic}
::GX::native2DSpriteSceneRemove .c top
::GX::native2DSpriteSceneBegin .c {0 0 500 400}
::GX::native2DSpriteSceneAppend .c retained $g
::GX::native2DSpriteSceneEnd .c
check {[dict get [::GX::native2DSpriteSceneDescribe .c] sprites]==1} {frame sweep retires untouched sprites}
# Direct scientific binding and selective invalidation, no Workbench dependency.
set scene [::GX::Native2D::core scene]
::GX::Native2D::core view $scene {500 400 0 0 0 0 {-1 -1 5 3}}
set cad [::GX::native2DCadCreate $scene]
set id [$cad object create {family quadratic_bezier controls {{0 0} {2 2} {4 0}}} 64]
$cad object style $id {visible 1 selectable 1 color {0.2 0.3 0.8 1} line_width 2}
$cad object direction $id {visible 1}
proc sync {} {
 ::GX::native2DSpriteSceneBegin .c {0 0 500 400}
 set receipt [::GX::native2DSpriteSceneSync .c $::scene [list [dict create id scientific object $::id controls 1 z 3]]]
 ::GX::native2DSpriteSceneEnd .c
 pause 30
 return $receipt
}
::GX::native2DSpriteSceneRemove .c retained
::GX::native2DSpriteSceneAttach .c $scene
::GX::native2DSpriteSceneAttach .c $scene
sync
set first [::GX::native2DSpriteSceneDescribe .c scientific]
set stats [::GX::native2DSpriteSceneDescribe .c]
set anchor [::GX::native2DSpriteSceneAnchor .c scientific direction_tip]
set marker [::GX::Native2D::core render_marker $scene $id]
check {[dict get $anchor position] eq [dict get $marker tip]} {direct marker anchor exactly matches authoritative C projection}
sync
set stable [::GX::native2DSpriteSceneDescribe .c]
check {[dict get $stable native_cache_hits]==[dict get $stats native_cache_hits]+1 && [dict get $stable native_sampled_points]==[dict get $stats native_sampled_points]} {unchanged object reused without sampling or geometry transfer}
set ref [$cad selection reference $id control 1000000001]
$cad control edit $ref {2 1.5}
sync
check {[dict get [::GX::native2DSpriteSceneDescribe .c scientific] native_revision]>[dict get $first native_revision]} {defining edit invalidates exact native state even without topology change}
set revision [dict get [::GX::native2DSpriteSceneDescribe .c scientific] native_revision]
$cad object style $id {line_width 4}
sync
check {[dict get [::GX::native2DSpriteSceneDescribe .c scientific] native_revision]>$revision} {scientific style change invalidates presentation}
set points [dict get [::GX::native2DSpriteSceneDescribe .c] native_sampled_points]
::GX::Native2D::core zoom $scene 1.1 {250 200}
sync
check {[dict get [::GX::native2DSpriteSceneDescribe .c] native_sampled_points]>$points} {viewport update refreshes projected geometry natively}
$cad selection apply [list [dict create kind object id $id index 0]]
::GX::Native2D::core gizmo $scene {visible 1 mode translate}
set before [$cad object definition $id]
$cad gesture begin free {200 200} [list $id];$cad gesture plan {215 210};$cad gesture apply
sync
$cad gesture cancel
sync
check {[$cad object definition $id] eq $before && ![::GX::Native2D::core drag_active $scene]} {drag preview and exact cancel remain synchronized}
# Compare original public manual conversion with direct representation on the
# same Cairo renderer, identical geometry/style/view; only transport differs.
canvas .manual -width 500 -height 400 -background white -highlightthickness 0
pack .manual
.c configure -highlightthickness 0
::GX::native2DSpriteSceneBegin .manual {0 0 500 400}
::GX::native2DSpriteSceneObject .manual manual [::GX::native2DPresentationObjectSnapshot $scene $id 4096] white
::GX::native2DSpriteSceneControls .manual $scene $id {} #22303f manual
# Match direct control color to default native style; the public manual helper
# receives the very same composited RGBA from the public snapshot.
set snapshot [::GX::native2DPresentationObjectSnapshot $scene $id 4096]
set out [open [file join $output snapshot.tcldict] w];puts $out $snapshot;close $out
set color [dict get [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA [dict get $snapshot style color]] white] rgb]
# Rebuild manual frame so the exact requested control stroke is used.
::GX::native2DSpriteSceneBegin .manual {0 0 500 400}
::GX::native2DSpriteSceneObject .manual manual $snapshot white
::GX::native2DSpriteSceneControls .manual $scene $id {} $color manual
::GX::native2DSpriteSceneEnd .manual
wm geometry . 600x900;pause 100
foreach {widget file} {.c direct .manual manual} {exec import -silent -window [winfo id $widget] [file join $output $file.png]}
# Tk path is not an X window id for ImageMagick; record via numeric winfo id.
::GX::native2DSpriteSceneDetach .c
check {[dict get [::GX::native2DSpriteSceneDescribe .c] native_bound_objects]==0} {explicit detach releases bindings without destroying scientific scene}
sync
$cad object delete $id
check {[catch {sync}]} {deleted scientific object rejects stale binding}
check {[dict get [::GX::native2DSpriteSceneDescribe .c] native_bound_objects]==0} {deleted binding retires retained resource}
set id [$cad object create {family line controls {{0 0} {4 1}}} 64];sync
::GX::native2DSpriteSceneBatch .c [list [dict create id manualIndependent geometry $g]]
::GX::Native2D::core destroy $scene
check {[dict get [::GX::native2DSpriteSceneDescribe .c] native_bound_objects]==0 && [dict get [::GX::native2DSpriteSceneDescribe .c] sprites]==1 && ![dict get [$cad state] alive]} {source disposal revokes scientific observers and preserves manual sprites}
::GX::native2DCadDispose $cad
::GX::native2DSpriteSceneDispose .manual;destroy .manual
::GX::native2DSpriteSceneDispose .c
check {![llength [info commands $n]] && [.c find withtag native_sprite_scene] eq {}} {explicit native resource disposal}
set n [::GX::native2DSpriteSceneCreate .c];destroy .c;pause
check {![llength [info commands $n]] && $errors eq {}} {Canvas destroys native owner without stale callback}
destroy .b
destroy .
