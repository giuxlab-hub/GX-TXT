# SPDX-License-Identifier: GPL-3.0-or-later
# Declared controls only. Numeric owns computation, Interactive Document owns
# results, Managed Resource owns arrays, Dataset Publication owns publication.
proc ::GX::_viewerGuiNumericDesignValidate {design} {
    set definitions {};foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {[dict get $c type] ne {section} || (![dict exists $p numeric_expression] && ![dict exists $p numeric_kind])} continue
        set kind [datasetPublicationV2DictDefault $p numeric_kind expression]
        if {$kind ni {expression interpolation complex_projection}} {error {Unknown declared Numeric form kind}}
        if {![dict exists $design requirements NUMERIC_API_v1] || [dict get $design requirements NUMERIC_API_v1]!=1} {error {Numeric form requires NUMERIC_API_v1@1}}
        set required {numeric_dataset {dataset_selector} numeric_start {entry field} numeric_count {entry field} numeric_x {choice combobox} numeric_status {status label} numeric_report {log}}
        switch -- $kind {
            expression {lappend required numeric_expression {entry field} numeric_output_unit {entry field choice combobox}}
            interpolation {lappend required numeric_y {choice combobox} numeric_query_dataset {dataset_selector} numeric_query_x {choice combobox} numeric_query_start {entry field} numeric_query_count {entry field} numeric_method {choice combobox} numeric_extrapolation {choice combobox}}
            complex_projection {lappend required numeric_real {choice combobox} numeric_imaginary {choice combobox} numeric_projection {choice combobox}}
        }
        foreach {key types} $required {
            if {![dict exists $p $key] || ![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types} {error "Invalid declared Numeric control $key"}
        }
        if {$kind eq {expression} && (![dict exists $p numeric_variables] || [dict size [dict get $p numeric_variables]]<1 || [dict size [dict get $p numeric_variables]]>32)} {error {Numeric expression form requires1..32 declared Variable bindings}}
        set symbols {}
        dict for {symbol target} [datasetPublicationV2DictDefault $p numeric_variables {}] {
            if {![regexp {^[A-Za-z][A-Za-z0-9_]{0,31}$} $symbol] || ![dict exists $definitions $target] || [dict get $definitions $target type] ni {choice combobox}} {error {Invalid Numeric symbol or Variable choice}}
            lappend symbols $symbol
        }
        set parameters [datasetPublicationV2DictDefault $p numeric_parameters {}]
        if {[dict size $parameters]>32} {error {Numeric form exceeds32 scalar parameters}}
        dict for {symbol controls} $parameters {
            if {![regexp {^[A-Za-z][A-Za-z0-9_]{0,31}$} $symbol] || $symbol in $symbols || [lsort [dict keys $controls]] ne {unit value}} {error {Invalid or duplicate Numeric parameter symbol}}
            foreach key {value unit} {
                set target [dict get $controls $key]
                if {![dict exists $definitions $target] || [dict get $definitions $target type] ni {entry field choice combobox}} {error {Numeric parameters require typed scalar and unit controls}}
            }
            lappend symbols $symbol
        }
        foreach {key types} {numeric_source {native2d} numeric_statistic {choice combobox} numeric_observed {choice combobox} numeric_relative_floor {entry field}} {
            if {[dict exists $p $key] && (![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types)} {error "Invalid optional Numeric control $key"}
        }
        if {[dict exists $p numeric_source] && ![dict exists $definitions [dict get $p numeric_source] properties diagram_catalog]} {error {Optional Numeric source must be a declared canonical diagram}}
        if {[dict exists $p numeric_observed] != [dict exists $p numeric_relative_floor]} {error {Numeric comparison requires both observed Variable and explicit relative floor}}
    }
}
proc ::GX::_viewerGuiNumericForm {window form} {
    if {![viewerGuiDesignGuard $window]} {error {Numeric form belongs to a previous Session lifetime}}
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || (![dict exists $c properties numeric_expression] && ![dict exists $c properties numeric_kind])} {error {Select a declared Numeric form}}
    modulePublicApiActivate math.numeric NUMERIC_API_v1
    return [dict get $c properties]
}
proc ::GX::_viewerGuiNumericDisplay {window form state detail} {
    set p [_viewerGuiNumericForm $window $form]
    viewerGuiDesignTextSet $window [dict get $p numeric_status] $state
    viewerGuiDesignTextSet $window [dict get $p numeric_report] [string range $detail 0 32767]
    viewerGuiTraceEmit $window $form numeric_state [dict create status $state]
}
proc ::GX::_viewerGuiNumericFieldsText {statistics} {
    set text {}
    dict for {id field} [::GX::StatisticsV1::numericFields $statistics] {
        append text "[dict get $field label]: "
        if {[dict get $field status] eq {value}} {
            append text [dict get $field value]
            if {[dict get $field unit_text] ni {1 dimensionless}} {append text " [dict get $field unit_text]"}
        } else {append text "[dict get $field status] — [dict get $field reason]"}
        append text "\n"
    }
    return $text
}
proc ::GX::_viewerGuiNumericStatisticsStore {window form source operation response} {
    set statistics [dict get $response captured_statistics]
    ::GX::StatisticsV1::validate $statistics
    set domain [viewerGuiDesignContextGet $window]
    if {![dict exists $domain numeric_results $form document_id] || [dict get $domain numeric_results $form document_id] ne $source} {error {Numeric result changed during statistical computation}}
    set current [interactiveDocumentRead $source]
    foreach key {generation revision sha256} {if {[dict get $domain numeric_results $form $key] ne [dict get $current $key]} {error {Numeric result Document changed during statistical computation}}}
    # The full existing statistical schema is persisted without reducing again.
    # Viewer state carries an immutable identity, never a copied numeric vector.
    set doc [interactiveDocumentCreate [dict get $::GX::ViewerGui::instances $window module] [dict get $::GX::ViewerGui::instances $window provider] gxtxt.statistical_result.v1 1 $statistics]
    set descriptor [dict create document_id [dict get $doc id] generation [dict get $doc generation] revision [dict get $doc revision] sha256 [dict get $doc sha256] source_result_document $source operation $operation]
    dict set domain numeric_statistics $form $descriptor;viewerGuiDesignContextSet $window $domain
    dict set response statistics_document $descriptor
    return $response
}
proc ::GX::_viewerGuiNumericRestore {window} {
    set domain [viewerGuiDesignContextGet $window]
    dict for {form descriptor} [datasetPublicationV2DictDefault $domain numeric_results {}] {
        lassign [_viewerGuiNumericResult $window $form] doc result
        set request [dict get $result request];set captured [dict get $result captured]
        _viewerGuiNumericDisplay $window $form RESTORED_RESULT "Saved Numeric result\n[_viewerGuiNumericDescription $request]\nRows: [dict get $request options start] + [dict get $captured row_count]\nUnit: [dict get $captured unit]\nSource Dataset: [dict get $request dataset_id]\nResult Document: [dict get $doc id]\n\nThe immutable captured vector was restored without recomputation."
    }
    dict for {form descriptor} [datasetPublicationV2DictDefault $domain numeric_statistics {}] {
        _viewerGuiNumericForm $window $form
        set doc [interactiveDocumentRead [dict get $descriptor document_id]]
        foreach key {module provider} {if {[dict get $doc ${key}_id] ne [dict get $::GX::ViewerGui::instances $window $key]} {error {Saved statistical result belongs to another Viewer owner}}}
        foreach key {generation revision sha256} {if {[dict get $doc $key] ne [dict get $descriptor $key]} {error {Saved statistical result Document changed}}}
        if {[dict get $doc format] ne {gxtxt.statistical_result.v1}} {error {Saved Numeric statistics have the wrong canonical format}}
        set statistics [dict get $doc payload];::GX::StatisticsV1::validate $statistics
        _viewerGuiNumericDisplay $window $form RESTORED_STATISTICS "Saved statistic: [dict get $descriptor operation]\nResult Document: [dict get $doc id]\n\n[_viewerGuiNumericFieldsText $statistics]"
    }
}
proc ::GX::viewerGuiDesignNumericDiscover {window form} {
    set p [_viewerGuiNumericForm $window $form];set values [viewerGuiDesignValues $window]
    set kind [datasetPublicationV2DictDefault $p numeric_kind expression]
    set targets [dict values [datasetPublicationV2DictDefault $p numeric_variables {}]];lappend targets [dict get $p numeric_x]
    foreach key {numeric_observed numeric_y numeric_real numeric_imaginary} {if {[dict exists $p $key]} {lappend targets [dict get $p $key]}}
    set dataset [dict get $values [dict get $p numeric_dataset]]
    set report [_viewerGuiNumericDatasetDiscover $window $dataset $targets $values]
    if {$kind eq {interpolation}} {append report "\n\nQuery [_viewerGuiNumericDatasetDiscover $window [dict get $values [dict get $p numeric_query_dataset]] [list [dict get $p numeric_query_x]] $values]"}
    append report "\n\nChoose explicit Variable identities and row start/count before Evaluate. Discovery does not change any row count."
    _viewerGuiNumericDisplay $window $form DISCOVERED $report
    return [dict create dataset_id $dataset variables [datasetVariableSchemaV3 $dataset]]
}
proc ::GX::_viewerGuiNumericDatasetDiscover {window dataset targets values} {
    set schema [datasetVariableSchemaV3 $dataset];set choices {};set report "Dataset: $dataset"
    foreach variable $schema {
        if {[dict get $variable dtype] ni {float64 float32 int64 int32 uint64 uint32 int16 uint16 int8 uint8} || [llength [dict get $variable shape]]!=1} continue
        lappend choices [dict get $variable variable_id]
        append report "\n[dict get $variable variable_id]: [dict get $variable unit]; rows [lindex [dict get $variable shape] 0]"
    }
    if {![llength $choices] || [llength $choices]>4096} {error {Dataset has no bounded numeric one-dimensional Variable choices}}
    foreach target [lsort -unique $targets] {
        viewerGuiDesignChoicesSet $window $target $choices
        if {[dict get $values $target] ni $choices} {viewerGuiDesignValueSet $window $target [lindex $choices 0]}
    }
    return $report
}
proc ::GX::_viewerGuiNumericSourceGuard {window p} {
    if {![dict exists $p numeric_source]} {return {}}
    set component [dict get $p numeric_source]
    if {![dict exists $::GX::ViewerGui::instances $window bindings $component document_id]} {error {Bind the declared Numeric source diagram first}}
    set doc [interactiveDocumentRead [dict get $::GX::ViewerGui::instances $window bindings $component document_id]]
    return [dict create document_id [dict get $doc id] generation [dict get $doc generation] revision [dict get $doc revision] sha256 [dict get $doc sha256]]
}
proc ::GX::_viewerGuiNumericRequest {window form} {
    set p [_viewerGuiNumericForm $window $form];set values [viewerGuiDesignValues $window]
    if {[datasetPublicationV2DictDefault $p numeric_kind expression] ne {expression}} {return [_viewerGuiNumericPointwiseRequest $window $p $values]}
    set dataset [dict get $values [dict get $p numeric_dataset]];set revision [datasetRevisionToken $dataset]
    set bindings {};dict for {symbol component} [dict get $p numeric_variables] {dict set bindings $symbol [dict create dataset_id $dataset variable_id [dict get $values $component]]}
    set parameters {};dict for {symbol controls} [datasetPublicationV2DictDefault $p numeric_parameters {}] {
        dict set parameters $symbol [dict create value [dict get $values [dict get $controls value]] unit [dict get $values [dict get $controls unit]]]
    }
    set options {};foreach key {start count output_unit} {dict set options $key [dict get $values [dict get $p numeric_$key]]}
    if {![string is entier -strict [dict get $options start]] || [dict get $options start]<0 || ![string is entier -strict [dict get $options count]] || [dict get $options count]<1 || [dict get $options count]>65536} {error {Numeric row start must be nonnegative; explicit count must be1..65536}}
    set x [dict get $values [dict get $p numeric_x]];set xmeta [datasetVariableV3ById $dataset $x]
    if {[llength [dict get $xmeta shape]]!=1 || [dict get $options start]+[dict get $options count]>[lindex [dict get $xmeta shape] 0]} {error {Numeric publication X row range exceeds its canonical Variable}}
    return [dict create dataset_id $dataset dataset_revision $revision expression [dict get $values [dict get $p numeric_expression]] bindings $bindings parameters $parameters options $options x_variable_id $x x_unit [dict get $xmeta unit] source_guard [_viewerGuiNumericSourceGuard $window $p]]
}
proc ::GX::_viewerGuiNumericPointwiseRequest {window p values} {
    set kind [dict get $p numeric_kind]
    set dataset [dict get $values [dict get $p numeric_dataset]]
    set start [dict get $values [dict get $p numeric_start]];set count [dict get $values [dict get $p numeric_count]]
    set start [uiFieldNormalize {type integer min 0} $start];set count [uiFieldNormalize {type integer min 1 max 65536} $count]
    set x [dict get $values [dict get $p numeric_x]]
    set revisions [dict create $dataset [datasetRevisionToken $dataset]]
    set request [dict create kind $kind source_guard [_viewerGuiNumericSourceGuard $window $p]]
    if {$kind eq {interpolation}} {
        set source [dict create dataset_id $dataset x_variable_id $x y_variable_id [dict get $values [dict get $p numeric_y]] start $start count $count]
        set dataset [dict get $values [dict get $p numeric_query_dataset]]
        set x [dict get $values [dict get $p numeric_query_x]]
        set start [dict get $values [dict get $p numeric_query_start]];set count [dict get $values [dict get $p numeric_query_count]]
        set query [dict create dataset_id $dataset variable_id $x start $start count $count]
        set start [uiFieldNormalize {type integer min 0} $start];set count [uiFieldNormalize {type integer min 1 max 65536} $count]
        dict set query start $start;dict set query count $count
        dict set revisions $dataset [datasetRevisionToken $dataset]
        set method [dict get $values [dict get $p numeric_method]];set extrapolation [dict get $values [dict get $p numeric_extrapolation]]
        if {$method ni {linear pchip} || $extrapolation ne {error}} {error {Choose linear/pchip with explicit extrapolation=error}}
        dict set request source $source;dict set request query $query
        dict set request interpolation_options [dict create method $method extrapolation $extrapolation]
        dict set request operation interpolate
        set unit [dict get [datasetVariableV3ById [dict get $source dataset_id] [dict get $source y_variable_id]] unit]
    } else {
        set real [dict get $values [dict get $p numeric_real]];set imaginary [dict get $values [dict get $p numeric_imaginary]]
        set projection [dict get $values [dict get $p numeric_projection]]
        if {$projection ni {magnitude phase_rad phase_deg}} {error {Choose magnitude, phase_rad or phase_deg}}
        dict set request real_variable_id $real;dict set request imaginary_variable_id $imaginary;dict set request projection $projection
        dict set request operation complex_unary.$projection
        set unit [dict get [datasetVariableV3ById $dataset $real] unit]
        if {$projection eq {phase_rad}} {set unit rad};if {$projection eq {phase_deg}} {set unit deg}
    }
    set xmeta [datasetVariableV3ById $dataset $x]
    if {[llength [dict get $xmeta shape]]!=1 || $start+$count>[lindex [dict get $xmeta shape] 0]} {error {Numeric publication X row range exceeds its canonical Variable}}
    dict set request dataset_id $dataset;dict set request dataset_revision [datasetRevisionToken $dataset]
    dict set request options [dict create start $start count $count output_unit $unit]
    dict set request x_variable_id $x;dict set request x_unit [dict get $xmeta unit];dict set request source_revisions $revisions
    return $request
}
proc ::GX::_viewerGuiNumericDescription {request} {
    switch -- [datasetPublicationV2DictDefault $request kind expression] {
        expression {return "Expression: [dict get $request expression]\nParameters: [dict get $request parameters]"}
        interpolation {return "Interpolation: [dict get $request interpolation_options method]; extrapolation: error\nSource: [dict get $request source]\nQuery: [dict get $request query]"}
        complex_projection {return "Split-complex [dict get $request projection]\nReal: [dict get $request real_variable_id]; imaginary: [dict get $request imaginary_variable_id]"}
    }
}
proc ::GX::_viewerGuiNumericGuard {window request {savedResult 0}} {
    if {![viewerGuiDesignGuard $window]} {error {Numeric Session lifetime changed}}
    set current [datasetRevisionToken [dict get $request dataset_id]]
    set expected [dict get $request dataset_revision]
    if {$current ne $expected && (!$savedResult || ![_datasetRevisionPortableEqual $current $expected])} {error {Numeric source Dataset changed; Evaluate again}}
    dict for {dataset revision} [datasetPublicationV2DictDefault $request source_revisions {}] {
        set current [datasetRevisionToken $dataset]
        if {$current ne $revision && (!$savedResult || ![_datasetRevisionPortableEqual $current $revision])} {error {A Numeric pointwise source Dataset changed; Evaluate again}}
    }
    _scientificExecutionPublicationGuard [dict get $request source_guard]
    if {$savedResult} {
        # Rebind only the returned, in-memory operation request. The immutable
        # Document and stored provenance retain their original carrier identity.
        # Subsequent computation/publication checks use strict current tokens.
        dict set request dataset_revision [datasetRevisionToken [dict get $request dataset_id]]
        dict for {dataset revision} [datasetPublicationV2DictDefault $request source_revisions {}] {
            dict set request source_revisions $dataset [datasetRevisionToken $dataset]
        }
    }
    return $request
}
proc ::GX::_viewerGuiNumericResult {window form} {
    _viewerGuiNumericForm $window $form
    set state [viewerGuiDesignContextGet $window]
    if {![dict exists $state numeric_results $form document_id]} {error {Evaluate this Numeric form before using its result}}
    set descriptor [dict get $state numeric_results $form]
    set doc [interactiveDocumentRead [dict get $descriptor document_id]]
    foreach key {module provider} {if {[dict get $doc ${key}_id] ne [dict get $::GX::ViewerGui::instances $window $key]} {error {Numeric result belongs to another Viewer owner}}}
    foreach key {generation revision sha256} {if {[dict get $doc $key] ne [dict get $descriptor $key]} {error {Numeric result Document changed; Evaluate again}}}
    if {[dict get $doc format] ni {gxtxt.numeric_expression.v1 gxtxt.numeric_pointwise.v1}} {error {Numeric result Document format differs}}
    set result [dict get $doc payload]
    # The immutable result Document is already checked against this Viewer and
    # saved Workspace above. Revalidate its Dataset content across a portable
    # carrier move without rewriting either identity or recomputing the vector.
    dict set result request [_viewerGuiNumericGuard $window [dict get $result request] 1]
    return [list $doc $result]
}
proc ::GX::viewerGuiDesignNumericEvaluate {window form} {
    set candidate {};set committed 0
    try {
        set request [_viewerGuiNumericRequest $window $form]
        set state [viewerGuiDesignContextGet $window]
        # Each successful evaluation is immutable: old Workspace/History states
        # retain their original Document and resource rather than a mutable head.
        set kind [datasetPublicationV2DictDefault $request kind expression]
        set format [expr {$kind eq {expression} ? {gxtxt.numeric_expression.v1} : {gxtxt.numeric_pointwise.v1}}]
        set doc [interactiveDocumentCreate [dict get $::GX::ViewerGui::instances $window module] [dict get $::GX::ViewerGui::instances $window provider] $format 1 [dict create state empty]]
        set id [dict get $doc id]
        set candidate $id
        switch -- $kind {
            expression {set captured [::GX::NumericAPIv1::expressionDatasetCaptured $id [dict get $request expression] [dict get $request bindings] [dict get $request parameters] [dict get $request options]]}
            interpolation {set captured [::GX::NumericAPIv1::interpolateDatasetCaptured $id [dict get $request source] [dict get $request query] [dict get $request interpolation_options]]}
            complex_projection {set captured [::GX::NumericAPIv1::complexDatasetCaptured $id [dict get $request dataset_id] [dict get $request real_variable_id] [dict get $request imaginary_variable_id] [dict get $request projection] [dict remove [dict get $request options] output_unit]]}
        }
        _viewerGuiNumericGuard $window $request
        if {[_viewerGuiNumericRequest $window $form] ne $request} {error {Numeric form changed while computing; previous result retained}}
        set result [dict create state evaluated request $request captured $captured]
        set updated [interactiveDocumentUpdate $id $result]
        set descriptor [dict create document_id $id generation [dict get $updated generation] revision [dict get $updated revision] sha256 [dict get $updated sha256]]
        dict set state numeric_results $form $descriptor
        if {[dict exists $state numeric_statistics $form]} {dict unset state numeric_statistics $form}
        viewerGuiDesignContextSet $window $state
        set committed 1
        _viewerGuiNumericDisplay $window $form EVALUATED "[_viewerGuiNumericDescription $request]\nRows: [dict get $request options start] + [dict get $captured row_count]\nUnit: [dict get $captured unit]\nSource Dataset: [dict get $request dataset_id]\nResult Document: $id\n\nCaptured vector is available for statistics and explicit Dataset publication. Pointwise values have no statistical interpretation until an eligible operation is requested."
        return $descriptor
    } on error {message options} {
        if {!$committed && $candidate ne {}} {catch {interactiveDocumentDelete $candidate}}
        catch {_viewerGuiNumericDisplay $window $form EVALUATION_FAILED "Evaluation failed: $message\n\nThe previous successful result and any published Dataset are retained with their original identities."}
        return -options $options $message
    }
}
proc ::GX::viewerGuiDesignNumericStatistics {window form} {
    set p [_viewerGuiNumericForm $window $form]
    if {![dict exists $p numeric_statistic]} {error {Declare a Numeric statistic choice}}
    set operation [dict get [viewerGuiDesignValues $window] [dict get $p numeric_statistic]]
    if {$operation ni {array_reduce.rms array_reduce.minimum array_reduce.maximum statistics}} {error {Choose a supported public Numeric reduction or statistics operation}}
    lassign [_viewerGuiNumericResult $window $form] doc result
    set request [dict get $result request];set captured [dict get $result captured]
    set response [::GX::NumericAPIv1::callOperationCaptured [dict get $doc id] $operation [list [dict get $captured array]] [dict create x_unit [dict get $request x_unit] y_unit [dict get $captured unit]] {kind struct fields {}} [dict create source_request $request source_result_document [dict get $doc id] source_result_sha256 [dict get $doc sha256]]]
    _viewerGuiNumericGuard $window $request
    ::GX::StatisticsV1::validate [dict get $response captured_statistics]
    set response [_viewerGuiNumericStatisticsStore $window $form [dict get $doc id] $operation $response]
    _viewerGuiNumericDisplay $window $form STATISTICS "Statistic: $operation\n\n[_viewerGuiNumericFieldsText [dict get $response captured_statistics]]"
    return $response
}
proc ::GX::viewerGuiDesignNumericCompare {window form} {
    set p [_viewerGuiNumericForm $window $form]
    if {![dict exists $p numeric_observed]} {error {Declare an observed Variable and relative floor for comparison}}
    lassign [_viewerGuiNumericResult $window $form] doc result
    set request [dict get $result request];set captured [dict get $result captured];set values [viewerGuiDesignValues $window]
    set observed [dict get $values [dict get $p numeric_observed]];set floor [dict get $values [dict get $p numeric_relative_floor]]
    set options [dict get $request options];dict set options output_unit [dict get $captured unit]
    set observation [::GX::NumericAPIv1::expressionDatasetCaptured [dict get $doc id] observed [dict create observed [dict create dataset_id [dict get $request dataset_id] variable_id $observed]] {} $options]
    set response [::GX::NumericAPIv1::callOperationCaptured [dict get $doc id] residual_metrics [list [dict get $observation array] [dict get $captured array]] [dict create x_unit [dict get $request x_unit] y_unit [dict get $captured unit]] [::GX::ScientificTransportv1::struct [dict create relative_floor [::GX::ScientificTransportv1::array {1 1} [list $floor]]]] [dict create source_request $request source_result_document [dict get $doc id] source_result_sha256 [dict get $doc sha256] observed_variable_id $observed relative_floor $floor]]
    _viewerGuiNumericGuard $window $request
    ::GX::StatisticsV1::validate [dict get $response captured_statistics]
    set response [_viewerGuiNumericStatisticsStore $window $form [dict get $doc id] residual_metrics $response]
    _viewerGuiNumericDisplay $window $form COMPARED "Observed: $observed\nReference: [_viewerGuiNumericDescription $request]\nRelative floor: $floor\n\n[_viewerGuiNumericFieldsText [dict get $response captured_statistics]]"
    return $response
}
proc ::GX::viewerGuiDesignNumericPublish {window form datasetComponent} {
    set c [viewerGuiDesignComponent $window $datasetComponent]
    if {[dict get $c type] ne {dataset_selector}} {error {Numeric publication requires a declared Dataset selector}}
    lassign [_viewerGuiNumericResult $window $form] doc result
    set request [dict get $result request];set captured [dict get $result captured];set count [dict get $captured row_count]
    set dataset numeric_result_[clock microseconds]
    set operation [datasetPublicationV2DictDefault $request operation dataset_expression]
    set definition [dict create dataset_id $dataset contract table.generic storage csv provenance "NUMERIC_API_v1@1 $operation; [_viewerGuiNumericDescription $request]" structured_metadata [dict create numeric.api_id NUMERIC_API_v1 numeric.operation $operation numeric.request $request numeric.captured_receipt [dict remove $captured array transport] numeric.result_document [dict get $doc id] numeric.result_sha256 [dict get $doc sha256]]]
    set domain [viewerGuiDesignContextGet $window]
    if {[dict exists $domain numeric_statistics $form]} {dict set definition structured_metadata numeric.statistical_result [dict get $domain numeric_statistics $form]}
    # Canonical Dataset metadata has a one-field-per-line portable contract.
    # Captured Numeric receipts can contain multiline document descriptions;
    # preserve their exact UTF-8 representation rather than dropping provenance.
    foreach key {numeric.request numeric.captured_receipt numeric.statistical_result} {
        if {[dict exists $definition structured_metadata $key]} {
            set value [dict get $definition structured_metadata $key]
            if {[regexp {[\r\n]} $value]} {
                dict set definition structured_metadata $key [datasetB64Encode $value]
                dict set definition structured_metadata ${key}.encoding base64-utf8
            }
        }
    }
    set plan [datasetPublicationV2Prepare $::GX::currentSession [dict get $::GX::ViewerGui::instances $window module] $definition]
    set writer [datasetPublicationV2OpenWriter $plan];set stream {}
    try {
        datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        datasetPublicationV2DeclareVariable $writer x [dict create dtype float64 unit [dict get $request x_unit] dimension_ids row]
        datasetPublicationV2DeclareVariable $writer value [dict create dtype float64 unit [dict get $captured unit] dimension_ids row]
        set stream [tableStreamOpenDataset $::GX::currentSession [dict get $request dataset_id] [list [dict get $request x_variable_id]] 1024 [dict create start [dict get $request options start] count $count numeric_transport values]]
        set offset 0
        while {$offset<$count} {
            _viewerGuiNumericGuard $window $request
            set chunk [tableStreamNext $stream];set rows [dict get $chunk nrows]
            if {$rows<1 || $offset+$rows>$count} {error {Numeric source X row range changed during publication}}
            set page [managedResourceNumericPage [dict get $captured resource] $offset $rows]
            binary scan [dict get $page bytes] q* numbers
            if {[llength $numbers]!=$rows} {error {Numeric result resource shape changed during publication}}
            datasetPublicationV2Append $writer row [dict create x [dict get $chunk values [dict get $request x_variable_id]] value $numbers]
            incr offset $rows
        }
        _viewerGuiNumericGuard $window $request
        set current [interactiveDocumentRead [dict get $doc id]]
        foreach key {generation revision sha256} {if {[dict get $current $key] ne [dict get $doc $key]} {error {Numeric result changed before publication}}}
        set receipt [datasetPublicationV2Finalize $writer]
    } on error {message options} {
        catch {datasetPublicationV2Abort $writer}
        catch {_viewerGuiNumericDisplay $window $form PUBLICATION_FAILED "Publication failed: $message\nPrevious successful results are retained."}
        return -options $options $message
    } finally {if {$stream ne {}} {tableStreamClose $stream}}
    viewerGuiDesignValueSet $window $datasetComponent [dict get $receipt dataset_id]
    _viewerGuiNumericDisplay $window $form PUBLISHED "Canonical Dataset: [dict get $receipt dataset_id]\nRows: $count\nx: [dict get $request x_variable_id] ([dict get $request x_unit])\nvalue: [dict get $captured unit]\n[_viewerGuiNumericDescription $request]"
    return $receipt
}
