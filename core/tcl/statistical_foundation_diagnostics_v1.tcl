# Shared interpretation of captured Numeric foundation diagnostics.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        precision_correlation {Covariance-pseudoinverse correlation} dimensionless {Negative off-diagonal covariance pseudoinverse entry divided by the geometric mean of its two diagonal entries; ordinary conditional partial correlation requires a nonsingular covariance}
        precision_variable_count {Covariance variables} count {Two measured variables plus the supplied control columns}
        precision_control_count {Control columns} count {Actual supplied control-column count; the count does not establish independent controls}
        precision_rank {Sample covariance rank} count {Octave numerical rank of the same sample covariance passed to the pseudoinverse, using its default singular-value tolerance}
        precision_normalization_valid {Positive finite precision normalization} dimensionless {One when the geometric mean of the two precision diagonal entries is real, finite and positive}
        adjusted_p_value {Multiplicity-adjusted p-value} dimensionless {Adjusted probability for the recorded family and method, retained in original hypothesis order; not a posterior probability of the null hypothesis}
        original_p_value {Original p-value} dimensionless {Supplied unadjusted p-value, whose test assumptions and validity are not established by adjustment}
        multiplicity_family_size {Hypotheses in the supplied family} count {Actual number of supplied p-values; omitted or selectively reported tests are not counted}
        multiplicity_index {Original hypothesis position} count {One-based position in the supplied family, preserved after sorting for adjustment}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy foundation_diagnostics definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_foundationDiagnosticFields {operation} {
    switch -- $operation {
        foundation.statistics.partial_correlation {return {n n correlation precision_correlation variable_count precision_variable_count control_count precision_control_count covariance_rank precision_rank normalization_valid precision_normalization_valid}}
        foundation.statistics.multiple_testing {return {adjusted_p adjusted_p_value original_p original_p_value hypothesis_index multiplicity_index family_size multiplicity_family_size}}
        default {_error {Unknown foundation diagnostic operation}}
    }
}
proc ::GX::StatisticsV1::_foundationDiagnosticAssumptions {method} {
    switch -- $method {
        covariance_pseudoinverse_normalization {return {{Rows are aligned observations and columns are the two measured variables followed by controls} {With nonsingular covariance this is the usual linear partial correlation; singular covariance gives a pseudoinverse-normalized descriptive coefficient that need not equal residual partial correlation} {Control adjustment does not establish causality; no p-value, confidence interval or sampling degrees of freedom is supplied}}}
        bonferroni {return {{Family-wise error control requires valid marginal p-values and a family specified independently of its results} {Bonferroni multiplies each p-value by the supplied family size and caps at one; no independence assumption is required}}}
        holm {return {{Family-wise error control requires valid marginal p-values and a family specified independently of its results} {Holm uses ascending p-values, descending family multipliers and a cumulative maximum, then restores original order; no independence assumption is required}}}
        bh {return {{False-discovery-rate control requires valid p-values and independence or suitable positive dependence among tests} {Benjamini-Hochberg uses ascending p-values and reverse cumulative minima of family-size-scaled p divided by rank, then restores original order} {The adjusted p-value is neither an individual false-discovery probability nor a posterior null probability}}}
        default {_error {Unknown foundation diagnostic method}}
    }
}
proc ::GX::StatisticsV1::_foundationDiagnosticAdapt {operation raw context} {
    set numerical {}
    dict for {field quantity} [_foundationDiagnosticFields $operation] {
        if {![dict exists $raw $field]||[llength [dict get $raw $field]]!=1} {_error {Foundation diagnostic adaptation needs actual scalar facts; use fromNumericColumns for a hypothesis family}}
        dict set numerical $quantity [dict get $raw $field]
    }
    set method [_get $raw method {}]
    if {$operation eq "foundation.statistics.partial_correlation"&&$method ne "covariance_pseudoinverse_normalization"||$operation eq "foundation.statistics.multiple_testing"&&$method ni {bonferroni holm bh}} {_error {Foundation diagnostic operation differs from its actual method}}
    dict set context method $method;dict set context assumptions [_foundationDiagnosticAssumptions $method]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateFoundationDiagnostic {profile numerical context} {
    set method [_get $context method {}]
    if {[_get $context assumptions {}] ne [_foundationDiagnosticAssumptions $method]} {_error {Foundation diagnostics must retain the shared CORE assumptions}}
    if {$profile eq "foundation_correlation"} {
        if {$method ne "covariance_pseudoinverse_normalization"} {_error {Correlation method differs from its registered profile}}
        foreach key {n precision_variable_count precision_control_count precision_rank} {
            set value [_get $numerical $key {}]
            if {![_finite $value]||$value<0||$value!=floor($value)} {_error {Correlation dimensions and rank must be nonnegative integers}}
        }
        if {[dict get $numerical n]<2||[dict get $numerical precision_control_count]<1||[dict get $numerical precision_variable_count]!=[dict get $numerical precision_control_count]+2||[dict get $numerical precision_rank]>min([dict get $numerical n]-1,[dict get $numerical precision_variable_count])} {_error {Correlation dimensions or covariance rank are inconsistent}}
        if {[_get $numerical precision_normalization_valid {}] ni {0 1}} {_error {Correlation needs its actual normalization-valid flag}}
        set v [_get $numerical precision_correlation {}]
        if {[_finite $v]&&abs($v)>1.000000000001} {_error {Numeric returned a correlation outside its normalized range}}
    } elseif {$profile eq "multiplicity"} {
        if {$method ni {bonferroni holm bh}} {_error {Adjustment method differs from its registered profile}}
        foreach key {multiplicity_family_size multiplicity_index} {set v [_get $numerical $key {}];if {![_finite $v]||$v<1||$v!=floor($v)} {_error {Multiplicity requires positive integer family size and original index}}}
        if {[dict get $numerical multiplicity_index]>[dict get $numerical multiplicity_family_size]} {_error {Hypothesis index exceeds the supplied family}}
        foreach key {original_p_value adjusted_p_value} {set v [_get $numerical $key {}];if {![_finite $v]||$v<0||$v>1} {_error {Multiplicity probabilities must lie between zero and one}}}
        if {[dict get $numerical adjusted_p_value]+1e-15<[dict get $numerical original_p_value]} {_error {Adjustment cannot lower the original probability}}
    } else {_error {Unknown foundation diagnostic profile}}
}
proc ::GX::StatisticsV1::_foundationDiagnosticPolicy {quantity profile numerical context} {
    set correlation {precision_correlation precision_variable_count precision_control_count precision_rank precision_normalization_valid}
    if {$profile eq "foundation_correlation"&&$quantity in $correlation} {
        if {$quantity eq "precision_correlation"&&![dict get $numerical precision_normalization_valid]} {return {undefined {The covariance pseudoinverse has no positive finite normalization for the measured pair}}}
        return {value {}}
    }
    if {$profile eq "multiplicity"&&$quantity in {adjusted_p_value original_p_value multiplicity_family_size multiplicity_index}} {return {value {}}}
    return {not_applicable {Quantity requires its registered foundation diagnostic profile}}
}
