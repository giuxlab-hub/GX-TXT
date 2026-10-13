# GX-TXT plot.dataset protected CORE rendering service API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Public, versioned API hosted by the protected CORE plot.dataset package.
# Available independent of the user-facing module Enabled state. Consumers should
# discover this file through plot.dataset/module.ini and must not depend on the
# module's runtime implementation files.

namespace eval ::GX::PlotDatasetAPIv1 {
    variable apiVersion 1
    variable moduleId plot.dataset
}

proc ::GX::PlotDatasetAPIv1::_error {message} {
    return -code error "plot.dataset API v1: $message"
}

proc ::GX::PlotDatasetAPIv1::_requireFramework {} {
    foreach cmd {
        ::GX::moduleField ::GX::moduleGraphIds ::GX::moduleGraphField
        ::GX::moduleGraphConfigKeys ::GX::moduleGraphConfigField
        ::GX::graphSeriesSet ::GX::graphSeriesRemove ::GX::graphSeriesList
        ::GX::graphSeriesIds ::GX::graphSeriesResolve ::GX::graphSeriesMove
        ::GX::plotVariantCreate ::GX::plotVariantExists ::GX::plotVariantConfigSet
        ::GX::plotVariantConfigGet ::GX::plotVariantCommand
    } {
        if {![llength [info commands $cmd]]} {
            _error "required GX-TXT public service is unavailable: $cmd"
        }
    }
    if {[::GX::moduleField plot.dataset id ""] eq "" && [lsearch -exact $::GX::moduleOrder plot.dataset] < 0} {
        _error "module plot.dataset is not discovered"
    }
}

proc ::GX::PlotDatasetAPIv1::_descriptor {} {
    variable moduleId
    set path [::GX::moduleField $moduleId descriptor ""]
    if {$path eq "" || ![file isfile $path]} {_error "module descriptor is unavailable"}
    return [::GX::parseIni $path]
}

proc ::GX::PlotDatasetAPIv1::capabilities {} {
    _requireFramework
    set d [_descriptor]
    set raw [::GX::descriptorValue $d public_api.PLOT_DATASET_API_v1 capabilities ""]
    return [::GX::splitList $raw]
}

proc ::GX::PlotDatasetAPIv1::supports {capability} {
    return [expr {[lsearch -exact [capabilities] $capability] >= 0}]
}

proc ::GX::PlotDatasetAPIv1::requireCapability {capability} {
    if {![supports $capability]} {_error "capability '$capability' is not supported"}
    return 1
}

proc ::GX::PlotDatasetAPIv1::apiInfo {} {
    variable apiVersion
    variable moduleId
    _requireFramework
    return [dict create \
        api_name PLOT_DATASET_API_v1 \
        api_version $apiVersion \
        module_id $moduleId \
        module_version [::GX::moduleField $moduleId version ""] \
        capabilities [capabilities]]
}

proc ::GX::PlotDatasetAPIv1::_plotId {graphId variantId} {
    if {$variantId eq ""} {return $graphId}
    return "$graphId/$variantId"
}

proc ::GX::PlotDatasetAPIv1::_plotRef {graphId {variantId ""}} {
    variable moduleId
    return [dict create module_id $moduleId graph_id $graphId variant_id $variantId plot_id [_plotId $graphId $variantId]]
}

proc ::GX::PlotDatasetAPIv1::_normalizePlotRef {plotRef} {
    variable moduleId
    _requireFramework
    if {[catch {dict size $plotRef}]} {_error "plot reference must be a dict returned by createPlot/openPlot"}
    foreach k {module_id graph_id variant_id} {
        if {![dict exists $plotRef $k]} {_error "plot reference is missing '$k'"}
    }
    if {[dict get $plotRef module_id] ne $moduleId} {_error "plot reference belongs to another module"}
    set graphId [dict get $plotRef graph_id]
    if {[lsearch -exact [::GX::moduleGraphIds $moduleId] $graphId] < 0} {_error "unknown graph '$graphId'"}
    set variantId [dict get $plotRef variant_id]
    if {$variantId ne "" && ![::GX::plotVariantExists $moduleId $graphId $variantId]} {_error "unknown plot variant '$variantId'"}
    return [_plotRef $graphId $variantId]
}

proc ::GX::PlotDatasetAPIv1::_setBaseGraphEnabled {graphId state} {
    variable moduleId
    set want [expr {$state ? 1 : 0}]
    set have [::GX::moduleGraphIsEnabled $moduleId $graphId]
    if {$have != $want} {::GX::moduleGraphToggle $moduleId $graphId}
    return $want
}

proc ::GX::PlotDatasetAPIv1::createPlot {graphId {kind base} {sourceVariant ""}} {
    variable moduleId
    _requireFramework
    if {[lsearch -exact [::GX::moduleGraphIds $moduleId] $graphId] < 0} {_error "unknown graph '$graphId'"}
    switch -- $kind {
        base {
            if {$sourceVariant ne ""} {_error "sourceVariant is valid only when kind=variant"}
            _setBaseGraphEnabled $graphId 1
            return [_plotRef $graphId ""]
        }
        variant {
            if {![::GX::plotVariantSupports $moduleId $graphId]} {_error "graph '$graphId' does not support variants"}
            if {[catch {set variantId [::GX::plotVariantCreate $moduleId $graphId $sourceVariant]} err]} {_error $err}
            return [_plotRef $graphId $variantId]
        }
        default {_error "kind must be 'base' or 'variant'"}
    }
}

proc ::GX::PlotDatasetAPIv1::openPlot {graphId {variantId ""}} {
    return [_normalizePlotRef [_plotRef $graphId $variantId]]
}

proc ::GX::PlotDatasetAPIv1::deletePlot {plotRef} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {$variantId eq ""} {_error "base graphs cannot be deleted; disable them with setPlotEnabled"}
    if {[llength [info commands ::GX::PlotDatasetAPIv2::removeSpec]]} {
        ::GX::PlotDatasetAPIv2::removeSpec $ref
    }
    ::GX::plotVariantDelete $moduleId $graphId $variantId
    return 1
}

proc ::GX::PlotDatasetAPIv1::setPlotEnabled {plotRef state} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    set state [expr {$state ? 1 : 0}]
    if {$variantId eq ""} {
        return [_setBaseGraphEnabled $graphId $state]
    }
    ::GX::plotVariantSet $moduleId $graphId $variantId [dict create enabled $state]
    return $state
}

proc ::GX::PlotDatasetAPIv1::_baseConfigSet {graphId key value} {
    variable moduleId
    if {[llength [info commands ::GX::moduleGraphConfigSet]]} {
        return [::GX::moduleGraphConfigSet $moduleId $graphId $key $value]
    }
    # Module API 1 historically exposes descriptor-generated graph state but not
    # a setter proc.  Keep the bridge encapsulated here; consumers never touch
    # the framework variable and no parallel configuration store is created.
    if {[lsearch -exact [::GX::moduleGraphConfigKeys $moduleId $graphId] $key] < 0} {_error "unknown plot configuration key '$key'"}
    if {[regexp {[\r\n]} $value]} {_error "plot configuration values must be single-line"}
    set ::GX::modulePlotCfg($moduleId,$graphId,$key) $value
    catch {::GX::refreshManifestPreview}
    return $value
}

proc ::GX::PlotDatasetAPIv1::_baseConfigGet {graphId key} {
    variable moduleId
    if {[llength [info commands ::GX::moduleGraphConfigGet]]} {
        return [::GX::moduleGraphConfigGet $moduleId $graphId $key]
    }
    if {[lsearch -exact [::GX::moduleGraphConfigKeys $moduleId $graphId] $key] < 0} {_error "unknown plot configuration key '$key'"}
    if {[info exists ::GX::modulePlotCfg($moduleId,$graphId,$key)]} {return $::GX::modulePlotCfg($moduleId,$graphId,$key)}
    return [::GX::moduleGraphConfigField $moduleId $graphId $key default ""]
}

proc ::GX::PlotDatasetAPIv1::setConfig {plotRef key value} {
    variable moduleId
    requireCapability plot_config
    set ref [_normalizePlotRef $plotRef]
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {[lsearch -exact [::GX::moduleGraphConfigKeys $moduleId $graphId] $key] < 0} {_error "unknown plot configuration key '$key'"}
    if {$variantId eq ""} {return [_baseConfigSet $graphId $key $value]}
    if {[catch {::GX::plotVariantConfigSet $moduleId $graphId $variantId $key $value} err]} {_error $err}
    return $value
}

proc ::GX::PlotDatasetAPIv1::getConfig {plotRef key} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {[lsearch -exact [::GX::moduleGraphConfigKeys $moduleId $graphId] $key] < 0} {_error "unknown plot configuration key '$key'"}
    if {$variantId eq ""} {return [_baseConfigGet $graphId $key]}
    return [::GX::plotVariantConfigGet $moduleId $graphId $variantId $key]
}

proc ::GX::PlotDatasetAPIv1::setTitle {plotRef title} {
    return [setConfig $plotRef title $title]
}

proc ::GX::PlotDatasetAPIv1::_requireSeriesGraph {ref} {
    variable moduleId
    set graphId [dict get $ref graph_id]
    if {[string tolower [::GX::moduleGraphField $moduleId $graphId series_editor ""]] ne "standard"} {
        _error "graph '$graphId' does not support Graph Series"
    }
}

proc ::GX::PlotDatasetAPIv1::_seriesCoreFields {resolved} {
    set out [dict create]
    foreach k {dataset_id x_variable_id y_variable_id family_variable_id secondary_variable_id ordering_variable_id axis label enabled order alignment_mode manual_offset_seconds row_filters} {
        if {[dict exists $resolved $k]} {dict set out $k [dict get $resolved $k]}
    }
    return $out
}

proc ::GX::PlotDatasetAPIv1::setSeries {plotRef seriesId fields} {
    variable moduleId
    requireCapability graph_series
    set ref [_normalizePlotRef $plotRef]
    _requireSeriesGraph $ref
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {[catch {dict size $fields}]} {_error "series fields must be a dict"}
    set ids [::GX::graphSeriesIds $moduleId $graphId $variantId]
    if {[lsearch -exact $ids $seriesId] >= 0} {
        set current [_seriesCoreFields [::GX::graphSeriesResolve $moduleId $graphId $seriesId $variantId]]
        set fields [dict merge $current $fields]
    } elseif {![dict exists $fields order]} {
        # Public API creation preserves insertion order unless the consumer
        # explicitly supplies another persistent Graph Series order.
        dict set fields order [expr {[llength $ids] + 1}]
    }
    foreach k {dataset_id x_variable_id y_variable_id axis} {
        if {![dict exists $fields $k]} {_error "new series requires '$k'"}
    }
    if {[catch {set result [::GX::graphSeriesSet $moduleId $graphId $seriesId $fields $variantId]} err]} {_error $err}
    return $result
}

proc ::GX::PlotDatasetAPIv1::getSeries {plotRef seriesId} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    _requireSeriesGraph $ref
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {[catch {set result [::GX::graphSeriesResolve $moduleId $graphId $seriesId $variantId]} err]} {_error $err}
    return $result
}

proc ::GX::PlotDatasetAPIv1::listSeries {plotRef {includeDisabled 1}} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    _requireSeriesGraph $ref
    return [::GX::graphSeriesList $moduleId [dict get $ref graph_id] [dict get $ref variant_id] [expr {$includeDisabled ? 1 : 0}]]
}

proc ::GX::PlotDatasetAPIv1::removeSeries {plotRef seriesId} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    _requireSeriesGraph $ref
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {[lsearch -exact [::GX::graphSeriesIds $moduleId $graphId $variantId] $seriesId] < 0} {_error "unknown graph series '$seriesId'"}
    ::GX::graphSeriesRemove $moduleId $graphId $seriesId $variantId
    return 1
}

proc ::GX::PlotDatasetAPIv1::setSeriesEnabled {plotRef seriesId state} {
    return [setSeries $plotRef $seriesId [dict create enabled [expr {$state ? 1 : 0}]]]
}

proc ::GX::PlotDatasetAPIv1::moveSeries {plotRef seriesId direction} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    _requireSeriesGraph $ref
    switch -- $direction {up {set delta -1} down {set delta 1} default {_error "direction must be 'up' or 'down'"}}
    if {[catch {set ids [::GX::graphSeriesMove $moduleId [dict get $ref graph_id] $seriesId $delta [dict get $ref variant_id]]} err]} {_error $err}
    return $ids
}

proc ::GX::PlotDatasetAPIv1::setSeriesOrder {plotRef orderedIds} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    _requireSeriesGraph $ref
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    set current [::GX::graphSeriesIds $moduleId $graphId $variantId]
    if {[lsort -dictionary $current] ne [lsort -dictionary $orderedIds]} {_error "orderedIds must contain every current series exactly once"}
    set rank 0
    foreach id $orderedIds {
        incr rank
        setSeries $ref $id [dict create order $rank]
    }
    return [::GX::graphSeriesIds $moduleId $graphId $variantId]
}

proc ::GX::PlotDatasetAPIv1::_graphConfigDict {ref} {
    variable moduleId
    set graphId [dict get $ref graph_id]
    set out [dict create]
    foreach key [::GX::moduleGraphConfigKeys $moduleId $graphId] {
        dict set out $key [getConfig $ref $key]
    }
    return $out
}

proc ::GX::PlotDatasetAPIv1::artifacts {plotRef} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    if {$::GX::currentSession eq ""} {_error "no open GX-TXT session"}
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {$variantId eq ""} {
        set outdir [file join $::GX::currentSession analysis $moduleId]
        set graphArtifact [file join $outdir [::GX::moduleGraphField $moduleId $graphId file ""]]
    } else {
        set outdir [::GX::plotVariantOutputDir $moduleId $graphId $variantId]
        set graphArtifact [::GX::plotVariantArtifact $moduleId $graphId $variantId]
    }
    set declared [list [file join $outdir render_cache.mat] [file join $outdir plot_summary.txt] $graphArtifact]
    set existing {}
    foreach p $declared {if {[file isfile $p]} {lappend existing [file normalize $p]}}
    return [dict create output_dir [file normalize $outdir] graph_artifact [file normalize $graphArtifact] render_cache [file normalize [file join $outdir render_cache.mat]] summary [file normalize [file join $outdir plot_summary.txt]] existing $existing]
}

proc ::GX::PlotDatasetAPIv1::readPlot {plotRef} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    if {$variantId eq ""} {
        set enabled [::GX::moduleGraphIsEnabled $moduleId $graphId]
        set displayName [::GX::moduleGraphField $moduleId $graphId name $graphId]
    } else {
        set enabled [::GX::plotVariantField $moduleId $graphId $variantId enabled 1]
        set displayName [::GX::plotVariantField $moduleId $graphId $variantId title $variantId]
    }
    set series {}
    if {[string tolower [::GX::moduleGraphField $moduleId $graphId series_editor ""]] eq "standard"} {
        set series [listSeries $ref 1]
    }
    return [dict merge $ref [dict create enabled $enabled display_name $displayName config [_graphConfigDict $ref] series $series artifacts [artifacts $ref]]]
}

proc ::GX::PlotDatasetAPIv1::_baseRenderCommand {graphId} {
    variable moduleId
    if {$::GX::currentSession eq ""} {_error "no open GX-TXT session"}
    set oldRun [::GX::moduleRunIsSelected $moduleId]
    set oldEnabled [::GX::moduleIsEnabled $moduleId]
    set graphState [dict create]
    foreach g [::GX::moduleGraphIds $moduleId] {dict set graphState $g [::GX::moduleGraphIsEnabled $moduleId $g]}
    set previousSelection $::GX::graphRuntimeSelectionOverride
    set code [catch {
        if {!$oldEnabled} {::GX::moduleSetEnabled $moduleId 1}
        ::GX::moduleSetRunSelected $moduleId 1
        foreach g [::GX::moduleGraphIds $moduleId] {_setBaseGraphEnabled $g [expr {$g eq $graphId}]}
        # Public render is an explicit request. Restrict runtime to this graph
        # without mutating its persistent USE scheduling preference.
        set ::GX::graphRuntimeSelectionOverride [dict create $moduleId [list $graphId]]
        set queue [::GX::buildStandardAnalysisQueue]
        set target "Analysis - [::GX::moduleField $moduleId name $moduleId]"
        set item {}
        foreach q $queue {if {[lindex $q 0] eq $target} {set item $q;break}}
        if {![llength $item]} {_error "framework did not produce a standard render command for base graph '$graphId'"}
    } err opts]
    set ::GX::graphRuntimeSelectionOverride $previousSelection
    foreach g [dict keys $graphState] {catch {_setBaseGraphEnabled $g [dict get $graphState $g]}}
    catch {::GX::moduleSetRunSelected $moduleId $oldRun}
    if {!$oldEnabled} {catch {::GX::moduleSetEnabled $moduleId 0}}
    if {$code} {return -options $opts $err}
    return $item
}

proc ::GX::PlotDatasetAPIv1::_baseRerenderCommand {graphId} {
    set ref [_plotRef $graphId ""]
    set a [artifacts $ref]
    set graphArtifact [dict get $a graph_artifact]
    set queue [::GX::buildStandardRerenderQueue [list $graphArtifact]]
    set target "Rerender - [::GX::moduleField plot.dataset name plot.dataset]"
    foreach q $queue {if {[lindex $q 0] eq $target} {return $q}}
    _error "rerender cache/runtime is unavailable for base graph '$graphId'; render it first"
}

# Standard Module runtime still requires a primary source even when a public
# consumer has supplied complete Graph Series identities. Use the first active
# series as that source only while constructing the standard command. This
# keeps consumers independent of framework source-state internals and leaves
# any user-selected primary source untouched.
proc ::GX::PlotDatasetAPIv1::_renderCommandWithSeriesSource {ref operation} {
    variable moduleId
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    set row [::GX::analysisSourceFindRow $moduleId primary]
    set injected 0
    if {$row && [::GX::analysisSourceRowDataset $moduleId $row] eq "" &&
        [string tolower [::GX::moduleGraphField $moduleId $graphId series_editor ""]] eq "standard"} {
        set active [listSeries $ref 0]
        if {[llength $active]} {
            set datasetId [dict get [lindex $active 0] dataset_id]
            set ::GX::moduleAnalysisSource($moduleId,$row,dataset_id) $datasetId
            set injected 1
        }
    }
    set code [catch {
        if {$variantId eq ""} {
            if {$operation eq "render"} {
                set item [_baseRenderCommand $graphId]
            } else {
                set item [_baseRerenderCommand $graphId]
            }
        } else {
            set item [::GX::plotVariantCommand $moduleId $graphId $variantId [expr {$operation eq "render" ? "analysis" : "rerender"}]]
        }
    } err opts]
    if {$injected} {set ::GX::moduleAnalysisSource($moduleId,$row,dataset_id) ""}
    if {$code} {return -options $opts $err}
    return $item
}

proc ::GX::PlotDatasetAPIv1::renderCommand {plotRef {operation render}} {
    variable moduleId
    set ref [_normalizePlotRef $plotRef]
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    switch -- $operation {
        render - analysis {
            requireCapability render
            return [_renderCommandWithSeriesSource $ref render]
        }
        rerender {
            requireCapability rerender
            return [_renderCommandWithSeriesSource $ref rerender]
        }
        default {_error "operation must be 'render' or 'rerender'"}
    }
}

proc ::GX::PlotDatasetAPIv1::_executeQueueItem {item} {
    if {[llength $item] < 2} {_error "invalid framework render command"}
    set label [lindex $item 0]
    set cmd [lindex $item 1]
    if {[catch {set output [exec {*}$cmd 2>@1]} err opts]} {
        _error "$label failed: $err"
    }
    return [dict create label $label output $output]
}

proc ::GX::PlotDatasetAPIv1::render {plotRef} {
    set ref [_normalizePlotRef $plotRef]
    set execution [_executeQueueItem [renderCommand $ref render]]
    return [dict create execution $execution artifacts [artifacts $ref]]
}

proc ::GX::PlotDatasetAPIv1::rerender {plotRef} {
    set ref [_normalizePlotRef $plotRef]
    set execution [_executeQueueItem [renderCommand $ref rerender]]
    return [dict create execution $execution artifacts [artifacts $ref]]
}
