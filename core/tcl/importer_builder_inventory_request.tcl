# SPDX-License-Identifier: GPL-3.0-or-later
# Fixed CORE auxiliary worker. Called only by the fixed managed Python envelope;
# input is inert dictionary data and filenames from its bounded os.scandir.
namespace eval ::GX {}
proc ::GX::_importerBuilderInventoryRun {request} {
    # Retain the fixed source location for this later proc invocation.
    set framework $::GX::ImporterBuilderInventoryFramework
    set ::argv0 __gxtxt_csv_inventory_request__
    uplevel #0 [list source [file join $framework gxtxt_pipeline.tcl]]
    # Register only the selected trusted Python tool in this private interpreter;
    # no configuration Save, module loading, user data scan or Session creation.
    ::GX::configurationRegister runtime.python [dict create group Runtime label Python type command default [dict get $request python_executable] scope user]
    set root [dict get $request root];set directory [dict get $request resource_root]
    if {![file isdirectory $directory] || [file type $directory] eq {link}} {error {Inventory temporary allocation is unavailable}}
    set items {};set diagnostics {};set total 0;set complete 0
    set truncated [dict get $request truncated]
    foreach name [dict get $request names] {
        if {[file tail $name] ne $name || ![string match *.ini $name]} {error {Invalid inventoried filename}}
        set path [file join $root $name]
        if {[catch {
            set id [file rootname $name]
            if {![regexp {^[a-z][a-z0-9_.-]*$} $id]} {error {Filename is not a valid recipe ID}}
            # Same public Read/Describe owner as interactive/headless callers.
            set receipt [::GX::_importerBuilderDescribeFromPath $id $path]
            if {[dict get $receipt definition id] ne $id} {error {Filename differs from declared recipe ID}}
            incr total [string bytelength $receipt]
            if {$total>2097152} {set truncated 1;error {Receipt budget reached}}
            dict set items $id $receipt
        } reason]} {lappend diagnostics [dict create path $path error [string range $reason 0 511]]}
        if {$total>2097152} {break}
        incr complete
        set ch [open [file join $directory progress.tmp] w]
        fconfigure $ch -encoding utf-8 -translation lf
        try {puts -nonewline $ch [dict create phase inventory rows $complete total [llength [dict get $request names]]]} finally {close $ch}
        file rename -force -- [file join $directory progress.tmp] [file join $directory progress.tcldict]
    }
    if {$truncated} {lappend diagnostics [dict create path $root error {Inventory limit reached: at most64 recipe files,256 directory entries and2MiB receipts. Remaining entries were not read; narrow the inventory and reload.}]}
    return [dict create schema gxtxt.importer_builder_inventory.v1 items $items diagnostics $diagnostics truncated $truncated scanned_entries [dict get $request scanned_entries] file_limit 64 entry_limit 256 receipt_limit_bytes 2097152]
}
set ::GX::ImporterBuilderInventoryFramework [file dirname [file dirname [file dirname [info script]]]]
