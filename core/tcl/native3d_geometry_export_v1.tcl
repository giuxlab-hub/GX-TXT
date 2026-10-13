# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] scientific_provider_transport_v1.tcl]
proc ::GX::native3DGeometryExportData {context format {mode bytes}} {
    if {$mode ni {bytes resource}} {error "Invalid Native3D export transport"}
    if {$format ni {step stl vtp}} {error "Choose an audited Native3D STEP, STL or VTP exporter"}
    set snapshot [dict get $context presentation_snapshot]
    if {[dict get $snapshot api_id] ne "NATIVE3D_GEOMETRY_EXPORT_SNAPSHOT_v1"||[dict get $snapshot api_version]!=1} {error "Invalid Native3D geometry export snapshot"}
    set owner [interactiveDocumentRead [dict get $context document_id]]
    if {[dict get $owner revision]!=[dict get $context revision]||[dict get $snapshot document_id] ne [dict get $context document_id]} {error "Geometry export snapshot is stale"}
    set source [dict get $snapshot object];set role [datasetPublicationV2DictDefault $source geometry_role regular]
    if {$role ne "regular"} {error "Construction/reference geometry is excluded from normal export"}
    interactiveDocumentResourceInfo [dict get $source geometry]
    set unit [dict get $snapshot working_unit];unitRegistryConversionPlan $unit mm
    set scale [expr {[unitRegistryIntrinsicScale $unit]/[unitRegistryIntrinsicScale mm]}]
    set scene {};set reader {};set bytes {}
    try {
        set scene [native3DGeometryOpen [dict get $context document_id]]
        set geometry [native3DGeometryCall $scene [expr {[dict get $source kind] eq "brep" ? "load_step" : "load_mesh"}] [dict create resource [dict get $source geometry]]]
        set object [dict get $geometry object_token]
        if {$format eq "step"&&[dict get $source kind] ne "brep"} {error "STEP export requires an exact accepted B-Rep"}
        if {$format ne "step"&&[dict get $source kind] eq "brep"} {
            set parameters [dict get $context parameters]
            set request [dict create object_token $object]
            foreach {key default} {linear_deflection .01 angular_deflection .3 weld_tolerance 1e-8 max_triangles 1000000 max_output_bytes 134217728} {dict set request $key [datasetPublicationV2DictDefault $parameters $key $default]}
            set geometry [native3DGeometryCall $scene mesh $request];set object [dict get $geometry object_token]
        }
        set resource [native3DGeometryExportResource $scene $object $format $scale]
        if {[dict get $resource size_bytes]>134217728} {error "Geometry file export exceeds the explicit128MiB bound"}
        if {$mode eq "resource"} {return [dict create status ok format $format resource $resource working_unit $unit source_object_id [dict get $snapshot object_id] object $source]}
        set reader [interactiveDocumentResourceOpenReader $resource]
        while 1 {set part [interactiveDocumentResourceNext $reader];append bytes [dict get $part bytes];if {[dict get $part eof]} break}
        if {[dict get [interactiveDocumentRead [dict get $context document_id]] revision]!=[dict get $context revision]} {error "Geometry changed during file export"}
        set metadata [dict create format gxtxt.native3d_geometry_export.v1 geometry_format $format working_unit $unit source_object_id [dict get $snapshot object_id] source_name [dict get $source name] source_geometry_sha256 [dict get $source geometry sha256] source_document_id [dict get $context document_id] source_document_revision [dict get $context revision] geometry_role $role geometry_policy complete_native_world_geometry api_id NATIVE_3D_GEOMETRY_API_v1 api_version 1 module_id [dict get $context workbench_id] module_version [dict get $context workbench_version] tessellation_parameters [dict get $context parameters] source_provenance [dict get $source provenance] source_bindings [dict get $source source_bindings]]
        set entries {};dict for {key value} $metadata {lappend entries "[::GX::ScientificTransportv1::_escape $key]:[::GX::ScientificTransportv1::_escape $value]"}
        set sidecar [encoding convertto utf-8 "{[join $entries ,]}\n"]
        return [dict create status ok format $format bytes $bytes sidecars [list [dict create suffix .gxtxt.json bytes $sidecar]] warnings {} export_policy [dict create geometry complete_native working_unit $unit source_object_id [dict get $snapshot object_id] native_resource $resource tessellation_parameters [dict get $context parameters] sidecar_encoding json_string_fields_v1 implicit_dataset_publication 0]]
    } finally {if {$reader ne {}} {interactiveDocumentResourceCloseReader $reader};if {$scene ne {}} {native3DGeometryClose $scene}}
}
proc ::GX::native3DGeometryPublishDataset {context format requested} {
    set requested [datasetPublicationV2RequestedId $requested geometry]
    if {$requested in [datasetRegistryIds]} {error "Dataset ID '$requested' already exists"}
    set receipt [native3DGeometryExportData $context $format resource]
    set source [dict get $receipt object];set resource [dict get $receipt resource]
    set writer {};set reader {};set path {}
    try {
        set writer [file tempfile path];fconfigure $writer -translation binary -encoding binary
        set reader [interactiveDocumentResourceOpenReader $resource]
        while 1 {set chunk [interactiveDocumentResourceNext $reader];puts -nonewline $writer [dict get $chunk bytes];if {[dict get $chunk eof]} break}
        close $writer;set writer {};interactiveDocumentResourceCloseReader $reader;set reader {}
        if {[dict get [interactiveDocumentRead [dict get $context document_id]] revision]!=[dict get $context revision]} {error "Geometry export context is stale"}
        set metadata [dict create dataset.display_name $requested geometry.working_unit [dict get $receipt working_unit] geometry.source_object_id [dict get $receipt source_object_id] geometry.document_id [dict get $context document_id] geometry.document_revision [dict get $context revision] geometry.complete 1 geometry.provenance [dict get $source provenance] geometry.source_bindings [dict get $source source_bindings] geometry.attributes [dict get $source attrs] geometry.role regular geometry.tessellation_parameters [dict get $context parameters] geometry.export_provider export.native3d_geometry]
        set sources {}
        foreach binding [dict get $source source_bindings] {
            if {[dict exists $binding source_descriptor]} {foreach identity [dict get $binding source_descriptor source_identities] {if {[dict exists $identity dataset_id]&&[dict get $identity dataset_id] ni $sources} {lappend sources [dict get $identity dataset_id]}}} elseif {[dict exists $binding source_dataset_id]&&[dict get $binding source_dataset_id] ni $sources} {lappend sources [dict get $binding source_dataset_id]}
        }
        set result [datasetFilePublicationPublish $::GX::currentSession export.native3d_geometry [dict create dataset_id $requested contract [expr {$format eq "step" ? "model.cad" : "geometry.mesh"}] format $format source_file $path source_dataset_ids $sources storage_kind binary media_type application/octet-stream producer_version 1.0.0 provenance "Explicit complete Native3D $format from [dict get $receipt source_object_id]" structured_metadata $metadata]]
        return [dict merge $result [dict create status ok created_ids [list $requested] implicit_dataset_publication 0]]
    } finally {if {$reader ne {}} {interactiveDocumentResourceCloseReader $reader};if {$writer ne {}} {close $writer};if {$path ne {}} {file delete -force -- $path}}
}
