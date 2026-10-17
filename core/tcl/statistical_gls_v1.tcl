# Full-covariance regression interpretation. All arithmetic and whitening
# remain at Numeric; only bounded captured summaries cross this authority.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::StatisticsV1::_glsNumber {value {nan 0}} {
    if {$nan&&[string equal -nocase $value NaN]} {return NaN}
    if {![_finite $value]} {_error {GLS requires finite captured numerical facts}}
    return [format %.17g $value]
}
proc ::GX::StatisticsV1::_glsRaw {raw} {
    set fields {schema numeric_api operation coefficients covariance standard_errors whitened_sequence observation_count parameter_count covariance_rank covariance_nullity exact_constraint_rank stochastic_parameter_count dof objective physical_sse physical_rmse covariance_semantics covariance_scale uncertainty_status singular_policy whitening_method minimum_covariance_eigenvalue covariance_eigenvalue_cutoff eigen_relative_tolerance symmetry_relative_tolerance constraint_relative_tolerance covariance_asymmetry exact_constraint_error exact_constraint_limit scaled_design_condition covariance_sha256 effective_covariance_sha256 observation_signature nonfinite_policy row_policy regularization}
    _keys $raw $fields gls_numeric_summary;set result {}
    foreach key $fields {
        if {![dict exists $raw $key]} {_error "GLS summary requires $key"};set value [dict get $raw $key]
        if {$key in {observation_count parameter_count covariance_rank covariance_nullity exact_constraint_rank stochastic_parameter_count dof}} {
            if {![_finite $value]||$value<0||$value>2048||$value!=floor($value)} {_error {Invalid GLS count}}
            set value [expr {int($value)}]
        } elseif {$key in {coefficients standard_errors}} {
            if {[llength $value]<1||[llength $value]>64} {_error {GLS parameter vectors require1..64 values}}
            set values {};foreach item $value {lappend values [_glsNumber $item [expr {$key eq "standard_errors"}]]};set value $values
        } elseif {$key eq "covariance"} {
            if {[llength $value]<1||[llength $value]>64} {_error {GLS covariance requires1..64 rows}}
            set rows {};foreach row $value {if {[llength $row]<1||[llength $row]>64} {_error {GLS covariance requires1..64 columns}};lappend rows [lmap item $row {_glsNumber $item 1}]};set value $rows
        } elseif {$key in {objective physical_sse physical_rmse minimum_covariance_eigenvalue covariance_eigenvalue_cutoff eigen_relative_tolerance symmetry_relative_tolerance constraint_relative_tolerance covariance_asymmetry exact_constraint_error exact_constraint_limit scaled_design_condition}} {
            set value [_glsNumber $value]
        } elseif {$key eq "covariance_scale"} {set value [_glsNumber $value 1]
        } elseif {$key eq "observation_signature"} {set value [_fitObservationSignature $value]
        } elseif {$key eq "whitened_sequence"} {if {$value ne {}} {set value [_sequenceRaw $value]}}
        dict set result $key $value
    }
    return $result
}
proc ::GX::StatisticsV1::_glsContext {context p} {
    _keys $context {response_unit covariance_unit parameter_ids parameter_units noise_model design_label} gls_context
    set result {}
    foreach key {response_unit covariance_unit noise_model} {_physicalText [dict get $context $key] $key 256;dict set result $key [dict get $context $key]}
    if {[dict get $result response_unit] eq {}||[dict get $result covariance_unit] eq {}} {_error {GLS needs explicit response and covariance units, including1 for dimensionless}}
    if {[dict get $result noise_model] ni {second_moments_only gaussian}} {_error {Declare Gaussian inference or second-moment assumptions only}}
    set conversion [::GX::unitRegistryDifferentialRatioPlan [dict get $result covariance_unit] [dict get $result response_unit] [dict get $result response_unit]]
    if {[dict get $conversion status] ne "value"||abs([dict get $conversion scale]-1)>8*2.2204460492503131e-16} {_error {Captured covariance must already be in squared response units; convert values upstream before fitting}}
    set ids {};set units {}
    foreach id [dict get $context parameter_ids] unit [dict get $context parameter_units] {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]{0,127}$} $id]||$id in $ids} {_error {GLS parameter identities must be unique canonical identifiers}}
        _physicalText $unit parameter_unit 256;if {$unit eq {}} {_error {Every GLS parameter needs its declared design-column unit}}
        lappend ids $id;lappend units $unit
    }
    if {[llength $ids]!=$p||[llength [dict get $context parameter_units]]!=$p} {_error {GLS parameter units and IDs must match design columns}}
    dict set result parameter_ids $ids;dict set result parameter_units $units
    set label [_get $context design_label {Explicit linear design}];_physicalText $label design_label 512;dict set result design_label $label
    return $result
}
proc ::GX::StatisticsV1::glsInterpretation {numeric context} {
    set raw [_glsRaw $numeric];set n [dict get $raw observation_count];set p [dict get $raw parameter_count]
    set r [dict get $raw covariance_rank];set q [dict get $raw exact_constraint_rank];set free [dict get $raw stochastic_parameter_count];set dof [dict get $raw dof]
    set context [_glsContext $context $p]
    foreach {key expected} {schema gxtxt.gls_numeric_summary.v1 numeric_api NUMERIC_API_v1 nonfinite_policy error row_policy all_input_rows_in_original_order regularization none} {if {[dict get $raw $key] ne $expected} {_error "Unknown GLS $key"}}
    if {$n<1||$p<1||$p>64||$r>[dict get $raw observation_count]||$r+[dict get $raw covariance_nullity]!=$n||$q>$p||$q>[dict get $raw covariance_nullity]||$free+$q!=$p||$r-$free!=$dof} {_error {GLS stochastic/constraint population is inconsistent}}
    if {[dict get $raw covariance_semantics] ni {absolute relative_scale}||[dict get $raw singular_policy] ni {reject exact_constraints}} {_error {Unknown GLS covariance policy}}
    if {[dict get $raw operation] ni {generalized_least_squares polynomial_gls}} {_error {Unknown GLS operation}}
    set singular [expr {$r<$n}]
    if {$singular&&[dict get $raw singular_policy] ne "exact_constraints"} {_error {Singular GLS covariance lacks explicit exact constraints}}
    set method [expr {$singular?"eigen_positive_modes_with_exact_null_constraints":"lower_cholesky_in_source_order"}]
    if {[dict get $raw whitening_method] ne $method} {_error {GLS whitening method differs from covariance rank}}
    foreach key {objective physical_sse physical_rmse covariance_eigenvalue_cutoff covariance_asymmetry exact_constraint_error exact_constraint_limit} {if {[dict get $raw $key]<0} {_error {Negative GLS magnitude}}}
    foreach key {eigen_relative_tolerance symmetry_relative_tolerance constraint_relative_tolerance} {if {[dict get $raw $key]<0||[dict get $raw $key]>1e-6} {_error {GLS numerical tolerance outside its declared bound}}}
    if {[dict get $raw minimum_covariance_eigenvalue]<-[dict get $raw covariance_eigenvalue_cutoff]||[dict get $raw exact_constraint_error]>[dict get $raw exact_constraint_limit]} {_error {GLS covariance or exact constraints failed validation}}
    foreach key {covariance_sha256 effective_covariance_sha256} {if {![regexp {^[0-9a-f]{64}$} [dict get $raw $key]]} {_error {Invalid GLS covariance fingerprint}}}
    set signature [dict get $raw observation_signature]
    if {[dict get $signature n]!=$n||![dict exists $signature predictor_count]||[dict get $signature predictor_count]!=([dict get $raw operation] eq "polynomial_gls"?1:$p)} {_error {GLS input signature does not match actual design/response population}}
    set uncertainty [expr {$free==0?"deterministic_constraints":([dict get $raw covariance_semantics] eq "absolute"?"known_covariance":($dof>0?"estimated_scale":"unavailable_no_residual_dof"))}]
    if {[dict get $raw uncertainty_status] ne $uncertainty} {_error {GLS uncertainty status contradicts its scale and effective DOF}}
    set available [expr {$uncertainty ne "unavailable_no_residual_dof"}];set scale [dict get $raw covariance_scale]
    if {($available&&(![_finite $scale]||$scale<0))||(!$available&&$scale ne "NaN")||($uncertainty eq "known_covariance"&&$scale!=1)||($uncertainty eq "deterministic_constraints"&&$scale!=0)} {_error {GLS covariance scale is inconsistent}}
    foreach key {coefficients standard_errors covariance} {if {[llength [dict get $raw $key]]!=$p} {_error {GLS parameter dimensions changed}}}
    foreach se [dict get $raw standard_errors] row [dict get $raw covariance] {
        if {[llength $row]!=$p} {_error {GLS parameter covariance is not square}}
        foreach value [concat [list $se] $row] {if {$available&&![_finite $value]||!$available&&$value ne "NaN"} {_error {GLS uncertainty values do not match availability}}}
        if {$available&&$se<0} {_error {Negative parameter standard uncertainty}}
    }
    if {$available} {
        set C [dict get $raw covariance];set se [dict get $raw standard_errors]
        for {set i 0} {$i<$p} {incr i} {
            set variance [lindex $C $i $i];set squared [expr {[lindex $se $i]*[lindex $se $i]}]
            if {$variance<0||![_finite $squared]||abs($variance-$squared)>1e-12*max(abs($variance),abs($squared),1e-300)} {_error {GLS covariance diagonal and standard uncertainties disagree}}
            for {set j 0} {$j<$p} {incr j} {
                set a [lindex $C $i $j];set b [lindex $C $j $i]
                if {abs($a-$b)>1e-12*max(abs($a),abs($b),1e-300)} {_error {GLS coefficient covariance is asymmetric}}
            }
        }
    }
    set ids [dict get $context parameter_ids];set units [dict get $context parameter_units];set parameters {}
    foreach id $ids unit $units value [dict get $raw coefficients] {lappend parameters [dict create id $id unit $unit value $value role fitted_linear_coefficient]}
    set quantities {}
    foreach {key field label unit definition} [list n observation_count {Observation rows} count {Original physical response rows in captured order} effective_n covariance_rank {Stochastic covariance modes} count {Positive covariance modes under the captured tolerance} p parameter_count {Design coefficients} count {Physical coefficient vector length} dof dof {Residual degrees of freedom} count {Stochastic covariance rank minus parameter directions remaining after exact constraints} objective objective {Whitened squared residual norm} 1 {Sum of squared covariance-whitened residuals; relative covariance has an unknown common scale} physical_rmse physical_rmse {Physical response RMSE} [dict get $context response_unit] {Square root of physical response squared error divided by original row count}] {
        dict set quantities $key [dict create status value kind scalar label $label unit $unit definition $definition value [dict get $raw $field] reason {}]
    }
    set status [expr {$available?"value":"unavailable"}];set reason [expr {$available?{}:"Relative covariance scale cannot be estimated without residual degrees of freedom"}]
    foreach {key kind unit} [list covariance matrix [dict create row_units $units column_units $units] standard_errors vector $units] {
        dict set quantities $key [dict create status $status kind $kind label [expr {$key eq "covariance"?"GLS coefficient covariance":"GLS coefficient standard uncertainties"}] unit $unit parameter_ids $ids value [dict get $raw $key] reason $reason definition {Conditional on the supplied linear design, covariance structure and any exact zero-variance observation equations; no additional estimated covariance-shape uncertainty is included}]
    }
    set diagnostics {}
    if {$r>=2} {
        if {[dict get $raw whitened_sequence] eq {}||[dict get $raw whitened_sequence n]!=$r} {_error {GLS whitened residual diagnostics do not match stochastic rank}}
        set order [expr {$singular?"positive covariance eigenmode order; not temporal source order":"lower-Cholesky innovations in captured source-row order"}]
        set diagnostics [residualSequenceInterpretation [dict get $raw whitened_sequence] [dict create residual_unit 1 coordinate_space covariance_whitened population fitted_residuals order_label $order residual_convention {observed minus fitted response, then whitened} source_sha256 [dict get $signature response_sha256]]]
    } elseif {[dict get $raw whitened_sequence] ne {}} {_error {Fewer than two stochastic modes cannot carry sequence diagnostics}}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.gls_interpretation.v1 request [dict create numeric $raw context $context] parameters $parameters quantities $quantities whitened_diagnostics $diagnostics assumptions {{Covariance values must already be in squared response units; relative covariance estimates only one common scale} {Zero-variance covariance modes are exact observation equations; inconsistent equations fail and no diagonal regularization is added} {A supplied covariance structure is conditional input, not automatically validated by the fitted residuals} {Whitened fitted residuals remain affected by parameter estimation; descriptive lag/run diagnostics are not a test proving independence} {Eigenmode diagnostics for singular covariance have no temporal interpretation} {Known second moments support coefficient covariance; Gaussian distribution assumptions are additional and must be explicitly declared} {No likelihood ranking, confidence interval or prediction interval is inferred from this summary alone}}]
}
proc ::GX::StatisticsV1::_glsValidate {result} {
    _keys [dict get $result request] {numeric context} gls_request
    set expected [glsInterpretation [dict get $result request numeric] [dict get $result request context]]
    if {[lsort [dict keys $result]] ne [lsort [dict keys $expected]]} {_error {GLS result fields changed}}
    foreach key {api_id api_version schema assumptions} {if {[dict get $result $key] ne [dict get $expected $key]} {_error "GLS result changed $key"}}
    set actualParameters [dict get $result parameters];if {[llength $actualParameters]!=[llength [dict get $expected parameters]]} {_error {GLS parameter count changed}}
    foreach a $actualParameters b [dict get $expected parameters] {
        if {[lsort [dict keys $a]] ne [lsort [dict keys $b]]} {_error {GLS parameter fields changed}}
        dict for {key wanted} $b {set actual [dict get $a $key];if {$key eq "value"} {set actual [_glsNumber $actual]};if {$actual ne $wanted} {_error {GLS parameter identity/value changed}}}
    }
    if {[lsort [dict keys [dict get $result quantities]]] ne [lsort [dict keys [dict get $expected quantities]]]} {_error {GLS quantity identities changed}}
    dict for {id item} [dict get $expected quantities] {
        set actual [dict get $result quantities $id];if {[lsort [dict keys $actual]] ne [lsort [dict keys $item]]} {_error {GLS quantity fields changed}}
        dict for {key wanted} $item {
            set found [dict get $actual $key]
            if {$key eq "value"} {
                if {$id eq "covariance"} {set found [lmap row $found {lmap value $row {_glsNumber $value 1}}]
                } elseif {$id eq "standard_errors"} {set found [lmap value $found {_glsNumber $value 1}]
                } else {set found [_glsNumber $found];set wanted [_glsNumber $wanted]}
            } elseif {$key eq "unit"&&$id eq "covariance"} {set found [dict create row_units [dict get $found row_units] column_units [dict get $found column_units]]}
            if {$found ne $wanted} {_error "GLS quantity $id changed $key"}
        }
    }
    set a [dict get $result whitened_diagnostics];set b [dict get $expected whitened_diagnostics]
    if {$a ne {}} {
        _sequenceValidate $a
        set a [residualSequenceInterpretation [dict get $a request numeric] [dict get $a request context]]
    }
    if {$a ne $b} {_error {GLS residual diagnostic source changed}}
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::glsReport {result} {
    validate $result;set raw [dict get $result request numeric];set context [dict get $result request context]
    set lines [list "Generalized least squares: [dict get $context design_label]" "Covariance: [dict get $raw covariance_semantics]; unit [dict get $context covariance_unit]; whitening [dict get $raw whitening_method]" "Exact constraints: rank [dict get $raw exact_constraint_rank]; stochastic parameter directions [dict get $raw stochastic_parameter_count]" "Uncertainty: [dict get $raw uncertainty_status]; noise assumption [dict get $context noise_model]"]
    foreach parameter [dict get $result parameters] {lappend lines "[dict get $parameter id] = [dict get $parameter value] [dict get $parameter unit]"}
    dict for {id item} [dict get $result quantities] {lappend lines "[dict get $item label]: [dict get $item value] ([dict get $item status]); [dict get $item definition]"}
    if {[dict get $result whitened_diagnostics] ne {}} {lappend lines [_sequenceReport [dict get $result whitened_diagnostics]]}
    return [join [concat $lines [dict get $result assumptions]] \n]
}

# Adapt an already solved GLS summary into the common retained-fit schema.
# Canonical model/parameter identity construction stays in fromNumeric.
proc ::GX::StatisticsV1::_glsRegressionRaw {raw} {
    set summary [_get $raw gls_summary [_get $raw summary $raw]]
    set summary [_glsRaw $summary]
    set result [dict create gls_summary $summary coefficients [dict get $summary coefficients] \
        n [dict get $summary observation_count] p [dict get $summary parameter_count] \
        rank [dict get $summary parameter_count] free_parameter_count [dict get $summary parameter_count] \
        dof [dict get $summary dof] sse [dict get $summary objective] \
        response_rmse [dict get $summary physical_rmse] covariance [dict get $summary covariance] \
        standard_errors [dict get $summary standard_errors] covariance_scale [dict get $summary covariance_scale] \
        observation_signature [dict get $summary observation_signature] \
        weight_semantics [expr {[dict get $summary covariance_semantics] eq "absolute"?"inverse_variance":"relative"}]]
    if {[dict exists $raw model]} {dict set result model [dict get $raw model]}
    return $result
}
proc ::GX::StatisticsV1::_glsRegressionContext {summary context parameters} {
    set orientation [_get $context orientation y_of_x]
    if {$orientation ni {y_of_x x_of_y}} {_error {Common GLS regression requires one functional response}}
    set response [_get $context [expr {$orientation eq "x_of_y"?"x_unit":"y_unit"}] {}]
    set semantics [dict get $summary covariance_semantics]
    set noise [_get $context noise_model unspecified]
    set expected [expr {$semantics eq "absolute"?"correlated_gaussian_known_covariance":"correlated_gaussian_estimated_scale"}]
    if {$noise ni [list unspecified $expected]} {_error {GLS noise assumption must describe the supplied full covariance and its scale}}
    set ids {};set units {};foreach parameter $parameters {lappend ids [dict get $parameter id];lappend units [dict get $parameter unit]}
    set meaning [glsInterpretation $summary [dict create response_unit $response covariance_unit [dict get $context covariance_unit] \
        parameter_ids $ids parameter_units $units noise_model [expr {$noise eq "unspecified"?"second_moments_only":"gaussian"}]]]
    set context [dict remove $context covariance_unit]
    dict set context gls $meaning
    dict set context constraints [expr {[dict get $summary exact_constraint_rank]>0?"equality":"none"}]
    dict set context covariance_scaling [expr {$semantics eq "absolute"?"absolute_measurement_variance":"estimated_residual_variance"}]
    foreach assumption [dict get $meaning assumptions] {if {$assumption eq {No likelihood ranking, confidence interval or prediction interval is inferred from this summary alone}} continue;dict lappend context assumptions $assumption}
    dict lappend context assumptions {Coefficients determined exactly by covariance-null equations have zero conditional variance; ordinary marginal intervals cover only remaining positive-variance coefficient coordinates}
    return $context
}
proc ::GX::StatisticsV1::_glsRegressionValidate {context numerical parameters provenance profile} {
    set meaning [dict get $context gls];_glsValidate $meaning
    set summary [_glsRaw [dict get $meaning request numeric]]
    if {$profile ne "regression"||[_get $context sample_role training] ne "training"||[dict get $provenance operation] ne [dict get $summary operation]||[dict exists $context response_transform]||[dict exists $context smoothing]||[dict exists $context baseline_correction]} {_error {GLS retained regression requires its actual untransformed linear training result}}
    set noise [dict get $meaning request context noise_model];set absolute [expr {[dict get $summary covariance_semantics] eq "absolute"}]
    set expectedNoise [expr {$noise eq "second_moments_only"?"unspecified":($absolute?"correlated_gaussian_known_covariance":"correlated_gaussian_estimated_scale")}]
    set expectedScaling [expr {$absolute?"absolute_measurement_variance":"estimated_residual_variance"}]
    set expectedWeights [expr {$absolute?"inverse_variance":"relative"}]
    if {[_get $context noise_model unspecified] ne $expectedNoise||[dict get $context covariance_scaling] ne $expectedScaling||[dict get $context weight_semantics] ne $expectedWeights||[dict get $context constraints] ne [expr {[dict get $summary exact_constraint_rank]>0?"equality":"none"}]} {_error {Common GLS policy differs from captured full-covariance meaning}}
    foreach {key source} {n observation_count p parameter_count rank parameter_count free_parameter_count parameter_count dof dof sse objective rmse physical_rmse} {
        if {![_finite [_get $numerical $key {}]]||[dict get $numerical $key]!=[dict get $summary $source]} {_error "Common GLS quantity $key differs from its captured numerical source"}
    }
    foreach key {covariance standard_errors} {
        set expected [dict get $summary $key];set actual [dict get $numerical $key]
        if {$key eq "covariance"} {set actual [lmap row $actual {lmap value $row {_glsNumber $value 1}}]} else {set actual [lmap value $actual {_glsNumber $value 1}]}
        if {$actual ne $expected} {_error {Common GLS covariance/standard uncertainties changed}}
    }
    if {[llength $parameters]!=[llength [dict get $meaning parameters]]} {_error {Common GLS parameter count changed}}
    foreach actual $parameters expected [dict get $meaning parameters] {
        foreach field {id unit} {if {[dict get $actual $field] ne [dict get $expected $field]} {_error {Common GLS parameter identity changed}}}
        if {[dict get $actual role] ne "free"||[_glsNumber [dict get $actual value]] ne [_glsNumber [dict get $expected value]]} {_error {Common GLS coefficient or role changed}}
    }
    set unit [_get $context [expr {[_get $context orientation y_of_x] eq "x_of_y"?"x_unit":"y_unit"}] {}]
    if {$unit ne [dict get $meaning request context response_unit]} {_error {Common GLS response unit changed}}
    foreach assumption [dict get $meaning assumptions] {if {$assumption eq {No likelihood ranking, confidence interval or prediction interval is inferred from this summary alone}} continue;if {$assumption ni [dict get $context assumptions]} {_error {Common GLS assumptions were removed}}}
}
proc ::GX::StatisticsV1::_glsRegressionPolicy {quantity policy context} {
    set meaning [dict get $context gls]
    if {$quantity in {covariance standard_errors}} {set item [dict get $meaning quantities $quantity];return [list [dict get $item status] [dict get $item reason]]}
    if {$policy eq "residual_dof"} {return {value {}}}
    if {$policy in {r_squared adjusted_r_squared}} {return {not_applicable {Full-covariance GLS does not inherit a diagonal-weight centered R squared definition}}}
    if {$policy eq "chi_squared"} {return {unavailable {The full-covariance summary retains the whitened objective and effective DOF without inventing an additional reduced statistic}}}
    return {unavailable {This inference quantity has no declared full-covariance GLS adaptation}}
}
