#!/usr/bin/env tclsh
# Replicate Curve Analysis v15.2 -> Plot Dataset v3 backend bridge.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The producer-visible graph remains curve.replicate_analysis. Rendering is
# delegated to plot.dataset. Presentation state from the producer graph is
# projected into the private backend Variant before the public renderCommand
# is built, so CORE serializes the normal plot.dataset runtime itself.

fconfigure stdout -buffering none -translation lf -encoding utf-8

proc fail {message} {
    catch {puts stderr "curve.replicate_analysis graphics bridge: $message"; flush stderr}
    catch {puts "ERROR\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $message]]"; flush stdout}
    exit 2
}
proc enc {value} { return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]] }
proc rv {d section field {default ""}} {
    set k "$section.$field"
    return [expr {[dict exists $d $k] ? [dict get $d $k] : $default}]
}
proc bool {v {default 0}} {
    set s [string tolower [string trim $v]]
    if {$s in {1 true yes on}} {return 1}
    if {$s in {0 false no off}} {return 0}
    return $default
}
proc numOrEmpty {v} {
    set v [string trim $v]
    if {$v eq "" || ![string is double -strict $v]} {return ""}
    return $v
}
proc listSemi {s} {
    set s [string map {, ;} $s]
    set out {}
    foreach v [split $s ";"] {set v [string trim $v]; if {$v ne ""} {lappend out $v}}
    return $out
}
proc styleMerge {base override} {
    set out $base
    dict for {k v} $override {
        set v [string trim $v]
        if {$v eq "" || $v eq "inherit"} continue
        dict set out $k $v
    }
    return $out
}

# Read family membership only through the framework Table Stream API.
# No Dataset path or CSV representation is opened by this plugin.
proc datasetFamilyMembers {datasetId familyVariableId {labelVariableId ""}} {
    if {$::GX::currentSession eq ""} {error "No Session is open while expanding family members"}
    ::GX::datasetVariableV3ById $datasetId $familyVariableId
    set variableIds [list $familyVariableId]
    if {$labelVariableId ne "" && $labelVariableId ne $familyVariableId} {
        ::GX::datasetVariableV3ById $datasetId $labelVariableId
        lappend variableIds $labelVariableId
    }
    set stream [::GX::tableStreamOpenDataset $::GX::currentSession $datasetId $variableIds 4096]
    set order {}
    set labels [dict create]
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream]
            set members [dict get $chunk values $familyVariableId]
            if {$labelVariableId ne "" && $labelVariableId ne $familyVariableId} {
                set labelValues [dict get $chunk values $labelVariableId]
            } else {
                set labelValues $members
            }
            set count [dict get $chunk nrows]
            for {set i 0} {$i < $count} {incr i} {
                set member [lindex $members $i]
                set label [lindex $labelValues $i]
                if {![dict exists $labels $member]} {
                    lappend order $member
                    dict set labels $member $label
                } elseif {[dict get $labels $member] ne $label} {
                    error "Family label changes within member '$member' in Dataset '$datasetId'"
                }
            }
            if {[dict get $chunk eof]} {break}
        }
    } finally {
        ::GX::tableStreamClose $stream
    }
    set out {}
    foreach member $order {
        lappend out [dict create member $member label [dict get $labels $member]]
    }
    return $out
}

proc familyMemberSelectedByFilters {record familyId labelId filters} {
    set member [dict get $record member]
    set label [dict get $record label]
    foreach f $filters {
        if {![dict exists $f filter_variable_id] || ![dict exists $f predicate]} continue
        set fid [dict get $f filter_variable_id]
        if {$fid eq $familyId} {set probe $member
        } elseif {$labelId ne "" && $fid eq $labelId} {set probe $label
        } else {continue}
        set pred [dict get $f predicate]
        switch -- $pred {
            exact_equal {
                if {![dict exists $f value] || $probe ne [dict get $f value]} {return 0}
            }
            in_set {
                if {![dict exists $f values] || [lsearch -exact [dict get $f values] $probe] < 0} {return 0}
            }
        }
    }
    return 1
}

# plot.dataset intentionally rejects a band attached to a family-grouped
# Series. Expand that public family representation into ordinary filtered
# Series first, then attach the band to each member Series.
proc expandFamilyBandSeries {series} {
    if {![dict exists $series band] || ![dict exists $series family_variable_id] ||
        [string trim [dict get $series family_variable_id]] eq ""} {
        return [list $series]
    }
    set datasetId [dict get $series dataset_id]
    set familyId [dict get $series family_variable_id]
    set labelId ""
    if {[dict exists $series secondary_variable_id]} {
        set labelId [string trim [dict get $series secondary_variable_id]]
    }
    set members [datasetFamilyMembers $datasetId $familyId $labelId]
    if {![llength $members]} {error "Family-grouped band Series '[dict get $series id]' has no members"}
    set baseId [dict get $series id]
    set baseLabel [string trim [dict get $series label]]
    set baseFilters [expr {[dict exists $series row_filters] ? [dict get $series row_filters] : {}}]
    set out {}
    set index 0
    foreach rec $members {
        if {![familyMemberSelectedByFilters $rec $familyId $labelId $baseFilters]} continue
        incr index
        set member [dict get $rec member]
        set memberLabel [dict get $rec label]
        set one $series
        dict unset one family_variable_id
        catch {dict unset one family_label_prefix}
        catch {dict unset one secondary_variable_id}
        dict set one id [format "%s_family_%04d" $baseId $index]
        set filters $baseFilters
        lappend filters [dict create filter_variable_id $familyId predicate exact_equal value $member]
        dict set one row_filters $filters
        if {$baseLabel eq ""} {
            dict set one label $memberLabel
        } elseif {$memberLabel eq ""} {
            dict set one label $baseLabel
        } else {
            dict set one label "$baseLabel $memberLabel"
        }
        lappend out $one
    }
    if {![llength $out]} {error "No family members match the active filters for band Series '$baseId'"}
    return $out
}

proc copyAxisStateFromRuntime {runtime producerGraph destKey} {
    variable ::GX::axisOverride
    array unset ::GX::axisOverride "$destKey,*"
    set sec "axis.$producerGraph"
    set prefix "$sec."
    set panelCount [rv $runtime $sec panel_count 0]
    if {![string is integer -strict $panelCount] || $panelCount < 0} {set panelCount 0}
    set panelNames {}
    for {set i 1} {$i <= $panelCount} {incr i} {
        set pn [rv $runtime $sec "panel${i}_name" ""]
        if {$pn ne ""} {lappend panelNames $pn}
    }
    if {[llength $panelNames]} {set ::GX::axisOverride($destKey,panels) $panelNames}
    dict for {k v} $runtime {
        if {![string match "$prefix*" $k]} continue
        set field [string range $k [string length $prefix] end]
        if {$field eq "panel_count" || [regexp {^panel[0-9]+_} $field]} continue
        set ::GX::axisOverride($destKey,$field) $v
    }
    for {set i 1} {$i <= $panelCount} {incr i} {
        set pn [rv $runtime $sec "panel${i}_name" ""]
        if {$pn eq ""} continue
        foreach field {y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color ylabel_x} {
            set key "$sec.panel${i}_$field"
            if {[dict exists $runtime $key]} {set ::GX::axisOverride($destKey,$pn,$field) [dict get $runtime $key]}
        }
    }
}

proc copyLegendStateFromRuntime {runtime producerGraph destKey} {
    array unset ::GX::legendOverride "$destKey,*"
    set sec "legend.$producerGraph"
    set prefix "$sec."
    dict for {k v} $runtime {
        if {![string match "$prefix*" $k]} continue
        set field [string range $k [string length $prefix] end]
        set ::GX::legendOverride($destKey,$field) $v
    }
}

proc copyLevelScaleFromRuntime {runtime producerGraph destKey} {
    foreach axis {y y2 z} {
        catch {unset ::GX::levelScale($destKey,$axis)}
        set sec "level_scale.$producerGraph.$axis"
        set prefix "$sec."
        set fields [dict create]
        dict for {k v} $runtime {
            if {![string match "$prefix*" $k]} continue
            dict set fields [string range $k [string length $prefix] end] $v
        }
        if {[dict size $fields]} {::GX::levelScaleSet $destKey $axis $fields}
    }
}

proc copyGraphicsFromRuntime {runtime providerVariant} {
    foreach field [::GX::moduleGraphicsFields] {
        set key "graphics_effective.$field"
        if {![dict exists $runtime $key]} continue
        set value [dict get $runtime $key]
        catch {::GX::plotVariantGraphicsSet plot.dataset plot.dataset.xy $providerVariant $field $value}
    }
}

proc genericSeriesToPlotSpec {graphId variantId s runtime} {
    set sid [dict get $s series_id]
    set out [dict create id $sid dataset_id [dict get $s dataset_id] \
        x_variable_id [dict get $s x_variable_id] y_variable_id [dict get $s y_variable_id] \
        axis [dict get $s axis] label [dict get $s label] enabled [dict get $s enabled] order [dict get $s order]]
    foreach f {family_variable_id secondary_variable_id ordering_variable_id row_filters} {
        if {[dict exists $s $f] && [dict get $s $f] ne ""} {dict set out $f [dict get $s $f]}
    }
    if {[dict exists $s family_variable_id] && [dict get $s family_variable_id] ne ""} {
        dict set out family_label_prefix [dict get $s label]
    }

    set psec "plot.$graphId"
    set kind line
    set style [dict create]
    switch -- $graphId {
        curve.replicate.overlay {
            set kind line
        }
        curve.replicate.consensus_uncertainty {
            set kind line
            set band [string tolower [string trim [rv $runtime $psec band y_std]]]
            if {[dict get $s dataset_id] eq "curve.replicate.profiles" && [dict get $s y_variable_id] in {mean median} && $band ne "none"} {
                switch -- $band {
                    y_sem {set lo lower_sem; set hi upper_sem}
                    sigma_total {set lo lower_sigma_total; set hi upper_sigma_total}
                    default {set lo lower_std; set hi upper_std}
                }
                dict set out band [dict create lower_variable_id $lo upper_variable_id $hi draw_center 1]
            }
        }
        curve.replicate.uncertainty_components {
            set kind line
        }
        curve.replicate.family_summary {
            set kind bar
            dict set out bar_width 0.22
            # Preserve the historical summary-statistic selector for the
            # default three Series while still allowing custom Series edits.
            set stat [string tolower [string trim [rv $runtime $psec summary_statistic rms]]]
            if {$stat ni {rms mean max}} {set stat rms}
            if {$sid in {within between total}} {
                set current [dict get $s y_variable_id]
                if {[regexp {^(within|between|total)_(rms|mean|max)$} $current -> comp old]} {
                    dict set out y_variable_id "${comp}_${stat}"
                }
            }
        }
    }

    # Generic Graph Series style fields are public CORE presentation state.
    # They override Graphics only when the user explicitly sets them.
    if {[dict exists $s style_color] && [string trim [dict get $s style_color]] ne ""} {
        dict set style color [dict get $s style_color]
    }
    if {[dict exists $s style_line_style] && [string trim [dict get $s style_line_style]] ne ""} {
        dict set style line_style [dict get $s style_line_style]
    }

    set present [::GX::CurveRepGraphicsV1::_stateGet $graphId $variantId $sid]
    set pkind [dict get $present kind]
    if {$pkind ne "" && $pkind ne "inherit"} {set kind $pkind}
    dict set out kind $kind
    set override [dict create]
    foreach f {color line_style line_width marker marker_size marker_fill opacity} {
        set v [dict get $present $f]
        if {$v ne "" && $v ne "inherit"} {dict set override $f $v}
    }
    set style [styleMerge $style $override]
    if {[dict size $style]} {dict set out style $style}

    # Optional graph-level family filter remains an additive scientific row
    # filter. It never replaces the Series editor's own filters.
    if {$graphId ne "curve.replicate.family_summary"} {
        set selected [listSemi [rv $runtime $psec family_filter ""]]
        if {[llength $selected]} {
            set filters [expr {[dict exists $out row_filters] ? [dict get $out row_filters] : {}}]
            lappend filters [dict create filter_variable_id family_value predicate in_set values $selected]
            dict set out row_filters $filters
        }
    }
    return $out
}

proc buildPlotSpec {graphId variantId runtime} {
    set psec "plot.$graphId"
    set title [rv $runtime $psec title "Replicate Curve Analysis"]
    set axes [dict create]
    set xa [dict create]
    set ya [dict create]
    set xl [string trim [rv $runtime $psec x_label auto]]
    set yl [string trim [rv $runtime $psec y_label auto]]
    if {$xl ne "" && [string tolower $xl] ne "auto"} {dict set xa label $xl}
    if {$yl ne "" && [string tolower $yl] ne "auto"} {dict set ya label $yl}

    if {$graphId eq "curve.replicate.family_summary" && [::GX::datasetField curve.replicate.family_summary id ""] ne ""} {
        if {![catch {set members [datasetFamilyMembers curve.replicate.family_summary family_index family_value]}] && [llength $members]} {
            set pos {}; set labels {}; set i 0
            foreach rec $members {
                incr i; lappend pos $i; lappend labels [dict get $rec label]
            }
            dict set xa tick_positions [join $pos ";"]
            dict set xa tick_labels [join $labels ";"]
        }
    }
    if {[dict size $xa]} {dict set axes x $xa}
    if {[dict size $ya]} {dict set axes y_left $ya}

    set sourceSeries [::GX::graphSeriesList curve.replicate_analysis $graphId $variantId 1]
    if {![llength $sourceSeries]} {error "No Graph Series are configured for curve.replicate_analysis/$graphId"}
    set series {}
    foreach s $sourceSeries {
        set prepared [genericSeriesToPlotSpec $graphId $variantId $s $runtime]
        foreach expanded [expandFamilyBandSeries $prepared] {lappend series $expanded}
    }
    set panel [dict create id main axes $axes series $series annotations {}]
    return [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy \
        title $title defaults [dict create style [dict create]] panels [list $panel] output [dict create]]
}

proc copyArtifactAndMetadata {artifact target} {
    file mkdir [file dirname $target]
    file copy -force -- $artifact $target
    set srcDir [file dirname $artifact]
    set srcBase [file rootname [file tail $artifact]]
    set dstDir [file dirname $target]
    set dstBase [file rootname [file tail $target]]
    set srcMeta [file join $srcDir .gxtxt_plotmeta "$srcBase.ini"]
    if {[file isfile $srcMeta]} {
        set md [file join $dstDir .gxtxt_plotmeta]; file mkdir $md
        file copy -force -- $srcMeta [file join $md "$dstBase.ini"]
    }
}

if {[catch {
    if {[llength $argv] != 6} {error "curve replicate bridge requires SESSION RUNTIME OUTDIR GRAPH_ID ALIAS_FILE OPERATION"}
    lassign $argv session runtimePath outdir graphId aliasFile operation
    if {$operation ni {render rerender}} {error "Operation must be render or rerender"}
    set session [file normalize $session]
    set runtimePath [file normalize $runtimePath]
    if {![file isdirectory $session]} {error "Session does not exist: $session"}
    if {![file isfile $runtimePath]} {error "Producer runtime does not exist: $runtimePath"}
    if {$graphId ni {curve.replicate.overlay curve.replicate.consensus_uncertainty curve.replicate.uncertainty_components curve.replicate.family_summary}} {error "Unknown producer graph '$graphId'"}
    if {![regexp {^[A-Za-z0-9_.-]+\.png$} $aliasFile]} {error "Invalid alias filename '$aliasFile'"}

    set here [file dirname [file normalize [info script]]]
    set root [file normalize [file join $here .. .. .. ..]]
    set argv0 __curve_replicate_plot_v152_bridge__
    source [file join $root gxtxt_pipeline.tcl]
    ::GX::defaults
    ::GX::loadModuleCatalog
    set ::GX::currentSession $session
    set manifest [file join $session metadata manifest.ini]
    if {[file isfile $manifest]} {::GX::loadManifest $manifest}
    ::GX::loadDatasetRegistry $session

    # Activate the producer's Series extension (headless-safe) and seed the
    # standard Graph Series if this is the first v15 render.
    set producerDescriptor [::GX::moduleField curve.replicate_analysis descriptor ""]
    source [file join [file dirname $producerDescriptor] api curve_replicate_graphics_api_v1.tcl]

    set runtime [::GX::parseIni $runtimePath]
    set producerVariant [rv $runtime plot_variant variant_id ""]
    ::GX::CurveRepGraphicsV1::ensureSeries $graphId $producerVariant

    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set spec [buildPlotSpec $graphId $producerVariant $runtime]
    set providerScope [expr {$producerVariant eq "" ? "base" : $producerVariant}]
    set providerKey "curve.replicate_analysis:v15.2:$graphId:$providerScope"
    set ref [::GX::PlotDatasetAPIv3::upsertPlotFromSpec curve.replicate_analysis $providerKey $spec]
    set providerVariant [dict get $ref variant_id]
    set destKey [::GX::plotVariantKey plot.dataset.xy $providerVariant]

    # Project every applicable shared presentation layer into the hidden
    # backend Variant before asking the public renderer for its command.
    copyAxisStateFromRuntime $runtime $graphId $destKey
    copyLegendStateFromRuntime $runtime $graphId $destKey
    copyLevelScaleFromRuntime $runtime $graphId $destKey
    copyGraphicsFromRuntime $runtime $providerVariant

    # Provider graph configuration that is not carried by PlotSpec.
    # The default line_width is inherit, so Graphics Inheritance remains the
    # authority unless the user deliberately sets a graph/Series override.
    set legendContent series
    if {$graphId eq "curve.replicate.overlay" && [string tolower [rv $runtime "plot.$graphId" legend_mode source_replicate]] eq "none"} {set legendContent none}
    catch {::GX::plotVariantConfigSet plot.dataset plot.dataset.xy $providerVariant legend_content $legendContent}
    catch {::GX::plotVariantConfigSet plot.dataset plot.dataset.xy $providerVariant point_order dataset_order}
    # v15 deliberately has no module graph-level line-width field. Reset the
    # hidden backend to inherit on every render so Global/Module Graphics is
    # authoritative unless a Series carries an explicit line_width override.
    catch {::GX::plotVariantConfigSet plot.dataset plot.dataset.xy $providerVariant line_width inherit}
    if {$graphId eq "curve.replicate.overlay"} {
        set graphMarkerSize [string trim [rv $runtime "plot.$graphId" marker_size 3]]
        if {$graphMarkerSize ne ""} {catch {::GX::plotVariantConfigSet plot.dataset plot.dataset.xy $providerVariant marker_size $graphMarkerSize}}
    }

    # Hidden backend Variants must never join normal scheduled plot.dataset
    # runs. Explicit API renderCommand remains valid regardless of USE.
    catch {::GX::graphUseStateSet plot.dataset plot.dataset.xy $providerVariant 0}
    ::GX::writeManifest $manifest

    set item [::GX::PlotDatasetAPIv1::renderCommand $ref $operation]
    set cmd [lindex $item 1]
    if {[catch {set renderOutput [exec {*}$cmd 2>@1]} renderError renderOptions]} {
        return -options $renderOptions "Plot Dataset backend render failed: $renderError"
    }
    set artifacts [::GX::PlotDatasetAPIv2::artifacts $ref]
    set artifact [dict get $artifacts graph_artifact]
    if {![file isfile $artifact]} {error "Plot Dataset backend did not create its graph artifact"}

    set target [file join [file normalize $outdir] $aliasFile]
    copyArtifactAndMetadata $artifact $target

    # The provider Variant is a backend implementation detail. Keep its
    # persistent PlotSpec/cache but remove the rendered PNG/geometry so the
    # Graphs window exposes only the producer-owned artifact.
    set providerMeta [file join [file dirname $artifact] .gxtxt_plotmeta "[file rootname [file tail $artifact]].ini"]
    catch {file delete -force -- $artifact}
    catch {file delete -force -- $providerMeta}

    ::GX::writeManifest $manifest
    puts [join [list RESULT [enc $target] [enc $providerVariant] [enc $providerKey]] \t]
    flush stdout
} message options]} {
    fail $message
}
