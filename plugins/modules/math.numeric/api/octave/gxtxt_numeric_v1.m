% GX-TXT NUMERIC_API_v1 public Octave binding.
% SPDX-License-Identifier: GPL-3.0-or-later
%
% out = gxtxt_numeric_v1(operation, ...)
%
% This file is the public Octave binding of the bundled math.numeric service.
% Low-level operations depend only on documented GNU Octave functionality.
% Dataset-aware operations use GX-TXT public Dataset/Table Stream/Selection APIs.
function out = gxtxt_numeric_v1(operation, varargin)
  if (nargin < 1 || !ischar(operation))
    error('GXTXT:Numeric','operation must be a character string');
  endif
  op = lower(strtrim(operation));
  if(!isempty(varargin)&&isstruct(varargin{end})&&isfield(varargin{end},'influence_diagnostics')&&!any(strcmp(op,{'least_squares','linear_regression','polynomial_fit'})))
    error('GXTXT:Numeric:Influence','Exact linear influence is supported only by least_squares, linear_regression and polynomial_fit');
  endif
  switch (op)
    case 'expression_evaluate'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_expression_v1('evaluate',varargin{:});
    case 'expression_analyze'
      require_nargs(op,varargin,1,2);out=gxtxt_numeric_expression_v1('analyze',varargin{:});
    case 'dataset_expression'
      require_nargs(op,varargin,4,5);out=gxtxt_numeric_expression_v1('dataset',varargin{:});
    case 'nested_f_test'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_nested_f_v1(varargin{1});
    case 'fit_bootstrap_prepare'
      require_nargs(op,varargin,5,5);out=gxtxt_numeric_fit_bootstrap_state_v1('prepare',varargin{:});
    case 'fit_bootstrap_draw'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_fit_bootstrap_state_v1('draw',varargin{:});
    case 'fit_bootstrap_summarize'
      require_nargs(op,varargin,5,5);out=gxtxt_numeric_fit_bootstrap_state_v1('summarize',varargin{:});
    case 'fit_profile'
      require_nargs(op,varargin,4,5);out=gxtxt_numeric_fit_profile_v1(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'fit_bootstrap'
      require_nargs(op,varargin,4,5);out=gxtxt_numeric_fit_bootstrap_v1(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'fit_region_catalog'
      require_nargs(op,varargin,0,0);out=gxtxt_numeric_fit_regions_v1('catalog');
    case 'fit_region_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_fit_regions_v1('compose',varargin{1});
    case 'fit_region_selection'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_fit_regions_v1('selection',varargin{1},varargin{2});
    case 'fit_observation_signature'
      require_nargs(op,varargin,1,4);out=gxtxt_numeric_fit_observations_v1(varargin{:});
    case 'fit_information_criteria'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_fit_information_criteria_v1(varargin{1});
    case 'fit_model_catalog'
      require_nargs(op,varargin,0,0);out=gxtxt_numeric_fit_composition_v1('catalog');
    case 'expression_dimensions'
      require_nargs(op,varargin,2,4);
      root=fullfile(fileparts(mfilename('fullpath')),'..','..','..','..','..');addpath(fullfile(root,'core/octave/units'));addpath(fullfile(root,'core/octave/io'));
      output_unit='';unknown_ids={};if(numel(varargin)>2),output_unit=varargin{3};endif;if(numel(varargin)>3),unknown_ids=varargin{4};if(isempty(unknown_ids)),unknown_ids={};endif;endif
      out=gxtxt_unit_expression_dimensions_v1(varargin{1},varargin{2},output_unit,unknown_ids);
    case 'polynomial_gls'
      require_nargs(op,varargin,4,5);out=op_polynomial_gls(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'generalized_least_squares'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_gls_v1(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'fit_characteristics'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_fit_characteristics_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'fit_initial_guess'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_fit_initial_guess_v1(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'fit_formula_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_fit_formula_v1('compose',varargin{1});
    case 'rational_model_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_rational_v1('compose',varargin{1});
    case 'rational_domain'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_rational_v1('domain',varargin{1},varargin{2});
    case 'rational_fit'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_rational_v1('fit',varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'rational_evaluate'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_rational_v1('evaluate',varargin{1},varargin{2},arg_opts(varargin,3));
    case 'rational_residuals'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_rational_v1('residuals',varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'rational_model_state'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_rational_v1('state',varargin{1});
    case 'rational_model_restore'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_rational_v1('restore',varargin{1});
    case 'fit_model_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_fit_composition_v1('compose',varargin{1});
    case {'signal_periodogram','signal_welch','signal_asd'}
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_signal_spectral_v1(op(8:end),varargin{1},[],varargin{2},arg_opts(varargin,3));
    case {'signal_cross_psd','signal_coherence','signal_frf_h1','signal_frf_h2'}
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_signal_spectral_v1(op(8:end),varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'window_metrics'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_window_metrics_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'signal_correlation'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_signal_correlation_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'event_period'
      require_nargs(op,varargin,1,2);out=gxtxt_numeric_event_timing_v1(op,varargin{1},[],arg_opts(varargin,2));
    case 'pulse_timing'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_event_timing_v1(op,varargin{1},varargin{2},arg_opts(varargin,3));
    case 'fft_spectrum_quality'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_fft_spectrum_quality_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'harmonic_peak_quality'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_harmonic_peak_quality_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'harmonic_components'
      require_nargs(op,varargin,4,5);out=gxtxt_numeric_harmonic_components_v1(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case {'signal_snr','signal_spectrum_quality'}
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_signal_quality_v1(op,varargin{1},varargin{2},arg_opts(varargin,3));
    case 'signal_summary'
      require_nargs(op,varargin,1,2);out=gxtxt_numeric_signal_summary_v1(varargin{1},arg_opts(varargin,2));
    case 'replicate_summary'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_replicate_summary_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'local_cloud_fit'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_local_cloud_fit_v1(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'welch_aggregate'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_welch_aggregate_v1(varargin{1},varargin{2},varargin{3});
    case 'power_level'
      require_nargs(op,varargin,1,2);out=op_power_level(varargin{1},arg_opts(varargin,2));
    case 'spectral_features'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_spectral_features_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'list_operations'
      require_nargs(op,varargin,0,0);out=gxtxt_numeric_operation_catalog_v1('list');
    case 'operation_metadata'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_operation_catalog_v1('metadata',varargin{1});
    case 'operation_by_expression_name'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_operation_catalog_v1('expression_name',varargin{1});
    case 'array_unary'
      require_nargs(op,varargin,2,3); out=op_array_unary(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'array_binary'
      require_nargs(op,varargin,3,4); out=op_array_binary(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'positive_translation'
      require_nargs(op,varargin,1,2); out=gxtxt_numeric_positive_translation_v1(varargin{1},arg_opts(varargin,2));
    case 'point_sequence_order'
      require_nargs(op,varargin,1,2); out=gxtxt_numeric_point_sequence_order_v1(varargin{1},arg_opts(varargin,2));
    case 'array_compare'
      require_nargs(op,varargin,3,4); out=op_array_compare(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'array_mask'
      require_nargs(op,varargin,2,4); out=op_array_mask(varargin{1},varargin{2},varargin(3:end));
    case 'array_select'
      require_nargs(op,varargin,2,2); out=op_array_select(varargin{1},varargin{2});
    case 'array_where'
      require_nargs(op,varargin,3,3); out=op_array_where(varargin{1},varargin{2},varargin{3});
    case 'array_reduce'
      require_nargs(op,varargin,2,3); out=op_array_reduce(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'complex_unary'
      require_nargs(op,varargin,3,4); out=op_complex_unary(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'complex_binary'
      require_nargs(op,varargin,5,6); out=op_complex_binary(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'unwrap'
      require_nargs(op,varargin,1,2); out=op_unwrap(varargin{1},arg_opts(varargin,2));
    case {'polar_coordinates','cartesian_coordinates'}
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_polar_coordinates_v1(op,varargin{1},varargin{2},arg_opts(varargin,3));
    case 'interpolate'
      require_nargs(op,varargin,3,4); out=op_interpolate(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'resample'
      require_nargs(op,varargin,3,4); out=op_resample(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'resample_uniform'
      require_nargs(op,varargin,3,4); out=op_resample_uniform(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'spline_create'
      require_nargs(op,varargin,2,3); out=op_spline_create(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'spline_evaluate'
      require_nargs(op,varargin,2,3); out=op_spline_evaluate(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'spline_integral'
      require_nargs(op,varargin,3,4); out=op_spline_integral(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'integrate'
      require_nargs(op,varargin,2,3); out=op_integrate(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'cumulative_integrate'
      require_nargs(op,varargin,2,3); out=op_cumulative_integrate(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'differentiate'
      require_nargs(op,varargin,2,3); out=op_differentiate(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'grid_info'
      require_nargs(op,varargin,1,2); out=op_grid_info(varargin{1},arg_opts(varargin,2));
    case 'validate_monotonic'
      require_nargs(op,varargin,1,2); out=op_validate_monotonic(varargin{1},arg_opts(varargin,2));
    case 'uniform_grid'
      require_nargs(op,varargin,3,4); out=op_uniform_grid(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'common_range'
      require_nargs(op,varargin,2,3); out=op_common_range(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'statistics'
      require_nargs(op,varargin,1,2); out=op_statistics(varargin{1},arg_opts(varargin,2));
    case 'pca_summary'
      require_nargs(op,varargin,2,3); out=gxtxt_numeric_pca_summary_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'resampling_summary'
      require_nargs(op,varargin,2,3); out=gxtxt_numeric_resampling_summary_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'rank'
      require_nargs(op,varargin,1,2); out=op_rank(varargin{1},arg_opts(varargin,2));
    case 'covariance'
      require_nargs(op,varargin,2,3); out=op_covariance(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'correlation'
      require_nargs(op,varargin,2,3); out=op_correlation(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'mad'
      require_nargs(op,varargin,1,2); out=op_mad(varargin{1},arg_opts(varargin,2));
    case 'histogram'
      require_nargs(op,varargin,1,3); edges=[];opts=struct();
      if(numel(varargin)>=2),edges=varargin{2};endif
      if(numel(varargin)>=3),opts=ensure_opts(varargin{3});endif
      out=op_histogram(varargin{1},edges,opts);
    case 'ecdf'
      require_nargs(op,varargin,1,2); out=op_ecdf(varargin{1},arg_opts(varargin,2));
    case 'normal_cdf'
      require_nargs(op,varargin,3,4); out=op_normal_cdf(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'student_t_cdf'
      require_nargs(op,varargin,2,3); out=op_student_t_cdf(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'student_t_quantile'
      require_nargs(op,varargin,2,3); out=op_student_t_quantile(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'derived_properties'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_derived_properties_v1(varargin{1});
    case 'parameter_uncertainty'
      require_nargs(op,varargin,1,1); out=gxtxt_numeric_parameter_uncertainty_v1(varargin{1});
    case 'prediction_uncertainty'
      require_nargs(op,varargin,3,4); out=gxtxt_numeric_prediction_uncertainty_v1(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'hypothesis_test'
      require_nargs(op,varargin,3,4); out=op_hypothesis_test(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'one_way_anova'
      require_nargs(op,varargin,2,3); out=op_one_way_anova(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'f_cdf'
      require_nargs(op,varargin,3,4); out=op_f_cdf(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'matrix_svd'
      require_nargs(op,varargin,1,2); out=op_matrix_svd(varargin{1},arg_opts(varargin,2));
    case 'linear_matrix'
      require_nargs(op,varargin,2,4); other=[];
      if(numel(varargin)>=3),other=varargin{3};endif
      out=gxtxt_numeric_linear_v1(varargin{1},varargin{2},other,arg_opts(varargin,4));
    case 'foundation'
      require_nargs(op,varargin,5,6);
      out=gxtxt_numeric_foundation_v1(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'resample_indices'
      require_nargs(op,varargin,4,5); out=op_resample_indices(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'residual_metrics'
      require_nargs(op,varargin,2,3); out=op_residual_metrics(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'matrix_statistics'
      require_nargs(op,varargin,1,2); out=op_matrix_statistics(varargin{1},arg_opts(varargin,2));
    case 'reduce_summary'
      require_nargs(op,varargin,1,2); out=op_reduce_summary(varargin{1},arg_opts(varargin,2));
    case 'reduce_accumulate'
      require_nargs(op,varargin,2,2); out=op_reduce_accumulate(varargin{1},varargin{2});
    case 'quantiles'
      require_nargs(op,varargin,2,3); out=op_quantiles(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'weighted_quantiles'
      require_nargs(op,varargin,3,4); out=op_weighted_quantiles(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'cumulative_sum'
      require_nargs(op,varargin,1,2); out=op_cumulative_sum(varargin{1},arg_opts(varargin,2));
    case 'vector_normalize'
      require_nargs(op,varargin,1,2); out=op_vector_normalize(varargin{1},arg_opts(varargin,2));
    case 'vector_similarity'
      require_nargs(op,varargin,2,3); out=op_vector_similarity(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'weighted_statistics'
      require_nargs(op,varargin,2,3); out=op_weighted_statistics(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'least_squares'
      require_nargs(op,varargin,2,4); weights=[]; opts=struct();
      if(numel(varargin)>=3),weights=varargin{3};endif
      if(numel(varargin)>=4),opts=ensure_opts(varargin{4});endif
      out=op_least_squares(varargin{1},varargin{2},weights,opts);
    case 'linear_regression'
      require_nargs(op,varargin,2,4); weights=[]; opts=struct();
      if(numel(varargin)>=3),weights=varargin{3};endif
      if(numel(varargin)>=4),opts=ensure_opts(varargin{4});endif
      out=op_linear_regression(varargin{1},varargin{2},weights,opts);
    case 'polynomial_fit'
      require_nargs(op,varargin,3,5); weights=[]; opts=struct();
      if(numel(varargin)>=4),weights=varargin{4};endif
      if(numel(varargin)>=5),opts=ensure_opts(varargin{5});endif
      out=op_polynomial_fit(varargin{1},varargin{2},varargin{3},weights,opts);
    case 'polynomial_evaluate'
      require_nargs(op,varargin,2,3); out=op_polynomial_evaluate(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'surface_model_state'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_surface_v1('state',varargin{1});
    case 'surface_model_restore'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_surface_v1('restore',varargin{1});
    case 'surface_model_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_surface_v1('compose',varargin{1});
    case 'surface_residuals'
      require_nargs(op,varargin,5,5);out=gxtxt_numeric_surface_v1('residuals',varargin{:});
    case 'surface_fit'
      require_nargs(op,varargin,5,5);out=gxtxt_numeric_surface_v1('fit',varargin{:});
    case 'surface_evaluate'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_surface_v1('evaluate',varargin{1},varargin{2},arg_opts(varargin,3));
    case 'surface_grid'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_surface_v1('grid',varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'complex_model_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_complex_v1('compose',varargin{1});
    case 'complex_fit'
      require_nargs(op,varargin,4,5);out=gxtxt_numeric_complex_v1('fit',varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'complex_evaluate'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_complex_v1('evaluate',varargin{1},varargin{2},arg_opts(varargin,3));
    case 'complex_residuals'
      require_nargs(op,varargin,4,4);out=gxtxt_numeric_complex_v1('residuals',varargin{:});
    case 'complex_from_polar'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_complex_v1('from_polar',varargin{1},varargin{2},varargin{3});
    case 'implicit_model_compose'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_implicit_v1('compose',varargin{1});
    case 'implicit_fit'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_implicit_v1('fit',varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'implicit_evaluate'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_implicit_v1('evaluate',varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'implicit_query'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_implicit_v1('query',varargin{1},varargin{2},varargin{3});
    case 'nonlinear_fit'
      require_nargs(op,varargin,4,5); out=op_nonlinear_fit(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'log_ratio'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_log_response_v1(op,varargin{1},struct('reference',varargin{2}));
    case 'log_response_retransform'
      require_nargs(op,varargin,1,2);out=gxtxt_numeric_log_response_v1(op,varargin{1},arg_opts(varargin,2));
    case 'model_export'
      require_nargs(op,varargin,1,2);out=gxtxt_numeric_model_export_v1(varargin{1},arg_opts(varargin,2));
    case 'nonlinear_evaluate'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_nonlinear_evaluate_v1(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'curve_model_fit'
      require_nargs(op,varargin,3,4);out=gxtxt_numeric_curve_models_v1('fit',varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'model_state_decode'
      require_nargs(op,varargin,1,1);out=gxtxt_numeric_model_state_decode_v1(varargin{1});
    case 'fit_input_policy'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_fit_input_policy_v1(varargin{1},varargin{2});
    case 'model_geometry'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_model_geometry_v1(varargin{1},varargin{2});
    case 'model_query'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_model_query_v1(varargin{1},varargin{2},varargin{3});
    case 'model_inverse'
      require_nargs(op,varargin,4,4);out=gxtxt_numeric_model_inverse_v1(varargin{1},varargin{2},varargin{3},varargin{4});
    case 'curve_model_parameter_state'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_curve_parameter_state_v1(varargin{1},varargin{2});
    case 'curve_model_evaluate'
      require_nargs(op,varargin,2,3);out=gxtxt_numeric_curve_models_v1('evaluate',varargin{1},varargin{2},arg_opts(varargin,3));
    case 'curve_model_project'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_curve_models_v1('project',varargin{1},varargin{2},varargin{3});
    case 'curve_model_residual'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_curve_models_v1('residual',varargin{1},varargin{2},varargin{3});
    case 'residual_sequence'
      require_nargs(op,varargin,3,3);out=gxtxt_numeric_residual_sequence_v1(varargin{1},varargin{2},varargin{3});
    case 'smooth'
      require_nargs(op,varargin,2,3); out=op_smooth(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'digital_filter'
      require_nargs(op,varargin,3,4); out=op_digital_filter(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'find_peaks'
      require_nargs(op,varargin,2,3); out=op_find_peaks(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'baseline'
      require_nargs(op,varargin,2,5); ax=[]; ay=[]; opts=struct();
      if(numel(varargin)==3&&isstruct(varargin{3})),opts=ensure_opts(varargin{3});
      elseif(numel(varargin)>=3),ax=varargin{3};endif
      if(numel(varargin)>=4),ay=varargin{4};endif
      if(numel(varargin)>=5),opts=ensure_opts(varargin{5});endif
      out=op_baseline(varargin{1},varargin{2},ax,ay,opts);
    case 'root_find'
      require_nargs(op,varargin,2,3); out=op_root_find(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'minimize_1d'
      require_nargs(op,varargin,2,3); out=op_minimize_1d(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'minimize'
      require_nargs(op,varargin,2,3); out=op_minimize(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'digitization_uncertainty'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_digitization_uncertainty_v1('propagate',varargin{:});
    case 'digitization_covariance'
      require_nargs(op,varargin,2,2);out=gxtxt_numeric_digitization_uncertainty_v1('covariance',varargin{:});
    case 'propagate_uncertainty'
      require_nargs(op,varargin,2,3); out=op_propagate_uncertainty(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'fft'
      require_nargs(op,varargin,1,2); out=op_fft(varargin{1},arg_opts(varargin,2));
    case 'ifft'
      require_nargs(op,varargin,2,3); out=op_ifft(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'analytic_signal'
      require_nargs(op,varargin,1,2); out=op_analytic_signal(varargin{1},arg_opts(varargin,2));
    case 'frequency_grid'
      require_nargs(op,varargin,2,3); out=op_frequency_grid(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'one_sided'
      require_nargs(op,varargin,2,3); out=op_one_sided(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'detrend'
      require_nargs(op,varargin,1,2); out=op_detrend(varargin{1},arg_opts(varargin,2));
    case 'window'
      require_nargs(op,varargin,2,3); out=op_window(varargin{1},varargin{2},arg_opts(varargin,3));
    case 'configure_fft_threads'
      require_nargs(op,varargin,1,1); out=op_configure_fft_threads(varargin{1});

    case 'dataset_integrate'
      require_nargs(op,varargin,4,5); out=op_dataset_integrate(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_array_unary'
      require_nargs(op,varargin,4,5); out=op_dataset_array_unary(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_array_binary'
      require_nargs(op,varargin,5,6); out=op_dataset_array_binary(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'dataset_array_scalar'
      require_nargs(op,varargin,5,6); out=op_dataset_array_scalar(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'dataset_cumulative_integrate'
      require_nargs(op,varargin,4,5); out=op_dataset_cumulative_integrate(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_differentiate'
      require_nargs(op,varargin,4,5); out=op_dataset_differentiate(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_interpolate'
      require_nargs(op,varargin,5,6); out=op_dataset_interpolate(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'dataset_resample'
      require_nargs(op,varargin,5,6); out=op_dataset_resample(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'dataset_resample_uniform'
      require_nargs(op,varargin,5,6); out=op_dataset_resample_uniform(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'dataset_statistics'
      require_nargs(op,varargin,3,4); out=op_dataset_statistics(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'dataset_reduce_summary'
      require_nargs(op,varargin,3,4); out=op_dataset_reduce_summary(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'dataset_weighted_statistics'
      require_nargs(op,varargin,4,5); out=op_dataset_weighted_statistics(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_grid_info'
      require_nargs(op,varargin,3,4); out=op_dataset_grid_info(varargin{1},varargin{2},varargin{3},arg_opts(varargin,4));
    case 'dataset_polynomial_fit'
      require_nargs(op,varargin,5,6); out=op_dataset_polynomial_fit(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},arg_opts(varargin,6));
    case 'dataset_nonlinear_fit'
      require_nargs(op,varargin,6,7); out=op_dataset_nonlinear_fit(varargin{1},varargin{2},varargin{3},varargin{4},varargin{5},varargin{6},arg_opts(varargin,7));
    case 'dataset_smooth'
      require_nargs(op,varargin,4,5); out=op_dataset_smooth(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_find_peaks'
      require_nargs(op,varargin,4,5); out=op_dataset_find_peaks(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    case 'dataset_baseline'
      require_nargs(op,varargin,4,5); out=op_dataset_baseline(varargin{1},varargin{2},varargin{3},varargin{4},arg_opts(varargin,5));
    otherwise
      error('GXTXT:Numeric','unsupported NUMERIC_API_v1 operation: %s',op);
  endswitch
endfunction

% ---------- common validation/options ----------
function require_nargs(op,args,minn,maxn)
  n=numel(args);
  if(n<minn||n>maxn),error('GXTXT:Numeric','%s expects %d..%d arguments after operation; got %d',op,minn,maxn,n);endif
endfunction
function opts=arg_opts(args,index)
  if(numel(args)>=index),opts=ensure_opts(args{index});else opts=struct();endif
endfunction
function opts=ensure_opts(opts)
  if(isempty(opts)),opts=struct();endif
  if(!isstruct(opts)||numel(opts)!=1),error('GXTXT:Numeric','options must be a scalar struct');endif
endfunction
function v=opt(opts,name,default)
  if(isstruct(opts)&&isfield(opts,name)),v=opts.(name);else v=default;endif
endfunction
function tf=opt_has(opts,name),tf=isstruct(opts)&&isfield(opts,name);endfunction
function s=opt_text(opts,name,default)
  v=opt(opts,name,default);
  if(ischar(v)),s=lower(strtrim(v));else s=lower(strtrim(num2str(v)));endif
endfunction
function v=opt_num(opts,name,default)
  q=opt(opts,name,default);
  if(ischar(q)),v=str2double(strtrim(q));else v=double(q);endif
  if(!isscalar(v)||!isreal(v)||!isfinite(v)),error('GXTXT:Numeric','option %s must be a finite real scalar',name);endif
endfunction
function v=opt_int(opts,name,default)
  v=opt_num(opts,name,default);
  if(v!=fix(v)),error('GXTXT:Numeric','option %s must be an integer',name);endif
endfunction
function tf=opt_bool(opts,name,default)
  q=opt(opts,name,default);
  if(islogical(q)&&isscalar(q)),tf=q;return;endif
  if(isnumeric(q)&&isscalar(q)&&isfinite(q)),tf=(q!=0);return;endif
  if(ischar(q))
    q=lower(strtrim(q));
    if(any(strcmp(q,{'1','true','yes','on'}))),tf=true;return;endif
    if(any(strcmp(q,{'0','false','no','off'}))),tf=false;return;endif
  endif
  error('GXTXT:Numeric','option %s must be boolean',name);
endfunction
function v=real_vector(v,name,allow_empty)
  if(nargin<3),allow_empty=false;endif
  if(!(isnumeric(v)||islogical(v))||!isreal(v)||(!isvector(v)&&!isempty(v)))
    error('GXTXT:Numeric','%s must be a real numeric vector',name);
  endif
  v=double(v(:));
  if(!allow_empty&&isempty(v)),error('GXTXT:Numeric','%s must not be empty',name);endif
endfunction
function v=numeric_vector(v,name,allow_empty)
  if(nargin<3),allow_empty=false;endif
  if(!(isnumeric(v)||islogical(v))||(!isvector(v)&&!isempty(v)))
    error('GXTXT:Numeric','%s must be a numeric vector',name);
  endif
  v=double(v(:));
  if(!allow_empty&&isempty(v)),error('GXTXT:Numeric','%s must not be empty',name);endif
endfunction
function A=real_matrix(A,name,allow_empty)
  if(nargin<3),allow_empty=false;endif
  if(!(isnumeric(A)||islogical(A))||!isreal(A)||ndims(A)!=2),error('GXTXT:Numeric','%s must be a real numeric matrix',name);endif
  A=double(A);if(!allow_empty&&isempty(A)),error('GXTXT:Numeric','%s must not be empty',name);endif
endfunction
function [a,b]=paired_vectors(a,b,aname,bname,opts,min_count)
  a=real_vector(a,aname,false);b=real_vector(b,bname,false);
  if(numel(a)!=numel(b)),error('GXTXT:Numeric','%s and %s lengths differ (%d vs %d)',aname,bname,numel(a),numel(b));endif
  policy=nonfinite_policy(opts);good=isfinite(a)&isfinite(b);
  if(any(!good))
    if(strcmp(policy,'omit')),a=a(good);b=b(good);else error('GXTXT:Numeric','%s/%s contain NaN or Inf; set nonfinite=omit explicitly to discard affected pairs',aname,bname);endif
  endif
  if(numel(a)<min_count),error('GXTXT:Numeric','%s/%s require at least %d valid points',aname,bname,min_count);endif
endfunction
function v=finite_vector(v,name,opts,min_count)
  v=real_vector(v,name,false);good=isfinite(v);policy=nonfinite_policy(opts);
  if(any(!good))
    if(strcmp(policy,'omit')),v=v(good);else error('GXTXT:Numeric','%s contains NaN or Inf; set nonfinite=omit explicitly to discard them',name);endif
  endif
  if(numel(v)<min_count),error('GXTXT:Numeric','%s requires at least %d valid values',name,min_count);endif
endfunction
function p=nonfinite_policy(opts)
  p=opt_text(opts,'nonfinite','error');
  if(!any(strcmp(p,{'error','omit'}))),error('GXTXT:Numeric','nonfinite must be error or omit');endif
endfunction
function require_strict_increasing(x,name)
  d=diff(x);
  if(any(d==0)),error('GXTXT:Numeric','%s contains duplicate coordinate values',name);endif
  if(any(d<0)),error('GXTXT:Numeric','%s must be strictly increasing; data are never silently sorted',name);endif
endfunction
function require_function_handle(f,name)
  if(!isa(f,'function_handle')),error('GXTXT:Numeric','%s must be an Octave function handle',name);endif
endfunction
function out=merge_opts(a,b)
  out=a;f=fieldnames(b);for i=1:numel(f),out.(f{i})=b.(f{i});endfor
endfunction
function y=iff(cond,a,b),if(cond),y=a;else y=b;endif,endfunction

% ---------- transforms, detrending and reusable windows ----------
function v=transform_vector(v,name,opts)
  v=numeric_vector(v,name,false);
  policy=nonfinite_policy(opts);
  if(strcmp(policy,'omit'))
    error('GXTXT:Numeric','transform operations do not support nonfinite=omit because omission changes sample coordinates');
  endif
  if(any(!isfinite(v))),error('GXTXT:Numeric','%s contains NaN or Inf',name);endif
endfunction
function mode=transform_normalization(opts)
  mode=opt_text(opts,'normalization','backward');
  if(!any(strcmp(mode,{'backward','forward','unitary'})))
    error('GXTXT:Numeric','normalization must be backward, forward or unitary');
  endif
endfunction
function n=transform_length(opts,default_n)
  n=opt_int(opts,'nfft',default_n);
  if(n<1),error('GXTXT:Numeric','nfft must be a positive integer');endif
endfunction
function z=normalize_transform(z,n,mode,inverse)
  if(strcmp(mode,'forward'))
    if(inverse),z=z*n;else z=z/n;endif
  elseif(strcmp(mode,'unitary'))
    if(inverse),z=z*sqrt(n);else z=z/sqrt(n);endif
  endif
endfunction
function out=op_fft(values,opts)
  x=transform_vector(values,'FFT input',opts);n=transform_length(opts,numel(x));mode=transform_normalization(opts);
  z=fft(x,n);z=normalize_transform(z,n,mode,false);
  out=struct('real',real(z(:)),'imaginary',imag(z(:)),'nfft',n,'input_length',numel(x),'normalization',mode,'ordering','fft');
endfunction
function out=op_ifft(real_values,imaginary_values,opts)
  re=real_vector(real_values,'IFFT real input',false);im=real_vector(imaginary_values,'IFFT imaginary input',false);
  if(numel(re)!=numel(im)),error('GXTXT:Numeric','IFFT real and imaginary input lengths differ');endif
  if(strcmp(nonfinite_policy(opts),'omit')),error('GXTXT:Numeric','transform operations do not support nonfinite=omit because omission changes sample coordinates');endif
  if(any(!isfinite(re))||any(!isfinite(im))),error('GXTXT:Numeric','IFFT input contains NaN or Inf');endif
  n=transform_length(opts,numel(re));mode=transform_normalization(opts);z=ifft(complex(re,im),n);z=normalize_transform(z,n,mode,true);
  out=struct('real',real(z(:)),'imaginary',imag(z(:)),'nfft',n,'input_length',numel(re),'normalization',mode,'ordering','sample');
endfunction
function out=op_analytic_signal(values,opts)
  if(strcmp(nonfinite_policy(opts),'omit')),error('GXTXT:Numeric','analytic_signal does not support nonfinite=omit because omission changes sample coordinates');endif
  x=real_vector(values,'analytic-signal input',false);if(any(!isfinite(x))),error('GXTXT:Numeric','analytic-signal input contains NaN or Inf');endif
  n=numel(x);F=op_fft(x,struct('nfft',n,'normalization','backward','nonfinite','error'));z=complex(F.real,F.imaginary);h=zeros(n,1);h(1)=1;
  if(mod(n,2)==0)
    h(n/2+1)=1;if(n/2>=2),h(2:n/2)=2;endif
  elseif(n>=3)
    h(2:(n+1)/2)=2;
  endif
  q=z.*h;A=op_ifft(real(q),imag(q),struct('nfft',n,'normalization','backward','nonfinite','error'));za=complex(A.real,A.imaginary);
  out=struct('real',real(za(:)),'imaginary',imag(za(:)),'amplitude',abs(za(:)),'n',n,'method','fft_hilbert_multiplier');
endfunction
function out=op_frequency_grid(sample_rate,nfft,opts)
  fs=double(sample_rate);n=double(nfft);
  if(!isscalar(fs)||!isreal(fs)||!isfinite(fs)||fs<=0),error('GXTXT:Numeric','sample_rate must be a finite positive scalar');endif
  if(!isscalar(n)||!isreal(n)||!isfinite(n)||n<1||n!=fix(n)),error('GXTXT:Numeric','nfft must be a positive integer');endif
  representation=opt_text(opts,'representation','two_sided');
  if(!any(strcmp(representation,{'one_sided','two_sided'}))),error('GXTXT:Numeric','representation must be one_sided or two_sided');endif
  ordering=opt_text(opts,'ordering','fft');df=fs/n;
  if(strcmp(representation,'one_sided'))
    if(!strcmp(ordering,'fft')),error('GXTXT:Numeric','one_sided frequency grids use fft ordering');endif
    f=(0:floor(n/2))'*df;
  else
    if(strcmp(ordering,'fft'))
      k=(0:n-1)';cut=ceil(n/2);k(k>=cut)=k(k>=cut)-n;f=k*df;
    elseif(strcmp(ordering,'shifted'))
      k=(-floor(n/2):ceil(n/2)-1)';f=k*df;
    else
      error('GXTXT:Numeric','ordering must be fft or shifted');
    endif
  endif
  out=struct('frequency',double(f(:)),'sample_rate',fs,'nfft',n,'df',df,'nyquist',fs/2,'representation',representation,'ordering',ordering,'has_nyquist',logical(mod(n,2)==0));
endfunction
function out=op_one_sided(real_values,imaginary_values,opts)
  re=real_vector(real_values,'spectrum real part',false);im=real_vector(imaginary_values,'spectrum imaginary part',false);
  if(numel(re)!=numel(im)),error('GXTXT:Numeric','spectrum real and imaginary lengths differ');endif
  if(any(!isfinite(re))||any(!isfinite(im))),error('GXTXT:Numeric','spectrum contains NaN or Inf');endif
  n=opt_int(opts,'nfft',numel(re));if(n<1||numel(re)!=n),error('GXTXT:Numeric','one_sided requires a full spectrum whose length equals nfft');endif
  scaling=opt_text(opts,'scaling','none');if(!any(strcmp(scaling,{'none','amplitude'}))),error('GXTXT:Numeric','one_sided scaling must be none or amplitude');endif
  nh=floor(n/2)+1;z=complex(re(1:nh),im(1:nh));factor=ones(nh,1);
  if(strcmp(scaling,'amplitude')&&nh>1)
    last=nh;if(mod(n,2)==0),last=nh-1;endif
    if(last>=2),factor(2:last)=2;endif
    z=z.*factor;
  endif
  out=struct('real',real(z(:)),'imaginary',imag(z(:)),'factor',factor,'indices',(1:nh)','nfft',n,'bin_count',nh,'scaling',scaling,'has_nyquist',logical(mod(n,2)==0));
endfunction
function out=op_detrend(values,opts)
  if(strcmp(nonfinite_policy(opts),'omit')),error('GXTXT:Numeric','detrending does not support nonfinite=omit because omission changes sample coordinates');endif
  v=real_vector(values,'detrend input',false);if(any(!isfinite(v))),error('GXTXT:Numeric','detrend input contains NaN or Inf');endif
  method=opt_text(opts,'method','mean');
  switch(method)
    case 'none'
      trend=zeros(size(v));y=v;
    case 'mean'
      trend=ones(size(v))*mean(v);y=v-trend;
    case 'linear'
      if(numel(v)<2),error('GXTXT:Numeric','linear detrend requires at least two samples');endif
      x=(0:numel(v)-1)';fit=op_polynomial_fit(x,v,1,[],struct('center_scale',true,'nonfinite','error'));pred=op_polynomial_evaluate(fit,x,struct());trend=double(pred.yq(:));y=v-trend;
    otherwise
      error('GXTXT:Numeric','detrend method must be none, mean or linear');
  endswitch
  out=struct('values',double(y(:)),'trend',double(trend(:)),'method',method,'n',numel(v));
endfunction
function out=op_window(name,n,opts)
  if(!ischar(name)),error('GXTXT:Numeric','window name must be a character string');endif
  name=lower(strtrim(name));n=double(n);if(!isscalar(n)||!isreal(n)||!isfinite(n)||n<1||n!=fix(n)),error('GXTXT:Numeric','window length must be a positive integer');endif
  sampling=opt_text(opts,'sampling','symmetric');if(!any(strcmp(sampling,{'symmetric','periodic'}))),error('GXTXT:Numeric','window sampling must be symmetric or periodic');endif
  if(n==1),w=1;else
    k=(0:n-1)';if(strcmp(sampling,'periodic')),d=n;else d=n-1;endif
    switch(name)
      case 'rectangular',w=ones(n,1);
      case 'hann',w=0.5-0.5*cos(2*pi*k/d);
      case 'hamming',w=0.54-0.46*cos(2*pi*k/d);
      case 'blackman',w=0.42-0.5*cos(2*pi*k/d)+0.08*cos(4*pi*k/d);
      case 'blackman_harris',w=0.35875-0.48829*cos(2*pi*k/d)+0.14128*cos(4*pi*k/d)-0.01168*cos(6*pi*k/d);
      case 'flat_top',w=0.21557895-0.41663158*cos(2*pi*k/d)+0.277263158*cos(4*pi*k/d)-0.083578947*cos(6*pi*k/d)+0.006947368*cos(8*pi*k/d);
      otherwise,error('GXTXT:Numeric','unsupported reusable window: %s',name);
    endswitch
  endif
  w=double(w(:));power_sum=sum(w.^2);coherent_gain=sum(w)/n;rms_gain=sqrt(power_sum/n);
  if(power_sum>0),enbw_bins=n*power_sum/(sum(w)^2);else enbw_bins=Inf;endif
  out=struct('values',w,'name',name,'length',n,'sampling',sampling,'power_sum',power_sum,'coherent_gain',coherent_gain,'rms_gain',rms_gain,'enbw_bins',enbw_bins);
endfunction

% ---------- interpolation, resampling and splines ----------
function method=interp_method(opts)
  method=opt_text(opts,'method','linear');
  if(!any(strcmp(method,{'nearest','linear','cubic','spline','pchip'})))
    error('GXTXT:Numeric','interpolation method must be nearest, linear, cubic, spline or pchip');
  endif
endfunction
function mode=extrap_mode(opts)
  mode=opt_text(opts,'extrapolation','error');
  if(!any(strcmp(mode,{'error','nan','linear','nearest','method'})))
    error('GXTXT:Numeric','extrapolation must be error, nan, linear, nearest or method');
  endif
endfunction
function [x,y]=xy_prepare(x,y,opts,min_count)
  [x,y]=paired_vectors(x,y,'X','Y',opts,min_count);require_strict_increasing(x,'X');
endfunction
function n=interp_min_points(method)
  if(any(strcmp(method,{'cubic','spline','pchip'}))),n=3;else n=2;endif
endfunction
function yq=linear_extrapolate(x,y,xq,yq)
  left=xq<x(1);right=xq>x(end);
  if(any(left)),s=(y(2)-y(1))/(x(2)-x(1));yq(left)=y(1)+s*(xq(left)-x(1));endif
  if(any(right)),s=(y(end)-y(end-1))/(x(end)-x(end-1));yq(right)=y(end)+s*(xq(right)-x(end));endif
endfunction
function out=op_interpolate(x,y,xq,opts)
  method=interp_method(opts);[x,y]=xy_prepare(x,y,opts,interp_min_points(method));
  xq=real_vector(xq,'X query',true);if(any(!isfinite(xq))),error('GXTXT:Numeric','X query contains NaN or Inf');endif
  emode=extrap_mode(opts);outside=(xq<x(1)|xq>x(end));
  if(strcmp(emode,'error')&&any(outside)),error('GXTXT:Numeric','interpolation query lies outside the source X range');endif
  yq=NaN(size(xq));inside=!outside;
  if(any(inside)),yq(inside)=interp1(x,y,xq(inside),method);endif
  if(any(outside))
    if(strcmp(emode,'nearest'))
      yq(xq<x(1))=y(1);yq(xq>x(end))=y(end);
    elseif(strcmp(emode,'linear'))
      yq=linear_extrapolate(x,y,xq,yq);
    elseif(strcmp(emode,'method'))
      yq(outside)=interp1(x,y,xq(outside),method,'extrap');
    endif
  endif
  out=struct('xq',xq,'yq',double(yq(:)),'method',method,'extrapolation',emode,'n_source',numel(x),'n_query',numel(xq),'kernel','octave.interp1');
endfunction
function out=op_resample(x,y,xq,opts)
  r=op_interpolate(x,y,xq,opts);
  out=struct('x',r.xq,'y',r.yq,'method',r.method,'extrapolation',r.extrapolation,'n_source',r.n_source,'n_output',r.n_query,'grid_kind','explicit');
endfunction
function out=op_resample_uniform(x,y,step,opts)
  [x,y]=xy_prepare(x,y,opts,2);step=double(step);
  if(!isscalar(step)||!isreal(step)||!isfinite(step)||step<=0),error('GXTXT:Numeric','resampling step must be a finite positive scalar');endif
  start=opt_num(opts,'start',x(1));stop=opt_num(opts,'stop',x(end));
  if(stop<start),error('GXTXT:Numeric','resampling stop must be >= start');endif
  g=op_uniform_grid(start,stop,step,struct('mode','step'));
  r=op_resample(x,y,g.x,opts);
  out=struct('x',r.x,'y',r.y,'step',g.step,'start',start,'stop_requested',stop,'stop_actual',g.stop_actual,'n_source',numel(x),'n_output',numel(r.x),'method',r.method,'extrapolation',r.extrapolation,'grid_kind','uniform');
endfunction
function out=op_spline_create(x,y,opts)
  method=opt_text(opts,'method','spline');
  if(!any(strcmp(method,{'spline','pchip'}))),error('GXTXT:Numeric','spline model method must be spline or pchip');endif
  [x,y]=xy_prepare(x,y,opts,3);
  if(strcmp(method,'spline')),pp=spline(x,y);else pp=pchip(x,y);endif
  [breaks,coefs,pieces,order,dim]=unmkpp(pp);
  out=struct('model_type','piecewise_polynomial','method',method,'breaks',double(breaks(:)),'coefficients',double(coefs),'pieces',pieces,'order',order,'dimension',dim,'x_min',x(1),'x_max',x(end));
endfunction
function pp=portable_model_to_pp(model)
  if(!isstruct(model)||numel(model)!=1),error('GXTXT:Numeric','spline model must be a scalar struct returned by spline_create');endif
  req={'breaks','coefficients','pieces','order','dimension'};
  for i=1:numel(req),if(!isfield(model,req{i})),error('GXTXT:Numeric','spline model is missing field %s',req{i});endif,endfor
  br=real_vector(model.breaks,'spline breaks',false);cf=real_matrix(model.coefficients,'spline coefficients',false);
  pieces=double(model.pieces);order=double(model.order);dim=double(model.dimension);
  if(numel(br)!=pieces+1||rows(cf)!=pieces||columns(cf)!=order),error('GXTXT:Numeric','invalid spline model dimensions');endif
  pp=mkpp(br.',cf,dim);
endfunction
function ppd=pp_derivative_local(pp,n)
  if(n<0||n!=fix(n)),error('GXTXT:Numeric','derivative_order must be a non-negative integer');endif
  ppd=pp;
  for q=1:n
    [br,c,p,o,d]=unmkpp(ppd);
    if(o<=1),c=zeros(p,1);o=1;else powers=(o-1):-1:1;c=c(:,1:o-1).*repmat(powers,p,1);o=o-1;endif
    ppd=mkpp(br,c,d);
  endfor
endfunction
function ppi=pp_integral_local(pp)
  [br,c,p,o,d]=unmkpp(pp);nc=zeros(p,o+1);powers=o:-1:1;nc(:,1:o)=c./repmat(powers,p,1);
  constant=0;
  for i=1:p
    nc(i,end)=constant;
    h=br(i+1)-br(i);constant=polyval(nc(i,:),h);
  endfor
  ppi=mkpp(br,nc,d);
endfunction
function out=op_spline_evaluate(model,xq,opts)
  pp=portable_model_to_pp(model);xq=real_vector(xq,'X query',true);if(any(!isfinite(xq))),error('GXTXT:Numeric','X query contains NaN or Inf');endif
  [br,~,~,~,~]=unmkpp(pp);emode=opt_text(opts,'extrapolation','error');if(!any(strcmp(emode,{'error','nan','method'}))),error('GXTXT:Numeric','spline extrapolation must be error, nan or method');endif
  outside=xq<br(1)|xq>br(end);if(strcmp(emode,'error')&&any(outside)),error('GXTXT:Numeric','spline query lies outside the model range');endif
  dorder=opt_int(opts,'derivative_order',0);if(dorder<0),error('GXTXT:Numeric','derivative_order must be >= 0');endif
  ppd=pp_derivative_local(pp,dorder);values=NaN(size(xq));inside=!outside;
  if(any(inside)),values(inside)=ppval(ppd,xq(inside));endif
  if(strcmp(emode,'method')&&any(outside)),values(outside)=ppval(ppd,xq(outside));endif
  method='';if(isfield(model,'method')),method=model.method;endif
  out=struct('xq',xq,'values',double(values(:)),'derivative_order',dorder,'method',method,'extrapolation',emode);
endfunction
function out=op_spline_integral(model,a,b,opts)
  pp=portable_model_to_pp(model);a=double(a);b=double(b);
  if(!isscalar(a)||!isscalar(b)||!isfinite(a)||!isfinite(b)),error('GXTXT:Numeric','spline integration bounds must be finite scalars');endif
  [br,~,~,~,~]=unmkpp(pp);emode=opt_text(opts,'extrapolation','error');if(!any(strcmp(emode,{'error','method'}))),error('GXTXT:Numeric','spline integral extrapolation must be error or method');endif
  if(strcmp(emode,'error')&&(a<br(1)||a>br(end)||b<br(1)||b>br(end))),error('GXTXT:Numeric','spline integration bounds lie outside the model range');endif
  ppi=pp_integral_local(pp);value=ppval(ppi,b)-ppval(ppi,a);
  out=struct('value',double(value),'a',a,'b',b,'method','analytic_piecewise_polynomial');
endfunction

% ---------- calculus, grids, ranges ----------
function out=op_integrate(x,y,opts)
  [x,y]=xy_prepare(x,y,opts,2);value=trapz(x,y);
  if(!isfinite(value)),error('GXTXT:Numeric','trapezoidal integration did not produce a finite result');endif
  out=struct('value',double(value),'n',numel(x),'x_min',x(1),'x_max',x(end),'method','trapezoidal','kernel','octave.trapz');
endfunction
function out=op_cumulative_integrate(x,y,opts)
  [x,y]=xy_prepare(x,y,opts,2);v=cumtrapz(x,y);
  if(any(!isfinite(v))),error('GXTXT:Numeric','cumulative trapezoidal integration did not produce finite values');endif
  out=struct('x',x,'integral',double(v(:)),'n',numel(x),'method','cumulative_trapezoidal');
endfunction
function out=op_differentiate(x,y,opts)
  [x,y]=xy_prepare(x,y,opts,2);d=gradient(y,x);
  if(any(!isfinite(d))),error('GXTXT:Numeric','numerical differentiation did not produce finite values');endif
  out=struct('x',x,'dy_dx',double(d(:)),'n',numel(x),'method','centered_secant_with_endpoint_secants','kernel','octave.gradient');
endfunction
function out=op_grid_info(x,opts)
  x=finite_vector(x,'X',opts,1);n=numel(x);rtol=opt_num(opts,'rtol',1e-9);atol=opt_num(opts,'atol',0);
  if(rtol<0||atol<0),error('GXTXT:Numeric','grid tolerances must be non-negative');endif
  if(n==1)
    out=struct('n',1,'uniform',false,'step',NaN,'step_mean',NaN,'step_median',NaN,'step_min',NaN,'step_max',NaN,'step_std',NaN,'direction','indeterminate','monotonic',false,'strict_monotonic',false,'duplicate_count',0,'max_step_deviation',NaN,'relative_max_step_deviation',NaN,'rtol',rtol,'atol',atol);return;
  endif
  d=diff(x);dups=sum(d==0);
  if(all(d>0)),direction='increasing';monotonic=true;strict=true;
  elseif(all(d<0)),direction='decreasing';monotonic=true;strict=true;
  elseif(all(d>=0)||all(d<=0)),direction='non_strict';monotonic=true;strict=false;
  else direction='non_monotonic';monotonic=false;strict=false;endif
  step=median(d);dev=max(abs(d-step));scale=max([abs(step);abs(d);1]);rel=dev/scale;
  uniform=(dups==0)&&strict&&all(abs(d-step)<=atol+rtol.*max(abs(step),abs(d)));
  if(numel(d)>1),sd=std(d,0);else sd=0;endif
  out=struct('n',n,'uniform',logical(uniform),'step',step,'step_mean',mean(d),'step_median',median(d),'step_min',min(d),'step_max',max(d),'step_std',sd,'direction',direction,'monotonic',logical(monotonic),'strict_monotonic',logical(strict),'duplicate_count',dups,'max_step_deviation',dev,'relative_max_step_deviation',rel,'rtol',rtol,'atol',atol);
endfunction
function out=op_validate_monotonic(x,opts)
  g=op_grid_info(x,opts);out=struct('n',g.n,'monotonic',g.monotonic,'strict_monotonic',g.strict_monotonic,'direction',g.direction,'duplicate_count',g.duplicate_count);
endfunction
function out=op_uniform_grid(startv,stopv,spacing,opts)
  startv=double(startv);stopv=double(stopv);spacing=double(spacing);
  if(!isscalar(startv)||!isscalar(stopv)||!isscalar(spacing)||!isfinite(startv)||!isfinite(stopv)||!isfinite(spacing)),error('GXTXT:Numeric','uniform-grid arguments must be finite scalars');endif
  if(stopv<startv),error('GXTXT:Numeric','uniform-grid stop must be >= start');endif
  mode=opt_text(opts,'mode','step');
  if(strcmp(mode,'step'))
    if(spacing<=0),error('GXTXT:Numeric','uniform-grid step must be positive');endif
    span=stopv-startv;tol=64*eps(max([1 abs(startv) abs(stopv) abs(spacing)]));n=floor((span+tol)/spacing)+1;x=startv+(0:n-1)'*spacing;if(!isempty(x)&&x(end)>stopv+tol),x(end)=[];endif;step=spacing;
  elseif(strcmp(mode,'count'))
    n=spacing;if(n<1||n!=fix(n)),error('GXTXT:Numeric','uniform-grid count must be a positive integer');endif
    if(n==1),x=startv;step=NaN;else x=linspace(startv,stopv,n).';step=(stopv-startv)/(n-1);endif
  else error('GXTXT:Numeric','uniform-grid mode must be step or count');endif
  out=struct('x',double(x(:)),'n',numel(x),'step',step,'start',startv,'stop_requested',stopv,'stop_actual',x(end),'mode',mode);
endfunction
function out=op_common_range(x1,x2,opts)
  x1=finite_vector(x1,'X1',opts,1);x2=finite_vector(x2,'X2',opts,1);x1min=min(x1);x1max=max(x1);x2min=min(x2);x2max=max(x2);lo=max(x1min,x2min);hi=min(x1max,x2max);overlap=(hi>=lo);
  if(overlap),rmin=lo;rmax=hi;width=hi-lo;else rmin=NaN;rmax=NaN;width=0;endif
  out=struct('overlap',logical(overlap),'min',rmin,'max',rmax,'width',width,'x1_min',x1min,'x1_max',x1max,'x2_min',x2min,'x2_max',x2max);
endfunction

% ---------- descriptive and weighted statistics ----------
function q=quantile_type7(v,p)
  v=sort(v(:));n=numel(v);p=p(:);q=zeros(size(p));
  for i=1:numel(p)
    if(p(i)<0||p(i)>1||!isfinite(p(i))),error('GXTXT:Numeric','quantile probabilities must be finite and within [0,1]');endif
    if(n==1),q(i)=v(1);continue;endif
    h=1+(n-1)*p(i);j=floor(h);g=h-j;
    if(j>=n),q(i)=v(n);else q(i)=(1-g)*v(j)+g*v(j+1);endif
  endfor
endfunction
function out=op_quantiles(v,p,opts)
  v=finite_vector(v,'values',opts,1);p=real_vector(p,'probabilities',true);if(any(!isfinite(p))||any(p<0)||any(p>1)),error('GXTXT:Numeric','quantile probabilities must be within [0,1]');endif
  q=quantile_type7(v,p);out=struct('probabilities',p,'quantiles',q,'n',numel(v),'definition','Hyndman-Fan type 7 linear interpolation');
endfunction
function out=op_cumulative_sum(v,opts)
  v=finite_vector(v,'values',opts,1);
  c=cumsum(v);
  out=struct('values',double(c(:)),'total',double(c(end)),'n',numel(v),'method','cumulative_sum');
endfunction

function out=op_vector_normalize(v,opts)
  v=finite_vector(v,'values',opts,1);method=opt_text(opts,'method','unit_vector');center=0;
  if(strcmp(method,'mean_center_unit_vector'))
    center=mean(v);work=v-center;
  elseif(strcmp(method,'unit_vector'))
    work=v;
  else
    error('GXTXT:Numeric','vector normalization method must be unit_vector or mean_center_unit_vector');
  endif
  norm_value=sqrt(sum(work.^2));if(!isfinite(norm_value)||norm_value<=0),error('GXTXT:Numeric','cannot normalize a zero-norm vector');endif
  out=struct('values',double(work(:)./norm_value),'norm',double(norm_value),'center',double(center),'n',numel(v),'method',method);
endfunction
function out=op_vector_similarity(a,b,opts)
  a=finite_vector(a,'A',opts,2);b=finite_vector(b,'B',opts,2);if(numel(a)!=numel(b)),error('GXTXT:Numeric','vector similarity inputs must have equal length');endif
  method=opt_text(opts,'method','cosine');work_a=a;work_b=b;
  if(strcmp(method,'pearson'))
    work_a=a-mean(a);work_b=b-mean(b);
  elseif(!any(strcmp(method,{'cosine','angular_similarity','normalized_residual'})))
    error('GXTXT:Numeric','vector similarity method must be cosine, pearson, angular_similarity or normalized_residual');
  endif
  na=sqrt(sum(work_a.^2));nb=sqrt(sum(work_b.^2));if(na<=0||nb<=0||!isfinite(na)||!isfinite(nb)),error('GXTXT:Numeric','vector similarity is undefined for zero-norm input');endif
  cosine=sum(work_a.*work_b)/(na*nb);cosine=max(-1,min(1,cosine));
  if(strcmp(method,'cosine')||strcmp(method,'pearson'))
    score=cosine;
  elseif(strcmp(method,'angular_similarity'))
    score=1-acos(cosine)/pi;
  else
    residual=sqrt(sum((a-b).^2)/sum(a.^2));score=1/(1+residual);
  endif
  out=struct('score',double(score),'cosine',double(cosine),'n',numel(a),'method',method);
endfunction

function out=op_statistics(v,opts)
  empty_policy=opt_text(opts,'empty_policy','error');
  if(!any(strcmp(empty_policy,{'error','undefined'}))),error('GXTXT:Numeric','statistics empty_policy must be error or undefined');endif
  n_input=numel(v);v=finite_vector(v,'values',opts,!strcmp(empty_policy,'undefined'));n=numel(v);
  if(n==0)
    out=struct('n',0,'n_input',n_input,'n_valid',0,'n_nonfinite',n_input);
    for field={'min','max','max_absolute','range','sum','mean','median','q25','q75','iqr','variance_population','std_population','variance_sample','std_sample','rms','standard_error_mean'}
      out.(field{1})=NaN;
    endfor
    return;
  endif
  m=mean(v);vp=mean((v-m).^2);qs=quantile_type7(v,[0.25;0.5;0.75]);
  if(n>1),vs=sum((v-m).^2)/(n-1);else vs=NaN;endif
  out=struct('n',n,'n_input',n_input,'n_valid',n,'n_nonfinite',n_input-n,'min',min(v),'max',max(v),'max_absolute',max(abs(v)),'range',max(v)-min(v),'sum',sum(v),'mean',m,'median',qs(2),'q25',qs(1),'q75',qs(3),'iqr',qs(3)-qs(1),'variance_population',vp,'std_population',sqrt(vp),'variance_sample',vs,'std_sample',sqrt(vs),'rms',sqrt(mean(v.^2)));
  out.standard_error_mean=sqrt(vs/n);
endfunction
function [x,y,n_input,n_valid]=finite_pair(x,y,opts,min_count)
  x=real_vector(x,'first values',false);y=real_vector(y,'second values',false);
  if(numel(x)!=numel(y)),error('GXTXT:Numeric','paired vectors have different lengths');endif
  n_input=numel(x);good=isfinite(x)&isfinite(y);
  if(any(!good))
    if(strcmp(nonfinite_policy(opts),'omit')),x=x(good);y=y(good);
    else error('GXTXT:Numeric','paired vectors contain NaN or Inf; set nonfinite=omit explicitly');endif
  endif
  n_valid=numel(x);
  if(n_valid<min_count),error('GXTXT:Numeric','paired vectors require at least %d valid observations',min_count);endif
endfunction
function ranks=rank_average(values)
  n=numel(values);[ordered,index]=sort(values(:));ranks=zeros(n,1);i=1;
  while(i<=n)
    j=i;while(j<n&&ordered(j+1)==ordered(i)),j+=1;endwhile
    ranks(index(i:j))=(i+j)/2;i=j+1;
  endwhile
endfunction
function out=op_rank(values,opts)
  values=real_vector(values,'values',false);n_input=numel(values);good=isfinite(values);
  if(any(!good)&&!strcmp(nonfinite_policy(opts),'omit')),error('GXTXT:Numeric','rank values contain NaN or Inf');endif
  valid=values(good);if(isempty(valid)),error('GXTXT:Numeric','rank requires a valid value');endif
  method=opt_text(opts,'ties','average');if(!any(strcmp(method,{'average','min','max','dense'}))),error('GXTXT:Numeric','rank ties must be average, min, max or dense');endif
  [ordered,index]=sort(valid);r=zeros(numel(valid),1);i=1;dense=0;
  while(i<=numel(valid))
    j=i;while(j<numel(valid)&&ordered(j+1)==ordered(i)),j+=1;endwhile
    dense+=1;
    switch(method)
      case 'average',value=(i+j)/2;
      case 'min',value=i;
      case 'max',value=j;
      case 'dense',value=dense;
    endswitch
    r(index(i:j))=value;i=j+1;
  endwhile
  result=NaN(n_input,1);result(good)=r;
  out=struct('ranks',result,'n_input',n_input,'n_valid',numel(valid),'n_nonfinite',n_input-numel(valid),'ties',method);
endfunction
function out=op_covariance(x,y,opts)
  [x,y,n_input,n_valid]=finite_pair(x,y,opts,1);
  centered_x=x-mean(x);centered_y=y-mean(y);cross=sum(centered_x.*centered_y);
  sample=NaN;if(n_valid>1),sample=cross/(n_valid-1);endif
  out=struct('covariance_population',cross/n_valid,'covariance_sample',sample, ...
    'n_input',n_input,'n_valid',n_valid,'n_nonfinite',n_input-n_valid,'missing_pair_policy','pairwise');
endfunction
function out=op_correlation(x,y,opts)
  [x,y,n_input,n_valid]=finite_pair(x,y,opts,2);
  method=opt_text(opts,'method','pearson');
  if(strcmp(method,'spearman')),x=rank_average(x);y=rank_average(y);
  elseif(!strcmp(method,'pearson')),error('GXTXT:Numeric','correlation method must be pearson or spearman');endif
  centered_x=x-mean(x);centered_y=y-mean(y);
  denominator=sqrt(sum(centered_x.^2)*sum(centered_y.^2));
  if(denominator==0),value=NaN;status='undefined_zero_variance';
  else value=sum(centered_x.*centered_y)/denominator;value=max(-1,min(1,value));status='ok';endif
  out=struct('correlation',value,'method',method,'status',status,'n_input',n_input, ...
    'n_valid',n_valid,'n_nonfinite',n_input-n_valid,'missing_pair_policy','pairwise','tie_method','average');
endfunction
function out=op_mad(values,opts)
  n_input=numel(values);values=finite_vector(values,'values',opts,1);
  scaling=opt_text(opts,'scale','raw');
  if(!any(strcmp(scaling,{'raw','normal_consistency'}))),error('GXTXT:Numeric','MAD scale must be raw or normal_consistency');endif
  center=quantile_type7(values,0.5);raw=quantile_type7(abs(values-center),0.5);
  factor=1;if(strcmp(scaling,'normal_consistency')),factor=1/0.6744897501960817;endif
  out=struct('mad',raw*factor,'raw_mad',raw,'median',center,'scale',scaling, ...
    'scale_factor',factor,'n_input',n_input,'n_valid',numel(values),'n_nonfinite',n_input-numel(values));
endfunction
function out=op_histogram(values,edges,opts)
  n_input=numel(values);values=finite_vector(values,'values',opts,1);
  mode=opt_text(opts,'bin_mode','auto');
  if(!any(strcmp(mode,{'auto','count','width','edges'}))),error('GXTXT:Numeric','histogram bin_mode must be auto, count, width or edges');endif
  if(strcmp(mode,'edges'))
    edges=real_vector(edges,'edges',false);
    if(numel(edges)<2||any(!isfinite(edges))||any(diff(edges)<=0)),error('GXTXT:Numeric','histogram edges must be finite and strictly increasing');endif
  else
    if(!isempty(edges)),error('GXTXT:Numeric','explicit edges require bin_mode=edges');endif
    lo=min(values);hi=max(values);
    if(lo==hi),lo-=0.5;hi+=0.5;endif
    if(strcmp(mode,'auto')),nbins=max(1,ceil(sqrt(numel(values))));
    elseif(strcmp(mode,'count')),nbins=opt_int(opts,'bin_count',0);
    else
      width=opt_num(opts,'bin_width',0);
      if(width<=0),error('GXTXT:Numeric','bin_width must be positive');endif
      nbins=max(1,ceil((hi-lo)/width));hi=lo+nbins*width;
    endif
    if(nbins<1||nbins>1000000),error('GXTXT:Numeric','histogram bin count must be from 1 to 1000000');endif
    edges=linspace(lo,hi,nbins+1).';
  endif
  raw=histc(values,edges);counts=raw(1:end-1);counts(end)+=raw(end);
  counts=counts(:);n_valid=numel(values);n_inside=sum(counts);centers=(edges(1:end-1)+edges(2:end))/2;
  out=struct('edges',edges(:),'centers',centers(:),'counts',counts, ...
    'relative_frequency',counts/n_valid,'cumulative_frequency',cumsum(counts)/n_valid, ...
    'bin_mode',mode,'n_input',n_input,'n_valid',n_valid,'n_nonfinite',n_input-n_valid, ...
    'n_inside',n_inside,'n_outside',n_valid-n_inside);
endfunction
function out=op_ecdf(values,opts)
  n_input=numel(values);values=finite_vector(values,'values',opts,1);
  [support,~,groups]=unique(values(:));counts=accumarray(groups,1,[numel(support),1]);
  n_valid=numel(values);
  out=struct('support',support(:),'counts',counts(:),'probability',cumsum(counts)/n_valid, ...
    'n_input',n_input,'n_valid',n_valid,'n_nonfinite',n_input-n_valid);
endfunction
function out=op_residual_metrics(observed,predicted,opts)
  if(!isnumeric(observed)||!isreal(observed)||!isvector(observed)||isempty(observed)|| ...
     !isnumeric(predicted)||!isreal(predicted)||!isvector(predicted)||numel(observed)!=numel(predicted))
    error('GXTXT:Numeric','residual_metrics requires equal non-empty real vectors');
  endif
  observed=double(observed(:));predicted=double(predicted(:));
  if(any(!isfinite(observed))||any(!isfinite(predicted)))
    error('GXTXT:Numeric','residual_metrics requires finite observed and predicted values');
  endif
  floor_value=opt_num(opts,'relative_floor',0);
  if(floor_value<0),error('GXTXT:Numeric','relative_floor must be non-negative');endif
  residual=predicted-observed;absolute=abs(residual);n=numel(residual);
  sse=sum(residual.^2);mu=mean(observed);sst=sum((observed-mu).^2);
  r2=NaN;if(n>=2&&sst>0),r2=1-sse/sst;endif
  max_relative=NaN;rms_relative=NaN;
  mask=(observed!=0)&(abs(observed)>=floor_value);
  if(any(mask))
    rel=absolute(mask)./abs(observed(mask));
    max_relative=max(rel);rms_relative=sqrt(mean(rel.^2));
  endif
  out=struct('n',n,'sse',sse,'mse',sse/n,'rmse',sqrt(sse/n),'mae',mean(absolute), ...
    'max_abs_error',max(absolute),'r2',r2,'response_variance',sst/n, ...
    'max_relative_error',max_relative,'rms_relative_error',rms_relative, ...
    'relative_n',sum(mask),'relative_floor',floor_value);
endfunction
function out=op_matrix_statistics(v,opts)
  if(!isnumeric(v)||!isreal(v)||isempty(v)||ndims(v)>2||any(!isfinite(v(:))))
    error('GXTXT:Numeric','matrix_statistics requires a non-empty finite real matrix');
  endif
  dim=1;if(isfield(opts,'dimension')),dim=opts.dimension;endif
  if(!isscalar(dim)||!any(dim==[1,2]))
    error('GXTXT:Numeric','matrix_statistics dimension must be 1 or 2');
  endif
  v=double(v);n=size(v,dim);mu=mean(v,dim);med=median(v,dim);
  vp=mean(bsxfun(@minus,v,mu).^2,dim);
  if(n>1),vs=vp*n/(n-1);else vs=NaN(size(mu));endif
  out=struct('n',n,'mean',mu,'median',med,'variance_population',vp, ...
    'std_population',sqrt(vp),'variance_sample',vs,'std_sample',sqrt(vs), ...
    'min',min(v,[],dim),'max',max(v,[],dim),'requested_dimension',dim,'input_shape',size(v),'output_shape',size(mu));
endfunction
function out=op_reduce_summary(v,opts)
  if(!isnumeric(v)||!isreal(v)||isempty(v)||ndims(v)>2||any(!isfinite(v(:))))
    error('GXTXT:Numeric','reduce_summary requires a non-empty finite real vector or matrix');
  endif
  v=double(v);
  if(isvector(v)&&!isfield(opts,'dimension'))
    n=numel(v);total=sum(v(:));lo=min(v(:));hi=max(v(:));
  else
    dim=1;if(isfield(opts,'dimension')),dim=opts.dimension;endif
    if(!isscalar(dim)||!any(dim==[1,2])),error('GXTXT:Numeric','reduce_summary dimension must be 1 or 2');endif
    n=size(v,dim);total=sum(v,dim);lo=min(v,[],dim);hi=max(v,[],dim);
  endif
  requested=0;if(isfield(opts,'dimension')||!isvector(v)),requested=dim;endif
  out=struct('count',n,'sum',total,'mean',total/n,'min',lo,'max',hi,'requested_dimension',requested,'input_shape',size(v),'output_shape',size(total));
endfunction
function out=op_reduce_accumulate(state,v)
  s=op_reduce_summary(v,struct());
  if(isempty(state))
    out=s;return;
  endif
  if(!isstruct(state)||!all(isfield(state,{'count','sum','min','max'})) || ...
      !isscalar(state.count)||!isscalar(state.sum)||!isscalar(state.min)||!isscalar(state.max) || ...
      !isfinite(state.count)||state.count<1||state.count!=fix(state.count))
    error('GXTXT:Numeric','reduce_accumulate requires a valid scalar summary state');
  endif
  out=struct('count',state.count+s.count,'sum',state.sum+s.sum, ...
    'min',min(state.min,s.min),'max',max(state.max,s.max));
  out.mean=out.sum/out.count;
endfunction
function out=op_configure_fft_threads(n)
  if(!isnumeric(n)||!isscalar(n)||!isfinite(n)||n<1||n!=fix(n))
    error('GXTXT:Numeric','configure_fft_threads requires a positive integer');
  endif
  out=struct('requested',n,'applied',false,'backend','none');
  if(exist('fftw','builtin')||exist('fftw','file'))
    try
      fftw('threads',n);out.applied=true;out.backend='fftw';
    catch
      % Some Octave builds expose FFTW without a thread-setting capability.
    end_try_catch
  endif
endfunction
function q=weighted_quantile_step(v,w,p)
  [v,idx]=sort(v(:));w=w(idx);cw=cumsum(w);sw=cw(end);p=p(:);q=zeros(size(p));
  for i=1:numel(p)
    if(p(i)<0||p(i)>1||!isfinite(p(i))),error('GXTXT:Numeric','quantile probabilities must be finite and within [0,1]');endif
    target=p(i)*sw;j=find(cw>=target,1,'first');if(isempty(j)),j=numel(v);endif;if(p(i)==0),j=1;endif;q(i)=v(j);
  endfor
endfunction
function [v,w,n_total,n_input,n_valid]=prepare_weighted(v,w,opts)
  v=real_vector(v,'values',false);w=real_vector(w,'weights',false);if(numel(v)!=numel(w)),error('GXTXT:Numeric','values and weights lengths differ (%d vs %d)',numel(v),numel(w));endif
  n_input=numel(v);
  good=isfinite(v)&isfinite(w);policy=nonfinite_policy(opts);
  if(any(!good)),if(strcmp(policy,'omit')),v=v(good);w=w(good);else error('GXTXT:Numeric','values/weights contain NaN or Inf; set nonfinite=omit explicitly to discard affected pairs');endif,endif
  n_total=numel(v);n_valid=n_total;
  if(any(w<0)),error('GXTXT:Numeric','weights must be non-negative');endif
  keep=w>0;v=v(keep);w=w(keep);if(isempty(w)),error('GXTXT:Numeric','at least one weight must be positive');endif
endfunction
function out=op_weighted_quantiles(v,w,p,opts)
  [v,w,n_total,n_input,n_valid]=prepare_weighted(v,w,opts);
  p=real_vector(p,'probabilities',true);
  if(any(!isfinite(p))||any(p<0)||any(p>1)),error('GXTXT:Numeric','weighted quantile probabilities must be within [0,1]');endif
  q=weighted_quantile_step(v,w,p);
  out=struct('probabilities',p(:),'quantiles',q(:),'n_total',n_total,'n_input',n_input,'n_valid',n_valid,'n_nonfinite',n_input-n_valid,'n_zero_weight',n_valid-numel(v),'n_positive_weight',numel(v),'n_positive',numel(v),'sum_weights',sum(w),'definition','weighted empirical CDF inverse');
endfunction

function out=op_weighted_statistics(v,w,opts)
  semantics=opt_text(opts,'weight_semantics','relative');
  if(!any(strcmp(semantics,{'relative','inverse_variance'}))),error('GXTXT:Numeric','Weighted statistics require relative or inverse_variance weights');endif
  [v,w,n_total,n_input,n_valid]=prepare_weighted(v,w,opts);sw=sum(w);sw2=sum(w.^2);mu=sum(w.*v)/sw;weighted_sse=sum(w.*(v-mu).^2);varp=weighted_sse/sw;denom=sw-sw2/sw;
  if(denom>0),varu=weighted_sse/denom;else varu=NaN;endif
  qs=weighted_quantile_step(v,w,[0.25;0.5;0.75]);
  out=struct('n_total',n_total,'n_input',n_input,'n_valid',n_valid,'n_nonfinite',n_input-n_valid,'n_zero_weight',n_valid-numel(v),'n_positive_weight',numel(v),'n_positive',numel(v),'sum_weights',sw,'effective_n',sw^2/sw2,'min',min(v),'max',max(v),'range',max(v)-min(v),'weighted_sum',sum(w.*v),'mean',mu,'median',qs(2),'q25',qs(1),'q75',qs(3),'iqr',qs(3)-qs(1),'variance_population',varp,'std_population',sqrt(varp),'variance_unbiased',varu,'std_unbiased',sqrt(varu),'rms',sqrt(sum(w.*v.^2)/sw),'quantile_definition','weighted empirical CDF inverse');
  out.weight_semantics=semantics;
  out.sampling_standard_error_mean=sqrt(varu/out.effective_n);
  out.measurement_standard_error_mean=NaN;
  if(strcmp(semantics,'inverse_variance'))
    out.measurement_standard_error_mean=sqrt(1/sw);
    out.dof=numel(v)-1;out.reduced_chi_squared=NaN;
    if(out.dof>0),out.reduced_chi_squared=weighted_sse/out.dof;endif
  endif
endfunction

% ---------- least squares, regression and polynomial fitting ----------
function [A,b,w,weighted,n0,input_rows]=prepare_ls(A,b,w,opts)
  A=real_matrix(A,'design matrix',false);b=real_vector(b,'response',false);if(rows(A)!=numel(b)),error('GXTXT:Numeric','design matrix row count and response length differ');endif
  n0=rows(A);good=all(isfinite(A),2)&isfinite(b);weighted=!isempty(w);
  input_rows=[];if(nargout>5),input_rows=uint64((1:n0)');endif
  if(weighted),w=real_vector(w,'weights',false);if(numel(w)!=n0),error('GXTXT:Numeric','weight length differs from design matrix row count');endif;good=good&isfinite(w);endif
  if(any(!good)),if(strcmp(nonfinite_policy(opts),'omit')),A=A(good,:);b=b(good);if(weighted),w=w(good);endif;if(nargout>5),input_rows=input_rows(good);endif;else error('GXTXT:Numeric','least-squares input contains NaN or Inf; set nonfinite=omit explicitly to discard affected rows');endif,endif
  if(weighted),if(any(w<0)),error('GXTXT:Numeric','weights must be non-negative');endif;keep=w>0;A=A(keep,:);b=b(keep);w=w(keep);if(nargout>5),input_rows=input_rows(keep);endif;if(isempty(w)),error('GXTXT:Numeric','at least one weight must be positive');endif,endif
endfunction
function out=op_least_squares(A,b,w,opts,retained_predictors)
  influence=opt_bool(opts,'influence_diagnostics',false);
  if(influence),influence_budget(rows(A),columns(A));[A,b,w,weighted,n_input,input_rows]=prepare_ls(A,b,w,opts);else [A,b,w,weighted,n_input]=prepare_ls(A,b,w,opts);endif
  n=rows(A);p=columns(A);if(n<p),error('GXTXT:Numeric','least squares requires at least as many valid rows as columns (%d < %d)',n,p);endif
  if(weighted),sw=sqrt(w);Aw=A.*repmat(sw,1,p);bw=b.*sw;else Aw=A;bw=b;endif
  factor=gxtxt_numeric_jacobian_factor_v1(Aw,false(p,1));rnk=factor.rank;s=factor.physical_singular_values;
  rank_policy=opt_text(opts,'rank_policy','error');if(!any(strcmp(rank_policy,{'error','minimum_norm'}))),error('GXTXT:Numeric','rank_policy must be error or minimum_norm');endif
  if(rnk<p&&strcmp(rank_policy,'error')),error('GXTXT:Numeric','design matrix is rank deficient (%d < %d)',rnk,p);endif
  if(rnk<p),beta=pinv(Aw)*bw;status='rank_deficient_minimum_norm';
  else
    % Solve in the same column coordinates used for the rank decision.
    % Raw backslash can discard a tiny but independently identified column.
    beta=((Aw./factor.column_scale)\bw)./factor.column_scale(:);status='ok';
  endif
  predicted=A*beta;
  weight_semantics=opt_text(opts,'weight_semantics','relative');if(!any(strcmp(weight_semantics,{'relative','inverse_variance'}))),error('GXTXT:Numeric','weight_semantics must be relative or inverse_variance');endif
  if(!weighted),weight_semantics='unweighted';endif
  diagnostics=struct('weight_semantics',weight_semantics);if(nargin>=5),diagnostics.predictor_values=retained_predictors;else diagnostics.predictor_values=A;endif;diagnostic_weights=w;if(!weighted),diagnostic_weights=ones(n,1);endif
  out=gxtxt_numeric_fit_diagnostics_v1(beta,b,predicted,Aw,diagnostic_weights,diagnostics,factor);
  out=rmfield(out,{'parameters','jacobian'});out.coefficients=beta(:);out.singular_values=s(:);out.n_input=n_input;
  out.sigma_squared=NaN;if(out.dof>0),out.sigma_squared=out.sse/out.dof;endif
  out.has_intercept=opt_bool(opts,'has_intercept',false);if(!out.has_intercept),out.adjusted_r_squared=NaN;endif
  out.status=status;
  if(influence),out.influence=gxtxt_numeric_influence_v1(Aw,out,factor,input_rows,n_input);endif
endfunction
function influence_budget(n,p)
  if(n<1||n>1000000||p<1||p>128||80*n*p+128*n+64*p*p>536870912),error('GXTXT:Numeric:Influence','Influence exceeds the 1M-row/128-parameter/512-MiB estimated workspace budget');endif
endfunction
function [x,y,w,input_rows]=prepare_fit_xyw(x,y,w,opts,min_count)
  x=real_vector(x,'X',false);y=real_vector(y,'Y',false);if(numel(x)!=numel(y)),error('GXTXT:Numeric','X and Y lengths differ');endif;weighted=!isempty(w);good=isfinite(x)&isfinite(y);
  input_rows=[];if(nargout>3),input_rows=uint64((1:numel(x))');endif
  if(weighted),w=real_vector(w,'weights',false);if(numel(w)!=numel(x)),error('GXTXT:Numeric','weight length differs from X/Y length');endif;good=good&isfinite(w);endif
  if(any(!good)),if(strcmp(nonfinite_policy(opts),'omit')),x=x(good);y=y(good);if(weighted),w=w(good);endif;if(nargout>3),input_rows=input_rows(good);endif;else error('GXTXT:Numeric','fit input contains NaN or Inf; set nonfinite=omit explicitly to discard affected observations');endif,endif
  if(weighted),if(any(w<0)),error('GXTXT:Numeric','weights must be non-negative');endif;keep=w>0;x=x(keep);y=y(keep);w=w(keep);if(nargout>3),input_rows=input_rows(keep);endif;if(isempty(w)),error('GXTXT:Numeric','at least one weight must be positive');endif,endif
  if(numel(x)<min_count),error('GXTXT:Numeric','fit requires at least %d valid observations',min_count);endif
endfunction
function out=op_linear_regression(x,y,w,opts)
  influence=opt_bool(opts,'influence_diagnostics',false);input_count=numel(x);
  if(influence),influence_budget(input_count,2);[x,y,w,input_rows]=prepare_fit_xyw(x,y,w,opts,2);else [x,y,w]=prepare_fit_xyw(x,y,w,opts,2);endif
  with_intercept=opt_bool(opts,'intercept',opt_bool(opts,'has_intercept',true));
  if(isfield(opts,'intercept')&&isfield(opts,'has_intercept')&&opt_bool(opts,'intercept',true)!=opt_bool(opts,'has_intercept',true))
    error('GXTXT:Numeric:InvalidOption','intercept and has_intercept must agree when both are supplied');
  endif
  if(with_intercept),A=[ones(numel(x),1),x];else A=x;endif
  r=op_least_squares(A,y,w,merge_opts(opts,struct('has_intercept',with_intercept)),x);r.x=x;r.y=y;r.intercept_included=logical(with_intercept);
  if(with_intercept),r.intercept=r.coefficients(1);r.slope=r.coefficients(2);else r.intercept=0;r.slope=r.coefficients(1);endif
  if(influence),r.influence.input_row_index=input_rows;r.influence.input_count=input_count;endif
  out=r;
endfunction
function V=poly_design(z,degree)
  n=numel(z);V=zeros(n,degree+1);for j=0:degree,V(:,j+1)=z.^(degree-j);endfor
endfunction
function T=scaled_poly_transform(degree,center,scale)
  T=zeros(degree+1,degree+1);
  for j=1:degree+1
    power=degree-j+1;
    if(power==0),e=1;else e=poly(repmat(center,1,power))/(scale^power);endif
    start=degree-power+1;T(start:degree+1,j)=e(:);
  endfor
endfunction
function out=op_polynomial_fit(x,y,degree,w,opts)
  degree=double(degree);if(!isscalar(degree)||!isfinite(degree)||degree<0||degree!=fix(degree)),error('GXTXT:Numeric','polynomial degree must be a non-negative integer');endif
  influence=opt_bool(opts,'influence_diagnostics',false);input_count=numel(x);
  if(influence),influence_budget(input_count,degree+1);[x,y,w,input_rows]=prepare_fit_xyw(x,y,w,opts,degree+1);else [x,y,w]=prepare_fit_xyw(x,y,w,opts,degree+1);endif
  center_scale=opt_bool(opts,'center_scale',true);
  [V,T,center,scale,scaling]=polynomial_coordinates(x,degree,center_scale);ls=op_least_squares(V,y,w,merge_opts(opts,struct('has_intercept',true)),x);coeff=T*ls.coefficients;covx=T*ls.covariance*T.';sex=sqrt(max(diag(covx),0));
  out=ls;out.coefficients=coeff(:);out.standard_errors=sex(:);out.covariance=covx;out.scaled_coefficients=ls.coefficients(:);out.scaled_covariance=ls.covariance;out.degree=degree;out.x_center=center;out.x_scale=scale;out.scaling=scaling;out.x=x;out.y=y;out.weighted=logical(!isempty(w));
  if(influence),out.influence.input_row_index=input_rows;out.influence.input_count=input_count;endif
endfunction
function [V,T,center,scale,scaling]=polynomial_coordinates(x,degree,center_scale)
  if(center_scale&&degree>0),center=mean(x);scale=std(x,0);if(!isfinite(scale)||scale<=0),error('GXTXT:Numeric','polynomial fit cannot scale a zero-spread X vector');endif;z=(x-center)/scale;scaling='center_scale';else center=0;scale=1;z=x;scaling='none';endif
  V=poly_design(z,degree);T=scaled_poly_transform(degree,center,scale);
endfunction
function out=op_polynomial_gls(x,y,degree,C,opts)
  degree=double(degree);
  if(!isscalar(degree)||!isfinite(degree)||degree<0||degree>63||degree!=fix(degree)),error('GXTXT:Numeric:GLS','Polynomial GLS degree must be an integer from0 to63');endif
  if(numel(x)>2048),error('GXTXT:Numeric:GLS','Polynomial GLS is bounded to2048 observations');endif
  [x,y]=prepare_fit_xyw(x,y,[],struct('nonfinite','error'),degree+1);
  center_scale=opt_bool(opts,'center_scale',true);if(isfield(opts,'center_scale')),opts=rmfield(opts,'center_scale');endif
  [V,T,center,scale,scaling]=polynomial_coordinates(x,degree,center_scale);
  out=gxtxt_numeric_gls_v1(V,y,C,opts);
  out.scaled_coefficients=out.coefficients;out.scaled_covariance=out.covariance;
  out.coefficients=T*out.coefficients;out.covariance=T*out.covariance*T.';
  if(any(!isfinite(out.coefficients))),error('GXTXT:Numeric:GLS','Physical polynomial coefficients overflow');endif
  available=!strcmp(out.uncertainty_status,'unavailable_no_residual_dof');
  if(available&&any(!isfinite(out.covariance(:)))),error('GXTXT:Numeric:GLS','Physical polynomial covariance overflow');endif
  variance=diag(out.covariance);finite=isfinite(variance);variance(finite)=max(variance(finite),0);out.standard_errors=sqrt(variance);
  out.operation='polynomial_gls';out.degree=degree;out.x_center=center;out.x_scale=scale;out.scaling=scaling;
  out.observation_signature=gxtxt_numeric_v1('fit_observation_signature',y,[],[],x);
  out.summary=rmfield(out,{'predicted','residuals','whitened_residuals','summary','scaled_coefficients','scaled_covariance','degree','x_center','x_scale','scaling'});
  out.summary.schema='gxtxt.gls_numeric_summary.v1';
endfunction
function out=op_polynomial_evaluate(model,xq,opts)
  if(!isstruct(model)||numel(model)!=1),error('GXTXT:Numeric','polynomial model must be a scalar struct returned by polynomial_fit');endif
  xq=real_vector(xq,'X query',true);if(any(!isfinite(xq))),error('GXTXT:Numeric','X query contains NaN or Inf');endif
  scale=1;z=xq;
  if(isfield(model,'scaled_coefficients')&&isfield(model,'x_center')&&isfield(model,'x_scale'))
    scale=double(model.x_scale);center=double(model.x_center);
    if(!isscalar(scale)||!isfinite(scale)||scale<=0||!isscalar(center)||!isfinite(center)),error('GXTXT:Numeric','Polynomial scaling must be finite with positive scale');endif
    c=real_vector(model.scaled_coefficients,'scaled coefficients',false);z=(xq-center)/scale;
  elseif(isfield(model,'coefficients'))
    c=real_vector(model.coefficients,'coefficients',false);
  else error('GXTXT:Numeric','polynomial model has no coefficients');endif
  degree=numel(c)-1;order=opt_int(opts,'derivative_order',0);
  if(order<0||order>12),error('GXTXT:Numeric','Polynomial derivative order must be0..12');endif
  for k=1:order,c=polyder(c);endfor
  yq=polyval(c(:).',z)/scale^order;
  out=struct('xq',xq,'yq',double(yq(:)),'degree',degree,'derivative_order',order);
endfunction

% ---------- generic nonlinear least squares ----------
function [X,y,w]=prepare_nonlinear_data(X,y,w,opts)
  X=real_matrix(X,'X',false);if(isvector(X)),X=X(:);endif;y=real_vector(y,'Y',false);if(rows(X)!=numel(y)),error('GXTXT:Numeric','X row count and Y length differ');endif
  weighted=!isempty(w);good=all(isfinite(X),2)&isfinite(y);if(weighted),w=real_vector(w,'weights',false);if(numel(w)!=numel(y)),error('GXTXT:Numeric','weight length differs from Y');endif;good=good&isfinite(w);endif
  if(any(!good)),if(strcmp(nonfinite_policy(opts),'omit')),X=X(good,:);y=y(good);if(weighted),w=w(good);endif;else error('GXTXT:Numeric','nonlinear-fit input contains NaN or Inf; set nonfinite=omit explicitly to discard affected observations');endif,endif
  if(weighted),if(any(w<0)),error('GXTXT:Numeric','weights must be non-negative');endif;keep=w>0;X=X(keep,:);y=y(keep);w=w(keep);if(isempty(w)),error('GXTXT:Numeric','at least one weight must be positive');endif;else w=ones(numel(y),1);endif
endfunction
function yhat=model_eval(fun,p,X,n)
  yhat=fun(p(:),X);yhat=real_vector(yhat,'model prediction',false);if(numel(yhat)!=n),error('GXTXT:Numeric','model function returned %d values for %d observations',numel(yhat),n);endif;if(any(!isfinite(yhat))),error('GXTXT:Numeric','model function returned NaN or Inf');endif
endfunction
function r=nl_weighted_residual(fun,p,X,y,sqrtw),r=sqrtw.*(model_eval(fun,p,X,numel(y))-y);endfunction
function J=numerical_jacobian(fun,p,X,y,sqrtw)
  p=p(:);base=nl_weighted_residual(fun,p,X,y,sqrtw);J=zeros(numel(base),numel(p));
  for j=1:numel(p),h=sqrt(eps)*max(1,abs(p(j)));q=p;q(j)+=h;J(:,j)=(nl_weighted_residual(fun,q,X,y,sqrtw)-base)/h;endfor
endfunction
function loaded=try_load_optim()
  loaded=(exist('lsqnonlin','file')==2);if(loaded),return;endif
  try pkg('load','optim');catch;end_try_catch
  loaded=(exist('lsqnonlin','file')==2);
endfunction
function out=op_nonlinear_fit(model_fun,X,y,initial,opts)
  if(isstruct(model_fun))
    out=gxtxt_numeric_declared_fit_v1(model_fun,X,y,initial,opts);return;
  endif
  if(!strcmp(opt_text(opts,'multistart_mode','single'),'single')),error('GXTXT:Numeric','Multistart currently requires a declared model');endif
  if(!strcmp(opt_text(opts,'fit_geometry','vertical_response'),'vertical_response')||opt_has(opts,'sigma_x')),error('GXTXT:Numeric','XY uncertainty fitting requires a declared model and the native backend');endif
  require_function_handle(model_fun,'model function');p0=real_vector(initial,'initial parameters',false);if(any(!isfinite(p0))),error('GXTXT:Numeric','initial parameters must be finite');endif;weights=[];weight_semantics='relative';
  if(opt_has(opts,'weights')),weights=real_vector(opts.weights,'weights',false);weight_semantics=opt_text(opts,'weight_semantics','relative');elseif(opt_has(opts,'sigma')),sig=real_vector(opts.sigma,'sigma',false);if(any(sig<=0)||any(!isfinite(sig))),error('GXTXT:Numeric','sigma values must be finite and positive');endif;weights=1./(sig.^2);weight_semantics='inverse_variance';endif
  if(!any(strcmp(weight_semantics,{'relative','inverse_variance'}))),error('GXTXT:Numeric','weight_semantics must be relative or inverse_variance');endif
  [X,y,w]=prepare_nonlinear_data(X,y,weights,opts);n=numel(y);p=numel(p0);sqrtw=sqrt(w);
  if(p<1||p>128||n*p*8>512*1024*1024),error('GXTXT:Numeric:Memory','Callback fitting requires 1..128 parameters and a Jacobian within 512 MiB');endif
  lb=-Inf(p,1);ub=Inf(p,1);if(opt_has(opts,'lower_bounds')),lb=real_vector(opts.lower_bounds,'lower_bounds',false);endif;if(opt_has(opts,'upper_bounds')),ub=real_vector(opts.upper_bounds,'upper_bounds',false);endif
  if(numel(lb)!=p||numel(ub)!=p),error('GXTXT:Numeric','parameter bounds must match initial parameter length');endif;if(any(isnan(lb))||any(isnan(ub))),error('GXTXT:Numeric','parameter bounds must not contain NaN');endif;if(any(lb>ub)),error('GXTXT:Numeric','lower_bounds must be <= upper_bounds');endif;if(any(p0<lb)||any(p0>ub)),error('GXTXT:Numeric','initial parameters violate bounds');endif
  fixed=zeros(p,1);if(opt_has(opts,'fixed_mask')),fixed=real_vector(opts.fixed_mask,'fixed_mask',false);endif
  if(numel(fixed)!=p||any(!ismember(fixed,[0,1]))),error('GXTXT:Numeric','fixed_mask must contain one boolean per parameter');endif
  fixed=logical(fixed)|(lb==ub);free=find(!fixed);free_count=numel(free);
  if(n<free_count),error('GXTXT:Numeric','nonlinear fit has fewer observations than free parameters');endif
  solver=opt_text(opts,'solver','auto');maxiter=opt_int(opts,'max_iterations',400);tol=opt_num(opts,'tolerance',1e-8);if(maxiter<1||tol<=0),error('GXTXT:Numeric','invalid nonlinear solver limits');endif
  bounded_fminsearch=opt_text(opts,'bounded_fminsearch','reject');
  if(!any(strcmp(bounded_fminsearch,{'reject','penalty_clip'}))),error('GXTXT:Numeric','bounded_fminsearch must be reject or penalty_clip');endif
  if(!any(strcmp(solver,{'auto','lsqnonlin','fminsearch'}))),error('GXTXT:Numeric','nonlinear solver must be auto, lsqnonlin or fminsearch');endif
  requested_solver=solver;have_lsq=false;if(free_count),have_lsq=try_load_optim();endif
  if(strcmp(solver,'auto')),if(have_lsq),solver='lsqnonlin';else solver='fminsearch';endif,endif
  free_model=@(q,predictors) model_fun(nonlinear_expand_free(q,p0,free),predictors);
  fun=@(q) nl_weighted_residual(free_model,q,X,y,sqrtw);iterations=NaN;evals=NaN;message='';Jfree=[];
  q0=p0(free);lo=lb(free);hi=ub(free);
  if(!free_count)
    qhat=zeros(0,1);Jfree=zeros(n,0);solver='fixed_evaluation';exitflag=1;iterations=0;evals=1;message='All parameters fixed; optimizer not invoked';
  elseif(strcmp(solver,'lsqnonlin'))
    if(!have_lsq),error('GXTXT:Numeric','solver lsqnonlin requires the Octave optim package');endif
    o=optimset('Display','off','MaxIter',maxiter,'TolFun',tol,'TolX',tol);
    try
      [qhat,obj,wr,exitflag,info,~,Jfree]=lsqnonlin(fun,q0,lo,hi,o);
      if(isstruct(info)),if(isfield(info,'iterations')),iterations=info.iterations;endif;if(isfield(info,'niter')),iterations=info.niter;endif;if(isfield(info,'funcCount')),evals=info.funcCount;endif;if(isfield(info,'nfev')),evals=info.nfev;endif;if(isfield(info,'message')),message=info.message;endif,endif
    catch err
      if(strcmp(requested_solver,'auto')&&opt_bool(opts,'fallback_on_solver_error',false)),solver='fminsearch';else rethrow(err);endif
    end_try_catch
  endif
  if(strcmp(solver,'fminsearch'))
    bounded=any(isfinite(lo))||any(isfinite(hi));
    if(bounded&&strcmp(bounded_fminsearch,'reject')),error('GXTXT:Numeric','bounded nonlinear fitting requires solver lsqnonlin or bounded_fminsearch=penalty_clip');endif
    if(bounded)
      scale=max(abs(q0),1);z0=q0./scale;
      objfun=@(z) nonlinear_bounded_penalty(z,scale,fun,lo,hi);
      o=optimset('Display','off','MaxIter',maxiter,'MaxFunEvals',20*maxiter,'TolX',tol,'TolFun',tol);
      [z,obj,exitflag,info]=fminsearch(objfun,z0,o);qhat=min(max(z.*scale,lo),hi);
    else
      objfun=@(q) sum(fun(q).^2);o=optimset('Display','off','MaxIter',maxiter,'TolX',tol,'TolFun',tol);[qhat,obj,exitflag,info]=fminsearch(objfun,q0,o);
    endif
    wr=fun(qhat);Jfree=numerical_jacobian(free_model,qhat,X,y,sqrtw);
    if(isstruct(info)),if(isfield(info,'iterations')),iterations=info.iterations;endif;if(isfield(info,'funcCount')),evals=info.funcCount;endif;endif
  endif
  phat=nonlinear_expand_free(qhat,p0,free);pred=model_eval(model_fun,phat,X,n);
  J=zeros(n,p);J(:,free)=Jfree;
  diagnostics=struct('weight_semantics',iff(isempty(weights),'unweighted',weight_semantics),'predictor_values',X,'fixed_mask',fixed);
  diagnostics.active_bounds=!fixed&((isfinite(lb)&abs(phat-lb)<=32*eps.*max(abs(lb),abs(phat)))|(isfinite(ub)&abs(phat-ub)<=32*eps.*max(abs(ub),abs(phat))));
  out=gxtxt_numeric_fit_diagnostics_v1(phat,y,pred,J,w,diagnostics);
  out.active_bounds=diagnostics.active_bounds;
  out.solver=solver;out.converged=logical(exitflag>0);out.exitflag=exitflag;
  out.iterations=iterations;out.function_evaluations=evals;out.solver_message=message;
endfunction

function full=nonlinear_expand_free(values,initial,free)
  full=initial;full(free)=values(:);
endfunction

function s=nonlinear_bounded_penalty(z,scale,fun,lb,ub)
  q=z.*scale;below=max(lb-q,0);above=max(q-ub,0);
  clipped=min(max(q,lb),ub);r=fun(clipped);
  s=sum(r.^2)+1e9*sum((below./max(abs(lb),1)).^2+(above./max(abs(ub),1)).^2);
endfunction

% ---------- smoothing and generic filtering ----------
function outv=moving_stat_local(v,window,kind)
  n=numel(v);outv=zeros(n,1);left=floor((window-1)/2);right=window-1-left;
  for i=1:n,a=max(1,i-left);b=min(n,i+right);seg=v(a:b);if(strcmp(kind,'mean')),outv(i)=mean(seg);else outv(i)=median(seg);endif,endfor
endfunction
function outv=local_polynomial_smooth(x,y,window,degree)
  n=numel(y);if(window>n),error('GXTXT:Numeric','local-polynomial window exceeds data length');endif;if(mod(window,2)==0),error('GXTXT:Numeric','local-polynomial window must be odd');endif;if(degree<0||degree>=window||degree!=fix(degree)),error('GXTXT:Numeric','local-polynomial degree must be an integer in [0, window-1]');endif
  outv=zeros(n,1);half=floor(window/2);
  for i=1:n
    a=i-half;b=i+half;if(a<1),b+=1-a;a=1;endif;if(b>n),a-=b-n;b=n;endif
    xx=x(a:b)-x(i);V=poly_design(xx,degree);beta=V\y(a:b);outv(i)=beta(end);
  endfor
endfunction
function loaded=try_load_signal()
  loaded=(exist('sgolayfilt','file')==2);if(loaded),return;endif
  try pkg('load','signal');catch;end_try_catch
  loaded=(exist('sgolayfilt','file')==2);
endfunction
function out=op_smooth(x,y,opts)
  if(numel(x)!=numel(y)),error('GXTXT:Numeric','X and Y smoothing lengths differ');endif
  original_count=numel(x);valid=isfinite(x(:))&isfinite(y(:));
  [x,y]=xy_prepare(x,y,opts,1);method=opt_text(opts,'method','moving_mean');window=opt_int(opts,'window',5);if(window<1),error('GXTXT:Numeric','smoothing window must be >= 1');endif;if(mod(window,2)==0),error('GXTXT:Numeric','smoothing window must be odd for centered v1 smoothing');endif
  if(any(strcmp(method,{'lowess','loess'})))
    allowed={'method','window','degree','robust_iterations','nonfinite','selection','selection_id','chunk_rows'};
    unknown=setdiff(fieldnames(opts),allowed);if(!isempty(unknown)),error('GXTXT:Numeric','Unknown LOWESS option: %s',unknown{1});endif
    degree=opt_int(opts,'degree',1+strcmp(method,'loess'));iterations=opt_int(opts,'robust_iterations',2);
    out=gxtxt_numeric_lowess_v1(x,y,window,degree,iterations);
    out.original_count=original_count;out.source_row_positions=uint64(find(valid));out.dropped_row_positions=uint64(find(!valid));return;
  endif
  if(isfield(opts,'robust_iterations')),error('GXTXT:Numeric','robust_iterations requires lowess or loess');endif
  if(strcmp(method,'moving_mean')),ys=moving_stat_local(y,window,'mean');degree=NaN;endpoint='shrink';
  elseif(strcmp(method,'moving_median')),ys=moving_stat_local(y,window,'median');degree=NaN;endpoint='shrink';
  elseif(any(strcmp(method,{'savitzky_golay','savgol'})))
    if(window>numel(x)),error('GXTXT:Numeric','Savitzky-Golay window exceeds retained data length');endif
    degree=opt_int(opts,'degree',2);if(degree<0||degree>=window),error('GXTXT:Numeric','Savitzky-Golay degree must be in [0, window-1]');endif
    g=op_grid_info(x,opts);if(!g.uniform),error('GXTXT:Numeric','Savitzky-Golay smoothing requires a uniform X grid; use local_polynomial for non-uniform coordinates');endif
    if(!try_load_signal()),error('GXTXT:Numeric','Savitzky-Golay smoothing requires the Octave signal package (sgolayfilt)');endif
    ys=sgolayfilt(y,degree,window);method='savitzky_golay';endpoint='signal.sgolayfilt';
  elseif(strcmp(method,'local_polynomial'))
    degree=opt_int(opts,'degree',2);ys=local_polynomial_smooth(x,y,window,degree);endpoint='shift_full_window';
  else error('GXTXT:Numeric','smoothing method must be moving_mean, moving_median, savitzky_golay, local_polynomial, lowess or loess');endif
  out=struct('x',x,'y',double(ys(:)),'residuals',double(y(:)-ys(:)),'method',method,'window',window,'degree',degree,'endpoint_policy',endpoint);
  out.original_count=original_count;out.source_row_positions=uint64(find(valid));out.dropped_row_positions=uint64(find(!valid));
endfunction
function out=op_digital_filter(y,b,a,opts)
  y=real_vector(y,'signal',false);b=real_vector(b,'numerator coefficients',false);a=real_vector(a,'denominator coefficients',false);
  if(any(!isfinite(y))||any(!isfinite(b))||any(!isfinite(a))),error('GXTXT:Numeric','digital filtering requires finite signal and coefficients');endif;if(a(1)==0),error('GXTXT:Numeric','first denominator coefficient must be non-zero');endif
  yf=filter(b,a,y);out=struct('y',double(yf(:)),'b',b,'a',a,'method','causal_difference_equation','initial_state','zero');
endfunction

% ---------- peak primitives ----------
function idx=local_peak_candidates(y)
  idx=zeros(0,1);if(numel(y)<3),return;endif
  d=diff(y);active=find(d!=0);
  if(numel(active)<2),return;endif
  transitions=find(d(active(1:end-1))>0 & d(active(2:end))<0);
  idx=round((active(transitions)+1+active(transitions+1))/2);
  idx=idx(:);
endfunction
function [prom,lbase,rbase]=peak_prominence_local(y,i)
  h=y(i);lb=find(y(1:i-1)>h,1,'last');if(isempty(lb)),lb=1;endif
  right=find(y(i+1:end)>h,1,'first');if(isempty(right)),rb=numel(y);else rb=i+right;endif
  lbase=min(y(lb:i));rbase=min(y(i:rb));prom=h-max(lbase,rbase);
endfunction
function xc=crossing_x(x,y,i,direction,level)
  n=numel(y);j=i;
  if(direction<0)
    while(j>1&&y(j)>level),j-=1;endwhile
    if(j==i),xc=x(i);elseif(y(j)==y(j+1)),xc=x(j);else xc=x(j)+(level-y(j))*(x(j+1)-x(j))/(y(j+1)-y(j));endif
  else
    while(j<n&&y(j)>level),j+=1;endwhile
    if(j==i),xc=x(i);elseif(y(j)==y(j-1)),xc=x(j);else xc=x(j-1)+(level-y(j-1))*(x(j)-x(j-1))/(y(j)-y(j-1));endif
  endif
endfunction
function keep=apply_peak_distance(x,idx,y,min_distance,mode)
  if(isempty(idx)),keep=idx;return;endif
  [~,ord]=sort(y(idx),'descend');accepted=[];
  for q=1:numel(ord),cand=idx(ord(q));ok=true;for j=1:numel(accepted),if(strcmp(mode,'samples')),dist=abs(cand-accepted(j));else dist=abs(x(cand)-x(accepted(j)));endif;if(dist<min_distance),ok=false;break;endif,endfor;if(ok),accepted(end+1,1)=cand;endif,endfor
  keep=sort(accepted);
endfunction
function out=op_find_peaks(x,y,opts)
  [x,y]=xy_prepare(x,y,opts,1);idx=local_peak_candidates(y);min_height=opt_num(opts,'min_height',-realmax);min_prom=opt_num(opts,'min_prominence',0);min_dist=opt_num(opts,'min_distance',1);mode=opt_text(opts,'distance_mode','samples');relh=opt_num(opts,'relative_height',0.5);
  if(!any(strcmp(mode,{'samples','x'}))),error('GXTXT:Numeric','peak distance_mode must be samples or x');endif;if(min_dist<0||min_prom<0||relh<0||relh>1),error('GXTXT:Numeric','invalid peak threshold option');endif
  idx=idx(y(idx)>=min_height);
  proms=zeros(numel(idx),1);for k=1:numel(idx),proms(k)=peak_prominence_local(y,idx(k));endfor;mask=proms>=min_prom;idx=idx(mask);proms=proms(mask);idx=apply_peak_distance(x,idx,y,min_dist,mode);
  proms=zeros(numel(idx),1);widths=zeros(numel(idx),1);lx=zeros(numel(idx),1);rx=zeros(numel(idx),1);
  for k=1:numel(idx),i=idx(k);proms(k)=peak_prominence_local(y,i);level=y(i)-relh*proms(k);lx(k)=crossing_x(x,y,i,-1,level);rx(k)=crossing_x(x,y,i,1,level);widths(k)=rx(k)-lx(k);endfor
  out=struct('indices',double(idx(:)),'x',x(idx),'heights',y(idx),'prominences',proms,'widths',widths,'left_x',lx,'right_x',rx,'n',numel(idx),'min_height',min_height,'min_prominence',min_prom,'min_distance',min_dist,'distance_mode',mode,'relative_height',relh,'index_base',1);
endfunction

% ---------- baseline primitives ----------
function out=op_baseline(x,y,anchor_x,anchor_y,opts)
  for values={x,y}
    v=values{1};if(isinteger(v)&&(any(v(:)>cast(flintmax,class(v)))||any(v(:)<cast(-flintmax,class(v)))))
      error('GXTXT:Numeric:Baseline','Baseline integer inputs outside the exact binary64 range require an explicit scientific conversion');
    endif
  endfor
  original_x=x(:);original_y=y(:);
  raw_x=real_vector(x,'X',false);raw_y=real_vector(y,'Y',false);
  [x,y]=paired_vectors(raw_x,raw_y,'X','Y',opts,1);good=isfinite(raw_x)&isfinite(raw_y);
  method=opt_text(opts,'method','constant');base=zeros(size(y));coeff=[];degree=NaN;details=struct();
  if(strcmp(method,'constant'))
    if(opt_has(opts,'value')),c=opt_num(opts,'value',0);else est=opt_text(opts,'estimator','mean');if(strcmp(est,'mean')),c=mean(y);elseif(strcmp(est,'median')),c=median(y);else error('GXTXT:Numeric','constant baseline estimator must be mean or median');endif,endif;base(:)=c;coeff=c;degree=0;
  elseif(any(strcmp(method,{'linear','polynomial'})))
    if(strcmp(method,'linear')),degree=1;else degree=opt_int(opts,'degree',2);endif
    fit=op_polynomial_fit(x,y,degree,[],opts);base=fit.predicted;coeff=fit.coefficients;
  elseif(strcmp(method,'anchors'))
    require_strict_increasing(x,'X');anchor_x=real_vector(anchor_x,'anchor X',false);anchor_y=real_vector(anchor_y,'anchor Y',false);if(numel(anchor_x)!=numel(anchor_y)),error('GXTXT:Numeric','anchor X/Y lengths differ');endif
    amethod=opt_text(opts,'anchor_method','linear');r=op_interpolate(anchor_x,anchor_y,x,struct('method',amethod,'extrapolation',opt_text(opts,'extrapolation','error'),'nonfinite',nonfinite_policy(opts)));base=r.yq;method=['anchors_' amethod];
  elseif(strcmp(method,'asls'))
    details=gxtxt_numeric_baseline_asls_v1(x,y,opts);base=details.baseline;details=rmfield(details,'baseline');
  else error('GXTXT:Numeric','baseline method must be constant, linear, polynomial, anchors or asls');endif
  out=struct('x',x,'baseline',double(base(:)),'corrected',double(y(:)-base(:)),'method',method,'degree',degree,'coefficients',double(coeff(:)));
  out.original_x=original_x(good);out.original_y=original_y(good);out.source_row_positions=find(good);out.dropped_row_positions=find(!good);out.index_base=1;
  out.original_n=numel(raw_y);out.selected_n=numel(y);out.nonfinite_policy=nonfinite_policy(opts);
  out.row_order='original_input_order';out.estimator=details;out.schema='gxtxt.baseline_result.v1';
endfunction

% ---------- root finding, optimization and uncertainty ----------
function out=op_root_find(fun,bracket,opts)
  require_function_handle(fun,'root function');bracket=real_vector(bracket,'root bracket/initial guess',false);if(any(!isfinite(bracket))),error('GXTXT:Numeric','root bracket/initial guess must be finite');endif;if(!(numel(bracket)==1||numel(bracket)==2)),error('GXTXT:Numeric','root bracket must contain one initial guess or two bracketing values');endif
  o=optimset('Display','off','TolX',opt_num(opts,'tolerance',1e-8),'MaxIter',opt_int(opts,'max_iterations',400));[root,fval,info,output]=fzero(fun,bracket,o);it=NaN;ev=NaN;if(isstruct(output)),if(isfield(output,'iterations')),it=output.iterations;endif;if(isfield(output,'funcCount')),ev=output.funcCount;endif,endif
  out=struct('root',root,'fval',fval,'converged',logical(info>0),'exitflag',info,'iterations',it,'function_evaluations',ev,'solver','fzero');
endfunction
function out=op_minimize_1d(fun,bounds,opts)
  require_function_handle(fun,'objective function');bounds=real_vector(bounds,'bounds',false);if(any(!isfinite(bounds))||numel(bounds)!=2||bounds(1)>=bounds(2)),error('GXTXT:Numeric','one-dimensional minimization requires finite bounds [lower upper] with lower < upper');endif
  o=optimset('Display','off','TolX',opt_num(opts,'tolerance',1e-8),'MaxIter',opt_int(opts,'max_iterations',400));[x,fval,info,output]=fminbnd(fun,bounds(1),bounds(2),o);it=NaN;ev=NaN;if(isstruct(output)),if(isfield(output,'iterations')),it=output.iterations;endif;if(isfield(output,'funcCount')),ev=output.funcCount;endif,endif
  out=struct('x',x,'fval',fval,'converged',logical(info>0),'exitflag',info,'iterations',it,'function_evaluations',ev,'solver','fminbnd');
endfunction
function out=op_minimize(fun,initial,opts)
  require_function_handle(fun,'objective function');initial=real_vector(initial,'initial parameters',false);if(any(!isfinite(initial))),error('GXTXT:Numeric','optimization initial parameters must be finite');endif;o=optimset('Display','off','TolX',opt_num(opts,'tolerance',1e-8),'TolFun',opt_num(opts,'function_tolerance',1e-8),'MaxIter',opt_int(opts,'max_iterations',800));[x,fval,info,output]=fminsearch(fun,initial,o);it=NaN;ev=NaN;if(isstruct(output)),if(isfield(output,'iterations')),it=output.iterations;endif;if(isfield(output,'funcCount')),ev=output.funcCount;endif,endif
  out=struct('x',x(:),'fval',fval,'converged',logical(info>0),'exitflag',info,'iterations',it,'function_evaluations',ev,'solver','fminsearch');
endfunction
function out=op_propagate_uncertainty(J,u,opts)
  J=real_matrix(J,'Jacobian',false);if(any(!isfinite(J(:)))),error('GXTXT:Numeric','Jacobian contains NaN or Inf');endif;kind=opt_text(opts,'input_kind','standard_uncertainty');n=columns(J);
  if(strcmp(kind,'standard_uncertainty'))
    s=real_vector(u,'standard uncertainties',false);if(numel(s)!=n||any(!isfinite(s))||any(s<0)),error('GXTXT:Numeric','standard uncertainties must be finite, non-negative and match Jacobian columns');endif;Cin=diag(s.^2);
  elseif(strcmp(kind,'covariance'))
    Cin=real_matrix(u,'input covariance',false);if(rows(Cin)!=n||columns(Cin)!=n||any(!isfinite(Cin(:)))),error('GXTXT:Numeric','input covariance dimensions must match Jacobian columns');endif;if(norm(Cin-Cin.','fro')>1e-10*max(1,norm(Cin,'fro'))),error('GXTXT:Numeric','input covariance must be symmetric');endif
    ev=eig((Cin+Cin.')/2);tol=1e-12*max(1,max(abs(ev)));if(any(ev < -tol)),error('GXTXT:Numeric','input covariance must be positive semidefinite within numerical tolerance');endif
  else error('GXTXT:Numeric','input_kind must be standard_uncertainty or covariance');endif
  Cout=J*Cin*J.';sout=sqrt(max(diag(Cout),0));out=struct('covariance',Cout,'standard_uncertainty',sout(:),'jacobian',J,'input_covariance',Cin,'method','first_order_linear_propagation','input_kind',kind,'input_count',columns(J),'output_count',rows(J));
endfunction

% ---------- Dataset-aware facade ----------
function out=op_dataset_array_unary(session,dataset_id,vid,name,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{vid});
  [vals,meta]=dataset_read(session,dataset_id,{vid},selection,opts);
  out=op_array_unary(name,vals{1},opts);out.dataset_id=dataset_id;out.variable_id=vid;
  out.source_unit=meta.units{1};out.selection_id=selection_id(selection);
endfunction
function out=op_dataset_array_binary(session,dataset_id,left_id,right_id,name,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{left_id,right_id});
  [vals,meta]=dataset_read(session,dataset_id,{left_id,right_id},selection,opts);
  out=op_array_binary(name,vals{1},vals{2},opts);out.dataset_id=dataset_id;
  out.left_variable_id=left_id;out.right_variable_id=right_id;
  out.left_source_unit=meta.units{1};out.right_source_unit=meta.units{2};out.selection_id=selection_id(selection);
endfunction
function out=op_dataset_array_scalar(session,dataset_id,vid,scalar,name,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{vid});
  [vals,meta]=dataset_read(session,dataset_id,{vid},selection,opts);
  if(opt_bool(opts,'scalar_first',false)),out=op_array_binary(name,scalar,vals{1},opts);
  else out=op_array_binary(name,vals{1},scalar,opts);endif
  out.dataset_id=dataset_id;out.variable_id=vid;out.source_unit=meta.units{1};
  out.selection_id=selection_id(selection);
endfunction
function out=op_dataset_integrate(session,dataset_id,xid,yid,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_integrate(vals{1},vals{2},opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);out.result_unit=combined_unit(meta.units{2},meta.units{1},'*');
endfunction
function out=op_dataset_cumulative_integrate(session,dataset_id,xid,yid,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_cumulative_integrate(vals{1},vals{2},opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);out.result_unit=combined_unit(meta.units{2},meta.units{1},'*');
endfunction
function out=op_dataset_differentiate(session,dataset_id,xid,yid,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_differentiate(vals{1},vals{2},opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);out.result_unit=combined_unit(meta.units{2},meta.units{1},'/');
endfunction
function out=op_dataset_interpolate(session,dataset_id,xid,yid,xq,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_interpolate(vals{1},vals{2},xq,opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);
endfunction
function out=op_dataset_resample(session,dataset_id,xid,yid,xq,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_resample(vals{1},vals{2},xq,opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);
endfunction
function out=op_dataset_resample_uniform(session,dataset_id,xid,yid,step,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_resample_uniform(vals{1},vals{2},step,opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);
endfunction
function out=op_dataset_statistics(session,dataset_id,vid,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{vid});[vals,meta]=dataset_read(session,dataset_id,{vid},selection,opts);r=op_statistics(vals{1},opts);r.dataset_id=dataset_id;r.variable_id=vid;r.unit=meta.units{1};r.selection_id=selection_id(selection);out=r;
endfunction
function out=op_dataset_reduce_summary(session,dataset_id,vid,opts)
  ensure_dataset_api();selection=opt(opts,'selection',struct('enabled',false));
  validate_dataset_ids(session,dataset_id,{vid});ids={vid};
  if(selection_enabled(selection))
    require_selection_dataset(selection,dataset_id);
    if(!isfield(selection,'x_variable_id')||isempty(strtrim(selection.x_variable_id))),error('GXTXT:Numeric','Dataset Selection requires stable x_variable_id');endif
    ids=append_unique(ids,selection.x_variable_id);
    if(strcmp(lower(strtrim(selection.type)),'rectangle'))
      if(!isfield(selection,'y_variable_id')||isempty(strtrim(selection.y_variable_id))),error('GXTXT:Numeric','Rectangle Dataset Selection requires stable y_variable_id');endif
      ids=append_unique(ids,selection.y_variable_id);
    endif
  endif
  chunk_rows=opt_int(opts,'chunk_rows',65536);
  if(chunk_rows<1),error('GXTXT:Numeric','chunk_rows must be >= 1');endif
  S=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','resource'));
  schema=S.schema;state=[];n_input=0;n_valid=0;policy=nonfinite_policy(opts);
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);if(C.nrows<1),continue;endif
      chunk=cell(1,numel(ids));
      for j=1:numel(ids)
        col=C.values{j};
        if(!(isnumeric(col)||islogical(col))),error('GXTXT:Numeric','Dataset variable %s is not numeric',ids{j});endif
        chunk{j}=double(col(:));
        if(numel(chunk{j})!=C.nrows),error('GXTXT:Numeric','Dataset variables are not row-aligned');endif
      endfor
      mask=true(C.nrows,1);
      if(selection_enabled(selection))
        xi=find_id(ids,selection.x_variable_id);
        if(strcmp(lower(strtrim(selection.type)),'rectangle'))
          yi=find_id(ids,selection.y_variable_id);mask=gxtxt_selection_mask(selection,chunk{xi},chunk{yi});
        else mask=gxtxt_selection_mask(selection,chunk{xi});endif
        mask=logical(mask(:));
        if(numel(mask)!=C.nrows),error('GXTXT:Numeric','Dataset Selection mask length differs from chunk');endif
      endif
      values=chunk{1}(mask);n_input+=numel(values);
      finite=isfinite(values);
      if(any(!finite)&&strcmp(policy,'error')),error('GXTXT:Numeric','Dataset reduction contains NaN or Inf; set nonfinite=omit explicitly');endif
      values=values(finite);n_valid+=numel(values);
      if(!isempty(values)),state=op_reduce_accumulate(state,values);endif
    endwhile
  unwind_protect_cleanup
    try S=gxtxt_table_stream_close(S);catch;end_try_catch
  end_unwind_protect
  if(isempty(state)),error('GXTXT:Numeric','Dataset reduction has no finite selected observations');endif
  out=state;out.n_input=n_input;out.n_valid=n_valid;out.n_nonfinite=n_input-n_valid;
  out.dataset_id=dataset_id;out.variable_id=vid;out.unit=schema_unit(schema,vid);
  out.selection_id=selection_id(selection);out.execution='chunk_composable';
endfunction
function out=op_dataset_weighted_statistics(session,dataset_id,vid,wid,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{vid,wid});[vals,meta]=dataset_read(session,dataset_id,{vid,wid},selection,opts);r=op_weighted_statistics(vals{1},vals{2},opts);r.dataset_id=dataset_id;r.variable_id=vid;r.weight_variable_id=wid;r.unit=meta.units{1};r.weight_unit=meta.units{2};r.selection_id=selection_id(selection);out=r;
endfunction
function out=op_dataset_grid_info(session,dataset_id,xid,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{xid});validate_x_selection(selection,dataset_id,xid);[vals,meta]=dataset_read(session,dataset_id,{xid},selection,opts);r=op_grid_info(vals{1},opts);r.dataset_id=dataset_id;r.x_variable_id=xid;r.x_unit=meta.units{1};r.selection_id=selection_id(selection);out=r;
endfunction
function out=op_dataset_polynomial_fit(session,dataset_id,xid,yid,degree,opts)
  selection=opt(opts,'selection',struct('enabled',false));wid='';if(opt_has(opts,'weight_variable_id')),wid=strtrim(opts.weight_variable_id);endif;ids={xid,yid};if(!isempty(wid)),ids{end+1}=wid;endif;validate_dataset_ids(session,dataset_id,ids);validate_xy_selection(selection,dataset_id,xid,yid);[vals,meta]=dataset_read(session,dataset_id,ids,selection,opts);w=[];if(!isempty(wid)),w=vals{3};endif;r=op_polynomial_fit(vals{1},vals{2},degree,w,opts);r.dataset_id=dataset_id;r.x_variable_id=xid;r.y_variable_id=yid;r.weight_variable_id=wid;r.x_unit=meta.units{1};r.y_unit=meta.units{2};r.selection_id=selection_id(selection);out=r;
endfunction
function out=op_dataset_nonlinear_fit(session,dataset_id,xid,yid,model_fun,initial,opts)
  selection=opt(opts,'selection',struct('enabled',false));wid=opt_text(opts,'weight_variable_id','');
  sxid=opt_text(opts,'sigma_x_variable_id','');syid=opt_text(opts,'sigma_variable_id','');
  bound_xy=!isempty(sxid)||!isempty(syid);ids={xid,yid};fitopts=opts;
  if(bound_xy)
    if(isempty(sxid)||isempty(syid)||!isempty(wid)||opt_has(opts,'weights')||opt_has(opts,'sigma')||opt_has(opts,'sigma_x')||!strcmp(opt_text(opts,'fit_geometry','vertical_response'),'orthogonal_xy'))
      error('GXTXT:Numeric:ODR','Dataset XY fitting requires both sigma variable identities, explicit orthogonal_xy geometry and no competing measurement arrays or weights');
    endif
    ids{end+1}=sxid;ids{end+1}=syid;
  elseif(!isempty(wid)),ids{end+1}=wid;endif
  validate_dataset_ids(session,dataset_id,ids);validate_xy_selection(selection,dataset_id,xid,yid);
  [vals,meta,original_rows]=dataset_read(session,dataset_id,ids,selection,opts);
  if(isstruct(model_fun)&&(isfield(model_fun,'composition')||isfield(model_fun,'regional_composition')))
    model_fun=gxtxt_numeric_fit_model_v1(model_fun,numel(initial));
    declaration='composition';if(isfield(model_fun,'regional_composition')),declaration='regional_composition';endif
    for axis=1:2
      keys={'x_unit','y_unit'};declared_unit=model_fun.(declaration).recipe.(keys{axis});
      actual_unit=meta.units{axis};if(isempty(actual_unit)),actual_unit='unspecified';endif
      if(!strcmp(declared_unit,actual_unit)),error('GXTXT:Numeric:Model','Frozen model recipe units differ from the bound Dataset axes; convert data explicitly before fitting');endif
    endfor
  endif
  if(bound_xy)
    for axis=1:2
      if(isempty(meta.units{axis})||!strcmp(meta.units{axis},meta.units{axis+2}))
        error('GXTXT:Numeric:ODR','Dataset sigma columns must declare the same units as their respective axes; convert uncertainties explicitly using the public CORE unit scale before array fitting');
      endif
    endfor
    fitopts.sigma_x=vals{3};fitopts.sigma=vals{4};
  elseif(!isempty(wid)),fitopts.weights=vals{3};endif
  r=op_nonlinear_fit(model_fun,vals{1},vals{2},initial,fitopts);
  r.dataset_id=dataset_id;r.x_variable_id=xid;r.y_variable_id=yid;r.weight_variable_id=wid;
  r.x_unit=meta.units{1};r.y_unit=meta.units{2};r.selection_id=selection_id(selection);
  if(isfield(r,'source_row_positions'))
    r.source_row_ordinals=original_rows(r.source_row_positions);r.dropped_row_ordinals=original_rows(r.dropped_row_positions);r.row_identity='original_dataset_one_based_uint64';
  endif
  if(bound_xy),r.sigma_x_variable_id=sxid;r.sigma_variable_id=syid;r.sigma_x_unit=meta.units{3};r.sigma_unit=meta.units{4};endif
  out=r;
endfunction
function out=op_dataset_smooth(session,dataset_id,xid,yid,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{xid,yid});validate_xy_selection(selection,dataset_id,xid,yid);
  [vals,meta,rows]=dataset_read(session,dataset_id,{xid,yid},selection,opts);
  r=op_smooth(vals{1},vals{2},opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);
  out.source_row_ordinals=rows(r.source_row_positions);out.dropped_row_ordinals=rows(r.dropped_row_positions);out.row_identity='original_dataset_one_based_uint64';
endfunction
function out=op_dataset_find_peaks(session,dataset_id,xid,yid,opts)
  [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts);r=op_find_peaks(vals{1},vals{2},opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);
endfunction
function out=op_dataset_baseline(session,dataset_id,xid,yid,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{xid,yid});validate_xy_selection(selection,dataset_id,xid,yid);
  [vals,meta,rows]=dataset_read(session,dataset_id,{xid,yid},selection,opts);
  if(strcmp(opt_text(opts,'method','constant'),'anchors')),error('GXTXT:Numeric','Dataset baseline anchors must be supplied through the low-level baseline API');endif
  r=op_baseline(vals{1},vals{2},[],[],opts);out=annotate_xy(r,dataset_id,xid,yid,meta,selection);
  out.source_row_ordinals=rows(r.source_row_positions);out.dropped_row_ordinals=rows(r.dropped_row_positions);out.row_identity='original_dataset_one_based_uint64';
endfunction
function [vals,meta,selection]=dataset_xy(session,dataset_id,xid,yid,opts)
  selection=opt(opts,'selection',struct('enabled',false));validate_dataset_ids(session,dataset_id,{xid,yid});validate_xy_selection(selection,dataset_id,xid,yid);[vals,meta]=dataset_read(session,dataset_id,{xid,yid},selection,opts);
endfunction
function r=annotate_xy(r,dataset_id,xid,yid,meta,selection)
  r.dataset_id=dataset_id;r.x_variable_id=xid;r.y_variable_id=yid;r.x_unit=meta.units{1};r.y_unit=meta.units{2};r.selection_id=selection_id(selection);
endfunction
function validate_dataset_ids(session,dataset_id,ids)
  ensure_dataset_api();if(!ischar(session)||isempty(strtrim(session))||exist(session,'dir')!=7),error('GXTXT:Numeric','Dataset session directory does not exist');endif;if(!ischar(dataset_id)||isempty(strtrim(dataset_id))),error('GXTXT:Numeric','dataset_id is required');endif
  for i=1:numel(ids),if(!ischar(ids{i})||isempty(strtrim(ids{i}))),error('GXTXT:Numeric','stable variable_id is required');endif,endfor
endfunction
function ensure_dataset_api()
  req={'gxtxt_table_stream_open_dataset','gxtxt_table_stream_next','gxtxt_table_stream_close','gxtxt_selection_mask'};
  for i=1:numel(req),if(exist(req{i},'file')!=2),error('GXTXT:Numeric','required public GX-TXT Dataset/Table Stream API function is unavailable: %s',req{i});endif,endfor
endfunction
function [values,meta,original_rows]=dataset_read(session,dataset_id,requested,selection,opts)
  ids=requested(:)';
  if(selection_enabled(selection))
    require_selection_dataset(selection,dataset_id);if(!isfield(selection,'x_variable_id')||isempty(strtrim(selection.x_variable_id))),error('GXTXT:Numeric','Dataset Selection must expose stable x_variable_id');endif;ids=append_unique(ids,selection.x_variable_id);
    if(strcmp(lower(strtrim(selection.type)),'rectangle')),if(!isfield(selection,'y_variable_id')||isempty(strtrim(selection.y_variable_id))),error('GXTXT:Numeric','Rectangle Dataset Selection must expose stable y_variable_id');endif;ids=append_unique(ids,selection.y_variable_id);endif
  endif
  chunk_rows=opt_int(opts,'chunk_rows',65536);if(chunk_rows<1),error('GXTXT:Numeric','chunk_rows must be >= 1');endif
  S=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','resource'));schema=S.schema;
  selected=selection_enabled(selection);nids=numel(ids);parts=cell(1,nids);
  capture_rows=nargout>2;row_parts={};original_rows=uint64([]);
  for j=1:nids,parts{j}={};endfor
  preallocate=!selected&&isfield(S,'row_count')&&isnumeric(S.row_count)&&isscalar(S.row_count)&&isfinite(S.row_count)&&S.row_count>=0&&S.row_count==fix(S.row_count)&&S.row_count<=50000000;
  if(preallocate),declared_rows=S.row_count;allvals=cell(1,nids);for j=1:nids,allvals{j}=zeros(declared_rows,1);endfor;written=0;endif
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows<1),continue;endif
      chunk=cell(1,nids);
      for j=1:nids
        col=C.values{j};
        if(!(isnumeric(col)||islogical(col))),error('GXTXT:Numeric','Dataset variable %s is not numeric',ids{j});endif
        chunk{j}=double(col(:));
        if(numel(chunk{j})!=C.nrows),error('GXTXT:Numeric','Dataset variables are not row-aligned');endif
      endfor
      if(selected)
        xi=find_id(ids,selection.x_variable_id);
        if(strcmp(lower(strtrim(selection.type)),'rectangle'))
          yi=find_id(ids,selection.y_variable_id);mask=gxtxt_selection_mask(selection,chunk{xi},chunk{yi});
        else
          mask=gxtxt_selection_mask(selection,chunk{xi});
        endif
        mask=logical(mask(:));
        if(numel(mask)!=C.nrows),error('GXTXT:Numeric','Dataset Selection mask length differs from chunk');endif
        for j=1:nids,parts{j}{end+1}=chunk{j}(mask);endfor
      elseif(preallocate)
        stop=written+C.nrows;
        if(stop>numel(allvals{1})),error('GXTXT:Numeric','Dataset row count exceeds declared metadata');endif
        for j=1:nids,allvals{j}(written+1:stop)=chunk{j};endfor
        written=stop;
      else
        for j=1:nids,parts{j}{end+1}=chunk{j};endfor
      endif
      if(capture_rows)
        identities=uint64(C.first_row)+(uint64(0:C.nrows-1))';
        if(selected),identities=identities(mask);endif
        row_parts{end+1}=identities;
      endif
    endwhile
  unwind_protect_cleanup
    try S=gxtxt_table_stream_close(S);catch;end_try_catch
  end_unwind_protect
  if(preallocate)
    if(written!=declared_rows),for j=1:nids,allvals{j}=allvals{j}(1:written);endfor;endif
  else
    allvals=cell(1,nids);
    for j=1:nids,if(isempty(parts{j})),allvals{j}=zeros(0,1);else allvals{j}=vertcat(parts{j}{:});endif,endfor
  endif
  values=cell(1,numel(requested));units=cell(1,numel(requested));for j=1:numel(requested),k=find_id(ids,requested{j});values{j}=allvals{k};units{j}=schema_unit(schema,requested{j});endfor;meta=struct('units',{units});
  if(capture_rows&&!isempty(row_parts)),original_rows=vertcat(row_parts{:});endif
endfunction
function ids=append_unique(ids,id),if(find_id(ids,id)==0),ids{end+1}=id;endif,endfunction
function idx=find_id(ids,id),idx=0;for i=1:numel(ids),if(strcmp(ids{i},id)),idx=i;return;endif,endfor,endfunction
function unit=schema_unit(schema,id)
  unit='';if(!isstruct(schema)),return;endif
  vars=schema;if(isscalar(schema)&&isfield(schema,'variables')),vars=schema.variables;endif
  for i=1:numel(vars)
    if(isfield(vars(i),'variable_id')&&strcmp(vars(i).variable_id,id))
      if(isfield(vars(i),'unit')),unit=vars(i).unit;endif;return;
    endif
  endfor
endfunction
function tf=selection_enabled(S),tf=isstruct(S)&&isfield(S,'enabled')&&logical(S.enabled);endfunction
function id=selection_id(S),id='';if(selection_enabled(S)&&isfield(S,'id')),id=S.id;endif,endfunction
function require_selection_dataset(S,dataset_id),if(!isfield(S,'source_dataset_id')||!strcmp(strtrim(S.source_dataset_id),dataset_id)),error('GXTXT:Numeric','Dataset Selection source dataset does not match requested dataset');endif,endfunction
function validate_x_selection(S,dataset_id,xid)
  if(!selection_enabled(S)),return;endif;require_selection_dataset(S,dataset_id);if(!strcmp(strtrim(S.x_variable_id),xid)),error('GXTXT:Numeric','Dataset Selection X variable does not match requested X variable');endif
endfunction
function validate_xy_selection(S,dataset_id,xid,yid)
  if(!selection_enabled(S)),return;endif;validate_x_selection(S,dataset_id,xid);if(strcmp(lower(strtrim(S.type)),'rectangle')&&!strcmp(strtrim(S.y_variable_id),yid)),error('GXTXT:Numeric','Rectangle Dataset Selection Y variable does not match requested Y variable');endif
endfunction
function u=combined_unit(a,b,op)
  a=strtrim(a);b=strtrim(b);if(isempty(a)&&isempty(b)),u='';elseif(isempty(a)),u=b;elseif(isempty(b)),u=a;else u=[a op b];endif
endfunction

% Generic real-array operations use exact shapes, with scalar expansion only.
function a=array_real(a,name)
  if(!isnumeric(a)&&!islogical(a)),error('GXTXT:Numeric','%s must be numeric',name);endif
  if(!isreal(a)||ndims(a)>2),error('GXTXT:Numeric','%s must be a real scalar, vector or matrix',name);endif
  a=double(a);
endfunction
function policy=array_policy(opts)
  policy=opt_text(opts,'nonfinite','error');
  if(!any(strcmp(policy,{'error','ieee'}))),error('GXTXT:Numeric','array nonfinite policy must be error or ieee');endif
endfunction
function array_check_finite(a,opts,name)
  if(strcmp(array_policy(opts),'error')&&any(!isfinite(a(:)))),error('GXTXT:Numeric','%s contains NaN or Inf',name);endif
endfunction
function [a,b]=array_pair(a,b)
  a=array_real(a,'first operand');b=array_real(b,'second operand');
  if(!isscalar(a)&&!isscalar(b)&&!isequal(size(a),size(b))),error('GXTXT:Numeric','array operands have different shapes');endif
endfunction
function z=complex_pair(real_part,imag_part,opts,name)
  [re,im]=array_pair(real_part,imag_part);
  array_check_finite(re,opts,[name ' real part']);array_check_finite(im,opts,[name ' imaginary part']);
  z=complex(re,im);
endfunction
function out=op_complex_unary(name,real_part,imag_part,opts)
  name=lower(strtrim(name));z=complex_pair(real_part,imag_part,opts,'complex operand');
  switch(name)
    case 'conjugate',v=conj(z);
    case 'magnitude',v=abs(z);
    case 'magnitude_squared',v=real(z).^2+imag(z).^2;
    case 'phase_rad',v=angle(z);
    case 'phase_deg',v=angle(z)*180/pi;
    case 'real',v=real(z);
    case 'imag',v=imag(z);
    otherwise,error('GXTXT:Numeric','unknown complex unary operation: %s',name);
  endswitch
  array_check_finite(v,opts,'complex unary result');
  if(strcmp(name,'conjugate')),out=struct('real',real(v),'imaginary',imag(v));
  else out=struct('values',v);endif
endfunction
function out=op_complex_binary(name,real_a,imag_a,real_b,imag_b,opts)
  name=lower(strtrim(name));a=complex_pair(real_a,imag_a,opts,'first complex operand');
  b=complex_pair(real_b,imag_b,opts,'second complex operand');
  if(!isscalar(a)&&!isscalar(b)&&!isequal(size(a),size(b))),error('GXTXT:Numeric','complex operands have different shapes');endif
  switch(name)
    case 'add',v=a+b;
    case 'subtract',v=a-b;
    case 'multiply',v=a.*b;
    case 'divide',v=a./b;
    otherwise,error('GXTXT:Numeric','unknown complex binary operation: %s',name);
  endswitch
  array_check_finite(v,opts,'complex binary result');
  out=struct('real',real(v),'imaginary',imag(v));
endfunction
function out=op_unwrap(phase,opts)
  phase=array_real(phase,'phase');
  if(!isvector(phase)),error('GXTXT:Numeric','unwrap requires a phase vector');endif
  array_check_finite(phase,opts,'phase');period=opt_num(opts,'period',2*pi);
  if(!isscalar(period)||!isfinite(period)||period<=0),error('GXTXT:Numeric','unwrap period must be finite and positive');endif
  v=phase;delta=diff(phase);jumps=zeros(size(delta));
  crossing=isfinite(delta)&abs(delta)>period/2;
  jumps(crossing)=-period*round(delta(crossing)/period);
  v(2:end)=phase(2:end)+cumsum(jumps);
  array_check_finite(v,opts,'unwrapped phase');out=struct('values',v,'period',period);
endfunction
function out=op_normal_cdf(x,mu,sigma,opts)
  [x,mu]=array_pair(x,mu);[x,sigma]=array_pair(x,sigma);
  if(!isscalar(mu)&&!isscalar(sigma)&&!isequal(size(mu),size(sigma))),error('GXTXT:Numeric','normal CDF parameter shapes differ');endif
  array_check_finite(x,opts,'normal CDF input');array_check_finite(mu,opts,'normal CDF mean');array_check_finite(sigma,opts,'normal CDF scale');
  if(any(sigma(:)<=0)),error('GXTXT:Numeric','normal CDF scale must be positive');endif
  v=0.5*erfc(-(x-mu)./(sigma*sqrt(2)));
  array_check_finite(v,opts,'normal CDF result');out=struct('values',v);
endfunction
function out=op_student_t_cdf(t,df,opts)
  [t,df]=array_pair(t,df);array_check_finite(t,opts,'Student-t input');array_check_finite(df,opts,'Student-t degrees of freedom');
  if(any(df(:)<=0)),error('GXTXT:Numeric','Student-t degrees of freedom must be positive');endif
  z=betainc(df./(df+t.^2),df/2,0.5);
  v=0.5*z;
  if(isscalar(t))
    if(t>=0),v=1-0.5*z;endif
  else
    v(t>=0)=1-0.5*z(t>=0);
  endif
  array_check_finite(v,opts,'Student-t CDF result');out=struct('values',v);
endfunction
function out=op_student_t_quantile(p,df,opts)
  if(!isnumeric(p)||!isscalar(p)||!isreal(p)||!isfinite(p)||p<0||p>1|| ...
     !isnumeric(df)||!isscalar(df)||!isreal(df)||!isfinite(df)||df<=0)
    error('GXTXT:Numeric','Student-t quantile requires probability in [0,1] and positive finite degrees of freedom');
  endif
  if(p==0),value=-Inf;
  elseif(p==1),value=Inf;
  elseif(p==0.5),value=0;
  else
    target=max(p,1-p);lo=0;hi=1;
    while(op_student_t_cdf(hi,df,struct()).values<target)
      hi*=2;if(hi>1e15),error('GXTXT:Numeric','Student-t quantile exceeds supported numeric range');endif
    endwhile
    for k=1:90
      mid=(lo+hi)/2;
      if(op_student_t_cdf(mid,df,struct()).values<target),lo=mid;else hi=mid;endif
    endfor
    value=(lo+hi)/2;if(p<0.5),value=-value;endif
  endif
  out=struct('values',value,'probability',p,'degrees_of_freedom',df);
endfunction
function out=op_hypothesis_test(method,x,y,opts)
  if(!ischar(method)),error('GXTXT:Numeric','hypothesis test method must be a string');endif
  method=lower(strtrim(method));
  allowed={'one_sample_t','independent_t','welch_t','paired_t','mann_whitney','signed_rank'};
  if(!any(strcmp(method,allowed))),error('GXTXT:Numeric','unsupported hypothesis test method: %s',method);endif
  alternative=opt_text(opts,'alternative','two_sided');
  if(!any(strcmp(alternative,{'two_sided','greater','less'}))),error('GXTXT:Numeric','alternative must be two_sided, greater or less');endif
  confidence=opt_num(opts,'confidence',0.95);
  if(confidence<=0||confidence>=1),error('GXTXT:Numeric','confidence must be strictly between 0 and 1');endif
  mu0=opt_num(opts,'mu0',0);policy=nonfinite_policy(opts);
  x=real_vector(x,'first sample',false);nx_input=numel(x);
  if(any(strcmp(method,{'paired_t','signed_rank'})))
    [x,y,~,n]=finite_pair(x,y,opts,2);ny_input=nx_input;nx=n;ny=n;
  elseif(strcmp(method,'one_sample_t'))
    if(!isempty(y)),error('GXTXT:Numeric','one-sample t-test does not accept a second sample');endif
    x=finite_vector(x,'first sample',opts,2);nx=numel(x);ny=0;ny_input=0;
  else
    y=real_vector(y,'second sample',false);ny_input=numel(y);
    x=finite_vector(x,'first sample',opts,2);y=finite_vector(y,'second sample',opts,2);
    nx=numel(x);ny=numel(y);
  endif
  statistic=NaN;df=NaN;pvalue=NaN;estimate=NaN;se=NaN;sd=NaN;interval_margin=NaN;ci_lower=NaN;ci_upper=NaN;
  effect=NaN;effect_name='not_defined';approximation='exact';ci_status='not_defined_for_rank_test';
  if(any(strcmp(method,{'one_sample_t','paired_t','independent_t','welch_t'})))
    if(strcmp(method,'paired_t')),d=x-y;estimate=mean(d);sd=std(d,0);se=sd/sqrt(nx);df=nx-1;effect_name='cohen_dz';
    elseif(strcmp(method,'one_sample_t')),d=x;estimate=mean(x);sd=std(x,0);se=sd/sqrt(nx);df=nx-1;effect_name='cohen_d';
    else
      estimate=mean(x)-mean(y);vx=var(x,0);vy=var(y,0);
      if(strcmp(method,'independent_t'))
        df=nx+ny-2;sp2=((nx-1)*vx+(ny-1)*vy)/df;se=sqrt(sp2*(1/nx+1/ny));sd=sqrt(sp2);effect_name='cohen_d';
      else
        a=vx/nx;b=vy/ny;se=sqrt(a+b);
        if(a+b>0),df=(a+b)^2/(a^2/(nx-1)+b^2/(ny-1));else df=nx+ny-2;endif
        sd=NaN;effect_name='not_reported_for_welch';
      endif
    endif
    if(se==0)
      if(estimate==mu0),statistic=0;else statistic=sign(estimate-mu0)*Inf;endif
    else statistic=(estimate-mu0)/se;endif
    pvalue=student_pvalue(statistic,df,alternative);
    if(isfinite(sd)&&sd>0),effect=(estimate-mu0)/sd;
    elseif(isfinite(sd)&&sd==0&&estimate==mu0),effect=0;
    elseif(isfinite(sd)&&sd==0),effect=sign(estimate-mu0)*Inf;endif
    if(strcmp(alternative,'two_sided'))
      crit=op_student_t_quantile((1+confidence)/2,df,struct()).values;
      interval_margin=crit*se;ci_lower=estimate-interval_margin;ci_upper=estimate+interval_margin;
    elseif(strcmp(alternative,'greater'))
      crit=op_student_t_quantile(confidence,df,struct()).values;
      interval_margin=crit*se;ci_lower=estimate-interval_margin;ci_upper=Inf;
    else
      crit=op_student_t_quantile(confidence,df,struct()).values;
      interval_margin=crit*se;ci_lower=-Inf;ci_upper=estimate+interval_margin;
    endif
    ci_status='defined';
  elseif(strcmp(method,'mann_whitney'))
    if(mu0!=0),error('GXTXT:Numeric','Mann-Whitney null shift must be zero');endif
    pooled=[x(:);y(:)];N=numel(pooled);r=rank_average(pooled);ranksum=sum(r(1:nx));
    statistic=ranksum-nx*(nx+1)/2;estimate=statistic;effect=2*statistic/(nx*ny)-1;effect_name='rank_biserial_correlation';
    if(N<=20)
      pvalue=exact_rank_sum_p(r,nx,ranksum,alternative);approximation='exact_conditional_permutation';
    else
      [~,~,group]=unique(pooled);counts=accumarray(group,1);ties=sum(counts.^3-counts);
      variance=nx*ny/12*((N+1)-ties/(N*(N-1)));
      if(variance<=0),error('GXTXT:Numeric','Mann-Whitney statistic has zero null variance');endif
      pvalue=normal_rank_p(statistic,nx*ny/2,sqrt(variance),alternative);
      approximation='tie_corrected_normal_with_continuity';
    endif
  else
    if(mu0!=0),error('GXTXT:Numeric','signed-rank null shift must be zero');endif
    differences=x-y;differences=differences(differences!=0);
    if(isempty(differences)),error('GXTXT:Numeric','signed-rank test has no nonzero differences');endif
    ranks=rank_average(abs(differences));N=numel(ranks);statistic=sum(ranks(differences>0));
    total=sum(ranks);estimate=statistic;effect=2*statistic/total-1;effect_name='matched_pairs_rank_biserial';
    if(N<=20)
      pvalue=exact_signed_rank_p(ranks,statistic,alternative);approximation='exact_conditional_signs';
    else
      variance=sum(ranks.^2)/4;
      if(variance<=0),error('GXTXT:Numeric','signed-rank statistic has zero null variance');endif
      pvalue=normal_rank_p(statistic,total/2,sqrt(variance),alternative);
      approximation='tie_corrected_normal_with_continuity';
    endif
  endif
  out=struct('method',method,'statistic',statistic,'degrees_of_freedom',df, ...
    'n_input_x',nx_input,'n_input_y',ny_input,'n_x',nx,'n_y',ny, ...
    'p_value',min(max(pvalue,0),1),'alternative',alternative,'confidence',confidence, ...
    'null_value',mu0,'estimate',estimate,'ci_lower',ci_lower,'ci_upper',ci_upper, ...
    'ci_status',ci_status,'standard_error',se,'test_standard_deviation',sd,'interval_margin',interval_margin,'effect_size',effect,'effect_name',effect_name, ...
    'nonfinite_policy',policy,'approximation',approximation);
endfunction
function p=student_pvalue(t,df,alternative)
  % Direct small tail avoids catastrophic 1-CDF cancellation.
  if(isinf(t)),tail=0;else tail=0.5*betainc(df/(df+t^2),df/2,0.5);endif
  if(strcmp(alternative,'two_sided')),p=2*tail;
  elseif(strcmp(alternative,'greater')),if(t>=0),p=tail;else p=1-tail;endif
  else if(t<=0),p=tail;else p=1-tail;endif,endif
endfunction

function p=normal_rank_p(statistic,mu,sd,alternative)
  if(strcmp(alternative,'greater'))
    z=(statistic-mu-0.5)/sd;p=0.5*erfc(z/sqrt(2));
  elseif(strcmp(alternative,'less'))
    z=(statistic-mu+0.5)/sd;p=0.5*erfc(-z/sqrt(2));
  else
    z=max(0,abs(statistic-mu)-0.5)/sd;p=erfc(z/sqrt(2));
  endif
endfunction
function p=exact_rank_sum_p(ranks,n1,observed,alternative)
  scaled=round(2*ranks(:));N=numel(scaled);maxsum=sum(scaled);dp=zeros(n1+1,maxsum+1);dp(1,1)=1;seen=0;
  for i=1:N
    weight=scaled(i);seen+=1;
    for k=min(n1,seen):-1:1
      for s=maxsum:-1:weight
        dp(k+1,s+1)+=dp(k,s-weight+1);
      endfor
    endfor
  endfor
  counts=dp(n1+1,:);total=sum(counts);point=round(2*observed);
  lower=sum(counts(1:point+1))/total;upper=sum(counts(point+1:end))/total;
  if(strcmp(alternative,'greater')),p=upper;
  elseif(strcmp(alternative,'less')),p=lower;
  else p=min(1,2*min(lower,upper));endif
endfunction
function p=exact_signed_rank_p(ranks,observed,alternative)
  scaled=round(2*ranks(:));maxsum=sum(scaled);counts=zeros(1,maxsum+1);counts(1)=1;
  for i=1:numel(scaled)
    weight=scaled(i);
    for s=maxsum:-1:weight
      counts(s+1)+=counts(s-weight+1);
    endfor
  endfor
  total=sum(counts);point=round(2*observed);
  lower=sum(counts(1:point+1))/total;upper=sum(counts(point+1:end))/total;
  if(strcmp(alternative,'greater')),p=upper;
  elseif(strcmp(alternative,'less')),p=lower;
  else p=min(1,2*min(lower,upper));endif
endfunction
function out=op_one_way_anova(values,groups,opts)
  values=real_vector(values,'ANOVA values',false);n_input=numel(values);
  if(isnumeric(groups)||islogical(groups))
    if(!isreal(groups)||!isvector(groups)||numel(groups)!=n_input)
      error('GXTXT:Numeric','ANOVA group labels must match value count');
    endif
    numeric_groups=double(groups(:));labels=cell(n_input,1);valid_group=isfinite(numeric_groups);
    for i=1:n_input,if(valid_group(i)),labels{i}=sprintf('%.17g',numeric_groups(i));else labels{i}='';endif,endfor
  elseif(iscell(groups))
    if(!isvector(groups)||numel(groups)!=n_input),error('GXTXT:Numeric','ANOVA group labels must match value count');endif
    labels=groups(:);valid_group=false(n_input,1);
    for i=1:n_input
      if(!ischar(labels{i})),error('GXTXT:Numeric','ANOVA group labels must be strings');endif
      labels{i}=strtrim(labels{i});valid_group(i)=!isempty(labels{i});
    endfor
  else error('GXTXT:Numeric','ANOVA groups must be a numeric vector or cell array of strings');endif
  method=opt_text(opts,'method','ordinary');
  if(!any(strcmp(method,{'ordinary','welch'}))),error('GXTXT:Numeric','ANOVA method must be ordinary or welch');endif
  good=isfinite(values)&valid_group;policy=nonfinite_policy(opts);
  if(any(!good)&&strcmp(policy,'error')),error('GXTXT:Numeric','ANOVA input contains nonfinite values or missing group labels');endif
  values=values(good);labels=labels(good);n_valid=numel(values);
  names={};indices=zeros(n_valid,1);
  for i=1:n_valid
    k=find(strcmp(names,labels{i}),1);
    if(isempty(k)),names{end+1}=labels{i};k=numel(names);endif
    indices(i)=k;
  endfor
  k=numel(names);if(k<2),error('GXTXT:Numeric','ANOVA requires at least two nonempty groups');endif
  counts=zeros(k,1);means=zeros(k,1);variances=NaN(k,1);sds=NaN(k,1);
  for j=1:k
    group_values=values(indices==j);counts(j)=numel(group_values);means(j)=mean(group_values);
    if(counts(j)>1),variances(j)=var(group_values,0);sds(j)=sqrt(variances(j));endif
  endfor
  overall=mean(values);ss_between=sum(counts.*(means-overall).^2);
  ss_within=0;for j=1:k,block=values(indices==j);ss_within+=sum((block-means(j)).^2);endfor
  ss_total=ss_between+ss_within;df_between=k-1;df_within=n_valid-k;
  if(df_within<=0),error('GXTXT:Numeric','ANOVA requires within-group degrees of freedom');endif
  ms_between=ss_between/df_between;ms_within=ss_within/df_within;
  eta_squared=NaN;omega_squared=NaN;effect_status='not_defined_for_welch';
  if(strcmp(method,'ordinary'))
    if(ms_within==0)
      if(ms_between==0),error('GXTXT:Numeric','ANOVA F statistic is undefined for identical constant groups');endif
      F=Inf;p=0;
    else
      F=ms_between/ms_within;p=betainc(df_within/(df_within+df_between*F),df_within/2,df_between/2);
    endif
    if(ss_total>0),eta_squared=ss_between/ss_total;omega_squared=(ss_between-df_between*ms_within)/(ss_total+ms_within);effect_status='ordinary_anova';endif
    denominator_df=df_within;
  else
    if(any(counts<2)||any(variances<=0)||any(!isfinite(variances)))
      error('GXTXT:Numeric','Welch ANOVA requires at least two observations and positive variance in every group');
    endif
    weights=counts./variances;total_weight=sum(weights);weighted_mean=sum(weights.*means)/total_weight;
    correction_sum=sum(((1-weights/total_weight).^2)./(counts-1));
    correction=1+(2*(k-2)/(k^2-1))*correction_sum;
    F=(sum(weights.*(means-weighted_mean).^2)/df_between)/correction;
    denominator_df=(k^2-1)/(3*correction_sum);
    p=betainc(denominator_df/(denominator_df+df_between*F),denominator_df/2,df_between/2);
  endif
  out=struct('method',method,'n_input',n_input,'n_valid',n_valid,'n_nonfinite',n_input-n_valid, ...
    'group_count',k,'group_names',{names(:)},'group_counts',counts,'group_means',means, ...
    'group_variances',variances,'group_standard_deviations',sds,'overall_mean',overall, ...
    'ss_between',ss_between,'ss_within',ss_within,'ss_total',ss_total, ...
    'df_between',df_between,'df_within',df_within,'ms_between',ms_between,'ms_within',ms_within, ...
    'f_statistic',F,'f_numerator_df',df_between,'f_denominator_df',denominator_df, ...
    'p_value',min(max(p,0),1),'eta_squared',eta_squared,'omega_squared',omega_squared, ...
    'effect_status',effect_status,'nonfinite_policy',policy);
endfunction
function out=op_f_cdf(f,df1,df2,opts)
  [f,df1]=array_pair(f,df1);[f,df2]=array_pair(f,df2);
  if(!isscalar(df1)&&!isscalar(df2)&&!isequal(size(df1),size(df2))),error('GXTXT:Numeric','F CDF parameter shapes differ');endif
  array_check_finite(f,opts,'F input');array_check_finite(df1,opts,'F numerator degrees of freedom');array_check_finite(df2,opts,'F denominator degrees of freedom');
  if(any(df1(:)<=0)||any(df2(:)<=0)),error('GXTXT:Numeric','F degrees of freedom must be positive');endif
  if(any(f(:)<0)),error('GXTXT:Numeric','F variate must be nonnegative');endif
  v=betainc((df1.*f)./(df1.*f+df2),df1/2,df2/2);
  array_check_finite(v,opts,'F CDF result');out=struct('values',v);
endfunction
function out=op_matrix_svd(A,opts)
  A=array_real(A,'matrix');
  if(isscalar(A)||isvector(A)||isempty(A)),error('GXTXT:Numeric','matrix SVD requires a nonempty two-dimensional matrix');endif
  array_check_finite(A,opts,'matrix SVD input');
  [U,S,V]=svd(A,'econ');singular_values=diag(S);
  if(isempty(singular_values)),tol=0;rnk=0;condition_number=Inf;
  else
    tol=max(size(A))*eps(max(singular_values));rnk=sum(singular_values>tol);
    if(rnk<min(size(A))),condition_number=Inf;
    else condition_number=max(singular_values)/min(singular_values);endif
  endif
  out=struct('u',U,'singular_values',singular_values,'v',V,'rank',rnk,'tolerance',tol,'condition_number',condition_number,'rows',rows(A),'cols',columns(A));
endfunction
function out=op_resample_indices(population_size,draw_count,replicates,seed,opts)
  values=[population_size,draw_count,replicates,seed];
  if(any(!isfinite(values))||any(values!=fix(values))),error('GXTXT:Numeric','resampling dimensions and seed must be finite integers');endif
  n=double(population_size);k=double(draw_count);r=double(replicates);state=double(seed);
  if(n<1||n>flintmax()||k<1||r<1||state<1||state>=2147483647),error('GXTXT:Numeric','resampling dimensions must be positive and seed in 1..2147483646');endif
  replace=opt_bool(opts,'replace',true);
  if(!replace&&k>n),error('GXTXT:Numeric','draw count exceeds population without replacement');endif
  if(k*r>10000000),error('GXTXT:Numeric','resampling request exceeds ten million output indices');endif
  indices=zeros(r,k);
  for row=1:r
    if(replace)
      for col=1:k
        state=mod(16807*state,2147483647);
        indices(row,col)=1+floor(n*state/2147483647);
      endfor
    else
      use_map=n>1000000;
      if(use_map),pool=containers.Map('KeyType','double','ValueType','double');
      else pool=1:n;endif
      for col=1:k
        state=mod(16807*state,2147483647);
        j=col+floor((n-col+1)*state/2147483647);
        if(use_map)
          if(isKey(pool,col)),left=pool(col);else left=col;endif
          if(isKey(pool,j)),right=pool(j);else right=j;endif
          pool(col)=right;pool(j)=left;indices(row,col)=right;
        else
          tmp=pool(col);pool(col)=pool(j);pool(j)=tmp;
          indices(row,col)=pool(col);
        endif
      endfor
    endif
  endfor
  out=struct('indices',indices,'population_size',n,'draw_count',k,'replicates',r,'seed',seed,'next_seed',state,'replace',logical(replace),'generator','park_miller_16807_v1');
endfunction
function mask=array_valid_mask(mask,shape)
  mask=array_real(mask,'mask');
  if(any(!isfinite(mask(:)))||any(mask(:)!=0&mask(:)!=1)),error('GXTXT:Numeric','mask values must be logical 0 or 1');endif
  if(!isscalar(mask)&&!isequal(size(mask),shape)),error('GXTXT:Numeric','mask shape does not match values');endif
  if(isscalar(mask)),mask=repmat(logical(mask),shape);else mask=logical(mask);endif
endfunction
function out=op_array_unary(name,a,opts)
  name=lower(strtrim(name));a=array_real(a,'operand');
  if(any(strcmp(name,{'is_finite','is_nan','is_inf','is_pos_inf','is_neg_inf'})))
    switch(name)
      case 'is_finite',v=isfinite(a);
      case 'is_nan',v=isnan(a);
      case 'is_inf',v=isinf(a);
      case 'is_pos_inf',v=isinf(a)&a>0;
      case 'is_neg_inf',v=isinf(a)&a<0;
    endswitch
    out=struct('values',v);return;
  endif
  array_check_finite(a,opts,'operand');
  switch(name)
    case 'negate',v=-a;
    case 'abs',v=abs(a);
    case 'sign',v=sign(a);
    case 'sqrt',v=sqrt(a);
    case 'square',v=a.^2;
    case 'reciprocal',v=1./a;
    case 'exp',v=exp(a);
    case 'expm1',v=expm1(a);
    case 'log',v=log(a);
    case 'log10',v=log10(a);
    case 'log1p',v=log1p(a);
    case 'sin',v=sin(a);
    case 'cos',v=cos(a);
    case 'tan',v=tan(a);
    case 'asin',v=asin(a);
    case 'acos',v=acos(a);
    case 'atan',v=atan(a);
    case 'sinh',v=sinh(a);
    case 'cosh',v=cosh(a);
    case 'tanh',v=tanh(a);
    case 'floor',v=floor(a);
    case 'ceil',v=ceil(a);
    case 'round',v=round(a);
    otherwise,error('GXTXT:Numeric','unknown array unary operation: %s',name);
  endswitch
  if(!isreal(v)),error('GXTXT:Numeric','array unary result is outside the real-number domain');endif
  array_check_finite(v,opts,'array unary result');out=struct('values',v);
endfunction
function out=op_array_binary(name,a,b,opts)
  name=lower(strtrim(name));[a,b]=array_pair(a,b);array_check_finite(a,opts,'first operand');array_check_finite(b,opts,'second operand');
  switch(name)
    case 'add',v=a+b;
    case 'subtract',v=a-b;
    case 'multiply',v=a.*b;
    case 'divide',v=a./b;
    case 'power',v=a.^b;
    case 'minimum',v=min(a,b);
    case 'maximum',v=max(a,b);
    case 'atan2',v=atan2(a,b);
    case 'hypot',v=hypot(a,b);
    otherwise,error('GXTXT:Numeric','unknown array binary operation: %s',name);
  endswitch
  if(!isreal(v)),error('GXTXT:Numeric','array binary result is outside the real-number domain');endif
  array_check_finite(v,opts,'array binary result');out=struct('values',v);
endfunction
function out=op_array_compare(name,a,b,opts)
  name=lower(strtrim(name));[a,b]=array_pair(a,b);array_check_finite(a,opts,'first operand');array_check_finite(b,opts,'second operand');
  switch(name)
    case 'equal',v=a==b;
    case 'not_equal',v=a!=b;
    case 'less_than',v=a<b;
    case 'less_equal',v=a<=b;
    case 'greater_than',v=a>b;
    case 'greater_equal',v=a>=b;
    otherwise,error('GXTXT:Numeric','unknown array comparison: %s',name);
  endswitch
  out=struct('values',v);
endfunction
function out=op_array_mask(name,a,rest)
  name=lower(strtrim(name));a=array_real(a,'first mask');
  if(strcmp(name,'logical_not'))
    if(!isempty(rest)),error('GXTXT:Numeric','logical_not accepts one mask');endif
    ma=array_valid_mask(a,size(a));v=!ma;
  else
    if(numel(rest)!=1),error('GXTXT:Numeric','binary logical operation requires two masks');endif
    b=array_real(rest{1},'second mask');[a,b]=array_pair(a,b);
    shape=size(a);if(isscalar(a)),shape=size(b);endif
    ma=array_valid_mask(a,shape);mb=array_valid_mask(b,shape);
    switch(name)
      case 'logical_and',v=ma&mb;
      case 'logical_or',v=ma|mb;
      case 'logical_xor',v=xor(ma,mb);
      otherwise,error('GXTXT:Numeric','unknown logical mask operation: %s',name);
    endswitch
  endif
  out=struct('values',v);
endfunction
function out=op_array_select(values,mask)
  values=array_real(values,'values');mask=array_valid_mask(mask,size(values));out=struct('values',values(mask));
endfunction
function out=op_array_where(mask,a,b)
  a=array_real(a,'true values');b=array_real(b,'false values');
  shape=size(mask);if(isscalar(mask)),if(!isscalar(a)),shape=size(a);elseif(!isscalar(b)),shape=size(b);endif,endif
  mask=array_valid_mask(mask,shape);
  if(!isscalar(a)&&!isequal(size(a),shape)),error('GXTXT:Numeric','true-value shape does not match mask');endif
  if(!isscalar(b)&&!isequal(size(b),shape)),error('GXTXT:Numeric','false-value shape does not match mask');endif
  if(isscalar(a)),a=repmat(a,shape);endif;if(isscalar(b)),b=repmat(b,shape);endif
  v=b;v(mask)=a(mask);out=struct('values',v);
endfunction
function out=op_array_reduce(name,a,opts)
  name=lower(strtrim(name));a=array_real(a,'values');
  axis=opt_int(opts,'axis',0);if(!any(axis==[0 1 2])),error('GXTXT:Numeric','array reduction axis must be 0, 1 or 2');endif
  requested_axis=axis;input_shape=size(a);
  if(axis==0),a=a(:);axis=1;endif
  names={'sum','product','minimum','maximum','argmin','argmax','count','valid_count','mean','median','variance_population','variance_sample','std_population','std_sample','rms','quantile','any','all','count_true'};
  if(!any(strcmp(name,names))),error('GXTXT:Numeric','unknown array reduction: %s',name);endif
  if(axis==1)
    v=zeros(1,columns(a));n_input=zeros(size(v));n_valid=zeros(size(v));
    for j=1:columns(a),[v(j),n_input(j),n_valid(j)]=reduce_one(name,a(:,j),opts);endfor;
  else
    v=zeros(rows(a),1);n_input=zeros(size(v));n_valid=zeros(size(v));
    for j=1:rows(a),[v(j),n_input(j),n_valid(j)]=reduce_one(name,a(j,:).',opts);endfor;
  endif
  if(any(strcmp(name,{'any','all'}))),v=logical(v);endif
  out=struct('values',v,'axis',axis,'requested_axis',requested_axis,'input_shape',input_shape, ...
    'action',name,'n_input',n_input,'n_valid',n_valid);
  if(strcmp(name,'quantile')),out.probability=opt_num(opts,'probability',.5);out.quantile_definition='Hyndman-Fan type 7 linear interpolation';endif
endfunction
function [value,n_input,n_valid]=reduce_one(name,values,opts)
  n_input=numel(values);n_valid=n_input;
  if(any(strcmp(name,{'any','all','count_true'})))
    mask=array_valid_mask(values,size(values));
    switch(name)
      case 'any',value=any(mask);
      case 'all',value=all(mask);
      case 'count_true',value=sum(mask);
    endswitch
    return;
  endif
  good=isfinite(values);n_valid=sum(good);
  if(strcmp(name,'count')),value=n_input;return;endif
  if(strcmp(name,'valid_count')),value=n_valid;return;endif
  policy=nonfinite_policy(opts);
  if(any(!good)&&strcmp(policy,'error')),error('GXTXT:Numeric','reduction values contain NaN or Inf; set nonfinite=omit explicitly');endif
  original_indices=find(good);values=values(good);
  if(isempty(values))
    if(strcmp(name,'sum')),value=0;return;endif
    if(strcmp(name,'product')),value=1;return;endif
    error('GXTXT:Numeric','array reduction requires at least one valid value');
  endif
  n=numel(values);mu=mean(values);
  switch(name)
    case 'sum',value=sum(values);
    case 'product',value=prod(values);
    case 'minimum',value=min(values);
    case 'maximum',value=max(values);
    case 'argmin',[~,k]=min(values);value=original_indices(k);
    case 'argmax',[~,k]=max(values);value=original_indices(k);
    case 'mean',value=mu;
    case 'median',value=quantile_type7(values,0.5);
    case 'variance_population',value=mean((values-mu).^2);
    case 'variance_sample',if(n>1),value=sum((values-mu).^2)/(n-1);else value=NaN;endif
    case 'std_population',value=sqrt(mean((values-mu).^2));
    case 'std_sample',if(n>1),value=sqrt(sum((values-mu).^2)/(n-1));else value=NaN;endif
    case 'rms',value=sqrt(mean(values.^2));
    case 'quantile',value=quantile_type7(values,opt_num(opts,'probability',0.5));
  endswitch
endfunction

function out=op_power_level(power,opts)
  if(!(isnumeric(power)||islogical(power))||!isreal(power)||isempty(power)||any(!isfinite(power(:)))||any(power(:)<0))
    error('GXTXT:Numeric','Power values must be nonempty finite nonnegative real values');
  endif
  reference=opt(opts,'reference_rms',1);
  if(!isnumeric(reference)||!isreal(reference)||!isscalar(reference)||!isfinite(reference)||reference<=0),error('GXTXT:Numeric','RMS reference must be positive and finite');endif
  power=double(power);amplitude=sqrt(power);level=NaN(size(power));positive=power>0;
  % Difference of logs avoids intermediate overflow/underflow of a ratio.
  level(positive)=10*log10(power(positive))-20*log10(reference);
  out=struct('power',power,'root_power',amplitude,'level_db',level,'reference_rms',reference,'zero_policy','undefined_finite_logarithmic_level');
endfunction
