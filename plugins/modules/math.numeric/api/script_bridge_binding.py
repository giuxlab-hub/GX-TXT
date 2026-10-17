"""Octave Script Bridge registration owned by math.numeric / NUMERIC_API_v1."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray
from gxtxt_script_bridge_server import CallbackRef
import importlib.util
from pathlib import Path

_callback_module = None
_callback_query_module = None
_callback_bootstrap_module = None


def _callback_query_backend():
    global _callback_query_module
    if _callback_query_module is None:
        spec = importlib.util.spec_from_file_location("gxtxt_numeric_callback_model_queries", Path(__file__).with_name("callback_model_queries.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _callback_query_module = module
    return _callback_query_module


def _callback_bootstrap_backend():
    global _callback_bootstrap_module
    if _callback_bootstrap_module is None:
        spec = importlib.util.spec_from_file_location("gxtxt_numeric_callback_bootstrap", Path(__file__).with_name("callback_bootstrap.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _callback_bootstrap_module = module
    return _callback_bootstrap_module


def _callback_backend():
    global _callback_module
    if _callback_module is None:
        try:
            spec = importlib.util.spec_from_file_location("gxtxt_numeric_callback_foundation", Path(__file__).with_name("callback_foundation.py"))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            _callback_module = module
        except ImportError as exc:
            raise BridgeError("GXTXT:Numeric:BackendUnavailable", f"callback solver requires NumPy and SciPy: {exc}") from exc
    return _callback_module

REGISTRATION = {
    "api_id": "NUMERIC_API_v1", "api_version": 1,
    "provider_kind": "module", "provider_id": "math.numeric",
    "documentation_ref": "plugins/modules/math.numeric/NUMERIC_API_v1.md",
    "operations": {
        "expression_evaluate": {"name":"expression_evaluate","summary":"Bounded typed pointwise expressions using shared CORE grammar and physical units","argument_convention":"expression text, symbol scalar/vector map, symbol unit map, optional output_unit options","result_convention":"finite real values, output unit and shared dimensional receipt; no code evaluation"},
        "expression_analyze": {"name":"expression_analyze","summary":"Bounded roots/intersections/local extrema of declared expressions","argument_convention":"request with expression, variable, finite interval, scalar symbols, symbol_units and mode; optional tolerances/evaluation budget","result_convention":"classified candidates, residuals, physical units and exact evaluation budget; finite sampling is not a completeness proof"},
        "dataset_expression": {"name":"dataset_expression","summary":"Canonical Dataset mathematical expression over an explicit bounded row window","argument_convention":"expression, symbol Dataset/Variable bindings, scalar parameter metadata and required start/count options","result_convention":"typed values and actual physical units with absolute source-row/Variable provenance"},
        "residual_sequence": {"name":"residual_sequence","summary":"Ordered residual runs, lag correlations and Durbin-Watson diagnostic facts","argument_convention":"residual vector, exact ordering keys (empty for input positions), explicit ordering options","result_convention":"bounded sequence facts and input/order fingerprints; CORE owns interpretation and no p values are computed"},
        "smooth": {"name":"smooth","summary":"Smooth finite ordered XY through the shared Numeric algorithms","argument_convention":"X, Y, optional smoothing options","result_convention":"Smoothed values, residuals, settings and exact retained/omitted positions; no parameter inference"},
        "dataset_smooth": {"name":"dataset_smooth","summary":"Smooth canonical Dataset variables with captured original row identities","argument_convention":"Dataset ID, X/Y variable IDs, optional smoothing options","result_convention":"Smoothed XY, physical units, settings and exact original Dataset row ordinals"},
        "log_ratio": {"name":"log_ratio","summary":"Natural logarithm of an explicit dimensionless positive response ratio","argument_convention":"values, positive reference in the same units","result_convention":"unchanged-shape log values and reference receipt"},
        "log_response_retransform": {"name":"log_response_retransform","summary":"Physical median, optional lognormal plug-in mean and captured log-interval transformation","argument_convention":"log predictions, explicit reference and optional variance/interval facts","result_convention":"physical arrays, bounded method and eligibility facts; CORE owns interpretation"},
        "baseline": {"name":"baseline","summary":"Estimate a separate baseline and corrected spectrum","argument_convention":"X, Y, optional options; or X, Y, anchor X, anchor Y, options","result_convention":"Original response, baseline, corrected response and exact selected positions with estimator receipt"},
        "dataset_baseline": {"name":"dataset_baseline","summary":"Estimate a baseline from stable Dataset variables","argument_convention":"Dataset ID, X/Y variable IDs and optional options","result_convention":"Separate spectral columns, original Dataset row identities and estimator receipt"},
        "fit_region_catalog": {"name":"fit_region_catalog","summary":"Discover independent regional increment cards","argument_convention":"no operands","result_convention":"versioned regional descriptor cards"},
        "fit_region_compose": {"name":"fit_region_compose","summary":"Compose one joint C0/C1 regional model","argument_convention":"physical region recipe with explicit breakpoint search bounds","result_convention":"frozen declared expression and joint constraints"},
        "fit_region_selection": {"name":"fit_region_selection","summary":"Select actual observations and identify regional membership","argument_convention":"frozen regional model and physical predictor vector","result_convention":"binary positional mask and region indices with bounded counts"},
        "fit_observation_signature": {"name":"fit_observation_signature","summary":"Fingerprint exact ordered fitted responses and weights","argument_convention":"observed vector, optional positive weights, additive response offset (empty to skip), retained predictors","result_convention":"bounded SHA and Gaussian normalization receipt"},
        "nested_f_test": {"name":"nested_f_test","summary":"Compute nested polynomial F test from captured SSE","argument_convention":"public CORE nested-F plan","result_convention":"F, degrees of freedom and upper-tail probability without refitting"},
        "fit_information_criteria": {"name":"fit_information_criteria","summary":"Compute comparable Gaussian likelihood criteria from captured facts","argument_convention":"public CORE model-selection plan","result_convention":"log likelihood, AIC, conditional AICc and BIC without refitting"},
        "fit_model_catalog": {"name":"fit_model_catalog","summary":"Discover reusable scalar model cards","argument_convention":"no operands","result_convention":"independent versioned descriptor cards"},
        "model_export": {"name":"model_export","summary":"Export standalone Python/Octave functions and LaTeX from saved model state","argument_convention":"model, export options including name and domain","result_convention":"python, octave, latex and metadata_json text"},
        "positive_translation": {"name":"positive_translation","summary":"Resolve the canonical reversible additive coordinate translation","argument_convention":"finite numeric values, optional mode and delta","result_convention":"mapped values, exact additive constants, bounds and algorithm identity"},
        "uniform_grid": {"name":"uniform_grid","summary":"Create a public Numeric uniform query grid","argument_convention":"minimum, maximum, count or step, optional mode","result_convention":"grid and actual spacing metadata"},
        "expression_dimensions": {"name":"expression_dimensions","summary":"Public CORE dimensional validation and parameter-unit inference","argument_convention":"expression, symbol_units, optional output_unit and unknown_parameter_ids","result_convention":"versioned CORE dimensions and symbol-scale receipt without evaluating scientific data"},
        "generalized_least_squares": {"name":"generalized_least_squares","summary":"Linear-design GLS with full observation covariance and explicit singular constraints","argument_convention":"design, response, covariance, optional policy","result_convention":"Coefficients, full covariance, exact source identity and whitened residual facts"},
        "polynomial_gls": {"name":"polynomial_gls","summary":"Centered polynomial GLS with full observation covariance","argument_convention":"x, y, degree, covariance, optional policy","result_convention":"Physical and scaled coefficients/covariance with retained GLS meaning"},
        "fit_characteristics": {"name":"fit_characteristics","summary":"Deterministic finite source shape hints without fitting","argument_convention":"predictors, response, optional declared thresholds","result_convention":"bounded shape facts and exact source signature; CORE owns advisory model meaning"},
        "fit_initial_guess": {"name":"fit_initial_guess","summary":"Bounded model-aware starting values without nonlinear optimization","argument_convention":"model kind, finite predictors, response, optional bounds/fixed/current values","result_convention":"proposed or explicitly unavailable starting values; no accepted fit or uncertainty"},
        "rational_residuals": {"name":"rational_residuals","summary":"Descriptive rational residuals at exact coordinates without fitting","argument_convention":"retained rational model, finite x and y, optional explicit extrapolation","result_convention":"shared residual metrics, physical residuals and domain receipt; no training inference"},
        "rational_model_compose": {"name": "rational_model_compose", "summary": "Declare a normalized physical polynomial quotient", "argument_convention": "physical coefficients, units and bounded domain", "result_convention": "validated rational declaration through shared dimensional compilation"},
        "rational_domain": {"name": "rational_domain", "summary": "Inspect denominator separation over a whole physical interval", "argument_convention": "compiled rational model or physical recipe and finite increasing domain", "result_convention": "bounded interval receipt and diagnostic poles; no fitting"},
        "rational_fit": {"name": "rational_fit", "summary": "Fit a guarded rational response through shared Ceres", "argument_convention": "model, predictor, response, optional noise and solver settings", "result_convention": "captured fit covariance, exact observations and qualified rational summary"},
        "rational_evaluate": {"name": "rational_evaluate", "summary": "Evaluate a retained rational model at exact coordinates", "argument_convention": "model, coordinates, optional explicit extrapolation and derivatives", "result_convention": "predictions, domain flags and whole-interval denominator guard"},
        "rational_model_state": {"name": "rational_model_state", "summary": "Capture a versioned rational model state", "argument_convention": "validated retained rational model", "result_convention": "inert physical recipe, parameters, domains and identities"},
        "rational_model_restore": {"name": "rational_model_restore", "summary": "Restore a versioned rational model without fitting", "argument_convention": "captured rational state", "result_convention": "validated model with exact physical parameters and identities"},
        "surface_model_state": {"name":"surface_model_state","summary":"Capture a versioned retained physical surface state","argument_convention":"validated fitted surface model","result_convention":"inert complete recipe parameters qualified domain and identities"},
        "surface_model_restore": {"name":"surface_model_restore","summary":"Restore a captured physical surface without fitting","argument_convention":"versioned retained surface state","result_convention":"validated physical model with exact parameters and identities"},
        "surface_model_compose": {"name":"surface_model_compose","summary":"Declare a physical z=f(x,y) model","argument_convention":"two-predictor formula recipe with physical units and parameters","result_convention":"versioned surface declaration through the shared dimensional compiler"},
        "surface_residuals": {"name":"surface_residuals","summary":"Evaluate physical surface residuals without fitting","argument_convention":"model, x, y, z, explicit layout and omission/extrapolation settings","result_convention":"descriptive physical residuals, original indices and captured interpretation summary"},
        "surface_fit": {"name":"surface_fit","summary":"Fit exact point or grid observations to a physical surface","argument_convention":"model, x, y, z, explicit layout and solver options","result_convention":"shared solver result, original linear indices, declared parameter covariance and surface input receipt"},
        "surface_evaluate": {"name":"surface_evaluate","summary":"Evaluate a captured physical surface at exact XY pairs","argument_convention":"model, Nx2 physical coordinates, optional domain/extrapolation/Jacobian options","result_convention":"retained predictions and explicit domain flags without interpolation or fitting"},
        "surface_grid": {"name":"surface_grid","summary":"Sample a retained surface on explicit XY axes","argument_convention":"model, x axis, y axis, optional domain/extrapolation/Jacobian options","result_convention":"Y-by-X model samples with units and bounds flags; no data interpolation"},
        "complex_model_compose": {"name":"complex_model_compose","summary":"Declare physical complex channels with shared parameters","argument_convention":"data-only frequency, real/imaginary channel formulas and physical parameters","result_convention":"versioned complex declaration using the shared dimensional compiler"},
        "complex_fit": {"name":"complex_fit","summary":"Joint complex Cartesian fit using absolute response covariance","argument_convention":"model, frequencies, complex observations, covariance contract, optional solver options","result_convention":"shared parameters/covariance and captured Cartesian metric; phase diagnostics are separate"},
        "complex_evaluate": {"name":"complex_evaluate","summary":"Evaluate retained complex physical responses","argument_convention":"model, frequencies, optional derivative or Jacobian request","result_convention":"complex channels, magnitude, principal phase and real component derivatives without fitting"},
        "complex_residuals": {"name":"complex_residuals","summary":"Evaluate retained complex Cartesian residuals","argument_convention":"model, frequencies, observations, absolute Cartesian covariance","result_convention":"physical residuals and bounded whitened diagnostics without fitting or parameter inference"},
        "complex_from_polar": {"name":"complex_from_polar","summary":"Convert declared amplitude and phase to physical complex observations","argument_convention":"magnitude, phase, explicit units/scale/reference options","result_convention":"complex values and conversion provenance; no covariance approximation"},
        "implicit_model_compose": {'name': 'implicit_model_compose', 'summary': 'Declare a physical implicit equation', 'argument_convention': 'data-only two-coordinate formula, residual mode and explicit reference normalization', 'result_convention': 'versioned implicit model with CORE units and bounds'},
        "implicit_fit": {'name': 'implicit_fit', 'summary': 'Fit algebraic implicit equation residuals with existing Ceres', 'argument_convention': 'implicit model, first and second coordinates, optional solver policy', 'result_convention': 'physical parameters/covariance and explicit equation residual facts; no ODR distance or inferred response curve'},
        "implicit_evaluate": {'name': 'implicit_evaluate', 'summary': 'Evaluate retained implicit equation values and parameter Jacobian', 'argument_convention': 'implicit model, first and second coordinates, optional Jacobian request', 'result_convention': 'equation values, residuals and declared physical normalization without fitting'},
        "implicit_query": {'name': 'implicit_query', 'summary': 'Solve an explicitly declared continuous response branch', 'argument_convention': 'implicit model, independent queries and branch declaration', 'result_convention': 'checked local roots, partial-derivative ratio and explicit unavailable/uniqueness status'},
        "fit_formula_compose": {"name":"fit_formula_compose","summary":"Declare a safe formula with CORE dimensional inference and explicit unit normalization","argument_convention":"data-only formula, predictor units and named parameter recipe","result_convention":"frozen expression model for the existing Numeric solver with physical parameter units and constraints"},
        "fit_model_compose": {"name":"fit_model_compose","summary":"Compose frozen model components and shared parameters","argument_convention":"recipe with components, x_unit, y_unit and optional parameter overrides","result_convention":"declared expression model and captured constraints"},
        "signal_snr": {"name":"signal_snr","summary":"Supplied signal/noise energy ratio","argument_convention":"two vectors and optional empty options","result_convention":"SNR and explicit energy/zero facts"},
        "signal_spectrum_quality": {"name":"signal_spectrum_quality","summary":"Coherent raw FFT-bin quality","argument_convention":"real vector, sample rate and fundamental_hz options","result_convention":"Raw FFT-bin powers, ratios and harmonic order identities"},
        "fft_spectrum_quality": {"name":"fft_spectrum_quality","summary":"Coherent-gain-corrected FFT lobe quality","argument_convention":"real samples, sample step, optional estimator options","result_convention":"Amplitude spectrum, bounded quality facts and component columns"},
        "harmonic_peak_quality": {"name":"harmonic_peak_quality","summary":"Local peaks in an existing amplitude spectrum","argument_convention":"frequency, amplitude, optional detection options","result_convention":"Detected component columns and bounded THD facts"},
        "harmonic_components": {"name":"harmonic_components","summary":"Identified component amplitudes and relative levels","argument_convention":"orders, expected frequencies, detected frequencies, amplitudes, required fundamental_amplitude options","result_convention":"Component columns with explicit level floor and reference"},
        "signal_periodogram": {"name":"signal_periodogram","summary":"Explicit periodogram spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "signal_welch": {"name":"signal_welch","summary":"Explicit welch spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "signal_asd": {"name":"signal_asd","summary":"Explicit asd spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "signal_cross_psd": {"name":"signal_cross_psd","summary":"Explicit cross_psd spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "signal_coherence": {"name":"signal_coherence","summary":"Explicit coherence spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "signal_frf_h1": {"name":"signal_frf_h1","summary":"Explicit frf_h1 spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "signal_frf_h2": {"name":"signal_frf_h2","summary":"Explicit frf_h2 spectral estimates","argument_convention":"signals, sample_rate, optional window/overlap/nfft","result_convention":"binary spectral vectors and common estimator facts"},
        "window_metrics": {"name":"window_metrics","summary":"Discrete deterministic window metrics","argument_convention":"window, sample_rate and optional empty options","result_convention":"bounded gains and equivalent noise bandwidth"},
        "signal_correlation": {"name":"signal_correlation","summary":"Uncentered sequence correlation","argument_convention":"first, second and optional normalization/sample_rate","result_convention":"binary lag vectors and bounded peak facts"},
        "event_period": {"name":"event_period","summary":"Descriptive reference crossing periods","argument_convention":"crossing vector and optional empty options","result_convention":"bounded period and frequency facts"},
        "pulse_timing": {"name":"pulse_timing","summary":"Descriptive complete pulse timing","argument_convention":"rising and falling vectors and optional empty options","result_convention":"bounded period width duty and sample spread facts"},
        "signal_summary": {"name":"signal_summary","summary":"Descriptive real/complex signal summary","argument_convention":"numeric vector and optional empty options","result_convention":"Bounded magnitude RMS, peak, crest and split complex DC facts"},
        "replicate_summary": {"name":"replicate_summary","summary":"Aligned replicate and source profile","argument_convention":"values matrix, source IDs, optional mode/sampling/local_dispersion options","result_convention":"Per-coordinate statistics, envelopes and eligibility facts"},
        "local_cloud_fit": {"name":"local_cloud_fit","summary":"Local unlabelled cloud estimator","argument_convention":"x, y, in-domain query, optional empty options","result_convention":"Per-query estimate, dispersion and effective denominator facts"},
        "welch_aggregate": {"name":"welch_aggregate","summary":"Aggregate normalized one-sided periodogram sums","argument_convention":"sum_psd, sum_amplitude, required window_count/frequency_step_hz/enbw_sum_hz options","result_convention":"Spectral vectors and bounded descriptive facts"},
        "power_level": {"name":"power_level","summary":"RMS and level of nonnegative powers","argument_convention":"power, optional reference_rms options","result_convention":"Power, RMS, finite level or undefined zero marker"},
        "spectral_features": {"name":"spectral_features","summary":"Descriptive spectral distribution","argument_convention":"frequency, values, optional options","result_convention":"Captured scalar descriptors and distribution vectors"},
        "statistics": {"name": "statistics", "summary": "Public descriptive statistics and conditional sampling SEM", "argument_convention": "values, optional options", "result_convention": "Raw Numeric summary for CORE interpretation"},
        "weighted_statistics": {"name": "weighted_statistics", "summary": "Weighted summary with explicit relative or inverse-variance semantics", "argument_convention": "values, weights, optional options", "result_convention": "Raw Numeric summary for CORE interpretation"},
        "quantiles": {"name": "quantiles", "summary": "Type-7 sample quantiles", "argument_convention": "values, probabilities, optional options", "result_convention": "Values with exact probability order and estimator definition"},
        "weighted_quantiles": {"name": "weighted_quantiles", "summary": "Weighted empirical-CDF quantiles", "argument_convention": "values, weights, probabilities, optional options", "result_convention": "Values with exact probability order and estimator definition"},
        "resampling_summary": {"name": "resampling_summary", "summary": "Summarize existing bootstrap or permutation replicates", "argument_convention": "distribution, observed statistic, optional options", "result_convention": "Numeric interval or corrected probability facts for CORE interpretation"},
        "one_way_anova": {"name": "one_way_anova", "summary": "Public ordinary or Welch one-way ANOVA", "argument_convention": "values, group labels, optional options", "result_convention": "Numeric grouped and test results for CORE interpretation"},
        "hypothesis_test": {"name": "hypothesis_test", "summary": "Public t and rank tests with explicit method and alternative", "argument_convention": "method, first values, second values, optional options", "result_convention": "Raw Numeric test result for CORE interpretation"},
        "mad": {"name": "mad", "summary": "Median absolute deviation with explicit scaling", "argument_convention": "values, optional options", "result_convention": "Median and raw/scaled MAD facts for CORE interpretation"},
        "matrix_svd": {"name": "matrix_svd", "summary": "Public economy SVD with rank and condition diagnostics", "argument_convention": "matrix, optional options", "result_convention": "Numeric U, singular values, V and dimensions"},
        "reduce_summary": {"name":"reduce_summary","summary":"Scalar or per-axis summary","argument_convention":"values and optional dimension","result_convention":"count sum mean minimum maximum and actual shape"},
        "reduce_accumulate": {"name":"reduce_accumulate","summary":"Accumulate a scalar summary state","argument_convention":"state and values","result_convention":"combined count sum mean minimum maximum"},
        "matrix_statistics": {"name": "matrix_statistics", "summary": "Public per-axis matrix descriptive statistics", "argument_convention": "matrix, optional dimension option", "result_convention": "Numeric count and indexed moment vectors"},
        "pca_summary": {"name": "pca_summary", "summary": "PCA moments and ratios from existing SVD magnitudes", "argument_convention": "singular values, observation count, optional centered flag", "result_convention": "Ordered component fact columns for CORE interpretation"},
        "propagate_uncertainty": {"name": "propagate_uncertainty", "summary": "First-order measurement uncertainty propagation with independent or correlated inputs", "argument_convention": "Jacobian, standard uncertainties or covariance, optional options", "result_convention": "Numeric output covariance, standard uncertainties and propagation provenance for CORE interpretation"},
        "digitization_uncertainty": {"name":"digitization_uncertainty","summary":"Declared pixel and shared calibration uncertainty propagation","argument_convention":"physical linearization, explicit distribution and calibration standard uncertainties","result_convention":"physical sigma arrays, covariance blocks and retained shared factors"},
        "digitization_covariance": {"name":"digitization_covariance","summary":"Original-order full calibrated coordinate covariance","argument_convention":"retained uncertainty state, x|y|xy","result_convention":"bounded full covariance preserving cross-point dependencies"},
        "derived_properties": {"name":"derived_properties","summary":"Physical parameter expressions with full correlated covariance","argument_convention":"public CORE derived-properties plan","result_convention":"values, analytic derivative availability and propagated covariance; no refit"},
        "parameter_uncertainty": {"name": "parameter_uncertainty", "summary": "Calculate free-parameter correlation and marginal confidence intervals from a public CORE inference plan", "argument_convention": "CORE parameter inference plan", "result_convention": "Numeric uncertainty receipt for CORE interpretation"},
        'fit_bootstrap_prepare': {"name":'fit_bootstrap_prepare',"summary":'Prepare exact data and captured estimator for either bootstrap driver',"argument_convention":'model, X, y, CORE plan, options',"result_convention":"data-only bootstrap state, draw or captured numerical receipt"},
        'fit_bootstrap_draw': {"name":'fit_bootstrap_draw',"summary":'Generate one aligned bootstrap dataset through the shared sampling owner',"argument_convention":'prepared state, seed',"result_convention":"data-only bootstrap state, draw or captured numerical receipt"},
        'fit_bootstrap_summarize': {"name":'fit_bootstrap_summarize',"summary":'Summarize the bounded refit ledger through shared covariance and quantile owners',"argument_convention":'prepared state, samples, statuses, seeds, execution',"result_convention":"data-only bootstrap state, draw or captured numerical receipt"},
        "fit_profile": {"name":"fit_profile","summary":"Constrained Gaussian likelihood profile with retained endpoint and failure evidence","argument_convention":"fitted declared model, exact predictors/response, CORE plan, original weights","result_convention":"typed trial ledger and bounded profile receipt"},
        "fit_bootstrap": {"name":"fit_bootstrap","summary":"Bounded parameter-refit bootstrap through the existing solvers","argument_convention":"fitted model, original predictors/response, public CORE plan, optional original weights","result_convention":"Typed parameter draws/status/seeds and bounded actual refit receipt"},
        "prediction_uncertainty": {"name": "prediction_uncertainty", "summary": "Propagate captured covariance through the native model for pointwise response intervals", "argument_convention": "model, predictors, CORE prediction plan, optional future observation noise", "result_convention": "Binary per-query predictions, interval bounds and availability with bounded inference receipt"},
        "least_squares": {"name": "least_squares", "summary": "Public linear-design least squares with optional exact influence diagnostics", "argument_convention": "design, response, optional weights and options", "result_convention": "Numeric fit with optional influence receipt and typed original input rows"},
        "linear_regression": {"name": "linear_regression", "summary": "Public weighted or unweighted linear least squares", "argument_convention": "X, Y, optional weights and options", "result_convention": "Numeric fit in intercept/slope parameter order"},
        "polynomial_fit": {"name": "polynomial_fit", "summary": "Public centered/scaled polynomial least squares", "argument_convention": "X, Y, degree, optional weights and options", "result_convention": "Numeric fit in descending-power order"},
        "residual_metrics": {"name": "residual_metrics", "summary": "Public observed/predicted descriptive residual calculations", "argument_convention": "observed, predicted, optional options", "result_convention": "Raw Numeric metrics for CORE interpretation"},
        "polar_coordinates": {"name": "polar_coordinates", "summary": "Convert physical XY with an explicit polar frame and angular branch", "argument_convention": "X, Y, optional frame options", "result_convention": "theta, radius, undefined-angle mask and frame"},
        "cartesian_coordinates": {"name": "cartesian_coordinates", "summary": "Convert declared angles and nonnegative radii to physical XY", "argument_convention": "theta, radius, optional frame options", "result_convention": "physical X/Y and frame"},
        "nonlinear_evaluate": {"name":"nonlinear_evaluate","summary":"Evaluate a saved declared model without fitting or residual buffers","argument_convention":"model with parameters, predictors, optional jacobian flag","result_convention":"predictions, model identity and optional physical Jacobian"},
        "curve_model_fit": {"name": "curve_model_fit", "summary": "Fit reconstructible curves including Akima interpolation and explicit-knot B-spline approximation", "argument_convention": "model, X, Y, optional options", "result_convention": "model state struct"},
        "model_state_decode": {"name":"model_state_decode","summary":"Decode saved Numeric model JSON with exact binary64 numbers","argument_convention":"JSON text or typed uint8 byte vector","result_convention":"model state preserving exact numbers and JSON structure; bounded native decoder"},
        "fit_input_policy": {"name":"fit_input_policy","summary":"Describe captured model ordering, duplicate and endpoint decisions","argument_convention":"model name, captured model state","result_convention":"versioned preprocessing policy; no fitting or statistics"},
        "model_geometry": {"name":"model_geometry","summary":"Exact Native2D definition for retained polynomial spans and arcs","argument_convention":"model, explicit physical domain/options","result_convention":"exact definition or explicit sampled-required reason; no fitting"},
        "model_query": {"name":"model_query","summary":"Retained scalar or XY model queries with declared derivative method and extrapolation flags","argument_convention":"model, query vector, explicit domain/options","result_convention":"points, derivative and inverse-slope validity; no fit or uncertainty"},
        "model_inverse": {"name":"model_inverse","summary":"Explicit local bracket inversion of a retained scalar model","argument_convention":"model, response targets, bracket, explicit domain/tolerances","result_convention":"verified roots or unavailable reasons; global uniqueness is not certified"},
        "curve_model_parameter_state": {"name":"curve_model_parameter_state","summary":"Compact editable direct-model parameter state","argument_convention":"model state, parameter vector or empty for current values","result_convention":"validated state, named parameters and unit roles; no optimization"},
        "curve_model_evaluate": {"name": "curve_model_evaluate", "summary": "Evaluate a persisted curve model", "argument_convention": "model state, query vector", "result_convention": "X/Y points struct"},
        "curve_model_project": {"name": "curve_model_project", "summary": "Project points to the nearest location on an arc or Bezier curve", "argument_convention": "model state, X, Y", "result_convention": "projected points, parameters and distances"},
        "curve_model_residual": {"name": "curve_model_residual", "summary": "Compute signed geometric projection distance and XY dispersion metrics", "argument_convention": "model state, X, Y", "result_convention": "projected points, signed distances and geometric metrics"},
        "array_unary": {"name": "array_unary", "summary": "Apply a public unary numerical operation", "argument_convention": "operation name, operand struct, optional options struct", "result_convention": "numerical result struct"},
        "array_binary": {"name": "array_binary", "summary": "Apply a public binary numerical operation", "argument_convention": "operation name, left operand struct, right operand struct, optional options struct", "result_convention": "numerical result struct"},
        "array_compare": {"name": "array_compare", "summary": "Build a numerical comparison mask", "argument_convention": "operation name, left operand struct, right operand struct, optional options struct", "result_convention": "numerical result struct"},
        "array_mask": {"name": "array_mask", "summary": "Apply a logical mask operation", "argument_convention": "operation name, first operand struct, optional second operand struct", "result_convention": "numerical result struct"},
        "array_select": {"name": "array_select", "summary": "Select values by mask", "argument_convention": "values operand struct, mask operand struct", "result_convention": "numerical result struct"},
        "array_where": {"name": "array_where", "summary": "Select true or false values by mask", "argument_convention": "mask, true values, false values as operand structs", "result_convention": "numerical result struct"},
        "array_reduce": {"name": "array_reduce", "summary": "Reduce a numeric array", "argument_convention": "operation name, operand struct, optional options struct", "result_convention": "numerical result struct"},
        "statistics_dataset": {"name": "statistics_dataset", "summary": "Compute statistics on a stable Dataset variable", "argument_convention": "dataset_id, variable_id, optional options struct", "result_convention": "statistics struct"},
        "dataset_statistics": {"name": "dataset_statistics", "summary": "Compute statistics on a stable Dataset variable in the current Session", "argument_convention": "dataset_id, variable_id, optional options struct", "result_convention": "statistics and canonical Dataset receipt"},
        "dataset_weighted_statistics": {"name": "dataset_weighted_statistics", "summary": "Compute weighted statistics on stable Dataset variables in the current Session", "argument_convention": "dataset_id, variable_id, weight_variable_id, optional options struct", "result_convention": "weighted statistics and canonical Dataset receipt"},
        "dataset_polynomial_fit": {"name": "dataset_polynomial_fit", "summary": "Fit a polynomial to stable Dataset variables in the current Session", "argument_convention": "dataset_id, x_variable_id, y_variable_id, degree, optional options struct", "result_convention": "fit and canonical Dataset receipt"},
        "linear_matrix": {"name": "linear_matrix", "summary": "Inspect, solve, or decompose a real or complex matrix", "argument_convention": "action, matrix struct, optional other matrix struct, optional options struct", "result_convention": "split-complex result struct"},
        "foundation": {"name": "foundation", "summary": "Vector, tensor, grid, geometry, sparse, statistics, calculus, ODE, constrained optimization and special-function primitives", "argument_convention": "family, action, three typed operands or execution-scoped callback handles, optional options struct", "result_convention": "structured mathematical result"},
        "root_find": {"name":"root_find","summary":"Find a scalar root with a registered callback","argument_convention":"callback, bracket or initial value, optional options","result_convention":"root and convergence diagnostics"},
        "minimize_1d": {"name":"minimize_1d","summary":"Minimize a scalar function on a bounded interval","argument_convention":"callback, bounds, optional options","result_convention":"minimum and convergence diagnostics"},
        "minimize": {"name":"minimize","summary":"Minimize a multivariate scalar function","argument_convention":"callback, initial point, optional options","result_convention":"minimum and convergence diagnostics"},
        "nonlinear_fit": {"name":"nonlinear_fit","summary":"Fit a registered callback or declared formula; declared models support explicit XY uncertainties and reproducible multistart","argument_convention":"X, Y, callback or expression model struct, initial parameters, optional options","result_convention":"parameters, residuals and fit diagnostics, with bounded trial receipts when multistart is requested"},
        "dataset_nonlinear_fit": {"name":"dataset_nonlinear_fit","summary":"Fit a callback or declared formula to stable Dataset variables","argument_convention":"Dataset ID, X/Y variable IDs, callback or expression model struct, initial parameters, optional options","result_convention":"fit diagnostics, exact source rows and Dataset provenance"},
    },
}
_ARGUMENTS = {
    "expression_evaluate": [("expression", "controlled expression text"),("symbols", "finite real scalar/vector map"),("symbol_units", "explicit physical unit map"),("options", "optional bounded output unit options")],
    "expression_analyze": [("request", "explicit typed expression/domain/parameter request"),("options", "optional bounded numerical policy")],
    "dataset_expression": [("expression", "controlled expression text"),("bindings", "canonical symbol to Dataset/Variable identities"),("parameters", "scalar value/unit parameter map"),("options", "required bounded start/count options")],
    "residual_sequence": [("residuals","real float32/float64 vector"),("ordering_keys","matching numeric vector or empty"),("options","explicit ordering and optional max_lag/nonfinite policy")],
    "smooth": [("X","strictly increasing distinct predictors"),("Y","observations"),("options","optional smoothing settings")],
    "dataset_smooth": [("dataset_id","Dataset ID"),("x_variable_id","stable X Variable ID"),("y_variable_id","stable Y Variable ID"),("options","optional smoothing and selection settings")],
    "log_ratio": [("values","positive real floating-point values"),("reference","positive same-unit normalization")],
    "log_response_retransform": [("log_predictions","finite real floating-point values"),("options","reference and optional captured log variance/interval facts")],
    "model_export": [("model","frozen evaluation state"),("options","domain, function name and physical context")],
    "baseline": [("X","predictors"),("Y","observations"),("options","optional options or anchor arguments")],
    "dataset_baseline": [("dataset_id","Dataset ID"),("x_variable_id","stable X Variable ID"),("y_variable_id","stable Y Variable ID"),("options","struct")],
    "fit_observation_signature": [("observed", "finite real vector"), ("weights", "optional positive real vector"), ("response_offset", "optional finite additive response translation"), ("predictors", "optional exact retained predictor matrix")],
    "positive_translation": [("values", "finite real values"), ("options", "mode and optional manual delta")],
    "uniform_grid": [("minimum", "finite scalar"), ("maximum", "finite scalar"), ("specification", "count or step"), ("options", "mode")],
    "nested_f_test": [("plan", "public CORE nested-F plan")],
    "fit_information_criteria": [("plan", "public CORE model-selection plan")],
    "fit_region_catalog": [],
    "fit_region_compose": [("recipe", "bounded regional recipe struct")],
    "fit_region_selection": [("model", "frozen regional model"), ("predictors", "physical predictor vector")],
    "fit_model_catalog": [],
    "expression_dimensions": [("expression", "controlled grammar text"),("symbol_units", "explicit unit map"),("output_unit", "optional target unit"),("unknown_parameter_ids", "optional parameter IDs to infer")],
    "generalized_least_squares": [("design","finite floating matrix"),("response","finite floating vector"),("covariance","finite symmetric matrix"),("options","struct")],
    "polynomial_gls": [("x","finite floating vector"),("y","finite floating vector"),("degree","integer0..63"),("covariance","finite symmetric matrix"),("options","struct")],
    "fit_characteristics": [("predictors","finite floating vector"),("response","finite floating vector"),("options","struct")],
    "fit_initial_guess": [("model_kind","model identifier"),("predictors","finite floating vector"),("response","finite floating vector"),("options","struct")],
    "rational_residuals": [("model","retained rational model"),("x","finite physical predictors"),("y","finite observations"),("options","explicit extrapolation policy")],
    "rational_model_compose": [("recipe","physical polynomial quotient declaration")],
    "rational_domain": [("model","compiled rational model or physical recipe"),("domain","finite increasing interval")],
    "rational_fit": [("model","rational declaration"),("x","physical predictor"),("y","physical response"),("options","response noise and bounded solver")],
    "rational_evaluate": [("model","retained rational model"),("x","physical query"),("options","extrapolation and derivatives")],
    "rational_model_state": [("model","retained rational model")],
    "rational_model_restore": [("state","versioned rational state")],
    "surface_model_state": [("model","retained physical surface")],
    "surface_model_restore": [("state","versioned retained physical surface")],
    "surface_model_compose": [("recipe","physical two-predictor formula")],
    "surface_residuals": [("model","retained surface"),("x","physical X"),("y","physical Y"),("z","observed response"),("options","explicit layout and omission/extrapolation policy")],
    "surface_fit": [("model","surface declaration"),("x","physical X values"),("y","physical Y values"),("z","observed response"),("options","explicit layout and solver settings")],
    "surface_evaluate": [("model","surface declaration"),("coordinates","Nx2 physical query pairs"),("options","domain extrapolation and Jacobian request")],
    "surface_grid": [("model","surface declaration"),("x","query X axis"),("y","query Y axis"),("options","domain extrapolation and Jacobian request")],
    "complex_model_compose": [("recipe","physical complex model declaration")],
    "complex_fit": [("model","complex declaration"),("frequency","physical predictor vector"),("observations","complex channel matrix"),("measurement","Cartesian covariance contract"),("options","struct")],
    "complex_evaluate": [("model","complex declaration"),("frequency","physical predictor vector"),("options","struct")],
    "complex_residuals": [("model","retained complex declaration"),("frequency","physical predictor vector"),("observations","complex channel matrix"),("measurement","absolute Cartesian covariance")],
    "complex_from_polar": [("magnitude","physical or db20 amplitude"),("phase","phase matrix"),("options","explicit conversion units")],
    "implicit_model_compose": [("recipe","physical implicit declaration")],
    "implicit_fit": [("model","implicit model"),("x","first coordinate vector"),("y","second coordinate vector"),("options","struct")],
    "implicit_evaluate": [("model","implicit model"),("x","first coordinate vector"),("y","second coordinate vector"),("options","struct")],
    "implicit_query": [("model","implicit model"),("queries","independent values"),("branch","explicit continuous branch")],
    "fit_formula_compose": [("recipe", "bounded formula and units declaration")],
    "fit_model_compose": [("recipe", "bounded component recipe struct")],
    "statistics": [("values", "numeric vector"), ("options", "struct")],
    "weighted_statistics": [("values", "numeric vector"), ("weights", "numeric vector"), ("options", "struct")],
    "quantiles": [("values", "numeric vector"), ("probabilities", "probability vector"), ("options", "struct")],
    "weighted_quantiles": [("values", "numeric vector"), ("weights", "numeric vector"), ("probabilities", "probability vector"), ("options", "struct")],
    "resampling_summary": [("distribution", "numeric vector"), ("observed", "scalar"), ("options", "struct")],
    "one_way_anova": [("values", "numeric vector"), ("groups", "numeric or text labels"), ("options", "struct")],
    "hypothesis_test": [("method", "string"), ("first_values", "numeric vector"), ("second_values", "numeric vector"), ("options", "struct")],
    "mad": [("values", "numeric vector"), ("options", "struct")],
    "matrix_svd": [("matrix", "numeric matrix"), ("options", "struct")],
    "reduce_summary": [("values", "numeric array"), ("options", "struct")],
    "reduce_accumulate": [("state", "summary or empty"), ("values", "numeric vector")],
    "matrix_statistics": [("matrix", "numeric matrix"), ("options", "struct")],
    "signal_snr": [("signal", "numeric vector"), ("noise", "numeric vector"), ("options", "struct")],
    "signal_spectrum_quality": [("signal", "real vector"), ("sample_rate", "positive scalar"), ("options", "struct")],
    "fft_spectrum_quality": [("signal", "real vector"), ("sample_step", "positive scalar"), ("options", "struct")],
    "harmonic_peak_quality": [("frequency", "real vector"), ("amplitude", "real vector"), ("options", "struct")],
    "harmonic_components": [("orders", "integer vector"), ("expected_frequency", "real vector"), ("detected_frequency", "real vector"), ("amplitudes", "real vector"), ("options", "struct")],
    "signal_summary": [("values", "numeric vector"), ("options", "struct")],
    "signal_periodogram": [ ("signal", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "signal_welch": [ ("signal", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "signal_asd": [ ("signal", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "signal_cross_psd": [ ("first", "numeric vector"), ("second", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "signal_coherence": [ ("first", "numeric vector"), ("second", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "signal_frf_h1": [ ("first", "numeric vector"), ("second", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "signal_frf_h2": [ ("first", "numeric vector"), ("second", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct") ],
    "window_metrics": [("window", "numeric vector"), ("sample_rate", "numeric scalar"), ("options", "struct")],
    "signal_correlation": [("first", "numeric vector"), ("second", "numeric vector"), ("options", "struct")],
    "event_period": [("crossings", "numeric vector"), ("options", "struct")],
    "pulse_timing": [("rising", "numeric vector"), ("falling", "numeric vector"), ("options", "struct")],
    "replicate_summary": [("values", "numeric matrix"), ("source_ids", "numeric vector"), ("options", "struct")],
    "local_cloud_fit": [("x", "numeric vector"), ("y", "numeric vector"), ("query", "numeric vector"), ("options", "struct")],
    "welch_aggregate": [("sum_psd", "numeric vector"), ("sum_amplitude", "numeric vector"), ("options", "struct")],
    "power_level": [("power", "numeric values"), ("options", "struct")],
    "spectral_features": [("frequency", "numeric vector"), ("values", "numeric vector"), ("options", "struct")],
    "pca_summary": [("singular_values", "numeric vector"), ("observation_count", "integer"), ("options", "struct")],
    "propagate_uncertainty": [("jacobian", "numeric matrix"), ("uncertainty", "standard uncertainty vector or covariance matrix"), ("options", "struct")],
    "digitization_uncertainty": [("linearization", "captured physical calibration Jacobians"),("specification", "explicit uncertainty model")],
    "digitization_covariance": [("state", "retained uncertainty state"),("axis", "x y or interleaved xy")],
    "derived_properties": [("plan", "CORE derived-properties plan")],
    "parameter_uncertainty": [("plan", "CORE parameter inference plan")],
    "fit_bootstrap_prepare": [("model", "captured model"), ("predictors", "original predictors"), ("response", "original response"), ("plan", "CORE plan"), ("options", "original weights struct")],
    "fit_bootstrap_draw": [("state", "unchanged prepared state"), ("seed", "current bounded generator state")],
    "fit_bootstrap_summarize": [("state", "unchanged prepared state"), ("samples", "parameter draws"), ("status", "trial status vector"), ("seeds", "trial seed vector"), ("execution", "execution accounting")],
    "fit_profile": [("model", "captured declared model"), ("predictors", "original predictors"), ("response", "original scalar response"), ("plan", "public CORE profile plan"), ("options", "original precision weights")],
    "fit_bootstrap": [("model", "captured fitted model"), ("predictors", "original numeric matrix"), ("response", "original retained response"), ("plan", "CORE bootstrap plan"), ("options", "original weights struct")],
    "prediction_uncertainty": [("model", "captured declared model"), ("predictors", "numeric query matrix"), ("plan", "CORE prediction inference plan"), ("options", "struct")],
    "least_squares": [("design", "numeric matrix"), ("response", "numeric vector"), ("weights", "optional numeric vector"), ("options", "struct")],
    "linear_regression": [("X", "numeric vector"), ("Y", "numeric vector"), ("weights", "optional numeric vector"), ("options", "struct")],
    "polynomial_fit": [("X", "numeric vector"), ("Y", "numeric vector"), ("degree", "integer"), ("weights", "optional numeric vector"), ("options", "struct")],
    "residual_metrics": [("observed", "numeric vector"), ("predicted", "numeric vector"), ("options", "struct")],
    "polar_coordinates": [("X", "numeric vector"), ("Y", "numeric vector"), ("options", "struct")],
    "cartesian_coordinates": [("theta", "numeric vector"), ("radius", "numeric vector"), ("options", "struct")],
    "nonlinear_evaluate": [("model", "declared model with parameters"), ("predictors", "numeric matrix"), ("options", "struct")],
    "curve_model_fit": [("model", "model name"), ("X", "numeric vector"), ("Y", "numeric vector"), ("options", "struct")],
    "model_state_decode": [("saved_json", "JSON text or typed uint8 byte vector")],
    "fit_input_policy": [("model", "supported model name"), ("state", "captured model state")],
    "model_geometry": [("model", "model state struct"), ("options", "explicit physical domain/options")],
    "model_query": [("model", "model state struct"), ("query", "numeric vector"), ("options", "struct")],
    "model_inverse": [("model", "model state struct"), ("targets", "numeric vector"), ("bracket", "numeric vector"), ("options", "struct")],
    "curve_model_parameter_state": [("model", "model state struct"), ("parameters", "numeric vector")],
    "curve_model_evaluate": [("model", "model state struct"), ("query", "numeric vector"), ("options", "optional struct")],
    "curve_model_project": [("model", "model state struct"), ("X", "numeric vector"), ("Y", "numeric vector")],
    "curve_model_residual": [("model", "model state struct"), ("X", "numeric vector"), ("Y", "numeric vector")],
    "array_unary": [("operation", "public numerical operation"), ("operand", "typed operand struct"), ("options", "struct")],
    "array_binary": [("operation", "public numerical operation"), ("left", "typed operand struct"), ("right", "typed operand struct"), ("options", "struct")],
    "array_compare": [("operation", "public comparison operation"), ("left", "typed operand struct"), ("right", "typed operand struct"), ("options", "struct")],
    "array_mask": [("operation", "public mask operation"), ("first", "typed operand struct"), ("second", "typed operand struct")],
    "array_select": [("values", "typed operand struct"), ("mask", "typed operand struct")],
    "array_where": [("mask", "typed operand struct"), ("true_values", "typed operand struct"), ("false_values", "typed operand struct")],
    "array_reduce": [("operation", "public reduction operation"), ("operand", "typed operand struct"), ("options", "struct")],
    "statistics_dataset": [("dataset_id", "Dataset ID"), ("variable_id", "stable Variable ID"), ("options", "struct")],
    "dataset_statistics": [("dataset_id", "Dataset ID"), ("variable_id", "stable Variable ID"), ("options", "struct")],
    "dataset_weighted_statistics": [("dataset_id", "Dataset ID"), ("variable_id", "stable Variable ID"), ("weight_variable_id", "stable weight Variable ID"), ("options", "struct")],
    "dataset_polynomial_fit": [("dataset_id", "Dataset ID"), ("x_variable_id", "stable X Variable ID"), ("y_variable_id", "stable Y Variable ID"), ("degree", "integer"), ("options", "struct")],
    "linear_matrix": [("action", "public linear algebra action"), ("matrix", "matrix with real and optional imaginary parts"), ("other", "optional second matrix"), ("options", "struct")],
    "foundation": [("family", "mathematical family"), ("action", "public mathematical action"), ("a", "typed operand"), ("b", "typed operand"), ("c", "typed operand"), ("options", "typed options struct")],
    "root_find": [("callback","registered callback"),("initial","bracket or initial value"),("options","struct")],
    "minimize_1d": [("callback","registered callback"),("bounds","interval"),("options","struct")],
    "minimize": [("callback","registered callback"),("initial","initial point"),("options","struct")],
    "nonlinear_fit": [("X","predictors"),("Y","observations"),("model","registered callback or expression model struct"),("initial","initial parameters"),("options","struct")],
    "dataset_nonlinear_fit": [("dataset_id","Dataset ID"),("x_variable_id","stable X Variable ID"),("y_variable_id","stable Y Variable ID"),("model","registered callback or expression model struct"),("initial","initial parameters"),("options","struct")],
}
for _name, _fields in _ARGUMENTS.items():
    _operation = REGISTRATION["operations"][_name]
    _operation["arguments"] = [{"name": name, "kind": kind, "required": name not in ("options", "second", "weights", "response_offset")}
                               for name, kind in _fields]
    if _name in ("weighted_statistics", "weighted_quantiles"):
        next(field for field in _operation["arguments"] if field["name"] == "weights")["required"] = True
    if _name == "residual_sequence":
        next(field for field in _operation["arguments"] if field["name"] == "options")["required"] = True
    if _name == "dataset_expression":
        next(field for field in _operation["arguments"] if field["name"] == "options")["required"] = True
    if _name == "expression_dimensions":
        for field in _operation["arguments"]:
            if field["name"] in ("output_unit", "unknown_parameter_ids"):
                field["required"] = False
    if _name in ("model_geometry", "model_query", "model_inverse"):
        for field in _operation["arguments"]:
            field["required"] = True
    _operation["result_contract"] = _operation["result_convention"]
    _operation["unit_behavior"] = "Units follow NUMERIC_API_v1 operation contract"

COMMANDS = {
    "array_unary": "arrayUnary", "array_binary": "arrayBinary",
    "array_compare": "arrayCompare", "array_mask": "arrayMask",
    "array_select": "arraySelect", "array_where": "arrayWhere",
    "array_reduce": "arrayReduce", "statistics_dataset": "statisticsDataset", "dataset_statistics": "statisticsDataset",
    "dataset_weighted_statistics": "weightedStatisticsDataset", "dataset_polynomial_fit": "polynomialFitDataset",
    "linear_matrix": "linearMatrix",
    "foundation": "foundation",
}


def _activate(host):
    host.call("::GX::modulePublicApiActivate", "math.numeric", "NUMERIC_API_v1")


def _adapt(host, raw, result_types, prefix=""):
    fields = host.as_dict(raw)
    out = {}
    for key, value in fields.items():
        path = prefix + key
        kind = result_types.get(path)
        if kind == "number":
            out[key] = float(value)
        elif kind == "boolean":
            out[key] = str(value).lower() in ("1", "true", "yes", "on")
        elif kind == "vector":
            out[key] = NumericArray(host.as_list(value))
        elif kind == "matrix":
            rows = [host.as_list(row) for row in host.as_list(value)]
            count = len(rows)
            width = len(rows[0]) if rows else 0
            if any(len(row) != width for row in rows):
                raise BridgeError("GXTXT:ScriptBridge:Transport", "numerical matrix has unequal row lengths")
            out[key] = NumericArray([rows[r][c] for c in range(width) for r in range(count)], [count, width])
        elif kind == "tensor":
            tensor = host.as_dict(value)
            shape = [int(x) for x in host.as_list(tensor["shape"])]
            values = [float(x) for x in host.as_list(tensor["values"])]
            out[key] = NumericArray(values, shape)
        elif kind == "string":
            out[key] = str(value)
        elif kind == "struct":
            out[key] = _adapt(host, value, result_types, path + ".")
        elif kind == "cell":
            items = []
            for i, item in enumerate(host.as_list(value), 1):
                child = f"{path}.item{i}"
                types = {"value" + name[len(child):]: item_kind for name, item_kind in result_types.items()
                         if name == child or name.startswith(child + ".")}
                items.append(_adapt(host, {"value": item}, types)["value"])
            out[key] = items
        else:
            raise BridgeError("GXTXT:ScriptBridge:Transport", f"numerical result field {key} has no supported type")
    return out


def _dataset_options(host, dataset_id, options):
    """Resolve the provider's named Selection once for every Dataset fit backend."""
    if not isinstance(options, dict):
        raise BridgeError("GXTXT:Numeric:InvalidArguments", "Dataset options must be a struct")
    if "selection_id" not in options:
        return options
    if "selection" in options:
        raise BridgeError("GXTXT:Numeric:InvalidSelection", "Choose either selection_id or selection")
    identifier = options["selection_id"]
    if not isinstance(identifier, str):
        raise BridgeError("GXTXT:Numeric:InvalidSelection", "Selection ID must be text")
    raw = host.as_dict(host.call("::GX::NumericAPIv1::_selectionForDataset", host.session, dataset_id, identifier))
    selection = {key: str(value) for key, value in raw.items()}
    for key in ("enabled", "x_min", "x_max", "y_min", "y_max", "x_binding_count"):
        if key in selection:
            selection[key] = float(selection[key] or "0") if key == "x_binding_count" else float(selection[key])
    if not selection:
        selection = {"enabled": False}
    return {**{key: value for key, value in options.items() if key != "selection_id"}, "selection": selection}


def invoke(host, operation, args):
    if operation == "dataset_expression":
        if len(args) != 4 or not isinstance(args[0], str) or not all(isinstance(value, dict) for value in args[1:]):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Dataset expressions require text, canonical bindings, scalar parameters and explicit bounded options")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, host.session, *[_numeric_argument(value) for value in args]])
    if operation in ("expression_evaluate", "expression_analyze"):
        minimum = 3 if operation == "expression_evaluate" else 1
        if len(args) not in (minimum, minimum + 1) or (len(args) == minimum + 1 and not isinstance(args[-1], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Bounded expressions require their declared typed operands and optional options structure")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation == "expression_dimensions":
        if len(args) not in (2, 3, 4) or not isinstance(args[0], str) or not isinstance(args[1], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "expression_dimensions requires text, unit map and optional target/unknown IDs")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    _activate(host)
    if operation == "residual_sequence":
        if len(args) != 3 or not isinstance(args[2], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Residual sequence requires values, ordering keys and explicit options")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == 'nonlinear_evaluate' and args and isinstance(args[0],dict) and args[0].get('kind') == 'registered_callback':
        if len(args) not in (2,3):
            raise BridgeError('GXTXT:Numeric:InvalidArguments','Callback prediction requires model, predictors and optional options')
        return _callback_backend().evaluate_model(host,args[0],args[1],args[2] if len(args)==3 else {})
    if operation in ('positive_translation','uniform_grid'):
        minimum = 1 if operation == 'positive_translation' else 3
        if len(args) not in (minimum,minimum+1) or (len(args)>minimum and not isinstance(args[-1],dict)):
            raise BridgeError('GXTXT:Numeric:InvalidArguments','Invalid coordinate operation arguments')
        from gxtxt_scientific_binary_v1 import call
        return call(host,'gxtxt_numeric_v1',[operation,*[_numeric_argument(v) for v in args]])
    if operation in ("log_ratio", "log_response_retransform"):
        valid = len(args) == 2 and (operation == "log_ratio" or isinstance(args[1], dict))
        if not valid:
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "Logarithmic operations require values and explicit reference/options")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation in ("smooth", "dataset_smooth"):
        if operation == "smooth":
            valid = len(args) in (2, 3) and (len(args) == 2 or isinstance(args[-1], dict))
            operands = args
        else:
            valid = len(args) in (3, 4) and (len(args) == 3 or isinstance(args[-1], dict))
            operands = [host.session, *args[:3], _dataset_options(host, args[0], args[3] if len(args) == 4 else {})] if valid else []
        if not valid:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid {operation} arguments")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in operands]])
    if operation in ("baseline", "dataset_baseline"):
        if operation == "baseline":
            valid = len(args) in (2, 3, 4, 5) and (len(args) not in (3, 5) or isinstance(args[-1], dict))
            operands = args
        else:
            valid = len(args) in (3, 4) and (len(args) == 3 or isinstance(args[-1], dict))
            operands = [host.session, *args[:3], _dataset_options(host, args[0], args[3] if len(args) == 4 else {})] if valid else []
        if not valid:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid {operation} arguments")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in operands]])
    if operation == "model_export":
        if len(args) != 2 or not isinstance(args[1], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "model_export needs model and export options")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("fit_observation_signature", "fit_information_criteria", "nested_f_test"):
        if operation in ("fit_information_criteria", "nested_f_test"):
            valid = len(args) == 1 and isinstance(args[0], dict)
        else:
            valid = len(args) in (1, 2, 3, 4)
        if not valid:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid {operation} arguments")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation == "dataset_nonlinear_fit" and len(args) in (5, 6):
        args = [*args[:5], _dataset_options(host, args[0], args[5] if len(args) == 6 else {})]
    if operation in ("reduce_summary", "signal_periodogram", "signal_welch", "signal_asd", "signal_cross_psd", "signal_coherence", "signal_frf_h1", "signal_frf_h2", "window_metrics", "signal_correlation", "event_period", "pulse_timing", "fft_spectrum_quality", "harmonic_peak_quality", "harmonic_components", "signal_snr", "signal_spectrum_quality", "signal_summary", "replicate_summary", "local_cloud_fit", "welch_aggregate", "power_level", "spectral_features", "statistics", "weighted_statistics", "quantiles", "weighted_quantiles", "hypothesis_test", "one_way_anova", "resampling_summary", "mad", "propagate_uncertainty", "pca_summary", "matrix_svd", "matrix_statistics", "nonlinear_evaluate"):
        minimum = {"reduce_summary": 1, "signal_periodogram": 2, "signal_welch": 2, "signal_asd": 2, "signal_cross_psd": 3, "signal_coherence": 3, "signal_frf_h1": 3, "signal_frf_h2": 3, "window_metrics": 2, "signal_correlation": 2, "event_period": 1, "pulse_timing": 2, "fft_spectrum_quality": 2, "harmonic_peak_quality": 2, "harmonic_components": 4, "signal_snr": 2, "signal_spectrum_quality": 2, "signal_summary": 1, "replicate_summary": 2, "local_cloud_fit": 3, "welch_aggregate": 2, "power_level": 1, "spectral_features": 2, "statistics": 1, "weighted_statistics": 2, "quantiles": 2, "weighted_quantiles": 3, "hypothesis_test": 3, "one_way_anova": 2, "resampling_summary": 2, "mad": 1, "propagate_uncertainty": 2, "pca_summary": 2, "matrix_svd": 1, "matrix_statistics": 1, "nonlinear_evaluate": 2}[operation]
        if len(args) not in (minimum, minimum + 1) or (len(args) > minimum and not isinstance(args[-1], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid {operation} arguments")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation in ("digitization_uncertainty", "digitization_covariance"):
        if len(args) != 2 or not isinstance(args[0], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Digitization uncertainty requires its captured physical contract and explicit model or axis")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("rational_residuals", "rational_model_compose", "rational_domain", "rational_fit", "rational_evaluate", "rational_model_state", "rational_model_restore"):
        expected = {"rational_residuals": (3,4), "rational_model_compose": (1,), "rational_domain": (2,), "rational_fit": (3,4), "rational_evaluate": (2,3), "rational_model_state": (1,), "rational_model_restore": (1,)}[operation]
        if len(args) not in expected or not isinstance(args[0], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Rational operations require their physical declaration and explicit domain")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("surface_model_compose", "surface_fit", "surface_evaluate", "surface_grid", "surface_residuals", "surface_model_state", "surface_model_restore"):
        expected = {"surface_model_compose": (1,), "surface_model_state": (1,), "surface_model_restore": (1,), "surface_fit": (5,), "surface_residuals": (5,), "surface_evaluate": (2,3), "surface_grid": (3,4)}[operation]
        if len(args) not in expected or not isinstance(args[0], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Surface operations require their physical declaration, exact coordinate arrays and explicit layout/domain")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("complex_model_compose", "complex_fit", "complex_evaluate", "complex_residuals", "complex_from_polar"):
        expected = {"complex_model_compose": (1,), "complex_fit": (4,5), "complex_evaluate": (2,3), "complex_residuals": (4,), "complex_from_polar": (3,)}[operation]
        if len(args) not in expected:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Complex operations require their explicit model, physical arrays and covariance or conversion contract")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("implicit_model_compose", "implicit_fit", "implicit_evaluate", "implicit_query"):
        expected = {"implicit_model_compose": (1,), "implicit_fit": (3,4), "implicit_evaluate": (3,4), "implicit_query": (3,)}[operation]
        if len(args) not in expected or not isinstance(args[0], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Implicit operations require their versioned declaration and exact coordinate/branch operands")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("generalized_least_squares", "polynomial_gls"):
        minimum = 4 if operation == "polynomial_gls" else 3
        if len(args) not in (minimum, minimum+1) or (len(args)>minimum and not isinstance(args[-1],dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "GLS requires its declared predictors, response, covariance and optional policy")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == "fit_characteristics":
        if len(args) not in (2,3) or (len(args)==3 and not isinstance(args[2],dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Characteristics require predictors, response and optional thresholds")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == "fit_initial_guess":
        if len(args) not in (3, 4) or not isinstance(args[0], str):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Initialization requires model kind, predictors, response and optional options")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation in ("fit_formula_compose", "fit_model_catalog", "fit_model_compose", "fit_region_catalog", "fit_region_compose", "fit_region_selection"):
        expected = 0 if operation in ("fit_model_catalog", "fit_region_catalog") else 2 if operation == "fit_region_selection" else 1
        if len(args) != expected or (expected and not isinstance(args[0], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid {operation} arguments")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == "reduce_accumulate":
        if len(args) != 2:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "reduce_accumulate requires state and values")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation in ("derived_properties", "parameter_uncertainty"):
        if len(args) != 1 or not isinstance(args[0], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires one public CORE plan")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, _numeric_argument(args[0])])
    if operation in ("fit_bootstrap_prepare", "fit_bootstrap_draw", "fit_bootstrap_summarize"):
        if len(args) != (2 if operation == 'fit_bootstrap_draw' else 5):
            raise BridgeError('GXTXT:Numeric:InvalidArguments', 'Invalid bootstrap state operation arguments')
        from gxtxt_scientific_binary_v1 import call
        return call(host, 'gxtxt_numeric_v1', [operation, *[_numeric_argument(v) for v in args]])
    if operation == "fit_profile":
        if len(args) not in (4, 5) or not isinstance(args[0], dict) or not isinstance(args[3], dict):
            raise BridgeError("GXTXT:Numeric:InvalidArguments", "fit_profile requires retained declared model, observations and CORE plan")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == "fit_bootstrap":
        if len(args) not in (4, 5) or not isinstance(args[0], dict) or not isinstance(args[3], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "fit_bootstrap requires a captured model, original data and public CORE plan")
        if args[0].get("kind") == "registered_callback":
            return _callback_bootstrap_backend().run(host, _callback_backend(), *args)
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == "prediction_uncertainty":
        if len(args) not in (3, 4) or not isinstance(args[0], dict) or not isinstance(args[2], dict) or len(args) == 4 and not isinstance(args[3], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "prediction_uncertainty requires a captured model, predictors and public CORE plan")
        from gxtxt_scientific_binary_v1 import call
        if args[0].get('kind') == 'registered_callback':
            model, query, plan = args[:3]
            if (plan.get('api_id') != 'STATISTICAL_PREDICTION_INFERENCE_PLAN_v1' or plan.get('status') != 'value'
                    or plan.get('model_source_sha256') != model.get('source_sha256')
                    or plan.get('model_binding_sha256') != model.get('binding_sha256')):
                raise BridgeError('GXTXT:Numeric:PredictionInference', 'Live model identity differs from the eligible CORE prediction plan')
            evaluated = _callback_backend().evaluate_model(host, model, query, {'jacobian':True})
            captured = {'kind':'registered_callback_evaluation', 'schema_version':1,
                'parameters':evaluated['parameters'], 'parameter_ids':evaluated['parameter_ids'],
                'predictor_ids':evaluated['predictor_ids'], 'source_sha256':evaluated['source_sha256'],
                'binding_sha256':evaluated['binding_sha256'], 'evaluation_query':query,
                'predicted':evaluated['predicted'], 'jacobian':evaluated['jacobian'],
                'jacobian_method':evaluated['jacobian_method']}
            args = [captured, query, plan, *args[3:]]
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(value) for value in args]])
    if operation in ("least_squares", "linear_regression", "polynomial_fit", "residual_metrics"):
        command, minimum, maximum = {
            "least_squares": ("leastSquares", 2, 4),
            "linear_regression": ("linearRegression", 2, 4),
            "polynomial_fit": ("polynomialFit", 3, 5),
            "residual_metrics": ("residualMetrics", 2, 3),
        }[operation]
        if not minimum <= len(args) <= maximum:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"Invalid {operation} argument count")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation in ("polar_coordinates", "cartesian_coordinates"):
        if len(args) not in (2, 3) or (len(args) == 3 and not isinstance(args[2], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires two numeric vectors and optional frame options")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation in ("model_geometry", "fit_input_policy", "model_state_decode", "model_query", "model_inverse", "curve_model_parameter_state", "curve_model_fit", "curve_model_evaluate", "curve_model_project", "curve_model_residual"):
        expected = {"model_geometry": (2, 2), "fit_input_policy": (2, 2), "model_state_decode": (1, 1), "model_query": (3, 3), "model_inverse": (4, 4), "curve_model_parameter_state": (2, 2), "curve_model_fit": (3, 4), "curve_model_evaluate": (2, 3), "curve_model_project": (3, 3), "curve_model_residual": (3, 3)}[operation]
        if not expected[0] <= len(args) <= expected[1]:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"invalid {operation} argument count")
        if operation in ("model_query", "model_inverse") and isinstance(args[0], dict) and args[0].get("kind") == "registered_callback":
            owner = _callback_query_backend()
            function = owner.query_model if operation == "model_query" else owner.inverse_model
            return function(host, _callback_backend(), *args)
        operands = args[:3] if operation == "curve_model_fit" else args
        options = args[3] if operation == "curve_model_fit" and len(args) == 4 else {}
        if not isinstance(options, dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "curve model options must be a struct")
        from gxtxt_scientific_binary_v1 import call
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in args]])
    if operation == "nonlinear_fit" and len(args) >= 3 and isinstance(args[2], dict) and ("expression" in args[2] or args[2].get("kind") in ("linear", "exponential", "gaussian", "power_law", "polynomial_fit")):
        if len(args) not in (4, 5) or (len(args) == 5 and not isinstance(args[4], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Declared nonlinear_fit requires X, Y, model, initial and optional options")
        from gxtxt_scientific_binary_v1 import call
        native_args = [args[2], args[0], args[1], args[3], args[4] if len(args) == 5 else {}]
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in native_args]])
    if operation == "dataset_nonlinear_fit" and len(args) >= 4 and isinstance(args[3], dict) and ("expression" in args[3] or args[3].get("kind") in ("linear", "exponential", "gaussian", "power_law", "polynomial_fit")):
        if len(args) not in (5, 6) or (len(args) == 6 and not isinstance(args[5], dict)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Declared Dataset fit requires Dataset ID, X/Y variable IDs, model, initial and optional options")
        from gxtxt_scientific_binary_v1 import call
        native_args = [host.session, *args[:5], args[5] if len(args) == 6 else {}]
        return call(host, "gxtxt_numeric_v1", [operation, *[_numeric_argument(v) for v in native_args]])
    if operation in ("root_find","minimize_1d","minimize","nonlinear_fit","dataset_nonlinear_fit"):
        return _callback_backend().invoke_legacy(host, operation, args)
    if operation in ("statistics_dataset", "dataset_statistics", "dataset_weighted_statistics", "dataset_polynomial_fit"):
        minimum = {"statistics_dataset": 2, "dataset_statistics": 2, "dataset_weighted_statistics": 3, "dataset_polynomial_fit": 4}[operation]
        if len(args) not in (minimum, minimum + 1) or len(args) == minimum + 1 and not isinstance(args[-1], dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires its Dataset bindings and optional options struct")
        args = [host.session, *args]
    elif operation in ("array_unary", "array_reduce") and len(args) not in (2, 3):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires name, operand, optional options")
    elif operation in ("array_binary", "array_compare") and len(args) not in (3, 4):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} requires name, two operands, optional options")
    elif operation == "array_mask" and len(args) not in (2, 3):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array_mask requires name and operand(s)")
    elif operation == "array_select" and len(args) != 2:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array_select requires values and mask")
    elif operation == "array_where" and len(args) != 3:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array_where requires mask and two alternatives")
    elif operation == "linear_matrix" and len(args) not in (2, 3, 4):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "linear_matrix requires action, matrix, optional other and options")
    elif operation == "foundation" and len(args) not in (5, 6):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "foundation requires family, action, three typed operands and optional options")
    callback_action = operation == "foundation" and (args[0] in ("ode", "constrained") or
        (args[0] == "calculus" and args[1] in ("gradient", "jacobian", "hessian", "directional")))
    if operation == "foundation" and len(args) == 5:
        args.append({} if callback_action else {"kind": "struct", "fields": {}})
    if callback_action:
        return _callback_backend().invoke(host, *args)
    if operation == "foundation" and args[0] not in ("equations", "variational"):
        # Same public data-only provider, using the existing CORE bulk channel.
        # Preserve complex matrices and avoid routing observation arrays through
        # the legacy Tcl/INI adapter. Callback admission above remains separate.
        from gxtxt_scientific_binary_v1 import call, native
        host.call("::GX::NumericAPIv1::requireCapability", "mathematical_foundation")
        options = native(args[5])
        if not isinstance(options, dict):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "foundation options require a typed struct")
        projection = options.pop("result_fields", None)
        if projection is not None:
            projection = projection.split(",") if isinstance(projection, str) else projection
            if not isinstance(projection, list) or not all(isinstance(x, str) and x for x in projection):
                raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "result_fields must name result fields")
        return call(host, "gxtxt_numeric_v1", ["foundation", args[0], args[1], *[native(v) for v in args[2:5]], options], projection)
    if operation in ("array_unary", "array_binary", "array_compare", "array_mask", "array_select", "array_where", "array_reduce"):
        try:
            from gxtxt_scientific_binary_v1 import call
            import numpy as np
        except ImportError:
            pass
        else:
            def operand(item):
                if not isinstance(item, dict) or item.get("kind") not in ("scalar", "vector", "matrix") or "value" not in item:
                    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "array operand requires scalar/vector/matrix kind and value")
                value = item["value"]
                if isinstance(value, NumericArray):
                    array = np.asarray(value.values).reshape(value.shape, order="F")
                else:
                    array = np.asarray(value, dtype=float)
                if item["kind"] == "scalar":
                    if array.size != 1: raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "scalar operand requires one value")
                    return float(array.reshape(-1)[0])
                if item["kind"] == "vector": return array.reshape(-1, 1, order="F")
                if array.ndim != 2 or not all(array.shape): raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "matrix requires nonempty two-dimensional values")
                return array
            named = operation not in ("array_select", "array_where")
            count = {"array_unary": 1, "array_binary": 2, "array_compare": 2, "array_reduce": 1,
                     "array_select": 2, "array_where": 3, "array_mask": len(args)-1}[operation]
            start = 1 if named else 0
            native_args = [operation] + ([args[0]] if named else []) + [operand(x) for x in args[start:start+count]]
            if operation in ("array_unary", "array_binary", "array_compare", "array_reduce"):
                options = args[start+count] if len(args)>start+count else {}
                if not isinstance(options, dict): raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "options must be a struct")
                native_args.append(options)
            return call(host, "gxtxt_numeric_v1", native_args)
    raw = host.call("::GX::NumericAPIv1::" + COMMANDS[operation], *args)
    result_types = host.as_dict(host.call("::GX::NumericAPIv1::resultTypes"))
    return _adapt(host, raw, result_types)


def _numeric_argument(value):
    """Preserve existing native vectors and scalar/model option contracts."""
    if isinstance(value, (str, NumericArray, int, float, bool)):
        return value
    if isinstance(value, dict):
        return {key: _numeric_argument(v) for key, v in value.items()}
    if isinstance(value, (list, tuple)) and value and all(isinstance(v, str) for v in value):
        return list(value)
    if isinstance(value, (list, tuple)) and all(isinstance(v, (int, float)) for v in value):
        if any(isinstance(v, int) and abs(v) > 2**53 for v in value):
            raise BridgeError("GXTXT:Numeric:Arguments", "Integer vector values outside the exact binary64 range require an explicit scientific conversion or typed array")
        import numpy as np
        return np.asarray(value, dtype=float).reshape(-1, 1)
    if isinstance(value, (list, tuple)) and value and all(isinstance(v, dict) for v in value):
        return [_numeric_argument(v) for v in value]
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", "Numeric arguments require text, text lists, numeric arrays or scalar structs")
