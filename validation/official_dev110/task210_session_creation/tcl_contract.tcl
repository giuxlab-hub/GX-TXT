# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework root operation stage
namespace eval ::GX {}
set ::GX::scriptDir [file normalize $framework]
source [file join $::GX::scriptDir core tcl session_creation_transaction_v1.tcl]
if {$operation eq {probe}} {
    set observed [::GX::_sessionCreationProbe $stage]
    if {![dict get $observed pending] || ![dict get $observed owner_alive]} {error {Fresh child could not discover live pending creation}}
    puts {PASS fresh_child_pending_probe}
    exit 0
}
set name {2>literal [set ::GX210_INJECTION 1] $literal {brace} ; Unicode μ}
set record [::GX::_sessionCreationReserve $root $name]
if {[dict get $record state] ne {reserved} || [file exists [dict get $record target]]} {error {Reserve incorrectly exposed target}}
file mkdir [dict get $record stage]
set f [open [file join [dict get $record stage] canary.txt] w]
puts -nonewline $f {Synthetic Tcl transport canary};close $f
set record [::GX::_sessionCreationClaim $record [dict get $record stage]]
set pending [::GX::_sessionCreationProbe [dict get $record stage]]
if {![dict get $pending pending] || ![dict get $pending owner_alive]} {error {Pending stage missing}}
set promoted [::GX::_sessionCreationPromote $record]
if {[dict get $promoted state] ne {promoted} || [file exists [dict get $record stage_parent]] ||
    ![file isfile [file join $root $name canary.txt]]} {error {Promotion/metadata cleanup differs}}
set observed [::GX::_sessionCreationInspect $record]
set aborted [::GX::_sessionCreationAbort $record]
if {[dict get $observed state] ne {promoted} || [dict get $aborted state] ne {promoted_retained} ||
    ![file isfile [file join $root $name canary.txt]] || [info exists ::GX210_INJECTION]} {error {Inert transport/committed preservation failed}}
puts {PASS all_private_Tcl_wrappers_and_inert_transport}
