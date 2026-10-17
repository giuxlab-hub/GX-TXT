#!/usr/bin/env python3
"""Conservative architecture gate: Python AST + targeted multi-language parsing.

This detects inspectable bypasses, not arbitrary obfuscated program equivalence.
Dynamic statistical code is an unresolved gate finding until explicitly audited.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import argparse
import ast
import configparser
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys

API = 'STATISTICAL_RESULT_SEMANTICS_API_v1'
STATS = {'reference_rms', 'reference_mean', 'symmetric_rms', 'symmetric_rmse', 'sampled_hausdorff_distance', 'centered_comparison_score', 'max_relative_error', 'rms_relative_error', 'r_squared', 'r2', 'adjusted_r_squared', 'reduced_chi_squared',
         'chi_squared', 'covariance', 'standard_errors', 'dof', 'edf',
         'rmse', 'residual_rmse', 'residual_standard_deviation', 'fit_quality',
         'covariance_sample', 'covariance_population', 'variance_sample',
         'variance_population', 'standard_deviation', 'correlation',
         'parameter_correlation', 'confidence_interval', 'confidence_intervals', 'ci_lower', 'ci_upper'}
STATS.update({'snr_db', 'thd', 'thd_db', 'thd_plus_n', 'sinad_db', 'sfdr_db', 'enob_bits', 'noise_floor_power_per_bin', 'fundamental_power', 'distortion_power', 'harmonic_powers'})
STATS.update({'parameter_covariance', 'parameter_standard_errors', 'bootstrap_standard_error', 'bootstrap_confidence_interval'})
STATS.update({'leverage', 'cooks_distance', 'deleted_residual', 'loo_prediction', 'studentized_residual', 'maximum_cook_distance'})
STATS.update({'log_bias_correction', 'log_response_mean', 'log_standard_deviation', 'log_response_median'})
STATS.update({'f_statistic', 'nested_f_statistic'})
STATS.update({'durbin_watson', 'runs_expected', 'runs_variance', 'runs_z', 'autocorrelation'})
STATS.update({'aic', 'aicc', 'bic', 'log_likelihood', 'likelihood_parameter_count', 'variance_mle', 'response_rmse'})
STATS.update({'signal_rms', 'signal_peak_magnitude', 'signal_real_peak_to_peak', 'signal_crest_factor', 'signal_dc_real', 'signal_dc_imaginary'})
STATS.update({'event_mean_period', 'event_frequency', 'pulse_mean_width', 'pulse_duty_ratio', 'period_jitter_std', 'jitter_std_seconds'})
STATS.update({'replicate_dispersion', 'replicate_sem', 'replicate_within', 'replicate_between', 'replicate_total', 'replicate_lower_std', 'replicate_upper_std', 'replicate_lower_sem', 'replicate_upper_sem', 'replicate_lower_total', 'replicate_upper_total'})
STATS.update({'local_sigma', 'local_effective_n', 'local_dof', 'y_std', 'y_sem', 'sigma_within', 'sigma_between', 'sigma_total'})
STATS.update({'integrated_power', 'band_rms', 'band_level_db', 'mean_enbw_hz', 'peak_psd', 'welch_integrated_power'})
STATS.update({'spectral_centroid', 'spectral_bandwidth', 'rms_frequency', 'spectral_flatness', 'spectral_crest_factor', 'spectral_entropy', 'occupied_bandwidth_90', 'spectral_weight_sum'})
STATS.update({'sem', 'sampling_se', 'standard_error', 'standard_error_mean',
              'sampling_standard_error_mean', 'measurement_standard_error_mean',
              'measurement_uncertainty', 'standard_uncertainty', 'output_standard_uncertainties', 'output_covariance', 'weighted_mean', 'variance_unbiased',
              'std_unbiased', 'std_sample', 'std_population', 'p_value', 'component_variance', 'explained_ratio', 'cumulative_ratio'})
NATIVE_STATISTICAL_AGGREGATES = {'gx2d_residual_summary': {3: 'mean_absolute', 4: 'rmse'}}
# These calls remain statistical estimators even when assigned to an ordinary
# name such as y or scale. Do not require a canonical result-field spelling.
DIRECT_ESTIMATORS = {'durbin_watson', 'runstest_1samp', 'runstest_2samp', 'acf', 'welch', 'csd', 'coherence', 'pwelch', 'cpsd', 'periodogram', 'mscohere', 'xcorr', 'correlate', 'correlate2d', 'std', 'var', 'cov', 'corr', 'corrcoef', 'stdev', 'pstdev',
                     'variance', 'pvariance', 'nanstd', 'nanvar', 'gsl_stats_variance', 'gsl_stats_sd'}
POLICIES = {'nested_f_allowed', 'model_comparison_policy', 'aic_allowed', 'likelihood_allowed', 'applicability', 'statistics_policy', 'statistical_policy',
            'r2_allowed', 'covariance_allowed', 'statistics_by_model',
            'statistics_applicable', 'uncertainty_applicable'}
PUBLIC = {'profileEligibility', 'profile_eligibility', 'profileSettings', 'profile_settings', 'profilePlan', 'profile_plan', 'profileInterpretation', 'profile_interpretation', 'profileReport', 'profile_report', 'glsInterpretation', 'gls_interpretation', 'glsReport', 'gls_report', 'fitSuggestions', 'fit_suggestions', 'fitSuggestionsReport', 'fit_suggestions_report', 'physicalPlausibility', 'physical_plausibility', 'physicalPlausibilityReport', 'physical_plausibility_report', 'residualSequenceInterpretation', 'residual_sequence_interpretation', 'bootstrapSettings', 'bootstrap_settings', 'bootstrapPlan', 'bootstrap_plan', 'bootstrapInterpretation', 'bootstrap_interpretation', 'influencePlan', 'influence_plan', 'influenceInterpretation', 'influence_interpretation', 'logResponsePlan', 'log_response_plan', 'logResponseInterpretation', 'log_response_interpretation', 'predictionInterpretation', 'prediction_interpretation', 'predictionInferencePlan', 'prediction_inference_plan', 'numericDataFields', 'numeric_data_fields', 'tableCsvRows', 'table_csv_rows', 'numericFieldElements', 'numeric_field_elements', 'numericFields', 'numeric_fields', 'fromNativeComparison', 'from_native_comparison', 'validatedResult', 'validated_result', 'tableRows', 'table_rows', 'solverReport', 'solver_report', 'interpret', 'fromNumeric', 'from_numeric', 'validate', 'report',
          'bindColumns', 'bind_columns', 'bindingTable', 'binding_table',
          'bindResourceColumns', 'bind_resource_columns', 'resourceBindingTable', 'resource_binding_table',
          'resourceBindingFieldElements', 'resource_field_elements', 'fromProviderColumns',
          'fromNumericTable', 'from_numeric_table', 'fromNumericColumns', 'from_numeric_columns',
          'interpretTable', 'interpret_table', 'tableSelect', 'table_select',
          'tableValues', 'table_values', 'tableReport', 'table_report', 'scalarRows', 'scalar_rows',
          'parameterReport', 'parameter_report', 'parameterIniReport', 'parameter_ini_report', 'registerModel', 'parameterRows', 'parameter_rows',
          'parameterCorrelationReport', 'parameter_correlation_report',
          'derivedPropertiesPlan', 'derived_properties_plan', 'derivedPropertiesInterpretation', 'derived_properties_interpretation', 'derivedPropertiesReport', 'derived_properties_report', 'parameterInferencePlan', 'parameter_inference_plan', 'withParameterUncertainty', 'with_parameter_uncertainty', 'iniReport', 'ini_report'}
OWNERS = {
    'core/tcl/statistical_fit_profile_v1.tcl': 'same public CORE authority; Gaussian likelihood policy, endpoint meaning and constrained refit accounting',
    'core/tcl/statistical_digitization_v1.tcl': 'same public CORE authority; pixel distribution, shared calibration and measurement eligibility without numerical recomputation',
    'core/tcl/statistical_knot_spline_v1.tcl': 'same CORE interpretation authority; declared interpolation versus fixed-knot approximation and descriptive inference boundaries',
    'core/tcl/statistical_rational_v1.tcl': 'same CORE interpretation authority; captured rational pole-domain and conditional parameter semantics',
    'core/tcl/statistical_surface_v1.tcl': 'same CORE interpretation authority; captured exact two-predictor surface geometry, missing-cell identity and conditional inference',
    'core/tcl/statistical_complex_v1.tcl': 'same CORE interpretation authority; captured Cartesian complex covariance, physical channels and conditional inference',
    'core/tcl/statistical_implicit_v1.tcl': 'same CORE interpretation authority; captured implicit equation residual normalization, conditioning, units and inference qualification',
    'core/tcl/statistical_gls_v1.tcl': 'same CORE interpretation authority; full observation covariance, exact null constraints and residual-mode semantics',
    'core/tcl/statistical_fit_suggestions_v1.tcl': 'same CORE interpretation authority; advisory model eligibility and exact-population captured comparison reuse',
    'core/tcl/statistical_physical_plausibility_v1.tcl': 'same CORE interpretation authority; explicit captured physical conditions, units and domain/advisory meaning',
    'core/tcl/statistical_derived_properties_v1.tcl': 'same CORE interpretation authority; derived physical quantities, covariance eligibility and validated propagation meaning',
    'core/tcl/statistical_residual_sequence_v1.tcl': 'same CORE interpretation authority; captured explicit-order residual sequence meaning and qualifications',
    'core/tcl/statistical_callback_solver_v1.tcl': 'same CORE interpretation authority; captured callback solver settings and truthful stopping receipts',
    'core/tcl/statistical_nested_f_v1.tcl': 'same CORE interpretation authority; proven polynomial nesting and captured F-test meaning',
    'core/tcl/statistical_fit_bootstrap_v1.tcl': 'same CORE interpretation authority; parameter-refit sampling plans, failure accounting and conditional interval meaning',
    'core/tcl/statistical_influence_v1.tcl': 'same CORE interpretation authority; exact linear-design influence applicability and validated meaning',
    'core/tcl/statistical_log_response_v1.tcl': 'same CORE interpretation authority; explicit logarithmic response and validated inverse-response meaning',
    'core/tcl/statistical_smoother_semantics_v1.tcl': 'same CORE interpretation authority; exact smoother trace meaning and bounded GCV receipt validation',
    'core/tcl/statistical_model_selection_v1.tcl': 'same CORE interpretation authority; comparable likelihood plans and captured model rankings',
    'core/tcl/statistical_result_resource_binding_v1.tcl': 'same CORE interpretation authority; captured facts in canonical Document resources',
    'core/tcl/statistical_location_semantics_v1.tcl': 'same CORE interpretation authority; mean intervals and robust location meaning',
    'core/tcl/statistical_clustering_semantics_v1.tcl': 'same CORE interpretation authority; native clustering and assignment meaning',
    'core/tcl/statistical_foundation_regression_v1.tcl': 'same CORE interpretation authority; captured foundation regression iterates and stopping facts',
    'core/tcl/statistical_prediction_uncertainty_v1.tcl': 'same CORE interpretation authority; pointwise response inference plans',
    'core/tcl/statistical_covariance_diagnostics_v1.tcl': 'same CORE interpretation authority; sample covariance matrices and spectral diagnostics',
    'core/tcl/statistical_survival_semantics_v1.tcl': 'same CORE interpretation authority; Kaplan-Meier risk-set meaning',
    'core/tcl/statistical_foundation_diagnostics_v1.tcl': 'same CORE interpretation authority; covariance-pseudoinverse correlation and multiplicity meaning',
    'core/tcl/statistical_signal_spectral_v1.tcl': 'same CORE interpretation authority; per-frequency density coherence and transfer meaning',
    'core/tcl/statistical_spectral_quality_v1.tcl': 'same CORE interpretation authority; amplitude-spectrum estimator meaning',
    'core/tcl/statistical_signal_semantics_v1.tcl': 'same CORE interpretation authority; descriptive real and complex signal meaning',
    'core/tcl/statistical_replicate_semantics_v1.tcl': 'same CORE interpretation authority; aligned replicate profile eligibility and assumptions',
    'core/tcl/statistical_result_column_binding_v1.tcl': 'same CORE interpretation authority; Dataset-local bounded fact references',
    'core/tcl/statistical_result_semantics_api_v1.tcl': 'interpretation',
    'core/tcl/statistical_solver_semantics_v1.tcl': 'same CORE interpretation authority; bounded numerical solver receipts',
    'core/tcl/statistical_result_table_v1.tcl': 'same CORE interpretation authority; compact parameterless tables',
    'core/script_bindings/statistical_result_semantics.py': 'transport',
    'core/python/gxtxt/__init__.py': 'existing unified public Script Bridge facade',
    'core/octave/util/gxtxt_api_call.m': 'existing unified public Script Bridge facade',
    'core/octave/util/gxtxt_statistics_v1.m': 'thin existing Script Bridge transport facade',
    'core/octave/util/gxtxt_statistics_values_v1.m': 'validated generic numeric table presentation',
}
NUMERIC_ROOT = 'plugins/modules/math.numeric/'
PUBLIC.update({'nestedFPlan', 'nested_f_plan', 'nestedFInterpretation', 'nested_f_interpretation'})
PUBLIC.update({'modelSelectionPlan', 'model_selection_plan', 'modelComparison', 'model_comparison'})
SUMMARY_LABELS = {'mean', 'median', 'variance', 'rms', 'std_sample', 'std_population', 'standard_deviation', 'root_mean_square'}
SUFFIXES = {'.py': 'python', '.tcl': 'tcl', '.m': 'octave', '.cpp': 'cpp', '.cc': 'cpp', '.cxx': 'cpp',
            '.c': 'cpp', '.h': 'cpp', '.hpp': 'cpp', '.inc': 'cpp'}
SKIP_PARTS = {'tests', 'test', 'validation', 'vendor', 'third_party', '__pycache__', '.git'}


@dataclass
class Token:
    kind: str
    value: str
    line: int
    column: int


def lex(source: str, language: str):
    """Language-aware lexical states, retaining locations and string values.

    Octave transpose, percent comments, Tcl command comments, C block comments,
    multiline quoted strings and escaped characters are distinct syntax states.
    This lexer is followed by balanced structural parsing, not line regex scans.
    """
    out = []; i = 0; line = 1; col = 1; command_start = True
    while i < len(source):
        start = i; start_line = line; start_col = col; ch = source[i]
        if ch in ' \t\r':
            i += 1; col += 1; continue
        if ch == '\n':
            out.append(Token('separator', ch, line, col));i += 1;line += 1;col = 1;command_start = True;continue
        comment = (language == 'tcl' and ch == '#' and command_start or
                   language == 'octave' and ch in '%#' or
                   language == 'cpp' and source.startswith('//', i))
        if comment:
            end = source.find('\n', i);i = len(source) if end < 0 else end;col += i-start;continue
        if language == 'cpp' and source.startswith('/*', i):
            end = source.find('*/', i+2)
            if end < 0: raise ValueError(f'{line}:{col}: unterminated block comment')
            text = source[i:end+2];i = end+2;line += text.count('\n');col = len(text.rsplit('\n', 1)[-1])+1 if '\n' in text else col+len(text);continue
        if ch == '\\' and i+1 < len(source) and (language == 'tcl' or language == 'cpp' and source[i+1] == '\n'):
            text = source[i:i+2];out.append(Token('escaped', text, line, col));i += 2
            if text[-1] == '\n':line += 1;col = 1
            else:col += 2
            continue
        transpose = (language == 'octave' and ch == "'" and out and
                     out[-1].kind != 'separator' and
                     (source[i-1].isalnum() or source[i-1] in ')]}._') and
                     source[i-1] not in ' \t')
        quoted = ch == '"' or ch == "'" and language != 'tcl' and not transpose
        if quoted:
            quote = ch;i += 1;value = ''
            while i < len(source):
                if source[i] == '\\' and i+1 < len(source) and not (language == 'octave' and quote == "'"):value += source[i:i+2];i += 2;continue
                if source[i] == quote:
                    if language == 'octave' and i+1 < len(source) and source[i+1] == quote:value += quote;i += 2;continue
                    i += 1;break
                value += source[i];i += 1
            else:raise ValueError(f'{line}:{col}: unterminated quoted string')
            text = source[start:i];line += text.count('\n');col = len(text.rsplit('\n',1)[-1])+1 if '\n' in text else col+len(text)
            out.append(Token('string', value, start_line, start_col));command_start = False;continue
        # A hyphen belongs to Tcl command/variable names, but is subtraction in
        # Octave/C++. Treating n-p as an identifier hides private DOF formulas.
        identifier = r'(?:::)?[A-Za-z_][A-Za-z_0-9:.-]*' if language == 'tcl' else r'(?:::)?[A-Za-z_][A-Za-z_0-9:.]*'
        match = re.match(identifier, source[i:])
        if match:
            text = match.group();out.append(Token('identifier', text, line, col));i += len(text);col += len(text);command_start = False;continue
        kind = 'separator' if ch == ';' else 'punctuation'
        out.append(Token(kind, ch, line, col));i += 1;col += 1;command_start = ch in ';{'
    return out


def structural_statements(tokens):
    """Build nested bracket groups; emit parent and nested command statements."""
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []; statements = []; current = []
    for token in tokens:
        if token.value in ('(', '[', '{') and token.kind == 'punctuation':
            stack.append((token, current, []));current = []
        elif token.value in pairs and token.kind == 'punctuation':
            if not stack or stack[-1][0].value != pairs[token.value]:
                raise ValueError(f'{token.line}:{token.column}: unbalanced {token.value}')
            statements.append(current)
            opening, parent, contents = stack.pop();current = parent + [opening] + contents + current + [token]
        elif token.kind == 'separator':
            if current:statements.append(current)
            if stack:stack[-1][2].extend(current + [token])
            current = []
        else:current.append(token)
    if stack:
        opening = stack[-1][0];raise ValueError(f'{opening.line}:{opening.column}: unclosed {opening.value}')
    if current:statements.append(current)
    return statements


def canonical(value):
    return value.split('::')[-1].split('.')[-1].lower()


REPORT_OPERATIONS = frozenset({'table_csv_rows', 'numeric_field_elements', 'numeric_fields', 'solver_report', 'report',
    'ini_report', 'parameter_report', 'parameter_correlation_report',
    'parameter_ini_report', 'scalar_rows', 'parameter_rows', 'table_report', 'table_rows'})


def python_unvalidated_statistics(node):
    """Ignore only exact validated CORE calls, never their sibling arguments."""
    if isinstance(node, ast.Call) and ast.unparse(node.func) in ('gxtxt_api_call', 'gxtxt.gxtxt_api_call'):
        if (len(node.args) >= 2 and isinstance(node.args[0], ast.Constant)
                and node.args[0].value == API and isinstance(node.args[1], ast.Constant)
                and node.args[1].value in REPORT_OPERATIONS):
            return set()
    found = set()
    if isinstance(node, ast.Name) and node.id.lower() in STATS:
        found.add(node.id.lower())
    elif isinstance(node, ast.Attribute) and node.attr.lower() in STATS:
        found.add(node.attr.lower())
    elif isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant) and node.slice.value in STATS:
        found.add(node.slice.value)
    for child in ast.iter_child_nodes(node):
        found.update(python_unvalidated_statistics(child))
    return found


def validated_report_positions(tokens):
    """Exact nested public calls only; never trust an entire file/function."""
    ends={};stack=[]
    for i, token in enumerate(tokens):
        if token.kind=='punctuation' and token.value=='(':stack.append(i)
        elif token.kind=='punctuation' and token.value==')' and stack:ends[stack.pop()]=i
    protected=set()
    for start,end in ends.items():
        if start==0:continue
        function=tokens[start-1].value
        args=tokens[start+1:end]
        public=False
        if function=='gxtxt_statistics_v1' and args:
            public=args[0].kind=='string' and args[0].value in REPORT_OPERATIONS
        elif function=='gxtxt_api_call' and len(args)>=3:
            public=(args[0].kind=='string' and args[0].value==API and args[1].value==',' and
                    args[2].kind=='string' and args[2].value in REPORT_OPERATIONS)
        if public:protected.update((t.line,t.column) for t in args)
    return protected


def native_statistical_initializers(tokens):
    """Known public C aggregate slots, including positional compound literals.

    This deliberately targets declared statistical result types rather than
    treating ordinary mathematical initializers as statistical policy.
    """
    for index, token in enumerate(tokens):
        slots = NATIVE_STATISTICAL_AGGREGATES.get(token.value)
        if token.kind != 'identifier' or not slots:
            continue
        # C compound literal: (public_result_type){ ... }
        if index == 0 or tokens[index-1].value != '(' or index+2 >= len(tokens):
            continue
        if tokens[index+1].value != ')' or tokens[index+2].value != '{':
            continue
        depth = 0; fields = [[]]
        for item in tokens[index+3:]:
            if item.value == '}' and depth == 0:
                break
            if item.value == ',' and depth == 0:
                fields.append([]); continue
            if item.value in ('(', '[', '{'): depth += 1
            if item.value in (')', ']', '}'): depth -= 1
            fields[-1].append(item)
        for position, quantity in slots.items():
            if position >= len(fields): continue
            expression = fields[position]
            if any(t.value in ('+', '-', '*', '/', 'sqrt', 'sqrtl', 'pow', 'powl') for t in expression):
                yield token.line, quantity


def scan(path, relative):
    language = SUFFIXES[path.suffix];source = path.read_text(encoding='utf-8')
    findings = []; seen = set()
    def emit(rule, line, operation, reason, severity='violation'):
        identity = (rule, line, operation)
        if identity not in seen:
            findings.append({'file': relative, 'line': line, 'operation': operation,
                             'authority': API, 'rule': rule, 'reason': reason, 'severity': severity})
            seen.add(identity)
    if relative in OWNERS:
        return findings, {'language': language, 'authority': OWNERS[relative], 'statistical': True, 'public_boundary': True}
    try:
        if language == 'tcl':
            from architecture_tcl_parser import parse
            tokens, statements = parse(source,Token)
        else:
            tokens = lex(source, language) if language != 'python' else []
            statements = structural_statements(tokens) if tokens else []
        tree = ast.parse(source, filename=relative) if language == 'python' else None
    except (SyntaxError, ValueError) as error:
        # Parse errors never silently become architectural PASS.
        emit('unresolved_parse', getattr(error, 'lineno', 1) or 1, 'parse', str(error), 'unknown')
        return findings, {'language': language, 'statistical': False, 'public_boundary': False}
    names = {canonical(t.value) for t in tokens if t.kind in ('identifier','string','validated_report')}
    if tree is not None:
        for node in ast.walk(tree):
            if isinstance(node, ast.Name):names.add(node.id.lower())
            elif isinstance(node, ast.Attribute):names.add(node.attr.lower())
            elif isinstance(node, ast.Constant) and isinstance(node.value,str):names.add(node.value.lower())
    statistical = bool(names & (STATS | POLICIES | set(NATIVE_STATISTICAL_AGGREGATES)))
    public_boundary = API.lower() in names or bool(names & {'gxtxt_statistics_v1','gxtxt_statistics_values_v1'}) or any(t.value.startswith('::GX::StatisticsV1::') and not t.value.startswith('::GX::StatisticsV1::_') for t in tokens)
    # Only the explicit CORE owners above may enter private interpretation
    # helpers. A consumer must not inject a model snapshot or policy through an
    # internal command and receive credit for a public API boundary.
    for index, token in enumerate(tokens):
        if token.value.startswith('::GX::StatisticsV1::_'):
            statistical = True
            emit('private_semantics_dependency',token.line,token.value,'Use the versioned public CORE operation; private interpretation helpers are not consumer APIs')
        if token.value == API:
            following = next((t for t in tokens[index+1:] if t.kind not in ('punctuation','separator')),None)
            if following is not None and following.kind == 'string' and following.value.startswith('_'):
                statistical = True
                emit('private_semantics_dependency',following.line,following.value,'A Script Bridge operation must be registered publicly; private CORE dispatch is forbidden')
    numerical_owner = relative.startswith(NUMERIC_ROOT)
    if language == 'cpp' and not numerical_owner:
        for line, quantity in native_statistical_initializers(tokens):
            emit('private_statistic',line,quantity,'Positional statistical result initializer must consume the public Numeric reduction owner')
    if tree is not None:
        for node in ast.walk(tree):
            if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef)):
                if node.name in ('gxtxt_api_call','interpret_statistics','statistics_semantics'):
                    emit('shadow_authority',node.lineno,node.name,'Use the registered CORE result API; do not define a parallel public facade')
            if isinstance(node,(ast.Import,ast.ImportFrom)):
                modules = [node.module or ''] if isinstance(node,ast.ImportFrom) else [n.name for n in node.names]
                for module in modules:
                    if ('math.numeric' in module or 'math_numeric' in module) and any(x in module for x in ('runtime','_private','_solver')):
                        emit('private_dependency',node.lineno,module,'Discover and invoke NUMERIC_API_v1 rather than an implementation file')
            if isinstance(node,(ast.Assign,ast.AnnAssign)):
                targets = node.targets if isinstance(node,ast.Assign) else [node.target]
                target_names = set()
                for target in targets:
                    for part in ast.walk(target):
                        if isinstance(part,ast.Name):target_names.add(part.id.lower())
                        if isinstance(part,ast.Constant) and isinstance(part.value,str):target_names.add(part.value.lower())
                if target_names & POLICIES:
                    emit('private_policy',node.lineno,','.join(sorted(target_names & POLICIES)),'Register a model descriptor with CORE instead of a private applicability policy')
                if not numerical_owner and target_names & STATS and node.value is not None and any(isinstance(n,(ast.BinOp,ast.Compare,ast.IfExp)) or isinstance(n,ast.Call) and canonical(ast.unparse(n.func)) in ('sqrt','sqrtl','pow','powl','log','log10','exp','std','var','cov','corr','corrcoef','mean','median') for n in ast.walk(node.value)):
                    emit('private_statistic',node.lineno,','.join(sorted(target_names & STATS)),'Compute through Numeric and interpret through the common CORE boundary')
            if isinstance(node,ast.Call):
                function = ast.unparse(node.func)
                constants = [a.value for a in node.args if isinstance(a,ast.Constant) and isinstance(a.value,str)]
                for target in constants:
                    if target.startswith('::GX::StatisticsV1::_') or API in constants and target.startswith('_'):
                        statistical = True
                        emit('private_semantics_dependency',node.lineno,target,'Use the versioned public CORE operation; private interpretation dispatch is forbidden')
                if not numerical_owner and canonical(function) in DIRECT_ESTIMATORS:
                    statistical = True
                    emit('private_statistic',node.lineno,function,'Direct statistical estimator calls belong to the public Numeric owner, regardless of the output variable name')
                if statistical and function in ('eval','exec','getattr'):
                    emit('dynamic_statistical_dispatch',node.lineno,function,'Dynamic statistical use requires a scoped reviewed runtime/publication test','unknown')
                if function.split('.')[-1] in ('print','write','writerow','writerows','publish','publish_metadata') and any(python_unvalidated_statistics(arg) for arg in [*node.args, *(keyword.value for keyword in node.keywords)]):
                    emit('unvalidated_report',node.lineno,function,'Report through CORE or explicitly validate the result contract before publication')
    else:
        report_positions=validated_report_positions(tokens) if language in ('octave','cpp') else set()
        for statement in statements:
            words = [canonical(t.value) for t in statement if t.kind in ('identifier','string','validated_report')]
            values = [t.value for t in statement]
            if not words:continue
            if not numerical_owner:
                for index, token in enumerate(statement):
                    if token.kind != 'identifier' or canonical(token.value) not in DIRECT_ESTIMATORS:
                        continue
                    is_call = index + 1 < len(statement) and statement[index + 1].value == '('
                    if language == 'tcl':
                        is_call = index == 0 and token.value.startswith(('::math::statistics::', 'math::statistics::'))
                    if is_call:
                        statistical = True
                        emit('private_statistic',token.line,token.value,'Direct statistical estimator calls belong to the public Numeric owner, regardless of the output variable name')
            used_stats = {canonical(t.value) for t in statement if t.kind in ('identifier','string') and (t.line,t.column) not in report_positions} & STATS
            all_used_stats = set(words) & STATS
            policies = set(words) & POLICIES
            if language == 'tcl' and not numerical_owner and words[0] in ('append','set','puts','return'):
                labels = {canonical(t.value) for t in statement if t.kind != 'validated_report'} & SUMMARY_LABELS
                if labels and 'expr' in words and any(canonical(t.value) in ('+','-','*','/','sqrt','sqrtl','pow','powl','log','log10','exp') for t in statement):
                    statistical = True
                    emit('private_statistic',statement[0].line,','.join(sorted(labels)),
                         'Statistical arithmetic embedded in a labeled UI/report output must use Numeric and CORE interpretation')
            if policies:
                token = next(t for t in statement if canonical(t.value) in policies)
                emit('private_policy',token.line,canonical(token.value),'Register applicability at the public CORE descriptor owner')
            for token in statement:
                if token.kind == 'string' and ('math.numeric/' in token.value or 'math.numeric\\' in token.value) and any(s in token.value for s in ('/runtime/','/api/octave/','\\runtime\\')):
                    emit('private_dependency',token.line,'load implementation path','Discover the public Numeric binding; do not embed a private provider path')
            if all_used_stats and not numerical_owner:
                first = statement[0]
                if language == 'tcl' and words[0] == 'set' and len(words)>1 and words[1] in STATS and 'expr' in words and any(canonical(t.value) in ('+','-','*','/','sqrt','sqrtl','pow','powl','log','log10','exp') for t in statement):
                    emit('private_statistic',first.line,words[1],'Compute through Numeric; Tcl presentation must consume the public interpreted result')
                if used_stats and words[0] in ('print','println','fprintf','printf','sprintf','puts','disp','display','publish_metadata'):
                    emit('unvalidated_report',first.line,words[0],'Raw statistical fields or labels reach an output boundary without the CORE validated report')
                # Tcl assigns through commands; equals signs in literal help text are data.
                assignments = [i for i,t in enumerate(statement) if t.value == '='] if language != 'tcl' else []
                for index in assignments:
                    if index and statement[index-1].value in ('=','!','<','>') or index+1<len(statement) and statement[index+1].value=='=':continue
                    previous = max((i for i,t in enumerate(statement[:index]) if t.kind=='separator'),default=-1)
                    following = next((i for i in range(index+1,len(statement)) if statement[i].kind=='separator'),len(statement))
                    left = {canonical(t.value) for t in statement[previous+1:index]}
                    right = statement[index+1:following]
                    if left & STATS and any(canonical(t.value) in ('+','-','*','/','sqrt','sqrtl','pow','powl','log','log10','exp','std','var','cov','corr','corrcoef','mean','median') for t in right):
                        emit('private_statistic',first.line,','.join(sorted(left & STATS)),'Module-local statistical computation/interpretation must use the public authorities')
                if words[0] in ('if','elseif','switch','case') and (set(words)&{'model','model_id','model_name'}) and all_used_stats:
                    emit('private_model_policy',first.line,','.join(sorted(all_used_stats)),'Model-specific statistical meaning belongs in the CORE descriptor contract')
            if statistical and words[0] in ('eval','uplevel','feval','str2func'):
                emit('dynamic_statistical_dispatch',statement[0].line,words[0],'Indirect statistical dispatch needs a scoped audited runtime contract','unknown')
            if words[0] in ('proc','function') and any(t.value in ('::GX::StatisticsV1::interpret','gxtxt_api_call','interpret_statistics','gxtxt_statistics_v1','gxtxt_statistics_values_v1') for t in statement[1:6]):
                emit('shadow_authority',statement[0].line,words[1],'Public statistical authority may only be defined by its registered CORE owner')
    return findings, {'language': language, 'statistical': statistical,
                      'public_boundary': public_boundary, 'numerical_owner': numerical_owner}


def run(root, extra_roots=()):
    diagnostics = [];inventory = [];modules = {}
    directories = [root / p for p in ('core','app','plugins','session_generators',
                                     'session_generator_libraries',
                                     'session_generator_packages/expanded')] + list(extra_roots)
    paths = sorted({p for directory in directories if directory.exists() for p in directory.rglob('*')
                    if p.is_file() and p.suffix in SUFFIXES and not SKIP_PARTS.intersection(p.relative_to(root).parts)})
    for path in paths:
        relative = path.relative_to(root).as_posix()
        try: found, evidence = scan(path, relative)
        except (UnicodeError, OSError) as error:
            found = [{'file':relative,'line':1,'operation':'read','authority':API,'rule':'unresolved_parse','reason':str(error),'severity':'unknown'}];evidence = {'statistical':False,'public_boundary':False}
        diagnostics.extend(found);inventory.append({'file':relative,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),**evidence})
        parts = path.relative_to(root).parts
        if len(parts)>3 and parts[:2] == ('plugins','modules'):
            entry = modules.setdefault(parts[2], {'statistical':False,'public_boundary':False})
            entry['statistical'] |= evidence['statistical'];entry['public_boundary'] |= evidence['public_boundary']
    for module, flags in modules.items():
        if not flags['statistical'] or module == 'math.numeric':continue
        manifest = root/'plugins/modules'/module/'module.ini'
        parser = configparser.ConfigParser(interpolation=None,strict=False);parser.read(manifest,encoding='utf-8')
        if parser.get('statistical_results','semantics_api',fallback='') != API:
            diagnostics.append({'file':manifest.relative_to(root).as_posix(),'line':1,'operation':'statistics declaration','authority':API,'rule':'missing_dependency','reason':'Statistical consumer must declare [statistical_results] semantics_api and a real boundary','severity':'violation'})
        elif not flags['public_boundary']:
            diagnostics.append({'file':manifest.relative_to(root).as_posix(),'line':1,'operation':'statistics boundary','authority':API,'rule':'missing_invocation','reason':'Manifest declaration has no discoverable CORE invocation; audit indirect boundaries explicitly','severity':'violation'})
    exception_path = root/'docs/architecture/STATISTICAL_SEMANTICS_EXCEPTIONS.json'
    exceptions = json.loads(exception_path.read_text()) if exception_path.exists() else []
    approved = [];remaining = []
    for diagnostic in diagnostics:
        match = None
        for exception in exceptions:
            required = {'file','line','rule','owner','reason','test','sha256'}
            if not required <= exception.keys() or not exception['owner'] or not exception['reason']:
                raise ValueError('Exception registry contains an unauditable entry')
            if all(exception[k] == diagnostic[k] for k in ('file','line','rule')):
                target = root/exception['file'];test = root/exception['test']
                if not target.is_file() or not test.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=exception['sha256']:
                    raise ValueError('Stale exception or missing test: '+exception['file'])
                match = exception;break
        if match:approved.append({**diagnostic,'exception':match})
        else:remaining.append(diagnostic)
    return {'api_id':API,'status':'FAIL' if remaining else 'PASS','diagnostics':remaining,'approved_exceptions':approved,
            'inventory':inventory,'coverage':{'python':'AST assignments/imports/calls','tcl':'Tcl 8.6 public command parser, recursive static bodies, no evaluation','octave_cpp':'comment/string-aware lexer and nested structural statements',
            'runtime':'separate mandatory publication and real Script Job gates',
            'limits':['No proof against arbitrary obfuscation','Indirect/dynamic statistical calls are unresolved gate findings','Third-party vendor trees and historical validation fixtures are excluded explicitly','C++ preprocessing and cross-process dynamic code require runtime evidence']}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('framework',type=Path);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--include',action='append',default=[],help='Additional relative production/fixture directory')
    args = parser.parse_args();root = args.framework.resolve()
    extra = [(root/path).resolve() for path in args.include]
    if any(not p.is_relative_to(root) for p in extra):parser.error('Additional roots must remain inside the framework')
    report = run(root,extra);args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(f"STATISTICAL_SEMANTICS_{report['status']}: {len(report['diagnostics'])} unapproved findings; {len(report['inventory'])} files")
    for finding in report['diagnostics'][:20]:print(f"{finding['file']}:{finding['line']}: {finding['rule']}: {finding['reason']}")
    return 1 if report['diagnostics'] else 0


if __name__ == '__main__':
    sys.exit(main())
