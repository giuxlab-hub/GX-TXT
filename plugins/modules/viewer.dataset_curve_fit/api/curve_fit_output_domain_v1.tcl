# Owned fitted-output domain flags. Numeric computes the masks; this layer
# validates shape/identity and adapts bounded resources for public consumers.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_outputDomainAttach {report} {
    set n [dict get $report output_n];set outside [dict get $report output_extrapolated_count]
    if {![string is entier -strict $n]||$n<2||![string is entier -strict $outside]||$outside<0||$outside>$n} {error {Invalid fitted-output domain counts}}
    dict set report output_domain [dict create schema gxtxt.fit_output_domain.v1 status value row_count $n outside_count $outside reference_domain [dict get $report training_domain] reference_basis [dict get $report training_domain_basis] boundary_policy closed_training_envelope intrinsic_policy checked_by_model_evaluator coordinate_space original_independent_or_normalized_parameter]
    return $report
}
proc ::GX::DatasetCurveFit::_outputDomainImport {report directory document} {
    set path [file join $directory output_domain.bin];set n [dict get $report output_n]
    if {[file size $path]!=16*$n} {error {Fitted-output domain rows differ from geometry}}
    if {$document ne {}} {
        dict set report output_domain_resource [::GX::interactiveDocumentResourceImportNumeric $document $path [dict create format float64_interleaved_le columns {fit_query is_extrapolated} row_count $n role fitted_output_domain]]
    } else {
        # Standalone built-in samples have no Document owner and at most10000
        # output points. Canonical Dataset paths always use owned resources.
        if {$n>10000} {error {Unowned fitted-output domain exceeds the bounded sample limit}}
        set f [::open $path rb];try {binary scan [read $f] q* values} finally {::close $f}
        dict set report output_domain_values $values
    }
    return [_outputDomainAttach $report]
}
proc ::GX::DatasetCurveFit::_outputDomainInfo {report} {
    if {![dict exists $report output_domain]} {return {}}
    set info [dict get $report output_domain]
    if {[dict get $info schema] ne "gxtxt.fit_output_domain.v1"||[dict get $info status] ne "value"||[dict get $info row_count]!=[dict get $report output_n]||[dict get $info reference_domain] ne [dict get $report training_domain]||[dict get $info reference_basis] ne [dict get $report training_domain_basis]||[dict get $info boundary_policy] ne "closed_training_envelope"||[dict get $info intrinsic_policy] ne "checked_by_model_evaluator"||[dict get $info coordinate_space] ne "original_independent_or_normalized_parameter"} {error {Fitted-output domain receipt differs from its accepted model}}
    set n [dict get $info row_count];set outside [dict get $info outside_count]
    if {![string is entier -strict $n]||$n<2||![string is entier -strict $outside]||$outside<0||$outside>$n||$outside!=[dict get $report output_extrapolated_count]} {error {Invalid fitted-output domain count}}
    if {[dict exists $report output_domain_resource]} {
        set resource [::GX::interactiveDocumentResourceInfo [dict get $report output_domain_resource]]
        if {[dict get $resource size_bytes]!=16*$n||[dict get $resource metadata columns] ne {fit_query is_extrapolated}||[dict get $resource metadata row_count]!=$n||[dict get $resource metadata format] ne "float64_interleaved_le"||[dict get $resource metadata role] ne "fitted_output_domain"} {error {Fitted-output domain resource shape differs}}
    } elseif {![dict exists $report output_domain_values]||[llength [dict get $report output_domain_values]]!=2*$n||$n>10000} {error {Fitted-output domain values are absent or outside their bound}}
    if {[dict get $report parametric]} {dict set info query_unit 1} elseif {[dict exists $report translation u unit]} {dict set info query_unit [dict get $report translation u unit]} else {dict set info query_unit {}}
    return $info
}
proc ::GX::DatasetCurveFit::_outputDomainPage {report start count} {
    set info [_outputDomainInfo $report];if {$info eq {}} {return {}}
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$count<1||$count>65536||$start+$count>[dict get $info row_count]} {error {Fitted-output domain page is outside its bounded range}}
    if {[dict exists $report output_domain_resource]} {
        binary scan [::GX::interactiveDocumentResourceReadChunk [dict get $report output_domain_resource] [expr {16*$start}] [expr {16*$count}]] q* values
    } else {set values [lrange [dict get $report output_domain_values] [expr {2*$start}] [expr {2*($start+$count)-1}]]}
    return [_outputDomainDecode $values $count]
}
proc ::GX::DatasetCurveFit::_outputDomainDecode {values count} {
    if {[llength $values]!=2*$count} {error {Incomplete fitted-output domain page}}
    set query {};set flags {}
    foreach {q flag} $values {
        lappend query [_finite $q {Fitted output query}]
        if {$flag ni {0 1 0.0 1.0}} {error {Invalid fitted-output extrapolation flag}}
        lappend flags [expr {int($flag)}]
    }
    return [dict create fit_query $query is_extrapolated $flags]
}
proc ::GX::DatasetCurveFit::_outputDomainNext {report reader start count} {
    if {$reader eq {}} {return [_outputDomainPage $report $start $count]}
    set chunk [::GX::interactiveDocumentResourceNext $reader [expr {16*$count}]]
    binary scan [dict get $chunk bytes] q* values
    return [_outputDomainDecode $values $count]
}
proc ::GX::DatasetCurveFit::_outputDomainFlags {report indices} {
    set info [_outputDomainInfo $report]
    if {$info eq {}||[llength $indices]>65536} {error {Missing or over-budget fitted-output display binding}}
    set ranges {}
    foreach index $indices {
        if {![string is entier -strict $index]||$index<0||$index>=[dict get $info row_count]} {error {Display index differs from the exact fitted output}}
        lappend ranges [list [expr {16*$index+8}] 8]
    }
    set flags {}
    if {[dict exists $report output_domain_resource]} {
        foreach bytes [::GX::interactiveDocumentResourceReadRanges [dict get $report output_domain_resource] $ranges] {binary scan $bytes q flag;lappend flags $flag}
    } else {foreach index $indices {lappend flags [lindex [dict get $report output_domain_values] [expr {2*$index+1}]]}}
    foreach flag $flags {if {$flag ni {0 1 0.0 1.0}} {error {Invalid fitted-output display flag}}}
    return $flags
}
proc ::GX::DatasetCurveFit::_outputDomainDraw {canvas object report background tags} {
    if {$object eq {}} return
    set info [_outputDomainInfo $report]
    if {$info eq {}||[dict get $info outside_count]==0} {::GX::native2DCanvasDrawObject $canvas $object $background $tags;return}
    set flags [_outputDomainFlags $report [dict get $object point_indices]]
    set grouped [dict create 0 {} 1 {}];set markers [dict create 0 {} 1 {}];set offset 0
    foreach path [dict get $object paths] {
        set active {};set current -1;set prior {}
        foreach point $path {
            set flag [lindex $flags $offset];incr offset
            dict lappend markers [expr {int($flag)}] [list $point]
            if {$prior ne {}} {
                set outside [expr {$priorFlag||$flag}]
                if {$outside!=$current} {
                    if {[llength $active]>1} {dict lappend grouped $current $active}
                    set active [list $prior];set current $outside
                }
                lappend active $point
            }
            set prior $point;set priorFlag $flag
        }
        if {[llength $active]>1} {dict lappend grouped $current $active}
    }
    if {$offset!=[llength $flags]} {error {Display paths lost their exact output indices}}
    foreach outside {0 1} {
        set copy $object;dict set copy paths [dict get $grouped $outside]
        # Shared segment endpoints must not duplicate scientific point markers.
        # Direction markers remain on the original-style pass exactly once.
        dict set copy style marker 0
        if {$outside} {dict unset copy marker;dict unset copy part_markers}
        if {$outside} {dict set copy style line_style 1;dict set copy style color {0.92 0.42 0.05 1}}
        ::GX::native2DCanvasDrawObject $canvas $copy $background [concat $tags [list [expr {$outside?"extrapolated_output":"interpolated_output"}]]]
        if {[dict get $object style marker]!=0} {
            dict set copy paths [dict get $markers $outside]
            dict set copy style marker [dict get $object style marker]
            dict unset copy marker;dict unset copy part_markers
            ::GX::native2DCanvasDrawObject $canvas $copy $background [concat $tags [list [expr {$outside?"extrapolated_output_point":"interpolated_output_point"}]]]
        }
    }
}
proc ::GX::DatasetCurveFit::_outputDomainPreviewDraw {w canvas report background} {
    set points [dict get $report fitted];set screen {};foreach point $points {lassign $point x y;lappend screen [_screen $w $x $y]}
    set indices [::GX::datasetPublicationV2DictDefault $report fitted_indices {}]
    if {$indices eq {}} {for {set i 0} {$i<[llength $points]} {incr i} {lappend indices $i}}
    set paths {};set start 0
    foreach cut [::GX::datasetPublicationV2DictDefault $report fitted_breaks {}] {lappend paths [lrange $screen $start $cut];set start [expr {$cut+1}]}
    lappend paths [lrange $screen $start end]
    set object [dict create id preview kind curve paths $paths point_indices $indices style {color {0.09 0.64 0.29 1} line_width 2.5 line_style 1 marker 0}]
    _outputDomainDraw $canvas $object $report $background preview_curve
}
