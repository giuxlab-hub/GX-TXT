# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev104/* $out] || [file exists $out]} {error {New private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev104_print_recipe__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog;set ::GX::cfg(output_root) [file join $out Sessions]
::GX::createNewSession private_print_recipe
proc check {expression name} {if {![uplevel 1 [list expr $expression]]} {error "FAIL $name"};dict set ::checks $name PASS}
set checks {}
set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession math.numeric {dataset_id print_table contract table.generic storage hdf5 structured_metadata {fixture.synthetic 1}}]
set writer [::GX::datasetPublicationV2OpenWriter $plan];::GX::datasetPublicationV2DeclareDimension $writer row 3
foreach {id unit} {x m y V} {::GX::datasetPublicationV2DeclareVariable $writer $id [dict create dtype float64 unit $unit dimension_ids row]}
::GX::datasetPublicationV2WriteRange $writer x 0 {0 1 2};::GX::datasetPublicationV2WriteRange $writer y 0 {1 3 5};::GX::datasetPublicationV2Finalize $writer
set signature [::GX::printRecipeSourceSignature dataset print_table]
set scientific [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_table]]
set empty [::GX::printRecipeNew];set history [::GX::printRecipeHistoryCreate $empty]
set recipe $empty
set item [dict create id print_table_1 source_kind dataset source_id print_table presentation table source_signature $signature options {variables {x y} start 0 count 3} caption {Synthetic metre/volt table}]
dict set recipe items [list $item]
set history [::GX::printRecipeHistoryEdit $history $recipe {Add source table}]
check {[dict get [::GX::scientificHistoryState $history] items] eq [list $item]} history_exact_source
set changed $recipe;dict set changed page orientation landscape
set history [::GX::printRecipeHistoryEdit $history $changed {Landscape page}]
set undone [::GX::scientificHistoryNavigate framework.printing $history 1]
check {[::GX::scientificHistoryState $undone] eq $recipe} undo_document_layout
check {[::GX::scientificHistoryState [::GX::scientificHistoryNavigate framework.printing $undone 2]] eq $changed} redo_document_layout
foreach bad {duplicate rows range unknown schema} {
 set invalid $recipe
 switch $bad {
  duplicate {dict lappend invalid items $item}
  rows {dict set invalid page rows 9}
  range {dict set item options count 10001;dict set invalid items [list $item]}
  unknown {dict set invalid private_code {exec false}}
  schema {dict set invalid schema fake}
 }
 check {[catch {::GX::printRecipeValidate $invalid}]} reject_$bad
}
set doc [::GX::printRecipeDocumentSave $changed $history]
set id [dict get $doc id];set stamp [list [dict get $doc generation] [dict get $doc revision] [dict get $doc sha256]]
set read [::GX::printRecipeDocumentRead $id]
check {[dict get $read payload recipe] eq $changed && [dict get $read payload history] eq $history} session_document_reopen
set payload [dict get $read payload];dict set payload recipe title {Private parallel editor}
::GX::interactiveDocumentUpdate $id $payload
set current [::GX::printRecipeDocumentRead $id]
check {[catch {::GX::printRecipeDocumentSave $changed $history $id $stamp}] && [dict get [::GX::printRecipeDocumentRead $id] sha256] eq [dict get $current sha256]} stale_document_save_refused
check {[::GX::printRecipeSourceSignature dataset print_table] eq $signature && [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_table]] eq $scientific} scientific_payload_and_identity_unchanged
set description [::GX::printContentDescribe dataset print_table]
check {[dict get $description representations] eq {table xy metadata} && [dict get [lindex [dict get $description variables] 0] unit] eq {m}} truthful_typed_capability
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS cases $checks document $id scientific_sha256 $scientific];close $f
puts "PASS [dict size $checks] print document contracts"
