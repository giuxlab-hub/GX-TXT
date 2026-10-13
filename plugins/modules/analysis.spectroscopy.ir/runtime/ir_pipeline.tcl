#!/usr/bin/env tclsh
# Scientific IR workflow; all Dataset, reference and numerical access uses public APIs.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} { error "usage: ir_pipeline.tcl FRAMEWORK_ROOT RUNTIME_INI" }
set framework [file normalize [lindex $argv 0]]
set runtimeIni [file normalize [lindex $argv 1]]
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1

namespace eval ::IR {
    variable moduleId analysis.spectroscopy.ir
    variable moduleVersion 1.1.2
    variable numeric ::GX::NumericAPIv1
    variable references ::GX::ReferenceLibraryAPIv1
}

proc ::IR::ini {cfg section key {default ""}} {
    return [::GX::descriptorValue $cfg $section $key $default]
}
proc ::IR::number {cfg key default min max} {
    set raw [ini $cfg config $key $default]
    if {![string is double -strict $raw] || [regexp -nocase {nan|inf} $raw]} {
        error "IR configuration $key must be finite numeric"
    }
    set value [expr {double($raw)}]
    if {$value < $min || $value > $max} { error "IR configuration $key is outside $min..$max" }
    return $value
}
proc ::IR::choice {cfg key options default} {
    set value [ini $cfg config $key $default]
    if {$value ni $options} { error "IR configuration $key has unsupported value '$value'" }
    return $value
}
proc ::IR::bindingName {binding} {
    set parts [split [string trim $binding] .]
    return [lindex $parts end]
}
proc ::IR::variableForBinding {variables binding} {
    set wanted [bindingName $binding]
    foreach variable $variables {
        set name [expr {[dict exists $variable name] ? [dict get $variable name] : ""}]
        set canonical [expr {[dict exists $variable canonical] ? [dict get $variable canonical] : ""}]
        if {[dict get $variable variable_id] eq $wanted || $name eq $wanted || $canonical eq $wanted} {
            return $variable
        }
    }
    error "IR binding '$binding' did not resolve to a stable variable_id"
}
proc ::IR::readExperimental {session datasetId xBinding yBinding} {
    set handle [::GX::datasetAccessOpen $session $datasetId]
    try {
        set meta [::GX::datasetAccessMetadata $handle]
        if {![::GX::contractSatisfies [dict get $meta contract] table.generic]} {
            error "IR source must be a numeric table Dataset"
        }
        set xVar [variableForBinding [dict get $meta variables] $xBinding]
        set yVar [variableForBinding [dict get $meta variables] $yBinding]
        set xId [dict get $xVar variable_id]
        set yId [dict get $yVar variable_id]
        if {$xId eq $yId} { error "IR X and Y must be distinct stable variables" }
        set xUnit [string trim [dict get $xVar unit]]
        if {$xUnit ni {cm^-1 1/cm cm-1}} { error "IR spectral coordinate must be wavenumber in cm^-1; got '$xUnit'" }
        set result [::GX::datasetAccessReadVariables $handle [list $xId $yId]]
        set x [dict get $result $xId values]
        set y [dict get $result $yId values]
        if {[llength $x] != [llength $y] || [llength $x] < 8} { error "IR source must have at least 8 paired samples" }
        set metadata [dict create]
        if {![catch {set metadata [::GX::datasetMetadataRead $session $datasetId]}]} {
            if {[catch {dict size $metadata}]} { set metadata [dict create] }
        }
        return [dict create x $x y $y x_id $xId y_id $yId x_unit $xUnit y_unit [dict get $yVar unit] metadata $metadata]
    } finally {
        ::GX::datasetAccessClose $handle
    }
}
proc ::IR::strictAscending {x y} {
    variable numeric
    if {[llength $x] != [llength $y] || [llength $x] < 2} { error "IR X/Y length mismatch" }
    foreach yv $y {
        if {![string is double -strict $yv] || [regexp -nocase {nan|inf} $yv]} { error "IR source contains non-finite samples" }
    }
    set info [${numeric}::validateMonotonic $x]
    if {![dict get $info strict_monotonic]} { error "IR X must be strictly monotonic without duplicate coordinates" }
    set direction [dict get $info direction]
    if {$direction eq "decreasing"} { return [list [lreverse $x] [lreverse $y]] }
    if {$direction ne "increasing"} { error "IR X monotonic direction is unsupported: $direction" }
    return [list $x $y]
}
proc ::IR::absorptionProxy {y representation} {
    set out {}
    if {$representation eq "relative_transmission_signal" || $representation eq "transmission_signal"} {
        variable numeric
        set stats [${numeric}::statistics $y]
        set maximum [dict get $stats max]
        foreach value $y { lappend out [expr {$maximum-double($value)}] }
        return $out
    }
    foreach value $y {
        set value [expr {double($value)}]
        switch -- $representation {
            absorbance { lappend out $value }
            absorption_index {
                if {$value < 0} { error "absorption index must be nonnegative" }
                lappend out $value
            }
            transmittance_fraction {
                if {$value <= 0 || $value > 1} { error "transmittance fraction must be in (0,1]" }
                lappend out [expr {-log10($value)}]
            }
            transmittance_percent {
                if {$value <= 0 || $value > 100} { error "percent transmittance must be in (0,100]" }
                lappend out [expr {-log10($value/100.0)}]
            }
            default { error "unsupported IR intensity representation '$representation'" }
        }
    }
    return $out
}
proc ::IR::process {x y representation cfg} {
    variable numeric
    lassign [strictAscending $x $y] x y
    set y [absorptionProxy $y $representation]
    set lo [number $cfg range_min_cm1 500 0 100000]
    set hi [number $cfg range_max_cm1 3700 0 100000]
    if {$hi <= $lo} { error "IR spectral range must have max > min" }
    set xx {}; set yy {}
    foreach xv $x yv $y {
        if {$xv >= $lo && $xv <= $hi} { lappend xx $xv; lappend yy $yv }
    }
    if {[llength $xx] < 8} { error "IR selected range has fewer than 8 samples" }
    set x $xx; set y $yy
    set baseline [choice $cfg baseline_method {none linear polynomial} none]
    if {$baseline ne "none"} {
        set options [dict create method $baseline]
        if {$baseline eq "polynomial"} {
            set degree [number $cfg baseline_degree 2 0 8]
            dict set options degree [expr {int($degree)}]
        }
        set result [${numeric}::baseline $x $y $options]
        set y [dict get $result corrected]
    }
    set smoothing [choice $cfg smoothing_method {none moving_mean local_polynomial savitzky_golay} none]
    if {$smoothing ne "none"} {
        set window [number $cfg smoothing_window 9 1 101]
        set window [expr {int($window)}]
        if {$window % 2 == 0} { error "IR smoothing window must be odd" }
        set result [${numeric}::smooth $x $y [dict create method $smoothing window $window degree 2]]
        set y [dict get $result y]
    }
    set derivative [number $cfg derivative_order 0 0 2]
    set derivative [expr {int($derivative)}]
    for {set i 0} {$i < $derivative} {incr i} {
        set result [${numeric}::differentiate $x $y]
        set y [dict get $result dy_dx]
    }
    set norm [choice $cfg normalization {unit_vector mean_center_unit_vector} mean_center_unit_vector]
    set normalized [${numeric}::normalizeVector $y [dict create method $norm]]
    set y [dict get $normalized values]
    return [dict create x $x y $y representation absorption_proxy x_ordering ascending]
}
proc ::IR::score {a b method} {
    variable numeric
    set apiMethod $method
    if {$method eq "spectral_angle"} { set apiMethod angular_similarity }
    if {[catch {set result [${numeric}::vectorSimilarity $a $b [dict create method $apiMethod]]}]} { return -1.0 }
    return [dict get $result score]
}
proc ::IR::peakOverlap {experimental reference tolerance} {
    set ex [dict get $experimental x]
    set ref [dict get $reference x]
    if {![llength $ex] || ![llength $ref]} { return 0.0 }
    set matched 0
    foreach center $ex {
        foreach candidate $ref {
            if {abs($center-$candidate) <= $tolerance} { incr matched; break }
        }
    }
    return [expr {$matched/double([llength $ex])}]
}

proc ::IR::publishTable {session datasetId contract columns schemas sourceId sourceVars provenance} {
    variable moduleId
    variable moduleVersion
    set ids [dict keys $columns]
    if {![llength $ids]} { error "IR output Dataset requires columns" }
    set n [llength [dict get $columns [lindex $ids 0]]]
    foreach id $ids {
        if {[llength [dict get $columns $id]] != $n} { error "IR output column length mismatch: $id" }
    }
    set definition [dict create dataset_id $datasetId contract $contract storage auto \
        producer_version $moduleVersion source_dataset_ids [list $sourceId] \
        source_variable_ids $sourceVars source $sourceId provenance $provenance \
        notes {Derived IR output; source Dataset and reference libraries remain unchanged.} \
        replace_owned 1]
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
            if {$written != $n} { error "IR output Dataset '$datasetId' incomplete write" }
        }
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {::GX::datasetPublicationV2Abort $writer}
        return -options $options $message
    }
}
proc ::IR::report {path details peaks candidates} {
    set f [open $path w]
    fconfigure $f -encoding utf-8 -translation lf
    try {
        puts $f "GX-TXT IR Spectroscopy and Reference Matching 1.1.2"
        puts $f "This report ranks spectral similarities; it does not prove chemical identity."
        puts $f "Version 1.0 assumes one dominant component; mixture deconvolution is unsupported."
        puts $f ""
        dict for {key value} $details { puts $f "$key: $value" }
        puts $f ""
        puts $f "Detected peaks (wavenumber cm^-1, relative height, prominence, width cm^-1):"
        foreach peak $peaks {
            puts $f "[dict get $peak wavenumber]\t[dict get $peak intensity]\t[dict get $peak prominence]\t[dict get $peak width]"
        }
        puts $f ""
        puts $f "Ranked reference candidates (scores are not probabilities):"
        foreach candidate $candidates {
            puts $f "[dict get $candidate rank]\t[dict get $candidate library_id]\t[dict get $candidate library_version]\t[dict get $candidate library_content_hash]\t[dict get $candidate spectrum_id]\t[dict get $candidate material_name]\t[dict get $candidate match_score]\t[dict get $candidate warning]"
        }
    } finally { close $f }
}

proc ::IR::run {configPath} {
    variable moduleId
    variable numeric
    variable references
    set cfg [::GX::parseIni $configPath]
    if {[ini $cfg runtime module_id ""] ne $moduleId} { error "IR runtime module ID mismatch" }
    set session [file normalize [ini $cfg runtime session ""]]
    set outputDir [file normalize [ini $cfg runtime output_dir ""]]
    if {![file isdirectory $session] || ![file isdirectory $outputDir]} { error "IR runtime Session/output directory is missing" }
    ::GX::openSessionPath $session
    set datasetId [ini $cfg analysis_source.primary dataset_id [ini $cfg dataset id ""]]
    if {$datasetId eq ""} { error "IR Analysis Source Dataset ID is missing" }
    set xBinding [ini $cfg bindings spectral_x ""]
    set yBinding [ini $cfg bindings spectral_y ""]
    if {$xBinding eq "" || $yBinding eq ""} { error "IR X/Y bindings are required" }
    set experimental [readExperimental $session $datasetId $xBinding $yBinding]
    set xId [dict get $experimental x_id]
    set yId [dict get $experimental y_id]
    set intensity [choice $cfg intensity_representation \
        {absorbance absorption_index transmittance_fraction transmittance_percent relative_transmission_signal} absorbance]
    set processed [process [dict get $experimental x] [dict get $experimental y] $intensity $cfg]
    set px [dict get $processed x]
    set py [dict get $processed y]
    set method [choice $cfg matching_method {cosine pearson spectral_angle normalized_residual} cosine]
    set lo [number $cfg range_min_cm1 500 0 100000]
    set hi [number $cfg range_max_cm1 3700 0 100000]
    set step [number $cfg resample_step_cm1 4 0.01 1000]
    set fpMin [number $cfg fingerprint_min_cm1 500 0 100000]
    set fpMax [number $cfg fingerprint_max_cm1 1500 0 100000]
    if {$fpMax <= $fpMin} { error "IR fingerprint range must have max > min" }
    set fpWeight [number $cfg fingerprint_weight 0.35 0 1]
    set minProm [number $cfg peak_min_prominence 0.03 0 100000]
    set peakTolerance [number $cfg peak_tolerance_cm1 16 0 10000]
    set topN [number $cfg top_n 10 1 100]
    if {$topN != int($topN)} { error "IR top_n must be an integer" }
    set threshold [number $cfg minimum_match_score 0.6 -1 1]
    set libraryIds [split [ini $cfg config reference_library_ids tum.refimp.ftir.2022] {;}]
    set libraryIds [lmap id $libraryIds {string trim $id}]
    set libraryIds [lsearch -all -inline -not -exact $libraryIds ""]
    if {![llength $libraryIds]} { error "IR requires at least one installed reference library" }
    set libraryIds [lsort -unique $libraryIds]
    set libraryFingerprints [dict create]
    foreach libraryId $libraryIds {
        ${references}::validateLibrary $libraryId
        set info [${references}::libraryInfo $libraryId]
        dict set libraryFingerprints $libraryId [dict create version [dict get $info version] content_hash [dict get $info content_hash]]
    }
    set peakResult [${numeric}::findPeaks $px $py \
        [dict create min_prominence $minProm min_distance $peakTolerance distance_mode x]]
    set peaks {}
    foreach center [dict get $peakResult x] height [dict get $peakResult heights] \
        prominence [dict get $peakResult prominences] width [dict get $peakResult widths] {
        lappend peaks [dict create peak_id [expr {[llength $peaks]+1}] wavenumber $center \
            intensity $height prominence $prominence width $width]
    }
    set candidates {}
    set skipped 0
    set usedBulk 0
    set expMetadata [dict get $experimental metadata]
    foreach libraryId $libraryIds {
        set libInfo [dict get $libraryFingerprints $libraryId]
        set spectrumIds [${references}::listSpectra $libraryId]
        if {[llength $spectrumIds] > 100 &&
            [ini $cfg config baseline_method none] eq "none" &&
            [ini $cfg config smoothing_method none] eq "none" &&
            [ini $cfg config derivative_order 0] == 0} {
            set limit [expr {min([llength $spectrumIds],max(30,int($topN)*3))}]
            set fast [${references}::bulkRank $libraryId [dict create x $px y $py] [dict create \
                experimental_representation $intensity range_min $lo range_max $hi \
                normalization [ini $cfg config normalization mean_center_unit_vector] \
                step $step method $method fingerprint_min $fpMin fingerprint_max $fpMax \
                fingerprint_weight $fpWeight limit $limit]]
            if {[dict get $fast scanned] != [llength $spectrumIds]} {
                error "IR CORE bulk rank scanned a different reference count"
            }
            incr skipped [dict get $fast skipped]
            set spectrumIds [lmap item [dict get $fast candidates] {dict get $item spectrum_id}]
            set usedBulk 1
        }
        foreach spectrumId $spectrumIds {
            set reference [${references}::readSpectrum $libraryId $spectrumId]
            if {[dict get $reference spectrum_kind] ne "IR" || [dict get $reference x_unit] ne "cm^-1"} {
                incr skipped; continue
            }
            set rep [dict get $reference y_representation]
            if {$rep ni {absorbance absorption_index transmittance transmittance_fraction transmittance_percent relative_transmission_signal transmission_signal}} {
                incr skipped; continue
            }
            # The imaginary refractive-index component k is a different
            # physical ordinate from absorbance or transmission. Compare it
            # only with another k trace, even though all are positive peaks.
            if {($intensity eq "absorption_index") != ($rep eq "absorption_index")} {
                incr skipped; continue
            }
            if {$rep eq "transmittance"} {
                set rep [expr {[dict get $reference y_unit] eq "%" ? "transmittance_percent" : "transmittance_fraction"}]
            }
            if {[catch {set refProcessed [process [dict get $reference x] [dict get $reference y] $rep $cfg]} problem]} {
                incr skipped; continue
            }
            set rx [dict get $refProcessed x]; set ry [dict get $refProcessed y]
            set common [${numeric}::commonRange $px $rx]
            if {![dict get $common overlap]} { incr skipped; continue }
            set commonMin [dict get $common min]
            set commonMax [dict get $common max]
            set gridResult [${numeric}::uniformGrid $commonMin $commonMax $step]
            set target [dict get $gridResult x]
            set targetCount [llength $target]
            if {$targetCount < 16} { incr skipped; continue }
            if {$targetCount > 20000} { error "IR matching grid exceeds 20,000 samples; increase spacing" }
            set exGrid [dict get [${numeric}::resample $px $py $target [dict create method linear]] y]
            set refGrid [dict get [${numeric}::resample $rx $ry $target [dict create method linear]] y]
            set fullScore [score $exGrid $refGrid $method]
            set exFp {}; set refFp {}
            foreach x $target a $exGrid b $refGrid {
                if {$x >= $fpMin && $x <= $fpMax} { lappend exFp $a; lappend refFp $b }
            }
            set fingerprintScore [expr {[llength $exFp] >= 16 ? [score $exFp $refFp $method] : $fullScore}]
            set combined [expr {(1.0-$fpWeight)*$fullScore+$fpWeight*$fingerprintScore}]
            set entityName [dict get $reference entity_id]
            set entity [dict create]
            if {$entityName ne ""} {
                if {![catch {set entity [${references}::entityInfo $libraryId $entityName]}]} {
                    foreach key {compound_name display_name name} {
                        if {[dict exists $entity $key] && [dict get $entity $key] ne ""} {
                            set entityName [dict get $entity $key]; break
                        }
                    }
                }
            }
            set warning ""
            set refMeta [dict get $reference metadata]
            foreach key {phase method} {
                if {[dict exists $expMetadata $key] && [dict exists $refMeta $key] &&
                    [dict get $expMetadata $key] ne [dict get $refMeta $key]} {
                    append warning "$key mismatch; "
                }
            }
            if {$rep eq "relative_transmission_signal" || $rep eq "transmission_signal"} {
                append warning "reference uses relative transmission signal; "
            }
            set refPeaks [${numeric}::findPeaks $rx $ry \
                [dict create min_prominence $minProm min_distance $peakTolerance distance_mode x]]
            set overlap [peakOverlap $peakResult $refPeaks $peakTolerance]
            lappend candidates [dict create library_id $libraryId library_version [dict get $libInfo version] \
                library_content_hash [dict get $libInfo content_hash] entity_id [dict get $reference entity_id] \
                spectrum_id $spectrumId material_name $entityName match_score $combined \
                full_spectrum_score $fullScore fingerprint_score $fingerprintScore \
                peak_overlap_score $overlap range_used "$commonMin..$commonMax cm^-1" \
                warning [string trim $warning] plot_x $target plot_experimental $exGrid plot_reference $refGrid]
        }
    }
    set candidates [lsort -command ::IR::candidateCompare $candidates]
    set candidates [lrange $candidates 0 [expr {int($topN)-1}]]
    set rank 0
    set ranked {}
    foreach item $candidates {
        dict set item rank [incr rank]
        lappend ranked $item
    }
    set candidates $ranked
    set status [expr {![llength $candidates] || [dict get [lindex $candidates 0] match_score] < $threshold ? "no convincing library match" : "candidate matches available"}]
    set provenance [dict create source_dataset_id $datasetId x_variable_id $xId y_variable_id $yId \
        intensity_representation $intensity baseline_method [ini $cfg config baseline_method none] \
        smoothing_method [ini $cfg config smoothing_method none] \
        normalization [ini $cfg config normalization mean_center_unit_vector] \
        derivative_order [ini $cfg config derivative_order 0] \
        matching_method $method fingerprint_region "$fpMin..$fpMax cm^-1" \
        fingerprint_weight $fpWeight peak_tolerance_cm1 $peakTolerance \
        reference_libraries $libraryIds reference_library_fingerprints $libraryFingerprints \
        matching_engine [expr {$usedBulk ? "CORE bulk prescreen plus exact public-API top candidates" : "exact public-API per reference"}] \
        identification_status $status]
    set base [regsub -all {[^A-Za-z0-9._-]} $datasetId _]
    set processedId "$base.ir.processed"
    set peaksId "$base.ir.peaks"
    set candidatesId "$base.ir.candidates"
    publishTable $session $processedId spectrum.scientific \
        [dict create wavenumber $px processed_intensity $py] \
        [dict create wavenumber [dict create unit cm^-1 semantic_role independent coordinate_role coordinate] \
            processed_intensity [dict create unit 1 semantic_role derived coordinate_variable_ids wavenumber]] \
        $datasetId [list $xId $yId] $provenance
    set peakColumns [dict create peak_id {} wavenumber {} intensity {} prominence {} width {}]
    foreach item $peaks {
        foreach key [dict keys $peakColumns] { dict lappend peakColumns $key [dict get $item $key] }
    }
    set peakSchema [dict create peak_id [dict create dtype int32] \
        wavenumber [dict create unit cm^-1] intensity [dict create unit 1] \
        prominence [dict create unit 1] width [dict create unit cm^-1]]
    publishTable $session $peaksId table.generic $peakColumns $peakSchema \
        $datasetId [list $xId $yId] $provenance
    set candidateKeys {rank library_id library_version library_content_hash entity_id spectrum_id material_name match_score full_spectrum_score fingerprint_score peak_overlap_score range_used warning}
    set candidateColumns [dict create]
    set candidateSchemas [dict create]
    foreach key $candidateKeys {
        dict set candidateColumns $key {}
        if {$key in {library_id library_version library_content_hash entity_id spectrum_id material_name range_used warning}} {
            dict set candidateSchemas $key [dict create dtype string]
        } elseif {$key eq "rank"} {
            dict set candidateSchemas $key [dict create dtype int32]
        } else { dict set candidateSchemas $key [dict create dtype float64] }
    }
    foreach item $candidates {
        foreach key $candidateKeys { dict lappend candidateColumns $key [dict get $item $key] }
    }
    publishTable $session $candidatesId table.generic $candidateColumns $candidateSchemas \
        $datasetId [list $xId $yId] $provenance
    set details [dict create experimental_dataset $datasetId x_variable_id $xId y_variable_id $yId \
        source_metadata $expMetadata intensity_representation $intensity \
        processing_configuration $provenance \
        matching_method $method reference_libraries $libraryIds \
        processed_dataset $processedId peaks_dataset $peaksId candidates_dataset $candidatesId \
        fingerprint_region "$fpMin..$fpMax cm^-1" grid_step_cm1 $step \
        candidate_count [llength $candidates] skipped_references $skipped identification_status $status]
    report [file join $outputDir ir_analysis_report.txt] $details $peaks $candidates
    set overlayId "$base.ir.overlay"
    set overlayProvenance [dict merge $provenance [dict create purpose plot_dataset_overlay]]
    set overlayColumns [dict create]
    set overlaySchemas [dict create]
    set hasReference 0
    if {[llength $candidates]} {
        set best [lindex $candidates 0]
        dict set overlayColumns wavenumber [dict get $best plot_x]
        dict set overlayColumns experimental_intensity [dict get $best plot_experimental]
        dict set overlayColumns reference_intensity [dict get $best plot_reference]
        dict set overlaySchemas wavenumber [dict create unit cm^-1 semantic_role independent coordinate_role coordinate]
        dict set overlaySchemas experimental_intensity [dict create unit 1 semantic_role derived coordinate_variable_ids wavenumber]
        dict set overlaySchemas reference_intensity [dict create unit 1 semantic_role reference coordinate_variable_ids wavenumber]
        dict set overlayProvenance best_reference_library_id [dict get $best library_id]
        dict set overlayProvenance best_reference_library_version [dict get $best library_version]
        dict set overlayProvenance best_reference_library_content_hash [dict get $best library_content_hash]
        dict set overlayProvenance best_reference_spectrum_id [dict get $best spectrum_id]
        set hasReference 1
    } else {
        dict set overlayColumns wavenumber $px
        dict set overlayColumns experimental_intensity $py
        dict set overlaySchemas wavenumber [dict create unit cm^-1 semantic_role independent coordinate_role coordinate]
        dict set overlaySchemas experimental_intensity [dict create unit 1 semantic_role derived coordinate_variable_ids wavenumber]
    }
    publishTable $session $overlayId spectrum.scientific $overlayColumns $overlaySchemas \
        $datasetId [list $xId $yId] $overlayProvenance
    puts "OVERLAY_DATASET=$overlayId"
    puts "HAS_REFERENCE=$hasReference"
    puts "PASS IR analysis: $status; [llength $peaks] peaks; [llength $candidates] candidates"
}
proc ::IR::candidateCompare {a b} {
    set av [dict get $a match_score]
    set bv [dict get $b match_score]
    if {$av > $bv} { return -1 }
    if {$av < $bv} { return 1 }
    return [string compare [dict get $a spectrum_id] [dict get $b spectrum_id]]
}

::IR::run $runtimeIni
