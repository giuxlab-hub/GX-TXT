function analysis_harmonic_analysis_main(args)
% Dataset-native harmonic analysis of an existing amplitude spectrum.
% Generic reusable numerical reductions are provided by public NUMERIC_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id = 'analysis.harmonic_analysis';
  module_version = '1.1.0';
  P = struct();
  publication_open = false;
  publication_finalized = false;

  config_path = arg_value(args, '--config', '');
  if (isempty(config_path))
    error('%s: --config is required', module_id);
  endif

  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg, 'runtime.output_dir', ''));
  session = strtrim(gxtxt_ini_get(cfg, 'runtime.session', ''));
  if (isempty(outdir) || isempty(session))
    error('%s: runtime.output_dir and runtime.session are required', module_id);
  endif
  if (exist(outdir, 'dir') != 7)
    mkdir(outdir);
  endif

  root = framework_root();
  numeric = discover_numeric_api(cfg, module_id);
  discover_plot_service(root, module_id);
  gxtxt_progress_start('prepare', 'Preparing harmonic analysis', 'indeterminate');

  try
    source_dataset_id = strtrim(gxtxt_ini_get(cfg, 'analysis_source.primary.dataset_id', ''));
    if (isempty(source_dataset_id))
      source_dataset_id = strtrim(gxtxt_ini_get(cfg, 'dataset.id', ''));
    endif
    if (isempty(source_dataset_id))
      error('%s: primary spectrum Dataset ID is missing', module_id);
    endif

    f_binding = binding_column(gxtxt_ini_get(cfg, 'bindings.frequency', ''), 'frequency');
    a_binding = binding_column(gxtxt_ini_get(cfg, 'bindings.amplitude', ''), 'amplitude');
    if (isempty(f_binding) || isempty(a_binding))
      error('%s: Frequency and Amplitude bindings are required', module_id);
    endif

    [f_unit, ~, f_meta] = gxtxt_analysis_source_variable_meta(cfg, 'primary', f_binding);
    [a_unit, ~, a_meta] = gxtxt_analysis_source_variable_meta(cfg, 'primary', a_binding);
    if (!meta_found(f_meta) || !meta_found(a_meta))
      error('%s: Frequency or Amplitude binding could not be resolved', module_id);
    endif

    f_id = strtrim(f_meta.variable_id);
    a_id = strtrim(a_meta.variable_id);
    f_name = strtrim(f_meta.name);
    a_name = strtrim(a_meta.name);
    if (isempty(f_id) || isempty(a_id) || strcmp(f_id, a_id))
      error('%s: stable and distinct Frequency/Amplitude variable IDs are required', module_id);
    endif
    if (isempty(f_name)), f_name = f_id; endif
    if (isempty(a_name)), a_name = a_id; endif

    mode = lower(strtrim(gxtxt_ini_get(cfg, 'config.fundamental_mode', 'auto_peak')));
    if (!any(strcmp(mode, {'auto_peak', 'explicit'})))
      error('%s: unsupported fundamental detection mode', module_id);
    endif

    explicit_f = str2double(strtrim(gxtxt_ini_get(cfg, 'config.fundamental_frequency', '')));
    max_harm = parse_int(gxtxt_ini_get(cfg, 'config.max_harmonic', '10'), 2, 10000, module_id, 'max_harmonic');
    guard = parse_int(gxtxt_ini_get(cfg, 'config.search_half_width_bins', '2'), 0, 1000, module_id, 'search_half_width_bins');
    dc_bins = parse_int(gxtxt_ini_get(cfg, 'config.exclude_dc_bins', '1'), 0, 1000, module_id, 'exclude_dc_bins');
    if (strcmp(mode, 'explicit') && (!isfinite(explicit_f) || explicit_f <= 0))
      error('%s: explicit fundamental frequency must be a positive finite value', module_id);
    endif

    output_dataset_id = strtrim(gxtxt_ini_get(cfg, 'config.output_dataset_id', 'harmonic_analysis.result'));
    if (isempty(regexp(output_dataset_id, '^[A-Za-z0-9_.-]+$', 'once')))
      error('%s: invalid output Dataset ID', module_id);
    endif
    if (strcmp(output_dataset_id, source_dataset_id))
      error('%s: output Dataset ID must differ from source Dataset ID', module_id);
    endif

    gxtxt_progress_stage('load_dataset', 'Reading spectrum Dataset', 'indeterminate');
    [freq, amp, source_provider] = read_spectrum(cfg, f_id, a_id);
    if (numel(freq) < 3)
      error('%s: spectrum must contain at least three bins', module_id);
    endif

    grid = feval(numeric.function_name, 'grid_info', freq, struct('nonfinite', 'error'));
    if (!isfield(grid, 'strict_monotonic') || !grid.strict_monotonic || !strcmp(grid.direction, 'increasing'))
      error('%s: frequency coordinate must be strictly increasing', module_id);
    endif
    df = grid.step_median;
    if (!isfinite(df) || df <= 0)
      error('%s: cannot determine a positive frequency spacing', module_id);
    endif
    if (freq(1) < 0)
      error('%s: one-sided harmonic analysis requires a non-negative frequency axis', module_id);
    endif

    amp_stats = feval(numeric.function_name, 'statistics', amp, struct('nonfinite', 'error'));
    if (amp_stats.min < 0)
      error('%s: amplitude spectrum must be non-negative', module_id);
    endif

    gxtxt_progress_stage('harmonics', 'Detecting fundamental and harmonics', 'determinate', max_harm);
    if (strcmp(mode, 'auto_peak'))
      start_idx = dc_bins + 2;
      if (start_idx > numel(amp)), start_idx = numel(amp); endif
      [fund_idx, fund_amp] = range_max_index(amp, start_idx, numel(amp), numeric.function_name);
      if (!isfinite(fund_amp) || fund_amp <= 0)
        error('%s: automatic fundamental search found no positive spectral peak', module_id);
      endif
    else
      fund_idx = local_peak_index(freq, amp, explicit_f, guard, numeric.function_name);
      fund_amp = amp(fund_idx);
      if (fund_amp <= 0)
        error('%s: explicit fundamental search resolved to a non-positive amplitude', module_id);
      endif
    endif

    f0 = freq(fund_idx);
    highest_frequency = freq(end);
    orders = [];
    expected = [];
    detected = [];
    amplitudes = [];
    errors = [];

    for k = 1:max_harm
      target = k * f0;
      if (target > highest_frequency + 0.5 * df)
        break;
      endif
      idx = local_peak_index(freq, amp, target, guard, numeric.function_name);
      orders(end+1, 1) = k;
      expected(end+1, 1) = target;
      detected(end+1, 1) = freq(idx);
      amplitudes(end+1, 1) = amp(idx);
      errors(end+1, 1) = freq(idx) - target;
      gxtxt_progress_update(k, max_harm, 'harmonics', sprintf('Processed harmonic order %d', k));
    endfor

    if (isempty(orders) || orders(1) != 1)
      error('%s: fundamental could not be represented in harmonic result', module_id);
    endif

    amplitudes(1) = fund_amp;
    detected(1) = f0;
    errors(1) = 0;
    safe_amplitudes = amplitudes;
    safe_amplitudes(safe_amplitudes < realmin) = realmin;
    amplitude_dbc = 20 * log10(safe_amplitudes / fund_amp);
    amplitude_percent = 100 * amplitudes / fund_amp;

    if (numel(amplitudes) > 1)
      sq_stats = feval(numeric.function_name, 'statistics', amplitudes(2:end).^2, struct('nonfinite', 'error'));
      thd_ratio = sqrt(sq_stats.sum) / fund_amp;
    else
      thd_ratio = 0;
    endif
    thd_percent = 100 * thd_ratio;
    if (thd_ratio > 0)
      thd_db = 20 * log10(thd_ratio);
    else
      thd_db = -Inf;
    endif

    provenance = sprintf('%s %s; source spectrum=%s; fundamental_mode=%s; f0=%.17g; max_harmonic=%d; search_half_width_bins=%d', ...
      module_id, module_version, source_dataset_id, mode, f0, max_harm, guard);
    popts = struct('storage', 'auto', 'replace_owned', true, ...
      'producer_version', module_version, ...
      'source_dataset_ids', {{source_dataset_id}}, ...
      'source_variable_ids', {{f_id, a_id}}, ...
      'source', source_dataset_id, ...
      'provenance', provenance, ...
      'notes', 'Integer-harmonic peak measurements derived from an existing amplitude spectrum; source spectrum is not recomputed or modified.');

    gxtxt_progress_stage('publish', 'Publishing harmonic result Dataset', 'determinate', numel(orders));
    P = gxtxt_publication_v2_open(session, module_id, output_dataset_id, 'table.generic', popts);
    publication_open = true;
    P = gxtxt_publication_v2_declare_dimension(P, 'harmonic', 0, true);
    P = declare_numeric(P, 'harmonic_order', 'harmonic_order', 'identifier', '1');
    P = declare_numeric(P, 'expected_frequency', 'expected_frequency', 'frequency', f_unit);
    P = declare_numeric(P, 'detected_frequency', 'detected_frequency', 'frequency', f_unit);
    P = declare_numeric(P, 'frequency_error', 'frequency_error', 'frequency_delta', f_unit);
    P = declare_numeric(P, 'amplitude', 'amplitude', 'measured', a_unit);
    P = declare_numeric(P, 'amplitude_dbc', 'amplitude_dBc', 'relative_level', 'dB');
    P = declare_numeric(P, 'amplitude_percent', 'amplitude_percent', 'relative_level', '%');
    P = gxtxt_publication_v2_append(P, 'harmonic', { ...
      'harmonic_order', double(orders); ...
      'expected_frequency', double(expected); ...
      'detected_frequency', double(detected); ...
      'frequency_error', double(errors); ...
      'amplitude', double(amplitudes); ...
      'amplitude_dbc', double(amplitude_dbc); ...
      'amplitude_percent', double(amplitude_percent)});
    [P, pub_diag] = gxtxt_publication_v2_diagnostics(P);
    [P, pub_result] = gxtxt_publication_v2_finalize(P);
    publication_finalized = true;
    publication_open = false;

    write_metrics(fullfile(outdir, 'harmonic_analysis_metrics.ini'), module_id, module_version, ...
      source_dataset_id, output_dataset_id, f_id, a_id, f_name, a_name, f_unit, a_unit, ...
      source_provider, mode, f0, fund_amp, max_harm, guard, dc_bins, numel(orders), ...
      thd_ratio, thd_percent, thd_db, P.provider);
    write_report(fullfile(outdir, 'harmonic_analysis_report.txt'), module_id, module_version, ...
      source_dataset_id, output_dataset_id, f_name, f_id, f_unit, a_name, a_id, a_unit, ...
      mode, f0, fund_amp, orders, expected, detected, errors, amplitudes, amplitude_dbc, ...
      amplitude_percent, thd_ratio, thd_percent, thd_db, guard, pub_diag, pub_result);

    dbc_stats = feval(numeric.function_name, 'statistics', amplitude_dbc, struct('nonfinite', 'error'));
    db_baseline = dbc_stats.min - 3;
    if (db_baseline > -3), db_baseline = -3; endif
    gxtxt_progress_stage('plot', 'Creating persistent plot.dataset harmonic graphs', 'indeterminate');
    graphs = create_standard_graphs(session, output_dataset_id, a_unit, db_baseline, module_id);
    copy_graph_artifacts(graphs, outdir, module_id);
    write_graph_manifest(fullfile(outdir, 'automatic_graphs.ini'), graphs);

    gxtxt_progress_complete('done', sprintf('Published %s with %d harmonic order(s); THD %.6g %%', ...
      output_dataset_id, numel(orders), thd_percent));
    fprintf('[%s] version=%s source=%s output=%s f0=%.12g harmonics=%d thd_percent=%.12g validation=PASS\n', ...
      module_id, module_version, source_dataset_id, output_dataset_id, f0, numel(orders), thd_percent);
  catch err
    if (publication_open && !publication_finalized)
      try
        P = gxtxt_publication_v2_abort(P);
      catch
      end_try_catch
    endif
    try
      gxtxt_progress_fail('failed', 'Harmonic analysis failed; see log for details');
    catch
    end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function tf = meta_found(meta)
  tf = isstruct(meta) && isfield(meta, 'found') && meta.found;
endfunction

function out = binding_column(value, role)
  value = strtrim(value);
  if (isempty(value) || strcmp(value, 'auto'))
    out = '';
    return;
  endif
  dot = find(value == '.', 1);
  if (!isempty(dot))
    out = value(dot+1:end);
  else
    out = value;
  endif
  if (isempty(out))
    error('analysis.harmonic_analysis: invalid %s binding', role);
  endif
endfunction

function [f, a, provider] = read_spectrum(cfg, fid, aid)
  S = gxtxt_table_stream_open_source(cfg, 'primary', {fid, aid}, 65536, ...
    struct('start', 0, 'count', -1, 'require_direct', false));
  provider = S.storage_provider;
  fc = {};
  ac = {};
  unwind_protect
    while (!S.eof)
      [S, C] = gxtxt_table_stream_next(S);
      if (C.nrows > 0)
        fc{end+1} = double(C.values{1}(:));
        ac{end+1} = double(C.values{2}(:));
      endif
    endwhile
  unwind_protect_cleanup
    S = gxtxt_table_stream_close(S);
  end_unwind_protect
  if (isempty(fc))
    f = zeros(0, 1);
    a = zeros(0, 1);
  else
    f = vertcat(fc{:});
    a = vertcat(ac{:});
  endif
endfunction

function [idx, value] = range_max_index(values, lo, hi, numeric_api)
  if (lo < 1 || hi > numel(values) || lo > hi)
    error('analysis.harmonic_analysis: invalid peak-search range');
  endif
  part = values(lo:hi);
  S = feval(numeric_api, 'statistics', part, struct('nonfinite', 'error'));
  value = S.max;
  rel = find(part == value, 1, 'first');
  if (isempty(rel))
    error('analysis.harmonic_analysis: public numerical maximum could not be mapped to a source bin');
  endif
  idx = lo + rel - 1;
endfunction

function idx = local_peak_index(freq, amp, target, guard, numeric_api)
  [~, nearest] = min(abs(freq - target));
  lo = nearest - guard;
  if (lo < 1), lo = 1; endif
  hi = nearest + guard;
  if (hi > numel(amp)), hi = numel(amp); endif
  [idx, ~] = range_max_index(amp, lo, hi, numeric_api);
endfunction

function api = discover_numeric_api(cfg, module_id)
  sec = 'public_api.NUMERIC_API_v1';
  provider = strtrim(gxtxt_ini_get(cfg, [sec '.module_id'], ''));
  if (!strcmp(provider, 'math.numeric'))
    error('%s: runtime NUMERIC_API_v1 provider discovery failed', module_id);
  endif
  if (!strcmp(strtrim(gxtxt_ini_get(cfg, [sec '.api_version'], '')), '1'))
    error('%s: unsupported runtime NUMERIC_API_v1 version', module_id);
  endif
  caps = split_list(gxtxt_ini_get(cfg, [sec '.capabilities'], ''));
  required = {'grid_analysis', 'descriptive_statistics'};
  for k = 1:numel(required)
    if (!any(strcmp(caps, required{k})))
      error('%s: NUMERIC_API_v1 capability missing: %s', module_id, required{k});
    endif
  endfor
  entry = strtrim(gxtxt_ini_get(cfg, [sec '.octave_entrypoint'], ''));
  fn = strtrim(gxtxt_ini_get(cfg, [sec '.octave_function'], ''));
  if (isempty(entry) || isempty(fn) || exist(entry, 'file') != 2)
    error('%s: runtime NUMERIC_API_v1 Octave binding unavailable', module_id);
  endif
  addpath(fileparts(entry));
  if (exist(fn, 'file') != 2)
    error('%s: advertised NUMERIC_API_v1 function unavailable', module_id);
  endif
  api = struct('function_name', fn, 'provider', provider);
endfunction

function discover_plot_service(root, module_id)
  pd = fullfile(root, 'plugins', 'modules', 'plot.dataset', 'module.ini');
  if (exist(pd, 'file') != 2), error('%s: plot.dataset descriptor missing', module_id); endif
  d = gxtxt_ini_read(pd);
  ids = split_list(gxtxt_ini_get(d, 'public_apis.ids', ''));
  if (!any(strcmp(ids, 'PLOT_DATASET_API_v2')))
    error('%s: PLOT_DATASET_API_v2 is not advertised', module_id);
  endif
  caps = split_list(gxtxt_ini_get(d, 'public_api.PLOT_DATASET_API_v2.capabilities', ''));
  if (!any(strcmp(caps, 'series_kind_bar')))
    error('%s: PLOT_DATASET_API_v2 capability missing: series_kind_bar', module_id);
  endif
  bridge = fullfile(root, 'core', 'octave', 'io', 'gxtxt_plot_dataset_v2.m');
  if (exist(bridge, 'file') != 2)
    error('%s: public PLOT_DATASET_API_v2 Octave bridge unavailable', module_id);
  endif
  addpath(fileparts(bridge));
endfunction

function G = create_standard_graphs(session, dataset_id, amplitude_unit, db_baseline, module_id)
  G = {};
  G{end+1} = create_harmonic_plot(session, dataset_id, 'harmonic_levels_dbc', ...
    'Harmonic levels — dBc', 'amplitude_dbc', 'Amplitude [dBc]', 'dB', db_baseline, module_id);
  G{end+1} = create_harmonic_plot(session, dataset_id, 'harmonic_levels_percent', ...
    'Harmonic levels — percent of fundamental', 'amplitude_percent', 'Amplitude [% of fundamental]', '%', 0, module_id);
  G{end+1} = create_harmonic_plot(session, dataset_id, 'harmonic_levels_linear', ...
    'Harmonic levels — linear amplitude', 'amplitude', axis_label('Amplitude', amplitude_unit), amplitude_unit, 0, module_id);
endfunction

function R = create_harmonic_plot(session, dataset_id, key, title_text, yvar, ylabel_text, yunit, baseline, module_id)
  axes = struct('x', struct('label', 'Harmonic order', 'scale', 'linear'), ...
    'y_left', struct('label', ylabel_text, 'scale', 'linear'));
  series = struct('id', key, 'dataset_id', dataset_id, 'x_variable_id', 'harmonic_order', ...
    'y_variable_id', yvar, 'axis', 'left', 'kind', 'bar', 'label', ylabel_text, ...
    'bar_width', '0.72', 'bar_baseline', num2str(baseline, 17), 'style', struct('opacity', 0.45));
  panel = struct('id', 'main', 'title', title_text, 'axes', axes, 'series', {{series}});
  spec = struct('schema', 'PLOT_DATASET_PLOTSPEC_v2', 'graph_type', 'cartesian_2d', ...
    'graph_id', 'plot.dataset.xy', 'title', title_text, 'defaults', struct('style', struct()), ...
    'panels', {{panel}}, 'output', struct());
  R = gxtxt_plot_dataset_v2(session, spec, struct('action', 'create', 'kind', 'variant', ...
    'source_variant', '', 'render', true));
  if (!isfield(R, 'artifact') || isempty(strtrim(R.artifact)))
    error('%s: plot.dataset returned no artifact for %s', module_id, key);
  endif
  R.key = key;
endfunction

function copy_graph_artifacts(G, outdir, module_id)
  for i = 1:numel(G)
    src = strtrim(G{i}.artifact);
    if (isempty(src) || exist(src, 'file') != 2)
      error('%s: plot.dataset graph artifact missing for %s', module_id, G{i}.key);
    endif
    dst = fullfile(outdir, sprintf('%02d_%s.png', i, G{i}.key));
    [ok, msg] = copyfile(src, dst, 'f');
    if (!ok), error('%s: cannot copy plot.dataset artifact: %s', module_id, msg); endif
  endfor
endfunction

function write_graph_manifest(path, G)
  fid = fopen(path, 'w');
  if (fid < 0), error('analysis.harmonic_analysis: cannot write automatic graph manifest'); endif
  unwind_protect
    fprintf(fid, '[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n', numel(G));
    for i = 1:numel(G)
      fprintf(fid, '\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\npng=%02d_%s.png\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n', ...
        i, G{i}.key, ini_escape(G{i}.graph_id), ini_escape(G{i}.variant_id), i, G{i}.key, ini_escape(G{i}.artifact));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function P = declare_numeric(P, id, name, role, unit)
  spec = struct('dtype', 'float64', 'dimension_ids', 'harmonic', 'name', name, ...
    'unit', unit, 'semantic_role', role, 'coordinate_role', 'data', 'axis_kind', 'none');
  P = gxtxt_publication_v2_declare_variable(P, id, spec);
endfunction

function n = parse_int(raw, minv, maxv, module_id, name)
  n = str2double(strtrim(raw));
  if (!isfinite(n) || n < minv || n > maxv || n != fix(n))
    error('%s: %s must be an integer in [%d, %d]', module_id, name, minv, maxv);
  endif
endfunction

function write_metrics(path, id, ver, src, outid, fid, aid, fname, aname, funit, aunit, ...
    src_provider, mode, f0, A0, max_h, guard, dc, n_h, thd_ratio, thd_pct, thd_db, out_provider)
  fh = fopen(path, 'w');
  if (fh < 0), error('%s: cannot write metrics', id); endif
  unwind_protect
    fprintf(fh, '; GX-TXT analysis.harmonic_analysis metrics\n');
    fprintf(fh, '[module]\nid=%s\nversion=%s\nvalidation=PASS\n', id, ver);
    fprintf(fh, '\n[source]\ndataset_id=%s\nfrequency_variable_id=%s\namplitude_variable_id=%s\n', src, fid, aid);
    fprintf(fh, 'frequency_name=%s\namplitude_name=%s\nfrequency_unit=%s\namplitude_unit=%s\nstorage_provider=%s\n', ...
      ini_escape(fname), ini_escape(aname), ini_escape(funit), ini_escape(aunit), src_provider);
    fprintf(fh, '\n[analysis]\nfundamental_mode=%s\nfundamental_frequency=%.17g\nfundamental_amplitude=%.17g\n', mode, f0, A0);
    fprintf(fh, 'max_harmonic=%d\nsearch_half_width_bins=%d\nexclude_dc_bins=%d\nresolved_harmonics=%d\n', max_h, guard, dc, n_h);
    fprintf(fh, 'thd_ratio=%.17g\nthd_percent=%.17g\nthd_db=%.17g\n', thd_ratio, thd_pct, thd_db);
    fprintf(fh, '\n[output]\ndataset_id=%s\nstorage_provider=%s\n', outid, out_provider);
  unwind_protect_cleanup
    fclose(fh);
  end_unwind_protect
endfunction

function write_report(path, id, ver, src, outid, fname, fid, funit, aname, aid, aunit, ...
    mode, f0, A0, orders, expected, detected, errors, amps, dbc, pct, thd_ratio, thd_pct, thd_db, ...
    guard, pub_diag, pub_result)
  fh = fopen(path, 'w');
  if (fh < 0), error('%s: cannot write report', id); endif
  unwind_protect
    fprintf(fh, 'GX-TXT Harmonic Analysis\n========================\n\n');
    fprintf(fh, 'Plugin: %s %s\nSource spectrum Dataset: %s\n', id, ver, src);
    fprintf(fh, 'Frequency: %s (%s) [%s]\nAmplitude: %s (%s) [%s]\n', fname, fid, funit, aname, aid, aunit);
    fprintf(fh, 'Fundamental mode: %s\nResolved fundamental: %.12g %s\nFundamental amplitude: %.12g %s\n', ...
      mode, f0, funit, A0, aunit);
    fprintf(fh, 'Local search half-width: %d bin(s)\n\n', guard);
    fprintf(fh, 'Harmonic table\n--------------\n');
    fprintf(fh, 'Order  Expected [%s]    Detected [%s]    Error [%s]       Amplitude [%s]    dBc          %% fundamental\n', ...
      funit, funit, funit, aunit);
    for k = 1:numel(orders)
      fprintf(fh, '%-6d %-17.10g %-17.10g %-17.10g %-17.10g %-12.6g %-12.6g\n', ...
        orders(k), expected(k), detected(k), errors(k), amps(k), dbc(k), pct(k));
    endfor
    fprintf(fh, '\nTHD\n---\nTHD ratio: %.12g\nTHD: %.12g %%\nTHD: %.12g dB\n', thd_ratio, thd_pct, thd_db);
    fprintf(fh, ['\nDefinition: sqrt(sum(H2^2 ... Hn^2)) / H1 using the detected peak amplitudes published in this result. ' ...
      'Only integer harmonics up to the configured maximum and available one-sided frequency range are included.\n']);
    fprintf(fh, '\nPublished Dataset\n-----------------\nDataset ID: %s\nContract: table.generic\n', outid);
    fprintf(fh, 'Columns: harmonic_order, expected_frequency, detected_frequency, frequency_error, amplitude, amplitude_dBc, amplitude_percent\n');
    fprintf(fh, '\nPublication diagnostics: %s\nPublication result: %s\n', pub_diag, pub_result);
  unwind_protect_cleanup
    fclose(fh);
  end_unwind_protect
endfunction

function root = framework_root()
  runtime_dir = fileparts(mfilename('fullpath'));
  module_dir = fileparts(runtime_dir);
  modules_dir = fileparts(module_dir);
  plugins_dir = fileparts(modules_dir);
  root = fileparts(plugins_dir);
endfunction

function s = axis_label(name, unit)
  if (isempty(strtrim(unit)) || strcmp(unit, '1')), s = name; else s = sprintf('%s [%s]', name, unit); endif
endfunction

function out = split_list(s)
  s = strrep(char(s), ',', ';');
  parts = strsplit(s, ';');
  out = {};
  for i = 1:numel(parts)
    q = strtrim(parts{i});
    if (!isempty(q)), out{end+1} = q; endif
  endfor
endfunction

function s = ini_escape(s)
  s = strrep(char(s), sprintf('\n'), ' ');
  s = strrep(s, sprintf('\r'), ' ');
endfunction

function value = arg_value(args, key, def)
  value = def;
  for i = 1:(numel(args)-1)
    if (strcmp(args{i}, key))
      value = args{i+1};
      return;
    endif
  endfor
endfunction
