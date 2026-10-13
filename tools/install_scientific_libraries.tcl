#!/usr/bin/env tclsh
# Install independent scientific data packages through the public manager.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} {
    error "usage: tclsh install_scientific_libraries.tcl FRAMEWORK_ROOT PACKAGE_DIRECTORY"
}
lassign $argv framework packageDir
set framework [file normalize $framework]
set packageDir [file normalize $packageDir]
if {![file isfile [file join $framework gxtxt_pipeline.tcl]]} {error "framework is missing"}
if {![file isdirectory $packageDir]} {error "package directory is missing"}
set packages [lsort [glob -nocomplain -directory $packageDir *.zip]]
if {![llength $packages]} {error "no scientific data packages found"}
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set api ::GX::ScientificLibraryManagerAPIv1
foreach package $packages {
    set filename [file rootname [file tail $package]]
    if {![regexp {^(.+)_([0-9]+(?:\.[0-9]+){1,3})$} $filename -> id version]} {
        error "scientific data package filename must be <library-id>_<version>.zip: $filename"
    }
    set existing ""
    catch {set existing [${api}::getLibraryInfo $id]}
    if {$existing eq "" || [dict get $existing state] eq "removed"} {
        set result [${api}::installLibrary $package]
        set action installed
    } elseif {[dict get $existing version] eq $version} {
        if {[dict get $existing package_sha256] ne [::GX::sha256File $package]} {
            error "installed $id $version differs from the selected package"
        }
        set result [${api}::verifyLibrary $id]
        set action verified
    } else {
        set result [${api}::updateLibrary $id $package]
        set action updated
    }
    if {[dict get $result version] ne $version} {error "version mismatch for $id"}
    puts "PASS $action $id $version entries=[dict get $result entry_count]"
}
