function demo_numeric_calculus_main(args, framework_root)
% Dataset-native calculus demonstration using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id = 'demo.numeric.calculus';
  module_version = '1.0.1';
  publication_open = false;
  publication_finalized = false;
  P = struct();

  config_path = arg_value(args,'--config','');
  if (isempty(config_path)), error('%s: --config is required',module_id); endif
  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session = strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if (isempty(outdir)), error('%s: runtime.output_dir missing',module_id); endif
  if (isempty(session)), error('%s: runtime.session missing',module_id); endif
  if (exist(outdir,'dir') != 7), mkdir(outdir); endif

  gxtxt_progress_start('prepare','Preparing numerical calculus demonstration','indeterminate');

  try
    source_dataset_id = strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if (isempty(source_dataset_id)), source_dataset_id = strtrim(gxtxt_ini_get(cfg,'dataset.id','')); endif
    if (isempty(source_dataset_id)), error('%s: primary source Dataset ID is missing',module_id); endif

    x_binding = binding_column(gxtxt_ini_get(cfg,'bindings.x',''),'x');
    function_binding = binding_column(gxtxt_ini_get(cfg,'bindings.function',''),'function');
    derivative_binding = binding_column(gxtxt_ini_get(cfg,'bindings.derivative_reference',''),'derivative_reference');
    antiderivative_binding = binding_column(gxtxt_ini_get(cfg,'bindings.antiderivative_reference',''),'antiderivative_reference');
    if (isempty(x_binding) || isempty(function_binding) || isempty(derivative_binding) || isempty(antiderivative_binding))
      error('%s: X, function, exact derivative and exact antiderivative bindings are required',module_id);
    endif

    [x_unit,~,x_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',x_binding);
    [function_unit,~,function_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',function_binding);
    [derivative_reference_unit,~,derivative_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',derivative_binding);
    [antiderivative_reference_unit,~,antiderivative_meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',antiderivative_binding);
    if (!meta_found(x_meta)), error('%s: X binding could not be resolved: %s',module_id,x_binding); endif
    if (!meta_found(function_meta)), error('%s: function binding could not be resolved: %s',module_id,function_binding); endif
    if (!meta_found(derivative_meta)), error('%s: exact derivative binding could not be resolved: %s',module_id,derivative_binding); endif
    if (!meta_found(antiderivative_meta)), error('%s: exact antiderivative binding could not be resolved: %s',module_id,antiderivative_binding); endif

    x_id = strtrim(x_meta.variable_id);
    function_id = strtrim(function_meta.variable_id);
    derivative_reference_id = strtrim(derivative_meta.variable_id);
    antiderivative_reference_id = strtrim(antiderivative_meta.variable_id);
    x_name = strtrim(x_meta.name);
    function_name = strtrim(function_meta.name);
    derivative_name = strtrim(derivative_meta.name);
    integral_name = strtrim(antiderivative_meta.name);
    if (isempty(x_id) || isempty(function_id) || isempty(derivative_reference_id) || isempty(antiderivative_reference_id))
      error('%s: current framework runtime must expose stable variable IDs for all selected bindings',module_id);
    endif
    ids={x_id,function_id,derivative_reference_id,antiderivative_reference_id};
    if (numel(unique(ids)) != numel(ids)), error('%s: all four bindings must resolve to different Dataset variables',module_id); endif

    output_dataset_id = strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.calculus.result'));
    if (isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once')))
      error('%s: Output Dataset ID may contain only letters, digits, ''.'', ''_'' and ''-''',module_id);
    endif
    if (strcmp(output_dataset_id,source_dataset_id))
      error('%s: Output Dataset ID must differ from the source Dataset ID',module_id);
    endif

    selection=struct('enabled',false);
    try selection=gxtxt_selection_from_runtime(cfg,'selection'); catch selerr
      error('%s: invalid Dataset Selection: %s',module_id,selerr.message);
    end_try_catch
    if (selection.enabled), validate_selection(selection,source_dataset_id,x_id,module_id); endif

    gxtxt_progress_stage('load_dataset','Reading source function and analytical references','indeterminate');
    [x,f,derivative_reference,antiderivative_reference,source_provider] = read_source_series(cfg,x_id,function_id,derivative_reference_id,antiderivative_reference_id,selection);
    n=numel(x);
    if (n < 2), error('%s: at least two selected samples are required',module_id); endif
    if (numel(f)!=n || numel(derivative_reference)!=n || numel(antiderivative_reference)!=n)
      error('%s: selected source variable lengths differ',module_id);
    endif
    if (any(!isfinite(x)) || any(!isfinite(f)) || any(!isfinite(derivative_reference)) || any(!isfinite(antiderivative_reference)))
      error('%s: calculus demonstration requires finite X, function and reference values',module_id);
    endif
    if (any(diff(x)<=0)), error('%s: X must be strictly increasing',module_id); endif

    numeric=discover_numeric_api(framework_root,module_id);
    opts=struct(); if(selection.enabled),opts.selection=selection;endif
    gxtxt_progress_stage('numeric','Invoking NUMERIC_API_v1 calculus operations','determinate',4);
    grid_info=feval(numeric.function_name,'dataset_grid_info',session,source_dataset_id,x_id,opts);gxtxt_progress_update(1,4,'numeric','Grid analysis complete');
    derivative_result=feval(numeric.function_name,'dataset_differentiate',session,source_dataset_id,x_id,function_id,opts);gxtxt_progress_update(2,4,'numeric','Numerical differentiation complete');
    definite_result=feval(numeric.function_name,'dataset_integrate',session,source_dataset_id,x_id,function_id,opts);gxtxt_progress_update(3,4,'numeric','Definite integration complete');
    cumulative_result=feval(numeric.function_name,'dataset_cumulative_integrate',session,source_dataset_id,x_id,function_id,opts);gxtxt_progress_update(4,4,'numeric','Cumulative integration complete');

    derivative_numeric=double(derivative_result.dy_dx(:));
    cumulative_x=double(cumulative_result.x(:));
    derivative_x=double(derivative_result.x(:));
    integral_numeric=double(cumulative_result.integral(:));
    definite_numeric=double(definite_result.value);
    x_tol=64.0*eps(max(1.0,max(abs(x))));
    structure_pass=(numel(derivative_numeric)==n && numel(integral_numeric)==n && numel(derivative_x)==n && numel(cumulative_x)==n);
    if (structure_pass)
      structure_pass=structure_pass && max(abs(derivative_x-x))<=x_tol && max(abs(cumulative_x-x))<=x_tol;
    endif
    structure_pass=structure_pass && all(isfinite(derivative_numeric)) && all(isfinite(integral_numeric)) && isfinite(definite_numeric);
    structure_pass=structure_pass && grid_info.n==n && derivative_result.n==n && definite_result.n==n && cumulative_result.n==n;
    structure_pass=structure_pass && isfield(derivative_result,'method') && !isempty(strtrim(derivative_result.method));
    structure_pass=structure_pass && isfield(definite_result,'method') && !isempty(strtrim(definite_result.method));
    structure_pass=structure_pass && isfield(cumulative_result,'method') && !isempty(strtrim(cumulative_result.method));
    if (!structure_pass)
      write_prepublication_failure(fullfile(outdir,'calculus_report.txt'),module_id,module_version,source_dataset_id,'NUMERIC_API_v1 returned inconsistent calculus output structure or alignment.');
      error('%s: numerical API contract validation failed; see calculus_report.txt',module_id);
    endif

    derivative_exact=double(derivative_reference(:));
    integral_exact=double(antiderivative_reference(:)-antiderivative_reference(1));
    derivative_error=derivative_numeric-derivative_exact;
    integral_error=integral_numeric-integral_exact;
    absolute_derivative_error=abs(derivative_error);
    absolute_integral_error=abs(integral_error);
    derivative_metrics=error_metrics(derivative_error,true,numeric.function_name);
    integral_metrics=error_metrics(integral_error,false,numeric.function_name);
    exact_definite=double(antiderivative_reference(end)-antiderivative_reference(1));
    definite_error=definite_numeric-exact_definite;

    derivative_unit=resolved_result_unit(derivative_result,derivative_reference_unit,module_id,'derivative');
    integral_unit=resolved_result_unit(cumulative_result,antiderivative_reference_unit,module_id,'integral');
    if (isfield(definite_result,'result_unit') && !isempty(strtrim(definite_result.result_unit)) && !isempty(integral_unit) && !strcmp(strtrim(definite_result.result_unit),integral_unit))
      error('%s: definite and cumulative integration result units disagree (%s vs %s)',module_id,strtrim(definite_result.result_unit),integral_unit);
    endif

    gxtxt_progress_stage('publish','Publishing derived calculus comparison Dataset','determinate',n);
    source_ids={x_id,function_id,derivative_reference_id,antiderivative_reference_id};
    selection_id='';if(selection.enabled),selection_id=selection.id;endif
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_ids},'source',source_dataset_id, ...
      'provenance',provenance_text(module_id,module_version,derivative_result,definite_result,cumulative_result,selection_id), ...
      'notes','Public NUMERIC_API_v1 calculus comparison against bound analytical derivative and antiderivative reference variables.');
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'sample',0,true);
    P=declare_series(P,'x','x','independent',x_unit,'');
    P=declare_series(P,'function','function','measured',function_unit,'x');
    P=declare_series(P,'derivative_exact','derivative_exact','reference',derivative_unit,'x');
    P=declare_series(P,'derivative_numeric','derivative_numeric','derived',derivative_unit,'x');
    P=declare_series(P,'derivative_error','derivative_error','residual',derivative_unit,'x');
    P=declare_series(P,'absolute_derivative_error','absolute_derivative_error','residual',derivative_unit,'x');
    P=declare_series(P,'integral_exact','integral_exact','reference',integral_unit,'x');
    P=declare_series(P,'integral_numeric','integral_numeric','derived',integral_unit,'x');
    P=declare_series(P,'integral_error','integral_error','residual',integral_unit,'x');
    P=declare_series(P,'absolute_integral_error','absolute_integral_error','residual',integral_unit,'x');
    items={'x',x;'function',f;'derivative_exact',derivative_exact;'derivative_numeric',derivative_numeric;'derivative_error',derivative_error;'absolute_derivative_error',absolute_derivative_error;'integral_exact',integral_exact;'integral_numeric',integral_numeric;'integral_error',integral_error;'absolute_integral_error',absolute_integral_error};
    P=gxtxt_publication_v2_append(P,'sample',items);
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);
    [P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;

    write_metrics(fullfile(outdir,'calculus_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id, ...
      x_id,function_id,derivative_reference_id,antiderivative_reference_id,x_name,function_name,derivative_name,integral_name, ...
      x_unit,function_unit,derivative_unit,integral_unit,source_provider,numeric,grid_info,derivative_result,definite_result,cumulative_result, ...
      derivative_metrics,integral_metrics,definite_numeric,exact_definite,definite_error,selection_id,P.provider,n);
    write_report(fullfile(outdir,'calculus_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id, ...
      x_id,function_id,derivative_reference_id,antiderivative_reference_id,x_name,function_name,derivative_name,integral_name, ...
      x_unit,function_unit,derivative_unit,integral_unit,numeric,grid_info,derivative_result,definite_result,cumulative_result, ...
      derivative_metrics,integral_metrics,definite_numeric,exact_definite,definite_error,selection_id,P.provider,pub_diag,pub_result,n,x(1),x(end));

    save(fullfile(outdir,'render_cache.mat'),'x','f','derivative_exact','derivative_numeric','derivative_error','integral_exact','integral_numeric','integral_error','x_name','function_name','derivative_name','integral_name','x_unit','function_unit','derivative_unit','integral_unit','output_dataset_id','selection_id');
    demo_numeric_calculus_render(outdir,output_dataset_id,x_name,function_name,derivative_name,integral_name,x_unit,function_unit,derivative_unit,integral_unit,cfg);

    gxtxt_progress_complete('done',sprintf('Published %s and rendered enabled calculus graphs (%d samples)',output_dataset_id,n));
    fprintf('[%s] version=%s source=%s output=%s derivative=%s integral=%s cumulative=%s samples=%d validation=PASS provider=%s\n', ...
      module_id,module_version,source_dataset_id,output_dataset_id,derivative_result.method,definite_result.method,cumulative_result.method,n,P.provider);
  catch err
    if(publication_open && !publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    try gxtxt_progress_fail('failed','Calculus demonstration failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction

function validate_selection(S,dataset_id,x_id,module_id)
  if(!strcmp(S.type,'x_range')),error('%s: this module supports only x_range Dataset Selections',module_id);endif
  if(!strcmp(strtrim(S.source_dataset_id),dataset_id)),error('%s: Dataset Selection belongs to a different source Dataset',module_id);endif
  if(!isempty(strtrim(S.x_variable_id))&&!strcmp(strtrim(S.x_variable_id),x_id)),error('%s: Dataset Selection uses a different X variable',module_id);endif
endfunction

function [x,f,dref,Fref,provider]=read_source_series(cfg,x_id,f_id,dref_id,Fref_id,selection)
  S=gxtxt_table_stream_open_source(cfg,'primary',{x_id,f_id,dref_id,Fref_id},65536,struct('start',0,'count',-1,'require_direct',false));
  provider=S.storage_provider;xc={};fc={};dc={};Fc={};total=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);if(C.nrows<1),continue;endif
      xc{end+1}=double(C.values{1}(:));fc{end+1}=double(C.values{2}(:));dc{end+1}=double(C.values{3}(:));Fc{end+1}=double(C.values{4}(:));total+=C.nrows;
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(total<1),x=zeros(0,1);f=x;dref=x;Fref=x;return;endif
  x=vertcat(xc{:});f=vertcat(fc{:});dref=vertcat(dc{:});Fref=vertcat(Fc{:});
  if(selection.enabled)
    mask=gxtxt_selection_mask(selection,x);x=x(mask);f=f(mask);dref=dref(mask);Fref=Fref(mask);
  endif
endfunction

function api=discover_numeric_api(framework_root,module_id)
  descriptor=fullfile(framework_root,'plugins','modules','math.numeric','module.ini');
  if(exist(descriptor,'file')!=2),error('%s: required math.numeric module descriptor is missing',module_id);endif
  d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));
  if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: required public NUMERIC_API_v1 is not advertised by math.numeric',module_id);endif
  api_version=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));if(!strcmp(api_version,'1')),error('%s: unsupported NUMERIC_API_v1 version: %s',module_id,api_version);endif
  capabilities=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));
  required={'integration','cumulative_integration','differentiation','dataset_calculus','grid_analysis','dataset_variables','dataset_selection','residual_metrics'};
  for k=1:numel(required),if(!any(strcmp(capabilities,required{k}))),error('%s: NUMERIC_API_v1 capability is missing: %s',module_id,required{k});endif,endfor
  entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));function_name=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));
  if(isempty(entry)||isempty(function_name)),error('%s: math.numeric does not advertise a complete Octave NUMERIC_API_v1 binding',module_id);endif
  entry_path=fullfile(fileparts(descriptor),entry);if(exist(entry_path,'file')!=2),error('%s: advertised NUMERIC_API_v1 Octave entrypoint is missing: %s',module_id,entry_path);endif
  addpath(fileparts(entry_path));if(exist(function_name,'file')!=2),error('%s: advertised NUMERIC_API_v1 Octave function is unavailable: %s',module_id,function_name);endif
  api=struct('name','NUMERIC_API_v1','api_version',api_version,'function_name',function_name,'entrypoint',entry,'descriptor',descriptor);
endfunction

function unit=resolved_result_unit(result,reference_unit,module_id,label)
  result_unit='';if(isfield(result,'result_unit')),result_unit=strtrim(result.result_unit);endif
  reference_unit=strtrim(reference_unit);
  if(!isempty(result_unit)&&!isempty(reference_unit)&&!strcmp(result_unit,reference_unit)),error('%s: %s reference unit (%s) disagrees with NUMERIC_API_v1 result unit (%s)',module_id,label,reference_unit,result_unit);endif
  if(!isempty(result_unit)),unit=result_unit;else unit=reference_unit;endif
endfunction

function M=error_metrics(err,derivative_mode,numeric_fn)
  err=double(err(:));n=numel(err);M=struct('rmse',NaN,'mae',NaN,'max_abs',NaN,'endpoint_max_abs',NaN,'interior_rmse',NaN);
  if(n<1||any(!isfinite(err))),return;endif
  metrics=feval(numeric_fn,'residual_metrics',zeros(size(err)),err,struct());
  M.rmse=metrics.rmse;M.mae=metrics.mae;M.max_abs=metrics.max_abs_error;
  if(derivative_mode)
    if(n>=2),M.endpoint_max_abs=max(abs([err(1);err(end)]));endif
    if(n>2),q=err(2:end-1);inner=feval(numeric_fn,'residual_metrics',zeros(size(q)),q,struct());M.interior_rmse=inner.rmse;endif
  endif
endfunction

function P=declare_series(P,id,name,role,unit,coordinate_id)
  spec=struct('dtype','float64','dimension_ids','sample','name',name,'unit',unit,'semantic_role',role,'axis_kind','explicit');
  if(isempty(coordinate_id)),spec.coordinate_role='coordinate';else spec.coordinate_role='data';spec.coordinate_variable_ids=coordinate_id;endif
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction

function out=binding_column(value,role)
  value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif
  dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else out=value;endif
  if(isempty(out)),error('demo.numeric.calculus: invalid %s binding',role);endif
endfunction
function value=arg_value(args,key,default),value=default;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
function s=provenance_text(module_id,module_version,D,I,C,selection_id)
  s=sprintf('%s %s via NUMERIC_API_v1; differentiation=%s; definite_integration=%s; cumulative_integration=%s',module_id,module_version,D.method,I.method,C.method);
  if(!isempty(selection_id)),s=[s '; selection_id=' selection_id];endif
endfunction

function write_prepublication_failure(path,module_id,module_version,source_dataset_id,message)
  fid=fopen(path,'w');if(fid<0),return;endif
  unwind_protect
    fprintf(fid,'GX-TXT Numerical Calculus Demo\n==============================\n\nPlugin: %s %s\nSource Dataset: %s\n\n%s\nNo derived Dataset was published.\n',module_id,module_version,source_dataset_id,message);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_metrics(path,module_id,module_version,source_dataset_id,output_dataset_id,x_id,function_id,dref_id,Fref_id,x_name,function_name,derivative_name,integral_name,x_unit,function_unit,derivative_unit,integral_unit,source_provider,numeric,grid_info,D,I,C,DM,IM,def_num,def_exact,def_err,selection_id,output_provider,n)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write calculus_metrics.ini',module_id);endif
  unwind_protect
    fprintf(fid,'; GX-TXT demo.numeric.calculus metrics\n');
    fprintf(fid,'[module]\nid=%s\nversion=%s\nvalidation=PASS\n',module_id,module_version);
    fprintf(fid,'\n[source]\ndataset_id=%s\nx_variable_id=%s\nfunction_variable_id=%s\nderivative_reference_variable_id=%s\nantiderivative_reference_variable_id=%s\nx_name=%s\nfunction_name=%s\nderivative_reference_name=%s\nantiderivative_reference_name=%s\nx_unit=%s\nfunction_unit=%s\nderivative_unit=%s\nintegral_unit=%s\nstorage_provider=%s\nsample_count=%d\ngrid_uniform=%d\ngrid_step=%.17g\nselection_id=%s\n',source_dataset_id,x_id,function_id,dref_id,Fref_id,ini_escape(x_name),ini_escape(function_name),ini_escape(derivative_name),ini_escape(integral_name),ini_escape(x_unit),ini_escape(function_unit),ini_escape(derivative_unit),ini_escape(integral_unit),source_provider,n,logical_num(grid_info.uniform),grid_info.step,ini_escape(selection_id));
    fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n',numeric.name,numeric.api_version,numeric.function_name);
    fprintf(fid,'\n[differentiation]\nmethod=%s\nkernel=%s\nrmse=%.17g\nmae=%.17g\nmax_abs_error=%.17g\nendpoint_max_abs_error=%.17g\ninterior_rmse=%.17g\n',ini_escape(D.method),field_text(D,'kernel'),DM.rmse,DM.mae,DM.max_abs,DM.endpoint_max_abs,DM.interior_rmse);
    fprintf(fid,'\n[definite_integration]\nmethod=%s\nkernel=%s\nnumerical=%.17g\nexact=%.17g\nerror=%.17g\n',ini_escape(I.method),field_text(I,'kernel'),def_num,def_exact,def_err);
    fprintf(fid,'\n[cumulative_integration]\nmethod=%s\nrmse=%.17g\nmae=%.17g\nmax_abs_error=%.17g\n',ini_escape(C.method),IM.rmse,IM.mae,IM.max_abs);
    fprintf(fid,'\n[output]\ndataset_id=%s\ncontract=table.generic\nstorage_provider=%s\n',output_dataset_id,output_provider);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,module_id,module_version,source_dataset_id,output_dataset_id,x_id,function_id,dref_id,Fref_id,x_name,function_name,derivative_name,integral_name,x_unit,function_unit,derivative_unit,integral_unit,numeric,grid_info,D,I,C,DM,IM,def_num,def_exact,def_err,selection_id,output_provider,pub_diag,pub_result,n,x0,x1)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write calculus_report.txt',module_id);endif
  unwind_protect
    fprintf(fid,'GX-TXT Numerical Calculus Demo\n==============================\n\n');
    fprintf(fid,'Plugin: %s %s\nSource Dataset: %s\n',module_id,module_version,source_dataset_id);
    fprintf(fid,'X: %s [%s] (variable_id=%s)\n',x_name,x_unit,x_id);fprintf(fid,'Function: %s [%s] (variable_id=%s)\n',function_name,function_unit,function_id);
    fprintf(fid,'Exact derivative: %s [%s] (variable_id=%s)\n',derivative_name,derivative_unit,dref_id);fprintf(fid,'Exact antiderivative: %s [%s] (variable_id=%s)\n',integral_name,integral_unit,Fref_id);
    fprintf(fid,'Samples: %d; X range: %.12g .. %.12g; uniform=%s; step=%.12g\n',n,x0,x1,bool_text(grid_info.uniform),grid_info.step);
    if(!isempty(selection_id)),fprintf(fid,'Dataset Selection: %s\n',selection_id);else fprintf(fid,'Dataset Selection: none\n');endif
    fprintf(fid,'NUMERIC API: %s v%s (%s)\nOutput Dataset: %s (table.generic; provider=%s)\n\n',numeric.name,numeric.api_version,numeric.function_name,output_dataset_id,output_provider);
    fprintf(fid,'Numerical differentiation\n-------------------------\nMethod: %s\nKernel: %s\nRMSE: %.12g\nMAE: %.12g\nMaximum absolute error: %.12g\nEndpoint maximum absolute error: %.12g\nInterior RMSE: %.12g\n\n',D.method,field_text(D,'kernel'),DM.rmse,DM.mae,DM.max_abs,DM.endpoint_max_abs,DM.interior_rmse);
    fprintf(fid,'Definite integration\n--------------------\nMethod: %s\nKernel: %s\nNumerical integral: %.12g\nExact/reference integral: %.12g\nError: %.12g\n\n',I.method,field_text(I,'kernel'),def_num,def_exact,def_err);
    fprintf(fid,'Cumulative integration\n----------------------\nMethod: %s\nRMSE: %.12g\nMAE: %.12g\nMaximum absolute error: %.12g\n\n',C.method,IM.rmse,IM.mae,IM.max_abs);
    fprintf(fid,'The exact cumulative reference is shifted by its first selected value so both curves represent an integral starting at the first selected X sample.\n');
    fprintf(fid,'The module reports actual numerical error diagnostics and does not hide endpoint behavior.\n');
    fprintf(fid,'Generator sidecar metadata is not required or read by this plugin; analytical references come from the bound Dataset variables.\n\n');
    fprintf(fid,'Publication diagnostics: %s\nPublication result: %s\n',to_text(pub_diag),to_text(pub_result));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function out=field_text(S,name),out='';if(isstruct(S)&&isfield(S,name)),out=ini_escape(S.(name));endif,endfunction
function out=logical_num(v),if(v),out=1;else out=0;endif,endfunction
function out=bool_text(v),if(v),out='yes';else out='no';endif,endfunction
function out=ini_escape(v),out=strrep(strrep(char(v),sprintf('\n'),' '),sprintf('\r'),' ');endfunction
function out=to_text(v),if(ischar(v)),out=v;elseif(isnumeric(v)||islogical(v)),out=mat2str(v);else out='structured result';endif,endfunction
