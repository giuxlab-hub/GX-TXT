# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=3} {error {usage: scientific_history_portable_worker.tcl FRAMEWORK STAGE LOGICAL_DESTINATION}}
lassign $argv framework stage logicalDestination
set argv0 __gxtxt_native_history_transport__
source [file join $framework gxtxt_pipeline.tcl]
if {[catch {set result [::GX::scientificHistoryPortableRescope $stage $logicalDestination]} message options]} {puts stderr [dict get $options -errorinfo];exit 1}
puts [llength $result]
