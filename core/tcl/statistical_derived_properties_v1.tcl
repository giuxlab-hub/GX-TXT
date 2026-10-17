# Derived physical properties: CORE owns eligibility and interpretation;
# Numeric owns expression evaluation, derivatives and covariance propagation.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::derivedPropertiesPlan {source definitions} {
    validate $source
    if {[dict get $source schema] ne "gxtxt.statistical_result.v1"} {_error {Derived properties require one captured fitted result}}
    set parameters [dict get $source parameters]
    if {[llength $parameters]<1||[llength $parameters]>128} {_error {Derived properties require 1..128 captured parameters}}
    if {[llength $definitions]<1||[llength $definitions]>32} {_error {Define 1..32 derived properties}}
    set plan [dict create api_id STATISTICAL_DERIVED_PROPERTIES_PLAN_v1 api_version 1 source_model_id [dict get $source model id] coefficient_space [_get [dict get $source context] coefficient_space original_physical] parameter_ids {} parameter_aliases {} parameter_units {} parameter_roles {} parameter_values {} free_indices {} source_covariance {} definitions {}]
    set index 0;set free {}
    foreach parameter $parameters {
        if {![dict exists $parameter value]||![_finite [dict get $parameter value]]} {_error {Every captured parameter must have a finite value}}
        foreach field {id unit role value} target {parameter_ids parameter_units parameter_roles parameter_values} {dict lappend plan $target [dict get $parameter $field]}
        dict lappend plan parameter_aliases p$index
        if {[dict get $parameter role] eq "free"} {lappend free $index;dict lappend plan free_indices [expr {$index+1}]}
        incr index
    }
    set covariance [dict get $source quantities covariance]
    dict set plan status [dict get $covariance status];dict set plan reason [dict get $covariance reason]
    if {![llength $free]} {dict set plan status not_applicable;dict set plan reason {No freely estimated parameters; fixed values are conditional inputs, not measurements with zero uncertainty}}
    if {[dict get $plan status] eq "value"} {
        # Unlike parameter correlations, propagation can legitimately include
        # a zero diagonal. Numeric checks the full covariance for PSD validity.
        foreach i $free {
            set row {};foreach j $free {lappend row [lindex [dict get $covariance value] $i $j]}
            dict lappend plan source_covariance $row
        }
    }
    set seen {}
    foreach definition $definitions {
        _keys $definition {id label expression unit constants} derived_property
        foreach key {id expression unit} {if {![dict exists $definition $key]} {_error "Derived property requires $key"}}
        set id [dict get $definition id]
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $id]||$id in $seen} {_error {Derived property IDs must be unique identifiers}}
        lappend seen $id
        foreach key {expression unit} {
            set text [dict get $definition $key]
            if {$text eq {}||[string length $text]>[expr {$key eq "expression"?32768:256}]||[regexp {[\x00-\x1f]} $text]} {_error "Invalid derived property $key"}
        }
        set label [_get $definition label $id]
        if {[string length $label]>256||[regexp {[\x00-\x1f]} $label]} {_error {Invalid derived property label}}
        set constants {};set ids [concat [dict get $plan parameter_aliases] {gx_query pi e}]
        foreach constant [_get $definition constants {}] {
            _keys $constant {id value unit} derived_constant
            foreach key {id value unit} {if {![dict exists $constant $key]} {_error "Derived constant requires $key"}}
            set cid [dict get $constant id]
            if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $cid]||$cid in $ids||![_finite [dict get $constant value]]} {_error {Derived constants require unique identifiers and finite values}}
            if {[dict get $constant unit] eq {}||[string length [dict get $constant unit]]>256||[regexp {[\x00-\x1f]} [dict get $constant unit]]} {_error {Derived constants require explicit units}}
            lappend ids $cid;lappend constants [dict create id $cid value [dict get $constant value] unit [dict get $constant unit]]
        }
        if {[llength $constants]>32} {_error {At most32 exact constants per property are supported}}
        dict lappend plan definitions [dict create id $id label $label expression [dict get $definition expression] unit [dict get $definition unit] constants $constants]
    }
    return $plan
}
proc ::GX::StatisticsV1::_sameDerivedPlan {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Derived property plan fields changed}}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key eq "definitions"} {continue};# Rebuilt from these exact validated declarations.
        if {$key eq "source_covariance"} {
            if {[llength $value]!=[llength $other]} {_error {Derived covariance row count changed}}
            set a {};set b {}
            foreach row $value otherRow $other {
                if {[llength $row]!=[llength $otherRow]} {_error {Derived covariance column count changed}}
                lappend a {*}$row;lappend b {*}$otherRow
            }
        } else {set a $value;set b $other}
        if {$key in {api_version parameter_values free_indices source_covariance}} {
            if {[llength $a]!=[llength $b]} {_error "Derived plan changed $key"}
            foreach x $a y $b {if {![_finite $y]||abs($x-$y)>4*2.2204460492503131e-16*max(abs($x),abs($y))} {_error "Derived plan changed $key"}}
        } elseif {$key in {parameter_ids parameter_aliases parameter_units parameter_roles}} {
            if {[llength $a]!=[llength $b]} {_error "Derived plan changed $key"}
            foreach x $a y $b {if {$x ne $y} {_error "Derived plan changed $key"}}
        } elseif {$value ne $other} {_error "Derived plan changed $key"}
    }
}
proc ::GX::StatisticsV1::derivedPropertiesInterpretation {source numeric} {
    _keys $numeric {numeric_api operation plan properties propagation_indices propagation derivative_method fit_performed} derived_properties_numeric
    if {[_get $numeric numeric_api {}] ne "NUMERIC_API_v1"||[_get $numeric operation {}] ne "derived_properties"||[_get $numeric derivative_method {}] ne "two_sided_automatic_differentiation"||[_get $numeric fit_performed 1]!=0} {_error {Derived properties require the public Numeric evaluation receipt}}
    set plan [derivedPropertiesPlan $source [dict get $numeric plan definitions]]
    _sameDerivedPlan $plan [dict get $numeric plan]
    set rows [dict get $numeric properties];set definitions [dict get $plan definitions]
    if {[llength $rows]!=[llength $definitions]} {_error {Derived property result count changed}}
    set out [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 schema gxtxt.derived_properties.v1 api_version 1 request [dict create source $source numeric $numeric] plan $plan properties {} propagation {} assumptions [_propagationAssumptions covariance]]
    dict lappend out assumptions {Constants and fixed parameters are treated as exact conditional inputs; their uncertainty is not included}
    dict lappend out assumptions {Nondifferentiable or undefined expressions have no ordinary first-order standard uncertainty}
    set ids {};set units {};set indices {};set index 0
    foreach row $rows definition $definitions {
        incr index
        _keys $row {id value_status value reason derivative_valid source_sha256 binding_sha256} derived_property_value
        if {[dict get $row id] ne [dict get $definition id]||[dict get $row value_status] ni {value undefined}||[dict get $row derivative_valid] ni {0 1 0.0 1.0}} {_error {Invalid derived property value identity or status}}
        foreach digest {source_sha256 binding_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $row $digest]]} {_error {Derived expression requires compiled identity digests}}}
        set item [dict merge $definition [dict create value_status [dict get $row value_status] reason [dict get $row reason] standard_uncertainty_status [dict get $plan status] standard_uncertainty_reason [dict get $plan reason] source_sha256 [dict get $row source_sha256] binding_sha256 [dict get $row binding_sha256]]]
        if {[dict get $row value_status] eq "value"} {
            if {![_finite [dict get $row value]]} {_error {Derived property value must be finite}}
            dict set item value [dict get $row value]
        } else {
            if {[dict get $row derivative_valid]} {_error {An undefined value cannot have a valid derivative}}
            dict set item standard_uncertainty_status undefined;dict set item standard_uncertainty_reason [dict get $row reason]
        }
        if {[dict get $row value_status] eq "value"&&![dict get $row derivative_valid]} {
            dict set item standard_uncertainty_status unavailable;dict set item standard_uncertainty_reason {Expression is not differentiable with respect to every estimated input at this point}
        }
        if {[dict get $item standard_uncertainty_status] eq "value"} {lappend ids [dict get $item id];lappend units [dict get $item unit];lappend indices $index}
        dict lappend out properties $item
    }
    set actual [dict get $numeric propagation_indices]
    if {[llength $actual]!=[llength $indices]} {_error {Derived covariance mapping changed}}
    foreach a $actual b $indices {if {![_finite $a]||$a!=$b} {_error {Derived covariance mapping changed}}}
    if {[llength $indices]} {
        set raw [dict get $numeric propagation]
        if {[dict get $raw input_count]!=[llength [dict get $plan free_indices]]} {_error {Derived covariance input identity count changed}}
        _sameInferencePlan [dict create source_covariance [dict get $plan source_covariance]] [dict create source_covariance [dict get $raw input_covariance]]
        set meaning [fromNumeric math.numeric.propagation propagate_uncertainty $raw [dict create output_ids $ids output_units $units]]
        if {[dict get $meaning quantities output_covariance status] ne "value"||[dict get $meaning quantities output_standard_uncertainties status] ne "value"} {_error {Derived propagation did not return available covariance}}
        dict set out propagation $meaning
        set properties [dict get $out properties];set errors [dict get $meaning quantities output_standard_uncertainties value]
        foreach idx $indices error $errors {
            set i [expr {$idx-1}];set row [lindex $properties $i];dict set row standard_uncertainty $error;lset properties $i $row
        }
        dict set out properties $properties
    } elseif {[dict get $numeric propagation] ne {}} {_error {Ineligible properties cannot carry propagated uncertainty}}
    return $out
}
proc ::GX::StatisticsV1::_derivedObjectEqual {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Derived property fields changed}}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key eq "constants"} {
            if {[llength $value]!=[llength $other]} {_error {Derived constants changed}}
            foreach a $value b $other {_derivedObjectEqual $a $b}
        } elseif {$key in {value standard_uncertainty}} {
            _sameInferencePlan [dict create source_parameters [list $value]] [dict create source_parameters [list $other]]
        } elseif {$value ne $other} {_error "Derived property changed $key"}
    }
}
proc ::GX::StatisticsV1::_derivedValidate {result} {
    set request [dict get $result request]
    if {[lsort [dict keys $request]] ne {numeric source}} {_error {Derived request has unvalidated fields}}
    set expected [derivedPropertiesInterpretation [dict get $request source] [dict get $request numeric]]
    if {[lsort [dict keys $result]] ne [lsort [dict keys $expected]]} {_error {Derived result has unvalidated fields}}
    foreach field {api_id api_version schema} {if {[dict get $result $field] ne [dict get $expected $field]} {_error "Derived result changed $field"}}
    _sameDerivedPlan [dict get $expected plan] [dict get $result plan]
    foreach field {definitions properties assumptions} {
        if {$field eq "definitions"} {set a [dict get $expected plan definitions];set b [dict get $result plan definitions]} else {set a [dict get $expected $field];set b [dict get $result $field]}
        if {[llength $a]!=[llength $b]} {_error "Derived $field count changed"}
        foreach x $a y $b {
            if {$field eq "assumptions"} {if {$x ne $y} {_error {Derived assumptions changed}}} else {_derivedObjectEqual $x $y}
        }
    }
    set a [dict get $expected propagation];set b [dict get $result propagation]
    if {$a eq {}} {if {$b ne {}} {_error {Unavailable derived covariance cannot be added}}} else {
        validate $b
        if {[dict get $b model id] ne "math.numeric.propagation"||[dict get $b provenance operation] ne "propagate_uncertainty"} {_error {Derived covariance has a different producer}}
        _sameInferencePlan [dict create source_covariance [dict get $a quantities output_covariance value] source_parameters [dict get $a quantities output_standard_uncertainties value]] [dict create source_covariance [dict get $b quantities output_covariance value] source_parameters [dict get $b quantities output_standard_uncertainties value]]
        foreach field {output_ids output_units} {
            set x [dict get $a context $field];set y [dict get $b context $field]
            if {[llength $x]!=[llength $y]} {_error {Derived output identities changed}}
            foreach i $x j $y {if {$i ne $j} {_error {Derived output identities changed}}}
        }
    }
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::derivedPropertiesReport {source numeric} {
    set result [derivedPropertiesInterpretation $source $numeric]
    set text "Derived physical properties\nCoefficient space: [dict get $result plan coefficient_space]\n"
    foreach item [dict get $result properties] {
        append text "\n[dict get $item label] ([dict get $item id])\nExpression: [dict get $item expression]\n"
        if {[dict get $item value_status] eq "value"} {append text "Value: [dict get $item value] [dict get $item unit]\n"} else {append text "Value: undefined — [dict get $item reason]\n"}
        if {[dict get $item standard_uncertainty_status] eq "value"} {append text "Standard uncertainty: [dict get $item standard_uncertainty] [dict get $item unit]\n"} else {append text "Standard uncertainty: [dict get $item standard_uncertainty_status] — [dict get $item standard_uncertainty_reason]\n"}
    }
    append text "\nAssumptions:\n[join [dict get $result assumptions] \n]\n"
    return $text
}
