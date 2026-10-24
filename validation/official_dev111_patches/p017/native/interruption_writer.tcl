# SPDX-License-Identifier: GPL-3.0-or-later
# Owned subprocess of contract.tcl: writes only a caller-supplied fresh fixture.
lassign $argv framework dir
if {[llength $argv]!=2 || [file exists $dir]} {error {usage: interruption_writer.tcl FRAMEWORK NEW_OUTPUT}}
file mkdir $dir
load [file join $framework core history libgxtxt_history.so] Gxtxt_history
set initial [dict create format gxtxt.scientific_recipe.v1 workbench_id test.owner required_apis SCIENTIFIC_RECIPE_API_v1 plugin_versions {} sources {} retention complete base [dict create value 0] steps {} cursor 0]
set h [::GX::historyNative open test.owner $initial [file join $dir killed.gxh] interruption#one]
for {set n 1} {$n<=32} {incr n} {::GX::historyNative appendPatch $h [dict create value $n] "durable $n"}
::GX::historyNative flush $h
set block [string repeat abcdefghijklmnopqrstuvwxyz012345 72]
for {set n 33} {$n<=1000} {incr n} {::GX::historyNative appendPatch $h [dict create value "$n:$block"] "pending $n"}
set f [open [file join $dir ready] w];puts $f [::GX::historyNative status $h];close $f
vwait forever
