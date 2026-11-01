# SPDX-License-Identifier: GPL-3.0-or-later
# DEV112 distribution adapter. All installation decisions remain in CORE.
namespace eval ::DEV112Install {
    variable arguments $::argv
    variable root [file normalize [file dirname [file dirname [info script]]]]
}
if {[llength $::DEV112Install::arguments] != 1} {
    puts stderr {Usage: tclsh distribution/install_worker.tcl package-plan.tsv}
    exit 2
}
source [file join $::DEV112Install::root gxtxt_pipeline.tcl]

proc ::DEV112Install::run {} {
    variable arguments
    ::GX::defaults
    ::GX::loadModuleCatalog
    set stream [open [lindex $arguments 0] r]
    try {set rows [split [read $stream] \n]} finally {close $stream}
    foreach row $rows {
        if {$row eq {}} continue
        if {[llength [split $row \t]] != 4} {error {Malformed installation plan}}
        lassign [split $row \t] id type package mode
        ::GX::pluginSafeId $id
        ::GX::pluginTypeSpec $type
        if {$mode ni {install update auto}} {error {Invalid installation operation}}
        if {$type eq {module} && [::GX::moduleField $id descriptor {}] ne {} &&
            ([::GX::moduleIsCore $id] || [::GX::moduleIsAlwaysAvailable $id])} {
            error {A bundled CORE/ALWAYS module cannot enter the optional installer}
        }
        # This adapter handles optional packages only. CORE/ALWAYS payloads
        # already belong to the distribution and never enter an install plan.
        set admission [::GX::pluginPackageOpen $package]
        try {
            set descriptor [::GX::parseIni [dict get $admission descriptor]]
            if {[::GX::descriptorValue $descriptor meta core 0]} {
                error {CORE modules are bundled and excluded from this installer}
            }
            if {[dict get $admission type] eq {module}} {
                set kind [::GX::descriptorValue $descriptor meta kind {}]
                set selectable [::GX::descriptorValue $descriptor meta selectable 1]
                if {$kind eq {acquisition} || !$selectable} {
                    error {CORE and ALWAYS modules are bundled; the DEV112 installer must not install or update them}
                }
            }
        } finally {::GX::pluginPackageClose $admission}
        # Do not pump idle events on the normal synchronous path. If an
        # ordinary catalog child is already running, wait through CORE's
        # existing gate; never bypass or replace its quiescence checks.
        set deadline [expr {[clock milliseconds]+30000}]
        while {[catch {::GX::pluginRuntimeCheckQuiescent [::GX::pluginTargetPath $type $id]} reason options]} {
            if {![string match {*framework child process is active*} $reason] || [clock milliseconds]>$deadline} {
                return -options $options $reason
            }
            after 100
            update
        }
        set result [::GX::pluginInstallPackage $package $mode $id]
        if {[dict get $result type] ne $type} {error {Installed package type differs from plan}}
        if {![::GX::pluginRegistryIsManaged $id] || [::GX::pluginInstalledField $id version] ne [dict get $result version]} {
            error {Official installation did not produce the expected managed registration}
        }
        puts "INSTALLED\t$id\t$type\t[dict get $result version]\t[dict get $result action]"
        flush stdout
    }
}
if {[catch {::DEV112Install::run} reason options]} {
    puts stderr $reason
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
