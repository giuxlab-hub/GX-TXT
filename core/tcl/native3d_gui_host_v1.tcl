# SPDX-License-Identifier: GPL-3.0-or-later
# Thin Viewer Provider/Tk adapter. Geometry and pixels are produced by libgx3de.
namespace eval ::GX::Engine3D {
    variable window .gx3de_viewer
    variable embedded 0
    variable hostWidgetChanging 0
    variable mountGeneration 0
    variable resizePending {}
    variable renderedSize {960 640}
    variable ownerModule viewer.engine_3d
    variable ownerProvider engine_3d
    variable windowTitle {GX-TXT Native 3D Engine Viewer}
    variable panelHook {}
    variable closeHook {}
    variable editHook {}
    variable selectionHook {}
    variable gestureStarting 0
    variable pendingDragEnd {}
    variable pendingDragJob {}
    variable gestureGeneration 0
    variable pendingGestureCancel {}
    variable pendingGestureCancelJob {}
    variable photo ""
    variable lastPng ""
    variable latestPick [dict create]
    variable selectionFrameDirty 0
    variable status "Ready"
    variable sidebarMode auto
    variable sidebarPending {}
    variable escapeOwner {}
    variable escapePrevious {}
    variable escapeInstalled {}
    variable selectedLayer ""
    variable visible 1
    variable opacity 1
    variable scalar ""
    variable scalarRange ""
    variable cameraPosition ""
    variable cameraTarget ""
    variable cameraUp ""
    variable projection perspective
    variable clipping ""
    variable planeOrigin ""
    variable planeNormal ""
    variable planeU ""
    variable planeVisible 0
    variable datasetId ""
    variable datasetX ""
    variable datasetY ""
    variable datasetZ ""
    variable datasetScalar ""
    variable datasetKind points
    variable datasetVx ""
    variable datasetVy ""
    variable datasetVz ""
    variable datasetRadius ""
    variable datasetOpacity ""
    variable worker ""
    variable workerGeneration 0
    variable workerSoftware 0
    variable workerExecution ""
    variable workerAddressSpaceBudget ""
    variable lastGraphicsPolicy ""
    variable workerLog ""
    variable workerLine ""
    variable workerBusy 0
    variable workerRssTimer ""
    variable renderGeneration 0
    variable cancelRequested 0
    variable pendingBackend ""
    variable pendingSession ""
    variable pendingAddedLayer ""
    variable activeNewLayer ""
    variable vector ""
    variable radius ""
    variable opacityArray ""
    variable tubeRadius 0
    variable isovalues ""
    variable colormap viridis
    variable representation surface
    variable layerKind surface
    variable baseColor {0.78;0.82;0.9}
    variable lineWidth 1
    variable pointSize 4
    variable backfaceCulling 0
    variable scalarColoring 0
    variable backgroundRgb {0.12;0.14;0.18}
    variable backgroundBottomRgb {0.04;0.05;0.08}
    variable backgroundGradient 0
    variable lighting 1
    variable lightingAmbient 0.25
    variable lightingDiffuse 0.8
    variable lightingSpecular 0.2
    variable lightingDirection {-0.4;-0.5;-1}
    variable lightingColor {1;1;1}
    variable lightingIntensity 1
    variable lightingLights ""
    variable clipBox ""
    variable cameraPreset isometric
    variable measurementA ""
    variable measurementB ""
    variable measurementC ""
    variable measurementKind distance
    variable curveKind section
    variable curveTolerance 0.001
    variable dragX 0
    variable dragY 0
    variable dragRenderX 0
    variable dragRenderY 0
    variable cameraLastUpdate 0
    variable cameraQueue {}
    variable cameraQueueSession ""
    variable dragMode ""
    variable planeMode 0
    variable planeTarget working
    variable planeAction translate
    variable planeHandle free
    variable planeSlot 0
    variable planeLastUpdate 0
    variable gizmoActive 0
    variable gizmoSpace world
    variable gizmoFamilies {axis,plane,free,rotate}
    variable gizmoPivot ""
    variable gizmoPivotMarker ""
    variable gizmoSizePixels 96
    variable gizmoLastUpdate 0
    variable pendingGizmoEnd ""
    variable axesWorld 0
    variable axesLocalLayer ""
    variable axesReferenceMarker ""
    variable axesSizePixels 72
    variable exportWidth 1920
    variable exportHeight 1080
    variable timelineId timeline_1
    variable timelineUnit s
    variable timelineTimes {0;1}
    variable timelineTrackId field_1
    variable timelineFrameLayers ""
    variable timelineFrame 0
    variable timelineTime 0
    variable timelineRate 1
    variable timelineLoop once
    variable timelineRangeFirst 0
    variable timelineRangeLast 1
    variable timelineTimer ""
    variable timelineLastTick 0
    variable fieldKind lines
    variable fieldSourceMode static
    variable fieldSourceTrack ""
    variable fieldSeeds {0;0;0}
    variable fieldSeedKind points
    variable fieldSeedOrigin {0;0;0}
    variable fieldSeedU {0;1;0}
    variable fieldSeedV {0;0;1}
    variable fieldSeedUCount 2
    variable fieldSeedVCount 2
    variable fieldDirection forward
    variable fieldVectorIndex 0
    variable fieldScalarIndex ""
    variable fieldStep 0.1
    variable fieldTimeStep 0.1
    variable fieldMinMagnitude 1e-9
    variable fieldTubeRadius 0.03
    variable fieldMaxSteps 1000
    variable fieldMaxPoints 10000
    variable fieldMaxMemoryBytes 16777216
    variable fieldSliceOrigin {0;0;0}
    variable fieldSliceU {0;1;0}
    variable fieldSliceV {0;0;1}
    variable fieldSliceUCount 8
    variable fieldSliceVCount 8
    variable fieldIsoName density
    variable fieldIsoValue 0.5
}

proc ::GX::native3DGuiHostApiInfo {} {
    return [dict create api_id NATIVE_3D_GUI_HOST_API_v1 api_version 1 shared_renderer 1 shared_worker 1 operations {configure mount suspend resume backend panel rpc close compact_preview_acquire compact_preview_release camera_reset camera_roll scientific_axes_grid shared_enlarged_viewport screenshot_dataset_publication layer_texture_validate layer_texture_bind layer_texture_anchor}]
}
proc ::GX::Engine3D::ownerModule {} {return $::GX::Engine3D::ownerModule}
proc ::GX::Engine3D::ownerProvider {} {return $::GX::Engine3D::ownerProvider}
proc ::GX::Engine3D::setHostIdentity {module provider} {
    if {$module eq $::GX::Engine3D::ownerModule&&$provider eq $::GX::Engine3D::ownerProvider} return
    if {$::GX::Engine3D::workerBusy} {error "Finish or cancel the active Native3D operation before changing the view host"}
    if {[::GX::viewerProviderDefinition $module $provider] eq {}} {error "Native3D view provider is unavailable"}
    if {$::GX::Engine3D::worker ne ""||([llength [info commands winfo]]&&[winfo exists $::GX::Engine3D::window])} {close}
    set ::GX::Engine3D::ownerModule $module;set ::GX::Engine3D::ownerProvider $provider
    set ::GX::Engine3D::panelHook {};set ::GX::Engine3D::closeHook {};set ::GX::Engine3D::editHook {};set ::GX::Engine3D::selectionHook {}
    set ::GX::Engine3D::windowTitle [expr {$module eq "viewer.engine_3d" ? "GX-TXT Native 3D Engine Viewer" : "GX-TXT [::GX::moduleField $module name $module]"}]
}
proc ::GX::Engine3D::configureHost {module provider callbacks} {
    foreach key [dict keys $callbacks] {if {$key ni {panel close edit selection}} {error "Unknown Native3D host callback '$key'"}}
    setHostIdentity $module $provider
    foreach {key variable} {panel panelHook close closeHook edit editHook selection selectionHook} {set ::GX::Engine3D::$variable [::GX::datasetPublicationV2DictDefault $callbacks $key {}]}
}

proc ::GX::Engine3D::root {} {
    return [file dirname [::GX::moduleField viewer.engine_3d descriptor]]
}
proc ::GX::Engine3D::loadNative {} {
    variable worker
    variable workerSoftware
    variable workerExecution
    variable workerAddressSpaceBudget
    variable workerLog
    set execution [::GX::configurationGet viewers.native3d.execution]
    set addressBudget [::GX::configurationGet viewers.native3d.worker_address_space_budget_mib]
    if {$worker ne "" && ($workerExecution ne $execution || $workerAddressSpaceBudget ne $addressBudget)} {
        stopWorker
        set workerSoftware [expr {$execution eq "Software"}]
    }
    if {$worker ne ""} return
    if {$workerExecution ne $execution} {set workerSoftware [expr {$execution eq "Software"}]}
    set workerExecution $execution
    set workerAddressSpaceBudget $addressBudget
    set library [file join $::GX::scriptDir core native3d bin libgx3de_viewer_tcl.so]
    if {![file isfile $library]} {error "Native 3D Engine bridge is missing: $library"}
    # Script Bridge can embed this interpreter inside Python. The renderer is
    # a Tcl worker and must use a Tcl executable in either host environment.
    set tool [auto_execok tclsh]
    if {$tool eq ""} {error "Native3D isolated rendering requires a Tcl executable"}
    set script [file join $::GX::scriptDir core native3d renderer_worker.tcl]
    set workerLog [file join [::GX::configurationCacheDirectory] "gx3de_viewer_worker_[pid].log"]
    set saved [dict create]
    foreach key {LIBGL_ALWAYS_SOFTWARE LIBGL_ALWAYS_INDIRECT MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER} {
        if {[info exists ::env($key)]} {dict set saved $key [list 1 $::env($key)]} \
            else {dict set saved $key [list 0 ""]}
    }
    if {$workerSoftware} {
        set ::env(LIBGL_ALWAYS_SOFTWARE) 1
        set ::env(LIBGL_ALWAYS_INDIRECT) 0
        set ::env(MESA_LOADER_DRIVER_OVERRIDE) llvmpipe
        set ::env(GALLIUM_DRIVER) llvmpipe
    } else {
        unset -nocomplain ::env(LIBGL_ALWAYS_SOFTWARE) ::env(MESA_LOADER_DRIVER_OVERRIDE) ::env(GALLIUM_DRIVER)
        set ::env(LIBGL_ALWAYS_INDIRECT) 0
    }
    set command [list $tool $script $library]
    if {$::tcl_platform(platform) eq "unix" && [auto_execok prlimit] ne ""} {
        set budget $addressBudget
        set command [concat [list [auto_execok prlimit] --as=[expr {$budget*1024*1024}] --] $command]
    }
    try {
        set worker [open "|[concat $command [list 2>$workerLog]]" r+]
        incr ::GX::Engine3D::workerGeneration
    } finally {
        dict for {key old} $saved {
            if {[lindex $old 0]} {set ::env($key) [lindex $old 1]} \
                else {unset -nocomplain ::env($key)}
        }
    }
    fconfigure $worker -buffering line -blocking 0 -encoding utf-8 -translation lf
    set response [waitLine 30000]
    if {$response ne "GX3DE_VIEWER_WORKER_READY"} {
        catch {::close $worker};set worker ""
        error "Native renderer worker did not initialize; see $workerLog: $response"
    }
}
proc ::GX::Engine3D::workerReadable {} {
    variable worker
    variable workerLine
    if {$worker eq ""} return
    if {[gets $worker line] >= 0} {
        set workerLine [list line $line]
    } elseif {[eof $worker]} {
        set workerLine [list dead "Native renderer worker exited; see $::GX::Engine3D::workerLog"]
    }
}
proc ::GX::Engine3D::workerRssBudget {} {
    return [::GX::configurationGet viewers.native3d.worker_rss_budget_mib]
}
proc ::GX::Engine3D::workerRssCheck {} {
    variable worker
    variable workerLine
    variable workerRssTimer
    set workerRssTimer ""
    if {$worker eq "" || $workerLine ne ""} return
    if {$::tcl_platform(os) eq "Linux"} {
        foreach process [pid $worker] {
            set statusPath "/proc/$process/status"
            if {![file readable $statusPath]} continue
            if {[catch {
                set fd [::open $statusPath r]
                try {set statusText [read $fd]} finally {::close $fd}
            }]} continue
            if {[regexp -line {^VmRSS:[[:space:]]+([0-9]+)[[:space:]]+kB} $statusText -> kib] && \
                $kib > [expr {[workerRssBudget]*1024}]} {
                set diagnostic "Native renderer RSS budget exceeded: [format %.1f [expr {$kib/1024.0}]] MiB resident; configured limit [workerRssBudget] MiB"
                stopWorker
                set workerLine [list dead $diagnostic]
                return
            }
        }
    }
    set workerRssTimer [after 250 ::GX::Engine3D::workerRssCheck]
}
proc ::GX::Engine3D::waitLine {milliseconds} {
    variable worker
    variable workerLine
    set workerLine ""
    workerRssBudget
    fileevent $worker readable ::GX::Engine3D::workerReadable
    set timer [after $milliseconds [list set ::GX::Engine3D::workerLine \
        [list timeout "Native renderer worker did not respond within ${milliseconds} ms; see $::GX::Engine3D::workerLog"]]]
    set ::GX::Engine3D::workerRssTimer [after 250 ::GX::Engine3D::workerRssCheck]
    vwait ::GX::Engine3D::workerLine
    after cancel $timer
    if {$::GX::Engine3D::workerRssTimer ne ""} {
        after cancel $::GX::Engine3D::workerRssTimer
        set ::GX::Engine3D::workerRssTimer ""
    }
    if {$worker ne ""} {fileevent $worker readable {}}
    lassign $workerLine status value
    if {$status ne "line"} {
        stopWorker
        error $value
    }
    return $value
}
proc ::GX::Engine3D::rpc {request} {
    variable worker
    variable workerBusy
    if {$workerBusy} {error "Native renderer request is already running"}
    set workerBusy 1
    try {
        loadNative
        if {[catch {puts $worker $request;flush $worker} problem]} {
            stopWorker
            error "Native renderer worker stopped unexpectedly: $problem"
        }
        set response [waitLine 120000]
    } finally {
        set workerBusy 0
        if {$::GX::Engine3D::resizePending ne {}} {after idle ::GX::Engine3D::hostResize}
        if {$::GX::Engine3D::pendingBackend ne ""} {
            after idle ::GX::Engine3D::resumeBackend
        }
        if {[llength $::GX::Engine3D::cameraQueue]} {
            after idle ::GX::Engine3D::flushCameraNavigation
        }
    }
    if {[llength $response] != 2} {error "Invalid native renderer reply: $response"}
    if {[lindex $response 0] ne "ok"} {error [lindex $response 1]}
    return [lindex $response 1]
}
proc ::GX::Engine3D::graphicsCheck {} {
    if {$::GX::Engine3D::workerBusy} {error "Wait for the current Native 3D request before checking the renderer"}
    set policy [::GX::native3dGraphicsPolicy]
    set mode [dict get $policy execution]
    if {$mode eq "Auto" && $::GX::Engine3D::workerSoftware} {
        stopWorker
        set ::GX::Engine3D::workerSoftware 0
    }
    if {[catch {set result [rpc [list graphics_probe $policy]]} first]} {
        if {$mode ne "Auto" || $::GX::Engine3D::workerSoftware} {error $first}
        stopWorker
        set ::GX::Engine3D::workerSoftware 1
        if {[catch {set result [rpc [list graphics_probe $policy]]} second]} {
            error "Hardware attempt failed: $first; Mesa software attempt failed: $second"
        }
    }
    return $result
}
proc ::GX::Engine3D::resumeBackend {} {
    variable pendingBackend
    variable pendingSession
    variable workerBusy
    if {$workerBusy || $pendingBackend eq ""} return
    set request $pendingBackend
    set pendingBackend ""
    if {$pendingSession ne $::GX::currentSession} {set pendingSession "";return}
    set pendingSession ""
    if {[catch {{*}$request} problem]} {
        set ::GX::Engine3D::status $problem
        if {$problem ne "Rendering cancelled"} {tk_messageBox -icon error -message $problem}
    }
}
proc ::GX::Engine3D::layerId {prefix} {
    set n 1
    while {[lsearch -exact [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] "${prefix}_$n"] >= 0} {incr n}
    return "${prefix}_$n"
}
proc ::GX::Engine3D::addArtifact {path {kind ""} {scalarArray ""} {isovalues ""} {volumeTransfer ""} {volumeSampleDistance 0.05}} {
    if {$::GX::currentSession eq ""} {error "Open a Session first"}
    if {![file isfile $path]} {error "Geometry source does not exist: $path"}
    set extension [string tolower [string trimleft [file extension $path] .]]
    if {$extension ni {stl obj step stp vtp vtu vti}} {error "Unsupported 3D artifact format: $extension"}
    set sha [::GX::sha256File $path]
    set root [file normalize $::GX::currentSession]
    set source [file normalize $path]
    set sourceHint ""
    set createdArtifact ""
    if {[string match "$root/*" $source]} {
        set relative [string range $source [expr {[string length $root]+1}] end]
    } else {
        set sourceHint $source
        set relative [file join viewer_artifacts "[string range $sha 0 15]_[file tail $path]"]
        set destination [file join $root $relative]
        file mkdir [file dirname $destination]
        if {[file exists $destination]} {
            if {![string equal -nocase [::GX::sha256File $destination] $sha]} {error "Session artifact name collision: $relative"}
        } else {file copy -- $path $destination;set createdArtifact $destination}
    }
    if {$kind eq ""} {set kind [expr {$extension in {vtp vtu vti} ? "surface" : "geometry"}]}
    set id [layerId geometry]
    try {
        set identity [::GX::viewerArtifactRegister $relative]
        ::GX::viewerLayerSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id [dict create \
            kind $kind source_mode artifact resource_path $relative sha256 [dict get $identity sha256] \
            format $extension format_version 1 source_path_hint $sourceHint \
            scalar_array $scalarArray isovalues $isovalues \
            volume_transfer $volumeTransfer volume_sample_distance $volumeSampleDistance \
            layer_order [llength [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]]]
    } on error {problem options} {
        if {$createdArtifact ne ""} {catch {file delete -- $createdArtifact}}
        return -options $options $problem
    }
    return $id
}
proc ::GX::Engine3D::rollbackArtifact {id} {
    if {$id eq ""} return
    if {[lsearch -exact [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $id] < 0} return
    set layer [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id]
    set relative [dict get $layer resource_path]
    set hint [dict get $layer source_path_hint]
    ::GX::viewerLayerRemove [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id
    if {$hint eq "" || ![string match "viewer_artifacts/*" $relative]} return
    foreach other [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] {
        set state [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $other]
        if {[dict get $state source_mode] eq "artifact" && [dict get $state resource_path] eq $relative} return
    }
    catch {file delete -- [file join $::GX::currentSession $relative]}
}
proc ::GX::Engine3D::addArtifactAndRender {path {kind ""} {scalarArray ""} {isovalues ""} {volumeTransfer ""} {volumeSampleDistance 0.05}} {
    set id [addArtifact $path $kind $scalarArray $isovalues $volumeTransfer $volumeSampleDistance]
    set ::GX::Engine3D::pendingAddedLayer $id
    try {rerender} on error {problem options} {
        set ::GX::Engine3D::pendingAddedLayer ""
        rollbackArtifact $id
        catch {refreshLayers}
        return -options $options $problem
    }
    return $id
}
proc ::GX::Engine3D::addDataset {datasetId xId yId zId {kind points} {scalarId ""} {vectorIds {}} {radiusId ""} {opacityId ""}} {
    set payload [::GX::sessionInspectionDatasetPayload $datasetId]
    set contract [::GX::datasetField $datasetId contract {}]
    if {$contract in {geometry.mesh model.cad}} {
        if {[dict get $payload format] ni {step stp stl obj vtp vtu}} {error "Unsupported canonical geometry format for Dataset '$datasetId'"}
        set id [addArtifact [dict get $payload path]]
        try {
            set layer [::GX::viewerLayerGet [ownerModule] [ownerProvider] $id]
            dict set layer dataset_id $datasetId;dict set layer source_dataset_id $datasetId;dict set layer source_dataset_sha256 [dict get $payload sha256]
            ::GX::viewerLayerSet [ownerModule] [ownerProvider] $id $layer
            set metadata [::GX::datasetMetadataRead $::GX::currentSession $datasetId]
            set ::GX::Engine3D::status "Loaded complete $datasetId geometry in declared [::GX::datasetPublicationV2DictDefault $metadata geometry.working_unit {undeclared}] file coordinates"
        } on error {message options} {::GX::viewerLayerRemove [ownerModule] [ownerProvider] $id;return -options $options $message}
        return $id
    }
    if {$kind ni {points trajectory}} {error "Dataset 3D kind must be points or trajectory"}
    if {[dict get $payload format] ne "csv"} {error "Dataset point/trajectory layers require a canonical CSV payload"}
    if {[llength $vectorIds] && [llength $vectorIds] != 3} {error "Vector needs three Dataset variable IDs"}
    foreach variableId [concat [list $xId $yId $zId $scalarId $radiusId $opacityId] $vectorIds] {
        if {$variableId ne ""} {::GX::viewerDatasetVariableCheck $datasetId $variableId}
    }
    set id [layerId dataset]
    set fields [dict create kind $kind source_mode dataset dataset_id $datasetId \
        x_variable_id $xId y_variable_id $yId z_variable_id $zId \
        source_dataset_id $datasetId source_dataset_sha256 [dict get $payload sha256] \
        layer_order [llength [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]]]
    if {$scalarId ne ""} {dict set fields scalar_array $scalarId}
    if {$radiusId ne ""} {dict set fields radius_array $radiusId}
    if {$opacityId ne ""} {dict set fields opacity_array $opacityId}
    try {
        ::GX::viewerLayerSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id $fields
        if {$scalarId ne ""} {
            ::GX::viewerAttributeSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id selected_scalar \
                [dict create kind scalar variable_ids $scalarId]
        }
        if {[llength $vectorIds]} {
            ::GX::viewerAttributeSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id selected_vector \
                [dict create kind vector variable_ids [join $vectorIds {;}]]
        }
    } on error {problem options} {
        ::GX::viewerLayerRemove [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id
        return -options $options $problem
    }
    return $id
}
proc ::GX::Engine3D::column {datasetId variableId} {
    if {$variableId eq ""} {return ""}
    set variable [::GX::datasetVariableById $datasetId $variableId]
    set position [dict get $variable canonical_position]
    if {![string is integer -strict $position] || $position < 1} {
        error "Dataset variable '$variableId' has no canonical CSV column"
    }
    return [expr {$position-1}]
}
proc ::GX::Engine3D::preparedScene {scene} {return [::GX::native3DScenePrepare $scene]}
proc ::GX::native3DScenePrepare {scene} {
    set layers [dict get $scene layers]
    dict for {id layer} $layers {
        if {[::GX::datasetPublicationV2DictDefault $layer texture {}] ne {}} {
            set descriptor [::GX::native3DLayerTextureValidate [dict get $layer texture] $layer]
            set resource [dict get $descriptor resource]
            set relative [::GX::_native3DPlanarArtifact $resource]
            dict set descriptor source_path [::GX::viewerArtifactResolve $relative [dict get $resource sha256]]
            dict set layer texture $descriptor
            dict set layers $id $layer
        }
        if {[dict get $layer source_mode] ne "dataset"} continue
        set ds [dict get $layer dataset_id]
        foreach axis {x y z} {
            dict set layer ${axis}_column [::GX::Engine3D::column $ds [dict get $layer ${axis}_variable_id]]
        }
        set scalarId [dict get $layer scalar_array]
        if {$scalarId ne ""} {
            if {![catch {column $ds $scalarId} c]} {dict set layer scalar_column $c}
        }
        set radiusId [dict get $layer radius_array]
        if {$radiusId ne ""} {dict set layer radius_column [::GX::Engine3D::column $ds $radiusId]}
        set opacityId [dict get $layer opacity_array]
        if {$opacityId ne ""} {dict set layer opacity_column [::GX::Engine3D::column $ds $opacityId]}
        dict for {attributeId attribute} [dict get $layer attributes] {
            set ids [::GX::splitList [dict get $attribute variable_ids]]
            if {[dict get $attribute kind] eq "scalar" && [llength $ids] == 1} {
                dict set layer scalar_column [::GX::Engine3D::column $ds [lindex $ids 0]]
            } elseif {[dict get $attribute kind] eq "vector" && [llength $ids] == 3} {
                set columns {}
                foreach v $ids {lappend columns [::GX::Engine3D::column $ds $v]}
                dict set layer vector_columns [join $columns {;}]
            }
        }
        dict set layers $id $layer
    }
    dict set scene layers $layers
    return $scene
}
proc ::GX::Engine3D::tempPng {} {
    set dir [file join [::GX::configurationCacheDirectory] gx3de_viewer]
    file mkdir $dir
    return [file join $dir "render_[pid].png"]
}
proc ::GX::Engine3D::pngComplete {path} {
    if {![file isfile $path] || [file size $path] < 68} {return 0}
    set fd [open $path rb]
    try {
        fconfigure $fd -translation binary -encoding binary
        binary scan [read $fd 8] H* magic
        seek $fd -12 end
        set trailer [read $fd 12]
    } finally {::close $fd}
    return [expr {$magic eq "89504e470d0a1a0a" && [string range $trailer 4 7] eq "IEND"}]
}
proc ::GX::Engine3D::displayNativePng {path} {
    variable window
    variable photo
    variable lastPng
    if {![pngComplete $path]} {error "Native renderer did not produce a complete PNG"}
    set lastPng $path
    if {[winfo exists $window.canvas]} {
        if {$photo ne ""} {image delete $photo}
        set photo [image create photo -file $path]
        $window.canvas delete all
        $window.canvas create image 0 0 -anchor nw -image $photo -tags native_image
        $window.canvas configure -scrollregion [list 0 0 [image width $photo] [image height $photo]]
    }
}
proc ::GX::Engine3D::gizmoImageRequest {request} {
    set destination [tempPng]
    set staged "${destination}.stage.[pid].[clock clicks].png"
    try {
        set result [rpc [concat $request [list $staged]]]
        if {![pngComplete $staged]} {error "Native manipulator did not produce a complete PNG"}
        file rename -force -- $staged $destination
    } finally {catch {file delete -- $staged}}
    displayNativePng $destination
    return $result
}
proc ::GX::Engine3D::renderScene {scene {destination ""} {stage full}} {
    variable window
    variable photo
    variable lastPng
    variable status
    variable latestPick
    variable cancelRequested
    if {$destination eq ""} {set destination [tempPng]}
    set prepared [preparedScene $scene]
    set cacheRoot [file join [::GX::configurationCacheDirectory] gx3de_viewer derived]
    file mkdir $cacheRoot
    dict set prepared cache_root $cacheRoot
    dict set prepared session_namespace [file normalize $::GX::currentSession]
    set graphics [::GX::native3dGraphicsPolicy]
    dict set prepared graphics_policy $graphics
    set status "Rendering..."
    set cancelRequested 0
    set stagedPng "${destination}.stage.[pid].[clock clicks].png"
    lassign [hostViewportSize] viewportWidth viewportHeight
    set ::GX::Engine3D::renderedSize [list $viewportWidth $viewportHeight]
    try {
    if {[catch {set result [rpc [list render $prepared $stagedPng $viewportWidth $viewportHeight $stage]]} first] && \
            [dict get $graphics execution] eq "Auto" && !$::GX::Engine3D::workerSoftware && \
            [regexp {^(render scene:|create pixel target:|Native renderer worker)} $first]} {
            if {$cancelRequested} {error "Rendering cancelled"}
            if {$first eq "Native renderer request is already running"} {error $first}
            stopWorker
            catch {file delete -- $stagedPng}
            set ::GX::Engine3D::workerSoftware 1
            set status "Retrying with Mesa llvmpipe..."
            if {[catch {set result [rpc [list render $prepared $stagedPng $viewportWidth $viewportHeight $stage]]} retry]} {
                error "Native render failed ($first); Mesa llvmpipe retry failed: $retry"
            }
        } elseif {![info exists result]} {
            if {$cancelRequested} {error "Rendering cancelled"}
            error $first
        }
        if {![pngComplete $stagedPng]} {
            error "Native renderer did not produce a complete PNG"
        }
        file rename -force -- $stagedPng $destination
    } finally {
        catch {file delete -- $stagedPng}
    }
    set lastPng $destination
    set ::GX::Engine3D::lastGraphicsPolicy $graphics
    set ::GX::Engine3D::gizmoActive 0
    set latestPick [dict create]
    if {[dict get $result auto_fitted]} {
        set fields [dict create]
        foreach key {camera_position camera_target camera_up} {
            dict set fields $key [join [dict get $result $key] {;}]
        }
        ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge \
            [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $fields]
        set ::GX::Engine3D::cameraPosition [dict get $fields camera_position]
        set ::GX::Engine3D::cameraTarget [dict get $fields camera_target]
        set ::GX::Engine3D::cameraUp [dict get $fields camera_up]
    }
    displayNativePng $destination
    set budget [dict get $graphics gpu_budget_mib]
    set budgetText [expr {$budget eq "auto" ? "unlimited" : "$budget MiB"}]
    set status "[string totitle $stage] ready: [dict get $result object_count] native objects; [dict get $result backend] [dict get $result execution] ([dict get $result device]); GPU estimate [expr {[dict get $result gpu_estimated_bytes]/1048576}] MiB / $budgetText ([dict get $result gpu_accounting])"
    set sceneState [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    if {[dict get $sceneState active_timeline_id] ne "" &&
        $::GX::Engine3D::timelineTimer eq "" && [winfo exists $window]} {
        foreach timeline [dict get $sceneState timeline_definitions] {
            if {[dict get $timeline id] eq [dict get $sceneState active_timeline_id] &&
                [dict get $timeline state] eq "playing"} {
                set ::GX::Engine3D::timelineLastTick [clock milliseconds]
                set ::GX::Engine3D::timelineTimer [after 50 ::GX::Engine3D::timelineTick]
                break
            }
        }
    }
    return $result
}
proc ::GX::Engine3D::needsProgressive {scene} {
    dict for {id layer} [dict get $scene layers] {
        if {[dict get $layer source_mode] eq "artifact" && [dict get $layer format] in {stl obj step stp}} {return 1}
    }
    return 0
}
proc ::GX::Engine3D::completeProgressive {generation session {newLayer ""}} {
    variable renderGeneration
    variable status
    if {$generation != $renderGeneration || $session ne $::GX::currentSession || \
        ![winfo exists $::GX::Engine3D::window]} return
    if {$::GX::Engine3D::workerBusy} {
        after 80 [list ::GX::Engine3D::completeProgressive $generation $session $newLayer]
        return
    }
    set status "Preparing full native geometry..."
    if {[catch {renderScene [::GX::viewerSceneResolve [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] "" full} problem]} {
        if {$newLayer ne "" && $problem ne "Rendering cancelled"} {
            catch {rollbackArtifact $newLayer}
            catch {refreshLayers}
            catch {rerender}
        }
        if {$problem ne "Rendering cancelled"} {set status $problem;tk_messageBox -icon error -message $problem}
    }
    if {$::GX::Engine3D::activeNewLayer eq $newLayer} {set ::GX::Engine3D::activeNewLayer ""}
}
proc ::GX::Engine3D::backend {action scene} {
    variable scientificDocumentId;variable scientificDocumentSession
    variable renderGeneration
    set addedSourceId ""
    if {$::GX::currentSession eq ""} {error "Open a Session before using the Native 3D Engine Viewer"}
    if {$::GX::Engine3D::workerBusy} {
        set ::GX::Engine3D::pendingBackend [list ::GX::Engine3D::backend $action $scene]
        set ::GX::Engine3D::pendingSession $::GX::currentSession
        cancelRendering 1
        return $::GX::Engine3D::window
    }
    set provider [dict get $scene provider]
    setHostIdentity [dict get $provider module_id] [dict get $provider viewer_id]
    if {$action eq {open}} {
        set scientificDocumentId [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $scene open_context {}] scientific_document_id {}]
        set scientificDocumentSession [::GX::interactiveDocumentSessionToken]
    }
    if {[info exists scientificDocumentId]&&$scientificDocumentId ne {}} {
        if {$scientificDocumentSession ne [::GX::interactiveDocumentSessionToken]} {error {Scientific representation belongs to a previous Session; reopen it explicitly}}
        set document [::GX::native3DScientificDocumentRead $scientificDocumentId]
        dict set scene scientific_figure [dict get $document scientific_figure]
    }
    if {$action eq "open" && [dict exists $scene open_context source_path]} {
        set source [dict get $scene open_context source_path]
        if {![file isfile $source]} {error "Viewer source does not exist: $source"}
        set sha [::GX::sha256File $source]
        set already 0
        dict for {id layer} [dict get $scene layers] {
            if {[dict get $layer source_mode] eq "artifact" && \
                [string equal -nocase [dict get $layer sha256] $sha]} {set already 1;break}
        }
        if {!$already} {
            set id [addArtifact $source]
            set addedSourceId $id
            foreach datasetId [::GX::datasetRegistryIds] {
                if {[catch {set payload [::GX::sessionInspectionDatasetPayload $datasetId]}]} continue
                if {[file normalize [dict get $payload path]] eq [file normalize $source]} {
                    set layer [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id]
                    ::GX::viewerLayerSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id [dict merge $layer \
                        [dict create source_dataset_id $datasetId \
                            source_dataset_sha256 [dict get $payload sha256]]]
                    break
                }
            }
            set scene [::GX::viewerSceneResolve [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
        }
    }
    panel [expr {$action eq "open"}]
    incr renderGeneration
    set transactionLayer [expr {$addedSourceId ne "" ? $addedSourceId : $::GX::Engine3D::pendingAddedLayer}]
    set ::GX::Engine3D::activeNewLayer $transactionLayer
    try {
        if {[::GX::configurationGet viewers.native3d.normal_quality] eq "Preview"} {
            renderScene $scene "" preview
            set ::GX::Engine3D::pendingAddedLayer ""
            set ::GX::Engine3D::activeNewLayer ""
        } elseif {[needsProgressive $scene]} {
            renderScene $scene "" preview
            set ::GX::Engine3D::pendingAddedLayer ""
            after 80 [list ::GX::Engine3D::completeProgressive $renderGeneration $::GX::currentSession $transactionLayer]
        } else {renderScene $scene;set ::GX::Engine3D::pendingAddedLayer "";set ::GX::Engine3D::activeNewLayer ""}
    } on error {problem options} {
        if {$transactionLayer ne ""} {rollbackArtifact $transactionLayer}
        set ::GX::Engine3D::pendingAddedLayer ""
        set ::GX::Engine3D::activeNewLayer ""
        catch {refreshLayers}
        return -options $options $problem
    }
    if {[info exists scientificDocumentId]&&$scientificDocumentId ne {}} {::GX::PlotDatasetAPIv4::saveInteractivePresentation $scientificDocumentId}
    refreshLayers
    return $::GX::Engine3D::window
}
proc ::GX::Engine3D::rerender {} {
    variable scientificDocumentId
    if {[info exists scientificDocumentId]&&$scientificDocumentId ne {}} {
        return [backend rerender [::GX::viewerSceneResolve [ownerModule] [ownerProvider]]]
    }
    return [::GX::viewerRerender [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
}
proc ::GX::Engine3D::latestPick {} {return $::GX::Engine3D::latestPick}
proc ::GX::Engine3D::markerFromPick {{id ""}} {
    variable latestPick
    if {![dict exists $latestPick hit] || ![dict get $latestPick hit]} {error "Pick a rendered object point first"}
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set markers [dict get $scene marker_definitions]
    if {$id eq ""} {set id "marker_[expr {[llength $markers]+1}]"}
    set marker [dict create id $id layer_id [dict get $latestPick layer_id] \
        occurrence_index [dict get $latestPick occurrence_index] \
        local_point [join [dict get $latestPick local_point] {;}] kind point \
        size_pixels 8 color {1;0.9;0.1} visible 1]
    lappend markers $marker
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict replace $scene marker_definitions $markers]
    rerender
    return $id
}
proc ::GX::Engine3D::addMeasurement {markerA markerB {kind distance} {markerC ""} {id ""}} {
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set definitions [dict get $scene measurement_definitions]
    if {$id eq ""} {set id "measurement_[expr {[llength $definitions]+1}]"}
    set definition [dict create id $id kind $kind marker_a $markerA marker_b $markerB \
        visible 1 show_value 1 color {1;0.95;0.2} size_pixels 7 line_width 2]
    if {$kind eq "angle"} {dict set definition marker_c $markerC}
    lappend definitions $definition
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict replace $scene measurement_definitions $definitions]
    rerender
    return $id
}
proc ::GX::Engine3D::addCurve {sourceLayer kind origin normal uAxis {id ""} {joinTolerance 0.001} {occurrenceIndex 0}} {
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set definitions [dict get $scene curve_definitions]
    if {$id eq ""} {set id "${kind}_[expr {[llength $definitions]+1}]"}
    set definition [dict create id $id kind $kind source_layer $sourceLayer \
        occurrence_index $occurrenceIndex origin $origin normal $normal u_axis $uAxis \
        visible 1 color {1;0.8;0.15} line_width 2 opacity 1 \
        join_tolerance $joinTolerance]
    lappend definitions $definition
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict replace $scene curve_definitions $definitions]
    rerender
    return $id
}
proc ::GX::Engine3D::addSelectedCurve {} {
    if {$::GX::Engine3D::selectedLayer eq ""} {error "Select a source layer first"}
    return [addCurve $::GX::Engine3D::selectedLayer $::GX::Engine3D::curveKind \
        $::GX::Engine3D::planeOrigin $::GX::Engine3D::planeNormal \
        $::GX::Engine3D::planeU "" $::GX::Engine3D::curveTolerance]
}
proc ::GX::Engine3D::pick {x y} {
    variable latestPick
    variable status
    if {$::GX::Engine3D::workerBusy} {
        set status "Rendering is still in progress; pick after the image settles"
        return [dict create hit 0]
    }
    set latestPick [rpc [list pick $x $y]]
    dict set latestPick viewport_xy [list $x $y]
    if {[dict get $latestPick hit]} {
        set status "Picked [dict get $latestPick layer_id] at [dict get $latestPick world_point]"
        set ::GX::Engine3D::selectedLayer [dict get $latestPick layer_id]
        # Native picking installs its selection anchor AFTER computing the hit.
        # Present that retained scene explicitly; unchanged canvas dimensions
        # must not leave the previous selected object's frame onscreen.
        set ::GX::Engine3D::selectionFrameDirty 1
        if {$::GX::Engine3D::selectionHook ne {}} {uplevel #0 [list {*}$::GX::Engine3D::selectionHook $latestPick]}
        hostResize
    } else {set status "No geometry at $x,$y"}
    return $latestPick
}
proc ::GX::Engine3D::screenshot {path {width 960} {height 640}} {
    if {$path eq ""} {error "Screenshot path is required"}
    if {![string is integer -strict $width] || ![string is integer -strict $height] || \
        $width < 16 || $height < 16 || $width > 4096 || $height > 4096} {
        error "PNG export dimensions must be 16..4096 pixels per side"
    }
    if {$::GX::Engine3D::workerBusy} {error "Wait for current rendering before exporting"}
    if {$::GX::Engine3D::lastPng eq "" || $::GX::Engine3D::lastGraphicsPolicy ne [::GX::native3dGraphicsPolicy]} {rerender}
    set staged "${path}.stage.[pid].[clock clicks].png"
    try {
        rpc [list export_png $staged $width $height]
        if {![pngComplete $staged]} {error "Native exporter did not produce a complete PNG"}
        file rename -force -- $staged $path
    } finally {catch {file delete -- $staged}}
    return $path
}
proc ::GX::Engine3D::chooseScreenshot {} {
    set path [tk_getSaveFile -defaultextension .png -filetypes {{PNG {.png}}}]
    if {$path ne ""} {
        if {[catch {screenshot $path $::GX::Engine3D::exportWidth $::GX::Engine3D::exportHeight} err]} {tk_messageBox -icon error -message $err}
    }
}
proc ::GX::Engine3D::setLayerPresentation {layerId fields} {
    set existing [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $layerId]
    dict for {key value} $fields {if {[dict exists $existing $key]&&$value eq [dict get $existing $key]} {dict unset fields $key}}
    if {$fields eq {}} {return $existing}
    if {$::GX::Engine3D::editHook ne {}} {uplevel #0 [list {*}$::GX::Engine3D::editHook presentation $layerId $fields]}
    set updated [::GX::viewerLayerSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $layerId [dict merge $existing $fields]]
    set selective [expr {$::GX::Engine3D::lastPng ne {}&&$::GX::Engine3D::worker ne {}}]
    foreach key [dict keys $fields] {if {$key ni {visible opacity base_color line_width point_size}} {set selective 0}}
    if {$selective} {
        set path [tempPng]
        try {rpc [list presentation $layerId $fields $path];displayNativePng $path} on error {m o} {
            ::GX::viewerLayerSet [ownerModule] [ownerProvider] $layerId $existing
            return -options $o $m
        }
    } else {rerender}
    return $updated
}
proc ::GX::Engine3D::setCamera {position target up} {
    set fields [dict merge [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] \
        [dict create camera_position $position camera_target $target camera_up $up]]
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $fields
    rerender
}
proc ::GX::Engine3D::vadd {a b} {
    lassign $a ax ay az;lassign $b bx by bz
    return [list [expr {$ax+$bx}] [expr {$ay+$by}] [expr {$az+$bz}]]
}
proc ::GX::Engine3D::vsub {a b} {
    lassign $a ax ay az;lassign $b bx by bz
    return [list [expr {$ax-$bx}] [expr {$ay-$by}] [expr {$az-$bz}]]
}
proc ::GX::Engine3D::vmul {a s} {
    lassign $a x y z;return [list [expr {$x*$s}] [expr {$y*$s}] [expr {$z*$s}]]
}
proc ::GX::Engine3D::vdot {a b} {
    lassign $a ax ay az;lassign $b bx by bz
    return [expr {$ax*$bx+$ay*$by+$az*$bz}]
}
proc ::GX::Engine3D::vcross {a b} {
    lassign $a ax ay az;lassign $b bx by bz
    return [list [expr {$ay*$bz-$az*$by}] [expr {$az*$bx-$ax*$bz}] [expr {$ax*$by-$ay*$bx}]]
}
proc ::GX::Engine3D::vunit {a} {
    set length [expr {sqrt([vdot $a $a])}]
    if {$length < 1e-12} {error "Camera axis is degenerate"}
    return [vmul $a [expr {1.0/$length}]]
}
proc ::GX::Engine3D::vrotate {value axis angle} {
    set axis [vunit $axis]
    set c [expr {cos($angle)}];set s [expr {sin($angle)}]
    return [vadd [vadd [vmul $value $c] [vmul [vcross $axis $value] $s]] \
        [vmul $axis [expr {[vdot $axis $value]*(1-$c)}]]]
}
proc ::GX::Engine3D::cameraVectors {} {
    set view [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set position [split [dict get $view camera_position] {;}]
    set target [split [dict get $view camera_target] {;}]
    set up [split [dict get $view camera_up] {;}]
    return [list $position $target $up]
}
proc ::GX::Engine3D::cameraCommit {position target up} {
    set view [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge $view [dict create \
        camera_position [join $position {;}] camera_target [join $target {;}] \
        camera_up [join $up {;}]]]
    set ::GX::Engine3D::cameraPosition [join $position {;}]
    set ::GX::Engine3D::cameraTarget [join $target {;}]
    set ::GX::Engine3D::cameraUp [join $up {;}]
    rerender
}
proc ::GX::Engine3D::cameraOrbit {dx dy} {
    cameraNavigate orbit $dx $dy
}
proc ::GX::Engine3D::cameraPan {dx dy} {
    cameraNavigate pan $dx $dy
}
proc ::GX::Engine3D::cameraZoom {steps} {
    cameraNavigate zoom $steps 0
}
proc ::GX::Engine3D::cameraNavigate {mode deltaX deltaY} {
    if {$::GX::Engine3D::workerBusy || [llength $::GX::Engine3D::cameraQueue]} {
        if {$::GX::Engine3D::cameraQueueSession ne $::GX::currentSession} {
            set ::GX::Engine3D::cameraQueue {}
            set ::GX::Engine3D::cameraQueueSession $::GX::currentSession
        }
        set queue $::GX::Engine3D::cameraQueue
        if {[llength $queue] && [lindex [lindex $queue end] 0] eq $mode} {
            lassign [lindex $queue end] ignored oldX oldY
            lset queue end [list $mode [expr {$oldX+$deltaX}] [expr {$oldY+$deltaY}]]
        } else {
            lappend queue [list $mode $deltaX $deltaY]
        }
        set ::GX::Engine3D::cameraQueue $queue
        if {!$::GX::Engine3D::workerBusy} {after idle ::GX::Engine3D::flushCameraNavigation}
        return
    }
    cameraNavigateNow $mode $deltaX $deltaY
}
proc ::GX::Engine3D::flushCameraNavigation {} {
    if {$::GX::Engine3D::workerBusy || ![llength $::GX::Engine3D::cameraQueue]} return
    if {$::GX::Engine3D::cameraQueueSession ne $::GX::currentSession ||
        ![winfo exists $::GX::Engine3D::window]} {
        set ::GX::Engine3D::cameraQueue {}
        return
    }
    set next [lindex $::GX::Engine3D::cameraQueue 0]
    set ::GX::Engine3D::cameraQueue [lrange $::GX::Engine3D::cameraQueue 1 end]
    showError [list ::GX::Engine3D::cameraNavigateNow {*}$next]
    if {[llength $::GX::Engine3D::cameraQueue]} {after idle ::GX::Engine3D::flushCameraNavigation}
}
proc ::GX::Engine3D::cameraNavigateNow {mode deltaX deltaY} {
    if {$::GX::Engine3D::lastPng eq ""} {rerender}
    set result [gizmoImageRequest [list navigate $mode $deltaX $deltaY]]
    set fields [dict create]
    foreach key {camera_position camera_target camera_up} {
        dict set fields $key [join [dict get $result $key] {;}]
    }
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge \
        [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $fields]
    set ::GX::Engine3D::cameraPosition [dict get $fields camera_position]
    set ::GX::Engine3D::cameraTarget [dict get $fields camera_target]
    set ::GX::Engine3D::cameraUp [dict get $fields camera_up]
    set ::GX::Engine3D::latestPick [dict create]
    set ::GX::Engine3D::status "Full ready: camera $mode"
}
proc ::GX::Engine3D::selectGizmo {} {
    if {$::GX::Engine3D::selectedLayer eq ""} {error "Select one layer to manipulate"}
    if {$::GX::Engine3D::workerBusy} {error "Wait for the current render before selecting the manipulator"}
    incr ::GX::Engine3D::renderGeneration
    gizmoImageRequest [list gizmo_select $::GX::Engine3D::selectedLayer $::GX::Engine3D::gizmoSpace \
        $::GX::Engine3D::gizmoFamilies $::GX::Engine3D::gizmoPivot \
        $::GX::Engine3D::gizmoPivotMarker $::GX::Engine3D::gizmoSizePixels]
    set ::GX::Engine3D::gizmoActive 1
    set ::GX::Engine3D::status "Manipulator active on $::GX::Engine3D::selectedLayer; drag a colored handle"
}
proc ::GX::Engine3D::gizmoMotion {x y} {
    if {$::GX::Engine3D::dragMode ne "gizmo" || $::GX::Engine3D::workerBusy} return
    set now [clock milliseconds]
    if {$now-$::GX::Engine3D::gizmoLastUpdate < 45} return
    set ::GX::Engine3D::gizmoLastUpdate $now
    set transaction [gestureReceipt]
    if {[catch {set result [gizmoImageRequest [list gizmo_update $x $y]]} problem options]} {
        if {[gestureCurrent $transaction]} {abortGizmo}
        return -options $options $problem
    }
    set ::GX::Engine3D::status "Moving [dict get $result handle]: [dict get $result translation_world]"
}
proc ::GX::Engine3D::abortGizmo {} {
    if {[catch {gestureReceipt} transaction] || ![gestureCurrent $transaction]} return
    set ::GX::Engine3D::pendingGizmoEnd ""
    if {$::GX::Engine3D::worker ne "" && !$::GX::Engine3D::workerBusy} {
        catch {rpc [list gizmo_end 0]}
    }
    if {![gestureCurrent $transaction]} return
    set ::GX::Engine3D::gizmoActive 0
    set ::GX::Engine3D::dragMode ""
    catch {rerender}
}
proc ::GX::Engine3D::finishGizmo {x y} {
    if {$::GX::Engine3D::workerBusy} {
        set ::GX::Engine3D::pendingGizmoEnd [list $x $y]
        after 30 ::GX::Engine3D::completeGizmoEnd
        return
    }
    set transaction [gestureReceipt]
    try {
        gizmoImageRequest [list gizmo_update $x $y]
        if {![gestureCurrent $transaction]} return
        set result [rpc [list gizmo_end 1]]
        if {![gestureCurrent $transaction]} {gestureNativeEnded $transaction;return}
        set layerId [dict get $result layer_id]
        set layer [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $layerId]
        set original [split [dict get $layer local_transform] {;}]
        if {$original eq {} || $original eq {{}}} {set original {1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1}}
        set changed 0;foreach prior $original current [dict get $result matrix] {if {$prior!=$current} {set changed 1;break}}
        if {!$changed} {
            set ::GX::Engine3D::status {Manipulator released without a geometry change}
        } elseif {$::GX::Engine3D::editHook ne {}} {
            uplevel #0 [list {*}$::GX::Engine3D::editHook transform $layerId [dict create matrix [dict get $result matrix]]]
        } else {
            ::GX::viewerLayerSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $layerId \
                [dict replace $layer local_transform [join [dict get $result matrix] {;}]]
        }
    } on error {problem options} {
        if {[gestureCurrent $transaction]} {abortGizmo}
        return -options $options $problem
    } finally {
        if {[gestureCurrent $transaction]} {set ::GX::Engine3D::dragMode {}}
    }
    set ::GX::Engine3D::gizmoActive 0
    rerender
}
proc ::GX::Engine3D::completeGizmoEnd {} {
    if {$::GX::Engine3D::pendingGizmoEnd eq ""} return
    if {!$::GX::Engine3D::gizmoActive} {set ::GX::Engine3D::pendingGizmoEnd "";return}
    if {$::GX::Engine3D::workerBusy} {after 30 ::GX::Engine3D::completeGizmoEnd;return}
    lassign $::GX::Engine3D::pendingGizmoEnd x y
    set ::GX::Engine3D::pendingGizmoEnd ""
    showError [list ::GX::Engine3D::finishGizmo $x $y]
}
proc ::GX::Engine3D::beginCanvasDrag {x y} {
    variable gestureStarting;variable pendingDragEnd;variable pendingDragJob;variable gestureGeneration
    if {$::GX::Engine3D::pendingGestureCancel ne {}||$::GX::Engine3D::workerBusy||$gestureStarting} {set ::GX::Engine3D::status "Wait for the current Native3D transaction before starting a gesture";return}
    if {$pendingDragJob ne {}} {after cancel $pendingDragJob;set pendingDragJob {}}
    set pendingDragEnd {};incr gestureGeneration;set gestureStarting 1
    try {beginCanvasDragReady $x $y} finally {
        set gestureStarting 0
        if {$pendingDragEnd ne {}} {set pendingDragJob [after idle ::GX::Engine3D::flushDragEnd]}
    }
}
proc ::GX::Engine3D::beginCanvasDragReady {x y} {
    if {$::GX::Engine3D::lastPng ne "" && !$::GX::Engine3D::workerBusy} {
        set region [rpc [list navcube_pick $x $y]]
        if {$region > 0} {
            set result [gizmoImageRequest [list navcube_click $x $y]]
            set fields [dict create]
            foreach key {camera_position camera_target camera_up} {
                dict set fields $key [join [dict get $result $key] {;}]
            }
            ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge \
                [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $fields]
            set ::GX::Engine3D::cameraPosition [dict get $fields camera_position]
            set ::GX::Engine3D::cameraTarget [dict get $fields camera_target]
            set ::GX::Engine3D::cameraUp [dict get $fields camera_up]
            set ::GX::Engine3D::latestPick [dict create]
            set ::GX::Engine3D::dragMode ""
            set ::GX::Engine3D::status "Navigation Cube region [dict get $result region]"
            return
        }
    }
    beginDrag orbit $x $y
}
proc ::GX::Engine3D::beginDrag {mode x y} {
    if {$mode eq "orbit" && $::GX::Engine3D::planeMode} {
        if {$::GX::Engine3D::workerBusy} {error "Wait for the current render before dragging a plane"}
        rpc [list plane_begin $::GX::Engine3D::planeTarget $::GX::Engine3D::planeAction \
            $::GX::Engine3D::planeHandle $::GX::Engine3D::planeSlot $x $y]
        set mode plane
        set ::GX::Engine3D::planeLastUpdate 0
        set ::GX::Engine3D::status "Dragging $::GX::Engine3D::planeTarget $::GX::Engine3D::planeAction"
    }
    if {$mode eq "orbit" && $::GX::Engine3D::gizmoActive && !$::GX::Engine3D::workerBusy} {
        set handle [rpc [list gizmo_begin $x $y]]
        if {$handle > 0} {set mode gizmo;set ::GX::Engine3D::status "Dragging manipulator handle $handle"}
    }
    set ::GX::Engine3D::dragMode $mode
    set ::GX::Engine3D::dragX $x
    set ::GX::Engine3D::dragY $y
    set ::GX::Engine3D::dragRenderX $x
    set ::GX::Engine3D::dragRenderY $y
    set ::GX::Engine3D::cameraLastUpdate 0
}
proc ::GX::Engine3D::planeMotion {x y} {
    if {$::GX::Engine3D::dragMode ne "plane" || $::GX::Engine3D::workerBusy} return
    set now [clock milliseconds]
    if {$now-$::GX::Engine3D::planeLastUpdate < 45} return
    set ::GX::Engine3D::planeLastUpdate $now
    gizmoImageRequest [list plane_update $x $y]
}
proc ::GX::Engine3D::finishPlane {x y} {
    if {$::GX::Engine3D::workerBusy} {error "Wait for plane rendering to finish"}
    set transaction [gestureReceipt]
    try {
        gizmoImageRequest [list plane_update $x $y]
        if {![gestureCurrent $transaction]} return
        set result [rpc [list plane_end 1]]
        if {![gestureCurrent $transaction]} {gestureNativeEnded $transaction;return}
    } on error {problem options} {
        if {[gestureCurrent $transaction]} {catch {rpc [list plane_end 0]}}
        return -options $options $problem
    } finally {
        if {[gestureCurrent $transaction]} {set ::GX::Engine3D::dragMode {}}
    }
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    switch -- $::GX::Engine3D::planeTarget {
        working {
            set ::GX::Engine3D::planeOrigin [join [dict get $result origin] {;}]
            set ::GX::Engine3D::planeNormal [join [dict get $result normal] {;}]
            set ::GX::Engine3D::planeU [join [dict get $result u_axis] {;}]
            dict set scene working_plane_origin $::GX::Engine3D::planeOrigin
            dict set scene working_plane_normal $::GX::Engine3D::planeNormal
            dict set scene working_plane_u_axis $::GX::Engine3D::planeU
        }
        clip {
            set planes [split $::GX::Engine3D::clipping {;}]
            lset planes $::GX::Engine3D::planeSlot [join [dict get $result equation] {,}]
            set ::GX::Engine3D::clipping [join $planes {;}]
            dict set scene clipping_planes $::GX::Engine3D::clipping
        }
        box {
            set ::GX::Engine3D::clipBox [join [dict get $result bounds] {;}]
            dict set scene clip_box $::GX::Engine3D::clipBox
        }
    }
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $scene
    set ::GX::Engine3D::status "Plane/clip drag saved in Session scene"
    rerender
}
proc ::GX::Engine3D::cameraMotion {x y} {
    set mode $::GX::Engine3D::dragMode
    if {$mode ni {orbit pan} || $::GX::Engine3D::workerBusy} return
    set now [clock milliseconds]
    if {$now-$::GX::Engine3D::cameraLastUpdate < 45} return
    set dx [expr {$x-$::GX::Engine3D::dragRenderX}]
    set dy [expr {$y-$::GX::Engine3D::dragRenderY}]
    if {abs($dx)+abs($dy) < 3} return
    if {$mode eq "orbit"} {cameraOrbit $dx $dy} else {cameraPan $dx $dy}
    set ::GX::Engine3D::dragRenderX $x
    set ::GX::Engine3D::dragRenderY $y
    set ::GX::Engine3D::cameraLastUpdate $now
}
proc ::GX::Engine3D::endDrag {x y} {
    variable pendingDragEnd;variable pendingDragJob
    if {$::GX::Engine3D::pendingGestureCancel ne {}} return
    if {$::GX::Engine3D::gestureStarting||$::GX::Engine3D::workerBusy} {
        set pendingDragEnd [dict create x $x y $y gesture $::GX::Engine3D::gestureGeneration worker $::GX::Engine3D::workerGeneration session [::GX::interactiveDocumentSessionToken]]
        if {!$::GX::Engine3D::gestureStarting&&$pendingDragJob eq {}} {set pendingDragJob [after 30 ::GX::Engine3D::flushDragEnd]}
        return
    }
    set dx [expr {$x-$::GX::Engine3D::dragX}]
    set dy [expr {$y-$::GX::Engine3D::dragY}]
    set mode $::GX::Engine3D::dragMode
    if {$mode eq "plane"} {finishPlane $x $y;return}
    if {$mode eq "gizmo"} {finishGizmo $x $y;return}
    set ::GX::Engine3D::dragMode ""
    if {[expr {abs($dx)+abs($dy)}] < 4} {
        if {$mode eq "orbit"} {pick $x $y}
    } elseif {$mode in {orbit pan}} {
        set finalX [expr {$x-$::GX::Engine3D::dragRenderX}]
        set finalY [expr {$y-$::GX::Engine3D::dragRenderY}]
        if {abs($finalX)+abs($finalY) >= 1} {
            if {$mode eq "orbit"} {cameraOrbit $finalX $finalY} else {cameraPan $finalX $finalY}
        }
    }
}
proc ::GX::Engine3D::cancelGesture {{afterCommand {}}} {
    variable pendingGestureCancel;variable pendingGestureCancelJob
    if {$pendingGestureCancel ne {} && [dict get $pendingGestureCancel gesture]==$::GX::Engine3D::gestureGeneration &&
        [dict get $pendingGestureCancel worker]==$::GX::Engine3D::workerGeneration &&
        [dict get $pendingGestureCancel session] eq [::GX::interactiveDocumentSessionToken]} {
        # Key repeat must retain the original rollback mode while RPC yields.
        if {$afterCommand ne {}} {dict set pendingGestureCancel after_command $afterCommand}
        return
    }
    incr ::GX::Engine3D::gestureGeneration
    set ::GX::Engine3D::pendingDragEnd {};set ::GX::Engine3D::pendingGizmoEnd {};set ::GX::Engine3D::cameraQueue {}
    if {$::GX::Engine3D::pendingDragJob ne {}} {after cancel $::GX::Engine3D::pendingDragJob;set ::GX::Engine3D::pendingDragJob {}}
    if {$pendingGestureCancelJob ne {}} {after cancel $pendingGestureCancelJob;set pendingGestureCancelJob {}}
    set pendingGestureCancel [dict create gesture $::GX::Engine3D::gestureGeneration worker $::GX::Engine3D::workerGeneration session [::GX::interactiveDocumentSessionToken] mode $::GX::Engine3D::dragMode starting $::GX::Engine3D::gestureStarting after_command $afterCommand]
    if {!$::GX::Engine3D::gestureStarting} {set ::GX::Engine3D::dragMode {}}
    cancelGestureReady
}
proc ::GX::Engine3D::gestureReceipt {} {
    return [list $::GX::Engine3D::gestureGeneration $::GX::Engine3D::workerGeneration [::GX::interactiveDocumentSessionToken]]
}
proc ::GX::Engine3D::gestureCurrent {transaction} {
    if {$::GX::Engine3D::pendingGestureCancel ne {} || [catch {gestureReceipt} current]} {return 0}
    return [expr {$transaction eq $current}]
}
proc ::GX::Engine3D::gestureNativeEnded {transaction} {
    # Escape during an end RPC must prevent the scientific edit. That RPC has
    # already released native rollback state; render the retained authority
    # rather than issuing a second end against a completed native transaction.
    variable pendingGestureCancel
    if {$pendingGestureCancel ne {} && [dict get $pendingGestureCancel worker]==[lindex $transaction 1] &&
        [dict get $pendingGestureCancel session] eq [lindex $transaction 2]} {
        dict set pendingGestureCancel mode {}
        dict set pendingGestureCancel starting 0
        cancelGestureReady
    }
}
proc ::GX::Engine3D::cancelGestureReady {} {
    variable pendingGestureCancel;variable pendingGestureCancelJob
    set pendingGestureCancelJob {}
    if {$pendingGestureCancel eq {}} return
    set pending $pendingGestureCancel
    if {[dict get $pending gesture]!=$::GX::Engine3D::gestureGeneration||[dict get $pending worker]!=$::GX::Engine3D::workerGeneration||[dict get $pending session] ne [::GX::interactiveDocumentSessionToken]} {set pendingGestureCancel {};set ::GX::Engine3D::dragMode {};return}
    if {$::GX::Engine3D::gestureStarting||$::GX::Engine3D::workerBusy} {set pendingGestureCancelJob [after 30 [list ::GX::Engine3D::showError ::GX::Engine3D::cancelGestureReady]];return}
    set mode [expr {[dict get $pending starting] ? $::GX::Engine3D::dragMode : [dict get $pending mode]}]
    set ::GX::Engine3D::dragMode {};set ::GX::Engine3D::gizmoActive 0
    # Native rollback precedes any destructive scene render. A following mouse
    # release sees no active gesture and cannot re-enter the old transaction.
    if {$mode eq "gizmo"} {rpc [list gizmo_end 0]} elseif {$mode eq "plane"} {rpc [list plane_end 0]}
    set pendingGestureCancel {}
    set command [dict get $pending after_command]
    if {$command ne {}} {uplevel #0 $command} else {rerender}
    set ::GX::Engine3D::status "Gesture canceled; geometry is unchanged"
}
proc ::GX::Engine3D::flushDragEnd {} {
    variable pendingDragEnd;variable pendingDragJob
    set pendingDragJob {}
    if {$pendingDragEnd eq {}} return
    set request $pendingDragEnd
    if {[dict get $request gesture]!=$::GX::Engine3D::gestureGeneration||[dict get $request worker]!=$::GX::Engine3D::workerGeneration||[dict get $request session] ne [::GX::interactiveDocumentSessionToken]||![winfo exists $::GX::Engine3D::window]} {set pendingDragEnd {};return}
    if {$::GX::Engine3D::gestureStarting||$::GX::Engine3D::workerBusy} {set pendingDragJob [after 30 ::GX::Engine3D::flushDragEnd];return}
    set pendingDragEnd {}
    showError [list ::GX::Engine3D::endDrag [dict get $request x] [dict get $request y]]
}
proc ::GX::Engine3D::setProjection {projection} {
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict replace \
        [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] projection $projection]
    rerender
}
proc ::GX::Engine3D::fitScene {} {
    cameraPreset fit_scene
}
proc ::GX::Engine3D::cameraPreset {name {layerId ""}} {
    variable lastPng
    if {$lastPng eq ""} {rerender}
    set destination [tempPng]
    set staged "${destination}.stage.[pid].[clock clicks].png"
    try {
        set result [rpc [list preset $name $layerId $staged 960 640]]
        if {![pngComplete $staged]} {error "Camera preset did not produce a complete PNG"}
        file rename -force -- $staged $destination
    } finally {catch {file delete -- $staged}}
    set fields [dict create projection [dict get $result projection]]
    foreach key {camera_position camera_target camera_up} {
        dict set fields $key [join [dict get $result $key] {;}]
    }
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge \
        [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $fields]
    set ::GX::Engine3D::cameraPosition [dict get $fields camera_position]
    set ::GX::Engine3D::cameraTarget [dict get $fields camera_target]
    set ::GX::Engine3D::cameraUp [dict get $fields camera_up]
    set ::GX::Engine3D::projection [dict get $fields projection]
    set ::GX::Engine3D::latestPick [dict create]
    displayNativePng $destination
    set ::GX::Engine3D::status "Full ready: camera preset $name"
}
proc ::GX::Engine3D::setClippingPlanes {planes} {
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict replace \
        [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] clipping_planes $planes]
    rerender
}
proc ::GX::Engine3D::setWorkingPlane {origin normal uAxis {visible 1}} {
    set view [::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] [dict merge \
        [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] \
        [dict create working_plane_origin $origin working_plane_normal $normal \
            working_plane_u_axis $uAxis working_plane_visible $visible]]]
    foreach {field key} {planeOrigin working_plane_origin planeNormal working_plane_normal planeU working_plane_u_axis planeVisible working_plane_visible} {
        set ::GX::Engine3D::$field [dict get $view $key]
    }
    rerender
}
proc ::GX::Engine3D::refreshLayers {} {
    variable window
    variable selectedLayer
    if {![winfo exists $window.side.scroll.controls.layers]} return
    $window.side.scroll.controls.layers delete 0 end
    foreach id [orderedLayerIds] {
        set layer [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $id]
        $window.side.scroll.controls.layers insert end "$id ([dict get $layer kind])"
    }
    if {$selectedLayer ne ""} {
        set index [lsearch -exact [orderedLayerIds] $selectedLayer]
        if {$index >= 0} {$window.side.scroll.controls.layers selection set $index}
    }
}
proc ::GX::Engine3D::layerSelected {} {
    variable window
    variable selectedLayer
    variable visible
    variable opacity
    variable scalar
    variable scalarRange
    variable vector
    variable radius
    variable opacityArray
    variable tubeRadius
    variable isovalues
    variable colormap
    variable representation
    variable layerKind
    variable baseColor
    variable lineWidth
    variable pointSize
    variable backfaceCulling
    variable scalarColoring
    set index [$window.side.scroll.controls.layers curselection]
    if {$index eq ""} return
    set selectedLayer [lindex [orderedLayerIds] [lindex $index 0]]
    set layer [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $selectedLayer]
    set visible [dict get $layer visible]
    set opacity [dict get $layer opacity]
    set scalar [dict get $layer scalar_array]
    set scalarRange [dict get $layer scalar_range]
    set vector [dict get $layer vector_array]
    set radius [dict get $layer radius_array]
    set opacityArray [dict get $layer opacity_array]
    set tubeRadius [dict get $layer tube_radius]
    set isovalues [dict get $layer isovalues]
    set colormap [dict get $layer colormap]
    set representation [dict get $layer representation]
    set layerKind [dict get $layer kind]
    set baseColor [dict get $layer base_color]
    set lineWidth [dict get $layer line_width]
    set pointSize [dict get $layer point_size]
    set backfaceCulling [dict get $layer backface_culling]
    set scalarColoring [dict get $layer scalar_coloring]
}
proc ::GX::Engine3D::compareLayers {a b} {
    set left [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $a]
    set right [::GX::viewerLayerGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $b]
    set x [dict get $left layer_order];set y [dict get $right layer_order]
    if {$x < $y} {return -1}
    if {$x > $y} {return 1}
    return [string compare $a $b]
}
proc ::GX::Engine3D::orderedLayerIds {} {
    return [lsort -command ::GX::Engine3D::compareLayers \
        [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]]
}
proc ::GX::Engine3D::applyLayer {} {
    variable selectedLayer
    if {$selectedLayer eq ""} {error "Select a layer"}
    setLayerPresentation $selectedLayer [dict create kind $::GX::Engine3D::layerKind visible $::GX::Engine3D::visible \
        opacity $::GX::Engine3D::opacity scalar_array $::GX::Engine3D::scalar \
        scalar_range $::GX::Engine3D::scalarRange vector_array $::GX::Engine3D::vector \
        radius_array $::GX::Engine3D::radius opacity_array $::GX::Engine3D::opacityArray \
        tube_radius $::GX::Engine3D::tubeRadius \
        isovalues $::GX::Engine3D::isovalues colormap $::GX::Engine3D::colormap \
        representation $::GX::Engine3D::representation \
        base_color $::GX::Engine3D::baseColor line_width $::GX::Engine3D::lineWidth \
        point_size $::GX::Engine3D::pointSize backface_culling $::GX::Engine3D::backfaceCulling \
        scalar_coloring $::GX::Engine3D::scalarColoring]
}
proc ::GX::Engine3D::applyView {} {
    set fields [dict create camera_position $::GX::Engine3D::cameraPosition \
        camera_target $::GX::Engine3D::cameraTarget camera_up $::GX::Engine3D::cameraUp \
        projection $::GX::Engine3D::projection clipping_planes $::GX::Engine3D::clipping \
        working_plane_origin $::GX::Engine3D::planeOrigin \
        working_plane_normal $::GX::Engine3D::planeNormal \
        working_plane_u_axis $::GX::Engine3D::planeU \
        working_plane_visible $::GX::Engine3D::planeVisible \
        background_rgb $::GX::Engine3D::backgroundRgb \
        background_bottom_rgb $::GX::Engine3D::backgroundBottomRgb \
        background_gradient $::GX::Engine3D::backgroundGradient \
        lighting $::GX::Engine3D::lighting \
        lighting_ambient $::GX::Engine3D::lightingAmbient \
        lighting_diffuse $::GX::Engine3D::lightingDiffuse \
        lighting_specular $::GX::Engine3D::lightingSpecular \
        lighting_direction $::GX::Engine3D::lightingDirection \
        lighting_color $::GX::Engine3D::lightingColor \
        lighting_intensity $::GX::Engine3D::lightingIntensity \
        lighting_lights $::GX::Engine3D::lightingLights \
        axes_world $::GX::Engine3D::axesWorld \
        axes_local_layer $::GX::Engine3D::axesLocalLayer \
        axes_reference_marker $::GX::Engine3D::axesReferenceMarker \
        axes_size_pixels $::GX::Engine3D::axesSizePixels \
        clip_box $::GX::Engine3D::clipBox]
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] \
        [dict merge [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $fields]
    rerender
}
proc ::GX::Engine3D::showError {script} {
    if {[catch {uplevel #0 $script} err]} {
        if {$err eq "Rendering cancelled"} return
        set ::GX::Engine3D::status $err; tk_messageBox -icon error -message $err
    }
}
proc ::GX::Engine3D::chooseArtifact {} {
    set path [tk_getOpenFile -filetypes {{3D {*.stl *.obj *.step *.stp *.vtp *.vtu *.vti}} {All {*}}}]
    if {$path eq ""} return
    if {[string equal -nocase [file extension $path] .vti]} {
        set dialog $::GX::Engine3D::window.vti
        if {[winfo exists $dialog]} {destroy $dialog}
        toplevel $dialog
        wm title $dialog "VTI scalar presentation"
        set ::GX::Engine3D::vtiPath $path
        set ::GX::Engine3D::vtiScalar ""
        set ::GX::Engine3D::vtiIsovalues ""
        set ::GX::Engine3D::vtiVolumeTransfer "0,0,0,0,0;1,1,0.8,0.1,0.6"
        set ::GX::Engine3D::vtiVolumeStep 0.05
        ttk::label $dialog.scalarLabel -text "Scalar array name"
        ttk::entry $dialog.scalar -textvariable ::GX::Engine3D::vtiScalar
        ttk::label $dialog.valuesLabel -text "Isovalues (; separated)"
        ttk::entry $dialog.values -textvariable ::GX::Engine3D::vtiIsovalues
        ttk::button $dialog.add -text "Add isosurface" -command {::GX::Engine3D::showError {
            ::GX::Engine3D::addArtifactAndRender $::GX::Engine3D::vtiPath isosurface \
                $::GX::Engine3D::vtiScalar $::GX::Engine3D::vtiIsovalues
            destroy $::GX::Engine3D::window.vti
        }}
        ttk::button $dialog.addField -text "Add scalar/vector field" -command {::GX::Engine3D::showError {
            ::GX::Engine3D::addArtifactAndRender $::GX::Engine3D::vtiPath surface
            destroy $::GX::Engine3D::window.vti
        }}
        ttk::label $dialog.transferLabel -text "Volume transfer scalar,R,G,B,opacity (; separated)"
        ttk::entry $dialog.transfer -textvariable ::GX::Engine3D::vtiVolumeTransfer
        ttk::label $dialog.stepLabel -text "Volume sample distance"
        ttk::entry $dialog.step -textvariable ::GX::Engine3D::vtiVolumeStep
        ttk::button $dialog.addVolume -text "Add volume" -command {::GX::Engine3D::showError {
            ::GX::Engine3D::addArtifactAndRender $::GX::Engine3D::vtiPath volume \
                $::GX::Engine3D::vtiScalar "" $::GX::Engine3D::vtiVolumeTransfer \
                $::GX::Engine3D::vtiVolumeStep
            destroy $::GX::Engine3D::window.vti
        }}
        pack $dialog.scalarLabel $dialog.scalar $dialog.valuesLabel $dialog.values $dialog.add $dialog.addField \
            $dialog.transferLabel $dialog.transfer $dialog.stepLabel $dialog.step $dialog.addVolume -fill x
        return
    }
    addArtifactAndRender $path
}
proc ::GX::Engine3D::chooseDataset {} {
    variable window
    set dialog $window.dataset
    if {[winfo exists $dialog]} {raise $dialog; return}
    toplevel $dialog
    wm title $dialog "Add Dataset 3D layer"
    set ids [::GX::datasetRegistryIds]
    set ::GX::Engine3D::datasetId [lindex $ids 0]
    set row 0
    ttk::label $dialog.label$row -text "Dataset ID";grid $dialog.label$row -row $row -column 0
    ttk::combobox $dialog.dataset -textvariable ::GX::Engine3D::datasetId -values $ids -state readonly
    ::GX::datasetSelectorAttach $dialog.dataset ::GX::datasetRegistryIds
    grid $dialog.dataset -row $row -column 1 -sticky ew;incr row
    bind $dialog.dataset <<ComboboxSelected>> ::GX::Engine3D::datasetSelected
    foreach {field label} {datasetX X datasetY Y datasetZ Z datasetScalar {Scalar (optional)} \
        datasetVx {Vector X (optional)} datasetVy {Vector Y} datasetVz {Vector Z} \
        datasetRadius {Radius (optional)} datasetOpacity {Opacity [0,1] (optional)}} {
        ttk::label $dialog.label$row -text $label;grid $dialog.label$row -row $row -column 0
        ttk::entry $dialog.$field -textvariable ::GX::Engine3D::$field
        grid $dialog.$field -row $row -column 1 -sticky ew;incr row
    }
    ttk::combobox $dialog.kind -textvariable ::GX::Engine3D::datasetKind -values {points trajectory} -state readonly
    grid $dialog.kind -row $row -column 1 -sticky ew;incr row
    ttk::button $dialog.add -text "Add layer" -command [list ::GX::Engine3D::showError {
        ::GX::Engine3D::addDataset $::GX::Engine3D::datasetId $::GX::Engine3D::datasetX \
            $::GX::Engine3D::datasetY $::GX::Engine3D::datasetZ \
            $::GX::Engine3D::datasetKind $::GX::Engine3D::datasetScalar \
            [expr {$::GX::Engine3D::datasetVx eq "" ? {} : \
                [list $::GX::Engine3D::datasetVx $::GX::Engine3D::datasetVy $::GX::Engine3D::datasetVz]}] \
            $::GX::Engine3D::datasetRadius $::GX::Engine3D::datasetOpacity
        destroy $::GX::Engine3D::window.dataset
        ::GX::Engine3D::rerender
    }]
    grid $dialog.add -row $row -column 1 -sticky ew
    incr row;ttk::label $dialog.sourceInfo -text {} -wraplength 470 -justify left
    grid $dialog.sourceInfo -row $row -column 0 -columnspan 2 -sticky ew -padx 6 -pady 8
    grid columnconfigure $dialog 1 -weight 1
    datasetSelected
}
proc ::GX::Engine3D::datasetSelected {} {
    variable datasetId
    if {$datasetId eq ""} return
    set dialog $::GX::Engine3D::window.dataset
    set geometry [expr {[::GX::datasetField $datasetId contract {}] in {geometry.mesh model.cad}}]
    foreach key {datasetX datasetY datasetZ datasetScalar datasetVx datasetVy datasetVz datasetRadius datasetOpacity kind} {if {[winfo exists $dialog.$key]} {$dialog.$key configure -state [expr {$geometry ? "disabled" : $key eq "kind" ? "readonly" : "normal"}]}}
    if {[winfo exists $dialog.sourceInfo]} {$dialog.sourceInfo configure -text [expr {$geometry ? "Complete canonical geometry Dataset: $datasetId. File coordinates and declared units are preserved; source bytes remain immutable." : "Choose numeric X/Y/Z bindings for a point or trajectory Dataset layer."}]}
    if {$geometry} return
    if {[catch {set schema [::GX::datasetVariableSchema $datasetId]}]} return
    set ids {}
    foreach variable $schema {
        if {[dict get $variable enabled] && [dict get $variable value_kind] in {number numeric integer real float double ""}} {
            lappend ids [dict get $variable variable_id]
        }
    }
    foreach {field index} {datasetX 0 datasetY 1 datasetZ 2} {
        if {$index < [llength $ids]} {set ::GX::Engine3D::$field [lindex $ids $index]}
    }
}
proc ::GX::Engine3D::timelineDefinitions {} {
    return [dict get [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] timeline_definitions]
}
proc ::GX::Engine3D::activeTimeline {} {
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set active [dict get $scene active_timeline_id]
    foreach timeline [dict get $scene timeline_definitions] {
        if {[dict get $timeline id] eq $active} {return $timeline}
    }
    error "Select a timeline first"
}
proc ::GX::Engine3D::saveTimeline {updated} {
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set definitions {}
    foreach timeline [dict get $scene timeline_definitions] {
        if {[dict get $timeline id] eq [dict get $updated id]} {set timeline $updated}
        lappend definitions $timeline
    }
    dict set scene timeline_definitions $definitions
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $scene
}
proc ::GX::Engine3D::createTimeline {} {
    if {$::GX::currentSession eq ""} {error "Open a Session first"}
    set times [split $::GX::Engine3D::timelineTimes {;}]
    if {![llength $times]} {error "Enter timeline times"}
    set last [expr {[llength $times]-1}]
    set id $::GX::Engine3D::timelineId
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set timeline [dict create id $id unit $::GX::Engine3D::timelineUnit times $times \
        tracks {} current_frame 0 current_time [lindex $times 0] \
        range_first 0 range_last $last rate 1 loop once state stopped]
    dict set scene timeline_definitions [concat [dict get $scene timeline_definitions] [list $timeline]]
    dict set scene active_timeline_id $id
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $scene
    set ::GX::Engine3D::timelineRangeFirst 0
    set ::GX::Engine3D::timelineRangeLast $last
    set ::GX::Engine3D::timelineFrame 0
    set ::GX::Engine3D::timelineTime [lindex $times 0]
    rerender
    return $id
}
proc ::GX::Engine3D::selectTimeline {} {
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    dict set scene active_timeline_id $::GX::Engine3D::timelineId
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $scene
    set timeline [activeTimeline]
    foreach {var key} {timelineUnit unit timelineFrame current_frame timelineTime current_time \
        timelineRate rate timelineLoop loop timelineRangeFirst range_first timelineRangeLast range_last} {
        set ::GX::Engine3D::$var [dict get $timeline $key]
    }
    rerender
}
proc ::GX::Engine3D::addTimelineTrack {} {
    set timeline [activeTimeline]
    set frames [split $::GX::Engine3D::timelineFrameLayers {;}]
    if {[llength $frames] != [llength [dict get $timeline times]]} {
        error "Enter one existing layer ID per frame, separated by semicolons"
    }
    foreach id $frames {
        if {$id ne "" && [lsearch -exact [::GX::viewerLayerIds [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] $id] < 0} {
            error "Timeline frame layer is missing: $id"
        }
    }
    dict lappend timeline tracks [dict create id $::GX::Engine3D::timelineTrackId frames $frames]
    saveTimeline $timeline
    rerender
}
proc ::GX::Engine3D::applyTimelineSettings {} {
    set timeline [activeTimeline]
    foreach {key var} {rate timelineRate loop timelineLoop range_first timelineRangeFirst \
        range_last timelineRangeLast} {dict set timeline $key [set ::GX::Engine3D::$var]}
    saveTimeline $timeline
    rerender
}
proc ::GX::Engine3D::timelineAction {action {value 0}} {
    if {$::GX::Engine3D::workerBusy} {error "Wait for the current native render"}
    ::GX::viewerSceneResolve [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]
    set ::GX::Engine3D::gizmoActive 0
    set ::GX::Engine3D::latestPick [dict create]
    set result [gizmoImageRequest [list timeline $action $value]]
    set timeline [activeTimeline]
    foreach key {current_frame current_time state} {dict set timeline $key [dict get $result $key]}
    saveTimeline $timeline
    set ::GX::Engine3D::timelineFrame [dict get $result current_frame]
    set ::GX::Engine3D::timelineTime [dict get $result current_time]
    set ::GX::Engine3D::status "Timeline [dict get $timeline id]: frame $::GX::Engine3D::timelineFrame, time $::GX::Engine3D::timelineTime"
    return $result
}
proc ::GX::Engine3D::timelineTick {} {
    set ::GX::Engine3D::timelineTimer ""
    if {![winfo exists $::GX::Engine3D::window] || $::GX::Engine3D::worker eq ""} return
    if {$::GX::Engine3D::workerBusy} {
        set ::GX::Engine3D::timelineTimer [after 50 ::GX::Engine3D::timelineTick]
        return
    }
    set now [clock milliseconds]
    set elapsed [expr {($now-$::GX::Engine3D::timelineLastTick)/1000.0}]
    set ::GX::Engine3D::timelineLastTick $now
    if {[catch {set result [timelineAction advance $elapsed]} problem]} {
        set ::GX::Engine3D::status $problem
        return
    }
    if {[dict get $result state] eq "playing"} {
        set ::GX::Engine3D::timelineTimer [after 50 ::GX::Engine3D::timelineTick]
    }
}
proc ::GX::Engine3D::timelinePlay {} {
    if {$::GX::Engine3D::timelineTimer ne ""} {after cancel $::GX::Engine3D::timelineTimer}
    timelineAction play
    set ::GX::Engine3D::timelineLastTick [clock milliseconds]
    set ::GX::Engine3D::timelineTimer [after 50 ::GX::Engine3D::timelineTick]
}
proc ::GX::Engine3D::timelinePause {} {
    if {$::GX::Engine3D::timelineTimer ne ""} {after cancel $::GX::Engine3D::timelineTimer;set ::GX::Engine3D::timelineTimer ""}
    timelineAction pause
}
proc ::GX::Engine3D::timelineStop {} {
    if {$::GX::Engine3D::timelineTimer ne ""} {after cancel $::GX::Engine3D::timelineTimer;set ::GX::Engine3D::timelineTimer ""}
    timelineAction stop
}
proc ::GX::Engine3D::addFieldDefinition {} {
    set scene [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    set kind $::GX::Engine3D::fieldKind
    set n 1
    set existing {}
    foreach prior [dict get $scene field_definitions] {lappend existing [dict get $prior id]}
    while {"${kind}_$n" in $existing} {incr n}
    set id "${kind}_$n"
    set definition [dict create id $id kind $kind]
    if {$::GX::Engine3D::fieldSourceMode eq "timeline"} {
        dict set definition timeline_id [dict get $scene active_timeline_id]
        dict set definition source_track $::GX::Engine3D::fieldSourceTrack
    } else {
        if {$kind eq "pathlines"} {error "Pathlines require a timeline track"}
        dict set definition source_layer $::GX::Engine3D::selectedLayer
    }
    dict set definition vector_array_index $::GX::Engine3D::fieldVectorIndex
    dict set definition scalar_array_index $::GX::Engine3D::fieldScalarIndex
    dict set definition seed_kind $::GX::Engine3D::fieldSeedKind
    dict set definition seed_points [split $::GX::Engine3D::fieldSeeds {|}]
    dict set definition seed_origin $::GX::Engine3D::fieldSeedOrigin
    dict set definition seed_u $::GX::Engine3D::fieldSeedU
    dict set definition seed_v $::GX::Engine3D::fieldSeedV
    dict set definition seed_u_count $::GX::Engine3D::fieldSeedUCount
    dict set definition seed_v_count $::GX::Engine3D::fieldSeedVCount
    dict set definition direction $::GX::Engine3D::fieldDirection
    dict set definition step_size $::GX::Engine3D::fieldStep
    dict set definition time_step $::GX::Engine3D::fieldTimeStep
    dict set definition min_magnitude $::GX::Engine3D::fieldMinMagnitude
    dict set definition tube_radius $::GX::Engine3D::fieldTubeRadius
    dict set definition max_steps $::GX::Engine3D::fieldMaxSteps
    dict set definition max_points $::GX::Engine3D::fieldMaxPoints
    dict set definition max_memory_bytes $::GX::Engine3D::fieldMaxMemoryBytes
    dict set definition origin $::GX::Engine3D::fieldSliceOrigin
    dict set definition u_step $::GX::Engine3D::fieldSliceU
    dict set definition v_step $::GX::Engine3D::fieldSliceV
    dict set definition u_count $::GX::Engine3D::fieldSliceUCount
    dict set definition v_count $::GX::Engine3D::fieldSliceVCount
    dict set definition scalar_name $::GX::Engine3D::fieldIsoName
    dict set definition value $::GX::Engine3D::fieldIsoValue
    dict lappend scene field_definitions $definition
    ::GX::viewerSceneSet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider] $scene
    rerender
    return $id
}
proc ::GX::Engine3D::panel {{raiseWindow 1}} {
    variable window
    if {[winfo exists $window]} {if {$raiseWindow} {raise $window};return $window}
    if {$::GX::Engine3D::embedded} {ttk::frame $window} else {
        toplevel $window
        wm title $window $::GX::Engine3D::windowTitle
        wm geometry $window 1510x820
    }
    bind $window <Destroy> [list ::GX::Engine3D::hostDestroyed $window %W]
    set ::GX::Engine3D::sidebarMode auto
    ttk::button $window.controlsToggle -text {View controls} -command ::GX::Engine3D::hostSidebarToggle
    pack $window.controlsToggle -side top -anchor e -padx 4 -pady 2
    ::GX::native2DViewportTooltip $window.controlsToggle {Show or hide Native3D view, lighting and navigation controls. Narrow embedded views hide them automatically.}
    bind $window <Configure> +[list ::GX::Engine3D::hostSidebarSchedule $window %W]
    ttk::frame $window.side
    pack $window.side -side left -fill y -padx 4 -pady 4
    canvas $window.side.scroll -width 460 -highlightthickness 0 \
        -yscrollcommand [list $window.side.bar set] -xscrollcommand [list $window.side.xbar set]
    ttk::scrollbar $window.side.xbar -orient horizontal -command [list $window.side.scroll xview]
    pack $window.side.xbar -side bottom -fill x
    ttk::scrollbar $window.side.bar -orient vertical -command [list $window.side.scroll yview]
    pack $window.side.bar -side right -fill y
    pack $window.side.scroll -side left -fill y
    ttk::frame $window.side.scroll.controls
    if {[ownerModule] eq "viewer.engine_3d"} {
        ttk::button $window.side.scroll.controls.planar -text {Working plane / Curve Workbench…} -command [list ::GX::Engine3D::showError ::GX::native3DPlanarDialog]
        pack $window.side.scroll.controls.planar -fill x -pady 5
    }
    $window.side.scroll create window 0 0 -anchor nw -window $window.side.scroll.controls -tags controls -width 460
    bind $window.side.scroll <Configure> [list ::GX::Engine3D::hostSidebarContentWidth $window.side.scroll %w]
    bind $window.side.scroll.controls <Configure> [list ::GX::Engine3D::hostSidebarContentWidth $window.side.scroll {}]
    bind $window.side.scroll <MouseWheel> [list $window.side.scroll yview scroll -3 units]
    bind $window.side.scroll <Button-4> [list $window.side.scroll yview scroll -3 units]
    bind $window.side.scroll <Button-5> [list $window.side.scroll yview scroll 3 units]
    canvas $window.canvas -width 960 -height 640 -background black
    pack $window.canvas -side left -fill both -expand 1
    if {$::GX::Engine3D::photo ne {}} {$window.canvas create image 0 0 -anchor nw -image $::GX::Engine3D::photo -tags native_image}
    bind $window.canvas <Configure> [list ::GX::Engine3D::hostResizeSchedule %w %h]
    bind $window.canvas <ButtonPress-1> {::GX::Engine3D::showError [list ::GX::Engine3D::beginCanvasDrag %x %y]}
    bind $window.canvas <B1-Motion> {::GX::Engine3D::showError [list ::GX::Engine3D::planeMotion %x %y];::GX::Engine3D::showError [list ::GX::Engine3D::gizmoMotion %x %y];::GX::Engine3D::showError [list ::GX::Engine3D::cameraMotion %x %y]}
    bind $window.canvas <ButtonRelease-1> {::GX::Engine3D::showError [list ::GX::Engine3D::endDrag %x %y]}
    bind $window.canvas <ButtonPress-2> {::GX::Engine3D::beginDrag pan %x %y}
    bind $window.canvas <B2-Motion> {::GX::Engine3D::showError [list ::GX::Engine3D::cameraMotion %x %y]}
    bind $window.canvas <ButtonRelease-2> {::GX::Engine3D::showError [list ::GX::Engine3D::endDrag %x %y]}
    bind $window.canvas <MouseWheel> {::GX::Engine3D::showError [list ::GX::Engine3D::cameraZoom [expr {%D/120.0}]]}
    bind $window.canvas <Button-4> {::GX::Engine3D::showError [list ::GX::Engine3D::cameraZoom 1]}
    bind $window.canvas <Button-5> {::GX::Engine3D::showError [list ::GX::Engine3D::cameraZoom -1]}
    hostEscapeInstall
    ttk::label $window.side.scroll.controls.title -text "Layers";pack $window.side.scroll.controls.title -fill x
    listbox $window.side.scroll.controls.layers -height 8 -width 32 -exportselection 0
    pack $window.side.scroll.controls.layers -fill x
    bind $window.side.scroll.controls.layers <<ListboxSelect>> ::GX::Engine3D::layerSelected
    ttk::button $window.side.scroll.controls.artifact -text "Add geometry / VTK file" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::chooseArtifact}
    ttk::button $window.side.scroll.controls.dataset -text "Add Dataset geometry / points / trajectory" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::chooseDataset}
    pack $window.side.scroll.controls.artifact $window.side.scroll.controls.dataset -fill x
    ttk::checkbutton $window.side.scroll.controls.visible -text Visible -variable ::GX::Engine3D::visible
    pack $window.side.scroll.controls.visible -anchor w
    ttk::combobox $window.side.scroll.controls.layerKind -textvariable ::GX::Engine3D::layerKind \
        -values {geometry triangle_mesh surface points trajectory isosurface} -state readonly
    pack $window.side.scroll.controls.layerKind -fill x
    foreach {field label} {opacity Opacity scalar {Scalar field} scalarRange {Range min;max} \
        vector {Vector field} radius {Radius field} opacityArray {Point opacity field} tubeRadius {Tube radius} \
        isovalues {Isovalues (; separated)} colormap Colormap \
        baseColor {Base RGB} lineWidth {Line width} pointSize {Point size}} {
        ttk::label $window.side.scroll.controls.${field}Label -text $label
        ttk::entry $window.side.scroll.controls.$field -textvariable ::GX::Engine3D::$field
        pack $window.side.scroll.controls.${field}Label $window.side.scroll.controls.$field -fill x
    }
    ttk::combobox $window.side.scroll.controls.representation -textvariable ::GX::Engine3D::representation \
        -values {surface wireframe surface_edges points} -state readonly
    pack $window.side.scroll.controls.representation -fill x
    ttk::checkbutton $window.side.scroll.controls.backface -text "Cull backfaces" \
        -variable ::GX::Engine3D::backfaceCulling
    ttk::checkbutton $window.side.scroll.controls.scalarColoring -text "Scalar coloring" \
        -variable ::GX::Engine3D::scalarColoring
    pack $window.side.scroll.controls.backface $window.side.scroll.controls.scalarColoring -anchor w
    ttk::button $window.side.scroll.controls.layerApply -text "Apply layer" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::applyLayer}
    pack $window.side.scroll.controls.layerApply -fill x
    ttk::separator $window.side.scroll.controls.timelineSep -orient horizontal
    pack $window.side.scroll.controls.timelineSep -fill x -pady 5
    ttk::label $window.side.scroll.controls.timelineTitle -text "Scientific timeline"
    pack $window.side.scroll.controls.timelineTitle -fill x
    foreach {name label} {timelineId {Timeline ID} timelineUnit {Time unit} \
        timelineTimes {Frame times (; separated)} timelineTrackId {Track ID} \
        timelineFrameLayers {Frame layer IDs (; separated)} timelineFrame {Current frame} \
        timelineTime {Current time} timelineRate {Playback rate} \
        timelineRangeFirst {Range first frame} timelineRangeLast {Range last frame}} {
        ttk::label $window.side.scroll.controls.${name}Label -text $label
        ttk::entry $window.side.scroll.controls.$name -textvariable ::GX::Engine3D::$name
        pack $window.side.scroll.controls.${name}Label $window.side.scroll.controls.$name -fill x
    }
    ttk::button $window.side.scroll.controls.timelineCreate -text "Create timeline" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::createTimeline}
    ttk::button $window.side.scroll.controls.timelineSelect -text "Select timeline" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::selectTimeline}
    ttk::button $window.side.scroll.controls.timelineTrack -text "Add changing layer track" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::addTimelineTrack}
    ttk::combobox $window.side.scroll.controls.timelineLoop -textvariable ::GX::Engine3D::timelineLoop \
        -values {once loop ping_pong} -state readonly
    ttk::button $window.side.scroll.controls.timelineSettings -text "Apply playback settings" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::applyTimelineSettings}
    pack $window.side.scroll.controls.timelineCreate $window.side.scroll.controls.timelineSelect \
        $window.side.scroll.controls.timelineTrack $window.side.scroll.controls.timelineLoop \
        $window.side.scroll.controls.timelineSettings -fill x
    ttk::frame $window.side.scroll.controls.timelineButtons
    foreach {name label action value} {frameGo Frame seek_frame {$::GX::Engine3D::timelineFrame} \
        timeGo Time seek_time {$::GX::Engine3D::timelineTime} \
        prev Previous step -1 next Next step 1 \
        play Play play 0 pause Pause pause 0 stop Stop stop 0} {
        if {$name in {play pause stop}} {
            set script "::GX::Engine3D::timeline[string totitle $name]"
        } else {
            set script [list ::GX::Engine3D::timelineAction $action]
            if {$name eq "frameGo"} {set script {::GX::Engine3D::timelineAction seek_frame $::GX::Engine3D::timelineFrame}} \
            elseif {$name eq "timeGo"} {set script {::GX::Engine3D::timelineAction seek_time $::GX::Engine3D::timelineTime}} \
            else {set script [list ::GX::Engine3D::timelineAction $action $value]}
        }
        ttk::button $window.side.scroll.controls.timelineButtons.$name -text $label \
            -command [list ::GX::Engine3D::showError $script]
        pack $window.side.scroll.controls.timelineButtons.$name -side left
    }
    pack $window.side.scroll.controls.timelineButtons -fill x
    ttk::separator $window.side.scroll.controls.fieldSep -orient horizontal
    pack $window.side.scroll.controls.fieldSep -fill x -pady 5
    ttk::label $window.side.scroll.controls.fieldTitle -text "Derived scientific field"
    pack $window.side.scroll.controls.fieldTitle -fill x
    ttk::combobox $window.side.scroll.controls.fieldKind -textvariable ::GX::Engine3D::fieldKind \
        -values {lines pathlines slice isosurface} -state readonly
    ttk::combobox $window.side.scroll.controls.fieldSourceMode -textvariable ::GX::Engine3D::fieldSourceMode \
        -values {static timeline} -state readonly
    ttk::combobox $window.side.scroll.controls.fieldSeedKind -textvariable ::GX::Engine3D::fieldSeedKind \
        -values {points line plane} -state readonly
    ttk::combobox $window.side.scroll.controls.fieldDirection -textvariable ::GX::Engine3D::fieldDirection \
        -values {forward backward both} -state readonly
    pack $window.side.scroll.controls.fieldKind $window.side.scroll.controls.fieldSourceMode \
        $window.side.scroll.controls.fieldSeedKind $window.side.scroll.controls.fieldDirection -fill x
    foreach {name label} {fieldSourceTrack {Timeline source track ID} fieldSeeds {Point seeds x;y;z | x;y;z} \
        fieldSeedOrigin {Seed origin x;y;z} fieldSeedU {Seed line/plane U step} \
        fieldSeedV {Seed plane V step} fieldSeedUCount {Seed U count} \
        fieldSeedVCount {Seed V count} fieldVectorIndex {Vector array index} \
        fieldScalarIndex {Scalar array index (optional)} fieldStep {Streamline spatial step} \
        fieldTimeStep {Pathline time step} fieldMinMagnitude {Minimum vector magnitude} \
        fieldTubeRadius {Tube radius} fieldMaxSteps {Maximum steps} \
        fieldMaxPoints {Maximum output points} fieldMaxMemoryBytes {Memory budget bytes} \
        fieldSliceOrigin {Slice origin} fieldSliceU {Slice U step} fieldSliceV {Slice V step} \
        fieldSliceUCount {Slice U count} fieldSliceVCount {Slice V count} \
        fieldIsoName {Isosurface scalar name} fieldIsoValue {Isosurface value}} {
        ttk::label $window.side.scroll.controls.${name}Label -text $label
        ttk::entry $window.side.scroll.controls.$name -textvariable ::GX::Engine3D::$name
        pack $window.side.scroll.controls.${name}Label $window.side.scroll.controls.$name -fill x
    }
    ttk::button $window.side.scroll.controls.fieldAdd -text "Create field layer" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::addFieldDefinition}
    pack $window.side.scroll.controls.fieldAdd -fill x
    ttk::combobox $window.side.scroll.controls.gizmoSpace -textvariable ::GX::Engine3D::gizmoSpace \
        -values {world local} -state readonly
    foreach {field label} {gizmoFamilies {Handles: axis,plane,free,rotate} \
        gizmoPivot {World pivot x;y;z (optional)} gizmoPivotMarker {Pivot marker ID (optional)} \
        gizmoSizePixels {Handle size (pixels)}} {
        ttk::label $window.side.scroll.controls.${field}Label -text $label
        ttk::entry $window.side.scroll.controls.$field -textvariable ::GX::Engine3D::$field
        pack $window.side.scroll.controls.${field}Label $window.side.scroll.controls.$field -fill x
    }
    ttk::button $window.side.scroll.controls.gizmoSelect -text "Manipulate selected object" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::selectGizmo}
    pack $window.side.scroll.controls.gizmoSpace $window.side.scroll.controls.gizmoSelect -fill x
    ttk::separator $window.side.scroll.controls.sep -orient horizontal;pack $window.side.scroll.controls.sep -fill x -pady 5
    foreach {field label} {cameraPosition {Camera position x;y;z} cameraTarget {Camera target x;y;z} cameraUp {Camera up x;y;z} \
        clipping {Clipping nx,ny,nz,d} clipBox {Clip box min/max (6 values)} \
        planeOrigin {Plane origin} planeNormal {Plane normal} planeU {Plane U axis} \
        backgroundRgb {Background RGB} backgroundBottomRgb {Gradient bottom RGB} \
        lightingAmbient Ambient lightingDiffuse Diffuse lightingSpecular Specular \
        lightingDirection {Light direction} lightingColor {Light RGB} lightingIntensity {Light intensity} \
        lightingLights {Directional lights dx,dy,dz,r,g,b,intensity; ...} \
        axesLocalLayer {Local axes layer ID} axesReferenceMarker {Reference axes marker ID} \
        axesSizePixels {Axes size (pixels)}} {
        ttk::label $window.side.scroll.controls.${field}Label -text $label
        ttk::entry $window.side.scroll.controls.$field -textvariable ::GX::Engine3D::$field
        pack $window.side.scroll.controls.${field}Label $window.side.scroll.controls.$field -fill x
    }
    ttk::combobox $window.side.scroll.controls.projection -textvariable ::GX::Engine3D::projection \
        -values {perspective orthographic} -state readonly
    pack $window.side.scroll.controls.projection -fill x
    ttk::combobox $window.side.scroll.controls.cameraPreset -textvariable ::GX::Engine3D::cameraPreset \
        -values {front back left right top bottom isometric fit_scene fit_object fit_selection} -state readonly
    ttk::button $window.side.scroll.controls.presetApply -text "Apply camera preset" \
        -command {::GX::Engine3D::showError {
            ::GX::Engine3D::cameraPreset $::GX::Engine3D::cameraPreset $::GX::Engine3D::selectedLayer
        }}
    pack $window.side.scroll.controls.cameraPreset $window.side.scroll.controls.presetApply -fill x
    ttk::checkbutton $window.side.scroll.controls.planeVisible -text "Working plane" -variable ::GX::Engine3D::planeVisible
    pack $window.side.scroll.controls.planeVisible -anchor w
    ttk::checkbutton $window.side.scroll.controls.planeMode -text "Drag plane / clip on canvas" \
        -variable ::GX::Engine3D::planeMode
    pack $window.side.scroll.controls.planeMode -anchor w
    foreach {name values label} {planeTarget {working clip box} Target \
        planeAction {translate rotate} Action \
        planeHandle {free x y z min_x min_y min_z max_x max_y max_z} Handle} {
        ttk::label $window.side.scroll.controls.${name}Label -text $label
        ttk::combobox $window.side.scroll.controls.$name -textvariable ::GX::Engine3D::$name \
            -values $values -state readonly
        pack $window.side.scroll.controls.${name}Label $window.side.scroll.controls.$name -fill x
    }
    ttk::label $window.side.scroll.controls.planeSlotLabel -text "Clip plane slot (zero based)"
    ttk::entry $window.side.scroll.controls.planeSlot -textvariable ::GX::Engine3D::planeSlot
    pack $window.side.scroll.controls.planeSlotLabel $window.side.scroll.controls.planeSlot -fill x
    ttk::checkbutton $window.side.scroll.controls.gradient -text "Gradient background" -variable ::GX::Engine3D::backgroundGradient
    ttk::checkbutton $window.side.scroll.controls.lighting -text Lighting -variable ::GX::Engine3D::lighting
    pack $window.side.scroll.controls.gradient $window.side.scroll.controls.lighting -anchor w
    ttk::checkbutton $window.side.scroll.controls.axesWorld -text "World XYZ axes" \
        -variable ::GX::Engine3D::axesWorld
    pack $window.side.scroll.controls.axesWorld -anchor w
    ttk::button $window.side.scroll.controls.viewApply -text "Apply view" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::applyView}
    ttk::button $window.side.scroll.controls.fit -text "Fit scene" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::fitScene}
    ttk::button $window.side.scroll.controls.render -text Rerender \
        -command {::GX::Engine3D::showError ::GX::Engine3D::rerender}
    ttk::button $window.side.scroll.controls.cancel -text "Cancel rendering" \
        -command ::GX::Engine3D::cancelRendering
    ttk::button $window.side.scroll.controls.screenshot -text "Save PNG" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::chooseScreenshot}
    foreach {field label} {exportWidth {PNG width} exportHeight {PNG height}} {
        ttk::label $window.side.scroll.controls.${field}Label -text $label
        ttk::entry $window.side.scroll.controls.$field -textvariable ::GX::Engine3D::$field
        pack $window.side.scroll.controls.${field}Label $window.side.scroll.controls.$field -fill x
    }
    pack $window.side.scroll.controls.viewApply $window.side.scroll.controls.fit $window.side.scroll.controls.render $window.side.scroll.controls.cancel $window.side.scroll.controls.screenshot -fill x
    ttk::separator $window.side.scroll.controls.annotationSep -orient horizontal
    pack $window.side.scroll.controls.annotationSep -fill x -pady 5
    ttk::button $window.side.scroll.controls.markPick -text "Mark selected point" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::markerFromPick}
    pack $window.side.scroll.controls.markPick -fill x
    foreach {field label} {measurementA {Marker A ID} measurementB {Marker B ID} measurementC {Marker C for angle}} {
        ttk::label $window.side.scroll.controls.${field}Label -text $label
        ttk::entry $window.side.scroll.controls.$field -textvariable ::GX::Engine3D::$field
        pack $window.side.scroll.controls.${field}Label $window.side.scroll.controls.$field -fill x
    }
    ttk::combobox $window.side.scroll.controls.measurementKind -textvariable ::GX::Engine3D::measurementKind \
        -values {distance delta_x delta_y delta_z angle} -state readonly
    ttk::button $window.side.scroll.controls.measure -text "Add measurement" \
        -command {::GX::Engine3D::showError {
            ::GX::Engine3D::addMeasurement $::GX::Engine3D::measurementA \
                $::GX::Engine3D::measurementB $::GX::Engine3D::measurementKind \
                $::GX::Engine3D::measurementC
        }}
    pack $window.side.scroll.controls.measurementKind $window.side.scroll.controls.measure -fill x
    ttk::separator $window.side.scroll.controls.curveSep -orient horizontal
    pack $window.side.scroll.controls.curveSep -fill x -pady 5
    ttk::combobox $window.side.scroll.controls.curveKind -textvariable ::GX::Engine3D::curveKind \
        -values {section profile projection} -state readonly
    ttk::entry $window.side.scroll.controls.curveTolerance -textvariable ::GX::Engine3D::curveTolerance
    ttk::button $window.side.scroll.controls.addCurve -text "Add section / profile / projection" \
        -command {::GX::Engine3D::showError ::GX::Engine3D::addSelectedCurve}
    pack $window.side.scroll.controls.curveKind $window.side.scroll.controls.curveTolerance $window.side.scroll.controls.addCurve -fill x
    ttk::label $window.side.scroll.controls.status -textvariable ::GX::Engine3D::status -wraplength 240
    pack $window.side.scroll.controls.status -fill x -pady 6
    set current [::GX::viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]]
    foreach {field key} {cameraPosition camera_position cameraTarget camera_target cameraUp camera_up projection projection \
        clipping clipping_planes clipBox clip_box planeOrigin working_plane_origin \
        planeNormal working_plane_normal planeU working_plane_u_axis planeVisible working_plane_visible \
        backgroundRgb background_rgb backgroundBottomRgb background_bottom_rgb \
        backgroundGradient background_gradient lighting lighting lightingAmbient lighting_ambient \
        lightingDiffuse lighting_diffuse lightingSpecular lighting_specular \
        lightingDirection lighting_direction lightingColor lighting_color lightingIntensity lighting_intensity \
        lightingLights lighting_lights axesWorld axes_world axesLocalLayer axes_local_layer \
        axesReferenceMarker axes_reference_marker \
        axesSizePixels axes_size_pixels} {
        set ::GX::Engine3D::$field [dict get $current $key]
    }
    if {[dict get $current active_timeline_id] ne ""} {
        set ::GX::Engine3D::timelineId [dict get $current active_timeline_id]
        set timeline [activeTimeline]
        set ::GX::Engine3D::timelineUnit [dict get $timeline unit]
        set ::GX::Engine3D::timelineTimes [join [dict get $timeline times] {;}]
        foreach {variable key} {timelineFrame current_frame timelineTime current_time \
            timelineRate rate timelineLoop loop timelineRangeFirst range_first timelineRangeLast range_last} {
            set ::GX::Engine3D::$variable [dict get $timeline $key]
        }
    }
    if {!$::GX::Engine3D::embedded} {wm protocol $window WM_DELETE_WINDOW ::GX::Engine3D::close}
    if {$::GX::Engine3D::panelHook ne {}} {uplevel #0 [list {*}$::GX::Engine3D::panelHook $window]}
    refreshLayers
    return $window
}
proc ::GX::Engine3D::close {} {
    if {$::GX::Engine3D::hostWidgetChanging} return
    hostEscapeRemove
    incr ::GX::Engine3D::mountGeneration
    if {$::GX::Engine3D::resizePending ne {}} {catch {after cancel $::GX::Engine3D::resizePending};set ::GX::Engine3D::resizePending {}}
    if {$::GX::Engine3D::sidebarPending ne {}} {after cancel $::GX::Engine3D::sidebarPending;set ::GX::Engine3D::sidebarPending {}}
    variable scientificDocumentId
    if {[info exists scientificDocumentId]&&$scientificDocumentId ne {}} {catch {::GX::PlotDatasetAPIv4::saveInteractivePresentation $scientificDocumentId};set scientificDocumentId {}}
    variable window
    variable photo
    variable lastPng
    incr ::GX::Engine3D::gestureGeneration
    if {$::GX::Engine3D::pendingGestureCancelJob ne {}} {after cancel $::GX::Engine3D::pendingGestureCancelJob;set ::GX::Engine3D::pendingGestureCancelJob {}}
    set ::GX::Engine3D::pendingGestureCancel {}
    if {$::GX::Engine3D::pendingDragJob ne {}} {after cancel $::GX::Engine3D::pendingDragJob;set ::GX::Engine3D::pendingDragJob {}}
    set ::GX::Engine3D::pendingDragEnd {}
    set ::GX::Engine3D::pendingBackend ""
    set ::GX::Engine3D::pendingSession ""
    set ::GX::Engine3D::pendingAddedLayer ""
    set ::GX::Engine3D::activeNewLayer ""
    set ::GX::Engine3D::pendingGizmoEnd ""
    set ::GX::Engine3D::cameraQueue {}
    if {$::GX::Engine3D::timelineTimer ne ""} {
        after cancel $::GX::Engine3D::timelineTimer
        set ::GX::Engine3D::timelineTimer ""
    }
    if {$::GX::Engine3D::closeHook ne {}} {uplevel #0 [list {*}$::GX::Engine3D::closeHook]}
    stopWorker
    set ::GX::Engine3D::gizmoActive 0
    incr ::GX::Engine3D::renderGeneration
    if {$photo ne ""} {image delete $photo;set photo ""}
    set ::GX::Engine3D::hostWidgetChanging 1
    try {if {[winfo exists $window]} {destroy $window}} finally {set ::GX::Engine3D::hostWidgetChanging 0}
    set window .gx3de_viewer;set ::GX::Engine3D::embedded 0
    catch {file delete -- [tempPng]}
    set lastPng ""
    set ::GX::Engine3D::selectionFrameDirty 0
}
proc ::GX::Engine3D::cancelRendering {{preservePending 0}} {
    set ::GX::Engine3D::cancelRequested 1
    incr ::GX::Engine3D::renderGeneration
    if {!$preservePending} {
        foreach id [list $::GX::Engine3D::pendingAddedLayer $::GX::Engine3D::activeNewLayer] {
            if {$id ne ""} {catch {rollbackArtifact $id}}
        }
        set ::GX::Engine3D::pendingBackend ""
        set ::GX::Engine3D::pendingSession ""
        set ::GX::Engine3D::pendingAddedLayer ""
        set ::GX::Engine3D::activeNewLayer ""
        catch {refreshLayers}
    }
    stopWorker
    set ::GX::Engine3D::gizmoActive 0
    set ::GX::Engine3D::pendingGizmoEnd ""
    set ::GX::Engine3D::cameraQueue {}
    set ::GX::Engine3D::status "Native rendering cancelled"
}
proc ::GX::Engine3D::stopWorker {} {
    variable worker
    if {$::GX::Engine3D::workerRssTimer ne ""} {
        after cancel $::GX::Engine3D::workerRssTimer
        set ::GX::Engine3D::workerRssTimer ""
    }
    if {$worker eq ""} return
    set ::GX::Engine3D::workerLine [list dead "Native renderer worker cancelled"]
    catch {fileevent $worker readable {}}
    catch {puts $worker [list close];flush $worker}
    foreach process [pid $worker] {if {$::tcl_platform(platform) eq "unix"} {catch {exec kill -TERM -- $process}}}
    catch {::close $worker}
    set worker ""
}

::GX::viewerBackendRegister gx3de_viewer ::GX::Engine3D::backend

# Retained Plot v4 representations use the same native host and public Viewer
# scene state; no live Dataset or source Variant is needed to inspect them.
proc ::GX::native3DScientificDocumentRead {id} {
    set item [interactiveDocumentRead $id]
    if {[dict get $item module_id] ne {plot.dataset}||[dict get $item provider_id] ne {native_3d}||[dict get $item format] ne {gxtxt.plot_dataset.native_v4_scene}} {error {Document is not an owned native Plot v4 scientific representation}}
    set payload [dict get $item payload]
    if {[dict get $payload renderer_owner] ne {PLOT_DATASET_API_v4}||![dict exists $payload scientific_figure]} {error {Invalid native scientific representation ownership}}
    return $payload
}
proc ::GX::native3DOpenScientificDocument {id} {
    set payload [native3DScientificDocumentRead $id]
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    ::GX::PlotDatasetAPIv4::activateInteractive $id
    set scene [viewerSceneResolve viewer.native_3d native_3d]
    dict set scene scientific_figure [dict get $payload scientific_figure]
    dict set scene open_context [dict create scene_only 1 scientific_document_id $id]
    dict set scene dataset_private_context {}
    return [::GX::Engine3D::backend open $scene]
}

# One editable Engine3D controller can be mounted in one arbitrary Tk owner.
# Suspend moves widgets only; Scene, worker, camera, photo and edit hooks remain
# under their existing owners. It is not an independent host/scene registry.
proc ::GX::native3DGuiHostMount {parent module provider {callbacks {}}} {
    if {![winfo exists $parent]} {error {Native3D mount parent no longer exists}}
    if {$::GX::Engine3D::workerBusy} {error {Finish or cancel the active Native3D request before changing its host}}
    ::GX::Engine3D::configureHost $module $provider $callbacks
    set target [expr {$parent eq "." ? ".native3d" : "$parent.native3d"}]
    if {$::GX::Engine3D::window eq $target && [winfo exists $target]} {return $target}
    if {[winfo exists $target]} {error {Native3D mount destination already exists}}
    ::GX::Engine3D::hostRemoveWidget
    set ::GX::Engine3D::window $target;set ::GX::Engine3D::embedded 1
    incr ::GX::Engine3D::mountGeneration
    return [::GX::Engine3D::panel 0]
}
proc ::GX::Engine3D::hostRemoveWidget {} {
    variable window;variable resizePending
    hostEscapeRemove
    if {$resizePending ne {}} {catch {after cancel $resizePending};set resizePending {}}
    if {$::GX::Engine3D::sidebarPending ne {}} {after cancel $::GX::Engine3D::sidebarPending;set ::GX::Engine3D::sidebarPending {}}
    set ::GX::Engine3D::hostWidgetChanging 1
    try {if {[winfo exists $window]} {destroy $window}} finally {set ::GX::Engine3D::hostWidgetChanging 0}
}
proc ::GX::native3DGuiHostSuspend {} {
    if {$::GX::Engine3D::workerBusy || $::GX::Engine3D::gizmoActive || $::GX::Engine3D::cameraQueue ne {} || $::GX::Engine3D::pendingBackend ne {}} {error {Finish or cancel the current Native3D gesture/request before switching views}}
    set receipt [dict create api_id NATIVE_3D_GUI_HOST_STATE_v1 session_token [interactiveDocumentSessionToken] module_id [::GX::Engine3D::ownerModule] viewer_id [::GX::Engine3D::ownerProvider] worker_generation $::GX::Engine3D::workerGeneration view [viewerSceneGet [::GX::Engine3D::ownerModule] [::GX::Engine3D::ownerProvider]] selected_layer $::GX::Engine3D::selectedLayer]
    ::GX::Engine3D::hostRemoveWidget
    set ::GX::Engine3D::window .gx3de_suspended
    dict set receipt mount_generation [incr ::GX::Engine3D::mountGeneration]
    return $receipt
}
proc ::GX::native3DGuiHostResume {parent receipt} {
    if {[dict get $receipt api_id] ne "NATIVE_3D_GUI_HOST_STATE_v1" || [dict get $receipt session_token] ne [interactiveDocumentSessionToken]} {error {Native3D suspended host belongs to a previous Session lifetime}}
    if {[dict get $receipt mount_generation]!=$::GX::Engine3D::mountGeneration || [dict get $receipt worker_generation]!=$::GX::Engine3D::workerGeneration || [dict get $receipt module_id] ne [::GX::Engine3D::ownerModule] || [dict get $receipt viewer_id] ne [::GX::Engine3D::ownerProvider]} {error {Native3D suspended controller was closed or replaced}}
    if {[viewerSceneGet [dict get $receipt module_id] [dict get $receipt viewer_id]] ne [dict get $receipt view]} {error {Native3D view changed while suspended; inspect its current state explicitly}}
    set callbacks {};foreach key {panel close edit selection} {dict set callbacks $key [set ::GX::Engine3D::${key}Hook]}
    set widget [native3DGuiHostMount $parent [dict get $receipt module_id] [dict get $receipt viewer_id] $callbacks]
    set ::GX::Engine3D::selectedLayer [dict get $receipt selected_layer]
    ::GX::Engine3D::refreshLayers
    return $widget
}
proc ::GX::Engine3D::hostDestroyed {owner widget} {
    if {$widget eq $owner && !$::GX::Engine3D::hostWidgetChanging && $owner eq $::GX::Engine3D::window} {close}
}
# Tk sends child key events through their toplevel tag, not ancestor frames.
# Keep one scoped binding on that actual toplevel, preserving its other handlers.
proc ::GX::Engine3D::hostEscapeInstall {} {
    hostEscapeRemove
    variable escapeOwner;variable escapePrevious;variable escapeInstalled
    set escapeOwner [winfo toplevel $::GX::Engine3D::window]
    set escapePrevious [bind $escapeOwner <Escape>]
    bind $escapeOwner <Escape> +[list ::GX::Engine3D::hostEscape %W]
    set escapeInstalled [bind $escapeOwner <Escape>]
}
proc ::GX::Engine3D::hostEscapeRemove {} {
    variable escapeOwner;variable escapePrevious;variable escapeInstalled
    if {$escapeOwner ne {} && [winfo exists $escapeOwner]} {
        set current [bind $escapeOwner <Escape>]
        if {$current eq $escapeInstalled} {
            bind $escapeOwner <Escape> $escapePrevious
        } else {
            # Another owner may have appended a handler since this mount.
            set own [list ::GX::Engine3D::hostEscape %W]
            set retained {};foreach line [split $current \n] {if {$line ne $own} {lappend retained $line}}
            bind $escapeOwner <Escape> [join $retained \n]
        }
    }
    set escapeOwner {};set escapePrevious {};set escapeInstalled {}
}
proc ::GX::Engine3D::hostEscape {widget} {
    set host $::GX::Engine3D::window
    if {![winfo exists $host] || ![winfo exists $widget]} return
    if {$widget ne $host && [string first "$host." $widget]!=0} return
    if {!$::GX::Engine3D::gizmoActive && $::GX::Engine3D::dragMode eq {} && !$::GX::Engine3D::gestureStarting && $::GX::Engine3D::pendingGestureCancel eq {}} return
    showError ::GX::Engine3D::cancelGesture
    return -code break
}
proc ::GX::Engine3D::hostViewportSize {} {
    set canvas $::GX::Engine3D::window.canvas
    if {![winfo exists $canvas] || [winfo width $canvas]<16 || [winfo height $canvas]<16} {return {960 640}}
    return [list [expr {max(16,min(4096,[winfo width $canvas]))}] [expr {max(16,min(4096,[winfo height $canvas]))}]]
}
proc ::GX::Engine3D::hostSidebarContentWidth {canvas width} {
    if {![winfo exists $canvas] || ![winfo exists $canvas.controls]} return
    if {$width eq {}} {set width [winfo width $canvas]}
    # The viewport remains bounded; its existing scrollbar must reach the full
    # requested controls, including captions enlarged by the configured font.
    set contentWidth [expr {max(460,$width,[winfo reqwidth $canvas.controls])}]
    if {[$canvas itemcget controls -width] != $contentWidth} {
        $canvas itemconfigure controls -width $contentWidth
    }
    $canvas configure -scrollregion [list 0 0 $contentWidth [winfo reqheight $canvas.controls]]
}
proc ::GX::Engine3D::hostSidebarSchedule {owner actual} {
    if {$actual ne $owner} return
    if {$::GX::Engine3D::sidebarPending ne {}} {after cancel $::GX::Engine3D::sidebarPending}
    set ::GX::Engine3D::sidebarPending [after idle ::GX::Engine3D::hostSidebarLayout]
}
proc ::GX::Engine3D::hostSidebarLayout {} {
    set ::GX::Engine3D::sidebarPending {}
    set window $::GX::Engine3D::window
    if {![winfo exists $window.canvas] || ![winfo exists $window.side]} return
    set width [winfo width $window]
    set mode $::GX::Engine3D::sidebarMode
    set shown [expr {$mode eq {show} || ($mode eq {auto} && (!$::GX::Engine3D::embedded || $width>=760))}]
    if {$shown} {
        set sideWidth [expr {$::GX::Engine3D::embedded ? max(200,min(360,int($width*.38))) : 460}]
        $window.side.scroll configure -width $sideWidth
        if {[winfo manager $window.side] eq {}} {pack $window.side -side left -fill y -padx 4 -pady 4 -before $window.canvas}
    } else {pack forget $window.side}
    $window.controlsToggle configure -text [expr {$shown ? {Hide view controls} : {Show view controls}}]
}
proc ::GX::Engine3D::hostSidebarToggle {} {
    set window $::GX::Engine3D::window
    if {![winfo exists $window.side]} return
    set ::GX::Engine3D::sidebarMode [expr {[winfo manager $window.side] eq {} ? {show} : {hide}}]
    hostSidebarLayout
}
proc ::GX::Engine3D::hostResizeSchedule {width height} {
    variable resizePending
    if {$width<16||$height<16} return
    if {$resizePending ne {}} {catch {after cancel $resizePending}}
    set resizePending [after 150 ::GX::Engine3D::hostResize]
}
proc ::GX::Engine3D::hostResize {} {
    variable resizePending;variable worker;variable workerBusy;variable renderedSize
    set resizePending {}
    if {![winfo exists $::GX::Engine3D::window.canvas] || $worker eq {}} return
    if {$workerBusy} {set resizePending busy;return}
    if {([hostViewportSize] eq $renderedSize && !$::GX::Engine3D::selectionFrameDirty) || $::GX::Engine3D::photo eq {}} return
    lassign [hostViewportSize] width height
    set destination [tempPng];set staged "$destination.resize.[pid].[clock clicks].png"
    try {
        rpc [list viewport $width $height $staged]
        if {![pngComplete $staged]} {error {Native viewport resize did not produce a complete frame}}
        file rename -force -- $staged $destination
        set renderedSize [list $width $height]
        displayNativePng $destination
        set ::GX::Engine3D::selectionFrameDirty 0
    } on error {message opts} {set ::GX::Engine3D::status "Viewport resize: $message"} finally {catch {file delete -- $staged}}
}

source [file join [file dirname [info script]] native3d_texture_v1.tcl]
