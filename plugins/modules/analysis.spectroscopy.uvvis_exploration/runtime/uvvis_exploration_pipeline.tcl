#!/usr/bin/env tclsh
# UV/Vis single-spectrum and elapsed-time analysis through public GX-TXT APIs.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} {error "usage: uvvis_exploration_pipeline.tcl FRAMEWORK_ROOT RUNTIME_INI"}
set framework [file normalize [lindex $argv 0]]
set runtimeIni [file normalize [lindex $argv 1]]
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1

namespace eval ::UVExplore {
    variable moduleId analysis.spectroscopy.uvvis_exploration
    variable moduleVersion 1.0.3
}
proc ::UVExplore::datasetProvenance {session datasetId} {
    set record [::GX::sessionInspectionDataset $datasetId $session]
    if {[dict exists $record provenance]} {return [dict get $record provenance]}
    return [dict create]
}
proc ::UVExplore::ini {cfg section key {default ""}} {::GX::descriptorValue $cfg $section $key $default}
proc ::UVExplore::finite {value label} {
    if {![string is double -strict $value] || [regexp -nocase {nan|inf} $value]} {error "$label must be finite"}
    return [expr {double($value)}]
}
proc ::UVExplore::choice {cfg key choices default} {
    set value [ini $cfg config $key $default]
    if {$value ni $choices} {error "Unsupported UV/Vis $key '$value'"}
    return $value
}
proc ::UVExplore::ascending {x y} {
    if {[llength $x] != [llength $y] || [llength $x] < 8} {error "UV/Vis spectrum needs eight paired samples"}
    set direction 0; set previous ""
    foreach xv $x yv $y {
        finite $xv {Wavelength}; finite $yv {Spectral response}
        if {$previous ne ""} {
            set now [expr {$xv > $previous ? 1 : ($xv < $previous ? -1 : 0)}]
            if {$now == 0 || ($direction && $now != $direction)} {error "Wavelengths must be strictly monotonic"}
            set direction $now
        }
        set previous $xv
    }
    if {$direction < 0} {return [list [lreverse $x] [lreverse $y]]}
    return [list $x $y]
}
proc ::UVExplore::sourceSpectrum {session id} {
    set handle [::GX::datasetAccessOpen $session $id]
    try {
        set meta [::GX::datasetAccessMetadata $handle]
        if {[dict get $meta contract] ne "spectrum.scientific"} {error "$id must be a scientific Spectrum"}
        set xunit ""; set yunit ""
        foreach var [dict get $meta variables] {
            switch -- [dict get $var variable_id] {
                spectral_x {set xunit [dict get $var unit]}
                spectral_y {set yunit [dict get $var unit]}
            }
        }
        if {$xunit ne "nm"} {error "$id needs wavelength in nm"}
        set provenance [datasetProvenance $session $id]
        if {![dict exists $provenance y_representation]} {error "$id lacks ordinate representation"}
        set values [::GX::datasetAccessReadVariables $handle {spectral_x spectral_y}]
        return [dict create x [dict get $values spectral_x values] y [dict get $values spectral_y values] \
            y_representation [dict get $provenance y_representation] y_unit $yunit dataset_id $id]
    } finally {::GX::datasetAccessClose $handle}
}
proc ::UVExplore::absorbance {y representation unit} {
    if {$representation eq "transmittance"} {
        set representation [expr {$unit eq "%" ? "transmittance_percent" : "transmittance_fraction"}]
    }
    set result {}
    foreach raw $y {
        set value [finite $raw {UV/Vis ordinate}]
        switch -- $representation {
            absorbance {lappend result $value}
            transmittance_fraction {
                if {$value <= 0 || $value > 1} {error "Fractional transmittance must be in (0,1]"}
                lappend result [expr {-log10($value)}]
            }
            transmittance_percent {
                if {$value <= 0 || $value > 100} {error "Percent transmittance must be in (0,100]"}
                lappend result [expr {-log10($value/100.0)}]
            }
            default {error "Unsupported UV/Vis ordinate '$representation'"}
        }
    }
    return $result
}
proc ::UVExplore::process {spectrum blank cfg} {
    lassign [ascending [dict get $spectrum x] [dict get $spectrum y]] x raw
    set original [absorbance $raw [dict get $spectrum y_representation] [dict get $spectrum y_unit]]
    set y $original
    if {$blank ne ""} {
        lassign [ascending [dict get $blank x] [dict get $blank y]] bx by
        set by [absorbance $by [dict get $blank y_representation] [dict get $blank y_unit]]
        set b [::GX::NumericAPIv1::resample $bx $by $x [dict create method linear extrapolation error]]
        set corrected {}
        foreach sample $y reference [dict get $b y] {lappend corrected [expr {$sample-$reference}]}
        set y $corrected
    }
    set baseline [choice $cfg baseline_method {none linear polynomial} none]
    if {$baseline ne "none"} {
        set y [dict get [::GX::NumericAPIv1::baseline $x $y [dict create method $baseline degree 2]] corrected]
    }
    set smooth [choice $cfg smoothing_method {none moving_mean local_polynomial savitzky_golay} none]
    if {$smooth ne "none"} {
        set window [ini $cfg config smoothing_window 9]
        if {![string is integer -strict $window] || $window < 3 || $window > 101 || $window % 2 == 0} {
            error "UV/Vis smoothing window must be odd, 3..101"
        }
        set y [dict get [::GX::NumericAPIv1::smooth $x $y \
            [dict create method $smooth window $window degree 2]] y]
    }
    set norm [choice $cfg normalization {none unit_vector mean_center_unit_vector} none]
    if {$norm ne "none"} {
        set y [dict get [::GX::NumericAPIv1::normalizeVector $y [dict create method $norm]] values]
    }
    return [dict create x $x original_absorbance $original y $y]
}
proc ::UVExplore::publish {session id contract columns schemas sourceIds provenance} {
    variable moduleId; variable moduleVersion
    set vars [dict keys $columns]
    set count [llength [dict get $columns [lindex $vars 0]]]
    foreach key $vars {if {[llength [dict get $columns $key]] != $count} {error "$id column mismatch"}}
    set definition [dict create dataset_id $id contract $contract storage auto producer_version $moduleVersion \
        source_dataset_ids $sourceIds source_variable_ids {} source [join $sourceIds {;}] \
        provenance $provenance notes {Derived UV/Vis analysis; original spectra remain unchanged.} replace_owned 1]
    set plan [::GX::datasetPublicationV2Prepare $session $moduleId $definition]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach key $vars {
            ::GX::datasetPublicationV2DeclareVariable $writer $key \
                [dict merge [dict create name $key dtype float64 dimension_ids row semantic_role derived] [dict get $schemas $key]]
        }
        if {$count} {::GX::datasetPublicationV2Append $writer row $columns}
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {::GX::datasetPublicationV2Abort $writer}
        return -options $options $message
    }
}
proc ::UVExplore::writeRows {path rows} {
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    try {foreach row $rows {puts $fd [join $row "\t"]}} finally {close $fd}
}
proc ::UVExplore::run {path} {
    variable moduleId
    set cfg [::GX::parseIni $path]
    if {[ini $cfg runtime module_id ""] ne $moduleId} {error "Wrong UV/Vis module ID"}
    set session [file normalize [ini $cfg runtime session ""]]
    set out [file normalize [ini $cfg runtime output_dir ""]]
    if {![file isdirectory $session] || ![file isdirectory $out]} {error "Session/output missing"}
    ::GX::openSessionPath $session
    set id [ini $cfg analysis_source.primary dataset_id ""]
    if {$id eq ""} {error "A UV/Vis source Dataset is required"}
    set mode [choice $cfg workflow {single_spectrum time_series} single_spectrum]
    set wavelength [finite [ini $cfg config selected_wavelength_nm 322] {Selected wavelength}]
    if {$wavelength <= 0} {error "Selected wavelength must be positive"}
    set blankMode [choice $cfg blank_correction {none subtract_blank_absorbance} none]
    set blankId [ini $cfg analysis_source.blank dataset_id ""]
    set blank ""
    if {$blankMode ne "none"} {
        if {$blankId eq ""} {error "Blank correction needs a bound Spectrum"}
        set blank [sourceSpectrum $session $blankId]
    }
    set norm [choice $cfg normalization {none unit_vector mean_center_unit_vector} none]
    set sourceIds [list $id]
    if {$blank ne ""} {lappend sourceIds $blankId}
    set provenance [dict create workflow $mode selected_wavelength_nm $wavelength \
        blank_correction $blankMode baseline_method [ini $cfg config baseline_method none] \
        smoothing_method [ini $cfg config smoothing_method none] normalization $norm \
        processing_api NUMERIC_API_v1 source_dataset_ids $sourceIds]
    if {$mode eq "single_spectrum"} {
        set source [sourceSpectrum $session $id]
        set processed [process $source $blank $cfg]
        set x [dict get $processed x]; set y [dict get $processed y]
        set raw [dict get $processed original_absorbance]
        set signal [lindex [dict get [::GX::NumericAPIv1::interpolate $x $y [list $wavelength]] yq] 0]
        set minProm [finite [ini $cfg config peak_min_prominence 0.005] {Peak prominence}]
        if {$minProm < 0} {error "Peak prominence must be nonnegative"}
        set found [::GX::NumericAPIv1::findPeaks $x $y [dict create min_prominence $minProm min_distance 5 distance_mode x]]
        set peakX [dict get $found x]; set peakY [dict get $found heights]
        set bestX ""; set bestY -Inf
        foreach px $peakX py $peakY {if {$py > $bestY} {set bestX $px; set bestY $py}}
        set responseId "$id.uvvis.selected_response"
        publish $session $responseId table.generic \
            [dict create wavelength_nm [list $wavelength] response [list $signal]] \
            [dict create wavelength_nm [dict create unit nm] response [dict create unit 1]] $sourceIds $provenance
        set processedId "$id.uvvis.processed"
        publish $session "$id.uvvis.original_absorbance" table.generic \
            [dict create wavelength_nm $x absorbance $raw] \
            [dict create wavelength_nm [dict create unit nm semantic_role independent coordinate_role coordinate] \
                absorbance [dict create unit 1 semantic_role measured coordinate_variable_ids wavelength_nm]] \
            $sourceIds [dict merge $provenance [dict create response_semantics original_absorbance_for_display]]
        if {$norm eq "none"} {
            publish $session $processedId spectrum.scientific [dict create spectral_x $x spectral_y $y] \
                [dict create spectral_x [dict create unit nm semantic_role independent coordinate_role coordinate] \
                    spectral_y [dict create unit 1 semantic_role measured coordinate_variable_ids spectral_x]] \
                $sourceIds [dict merge $provenance [dict create y_representation absorbance spectrum_kind UV_VIS]]
        } else {
            publish $session $processedId table.generic [dict create wavelength_nm $x relative_response $y] \
                [dict create wavelength_nm [dict create unit nm semantic_role independent] \
                    relative_response [dict create unit 1]] $sourceIds \
                [dict merge $provenance [dict create response_semantics normalized_relative]]
        }
        publish $session "$id.uvvis.peaks" table.generic \
            [dict create wavelength_nm $peakX response $peakY] \
            [dict create wavelength_nm [dict create unit nm] response [dict create unit 1]] $sourceIds $provenance
        set rowsA {}; set rowsB {}
        foreach xv $x rv $raw pv $y {lappend rowsA [list $xv $rv]; lappend rowsB [list $xv $pv]}
        writeRows [file join $out original_plot.tsv] $rowsA
        writeRows [file join $out processed_plot.tsv] $rowsB
        set fd [open [file join $out uvvis_exploration_report.md] w]
        puts $fd "# UV/Vis single-spectrum exploration\n\nSource: `$id`; selected wavelength: $wavelength nm; response: $signal."
        puts $fd "\nOriginal ordinate: [dict get $source y_representation]. Blank: $blankMode. Baseline: [dict get $provenance baseline_method]. Smoothing: [dict get $provenance smoothing_method]. Normalization: $norm."
        puts $fd "\nDetected peaks: [llength $peakX]. Strongest local maximum: $bestX nm (response $bestY). Original source remains unchanged."
        close $fd
        puts "PASS UV/Vis single spectrum: samples=[llength $x] peaks=[llength $peakX] A($wavelength)=$signal"
    } else {
        set family [::GX::SpectralFamilyAPIv1::readSession $session $id]
        set familyMeta [datasetProvenance $session $id]
        foreach key {spectrum_kind parameter_quantity parameter_unit y_representation} {
            if {![dict exists $familyMeta $key]} {error "Time-series family lacks $key provenance"}
        }
        set familyHandle [::GX::datasetAccessOpen $session $id]
        try {
            set familySchema [::GX::datasetAccessMetadata $familyHandle]
        } finally {::GX::datasetAccessClose $familyHandle}
        set xUnit ""; set familyUnit ""
        foreach var [dict get $familySchema variables] {
            switch -- [dict get $var variable_id] {
                spectral_x {set xUnit [dict get $var unit]}
                spectral_y {set familyUnit [dict get $var unit]}
            }
        }
        if {[dict get $familyMeta spectrum_kind] ne "UV_VIS" || $xUnit ne "nm"} {
            error "Time-series source must contain UV/Vis wavelength spectra"
        }
        if {[dict get $familyMeta parameter_quantity] ni {elapsed_time time}} {
            error "Time-series family must be parameterized by elapsed_time or time"
        }
        set familyRep [dict get $familyMeta y_representation]
        set columns [dict create member_id {} elapsed_time {} response {}]
        set processedCols [dict create member_id {} parameter_value {} spectral_x {} spectral_y {}]
        set graphRows {}
        set index 0
        foreach member [dict get $family members] {
            incr index
            set sample [dict create x [dict get $member x] y [dict get $member y] \
                y_representation $familyRep y_unit $familyUnit]
            set processed [process $sample $blank $cfg]
            set x [dict get $processed x]; set y [dict get $processed y]
            set signal [lindex [dict get [::GX::NumericAPIv1::interpolate $x $y [list $wavelength]] yq] 0]
            set t [dict get $member parameter_value]
            dict lappend columns member_id [dict get $member member_id]
            dict lappend columns elapsed_time $t
            dict lappend columns response $signal
            foreach xv $x yv $y {
                dict lappend processedCols member_id [dict get $member member_id]
                dict lappend processedCols parameter_value $t
                dict lappend processedCols spectral_x $xv
                dict lappend processedCols spectral_y $yv
                if {$index <= 12} {lappend graphRows [list $index $t $xv $yv]}
            }
        }
        set unit [dict get $familyMeta parameter_unit]
        publish $session "$id.uvvis.time_response" table.generic $columns \
            [dict create member_id [dict create dtype string] elapsed_time [dict create unit $unit] \
                response [dict create unit 1]] $sourceIds $provenance
        set processedId "$id.uvvis.processed_family"
        set contract [expr {$norm eq "none" ? "spectrum.family" : "table.generic"}]
        publish $session $processedId $contract $processedCols \
            [dict create member_id [dict create dtype string] parameter_value [dict create unit $unit] \
                spectral_x [dict create unit nm semantic_role independent coordinate_role coordinate] \
                spectral_y [dict create unit 1 semantic_role measured coordinate_variable_ids spectral_x]] \
            $sourceIds [dict merge $provenance [dict create parameter_quantity elapsed_time parameter_unit $unit spectrum_kind UV_VIS \
                y_representation [expr {$norm eq "none" ? "absorbance" : "normalized_relative"}]]]
        set timeRows {}
        foreach t [dict get $columns elapsed_time] y [dict get $columns response] {lappend timeRows [list $t $y]}
        writeRows [file join $out family_plot.tsv] $graphRows
        writeRows [file join $out time_plot.tsv] $timeRows
        set unitFile [open [file join $out time_unit.txt] w]
        puts $unitFile $unit
        close $unitFile
        set fd [open [file join $out uvvis_exploration_report.md] w]
        puts $fd "# UV/Vis elapsed-time response\n\nFamily: `$id`; [dict get $family member_count] original spectra; selected wavelength: $wavelength nm."
        puts $fd "\nElapsed-time unit: $unit. Blank: $blankMode. Baseline: [dict get $provenance baseline_method]. Smoothing: [dict get $provenance smoothing_method]. Normalization: $norm."
        puts $fd "\nIndividual time points remain in the canonical response Dataset. The processed family is a separate derived Dataset. No kinetic model or reaction-rate claim is made."
        close $fd
        puts "PASS UV/Vis time series: spectra=[dict get $family member_count] wavelength=$wavelength unit=$unit"
    }
}
::UVExplore::run $runtimeIni
