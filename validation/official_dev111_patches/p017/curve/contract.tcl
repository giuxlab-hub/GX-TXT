# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {usage: contract.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_CURVE_HISTORY_CONTRACT__
set nativePins {}
foreach relative {core/history/history_engine.cpp core/history/libgxtxt_history.so core/tcl/scientific_history_native.tcl core/tcl/scientific_recipe_history.tcl core/tcl/interactive_document_api_v1.tcl core/tcl/parameter_service_api_v1.tcl core/tcl/native2d_viewport_host_v1.tcl} {
    dict set nativePins $relative [lindex [exec sha256sum [file join $framework $relative]] 0]
}
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk;wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_CURVE_HISTORY
::GX::modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
namespace eval ::T {variable checks {};variable projections 0;variable exports 0;variable nativeCalls {record 0 flush 0 checkpoint 0};variable payloadReads 0}
proc ::T::check {name condition} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $name"};lappend ::T::checks [dict create name $name status PASS];puts "PASS $name";flush stdout}
proc ::T::write {name data} {set f [open [file join $::out $name] w];try {puts $f $data} finally {close $f}}
proc ::T::projection {command operation} {incr ::T::projections}
proc ::T::payloadRead {command operation} {incr ::T::payloadReads}
proc ::T::native {command operation} {set action [lindex $command 1];if {[dict exists $::T::nativeCalls $action]} {dict incr ::T::nativeCalls $action}}
proc ::T::exported {command operation} {incr ::T::exports}
proc ::T::rejectProjection {command operation} {error {Controlled projection failure after scientific acceptance}}
proc bgerror {message} {lappend ::T::background $message;puts stderr "BACKGROUND $message"}
try {
    set w [::GX::CurveWorkbench::open {workspace_id new}];update
    ::T::check {manual Curve attaches shared CORE History and strip} {$::GX::CurveWorkbench::st($w,historyReady) && [winfo exists $w.historyStrip] && ![info exists ::GX::CurveWorkbench::st($w,undo)] && ![info exists ::GX::CurveWorkbench::st($w,scientificRecipe)]}
    set values {family line controls {{0 0} {1 1}} radius_x 1 radius_y 1 rotation 0 angle_start 0 angle_sweep 360 closed 0 samples 17 name {History line}}
    ::GX::CurveWorkbench::_sketchApply $w [::GX::interactiveDocumentSessionToken] {} $values
    set id $::GX::CurveWorkbench::st($w,active)
    ::T::check {existing retained primitive is immediately undoable} {[dict get [::GX::scientificHistoryViewerStatus $w] cursor]>=1 && [dict exists [::GX::scientificHistoryViewerState $w] $id]}
    ::GX::CurveWorkbench::_saveExplicit $w
    set document $::GX::CurveWorkbench::st($w,document)
    set revision [dict get [::GX::interactiveDocumentMetadata $document] revision]
    set count [dict get [::GX::scientificHistoryViewerStatus $w] count]
    trace add execution ::GX::CurveWorkbench::_historyProject enter ::T::projection
    trace add execution ::GX::scientificHistoryViewerRecord enter ::T::exported
    trace add execution ::GX::historyNative enter ::T::native
    for {set i 0} {$i<40} {incr i} {::GX::CurveWorkbench::_cadTransformApply $w translate [list $id] {0 0} {dx 0.01 dy 0.001}}
    set last [::GX::scientificHistoryViewerState $w]
    set noOpCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
    ::GX::CurveWorkbench::_history $w [::GX::CurveWorkbench::_snapshotIds $w [list $id]] [list $id]
    ::T::check {unchanged scientific state does not fabricate a History step} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$noOpCount}
    ::T::check {all actual moves retained beyond former private30 cap} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$count+40}
    ::T::check {normal moves never export whole History or project Documents} {$::T::exports==0 && $::T::projections==0 && [dict get [::GX::interactiveDocumentMetadata $document] revision]==$revision}
    ::GX::CurveWorkbench::undo $w
    set prior [::GX::scientificHistoryViewerState $w]
    ::T::check {Undo restores exact retained geometry and keeps Redo} {[dict get $prior $id sketch_definition] eq [dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] && [dict get [::GX::scientificHistoryViewerStatus $w] cursor]==$count+39}
    ::GX::scientificHistoryViewerBrowse $w [dict get [::GX::scientificHistoryViewerStatus $w] count] index
    ::T::check {numeric browse can inspect the final future retained operation} {[::GX::CurveWorkbench::_historyBrowsing $w] && [dict get [::GX::scientificHistoryViewerState $w] $id sketch_definition] eq [dict get $last $id sketch_definition]}
    ::GX::scientificHistoryViewerNavigate $w latest
    ::GX::CurveWorkbench::redo $w
    ::T::check {Redo returns exact scientific snapshot without projection} {[dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] eq [dict get $last $id sketch_definition] && $::T::exports==0 && $::T::projections==0}
    ::T::check {ordinary moves and navigation never wait or export inside native CORE} {[dict get $::T::nativeCalls record]==0 && [dict get $::T::nativeCalls flush]==0 && [dict get $::T::nativeCalls checkpoint]==0}
    trace remove execution ::GX::historyNative enter ::T::native
    trace remove execution ::GX::CurveWorkbench::_historyProject enter ::T::projection
    trace remove execution ::GX::scientificHistoryViewerRecord enter ::T::exported
    ::GX::CurveWorkbench::undo $w
    set recipe [::GX::CurveWorkbench::_recipeCapture [dict create document_id $document]]
    ::T::check {explicit recipe exports cursor while native future remains} {[llength [dict get $recipe steps]]==$count+39 && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$count+40}
    ::GX::CurveWorkbench::redo $w
    ::GX::CurveWorkbench::_saveExplicit $w
    set ::T::payloadReads 0
    trace add execution ::GX::interactiveDocumentRead enter ::T::payloadRead
    ::GX::CurveWorkbench::_snapshotIds $w [list $id]
    trace remove execution ::GX::interactiveDocumentRead enter ::T::payloadRead
    ::T::check {first ordinary affected-state capture after Save never reads accumulated History payload} {$::T::payloadReads==0}
    set persisted [::GX::interactiveDocumentRead $document]
    ::T::check {Save projects complete compatible recipe and verified durable state} {[llength [dict get $persisted payload cad_workspace scientific_recipe steps]]==[dict get [::GX::scientificHistoryViewerStatus $w] count] && [dict get [::GX::scientificHistoryViewerStatus $w] pending]==0}
    ::GX::CurveWorkbench::_close $w
    set w [::GX::CurveWorkbench::open [dict create workspace_id $document]];update
    ::T::check {reopen retains full timeline logical identity and exact geometry} {[dict get [::GX::scientificHistoryViewerStatus $w] count]>=$count+40 && [dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] eq [dict get $last $id sketch_definition]}
    set token [::GX::CurveWorkbench::_parameterBind $w]
    ::GX::parameterSet $token history_length {formula {2+3} unit mm}
    ::T::check {parameter formula accepted as same shared History} {[dict get [::GX::parameterDefinitions $token] history_length formula] eq {2+3}}
    ::GX::parameterSet $token history_length {formula {4+5} unit mm}
    ::GX::CurveWorkbench::undo $w
    ::T::check {Undo restores exact parameter formula} {[dict get [::GX::parameterDefinitions $token] history_length formula] eq {2+3}}
    ::GX::CurveWorkbench::redo $w
    ::T::check {Redo restores exact parameter formula} {[dict get [::GX::parameterDefinitions $token] history_length formula] eq {4+5}}
    set parameterCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
    ::GX::CurveWorkbench::_timelineBrowse $w [expr {$parameterCount-1}]
    ::T::check {browse uses read view without changing canonical parameters} {[dict get [::GX::parameterDefinitions $token] history_length formula] eq {2+3} && [dict get [::GX::interactiveDocumentRead $document] payload workspace_metadata parameters history_length formula] eq {4+5}}
    ::GX::scientificHistoryViewerNavigate $w latest
    ::T::check {Latest closes parameter read view and preserves canonical definition} {[dict get [::GX::parameterDefinitions $token] history_length formula] eq {4+5}}
    set context [::GX::CurveWorkbench::_extensionContext $w]
    ::T::check {extension context preserves canonical revision schema} {[dict get $context revision]==[dict get [::GX::interactiveDocumentMetadata $document] revision] && ![dict exists $context history_revision]}
    set tx [::GX::CurveWorkbench::_extensionBegin $context]
    set applied [::GX::CurveWorkbench::_extensionApply $tx {status ok operations {}}]
    set returned [::GX::CurveWorkbench::_extensionCommit $tx $applied]
    ::T::check {existing extension transaction ends with explicit projection barrier} {[dict get $returned revision]==[dict get [::GX::interactiveDocumentMetadata $document] revision] && [dict get [::GX::scientificHistoryViewerStatus $w] pending]==0}
    ::GX::datasetPublicationV2PublishSeries $::GX::currentSession math.numeric [dict create dataset_id history_source contract table.generic storage csv x_values {0 1 2 3} y_values {1 3 5 7} x_variable {variable_id source_x unit mm} y_variable {variable_id source_y unit mm}]
    set sourceHash [dict get [::GX::sessionInspectionDatasetPayload history_source] sha256]
    ::GX::CurveWorkbench::_sourceOpen $w
    ::GX::CurveWorkbench::_sourceAdd $w
    set sourceId $::GX::CurveWorkbench::st($w,active)
    set fingerprint [dict get $::GX::CurveWorkbench::st($w,curves) $sourceId source_descriptor source_id]
    ::GX::CurveWorkbench::_saveExplicit $w
    ::GX::CurveWorkbench::undo $w
    ::GX::CurveWorkbench::redo $w
    ::T::check {Dataset History navigation preserves original immutable source fingerprint} {[dict get [::GX::sessionInspectionDatasetPayload history_source] sha256] eq $sourceHash && [dict get $::GX::CurveWorkbench::st($w,curves) $sourceId source_descriptor source_id] eq $fingerprint}
    ::GX::CurveWorkbench::_close $w
    set w [::GX::CurveWorkbench::open [dict create workspace_id $document]];update
    ::T::check {save reopen retains Dataset binding and source authority} {[dict get $::GX::CurveWorkbench::st($w,curves) $sourceId source_descriptor source_id] eq $fingerprint && [dict get [::GX::sessionInspectionDatasetPayload history_source] sha256] eq $sourceHash}
    # Controlled owner loss: drain/close its native writer without projection,
    # release only this owned GUI/science, then recover through the public choice.
    set ::GX::CurveWorkbench::st($w,objectSelection) [list $id]
    ::GX::CurveWorkbench::_cadTransformApply $w translate [list $id] {0 0} {dx .123 dy .456}
    set expected [dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition]
    ::GX::scientificHistoryViewerDetach $w 0
    set ::GX::CurveWorkbench::st($w,historyReady) 0
    set ::GX::CurveWorkbench::st($w,historyDiscard) 1
    ::GX::CurveWorkbench::_close $w
    set w [::GX::CurveWorkbench::open [dict create workspace_id $document recovery_choice recover]];update
    ::T::check {native recovery restores accepted unprojected domain geometry} {[dict get [::GX::CurveWorkbench::_snapshotIds $w [list $id]] $id sketch_definition] eq $expected}
    ::GX::CurveWorkbench::_saveExplicit $w
    set prefixCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
    ::GX::CurveWorkbench::_sketchApply $w [::GX::interactiveDocumentSessionToken] {} $values
    set allocatedCounter $::GX::CurveWorkbench::st($w,next)
    ::GX::CurveWorkbench::undo $w
    # Automatic contract choice only. The real GUI suite separately uses
    # xdotool for every branch confirmation; no product callback is replaced.
    after 100 [list $w.__tk__messagebox.ok invoke]
    ::GX::scientificHistoryViewerNavigate $w branch
    ::T::check {confirmed branch preserves monotonic allocated IDs outside discarded future} {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$prefixCount && [dict get [::GX::scientificHistoryViewerAuxiliary $w] fields next]==$allocatedCounter}
    set scientificCount [dict get [::GX::scientificHistoryViewerStatus $w] count]
    set ::GX::CurveWorkbench::st($w,externalFeedback) {auxiliary-only recovery marker}
    set pan [::GX::Native2D::core view_requested $::GX::CurveWorkbench::st($w,scene)]
    lset pan 6 {-8 -9 12 11}
    ::GX::Native2D::core view $::GX::CurveWorkbench::st($w,scene) $pan
    ::GX::CurveWorkbench::_save $w
    ::GX::scientificHistoryViewerDetach $w 0
    set ::GX::CurveWorkbench::st($w,historyReady) 0;set ::GX::CurveWorkbench::st($w,historyDiscard) 1
    ::GX::CurveWorkbench::_close $w
    set w [::GX::CurveWorkbench::open [dict create workspace_id $document recovery_choice recover]];update
    ::T::check {auxiliary-only journal recovery preserves view without scientific steps} {$::GX::CurveWorkbench::st($w,externalFeedback) eq {auxiliary-only recovery marker} && [lindex [::GX::Native2D::core view_requested $::GX::CurveWorkbench::st($w,scene)] 6] eq {-8.0 -9.0 12.0 11.0} && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$scientificCount && $::GX::CurveWorkbench::st($w,next)>=$allocatedCounter}
    ::GX::CurveWorkbench::_saveExplicit $w
    ::GX::CurveWorkbench::_close $w
    set importedSketch [dict create schema gxtxt.geometry.sketch version 1.0 objects [dict create curve42 [dict create name {Imported exact line} definition $expected units {mm mm} provenance {}]] constraints {} parameters {span {formula {2+3} unit mm}} provenance {producer P017_synthetic_fixture}]
    set published [::GX::sketchDatasetPublish $::GX::currentSession viewer.curve_workbench history_sketch $importedSketch]
    set sketchHash [dict get $published sha256]
    set w [::GX::CurveWorkbench::open {workspace_id new}];update
    trace add execution ::GX::CurveWorkbench::_historyProject enter ::T::rejectProjection
    set intake [::GX::CurveWorkbench::_datasetImport $w history_sketch]
    trace remove execution ::GX::CurveWorkbench::_historyProject enter ::T::rejectProjection
    ::T::check {Sketch import preserves accepted science after controlled projection failure} {[dict get $intake accepted] && [dict exists $::GX::CurveWorkbench::st($w,curves) curve42] && [dict get [::GX::scientificHistoryViewerStatus $w] count]>=1}
    ::GX::CurveWorkbench::_saveExplicit $w
    ::GX::CurveWorkbench::undo $w
    ::T::check {Sketch intake is one native Undo boundary} {[dict size $::GX::CurveWorkbench::st($w,curves)]==0}
    ::GX::CurveWorkbench::redo $w
    ::T::check {Sketch Redo restores exact definition parameters and immutable source} {[dict get [::GX::CurveWorkbench::_snapshotIds $w {curve42}] curve42 sketch_definition] eq $expected && [dict get [::GX::parameterDefinitions [::GX::CurveWorkbench::_parameterBind $w]] span formula] eq {2+3} && [::GX::datasetField history_sketch sha256 {}] eq $sketchHash}
    ::GX::CurveWorkbench::_saveExplicit $w
    set native [dict get $::GX::CurveWorkbench::st($w,curves) curve42 native]
    ::GX::CurveWorkbench::_constraintCommit $w {} [dict create kind horizontal a $native a_index 3000000000]
    ::GX::CurveWorkbench::_saveExplicit $w
    set legacyPayload [dict get [::GX::interactiveDocumentRead $::GX::CurveWorkbench::st($w,document)] payload]
    set genuine [dict get $legacyPayload cad_workspace scientific_recipe]
    set legacySteps {};foreach step [dict get $genuine steps] {lappend legacySteps [dict remove $step description timestamp kind group group_id group_label undo_auxiliary]}
    dict set legacyPayload cad_workspace scientific_recipe [dict create base [dict get $genuine base] steps $legacySteps retention complete]
    dict unset legacyPayload cad_workspace history_auxiliary
    ::GX::CurveWorkbench::_close $w
    set legacy [::GX::sessionWorkspaceCreate curve_workbench {Legacy metadata fixture} $legacyPayload]
    set w [::GX::CurveWorkbench::open [dict create workspace_id [dict get $legacy id]]];update
    set rows [dict get [::GX::scientificHistoryViewerSummary $w] steps]
    set importedSteps [dict get [::GX::scientificHistoryViewerRecord $w] steps]
    set bytesPreserved 1
    foreach old $legacySteps new [lrange $importedSteps 0 [expr {[llength $legacySteps]-1}]] {if {$old ne $new} {set bytesPreserved 0}}
    set legacyLast [lindex $rows [expr {[llength $legacySteps]-1}]]
    ::T::write legacy-description-diagnostic.tcldict [dict create original_steps [llength $legacySteps] imported_steps [llength $importedSteps] bytes_preserved $bytesPreserved last_legacy_row $legacyLast]
    ::T::check {legacy constraint descriptions use patch metadata without changing scientific bytes} {[dict get $legacyLast kind] eq {constraint_add} && $bytesPreserved && ![info exists ::GX::CurveWorkbench::st($w,descriptionProjection)]}
    ::GX::createNewSession SYNTHETIC_CURVE_OTHER
    set rejected [catch {::GX::CurveWorkbench::_cadTransformApply $w translate [list $id] {0 0} {dx 1 dy 1}}]
    ::T::check {Session change rejects stale scientific mutation without a new owner} {$rejected && [::GX::interactiveDocumentList viewer.curve_workbench curve_workbench] eq {}}
    if {[winfo exists $w]} {::GX::CurveWorkbench::_close $w}
    ::T::write receipt.tcldict [dict create status PASS checks $::T::checks tested_native_pins $nativePins ordinary_native_calls $::T::nativeCalls scope {API-invoked real mapped domain contract; human GUI acceptance OPEN}]
} on error {message options} {::T::write FIRST_FAILURE.tcldict [dict create message $message options $options checks $::T::checks];puts stderr [dict get $options -errorinfo];exit 1} finally {catch {destroy .}}
exit 0
