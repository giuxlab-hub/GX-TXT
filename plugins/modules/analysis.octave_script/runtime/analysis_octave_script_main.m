function analysis_octave_script_main(args, framework_root)
% Run one user-authored GNU Octave script through OCTAVE_SCRIPT_BRIDGE_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id = 'analysis.octave_script';
  module_version = '1.4.0';
  bridge_started = false;
  original_pwd = pwd();
  original_path = path();

  config_path = arg_value(args, '--config', '');
  if (isempty(config_path))
    error('%s: --config is required', module_id);
  endif

  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg, 'runtime.output_dir', ''));
  if (isempty(outdir))
    error('%s: runtime.output_dir is required', module_id);
  endif
  if (exist(outdir, 'dir') != 7)
    mkdir(outdir);
  endif

  report_path = fullfile(outdir, 'octave_script_run_report.txt');
  snapshot_path = fullfile(outdir, 'executed_script.m');
  started_at = iso_timestamp();
  script_file = strtrim(gxtxt_ini_get(cfg, 'config.script_file', ''));
  source_mode = strtrim(gxtxt_ini_get(cfg, 'config.source_mode', 'external_file'));
  script_reference = strtrim(gxtxt_ini_get(cfg, 'config.registered_script', ''));
  script_id = strtrim(gxtxt_ini_get(cfg, 'config.script_id', ''));
  registered_name = strtrim(gxtxt_ini_get(cfg, 'config.script_name', ''));
  script_scope = strtrim(gxtxt_ini_get(cfg, 'config.script_scope', ''));
  script_version = strtrim(gxtxt_ini_get(cfg, 'config.script_version', ''));
  script_revision = strtrim(gxtxt_ini_get(cfg, 'config.script_revision', ''));
  expected_sha256 = lower(strtrim(gxtxt_ini_get(cfg, 'config.script_sha256', '')));
  if (strcmp(source_mode, 'external_file'))
    script_reference = '';
    script_id = '';
    script_scope = '';
    script_version = '';
    script_revision = '';
    expected_sha256 = '';
  endif
  working_directory = strtrim(gxtxt_ini_get(cfg, 'config.working_directory', ''));
  arguments_raw = gxtxt_ini_get(cfg, 'config.arguments', '');
  include_script_directory = logical_text(gxtxt_ini_get(cfg, 'config.include_script_directory', '1'));
  required_apis_raw = gxtxt_ini_get(cfg, 'config.required_apis', '');
  required_apis = parse_required_apis(required_apis_raw);

  script_name = '';
  script_sha256 = '';
  bridge_api_count = NaN;
  bridge_api_id = '';
  bridge_api_version = '';
  bridge_transport_version = '';
  registered_api_ids = {};
  input_summary = {};
  script_directory = '';

  try
    if (!any(strcmp(source_mode, {'registered_script', 'external_file'})))
      error('%s: unsupported script source mode: %s', module_id, source_mode);
    endif
    if (strcmp(source_mode, 'registered_script') && ...
        (isempty(script_reference) || isempty(script_id) || !strcmp(script_reference, [script_scope ':' script_id]) || isempty(expected_sha256)))
      error('%s: registered script identity is incomplete', module_id);
    endif
    if (isempty(script_file))
      error('%s: no Octave script was selected', module_id);
    endif
    if (exist(script_file, 'file') != 2)
      error('%s: selected Octave script does not exist: %s', module_id, script_file);
    endif
    [script_directory, base, ext] = fileparts(script_file);
    script_name = [base ext];
    if (strcmp(source_mode, 'registered_script') && !isempty(registered_name))
      script_name = registered_name;
    endif
    if (!strcmpi(ext, '.m'))
      error('%s: selected file must have the .m extension', module_id);
    endif
    if (!isempty(working_directory) && exist(working_directory, 'dir') != 7)
      error('%s: configured working directory does not exist: %s', module_id, working_directory);
    endif

    source_bytes = read_binary_file(script_file, module_id);
    write_binary_file(snapshot_path, source_bytes, module_id);
    script_sha256 = sha256_bytes(source_bytes);
    if (strcmp(source_mode, 'registered_script') && !strcmpi(script_sha256, expected_sha256))
      error('%s: registered Session script SHA-256 differs from the selected snapshot', module_id);
    endif

    required_bridge = {
      'gxtxt_script_bridge_start', ...
      'gxtxt_script_bridge_stop', ...
      'gxtxt_bridge_info', ...
      'gxtxt_api_list', ...
      'gxtxt_api_has', ...
      'gxtxt_api_describe', ...
      'gxtxt_api_has_operation', ...
      'gxtxt_api_call', ...
      'gxtxt_api_require', ...
      'gxtxt_context'
    };
    for k = 1:numel(required_bridge)
      if (exist(required_bridge{k}, 'file') != 2)
        error('%s: required OCTAVE_SCRIPT_BRIDGE_API_v1 function is unavailable: %s', module_id, required_bridge{k});
      endif
    endfor

    execution = struct();
    execution.script_name = script_name;
    execution.script_sha256 = script_sha256;
    execution.arguments_raw = arguments_raw;
    execution.script_snapshot_name = 'executed_script.m';
    execution.module_version = module_version;
    execution.script_reference = script_reference;
    execution.script_id = script_id;
    execution.script_scope = script_scope;
    execution.script_version = script_version;
    execution.script_revision = script_revision;

    gxtxt_script_bridge_start(config_path, execution);
    bridge_started = true;

    info = gxtxt_bridge_info();
    validate_bridge_info(info, module_id);
    bridge_api_id = scalar_text(info.api_id);
    bridge_api_version = scalar_text(info.api_version);
    if (isfield(info, 'transport_version'))
      bridge_transport_version = scalar_text(info.transport_version);
    endif

    apis = gxtxt_api_list();
    bridge_api_count = collection_count(apis);
    registered_api_ids = api_ids(apis);

    for k = 1:numel(required_apis)
      gxtxt_api_require(required_apis{k});
    endfor

    ctx = gxtxt_context();
    if (!isstruct(ctx))
      error('%s: gxtxt_context() returned an invalid value', module_id);
    endif
    if (isfield(ctx, 'module_id') && !isempty(scalar_text(ctx.module_id)) && !strcmp(scalar_text(ctx.module_id), module_id))
      error('%s: bridge execution context belongs to module %s', module_id, scalar_text(ctx.module_id));
    endif
    input_summary = context_input_summary(ctx);

    if (include_script_directory && !isempty(script_directory))
      addpath(script_directory);
    endif
    if (!isempty(working_directory))
      cd(working_directory);
    endif

    execute_user_script(snapshot_path);

    cd(original_pwd);
    path(original_path);
    gxtxt_script_bridge_stop();
    bridge_started = false;

    write_report(report_path, struct( ...
      'status', 'PASS', ...
      'module_id', module_id, ...
      'module_version', module_version, ...
      'octave_version', version(), ...
      'script_name', script_name, ...
      'script_sha256', script_sha256, ...
      'source_mode', source_mode, ...
      'script_reference', script_reference, ...
      'script_id', script_id, ...
      'script_scope', script_scope, ...
      'script_version', script_version, ...
      'script_revision', script_revision, ...
      'script_directory_in_path', include_script_directory, ...
      'working_directory', working_directory, ...
      'arguments_raw', arguments_raw, ...
      'required_apis', {required_apis}, ...
      'started_at', started_at, ...
      'finished_at', iso_timestamp(), ...
      'bridge_api_id', bridge_api_id, ...
      'bridge_api_version', bridge_api_version, ...
      'bridge_transport_version', bridge_transport_version, ...
      'registered_api_count', bridge_api_count, ...
      'registered_api_ids', {registered_api_ids}, ...
      'input_summary', {input_summary}, ...
      'message', 'User Octave script completed successfully.'));

  catch err
    try cd(original_pwd); catch; end_try_catch
    try path(original_path); catch; end_try_catch
    if (bridge_started)
      try
        gxtxt_script_bridge_stop();
      catch
      end_try_catch
      bridge_started = false;
    endif
    if (exist(snapshot_path, 'file') != 2 && !isempty(script_file) && exist(script_file, 'file') == 2)
      try
        source_bytes = read_binary_file(script_file, module_id);
        write_binary_file(snapshot_path, source_bytes, module_id);
        if (isempty(script_sha256))
          script_sha256 = sha256_bytes(source_bytes);
        endif
      catch
      end_try_catch
    endif
    try
      write_report(report_path, struct( ...
        'status', 'FAIL', ...
        'module_id', module_id, ...
        'module_version', module_version, ...
        'octave_version', safe_octave_version(), ...
        'script_name', script_name, ...
        'script_sha256', script_sha256, ...
        'source_mode', source_mode, ...
        'script_reference', script_reference, ...
        'script_id', script_id, ...
        'script_scope', script_scope, ...
        'script_version', script_version, ...
        'script_revision', script_revision, ...
        'script_directory_in_path', include_script_directory, ...
        'working_directory', working_directory, ...
        'arguments_raw', arguments_raw, ...
        'required_apis', {required_apis}, ...
        'started_at', started_at, ...
        'finished_at', iso_timestamp(), ...
        'bridge_api_id', bridge_api_id, ...
        'bridge_api_version', bridge_api_version, ...
        'bridge_transport_version', bridge_transport_version, ...
        'registered_api_count', bridge_api_count, ...
        'registered_api_ids', {registered_api_ids}, ...
        'input_summary', {input_summary}, ...
        'message', err.message));
    catch
    end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function execute_user_script(snapshot_path)
% Execute in a dedicated function workspace so ordinary script variables cannot
% overwrite the module runner state. The bridge lifecycle remains runner-owned.
  if (exist(snapshot_path, 'file') != 2)
    error('analysis.octave_script: script snapshot is missing: %s', snapshot_path);
  endif
  source(snapshot_path);
endfunction

function validate_bridge_info(info, module_id)
  if (!isstruct(info) || !isfield(info, 'api_id') || !isfield(info, 'api_version') || !isfield(info, 'active'))
    error('%s: gxtxt_bridge_info() returned an invalid OCTAVE_SCRIPT_BRIDGE_API_v1 descriptor', module_id);
  endif
  if (!strcmp(scalar_text(info.api_id), 'OCTAVE_SCRIPT_BRIDGE_API_v1'))
    error('%s: unsupported Octave Script Bridge API: %s', module_id, scalar_text(info.api_id));
  endif
  if (!strcmp(scalar_text(info.api_version), '1'))
    error('%s: unsupported Octave Script Bridge API version: %s', module_id, scalar_text(info.api_version));
  endif
  if (!logical_scalar(info.active))
    error('%s: Octave Script Bridge is not active after initialization', module_id);
  endif
endfunction

function ids = api_ids(apis)
  ids = {};
  if (isempty(apis))
    return;
  endif
  if (iscell(apis))
    items = apis;
  elseif (isstruct(apis))
    items = cell(1, numel(apis));
    for k = 1:numel(apis), items{k} = apis(k); endfor
  else
    error('analysis.octave_script: gxtxt_api_list() returned an unsupported collection type');
  endif
  for k = 1:numel(items)
    item = items{k};
    if (isstruct(item) && isfield(item, 'api_id'))
      id = scalar_text(item.api_id);
      if (!isempty(id)), ids{end + 1} = id; endif
    endif
  endfor
endfunction

function out = context_input_summary(ctx)
  out = {};
  if (!isfield(ctx, 'inputs') || !isstruct(ctx.inputs))
    return;
  endif
  aliases = fieldnames(ctx.inputs);
  for k = 1:numel(aliases)
    alias = aliases{k};
    item = ctx.inputs.(alias);
    dataset_id = '';
    contract = '';
    if (isstruct(item))
      if (isfield(item, 'dataset_id')), dataset_id = scalar_text(item.dataset_id); endif
      if (isfield(item, 'contract')), contract = scalar_text(item.contract); endif
      if (isempty(contract) && isfield(item, 'kind')), contract = scalar_text(item.kind); endif
    endif
    out{end + 1} = sprintf('%s=%s%s', alias, dataset_id, conditional_suffix(contract));
  endfor
endfunction

function s = conditional_suffix(contract)
  if (isempty(contract)), s = ''; else s = sprintf(' [%s]', contract); endif
endfunction

function n = collection_count(v)
  if (iscell(v) || isstruct(v))
    n = numel(v);
  elseif (isempty(v))
    n = 0;
  else
    error('analysis.octave_script: gxtxt_api_list() returned an unsupported collection type');
  endif
endfunction

function out = scalar_text(v)
  if (ischar(v))
    out = v;
  elseif (iscell(v) && numel(v) == 1 && ischar(v{1}))
    out = v{1};
  elseif (isnumeric(v) && isscalar(v))
    out = num2str(v, 17);
  else
    out = '';
  endif
endfunction

function tf = logical_scalar(v)
  if (islogical(v) && isscalar(v))
    tf = v;
  elseif (isnumeric(v) && isscalar(v))
    tf = (v != 0);
  elseif (ischar(v))
    tf = any(strcmpi(strtrim(v), {'1', 'true', 'yes', 'on'}));
  else
    tf = false;
  endif
endfunction

function tf = logical_text(v)
  tf = any(strcmpi(strtrim(scalar_text(v)), {'1', 'true', 'yes', 'on'}));
endfunction

function apis = parse_required_apis(raw)
  apis = {};
  raw = strtrim(scalar_text(raw));
  if (isempty(raw)), return; endif
  parts = regexp(raw, '[;,]', 'split');
  for k = 1:numel(parts)
    id = strtrim(parts{k});
    if (!isempty(id) && !any(strcmp(apis, id)))
      apis{end + 1} = id;
    endif
  endfor
endfunction

function bytes = read_binary_file(path, module_id)
  fid = fopen(path, 'rb');
  if (fid < 0)
    error('%s: cannot open script for reading: %s', module_id, path);
  endif
  unwind_protect
    bytes = fread(fid, Inf, '*uint8');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_binary_file(path, bytes, module_id)
  fid = fopen(path, 'wb');
  if (fid < 0)
    error('%s: cannot create script snapshot: %s', module_id, path);
  endif
  unwind_protect
    count = fwrite(fid, bytes, 'uint8');
    if (count != numel(bytes))
      error('%s: incomplete script snapshot write', module_id);
    endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function h = sha256_bytes(bytes)
  if (exist('hash', 'builtin') != 5 && exist('hash', 'file') != 2)
    error('analysis.octave_script: GNU Octave hash() is required for script provenance');
  endif
  h = lower(hash('sha256', char(bytes(:).')));
endfunction

function write_report(path, r)
  fid = fopen(path, 'w');
  if (fid < 0), error('analysis.octave_script: cannot create run report'); endif
  unwind_protect
    fprintf(fid, 'GX-TXT Octave Script run report\n');
    fprintf(fid, 'Status: %s\n', safe_report_text(r.status));
    fprintf(fid, 'Module: %s\n', safe_report_text(r.module_id));
    fprintf(fid, 'Module version: %s\n', safe_report_text(r.module_version));
    fprintf(fid, 'GNU Octave version: %s\n', safe_report_text(r.octave_version));
    fprintf(fid, 'Script: %s\n', safe_report_text(r.script_name));
    fprintf(fid, 'Script SHA-256: %s\n', safe_report_text(r.script_sha256));
    fprintf(fid, 'Source mode: %s\n', safe_report_text(r.source_mode));
    fprintf(fid, 'Registered reference: %s\n', safe_report_text(r.script_reference));
    fprintf(fid, 'Script ID: %s\n', safe_report_text(r.script_id));
    fprintf(fid, 'Script scope: %s\n', safe_report_text(r.script_scope));
    fprintf(fid, 'Script version: %s\n', safe_report_text(r.script_version));
    fprintf(fid, 'Script revision: %s\n', safe_report_text(r.script_revision));
    fprintf(fid, 'Script directory added to Octave path: %s\n', logical_report(r.script_directory_in_path));
    fprintf(fid, 'Working directory: %s\n', safe_report_text(r.working_directory));
    fprintf(fid, 'Arguments: %s\n', safe_report_text(r.arguments_raw));
    fprintf(fid, 'Required APIs: %s\n', join_report_list(r.required_apis));
    fprintf(fid, 'Started: %s\n', safe_report_text(r.started_at));
    fprintf(fid, 'Finished: %s\n', safe_report_text(r.finished_at));
    fprintf(fid, 'Bridge API: %s\n', safe_report_text(r.bridge_api_id));
    fprintf(fid, 'Bridge API version: %s\n', safe_report_text(r.bridge_api_version));
    fprintf(fid, 'Bridge transport version: %s\n', safe_report_text(r.bridge_transport_version));
    if (isnumeric(r.registered_api_count) && isscalar(r.registered_api_count) && isfinite(r.registered_api_count))
      fprintf(fid, 'Registered script-callable APIs: %d\n', round(r.registered_api_count));
    else
      fprintf(fid, 'Registered script-callable APIs: unknown\n');
    endif
    fprintf(fid, 'Registered API IDs: %s\n', join_report_list(r.registered_api_ids));
    fprintf(fid, 'Input aliases: %s\n', join_report_list(r.input_summary));
    fprintf(fid, 'Message: %s\n', safe_report_text(r.message));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function out = join_report_list(v)
  if (!iscell(v) || isempty(v)), out = ''; return; endif
  cleaned = cell(size(v));
  for k = 1:numel(v), cleaned{k} = safe_report_text(v{k}); endfor
  out = strjoin(cleaned, '; ');
endfunction

function out = logical_report(v)
  if (logical_scalar(v)), out = 'yes'; else out = 'no'; endif
endfunction

function out = safe_report_text(v)
  out = scalar_text(v);
  out = strrep(out, sprintf('\r'), ' ');
  out = strrep(out, sprintf('\n'), ' ');
endfunction

function t = iso_timestamp()
  try
    t = strftime('%Y-%m-%dT%H:%M:%S%z', localtime(time()));
  catch
    t = '';
  end_try_catch
endfunction

function v = safe_octave_version()
  try v = version(); catch; v = ''; end_try_catch
endfunction

function v = arg_value(args, key, default_value)
  v = default_value;
  for i = 1:numel(args)
    if (strcmp(args{i}, key) && i < numel(args))
      v = args{i + 1};
      return;
    endif
  endfor
endfunction
