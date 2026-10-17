function demo_numeric_regression_main(args,framework_root)
% Dataset-native regression demonstration using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='demo.numeric.regression';module_version='1.1.0';publication_open=false;publication_finalized=false;P=struct();C=struct();coeff_open=false;coeff_finalized=false;
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing numerical regression demonstration','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif;if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif
    xb=binding_column(gxtxt_ini_get(cfg,'bindings.x',''),'x');yb=binding_column(gxtxt_ini_get(cfg,'bindings.measured',''),'measured');rb=binding_column(gxtxt_ini_get(cfg,'bindings.reference',''),'reference');sb=binding_column(gxtxt_ini_get(cfg,'bindings.sigma',''),'sigma');wb=binding_column(gxtxt_ini_get(cfg,'bindings.weight',''),'weight');
    if(isempty(xb)||isempty(yb)),error('%s: X and measured Y bindings are required',module_id);endif
    [x_unit,~,xm]=gxtxt_analysis_source_variable_meta(cfg,'primary',xb);[y_unit,~,ym]=gxtxt_analysis_source_variable_meta(cfg,'primary',yb);if(!meta_found(xm)||!meta_found(ym)),error('%s: X or measured Y binding could not be resolved',module_id);endif
    x_id=strtrim(xm.variable_id);y_id=strtrim(ym.variable_id);x_name=strtrim(xm.name);y_name=strtrim(ym.name);if(isempty(x_id)||isempty(y_id)),error('%s: stable variable IDs are required',module_id);endif
    [reference_id,reference_name,reference_unit]=optional_meta(cfg,rb,'reference',module_id);[sigma_id,sigma_name,sigma_unit]=optional_meta(cfg,sb,'sigma',module_id);[weight_id,weight_name,weight_unit]=optional_meta(cfg,wb,'weight',module_id);
    if(!isempty(reference_id)&&!isempty(reference_unit)&&!isempty(y_unit)&&!strcmp(reference_unit,y_unit)),error('%s: reference and measured Y units differ',module_id);endif
    if(!isempty(sigma_id)&&!isempty(sigma_unit)&&!isempty(y_unit)&&!strcmp(sigma_unit,y_unit)),error('%s: sigma and measured Y units differ',module_id);endif
    fit_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.fit_mode','linear')));if(!any(strcmp(fit_mode,{'linear','polynomial'}))),error('%s: Regression mode must be linear or polynomial',module_id);endif
    degree=str2double(gxtxt_ini_get(cfg,'config.polynomial_degree','3'));if(strcmp(fit_mode,'linear')),degree=1;endif;if(!isfinite(degree)||degree<1||degree!=fix(degree)),error('%s: Polynomial degree must be a positive integer',module_id);endif
    weight_semantics=lower(strtrim(gxtxt_ini_get(cfg,'config.weight_semantics','relative')));if(!any(strcmp(weight_semantics,{'relative','inverse_variance'}))),error('%s: Weight semantics must be relative or inverse_variance',module_id);endif
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.regression.result'));if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid Output Dataset ID',module_id);endif;if(strcmp(output_dataset_id,source_dataset_id)),error('%s: Output Dataset ID must differ from source Dataset ID',module_id);endif
    selection=struct('enabled',false);try selection=gxtxt_selection_from_runtime(cfg,'selection');catch selerr,error('%s: invalid Dataset Selection: %s',module_id,selerr.message);end_try_catch;if(selection.enabled),validate_selection(selection,source_dataset_id,x_id,module_id);endif

    gxtxt_progress_stage('load_dataset','Reading regression source variables','indeterminate');
    ids={x_id,y_id};roles={'x','measured'};if(!isempty(reference_id)),ids{end+1}=reference_id;roles{end+1}='reference';endif;if(!isempty(sigma_id)),ids{end+1}=sigma_id;roles{end+1}='sigma';endif;if(!isempty(weight_id)),ids{end+1}=weight_id;roles{end+1}='weight';endif
    [D,source_provider]=read_source(cfg,ids,roles,selection);x=D.x;measured=D.measured;n=numel(x);if(n<degree+1),error('%s: degree %d requires at least %d selected observations',module_id,degree,degree+1);endif
    if(any(!isfinite(x))||any(!isfinite(measured))),error('%s: X and measured Y must be finite',module_id);endif
    if(isfield(D,'sigma')),if(any(!isfinite(D.sigma))||any(D.sigma<=0)),error('%s: measurement standard uncertainties must be finite and positive',module_id);endif,endif
    if(isfield(D,'weight')),if(any(!isfinite(D.weight))||any(D.weight<0)||!any(D.weight>0)),error('%s: statistical weights must be finite, non-negative and include a positive value',module_id);endif,endif

    numeric=discover_numeric_api(framework_root,module_id);
    statistics_lifetime=gxtxt_statistics_scope_v1();
    opts=struct('center_scale',true);if(selection.enabled),opts.selection=selection;endif
    gxtxt_progress_stage('numeric','Running public regression operations','determinate',4);
    fit_ols=feval(numeric.function_name,'dataset_polynomial_fit',session,source_dataset_id,x_id,y_id,degree,opts);gxtxt_progress_update(1,4,'numeric','OLS polynomial fit complete');
    ev_ols=feval(numeric.function_name,'polynomial_evaluate',fit_ols,x,struct());fit_ols.predicted=double(fit_ols.predicted(:));fit_ols.residuals=double(fit_ols.residuals(:));
    fit_ols.metrics=feval(numeric.function_name,'residual_metrics',measured,fit_ols.predicted);fit_ols.eval_max_abs=max(abs(double(ev_ols.yq(:))-fit_ols.predicted));
    has_wls=!isempty(weight_id);fit_wls=empty_fit();
    if(has_wls)
      wopts=opts;wopts.weight_variable_id=weight_id;wopts.weight_semantics=weight_semantics;fit_wls=feval(numeric.function_name,'dataset_polynomial_fit',session,source_dataset_id,x_id,y_id,degree,wopts);ev_wls=feval(numeric.function_name,'polynomial_evaluate',fit_wls,x,struct());fit_wls.predicted=double(fit_wls.predicted(:));fit_wls.residuals=double(fit_wls.residuals(:));fit_wls.metrics=feval(numeric.function_name,'residual_metrics',measured,fit_wls.predicted);fit_wls.eval_max_abs=max(abs(double(ev_wls.yq(:))-fit_wls.predicted));
    endif;gxtxt_progress_update(2,4,'numeric','Weighted fit path complete');
    gxtxt_progress_update(3,4,'numeric','Existing fit and residual facts ready for CORE interpretation');

    md=read_optional_metadata(cfg);truth=truth_from_metadata(md,degree,numeric);has_reference=isfield(D,'reference');reference=zeros(0,1);reference_source='none';
    if(has_reference),reference=D.reference;reference_source='dataset';elseif(truth.available),reference=truth.reference(x);has_reference=true;reference_source='dataset_metadata';endif
    if(has_reference),if(numel(reference)!=n||any(!isfinite(reference))),error('%s: reference Y must be finite and row-aligned',module_id);endif,endif
    if(truth.available),truth.ols_error=fit_ols.coefficients(:)-truth.coefficients(:);if(has_wls),truth.wls_error=fit_wls.coefficients(:)-truth.coefficients(:);else truth.wls_error=[];endif;endif
    sigma_weight=struct('available',false,'consistent',false);
    raw_consistency=struct();
    if(isfield(D,'sigma')&&isfield(D,'weight'))
      sigma_weight.available=true;expected=1.0./(D.sigma.^2);
      if(any(!isfinite(expected))||any(expected<=0)),error('%s: sigma inverse variances must be finite positive binary64 values for comparison',module_id);endif
      raw_consistency=feval(numeric.function_name,'residual_metrics',expected,D.weight,struct('relative_floor',realmin));
    endif
    sigma_weight.core=gxtxt_statistics_v1('from_numeric','math.numeric.comparison','residual_metrics',raw_consistency, ...
      struct('y_unit',weight_unit,'sample_role','evaluation'),struct(), ...
      struct('producer',module_id,'purpose','numerical_sigma_weight_consistency','tolerance',1e-8));
    consistency_values=gxtxt_statistics_values_v1(sigma_weight.core);
    sigma_weight.consistent=sigma_weight.available&&consistency_values.relative_n==n&&isfinite(consistency_values.max_relative_error)&&consistency_values.max_relative_error<=1e-8;

    validation=validate_fit_contract(fit_ols,fit_wls,has_wls,n,degree);
    gxtxt_progress_update(4,4,'numeric','Regression diagnostics and metadata checks complete');if(!validation.pass),write_failure(fullfile(outdir,'regression_report.txt'),module_id,module_version,validation.message);error('%s: numerical validation failed; see regression_report.txt',module_id);endif

    context=struct('orientation','y_of_x','x_unit',x_unit,'y_unit',y_unit,'x_variable_id',x_id,'y_variable_id',y_id, ...
      'constraints','none','coefficient_space','original_physical','noise_model',gxtxt_ini_get(cfg,'config.noise_model','unspecified'));
    fit_ols=interpret_fit(fit_ols,context,module_id);statistical_results=struct('ols',fit_ols.core,'sigma_weight',sigma_weight.core);
    if(has_wls),fit_wls=interpret_fit(fit_wls,context,module_id);statistical_results.wls=fit_wls.core;endif

    gxtxt_progress_stage('publish','Publishing regression comparison Dataset','determinate',n);
    srcids={x_id,y_id};if(!isempty(reference_id)),srcids{end+1}=reference_id;endif;if(!isempty(sigma_id)),srcids{end+1}=sigma_id;endif;if(!isempty(weight_id)),srcids{end+1}=weight_id;endif
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{srcids},'source',source_dataset_id,'provenance',sprintf('%s %s via NUMERIC_API_v1; mode=%s; degree=%d; weighted=%d; weight_semantics=%s',module_id,module_version,fit_mode,degree,has_wls,weight_semantics),'notes','Regression fit values and residual diagnostics produced by public math.numeric operations.');
    popts.statistical_results=statistical_results;
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;P=gxtxt_publication_v2_declare_dimension(P,'sample',0,true);P=declare_series(P,'x','x','independent',x_unit,'');P=declare_series(P,'measured','measured','measured',y_unit,'x');P=declare_series(P,'fitted_ols','fitted_ols','derived',y_unit,'x');P=declare_series(P,'residual_ols','residual_ols','residual',y_unit,'x');P=declare_series(P,'absolute_residual_ols','absolute_residual_ols','derived',y_unit,'x');
    items={'x',x;'measured',measured;'fitted_ols',fit_ols.predicted;'residual_ols',fit_ols.residuals;'absolute_residual_ols',abs(fit_ols.residuals)};
    if(has_wls),P=declare_series(P,'fitted_wls','fitted_wls','derived',y_unit,'x');P=declare_series(P,'residual_wls','residual_wls','residual',y_unit,'x');P=declare_series(P,'absolute_residual_wls','absolute_residual_wls','derived',y_unit,'x');items(end+1,:)={'fitted_wls',fit_wls.predicted};items(end+1,:)={'residual_wls',fit_wls.residuals};items(end+1,:)={'absolute_residual_wls',abs(fit_wls.residuals)};endif
    if(isfield(D,'sigma')),P=declare_series(P,'sigma','sigma','uncertainty',sigma_unit,'x');items(end+1,:)={'sigma',D.sigma};endif
    if(isfield(D,'weight')),P=declare_series(P,'weight','weight','weight',weight_unit,'x');items(end+1,:)={'weight',D.weight};endif
    if(has_reference),P=declare_series(P,'reference','reference','reference',y_unit,'x');P=declare_series(P,'fit_error_ols','fit_error_ols','residual',y_unit,'x');items(end+1,:)={'reference',reference};items(end+1,:)={'fit_error_ols',fit_ols.predicted-reference};if(has_wls),P=declare_series(P,'fit_error_wls','fit_error_wls','residual',y_unit,'x');items(end+1,:)={'fit_error_wls',fit_wls.predicted-reference};endif,endif
    P=gxtxt_publication_v2_append(P,'sample',items);[P,pub_diag]=gxtxt_publication_v2_diagnostics(P);[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;

    coeff_dataset_id=[output_dataset_id '.coefficients'];
    C=gxtxt_publication_v2_open(session,module_id,coeff_dataset_id,'table.generic',popts);coeff_open=true;
    C=gxtxt_publication_v2_declare_dimension(C,'coefficient',0,true);
    C=declare_coefficient(C,'coefficient_index','independent',true);
    C=declare_coefficient(C,'estimate_ols','derived',false);
    C=declare_coefficient(C,'stderr_ols','uncertainty',false);
    coeff_items={'coefficient_index',(1:numel(fit_ols.coefficients))'; ...
      'estimate_ols',fit_ols.coefficients(:);'stderr_ols',fit_ols.standard_errors(:)};
    if(has_wls)
      C=declare_coefficient(C,'estimate_wls','derived',false);
      C=declare_coefficient(C,'stderr_wls','uncertainty',false);
      coeff_items(end+1,:)={'estimate_wls',fit_wls.coefficients(:)};
      coeff_items(end+1,:)={'stderr_wls',fit_wls.standard_errors(:)};
    endif
    for field={'parameter_id','unit','stderr_ols_status','stderr_ols_reason'}
      C=declare_coefficient_text(C,field{1});
    endfor
    params=gxtxt_statistics_v1('parameter_rows',fit_ols.core);
    coeff_items=[coeff_items;{'parameter_id',cellfun(@(r) r.id,params,'UniformOutput',false)(:);'unit',cellfun(@(r) r.unit,params,'UniformOutput',false)(:); ...
      'stderr_ols_status',cellfun(@(r) r.se_status,params,'UniformOutput',false)(:);'stderr_ols_reason',cellfun(@(r) r.se_reason,params,'UniformOutput',false)(:)}];
    if(has_wls)
      for field={'stderr_wls_status','stderr_wls_reason'},C=declare_coefficient_text(C,field{1});endfor
      wparams=gxtxt_statistics_v1('parameter_rows',fit_wls.core);
      coeff_items=[coeff_items;{'stderr_wls_status',cellfun(@(r) r.se_status,wparams,'UniformOutput',false)(:);'stderr_wls_reason',cellfun(@(r) r.se_reason,wparams,'UniformOutput',false)(:)}];
    endif
    C=gxtxt_publication_v2_append(C,'coefficient',coeff_items);
    [C,~]=gxtxt_publication_v2_finalize(C);coeff_finalized=true;coeff_open=false;

    write_metrics(fullfile(outdir,'regression_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,fit_mode,degree,weight_semantics,x_id,y_id,reference_id,sigma_id,weight_id,x_name,y_name,x_unit,y_unit,n,source_provider,numeric,fit_ols,fit_wls,has_wls,truth,md,reference_source,sigma_weight,P.provider);
    write_report(fullfile(outdir,'regression_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,fit_mode,degree,weight_semantics,x_name,y_name,x_unit,y_unit,n,numeric,fit_ols,fit_wls,has_wls,truth,md,reference_source,sigma_weight,pub_diag,pub_result);
    has_sigma=isfield(D,'sigma');
    save(fullfile(outdir,'render_cache.mat'),'has_wls','has_reference','has_sigma','x_name','y_name','x_unit','y_unit','degree','fit_mode','output_dataset_id','coeff_dataset_id');
    demo_numeric_regression_render(outdir,output_dataset_id,coeff_dataset_id,has_wls,has_reference,has_sigma,x_name,y_name,x_unit,y_unit,degree,cfg);
    gxtxt_progress_complete('done',sprintf('Published %s and rendered regression graphs',output_dataset_id));fprintf('[%s] version=%s source=%s output=%s degree=%d weighted=%d validation=PASS provider=%s\n',module_id,module_version,source_dataset_id,output_dataset_id,degree,has_wls,P.provider);
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    if(coeff_open&&!coeff_finalized),try C=gxtxt_publication_v2_abort(C);catch;end_try_catch;endif
    try gxtxt_progress_fail('failed','Regression demonstration failed; see log for details');catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction

function tf=meta_found(m),tf=isstruct(m)&&isfield(m,'found')&&m.found;endfunction
function [id,name,unit]=optional_meta(cfg,binding,role,module_id),id='';name='';unit='';if(isempty(binding)),return;endif;[unit,~,m]=gxtxt_analysis_source_variable_meta(cfg,'primary',binding);if(!meta_found(m)),error('%s: optional %s binding could not be resolved: %s',module_id,role,binding);endif;id=strtrim(m.variable_id);name=strtrim(m.name);if(isempty(id)),error('%s: optional %s binding has no stable variable ID',module_id,role);endif,endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else out=value;endif;if(isempty(out)),error('demo.numeric.regression: invalid %s binding',role);endif,endfunction
function [D,provider]=read_source(cfg,ids,roles,selection),S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false));provider=S.storage_provider;parts=cell(1,numel(ids));for j=1:numel(ids),parts{j}={};endfor;unwind_protect,while(!S.eof),[S,C]=gxtxt_table_stream_next(S);if(C.nrows>0),for j=1:numel(ids),parts{j}{end+1}=double(C.values{j}(:));endfor,endif,endwhile,unwind_protect_cleanup,S=gxtxt_table_stream_close(S);end_unwind_protect;D=struct();for j=1:numel(ids),if(isempty(parts{j})),v=zeros(0,1);else v=vertcat(parts{j}{:});endif;D.(roles{j})=v;endfor;if(selection.enabled),mask=gxtxt_selection_mask(selection,D.x);fn=fieldnames(D);for j=1:numel(fn),D.(fn{j})=D.(fn{j})(mask);endfor,endif,endfunction
function api=discover_numeric_api(root,module_id),descriptor=fullfile(root,'plugins','modules','math.numeric','module.ini');if(exist(descriptor,'file')!=2),error('%s: math.numeric descriptor missing',module_id);endif;d=gxtxt_ini_read(descriptor);caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));required={'linear_least_squares','weighted_linear_least_squares','linear_regression','polynomial_fit','weighted_polynomial_fit','dataset_fitting','descriptive_statistics','dataset_selection'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor;entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));ver=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));if(!strcmp(ver,'1')),error('%s: unsupported NUMERIC_API_v1 version',module_id);endif;addpath(fileparts(fullfile(fileparts(descriptor),entry)));if(exist(fn,'file')!=2),error('%s: NUMERIC_API_v1 Octave function unavailable',module_id);endif;api=struct('name','NUMERIC_API_v1','api_version',ver,'function_name',fn,'entrypoint',entry);endfunction
function F=interpret_fit(F,context,producer)
  F.core=gxtxt_statistics_v1('from_numeric','math.numeric.polynomial','polynomial_fit',F,context,F.metrics,struct('producer',producer));
  interpreted=gxtxt_statistics_values_v1(F.core);
  F.standard_errors=interpreted.standard_errors;
endfunction
function E=empty_fit(),E=struct('available',false,'coefficients',[],'standard_errors',[],'predicted',[],'residuals',[],'metrics',struct(),'r_squared',NaN,'adjusted_r_squared',NaN,'rmse',NaN,'residual_rmse',NaN,'condition_number',NaN,'reduced_chi_squared',NaN,'weight_semantics','','eval_max_abs',NaN);endfunction
function V=validate_fit_contract(O,W,has_wls,n,degree)
  pass=numel(O.coefficients)==degree+1&&numel(O.predicted)==n&&numel(O.residuals)==n&&all(isfinite(O.predicted))&&all(isfinite(O.residuals))&&O.eval_max_abs<=1e-9*max(1,max(abs(O.predicted)));
  if(has_wls),pass=pass&&numel(W.coefficients)==degree+1&&numel(W.predicted)==n&&numel(W.residuals)==n&&all(isfinite(W.predicted))&&all(isfinite(W.residuals))&&W.weighted&&W.eval_max_abs<=1e-9*max(1,max(abs(W.predicted)));endif
  msg='';if(!pass),msg='NUMERIC_API_v1 returned inconsistent regression dimensions or polynomial evaluation.';endif
  V=struct('pass',pass,'message',msg);
endfunction
function md=read_optional_metadata(cfg),try md=gxtxt_analysis_source_dataset_metadata(cfg,'primary');catch,md=struct('found',false,'count',0,'keys',{{}},'values',{{}});end_try_catch;endfunction
function T=truth_from_metadata(md,degree,api),T=struct('available',false,'coefficients',[],'degree',NaN,'source','none');if(!isstruct(md)||!isfield(md,'found')||!md.found),T.reference=@(x) zeros(size(x));return;endif;[raw,ok]=mdget(md,'regression.truth.coefficients','');if(!ok),T.reference=@(x) zeros(size(x));return;endif;parts=strsplit(strrep(raw,',',';'),';');c=[];for k=1:numel(parts),v=str2double(strtrim(parts{k}));if(!isfinite(v)),T.reference=@(x) zeros(size(x));return;endif;c(end+1,1)=v;endfor;if(numel(c)!=degree+1),T.reference=@(x) zeros(size(x));return;endif;[dr,dok]=mdget(md,'regression.truth.degree','');if(dok&&str2double(dr)!=degree),T.reference=@(x) zeros(size(x));return;endif;T.available=true;T.coefficients=c;T.degree=degree;T.source='dataset_metadata';T.reference=@(x) reference_eval(api,c,x);endfunction
function y=reference_eval(api,c,x),M=struct('coefficients',c(:));R=feval(api.function_name,'polynomial_evaluate',M,x,struct());y=double(R.yq(:));endfunction
function [v,found]=mdget(md,key,def),v=def;found=false;if(!isfield(md,'keys')),return;endif;i=find(strcmp(md.keys,key),1);if(!isempty(i)),v=md.values{i};found=true;endif,endfunction
function validate_selection(S,dataset_id,x_id,module_id),if(!S.enabled),return;endif;if(!strcmp(S.source_dataset_id,dataset_id)||!strcmp(S.x_variable_id,x_id)),error('%s: Dataset Selection does not match source Dataset/X binding',module_id);endif;if(!strcmp(lower(strtrim(S.type)),'x_range')),error('%s: only X-range Dataset Selection is supported',module_id);endif,endfunction
function P=declare_series(P,id,name,role,unit,coord),spec=struct('dtype','float64','dimension_ids','sample','name',name,'unit',unit,'semantic_role',role,'axis_kind','explicit');if(isempty(coord)),spec.coordinate_role='coordinate';else spec.coordinate_role='data';spec.coordinate_variable_ids=coord;endif;P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function P=declare_coefficient(P,id,role,coordinate)
  spec=struct('dtype','float64','dimension_ids','coefficient','name',id,'unit','','semantic_role',role,'axis_kind','explicit');
  if(coordinate),spec.coordinate_role='coordinate';else spec.coordinate_role='data';spec.coordinate_variable_ids='coefficient_index';endif
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction
function P=declare_coefficient_text(P,id)
  spec=struct('dtype','string','dimension_ids','coefficient','name',id,'unit','','semantic_role','category','value_kind','text','coordinate_role','data','axis_kind','none');
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction
function write_failure(path,id,ver,msg),fid=fopen(path,'w');if(fid<0),return;endif;fprintf(fid,'GX-TXT Numerical Regression Demo\n================================\n\nPlugin: %s %s\nValidation: FAIL\n%s\n',id,ver,msg);fclose(fid);endfunction
function write_metrics(path,id,ver,src,outid,mode,degree,wsem,xid,yid,rid,sid,wid,xname,yname,xunit,yunit,n,provider,api,O,W,has_wls,T,md,refsrc,SW,outprovider),fid=fopen(path,'w');if(fid<0),error('%s: cannot write regression_metrics.ini',id);endif;fprintf(fid,'; GX-TXT demo.numeric.regression metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n\n[source]\ndataset_id=%s\nx_variable_id=%s\ny_variable_id=%s\nreference_variable_id=%s\nsigma_variable_id=%s\nweight_variable_id=%s\nx_name=%s\ny_name=%s\nx_unit=%s\ny_unit=%s\nsample_count=%d\nstorage_provider=%s\n',id,ver,src,xid,yid,rid,sid,wid,ini_escape(xname),ini_escape(yname),ini_escape(xunit),ini_escape(yunit),n,provider);fprintf(fid,'\n[fit]\nmode=%s\ndegree=%d\nweight_semantics=%s\nweighted_available=%d\nreference_source=%s\n',mode,degree,wsem,has_wls,refsrc);write_fit_ini(fid,'ols',O);if(has_wls),write_fit_ini(fid,'wls',W);endif;fprintf(fid,'\n[metadata]\nresource_found=%d\ntruth_coefficients_available=%d\n',logical_num(md.found),logical_num(T.available));if(T.available),fprintf(fid,'truth_coefficients=%s\nols_coefficient_error=%s\n',vec_text(T.coefficients),vec_text(T.ols_error));if(has_wls),fprintf(fid,'wls_coefficient_error=%s\n',vec_text(T.wls_error));endif,endif;fprintf(fid,'\n[sigma_weight]\navailable=%d\nconsistent_inverse_variance=%d\n',logical_num(SW.available),logical_num(SW.consistent));fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',SW.core,struct('max_relative_error','max_relative_error')));fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n\n[output]\ndataset_id=%s\ncontract=table.generic\nstorage_provider=%s\n',api.name,api.api_version,api.function_name,outid,outprovider);fclose(fid);endfunction
function write_fit_ini(fid,name,F)
  fprintf(fid,'\n[%s]\nweight_semantics=%s\n%s\n',name,F.weight_semantics,gxtxt_statistics_v1('parameter_ini_report',F.core));
  mapping=struct('r_squared','r_squared','adjusted_r_squared','adjusted_r_squared','rmse','rmse','mae','mae','max_abs_residual','max_abs_error', ...
    'api_objective_rmse','weighted_residual_standard_deviation','condition_number','condition_number','reduced_chi_squared','reduced_chi_squared');
  fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',F.core,mapping));
endfunction
function write_report(path,id,ver,src,outid,mode,degree,wsem,xname,yname,xunit,yunit,n,api,O,W,has_wls,T,md,refsrc,SW,pdiag,presult)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write regression_report.txt',id);endif
  fprintf(fid,'GX-TXT Numerical Regression Demo\n================================\n\nPlugin: %s %s\nSource Dataset: %s\nMode: %s; degree=%d\nX: %s [%s]\nY: %s [%s]\nSamples: %d\nNUMERIC_API_v1: %s\n',id,ver,src,mode,degree,xname,xunit,yname,yunit,n,api.function_name);
  fprintf(fid,'\nOLS parameters\n%s\n%s\n',gxtxt_statistics_v1('parameter_report',O.core),gxtxt_statistics_v1('report',O.core,{'n','rmse','mae','max_abs_error','r_squared','adjusted_r_squared','dof','condition_number','weighted_residual_standard_deviation','reduced_chi_squared'}));
  if(has_wls)
    fprintf(fid,'\nWLS parameters; weight semantics: %s\n%s\n%s\n',wsem,gxtxt_statistics_v1('parameter_report',W.core),gxtxt_statistics_v1('report',W.core,{'n','rmse','mae','max_abs_error','r_squared','adjusted_r_squared','dof','condition_number','weighted_residual_standard_deviation','reduced_chi_squared'}));
  endif
  fprintf(fid,'\nDataset Metadata resource present: %s\nReference source: %s\n',bool_text(md.found),refsrc);
  if(T.available),fprintf(fid,'Truth coefficients: %s\nOLS coefficient error: %s\n',vec_text(T.coefficients),vec_text(T.ols_error));if(has_wls),fprintf(fid,'WLS coefficient error: %s\n',vec_text(T.wls_error));endif,endif
  if(SW.available),fprintf(fid,'Sigma/weight numerical inverse-variance consistency (tolerance 1e-8): %s\n%s\n',bool_text(SW.consistent),gxtxt_statistics_v1('report',SW.core,{'max_relative_error','relative_n'}));endif
  fprintf(fid,'\nPublished Dataset: %s\nPublication finalized: yes\nValidation: PASS\n',outid);fclose(fid);
endfunction
function s=vec_text(v),if(isempty(v)),s='';return;endif;c=arrayfun(@(x)sprintf('%.17g',x),v(:)','UniformOutput',false);s=strjoin(c,';');endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function n=logical_num(v),n=double(logical(v));endfunction
function s=bool_text(v),if(v),s='yes';else s='no';endif,endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
