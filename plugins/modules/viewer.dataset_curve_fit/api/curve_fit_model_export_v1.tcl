# Accepted result export delegates all model interpretation/code generation to
# NUMERIC_API_v1. It never loads training data or estimates statistical facts.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::resultExport {reference name} {
    return [_modelExportRecord [_recipeResultRecord $reference] $name $reference]
}
proc ::GX::DatasetCurveFit::_modelExportRecord {record name reference} {
    _validateAcceptedStatistics $record
    set p [dict get $record provenance]
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set positive 0
    if {[dict get $p model] eq "rational"} {
        set model [_rationalSavedNode $p]
    } elseif {[dict get $p model] eq "complex_response"} {
        set model [_complexSavedNode $p]
    } elseif {[dict get $p model] eq "implicit"} {
        set model [_implicitSavedNode $p]
    } elseif {[dict exists $p registered_model_state]} {
        set saved [dict get $p registered_model_state]
        set resource [dict get $p registered_source_resource]
        set size [dict get [::GX::interactiveDocumentResourceInfo $resource] size_bytes]
        if {$size>1048576} {error {Registered source exceeds the 1 MiB independent export limit}}
        set bytes [::GX::interactiveDocumentResourceReadChunk $resource 0 $size]
        set fields [dict create kind [::GX::ScientificTransportv1::text registered_callback_source] source [::GX::ScientificTransportv1::text [encoding convertfrom utf-8 $bytes]]]
        foreach field {source_sha256 binding_sha256} {dict set fields $field [::GX::ScientificTransportv1::text [dict get $saved $field]]}
        foreach field {language entrypoint} {dict set fields $field [::GX::ScientificTransportv1::text [dict get $p options registered_model $field]]}
        dict set fields parameter_ids [dict create kind cell items [lmap id [dict get $saved parameter_ids] {::GX::ScientificTransportv1::text $id}]]
        set parameters [dict get $saved parameters]
        dict set fields parameters [::GX::ScientificTransportv1::array [list [llength $parameters] 1] $parameters]
        set model [::GX::ScientificTransportv1::struct $fields]
        set positive [expr {[dict get $saved predictor_domain] eq "positive_real"}]
    } elseif {[dict exists $p numeric_model_state]} {
        set saved [dict get $p numeric_model_state];set fields {}
        dict set fields kind [::GX::ScientificTransportv1::text expression]
        foreach field {expression parameter_ids predictor_ids} {
            dict set fields $field [dict create kind cell items [lmap v [dict get $saved $field] {::GX::ScientificTransportv1::text $v}]]
        }
        set parameters [dict get $saved parameters]
        dict set fields parameters [::GX::ScientificTransportv1::array [list [llength $parameters] 1] $parameters]
        dict set fields source_sha256 [::GX::ScientificTransportv1::text [dict get $saved source_sha256]]
        set model [::GX::ScientificTransportv1::struct $fields]
        set positive [expr {[dict get $saved kind] eq "power_law"||([dict exists $saved input_constraints domain]&&[dict get $saved input_constraints domain] eq "positive_real")}]
    } elseif {[dict exists $p model_state_resource]} {
        set resource [dict get $p model_state_resource];set info [::GX::interactiveDocumentResourceInfo $resource]
        if {[dict get $info size_bytes]>2097152} {error {Saved model exceeds the 2 MiB standalone text export limit; reduce the model explicitly}}
        set reader [::GX::interactiveDocumentResourceOpenReader $resource];set bytes {}
        try {
            while {1} {set page [::GX::interactiveDocumentResourceNext $reader 65536];append bytes [dict get $page bytes];if {[dict get $page eof]} break}
        } finally {::GX::interactiveDocumentResourceCloseReader $reader}
        set model [::GX::ScientificTransportv1::text [encoding convertfrom utf-8 $bytes]]
    } elseif {[dict exists $p model_state_json]&&[dict get $p model_state_json] ne {}} {
        set model [::GX::ScientificTransportv1::text [dict get $p model_state_json]]
    } elseif {[dict get $p model] eq "linear"} {
        set values [split [dict get $p parameters] ,]
        set model [::GX::ScientificTransportv1::struct [dict create kind [::GX::ScientificTransportv1::text polynomial_export] coefficients [::GX::ScientificTransportv1::array [list [llength $values] 1] $values]]]
    } else {error {This accepted fit lacks its exact saved evaluation state. Make an explicit new preview and accept it before independent export.}}
    set orientation [dict get $p orientation]
    set domain [dict get $p domain]
    if {[dict exists $p export_domain]} {set domain [split [dict get $p export_domain] ,]} elseif {$domain eq "source"} {
        if {$orientation eq "parametric"} {set domain {0 1}} elseif {$orientation eq "r_of_theta"} {set domain [list [dict get $p angular_min] [dict get $p angular_max]]} else {set domain [split [dict get $p translation u original_bounds] ,]}
    } else {if {[lindex $domain 0] eq "parameter"} {set domain [lrange $domain 1 end]};set domain [lrange $domain 0 1]}
    set opts [dict create model_id [::GX::ScientificTransportv1::text math.numeric.[dict get $p model]] name [::GX::ScientificTransportv1::text $name] orientation [::GX::ScientificTransportv1::text $orientation] domain [::GX::ScientificTransportv1::array {1 2} $domain] positive_predictor [::GX::ScientificTransportv1::array {1 1} [list $positive]]]
    foreach axis {u v} {dict set opts delta_$axis [::GX::ScientificTransportv1::array {1 1} [list [dict get $p translation $axis delta]]]}
    foreach axis {x y} {dict set opts ${axis}_unit [::GX::ScientificTransportv1::text [dict get $p source_axes $axis unit]]}
    dict set opts query_unit [::GX::ScientificTransportv1::text [expr {$orientation eq "parametric" ? "dimensionless normalized t" : [dict get $p translation u unit]}]]
    set units {};set ids {};set values {};foreach parameter [dict get $p statistical_results training parameters] {lappend units [::GX::ScientificTransportv1::text [dict get $parameter unit]];lappend ids [::GX::ScientificTransportv1::text [dict get $parameter id]];lappend values [dict get $parameter value]}
    dict set opts parameter_ids [dict create kind cell items $ids]
    dict set opts parameter_values [expr {[llength $values] ? [::GX::ScientificTransportv1::array [list [llength $values] 1] $values] : [::GX::ScientificTransportv1::empty]}]
    dict set opts parameter_units [dict create kind cell items $units]
    dict set opts source_reference [::GX::ScientificTransportv1::text [dict merge $reference [dict create model [dict get $p model] source_kind [dict get $p source_kind] producer viewer.dataset_curve_fit numeric_api NUMERIC_API_v1 source_sha256 [::GX::datasetPublicationV2DictDefault $p source_sha256 {}]]]]
    if {$orientation eq "r_of_theta"} {
        set frame {};dict for {key value} [dict get $p polar_frame] {
            if {$key in {origin theta_zero clockwise angle_cut}} {set node [::GX::ScientificTransportv1::array [list 1 [llength $value]] $value]} else {set node [::GX::ScientificTransportv1::text $value]}
            dict set frame $key $node
        }
        dict set opts polar_frame [::GX::ScientificTransportv1::struct $frame]
    }
    return [::GX::NumericAPIv1::callOperation model_export [list $model] [::GX::ScientificTransportv1::struct $opts]]
}
proc ::GX::DatasetCurveFit::_modelExport {w} {
    variable state
    set selected [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selected]!=1} {error {Select one accepted model to export}}
    set record [lindex $state($w,records) [lindex $selected 0]]
    set path [tk_getSaveFile -parent $w -title {Export independent model bundle} -defaultextension .py -initialfile fit_model.py]
    if {$path eq {}} return
    set stem [file rootname $path];set name [file tail $stem]
    set reference [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    set code [resultExport $reference $name];set bundle {}
    foreach {field suffix} {python .py octave .m latex .tex metadata_json .json} {
        lappend bundle [dict create id model_$field destination ${stem}${suffix} writer [list ::GX::DatasetCurveFit::_recipeWrite [dict get $code $field]]]
    }
    return [::GX::filePublicationPublishBundle $bundle]
}
