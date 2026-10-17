# Interpretation of the existing foundation IRLS/Newton calculations.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label kind unit definition} {
        foundation_coefficients {Returned real coefficients} vector output_units {Returned coefficient iterate in original design-column order; complex estimates require the explicit real and imaginary component fields}
        foundation_design_columns {Supplied design columns} scalar count {Actual design width; this count alone does not establish independent or identifiable coefficients}
        foundation_coefficient_real {Real coefficient components} vector output_units {Real part of the returned coefficient iterate in original design-column order}
        foundation_coefficient_imaginary {Imaginary coefficient components} vector output_units {Imaginary part of the same returned coefficient iterate in original design-column order}
        foundation_iterations {Performed update iterations} scalar count {Actual number of iterations performed by the recorded foundation method}
        foundation_converged {Recorded stopping criterion satisfied} scalar dimensionless {One means the actual update norm was below its recorded threshold; this alone does not establish identifiability, a finite maximum likelihood estimate or statistical validity}
        foundation_update_norm {Last coefficient update norm} scalar unspecified {Euclidean norm of the actual last update in the supplied coefficient coordinates; mixed coefficient units have no single physical norm unit}
        foundation_threshold {Last stopping threshold} scalar unspecified {Actual threshold compared with the last coefficient update norm in the recorded numerical coordinate convention}
        foundation_tolerance {Configured stopping tolerance} scalar unspecified {Numerical tolerance used by the actual method; its absolute or relative convention is recorded in the CORE assumptions}
        foundation_iteration_limit {Configured iteration limit} scalar count {Maximum number of iterations allowed by the captured calculation}
        foundation_huber_constant {Huber weight constant} scalar dimensionless {Positive factor multiplying the current robust residual scale in the IRLS weight rule}
        foundation_last_scale {Last IRLS weight scale} scalar response {MAD-based residual scale used to form the last update, before that update; not a standard error or a refitted final residual dispersion}
        foundation_score_norm {Final score-coordinate norm} scalar unspecified {Norm of the returned design-transposed response-minus-fitted-mean vector in original design coordinates; not a calibrated test statistic}
    } {dict set quantities $id [dict create label $label kind $kind unit $unit policy foundation_regression definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_foundationRegressionFields {operation} {
    set fields {n n p foundation_design_columns coefficients foundation_coefficients coefficients_real foundation_coefficient_real coefficients_imaginary foundation_coefficient_imaginary iterations foundation_iterations converged foundation_converged last_update_norm foundation_update_norm last_threshold foundation_threshold tolerance foundation_tolerance iteration_limit foundation_iteration_limit}
    switch -- $operation {
        foundation.statistics.robust_regression {return [concat $fields {huber_constant foundation_huber_constant last_scale foundation_last_scale}]}
        foundation.statistics.logistic_regression {return $fields}
        foundation.statistics.glm {return [concat $fields {score_norm foundation_score_norm}]}
        default {_error {Unknown foundation regression operation}}
    }
}
proc ::GX::StatisticsV1::_foundationRegressionAssumptions {method family} {
    set common {{The supplied design is used as given, with no automatic intercept or feature standardization; coefficients retain design-column order} {Returned coefficients are numerical iterates; stopping by a coefficient change alone does not establish identification, global optimality or statistical model validity} {No covariance, standard error, confidence interval, p-value or sampling degrees of freedom is supplied by these foundation routines}}
    switch -- $method {
        {Huber IRLS} {return [concat $common {{Each update uses Hermitian weighted normal equations and residual magnitudes; complex coefficients retain their real and imaginary components} {The weight scale is 1.4826 times the Octave median absolute residual deviation from the residual median, with an absolute machine-epsilon floor; the last captured scale precedes the final update} {Stopping compares update norm with 1e-10 times max(1, previous coefficient norm), with at most 100 updates; this is the accepted numerical coordinate convention}}]}
        logistic_newton_weight_floor {return [concat $common {{Binary independent-response logistic interpretation is conditional on an appropriate logit model; separation can prevent a finite maximum likelihood estimate} {Newton updates use a probability-variance floor of 1e-10 and no linear-predictor clipping; stopping compares absolute update norm with 1e-9, at most 100 updates}}]}
        glm_clipped_irls {
            set specific {{IRLS update means clip the linear predictor to [-40,40], use variance floor 1e-8 and reject information-matrix reciprocal condition below 1e-12} {Stopping compares update norm with tolerance times max(1, updated coefficient norm); final fitted means are evaluated without predictor clipping}}
            if {$family eq "poisson"} {lappend specific {Poisson log-link interpretation assumes an appropriate independent count model; overdispersion is not estimated} {Poisson steps use the accepted objective backtracking rule down to scale 1/1024; the stopping flag alone is not proof of an interior maximum}}
            if {$family eq "binomial"} {lappend specific {Binary logit interpretation is conditional on an appropriate independent-response model; separation can prevent a finite maximum likelihood estimate}}
            return [concat $common $specific]
        }
        default {_error {Unknown foundation regression method}}
    }
}
proc ::GX::StatisticsV1::_foundationRegressionAdapt {operation raw context} {
    set expected [dict get {foundation.statistics.robust_regression {Huber IRLS} foundation.statistics.logistic_regression logistic_newton_weight_floor foundation.statistics.glm glm_clipped_irls} $operation]
    if {[_get $raw method {}] ne $expected} {_error {Regression result differs from its actual foundation method}}
    foreach key {input_kind family link} {dict set context $key [_get $raw $key [expr {$key eq "family"?"unspecified":($key eq "link"?"identity":"")}]]}
    dict set context method $expected;dict set context assumptions [_foundationRegressionAssumptions $expected [dict get $context family]]
    set p [_get $raw p {}]
    if {![_finite $p]||$p<1||$p>128||$p!=floor($p)} {_error {Bounded foundation interpretation requires one to 128 design coefficients}}
    if {![dict exists $context output_ids]} {set ids {};for {set i 1} {$i<=$p} {incr i} {lappend ids coefficient_$i};dict set context output_ids $ids}
    if {![dict exists $context output_units]} {dict set context output_units [lrepeat [expr {int($p)}] unspecified]}
    set numerical {}
    dict for {field quantity} [_foundationRegressionFields $operation] {
        if {$field eq "coefficients"} continue
        if {![dict exists $raw $field]} {_error {Foundation regression is missing an actual captured fact}}
        dict set numerical $quantity [dict get $raw $field]
    }
    if {[dict get $context input_kind] eq "real"} {dict set numerical foundation_coefficients [dict get $raw coefficients_real]}
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateFoundationRegression {numerical context} {
    set method [_get $context method {}];set family [_get $context family {}];set link [_get $context link {}]
    if {[_get $context assumptions {}] ne [_foundationRegressionAssumptions $method $family]} {_error {Foundation regression requires its shared CORE limitations}}
    if {[_get $context input_kind {}] ni {real complex}} {_error {Regression requires the actual real/complex input kind}}
    if {$method eq "Huber IRLS"} {
        if {$family ne "unspecified"||$link ne "identity"} {_error {Robust linear regression cannot claim a GLM family or link}}
        set c [_get $numerical foundation_huber_constant {}];if {![_finite $c]||$c<=0} {_error {Invalid captured Huber constant}}
    } else {
        if {[dict get $context input_kind] ne "real"||$family ni {binomial poisson}||$link ne [expr {$family eq "binomial"?"logit":"log"}]} {_error {Regression response family, link and input kind are inconsistent}}
        if {$method eq "logistic_newton_weight_floor"&&$family ne "binomial"} {_error {Logistic regression requires binary outcomes}}
        if {[_get $context y_unit unspecified] ni {{} unspecified 1 count dimensionless}} {_error {Binary and count responses must be dimensionless}}
    }
    foreach key {n p foundation_iterations foundation_iteration_limit} {set v [_get $numerical $key {}];if {![_finite $v]||$v<1||$v!=floor($v)} {_error {Regression dimensions and iteration counts must be positive integers}}}
    set p [dict get $numerical p];set ids [_get $context output_ids {}]
    if {[_get $numerical foundation_design_columns {}] ne $p} {_error {Design width differs from the captured coefficient count}}
    if {$p>128||[llength $ids]!=$p||[llength [lsort -unique $ids]]!=$p||{} in $ids||[llength [_get $context output_units {}]]!=$p} {_error {Coefficient identities, units and design width differ}}
    if {[dict get $numerical foundation_iterations]>[dict get $numerical foundation_iteration_limit]} {_error {Performed updates exceed the captured limit}}
    set tol [_get $numerical foundation_tolerance {}];if {![_finite $tol]||$tol<=0} {_error {Regression tolerance must be positive and finite}}
    if {$method eq "Huber IRLS"&&($tol!=1e-10||[dict get $numerical foundation_iteration_limit]!=100)||$method eq "logistic_newton_weight_floor"&&($tol!=1e-9||[dict get $numerical foundation_iteration_limit]!=100)} {_error {Captured fixed stopping settings changed}}
    set flag [_get $numerical foundation_converged {}];set change [_get $numerical foundation_update_norm {}];set threshold [_get $numerical foundation_threshold {}]
    if {![_finite $flag]||($flag!=0&&$flag!=1)||![_finite $threshold]||$threshold<=0} {_error {Invalid captured stopping facts}}
    if {[_finite $change]&&$change<0} {_error {Update norm cannot be negative}}
    if {$flag!=([_finite $change]&&$change<$threshold)} {_error {Stopping flag differs from the captured norm and threshold}}
    foreach key {foundation_coefficient_real foundation_coefficient_imaginary} {if {[llength [_get $numerical $key {}]]!=$p} {_error {Coefficient components differ from design width}}}
    if {[dict get $context input_kind] eq "real"} {
        if {[_get $numerical foundation_coefficients {}] ne [dict get $numerical foundation_coefficient_real]} {_error {Real coefficient aliases differ}}
        foreach v [dict get $numerical foundation_coefficient_imaginary] {if {![_finite $v]||$v!=0} {_error {Real coefficient output has a nonzero imaginary part}}}
    }
}
proc ::GX::StatisticsV1::_foundationRegressionPolicy {quantity profile numerical context} {
    if {$profile ne "foundation_regression"} {return {not_applicable {Quantity requires the registered foundation regression calculation}}}
    if {$quantity eq "foundation_coefficients"&&[_get $context input_kind {}] eq "complex"} {return {not_applicable {Complex coefficient values require the explicit real and imaginary component fields}}}
    if {$quantity in {foundation_huber_constant foundation_last_scale}&&[_get $context method {}] ne "Huber IRLS"} {return {not_applicable {Quantity belongs to the robust IRLS weight update}}}
    if {$quantity eq "foundation_score_norm"&&[_get $context method {}] ne "glm_clipped_irls"} {return {not_applicable {Final score norm is supplied only by the recorded GLM routine}}}
    return {value {}}
}
proc ::GX::StatisticsV1::_foundationRegressionDataFields {result} {
    set n [expr {int([dict get $result quantities n value])}];set context [dict get $result context];set fields {}
    set method [dict get $context method]
    if {$method eq "Huber IRLS"} {
        set unit [_get $context y_unit unspecified];if {$unit eq {}} {set unit unspecified}
        foreach {field label definition} {
            residual_real {Real residual component} {Real part of observed minus fitted response in original observation order}
            residual_imaginary {Imaginary residual component} {Imaginary part of the same observed minus fitted response in original observation order}
        } {dict set fields $field [dict create kind vector value_kind real unit $unit shape [list $n 1] label $label definition $definition]}
        if {[dict get $context input_kind] eq "real"} {dict set fields residual [dict create kind vector value_kind real unit $unit shape [list $n 1] label {Observed minus fitted response} definition {Raw residual at the returned iterate in original observation order; not a standardized residual or uncertainty estimate}]}
    } else {
        set field [expr {$method eq "logistic_newton_weight_floor"?"probability":"fitted_mean"}]
        set binomial [expr {[dict get $context family] eq "binomial"}]
        set label [expr {$binomial?"Fitted response probability":"Fitted count mean"}]
        dict set fields $field [dict create kind vector value_kind real unit 1 shape [list $n 1] minimum 0 label $label definition {Inverse-link response at the returned coefficient iterate in original observation order; no sampling interval or prediction coverage is implied}]
        if {$binomial} {dict set fields $field maximum 1}
    }
    return $fields
}
