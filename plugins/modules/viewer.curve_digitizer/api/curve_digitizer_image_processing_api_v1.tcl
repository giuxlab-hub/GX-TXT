# GX-TXT Curve Digitizer processed Image Dataset public contract.
# SPDX-License-Identifier: GPL-3.0-or-later
# This read-only facade uses the public Dataset registry/metadata APIs only.
namespace eval ::GX::CurveDigitizerImage {
    variable prefix curve_digitizer.image_processing.
}
proc ::GX::CurveDigitizerImage::_required {metadata suffix} {
    variable prefix
    set key "${prefix}${suffix}"
    if {![dict exists $metadata $key]} {error "Processed image metadata is missing '$key'."}
    return [dict get $metadata $key]
}
proc ::GX::CurveDigitizerImage::_context {datasetId {session {}}} {
    if {[string trim $datasetId] eq {}} {error {An Image Dataset ID is required.}}
    set current [::GX::sessionInspectionCurrentSession]
    if {$session eq {}} {set session $current}
    if {$current eq {} || [file normalize $current] ne [file normalize $session]} {
        error {Processed image inspection requires the current GX-TXT Session.}
    }
    set dataset [::GX::sessionInspectionDataset $datasetId $session]
    set contract [expr {[dict exists $dataset contract] ? [dict get $dataset contract] : [dict get $dataset kind]}]
    if {$contract ne {image.raster}} {error "Dataset '$datasetId' is not an image.raster Dataset."}
    set md [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $md curve_digitizer.image_processing.schema_version]} {
        error "Dataset '$datasetId' has no Curve Digitalizer Image Processing manifest."
    }
    return [dict create session $session metadata $md dataset $dataset]
}
proc ::GX::CurveDigitizerImage::read {datasetId {session {}}} {
    set ctx [_context $datasetId $session]
    set md [dict get $ctx metadata]
    if {[_required $md schema_version] ne {1} || [_required $md producer_id] ne {viewer.curve_digitizer}} {
        error {Unsupported processed-image manifest schema or producer.}
    }
    set source [_required $md source_dataset_id]
    set sourceSha [string tolower [_required $md source_sha256]]
    if {$source eq {} || ![regexp {^[a-f0-9]{64}$} $sourceSha]} {error {Invalid original image identity.}}
    if {[_required $md engine] ne {ImageMagick}} {error {Unsupported image processing engine.}}
    set preserved [_required $md geometry_preserved]
    set transform [_required $md pixel_transform]
    if {$preserved ne {1} || $transform ne {identity}} {error {Image Processing manifest does not preserve raster geometry.}}
    set width [_required $md image_width];set height [_required $md image_height]
    foreach {field value} [list width $width height $height] {
        if {![string is integer -strict $value] || $value < 1 || $value > 100000} {error "Invalid output image $field."}
    }
    set count [_required $md operation_count]
    if {![string is integer -strict $count] || $count < 1 || $count > 30} {error {Invalid processed-image operation count.}}
    set operations {}
    set known {grayscale channel gamma brightness_contrast auto_level contrast_stretch clahe threshold median negate sharpen}
    for {set i 0} {$i < $count} {incr i} {
        set kind [_required $md operation.$i.kind]
        set value [_required $md operation.$i.value]
        if {$kind ni $known || [regexp {[\r\n]} $value]} {error "Invalid processing operation at index $i."}
        lappend operations [dict create kind $kind value $value]
    }
    set digest [string tolower [_required $md fingerprint]]
    if {![regexp {^[a-f0-9]{64}$} $digest]} {error {Invalid processing fingerprint.}}
    set recorded [dict get $ctx dataset]
    set outputSha [expr {[dict exists $recorded canonical_sha256] ? [dict get $recorded canonical_sha256] : {}}]
    return [dict create api_id CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1 api_version 1 \
        dataset_id $datasetId source_dataset_id $source \
        source_display_name [_required $md source_display_name] source_sha256 $sourceSha \
        processing_operations $operations operation_count $count \
        processing_engine ImageMagick processing_engine_version [_required $md engine_version] \
        geometry_preserved 1 pixel_transform identity \
        image_width $width image_height $height processing_fingerprint $digest \
        output_sha256 $outputSha]
}
proc ::GX::CurveDigitizerImage::operations {datasetId {session {}}} {
    return [dict get [read $datasetId $session] processing_operations]
}
proc ::GX::CurveDigitizerImage::lineage {datasetId {session {}}} {
    if {$session eq {}} {set session [::GX::sessionInspectionCurrentSession]}
    set chain {};set visited {}
    set current $datasetId
    for {set i 0} {$i < 64} {incr i} {
        if {$current in $visited} {error {Cycle detected in processed image lineage.}}
        lappend visited $current
        if {[catch {set info [read $current $session]} errorMessage]} {
            # Only an actual non-processed image may terminate the chain.
            # A corrupt processed-image manifest must fail, not become a root.
            if {![llength $chain]} {error $errorMessage}
            set possible [::GX::datasetMetadataRead $session $current]
            if {[dict exists $possible curve_digitizer.image_processing.schema_version]} {
                error $errorMessage
            }
            set record [::GX::sessionInspectionDataset $current $session]
            set kind [expr {[dict exists $record contract] ? [dict get $record contract] : [dict get $record kind]}]
            if {$kind ne {image.raster}} {error {Image lineage parent is not an image.raster Dataset.}}
            set sha [expr {[dict exists $record canonical_sha256] ? [dict get $record canonical_sha256] : {}}]
            if {[dict get [lindex $chain end] source_sha256] ne [string tolower $sha]} {
                error {Image lineage SHA-256 does not match its canonical source.}
            }
            lappend chain [dict create dataset_id $current source_dataset_id {} output_sha256 $sha original 1]
            return $chain
        }
        lappend chain [dict create dataset_id $current source_dataset_id [dict get $info source_dataset_id] \
                              source_sha256 [dict get $info source_sha256] \
                              output_sha256 [dict get $info output_sha256] \
                              processing_fingerprint [dict get $info processing_fingerprint] original 0]
        set next [dict get $info source_dataset_id]
        # Verify each parent before traversing; never silently trust a stale ID.
        set parent [::GX::sessionInspectionDataset $next $session]
        set actual [expr {[dict exists $parent canonical_sha256] ? [string tolower [dict get $parent canonical_sha256]] : {}}]
        if {$actual ne [dict get $info source_sha256]} {error "Image lineage source '$next' changed or has mismatched SHA-256."}
        set current $next
    }
    error {Processed-image lineage exceeds its maximum depth.}
}
proc ::GX::CurveDigitizerImage::hasManifest {datasetId {session {}}} {
    return [expr {![catch {read $datasetId $session}]}]
}
