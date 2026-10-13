# GX-TXT Plot Module API v1: optional persistent plot variants.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable plotVariant
    variable plotVariantConfig
    variable plotVariantBinding
    variable plotVariantGraphics
    variable plotVariantCounter
    array set plotVariant {}
    array set plotVariantConfig {}
    array set plotVariantBinding {}
    array set plotVariantGraphics {}
    array set plotVariantCounter {}
}
proc ::GX::plotVariantSupports {moduleId graphId} {
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $moduleId] ||
        ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $graphId]} { return 0 }
    return [expr {[lsearch -exact [moduleGraphIds $moduleId] $graphId] >= 0 &&
        [string tolower [moduleGraphField $moduleId $graphId supports_variants 0]] in {1 yes true on}}]
}
proc ::GX::plotVariantDataModel {moduleId graphId} {
    set model [string tolower [string trim [moduleGraphField $moduleId $graphId variant_data_model series]]]
    if {$model eq ""} { set model series }
    if {$model ni {series module_cache}} {
        error "Unsupported variant_data_model '$model' for $moduleId/$graphId"
    }
    return $model
}
proc ::GX::plotVariantExists {moduleId graphId variantId} {
    variable plotVariant
    return [info exists plotVariant($moduleId,$graphId,$variantId,title)]
}
proc ::GX::plotVariantIds {moduleId graphId} {
    variable plotVariant
    set out {}
    foreach k [array names plotVariant "$moduleId,$graphId,*,title"] {
        lappend out [lindex [split $k ,] 2]
    }
    return [lsort -dictionary $out]
}
proc ::GX::plotVariantField {moduleId graphId variantId field {default ""}} {
    variable plotVariant
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant $moduleId/$graphId/$variantId" }
    if {[info exists plotVariant($moduleId,$graphId,$variantId,$field)]} { return $plotVariant($moduleId,$graphId,$variantId,$field) }
    return $default
}
proc ::GX::plotVariantSet {moduleId graphId variantId fields} {
    variable plotVariant
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    dict for {field value} $fields {
        if {$field ni {title enabled provider_key}} { error "Unknown plot variant field: $field" }
        if {[regexp {[\r\n]} $value]} { error "Variant fields must be single-line" }
        if {$field eq "enabled" && $value ni {0 1}} { error "enabled must be 0 or 1" }
        if {$field eq "provider_key" && $value ne ""} {
            foreach other [plotVariantIds $moduleId $graphId] {
                if {$other ne $variantId && [plotVariantField $moduleId $graphId $other provider_key ""] eq $value} {
                    error "Provider key '$value' is already used by variant $other"
                }
            }
        }
        set plotVariant($moduleId,$graphId,$variantId,$field) $value
    }
    catch {refreshGraphs}
    catch {refreshManifestPreview}
}
proc ::GX::plotVariantFindProviderKey {moduleId graphId providerKey} {
    if {$providerKey eq ""} {error "Provider key must not be empty"}
    foreach vid [plotVariantIds $moduleId $graphId] {
        if {[plotVariantField $moduleId $graphId $vid provider_key ""] eq $providerKey} {return $vid}
    }
    return ""
}
proc ::GX::plotVariantKey {graphId variantId} {
    if {$variantId eq ""} { return $graphId }
    return "$graphId.$variantId"
}
proc ::GX::plotVariantDecodeKey {moduleId key} {
    foreach graph [moduleGraphIds $moduleId] {
        if {$key eq $graph} { return [list $graph ""] }
        foreach vid [plotVariantIds $moduleId $graph] {
            if {$key eq [plotVariantKey $graph $vid]} { return [list $graph $vid] }
        }
    }
    return {}
}
proc ::GX::plotVariantOutputDir {moduleId graphId variantId} {
    variable currentSession
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    if {$currentSession eq ""} { error "Open a session first" }
    return [file join $currentSession analysis $moduleId variants $graphId $variantId]
}
proc ::GX::plotVariantArtifact {moduleId graphId variantId} {
    return [file join [plotVariantOutputDir $moduleId $graphId $variantId] [moduleGraphField $moduleId $graphId file ""]]
}
proc ::GX::plotVariantCreate {moduleId graphId {sourceVariant ""}} {
    variable plotVariant
    variable plotVariantCounter
    variable plotVariantConfig
    variable plotVariantBinding
    variable modulePlotCfg
    variable axisOverride
    variable legendOverride
    variable levelScale
    variable plotRegion
    variable graphSeries
    variable plotVariantGraphics
    if {![plotVariantSupports $moduleId $graphId]} { error "Graph does not declare supports_variants: $moduleId/$graphId" }
    set dataModel [plotVariantDataModel $moduleId $graphId]
    if {$sourceVariant ne "" && ![plotVariantExists $moduleId $graphId $sourceVariant]} { error "Unknown source variant" }
    if {![info exists plotVariantCounter($moduleId,$graphId)]} { set plotVariantCounter($moduleId,$graphId) 0 }
    while 1 {
        incr plotVariantCounter($moduleId,$graphId)
        set vid [format p%04d $plotVariantCounter($moduleId,$graphId)]
        if {![plotVariantExists $moduleId $graphId $vid]} break
    }
    set sourceKey [plotVariantKey $graphId $sourceVariant]
    set targetKey [plotVariantKey $graphId $vid]
    set plotVariant($moduleId,$graphId,$vid,title) "Plot $vid"
    set plotVariant($moduleId,$graphId,$vid,enabled) 1
    set plotVariant($moduleId,$graphId,$vid,provider_key) ""
    foreach key [moduleGraphConfigKeys $moduleId $graphId] {
        if {$sourceVariant eq ""} {
            set value [expr {[info exists modulePlotCfg($moduleId,$graphId,$key)] ? $modulePlotCfg($moduleId,$graphId,$key) : [moduleGraphConfigField $moduleId $graphId $key default ""]}]
        } else {
            set value $plotVariantConfig($moduleId,$graphId,$sourceVariant,$key)
        }
        set plotVariantConfig($moduleId,$graphId,$vid,$key) $value
    }
    foreach a {axisOverride legendOverride} {
        upvar 0 ::GX::$a state
        foreach k [array names state "$sourceKey,*"] {
            set suffix [string range $k [string length $sourceKey] end]
            set state($targetKey$suffix) $state($k)
        }
    }
    foreach axis {y y2 z} {
        if {[info exists levelScale($sourceKey,$axis)]} { set levelScale($targetKey,$axis) $levelScale($sourceKey,$axis) }
    }
    foreach k [array names plotRegion "$moduleId,$sourceKey,*"] {
        set suffix [string range $k [string length "$moduleId,$sourceKey"] end]
        set plotRegion($moduleId,$targetKey$suffix) $plotRegion($k)
    }
    foreach role [expr {$dataModel eq "series" ? [moduleBindingRoles $moduleId] : {}}] {
        if {$sourceVariant ne ""} {
            if {[info exists plotVariantBinding($moduleId,$graphId,$sourceVariant,$role)]} {
                set plotVariantBinding($moduleId,$graphId,$vid,$role) $plotVariantBinding($moduleId,$graphId,$sourceVariant,$role)
            }
        } else {
            catch {
                set value [resolveModuleBinding $moduleId $role ""]
                set ds [analysisSourceDatasetFor $moduleId primary]
                set name [lindex [split $value .] end]
                set v [datasetVariableResolve $ds $name]
                set plotVariantBinding($moduleId,$graphId,$vid,$role) [dict create dataset_id $ds variable_id [dict get $v variable_id]]
            }
        }
    }
    foreach field [moduleGraphicsFields] {
        if {$sourceVariant ne "" && [info exists plotVariantGraphics($moduleId,$graphId,$sourceVariant,$field)]} {
            set plotVariantGraphics($moduleId,$graphId,$vid,$field) $plotVariantGraphics($moduleId,$graphId,$sourceVariant,$field)
        } else {
            set plotVariantGraphics($moduleId,$graphId,$vid,$field) ""
        }
    }
    foreach sid [expr {$dataModel eq "series" ? [graphSeriesIds $moduleId $graphId $sourceVariant] : {}}] {
        set old [graphSeriesKey $moduleId $graphId $sid $sourceVariant]
        set graphSeries([graphSeriesKey $moduleId $graphId $sid $vid]) $graphSeries($old)
    }
    if {$::GX::currentSession ne "" && [file isdirectory $::GX::currentSession] && [llength [info commands ::GX::annotationPathForPlot]]} {
        if {$sourceVariant eq ""} {
            set sourceArtifact [file join $::GX::currentSession analysis $moduleId [moduleGraphField $moduleId $graphId file ""]]
        } else {
            set sourceArtifact [plotVariantArtifact $moduleId $graphId $sourceVariant]
        }
        set annotationSource [annotationPathForPlot $sourceArtifact]
        if {[file isfile $annotationSource]} {
            set annotationTarget [annotationPathForPlot [plotVariantArtifact $moduleId $graphId $vid]]
            file mkdir [file dirname $annotationTarget]
            file copy -force -- $annotationSource $annotationTarget
        }
    }
    if {[llength [info commands ::GX::graphResourceCopy]]} {
        graphResourceCopy [dict create kind provider module_id $moduleId graph_id $graphId variant_id $sourceVariant] \
            [dict create kind provider module_id $moduleId graph_id $graphId variant_id $vid]
    }
    catch {refreshManifestPreview}
    return $vid
}

# A provider can create a plot from a complete Dataset specification without
# inheriting the base graph's data-specific viewport or region selection.
# Keep this operation in CORE, where variant presentation state is owned.
proc ::GX::plotVariantResetInheritedDataView {moduleId graphId variantId} {
    variable axisOverride
    variable plotRegion
    variable levelScale
    variable legendOverride
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    set key [plotVariantKey $graphId $variantId]
    foreach a {axisOverride legendOverride levelScale} {
        upvar 0 ::GX::$a state
        array unset state "$key,*"
    }
    array unset plotRegion "$moduleId,$key,*"
    return $key
}
proc ::GX::plotVariantDuplicate {moduleId graphId variantId} {
    return [plotVariantCreate $moduleId $graphId $variantId]
}
proc ::GX::plotVariantConfigSet {moduleId graphId variantId key value} {
    variable plotVariantConfig
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] $key] < 0} { error "Unknown plot configuration key" }
    if {[regexp {[\r\n]} $value]} { error "Plot configuration must be single-line" }
    set plotVariantConfig($moduleId,$graphId,$variantId,$key) $value
    catch {refreshManifestPreview}
}
proc ::GX::plotVariantConfigGet {moduleId graphId variantId key} {
    variable plotVariantConfig
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    return $plotVariantConfig($moduleId,$graphId,$variantId,$key)
}
proc ::GX::plotVariantBindingSet {moduleId graphId variantId role datasetId variableId} {
    variable plotVariantBinding
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    if {[lsearch -exact [moduleBindingRoles $moduleId] $role] < 0} { error "Unknown module binding role" }
    if {$datasetId eq "" && $variableId eq ""} {
        catch {unset plotVariantBinding($moduleId,$graphId,$variantId,$role)}
        return
    }
    set v [datasetVariableById $datasetId $variableId]
    set plotVariantBinding($moduleId,$graphId,$variantId,$role) [dict create dataset_id $datasetId variable_id $variableId]
    catch {refreshManifestPreview}
    return $v
}
proc ::GX::plotVariantBindingGet {moduleId graphId variantId role} {
    variable plotVariantBinding
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    if {[info exists plotVariantBinding($moduleId,$graphId,$variantId,$role)]} {
        return $plotVariantBinding($moduleId,$graphId,$variantId,$role)
    }
    return {}
}
proc ::GX::plotVariantGraphicsSet {moduleId graphId variantId field value} {
    variable plotVariantGraphics
    variable axisOverride
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    if {$field ni [moduleGraphicsFields]} { error "Unknown graphics field" }
    if {[regexp {[\r\n]} $value]} { error "Graphics value must be single-line" }
    if {$field in {width_px height_px dpi font_size axis_label_font_size title_font_size line_width legend_columns legend_font_size legend_margin_px} &&
        $value ne "" && $value ne "inherit" &&
        (![string is double -strict $value] || $value <= 0)} {
        error "$field must be positive or inherit/blank"
    }
    if {$field eq "background"} {
        if {$value ni {"" inherit transparent} && ![regexp {^#[0-9A-Fa-f]{6}$} $value]} {error "Plot background must be #RRGGBB, transparent, or inherit"}
        set axisOverride([plotVariantKey $graphId $variantId],background) [expr {$value eq "inherit" ? "" : $value}]
        catch {unset plotVariantGraphics($moduleId,$graphId,$variantId,background)}
    } else {
        set plotVariantGraphics($moduleId,$graphId,$variantId,$field) $value
    }
    catch {refreshManifestPreview}
}
proc ::GX::plotVariantGraphicsGet {moduleId graphId variantId field} {
    variable plotVariantGraphics
    variable axisOverride
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    if {$field ni [moduleGraphicsFields]} { error "Unknown graphics field" }
    if {$field eq "background"} {
        set key [plotVariantKey $graphId $variantId]
        return [expr {[info exists axisOverride($key,background)] ? $axisOverride($key,background) : ""}]
    }
    if {[info exists plotVariantGraphics($moduleId,$graphId,$variantId,$field)]} {
        return $plotVariantGraphics($moduleId,$graphId,$variantId,$field)
    }
    return ""
}
proc ::GX::plotVariantDelete {moduleId graphId variantId} {
    variable currentSession
    variable graphUseState
    if {![plotVariantExists $moduleId $graphId $variantId]} { error "Unknown plot variant" }
    set key [plotVariantKey $graphId $variantId]
    set dir ""
    if {$currentSession ne ""} { set dir [plotVariantOutputDir $moduleId $graphId $variantId] }
    if {$dir ne "" && [file exists $dir] && [file type $dir] eq "link"} { error "Variant artifact directory is a symlink" }
    if {[llength [info commands ::GX::graphResourceDelete]]} {
        graphResourceDelete [dict create kind provider module_id $moduleId graph_id $graphId variant_id $variantId]
    }
    foreach a {plotVariant plotVariantConfig plotVariantBinding plotVariantGraphics graphSeries axisOverride legendOverride levelScale plotRegion} {
        upvar 0 ::GX::$a state
        switch $a {
            plotVariant - plotVariantConfig - plotVariantBinding - plotVariantGraphics - graphSeries { array unset state "$moduleId,$graphId,$variantId,*" }
            axisOverride - legendOverride - levelScale { array unset state "$key,*" }
            plotRegion { array unset state "$moduleId,$key,*" }
        }
    }
    catch {unset graphUseState($moduleId,$graphId,$variantId)}
    if {$dir ne "" && [file exists $dir]} {
        file delete -force -- $dir
    }
    catch {refreshGraphs}
    catch {refreshManifestPreview}
}

# Additive Manifest Format 2 fields. Old manifests have no plot_variant sections.
proc ::GX::manifestStringV2_before_graph_workflow {} {
    variable plotVariant
    variable plotVariantCounter
    variable plotVariantConfig
    variable plotVariantBinding
    variable plotVariantGraphics
    variable plotRegion
    set out [::GX::manifestStringV2_before_plot_variant]
    append out "\n\[plot_variant_api\]\n"; appendKV out version 1
    foreach mid $::GX::moduleOrder {
        foreach gid [moduleGraphIds $mid] {
            if {![plotVariantSupports $mid $gid]} continue
            if {[info exists plotVariantCounter($mid,$gid)]} {
                append out "\n\[plot_variant_counter.$mid.$gid\]\n"
                appendKV out value $plotVariantCounter($mid,$gid)
            }
            foreach vid [plotVariantIds $mid $gid] {
                append out "\n\[plot_variant.$mid.$gid.$vid\]\n"
                foreach f {title enabled provider_key} { appendKV out $f [plotVariantField $mid $gid $vid $f ""] }
                foreach f [moduleGraphConfigKeys $mid $gid] {
                    appendKV out "config_$f" $plotVariantConfig($mid,$gid,$vid,$f)
                }
                foreach role [moduleBindingRoles $mid] {
                    if {![info exists plotVariantBinding($mid,$gid,$vid,$role)]} continue
                    set binding $plotVariantBinding($mid,$gid,$vid,$role)
                    appendKV out "binding_$role.dataset_id" [dict get $binding dataset_id]
                    appendKV out "binding_$role.variable_id" [dict get $binding variable_id]
                }
                foreach field [moduleGraphicsFields] {
                    if {$field eq "background"} continue
                    appendKV out "graphics_$field" [plotVariantGraphicsGet $mid $gid $vid $field]
                }
                if {[plotRegionSupports $mid $gid]} {
                    set key [plotVariantKey $gid $vid]
                    plotRegionEnsure $mid $key
                    append out "\n\[plot_variant_region.$mid.$gid.$vid\]\n"
                    foreach f {enabled space axis x_min x_max y_min y_max} { appendKV out $f $plotRegion($mid,$key,$f) }
                }
            }
        }
    }
    return $out
}
proc ::GX::loadManifestV2_before_graph_workflow {path} {
    variable plotVariant
    variable plotVariantCounter
    variable plotVariantConfig
    variable plotVariantBinding
    variable plotVariantGraphics
    variable plotRegion
    array unset plotVariant *
    array unset plotVariantCounter *
    array unset plotVariantConfig *
    array unset plotVariantBinding *
    array unset plotVariantGraphics *
    ::GX::loadManifestV2_before_plot_variant $path
    set ini [parseIni $path]
    foreach mid $::GX::moduleOrder {
        foreach gid [moduleGraphIds $mid] {
            if {![plotVariantSupports $mid $gid]} continue
            set counterKey "plot_variant_counter.$mid.$gid.value"
            if {[dict exists $ini $counterKey]} { set plotVariantCounter($mid,$gid) [dict get $ini $counterKey] }
            foreach key [dict keys $ini "plot_variant.$mid.$gid.*.title"] {
                set prefix "plot_variant.$mid.$gid."
                set vid [string range $key [string length $prefix] end-[string length ".title"]]
                if {![regexp {^p[0-9]+$} $vid]} continue
                set base "$prefix$vid."
                set plotVariant($mid,$gid,$vid,title) [dict get $ini $key]
                set plotVariant($mid,$gid,$vid,enabled) [expr {[dict exists $ini "${base}enabled"] ? [dict get $ini "${base}enabled"] : 1}]
                set plotVariant($mid,$gid,$vid,provider_key) [expr {[dict exists $ini "${base}provider_key"] ? [dict get $ini "${base}provider_key"] : ""}]
                foreach f [moduleGraphConfigKeys $mid $gid] {
                    set name "${base}config_$f"
                    set plotVariantConfig($mid,$gid,$vid,$f) [expr {[dict exists $ini $name] ? [dict get $ini $name] : [moduleGraphConfigField $mid $gid $f default ""]}]
                }
                foreach role [moduleBindingRoles $mid] {
                    set dk "${base}binding_$role.dataset_id"
                    set vk "${base}binding_$role.variable_id"
                    if {[dict exists $ini $dk] && [dict exists $ini $vk]} {
                        set plotVariantBinding($mid,$gid,$vid,$role) [dict create dataset_id [dict get $ini $dk] variable_id [dict get $ini $vk]]
                    }
                }
                foreach field [moduleGraphicsFields] {
                    set name "${base}graphics_$field"
                    set plotVariantGraphics($mid,$gid,$vid,$field) [expr {[dict exists $ini $name] ? [dict get $ini $name] : ""}]
                }
                set oldBackground [string trim $plotVariantGraphics($mid,$gid,$vid,background)]
                set graphKey [plotVariantKey $gid $vid]
                if {$oldBackground ne "" && $oldBackground ne "inherit" &&
                    (![info exists ::GX::axisOverride($graphKey,background)] || $::GX::axisOverride($graphKey,background) eq "")} {
                    set ::GX::axisOverride($graphKey,background) $oldBackground
                }
                unset plotVariantGraphics($mid,$gid,$vid,background)
                set number [scan [string range $vid 1 end] %d]
                if {![info exists plotVariantCounter($mid,$gid)] || $number > $plotVariantCounter($mid,$gid)} { set plotVariantCounter($mid,$gid) $number }
                set graphKey [plotVariantKey $gid $vid]
                foreach f {enabled space axis x_min x_max y_min y_max} {
                    set name "plot_variant_region.$mid.$gid.$vid.$f"
                    if {[dict exists $ini $name]} { set plotRegion($mid,$graphKey,$f) [dict get $ini $name] }
                }
            }
        }
    }
}
proc ::GX::defaults_before_graph_workflow {} {
    ::GX::defaults_before_plot_variant
    foreach a {plotVariant plotVariantCounter plotVariantConfig plotVariantBinding plotVariantGraphics} {
        upvar 0 ::GX::$a state
        array unset state *
    }
}

proc ::GX::plotVariantResolvedBinding {moduleId graphId variantId role} {
    set binding [plotVariantBindingGet $moduleId $graphId $variantId $role]
    if {$binding eq ""} { return {} }
    set ds [dict get $binding dataset_id]
    set vid [dict get $binding variable_id]
    set v [datasetVariableById $ds $vid]
    if {![dict get $v enabled]} { error "$moduleId/$graphId/$variantId: $role is Use=no ($ds/$vid); enable the variable before rendering" }
    set path [datasetResolvePath $::GX::currentSession $ds]
    if {![file isfile $path]} { error "$moduleId/$graphId/$variantId: canonical data for $ds/$vid is unavailable" }
    return [dict merge $binding [dict create name [dict get $v canonical] unit [dict get $v unit] path $path]]
}
proc ::GX::plotVariantResolvedSeries {moduleId graphId variantId} {
    if {[plotVariantDataModel $moduleId $graphId] eq "module_cache"} { return {} }
    set out {}
    if {[llength [graphSeriesIds $moduleId $graphId $variantId]]} {
        set out [graphSeriesList $moduleId $graphId $variantId]
        if {![llength $out]} { error "$moduleId/$graphId/$variantId: no enabled Graph Series to render" }
        return $out
    }
    set x [plotVariantResolvedBinding $moduleId $graphId $variantId x]
    set y [plotVariantResolvedBinding $moduleId $graphId $variantId y]
    if {$x eq "" || $y eq ""} { error "$moduleId/$graphId/$variantId: X and Y stable-ID bindings are required" }
    if {[dict get $x dataset_id] ne [dict get $y dataset_id]} { error "X and Y in one series must use the same dataset" }
    set ds [dict get $x dataset_id]
    foreach {role axis} {y left y2 right} {
        set b [plotVariantResolvedBinding $moduleId $graphId $variantId $role]
        if {$b eq ""} continue
        if {[dict get $b dataset_id] ne $ds} { error "$role requires the X dataset; use Graph Series for another dataset" }
        set xv [datasetVariableById $ds [dict get $x variable_id]]
        set yv [datasetVariableById $ds [dict get $b variable_id]]
        lappend out [dict create module_id $moduleId graph_id $graphId variant_id $variantId series_id $role dataset_id $ds path [dict get $x path] x_variable_id [dict get $x variable_id] y_variable_id [dict get $b variable_id] x_name [dict get $x name] y_name [dict get $b name] x_unit [dict get $x unit] y_unit [dict get $b unit] x_semantic_role [dict get $xv semantic_role] y_semantic_role [dict get $yv semantic_role] x_value_kind [dict get $xv value_kind] x_value_format [dict get $xv value_format] x_decimal_separator [dict get $xv decimal_separator] y_value_kind [dict get $yv value_kind] y_value_format [dict get $yv value_format] y_decimal_separator [dict get $yv decimal_separator] axis $axis label "" enabled 1 order 0 time_reference [dict get $xv time_reference] time_origin [dict get $xv time_origin] x_time_reference [dict get $xv time_reference] x_time_origin [dict get $xv time_origin] y_time_reference [dict get $yv time_reference] y_time_origin [dict get $yv time_origin] alignment_mode none manual_offset_seconds 0]
    }
    return $out
}
proc ::GX::plotVariantDataFingerprint {moduleId graphId variantId series} {
    set items [list $moduleId $graphId $variantId]
    foreach field [moduleConfigKeys $moduleId] {
        if {[info exists ::GX::moduleCfg($moduleId,$field)]} { lappend items $field $::GX::moduleCfg($moduleId,$field) }
    }
    foreach field [splitList [moduleGraphField $moduleId $graphId preparation_fields ""]] {
        if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] $field] < 0} {
            error "Unknown graph preparation field: $field"
        }
        lappend items $field [plotVariantConfigGet $moduleId $graphId $variantId $field]
    }
    if {[plotVariantDataModel $moduleId $graphId] eq "module_cache"} {
        # The copied base runtime owns real scientific sources/bindings. Do not
        # infer them from a fake Graph Series or a variant X/Y pair.
        set runtime [parseIni [file join [plotVariantOutputDir $moduleId $graphId $variantId] runtime.ini]]
        foreach key [lsort [dict keys $runtime]] {
            if {[regexp {^(analysis_source[.][^.]+[.]path|dataset[.]path|bindings[.]|temporal_set[.])} $key]} {
                set value [dict get $runtime $key]
                lappend items $key $value
                if {[string match *.path $key] && [file isfile $value]} {
                    # Large scientific Datasets may be multi-GB. Their path,
                    # size and mtime are the same cheap change stamp consumed
                    # by module-cache providers; never rescan bytes per plot.
                    lappend items [file size $value] [file mtime $value]
                }
            }
        }
        set cache [file join $::GX::currentSession analysis [sanitize $moduleId] render_cache.mat]
        lappend items module_cache $cache
        if {[file isfile $cache]} { lappend items [sha256File $cache] }
    }
    foreach s $series {
        foreach field {series_id dataset_id x_variable_id y_variable_id axis alignment_mode manual_offset_seconds path} {
            lappend items $field [dict get $s $field]
        }
        lappend items [sha256File [dict get $s path]]
        foreach axis {x y} {
            lappend items [datasetVariableById [dict get $s dataset_id] [dict get $s "${axis}_variable_id"]]
        }
    }
    foreach role {z family color} {
        if {[lsearch -exact [moduleBindingRoles $moduleId] $role] < 0} continue
        set b [plotVariantBindingGet $moduleId $graphId $variantId $role]
        if {$b ne ""} {
            lappend items $role [dict get $b dataset_id] [dict get $b variable_id]
            lappend items [datasetVariableById [dict get $b dataset_id] [dict get $b variable_id]]
        }
    }
    set dir [plotVariantOutputDir $moduleId $graphId $variantId]
    file mkdir $dir
    set scratch [file join $dir .variant_fingerprint_input]
    set fd [open $scratch w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts -nonewline $fd $items
    close $fd
    try {
        return [sha256File $scratch]
    } finally {
        file delete -force -- $scratch
    }
}
proc ::GX::plotVariantWriteRuntime_before_graph_workflow {moduleId graphId variantId} {
    variable axisOverride
    variable legendOverride
    variable plotRegion
    variable plotVariantConfig
    set outDir [plotVariantOutputDir $moduleId $graphId $variantId]
    set dataModel [plotVariantDataModel $moduleId $graphId]
    file mkdir $outDir
    loadDatasetRegistry $::GX::currentSession
    set series [plotVariantResolvedSeries $moduleId $graphId $variantId]
    if {$dataModel eq "series"} {
        if {![llength $series]} { error "Variant has no series" }
        set runtimeSeries [expr {[llength [graphSeriesIds $moduleId $graphId $variantId]] ? [graphSeriesList $moduleId $graphId $variantId 1] : $series}]
        set primary [lindex $series 0]
    }
    # Inherit framework/module graphics, then project only this variant's state.
    # writeStandardRuntimeConfig targets the module's base output directory.
    # Preserve that base runtime while using it as a serialization template;
    # otherwise switching to a variant leaves the base with unrelated derived
    # state until its next render.
    set basePath [file join $::GX::currentSession analysis [sanitize $moduleId] runtime.ini]
    set baseExisted [file isfile $basePath]
    set baseBytes ""
    if {$baseExisted} {
        set saved [open $basePath r]
        fconfigure $saved -translation binary -encoding binary
        set baseBytes [read $saved]
        close $saved
    }
    set runtime [file join $outDir runtime.ini]
    # A persistent series variant carries its own stable Dataset bindings. A
    # reopened Session may have no module-level primary source selected, so
    # supply the variant's primary Dataset only while serializing its runtime.
    set sourceRow 0
    set savedSource ""
    if {$dataModel eq "series" && [moduleSupportsAnalysisSources $moduleId]} {
        set sourceRow [analysisSourceFindRow $moduleId primary]
        if {$sourceRow} {
            set savedSource [analysisSourceRowDataset $moduleId $sourceRow]
            if {$savedSource eq ""} {
                set ::GX::moduleAnalysisSource($moduleId,$sourceRow,dataset_id) [dict get $primary dataset_id]
            }
        }
    }
    try {
        set base [writeStandardRuntimeConfig $moduleId]
        file copy -force -- $base $runtime
    } finally {
        if {$sourceRow && $savedSource eq ""} {
            set ::GX::moduleAnalysisSource($moduleId,$sourceRow,dataset_id) $savedSource
        }
        if {$baseExisted} {
            set saved [open $basePath w]
            fconfigure $saved -translation binary -encoding binary
            puts -nonewline $saved $baseBytes
            close $saved
        } else {
            catch {file delete -force -- $basePath}
        }
    }
    set fd [open $runtime a]; fconfigure $fd -encoding utf-8 -translation lf
    try {
    puts $fd "\n\[runtime\]"; putKV $fd output_dir $outDir
    puts $fd "\n\[render_cache_api\]"
    if {$dataModel eq "module_cache"} {
        putKV $fd path [file join $::GX::currentSession analysis [sanitize $moduleId] render_cache.mat]
    } else {
        putKV $fd path [file join $outDir render_cache.mat]
    }
    puts $fd "\n\[plot_variant\]"
    putKV $fd api_version 1; putKV $fd graph_id $graphId; putKV $fd variant_id $variantId
    putKV $fd data_model $dataModel
    putKV $fd title [plotVariantField $moduleId $graphId $variantId title]
    puts $fd "\n\[graph_provider\]"; putKV $fd enabled $graphId
    puts $fd "\n\[plot.$graphId\]"
    foreach field [moduleGraphConfigKeys $moduleId $graphId] {
        putKV $fd $field $plotVariantConfig($moduleId,$graphId,$variantId,$field)
    }
    if {$dataModel eq "series"} {
    set ds [dict get $primary dataset_id]
    set source [dict get $primary path]
    puts $fd "\n\[dataset\]"
    putKV $fd id $ds; putKV $fd path $source; putKV $fd kind [datasetField $ds kind ""]
    putKV $fd columns [datasetField $ds columns ""]
    puts $fd "\n\[analysis_source.primary\]"
    putKV $fd dataset_id $ds; putKV $fd path $source
    putKV $fd kind [datasetField $ds kind ""]
    putKV $fd columns [datasetField $ds columns ""]
    putKV $fd contract [datasetField $ds kind ""]
    putKV $fd format [datasetField $ds format ""]
    set vars [analysisSourceDatasetVariables $ds]
    set names {}; set units {}; set roles {}
    foreach v $vars {
        lappend names [dict get $v name]
        lappend units [dict get $v unit]
        lappend roles [dict get $v semantic_role]
    }
    putKV $fd variables [join $names ";"]
    putKV $fd units [join $units ";"]
    putKV $fd semantic_roles [join $roles ";"]
    putKV $fd variable_count [llength $vars]
    set i 0
    foreach v $vars {
        incr i
        puts $fd "\n\[analysis_source.primary.variable.$i\]"
        foreach field {name variable_id unit semantic_role semantic_source semantic_reason original_header source_column value_kind value_format decimal_separator time_reference time_origin} {
            putKV $fd $field [dict get $v $field]
        }
    }
    puts $fd "\n\[bindings\]"
    set explicitSeries [expr {[llength [graphSeriesIds $moduleId $graphId $variantId]] > 0}]
    foreach role [moduleBindingRoles $moduleId] {
        if {$role eq "x"} {
            putKV $fd x "primary.[dict get $primary x_name]"
        } elseif {$role eq "y"} {
            putKV $fd y "primary.[dict get $primary y_name]"
        } elseif {$explicitSeries && $role in {y2 family color}} {
            putKV $fd $role ""
        } else {
            set b [plotVariantResolvedBinding $moduleId $graphId $variantId $role]
            if {$b eq ""} {
                putKV $fd $role ""
            } else {
                if {[dict get $b dataset_id] ne $ds} { error "$role must use the primary dataset for this graph" }
                putKV $fd $role "primary.[dict get $b name]"
            }
        }
    }
    }
    set key [plotVariantKey $graphId $variantId]
    puts $fd "\n\[axis.$graphId\]"
    # Plot layout is independent of the Axes editor's enabled flag. A
    # layout-only Variant must still transport its margins to the renderer.
    set has [expr {[info exists axisOverride($key,enabled)] || [info exists axisOverride($key,layout_auto)]}]
    putKV $fd enabled [expr {[info exists axisOverride($key,enabled)] ? $axisOverride($key,enabled) : 0}]
    if {$has} {
        foreach ak [lsort [array names axisOverride "$key,*"]] {
            set suffix [string range $ak [expr {[string length $key]+1}] end]
            if {[string first , $suffix] < 0 && $suffix ni {enabled panels}} {
                putKV $fd $suffix $axisOverride($ak)
            }
        }
        set panels [expr {[info exists axisOverride($key,panels)] ? $axisOverride($key,panels) : {}}]
        putKV $fd panel_count [llength $panels]
        set pi 0
        foreach panel $panels {
            incr pi
            putKV $fd "panel${pi}_name" $panel
            foreach ak [lsort [array names axisOverride "$key,$panel,*"]] {
                set field [string range $ak [string length "$key,$panel,"] end]
                putKV $fd "panel${pi}_$field" $axisOverride($ak)
            }
        }
    }
    puts $fd "\n\[legend.$graphId\]"
    set has [info exists legendOverride($key,enabled)]
    putKV $fd enabled [expr {$has ? $legendOverride($key,enabled) : 0}]
    if {$has} {
        foreach lk [lsort [array names legendOverride "$key,*"]] {
            set field [string range $lk [expr {[string length $key]+1}] end]
            if {$field ne "enabled"} { putKV $fd $field $legendOverride($lk) }
        }
    }
    foreach axis {y y2 z} {
        puts $fd "\n\[level_scale.$graphId.$axis\]"
        set ls [levelScaleGet $key $axis]
        dict for {field value} $ls { putKV $fd $field $value }
    }
    if {[plotRegionSupports $moduleId $graphId]} {
        plotRegionEnsure $moduleId $key
        puts $fd "\n\[plot.region.$graphId\]"
        foreach field {enabled space axis x_min x_max y_min y_max} { putKV $fd $field $plotRegion($moduleId,$key,$field) }
    }
    if {$dataModel eq "series"} {
        puts $fd "\n\[graph_series\]"
        putKV $fd api_version 1; putKV $fd count [llength $runtimeSeries]
        set i 0
        foreach item $runtimeSeries {
            incr i
            puts $fd "\n\[graph_series.$i\]"
            putKV $fd scientific_dataset_identity [graphSeriesPreparationIdentity [dict get $item dataset_id]]
            putKV $fd dataset_row_count [datasetField [dict get $item dataset_id] row_count ""]
            foreach field {module_id graph_id variant_id series_id dataset_id path x_variable_id y_variable_id x_name y_name x_unit y_unit x_semantic_role y_semantic_role x_value_kind x_value_format x_decimal_separator y_value_kind y_value_format y_decimal_separator axis label enabled order time_reference time_origin x_time_reference x_time_origin y_time_reference y_time_origin alignment_mode manual_offset_seconds} {
                putKV $fd $field [dict get $item $field]
            }
            foreach field {family_variable_id secondary_variable_id ordering_variable_id style_color style_line_style} {
                putKV $fd $field [expr {[dict exists $item $field] ? [dict get $item $field] : ""}]
            }
            putKV $fd source_row_ordinals [datasetPublicationV2DictDefault $item source_row_ordinals {}]
            set filters [expr {[dict exists $item row_filters] ? [dict get $item row_filters] : {}}]
            putKV $fd filter_count [llength $filters]
            set j 0
            foreach filter $filters {
                incr j
                dict for {field value} $filter {
                    if {$field ne "values"} {putKV $fd "filter_${j}_$field" $value}
                }
                if {[dict exists $filter values]} {
                    set values [dict get $filter values]
                    putKV $fd "filter_${j}_value_count" [llength $values]
                    set k 0
                    foreach value $values {putKV $fd "filter_${j}_value_[incr k]" $value}
                }
            }
        }
    }
    } finally {
        close $fd
    }
    return [list $runtime [plotVariantDataFingerprint $moduleId $graphId $variantId $series]]
}
proc ::GX::plotVariantWriteRuntime {moduleId graphId variantId} {
    tailcall ::GX::plotVariantWriteRuntime_before_graph_workflow $moduleId $graphId $variantId
}
proc ::GX::plotVariantWriteGraphMap {moduleId graphId variantId} {
    variable axisOverride
    set dir [plotVariantOutputDir $moduleId $graphId $variantId]
    set path [file join $dir .plot_graph_map.tsv]
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "path\tkey\tpanels"
    set key [plotVariantKey $graphId $variantId]
    set panels [expr {[info exists axisOverride($key,panels)] ? $axisOverride($key,panels) : {}}]
    puts $fd "[file normalize [plotVariantArtifact $moduleId $graphId $variantId]]\t$key\t[join $panels ";"]"
    close $fd
    return $path
}
proc ::GX::plotVariantCommand {moduleId graphId variantId operation} {
    variable cfg
    variable scriptDir
    lassign [plotVariantWriteRuntime $moduleId $graphId $variantId] runtime fingerprint
    set dir [plotVariantOutputDir $moduleId $graphId $variantId]
    set dataModel [plotVariantDataModel $moduleId $graphId]
    set cache [expr {$dataModel eq "module_cache" ? [file join $::GX::currentSession analysis [sanitize $moduleId] render_cache.mat] : [file join $dir render_cache.mat]}]
    set stamp [file join $dir .variant_data_fingerprint]
    if {$dataModel eq "module_cache"} {
        # A module-cache variant is presentation only. Even an analysis-queue
        # request must never fall back to the scientific runner.
        if {$operation eq "rerender" && ![file isfile $cache]} {
            error "$moduleId/$graphId/$variantId: base render cache is missing; run base analysis first"
        }
        set operation rerender
    } elseif {$operation eq "rerender"} {
        set reusable 0
        if {[file isfile $cache] && [file isfile $stamp]} {
            set sf [open $stamp r]
            set previous [string trim [read $sf]]
            close $sf
            if {$previous eq $fingerprint} { set reusable 1 }
        }
        if {!$reusable} { set operation analysis }
    }
    set scriptField [expr {$operation eq "rerender" ? "rerender_script" : "runner_script"}]
    set script [file join $scriptDir [moduleField $moduleId $scriptField ""]]
    if {![file isfile $script]} { error "Variant runner is unavailable: $script" }
    set runId [progressNewRunId $moduleId $operation]
    appendProgressRuntimeJob $runtime $moduleId $runId $operation
    set child [list $cfg(octave_cmd) --quiet --no-gui $script --config $runtime]
    if {$operation eq "rerender"} { lappend child --cache $cache }
    if {$dataModel eq "module_cache"} {
        set expected [moduleGraphField $moduleId $graphId file ""]
    } else {
        set expected [join [concat [splitList [moduleField $moduleId outputs ""]] [list [moduleGraphField $moduleId $graphId file ""]]] ";"]
    }
    set envmap [plotEnv $moduleId]
    set graphicsMap [moduleGraphicsEnvMap]
    foreach field [moduleGraphicsFields] {
        if {$field eq "background"} continue
        set value [string trim [plotVariantGraphicsGet $moduleId $graphId $variantId $field]]
        if {$value ne "" && $value ne "inherit" && [dict exists $graphicsMap $field]} {
            set envmap [envListReplace $envmap [dict get $graphicsMap $field] $value]
        }
    }
    set envmap [envListReplace $envmap GXTXT_PLOT_GRAPH_MAP_FILE [plotVariantWriteGraphMap $moduleId $graphId $variantId]]
    set cmd [concat [list env OMP_NUM_THREADS=$cfg(cpu_count) OPENBLAS_NUM_THREADS=$cfg(cpu_count) MKL_NUM_THREADS=$cfg(cpu_count) NUMEXPR_NUM_THREADS=$cfg(cpu_count) GXTXT_PROGRESS_ENABLED=1 GXTXT_PROGRESS_MODULE_ID=$moduleId GXTXT_PROGRESS_RUN_ID=$runId GXTXT_PROGRESS_OPERATION=$operation] [graphicsEnv] $envmap [list tclsh [file join $scriptDir core tcl standard_octave_exec.tcl] --output-dir $dir --expected $expected --stamp $stamp $fingerprint --] $child]
    return [list "[string totitle $operation] - [moduleField $moduleId name $moduleId] / [plotVariantField $moduleId $graphId $variantId title]" $cmd $moduleId $runId]
}
proc ::GX::buildStandardAnalysisQueue {} {
    set q [::GX::buildStandardAnalysisQueue_before_plot_variant]
    foreach mid $::GX::moduleOrder {
        if {![moduleIsEnabled $mid] || ![moduleRunIsSelected $mid]} continue
        if {[moduleField $mid runner ""] ne "standard_octave"} continue
        foreach gid [moduleGraphIds $mid] {
            foreach vid [plotVariantIds $mid $gid] {
                if {![plotVariantField $mid $gid $vid enabled 1]} continue
                if {[llength [info commands ::GX::graphUseStateGet]] && ![graphUseStateGet $mid $gid $vid]} continue
                lappend q [plotVariantCommand $mid $gid $vid analysis]
            }
        }
    }
    return $q
}
proc ::GX::buildStandardRerenderQueue_before_graph_workflow {paths} {
    set basePaths {}
    set variantRequests {}
    foreach p $paths {
        set v [plotVariantInfoForPath $p]
        if {[llength $v] == 3} {
            if {[lsearch -exact $variantRequests $v] < 0} { lappend variantRequests $v }
        } else {
            lappend basePaths $p
        }
    }
    set q [::GX::buildStandardRerenderQueue_before_plot_variant $basePaths]
    foreach v $variantRequests {
        lassign $v mid gid vid
        # variantRequests contains explicit artifact selections. Persistent USE
        # controls scheduled runs, not a direct rerender of the chosen variant.
        if {[plotVariantField $mid $gid $vid enabled 1]} {
            lappend q [plotVariantCommand $mid $gid $vid rerender]
        }
    }
    return $q
}

proc ::GX::plotVariantPathCandidate {path} {
    variable currentSession
    if {$currentSession eq ""} { return 0 }
    set root [file normalize [file join $currentSession analysis]]
    set p [file normalize $path]
    if {[string first "$root/" "$p/"] != 0} { return 0 }
    set rel [string range $p [expr {[string length $root]+1}] end]
    set parts [file split $rel]
    if {[lindex $parts 1] ne "variants"} { return 0 }
    set mid [lindex $parts 0]
    foreach gid [moduleGraphIds $mid] {
        if {[plotVariantSupports $mid $gid]} { return 1 }
    }
    return 0
}
proc ::GX::plotVariantInfoForPath {path} {
    variable currentSession
    if {$currentSession eq ""} { return {} }
    set root [file normalize [file join $currentSession analysis]]
    set p [file normalize $path]
    if {[string first "$root/" "$p/"] != 0} { return {} }
    set rel [string range $p [expr {[string length $root]+1}] end]
    set parts [file split $rel]
    if {[llength $parts] < 5 || [lindex $parts 1] ne "variants"} { return {} }
    lassign $parts mid _ gid vid
    if {![plotVariantExists $mid $gid $vid]} { return {} }
    if {$p ne [file normalize [plotVariantArtifact $mid $gid $vid]]} { return {} }
    return [list $mid $gid $vid]
}
proc ::GX::nativeGraphInfoForPath {path} {
    set v [plotVariantInfoForPath $path]
    if {[llength $v] == 3} { return [lrange $v 0 1] }
    if {[plotVariantPathCandidate $path]} { return {} }
    return [::GX::nativeGraphInfoForPath_before_plot_variant $path]
}
proc ::GX::graphKeyForPath_before_graph_workflow {path} {
    set v [plotVariantInfoForPath $path]
    if {[llength $v] == 3} { return [plotVariantKey [lindex $v 1] [lindex $v 2]] }
    return [::GX::graphKeyForPath_before_plot_variant $path]
}
proc ::GX::graphKeyForPath {path} {
    return [::GX::graphKeyForPath_before_graph_workflow $path]
}
proc ::GX::plotRegionSupports {moduleId graphKey} {
    set decoded [plotVariantDecodeKey $moduleId $graphKey]
    if {[llength $decoded] == 2} { set graphKey [lindex $decoded 0] }
    return [::GX::plotRegionSupports_before_plot_variant $moduleId $graphKey]
}
proc ::GX::plotRegionType {moduleId graphKey} {
    set decoded [plotVariantDecodeKey $moduleId $graphKey]
    if {[llength $decoded] == 2} { set graphKey [lindex $decoded 0] }
    return [::GX::plotRegionType_before_plot_variant $moduleId $graphKey]
}

# Generic descriptor-driven GUI. The Graphs tab continues to edit axes,
# legend, level scale, annotations and regions through its existing services.
proc ::GX::buildModulePlotConfigFrame {parent mid} {
    set rows [::GX::buildModulePlotConfigFrame_before_plot_variant $parent $mid]
    set row 1
    foreach gid [moduleGraphIds $mid] {
        if {![winfo exists $parent.c$row]} { incr row; continue }
        if {[plotVariantSupports $mid $gid]} {
            ttk::button $parent.v$row -text "Variants..." -command [list ::GX::plotVariantManager $mid $gid]
            grid $parent.v$row -row $row -column 4 -sticky e -padx 4
        }
        if {[plotVariantSupports $mid $gid] || [moduleGraphField $mid $gid series_editor ""] eq "standard"} {
            ttk::button $parent.s$row -text "Series..." -command [list ::GX::graphSeriesEditorBase $mid $gid]
            grid $parent.s$row -row $row -column 5 -sticky e -padx 4
        }
        incr row
    }
    return $rows
}
proc ::GX::launchGui_before_session_actions {} {
    ::GX::launchGui_before_plot_variant
    set f .top.nb.graphs.actions
    if {[winfo exists $f] && ![winfo exists $f.variants]} {
        ttk::button $f.variants -text "Variants..." -command ::GX::plotVariantManagerForCurrent
        pack $f.variants -side left -padx 3
    }
}
proc ::GX::plotVariantManagerForCurrent {} {
    set p [currentGraphPath]
    set info [nativeGraphInfoForPath $p]
    if {[llength $info] != 2} { tk_messageBox -message "Select a Graph Provider plot first."; return }
    lassign $info mid gid
    if {![plotVariantSupports $mid $gid]} { tk_messageBox -message "This graph does not declare plot variants."; return }
    plotVariantManager $mid $gid
}
proc ::GX::plotVariantManager {mid gid} {
    set w .plotvariants
    catch {destroy $w}
    toplevel $w
    wm title $w "Plot variants - [moduleGraphField $mid $gid name $gid]"
    wm transient $w .
    ttk::label $w.h -text "$mid / $gid\nBase is the legacy graph. Each variant has a stable ID, its own configuration and output directory." -justify left
    pack $w.h -anchor w -padx 8 -pady 6
    ttk::treeview $w.tree -columns {id title enabled} -show headings -height 9
    foreach {col label width} {id "Variant ID" 130 title Title 310 enabled Enabled 90} {
        $w.tree heading $col -text $label
        $w.tree column $col -width $width
    }
    pack $w.tree -fill both -expand 1 -padx 8
    ttk::frame $w.actions
    foreach {name label action} {new "New from base" new duplicate Duplicate duplicate edit Edit edit render Render render remove Delete remove} {
        ttk::button $w.actions.$name -text $label -command [list ::GX::plotVariantManagerAction $w $mid $gid $action]
        pack $w.actions.$name -side left -padx 3
    }
    pack $w.actions -anchor w -padx 8 -pady 8
    bind $w.tree <Double-1> [list ::GX::plotVariantManagerAction $w $mid $gid edit]
    plotVariantManagerRefresh $w $mid $gid
}
proc ::GX::plotVariantManagerRefresh {w mid gid} {
    if {![winfo exists $w.tree]} return
    set selected [$w.tree selection]
    foreach item [$w.tree children {}] { $w.tree delete $item }
    foreach vid [plotVariantIds $mid $gid] {
        $w.tree insert {} end -id $vid -values [list $vid [plotVariantField $mid $gid $vid title] [expr {[plotVariantField $mid $gid $vid enabled] ? "Yes" : "No"}]]
    }
    if {[llength $selected] && [$w.tree exists [lindex $selected 0]]} { $w.tree selection set [lindex $selected 0] }
}
proc ::GX::plotVariantManagerAction {w mid gid action} {
    if {![winfo exists $w.tree]} {return}
    if {$action eq "new"} {
        if {[catch {set vid [plotVariantCreate $mid $gid]} err]} { tk_messageBox -parent $w -icon error -message $err; return }
        plotVariantManagerRefresh $w $mid $gid
        $w.tree selection set $vid
        plotVariantEditor $w $mid $gid $vid
        return
    }
    set selected [$w.tree selection]
    if {[llength $selected] != 1} { tk_messageBox -parent $w -message "Select one variant."; return }
    set vid [lindex $selected 0]
    if {$action eq "duplicate"} {
        if {[catch {set next [plotVariantDuplicate $mid $gid $vid]} err]} { tk_messageBox -parent $w -icon error -message $err; return }
        plotVariantManagerRefresh $w $mid $gid
        $w.tree selection set $next
        plotVariantEditor $w $mid $gid $next
    } elseif {$action eq "edit"} {
        plotVariantEditor $w $mid $gid $vid
    } elseif {$action eq "render"} {
        if {[catch {set artifact [plotVariantArtifact $mid $gid $vid]} err]} { tk_messageBox -parent $w -icon error -message $err; return }
        startRerenderPaths [list $artifact]
    } elseif {$action eq "remove"} {
        if {[tk_messageBox -parent $w -type yesno -icon question -message "Delete $vid and its generated artifacts?"] ne "yes"} return
        if {[catch {
            if {$mid eq "plot.dataset"} {
                ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
                ::GX::PlotDatasetAPIv3::deletePlot [dict create module_id $mid graph_id $gid variant_id $vid]
            } else {
                plotVariantDelete $mid $gid $vid
            }
        } err]} { tk_messageBox -parent $w -icon error -message $err; return }
        plotVariantManagerRefresh $w $mid $gid
    }
}
proc ::GX::plotVariantBindingChoices {mid gid vid role} {
    variable ui
    set choices [list ""]
    foreach ds [datasetRegistryIds] {
        foreach v [datasetVariableSchema $ds] {
            set varId [dict get $v variable_id]
            set name [dict get $v canonical]
            set suffix [expr {[dict get $v enabled] ? "" : " (Use=no)"}]
            set display "$ds / $varId — $name$suffix"
            set ui(variantBindingMap,$role,$display) [list $ds $varId]
            lappend choices $display
        }
    }
    set current [plotVariantBindingGet $mid $gid $vid $role]
    set ui(variantBindingChoice,$role) ""
    if {$current ne ""} {
        set pair [list [dict get $current dataset_id] [dict get $current variable_id]]
        foreach display [lrange $choices 1 end] {
            if {$ui(variantBindingMap,$role,$display) eq $pair} {
                set ui(variantBindingChoice,$role) $display
                break
            }
        }
        if {$ui(variantBindingChoice,$role) eq ""} {
            set display "[lindex $pair 0] / [lindex $pair 1] — unavailable until dataset metadata is loaded"
            set ui(variantBindingMap,$role,$display) $pair
            lappend choices $display
            set ui(variantBindingChoice,$role) $display
        }
    }
    return $choices
}
proc ::GX::plotVariantEditor_before_graph_workflow {parent mid gid vid} {
    variable ui
    set dataModel [plotVariantDataModel $mid $gid]
    if {$::GX::currentSession ne ""} { catch {loadDatasetRegistry $::GX::currentSession} }
    set w .plotvariantedit
    catch {destroy $w}
    toplevel $w
    wm title $w "Plot variant $vid - $gid"
    wm transient $w $parent
    set ui(variantTitle) [plotVariantField $mid $gid $vid title]
    set ui(variantEnabled) [plotVariantField $mid $gid $vid enabled]
    ttk::frame $w.header
    ttk::label $w.header.id -text "$mid / $gid / $vid"
    ttk::label $w.header.tl -text Title
    ttk::entry $w.header.title -textvariable ::GX::ui(variantTitle) -width 42
    ttk::checkbutton $w.header.enabled -text Enabled -variable ::GX::ui(variantEnabled)
    pack $w.header.id $w.header.tl $w.header.title $w.header.enabled -side left -padx 4
    pack $w.header -anchor w -padx 8 -pady 8
    ttk::notebook $w.nb
    set tabs [expr {$dataModel eq "module_cache" ? {plot graphics} : {bindings series plot graphics}}]
    foreach tab $tabs { ttk::frame $w.nb.$tab; $w.nb add $w.nb.$tab -text [string totitle $tab] }
    pack $w.nb -fill both -expand 1 -padx 8
    if {$dataModel eq "series"} {
    set row 0
    foreach role [moduleBindingRoles $mid] {
        set choices [plotVariantBindingChoices $mid $gid $vid $role]
        ttk::label $w.nb.bindings.l$row -text $role
        ttk::combobox $w.nb.bindings.c$row -textvariable ::GX::ui(variantBindingChoice,$role) -values $choices -state readonly -width 52
        grid $w.nb.bindings.l$row -row $row -column 0 -sticky w -padx 4 -pady 3
        grid $w.nb.bindings.c$row -row $row -column 1 -sticky ew -padx 4 -pady 3
        incr row
    }
    ttk::label $w.nb.bindings.note -text "Bindings use dataset_id + variable_id. Use=no remains saved; rendering reports unavailable data." -wraplength 520
    grid $w.nb.bindings.note -row $row -column 0 -columnspan 2 -sticky w -padx 4 -pady 6
    }
    set row 0
    foreach field [moduleGraphConfigKeys $mid $gid] {
        set ui(variantConfig,$field) [plotVariantConfigGet $mid $gid $vid $field]
        ttk::label $w.nb.plot.l$row -text [moduleGraphConfigField $mid $gid $field label $field]
        set values [splitList [moduleGraphConfigField $mid $gid $field values ""]]
        if {[llength $values]} {
            ttk::combobox $w.nb.plot.e$row -textvariable ::GX::ui(variantConfig,$field) -values $values -width 32
        } else {
            ttk::entry $w.nb.plot.e$row -textvariable ::GX::ui(variantConfig,$field) -width 34
        }
        grid $w.nb.plot.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
        grid $w.nb.plot.e$row -row $row -column 1 -sticky ew -padx 4 -pady 2
        incr row
    }
    set row 0
    foreach field [moduleGraphicsFields] {
        if {$field eq "background"} continue
        set ui(variantGraphics,$field) [plotVariantGraphicsGet $mid $gid $vid $field]
        ttk::label $w.nb.graphics.l$row -text $field
        ttk::entry $w.nb.graphics.e$row -textvariable ::GX::ui(variantGraphics,$field) -width 24
        grid $w.nb.graphics.l$row -row $row -column 0 -sticky e -padx 4 -pady 1
        grid $w.nb.graphics.e$row -row $row -column 1 -sticky ew -padx 4 -pady 1
        incr row
    }
    if {$dataModel eq "series"} {
        # The shared editor is taller than a notebook tab. Give it the same
        # scrolling host used by the base graph instead of shrinking its table
        # to zero height when the provider adds controls below it.
        set seriesBody [scrollableDialogBody $w.nb.series]
        graphSeriesEditorBuild $seriesBody $mid $gid $vid
    }
    ttk::frame $w.buttons
    ttk::button $w.buttons.save -text Save -command [list ::GX::plotVariantEditorSave $w $parent $mid $gid $vid 0]
    ttk::button $w.buttons.render -text "Save and render" -command [list ::GX::plotVariantEditorSave $w $parent $mid $gid $vid 1]
    ttk::button $w.buttons.close -text Close -command [list destroy $w]
    pack $w.buttons.save $w.buttons.render $w.buttons.close -side left -padx 4
    pack $w.buttons -anchor e -padx 8 -pady 8
}
proc ::GX::plotVariantEditor {parent mid gid vid} {
    tailcall ::GX::plotVariantEditor_before_graph_workflow $parent $mid $gid $vid
}
proc ::GX::plotVariantEditorSave {w parent mid gid vid render} {
    variable ui
    set dataModel [plotVariantDataModel $mid $gid]
    # The embedded Series Editor owns provider state that is staged in its
    # controls. Commit the selected series through the existing extension
    # lifecycle before saving or rendering the outer variant.
    set seriesEditor $w.nb.series.viewport.canvas.body
    if {$dataModel eq "series" && [info exists ::GX::seriesEditorExtensionInstance($seriesEditor)]} {
        set extensionInstance $::GX::seriesEditorExtensionInstance($seriesEditor)
        if {[dict get $extensionInstance series_id] ne "" &&
            ![graphSeriesEditorSave $seriesEditor $mid $gid $vid]} {
            return
        }
    }
    if {[catch {
        plotVariantSet $mid $gid $vid [dict create title [string trim $ui(variantTitle)] enabled $ui(variantEnabled)]
        foreach role [expr {$dataModel eq "series" ? [moduleBindingRoles $mid] : {}}] {
            set display $ui(variantBindingChoice,$role)
            if {$display eq ""} {
                plotVariantBindingSet $mid $gid $vid $role "" ""
            } else {
                lassign $ui(variantBindingMap,$role,$display) ds varId
                set current [plotVariantBindingGet $mid $gid $vid $role]
                if {$current eq "" || [dict get $current dataset_id] ne $ds || [dict get $current variable_id] ne $varId} {
                    plotVariantBindingSet $mid $gid $vid $role $ds $varId
                }
            }
        }
        foreach field [moduleGraphConfigKeys $mid $gid] {
            plotVariantConfigSet $mid $gid $vid $field [string trim $ui(variantConfig,$field)]
        }
        foreach field [moduleGraphicsFields] {
            if {$field eq "background"} continue
            plotVariantGraphicsSet $mid $gid $vid $field [string trim $ui(variantGraphics,$field)]
        }
    } err]} { tk_messageBox -parent $w -icon error -message $err; return }
    plotVariantManagerRefresh $parent $mid $gid
    destroy $w
    if {$render} {
        if {[catch {set artifact [plotVariantArtifact $mid $gid $vid]} err]} {
            tk_messageBox -parent $parent -icon error -message $err
        } else {
            startRerenderPaths [list $artifact]
        }
    }
}
# One editor implementation serves the base graph and every variant.
proc ::GX::graphSeriesEditorBase {mid gid} {
    set w .graphseriesbase
    catch {destroy $w}
    toplevel $w
    wm title $w "Graph Series — $mid/$gid"
    # plot.dataset multi-panel: provider details can exceed notebook-height screens; keep the shared editor usable without hiding controls.
    set editor [scrollableDialogBody $w]
    graphSeriesEditorBuild $editor $mid $gid ""
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.close -anchor e -padx 8 -pady 6
    set sw [winfo screenwidth $w]; set sh [winfo screenheight $w]
    set ww [expr {min(1000,max(700,$sw-80))}]; set hh [expr {min(780,max(460,$sh-120))}]
    catch {wm geometry $w ${ww}x${hh}}; catch {wm minsize $w 650 420}; catch {wm resizable $w 1 1}
}
proc ::GX::graphSeriesEditorBuild {f mid gid vid} {
    variable ui
    set baseColumns {id enabled dataset x y axis label filters}
    set providerColumns {}
    catch {set providerColumns [seriesEditorExtensionTableColumns $mid $gid]}
    set columns $baseColumns
    foreach spec $providerColumns { lappend columns [dict get $spec id] }
    ttk::treeview $f.tree -columns $columns -show headings -height 8
    foreach col $baseColumns {
        $f.tree heading $col -text [string totitle $col]
        $f.tree column $col -width [expr {$col eq "label" ? 140 : 85}]
    }
    foreach spec $providerColumns {
        set col [dict get $spec id]
        $f.tree heading $col -text [dict get $spec heading]
        $f.tree column $col -width [dict get $spec width]
    }
    # plot.dataset multi-panel: many-Series lists must remain scrollable; keep the shared editor provider-neutral.
    ttk::scrollbar $f.treeY -orient vertical -command [list $f.tree yview]
    $f.tree configure -yscrollcommand [list $f.treeY set]
    grid $f.tree -row 0 -column 0 -columnspan 6 -sticky nsew -pady 5
    grid $f.treeY -row 0 -column 6 -sticky ns -pady 5
    grid rowconfigure $f 0 -weight 1
    grid columnconfigure $f 4 -weight 1
    grid columnconfigure $f 5 -weight 1
    set row 1
    set fieldLayout {id 1 0 dataset_id 1 3 x_variable_id 2 0 y_variable_id 2 3 group_variable_id 3 0 category_variable_id 3 3 axis 4 0 label 4 3 filter_variable_id 8 0 ordering_variable_id 9 3}
    foreach {field label values} [list id ID {} dataset_id Dataset [datasetRegistryIds] x_variable_id X {} y_variable_id Y {} group_variable_id {Primary family variable} {} category_variable_id {Secondary parameter variable} {} axis Axis {left right} label Label {} filter_variable_id {Filter variable} {} ordering_variable_id {Order by variable} {}] {
        set ui(seriesEditor,$f,$field) ""
        ttk::label $f.l$field -text $label
        if {[llength $values] || $field in {dataset_id x_variable_id y_variable_id group_variable_id category_variable_id filter_variable_id ordering_variable_id}} {
            ttk::combobox $f.e$field -textvariable ::GX::ui(seriesEditor,$f,$field) -values $values -width [expr {$field eq "dataset_id" ? 42 : 25}]
        } else {
            ttk::entry $f.e$field -textvariable ::GX::ui(seriesEditor,$f,$field) -width 25
        }
        set placement [lsearch -exact $fieldLayout $field]
        set fieldRow [lindex $fieldLayout [expr {$placement+1}]]
        set fieldColumn [lindex $fieldLayout [expr {$placement+2}]]
        grid $f.l$field -row $fieldRow -column $fieldColumn -sticky w -padx 3
        # A wide tree/provider area may stretch the last grid column. Keep
        # selector arrows inside the visible dialog at ordinary screen sizes.
        grid $f.e$field -row $fieldRow -column [expr {$fieldColumn+1}] -columnspan 2 -sticky [expr {$field eq "dataset_id" ? "ew" : "w"}] -padx 3
    }
    set ui(seriesEditor,$f,point_order_mode) {As stored / Sequential}
    ttk::label $f.lpoint_order_mode -text "Point order"
    ttk::combobox $f.epoint_order_mode -textvariable ::GX::ui(seriesEditor,$f,point_order_mode) -values {{As stored / Sequential} {By X ascending} {By variable...}} -state readonly -width 25
    grid $f.lpoint_order_mode -row 8 -column 3 -sticky w -padx 3
    grid $f.epoint_order_mode -row 8 -column 4 -columnspan 2 -sticky w -padx 3
    bind $f.epoint_order_mode <<ComboboxSelected>> [list ::GX::graphSeriesEditorPointOrderChanged $f]
    bind $f.eordering_variable_id <<ComboboxSelected>> [list set ::GX::ui(seriesEditor,$f,point_order_mode) {By variable...}]
    graphSeriesEditorPointOrderChanged $f
    set ui(seriesEditor,$f,family_mode) {All values as separate series}
    set ui(seriesEditor,$f,category_mode) {All values}
    set ui(seriesEditor,$f,category_behavior) Filter
    ttk::label $f.lfamily_mode -text "Family values"
    ttk::combobox $f.efamily_mode -state readonly -textvariable ::GX::ui(seriesEditor,$f,family_mode) -values {{Selected value} {Selected values} {All values as separate series}}
    ttk::label $f.lcategory_behavior -text "Second behavior"
    ttk::combobox $f.ecategory_behavior -state readonly -textvariable ::GX::ui(seriesEditor,$f,category_behavior) -values {Filter {Style category} {Split into series}}
    grid $f.lfamily_mode -row 5 -column 0 -sticky w -padx 3
    grid $f.efamily_mode -row 5 -column 1 -columnspan 2 -sticky ew -padx 3
    grid $f.lcategory_behavior -row 5 -column 3 -sticky w -padx 3
    grid $f.ecategory_behavior -row 5 -column 4 -columnspan 2 -sticky ew -padx 3
    ttk::label $f.lfamily_values -text "Family value(s)"
    ttk::frame $f.family_values_box
    listbox $f.family_values -selectmode extended -exportselection 0 -height 3
    ttk::scrollbar $f.family_valuesY -orient vertical -command [list $f.family_values yview]
    ttk::scrollbar $f.family_valuesX -orient horizontal -command [list $f.family_values xview]
    $f.family_values configure -yscrollcommand [list $f.family_valuesY set]
    $f.family_values configure -xscrollcommand [list $f.family_valuesX set]
    ttk::label $f.lcategory_values -text "Second value(s)"
    ttk::frame $f.category_values_box
    listbox $f.category_values -selectmode extended -exportselection 0 -height 3
    ttk::scrollbar $f.category_valuesY -orient vertical -command [list $f.category_values yview]
    ttk::scrollbar $f.category_valuesX -orient horizontal -command [list $f.category_values xview]
    $f.category_values configure -yscrollcommand [list $f.category_valuesY set]
    $f.category_values configure -xscrollcommand [list $f.category_valuesX set]
    grid $f.lfamily_values -row 6 -column 0 -sticky nw -padx 3
    grid $f.family_values_box -row 6 -column 1 -columnspan 2 -sticky nsew -padx 3
    grid $f.family_values -in $f.family_values_box -row 0 -column 0 -sticky nsew
    grid $f.family_valuesY -in $f.family_values_box -row 0 -column 1 -sticky ns
    grid $f.family_valuesX -in $f.family_values_box -row 1 -column 0 -sticky ew
    grid columnconfigure $f.family_values_box 0 -weight 1
    grid $f.lcategory_values -row 6 -column 3 -sticky nw -padx 3
    grid $f.category_values_box -row 6 -column 4 -columnspan 2 -sticky nsew -padx 3
    grid $f.category_values -in $f.category_values_box -row 0 -column 0 -sticky nsew
    grid $f.category_valuesY -in $f.category_values_box -row 0 -column 1 -sticky ns
    grid $f.category_valuesX -in $f.category_values_box -row 1 -column 0 -sticky ew
    grid columnconfigure $f.category_values_box 0 -weight 1
    ttk::label $f.lcategory_mode -text "Second values"
    ttk::combobox $f.ecategory_mode -state readonly -textvariable ::GX::ui(seriesEditor,$f,category_mode) -values {{Selected value} {Selected values} {All values}}
    grid $f.lcategory_mode -row 7 -column 3 -sticky w -padx 3
    grid $f.ecategory_mode -row 7 -column 4 -columnspan 2 -sticky ew -padx 3
    ttk::label $f.lfilter_values -text "Filter value"
    ttk::frame $f.filter_values_box
    listbox $f.filter_values -selectmode browse -exportselection 0 -height 3
    ttk::scrollbar $f.filter_valuesY -orient vertical -command [list $f.filter_values yview]
    ttk::scrollbar $f.filter_valuesX -orient horizontal -command [list $f.filter_values xview]
    $f.filter_values configure -yscrollcommand [list $f.filter_valuesY set]
    $f.filter_values configure -xscrollcommand [list $f.filter_valuesX set]
    grid $f.lfilter_values -row 9 -column 0 -sticky nw -padx 3
    grid $f.filter_values_box -row 9 -column 1 -columnspan 2 -sticky nsew -padx 3
    grid $f.filter_values -in $f.filter_values_box -row 0 -column 0 -sticky nsew
    grid $f.filter_valuesY -in $f.filter_values_box -row 0 -column 1 -sticky ns
    grid $f.filter_valuesX -in $f.filter_values_box -row 1 -column 0 -sticky ew
    grid columnconfigure $f.filter_values_box 0 -weight 1
    set row 10
    set ui(seriesEditor,$f,enabled) 1
    set ui(seriesEditor,$f,axis) left
    set ui(seriesEditor,$f,dataset_id) [lindex [datasetRegistryIds] 0]
    set ui(seriesEditor,$f,row_filters) {}
    set ui(seriesEditor,$f,value_status) "Choose Family, Second or Filter variable to load its values."
    ttk::checkbutton $f.enabled -text Enabled -variable ::GX::ui(seriesEditor,$f,enabled)
    grid $f.enabled -row $row -column 0 -columnspan 2 -sticky w -padx 3
    ttk::button $f.refresh_values -text "Refresh values" -command [list ::GX::graphSeriesEditorDatasetChanged $f 1]
    ttk::label $f.value_status -textvariable ::GX::ui(seriesEditor,$f,value_status) -wraplength 390
    grid $f.refresh_values -row $row -column 3 -sticky w -padx 3
    grid $f.value_status -row $row -column 4 -columnspan 2 -sticky w -padx 3
    incr row
    # A mouse click on a listed value means the user wants that value. Make
    # the corresponding Selected mode active instead of silently leaving All.
    bind $f.family_values <ButtonRelease-1> [list ::GX::graphSeriesEditorUseClickedValues $f family_values family_mode]
    bind $f.category_values <ButtonRelease-1> [list ::GX::graphSeriesEditorUseClickedValues $f category_values category_mode]
    foreach {widget field} {family_values group_variable_id category_values category_variable_id filter_values filter_variable_id} {
        bind $f.$widget <ButtonPress-1> [list ::GX::graphSeriesEditorEnsureValues $f $widget $field]
    }
    bind $f.edataset_id <ButtonPress-1> [list ::GX::graphSeriesEditorDatasetChoices $f]
    bind $f.edataset_id <<ComboboxSelected>> [list ::GX::graphSeriesEditorDatasetChanged $f]
    bind $f.egroup_variable_id <<ComboboxSelected>> [list ::GX::graphSeriesEditorValueChoices $f]
    bind $f.ecategory_variable_id <<ComboboxSelected>> [list ::GX::graphSeriesEditorValueChoices $f]
    bind $f.efilter_variable_id <<ComboboxSelected>> [list ::GX::graphSeriesEditorValueChoices $f]
    # These comboboxes are editable. Typing a Dataset/variable name does not
    # produce <<ComboboxSelected>>, so refresh after keyboard input as well.
    foreach field {dataset_id group_variable_id category_variable_id filter_variable_id} {
        bind $f.e$field <KeyRelease> [list ::GX::graphSeriesEditorScheduleChoices $f $field]
        bind $f.e$field <FocusOut> [list ::GX::graphSeriesEditorScheduleChoices $f $field]
        # Clipboard and X11 middle-click paste change the textvariable without
        # reliably producing KeyRelease or FocusOut in the focused combobox.
        set variableName ::GX::ui(seriesEditor,$f,$field)
        set callback [list ::GX::graphSeriesEditorTracedChoice $f $field]
        catch {trace remove variable $variableName write $callback}
        trace add variable $variableName write $callback
    }
    bind $f.tree <<TreeviewSelect>> [list ::GX::graphSeriesEditorLoad $f $mid $gid $vid]
    graphSeriesEditorDatasetChanged $f
    ttk::button $f.save -text "Add/update one series" -command [list ::GX::graphSeriesEditorSave $f $mid $gid $vid]
    ttk::button $f.expand -text "Create family series" -command [list ::GX::graphSeriesEditorExpandFamily $f $mid $gid $vid]
    ttk::button $f.remove -text "Remove selected series" -command [list ::GX::graphSeriesEditorRemove $f $mid $gid $vid]
    ttk::button $f.up -text Up -command [list ::GX::graphSeriesEditorMove $f $mid $gid $vid -1]
    ttk::button $f.down -text Down -command [list ::GX::graphSeriesEditorMove $f $mid $gid $vid 1]
    grid $f.save -row $row -column 0 -sticky w -pady 5
    grid $f.expand -row $row -column 1 -sticky w -pady 5
    grid $f.remove -row $row -column 3 -sticky w -pady 5
    grid $f.up -row $row -column 4 -sticky w -pady 5
    grid $f.down -row $row -column 5 -sticky w -pady 5
    ttk::label $f.note -text "Add/update one series stores the secondary parameter as metadata. To apply Second behavior, choose its values and click Create family series. That action creates independent curves after filtering; Ordering sorts points within each curve." -wraplength 850
    grid $f.note -row [expr {$row+1}] -column 0 -columnspan 6 -sticky w
    # Keep the primary action beside the selectors. Provider details can be
    # several screens tall and must not push family creation out of view.
    seriesEditorExtensionBuild $f $mid $gid $vid [expr {$row+2}]
    graphSeriesEditorRefresh $f $mid $gid $vid
}
proc ::GX::graphSeriesEditorRefresh {f mid gid vid} {
    foreach item [$f.tree children {}] { $f.tree delete $item }
    set seriesIds [graphSeriesIds $mid $gid $vid]
    set batchReady 0
    if {![catch {set definition [seriesEditorExtensionFor $mid $gid]}] &&
        $definition ne "" && [dict get $definition table_values_batch_proc] ne "" &&
        ![catch {set batchValues [seriesEditorExtensionTableValuesBatch $mid $gid $vid $seriesIds]}]} {
        set batchReady 1
    }
    foreach sid $seriesIds {
        set d $::GX::graphSeries([graphSeriesKey $mid $gid $sid $vid])
        set count [expr {[dict exists $d row_filters] ? [llength [dict get $d row_filters]] : 0}]
        set values [list $sid [dict get $d enabled] [dict get $d dataset_id] [dict get $d x_variable_id] [dict get $d y_variable_id] [dict get $d axis] [dict get $d label] $count]
        if {$batchReady} {
            set extra [expr {[dict exists $batchValues $sid] ? [dict get $batchValues $sid] : [dict create]}]
            set extraOk 1
        } else {
            set extraOk [expr {![catch {set extra [seriesEditorExtensionTableValues $mid $gid $vid $sid [graphSeriesSnapshot $mid $gid $sid $vid]]}]}]
        }
        if {$extraOk} {
            foreach spec [seriesEditorExtensionTableColumns $mid $gid] {
                set cid [dict get $spec id]
                lappend values [expr {[dict exists $extra $cid] ? [dict get $extra $cid] : ""}]
            }
        } else {
            foreach spec [seriesEditorExtensionTableColumns $mid $gid] { lappend values "" }
        }
        $f.tree insert {} end -id $sid -values $values
    }
}
proc ::GX::graphSeriesEditorDatasetChanged {f {refresh 0}} {
    variable ui
    graphSeriesEditorDatasetChoices $f
    set ds [string trim $ui(seriesEditor,$f,dataset_id)]
    set datasets [datasetRegistryIds]
    if {$ds eq "" && [llength $datasets] == 1} {
        set ds [lindex $datasets 0]
        set ui(seriesEditor,$f,dataset_id) $ds
    }
    set choices {}
    if {$ds ne "" && [datasetField $ds id ""] ne ""} {
        foreach v [datasetVariableSchema $ds] {
            set item "[dict get $v variable_id] — [dict get $v canonical]"
            if {![dict get $v enabled]} { append item " (Use=no)" }
            lappend choices $item
        }
    }
    foreach field {x_variable_id y_variable_id group_variable_id category_variable_id filter_variable_id ordering_variable_id} { $f.e$field configure -values $choices }
    graphSeriesEditorValueChoices $f $refresh
}
proc ::GX::graphSeriesEditorDatasetChoices {f} {
    $f.edataset_id configure -values [datasetRegistryIds]
}
proc ::GX::graphSeriesEditorEnsureValues {f widget field} {
    variable ui
    if {[$f.$widget size] == 0 && [string trim $ui(seriesEditor,$f,$field)] ne ""} {
        graphSeriesEditorDatasetChanged $f
    }
}
proc ::GX::graphSeriesEditorScheduleChoices {f field} {
    variable ui
    if {[info exists ui(seriesEditor,$f,loading)] && $ui(seriesEditor,$f,loading)} {return}
    if {[info exists ui(seriesEditor,$f,choices_after)] && $ui(seriesEditor,$f,choices_after) ne ""} {
        after cancel $ui(seriesEditor,$f,choices_after)
    }
    set ui(seriesEditor,$f,choices_after) [after 120 [list ::GX::graphSeriesEditorRefreshTypedChoices $f $field]]
}
proc ::GX::graphSeriesEditorTracedChoice {f field args} {
    variable ui
    if {[winfo exists $f] && (![info exists ui(seriesEditor,$f,loading)] || !$ui(seriesEditor,$f,loading))} {graphSeriesEditorScheduleChoices $f $field}
}
proc ::GX::graphSeriesEditorRefreshTypedChoices {f field} {
    variable ui
    catch {unset ui(seriesEditor,$f,choices_after)}
    if {![winfo exists $f]} {return}
    if {$field eq "dataset_id"} {
        graphSeriesEditorDatasetChanged $f
    } else {
        graphSeriesEditorValueChoices $f
    }
}
proc ::GX::graphSeriesEditorVariableId {datasetId selected} {
    set selected [string trim $selected]
    if {$datasetId eq "" || $selected eq "" || [datasetField $datasetId id ""] eq ""} {return ""}
    foreach variable [datasetVariableSchema $datasetId] {
        set id [dict get $variable variable_id]
        set name [dict get $variable canonical]
        if {$selected eq $id || $selected eq $name ||
            $selected eq "$id — $name" || $selected eq "$id — $name (Use=no)"} {
            return $id
        }
    }
    return ""
}
proc ::GX::graphSeriesEditorCheckedVariableId {datasetId selected label {required 0}} {
    set selected [string trim $selected]
    if {$selected eq ""} {
        if {$required} {error "Choose a $label variable."}
        return ""
    }
    set id [graphSeriesEditorVariableId $datasetId $selected]
    if {$id eq ""} {
        error "Unknown $label variable '$selected' for Dataset '$datasetId'. Choose a listed variable or type its exact canonical name."
    }
    return $id
}
proc ::GX::graphSeriesEditorValueChoices {f {refresh 0}} {
    variable ui
    set ds [string trim $ui(seriesEditor,$f,dataset_id)]
    set counts {}
    set problems {}
    foreach {field widget label} {group_variable_id family_values Family category_variable_id category_values Second filter_variable_id filter_values Filter} {
        set previous {}
        foreach index [$f.$widget curselection] {lappend previous [$f.$widget get $index]}
        $f.$widget delete 0 end
        set selected [string trim $ui(seriesEditor,$f,$field)]
        if {$selected eq ""} {continue}
        set id [graphSeriesEditorVariableId $ds $ui(seriesEditor,$f,$field)]
        if {$id eq ""} {
            lappend problems "Unknown $label variable '$selected'. Choose a listed variable or type its exact canonical name."
            continue
        }
        if {[catch {
            set values [graphSeriesDistinctValues $ds $id 4096 $refresh]
            set dtype [dict get [datasetVariableV3ById $ds $id] dtype]
        } reason]} {
            lappend problems "Could not load $label values: $reason"
            continue
        }
        if {![llength $values]} {
            lappend problems "$label variable '$selected' has no usable values in Dataset '$ds'. Inspect Dataset preview/schema and reimport the original CSV if its values are missing."
            continue
        }
        foreach value $values {$f.$widget insert end $value}
        lappend counts "$label [llength $values] ($dtype)"
        foreach value $previous {
            set index [lsearch -exact $values $value]
            if {$index >= 0} {$f.$widget selection set $index}
        }
    }
    if {[llength $problems]} {
        set ui(seriesEditor,$f,value_status) [join $problems " "]
    } elseif {[llength $counts]} {
        set ui(seriesEditor,$f,value_status) "Values loaded: [join $counts {, }]."
    } elseif {$ds eq ""} {
        set ui(seriesEditor,$f,value_status) "Choose a Dataset to list its values."
    } else {
        set ui(seriesEditor,$f,value_status) "Choose Family, Second or Filter variable to load its values."
    }
}
proc ::GX::graphSeriesEditorSelectedValues {f widget mode} {
    set all [$f.$widget get 0 end]
    if {$mode in {{All values} {All values as separate series}}} {return $all}
    set values {}
    foreach index [$f.$widget curselection] {lappend values [$f.$widget get $index]}
    if {$mode eq "Selected value" && [llength $values] != 1} {error "Choose exactly one value in $widget."}
    if {$mode eq "Selected values" && ![llength $values]} {error "Choose one or more values in $widget."}
    return $values
}
proc ::GX::graphSeriesEditorUseClickedValues {f widget modeField} {
    variable ui
    set count [llength [$f.$widget curselection]]
    if {$count == 1} {
        set ui(seriesEditor,$f,$modeField) {Selected value}
    } elseif {$count > 1} {
        set ui(seriesEditor,$f,$modeField) {Selected values}
    }
}
proc ::GX::graphSeriesEditorFilterChoice {f} {
    variable ui
    set ds [string trim $ui(seriesEditor,$f,dataset_id)]
    set variableId [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,filter_variable_id) Filter]
    set indices [$f.filter_values curselection]
    if {$variableId eq ""} {return {}}
    if {[llength $indices] != 1} {error "Choose one filter value for $variableId."}
    set value [$f.filter_values get [lindex $indices 0]]
    return [list [dict create filter_variable_id $variableId predicate exact_equal value $value]]
}
proc ::GX::graphSeriesEditorEnsurePrimarySource {moduleId datasetId} {
    # A newly configured Plot Dataset series already identifies its Dataset.
    # Use it as the required primary Analysis Source when that source is empty,
    # so the normal Run action can render the graph just created in this editor.
    if {$moduleId ne "plot.dataset" || $datasetId eq ""} {return}
    set row [analysisSourceFindRow $moduleId primary]
    if {$row && [analysisSourceRowDataset $moduleId $row] eq ""} {
        set ::GX::moduleAnalysisSource($moduleId,$row,dataset_id) $datasetId
    }
}
proc ::GX::graphSeriesEditorExpandFamily {f mid gid vid} {
    variable ui
    if {[catch {
        set ds [string trim $ui(seriesEditor,$f,dataset_id)]
        set xid [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,x_variable_id) X 1]
        set yid [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,y_variable_id) Y 1]
        set group [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,group_variable_id) {Primary family} 1]
        set category [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,category_variable_id) {Secondary parameter}]
        set prefix [string trim $ui(seriesEditor,$f,id)]
        if {$prefix eq ""} {set prefix family}
        regsub -all {[^A-Za-z0-9_.-]} $prefix _ prefix
        if {![regexp {^[A-Za-z_]} $prefix]} {set prefix "family_$prefix"}
        set suffix 1
        set base $prefix
        while {[llength [lsearch -all -glob [graphSeriesIds $mid $gid $vid] "${prefix}_*"]]} {
            set prefix "${base}_[incr suffix]"
        }
        set caption [string trim $ui(seriesEditor,$f,label)]
        if {$caption eq ""} {set caption [lindex $ui(seriesEditor,$f,group_variable_id) end]}
        set familyValues [graphSeriesEditorSelectedValues $f family_values $ui(seriesEditor,$f,family_mode)]
        if {$ui(seriesEditor,$f,family_mode) eq "All values as separate series"} {set familyValues {}}
        set categoryValues {}
        if {$category ne ""} {set categoryValues [graphSeriesEditorSelectedValues $f category_values $ui(seriesEditor,$f,category_mode)]}
        if {$ui(seriesEditor,$f,category_mode) eq "All values" && $ui(seriesEditor,$f,category_behavior) eq "Filter"} {set categoryValues {}}
        set behavior $ui(seriesEditor,$f,category_behavior)
        set template "$caption: {member}"
        if {$category ne "" && $behavior ne "Filter"} {append template " · {category}"}
        set ordering [graphSeriesEditorOrderingId $f $ds $xid]
        set options [dict create series_prefix $prefix label_template $template category_variable_id $category family_values $familyValues category_values $categoryValues category_behavior $behavior row_filters [graphSeriesEditorFilterChoice $f] ordering_variable_id $ordering]
        set created [graphSeriesExpandGroups $mid $gid $ds $xid $yid $group $options $vid]
        graphSeriesEditorEnsurePrimarySource $mid $ds
        graphSeriesEditorRefresh $f $mid $gid $vid
        set ui(seriesEditor,$f,id) ""
    } err]} {tk_messageBox -parent [winfo toplevel $f] -icon error -message $err}
}
proc ::GX::graphSeriesEditorPointOrderChanged {f} {
    variable ui
    if {![winfo exists $f.eordering_variable_id]} return
    $f.eordering_variable_id configure -state [expr {$ui(seriesEditor,$f,point_order_mode) eq {By variable...} ? "normal" : "disabled"}]
}
proc ::GX::graphSeriesEditorOrderingId {f datasetId xId} {
    variable ui
    switch -- $ui(seriesEditor,$f,point_order_mode) {
        {As stored / Sequential} {return ""}
        {By X ascending} {return $xId}
        {By variable...} {return [graphSeriesEditorCheckedVariableId $datasetId $ui(seriesEditor,$f,ordering_variable_id) Ordering 1]}
        default {error "Unknown point-order mode: $ui(seriesEditor,$f,point_order_mode)"}
    }
}
proc ::GX::graphSeriesEditorLoad {f mid gid vid} {
    variable ui
    set selected [$f.tree selection]
    if {[llength $selected] != 1} return
    set sid [lindex $selected 0]
    set d $::GX::graphSeries([graphSeriesKey $mid $gid $sid $vid])
    if {[info exists ui(seriesEditor,$f,choices_after)] && $ui(seriesEditor,$f,choices_after) ne ""} {
        after cancel $ui(seriesEditor,$f,choices_after)
        unset ui(seriesEditor,$f,choices_after)
    }
    set ui(seriesEditor,$f,loading) 1
    set ui(seriesEditor,$f,id) $sid
    foreach field {dataset_id x_variable_id y_variable_id axis label enabled} {
        set ui(seriesEditor,$f,$field) [dict get $d $field]
    }
    set ui(seriesEditor,$f,row_filters) [expr {[dict exists $d row_filters] ? [dict get $d row_filters] : {}}]
    foreach {uiField dataField} {group_variable_id family_variable_id category_variable_id secondary_variable_id ordering_variable_id ordering_variable_id} {
        set ui(seriesEditor,$f,$uiField) [expr {[dict exists $d $dataField] ? [dict get $d $dataField] : ""}]
    }
    set orderId $ui(seriesEditor,$f,ordering_variable_id)
    set ui(seriesEditor,$f,point_order_mode) [expr {$orderId eq "" ? {As stored / Sequential} : ($orderId eq $ui(seriesEditor,$f,x_variable_id) ? {By X ascending} : {By variable...})}]
    graphSeriesEditorPointOrderChanged $f
    set ui(seriesEditor,$f,filter_variable_id) ""
    set filters $ui(seriesEditor,$f,row_filters)
    foreach filter $filters {
        set id [dict get $filter filter_variable_id]
        if {$id eq $ui(seriesEditor,$f,group_variable_id) || $id eq $ui(seriesEditor,$f,category_variable_id)} continue
        if {[dict get $filter predicate] ne "exact_equal"} continue
        set ui(seriesEditor,$f,filter_variable_id) $id
        break
    }
    set ui(seriesEditor,$f,loading) 0
    graphSeriesEditorDatasetChanged $f
    foreach filter $filters {
        if {[dict get $filter filter_variable_id] ne $ui(seriesEditor,$f,filter_variable_id)} continue
        if {[dict get $filter predicate] ne "exact_equal"} continue
        set index [lsearch -exact [$f.filter_values get 0 end] [dict get $filter value]]
        if {$index >= 0} {$f.filter_values selection set $index}
        break
    }
    seriesEditorExtensionLoad $f $sid [graphSeriesSnapshot $mid $gid $sid $vid]
}
proc ::GX::graphSeriesEditorSave {f mid gid vid} {
    variable ui
    if {[catch {
        set sid [string trim $ui(seriesEditor,$f,id)]
        set ds [string trim $ui(seriesEditor,$f,dataset_id)]
        set xid [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,x_variable_id) X 1]
        set yid [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,y_variable_id) Y 1]
        set filters $ui(seriesEditor,$f,row_filters)
        set filterId [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,filter_variable_id) Filter]
        if {$filterId ne "" && [llength [$f.filter_values curselection]]} {
            set kept {}
            foreach item $filters {if {[dict get $item filter_variable_id] ne $filterId} {lappend kept $item}}
            set filters [concat $kept [graphSeriesEditorFilterChoice $f]]
        }
        set ordering [graphSeriesEditorOrderingId $f $ds $xid]
        set fields [dict create dataset_id $ds x_variable_id $xid y_variable_id $yid family_variable_id [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,group_variable_id) {Primary family}] secondary_variable_id [graphSeriesEditorCheckedVariableId $ds $ui(seriesEditor,$f,category_variable_id) {Secondary parameter}] ordering_variable_id $ordering axis [string trim $ui(seriesEditor,$f,axis)] label [string trim $ui(seriesEditor,$f,label)] enabled $ui(seriesEditor,$f,enabled) row_filters $filters]
        # Validate both layers before either is committed. Provider validation
        # receives the normalized proposed generic snapshot.
        set normalized [graphSeriesValidate $mid $gid $sid $fields $vid]
        set proposed [dict merge $normalized [dict create module_id $mid graph_id $gid variant_id $vid series_id $sid]]
        set prepared [seriesEditorExtensionPrepareSave $f $sid $proposed]
        set priorExists 0
        set priorFields {}
        if {$sid in [graphSeriesIds $mid $gid $vid]} {
            set priorExists 1
            set priorFields [graphSeriesSnapshot $mid $gid $sid $vid]
            foreach identity {module_id graph_id variant_id series_id} { dict unset priorFields $identity }
        }
        graphSeriesSet $mid $gid $sid $normalized $vid
        if {[catch {
            seriesEditorExtensionCommitSave $f $sid [graphSeriesSnapshot $mid $gid $sid $vid] $prepared
        } providerError providerOptions]} {
            if {$priorExists} {
                graphSeriesSet $mid $gid $sid $priorFields $vid
            } else {
                graphSeriesRemove $mid $gid $sid $vid
            }
            return -options $providerOptions $providerError
        }
        graphSeriesEditorEnsurePrimarySource $mid [dict get $normalized dataset_id]
    } err]} { tk_messageBox -parent [winfo toplevel $f] -icon error -message $err; return 0 }
    graphSeriesEditorRefresh $f $mid $gid $vid
    $f.tree selection set $sid
    seriesEditorExtensionLoad $f $sid [graphSeriesSnapshot $mid $gid $sid $vid]
    catch {refreshManifestPreview}
    return 1
}
proc ::GX::graphSeriesEditorRemove {f mid gid vid} {
    set selected [$f.tree selection]
    if {[llength $selected] != 1} return
    graphSeriesRemove $mid $gid [lindex $selected 0] $vid
    graphSeriesEditorRefresh $f $mid $gid $vid
    seriesEditorExtensionLoad $f "" {}
    catch {refreshManifestPreview}
}
proc ::GX::graphSeriesEditorMove {f mid gid vid delta} {
    set selected [$f.tree selection]
    if {[llength $selected] != 1} return
    set sid [lindex $selected 0]
    graphSeriesMove $mid $gid $sid $delta $vid
    graphSeriesEditorRefresh $f $mid $gid $vid
    $f.tree selection set $sid
    seriesEditorExtensionLoad $f $sid [graphSeriesSnapshot $mid $gid $sid $vid]
    catch {refreshManifestPreview}
}
# Compatibility entry points for earlier variant editor callers.
proc ::GX::plotVariantSeriesEditorBuild {f mid gid vid} { graphSeriesEditorBuild $f $mid $gid $vid }
proc ::GX::plotVariantSeriesEditorRefresh {f mid gid vid} { graphSeriesEditorRefresh $f $mid $gid $vid }
proc ::GX::plotVariantSeriesDatasetChanged {f} { graphSeriesEditorDatasetChanged $f }
proc ::GX::plotVariantSeriesEditorLoad {f mid gid vid} { graphSeriesEditorLoad $f $mid $gid $vid }
proc ::GX::plotVariantSeriesEditorSave {f mid gid vid} { graphSeriesEditorSave $f $mid $gid $vid }
proc ::GX::plotVariantSeriesEditorRemove {f mid gid vid} { graphSeriesEditorRemove $f $mid $gid $vid }
