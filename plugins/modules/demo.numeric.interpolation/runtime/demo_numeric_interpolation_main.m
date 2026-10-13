function demo_numeric_interpolation_main(args, framework_root)
% Dataset-native interpolation/resampling demo using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id = 'demo.numeric.interpolation';
  module_version = '1.0.4';
  methods = {'linear','cubic','spline','pchip'};
  publication_open = false;
  publication_finalized = false;
  P = struct();

  config_path = arg_value(args,'--config','');
  if (isempty(config_path))
    error('%s: --config is required',module_id);
  endif
  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session = strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if (isempty(outdir)), error('%s: runtime.output_dir missing',module_id); endif
  if (isempty(session)), error('%s: runtime.session missing',module_id); endif
  if (exist(outdir,'dir') != 7), mkdir(outdir); endif

  gxtxt_progress_start('prepare','Preparing interpolation/resampling demonstration','indeterminate');

  try
    source_dataset_id = strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if (isempty(source_dataset_id))
      source_dataset_id = strtrim(gxtxt_ini_get(cfg,'dataset.id',''));
    endif
    if (isempty(source_dataset_id))
      error('%s: primary source Dataset ID is missing',module_id);
    endif

    x_binding = binding_column(gxtxt_ini_get(cfg,'bindings.x',''),'x');
    y_binding = binding_column(gxtxt_ini_get(cfg,'bindings.y',''),'y');
    if (isempty(x_binding) || isempty(y_binding))
      error('%s: X and Y variable bindings are required',module_id);
    endif

    [x_unit,~,x_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',x_binding);
    [y_unit,~,y_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',y_binding);
    if (!isfield(x_meta,'found') || !x_meta.found)
      error('%s: X binding could not be resolved: %s',module_id,x_binding);
    endif
    if (!isfield(y_meta,'found') || !y_meta.found)
      error('%s: Y binding could not be resolved: %s',module_id,y_binding);
    endif
    x_id = strtrim(x_meta.variable_id);
    y_id = strtrim(y_meta.variable_id);
    x_name = strtrim(x_meta.name);
    y_name = strtrim(y_meta.name);
    if (isempty(x_id) || isempty(y_id))
      error('%s: current framework runtime must expose stable variable IDs for the selected bindings',module_id);
    endif

    query_count = parse_query_count(gxtxt_ini_get(cfg,'config.query_point_count','201'));
    output_dataset_id = strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.interpolation.result'));
    if (isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once')))
      error('%s: Output Dataset ID may contain only letters, digits, ''.'', ''_'' and ''-''',module_id);
    endif
    if (strcmp(output_dataset_id,source_dataset_id))
      error('%s: Output Dataset ID must differ from the source Dataset ID',module_id);
    endif

    gxtxt_progress_stage('load_dataset','Reading canonical source variables','indeterminate');
    [x_source,y_source,source_provider] = read_source_xy(cfg,x_id,y_id);
    if (numel(x_source) < 3)
      error('%s: at least three source samples are required for cubic/spline/PCHIP interpolation',module_id);
    endif
    if (numel(x_source) != numel(y_source))
      error('%s: X/Y source length mismatch',module_id);
    endif
    if (any(!isfinite(x_source)) || any(!isfinite(y_source)))
      error('%s: source X/Y contains NaN or Inf; the canonical demo requires finite samples',module_id);
    endif
    dx = diff(x_source);
    if (any(dx <= 0))
      error('%s: source X must be strictly increasing for interpolation',module_id);
    endif

    numeric = discover_numeric_api(framework_root);
    gxtxt_progress_stage('numeric','Invoking NUMERIC_API_v1','indeterminate');

    grid = feval(numeric.function_name,'uniform_grid',x_source(1),x_source(end),query_count,struct('mode','count'));
    xq = double(grid.x(:));
    reference = sin(xq) + 0.1 .* xq;
    source_reference = sin(x_source) + 0.1 .* x_source;
    source_reference_max_abs_error = max(abs(y_source - source_reference));

    source_serialization_tolerance = source_reference_tolerance(source_reference);
    interpolation_identity_tolerance = 1.0e-10 * max(1.0,max(abs(y_source)));
    h_max = max(dx);
    linear_reference_bound = (h_max * h_max) / 8.0;
    dense_reference_tolerance = linear_reference_bound * (1.0 + 64.0 * eps(max(1.0,linear_reference_bound)));

    result = struct();
    all_pass = (source_reference_max_abs_error <= source_serialization_tolerance);
    for k = 1:numel(methods)
      method = methods{k};
      options = struct('method',method,'extrapolation','error');
      R = feval(numeric.function_name,'dataset_interpolate',session,source_dataset_id,x_id,y_id,xq,options);
      S = feval(numeric.function_name,'dataset_interpolate',session,source_dataset_id,x_id,y_id,x_source,options);
      yq = double(R.yq(:));
      ys = double(S.yq(:));
      err = yq - reference;
      identity_error = max(abs(ys - y_source));
      max_abs_error = max(abs(err));
      metric=feval(numeric.function_name,'residual_metrics',zeros(size(err)),err,struct());
      rmse=metric.rmse;mean_abs_error=metric.mae;
      pass_identity = (identity_error <= interpolation_identity_tolerance);
      if (strcmp(method,'linear'))
        pass_reference = (max_abs_error <= dense_reference_tolerance);
        reference_check = 'bounded';
      else
        % No arbitrary dense-grid pass/fail threshold is imposed on the
        % higher-order methods. Their analytical-reference errors are reported
        % as diagnostics, while the interpolation identity is validated.
        pass_reference = true;
        reference_check = 'diagnostic_only';
      endif
      pass_method = pass_identity && pass_reference;
      all_pass = all_pass && pass_method;
      result.(method) = struct('y',yq,'error',err,'identity_error',identity_error, ...
        'max_abs_error',max_abs_error,'rmse',rmse,'mean_abs_error',mean_abs_error, ...
        'pass_identity',pass_identity,'pass_reference',pass_reference, ...
        'reference_check',reference_check,'pass',pass_method);
    endfor

    % Exercise the public resampling facade independently of interpolation.
    % On the same explicit target grid, linear resampling and linear
    % interpolation share the documented contract and should agree to roundoff.
    RR = feval(numeric.function_name,'dataset_resample',session,source_dataset_id,x_id,y_id,xq, ...
      struct('method','linear','extrapolation','error'));
    linear_resample_consistency_max_abs_error = max(abs(double(RR.y(:)) - result.linear.y));
    linear_resample_consistency_tolerance = 64.0 * eps(max(1.0,max(abs(result.linear.y))));
    linear_resample_consistency_pass = ...
      (linear_resample_consistency_max_abs_error <= linear_resample_consistency_tolerance);
    all_pass = all_pass && linear_resample_consistency_pass;

    grid_info = feval(numeric.function_name,'dataset_grid_info',session,source_dataset_id,x_id,struct());

    gxtxt_progress_stage('publish','Publishing derived interpolation Dataset','determinate',numel(xq));
    popts = struct('storage','auto','replace_owned',true, ...
      'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}}, ...
      'source_variable_ids',{{x_id,y_id}}, ...
      'source','GX-TXT Numerical Examples / Interpolation', ...
      'provenance',sprintf('%s %s via NUMERIC_API_v1',module_id,module_version), ...
      'notes','Deterministic interpolation/resampling demonstration against y=sin(x)+0.1*x.');
    P = gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);
    publication_open = true;
    % A multivariable table must be published through sequential append so the
    % CSV provider can emit aligned rows.  The uniform x coordinate is implicit
    % in the public schema and is materialized automatically by the CSV provider.
    P = gxtxt_publication_v2_declare_dimension(P,'sample',0,true);
    P = gxtxt_publication_v2_declare_uniform(P,'x','sample',xq(1),grid.step, ...
      struct('name',x_name,'unit',x_unit,'dtype','float64','semantic_role','independent'));
    P = declare_series(P,'y_reference',y_name,'reference',y_unit);
    P = declare_series(P,'y_linear',[y_name ' - linear interpolation'],'derived',y_unit);
    P = declare_series(P,'error_linear','linear interpolation error','residual',y_unit);
    P = declare_series(P,'y_cubic',[y_name ' - cubic interpolation'],'derived',y_unit);
    P = declare_series(P,'error_cubic','cubic interpolation error','residual',y_unit);
    P = declare_series(P,'y_spline',[y_name ' - spline interpolation'],'derived',y_unit);
    P = declare_series(P,'error_spline','spline interpolation error','residual',y_unit);
    P = declare_series(P,'y_pchip',[y_name ' - PCHIP interpolation'],'derived',y_unit);
    P = declare_series(P,'error_pchip','PCHIP interpolation error','residual',y_unit);

    items = cell(1 + 2*numel(methods),2);
    items{1,1} = 'y_reference';
    items{1,2} = reference;
    item_index = 2;
    for k = 1:numel(methods)
      method = methods{k};
      items{item_index,1} = ['y_' method];
      items{item_index,2} = result.(method).y;
      item_index += 1;
      items{item_index,1} = ['error_' method];
      items{item_index,2} = result.(method).error;
      item_index += 1;
    endfor
    P = gxtxt_publication_v2_append(P,'sample',items);
    [P,pub_diag] = gxtxt_publication_v2_diagnostics(P);
    [P,pub_result] = gxtxt_publication_v2_finalize(P);
    publication_finalized = true;
    publication_open = false;

    write_metrics(fullfile(outdir,'interpolation_metrics.ini'),module_id,module_version, ...
      source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,source_provider, ...
      numeric,query_count,x_source,grid,grid_info,source_reference_max_abs_error, ...
      source_serialization_tolerance,interpolation_identity_tolerance,linear_reference_bound, ...
      dense_reference_tolerance,linear_resample_consistency_max_abs_error, ...
      linear_resample_consistency_tolerance,linear_resample_consistency_pass,result,all_pass,P.provider);
    write_report(fullfile(outdir,'interpolation_report.txt'),module_id,module_version, ...
      source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,numeric, ...
      query_count,x_source,grid_info,source_reference_max_abs_error,source_serialization_tolerance, ...
      interpolation_identity_tolerance,linear_reference_bound,dense_reference_tolerance, ...
      linear_resample_consistency_max_abs_error,linear_resample_consistency_tolerance, ...
      linear_resample_consistency_pass,result,all_pass,P.provider,pub_diag,pub_result);

    save(fullfile(outdir,'render_cache.mat'),'x_source','y_source','xq','reference','result', ...
      'x_name','y_name','x_unit','y_unit','linear_reference_bound','methods','output_dataset_id','source_dataset_id','x_id','y_id');

    if (!all_pass)
      error('%s: numerical validation failed; see interpolation_report.txt',module_id);
    endif

    demo_numeric_interpolation_render(outdir,output_dataset_id,source_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,cfg);

    gxtxt_progress_complete('done',sprintf('Published %s and rendered enabled graphs (%d query points)',output_dataset_id,numel(xq)));
    fprintf('[%s] version=%s source=%s output=%s methods=linear,cubic,spline,pchip points=%d validation=PASS provider=%s\n', ...
      module_id,module_version,source_dataset_id,output_dataset_id,numel(xq),P.provider);
  catch err
    if (publication_open && !publication_finalized)
      try P = gxtxt_publication_v2_abort(P); catch; end_try_catch
    endif
    try gxtxt_progress_fail('failed','Interpolation demonstration failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function P = declare_series(P,id,name,role,unit)
  P = gxtxt_publication_v2_declare_variable(P,id,struct( ...
    'dtype','float64','dimension_ids','sample','name',name,'unit',unit, ...
    'semantic_role',role,'coordinate_variable_ids','x'));
endfunction

function [x,y,provider] = read_source_xy(cfg,x_id,y_id)
  chunk_rows = 65536;
  S = gxtxt_table_stream_open_source(cfg,'primary',{x_id,y_id},chunk_rows, ...
    struct('start',0,'count',-1,'require_direct',false));
  provider = S.storage_provider;
  xc = {}; yc = {}; total = 0;
  unwind_protect
    while (!S.eof)
      [S,C] = gxtxt_table_stream_next(S);
      if (C.nrows < 1), continue; endif
      xc{end+1} = double(C.values{1}(:));
      yc{end+1} = double(C.values{2}(:));
      total += C.nrows;
    endwhile
  unwind_protect_cleanup
    S = gxtxt_table_stream_close(S);
  end_unwind_protect
  if (total < 1)
    x = zeros(0,1); y = zeros(0,1);
  else
    x = vertcat(xc{:}); y = vertcat(yc{:});
  endif
endfunction

function api = discover_numeric_api(framework_root)
  descriptor = fullfile(framework_root,'plugins','modules','math.numeric','module.ini');
  if (exist(descriptor,'file') != 2)
    error('demo.numeric.interpolation: required math.numeric module descriptor is missing');
  endif
  d = gxtxt_ini_read(descriptor);
  ids = split_list(gxtxt_ini_get(d,'public_apis.ids',''));
  if (!any(strcmp(ids,'NUMERIC_API_v1')))
    error('demo.numeric.interpolation: required public NUMERIC_API_v1 is not advertised by math.numeric');
  endif
  api_version = strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));
  if (!strcmp(api_version,'1'))
    error('demo.numeric.interpolation: unsupported NUMERIC_API_v1 version: %s',api_version);
  endif
  caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));
  if(!any(strcmp(caps,'residual_metrics'))),error('demo.numeric.interpolation: residual_metrics capability is unavailable');endif
  entry = strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));
  function_name = strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));
  if (isempty(entry) || isempty(function_name))
    error('demo.numeric.interpolation: math.numeric does not advertise a complete Octave NUMERIC_API_v1 binding');
  endif
  entry_path = fullfile(fileparts(descriptor),entry);
  if (exist(entry_path,'file') != 2)
    error('demo.numeric.interpolation: advertised NUMERIC_API_v1 Octave entrypoint is missing: %s',entry_path);
  endif
  addpath(fileparts(entry_path));
  if (exist(function_name,'file') != 2)
    error('demo.numeric.interpolation: advertised NUMERIC_API_v1 Octave function is unavailable: %s',function_name);
  endif
  api = struct('name','NUMERIC_API_v1','api_version',api_version,'function_name',function_name, ...
    'entrypoint',entry,'descriptor',descriptor);
endfunction

function tol = source_reference_tolerance(reference)
  % The canonical generator serializes values with Python format .12g.
  % Around this dataset's O(1) range, 5e-12 safely covers decimal quantization.
  tol = 5.0e-12 * max(1.0,max(abs(reference)));
endfunction

function n = parse_query_count(raw)
  n = str2double(strtrim(raw));
  if (!isfinite(n) || n != fix(n) || n < 3 || n > 100001)
    error('demo.numeric.interpolation: Uniform query point count must be an integer from 3 to 100001');
  endif
endfunction

function out = binding_column(value,role)
  value = strtrim(value);
  if (isempty(value) || strcmp(value,'auto')), out = ''; return; endif
  dot = find(value=='.',1);
  if (!isempty(dot)), out = value(dot+1:end); else out = value; endif
  if (isempty(out)), error('demo.numeric.interpolation: invalid %s binding',role); endif
endfunction

function value = arg_value(args,key,default)
  value = default;
  for i = 1:(numel(args)-1)
    if (strcmp(args{i},key)), value = args{i+1}; return; endif
  endfor
endfunction

function out = split_list(s)
  s = strrep(s,',',';');
  if (isempty(strtrim(s))), out = {}; return; endif
  out = strsplit(s,';');
  out = cellfun(@strtrim,out,'UniformOutput',false);
  out = out(!cellfun(@isempty,out));
endfunction

function write_metrics(path,module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,source_provider,numeric,query_count,x_source,grid,grid_info,source_reference_max_abs_error,source_serialization_tolerance,interpolation_identity_tolerance,linear_reference_bound,dense_reference_tolerance,linear_resample_consistency_max_abs_error,linear_resample_consistency_tolerance,linear_resample_consistency_pass,result,all_pass,output_provider)
  fid = fopen(path,'w'); if (fid < 0), error('%s: cannot write interpolation_metrics.ini',module_id); endif
  unwind_protect
    fprintf(fid,'; GX-TXT demo.numeric.interpolation metrics\n');
    fprintf(fid,'[module]\nid=%s\nversion=%s\nvalidation=%s\n',module_id,module_version,pass_text(all_pass));
    fprintf(fid,'\n[source]\ndataset_id=%s\nx_variable_id=%s\ny_variable_id=%s\nx_name=%s\ny_name=%s\nx_unit=%s\ny_unit=%s\nstorage_provider=%s\nsource_count=%d\nx_min=%.17g\nx_max=%.17g\nh_max=%.17g\nsource_grid_uniform=%d\n', ...
      source_dataset_id,x_id,y_id,ini_escape(x_name),ini_escape(y_name),ini_escape(x_unit),ini_escape(y_unit),source_provider,numel(x_source),x_source(1),x_source(end),max(diff(x_source)),logical_num(grid_info.uniform));
    fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n',numeric.name,numeric.api_version,numeric.function_name);
    fprintf(fid,'\n[output]\ndataset_id=%s\ncontract=table.generic\nstorage_provider=%s\nquery_point_count=%d\nquery_step=%.17g\nquery_start=%.17g\nquery_stop=%.17g\n', ...
      output_dataset_id,output_provider,query_count,grid.step,grid.x(1),grid.x(end));
    fprintf(fid,'\n[validation]\nreference_function=y=sin(x)+0.1*x\nsource_reference_max_abs_error=%.17g\nsource_serialization_tolerance=%.17g\ninterpolation_identity_tolerance=%.17g\nlinear_reference_bound=%.17g\ndense_reference_tolerance=%.17g\nlinear_resample_consistency_max_abs_error=%.17g\nlinear_resample_consistency_tolerance=%.17g\nlinear_resample_consistency_check=%s\n', ...
      source_reference_max_abs_error,source_serialization_tolerance,interpolation_identity_tolerance,linear_reference_bound,dense_reference_tolerance, ...
      linear_resample_consistency_max_abs_error,linear_resample_consistency_tolerance,pass_text(linear_resample_consistency_pass));
    methods = {'linear','cubic','spline','pchip'};
    for k = 1:numel(methods)
      m = methods{k}; R = result.(m);
      if (strcmp(R.reference_check,'bounded')), reference_status=pass_text(R.pass_reference); else reference_status='DIAGNOSTIC_ONLY'; endif
      fprintf(fid,'\n[method.%s]\nmax_abs_error=%.17g\nrmse=%.17g\nmean_abs_error=%.17g\nsource_point_max_abs_error=%.17g\nreference_check=%s\nsource_point_check=%s\nvalidation=%s\n', ...
        m,R.max_abs_error,R.rmse,R.mean_abs_error,R.identity_error,reference_status,pass_text(R.pass_identity),pass_text(R.pass));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,numeric,query_count,x_source,grid_info,source_reference_max_abs_error,source_serialization_tolerance,interpolation_identity_tolerance,linear_reference_bound,dense_reference_tolerance,linear_resample_consistency_max_abs_error,linear_resample_consistency_tolerance,linear_resample_consistency_pass,result,all_pass,output_provider,pub_diag,pub_result)
  fid = fopen(path,'w'); if (fid < 0), error('%s: cannot write interpolation_report.txt',module_id); endif
  unwind_protect
    fprintf(fid,'GX-TXT Numerical Interpolation Demo\n');
    fprintf(fid,'==================================\n\n');
    fprintf(fid,'Plugin: %s %s\n',module_id,module_version);
    fprintf(fid,'Source Dataset: %s\n',source_dataset_id);
    fprintf(fid,'Source X: %s [%s] (variable_id=%s)\n',x_name,x_unit,x_id);
    fprintf(fid,'Source Y: %s [%s] (variable_id=%s)\n',y_name,y_unit,y_id);
    fprintf(fid,'Source samples: %d; strictly increasing; uniform=%s\n',numel(x_source),bool_text(grid_info.uniform));
    fprintf(fid,'Reference: y = sin(x) + 0.1*x\n');
    fprintf(fid,'NUMERIC API: %s v%s (%s)\n',numeric.name,numeric.api_version,numeric.function_name);
    fprintf(fid,'Query grid: %d uniformly spaced points from %.17g to %.17g\n',query_count,x_source(1),x_source(end));
    fprintf(fid,'Output Dataset: %s (table.generic; provider=%s)\n\n',output_dataset_id,output_provider);
    fprintf(fid,'Validation basis\n----------------\n');
    fprintf(fid,'Source/reference max abs error: %.12g (tolerance %.12g)\n',source_reference_max_abs_error,source_serialization_tolerance);
    fprintf(fid,'Interpolation identity tolerance at source points: %.12g\n',interpolation_identity_tolerance);
    fprintf(fid,'Maximum source spacing h_max: %.12g\n',max(diff(x_source)));
    fprintf(fid,'Linear interpolation analytical bound h_max^2/8: %.12g\n',linear_reference_bound);
    fprintf(fid,'Dense-grid linear-reference acceptance envelope: %.12g\n',dense_reference_tolerance);
    fprintf(fid,'Linear resample/interpolate consistency: %.12g (tolerance %.12g) %s\n\n', ...
      linear_resample_consistency_max_abs_error,linear_resample_consistency_tolerance,pass_text(linear_resample_consistency_pass));
    fprintf(fid,'Method diagnostics\n------------------\n');
    methods = {'linear','cubic','spline','pchip'};
    for k = 1:numel(methods)
      m = methods{k}; R = result.(m);
      if (strcmp(R.reference_check,'bounded')), refnote=['reference=' pass_text(R.pass_reference)]; else refnote='reference=DIAGNOSTIC_ONLY'; endif
      fprintf(fid,'%-7s max_abs=%.12g  rmse=%.12g  mean_abs=%.12g  source_point_max_abs=%.12g  identity=%s  %s\n', ...
        m,R.max_abs_error,R.rmse,R.mean_abs_error,R.identity_error,pass_text(R.pass_identity),refnote);
    endfor
    fprintf(fid,'\nOverall validation: %s\n',pass_text(all_pass));
    fprintf(fid,'Publication diagnostics: %s\n',to_text(pub_diag));
    fprintf(fid,'Publication result: %s\n',to_text(pub_result));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function out = pass_text(v)
  if (v), out = 'PASS'; else out = 'FAIL'; endif
endfunction

function out = bool_text(v)
  if (v), out = 'yes'; else out = 'no'; endif
endfunction

function out = logical_num(v)
  if (v), out = 1; else out = 0; endif
endfunction

function out = ini_escape(v)
  out = strrep(strrep(char(v),sprintf('\n'),' '),sprintf('\r'),' ');
endfunction

function out = to_text(v)
  if (ischar(v)), out = v;
  elseif (isstring(v)), out = char(v);
  elseif (isnumeric(v) || islogical(v)), out = mat2str(v);
  else out = 'structured result';
  endif
endfunction
