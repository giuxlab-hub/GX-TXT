# Exact row-stage receipt; CORE owns transport and Numeric owns model decisions.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_preprocessingCapture {document input training known policy} {
    set receipt [dict get $input preprocessing]
    if {[dict get $receipt schema] ne "gxtxt.curve_source_preprocessing.v1"||[dict get $policy schema] ne "gxtxt.fit_input_policy.v1"} {error {Unsupported captured preprocessing contract}}
    dict set receipt schema gxtxt.fit_preprocessing.v1
    dict set receipt status value
    dict set receipt model_policy $policy
    set result {};set stages {}
    foreach {stage pathField countField} {input input_source_rows_file filtered_count nonfinite nonfinite_source_rows_file nonfinite_count unselected unselected_source_rows_file selection_excluded_count} {
        if {$stage eq "input"&&[dict get $receipt nonfinite_count]==0} {dict set stages input source_rows_resource;continue}
        set n [dict get $receipt $countField];set path [dict get $input $pathField]
        if {[file size $path]!=8*$n} {error {Preprocessing row audit shape differs from its CORE count}}
        set field preprocessing_${stage}_rows_resource
        dict set result $field [::GX::interactiveDocumentResourceImportNumeric $document $path [dict create format uint64_le columns {source_row_ordinal} row_count $n role preprocessing_$stage]]
        dict set stages $stage $field
    }
    foreach {stage field} {finite source_rows_resource fit comparison_rows_resource model preprocessing_model_rows_resource} {
        if {![dict exists $known $field]} {error "Preprocessing requires exact $stage row identity"}
        dict set result $field [dict get $known $field];dict set stages $stage $field
    }
    if {[dict get $training source_rows_file] eq [dict get $input source_rows_file]} {
        dict set stages selected source_rows_resource
    } else {
        set n [dict get $receipt selected_count];set path [dict get $training source_rows_file]
        if {[file size $path]!=8*$n} {error {Selected preprocessing rows lost their captured count}}
        dict set result preprocessing_selected_rows_resource [::GX::interactiveDocumentResourceImportNumeric $document $path [dict create format uint64_le columns {source_row_ordinal} row_count $n role preprocessing_selected]]
        dict set stages selected preprocessing_selected_rows_resource
    }
    if {[dict exists $known preprocessing_region_rows_resource]} {
        dict set result preprocessing_region_rows_resource [dict get $known preprocessing_region_rows_resource]
        dict set stages region preprocessing_region_rows_resource
        dict set receipt region_count [dict get [dict get $known preprocessing_region_rows_resource] metadata row_count]
    }
    dict set receipt fit_count [dict get [dict get $known comparison_rows_resource] metadata row_count]
    dict set receipt model_input_count [dict get [dict get $known preprocessing_model_rows_resource] metadata row_count]
    return [_preprocessingComplete $result $receipt $stages]
}
proc ::GX::DatasetCurveFit::_preprocessingInline {source count selected fitRows modelRows policy {regionRows {}}} {
    if {![string is entier -strict $count]||$count<2||$count>10000} {error {Standalone preprocessing is bounded to 2..10000 source rows}}
    set all {};set unselected {};set picked {}
    foreach row $selected {
        if {![string is entier -strict $row]||$row<0||$row>=$count||[dict exists $picked $row]} {error {Standalone selected rows differ from original sample identities}}
        dict set picked $row 1
    }
    for {set row 0} {$row<$count} {incr row} {lappend all $row;if {![dict exists $picked $row]} {lappend unselected $row}}
    foreach row [concat $fitRows $modelRows $regionRows] {if {![dict exists $picked $row]} {error {Standalone model row is outside its captured selected input}}}
    set n [llength $selected]
    set receipt [dict create schema gxtxt.fit_preprocessing.v1 status value source $source source_request {} selection_descriptor {} original_count $count original_count_status value filtered_count $count finite_count $count selected_count $n nonfinite_count 0 selection_excluded_count [llength $unselected] fit_count [llength $fitRows] model_input_count [llength $modelRows] finite_policy require_finite_sample_pairs duplicate_policy preserve_observations order_policy preserve_stream_order row_identity_kind sample_row model_policy $policy]
    set result [dict create preprocessing_input_rows $all preprocessing_nonfinite_rows {} preprocessing_unselected_rows $unselected preprocessing_selected_rows $selected preprocessing_fit_rows $fitRows preprocessing_model_rows $modelRows]
    set stages {input preprocessing_input_rows finite preprocessing_input_rows selected preprocessing_selected_rows fit preprocessing_fit_rows nonfinite preprocessing_nonfinite_rows unselected preprocessing_unselected_rows model preprocessing_model_rows}
    if {$regionRows ne {}} {dict set result preprocessing_region_rows $regionRows;dict set stages region preprocessing_region_rows;dict set receipt region_count [llength $regionRows]}
    return [_preprocessingComplete $result $receipt $stages]
}
proc ::GX::DatasetCurveFit::_preprocessingComplete {result receipt stages} {
    dict set receipt stages $stages
    dict set receipt excluded_ids [_preprocessingExclusions $receipt]
    dict set result preprocessing $receipt
    _preprocessingInfo $result
    return $result
}
proc ::GX::DatasetCurveFit::_preprocessingExclusions {receipt} {
    set stages [dict get $receipt stages]
    # Complements/differences preserve every excluded identity without a second
    # data scan or an unbounded control-message list. Referenced stages are exact.
    set excluded [dict create nonfinite {kind exact_stage stage nonfinite} point_mask {kind exact_stage stage unselected} region_or_measurement {kind stage_difference from selected subtract fit} model_nodes {kind stage_difference from fit subtract model}]
    if {[dict exists $stages region]} {
        dict set excluded region {kind stage_difference from selected subtract region}
        dict set excluded measurement {kind stage_difference from region subtract fit}
    } else {dict set excluded measurement {kind stage_difference from selected subtract fit}}
    if {[dict get $receipt original_count_status] eq "value"} {
        dict set excluded filter_or_window [dict create kind range_difference start 0 stop_exclusive [dict get $receipt original_count] subtract input]
    } else {dict set excluded filter_or_window {kind unavailable reason original_count_unavailable}}
    return $excluded
}
proc ::GX::DatasetCurveFit::_preprocessingInfo {result} {
    if {![dict exists $result preprocessing]} {
        return [dict create schema gxtxt.fit_preprocessing.v1 status unavailable reason [expr {[dict exists $result model_input_policy]?"source_adapter_without_row_audit":"historical_receipt_not_recorded"}]]
    }
    set info [dict get $result preprocessing]
    if {[dict get $info schema] ne "gxtxt.fit_preprocessing.v1"||[dict get $info status] ne "value"} {error {Unsupported preprocessing receipt}}
    set policy [dict get $info model_policy]
    if {[dict get $policy schema] ne "gxtxt.fit_input_policy.v1"||([dict exists $result model]&&[dict get $policy model] ne [dict get $result model])} {error {Preprocessing model policy differs from its fit}}
    if {[dict exists $result model_input_policy]&&[dict get $result model_input_policy] ne $policy} {error {Captured input policies disagree}}
    set original [dict get $info original_count];set originalStatus [dict get $info original_count_status]
    if {![string is entier -strict $original]||$originalStatus ni {value unavailable}||($originalStatus eq "value"&&$original<0)||($originalStatus eq "unavailable"&&$original!=-1)} {error {Preprocessing original count or availability is invalid}}
    foreach field {filtered_count finite_count selected_count nonfinite_count selection_excluded_count fit_count model_input_count} {
        set n [dict get $info $field]
        if {![string is entier -strict $n]||$n<0} {error {Preprocessing counts must be exact nonnegative integers}}
    }
    if {[dict get $info filtered_count]!=[dict get $info finite_count]+[dict get $info nonfinite_count]||[dict get $info finite_count]!=[dict get $info selected_count]+[dict get $info selection_excluded_count]||[dict get $info fit_count]>[dict get $info selected_count]||[dict get $info model_input_count]>[dict get $info fit_count]} {error {Preprocessing stage counts are inconsistent}}
    if {$originalStatus eq "value"&&[dict get $info filtered_count]>$original} {error {Filtered rows exceed the captured original count}}
    foreach {field countField} {observation_count fit_count model_input_count model_input_count} {
        if {[dict exists $policy $field]&&[dict get $policy $field]!=[dict get $info $countField]} {error {Model preprocessing counts differ from retained row stages}}
    }
    set counts {input filtered_count finite finite_count selected selected_count nonfinite nonfinite_count unselected selection_excluded_count fit fit_count model model_input_count}
    if {[dict exists $info stages region]} {
        set n [dict get $info region_count]
        if {![string is entier -strict $n]||$n<[dict get $info fit_count]||$n>[dict get $info selected_count]} {error {Preprocessing regional count is inconsistent}}
        lappend counts region region_count
    }
    if {[dict size [dict get $info stages]]!=[llength $counts]/2} {error {Unknown captured preprocessing stage}}
    set exclusions [_preprocessingExclusions $info]
    if {[dict size [dict get $info excluded_ids]]!=[dict size $exclusions]} {error {Missing or unknown preprocessing exclusion}}
    dict for {name spec} $exclusions {
        if {![dict exists $info excluded_ids $name]||[dict get $info excluded_ids $name] ne $spec} {error {Preprocessing exclusion differs from its captured row stages}}
    }
    foreach {stage countField} $counts {
        set field [dict get $info stages $stage]
        if {[string match *_resource $field]} {
            set resource [::GX::interactiveDocumentResourceInfo [dict get $result $field]]
            if {[dict get $resource metadata format] ne "uint64_le"||[dict get $resource metadata row_count]!=[dict get $info $countField]||[dict get $resource size_bytes]!=8*[dict get $info $countField]} {error "Preprocessing $stage rows differ from their captured count"}
        } else {
            set rows [dict get $result $field]
            if {[llength $rows]!=[dict get $info $countField]||[llength $rows]>10000||[dict get $info row_identity_kind] ne "sample_row"} {error {Standalone preprocessing row count or identity changed}}
            foreach row $rows {if {![string is entier -strict $row]||$row<0||$row>=[dict get $info original_count]} {error {Standalone preprocessing contains a foreign row identity}}}
        }
    }
    if {[dict exists $result train_n]&&[dict get $result train_n]!=[dict get $info fit_count]} {error {Preprocessing fit rows differ from fitted observations}}
    return $info
}
proc ::GX::DatasetCurveFit::resultPreprocessingRows {reference stage start count} {
    set p [dict get [_recipeResultRecord $reference] provenance];set info [_preprocessingInfo $p]
    if {[dict get $info status] ne "value"} {error {Historical fit has no captured preprocessing row audit}}
    if {![dict exists $info stages $stage]} {error {Unknown captured preprocessing row stage}}
    set field [dict get $info stages $stage];set value [dict get $p $field]
    set resource [string match *_resource $field];set n [expr {$resource?[dict get $value metadata row_count]:[llength $value]}]
    if {![string is entier -strict $start]||![string is entier -strict $count]||$start<0||$start>$n||$count<1||$count>4096} {error {Preprocessing row page requires 1..4096 rows in range}}
    set count [expr {min($count,$n-$start)}];set rows {}
    if {$count} {
        if {$resource} {binary scan [::GX::interactiveDocumentResourceReadChunk $value [expr {8*$start}] [expr {8*$count}]] wu* rows} else {set rows [lrange $value $start [expr {$start+$count-1}]]}
    }
    return [dict create schema gxtxt.fit_preprocessing_rows.v1 stage $stage start $start total $n count $count row_identity_kind [dict get $info row_identity_kind] source_rows $rows]
}
