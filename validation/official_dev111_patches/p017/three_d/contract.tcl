# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {usage: contract.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_3D_HISTORY_CONTRACT__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk;wm withdraw .
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_3D_HISTORY
::GX::modulePublicApiActivate viewer.3d_workbench WORKBENCH_3D_API_v1
::GX::configurationSet viewers.native3d.execution Software
namespace eval ::T {variable checks {};variable projections 0;variable timings {}}
proc ::T::check {name condition} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $name"};lappend ::T::checks [dict create name $name status PASS];puts "PASS $name";flush stdout}
proc ::T::write {name data} {set f [open [file join $::out $name] w];try {puts $f $data} finally {close $f}}
proc ::T::projection {command operation} {incr ::T::projections}
try {
    set document [::GX::Workbench3D::activateDocument {workspace_id new recovery_choice recover}]
    set context $::GX::Workbench3D::historyContext
    ::T::check {windowless scientific owner uses CORE context} {[string match history-context#* $context] && [::GX::Workbench3D::guiInspect] ne {} && ![winfo exists $::GX::Engine3D::window]}
    set first [::GX::Workbench3D::guiCommand primitive {primitive box dimensions {2 3 4} radius 1 height 1 name {History fixture body}}]
    set object [lindex [dict keys [dict get $first objects]] 0]
    set geometry [dict get $::GX::Workbench3D::model objects $object geometry sha256]
    ::T::check {existing primitive accepted with immediate Undo} {[dict get $first undo_count]==1 && [dict get $first history accepted] && [dict get $first history count]==1}
    set revision [dict get [::GX::interactiveDocumentMetadata $document] revision]
    trace add execution ::GX::Workbench3D::historyProject enter ::T::projection
    for {set n 1} {$n<=40} {incr n} {
        set begin [clock microseconds]
        ::GX::Workbench3D::hostEdit presentation $object [dict create opacity [expr {.4+$n/100.0}]]
        lappend ::T::timings [expr {[clock microseconds]-$begin}]
    }
    set accepted [::GX::scientificHistoryViewerStatus $context]
    ::T::check {all operations exceed former private32 cap without truncation} {[dict get $accepted count]==41 && [dict get $accepted cursor]==41 && ![info exists ::GX::Workbench3D::undo] && ![info exists ::GX::Workbench3D::redo]}
    ::T::check {normal recording avoids full Document projection} {$::T::projections==0 && [dict get [::GX::interactiveDocumentMetadata $document] revision]==$revision}
    set resource [dict get $::GX::Workbench3D::model objects $object geometry]
    ::T::check {presentation History preserves exact scientific geometry} {[dict get $resource sha256] eq $geometry}
    ::GX::Workbench3D::guiCommand undo
    ::T::check {Undo hydrates prior domain state without saving whole History} {abs([dict get $::GX::Workbench3D::model objects $object style opacity]-.79)<1e-12 && [dict get [::GX::scientificHistoryViewerStatus $context] cursor]==40 && $::T::projections==0}
    set exported [::GX::Workbench3D::recipeCapture [dict create document_id $document]]
    set exportedState [::GX::scientificHistoryState $exported]
    ::T::check {executable recipe exports current checkpoint without discarding Redo} {abs([dict get $exportedState objects $object style opacity]-.79)<1e-12 && [llength [dict get $exported steps]]==40 && [dict get [::GX::scientificHistoryViewerStatus $context] count]==41}
    ::GX::Workbench3D::guiCommand redo
    ::T::check {Redo restores accepted state and unchanged scientific resource} {abs([dict get $::GX::Workbench3D::model objects $object style opacity]-.8)<1e-12 && [dict get $::GX::Workbench3D::model objects $object geometry sha256] eq $geometry && [dict get [::GX::scientificHistoryViewerStatus $context] cursor]==41}
    ::GX::Workbench3D::guiCommand save
    set persisted [::GX::interactiveDocumentRead $document]
    set record [dict get $persisted payload scientific_history]
    ::T::check {explicit Save projects compatible complete History and empties private fields} {$::T::projections==1 && [dict get $persisted payload undo] eq {} && [dict get $persisted payload redo] eq {} && [llength [dict get $record steps]]>=41 && [dict get [::GX::scientificHistoryViewerStatus $context] pending]==0}
    trace remove execution ::GX::Workbench3D::historyProject enter ::T::projection
    ::GX::Workbench3D::close
    ::T::check {Close releases CORE context before scientific scene} {$::GX::Workbench3D::historyContext eq {} && $::GX::Workbench3D::scene eq {}}
    ::GX::Workbench3D::activateDocument [dict create workspace_id $document recovery_choice recover]
    set context $::GX::Workbench3D::historyContext
    ::T::check {reopen preserves all scientific History and stable object identity} {[dict get [::GX::scientificHistoryViewerStatus $context] count]>=41 && [dict exists $::GX::Workbench3D::model objects $object] && [dict get $::GX::Workbench3D::model objects $object geometry sha256] eq $geometry}
    ::GX::Workbench3D::guiCommand undo
    ::GX::Workbench3D::guiCommand redo
    ::T::check {reopened Undo Redo remains immediate} {[dict get [::GX::scientificHistoryViewerStatus $context] cursor]==[dict get [::GX::scientificHistoryViewerStatus $context] count]}
    ::GX::Workbench3D::hostEdit presentation $object {opacity .9}
    set crashRecord [::GX::scientificHistoryViewerRecord $context]
    set crashScene $::GX::Workbench3D::scene
    # Controlled loss of the presentation owner closes the public RAM context
    # without projecting the Document, preserving its independently durable log.
    ::GX::scientificHistoryContextClose $context 0
    set ::GX::Workbench3D::historyContext {}
    ::GX::native3DGeometryClose $crashScene;set ::GX::Workbench3D::scene {}
    ::GX::Workbench3D::activateDocument [dict create workspace_id $document recovery_choice recover]
    set context $::GX::Workbench3D::historyContext
    ::T::check {explicit recovery restores unsaved domain state from native journal} {[::GX::scientificHistoryViewerRecord $context] eq $crashRecord && abs([dict get $::GX::Workbench3D::model objects $object style opacity]-.9)<1e-12}
    set interoperability [::GX::Workbench3D::extensionContext]
    ::T::check {legacy extension context carries current canonical revision and accepted fields} {[dict get $interoperability revision]==[dict get [::GX::interactiveDocumentMetadata $document] revision] && ![dict exists $interoperability history_revision]}
    set transaction [::GX::Workbench3D::extensionBegin $interoperability]
    try {
        set applied [::GX::Workbench3D::extensionApply $transaction {status ok operations {}}]
        set returned [::GX::Workbench3D::extensionCommit $transaction $applied]
        set transaction {}
    } finally {if {$transaction ne {}} {::GX::Workbench3D::extensionRollback $transaction}}
    ::T::check {existing extension transaction retains canonical revision contract} {[dict get $returned revision]==[dict get [::GX::interactiveDocumentMetadata $document] revision] && [dict get $returned history pending]==0 && [dict get $::GX::Workbench3D::model objects $object geometry sha256] eq $geometry}
    ::GX::Workbench3D::close
    # An inert historical fixture exercises exact former private-stack import.
    # No current Session/Document is overwritten; every old payload is archived.
    set base [::GX::Workbench3D::defaultModel]
    set one $base;dict set one attrs marker one
    set two $base;dict set two attrs marker two
    set three $base;dict set three attrs marker three
    set oldPayload [dict create model $two undo [list $base $one] redo [list $three] allocation_counters {}]
    set legacy [::GX::interactiveDocumentCreate viewer.3d_workbench workbench_3d workbench3d.document.v1 1 $oldPayload]
    set legacyId [dict get $legacy id]
    ::GX::Workbench3D::activateDocument [dict create workspace_id $legacyId recovery_choice recover]
    set context $::GX::Workbench3D::historyContext
    ::T::check {legacy import preserves old Undo and Redo availability} {[dict get [::GX::scientificHistoryViewerStatus $context] cursor]==2 && [dict get [::GX::scientificHistoryViewerStatus $context] count]==3}
    ::GX::interactiveDocumentResourceCollect $legacyId
    ::T::check {CORE resource collection preserves unprojected legacy archive} {[dict get [::GX::interactiveDocumentResourceInfo $::GX::Workbench3D::legacyHistoryArchive] size_bytes]>0}
    ::GX::Workbench3D::guiCommand undo
    ::T::check {imported Undo restores exact legacy checkpoint} {[dict get $::GX::Workbench3D::model attrs marker] eq {one}}
    ::GX::Workbench3D::guiCommand redo
    ::GX::Workbench3D::guiCommand redo
    ::T::check {imported Redo preserves formerly future state} {[dict get $::GX::Workbench3D::model attrs marker] eq {three}}
    ::GX::Workbench3D::guiCommand save
    set saved [::GX::interactiveDocumentRead $legacyId]
    set archive [dict get $saved payload legacy_history_archive]
    set reader [::GX::interactiveDocumentResourceOpenReader $archive];set bytes {}
    try {while 1 {set part [::GX::interactiveDocumentResourceNext $reader];append bytes [dict get $part bytes];if {[dict get $part eof]} break}} finally {::GX::interactiveDocumentResourceCloseReader $reader}
    ::T::check {legacy raw payload is archived exactly without discarded provenance} {[encoding convertfrom utf-8 $bytes] eq $oldPayload}
    ::GX::Workbench3D::close
    ::T::write receipt.tcldict [dict create status PASS_3D_HISTORY_CONTRACT checks $::T::checks timings_us $::T::timings document $document legacy_document $legacyId geometry_sha256 $geometry framework $framework scope {Automated original manual scientific owner; no GUI shell input; no new CAD functionality}]
} on error {message options} {
    ::T::write FIRST_FAILURE.tcldict [dict create message $message options $options checks $::T::checks]
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts {PASS manual3D native History contract}
exit 0
