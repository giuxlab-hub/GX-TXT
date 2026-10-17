# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev104/* $out] || [file exists $out]} {error {New private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev104_builder_contract__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc check {expression name} {if {![uplevel 1 [list expr $expression]]} {error "FAIL $name"};dict set ::checks $name PASS}
set checks {}
proc add {model id type parent properties layout} {return [::GX::viewerGuiDesignModelEdit $model add [dict create id $id type $type parent $parent properties $properties layout $layout]]}
set model [::GX::viewerGuiDesignModelCreate [::GX::viewerGuiDesignNew {Minimal scientific Viewer}]]
set model [::GX::viewerGuiDesignModelEdit $model metadata module_id viewer.dev104_demo_a]
set model [::GX::viewerGuiDesignModelEdit $model metadata provider_id dev104_demo_a]
set model [add $model inspect action toolbar {label Inspect action inspect tooltip {Unconnected scientific handler} shortcut F5} {row 0 column 0}]
set model [add $model file_menu menu menubar {label Actions actions {inspect}} {}]
set model [add $model settings section inspector {title Settings} {row 0 column 0}]
set model [add $model note field settings {label {Sample label} datatype string default {Private fixture}} {row 0 column 0}]
set model [add $model view native2d canvas {title {Scientific viewport}} {row 0 column 0 weight 1 sticky nsew}]
set model [add $model status status footer {text {No scientific action has run.}} {row 0 column 0}]
foreach type {help workspace history} {set model [add $model ${type}_controls $type footer {} {}]}
set design [dict get $model design]
set duplicated [::GX::viewerGuiDesignModelEdit $model duplicate settings]
check {[llength [dict get $duplicated design components]]==[llength [dict get $design components]]+2} duplicate_subtree
set undone [::GX::viewerGuiDesignModelNavigate $duplicated undo]
check {[dict get $undone design] eq $design} undo_exact
check {[dict get [::GX::viewerGuiDesignModelNavigate $undone redo] design] eq [dict get $duplicated design]} redo_exact
check {[catch {::GX::viewerGuiDesignModelEdit $model reparent settings note}]} invalid_container
check {[catch {::GX::viewerGuiDesignModelEdit $model reparent settings settings}]} cycle_refused
set copied [::GX::viewerGuiDesignModelEdit $model paste [lrange [dict get $design components] 2 3] inspector [dict get $design handlers]]
check {[llength [dict get $copied design components]]==[llength [dict get $design components]]+2} paste_subtree
set changed [::GX::viewerGuiDesignModelEdit $model bind note note_changed presentation]
check {[dict get $changed design handlers note_changed effect] eq {presentation} && [dict get [lindex [dict get $changed design components] 3] properties change_action] eq {note_changed}} input_event_contract
set constrained [::GX::viewerGuiDesignModelEdit $model constraints settings {rowspan 3 minimum_width 240 padding 9}]
set duplicate [::GX::viewerGuiDesignModelEdit $constrained duplicate settings]
set rootCopy [lindex [dict get $duplicate design components] end-1]
check {[dict get $rootCopy layout row]==3 && [dict get $rootCopy layout rowspan]==3 && [dict get $rootCopy layout minimum_width]==240 && [dict get $rootCopy layout padding]==9} duplicate_span_constraints
set packed [::GX::viewerGuiDesignModelCreate [::GX::viewerGuiDesignNew {Packed containers}]]
set packed [add $packed first section inspector {title First} {manager pack fill x minimum_width 220}]
set packed [add $packed child field first {label Child datatype string default one} {row 0 column 0}]
set packed [add $packed second section inspector {title Second} {manager pack fill x}]
set packed [::GX::viewerGuiDesignModelEdit $packed reorder first 1]
set packedIds {};foreach item [dict get $packed design components] {lappend packedIds [dict get $item id]}
check {[lsearch -exact $packedIds second]<[lsearch -exact $packedIds first] && [lsearch -exact $packedIds first]<[lsearch -exact $packedIds child]} pack_reorder_parent_before_child
set packed [::GX::viewerGuiDesignModelEdit $packed paste [lrange [dict get $design components] 2 3] inspector [dict get $design handlers]]
set pasted [lindex [dict get $packed design components] end-1]
check {[dict get $pasted layout manager] eq {pack} && ![dict exists $pasted layout row]} paste_adopts_target_geometry
check {[catch {::GX::viewerGuiDesignModelEdit $packed swap first second}]} pack_grid_swap_refused
foreach kind {duplicate version handler callback property} {
 set invalid $design
 switch $kind {
  duplicate {dict lappend invalid components [lindex [dict get $design components] 0]}
  version {dict set invalid requirements UI_FIELD_API_v1 999}
  handler {dict set invalid handlers {}}
  callback {dict set invalid handlers inspect {arguments wrong effect unbound}}
  property {set c [lindex [dict get $design components] 0];dict set c properties invented 1;dict set invalid components [lreplace [dict get $design components] 0 0 $c]}
 }
 check {[catch {::GX::viewerGuiDesignValidate $invalid}]} reject_$kind
}
::GX::viewerGuiDesignSave [file join $out demo_a.gxtxt-viewer] $design
check {[::GX::viewerGuiDesignRead [file join $out demo_a.gxtxt-viewer]] eq $design} inert_roundtrip
set fixture [open [file join $out malicious.gxtxt-viewer] w];puts $fixture {exec touch SHOULD_NOT_EXIST};close $fixture
check {[catch {::GX::viewerGuiDesignRead [file join $out malicious.gxtxt-viewer]}] && ![file exists SHOULD_NOT_EXIST]} not_evaluated
set b [::GX::viewerGuiDesignModelCreate [::GX::viewerGuiDesignNew {Scientific XY Viewer}]]
foreach {key value} {module_id viewer.dev104_demo_b provider_id dev104_demo_b} {set b [::GX::viewerGuiDesignModelEdit $b metadata $key $value]}
set col 0;foreach {id label} {load {Load selected Dataset} fit Fit zoom_in {Zoom in} zoom_out {Zoom out}} {set b [add $b $id action toolbar [dict create label $label action $id] [dict create row 0 column $col]];incr col}
set b [add $b source section inspector {title {Canonical scientific source}} {row 0 column 0}]
set b [add $b dataset dataset_selector source {label Dataset} {row 0 column 0}]
set b [add $b x_variable field source {label {X Variable ID} datatype string default x} {row 1 column 0}]
set b [add $b y_variable field source {label {Y Variable ID} datatype string default y} {row 2 column 0}]
set b [add $b xy native2d canvas {title {Private scientific XY curve}} {row 0 column 0 weight 1 sticky nsew}]
foreach type {help workspace history} {set b [add $b ${type}_controls $type footer {} {}]}
::GX::viewerGuiDesignSave [file join $out demo_b.gxtxt-viewer] [dict get $b design]
set c [::GX::viewerGuiDesignModelEdit $model metadata module_id viewer.dev104_demo_c]
set c [::GX::viewerGuiDesignModelEdit $c metadata provider_id dev104_demo_c]
set c [::GX::viewerGuiDesignModelEdit $c metadata title {Workbench-style interface}]
set c [add $c layers section inspector {title {Presentation layers}} {row 1 column 0}]
set c [add $c visible toggle layers {label {Show reference layer} default 1} {row 0 column 0}]
set c [add $c tabs tabs inspector {} {row 2 column 0}]
set c [add $c inputs tab tabs {title Inputs} {}]
set c [add $c diagnostics tab tabs {title Diagnostics} {}]
set c [add $c message label diagnostics {text {Scientific CAD callbacks remain with their original owner.}} {row 0 column 0}]
::GX::viewerGuiDesignSave [file join $out demo_c.gxtxt-viewer] [dict get $c design]
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS cases $checks];close $f
puts "PASS [dict size $checks] Viewer design contracts"
