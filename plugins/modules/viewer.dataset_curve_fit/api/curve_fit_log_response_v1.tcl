# SPDX-License-Identifier: GPL-3.0-or-later
# Fitter selects source/owned data; CORE and Numeric own transform and meaning.
proc ::GX::DatasetCurveFit::_logLineage {dataset x y} {
    set provenance [::GX::datasetTransformProvenance $::GX::currentSession $dataset];set result {}
    foreach binding [::GX::datasetPublicationV2DictDefault $provenance logarithm_lineage {}] {
        if {[dict get $binding variable_id] in [list $x $y]} {lappend result $binding}
    }
    return $result
}
proc ::GX::DatasetCurveFit::_logContext {source orientation} {
    if {$orientation ni {y_of_x x_of_y}} {return {}}
    set axis [expr {$orientation eq "x_of_y"?"x":"y"}];set id [dict get $source source_axes $axis variable_id];set matches {}
    foreach binding [::GX::datasetPublicationV2DictDefault $source logarithm_lineage {}] {if {[dict get $binding variable_id] eq $id} {lappend matches $binding}}
    if {$matches eq {}} {return {}}
    set binding [lindex $matches 0];set transform [dict get $binding transform]
    set context [dict create schema gxtxt.log_response_context.v1 variable_id $id inverse_eligible [dict get $binding inverse_eligible] inverse_reason [dict get $binding inverse_reason]]
    foreach field {base reference source_dataset_id source_sha256 source_variable_id source_unit} {dict set context $field [dict get $transform $field]}
    if {[llength $matches]!=1} {dict set context inverse_eligible 0;dict set context inverse_reason {Multiple logarithmic source transformations share this response; an unambiguous inverse has not been declared}}
    return $context
}
proc ::GX::DatasetCurveFit::_logSettings {w} {
    variable state
    _assertLoaded $w
    if {$state($w,sourceKind) ne "dataset"||$state($w,sourceTransformManifest) ne {}} {error {Logarithmic variables require a canonical Dataset curve; materialize edited coordinates first}}
    set fields [dict create output [dict create type string label {New Dataset ID} required 1] y_reference [dict create type number label "Positive Y reference ([dict get [::GX::datasetVariableV3ById $state($w,dataset) $state($w,y)] unit])" required 1] transform_x [dict create type choice label {Also transform positive X values} values {no yes}] x_reference [dict create type number label "Positive X reference ([dict get [::GX::datasetVariableV3ById $state($w,dataset) $state($w,x)] unit])" required 1]]
    set values [dict create output $state($w,dataset)_log y_reference 1 transform_x no x_reference 1]
    ::GX::uiFieldFormCreate $w.logSettings {Logarithmic fitting} $fields $values [list ::GX::DatasetCurveFit::_logApply $w $state($w,activeSource)] $w
    ttk::label $w.logSettings.viewport.content.labelHelp -text {Creates dimensionless ln(value/reference) columns in a new Dataset. Values and same-unit references must be positive. Fit errors are additive in log space. Choose the noise assumptions before interpreting intervals or publishing a physical response.} -wraplength 520
    grid $w.logSettings.viewport.content.labelHelp -row 8 -column 0 -sticky ew -padx 5 -pady 8
}
proc ::GX::DatasetCurveFit::_logFocusSource {w} {
    variable state
    # A new coordinate system must not inherit an overlay of physical and log
    # curves. Keep every source and accepted fit, with explicit hidden state.
    dict for {id entry} $state($w,sources) {setSourceVisible $w $id [expr {$id eq $state($w,activeSource)}]}
    foreach record $state($w,records) {setFitVisible $w [dict get $record fit_curve_id] [expr {[dict get $record source_curve_id] eq $state($w,activeSource)}]}
    set state($w,schema) [variables $state($w,dataset)];_uiVariableChoices $w
    _invalidateSettings $w
    set state($w,residualStart) 0;set state($w,residualStatus) {Preview this source to inspect its residuals.}
    set state($w,viewBounds) {};_orientationLabels $w
}
proc ::GX::DatasetCurveFit::_logProgress {w progress} {variable state;set state($w,status) {Creating separate dimensionless logarithmic columns; original data remain unchanged…}}
proc ::GX::DatasetCurveFit::_logApply {w owner values} {
    variable state
    if {$owner ne $state($w,activeSource)} {error {Active source changed; reopen logarithmic settings}}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set transforms {};set names {};foreach descriptor [::GX::datasetVariableSchemaV3 $state($w,dataset)] {lappend names [dict get $descriptor variable_id]}
    set x $state($w,x);set y $state($w,y)
    foreach axis {y x} {
        if {$axis eq "x"&&[dict get $values transform_x] ne "yes"} continue
        set reference [_finite [dict get $values ${axis}_reference] "Positive $axis reference"]
        if {$reference<=0} {error {Logarithmic references must be positive in the source units}}
        set original $state($w,$axis);set generated log_$original;set suffix 1
        while {$generated in $names} {set generated log_${original}_[incr suffix]}
        lappend names $generated;lappend transforms [dict create source_variable_id $original output_variable_id $generated reference $reference]
        set $axis $generated
    }
    set filters {};set mapping [dict create = exact_equal != not_equal < less_than <= less_equal > greater_than >= greater_equal contains contains LIKE like]
    foreach filter $state($w,filters) {
        set operator [dict get $filter operator];set item [dict create filter_variable_id [dict get $filter variable]]
        if {$operator eq "between"} {lassign [dict get $filter value] lower upper;dict set item predicate between_inclusive;dict set item lower $lower;dict set item upper $upper} else {dict set item predicate [dict get $mapping $operator];dict set item value [dict get $filter value]}
        lappend filters $item
    }
    set row log_source_row_ordinal;set suffix 1;while {$row in $names} {set row log_source_row_ordinal_[incr suffix]}
    set manifest [dict create api_version 1 operation log_variables sources [list [dict create dataset_id $state($w,dataset) row_filters $filters]] options [dict create logarithms $transforms row_variable_id $row] output [dict create dataset_id [dict get $values output] display_name "$state($w,dataset): logarithmic response"]]
    set controls [_operationBegin $w]
    try {
        set result [::GX::datasetTransformExecuteResponsive $::GX::currentSession $manifest [dict create progress_command [list ::GX::DatasetCurveFit::_logProgress $w] cancel_command [list ::GX::DatasetCurveFit::_baselineCancelled $w]]]
        loadSource $w [dict get $result dataset_id] $x $y {}
        _logFocusSource $w
        set state($w,translationUMode) off;set state($w,translationVMode) off
        set state($w,status) {Logarithmic source created. Fit and residuals use ln(value/reference); choose the log-error assumptions before inference. Original data remain separate.}
    } finally {_operationEnd $w $controls}
    _refreshFits $w;_saveState $w;redraw $w
    if {[winfo exists $w.logSettings]} {destroy $w.logSettings}
}
proc ::GX::DatasetCurveFit::_logRecipeValidate {source} {
    set current [_logLineage [dict get $source source_dataset_id] [dict get $source source_x_variable_id] [dict get $source source_y_variable_id]]
    if {$current ne [::GX::datasetPublicationV2DictDefault $source logarithm_lineage {}]} {error {Logarithmic source normalization/lineage changed; review the source and explicitly capture a new recipe}}
}
proc ::GX::DatasetCurveFit::_logTemplateBind {prior source} {
    set current [_logLineage [dict get $source source_dataset_id] [dict get $source source_x_variable_id] [dict get $source source_y_variable_id]]
    dict set source logarithm_lineage $current
    foreach orientation {y_of_x x_of_y} {
        set before [_logContext $prior $orientation];set after [_logContext $source $orientation]
        if {($before eq {})!=($after eq {})} {error {Template mapping cannot silently change between original and logarithmic coordinates}}
        if {$before ne {}} {
            foreach field {base reference source_unit inverse_eligible} {if {[dict get $before $field] ne [dict get $after $field]} {error "Template logarithmic $field differs; capture a template for the intended normalization"}}
            if {![dict get $after inverse_eligible]} {error {A logarithmic template requires certified unchanged log-ratio coordinates}}
        }
    }
    if {$current eq {}} {dict unset source logarithm_lineage}
    return $source
}
proc ::GX::DatasetCurveFit::resultRetransform {reference datasetId} {
    set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    _requireConvergedNativeFit $p
    set source [dict get $p statistical_results training];set plan [::GX::StatisticsV1::logResponsePlan $source]
    if {[dict get $plan status] ne "value"} {error [dict get $plan reason]}
    set n [dict get $p output_n]
    if {[dict exists $record geometry_resource]} {
        set geometry [dict get $record geometry_resource]
    } else {
        # Small accepted curves retain their bounded exact point list. Use the
        # same Native/Document export owner as large saved curves, without refit.
        if {[llength [dict get $record points]]!=$n} {error {Accepted curve lacks its exact retained geometry}}
        set scene [::GX::Native2D::core scene]
        try {
            set curve [::GX::Native2D::core add $scene [dict get $record points]]
            set geometry [::GX::interactiveDocumentNative2DStore [dict get $reference document_id] $scene $curve [dict create fit_curve_id [dict get $record fit_curve_id]]]
        } finally {::GX::Native2D::core destroy $scene}
    }
    if {[dict get $geometry metadata format] ne "native2d.float64_xy_le_v1"} {error {Accepted result geometry format is unsupported}}
    set input [::GX::ScientificTransportv1::resourceArray $geometry [list 2 $n]]
    set fields [dict create orientation [::GX::ScientificTransportv1::text [dict get $p orientation]] reference [::GX::ScientificTransportv1::array {1 1} [list [dict get $plan reference]]]]
    if {[dict get $plan mean_status] eq "value"} {dict set fields log_standard_deviation [::GX::ScientificTransportv1::array {1 1} [list [dict get $plan log_standard_deviation]]]}
    set prediction {};set predictionInput [::GX::ScientificTransportv1::empty]
    if {[dict exists $p statistical_results prediction]} {
        set prediction [dict get $p statistical_results prediction];::GX::StatisticsV1::validate $prediction
        if {![dict exists $p prediction_resource]} {error {Captured log intervals lack their owned scientific rows}}
        set predictionInput [::GX::ScientificTransportv1::resourceArray [dict get $p prediction_resource] [list 8 $n]]
        dict set fields interval_kind [::GX::ScientificTransportv1::text log_[dict get $prediction provenance prediction_plan kind]]
        dict set fields confidence [::GX::ScientificTransportv1::array {1 1} [list [dict get $prediction context confidence]]]
    }
    return [::GX::ScientificTransportv1::withCapturedColumns viewer.dataset_curve_fit dataset_curve_fit_log_response_v1 log_response retransform $input $predictionInput [::GX::ScientificTransportv1::empty] [::GX::ScientificTransportv1::struct $fields] {query median mean lower upper} [list ::GX::DatasetCurveFit::_logPublishCaptured $reference $datasetId $source $prediction]]
}
proc ::GX::DatasetCurveFit::_logPublishCaptured {reference datasetId source prediction transported path} {
    # Recheck the accepted owner after the calculation, before publication.
    set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    set raw [dict get $transported values sample];set capture [dict get $transported values capture]
    set numeric [dict remove $raw query median mean lower upper coordinate_source]
    set meaning [::GX::StatisticsV1::logResponseInterpretation $source $numeric $prediction]
    set n [dict get $meaning row_count];set names [dict get $capture fields]
    if {$n!=[dict get $p output_n]} {error {Physical log response row count differs from the accepted result}}
    if {$n==1&&$names eq {}} {
        set names {};set bytes {}
        foreach name {query median mean lower upper} {if {[dict get $raw $name] ne {}} {lappend names $name;append bytes [binary format q [dict get $raw $name]]}}
        set channel [::open $path {WRONLY CREAT EXCL}];fconfigure $channel -encoding binary -translation binary
        try {puts -nonewline $channel $bytes} finally {::close $channel}
    } elseif {[dict get $capture row_count]!=$n} {error {Captured physical response columns have an inconsistent shape}}
    set expected {query median}
    foreach field {mean lower upper} {if {[dict get $meaning columns $field status] eq "value"} {lappend expected $field}}
    if {$names ne $expected||![file isfile $path]||[file size $path]!=8*$n*[llength $names]} {error {Captured physical response fields differ from CORE interpretation}}
    set schema {};set queryAxis [expr {[dict get $p orientation] eq "x_of_y"?"y":"x"}]
    foreach name $names {
        if {$name eq "query"} {set label [dict get $p source_axes $queryAxis display_label];set unit [dict get $p source_axes $queryAxis unit];set role coordinate} else {set label [dict get $meaning columns $name label];set unit [dict get $meaning columns $name unit];set role data}
        lappend schema [dict create variable_id $name name $name display_label $label unit $unit dtype float64 semantic_role $role coordinate_role $role]
    }
    set resource [::GX::interactiveDocumentResourceImportNumeric [dict get $reference document_id] $path [dict create format gxtxt.numeric_matrix.float64_column_major_le.v1 row_count $n column_ids $names dtype float64 endian little]]
    set stats [dict get $p statistical_results];dict set stats physical_retransformation $meaning
    set metadata [dict create curve_fit.statistical_results $stats curve_fit.log_result_reference $reference curve_fit.logarithmic_source $p curve_fit.retransformation_coordinates [dict get $raw coordinate_source] curve_fit.retransformation_resource_sha256 [dict get $resource sha256] curve_fit.retransformation_columns $names curve_fit.retransformation_transport [dict get $transported transport]]
    set definition [dict create dataset_id $datasetId contract table.generic storage hdf5 source {Dataset Curve Fit logarithmic response} provenance {Physical response derived from an accepted logarithmic fit; original log-space model retained} structured_metadata $metadata]
    return [::GX::datasetPublicationV2PublishManagedColumns $::GX::currentSession viewer.dataset_curve_fit $definition $resource $schema]
}
proc ::GX::DatasetCurveFit::_logPublishDialog {w} {
    variable state
    set selected [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selected]!=1} {error {Select one accepted logarithmic fit}}
    set record [lindex $state($w,records) [lindex $selected 0]]
    _saveState $w
    set reference [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set current [_recipeResultRecord $reference]
    set plan [::GX::StatisticsV1::logResponsePlan [dict get $current provenance statistical_results training]]
    if {[dict get $plan status] ne "value"} {error [dict get $plan reason]}
    set fields [dict create output [dict create type string label {New physical-response Dataset ID} required 1]]
    ::GX::uiFieldFormCreate $w.logPublish {Physical response: separate median/fit, eligible plug-in mean and captured interval columns} $fields [dict create output $state($w,dataset)_physical] [list ::GX::DatasetCurveFit::_logPublishApply $w $reference] $w
}
proc ::GX::DatasetCurveFit::_logPublishApply {w reference values} {
    variable state
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set result [resultRetransform $reference [dict get $values output]]
    loadSource $w [dict get $result dataset_id] query median {}
    _logFocusSource $w
    _refreshFits $w;_saveState $w;redraw $w
    set state($w,status) {Published separate physical response columns. CORE metadata identifies the median/fit, optional plug-in mean and interval target; the accepted log fit is retained.}
    if {[winfo exists $w.logPublish]} {destroy $w.logPublish}
}
proc ::GX::DatasetCurveFit::_logDetails {w} {
    variable state
    if {![dict exists $state($w,preview) statistical_results training context response_transform]} {error {Select or preview a fitted logarithmic response first}}
    set statistics [dict get $state($w,preview) statistical_results training]
    set content [::GX::StatisticsV1::report $statistics {n rmse r_squared dof}]
    set dialog $w.logDetails
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog {Log-response interpretation};wm transient $dialog $w
    text $dialog.text -wrap word -width 86 -height 24 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end $content;$dialog.text configure -state disabled
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
