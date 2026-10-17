# Public, headless processing manifest for canonical image.raster Datasets.
# All persistence belongs to GX-TXT's Dataset Metadata + File Publication APIs.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII { variable manifestSchema scientific_image_inspector.manifest.v1 }

proc ::GX::SII::makeManifest {sourceId steps panels settings annotations format {workspaceId {}}} {
    variable manifestSchema
    set sources {}
    set sourceFacts {}
    set entries [expr {[llength $panels] ? $panels : [list [dict create source_id $sourceId steps $steps]]}]
    foreach panel $entries {
        set id [dict get $panel source_id]
        if {[string match {local:*} $id]} {error {Publish source images as canonical Datasets before creating a derived image}}
        set data [sourceInfo $id]
        if {[dict exists $panel source_sha] && [dict get $panel source_sha] ne [dict get $data sha256]} {
            error "Source Dataset '$id' SHA-256 changed"
        }
        dict set sources $id [dict get $data sha256]
        set facts [dict create format [dict get $data format] media_type [dict get $data media_type]             size_bytes [dict get $data size_bytes] sha256 [dict get $data sha256]]
        set technical [inspectFile [dict get $data path]]
        foreach field {width height depth channels colorspace orientation frames resolution_x resolution_y density_units} {
            dict set facts $field [dict get $technical $field]
        }
        # Source's own metadata is a verified CORE record, not inferred by DPI.
        dict set facts dataset_metadata [dict get $data metadata]
        dict set sourceFacts $id $facts
    }
    set geometry [dict create origin top-left coordinate_unit pixel calibrated 0]
    # The annotated figure canvas and image pipeline coordinate systems differ
    # only when explicit geometry operators are accepted in the recipe.
    set recipe [validateSteps $steps]
    set overlay {}
    foreach a $annotations {
        # Preserve editable definitions, not flattened preview samples.
        lappend overlay $a
    }
    return [dict create schema $manifestSchema producer_module viewer.scientific_image_inspector \
        source_sha256_map $sources source_facts $sourceFacts primary_source_id $sourceId \
        operation_steps $recipe figure_panels $panels figure_settings $settings \
        annotations $overlay annotation_layers_json [annotationsJson $overlay] coordinate_system $geometry \
        color_policy {Uncalibrated image values; no physical pixel size inferred from DPI; ICC is not silently assigned} \
        image_magick_version [magickVersion] \
        workspace_id $workspaceId \
        output [dict create format $format dataset_id {} expected_sha256 {}] \
        created_utc [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]]
}
proc ::GX::SII::manifestValidate {manifest} {
    variable manifestSchema
    if {[catch {dict size $manifest}]} {error {Image Inspector manifest is not a dictionary}}
    foreach key {schema producer_module source_sha256_map source_facts primary_source_id operation_steps figure_panels figure_settings annotations coordinate_system image_magick_version output created_utc} {
        if {![dict exists $manifest $key]} {error "Image Inspector manifest missing field: $key"}
    }
    if {[dict get $manifest schema] ne $manifestSchema} {error {Unsupported Image Inspector manifest schema}}
    if {[dict get $manifest producer_module] ne "viewer.scientific_image_inspector"} {error {Manifest does not belong to Scientific Image Inspector}}
    dict for {id sha} [dict get $manifest source_sha256_map] {
        if {$id eq {} || ![regexp -nocase {^[0-9a-f]{64}$} $sha]} {error {Manifest source identity is invalid}}
    }
    if {[dict exists $manifest annotation_layers_json] && [dict get $manifest annotation_layers_json] ne [annotationsJson [dict get $manifest annotations]]} {
        error {Published annotation JSON does not match the retained overlay definitions}
    }
    foreach key {format dataset_id expected_sha256} {
        if {![dict exists $manifest output $key]} {error "Manifest output missing $key"}
    }
    return $manifest
}
proc ::GX::SII::manifestGet {datasetId} {
    # This method works headlessly; no Tk, ImageMagick processing, or workspace GUI.
    set session [::GX::sessionInspectionCurrentSession]
    set metadata [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $metadata image.inspector.manifest]} {
        error "Dataset '$datasetId' has no Scientific Image Inspector manifest"
    }
    set manifest [manifestValidate [dict get $metadata image.inspector.manifest]]
    # Read-only consistency check against CORE's published file identity when available.
    if {[llength [info commands ::GX::sessionInspectionDatasetPayload]]} {
        if {![catch {set receipt [::GX::sessionInspectionDatasetPayload $datasetId $session]}]} {
            if {[dict exists $receipt sha256] &&                 ![string equal -nocase [dict get $receipt sha256] [dict get $manifest output expected_sha256]]} {
                error {Image Inspector manifest output SHA-256 mismatch}
            }
        }
    }
    if {[dict get $manifest output dataset_id] ne $datasetId} {
        error {Image Inspector manifest Dataset identity mismatch}
    }
    return $manifest
}
proc ::GX::SII::manifestSummary {datasetId} {
    set manifest [manifestGet $datasetId]
    return [dict create dataset_id $datasetId schema [dict get $manifest schema] \
        sources [dict get $manifest source_sha256_map] \
        operation_count [llength [dict get $manifest operation_steps]] \
        panel_count [llength [dict get $manifest figure_panels]] \
        annotation_count [llength [dict get $manifest annotations]] \
        output [dict get $manifest output] \
        workspace_id [dict get $manifest workspace_id]]
}
proc ::GX::SII::apiInfo {} {
    return [dict create api_id SCIENTIFIC_IMAGE_INSPECTOR_API_v1 manifest_schema scientific_image_inspector.manifest.v1 \
        operations {manifest_get manifest_summary annotations_json inspect catalog capabilities} gui_required 0]
}
proc ::GX::SII::apiCall {operation args} {
    switch -- $operation {
        manifest_get {if {[llength $args] != 1} {error {manifest_get requires dataset_id}};return [manifestGet [lindex $args 0]]}
        manifest_summary {if {[llength $args] != 1} {error {manifest_summary requires dataset_id}};return [manifestSummary [lindex $args 0]]}
        annotations_json {if {[llength $args]!=1} {error {annotations_json requires dataset_id}};return [annotationsJson [dict get [manifestGet [lindex $args 0]] annotations]]}
        inspect {if {[llength $args] != 1} {error {inspect requires dataset_id}};return [inspect [lindex $args 0]]}
        catalog {return [catalogList {*}$args]}
        capabilities {return [capabilities]}
        default {error "Unsupported Scientific Image Inspector API operation: $operation"}
    }
}
