# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only scientific guard in an isolated managed worker environment.
lassign $argv framework session guards
set argv0 __gxtxt_print_source_verify__
source [file join $framework gxtxt_pipeline.tcl]
try {
    ::GX::defaults;::GX::loadModuleCatalog
    set ::GX::currentSession $session
    ::GX::loadManifest [file join $session metadata manifest.ini]
    ::GX::loadDatasetRegistry $session
    set f [open $guards r];fconfigure $f -encoding utf-8;set data [read $f];close $f
    dict for {id node} [dict get $data nodes] {::GX::scientificExecutionNodeRegister $id $node}
    dict for {id expected} [dict get $data datasets] {
        if {[::GX::datasetViewerScientificIdentity $id] ne $expected} {error "Dataset $id scientific schema, metadata, calibration or source revision changed."}
        if {[::GX::datasetProviderFor $id] eq {remote}} {::GX::datasetRemoteVerify $id}
    }
    puts {Scientific source guards verified.}
} on error {message options} {puts stderr $message;exit 1}
