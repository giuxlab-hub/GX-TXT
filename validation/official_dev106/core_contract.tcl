# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev106/* $out] || [file exists $out]} {error {Fresh private dev106 output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev106_contract__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet scripts.user_root [file join $out user_scripts]
::GX::datasetPreviewCacheInit
::GX::configurationSet preview.cache_enabled 0
set ::GX::cfg(output_root) [file join $out old_location]
::GX::createNewSession scientific_A
set session $::GX::currentSession
::GX::datasetPreviewCacheInit
::GX::configurationSet preview.cache_enabled 0
::GX::configurationSet storage.session_root [file join $out configured_R]
::GX::configurationApply
set storageBefore [list [::GX::configurationGet storage.session_root] $::GX::cfg(output_root) [array get ::GX::workspaceDir]]
set importEvidence {};set checks {};proc check {expression name} {if {![uplevel 1 [list expr $expression]]} {error "FAIL $name"};dict set ::checks $name PASS;puts "PASS $name";flush stdout}
proc writefile {path text} {file mkdir [file dirname $path];set f [open $path w];fconfigure $f -encoding utf-8 -translation lf;puts -nonewline $f $text;close $f;return $path}
set inputs [file join $out external_inputs]
foreach {extension id source} [list md markdown_doc "# Scientific µ\n\n**Measured** values.\n- one\n" htm htm_doc {<h1>HTM µ</h1><p>Preserved</p>} html html_doc {<h1>Result µ</h1><p><strong>Measured</strong> result</p><script>throw Error('never')</script>} xml xml_doc {<?xml version="1.0"?><r xmlns:p="urn:test"><p:sample unit="µm">A &amp; B</p:sample></r>} js javascript_doc {const result = 'µ'; /* inert */}] {
    set sourceFile [writefile [file join $inputs "science µ source.$extension"] $source]
    set sourceHash [::GX::sha256File $sourceFile]
    set ::GX::moduleCfg(acq.text_document,destination) dataset
    set result [::GX::acquisitionHandlerImportSourcesToSession acq.text_document $session [list $sourceFile] $id {} {}]
    check {[lindex $result 0] eq $id} import_$extension
    set payload [::GX::sessionInspectionDatasetPayload $id]
    dict set importEvidence $id [dict create outcome canonical_dataset source_original_path $sourceFile source_sha256 $sourceHash payload $payload registry_relative_path [::GX::datasetField $id path] session $session storage_before $storageBefore storage_after [list [::GX::configurationGet storage.session_root] $::GX::cfg(output_root) [array get ::GX::workspaceDir]]]
    check {[string first "$session/" [dict get $payload path]]==0 && [::GX::sha256File [dict get $payload path]] eq $sourceHash} containment_and_sha_$extension
    check {[list [::GX::configurationGet storage.session_root] $::GX::cfg(output_root) [array get ::GX::workspaceDir]] eq $storageBefore} storage_unchanged_$extension
}
check {[::GX::datasetDocumentKind markdown_doc] eq {markdown}} markdown_semantic_identity
check {[::GX::datasetDocumentKind html_doc] eq {html}} html_semantic_identity
check {[::GX::datasetDocumentKind xml_doc] eq {xml}} xml_semantic_identity
set beforeIds [::GX::datasetRegistryIds]
set failed [catch {::GX::acquisitionHandlerImportSourcesToSession acq.text_document $session [list $sourceFile] {bad id with spaces} {} {}} reason options]
check {$failed && [string match {*bad id with spaces*} $reason] && [::GX::datasetRegistryIds] eq $beforeIds} invalid_id_before_writes
set f [open [file join $out invalid_id.tcldict] w];puts $f [dict create error $reason options $options];close $f
set pythonSource [writefile [file join $inputs {user numerical script.py}] "import sys\nprint('OUTPUT α 42')\nprint('STDERR β', file=sys.stderr)\n"]
set ::GX::moduleCfg(acq.text_document,destination) auto
set receipt [::GX::acquisitionHandlerImportSourcesToSession acq.text_document $session [list $pythonSource] user_python {} {}]
check {[dict get $receipt outcome] eq {registered_session_script} && [dict get $receipt reference] eq {session:user_python}} true_script_import
check {[::GX::datasetRegistryIds] eq $beforeIds} script_only_no_dataset
dict set importEvidence user_python [dict merge $receipt [dict create source_original_path $pythonSource registered [::GX::scriptRegistryDescribe session:user_python]]]
check {[llength [::GX::scriptRegistryList session]]==1} visible_user_script_no_service
set job [::GX::scriptJobSubmit session:user_python {}]
set completed [::GX::scriptJobWait [dict get $job id] 120]
check {[dict get $completed state] eq {COMPLETED}} actual_python_job
set stdout [::GX::scriptJobStreamRead [dict get $job id] stdout]
set stderr [::GX::scriptJobStreamRead [dict get $job id] stderr]
set diagnostics [::GX::scriptJobStreamRead [dict get $job id] diagnostics]
check {[string match {*OUTPUT α 42*} [dict get $stdout content]] && ![string match {*STDERR β*} [dict get $stdout content]]} real_stdout_separation
check {[string match {*STDERR β*} [dict get $stderr content]] && ![string match {*OUTPUT α 42*} [dict get $stderr content]]} real_stderr_separation
check {[string match {*terminal*} [dict get $diagnostics content]] && ![string match {*OUTPUT α 42*} [dict get $diagnostics content]]} genuine_diagnostic_events
set pubOut [::GX::scriptJobStreamPublish [dict get $job id] stdout user_output]
set pubLog [::GX::scriptJobStreamPublish [dict get $job id] diagnostics user_diagnostics]
check {[dict get $pubOut dataset_id] eq {user_output} && [dict get $pubLog dataset_id] eq {user_diagnostics} && [dict get $pubOut sha256] ne [dict get $pubLog sha256]} independent_stream_publications
set beforeJobs [llength [::GX::scriptJobList]]
::GX::scriptRegistrySave session missing_import {Missing import test} {import gxtxt_deliberately_missing_dev106_abc} {language Python}
check {[catch {::GX::scriptJobSubmit session:missing_import {}} reason] && [string match {*MISSING*} $reason] && [llength [::GX::scriptJobList]]==$beforeJobs} static_missing_import_refuses_before_job
::GX::configurationSet preview.cache_enabled 1
set key [::GX::datasetPreviewCacheRequest markdown_doc {}]
set until [expr {[clock milliseconds]+120000}]
while {[dict get [::GX::datasetPreviewCacheStatus $key] status] eq {preparing} && [clock milliseconds]<$until} {after 50 {set ::tick 1};vwait ::tick}
set cache [::GX::datasetPreviewCacheStatus $key]
check {[dict get $cache status] eq {ready}} actual_private_preview_service
check {[llength [::GX::scriptRegistryList session]]==2 && ![file exists [file join $session scripts registered gx-core-dataset-preview]]} no_registered_preview_worker
check {[catch {::GX::scriptJobSubmit core-service:dataset-preview {}}]} ordinary_api_refuses_service
set inventory [::GX::sessionInspectionResults $session]
check {![string match {*core-service*} [dict get $inventory records]] && [string match {*Acquisition/import*} [dict get $inventory records]]} results_include_imports_exclude_services
set d [::GX::xmlDocument create samples];set node [::GX::xmlDocument root $d]
::GX::xmlDocument attribute $d $node unit {µm & <value>}
set child [::GX::xmlDocument append $d $node sample {A & B < C}]
set serialized [::GX::xmlDocument serialize $d 1]
set export [::GX::xmlDocument write $d [file join $out exported.xml]]
check {[string match {*&amp;*} $serialized] && [file isfile [file join $out exported.xml]]} native_xml_create_write
check {[catch {::GX::xmlDocument parse {<!DOCTYPE r [<!ENTITY ext SYSTEM "file:///etc/passwd">]><r>&ext;</r>}}]} xml_xxe_refused
::GX::xmlDocument release $d
check {[catch {::GX::xmlDocument root $d}]} xml_stale_handle
set octaveSource [writefile [file join $inputs {genuine Octave Ω source.m}] "disp('TRUE_IMPORTED_OCTAVE');\n"]
set priorIds [::GX::datasetRegistryIds]
set ::GX::moduleCfg(acq.text_document,destination) session_script;set ::GX::moduleCfg(acq.text_document,language) octave
set octaveReceipt [::GX::acquisitionHandlerImportSourcesToSession acq.text_document $session [list $octaveSource] user_octave {} {}]
dict set importEvidence user_octave [dict merge $octaveReceipt [dict create source_original_path $octaveSource registered [::GX::scriptRegistryDescribe session:user_octave]]]
check {[dict get $octaveReceipt reference] eq {session:user_octave} && [dict get [::GX::scriptRegistryDescribe session:user_octave] language] eq {Octave}} explicit_genuine_octave_source_import
check {[::GX::datasetRegistryIds] eq $priorIds} octave_script_import_no_dataset
set octaveJob [::GX::scriptJobSubmit session:user_octave {}];set octaveJob [::GX::scriptJobWait [dict get $octaveJob id] 90]
check {[dict get $octaveJob state] eq {COMPLETED} && [string match *TRUE_IMPORTED_OCTAVE* [dict get [::GX::scriptJobStreamRead [dict get $octaveJob id] stdout] content]]} imported_octave_actual_run
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS checks $checks import_evidence $importEvidence session $session job $job cache $cache storage $storageBefore];close $f
puts "PASS [dict size $checks] actual CORE checks"
