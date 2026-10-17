# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev104/* $out] || [file exists $out]} {error {New private dev104 output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev104_project_contract__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc receipt {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
proc check {condition name} {set pass [uplevel 1 [list expr $condition]];receipt $name [dict create pass $pass];if {!$pass} {error "FAIL: $name"}}
set ::GX::cfg(output_root) [file join $out Sessions]
set session [::GX::createNewSession organization]
set eid $::GX::cfg(experiment_id);set default [::GX::projectDefaultId]
set p [::GX::projectCreate Photocatalysis];set q [::GX::projectCreate Controls]
set a [::GX::projectNamespaceCreate Chemistry];set b [::GX::projectNamespaceCreate Electronics]
::GX::projectNamespaceAssign $p $a [::GX::projectOrganizationGeneration]
::GX::projectNamespaceAssign $q $b [::GX::projectOrganizationGeneration]
set g [::GX::projectSessionNamespaceCreate $p Kinetics]
set h [::GX::projectSessionNamespaceCreate $p Controls]
set collision [::GX::projectSessionNamespaceCreate $q Kinetics]
set stale [::GX::projectOrganizationCapture ex:$eid]
::GX::projectSessionNamespaceAssign $eid $p $g $default [::GX::projectOrganizationGeneration]
check {[::GX::projectExperimentResolve $eid] eq $session && [::GX::projectMembershipField $eid session_namespace] eq $g} initial_move
set hash [::GX::sha256File [file join $session metadata manifest.ini]]
check {[catch {::GX::projectOrganizationMove $stale $q}] && [::GX::sha256File [file join $session metadata manifest.ini]] eq $hash} stale_refused
set snapshot [::GX::projectOrganizationGeneration]
check {[catch {::GX::projectSessionNamespaceAssign $eid $q $g $p $snapshot}] && [::GX::projectOrganizationGeneration]==$snapshot} foreign_group_refused
::GX::projectOrganizationMove [::GX::projectOrganizationCapture ex:$eid] sn:$p:$h
check {[::GX::sha256File [file join $session metadata manifest.ini]] eq $hash} regroup_no_manifest_write
::GX::projectOrganizationMove [::GX::projectOrganizationCapture ex:$eid] sn:$q:$collision
check {[::GX::projectMembershipField $eid project_id] eq $q && [::GX::projectMembershipField $eid session_namespace] eq $collision} cross_project_explicit_group
::GX::projectOrganizationMove [::GX::projectOrganizationCapture ex:$eid] $p
check {[::GX::projectMembershipField $eid session_namespace] eq {}} cross_project_ungrouped
check {[catch {::GX::projectOrganizationCapture $default}]} default_protected
check {[catch {::GX::projectSessionNamespaceCreate $default Invalid}]} default_group_refused
check {[catch {::GX::projectNamespaceCreate chemistry}]} duplicate_refused
check {[catch {::GX::projectNamespaceRename $a "bad\nname"}]} invalid_name_refused
set before [::GX::sha256File [::GX::projectRegistryPath]]
set beforeGeneration [::GX::projectOrganizationGeneration]
set failed [catch {::GX::_projectOrganizationTransaction $beforeGeneration {
    set ::GX::projectCatalog($p,namespace_id) {}
    ::GX::projectSaveRegistry
    error {Private forced organization rollback}
}} message]
check {$failed && [::GX::sha256File [::GX::projectRegistryPath]] eq $before && [::GX::projectOrganizationGeneration]==$beforeGeneration && [::GX::projectField $p namespace_id] eq $a} rollback_preserves_registry_memory
::GX::projectSessionNamespaceAssign $eid $p $g $p [::GX::projectOrganizationGeneration]
::GX::projectNamespaceRename $a {Physical Chemistry}
::GX::projectSessionNamespaceRename $p $g {Time series}
::GX::projectLoadRegistry
check {[dict get [::GX::projectNamespaceList] $a] eq {Physical Chemistry} && [dict get [::GX::projectSessionNamespaceList $p] $g] eq {Time series} && [::GX::projectMembershipField $eid session_namespace] eq $g} registry_reopen
set package [file join $out organized.gxtxt-project.zip]
set exported [::GX::projectPortableExport $p $package]
set imported [::GX::projectPortableImport $package {Imported Photocatalysis}]
set ip [dict get $imported project_id];set ie [lindex [dict keys [dict get $imported experiments]] 0]
set ig [::GX::projectMembershipField $ie session_namespace]
check {$ip ne $p && $ie ne $eid && $ig ne $g && [dict get [::GX::projectSessionNamespaceList $ip] $ig] eq {Time series} && [::GX::projectField $ip namespace_id] ne $a} portable_remap
::GX::projectSessionNamespaceDelete $p $g
check {[::GX::projectMembershipField $eid session_namespace] eq {} && [file isdirectory $session]} populated_session_group_delete
::GX::projectNamespaceDelete $a
check {[::GX::projectField $p namespace_id] eq {}} populated_project_group_delete
::GX::projectOrganizationMove [::GX::projectOrganizationCapture ex:$eid] $default
check {[::GX::projectExperimentResolve $eid] eq $session && [::GX::projectMembershipField $eid project_id] eq $default} returned_default_no_move
receipt result [dict create status PASS project $p receiving_project $q experiment $eid session $session imported $ip generation [::GX::projectOrganizationGeneration] api [::GX::projectOrganizationApiInfo]]
puts "PASS: Project organization contracts"
