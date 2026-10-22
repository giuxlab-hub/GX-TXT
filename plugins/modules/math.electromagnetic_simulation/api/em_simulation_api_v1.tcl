# Native domain adapter; all Job, resource, Dataset and Workspace state remains
# with the existing public CORE authorities. GPL-3.0-or-later.
namespace eval ::GX::ElectromagneticSimulation {
    variable moduleId math.electromagnetic_simulation
    variable root [file normalize [file join [file dirname [info script]] ..]]
    variable provider math.electromagnetic_simulation.fem2d
}
proc ::GX::ElectromagneticSimulation::_native {operation args} {
    variable root
    if {![llength [info commands ::GX::EMNative::core]]} {load [file join $root native bin emfem.so] Emfem}
    ::GX::EMNative::core $operation {*}$args
}
proc ::GX::ElectromagneticSimulation::apiInfo {} {dict create api_id ELECTROMAGNETIC_SIMULATION_API_v1 api_version 1 backend {Gmsh GetDP} implementation native_cpp problems {electrostatic_2d magnetostatic_2d} dimensional_formulations planar_2d operations {defaultModel validate saveModel listModels loadModel runAsync jobStatus jobLog cancel resultDescribe resultPreview publish fieldDescribe} features {validate models_save_load managed_run_async cancel result_preview publish exact_mesh_topology} limitations {linear_materials bounded_mesh no_spice no_axisymmetry no_device_inductance}}
proc ::GX::ElectromagneticSimulation::defaultModel {kind} {_native default $kind}
proc ::GX::ElectromagneticSimulation::validate {model} {set m [_native validate $model];dict create valid 1 problem [dict get $m kind] dimension planar_2d units SI model $m}
proc ::GX::ElectromagneticSimulation::workspaceValidate {payload} {
    if {[dict exists $payload model]} {set model [dict get $payload model]} else {set model [dict remove $payload workspace_metadata gmsh getdp]}
    _native validate $model;return [dict create valid 1]
}
proc ::GX::ElectromagneticSimulation::workspaceOpen {documentId} {
    # Presentation changes never replace the original em_models scientific owner.
    loadModel $documentId
    set module viewer.electromagnetics_studio;set provider electromagnetics_studio
    if {[info exists ::GX::moduleCatalog($module,dict)] && $provider in [::GX::viewerProviderIds $module] && [::GX::viewerProviderEnabled $module $provider]} {
        return [::GX::viewerOpen $module $provider [dict create em_document_id $documentId]]
    }
    return [::GX::viewerOpen viewer.electromagnetics electromagnetics [dict create workspace_id $documentId]]
}
proc ::GX::ElectromagneticSimulation::saveModel {model {documentId {}} {workspaceName {}}} {
    set model [_native validate $model]
    if {$documentId eq {}} {if {$workspaceName eq {}} {set workspaceName [dict get $model model_id]};return [::GX::sessionWorkspaceCreate em_models $workspaceName [dict create model $model]]}
    set prior [::GX::interactiveDocumentRead $documentId]
    if {[dict get $prior module_id] ne {math.electromagnetic_simulation}||[dict get $prior provider_id] ne {em_models}||[dict get $prior format] ne {gxtxt.em_model}} {error {Foreign electromagnetic model owner}}
    ::GX::sessionWorkspacePromote $documentId
    set payload [dict get [::GX::sessionWorkspaceGet $documentId] payload];if {![dict exists $payload model]} {set payload {}};dict set payload model $model
    return [::GX::sessionWorkspaceUpdate $documentId $payload]
}
proc ::GX::ElectromagneticSimulation::listModels {} {::GX::interactiveDocumentList math.electromagnetic_simulation em_models}
proc ::GX::ElectromagneticSimulation::loadModel {id} {
    set d [::GX::interactiveDocumentRead $id]
    if {[dict get $d module_id] ne {math.electromagnetic_simulation}||[dict get $d provider_id] ne {em_models}||[dict get $d format] ne {gxtxt.em_model}} {error {Foreign electromagnetic model owner}}
    set payload [dict get $d payload]
    if {[dict exists $payload model]} {set model [dict get $payload model]} else {set model [dict remove $payload workspace_metadata gmsh getdp]}
    return [_native validate $model]
}
proc ::GX::ElectromagneticSimulation::runAsync {model {callback {}} {documentId {}}} {
    variable provider
    set model [_native validate $model];set options {}
    if {$documentId ne {}} {loadModel $documentId;set d [::GX::interactiveDocumentRead $documentId];dict set options document_id $documentId;dict set options expected_revision [dict get $d revision]}
    set prepared [::GX::scientificExecutionPrepare $provider $model {} $options]
    set job [dict get [::GX::scientificExecutionSubmit $prepared] job_id]
    if {$callback ne {}} {after 100 [list ::GX::ElectromagneticSimulation::_notify $job $callback [::GX::interactiveDocumentSessionToken]]}
    return $job
}
# Compatibility completion notification only: no Job state or process ownership.
proc ::GX::ElectromagneticSimulation::_notify {job callback token} {
    if {[catch {::GX::interactiveDocumentSessionToken} current]||$token ne $current} return
    set result [jobStatus $job];set state [dict get $result state]
    if {$state in {QUEUED PREPARING RUNNING FINALIZING CANCELLING}} {after 150 [list ::GX::ElectromagneticSimulation::_notify $job $callback $token];return}
    set outcome [dict create ok [expr {$state eq {COMPLETED}}] job_id $job status $state]
    if {$state eq {COMPLETED}} {if {[catch {set receipt [resultDescribe $job]} reason]} {dict set outcome ok 0;dict set outcome error $reason} else {dict set outcome elements [dict get $receipt mesh_triangles]}} else {dict set outcome error "Managed FEM Job ended as $state; inspect its retained CORE log."}
    if {[catch {uplevel #0 [list {*}$callback $outcome]} reason]} {puts stderr "Electromagnetics completion notification: $reason"}
}
proc ::GX::ElectromagneticSimulation::jobStatus {id} {::GX::scientificExecutionStatus $id}
proc ::GX::ElectromagneticSimulation::jobLog {id {offset 0} {count 65536}} {
    if {[dict get [jobStatus $id] provider_id] ne {math.electromagnetic_simulation.fem2d}} {error {Select an actual electromagnetic FEM Job}}
    tailcall ::GX::scientificExecutionLog $id $offset $count
}
proc ::GX::ElectromagneticSimulation::cancel {id} {::GX::scientificExecutionCancel $id}
proc ::GX::ElectromagneticSimulation::_resultToken {job} {
    set status [jobStatus $job];if {[dict get $status state] ne {COMPLETED}} {error {A completed managed FEM Job is required}}
    foreach item [dict get [::GX::scientificExecutionOutputs $job] outputs] {if {[dict get $item role] eq {typed_result}} {return [dict get $item token]}}
    error {Managed Job has no validated electromagnetic result role}
}
proc ::GX::ElectromagneticSimulation::_result {job} {
    set token [_resultToken $job];set offset 0;set bytes {};set generation {}
    while {1} {
        set page [::GX::scientificExecutionReadOutput $job $token $offset 1048576 $generation]
        if {$generation eq {}} {set generation [dict get $page source_generation]}
        append bytes [binary decode base64 [dict get $page bytes_base64]]
        if {[string length $bytes]>16777216} {error {Typed FEM result exceeds bounded import capacity}}
        set next [dict get $page next_offset]
        if {$next>=[dict get $page size_bytes]} break
        if {$next<=$offset} {error {Managed result page made no progress}};set offset $next
    }
    set result [encoding convertfrom utf-8 $bytes]
    if {[catch {dict size $result}]||![dict exists $result schema]||[dict get $result schema] ne {GXTXT_EM_FEM_RESULT_v1}} {error {Invalid typed electromagnetic output}}
    return $result
}
proc ::GX::ElectromagneticSimulation::resultDescribe {job} {set result [_result $job];dict merge [dict get $result receipt] [dict create job_id $job state COMPLETED solver_versions [dict get $result solver_versions] native_sha256 [::GX::datasetPublicationV2DictDefault $result native_sha256 {unavailable in earlier provider receipt}]]}
proc ::GX::ElectromagneticSimulation::resultPreview {job {offset 0} {count 20}} {
    if {![string is integer -strict $offset]||$offset<0||![string is integer -strict $count]||$count<1||$count>100} {error {Preview requires nonnegative offset and 1..100 rows}}
    set data [dict get [_result $job] cells];set header [dict keys $data];set total [llength [dict get $data element_id]];set rows {}
    for {set row $offset} {$row<min($total,$offset+$count)} {incr row} {set values {};foreach name $header {lappend values [lindex [dict get $data $name] $row]};lappend rows $values}
    dict create header $header rows $rows offset $offset total $total
}
proc ::GX::ElectromagneticSimulation::publish {job datasetId} {::GX::scientificExecutionImportResults $job [_resultToken $job] [dict create dataset_id $datasetId]}
proc ::GX::ElectromagneticSimulation::_publishTable {id columns specs metadata} {
    set plan [::GX::datasetPublicationV2Prepare [::GX::sessionInspectionCurrentSession] math.electromagnetic_simulation [dict create dataset_id $id contract table.generic storage csv replace_owned 0 producer_version 0.2.0 structured_metadata $metadata]]
    set w [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $w row 0 {extendible 1}
        dict for {name values} $columns {lassign [dict get $specs $name] dtype unit role;::GX::datasetPublicationV2DeclareVariable $w $name [dict create dtype $dtype unit $unit coordinate_role $role dimension_ids row]}
        set total [llength [dict get $columns [lindex [dict keys $columns] 0]]]
        for {set at 0} {$at<$total} {incr at 512} {set chunk {};dict for {name values} $columns {dict set chunk $name [lrange $values $at [expr {$at+511}]]};::GX::datasetPublicationV2Append $w row $chunk}
        return [::GX::datasetPublicationV2Finalize $w]
    } on error {message options} {catch {::GX::datasetPublicationV2Abort $w};return -options $options $message}
}
proc ::GX::ElectromagneticSimulation::_publishReviewed {session module request} {
    _publishTable [dict get $request dataset_id] [dict get $request columns] [dict get $request specs] [dict get $request metadata]
}
# Snapshot approved opaque output roles into the existing managed Resource owner.
# No result directory/path escapes CORE and no Job state is copied here.
proc ::GX::ElectromagneticSimulation::_retainOutputs {job} {
    set status [::GX::scientificExecutionStatus $job]
    if {[dict exists $status source_identities workspace id]} {set document [dict get $status source_identities workspace id];set owner [::GX::interactiveDocumentRead $document];if {[dict get $owner module_id] ne {math.electromagnetic_simulation}} {error {Foreign solver-resource owner}}} else {set document [dict get [::GX::interactiveDocumentCreate math.electromagnetic_simulation em_results gxtxt.em_result 1 [dict create source_job_id $job]] id]}
    set resources {};set total 0
    foreach output [dict get [::GX::scientificExecutionOutputs $job] outputs] {
        set role [dict get $output role]
        if {$role ni {mesh source_geometry source_formulation scalar_field vector_field auxiliary_field solver_log}} continue
        if {[dict get $output availability] ne {available}||[dict get $output size_bytes]>67108864} {error {Missing or oversized approved solver resource}}
        incr total [dict get $output size_bytes];if {$total>268435456} {error {Solver resource snapshot exceeds total budget}}
        set token [dict get $output token];set generation [dict get $output source_generation]
        set writer [::GX::interactiveDocumentResourceOpenWriter $document [dict create format [dict get $output format] kind em_solver_source role $role source_job_id $job source_generation $generation]]
        try {
            set offset 0
            while {$offset<[dict get $output size_bytes]} {set page [::GX::scientificExecutionReadOutput $job $token $offset 1048576 $generation];set next [dict get $page next_offset];if {$next<=$offset} {error {Solver resource stream made no progress}};::GX::interactiveDocumentResourceAppend $writer [binary decode base64 [dict get $page bytes_base64]];set offset $next}
            ::GX::scientificExecutionReadOutput $job $token 0 1 $generation
            dict set resources $role [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
        } finally {if {$writer ne {}} {catch {::GX::interactiveDocumentResourceAbort $writer}}}
    }
    return $resources
}
proc ::GX::ElectromagneticSimulation::importResult {job token bytes request} {
    set data [encoding convertfrom utf-8 $bytes]
    if {[catch {dict size $data}]||[dict get $data schema] ne {GXTXT_EM_FEM_RESULT_v1}} {error {Wrong managed output scientific contract}}
    set model [_native validate [dict get $data model]];set id [dict get $request dataset_id];set nodesId ${id}_nodes
    foreach candidate [list $id $nodesId] {if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,80}$} $candidate]||$candidate in [::GX::sessionInspectionDatasetIds]} {error {Publication requires two unused canonical Dataset identities}}}
    set retained [_retainOutputs $job]
    set receipt [dict get $data receipt];set magnetic [expr {[dict get $model kind] eq {magnetostatic_2d}}]
    set roles {node_potential_variable_id potential node_id_variable_id node_id node_x_variable_id x node_y_variable_id y cell_id_variable_id element_id cell_x_variable_id x cell_y_variable_id y node_variable_ids {node_0_id node_1_id node_2_id} scalar_variable_id field_norm potential_variable_id potential field_component_variable_ids {field_x field_y field_z} region_variable_id region_id material_variable_id material_id}
    if {![dict exists $data nodes potential]} {dict unset roles node_potential_variable_id}
    set common [dict create em.solver_resources $retained em.native_sha256 [::GX::datasetPublicationV2DictDefault $data native_sha256 {unavailable in earlier provider receipt}] em.roles $roles em.kind [dict get $model kind] em.formulation planar_2d em.field_association cell_centroid em.job_id $job em.model $model em.solver_versions [dict get $data solver_versions] em.mesh_nodes [dict get $receipt mesh_nodes] em.mesh_triangles [dict get $receipt mesh_triangles] em.independent_relative_weak_residual [dict get $receipt independent_relative_weak_residual] em.solver_residual_absolute [dict get $receipt solver_residual_absolute] em.nodes_dataset_id $nodesId em.cells_dataset_id $id field.coordinate_system cartesian]
    set nodeSpecs {node_id {int64 {} auxiliary} x {float64 m coordinate} y {float64 m coordinate} z {float64 m auxiliary}};dict set nodeSpecs potential [list float64 [expr {$magnetic?{Wb/m}:{V}}] data]
    set specs {element_id {int64 {} auxiliary} region_id {int32 {} auxiliary} material_id {int32 {} auxiliary} node_0_id {int64 {} auxiliary} node_1_id {int64 {} auxiliary} node_2_id {int64 {} auxiliary} x {float64 m coordinate} y {float64 m coordinate} z {float64 m auxiliary} area {float64 m^2 data}}
    set unit [expr {$magnetic?{T}:{V/m}}];foreach k {field_x field_y field_z field_norm} {dict set specs $k [list float64 $unit data]};dict set specs potential [list float64 [expr {$magnetic?{Wb/m}:{V}}] data]
    if {$magnetic} {foreach k {auxiliary_x auxiliary_y auxiliary_z} {dict set specs $k {float64 A/m data}}}
    set requests [list [dict create dataset_id $nodesId columns [dict get $data nodes] specs $nodeSpecs metadata $common] [dict create dataset_id $id columns [dict get $data cells] specs $specs metadata $common]]
    set batch [::GX::datasetPublicationV2PublishBatch [::GX::sessionInspectionCurrentSession] math.electromagnetic_simulation $requests ::GX::ElectromagneticSimulation::_publishReviewed]
    lassign [dict get $batch datasets] nodes field
    dict create dataset_id $id nodes_dataset_id $nodesId field $field nodes $nodes job_id $job receipt $receipt
}
proc ::GX::ElectromagneticSimulation::fieldDescribe {dataset} {
    if {[::GX::datasetField $dataset source_module {}] ne {math.electromagnetic_simulation}} {error {Dataset is not published by the Electromagnetic Simulation provider}}
    set metadata [::GX::datasetMetadataRead [::GX::sessionInspectionCurrentSession] $dataset]
    foreach key {em.roles em.nodes_dataset_id em.kind} {if {![dict exists $metadata $key]} {error {Electromagnetic field role contract is unavailable}}}
    set roles [dict get $metadata em.roles];set nodeDataset [dict get $metadata em.nodes_dataset_id]
    dict for {role ids} $roles {set ds [expr {[string match node_* $role]&&$role ne {node_variable_ids}?$nodeDataset:$dataset}];foreach id $ids {::GX::datasetVariableV3ById $ds $id}}
    return [dict create dataset_id $dataset nodes_dataset_id $nodeDataset problem [dict get $metadata em.kind] roles $roles metadata $metadata]
}
proc ::GX::ElectromagneticSimulation::_register {} {
    variable provider
    ::GX::sessionWorkspaceProviderRegister em_models {module_id math.electromagnetic_simulation type {Electromagnetics model} schema gxtxt.em_model version 1 validate ::GX::ElectromagneticSimulation::workspaceValidate open ::GX::ElectromagneticSimulation::workspaceOpen}
    set parameters {}
    foreach key {kind model_id formulation half_width_m height_m mesh_size_m radius_m current_density_A_m2 mu_r voltage_V eps_r} {
        set descriptor [dict create type [expr {$key in {kind model_id formulation}?{string}:{number}}] required 1]
        if {$key eq {kind}} {dict set descriptor type choice;dict set descriptor values {electrostatic_2d magnetostatic_2d}}
        dict set parameters $key $descriptor
    }
    ::GX::scientificExecutionRegister $provider [dict create module_id math.electromagnetic_simulation version 0.2.0 worker plugins/modules/math.electromagnetic_simulation/backend/em_fem_provider.py runtime_files {plugins/modules/math.electromagnetic_simulation/native/bin/emfem.so} tools {gmsh getdp} parameters $parameters import_command ::GX::ElectromagneticSimulation::importResult]
}
::GX::ElectromagneticSimulation::_register
