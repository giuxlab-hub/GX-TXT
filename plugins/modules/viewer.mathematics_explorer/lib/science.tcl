# GX-TXT Mathematics Explorer — validation, authorized service adapters and state
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::MathematicsExplorer {}

proc ::GX::MathematicsExplorer::finiteNumber {value label} {
    if {![string is double -strict $value]} {error "$label must be a finite real number."}
    if {[catch {set number [expr {double($value)}]}]} {
        error "$label must be finite (NaN/Inf is not allowed)."
    }
    if {$number != $number || abs($number) == Inf} {
        error "$label must be finite (NaN/Inf is not allowed)."
    }
    return $number
}
proc ::GX::MathematicsExplorer::initialState {} {
    return [dict create schema 1 title {Mathematics Explorer} \
        xmin -6 xmax 6 samples 301 symbol_units [dict create x 1 a 1 b 1 c 1] output_unit 1 view_axes {} parameters [dict create a 1 b 1 c 0] \
        derivative 0 functions [list \
        [dict create id f1 label {Function 1} preset Sine enabled 1 expression {a*sin(b*x)+c}] \
        [dict create id f2 label {Function 2} preset Polynomial enabled 0 expression {a*x^2+b*x+c}] \
        [dict create id f3 label {Function 3} preset Decay enabled 0 expression {a*exp(-b*x)+c}]]]
}
proc ::GX::MathematicsExplorer::presets {} {
    return [dict create Sine {a*sin(b*x)+c} Polynomial {a*x^2+b*x+c} \
        Decay {a*exp(-b*x)+c} Gaussian {a*exp(-((x-b)/c)^2)} \
        Linear {a*x+b} Custom {}]
}
proc ::GX::MathematicsExplorer::validateState {state} {
    if {[catch {dict size $state}]} {error "Saved mathematics state is not a dictionary."}
    foreach {key value} {symbol_units {x 1 a 1 b 1 c 1} output_unit 1 view_axes {}} {if {![dict exists $state $key]} {dict set state $key $value}}
    foreach symbol {x a b c} {if {![dict exists $state symbol_units $symbol]} {error "Explicit unit missing for $symbol"};set unit [dict get $state symbol_units $symbol];::GX::unitRegistryArithmeticPlan + $unit $unit}
    ::GX::unitRegistryArithmeticPlan + [dict get $state output_unit] [dict get $state output_unit]
    foreach field {schema title xmin xmax samples parameters derivative functions} {
        if {![dict exists $state $field]} {error "Mathematics state is missing '$field'."}
    }
    if {[dict get $state schema] ne "1"} {error "Unsupported mathematics state format."}
    set title [dict get $state title]
    if {[string length $title] > 100 || [regexp {[\r\n\t]} $title]} {error "Invalid plot title."}
    set xmin [finiteNumber [dict get $state xmin] {X minimum}]
    set xmax [finiteNumber [dict get $state xmax] {X maximum}]
    if {$xmin >= $xmax} {error "X maximum must be greater than X minimum."}
    set n [dict get $state samples]
    if {![string is integer -strict $n] || $n < 32 || $n > 1201} {error "Sample count must be an integer between 32 and 1201."}
    if {[dict get $state derivative] ni {0 1}} {error "Derivative flag must be 0 or 1."}
    set params [dict get $state parameters]
    if {[catch {dict size $params}]} {error "Parameters are invalid."}
    foreach p {a b c} {
        if {![dict exists $params $p]} {error "Missing parameter $p."}
        finiteNumber [dict get $params $p] "Parameter $p"
    }
    set functions [dict get $state functions]
    if {[llength $functions] != 3} {error "Exactly three function slots must be present."}
    set active 0; set index 0
    foreach fn $functions {
        incr index
        if {[catch {dict size $fn}]} {error "Invalid function slot $index."}
        foreach key {id label preset enabled expression} {
            if {![dict exists $fn $key]} {error "Incomplete function slot $index."}
        }
        if {[dict get $fn id] ne "f$index"} {error "Function slot IDs must remain stable."}
        if {[dict get $fn enabled] ni {0 1}} {error "Invalid enabled flag for function $index."}
        if {[dict get $fn preset] ni [dict keys [presets]]} {error "Invalid preset for function $index."}
        set label [dict get $fn label]
        if {[string length $label] > 72 || [regexp {[\r\n\t]} $label]} {error "Invalid function label."}
        parseExpression [dict get $fn expression]
        if {[dict get $fn enabled]} {incr active}
    }
    if {$active == 0} {error "Select at least one function."}
    if {[dict get $state derivative] && ![dict get [lindex $functions 0] enabled]} {
        error "Numerical differentiation requires Function 1 to be enabled."
    }
    return $state
}
proc ::GX::MathematicsExplorer::activateNumerics {} {
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    foreach capability {elementwise_unary elementwise_binary uniform_grid integration differentiation} {
        ::GX::NumericAPIv1::requireCapability $capability
    }
    if {![::GX::NumericAPIv1::octaveAvailable]} {error "The public Numeric service requires its configured Octave runtime."}
}
proc ::GX::MathematicsExplorer::_operand {values} {
    set n [llength $values]
    if {$n == 0} {error "Empty mathematical operand."}
    return [dict create kind [expr {$n == 1 ? "scalar" : "vector"}] value $values]
}
proc ::GX::MathematicsExplorer::_numericValues {result} {
    if {![dict exists $result values]} {error "Public NUMERIC_API did not return a numeric values field."}
    set values [dict get $result values]
    foreach n $values {finiteNumber $n {Computed value}}
    return $values
}
proc ::GX::MathematicsExplorer::evaluateExpression {expression x parameters units outputUnit} {
    set symbols [dict create x [::GX::ScientificTransportv1::array [list [llength $x] 1] $x]]
    dict for {id value} $parameters {dict set symbols $id [::GX::ScientificTransportv1::array {1 1} [list $value]]}
    set unitNodes {};dict for {id unit} $units {dict set unitNodes $id [::GX::ScientificTransportv1::text $unit]}
    return [::GX::NumericAPIv1::callOperation expression_evaluate [list \
        [::GX::ScientificTransportv1::text $expression] [::GX::ScientificTransportv1::struct $symbols] \
        [::GX::ScientificTransportv1::struct $unitNodes]] \
        [::GX::ScientificTransportv1::struct [dict create output_unit [::GX::ScientificTransportv1::text $outputUnit]]]]
}
proc ::GX::MathematicsExplorer::analyzeFirst {state mode} {
    set state [validateState $state];activateNumerics
    if {$mode ni {roots intersections extrema}} {error {Unsupported mathematical analysis}}
    set first [lindex [dict get $state functions] 0]
    if {![dict get $first enabled]} {error {Enable Function1 for analysis}}
    set symbols {};dict for {id value} [dict get $state parameters] {dict set symbols $id [::GX::ScientificTransportv1::array {1 1} [list $value]]}
    set units {};dict for {id value} [dict get $state symbol_units] {dict set units $id [::GX::ScientificTransportv1::text $value]}
    set fields [dict create expression [::GX::ScientificTransportv1::text [dict get $first expression]] \
        variable [::GX::ScientificTransportv1::text x] mode [::GX::ScientificTransportv1::text $mode] \
        interval [::GX::ScientificTransportv1::array {2 1} [list [dict get $state xmin] [dict get $state xmax]]] \
        symbols [::GX::ScientificTransportv1::struct $symbols] symbol_units [::GX::ScientificTransportv1::struct $units]]
    if {$mode eq {intersections}} {
        set second [lindex [dict get $state functions] 1]
        if {![dict get $second enabled]} {error {Enable Function2 for intersections}}
        dict set fields expression2 [::GX::ScientificTransportv1::text [dict get $second expression]]
    }
    return [::GX::NumericAPIv1::callOperation expression_analyze [list [::GX::ScientificTransportv1::struct $fields]] \
        [::GX::ScientificTransportv1::struct [dict create output_unit [::GX::ScientificTransportv1::text [dict get $state output_unit]]]]]
}
proc ::GX::MathematicsExplorer::nativeModel {state computed} {
    set panels {};set ordinary {};set n 0
    foreach source [dict get $computed series] {
        set points {};set rows {};set bounds {Inf Inf -Inf -Inf};set row 0
        foreach x [dict get $computed x] y [dict get $source values] {
            lappend points [list $x $y];lappend rows $row;incr row
            foreach i {0 1 2 3} value [list $x $y $x $y] {lset bounds $i [expr {$i<2?min([lindex $bounds $i],$value):max([lindex $bounds $i],$value)}]}
        }
        set series [dict create id [dict get $source id] label [dict get $source label] kind line axis left \
            points $points source_rows $rows full_bounds $bounds breaks {} style {line_width 1.5}]
        if {[dict get $source id] eq {f1_derivative}} {
            lappend panels [dict create id derivative axes [dict create x [dict create label "x ([dict get $state symbol_units x])"] \
                left [dict create label "Derivative ([dict get $source unit])"]] series [list $series] annotations {}]
        } else {lappend ordinary $series}
    }
    set main [dict create id functions axes [dict create x [dict create label "x ([dict get $state symbol_units x])"] \
        left [dict create label "Function ([dict get $state output_unit])"]] series $ordinary annotations {}]
    return [dict create title [dict get $state title] panels [linsert $panels 0 $main] \
        native_presentation [dict create schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1 graphics {} layout {layout_auto 1} legend {placement inside}]]
}
proc ::GX::MathematicsExplorer::publishGraph {state computed documentId token datasetId} {
    publishComputed $state $computed $documentId $token $datasetId
    set panels {};set ordinary {}
    foreach source [dict get $computed series] {
        set series [dict create id [dict get $source id] dataset_id $datasetId x_variable_id x \
            y_variable_id [dict get $source id] kind line label [dict get $source label] axis left style {}]
        if {[dict get $source id] eq {f1_derivative}} {lappend panels [dict create id derivative axes {} series [list $series] annotations {}]} else {lappend ordinary $series}
    }
    set panels [linsert $panels 0 [dict create id functions axes {} series $ordinary annotations {}]]
    set spec [dict create schema PLOT_DATASET_PLOTSPEC_v2 graph_type cartesian_2d graph_id plot.dataset.xy \
        title [dict get $state title] defaults {style {}} panels $panels output {}]
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    try {
        set ref [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
        ::GX::PlotDatasetAPIv4::render $ref
        ::GX::graphMetadataUpdate [dict merge {kind provider module_id plot.dataset} $ref] \
            [dict create mathematics.document_id $documentId mathematics.dataset_id $datasetId mathematics.formulas [dict get $state functions]]
        ::GX::sessionPersistenceCommit
        return $ref
    } on error {message options} {return -options $options "Dataset $datasetId was committed and preserved; Graph phase failed: $message"}
}
proc ::GX::MathematicsExplorer::calculate {state} {
    set state [validateState $state]
    activateNumerics
    set grid [::GX::NumericAPIv1::uniformGrid [dict get $state xmin] [dict get $state xmax] [dict get $state samples] [dict create mode count]]
    if {![dict exists $grid x]} {error "Uniform Grid service returned no X coordinate."}
    set x [dict get $grid x]
    set samples [dict get $state samples]
    if {[llength $x] != $samples} {error "Numeric service returned an unexpected grid length."}
    set series {}; set outputs [dict create x $x];set outputUnits [dict create x [dict get $state symbol_units x]]
    set params [dict get $state parameters]
    foreach fn [dict get $state functions] {
        if {![dict get $fn enabled]} {continue}
        set response [evaluateExpression [dict get $fn expression] $x $params [dict get $state symbol_units] [dict get $state output_unit]]
        set values [dict get $response values]
        if {[llength $values] == 1} {set values [lrepeat $samples [lindex $values 0]]}
        if {[llength $values] != $samples} {error "Formula [dict get $fn id] produced a non-vector result."}
        dict set outputs [dict get $fn id] $values
        dict set outputUnits [dict get $fn id] [dict get $response unit]
        lappend series [dict create id [dict get $fn id] label [dict get $fn label] values $values unit [dict get $response unit]]
    }
    if {[dict get $state derivative]} {
        set dy [::GX::NumericAPIv1::differentiate $x [dict get $outputs f1]]
        if {![dict exists $dy dy_dx]} {error "Differentiation service returned no dy_dx field."}
        set values [dict get $dy dy_dx]
        if {[llength $values] != $samples} {error "Differentiation produced an unexpected result length."}
        foreach n $values {finiteNumber $n {Derivative}}
        set plan [::GX::unitRegistryArithmeticPlan / [dict get $state output_unit] [dict get $state symbol_units x]]
        set scale [expr {[dict get $plan left_scale]/[dict get $plan right_scale]}]
        set converted {};foreach value $values {lappend converted [expr {$value*$scale}]}
        dict set outputs f1_derivative $converted
        dict set outputUnits f1_derivative [dict get $plan output_unit]
        lappend series [dict create id f1_derivative label {d(Function 1)/dx} values $converted unit [dict get $plan output_unit]]
    }
    return [dict create x $x series $series outputs $outputs output_units $outputUnits]
}
proc ::GX::MathematicsExplorer::integralOfFirst {result} {
    if {![dict exists $result outputs f1]} {error "Function 1 is not available."}
    activateNumerics
    set response [::GX::NumericAPIv1::integrate [dict get $result x] [dict get $result outputs f1]]
    if {![dict exists $response value]} {error "Integration service returned no definite integral value."}
    return [finiteNumber [dict get $response value] {Integral}]
}
proc ::GX::MathematicsExplorer::renderPreview {state computed directory} {
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    ::GX::PlotDatasetAPIv4::requireCapability transient_2d_curves
    return [::GX::PlotDatasetAPIv4::renderTransientCurves2D \
        [dict get $computed x] [dict get $computed series] \
        [dict get $state title] $directory ""]
}
proc ::GX::MathematicsExplorer::sessionToken {} {
    ::GX::sessionInspectionCurrentSession
    return [::GX::interactiveDocumentSessionToken]
}
proc ::GX::MathematicsExplorer::saveDocument {state currentId sessionToken} {
    validateState $state
    if {$sessionToken ne [sessionToken]} {error "Session changed. Work was not saved in another Session."}
    set payload $state ;# Tcl dict is structured UTF-8 text, parsed as data (never eval'ed).
    if {$currentId eq ""} {
        set record [::GX::interactiveDocumentCreate viewer.mathematics_explorer mathematics_explorer gxtxt.mathematics_explorer.state 1 $payload]
    } else {
        set existing [::GX::interactiveDocumentRead $currentId]
        if {[dict get $existing module_id] ne "viewer.mathematics_explorer" || [dict get $existing provider_id] ne "mathematics_explorer"} {
            error "Document belongs to another viewer."
        }
        set record [::GX::interactiveDocumentUpdate $currentId $payload]
    }
    return [dict get $record id]
}
proc ::GX::MathematicsExplorer::readDocument {id sessionToken} {
    if {$sessionToken ne [sessionToken]} {error "Session changed. Choose a document from the current Session."}
    set record [::GX::interactiveDocumentRead $id]
    if {[dict get $record module_id] ne "viewer.mathematics_explorer" || \
        [dict get $record provider_id] ne "mathematics_explorer" || \
        [dict get $record format] ne "gxtxt.mathematics_explorer.state" || \
        [dict get $record format_version] ne "1"} {error "Document has the wrong owner or format."}
    return [validateState [dict get $record payload]]
}
proc ::GX::MathematicsExplorer::listDocuments {} {
    return [::GX::interactiveDocumentList viewer.mathematics_explorer mathematics_explorer]
}
proc ::GX::MathematicsExplorer::publishComputed {state computed documentId sessionToken outputId} {
    if {$sessionToken ne [sessionToken]} {error "Session changed; publication refused."}
    validateState $state
    if {$documentId eq ""} {error "Save the mathematical document before publishing."}
    set doc [::GX::interactiveDocumentRead $documentId]
    if {[dict get $doc module_id] ne "viewer.mathematics_explorer" ||
        [dict get $doc provider_id] ne "mathematics_explorer" ||
        [dict get $doc format] ne "gxtxt.mathematics_explorer.state" ||
        [dict get $doc format_version] ne "1"} {
        error "Unrelated or incompatible document cannot own this result."
    }
    if {![dict exists $doc payload] ||
        [validateState [dict get $doc payload]] ne $state} {
        error "The current mathematical model differs from the saved document; save it before publication."
    }
    set outputId [::GX::datasetPublicationV2ValidateId dataset $outputId]
    set outputs [dict get $computed outputs]
    set expected [list x]
    foreach fn [dict get $state functions] {if {[dict get $fn enabled]} {lappend expected [dict get $fn id]}}
    if {[dict get $state derivative]} {lappend expected f1_derivative}
    if {[lsort $expected] ne [lsort [dict keys $outputs]]} {error "Computed data does not match the current mathematical model."}
    set samples [dict get $state samples]
    foreach var $expected {
        if {[llength [dict get $outputs $var]] != $samples} {error "Incorrect computed data length for '$var'."}
        foreach n [dict get $outputs $var] {finiteNumber $n "Output '$var'"}
    }
    set provenance "Mathematics Explorer document $documentId; title=[dict get $state title]; domain=[dict get $state xmin],[dict get $state xmax]; samples=$samples; params=[dict get $state parameters]; functions=[dict get $state functions]; derivative=[dict get $state derivative]; symbol_units=[dict get $state symbol_units]; output_unit=[dict get $state output_unit]"
    set definition [dict create dataset_id $outputId contract table.generic storage csv \
        producer_version [::GX::moduleField viewer.mathematics_explorer version {}] source {Mathematics Explorer} provenance $provenance \
        notes {Sampled mathematical functions through public Numeric. Numerical calculus is grid-dependent; units are explicitly declared and checked.}]
    set session [::GX::sessionInspectionCurrentSession]
    set plan [::GX::datasetPublicationV2Prepare $session viewer.mathematics_explorer $definition]
    set writer ""
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        foreach var $expected {
            set role [expr {$var eq "x" ? "coordinate" : "data"}]
            ::GX::datasetPublicationV2DeclareVariable $writer $var [dict create \
                name $var display_label $var unit [dict get $computed output_units $var] semantic_role "" dtype float64 \
                rank 1 dimension_ids row coordinate_role $role axis_kind explicit]
        }
        ::GX::datasetPublicationV2Append $writer row $outputs
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        return -options $options $message
    }
}
