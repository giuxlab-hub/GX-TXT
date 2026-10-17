function analysis_statistics_weighted_main(args,framework_root)
% Weighted descriptive analysis with explicit weight and uncertainty semantics.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.weighted';version='1.1.0';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing weighted statistics','indeterminate');
  try
    [value_id,value_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.value_variable',''));
    [weight_id,weight_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.weight_variable',''));
    if(isempty(value_unit)),error('%s: measurement unit is required; use 1 for a dimensionless measurement',module_id);endif
    if(strcmp(value_id,weight_id)),error('%s: value and weight variables must differ',module_id);endif
    model=lower(strtrim(gxtxt_ini_get(cfg,'config.weight_model','statistical_weight')));
    if(!any(strcmp(model,{'statistical_weight','inverse_variance_uncertainty'})))
      error('%s: select an explicit weight model',module_id);
    endif
    se_model=lower(strtrim(gxtxt_ini_get(cfg,'config.mean_se_model','none')));
    if(!any(strcmp(se_model,{'none','sampling'}))),error('%s: invalid mean-SE model',module_id);endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    prefix=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_prefix','statistics.weighted'));
    if(isempty(regexp(prefix,'^[A-Za-z0-9_.-]+$','once'))||strcmp(prefix,source_id))
      error('%s: invalid output Dataset prefix',module_id);
    endif
    probabilities=parse_numbers(gxtxt_ini_get(cfg,'config.quantile_probabilities','0;0.25;0.5;0.75;1'));
    if(any(probabilities<0)||any(probabilities>1)),error('%s: quantile probabilities must lie in [0,1]',module_id);endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected value and weight variables','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',{value_id,weight_id},selection,65536);
    if(rows(matrix)<1),error('%s: no selected observations',module_id);endif
    values=matrix(:,1);second=matrix(:,2);
    if(strcmp(model,'statistical_weight'))
      if(!isempty(weight_unit)&&!strcmp(weight_unit,'1'))
        parsed=gxtxt_unit_parse(weight_unit);
        if(!strcmp(parsed.kind,'linear')||!parsed.dimensionless),error('%s: statistical weights must be dimensionless',module_id);endif
      endif
      weights=second;weight_unit_out='1';
      weighted_sum_unit=value_unit;
    else
      if(isempty(value_unit)||isempty(weight_unit)),error('%s: measurement and uncertainty units are required',module_id);endif
      compatible=gxtxt_unit_compatible(weight_unit,value_unit);
      if(!compatible),error('%s: measurement uncertainty unit must match measurement dimension',module_id);endif
      finite=isfinite(second);converted=second;
      if(any(finite)),converted(finite)=gxtxt_unit_convert(second(finite),weight_unit,value_unit);endif
      if(any(converted(finite)<=0)),error('%s: measurement uncertainties must be strictly positive',module_id);endif
      weights=NaN(size(second));
      if(any(finite))
        squared=gxtxt_numeric_v1('array_binary','power',converted(finite),2);
        inverse=gxtxt_numeric_v1('array_binary','divide',1,squared.values);
        weights(finite)=inverse.values;
      endif
      if(any(!isfinite(weights(finite)))||any(weights(finite)<=0)),error('%s: inverse-variance weights are outside the finite numeric range',module_id);endif
      if(strcmp(value_unit,'1')),weight_unit_out='1';weighted_sum_unit='1';
      else weight_unit_out=[value_unit '^-2'];weighted_sum_unit=[value_unit '^-1'];endif
    endif
    gxtxt_progress_stage('compute','Computing public weighted statistics','indeterminate');
    semantics='relative';if(strcmp(model,'inverse_variance_uncertainty')),semantics='inverse_variance';endif
    stats=gxtxt_numeric_v1('weighted_statistics',values,weights,struct('nonfinite',policy,'weight_semantics',semantics));
    Q=gxtxt_numeric_v1('weighted_quantiles',values,weights,probabilities,struct('nonfinite',policy));
    context=struct('y_unit',value_unit,'sampling_model','independent_observations','mean_se_model',se_model, ...
      'assumptions',{{'Mean uncertainty is conditional on independent observations and the explicitly selected weight model'}});
    provenance=struct('producer',module_id,'source_dataset_id',source_id,'source_variable_id',value_id,'weight_variable_id',weight_id);
    statistics=gxtxt_statistics_v1('from_numeric','math.numeric.summary','weighted_statistics',stats,context,struct(),provenance);
    quantiles=gxtxt_statistics_v1('from_numeric','math.numeric.summary','weighted_quantiles',Q,context,struct(),provenance);
    interpreted=gxtxt_statistics_values_v1(statistics);
    mapping={'mean','mean';'weighted_sum','weighted_sum';'variance_population','variance_population';'std_population','standard_deviation_population'; ...
      'variance_unbiased','variance';'std_unbiased','standard_deviation';'median','median';'q25','quartile_1';'q75','quartile_3';'iqr','interquartile_range'};
    for i=1:rows(mapping),stats.(mapping{i,1})=interpreted.(mapping{i,2});endfor
    Q.quantiles=quantiles.quantities.quantiles.value;
    measurement_uncertainty=interpreted.measurement_standard_error_mean;sampling_se=interpreted.standard_error_mean;
    % Preserve existing Dataset status spellings as presentation aliases of
    % the CORE statuses. Applicability and numerical values are never decided here.
    measurement_status=statistics.quantities.measurement_standard_error_mean.status;
    if(strcmp(measurement_status,'value')),measurement_status='known_independent_measurement_uncertainty';endif
    sampling_status=statistics.quantities.standard_error_mean.status;
    if(strcmp(sampling_status,'value')),sampling_status='sampling_estimate_from_replicate_variability';
    elseif(strcmp(sampling_status,'undefined')),sampling_status='insufficient_effective_sample_size';
    elseif(strcmp(sampling_status,'unavailable')),sampling_status='not_requested';endif
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Weighted Statistics', ...
      'provenance',sprintf('%s %s; source=%s; value=%s; second=%s; selection=%s; weight_model=%s; mean_se_model=%s; nonfinite=%s',module_id,version,source_id,value_id,weight_id,selection_id(selection),model,se_model,policy), ...
      'notes','Weight semantics explicit; measurement uncertainty and sampling standard error are separate.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids={value_id,weight_id};
    opts.statistical_results=struct('summary',statistics,'quantiles',quantiles);
    gxtxt_progress_stage('publish','Publishing weighted summaries and quantiles','indeterminate');
    publish_table(session,module_id,[prefix '.summary'],'summary',opts,{ ...
      'n_input','Selected pair count','int64','','count',int64(stats.n_input); ...
      'n_valid','Finite pair count','int64','','count',int64(stats.n_valid); ...
      'n_nonfinite','Excluded nonfinite pair count','int64','','count',int64(stats.n_nonfinite); ...
      'n_zero_weight','Zero-weight pair count','int64','','count',int64(stats.n_zero_weight); ...
      'n_positive_weight','Positive-weight pair count','int64','','count',int64(stats.n_positive_weight); ...
      'sum_weights','Sum of statistical weights','float64',weight_unit_out,'derived',stats.sum_weights; ...
      'effective_n','Effective sample size','float64','1','derived',stats.effective_n; ...
      'weighted_mean','Weighted mean','float64',value_unit,'derived',stats.mean; ...
      'weighted_sum','Weighted sum','float64',weighted_sum_unit,'derived',stats.weighted_sum; ...
      'weighted_variance_population','Weighted population variance','float64',squared_unit(value_unit),'derived',stats.variance_population; ...
      'weighted_std_population','Weighted population standard deviation','float64',value_unit,'derived',stats.std_population; ...
      'replicate_variance_unbiased','Unbiased weighted replicate variance','float64',squared_unit(value_unit),'derived',stats.variance_unbiased; ...
      'replicate_std_unbiased','Unbiased weighted replicate standard deviation','float64',value_unit,'derived',stats.std_unbiased; ...
      'weighted_median','Weighted median','float64',value_unit,'derived',stats.median; ...
      'weighted_q25','Weighted first quartile','float64',value_unit,'derived',stats.q25; ...
      'weighted_q75','Weighted third quartile','float64',value_unit,'derived',stats.q75; ...
      'weighted_iqr','Weighted interquartile range','float64',value_unit,'derived',stats.iqr; ...
      'measurement_uncertainty_of_mean','Known measurement uncertainty of weighted mean','float64',value_unit,'uncertainty',measurement_uncertainty; ...
      'sampling_standard_error_of_mean','Sampling standard error of weighted mean','float64',value_unit,'uncertainty',sampling_se; ...
      'measurement_uncertainty_status','Measurement uncertainty model status','string','','category',{measurement_status}; ...
      'sampling_standard_error_status','Sampling standard error model status','string','','category',{sampling_status}});
    publish_table(session,module_id,[prefix '.quantiles'],'quantile',opts,{ ...
      'probability','Weighted quantile probability','float64','1','coordinate',Q.probabilities; ...
      'value','Weighted empirical-CDF inverse quantile','float64',value_unit,'derived',Q.quantiles});
    write_summary(fullfile(outdir,'weighted_summary.ini'),source_id,value_id,weight_id,prefix,selection,model,se_model,policy,stats,statistics);
    write_report(fullfile(outdir,'weighted_report.txt'),source_id,value_id,weight_id,value_unit,selection,model,se_model,policy,stats,statistics);
    fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');if(fid<0),error('%s: cannot write graph manifest',module_id);endif
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\n');fclose(fid);
    gxtxt_progress_complete('done',sprintf('Published weighted summary and %d quantiles',numel(Q.probabilities)));
    fprintf('[%s] source=%s value=%s second=%s model=%s valid=%d\n',module_id,source_id,value_id,weight_id,model,stats.n_valid);
  catch err
    try gxtxt_progress_fail('failed','Weighted statistics failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function [vid,unit]=resolve_numeric(cfg,source_id,token)
  [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',strtrim(token));
  if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
    error('analysis.statistics.weighted: stable source variable could not be resolved');
  endif
  if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
    error('analysis.statistics.weighted: source variables must be numeric');
  endif
  if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
  vid=strtrim(meta.variable_id);if(isempty(vid)),error('analysis.statistics.weighted: stable variable ID is missing');endif
endfunction
function values=parse_numbers(text)
  parts=strsplit(strrep(text,',',';'),';');values=[];
  for i=1:numel(parts)
    token=strtrim(parts{i});if(isempty(token)),continue;endif
    value=str2double(token);if(!isfinite(value)),error('analysis.statistics.weighted: invalid quantile probability');endif
    values(end+1,1)=value;
  endfor
  if(isempty(values)),error('analysis.statistics.weighted: quantile probabilities are required');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.weighted: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.weighted: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function unit=squared_unit(base)
  if(strcmp(base,'1')),unit='1';else unit=[base '^2'];endif
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
function write_summary(path,source_id,value_id,weight_id,prefix,selection,model,se_model,policy,S,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.weighted: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.weighted\nmodule_version=1.1.0\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nvalue_variable_id=%s\nsecond_variable_id=%s\nselection_id=%s\n',source_id,value_id,weight_id,selection_id(selection));
    fprintf(fid,'\n[analysis]\nweight_model=%s\nmean_se_model=%s\nnonfinite_policy=%s\nn_input=%d\nn_valid=%d\nn_nonfinite=%d\nn_zero_weight=%d\nn_positive_weight=%d\n',model,se_model,policy,S.n_input,S.n_valid,S.n_nonfinite,S.n_zero_weight,S.n_positive_weight);
    mapping=struct('sum_weights','sum_weights','effective_n','effective_n','weighted_mean','mean', ...
      'measurement_uncertainty_of_mean','measurement_standard_error_mean','sampling_standard_error_of_mean','standard_error_mean');
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',statistics,mapping));
    fprintf(fid,'\n[output]\nprefix=%s\n',prefix);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,value_id,weight_id,unit,selection,model,se_model,policy,S,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.weighted: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Weighted Statistics\nSource Dataset: %s\nValue: %s (%s)\nSecond variable: %s\nSelection: %s\nWeight model: %s\nMean-SE model: %s\nNaN / Inf: %s\n',source_id,value_id,unit,weight_id,selection_id(selection),model,se_model,policy);
    fprintf(fid,'Selected pairs: %d  Finite pairs: %d  Zero weights: %d  Positive weights: %d\n',S.n_input,S.n_valid,S.n_zero_weight,S.n_positive_weight);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistics,{'sum_weights','effective_n','mean','standard_deviation_population','standard_deviation','median','interquartile_range','measurement_standard_error_mean','standard_error_mean'}));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
