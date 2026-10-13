# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset Transform owns structural recipes; storage and commit remain in the
# existing Canonical Dataset, Schema, Metadata and Publication authorities.
namespace eval ::GX::DatasetTransform {
    variable serial 0
    variable plans;array set plans {}
    variable views;array set views {}
    variable streams;array set streams {}
}
proc ::GX::datasetTransformOperations {} {
    return {project_variables subset_rows concat_rows merge_columns join_by_key rename_reorder curve_bundle build_family extract_family_member split_family convert_units transform_xy reverse_rows reverse_range reverse_sequence combine_selection sort_rows}
}
proc ::GX::datasetTransformDescribeOperation {operation} {
    if {$operation ni [datasetTransformOperations]} {error "Unknown Dataset Transform operation '$operation'"}
    return [dict create api_id DATASET_TRANSFORM_API_v1 api_version 1 operation $operation manifest DATASET_TRANSFORM_MANIFEST_v1 create_only 1 interpolation none bounded_input_chunk_rows 65536 temporary_index disk metadata_policies {inherit_single_source inherit_primary merge_common explicit} ordering explicit]
}
proc ::GX::_datasetTransformSourceSnapshot {session id} {
    set payload [sessionInspectionDatasetPayload $id $session]
    return [dict create dataset_id $id sha256 [dict get $payload sha256] schema [datasetVariableSchemaV3 $id] metadata [datasetMetadataRead $session $id]]
}
proc ::GX::_datasetTransformNormalize {session manifest} {
    if {[catch {dict size $manifest}]} {error "Dataset Transform Manifest must be a dictionary"}
    foreach key [dict keys $manifest] {
        if {$key ni {api_id api_version operation sources output options schema_policy metadata_policy}} {error "Unknown Dataset Transform Manifest field '$key'"}
    }
    foreach key {api_version operation sources} {if {![dict exists $manifest $key]} {error "Dataset Transform Manifest needs '$key'"}}
    if {[dict get $manifest api_version] ne "1"} {error "Unsupported Dataset Transform Manifest version"}
    datasetTransformDescribeOperation [dict get $manifest operation]
    foreach key {output options schema_policy} {
        if {![dict exists $manifest $key]} {dict set manifest $key [dict create]}
        if {[catch {dict size [dict get $manifest $key]}]} {error "Manifest $key must be a dictionary"}
    }
    set output [dict get $manifest output]
    foreach key [dict keys $output] {if {$key ni {dataset_id member_outputs contract storage display_name notes}} {error "Unsupported transform output field '$key'"}}
    if {[dict exists $output dataset_id] && [dict get $output dataset_id] ne ""} {dict set output dataset_id [datasetPublicationV2RequestedId [dict get $output dataset_id]]}
    if {![dict exists $output contract]} {dict set output contract auto}
    if {![dict exists $output storage]} {dict set output storage auto}
    if {[dict get $output storage] ni {auto csv hdf5}} {error "Transform storage must be auto, csv or hdf5"}
    if {[dict get $manifest operation] eq "split_family"} {
        if {![dict exists $output member_outputs] || ![dict size [dict get $output member_outputs]]} {error "split_family requires explicit output member_outputs mapping"}
        set ids {};set normalized [dict create]
        dict for {member requested} [dict get $output member_outputs] {
            set id [datasetPublicationV2RequestedId $requested]
            if {[string trim $requested] eq "" || $id in $ids} {error "Split outputs require distinct nonempty requested Dataset IDs"}
            lappend ids $id;dict set normalized $member $id
        }
        dict set output member_outputs $normalized
    } elseif {[dict exists $output member_outputs]} {error "member_outputs is only valid for split_family"}
    set allowedOptions {variable_ids rename display_labels start count reorder ranges steps keys mode join duplicate_policy representation x_tolerance member_id members member_variable_id source_member_ids family_axes family_units target_units x_variable_id y_variable_id matrix metadata include_lineage lineage_prefix order_variable_ids descending polar_output preserve_auxiliary}
    foreach key [dict keys [dict get $manifest options]] {if {$key ni $allowedOptions} {error "Unknown Dataset Transform option '$key'"}}
    dict for {key value} [dict get $manifest schema_policy] {
        if {$key ni {dtype_policy unit_policy} || ($key eq "dtype_policy" && $value ne "strict") || ($key eq "unit_policy" && $value ne "explicit")} {error "Unsupported Dataset Transform schema policy '$key=$value'"}
    }
    dict set manifest output $output
    set sources {};set members {};set snapshots {}
    foreach source [dict get $manifest sources] {
        if {[catch {dict size $source}] || (![dict exists $source dataset_id] && ![dict exists $source native_geometry])} {error "Every transform source needs a Dataset or owned Native geometry"}
        foreach key [dict keys $source] {
            if {$key ni {dataset_id member_id variable_ids variable_map x_variable_id y_variable_id start count rows row_operation row_filters selection_filters selection_operation family_coordinates convert_units assume_units selection_id order_variable_ids reverse native_geometry}} {error "Unknown transform source field '$key'"}
        }
        set id [datasetPublicationV2DictDefault $source dataset_id {}]
        if {$id ne {}} {datasetPublicationV2ValidateId source_dataset $id}
        if {[dict exists $source native_geometry]} {
            if {[dict get $manifest operation] ni {concat_rows curve_bundle build_family}} {error "Owned Native geometry materialization requires concat_rows, curve_bundle or build_family"}
            set geometry [dict get $source native_geometry]
            foreach key [dict keys $geometry] {if {$key ni {xy_resource row_resource gap_resource x_variable y_variable}} {error "Unknown Native geometry source field '$key'"}}
            foreach key {xy_resource x_variable y_variable} {if {![dict exists $geometry $key]} {error "Native geometry source requires $key"}}
            set reference [dict get $geometry xy_resource];interactiveDocumentResourceInfo $reference
            if {[dict get $reference metadata format] ne "native2d.float64_xy_le_v1"||[dict get $reference size_bytes]%16} {error "Native geometry requires owned float64 XY rows"}
            set count [expr {[dict get $reference size_bytes]/16}]
            foreach {key width} {row_resource 8 gap_resource 1} {if {[dict exists $geometry $key]} {set ref [dict get $geometry $key];interactiveDocumentResourceInfo $ref;if {[dict get $ref size_bytes]!=$count*$width} {error "Native geometry $key shape differs from XY rows"}}}
        }
        if {![dict exists $source member_id]} {dict set source member_id "member[expr {[llength $sources]+1}]"}
        set member [dict get $source member_id]
        datasetPublicationV2ValidateId dataset $member
        if {$member in $members} {error "Duplicate transform member ID '$member'"}
        lappend members $member
        if {[dict exists $source selection_id]} {
            set selection [sessionInspectionSelection [dict get $source selection_id] $session]
            if {[dict get $selection source_dataset_id] ne $id} {error "Selection belongs to a different Dataset"}
            set filters [datasetPublicationV2DictDefault $source row_filters {}]
            foreach axis {x y} {
                if {$axis eq "y" && [dict get $selection type] ne "rectangle"} continue
                lappend filters [dict create filter_variable_id [dict get $selection ${axis}_variable_id] predicate between_inclusive lower [dict get $selection ${axis}_min] upper [dict get $selection ${axis}_max]]
            }
            dict set source selection_filters [lrange $filters [llength [datasetPublicationV2DictDefault $source row_filters {}]] end]
        }
        if {$id ne {}} {lappend snapshots [_datasetTransformSourceSnapshot $session $id]}
        lappend sources $source
    }
    if {![llength $sources]} {error "Dataset Transform needs at least one source"}
    dict set manifest sources $sources
    if {$snapshots eq {}} {dict set manifest metadata_policy explicit}
    set policy [datasetPublicationV2DictDefault $manifest metadata_policy [expr {[llength $sources]==1 ? "inherit_single_source" : "merge_common"}]]
    if {$policy ni {inherit_single_source inherit_primary merge_common explicit}} {error "Unknown transform metadata policy '$policy'"}
    if {$policy eq "inherit_single_source" && [llength $sources]!=1} {error "inherit_single_source requires exactly one source"}
    dict set manifest metadata_policy $policy
    dict set manifest api_id DATASET_TRANSFORM_MANIFEST_v1
    return [list $manifest $snapshots]
}
proc ::GX::datasetTransformPlan {session manifest} {_datasetTransformPlanInternal $session $manifest ""}
proc ::GX::_datasetTransformGeometryOwners {manifest} {
    set owners {}
    foreach source [dict get $manifest sources] {
        if {![dict exists $source native_geometry]} continue
        foreach key {xy_resource row_resource gap_resource} {
            if {![dict exists $source native_geometry $key]} continue
            set reference [dict get $source native_geometry $key]
            interactiveDocumentResourceInfo $reference
            set id [dict get $reference document_id];set owner [interactiveDocumentRead $id]
            dict set owners $id [dict create generation [dict get $owner generation] revision [dict get $owner revision]]
        }
    }
    return $owners
}
proc ::GX::_datasetTransformPlanInternal {session manifest job} {
    variable ::GX::DatasetTransform::plans;variable ::GX::DatasetTransform::serial
    variable scriptDir
    set session [file normalize $session]
    set ::GX::currentSession $session
    loadDatasetRegistry $session
    lassign [_datasetTransformNormalize $session $manifest] manifest snapshots
    set geometryOwners [_datasetTransformGeometryOwners $manifest]
    set f [file tempfile directory];close $f;file delete -- $directory;file mkdir $directory
    try {
        # Resolve owned resource authority in CORE. Only this private worker
        # manifest receives staged paths; plugins supply no filesystem paths.
        set workerManifest $manifest;set stagedSources {};set resourceIndex 0
        foreach source [dict get $manifest sources] {
            if {[dict exists $source native_geometry]} {
                foreach key {xy_resource row_resource gap_resource} {
                    if {![dict exists $source native_geometry $key]} continue
                    set reference [dict get $source native_geometry $key]
                    set reader [interactiveDocumentResourceOpenReader $reference]
                    set path [file join $directory geometry_[incr resourceIndex].bin];set channel [open $path wb]
                    set stagedBytes 0
                    try {while 1 {
                        set chunk [interactiveDocumentResourceNext $reader];puts -nonewline $channel [dict get $chunk bytes];incr stagedBytes [string length [dict get $chunk bytes]]
                        if {$job ne {}} {_datasetTransformResponsiveBoundary $job stage_geometry $stagedBytes [dict get $reference size_bytes]}
                        if {[dict get $chunk eof]} break
                    }} finally {close $channel;interactiveDocumentResourceCloseReader $reader}
                    dict set source _${key}_file $path
                }
            }
            lappend stagedSources $source
        }
        dict set workerManifest sources $stagedSources
        set f [open [file join $directory runtime.ini] w]
        puts $f "\[runtime\]\nsession=$session\nmodule_id=core.dataset_transform\noperation=plan";close $f
        set f [open [file join $directory request.utf8] w];fconfigure $f -encoding utf-8 -translation lf;puts -nonewline $f $workerManifest;close $f
        set command [list [runtimeToolRequired python] -B [file join $scriptDir core python dataset_transform_worker_v1.py] [file join $directory runtime.ini] [file join $directory request.utf8] $directory]
        if {$job eq ""} {set report [exec {*}$command]} else {set report [_datasetTransformResponsiveWorker $job $command]}
        if {[catch {dict size $report}]} {error "Dataset Transform worker returned an invalid plan"}
        if {[_datasetTransformGeometryOwners $manifest] ne $geometryOwners} {error "Native geometry owner changed while planning; plan again"}
        foreach snapshot $snapshots {
            if {[_datasetTransformSourceSnapshot $session [dict get $snapshot dataset_id]] ne $snapshot} {error "Source Dataset changed while planning; plan again"}
        }
        set token "transform-plan#[pid]-[incr serial]"
        set plans($token) [dict create session $session session_token [interactiveDocumentSessionToken] directory $directory manifest $manifest snapshots $snapshots geometry_owners $geometryOwners report $report]
        set directory ""
        return [dict merge $report [dict create plan_id $token manifest $manifest status ready]]
    } finally {if {$directory ne ""} {file delete -force -- $directory}}
}
proc ::GX::datasetTransformValidate {session manifest} {
    set plan [datasetTransformPlan $session $manifest]
    set result [dict remove $plan plan_id]
    datasetTransformReleasePlan [dict get $plan plan_id]
    return [dict merge $result [dict create valid 1]]
}
proc ::GX::datasetTransformReleasePlan {token} {
    variable ::GX::DatasetTransform::plans;variable ::GX::DatasetTransform::views
    if {![info exists plans($token)]} {error "Unknown Dataset Transform plan"}
    foreach view [array names views] {if {[dict get $views($view) plan_id] eq $token} {error "Plan has an open transform view"}}
    file delete -force -- [dict get $plans($token) directory]
    unset plans($token)
}
proc ::GX::_datasetTransformRequire {token} {
    variable ::GX::DatasetTransform::plans;variable currentSession
    if {![info exists plans($token)]} {error "Unknown or released Dataset Transform plan"}
    set record $plans($token)
    if {[interactiveDocumentSessionToken] ne [dict get $record session_token]} {error "Dataset Transform belongs to a different Session lifetime"}
    if {[_datasetTransformGeometryOwners [dict get $record manifest]] ne [dict get $record geometry_owners]} {error "Native geometry owner revision/generation changed; plan again"}
    foreach snapshot [dict get $record snapshots] {
        if {[_datasetTransformSourceSnapshot [dict get $record session] [dict get $snapshot dataset_id]] ne $snapshot} {error "Dataset Transform source/schema/metadata changed; plan again"}
    }
    return $record
}
proc ::GX::datasetTransformOpenView {session manifestOrPlan {member ""}} {
    variable ::GX::DatasetTransform::views;variable ::GX::DatasetTransform::serial
    set ownsPlan [expr {![dict exists $manifestOrPlan plan_id]}]
    if {!$ownsPlan} {set plan $manifestOrPlan} else {set plan [datasetTransformPlan $session $manifestOrPlan]}
    set token [dict get $plan plan_id];_datasetTransformRequire $token
    set record [_datasetTransformRequire $token]
    if {$member ne "" && ![dict exists $record report family_parts $member]} {error "Unknown split-family view member"}
    set view "transform-view#[pid]-[incr serial]";set views($view) [dict create plan_id $token owns_plan $ownsPlan member $member]
    return $view
}
proc ::GX::datasetTransformOpenViewStream {view {variableIds {}} {chunkRows 4096} {options {}}} {
    variable ::GX::DatasetTransform::views;variable ::GX::DatasetTransform::streams;variable ::GX::DatasetTransform::serial
    if {![info exists views($view)]} {error "Unknown or closed Dataset Transform view"}
    if {![string is entier -strict $chunkRows] || $chunkRows<1 || $chunkRows>65536} {error "Transform chunk_rows must be 1..65536"}
    set record [_datasetTransformRequire [dict get $views($view) plan_id]]
    set report [dict get $record report]
    set member [dict get $views($view) member]
    set filename values.hexrows
    if {$member ne ""} {
        dict set report row_count [dict get $report family_parts $member]
        set index [lsearch -exact [dict keys [dict get $record manifest output member_outputs]] $member]
        set filename [format part_%06d.hexrows $index]
        set specs {}
        foreach spec [dict get $report variables] {dict set spec shape [dict get $report row_count];dict set spec axis_count [dict get $report row_count];lappend specs $spec}
        dict set report variables $specs
    }
    set allIds [lmap v [dict get $report variables] {dict get $v variable_id}]
    if {$variableIds eq {}} {set variableIds $allIds}
    set indices {};set variables {}
    foreach id $variableIds {
        set index [lsearch -exact $allIds $id]
        if {$index<0 || $index in $indices} {error "Unknown or duplicate transform Variable ID '$id'"}
        lappend indices $index;lappend variables [lindex [dict get $report variables] $index]
    }
    foreach key [dict keys $options] {if {$key ni {start count}} {error "Unknown transform stream option '$key'"}}
    set start [datasetPublicationV2DictDefault $options start 0];set count [datasetPublicationV2DictDefault $options count -1]
    set total [dict get $report row_count]
    if {![string is entier -strict $start] || ![string is entier -strict $count] || $start<0 || $start>$total || $count< -1 || ($count>=0 && $start+$count>$total)} {error "Transform stream range is outside the view"}
    if {$count<0} {set count [expr {$total-$start}]}
    set f [open [file join [dict get $record directory] $filename] r];fconfigure $f -encoding ascii -translation lf
    for {set i 0} {$i<$start} {incr i} {gets $f}
    set stream "transform-stream#[pid]-[incr serial]"
    set streams($stream) [dict create api_version 3 dataset_id "" storage_provider logical_transform contract [dict get $report contract] view $view channel $f variables $variables variable_ids $variableIds selected_variable_ids $variableIds ids $variableIds indices $indices position $start start $start remaining $count row_count $total chunk_rows $chunkRows chunks_read 0 rows_returned 0]
    return $stream
}
proc ::GX::datasetTransformStreamMetadata {stream} {
    variable ::GX::DatasetTransform::streams
    if {![info exists streams($stream)]} {error "Unknown or closed Dataset Transform stream"}
    return [dict remove $streams($stream) channel indices view remaining position]
}
proc ::GX::datasetTransformStreamNext {stream} {
    variable ::GX::DatasetTransform::streams
    if {![info exists streams($stream)]} {error "Unknown or closed Dataset Transform stream"}
    set record $streams($stream);set values [dict create]
    foreach id [dict get $record ids] {dict set values $id {}}
    set count [expr {min([dict get $record remaining],[dict get $record chunk_rows])}]
    set f [dict get $record channel];set offset [dict get $record position]
    for {set i 0} {$i<$count} {incr i} {
        if {[gets $f line]<0} {error "Truncated private transform row transport"}
        set fields [split $line \t]
        foreach id [dict get $record ids] index [dict get $record indices] {
            dict lappend values $id [encoding convertfrom utf-8 [binary decode hex [lindex $fields $index]]]
        }
    }
    dict incr record position $count;dict incr record remaining [expr {-$count}]
    dict incr record chunks_read;dict incr record rows_returned $count;set streams($stream) $record
    set columns {}
    foreach spec [dict get $record variables] {lappend columns [dict merge $spec [dict create values [dict get $values [dict get $spec variable_id]] count $count transport values]]}
    return [dict create api_version 3 offset $offset start $offset nrows $count row_count $count values $values columns $columns selected_variable_ids [dict get $record ids] eof [expr {[dict get $record remaining]==0}]]
}
proc ::GX::datasetTransformStreamDiagnostics {stream} {
    variable ::GX::DatasetTransform::streams
    if {![info exists streams($stream)]} {error "Unknown or closed Dataset Transform stream"}
    set record $streams($stream)
    return [dict create api_version 3 storage_provider logical_transform chunk_rows [dict get $record chunk_rows] chunks_read [dict get $record chunks_read] rows_returned [dict get $record rows_returned] temporary_index disk registry_entries_created 0]
}
proc ::GX::datasetTransformStreamClose {stream} {
    variable ::GX::DatasetTransform::streams
    if {![info exists streams($stream)]} {error "Unknown or closed Dataset Transform stream"}
    close [dict get $streams($stream) channel];unset streams($stream)
}
proc ::GX::datasetTransformCloseView {view} {
    variable ::GX::DatasetTransform::views;variable ::GX::DatasetTransform::streams
    if {![info exists views($view)]} {error "Unknown or closed Dataset Transform view"}
    foreach stream [array names streams] {if {[dict get $streams($stream) view] eq $view} {datasetTransformStreamClose $stream}}
    set record $views($view)
    unset views($view)
    if {[dict get $record owns_plan]} {datasetTransformReleasePlan [dict get $record plan_id]}
}
proc ::GX::_datasetTransformMetadata {record} {
    set manifest [dict get $record manifest];set snapshots [dict get $record snapshots]
    set policy [dict get $manifest metadata_policy]
    set result [dict create];set conflicts [dict create]
    if {$snapshots ne {}&&$policy in {inherit_single_source inherit_primary}} {set result [dict get [lindex $snapshots 0] metadata]}
    if {$policy eq "explicit"} {set result [datasetPublicationV2DictDefault [dict get $manifest options] metadata {}]}
    if {$snapshots ne {}&&$policy eq "merge_common"} {
        set result [dict get [lindex $snapshots 0] metadata]
        foreach snapshot [lrange $snapshots 1 end] {
            set metadata [dict get $snapshot metadata]
            dict for {key value} $result {
                if {![dict exists $metadata $key] || [dict get $metadata $key] ne $value} {
                    dict set conflicts $key 1;dict unset result $key
                }
            }
        }
    }
    foreach key [dict keys $result] {if {[string match transform.* $key]} {dict unset result $key}}
    dict set result transform.api_version 1
    dict set result transform.manifest $manifest
    dict set result transform.effective [dict get $record report]
    dict set result transform.metadata_conflicts [lsort [dict keys $conflicts]]
    dict set result transform.producer core.dataset_transform
    dict set result transform.producer_version 1.0.0
    dict set result transform.timestamp [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S%z]
    set output [dict get $manifest output]
    if {[dict exists $output display_name]} {dict set result dataset.display_name [dict get $output display_name]}
    return $result
}
proc ::GX::datasetTransformExecute {session manifestOrPlan} {
    set own [expr {![dict exists $manifestOrPlan plan_id]}]
    if {$own} {set plan [datasetTransformPlan $session $manifestOrPlan]} else {set plan $manifestOrPlan}
    try {
        if {[dict get [_datasetTransformRequire [dict get $plan plan_id]] manifest operation] eq "split_family"} {
            return [datasetCatalogTransaction ::GX::_datasetTransformExecuteSplit $session $plan]
        }
        return [_datasetTransformMaterialize $session $plan]
    } finally {
        if {$own} {datasetTransformReleasePlan [dict get $plan plan_id]}
    }
}
proc ::GX::_datasetTransformExecuteSplit {session plan} {
    set record [_datasetTransformRequire [dict get $plan plan_id]]
    set ids [dict values [dict get $record manifest output member_outputs]]
    foreach id $ids {if {[datasetField $id id ""] ne ""} {error "Dataset ID '$id' already exists"}}
    set created {};set results {}
    try {
        dict for {member id} [dict get $record manifest output member_outputs] {
            set result [_datasetTransformMaterialize $session $plan $member]
            lappend created $id;lappend results $result
        }
    } on error {reason options} {
        set rollbackErrors {}
        foreach id [lreverse $created] {
            if {[catch {datasetDelete $session $id} cleanupError]} {lappend rollbackErrors "$id: $cleanupError"}
        }
        if {[llength $rollbackErrors]} {append reason "; split rollback failed: [join $rollbackErrors {; }]"}
        return -options $options $reason
    }
    return [dict create api_version 1 operation split_family dataset_ids $ids datasets $results]
}
proc ::GX::_datasetTransformMaterialize {session plan {member ""} {job ""}} {
    set record [_datasetTransformRequire [dict get $plan plan_id]]
    set manifest [dict get $record manifest];set output [dict get $manifest output];set report [dict get $record report]
    if {$member ne ""} {
        dict set output dataset_id [dict get $output member_outputs $member]
        dict set report row_count [dict get $report family_parts $member]
        dict set report output_member_id $member
        set specs {}
        foreach spec [dict get $report variables] {dict set spec shape [dict get $report row_count];dict set spec axis_count [dict get $report row_count];lappend specs $spec}
        dict set report variables $specs
    }
    if {![dict exists $output dataset_id] || [dict get $output dataset_id] eq ""} {error "Materialization requires an explicit output Dataset ID"}
    set sourceIds [lmap snapshot [dict get $record snapshots] {dict get $snapshot dataset_id}]
    set bindings {};foreach source [dict get $report source_fingerprints] {if {[dict get $source dataset_id] eq {}} continue;foreach variable [dict get $source variable_ids] {lappend bindings "[dict get $source dataset_id]:$variable"}}
    set definition [dict create dataset_id [dict get $output dataset_id] contract [dict get $report contract] storage [dict get $output storage] expected_rows [dict get $report row_count] estimated_numeric_bytes [expr {[dict get $report row_count]*[llength [dict get $report variables]]*8}] producer_version 1.0.0 source "CORE Dataset Transform" source_dataset_ids $sourceIds source_variable_ids $bindings structured_metadata [_datasetTransformMetadata $record] provenance $manifest notes [datasetPublicationV2DictDefault $output notes ""]]
    set publication [datasetPublicationV2Prepare $session core.dataset_transform $definition]
    set publicationInfo [datasetPublicationV2PlanInfo $publication]
    dict set report output_storage_provider [dict get $publicationInfo provider]
    dict set report output_dataset_id [dict get $output dataset_id]
    dict set record report $report
    datasetPublicationV2SetPlanMetadata $publication [_datasetTransformMetadata $record]
    set writer "";set view "";set stream ""
    try {
        set writer [datasetPublicationV2OpenWriter $publication]
        datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach spec [dict get $report variables] {
            # The plan describes final shape; the append writer initially owns
            # an empty extendible dimension and grows its schema transactionally.
            datasetPublicationV2DeclareVariable $writer [dict get $spec variable_id] [dict remove $spec shape maxshape axis_count]
        }
        set view [datasetTransformOpenView $session $plan $member]
        # Publication accepts bounded bulk columns. Avoid hundreds of small
        # index/provider transactions for large complete-tuple results.
        set chunkRows [expr {$job eq "" ? 65536 : [_datasetTransformResponsiveChunkRows $job]}]
        set stream [datasetTransformOpenViewStream $view {} $chunkRows]
        set rows 0
        if {$job ne ""} {_datasetTransformResponsiveBoundary $job materializing $rows [dict get $report row_count]}
        while {1} {
            set chunk [datasetTransformStreamNext $stream]
            if {[dict get $chunk nrows]} {datasetPublicationV2Append $writer row [dict get $chunk values]}
            incr rows [dict get $chunk nrows]
            if {$job ne ""} {_datasetTransformResponsiveBoundary $job materializing $rows [dict get $report row_count]}
            if {[dict get $chunk eof]} break
        }
        if {$job ne ""} {
            _datasetTransformResponsiveBoundary $job precommit $rows [dict get $report row_count]
            # Final verification follows the last event-loop boundary. Commit
            # itself never yields or permits cancellation after registry writes.
            _datasetTransformRequire [dict get $plan plan_id]
        }
        set result [datasetPublicationV2Finalize $writer];set writer ""
        return [dict merge $result [dict create row_count [dict get $report row_count] contract [dict get $report contract]]]
    } finally {
        if {$writer ne ""} {datasetPublicationV2Abort $writer}
        if {$stream ne ""} {datasetTransformStreamClose $stream}
        if {$view ne ""} {datasetTransformCloseView $view}
    }
}
proc ::GX::datasetTransformProvenance {session datasetId} {
    set metadata [datasetMetadataRead $session $datasetId]
    set result [dict create]
    dict for {key value} $metadata {if {[string match transform.* $key]} {dict set result [string range $key 10 end] $value}}
    return $result
}
# Table Stream remains the shared read path. Only dispatch on this authority's
# opaque prefix; ordinary canonical streams retain their original implementation.
foreach {name implementation} {tableStreamNext datasetTransformStreamNext tableStreamMetadata datasetTransformStreamMetadata tableStreamDiagnostics datasetTransformStreamDiagnostics tableStreamClose datasetTransformStreamClose} {
    rename ::GX::$name ::GX::${name}_before_transform_v1
    proc ::GX::$name {stream args} [string map [list @IMPL@ $implementation @NAME@ $name] {
        if {[string match transform-stream#* $stream]} {tailcall ::GX::@IMPL@ $stream {*}$args}
        tailcall ::GX::@NAME@_before_transform_v1 $stream {*}$args
    }]
}
