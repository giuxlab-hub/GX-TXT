# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] common.tcl]
if {[llength $argv]!=3} {error {Usage: contracts.tcl FRAMEWORK_COPY NEW_RAID_OUTPUT baseline|candidate}}
lassign $argv framework out mode
if {$mode ni {baseline candidate}} {error {Expected baseline or candidate}}
set helperDir [file dirname [file normalize [info script]]]
set framework [::GX210Acq::admitCopy $framework]
set out [::GX210Acq::privatePath $out]
if {[file exists $out] || [string match "$framework/*" $out] || [string match "$out/*" $framework]} {
    error {Output must be fresh and separate from the disposable framework copy}
}
::GX210Acq::raid [file dirname $out]
file mkdir $out
set checks {};set observations {};set beforeHashes {}
proc check {name expression} {
    set ok [uplevel 1 [list expr $expression]]
    dict set ::checks $name [expr {$ok ? {PASS} : {FAIL}}]
    puts "[expr {$ok ? {PASS} : {FAIL}}] $name"
}
proc packageFixture {suffix letter} {
    set id acq.gx210_lifecycle_$suffix
    set ns ::GX210Fixture_$suffix
    set version [expr {$letter eq {A} ? {1.0.0} : {2.0.0}}]
    set package [file join $::out packages $suffix $letter]
    ::GX210Acq::writeFile [file join $package plugin-package.ini] [format {
[package]
api_version=1
id=%s
type=module
version=%s
name=TASK210 TEST ONLY acquisition lifecycle
framework_min=0.9.3
} $id $version]
    set optional [expr {$letter eq {B} ? "preflight_proc=${ns}::preflightB\ncapabilities=preflight" : {capabilities=}}]
    ::GX210Acq::writeFile [file join $package module.ini] [format {
; TASK210 TEST ONLY: non-scientific loader markers; never imports a Dataset.
[meta]
api_version=1
id=%s
kind=acquisition
group=Test only
name=TASK210 TEST ONLY acquisition lifecycle
version=%s
runner=standard_tcl
core=0
selectable=0
default_enabled=0
order=9999
description=Non-scientific API regression marker; no import output.
[inputs]
contracts=raw.text
[outputs]
datasets=
files=
[config]
fields=
[runner]
handler=gx210_lifecycle_%s
[acquisition_handler]
api_version=1
script=runtime/marker.tcl
inspect_proc=%s::inspect
import_proc=%s::import
source_kind=text
variable_mapping=none
supports_batch=0
%s
} $id $version $suffix $ns $ns $optional]
    set script [format {
# TASK210 TEST ONLY; non-scientific exact loader marker.
namespace eval %s {}
proc %s::inspect {request} {
    return [dict create recognized 1 format TASK210_TEST_ONLY_%s variables {} metadata {} preview_rows {} warnings {}]
}
proc %s::import {request} {error {TEST ONLY fixture cannot import scientific data}}
} $ns $ns $letter $ns]
    if {$letter eq {B}} {append script "\nproc ${ns}::preflightB {request} {return \[dict create ok 1 errors {} warnings {}\]}\n"}
    ::GX210Acq::writeFile [file join $package runtime marker.tcl] $script
    return $package
}
proc inspectMarker {id} {
    return [dict get [::GX::acquisitionHandlerInspect $id [file join $::out fixture.txt]] format]
}
set exitCode 1
try {
    foreach relative {gxtxt_pipeline.tcl core/tcl/acquisition_handler_api_v1.tcl core/tcl/plugin_runtime_lifecycle_v1.tcl core/tcl/plugin_install_api_v1.tcl} {
        dict set beforeHashes $relative [::GX210Acq::sha [file join $framework $relative]]
    }
    ::GX210Acq::writeFile [file join $out fixture.txt] "TASK210 TEST ONLY non-scientific acquisition marker\n"
    ::GX210Acq::boot $framework $out
    foreach suffix {loaded cold async} {
        set id acq.gx210_lifecycle_$suffix
        if {[file exists [::GX::pluginTargetPath module $id]]} {error "Fixture already present: $id"}
        foreach letter {A B} {dict set packages $suffix $letter [packageFixture $suffix $letter]}
    }
    set legacyBefore [list $::GX::acquisitionHandlerRegistry(generic_csv) $::GX::acquisitionHandlerRegistry(rigol_csv)]

    set id acq.gx210_lifecycle_loaded;set hid gx210_lifecycle_loaded
    dict set observations loaded_install [::GX::pluginInstallPackage [dict get $packages loaded A] install $id]
    check loaded_inspection_A {[inspectMarker $id] eq {TASK210_TEST_ONLY_A}}
    set registrationBefore $::GX::acquisitionHandlerRegistry($hid)
    dict set observations loaded_registration_before $registrationBefore
    dict set observations loaded_runtime_before [::GX::pluginRuntimeInfo $id]
    check loaded_runtime_observed {[::GX::pluginRuntimeModuleLoaded $id]}
    dict set observations loaded_update [::GX::pluginInstallPackage [dict get $packages loaded B] update $id]
    set receipt [dict get $observations loaded_update]
    check loaded_update_restart {[dict get $receipt installed_version] eq {2.0.0} && [dict get $receipt active_version] eq {1.0.0} && [dict exists $::GX::pluginRuntimePending $id]}
    check installed_B_descriptor {[::GX::moduleField $id version {}] eq {2.0.0}}
    check old_callable_retained {[dict get [::GX210Fixture_loaded::inspect {}] format] eq {TASK210_TEST_ONLY_A}}
    set beforeLoad $::GX::acquisitionHandlerRegistry($hid)
    dict set observations loaded_registration_after_update $beforeLoad
    set rejected [catch {::GX::acquisitionHandlerLoadModule $id} reason options]
    dict set observations pending_loader [dict create rejected $rejected reason $reason options $options]
    dict set observations loaded_registration_after_attempt $::GX::acquisitionHandlerRegistry($hid)
    check pending_loader_restart_guard {$rejected && [string match {*restart required*} $reason]}
    check complete_registration_preserved {$registrationBefore eq $beforeLoad && $registrationBefore eq $::GX::acquisitionHandlerRegistry($hid)}
    check new_callback_not_sourced {![llength [info commands ::GX210Fixture_loaded::preflightB]]}
    set pending [expr {[dict exists $::GX::pluginRuntimePending $id] ? [dict get $::GX::pluginRuntimePending $id] : {}}]
    check previous_package_retained {[dict exists $pending previous_root] && [file isdirectory [dict get $pending previous_root]]}

    set id acq.gx210_lifecycle_cold
    dict set observations cold_install [::GX::pluginInstallPackage [dict get $packages cold A] install $id]
    check cold_not_loaded {![::GX::pluginRuntimeModuleLoaded $id] && ![llength [info commands ::GX210Fixture_cold::inspect]]}
    dict set observations cold_update [::GX::pluginInstallPackage [dict get $packages cold B] update $id]
    set receipt [dict get $observations cold_update]
    check cold_update_active {[dict get $receipt installed_version] eq {2.0.0} && [dict get $receipt active_version] eq {2.0.0} && ![dict exists $::GX::pluginRuntimePending $id]}
    check cold_inspection_B {[inspectMarker $id] eq {TASK210_TEST_ONLY_B}}
    check cold_new_capability {[::GX::acquisitionHandlerHasCapability gx210_lifecycle_cold preflight]}

    set id acq.gx210_lifecycle_async
    dict set observations async_install [::GX::pluginInstallPackage [dict get $packages async A] install $id]
    check async_initial_A {[inspectMarker $id] eq {TASK210_TEST_ONLY_A}}
    set target [::GX::pluginTargetPath module $id]
    set targetBefore [list [::GX210Acq::readFile [file join $target module.ini]] [::GX210Acq::readFile [file join $target runtime marker.tcl]]]
    set registryBefore [::GX210Acq::readFile [::GX::pluginRegistryPath]]
    set runtimeBefore [list $::GX::pluginRuntimeLoaded $::GX::pluginRuntimePending]
    set activeBefore $::GX::acquisitionHandlerAsyncActive
    try {
        set ::GX::acquisitionHandlerAsyncActive 1
        set rejected [catch {::GX::pluginInstallPackage [dict get $packages async B] update $id} reason options]
    } finally {set ::GX::acquisitionHandlerAsyncActive $activeBefore}
    dict set observations async_update [dict create rejected $rejected reason $reason options $options receipt [::GX::pluginRuntimeInfo $id]]
    check active_acquisition_update_rejected {$rejected}
    check async_target_preserved {$targetBefore eq [list [::GX210Acq::readFile [file join $target module.ini]] [::GX210Acq::readFile [file join $target runtime marker.tcl]]]}
    check async_registry_preserved {$registryBefore eq [::GX210Acq::readFile [::GX::pluginRegistryPath]]}
    check async_runtime_preserved {$runtimeBefore eq [list $::GX::pluginRuntimeLoaded $::GX::pluginRuntimePending]}
    check async_honest_failure_receipt {$rejected && [dict get [::GX::pluginRuntimeInfo $id] status] eq {Update failed}}
    check legacy_registration_unchanged {$legacyBefore eq [list $::GX::acquisitionHandlerRegistry(generic_csv) $::GX::acquisitionHandlerRegistry(rigol_csv)]}
    check legacy_loader_generic {[::GX::acquisitionHandlerLoadModule acq.generic_csv] eq {generic_csv}}

    ::GX210Acq::writeFile [file join $out child_authorized.tcldict] [dict create framework $framework mode $mode]
    set childStatus [catch {exec [info nameofexecutable] [file join $helperDir fresh.tcl] $framework $out >[file join $out fresh.log] 2>@1} childError]
    dict set observations fresh_child [dict create status $childStatus message $childError]
    check fresh_child_success {!$childStatus && [file isfile [file join $out fresh_result.tcldict]]}
    if {!$childStatus} {
        set fresh [::GX210Acq::readFile [file join $out fresh_result.tcldict]]
        dict set observations fresh $fresh
        check fresh_loaded_B {[dict get $fresh loaded format] eq {TASK210_TEST_ONLY_B} && [dict get $fresh loaded runtime active_version] eq {2.0.0}}
        check fresh_loaded_new_capability {[dict get $fresh loaded registration preflight_proc] eq {::GX210Fixture_loaded::preflightB}}
        check fresh_cold_B {[dict get $fresh cold format] eq {TASK210_TEST_ONLY_B}}
        check fresh_async_A {[dict get $fresh async format] eq {TASK210_TEST_ONLY_A}}
    }
    foreach relative [dict keys $beforeHashes] {check source_preserved_$relative {[dict get $beforeHashes $relative] eq [::GX210Acq::sha [file join $framework $relative]]}}
    set failed {};dict for {name value} $checks {if {$value eq {FAIL}} {lappend failed $name}}
    if {$mode eq {candidate}} {
        set status [expr {[llength $failed] ? {FAIL} : {PASS}}]
    } else {
        set oldReceipt [dict get $observations loaded_update]
        set reproduced [expr {[dict get $oldReceipt installed_version] eq {2.0.0} && [dict get $oldReceipt active_version] eq {2.0.0} && [dict get [::GX210Fixture_loaded::inspect {}] format] eq {TASK210_TEST_ONLY_A} && [dict get $checks loaded_update_restart] eq {FAIL}}]
        set expectedFailures {loaded_runtime_observed loaded_update_restart pending_loader_restart_guard previous_package_retained active_acquisition_update_rejected async_target_preserved async_registry_preserved async_runtime_preserved async_honest_failure_receipt fresh_async_A}
        set unexpected {};foreach name $failed {if {$name ni $expectedFailures} {lappend unexpected $name}}
        dict set observations baseline_expected_failure_names $expectedFailures
        dict set observations baseline_unexpected_failures $unexpected
        set status [expr {$reproduced && ![llength $unexpected] ? {PASS_BASELINE_REPRODUCED} : {FAIL_BASELINE_NOT_REPRODUCED}}]
    }
    set exitCode [expr {$status in {PASS PASS_BASELINE_REPRODUCED} ? 0 : 1}]
} on error {error options} {
    set status ERROR
    dict set observations fatal [dict create message $error options $options]
    puts stderr $error
} finally {
    ::GX210Acq::writeFile [file join $out RESULT.tcldict] [dict create schema gx210.acquisition_lifecycle.v1 status $status mode $mode framework $framework output $out timestamp_utc [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}] checks $checks observations $observations source_hashes $beforeHashes GUI_acceptance NOT_TESTED scientific_import NOT_TESTED]
}
exit $exitCode
