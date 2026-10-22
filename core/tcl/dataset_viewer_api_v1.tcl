# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only consultation of canonical identities; no publication/write callback.
namespace eval ::GX::DatasetViewer {variable serial 0;variable state;variable previewImage {};variable previewJob {}}
proc ::GX::datasetViewerApiInfo {} {
    return [dict create api_id DATASET_VIEWER_API_v1 api_version 1 host_only 1 operations {datasetViewerDescribe datasetViewerOpen datasetViewerOpenMolecule datasetMediaViewerOpenResource datasetMediaViewerInspect} host_arguments [dict create datasetViewerDescribe {datasetId} datasetViewerOpen {datasetId} datasetViewerOpenMolecule {datasetId} datasetMediaViewerOpenResource {reference {title {Managed Document PDF}}} datasetMediaViewerInspect {owner}] result_contract [dict create datasetViewerDescribe {Canonical Dataset contract, format, target, read_only and revision metadata; no publication.} datasetViewerOpen {Existing registered canonical Dataset viewer owner; geometry.sketch retains its editing viewer.} datasetViewerOpenMolecule {Existing enabled Molecule Viewer opened with the exact canonical molecular.structure Dataset ID; no source conversion or implicit publication. Its ordinary Open 3D structure action provides chemical representations and conformers.} datasetMediaViewerOpenResource {Opaque shared managed-PDF reader owner; validates current Document, generation, Session and PDF resource bytes. No Dataset is created.} datasetMediaViewerInspect {Read-only public PDF receipt; managed source identifies Document/resource without Dataset ID, child process IDs or native control coordinates.}] profiles [dict create molecular_structure [dict create contract molecular.structure module_id viewer.molecule_3d viewer_id molecule_3d implicit_publication 0] managed_document_pdf [dict create source_kind managed_resource format pdf title_default {Managed Document PDF} runtime_owner existing_dataset_media_reader implicit_publication 0]]]
}
proc ::GX::datasetViewerDescribe {datasetId} {
    set payload [sessionInspectionDatasetPayload $datasetId]
    set contract [datasetField $datasetId contract [datasetField $datasetId kind {}]]
    set format [string tolower [dict get $payload format]]
    set media [datasetField $datasetId media_type {}]
    set kind unsupported
    if {$contract eq "geometry.sketch"} {set kind sketch
    } elseif {$format eq "pdf"||$contract eq "document.pdf"} {set kind pdf
    } elseif {$format in {stl obj step stp vtp vtu vti}||$contract in {geometry.mesh model.cad field.scalar_3d field.scalar_grid}} {set kind mesh
    } elseif {$contract in {molecular.structure structure.crystal}} {set kind structure
    } elseif {[string match image/* $media]||$contract eq "image.raster"} {set kind image
    } elseif {($contract eq "audio.waveform"&&$format in {csv hdf5 h5})} {set kind scientific
    } elseif {[string match audio/* $media]||$contract in {audio.source audio.waveform}} {set kind audio
    } elseif {$contract in {document.text code.source}||[string match text/* $media]&&$format ni {csv tsv}} {set kind text
    } elseif {$contract in {table.generic timeseries.table curve_family.table curve3d.table}||[string match spectrum.* $contract]||$format in {csv hdf5 h5}} {set kind scientific}
    return [dict create api_id DATASET_VIEWER_API_v1 dataset_id $datasetId contract $contract format $format media_type $media target $kind read_only [expr {$kind ne "sketch"}] implicit_publication 0 revision [dict get $payload sha256]]
}
proc ::GX::datasetViewerOpen {datasetId} {
    set info [datasetViewerDescribe $datasetId]
    if {[datasetDocumentKind $datasetId] ne {}} {return [datasetDocumentOpen $datasetId]}
    switch [dict get $info target] {
        scientific {return [scientificDatasetViewerOpen $datasetId]}
        mesh - structure {return [meshDatasetViewerOpen $datasetId]}
        pdf - image - audio {return [datasetMediaViewerOpen $datasetId [dict get $info target]]}
        sketch {return [viewerOpen viewer.curve_workbench curve_workbench [dict create sketch_dataset_id $datasetId]]}
        default {return [datasetConsultationOpen $datasetId $info]}
    }
}
proc ::GX::_datasetViewerMoleculeAvailable {id} {
    if {[datasetField $id contract [datasetField $id kind {}]] ne {molecular.structure}} {return 0}
    if {[moduleField viewer.molecule_3d descriptor {}] eq {}} {return 0}
    if {[catch {set available [viewerProviderEnabled viewer.molecule_3d molecule_3d]}]} {return 0}
    return $available
}
proc ::GX::datasetViewerOpenMolecule {id} {
    set info [datasetViewerDescribe $id]
    if {[dict get $info contract] ne {molecular.structure}} {error {Open in Molecule Viewer requires a canonical molecular.structure Dataset; numerical XYZ data use their scientific Preview.}}
    if {![_datasetViewerMoleculeAvailable $id]} {error {Molecule Viewer is unavailable or disabled. Enable its installed Viewer provider to inspect this molecular Dataset.}}
    return [viewerOpen viewer.molecule_3d molecule_3d [dict create dataset_id $id]]
}
proc ::GX::datasetPreviewOpenMoleculeCurrent {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne {imported} || $id eq {}} {error {Activate an imported canonical molecular Dataset first.}}
    return [datasetViewerOpenMolecule $id]
}
proc ::GX::datasetPreviewOpenCurrent {} {
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    if {$mode ne "imported"||$id eq {}} {error {Activate an imported canonical Dataset. Pending sources support Preview only.}}
    return [datasetViewerOpen $id]
}
proc ::GX::datasetPreviewUpdateOpenButton {} {
    set w .top.nb.channels.browser.tools.open
    if {![winfo exists $w]} return
    lassign [datasetInspectionParseChoice $::GX::variableDatasetChoice] mode id
    $w state [expr {$mode eq "imported"&&$id ne {}?"!disabled":"disabled"}]
    set molecule .top.nb.channels.browser.molecule
    if {![winfo exists $molecule]} {
        ttk::button $molecule -text {Open in Molecule Viewer} -command [list ::GX::datasetPageAction datasetPreviewOpenMoleculeCurrent]
        native2DViewportTooltip $molecule {Open this same canonical molecular Dataset in Molecule Viewer, then use Open 3D structure for chemical styles and conformers.}
    }
    if {$mode eq {imported} && $id ne {} && [datasetField $id contract [datasetField $id kind {}]] eq {molecular.structure}} {
        $molecule state [expr {[_datasetViewerMoleculeAvailable $id]?{!disabled}:{disabled}}]
        pack $molecule -side top -fill x -padx 3 -pady 3 -before .top.nb.channels.browser.current
    } else {pack forget $molecule}
}
proc ::GX::scientificDatasetAxes {id} {
    set numeric {};set axes {};set values {}
    foreach v [datasetVariableSchemaV3 $id] {
        if {![dict get $v enabled]||[dict get $v value_kind] eq "text"||[dict get $v rank]!=1} continue
        set vid [dict get $v variable_id];lappend numeric $vid
        if {[dict get $v coordinate_role] eq "coordinate"||[dict get $v value_kind] eq "elapsed_time"||[dict get $v semantic_role] in {time elapsed_time frequency energy wavelength wavenumber chemical_shift}} {lappend axes $vid} else {lappend values $vid}
    }
    set x {};set y {}
    if {[llength $axes]==1} {set x [lindex $axes 0];if {[llength $values]==1} {set y [lindex $values 0]}}
    if {![catch {set manifest [datasetPreviewCurveManifest $id]}] && $manifest ne {}} {
        set x [dict get $manifest columns x];set y [dict get $manifest columns y]
    }
    return [dict create numeric $numeric x $x y $y]
}

proc ::GX::scientificDatasetPreview {datasetId xId yId output {member {}}} {
    set filters {}
    if {$member ne {}} {
        foreach v [datasetVariableSchemaV3 $datasetId] {
            if {[dict get $v semantic_role] eq "member_identity" || [dict get $v variable_id] eq "member_id"} {
                set filters [list [dict create filter_variable_id [dict get $v variable_id] predicate in_set values [list $member]]];break
            }
        }
    }
    return [dict merge [scientificDatasetPreviewFiltered $datasetId $xId $yId $output [list $filters]] [dict create dataset_id $datasetId x_variable_id $xId y_variable_id $yId]]
}

proc ::GX::datasetViewerMetadataIdentity {session id} {
    # Public metadata is a map. Its writer may reorder keys while persisting
    # framework preferences; retain exact values, including opaque list text.
    set metadata [datasetMetadataRead $session $id]
    set ordered {}
    foreach key [lsort [dict keys $metadata]] {dict set ordered $key [dict get $metadata $key]}
    return $ordered
}
proc ::GX::datasetViewerStamp {id path} {
    if {[datasetField $id storage_provider {}] eq "remote"} {return [list remote [datasetField $id remote_node_id] [datasetField $id remote_session_id] [datasetField $id remote_revision] [datasetVariableSchemaV3 $id]]}
    file stat $path stat
    # Coordinate and Preview preferences share the metadata resource, but only
    # their framework bookkeeping may be acknowledged by an open host. Keep
    # the public fields in the same source stamp so a provenance edit cannot
    # leave the bound inspection snapshot silently current.
    return [list [sessionInspectionDataset $id] [datasetVariableSchemaV3 $id] $stat(size) $stat(mtime) $stat(ctime) $stat(ino) [datasetMetadataRead $::GX::currentSession $id]]
}
proc ::GX::datasetViewerCheck {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,identity)]} {error {Viewer is closed.}}
    if {$state($w,session) ne [interactiveDocumentSessionToken]} {error {Session changed; reopen this Dataset.}}
    if {[info exists state($w,managedResource)]} {
        # Retained Resource bytes can outlive deletion of their Document.
        # A live preview still requires its original live Document owner.
        set owner [interactiveDocumentRead $state($w,id)]
        if {[dict get $owner generation] ne $state($w,managedOwnerGeneration)} {error {Document owner changed; reopen its PDF preview.}}
        interactiveDocumentResourceInfo $state($w,managedResource)
        return
    }
    if {[info exists state($w,sourceCheck)]} {
        if {[uplevel #0 $state($w,sourceCheck)] ne $state($w,sourceKey)} {error {Native3D preview source/configuration changed; activate again.}}
    }
    set current [datasetViewerStamp $state($w,id) $state($w,path)]
    if {$current ne $state($w,stamp)} {
        # Scientific display policy may change without touching the source or
        # schema. Keep every other revision check, including filesystem identity.
        set verifiedProjection 0
        if {[info exists state($w,sourceCheck)] && [info exists state($w,sourceScientificIdentity)]} {
            # Prepared graph geometry need not have an XY coordinateContext.
            # Its sourceCheck above and complete scientific identity must both
            # remain exact before accepting bookkeeping-only metadata writes.
            set verifiedProjection [expr {[datasetViewerScientificIdentity $state($w,id)] eq $state($w,sourceScientificIdentity)}]
        }
        # Filter controls persist framework preferences before the first Plot.
        # The inspection host already binds the same canonical source then;
        # its public metadata component above still rejects provenance edits.
        set inspectedSource [info exists state($w,inspection)]
        if {(![info exists state($w,coordinateContext)] && !$verifiedProjection && !$inspectedSource) || [scientificDatasetCoordinateSourceStamp $current] ne [scientificDatasetCoordinateSourceStamp $state($w,stamp)]} {error {Dataset revision changed; reopen it explicitly.}}
        set state($w,stamp) $current
    }
}
proc ::GX::datasetViewerWatch {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[info exists state($w,previewChoice)]&&$state($w,previewChoice) ne $::GX::variableDatasetChoice} {datasetViewerClose $w;return}
    if {[catch {datasetViewerCheck $w;scientificDatasetViewerCoordinateRefresh $w} reason]} {datasetViewerClose $w;setStatus $reason 100;return}
    if {![info exists state($w,id)]} return
    set state($w,watch) [after 1000 [list ::GX::datasetViewerWatch $w]]
}
proc ::GX::datasetViewerClose {w} {
    variable ::GX::DatasetViewer::state
    if {[info exists state($w,summaryTrace)]} {
        foreach element {legend status} {trace remove variable state($w,$element) write $state($w,summaryTrace)}
    }
    foreach timer {watch drawJob memberScan externalWatch prepareAfter} {if {[info exists state($w,$timer)]} {after cancel $state($w,$timer)}}
    if {[info exists state($w,job)]&&$state($w,job) ne {}} {catch {curveSourceCancel $state($w,job)}}
    if {[info exists state($w,source)]&&$state($w,source) ne {}} {curveSourceClose $state($w,source)}
    if {[info exists state($w,plotWidget)]&&$state($w,plotWidget) ne {}} {catch {::GX::PlotDatasetAPIv4::widgetDestroy $state($w,plotWidget)}}
    if {[info exists state($w,preparePipe)]} {
        fileevent $state($w,preparePipe) readable {};foreach pid [pid $state($w,preparePipe)] {
            if {[info exists state($w,prepareGroup)]} {catch {exec kill -TERM -- -$pid}} else {catch {exec kill -TERM -- $pid}}
        };catch {close $state($w,preparePipe)}
    }
    if {[info exists state($w,xyzStream)]} {catch {tableStreamClose $state($w,xyzStream)}}
    if {[info exists state($w,compactCanvas)]} {native3DPreviewClosed $w}
    if {[info exists state($w,worker)]} {catch {puts $state($w,worker) close;flush $state($w,worker)};foreach pid [pid $state($w,worker)] {catch {exec kill -TERM -- $pid}};catch {close $state($w,worker)}}
    if {[info exists state($w,externalPipe)]} {fileevent $state($w,externalPipe) readable {};catch {close $state($w,externalPipe)}}
    if {[info exists state($w,externalPids)]} {foreach pid $state($w,externalPids) {catch {exec kill -TERM -- $pid}}}
    if {[info exists state($w,decoder)]} {foreach pid [pid $state($w,decoder)] {catch {exec kill -TERM -- $pid}};catch {close $state($w,decoder)}}
    if {[info exists state($w,image)]&&$state($w,image) ne {}} {catch {image delete $state($w,image)}}
    if {[info exists state($w,temp)]} {file delete -force -- $state($w,temp)}
    if {[info exists state($w,memberStream)]} {catch {tableStreamClose $state($w,memberStream)}}
    if {[info exists state($w,previewWidget)] && $::GX::DatasetViewer::previewJob eq $w} {
        set ::GX::DatasetViewer::previewJob {}
        if {[winfo exists .top.nb.preview.geometry]} {place forget .top.nb.preview.geometry}
    }
    # Tk listvariables reinstall their values during widget destruction.
    # Destroy widgets first, then remove every per-window value.
    catch {destroy $w}
    array unset state $w,*
}
proc ::GX::datasetViewerWindow {id title} {
    variable ::GX::DatasetViewer::state;variable ::GX::DatasetViewer::serial
    set w .datasetViewer[incr serial]
    set state($w,id) $id;set state($w,identity) [datasetViewerDescribe $id];set state($w,session) [interactiveDocumentSessionToken]
    set state($w,path) [dict get [sessionInspectionDatasetPayload $id] path]
    set state($w,stamp) [datasetViewerStamp $id $state($w,path)]
    toplevel $w;wm title $w "$title — $id (read-only)";wm geometry $w 1100x760
    wm protocol $w WM_DELETE_WINDOW [list ::GX::datasetViewerClose $w]
    set state($w,status) "$id — canonical values, no publication"
    ttk::label $w.status -textvariable ::GX::DatasetViewer::state($w,status) -wraplength 1000
    pack $w.status -side bottom -fill x -padx 8 -pady 5
    datasetViewerWatch $w
    return $w
}
# This is a read-only projection of the public authorities, not another schema
# or metadata store. Keep their return strings intact for the advanced Raw view.
# Structured projection only for the documented Object Origin v1 contract.
# Values still come from public metadata; unknown records stay opaque in Raw.
proc ::GX::scientificDatasetInspectionOriginProjection {origin} {
    set rows {};set messages {};set limited 0;set visited 0
    set queue [list [list [list {Dataset origin}] $origin 0]]
    while {[llength $queue] && [llength $rows]<768} {
        if {[incr visited]>2048} {set limited 1;break}
        lassign [lindex $queue 0] path value depth
        set queue [lrange $queue 1 end]
        set relationship [join $path { / }]
        if {[catch {dict get $value version} version] || $version ne {1} || $depth>64} {
            lappend rows [list $relationship {Opaque origin record} $value]
            lappend messages {Unrecognized or depth-limited origin records remain complete in Raw.}
            continue
        }
        dict for {field item} $value {
            if {$field in {parent events}} continue
            if {[llength $rows]>=768} {set limited 1;break}
            lappend rows [list $relationship $field $item]
        }
        if {[dict exists $value parent]} {
            set parent [dict get $value parent]
            if {[catch {dict size $parent}]} {
                if {[llength $rows]<768} {lappend rows [list $relationship {Opaque parent} $parent]} else {set limited 1}
                lappend messages {Malformed parent containers remain opaque; the complete value is available in Raw.}
            } else {
                dict for {key item} $parent {
                    if {[llength $rows]>=768 || [llength $queue]>=768} {set limited 1;break}
                    if {$key in {source_origin session_origin origin_snapshot}} {
                        lappend queue [list [concat $path [list parent $key]] $item [expr {$depth+1}]]
                    } elseif {$key eq {source_dataset_origins} && ![catch {dict size $item}]} {
                        dict for {dataset child} $item {
                            if {[llength $queue]>=768} {set limited 1;break}
                            lappend queue [list [concat $path [list parent $key "Dataset: $dataset"]] $child [expr {$depth+1}]]
                        }
                    } else {
                        lappend rows [list "$relationship / parent" $key $item]
                        if {$key eq {source_dataset_origins}} {lappend messages {Malformed source-origin collections remain opaque in Raw.}}
                    }
                }
            }
        }
        if {[dict exists $value events]} {
            set events [dict get $value events]
            if {[catch {llength $events}]} {
                if {[llength $rows]<768} {lappend rows [list $relationship {Opaque events} $events]} else {set limited 1}
                lappend messages {Malformed event containers remain opaque; the complete value is available in Raw.}
            } else {
                set index 0
                foreach event $events {
                    if {[incr visited]>2048} {set limited 1;break}
                    incr index
                    if {[llength $rows]>=768} {set limited 1;break}
                    if {[catch {dict size $event}]} {lappend rows [list "$relationship / event $index" {Opaque event} $event];continue}
                    dict for {key item} $event {
                        if {[llength $rows]>=768} {set limited 1;break}
                        lappend rows [list "$relationship / event $index" $key $item]
                    }
                }
            }
        }
    }
    if {[llength $queue] || $limited} {lappend messages {Structured inspection is limited to 768 rows and 2048 records; the complete published ancestry remains in Raw.}}
    return [dict create rows $rows messages [lsort -unique $messages]]
}
proc ::GX::scientificDatasetInspectionSnapshot {id} {
    set record [sessionInspectionDataset $id]
    set variables [datasetVariableSchemaV3 $id]
    set metadata [datasetMetadataRead $::GX::currentSession $id]
    set notes [datasetUserNotes $id]
    return [dict create record $record variables $variables metadata $metadata notes $notes]
}
proc ::GX::scientificDatasetInspectionSection {authority key} {
    # Group only fields declared by the public record / origin / digitizer
    # contracts. Arbitrary user keys are opaque, even if they sound scientific.
    if {$authority eq {record}} {
        if {$key in {source source_module producer_module producer_version source_dataset_ids source_variable_ids provenance source_raw source_header_rows source_delimiter}} {return {Sources and provenance}}
        if {$key in {canonical_sha256 sha256 integrity_algorithm integrity_seconds publication_api_version canonical_access_api_version variable_schema_api_version created_at immutable structured_metadata_file structured_metadata_api_version structured_metadata_updated_at structured_metadata_revision}} {return {Integrity and publication}}
        if {$key in {notes user_notes user_notes_file}} {return Notes}
        if {$key in {variables columns units semantic_roles var_count} || [regexp {^var[0-9]+_} $key]} {return {Variable schema}}
        if {$key in {id kind contract format storage_kind media_type path storage_provider storage_provider_version requested_storage_provider storage_selection_reason row_count sample_count display_name metadata_display_name}} {return {Identity and format}}
    } else {
        if {$key eq {origin.definition} || $key in {curve_digitizer.plugin_id curve_digitizer.plugin_version curve_digitizer.configuration_id curve_digitizer.configuration_document_id curve_digitizer.configuration_name curve_digitizer.source_dataset_id curve_digitizer.source_variable_id curve_digitizer.source_sha256}} {return {Sources and provenance}}
        if {$key in {curve_digitizer.publication_timestamp curve_digitizer.publication_contract}} {return {Integrity and publication}}
        if {$key in {curve_digitizer.manifest_version curve_digitizer.calibration_type curve_digitizer.calibration_id curve_digitizer.calibration_sha256 curve_digitizer.calibration_manifest curve_digitizer.calibration_measurements curve_digitizer.calibration_method curve_digitizer.measurement_count curve_digitizer.publication_measurement_id curve_digitizer.image_width curve_digitizer.image_height curve_digitizer.coordinate_origin curve_digitizer.y_direction curve_digitizer.physical_unit curve_digitizer.raster_geometry curve_digitizer.raster_geometry.source_to_calibration curve_digitizer.uncertainty curve_digitizer.uncertainty.pixel_sigma_px} || [regexp {^curve_digitizer\.(measurement\.[0-9]+\.(measurement_id|label|state|active|valid|calibration_id|calibration_sha256|calibration_type|corners_px|axes|scale_reference|transform\.(h[0-2][0-2]|[xy]_(minimum|maximum|scale|unit)))|transform\.(convention|raster_origin|pixel_reference|h[0-2][0-2]|scientific_h[0-2][0-2]|[xy]_(minimum|maximum|scale|unit))|calibration_method\.(type|point_selection|tick_reference|measurement_uncertainty)|scale_bar\.(pixel_length|physical_length|unit|display_unit|selection_method|start_[xy]|end_[xy]|edge_convention))$} $key]} {return Calibrations}
        if {$key in {curve_digitizer.curve_schema_version curve_digitizer.family_unit curve_digitizer.family_label} || [string match {curve_digitizer.curve_column.*} $key]} {return {Variable schema}}
    }
    return {Other published fields}
}
proc ::GX::scientificDatasetInspectionCalibrationRows {manifest measurements} {
    # Typed values from the existing public Calibration API only. Never parse
    # the producer's JSON or reconstruct a map from names or image geometry.
    set rows {};set authority {Calibration API v1}
    foreach {key label} {dataset_id {Dataset ID} source_dataset_id {Source Dataset ID} source_sha256 {Recorded source SHA-256} configuration_id {Configuration ID} calibration_type Type calibration_id {Calibration ID} calibration_sha256 {Calibration SHA-256} image_width {Image width (pixels)} image_height {Image height (pixels)} coordinate_origin {Coordinate origin} y_direction {Y direction} physical_unit {Declared common physical unit} raster_pixel_mapping {Source pixel mapping}} {
        if {[dict exists $manifest $key]} {lappend rows [list Calibrations $authority "Base calibration / $label" [dict get $manifest $key]]}
    }
    foreach axis {x y} {
        foreach {key label} {minimum Minimum maximum Maximum scale Scale unit Unit} {
            if {[dict exists $manifest transform ${axis}_axis $key]} {lappend rows [list Calibrations $authority "Scientific [string toupper $axis] / $label" [dict get $manifest transform ${axis}_axis $key]]}
        }
    }
    foreach {key label} {convention Convention raster_origin {Raster origin} pixel_reference {Pixel reference} normalized_coordinates {Normalized coordinate convention} normalized_homography {Normalized homography} scientific_homography {Scientific homography}} {
        if {[dict exists $manifest transform $key]} {lappend rows [list Calibrations $authority "Transform / $label" [dict get $manifest transform $key]]}
    }
    foreach {key label} {type Type point_selection {Point selection} tick_reference {Tick reference} measurement_uncertainty {Measurement uncertainty}} {
        if {[dict exists $manifest calibration_method $key]} {lappend rows [list Calibrations $authority "Calibration method / $label" [dict get $manifest calibration_method $key]]}
    }
    foreach {key label} {pixel_length {Pixel length} physical_length {Physical length} unit Unit display_unit {Display unit} selection_method {Selection method} start_px {Start (pixels)} end_px {End (pixels)} edge_convention {Tick edge convention}} {
        if {[dict exists $manifest scale_bar $key]} {lappend rows [list Calibrations $authority "Scale bar / $label" [dict get $manifest scale_bar $key]]}
    }
    set index 0
    foreach measurement $measurements {
        incr index
        foreach {key label} {measurement_id ID label Label state State active Active valid Valid calibration_id {Calibration ID} calibration_sha256 {Calibration SHA-256} calibration_type Type} {
            if {[dict exists $measurement $key]} {lappend rows [list Calibrations $authority "Measurement $index / $label" [dict get $measurement $key]]}
        }
    }
    return $rows
}
proc ::GX::scientificDatasetInspectionRows {snapshot {calibration {}} {measurements {}}} {
    set groups {}
    if {$calibration ne {}} {
        foreach row [scientificDatasetInspectionCalibrationRows $calibration $measurements] {dict lappend groups Calibrations $row}
    }
    foreach {source title} {record {Dataset record} metadata {Public metadata}} {
        dict for {key value} [dict get $snapshot $source] {
            set section [scientificDatasetInspectionSection $source $key]
            dict lappend groups $section [list $section $title $key $value]
        }
    }
    set rows {}
    foreach section {{Identity and format} {Sources and provenance} {Variable schema} Calibrations {Integrity and publication} Notes {Other published fields}} {
        if {[dict exists $groups $section]} {lappend rows {*}[dict get $groups $section]}
    }
    return $rows
}
proc ::GX::scientificDatasetInspectionText {widget text} {
    if {![winfo exists $widget]} return
    $widget configure -state normal
    $widget delete 1.0 end
    $widget insert 1.0 $text
    $widget configure -state disabled
}
proc ::GX::scientificDatasetInspectionLog {parent text} {
    uiFieldComponentCreate $parent.value log [dict create text $text height 7] {} {}
    ttk::scrollbar $parent.scroll -command [list $parent.value yview]
    $parent.value configure -yscrollcommand [list $parent.scroll set]
    pack $parent.scroll -side right -fill y
    pack $parent.value -fill both -expand 1
}
proc ::GX::scientificDatasetInspectionSelect {w kind tree} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,inspection)] || ![winfo exists $tree]} return
    if {[catch {datasetViewerCheck $w} message]} {set state($w,status) $message;return}
    set selected [$tree selection]
    if {![llength $selected]} return
    set values [$tree item [lindex $selected 0] -values]
    if {$kind eq {variables}} {
        set variable [lindex [dict get $state($w,inspection) variables] [$tree index [lindex $selected 0]]]
        set text {}
        dict for {key value} $variable {append text "$key: $value\n"}
    } elseif {$kind eq {ancestry}} {
        lassign $values relationship field value
        set text "$relationship\n$field\n\n$value"
    } else {
        lassign $values section authority field value
        set text "$section\n$authority / $field\n\n$value"
    }
    scientificDatasetInspectionText $w.views.infoPage.$kind.detail.value $text
}
proc ::GX::scientificDatasetInspectionRaw {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,inspection)] || ![winfo exists $w.views.infoPage.raw]} return
    if {[catch {datasetViewerCheck $w} message]} {set state($w,status) $message;return}
    set keys {record variables metadata notes}
    set index [$w.views.infoPage.raw.source current]
    if {$index<0} return
    scientificDatasetInspectionText $w.views.infoPage.raw.content.value [dict get $state($w,inspection) [lindex $keys $index]]
}
proc ::GX::scientificDatasetInspectionBuild {w} {
    variable ::GX::DatasetViewer::state
    set state($w,inspection) [scientificDatasetInspectionSnapshot $state($w,id)]
    set page $w.views.infoPage
    uiFieldComponentCreate $page tabs {} {} {}
    $w.views add $page -text {Schema and provenance}
    foreach {name title} {variables Variables properties {Dataset and metadata} ancestry {Source ancestry} notes Notes raw {Raw (advanced)}} {
        uiFieldComponentCreate $page.$name panel {} {} {}
        $page add $page.$name -text $title
    }
    set v $page.variables
    uiFieldComponentCreate $v.help label [dict create text {Canonical schema from the public API, including its defaults. Empty cells mean no value is supplied. Select a Variable for all fields; Ctrl+C copies selected rows.}] {} {}
    pack $v.help -fill x -pady 4
    uiFieldComponentCreate $v.table table [dict create columns {{Variable ID} Name dtype Unit {Semantic role} {Coordinate role} Rank Shape} scrollbars both] {} {}
    set tree [uiFieldComponentTableWidget $v.table]
    # Keep headings readable at narrow widths; the shared horizontal scrollbar
    # exposes the remaining columns instead of shrinking each heading to 40px.
    foreach column [$tree cget -columns] {
        set width [expr {max(90,[font measure TkHeadingFont $column]+24)}]
        $tree column $column -width $width -minwidth $width -stretch 0
    }
    $tree column Name -width 160 -minwidth 160 -stretch 1
    foreach variable [dict get $state($w,inspection) variables] {
        set values {}
        foreach key {variable_id canonical dtype unit semantic_role coordinate_role rank shape} {
            set value [datasetPublicationV2DictDefault $variable $key {}]
            if {$key eq {canonical} && [datasetPublicationV2DictDefault $variable display_label {}] ne {}} {set value [dict get $variable display_label]}
            lappend values $value
        }
        $tree insert {} end -values $values
    }
    pack $v.table -fill both -expand 1 -pady 4
    uiFieldComponentCreate $v.detail section [dict create title {Selected Variable — all canonical fields}] {} {}
    scientificDatasetInspectionLog $v.detail {Select a Variable above to inspect its complete canonical schema.}
    pack $v.detail -fill both -expand 1
    bind $tree <<TreeviewSelect>> [list ::GX::scientificDatasetInspectionSelect $w variables $tree]
    set p $page.properties
    set explanation {Published Dataset record and public metadata only. Field names are preserved; no provenance, calibration or integrity result is inferred. Select a row for its full wrapped value; Ctrl+C copies a single-line tabular row; copy complete multiline text from the detail below or Raw.}
    set metadata [dict get $state($w,inspection) metadata];set calibration {};set measurements {}
    if {[datasetPublicationV2DictDefault $metadata curve_digitizer.plugin_id {}] eq {viewer.curve_digitizer}} {
        if {[catch {
            modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_CALIBRATION_API_v1
            set calibration [::GX::CurveDigitizerCalibration::read $state($w,id)]
        } reason]} {
            append explanation "\nPublished calibration unavailable: $reason Exact metadata remains in Raw."
        } else {
            append explanation "\n" {Calibration rows use the validated public Calibration API v1 projection, including its documented defaults. Recorded identities and maps do not certify current source integrity, physical accuracy or quantified uncertainty. Original published JSON and all other fields remain complete in Raw.}
            if {[catch {set measurements [::GX::CurveDigitizerCalibration::replicates $state($w,id)]} reason]} {append explanation "\nPublished calibration measurements unavailable: $reason"}
        }
    }
    uiFieldComponentCreate $p.help label [dict create text $explanation] {} {}
    pack $p.help -fill x -pady 4
    uiFieldComponentCreate $p.table table [dict create columns {Section Authority Field Value} scrollbars both] {} {}
    set tree [uiFieldComponentTableWidget $p.table]
    $tree column Section -width 180 -stretch 0
    $tree column Authority -width 120 -stretch 0
    $tree column Field -width 230 -stretch 0
    $tree column Value -width 400
    foreach row [scientificDatasetInspectionRows $state($w,inspection) $calibration $measurements] {$tree insert {} end -values $row}
    pack $p.table -fill both -expand 1 -pady 4
    uiFieldComponentCreate $p.detail section [dict create title {Selected field — complete value}] {} {}
    scientificDatasetInspectionLog $p.detail {Select a field above. Long paths, hashes and multiline values remain complete here and in Raw.}
    pack $p.detail -fill both -expand 1
    bind $tree <<TreeviewSelect>> [list ::GX::scientificDatasetInspectionSelect $w properties $tree]
    set a $page.ancestry
    set metadata [dict get $state($w,inspection) metadata]
    set explanation {Recorded Object Origin v1 ancestry from the published snapshot. Creator, source and Session relationships describe declared lineage; they do not certify authorship or creation of physical measurements. Select a row for its complete value; exact original metadata remains in Raw.}
    set rows {}
    if {[dict exists $metadata origin.definition]} {
        set projection [scientificDatasetInspectionOriginProjection [dict get $metadata origin.definition]]
        set rows [dict get $projection rows]
        foreach message [dict get $projection messages] {append explanation "\n$message"}
    } else {append explanation {
No origin.definition is published for this Dataset. No ancestry is inferred.}}
    uiFieldComponentCreate $a.help label [dict create text $explanation] {} {}
    pack $a.help -fill x -pady 4
    uiFieldComponentCreate $a.table table [dict create columns {Relationship Field Value} scrollbars both] {} {}
    set tree [uiFieldComponentTableWidget $a.table]
    $tree column Relationship -width 300 -stretch 0
    $tree column Field -width 180 -stretch 0
    $tree column Value -width 350
    foreach row $rows {$tree insert {} end -values $row}
    pack $a.table -fill both -expand 1 -pady 4
    uiFieldComponentCreate $a.detail section [dict create title {Selected ancestry field — complete value}] {} {}
    scientificDatasetInspectionLog $a.detail {Select a recorded ancestry field above. Historical parent snapshots are displayed without reopening or replacing their sources.}
    pack $a.detail -fill both -expand 1
    bind $tree <<TreeviewSelect>> [list ::GX::scientificDatasetInspectionSelect $w ancestry $tree]
    uiFieldComponentCreate $page.notes.help label [dict create text {Read-only user notes from the public Dataset notes API. Their original markup is preserved.}] {} {}
    pack $page.notes.help -fill x -pady 4
    ttk::frame $page.notes.content
    scientificDatasetInspectionLog $page.notes.content [dict get $state($w,inspection) notes]
    pack $page.notes.content -fill both -expand 1
    set r $page.raw
    uiFieldComponentCreate $r.help label [dict create text {Advanced: exact public API return values, not physical source-file bytes. Select a source, then select text and Ctrl+C to copy. No fields are rewritten or interpreted.}] {} {}
    pack $r.help -fill x -pady 4
    uiFieldComponentCreate $r.source combobox [dict create choices {{Dataset record — sessionInspectionDataset} {Variable schema — datasetVariableSchemaV3} {Public metadata — datasetMetadataRead} {User notes — datasetUserNotes}} width 38] ::GX::DatasetViewer::state($w,inspectionRaw) [list ::GX::scientificDatasetInspectionRaw $w]
    pack $r.source -fill x -pady 4
    ttk::frame $r.content
    scientificDatasetInspectionLog $r.content {}
    pack $r.content -fill both -expand 1
    $r.source current 0
    scientificDatasetInspectionRaw $w
}
proc ::GX::scientificDatasetViewerControlsLayout {w width} {
    if {![winfo exists $w.views.plot.bar] || $width<2} return
    set p $w.views.plot
    set bar $p.bar
    set available [expr {max(1,$width-16)}]
    # Keep axis pairs and actions in separate semantic rows. Independent grid
    # containers avoid one wide combo forcing every action into its own row.
    set axesWidth 0
    foreach child {xLabel x yLabel y} {pack forget $bar.$child;incr axesWidth [expr {[winfo reqwidth $bar.$child]+6}]}
    set row 0;set column 0;set used 0
    foreach axis {x y} {
        set pair [expr {[winfo reqwidth $bar.${axis}Label]+[winfo reqwidth $bar.$axis]+12}]
        if {$used && $used+$pair>$available} {incr row;set column 0;set used 0}
        grid $bar.${axis}Label -in $bar.axes -row $row -column $column -sticky w -padx 3 -pady 2
        incr column
        grid $bar.$axis -in $bar.axes -row $row -column $column -sticky w -padx 3 -pady 2
        incr column;incr used $pair
    }
    foreach row {0 1 2 3 4} {grid forget $bar.actions.row$row}
    set actionsWidth 0;set row 0;set used 0
    foreach child {plot fit cancel aspect details} {
        pack forget $bar.$child
        grid forget $bar.$child
        set needed [expr {[winfo reqwidth $bar.$child]+6}]
        incr actionsWidth $needed
        if {$used && $used+$needed>$available} {incr row;set used 0}
        # A later wide action must not widen an earlier row's grid columns.
        # Each pre-created row owns only its actual requested button widths.
        set master $bar.actions.row$row
        grid $master -row $row -column 0 -sticky w
        pack $bar.$child -in $master -side left -padx 3 -pady 2
        incr used $needed
    }
    grid $bar.axes -row 0 -column 0 -sticky w
    if {$axesWidth+$actionsWidth+12<=$available} {
        grid $bar.actions -row 0 -column 1 -columnspan 1 -sticky w
    } else {grid $bar.actions -row 1 -column 0 -columnspan 2 -sticky w}
    $p.legend configure -wraplength [expr {max(120,$width-16)}]
    $w.status configure -wraplength [expr {max(120,$width-16)}]
    set series $p.series
    foreach child {label variables filters} {pack forget $series.$child}
    grid $series.label -row 0 -column 0 -sticky w -padx 4
    grid $series.variables -row 1 -column 0 -sticky w -padx 4 -pady 3
    if {$width>max([winfo reqwidth $series.variables],[winfo reqwidth $series.label])+max(420,[winfo reqwidth $series.filters])+32} {
        grid $series.filters -row 0 -column 1 -rowspan 2 -columnspan 1 -sticky new -padx 8 -pady 4
        grid columnconfigure $series 0 -weight 0
        grid columnconfigure $series 1 -weight 1
    } else {
        grid $series.filters -row 2 -column 0 -rowspan 1 -columnspan 2 -sticky ew -padx 4 -pady 3
        grid columnconfigure $series 0 -weight 1
        grid columnconfigure $series 1 -weight 0
    }
}
proc ::GX::scientificDatasetViewerAxisLabels {w {series @current} {context @current}} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,plottedRequest)]} {return {}}
    if {$series eq {@current}} {set series $state($w,series)}
    if {$context eq {@current}} {set context [expr {[info exists state($w,coordinateContext)] ? $state($w,coordinateContext) : {}}]}
    set ys [lindex $state($w,plottedRequest) 1]
    if {[llength $series]} {set ys {};foreach item $series {set vid [dict get $item y];if {$vid ni $ys} {lappend ys $vid}}}
    set ids [list [list [lindex $state($w,plottedRequest) 0]] $ys]
    set labels {}
    foreach axis {x y} variables $ids {
        set names {};set unit {}
        foreach vid $variables {
            set variable [datasetVariableV3ById $state($w,id) $vid]
            set name [datasetPublicationV2DictDefault $variable display_label {}]
            if {$name eq {}} {set name [dict get $variable canonical]}
            if {$name ni $names} {lappend names $name}
            set unit [dict get $variable unit]
            if {$context ne {}} {set unit [dict get [scientificDatasetCoordinateSettings $context $vid] display_unit]}
        }
        set label [join $names {, }]
        if {$unit ne {}} {append label " ($unit)"}
        dict set labels [format %s_label $axis] $label
    }
    return $labels
}

proc ::GX::scientificDatasetViewerSummary {w args} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)] || ![winfo exists $w.views.plot.legend]} return
    if {[catch {datasetViewerCheck $w} reason]} {
        set state($w,axisSummary) {Source changed; reopen this Dataset.}
        set state($w,compactStatus) $reason
        return
    }
    set parts {}
    foreach axis {x y} {
        if {$state($w,$axis) eq {}} {lappend parts "[string toupper $axis]: choose a Variable";continue}
        if {[catch {set v [datasetVariableV3ById $state($w,id) $state($w,$axis)]}]} continue
        set label [datasetPublicationV2DictDefault $v display_label {}]
        if {$label eq {}} {set label [dict get $v canonical]}
        if {[dict get $v unit] ne {}} {append label " ([dict get $v unit])"}
        lappend parts "[string toupper $axis]: $label"
    }
    set state($w,axisSummary) "Selected source variables — [join $parts {; }]"
    set message $state($w,status)
    if {[string first filter_variable_id $message]>=0} {
        set message {Scientific point/series readout updated; open Selection details for complete values and predicates.}
    } elseif {[string length $message]>180} {set message "[string range $message 0 176]…"}
    set state($w,compactStatus) $message
    if {[winfo exists $w.views.details] && [$w.views select] eq "$w.views.details"} {scientificDatasetViewerDetails $w 0}
}
proc ::GX::scientificDatasetViewerDetails {w {show 1}} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)] || ![winfo exists $w.views.details]} return
    if {[catch {datasetViewerCheck $w} message]} {set state($w,status) $message;return}
    set text "Dataset: $state($w,id)\n\nCURRENT CONTROLS (select Plot to apply)\n"
    foreach axis {x y} {append text "[string toupper $axis] Variable ID: $state($w,$axis)\n"}
    append text "Additional Y Variable IDs: "
    set overlays {};foreach index [$w.views.plot.series.variables curselection] {lappend overlays [lindex $state($w,numeric) $index]}
    append text "$overlays\nGrouping Variable IDs: [datasetPublicationV2DictDefault $state($w,filters) @grouping {}]\nOrdering Variable ID: $state($w,ordering)\n\nCurrent row predicates (public filter contract):\n"
    foreach predicate [scientificDatasetFilterSelectionPredicates $state($w,dimensions) $state($w,filters)] {
        dict for {key value} $predicate {append text "  $key: $value\n"}
        append text "\n"
    }
    if {[info exists state($w,plottedRequest)]} {
        lassign $state($w,plottedRequest) x ys requests
        append text "\nLAST PLOT REQUEST\nX Variable ID: $x\nY Variable IDs: $ys\n"
        set index 0
        foreach request $requests {
            append text "\nSeries selection [incr index]:\n"
            foreach predicate $request {dict for {key value} $predicate {append text "  $key: $value\n"};append text "\n"}
        }
    }
    append text "\nCOMPLETE PLOT LEGEND\n$state($w,legend)\n\nCOMPLETE STATUS / POINT READOUT\n$state($w,status)"
    scientificDatasetInspectionText $w.views.details.content.value $text
    if {$show} {$w.views select $w.views.details}
}

# GUI adoption only. Interpretation and scientific controller ownership stay
# with public Plot v4, never a parallel display-only Native2D scene.
proc ::GX::scientificDatasetPlotRequire {} {
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    foreach operation {scientificModel widgetPointer widgetRetain} {
        if {![llength [info commands ::GX::PlotDatasetAPIv4::$operation]]} {error "Installed Plot v4 lacks required scientific consultation operation $operation"}
    }
}
proc ::GX::scientificDatasetViewerModel {w series context} {
    variable ::GX::DatasetViewer::state
    scientificDatasetPlotRequire
    datasetViewerCheck $w
    set records {};set index 0
    foreach item $series {
        set y [dict get $item y]
        set variable [datasetVariableV3ById $state($w,id) $y]
        set label [datasetPublicationV2DictDefault $variable display_label [dict get $variable canonical]]
        if {$label eq {}} {set label [dict get $variable canonical]}
        if {[dict get $item member] ne {}} {append label " · [dict get $item member]"}
        lappend records [dict create id trace_$index y_variable_id $y label $label filters [dict get $item filters] source_descriptor [dict get $item source_descriptor] display [dict get $item display]]
        incr index
    }
    set labels [scientificDatasetViewerAxisLabels $w $series $context]
    set options [dict create title {} axis_labels [dict create x [dict get $labels x_label] y [dict get $labels y_label]] aspect $state($w,aspect) progress [list ::GX::scientificDatasetOpeningProgress $w $state($w,epoch)]]
    return [::GX::PlotDatasetAPIv4::scientificModel $state($w,id) [lindex $state($w,plottedRequest) 0] $records $context $options]
}
proc ::GX::scientificDatasetViewerAdopt {w series context} {
    variable ::GX::DatasetViewer::state
    set epoch $state($w,epoch)
    scientificDatasetViewerRetain $w {Previous render — preparing scientific model}
    set state($w,opening) 1
    try {
        set model [scientificDatasetViewerModel $w $series $context]
    } on error {message options} {
        if {![info exists state($w,id)] || $state($w,epoch)!=$epoch} {return 0}
        return -options $options $message
    } finally {
        if {[info exists state($w,id)] && $state($w,epoch)==$epoch} {set state($w,opening) 0}
    }
    if {![info exists state($w,id)] || $state($w,epoch)!=$epoch} {return 0}
    datasetViewerCheck $w
    set policy {prepared_model 1 retain_presentation 1}
    ::GX::PlotDatasetAPIv4::widgetValidateSources $model $policy
    set path $w.views.plot.canvas
    if {$state($w,plotWidget) ne {}} {
        ::GX::PlotDatasetAPIv4::widgetConfigure $path $model $policy
    } else {
        if {[winfo exists $path]} {destroy $path}
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model $policy
        pack $path -fill both -expand 1
        bind $path <ButtonPress-1> [list ::GX::scientificDatasetViewerPan $w start %x %y]
        bind $path <B1-Motion> [list ::GX::scientificDatasetViewerPan $w move %x %y]
        bind $path <Button-4> [list ::GX::scientificDatasetViewerZoom $w 1.25 %x %y]
        bind $path <Button-5> [list ::GX::scientificDatasetViewerZoom $w 0.8 %x %y]
        bind $path <Motion> [list ::GX::scientificDatasetViewerPoint $w %x %y]
        set state($w,plotWidget) $path
    }
    set state($w,plotModel) $model
    set state($w,plotCurrent) 1
    return 1
}
proc ::GX::scientificDatasetViewerRetain {w reason} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set state($w,plotCurrent) 0
    if {$state($w,plotWidget) eq {}} return
    ::GX::PlotDatasetAPIv4::widgetRetain $state($w,plotWidget) $reason
}
proc ::GX::scientificDatasetViewerOpen {id} {
    variable ::GX::DatasetViewer::state
    set w [datasetViewerWindow $id {CORE Scientific Dataset Viewer}]
    set state($w,plotWidget) {};set state($w,plotCurrent) 0;set state($w,source) {};set state($w,job) {};set state($w,opening) 0;set state($w,start) 0;set state($w,epoch) 0
    ttk::notebook $w.views;pack $w.views -fill both -expand 1
    ttk::frame $w.views.plot;$w.views add $w.views.plot -text Plot
    set p $w.views.plot
    uiFieldComponentCreate $p.bar section [dict create title {Axes and rendering}] {} {}
    # Layout masters precede their sibling controls in Tk's stacking order.
    foreach group {axes actions} {
        uiFieldComponentCreate $p.bar.$group panel {} {} {}
        $p.bar.$group configure -padding 0
    }
    # Row masters precede the sibling controls in Tk's stacking order.
    foreach row {0 1 2 3 4} {ttk::frame $p.bar.actions.row$row}
    pack $p.bar -fill x -padx 5 -pady 3
    set axes [scientificDatasetAxes $id]
    foreach key {x y} {
        set state($w,$key) [dict get $axes $key]
        ttk::label $p.bar.${key}Label -text "[string toupper $key] Variable"
        ttk::combobox $p.bar.$key -values [dict get $axes numeric] -textvariable ::GX::DatasetViewer::state($w,$key) -state readonly -width 22
        pack $p.bar.${key}Label $p.bar.$key -side left -padx 5 -pady 6
        uiFieldSelectorWithinViewer $p.bar.$key $w
        bind $p.bar.$key <<ComboboxSelected>> [list ::GX::scientificDatasetViewerSummary $w]
    }
    foreach {name title action} {plot Plot scientificDatasetViewerPlot fit Fit scientificDatasetViewerFit cancel Cancel scientificDatasetViewerCancel} {
        ttk::button $p.bar.$name -text $title -command [list ::GX::$action $w];pack $p.bar.$name -side left -padx 5
    }
    scientificDatasetSeriesBuild $w [dict get $axes numeric]
    $p.series.label configure -text {Additional Y variables (Ctrl selects):}
    $p.series.filters.configure configure -text {Filters and grouping…}
    grid columnconfigure $p.series.filters 0 -weight 1
    foreach row [winfo children $p.series.filters] {
        if {[regexp {^f[0-9]+$} [winfo name $row]]} {
            grid configure $row -sticky ew
            bind $row <Configure> [list ::GX::uiFieldControlsLayout $row %w]
        }
    }
    set state($w,aspect) auto
    ttk::checkbutton $p.bar.aspect -text {Equal numeric aspect} -variable ::GX::DatasetViewer::state($w,aspect) -onvalue xy_equal -offvalue auto -command [list ::GX::scientificDatasetViewerAspect $w]
    pack $p.bar.aspect -side left -padx 5
    set state($w,legend) {Select explicit X and Y variables, then Plot.}
    ttk::label $p.legend -textvariable ::GX::DatasetViewer::state($w,axisSummary) -justify left
    pack $p.legend -fill x -padx 8 -pady 3
    $w.status configure -textvariable ::GX::DatasetViewer::state($w,compactStatus) -justify left
    ttk::button $p.bar.details -text {Selection details…} -command [list ::GX::scientificDatasetViewerDetails $w]
    pack $p.bar.details -side left
    bind $p.bar <Configure> [list ::GX::scientificDatasetViewerControlsLayout $w %w]
    # The public Plot owner creates its surface after canonical source/model
    # admission. This empty frame is only the initial layout slot.
    ttk::frame $p.canvas;pack $p.canvas -fill both -expand 1
    set tableVariables {};foreach v [datasetVariableSchemaV3 $id] {if {[dict get $v rank]==1} {lappend tableVariables [dict get $v variable_id]}}
    if {[llength $tableVariables]} {
        datasetPreviewCreateTable $w.views.table $::GX::currentSession $id
        $w.views add $w.views.table -text {Canonical table}
    }
    set arrays {}
    foreach v [datasetVariableSchemaV3 $id] {if {[dict get $v enabled]&&[dict get $v rank]>=2} {lappend arrays [dict get $v variable_id]}}
    if {[llength $arrays]} {scientificDatasetMatrixBuild $w $arrays}
    scientificDatasetInspectionBuild $w
    uiFieldComponentCreate $w.views.details panel {} {} {}
    $w.views add $w.views.details -text {Selection details}
    ttk::button $w.views.details.refresh -text {Refresh current selection and status} -command [list ::GX::scientificDatasetViewerDetails $w 0]
    pack $w.views.details.refresh -anchor w -pady 4
    ttk::frame $w.views.details.content
    scientificDatasetInspectionLog $w.views.details.content {}
    pack $w.views.details.content -fill both -expand 1
    set state($w,summaryTrace) [list ::GX::scientificDatasetViewerSummary $w]
    foreach element {legend status} {trace add variable state($w,$element) write $state($w,summaryTrace)}
    scientificDatasetViewerSummary $w
    if {$state($w,x) ne {}&&$state($w,y) ne {}&&$state($w,memberVariable) eq {}} {after idle [list ::GX::scientificDatasetViewerPlot $w]}
    return $w
}
proc ::GX::scientificDatasetViewerCancel {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    set pending [expr {$state($w,job) ne {} || $state($w,opening) || [info exists state($w,queue)] && $state($w,queue) ne {}}]
    incr state($w,epoch)
    set state($w,opening) 0
    set state($w,queue) {}
    if {$state($w,job) ne {}} {curveSourceCancel $state($w,job);set state($w,job) {}}
    if {$state($w,source) ne {}} {curveSourceClose $state($w,source);set state($w,source) {}}
    if {$pending} {
        set state($w,status) {Loading cancelled; select Plot to refresh.}
        scientificDatasetViewerRetain $w {Previous render — loading cancelled; select Plot to refresh}
    }
}

proc ::GX::scientificDatasetViewerProgress {w receipt} {
    variable ::GX::DatasetViewer::state
    if {[info exists state($w,id)]} {set state($w,status) "Loading canonical rows: [dict get $receipt completed_rows] / [dict get $receipt total_rows]"}
}

proc ::GX::scientificDatasetViewerDrawLater {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[info exists state($w,drawJob)]} {after cancel $state($w,drawJob)}
    set state($w,drawJob) [after idle [list ::GX::scientificDatasetViewerDraw $w]]
}
proc ::GX::scientificDatasetViewerDraw {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,plotWidget)] || $state($w,plotWidget) eq {} || !$state($w,plotCurrent)} return
    if {[catch {datasetViewerCheck $w;::GX::PlotDatasetAPIv4::widgetDraw $state($w,plotWidget)} reason]} {set state($w,status) $reason}
}

proc ::GX::scientificDatasetViewerFit {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)]} return
    if {[catch {set selection [scientificDatasetViewerSelection $w]} reason]} {set state($w,status) $reason;return}
    if {![info exists state($w,plottedRequest)] || $state($w,plottedRequest) ne $selection} {scientificDatasetViewerPlot $w;return}
    if {$state($w,opening) || $state($w,job) ne {} || $state($w,queue) ne {} || ![llength $state($w,series)] || !$state($w,plotCurrent)} return
    if {[catch {
        datasetViewerCheck $w
        ::GX::PlotDatasetAPIv4::widgetPointer $state($w,plotWidget) fit 0 0
        # A newly configured plot may not have a painted receipt yet. Read
        # coordinate status from the same public painter's completed draw.
        set receipt [::GX::PlotDatasetAPIv4::widgetDraw $state($w,plotWidget)]
        set state($w,status) [scientificDatasetCoordinateNotice [dict get $receipt coordinate_presentation]]
    } reason]} {set state($w,status) $reason}
}

proc ::GX::scientificDatasetViewerAspect {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,id)] || $state($w,opening) || $state($w,job) ne {} || $state($w,queue) ne {} || ![llength $state($w,series)] || !$state($w,plotCurrent)} return
    set epoch $state($w,epoch)
    try {
        datasetViewerCheck $w
        set axes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $state($w,plotWidget)] axes]
        if {![scientificDatasetViewerAdopt $w $state($w,series) $state($w,coordinateContext)]} return
        ::GX::PlotDatasetAPIv4::widgetView $state($w,plotWidget) restore $axes
    } on error {reason options} {
        if {[info exists state($w,id)] && $state($w,epoch)==$epoch} {set state($w,status) $reason}
    }
}

proc ::GX::scientificDatasetViewerPan {w phase x y} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,plotCurrent)] || !$state($w,plotCurrent)} return
    set operation [expr {$phase eq {start} ? {pan_start} : {pan}}]
    if {[catch {datasetViewerCheck $w;::GX::PlotDatasetAPIv4::widgetPointer $state($w,plotWidget) $operation $x $y} reason]} {set state($w,status) $reason}
}

proc ::GX::scientificDatasetViewerZoom {w factor x y} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,plotCurrent)] || !$state($w,plotCurrent)} return
    if {[catch {datasetViewerCheck $w;::GX::PlotDatasetAPIv4::widgetPointer $state($w,plotWidget) zoom $x $y $factor} reason]} {set state($w,status) $reason}
}

proc ::GX::scientificDatasetMatrixBuild {w arrays} {
    variable ::GX::DatasetViewer::state
    set p $w.views.matrix;ttk::frame $p;$w.views add $p -text {Array plane}
    ttk::frame $p.bar;pack $p.bar -fill x
    set state($w,array) [lindex $arrays 0];set state($w,starts) {};set state($w,counts) {}
    ttk::combobox $p.bar.variable -values $arrays -state readonly -textvariable ::GX::DatasetViewer::state($w,array)
    ttk::label $p.bar.label -text {Starts / counts (storage order):}
    ttk::entry $p.bar.starts -textvariable ::GX::DatasetViewer::state($w,starts) -width 20
    ttk::entry $p.bar.counts -textvariable ::GX::DatasetViewer::state($w,counts) -width 20
    ttk::button $p.bar.show -text {Read plane} -command [list ::GX::scientificDatasetMatrixRead $w]
    pack $p.bar.variable $p.bar.label $p.bar.starts $p.bar.counts $p.bar.show -side left -padx 4 -pady 6
    canvas $p.canvas -background white;pack $p.canvas -fill both -expand 1
    bind $p.bar.variable <<ComboboxSelected>> [list ::GX::scientificDatasetMatrixDefaults $w]
    scientificDatasetMatrixDefaults $w
}
proc ::GX::scientificDatasetMatrixDefaults {w} {
    variable ::GX::DatasetViewer::state
    set v [datasetVariableV3ById $state($w,id) $state($w,array)]
    set shape [split [dict get $v shape] {;}];set starts {};set counts {}
    for {set i 0} {$i<[llength $shape]} {incr i} {lappend starts 0;lappend counts [expr {$i<[llength $shape]-2?1:min(128,[lindex $shape $i])}]}
    set state($w,starts) $starts;set state($w,counts) $counts
    set state($w,status) "Shape: $shape; dimensions: [dict get $v dimension_ids]; coordinates: [dict get $v coordinate_variable_ids]. Select at most two non-singleton dimensions; up to 16384 original cells, no aggregation."
}
proc ::GX::scientificDatasetMatrixRead {w} {
    variable ::GX::DatasetViewer::state
    if {[catch {
        datasetViewerCheck $w
        set starts $state($w,starts);set counts $state($w,counts)
        set v [datasetVariableV3ById $state($w,id) $state($w,array)]
        set shape [split [dict get $v shape] {;}]
        if {[llength $starts]!=[llength $shape]||[llength $counts]!=[llength $shape]} {error {Starts and counts must match rank.}}
        set elements 1;set axes {};set i 0
        foreach start $starts count $counts limit $shape {
            if {![string is integer -strict $start]||![string is integer -strict $count]||$start<0||$count<1||$start+$count>$limit} {error {Plane range is outside its dimension.}}
            set elements [expr {$elements*$count}];if {$count>1} {lappend axes $i};incr i
        }
        if {$elements>16384||[llength $axes]!=2} {error {Choose a plane with two non-singleton dimensions and at most 16384 cells.}}
        set handle [datasetAccessOpen $::GX::currentSession $state($w,id)]
        try {set slab [datasetAccessReadHyperslab $handle $state($w,array) $starts $counts]} finally {datasetAccessClose $handle}
        set values [dict get $slab values];set lo Inf;set hi -Inf
        foreach value $values {if {[string is double -strict $value]&&![catch {expr {abs($value)<Inf}} finite]&&$finite} {set lo [expr {min($lo,$value)}];set hi [expr {max($hi,$value)}]}}
        if {$lo eq "Inf"} {error {Plane has no finite values.}}
        lassign $axes ay ax;set ny [lindex $counts $ay];set nx [lindex $counts $ax]
        set c $w.views.matrix.canvas;$c delete all
        set dx [expr {max(1.0,([winfo width $c]-110.0)/$nx)}];set dy [expr {max(1.0,([winfo height $c]-70.0)/$ny)}]
        set n 0
        foreach value $values {
            set color #b8b8b8
            if {[string is double -strict $value]&&![catch {expr {abs($value)<Inf}} finite]&&$finite} {
                set t [expr {$hi==$lo?.5:($value-$lo)/($hi-$lo)}]
                set color [format #%02x%02x%02x [expr {int(255*$t)}] [expr {int(180*(1-abs(2*$t-1)))}] [expr {int(255*(1-$t))}]]
            }
            set x [expr {70+($n%$nx)*$dx}];set y [expr {20+($n/$nx)*$dy}]
            set item [$c create rectangle $x $y [expr {$x+$dx}] [expr {$y+$dy}] -fill $color -outline {}]
            set row [expr {[lindex $starts $ay]+$n/$nx}];set col [expr {[lindex $starts $ax]+$n%$nx}]
            $c bind $item <Enter> [list set ::GX::DatasetViewer::state($w,status) "Storage indices: $row, $col; canonical value: $value [dict get $v unit]"]
            incr n
        }
        set dimensions [datasetSchemaV3SplitIds [dict get $v dimension_ids]]
        set coordinateIds [datasetSchemaV3SplitIds [dict get $v coordinate_variable_ids]]
        foreach axis [list $ax $ay] orientation {x y} {
            set dimension [lindex $dimensions $axis];set label "$dimension (storage index)";set ticks {}
            foreach coordinate $coordinateIds {
                set cv [datasetVariableV3ById $state($w,id) $coordinate]
                if {[dict get $cv rank]==1&&[datasetSchemaV3SplitIds [dict get $cv dimension_ids]] eq [list $dimension]} {
                    set handle [datasetAccessOpen $::GX::currentSession $state($w,id)]
                    try {set ticks [dict get [datasetAccessReadHyperslab $handle $coordinate [list [lindex $starts $axis]] [list [lindex $counts $axis]]] values]} finally {datasetAccessClose $handle}
                    set label "[dict get $cv canonical] ([dict get $cv unit])";break
                }
            }
            for {set i 0} {$i<=4} {incr i} {
                set n [expr {int(([lindex $counts $axis]-1)*$i/4.0)}]
                set value [expr {$ticks eq {}?[lindex $starts $axis]+$n:[lindex $ticks $n]}]
                if {[string is double -strict $value]} {set value [format %.6g $value]}
                if {$orientation eq "x"} {$c create text [expr {70+($n+.5)*$dx}] [expr {[winfo height $c]-40}] -text $value} else {$c create text 65 [expr {20+($n+.5)*$dy}] -text $value -anchor e}
            }
            if {$orientation eq "x"} {$c create text 70 [expr {[winfo height $c]-15}] -anchor w -text $label} else {$c create text 8 8 -anchor nw -text $label}
        }
        set state($w,status) "Exact plane: $starts / $counts. Range $lo to $hi [dict get $v unit]; gray = nonfinite. No interpolation or publication."
    } message]} {set state($w,status) $message}
}
proc ::GX::datasetConsultationOpen {id info} {
    variable ::GX::DatasetViewer::state
    set w [datasetViewerWindow $id {CORE Dataset consultation}]
    set path [dict get [sessionInspectionDatasetPayload $id] path]
    text $w.content -wrap word -font TkFixedFont -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -command [list $w.content yview];pack $w.scroll -side right -fill y
    pack $w.content -fill both -expand 1
    set type [dict get $info target]
    if {$type in {image audio}} {
        set f [file tempfile temp];close $f;file delete $temp;file mkdir $temp;set state($w,temp) $temp
        if {[catch {set artifact [datasetPreviewMediaArtifact $path [dict get $info media_type] [dict get $info format] [dict get $info contract] $temp]} reason]} {$w.content insert end $reason
        } elseif {$artifact ne {}&&[dict exists $artifact path]&&[file isfile [dict get $artifact path]]} {
            set state($w,image) [image create photo -file [dict get $artifact path]]
            $w.content image create end -image $state($w,image)
        }
    } elseif {$type in {text structure}} {
        set f [open $path r];fconfigure $f -encoding utf-8
        try {set content [read $f 262144];set complete [eof $f]} finally {close $f}
        $w.content insert end $content
        if {!$complete} {$w.content insert end "\n\nBounded content inspection: first 256 KiB shown."}
    } else {$w.content insert end "No CORE semantic decoder is registered for this contract/format. The original Dataset is preserved.\n"}
    $w.content insert end "\n\n$info\n\n[datasetMetadataRead $::GX::currentSession $id]"
    $w.content configure -state disabled
    return $w
}
# Integrated Preview continues to use the existing media renderers and table
# descriptors; scientific PNGs use the same Curve Source + Native authority.
rename ::GX::datasetInspectionRenderPreview ::GX::datasetInspectionRenderPreview_before_core_viewers
proc ::GX::datasetInspectionRenderPreview {w choice} {
    previewDescriptorClearWidgetArtifact $w
    datasetDigitizerPreviewClear
    datasetPreviewUpdateOpenButton
    set expected [datasetPreviewStamp]
    set epoch $::GX::ui(previewEpoch)
    variable ::GX::DatasetViewer::previewImage
    variable ::GX::DatasetViewer::previewJob
    if {$previewJob ne {}} {catch {datasetViewerClose $previewJob};set previewJob {}}
    if {[winfo exists .top.nb.preview.mapping]} {grid remove .top.nb.preview.mapping}
    if {$previewImage ne {}} {catch {image delete $previewImage};set previewImage {}}
    lassign [datasetInspectionParseChoice $choice] mode id
    if {$mode ne "imported"} {return [datasetInspectionRenderPreview_before_core_viewers $w $choice]}
    if {[catch {set info [datasetViewerDescribe $id]} reason]} {
        $w configure -state normal;$w delete 1.0 end;$w insert end "Canonical Dataset unavailable: $reason";$w configure -state disabled;return 0
    }
    if {[datasetDocumentKind $id] in {markdown html xml code}} {
        if {[catch {datasetDocumentRender $w $id} reason]} {$w configure -state normal;$w delete 1.0 end;$w insert end "Document preview failed: $reason";$w configure -state disabled;return 0}
        return 1
    }
    if {[dict get $info target] in {mesh structure}} {
        $w configure -state normal;$w delete 1.0 end;$w insert end "Rendering canonical geometry through CORE Native3D…";$w configure -state disabled
        set previewJob [meshDatasetViewerOpen $id $w]
        return 1
    }
    if {[dict get $info target] ne "scientific"} {return [datasetInspectionRenderPreview_before_core_viewers $w $choice]}
    $w configure -state normal;$w delete 1.0 end
    $w insert end "Dataset: $id — [dict get $info contract]\nCanonical scientific data; display-only preview.\n\n"
    set axes [scientificDatasetPreviewControls $id [scientificDatasetAxes $id]]
    if {[catch {datasetDigitizerPreviewRender $w $id} reason]} {$w insert end "Source raster preview unavailable: $reason\n"}
    set f [file tempfile planePath];close $f
    try {set plane [scientificDatasetArrayPreview $id $planePath]
        if {$plane ne {}} {
            grid remove .top.nb.preview.mapping
            set previewImage [image create photo -file $planePath];$w image create end -image $previewImage;$w insert end "\n$plane\n";$w configure -state disabled;return 1
        }
    } on error {message options} {$w insert end "Array preview: $message\n"} finally {file delete -force $planePath}
    if {[dict get $axes x] eq {}||[dict get $axes y] eq {}} {
        $w insert end "X/Y mapping is ambiguous or multidimensional. Open Dataset to select explicit variables or a plane.\n"
        datasetPreviewRenderSchema $w $id
    } else {
        set f [file tempfile path];close $f
        try {
            set displayFilters $::GX::ui(previewMap,filters)
            if {[datasetDigitizerPreviewHasRecord $id]} {set displayFilters [dict remove $displayFilters @hidden_filters]}
            set requests [scientificDatasetFilterRequests $::GX::ui(previewMap,dimensions) $displayFilters $::GX::ui(previewMap,separate)]
            set receipt [scientificDatasetPreviewFiltered $id [dict get $axes x] [dict get $axes y] $path $requests]
            if {$choice ne $::GX::variableDatasetChoice || $epoch!=$::GX::ui(previewEpoch) || $expected ne [datasetPreviewStamp]} return
            set ::GX::ui(previewMap,status) "[scientificDatasetFilterMode $::GX::ui(previewMap,dimensions) $::GX::ui(previewMap,filters) $::GX::ui(previewMap,separate)] — [dict get $receipt trace_count] trace(s), [dict get $receipt row_count] source rows"
            foreach key {x y} {set vid [dict get $axes $key];set v [datasetVariableV3ById $id $vid];$w insert end "[string toupper $key]: [dict get $v canonical] ([scientificDatasetCoordinateLabel [dict get $receipt coordinate_presentation context] $vid])   "}
            $w insert end "\n"
            if {![datasetDigitizerPreviewAttachNative $id $w [dict get $receipt native_model]]} {
                set previewImage [image create photo -file $path]
                $w image create end -image $previewImage
            }
            $w insert end "\n[scientificDatasetFilterMode $::GX::ui(previewMap,dimensions) $::GX::ui(previewMap,filters) $::GX::ui(previewMap,separate)] — [dict get $receipt trace_count] trace(s)\nX: [dict get $axes x]   Y: [dict get $axes y]\nRows: [dict get $receipt row_count]; reduced display: [dict get $receipt reduced]. Original source ordering and gaps retained.\n"
            $w insert end "[scientificDatasetCoordinateNotice [dict get $receipt coordinate_presentation]]\n"
            lassign [dict get $receipt view_bounds] x0 y0 x1 y1
            $w insert end "Independent axes — X view: [format %.8g $x0] .. [format %.8g $x1]; Y view: [format %.8g $y0] .. [format %.8g $y1]. [dict get $receipt displayed_points] drawn points.\n"
        } on error {message options} {if {$epoch==$::GX::ui(previewEpoch) && $expected eq [datasetPreviewStamp]} {$w insert end "Scientific preview unavailable: $message\n"}} finally {file delete -force $path}
    }
    if {[catch {datasetDigitizerPreviewFinish $w $id} reason]} {$w insert end "Original image unavailable: $reason\n"}
    $w configure -state disabled
    return 1
}

proc ::GX::datasetMediaViewerOpen {id kind} {
    variable ::GX::DatasetViewer::state
    set w [datasetViewerWindow $id {CORE media lifecycle}];wm withdraw $w
    set path $state($w,path)
    if {$kind eq "pdf"} {set script pdf_dataset_viewer.py;set args [list $path $id]} else {set script media_dataset_viewer.py;set args [list $path $id $kind]}
    if {$kind eq {pdf}} {
        lappend args --owner-receipts
        set state($w,mediaKind) pdf
        set state($w,mediaSourceSha) [dict get [sessionInspectionDatasetPayload $id] sha256]
        set state($w,externalBuffer) {}
        set state($w,mediaReceipt) [dict create state starting dataset_id $id source_sha256 $state($w,mediaSourceSha)]
    }
    if {$kind eq "audio"} {
        set metadata [datasetMetadataRead $::GX::currentSession $id]
        foreach key {audio.raw_input_format audio.raw_sample_rate_hz audio.raw_channels audio.selected_stream_index} {lappend args [datasetPublicationV2DictDefault $metadata $key {}]}
    }
    _datasetMediaViewerLaunch $w $script $args
    return $w
}
proc ::GX::_datasetMediaViewerLaunch {w script arguments} {
    variable ::GX::DatasetViewer::state
    # Both Dataset and managed Document PDF sources use this identical reader,
    # pipe observation and lifecycle owner, never a second PDF implementation.
    try {
        set state($w,externalPipe) [open [concat [list | [runtimeToolRequired python] -B [file join $::GX::scriptDir core python $script]] $arguments [list 2>@stderr]] r]
        fconfigure $state($w,externalPipe) -blocking 0 -buffering none
        set state($w,externalPids) [pid $state($w,externalPipe)]
        fileevent $state($w,externalPipe) readable [list ::GX::datasetMediaViewerWatch $w]
    } on error {message options} {datasetViewerClose $w;return -options $options $message}
}
proc ::GX::datasetMediaViewerOpenResource {reference {title {Managed Document PDF}}} {
    variable ::GX::DatasetViewer::state;variable ::GX::DatasetViewer::serial
    interactiveDocumentResourceInfo $reference
    if {[datasetPublicationV2DictDefault [dict get $reference metadata] format {}] ne {pdf}} {error {Managed PDF preview requires a PDF Document resource}}
    set document [dict get $reference document_id]
    set owner [interactiveDocumentRead $document]
    set w .datasetViewer[incr serial]
    set state($w,id) $document
    set state($w,identity) [dict create source_kind managed_resource document_id $document source_sha256 [dict get $reference sha256]]
    set state($w,managedResource) $reference
    set state($w,managedOwnerGeneration) [dict get $owner generation]
    set state($w,session) [interactiveDocumentSessionToken]
    set state($w,path) [_documentResourceIdentity $reference]
    set state($w,mediaKind) pdf
    set state($w,mediaSourceSha) [dict get $reference sha256]
    set state($w,externalBuffer) {}
    set state($w,mediaReceipt) [dict create state starting source_kind managed_resource document_id $document source_sha256 [dict get $reference sha256]]
    toplevel $w;wm withdraw $w
    wm protocol $w WM_DELETE_WINDOW [list ::GX::datasetViewerClose $w]
    datasetViewerWatch $w
    _datasetMediaViewerLaunch $w pdf_dataset_viewer.py [list $state($w,path) $document --owner-receipts --managed-resource --title $title]
    return $w
}
proc ::GX::datasetMediaViewerWatch {w} {
    variable ::GX::DatasetViewer::state
    if {![info exists state($w,externalPipe)]} return
    set channel $state($w,externalPipe)
    if {[catch {set bytes [read $channel 65536]} reason]} {datasetViewerClose $w;return}
    if {[info exists state($w,mediaKind)] && $state($w,mediaKind) eq {pdf}} {
        append state($w,externalBuffer) $bytes
        if {[string length $state($w,externalBuffer)]>131072} {datasetViewerClose $w;return}
        while {[set newline [string first \n $state($w,externalBuffer)]]>=0} {
            set line [string range $state($w,externalBuffer) 0 [expr {$newline-1}]]
            set state($w,externalBuffer) [string range $state($w,externalBuffer) [expr {$newline+1}] end]
            if {[catch {_datasetMediaViewerAcceptReceipt $w $line} reason]} {
                set state($w,mediaReceipt) [dict create state unavailable dataset_id $state($w,id) source_sha256 $state($w,mediaSourceSha) status "PDF reader inspection unavailable: $reason"]
            }
        }
    }
    if {[eof $channel]} {fileevent $channel readable {};catch {close $channel};unset state($w,externalPipe) state($w,externalPids);datasetViewerClose $w}
}
proc ::GX::_datasetMediaViewerAcceptReceipt {w line} {
    variable ::GX::DatasetViewer::state
    if {[string length $line]>32768 || ![string match {GXPDF1 *} $line]} {error {Unexpected bounded PDF reader frame}}
    set receipt [encoding convertfrom utf-8 [binary decode base64 -strict [string range $line 7 end]]]
    foreach field {schema pid dataset_id source_sha256 state page pages zoom_percent page_size_points rendered_sha256 rendered_pixels window_id frame_id geometry mapped status canvas controls} {
        if {![dict exists $receipt $field]} {error "PDF reader frame lacks $field"}
    }
    if {[dict get $receipt schema] ne {gxtxt.pdf_reader_receipt.v1} || [dict get $receipt pid] ni $state($w,externalPids) || [dict get $receipt dataset_id] ne $state($w,id) || [dict get $receipt source_sha256] ne $state($w,mediaSourceSha) || [dict get $receipt state] ni {starting rendering ready unavailable closed}} {error {PDF reader frame does not match its launched source owner}}
    set kind [expr {[info exists state($w,managedResource)] ? {managed_resource} : {dataset}}]
    if {[datasetPublicationV2DictDefault $receipt source_kind dataset] ne $kind} {error {PDF reader source kind differs from its owner}}
    foreach field {window_id frame_id} {if {![regexp {^(0x[0-9a-fA-F]+|[0-9]+)$} [dict get $receipt $field]]} {error {Invalid owned native window identity}}}
    foreach field {page pages} {if {![string is integer -strict [dict get $receipt $field]] || [dict get $receipt $field]<0} {error {Invalid PDF page receipt}}}
    if {![string is double -strict [dict get $receipt zoom_percent]] || [dict get $receipt zoom_percent]<10 || [dict get $receipt zoom_percent]>400} {error {Invalid PDF zoom receipt}}
    if {[lsort [dict keys [dict get $receipt controls]]] ne [lsort {previous next zoom_out zoom_in fit_page fit_width}]} {error {Unexpected PDF reader controls}}
    foreach control [concat [dict values [dict get $receipt controls]] [list [dict get $receipt canvas]]] {
        if {![string is integer -strict [dict get $control native_id]] || [llength [dict get $control rectangle]]!=4} {error {Invalid owned PDF control geometry}}
        foreach value [dict get $control rectangle] {if {![string is integer -strict $value]} {error {Invalid PDF control pixel value}}}
    }
    set state($w,mediaReceipt) $receipt
}
proc ::GX::datasetMediaViewerInspect {w} {
    variable ::GX::DatasetViewer::state
    datasetViewerCheck $w
    if {![info exists state($w,mediaKind)] || $state($w,mediaKind) ne {pdf}} {error {This media owner is not a PDF reader}}
    set receipt $state($w,mediaReceipt)
    # Native identities/coordinates belong only to the trusted GUI-test owner.
    set public [dict remove $receipt pid window_id frame_id controls canvas]
    if {[dict exists $receipt canvas]} {
        dict set public canvas [dict remove [dict get $receipt canvas] native_id rectangle]
        dict for {name control} [dict get $receipt controls] {dict set public controls $name [dict create mapped [dict get $control mapped] enabled [dict get $control enabled]]}
    }
    dict set public session $state($w,session)
    if {[info exists state($w,managedResource)]} {
        set public [dict remove $public dataset_id]
        dict set public source_kind managed_resource
        dict set public document_id $state($w,id)
        dict set public resource $state($w,managedResource)
    }
    dict set public read_only 1
    return $public
}

rename ::GX::openSessionPath ::GX::openSessionPath_before_dataset_edit_guard
proc ::GX::openSessionPath {path} {
    if {[info exists ::GX::datasetPageEditors]&&[dict size $::GX::datasetPageEditors]} {error {Save or Cancel the open Dataset editor before switching Sessions. Draft input remains in its section.}}
    tailcall openSessionPath_before_dataset_edit_guard $path
}
source [file join [file dirname [info script]] dataset_digitizer_preview_v1.tcl]

# Render dependencies exclude user Preview controls, retaining scientific source,
# schema, calibration and public metadata. Host-side retained presentation only.
proc ::GX::datasetViewerLinkedSourceIdentity {session id} {
    if {[catch {set record [sessionInspectionDataset $id $session]} reason]} {return [dict create dataset_id $id status missing reason $reason]}
    set identity [dict create dataset_id $id registry $record metadata [datasetMetadataRead $session $id]]
    set reason {Canonical linked source has no resource path}
    if {[dict exists $record path] && ![catch {set actual [sessionInspectionResolveResource [dict get $record path] $session]} reason]} {
        dict set identity status resolved
        dict set identity resource $actual
    } else {
        dict set identity status unverified
        dict set identity reason $reason
    }
    return $identity
}
proc ::GX::datasetViewerScientificIdentity {id} {
    set storage [datasetProviderFor $id];set location {}
    if {$storage eq "remote"} {set location [list [datasetField $id remote_node_id] [datasetField $id remote_session_id] [datasetField $id remote_revision]]} else {
        set path [datasetResolvePath $::GX::currentSession $id]
        if {[file isfile $path]} {file stat $path st;set location [list $st(size) $st(mtime) $st(ctime) $st(ino)]}
    }
    set metadata [datasetViewerMetadataIdentity $::GX::currentSession $id]
    set identity [list $id [datasetField $id canonical_sha256 [datasetField $id sha256]] [datasetVariableSchemaV3 $id] $metadata [_datasetCoordinateStored $::GX::currentSession $id] $location]
    if {[dict exists $metadata curve_digitizer.source_dataset_id] && [dict get $metadata curve_digitizer.source_dataset_id] ne {}} {
        lappend identity linked_source [datasetViewerLinkedSourceIdentity $::GX::currentSession [dict get $metadata curve_digitizer.source_dataset_id]]
    }
    return $identity
}
