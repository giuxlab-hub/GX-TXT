# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {usage: contract.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_PORTABLE_HISTORY__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
::GX::createNewSession SYNTHETIC_PORTABLE_NATIVE_HISTORY
namespace eval ::PT {variable state;variable contexts;variable commits;variable checks {}}
proc ::PT::emit {name value} {set f [open [file join $::out $name.tcldict] w];try {fconfigure $f -encoding utf-8;puts $f $value} finally {close $f}}
proc ::PT::check {condition message} {if {![uplevel 1 [list expr $condition]]} {error "FAIL: $message"};lappend ::PT::checks $message;emit checks $::PT::checks;puts "PASS: $message";flush stdout}
proc ::PT::capture {label} {return $::PT::state($label)}
proc ::PT::restore {label snapshot} {set ::PT::state($label) $snapshot}
proc ::PT::guard {label} {return [info exists ::PT::state($label)]}
proc ::PT::commit {label record} {incr ::PT::commits($label)}
proc ::PT::validate {record} {if {![dict exists $record base code]} {error {Synthetic author state requires inert code}}}
proc ::PT::attach {label owner document channel {record {}}} {
    set ::PT::state($label) {code {disp(0);} metadata {author_note synthetic}};set ::PT::commits($label) 0
    set cb [dict create capture [list ::PT::capture $label] restore [list ::PT::restore $label] guard [list ::PT::guard $label] commit [list ::PT::commit $label] channel $channel recovery_choice recover]
    if {$document ne {}} {dict set cb document_id $document}
    set ::PT::contexts($label) [::GX::scientificHistoryContextAttach $owner $cb $record]
    return $::PT::contexts($label)
}
proc ::PT::change {label code} {dict set ::PT::state($label) code $code;return [::GX::scientificHistoryViewerRecordOperation $::PT::contexts($label) {Edit inert author code}]}
foreach owner {fixture.portable_history fixture.excluded_history} {::GX::scientificRecipeHostRegister $owner [dict create capture ::PT::capture validate ::PT::validate replay ::GX::scientificHistoryState]}
try {
    set source $::GX::currentSession
    set script [::GX::interactiveDocumentCreate fixture.portable_history script_author gxtxt.octave_script.document 1.0 {disp(0);}];set id [dict get $script id]
    set excluded [::GX::interactiveDocumentCreate fixture.excluded_history unproved gxtxt.unknown.document 1 {inert excluded}];set excludedId [dict get $excluded id]
    set a [::PT::attach A fixture.portable_history $id preparation]
    set b [::PT::attach B fixture.excluded_history $excludedId excluded]
    set draft [::PT::attach Draft fixture.portable_history {} unsaved]
    set manifestHash [::GX::sha256File [file join $source metadata manifest.ini]]
    set registryHash [::GX::sha256File [file join $source metadata interactive_documents.ini]]
    set sourcePayload [::GX::interactiveDocumentRead $id]
    ::PT::change A {disp(1);};::PT::change A {disp(2);};::PT::change B {excluded(1);};::PT::change Draft {draft(9);}
    set expectedA [::GX::scientificHistoryViewerRecord $a];set expectedDraft [::GX::scientificHistoryViewerRecord $draft]
    set beforeAux [::GX::scientificHistoryViewerStatus $a]
    set expectedAux [dict create viewport {bounds {-2 -3 8 12} scale {1 1}} presentation {legend 1 grid 1} selected_ids curve1]
    set auxiliaryStatus [::GX::historyNative auxiliary [dict get $::GX::ScientificHistory::viewers $a handle] $expectedAux]
    ::PT::check {$::PT::commits(A)==0 && [dict get [::GX::interactiveDocumentRead $id] payload] eq {disp(0);}} {Unsaved native operations remain distinct from the canonical saved Document}
    set foreignArchive [file join $out foreign-must-not-publish.zip]
    set failed [catch {exec [::GX::runtimeToolRequired python] [file join $framework core python session_portable_v1.py] export $source $foreignArchive $framework test 2>@1} reason]
    ::PT::emit foreign_writer [dict create rejected $failed reason $reason archive_exists [file exists $foreignArchive]]
    ::PT::check {$failed && [string match {*foreign active writer*} $reason] && ![file exists $foreignArchive]} {An external exporter rejects a foreign active writer instead of racing its files}
    set heldPath [file join $source metadata history idoc_7777.gxh.lock]
    set lockCommand [list [::GX::runtimeToolRequired python] [file join [file dirname [info script]] lock_holder.py] $heldPath]
    set lockStream [open [linsert $lockCommand 0 |] r+]
    try {
        if {[gets $lockStream] ne {LOCKED}} {error {Controlled lock holder failed to start}}
        set owned [dict get [::GX::scientificHistoryPortableDrain $source] owned]
        set guardedArchive [file join $out initial-writer-must-not-publish.zip]
        set command [list [::GX::runtimeToolRequired python] [file join $framework core python session_portable_v1.py] export $source $guardedArchive $framework test]
        foreach path $owned {lappend command --history-owned $path}
        set rejected [catch {exec {*}$command 2>@1} initialReason]
        ::PT::check {$rejected && [string match {*foreign active writer*} $initialReason] && [string match {*idoc_7777.gxh*} $initialReason] && ![file exists $guardedArchive]} {A foreign initial writer is rejected even before its first data/checkpoint exists}
    } finally {puts $lockStream release;flush $lockStream;close $lockStream;file delete -- $heldPath}
    set archive [file join $out session.zip]
    set exported [::GX::sessionPortableExport $source $archive]
    set sourceStatus [::GX::scientificHistoryViewerStatus $a]
    ::PT::check {[dict get $sourceStatus accepted_revision]==[dict get $sourceStatus durable_revision] && [dict get $sourceStatus pending]==0} {Public Session export drains accepted native bytes to verified durability}
    ::PT::check {$::PT::commits(A)==0 && $::PT::commits(B)==0 && $::PT::commits(Draft)==0} {Session export does not invoke hidden Viewer Save or Document projection}
    ::PT::check {[::GX::sha256File [file join $source metadata manifest.ini]] eq $manifestHash && [::GX::sha256File [file join $source metadata interactive_documents.ini]] eq $registryHash && [::GX::interactiveDocumentRead $id] eq $sourcePayload} {Session export leaves original Manifest registry and canonical scientific bytes unchanged}
    set importedPath [file join $out imported]
    set imported [::GX::sessionPortableImport $archive $importedPath]
    ::PT::check {[dict get $imported session] eq $importedPath && [dict get $imported history_rebased]==3} {Genuine public Session import transaction rescopes all three native families}
    set importedRegistry [::GX::_interactiveDocumentRegistryRead $importedPath]
    ::PT::check {[dict get $importedRegistry $id generation] eq [dict get $script generation]} {Import preserves authorized Document generation and registry ownership}
    set importedFamily [file join $importedPath metadata history "$id.preparation.gxh"]
    set info [::GX::_historyPortableVerify $importedPath $importedFamily $importedRegistry]
    file stat $importedPath importedStat
    ::PT::check {[lrange [dict get $info identity] 0 2] eq [list $importedPath $importedStat(dev) $importedStat(ino)]} {Imported native identity uses final logical path and retained staging inode}
    set importedA [dict get $info recovered record]
    ::PT::check {[dict get $importedA steps] eq [dict get $expectedA steps] && [dict get $importedA base] eq [dict get $expectedA base] && [dict get $importedA cursor]==[dict get $expectedA cursor]} {Import preserves exact native scientific step bytes order base and cursor}
    ::PT::check {[dict get $info recovered auxiliary] eq $expectedAux && [dict get $auxiliaryStatus count]==[dict get $beforeAux count] && [dict get $auxiliaryStatus cursor]==[dict get $beforeAux cursor]} {Public Session transport preserves native auxiliary presentation without scientific History entries or cursor changes}
    ::PT::check {[dict get $info recovered revision]==1 && [llength [glob -nocomplain -directory [file join $importedPath metadata history transport_archives] */*.receipt.tcldict]]>=2} {New Session starts an explicit revision epoch with archived verified source identities and bytes}
    set originalFamily [file join $source metadata history "$id.preparation.gxh"]
    set originCopies [glob -nocomplain [file join $importedPath metadata history transport_archives * "$id.preparation.gxh.checkpoint"]]
    ::PT::check {[llength $originCopies]==1 && [::GX::sha256File [lindex $originCopies 0]] eq [::GX::sha256File "$originalFamily.checkpoint"]} {Original source checkpoint bytes are retained exactly in the imported archive}

    set originBase [string range [lindex $originCopies 0] 0 end-11]
    set f [open "$originBase.receipt.tcldict" r];set originReceipt [read $f];close $f
    ::PT::check {[dict get $originReceipt source_accepted_revision]==[dict get $sourceStatus accepted_revision] && [dict get $originReceipt source_durable_revision]==[dict get $sourceStatus durable_revision] && [dict get $originReceipt raw_sha256 {}] eq [::GX::sha256File $originalFamily] && [::GX::sha256File $originBase] eq [::GX::sha256File $originalFamily]} {Origin receipt retains accepted/durable revisions and exact raw journal checksum}
    set corrupt [file join $out valid-package-foreign-owner.zip]
    exec [::GX::runtimeToolRequired python] [file join [file dirname [info script]] mutate_package.py] $archive $corrupt $id [dict get $script generation]
    ::GX::sessionPortableValidate $corrupt
    set badDestination [file join $out rejected-import]
    ::PT::check {[catch {::GX::sessionPortableImport $corrupt $badDestination} message] && [string match {*ownership mismatch*} $message] && ![file exists $badDestination]} {Verified ZIP with foreign native generation fails before Session publication}

    # Orphan bytes are a deliberately unowned preparation-copy fixture. Full
    # Session transport above contained only valid registered owners.
    file copy -- "$originalFamily.checkpoint" [file join $source metadata history idoc_9999.gxh.checkpoint]
    set clone [::GX::sessionExperimentClone {P017 preparation copy} [file join $out cloned]]
    set cloned [dict get $clone session_path]
    set cloneRegistry [::GX::_interactiveDocumentRegistryRead $cloned]
    ::PT::check {[dict get $clone document_count]==1 && [dict exists $cloneRegistry $id] && ![dict exists $cloneRegistry $excludedId]} {Public preparation duplication copies only the policy-authorized author Document}
    set cloneFamilies [::GX::_historyPortableFamilies $cloned]
    ::PT::check {[llength $cloneFamilies]==1 && [file tail [lindex $cloneFamilies 0]] eq "$id.preparation.gxh"} {Generic clone transport omits excluded orphan and unsaved-draft History families}
    set clonedInfo [::GX::_historyPortableVerify $cloned [lindex $cloneFamilies 0] $cloneRegistry]
    set clonedA [dict get $clonedInfo recovered record]
    ::PT::check {[dict get $clonedA steps] eq [dict get $expectedA steps] && [dict get $clonedA cursor]==[dict get $expectedA cursor] && [dict get $clonedInfo recovered auxiliary] eq $expectedAux} {Selected preparation History retains every unsaved scientific step and auxiliary presentation through native rebind}
    ::PT::check {$::PT::commits(A)==0 && $::PT::commits(B)==0 && [::GX::sha256File [file join $source metadata manifest.ini]] eq $manifestHash && [::GX::sha256File [file join $source metadata interactive_documents.ini]] eq $registryHash && [::GX::interactiveDocumentRead $id] eq $sourcePayload} {Duplication does not save or mutate original canonical scientific state}
    foreach context [list $a $b $draft] {::GX::scientificHistoryContextClose $context 0}
    ::GX::openSessionPath $importedPath
    set recoveredContext [::PT::attach Imported fixture.portable_history $id preparation]
    ::PT::check {[dict get $::PT::state(Imported) code] eq {disp(2);} && [dict get [::GX::scientificHistoryViewerStatus $recoveredContext] count]==2} {The imported real CORE context opens and recovers its unsaved native state}
    ::GX::scientificHistoryContextClose $recoveredContext 0
    set drafts [::GX::scientificHistoryDrafts fixture.portable_history unsaved]
    ::PT::check {[llength $drafts]==1 && [dict get [::GX::scientificHistoryState [dict get [lindex $drafts 0] record]] code] eq {draft(9);}} {Imported unsaved draft discovery verifies its new Session identity and exact scientific state}
    ::PT::check {![llength [info commands winfo]]} {Session transport ownership work remains headless without hidden GUI hosts}
    ::PT::emit receipt [dict create status PASS_PORTABLE_NATIVE_HISTORY framework $framework checks $::PT::checks exported $exported imported $imported cloned $clone source_durable $sourceStatus native_import $info no_source_Save 1]
    puts {PASS PORTABLE NATIVE HISTORY}
} on error {message options} {
    ::PT::emit FIRST_FAILURE [dict create message $message options $options checks $::PT::checks]
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
