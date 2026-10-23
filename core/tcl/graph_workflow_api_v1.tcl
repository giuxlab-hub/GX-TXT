# GX-TXT Graph Workflow API v1
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable graphWorkflowApiVersion 1
    variable modulePublicApiActivated
    variable graphUseState
    variable graphAxisDialogTarget {}
    variable graphRuntimeSelectionOverride {}
    array set modulePublicApiActivated {}
    array set graphUseState {}
}

proc ::GX::modulePublicApiIds {moduleId} {
    set descriptor [moduleField $moduleId descriptor ""]
    if {$descriptor eq "" || ![file isfile $descriptor]} { return {} }
    set d [parseIni $descriptor]
    return [splitList [descriptorValue $d public_apis ids ""]]
}
proc ::GX::modulePublicApiDocumentation {moduleId apiId} {
    set path [moduleField $moduleId descriptor {}]
    if {$path eq {} || ![file isfile $path]} {error {Public API provider descriptor is unavailable}}
    set d [parseIni $path]
    if {$apiId ni [splitList [descriptorValue $d public_apis ids {}]]} {error {Provider does not declare this public API}}
    set contract [descriptorValue $d public_api.$apiId public_contract {}]
    return [_modulePublicApiDocumentationValidate $contract]
}
proc ::GX::_modulePublicApiDocumentationValidate {contract} {
    if {$contract eq {}} {return {}}
    # Provider-owned inert documentation. Reading never activates the provider
    # or changes Script Bridge / restricted SDK authorization.
    if {[catch {dict size $contract}] || ![dict exists $contract schema] || [dict get $contract schema] ne {gxtxt.public_api_documentation.v1} || ![dict exists $contract purpose] || [string trim [dict get $contract purpose]] eq {} || ![dict exists $contract operations]} {error {Invalid provider public documentation contract}}
    foreach key [dict keys $contract] {if {$key ni {schema purpose operations context}} {error {Unknown public documentation field}}}
    if {![dict size [dict get $contract operations]]} {error {Public documentation requires at least one declared operation}}
    dict for {operation item} [dict get $contract operations] {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $operation]} {error {Public documentation needs logical operation names}}
        foreach key {command arguments parameters result context} {if {![dict exists $item $key]} {error "Public documentation operation '$operation' requires '$key'"}}
        if {[string trim [dict get $item context]] eq {}} {error {Public operations require their actual context}}
        foreach key [dict keys $item] {if {$key ni {command arguments parameters result context example}} {error {Unknown public operation documentation field}}}
        if {![regexp {^::[A-Za-z][A-Za-z0-9_]*(?:::[A-Za-z][A-Za-z0-9_]*)+$} [dict get $item command]]} {error {Public documentation requires a literal qualified host command}}
        set names {}
        foreach formal [dict get $item arguments] {
            if {[llength $formal] ni {1 2} || ![regexp {^[A-Za-z][A-Za-z0-9_]*$} [lindex $formal 0]]} {error {Invalid public host formal argument}}
            lappend names [lindex $formal 0]
        }
        if {[llength [lsort -unique $names]]!=[llength $names] || [lsort [dict keys [dict get $item parameters]]]!=[lsort $names]} {error {Public parameter descriptions must match every declared formal argument}}
        dict for {name parameter} [dict get $item parameters] {
            foreach key {type description} {if {![dict exists $parameter $key] || [string trim [dict get $parameter $key]] eq {}} {error {Public parameters require actual type and description}}}
        }
        foreach key {type description} {if {![dict exists $item result $key] || [string trim [dict get $item result $key]] eq {}} {error {Public results require actual type and description}}}
    }
    return $contract
}
proc ::GX::modulePublicApiActivate {moduleId apiId} {
    variable modulePublicApiActivated
    pluginRuntimeTryPending $moduleId
    set key "$moduleId,$apiId"
    if {[info exists modulePublicApiActivated($key)]} {
        if {$modulePublicApiActivated($key) eq "loading"} { error "Recursive public API activation for $moduleId/$apiId." }
        return $modulePublicApiActivated($key)
    }
    pluginRuntimeGuardNewLoad $moduleId
    set descriptor [moduleField $moduleId descriptor ""]
    if {$descriptor eq "" || ![file isfile $descriptor]} { error "Module '$moduleId' has no readable descriptor." }
    set d [parseIni $descriptor]
    if {$apiId ni [splitList [descriptorValue $d public_apis ids ""]]} { error "Module '$moduleId' does not declare public API '$apiId'." }
    set rel [string trim [descriptorValue $d "public_api.$apiId" entrypoint ""]]
    if {$rel eq ""} { error "Public API '$moduleId/$apiId' has no entrypoint." }
    set root [file normalize [file dirname $descriptor]]
    set entry [file normalize [file join $root $rel]]
    if {[string first "$root/" "$entry/"] != 0 || ![file isfile $entry]} { error "Public API '$moduleId/$apiId' entrypoint is outside the module or missing." }
    set modulePublicApiActivated($key) loading
    if {[catch {_datasetPrivateWithModule $moduleId [list uplevel #0 [list source $entry]]} err opts]} {
        unset modulePublicApiActivated($key)
        return -options $opts "Public API '$moduleId/$apiId' activation failed: $err"
    }
    set modulePublicApiActivated($key) $entry
    pluginRuntimeNoteLoaded $moduleId
    return $entry
}
# plot.dataset multi-panel: activate provider-owned Graph configuration controls through the public extension hook.
proc ::GX::moduleGraphConfigExtensionsActivate {moduleId} {
    set descriptor [moduleField $moduleId descriptor ""]
    if {$descriptor eq "" || ![file isfile $descriptor]} { return }
    set d [parseIni $descriptor]
    set apiIds [splitList [descriptorValue $d public_apis ids ""]]
    set suppliesExtension 0
    foreach apiId $apiIds {
        if {"graph_config_extension" in [splitList [descriptorValue $d "public_api.$apiId" capabilities ""]]} {
            set suppliesExtension 1
            break
        }
    }
    if {!$suppliesExtension} { return }
    foreach apiId $apiIds { modulePublicApiActivate $moduleId $apiId }
}
proc ::GX::graphConfigExtensionFor {moduleId graphId} {
    moduleGraphConfigExtensionsActivate $moduleId
    return [::GX::graphConfigExtensionFor_before_graph_workflow $moduleId $graphId]
}

proc ::GX::moduleSeriesEditorExtensionsActivate {moduleId} {
    set descriptor [moduleField $moduleId descriptor ""]
    if {$descriptor eq "" || ![file isfile $descriptor]} { return }
    set d [parseIni $descriptor]
    set apiIds [splitList [descriptorValue $d public_apis ids ""]]
    set suppliesExtension 0
    foreach apiId $apiIds {
        if {"series_editor_extension" in [splitList [descriptorValue $d "public_api.$apiId" capabilities ""]]} {
            set suppliesExtension 1
            break
        }
    }
    if {!$suppliesExtension} { return }
    # Activate the module's declared API surface in descriptor order so an
    # extension entrypoint can use sibling public APIs without depending on an
    # unrelated earlier GUI action.
    foreach apiId $apiIds { modulePublicApiActivate $moduleId $apiId }
}
proc ::GX::seriesEditorExtensionFor {moduleId graphId} {
    moduleSeriesEditorExtensionsActivate $moduleId
    return [::GX::seriesEditorExtensionFor_before_graph_workflow $moduleId $graphId]
}

proc ::GX::graphAxisAddress {moduleId graphId {variantId ""}} {
    if {$graphId ni [moduleGraphIds $moduleId]} { error "Unknown graph '$moduleId/$graphId'." }
    if {$variantId ne ""} {
        if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant '$moduleId/$graphId/$variantId'." }
        return [plotVariantKey $graphId $variantId]
    }
    return $graphId
}
proc ::GX::graphAxisArtifactPath {moduleId graphId {variantId ""}} {
    variable currentSession
    if {$variantId ne "" && $currentSession ne ""} { return [plotVariantArtifact $moduleId $graphId $variantId] }
    set file [moduleGraphField $moduleId $graphId file ""]
    if {$file eq ""} { set file "[sanitize $graphId].png" }
    set root [expr {$currentSession ne "" ? $currentSession : [file join $::GX::scriptDir .gxtxt-unopened-session]}]
    if {$variantId ne ""} { return [file join $root analysis $moduleId variants $graphId $variantId $file] }
    return [file join $root analysis $moduleId $file]
}
proc ::GX::graphAxisConfigSnapshot {moduleId graphId {variantId ""}} {
    variable axisOverride
    set key [graphAxisAddress $moduleId $graphId $variantId]
    axisOverrideEnsure $key {}
    set out [dict create api_version 1 module_id $moduleId graph_id $graphId variant_id $variantId graph_key $key]
    foreach name [array names axisOverride "$key,*"] {
        set field [string range $name [expr {[string length $key]+1}] end]
        if {[string first , $field] < 0} { dict set out $field $axisOverride($name) }
    }
    return $out
}

# Headless graph presentation mutation shares the Axes dialog's CORE state.
proc ::GX::graphAxisPresentationSet {moduleId graphId variantId changes} {
    variable axisOverride
    if {[catch {dict size $changes}]} {error "Graph presentation changes must be a dictionary"}
    set key [graphAxisAddress $moduleId $graphId $variantId]
    axisOverrideEnsure $key {}
    set values [dict create]
    dict for {field raw} $changes {
        if {$field ni {xy_aspect_mode aspect_mode aspect_ratio background}} {error "Unsupported graph presentation field '$field'"}
        set value [string trim $raw]
        if {[regexp {[\r\n]} $value]} {error "Graph presentation values must be single-line"}
        if {$value eq "inherit"} {set value ""}
        if {$field eq "xy_aspect_mode" && $value ni {"" auto xy_equal}} {error "2D aspect must be inherit, auto, or xy_equal"}
        if {$field eq "background" && $value ni {"" transparent} && ![regexp {^#[0-9A-Fa-f]{6}$} $value]} {
            error "Plot background must be inherit, transparent, or #RRGGBB"
        }
        dict set values $field $value
    }
    set mode [expr {[dict exists $values aspect_mode] ? [dict get $values aspect_mode] : $axisOverride($key,aspect_mode)}]
    set ratio [expr {[dict exists $values aspect_ratio] ? [dict get $values aspect_ratio] : $axisOverride($key,aspect_ratio)}]
    plot3dAspectValidate [expr {$mode eq "" ? "inherit" : $mode}] $ratio
    dict for {field value} $values {set axisOverride($key,$field) $value}
    writeAxisOverrideFile
    catch {refreshManifestPreview}
    return [graphAxisConfigSnapshot $moduleId $graphId $variantId]
}
proc ::GX::graphAxisConfigOpen {moduleId graphId {variantId ""}} {
    variable graphAxisDialogTarget
    set key [graphAxisAddress $moduleId $graphId $variantId]
    set path [graphAxisArtifactPath $moduleId $graphId $variantId]
    set graphAxisDialogTarget [dict create module_id $moduleId graph_id $graphId variant_id $variantId graph_key $key path $path]
    try { axisConfigDialog } finally { set graphAxisDialogTarget {} }
    return $key
}
proc ::GX::currentGraphPath {} {
    variable graphAxisDialogTarget
    if {$graphAxisDialogTarget ne ""} { return [dict get $graphAxisDialogTarget path] }
    return [::GX::currentGraphPath_before_graph_workflow]
}
proc ::GX::graphKeyForPath {path} {
    variable graphAxisDialogTarget
    if {$graphAxisDialogTarget ne "" && $path eq [dict get $graphAxisDialogTarget path]} { return [dict get $graphAxisDialogTarget graph_key] }
    return [::GX::graphKeyForPath_before_graph_workflow $path]
}
proc ::GX::moduleGraphConfigDialog {moduleId graphId} {
    set w [::GX::moduleGraphConfigDialog_before_graph_workflow $moduleId $graphId]
    # plot.dataset multi-panel: append provider-owned controls without changing the generic graph fields.
    if {[winfo exists $w.body]} {
        set extensionRow [expr {[llength [moduleGraphConfigKeys $moduleId $graphId]] + 1}]
        catch {graphConfigExtensionBuild $w.body $moduleId $graphId "" $extensionRow}
    }
    if {[winfo exists $w.buttons]} {
        ttk::button $w.buttons.axes -text "Axes..." -command [list ::GX::graphAxisConfigOpen $moduleId $graphId ""]
        grid $w.buttons.axes -row 0 -column 0 -padx 4
        grid $w.buttons.close -row 0 -column 1 -padx 4
    }
    return $w
}
proc ::GX::plotVariantEditor {parent moduleId graphId variantId} {
    ::GX::plotVariantEditor_before_graph_workflow $parent $moduleId $graphId $variantId
    set w .plotvariantedit
    # plot.dataset multi-panel: expose the same provider graph configuration inside a variant's Plot tab.
    if {[winfo exists $w.nb.plot]} {
        set extensionRow [expr {[llength [moduleGraphConfigKeys $moduleId $graphId]] + 1}]
        catch {graphConfigExtensionBuild $w.nb.plot $moduleId $graphId $variantId $extensionRow}
    }
    if {[winfo exists $w.buttons]} {
        ttk::button $w.buttons.axes -text "Axes..." -command [list ::GX::graphAxisConfigOpen $moduleId $graphId $variantId]
        pack $w.buttons.axes -side left -padx 4 -before $w.buttons.close
    }
    # The embedded Series editor can request a taller window than the
    # display. Keep Save/Render/Close reachable; its own viewport scrolls.
    pack forget $w.nb $w.buttons
    pack $w.buttons -side bottom -anchor e -padx 8 -pady 8
    pack $w.nb -side top -fill both -expand 1 -padx 8
    set width [expr {min(1050, max(720, [winfo screenwidth $w] - 80))}]
    set height [expr {min(820, max(560, [winfo screenheight $w] - 80))}]
    wm geometry $w "${width}x${height}"
}

proc ::GX::graphUseStateKey {moduleId graphId {variantId ""}} {
    if {$graphId ni [moduleGraphIds $moduleId]} { error "Unknown graph '$moduleId/$graphId'." }
    if {$variantId ne "" && ![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant '$moduleId/$graphId/$variantId'." }
    return "$moduleId,$graphId,$variantId"
}
proc ::GX::graphUseStateGet {moduleId graphId {variantId ""}} {
    variable graphUseState
    set key [graphUseStateKey $moduleId $graphId $variantId]
    return [expr {[info exists graphUseState($key)] ? ($graphUseState($key) ? 1 : 0) : 1}]
}
proc ::GX::graphUseStateSet {moduleId graphId variantId value} {
    variable graphUseState
    set key [graphUseStateKey $moduleId $graphId $variantId]
    set graphUseState($key) [expr {$value ? 1 : 0}]
    catch {refreshManifestPreview}
    return $graphUseState($key)
}
proc ::GX::graphUseIdentityForPath {path} {
    set v [plotVariantInfoForPath $path]
    if {[llength $v] == 3} { return $v }
    set n [nativeGraphInfoForPath $path]
    if {[llength $n] == 2} { return [concat $n [list ""]] }
    return {}
}

# Public graph lifecycle entry point for the Plots page and other consumers.
# A descriptor-backed base graph is disabled before its artifact is removed;
# producer-owned scientific Datasets and registered scripts remain untouched.
proc ::GX::graphLifecycleDelete {path} {
    variable currentSession
    if {$currentSession eq "" || ![file isfile $path]} { error "Select an existing Session plot." }
    set root [file normalize [file join $currentSession analysis]]
    set path [file normalize $path]
    if {[string first "$root/" "$path/"] != 0 || [string tolower [file extension $path]] ne ".png"} {
        error "Plot must be a Session-owned PNG."
    }
    if {[llength [info commands ::GX::PlotClone::infoForPath]] && [::GX::PlotClone::infoForPath $path] ne ""} {
        set dir [file dirname $path]
        if {[file type $dir] eq "link"} { error "Clone directory is a symlink." }
        if {[llength [info commands ::GX::graphResourceDelete]]} {
            graphResourceDelete [dict create kind clone clone_id [file tail $dir]]
        }
        file delete -force -- $dir
        return 1
    }
    set identity [graphUseIdentityForPath $path]
    if {[llength $identity] == 3} {
        lassign $identity moduleId graphId variantId
        if {$variantId ne ""} {
            if {$moduleId eq "plot.dataset"} {
                modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
                ::GX::PlotDatasetAPIv3::deletePlot [dict create module_id $moduleId graph_id $graphId variant_id $variantId]
            } else {
                plotVariantDelete $moduleId $graphId $variantId
            }
            catch {unset ::GX::graphUseState($moduleId,$graphId,$variantId)}
            return 1
        }
        if {[llength [info commands ::GX::graphResourceDelete]]} {
            graphResourceDelete [dict create kind provider module_id $moduleId graph_id $graphId variant_id ""]
        }
        set ::GX::moduleGraphEnabled($moduleId,$graphId) 0
        set key [plotVariantKey $graphId ""]
        foreach arrayName {axisOverride legendOverride levelScale} {
            upvar 0 ::GX::$arrayName state
            array unset state "$key,*"
        }
        array unset ::GX::plotRegion "$moduleId,$key,*"
        catch {unset ::GX::graphUseState($moduleId,$graphId,)}
        if {$moduleId eq "plot.dataset"} {
            modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
            ::GX::PlotDatasetAPIv3::removeSpec [dict create module_id $moduleId graph_id $graphId variant_id ""]
            foreach sid [graphSeriesIds $moduleId $graphId ""] {
                graphSeriesRemove $moduleId $graphId $sid ""
            }
        }
    }
    set stem [file rootname [file tail $path]]
    foreach sidecar [list [file join [file dirname $path] annotations "${stem}.json"] \
        [file join [file dirname $path] .gxtxt_plotmeta "${stem}.ini"] \
        [file join [file dirname $path] .gxtxt_plotmeta "${stem}.xrange.ini"]] {
        if {[file isfile $sidecar]} { file delete -- $sidecar }
    }
    file delete -- $path
    catch {refreshManifestPreview}
    return 1
}

# Analysis modules may retain a PNG copy for their output contract while the
# editable graph lives in a persistent plot.dataset variant. Show only the
# provider artifact in the Graphs tab when that variant is available; otherwise
# keep the module copy visible so an incomplete run is still inspectable.
proc ::GX::graphWorkflowProviderAliasPaths {session} {
    set aliases {}
    set analysis [file join $session analysis]
    # Producers can write the public provider bridge inside a persistent
    # module Variant. Search the complete analysis tree so its PNG copy does
    # not appear as a second, falsely editable graph beside the canonical
    # Plot Dataset Variant.
    foreach manifest [walkFiles $analysis] {
        if {[file tail $manifest] ne "automatic_graphs.ini"} continue
        set dir [file dirname $manifest]
        if {[catch {set data [parseIni $manifest]}]} continue
        if {[descriptorValue $data automatic_graphs provider ""] ne "plot.dataset"} continue
        set count [descriptorValue $data automatic_graphs count 0]
        if {![string is integer -strict $count] || $count < 0 || $count > 10000} continue
        for {set i 1} {$i <= $count} {incr i} {
            set section [format "graph.%02d" $i]
            set png [descriptorValue $data $section png ""]
            set graphId [descriptorValue $data $section graph_id ""]
            set variantId [descriptorValue $data $section variant_id ""]
            if {$png eq "" || [file pathtype $png] ne "relative" || $graphId eq "" || $variantId eq ""} continue
            set alias [file normalize [file join $dir $png]]
            set safeRoot [file normalize $dir]
            if {[string first "${safeRoot}[file separator]" $alias] != 0} continue
            if {![file isfile $alias]} continue
            # A retained bridge may name an ID later reused by an unrelated
            # user Variant. Only the actual producer-owned representation is
            # an alias; missing/stale provenance leaves the producer visible.
            if {[catch {
                set producer [graphUseIdentityForPath $alias]
                if {[llength $producer] != 3} {error {Unknown producer graph}}
                lassign $producer producerModule producerGraph producerVariant
                if {[file normalize [graphAxisArtifactPath $producerModule $producerGraph $producerVariant]] ne $alias} {error {Producer artifact differs}}
                set scope [expr {$producerVariant eq {} ? {base} : $producerVariant}]
                set key [descriptorValue $data $section key {}]
                if {$key eq {} || [descriptorValue $data $section scope {}] ne $scope} {error {Producer scope/key differs}}
                set declaredKey [moduleGraphField $producerModule $producerGraph interactive_3d_key {}]
                if {$declaredKey ne {} && $declaredKey ne $key} {error {Declared producer key differs}}
                set artifact [plotVariantArtifact plot.dataset $graphId $variantId]
                if {![file isfile $artifact] || [plotVariantInfoForPath $artifact] ne [list plot.dataset $graphId $variantId]} {error {Representation artifact differs}}
                if {[plotVariantField plot.dataset $graphId $variantId provider_key {}] ne "${producerModule}:${scope}:${key}"} {error {Representation producer differs}}
            }]} continue
            # Historical absolute provider_artifact paths are provenance, not
            # authority to open another Session after an ordinary Session copy.
            if {$alias ne [file normalize $artifact]} {lappend aliases $alias}
        }
    }
    return [lsort -unique $aliases]
}
# Resolve a producer graph and its existing scientific representation separately.
# This is inspection only: it never creates a Plot Variant or rewrites bindings.
proc ::GX::graphWorkflowScientific3DSource {reference} {
    variable currentSession
    variable moduleBindingIdentity
    variable moduleBinding
    variable modulePlotCfg
    set ref [graphResourceRef $reference]
    if {[dict get $ref kind] ne "provider"} {error {This graph has no declared interactive scientific 3D source.}}
    set mid [dict get $ref module_id];set gid [dict get $ref graph_id];set vid [dict get $ref variant_id]
    if {$mid eq "plot.dataset" && $gid eq "plot.dataset.xyz"} {
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
        set owner ::GX::PlotDatasetAPIv4
        if {![${owner}::isOwned $ref]} {modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3;set owner ::GX::PlotDatasetAPIv3}
        ${owner}::previewCompatibility $ref
        return [dict create original_reference $ref representation_reference $ref owner $owner source_info [${owner}::interactiveSourceInfo $ref]]
    }
    if {$currentSession eq {} || ![file isdirectory $currentSession]} {error {Open the graph's Session first.}}
    set type [moduleGraphField $mid $gid interactive_3d_plot_type {}]
    set sourceRole [moduleGraphField $mid $gid interactive_3d_source {}]
    set bridgeKey [moduleGraphField $mid $gid interactive_3d_key {}]
    if {[moduleGraphField $mid $gid interactive_3d_provider {}] ne "plot.dataset" ||
        $type ni {surface mesh contour3 scatter3 line3 trisurf heatmap} || $sourceRole eq {} || $bridgeKey eq {}} {
        error {The provider has no declared scientific 3D geometry contract; a PNG alone cannot supply interactive geometry.}
    }
    set artifact [graphAxisArtifactPath $mid $gid $vid]
    set dir [file dirname $artifact]
    set manifest [file join $dir automatic_graphs.ini]
    if {![file isfile $manifest] || [file size $manifest]>8388608} {error {The graph's scientific provider bridge is unavailable.}}
    set bridge [parseIni $manifest]
    foreach {field expected} {provider plot.dataset api PLOT_DATASET_API_v2 bridge PLOT_DATASET_OCTAVE_BRIDGE_v1} {
        if {[descriptorValue $bridge automatic_graphs $field {}] ne $expected} {error "Unsupported scientific provider bridge: $field."}
    }
    set count [descriptorValue $bridge automatic_graphs count 0]
    if {![string is integer -strict $count] || $count<1 || $count>10000} {error {Invalid scientific provider bridge count.}}
    set scope [expr {$vid eq {}?"base":$vid}]
    set matches {}
    for {set i 1} {$i<=$count} {incr i} {
        set section [format graph.%02d $i]
        if {[descriptorValue $bridge $section png {}] eq [file tail $artifact]} {lappend matches $section}
    }
    if {[llength $matches]!=1} {error {The selected graph has no unique scientific provider bridge entry.}}
    set section [lindex $matches 0]
    if {[descriptorValue $bridge $section key {}] ne $bridgeKey ||
        [descriptorValue $bridge $section scope {}] ne $scope ||
        [descriptorValue $bridge $section graph_id {}] ne "plot.dataset.xyz"} {error {Scientific bridge identity does not match the selected graph contract.}}
    set representationId [descriptorValue $bridge $section variant_id {}]
    if {![regexp {^p[0-9]+$} $representationId]} {error {Invalid scientific representation identity.}}
    # Recorded absolute paths remain provenance after a Session copy. Current
    # Session ownership, not the old workstation path, locates preparation.
    set preparedDir [file join $currentSession analysis plot.dataset variants plot.dataset.xyz $representationId]
    set runtime [file join $preparedDir runtime.ini]
    set cache [file join $preparedDir render_cache.mat]
    if {![file isfile $cache] || ![file isfile $runtime]} {error {The graph has no retained scientific 3D preparation/runtime.}}
    if {[file size $cache]>134217728 || [file size $runtime]>8388608} {error {Prepared graph exceeds the existing preview intake budget.}}
    set saved [parseIni $runtime]
    if {[descriptorValue $saved plot_variant graph_id {}] ne "plot.dataset.xyz" ||
        [descriptorValue $saved plot_variant variant_id {}] ne $representationId ||
        [descriptorValue $saved plot.plot.dataset.xyz plot_type {}] ne $type} {error {Retained scientific geometry kind or representation identity differs from the graph contract.}}
    set dataset [analysisSourceDatasetFor $mid $sourceRole]
    if {$dataset eq {} || [descriptorValue $saved dataset id {}] ne $dataset ||
        [descriptorValue $saved analysis_source.primary dataset_id {}] ne $dataset} {error {Graph source Dataset changed since its scientific preparation.}}
    set payload [sessionInspectionDatasetPayload $dataset]
    set bindings {};set variables {}
    set n [descriptorValue $saved analysis_source.primary variable_count 0]
    if {![string is integer -strict $n] || $n<1 || $n>100000} {error {Prepared source has no valid Variable identity metadata.}}
    foreach role {x y z} {
        if {![info exists moduleBindingIdentity($mid,$role)] || [llength [split $moduleBindingIdentity($mid,$role) |]]!=3} {error "Resolve the graph's $role Variable identity through its normal binding controls first."}
        lassign [split $moduleBindingIdentity($mid,$role) |] selectedRole selectedDataset variableId
        if {$selectedRole ne $sourceRole || $selectedDataset ne $dataset} {error "Graph $role source binding changed since preparation."}
        set variable [datasetVariableById $dataset $variableId]
        set name [dict get $variable canonical]
        if {![dict get $variable enabled] || ![info exists moduleBinding($mid,$role)] || $moduleBinding($mid,$role) ne "$sourceRole.$name" ||
            [descriptorValue $saved bindings $role {}] ne "primary.$name"} {error "Graph $role binding no longer matches its prepared source."}
        set matched 0
        for {set i 1} {$i<=$n} {incr i} {
            set prefix analysis_source.primary.variable.$i
            if {[descriptorValue $saved $prefix variable_id {}] ne $variableId} continue
            if {[descriptorValue $saved $prefix name {}] ne $name || [descriptorValue $saved $prefix unit {}] ne [dict get $variable unit]} {error "Graph $role Variable name/unit changed since preparation."}
            incr matched
        }
        if {$matched!=1} {error "Prepared source has no unique $role Variable identity."}
        dict set bindings $role [dict create dataset_id $dataset variable_id $variableId]
        dict set variables $role $variable
    }
    foreach role {family color} {
        if {[descriptorValue $saved bindings $role {}] ne {}} {error {This producer contract does not declare additional family/color bindings.}}
    }
    # Current producer presentation is compared with its retained runtime;
    # unlike graphAxisConfigSnapshot this read does not initialize overrides.
    set producerRuntime [file join $dir runtime.ini]
    if {![file isfile $producerRuntime] || [file size $producerRuntime]>8388608} {error {The producer's retained presentation receipt is missing.}}
    set producer [parseIni $producerRuntime]
    foreach field [moduleGraphConfigKeys $mid $gid] {
        set previous [descriptorValue $producer plot.$gid $field {}]
        set current [moduleGraphConfigField $mid $gid $field default {}]
        if {$vid ne {}} {set current [plotVariantConfigGet $mid $gid $vid $field]} elseif {[info exists modulePlotCfg($mid,$gid,$field)]} {set current $modulePlotCfg($mid,$gid,$field)}
        if {$current ne $previous} {error "Graph $field changed; render the graph to update its scientific presentation."}
        if {$field in {title contour_levels x_label y_label z_label} && $previous ne {} && $previous ne "auto" && $previous ne [descriptorValue $saved plot.plot.dataset.xyz $field {}]} {error "Prepared graph $field differs from its producer presentation."}
    }
    set graphKey [graphAxisAddress $mid $gid $vid]
    set presentation {}
    foreach array {axisOverride legendOverride} prefix {axis legend} {
        upvar #0 ::GX::$array values
        set defaults [expr {$array eq "axisOverride"?[dict merge [axisOverrideFieldDefaults] [plot3dAxisFieldDefaults] [layoutOverrideFieldDefaults]]:[legendOverrideFieldDefaults]}]
        foreach name [lsort [array names values "$graphKey,*"]] {
            set field [string range $name [expr {[string length $graphKey]+1}] end]
            if {$field eq "panels"} continue
            if {$array eq "axisOverride" && [string match layout_* $field] && $field ne {layout_auto}} {
                set automatic [expr {![info exists values($graphKey,layout_auto)] || $values($graphKey,layout_auto) ne {0}}]
                if {$automatic && [descriptorValue $producer axis.$gid layout_auto 1] ne {0}} continue
            }
            set default [expr {[dict exists $defaults $field]?[dict get $defaults $field]:{}}]
            set previous [descriptorValue $producer $prefix.$gid $field $default]
            set current $values($name)
            if {$array eq "axisOverride" && $field eq {layout_auto}} {
                set previous [expr {$previous eq {0}?0:1}]
                set current [expr {$current eq {0}?0:1}]
            }
            # Existing legend owner normalizes the old empty alignment to
            # center. Treat that migration as the same effective setting.
            if {$array eq "legendOverride" && $field eq "alignment"} {
                if {$previous eq {}} {set previous center}
                if {$current eq {}} {set current center}
            }
            if {$current ne $previous} {error "Graph $array/$field changed; render before interactive Preview."}
            lappend presentation $array $field $values($name)
        }
    }
    foreach axis {y y2 z} {
        set current [levelScaleGet $graphKey $axis]
        dict for {field default} [levelScaleDefaults] {
            if {[dict get $current $field] ne [descriptorValue $producer level_scale.$gid.$axis $field $default]} {error "Graph $axis level scale changed; render before interactive Preview."}
        }
        lappend presentation levelScale $axis $current
    }
    dict for {key value} $saved {
        if {[regexp {^axis\.plot\.dataset\.xyz\.(x|y|z)_?(scale|dir)$} $key] && $value ni {{} inherit linear normal}} {error {Logarithmic/reversed axes require a Native3D nonlinear calibrated coordinate-mapping contract.}}
    }
    set context [datasetCoordinateRead $currentSession $dataset]
    set coordinatePath [file join $preparedDir coordinate_presentation.ini]
    set coordinate {}
    if {[file isfile $coordinatePath]} {
        set coordinate [parseIni $coordinatePath]
        set count [descriptorValue $coordinate coordinate_presentation count 0]
        if {[descriptorValue $coordinate coordinate_presentation api_version {}] ne "1" || ![string is integer -strict $count] || $count<0 || $count>1024} {error {Invalid coordinate render receipt; render the graph again.}}
        set matched 0
        for {set i 1} {$i<=$count} {incr i} {
            if {[descriptorValue $coordinate dataset.$i id {}] ne $dataset} continue
            if {[descriptorValue $coordinate dataset.$i revision {}] ne [dict get $context revision] || [descriptorValue $coordinate dataset.$i source_sha256 {}] ne [dict get $context source_sha256]} {error {Dataset coordinate settings changed since static render; render before interactive Preview.}}
            set matched 1
        }
        if {!$matched && [dict get $context revision]>0} {error {The retained graph has no current Dataset coordinate receipt.}}
    } elseif {[dict get $context revision]>0} {error {The retained graph has no current Dataset coordinate receipt.}}
    set representation {}
    if {[plotVariantExists plot.dataset plot.dataset.xyz $representationId]} {
        if {[plotVariantField plot.dataset plot.dataset.xyz $representationId provider_key {}] ne "${mid}:${scope}:${bridgeKey}"} {error {The scientific representation belongs to another producer.}}
        set representation [graphResourceRef [dict create module_id plot.dataset graph_id plot.dataset.xyz variant_id $representationId]]
        foreach role {x y z} {
            set binding [plotVariantBindingGet plot.dataset plot.dataset.xyz $representationId $role]
            if {$binding eq {} || [dict get $binding dataset_id] ne $dataset || [dict get $binding variable_id] ne [dict get $bindings $role variable_id]} {error "Registered scientific representation $role binding differs from the producer source."}
        }
        if {[plotVariantConfigGet plot.dataset plot.dataset.xyz $representationId plot_type] ne $type} {error {Registered scientific representation has a different geometry kind.}}
    }
    set identities [list [interactiveDocumentSessionToken] $ref $representation $dataset [dict get $payload sha256] $bindings $variables $type $presentation $context $coordinate]
    foreach path [list $manifest $runtime $cache $producerRuntime] {lappend identities $path [sha256File $path]}
    set fingerprint [exec -- [runtimeToolRequired python] -c {import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())} << [encoding convertto utf-8 $identities]]
    set sourceInfo [dict create plot_ref $ref bindings $bindings source_dataset_id $dataset source_sha256 [dict get $payload sha256] fingerprint $fingerprint representation_reference $representation bridge_manifest $manifest geometry_kind $type]
    return [dict create original_reference $ref representation_reference $representation owner ::GX::PlotDataset3DAPIv1 source_info $sourceInfo \
        prepared_source [dict create cache $cache runtime $runtime saved $saved variables $variables source_payload $payload plot_type $type session $currentSession] fingerprint $fingerprint]
}

proc ::GX::scheduledModuleGraphIds {moduleId} {
    variable graphRuntimeSelectionOverride
    set out {}
    set restricted [dict exists $graphRuntimeSelectionOverride $moduleId]
    set selected [expr {$restricted ? [dict get $graphRuntimeSelectionOverride $moduleId] : {}}]
    foreach graphId [activeModuleGraphIds $moduleId] {
        if {$restricted && $graphId ni $selected} continue
        # USE filters normal scheduled runs. A graph explicitly selected for
        # rerender is an immediate user request and must not become a silent
        # no-op merely because its persistent scheduling flag is off.
        if {$restricted || [graphUseStateGet $moduleId $graphId ""]} { lappend out $graphId }
    }
    return $out
}
proc ::GX::defaults_before_temporal_set_v1 {} {
    ::GX::defaults_before_graph_workflow
    # Keep interpreter-lifetime API activation during Session/config resets.
    # Tcl wrappers remain installed; forgetting them attempts duplicate renames.
    array unset ::GX::graphUseState *
    set ::GX::graphAxisDialogTarget {}
    set ::GX::graphRuntimeSelectionOverride {}
}
proc ::GX::manifestStringV2_before_temporal_set_v1 {} {
    variable graphUseState
    variable axisOverride
    set out [::GX::manifestStringV2_before_graph_workflow]
    # Preserve the established 2D axis manifest sections. A historical
    # Manifest Format 2 rebuild omitted them even though the loader and the
    # sole axisOverride authority remained in CORE.
    if {[string first "\n\[plot.axis.overrides\]\n" $out] < 0} {
        set axisKeys {}
        foreach name [array names axisOverride "*,enabled"] {
            set key [string range $name 0 end-8]
            if {$key ni $axisKeys} { lappend axisKeys $key }
        }
        append out "\n\[plot.axis.overrides\]\n"
        appendKV out keys [join [lsort $axisKeys] ","]
        foreach key [lsort $axisKeys] {
            append out "\n\[plot.axis.$key\]\n"
            foreach {field default} {enabled 1 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color ""} {
                appendKV out $field [expr {[info exists axisOverride($key,$field)] ? $axisOverride($key,$field) : $default}]
            }
            set panels [expr {[info exists axisOverride($key,panels)] ? $axisOverride($key,panels) : {}}]
            appendKV out panel_count [llength $panels]
            set index 0
            foreach panel $panels {
                incr index
                appendKV out "panel${index}_name" $panel
                foreach {field default} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x ""} {
                    appendKV out "panel${index}_$field" [expr {[info exists axisOverride($key,$panel,$field)] ? $axisOverride($key,$panel,$field) : $default}]
                }
            }
        }
    }
    append out "\n\[graph_workflow_api\]\n"; appendKV out version 1
    set index 0
    foreach key [lsort [array names graphUseState]] {
        lassign [split $key ,] moduleId graphId variantId
        incr index
        append out "\n\[graph_use.$index\]\n"
        appendKV out module_id $moduleId
        appendKV out graph_id $graphId
        appendKV out variant_id $variantId
        appendKV out use $graphUseState($key)
    }
    append out "\n\[graph_use\]\n"; appendKV out count $index
    return $out
}
proc ::GX::loadManifestV2_before_temporal_set_v1 {path} {
    variable graphUseState
    variable axisOverride
    array unset graphUseState *
    ::GX::loadManifestV2_before_graph_workflow $path
    set d [parseIni $path]
    # Restore the established 2D axis sections into the same CORE authority.
    if {[dict exists $d plot.axis.overrides.keys]} {
        foreach key [split [dict get $d plot.axis.overrides.keys] ","] {
            set key [string trim $key]
            if {$key eq ""} continue
            axisOverrideEnsure $key {}
            foreach {field default} {enabled 1 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color ""} {
                set name "plot.axis.$key.$field"
                set axisOverride($key,$field) [expr {[dict exists $d $name] ? [dict get $d $name] : $default}]
            }
            set panels {}
            set panelCount [expr {[dict exists $d "plot.axis.$key.panel_count"] ? [dict get $d "plot.axis.$key.panel_count"] : 0}]
            if {![string is integer -strict $panelCount] || $panelCount < 0} { set panelCount 0 }
            if {$panelCount > 32} { set panelCount 32 }
            for {set panelIndex 1} {$panelIndex <= $panelCount} {incr panelIndex} {
                set name "plot.axis.$key.panel${panelIndex}_name"
                if {![dict exists $d $name] || [string trim [dict get $d $name]] eq ""} continue
                set panel [dict get $d $name]
                lappend panels $panel
                foreach {field default} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x ""} {
                    set name "plot.axis.$key.panel${panelIndex}_$field"
                    set axisOverride($key,$panel,$field) [expr {[dict exists $d $name] ? [dict get $d $name] : $default}]
                }
            }
            set axisOverride($key,panels) $panels
        }
    }
    set count [expr {[dict exists $d graph_use.count] ? [dict get $d graph_use.count] : 0}]
    if {![string is integer -strict $count] || $count < 0} { error "Invalid graph_use.count." }
    for {set i 1} {$i <= $count} {incr i} {
        set p "graph_use.$i."
        foreach f {module_id graph_id use} {
            if {![dict exists $d "$p$f"]} { error "Incomplete graph use entry $i." }
        }
        set moduleId [dict get $d "${p}module_id"]
        set graphId [dict get $d "${p}graph_id"]
        set variantId [expr {[dict exists $d "${p}variant_id"] ? [dict get $d "${p}variant_id"] : ""}]
        graphUseStateSet $moduleId $graphId $variantId [dict get $d "${p}use"]
    }
}
proc ::GX::refreshGraphs {} {
    variable ui
    variable graphUse
    ::GX::refreshGraphs_before_graph_workflow
    if {![info exists ui(graphTree)] || ![winfo exists $ui(graphTree)]} return
    set t $ui(graphTree)
    foreach row [$t children {}] {
        if {![info exists ui(graphPath,$row)]} continue
        set identity [graphUseIdentityForPath $ui(graphPath,$row)]
        if {[llength $identity] != 3} continue
        lassign $identity moduleId graphId variantId
        set use [graphUseStateGet $moduleId $graphId $variantId]
        set graphUse($row) $use
        set values [$t item $row -values]; lset values 0 [expr {$use ? "YES" : "NO"}]; $t item $row -values $values
    }
}
proc ::GX::toggleGraph {} {
    variable ui
    variable graphUse
    set t $ui(graphTree); set sel [$t selection]; if {[llength $sel] != 1} return
    set row [lindex $sel 0]; if {![info exists ui(graphPath,$row)]} return
    set value [expr {![info exists graphUse($row)] || !$graphUse($row)}]
    set identity [graphUseIdentityForPath $ui(graphPath,$row)]
    if {[llength $identity] == 3} { lassign $identity moduleId graphId variantId; set value [graphUseStateSet $moduleId $graphId $variantId $value] }
    if {[::GX::PlotClone::infoForPath $ui(graphPath,$row)] ne ""} {::GX::PlotClone::setUse $ui(graphPath,$row) $value}
    set graphUse($row) $value
    set values [$t item $row -values]; lset values 0 [expr {$value ? "YES" : "NO"}]; $t item $row -values $values
}
proc ::GX::setAllGraphs {value} {
    variable ui
    variable graphUse
    set value [expr {$value ? 1 : 0}]
    set t $ui(graphTree)
    foreach row [$t children {}] {
        if {[info exists ui(graphPath,$row)]} {
            set identity [graphUseIdentityForPath $ui(graphPath,$row)]
            if {[llength $identity] == 3} { lassign $identity moduleId graphId variantId; graphUseStateSet $moduleId $graphId $variantId $value }
            if {[::GX::PlotClone::infoForPath $ui(graphPath,$row)] ne ""} {::GX::PlotClone::setUse $ui(graphPath,$row) $value}
        }
        set graphUse($row) $value
        set values [$t item $row -values]; lset values 0 [expr {$value ? "YES" : "NO"}]; $t item $row -values $values
    }
}
proc ::GX::moduleExpectedOutputs {moduleId} {
    set out [splitList [moduleField $moduleId outputs ""]]
    foreach graphId [scheduledModuleGraphIds $moduleId] {
        set file [string trim [moduleGraphField $moduleId $graphId file ""]]
        if {$file ne "" && $file ni $out} { lappend out $file }
    }
    return [join $out ";"]
}
proc ::GX::graphUseRewriteRuntime {path moduleId} {
    set provider [activeModuleGraphIds $moduleId]
    set use {}
    foreach graphId [moduleGraphIds $moduleId] { if {[graphUseStateGet $moduleId $graphId ""]} { lappend use $graphId } }
    set effective [scheduledModuleGraphIds $moduleId]
    set fd [open $path r]; fconfigure $fd -encoding utf-8
    set lines [split [read $fd] "\n"]; close $fd
    set out {}; set section ""; set injected 0
    foreach line $lines {
        if {[regexp {^\[([^]]+)\]$} [string trim $line] -> name]} { set section $name }
        if {$section eq "graph_provider" && [regexp {^enabled=} $line]} {
            lappend out "enabled=[join $effective {;}]"
            lappend out "provider_enabled=[join $provider {;}]"
            lappend out "use_enabled=[join $use {;}]"
            lappend out "effective_enabled=[join $effective {;}]"
            set injected 1
        } else { lappend out $line }
    }
    if {!$injected} { error "$moduleId runtime does not expose a graph_provider enabled field." }
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts -nonewline $fd [join $out "\n"]; close $fd
}
proc ::GX::writeStandardRuntimeConfig_before_dataset_access_v2 {moduleId} {
    if {[llength [moduleGraphIds $moduleId]]} {
        # Provider state must be reconciled before runtime serialization. For
        # plot.dataset this prevents a valid new Graph Series from disappearing
        # when its older PlotSpec/cache does not contain the same stable ID.
        moduleSeriesEditorExtensionsActivate $moduleId
        if {$moduleId eq "plot.dataset" &&
            [llength [info commands ::GX::PlotDatasetAPIv2::reconcilePersistentPlots]]} {
            ::GX::PlotDatasetAPIv2::reconcilePersistentPlots
        }
    }
    set path [::GX::writeStandardRuntimeConfig_before_graph_workflow $moduleId]
    if {[llength [moduleGraphIds $moduleId]]} { graphUseRewriteRuntime $path $moduleId }
    return $path
}

proc ::GX::buildStandardRerenderQueue {paths} {
    variable graphRuntimeSelectionOverride
    set selected [dict create];set legacy {};set native {};set seen {}
    foreach path $paths {
        set normalized [file normalize $path]
        if {$normalized in $seen} continue
        lappend seen $normalized
        if {[graphRendererOwnerForPath $normalized] eq {PLOT_DATASET_API_v4}} {
            lappend native [graphRendererQueueCommand [graphResourceRefForPath $normalized]]
            continue
        }
        lappend legacy $path
        set identity [graphUseIdentityForPath $path]
        if {[llength $identity] != 3} continue
        lassign $identity moduleId graphId variantId
        if {$variantId ne ""} continue
        dict lappend selected $moduleId $graphId
    }
    set previous $graphRuntimeSelectionOverride
    set graphRuntimeSelectionOverride $selected
    try {
        return [concat [::GX::buildStandardRerenderQueue_before_graph_workflow $legacy] $native]
    } finally {
        set graphRuntimeSelectionOverride $previous
    }
}

proc ::GX::plotVariantWriteRuntime {moduleId graphId variantId} {
    set result [::GX::plotVariantWriteRuntime_before_graph_workflow $moduleId $graphId $variantId]
    set path [lindex $result 0]
    set provider [moduleGraphIsEnabled $moduleId $graphId]
    set variant [plotVariantField $moduleId $graphId $variantId enabled 1]
    set use [graphUseStateGet $moduleId $graphId $variantId]
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[graph_use\]"
    putKV $fd api_version 1
    putKV $fd provider_enabled $provider
    putKV $fd variant_enabled $variant
    putKV $fd use $use
    # Existing Plot Module semantics keep a variant independent from the base
    # Graph Provider enabled flag. Its own enabled flag and USE control work.
    putKV $fd effective [expr {$variant && $use}]
    close $fd
    return $result
}
