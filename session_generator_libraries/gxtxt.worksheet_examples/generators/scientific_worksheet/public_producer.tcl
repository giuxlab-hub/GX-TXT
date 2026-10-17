# SPDX-License-Identifier: GPL-3.0-or-later
# This producer consumes public Session, Script Registry and Script Execution APIs.
lassign $argv framework session producer
set argv0 __gxtxt_public_worksheet_generator__
package require Tk
wm withdraw .
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
::GX::openSessionPath $session
set channel [open $producer r];fconfigure $channel -encoding utf-8;set code [read $channel];close $channel
::GX::scriptRegistrySave session worksheet_example_producer {Independent Scientific Workbook Producer} $code [dict create language Python version 1.0.0 required_apis {SCIENTIFIC_WORKSHEET_API_v1;PLOT_DATASET_API_v4;DATASET_PUBLICATION_API_v2;SESSION_WORKSPACE_API_v1} description {Deterministic signed source data, typed Workbook, exact public formula lineage and native charts}]
set result [::GX::scriptExecutionRun session:worksheet_example_producer {}]
puts $result
exit 0
