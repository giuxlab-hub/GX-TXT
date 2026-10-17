# Shared meaning of captured covariance diagnostics, without recomputing moments.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label kind unit definition} {
        sample_covariance_real {Sample covariance, real component} matrix output_products {Real component of the centered sample covariance with denominator n minus one; complex covariance conjugates the first variable}
        sample_covariance_imaginary {Sample covariance, imaginary component} matrix output_products {Imaginary component of the same Hermitian sample covariance, antisymmetric under exchange of variable identities}
        sample_covariance_eigenvalues_real {Covariance eigenvalues, real component} vector covariance_eigen_unit {Real parts returned by the native eig operation in its returned order; eigenvalues depend on coordinate scaling and are not sampling uncertainties}
        sample_covariance_eigenvalues_imaginary {Covariance eigenvalues, imaginary component} vector covariance_eigen_unit {Actual imaginary parts returned by the native eig operation; a mathematical Hermitian covariance has real eigenvalues, without silently removing numerical components}
        sample_covariance_condition {Covariance condition number} scalar dimensionless {Native two-norm condition estimate of the computed covariance; not a goodness-of-fit statistic or a sampling probability}
        sample_covariance_rank {Numerical covariance rank} scalar count {Native numerical rank using the default singular-value tolerance; not a count of scientifically independent causes}
        sample_covariance_variable_count {Covariance variable count} scalar count {Number of actual covariance columns; a vector input is interpreted as observations of one variable}
    } {dict set quantities $id [dict create label $label kind $kind unit $unit policy covariance_diagnostics definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_covarianceDiagnosticFields {} {
    return {n n variable_count sample_covariance_variable_count covariance_real sample_covariance_real covariance_imaginary sample_covariance_imaginary eigenvalues_real sample_covariance_eigenvalues_real eigenvalues_imaginary sample_covariance_eigenvalues_imaginary condition_number sample_covariance_condition rank sample_covariance_rank}
}
proc ::GX::StatisticsV1::_covarianceDiagnosticAssumptions {} {
    return {{Rows are aligned observations; a vector input denotes one variable, following the recorded Numeric convention} {Sample covariance uses centered products divided by n minus one; a singleton has no defined sample covariance despite the native zero placeholder} {Complex covariance conjugates the first variable and is Hermitian; real and imaginary components preserve the actual numerical output} {Eigenvalues and conditioning depend on coordinate scaling; mixed physical units have no single eigenvalue unit} {Covariance, rank and spectrum are descriptive; independence, population coverage and causal relationships are not established}}
}
proc ::GX::StatisticsV1::_covarianceDiagnosticAdapt {raw context} {
    if {[_get $raw method {}] ne "centered_sample_covariance_n_minus_one"||[_get $raw input_kind {}] ni {real complex}} {_error {Covariance diagnostics require their actual method and input kind}}
    set count [_get $raw variable_count {}]
    if {![_finite $count]||$count!=floor($count)||$count<1||$count>128} {_error {Bounded covariance interpretation requires one to 128 variable identities}}
    set count [expr {int($count)}]
    if {![dict exists $context output_ids]} {set ids {};for {set i 1} {$i<=$count} {incr i} {lappend ids variable_$i};dict set context output_ids $ids}
    if {![dict exists $context output_units]} {dict set context output_units [lrepeat $count [_get $context y_unit unspecified]]}
    set numerical {}
    dict for {field quantity} [_covarianceDiagnosticFields] {
        if {![dict exists $raw $field]} {_error {Covariance diagnostics are missing a captured numerical fact}}
        dict set numerical $quantity [dict get $raw $field]
    }
    dict set context method [dict get $raw method];dict set context input_kind [dict get $raw input_kind]
    dict set context assumptions [_covarianceDiagnosticAssumptions]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_covarianceEigenUnit {context} {
    set units [_get $context output_units {}]
    if {![llength $units]||[llength [lsort -unique $units]]!=1||[lindex $units 0] in {{} unspecified}} {return unspecified}
    return [list power [lindex $units 0] 2]
}
proc ::GX::StatisticsV1::_covarianceEigenIds {context} {
    set ids {};set index 0
    foreach unused [_get $context output_ids {}] {lappend ids eigenvalue_[incr index]}
    return $ids
}
proc ::GX::StatisticsV1::_validateCovarianceDiagnostic {numerical context} {
    if {[_get $context method {}] ne "centered_sample_covariance_n_minus_one"||[_get $context input_kind {}] ni {real complex}||[_get $context assumptions {}] ne [_covarianceDiagnosticAssumptions]} {_error {Covariance diagnostics must retain actual method, input kind and CORE assumptions}}
    foreach key {n sample_covariance_variable_count sample_covariance_rank} {set v [_get $numerical $key {}];if {![_finite $v]||$v<0||$v!=floor($v)} {_error {Covariance dimensions and rank must be nonnegative integers}}}
    set count [dict get $numerical sample_covariance_variable_count];set ids [_get $context output_ids {}];set units [_get $context output_units {}]
    if {$count<1||$count>128||[llength $ids]!=$count||[llength [lsort -unique $ids]]!=$count||[llength $units]!=$count||{} in $ids||[dict get $numerical n]<1||[dict get $numerical sample_covariance_rank]>min($count,[dict get $numerical n]-1)} {_error {Covariance dimensions, variable identities or units are inconsistent}}
    set condition [_get $numerical sample_covariance_condition {}]
    if {[_finite $condition]&&$condition<1} {_error {A finite covariance condition number cannot be below one}}
    foreach key {sample_covariance_real sample_covariance_imaginary} {
        set matrix [_get $numerical $key {}]
        if {[llength $matrix]!=$count} {_error {Covariance rows differ from actual variable identities}}
        foreach row $matrix {if {[llength $row]!=$count} {_error {Covariance columns differ from actual variable identities}};foreach v $row {if {![_finite $v]} {_error {Covariance contains a nonfinite captured entry}}}}
    }
    set real [dict get $numerical sample_covariance_real];set imaginary [dict get $numerical sample_covariance_imaginary]
    for {set i 0} {$i<$count} {incr i} {
        if {[lindex $real $i $i]<0} {_error {Sample covariance cannot have a negative diagonal variance}}
        for {set j 0} {$j<$count} {incr j} {
            set a [lindex $real $i $j];set b [lindex $real $j $i]
            if {abs($a-$b)>1e-12*max(abs($a),abs($b))} {_error {Real covariance is not symmetric}}
            set a [lindex $imaginary $i $j];set b [lindex $imaginary $j $i]
            if {abs($a+$b)>1e-12*max(abs($a),abs($b),abs([lindex $real $i $i]),abs([lindex $real $j $j]))} {_error {Imaginary covariance is not antisymmetric}}
            if {[dict get $context input_kind] eq "real"&&$a!=0} {_error {Real input cannot supply an imaginary covariance}}
        }
    }
    foreach key {sample_covariance_eigenvalues_real sample_covariance_eigenvalues_imaginary} {if {[llength [_get $numerical $key {}]]!=$count} {_error {Covariance eigenvalues differ from their actual variable count}}}
}
proc ::GX::StatisticsV1::_covarianceDiagnosticPolicy {quantity profile numerical context} {
    if {$profile ne "covariance_diagnostics"} {return {not_applicable {Quantity requires registered sample covariance diagnostics}}}
    if {[dict get $numerical n]<2&&$quantity ni {sample_covariance_variable_count sample_covariance_rank}} {return {undefined {At least two observations are required for sample covariance}}}
    if {$quantity eq "sample_covariance_condition"&&![_finite [_get $numerical $quantity {}]]} {return {undefined {The computed covariance has no finite condition number}}}
    return {value {}}
}
