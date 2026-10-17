# SPDX-License-Identifier: GPL-3.0-or-later
# Renderer selection is metadata on the existing canonical Graph resource.
proc ::GX::graphRendererOwner {reference} {
    set reference [graphResourceRef $reference]
    set metadata [graphMetadataRead $reference]
    set owner [datasetPublicationV2DictDefault $metadata renderer_owner legacy]
    if {$owner eq {}} {set owner legacy}
    if {$owner eq {legacy}} {return legacy}
    if {$owner ne {PLOT_DATASET_API_v4} || [datasetPublicationV2DictDefault $metadata renderer_owner_api_version 0] ne {1}} {error {Unsupported or invalid Graph renderer ownership metadata}}
    if {[dict get $reference kind] eq {provider} && [dict get $reference module_id] ne {plot.dataset}} {error {Native Plot renderer ownership requires the canonical Plot Dataset provider}}
    return $owner
}
proc ::GX::graphRendererOwnerForPath {path} {
    # Historical non-provider artifacts retain their established rerender path.
    if {[catch {set reference [graphResourceRefForPath $path]}]} {return legacy}
    return [graphRendererOwner $reference]
}
proc ::GX::graphNativeRendererRequire {} {
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
}
proc ::GX::graphRendererQueueCommand {reference} {
    variable scriptDir;variable currentSession
    set reference [graphResourceRef $reference]
    if {[graphRendererOwner $reference] ne {PLOT_DATASET_API_v4}} {error {Graph has no native renderer owner}}
    graphNativeRendererRequire
    set worker [file join $scriptDir core tcl graph_renderer_worker.tcl]
    return [list {Native Plot Dataset render} [list [auto_execok tclsh] $worker $scriptDir $currentSession $reference]]
}
proc ::GX::graphRendererSnapshotCopy {source target} {
    graphNativeRendererRequire
    return [::GX::PlotDatasetAPIv4::snapshotCopy $source $target]
}
proc ::GX::graphRendererSnapshotRender {directory graph} {
    graphNativeRendererRequire
    return [::GX::PlotDatasetAPIv4::renderSnapshot $directory $graph]
}

# Read the existing graphics, Variant, Axes and Legend authorities.  The
# additional presentation dictionary is an ephemeral renderer projection,
# never a second configuration store or a mutation of the saved PlotSpec.
proc ::GX::graphRendererEffectiveSpec {reference spec} {
    variable cfg; variable moduleGraphicsOverride; variable modulePlotCfg
    variable axisOverride; variable legendOverride; variable levelScale
    set reference [graphResourceRef $reference]
    if {[dict get $reference kind] eq {clone}} {return $spec}
    set mid [dict get $reference module_id];set gid [dict get $reference graph_id]
    set vid [dict get $reference variant_id];set key [graphAxisAddress $mid $gid $vid]
    set supplied [datasetPublicationV2DictDefault $spec native_presentation {}]
    set suppliedGraphics [datasetPublicationV2DictDefault $supplied graphics {}]
    set variantGraphics {}
    set graphics [dict create]
    foreach field [moduleGraphicsFields] {
        set config plot_$field
        switch -- $field {
            dpi {set config analysis_png_dpi}
            legend_placement {set config plot_legend_mode}
            legend_inside_preset {set config plot_legend_location}
            legend_margin_px {set config plot_legend_external_margin_px}
            view_azimuth {set config plot_3d_azimuth}
            view_elevation {set config plot_3d_elevation}
            projection - aspect_mode - aspect_ratio {set config plot_3d_$field}
        }
        if {[info exists cfg($config)]} {dict set graphics $field $cfg($config)}
        if {[info exists moduleGraphicsOverride($mid,enabled)] && $moduleGraphicsOverride($mid,enabled) &&
            [info exists moduleGraphicsOverride($mid,$field)] && $moduleGraphicsOverride($mid,$field) ni {{} inherit}} {
            dict set graphics $field $moduleGraphicsOverride($mid,$field)
        }
        if {[dict exists $suppliedGraphics $field]} {dict set graphics $field [dict get $suppliedGraphics $field]}
        if {$vid ne {}} {
            set value [plotVariantGraphicsGet $mid $gid $vid $field]
            if {$value ni {{} inherit}} {dict set graphics $field $value;dict set variantGraphics $field $value}
        }
    }
    set axes [datasetPublicationV2DictDefault $supplied axes {}]
    set layout {}
    foreach {field config} {layout_margin_left plot_stacked_margin_left_pct layout_margin_right plot_stacked_margin_right_pct layout_margin_top plot_stacked_margin_top_pct layout_margin_bottom plot_stacked_margin_bottom_pct layout_gap plot_stacked_gap_pct} {
        if {[info exists cfg($config)]} {dict set layout $field $cfg($config)}
    }
    set layout [dict merge $layout [datasetPublicationV2DictDefault $supplied layout {}]]
    foreach name [array names axisOverride "$key,*"] {
        set field [string range $name [expr {[string length $key]+1}] end]
        if {[string first , $field]>=0} continue
        set value $axisOverride($name)
        if {[string match layout_* $field]} {dict set layout $field $value;continue}
        if {$value ni {{} inherit}} {dict set axes $field $value}
    }
    if {[dict exists $axes enabled] && ![dict get $axes enabled]} {set axes [dict create]}
    foreach field {background view_azimuth view_elevation projection aspect_mode aspect_ratio colormap colorbar_visible colorbar_label color_unit color_min color_max} {
        if {[dict exists $axes $field]} {dict set graphics $field [dict get $axes $field]}
    }
    set legend [dict create]
    foreach {source target} {legend_placement placement legend_inside_preset inside_preset legend_layout layout legend_alignment alignment legend_columns columns legend_font_unit font_unit legend_font_size font_size legend_background background legend_border border legend_border_color border_color legend_margin_px margin_px} {
        if {[dict exists $graphics $source]} {dict set legend $target [dict get $graphics $source]}
    }
    set legend [dict merge $legend [datasetPublicationV2DictDefault $supplied legend {}]]
    foreach field {manual_x manual_y} {if {[info exists cfg(plot_legend_$field)] && ![dict exists $legend $field]} {dict set legend $field $cfg(plot_legend_$field)}}
    foreach {source target} {legend_placement placement legend_inside_preset inside_preset legend_layout layout legend_alignment alignment legend_columns columns legend_font_unit font_unit legend_font_size font_size legend_background background legend_border border legend_border_color border_color legend_margin_px margin_px} {
        if {[dict exists $variantGraphics $source]} {dict set legend $target [dict get $variantGraphics $source]}
    }
    if {[info exists legendOverride($key,enabled)] && $legendOverride($key,enabled)} {
        foreach {source target} {mode placement placement placement location inside_preset alignment alignment columns columns font_unit font_unit font_size font_size background background border border border_color border_color external_margin_px margin_px manual_x manual_x manual_y manual_y} {
            if {[info exists legendOverride($key,$source)] && $legendOverride($key,$source) ni {{} inherit}} {dict set legend $target $legendOverride($key,$source)}
        }
        if {[info exists legendOverride($key,layout)] && $legendOverride($key,layout) ni {{} inherit}} {
            dict set legend layout $legendOverride($key,layout)
        } elseif {[info exists legendOverride($key,orientation)]} {
            switch -- $legendOverride($key,orientation) {horizontal {dict set legend layout row} vertical {dict set legend layout stacked}}
        }
    }
    if {[dict exists $legend placement] && [dict get $legend placement] in {below above left right} &&
        ![info exists legendOverride($key,border)] && [info exists cfg(plot_legend_external_border)]} {
        dict set legend border $cfg(plot_legend_external_border)
    }
    if {![dict exists $legend font_unit] || [dict get $legend font_unit] in {{} inherit}} {
        dict set legend font_unit [datasetPublicationV2DictDefault $graphics font_unit px]
    }
    foreach axis {y y2 z} {
        if {[info exists levelScale($key,$axis)] || ![dict exists $axes ${axis}_level_scale]} {dict set axes ${axis}_level_scale [levelScaleGet $key $axis]}
    }
    set fields [moduleGraphConfigKeys $mid $gid]
    set plotConfig [datasetPublicationV2DictDefault $supplied plot_config {}]
    foreach field {plot_style point_order marker_size line_width legend_content plot_type contour_levels reduction_mode target_points family_label_prefix extra_format} {
        if {$field ni $fields} continue
        set value {}
        if {$vid ne {}} {set value [plotVariantConfigGet $mid $gid $vid $field]} elseif {[info exists modulePlotCfg($mid,$gid,$field)]} {set value $modulePlotCfg($mid,$gid,$field)}
        if {$value ni {{} auto inherit}} {dict set plotConfig $field $value}
    }
    foreach field {title x_label y_label y2_label z_label} {
        set value {}
        if {$field in $fields} {
            if {$vid ne {}} {set value [plotVariantConfigGet $mid $gid $vid $field]} elseif {[info exists modulePlotCfg($mid,$gid,$field)]} {set value $modulePlotCfg($mid,$gid,$field)}
        }
        if {$value in {{} auto inherit} && [dict exists $axes $field]} {set value [dict get $axes $field]}
        if {$value ni {{} auto inherit}} {dict set axes $field $value}
    }
    if {[dict exists $axes title]} {dict set spec title [dict get $axes title]}
    set projected {};set panelOverrides [dict create];set index 0
    if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {
        foreach prefix {x y z} {
            foreach {suffix target} {label label unit display_unit scale scale min min max max step major_step} {
                if {[dict exists $axes ${prefix}_$suffix]} {dict set spec axes $prefix $target [dict get $axes ${prefix}_$suffix]}
            }
        }
    }
    foreach panel [datasetPublicationV2DictDefault $spec panels {}] {
        incr index;set id [dict get $panel id]
        set overrides [dict merge $axes [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault $supplied panels {}] $id {}]]
        foreach panelKey [list $index $id] {
            foreach name [array names axisOverride "$key,$panelKey,*"] {
                set field [string range $name [expr {[string length "$key,$panelKey"]+1}] end]
                if {$axisOverride($name) ni {{} inherit}} {dict set overrides $field $axisOverride($name)}
            }
        }
        dict set panelOverrides $id $overrides
        foreach {prefix axis} {x x y y_left y2 y_right z z} {
            foreach {suffix target} {label label unit display_unit scale scale min min max max step major_step} {
                if {[dict exists $overrides ${prefix}_$suffix]} {
                    dict set panel axes $axis $target [dict get $overrides ${prefix}_$suffix]
                }
            }
        }
        lappend projected $panel
    }
    if {[dict exists $spec panels]} {dict set spec panels $projected}
    dict set spec native_presentation [dict create schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1 graphics $graphics legend $legend axes $axes panels $panelOverrides layout $layout plot_config $plotConfig]
    return $spec
}
