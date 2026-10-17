function analysis_regression_main(args,framework_root)
% Production linear/polynomial regression through public GX-TXT services.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.regression';version='1.1.0';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  execution=struct('script_name',module_id,'script_sha256',hash('sha256',fileread([mfilename('fullpath') '.m'])),'arguments_raw','');
  gxtxt_script_bridge_start(config_path,execution);
  bridge_cleanup=onCleanup(@() gxtxt_script_bridge_stop());
  gxtxt_progress_start('prepare','Preparing regression','indeterminate');
  try
    [x_id,x_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.x_variable',''));
    [y_id,y_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.y_variable',''));
    if(strcmp(x_id,y_id)),error('%s: X and Y variables must differ',module_id);endif
    if(isempty(x_unit)||isempty(y_unit)),error('%s: X/Y units are required; use 1 for dimensionless data',module_id);endif
    fit_model=lower(strtrim(gxtxt_ini_get(cfg,'config.fit_model','linear')));
    if(!any(strcmp(fit_model,{'linear','polynomial'}))),error('%s: fit model must be linear or polynomial',module_id);endif
    degree=1;if(strcmp(fit_model,'polynomial'))
      degree=str2double(gxtxt_ini_get(cfg,'config.polynomial_degree','2'));
      if(!isfinite(degree)||degree<1||degree>20||degree!=fix(degree))
        error('%s: polynomial degree must be an integer from 1 to 20',module_id);
      endif
    endif
    weight_model=lower(strtrim(gxtxt_ini_get(cfg,'config.weight_model','none')));
    if(!any(strcmp(weight_model,{'none','statistical_weight','inverse_variance_uncertainty'})))
      error('%s: select explicit weight semantics',module_id);
    endif
    weight_id='';weight_unit='';ids={x_id,y_id};
    token=strtrim(gxtxt_ini_get(cfg,'config.weight_variable',''));
    if(strcmp(weight_model,'none'))
      if(!isempty(token)),error('%s: weight variable is set while weight model is none',module_id);endif
    else
      if(isempty(token)),error('%s: selected weight model requires a weight or uncertainty variable',module_id);endif
      [weight_id,weight_unit]=resolve_numeric(cfg,source_id,token);
      if(any(strcmp(weight_id,ids))),error('%s: weight variable must differ from X and Y',module_id);endif
      ids{end+1}=weight_id;
    endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    rank_policy=lower(strtrim(gxtxt_ini_get(cfg,'config.rank_policy','error')));
    if(!any(strcmp(rank_policy,{'error','minimum_norm'}))),error('%s: invalid rank policy',module_id);endif
    prefix=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_prefix','analysis.regression'));
    if(isempty(regexp(prefix,'^[A-Za-z0-9_.-]+$','once'))||strcmp(prefix,source_id))
      error('%s: invalid output Dataset prefix',module_id);
    endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected regression variables','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',ids,selection,65536);
    if(rows(matrix)<degree+1),error('%s: insufficient selected observations for degree %d',module_id,degree);endif
    x=matrix(:,1);y=matrix(:,2);n_input=numel(x);weight=[];
    valid=isfinite(x)&isfinite(y);
    if(numel(ids)>2)
      second=matrix(:,3);valid=valid&isfinite(second);
      if(strcmp(weight_model,'statistical_weight'))
        if(!isempty(weight_unit))
          parsed=gxtxt_unit_parse(weight_unit);
          if(!strcmp(parsed.kind,'linear')||!parsed.dimensionless),error('%s: statistical weights must be dimensionless',module_id);endif
        endif
        weight=second;
        if(any(weight(isfinite(weight))<0)),error('%s: statistical weights must be nonnegative',module_id);endif
      else
        if(isempty(weight_unit)||!gxtxt_unit_compatible(weight_unit,y_unit))
          error('%s: measurement uncertainty unit must match Y',module_id);
        endif
        converted=second;finite=isfinite(second);
        if(any(finite)),converted(finite)=gxtxt_unit_convert(second(finite),weight_unit,y_unit);endif
        if(any(converted(finite)<=0)),error('%s: measurement uncertainty must be strictly positive',module_id);endif
        weight=NaN(size(second));
        if(any(finite))
          square=gxtxt_analysis_numeric_call('array_binary','power',converted(finite),2);
          inverse=gxtxt_analysis_numeric_call('array_binary','divide',1,square.values);
          weight(finite)=inverse.values;
        endif
        if(any(!isfinite(weight(finite)))||any(weight(finite)<=0)),error('%s: inverse-variance weights are outside finite range',module_id);endif
      endif
    endif
    if(strcmp(policy,'error')&&any(!valid)),error('%s: selected fit data contain NaN or Inf',module_id);endif
    n_nonfinite=sum(!valid);
    if(!isempty(weight)),positive=(weight>0);n_zero_weight=sum(valid&!positive);valid=valid&positive;
    else n_zero_weight=0;endif
    x=x(valid);y=y(valid);source_rows=source_rows(valid);
    if(!isempty(weight)),weight=weight(valid);endif
    if(numel(x)<degree+1),error('%s: insufficient valid positive-weight rows for degree %d',module_id,degree);endif
    if(numel(unique(x))<degree+1&&strcmp(rank_policy,'error'))
      error('%s: X has insufficient distinct coordinates for degree %d',module_id,degree);
    endif
    gxtxt_progress_stage('compute','Running public numerical regression','indeterminate');
    options=struct('rank_policy',rank_policy,'weight_semantics',numeric_weight_semantics(weight_model),'nonfinite','error');
    if(strcmp(fit_model,'linear'))
      options.intercept=true;fit=gxtxt_analysis_numeric_call('linear_regression',x,y,weight,options);
      powers=[0;1];
    else
      options.center_scale=true;fit=gxtxt_analysis_numeric_call('polynomial_fit',x,y,degree,weight,options);
      powers=(degree:-1:0)';
    endif
    if(numel(fit.predicted)!=numel(x)||numel(fit.residuals)!=numel(x))
      error('%s: NUMERIC_API fit output is not row-aligned',module_id);
    endif
    metrics=gxtxt_analysis_numeric_call('residual_metrics',y,fit.predicted,struct());
    context=struct('orientation','y_of_x','x_unit',x_unit,'y_unit',y_unit, ...
      'x_variable_id',x_id,'y_variable_id',y_id,'constraints','none');
    context.noise_model=gxtxt_ini_get(cfg,'config.noise_model','unspecified');
    operation='linear_regression';if(strcmp(fit_model,'polynomial')),operation='polynomial_fit';endif
    statistics=gxtxt_statistics_v1('from_numeric',['math.numeric.' fit_model],operation,fit,context,metrics,struct('producer',module_id));
    interpreted=gxtxt_statistics_values_v1(statistics);
    fit.standard_errors=interpreted.standard_errors;fit.covariance=interpreted.covariance;
    fit.r_squared=interpreted.r_squared;fit.adjusted_r_squared=interpreted.adjusted_r_squared;
    fit.reduced_chi_squared=interpreted.reduced_chi_squared;
    % Preserve the historical field ID while giving its actual meaning. The
    % descriptive n-denominator RMSE remains residual_rmse in this Dataset.
    fit.rmse=interpreted.weighted_residual_standard_deviation;
    [curve_x,order]=sort(x);curve_y=fit.predicted(order);
    coefficient_units=cell(numel(powers),1);
    for i=1:numel(powers),coefficient_units{i}=coefficient_unit(y_unit,x_unit,powers(i));endfor
    covariance_units=cell(numel(powers)^2,1);ii=zeros(numel(powers)^2,1,'int64');jj=ii;covariance_values=zeros(numel(powers)^2,1);k=0;
    for i=1:numel(powers)
      for j=1:numel(powers)
        k+=1;ii(k)=i;jj(k)=j;covariance_values(k)=fit.covariance(i,j);
        covariance_units{k}=product_unit(coefficient_units{i},coefficient_units{j});
      endfor
    endfor
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Regression', ...
      'provenance',sprintf('%s %s; source=%s; x=%s; y=%s; weight=%s; selection=%s; model=%s; degree=%d; weight_model=%s; nonfinite=%s; rank_policy=%s',module_id,version,source_id,x_id,y_id,weight_id,selection_id(selection),fit_model,degree,weight_model,policy,rank_policy), ...
      'notes','Fit and residual rows preserve one-based source-row identity; coefficient units vary by power.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids=ids;
    opts.statistical_results=struct('training',statistics);
    fit_id=[prefix '.fit'];curve_id=[prefix '.curve'];coeff_id=[prefix '.coefficients'];cov_id=[prefix '.covariance'];metrics_id=[prefix '.metrics'];
    sse_unit=squared_unit(y_unit);fit_rmse_unit=y_unit;
    if(strcmp(weight_model,'inverse_variance_uncertainty')),sse_unit='1';fit_rmse_unit='1';endif
    gxtxt_progress_stage('publish','Publishing regression Datasets','indeterminate');
    publish_table(session,module_id,fit_id,'row',opts,{ ...
      'source_row','Original one-based source row','int64','','index',int64(source_rows); ...
      'x','Independent X','float64',x_unit,'coordinate',x; ...
      'measured','Measured Y','float64',y_unit,'measurement',y; ...
      'fitted','Fitted Y','float64',y_unit,'derived',fit.predicted; ...
      'residual','Measured minus fitted','float64',y_unit,'residual',fit.residuals; ...
      'absolute_residual','Absolute residual','float64',y_unit,'derived',abs(fit.residuals)});
    publish_table(session,module_id,curve_id,'point',opts,{ ...
      'x','Sorted X','float64',x_unit,'coordinate',curve_x; ...
      'fitted','Model prediction','float64',y_unit,'derived',curve_y});
    publish_table(session,module_id,coeff_id,'coefficient',opts,{ ...
      'coefficient_index','Coefficient index','int64','','index',int64((1:numel(powers))'); ...
      'power','X power','int32','','index',int32(powers); ...
      'estimate','Coefficient estimate','float64','','derived',fit.coefficients; ...
      'standard_error','Coefficient standard error','float64','','uncertainty',fit.standard_errors; ...
      'coefficient_unit','Coefficient unit','string','','unit',coefficient_units});
    publish_table(session,module_id,cov_id,'pair',opts,{ ...
      'coefficient_i','First coefficient index','int64','','index',ii; ...
      'coefficient_j','Second coefficient index','int64','','index',jj; ...
      'covariance','Coefficient covariance','float64','','derived',covariance_values; ...
      'covariance_unit','Covariance unit','string','','unit',covariance_units});
    publish_table(session,module_id,metrics_id,'fit',opts,{ ...
      'fit_model','Fit model','string','','category',{fit_model}; ...
      'degree','Polynomial degree','int32','','index',int32(degree); ...
      'weight_model','Weight semantics','string','','category',{weight_model}; ...
      'numeric_weight_semantics','NUMERIC_API weight semantics','string','','category',{fit.weight_semantics}; ...
      'n_input','Selected row count','int64','','count',int64(n_input); ...
      'n_valid','Fitted row count','int64','','count',int64(numel(x)); ...
      'n_nonfinite','Excluded nonfinite rows','int64','','count',int64(n_nonfinite); ...
      'n_zero_weight','Excluded zero-weight rows','int64','','count',int64(n_zero_weight); ...
      'rank','Design-matrix rank','int32','','derived',int32(fit.rank); ...
      'dof','Residual degrees of freedom','int32','','derived',int32(fit.dof); ...
      'condition_number','Design condition number','float64','1','derived',fit.condition_number; ...
      'r_squared','R squared','float64','1','derived',fit.r_squared; ...
      'adjusted_r_squared','Adjusted R squared','float64','1','derived',fit.adjusted_r_squared; ...
      'rmse',statistics.quantities.weighted_residual_standard_deviation.label,'float64',fit_rmse_unit,'derived',fit.rmse; ...
      'residual_rmse','Unweighted residual RMSE','float64',y_unit,'derived',metrics.rmse; ...
      'mae','Mean absolute error','float64',y_unit,'derived',metrics.mae; ...
      'max_abs_error','Maximum absolute error','float64',y_unit,'derived',metrics.max_abs_error; ...
      'sse','Weighted sum of squared errors','float64',sse_unit,'derived',fit.sse; ...
      'reduced_chi_squared','Reduced chi squared','float64','1','derived',fit.reduced_chi_squared; ...
      'status','Fit status','string','','category',{fit.status}});
    graphs=struct('key',{},'graph_id',{},'variant_id',{},'artifact',{},'png',{});
    if(parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1')))
      gxtxt_progress_stage('graphs','Creating persistent fit and residual graphs','indeterminate');
      graphs(1)=plot_fit(session,fit_id,curve_id,x_unit,y_unit);
      graphs(2)=plot_residual(session,fit_id,x_unit,y_unit);
      for i=1:numel(graphs)
        [ok,msg]=copyfile(graphs(i).artifact,fullfile(outdir,graphs(i).png),'f');
        if(!ok),error('%s: cannot copy Plot Dataset artifact: %s',module_id,msg);endif
      endfor
    endif
    write_manifest(fullfile(outdir,'automatic_graphs.ini'),graphs);
    write_summary(fullfile(outdir,'regression_summary.ini'),source_id,x_id,y_id,weight_id,prefix,selection,fit_model,degree,weight_model,policy,rank_policy,n_input,n_nonfinite,n_zero_weight,fit.status,statistics,numel(graphs));
    write_report(fullfile(outdir,'regression_report.txt'),source_id,x_id,y_id,weight_id,x_unit,y_unit,selection,fit_model,degree,weight_model,policy,statistics);
    fid=fopen(fullfile(outdir,'statistical_results.tcldict'),'w');if(fid<0),error('Cannot write statistical result contract');endif
    unwind_protect
      fprintf(fid,'%s\n',gxtxt_statistics_v1('publication_metadata',opts.statistical_results));
    unwind_protect_cleanup
      fclose(fid);
    end_unwind_protect
    gxtxt_progress_complete('done',sprintf('Published regression fit with %d coefficients and %d graphs',numel(powers),numel(graphs)));
    fprintf('[%s] source=%s model=%s degree=%d valid=%d graphs=%d\n%s\n',module_id,source_id,fit_model,degree,numel(x),numel(graphs),gxtxt_statistics_v1('report',statistics));
  catch err
    try gxtxt_progress_fail('failed','Regression failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function [vid,unit]=resolve_numeric(cfg,source_id,token)
  [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',strtrim(token));
  if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
    error('analysis.regression: stable source variable could not be resolved');
  endif
  if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
    error('analysis.regression: source variables must be numeric');
  endif
  if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
  vid=strtrim(meta.variable_id);if(isempty(vid)),error('analysis.regression: stable variable ID is missing');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.regression: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.regression: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function semantics=numeric_weight_semantics(model)
  if(strcmp(model,'inverse_variance_uncertainty')),semantics='inverse_variance';else semantics='relative';endif
endfunction
function unit=coefficient_unit(y,x,power)
  if(power==0),unit=y;return;endif
  if(strcmp(x,'1')),unit=y;return;endif
  if(strcmp(y,'1')),unit=[x '^' num2str(-power)];return;endif
  if(power==1),unit=[y '/' x];else unit=[y '/' x '^' num2str(power)];endif
endfunction
function unit=product_unit(left,right)
  if(strcmp(left,'1')),unit=right;elseif(strcmp(right,'1')),unit=left;else unit=[left '*' right];endif
endfunction
function unit=squared_unit(base)
  if(strcmp(base,'1')),unit='1';else unit=[base '^2'];endif
endfunction
function out=parse_bool(text)
  q=lower(strtrim(text));if(any(strcmp(q,{'1','true','yes','on'}))),out=true;
  elseif(any(strcmp(q,{'0','false','no','off'}))),out=false;
  else error('analysis.regression: expected a boolean setting');endif
endfunction
function publish_table(session,module_id,dataset_id,dim,opts,variables)
  P=struct();opened=false;
  try
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,dim,0,true);
    for i=1:rows(variables)
      P=gxtxt_publication_v2_declare_variable(P,variables{i,1},struct('dtype',variables{i,3},'dimension_ids',dim, ...
        'name',variables{i,2},'unit',variables{i,4},'semantic_role',variables{i,5}));
    endfor
    P=gxtxt_publication_v2_append(P,dim,variables(:,[1,6]));
    [P,result]=gxtxt_publication_v2_finalize(P);opened=false;
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    rethrow(err);
  end_try_catch
endfunction
function graph=plot_fit(session,fit_id,curve_id,xunit,yunit)
  series={ ...
    struct('id','measured','dataset_id',fit_id,'x_variable_id','x','y_variable_id','measured','axis','left','kind','scatter','label','Measured'), ...
    struct('id','fitted','dataset_id',curve_id,'x_variable_id','x','y_variable_id','fitted','axis','left','kind','line','label','Fitted')};
  axes=struct('x',struct('label',['X (' xunit ')']),'y_left',struct('label',['Y (' yunit ')']));
  panel=struct('id','main','title','Measured and fitted','axes',axes,'series',{series});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title','Regression fit','defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
  if(!isfield(R,'artifact')||exist(R.artifact,'file')!=2),error('analysis.regression: Plot Dataset returned no fit artifact');endif
  graph=struct('key','fit','graph_id',R.graph_id,'variant_id',R.variant_id,'artifact',R.artifact,'png','regression_fit.png');
endfunction
function graph=plot_residual(session,fit_id,xunit,yunit)
  series={struct('id','residual','dataset_id',fit_id,'x_variable_id','x','y_variable_id','residual','axis','left','kind','scatter','label','Residual')};
  annotations={struct('type','reference_line','axis','left','value',0,'line_style','dotted')};
  axes=struct('x',struct('label',['X (' xunit ')']),'y_left',struct('label',['Residual (' yunit ')']));
  panel=struct('id','main','title','Residuals versus X','axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title','Regression residuals','defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
  if(!isfield(R,'artifact')||exist(R.artifact,'file')!=2),error('analysis.regression: Plot Dataset returned no residual artifact');endif
  graph=struct('key','residual','graph_id',R.graph_id,'variant_id',R.variant_id,'artifact',R.artifact,'png','regression_residual.png');
endfunction
function write_manifest(path,graphs)
  fid=fopen(path,'w');if(fid<0),error('analysis.regression: cannot write graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(graphs));
    for i=1:numel(graphs)
      g=graphs(i);fprintf(fid,'\n[graph.%02d]\nkey=regression.%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\n',i,g.key,g.graph_id,g.variant_id,g.png,g.artifact);
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_summary(path,source_id,x_id,y_id,weight_id,prefix,selection,model,degree,weight_model,policy,rank_policy,n_input,n_nonfinite,n_zero_weight,status,statistics,graphs)
  fid=fopen(path,'w');if(fid<0),error('analysis.regression: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.regression\nmodule_version=1.1.0\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nx_variable_id=%s\ny_variable_id=%s\nweight_variable_id=%s\nselection_id=%s\n',source_id,x_id,y_id,weight_id,selection_id(selection));
    fprintf(fid,'\n[fit]\nmodel=%s\ndegree=%d\nweight_model=%s\nnonfinite_policy=%s\nrank_policy=%s\nn_input=%d\nn_nonfinite=%d\nn_zero_weight=%d\nstatus=%s\n',model,degree,weight_model,policy,rank_policy,n_input,n_nonfinite,n_zero_weight,status);
    mapping=struct('n_valid','n','rank','rank','dof','dof','condition_number','condition_number','r_squared','r_squared', ...
      'adjusted_r_squared','adjusted_r_squared','rmse','weighted_residual_standard_deviation','residual_rmse','rmse','mae','mae','max_abs_error','max_abs_error');
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',statistics,mapping));
    fprintf(fid,'\n[output]\nprefix=%s\nautomatic_graph_count=%d\n',prefix,graphs);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,x_id,y_id,weight_id,xunit,yunit,selection,model,degree,weight_model,policy,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.regression: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Regression\nSource Dataset: %s\nX: %s (%s)\nY: %s (%s)\nWeight variable: %s\nSelection: %s\nModel: %s, degree %d\nWeight model: %s\nNaN / Inf: %s\n',source_id,x_id,xunit,y_id,yunit,weight_id,selection_id(selection),model,degree,weight_model,policy);
    fprintf(fid,'\n%s\n\n%s\n',gxtxt_statistics_v1('parameter_report',statistics), ...
      gxtxt_statistics_v1('report',statistics,{'n','rmse','residual_standard_deviation','mae','max_abs_error','r_squared','adjusted_r_squared','rank','dof','condition_number','reduced_chi_squared'}));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
