# SPDX-License-Identifier: GPL-3.0-or-later
# Finite public presentation routes to this existing scientific owner. The
# original purpose forms retain callbacks, source captures and commit guards.
proc ::GX::Workbench3D::guiPresentationChanged {} {
    if {[llength [info commands winfo]] && [winfo exists $::GX::Engine3D::window]} {
        event generate $::GX::Engine3D::window <<GXWorkbench3DChanged>> -when tail
    }
}
proc ::GX::Workbench3D::guiFormCommands {} {
    return {import_dataset_form combine_form extrusion_targets_form mesh_pair_form
        details_form measurement_form constraint_form measurements_manager
        constraints_manager organization_manager comparison_manager texture_form
        texture_clear export_form recipe_manager extensions_manager documents_manager
        translate_form rotate_form scale_form reset_transform_form tessellate_form
        mesh_clean_form mesh_weld_form mesh_orient_form brep_heal_form
        mesh_seam_form mesh_lod_form mesh_boundaries_form mesh_intersections_form
        align_three_points_form clip_form clip_cap_form section_profile_form
        duplicate_object group_create group_duplicate group_ungroup group_translate_form
        group_rotate_form group_scale_form planar_section planar_projection
        preview_accept preview_cancel profile_source_form extrusion_form
        working_unit_form working_plane_form publish_dataset_form}
}
proc ::GX::Workbench3D::guiForm {action} {
    variable editAction
    if {$action ni [guiFormCommands]} {error {Unknown finite Workbench3D form}}
    switch -- $action {
        import_dataset_form {importDatasetForm}
        combine_form {combineForm}
        extrusion_targets_form {extrusionTargetsForm}
        mesh_pair_form {meshPairForm}
        details_form {detailsForm}
        measurement_form {measurementForm}
        constraint_form {constraintForm}
        measurements_manager {measurementsPanel}
        constraints_manager {constraintsPanel}
        organization_manager {organizationPanel}
        comparison_manager {comparisonPanel}
        texture_form {textureForm}
        texture_clear {textureClear}
        export_form {geometryExportOpen}
        recipe_manager {
            ::GX::scientificRecipeDialog $::GX::Engine3D::window.recipe \
                viewer.3d_workbench ::GX::Workbench3D::extensionContext $::GX::Engine3D::window
        }
        extensions_manager {
            ::GX::workbenchExtensionActionDialog $::GX::Engine3D::window.extensions \
                ::GX::Workbench3D::extensionContext $::GX::Engine3D::window
        }
        documents_manager {::GX::interactiveDocumentManagerDialog $::GX::Engine3D::window}
        profile_source_form {profileSourceForm}
        extrusion_form {extrusionForm}
        working_unit_form {workingUnitForm}
        working_plane_form {workingPlaneForm}
        publish_dataset_form {publishDatasetForm}
        group_create {groupOperation create}
        duplicate_object {deriveSelected duplicate {}}
        group_duplicate {groupOperation duplicate}
        group_ungroup {groupOperation ungroup}
        planar_section {planarEditSelected section}
        planar_projection {planarEditSelected projection}
        preview_accept {acceptPreview}
        preview_cancel {cancelPreview;::GX::Engine3D::rerender}
        default {
            # Names are fixed by the existing operation catalog; no author
            # supplied Tcl command, callback, payload or native handle is used.
            set actions [dict create \
                translate_form translate rotate_form rotate scale_form scale \
                reset_transform_form reset_transform tessellate_form mesh \
                mesh_clean_form clean mesh_weld_form weld mesh_orient_form orient \
                brep_heal_form heal mesh_seam_form mesh_heal_seam \
                mesh_lod_form mesh_lod mesh_boundaries_form mesh_boundaries \
                mesh_intersections_form mesh_intersection_pairs \
                align_three_points_form align_three_points clip_form clip \
                clip_cap_form clip_cap section_profile_form section_profile \
                group_translate_form group_translate group_rotate_form group_rotate \
                group_scale_form group_scale]
            set editAction [dict get $actions $action]
            editForm
        }
    }
}

# The finite forms below expose existing owner operations independently of the
# retired whole settings panel. Every delayed Apply retains the native scene
# identity/revision and any scientific source/working-plane capture it uses.
proc ::GX::Workbench3D::purposeFormGuard {captured} {
    variable scene;variable busy;variable module;variable provider
    if {$scene eq {} || $busy || $::GX::Engine3D::workerBusy} {error {Finish or cancel the active 3D operation first}}
    if {[::GX::Engine3D::ownerModule] ne $module || [::GX::Engine3D::ownerProvider] ne $provider ||
        [::GX::native3DGeometrySceneInfo $scene] ne $captured} {error {Geometry document changed; reopen this form}}
}
proc ::GX::Workbench3D::purposeFormApply {captured callback values} {
    # Delayed coordinates and targets belong to the scene/unit displayed when
    # the form opened. Reuse its existing guard before any semantic mutation.
    purposeFormGuard $captured
    return [uplevel #0 [list {*}$callback $values]]
}
proc ::GX::Workbench3D::profileSourceForm {} {
    variable scene
    set choices {}
    foreach id [::GX::datasetRegistryIds] {
        set variables 0
        foreach v [::GX::datasetVariableSchemaV3 $id] {
            if {[dict get $v enabled] && [dict get $v value_kind] eq {number} && [dict get $v rank]==1} {incr variables}
        }
        if {$variables>=2} {lappend choices $id}
    }
    if {$choices eq {}} {error {The Session has no Dataset with two enabled numerical coordinate variables}}
    set fields [dict create dataset_id [dict create type choice label {Canonical coordinate Dataset} values $choices]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.profileSource {Profile from scientific coordinates — choose source} \
        $fields [dict create dataset_id [lindex $choices 0]] \
        [list ::GX::Workbench3D::profileCoordinatesForm [::GX::native3DGeometrySceneInfo $scene]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::profileCoordinatesForm {captured values} {
    variable model
    purposeFormGuard $captured
    set id [dict get $values dataset_id];set choices {}
    foreach v [::GX::datasetVariableSchemaV3 $id] {
        if {[dict get $v enabled] && [dict get $v value_kind] eq {number} && [dict get $v rank]==1} {lappend choices [dict get $v variable_id]}
    }
    if {[llength $choices]<2} {error {The selected Dataset no longer has two enabled numerical coordinate variables}}
    set identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $id]
    set view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d]
    set plane [list [dict get $view working_plane_origin] [dict get $view working_plane_normal] [dict get $view working_plane_u_axis]]
    set fields [dict create \
        x [dict create type choice label {X coordinate variable ID} values $choices] \
        y [dict create type choice label {Y coordinate variable ID} values $choices] \
        closed [dict create type boolean label {Interpret the contour as closed}] \
        append_to [dict create type choice label {New profile or append a contour to this captured plane} values [linsert [dict keys [dict get $model profiles]] 0 new]] \
        convert [dict create type boolean label {Explicitly convert declared coordinate units to the working unit}] \
        assume [dict create type boolean label {For two unitless axes only: explicitly assume the working unit}]]
    set initial [dict create x [lindex $choices 0] y [lindex $choices 1] closed 1 append_to new convert 1 assume 0]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.profileCoordinates "Profile: $id — [dict get $model working_unit]" \
        $fields $initial [list ::GX::Workbench3D::profileSourceApply $captured $id $identity $plane] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::profileSourceApply {captured id identity plane values} {
    variable dataset;variable x;variable y;variable closedProfile;variable includeProfile
    variable profile;variable convertProfileUnits;variable assumeProfileUnit
    purposeFormGuard $captured
    if {[::GX::curveSourceDatasetIdentity $::GX::currentSession $id] ne $identity} {error {Profile Dataset payload or scientific schema changed; reopen source selection}}
    set view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d]
    if {[list [dict get $view working_plane_origin] [dict get $view working_plane_normal] [dict get $view working_plane_u_axis]] ne $plane} {error {Working plane changed; reopen profile coordinates}}
    if {[dict get $values x] eq [dict get $values y]} {error {Select two distinct canonical coordinate variable IDs}}
    set previous {}
    foreach field {dataset x y closedProfile includeProfile profile convertProfileUnits assumeProfileUnit} {dict set previous $field [set $field]}
    try {
        set dataset $id;set x [dict get $values x];set y [dict get $values y]
        set closedProfile [dict get $values closed];set includeProfile [expr {[dict get $values append_to] ne {new}}]
        if {$includeProfile} {set profile [dict get $values append_to]}
        set convertProfileUnits [dict get $values convert];set assumeProfileUnit [dict get $values assume]
        loadProfile
    } on error {message options} {
        # A rejected intake must not leave failed form choices as the active
        # tool state. Do not alter a replaced owner or undo an accepted commit
        # merely because its subsequent presentation reported an error.
        if {![catch {::GX::native3DGeometrySceneInfo $::GX::Workbench3D::scene} current] && $current eq $captured} {
            dict for {field prior} $previous {set $field $prior}
        }
        return -options $options $message
    }
    projectSelection
}
proc ::GX::Workbench3D::extrusionForm {} {
    variable scene;variable model;variable profile;variable distance;variable mode;variable target;variable nextName
    set profiles [dict keys [dict get $model profiles]]
    if {$profiles eq {}} {error {Create a validated profile before extrusion}}
    set targets {};dict for {id record} [dict get $model objects] {if {[dict get $record kind] eq {brep} && ![dict get $record locked]} {lappend targets $id}}
    set fields [dict create \
        profile [dict create type choice label {Canonical profile ID} values $profiles] \
        distance [dict create type number required 1 label "Signed extrusion distance ([dict get $model working_unit])"] \
        mode [dict create type choice label {Operation (Join/Cut/Intersect require a target)} values {new join cut intersect}] \
        target [dict create type choice label {Main target (multi-target settings remain separate)} values [linsert $targets 0 none]] \
        name [dict create type string required 1 label {Accepted new body name}]]
    set initial [dict create profile [expr {$profile in $profiles?$profile:[lindex $profiles 0]}] distance $distance mode $mode \
        target [expr {$target in $targets?$target:{none}}] name $nextName]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.extrusion "Preview extrusion — [dict get $model working_unit]" \
        $fields $initial [list ::GX::Workbench3D::extrusionFormApply [::GX::native3DGeometrySceneInfo $scene]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::extrusionFormApply {captured values} {
    variable profile;variable distance;variable mode;variable target;variable nextName;variable status
    purposeFormGuard $captured
    set profile [dict get $values profile];set distance [dict get $values distance]
    set mode [dict get $values mode];set target [dict get $values target];set nextName [dict get $values name]
    extrudePreview
    set status {Extrusion preview ready; inspect it, then Accept or Cancel preview.}
    guiPresentationChanged
}
proc ::GX::Workbench3D::workingUnitForm {} {
    variable scene;variable model
    set choices {};set from [dict get $model working_unit]
    foreach unit [::GX::unitRegistryList] {
        if {![catch {::GX::unitRegistryConversionPlan $from $unit;::GX::unitRegistryConversionPlan $unit mm}]} {lappend choices $unit}
    }
    set fields [dict create unit [dict create type choice label {Convert coordinates, geometry and length-valued settings; physical size stays the same} values $choices]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.workingUnit "Convert working unit from $from (not geometric scaling)" \
        $fields [dict create unit $from] [list ::GX::Workbench3D::workingUnitApply [::GX::native3DGeometrySceneInfo $scene]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::workingUnitApply {captured values} {
    variable requestedUnit
    purposeFormGuard $captured
    set requestedUnit [dict get $values unit]
    convertWorkingUnit
}
proc ::GX::Workbench3D::workingPlaneForm {} {
    variable scene;variable model
    set view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d]
    set fields [dict create \
        origin [dict create type string required 1 label "Origin x;y;z ([dict get $model working_unit])"] \
        normal [dict create type string required 1 label {Normal vector x;y;z (dimensionless)}] \
        u_axis [dict create type string required 1 label {In-plane U direction x;y;z (dimensionless)}] \
        visible [dict create type boolean label {Show working plane}]]
    set initial [dict create origin [dict get $view working_plane_origin] normal [dict get $view working_plane_normal] \
        u_axis [dict get $view working_plane_u_axis] visible [dict get $view working_plane_visible]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.workingPlane {Working plane for new profiles and sections} \
        $fields $initial [list ::GX::Workbench3D::workingPlaneApply [::GX::native3DGeometrySceneInfo $scene] $initial] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::workingPlaneApply {captured prior values} {
    purposeFormGuard $captured
    set view [::GX::viewerSceneGet viewer.3d_workbench workbench_3d]
    foreach {field key} {origin working_plane_origin normal working_plane_normal u_axis working_plane_u_axis visible working_plane_visible} {
        if {[dict get $view $key] ne [dict get $prior $field]} {error {Working plane changed; reopen this form}}
    }
    ::GX::Engine3D::setWorkingPlane [dict get $values origin] [dict get $values normal] [dict get $values u_axis] [dict get $values visible]
    guiPresentationChanged
}
proc ::GX::Workbench3D::publishDatasetForm {} {
    variable scene;variable resultId;variable exportFormat
    set context [geometryExportContext]
    set object [dict get $context presentation_snapshot object]
    set formats [expr {[dict get $object kind] eq {brep}?{step stl vtp}:{stl vtp}}]
    set fields [dict create \
        dataset_id [dict create type string required 1 label {New canonical Dataset ID (existing IDs are preserved)}] \
        format [dict create type choice label {Complete geometry format; mesh formats use the existing tessellation policy} values $formats]]
    set initial [dict create dataset_id [::GX::datasetPublicationV2RequestedId $resultId geometry] \
        format [expr {$exportFormat in $formats?$exportFormat:[lindex $formats 0]}]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.publishDataset "Publish [dict get $object name] as a canonical Dataset" \
        $fields $initial [list ::GX::Workbench3D::publishDatasetApply [::GX::native3DGeometrySceneInfo $scene] [dict get $context presentation_snapshot object_id]] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::publishDatasetApply {captured id values} {
    variable resultId;variable exportFormat;variable status
    purposeFormGuard $captured
    if {[selected] ne $id} {error {Selected geometry changed; reopen the publication form}}
    set resultId [dict get $values dataset_id];set exportFormat [dict get $values format]
    set receipt [publish]
    set status "Published canonical Dataset: [dict get $receipt created_ids]"
    guiPresentationChanged
    return $receipt
}
