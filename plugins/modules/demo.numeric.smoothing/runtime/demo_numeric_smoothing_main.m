function demo_numeric_smoothing_main(args, framework_root)
% Dataset-native smoothing demonstration using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id = 'demo.numeric.smoothing';
  module_version = '1.0.2';
  methods = {'moving_mean','moving_median','savitzky_golay','local_polynomial'};
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

  gxtxt_progress_start('prepare','Preparing numerical smoothing demonstration','indeterminate');

  try
    source_dataset_id = strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if (isempty(source_dataset_id))
      source_dataset_id = strtrim(gxtxt_ini_get(cfg,'dataset.id',''));
    endif
    if (isempty(source_dataset_id))
      error('%s: primary source Dataset ID is missing',module_id);
    endif

    x_binding = binding_column(gxtxt_ini_get(cfg,'bindings.x',''),'x');
    measured_binding = binding_column(gxtxt_ini_get(cfg,'bindings.measured',''),'measured');
    reference_binding = binding_column(gxtxt_ini_get(cfg,'bindings.reference',''),'reference');
    if (isempty(x_binding) || isempty(measured_binding) || isempty(reference_binding))
      error('%s: X, measured Y and reference Y bindings are required',module_id);
    endif

    [x_unit,~,x_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',x_binding);
    [measured_unit,~,measured_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',measured_binding);
    [reference_unit,~,reference_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',reference_binding);
    if (!meta_found(x_meta)), error('%s: X binding could not be resolved: %s',module_id,x_binding); endif
    if (!meta_found(measured_meta)), error('%s: measured Y binding could not be resolved: %s',module_id,measured_binding); endif
    if (!meta_found(reference_meta)), error('%s: reference Y binding could not be resolved: %s',module_id,reference_binding); endif

    x_id = strtrim(x_meta.variable_id);
    measured_id = strtrim(measured_meta.variable_id);
    reference_id = strtrim(reference_meta.variable_id);
    x_name = strtrim(x_meta.name);
    measured_name = strtrim(measured_meta.name);
    reference_name = strtrim(reference_meta.name);
    if (isempty(x_id) || isempty(measured_id) || isempty(reference_id))
      error('%s: current framework runtime must expose stable variable IDs for all selected bindings',module_id);
    endif
    if (strcmp(measured_id,reference_id))
      error('%s: measured Y and reference Y must be different Dataset variables',module_id);
    endif
    if (!isempty(strtrim(measured_unit)) && !isempty(strtrim(reference_unit)) && !strcmp(strtrim(measured_unit),strtrim(reference_unit)))
      error('%s: measured and reference variables have incompatible units (%s vs %s)',module_id,measured_unit,reference_unit);
    endif

    output_dataset_id = strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.smoothing.result'));
    if (isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once')))
      error('%s: Output Dataset ID may contain only letters, digits, ''.'', ''_'' and ''-''',module_id);
    endif
    if (strcmp(output_dataset_id,source_dataset_id))
      error('%s: Output Dataset ID must differ from the source Dataset ID',module_id);
    endif

    params = read_parameters(cfg,module_id);

    gxtxt_progress_stage('load_dataset','Reading source X, measured Y and reference Y','indeterminate');
    [x,measured,reference,source_provider] = read_source_series(cfg,x_id,measured_id,reference_id);
    n = numel(x);
    if (n < 5), error('%s: at least five samples are required',module_id); endif
    if (numel(measured) != n || numel(reference) != n)
      error('%s: source variable lengths differ',module_id);
    endif
    if (any(!isfinite(x)) || any(!isfinite(measured)) || any(!isfinite(reference)))
      error('%s: the smoothing demo requires finite X, measured and reference values',module_id);
    endif
    if (any(diff(x) <= 0))
      error('%s: X must be strictly increasing',module_id);
    endif
    validate_windows_against_length(params,n,module_id);

    numeric = discover_numeric_api(framework_root,module_id);
    gxtxt_progress_stage('numeric','Invoking NUMERIC_API_v1 smoothing methods','determinate',numel(methods));

    grid_info = feval(numeric.function_name,'dataset_grid_info',session,source_dataset_id,x_id,struct());
    if (!grid_info.uniform)
      error('%s: Savitzky-Golay demonstration requires a uniform X grid; the selected X variable is non-uniform',module_id);
    endif

    measured_error = measured - reference;
    measured_metrics = error_metrics(measured_error,0,numeric.function_name);
    x_tolerance = 64.0 * eps(max(1.0,max(abs(x))));
    result = struct();
    all_pass = true;

    for k = 1:numel(methods)
      method = methods{k};
      opts = method_options(method,params);
      R = feval(numeric.function_name,'dataset_smooth',session,source_dataset_id,x_id,measured_id,opts);
      sx = double(R.x(:)); sy = double(R.y(:));
      expected_window = opts.window;
      expected_degree = NaN; if (isfield(opts,'degree')), expected_degree = opts.degree; endif
      length_pass = (numel(sx) == n && numel(sy) == n);
      if (length_pass), x_shift = max(abs(sx - x)); else x_shift = Inf; endif
      x_pass = length_pass && (x_shift <= x_tolerance);
      finite_pass = length_pass && all(isfinite(sy));
      method_pass = isfield(R,'method') && strcmp(strtrim(R.method),method);
      window_pass = isfield(R,'window') && double(R.window) == expected_window;
      if (isnan(expected_degree))
        degree_pass = true;
      else
        degree_pass = isfield(R,'degree') && double(R.degree) == expected_degree;
      endif
      endpoint_policy = ''; if (isfield(R,'endpoint_policy')), endpoint_policy = strtrim(R.endpoint_policy); endif
      endpoint_pass = !isempty(endpoint_policy);
      pass = length_pass && x_pass && finite_pass && method_pass && window_pass && degree_pass && endpoint_pass;
      all_pass = all_pass && pass;
      if (!length_pass)
        err = NaN(n,1);
      else
        err = sy - reference;
      endif
      edge_count = floor((expected_window - 1) / 2);
      M = error_metrics(err,edge_count,numeric.function_name);
      result.(method) = struct('x',sx,'y',sy,'error',err,'window',expected_window, ...
        'degree',expected_degree,'endpoint_policy',endpoint_policy,'x_shift_max_abs',x_shift, ...
        'metrics',M,'length_pass',length_pass,'x_pass',x_pass,'finite_pass',finite_pass, ...
        'method_pass',method_pass,'window_pass',window_pass,'degree_pass',degree_pass, ...
        'endpoint_pass',endpoint_pass,'pass',pass);
      gxtxt_progress_update(k,numel(methods),'numeric',sprintf('Completed %s smoothing',method));
    endfor

    if (!all_pass)
      write_prepublication_failure(fullfile(outdir,'smoothing_report.txt'),module_id,module_version,source_dataset_id,result);
      error('%s: numerical API contract validation failed; see smoothing_report.txt',module_id);
    endif

    % Publication begins only after numerical/API validation has passed, so a
    % failed smoothing run cannot leave a derived Dataset behind.
    gxtxt_progress_stage('publish','Publishing derived smoothing comparison Dataset','determinate',n);
    popts = struct('storage','auto','replace_owned',true, ...
      'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}}, ...
      'source_variable_ids',{{x_id,measured_id,reference_id}}, ...
      'source',source_dataset_id, ...
      'provenance',provenance_text(module_id,module_version,params), ...
      'notes','Comparison of public NUMERIC_API_v1 smoothing methods against a bound reference variable.');
    P = gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);
    publication_open = true;
    P = gxtxt_publication_v2_declare_dimension(P,'sample',0,true);
    P = declare_series(P,'x','x','independent',x_unit,'');
    P = declare_series(P,'reference','reference','reference',reference_unit,'x');
    P = declare_series(P,'measured','measured','measured',measured_unit,'x');
    for k = 1:numel(methods)
      method = methods{k}; label = method_label(method);
      P = declare_series(P,['smooth_' method],['smooth_' method],'derived',measured_unit,'x');
      P = declare_series(P,['error_' method],['error_' method],'residual',measured_unit,'x');
    endfor

    items = cell(3 + 2*numel(methods),2);
    items{1,1}='x'; items{1,2}=x;
    items{2,1}='reference'; items{2,2}=reference;
    items{3,1}='measured'; items{3,2}=measured;
    idx=4;
    for k=1:numel(methods)
      method=methods{k};
      items{idx,1}=['smooth_' method]; items{idx,2}=result.(method).y; idx+=1;
      items{idx,1}=['error_' method]; items{idx,2}=result.(method).error; idx+=1;
    endfor
    P = gxtxt_publication_v2_append(P,'sample',items);
    [P,pub_diag] = gxtxt_publication_v2_diagnostics(P);
    [P,pub_result] = gxtxt_publication_v2_finalize(P);
    publication_finalized = true;
    publication_open = false;

    write_metrics(fullfile(outdir,'smoothing_metrics.ini'),module_id,module_version, ...
      source_dataset_id,output_dataset_id,x_id,measured_id,reference_id,x_name,measured_name,reference_name, ...
      x_unit,measured_unit,reference_unit,source_provider,numeric,params,grid_info,measured_metrics,result,true,P.provider,n);
    write_report(fullfile(outdir,'smoothing_report.txt'),module_id,module_version, ...
      source_dataset_id,output_dataset_id,x_id,measured_id,reference_id,x_name,measured_name,reference_name, ...
      x_unit,measured_unit,reference_unit,numeric,params,grid_info,measured_metrics,result,true,P.provider,pub_diag,pub_result,n);

    save(fullfile(outdir,'render_cache.mat'),'x_name','measured_name','reference_name', ...
      'x_unit','measured_unit','reference_unit','params','methods','output_dataset_id');

    demo_numeric_smoothing_render(outdir,output_dataset_id,x_name,measured_name,reference_name, ...
      x_unit,measured_unit,reference_unit,cfg);

    gxtxt_progress_complete('done',sprintf('Published %s and rendered enabled smoothing graphs (%d samples)',output_dataset_id,n));
    fprintf('[%s] version=%s source=%s output=%s methods=moving_mean,moving_median,savitzky_golay,local_polynomial samples=%d validation=PASS provider=%s\n', ...
      module_id,module_version,source_dataset_id,output_dataset_id,n,P.provider);
  catch err
    if (publication_open && !publication_finalized)
      try P = gxtxt_publication_v2_abort(P); catch; end_try_catch
    endif
    try gxtxt_progress_fail('failed','Smoothing demonstration failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function tf = meta_found(meta)
  tf = isstruct(meta) && isfield(meta,'found') && meta.found;
endfunction

function params = read_parameters(cfg,module_id)
  params = struct();
  params.moving_mean_window = parse_odd_window(gxtxt_ini_get(cfg,'config.moving_mean_window','15'),'Moving mean window',module_id);
  params.moving_median_window = parse_odd_window(gxtxt_ini_get(cfg,'config.moving_median_window','15'),'Moving median window',module_id);
  params.savgol_window = parse_odd_window(gxtxt_ini_get(cfg,'config.savgol_window','15'),'Savitzky-Golay window',module_id);
  params.savgol_degree = parse_degree(gxtxt_ini_get(cfg,'config.savgol_degree','3'),'Savitzky-Golay degree',module_id);
  params.local_polynomial_window = parse_odd_window(gxtxt_ini_get(cfg,'config.local_polynomial_window','15'),'Local-polynomial window',module_id);
  params.local_polynomial_degree = parse_degree(gxtxt_ini_get(cfg,'config.local_polynomial_degree','2'),'Local-polynomial degree',module_id);
  if (params.savgol_degree >= params.savgol_window)
    error('%s: Savitzky-Golay degree must be smaller than its window',module_id);
  endif
  if (params.local_polynomial_degree >= params.local_polynomial_window)
    error('%s: Local-polynomial degree must be smaller than its window',module_id);
  endif
endfunction

function v = parse_odd_window(raw,label,module_id)
  v = str2double(strtrim(raw));
  if (!isfinite(v) || v != fix(v) || v < 3 || mod(v,2)==0 || v > 100001)
    error('%s: %s must be an odd integer from 3 to 100001 samples',module_id,label);
  endif
endfunction

function v = parse_degree(raw,label,module_id)
  v = str2double(strtrim(raw));
  if (!isfinite(v) || v != fix(v) || v < 0 || v > 1000)
    error('%s: %s must be a non-negative integer',module_id,label);
  endif
endfunction

function validate_windows_against_length(params,n,module_id)
  fields={'moving_mean_window','moving_median_window','savgol_window','local_polynomial_window'};
  for k=1:numel(fields)
    f=fields{k}; if (params.(f) > n), error('%s: %s (%d) exceeds Dataset length (%d)',module_id,f,params.(f),n); endif
  endfor
endfunction

function opts = method_options(method,params)
  if (strcmp(method,'moving_mean'))
    opts=struct('method',method,'window',params.moving_mean_window);
  elseif (strcmp(method,'moving_median'))
    opts=struct('method',method,'window',params.moving_median_window);
  elseif (strcmp(method,'savitzky_golay'))
    opts=struct('method',method,'window',params.savgol_window,'degree',params.savgol_degree);
  elseif (strcmp(method,'local_polynomial'))
    opts=struct('method',method,'window',params.local_polynomial_window,'degree',params.local_polynomial_degree);
  else
    error('demo.numeric.smoothing: unsupported configured method: %s',method);
  endif
endfunction

function M = error_metrics(err,edge_count,numeric_fn)
  err=double(err(:)); n=numel(err);
  M=struct('rmse',NaN,'mae',NaN,'max_abs',NaN,'edge_rmse',NaN,'interior_rmse',NaN,'edge_count',edge_count);
  if (n<1 || any(!isfinite(err))), return; endif
  metrics=feval(numeric_fn,'residual_metrics',zeros(size(err)),err,struct());
  M.rmse=metrics.rmse;M.mae=metrics.mae;M.max_abs=metrics.max_abs_error;
  if (edge_count > 0 && 2*edge_count < n)
    edge_err=[err(1:edge_count);err((n-edge_count+1):n)];
    interior_err=err((edge_count+1):(n-edge_count));
    edge_metrics=feval(numeric_fn,'residual_metrics',zeros(size(edge_err)),edge_err,struct());
    interior_metrics=feval(numeric_fn,'residual_metrics',zeros(size(interior_err)),interior_err,struct());
    M.edge_rmse=edge_metrics.rmse;M.interior_rmse=interior_metrics.rmse;
  else
    M.interior_rmse=M.rmse;
  endif
endfunction

function P = declare_series(P,id,name,role,unit,coordinate_id)
  spec=struct('dtype','float64','dimension_ids','sample','name',name,'unit',unit,'semantic_role',role,'axis_kind','explicit');
  if (isempty(coordinate_id))
    spec.coordinate_role='coordinate';
  else
    spec.coordinate_role='data'; spec.coordinate_variable_ids=coordinate_id;
  endif
  P = gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction

function [x,measured,reference,provider] = read_source_series(cfg,x_id,measured_id,reference_id)
  S = gxtxt_table_stream_open_source(cfg,'primary',{x_id,measured_id,reference_id},65536, ...
    struct('start',0,'count',-1,'require_direct',false));
  provider=S.storage_provider; xc={}; mc={}; rc={}; total=0;
  unwind_protect
    while (!S.eof)
      [S,C]=gxtxt_table_stream_next(S); if (C.nrows<1), continue; endif
      xc{end+1}=double(C.values{1}(:)); mc{end+1}=double(C.values{2}(:)); rc{end+1}=double(C.values{3}(:)); total+=C.nrows;
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if (total<1), x=zeros(0,1); measured=zeros(0,1); reference=zeros(0,1);
  else x=vertcat(xc{:}); measured=vertcat(mc{:}); reference=vertcat(rc{:}); endif
endfunction

function api = discover_numeric_api(framework_root,module_id)
  descriptor=fullfile(framework_root,'plugins','modules','math.numeric','module.ini');
  if (exist(descriptor,'file')!=2), error('%s: required math.numeric module descriptor is missing',module_id); endif
  d=gxtxt_ini_read(descriptor); ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));
  if (!any(strcmp(ids,'NUMERIC_API_v1'))), error('%s: required public NUMERIC_API_v1 is not advertised by math.numeric',module_id); endif
  api_version=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));
  if (!strcmp(api_version,'1')), error('%s: unsupported NUMERIC_API_v1 version: %s',module_id,api_version); endif
  capabilities=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));
  required={'smoothing','moving_average','moving_median','savitzky_golay','local_polynomial_smoothing','dataset_smoothing','grid_analysis','residual_metrics'};
  for k=1:numel(required)
    if (!any(strcmp(capabilities,required{k}))), error('%s: NUMERIC_API_v1 capability is missing: %s',module_id,required{k}); endif
  endfor
  entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));
  function_name=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));
  if (isempty(entry)||isempty(function_name)), error('%s: math.numeric does not advertise a complete Octave NUMERIC_API_v1 binding',module_id); endif
  entry_path=fullfile(fileparts(descriptor),entry);
  if (exist(entry_path,'file')!=2), error('%s: advertised NUMERIC_API_v1 Octave entrypoint is missing: %s',module_id,entry_path); endif
  addpath(fileparts(entry_path));
  if (exist(function_name,'file')!=2), error('%s: advertised NUMERIC_API_v1 Octave function is unavailable: %s',module_id,function_name); endif
  api=struct('name','NUMERIC_API_v1','api_version',api_version,'function_name',function_name,'entrypoint',entry,'descriptor',descriptor);
endfunction

function out = binding_column(value,role)
  value=strtrim(value); if (isempty(value)||strcmp(value,'auto')), out=''; return; endif
  dot=find(value=='.',1); if (!isempty(dot)), out=value(dot+1:end); else out=value; endif
  if (isempty(out)), error('demo.numeric.smoothing: invalid %s binding',role); endif
endfunction

function value = arg_value(args,key,default)
  value=default; for i=1:(numel(args)-1), if (strcmp(args{i},key)), value=args{i+1}; return; endif; endfor
endfunction

function out = split_list(s)
  s=strrep(s,',',';'); if (isempty(strtrim(s))), out={}; return; endif
  out=strsplit(s,';'); out=cellfun(@strtrim,out,'UniformOutput',false); out=out(!cellfun(@isempty,out));
endfunction

function s = provenance_text(module_id,module_version,params)
  s=sprintf('%s %s via NUMERIC_API_v1; moving_mean_window=%d; moving_median_window=%d; savgol_window=%d; savgol_degree=%d; local_polynomial_window=%d; local_polynomial_degree=%d', ...
    module_id,module_version,params.moving_mean_window,params.moving_median_window,params.savgol_window,params.savgol_degree,params.local_polynomial_window,params.local_polynomial_degree);
endfunction

function label = method_label(method)
  if (strcmp(method,'moving_mean')), label='Moving mean';
  elseif (strcmp(method,'moving_median')), label='Moving median';
  elseif (strcmp(method,'savitzky_golay')), label='Savitzky-Golay';
  elseif (strcmp(method,'local_polynomial')), label='Local polynomial';
  else label=method; endif
endfunction

function write_prepublication_failure(path,module_id,module_version,source_dataset_id,result)
  fid=fopen(path,'w'); if(fid<0),return;endif
  unwind_protect
    fprintf(fid,'GX-TXT Numerical Smoothing Demo\n================================\n\n');
    fprintf(fid,'Plugin: %s %s\nSource Dataset: %s\n\n',module_id,module_version,source_dataset_id);
    fprintf(fid,'Numerical/API contract validation failed before Dataset publication.\n');
    methods=fieldnames(result); for k=1:numel(methods),m=methods{k};R=result.(m);fprintf(fid,'%s: validation=%s endpoint_policy=%s x_shift_max_abs=%.12g\n',m,pass_text(R.pass),R.endpoint_policy,R.x_shift_max_abs);endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_metrics(path,module_id,module_version,source_dataset_id,output_dataset_id,x_id,measured_id,reference_id,x_name,measured_name,reference_name,x_unit,measured_unit,reference_unit,source_provider,numeric,params,grid_info,measured_metrics,result,all_pass,output_provider,n)
  fid=fopen(path,'w'); if(fid<0),error('%s: cannot write smoothing_metrics.ini',module_id);endif
  unwind_protect
    fprintf(fid,'; GX-TXT demo.numeric.smoothing metrics\n');
    fprintf(fid,'[module]\nid=%s\nversion=%s\nvalidation=%s\n',module_id,module_version,pass_text(all_pass));
    fprintf(fid,'\n[source]\ndataset_id=%s\nx_variable_id=%s\nmeasured_variable_id=%s\nreference_variable_id=%s\nx_name=%s\nmeasured_name=%s\nreference_name=%s\nx_unit=%s\nmeasured_unit=%s\nreference_unit=%s\nstorage_provider=%s\nsample_count=%d\ngrid_uniform=%d\ngrid_step=%.17g\n', ...
      source_dataset_id,x_id,measured_id,reference_id,ini_escape(x_name),ini_escape(measured_name),ini_escape(reference_name),ini_escape(x_unit),ini_escape(measured_unit),ini_escape(reference_unit),source_provider,n,logical_num(grid_info.uniform),grid_info.step);
    fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n',numeric.name,numeric.api_version,numeric.function_name);
    fprintf(fid,'\n[parameters]\nmoving_mean_window=%d\nmoving_median_window=%d\nsavgol_window=%d\nsavgol_degree=%d\nlocal_polynomial_window=%d\nlocal_polynomial_degree=%d\n', ...
      params.moving_mean_window,params.moving_median_window,params.savgol_window,params.savgol_degree,params.local_polynomial_window,params.local_polynomial_degree);
    fprintf(fid,'\n[measured]\nrmse=%.17g\nmae=%.17g\nmax_abs_error=%.17g\n',measured_metrics.rmse,measured_metrics.mae,measured_metrics.max_abs);
    methods={'moving_mean','moving_median','savitzky_golay','local_polynomial'};
    for k=1:numel(methods)
      m=methods{k};R=result.(m);M=R.metrics;
      fprintf(fid,'\n[method.%s]\nwindow=%d\ndegree=%s\nendpoint_policy=%s\nrmse=%.17g\nmae=%.17g\nmax_abs_error=%.17g\nedge_count=%d\nedge_rmse=%.17g\ninterior_rmse=%.17g\nx_shift_max_abs=%.17g\nvalidation=%s\n', ...
        m,R.window,degree_text(R.degree),R.endpoint_policy,M.rmse,M.mae,M.max_abs,M.edge_count,M.edge_rmse,M.interior_rmse,R.x_shift_max_abs,pass_text(R.pass));
    endfor
    fprintf(fid,'\n[output]\ndataset_id=%s\ncontract=table.generic\nstorage_provider=%s\n',output_dataset_id,output_provider);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,module_id,module_version,source_dataset_id,output_dataset_id,x_id,measured_id,reference_id,x_name,measured_name,reference_name,x_unit,measured_unit,reference_unit,numeric,params,grid_info,measured_metrics,result,all_pass,output_provider,pub_diag,pub_result,n)
  fid=fopen(path,'w'); if(fid<0),error('%s: cannot write smoothing_report.txt',module_id);endif
  unwind_protect
    fprintf(fid,'GX-TXT Numerical Smoothing Demo\n================================\n\n');
    fprintf(fid,'Plugin: %s %s\n',module_id,module_version);
    fprintf(fid,'Source Dataset: %s\n',source_dataset_id);
    fprintf(fid,'X: %s [%s] (variable_id=%s)\n',x_name,x_unit,x_id);
    fprintf(fid,'Measured Y: %s [%s] (variable_id=%s)\n',measured_name,measured_unit,measured_id);
    fprintf(fid,'Reference Y: %s [%s] (variable_id=%s)\n',reference_name,reference_unit,reference_id);
    fprintf(fid,'Samples: %d; uniform X=%s; step=%.12g\n',n,bool_text(grid_info.uniform),grid_info.step);
    fprintf(fid,'NUMERIC API: %s v%s (%s)\n',numeric.name,numeric.api_version,numeric.function_name);
    fprintf(fid,'Output Dataset: %s (table.generic; provider=%s)\n\n',output_dataset_id,output_provider);
    fprintf(fid,'Configured parameters\n---------------------\n');
    fprintf(fid,'Moving mean window: %d\n',params.moving_mean_window);
    fprintf(fid,'Moving median window: %d\n',params.moving_median_window);
    fprintf(fid,'Savitzky-Golay: window=%d degree=%d\n',params.savgol_window,params.savgol_degree);
    fprintf(fid,'Local polynomial: window=%d degree=%d\n\n',params.local_polynomial_window,params.local_polynomial_degree);
    fprintf(fid,'Reference-error diagnostics\n---------------------------\n');
    fprintf(fid,'Measured/noisy: rmse=%.12g  mae=%.12g  max_abs=%.12g\n',measured_metrics.rmse,measured_metrics.mae,measured_metrics.max_abs);
    methods={'moving_mean','moving_median','savitzky_golay','local_polynomial'};
    for k=1:numel(methods)
      m=methods{k};R=result.(m);M=R.metrics;
      fprintf(fid,'%-19s rmse=%.12g  mae=%.12g  max_abs=%.12g  edge_rmse=%.12g  interior_rmse=%.12g\n', ...
        method_label(m),M.rmse,M.mae,M.max_abs,M.edge_rmse,M.interior_rmse);
      fprintf(fid,'  window=%d degree=%s endpoint=%s x_shift_max_abs=%.12g validation=%s\n', ...
        R.window,degree_text(R.degree),R.endpoint_policy,R.x_shift_max_abs,pass_text(R.pass));
    endfor
    fprintf(fid,'\nOverall API/structure validation: %s\n',pass_text(all_pass));
    fprintf(fid,'No method is ranked as universally best; the metrics describe behavior for this Dataset and parameter set.\n');
    fprintf(fid,'Publication diagnostics: %s\n',to_text(pub_diag));
    fprintf(fid,'Publication result: %s\n',to_text(pub_result));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function out = degree_text(v)
  if (isnan(v)), out='not_applicable'; else out=sprintf('%d',v); endif
endfunction
function out = pass_text(v), if(v),out='PASS';else out='FAIL';endif,endfunction
function out = bool_text(v), if(v),out='yes';else out='no';endif,endfunction
function out = logical_num(v), if(v),out=1;else out=0;endif,endfunction
function out = ini_escape(v), out=strrep(strrep(char(v),sprintf('\n'),' '),sprintf('\r'),' '); endfunction
function out = to_text(v)
  if (ischar(v)),out=v; elseif (isnumeric(v)||islogical(v)),out=mat2str(v); else out='structured result'; endif
endfunction
