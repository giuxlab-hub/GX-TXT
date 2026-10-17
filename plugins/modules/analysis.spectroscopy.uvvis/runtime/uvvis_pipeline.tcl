#!/usr/bin/env tclsh
# Dataset-native UV/Vis family calibration through public CORE and NUMERIC APIs.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} {error "usage: uvvis_pipeline.tcl FRAMEWORK_ROOT RUNTIME_INI"}
set framework [file normalize [lindex $argv 0]]
set runtimeIni [file normalize [lindex $argv 1]]
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1

namespace eval ::UVVis {
    variable moduleId analysis.spectroscopy.uvvis
    variable moduleVersion 1.2.0
}

proc ::UVVis::datasetProvenance {session datasetId} {
    set record [::GX::sessionInspectionDataset $datasetId $session]
    if {[dict exists $record provenance]} {return [dict get $record provenance]}
    return [dict create]
}
proc ::UVVis::ini {cfg section key {default ""}} {
    return [::GX::descriptorValue $cfg $section $key $default]
}
proc ::UVVis::finiteNumber {value label} {
    if {![string is double -strict $value] || [regexp -nocase {nan|inf} $value]} {error "$label must be finite numeric"}
    return [expr {double($value)}]
}
proc ::UVVis::sourceSpectrum {session datasetId} {
    set handle [::GX::datasetAccessOpen $session $datasetId]
    try {
        set meta [::GX::datasetAccessMetadata $handle]
        if {[dict get $meta contract] ne "spectrum.scientific"} {error "$datasetId is not a scientific Spectrum"}
        set variables [dict get $meta variables]
        set xUnit ""; set yUnit ""
        foreach var $variables {
            if {[dict get $var variable_id] eq "spectral_x"} {set xUnit [dict get $var unit]}
            if {[dict get $var variable_id] eq "spectral_y"} {set yUnit [dict get $var unit]}
        }
        if {$xUnit ne "nm" || $yUnit ne "1"} {error "$datasetId requires wavelength in nm and dimensionless absorbance"}
        set provenance [datasetProvenance $session $datasetId]
        if {[catch {dict get $provenance y_representation} representation] || $representation ne "absorbance"} {
            error "$datasetId must explicitly preserve absorbance representation"
        }
        set values [::GX::datasetAccessReadVariables $handle {spectral_x spectral_y}]
        return [dict create x [dict get $values spectral_x values] y [dict get $values spectral_y values] dataset_id $datasetId]
    } finally {::GX::datasetAccessClose $handle}
}
proc ::UVVis::correctFamily {family blank} {
    if {$blank eq ""} {return $family}
    set bx [dict get $blank x]; set by [dict get $blank y]
    if {[lindex $bx 0] > [lindex $bx end]} {set bx [lreverse $bx]; set by [lreverse $by]}
    set out {}
    foreach member [dict get $family members] {
        set x [dict get $member x]
        set qx $x
        set reversed [expr {[lindex $qx 0] > [lindex $qx end]}]
        if {$reversed} {set qx [lreverse $qx]}
        set b [::GX::NumericAPIv1::resample $bx $by $qx \
            [dict create method linear extrapolation error]]
        set baselineValues [dict get $b y]
        if {$reversed} {set baselineValues [lreverse $baselineValues]}
        set y {}
        foreach sample [dict get $member y] baseline $baselineValues {
            lappend y [expr {$sample-$baseline}]
        }
        dict set member y $y
        lappend out $member
    }
    dict set family members $out
    return $family
}
proc ::UVVis::correctUnknown {unknown blank} {
    if {$blank eq ""} {return $unknown}
    set bx [dict get $blank x]; set by [dict get $blank y]
    if {[lindex $bx 0] > [lindex $bx end]} {set bx [lreverse $bx]; set by [lreverse $by]}
    set qx [dict get $unknown x]
    set reversed [expr {[lindex $qx 0] > [lindex $qx end]}]
    if {$reversed} {set qx [lreverse $qx]}
    set b [::GX::NumericAPIv1::resample $bx $by $qx \
        [dict create method linear extrapolation error]]
    set baselineValues [dict get $b y]
    if {$reversed} {set baselineValues [lreverse $baselineValues]}
    set y {}
    foreach sample [dict get $unknown y] baseline $baselineValues {lappend y [expr {$sample-$baseline}]}
    dict set unknown y $y
    return $unknown
}
proc ::UVVis::publishTable {session datasetId columns schemas sourceIds provenance} {
    variable moduleId
    variable moduleVersion
    set ids [dict keys $columns]
    set n [llength [dict get $columns [lindex $ids 0]]]
    foreach id $ids {if {[llength [dict get $columns $id]] != $n} {error "UV/Vis output $datasetId column length mismatch"}}
    set definition [dict create dataset_id $datasetId contract table.generic storage auto \
        producer_version $moduleVersion source_dataset_ids $sourceIds source_variable_ids {} \
        source [join $sourceIds {;}] provenance $provenance \
        notes {Derived UV/Vis output; full original spectra and their Spectral Family remain unchanged.} replace_owned 1]
    if {[dict exists $provenance statistical_results]} {
        dict set definition structured_metadata [::GX::StatisticsV1::publicationMetadata [dict get $provenance statistical_results]]
    }
    set plan [::GX::datasetPublicationV2Prepare $session $moduleId $definition]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach id $ids {
            set schema [dict merge [dict create name $id dtype float64 dimension_ids row semantic_role derived] [dict get $schemas $id]]
            ::GX::datasetPublicationV2DeclareVariable $writer $id $schema
        }
        if {$n > 0} {
            set written [::GX::datasetPublicationV2Append $writer row $columns]
            if {$written != $n} {error "UV/Vis output $datasetId incomplete"}
        }
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {::GX::datasetPublicationV2Abort $writer}
        return -options $options $message
    }
}
proc ::UVVis::writeReport {path details standards heldout unknown statistics} {
    ::GX::StatisticsV1::validate $statistics
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    try {
        puts $fd "# UV/Vis Spectral Family Quantitation 1.2.0\n"
        puts $fd "This report complements canonical Datasets. Inspect the full measured spectra, individual responses and residuals before interpreting the calibration.\n"
        dict for {key value} $details {puts $fd "- **$key:** $value"}
        puts $fd "\n[::GX::StatisticsV1::parameterReport $statistics]\n"
        puts $fd [::GX::StatisticsV1::report $statistics {n residual_standard_deviation r_squared dof reduced_chi_squared}]
        puts $fd "\n## Calibration standards (individual measurements retained)\n"
        puts $fd "| Member | Concentration | Response | Fitted response | Residual |"
        puts $fd "|---|---:|---:|---:|---:|"
        foreach row $standards {puts $fd "| [join $row { | }] |"}
        puts $fd "\n## Held-out validation\n"
        puts $fd "| Member | Known concentration | Measured response | Estimated concentration | Error |"
        puts $fd "|---|---:|---:|---:|---:|"
        foreach row $heldout {puts $fd "| [join $row { | }] |"}
        if {![llength $heldout]} {puts $fd "No held-out member was requested."}
        puts $fd "\n## Independent unknown\n"
        if {$unknown eq ""} {puts $fd "No independent unknown Spectrum was bound."} else {puts $fd $unknown}
        puts $fd "\nCalibration fit uncertainty is reported only through the public regression diagnostics; no prediction interval is asserted here. A high R-squared alone does not establish chemical selectivity or a valid range."
    } finally {close $fd}
}

proc ::UVVis::run {configPath} {
    variable moduleId
    set cfg [::GX::parseIni $configPath]
    if {[ini $cfg runtime module_id ""] ne $moduleId} {error "UV/Vis runtime module ID mismatch"}
    set session [file normalize [ini $cfg runtime session ""]]
    set output [file normalize [ini $cfg runtime output_dir ""]]
    if {![file isdirectory $session] || ![file isdirectory $output]} {error "UV/Vis Session/output missing"}
    ::GX::openSessionPath $session
    set familyId [ini $cfg analysis_source.primary dataset_id ""]
    if {$familyId eq ""} {error "UV/Vis Spectral Family Dataset is required"}
    set family [::GX::SpectralFamilyAPIv1::readSession $session $familyId]
    if {[dict get $family member_count] < 3} {error "UV/Vis calibration requires at least three family members"}
    set wavelength [finiteNumber [ini $cfg config analytical_wavelength_nm 280] {Analytical wavelength}]
    set peakMin [finiteNumber [ini $cfg config peak_search_min_nm 250] {Peak search minimum}]
    set peakMax [finiteNumber [ini $cfg config peak_search_max_nm 800] {Peak search maximum}]
    if {$peakMax <= $peakMin || $wavelength <= 0} {error "Invalid UV/Vis wavelength configuration"}
    set blankId [ini $cfg analysis_source.blank dataset_id ""]
    set blankMode [ini $cfg config blank_correction none]
    if {$blankMode ni {none subtract_blank_absorbance}} {error "Invalid blank-correction mode"}
    set blank ""
    if {$blankMode eq "subtract_blank_absorbance"} {
        if {$blankId eq ""} {error "Blank Spectrum Dataset required for absorbance subtraction"}
        set blank [sourceSpectrum $session $blankId]
    }
    set family [correctFamily $family $blank]
    set responses [::GX::SpectralFamilyAPIv1::responseAt $family $wavelength]
    set heldoutIds [lmap id [split [ini $cfg config heldout_member_ids ""] {;}] {string trim $id}]
    set heldoutIds [lsearch -all -inline -not -exact $heldoutIds ""]
    set seen [dict create]
    set x {}; set y {}; set standardIds {}; set validationRows {}
    set responseColumns [dict create member_id {} concentration {} response {} role {}]
    foreach item $responses {
        set id [dict get $item member_id]
        set concentration [dict get $item parameter_value]
        set signal [dict get $item response]
        dict set seen $id 1
        set role [expr {[lsearch -exact $heldoutIds $id] >= 0 ? "held_out_validation" : "calibration_standard"}]
        dict lappend responseColumns member_id $id
        dict lappend responseColumns concentration $concentration
        dict lappend responseColumns response $signal
        dict lappend responseColumns role $role
        if {$role eq "calibration_standard"} {
            lappend x $concentration; lappend y $signal; lappend standardIds $id
        } else {
            lappend validationRows [list $id $concentration $signal]
        }
    }
    foreach id $heldoutIds {if {![dict exists $seen $id]} {error "Unknown held-out member ID '$id'"}}
    if {[llength $x] < 3} {error "At least three calibration standards must remain after holdout"}
    set fit [::GX::NumericAPIv1::linearRegression $x $y]
    set statistics [::GX::StatisticsV1::fromNumeric math.numeric.linear linear_regression $fit \
        [dict create orientation y_of_x x_unit % y_unit 1 constraints none x_variable_id concentration y_variable_id response] \
        {} [dict create producer $moduleId]]
    set slope [dict get $fit slope]
    set intercept [dict get $fit intercept]
    if {abs($slope) < 1e-12} {error "Calibration slope is too close to zero for inverse prediction"}
    set fitted [dict get $fit predicted]
    set residuals [dict get $fit residuals]
    set sourceIds [list $familyId]
    if {$blank ne ""} {lappend sourceIds $blankId}
    set provenance [dict create analytical_wavelength_nm $wavelength blank_mode $blankMode \
        heldout_member_ids $heldoutIds regression_api NUMERIC_API_v1 regression_method unweighted_linear_least_squares \
        slope $slope intercept $intercept r_squared [::GX::StatisticsV1::scalarValue $statistics r_squared] \
        source_family $familyId statistical_results [dict create calibration $statistics]]
    set responseSchema [dict create member_id [dict create dtype string] \
        concentration [dict create unit %] response [dict create unit 1] role [dict create dtype string]]
    publishTable $session "$familyId.selected_responses" $responseColumns $responseSchema $sourceIds $provenance
    set calibration [dict create member_id $standardIds concentration $x response $y fitted_response $fitted residual $residuals]
    set calibrationSchema [dict create member_id [dict create dtype string] concentration [dict create unit %] \
        response [dict create unit 1] fitted_response [dict create unit 1] residual [dict create unit 1]]
    publishTable $session "$familyId.calibration" $calibration $calibrationSchema $sourceIds $provenance
    set residualColumns [dict create member_id $standardIds concentration $x residual $residuals]
    publishTable $session "$familyId.residuals" $residualColumns \
        [dict create member_id [dict create dtype string] concentration [dict create unit %] residual [dict create unit 1]] \
        $sourceIds $provenance
    set validation [dict create member_id {} known_concentration {} response {} estimated_concentration {} error {}]
    set validationReport {}
    set holdPlot {}
    foreach row $validationRows {
        lassign $row id known signal
        set estimated [expr {($signal-$intercept)/$slope}]
        set error [expr {$estimated-$known}]
        foreach {key value} [list member_id $id known_concentration $known response $signal estimated_concentration $estimated error $error] {
            dict lappend validation $key $value
        }
        lappend validationReport [list $id $known $signal $estimated $error]
        lappend holdPlot [list $known $signal $estimated]
    }
    publishTable $session "$familyId.validation" $validation \
        [dict create member_id [dict create dtype string] known_concentration [dict create unit %] \
            response [dict create unit 1] estimated_concentration [dict create unit %] error [dict create unit %]] \
        $sourceIds $provenance
    set unknownId [ini $cfg analysis_source.unknown dataset_id ""]
    set unknownReport ""; set unknownPlot {}
    if {$unknownId ne ""} {
        set unknown [correctUnknown [sourceSpectrum $session $unknownId] $blank]
        set ux [dict get $unknown x]; set uy [dict get $unknown y]
        if {[lindex $ux 0] > [lindex $ux end]} {set ux [lreverse $ux]; set uy [lreverse $uy]}
        set sampled [::GX::NumericAPIv1::interpolate $ux $uy [list $wavelength]]
        set signal [lindex [dict get $sampled yq] 0]
        set estimated [expr {($signal-$intercept)/$slope}]
        set sortedX [lsort -real $x]
        set low [lindex $sortedX 0]; set high [lindex $sortedX end]
        set rangeStatus [expr {$estimated < $low || $estimated > $high ? "outside calibration range" : "inside calibration range"}]
        publishTable $session "$familyId.unknown_result" \
            [dict create sample_id [list $unknownId] response [list $signal] estimated_concentration [list $estimated] range_status [list $rangeStatus]] \
            [dict create sample_id [dict create dtype string] response [dict create unit 1] \
                estimated_concentration [dict create unit %] range_status [dict create dtype string]] \
            [concat $sourceIds [list $unknownId]] $provenance
        set unknownReport "Dataset $unknownId: response $signal, estimated concentration $estimated wt%, $rangeStatus."
        set unknownPlot [list $estimated $signal]
    }
    # The highest-concentration measured spectrum provides a transparent
    # suggested lambda max. The analyst's chosen wavelength stays independent.
    set selectedMember ""; set topParameter -Inf
    foreach member [dict get $family members] {
        set p [dict get $member parameter_value]
        if {$p > $topParameter} {set topParameter $p; set selectedMember $member}
    }
    set peakX {}; set peakY {}
    foreach xv [dict get $selectedMember x] yv [dict get $selectedMember y] {
        if {$xv >= $peakMin && $xv <= $peakMax} {lappend peakX $xv; lappend peakY $yv}
    }
    if {[llength $peakX] < 3} {error "Peak search window has too few points"}
    if {[lindex $peakX 0] > [lindex $peakX end]} {set peakX [lreverse $peakX]; set peakY [lreverse $peakY]}
    set peaks [::GX::NumericAPIv1::findPeaks $peakX $peakY [dict create min_prominence 0.005 min_distance 5 distance_mode x]]
    set peakPosition ""; set peakHeight -Inf
    foreach px [dict get $peaks x] py [dict get $peaks heights] {
        if {$py > $peakHeight} {set peakPosition $px; set peakHeight $py}
    }
    if {$peakPosition eq ""} {error "No credible local UV/Vis maximum in the configured search interval"}
    publishTable $session "$familyId.lambda_max" \
        [dict create source_member [list [dict get $selectedMember member_id]] wavelength_nm [list $peakPosition] response [list $peakHeight]] \
        [dict create source_member [dict create dtype string] wavelength_nm [dict create unit nm] response [dict create unit 1]] \
        $sourceIds [dict merge $provenance [dict create peak_search_range "$peakMin..$peakMax nm"]]
    set standardReport {}
    foreach id $standardIds cx $x cy $y fy $fitted ry $residuals {lappend standardReport [list $id $cx $cy $fy $ry]}
    set sortedX [lsort -real $x]
    writeReport [file join $output uvvis_report.md] \
        [dict create family_dataset $familyId member_count [dict get $family member_count] \
            selected_wavelength_nm $wavelength suggested_lambda_max_nm $peakPosition \
            blank_correction $blankMode calibration_standard_count [llength $x] \
            slope_A_per_wt_percent $slope intercept_A $intercept \
            calibration_range_wt_percent "[lindex $sortedX 0]..[lindex $sortedX end]"] \
        $standardReport $validationReport $unknownReport $statistics
    set familyPlotId $familyId
    if {$blank ne ""} {
        set familyColumns [dict create member_id {} parameter_value {} spectral_x {} spectral_y {}]
        foreach member [dict get $family members] {
            foreach xv [dict get $member x] yv [dict get $member y] {
                dict lappend familyColumns member_id [dict get $member member_id]
                dict lappend familyColumns parameter_value [dict get $member parameter_value]
                dict lappend familyColumns spectral_x $xv
                dict lappend familyColumns spectral_y $yv
            }
        }
        set familyPlotId "$familyId.blank_corrected_family"
        publishTable $session $familyPlotId $familyColumns             [dict create member_id [dict create dtype string] parameter_value [dict create unit %] spectral_x [dict create unit nm semantic_role independent] spectral_y [dict create unit 1 semantic_role measured]]             $sourceIds [dict merge $provenance [dict create purpose blank_corrected_family_plot]]
    }
    set absResiduals [lmap v $residuals {expr {abs($v)}}]
    set residualStats [::GX::NumericAPIv1::statistics $absResiduals]
    set residualSpread [dict get $residualStats max]
    set validationDataset [expr {[llength $validationRows] ? "$familyId.validation" : ""}]
    set unknownDataset [expr {$unknownId ne "" ? "$familyId.unknown_result" : ""}]
    puts "FAMILY_PLOT_DATASET=$familyPlotId"
    puts "CALIBRATION_DATASET=$familyId.calibration"
    puts "RESIDUALS_DATASET=$familyId.residuals"
    puts "VALIDATION_DATASET=$validationDataset"
    puts "UNKNOWN_DATASET=$unknownDataset"
    puts "SELECTED_WAVELENGTH_NM=$wavelength"
    puts "RESIDUAL_SPREAD=$residualSpread"
    puts "PASS UV/Vis analysis: [dict get $family member_count] full spectra, [llength $x] standards, [llength $validationRows] held-out, A($wavelength)"
    puts [::GX::StatisticsV1::report $statistics {r_squared residual_standard_deviation}]
}
::UVVis::run $runtimeIni
