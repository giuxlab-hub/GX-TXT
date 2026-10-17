function curvefit_family_global_main(args)
% GX-TXT Standard Module API v1 - curve family fitting/evaluation implementation
% GX-TXT Pipeline v0.7.8 native integration: shared parameter/domain APIs + progress API
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% operation_mode=fit      -> historical fitting workflow (solver unchanged)
% operation_mode=evaluate -> frozen parameters, no optimizer is called

  config_path = arg_value(args,'--config','');
  if (isempty(config_path)), error('curvefit.family_global: --config is required'); endif
  cfg = read_ini(config_path);
  statistics_scope=gxtxt_statistics_scope_v1();
  numeric_fn = curvefit_numeric_api(cfg,{'nonlinear_least_squares','residual_metrics'});
  outdir = ini_get(cfg,'runtime.output_dir','');
  if (isempty(outdir)), error('curvefit.family_global: runtime.output_dir missing'); endif
  if (exist(outdir,'dir') != 7), mkdir(outdir); endif

  progress_start_safe('loading_data','Loading dataset','indeterminate',0);
  try
    thisdir = fileparts(mfilename('fullpath'));
    addpath(thisdir);
    model_script = ini_get(cfg,'model.script','');
    if (isempty(model_script) || exist(model_script,'file') != 2), error('Model script not found: %s',model_script); endif
    model_source_sha256=hash('sha256',fileread(model_script));
    curvefit_family_recipe_guard(cfg);
    addpath(fileparts(model_script));
    model_fun_name = ini_get(cfg,'model.function','');
    if (isempty(model_fun_name)), error('curvefit.family_global: model.function missing'); endif
    model_fun = str2func(model_fun_name);

    % Semantic model bindings are independent from presentation orientation.
    x_name = resolved_binding(cfg,'x','model.x_column','X_V');
    fam_name = resolved_binding(cfg,'family','model.family_column','Vg_V');
    y_name = resolved_binding(cfg,'y','model.y_column','Y_mA');
    [x, family, y,source_audit] = curvefit_family_source(cfg,x_name,fam_name,y_name);
    curvefit_family_recipe_guard(cfg,source_audit);
    progress_stage_safe('loading_data','Dataset loaded','determinate',max(numel(y),1));
    progress_update_safe(numel(y),max(numel(y),1),'loading_data','Dataset loaded');

    progress_stage_safe('validating_inputs','Validating model, bindings and configuration','indeterminate',0);
    if (numel(y) < 5), error('curvefit.family_global: too few valid data rows'); endif

    param_names = split_semicolon(ini_get(cfg,'model.param_names',''));
    if (isempty(param_names)), error('curvefit.family_global: model.param_names missing'); endif
    base_param_names=param_names;
    parameter_plan=curvefit_family_parameter_plan(cfg,base_param_names,family);
    param_names=parameter_plan.slot_ids;
    model_id = ini_get(cfg,'model.id','');
    dataset_id = source_audit.dataset_id;
    training_domain = empty_training_domain(x_name,fam_name,model_id,0,[]);
    training_domain_source = 'unavailable';
    parameter_path = '';

    operation_mode = lower(strtrim(ini_get(cfg,'config.operation_mode','fit')));
    if (isempty(operation_mode)), operation_mode='fit'; endif
    if (!any(strcmp(operation_mode,{'fit','evaluate'})))
      error('curvefit.family_global: invalid operation_mode: %s',operation_mode);
    endif

    presentation_orientation = lower(strtrim(ini_get(cfg,'config.presentation_orientation','x_by_family')));
    if (isempty(presentation_orientation)), presentation_orientation='x_by_family'; endif
    if (!any(strcmp(presentation_orientation,{'x_by_family','family_by_x'})))
      error('curvefit.family_global: invalid presentation_orientation: %s',presentation_orientation);
    endif
    [statistical_context,publication_units]=curvefit_family_context(cfg,x_name,fam_name,y_name,presentation_orientation);

    if (strcmp(operation_mode,'fit'))
      progress_stage_safe('preparing_fit','Preparing fit','indeterminate',0);
      % Generic bounded least squares belongs to the public numerical service.
      theta0 = parse_num_list(ini_get(cfg,'model.param_initial',''));
      lb = parse_num_list(ini_get(cfg,'model.param_lower',''));
      ub = parse_num_list(ini_get(cfg,'model.param_upper',''));
      if (isempty(theta0) || numel(theta0) != numel(lb) || numel(theta0) != numel(ub)), error('Invalid model parameter vectors'); endif
      if (numel(theta0) != numel(base_param_names)), error('Model parameter names and vectors have inconsistent lengths'); endif
      [theta0,lb,ub,fixed_mask]=curvefit_family_parameter_vectors(cfg,parameter_plan,theta0,lb,ub);
      parameter_plan.fixed_mask=fixed_mask;

      solver = lower(strtrim(ini_get(cfg,'config.solver','auto')));
      max_iter = str2double(ini_get(cfg,'config.max_iter','2000')); if (!isfinite(max_iter) || max_iter < 1), max_iter=2000; endif
      tol = str2double(ini_get(cfg,'config.tolerance','1e-8')); if (!isfinite(tol) || tol <= 0), tol=1e-8; endif

      progress_stage_safe('optimizing','Optimizing model parameters','indeterminate',0);
      fit_opts=struct('solver',solver,'lower_bounds',lb(:),'upper_bounds',ub(:),'fixed_mask',fixed_mask, ...
                      'max_iterations',round(max_iter),'tolerance',tol, ...
                      'bounded_fminsearch','penalty_clip','fallback_on_solver_error',strcmp(solver,'auto'));
      fit_model=@(th,predictors) curvefit_family_parameter_evaluate(model_fun,parameter_plan,th,predictors(:,1),predictors(:,2));
      fit_result=feval(numeric_fn,'nonlinear_fit',fit_model,[x(:),family(:)],y(:),theta0(:),fit_opts);
      theta=fit_result.parameters(:)';
      resnorm=fit_result.sse;
      solver_used=fit_result.solver;

      parameter_source = 'optimized';
      parameter_source_detail = ['solver:' solver_used];
      parameters_optimized = fit_result.free_parameter_count>0;
      if(!parameters_optimized),parameter_source='fixed_initial';parameter_source_detail='no_optimizer_all_parameters_fixed';endif
      training_domain = build_training_domain(x,family,y,x_name,fam_name,model_id);
      if(strcmp(training_domain.domain_type,'convex_hull'))
        training_domain_source = fullfile(outdir,'fit_domain.csv');
      else
        training_domain_source = 'unavailable';
      endif
    else
      progress_stage_safe('preparing_fit','Preparing evaluation with frozen parameters','indeterminate',0);
      % Evaluate/Validate path: frozen parameters only. No solver configuration is read.
      parameter_source = lower(strtrim(ini_get(cfg,'config.parameter_source','manual')));
      if (!any(strcmp(parameter_source,{'manual','csv'})))
        error('curvefit.family_global: invalid parameter_source: %s',parameter_source);
      endif
      if (strcmp(parameter_source,'manual'))
        theta = parse_num_list(ini_get(cfg,'config.fixed_parameter_values',''));
        validate_fixed_parameter_vector(theta,param_names,'manual frozen parameters');
        parameter_source_detail = 'manual';
      else
        raw_parameter_path = strtrim(ini_get(cfg,'config.parameter_csv_path',''));
        parameter_path = resolve_parameter_path(raw_parameter_path,config_path,outdir);
        ps = gxtxt_read_parameter_set(parameter_path,{},model_id);
        [parameter_plan,theta]=curvefit_family_parameter_replay_plan(cfg,base_param_names,family,ps,model_id);
        param_names=parameter_plan.slot_ids;
        validate_fixed_parameter_vector(theta,param_names,'parameter CSV');
        parameter_source_detail = parameter_path;
        domain_candidate = fullfile(fileparts(parameter_path),'fit_domain.csv');
        if (exist(domain_candidate,'file') == 2)
          try
            shared_domain = gxtxt_read_model_domain(domain_candidate,{'x','family'},model_id);
            training_domain = enrich_training_domain(shared_domain,x_name,fam_name,NaN,[]);
            training_domain_source = domain_candidate;
          catch domain_err
            if(is_legacy_curvefit_domain_file(domain_candidate))
              warning('curvefit.family_global: legacy pre-v0.7.8 fit_domain.csv ignored; domain classification unavailable');
            else
              rethrow(domain_err);
            endif
          end_try_catch
        endif
      endif
      solver_used = 'none';
      parameters_optimized = false;
    endif

    progress_stage_safe('computing_predictions','Computing model predictions','indeterminate',0);
    % The mathematical model always receives physical model inputs in this order.
    % presentation_orientation never swaps these arguments.
    pred = curvefit_family_parameter_evaluate(model_fun,parameter_plan,theta,x,family);
    pred = pred(:);
    if (numel(pred) != numel(y)), error('curvefit.family_global: model output length does not match dataset'); endif
    if (!isreal(pred)||any(!isfinite(pred))), error('curvefit.family_global: model must produce finite real predictions'); endif
    if(!strcmp(model_source_sha256,hash('sha256',fileread(model_script))))
      error('curvefit.family_global: mathematical model source changed during execution; no result was published');
    endif
    curvefit_family_recipe_guard(cfg,source_audit);
    session=strtrim(ini_get(cfg,'runtime.session',''));
    if(!isempty(session)&&!isequal(source_audit.source_identity,gxtxt_curve_source_dataset_identity_v1(session,dataset_id)))
      error('curvefit.family_global: source content or scientific schema changed during model execution; no result was published');
    endif

    progress_stage_safe('computing_metrics','Computing residuals and metrics','indeterminate',0);
    resid = pred-y;
    global_metrics=feval(numeric_fn,'residual_metrics',y,pred,struct());
    if (strcmp(operation_mode,'evaluate')), resnorm=global_metrics.sse; endif
    statistical_provenance=struct('producer','curvefit.family_global','mathematical_model_id',model_id,'mathematical_model_source_sha256',model_source_sha256, ...
      'source_dataset_id',dataset_id,'operation_mode',operation_mode,'source_audit',rmfield(source_audit,'source_row_ordinals'),'parameter_map',parameter_plan,'parameter_values',theta);
    source_row_ordinals=source_audit.source_row_ordinals;
    statistical_results=struct();
    if(strcmp(operation_mode,'fit'))
      fit_result.model=struct('parameter_ids',{param_names},'parameter_units',{parameter_plan.slot_units});
      training_context=statistical_context;training_context.sample_role='training';
      statistical_results.global=gxtxt_statistics_v1('from_numeric','math.numeric.nonlinear','nonlinear_fit',fit_result,training_context,global_metrics,statistical_provenance);
    else
      statistical_results.global=gxtxt_statistics_v1('from_numeric','math.numeric.comparison','residual_metrics',global_metrics,statistical_context,struct(),statistical_provenance);
    endif
    global_values=gxtxt_statistics_values_v1(statistical_results.global);
    rmse=global_values.rmse;mae=global_values.mae;
    r2=global_values.r_squared;if(strcmp(operation_mode,'evaluate')),r2=global_values.centered_comparison_score;endif

    minimum_abs_y_for_relative_error = str2double(ini_get(cfg,'config.minimum_abs_y_for_relative_error','1e-12'));
    if (!isfinite(minimum_abs_y_for_relative_error) || minimum_abs_y_for_relative_error < 0)
      minimum_abs_y_for_relative_error = 1e-12;
    endif
    relative_error_mask = (abs(y) >= minimum_abs_y_for_relative_error) & (y != 0);
    relative_residual_percent = NaN(size(y));
    relative_residual_percent(relative_error_mask) = 100 .* resid(relative_error_mask) ./ y(relative_error_mask);

    progress_stage_safe('classifying_domain','Classifying training-domain membership','indeterminate',0);
    % Domain classification always uses the mathematical-model input order (x,family),
    % never the presentation orientation and never measured Y.
    [domain_role,domain_role_code] = classify_training_domain_shared(x,family,training_domain);
    domain_metrics = compute_domain_metrics(y,pred,domain_role_code,numeric_fn,global_metrics);

    [horizontal,group,horizontal_name,group_name] = presentation_view(x,family,x_name,fam_name,presentation_orientation);
    group_metrics = curvefit_family_group_metrics(group,y,pred,numeric_fn);
    group_domain_metrics = compute_group_domain_metrics(group,y,pred,domain_role_code,numeric_fn,group_metrics);
    domain_provenance=statistical_provenance;domain_provenance.domain_roles=domain_metrics.domain_role;
    [domain_records,domain_metrics]=curvefit_family_statistics(domain_metrics,statistical_context,domain_provenance,'domain');
    group_provenance=statistical_provenance;group_provenance.presentation_orientation=presentation_orientation;group_provenance.group_values=group_metrics.group_value;
    [group_records,group_metrics]=curvefit_family_statistics(group_metrics,statistical_context,group_provenance,'group');
    cross_provenance=group_provenance;cross_provenance.group_values=group_domain_metrics.group_value;cross_provenance.domain_roles=group_domain_metrics.domain_role;
    [cross_records,group_domain_metrics]=curvefit_family_statistics(group_domain_metrics,statistical_context,cross_provenance,'group_domain');
    for part={domain_records,group_records,cross_records}
      for name=fieldnames(part{1})',statistical_results.(name{1})=part{1}.(name{1});endfor
    endfor
    metadata=gxtxt_statistics_v1('publication_metadata',statistical_results);
    f=fopen(fullfile(outdir,'fit_statistics.tcldict'),'w');if(f<0),error('Cannot write statistical metadata');endif
    fprintf(f,'%s\n',metadata);fclose(f);
    % Legacy cache/output name retained for compatibility; values follow active presentation grouping.
    family_metrics = group_metrics;

    progress_stage_safe('building_render_cache','Building render cache','indeterminate',0);
    X=x; Y_measured=y; Y_fitted=pred; Y_predicted=pred; residual=resid;
    parameters_used=theta;
    [family_unit,~,~]=gxtxt_analysis_source_variable_meta(cfg,'primary',fam_name);
    parameter_state=struct('plan',parameter_plan,'values',theta,'operation_mode',operation_mode,'family_unit',family_unit);
    domain_model_x_min=min(x); domain_model_x_max=max(x);
    domain_model_family_min=min(family); domain_model_family_max=max(family);
    domain_measured_y_min=min(y); domain_measured_y_max=max(y);
    training_domain_type=training_domain.domain_type;
    training_domain_vertices=training_domain.vertices;
    training_domain_model_id=training_domain.model_id;
    training_domain_model_x_name=training_domain.model_x_name;
    training_domain_model_family_name=training_domain.model_family_name;
    training_domain_tolerance=training_domain.tolerance_norm;
    save(fullfile(outdir,'render_cache.mat'),'x','family','y','pred','X','Y_measured','Y_fitted','Y_predicted','resid','residual', ...
         'source_audit','source_row_ordinals','parameter_plan','parameter_state','base_param_names','model_source_sha256','statistical_results','statistical_context','statistical_provenance','publication_units','global_metrics','relative_error_mask','relative_residual_percent','minimum_abs_y_for_relative_error','family_metrics','group_metrics', ...
         'group_domain_metrics','domain_metrics','domain_role','domain_role_code', ...
         'training_domain_type','training_domain_vertices','training_domain_source','training_domain_model_id', ...
         'training_domain_model_x_name','training_domain_model_family_name','training_domain_tolerance', ...
         'horizontal','group','horizontal_name','group_name','presentation_orientation','operation_mode', ...
         'parameter_source','parameter_source_detail','parameters_optimized','parameters_used', ...
         'theta','param_names','model_id','dataset_id','solver_used','rmse','mae','r2','x_name','fam_name','y_name', ...
         'domain_model_x_min','domain_model_x_max','domain_model_family_min','domain_model_family_max','domain_measured_y_min','domain_measured_y_max');

    session=strtrim(ini_get(cfg,'runtime.session',''));
    if(!isempty(session))
      progress_stage_safe('rendering_graphs','Publishing and rendering public Plot Variants','indeterminate',0);
      graph_data=curvefit_family_publish(session,dataset_id,horizontal,group,y,pred,resid,relative_residual_percent,group_metrics,statistical_results,publication_units,source_audit,parameter_state);
      % Retain the exact bounded CORE commit receipts, not a later registry read.
      % These are UTF-8 bytes already serialized by CORE, not scientific arrays.
      for name=fieldnames(graph_data.publications)'
        path=fullfile(outdir,['publication_' name{1} '.tcldict']);fid=fopen(path,'wb');
        if(fid<0),error('curvefit.family_global: cannot retain publication receipt');endif
        unwind_protect
          fwrite(fid,uint8(graph_data.publications.(name{1})),'uint8');
        unwind_protect_cleanup
          fclose(fid);
        end_unwind_protect
      endfor
      curvefit_family_render_public(outdir,cfg,graph_data,horizontal_name,group_name,y_name,operation_mode);
    endif

    domain_available = strcmp(training_domain.domain_type,'convex_hull');
    output_total = 6 + double(domain_available);
    progress_stage_safe('writing_outputs','Writing scientific outputs','determinate',output_total);
    output_done=0;
    parameter_model_id='';if(parameter_plan.has_local),parameter_model_id=model_id;endif
    write_parameters(fullfile(outdir,'fit_parameters.csv'),param_names,theta,parameter_model_id); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');
    if (domain_available)
      write_fit_domain(fullfile(outdir,'fit_domain.csv'),training_domain); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');
    else
      remove_if_exists(fullfile(outdir,'fit_domain.csv'));
    endif
    write_predictions(fullfile(outdir,'fit_predictions.csv'),x,family,y,pred,resid,relative_residual_percent,relative_error_mask, ...
                      domain_role,x_name,fam_name,y_name,operation_mode); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');
    write_metrics_by_family(fullfile(outdir,'fit_metrics_by_family.csv'),group_metrics); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');
    write_metrics_by_domain(fullfile(outdir,'fit_metrics_by_domain.csv'),domain_metrics); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');
    write_metrics_by_family_domain(fullfile(outdir,'fit_metrics_by_family_domain.csv'),group_domain_metrics); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');
    write_summary(fullfile(outdir,'fit_summary.txt'),cfg,operation_mode,parameter_source,parameter_source_detail,parameters_optimized, ...
                  solver_used,statistical_results,param_names,theta, ...
                  x_name,fam_name,y_name,presentation_orientation,horizontal_name,group_name,x,family,y, ...
                  training_domain,training_domain_source,domain_metrics,source_audit,parameter_plan); output_done++; progress_update_safe(output_done,output_total,'writing_outputs','Writing scientific outputs');

    fprintf('[curvefit.family_global] mode=%s rows=%d solver=%s\n%s\n',operation_mode,numel(y),solver_used,gxtxt_statistics_v1('report',statistical_results.global,{'rmse','mae','r_squared','centered_comparison_score'}));
    progress_complete_safe('completed','Curve fitting analysis completed');
  catch err
    progress_fail_safe('failed','Curve fitting module failed; see log for details');
    rethrow(err);
  end_try_catch
endfunction

function v = arg_value(args,key,def)
  v=def;
  for k=1:numel(args)-1
    if (strcmp(args{k},key)), v=args{k+1}; return; endif
  endfor
endfunction

function d = read_ini(path)
  d=struct(); sec=''; fid=fopen(path,'r'); if(fid<0), error('Cannot open INI: %s',path); endif
  unwind_protect
    while (true)
      line=fgetl(fid); if(!ischar(line)), break; endif
      line=strtrim(line); if(isempty(line) || line(1)==';' || line(1)=='#'), continue; endif
      tok=regexp(line,'^\[(.+)\]$','tokens','once');
      if(!isempty(tok)), sec=tok{1}; continue; endif
      eq=find(line=='=',1); if(isempty(eq)), continue; endif
      key=strtrim(line(1:eq-1)); val=line(eq+1:end);
      sk=make_key([sec '.' key]); d.(sk)=ini_unescape(val);
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function k = make_key(s), k=regexprep(s,'[^A-Za-z0-9_]','_'); if(isempty(k)||!isletter(k(1))), k=['k_' k]; endif; endfunction
function s = ini_unescape(s), s=strrep(s,'\\n',sprintf('\n')); s=strrep(s,'\\r',sprintf('\r')); s=strrep(s,'\\\\','\\'); endfunction
function v = ini_get(d,key,def), k=make_key(key); if(isfield(d,k)), v=d.(k); else v=def; endif; endfunction
function a = split_semicolon(s), if(isempty(strtrim(s))), a={}; else a=strsplit(s,';'); a=cellfun(@strtrim,a,'UniformOutput',false); endif; endfunction
function v = parse_num_list(s), c=split_semicolon(s); v=zeros(1,numel(c)); for i=1:numel(c), v(i)=str2double(c{i}); endfor; endfunction

function name = resolved_binding(cfg,role,model_key,def)
  name=strtrim(ini_get(cfg,['bindings.' role],''));
  if (isempty(name)), name=strtrim(ini_get(cfg,model_key,def)); endif
  if (isempty(name)), name=def; endif
  % Public Analysis Source bindings are role-qualified; the CSV header is not.
  if (strncmp(name,'primary.',8)), name=name(9:end); endif
endfunction

function validate_fixed_parameter_vector(theta,names,source_label)
  if (numel(theta) != numel(names))
    error('curvefit.family_global: %s has %d values but selected model requires %d parameters',source_label,numel(theta),numel(names));
  endif
  if (isempty(theta) || any(!isfinite(theta)))
    error('curvefit.family_global: %s contains missing or non-numeric values',source_label);
  endif
endfunction

function path = resolve_parameter_path(raw,config_path,outdir)
  raw=strtrim(raw);
  if (isempty(raw)), error('curvefit.family_global: parameter_csv_path is required when parameter_source=csv'); endif
  candidates={};
  if (is_absolute_path(raw))
    candidates={raw};
  else
    candidates={fullfile(fileparts(config_path),raw), fullfile(outdir,raw), raw};
  endif
  path='';
  for i=1:numel(candidates)
    if (exist(candidates{i},'file') == 2), path=candidates{i}; return; endif
  endfor
  error('curvefit.family_global: parameter CSV not found: %s',raw);
endfunction

function b = is_absolute_path(path)
  b = (!isempty(path) && path(1)=='/') || !isempty(regexp(path,'^[A-Za-z]:[\\\\/]','once'));
endfunction

function d = empty_training_domain(xname,fname,model_id,training_n,y)
  d=struct();
  d.kind='unavailable'; d.domain_type='unavailable'; d.model_id=model_id;
  d.input_names={'x','family'}; d.model_x_name=xname; d.model_family_name=fname;
  d.x_min=NaN; d.x_max=NaN; d.family_min=NaN; d.family_max=NaN;
  if(nargin>=5 && !isempty(y)),d.measured_y_min=min(y);d.measured_y_max=max(y);else d.measured_y_min=NaN;d.measured_y_max=NaN;endif
  d.training_n=training_n; d.vertices=zeros(0,2); d.tolerance_norm=NaN;
endfunction

function d = build_training_domain(x,f,y,xname,fname,model_id)
  d=empty_training_domain(xname,fname,model_id,numel(x),y);
  d.x_min=min(x); d.x_max=max(x); d.family_min=min(f); d.family_max=max(f);
  pts=unique([x(:) f(:)],'rows');
  if(rows(pts)<3 || !(d.x_max>d.x_min) || !(d.family_max>d.family_min)), return; endif
  try
    k=convhull(pts(:,1),pts(:,2));
  catch
    return;
  end_try_catch
  if(numel(k)>=2 && k(1)==k(end)),k=k(1:end-1);endif
  if(numel(k)<3),return;endif
  d.kind='convex_hull'; d.domain_type='convex_hull'; d.vertices=pts(k,:);
  % Use the shared v0.7.8 validator for the persisted mathematical-model domain.
  d=gxtxt_validate_model_domain(d,{'x','family'},model_id);
  d.domain_type='convex_hull';
endfunction

function d = enrich_training_domain(shared,xname,fname,training_n,y)
  d=shared;
  d.kind='convex_hull'; d.domain_type='convex_hull';
  d.model_x_name=xname; d.model_family_name=fname;
  if(rows(d.vertices)>0)
    d.x_min=min(d.vertices(:,1)); d.x_max=max(d.vertices(:,1));
    d.family_min=min(d.vertices(:,2)); d.family_max=max(d.vertices(:,2));
  else
    d.x_min=NaN; d.x_max=NaN; d.family_min=NaN; d.family_max=NaN;
  endif
  if(nargin>=5 && !isempty(y)),d.measured_y_min=min(y);d.measured_y_max=max(y);else d.measured_y_min=NaN;d.measured_y_max=NaN;endif
  d.training_n=training_n; d.tolerance_norm=NaN;
endfunction

function write_fit_domain(path,d)
  if(!strcmp(d.domain_type,'convex_hull'))
    error('curvefit.family_global: refusing to write unavailable/invalid model domain');
  endif
  % Validate immediately before persistence using the shared v0.7.8 API.
  d=gxtxt_validate_model_domain(d,{'x','family'},d.model_id);
  fid=fopen(path,'w'); if(fid<0),error('Cannot write %s',path);endif
  unwind_protect
    if(!isempty(d.model_id)),fprintf(fid,'# model_id=%s\n',d.model_id);endif
    fprintf(fid,'# domain_kind=convex_hull\n');
    fprintf(fid,'%s,%s\n',d.input_names{1},d.input_names{2});
    for i=1:rows(d.vertices),fprintf(fid,'%.17g,%.17g\n',d.vertices(i,1),d.vertices(i,2));endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function [roles,codes] = classify_training_domain_shared(x,f,d)
  n=numel(x); codes=zeros(n,1); roles=repmat({'unknown'},n,1);
  if(!strcmp(d.domain_type,'convex_hull') || rows(d.vertices)<3),return;endif
  [inside,~]=gxtxt_classify_model_domain(d,[x(:) f(:)],[]);
  inside=logical(inside(:));
  codes(inside)=1; codes(!inside)=2;
  ii=find(codes==1); oo=find(codes==2);
  if(!isempty(ii)),roles(ii)=repmat({'in_domain'},numel(ii),1);endif
  if(!isempty(oo)),roles(oo)=repmat({'out_of_domain'},numel(oo),1);endif
endfunction

function tf=is_legacy_curvefit_domain_file(path)
  tf=false; fid=fopen(path,'r'); if(fid<0),return;endif
  unwind_protect
    while(true)
      line=fgetl(fid);if(!ischar(line)),break;endif
      t=strtrim(line);if(isempty(t)||t(1)=='#'||t(1)==';'),continue;endif
      tf=!isempty(regexp(lower(t),'^record_type\s*,\s*key\s*,\s*value\s*,','once'));
      break;
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function remove_if_exists(path)
  if(exist(path,'file')==2),unlink(path);endif
endfunction

function metrics=compute_domain_metrics(y,pred,codes,numeric_fn,all_metrics)
  roles={'all','in_domain','out_of_domain','unknown'};
  metrics=init_metric_table(roles);
  masks={true(size(codes)),codes==1,codes==2,codes==0};
  for i=1:numel(roles)
    if(i==1),m=all_metrics;else m=[];endif
    metrics=assign_metric(metrics,i,y,pred,masks{i},numeric_fn,m);
  endfor
endfunction

function metrics=init_metric_table(roles)
  n=numel(roles); metrics=struct(); metrics.domain_role=roles(:); metrics.n=zeros(n,1); metrics.sse=NaN(n,1); metrics.rmse=NaN(n,1); metrics.mae=NaN(n,1); metrics.max_abs_error=NaN(n,1); metrics.r2=NaN(n,1);metrics.response_variance=NaN(n,1);
endfunction

function metrics=assign_metric(metrics,i,y,pred,mask,numeric_fn,m)
  idx=find(mask); n=numel(idx); metrics.n(i)=n; if(n==0),return;endif
  if(isempty(m)),m=feval(numeric_fn,'residual_metrics',y(idx),pred(idx),struct());endif
  metrics.sse(i)=m.sse;metrics.rmse(i)=m.rmse;metrics.mae(i)=m.mae;
  metrics.max_abs_error(i)=m.max_abs_error;metrics.r2(i)=m.r2;metrics.response_variance(i)=m.response_variance;
endfunction

function metrics=compute_group_domain_metrics(g,y,pred,codes,numeric_fn,group_metrics)
  groups=unique(g); roles={'all','in_domain','out_of_domain','unknown'}; nr=numel(groups)*numel(roles);
  metrics=struct(); metrics.group_value=zeros(nr,1); metrics.domain_role=cell(nr,1); metrics.n=zeros(nr,1); metrics.sse=NaN(nr,1); metrics.rmse=NaN(nr,1); metrics.mae=NaN(nr,1); metrics.max_abs_error=NaN(nr,1); metrics.r2=NaN(nr,1);metrics.response_variance=NaN(nr,1);
  row=0;
  for k=1:numel(groups)
    base=(g==groups(k));
    masks={base,base&(codes==1),base&(codes==2),base&(codes==0)};
    for j=1:numel(roles)
      row=row+1; metrics.group_value(row)=groups(k); metrics.domain_role{row}=roles{j};
      m=[];if(j==1),m=struct();for name={'n','sse','rmse','mae','max_abs_error','r2','response_variance'},m.(name{1})=group_metrics.(name{1})(k);endfor;endif
      tmp=init_metric_table({roles{j}}); tmp=assign_metric(tmp,1,y,pred,masks{j},numeric_fn,m);
      metrics.n(row)=tmp.n(1);metrics.sse(row)=tmp.sse(1);metrics.rmse(row)=tmp.rmse(1);metrics.mae(row)=tmp.mae(1);metrics.max_abs_error(row)=tmp.max_abs_error(1);metrics.r2(row)=tmp.r2(1);metrics.response_variance(row)=tmp.response_variance(1);
    endfor
  endfor
endfunction

function write_metrics_by_domain(path,metrics)
  curvefit_family_metric_csv(path,metrics,{'domain_role'},{'n','sse','rmse','mae','r2'});
endfunction
function write_metrics_by_family_domain(path,metrics)
  curvefit_family_metric_csv(path,metrics,{'group_value','domain_role'},{'n','sse','rmse','mae','max_abs_error','r2'});
endfunction


function [h,g,hname,gname] = presentation_view(x,f,xname,fname,orientation)
  if (strcmp(orientation,'family_by_x'))
    h=f; g=x; hname=fname; gname=xname;
  else
    h=x; g=f; hname=xname; gname=fname;
  endif
endfunction

function write_parameters(path,names,theta,model_id)
  fid=fopen(path,'w'); if(fid<0), error('Cannot write %s',path); endif
  if(!isempty(model_id)),fprintf(fid,'# model_id=%s\n# family_parameter_schema=gxtxt.family_parameters.v1\n',model_id);endif
  fprintf(fid,'parameter,value\n');
  for i=1:numel(theta), if(i<=numel(names)), n=names{i}; else n=sprintf('p%d',i); endif; fprintf(fid,'%s,%.17g\n',n,theta(i)); endfor
  fclose(fid);
endfunction

function write_predictions(path,x,f,y,p,r,rel,relmask,domain_role,xname,fname,yname,operation_mode)
  fid=fopen(path,'w'); if(fid<0), error('Cannot write %s',path); endif
  unwind_protect
    if (strcmp(operation_mode,'fit'))
      % Preserve historical fit output schema exactly.
      fprintf(fid,'%s,%s,%s,Y_fitted,residual\n',xname,fname,yname);
      for i=1:numel(y), fprintf(fid,'%.17g,%.17g,%.17g,%.17g,%.17g\n',x(i),f(i),y(i),p(i),r(i)); endfor
    else
      fprintf(fid,'%s,%s,%s,Y_predicted,residual,relative_residual_percent,domain_role\n',xname,fname,yname);
      for i=1:numel(y)
        fprintf(fid,'%.17g,%.17g,%.17g,%.17g,%.17g,',x(i),f(i),y(i),p(i),r(i));
        if (relmask(i)), fprintf(fid,'%.17g,',rel(i)); else fprintf(fid,','); endif
        fprintf(fid,'%s\n',domain_role{i});
      endfor
    endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction


function write_metrics_by_family(path,metrics)
  curvefit_family_metric_csv(path,metrics,{'family_value'},{'n','sse','rmse','mae','max_abs_error','r2'});
endfunction

function write_summary(path,cfg,operation_mode,parameter_source,parameter_source_detail,parameters_optimized, ...
                       solver,statistical_results,names,theta,xname,fname,yname,orientation,hname,gname,x,f,y, ...
                       training_domain,training_domain_source,domain_metrics,source_audit,parameter_plan)
  fid=fopen(path,'w'); if(fid<0), error('Cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'GX-TXT Curve Family Fitting\n');
    fprintf(fid,'Module: %s\n',ini_get(cfg,'runtime.module_id',''));
    fprintf(fid,'Dataset: %s\n',ini_get(cfg,'dataset.id',''));
    fprintf(fid,'Model: %s\n',ini_get(cfg,'model.id',''));
    fprintf(fid,'Bindings: x=%s, family=%s, y=%s\n',xname,fname,yname);
    fprintf(fid,'Source rows: %d; used: %d; omitted: %d; missing: %d\n',source_audit.row_count,source_audit.used_row_count,source_audit.omitted_row_count,source_audit.missing_row_count);
    fprintf(fid,'Source row policy: %s; exact zero-based ordinals retained in render_cache.mat\n',source_audit.row_policy);
    if(isstruct(source_audit.source_identity)),fprintf(fid,'Source SHA256: %s\nScientific schema identity: %s\n',source_audit.source_identity.sha256,source_audit.source_identity.schema_identity);endif
    fprintf(fid,'Operation mode: %s\n',operation_mode);
    fprintf(fid,'Parameters optimized: %s\n',bool_text(parameters_optimized));
    fprintf(fid,'Parameter source: %s\n',parameter_source);
    fprintf(fid,'Parameter source detail: %s\n',parameter_source_detail);
    fprintf(fid,'Parameter mapping: %s\n',parameter_plan.schema);
    for i=1:numel(parameter_plan.base_parameter_ids)
      fprintf(fid,'  Original model parameter %s: %s\n',parameter_plan.base_parameter_ids{i},parameter_plan.scopes{i});
    endfor
    if(parameter_plan.has_local)
      fprintf(fid,'Local parameter identities explicitly qualify physical family values; all estimates belong to one joint fit.\n');
    endif
    fprintf(fid,'Presentation orientation: %s\n',orientation);
    fprintf(fid,'Presentation horizontal: %s\n',hname);
    fprintf(fid,'Presentation group: %s\n',gname);
    if (strcmp(operation_mode,'fit')), fprintf(fid,'Solver: %s\n',solver); else fprintf(fid,'Solver: not used\n'); endif
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistical_results.global,{'n','sse','rmse','mae','r_squared','centered_comparison_score','dof','covariance'}));
    fprintf(fid,'Evaluated model X range: %.17g .. %.17g\n',min(x),max(x));
    fprintf(fid,'Evaluated model family range: %.17g .. %.17g\n',min(f),max(f));
    fprintf(fid,'Measured Y range: %.17g .. %.17g\n',min(y),max(y));
    fprintf(fid,'Training domain: %s\n',training_domain.domain_type);
    fprintf(fid,'Training domain source: %s\n',training_domain_source);
    if (strcmp(training_domain.domain_type,'convex_hull'))
      if(isfinite(training_domain.training_n)),fprintf(fid,'Training points: %d\n',training_domain.training_n);else fprintf(fid,'Training points: unavailable\n');endif
      fprintf(fid,'Training model X range: %.17g .. %.17g\n',training_domain.x_min,training_domain.x_max);
      fprintf(fid,'Training model family range: %.17g .. %.17g\n',training_domain.family_min,training_domain.family_max);
    else
      fprintf(fid,'Domain classification: unavailable\n');
    endif

    if (strcmp(operation_mode,'evaluate'))
      fprintf(fid,'Total points: %d\n',domain_metric_n(domain_metrics,'all'));
      fprintf(fid,'In-domain points: %d\n',domain_metric_n(domain_metrics,'in_domain'));
      fprintf(fid,'Out-of-domain points: %d\n',domain_metric_n(domain_metrics,'out_of_domain'));
      fprintf(fid,'Unknown-domain points: %d\n',domain_metric_n(domain_metrics,'unknown'));
      write_summary_metric_block(fid,'ALL DATA',statistical_results.domain_block_0001,'domain_000001');
      write_summary_metric_block(fid,'IN-DOMAIN VALIDATION',statistical_results.domain_block_0001,'domain_000002');
      write_summary_metric_block(fid,'OUT-OF-DOMAIN EXTRAPOLATION',statistical_results.domain_block_0001,'domain_000003');
    endif

    fprintf(fid,'Parameters:\n');
    for i=1:numel(theta), if(i<=numel(names)), nm=names{i}; else nm=sprintf('p%d',i); endif; fprintf(fid,'  %s = %.17g\n',nm,theta(i)); endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_summary_metric_block(fid,title_txt,table,role)
  fprintf(fid,'\n%s\n%s\n',title_txt,gxtxt_statistics_v1('table_report',table,{role},{'n','rmse','mae','centered_comparison_score'}));
endfunction

function n=domain_metric_n(metrics,role)
  idx=find(strcmp(metrics.domain_role,role),1); if(isempty(idx)),n=0;else n=metrics.n(idx);endif
endfunction


function s = bool_text(b), if(b), s='yes'; else s='no'; endif; endfunction

function progress_start_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_start','file')!=2),return;endif
  try
    if(strcmp(mode,'determinate'))
      gxtxt_progress_start(stage,message,mode,total);
    else
      gxtxt_progress_start(stage,message,mode);
    endif
  catch
  end_try_catch
endfunction

function progress_stage_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_stage','file')!=2),return;endif
  try
    if(strcmp(mode,'determinate'))
      gxtxt_progress_stage(stage,message,mode,total);
    else
      gxtxt_progress_stage(stage,message,mode);
    endif
  catch
  end_try_catch
endfunction

function progress_update_safe(current,total,stage,message)
  if(exist('gxtxt_progress_update','file')!=2 || total<=0),return;endif
  try
    gxtxt_progress_update(current,total,stage,message);
  catch
  end_try_catch
endfunction

function progress_complete_safe(stage,message)
  if(exist('gxtxt_progress_complete','file')!=2),return;endif
  try
    gxtxt_progress_complete(stage,message);
  catch
  end_try_catch
endfunction

function progress_fail_safe(stage,message)
  if(exist('gxtxt_progress_fail','file')!=2),return;endif
  try
    gxtxt_progress_fail(stage,message);
  catch
  end_try_catch
endfunction
