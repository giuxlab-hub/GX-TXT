# GX-TXT Scientific Image Inspector headless integration tests.
# Generates disposable images; uses GX public-API doubles only for Session calls.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
set magick [expr {[info exists ::env(GXTXT_TEST_MAGICK)] ? $::env(GXTXT_TEST_MAGICK) : [auto_execok magick]}]
if {$magick eq ""} {puts stderr {SKIP: ImageMagick 'magick' was not found}; exit 77}
set fd [file tempfile work]
close $fd; file delete $work; file mkdir $work
set ::testWork $work
set ::testMagick $magick
proc check {label test} {
    if {![uplevel 1 [list expr $test]]} {error "TEST FAILURE: $label"}
    puts "PASS: $label"
}
namespace eval ::GX {
    variable publishCount 0
    variable docs {}
    proc runtimeToolRequired {name} {return $::testMagick}
    proc configurationTempDirectory {} {return $::testWork}
    proc sessionInspectionCurrentSession {} {return $::testWork}
    proc sessionInspectionDatasetIds {args} {return {rgb gray alpha multi}}
    proc sessionInspectionDataset {id args} {return [dict create contract image.raster format png media_type image/png]}
    proc sessionInspectionDatasetPayload {id args} {
        set name [dict get {rgb rgb.png gray gray16.tif alpha alpha.png multi multi.tif} $id]
        set path [file join $::testWork $name]
        return [dict create path $path sha256 [lindex [exec sha256sum -- $path] 0]]
    }
    proc sha256File {path} {return [lindex [exec sha256sum -- $path] 0]}
    proc datasetMetadataRead {session id} {
        if {$id eq "gray.published" && [info exists ::lastPublishedRequest]} {
            return [dict get $::lastPublishedRequest structured_metadata]
        }
        return [dict create source.instrument {test fixture}]
    }
    proc contractSatisfies {given required} {expr {$given eq $required}}
    proc interactiveDocumentSessionToken {} {return session-token-fixture}
    proc datasetFilePublicationPublish {session module req} {
        if {$module ne {viewer.scientific_image_inspector}} {error "Wrong publishing module"}
        if {[dict get $req contract] ne {image.raster}} {error "Wrong contract"}
        if {[dict get $req source_dataset_ids] ne {gray}} {error "Wrong parent Dataset"}
        if {![file isfile [dict get $req source_file]]} {error "Missing image file"}
        set ::lastPublishedRequest $req
        incr ::GX::publishCount
        return [dict create dataset_id [dict get $req dataset_id] sha256 [sha256File [dict get $req source_file]]]
    }
}
source [file join $root runtime catalog.tcl]
source [file join $root runtime engine.tcl]
source [file join $root runtime annotations_json.tcl]
source [file join $root runtime manifest.tcl]
set ::GX::SII::version 0.1.0
set ::GX::SII::moduleId viewer.scientific_image_inspector
namespace path ::GX::SII
set status 0
try {
    exec $magick -size 88x72 gradient:red-blue -depth 8 [file join $work rgb.png]
    exec $magick -size 96x64 gradient: -colorspace Gray -depth 16 [file join $work gray16.tif]
    exec $magick -size 90x70 xc:none -fill #2244CC88 -draw {rectangle 8,8 60,55} [file join $work alpha.png]
    exec $magick [file join $work rgb.png] [file join $work alpha.png] [file join $work multi.tif]
    set opCount [llength [catalogList]]
    check catalog_count {$opCount >= 60}
    set runnable [lsearch -all -inline [lmap o [catalogList] {dict get $o support}] executable]
    check broad_operations {[llength $runnable] >= 40}
    check disabled_fx {[dict get [operationStatus fx] state] eq "disabled"}
    check metadata_16bit {[dict get [inspect gray] depth] == 16}
    check original_sha {[dict get [sourceInfo gray] sha256] ne ""}
    check multipage {[dict get [inspect multi] frame_count] == 2}
    set before [::GX::sha256File [file join $work gray16.tif]]
    set steps [list [dict create op gamma params {gamma 1.1} scope all roi {}] \
        [dict create op gaussian_blur params {sigma 1.2 radius 0} scope all roi {}]]
    set a [process gray $steps tiff16]
    check process_tiff16 {[file isfile [dict get $a result_path]]}
    check full_precision {[dict get [inspectFile [dict get $a result_path]] depth] == 16}
    check source_unchanged {$before eq [::GX::sha256File [file join $work gray16.tif]]}
    releaseResult [dict get $a result_path]
    check release_temp {![file exists [dict get $a result_path]]}
    set a [process gray {} tiff32f]
    check float_tiff {[file isfile [dict get $a result_path]]}
    releaseResult [dict get $a result_path]
    set roiStep [list [dict create op threshold params {threshold 50} scope roi roi {5 6 20 12}]]
    set a [process rgb $roiStep png16]
    check roi_output {[file isfile [dict get $a result_path]]}
    releaseResult [dict get $a result_path]
    set result [stats [dict get [sourceInfo rgb] path] {} R]
    check channel_stats {[dict exists $result mean] && [dict exists $result unique_colors]}
    set pal [palette [dict get [sourceInfo rgb] path] {} 8]
    check quantized_palette {[llength $pal] > 1 && [llength $pal] <= 8}
    set histogramResult [histogram [dict get [sourceInfo rgb] path] R]
    set sum 0
    foreach v [dict get $histogramResult bins] {incr sum $v}
    check histogram_complete {$sum == 88 * 72}
    set p [pixel [dict get [sourceInfo rgb] path] 2 3]
    check pixel_inspection {[string first {2,3} $p] == -1 && [string first {0,0} $p] >= 0}
    check reject_injection {[catch {validate gamma {gamma {1;exec rm -rf /}}}]}
    check reject_bad_geometry {[catch {validate resize {geometry {1x1@/etc/passwd}}}]}
    check reject_bad_operation {[catch {validate fx {}}]}
    check reject_unknown_params {[catch {validate gamma {gamma 1 unknown 8}}]}
    check reject_illegal_path_release {[catch {releaseResult /etc/passwd}]}
    set published [publish gray $steps gray.published tiff16]
    check metadata_manifest {[dict exists [dict get $::lastPublishedRequest structured_metadata] image.inspector.manifest]}
    check manifest_identity {[dict get [dict get [dict get $::lastPublishedRequest structured_metadata] image.inspector.manifest] output dataset_id] eq "gray.published"}
    set readBack [manifestGet gray.published]
    check public_manifest_lookup {[dict get $readBack output dataset_id] eq "gray.published"}
    check public_manifest_steps {[llength [dict get $readBack operation_steps]]==2}
    check manifest_api_summary {[dict get [apiCall manifest_summary gray.published] operation_count]==2}
    check manifest_wrong_target {[catch {manifestGet nonexistent}]} 
    check publish_once {$::GX::publishCount == 1 && [dict get $published dataset_id] eq "gray.published"}
    check publish_source_unchanged {$before eq [::GX::sha256File [file join $work gray16.tif]]}
    puts {ALL HEADLESS TESTS PASSED}
} on error {message options} {
    puts stderr "FAILED: $message\n[dict get $options -errorinfo]"
    set status 1
} finally {
    cleanTemps
    file delete -force -- $work
}
exit $status
