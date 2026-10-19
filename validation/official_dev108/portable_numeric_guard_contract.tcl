# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
if {[info exists ::env(DISPLAY)] || [file exists $out] || ![string match */_private_dev108/portable-numeric-guard* [file normalize $out]]} {error {Fresh private headless contract only}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __portable_numeric_guard__;source [file join $root gxtxt_pipeline.tcl];set argv {};::GX::defaults;::GX::loadModuleCatalog
set imported [file join [file dirname $root] _private_dev108 qa_ac040_01 Sessions imported_author192_ac040]
::GX::openSessionPath $imported
set ws [::GX::sessionWorkspaceGet idoc_0018]
set desc [dict get $ws payload domain_state numeric_results ac_form]
set doc [::GX::interactiveDocumentRead [dict get $desc document_id]]
set originalDoc $doc;set request [dict get $doc payload request]
set saved [dict get $request dataset_revision];set current [::GX::datasetRevisionToken [dict get $request dataset_id]]
if {$current eq $saved || ![::GX::_datasetRevisionPortableEqual $current $saved]} {error {Actual imported pristine token not accepted}}
set denials {}
foreach {name candidate} [list schema [lreplace $saved 0 0 dataset-revision-v2] id [lreplace $saved 2 2 other_dataset] record [lreplace $saved 3 3 [dict replace [lindex $saved 3] changed_field scientific_change]] metadata [lreplace $saved 4 4 [string repeat 0 64]] short [lrange $saved 0 3] extra [concat $saved extra] malformed "\{"] {
 if {[::GX::_datasetRevisionPortableEqual $current $candidate]} {error "Changed/malformed token accepted: $name"}
 lappend denials $name
}
# Exercise the exact existing guard with only its presentation lifetime adapter
# substituted in this headless contract. Scientific Document guard remains real.
rename ::GX::viewerGuiDesignGuard ::GX::contractOriginalViewerGuard
proc ::GX::viewerGuiDesignGuard {window} {expr {$window eq {contract_window}}}
try {
 if {![catch {::GX::_viewerGuiNumericGuard contract_window $request}]} {error {Live strict guard accepted foreign carrier}}
 set rebound [::GX::_viewerGuiNumericGuard contract_window $request 1]
 if {[dict get $rebound dataset_revision] ne $current} {error {Ephemeral request not bound to current carrier}}
 ::GX::_viewerGuiNumericGuard contract_window $rebound
 foreach {dataset token} [dict get $rebound source_revisions] {if {$token ne [::GX::datasetRevisionToken $dataset]} {error {Pointwise source not rebound}}}
 set bad $request;dict set bad dataset_revision [lreplace $saved 4 4 [string repeat 0 64]]
 if {![catch {::GX::_viewerGuiNumericGuard contract_window $bad 1}]} {error {Changed metadata accepted on restore}}
 if {[::GX::interactiveDocumentRead [dict get $desc document_id]] ne $originalDoc || [::GX::sessionWorkspaceGet idoc_0018] ne $ws} {error {Immutable authority changed}}
} finally {rename ::GX::viewerGuiDesignGuard {};rename ::GX::contractOriginalViewerGuard ::GX::viewerGuiDesignGuard}
set f [open [file join $out PORTABLE_NUMERIC_GUARD_CONTRACT.tcldict] w];puts $f [dict create status PASS_SAVED_CONTENT_REVALIDATION_STRICT_LIVE_GUARD token_differences Session_path denials $denials original_result_document $desc immutable_document_unchanged 1 canonical_workspace_unchanged 1 live_foreign_carrier_denied 1 rebound_current_live_guard_passed 1 computation none publication none qualification {Headless guard contract; actual normal GUI restoration independently required}];close $f
puts PASS_SAVED_CONTENT_REVALIDATION_STRICT_LIVE_GUARD
