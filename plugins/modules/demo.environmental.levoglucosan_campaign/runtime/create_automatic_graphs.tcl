#!/usr/bin/env tclsh
# Generate selectable automatic plot.dataset graphs for the Sardinia levoglucosan demo.
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::LevoglucosanDemoPlot {}

proc ::LevoglucosanDemoPlot::argValue {argv name defaultValue} {
    set idx [lsearch -exact $argv $name]
    if {$idx < 0 || $idx + 1 >= [llength $argv]} { return $defaultValue }
    return [lindex $argv [expr {$idx + 1}]]
}

proc ::LevoglucosanDemoPlot::findRoot {} {
    set dir [file normalize [file dirname [info script]]]
    for {set i 0} {$i < 8} {incr i} {
        if {[file isfile [file join $dir gxtxt_pipeline.tcl]]} { return $dir }
        set parent [file dirname $dir]
        if {$parent eq $dir} break
        set dir $parent
    }
    error "Cannot locate the GX-TXT root from [info script]."
}

proc ::LevoglucosanDemoPlot::siteNames {} {
    return [list "Cagliari metropolitan" "Gonnostramatza / Marmilla" "Nuoro / Barbagia" "Olbia / Gallura"]
}

proc ::LevoglucosanDemoPlot::newSinglePanelSpec {title} {
    set spec [::GX::PlotDatasetAPIv3::newSpec -graph_id plot.dataset.xy -title $title]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel id main
    dict set panel title $title
    dict set panel annotations {}
    dict set spec panels [list $panel]
    return $spec
}

proc ::LevoglucosanDemoPlot::groupEnabled {groups group} {
    return [expr {[lsearch -exact [split $groups ,] $group] >= 0}]
}

proc ::LevoglucosanDemoPlot::buildSpecs {fireEvent fireStart fireEnd uncertaintyStart uncertaintyEnd uncertaintySite groups qcThreshold anomalyThreshold} {
    set names [siteNames]
    set specs {}

    # 1. Dense full-year time series. One confidence band demonstrates uncertainty
    # without covering the graph with 1,460 individual error bars.
    set spec [newSinglePanelSpec "Full-year daily levoglucosan - synthetic Sardinia campaign"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Day of year (2025 synthetic calendar)" min 1 max 365]
    dict set panel axes y_left [dict create label "Levoglucosan in aqueous extract" display_unit ppm min 0]
    set series {}
    lappend series [dict create id gon_confidence dataset_id demo.environmental.levoglucosan.daily.site2 \
        x_variable_id day_of_year y_variable_id mean_ppm axis left kind band label "Gonnostramatza conditional 95% CI" \
        band [dict create lower_variable_id ci95_lower_ppm upper_variable_id ci95_upper_ppm draw_center 0] \
        style [dict create opacity 0.13]]
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_daily" dataset_id "demo.environmental.levoglucosan.daily.site${s}" \
            x_variable_id day_of_year y_variable_id mean_ppm axis left kind line label [lindex $names [expr {$s-1}]] \
            style [dict create line_width 1.5]]
    }
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group seasonality slug 01_full_year_daily.png title [dict get $spec title] spec $spec]

    # 2. Monthly means with true CI variables supplied through the public error binding.
    set spec [newSinglePanelSpec "Monthly levoglucosan means with conditional 95% confidence intervals"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Month number" min 1 max 12]
    dict set panel axes y_left [dict create label "Monthly mean levoglucosan" display_unit ppm min 0]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_monthly" dataset_id "demo.environmental.levoglucosan.monthly.site${s}" \
            x_variable_id month y_variable_id mean_ppm axis left kind line_marker label [lindex $names [expr {$s-1}]] \
            y_error [dict create mode symmetric variable_id ci95_half_width_ppm]]
    }
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group seasonality slug 02_monthly_errorbars.png title [dict get $spec title] spec $spec]

    # 3. Strongest generated wildfire event, with daily triplicate-mean CI and event interval.
    set spec [newSinglePanelSpec "Selected synthetic wildfire event - daily means and conditional 95% CI"]
    set panel [lindex [dict get $spec panels] 0]
    set xmin [expr {max(1, int($fireStart)-2)}]
    set xmax [expr {min(365, int($fireEnd)+2)}]
    dict set panel axes x [dict create label "Day of year" min $xmin max $xmax]
    dict set panel axes y_left [dict create label "Daily mean levoglucosan" display_unit ppm min 0]
    dict set panel annotations [list [dict create type reference_region axis x min $fireStart max $fireEnd \
        label "Synthetic wildfire event $fireEvent" opacity 0.10]]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_wildfire" dataset_id "demo.environmental.levoglucosan.wildfire.site${s}" \
            x_variable_id day_of_year y_variable_id mean_ppm axis left kind line_marker label [lindex $names [expr {$s-1}]] \
            y_error [dict create mode symmetric variable_id ci95_half_width_ppm]]
    }
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group fire slug 03_selected_wildfire.png title [dict get $spec title] spec $spec]

    # 4. Seasonal/site comparison. Category codes are documented in the axis label.
    set spec [newSinglePanelSpec "Seasonal and wildfire-period site comparison"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Category: 1 winter; 2 spring; 3 summer non-fire; 4 summer fire; 5 autumn" min 1 max 5]
    dict set panel axes y_left [dict create label "Mean daily levoglucosan" display_unit ppm min 0]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_seasonal" dataset_id "demo.environmental.levoglucosan.seasonal.site${s}" \
            x_variable_id category_code y_variable_id mean_ppm axis left kind line_marker label [lindex $names [expr {$s-1}]] \
            y_error [dict create mode symmetric variable_id ci95_half_width_ppm]]
    }
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group seasonality slug 04_seasonal_site_comparison.png title [dict get $spec title] spec $spec]

    # 5. Fire exposure relationship, with per-site observations and the weighted fit.
    set spec [newSinglePanelSpec "Levoglucosan versus synthetic wildfire exposure"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Fire exposure index" min 0]
    dict set panel axes y_left [dict create label "Daily mean levoglucosan" display_unit ppm min 0]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_fire_exposure" dataset_id "demo.environmental.levoglucosan.fire.site${s}" \
            x_variable_id fire_exposure_index y_variable_id mean_ppm axis left kind scatter label [lindex $names [expr {$s-1}]] \
            y_error [dict create mode symmetric variable_id sem_ppm]]
    }
    lappend series [dict create id exposure_fit dataset_id demo.environmental.levoglucosan.fire_exposure_regression \
        x_variable_id exposure_index y_variable_id fit_ppm axis left kind line label "Weighted linear fit" \
        style [dict create line_width 2.0]]
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group fire slug 05_fire_exposure_relationship.png title [dict get $spec title] spec $spec]

    # 6. Fire-distance attenuation relationship.
    set spec [newSinglePanelSpec "Levoglucosan versus nearest active-fire distance"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Nearest active-fire distance" display_unit km min 0]
    dict set panel axes y_left [dict create label "Daily mean levoglucosan" display_unit ppm min 0]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_fire_distance" dataset_id "demo.environmental.levoglucosan.fire.site${s}" \
            x_variable_id distance_km y_variable_id mean_ppm axis left kind scatter label [lindex $names [expr {$s-1}]] \
            y_error [dict create mode symmetric variable_id sem_ppm]]
    }
    lappend series [dict create id distance_fit dataset_id demo.environmental.levoglucosan.fire_distance_regression \
        x_variable_id distance_km y_variable_id fit_ppm axis left kind line label "Weighted linear fit" \
        style [dict create line_width 2.0]]
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group fire slug 06_fire_distance_relationship.png title [dict get $spec title] spec $spec]

    # 7. Compact four-site geographic comparison. Four points are descriptive only.
    set spec [newSinglePanelSpec "Four-site geographic comparison of wildfire-period levoglucosan"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Longitude" display_unit deg]
    dict set panel axes y_left [dict create label "Summer wildfire-period mean levoglucosan" display_unit ppm min 0]
    dict set panel series [list [dict create id geographic_summary dataset_id demo.environmental.levoglucosan.site_summary \
        x_variable_id longitude_deg y_variable_id summer_fire_mean_ppm axis left kind scatter label "Four Sardinian reference sites" \
        y_error [dict create mode symmetric variable_id summer_fire_ci95_half_width_ppm] \
        style [dict create marker circle marker_size 8]]]
    dict set spec panels [list $panel]
    lappend specs [dict create group spatial slug 07_geographic_site_comparison.png title [dict get $spec title] spec $spec]

    # 8. Measurement-uncertainty teaching view: all three replicates plus mean and Student-t CI.
    set spec [newSinglePanelSpec "Technical triplicates, daily mean, and conditional 95% CI - site $uncertaintySite"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Day of year" min $uncertaintyStart max $uncertaintyEnd]
    dict set panel axes y_left [dict create label "Levoglucosan in aqueous extract" display_unit ppm min 0]
    set series [list \
        [dict create id replicate_1 dataset_id demo.environmental.levoglucosan.uncertainty_demo x_variable_id day_of_year y_variable_id replicate_1_ppm axis left kind scatter label "Technical replicate 1"] \
        [dict create id replicate_2 dataset_id demo.environmental.levoglucosan.uncertainty_demo x_variable_id day_of_year y_variable_id replicate_2_ppm axis left kind scatter label "Technical replicate 2"] \
        [dict create id replicate_3 dataset_id demo.environmental.levoglucosan.uncertainty_demo x_variable_id day_of_year y_variable_id replicate_3_ppm axis left kind scatter label "Technical replicate 3"] \
        [dict create id daily_mean dataset_id demo.environmental.levoglucosan.uncertainty_demo x_variable_id day_of_year y_variable_id daily_mean_ppm axis left kind line_marker label "Daily triplicate mean (conditional 95% CI)" \
            y_error [dict create mode symmetric variable_id daily_ci95_half_width_ppm] style [dict create line_width 2.0]]]
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group uncertainty_qc slug 08_measurement_uncertainty.png title [dict get $spec title] spec $spec]

    # 9. Daily technical-replicate coefficient of variation.
    set spec [newSinglePanelSpec "Daily technical-replicate coefficient of variation"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Day of year" min 1 max 365]
    dict set panel axes y_left [dict create label {Technical replicate CV [%]} min 0]
    dict set panel annotations [list [dict create type reference_line axis left value $qcThreshold label "Configured high-CV threshold"]]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_qc" dataset_id "demo.environmental.levoglucosan.qc.site${s}" \
            x_variable_id day_of_year y_variable_id cv_percent axis left kind line label [lindex $names [expr {$s-1}]]]
    }
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group uncertainty_qc slug 09_measurement_qc_cv.png title [dict get $spec title] spec $spec]

    # 10. Pairwise same-day site correlations. Pair codes follow the report table.
    set spec [newSinglePanelSpec "Synchronized daily cross-site correlations"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Site pair code: 1 CAG-GON; 2 CAG-NUO; 3 CAG-OLB; 4 GON-NUO; 5 GON-OLB; 6 NUO-OLB" min 1 max 6]
    dict set panel axes y_left [dict create label "Pearson correlation coefficient" min -1 max 1]
    dict set panel series [list [dict create id cross_site_r dataset_id demo.environmental.levoglucosan.relationships \
        x_variable_id pair_code y_variable_id pearson_r axis left kind bar label "Pearson r"]]
    dict set spec panels [list $panel]
    lappend specs [dict create group cross_site slug 10_cross_site_correlations.png title [dict get $spec title] spec $spec]

    # 11. Robust anomaly score from site-wise moving-median baselines.
    set spec [newSinglePanelSpec "Positive robust anomaly score by monitoring site"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Day of year" min 1 max 365]
    dict set panel axes y_left [dict create label "Robust anomaly score"]
    dict set panel annotations [list [dict create type reference_line axis left value $anomalyThreshold label "Configured anomaly threshold"]]
    set series {}
    for {set s 1} {$s <= 4} {incr s} {
        lappend series [dict create id "site${s}_anomaly" dataset_id "demo.environmental.levoglucosan.anomaly.site${s}" \
            x_variable_id day_of_year y_variable_id robust_z axis left kind line label [lindex $names [expr {$s-1}]]]
    }
    dict set panel series $series
    dict set spec panels [list $panel]
    lappend specs [dict create group anomaly slug 11_anomaly_scores.png title [dict get $spec title] spec $spec]

    # 12. Compact annual campaign summary by site.
    set spec [newSinglePanelSpec "Annual mean levoglucosan by monitoring site"]
    set panel [lindex [dict get $spec panels] 0]
    dict set panel axes x [dict create label "Site ID: 1 Cagliari; 2 Gonnostramatza; 3 Nuoro; 4 Olbia" min 1 max 4]
    dict set panel axes y_left [dict create label "Annual mean levoglucosan" display_unit ppm min 0]
    dict set panel series [list [dict create id annual_site_summary dataset_id demo.environmental.levoglucosan.site_summary \
        x_variable_id site_id y_variable_id annual_mean_ppm axis left kind bar label "Annual mean" \
        y_error [dict create mode symmetric variable_id annual_ci95_half_width_ppm]]]
    dict set spec panels [list $panel]
    lappend specs [dict create group summary slug 12_campaign_site_summary.png title [dict get $spec title] spec $spec]

    set selected {}
    foreach entry $specs {
        if {[groupEnabled $groups [dict get $entry group]]} { lappend selected $entry }
    }
    return $selected
}

proc ::LevoglucosanDemoPlot::writeManifest {outputDir records} {
    set path [file join $outputDir automatic_graphs.ini]
    set f [open $path w]
    fconfigure $f -encoding utf-8 -translation lf
    try {
        puts $f {[automatic_graphs]}
        puts $f "count=[llength $records]"
        puts $f {provider=plot.dataset}
        puts $f {api=PLOT_DATASET_API_v3}
        puts $f {persistent_variants=true}
        set i 0
        foreach record $records {
            incr i
            puts $f ""
            puts $f [format {[graph.%02d]} $i]
            puts $f "title=[dict get $record title]"
            puts $f "group=[dict get $record group]"
            puts $f "graph_id=[dict get $record graph_id]"
            puts $f "variant_id=[dict get $record variant_id]"
            puts $f "png=[dict get $record slug]"
            puts $f "provider_artifact=[dict get $record provider_artifact]"
            puts $f {rerender=Use the persisted plot.dataset variant}
        }
    } finally {
        close $f
    }
    return $path
}

proc ::LevoglucosanDemoPlot::main {argv} {
    set session [argValue $argv --session ""]
    set outputDir [argValue $argv --output-dir ""]
    set fireEvent [argValue $argv --fire-event-id ""]
    set fireStart [argValue $argv --fire-start-day ""]
    set fireEnd [argValue $argv --fire-end-day ""]
    set uncertaintyStart [argValue $argv --uncertainty-start-day ""]
    set uncertaintyEnd [argValue $argv --uncertainty-end-day ""]
    set uncertaintySite [argValue $argv --uncertainty-site ""]
    set groups [argValue $argv --groups "summary,seasonality,fire,uncertainty_qc,cross_site,anomaly,spatial"]
    set qcThreshold [argValue $argv --qc-threshold "10"]
    set anomalyThreshold [argValue $argv --anomaly-threshold "4"]
    foreach {name value} [list session $session output-directory $outputDir fire-event $fireEvent fire-start $fireStart fire-end $fireEnd uncertainty-start $uncertaintyStart uncertainty-end $uncertaintyEnd uncertainty-site $uncertaintySite qc-threshold $qcThreshold anomaly-threshold $anomalyThreshold] {
        if {[string trim $value] eq ""} { error "Missing required $name argument." }
    }
    set session [file normalize $session]
    set outputDir [file normalize $outputDir]
    if {![file isdirectory $session]} { error "Session directory does not exist: $session" }
    file mkdir $outputDir

    set root [findRoot]
    cd $root
    ::GX::defaults
    ::GX::loadModuleCatalog
    ::GX::openSessionPath $session
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    foreach capability {cartesian_2d multi_dataset series_kind_line series_kind_scatter series_kind_line_marker series_kind_band series_kind_bar errorbar_y uncertainty_band annotations_reference_line annotations_reference_region variants render rerender artifacts stable_variable_identity} {
        ::GX::PlotDatasetAPIv3::requireCapability $capability
    }

    set specs [buildSpecs $fireEvent $fireStart $fireEnd $uncertaintyStart $uncertaintyEnd $uncertaintySite $groups $qcThreshold $anomalyThreshold]
    set records {}
    foreach entry $specs {
        set spec [dict get $entry spec]
        ::GX::PlotDatasetAPIv3::validateSpec $spec
        set key "demo.environmental.levoglucosan_campaign:base:[dict get $entry slug]"
        set ref [::GX::PlotDatasetAPIv3::upsertPlotFromSpec demo.environmental.levoglucosan_campaign $key $spec]
        set result [::GX::PlotDatasetAPIv3::render $ref]
        set artifacts [dict get $result artifacts]
        set src [dict get $artifacts graph_artifact]
        if {![file isfile $src]} { error "plot.dataset did not produce the expected graph artifact." }
        set dst [file join $outputDir [dict get $entry slug]]
        file copy -force -- $src $dst
        if {![file isfile $dst] || [file size $dst] <= 0} { error "Automatic graph copy failed: $dst" }
        lappend records [dict create \
            slug [dict get $entry slug] title [dict get $entry title] group [dict get $entry group] \
            graph_id [dict get $ref graph_id] variant_id [dict get $ref variant_id] \
            provider_artifact $src]
    }
    ::GX::sessionPersistenceCommit
    set manifest [writeManifest $outputDir $records]
    puts "PASS demo.environmental.levoglucosan_campaign automatic graphs: [llength $records] rendered plot.dataset variants; manifest=$manifest"
}

if {[file normalize $::argv0] eq [file normalize [info script]]} {
    # Source the fixed framework entry at global scope before the helper main.
    set ::argv0 __not_main__
    source [file join [::LevoglucosanDemoPlot::findRoot] gxtxt_pipeline.tcl]
    if {[catch {::LevoglucosanDemoPlot::main $::argv} err opts]} {
        puts stderr "FAIL demo.environmental.levoglucosan_campaign automatic graphs: $err"
        if {[dict exists $opts -errorinfo]} { puts stderr [dict get $opts -errorinfo] }
        exit 1
    }
}
