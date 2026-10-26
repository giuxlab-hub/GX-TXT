# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output
foreach kind {CONFIG DATA CACHE STATE} {set ::env(XDG_${kind}_HOME) [file join $output [string tolower $kind]]}
set argv0 __EXP01_NATIVE_RESOURCE_CONTRACT__;source [file join $root gxtxt_pipeline.tcl];::GX::defaults
load [file join $root core native3d bin libgx3de_viewer_tcl.so] Gx3deviewer
set model [dict create view [::GX::viewerSceneDefaults] layers {} graphics_policy [::GX::native3dGraphicsPolicy]]
dict set model graphics_policy execution Software
::GX3DEViewer::projection enable 1
::GX3DEViewer::render $model [file join $output initial.png] 640 480 full
set prior [::GX3DEViewer::projection snapshot]
set layer [dict create source_mode memory_geometry vertices {{-2 0 0} {2 0 0}} polylines {{0 1}} triangles {} base_color {1;0;0} line_width 2 point_size 5 backface_culling 0 scalar_coloring 0 scalar_array {} local_transform {} texture {} opacity 1 visible 1 representation wireframe]
set changes [dict create A [dict create revision rev1 visible 1 layers [dict create curve $layer]]]
set admitted [::GX3DEViewer::sketch_resources sync $changes [file join $output admitted.png]]
if {[dict get $admitted resources]!=1 || [dict get $admitted points]!=2} {error {Native admission count differs}}
if {$prior ne [::GX3DEViewer::projection snapshot]} {error {Actor admission changed camera frame}}
set unchanged [::GX3DEViewer::sketch_resources sync {A {revision rev1 visible 1 layers deliberately_not_parsed}} {}]
if {[dict get $unchanged changed]!=0 || [dict get $unchanged reuses]!=1} {error {Unchanged resource reparsed}}
set bad [dict replace $changes A [dict create revision rev2 visible 1 layers [dict create curve [dict replace $layer vertices {{0 0 bad} {1 1 1}}]]]]
if {![catch {::GX3DEViewer::sketch_resources sync $bad {}} failure]} {error {Invalid resource accepted}}
set rejected [::GX3DEViewer::sketch_resources status {} {}]
if {[dict get $rejected resource_states A revision] ne {rev1}} {error {Rejected batch retired previous actor}}
set hidden [::GX3DEViewer::sketch_resources sync {A {revision rev1 visible 0}} {}]
if {[dict get $hidden resource_states A visible]} {error {Visibility not applied}}
::GX3DEViewer::render $model [file join $output reset.png] 640 480 full
set replay [::GX3DEViewer::sketch_resources status {} {}]
if {[dict get $replay resources]!=1 || [dict get $replay replays]!=1} {error {Base scene reset lost resident resource}}
set removed [::GX3DEViewer::sketch_resources sync {A remove} {}]
if {[dict get $removed resources]!=0 || [dict get $removed actors]!=0} {error {Resource not disposed}}
::GX3DEViewer::close
set f [open [file join $output RESULT.tcldict] w];puts $f [dict create status PASS admitted $admitted unchanged $unchanged rejected_error $failure rejected $rejected hidden $hidden replay $replay disposed $removed];close $f
puts PASS
