# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework path mode
if {[llength $argv]!=3 || $mode ni {normal error} || [file exists $path]} {error {usage: exit_writer.tcl FRAMEWORK FRESH_PATH normal|error}}
load [file join $framework core history libgxtxt_history.so] Gxtxt_history
set record [dict create format gxtxt.scientific_recipe.v1 workbench_id auxiliary.owner required_apis SCIENTIFIC_RECIPE_API_v1 plugin_versions {} sources {} retention complete base {value 0} steps {} cursor 0]
set h [::GX::historyNative open auxiliary.owner $record $path exit#one]
::GX::historyNative auxiliary $h [dict create exit_mode $mode retained [string repeat metadata 1024]]
if {$mode eq "error"} {error {Controlled native writer exit fixture}}
