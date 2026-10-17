# CORE interprets explicit physical conditions on captured parameters. This is
# a point-value review, not another estimator, uncertainty model or fit authority.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::physicalPlausibility {source rules {context {}}} {
    validate $source
    if {[dict get $source schema] ne "gxtxt.statistical_result.v1"} {_error {Physical review requires one captured parameter result}}
    if {[llength $rules]>32||[llength [dict get $source parameters]]>128} {_error {Physical review supports at most 32 rules and 128 parameters}}
    _keys $context {domain} physical_review_context
    if {[dict exists $context domain]} {
        set domain [dict get $context domain];_keys $domain {minimum maximum unit} physical_review_domain
        foreach key {minimum maximum unit} {if {![dict exists $domain $key]} {_error "Physical review domain requires $key"}}
        foreach key {minimum maximum} {if {![_finite [dict get $domain $key]]} {_error {Physical review domain must be finite}}}
        if {[dict get $domain minimum]>[dict get $domain maximum]} {_error {Physical review domain must be ordered}}
        _physicalText [dict get $domain unit] unit 256
    }
    set parameters {};foreach parameter [dict get $source parameters] {dict set parameters [dict get $parameter id] $parameter}
    set normalized {};set checks {};set ids {};set evaluated 0;set advisory 0;set invalid 0;set disabled 0;set unavailable 0
    foreach rule $rules {
        _keys $rule {id label parameter_id unit kind severity enabled lower upper lower_inclusive upper_inclusive maximum_fraction rationale} physical_rule
        foreach key {id parameter_id unit kind rationale} {if {![dict exists $rule $key]} {_error "Physical rule requires $key"}}
        set id [dict get $rule id]
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $id]||$id in $ids} {_error {Physical rule IDs must be distinct identifiers}}
        lappend ids $id
        set pid [dict get $rule parameter_id]
        if {![dict exists $parameters $pid]} {_error "Physical rule refers to an uncaptured parameter: $pid"}
        set parameter [dict get $parameters $pid]
        set unit [dict get $rule unit];_physicalText $unit unit 256
        # Rules deliberately use the exact captured parameter unit. A review
        # never rewrites coefficients or replays a changed user unit registry.
        if {$unit ne [dict get $parameter unit]} {_error {Physical bounds must use the captured parameter unit; convert the declared bounds explicitly}}
        set kind [dict get $rule kind]
        if {$kind ni {interval domain_fraction}} {_error {Physical rule kind must be interval or domain_fraction}}
        set label [_get $rule label $id];_physicalText $label label 256
        set rationale [dict get $rule rationale];_physicalText $rationale rationale 2048
        set severity [_get $rule severity advisory]
        if {$severity ni {advisory domain_requirement}} {_error {Physical rule severity must be advisory or domain_requirement}}
        set enabled [_physicalBoolean [_get $rule enabled 1]]
        set r [dict create id $id label $label parameter_id $pid unit $unit kind $kind severity $severity enabled $enabled rationale $rationale]
        set limits {}
        if {$kind eq "interval"} {
            if {[dict exists $rule maximum_fraction]||(![dict exists $rule lower]&&![dict exists $rule upper])} {_error {An interval rule needs at least one explicit bound and no domain fraction}}
            foreach side {lower upper} {
                if {[dict exists $rule $side]} {
                    set bound [dict get $rule $side]
                    if {![_finite $bound]} {_error {Physical bounds must be finite}}
                    dict set r $side $bound;dict set limits $side $bound
                    set inclusive [_physicalBoolean [_get $rule ${side}_inclusive 1]]
                    dict set r ${side}_inclusive $inclusive;dict set limits ${side}_inclusive $inclusive
                } elseif {[dict exists $rule ${side}_inclusive]} {_error {Inclusive flag requires its corresponding bound}}
            }
            if {[dict exists $r lower]&&[dict exists $r upper]&&([dict get $r lower]>[dict get $r upper]||([dict get $r lower]==[dict get $r upper]&&(![dict get $r lower_inclusive]||![dict get $r upper_inclusive])))} {_error {Physical interval is empty or reversed}}
        } else {
            foreach key {lower upper lower_inclusive upper_inclusive} {if {[dict exists $rule $key]} {_error {A domain-fraction rule cannot also declare interval bounds}}}
            set fraction [_get $rule maximum_fraction 1]
            if {![_finite $fraction]||$fraction<=0} {_error {Maximum domain fraction must be positive and finite}}
            dict set r maximum_fraction $fraction
            if {[dict exists $context domain]} {
                if {[dict get $domain unit] ne $unit} {_error {Domain-width comparison requires the exact declared physical-domain unit}}
                set span [expr {double([dict get $domain maximum])-double([dict get $domain minimum])}]
                set upper [expr {$fraction*$span}]
                if {![_finite $span]||![_finite $upper]} {_error {Physical domain width is not finitely representable}}
                if {$span>0} {set limits [dict create lower 0 lower_inclusive 1 upper $upper upper_inclusive 1]}
            }
        }
        lappend normalized $r
        set item [dict create rule $r parameter_role [dict get $parameter role] status unavailable outcome unavailable reason {} limits $limits]
        if {[dict exists $parameter value]&&[_finite [dict get $parameter value]]} {dict set item value [dict get $parameter value]}
        if {!$enabled} {
            incr disabled;dict set item status not_applicable;dict set item outcome disabled;dict set item reason {Rule explicitly disabled; no condition was assessed}
        } elseif {![dict exists $item value]} {
            incr unavailable;dict set item reason {Captured parameter has no finite value}
        } elseif {$limits eq {}} {
            incr unavailable;dict set item reason {A positive declared physical-domain width is required}
        } else {
            incr evaluated;set value [dict get $item value];set violated 0
            foreach side {lower upper} {
                if {![dict exists $limits $side]} continue
                set bound [dict get $limits $side];set inclusive [dict get $limits ${side}_inclusive]
                if {($side eq "lower"&&($value<$bound||(!$inclusive&&$value==$bound)))||($side eq "upper"&&($value>$bound||(!$inclusive&&$value==$bound)))} {set violated 1}
            }
            dict set item status value;dict set item outcome [expr {$violated?"violation":"satisfied"}]
            if {$violated} {
                if {$severity eq "domain_requirement"} {incr invalid;dict set item reason {Captured value violates the explicitly declared physical domain requirement}} else {incr advisory;dict set item reason {Captured value triggers the optional physical advisory}}
            } else {dict set item reason {Captured point value satisfies this declared condition; this does not establish model validity}}
        }
        lappend checks $item
    }
    set assessment no_violations
    if {$invalid} {set assessment domain_requirements_violated} elseif {$advisory} {set assessment advisories_present} elseif {$unavailable} {set assessment incomplete} elseif {!$evaluated} {set assessment not_assessed}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.physical_plausibility_review.v1 \
        request [dict create source $source rules $normalized context $context] \
        status [expr {$unavailable?"unavailable":($evaluated?"value":"not_applicable")}] assessment $assessment \
        coefficient_space [_get [dict get $source context] coefficient_space original_physical] \
        rule_count [llength $rules] evaluated_count $evaluated advisory_count $advisory invalid_domain_count $invalid disabled_count $disabled unavailable_count $unavailable checks $checks \
        assumptions {{Rules compare captured parameter point values in their stated coefficient coordinates and exact units} {A satisfied condition is not evidence that a model is correct or that its parameter uncertainty is small} {Domain requirements and advisory conditions are explicit user or model declarations; this review does not alter a fit} {Disabling a review rule cannot relax intrinsic model domains, solver bounds or measurement requirements} {No fit, statistics, confidence interval or posterior probability is computed by this review}}]
}
proc ::GX::StatisticsV1::_physicalText {value label maximum} {
    if {$value eq {}||[string length $value]>$maximum||[regexp {[\x00-\x1f]} $value]} {_error "Physical review $label must be nonempty bounded text"}
}
proc ::GX::StatisticsV1::_physicalBoolean {value} {
    if {![_finite $value]||($value!=0&&$value!=1)} {_error {Physical rule flags must be boolean 0 or 1}}
    return [expr {int($value)}]
}
proc ::GX::StatisticsV1::_physicalEqual {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error {Physical review fields changed}}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key in {request context domain rule limits}} {_physicalEqual $value $other
        } elseif {$key in {rules checks}} {
            if {[llength $value]!=[llength $other]} {_error {Physical review rule count changed}}
            foreach a $value b $other {_physicalEqual $a $b}
        } elseif {$key in {api_version rule_count evaluated_count advisory_count invalid_domain_count disabled_count unavailable_count value minimum maximum lower upper lower_inclusive upper_inclusive maximum_fraction enabled}} {
            if {![_finite $other]||$value!=$other} {_error "Physical review changed $key"}
        } elseif {$key eq "assumptions"} {
            if {[llength $value]!=[llength $other]} {_error {Physical review assumptions changed}}
            foreach a $value b $other {if {$a ne $b} {_error {Physical review assumptions changed}}}
        } elseif {$value ne $other} {_error "Physical review changed $key"}
    }
}
proc ::GX::StatisticsV1::_physicalValidate {result} {
    set request [dict get $result request];_keys $request {source rules context} physical_review_request
    set expected [physicalPlausibility [dict get $request source] [dict get $request rules] [dict get $request context]]
    _physicalEqual $expected $result
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::physicalPlausibilityReport {result} {
    validate $result
    if {[dict get $result schema] ne "gxtxt.physical_plausibility_review.v1"} {_error {Expected a physical plausibility review}}
    set text "Physical plausibility review\nAssessment: [dict get $result assessment]\nCoefficient space: [dict get $result coefficient_space]\n"
    foreach item [dict get $result checks] {
        set rule [dict get $item rule]
        append text "\n[dict get $rule label] — [dict get $rule severity]\nParameter: [dict get $rule parameter_id] ([dict get $rule unit]), [dict get $item parameter_role]\n"
        if {[dict exists $item value]} {append text "Captured value: [dict get $item value] [dict get $rule unit]\n"}
        append text "Condition: [dict get $rule rationale]\nOutcome: [dict get $item outcome] — [dict get $item reason]\n"
        foreach side {lower upper} {if {[dict exists $item limits $side]} {append text "[string totitle $side] bound: [dict get $item limits $side] [dict get $rule unit] ([expr {[dict get $item limits ${side}_inclusive]?"inclusive":"exclusive"}])\n"}}
    }
    append text "\n[join [dict get $result assumptions] \n]\n";return $text
}
