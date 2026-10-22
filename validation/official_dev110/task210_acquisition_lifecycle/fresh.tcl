# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] common.tcl]
if {[llength $argv]!=2} {error {Internal child requires FRAMEWORK_COPY EXISTING_PARENT_OUTPUT}}
lassign $argv framework out
set framework [::GX210Acq::admitCopy $framework]
set out [::GX210Acq::privatePath $out]
if {![file isfile [file join $out child_authorized.tcldict]]} {error {Missing parent run authorization}}
set authorization [::GX210Acq::readFile [file join $out child_authorized.tcldict]]
if {[dict get $authorization framework] ne $framework} {error {Child framework differs from parent authorization}}
::GX210Acq::boot $framework $out
set result {}
foreach suffix {loaded cold async} {
    set id acq.gx210_lifecycle_$suffix
    set inspection [::GX::acquisitionHandlerInspect $id [file join $out fixture.txt]]
    set hid [::GX::moduleRunnerHandler $id]
    dict set result $suffix [dict create format [dict get $inspection format] \
        registration $::GX::acquisitionHandlerRegistry($hid) runtime [::GX::pluginRuntimeInfo $id]]
}
::GX210Acq::writeFile [file join $out fresh_result.tcldict] $result
puts {Fresh interpreter acquisition observations recorded}
