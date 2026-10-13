# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Native2DExport {}
proc ::GX::Native2DExport::_render {format context} {
    if {![dict exists $context presentation_snapshot]} {error "Export needs a Native2D presentation snapshot"}
    set snapshot [dict get $context presentation_snapshot]
    if {[dict get $snapshot api_id] ne "NATIVE2D_PRESENTATION_SNAPSHOT_v1" || [dict get $snapshot api_version]!=1} {error "Unsupported Native2D snapshot"}
    set channel [file tempfile input];set output "${input}.${format}"
    try {
        fconfigure $channel -encoding utf-8 -translation lf
        puts -nonewline $channel $snapshot;close $channel;set channel ""
        set renderer [file join [file dirname [::GX::moduleField export.native2d_presentation descriptor ""]] runtime native2d_export.py]
        set scale [::GX::datasetPublicationV2DictDefault [dict get $context parameters] scale 1]
        exec [::GX::runtimeToolResolve python] -B $renderer $input $output $format $scale
        set reader [open $output rb];try {set bytes [read $reader]} finally {close $reader}
        return [dict create status ok format $format bytes $bytes warnings {} export_policy [dict create source Native2D_presentation_snapshot point_budget [dict get $snapshot point_budget] scientific_materialization 0 clipping native_viewport vector [expr {$format eq "svg"}]]]
    } finally {
        if {$channel ne ""} {close $channel}
        file delete -force -- $input $output
    }
}
proc ::GX::Native2DExport::svg {context} {return [_render svg $context]}
proc ::GX::Native2DExport::png {context} {return [_render png $context]}
