# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework source destination expected policy
set argv0 __gxtxt_print_promote__;source [file join $framework gxtxt_pipeline.tcl]
try {::GX::defaults;puts [::GX::filePublicationCopy $source $destination $expected $policy]} on error {m o} {puts stderr $m;exit 1}
