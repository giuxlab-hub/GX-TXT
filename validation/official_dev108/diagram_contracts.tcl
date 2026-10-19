# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set out [file normalize $out]
if {![string match */_private_dev108/* $out] || [file exists $out]} {error {Fresh dev108 private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev108_diagram_contracts__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions]
set session [::GX::createNewSession diagram_contracts]
set symbol {title Process prefix P paths {{{-2 -1} {2 -1} {2 1} {-2 1} {-2 -1}}} pins {in {-3 0} out {3 0}} attributes {caption {type string default Process}}}
::GX::native2DGeometryDiagramCatalogRegister validation.flow [dict create module_id viewer.development_workspace version 1 license GPL-3.0-or-later symbols [dict create process $symbol]]
set created [::GX::native2DGeometryDiagramCreate viewer.development_workspace development_workspace validation.flow]
set id [dict get $created id]
proc edit {operation request} {
    set owner [::GX::native2DGeometryDiagramRead $::id]
    return [::GX::native2DGeometryDiagramEdit $::id $owner $operation $request]
}
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
set a [dict get [edit place {kind process position {0 0} name Source}] object_id]
set b [dict get [edit place {kind process position {12 0} name Sink}] object_id]
set c [dict get [edit place {kind process position {6 -6} rotation 90 name Control}] object_id]
set d [dict get [edit place {kind process position {6 6} rotation 90 name Audit}] object_id]
set first [dict get [edit wire [dict create start [list $a out] end [list $b in]]] object_id]
set second [dict get [edit wire [dict create start [list $c out] end [list $d in]]] object_id]
set crossed [::GX::native2DGeometryDiagramRead $id]
check {[dict size [dict get $crossed payload junctions]]==0} {Coincident crossing invented a junction}
set failures {}
foreach {name operation request} [list invalid_pin wire [dict create start [list $a missing] end [list $b in]] duplicate_name properties [dict create id $b name Source] wrong_rotation transform [dict create id $a rotation 45] unknown_attribute properties [dict create id $a attributes {executable forbidden}]] {
    check {[catch {edit $operation $request} reason]} "Invalid $name was admitted"
    check {[::GX::native2DGeometryDiagramRead $id] eq $crossed} "Failed $name changed authority"
    dict set failures $name $reason
}
set stale [::GX::native2DGeometryDiagramRead $id]
edit properties [dict create id $a attributes {caption {A typed flow symbol}}]
check {[catch {::GX::native2DGeometryDiagramEdit $id $stale remove [dict create id $a]} reason options]} {Stale edit succeeded}
check {[dict get $options -errorcode] eq {GX NATIVE2D STALE_SOURCE}} {Stale error contract missing}
set saved [::GX::native2DGeometryDiagramRead $id]
edit remove [dict create id $a]
set removed [::GX::native2DGeometryDiagramRead $id]
check {![dict exists $removed payload wires $first] && [dict exists $removed payload wires $second]} {Removal damaged unrelated crossing}
edit restore [dict create payload [dict get $saved payload]]
set restored [::GX::native2DGeometryDiagramRead $id]
check {[dict get $restored payload] eq [dict get $saved payload]} {Restore changed authoritative payload unexpectedly}
set new [dict get [edit junction {position {6 0}}] object_id]
check {$new ni [dict keys [dict get $restored payload components]]} {Object identity reused}
set label [dict get [edit label [dict create endpoint [list $b in] text stable_net]] object_id]
set beforeLabel [::GX::native2DGeometryDiagramRead $id]
set highwater [dict get $beforeLabel payload next_id]
edit label [dict create id $label text renamed_net offset {12 24}]
set labelled [::GX::native2DGeometryDiagramRead $id]
check {[dict get $labelled payload next_id]==$highwater && [dict get $labelled payload labels $label text] eq {renamed_net}} {Label update changed stable identity/highwater}
check {[dict get $labelled payload labels $label endpoint] eq [list $b in]} {Label offset changed electrical endpoint}
foreach bad [list [dict create id $label text {invalid net}] [dict create id $label offset {Inf 0}] [dict create id missing text absent]] {
    check {[catch {edit label $bad}]} {Invalid label update admitted}
    check {[::GX::native2DGeometryDiagramRead $id] eq $labelled} {Rejected label edit changed canonical source}
}
set legacy [dict get $labelled payload]
dict unset legacy labels $label offset
::GX::native2DGeometryDiagramValidate $legacy
edit remove [dict create id $label]
check {![dict exists [::GX::native2DGeometryDiagramRead $id] payload labels $label]} {Selected label not removed}
edit restore [dict create payload [dict get $labelled payload]]
check {[dict get [::GX::native2DGeometryDiagramRead $id] payload labels $label] eq [dict get $labelled payload labels $label]} {Label restore changed stable identity}
set reopened [::GX::interactiveDocumentRead $id]
check {[dict get $reopened payload schema] eq {gxtxt.native2d.diagram.v1}} {Canonical document reopen lost schema}
set f [open [file join $out result.tcldict] w]
puts $f [dict create result PASS non_electrical_reuse validation.flow document $reopened invalid_operations $failures crossing_wires [list $first $second] stale_guard [dict get $options -errorcode]]
close $f
puts "PASS public Native2D diagram document contracts: $id"
