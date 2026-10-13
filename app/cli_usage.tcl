# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::usage {} {
    puts "GX-TXT Pipeline v$::GX::version"
    puts ""
    puts "GUI:"
    puts "  wish gxtxt_pipeline.tcl"
    puts ""
    puts "Batch/headless:"
    puts "  tclsh gxtxt_pipeline.tcl --manifest file.ini --run"
    puts ""
    puts "Options:"
    puts "  --help                 show this help"
    puts "  --manifest FILE --run  run the pipeline from a manifest"
}

# Standard Module API v1 native-only profile. Only descriptor-conformant modules
# are discoverable in v0.7.1; legacy GX-TXT analysis algorithms remain archived
# in the source tree but are not registered or exposed by the GUI.
