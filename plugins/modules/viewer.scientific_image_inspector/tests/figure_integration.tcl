# Standalone figure editing/annotation/export contract tests with disposable images.
# SPDX-License-Identifier: GPL-3.0-or-later
set root [file normalize [file join [file dirname [info script]] ..]]
set work [file tempfile scratch];close $work;file delete -- $scratch;file mkdir $scratch
set magick [auto_execok magick]
set ::testWork $scratch;set ::testMagick $magick
proc test {name expression} {
    if {![uplevel 1 [list expr $expression]]} {error "FAILED $name"}
    puts "PASS: $name"
}
namespace eval ::GX {
    proc runtimeToolRequired {name} {return $::testMagick}
    proc configurationTempDirectory {} {return $::testWork}
    proc sessionInspectionCurrentSession {} {return $::testWork}
    proc sessionInspectionDatasetIds {args} {return {a b}}
    proc sessionInspectionDataset {id args} {return [dict create contract image.raster format png media_type image/png]}
    proc sessionInspectionDatasetPayload {id args} {
        set path [file join $::testWork ${id}.png]
        return [dict create path $path sha256 [lindex [exec sha256sum -- $path] 0]]
    }
    proc sha256File {path} {return [lindex [exec sha256sum -- $path] 0]}
    proc contractSatisfies {a b} {expr {$a eq $b}}
    proc datasetMetadataRead {args} {return {}}
    proc datasetFilePublicationPublish {session module request} {
        set ::lastPublication $request
        return [dict create dataset_id [dict get $request dataset_id] sha256 [::GX::sha256File [dict get $request source_file]]]
    }
}
source [file join $root runtime catalog.tcl]
source [file join $root runtime engine.tcl]
source [file join $root runtime annotations_json.tcl]
source [file join $root runtime manifest.tcl]
source [file join $root runtime article.tcl]
set ::GX::SII::moduleId viewer.scientific_image_inspector
set ::GX::SII::version 0.2.0
set failed 0
try {
    exec $magick -size 120x90 gradient:blue-orange PNG:[file join $scratch a.png]
    exec $magick -size 100x140 gradient:green-yellow PNG:[file join $scratch b.png]
    set before1 [::GX::sha256File [file join $scratch a.png]]
    set before2 [::GX::sha256File [file join $scratch b.png]]
    set panels {}
    foreach id {a b} {
        lappend panels [dict create source_id $id source_sha [dict get [::GX::SII::sourceInfo $id] sha256] steps [list [dict create op auto_level params {} scope all]]]
    }
    set settings [dict create width 640 height 460 margin 20 gutter 12 layout horizontal background #FFFFFF]
    set a [dict create kind text text A x1 40 y1 35 size 35 stroke 3 color #FFFFFF]
    set b [dict create kind arrow x1 400 y1 120 x2 510 y2 200 stroke 5 color #FF0000]
    set c [dict create kind rectangle x1 48 y1 110 x2 150 y2 240 stroke 3 color #112233]
    set overlay [list $a $b $c]
    set output [file join $scratch composed.tif]
    set receipt [::GX::SII::figureCreate $panels $settings $overlay $output tiff16]
    test composed_file {[file isfile $output] && [file size $output]>0}
    set info [::GX::SII::inspectFile $output]
    test composed_dimensions {[dict get $info width]==640 && [dict get $info height]==460}
    test preserved_precision {[dict get $info depth]==16}
    test annotation_count {[dict get $receipt annotation_count]==3}
    set rotated [::GX::SII::validateAnnotation [dict merge $c [dict create id ann18 rotation 30 pivot_x 85 pivot_y 170]] 640 460]
    test retained_transform {[dict get $rotated id] eq "ann18" && [dict get $rotated rotation]==30}
    set moved [::GX::SII::annotationTransformPoint $rotated 48 110]
    test native_rotation {[lindex $moved 0]!=48 || [lindex $moved 1]!=110}
    set rotatedOutput [file join $scratch rotated.png]
    ::GX::SII::figureCreate $panels $settings [list $rotated [dict merge $a [dict create rotation 25]]] $rotatedOutput png8
    test rotated_publish_raster {[file isfile $rotatedOutput] && [file size $rotatedOutput]>0}
    set annotationsJson [::GX::SII::annotationsJson [list $rotated]]
    test rotated_json {[string first {"rotation":30} $annotationsJson]>=0 && [string first {"pivot_x":85} $annotationsJson]>=0}
    test pivot_pair_validated {[catch {::GX::SII::validateAnnotation [dict remove $rotated pivot_y] 640 460}]}
    ::GX::SII::figurePublish $panels $settings [list $rotated] figure.rotated png16
    set stored [dict get [dict get $::lastPublication structured_metadata] image.inspector.manifest]
    test rotation_metadata_published {[dict get [lindex [dict get $stored annotations] 0] rotation]==30}
    set caption [dict merge $a [dict create font_family DejaVu-Sans font_unit pt font_value 12 font_dpi 300 size 50 box_width 120 box_height 55]]
    set captionValidated [::GX::SII::validateAnnotation $caption 640 460]
    test font_units_retained {[dict get $captionValidated font_unit] eq "pt" && [dict get $captionValidated font_dpi]==300}
    set typedCaption [file join $scratch caption.png]
    ::GX::SII::figureCreate $panels $settings [list $captionValidated] $typedCaption png16
    test selected_font_publication {[file isfile $typedCaption] && [file size $typedCaption]>0}
    set captionJson [::GX::SII::annotationsJson [list $captionValidated]]
    test font_json_manifest {[string first {"font_family":"DejaVu-Sans"} $captionJson]>=0 && [string first {"font_dpi":300} $captionJson]>=0}

    test immutable_first {[::GX::sha256File [file join $scratch a.png]] eq $before1}
    test immutable_second {[::GX::sha256File [file join $scratch b.png]] eq $before2}
    test rejects_bad_color {[catch {::GX::SII::validateAnnotation [dict replace $a color red] 640 460}]}
    test rejects_text_expansion {[catch {::GX::SII::validateAnnotation [dict replace $a text {@/etc/passwd}] 640 460}]}
    test rejects_bad_dimension {[catch {::GX::SII::figurePlan $panels 400 300 200 20 horizontal}]}
    set web [file join $scratch composed.webp]
    ::GX::SII::figureCreate $panels $settings $overlay $web webp
    test web_created {[file isfile $web]}
    set pub [::GX::SII::figurePublish $panels $settings $overlay figure.1 png16]
    test published {[dict get $pub dataset_id] eq "figure.1"}
    test both_lineages {[lsort [dict get $::lastPublication source_dataset_ids]] eq {a b}}
    test manifest_present {[dict exists [dict get $::lastPublication structured_metadata] image.inspector.manifest]}
    test manifest_lineage {[dict size [dict get [dict get [dict get $::lastPublication structured_metadata] image.inspector.manifest] source_sha256_map]] == 2}
    test metadata_recipe {[dict exists [dict get $::lastPublication structured_metadata] image.panels]}
    puts {FIGURE INTEGRATION TESTS PASSED}
} on error {msg opts} {
    puts stderr "FIGURE TEST FAILED: $msg\n[dict get $opts -errorinfo]"
    set failed 1
} finally {
    ::GX::SII::cleanTemps
    file delete -force -- $scratch
}
exit $failed
