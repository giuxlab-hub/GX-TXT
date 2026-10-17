#!/usr/bin/env tclsh
# Replicate Curve Analysis v15.3 -> Plot Dataset v3 backend bridge.
# The v152 filename and persisted provider keys remain compatibility identities.
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
    foreach f {family_variable_id secondary_variable_id ordering_variable_id row_filters source_row_ordinals} {
        if {[dict exists $s $f] && [dict get $s $f] ne ""} {dict set out $f [dict get $s $f]}
    }
    # Optional Family is absent, not a fabricated numeric family. Retain the
    # trace identity grouping while omitting the unbound auxiliary dimension.
    if {[string trim [rv $runtime bindings family ""]] eq ""&&[dict get $s dataset_id] in {curve.replicate.traces curve.replicate.profiles}} {
        foreach field {family_variable_id secondary_variable_id} {
            if {[dict exists $out $field]&&[dict get $out $field] eq "family_value"} {dict unset out $field}
        }
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

proc seriesHasFiniteRows {session series} {
    # Presentation eligibility only: no estimates or statistical policy here.
    # Read canonical selected observations with the public Graph Series predicates.
    set dataset [dict get $series dataset_id]
    set ids [list [dict get $series x_variable_id] [dict get $series y_variable_id]]
    foreach field {family_variable_id secondary_variable_id ordering_variable_id} {
        if {[dict exists $series $field]&&[dict get $series $field] ne ""} {lappend ids [dict get $series $field]}
    }
    if {[dict exists $series bar_bounds]} {lappend ids {*}[dict values [dict get $series bar_bounds]]}
    set finite {}
    foreach id [lsort -unique $ids] {
        set dtype [dict get [::GX::datasetVariableV3ById $dataset $id] dtype]
        if {$dtype ne "string"} {lappend finite [dict create filter_variable_id $id predicate is_finite dtype $dtype]}
    }
    set filters {}
    if {[dict exists $series row_filters]} {set filters [::GX::graphSeriesNormalizeFilters $dataset [dict get $series row_filters]]}
    foreach filter $filters {lappend ids [dict get $filter filter_variable_id]}
    set selected {}
    if {[dict exists $series source_row_ordinals]} {foreach row [dict get $series source_row_ordinals] {dict set selected $row 1}}
    set stream [::GX::tableStreamOpenDataset $session $dataset [lsort -unique $ids] 512 {numeric_transport values}]
    try {
        while {1} {
            set chunk [::GX::tableStreamNext $stream];set values [dict get $chunk values]
            for {set i 0} {$i<[dict get $chunk row_count]} {incr i} {
                if {[dict size $selected]&&![dict exists $selected [expr {[dict get $chunk offset]+$i}]]} continue
                set valid 1
                foreach filter [concat $finite $filters] {
                    if {![::GX::graphSeriesFilterRowMatch $filter [lindex [dict get $values [dict get $filter filter_variable_id]] $i]]} {set valid 0;break}
                }
                if {$valid} {return 1}
            }
            if {[dict get $chunk eof]} {return 0}
        }
    } finally {::GX::tableStreamClose $stream}
}

proc buildPlotSpec {graphId variantId runtime omittedName} {
    upvar 1 $omittedName omitted
    set omitted {}
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
                incr i; lappend pos $i
                if {[string trim [rv $runtime bindings family ""]] eq ""} {lappend labels {All curves}} else {lappend labels [dict get $rec label]}
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
        foreach expanded [expandFamilyBandSeries $prepared] {
            if {[seriesHasFiniteRows $::GX::currentSession $expanded]} {lappend series $expanded} else {lappend omitted [dict get $expanded id]}
        }
    }
    set panel [dict create id main axes $axes series $series annotations {}]
    return [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy \
        title $title defaults [dict create style [dict create]] panels [list $panel] output [dict create]]
}

proc writeGraphStatus {outdir aliasFile graphId variantId status omitted count reason} {
    file mkdir $outdir
    set path [file join $outdir "[file rootname $aliasFile].status.ini"]
    set temp "$path.[pid].tmp";set fd [open $temp {WRONLY CREAT EXCL}]
    try {
        puts $fd {[graph_status]}
        foreach {key value} [list api_version 1 graph_id $graphId variant_id $variantId render_status $status rendered_series $count omitted_series $omitted reason $reason statistical_semantics_api STATISTICAL_RESULT_SEMANTICS_API_v1] {::GX::putKV $fd $key $value}
    } finally {close $fd}
    file rename -force -- $temp $path
    return $path
}

proc preserveUnavailableArtifact {outdir aliasFile} {
    set stem [file rootname $aliasFile];set candidates [list $aliasFile "$stem.svg" "$stem.pdf" [file join .gxtxt_plotmeta "$stem.ini"]]
    set history ""
    foreach relative $candidates {
        set path [file join $outdir $relative];if {![file isfile $path]} continue
        if {$history eq ""} {set history [file join $outdir previous_graphs "[clock microseconds]_[pid]"];file mkdir $history}
        set destination [file join $history $relative];file mkdir [file dirname $destination]
        file rename -- $path $destination
    }
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
    set statisticalDataset [dict get {curve.replicate.overlay curve.replicate.traces curve.replicate.consensus_uncertainty curve.replicate.profiles curve.replicate.uncertainty_components curve.replicate.profiles curve.replicate.family_summary curve.replicate.family_summary} $graphId]
    set statistics [::GX::datasetMetadataRead $session $statisticalDataset]
    if {![dict exists $statistics analysis.statistical_results]} {error {Replicate result lacks captured CORE meaning; recalculate before rendering}}
    ::GX::StatisticsV1::validateMetadata $statistics
    ::GX::sessionInspectionDatasetPayload $statisticalDataset $session
    dict for {record result} [dict get $statistics analysis.statistical_results] {
        if {[dict get $result schema] eq "gxtxt.statistical_result.column_binding.v1"} {::GX::StatisticsV1::bindingTable $session $statisticalDataset $record 0 1}
    }

    # Activate the producer's Series extension (headless-safe) and seed the
    # standard Graph Series if this is the first v15 render.
    set producerDescriptor [::GX::moduleField curve.replicate_analysis descriptor ""]
    source [file join [file dirname $producerDescriptor] api curve_replicate_graphics_api_v1.tcl]

    set runtime [::GX::parseIni $runtimePath]
    set producerVariant [rv $runtime plot_variant variant_id ""]
    ::GX::CurveRepGraphicsV1::ensureSeries $graphId $producerVariant

    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set spec [buildPlotSpec $graphId $producerVariant $runtime omitted]
    set renderedCount [llength [dict get [lindex [dict get $spec panels] 0] series]]
    set reason ""
    if {[llength $omitted]} {set reason {No finite observations satisfy the omitted Series bindings and filters; captured CORE results retain statistical availability and assumptions.}}
    if {!$renderedCount} {
        preserveUnavailableArtifact $outdir $aliasFile
        set statusPath [writeGraphStatus $outdir $aliasFile $graphId $producerVariant unavailable $omitted 0 $reason]
        ::GX::writeManifest $manifest
        puts [join [list UNAVAILABLE [enc $reason] [enc $statusPath]] \t]
        flush stdout
        exit 0
    }
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
    writeGraphStatus $outdir $aliasFile $graphId $producerVariant rendered $omitted $renderedCount $reason

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
