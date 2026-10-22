# SPDX-License-Identifier: GPL-3.0-or-later
# Native3D owns all scientific geometry. This module owns semantic UI state.
namespace eval ::GX::Workbench3D {
    variable module viewer.3d_workbench;variable provider workbench_3d
    variable document {};variable scene {};variable tokens {};variable profileTokens {}
    variable model {};variable undo {};variable redo {};variable preview {};variable busy 0
    variable panel {};variable status Ready;variable selection {};variable dataset {};variable x {};variable y {}
    variable distance 1;variable mode new;variable target {};variable profile {};variable nextName Body
    variable primitive box;variable dimensions {1 1 1};variable radius 1;variable height 1
    variable resultId {};variable exportFormat stl;variable subscription {}
    variable editAction translate;variable closedProfile 1;variable includeProfile 0
    variable groupTokens {};variable groupName Group
    variable requestedUnit mm;variable convertProfileUnits 1;variable assumeProfileUnit 0
    variable constraintKind coincident
    variable measurementKind distance
    variable cleanupNotice {}
    variable allocationCounters {}
    variable extrusionTargets {};variable keepExtrusionTool 0
    # Tk presentation destinations are process-local, never scientific payload.
    variable guiHost {};variable planarHosts {}
}
proc ::GX::Workbench3D::defaultModel {} {
    return [dict create format workbench3d.document.v1 working_unit mm objects {} profiles {} next_object 0 next_profile 0 next_organization 0 next_comparison 0 recipe {} groups {} constraints {} measurements {} comparisons {} views {} selection_sets {} layers {} attrs {} view [::GX::viewerSceneDefaults]]
}
proc ::GX::Workbench3D::apiInfo {} {
    return [dict create api_id WORKBENCH_3D_API_v1 api_version 1 scientific_owner viewer.3d_workbench/workbench_3d document_format workbench3d.document.v1 operations {activateDocument guiMount guiInspect selectionSet selectionApply guiCommand} gui_commands [concat {primitive inspect save undo redo close} [guiFormCommands]] editable_hosts 1 sdk_exposure finite_declared_workbench_command full_parity_acceptance pending]
}
proc ::GX::Workbench3D::call {action request} {variable scene;return [::GX::native3DGeometryCall $scene $action $request]}
proc ::GX::Workbench3D::projectSelection {} {
    # Semantic selection belongs to this owner; a legacy tree is optional.
    # Never turn an accepted geometry commit into a failed operation because
    # its old presentation is absent or its widget acknowledgement fails.
    variable panel;variable selection;variable model;variable profile;variable status
    set ::GX::Engine3D::selectedLayer {}
    if {[llength $selection]==1} {
        set id [lindex $selection 0]
        if {[dict exists $model objects $id] || [dict exists $model profiles $id]} {
            set ::GX::Engine3D::selectedLayer $id
            if {[dict exists $model profiles $id]} {set profile $id}
        }
    }
    if {$panel ne {} && [winfo exists $panel.objects]} {
        if {[catch {
            $panel.objects selection set $selection
            if {[llength $selection]} {$panel.objects see [lindex $selection 0]}
        } message]} {set status "Selection presentation failed: $message"}
    }
    guiPresentationChanged
}
proc ::GX::Workbench3D::millimeters {} {
    variable model
    set unit [dict get $model working_unit]
    ::GX::unitRegistryConversionPlan $unit mm
    return [expr {[::GX::unitRegistryIntrinsicScale $unit]/[::GX::unitRegistryIntrinsicScale mm]}]
}
proc ::GX::Workbench3D::allocationMerge {counters snapshot} {
    foreach key {next_object next_profile next_group next_constraint next_measurement next_organization next_comparison} {
        set value [::GX::datasetPublicationV2DictDefault $snapshot $key 0]
        set prior [::GX::datasetPublicationV2DictDefault $counters $key 0]
        if {![string is entier -strict $value]||$value<0||![string is entier -strict $prior]||$prior<0} {error "Invalid 3D logical identity allocation counter"}
        dict set counters $key [expr {max($value,$prior)}]
    }
    return $counters
}
proc ::GX::Workbench3D::nextId {key prefix} {
    variable model;variable allocationCounters
    set value [expr {[dict get [allocationMerge $allocationCounters $model] $key]+1}]
    dict set model $key $value
    return "${prefix}_$value"
}
proc ::GX::Workbench3D::payload {} {
    variable model;variable undo;variable redo;variable allocationCounters
    return [dict create model $model undo $undo redo $redo allocation_counters [allocationMerge $allocationCounters $model]]
}
proc ::GX::Workbench3D::checkpoint {} {
    variable scene;variable model;variable module;variable provider;variable allocationCounters
    foreach key {dataset x y distance mode target profile nextName primitive dimensions radius height resultId exportFormat editAction closedProfile includeProfile convertProfileUnits assumeProfileUnit extrusionTargets keepExtrusionTool} {dict set model tool_settings $key [set ::GX::Workbench3D::$key]}
    dict set model view [::GX::viewerSceneGet $module $provider]
    set result [::GX::native3DGeometryCheckpoint $scene [payload]]
    # Acknowledge only committed identities. Undo keeps these separate from
    # model snapshots; failed uncommitted staging remains retryable.
    set allocationCounters [allocationMerge $allocationCounters $model]
    return $result
}
proc ::GX::Workbench3D::record {operation parameters targets results} {
    variable model
    dict lappend model recipe [dict create api_id NATIVE_3D_GEOMETRY_API_v1 api_version 1 provider native3d_geometry module_id viewer.3d_workbench module_version [::GX::moduleField viewer.3d_workbench version] operation $operation parameters $parameters targets $targets result_ids $results working_unit [dict get $model working_unit]]
    dict set model recipe [lrange [dict get $model recipe] end-127 end]
}
proc ::GX::Workbench3D::commit {before operation parameters targets results} {
    variable model;variable undo;variable redo;variable document;variable preview;variable scene;variable module;variable provider;variable status;variable cleanupNotice
    set oldUndo $undo;set oldRedo $redo
    set oldView [::GX::datasetPublicationV2DictDefault $before view [::GX::viewerSceneGet $module $provider]]
    set validated {}
    lappend undo $before;set undo [lrange $undo end-31 end];set redo {}
    record $operation $parameters $targets $results
    try {
        set validated [::GX::native3DGeometrySceneInfo $scene]
        # Complete presentation/cache staging before the authoritative write.
        # A failed display/import can then roll back without a committed Doc.
        refresh
        checkpoint
    } on error {message options} {
        set model $before;set undo $oldUndo;set redo $oldRedo
        if {$validated ne {}&&[dict get $validated session_token] eq [::GX::interactiveDocumentSessionToken]} {
            ::GX::viewerSceneSet $module $provider $oldView
            if {[catch {refresh} rollback]} {append message "; presentation rollback failed: $rollback"}
        }
        return -options $options $message
    }
    # Garbage collection follows a successful commit. Its failure cannot turn
    # that committed action into an apparent rollback or discard its undo.
    set cleanup ok
    if {[catch {::GX::interactiveDocumentResourceCollect $document $preview} message]} {set cleanup $message;set cleanupNotice $message;set status "Action committed. Resource cleanup failed: $message"}
    guiPresentationChanged
    return [dict create status committed cleanup_status $cleanup]
}
proc ::GX::Workbench3D::resourceToFile {reference path} {
    set reader [::GX::interactiveDocumentResourceOpenReader $reference];set f {}
    try {
        set f [::open $path wb]
        while 1 {set part [::GX::interactiveDocumentResourceNext $reader];puts -nonewline $f [dict get $part bytes];if {[dict get $part eof]} break}
    } finally {if {$f ne {}} {::close $f};::GX::interactiveDocumentResourceCloseReader $reader}
}
proc ::GX::Workbench3D::renderResource {reference id fields} {
    variable module;variable provider
    set root [file join [::GX::configurationCacheDirectory] workbench3d];file mkdir $root
    set format [lindex [split [dict get $reference metadata format] .] 1]
    set path [file join $root "[dict get $reference sha256].$format"]
    if {![file isfile $path]||[::GX::sha256File $path] ne [dict get $reference sha256]} {resourceToFile $reference $path}
    set added [::GX::Engine3D::addArtifact $path]
    try {
        set layer [::GX::viewerLayerGet $module $provider $added]
        ::GX::viewerLayerSet $module $provider $id [dict merge $layer $fields]
    } finally {::GX::viewerLayerRemove $module $provider $added}
    return $id
}
proc ::GX::Workbench3D::snapshotObject {receipt} {
    variable scene
    set token [dict get $receipt object_token];set kind [dict get $receipt kind]
    # Authoritative mesh snapshots must preserve native Float64 coordinates.
    # Binary STL is suitable for the separate display artifact, but rounds
    # coordinates to Float32 and cannot be the Document/History source.
    set format [expr {$kind eq "brep" ? "step" : "vtp"}]
    set resource [::GX::native3DGeometryExportResource $scene $token $format [millimeters] local]
    if {$kind eq "brep"} {
        set mesh [call mesh [dict create object_token $token linear_deflection .01 angular_deflection .3 weld_tolerance 1e-8 max_triangles 1000000 max_output_bytes 134217728]]
        set meshToken [dict get $mesh object_token]
        try {set view [::GX::native3DGeometryExportResource $scene $meshToken stl [millimeters]]} finally {call delete [dict create object_token $meshToken]}
    } else {set view [::GX::native3DGeometryExportResource $scene $token stl [millimeters]]}
    return [dict create kind $kind geometry $resource display_geometry $view diagnostics [dict remove $receipt object_token] name Body visible 1 locked 0 group {} attrs {} source_bindings {} provenance {} style [dict create base_color {0.78;0.82;0.9} opacity 1 representation surface]]
}
proc ::GX::Workbench3D::installObject {receipt name {replace {}}} {
    return [installPreparedObject $receipt [snapshotObject $receipt] $name $replace]
}
proc ::GX::Workbench3D::installPreparedObject {receipt record name {replace {}}} {
    variable model;variable tokens
    if {$replace ne {}} {set id $replace;set previous [dict get $model objects $id];foreach key {visible locked group attrs style source_bindings geometry_role} {if {[dict exists $previous $key]} {dict set record $key [dict get $previous $key]}}} else {set id [nextId next_object body]}
    dict set record name $name;dict set model objects $id $record
    dict set tokens $id [dict get $receipt object_token]
    return $id
}
proc ::GX::Workbench3D::restoreStage {} {
    variable scene;variable document;variable model;variable tokens;variable profileTokens;variable groupTokens;variable module;variable provider
    set scene [::GX::native3DGeometryOpen $document];set tokens {};set profileTokens {};set groupTokens {}
    dict for {id record} [dict get $model objects] {
        set action [expr {[dict get $record kind] eq "brep" ? "restore_step" : "load_mesh"}]
        set receipt [call $action [dict create resource [dict get $record geometry]]]
        dict set tokens $id [dict get $receipt object_token]
    }
    dict for {id record} [dict get $model profiles] {
        set receipt [call profile [dict create contours [dict get $record contours] plane [dict get $record plane] tolerance [dict get $record tolerance]]]
        dict set profileTokens $id [dict get $receipt profile_token]
    }
    dict for {id group} [dict get $model groups] {
        set ids [dict get $group members];set originals [lmap member $ids {dict get $tokens $member}]
        set receipt [call group_copy [dict create object_tokens $originals]]
        foreach member $ids result [dict get $receipt members] {dict set tokens $member [dict get $result object_token]}
        foreach original $originals {call delete [dict create object_token $original]}
        dict set groupTokens $id [dict get $receipt group_token]
    }
    # The shared editable host survives Document switches. An older or empty
    # Document without a saved view must not inherit another Document's marker,
    # measurement, field or curve source references.
    set view [::GX::datasetPublicationV2DictDefault $model view [::GX::viewerSceneDefaults]]
    ::GX::viewerSceneSet $module $provider $view
    foreach {field key} {cameraPosition camera_position cameraTarget camera_target cameraUp camera_up planeOrigin working_plane_origin planeNormal working_plane_normal planeU working_plane_u_axis} {set ::GX::Engine3D::$field [dict get $view $key]}
    refresh
}
proc ::GX::Workbench3D::restore {} {
    variable scene;variable tokens;variable profileTokens;variable groupTokens;variable module;variable provider
    set previous $scene;set oldTokens $tokens;set oldProfiles $profileTokens;set oldGroups $groupTokens
    set oldView [::GX::viewerSceneGet $module $provider]
    try {restoreStage} on error {message options} {
        if {$scene ne $previous&&$scene ne {}&&[catch {::GX::native3DGeometryClose $scene} cleanup]} {append message "; staged-scene cleanup failed: $cleanup"}
        set scene $previous;set tokens $oldTokens;set profileTokens $oldProfiles;set groupTokens $oldGroups
        ::GX::viewerSceneSet $module $provider $oldView
        return -options $options $message
    }
    if {$previous ne {}} {::GX::native3DGeometryClose $previous}
}
proc ::GX::Workbench3D::refresh {} {
    variable panel;variable model;variable module;variable provider;variable preview;variable selection
    set havePanel [expr {$panel ne {}&&[winfo exists $panel]}]
    foreach {field label} {distance {Signed extrusion distance} dimensions {Box dimensions (X Y Z)} radius {Cylinder radius} height {Cylinder height}} {
        if {[winfo exists $panel.${field}Label]} {$panel.${field}Label configure -text "$label ([dict get $model working_unit])" -wraplength 280 -justify left}
    }
    if {$havePanel} {$panel.objects delete [$panel.objects children {}]}
    dict for {id record} [dict get $model objects] {
        if {$havePanel} {$panel.objects insert {} end -id $id -text [dict get $record name] -values [list [dict get $record kind] [dict get $record group] [dict get $record visible] [dict get $record locked]]}
        renderResource [dict get $record display_geometry] $id [dict merge [dict get $record style] [dict create visible [dict get $record visible]]]
    }
    dict for {id record} [dict get $model profiles] {
        set visible [::GX::datasetPublicationV2DictDefault $record visible 1];set locked [::GX::datasetPublicationV2DictDefault $record locked 0]
        if {$havePanel} {$panel.objects insert {} end -id $id -text "Profile: [dict get $record name]" -values [list profile {} $visible $locked]}
        if {[dict exists $record display_geometry]} {renderResource [dict get $record display_geometry] $id [dict merge [dict create kind trajectory base_color {1;0.6;0.1} line_width 3 representation wireframe visible $visible] [::GX::datasetPublicationV2DictDefault $record style {}]]}
    }
    foreach id [::GX::viewerLayerIds $module $provider] {if {![dict exists $model objects $id]&&![dict exists $model profiles $id]&&$id ne "operation_preview"} {::GX::viewerLayerRemove $module $provider $id}}
    if {$havePanel} {
        $panel.profile configure -values [dict keys [dict get $model profiles]]
        $panel.target configure -values [dict keys [dict get $model objects]]
    }
    set selection [lmap id $selection {if {![dict exists $model objects $id]&&![dict exists $model profiles $id]} continue;set id}]
    if {$havePanel} {$panel.objects selection set $selection}
    measurementPresentation
    ::GX::Engine3D::refreshLayers
}
proc ::GX::Workbench3D::datasetChoices {{event {}}} {
    variable panel;variable dataset;variable x;variable y
    if {$panel eq {}||![winfo exists $panel]} return
    $panel.dataset configure -values [::GX::datasetRegistryIds]
    set ids {};if {$dataset in [::GX::datasetRegistryIds]} {foreach variable [::GX::datasetVariableSchemaV3 $dataset] {if {[dict get $variable value_kind] eq "number"&&[dict get $variable rank]==1} {lappend ids [dict get $variable variable_id]}}}
    foreach axis {x y} {$panel.$axis configure -values $ids;if {[set $axis] ni $ids} {set $axis [lindex $ids [expr {$axis eq "x" ? 0 : 1}]]}}
}
proc ::GX::Workbench3D::loadProfile {} {
    variable dataset;variable x;variable y;variable scene;variable model;variable profileTokens;variable profile
    variable closedProfile;variable includeProfile
    variable convertProfileUnits;variable assumeProfileUnit
    set before $model
    # Retain admitted operation inputs while the native owner yields for RPC.
    set sourceDataset $dataset;set sourceX $x;set sourceY $y
    set sourceClosed $closedProfile;set append $includeProfile
    set targetProfile $profile;set priorActiveProfile $profile
    set convertUnits $convertProfileUnits;set assumeUnit $assumeProfileUnit
    set captured [::GX::native3DGeometrySceneInfo $scene]
    set view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d]
    set plane [dict create origin [split [dict get $view working_plane_origin] {;}] normal [split [dict get $view working_plane_normal] {;}] u_axis [split [dict get $view working_plane_u_axis] {;}]]
    if {$append} {
        if {![dict exists $model profiles $targetProfile]} {error "Select a profile to receive the additional contour"}
        if {[::GX::datasetPublicationV2DictDefault [dict get $model profiles $targetProfile] locked 0]} {error "The selected profile is locked"}
        if {[dict get $model profiles $targetProfile plane] ne $plane} {error "Additional contours must use the same captured working plane"}
    }
    set request [dict create dataset_id $sourceDataset x_variable_id $sourceX y_variable_id $sourceY]
    set schema [::GX::datasetVariableSchemaV3 $sourceDataset];set units {}
    foreach axis [list $sourceX $sourceY] {foreach variable $schema {if {[dict get $variable variable_id] eq $axis} {lappend units [dict get $variable unit];break}}}
    set working [dict get $model working_unit];set needsConversion 0;set emptyUnits 0
    foreach unit $units {if {$unit eq {}} {set emptyUnits 1} elseif {$unit ne $working} {set needsConversion 1;::GX::unitRegistryConversionPlan $unit $working}}
    if {$emptyUnits&&(!$assumeUnit||$needsConversion||[llength [lsort -unique $units]]!=1)} {error "Missing coordinate units: explicitly assume the working unit for both axes, or normalize the Dataset Schema first"}
    if {$needsConversion} {
        if {!$convertUnits} {error "Coordinate units differ from $working; enable explicit profile unit conversion"}
        dict set request transform_manifest [dict create api_version 1 operation convert_units sources [list [dict create dataset_id $sourceDataset variable_ids [list $sourceX $sourceY] x_variable_id $sourceX y_variable_id $sourceY]] output {} options [dict create target_units [dict create $sourceX $working $sourceY $working] include_lineage 1 lineage_prefix native3d_unit_]]
    }
    set source [::GX::curveSourceOpen $::GX::currentSession $request]
    try {
        set descriptor [::GX::curveSourceDescribe $source]
        set units [lmap variable [dict get $descriptor variables] {dict get $variable unit}]
        foreach unit $units {if {$unit ne $working&&!($unit eq {}&&$assumeUnit)} {error "Profile coordinate conversion did not produce the working unit $working"}}
        set receipt [::GX::native3DGeometryProfileFromSources $scene [list [dict create source_token $source closed $sourceClosed]] $plane 1e-8]
    } finally {::GX::curveSourceClose $source}
    if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Profile geometry owner changed during intake; reopen source selection"}
    set contours {};set bindings [dict get $receipt source_bindings]
    set previousToken {};set appendTarget {}
    foreach binding $bindings {lappend contours [dict create xy_resource [dict get $binding xy_resource] gap_resource [dict get $binding gap_resource] closed [dict get $binding closed]]}
    if {$append} {
        if {![dict exists $model profiles $targetProfile]} {error "Select a profile to receive the additional contour"}
        set prior [dict get $model profiles $targetProfile]
        if {[dict get $prior plane] ne $plane} {error "Additional contours must use the same captured working plane"}
        set contours [concat [dict get $prior contours] $contours];set bindings [concat [dict get $prior source_bindings] $bindings]
        set singleToken [dict get $receipt profile_token]
        try {set receipt [call profile [dict create contours $contours plane $plane tolerance 1e-8]]} finally {call profile_delete [dict create profile_token $singleToken]}
        set id $targetProfile;set appendTarget $id
        set previousToken [dict get $profileTokens $id]
        set record [dict merge $prior [dict create contours $contours source_bindings $bindings]]
    } else {
        set id {}
        set record [dict create contours $contours source_bindings $bindings plane $plane tolerance 1e-8 name $sourceDataset source_dataset_id $sourceDataset working_unit $working assumed_coordinate_unit [expr {$emptyUnits ? $working : {}}]]
    }
    try {
        dict set record display_geometry [::GX::native3DGeometryProfileViewResource $scene [dict get $receipt profile_token]]
    } on error {message options} {
        catch {call profile_delete [dict create profile_token [dict get $receipt profile_token]]}
        return -options $options $message
    }
    if {$id eq {}} {set id [nextId next_profile profile]}
    dict set model profiles $id $record
    dict set profileTokens $id [dict get $receipt profile_token];set profile $id
    try {
        commit $before profile_from_sources [dict create source_request $request plane $plane closed $sourceClosed tolerance 1e-8 append_to $appendTarget] $appendTarget [list $id]
    } on error {message options} {
        if {$previousToken ne {}} {dict set profileTokens $id $previousToken} else {dict unset profileTokens $id}
        set profile $priorActiveProfile
        catch {call profile_delete [dict create profile_token [dict get $receipt profile_token]]}
        return -options $options $message
    }
    if {$previousToken ne {} && [catch {call profile_delete [dict create profile_token $previousToken]} cleanup]} {
        set ::GX::Workbench3D::cleanupNotice "Accepted profile; previous native contour cleanup failed: $cleanup"
    }
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::cancelPreview {} {
    variable preview;variable module;variable provider
    if {$preview ne {}&&[dict exists $preview operation]&&[dict get $preview operation] eq "extrude_multi"} {tailcall cancelMultiExtrusion}
    if {$preview ne {}} {call delete [dict create object_token [dict get $preview receipt object_token]];set preview {}}
    if {"operation_preview" in [::GX::viewerLayerIds $module $provider]} {::GX::viewerLayerRemove $module $provider operation_preview}
}
proc ::GX::Workbench3D::extrudePreview {} {
    variable profile;variable profileTokens;variable distance;variable mode;variable target;variable tokens;variable preview;variable model
    if {$::GX::Workbench3D::extrusionTargets ne {}||$::GX::Workbench3D::keepExtrusionTool} {tailcall extrudeMultiPreview}
    if {![dict exists $profileTokens $profile]} {error "Load or select a validated closed profile"}
    set d [::GX::uiFieldNormalize {type number required 1} $distance]
    if {$mode ni {new join cut intersect}} {error "Choose New, Join, Cut or Intersect"}
    if {$mode ne "new"&&(![dict exists $tokens $target]||[dict get $model objects $target kind] ne "brep"||[dict get $model objects $target locked])} {error "Select an unlocked B-Rep target for $mode"}
    set tool [call extrude [dict create profile_token [dict get $profileTokens $profile] distance $d]]
    set result $tool
    try {
        if {$mode ne "new"} {set result [call boolean [dict create base [dict get $tokens $target] tool [dict get $tool object_token] mode $mode]]}
        if {![dict get $result topology_valid]||![dict get $result closed]} {error "Extrusion result is not a valid closed solid"}
        set record [snapshotObject $result]
        cancelPreview
        set preview [dict create receipt $result record $record scope_snapshot [::GX::native3DGeometrySceneInfo $::GX::Workbench3D::scene] profile_snapshot [dict get $model profiles $profile] parameters [dict create profile_id $profile distance $d mode $mode target $target]]
        renderResource [dict get $record display_geometry] operation_preview [dict create base_color {1;0.6;0.1} opacity .65]
    } on error {message options} {call delete [dict create object_token [dict get $result object_token]];return -options $options $message} finally {if {$mode ne "new"} {call delete [dict create object_token [dict get $tool object_token]]}}
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::acceptPreview {} {
    variable preview;variable model;variable tokens;variable nextName;variable selection;variable scene
    if {$preview eq {}} {error "Preview the extrusion first"}
    if {![dict exists $preview scope_snapshot]||[::GX::native3DGeometrySceneInfo $scene] ne [dict get $preview scope_snapshot]} {error "Geometry document changed after preview; review a new preview before accepting"}
    if {[dict exists $preview operation]&&[dict get $preview operation] eq "combine"} {tailcall acceptCombinePreview}
    if {[dict exists $preview operation]&&[dict get $preview operation] eq "extrude_multi"} {tailcall acceptMultiExtrusion}
    set before $model;set parameters [dict get $preview parameters];set priorTokens $tokens
    set replace [expr {[dict get $parameters mode] eq "new" ? {} : [dict get $parameters target]}]
    try {
        set id [installPreparedObject [dict get $preview receipt] [dict get $preview record] $nextName $replace]
        dict set model objects $id provenance [dict create operation extrude parameters $parameters profile_snapshot [dict get $preview profile_snapshot]]
        dict set model objects $id source_bindings [dict get $preview profile_snapshot source_bindings]
        if {$replace ne {}&&[dict get $before objects $replace group] ne {}} {structuralCommit $before extrude $parameters [list [dict get $parameters profile_id] $replace] [list $id] $priorTokens} else {commit $before extrude $parameters [list [dict get $parameters profile_id] $replace] [list $id]}
    } on error {message options} {set model $before;set tokens $priorTokens;return -options $options $message}
    set preview {};set selection [list $id];projectSelection
    if {$replace ne {}} {
        if {[dict get $before objects $replace group] eq {}} {committedCleanupDelete [list [dict get $priorTokens $replace]]}
    }
    if {"operation_preview" in [::GX::viewerLayerIds viewer.3d_workbench workbench_3d]} {::GX::viewerLayerRemove viewer.3d_workbench workbench_3d operation_preview}
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::createPrimitive {} {
    variable primitive;variable dimensions;variable radius;variable height;variable nextName;variable model;variable tokens;variable selection;variable panel
    set before $model;set priorTokens $tokens
    set request [expr {$primitive eq "box" ? [dict create lengths $dimensions] : [dict create radius $radius height $height]}]
    set receipt [call $primitive $request]
    try {set id [installObject $receipt $nextName];commit $before $primitive $request {} [list $id]} on error {message options} {
        set model $before;set tokens $priorTokens
        if {[catch {call delete [dict create object_token [dict get $receipt object_token]]} cleanup]} {append message "; temporary geometry cleanup failed: $cleanup"}
        return -options $options $message
    }
    selectionSet [list $id]
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::importDatasetForm {} {
    variable scene
    set choices {}
    foreach id [::GX::datasetRegistryIds] {if {[string tolower [::GX::datasetField $id format]] in {step stp stl obj vtp}} {lappend choices $id}}
    if {$choices eq {}} {error "The Session contains no STEP, STL, OBJ or VTP Dataset"}
    set fields [dict create dataset_id [dict create type choice label {Source Dataset ID} values $choices] input_unit [dict create type choice label {Input unit when mesh metadata has none} values {mm cm m in}] name [dict create type string label {Local object name} required 1]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.intake "Import Dataset as local geometry" $fields [dict create dataset_id [lindex $choices 0] input_unit mm name {Imported geometry}] [list ::GX::Workbench3D::importDatasetApply [::GX::native3DGeometrySceneInfo $scene]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::importDatasetApply {captured values} {
    variable scene;variable model;variable tokens;variable busy;variable selection;variable panel
    if {$busy} {error "Finish the current Workbench operation first"}
    if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Geometry document changed; reopen Dataset intake"}
    set busy 1;set before $model;set oldTokens $tokens;set receipt {}
    try {
        set receipt [::GX::native3DGeometryImportDataset $scene [dict get $values dataset_id] [dict get $model working_unit] [dict get $values input_unit]]
        set id [installObject $receipt [dict get $values name]]
        set binding [dict get $receipt dataset_binding]
        dict set model objects $id provenance [dict create operation import_dataset dataset_binding $binding kernel NATIVE_3D_GEOMETRY_API_v1]
        dict set model objects $id source_bindings [list [dict create source_descriptor [dict create source_kind dataset source_dataset_id [dict get $binding source_dataset_id] source_identities [list [dict create dataset_id [dict get $binding source_dataset_id] canonical_sha256 [dict get $binding source_sha256]]]] source_resource [dict get $binding source_resource]]]
        commit $before import_dataset $binding [list [dict get $values dataset_id]] [list $id]
    } on error {message options} {
        set model $before;set tokens $oldTokens
        if {$receipt ne {}&&[catch {call delete [dict create object_token [dict get $receipt object_token]]} cleanup]} {append message "; intake cleanup failed: $cleanup"}
        return -options $options $message
    } finally {set busy 0}
    set selection [list $id];projectSelection
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::selected {} {
    variable selection;variable model
    if {[llength $selection]!=1||![dict exists $model objects [lindex $selection 0]]} {error "Select exactly one accepted object"}
    set id [lindex $selection 0]
    if {[dict get $model objects $id locked]} {error "Object is locked"}
    return $id
}
proc ::GX::Workbench3D::deriveSelected {action parameters {replace 0} {render 1}} {
    variable model;variable tokens;variable selection
    set id [selected];set before $model
    dict set parameters object_token [dict get $tokens $id]
    set receipt [call $action $parameters];set priorTokens $tokens
    try {
        if {$replace&&$action ne "constraint_solve"} {set receipt [enforceConstraints $id $receipt]}
        set name [expr {$replace ? [dict get $model objects $id name] : "[dict get $model objects $id name] — $action"}]
        set result [installObject $receipt $name [expr {$replace ? $id : {}}]]
        dict set model objects $result source_bindings [::GX::datasetPublicationV2DictDefault [dict get $before objects $id] source_bindings {}]
        dict set model objects $result provenance [dict create operation $action parameters [dict remove $parameters object_token] source_object_id $id source_geometry [dict get $before objects $id geometry]]
        if {$replace&&[dict get $before objects $id group] ne {}} {structuralCommit $before $action [dict remove $parameters object_token] [list $id] [list $result] $priorTokens} else {commit $before $action [dict remove $parameters object_token] [list $id] [list $result]}
    } on error {message options} {set model $before;set tokens $priorTokens;call delete [dict create object_token [dict get $receipt object_token]];return -options $options $message}
    if {$replace} {
        if {[dict get $before objects $id group] eq {}} {committedCleanupDelete [list [dict get $priorTokens $id]]}
    }
    set selection [list $result];projectSelection
    if {$render} {::GX::Engine3D::rerender}
}
proc ::GX::Workbench3D::constraintSpecs {id} {
    variable model;variable tokens
    set result {}
    dict for {constraint record} [dict get $model constraints] {
        if {[dict get $record object_id] ne $id||![dict get $record enabled]} continue
        set spec [dict get $record specification]
        if {[dict exists $spec surface_object_id]} {dict set spec surface_object_token [dict get $tokens [dict get $spec surface_object_id]];dict unset spec surface_object_id}
        if {[dict exists $spec anchors]} {
            set anchors {};foreach anchor [dict get $spec anchors] {
                if {[dict exists $anchor object_id]} {dict set anchor object_token [dict get $tokens [dict get $anchor object_id]];dict unset anchor object_id}
                lappend anchors $anchor
            };dict set spec anchors $anchors
        }
        lappend result $spec
    }
    return $result
}
proc ::GX::Workbench3D::enforceConstraints {id receipt} {
    set specs [constraintSpecs $id]
    if {![llength $specs]} {return $receipt}
    set token [dict get $receipt object_token]
    set result [call constraint_solve [dict create object_token $token constraints $specs]]
    call delete [dict create object_token $token]
    return $result
}
proc ::GX::Workbench3D::constraintForm {} {
    variable constraintKind;variable model;variable scene
    set id [selected];set fields {};set values {}
    dict set fields kind [dict create type choice label {Constraint type} values {fixed coincident distance point_on_plane angle_lines parallel_lines perpendicular_lines point_on_line point_on_surface aligned_axes} default $constraintKind]
    dict set values kind $constraintKind
    foreach {key label value} {local_points {Local source points (three XYZ triples)} {{0 0 0} {1 0 0} {0 1 0}} world_points {World target points (three XYZ triples)} {{0 0 0} {1 0 0} {0 1 0}} surface_object_id {Surface mesh object ID} {} target {Distance or angle target (radians)} 0 tolerance {Tolerance in CORE constraint convention} 1e-8} {
        dict set fields $key [dict create type [expr {$key in {target tolerance} ? "number" : "string"}] label $label default $value];dict set values $key $value
    }
    dict set fields tolerance min 1e-300
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.constraint "Add constraint — $id ([dict get $model working_unit])" $fields $values [list ::GX::Workbench3D::purposeFormApply [::GX::native3DGeometrySceneInfo $scene] [list ::GX::Workbench3D::constraintApply $id]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::measurementForm {} {
    variable measurementKind;variable model;variable scene
    set id [selected]
    set fields [dict create kind [dict create type choice label Measurement values {distance delta_x delta_y delta_z angle distance_on_plane point_line_distance point_plane_distance line_line_angle line_plane_angle plane_plane_angle point_surface_distance} default $measurementKind] space [dict create type choice label {Point coordinate frame} values {world local} default world] points [dict create type string label {Up to four XYZ triples} default {{0 0 0} {1 0 0} {0 1 0} {0 0 1}}] surface_object_id [dict create type string label {Surface mesh object ID} default {}] plane2_origin [dict create type string label {Second plane origin (XYZ)} default {0 0 0}] plane2_normal [dict create type string label {Second plane normal (XYZ)} default {1 0 0}] plane2_u [dict create type string label {Second plane U axis (XYZ)} default {0 1 0}]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.measurement "Measure — $id ([dict get $model working_unit])" $fields {} [list ::GX::Workbench3D::purposeFormApply [::GX::native3DGeometrySceneInfo $scene] [list ::GX::Workbench3D::measurementApply $id]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::measurementApply {id values} {
    variable model;variable tokens;variable measurementKind;variable status
    set before $model;set kind [dict get $values kind];set measurementKind $kind
    set required [dict get {distance 2 delta_x 2 delta_y 2 delta_z 2 angle 3 distance_on_plane 2 point_line_distance 3 point_plane_distance 1 line_line_angle 4 line_plane_angle 2 plane_plane_angle 0 point_surface_distance 1} $kind]
    set points [dict get $values points]
    if {[llength $points]<$required} {error "This measurement requires $required points"}
    set anchors {}
    foreach point [lrange $points 0 [expr {$required-1}]] {
        if {$required==0} break
        if {[llength $point]!=3} {error "Each point needs three finite coordinates"};foreach value $point {::GX::uiFieldNormalize {type number required 1} $value}
        lappend anchors [dict create kind [expr {[dict get $values space] eq "local" ? "moving_point" : "world_point"}] point $point]
    }
    set request [dict create kind $kind anchors $anchors object_token [dict get $tokens $id]]
    if {$kind in {distance_on_plane point_plane_distance line_plane_angle plane_plane_angle}} {dict set request plane [dict create origin [split $::GX::Engine3D::planeOrigin {;}] normal [split $::GX::Engine3D::planeNormal {;}] u_axis [split $::GX::Engine3D::planeU {;}]]}
    if {$kind eq "plane_plane_angle"} {dict set request plane2 [dict create origin [dict get $values plane2_origin] normal [dict get $values plane2_normal] u_axis [dict get $values plane2_u]]}
    if {$kind eq "point_surface_distance"} {dict set request surface_object_token [dict get $tokens [dict get $values surface_object_id]]}
    set measured [call measure $request]
    set unit [expr {[string match *angle $kind] ? "rad" : [dict get $model working_unit]}]
    set result [nextId next_measurement measurement]
    set saved [dict remove $request object_token surface_object_token]
    if {$kind eq "point_surface_distance"} {dict set saved surface_object_id [dict get $values surface_object_id]}
    dict set model measurements $result [dict create object_id $id specification $saved value [dict get $measured value] unit $unit source_geometry [dict get $model objects $id geometry]]
    if {$kind eq "point_surface_distance"} {dict set model measurements $result source_surface_geometry [dict get $model objects [dict get $saved surface_object_id] geometry]}
    set view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d];set markers [dict get $view marker_definitions];set ids {};set index 0
    foreach anchor $anchors {
        set point [dict get [call anchor_describe [dict create object_token [dict get $tokens $id] anchor $anchor]] world_point]
        set marker "${result}_point[incr index]";lappend ids $marker
        lappend markers [dict create id $marker layer_id $id occurrence_index 0 local_point [join $point {;}] kind cross size_pixels 8 color {1;0.9;0.1} visible 1]
    }
    dict set view marker_definitions $markers
    if {$kind in {distance delta_x delta_y delta_z angle}} {
        set definition [dict create id $result kind $kind marker_a [lindex $ids 0] marker_b [lindex $ids 1] visible 1 show_value 1 color {1;0.95;0.2} size_pixels 7 line_width 2]
        if {$kind eq "angle"} {dict set definition marker_c [lindex $ids 2]}
        dict lappend view measurement_definitions $definition
    }
    ::GX::viewerSceneSet viewer.3d_workbench workbench_3d $view
    dict set model measurements $result marker_ids $ids
    commit $before measure [dict create measurement_id $result specification $saved] [list $id] [list $result]
    set status "$kind: [dict get $measured value] $unit"
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::measurementsPanel {} {
    variable model
    set window $::GX::Engine3D::window.measurements
    if {[winfo exists $window]} {destroy $window};toplevel $window;wm title $window Measurements
    ttk::treeview $window.list -columns {object kind value unit state} -show {tree headings} -selectmode extended
    $window.list heading #0 -text ID
    foreach key {object kind value unit state} {$window.list heading $key -text [string totitle $key];$window.list column $key -width 130}
    dict for {id record} [dict get $model measurements] {
        set object [dict get $record object_id];set state [measurementState $record]
        $window.list insert {} end -id $id -text $id -values [list $object [dict get $record specification kind] [dict get $record value] [dict get $record unit] $state]
    }
    pack $window.list -fill both -expand 1
    ttk::button $window.refresh -text "Refresh selected against current geometry" -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::refreshMeasurements $window]]
    ttk::button $window.delete -text "Delete selected measurements" -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::deleteMeasurements $window]]
    ttk::button $window.publish -text "Publish selected measurements as Dataset…" -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::measurementPublishForm $window]]
    pack $window.refresh $window.delete $window.publish -fill x
    ttk::label $window.explanation -text "Stale or missing measurements retain their previous value for inspection. Their markers stay hidden until a successful explicit refresh." -wraplength 600
    pack $window.explanation -fill x -padx 6 -pady 6
}
proc ::GX::Workbench3D::measurementPublishForm {window} {
    variable scene
    set ids [$window.list selection];if {$ids eq {}} {error "Select measurements to publish"}
    set captured [::GX::native3DGeometrySceneInfo $scene]
    set fields [dict create dataset_id [dict create type string label {Public Dataset name / ID} required 1] storage [dict create type choice label Storage values {auto csv hdf5} default auto]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.measurementPublication "Publish [llength $ids] measurement(s)" $fields {dataset_id measurement_report storage auto} [list ::GX::Workbench3D::measurementPublishApply $captured $ids] $window
}
proc ::GX::Workbench3D::measurementPublishApply {captured ids values} {
    variable scene;variable model;variable status;variable document
    if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Geometry document changed; reopen the publication form"}
    set requested [::GX::datasetPublicationV2RequestedId [dict get $values dataset_id] measurements]
    set commonUnit __unset__;set sourceIds {};set sourceFingerprints {};set expectedBytes 0
    foreach id $ids {
        if {![dict exists $model measurements $id]||[measurementState [dict get $model measurements $id]] ne "current"} {error "Measurement $id is stale or missing; refresh it explicitly before publication"}
        set unit [dict get $model measurements $id unit]
        incr expectedBytes [expr {512+2*[string bytelength [dict get $model measurements $id specification]]}]
        if {$commonUnit eq "__unset__"} {set commonUnit $unit} elseif {$commonUnit ne $unit} {set commonUnit ""}
        foreach binding [dict get $model objects [dict get $model measurements $id object_id] source_bindings] {
            if {![dict exists $binding source_descriptor]} continue
            set descriptor [dict get $binding source_descriptor]
            foreach identity [dict get $descriptor source_identities] {
                if {$identity ni $sourceFingerprints} {lappend sourceFingerprints $identity}
                if {[dict get $descriptor source_kind] in {dataset transform_view}&&[dict exists $identity dataset_id]} {
                    set source [dict get $identity dataset_id];if {$source ni $sourceIds} {lappend sourceIds $source}
                }
            }
        }
    }
    set definition [dict create dataset_id $requested contract table.generic storage [dict get $values storage] expected_rows [llength $ids] expected_bytes [expr {256*[llength $ids]}] producer_version [::GX::moduleField viewer.3d_workbench version] provenance "Explicit Native3D measurement inspection from $document at revision [dict get $captured revision]" structured_metadata [dict create dataset.display_name $requested inspection.kind native3d_measurements inspection.document_id $document inspection.document_revision [dict get $captured revision] inspection.value_units_column unit inspection.geometry_policy complete_native inspection.anchor_policy explicit_current_geometry inspection.source_dataset_id_policy none_unless_dataset_source]]
    dict set definition source_dataset_ids $sourceIds
    dict set definition expected_bytes $expectedBytes
    dict set definition structured_metadata inspection.source_fingerprints $sourceFingerprints
    dict set definition structured_metadata inspection.anchor_specification_encoding tcl_list_dict_data_v1
    dict set definition structured_metadata inspection.world_transform_encoding column_major_16_finite_numbers
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession viewer.3d_workbench $definition];set writer {}
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        foreach {key dtype label role} {measurement_index uint64 {Measurement ordinal} coordinate measurement_id string {Measurement ID} data object_id string {Geometry object ID} data kind string {Measurement kind} data value float64 {Measured value} data unit string {Value unit} data source_geometry_sha256 string {Captured geometry SHA-256} data anchor_specification string {Captured anchor specification} data world_transform string {Captured world affine coefficients} data} {
            set schema [dict create name $label dtype $dtype rank 1 dimension_ids row coordinate_role $role]
            if {$key eq "value"} {dict set schema unit $commonUnit}
            ::GX::datasetPublicationV2DeclareVariable $writer $key $schema
        }
        set data {};set ordinal 0;set chunk 0
        foreach id $ids {
            set record [dict get $model measurements $id]
            set placement [::GX::datasetPublicationV2DictDefault [dict get $record source_geometry metadata] transform {}]
            foreach {key value} [list measurement_index [incr ordinal] measurement_id $id object_id [dict get $record object_id] kind [dict get $record specification kind] value [dict get $record value] unit [dict get $record unit] source_geometry_sha256 [dict get $record source_geometry metadata geometry_sha256] anchor_specification [dict get $record specification] world_transform $placement] {dict lappend data $key $value}
            if {[incr chunk]==512} {::GX::datasetPublicationV2Append $writer row $data;set data {};set chunk 0}
        }
        if {$chunk} {::GX::datasetPublicationV2Append $writer row $data}
        if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Geometry document changed during publication"}
        set result [::GX::datasetPublicationV2Finalize $writer];set writer {}
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
    set status "Published measurement Dataset [dict get $result dataset_id]."
    return $result
}
proc ::GX::Workbench3D::measurementState {record} {
    variable model
    set id [dict get $record object_id]
    if {![dict exists $model objects $id]} {return missing}
    if {[dict get $record source_geometry] ne [dict get $model objects $id geometry]} {return stale}
    if {[dict exists $record specification surface_object_id]} {
        set surface [dict get $record specification surface_object_id]
        if {![dict exists $model objects $surface]} {return missing}
        if {![dict exists $record source_surface_geometry]||[dict get $record source_surface_geometry] ne [dict get $model objects $surface geometry]} {return stale}
    }
    return current
}
proc ::GX::Workbench3D::measurementPresentation {} {
    variable model;variable module;variable provider
    set view [::GX::viewerSceneGet $module $provider];set visibility {}
    dict for {id record} [dict get $model measurements] {
        set visible [expr {[measurementState $record] eq "current"}]
        dict set visibility $id $visible
        foreach marker [::GX::datasetPublicationV2DictDefault $record marker_ids {}] {dict set visibility $marker $visible}
    }
    foreach key {marker_definitions measurement_definitions} {
        set items {}
        foreach item [dict get $view $key] {
            if {[dict exists $visibility [dict get $item id]]} {dict set item visible [dict get $visibility [dict get $item id]]}
            lappend items $item
        }
        dict set view $key $items
    }
    ::GX::viewerSceneSet $module $provider $view
}
proc ::GX::Workbench3D::refreshMeasurements {window} {
    variable model;variable tokens;variable module;variable provider;variable status
    set ids [$window.list selection];if {$ids eq {}} {error "Select measurements to refresh"}
    set before $model;set oldView [::GX::viewerSceneGet $module $provider];dict set before view $oldView
    set after $model;set coordinates {}
    # Resolve every requested measurement first. A missing/invalid topology
    # anchor aborts the entire action without partially changing saved values.
    foreach id $ids {
        set record [dict get $model measurements $id];set object [dict get $record object_id]
        if {![dict exists $tokens $object]} {error "Measurement $id references missing object $object"}
        set request [dict get $record specification];dict set request object_token [dict get $tokens $object]
        if {[dict exists $request surface_object_id]} {
            set surface [dict get $request surface_object_id]
            if {![dict exists $tokens $surface]} {error "Measurement $id references missing surface $surface"}
            dict set request surface_object_token [dict get $tokens $surface];dict unset request surface_object_id
            dict set record source_surface_geometry [dict get $model objects $surface geometry]
        }
        set measured [call measure $request]
        dict set record value [dict get $measured value]
        dict set record unit [expr {[string match *angle [dict get $request kind]] ? "rad" : [dict get $model working_unit]}]
        dict set record source_geometry [dict get $model objects $object geometry]
        foreach anchor [dict get $request anchors] marker [::GX::datasetPublicationV2DictDefault $record marker_ids {}] {
            if {$marker eq {}} break
            dict set coordinates $marker [dict get [call anchor_describe [dict create object_token [dict get $tokens $object] anchor $anchor]] world_point]
        }
        dict set after measurements $id $record
    }
    set view $oldView;set markers {}
    foreach marker [dict get $view marker_definitions] {
        if {[dict exists $coordinates [dict get $marker id]]} {dict set marker local_point [join [dict get $coordinates [dict get $marker id]] {;}]}
        lappend markers $marker
    }
    dict set view marker_definitions $markers
    set model $after;::GX::viewerSceneSet $module $provider $view;measurementPresentation
    try {commit $before refresh_measurements [dict create measurement_ids $ids] {} $ids} on error {message options} {
        set model $before;::GX::viewerSceneSet $module $provider $oldView
        return -options $options $message
    }
    set status "Refreshed [llength $ids] measurement(s) against current native geometry."
    measurementsPanel;::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::deleteMeasurements {window} {
    variable model;variable module;variable provider
    set ids [$window.list selection];if {$ids eq {}} {error "Select measurements to delete"}
    set before $model;set oldView [::GX::viewerSceneGet $module $provider];dict set before view $oldView
    set removed $ids
    foreach id $ids {foreach marker [::GX::datasetPublicationV2DictDefault [dict get $model measurements $id] marker_ids {}] {lappend removed $marker};dict unset model measurements $id}
    set view $oldView
    foreach key {marker_definitions measurement_definitions} {dict set view $key [lmap item [dict get $view $key] {if {[dict get $item id] in $removed} continue;set item}]}
    ::GX::viewerSceneSet $module $provider $view
    try {commit $before delete_measurements [dict create measurement_ids $ids] {} {}} on error {message options} {
        set model $before;::GX::viewerSceneSet $module $provider $oldView
        return -options $options $message
    }
    measurementsPanel;::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::constraintApply {id values} {
    variable model;variable tokens;variable status;variable selection;variable constraintKind
    set before $model;set priorTokens $tokens;set kind [dict get $values kind];set constraintKind $kind
    set local [dict get $values local_points];set world [dict get $values world_points]
    if {[llength $local]!=3||[llength $world]!=3} {error "Enter three XYZ triples in both coordinate fields"}
    foreach point [concat $local $world] {if {[llength $point]!=3} {error "Each point needs three coordinates"};foreach value $point {::GX::uiFieldNormalize {type number required 1} $value}}
    set spec [dict create kind $kind tolerance [dict get $values tolerance]]
    switch -- $kind {
        fixed {dict set spec matrix [dict get [call describe [dict create object_token [dict get $tokens $id]]] world_transform]}
        coincident - distance {dict set spec local_point [lindex $local 0];dict set spec world_point [lindex $world 0];if {$kind eq "distance"} {dict set spec target [dict get $values target]}}
        point_on_plane {dict set spec local_point [lindex $local 0];dict set spec plane [dict create origin [split $::GX::Engine3D::planeOrigin {;}] normal [split $::GX::Engine3D::planeNormal {;}] u_axis [split $::GX::Engine3D::planeU {;}]]}
        point_on_surface {dict set spec anchors [list [dict create kind moving_point point [lindex $local 0]]];dict set spec surface_object_id [dict get $values surface_object_id]}
        point_on_line {dict set spec anchors [list [dict create kind moving_point point [lindex $local 0]] [dict create kind world_point point [lindex $world 0]] [dict create kind world_point point [lindex $world 1]]]}
        default {dict set spec anchors [list [dict create kind moving_point point [lindex $local 0]] [dict create kind moving_point point [lindex $local 1]] [dict create kind world_point point [lindex $world 0]] [dict create kind world_point point [lindex $world 1]]];if {$kind eq "angle_lines"} {dict set spec target [dict get $values target]}}
    }
    set constraint [nextId next_constraint constraint]
    dict set model constraints $constraint [dict create object_id $id specification $spec enabled 1 status pending residual {}]
    set receipt {}
    try {
        set receipt [call constraint_solve [dict create object_token [dict get $tokens $id] constraints [constraintSpecs $id]]]
        installObject $receipt [dict get $model objects $id name] $id
        dict set model constraints $constraint status [dict get $receipt constraint_status];dict set model constraints $constraint residual [dict get $receipt maximum_residual]
        if {[dict get $before objects $id group] ne {}} {structuralCommit $before constraint_solve [dict create constraint_id $constraint specification $spec] [list $id] [list $id] $priorTokens} else {commit $before constraint_solve [dict create constraint_id $constraint specification $spec] [list $id] [list $id]}
    } on error {message options} {set model $before;set tokens $priorTokens;if {$receipt ne {}} {call delete [dict create object_token [dict get $receipt object_token]]};return -options $options $message}
    if {[dict get $before objects $id group] eq {}} {committedCleanupDelete [list [dict get $priorTokens $id]]}
    set selection [list $id];projectSelection
    set status "Constraint residual [dict get $receipt maximum_residual]; [expr {[dict get $receipt constraint_status]==3 ? {satisfied, remaining degrees of freedom} : {satisfied}}]"
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::constraintsPanel {} {
    variable model
    set window $::GX::Engine3D::window.constraints
    if {[winfo exists $window]} {destroy $window};toplevel $window;wm title $window Constraints
    ttk::treeview $window.list -columns {object kind target status residual tolerance} -show {tree headings} -selectmode extended
    $window.list heading #0 -text ID
    foreach key {object kind target status residual tolerance} {$window.list heading $key -text [string totitle $key];$window.list column $key -width 125}
    dict for {id record} [dict get $model constraints] {set spec [dict get $record specification];$window.list insert {} end -id $id -text $id -values [list [dict get $record object_id] [dict get $spec kind] [::GX::datasetPublicationV2DictDefault $spec target {}] [dict get $record status] [dict get $record residual] [dict get $spec tolerance]]}
    pack $window.list -fill both -expand 1
    ttk::button $window.remove -text "Delete selected constraints" -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::deleteConstraints $window]];pack $window.remove -fill x
    ttk::button $window.edit -text "Edit target / tolerance…" -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::editConstraint $window]];pack $window.edit -fill x
    ttk::button $window.solve -text "Solve selected object's complete constraint set" -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::solveConstraints $window]];pack $window.solve -fill x
}
proc ::GX::Workbench3D::editConstraint {window} {
    variable model;variable scene
    set ids [$window.list selection];if {[llength $ids]!=1} {error "Select one constraint"};set id [lindex $ids 0]
    set record [dict get $model constraints $id];set spec [dict get $record specification]
    set fields [dict create tolerance [dict create type number label Tolerance min 1e-300 required 1] enabled [dict create type boolean label Enabled default 1]]
    set values [dict create tolerance [dict get $spec tolerance] enabled [dict get $record enabled]]
    if {[dict exists $spec target]} {dict set fields target [dict create type number label {Target (length or radians, according to type)} required 1];dict set values target [dict get $spec target]}
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.constraintEdit "Edit $id" $fields $values [list ::GX::Workbench3D::purposeFormApply [::GX::native3DGeometrySceneInfo $scene] [list ::GX::Workbench3D::editConstraintApply $id]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::editConstraintApply {id values} {
    variable model
    set before $model
    dict set model constraints $id specification tolerance [dict get $values tolerance]
    dict set model constraints $id enabled [dict get $values enabled]
    if {[dict exists $values target]} {dict set model constraints $id specification target [dict get $values target]}
    dict set model constraints $id status pending;dict set model constraints $id residual {}
    commit $before edit_constraint [dict create constraint_id $id values $values] {} {};constraintsPanel
}
proc ::GX::Workbench3D::solveConstraints {window} {
    variable model;variable tokens;variable selection
    set ids [$window.list selection];if {![llength $ids]} {error "Select a constraint"}
    set object [dict get $model constraints [lindex $ids 0] object_id];set selection [list $object]
    deriveSelected constraint_solve [dict create constraints [constraintSpecs $object]] 1
    set receipt [call describe [dict create object_token [dict get $tokens $object]]]
    # Store status only after the CORE solve/geometry checkpoint succeeded.
    dict for {id record} [dict get $model constraints] {if {[dict get $record object_id] eq $object&&[dict get $record enabled]} {dict set model constraints $id status evaluated;dict set model constraints $id residual [::GX::datasetPublicationV2DictDefault [dict get $model objects $object diagnostics] maximum_residual {}]}}
    checkpoint;constraintsPanel
}
proc ::GX::Workbench3D::deleteConstraints {window} {
    variable model
    set before $model;set ids [$window.list selection]
    foreach id $ids {dict unset model constraints $id}
    commit $before delete_constraints [dict create constraint_ids $ids] {} {};destroy $window;constraintsPanel
}
proc ::GX::Workbench3D::editForm {} {
    variable editAction;variable model;variable scene
    if {[string match group_* $editAction]} {selectedGroup} else {selected}
    set fields {};set values {}
    set action [string map {group_ {}} $editAction]
    switch -- $action {
        translate {set components {dx dy dz};set defaults {0 0 0}}
        rotate {set components {axis_x axis_y axis_z angle_deg pivot_x pivot_y pivot_z};set defaults {0 0 1 0 0 0 0}}
        scale {set components {factor_x factor_y factor_z pivot_x pivot_y pivot_z};set defaults {1 1 1 0 0 0}}
        weld - heal - self_intersections - mesh_heal_seam {set components {tolerance};set defaults {1e-8}}
        mesh_boundaries {set components {max_items max_vertices};set defaults {256 1024}}
        mesh_intersection_pairs {set components {tolerance max_items};set defaults {1e-8 256}}
        clip - clip_cap - section_profile {set components {origin_x origin_y origin_z normal_x normal_y normal_z u_x u_y u_z tolerance};set defaults {0 0 0 0 0 1 1 0 0 1e-8}}
        mesh {set components {linear_deflection angular_deflection weld_tolerance max_triangles max_output_bytes};set defaults {.01 .3 1e-8 1000000 134217728}}
        default {set components {};set defaults {}}
    }
    foreach component $components value $defaults {
        set label [string map {_ { }} $component]
        if {$component in {dx dy dz pivot_x pivot_y pivot_z origin_x origin_y origin_z tolerance linear_deflection weld_tolerance}} {append label " ([dict get $model working_unit])"} elseif {$component eq "angle_deg"} {append label " (degrees)"} elseif {$component eq "angular_deflection"} {append label " (radians)"} elseif {$component eq "max_output_bytes"} {append label " (bytes)"} elseif {$component eq "max_triangles"} {append label " (count)"} else {append label " (dimensionless)"}
        dict set fields $component [dict create type number label $label required 1 default $value];dict set values $component $value
    }
    if {$editAction eq "mesh"} {foreach key {max_triangles max_output_bytes} {dict set fields $key type integer;dict set fields $key min 1}}
    if {$editAction in {mesh_boundaries mesh_intersection_pairs}} {foreach key {max_items max_vertices} {if {[dict exists $fields $key]} {dict set fields $key type integer;dict set fields $key min 1;dict set fields $key max [expr {$key eq "max_items"?4096:65536}]}}}
    if {$editAction eq "mesh_lod"} {dict set fields level [dict create type choice label {Derived mesh resolution} values {preview low medium high full}];dict set values level low}
    if {$editAction eq "align_three_points"} {
        foreach key {local_points world_points} label {{Three local source points} {Three world target points}} {dict set fields $key [dict create type string label "$label ([dict get $model working_unit])" required 1];dict set values $key {{0 0 0} {1 0 0} {0 1 0}}}
        dict set fields tolerance [dict create type number label "Alignment tolerance ([dict get $model working_unit])" required 1 min 0];dict set values tolerance 1e-8
    }
    if {$editAction in {clip clip_cap}} {dict set fields keep_positive [dict create type boolean label {Keep positive side} default 1];dict set values keep_positive 1}
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.operation "[string totitle $editAction] — [dict get $model working_unit]" $fields $values [list ::GX::Workbench3D::purposeFormApply [::GX::native3DGeometrySceneInfo $scene] [list ::GX::Workbench3D::editApply $editAction]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::editApply {action values} {
    set grouped [string match group_* $action];set action [string map {group_ {}} $action]
    set parameters {}
    switch -- $action {
        translate {dict set parameters delta [list [dict get $values dx] [dict get $values dy] [dict get $values dz]]}
        rotate {dict set parameters axis [list [dict get $values axis_x] [dict get $values axis_y] [dict get $values axis_z]];dict set parameters pivot [list [dict get $values pivot_x] [dict get $values pivot_y] [dict get $values pivot_z]];dict set parameters radians [expr {[dict get $values angle_deg]*acos(-1)/180.0}]}
        scale {dict set parameters factors [list [dict get $values factor_x] [dict get $values factor_y] [dict get $values factor_z]];dict set parameters pivot [list [dict get $values pivot_x] [dict get $values pivot_y] [dict get $values pivot_z]]}
        clip - clip_cap - section_profile {dict set parameters plane [dict create origin [list [dict get $values origin_x] [dict get $values origin_y] [dict get $values origin_z]] normal [list [dict get $values normal_x] [dict get $values normal_y] [dict get $values normal_z]] u_axis [list [dict get $values u_x] [dict get $values u_y] [dict get $values u_z]]];dict set parameters tolerance [dict get $values tolerance];if {$action ne "section_profile"} {dict set parameters keep_positive [dict get $values keep_positive]}}
        default {set parameters $values}
    }
    if {$action eq "self_intersections"} {variable tokens;variable status;dict set parameters object_token [dict get $tokens [selected]];set status "[dict get [call self_intersections $parameters] intersecting_pairs] intersecting nonadjacent triangle pairs";return}
    if {$action eq "section_profile"} {sectionProfile $parameters;return}
    if {$action in {mesh_boundaries mesh_intersection_pairs}} {meshInspection $action $parameters;return}
    if {$grouped} {groupOperation $action $parameters} else {deriveSelected $action $parameters [expr {$action in {translate rotate scale reset_transform}}]}
}
proc ::GX::Workbench3D::selectedGroup {} {
    variable model;variable selection
    if {![llength $selection]} {error {Select a grouped object or members of one group}}
    set group {}
    foreach id $selection {
        if {![dict exists $model objects $id]} {error {Select accepted objects from one group}}
        set candidate [dict get $model objects $id group]
        if {$candidate eq {} || ![dict exists $model groups $candidate] || ($group ne {} && $candidate ne $group)} {error {Select accepted objects from one group}}
        set group $candidate
    }
    return $group
}
proc ::GX::Workbench3D::groupOperation {{action create} {parameters {}}} {
    variable model;variable tokens;variable selection;variable groupTokens;variable groupName
    if {![llength $selection]} {error "Select objects in the Workbench tree"}
    set ids $selection;set before $model;set priorTokens $tokens;set group {}
    if {$action ne "create"} {
        set group [selectedGroup]
        set ids [dict get $model groups $group members]
    }
    foreach id $ids {
        if {![dict exists $model objects $id]||[dict get $model objects $id locked]} {error "Groups require unlocked accepted objects"}
        if {$action eq "create"&&[dict get $model objects $id group] ne {}} {error "Ungroup objects before creating another group"}
        if {$action in {translate rotate scale}} {dict for {constraint record} [dict get $model constraints] {if {[dict get $record object_id] eq $id&&[dict get $record enabled]} {error "Group contains a constrained object; solve or remove its constraints before transforming the group"}}}
    }
    set originals [lmap id $ids {dict get $tokens $id}]
    if {$action eq "ungroup"} {
        foreach id $ids {dict set model objects $id group {}}
        dict unset model groups $group
        structuralCommit $before ungroup {} [list $group] $ids $priorTokens
        ::GX::Engine3D::rerender;return
    }
    dict set parameters object_tokens $originals
    if {$action in {translate rotate scale}} {dict set parameters transform_action $action} elseif {$action ni {create duplicate}} {error "Unsupported group action"}
    if {$action eq "duplicate"} {set receipt [call group_duplicate [dict create group_token [dict get $groupTokens $group]]]} else {set receipt [call group_copy $parameters]}
    set resultGroup $group;set newGroup [expr {$action in {create duplicate}}]
    if {$newGroup} {set resultGroup [nextId next_group group]}
    set results {}
    try {
        foreach id $ids member [dict get $receipt members] {
            set result [installObject $member [dict get $model objects $id name] [expr {$action eq "duplicate" ? {} : $id}]]
            dict set model objects $result group $resultGroup
            dict set model objects $result source_bindings [::GX::datasetPublicationV2DictDefault [dict get $before objects $id] source_bindings {}]
            dict set model objects $result provenance [dict create operation "group_$action" source_object_id $id source_geometry [dict get $before objects $id geometry]]
            lappend results $result
        }
        dict set model groups $resultGroup [dict create name $groupName members $results attrs {}]
        commit $before "group_$action" [dict remove $parameters object_tokens] $ids $results
    } on error {message options} {set model $before;set tokens $priorTokens;call group_delete [dict create group_token [dict get $receipt group_token]];return -options $options $message}
    set priorGroupToken {};if {$group ne {}&&[dict exists $groupTokens $group]} {set priorGroupToken [dict get $groupTokens $group]}
    # Publish the accepted Native ownership map before disposing predecessor
    # handles. Failed cleanup cannot retain an obsolete group as the live owner.
    dict set groupTokens $resultGroup [dict get $receipt group_token]
    if {$action ne "duplicate"} {
        set cleanup {}
        if {$priorGroupToken ne {}} {if {[catch {call group_delete [dict create group_token $priorGroupToken]} message]} {lappend cleanup $message}} else {foreach original $originals {if {[catch {call delete [dict create object_token $original]} message]} {lappend cleanup $message}}}
        if {$cleanup ne {}} {set ::GX::Workbench3D::cleanupNotice "Group action committed; predecessor cleanup failed: [join $cleanup {; }]"}
    }
    set selection $results;projectSelection
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::sectionProfile {parameters} {
    variable model;variable tokens;variable scene;variable profileTokens;variable profile
    set id [selected];set before $model;dict set parameters object_token [dict get $tokens $id]
    set receipt [call section_profile $parameters];set native [dict get $receipt profile_token];set result {}
    try {
        set resources [::GX::native3DGeometryProfileResources $scene $native]
        set view [::GX::native3DGeometryProfileViewResource $scene $native]
        set result [nextId next_profile profile]
        dict set model profiles $result [dict create contours [dict get $resources contours] plane [dict get $resources captured_plane] tolerance [dict get $parameters tolerance] working_unit [dict get $model working_unit] source_kind native3d_section source_object_id $id source_geometry [dict get $model objects $id geometry] source_bindings [dict get $model objects $id source_bindings] name "Section of [dict get $model objects $id name]" display_geometry $view]
        dict set profileTokens $result $native;set profile $result
        commit $before section_profile [dict remove $parameters object_token] [list $id] [list $result]
    } on error {message options} {set model $before;if {$result ne {}&&[dict exists $profileTokens $result]} {dict unset profileTokens $result};call profile_delete [dict create profile_token $native];return -options $options $message}
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::inspectSelected {} {
    variable tokens;variable status;variable model
    set info [call describe [dict create object_token [dict get $tokens [selected]]]]
    set status "[dict get $info kind]; area [dict get $info surface_area] [dict get $model working_unit]^2; volume [dict get $info volume] [dict get $model working_unit]^3 (defined [dict get $info volume_defined]); closed [dict get $info closed]"
    if {[dict exists $info boundary_edges]} {append status "; boundary edges [dict get $info boundary_edges]; nonmanifold [dict get $info nonmanifold_edges]; orientation conflicts [dict get $info orientation_conflicts]"}
}
proc ::GX::Workbench3D::convertWorkingUnit {} {
    variable requestedUnit;variable model;variable tokens;variable profileTokens;variable scene;variable module;variable provider
    set from [dict get $model working_unit];set to [string trim $requestedUnit]
    ::GX::unitRegistryConversionPlan $from $to;::GX::unitRegistryConversionPlan $to mm
    if {$from eq $to} return
    set factor [lindex [::GX::unitRegistryConvertCoordinates $from $to {1}] 0]
    set viewBefore [::GX::viewerSceneGet $module $provider];set viewAfter $viewBefore
    foreach key {camera_position camera_target working_plane_origin} {dict set viewAfter $key [join [::GX::unitRegistryConvertCoordinates $from $to [split [dict get $viewBefore $key] {;}]] {;}]}
    set before $model;dict set before view $viewBefore
    set priorTokens $tokens;set priorProfiles $profileTokens;set created {};set createdProfiles {};set toolsBefore {}
    foreach key {distance radius height dimensions} {dict set toolsBefore $key [set ::GX::Workbench3D::$key]}
    cancelPreview
    try {
        dict set model working_unit $to
        dict for {id record} [dict get $before objects] {
            set receipt [call rescale_coordinates [dict create object_token [dict get $priorTokens $id] factor $factor]]
            lappend created [dict get $receipt object_token]
            installObject $receipt [dict get $record name] $id
            dict set model objects $id provenance [dict create operation convert_working_unit source_unit $from target_unit $to factor $factor source_geometry [dict get $record geometry]]
        }
        dict for {id record} [dict get $before profiles] {
            set receipt [call profile_rescale [dict create profile_token [dict get $priorProfiles $id] factor $factor]];set profileToken [dict get $receipt profile_token];lappend createdProfiles $profileToken
            set resources [::GX::native3DGeometryProfileResources $scene $profileToken]
            dict set model profiles $id contours [dict get $resources contours];dict set model profiles $id plane [dict get $resources captured_plane]
            dict set model profiles $id tolerance [expr {[dict get $record tolerance]*$factor}];dict set model profiles $id working_unit $to
            dict set model profiles $id display_geometry [::GX::native3DGeometryProfileViewResource $scene $profileToken]
            dict set profileTokens $id $profileToken
        }
        dict for {id record} [dict get $before constraints] {
            set spec [dict get $record specification]
            foreach key {local_point world_point} {if {[dict exists $spec $key]} {dict set spec $key [::GX::unitRegistryConvertCoordinates $from $to [dict get $spec $key]]}}
            if {[dict exists $spec matrix]} {set matrix [dict get $spec matrix];set converted [::GX::unitRegistryConvertCoordinates $from $to [lrange $matrix 12 14]];set matrix [lreplace $matrix 12 14 {*}$converted];dict set spec matrix $matrix}
            if {[dict exists $spec anchors]} {set anchors {};foreach anchor [dict get $spec anchors] {if {[dict exists $anchor point]} {dict set anchor point [::GX::unitRegistryConvertCoordinates $from $to [dict get $anchor point]]};lappend anchors $anchor};dict set spec anchors $anchors}
            if {[dict exists $spec plane]} {dict set spec plane origin [::GX::unitRegistryConvertCoordinates $from $to [dict get $spec plane origin]]}
            if {[dict get $spec kind] eq "distance"} {dict set spec target [lindex [::GX::unitRegistryConvertCoordinates $from $to [list [dict get $spec target]]] 0]}
            if {[dict get $spec kind] ni {fixed angle_lines parallel_lines perpendicular_lines aligned_axes}} {dict set spec tolerance [expr {[dict get $spec tolerance]*$factor}]}
            dict set model constraints $id specification $spec
        }
        dict for {id record} [dict get $before measurements] {
            set spec [dict get $record specification];set anchors {}
            foreach anchor [dict get $spec anchors] {
                if {[dict exists $anchor point]} {dict set anchor point [::GX::unitRegistryConvertCoordinates $from $to [dict get $anchor point]]}
                lappend anchors $anchor
            }
            dict set spec anchors $anchors
            foreach key {plane plane2} {if {[dict exists $spec $key origin]} {dict set spec $key origin [::GX::unitRegistryConvertCoordinates $from $to [dict get $spec $key origin]]}}
            dict set model measurements $id specification $spec
            if {![string match *angle [dict get $spec kind]]} {
                dict set model measurements $id value [lindex [::GX::unitRegistryConvertCoordinates $from $to [list [dict get $record value]]] 0]
                dict set model measurements $id unit $to
            }
            # Keep the captured geometry reference: converted anchors remain
            # inspectable, but changed topology requires an explicit refresh.
        }
        dict for {id comparison} [::GX::datasetPublicationV2DictDefault $before comparisons {}] {
            foreach field {linear_deflection weld_tolerance section_tolerance} {if {[dict exists $comparison parameters $field]} {dict set model comparisons $id parameters $field [expr {[dict get $comparison parameters $field]*$factor}]}}
            if {[dict exists $comparison parameters plane_origin]} {dict set model comparisons $id parameters plane_origin [lmap component [dict get $comparison parameters plane_origin] {expr {$component*$factor}}]}
        }
        foreach key {distance radius height dimensions} {set ::GX::Workbench3D::$key [::GX::unitRegistryConvertCoordinates $from $to [dict get $toolsBefore $key]]}
        ::GX::viewerSceneSet $module $provider $viewAfter
        commit $before convert_working_unit [dict create source_unit $from target_unit $to factor $factor physical_scale 0] [dict keys [dict get $before objects]] [dict keys [dict get $model objects]]
    } on error {message options} {
        set model $before;set tokens $priorTokens;set profileTokens $priorProfiles
        ::GX::viewerSceneSet $module $provider $viewBefore
        dict for {key value} $toolsBefore {set ::GX::Workbench3D::$key $value}
        foreach token $created {call delete [dict create object_token $token]};foreach token $createdProfiles {call profile_delete [dict create profile_token $token]}
        return -options $options $message
    }
    foreach {field key} {cameraPosition camera_position cameraTarget camera_target planeOrigin working_plane_origin} {set ::GX::Engine3D::$field [dict get $viewAfter $key]}
    restore;::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::detailsForm {} {
    variable selection;variable model
    if {[llength $selection]!=1} {error "Select one object or profile"}
    set id [lindex $selection 0];set section [expr {[dict exists $model objects $id] ? "objects" : "profiles"}];set record [dict get $model $section $id]
    set fields [dict create name [dict create type string label Name required 1] visible [dict create type boolean label Visible default 1] locked [dict create type boolean label Locked default 0] color [dict create type color label {Line / surface color} alpha 1 default [dict create rgb #C7D1E6 alpha 1]] attributes [dict create type string label {Attributes (key/value dictionary)} default {}]]
    set style [::GX::datasetPublicationV2DictDefault $record style [dict create base_color {1;0.6;0.1} opacity 1]]
    set rgba [concat [split [dict get $style base_color] {;}] [list [dict get $style opacity]]]
    set values [dict create name [dict get $record name] visible [::GX::datasetPublicationV2DictDefault $record visible 1] locked [::GX::datasetPublicationV2DictDefault $record locked 0] color [::GX::uiFieldColorFromRGBA $rgba] attributes [::GX::datasetPublicationV2DictDefault $record attrs {}]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.details "Details — $id" $fields $values [list ::GX::Workbench3D::detailsApply $section $id] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::detailsApply {section id values} {
    variable model
    if {[catch {dict size [dict get $values attributes]}]} {error "Attributes must contain key/value pairs"}
    set before $model;set rgba [::GX::uiFieldColorToRGBA [dict get $values color]]
    foreach key {name visible locked} {dict set model $section $id $key [dict get $values $key]}
    dict set model $section $id attrs [dict get $values attributes]
    dict set model $section $id style base_color [join [lrange $rgba 0 2] {;}];dict set model $section $id style opacity [lindex $rgba 3]
    commit $before set_attributes [dict remove $values color] [list $id] [list $id];::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::hostEdit {action id fields} {
    variable model;variable tokens
    if {![dict exists $model objects $id]} {error "Select an accepted Workbench object"}
    if {[dict get $model objects $id locked]} {error "Object is locked"}
    set before $model
    if {$action eq "transform"} {
        set ::GX::Workbench3D::selection [list $id];dict set fields mode relative_world
        deriveSelected transform $fields 1 0
        return
    } elseif {$action eq "presentation"} {
        foreach key {base_color opacity representation} {if {[dict exists $fields $key]} {dict set model objects $id style $key [dict get $fields $key]}}
        if {[dict exists $fields visible]} {dict set model objects $id visible [dict get $fields visible]}
    } else {error "Unsupported shared-host edit '$action'"}
    commit $before $action [dict remove $fields object_token] [list $id] [list $id]
}
proc ::GX::Workbench3D::undoRedo {direction} {
    variable model;variable undo;variable redo;variable module;variable provider;variable scene
    variable tokens;variable profileTokens;variable groupTokens;variable cleanupNotice;variable selection
    if {$direction ni {undo redo}} {error "Unknown history direction"}
    if {![llength [set $direction]]} return
    set scope [::GX::native3DGeometrySceneInfo $scene]
    cancelPreview
    set before $model;set oldUndo $undo;set oldRedo $redo;set oldScene $scene
    set oldTokens $tokens;set oldProfiles $profileTokens;set oldGroups $groupTokens;set oldSelection $selection
    set oldView [::GX::viewerSceneGet $module $provider];set oldSettings {}
    foreach key {dataset x y distance mode target profile nextName primitive dimensions radius height resultId exportFormat editAction closedProfile includeProfile convertProfileUnits assumeProfileUnit extrusionTargets keepExtrusionTool requestedUnit} {dict set oldSettings $key [set ::GX::Workbench3D::$key]}
    if {$direction eq "undo"} {lappend redo $model;set model [lindex $undo end];set undo [lrange $undo 0 end-1]} else {lappend undo $model;set model [lindex $redo end];set redo [lrange $redo 0 end-1]}
    try {
        if {[dict exists $model tool_settings]} {dict for {key value} [dict get $model tool_settings] {if {[dict exists $oldSettings $key]} {set ::GX::Workbench3D::$key $value}}}
        set ::GX::Workbench3D::requestedUnit [dict get $model working_unit]
        # Keep the current retained scene alive until the complete replacement
        # has hydrated and the authoritative history write succeeds.
        restoreStage
        checkpoint
    } on error {message options} {
        if {$scene ne $oldScene&&$scene ne {}&&[catch {::GX::native3DGeometryClose $scene} cleanup]} {append message "; staged history cleanup failed: $cleanup"}
        set scene $oldScene;set tokens $oldTokens;set profileTokens $oldProfiles;set groupTokens $oldGroups
        set model $before;set undo $oldUndo;set redo $oldRedo;set selection $oldSelection
        dict for {key value} $oldSettings {set ::GX::Workbench3D::$key $value}
        if {[dict get $scope session_token] eq [::GX::interactiveDocumentSessionToken]} {
            ::GX::viewerSceneSet $module $provider $oldView
            if {[catch {refresh} rollback]} {append message "; history presentation rollback failed: $rollback"}
        }
        return -options $options $message
    }
    if {[catch {::GX::native3DGeometryClose $oldScene} cleanup]} {set cleanupNotice "history committed; previous scene cleanup failed: $cleanup"}
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::publish {} {
    variable exportFormat;variable resultId
    set requested [::GX::datasetPublicationV2RequestedId $resultId geometry]
    set context [geometryExportContext]
    dict set context parameters [dict create dataset_id $requested format $exportFormat]
    set result [::GX::workbenchExtensionInvoke export.native3d_geometry publish $context]
    set resultId $requested
    return $result
}

proc ::GX::Workbench3D::safe {script} {
    variable busy;variable status;variable cleanupNotice
    if {$busy} {set status "Finish or cancel the current operation";return}
    set busy 1
    set status Working
    set cleanupNotice {}
    try {set result [uplevel #0 $script];if {$status eq "Working"} {set status Ready};if {$cleanupNotice ne {}} {append status "; action committed, resource cleanup pending: $cleanupNotice"};return $result} on error {message options} {set status $message;tk_messageBox -parent $::GX::Engine3D::window -icon error -message $message} finally {set busy 0}
}
proc ::GX::Workbench3D::buildPanel {window} {
    variable panel;variable subscription
    set panel $window.side.scroll.controls.workbench
    ttk::labelframe $panel -text "3D Workbench — unpublished geometry" -padding 5
    pack $panel -before [lindex [pack slaves $window.side.scroll.controls] 0] -fill x -pady 5
    foreach {field label values} {dataset {Profile Dataset} {} x {X variable} {} y {Y variable} {} profile {Active profile} {} mode {Extrusion mode} {new join cut intersect} target {Target B-Rep} {} primitive {Primitive} {box cylinder} exportFormat {Publication format} {stl step vtp}} {
        ttk::label $panel.${field}Label -text $label
        ttk::combobox $panel.$field -textvariable ::GX::Workbench3D::$field -values $values -state readonly
        pack $panel.${field}Label $panel.$field -fill x
    }
    bind $panel.dataset <<ComboboxSelected>> ::GX::Workbench3D::datasetChoices
    foreach {field label} {distance {Signed extrusion distance} nextName {Object name} dimensions {Box dimensions (X Y Z)} radius {Cylinder radius} height {Cylinder height} resultId {Public Dataset ID}} {
        ttk::label $panel.${field}Label -text $label
        ttk::entry $panel.$field -textvariable ::GX::Workbench3D::$field
        pack $panel.${field}Label $panel.$field -fill x
    }
    ttk::treeview $panel.objects -columns {kind group visible locked} -show {tree headings} -selectmode extended -height 6
    $panel.objects heading #0 -text Object;$panel.objects column #0 -width 125
    foreach column {kind group visible locked} {$panel.objects heading $column -text [string totitle $column];$panel.objects column $column -width 62}
    pack $panel.objects -fill x
    bind $panel.objects <<TreeviewSelect>> [list set ::GX::Workbench3D::selection {}]
    bind $panel.objects <<TreeviewSelect>> +[list ::GX::Workbench3D::selectTree]
    foreach {key label} {closedProfile {Close profile endpoints explicitly} includeProfile {Add contour to active profile} convertProfileUnits {Convert profile units to working unit} assumeProfileUnit {Use working unit for undeclared axes}} {ttk::checkbutton $panel.$key -text $label -variable ::GX::Workbench3D::$key;pack $panel.$key -anchor w}
    ttk::label $panel.unitLabel -text "Working unit (physical geometry unchanged)";pack $panel.unitLabel -anchor w
    set units {};foreach unit {mm cm m in} {if {![catch {::GX::unitRegistryConvertCoordinates $unit mm {1}}]} {lappend units $unit}}
    ttk::combobox $panel.requestedUnit -textvariable ::GX::Workbench3D::requestedUnit -state readonly -values $units;pack $panel.requestedUnit -fill x
    ttk::button $panel.unitApply -text "Convert working coordinates" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::convertWorkingUnit];pack $panel.unitApply -fill x
    ttk::combobox $panel.editAction -textvariable ::GX::Workbench3D::editAction -state readonly -values {translate rotate scale reset_transform duplicate align_three_points mesh clean weld orient heal mesh_heal_seam mesh_lod mesh_boundaries mesh_intersection_pairs clip clip_cap self_intersections group_translate group_rotate group_scale section_profile}
    pack $panel.editAction -fill x
    ttk::entry $panel.groupName -textvariable ::GX::Workbench3D::groupName;pack $panel.groupName -fill x
    foreach {key label action} {group {Group selected} create duplicateGroup {Duplicate group} duplicate ungroup Ungroup ungroup} {ttk::button $panel.$key -text $label -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::groupOperation $action]];pack $panel.$key -fill x}
    foreach {key label action} {constraint {Add constraint…} constraintForm constraints {Inspect / delete constraints…} constraintsPanel} {ttk::button $panel.$key -text $label -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::$action]];pack $panel.$key -fill x}
    foreach {key label action} {measurement {Add measurement…} measurementForm measurements {Inspect measurements…} measurementsPanel} {ttk::button $panel.$key -text $label -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::$action]];pack $panel.$key -fill x}
    ttk::button $panel.texture -text {Managed image on picked face…} -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::textureForm];pack $panel.texture -fill x
    ttk::button $panel.textureClear -text {Remove selected object's image} -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::textureClear];pack $panel.textureClear -fill x
    ttk::button $panel.combine -text "Combine B-Rep bodies…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::combineForm]
    pack $panel.combine -fill x
    ttk::button $panel.intake -text "Import mesh / CAD Dataset…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::importDatasetForm];pack $panel.intake -fill x
    ttk::button $panel.meshPair -text "Append / merge / stitch / bridge meshes…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::meshPairForm];pack $panel.meshPair -fill x
    ttk::button $panel.extrusionTargets -text "Extrusion targets / keep tool…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::extrusionTargetsForm];pack $panel.extrusionTargets -fill x
    ttk::button $panel.details -text "Name / visibility / lock / attributes…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::detailsForm];pack $panel.details -fill x
    foreach {key label script} {planarSection {Edit section in Curve Workbench…} {::GX::Workbench3D::planarEditSelected section} planarProjection {Edit projection in Curve Workbench…} {::GX::Workbench3D::planarEditSelected projection} loadProfile {Load profile on working plane} {::GX::Workbench3D::loadProfile} primitiveGo {Create primitive} {::GX::Workbench3D::createPrimitive} preview {Preview extrusion} {::GX::Workbench3D::extrudePreview} accept {Accept preview} {::GX::Workbench3D::acceptPreview} cancel {Cancel preview} {::GX::Workbench3D::cancelPreview;::GX::Engine3D::rerender} edit {Edit / derive selected…} {::GX::Workbench3D::editForm} inspect {Inspect area / volume / diagnostics} {::GX::Workbench3D::inspectSelected} undo Undo {::GX::Workbench3D::undoRedo undo} redo Redo {::GX::Workbench3D::undoRedo redo} publish {Publish selected as Dataset…} {::GX::Workbench3D::publish} save {Save Workbench state} {::GX::Workbench3D::checkpoint}} {
        ttk::button $panel.$key -text $label -command [list ::GX::Workbench3D::safe $script];pack $panel.$key -fill x -pady 1
    }
    ttk::label $panel.status -textvariable ::GX::Workbench3D::status -wraplength 425;pack $panel.status -fill x
    bind $window <Escape> {::GX::Engine3D::showError {::GX::Engine3D::cancelGesture {::GX::Workbench3D::safe {::GX::Workbench3D::cancelPreview;::GX::Engine3D::rerender}}}}
    set subscription [::GX::datasetCatalogSubscribe ::GX::Workbench3D::datasetChoices]
    datasetChoices;refresh
}
proc ::GX::Workbench3D::selectTree {} {variable panel;variable selection;variable model;variable profile;set selection [$panel.objects selection];if {[llength $selection]==1} {set ::GX::Engine3D::selectedLayer [lindex $selection 0];if {[dict exists $model profiles [lindex $selection 0]]} {set profile [lindex $selection 0]}}}
proc ::GX::Workbench3D::hostSelection {pick} {
    variable panel;variable selection;variable model;variable status
    set id [dict get $pick layer_id]
    if {![dict exists $model objects $id]&&![dict exists $model profiles $id]} return
    selectionSet [list $id]
    set status "Selected $id at [dict get $pick world_point]"
}
proc ::GX::Workbench3D::close {} {
    variable scene;variable subscription;variable panel;variable preview
    if {$subscription ne {}} {::GX::datasetCatalogUnsubscribe $subscription;set subscription {}}
    if {$scene ne {}} {::GX::native3DGeometryClose $scene;set scene {}}
    set panel {};set preview {}
}
proc ::GX::Workbench3D::activateDocument {{context {}}} {
    variable module;variable provider;variable document;variable model;variable undo;variable redo;variable scene;variable allocationCounters;variable status;variable recoveryNotice
    if {$::GX::currentSession eq {}} {error "Open a Session first"}
    package require Tk
    set requested [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    set forceNew [expr {$requested eq {new}}]
    if {$forceNew} {set requested {}}
    if {$requested ne {}} {
        set requestedOwner [::GX::interactiveDocumentRead $requested]
        if {[dict get $requestedOwner module_id] ne $module || [dict get $requestedOwner provider_id] ne $provider || [dict get $requestedOwner format] ne "workbench3d.document.v1"} {error {Requested3D Workspace has another scientific owner}}
    }
    if {$scene ne {}} {
        if {$requested ne {} && $requested ne $document} {error {Close the active3D Workspace before opening another explicit identity}}
        if {$forceNew} {error {Close the active3D Workspace before creating another Document}}
        ::GX::native3DGeometrySceneInfo $scene
        return $document
    }
    if {[::GX::Engine3D::ownerModule] ne $module || [::GX::Engine3D::ownerProvider] ne $provider} {
        ::GX::Engine3D::configureHost $module $provider [dict create close ::GX::Workbench3D::close edit ::GX::Workbench3D::hostEdit selection ::GX::Workbench3D::hostSelection]
    }
    set recoveryNotice {}
    set docs [::GX::interactiveDocumentList $module $provider]
    if {!$forceNew && ($requested ne {} || [llength $docs])} {
        if {$requested ne {}} {set document $requested} else {set document [dict get [lindex $docs end] id]}
        set recovery [::GX::workbenchRecoveryPrompt $document .]
        if {[dict get $recovery status] eq "corrupt"} {set ::GX::Workbench3D::recoveryNotice "Recovery journal is corrupt; normal document remains available: [dict get $recovery reason]"}
        set payload [dict get [::GX::interactiveDocumentRead $document] payload];set model [dict get $payload model];set undo [dict get $payload undo];set redo [dict get $payload redo]
        set allocationCounters [::GX::datasetPublicationV2DictDefault $payload allocation_counters {}]
        # Upgrade older documents using every retained semantic snapshot.
        foreach snapshot [linsert [concat $undo $redo] 0 $model] {set allocationCounters [allocationMerge $allocationCounters $snapshot]}
    } else {
        set model [defaultModel];set undo {};set redo {};set allocationCounters {}
        set document [dict get [::GX::interactiveDocumentCreate $module $provider workbench3d.document.v1 1 [payload]] id]
    }
    set ::GX::Workbench3D::extrusionTargets {};set ::GX::Workbench3D::keepExtrusionTool 0
    if {[dict exists $model tool_settings]} {dict for {key value} [dict get $model tool_settings] {if {$key in {dataset x y distance mode target profile nextName primitive dimensions radius height resultId exportFormat editAction closedProfile includeProfile convertProfileUnits assumeProfileUnit extrusionTargets keepExtrusionTool}} {set ::GX::Workbench3D::$key $value}}}
    set ::GX::Workbench3D::requestedUnit [dict get $model working_unit]
    if {[dict get [::GX::workbenchRecoveryInspect $document] status] ne "corrupt"&&[catch {::GX::workbenchRecoveryBegin $document} recoveryMessage]} {set ::GX::Workbench3D::recoveryNotice "Recovery journal unavailable: $recoveryMessage"}
    restore
    set status [expr {$forceNew ? {New empty geometry Document.} : {Opened canonical geometry Document.}}]
    lifecycleAttach
    return $document
}
proc ::GX::Workbench3D::open {{context {}}} {
    variable module;variable provider;variable scene
    if {$scene ne {} && [winfo exists $::GX::Engine3D::window]} {
        activateDocument $context
        raise $::GX::Engine3D::window
        return $::GX::Engine3D::window
    }
    ::GX::Engine3D::configureHost $module $provider [dict create panel ::GX::Workbench3D::buildPanel close ::GX::Workbench3D::close edit ::GX::Workbench3D::hostEdit selection ::GX::Workbench3D::hostSelection]
    activateDocument $context
    return [::GX::Engine3D::backend open [::GX::viewerSceneResolve $module $provider]]
}
proc ::GX::Workbench3D::guiMount {parent {context {}}} {
    variable module;variable provider;variable panel;variable document;variable guiHost
    if {![winfo exists $parent]} {error {The declared editable3D viewport no longer exists}}
    # Configure before hydration: switching the existing editable owner can
    # close its prior geometry, and must never close newly activated state.
    set callbacks [dict create close ::GX::Workbench3D::close edit ::GX::Workbench3D::hostEdit selection ::GX::Workbench3D::hostSelection]
    ::GX::Engine3D::configureHost $module $provider $callbacks
    activateDocument $context
    set panel {}
    set mounted [::GX::native3DGuiHostMount $parent $module $provider $callbacks]
    set owner [::GX::interactiveDocumentRead $document]
    set guiHost [dict create parent $parent incarnation [winfo id $parent] session_token [::GX::interactiveDocumentSessionToken] document_id $document generation [dict get $owner generation]]
    # The component parent survives a planar handoff; the native child does not.
    # Forward changes to that stable presentation owner after every remount.
    bind $mounted <<GXWorkbench3DChanged>> [list event generate $parent <<GXWorkbench3DChanged>>]
    ::GX::Engine3D::backend open [::GX::viewerSceneResolve $module $provider]
    return $mounted
}
proc ::GX::Workbench3D::guiInspect {} {
    variable document;variable scene;variable model;variable selection;variable undo;variable redo;variable preview;variable busy;variable status;variable recoveryNotice
    if {$scene eq {}} {return [dict create status unbound owner viewer.3d_workbench/workbench_3d]}
    ::GX::native3DGeometrySceneInfo $scene
    set owner [::GX::interactiveDocumentRead $document]
    set objects {};set profiles {}
    dict for {id record} [dict get $model objects] {dict set objects $id [dict create name [dict get $record name] kind [dict get $record kind] visible [dict get $record visible] locked [dict get $record locked]]}
    dict for {id record} [dict get $model profiles] {dict set profiles $id [dict create name [dict get $record name] working_unit [dict get $record working_unit]]}
    return [dict create status ready owner viewer.3d_workbench/workbench_3d document_id $document generation [dict get $owner generation] revision [dict get $owner revision] sha256 [dict get $owner sha256] working_unit [dict get $model working_unit] objects $objects profiles $profiles selected $selection undo_count [llength $undo] redo_count [llength $redo] preview_pending [expr {$preview ne {}}] busy $busy message $status recovery_notice $recoveryNotice]
}
proc ::GX::Workbench3D::selectionSet ids {
    variable scene;variable model;variable selection;variable tokens
    if {$scene eq {}} {error {Open an actual3D Workspace first}}
    ::GX::native3DGeometrySceneInfo $scene
    if {[llength $ids]!=[llength [lsort -unique $ids]]} {error {Selection requires distinct canonical object/profile identities}}
    foreach id $ids {
        if {![dict exists $model objects $id] && ![dict exists $model profiles $id]} {error {Selected3D object/profile no longer exists}}
        if {![organizationSelectable $id]} {error {Object is not selectable in its Layer}}
    }
    set members {}
    foreach id $ids {
        if {[dict exists $model objects $id]} {lappend members [dict create object_token [dict get $tokens $id]]}
    }
    # Use the same current-member authority as named Selection Sets. Profiles
    # remain valid Workbench selections without masquerading as native bodies.
    call selection_set_apply [dict create members $members mode replace]
    set selection $ids
    projectSelection
    return [guiInspect]
}
proc ::GX::Workbench3D::selectionApply {ids {mode replace}} {
    variable selection;variable model;variable tokens
    if {$mode ni {replace add subtract}} {error {Selection mode must be replace, add or subtract}}
    if {[llength $ids]!=[llength [lsort -unique $ids]]} {error {Selection requires distinct canonical identities}}
    if {$mode eq {replace}} {return [selectionSet $ids]}
    set wanted $selection;set members {}
    foreach id $ids {
        if {![dict exists $model objects $id] && ![dict exists $model profiles $id]} {error {Selected3D object/profile no longer exists}}
        if {![organizationSelectable $id]} {error {Object is not selectable in its Layer}}
        if {[dict exists $model objects $id]} {lappend members [dict create object_token [dict get $tokens $id]]}
        set index [lsearch -exact $wanted $id]
        if {$mode eq {add} && $index<0} {lappend wanted $id
        } elseif {$mode eq {subtract} && $index>=0} {set wanted [lreplace $wanted $index $index]}
    }
    set receipt [call selection_set_apply [dict create members $members mode $mode]]
    set profiles [lmap id $wanted {if {![dict exists $model profiles $id]} continue;set id}]
    set selection [concat [selectionMemberObjects [dict get $receipt selected_members]] $profiles]
    projectSelection
    return [guiInspect]
}
proc ::GX::Workbench3D::selectionMemberObjects {members} {
    variable tokens
    set reverse {};dict for {id token} $tokens {dict set reverse $token $id}
    set result {}
    foreach member $members {
        set token [dict get $member object_token]
        if {![dict exists $reverse $token]} {error {Selection member is outside the current canonical Workbench}}
        set id [dict get $reverse $token]
        if {$id ni $result} {lappend result $id}
    }
    return $result
}
proc ::GX::Workbench3D::guiCommand {action {values {}}} {
    variable scene;variable busy;variable primitive;variable dimensions;variable radius;variable height;variable nextName;variable status;variable cleanupNotice
    if {$scene eq {}} {error {Open an actual3D Workspace first}}
    if {$busy || $::GX::Engine3D::workerBusy} {error {Finish or cancel the active3D operation first}}
    ::GX::native3DGeometrySceneInfo $scene
    if {$action eq {primitive}} {
        if {[lsort [dict keys $values]] ne [lsort {primitive dimensions radius height name}]} {error {Primitive form requires kind, dimensions, radius, height and name}}
        if {[dict get $values primitive] ni {box cylinder}} {error {Choose the existing exact box or cylinder primitive}}
        set kind [dict get $values primitive]
        if {$kind eq {box}} {
            set lengths [dict get $values dimensions]
            if {[llength $lengths]!=3} {error {A box requires three positive lengths in the working unit}}
            foreach value $lengths {if {[::GX::uiFieldNormalize {type number min 0} $value]<=0} {error {Box lengths must be positive in the working unit}}}
        } else {
            foreach key {radius height} {if {[::GX::uiFieldNormalize {type number min 0} [dict get $values $key]]<=0} {error {Cylinder radius and height must be positive in the working unit}}}
        }
        set name [::GX::uiFieldNormalize {type string required 1} [dict get $values name]]
        set primitive $kind;set dimensions [dict get $values dimensions];set radius [dict get $values radius];set height [dict get $values height];set nextName $name
        createPrimitive
    } else {
        if {$values ne {}} {error {This3D command accepts no extra parameters}}
        switch -- $action {
            inspect {inspectSelected}
            save {saveExplicit}
            undo - redo {undoRedo $action}
            close {::GX::Engine3D::close}
            default {
                if {$action ni [guiFormCommands]} {error {This finite3D host command is not implemented; request its existing-owner binding}}
                guiForm $action
            }
        }
    }
    set inspection [guiInspect]
    if {$action in {preview_accept preview_cancel undo redo}} {
        # This shared host route bypasses the legacy panel's safe/Working
        # wrapper. Project the successful current state instead of retaining
        # the old preview's instruction to Accept, or its unchanged-body claim.
        set outcome [dict get [dict create preview_accept {Preview accepted} preview_cancel {Preview cleared} undo Undo redo Redo] $action]
        set status "$outcome; current document revision [dict get $inspection revision]."
        if {[dict get $inspection preview_pending]} {append status { An operation preview remains pending.}}
        if {$cleanupNotice ne {}} {append status "; resource cleanup pending: $cleanupNotice"}
        dict set inspection message $status
        guiPresentationChanged
    }
    return $inspection
}

proc ::GX::Workbench3D::dispatch {action scene} {
    if {$action eq "rerender"} {return [::GX::Engine3D::backend rerender $scene]}
    if {$action ne "open"} {error "Unsupported 3D Workbench action"}
    return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]
}
source [file join [file dirname [info script]] workbench_3d_combine_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_mesh_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_extrusion_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_recovery_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_lifecycle_v1.tcl]
::GX::viewerBackendRegister workbench_3d_native ::GX::Workbench3D::dispatch

source [file join [file dirname [info script]] workbench_3d_structural_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_extensions_recipe_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_organization_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_comparison_v1.tcl]

source [file join [file dirname [info script]] workbench_3d_planar_return.tcl]
source [file join [file dirname [info script]] workbench_3d_texture_v1.tcl]
source [file join [file dirname [info script]] workbench_3d_builder_forms_v1.tcl]
