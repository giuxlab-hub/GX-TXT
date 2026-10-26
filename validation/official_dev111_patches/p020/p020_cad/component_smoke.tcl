# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {Usage: component_smoke.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework output
set framework [file normalize $framework];set output [file normalize $output]
if {[file exists $output]} {error {Use a fresh output directory}}
file mkdir $output
set ::env(XDG_CONFIG_HOME) [file join $output config]
set ::env(XDG_DATA_HOME) [file join $output data]
set ::env(XDG_CACHE_HOME) [file join $output cache]
set argv0 __component_smoke__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
set ::GX::cfg(output_root) [file join $output sessions]
::GX::createNewSession p020_cad
::GX::configurationSet viewers.native3d.execution Software
::GX::configurationSet storage.cache_dir [file join $output cache]
if {[string first "$output/" [file normalize $::GX::currentSession]]!=0 || [string first "$output/" [file normalize [::GX::configurationPath]]]!=0 || [::GX::configurationCacheDirectory] ne [file join $output cache]} {error {Component fixture escaped its private Session/config/cache root}}
puts "PRIVATE_ROOTS session=$::GX::currentSession config=[::GX::configurationPath] cache=[::GX::configurationCacheDirectory]"
if {![llength [info commands ::GX::nativeCadSketchCreate]]} {source [file join $framework core tcl native_cad_sketch_v1.tcl]}
proc assert {expression message} {if {![uplevel 1 [list expr $expression]]} {error $message};puts "PASS $message"}
set ::backgroundErrors {}
proc bgerror {message} {lappend ::backgroundErrors [list $message $::errorInfo]}
proc viewportReady {sketch} {
    set deadline [expr {[clock milliseconds]+15000}]
    while {[clock milliseconds]<$deadline} {
        update
        set state [::GX::native3DViewportInspect [$sketch get viewport]]
        if {[dict get $state status] in {error failed stale_source}} {error [dict get $state error]}
        if {[dict get $state status] eq {ready} && [dict get $state busy] eq {} && ![dict get $state pending]} {return $state}
        after 20
    }
    error "Native3D did not become ready: $state"
}
ttk::frame .component;pack .component -fill both -expand 1
set sketch [::GX::nativeCadSketchCreate .component {plane {origin {2 3 4} normal {0 1 1} u_axis {1 0 0}}}]
pack [$sketch widget] -fill both -expand 1
wm geometry . 900x640
update
set host [$sketch get host];set advanced [$sketch get advanced]
set local {{0 0} {3 4} {-2 1}}
set mapped [$sketch transform to_world $local]
set restored [$sketch transform to_plane [dict get $mapped points]]
foreach p $local q [dict get $restored points] {foreach a $p b [lrange $q 0 1] {assert {abs($a-$b)<1e-12} {oriented local/world roundtrip}}}
set before [::GX::scientificHistoryViewerStatus [$sketch get history_context]]
$advanced construction start line
$advanced construction adopt {{point {0 0}} {point {5 0}}}
set created [$advanced construction commit]
$host fit
assert {[dict get [$sketch get model] format] eq {gxtxt.native_cad_sketch.v1}} {exact generic Sketch model}
set map [dict get [$sketch state] object_map]
assert {[dict size $map]==1} {one exact construction retained}
set object [lindex [dict values $map] 0]
set definition [[$sketch get context] object definition $object]
assert {[dict get $definition family] eq {line}} {Native2D exact line is authoritative}
set initialExact [$sketch get model]
set scene [$sketch world_scene]
assert {[dict size [dict get $scene layers]]==1} {dynamic Native3D world geometry layer}
assert {[llength [dict get [lindex [dict values [dict get $scene layers]] 0] vertices]]==129} {bounded explicit visual sampling}
set rendered [viewportReady $sketch]
assert {[dict get $rendered error] eq {} && [dict get $rendered result] ne {}} {actual Native3D renderer produces a frame}
assert {[string first "$output/cache/" [dict get $rendered result path]]==0} {actual Native3D frame stays inside the private cache}
set receipt [open [file join $output native3d_frame.tcldict] w]
puts $receipt $rendered;close $receipt
set capture [auto_execok import]
if {$capture ne {}} {exec {*}$capture -window [winfo id .] [file join $output component.png]}
::GX::native3DViewportNavigate [$sketch get viewport] orbit 20 5
viewportReady $sketch
set camera [::GX::native3DViewportCamera [$sketch get viewport]]
set stale [[$sketch get context] selection reference $object control 1]
$sketch command undo
assert {[dict size [dict get [$sketch state] object_map]]==0} {CORE History undo}
$sketch command redo
assert {[dict size [dict get [$sketch state] object_map]]==1} {CORE History redo}
assert {[$sketch get model] eq $initialExact} {History hydration preserves implicit identity attributes exactly}
assert {[catch {[$sketch get context] control resolve $stale}]} {old raw native controls cannot alias after History hydration}
viewportReady $sketch
assert {[::GX::native3DViewportCamera [$sketch get viewport]] eq $camera} {Native3D context camera survives scientific edits}
set expected [$sketch get model];set document [$sketch get document_id]
$sketch save
$sketch close
set sketch [::GX::nativeCadSketchCreate .component [dict create document_id $document]]
assert {[$sketch get model] eq $expected} {exact save/close/reopen}
set host [$sketch get host];set advanced [$sketch get advanced];set cad [$sketch get context]
set object [lindex [dict values [dict get [$sketch state] object_map]] 0]
set ref [$cad selection reference $object object 0]
set specification [$cad relationship dimension_infer [list $ref] {2 -1}]
dict set specification annotation {2 -1};dict set specification placed 1;dict set specification driven 1
$advanced constraint apply 0 $specification
assert {[dict size [dict get [$sketch state] relationship_map]]==1} {shared graphical dimension retained with logical identity}
set withDimension [$sketch get model]
$sketch command undo
assert {[dict size [dict get [$sketch state] relationship_map]]==0} {dimension Undo uses CORE History}
$sketch command redo
assert {[$sketch get model] eq $withDimension} {exact dimension state survives staged Redo}
set advanced [$sketch get advanced]
set object [lindex [dict values [dict get [$sketch state] object_map]] 0]
set control [[$sketch get context] selection reference $object control 1]
$advanced control edit $control {5 1}
set record [::GX::scientificHistoryViewerRecord [$sketch get history_context]]
set patch [dict get [lindex [dict get $record steps] end] patch]
assert {[dict size $patch]<=2 && ![dict exists $patch scientific_history]} {control edit submits only changed scientific entity patches}
$sketch command undo
assert {[$sketch get model] eq $withDimension} {defining-control edit Undo restores exact geometry and dimension}
set advanced [$sketch get advanced]
$advanced construction start circle
$advanced construction adopt {{point {10 10}}}
$advanced construction preview {point {12 10}}
set previewCount [llength [::GX::Native2D::core ids [$sketch get scene]]]
assert {$previewCount==2} {real native preview is present}
assert {[dict size [dict get [$sketch state] object_map]]==1} {preview is excluded from scientific identity}
$sketch command cancel
assert {[$sketch get model] eq $withDimension} {preview cancellation preserves exact scientific state}
set rejected [catch {::GX::nativeCadSketchCreate .component {working_unit s}}]
assert {$rejected} {nonlength working units rejected}
set documents [llength [::GX::interactiveDocumentList]]
set rejected [catch {::GX::nativeCadSketchCreate .component {plane {origin {0 0 0} normal {0 0 0} u_axis {1 0 0}}}}]
assert {$rejected && [llength [::GX::interactiveDocumentList]]==$documents} {invalid plane rejected without orphan Document}
set controls [$sketch canvasControls]
assert {[::GX::native2DViewportPanelWidget [$host canvas] cad_tools] eq [winfo parent $controls]} {Canvas controls use the existing ViewportHost panel owner}
menu .cadmenu
$sketch menu .cadmenu
update
if {[llength $::backgroundErrors]} {puts stderr $::backgroundErrors}
assert {![llength $::backgroundErrors]} {actual GUI component has no background errors}
$sketch close
set sketch [::GX::nativeCadSketchCreate .component]
set advanced [$sketch get advanced]
$advanced construction start line
$advanced construction adopt {{point {0 0}} {point {2 0}}}
$advanced construction commit
$advanced construction start line
$advanced construction adopt {{point {2 0}} {point {2 2}}}
$advanced construction commit
set ids [dict values [dict get [$sketch state] object_map]]
$advanced topology apply join_points $ids {index 1 target_index 0 tolerance 1e-8}
assert {[dict size [dict get [$sketch state] relationship_map]]==1} {shared topology retains joined point identities}
set joined [$advanced topology apply join_path $ids {}]
assert {[dict get [[$sketch get context] object definition $joined] family] eq {composite_path}} {shared topology creates a retained joined Path}
set split [$advanced topology apply split_composition [list $joined] {index 1}]
assert {[llength $split]==2} {shared topology splits exact Path composition}
set compound [$advanced topology apply compound $ids {}]
assert {[dict get [[$sketch get context] object definition $compound] family] eq {compound}} {shared topology creates exact Compound}
set world [$sketch world_scene]
set partCount 0
dict for {id layer} [dict get $world layers] {if {[dict get $layer sketch_object]==$compound} {incr partCount}}
assert {$partCount==2} {Compound constituents remain separate Native3D lines}
set host [$sketch get host]
$host tool translate
$host activate [list $compound]
set native [$sketch get scene]
::GX::Native2D::core pivot $native custom {0 0}
$host begin translate [::GX::Native2D::core device $native {0 0}] [list $compound] free
$host move [::GX::Native2D::core device $native {3 2}]
$host finish
set moved [$sketch world_scene]
set first {}
dict for {id layer} [dict get $moved layers] {if {[dict get $layer sketch_object]==$compound} {set first [lindex [dict get $layer vertices] 0];break}}
assert {abs([lindex $first 0]-3)<1e-12 && abs([lindex $first 1]-2)<1e-12} {Native3D Compound view honors the native parent affine transform}
set advanced [$sketch get advanced]
set separate [$advanced topology apply separate [list $compound] {}]
assert {[llength $separate]==2} {shared topology separates exact Compound}
$advanced construction start path
$advanced construction adopt {{point {0 5}} {point {2 5}} {point {3 7}}}
set path [dict get [$advanced construction commit] id]
set split [$advanced topology apply split_path [list $path] {index 1}]
assert {[llength $split]==2} {shared topology splits retained straight Path}
$advanced construction start point
$advanced construction adopt {{point {4 4}}}
set point [dict get [$advanced construction commit] id]
set projected [$sketch world_scene]
set pointCells {}
dict for {id layer} [dict get $projected layers] {if {[dict get $layer sketch_object]==$point} {set pointCells [dict get $layer points]}}
assert {$pointCells eq {0}} {Native3D point uses an actual vertex cell}
viewportReady $sketch
assert {[dict get [$sketch state] renderer_error] eq {}} {actual Native3D renders points and transformed composition together}
set id [$sketch get document_id]
$sketch save
set viewport [$sketch get viewport]
::GX::native3DViewportNavigate $viewport orbit 120 40
set external [dict get [::GX::interactiveDocumentRead $id] payload]
dict set external external_revision 1
::GX::interactiveDocumentUpdate $id $external
assert {[catch {$sketch command line}]} {external Document revision invalidates edit scope}
$sketch destroy
set deadline [expr {[clock milliseconds]+3000}]
while {[dict get [::GX::native3DGuiHostApiInfoV2] retiring_workers]>0 && [clock milliseconds]<$deadline} {update;after 20}
assert {[catch {::GX::native3DViewportInspect $viewport}] && [dict get [::GX::native3DGuiHostApiInfoV2] retiring_workers]==0} {closing an active Native3D request releases its isolated worker}
assert {![llength $::backgroundErrors]} {no late GUI errors after pending close}
puts {PASS component smoke complete}
destroy .
exit 0
