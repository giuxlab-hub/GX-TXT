#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework session
set argv0 __job_recovery__;source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
set ::GX::currentSession $session
if {[catch {::GX::datasetPublicationRecover $session} reason]} {puts stderr $reason;exit 1}
puts {PUBLICATION_RECOVERY_PASS}
