# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::AcqSketch {}
proc ::AcqSketch::inspect {request} {
    set sketch [::GX::sketchDatasetReadFile [dict get $request source_path]]
    return [dict create recognized 1 format gxsketch variables {} metadata {} warnings {} preview_kind metadata preview_metadata [dict create Format {Canonical Sketch 1.0} Objects [dict size [dict get $sketch objects]]]]
}
proc ::AcqSketch::import {request} {
    set raw [dict get $request raw_path];::GX::sketchDatasetReadFile $raw
    set id [dict get $request dataset_id];set name $id.gxsketch
    file copy -- $raw [file join [dict get $request output_dir] $name]
    return [dict create datasets [list [dict create dataset_id $id contract geometry.sketch format gxsketch path $name storage_kind text media_type application/vnd.gxtxt.sketch variables {} units {} semantic_roles {} source {Sketch geometry} provenance {Validated exact portable geometry; no scientific sources imported}]]]
}
proc ::AcqSketch::preview {request} {
    set output [file join [dict get $request preview_dir] sketch.png]
    ::GX::sketchDatasetPreview [dict get $request dataset_path] $output
    return [dict create preview_kind artifact preview_artifact [dict create path $output media_type image/png label {Sketch geometry}]]
}
