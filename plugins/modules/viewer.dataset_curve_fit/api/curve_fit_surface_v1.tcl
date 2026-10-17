# Physical surface workflow. CORE owns storage/transport/history; Numeric fits.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_surfaceKeys {value allowed label} {
    foreach key [dict keys $value] {if {$key ni $allowed} {error "Unknown $label field: $key"}}
}
proc ::GX::DatasetCurveFit::_surfaceNumber {value} {return [::GX::ScientificTransportv1::array {1 1} [list $value]]}
proc ::GX::DatasetCurveFit::_surfaceCoordinate {value label} {
    if {[string is entier -strict $value]&&abs($value)>9007199254740992} {error {Surface coordinates cannot narrow integers outside the exact binary64 range}}
    return [_finite $value $label]
}
proc ::GX::DatasetCurveFit::_surfaceDescriptorNode {descriptor} {
    set fields {}
    dict for {key value} $descriptor {
        if {$key in {version count byte_count shape}} {set node [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]} else {set node [::GX::ScientificTransportv1::text $value]}
        dict set fields $key $node
    }
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::_surfaceBinding {request recipe} {
    _surfaceKeys $request {dataset_id x_variable_id y_variable_id z_variable_id sigma_variable_id layout} {surface source}
    set dataset [dict get $request dataset_id];set layout [dict get $request layout]
    if {$layout ni {points grid_yx}} {error {Declare surface input as points or grid_yx}}
    if {[dict get $recipe predictor_ids] ne {x y}} {error {Physical surface predictors must be x and y}}
    set identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]
    set handle [::GX::datasetAccessOpen $::GX::currentSession $dataset]
    try {
        if {![dict get [::GX::datasetAccessCapabilities $handle] managed_binary_read]} {error {Surface capture requires canonical managed binary reads}}
        set all {};foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {dict set all [dict get $variable variable_id] $variable}
        set roles {}
        foreach role {x y z sigma} {
            set field ${role}_variable_id
            if {$role eq "sigma"&&[::GX::datasetPublicationV2DictDefault $request $field {}] eq {}} continue
            set id [dict get $request $field]
            if {![dict exists $all $id]} {error "Surface Variable is unavailable: $id"}
            set v [dict get $all $id]
            if {![dict get $v enabled]||[dict get $v value_kind] ne "number"||[dict get $v dtype] ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64}||[dict get $v rank] ni {1 2}} {error {Surface Variables require enabled real numeric vectors or matrices}}
            set shape [::GX::datasetPublicationV2Shape [dict get $v shape]]
            set count [::GX::datasetPublicationV2ElementCount $shape]
            if {$count<1||$count>65536} {error {Surface capture is bounded to1..65536 original values per Variable}}
            dict set roles $role $v
        }
        foreach role {x y z} expected [concat [dict get $recipe predictor_units] [list [dict get $recipe response_unit]]] {
            if {[dict get $roles $role unit] ne $expected} {error "Surface $role unit differs from its canonical Variable; convert units explicitly upstream"}
        }
        set xv [dict get $roles x];set yv [dict get $roles y];set zv [dict get $roles z]
        if {[dict get $xv rank]!=1||[dict get $yv rank]!=1} {error {Surface X/Y coordinates must be explicit canonical vectors}}
        set xd [::GX::datasetSchemaV3SplitIds [dict get $xv dimension_ids]];set yd [::GX::datasetSchemaV3SplitIds [dict get $yv dimension_ids]];set zd [::GX::datasetSchemaV3SplitIds [dict get $zv dimension_ids]]
        if {$layout eq "points"} {
            if {[dict get $zv rank]!=1||$xd ne $yd||$xd ne $zd||[dict get $xv shape] ne [dict get $zv shape]||[dict get $yv shape] ne [dict get $zv shape]} {error {Surface point coordinates and Z must share one exact canonical row dimension}}
        } elseif {[dict get $zv rank]!=2||$xd eq $yd||$zd ne [concat $yd $xd]||[::GX::datasetPublicationV2Shape [dict get $zv shape]] ne [list [lindex [::GX::datasetPublicationV2Shape [dict get $yv shape]] 0] [lindex [::GX::datasetPublicationV2Shape [dict get $xv shape]] 0]]} {error {Surface grid Z must have the exact ordered Y/X axis dimensions; no transposition is inferred}}
        if {[dict exists $roles sigma]} {
            set sigma [dict get $roles sigma]
            foreach key {rank shape dimension_ids unit} {if {[dict get $sigma $key] ne [dict get $zv $key]} {error {Response sigma must have the exact Z shape, dimension identities and physical unit}}}
        }
        return [dict create schema gxtxt.surface_source_binding.v1 dataset_id $dataset layout $layout request $request dataset_identity $identity roles $roles original_shape [::GX::datasetPublicationV2Shape [dict get $zv shape]] original_count [::GX::datasetPublicationV2ElementCount [::GX::datasetPublicationV2Shape [dict get $zv shape]]] index_base 0 index_order column_major]
    } finally {::GX::datasetAccessClose $handle}
}
proc ::GX::DatasetCurveFit::_surfaceStage {binding directory} {
    set dataset [dict get $binding dataset_id]
    if {[::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset] ne [dict get $binding dataset_identity]} {error {Surface Dataset changed before capture}}
    set handle [::GX::datasetAccessOpen $::GX::currentSession $dataset];set source {};set staged {}
    try {
        set all {};foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {dict set all [dict get $variable variable_id] $variable}
        dict for {role variable} [dict get $binding roles] {
            set id [dict get $variable variable_id]
            if {![dict exists $all $id]||[dict get $all $id] ne $variable} {error {Surface Variable schema changed before capture}}
            set shape [::GX::datasetPublicationV2Shape [dict get $variable shape]];set starts [lrepeat [llength $shape] 0];set lease {}
            try {
                set response [::GX::datasetAccessReadHyperslabResource $handle $id $starts $shape]
                set lease [dict get $response binary_resource]
                set captured [::GX::ScientificTransportv1::stageDatasetResource $lease $directory]
                dict set staged $role $captured
                dict set source $role [_surfaceDescriptorNode [dict get $captured descriptor]]
            } finally {if {$lease ne {}} {::GX::datasetAccessReleaseResource $handle [dict get $lease resource_id]}}
        }
        if {[::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset] ne [dict get $binding dataset_identity]} {error {Surface Dataset changed during exact capture}}
        return [dict create node [::GX::ScientificTransportv1::struct $source] staged $staged]
    } finally {::GX::datasetAccessClose $handle}
}
proc ::GX::DatasetCurveFit::_surfaceRun {directory request {host {}}} {
    variable root;variable state
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set input [file join $directory request.ini];set output [file join $directory response.ini]
    ::GX::ScientificTransportv1::writeResult $input $request
    set environment [dict create GXDCF_SURFACE_REQUEST $input GXDCF_SURFACE_RESULT $output GXDCF_SURFACE_SESSION $::GX::currentSession GXDCF_CORE_OCTAVE_DIR [file join $root core octave] GXDCF_NUMERIC_API_DIR [::GX::NumericAPIv1::octaveApiDir]]
    set run [::GX::parallelExecutionNewRunId physical_surface];set progress {}
    if {$host ne {}} {set state($host,numericRun) $run;set state($host,sourceCancelled) 0;set progress [list ::GX::DatasetCurveFit::_numericProgress $host]}
    try {
        set executable [::GX::runtimeToolRequired octave]
        set task [dict create id surface argv [list $executable --quiet --no-gui --path [file join $root plugins modules viewer.dataset_curve_fit api octave] --eval {dataset_surface_fit_v1('file')}]]
        set execution [::GX::parallelExecutionExecute [list $task] [dict create kind process command_builder ::GX::DatasetCurveFit::_numericCommand environment $environment] [dict create workers 1 run_id $run progress_command $progress]]
        if {[dict get $execution state] eq "cancelled"} {error {Surface operation cancelled}}
        set result [lindex [dict get $execution results] 0]
        if {[dict get $result state] ne "success"} {error "Surface operation failed: [dict get $result stderr] [dict get $result error]"}
        return [dict get [::GX::ScientificTransportv1::readResult $output] values]
    } finally {
        ::GX::parallelExecutionRelease $run
        if {$host ne {}&&[info exists state($host,numericRun)]} {set state($host,numericRun) {}}
    }
}
proc ::GX::DatasetCurveFit::_surfaceRead {id} {
    set workspace [::GX::sessionWorkspaceGet $id]
    if {[dict get $workspace provider_id] ne "dataset_surface_fit"} {error {This Workspace does not contain a physical surface fit}}
    surfaceWorkspaceValidate [dict get $workspace payload]
    return $workspace
}
proc ::GX::DatasetCurveFit::_surfaceHistoryValidate {record} {surfaceWorkspaceValidate [dict get $record base];return 1}
proc ::GX::DatasetCurveFit::_surfaceHistoryCapture {id} {return [dict remove [dict get [_surfaceRead $id] payload] scientific_history]}
proc ::GX::DatasetCurveFit::_surfaceHistoryReplay {record} {return [::GX::scientificHistoryState $record]}
::GX::scientificRecipeHostRegister viewer.dataset_curve_fit.surface [dict create capture ::GX::DatasetCurveFit::_surfaceHistoryCapture validate ::GX::DatasetCurveFit::_surfaceHistoryValidate replay ::GX::DatasetCurveFit::_surfaceHistoryReplay]
proc ::GX::DatasetCurveFit::surfaceCreate {name} {
    ::GX::sessionWorkspaceProviderDiscover viewer.dataset_curve_fit
    set payload [dict create version 1 source {} recipe {} settings {} preview {} records {}]
    dict set payload scientific_history [::GX::scientificHistoryCreate viewer.dataset_curve_fit.surface $payload]
    return [::GX::sessionWorkspaceCreate dataset_surface_fit $name $payload]
}
proc ::GX::DatasetCurveFit::_surfaceCommit {original payload description} {
    set id [dict get $original workspace_id];set current [_surfaceRead $id]
    if {[dict get $current generation] ne [dict get $original generation]||[dict get $current revision]!=[dict get $original revision]} {error {Surface Workspace changed in another editor; reopen before committing}}
    set before [dict get $original payload]
    set history [::GX::datasetPublicationV2DictDefault $before scientific_history {}]
    if {$history eq {}} {set history [::GX::scientificHistoryCreate viewer.dataset_curve_fit.surface [dict remove $before scientific_history]]}
    set snapshot [dict remove $payload scientific_history]
    dict set payload scientific_history [::GX::scientificHistoryAppend viewer.dataset_curve_fit.surface $history $snapshot $description]
    return [::GX::sessionWorkspaceUpdate $id $payload]
}
proc ::GX::DatasetCurveFit::_surfaceArrayImport {document file shape dtype unit role} {
    set metadata [dict create format gxtxt.numeric_array_le.v1 dtype $dtype endian little order F shape $shape unit $unit role $role]
    if {[file size $file]!=[::GX::datasetPublicationV2ElementCount $shape]*[::GX::datasetBinaryTransportWidth $dtype]} {error {Surface array artifact differs from its exact shape and dtype}}
    return [::GX::interactiveDocumentResourceImportNumeric $document $file $metadata]
}
proc ::GX::DatasetCurveFit::_surfaceValidateResult {document result} {
    if {[dict get $result schema] ne "gxtxt.fitter_surface_result.v1"||![regexp {^surface_[0-9]+_[0-9]+$} [dict get $result id]]} {error {Invalid retained surface result identity}}
    set meaning [dict get $result statistics];::GX::StatisticsV1::validate $meaning
    if {[dict get $meaning model id] ne "math.numeric.surface"||[dict get $meaning context sample_role] ne "training"} {error {Surface result requires its captured CORE training interpretation}}
    set summary [dict get $meaning context surface];set n [dict get $summary observation_receipt retained_count]
    if {[dict get $result declaration_sha256] ne [dict get $summary declaration_sha256]||[dict get $result domain] ne [dict get $summary observation_domain bounds]} {error {Surface result declaration or coordinate bounds changed}}
    foreach field {state_resource observations_resource indices_resource} {
        set ref [dict get $result $field];::GX::interactiveDocumentResourceInfo $ref
        if {[dict get $ref document_id] ne $document} {error {Surface result resource belongs to another Workspace}}
    }
    set state [dict get $result state_resource];set observations [dict get $result observations_resource];set indices [dict get $result indices_resource]
    foreach ref [list $observations $indices] {
        foreach {field expected} {format gxtxt.numeric_array_le.v1 endian little order F} {if {[dict get $ref metadata $field] ne $expected} {error {Surface resource encoding changed}}}
    }
    set response [dict get $summary response_unit];set expectedUnits [concat [dict get $summary predictor_units] [list $response $response $response]]
    if {[dict get $observations metadata column_ids] ne {x y observed_z predicted_z residual_z}||[dict get $observations metadata column_units] ne $expectedUnits} {error {Surface observation columns or physical units changed}}
    if {[dict get $state metadata format] ne "gxtxt.surface_state.v1"||[dict get $state sha256] ne [dict get $result state_sha256]||[dict get $state size_bytes]>1048576} {error {Retained surface state identity or size changed}}
    if {[dict get $observations size_bytes]!=40*$n||[dict get $observations metadata shape] ne [list [expr {int($n)}] 5]||[dict get $observations metadata dtype] ne "float64"||[dict get $observations sha256] ne [dict get $result observations_sha256]} {error {Retained surface observations lost their physical row/column binding}}
    if {[dict get $indices size_bytes]!=8*$n||[dict get $indices metadata shape] ne [list [expr {int($n)}]]||[dict get $indices metadata dtype] ne "uint64"||[dict get $indices sha256] ne [dict get $result indices_sha256]} {error {Retained surface original indices changed}}
    set binding [dict get $result binding]
    set numericalShape [dict get $binding original_shape]
    if {[dict get $binding layout] eq "points"} {lappend numericalShape 1}
    if {[dict get $binding original_count]!=[dict get $summary observation_receipt original_count]||$numericalShape ne [dict get $summary observation_receipt original_shape]||[dict get $binding layout] ne [dict get $summary observation_receipt layout]} {error {Surface source layout differs from the captured numerical receipt}}
    if {[lsort [dict keys [dict get $result input_resources]]] ne [lsort [dict keys [dict get $binding roles]]]} {error {Surface original input roles changed}}
    dict for {role ref} [dict get $result input_resources] {
        ::GX::interactiveDocumentResourceInfo $ref
        if {[dict get $ref document_id] ne $document||[dict get $ref sha256] ne [dict get $binding input_sha256 $role]} {error {Surface original input resource changed}}
        set variable [dict get $binding roles $role]
        foreach field {dtype unit} {if {[dict get $ref metadata $field] ne [dict get $variable $field]} {error {Surface original input physical schema changed}}}
        if {[dict get $ref metadata shape] ne [::GX::datasetPublicationV2Shape [dict get $variable shape]]} {error {Surface original input dimensions changed}}
    }
    _surfaceStateValidate $result [_surfaceStateRead $state]
    return $result
}
proc ::GX::DatasetCurveFit::surfacePreview {workspace source recipe {options {}} {host {}}} {
    _surfaceKeys $options {nonfinite noise_model max_iterations max_seconds} {surface fit options}
    set original [_surfaceRead $workspace];set token [::GX::interactiveDocumentSessionToken]
    set binding [_surfaceBinding $source $recipe]
    set settings [dict create layout [dict get $binding layout] nonfinite [::GX::datasetPublicationV2DictDefault $options nonfinite error]]
    if {[dict get $settings nonfinite] ni {error omit}} {error {Choose explicit surface nonfinite policy error or omit}}
    foreach key {max_iterations max_seconds} {if {[dict exists $options $key]} {dict set settings $key [_finite [dict get $options $key] "Surface $key"]}}
    set noise [::GX::datasetPublicationV2DictDefault $options noise_model unspecified]
    if {$noise ni {unspecified independent_gaussian_known_sigma independent_gaussian_estimated_variance}} {error {Choose the explicit response-noise assumption}}
    if {$noise eq "independent_gaussian_known_sigma"&&![dict exists $binding roles sigma]||$noise eq "independent_gaussian_estimated_variance"&&[dict exists $binding roles sigma]} {error {Surface noise assumption conflicts with the declared response sigma}}
    set allocation [::GX::resourceManagementAllocate surface_fit [dict create kind directory session $::GX::currentSession lifetime computation]];set directory [dict get $allocation path]
    try {
        set capture [_surfaceStage $binding $directory];set nodes {}
        dict for {key value} $settings {dict set nodes $key [expr {$key in {max_iterations max_seconds}?[_surfaceNumber $value]:[::GX::ScientificTransportv1::text $value]}]}
        set context [::GX::ScientificTransportv1::struct [dict create noise_model [::GX::ScientificTransportv1::text $noise]]]
        set report [_surfaceRun $directory [dict create action [::GX::ScientificTransportv1::text fit] recipe [_formulaRecipeNode $recipe] source [dict get $capture node] settings [::GX::ScientificTransportv1::struct $nodes] context $context] $host]
        if {$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed during surface fitting}}
        set current [_surfaceRead $workspace]
        if {[dict get $current generation] ne [dict get $original generation]||[dict get $current revision]!=[dict get $original revision]} {error {Surface Workspace changed during fitting}}
        if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding dataset_id]] ne [dict get $binding dataset_identity]} {error {Surface Dataset changed during fitting}}
        if {[dict get $report schema] ne "gxtxt.fitter_surface_capture.v1"} {error {Unknown surface worker result}}
        set meaning [dict get $report statistics];::GX::StatisticsV1::validate $meaning
        set n [expr {int([dict get $report observation_count])}]
        if {$n<2||$n>65536} {error {Surface captured observation count is outside its contract}}
        set saved [::GX::interactiveDocumentResourceImportNumeric $workspace [file join $directory surface-state.ini] [dict create format gxtxt.surface_state.v1 role retained_physical_surface]]
        set observed [_surfaceArrayImport $workspace [file join $directory surface-observations.bin] [list $n 5] float64 {} surface_observations]
        dict set observed metadata column_ids [dict get $report observation_columns];dict set observed metadata column_units [dict get $report observation_units]
        set indices [_surfaceArrayImport $workspace [file join $directory surface-indices.bin] [list $n] uint64 1 original_surface_indices]
        set inputs {}
        dict for {role staged} [dict get $capture staged] {
            set descriptor [dict get $staged descriptor];set variable [dict get $binding roles $role]
            set shape [::GX::datasetPublicationV2Shape [dict get $variable shape]]
            # Managed transport pads a rank-one vector to Nx1 for Octave. Keep
            # its exact canonical Dataset rank in the retained source resource.
            set transportShape [dict get $descriptor shape]
            set expectedTransportShape $shape
            if {[llength $shape]==1} {lappend expectedTransportShape 1}
            if {$transportShape ne $expectedTransportShape||[dict get $descriptor dtype] ne [dict get $variable dtype]} {error {Surface source transport shape or dtype differs from its canonical schema}}
            set ref [_surfaceArrayImport $workspace [file join $directory [dict get $descriptor resource_id]] $shape [dict get $descriptor dtype] [dict get $variable unit] original_surface_$role]
            if {[dict get $ref sha256] ne [dict get $staged sha256]} {error {Surface input bytes changed during ownership transfer}}
            dict set inputs $role $ref;dict set binding input_sha256 $role [dict get $ref sha256]
        }
        set result [dict create schema gxtxt.fitter_surface_result.v1 id surface_[pid]_[clock microseconds] name {} binding $binding recipe $recipe options $options statistics $meaning domain [dict get $report domain] declaration_sha256 [dict get $report declaration_sha256] state_resource $saved state_sha256 [dict get $saved sha256] observations_resource $observed observations_sha256 [dict get $observed sha256] indices_resource $indices indices_sha256 [dict get $indices sha256] input_resources $inputs]
        _surfaceValidateResult $workspace $result
        set payload [dict get $original payload];dict set payload source $source;dict set payload recipe $recipe;dict set payload settings $options;dict set payload preview $result
        _surfaceCommit $original $payload {Preview physical surface fit}
        return $result
    } finally {
        ::GX::resourceManagementRelease [dict get $allocation id]
        ::GX::resourceManagementCleanup [list [dict get $allocation id]]
    }
}
proc ::GX::DatasetCurveFit::surfaceAccept {workspace name} {
    set original [_surfaceRead $workspace];set payload [dict get $original payload];set result [dict get $payload preview]
    if {$result eq {}} {error {Preview a physical surface before accepting it}}
    _surfaceValidateResult $workspace $result
    set name [string trim $name]
    if {$name eq {}||[string length $name]>160||[regexp {[\r\n]} $name]} {error {An accepted surface needs a one-line name of1..160 characters}}
    foreach saved [dict get $payload records] {if {[dict get $saved name] eq $name||[dict get $saved id] eq [dict get $result id]} {error {Surface name or preview has already been accepted}}}
    dict set result name $name;dict lappend payload records $result;dict set payload preview {}
    _surfaceCommit $original $payload "Accept surface: $name"
    return [surfaceResultReference $workspace [dict get $result id]]
}
proc ::GX::DatasetCurveFit::surfaceResultReference {workspace fitId} {
    set original [_surfaceRead $workspace]
    foreach result [dict get [dict get $original payload] records] {
        if {[dict get $result id] ne $fitId} continue
        _surfaceValidateResult $workspace $result
        return [dict create schema gxtxt.surface_fit_reference.v1 workspace_id $workspace owner_generation [dict get $original generation] fit_id $fitId state_sha256 [dict get $result state_sha256]]
    }
    error {Accepted surface result is unavailable in this Workspace}
}
proc ::GX::DatasetCurveFit::_surfaceResult {reference} {
    if {[dict get $reference schema] ne "gxtxt.surface_fit_reference.v1"} {error {A versioned accepted surface reference is required}}
    set workspace [dict get $reference workspace_id];set fitId [dict get $reference fit_id]
    if {[surfaceResultReference $workspace $fitId] ne $reference} {error {Accepted surface owner, identity or state changed}}
    foreach result [dict get [dict get [_surfaceRead $workspace] payload] records] {if {[dict get $result id] eq $fitId} {return $result}}
}
proc ::GX::DatasetCurveFit::_surfaceCopyResource {reference path} {
    set reader [::GX::interactiveDocumentResourceOpenReader $reference];set channel {}
    try {
        set channel [::open $path {WRONLY CREAT EXCL}];fconfigure $channel -translation binary
        while {1} {set page [::GX::interactiveDocumentResourceNext $reader];puts -nonewline $channel [dict get $page bytes];if {[dict get $page eof]} break}
    } finally {if {$channel ne {}} {::close $channel};::GX::interactiveDocumentResourceCloseReader $reader}
}
proc ::GX::DatasetCurveFit::_surfaceStateRead {reference} {
    variable surfaceStateCache
    if {![info exists surfaceStateCache]} {set surfaceStateCache {}}
    ::GX::interactiveDocumentResourceInfo $reference
    set key [list [::GX::interactiveDocumentSessionToken] [dict get $reference document_id] [dict get $reference owner_generation] [dict get $reference sha256]]
    if {[dict exists $surfaceStateCache $key]} {return [dict get $surfaceStateCache $key]}
    set allocation [::GX::resourceManagementAllocate surface_state_read [dict create kind directory session $::GX::currentSession lifetime computation]]
    try {
        set path [file join [dict get $allocation path] surface-state.ini];_surfaceCopyResource $reference $path
        set saved [dict get [::GX::ScientificTransportv1::readResult $path] values]
    } finally {::GX::resourceManagementRelease [dict get $allocation id];::GX::resourceManagementCleanup [list [dict get $allocation id]]}
    if {[dict size $surfaceStateCache]>=8} {dict unset surfaceStateCache [lindex [dict keys $surfaceStateCache] 0]}
    dict set surfaceStateCache $key $saved
    return $saved
}
proc ::GX::DatasetCurveFit::_surfaceRecipeEqual {a b} {
    if {[lsort [dict keys $a]] ne [lsort [dict keys $b]]} {return 0}
    foreach key {expression predictor_ids predictor_units response_unit} {if {[dict get $a $key] ne [dict get $b $key]} {return 0}}
    set ap [dict get $a parameters];set bp [dict get $b parameters]
    if {[llength $ap]!=[llength $bp]} {return 0}
    foreach first $ap second $bp {
        if {[lsort [dict keys $first]] ne [lsort [dict keys $second]]} {return 0}
        dict for {key value} $first {
            if {$key in {id unit}} {if {$value ne [dict get $second $key]} {return 0}} elseif {$key eq "fixed"} {
                if {!!$value!=!![dict get $second $key]} {return 0}
            } elseif {$value!=[dict get $second $key]} {return 0}
        }
    }
    return 1
}
proc ::GX::DatasetCurveFit::_surfaceStateValidate {result saved} {
    set meaning [dict get $result statistics];set summary [dict get $meaning context surface]
    if {![_surfaceRecipeEqual [dict get $result recipe] [dict get $saved recipe]]} {error {Retained surface recipe differs from its owned physical model state}}
    foreach key {declaration_sha256 source_sha256 binding_sha256} other {declaration_sha256 formula_source_sha256 formula_binding_sha256} {
        if {[dict get $saved $key] ne [dict get $summary $other]} {error {Retained surface model identity differs from its captured CORE interpretation}}
    }
    if {[dict get $saved observation_domain] ne [dict get $summary observation_domain]} {error {Retained surface bounds or coverage meaning changed}}
    set values [lmap p [dict get $meaning parameters] {dict get $p value}]
    if {[llength $values]!=[llength [dict get $saved parameters]]} {error {Retained surface parameter count changed}}
    foreach expected $values actual [dict get $saved parameters] {if {$actual!=$expected} {error {Retained surface parameters differ from their captured CORE interpretation}}}
    # Numeric restore validates the complete declaration, dimensional recipe and
    # parameter constraints again before any retained evaluation or export.
    return $saved
}
proc ::GX::DatasetCurveFit::_surfaceStageState {result directory} {
    set saved [_surfaceStateValidate $result [_surfaceStateRead [dict get $result state_resource]]]
    _surfaceCopyResource [dict get $result state_resource] [file join $directory surface-state.ini]
    return $saved
}
proc ::GX::DatasetCurveFit::_surfaceRetained {reference action fields {host {}}} {
    set result [_surfaceResult $reference];set token [::GX::interactiveDocumentSessionToken]
    set allocation [::GX::resourceManagementAllocate surface_retained [dict create kind directory session $::GX::currentSession lifetime computation]]
    set directory [dict get $allocation path]
    try {
        _surfaceStageState $result $directory
        set report [_surfaceRun $directory [dict merge [dict create action [::GX::ScientificTransportv1::text $action]] $fields] $host]
        if {$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed during retained surface evaluation}}
        _surfaceResult $reference
        if {$action eq "grid"} {
            set shape [dict get $report shape];set workspace [dict get $reference workspace_id];set refs {}
            foreach role {x y z} unit [dict get $report coordinate_units] sizes [list [list [lindex $shape 1]] [list [lindex $shape 0]] $shape] {
                dict set refs $role [_surfaceArrayImport $workspace [file join $directory surface-grid-$role.bin] $sizes float64 $unit sampled_surface_$role]
            }
            dict set report resources $refs
        }
        dict set report reference $reference
        return $report
    } finally {::GX::resourceManagementRelease [dict get $allocation id];::GX::resourceManagementCleanup [list [dict get $allocation id]]}
}
proc ::GX::DatasetCurveFit::_surfaceQueryOptions {options {allowJacobian 1}} {
    _surfaceKeys $options [expr {$allowJacobian?{extrapolation jacobian}:{extrapolation}}] {retained surface query options}
    set policy [::GX::datasetPublicationV2DictDefault $options extrapolation error]
    if {$policy ni {error allow}} {error {Surface extrapolation must be error or explicit allow}}
    set fields [dict create extrapolation [::GX::ScientificTransportv1::text $policy]]
    if {[dict exists $options jacobian]} {
        if {![string is boolean -strict [dict get $options jacobian]]} {error {Surface Jacobian request must be boolean}}
        dict set fields jacobian [_surfaceNumber [expr {!![dict get $options jacobian]}]]
    }
    return [::GX::ScientificTransportv1::struct $fields]
}
proc ::GX::DatasetCurveFit::surfaceQuery {reference coordinates {options {}}} {
    set n [llength $coordinates];if {$n<1||$n>512} {error {Retained surface queries require1..512 exact XY rows}}
    set xs {};set ys {}
    foreach pair $coordinates {
        if {[llength $pair]!=2} {error {Surface query requires physical XY pairs}}
        lappend xs [_surfaceCoordinate [lindex $pair 0] {Surface query X}];lappend ys [_surfaceCoordinate [lindex $pair 1] {Surface query Y}]
    }
    return [_surfaceRetained $reference query [dict create coordinates [::GX::ScientificTransportv1::array [list $n 2] [concat $xs $ys]] options [_surfaceQueryOptions $options]]]
}
proc ::GX::DatasetCurveFit::surfaceExport {reference functionName} {
    set domain [dict get [_surfaceResult $reference] domain];set flat {}
    foreach col {0 1} {foreach row $domain {lappend flat [lindex $row $col]}}
    return [_surfaceRetained $reference export [dict create options [::GX::ScientificTransportv1::struct [dict create name [::GX::ScientificTransportv1::text $functionName] domain [::GX::ScientificTransportv1::array {2 2} $flat]]]]]
}
proc ::GX::DatasetCurveFit::surfaceInfo {reference} {
    set result [_surfaceResult $reference]
    set resources {}
    foreach key {state_resource observations_resource indices_resource} {dict set resources $key [dict get $result $key]}
    dict for {role resource} [dict get $result input_resources] {dict set resources input_$role $resource}
    return [dict create schema gxtxt.fitter_surface_info.v1 reference $reference name [dict get $result name] statistics [dict get $result statistics] domain [dict get $result domain] recipe [surfaceRecipeCapture $reference] source_layout [dict get $result binding layout] original_shape [dict get $result binding original_shape] state_sha256 [dict get $result state_sha256] resources $resources fit_performed 0]
}
proc ::GX::DatasetCurveFit::surfaceReport {reference} {
    set meaning [dict get [_surfaceResult $reference] statistics]
    return "[::GX::StatisticsV1::report $meaning {n sse r_squared dof rmse}]\n[::GX::StatisticsV1::parameterReport $meaning]"
}
proc ::GX::DatasetCurveFit::surfaceResidualPage {reference start count} {
    set result [_surfaceResult $reference]
    return [_surfaceResidualPage $result $start $count]
}
proc ::GX::DatasetCurveFit::_surfaceResidualPage {result start count} {
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$count>512} {error {Surface residual pages require a nonnegative offset and1..512 rows}}
    set ref [dict get $result observations_resource];set total [lindex [dict get $ref metadata shape] 0]
    if {$start>$total} {error {Surface residual offset is outside the retained rows}}
    set count [expr {min($count,$total-$start)}];set ranges {}
    for {set col 0} {$col<5} {incr col} {lappend ranges [list [expr {8*($col*$total+$start)}] [expr {8*$count}]]}
    set columns {};foreach bytes [::GX::interactiveDocumentResourceReadRanges $ref $ranges] {binary scan $bytes q* values;lappend columns $values}
    set rows {};for {set row 0} {$row<$count} {incr row} {foreach column $columns {lappend rows [lindex $column $row]}}
    set page [dict create bytes [binary format q* $rows] dtype float64 columns [dict get $ref metadata column_ids] start $start row_count $count total_rows $total source_sha256 [dict get $ref sha256]]
    set indices [dict get $result indices_resource]
    set ids [dict create bytes [::GX::interactiveDocumentResourceReadChunk $indices [expr {8*$start}] [expr {8*$count}]] dtype uint64 columns {original_linear_index} start $start row_count $count total_rows $total source_sha256 [dict get $indices sha256]]
    return [dict create api_id FITTER_SURFACE_RESIDUAL_PAGE_v1 api_version 1 meaning [dict get $result statistics] residuals $page source_rows $ids physical_column_units [dict get $ref metadata column_units] meaning_scope training_vertical_z_residuals display_projection {}]
}
proc ::GX::DatasetCurveFit::surfacePublish {reference dataset x y {options {}}} {
    set result [_surfaceResult $reference]
    set x [lmap v $x {_surfaceCoordinate $v {Surface grid X}}];set y [lmap v $y {_surfaceCoordinate $v {Surface grid Y}}]
    set report [_surfaceRetained $reference grid [dict create x [::GX::ScientificTransportv1::array [list [llength $x] 1] $x] y [::GX::ScientificTransportv1::array [list [llength $y] 1] $y] options [_surfaceQueryOptions $options 0]]]
    set variables {}
    foreach role {x y z} dims {surface_x surface_y {surface_y;surface_x}} {
        set ref [dict get $report resources $role]
        lappend variables [dict create variable_id $role schema [dict create dtype float64 dimension_ids $dims unit [dict get $ref metadata unit]] resource $ref]
    }
    set definition [dict create dataset_id $dataset contract table.generic storage hdf5 producer viewer.dataset_curve_fit title [dict get $result name]]
    dict set definition structured_metadata [dict create surface_fit.statistical_results [dict create source_training [dict get $result statistics]] surface_fit.recipe [dict get $result recipe] surface_fit.source_binding [dict get $result binding] surface_fit.reference $reference surface_fit.state_sha256 [dict get $result state_sha256] surface_fit.representation sampled_declared_surface_model surface_fit.interpolation_performed 0 surface_fit.fit_performed 0 surface_fit.statistics_scope original_training_observations_not_sampled_grid surface_fit.domain_meaning [dict get $report domain_meaning] surface_fit.extrapolation [::GX::datasetPublicationV2DictDefault $options extrapolation error]]
    set publication [::GX::datasetPublicationV2PublishManagedVariables $::GX::currentSession viewer.dataset_curve_fit $definition [dict create surface_x [llength $x] surface_y [llength $y]] $variables]
    # Persist the qualification with the owning scientific Workspace and keep
    # the canonical Dataset identity for later render/reuse validation.
    set receipt [dict create schema gxtxt.surface_publication.v1 dataset_id [dict get $publication dataset_id] dataset_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $publication dataset_id]] reference $reference representation sampled_declared_surface_model interpolation_performed 0 fit_performed 0 coordinate_units [dict get $report coordinate_units] domain_meaning [dict get $report domain_meaning] extrapolation [::GX::datasetPublicationV2DictDefault $options extrapolation error] shape [dict get $report shape]]
    set original [_surfaceRead [dict get $reference workspace_id]];set payload [dict get $original payload];dict lappend payload publications $receipt
    _surfaceCommit $original $payload "Publish sampled surface: [dict get $publication dataset_id]"
    dict set publication surface $receipt
    return $publication
}
proc ::GX::DatasetCurveFit::surfacePlot {reference dataset {style surface}} {
    _surfaceResult $reference
    if {$style ni {surface mesh}} {error {Choose surface or mesh rendering of the sampled physical model}}
    set payload [dict get [_surfaceRead [dict get $reference workspace_id]] payload];set found 0
    foreach receipt [::GX::datasetPublicationV2DictDefault $payload publications {}] {
        if {[dict get $receipt dataset_id] eq $dataset&&[dict get $receipt reference] eq $reference&&[dict get $receipt dataset_identity] eq [::GX::curveSourceDatasetIdentity $::GX::currentSession $dataset]} {set found 1;break}
    }
    if {!$found} {error {Choose an unchanged canonical grid published from this accepted surface}}
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set spec [::GX::PlotDatasetAPIv3::newSpec -graph_id plot.dataset.xyz -title {Sampled physical surface model}]
    dict set spec graph_type cartesian_3d
    foreach {field value} [list dataset_id $dataset x_variable_id x y_variable_id y z_variable_id z] {dict set spec $field $value}
    dict set spec config [dict create plot_type $style]
    ::GX::PlotDatasetAPIv3::validateSpec $spec
    set plot [::GX::PlotDatasetAPIv3::createPlotFromSpec $spec variant]
    ::GX::writeManifest [file join $::GX::currentSession metadata manifest.ini]
    return $plot
}
proc ::GX::DatasetCurveFit::surfaceRecipeCapture {reference} {
    set result [_surfaceResult $reference]
    return [::GX::scientificRecipeEncode [dict create format gxtxt.surface_fit_recipe.v1 source [dict get $result binding request] dataset_identity [dict get $result binding dataset_identity] recipe [dict get $result recipe] options [dict get $result options]]]
}
proc ::GX::DatasetCurveFit::surfaceRecipeRun {encoded name acceptedName} {
    set recipe [::GX::scientificRecipeDataDecode $encoded gxtxt.surface_fit_recipe.v1]
    if {[dict get $recipe dataset_identity] ne [::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $recipe source dataset_id]]} {error {Surface recipe source changed; explicitly review and bind the new source before fitting}}
    set workspace [dict get [surfaceCreate $name] workspace_id]
    surfacePreview $workspace [dict get $recipe source] [dict get $recipe recipe] [dict get $recipe options]
    return [surfaceAccept $workspace $acceptedName]
}
proc ::GX::DatasetCurveFit::surfacePreviewSummary {workspace source recipe options} {
    set result [surfacePreview $workspace $source $recipe $options]
    return [dict create workspace_id $workspace preview_id [dict get $result id] statistics [dict get $result statistics] domain [dict get $result domain] fit_performed 1]
}
