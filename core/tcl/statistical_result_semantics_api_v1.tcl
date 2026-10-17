# SPDX-License-Identifier: GPL-3.0-or-later
# Scientific meaning only. Numerical estimates remain owned by NUMERIC_API_v1.
namespace eval ::GX::StatisticsV1 {
    variable models {}
    variable catalogSignature {}
    variable quantities [dict create \
        replicate_mean {label {Consensus mean} unit response kind scalar policy replicate_profile definition {Arithmetic mean of aligned contributing curves}} \
        replicate_median {label {Consensus median} unit response kind scalar policy replicate_profile definition {Median of aligned contributing curves}} \
        replicate_dispersion {label {Profile dispersion} unit response kind scalar policy replicate_profile definition {Sample curve spread; cloud mode uses combined local and source-location spread when available}} \
        replicate_sem {label {Conditional consensus SEM} unit response kind scalar policy replicate_profile definition {Sample curve standard deviation divided by square root of curve count under the declared independent-trace model}} \
        replicate_within {label {Within-source dispersion component} unit response kind scalar policy replicate_profile definition {Labelled mode uses pooled within-source moments; cloud mode uses RMS of local residual dispersions}} \
        replicate_between {label {Between-source dispersion component} unit response kind scalar policy replicate_profile definition {Labelled mode uses the truncated random-effects moment; cloud mode uses sample spread of source locations}} \
        replicate_total {label {Combined source dispersion} unit response kind scalar policy replicate_profile definition {Quadrature combination of available within-source and between-source dispersion components}} \
        replicate_trace_count {label {Contributing curves} unit count kind scalar policy replicate_profile definition {Count of aligned input curves; not a verified independent replicate count}} \
        replicate_source_count {label {Distinct sources} unit count kind scalar policy replicate_profile definition {Count of distinct source identities supplied with the curves}} \
        replicate_within_df {label {Within-source residual count} unit count kind scalar policy replicate_profile definition {Labelled curve count minus source count for the pooled within-source moment}} \
        replicate_component_coefficient {label {Unequal-group coefficient} unit dimensionless kind scalar policy replicate_profile definition {Random-effects group-size coefficient from the actual source replicate counts}} \
        replicate_components_available {label {Component inputs available} unit dimensionless kind scalar policy replicate_profile definition {One means numerical component inputs are available; it does not verify physical variance assumptions}} \
        replicate_between_clamped {label {Between-source variance truncated} unit dimensionless kind scalar policy replicate_profile definition {One means a negative random-effects variance estimate was replaced by the nonnegative boundary}} \
        replicate_lower_std {label {Lower dispersion envelope} unit response kind scalar policy replicate_profile definition {Consensus mean minus profile dispersion; no confidence or prediction coverage claim}} \
        replicate_upper_std {label {Upper dispersion envelope} unit response kind scalar policy replicate_profile definition {Consensus mean plus profile dispersion; no confidence or prediction coverage claim}} \
        replicate_lower_sem {label {Lower conditional SEM envelope} unit response kind scalar policy replicate_profile definition {Consensus mean minus conditional SEM; no confidence or prediction coverage claim}} \
        replicate_upper_sem {label {Upper conditional SEM envelope} unit response kind scalar policy replicate_profile definition {Consensus mean plus conditional SEM; no confidence or prediction coverage claim}} \
        replicate_lower_total {label {Lower combined dispersion envelope} unit response kind scalar policy replicate_profile definition {Consensus mean minus combined source dispersion; no confidence or prediction coverage claim}} \
        replicate_upper_total {label {Upper combined dispersion envelope} unit response kind scalar policy replicate_profile definition {Consensus mean plus combined source dispersion; no confidence or prediction coverage claim}} \
        local_cloud_query {label {Local query coordinate} unit predictor kind scalar policy local_cloud definition {Actual source X coordinate at which the local estimator is evaluated}} \
        local_cloud_location {label {Local cloud location} unit response kind scalar policy local_cloud definition {Local quadratic intercept at the query, or weighted constant fallback}} \
        local_cloud_dispersion {label {Local cloud residual dispersion} unit response kind scalar policy local_cloud definition {Weighted residual RMS times square root of Kish effective count divided by its positive correction denominator}} \
        local_cloud_effective_count {label {Local effective weight count} unit count kind scalar policy local_cloud definition {Squared sum of positive tricube weights divided by their squared sum}} \
        local_cloud_variance_denominator {label {Local variance correction denominator} unit count kind scalar policy local_cloud definition {Kish effective weight count minus fitted coefficient count; not sampling degrees of freedom}} \
        local_cloud_count {label {Local neighbourhood points} unit count kind scalar policy local_cloud definition {Deterministic nearest-neighbour count; not independent replicate count}} \
        local_cloud_degree {label {Local polynomial degree} unit count kind scalar policy local_cloud definition {Two for accepted local quadratic; zero for weighted constant fallback}} \
        local_cloud_quadratic_condition {label {Candidate quadratic design condition} unit dimensionless kind scalar policy local_cloud definition {Condition reported by the weighted quadratic least-squares solve before fallback selection}} \
        welch_window_count {label {Averaged windows} unit count kind scalar policy welch definition {Number of normalized periodograms in the arithmetic mean}} \
        welch_mean_enbw {label {Mean equivalent noise bandwidth} unit frequency kind scalar policy welch definition {Arithmetic mean of the segment window equivalent noise bandwidths}} \
        welch_integrated_power {label {Integrated one-sided PSD} unit band_power kind scalar policy welch definition {Frequency-bin width times the sum of all one-sided PSD bins including DC and Nyquist when present}} \
        welch_peak_frequency {label {Peak frequency excluding DC} unit frequency kind scalar policy welch definition {First positive maximum outside DC; undefined when all non-DC bins have zero PSD}} \
        welch_peak_psd {label {Peak PSD excluding DC} unit psd kind scalar policy welch definition {Maximum one-sided PSD outside DC}} \
        welch_zero_level_bins {label {Bins without a finite dB level} unit count kind scalar policy welch definition {Number of zero-PSD bins; numerical NaN marks undefined finite logarithmic levels}} \
        integrated_power {label {Integrated band power} unit band_power kind scalar policy power_level definition {Integral of the linear PSD over the recorded frequency band}} \
        band_rms {label {Band RMS} unit response kind scalar policy power_level definition {Square root of integrated band power}} \
        band_level_db {label {Band level relative to RMS reference} unit dB kind scalar policy power_level definition {10 log10(power) minus 20 log10(reference RMS); zero power has no finite level}} \
        spectral_bin_count {label {Analysed spectral bins} unit count kind scalar policy spectral definition {Number of bins retained after DC handling}} \
        spectral_bin_spacing {label {Frequency bin spacing} unit frequency kind scalar policy spectral definition {Uniform source frequency spacing}} \
        dominant_frequency {label {Dominant frequency} unit frequency kind scalar policy spectral definition {First frequency bin attaining the maximum spectral weight}} \
        spectral_centroid {label {Spectral centroid} unit frequency kind scalar policy spectral definition {Frequency mean weighted by the spectral bin weights}} \
        rms_frequency {label {RMS frequency} unit frequency kind scalar policy spectral definition {Square root of the weighted second frequency moment}} \
        spectral_bandwidth {label {Spectral bandwidth} unit frequency kind scalar policy spectral definition {Population standard deviation of the weighted frequency distribution}} \
        frequency_05 {label {5% cumulative-weight frequency} unit frequency kind scalar policy spectral definition {Weighted empirical CDF inverse at probability 0.05}} \
        frequency_50 {label {50% cumulative-weight frequency} unit frequency kind scalar policy spectral definition {Weighted empirical CDF inverse at probability 0.50}} \
        frequency_85 {label {85% cumulative-weight frequency} unit frequency kind scalar policy spectral definition {Weighted empirical CDF inverse at probability 0.85}} \
        frequency_95 {label {95% cumulative-weight frequency} unit frequency kind scalar policy spectral definition {Weighted empirical CDF inverse at probability 0.95}} \
        occupied_bandwidth_90 {label {90% occupied bandwidth} unit frequency kind scalar policy spectral definition {Difference between the 95% and 5% cumulative-weight frequencies}} \
        spectral_flatness {label {Spectral flatness} unit dimensionless kind scalar policy spectral definition {Geometric divided by arithmetic mean of the bin weights; zero when any weight is zero}} \
        spectral_crest_factor {label {Spectral crest factor} unit dimensionless kind scalar policy spectral definition {Maximum divided by arithmetic mean of the bin weights}} \
        spectral_entropy {label {Normalized spectral entropy} unit dimensionless kind scalar policy spectral definition {Shannon entropy of normalized bin weights divided by logarithm of the retained bin count}} \
        spectral_weight_sum {label {Sum of spectral bin weights} unit spectral_weight kind scalar policy spectral definition {Sum of squared amplitudes or supplied power/PSD bins; PSD is not integrated over frequency}} \
        n {label {Observations} unit count kind scalar policy descriptive} \
        rank {label {Numerical rank} unit count kind scalar policy descriptive} \
        edf {label {Effective model degrees of freedom} unit count kind scalar policy smoother} \
        dof {label {Residual degrees of freedom} unit count kind scalar policy residual_dof} \
        rmse {label {Root mean squared residual} unit response kind scalar policy residual} \
        mae {label {Mean absolute residual} unit response kind scalar policy residual} \
        max_abs_error {label {Maximum absolute residual} unit response kind scalar policy residual} \
        sampled_hausdorff_distance {label {Sampled Hausdorff distance} unit response kind scalar policy geometric_distance} \
        centered_comparison_score {label {Centered prediction score (1 - SSE/SST)} unit dimensionless kind scalar policy comparison_score} \
        relative_n {label {Eligible relative-error observations} unit count kind scalar policy relative_count} \
        max_relative_error {label {Maximum absolute relative error} unit dimensionless kind scalar policy relative_error} \
        rms_relative_error {label {Root mean squared relative error} unit dimensionless kind scalar policy relative_error} \
        residual_standard_deviation {label {Residual standard deviation} unit response kind scalar policy inference} \
        weighted_residual_standard_deviation {label {Weighted residual standard deviation} unit weighted_response kind scalar policy inference} \
        sse {label {Sum of squared residuals} unit squared_response kind scalar policy residual} \
        r_squared {label {R squared} unit dimensionless kind scalar policy r_squared} \
        adjusted_r_squared {label {Adjusted R squared} unit dimensionless kind scalar policy adjusted_r_squared} \
        geometric_dispersion_score {label {XY dispersion score} unit dimensionless kind scalar policy geometric_score} \
        reduced_chi_squared {label {Reduced chi squared} unit dimensionless kind scalar policy chi_squared} \
        covariance {label {Parameter covariance} unit parameter_products kind matrix policy inference} \
        standard_errors {label {Parameter standard errors} unit parameter_units kind vector policy inference} \
        condition_number {label {Condition number} unit dimensionless kind scalar policy descriptive} \
        mean {label {Mean} unit response kind scalar policy summary} \
        minimum {label {Minimum} unit response kind scalar policy summary} \
        absolute_maximum {label {Maximum absolute value} unit response kind scalar policy summary definition {Largest absolute value among the valid observed values}} \
        maximum {label {Maximum} unit response kind scalar policy summary} \
        range {label {Range} unit response kind scalar policy summary} \
        sum {label {Sum} unit response kind scalar policy summary} \
        median {label {Median} unit response kind scalar policy summary} \
        raw_median_absolute_deviation {label {Raw median absolute deviation} unit response kind scalar policy summary} \
        median_absolute_deviation {label {Scaled median absolute deviation} unit response kind scalar policy summary} \
        quartile_1 {label {First quartile} unit response kind scalar policy summary} \
        quartile_3 {label {Third quartile} unit response kind scalar policy summary} \
        interquartile_range {label {Interquartile range} unit response kind scalar policy summary} \
        root_mean_square {label {Root mean square} unit response kind scalar policy summary} \
        variance_population {label {Population variance} unit squared_response kind scalar policy summary} \
        standard_deviation_population {label {Population standard deviation} unit response kind scalar policy summary} \
        standard_error_mean {label {Sampling standard error of mean} unit response kind scalar policy sampling_mean} \
        measurement_standard_error_mean {label {Known measurement uncertainty of weighted mean} unit response kind scalar policy measurement_mean} \
        effective_n {label {Kish effective sample size} unit count kind scalar policy weighted_summary} \
        sum_weights {label {Sum of weights} unit weight kind scalar policy weighted_summary} \
        weighted_sum {label {Weighted sum} unit weighted_sum kind scalar policy weighted_summary} \
        singular_value {label {Singular value} unit response kind scalar policy pca} \
        component_variance {label {Component sample variance} unit squared_response kind scalar policy pca} \
        explained_ratio {label {Explained variance ratio} unit dimensionless kind scalar policy pca} \
        cumulative_ratio {label {Cumulative explained variance ratio} unit dimensionless kind scalar policy pca} \
        component_index {label {Component index} unit count kind scalar policy pca} \
        output_covariance {label {Propagated output covariance} unit output_products kind matrix policy propagation} \
        output_standard_uncertainties {label {Propagated output standard uncertainties} unit output_units kind vector policy propagation} \
        standard_uncertainty {label {Selected output standard uncertainty} unit selected_output kind scalar policy propagation} \
        quantiles {label {Quantiles} unit response kind vector policy quantiles} \
        standard_deviation {label {Sample standard deviation} unit response kind scalar policy summary_sample} \
        variance {label {Sample variance} unit squared_response kind scalar policy summary_sample} \
        covariance_sample {label {Sample covariance} unit pair_product kind scalar policy summary_sample} \
        covariance_population {label {Population covariance} unit pair_product kind scalar policy summary} \
        correlation {label {Correlation coefficient} unit dimensionless kind scalar policy summary_sample} \
        test_statistic {label {Test statistic} unit dimensionless kind scalar policy hypothesis} \
        test_degrees_of_freedom {label {Test degrees of freedom} unit count kind scalar policy hypothesis} \
        n_first {label {First sample observations} unit count kind scalar policy hypothesis_fact} \
        n_second {label {Second sample observations} unit count kind scalar policy hypothesis_fact} \
        p_value {label {p-value} unit dimensionless kind scalar policy hypothesis} \
        test_estimate {label {Test estimate} unit test_estimate kind scalar policy hypothesis_fact} \
        null_value {label {Null value} unit test_estimate kind scalar policy hypothesis_fact} \
        test_standard_error {label {Standard error of tested estimate} unit response kind scalar policy hypothesis} \
        test_standard_deviation {label {Standard deviation underlying test} unit response kind scalar policy hypothesis} \
        interval_margin {label {Confidence interval margin} unit response kind scalar policy hypothesis} \
        ci_lower {label {Confidence interval lower bound} unit test_estimate kind scalar policy hypothesis} \
        ci_upper {label {Confidence interval upper bound} unit test_estimate kind scalar policy hypothesis} \
        effect_size {label {Effect size} unit dimensionless kind scalar policy hypothesis} \
        group_count {label {Groups} unit count kind scalar policy anova_fact} \
        grand_mean {label {Overall mean} unit response kind scalar policy anova_fact} \
        ss_between {label {Between-group sum of squares} unit squared_response kind scalar policy anova_fact} \
        ss_within {label {Within-group sum of squares} unit squared_response kind scalar policy anova_fact} \
        ss_total {label {Total sum of squares} unit squared_response kind scalar policy anova_fact} \
        df_between {label {Between-group degrees of freedom} unit count kind scalar policy anova_fact} \
        df_within {label {Within-group degrees of freedom} unit count kind scalar policy anova_fact} \
        ms_between {label {Between-group mean square} unit squared_response kind scalar policy anova_fact} \
        ms_within {label {Within-group mean square} unit squared_response kind scalar policy anova_fact} \
        f_statistic {label {ANOVA F statistic} unit dimensionless kind scalar policy anova} \
        f_numerator_df {label {F numerator degrees of freedom} unit count kind scalar policy anova} \
        f_denominator_df {label {F denominator degrees of freedom} unit count kind scalar policy anova} \
        eta_squared {label {Eta squared} unit dimensionless kind scalar policy anova_effect} \
        omega_squared {label {Omega squared} unit dimensionless kind scalar policy anova_effect} \
        replicates {label {Resampling replicates} unit count kind scalar policy resampling} \
        extreme_count {label {Extreme permutation replicates} unit count kind scalar policy resampling} \
        bootstrap_standard_error {label {Bootstrap standard error} unit response kind scalar policy resampling}]
}
proc ::GX::StatisticsV1::_error {message} {return -code error -errorcode {GXTXT STATISTICS CONTRACT} $message}
proc ::GX::StatisticsV1::_get {record key default} {if {[dict exists $record $key]} {return [dict get $record $key]};return $default}
proc ::GX::StatisticsV1::_finite {value} {expr {[string is double -strict $value]&&![catch {expr {abs(double($value))<Inf}} finite]&&$finite}}
proc ::GX::StatisticsV1::_infinite {value sign} {expr {[string is double -strict $value]&&![catch {expr {double($value)==$sign*Inf}} equal]&&$equal}}
proc ::GX::StatisticsV1::_keys {record allowed label} {
    if {[catch {dict keys $record} keys]} {_error "$label must be a dictionary"}
    foreach key $keys {if {$key ni $allowed} {_error "Unknown $label field '$key'"}}
}
proc ::GX::StatisticsV1::apiInfo {} {
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 \
        provider_kind core provider_id statistical_result_semantics \
        tcl_provider_adapter fromProviderColumns \
        operations {profile_eligibility profile_settings profile_plan profile_interpretation profile_report digitization_interpretation digitization_fit_plan digitization_report gls_interpretation gls_report fit_suggestions fit_suggestions_report physical_plausibility physical_plausibility_report derived_properties_plan derived_properties_interpretation derived_properties_report residual_sequence_interpretation nested_f_plan nested_f_interpretation bootstrap_settings bootstrap_plan bootstrap_interpretation influence_plan influence_interpretation log_response_plan log_response_interpretation model_selection_plan model_comparison prediction_interpretation prediction_inference_plan numeric_data_fields resource_field_elements store_columns bind_resource_columns resource_binding_table table_csv_rows bind_columns binding_table api_info models model quantities numeric_field_map numeric_fields numeric_model numeric_field_elements from_numeric from_native_comparison from_numeric_table from_numeric_columns interpret interpret_table table_select table_values table_report table_rows validate validated_result report solver_report ini_report scalar_rows parameter_report parameter_ini_report parameter_rows parameter_correlation_report feature parameter_inference_plan with_parameter_uncertainty publication_metadata} \
        statuses {value not_applicable unavailable undefined error} \
        conditional_parameter_units_schema gxtxt.conditional_parameter_units.v1 residual_sequence_schema gxtxt.residual_sequence_interpretation.v1 numerical_authority NUMERIC_API_v1 schema gxtxt.statistical_result.v1 table_schema gxtxt.statistical_result.table.v1 column_binding_schema gxtxt.statistical_result.column_binding.v1 resource_binding_schema gxtxt.statistical_result.resource_binding.v1]
}
proc ::GX::StatisticsV1::registerModel {owner id descriptor} {
    variable models
    if {[::GX::moduleField $owner descriptor {}] eq {}} {_error "Unknown model provider '$owner'"}
    if {![string match "$owner.*" $id]||![regexp {^[A-Za-z0-9_.-]+$} $id]} {_error "Descriptor ID must be qualified by its provider"}
    _keys $descriptor {label profile parameter_ids parameter_convention description} descriptor
    foreach key {label profile parameter_convention} {if {[_get $descriptor $key {}] eq {}} {_error "Descriptor requires $key"}}
    if {[dict get $descriptor profile] ni {prediction_uncertainty foundation_regression clustering covariance_diagnostics survival foundation_correlation multiplicity location_estimate regression nonlinear_regression interpolation smoother projection parametric_regression geometric_comparison summary solver hypothesis anova resampling comparison propagation pca spectral_distribution power_level welch_spectrum local_cloud replicate_profile signal_summary signal_snr signal_spectrum_quality fft_spectrum_quality harmonic_peak_quality harmonic_components event_timing signal_correlation window_metrics signal_spectral}} {_error "Unknown statistical profile"}
    if {[dict get $descriptor parameter_convention] ni {named descending_power basis_controls model_state none}} {_error "Unknown parameter convention"}
    set ids [_get $descriptor parameter_ids {}]
    if {[llength $ids]!=[llength [lsort -unique $ids]]} {_error "Duplicate descriptor parameter identities"}
    set descriptor [dict merge $descriptor [dict create id $id owner $owner parameter_ids $ids]]
    if {[dict exists $models $id]&&[dict get $models $id] ne $descriptor} {_error "Cannot replace an existing statistical descriptor '$id'"}
    dict set models $id $descriptor
    return $descriptor
}
proc ::GX::StatisticsV1::_catalog {} {
    variable catalogSignature
    variable models
    # Standalone canonical publication/metadata workers start with defaults only.
    # Discover through the public catalog before validating their first record.
    if {![info exists ::GX::moduleOrder]||![llength $::GX::moduleOrder]} {::GX::loadModuleCatalog}
    set signature {}
    foreach owner $::GX::moduleOrder {lappend signature $owner [::GX::moduleField $owner dict {}]}
    if {$signature eq $catalogSignature} return
    # Build transactionally; a malformed/new shadow registration cannot partially
    # replace a catalog already used by open scientific consumers.
    set before $models
    try {
        foreach owner $::GX::moduleOrder {
            set manifest [::GX::moduleField $owner dict {}]
            foreach local [::GX::splitList [::GX::descriptorValue $manifest statistical_models ids {}]] {
                set section statistical_model.$local
                set descriptor {}
                foreach key {label profile parameter_convention description} {dict set descriptor $key [::GX::descriptorValue $manifest $section $key {}]}
                dict set descriptor parameter_ids [::GX::splitList [::GX::descriptorValue $manifest $section parameter_ids {}]]
                registerModel $owner $owner.$local $descriptor
            }
        }
    } on error {message options} {set models $before;return -options $options $message}
    set catalogSignature $signature
}
proc ::GX::StatisticsV1::models {} {
    _catalog;variable models;set out {}
    dict for {id descriptor} $models {if {[::GX::moduleIsEnabled [dict get $descriptor owner]]} {lappend out $id}}
    return [lsort $out]
}
proc ::GX::StatisticsV1::model {id} {
    _catalog;variable models
    if {![dict exists $models $id]} {_error "Unregistered statistical model '$id'"}
    set result [dict get $models $id]
    if {![::GX::moduleIsEnabled [dict get $result owner]]} {_error "Statistical model provider is disabled"}
    return $result
}
proc ::GX::StatisticsV1::quantities {} {variable quantities;return $quantities}
proc ::GX::StatisticsV1::numericModel {operation {facts {}}} {
    # Provider-owned associations are separate from persisted model descriptors.
    # Adding an operation binding must not invalidate existing captured results.
    _catalog
    set manifest [::GX::moduleField math.numeric dict {}];set matches {}
    foreach local [::GX::splitList [::GX::descriptorValue $manifest statistical_models ids {}]] {
        set operations [::GX::splitList [::GX::descriptorValue $manifest statistical_model.$local numeric_operations {}]]
        if {$operation in $operations} {lappend matches math.numeric.$local}
    }
    if {[llength $matches]!=1} {return -code error -errorcode {GXTXT STATISTICS NUMERIC_MODEL_REQUIRED} "Numeric operation '$operation' requires an explicit registered model; found [llength $matches] default associations"}
    numericFieldMap $operation
    _keys $facts {has_intercept} {Numeric model selector}
    set id [lindex $matches 0]
    if {[dict exists $facts has_intercept]} {
        if {$operation ne "linear_regression"||![string is boolean -strict [dict get $facts has_intercept]]} {_error {Intercept selector requires a Boolean linear-regression fact}}
        if {![dict get $facts has_intercept]} {
            set section statistical_model.[string range $id 13 end]
            set selected [::GX::descriptorValue $manifest $section numeric_no_intercept_model {}]
            if {$selected eq {}} {_error {Numeric provider has no registered model for regression through the origin}}
            set id $selected
        }
    }
    return [model $id]
}
proc ::GX::StatisticsV1::numericFieldMap {operation} {
    set operation [_numericOperationBase $operation]
    # Public source-field identities, shared by interpretation and consumers.
    # A mapping is not evidence that a value is defined: use numericFields on
    # the captured validated result to obtain status, reason and physical unit.
    switch -- $operation {
        foundation.statistics.robust_regression - foundation.statistics.logistic_regression - foundation.statistics.glm {return [_foundationRegressionFields $operation]}
        prediction_uncertainty {return [_predictionFields]}
        foundation.statistics.kmeans {return [_clusteringFields]}
        foundation.statistics.covariance_diagnostics {return [_covarianceDiagnosticFields]}
        foundation.statistics.survival_kaplan_meier {return [_survivalFieldMap]}
        foundation.statistics.partial_correlation - foundation.statistics.multiple_testing {return [_foundationDiagnosticFields $operation]}
        foundation.statistics.confidence_interval - foundation.statistics.robust_location {return [_locationFieldMap $operation]}
        foundation.statistics.bootstrap_ci {return {n_x n_first n_y n_second estimate test_estimate replicates replicates lower ci_lower upper ci_upper bootstrap_standard_error bootstrap_standard_error}}
        foundation.statistics.permutation_test {return {n_x n_first n_y n_second difference test_estimate replicates replicates extreme_count extreme_count p_value p_value}}
        fft_spectrum_quality {return {N n df amplitude_bin_spacing coherent_gain fft_window_coherent_gain fund_amp spectrum_reference_amplitude f0 spectrum_reference_frequency thd_ratio amplitude_thd_ratio thd_pct amplitude_thd_percent thd_db amplitude_thd_level sfdr_db amplitude_sfdr_level worst_dbc amplitude_spur_relative_level worst_amp amplitude_spur worst_freq amplitude_spur_frequency sinad_db amplitude_sinad_level enob amplitude_nominal_bits noise_floor amplitude_noise_median noise_floor_dbc amplitude_noise_median_level}}
        harmonic_peak_quality {return {bin_count n df amplitude_bin_spacing resolved_harmonics harmonic_count fund_amp spectrum_reference_amplitude f0 spectrum_reference_frequency thd_ratio amplitude_thd_ratio thd_pct amplitude_thd_percent thd_db amplitude_thd_level}}
        harmonic_components {return {component_order harmonic_order component_expected_frequency harmonic_expected_frequency component_frequency harmonic_frequency component_frequency_error harmonic_frequency_error component_amplitude harmonic_amplitude component_level_db harmonic_level_db component_percent harmonic_amplitude_percent fundamental_amplitude spectrum_reference_amplitude}}
        signal_snr {return {n n snr_db signal_snr_db signal_energy signal_energy_sum noise_energy supplied_noise_energy_sum}}
        signal_spectrum_quality {return {n n fundamental_power signal_fundamental_bin_power dc_power signal_dc_bin_power harmonic_powers signal_harmonic_bin_powers noise_power signal_noise_bin_power noise_floor_power_per_bin signal_noise_floor_bin_power noise_floor_db_relative signal_noise_floor_db_relative distortion_power signal_distortion_bin_power thd signal_thd thd_db signal_thd_db thd_plus_n signal_thd_plus_noise snr_db signal_snr_db sinad_db signal_sinad_db sfdr_db signal_sfdr_db enob_bits signal_enob_bits}}
        signal_summary {return {n n rms signal_rms peak signal_peak_magnitude peak_to_peak signal_real_peak_to_peak crest_factor signal_crest_factor dc_real signal_dc_real dc_imaginary signal_dc_imaginary}}
        signal_periodogram - signal_welch - signal_asd - signal_cross_psd - signal_coherence - signal_frf_h1 - signal_frf_h2 {return [_signalSpectralFieldMap $operation]}
        window_metrics {return {n n sample_rate window_sample_rate coherent_gain window_coherent_gain power_gain window_power_gain equivalent_noise_bandwidth_hz window_equivalent_noise_bandwidth}}
        signal_correlation {return {n n n_x sequence_first_count n_y sequence_second_count lag_count sequence_lag_count peak_magnitude sequence_peak_magnitude peak_value_real sequence_peak_real peak_value_imaginary sequence_peak_imaginary delay_samples sequence_delay_samples delay_seconds sequence_delay_seconds}}
        event_period {return {n n crossing_count event_crossing_count period_count event_period_count period event_mean_period frequency_hz event_frequency}}
        pulse_timing {return {n n crossing_count event_crossing_count period_count event_period_count width_count pulse_width_count period_seconds event_mean_period frequency_hz event_frequency pulse_width_seconds pulse_mean_width duty_cycle pulse_duty_ratio jitter_std_seconds period_jitter_std}}
        replicate_summary {return {y_mean replicate_mean y_median replicate_median y_std replicate_dispersion y_sem replicate_sem sigma_within replicate_within sigma_between replicate_between sigma_total replicate_total n replicate_trace_count n_sources replicate_source_count within_df replicate_within_df component_coefficient replicate_component_coefficient components_identifiable replicate_components_available between_clamped replicate_between_clamped lower_std replicate_lower_std upper_std replicate_upper_std lower_sem replicate_lower_sem upper_sem replicate_upper_sem lower_total replicate_lower_total upper_total replicate_upper_total}}
        local_cloud_fit {return {query local_cloud_query local_mean local_cloud_location local_sigma local_cloud_dispersion local_effective_n local_cloud_effective_count local_dof local_cloud_variance_denominator local_count local_cloud_count local_degree local_cloud_degree quadratic_condition local_cloud_quadratic_condition}}
        welch_aggregate {return {window_count welch_window_count bin_count spectral_bin_count df spectral_bin_spacing mean_enbw_hz welch_mean_enbw integrated_power welch_integrated_power peak_frequency welch_peak_frequency peak_psd welch_peak_psd zero_level_bins welch_zero_level_bins}}
        power_level {return {power integrated_power root_power band_rms level_db band_level_db}}
        spectral_features {return {bin_count spectral_bin_count df spectral_bin_spacing dominant_frequency dominant_frequency spectral_centroid spectral_centroid rms_frequency rms_frequency spectral_bandwidth spectral_bandwidth frequency_05 frequency_05 frequency_50 frequency_50 frequency_85 frequency_85 frequency_95 frequency_95 occupied_bandwidth_90 occupied_bandwidth_90 spectral_flatness spectral_flatness spectral_crest_factor spectral_crest_factor spectral_entropy spectral_entropy total_power_equivalent spectral_weight_sum}}
        matrix_statistics {return {n n mean mean median median min minimum max maximum variance_population variance_population std_population standard_deviation_population variance_sample variance std_sample standard_deviation}}
        reduce_summary - reduce_accumulate {return {count n sum sum mean mean min minimum max maximum}}
        statistics {return {n n mean mean min minimum max maximum max_absolute absolute_maximum range range sum sum median median q25 quartile_1 q75 quartile_3 iqr interquartile_range rms root_mean_square variance_population variance_population std_population standard_deviation_population variance_sample variance std_sample standard_deviation standard_error_mean standard_error_mean}}
        weighted_statistics {return {n_positive_weight n mean mean min minimum max maximum range range median median q25 quartile_1 q75 quartile_3 iqr interquartile_range rms root_mean_square variance_population variance_population std_population standard_deviation_population variance_unbiased variance std_unbiased standard_deviation sampling_standard_error_mean standard_error_mean measurement_standard_error_mean measurement_standard_error_mean effective_n effective_n sum_weights sum_weights weighted_sum weighted_sum}}
        mad {return {n_valid n median median raw_mad raw_median_absolute_deviation mad median_absolute_deviation}}
        covariance - correlation {return {n_valid n covariance_sample covariance_sample covariance_population covariance_population correlation correlation}}
        quantiles {return {n n quantiles quantiles}}
        weighted_quantiles {return {n_positive_weight n quantiles quantiles}}
        generalized_least_squares - polynomial_gls {return {observation_count n covariance_rank effective_n dof dof objective sse physical_rmse rmse covariance covariance standard_errors standard_errors}}
        least_squares - linear_regression - polynomial_fit - nonlinear_fit - implicit_fit - complex_fit - surface_fit - rational_fit {return {n n rank rank dof dof sse sse r_squared r_squared adjusted_r_squared adjusted_r_squared reduced_chi_squared reduced_chi_squared covariance covariance standard_errors standard_errors condition_number condition_number rmse weighted_residual_standard_deviation residual_rmse residual_standard_deviation response_rmse rmse}}
        curve_model_fit {return [concat {n n rank rank dof dof sse sse r_squared r_squared adjusted_r_squared adjusted_r_squared reduced_chi_squared reduced_chi_squared covariance covariance standard_errors standard_errors condition_number condition_number} [_smoothingFields]]}
        rational_residuals - surface_residuals {return {n n sse sse rmse rmse mae mae max_abs_error max_abs_error r2 r_squared}}
        complex_residuals {return {n n sse sse rmse rmse mae mae max_abs_error max_abs_error}}
        residual_metrics {return {n n rmse rmse mae mae max_abs_error max_abs_error sse sse r2 r_squared relative_n relative_n max_relative_error max_relative_error rms_relative_error rms_relative_error}}
        residual_summary {return {count n rmse rmse mean_absolute mae max_absolute max_abs_error hausdorff_sampled sampled_hausdorff_distance}}
        matrix_svd {return {rows n rank rank condition_number condition_number}}
        pca_summary {return {n n singular_value singular_value component_variance component_variance explained_ratio explained_ratio cumulative_ratio cumulative_ratio component_index component_index}}
        propagate_uncertainty {return {covariance output_covariance standard_uncertainty output_standard_uncertainties}}
        hypothesis_test {return {statistic test_statistic degrees_of_freedom test_degrees_of_freedom n_x n_first n_y n_second p_value p_value estimate test_estimate null_value null_value standard_error test_standard_error test_standard_deviation test_standard_deviation interval_margin interval_margin ci_lower ci_lower ci_upper ci_upper effect_size effect_size}}
        one_way_anova {return {n_valid n overall_mean grand_mean group_count group_count ss_between ss_between ss_within ss_within ss_total ss_total df_between df_between df_within df_within ms_between ms_between ms_within ms_within f_statistic f_statistic f_numerator_df f_numerator_df f_denominator_df f_denominator_df p_value p_value eta_squared eta_squared omega_squared omega_squared}}
        resampling_summary {return {n_x n_first n_y n_second estimate test_estimate replicates replicates extreme_count extreme_count ci_lower ci_lower ci_upper ci_upper p_value p_value bootstrap_standard_error bootstrap_standard_error}}
        default {
            if {[string match array_reduce.* $operation]} {
                set action [string range $operation 13 end]
                set meanings {sum sum mean mean median median minimum minimum maximum maximum variance_population variance_population variance_sample variance std_population standard_deviation_population std_sample standard_deviation rms root_mean_square quantile quantiles}
                if {[dict exists $meanings $action]} {return [dict create values [dict get $meanings $action] n_valid n]}
            }
            return -code error -errorcode {GXTXT STATISTICS UNKNOWN_NUMERIC_OPERATION} "Numeric operation '$operation' has no registered field interpretation"
        }
    }
}
proc ::GX::StatisticsV1::_numericOperationBase {operation} {
    switch -- $operation {
        statistics_dataset - dataset_statistics {return statistics}
        dataset_weighted_statistics {return weighted_statistics}
        dataset_polynomial_fit {return polynomial_fit}
        dataset_nonlinear_fit {return nonlinear_fit}
        default {return $operation}
    }
}
proc ::GX::StatisticsV1::numericFields {result} {
    validate $result
    if {[dict get $result schema] ne "gxtxt.statistical_result.v1"} {_error {Numeric field interpretation requires one captured result; select table rows explicitly}}
    if {![dict exists $result provenance operation]||![dict exists $result provenance numeric_api]||[dict get $result provenance numeric_api] ne "NUMERIC_API_v1"} {_error {Numeric field interpretation requires a public Numeric adaptation receipt}}
    set operation [dict get $result provenance operation]
    if {$operation eq "one_way_anova"&&[dict get $result model profile] ne "anova"} {_error {Indexed ANOVA group results require their explicit group summary fields}}
    set mapping [numericFieldMap $operation];set out {}
    foreach {field quantity} $mapping {
        if {$quantity eq "r_squared"} {
            set profile [dict get $result model profile]
            if {$profile in {projection parametric_regression}} {set quantity geometric_dispersion_score}
            if {$profile eq "comparison"} {set quantity centered_comparison_score}
        }
        set item [dict get $result quantities $quantity]
        set unit [dict get $item unit];set display $unit
        if {$unit in {count dimensionless}} {set display 1} elseif {[llength $unit]==3&&[lindex $unit 0] eq "power"} {set display "[lindex $unit 1]^[lindex $unit 2]"}
        # Vectors and matrices retain their kind and structured unit identities.
        # Non-value states have no fabricated numeric substitute here.
        dict set out $field [dict merge $item [dict create id $field quantity $quantity unit_text $display]]
    }
    return $out
}
proc ::GX::StatisticsV1::numericFieldElements {result field} {
    if {[_get $result schema {}] eq "gxtxt.statistical_result.table.v1"} {
        if {![dict exists $result provenance operation]||[_get [dict get $result provenance] numeric_api {}] ne "NUMERIC_API_v1"} {_error {Numeric field projection requires a captured Numeric operation}}
        set mapping [numericFieldMap [dict get $result provenance operation]]
        if {![dict exists $mapping $field]} {_error "Source field '$field' has no statistical interpretation"}
        set rows [tableRows $result [dict create $field [dict get $mapping $field]]]
        set cells {};set index 0
        foreach row $rows {
            set item [dict get $row cells $field]
            if {[dict get $item status] ne "value"} {dict unset item value}
            dict set item unit [dict get $item unit_text]
            dict set item row $index;dict set item column 0;dict set item row_id [dict get $row row_id]
            lappend cells $item;incr index
        }
        return [dict create shape [list [llength $rows] 1] cells $cells]
    }
    set fields [numericFields $result]
    if {![dict exists $fields $field]} {_error "Source field '$field' has no statistical interpretation"}
    set item [dict get $fields $field];set kind [dict get $item kind]
    set rows 1;set columns 1;set ids {};set units {};set values {}
    set quantity [dict get $item quantity]
    if {$kind ne "scalar"} {
        if {[dict exists $item parameter_ids]} {set ids [dict get $item parameter_ids]}
        if {[dict exists $item output_ids]} {set ids [dict get $item output_ids]}
        if {[dict exists $item element_ids]} {set ids [dict get $item element_ids]}
        if {$quantity eq "quantiles"} {set ids [dict get $item probabilities]}
        set rows [llength $ids]
        if {$kind eq "matrix"} {set columns $rows}
        if {$quantity eq "cluster_centers"} {set ids [dict get $item row_ids];set rows [llength $ids];set columns [llength [dict get $item column_ids]]}
        if {$rows==0&&$quantity ne "signal_harmonic_bin_powers"} {_error {Statistical field has no declared element identities}}
    }
    if {[dict get $item status] eq "value"} {
        set values [dict get $item value]
        if {$kind eq "scalar"} {set values [list $values]}
        if {$kind eq "matrix"} {set values [concat {*}$values]}
        if {[llength $values]!=$rows*$columns} {_error {Statistical field values differ from their element identities}}
    }
    set cells {};set index 0
    for {set row 0} {$row<$rows} {incr row} {
        for {set column 0} {$column<$columns} {incr column} {
            set cell [dict create id $field quantity $quantity label [dict get $item label] kind scalar status [dict get $item status] reason [dict get $item reason] row $row column $column]
            if {[dict exists $item definition]} {dict set cell definition [dict get $item definition]}
            set unit [dict get $item unit_text]
            if {$kind eq "vector"} {
                dict set cell element_id [lindex $ids $row]
                if {$quantity eq "quantiles"} {dict set cell probability [lindex $ids $row]} elseif {![dict exists $item element_ids]} {set unit [lindex [dict get $item unit] $row]}
            } elseif {$kind eq "matrix"} {
                dict set cell row_id [lindex $ids $row];dict set cell column_id [lindex $ids $column]
                if {$quantity eq "cluster_centers"} {
                    dict set cell column_id [lindex [dict get $item column_ids] $column]
                    set unit [lindex [dict get $item unit column_units] $column]
                    if {$unit eq {}} {set unit unspecified}
                } else {
                set left [lindex [dict get $item unit row_units] $row];set right [lindex [dict get $item unit column_units] $column]
                if {$left in {{} unspecified}||$right in {{} unspecified}} {set unit unspecified} else {set unit "($left)*($right)"}
                }
            }
            dict set cell unit $unit;dict set cell unit_text $unit
            if {[dict get $item status] eq "value"} {dict set cell value [lindex $values $index]}
            lappend cells $cell;incr index
        }
    }
    return [dict create shape [list $rows $columns] cells $cells]
}
proc ::GX::StatisticsV1::_resamplingAssumptions {method} {
    switch -- $method {
        bootstrap {return {{Empirical resampling assumes independent identically distributed observations} {Percentile intervals approximate repeated-sampling coverage; they do not establish exact finite-sample coverage}}}
        permutation_independent {return {{Independent observations with exchangeable group labels under the null} {Monte Carlo tail probability uses the observed statistic and the plus-one correction}}}
        permutation_paired {return {{Independent pairs with sign-exchangeable differences under the null} {Monte Carlo tail probability uses the observed statistic and the plus-one correction}}}
        default {_error {Unknown resampling method}}
    }
}
proc ::GX::StatisticsV1::_validateResamplingContext {context numerical} {
    set method [_get $context method {}]
    if {[_get $context assumptions {}] ne [_resamplingAssumptions $method]} {_error {Resampling result must preserve CORE conditional assumptions}}
    set confidence [_get $context confidence {}]
    if {($method eq "bootstrap"||[dict exists $context confidence])&&(![_finite $confidence]||$confidence<=0||$confidence>=1)} {_error {Invalid resampling confidence}}
    if {[_get $context alternative {}] ni {two_sided greater less}} {_error {Invalid resampling alternative}}
    set inference [expr {$method eq "bootstrap" ? "percentile_confidence_interval" : "monte_carlo_permutation_p_plus_one"}]
    if {[_get $context inference {}] ne $inference||[_get $context approximation {}] ne $inference} {_error {Resampling inference does not match the selected method}}
    if {$method eq "bootstrap"&&([dict get $context alternative] ne "two_sided"||[_get $context quantile_definition {}] ni {{Hyndman-Fan type 7 linear interpolation} {Hyndman-Fan type 5 piecewise linear interpolation}})} {_error {Bootstrap percentile interval must identify its two-sided quantile convention}}
    if {[dict exists $numerical extreme_count]&&[dict exists $numerical replicates]&&[dict get $numerical extreme_count]>[dict get $numerical replicates]} {_error {Extreme count exceeds generated replicates}}
    if {$method eq "bootstrap"&&[_finite [_get $numerical ci_lower {}]]&&[_finite [_get $numerical ci_upper {}]]&&[dict get $numerical ci_lower]>[dict get $numerical ci_upper]} {_error {Bootstrap interval bounds are reversed}}
}
proc ::GX::StatisticsV1::_resamplingPolicy {quantity profile numerical context} {
    if {$profile ne "resampling"} {return {not_applicable {Quantity requires a registered resampling analysis}}}
    if {$quantity in {replicates n_first n_second test_estimate}} {return {value {}}}
    set bootstrap [expr {[dict get $context method] eq "bootstrap"}]
    if {$quantity eq "extreme_count"&&!$bootstrap} {return {value {}}}
    if {$bootstrap&&$quantity ni {ci_lower ci_upper bootstrap_standard_error}||!$bootstrap&&$quantity ne "p_value"} {return {not_applicable {The selected resampling method does not provide this inferential quantity}}}
    if {![dict exists $numerical n_first]||(!$bootstrap&&![dict exists $numerical n_second])} {return {unavailable {Source sample counts are required for resampling interpretation}}}
    if {[dict get $numerical n_first]<2||(!$bootstrap&&[dict get $numerical n_second]<2)} {return {undefined {Resampling inference requires at least two valid observations per sample}}}
    if {![_finite [_get $numerical replicates {}]]||[dict get $numerical replicates]<1} {return {undefined {A generated resampling distribution is required}}}
    if {$bootstrap} {
        if {[dict get $numerical replicates]<2||![_finite [_get $numerical distribution_variance {}]]||[dict get $numerical distribution_variance]<=0} {return {undefined {A degenerate empirical distribution does not establish bootstrap uncertainty or interval coverage}}}
    } elseif {[dict exists $numerical p_value]&&[_finite [dict get $numerical p_value]]&&[dict get $numerical p_value]<=0} {return {error {A finite Monte Carlo plus-one probability cannot be zero}}}
    return {value {}}
}
proc ::GX::StatisticsV1::_anovaAssumptions {method} {
    if {$method eq "ordinary"} {return {{Independent Gaussian observations within groups with equal population variances} {Inference is conditional on the selected ANOVA assumptions}}}
    if {$method eq "welch"} {return {{Independent Gaussian groups with positive estimated variances} {Welch F inference uses approximate denominator degrees of freedom}}}
    _error {Unknown ANOVA method}
}
proc ::GX::StatisticsV1::_anovaPolicy {quantity profile numerical context} {
    if {$profile ne "anova"} {return {not_applicable {Quantity requires a registered ANOVA analysis}}}
    if {$quantity in {group_count grand_mean ss_between ss_within ss_total df_between df_within ms_between ms_within}} {return {value {}}}
    if {$quantity in {eta_squared omega_squared}} {
        if {[_get $context method {}] ne "ordinary"} {return {not_applicable {Classical sums-of-squares effect estimators do not describe this Welch test}}}
        if {![_finite [_get $numerical ss_total {}]]||[dict get $numerical ss_total]<=0} {return {undefined {Effect estimation requires positive total variation}}}
        return {value {}}
    }
    foreach key {ms_within f_numerator_df f_denominator_df} {
        if {![dict exists $numerical $key]} {return {unavailable {Numeric did not supply the required ANOVA variance and degrees of freedom}}}
        if {![_finite [dict get $numerical $key]]||[dict get $numerical $key]<=0} {return {undefined {ANOVA inference requires positive estimated within-group variance and degrees of freedom}}}
    }
    return {value {}}
}
proc ::GX::StatisticsV1::_testAssumptions {method} {
    switch -- $method {
        one_sample_t {return {{Independent observations with a Gaussian sampling model} {Inference is conditional on the selected test assumptions}}}
        paired_t {return {{Independent pairs with Gaussian within-pair differences} {Inference is conditional on the selected test assumptions}}}
        independent_t {return {{Independent Gaussian samples with equal population variances} {Inference is conditional on the selected test assumptions}}}
        welch_t {return {{Independent Gaussian samples; Welch-Satterthwaite degrees of freedom are approximate} {Inference is conditional on the selected test assumptions}}}
        mann_whitney {return {{Independent samples; exchangeability under the equal-distribution null} {A location interpretation additionally requires comparable distribution shapes}}}
        signed_rank {return {{Independent pairs with a symmetric difference distribution under the null} {Zero differences are excluded by the Numeric signed-rank method}}}
        default {_error {Unknown hypothesis test method}}
    }
}
proc ::GX::StatisticsV1::_validateTestContext {context numerical} {
    set method [_get $context method {}]
    if {[_get $context assumptions {}] ne [_testAssumptions $method]} {_error {Hypothesis result must preserve the CORE conditional assumptions}}
    if {[_get $context alternative {}] ni {two_sided greater less}} {_error {Unknown hypothesis alternative}}
    set confidence [_get $context confidence {}]
    if {![_finite $confidence]||$confidence<=0||$confidence>=1} {_error {Invalid hypothesis confidence}}
    set rank [expr {$method in {mann_whitney signed_rank}}]
    set permitted [expr {$rank ? {exact_conditional_permutation exact_conditional_signs tie_corrected_normal_with_continuity} : {exact}}]
    if {[_get $context approximation {}] ni $permitted} {_error {Unknown hypothesis probability method}}
    if {$method eq "mann_whitney"&&[_get $context approximation {}] eq "exact_conditional_signs"||$method eq "signed_rank"&&[_get $context approximation {}] eq "exact_conditional_permutation"} {_error {Probability method does not match rank test}}
    set effect [dict get [dict create one_sample_t cohen_d paired_t cohen_dz independent_t cohen_d welch_t not_reported_for_welch mann_whitney rank_biserial_correlation signed_rank matched_pairs_rank_biserial] $method]
    if {[_get $context effect_name {}] ne $effect} {_error {Effect estimator does not match test method}}
    if {[_get $context ci_status {}] ne [expr {$rank ? "not_defined_for_rank_test" : "defined"}]} {_error {Interval convention does not match test method}}
    if {!$rank&&[_get $numerical test_standard_error {}] ne {}&&[_finite [dict get $numerical test_standard_error]]&&[dict get $numerical test_standard_error]>0} {
        set lo [_get $numerical ci_lower NaN];set hi [_get $numerical ci_upper NaN]
        if {[_finite $lo]&&[_finite $hi]&&$lo>$hi} {_error {Hypothesis interval bounds are reversed}}
    }
}
proc ::GX::StatisticsV1::_testPolicy {quantity profile numerical context} {
    if {$profile eq "resampling"} {return [_resamplingPolicy $quantity $profile $numerical $context]}
    if {$profile eq "anova"&&$quantity eq "p_value"} {return [_anovaPolicy $quantity $profile $numerical $context]}
    if {$profile ne "hypothesis"} {return {not_applicable {Quantity requires a registered hypothesis test}}}
    if {$quantity in {n_first n_second test_estimate null_value}} {return {value {}}}
    set method [dict get $context method];set rank [expr {$method in {mann_whitney signed_rank}}]
    if {[_get $numerical n_first 0]<2||($method ne "one_sample_t"&&[_get $numerical n_second 0]<2)} {return {undefined {The selected test requires at least two observations per sample}}}
    if {$rank&&$quantity in {test_degrees_of_freedom test_standard_error test_standard_deviation interval_margin ci_lower ci_upper}} {return {not_applicable {This rank-test method does not provide t degrees of freedom or a mean confidence interval}}}
    if {$quantity eq "test_standard_deviation"} {if {$method eq "welch_t"} {return {not_applicable {Welch inference does not pool sample standard deviations}}};return {value {}}}
    if {$quantity eq "effect_size"&&$method eq "welch_t"} {return {not_applicable {The selected Welch method does not report a pooled-variance effect estimator}}}
    if {!$rank} {
        if {![dict exists $numerical test_standard_error]} {return {unavailable {Numeric did not supply the tested estimate standard error}}}
        set se [dict get $numerical test_standard_error]
        if {![_finite $se]||$se<=0} {return {undefined {Zero or invalid sample uncertainty does not establish a nondegenerate t sampling distribution}}}
        if {![dict exists $numerical test_degrees_of_freedom]||![_finite [dict get $numerical test_degrees_of_freedom]]||[dict get $numerical test_degrees_of_freedom]<=0} {return {undefined {Test degrees of freedom must be finite and positive}}}
        if {$quantity in {ci_lower ci_upper}} {
            if {![dict exists $numerical ci_lower]||![dict exists $numerical ci_upper]} {return {unavailable {Numeric did not supply both interval endpoints}}}
            set alternative [dict get $context alternative];set lo [dict get $numerical ci_lower];set hi [dict get $numerical ci_upper]
            if {$alternative eq "greater"&&![_infinite $hi 1]||$alternative eq "less"&&![_infinite $lo -1]} {return {error {One-sided interval must retain its specified unbounded endpoint}}}
            if {($alternative ne "less"&&![_finite $lo])||($alternative ne "greater"&&![_finite $hi])} {return {undefined {Numeric did not supply the required finite interval endpoint}}}
        }
    }
    return {value {}}
}
proc ::GX::StatisticsV1::_residual {profile context} {
    set orientation [_get $context orientation y_of_x]
    set x [_get $context x_unit {}];set y [_get $context y_unit {}]
    if {$orientation ni {y_of_x x_of_y r_of_theta parametric joint_responses implicit_residual z_of_xy}} {_error "Unknown residual orientation"}
    if {$orientation eq "joint_responses"&&($profile ne "nonlinear_regression"||[_get $context weight_semantics {}] ne "inverse_variance")} {_error "Joint residuals require nonlinear response components and explicit inverse-variance normalization"}
    if {$profile in {projection parametric_regression geometric_comparison}&&$orientation ne "parametric"} {_error "Geometric models require parametric residual orientation"}
    if {$orientation eq "parametric"&&$profile ni {projection parametric_regression geometric_comparison}} {_error "Functional model cannot claim projected residual semantics"}
    switch -- $orientation {
        y_of_x {set axis y;set unit $y;set definition observed_minus_predicted_at_source_x}
        x_of_y {set axis x;set unit $x;set definition observed_minus_predicted_at_source_y}
        r_of_theta {set axis radius;set unit [_get $context radial_unit {}];set definition observed_minus_predicted_radius_at_source_theta}
        parametric {set axis signed_normal_distance;set unit $x;set definition signed_normal_projection_distance}
        joint_responses {set axis response_components;set unit 1;set definition componentwise_observed_minus_predicted_divided_by_sigma}
        z_of_xy {if {$profile ne "nonlinear_regression"||![dict exists $context surface]} {_error {Surface residuals require their captured two-predictor context}};set axis z;set unit [_get $context z_unit {}];set definition observed_minus_predicted_at_source_xy}
        implicit_residual {if {$profile ne "nonlinear_regression"||![dict exists $context implicit]} {_error {Implicit residuals require their declared equation context}};set axis equation;set unit [dict get $context implicit residual_unit];set definition zero_minus_equation_value_at_observed_coordinates}
    }
    if {[dict exists $context complex]} {set definition lower_cholesky_whitened_cartesian_observed_minus_predicted}
    set status value;set reason {}
    if {$profile eq "comparison"} {set definition predicted_minus_reference_at_aligned_coordinates}
    if {$profile eq "geometric_comparison"} {
        set axis distance
        switch -- [dict get $context comparison_metric] {
            nearest_curve_distance {set definition unsigned_nearest_curve_distance}
            nearest_surface_distance {set definition unsigned_nearest_triangle_surface_distance}
            euclidean_at_normalized_path {set definition euclidean_correspondence_distance_signed_by_target_tangent_side}
        }
    }
    if {[dict exists $context residual_sign]} {
        if {$orientation ni {y_of_x x_of_y}||$profile ni {regression nonlinear_regression smoother interpolation comparison}} {_error {An explicit residual sign requires a functional response or comparison profile}}
        set sign [dict get $context residual_sign]
        if {$sign ni {observed_minus_predicted predicted_minus_observed}} {_error {Unknown functional residual sign}}
        if {$profile eq "comparison"} {
            set definition [expr {$sign eq "predicted_minus_observed" ? "predicted_minus_reference_at_aligned_coordinates" : "reference_minus_predicted_at_aligned_coordinates"}]
        } else {
            set definition "${sign}_at_source_[expr {$orientation eq "y_of_x" ? "x" : "y"}]"
        }
    }
    if {$orientation in {parametric r_of_theta}} {
        if {$x eq {}||$y eq {}||$x ne $y} {set status unavailable;set reason {Euclidean geometry requires both physical axes in the same declared unit}}
        if {$orientation eq "r_of_theta"&&($unit eq {}||$unit ne $x)} {set status unavailable;set reason {Radial units must equal the declared physical coordinate units}}
    }
    if {[_get $context comparison_metric {}] eq "nearest_surface_distance"&&([_get $context z_unit {}] eq {}||[dict get $context z_unit] ne $x)} {set status unavailable;set reason {Euclidean surface comparison requires X/Y/Z in one declared physical unit}}
    if {[_get $context comparison_metric {}] eq "vertical_at_reference_x"&&($x eq {}||$y eq {})} {set status unavailable;set reason {Native functional comparison requires declared physical coordinate units}}
    if {$profile in {summary solver hypothesis anova resampling propagation pca spectral_distribution power_level welch_spectrum local_cloud replicate_profile signal_summary signal_snr signal_spectrum_quality fft_spectrum_quality harmonic_peak_quality harmonic_components event_timing signal_correlation window_metrics signal_spectral}} {set status not_applicable;set reason {This analysis has no residual model}}
    set space original_physical
    if {[dict exists $context response_transform]} {
        set space [expr {[dict get $context response_transform inverse_eligible]?"natural_log_ratio":"modified_log_coordinates"}]
        set definition "${definition}_in_${space}"
    }
    if {[_get $context fit_geometry vertical_response] eq "orthogonal_xy"} {
        set axis normalized_xy_distance;set unit 1;set space standardized_measurement_errors
        set definition norm_of_fitted_minus_observed_coordinate_corrections_divided_by_axis_sigma
    }
    return [dict create definition $definition orientation $orientation axis $axis unit $unit \
        coordinate_space $space status $status reason $reason \
        zero_normal_sign_policy [_get $context zero_normal_sign_policy unspecified]]
}
proc ::GX::StatisticsV1::_spectralBandUnits {psdUnit} {
    set unit [string trim $psdUnit]
    if {$unit eq {}} {return {power_unit unspecified y_unit unspecified}}
    if {$unit eq "1/Hz"} {return {power_unit 1 y_unit 1}}
    if {[regexp {^(.+)\^2/Hz$} $unit unused amplitude]} {return [dict create power_unit "${amplitude}^2" y_unit $amplitude]}
    return [dict create power_unit "${unit}*Hz" y_unit "sqrt(${unit}*Hz)"]
}
proc ::GX::StatisticsV1::_localCloudAssumptions {} {
    return {{Deterministic nearest neighbours sorted by distance, X and Y; CSV row order does not define replicates} {Tricube weights have a positive 1e-6 floor; local quadratic falls back to a weighted constant when rank or conditioning fails} {The Kish effective-count correction is a local dispersion heuristic, not calibrated sampling degrees of freedom or a confidence interval} {Unlabelled source points do not establish independent repeat count or standard error of a consensus mean} {A nonpositive effective variance denominator is undefined and is never clamped to one}}
}
proc ::GX::StatisticsV1::_powerLevelUnits {context} {
    if {[dict exists $context psd_unit]} {return [_spectralBandUnits [dict get $context psd_unit]]}
    if {![dict exists $context power_unit]} {_error {Band levels require the actual PSD or integrated-power unit}}
    set unit [string trim [dict get $context power_unit]]
    if {$unit eq {}||$unit eq "unspecified"} {return {power_unit unspecified y_unit unspecified}}
    if {$unit eq "1"} {return {power_unit 1 y_unit 1}}
    if {[regexp {^(.+)\^2$} $unit -> base]} {return [dict create power_unit $unit y_unit $base]}
    return [dict create power_unit $unit y_unit "sqrt($unit)"]
}
proc ::GX::StatisticsV1::_welchUnits {unit} {
    if {$unit eq {}||$unit eq "unspecified"} {return {x_unit Hz power_unit unspecified psd_unit unspecified asd_unit unspecified}}
    if {$unit eq "1"} {return {x_unit Hz power_unit 1 psd_unit 1/Hz asd_unit 1/sqrt(Hz)}}
    return [dict create x_unit Hz power_unit "${unit}^2" psd_unit "${unit}^2/Hz" asd_unit "${unit}/sqrt(Hz)"]
}
proc ::GX::StatisticsV1::_welchAssumptions {} {
    return {{Arithmetic average of already normalized one-sided periodograms; no FFT is repeated} {Integrated power includes every bin with the recorded uniform frequency width} {Peak search excludes DC and selects the first positive maximum; an empty positive spectrum has no peak frequency} {Overlapping windows are not independent observations; no sampling degrees of freedom or confidence interval is inferred} {dB values use a unit PSD reference; zero PSD has no finite logarithmic value and is published as NaN}}
}
proc ::GX::StatisticsV1::_powerLevelAssumptions {} {
    return {{Power is the linear PSD integral over the recorded frequency band} {The positive RMS reference uses the derived RMS unit} {Zero power has no finite logarithmic level; no numeric floor is a measured value} {Band integration is descriptive and does not establish sampling uncertainty or filter-bank instrument compliance}}
}
proc ::GX::StatisticsV1::_spectralAssumptions {} {
    return {{Descriptive distribution of nonnegative uniformly spaced spectral bins; no sampling uncertainty or regression inference} {Amplitude bins are squared; power and PSD bins are used directly as weights} {PSD weight sum omits the frequency-bin width and is not integrated physical power} {Quantiles use the weighted empirical CDF inverse; ties for the dominant bin choose the first retained frequency}}
}
proc ::GX::StatisticsV1::_propagationAssumptions {kind} {
    if {$kind eq "standard_uncertainty"} {return {{Input standard uncertainties describe independent measurements} {First-order Jacobian linearization; exact for affine transformations with the supplied covariance} {No confidence level or sampling degrees of freedom are implied}}}
    if {$kind eq "covariance"} {return {{Supplied input covariance includes the modeled correlations} {First-order Jacobian linearization; exact for affine transformations with the supplied covariance} {No confidence level or sampling degrees of freedom are implied}}}
    _error {Unknown uncertainty propagation input kind}
}
proc ::GX::StatisticsV1::_validatePropagation {context numerical} {
    set ids [_get $context output_ids {}];set units [_get $context output_units {}]
    if {[llength $ids]<1||[llength $ids]>256||[llength $ids]!=[llength $units]||[llength [lsort -unique $ids]]!=[llength $ids]} {_error {Propagation requires one to 256 unique output identities with matching units}}
    foreach id $ids {if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]{0,255}$} $id]} {_error {Invalid propagation output identity}}}
    foreach unit $units {if {$unit eq {}||[string length $unit]>256||[regexp {[\x00-\x1f]} $unit]} {_error {Propagation output units must be explicit, bounded strings; use unspecified when unknown}}}
    if {[_get $context method {}] ne "first_order_linear_propagation"||[_get $context assumptions {}] ne [_propagationAssumptions [_get $context input_kind {}]]} {_error {Propagation method and conditional assumptions must match the CORE contract}}
    if {![dict exists $numerical output_count]||[dict get $numerical output_count]!=[llength $ids]} {_error {Numeric output count differs from declared output identities}}
    if {![_finite [_get $numerical input_count {}]]||[dict get $numerical input_count]<1||[dict get $numerical input_count]!=floor([dict get $numerical input_count])} {_error {Propagation requires a positive integer input count}}
    if {[dict exists $context output_index]} {
        set index [dict get $context output_index]
        if {![_finite $index]||$index!=floor($index)||$index<1||$index>[llength $ids]} {_error {Selected propagation output index is outside its identity list}}
        set selected [lindex [_get $numerical output_standard_uncertainties {}] [expr {int($index)-1}]]
        set scalar [_get $numerical standard_uncertainty {}]
        set same [expr {$scalar eq $selected}]
        # Scalar JSON and typed-vector decoding can differ by one binary64 ULP;
        # use the same bounded transport tolerance as inference source facts.
        if {!$same&&[_finite $scalar]&&[_finite $selected]} {set same [expr {abs($scalar-$selected)<=4*2.2204460492503131e-16*max(abs($scalar),abs($selected))}]}
        if {!$same} {_error {Selected uncertainty differs from the identified Numeric output}}
    } elseif {[dict exists $numerical standard_uncertainty]} {_error {Scalar propagated uncertainty requires an explicit output index}}
}
proc ::GX::StatisticsV1::_policy {quantity profile numerical context residual} {
    variable quantities
    set policy [dict get $quantities $quantity policy]
    if {[dict exists $context implicit]&&$quantity in {r_squared adjusted_r_squared reduced_chi_squared}} {return {not_applicable {Implicit equation residuals and physical reference normalization do not define response R squared or a known-sigma chi squared statistic}}}
    if {$policy eq "smoothing_fact"} {return [_smoothingPolicy $quantity $profile $numerical $context]}
    set fit [expr {$profile in {regression nonlinear_regression parametric_regression}}]
    if {[_get $context fit_geometry vertical_response] eq "orthogonal_xy"&&$quantity in {r_squared adjusted_r_squared residual_standard_deviation rmse mae max_abs_error}} {
        return {not_applicable {An XY uncertainty fit minimizes normalized corrections in both axes; ordinary functional-response residual scores do not describe this objective}}
    }
    if {$policy eq "spectral_quality"} {return [_spectralQualityPolicy $quantity $profile $numerical $context]}
    if {$policy eq "signal_quality"} {return [_signalQualityPolicy $quantity $profile $numerical $context]}
    if {$policy eq "clustering"} {return [_clusteringPolicy $quantity $profile $numerical $context]}
    if {$policy eq "foundation_regression"} {return [_foundationRegressionPolicy $quantity $profile $numerical $context]}
    if {$policy eq "prediction_uncertainty"} {if {$profile eq "prediction_uncertainty"} {return {value {}}};return {not_applicable {Quantity requires a captured pointwise prediction uncertainty result}}}
    if {$policy eq "covariance_diagnostics"} {return [_covarianceDiagnosticPolicy $quantity $profile $numerical $context]}
    if {$policy eq "survival"} {return [_survivalPolicy $quantity $profile $numerical $context]}
    if {$policy eq "foundation_diagnostics"} {return [_foundationDiagnosticPolicy $quantity $profile $numerical $context]}
    if {$policy eq "location_estimate"} {return [_locationPolicy $quantity $profile $numerical $context]}
    if {$policy eq "signal_spectral"} {return [_signalSpectralPolicy $quantity $profile $numerical $context]}
    if {$policy eq "window_metrics"} {return [_windowMetricsPolicy $quantity $profile $numerical $context]}
    if {$policy eq "signal_correlation"} {return [_signalCorrelationPolicy $quantity $profile $numerical $context]}
    if {$policy eq "event_timing"} {return [_eventTimingPolicy $quantity $profile $numerical $context]}
    if {$policy eq "signal_summary"} {return [_signalSummaryPolicy $quantity $profile $numerical $context]}
    if {$policy eq "replicate_profile"} {return [_replicatePolicy $quantity $profile $numerical $context]}
    if {$policy eq "local_cloud"} {
        if {$profile ne "local_cloud"} {return {not_applicable {Quantity requires a registered local cloud estimator}}}
        if {$quantity ni {local_cloud_count local_cloud_query}&&[_get $numerical local_cloud_count 0]<4} {return {unavailable {At least four source points are required by the local estimator}}}
        if {$quantity in {local_cloud_dispersion local_cloud_variance_denominator}&&[_get $numerical local_cloud_variance_denominator 0]<=0} {return {undefined {Effective weight count does not exceed the fitted coefficient count; no positive variance denominator}}}
        return {value {}}
    }
    if {$policy eq "welch"} {
        if {$profile ne "welch_spectrum"} {return {not_applicable {Quantity requires a registered Welch spectrum}}}
        if {$quantity eq "welch_peak_frequency"&&[_get $numerical welch_peak_psd -1]==0} {return {undefined {No positive non-DC PSD bin identifies a peak frequency}}}
        return {value {}}
    }
    if {$policy eq "power_level"} {
        if {$profile ne "power_level"} {return {not_applicable {Quantity requires the integrated power-level profile}}}
        if {$quantity eq "band_level_db"&&[_get $numerical integrated_power -1]==0} {return {undefined {Zero power has no finite logarithmic level relative to a positive reference}}}
        return {value {}}
    }
    if {$policy eq "spectral"} {
        if {$profile ne "spectral_distribution"&& !($profile eq "welch_spectrum"&&$quantity in {spectral_bin_count spectral_bin_spacing})} {return {not_applicable {Quantity requires a registered spectral distribution}}}
        return {value {}}
    }
    if {$policy eq "geometric_distance"} {
        if {$profile ne "geometric_comparison"||[_get $context comparison_metric {}] ni {nearest_curve_distance nearest_surface_distance}||[_get $context comparison_direction {}] ne "bidirectional_pooled"} {return {not_applicable {Sampled Hausdorff distance requires both directions of a nearest-geometry comparison}}}
        if {[dict get $residual status] ne "value"} {return [list [dict get $residual status] [dict get $residual reason]]}
        return {value {}}
    }
    if {$policy in {comparison_score relative_count relative_error}} {
        if {$profile ne "comparison"} {return {not_applicable {Quantity requires an aligned prediction-comparison profile}}}
        if {![dict exists $numerical n]} {return {unavailable {Numeric did not supply an aligned comparison count}}}
        if {$policy eq "comparison_score"} {
            if {[dict get $numerical n]<2} {return {undefined {A centered prediction score requires at least two aligned observations}}}
            if {![dict exists $numerical response_variance]} {return {unavailable {Reference dispersion is required for a centered prediction score}}}
            if {![_finite [dict get $numerical response_variance]]||[dict get $numerical response_variance]<=0} {return {undefined {Reference dispersion is zero or nonfinite}}}
        } else {
            if {![dict exists $numerical relative_n]||![dict exists $numerical relative_floor]} {return {unavailable {Numeric must supply the eligible denominator count and exclusion floor}}}
            if {$policy eq "relative_error"&&[dict get $numerical relative_n]<1} {return {undefined {No nonzero reference denominators satisfy the recorded relative-error floor}}}
        }
        return {value {}}
    }
    if {$policy eq "pca"} {
        if {$profile ne "pca"} {return {not_applicable {Quantity requires a registered PCA spectral summary}}}
        if {$quantity in {explained_ratio cumulative_ratio}&&[_get $numerical total_component_variance 0]<=0} {return {undefined {Zero total spectral moment has no explained proportion}}}
        return {value {}}
    }
    if {$policy eq "propagation"} {
        if {$profile ne "propagation"} {return {not_applicable {Quantity requires the registered measurement propagation profile}}}
        if {$quantity eq "standard_uncertainty"&&![dict exists $context output_index]} {return {unavailable {Select an identified output to request a scalar uncertainty}}}
        return {value {}}
    }
    if {$profile eq "summary"&&$policy eq "chi_squared"} {
        if {[_get $context weight_semantics unweighted] ne "inverse_variance"} {return {not_applicable {Reduced chi squared for a weighted mean requires absolute inverse-variance weights}}}
        if {[_get $context sampling_model unspecified] ne "independent_observations"||[_get $context noise_model unspecified] ne "independent_gaussian_known_sigma"} {return {unavailable {Reduced chi squared requires explicitly independent Gaussian measurements with known absolute uncertainties}}}
        if {[_get $numerical n 0]<2||[_get $numerical dof 0]<=0} {return {undefined {Weighted-mean reduced chi squared requires positive residual degrees of freedom}}}
        return {value {}}
    }
    if {$profile in {comparison geometric_comparison}} {
        if {$policy in {inference residual_dof chi_squared r_squared adjusted_r_squared geometric_score smoother}} {return {not_applicable {A pointwise numerical comparison does not estimate a regression or sampling-inference model}}}
        if {$policy eq "residual"} {
            if {![dict exists $numerical n]} {return {unavailable {Numeric did not supply an aligned comparison count}}}
            if {[dict get $numerical n]<1} {return {undefined {No aligned observations exist for this comparison subset}}}
        }
    }
    if {[_get $context orientation {}] eq "joint_responses"&&$quantity in {r_squared adjusted_r_squared residual_standard_deviation rmse mae max_abs_error}} {
        return {not_applicable {Different physical response units cannot be pooled into a single unweighted residual score}}
    }
    if {$policy eq "resampling"} {return [_resamplingPolicy $quantity $profile $numerical $context]}
    if {$policy in {anova anova_fact anova_effect}} {return [_anovaPolicy $quantity $profile $numerical $context]}
    if {$policy in {hypothesis hypothesis_fact}} {return [_testPolicy $quantity $profile $numerical $context]}
    if {$policy eq "descriptive"} {return {value {}}}
    if {$policy in {summary summary_sample sampling_mean measurement_mean weighted_summary quantiles}} {
        if {$profile ne "summary"} {return {not_applicable {Quantity requires a registered summary analysis}}}
        if {![dict exists $numerical n]} {return {unavailable {Numeric did not supply an observation count}}}
        if {[dict get $numerical n]<1||($policy eq "summary_sample"&&[dict get $numerical n]<2)} {return {undefined {Insufficient observations for the specified estimator}}}
        if {$policy in {sampling_mean measurement_mean}} {
            if {[_get $context sampling_model unspecified] ne "independent_observations"} {return {unavailable {Mean uncertainty requires an explicit independent-observation model}}}
            if {$policy eq "measurement_mean"&&[_get $context weight_semantics unweighted] ne "inverse_variance"} {return {not_applicable {Known measurement uncertainty requires absolute inverse-variance weights}}}
            if {$policy eq "sampling_mean"} {
                if {[_get $context mean_se_model none] ne "sampling"} {return {unavailable {Sampling standard error was not requested}}}
                if {[dict get $numerical n]<2||([dict exists $numerical effective_n]&&[dict get $numerical effective_n]<=1)} {return {undefined {Sampling standard error requires more than one effective observation}}}
            }
        }
        if {$policy eq "weighted_summary"&&[_get $context weight_semantics unweighted] eq "unweighted"} {return {not_applicable {This quantity belongs to explicitly weighted observations}}}
        if {$policy eq "quantiles"&&(![dict exists $numerical quantile_probabilities]||[_get $context quantile_definition {}] eq {})} {return {unavailable {Numeric must supply quantile probabilities and its estimator definition}}}
        return {value {}}
    }
    if {$policy eq "smoother"} {if {$profile ne "smoother"} {return {not_applicable {EDF belongs to an explicitly specified smoother}}};return {value {}}}
    if {$policy in {residual r_squared adjusted_r_squared geometric_score residual_dof chi_squared inference}&&[dict get $residual status] ne "value"} {return [list [dict get $residual status] [dict get $residual reason]]}
    if {$policy eq "residual"} {return {value {}}}
    if {[dict exists $context smoothing]&&$policy in {inference residual_dof chi_squared adjusted_r_squared}} {return {unavailable {Smoothing-induced correlations and effective complexity have not been propagated; coefficients and descriptive residuals remain available}}}
    if {[dict exists $context baseline_correction]&&$policy in {inference residual_dof chi_squared adjusted_r_squared}} {return {unavailable {Estimated baseline uncertainty, induced residual correlations and effective complexity have not been propagated; fit coefficients and descriptive residuals remain available}}}
    if {[_get $context sample_role training] eq "evaluation"&&$policy in {inference residual_dof chi_squared adjusted_r_squared}} {return {not_applicable {Training-parameter inference is not recomputed from evaluation residuals}}}
    if {[dict exists $context gls]&&$policy in {inference residual_dof chi_squared r_squared adjusted_r_squared}} {return [_glsRegressionPolicy $quantity $policy $context]}
    if {$policy eq "geometric_score"} {if {$profile ni {projection parametric_regression}} {return {not_applicable {XY dispersion is a geometric descriptive score}}};return {value {}}}
    if {$policy in {r_squared adjusted_r_squared}} {
        if {$profile in {projection parametric_regression}} {return {not_applicable {Projected XY dispersion is not functional-response R squared}}}
        if {$profile eq "interpolation"} {return {not_applicable {Exact interpolation does not establish regression goodness of fit}}}
        if {[_get $numerical response_variance {}] eq {}} {return {unavailable {Response dispersion is required to determine whether R squared is defined}}}
        if {![_finite [dict get $numerical response_variance]]} {return {undefined {Response dispersion is nonfinite; centered R squared cannot be interpreted}}}
        if {[_get $numerical response_variance 0]<=0} {return {undefined {Response is constant; centered R squared has a zero denominator}}}
        if {$policy eq "adjusted_r_squared"&&(!$fit||![_get $context has_intercept 0])} {return {not_applicable {Adjusted R squared requires an identified regression model with intercept}}}
        return {value {}}
    }
    if {[dict exists $context knot_spline]&&$policy in {inference residual_dof chi_squared adjusted_r_squared}} {return {not_applicable {This knot contract supplies descriptive residuals without parameter inference}}}
    if {$profile eq "interpolation"} {return {not_applicable {Interpolation knot values are not independently estimated regression parameters}}}
    if {$policy eq "residual_dof"} {
        if {$profile eq "smoother"&&(![dict exists $numerical edf]||[_get $context smoother_dof_convention {}] eq {})} {return {unavailable {Smoother EDF and residual variance DOF convention must be supplied by Numeric}}}
        if {$profile eq "projection"} {return {unavailable {Projection model has no validated inferential degrees-of-freedom model}}}
        return {value {}}
    }
    if {$policy eq "chi_squared"} {
        if {[_get $context weight_semantics unweighted] ne "inverse_variance"||[_get $context noise_model unspecified] ne "independent_gaussian_known_sigma"} {return {not_applicable {Reduced chi squared requires declared independent Gaussian measurement errors with known absolute sigma}}}
    }
    if {!$fit&&$profile ne "smoother"} {return {not_applicable {No registered parameter inference model}}}
    if {$profile eq "smoother"&&(![dict exists $numerical edf]||[_get $context smoother_dof_convention {}] eq {})} {return {unavailable {Smoother uncertainty requires EDF and a validated residual variance DOF convention}}}
    foreach field {rank p dof} {if {![dict exists $numerical $field]} {return [list unavailable "Numeric did not supply $field for inference"]}}
    if {[dict get $numerical rank]<[_get $numerical free_parameter_count [dict get $numerical p]]} {return {undefined {Rank-deficient free parameterization; independent parameter uncertainty is not identifiable}}}
    if {[dict get $numerical dof]<=0} {return {undefined {No positive residual degrees of freedom}}}
    if {[_get $context constraints unknown] ni {none inactive_bounds fixed_parameters}} {return {unavailable {Active or unclassified constraints require a validated constrained inference method}}}
    if {[_get $context loss linear] ne "linear"} {return {unavailable {Robust loss requires a separately validated uncertainty estimator}}}
    if {$profile eq "nonlinear_regression"||[_get $context fit_geometry vertical_response] eq "orthogonal_xy"} {
        if {![dict exists $numerical converged]} {return {unavailable {Solver convergence was not reported}}}
        if {![dict get $numerical converged]} {return {unavailable {Solver did not converge; local covariance cannot be presented as validated uncertainty}}}
    }
    if {$quantity in {covariance standard_errors}&&[_get $context covariance_scaling {}] eq {}} {return {unavailable {Covariance scaling convention is unspecified}}}
    if {$quantity in {covariance standard_errors}&&[dict exists $context regional_fit]} {
        set regional [dict get $context regional_fit]
        foreach count [dict get $regional region_counts] {if {$count==0} {return {unavailable {An unobserved region has no direct training support; ordinary local intervals require a separately validated support analysis}}}}
        foreach fixed [dict get $regional breakpoint_fixed] continuity [dict get $regional continuity] count [dict get $regional sample_coincidence_counts] {
            if {!$fixed&&$continuity eq "C0"&&$count>0} {return {unavailable {A free C0 breakpoint coincides with a training predictor; its one-sided Jacobian does not establish an ordinary symmetric local interval}}}
        }
    }
    return {value {}}
}
proc ::GX::StatisticsV1::_regionalFitAssumptions {} {
    return {{All regions and free breakpoints share one joint optimization and covariance} {Breakpoint intervals are local approximations conditional on identified regime changes, observation support and the chosen model; they are not profile intervals or evidence of a unique global optimum} {Predictions in observation gaps and beyond observed support are model continuations, not observed regimes}}
}
proc ::GX::StatisticsV1::_baselineAssumptions {} {
    return {{The spectrum was baseline-corrected in a separate Dataset; original Y, estimated baseline, corrected Y and fitted model have distinct identities} {Baseline estimation uncertainty and induced correlations are not propagated; full-spectrum confidence intervals and likelihood criteria are unavailable}}
}
proc ::GX::StatisticsV1::_validateBaselineContext {facts} {
    set fields {schema method source_dataset_id source_sha256 original_y_variable_id baseline_variable_id corrected_variable_id uncertainty_policy}
    _keys $facts $fields baseline_correction
    foreach key $fields {if {![dict exists $facts $key]||[dict get $facts $key] eq {}} {_error "Baseline context requires $key"}}
    if {[dict get $facts schema] ne "gxtxt.baseline_context.v1"||[dict get $facts method] ni {asls constant linear polynomial}||[dict get $facts uncertainty_policy] ne "baseline_treated_as_fixed_no_baseline_estimation_uncertainty"||![regexp {^[a-f0-9]{64}$} [dict get $facts source_sha256]]} {_error {Invalid baseline provenance or uncertainty policy}}
    set ids {};foreach key {original_y_variable_id baseline_variable_id corrected_variable_id} {lappend ids [dict get $facts $key]}
    if {[llength [lsort -unique $ids]]!=3} {_error {Original, baseline and corrected Variables must remain distinct}}
}
proc ::GX::StatisticsV1::_smoothingAssumptions {} {
    return [list {Input coordinates include an explicitly smoothed derived variable.} {Smoothing-induced correlations, bias and effective complexity are not propagated; independent-error parameter inference, bootstrap and likelihood comparison are unavailable.}]
}
proc ::GX::StatisticsV1::_validateSmoothingContext {facts} {
    _keys $facts {schema bindings} smoothing
    if {[_get $facts schema {}] ne "gxtxt.smoothing_context.v1"||![dict exists $facts bindings]||[llength [dict get $facts bindings]]<1||[llength [dict get $facts bindings]]>64} {_error {Smoothing context requires one to64 captured bindings}}
    set fields {variable_id method source_dataset_id source_sha256 original_y_variable_id smoothed_variable_id uncertainty_policy}
    foreach binding [dict get $facts bindings] {
        _keys $binding $fields smoothing_binding
        foreach key $fields {if {![dict exists $binding $key]||[dict get $binding $key] eq {}} {_error "Smoothing binding requires $key"}}
        if {[dict get $binding method] ni {moving_mean moving_median savitzky_golay local_polynomial lowess}||![regexp {^[a-f0-9]{64}$} [dict get $binding source_sha256]]||[dict get $binding original_y_variable_id] eq [dict get $binding smoothed_variable_id]||[dict get $binding uncertainty_policy] ne "smoothing_induces_correlated_errors_no_parameter_inference"} {_error {Invalid smoothing lineage or uncertainty policy}}
    }
}
proc ::GX::StatisticsV1::_validateRegionalFit {facts numerical parameters} {
    _keys $facts {schema region_counts breakpoint_ids breakpoint_values breakpoint_fixed continuity sample_coincidence_counts} regional_fit
    foreach key {schema region_counts breakpoint_ids breakpoint_values breakpoint_fixed continuity sample_coincidence_counts} {if {![dict exists $facts $key]} {_error "Regional inference facts require $key"}}
    if {[dict get $facts schema] ne "gxtxt.regional_fit_inference.v1"} {_error {Unsupported regional inference facts}}
    set ids [dict get $facts breakpoint_ids];set count [llength $ids]
    if {$count<1||$count>32||[llength [lsort -unique $ids]]!=$count||[llength [dict get $facts region_counts]]!=$count+1} {_error {Invalid regional inference dimensions}}
    foreach key {breakpoint_values breakpoint_fixed continuity sample_coincidence_counts} {if {[llength [dict get $facts $key]]!=$count} {_error {Regional breakpoint facts differ in length}}}
    set total 0
    foreach n [dict get $facts region_counts] {if {![_finite $n]||$n<0||$n!=floor($n)} {_error {Invalid regional observation count}};set total [expr {$total+$n}]}
    if {![dict exists $numerical n]||$total!=[dict get $numerical n]} {_error {Regional support counts differ from fitted observations}}
    set byId {};foreach p $parameters {dict set byId [dict get $p id] $p}
    set previous {}
    foreach id $ids value [dict get $facts breakpoint_values] fixed [dict get $facts breakpoint_fixed] continuity [dict get $facts continuity] n [dict get $facts sample_coincidence_counts] {
        if {![dict exists $byId $id]||![_finite $value]||$value!=[dict get $byId $id value]||![_finite $fixed]||$fixed ni {0 1 0.0 1.0}||$continuity ni {C0 C1}||![_finite $n]||$n<0||$n>=$total+1||$n!=floor($n)} {_error {Invalid captured breakpoint identity, value or regularity facts}}
        if {($fixed&&[dict get $byId $id role] ne "fixed")||(!$fixed&&[dict get $byId $id role] ne "free")} {_error {Breakpoint fixed/free role differs from the fitted parameter}}
        if {$previous ne {}&&$value<$previous} {_error {Captured breakpoint support is not in physical order}}
        set previous $value
    }
}
proc ::GX::StatisticsV1::interpret {request} {return [_interpretRequest $request]}
proc ::GX::StatisticsV1::_interpretRequest {request {selectedQuantities {}} {validatedDescriptor {}}} {
    variable quantities
    _keys $request {model_id context numerical provenance parameters parameter_uncertainty solver_receipt} request
    foreach key {model_id context numerical provenance} {if {![dict exists $request $key]} {_error "Request requires $key"}}
    if {$validatedDescriptor eq {}} {
        set descriptor [model [dict get $request model_id]]
    } else {
        # Only a synchronous CORE page can supply this already validated
        # descriptor. Public interpret accepts one argument and always discovers
        # the current catalog; no client may opt out of that validation.
        set descriptor $validatedDescriptor
        if {[dict get $descriptor id] ne [dict get $request model_id]} {_error {Validated model snapshot differs from the row request}}
    }
    set profile [dict get $descriptor profile]
    set context [dict get $request context];set numerical [dict get $request numerical]
    _keys $numerical [concat [dict keys $quantities] {p free_parameter_count response_variance converged quantile_probabilities distribution_variance tail_tolerance input_count output_count component_count total_component_variance relative_floor harmonic_orders}] numerical
    _keys $context {orientation residual_sign comparison_metric comparison_direction x_unit y_unit z_unit radial_unit x_variable_id y_variable_id weight_unit weight_semantics noise_model has_intercept constraints covariance_scaling coefficient_space translation smoother_dof_convention zero_normal_sign_policy sample_role solver method assumptions loss sampling_model mean_se_model quantile_definition alternative confidence approximation effect_name ci_status group_index inference mad_scale output_ids output_units output_index input_kind input_semantics exclude_dc asd_unit psd_unit power_unit reference_rms zero_policy averaging peak_policy variance_correction insufficient_policy mode component_method normalization sample_rate fundamental_hz fundamental_bin signal_zero noise_zero window detrend fundamental_mode guard_bins track_harmonics exclude_dc_bins spur_search level_floor component_level_floor timing_operation peak_resolved spectral_operation sidedness family link cluster_ids initialization empty_cluster_policy iteration_limit convergence_evidence fit_geometry regional_fit baseline_correction smoother_predictor_unit response_transform smoothing conditional_parameter_units gls implicit complex rational surface knot_spline} context
    if {[dict exists $context response_transform]} {
        _validateLogResponseContext $context
        foreach assumption [_logResponseContextAssumptions $context] {if {[lsearch -exact [_get $context assumptions {}] $assumption]<0} {_error {Log-response context must retain CORE interpretation qualifications}}}
    }
    set geometry [_get $context fit_geometry vertical_response]
    if {[dict exists $context smoothing]} {
        _validateSmoothingContext [dict get $context smoothing]
        foreach assumption [_smoothingAssumptions] {if {[lsearch -exact [_get $context assumptions {}] $assumption]<0} {_error {Smoothing context must retain CORE uncertainty qualifications}}}
    }
    if {[dict exists $context baseline_correction]} {
        _validateBaselineContext [dict get $context baseline_correction]
        foreach assumption [_baselineAssumptions] {if {[lsearch -exact [_get $context assumptions {}] $assumption]<0} {_error {Baseline context must retain CORE uncertainty qualifications}}}
    }
    if {[dict exists $context regional_fit]} {
        if {$profile ne "nonlinear_regression"||[_get $context sample_role training] ne "training"} {_error {Regional inference facts require the actual joint nonlinear training fit}}
        _validateRegionalFit [dict get $context regional_fit] $numerical [dict get $request parameters]
        foreach assumption [_regionalFitAssumptions] {if {[lsearch -exact [_get $context assumptions {}] $assumption]<0} {_error {Regional inference must retain CORE conditional assumptions}}}
    }
    if {$geometry ni {vertical_response orthogonal_xy implicit_algebraic vertical_response_z_at_exact_xy}} {_error {Unknown fit geometry}}
    if {$geometry eq "orthogonal_xy"} {
        if {$profile ni {regression nonlinear_regression}||[_get $context orientation y_of_x] ni {y_of_x x_of_y}||[_get $context weight_semantics {}] ne "inverse_variance"||[_get $context covariance_scaling {}] ne "absolute_measurement_variance"||[_get $context loss linear] ne "linear"||[_get $context sample_role training] ne "training"||[dict exists $context residual_sign]} {_error {Orthogonal XY geometry requires its training regression, absolute axis uncertainties and quadratic normalized corrections}}
        if {![dict exists $request solver_receipt]||[_get $context assumptions {}] ne [_orthogonalXYAssumptions]} {_error {Orthogonal XY interpretation requires its captured native receipt and CORE assumptions}}
        if {[_get $context noise_model unspecified] ni {unspecified independent_gaussian_known_sigma}} {_error {Orthogonal XY inference cannot replace supplied absolute uncertainties with estimated response variance}}
    }
    if {$profile eq "geometric_comparison"} {
        if {[_get $context comparison_metric {}] ni {nearest_curve_distance nearest_surface_distance euclidean_at_normalized_path}} {_error {Geometric comparisons require an explicit correspondence metric}}
        if {[_get $context comparison_direction {}] ni {reference_to_target bidirectional_pooled}} {_error {Geometric comparisons require an explicit direction}}
        if {[dict get $context comparison_metric] eq "euclidean_at_normalized_path"&&[dict get $context comparison_direction] ne "reference_to_target"} {_error {Normalized-path correspondence is directional}}
    } elseif {[dict exists $context comparison_metric]&&($profile ne "comparison"||[dict get $context comparison_metric] ne "vertical_at_reference_x")} {_error {Comparison metric is incompatible with its registered profile}}
    if {[dict exists $context z_unit]&&[_get $context comparison_metric {}] ne "nearest_surface_distance"&&![dict exists $context surface]} {_error {A third coordinate unit requires a declared surface response or surface-comparison metric}}
    foreach {key allowed} {sampling_model {unspecified independent_observations} mean_se_model {none sampling} mad_scale {raw normal_consistency}} {
        if {$key eq "sampling_model"&&$profile eq "replicate_profile"} {set allowed {unspecified independent_traces}}
        if {[dict exists $context $key]&&[dict get $context $key] ni $allowed} {_error "Unknown $key"}
    }
    if {[dict exists $numerical relative_n]} {
        set count [dict get $numerical relative_n]
        if {![_finite $count]||$count<0||$count!=floor($count)||![_finite [_get $numerical n {}]]||$count>[dict get $numerical n]} {_error {Relative denominator count must be an integer within the aligned observation count}}
    }
    if {[dict exists $numerical relative_floor]&&(![_finite [dict get $numerical relative_floor]]||[dict get $numerical relative_floor]<0)} {_error {Relative denominator floor must be finite and nonnegative}}
    if {[dict exists $numerical quantile_probabilities]} {
        set probabilities [dict get $numerical quantile_probabilities]
        if {[llength $probabilities]>4096} {_error "Quantile metadata exceeds the bounded contract"}
        foreach probability $probabilities {if {![_finite $probability]||$probability<0||$probability>1} {_error "Quantile probabilities must be within zero and one"}}
    }
    if {$profile eq "pca"} {
        if {[_get $context method {}] ni {centered_sample_covariance uncentered_second_moment_n_minus_one}} {_error {PCA must preserve the centering and moment denominator convention}}
        foreach field {n component_count component_index} {if {![_finite [_get $numerical $field {}]]||[dict get $numerical $field]<1||[dict get $numerical $field]!=floor([dict get $numerical $field])} {_error {PCA requires positive integer dimensions and component identity}}}
        if {[dict get $numerical n]<2||[dict get $numerical component_index]>[dict get $numerical component_count]} {_error {Invalid PCA observation count or component index}}
        if {![_finite [_get $numerical total_component_variance {}]]||[dict get $numerical total_component_variance]<0} {_error {PCA requires a finite nonnegative total spectral moment}}
        if {[_get $context assumptions {}] ne {{Descriptive spectral decomposition; explained ratios do not establish sampling inference or causality} {Component signs and bases within degenerate subspaces are not unique}}} {_error {PCA must retain the CORE interpretation limits}}
    }
    if {$profile in {signal_snr signal_spectrum_quality}} {_validateSignalQuality $profile $numerical $context}
    if {$profile in {fft_spectrum_quality harmonic_peak_quality harmonic_components}} {_validateSpectralQuality $profile $numerical $context}
    if {$profile eq "clustering"} {_validateClustering $numerical $context}
    if {$profile eq "foundation_regression"} {_validateFoundationRegression $numerical $context}
    if {$profile eq "prediction_uncertainty"} {_validatePrediction $request}
    if {$profile eq "smoother"} {_validateSmoothing $request}
    if {$profile eq "covariance_diagnostics"} {_validateCovarianceDiagnostic $numerical $context}
    if {$profile eq "survival"} {_validateSurvival $numerical $context}
    if {$profile in {foundation_correlation multiplicity}} {_validateFoundationDiagnostic $profile $numerical $context}
    if {$profile eq "location_estimate"} {
        _validateLocation $numerical $context
        set locationId [expr {[dict get $context method] eq "student_t_mean"?"mean_confidence_interval":"huber_location"}]
        if {[dict get $descriptor owner] eq "math.numeric"&&[dict get $descriptor id] ne "math.numeric.$locationId"} {_error {Registered Numeric location model identity differs from its estimator}}
    }
    if {$profile eq "signal_summary"} {_validateSignalSummary $numerical $context}
    if {$profile eq "signal_spectral"} {
        _validateSignalSpectral $numerical $context
        if {[dict get $descriptor owner] eq "math.numeric"&&[dict get $descriptor id] ne "math.numeric.signal_[dict get $context spectral_operation]"} {_error {Registered Numeric spectral model identity differs from its estimator}}
    }
    if {$profile eq "window_metrics"} {_validateWindowMetrics $numerical $context}
    if {$profile eq "signal_correlation"} {_validateSignalCorrelation $numerical $context}
    if {$profile eq "event_timing"} {_validateEventTiming $numerical $context}
    if {$profile eq "replicate_profile"} {_validateReplicate $numerical $context}
    if {$profile eq "local_cloud"} {
        if {[_get $context method {}] ne "nearest_tricube_quadratic_or_constant"||[_get $context variance_correction {}] ne "kish_effective_n_minus_parameters"||[_get $context insufficient_policy {}] ne "undefined_without_positive_variance_denominator"||[_get $context assumptions {}] ne [_localCloudAssumptions]} {_error {Local cloud estimator must preserve its algorithm and conditional interpretation}}
        set count [_get $numerical local_cloud_count {}]
        if {![_finite $count]||$count<1||$count>25||$count!=floor($count)} {_error {Local neighbourhood count must be an integer from one to 25}}
        if {$count>=4} {
            if {[_get $numerical local_cloud_degree {}] ni {0 0.0 2 2.0}} {_error {Local estimator degree must be constant or quadratic}}
            set effective [_get $numerical local_cloud_effective_count {}]
            if {![_finite $effective]||$effective<1||$effective>$count*(1+1e-12)||![_finite [_get $numerical local_cloud_variance_denominator {}]]} {_error {Local effective weight facts must be finite and consistent with the neighbourhood count}}
        }
    }
    if {$profile eq "welch_spectrum"} {
        dict for {key expected} [_welchUnits [_get $context y_unit {}]] {if {[_get $context $key {}] ne $expected} {_error {Welch units differ from the captured signal unit}}}
        if {[_get $context zero_policy {}] ne "undefined_finite_logarithmic_level"||[_get $context averaging {}] ne "arithmetic_periodogram_mean"||[_get $context peak_policy {}] ne "first_positive_maximum_excluding_dc"||[_get $context assumptions {}] ne [_welchAssumptions]} {_error {Welch requires the captured estimator, peak/zero policies and CORE interpretation limits}}
        foreach key {welch_window_count spectral_bin_count} {
            if {![_finite [_get $numerical $key {}]]||[dict get $numerical $key]<1||[dict get $numerical $key]!=floor([dict get $numerical $key])} {_error {Welch counts must be positive integers}}
        }
        if {[dict get $numerical spectral_bin_count]<2} {_error {Welch requires at least two spectral bins}}
        foreach key {spectral_bin_spacing welch_mean_enbw} {if {![_finite [_get $numerical $key {}]]||[dict get $numerical $key]<=0} {_error {Welch frequency spacing and bandwidth must be finite and positive}}}
        foreach key {welch_integrated_power welch_peak_psd welch_zero_level_bins} {if {![_finite [_get $numerical $key {}]]||[dict get $numerical $key]<0} {_error {Welch power and zero count must be finite and nonnegative}}}
        set zeros [dict get $numerical welch_zero_level_bins]
        if {$zeros!=floor($zeros)||$zeros>[dict get $numerical spectral_bin_count]} {_error {Welch zero count must identify actual bins}}
    }
    if {$profile eq "power_level"} {
        dict for {key expected} [_powerLevelUnits $context] {if {[_get $context $key {}] ne $expected} {_error {Band power and RMS units conflict with the actual source unit}}}
        if {![_finite [_get $numerical integrated_power {}]]||[dict get $numerical integrated_power]<0} {_error {Integrated band power must be finite and nonnegative}}
        if {![_finite [_get $context reference_rms {}]]||[dict get $context reference_rms]<=0} {_error {RMS reference must be finite and positive}}
        if {[_get $context zero_policy {}] ne "undefined_finite_logarithmic_level"||[_get $context assumptions {}] ne [_powerLevelAssumptions]} {_error {Power level must retain its CORE zero policy and interpretation limits}}
    }
    if {$profile eq "spectral_distribution"} {
        if {[_get $context input_semantics {}] ni {amplitude power psd}||![string is boolean -strict [_get $context exclude_dc {}]]} {_error {Spectral interpretation requires explicit input semantics and DC handling}}
        if {[_get $context assumptions {}] ne [_spectralAssumptions]||[_get $context quantile_definition {}] ne "weighted empirical CDF inverse"} {_error {Spectral interpretation requires the CORE descriptive limits and actual quantile definition}}
        foreach key {spectral_bin_count spectral_bin_spacing spectral_weight_sum} {
            if {![_finite [_get $numerical $key {}]]||[dict get $numerical $key]<=0} {_error "Spectral result requires a positive finite $key"}
        }
        if {[dict get $numerical spectral_bin_count]<2||[dict get $numerical spectral_bin_count]!=floor([dict get $numerical spectral_bin_count])} {_error {Spectral bin count must be an integer of at least two}}
    }
    if {$profile eq "propagation"} {_validatePropagation $context $numerical}
    if {$profile eq "hypothesis"} {_validateTestContext $context $numerical}
    if {$profile eq "resampling"} {
        _validateResamplingContext $context $numerical
        if {[dict get $descriptor owner] eq "math.numeric"} {
            set id [dict get $descriptor id];set method [dict get $context method]
            if {$id eq "math.numeric.foundation_bootstrap_interval"&&($method ne "bootstrap"||[dict get $context quantile_definition] ne "Hyndman-Fan type 5 piecewise linear interpolation")} {_error {Foundation bootstrap must retain its original quantile estimator}}
            if {$id eq "math.numeric.foundation_permutation_mean"&&($method ne "permutation_independent"||[dict get $context alternative] ne "two_sided"||![_finite [_get $numerical tail_tolerance {}]]||[dict get $numerical tail_tolerance]!=0)} {_error {Foundation permutation must retain its strict absolute-tail convention}}
            if {$id eq "math.numeric.resampling"&&$method eq "bootstrap"&&[dict get $context quantile_definition] ne "Hyndman-Fan type 7 linear interpolation"} {_error {Public resampling summary must retain its registered quantile estimator}}
            if {$id eq "math.numeric.resampling"&&$method ne "bootstrap"&&(![_finite [_get $numerical tail_tolerance {}]]||[dict get $numerical tail_tolerance]<=0)} {_error {Public resampling summary must retain its positive numerical tail tolerance}}
        }
    }
    if {$profile eq "anova"} {
        if {[_get $context method {}] ni {ordinary welch}} {_error {Unknown ANOVA method}}
        if {[_get $context assumptions {}] ne [_anovaAssumptions [dict get $context method]]} {_error {ANOVA result must preserve the CORE conditional assumptions}}
    }
    set provenance [dict get $request provenance]
    foreach key {numeric_api operation producer} {if {[_get $provenance $key {}] eq {}} {_error "Provenance requires $key"}}
    if {[dict get $provenance numeric_api] ne "NUMERIC_API_v1"} {_error "Numerical provenance must identify the public NUMERIC_API_v1 authority"}
    foreach {field permitted} {weight_semantics {unweighted relative inverse_variance} constraints {none inactive_bounds active_bounds fixed_parameters equality unknown} coefficient_space {original_physical translated_fit normalized_basis} sample_role {training evaluation}} {
        if {[dict exists $context $field]&&[dict get $context $field] ni $permitted} {_error "Invalid $field"}
    }
    foreach field {n p rank dof edf free_parameter_count} {
        if {[dict exists $numerical $field]&&(![_finite [dict get $numerical $field]]||[dict get $numerical $field]<0)} {_error "Invalid numerical fact '$field'"}
    }
    foreach field {n p rank free_parameter_count n_first n_second replicates extreme_count} {if {[dict exists $numerical $field]&&[dict get $numerical $field]!=floor([dict get $numerical $field])} {_error "$field must be an integer"}}
    foreach field {converged} {if {[dict exists $numerical $field]&&![string is boolean -strict [dict get $numerical $field]]} {_error "Invalid $field"}}
    if {[dict exists $numerical rank]&&[dict exists $numerical p]&&[dict get $numerical rank]>[dict get $numerical p]} {_error "Rank exceeds parameter count"}
    if {[dict exists $numerical rank]&&[dict exists $numerical n]&&[dict get $numerical rank]>[dict get $numerical n]} {_error "Rank exceeds observation count"}
    if {[dict exists $numerical free_parameter_count]} {
        if {![dict exists $numerical p]||[dict get $numerical free_parameter_count]>[dict get $numerical p]} {_error "Free parameter count exceeds total parameter count"}
        if {[dict exists $numerical rank]&&[dict get $numerical rank]>[dict get $numerical free_parameter_count]} {_error "Rank exceeds free parameter count"}
    }
    set parameters [_get $request parameters {}];set ids {};set units {}
    foreach parameter $parameters {
        _keys $parameter {id label value unit role} parameter
        foreach field {id unit role} {if {![dict exists $parameter $field]} {_error "Parameter requires $field"}}
        set id [dict get $parameter id]
        if {$id eq {}||$id in $ids} {_error "Parameter identities must be nonempty and unique"}
        if {[dict get $parameter role] ni {free fixed derived state}} {_error "Unknown parameter role"}
        if {[dict exists $parameter value]&&![_finite [dict get $parameter value]]} {_error "Parameter value is nonfinite"}
        lappend ids $id;lappend units [dict get $parameter unit]
    }
    if {[dict exists $context conditional_parameter_units]} {
        set expectedUnits [_conditionalParameterUnits [dict get $request model_id] $parameters $context]
        _validateConditionalParameterUnits [dict get $context conditional_parameter_units] $expectedUnits $parameters
    }
    if {[dict get $descriptor parameter_convention] eq "named"&&$ids ne [dict get $descriptor parameter_ids]} {_error "Parameter order must match the registered identities"}
    if {[dict exists $numerical free_parameter_count]} {
        set free 0
        foreach parameter $parameters {if {[dict get $parameter role] eq "free"} {incr free}}
        if {[llength $parameters]!=[dict get $numerical p]||$free!=[dict get $numerical free_parameter_count]} {_error "Parameter roles must match the numerical free parameter count"}
    }
    if {[_get $provenance operation {}] in {generalized_least_squares polynomial_gls}&&[_get $context sample_role training] eq "training"&&![dict exists $context gls]} {_error {GLS training result requires its full covariance interpretation}}
    if {[dict exists $context gls]} {_glsRegressionValidate $context $numerical $parameters $provenance $profile}
    if {($geometry eq "implicit_algebraic"||[_get $provenance operation {}] eq "implicit_fit"||[dict get $descriptor id] eq "math.numeric.implicit")&&![dict exists $context implicit]} {_error {Implicit statistics require their captured equation interpretation}}
    if {([_get $provenance operation {}] in {complex_fit complex_residuals}||[dict get $descriptor id] eq "math.numeric.complex_response")&&![dict exists $context complex]} {_error {Complex statistics require their captured covariance interpretation}}
    if {[dict exists $context complex]} {_complexValidate [dict get $descriptor id] $context $numerical $parameters $provenance $profile}
    if {($geometry eq "vertical_response_z_at_exact_xy"||[_get $provenance operation {}] in {surface_fit surface_residuals}||[dict get $descriptor id] eq "math.numeric.surface")&&![dict exists $context surface]} {_error {Surface statistics require their captured coordinate interpretation}}
    if {([_get $provenance operation {}] in {rational_fit rational_residuals}||[dict get $descriptor id] eq "math.numeric.rational")&&![dict exists $context rational]} {_error {Rational statistics require their captured pole-domain interpretation}}
    if {[dict get $descriptor id] in {math.numeric.akima math.numeric.bspline}&&![dict exists $context knot_spline]} {_error {Knot models require their captured interpolation or approximation meaning}}
    if {[dict exists $context knot_spline]} {_knotSplineValidate [dict get $descriptor id] $context $numerical $parameters $provenance $profile}
    if {[dict exists $context rational]} {_rationalValidate [dict get $descriptor id] $context $numerical $parameters $provenance $profile}
    if {[dict exists $context surface]} {_surfaceValidate [dict get $descriptor id] $context $numerical $parameters $provenance $profile}
    if {[dict exists $context implicit]} {_implicitValidate [dict get $descriptor id] $context $numerical $parameters $provenance $profile}
    if {[_get $context constraints unknown] eq "fixed_parameters"&&![dict exists $numerical free_parameter_count]} {_error "Fixed-parameter inference requires the free parameter count"}
    set residual [_residual $profile $context]
    set interpreted {}
    # Bounded resource field projection uses the identical validation/policy
    # path, constructing only requested definitions. Partial results never leave
    # this private helper as standalone public statistical-result records.
    set renderQuantities $quantities
    if {[llength $selectedQuantities]} {
        set renderQuantities {}
        foreach quantity $selectedQuantities {
            if {![dict exists $quantities $quantity]} {_error {Unknown selected statistical quantity}}
            dict set renderQuantities $quantity [dict get $quantities $quantity]
        }
    }
    dict for {quantity metadata} $renderQuantities {
        lassign [_policy $quantity $profile $numerical $context $residual] status reason
        set unit [dict get $metadata unit]
        switch -- $unit {
            coordinate_columns {set unit [dict create column_units [_get $context output_units {}]]}
            covariance_eigen_unit {set unit [_covarianceEigenUnit $context]}
            output_units {set unit [_get $context output_units {}]}
            output_products {set unit [dict create row_units [_get $context output_units {}] column_units [_get $context output_units {}]]}
            selected_output {set unit [expr {[dict exists $context output_index] ? [lindex [_get $context output_units {}] [expr {int([dict get $context output_index])-1}]] : "unspecified"}]}
            psd {set unit [_get $context psd_unit unspecified]}
            band_power {set unit [_get $context power_unit unspecified]}
            predictor - frequency {set unit [_get $context x_unit unspecified]}
            cubic_predictor {set unit [list power [_get $context smoother_predictor_unit [expr {[_get $context orientation y_of_x] eq "r_of_theta"?"unspecified":[_get $context [expr {[_get $context orientation y_of_x] eq "x_of_y"?"y_unit":"x_unit"}] unspecified]}]] 3]}
            spectral_weight {set unit [expr {[_get $context input_semantics {}] eq "amplitude" ? [list power [_get $context y_unit unspecified] 2] : [_get $context y_unit unspecified]}]}
            response {set unit [dict get $residual unit]}
            test_estimate {set unit [expr {[_get $context method {}] in {mann_whitney signed_rank} ? "1" : [dict get $residual unit]}]}
            weighted_response {set unit [expr {[_get $context weight_semantics unweighted] eq "inverse_variance" ? "1" : [dict get $residual unit]}]}
            squared_response {set unit [list power [dict get $residual unit] 2]}
            parameter_units {set unit $units}
            parameter_products {set unit [dict create row_units $units column_units $units]}
            spectral_estimate {set unit [_signalSpectralUnit $context]}
            sequence_product {set unit [expr {[_get $context normalization {}] eq "coefficient" ? "1" : "([_get $context x_unit unspecified])*([_get $context y_unit unspecified])"}]}
            pair_product {set unit "([_get $context x_unit unspecified])*([_get $context y_unit unspecified])"}
            weight {set unit [expr {[_get $context weight_semantics unweighted] eq "inverse_variance" ? [list power [dict get $residual unit] -2] : [_get $context weight_unit "1"]}]}
            weighted_sum {set unit [expr {[_get $context weight_semantics unweighted] eq "inverse_variance" ? [list power [dict get $residual unit] -1] : ([_get $context weight_unit "1"] in {{} 1} ? [dict get $residual unit] : "[dict get $residual unit]*[dict get $context weight_unit]")}]}
        }
        if {[dict exists $context gls]&&$quantity eq "sse"} {set unit [list power 1 2]}
        if {$quantity eq "sse"&&[_get $context weight_semantics unweighted] eq "inverse_variance"} {set unit [list power 1 2]}
        set item [dict create status $status label [dict get $metadata label] unit $unit kind [dict get $metadata kind] reason $reason]
        if {[dict exists $metadata definition]} {dict set item definition [dict get $metadata definition]}
        if {[dict exists $context gls]} {
            if {$quantity eq "dof"} {dict set item definition {Positive observation-covariance rank minus stochastic coefficient directions after exact null-mode constraints}}
            if {$quantity eq "sse"} {dict set item definition {Squared norm of covariance-whitened observed-minus-fitted response; full covariance structure and scale are explicit}}
            if {$quantity in {covariance standard_errors}} {dict set item definition [dict get $context gls quantities $quantity definition]}
        }
        if {[dict exists $context complex]} {set item [_complexQuantity $quantity $item]}
        if {[dict exists $context implicit]} {set item [_implicitQuantity $quantity $item $context]}
        if {$geometry eq "orthogonal_xy"} {
            switch -- $quantity {
                sse {dict set item definition {Sum over observation pairs of (delta_X/sigma_X)^2 + (delta_Y/sigma_Y)^2 at the fitted latent coordinates}}
                dof {dict set item definition {Two residual components per observation pair minus one fitted latent coordinate per pair minus the identifiable free model-parameter rank}}
                weighted_residual_standard_deviation {dict set item label {Normalized XY residual scale};dict set item definition {Square root of normalized XY objective divided by residual degrees of freedom; absolute-sigma covariance is not multiplied by this scale}}
                covariance - standard_errors {dict set item definition {Local Gauss-Newton parameter uncertainty after eliminating independent latent-coordinate tangents; conditional on supplied absolute axis uncertainties and the fitted model}}
            }
        }
        if {$profile eq "signal_spectral"&&$quantity in {spectral_estimate_real spectral_estimate_imaginary}} {dict set item definition [_signalSpectralDefinition [dict get $context spectral_operation] $quantity]}
        if {$profile in {regression nonlinear_regression}&&$geometry ne "orthogonal_xy"&&[_get $context weight_semantics unweighted] ne "unweighted"&&$quantity eq "r_squared"} {
            dict set item definition {Weighted centred response comparison: one minus weighted residual sum of squares divided by weighted response variation around its weighted mean; a descriptive fit criterion, not evidence that the physical model is valid}
        }
        if {$profile eq "geometric_comparison"} {
            foreach {key label} {n {Scientific comparison locations} rmse {Root mean squared distance} mae {Mean absolute distance} max_abs_error {Maximum sampled distance}} {if {$quantity eq $key} {dict set item label $label}}
        }
        if {$profile eq "hypothesis"&&(($quantity eq "ci_lower"&&[_get $context alternative {}] eq "less")||($quantity eq "ci_upper"&&[_get $context alternative {}] eq "greater"))} {
            # Endpoint convention is shared even when this row has no valid CI.
            dict set item endpoint unbounded
        }
        if {$profile eq "pca"&&[_get $context method {}] eq "uncentered_second_moment_n_minus_one"} {
            if {$quantity eq "component_variance"} {dict set item label {Uncentered component squared magnitude / (n - 1)}}
            if {$quantity eq "explained_ratio"} {dict set item label {Uncentered spectral proportion}}
            if {$quantity eq "cumulative_ratio"} {dict set item label {Cumulative uncentered spectral proportion}}
        }
        if {$quantity in {singular_value component_variance explained_ratio cumulative_ratio component_index}&&$profile eq "pca"} {dict set item definition [dict get $context method]}
        if {$profile eq "summary"&&[_get $context weight_semantics unweighted] ne "unweighted"} {
            if {$quantity in {mean median quartile_1 quartile_3 interquartile_range root_mean_square variance_population standard_deviation_population quantiles}} {dict set item label "Weighted [string tolower [dict get $item label]]"}
            if {$quantity in {variance standard_deviation}} {dict set item label "Reliability-weight-corrected [string tolower [dict get $item label]]"}
        }
        if {$profile eq "summary"&&$quantity in {median quartile_1 quartile_3 interquartile_range}&&[_get $context quantile_definition {}] ne {}} {dict set item definition [dict get $context quantile_definition]}
        if {$quantity eq "median_absolute_deviation"} {dict set item scale [_get $context mad_scale raw]}
        if {$quantity eq "correlation"&&[_get $context method {}] in {pearson spearman}} {dict set item label "[string totitle [dict get $context method]] correlation coefficient"}
        if {$status eq "value"} {
            if {![dict exists $numerical $quantity]} {dict set item status unavailable;dict set item reason {The numerical provider did not supply this quantity}} else {
                set value [dict get $numerical $quantity];set flat $value
                if {[dict get $metadata kind] eq "scalar"} {set flat [list $value]}
                if {[dict get $metadata kind] eq "matrix"} {
                    set dimension [expr {$quantity in {output_covariance sample_covariance_real sample_covariance_imaginary} ? [llength [_get $context output_ids {}]] : [llength $ids]}]
                    set columnDimension $dimension
                    if {$quantity eq "cluster_centers"} {set dimension [llength [_get $context cluster_ids {}]];set columnDimension [llength [_get $context output_ids {}]]}
                    set flat {};if {[llength $value]!=$dimension} {_error "Covariance row count differs from parameter identity count"}
                    foreach row $value {if {[llength $row]!=$columnDimension} {_error "Covariance column count differs from parameter identity count"};lappend flat {*}$row}
                }
                if {[dict get $metadata kind] eq "vector"} {
                    set expected [expr {$quantity eq "quantiles" ? [llength [_get $numerical quantile_probabilities {}]] : ($quantity in {output_standard_uncertainties sample_covariance_eigenvalues_real sample_covariance_eigenvalues_imaginary} ? [llength [_get $context output_ids {}]] : [llength $ids])}]
                    if {$quantity in {cluster_populations cluster_within_ss}} {set expected [llength [_get $context cluster_ids {}]]}
                    if {$quantity in {foundation_coefficients foundation_coefficient_real foundation_coefficient_imaginary}} {set expected [llength [_get $context output_ids {}]]}
                    if {$quantity eq "signal_harmonic_bin_powers"} {set expected [llength [_get $numerical harmonic_orders {}]]}
                    if {[llength $value]!=$expected} {_error "Vector differs from its identity or probability count"}
                }
                set finite 1;foreach number $flat {if {![_finite $number]} {set finite 0;break}}
                if {!$finite&&$profile eq "hypothesis"&&$quantity in {ci_lower ci_upper}&&[llength $flat]==1} {
                    set alternative [_get $context alternative {}]
                    if {($quantity eq "ci_lower"&&$alternative eq "less"&&[_infinite $value -1])||($quantity eq "ci_upper"&&$alternative eq "greater"&&[_infinite $value 1])} {
                        set finite 1;dict set item endpoint unbounded
                    }
                }
                if {!$finite} {dict set item status undefined;dict set item reason {Numeric returned a nonfinite quantity}} else {dict set item value $value}
                if {$finite&&$quantity in {absolute_maximum rmse mae max_abs_error sampled_hausdorff_distance max_relative_error rms_relative_error relative_n residual_standard_deviation weighted_residual_standard_deviation sse singular_value component_variance explained_ratio cumulative_ratio standard_errors output_standard_uncertainties standard_uncertainty variance standard_deviation raw_median_absolute_deviation median_absolute_deviation range interquartile_range root_mean_square variance_population standard_deviation_population standard_error_mean measurement_standard_error_mean effective_n sum_weights test_standard_error test_standard_deviation interval_margin test_degrees_of_freedom n_first n_second ss_between ss_within ss_total ms_between ms_within f_statistic f_numerator_df f_denominator_df group_count df_between df_within bootstrap_standard_error replicates extreme_count}} {
                    foreach number $flat {if {$number<0} {dict unset item value;dict set item status error;dict set item reason {Numeric returned a negative quantity whose contract requires nonnegative values};break}}
                }
                if {$finite&&$quantity in {explained_ratio cumulative_ratio}&&$value>1+4*2.2204460492503131e-16} {dict unset item value;dict set item status error;dict set item reason {Numeric returned a spectral proportion above one}}
                if {$finite&&$quantity eq "p_value"&&($value<0||$value>1)} {dict unset item value;dict set item status error;dict set item reason {Numeric returned a p-value outside zero to one}}
                if {$finite&&$quantity in {covariance output_covariance}} {
                    for {set i 0} {$i<[llength $value]} {incr i} {
                        if {[lindex $value $i $i]<0} {dict unset item value;dict set item status error;dict set item reason {Numeric returned a negative parameter variance};break}
                    }
                }
            }
        }
        if {$quantity eq "r_squared"} {dict set item convention centered_observed_response;dict set item interpretation descriptive_not_a_goodness_of_fit_test}
        if {$quantity eq "centered_comparison_score"} {dict set item convention one_minus_prediction_sse_over_centered_reference_sst;dict set item interpretation descriptive_prediction_score_no_fitting_or_independence_claim}
        if {$quantity in {relative_n max_relative_error rms_relative_error}} {dict set item convention absolute_error_divided_by_absolute_nonzero_reference_at_or_above_recorded_floor}
        if {$quantity eq "geometric_dispersion_score"} {dict set item convention one_minus_projection_sse_over_total_xy_dispersion}
        if {$quantity in {covariance standard_errors}} {dict set item parameter_ids $ids;dict set item coefficient_space [_get $context coefficient_space original_physical];dict set item scaling [_get $context covariance_scaling unspecified]}
        if {$quantity eq "cluster_centers"} {dict set item row_ids [_get $context cluster_ids {}];dict set item column_ids [_get $context output_ids {}]}
        if {$quantity in {foundation_coefficients foundation_coefficient_real foundation_coefficient_imaginary}} {dict set item output_ids [_get $context output_ids {}]}
        if {$quantity in {cluster_populations cluster_within_ss}} {dict set item element_ids [_get $context cluster_ids {}]}
        if {$quantity in {sample_covariance_real sample_covariance_imaginary}} {dict set item output_ids [_get $context output_ids {}]}
        if {$quantity in {sample_covariance_eigenvalues_real sample_covariance_eigenvalues_imaginary}} {dict set item element_ids [expr {$profile eq "covariance_diagnostics" ? [_covarianceEigenIds $context] : {}}]}
        if {$quantity in {output_covariance output_standard_uncertainties standard_uncertainty}} {dict set item output_ids [_get $context output_ids {}];if {[dict exists $context output_index]} {dict set item output_index [dict get $context output_index]}}
        if {$quantity eq "signal_harmonic_bin_powers"} {dict set item element_ids [_get $numerical harmonic_orders {}]}
        if {$quantity eq "quantiles"} {dict set item probabilities [_get $numerical quantile_probabilities {}];dict set item estimator [_get $context quantile_definition unspecified]}
        if {$profile eq "resampling"&&$quantity eq "test_estimate"} {dict set item label {Observed statistic}}
        if {$profile eq "resampling"&&$quantity in {ci_lower ci_upper}} {dict set item estimator percentile;dict set item approximation empirical_bootstrap}
        if {$quantity eq "p_value"} {dict set item interpretation probability_under_null_not_probability_of_null;dict set item method [_get $context approximation unspecified]}
        if {$quantity eq "interval_margin"} {dict set item convention [expr {[_get $context alternative {}] eq "two_sided" ? "symmetric_half_width" : "finite_one_sided_margin"}]}
        if {$quantity in {ci_lower ci_upper}} {dict set item confidence [_get $context confidence {}];dict set item alternative [_get $context alternative {}]}
        if {$quantity eq "effect_size"} {dict set item estimator [_get $context effect_name unspecified]}
        dict set interpreted $quantity $item
    }
    set solver [dict create status unavailable reason {Numerical provider did not report convergence} method [_get $context solver unspecified]]
    if {[dict exists $numerical converged]} {set solver [dict create status value converged [dict get $numerical converged] method [_get $context solver unspecified] reason {}]}
    if {[dict exists $request solver_receipt]} {set solver [_solverReceipt [dict get $request solver_receipt] $parameters $numerical $context]}
    set result [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.statistical_result.v1 \
        model $descriptor residual $residual parameters $parameters quantities $interpreted solver $solver \
        context $context provenance $provenance assumptions [_get $context assumptions {}] request $request]
    if {[dict exists $request parameter_uncertainty]} {
        dict set result parameter_uncertainty [_interpretUncertainty $result [dict get $request parameter_uncertainty]]
    }
    return $result
}
proc ::GX::StatisticsV1::validate {result} {
    if {[_get $result schema {}] eq "gxtxt.fit_profile_interpretation.v1"} {return [_profileValidate $result]}
    if {[_get $result schema {}] eq "gxtxt.digitization_interpretation.v1"} {_digitizationValidated $result;return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]}
    if {[_get $result api_id {}] ne "STATISTICAL_RESULT_SEMANTICS_API_v1"||[_get $result api_version {}] ne "1"} {_error "Unversioned or nonpublic statistical result"}
    if {[_get $result schema {}] eq "gxtxt.residual_sequence_interpretation.v1"} {return [_sequenceValidate $result]}
    if {[_get $result schema {}] eq "gxtxt.gls_interpretation.v1"} {return [_glsValidate $result]}
    if {[_get $result schema {}] eq "gxtxt.fit_suggestions.v1"} {return [_suggestionValidate $result]}
    if {[_get $result schema {}] eq "gxtxt.physical_plausibility_review.v1"} {return [_physicalValidate $result]}
    if {[_get $result schema {}] eq "gxtxt.derived_properties.v1"} {return [_derivedValidate $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.resource_binding.v1"} {return [_validateResourceBinding $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.column_binding.v1"} {return [_validateColumnBinding $result]}
    if {[_get $result schema {}] eq "gxtxt.nested_f_interpretation.v1"} {set r [dict get $result request];set expected [nestedFInterpretation [dict get $r reduced] [dict get $r full] [dict get $r numeric]]} elseif {[_get $result schema {}] eq "gxtxt.regression_bootstrap_interpretation.v1"} {set expected [_bootstrapReinterpret [dict get $result request]]} elseif {[_get $result schema {}] eq "gxtxt.regression_influence_interpretation.v1"} {set expected [_influenceReinterpret [dict get $result request]]} elseif {[_get $result schema {}] eq "gxtxt.log_response_interpretation.v1"} {set expected [_logResponseReinterpret [dict get $result request]]} elseif {[_get $result schema {}] eq "gxtxt.model_comparison.v1"} {set expected [modelComparison [dict get $result request entries] [dict get $result request criterion]]} elseif {[_get $result schema {}] eq "gxtxt.statistical_result.table.v1"} {set expected [interpretTable [dict get $result request]]} else {
        set expected [interpret [dict get $result request]]
    }
    foreach key [dict keys $expected] {
        if {$key eq "quantities"&&[_get $result schema {}] eq "gxtxt.statistical_result.v1"&&[dict exists $result quantities]} {
            # Preserve complete known v1 catalogues when all later additions
            # are inapplicable to the captured request. Never fill in missing
            # facts or accept an arbitrary partial catalogue.
            set additive {smoothing_lambda smoothing_gcv_score residual_mean_dof residual_variance_dof smoother_trace_squared}
            set originalCatalogue {n rank edf dof rmse mae max_abs_error centered_comparison_score relative_n max_relative_error rms_relative_error residual_standard_deviation weighted_residual_standard_deviation sse r_squared adjusted_r_squared geometric_dispersion_score reduced_chi_squared covariance standard_errors condition_number mean minimum maximum range sum median raw_median_absolute_deviation median_absolute_deviation quartile_1 quartile_3 interquartile_range root_mean_square variance_population standard_deviation_population standard_error_mean measurement_standard_error_mean effective_n sum_weights weighted_sum singular_value component_variance explained_ratio cumulative_ratio component_index output_covariance output_standard_uncertainties standard_uncertainty quantiles standard_deviation variance covariance_sample covariance_population correlation test_statistic test_degrees_of_freedom n_first n_second p_value test_estimate null_value test_standard_error test_standard_deviation interval_margin ci_lower ci_upper effect_size group_count grand_mean ss_between ss_within ss_total df_between df_within ms_between ms_within f_statistic f_numerator_df f_denominator_df eta_squared omega_squared replicates extreme_count bootstrap_standard_error}
            set missing {};dict for {quantity item} [dict get $expected quantities] {
                if {![dict exists $result quantities $quantity]} {lappend missing $quantity}
            }
            if {[lsort [dict keys [dict get $result quantities]]] eq [lsort $originalCatalogue]} {set additive $missing}
            if {[lsort $missing] eq [lsort $additive]} {
                set compatible 1
                foreach quantity $additive {
                    if {[dict get $expected quantities $quantity status] ne "not_applicable"||[dict exists $result request numerical $quantity]} {set compatible 0}
                }
                if {$compatible} {foreach quantity $additive {dict unset expected quantities $quantity}}
            }
        }
        if {[_get $result schema {}] eq "gxtxt.regression_bootstrap_interpretation.v1"&&$key in {plan parameters covariance}} {
            if {![dict exists $result $key]} {_error "Bootstrap result lacks $key"}
            _bootstrapCompare $key [dict get $expected $key] [dict get $result $key]
            continue
        }
        if {$key eq "columns"&&[dict exists $result columns]&&[dict get $result columns] ne [dict get $expected columns]} {
            dict for {quantity column} [dict get $expected columns] {
                if {![dict exists $result columns $quantity]} {_error "Statistical table lacks column '$quantity'"}
                dict for {field value} $column {
                    if {![dict exists $result columns $quantity $field]||[dict get $result columns $quantity $field] ne $value} {_error "Statistical table column '$quantity' field '$field' bypasses CORE interpretation"}
                }
            }
        }
        if {![dict exists $result $key]||[dict get $result $key] ne [dict get $expected $key]} {_error "Statistical result field '$key' bypasses the CORE interpretation"}
    }
    if {[lsort [dict keys $result]] ne [lsort [dict keys $expected]]} {_error "Statistical result has unvalidated fields"}
    return [dict create valid 1 api_id STATISTICAL_RESULT_SEMANTICS_API_v1]
}
proc ::GX::StatisticsV1::validatedResult {result} {validate $result;return $result}
proc ::GX::StatisticsV1::fromNativeComparison {method receipt context provenance} {
    # The native kernel reduces deviations through Numeric's public C binding.
    # Preserve its existing facts; never derive estimates from display/LOD rows.
    if {$method ni {x path geometry surface}} {_error {Unknown native comparison method}}
    _keys $context {x_unit y_unit z_unit x_variable_id y_variable_id} {native coordinate context}
    foreach field {x_unit y_unit} {if {![dict exists $context $field]} {_error "Native comparison requires $field (empty means undeclared)"}}
    set facts {}
    set mapping {count count rmse rmse mean_absolute mean_absolute max_absolute max_absolute}
    if {$method eq "surface"} {set mapping {reference_samples count reference_rms rmse reference_mean mean_absolute reference_max max_absolute};if {![dict exists $context z_unit]} {_error {Surface comparison requires z_unit}}}
    foreach {source target} $mapping {
        if {![dict exists $receipt $source]} {_error "Native reduction receipt requires $source"}
        dict set facts $target [dict get $receipt $source]
    }
    dict set context sample_role evaluation
    dict set context assumptions {{Descriptive comparison of captured coordinates; no fitted-parameter or sampling-inference claim}}
    dict set provenance native_api [expr {$method eq "surface" ? "NATIVE_3D_GEOMETRY_API_v1" : "NATIVE_2D_GEOMETRY_API_v1"}]
    dict set provenance reduction_binding gxtxt_numeric_reductions_v1.h
    dict set provenance method $method
    if {$method eq "x"} {
        set model math.numeric.comparison
        dict set context orientation y_of_x;dict set context residual_sign observed_minus_predicted
        dict set context comparison_metric vertical_at_reference_x
    } else {
        set model math.numeric.geometric_deviation
        dict set context orientation parametric;dict set context comparison_direction reference_to_target
        dict set context comparison_metric [dict get {path euclidean_at_normalized_path geometry nearest_curve_distance surface nearest_surface_distance} $method]
        if {$method eq "path"} {dict set context zero_normal_sign_policy nonnegative_when_tangent_cross_product_is_zero}
    }
    if {$method eq "geometry"} {
        foreach field {count_a count_b sample_budget sampling_a sampling_b projection_exact_a projection_exact_b policy} {
            if {![dict exists $receipt $field]} {_error "Native geometry receipt requires $field"}
            dict set provenance $field [dict get $receipt $field]
        }
        foreach field {count_a count_b sample_budget} {if {![string is integer -strict [dict get $receipt $field]]||[dict get $receipt $field]<1} {_error {Invalid native scientific sampling count}}}
        if {[dict get $receipt count_a]!=[dict get $receipt count]||[dict get $receipt count_a]>[dict get $receipt sample_budget]||[dict get $receipt count_b]>[dict get $receipt sample_budget]} {_error {Native scientific count disagrees with its sampling budget}}
        dict lappend context assumptions {Distances and Hausdorff maxima apply to recorded scientific samples, not the continuous source curves; display zoom does not choose this sample}
    } elseif {$method eq "surface"} {
        foreach field {reference_vertices target_vertices reference_samples target_samples reference_tessellated target_tessellated sampling_policy projection_policy extrema_policy tessellation} {
            if {![dict exists $receipt $field]} {_error "Native surface receipt requires $field"}
            dict set provenance $field [dict get $receipt $field]
        }
        foreach side {reference target} {
            foreach kind {vertices samples} {set value [dict get $receipt ${side}_$kind];if {![string is integer -strict $value]||$value<1} {_error {Invalid native surface sampling count}}}
            if {[dict get $receipt ${side}_samples]>[dict get $receipt ${side}_vertices]||[dict get $receipt ${side}_samples]>[dict get $receipt tessellation sample_budget]} {_error {Native surface sample count exceeds its source or budget}}
        }
        dict lappend context assumptions {Deterministic sampled vertices are projected to complete target triangles; sampled Hausdorff bounds do not establish continuous-surface extrema and B-Rep comparisons depend on recorded tessellation}
    } else {
        dict set provenance sampling_policy all_eligible_reference_vertices_independent_of_display_lod
        foreach field {display_rows display_is_scientific_data max_source_index} {if {[dict exists $receipt $field]} {dict set provenance $field [dict get $receipt $field]}}
        if {[dict exists $receipt display_is_scientific_data]&&[dict get $receipt display_is_scientific_data]} {_error {Native comparison cannot substitute display rows for scientific observations}}
    }
    set results [dict create reference [fromNumeric $model residual_summary $facts $context {} $provenance]]
    if {$method in {geometry surface}} {
        # Combining counts labels the existing pooled reduction; it computes no
        # RMS, maximum or other numerical statistic a second time.
        if {$method eq "surface"} {set count [expr {[dict get $receipt reference_samples]+[dict get $receipt target_samples]}];set rms [dict get $receipt symmetric_rms]} else {set count [expr {[dict get $receipt count_a]+[dict get $receipt count_b]}];set rms [dict get $receipt symmetric_rmse]}
        set pooled [dict create count $count rmse $rms hausdorff_sampled [dict get $receipt hausdorff_sampled]]
        dict set context comparison_direction bidirectional_pooled
        dict set results bidirectional [fromNumeric $model residual_summary $pooled $context {} $provenance]
    }
    return $results
}
proc ::GX::StatisticsV1::report {result {requested {n rmse r_squared dof standard_errors reduced_chi_squared}}} {
    if {[_get $result schema {}] eq "gxtxt.fit_profile_interpretation.v1"} {return [profileReport $result]}
    if {[_get $result schema {}] eq "gxtxt.digitization_interpretation.v1"} {return [digitizationReport $result]}
    if {[_get $result schema {}] eq "gxtxt.gls_interpretation.v1"} {return [glsReport $result]}
    if {[_get $result schema {}] eq "gxtxt.fit_suggestions.v1"} {return [fitSuggestionsReport $result]}
    if {[_get $result schema {}] eq "gxtxt.physical_plausibility_review.v1"} {return [physicalPlausibilityReport $result]}
    if {[_get $result schema {}] eq "gxtxt.derived_properties.v1"} {validate $result;return [derivedPropertiesReport [dict get $result request source] [dict get $result request numeric]]}
    if {[_get $result schema {}] eq "gxtxt.residual_sequence_interpretation.v1"} {return [_sequenceReport $result]}
    if {[_get $result schema {}] eq "gxtxt.regression_bootstrap_interpretation.v1"} {return [_bootstrapReport $result]}
    if {[_get $result schema {}] eq "gxtxt.regression_influence_interpretation.v1"} {return [_influenceReport $result]}
    if {[_get $result schema {}] eq "gxtxt.log_response_interpretation.v1"} {return [_logResponseReport $result]}
    if {[_get $result schema {}] eq "gxtxt.nested_f_interpretation.v1"} {return [_nestedFReport $result]}
    if {[_get $result schema {}] eq "gxtxt.model_comparison.v1"} {return [_modelComparisonReport $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.resource_binding.v1"} {return [resourceBindingReport $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.column_binding.v1"} {return [bindingReport $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.table.v1"} {return [tableReport $result {} $requested]}
    validate $result
    set lines {}
    foreach key $requested {
        if {![dict exists $result quantities $key]} {_error "Unknown report quantity '$key'"}
        set item [dict get $result quantities $key]
        set unit [dict get $item unit]
        if {[llength $unit]==3&&[lindex $unit 0] eq "power"} {set unit "[lindex $unit 1]^[lindex $unit 2]"}
        if {[dict get $item status] eq "value"} {
            set display [dict get $item value]
            if {[dict get $item kind] eq "scalar"} {set display [format %.9g $display]}
            lappend lines "[dict get $item label]: $display ($unit)"
        } else {lappend lines "[dict get $item label]: [dict get $item status] — [dict get $item reason]"}
    }
    if {[dict get $result model profile] in {prediction_uncertainty foundation_regression clustering covariance_diagnostics survival foundation_correlation multiplicity spectral_distribution power_level welch_spectrum local_cloud replicate_profile signal_summary signal_snr signal_spectrum_quality fft_spectrum_quality harmonic_peak_quality harmonic_components event_timing signal_correlation window_metrics signal_spectral}} {
        foreach key $requested {if {[dict exists $result quantities $key definition]} {lappend lines "[dict get $result quantities $key label] definition: [dict get $result quantities $key definition]"}}
        foreach assumption [dict get $result context assumptions] {lappend lines $assumption}
    }
    if {[dict exists $result context complex]} {foreach assumption [_complexAssumptions [dict get $result context complex operation]] {lappend lines $assumption}}
    if {[dict exists $result context implicit]} {foreach assumption [_implicitAssumptions] {lappend lines $assumption}}
    if {[dict exists $result context rational]} {foreach assumption [_rationalAssumptions [dict get $result context rational operation]] {lappend lines $assumption}}
    if {[dict exists $result context knot_spline]} {foreach assumption [_knotSplineAssumptions [dict get $result context knot_spline model]] {lappend lines $assumption}}
    if {[dict exists $result context surface]} {foreach assumption [_surfaceAssumptions [dict get $result context surface operation]] {lappend lines $assumption}}
    if {[dict exists $result context regional_fit]} {foreach assumption [_regionalFitAssumptions] {lappend lines $assumption}}
    if {[dict exists $result context smoothing]} {foreach assumption [_smoothingAssumptions] {lappend lines $assumption}}
    if {[dict exists $result context baseline_correction]} {foreach assumption [_baselineAssumptions] {lappend lines $assumption}}
    if {[dict exists $result context response_transform]} {foreach assumption [_logResponseContextAssumptions [dict get $result context]] {lappend lines $assumption}}
    if {[dict exists $result provenance smoothing]} {
        foreach key $requested {if {[dict exists $result quantities $key definition]} {lappend lines "[dict get $result quantities $key label] definition: [dict get $result quantities $key definition]"}}
        foreach assumption [_smoothingAssumptions] {lappend lines $assumption}
    }
    return [join $lines \n]
}
proc ::GX::StatisticsV1::scalarValue {result quantity} {
    # Numeric table compatibility only. Persist the full result alongside this
    # value so that NaN never loses its explicit applicability/status/reason.
    validate $result
    set item [dict get $result quantities $quantity]
    if {[dict get $item kind] ne "scalar"} {_error "scalarValue requires a scalar quantity"}
    if {[dict get $item status] eq "value"} {return [dict get $item value]}
    return NaN
}
proc ::GX::StatisticsV1::iniReport {result mapping} {
    validate $result
    set lines {}
    dict for {field quantity} $mapping {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $field]} {_error "INI statistical field alias must be an identifier"}
        if {![dict exists $result quantities $quantity]} {_error "Unknown statistical quantity '$quantity'"}
        set item [dict get $result quantities $quantity]
        if {[dict get $item kind] ne "scalar"} {_error "INI scalar reports cannot flatten parameter matrices or vectors"}
        set value NaN
        if {[dict get $item status] eq "value"} {set value [format %.17g [dict get $item value]]}
        lappend lines "$field=$value" "$field.statistical_status=[dict get $item status]"
        lappend lines "$field.statistical_quantity=$quantity"
        foreach key {label reason unit} {
            set text [string map [list \\ \\\\ \r {\r} \n {\n}] [dict get $item $key]]
            lappend lines "$field.statistical_$key=$text"
        }
    }
    return [join $lines \n]
}
proc ::GX::StatisticsV1::scalarRows {result mapping} {
    validate $result
    set rows {}
    dict for {id quantity} $mapping {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $id]||![dict exists $result quantities $quantity]} {_error {Scalar row aliases and quantities must be valid identifiers}}
        set item [dict get $result quantities $quantity]
        if {[dict get $item kind] ne "scalar"} {_error {Scalar rows cannot flatten vector or matrix identities}}
        set unit [dict get $item unit];set display $unit
        if {$unit in {count dimensionless}} {set display 1} elseif {[llength $unit]==3&&[lindex $unit 0] eq "power"} {set display "[lindex $unit 1]^[lindex $unit 2]"}
        set value NaN;if {[dict get $item status] eq "value"} {set value [dict get $item value]}
        lappend rows [dict merge $item [dict create id $id quantity $quantity value $value unit_text $display]]
    }
    return $rows
}
proc ::GX::StatisticsV1::parameterIniReport {result} {
    # Preserve legacy numeric vector keys together with mandatory identities,
    # units and per-parameter states. No vector can lose its scientific order.
    set rows [parameterRows $result]
    set ids {};set units {};set estimates {};set errors {};set states {};set reasons {}
    foreach row $rows {
        lappend ids [dict get $row id];lappend units [dict get $row unit]
        set value NaN;if {[dict get $row value_status] eq "value"} {set value [format %.17g [dict get $row value]]}
        lappend estimates $value
        set value NaN;if {[dict get $row se_status] eq "value"} {set value [format %.17g [dict get $row standard_error]]}
        lappend errors $value;lappend states [dict get $row se_status];lappend reasons [dict get $row se_reason]
    }
    set item [dict get $result quantities standard_errors]
    set fields [dict create coefficients [join $estimates {;}] standard_errors [join $errors {;}] \
        parameter_ids $ids parameter_units $units coefficient_space [_get [dict get $result context] coefficient_space original_physical] \
        standard_errors.statistical_quantity standard_errors standard_errors.statistical_status [dict get $item status] \
        standard_errors.statistical_reason [dict get $item reason] standard_errors.parameter_statuses $states standard_errors.parameter_reasons $reasons]
    set lines {}
    dict for {key value} $fields {
        lappend lines "$key=[string map [list \\ \\\\ \r {\r} \n {\n}] $value]"
    }
    return [join $lines \n]
}
proc ::GX::StatisticsV1::_conditionalParameterUnits {modelId parameters context} {
    if {$modelId ne "math.numeric.power_law"||[llength $parameters]!=2||[dict get [lindex $parameters 0] id] ne "scale"||[dict get [lindex $parameters 1] id] ne "exponent"} {_error {Conditional power units require the registered scale/exponent model}}
    set independent [_get $context x_unit {}];set response [_get $context y_unit {}]
    if {[_get $context orientation y_of_x] eq "x_of_y"} {set independent [_get $context y_unit {}];set response [_get $context x_unit {}]}
    if {[_get $context orientation y_of_x] eq "r_of_theta"} {set independent rad;set response [_get $context radial_unit {}]}
    set exponent [lindex $parameters 1]
    set receipt [dict create schema gxtxt.conditional_parameter_units.v1 model_id $modelId parameter_id scale exponent_id exponent \
        predictor_unit $independent response_unit $response unit_expression unspecified status unavailable \
        exponent_status unavailable exponent_role [dict get $exponent role] \
        covariance_basis fixed_coordinate_unit_basis reference_magnitude 1 \
        reason {Explicit multiplicative predictor and response units are required; no conditional physical unit is invented}]
    if {[dict exists $exponent value]} {dict set receipt exponent_status value;dict set receipt exponent_value [expr {double([dict get $exponent value])}]}
    if {$independent eq {}||$response eq {}} {return $receipt}
    # Intrinsic Unit Registry parsing is bounded and performs no observation or
    # statistical computation. Semantic/affine/opaque units need conversion.
    if {[catch {::GX::unitRegistryIntrinsicScale $independent;::GX::unitRegistryIntrinsicScale $response}]} {return $receipt}
    if {[::GX::unitTclDimensionKey $independent] eq [::GX::unitTclDimensionKey 1]} {
        dict set receipt status value;dict set receipt unit_expression $response
        dict set receipt reason {The predictor is dimensionless; the coefficient has the response unit in the fixed coordinate-unit basis}
    } else {
        dict set receipt status conditional;dict set receipt unit_expression "($response)/($independent)^exponent"
        dict set receipt reason {The coefficient unit depends on the exponent. Estimates, covariance and intervals refer to the fixed coordinate-unit basis; changing that basis requires a joint parameter transformation, including exponent correlation}
    }
    return $receipt
}
proc ::GX::StatisticsV1::_validateConditionalParameterUnits {actual expected parameters} {
    if {[lsort [dict keys $actual]] ne [lsort [dict keys $expected]]} {_error {Conditional parameter-unit receipt fields changed}}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key in {exponent_value reference_magnitude}} {
            if {![_finite $other]||$other!=$value} {_error "Conditional parameter-unit receipt changed $key"}
        } elseif {$other ne $value} {_error "Conditional parameter-unit receipt changed $key"}
    }
    if {[dict get [lindex $parameters 0] unit] ne [dict get $expected unit_expression]||[dict get [lindex $parameters 1] unit] ne "1"} {_error {Conditional parameter-unit receipt conflicts with parameter units}}
}
proc ::GX::StatisticsV1::fromNumeric {modelId operation raw context {metrics {}} {provenance {}}} {
    # One public adaptation boundary for the existing Numeric result contracts.
    # Field selection and identity mapping do not compute statistical estimates.
    set sourceOperation $operation;set operation [_numericOperationBase $operation]
    if {$sourceOperation ne $operation} {
        set unitFields {unit y_unit}
        set variableFields {variable_id weight_variable_id}
        set requiredVariables {variable_id}
        if {$operation in {polynomial_fit nonlinear_fit}} {set unitFields {x_unit x_unit y_unit y_unit};set variableFields {x_variable_id y_variable_id weight_variable_id};set requiredVariables {x_variable_id y_variable_id}}
        if {$operation eq "nonlinear_fit"&&([dict exists $raw sigma_x_variable_id]||[dict exists $raw sigma_variable_id])} {
            if {[_get $raw fit_geometry {}] ne "orthogonal_xy"||[_get $raw sigma_x_unit {}] eq {}||[_get $raw sigma_unit {}] eq {}||[_get $raw sigma_x_unit {}] ne [_get $raw x_unit {}]||[_get $raw sigma_unit {}] ne [_get $raw y_unit {}]||[_get $raw row_identity {}] ne "original_dataset_one_based_uint64"} {_error {Dataset XY sigma bindings require matching physical units and original-row identities}}
            lappend variableFields sigma_x_variable_id sigma_variable_id
            lappend requiredVariables sigma_x_variable_id sigma_variable_id
        }
        if {$operation eq "weighted_statistics"} {lappend unitFields weight_unit weight_unit;lappend requiredVariables weight_variable_id}
        foreach field $requiredVariables {if {[_get $raw $field {}] eq {}} {_error "Dataset statistical receipt requires its canonical '$field'"}}
        foreach {source target} $unitFields {
            if {![dict exists $raw $source]} {_error "Dataset statistical receipt requires its recorded '$source'"}
            set value [dict get $raw $source]
            if {[dict exists $context $target]&&[dict get $context $target] ne $value} {_error "Statistical context '$target' conflicts with the numerical Dataset receipt; convert measurements explicitly"}
            dict set context $target $value
        }
        if {[_get $raw dataset_id {}] eq {}} {_error {Dataset statistical receipt requires its canonical Dataset identity}}
        set sources {}
        foreach field $variableFields {
            if {[_get $raw $field {}] ne {}} {lappend sources [dict create dataset_id [dict get $raw dataset_id] variable_id [dict get $raw $field]]}
        }
        if {![llength $sources]} {_error {Dataset statistical receipt requires its canonical Variable identity}}
        if {[dict exists $provenance source_variables]&&[dict get $provenance source_variables] ne $sources} {_error {Statistical provenance conflicts with recorded Dataset variables}}
        dict set provenance source_variables $sources
        dict set provenance selection_id [_get $raw selection_id {}]
        set binding [dict create dataset_id [dict get $raw dataset_id] selection_id [_get $raw selection_id {}]]
        foreach field [concat $variableFields {unit weight_unit x_unit y_unit sigma_x_unit sigma_unit row_identity}] {if {[dict exists $raw $field]} {dict set binding $field [dict get $raw $field]}}
        dict set provenance dataset_binding $binding
    }
    set descriptor [model $modelId];set profile [dict get $descriptor profile]
    if {[dict exists $raw knot_summary]} {
        if {$operation ne "curve_model_fit"||$modelId ne "math.numeric.[dict get $raw knot_summary model]"} {_error {Knot facts cannot bypass their registered interpretation}}
        set context [_knotSplineContext [dict get $raw knot_summary] $context]
    }

    if {$operation in {rational_fit rational_residuals}&&$modelId ne "math.numeric.rational"} {_error {Rational facts require their registered model}}
    if {[dict exists $raw rational_summary]&&$operation ni {rational_fit rational_residuals}} {_error {Rational facts cannot bypass their pole-domain interpretation}}
    if {$operation in {rational_fit rational_residuals}} {set context [_rationalContext [dict get $raw rational_summary] $context]}
    if {$operation in {surface_fit surface_residuals}&&$modelId ne "math.numeric.surface"} {_error {Surface facts require their registered model}}
    if {[dict exists $raw surface_summary]&&$operation ni {surface_fit surface_residuals}} {_error {Surface facts cannot bypass their coordinate interpretation}}
    if {$operation in {surface_fit surface_residuals}} {set context [_surfaceContext [dict get $raw surface_summary] $context]}
    if {$operation in {complex_fit complex_residuals}&&$modelId ne "math.numeric.complex_response"} {_error {Complex Numeric facts require their registered model}}
    if {[dict exists $raw complex_summary]&&$operation ni {complex_fit complex_residuals}} {_error {Complex facts cannot bypass their covariance interpretation}}
    if {$operation eq "implicit_fit"&&$modelId ne "math.numeric.implicit"} {_error {Implicit Numeric facts require their registered implicit model}}
    if {$operation in {generalized_least_squares polynomial_gls}} {if {$modelId ni {math.numeric.linear_design math.numeric.linear math.numeric.linear_origin math.numeric.polynomial}} {_error {GLS requires an explicitly declared linear-in-parameters model}};if {$operation eq "polynomial_gls"&&$modelId ne "math.numeric.polynomial"} {_error {Polynomial GLS requires its canonical polynomial model}};set raw [_glsRegressionRaw $raw];if {[dict get $raw gls_summary operation] ne $operation} {_error {GLS operation differs from its numeric summary}}}
    if {$operation ni {rational_fit rational_residuals surface_fit surface_residuals complex_fit complex_residuals implicit_fit generalized_least_squares polynomial_gls foundation.statistics.robust_regression foundation.statistics.logistic_regression foundation.statistics.glm foundation.statistics.kmeans foundation.statistics.covariance_diagnostics foundation.statistics.survival_kaplan_meier foundation.statistics.partial_correlation foundation.statistics.multiple_testing foundation.statistics.bootstrap_ci foundation.statistics.permutation_test foundation.statistics.confidence_interval foundation.statistics.robust_location least_squares linear_regression polynomial_fit nonlinear_fit curve_model_fit residual_summary residual_metrics matrix_statistics reduce_summary reduce_accumulate statistics weighted_statistics quantiles weighted_quantiles covariance correlation mad hypothesis_test one_way_anova resampling_summary propagate_uncertainty pca_summary matrix_svd spectral_features power_level welch_aggregate local_cloud_fit replicate_summary signal_summary signal_snr signal_spectrum_quality fft_spectrum_quality harmonic_peak_quality harmonic_components event_period pulse_timing signal_correlation window_metrics signal_periodogram signal_welch signal_asd signal_cross_psd signal_coherence signal_frf_h1 signal_frf_h2}&&![string match array_reduce.* $operation]} {_error "Numeric operation has no registered result adaptation"}
    set numerical {}
    if {[dict exists $raw knot_summary]} {foreach key {rmse mae max_abs_error} {if {[dict exists $raw $key]} {dict set numerical $key [dict get $raw $key]}}}
    if {$operation in {foundation.statistics.robust_regression foundation.statistics.logistic_regression foundation.statistics.glm}} {
        if {$profile ne "foundation_regression"||[dict get [numericModel $operation] id] ne $modelId} {_error {Foundation regression requires its actual registered Numeric model}}
        lassign [_foundationRegressionAdapt $operation $raw $context] numerical context
        # These bounded component vectors carry design-column identities. They
        # do not become ordinary least-squares parameter inference records.
        set raw [dict remove $raw coefficients parameters parameter_values]
    }
    if {$operation eq "foundation.statistics.kmeans"} {
        if {$profile ne "clustering"||[dict get [numericModel $operation] id] ne $modelId} {_error {Clustering requires its actual registered Numeric model}}
        lassign [_clusteringAdapt $raw $context] numerical context
        foreach key {seed random_generator backend backend_version} {if {![dict exists $raw $key]} {_error {Clustering requires actual seed and backend provenance}}}
        set seed [dict get $raw seed]
        if {![_finite $seed]||$seed<0||$seed!=floor($seed)||[dict get $raw backend] ne "Octave statistics kmeans"||[dict get $raw backend_version] eq {}} {_error {Invalid captured clustering provenance}}
        dict set provenance sampling_seed $seed;dict set provenance random_generator [dict get $raw random_generator]
        dict set provenance numeric_backend [dict get $raw backend];dict set provenance numeric_backend_version [dict get $raw backend_version]
    }
    if {$operation eq "foundation.statistics.covariance_diagnostics"} {
        if {$profile ne "covariance_diagnostics"||[dict get [numericModel $operation] id] ne $modelId} {_error {Covariance requires its actual registered diagnostic model}}
        lassign [_covarianceDiagnosticAdapt $raw $context] numerical context
        # These are observation covariance diagnostics, not parameter inference.
        set raw [dict remove $raw covariance rank condition_number]
    }
    if {$operation eq "foundation.statistics.survival_kaplan_meier"} {
        if {$profile ne "survival"||[dict get [numericModel $operation] id] ne $modelId} {_error {Survival requires its actual registered Numeric model}}
        lassign [_survivalAdapt $raw $context] numerical context
    }
    if {$operation in {foundation.statistics.partial_correlation foundation.statistics.multiple_testing}} {
        if {$profile ni {foundation_correlation multiplicity}||[dict get [numericModel $operation] id] ne $modelId} {_error {Foundation diagnostic requires its actual registered Numeric model}}
        lassign [_foundationDiagnosticAdapt $operation $raw $context] numerical context
    }
    if {$operation in {foundation.statistics.confidence_interval foundation.statistics.robust_location}} {
        if {$profile ne "location_estimate"||[dict get [numericModel $operation] id] ne $modelId} {_error {Location result requires its actual registered Numeric model}}
        lassign [_locationAdapt $operation $raw $context] numerical context
    }
    if {$operation in {signal_snr signal_spectrum_quality}} {
        if {$profile ne $operation} {_error {Signal quality requires its registered operation profile}}
        lassign [_signalQualityAdapt $profile $operation $raw $context] numerical context
    }
    if {$operation in {fft_spectrum_quality harmonic_peak_quality harmonic_components}} {
        if {$profile ne $operation} {_error {Amplitude quality requires its registered Numeric profile}}
        lassign [_spectralQualityAdapt $operation $raw $context] numerical context
    }
    if {$operation in {signal_periodogram signal_welch signal_asd signal_cross_psd signal_coherence signal_frf_h1 signal_frf_h2}} {
        if {$profile ne "signal_spectral"} {_error {Spectral estimates require their registered profile}}
        lassign [_signalSpectralAdapt $operation $raw $context] numerical context
    }
    if {$operation eq "window_metrics"} {
        if {$profile ne $operation} {_error {Window moments require their registered profile}}
        lassign [_windowMetricsAdapt $raw $context] numerical context
    }
    if {$operation eq "signal_correlation"} {
        if {$profile ne $operation} {_error {Sequence correlation requires its registered profile}}
        lassign [_signalCorrelationAdapt $raw $context] numerical context
    }
    if {$operation in {event_period pulse_timing}} {
        if {$profile ne "event_timing"} {_error {Event summaries require their registered timing profile}}
        lassign [_eventTimingAdapt $operation $raw $context] numerical context
    }
    if {$operation eq "signal_summary"} {
        if {$profile ne "signal_summary"} {_error {Signal moments require their registered descriptive profile}}
        dict for {source quantity} [numericFieldMap $operation] {
            if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Signal summary requires bounded scalar facts}}
            dict set numerical $quantity [dict get $raw $source]
        }
        foreach key {method input_kind} {dict set context $key [_get $raw $key {}]}
        dict set context assumptions [_signalSummaryAssumptions]
    }
    if {$operation eq "replicate_summary"} {
        if {$profile ne "replicate_profile"} {_error {Replicate summaries require their registered profile}}
        dict for {source quantity} [numericFieldMap $operation] {
            if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Interpret one replicate coordinate per scalar result; use tables or column bindings for a profile}}
            dict set numerical $quantity [dict get $raw $source]
        }
        foreach key {mode sampling_model component_method} {dict set context $key [_get $raw $key {}]}
        dict set context assumptions [_replicateAssumptions [dict get $context mode] [dict get $context sampling_model]]
    }
    if {$operation eq "local_cloud_fit"} {
        if {$profile ne "local_cloud"} {_error {Local cloud results require their registered profile}}
        dict for {source quantity} [numericFieldMap $operation] {
            if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Local cloud interpretation requires one query per result; use from_numeric_columns for multiple queries}}
            dict set numerical $quantity [dict get $raw $source]
        }
        foreach key {method variance_correction insufficient_policy} {dict set context $key [_get $raw $key {}]}
        dict set context assumptions [_localCloudAssumptions]
    }
    if {$operation eq "welch_aggregate"} {
        if {$profile ne "welch_spectrum"} {_error {Welch aggregation requires its registered profile}}
        dict for {source quantity} [numericFieldMap $operation] {if {[dict exists $raw $source]} {dict set numerical $quantity [dict get $raw $source]}}
        if {![dict exists $context y_unit]} {_error {Welch requires the actual signal unit; an empty unit remains unspecified}}
        dict for {key expected} [_welchUnits [dict get $context y_unit]] {
            if {[dict exists $context $key]&&[dict get $context $key] ne $expected} {_error {Welch units conflict with the source signal unit}}
            dict set context $key $expected
        }
        foreach key {zero_policy averaging peak_policy} {dict set context $key [_get $raw $key {}]}
        dict set context assumptions [_welchAssumptions]
    }
    if {$operation eq "power_level"} {
        if {$profile ne "power_level"} {_error {Power level requires its registered profile}}
        dict for {source quantity} [numericFieldMap $operation] {
            if {[dict exists $raw $source]} {
                if {[llength [dict get $raw $source]]!=1} {_error {Use from_numeric_columns for multiple power bands}}
                dict set numerical $quantity [dict get $raw $source]
            }
        }
        dict for {key expected} [_powerLevelUnits $context] {
            if {[dict exists $context $key]&&[dict get $context $key] ne $expected} {_error {Band units conflict with the source PSD unit}}
            dict set context $key $expected
        }
        foreach key {reference_rms zero_policy} {dict set context $key [_get $raw $key {}]}
        dict set context assumptions [_powerLevelAssumptions]
    }
    if {$operation eq "spectral_features"} {
        if {$profile ne "spectral_distribution"} {_error {Spectral descriptors require their registered profile}}
        dict for {source quantity} [numericFieldMap $operation] {if {[dict exists $raw $source]} {dict set numerical $quantity [dict get $raw $source]}}
        foreach key {input_semantics exclude_dc quantile_definition} {dict set context $key [_get $raw $key {}]}
        dict set context assumptions [_spectralAssumptions]
    }
    if {[string match array_reduce.* $operation]} {
        set map [numericFieldMap $operation]
        if {$profile ne "summary"||[_get $raw action {}] ne [string range $operation 13 end]} {_error {Array reduction facts must match their declared summary operation}}
        foreach field {values n_input n_valid} {
            if {![dict exists $raw $field]||[llength [dict get $raw $field]]!=1} {_error {Interpret one reduction group per result; use from_numeric_columns for axis-indexed arrays}}
        }
        foreach field {n_input n_valid} {
            set count [dict get $raw $field]
            if {![_finite $count]||$count<0||$count!=floor($count)} {_error {Reduction counts must be nonnegative integers}}
        }
        if {[dict get $raw n_valid]>[dict get $raw n_input]} {_error {Valid reduction count exceeds its input count}}
        foreach {source target} $map {dict set numerical $target [dict get $raw $source]}
        if {[dict get $raw action] eq "quantile"} {
            dict set numerical quantile_probabilities [_get $raw probability {}]
            dict set context quantile_definition [_get $raw quantile_definition {}]
        }
        foreach field {n_input requested_axis input_shape} {
            if {[dict exists $raw $field]} {dict set provenance reduction_$field [dict get $raw $field]}
        }
    }
    if {[_get $context sample_role training] eq "training"} {
        foreach key {n p rank dof edf sse r_squared adjusted_r_squared reduced_chi_squared covariance standard_errors condition_number converged response_variance free_parameter_count} {
            if {[dict exists $raw $key]} {dict set numerical $key [dict get $raw $key]}
        }
        if {$operation in {rational_fit surface_fit complex_fit implicit_fit generalized_least_squares polynomial_gls least_squares linear_regression polynomial_fit nonlinear_fit}} {
            if {[dict exists $raw response_rmse]} {dict set numerical rmse [dict get $raw response_rmse]}
            if {[dict exists $raw rmse]} {dict set numerical weighted_residual_standard_deviation [dict get $raw rmse]}
            # Numeric's rmse is weighted and DOF-scaled. Its residual_rmse is
            # unweighted and DOF-scaled, retaining physical response units.
            if {[dict exists $raw residual_rmse]} {dict set numerical residual_standard_deviation [dict get $raw residual_rmse]} elseif {[_get $raw weight_semantics unweighted] eq "unweighted"&&[dict exists $raw rmse]} {dict set numerical residual_standard_deviation [dict get $raw rmse]}
        }
    }
    # Parameter identity/roles remain facts of the trained model when reporting
    # a different evaluation sample. Do not recompute training inference there.
    foreach key {p free_parameter_count} {if {[dict exists $raw $key]} {dict set numerical $key [dict get $raw $key]}}
    foreach key {n rmse mae max_abs_error r_squared response_variance} {if {[dict exists $metrics $key]} {dict set numerical $key [dict get $metrics $key]}}
    if {![dict exists $numerical r_squared]&&[dict exists $metrics r2]} {dict set numerical r_squared [dict get $metrics r2]}
    if {$operation in {rational_residuals surface_residuals}} {
        foreach field {rank dof covariance standard_errors reduced_chi_squared solver_receipt} {if {[dict exists $raw $field]} {_error {Descriptive evaluation cannot acquire training inference facts}}}
        foreach {field quantity} [numericFieldMap $operation] {if {[dict exists $raw $field]} {dict set numerical $quantity [dict get $raw $field]}}
    }
    if {$operation eq "complex_residuals"} {
        foreach field {rank dof covariance standard_errors reduced_chi_squared solver_receipt} {if {[dict exists $raw $field]} {_error {Complex evaluation cannot acquire training inference facts}}}
        foreach key {n sse rmse mae max_abs_error} {if {![dict exists $raw $key]} {_error "Complex evaluation requires $key"};dict set numerical $key [dict get $raw $key]}
    }
    if {$operation eq "residual_metrics"} {
        foreach key {n rmse mae max_abs_error sse response_variance relative_n relative_floor max_relative_error rms_relative_error} {if {[dict exists $raw $key]} {dict set numerical $key [dict get $raw $key]}}
        if {[dict exists $raw r2]} {dict set numerical r_squared [dict get $raw r2]}
        if {$profile eq "comparison"&&[dict exists $raw r2]} {dict set numerical centered_comparison_score [dict get $raw r2]}
    }
    if {$operation eq "residual_summary"} {
        if {$profile ni {comparison geometric_comparison}} {_error {Native residual summaries require a descriptive comparison profile}}
        foreach {source target} {count n rmse rmse mean_absolute mae max_absolute max_abs_error hausdorff_sampled sampled_hausdorff_distance} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
    }
    if {$operation eq "matrix_svd"} {
        if {$profile ne "solver"} {_error {SVD diagnostics require the registered solver profile}}
        foreach {source target} {rows n cols p rank rank condition_number condition_number} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
    }
    if {$operation eq "pca_summary"} {
        if {$profile ne "pca"} {_error {PCA component summary requires its registered profile}}
        foreach key {n singular_value component_variance explained_ratio cumulative_ratio component_index component_count total_component_variance} {if {[dict exists $raw $key]} {dict set numerical $key [dict get $raw $key]}}
        dict set context method [_get $raw method {}]
        dict set context assumptions {{Descriptive spectral decomposition; explained ratios do not establish sampling inference or causality} {Component signs and bases within degenerate subspaces are not unique}}
    }
    if {$operation eq "propagate_uncertainty"} {
        if {$profile ne "propagation"} {_error {Propagation requires its registered statistical profile}}
        set numerical {}
        foreach {source target} {covariance output_covariance standard_uncertainty output_standard_uncertainties input_count input_count output_count output_count} {
            if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}
        }
        dict set context method [_get $raw method {}];dict set context input_kind [_get $raw input_kind {}]
        dict set context assumptions [_propagationAssumptions [dict get $context input_kind]]
        if {[dict exists $context output_index]} {
            set index [dict get $context output_index]
            if {![_finite $index]||$index!=floor($index)||$index<1||$index>[llength [_get $raw standard_uncertainty {}]]} {_error {Selected propagation output is outside the Numeric output list}}
            dict set numerical standard_uncertainty [lindex [dict get $raw standard_uncertainty] [expr {int($index)-1}]]
        }
    }
    if {$operation in {resampling_summary foundation.statistics.bootstrap_ci foundation.statistics.permutation_test}} {
        if {$operation ne "resampling_summary"&&[dict get [numericModel $operation] id] ne $modelId} {_error {Foundation resampling requires its actual registered Numeric model}}
        if {$profile ne "resampling"} {_error {Resampling summary requires its registered interpretation profile}}
        foreach {source target} [concat [numericFieldMap $operation] {distribution_variance distribution_variance tail_tolerance tail_tolerance}] {
            if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}
        }
        if {$operation ne "resampling_summary"} {
            if {[_get $raw random_generator {}] ne "twister"||![dict exists $raw seed]} {_error {Foundation resampling requires its actual random generator and seed}}
            set seed [dict get $raw seed];if {![_finite $seed]||$seed<0||$seed!=floor($seed)} {_error {Foundation resampling requires an explicit nonnegative integer seed}}
            dict set provenance sampling_seed [dict get $raw seed];dict set provenance random_generator twister
        }
        foreach key {method alternative confidence inference quantile_definition} {if {[dict exists $raw $key]} {dict set context $key [dict get $raw $key]}}
        dict set context assumptions [_resamplingAssumptions [_get $context method {}]]
        dict set context approximation [_get $raw inference {}]
    }
    if {$operation eq "one_way_anova"} {
        if {$profile eq "summary"} {
            set index [_get $context group_index {}];set count [llength [_get $raw group_counts {}]]
            if {![_finite $index]||$index!=floor($index)||$index<1||$index>$count} {_error {ANOVA group index is outside the numerical group identity list}}
            foreach {source target} {group_counts n group_means mean group_variances variance group_standard_deviations standard_deviation} {
                if {[llength [_get $raw $source {}]]!=$count} {_error {ANOVA group facts have inconsistent dimensions}}
                dict set numerical $target [lindex [dict get $raw $source] [expr {int($index)-1}]]
            }
            if {[llength [_get $raw group_names {}]]!=$count} {_error {ANOVA group names differ from numerical group count}}
            dict set provenance group_name [lindex [dict get $raw group_names] [expr {int($index)-1}]]
        } elseif {$profile eq "anova"} {
            foreach key {group_count ss_between ss_within ss_total df_between df_within ms_between ms_within f_statistic f_numerator_df f_denominator_df p_value eta_squared omega_squared} {
                if {[dict exists $raw $key]} {dict set numerical $key [dict get $raw $key]}
            }
            foreach {source target} {n_valid n overall_mean grand_mean} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
            dict set context method [_get $raw method {}]
            dict set context assumptions [_anovaAssumptions [dict get $context method]]
            dict set context approximation [expr {[dict get $context method] eq "welch" ? "welch_f_approximation" : "f_distribution"}]
        } else {_error {ANOVA requires its test profile or indexed group summary profile}}
    }
    if {$operation eq "hypothesis_test"} {
        if {$profile ne "hypothesis"} {_error "Hypothesis test requires its registered statistical profile"}
        foreach {source target} {statistic test_statistic degrees_of_freedom test_degrees_of_freedom n_x n_first n_y n_second p_value p_value estimate test_estimate null_value null_value standard_error test_standard_error test_standard_deviation test_standard_deviation interval_margin interval_margin ci_lower ci_lower ci_upper ci_upper effect_size effect_size} {
            if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}
        }
        foreach key {method alternative confidence approximation effect_name ci_status} {if {[dict exists $raw $key]} {dict set context $key [dict get $raw $key]}}
        dict set context assumptions [_testAssumptions [_get $context method {}]]
    }
    if {$operation in {matrix_statistics reduce_summary reduce_accumulate}} {
        if {$profile ne "summary"} {_error {Axis and accumulated summaries require their descriptive profile}}
        dict for {source target} [numericFieldMap $operation] {
            if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Adapt one scalar axis group at a time, or use bounded statistical columns}}
            dict set numerical $target [dict get $raw $source]
        }
        set count [dict get $numerical n]
        if {![_finite $count]||$count<1||$count!=floor($count)} {_error {Summary requires its actual positive integer observation count}}
        foreach field {input_shape output_shape requested_dimension} {if {[dict exists $raw $field]} {dict set provenance reduction_$field [dict get $raw $field]}}
    }
    if {$operation in {statistics weighted_statistics}} {
        dict set context quantile_definition [expr {$operation eq "statistics" ? "Hyndman-Fan type 7 linear interpolation" : [_get $raw quantile_definition "weighted empirical CDF inverse"]}]
        foreach {source target} {n n mean mean std_sample standard_deviation variance_sample variance std_unbiased standard_deviation variance_unbiased variance} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
        foreach {source target} {min minimum max maximum max_absolute absolute_maximum range range sum sum median median q25 quartile_1 q75 quartile_3 iqr interquartile_range rms root_mean_square variance_population variance_population std_population standard_deviation_population standard_error_mean standard_error_mean sampling_standard_error_mean standard_error_mean measurement_standard_error_mean measurement_standard_error_mean effective_n effective_n sum_weights sum_weights weighted_sum weighted_sum} {
            if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}
        }
        if {$operation eq "weighted_statistics"&&[dict exists $raw n_positive_weight]} {dict set numerical n [dict get $raw n_positive_weight];dict set context weight_semantics [_get $raw weight_semantics relative]}
    }
    if {$operation in {quantiles weighted_quantiles}} {
        foreach {source target} {n n n_positive_weight n quantiles quantiles probabilities quantile_probabilities} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
        dict set context quantile_definition [_get $raw definition unspecified]
        if {$operation eq "weighted_quantiles"} {dict set context weight_semantics relative}
    }
    if {$operation eq "mad"} {
        foreach {source target} {n_valid n median median raw_mad raw_median_absolute_deviation mad median_absolute_deviation} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
        dict set context mad_scale [_get $raw scale raw]
        if {[dict get $context mad_scale] ni {raw normal_consistency}} {_error {Unknown MAD scaling convention}}
    }
    if {$operation in {covariance correlation}} {
        foreach {source target} {n_valid n covariance_sample covariance_sample covariance_population covariance_population correlation correlation} {if {[dict exists $raw $source]} {dict set numerical $target [dict get $raw $source]}}
        if {[dict exists $raw method]} {dict set context method [dict get $raw method]}
    }
    if {$profile in {projection parametric_regression}&&[dict exists $numerical r_squared]} {
        dict set numerical geometric_dispersion_score [dict get $numerical r_squared]
        dict unset numerical r_squared
    }
    foreach {source target} {solver solver weight_semantics weight_semantics has_intercept has_intercept} {if {[dict exists $raw $source]} {dict set context $target [dict get $raw $source]}}
    set geometry [_get $raw fit_geometry vertical_response]
    if {[dict exists $context fit_geometry]&&[dict get $context fit_geometry] ne $geometry} {_error {Statistical fit geometry differs from the captured Numeric result}}
    if {$geometry eq "orthogonal_xy"} {
        if {$operation ne "nonlinear_fit"} {_error {Orthogonal XY geometry requires the declared-model Numeric fit}}
        dict set context fit_geometry $geometry
        dict set context assumptions [_orthogonalXYAssumptions]
    } elseif {$geometry eq "implicit_algebraic"&&$operation eq "implicit_fit"} {dict set context fit_geometry $geometry
    } elseif {$geometry eq "vertical_response_z_at_exact_xy"&&$operation in {surface_fit surface_residuals}} {dict set context fit_geometry $geometry
    } elseif {$geometry ne "vertical_response"} {_error {Unknown captured fit geometry}}
    if {[dict exists $raw loss]} {dict set context loss [dict get $raw loss]}
    if {[_get $raw response_count 1]>1} {dict set context orientation joint_responses}
    set fixed [_get $raw fixed_mask {}]
    if {[llength $fixed]} {
        set anyFixed 0
        foreach flag $fixed {
            if {![_finite $flag]||$flag ni {0 1 0.0 1.0}} {_error "Invalid fixed parameter mask"}
            if {$flag} {set anyFixed 1}
        }
        if {$anyFixed} {dict set context constraints fixed_parameters}
    }
    if {[dict exists $raw active_bounds]} {
        set anyActive 0
        foreach flag [dict get $raw active_bounds] {if {![_finite $flag]||$flag ni {0 1 0.0 1.0}} {_error "Invalid active bound mask"};if {$flag} {set anyActive 1}}
        if {$anyActive} {dict set context constraints active_bounds} elseif {![info exists anyFixed]||!$anyFixed} {dict set context constraints inactive_bounds}
    }
    if {[dict exists $raw covariance_scale]} {
        dict set context covariance_scaling [expr {[_get $raw weight_semantics unweighted] eq "inverse_variance" ? "absolute_measurement_variance" : "estimated_residual_variance"}]
    }
    set context [dict merge [dict create constraints unknown coefficient_space original_physical \
        assumptions {{Numerical estimates are conditional on the supplied model and measurement assumptions}}] $context]
    set values [_get $raw parameter_values [_get $raw coefficients [_get $raw parameters {}]]]
    set convention [dict get $descriptor parameter_convention];set ids [dict get $descriptor parameter_ids]
    if {$convention ne "named"} {
        set ids {};set count [llength $values]
        for {set i 0} {$i<$count} {incr i} {lappend ids [expr {$convention eq "descending_power" ? "power_[expr {$count-$i-1}]" : "parameter_[expr {$i+1}]"}]}
    } elseif {[llength $values]&&[llength $values]!=[llength $ids]} {_error "Numeric parameter count differs from the named model descriptor"}
    if {$convention eq "basis_controls"&&[dict exists $raw model parameter_ids]} {
        set ids [dict get $raw model parameter_ids]
        if {[llength $ids]!=[llength $values]} {_error "Declared parameter identities and estimates differ in length"}
    }
    set declaredUnits {}
    if {[dict exists $raw model parameter_units]} {set declaredUnits [dict get $raw model parameter_units];if {[llength $declaredUnits]!=[llength $ids]} {_error "Declared parameter units differ in length"}}
    if {[llength $fixed]&&[llength $fixed]!=[llength $ids]} {_error "Fixed mask differs from parameter identities"}
    set orientation [_get $context orientation y_of_x]
    set response [_get $context y_unit {}];set independent [_get $context x_unit {}]
    if {$orientation eq "x_of_y"} {set response [_get $context x_unit {}];set independent [_get $context y_unit {}]}
    if {$orientation eq "z_of_xy"} {set response [_get $context z_unit {}]}
    if {$orientation eq "r_of_theta"} {set response [_get $context radial_unit {}];set independent rad}
    set parameters {};set i 0
    foreach id $ids {
        set unit unspecified
        if {$convention eq "named"} {
            # Physical dimensional relationships, never inferred from display text.
            switch -- $id {
                intercept - amplitude - offset {set unit $response}
                slope {if {$response ne {}&&$independent ne {}} {set unit "$response/$independent"}}
                rate {if {$independent ne {}} {set unit "1/$independent"}}
                center - width {set unit $independent}
                exponent {set unit 1}
            }
        } elseif {$convention eq "descending_power"&&$response ne {}&&$independent ne {}} {set unit "$response/($independent)^[expr {[llength $ids]-$i-1}]"}
        if {$profile eq "smoother"&&$convention eq "model_state"} {set unit $response}
        if {$unit eq {}} {set unit unspecified}
        if {[llength $declaredUnits]} {set unit [lindex $declaredUnits $i]}
        set parameter [dict create id $id label $id unit $unit role [expr {$convention eq "model_state" ? "state" : "free"}]]
        if {[llength $fixed]&&[lindex $fixed $i]} {dict set parameter role fixed}
        if {[llength $values]} {dict set parameter value [lindex $values $i]}
        lappend parameters $parameter;incr i
    }
    if {$modelId eq "math.numeric.power_law"} {
        set receipt [_conditionalParameterUnits $modelId $parameters $context]
        set scale [lindex $parameters 0];set inferred [dict get $receipt unit_expression]
        if {[llength $declaredUnits]&&($inferred ne [lindex $declaredUnits 0]||[lindex $declaredUnits 1] ne "1")} {_error {Declared power-law parameter units conflict with the captured physical coordinate basis}}
        dict set scale unit $inferred;lset parameters 0 $scale
        if {[dict exists $context conditional_parameter_units]} {_validateConditionalParameterUnits [dict get $context conditional_parameter_units] $receipt $parameters}
        dict set context conditional_parameter_units $receipt
    }
    set provenance [dict merge $provenance [dict create numeric_api NUMERIC_API_v1 operation $sourceOperation]]
    if {[dict exists $context response_transform]} {
        _validateLogResponseContext $context
        foreach assumption [_logResponseContextAssumptions $context] {if {[lsearch -exact [dict get $context assumptions] $assumption]<0} {dict lappend context assumptions $assumption}}
    }
    if {[dict exists $context smoothing]} {
        _validateSmoothingContext [dict get $context smoothing]
        foreach assumption [_smoothingAssumptions] {if {[lsearch -exact [dict get $context assumptions] $assumption]<0} {dict lappend context assumptions $assumption}}
    }
    if {[dict exists $context baseline_correction]} {
        _validateBaselineContext [dict get $context baseline_correction]
        foreach assumption [_baselineAssumptions] {if {[lsearch -exact [dict get $context assumptions] $assumption]<0} {dict lappend context assumptions $assumption}}
    }
    if {[dict exists $raw regional_fit]&&[_get $context sample_role training] eq "training"} {
        if {$operation ne "nonlinear_fit"} {_error {Regional facts require the actual nonlinear fit}}
        set facts [dict get $raw regional_fit]
        if {[_get $facts schema {}] ne "gxtxt.regional_fit_receipt.v1"} {_error {Unsupported Numeric regional receipt}}
        set regional [dict create schema gxtxt.regional_fit_inference.v1]
        foreach key {breakpoint_ids breakpoint_values breakpoint_fixed continuity sample_coincidence_counts} {dict set regional $key [dict get $facts $key]}
        dict set regional region_counts [dict get $facts inference_region_counts]
        if {[dict exists $context regional_fit]&&[dict get $context regional_fit] ne $regional} {_error {Context cannot replace captured regional inference facts}}
        dict set context regional_fit $regional
        foreach assumption [_regionalFitAssumptions] {if {[lsearch -exact [dict get $context assumptions] $assumption]<0} {dict lappend context assumptions $assumption}}
    }
    if {$operation in {rational_fit surface_fit implicit_fit least_squares linear_regression polynomial_fit nonlinear_fit}&&[dict exists $raw observation_signature]&&[_get $context sample_role training] eq "training"} {
        dict set provenance observation_signature [_fitObservationSignature [dict get $raw observation_signature]]
    }
    if {$operation eq "polynomial_fit"&&[_get $context sample_role training] eq "training"} {
        set present 0;foreach field {scaled_coefficients scaled_covariance x_center x_scale} {if {[dict exists $raw $field]} {incr present}}
        if {$present&&$present!=4} {_error {Incomplete Numeric polynomial propagation facts}}
        if {$present&&[llength $values]<=128} {
            dict set provenance polynomial_propagation_basis [_polynomialPropagationBasis [dict create api_id STATISTICAL_POLYNOMIAL_PROPAGATION_BASIS_v1 api_version 1 kind centered_scaled_descending_power source_parameters [dict get $raw scaled_coefficients] source_covariance [dict get $raw scaled_covariance] query_center [dict get $raw x_center] query_scale [dict get $raw x_scale]] [llength $values] 0]
        }
    }
    foreach key {source_sha256 binding_sha256} {
        if {[dict exists $raw model $key]} {
            set digest [dict get $raw model $key]
            if {![regexp {^[0-9a-f]{64}$} $digest]} {_error {Numeric model digest is malformed}}
            dict set provenance model_$key $digest
        }
    }
    if {![dict exists $provenance producer]} {dict set provenance producer math.numeric}
    if {$profile eq "smoother"&&$operation eq "curve_model_fit"&&[_get $context sample_role training] eq "training"&&[dict exists $raw trace_method]} {
        set smoothing [_smoothingAdapt $raw $context]
        set numerical [dict merge $numerical [dict get $smoothing numerical]]
        set context [dict get $smoothing context];dict set provenance smoothing [dict get $smoothing receipt]
    }
    if {$operation in {generalized_least_squares polynomial_gls}&&[_get $context sample_role training] eq "training"} {set context [_glsRegressionContext [dict get $raw gls_summary] $context $parameters]} else {set context [dict remove $context covariance_unit]}
    if {$operation in {complex_fit complex_residuals}} {set context [_complexContext [dict get $raw complex_summary] $context]}
    if {$operation eq "implicit_fit"} {set context [_implicitContext [dict get $raw implicit_summary] $context]}
    set request [dict create model_id $modelId context $context numerical $numerical parameters $parameters provenance $provenance]
    if {[dict exists $raw solver_receipt]} {dict set request solver_receipt [dict get $raw solver_receipt]}
    return [interpret $request]
}
proc ::GX::StatisticsV1::feature {result quantity} {
    validate $result
    if {![dict exists $result quantities $quantity]} {_error "Unknown quantity '$quantity'"}
    set item [dict get $result quantities $quantity]
    if {[dict get $item kind] ne "scalar"} {_error "Analysis features require scalar quantities"}
    set value NaN;set status unavailable
    switch -- [dict get $item status] {
        value {set value [dict get $item value];set status valid}
        error {set status failed}
    }
    return [dict create value $value status $status reason [dict get $item reason] \
        unit [dict get $item unit] interpretation_status [dict get $item status] quantity $quantity]
}
proc ::GX::StatisticsV1::parameterReport {result} {
    validate $result
    set lines {};set i 0;set uncertainty [dict get $result quantities standard_errors]
    foreach parameter [dict get $result parameters] {
        set value unavailable
        if {[dict exists $parameter value]} {set value [format %.9g [dict get $parameter value]]}
        set line "[dict get $parameter id] = $value ([dict get $parameter unit])"
        if {[dict get $parameter role] eq "fixed"} {append line " ; fixed value"} elseif {[dict get $uncertainty status] eq "value"} {append line " ; SE [format %.9g [lindex [dict get $uncertainty value] $i]]"}
        if {[dict exists $result parameter_uncertainty intervals]} {
            set intervals [dict get $result parameter_uncertainty intervals]
            set index [lsearch -exact [dict get $result parameter_uncertainty parameter_ids] [dict get $parameter id]]
            if {$index>=0&&[dict get $intervals status] eq "value"} {
                append line " ; [format %.6g [dict get $intervals confidence]] confidence interval \[[format %.9g [lindex [dict get $intervals lower] $index]], [format %.9g [lindex [dict get $intervals upper] $index]]\]"
            }
        }
        lappend lines $line;incr i
    }
    if {![llength $lines]} {lappend lines {No scalar regression parameters; retained model state is available separately}}
    lappend lines "Coefficient space: [_get [dict get $result context] coefficient_space original_physical]"
    if {[dict exists $result context conditional_parameter_units]} {lappend lines "Parameter units: [dict get $result context conditional_parameter_units reason]"}
    if {[dict get $uncertainty status] ne "value"} {lappend lines "Standard errors: [dict get $uncertainty status] — [dict get $uncertainty reason]"}
    if {[dict exists $result parameter_uncertainty intervals]} {
        set intervals [dict get $result parameter_uncertainty intervals]
        if {[dict get $intervals status] eq "value"} {lappend lines "Interval method: [dict get $intervals distribution]; [dict get $intervals approximation]; pointwise marginal intervals"} else {lappend lines "Confidence intervals: [dict get $intervals status] — [dict get $intervals reason]"}
    }
    if {[dict exists $result context complex]} {foreach assumption [_complexAssumptions [dict get $result context complex operation]] {lappend lines $assumption}}
    if {[dict exists $result context implicit]} {foreach assumption [_implicitAssumptions] {lappend lines $assumption}}
    if {[dict exists $result context rational]} {foreach assumption [_rationalAssumptions [dict get $result context rational operation]] {lappend lines $assumption}}
    if {[dict exists $result context knot_spline]} {foreach assumption [_knotSplineAssumptions [dict get $result context knot_spline model]] {lappend lines $assumption}}
    if {[dict exists $result context surface]} {foreach assumption [_surfaceAssumptions [dict get $result context surface operation]] {lappend lines $assumption}}
    return [join $lines \n]
}
proc ::GX::StatisticsV1::validateMetadata {metadata} {
    # The canonical publication and metadata owners call this same boundary.
    # Legacy plain metadata is retained; a versioned interpretation cannot be
    # substituted with a private contract or a hand-edited statistical label.
    set count 0
    dict for {key value} $metadata {
        if {[lindex [split $key .] end] eq "statistical_results"} {
            if {[catch {dict size $value}]||![dict size $value]} {_error "Statistical result metadata '$key' requires named result records"}
            dict for {name result} $value {validate $result;incr count}
        } elseif {![catch {dict get $value api_id} id]&&$id eq "STATISTICAL_RESULT_SEMANTICS_API_v1"} {
            validate $value;incr count
        }
    }
    return [dict create valid 1 result_count $count]
}
proc ::GX::StatisticsV1::publicationMetadata {results} {
    set metadata [dict create analysis.statistical_results $results]
    validateMetadata $metadata
    return $metadata
}
proc ::GX::StatisticsV1::validatePublication {owner definition} {
    _catalog
    set metadata [_get $definition structured_metadata {}]
    set checked [validateMetadata $metadata]
    set manifest [::GX::moduleField $owner dict {}]
    if {[::GX::descriptorValue $manifest statistical_results publication_required 0] eq "1"&&![dict get $checked result_count]} {
        _error "Statistical producer '$owner' must publish its validated interpretation with the result"
    }
    return $checked
}
proc ::GX::StatisticsV1::validateMetadataReplacement {before after} {
    set checked [validateMetadata $after]
    dict for {key value} $before {
        set statistical [expr {[lindex [split $key .] end] eq "statistical_results"}]
        if {!$statistical&&![catch {dict get $value api_id} id]&&$id eq "STATISTICAL_RESULT_SEMANTICS_API_v1"} {set statistical 1}
        if {$statistical&&![dict exists $after $key]} {_error "Cannot erase statistical interpretation '$key' from an existing scientific result"}
    }
    return $checked
}

# Eligibility and scientific labels belong here. Quantiles, covariance
# normalization and interval arithmetic belong only to the Numeric provider.
proc ::GX::StatisticsV1::parameterInferencePlan {result {confidence 0.95}} {
    validate $result
    return [_parameterInferencePlan $result $confidence]
}
proc ::GX::StatisticsV1::_parameterInferencePlan {result confidence} {
    if {![_finite $confidence]||$confidence<=0||$confidence>=1} {_error "Confidence must be strictly between zero and one"}
    set covariance [dict get $result quantities covariance]
    set plan [dict create api_id STATISTICAL_PARAMETER_INFERENCE_PLAN_v1 api_version 1 \
        status [dict get $covariance status] reason [dict get $covariance reason] confidence $confidence \
        source_model_id [dict get $result model id] coefficient_space [_get [dict get $result context] coefficient_space original_physical] \
        parameter_ids {} parameter_units {} source_parameters {} source_covariance {} \
        degrees_of_freedom {} distribution none approximation unavailable \
        interval_status unavailable interval_reason {A valid parameter covariance is required}]
    if {[dict get $covariance status] ne "value"} {
        dict set plan interval_status [dict get $covariance status]
        dict set plan interval_reason [dict get $covariance reason]
        return $plan
    }
    set indices {};set i 0
    foreach parameter [dict get $result parameters] {
        if {[dict get $parameter role] eq "free"} {
            if {[dict exists $result context gls]&&[lindex [dict get $covariance value] $i $i]==0} {incr i;continue}
            if {![dict exists $parameter value]} {_error "Parameter inference requires estimated values"}
            lappend indices $i
            dict lappend plan parameter_ids [dict get $parameter id]
            dict lappend plan parameter_units [dict get $parameter unit]
            dict lappend plan source_parameters [dict get $parameter value]
        }
        incr i
    }
    if {![llength $indices]} {
        dict set plan status not_applicable;dict set plan reason [expr {[dict exists $result context gls]?"No positive-variance coefficient coordinates remain after exact covariance constraints":"There are no freely estimated parameters"}]
        dict set plan interval_status not_applicable;dict set plan interval_reason [dict get $plan reason]
        return $plan
    }
    if {[llength $indices]>256} {_error "Parameter inference is bounded to 256 free parameters"}
    set matrix [dict get $covariance value];set reduced {}
    foreach i $indices {
        if {[lindex $matrix $i $i]<=0} {
            dict set plan status undefined;dict set plan reason {A free parameter has zero estimated variance; correlation and ordinary confidence intervals are undefined}
            dict set plan interval_status undefined;dict set plan interval_reason [dict get $plan reason]
            return $plan
        }
        set row {};foreach j $indices {lappend row [lindex $matrix $i $j]};lappend reduced $row
    }
    dict set plan source_covariance $reduced
    dict set plan degrees_of_freedom [dict get $result quantities dof value]
    set context [dict get $result context]
    set noise [_get $context noise_model unspecified]
    set scaling [_get $context covariance_scaling unspecified]
    if {[dict exists $context gls]} {
        if {$noise eq "correlated_gaussian_known_covariance"} {dict set plan distribution normal
        } elseif {$noise eq "correlated_gaussian_estimated_scale"&&[dict get $plan degrees_of_freedom]>0} {dict set plan distribution student_t
        } else {dict set plan interval_reason {GLS intervals require an explicit Gaussian full-covariance assumption and identifiable scale};return $plan}
        dict set plan interval_status value;dict set plan interval_reason {};dict set plan approximation linear_model_conditional_covariance
        return $plan
    }
    if {$noise eq "independent_gaussian_known_sigma"&&$scaling eq "absolute_measurement_variance"&&[_get $context weight_semantics unweighted] eq "inverse_variance"} {
        dict set plan distribution normal
    } elseif {$noise eq "independent_gaussian_estimated_variance"&&$scaling eq "estimated_residual_variance"&&[_get $context weight_semantics unweighted] in {unweighted relative}} {
        dict set plan distribution student_t
    } else {
        dict set plan interval_reason {Confidence intervals require an explicit Gaussian noise assumption consistent with the covariance scaling and weights}
        return $plan
    }
    dict set plan interval_status value;dict set plan interval_reason {}
    dict set plan approximation [expr {[dict get $result model profile] eq "regression"&&[_get $context fit_geometry vertical_response] ne "orthogonal_xy" ? "linear_model" : "local_linearization"}]
    return $plan
}
proc ::GX::StatisticsV1::_sameInferencePlan {expected actual} {
    if {[lsort [dict keys $expected]] ne [lsort [dict keys $actual]]} {_error "Numeric inference receipt has an incompatible plan"}
    dict for {key value} $expected {
        set other [dict get $actual $key]
        if {$key eq "source_covariance"} {
            if {[llength $value]!=[llength $other]} {_error "Inference covariance shape changed"}
            set a {};set b {}
            foreach row $value otherRow $other {
                if {[llength $row]!=[llength $otherRow]} {_error "Inference covariance shape changed"}
                lappend a {*}$row;lappend b {*}$otherRow
            }
        } elseif {$key in {source_parameters confidence degrees_of_freedom api_version query_center query_scale}} {set a $value;set b $other} else {
            if {$value ne $other} {_error "Numeric inference plan changed '$key'"}
            continue
        }
        if {[llength $a]!=[llength $b]} {_error "Numeric inference plan changed '$key'"}
        foreach x $a y $b {
            if {![_finite $y]} {_error "Numeric inference plan changed '$key'"}
            # The existing bounded Tcl/Octave JSON adapter can round a decimal
            # by one binary64 ULP. This is a transport comparison, not a new
            # covariance estimate; retain exact counts and confidence settings.
            set same [expr {$x==$y}]
            if {!$same&&$key in {source_parameters source_covariance query_center query_scale}} {set same [expr {abs($x-$y)<=4*2.2204460492503131e-16*max(abs($x),abs($y))}]}
            if {!$same} {_error "Numeric inference plan changed '$key'"}
        }
    }
}
proc ::GX::StatisticsV1::_interpretUncertainty {result receipt} {
    _keys $receipt {confidence numeric} parameter_uncertainty
    set confidence [_get $receipt confidence 0.95]
    set plan [_parameterInferencePlan $result $confidence]
    set status [dict get $plan status];set reason [dict get $plan reason]
    set out [dict create api_version 1 parameter_ids [dict get $plan parameter_ids] \
        parameter_units [dict get $plan parameter_units] coefficient_space [dict get $plan coefficient_space] \
        correlation [dict create status $status reason $reason unit 1] \
        intervals [dict create status [dict get $plan interval_status] reason [dict get $plan interval_reason] confidence $confidence \
            distribution [dict get $plan distribution] approximation [dict get $plan approximation] coverage pointwise_marginal]]
    if {![dict exists $receipt numeric]} {
        if {$status eq "value"} {dict set out correlation status unavailable;dict set out correlation reason {Numeric parameter uncertainty has not been calculated}}
        if {[dict get $out intervals status] eq "value"} {dict set out intervals status unavailable;dict set out intervals reason {Numeric parameter uncertainty has not been calculated}}
        return $out
    }
    if {$status ne "value"} {_error "Cannot attach numerical uncertainty to an ineligible parameterization"}
    set raw [dict get $receipt numeric]
    _keys $raw {numeric_api operation plan correlation lower upper critical_value} parameter_uncertainty_numeric
    if {[_get $raw numeric_api {}] ne "NUMERIC_API_v1"||[_get $raw operation {}] ne "parameter_uncertainty"} {_error "Uncertainty must identify its public Numeric calculation"}
    _sameInferencePlan $plan [dict get $raw plan]
    set ids [dict get $plan parameter_ids];set p [llength $ids];set matrix [dict get $raw correlation]
    if {[llength $matrix]!=$p} {_error "Parameter correlation row count differs from free identities"}
    foreach row $matrix {if {[llength $row]!=$p} {_error "Parameter correlation column count differs from free identities"};foreach value $row {if {![_finite $value]||$value < -1.000000000001||$value > 1.000000000001} {_error "Numeric returned invalid parameter correlation"}}}
    dict set out correlation value $matrix
    if {[dict get $plan interval_status] eq "value"} {
        foreach key {lower upper} {
            if {![dict exists $raw $key]||[llength [dict get $raw $key]]!=$p} {_error "Numeric interval bounds differ from free parameter identities"}
            foreach value [dict get $raw $key] {if {![_finite $value]} {_error "Numeric returned nonfinite interval bounds"}}
            dict set out intervals $key [dict get $raw $key]
        }
        foreach lo [dict get $raw lower] hi [dict get $raw upper] value [dict get $plan source_parameters] {if {$lo>$value||$hi<$value} {_error "Numeric interval does not enclose its parameter estimate"}}
        if {![_finite [_get $raw critical_value {}]]||[dict get $raw critical_value]<=0} {_error "Numeric returned invalid interval critical value"}
        dict set out intervals critical_value [dict get $raw critical_value]
    } elseif {[dict exists $raw lower]||[dict exists $raw upper]||[dict exists $raw critical_value]} {_error "Numeric supplied confidence intervals without an eligible noise model"}
    dict set out provenance [dict create numeric_api NUMERIC_API_v1 operation parameter_uncertainty]
    return $out
}
proc ::GX::StatisticsV1::withParameterUncertainty {result confidence {numeric {}}} {
    validate $result
    set request [dict get $result request]
    set receipt [dict create confidence $confidence]
    if {$numeric ne {}} {dict set receipt numeric $numeric}
    dict set request parameter_uncertainty $receipt
    return [interpret $request]
}
proc ::GX::StatisticsV1::parameterRows {result} {
    validate $result
    set rows {};set i 0;set se [dict get $result quantities standard_errors]
    foreach parameter [dict get $result parameters] {
        set row [dict merge $parameter [dict create value_status unavailable se_status [dict get $se status] se_reason [dict get $se reason] ci_status unavailable ci_reason {Parameter intervals have not been requested}]]
        if {[dict exists $parameter value]} {dict set row value_status value}
        if {[dict get $se status] eq "value"} {dict set row standard_error [lindex [dict get $se value] $i]}
        if {[dict get $parameter role] eq "fixed"} {
            dict unset row standard_error
            dict set row se_status not_applicable;dict set row se_reason {Parameter was fixed, not estimated}
            dict set row ci_status not_applicable;dict set row ci_reason {Parameter was fixed, not estimated}
        } elseif {[dict exists $result parameter_uncertainty]} {
            set u [dict get $result parameter_uncertainty];set ci [dict get $u intervals]
            dict set row ci_status [dict get $ci status];dict set row ci_reason [dict get $ci reason]
            dict set row confidence [dict get $ci confidence]
            set j [lsearch -exact [dict get $u parameter_ids] [dict get $parameter id]]
            if {[dict get $ci status] eq "value"&&$j>=0} {dict set row lower [lindex [dict get $ci lower] $j];dict set row upper [lindex [dict get $ci upper] $j]}
        }
        lappend rows $row;incr i
    }
    return $rows
}
proc ::GX::StatisticsV1::parameterCorrelationReport {result} {
    validate $result
    if {![dict exists $result parameter_uncertainty]} {return {Parameter correlation: unavailable — parameter uncertainty has not been requested}}
    set u [dict get $result parameter_uncertainty];set c [dict get $u correlation]
    if {[dict get $c status] ne "value"} {return "Parameter correlation: [dict get $c status] — [dict get $c reason]"}
    set lines [list "Free parameter correlation (dimensionless); [dict get $u coefficient_space]" [join [linsert [dict get $u parameter_ids] 0 parameter] \t]]
    foreach id [dict get $u parameter_ids] row [dict get $c value] {
        lappend lines [join [linsert [lmap v $row {format %.9g $v}] 0 $id] \t]
    }
    return [join $lines \n]
}

# Part of the same public authority; transport-only compact parameterless records.
source [file join [file dirname [info script]] statistical_result_table_v1.tcl]
source [file join [file dirname [info script]] statistical_result_column_binding_v1.tcl]
source [file join [file dirname [info script]] statistical_solver_semantics_v1.tcl]
source [file join [file dirname [info script]] statistical_callback_solver_v1.tcl]

source [file join [file dirname [info script]] statistical_replicate_semantics_v1.tcl]

source [file join [file dirname [info script]] statistical_signal_semantics_v1.tcl]
source [file join [file dirname [info script]] statistical_signal_spectral_v1.tcl]

source [file join [file dirname [info script]] statistical_spectral_quality_v1.tcl]

source [file join [file dirname [info script]] statistical_location_semantics_v1.tcl]

source [file join [file dirname [info script]] statistical_result_resource_binding_v1.tcl]

source [file join [file dirname [info script]] statistical_foundation_diagnostics_v1.tcl]

source [file join [file dirname [info script]] statistical_survival_semantics_v1.tcl]

source [file join [file dirname [info script]] statistical_covariance_diagnostics_v1.tcl]

source [file join [file dirname [info script]] statistical_clustering_semantics_v1.tcl]
source [file join [file dirname [info script]] statistical_foundation_regression_v1.tcl]
source [file join [file dirname [info script]] statistical_prediction_uncertainty_v1.tcl]
source [file join [file dirname [info script]] statistical_model_selection_v1.tcl]
source [file join [file dirname [info script]] statistical_nested_f_v1.tcl]
source [file join [file dirname [info script]] statistical_smoother_semantics_v1.tcl]

source [file join [file dirname [info script]] statistical_log_response_v1.tcl]

source [file join [file dirname [info script]] statistical_influence_v1.tcl]

source [file join [file dirname [info script]] statistical_fit_bootstrap_v1.tcl]
source [file join [file dirname [info script]] statistical_fit_profile_v1.tcl]

source [file join [file dirname [info script]] statistical_residual_sequence_v1.tcl]

source [file join [file dirname [info script]] statistical_derived_properties_v1.tcl]

source [file join [file dirname [info script]] statistical_physical_plausibility_v1.tcl]

source [file join [file dirname [info script]] statistical_fit_suggestions_v1.tcl]
source [file join [file dirname [info script]] statistical_gls_v1.tcl]

source [file join [file dirname [info script]] statistical_implicit_v1.tcl]

source [file join [file dirname [info script]] statistical_complex_v1.tcl]

source [file join [file dirname [info script]] statistical_surface_v1.tcl]
source [file join [file dirname [info script]] statistical_rational_v1.tcl]

source [file join [file dirname [info script]] statistical_knot_spline_v1.tcl]

source [file join [file dirname [info script]] statistical_digitization_v1.tcl]
