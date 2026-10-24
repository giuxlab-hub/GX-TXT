lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}};file mkdir $output
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache GXTXT_RESOURCE_ROOT resources GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p016_independent_cad__;source [file join $framework gxtxt_pipeline.tcl];::GX::defaults;::GX::native2DEnsure
proc check {v label} {if {![uplevel 1 [list expr $v]]} {error "FAIL: $label"};puts "PASS: $label";flush stdout}
set scene [::GX::Native2D::core scene]
set cad [::GX::native2DCadCreate $scene]
check {[dict get [$cad selection snapshot] references] eq {}} {independent CORE CAD starts with one empty native selection}
set a [$cad object create {family line controls {{0 0} {2 0}}} 64]
set b [$cad object create {family quadratic_bezier controls {{2 0} {3 1} {4 0}}} 64]
set controls [$cad control inspect $a];check {[llength $controls]==2} {actual defining controls exposed without Viewer internals}
set r [$cad selection reference $a object 0]
$cad selection apply [list [dict create kind object id $a index 0]]
check {[llength [dict get [$cad selection snapshot] references]]==1} {one native semantic set and typed reference projection}
set reference [$cad selection reference $a control 1000000000]
set options [$cad relationship options [list $reference]]
set fixed [$cad relationship apply 0 [dict get $options fixed]]
check {[dict get $fixed valid]} {constraint creation reuses original scientific authority}
$cad relationship remove [dict get $fixed id]
set definition [$cad control preview [$cad selection reference $b control 1000000001] {3 1.2}]
$cad control edit [$cad selection reference $b control 1000000001] {3 1.2}
check {[dict get [$cad object definition $b] controls] eq [dict get $definition controls]} {spline/Bezier defining edit follows native preview and commit contract}
set joined [$cad object join [list $a $b] {} 2 1e-9]
check {[llength [$cad component list $joined]]==2} {connected retained constituents addressed by stable native IDs}
set copies [$cad object separate $joined];check {[llength $copies]==2} {generic Separate exposes exact constituents preserving source}
set style [$cad object style $a];$cad object style $a {selected 1}
::GX::Native2D::core gizmo $scene {visible 1 mode translate}
$cad gesture begin free {100 100} [list $a]
set proposal [$cad gesture plan {120 100} 0];$cad gesture apply
check {[dict get [$cad state] native_drag]} {generic plan/apply owns existing native drag}
$cad gesture cancel
check {![::GX::Native2D::core drag_active $scene]} {generic cancellation releases native transaction}
$cad gesture begin free {100 100} [list $a];$cad gesture plan {125 100};$cad gesture apply;$cad gesture commit
check {![::GX::Native2D::core drag_active $scene]} {native commit permits subsequent operations}
set region [$cad selection region [list $a $b] {{-100 -100} {100 -100} {100 100} {-100 100}} 128 object]
$cad selection apply $region
check {[llength [dict get [$cad selection snapshot] objects]]==2} {native region and multiple selection independently reusable}
set segment [$cad selection reference $a segment 0]
set spec [$cad relationship dimension_infer [list $segment] {1 -1}]
set dimension [$cad relationship dimension_apply 0 $spec 1 {1 -1}]
check {[dict get $dimension valid] && [dict get [$cad relationship dimension_geometry [dict get $dimension id]] driven]} {dimension inference and annotation use native solver authority}
$cad relationship enable [dict get $dimension id] 0
$cad relationship remove [dict get $dimension id]
check {[llength [$cad object bounds $a]]==4} {native transformed bounds exposed without layout knowledge}
::GX::Native2D::core destroy $scene
check {![dict get [$cad state] alive]} {scientific scene closure revokes managed CAD reference}
check {[catch {$cad object controls $a}]} {closed source cannot be reused}
::GX::native2DCadDispose $cad
check {![llength [info commands $cad]] && ![llength [info commands ::GX::CurveWorkbench::open]]} {independent consumer disposes without importing Curve Workbench}
set f [open [file join $output RESULT.txt] w];puts $f PASS;close $f
