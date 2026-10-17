function result=gxtxt_statistics_v1(operation,varargin)
% Thin STATISTICAL_RESULT_SEMANTICS_API_v1 facade over the unified Script Bridge.
% Numerical arrays remain in managed binary transport. Interpretation is bounded;
% store_columns streams captured vectors into the existing Document resource owner.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(strcmp(operation,'profile_interpretation'))
    if(numel(varargin)!=2),error('GXTXT:Statistics','Profile interpretation needs source and captured receipt');endif
    if(isfield(varargin{2},'summary')),varargin{2}=varargin{2}.summary;endif
  elseif(strcmp(operation,'bootstrap_interpretation'))
    if(numel(varargin)!=2),error('GXTXT:Statistics','bootstrap_interpretation requires source and Numeric refit receipt');endif
    raw=varargin{2};bounded=struct();
    for key={'schema','method','source_operation','n','p','free_parameter_count','replicates','attempted_count','successful_count','regular_count','boundary_count','rank_failure_count','nonconverged_count','nonfinite_count','solver_error_count','not_completed_count','confidence','seed','next_seed','generator','normal_transform','strategy_version','execution_policy','cancellation_policy','max_seconds','elapsed_seconds','interval_method','interval_policy','quantile_definition','tail_resolution','weight_semantics','simulation_scale_policy','simulation_scale','observation_signature','source_parameters','parameter_ids','source_model_sha256','source_binding_sha256','summary_status','summary_message','messages','parameter_covariance','parameter_standard_errors','ci_lower','ci_upper','original_fit_count','workspace_bytes_bound'}
      name=key{1};if(isfield(raw,name)),bounded.(name)=raw.(name);endif
    endfor
    varargin{2}=bounded;
  elseif(strcmp(operation,'influence_interpretation'))
    if(numel(varargin)!=2),error('GXTXT:Statistics','influence_interpretation requires source and Numeric receipt');endif
    raw=varargin{2};bounded=struct();
    for key={'schema','method','n','p','rank','dof','input_count','weight_semantics','scale_method','residual_scale','near_one_tolerance','leverage_roundoff_count','deletion_available_count','scaled_available_count','maximum_leverage','leverage_sum','maximum_cook_distance','leverage_review_threshold','cook_review_threshold','high_leverage_count','high_cook_count','row_identity','factorization_reused','fit_count','block_rows'}
      name=key{1};if(isfield(raw,name)),bounded.(name)=raw.(name);endif
    endfor
    varargin{2}=bounded;
  elseif(strcmp(operation,'log_response_interpretation'))
    if(numel(varargin)<2||numel(varargin)>3),error('GXTXT:Statistics','log_response_interpretation requires source, Numeric receipt and optional captured prediction interpretation');endif
    raw=varargin{2};bounded=struct();
    for key={'schema','n','reference','base','mean_available','log_standard_deviation','log_bias_correction','interval_kind','confidence','interval_available_count','method'}
      name=key{1};if(isfield(raw,name)),bounded.(name)=raw.(name);endif
    endfor
    varargin{2}=bounded;
  elseif(strcmp(operation,'prediction_interpretation'))
    if(numel(varargin)!=2),error('GXTXT:Statistics','prediction_interpretation requires source result and Numeric receipt');endif
    raw=varargin{2};bounded=struct();
    for key={'numeric_api','operation','plan','query_count','available_count','unavailable_count','critical_value','critical_value_reused','covariance_roundoff_eigenvalues_clipped','model_source_sha256','model_binding_sha256'}
      name=key{1};if(isfield(raw,name)),bounded.(name)=raw.(name);endif
    endfor
    varargin{2}=bounded;
  elseif(strcmp(operation,'from_numeric'))
    if(numel(varargin)<4||numel(varargin)>6),error('GXTXT:Statistics','from_numeric requires 4 to 6 arguments');endif
    varargin{3}=bounded_numeric(varargin{3},varargin{2});
  elseif(strcmp(operation,'from_native_comparison'))
    if(numel(varargin)!=4),error('GXTXT:Statistics','from_native_comparison requires four arguments');endif
    receipt=varargin{2};bounded=struct();
    for field={'count','rmse','mean_absolute','max_absolute','count_a','count_b','sample_budget','sampling_a','sampling_b','projection_exact_a','projection_exact_b','policy','symmetric_rmse','hausdorff_sampled','display_rows','display_is_scientific_data','max_source_index','reference_samples','target_samples','reference_vertices','target_vertices','reference_rms','reference_mean','reference_max','symmetric_rms','reference_tessellated','target_tessellated','sampling_policy','projection_policy','extrema_policy','tessellation'}
      name=field{1};if(isfield(receipt,name)),bounded.(name)=receipt.(name);endif
    endfor
    varargin{2}=bounded;
  elseif(strcmp(operation,'from_numeric_table'))
    if(numel(varargin)<4||numel(varargin)>5),error('GXTXT:Statistics','from_numeric_table requires 4 to 5 arguments');endif
    entries=varargin{3};if(isstruct(entries)),entries=num2cell(entries);endif
    if(!iscell(entries)||isempty(entries)||numel(entries)>8192),error('GXTXT:Statistics','Statistical table requires one to 8192 rows');endif
    total=0;
    for k=1:numel(entries)
      entry=entries{k};if(!isstruct(entry)||!isscalar(entry)||!isfield(entry,'id')||!isfield(entry,'raw')||numel(fieldnames(entry))!=2),error('GXTXT:Statistics','Statistical table row requires exactly id and raw');endif
      entry.raw=bounded_numeric(entry.raw,varargin{2});names=fieldnames(entry.raw);
      for j=1:numel(names),total+=numel(entry.raw.(names{j}));endfor
      if(total>1000000),error('GXTXT:Statistics','Statistical table exceeds one million bounded fact elements');endif
      entries{k}=entry;
    endfor
    varargin{3}=entries;
  endif
  % Standalone scientific modules use the same registered binding in a bounded
  % stateless profile of the existing bridge; no Session or Script Job is made.
  lifetime=gxtxt_statistics_scope_v1();
  result=gxtxt_api_call('STATISTICAL_RESULT_SEMANTICS_API_v1',operation,varargin);
endfunction

function bounded=bounded_numeric(raw,operation)
  if(!isstruct(raw)||!isscalar(raw)),error('GXTXT:Statistics','Numeric result must be a scalar struct');endif
  bounded=struct();
  if(any(strcmp(operation,{'generalized_least_squares','polynomial_gls'})))
    original=raw;
    if(isfield(raw,'gls_summary')),raw=raw.gls_summary;
    elseif(isfield(raw,'summary')),raw=raw.summary;endif
    fields={'schema','numeric_api','operation','coefficients','covariance','standard_errors','whitened_sequence','observation_count','parameter_count','covariance_rank','covariance_nullity','exact_constraint_rank','stochastic_parameter_count','dof','objective','physical_sse','physical_rmse','covariance_semantics','covariance_scale','uncertainty_status','singular_policy','whitening_method','minimum_covariance_eigenvalue','covariance_eigenvalue_cutoff','eigen_relative_tolerance','symmetry_relative_tolerance','constraint_relative_tolerance','covariance_asymmetry','exact_constraint_error','exact_constraint_limit','scaled_design_condition','covariance_sha256','effective_covariance_sha256','observation_signature','nonfinite_policy','row_policy','regularization'};
    facts=struct();
    for k=1:numel(fields),name=fields{k};if(isfield(raw,name)),facts.(name)=raw.(name);endif;endfor
    bounded.gls_summary=facts;
    if(isfield(original,'model'))
      bounded.model=struct();
      for key={'parameter_ids','parameter_units'},name=key{1};if(isfield(original.model,name)),bounded.model.(name)=original.model.(name);endif;endfor
    endif
    return;
  endif
    fields={'count','mean_absolute','max_absolute','hausdorff_sampled','rows','cols','singular_value','component_variance','explained_ratio','cumulative_ratio','component_index','component_count','total_component_variance','standard_uncertainty','input_kind','input_count','output_count','n','p','rank','dof','edf','sse','r_squared','adjusted_r_squared', ...
      'reduced_chi_squared','covariance','standard_errors','condition_number','scaled_coefficients','scaled_covariance','x_center','x_scale', ...
      'converged','response_variance','rmse','mae','max_abs_error','max_absolute','residual_rmse','r2','mean','std', ...
      'relative_n','relative_floor','max_relative_error','rms_relative_error', ...
      'variance','std_sample','variance_sample','std_unbiased','variance_unbiased', ...
      'n_valid','n_positive_weight','covariance_sample','covariance_population','correlation','method', ...
      'solver_receipt','solver','weight_semantics','has_intercept','covariance_scale','fit_geometry', ...
      'knot_summary','rational_summary','surface_summary','complex_summary','implicit_summary','regional_fit','response_rmse','observation_signature','free_parameter_count','fixed_mask','active_bounds','response_count','loss', ...
      'mad','raw_mad','scale','min','max','range','sum','median','q25','q75','iqr','rms','variance_population','std_population', ...
      'standard_error_mean','sampling_standard_error_mean','measurement_standard_error_mean','effective_n','sum_weights','weighted_sum', ...
      'quantiles','probabilities','definition', ...
      'statistic','degrees_of_freedom','n_x','n_y','p_value','estimate','null_value','standard_error', ...
      'ci_lower','ci_upper','test_standard_deviation','interval_margin','effect_size','alternative','confidence','approximation','effect_name','ci_status', ...
      'group_count','group_names','group_counts','group_means','group_variances','group_standard_deviations', ...
      'overall_mean','ss_between','ss_within','ss_total','df_between','df_within','ms_between','ms_within', ...
      'f_statistic','f_numerator_df','f_denominator_df','eta_squared','omega_squared', ...
      'replicates','extreme_count','bootstrap_standard_error','distribution_variance','tail_tolerance','inference','quantile_definition', ...
      'parameter_values','coefficients','parameters'};
    if(any(strcmp(operation,{'fft_spectrum_quality','harmonic_peak_quality','harmonic_components'})))
      fields=[fields,{'N','bin_count','df','coherent_gain','resolved_harmonics','fund_amp','f0','thd_ratio','thd_pct','thd_db','sfdr_db','worst_dbc','worst_amp','worst_freq','sinad_db','enob','noise_floor','noise_floor_dbc','normalization','window','detrend','fundamental_mode','guard_bins','track_harmonics','exclude_dc_bins','spur_search','level_floor','component_method','component_level_floor','fundamental_amplitude'}];
      if(strcmp(operation,'harmonic_components')),fields=[fields,{'component_order','component_expected_frequency','component_frequency','component_frequency_error','component_amplitude','component_level_db','component_percent'}];endif
    endif
    if(any(strcmp(operation,{'signal_snr','signal_spectrum_quality'})))
      fields=[fields,{'snr_db','signal_energy','noise_energy','signal_zero','noise_zero','sample_rate','fundamental_hz','fundamental_bin','harmonic_orders','normalization','fundamental_power','dc_power','harmonic_powers','noise_power','noise_floor_power_per_bin','noise_floor_db_relative','distortion_power','thd','thd_db','thd_plus_n','sinad_db','sfdr_db','enob_bits'}];
    endif
    if(any(strcmp(operation,{'foundation.statistics.bootstrap_ci','foundation.statistics.permutation_test'})))
      fields=[fields,{'estimate','difference','lower','upper','confidence','n_x','n_y','extreme_count','replicates','distribution_variance','bootstrap_standard_error','inference','quantile_definition','alternative','tail_tolerance','seed','random_generator'}];
    endif
    if(any(strcmp(operation,{'foundation.statistics.confidence_interval','foundation.statistics.robust_location'})))
      fields=[fields,{'estimate','lower','upper','confidence','standard_error','degrees_of_freedom','location','scale','iterations','huber_constant','converged','scale_method'}];
    endif
    if(strcmp(operation,'foundation.statistics.kmeans'))
      fields=[fields,{'centroids','cluster_counts','within_ss','total_within_ss','cluster_count','feature_count','replicates','seed','random_generator','backend','backend_version','start_method','empty_action','max_iterations','convergence'}];
    endif
    if(any(strcmp(operation,{'foundation.statistics.robust_regression','foundation.statistics.logistic_regression','foundation.statistics.glm'})))
      fields=[setdiff(fields,{'coefficients','parameters','parameter_values'}),{'coefficients_real','coefficients_imaginary','iterations','last_update_norm','last_threshold','tolerance','iteration_limit','huber_constant','last_scale','family','link','score_norm'}];
    endif
    if(strcmp(operation,'foundation.statistics.covariance_diagnostics'))
      fields=[setdiff(fields,{'covariance'}),{'variable_count','covariance_real','covariance_imaginary','eigenvalues_real','eigenvalues_imaginary'}];
    endif
    if(strcmp(operation,'foundation.statistics.survival_kaplan_meier'))
      fields=[fields,{'time','survival','at_risk','events','censored'}];
    endif
    if(strcmp(operation,'foundation.statistics.partial_correlation'))
      fields=[fields,{'correlation','variable_count','control_count','covariance_rank','normalization_valid'}];
    endif
    if(any(strcmp(operation,{'matrix_statistics','reduce_summary','reduce_accumulate'})))
      fields=[fields,{'input_shape','output_shape','requested_dimension'}];
    endif
    if(any(strcmp(operation,{'signal_periodogram','signal_welch','signal_asd','signal_cross_psd','signal_coherence','signal_frf_h1','signal_frf_h2'})))
      fields=[fields,{'sample_rate','fft_length','bin_count','window_length','overlap_samples','window_count','used_sample_count','spectral_operation','sidedness','detrend','normalization','frequency_hz','psd_real','psd_imaginary','asd','value_real','value_imaginary'}];
    endif
    if(strcmp(operation,'window_metrics'))
      fields=[fields,{'sample_rate','coherent_gain','power_gain','equivalent_noise_bandwidth_hz'}];
    endif
    if(strcmp(operation,'signal_correlation'))
      fields=[fields,{'lag_count','peak_magnitude','peak_value_real','peak_value_imaginary','delay_samples','delay_seconds','sample_rate','normalization','peak_policy','peak_resolved'}];
    endif
    if(any(strcmp(operation,{'event_period','pulse_timing'})))
      fields=[fields,{'crossing_count','period_count','width_count','period','period_seconds','frequency_hz','pulse_width_seconds','duty_cycle','jitter_std_seconds'}];
    endif
    if(strcmp(operation,'signal_summary'))
      fields=[fields,{'peak','peak_to_peak','crest_factor','dc_real','dc_imaginary'}];
    endif
    if(strcmp(operation,'replicate_summary'))
      fields=[fields,{'y_mean','y_median','y_std','y_sem','sigma_within','sigma_between','sigma_total','n','n_sources','within_df','component_coefficient','components_identifiable','between_clamped','lower_std','upper_std','lower_sem','upper_sem','lower_total','upper_total','mode','sampling_model','component_method'}];
    endif
    if(strcmp(operation,'local_cloud_fit'))
      fields=[fields,{'query','local_mean','local_sigma','local_effective_n','local_dof','local_count','local_degree','quadratic_condition','method','variance_correction','insufficient_policy'}];
    endif
    if(strcmp(operation,'welch_aggregate'))
      fields=[fields,{'window_count','bin_count','df','mean_enbw_hz','integrated_power','peak_frequency','peak_psd','zero_level_bins','zero_policy','averaging','peak_policy'}];
    endif
    if(strcmp(operation,'power_level'))
      fields=[fields,{'power','root_power','level_db','reference_rms','zero_policy'}];
    endif
    if(strcmp(operation,'spectral_features'))
      fields=[fields,{'bin_count','df','dominant_frequency','spectral_centroid','rms_frequency','spectral_bandwidth','frequency_05','frequency_50','frequency_85','frequency_95','occupied_bandwidth_90','spectral_flatness','spectral_crest_factor','spectral_entropy','total_power_equivalent','input_semantics','exclude_dc'}];
    endif
    if(strncmp(operation,'array_reduce.',13))
      fields=[fields,{'action','values','n_input','requested_axis','input_shape','probability'}];
    endif
    if(strncmp(operation,'dataset_',8)||strcmp(operation,'statistics_dataset'))
      fields=[fields,{'dataset_id','variable_id','weight_variable_id','x_variable_id','y_variable_id','unit','weight_unit','x_unit','y_unit','selection_id','sigma_x_variable_id','sigma_variable_id','sigma_x_unit','sigma_unit','row_identity'}];
    endif
    for k=1:numel(fields)
      name=fields{k};if(!isfield(raw,name)),continue;endif
      if(numel(raw.(name))>65536),error('GXTXT:Statistics','Result fact %s exceeds the bounded metadata contract',name);endif
      bounded.(name)=raw.(name);
    endfor
    if(isfield(raw,'model')&&isstruct(raw.model)&&isscalar(raw.model))
      bounded.model=struct();
      for field={'source_sha256','binding_sha256'}
        name=field{1};if(isfield(raw.model,name))
          value=raw.model.(name);if(!ischar(value)||isempty(regexp(value,'^[0-9a-f]{64}$','once'))),error('GXTXT:Statistics','Invalid model source digest');endif
          bounded.model.(name)=value;
        endif
      endfor
      for field={'parameter_ids','parameter_units'}
        name=field{1};if(isfield(raw.model,name))
          values=raw.model.(name);
          if(!iscellstr(values)||numel(values)>128||sum(cellfun(@numel,values))>16384),error('GXTXT:Statistics','Invalid bounded model metadata');endif
          bounded.model.(name)=values;
        endif
      endfor
    endif
endfunction
