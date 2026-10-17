# GX-TXT Plot Dataset 3D API v1: scientific Plot Variant to shared scene.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::PlotDataset3DAPIv1 {
    variable apiDir [file dirname [file normalize [info script]]]
    variable moduleId plot.dataset
    variable viewerModule viewer.native_3d
    variable viewerId native_3d
}

proc ::GX::PlotDataset3DAPIv1::apiInfo {} {
    return [dict create api_name PLOT_DATASET_3D_API_v1 api_version 1 \
        module_id plot.dataset module_version [::GX::moduleField plot.dataset version] \
        plot_types {scatter3 line3 surface mesh contour3 trisurf heatmap} \
        capabilities {build_scene open_interactive refresh_interactive persistent_source_binding static_plot_unchanged manual_sync source_fingerprint independent_representation readonly_native3d_preview_export calibrated_native3d_figure preview_compatibility}]
}

proc ::GX::PlotDataset3DAPIv1::sources {} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v1
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
    set result {}
    foreach variant [::GX::plotVariantIds plot.dataset plot.dataset.xyz] {
        set ref [::GX::PlotDatasetAPIv1::openPlot plot.dataset.xyz $variant]
        if {![catch {_source $ref}]} {lappend result $ref}
    }
    return $result
}

proc ::GX::PlotDataset3DAPIv1::sourceInfo {plotRef} {
    set ref [_ref $plotRef]
    set source [_source $ref]
    set bindings [dict create]
    foreach role {x y z family color} {
        set binding [::GX::plotVariantBindingGet plot.dataset plot.dataset.xyz [dict get $ref variant_id] $role]
        if {$binding ne ""} {dict set bindings $role $binding}
    }
    return [dict create plot_ref $ref graph [::GX::PlotDatasetAPIv2::readPlot $ref] \
        bindings $bindings source_dataset_id [dict get $source dataset_id] \
        source_sha256 [dict get $source payload sha256] fingerprint [sourceFingerprint $ref]]
}

# A graph/Variant has no durable revision counter. Hash its persistent
# scientific configuration and canonical source digests, never render mtimes.
proc ::GX::PlotDataset3DAPIv1::sourceFingerprint {plotRef} {
    set ref [_ref $plotRef]
    set source [_source $ref]
    set plot [::GX::PlotDatasetAPIv2::readPlot $ref]
    set items [list [dict get $ref module_id] [dict get $ref graph_id] [dict get $ref variant_id]]
    set config [dict get $plot config]
    foreach key [lsort [dict keys $config]] {lappend items config $key [dict get $config $key]}
    foreach role {x y z family color} {
        set binding [::GX::plotVariantBindingGet plot.dataset plot.dataset.xyz [dict get $ref variant_id] $role]
        if {$binding eq ""} continue
        set dataset [dict get $binding dataset_id]
        lappend items binding $role $dataset [dict get $binding variable_id] \
            [dict get [::GX::sessionInspectionDatasetPayload $dataset] sha256]
    }
    set bytes [encoding convertto utf-8 $items]
    return [exec -- python3 -c {import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())} << $bytes]
}

proc ::GX::PlotDataset3DAPIv1::_representation {id} {
    set document [::GX::interactiveDocumentRead $id]
    if {[dict get $document module_id] ne "plot.dataset" ||
        [dict get $document provider_id] ne "native_3d" ||
        [dict get $document format] ne "gxtxt.plot_dataset.interactive_scene"} {
        error "Interactive representation '$id' does not belong to Plot Dataset."
    }
    return [dict get $document payload]
}

proc ::GX::PlotDataset3DAPIv1::representations {} {
    set out {}
    foreach item [::GX::interactiveDocumentList plot.dataset native_3d] {
        if {[dict get $item format] ne "gxtxt.plot_dataset.interactive_scene"} continue
        lappend out [dict create id [dict get $item id] status [syncStatus [dict get $item id]] \
            plot_ref [dict get [_representation [dict get $item id]] source_plot_reference]]
    }
    return $out
}

proc ::GX::PlotDataset3DAPIv1::syncStatus {representationId} {
    set state [_representation $representationId]
    set ref [dict get $state source_plot_reference]
    if {[catch {set current [sourceFingerprint $ref]}]} {return "SOURCE MISSING"}
    if {$current eq [dict get $state last_successful_sync_fingerprint]} {return SYNCED}
    return "OUT OF SYNC"
}

proc ::GX::PlotDataset3DAPIv1::_activeLayers {} {
    set layers [dict create]
    foreach id [::GX::viewerLayerIds viewer.native_3d native_3d] {
        dict set layers $id [::GX::viewerLayerGet viewer.native_3d native_3d $id]
    }
    return $layers
}

proc ::GX::PlotDataset3DAPIv1::_currentRepresentation {state} {
    set ids [lsort [dict keys [dict get $state layers]]]
    expr {$ids eq [::GX::viewerLayerIds viewer.native_3d native_3d]}
}

proc ::GX::PlotDataset3DAPIv1::_saveActiveRepresentation {} {
    foreach item [::GX::interactiveDocumentList plot.dataset native_3d] {
        if {[dict get $item format] ne "gxtxt.plot_dataset.interactive_scene"} continue
        set id [dict get $item id]
        set state [_representation $id]
        if {![_currentRepresentation $state]} continue
        dict set state viewer_scene [::GX::viewerSceneGet viewer.native_3d native_3d]
        dict set state layers [_activeLayers]
        ::GX::interactiveDocumentUpdate $id $state
        return $id
    }
    return ""
}

proc ::GX::PlotDataset3DAPIv1::activateRepresentation {representationId} {
    set state [_representation $representationId]
    _saveActiveRepresentation
    foreach id [::GX::viewerLayerIds viewer.native_3d native_3d] {
        ::GX::viewerLayerRemove viewer.native_3d native_3d $id
    }
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict get $state viewer_scene]
    dict for {id layer} [dict get $state layers] {
        ::GX::viewerLayerSet viewer.native_3d native_3d $id $layer
    }
    ::GX::sessionPersistenceCommit
    return [dict create representation_id $representationId status [syncStatus $representationId] \
        plot_ref [dict get $state source_plot_reference]]
}

proc ::GX::PlotDataset3DAPIv1::_ref {plotRef} {
    if {[catch {dict size $plotRef}] || ![dict exists $plotRef graph_id] ||
        [dict get $plotRef graph_id] ne "plot.dataset.xyz" ||
        ![dict exists $plotRef variant_id] || [dict get $plotRef variant_id] eq ""} {
        error "Plot Dataset 3D requires a persistent plot.dataset.xyz Variant reference."
    }
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v1
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v2
    ::GX::PlotDatasetAPIv2::readPlot $plotRef
    return $plotRef
}

proc ::GX::PlotDataset3DAPIv1::_source {plotRef} {
    set variant [dict get $plotRef variant_id]
    set dataset ""
    set axes [dict create]
    foreach role {x y z} {
        set binding [::GX::plotVariantBindingGet plot.dataset plot.dataset.xyz $variant $role]
        if {$binding eq ""} {error "Plot Dataset 3D Variant has no $role binding."}
        if {$dataset eq ""} {set dataset [dict get $binding dataset_id]}
        if {[dict get $binding dataset_id] ne $dataset} {
            error "Plot Dataset 3D X/Y/Z bindings must refer to one Dataset."
        }
        dict set axes $role [dict get $binding variable_id]
    }
    set payload [::GX::sessionInspectionDatasetPayload $dataset]
    return [dict create dataset_id $dataset payload $payload axes $axes]
}

proc ::GX::PlotDataset3DAPIv1::buildScene {plotRef {representationId ""}} {
    variable apiDir
    set ref [_ref $plotRef]
    set source [_source $ref]
    set sourceRevision [sourceFingerprint $ref]
    set previous [dict create]
    if {$representationId ne ""} {
        set previous [_representation $representationId]
        if {[dict get $previous source_plot_reference] ne $ref} {
            error "Interactive representation belongs to a different exact graph/Variant."
        }
    }
    _saveActiveRepresentation
    if {$representationId ne ""} {
        set previous [_representation $representationId]
        set scenePresentation [dict get $previous viewer_scene]
        if {[_currentRepresentation $previous]} {
            set scenePresentation [::GX::viewerSceneGet viewer.native_3d native_3d]
        }
    } else {
        set scenePresentation [::GX::viewerSceneGet viewer.native_3d native_3d]
    }
    set plot [::GX::PlotDatasetAPIv2::readPlot $ref]
    set plotType [dict get $plot config plot_type]
    set pointOrder [dict get $plot config point_order]
    set contourLevels [dict get $plot config contour_levels]
    if {$plotType ni {scatter3 line3 surface mesh contour3 trisurf heatmap}} {
        error "Plot Dataset 3D plot type '$plotType' is unavailable interactively."
    }
    # The normal Plot Dataset path owns preparation and all scientific
    # interpretation. Its prepared cache is a bounded, derived display source.
    ::GX::PlotDatasetAPIv2::render $ref
    set artifacts [::GX::PlotDatasetAPIv2::artifacts $ref]
    set cache [dict get $artifacts render_cache]
    if {![file isfile $cache]} {error "Plot Dataset 3D prepared cache is missing."}
    # Interactive geometry belongs to the independent Viewer representation.
    # Deleting the source Variant must not remove an already created view.
    set parent [file join $::GX::currentSession resources viewer.native_3d plot_representations]
    file mkdir $parent
    set sceneDir [file join $parent [format "interactive_scene_%d_%d" [clock seconds] [clock microseconds]]]
    set octave [expr {[info exists ::GX::cfg(octave_cmd)] && $::GX::cfg(octave_cmd) ne "" ? $::GX::cfg(octave_cmd) : "octave"}]
    set script [file normalize [file join $apiDir .. runtime plot_dataset_scene_export.m]]
    if {![file isfile $script]} {error "Plot Dataset 3D scene exporter is missing."}
    if {[catch {exec -- env DISPLAY= GXTXT_GRAPHICS_MODE=headless $octave --quiet --no-gui \
        $script $cache $sceneDir $pointOrder $contourLevels 2>@1} output options]} {
        catch {file delete -force -- $sceneDir}
        return -options $options "Plot Dataset 3D scene export failed: $output"
    }
    set paths [lsort [glob -nocomplain -types f -directory $sceneDir scene_*.vtp]]
    if {![llength $paths]} {error "Plot Dataset 3D generated no interactive scene layers."}
    if {![::GX::moduleIsEnabled viewer.native_3d]} {
        ::GX::moduleSetEnabled viewer.native_3d 1
    }
    ::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
    set oldLayers [::GX::viewerLayerIds viewer.native_3d native_3d]
    set newLayers {}
    set sourceId [dict get $source dataset_id]
    set sourceSha [dict get $source payload sha256]
    set order 0
    set runId [clock microseconds]
    set priorOrdered {}
    if {$representationId ne "" && [dict exists $previous layers]} {
        dict for {priorId priorLayer} [dict get $previous layers] {
            lappend priorOrdered [list [dict get $priorLayer layer_order] $priorId]
        }
        set priorOrdered [lsort -integer -index 0 $priorOrdered]
    }
    try {
    foreach path $paths {
        incr order
        set relative [string range $path [expr {[string length [file normalize $::GX::currentSession]]+1}] end]
        set artifact [::GX::viewerArtifactRegister $relative]
        set layerId [format "plot_%d_%04d" $runId $order]
        set kind [expr {$plotType eq "scatter3" ? "points" :
            ($plotType in {line3 contour3} ? "trajectory" : "surface")}]
        set representation [expr {$plotType eq "mesh" ? "wireframe" : "surface"}]
        set scalar [expr {$plotType in {surface mesh trisurf heatmap scatter3} ? "scientific_scalar" : ""}]
        # Scatter without C has no array. The renderer then uses a fixed color.
        if {$plotType eq "scatter3" && [::GX::plotVariantBindingGet plot.dataset plot.dataset.xyz [dict get $ref variant_id] color] eq ""} {
            set scalar ""
        }
        ::GX::viewerLayerSet viewer.native_3d native_3d $layerId [dict merge \
            [dict create kind $kind source_mode artifact format vtp format_version 1 \
                layer_order $order representation $representation scalar_array $scalar \
                source_dataset_id $sourceId source_dataset_sha256 $sourceSha \
                source_update_policy snapshot] $artifact]
        if {$representationId ne "" && $order <= [llength $priorOrdered]} {
                set prior [dict get $previous layers [lindex [lindex $priorOrdered [expr {$order-1}]] 1]]
                set current [::GX::viewerLayerGet viewer.native_3d native_3d $layerId]
                if {[dict get $prior kind] eq [dict get $current kind] &&
                    [dict get $prior scalar_array] eq [dict get $current scalar_array]} {
                    foreach field {visible opacity representation colormap scalar_range} {
                        dict set current $field [dict get $prior $field]
                    }
                    ::GX::viewerLayerSet viewer.native_3d native_3d $layerId $current
                }
        }
        lappend newLayers $layerId
    }
    ::GX::viewerSceneSet viewer.native_3d native_3d [dict merge \
        $scenePresentation [dict create scene_mode scientific]]
    } on error {problem options} {
        foreach layer $newLayers {::GX::viewerLayerRemove viewer.native_3d native_3d $layer}
        return -options $options $problem
    }
    foreach old $oldLayers {::GX::viewerLayerRemove viewer.native_3d native_3d $old}
    set provenance [dict create source_module_id plot.dataset source_graph_id [dict get $ref graph_id] \
        source_variant_id [dict get $ref variant_id] source_plot_reference $ref \
        source_fingerprint $sourceRevision last_successful_sync_fingerprint $sourceRevision \
        source_dataset_id $sourceId source_dataset_sha256 $sourceSha \
        viewer_scene [::GX::viewerSceneGet viewer.native_3d native_3d] layers [_activeLayers]]
    if {$representationId eq ""} {
        set item [::GX::interactiveDocumentCreate plot.dataset native_3d \
            gxtxt.plot_dataset.interactive_scene 1.0 $provenance]
        set representationId [dict get $item id]
    } else {
        ::GX::interactiveDocumentUpdate $representationId $provenance
    }
    ::GX::sessionPersistenceCommit
    return [dict create plot_ref $ref plot_type $plotType source_dataset_id $sourceId \
        source_sha256 $sourceSha layer_ids [::GX::viewerLayerIds viewer.native_3d native_3d] \
        scene_dir $sceneDir static_artifact [dict get $artifacts graph_artifact] \
        representation_id $representationId source_fingerprint $sourceRevision status SYNCED]
}

proc ::GX::PlotDataset3DAPIv1::openInteractive {plotRef} {
    set scene [buildScene $plotRef]
    ::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]
    return $scene
}

proc ::GX::PlotDataset3DAPIv1::refreshInteractive {plotRef} {
    foreach item [representations] {
        if {[dict get $item plot_ref] eq $plotRef} {
            return [syncInteractive [dict get $item id]]
        }
    }
    return [openInteractive $plotRef]
}

proc ::GX::PlotDataset3DAPIv1::syncInteractive {representationId} {
    set state [_representation $representationId]
    set ref [dict get $state source_plot_reference]
    sourceFingerprint $ref
    set scene [buildScene $ref $representationId]
    ::GX::viewerOpen viewer.native_3d native_3d [dict create scene_only 1]
    return $scene
}

# Ordinary embedded preview: caller-owned temporary files, no persistent scene.
proc ::GX::PlotDataset3DAPIv1::previewExportCommand {plotRef output} {
    variable apiDir
    set ref [_ref $plotRef]
    set artifacts [::GX::PlotDatasetAPIv2::artifacts $ref]
    set cache [dict get $artifacts render_cache]
    set runtime [file join [dict get $artifacts output_dir] runtime.ini]
    if {![file isfile $cache] || ![file isfile $runtime]} {error {Original 3D preparation/runtime unavailable; render the graph first.}}
    if {[file size $cache]>134217728} {error {Prepared graph exceeds the 128 MiB preview intake budget; static graph preserved.}}
    set saved [::GX::parseIni $runtime]
    set source [_source $ref]
    set sourcePath [dict get $source payload path]
    set originalPath [dict get $saved dataset.path]
    if {![file isfile $originalPath] || [::GX::sha256File $originalPath] ne [dict get $source payload sha256]} {
        error {Static graph preparation belongs to a different Dataset revision; rerender the graph before preview.}
    }
    set graph [::GX::PlotDatasetAPIv2::readPlot $ref]
    dict for {field value} [dict get $graph config] {
        set k "plot.plot.dataset.xyz.$field"
        if {[dict exists $saved $k] && [dict get $saved $k] ne $value} {error "Graph $field changed since the static render; rerender before preview."}
    }
    foreach field [::GX::moduleConfigKeys plot.dataset] {
        if {[info exists ::GX::moduleCfg(plot.dataset,$field)] && [dict exists $saved config.$field] && [dict get $saved config.$field] ne $::GX::moduleCfg(plot.dataset,$field)} {
            error "Scientific preparation setting $field changed; rerender before preview."
        }
    }
    set graphKey [::GX::plotVariantKey plot.dataset.xyz [dict get $ref variant_id]]
    foreach {array prefix} {axisOverride axis.plot.dataset.xyz legendOverride legend.plot.dataset.xyz} {
        upvar #0 ::GX::$array a
        foreach name [array names a "$graphKey,*"] {
            set field [string range $name [expr {[string length $graphKey]+1}] end]
            if {[dict exists $saved $prefix.$field] && [dict get $saved $prefix.$field] ne $a($name)} {error "Graph $array/$field changed since static render; rerender before preview."}
        }
    }
    foreach role {x y z family color} {
        set binding [::GX::plotVariantResolvedBinding plot.dataset plot.dataset.xyz [dict get $ref variant_id] $role]
        set value [expr {$binding eq {}?{}:"primary.[dict get $binding name]"}]
        if {[dict exists $saved bindings.$role] && [dict get $saved bindings.$role] ne $value} {error "Graph $role binding changed since the static render; rerender before preview."}
    }
    # Dataset view policy belongs to the successful static-render snapshot.
    # A metadata-only edit must not silently present the old cache as current.
    set coordinateReceipt [file join [dict get $artifacts output_dir] coordinate_presentation.ini]
    set coordinateState {};if {[file isfile $coordinateReceipt]} {set coordinateState [::GX::parseIni $coordinateReceipt]}
    set seen {}
    foreach role {x y z family color} {
        set binding [::GX::plotVariantResolvedBinding plot.dataset plot.dataset.xyz [dict get $ref variant_id] $role]
        if {$binding eq {}} continue
        set id [dict get $binding dataset_id];if {$id in $seen} continue;lappend seen $id
        set context [::GX::datasetCoordinateRead $::GX::currentSession $id]
        set matched 0
        if {[dict exists $coordinateState coordinate_presentation.count]} {
            if {![dict exists $coordinateState coordinate_presentation.api_version]||[dict get $coordinateState coordinate_presentation.api_version] ne "1"} {error {Unsupported coordinate render receipt; rerender the graph.}}
            set count [dict get $coordinateState coordinate_presentation.count]
            if {![string is integer -strict $count]||$count<0||$count>1024} {error {Invalid coordinate render receipt; rerender the graph.}}
            for {set i 1} {$i<=$count} {incr i} {
                if {[dict get $coordinateState dataset.$i.id] ne $id} continue
                if {[dict get $coordinateState dataset.$i.revision] ne [dict get $context revision]||[dict get $coordinateState dataset.$i.source_sha256] ne [dict get $context source_sha256]} {error {Dataset coordinate settings changed since static render; rerender before preview.}}
                set matched 1;break
            }
        }
        if {!$matched&&[dict get $context revision]>0} {error {Static graph has no current Dataset coordinate receipt; rerender before preview.}}
    }
    # Reuse the exact configuration that produced the retained static graph.
    # The prepared cache and runtime are read only, including legacy Sessions.
    set envmap [::GX::plotEnv plot.dataset]
    set recorded {}
    dict for {k value} $saved {
        if {[regexp {^graphics_effective\.(GXTXT_(PLOT(_|3D_).*|PNG_DPI))$} $k -> name] && ![string match *_FILE $name]} {lappend recorded "$name=$value"}
    }
    if {[llength $recorded]} {set envmap $recorded}
    set graphicsMap [::GX::moduleGraphicsEnvMap]
    foreach field [::GX::moduleGraphicsFields] {
        if {$field eq "background"} continue
        set value [string trim [::GX::plotVariantGraphicsGet plot.dataset plot.dataset.xyz [dict get $ref variant_id] $field]]
        if {$value ne "" && $value ne "inherit" && [dict exists $graphicsMap $field]} {set envmap [::GX::envListReplace $envmap [dict get $graphicsMap $field] $value]}
    }
    set script [file normalize [file join $apiDir .. runtime plot_dataset_preview_export.m]]
    return [concat [list env GXTXT_GRAPHICS_MODE=headless GXTXT_PROGRESS_ENABLED=0] $envmap [list [auto_execok tclsh] \
        [file join $::GX::scriptDir core tcl native3d_plot_prepare_worker.tcl] $::GX::cfg(octave_cmd) $script $cache $runtime $output \
        [::GX::runtimeToolRequired python] [file join $::GX::scriptDir core python native3d_plot_preview.py]]]
}

# Read-only UI eligibility; diagnostics also guard the export itself.
proc ::GX::PlotDataset3DAPIv1::previewCompatibility {ref} {
    set ref [_ref $ref]
    set graph [::GX::PlotDatasetAPIv2::readPlot $ref]
    if {[dict get $graph config plot_type] ni {surface mesh scatter3 line3 contour3 trisurf heatmap}} {error {This graph type has no exact Native3D geometry contract.}}
    set artifacts [::GX::PlotDatasetAPIv2::artifacts $ref]
    previewExportCommand $ref [file join [dict get $artifacts output_dir] .unused_preview_eligibility]
    set saved [::GX::parseIni [file join [dict get $artifacts output_dir] runtime.ini]]
    dict for {key value} $saved {
        if {[regexp {^axis\.plot\.dataset\.xyz\.(x|y|z)_?(scale|dir)$} $key] && $value ni {{} inherit linear normal}} {error {Logarithmic/reversed axes require a Native3D nonlinear calibrated coordinate-mapping contract.}}
    }
    return [dict create supported 1 plot_ref $ref]
}
