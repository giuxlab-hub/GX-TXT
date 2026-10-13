#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} {error "usage: nmr_pipeline.tcl FRAMEWORK RUNTIME_INI"}
namespace eval ::NMR {
    variable module analysis.spectroscopy.nmr
    variable version 1.0.0
}
proc ::NMR::field {cfg section key {default ""}} {
    return [::GX::descriptorValue $cfg $section $key $default]
}
proc ::NMR::number {cfg key default min max} {
    set raw [field $cfg config $key $default]
    if {![string is double -strict $raw] || [regexp -nocase {nan|inf} $raw]} {error "Invalid NMR $key"}
    set value [expr {double($raw)}]
    if {$value < $min || $value > $max} {error "NMR $key outside $min..$max"}
    return $value
}
proc ::NMR::publish {session id contract columns schemas source provenance} {
    variable module
    variable version
    set names [dict keys $columns]
    set count [llength [dict get $columns [lindex $names 0]]]
    foreach name $names {
        if {[llength [dict get $columns $name]] != $count} {error "NMR publication column mismatch"}
    }
    set definition [dict create dataset_id $id contract $contract storage auto \
        producer_version $version source_dataset_ids [list $source] \
        source_variable_ids {spectral_x spectral_y} source $source \
        provenance $provenance notes {Measured NMR source remains unchanged.} replace_owned 1]
    set plan [::GX::datasetPublicationV2Prepare $session $module $definition]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach name $names {
            set schema [dict merge [dict create name $name dtype float64 dimension_ids row semantic_role derived] [dict get $schemas $name]]
            ::GX::datasetPublicationV2DeclareVariable $writer $name $schema
        }
        if {$count > 0} {
            set written [::GX::datasetPublicationV2Append $writer row $columns]
            if {$written != $count} {error "NMR publication incomplete write"}
        }
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {::GX::datasetPublicationV2Abort $writer}
        return -options $options $message
    }
}
proc ::NMR::extremaPreserving {xs ys limit} {
    set count [llength $xs]
    if {$count != [llength $ys]} {error "NMR extrema reduction needs paired samples"}
    if {$count <= $limit} {return [list $xs $ys]}
    set block [expr {int(ceil(2.0*$count/$limit))}]
    set outX {};set outY {}
    for {set start 0} {$start < $count} {incr start $block} {
        set stop [expr {min($start+$block,$count)}]
        set minIndex $start;set maxIndex $start
        for {set index [expr {$start+1}]} {$index < $stop} {incr index} {
            set value [lindex $ys $index]
            if {$value < [lindex $ys $minIndex]} {set minIndex $index}
            if {$value > [lindex $ys $maxIndex]} {set maxIndex $index}
        }
        foreach index [lsort -integer -unique [list $minIndex $maxIndex]] {
            lappend outX [lindex $xs $index]
            lappend outY [lindex $ys $index]
        }
    }
    return [list $outX $outY]
}
proc ::NMR::run {path} {
    variable module
    set cfg [::GX::parseIni $path]
    if {[field $cfg runtime module_id ""] ne $module} {error "NMR runtime module ID mismatch"}
    set session [file normalize [field $cfg runtime session ""]]
    set output [file normalize [field $cfg runtime output_dir ""]]
    if {![file isdirectory $session] || ![file isdirectory $output]} {error "NMR Session/output missing"}
    ::GX::openSessionPath $session
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set source [field $cfg analysis_source.primary dataset_id [field $cfg dataset id ""]]
    if {$source eq ""} {error "NMR Analysis Source missing"}
    set handle [::GX::datasetAccessOpen $session $source]
    try {
        set info [::GX::datasetAccessMetadata $handle]
        set found [dict create]
        foreach variable [dict get $info variables] {
            dict set found [dict get $variable variable_id] $variable
        }
        foreach id {spectral_x spectral_y} {if {![dict exists $found $id]} {error "NMR $id binding missing"}}
        if {[dict get $found spectral_x unit] ne "ppm"} {error "NMR shift unit must be ppm"}
        set values [::GX::datasetAccessReadVariables $handle {spectral_x spectral_y}]
        set xs [dict get $values spectral_x values]
        set ys [dict get $values spectral_y values]
    } finally {::GX::datasetAccessClose $handle}
    if {[llength $xs] != [llength $ys] || [llength $xs] < 8} {error "NMR source needs paired samples"}
    set low [number $cfg region_min_ppm -5 -10000 10000]
    set high [number $cfg region_max_ppm 220 -10000 10000]
    if {$high <= $low} {error "NMR region max must exceed min"}
    set maxPoints [expr {int([number $cfg max_analysis_points 131072 128 1000000])}]
    set selectedX {}; set selectedY {}
    foreach x $xs y $ys {
        if {$x >= $low && $x <= $high} {lappend selectedX $x; lappend selectedY $y}
    }
    if {[llength $selectedX] < 8} {error "NMR region has too few samples"}
    set stride [expr {int(ceil([llength $selectedX]/double($maxPoints)))}]
    if {$stride > 1} {
        set thinX {};set thinY {}
        for {set i 0} {$i < [llength $selectedX]} {incr i $stride} {
            lappend thinX [lindex $selectedX $i]
            lappend thinY [lindex $selectedY $i]
        }
        set selectedX $thinX;set selectedY $thinY
    }
    if {[lindex $selectedX 0] > [lindex $selectedX end]} {
        set selectedX [lreverse $selectedX]; set selectedY [lreverse $selectedY]
    }
    set method [field $cfg config baseline_method linear]
    if {$method ni {none constant linear}} {error "Unsupported NMR baseline method"}
    if {$method ne "none"} {
        set baseline [::GX::NumericAPIv1::baseline $selectedX $selectedY \
            [dict create method $method estimator median]]
        set corrected [dict get $baseline corrected]
    } else {set corrected $selectedY}
    set scale 0.0
    foreach y $corrected {set a [expr {abs(double($y))}];if {$a > $scale} {set scale $a}}
    if {$scale <= 0} {error "NMR spectrum has zero intensity"}
    set normalized [lmap y $corrected {expr {double($y)/$scale}}]
    set minProm [number $cfg peak_min_prominence 0.05 0 1000]
    set minDistance [number $cfg peak_min_distance_ppm 0.15 0 1000]
    set peakSearchMax [expr {int([number $cfg peak_search_max_points 8192 128 1000000])}]
    lassign [extremaPreserving $selectedX $normalized $peakSearchMax] peakXInput peakYInput
    set peakMode [expr {[llength $peakXInput] == [llength $selectedX] ? "full_resolution" : "extrema_preserving"}]
    set peaks [::GX::NumericAPIv1::findPeaks $peakXInput $peakYInput \
        [dict create min_height 0 min_prominence $minProm min_distance $minDistance distance_mode x]]
    set peakX [dict get $peaks x];set peakY [dict get $peaks heights]
    set peakProm [dict get $peaks prominences]
    set peakWidth [dict get $peaks widths]
    set integrationLow [number $cfg integrate_min_ppm 0 -10000 10000]
    set integrationHigh [number $cfg integrate_max_ppm 220 -10000 10000]
    if {$integrationHigh <= $integrationLow} {error "NMR integration max must exceed min"}
    set ix {};set iy {}
    foreach x $selectedX y $normalized {
        if {$x >= $integrationLow && $x <= $integrationHigh} {lappend ix $x;lappend iy $y}
    }
    if {[llength $ix] < 2} {error "NMR integration region has too few samples"}
    set integral [::GX::NumericAPIv1::integrate $ix $iy]
    set base [regsub -all {[^A-Za-z0-9._-]} $source _]
    set processedId "${base}.nmr.processed"
    set displayId "${base}.nmr.display"
    set peaksId "${base}.nmr.peaks"
    set integralId "${base}.nmr.integrals"
    set provenance "source=$source;region=$low..$high ppm;baseline=$method;normalization=max_absolute;stride=$stride;peak_search=$peakMode;peak_search_points=[llength $peakXInput];peak_prominence=$minProm;peak_distance=$minDistance ppm;integration=$integrationLow..$integrationHigh ppm"
    publish $session $processedId spectrum.scientific \
        [dict create spectral_x $selectedX spectral_y $normalized] \
        [dict create spectral_x [dict create unit ppm semantic_role independent coordinate_role coordinate] \
            spectral_y [dict create unit 1 semantic_role derived coordinate_variable_ids spectral_x]] \
        $source $provenance
    lassign [extremaPreserving $selectedX $normalized 4096] displayX displayY
    publish $session $displayId spectrum.scientific \
        [dict create spectral_x $displayX spectral_y $displayY] \
        [dict create spectral_x [dict create unit ppm semantic_role independent coordinate_role coordinate] \
            spectral_y [dict create unit 1 semantic_role derived coordinate_variable_ids spectral_x]] \
        $source "$provenance;display=extrema_preserving;display_points=[llength $displayX];quantitative_source=$processedId"
    set count [llength $peakX]
    set peakIds {}
    for {set i 1} {$i <= $count} {incr i} {lappend peakIds $i}
    publish $session $peaksId table.generic \
        [dict create peak_id $peakIds chemical_shift_ppm $peakX \
            intensity $peakY prominence $peakProm width_ppm $peakWidth] \
        [dict create peak_id [dict create dtype int32] chemical_shift_ppm [dict create unit ppm semantic_role independent coordinate_role coordinate] \
            intensity [dict create unit 1] prominence [dict create unit 1] width_ppm [dict create unit ppm]] \
        $source $provenance
    publish $session $integralId table.generic \
        [dict create region_min_ppm [list $integrationLow] region_max_ppm [list $integrationHigh] integral [list [dict get $integral value]]] \
        [dict create region_min_ppm [dict create unit ppm] region_max_ppm [dict create unit ppm] \
            integral [dict create unit {}]] $source $provenance
    set report [open [file join $output nmr_analysis_report.txt] w]
    fconfigure $report -encoding utf-8 -translation lf
    puts $report "NMR analysis.spectroscopy.nmr 1.0.0\nSource Dataset: $source\nFull-resolution processed Dataset: $processedId\nExtrema-preserving graph Dataset: $displayId ([llength $displayX] points)\nPeak Dataset: $peaksId\nIntegral Dataset: $integralId\n$provenance\nDetected peaks: $count\nIntegral: [dict get $integral value] (relative intensity × ppm)"
    close $report
    puts "PASS NMR analysis source=$source processed=$processedId peaks=$count integral=[dict get $integral value]"
}
::NMR::run [lindex $argv 1]
