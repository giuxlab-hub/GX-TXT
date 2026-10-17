function analysis_statistics_tests_main(args,framework_root)
% Focused hypothesis-test workflow using public NUMERIC_API primitives.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.tests';version='1.1.0';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  P=struct();opened=false;
  gxtxt_progress_start('prepare','Preparing hypothesis test','indeterminate');
  try
    method=lower(strtrim(gxtxt_ini_get(cfg,'config.method','one_sample_t')));
    if(!any(strcmp(method,{'one_sample_t','independent_t','welch_t','paired_t','mann_whitney','signed_rank'})))
      error('%s: unsupported test method',module_id);
    endif
    [first_id,first_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.first_variable',''));
    if(isempty(first_unit)),error('%s: first sample unit is required; use 1 for dimensionless data',module_id);endif
    second_id='';second_unit='';ids={first_id};
    if(!strcmp(method,'one_sample_t'))
      [second_id,second_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.second_variable',''));
      if(strcmp(first_id,second_id)),error('%s: first and second sample variables must differ',module_id);endif
      if(isempty(second_unit)||!gxtxt_unit_compatible(second_unit,first_unit))
        error('%s: two sample units must be compatible',module_id);
      endif
      ids{end+1}=second_id;
    endif
    alternative=lower(strtrim(gxtxt_ini_get(cfg,'config.alternative','two_sided')));
    if(!any(strcmp(alternative,{'two_sided','greater','less'}))),error('%s: invalid alternative',module_id);endif
    confidence=str2double(gxtxt_ini_get(cfg,'config.confidence','0.95'));
    if(!isfinite(confidence)||confidence<=0||confidence>=1),error('%s: confidence must lie strictly between 0 and 1',module_id);endif
    mu0=str2double(gxtxt_ini_get(cfg,'config.mu0','0'));
    if(!isfinite(mu0)),error('%s: null value must be finite',module_id);endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    output_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','statistics.tests.result'));
    if(isempty(regexp(output_id,'^[A-Za-z0-9_.-]+$','once'))||strcmp(output_id,source_id))
      error('%s: invalid or conflicting output Dataset ID',module_id);
    endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected sample values','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',ids,selection,65536);
    if(rows(matrix)<1),error('%s: no selected sample observations',module_id);endif
    x=matrix(:,1);y=[];
    if(numel(ids)>1)
      y=matrix(:,2);
      if(!strcmp(second_unit,first_unit))
        finite=isfinite(y);y(finite)=gxtxt_unit_convert(y(finite),second_unit,first_unit);
      endif
    endif
    gxtxt_progress_stage('compute','Computing public hypothesis test','indeterminate');
    result=gxtxt_numeric_v1('hypothesis_test',method,x,y,struct('mu0',mu0,'alternative',alternative,'confidence',confidence,'nonfinite',policy));
    statistics=gxtxt_statistics_v1('from_numeric','math.numeric.hypothesis','hypothesis_test',result, ...
      struct('y_unit',first_unit),struct(),struct('producer',module_id,'source_dataset_id',source_id, ...
        'first_variable_id',first_id,'second_variable_id',second_id));
    V=gxtxt_statistics_values_v1(statistics);
    for mapping={'statistic','test_statistic';'degrees_of_freedom','test_degrees_of_freedom';'p_value','p_value'; ...
                 'estimate','test_estimate';'null_value','null_value';'ci_lower','ci_lower';'ci_upper','ci_upper';'effect_size','effect_size'}'
      result.(mapping{1})=V.(mapping{2});
    endfor
    interval_status=statistics.quantities.ci_lower.status;
    if(strcmp(interval_status,'value')),result.ci_status='defined';
    elseif(strcmp(interval_status,'not_applicable')),result.ci_status='not_defined_for_rank_test';
    else result.ci_status=interval_status;endif
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Hypothesis Tests', ...
      'provenance',sprintf('%s %s; source=%s; first=%s; second=%s; selection=%s; method=%s; alternative=%s; confidence=%.12g; mu0=%.12g; nonfinite=%s',module_id,version,source_id,first_id,second_id,selection_id(selection),method,alternative,confidence,mu0,policy), ...
      'notes','Method, pairing, variance assumption and alternative were explicitly selected.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids=ids;opts.statistical_results=struct('test',statistics);
    gxtxt_progress_stage('publish','Publishing test result Dataset','indeterminate');
    P=gxtxt_publication_v2_open(session,module_id,output_id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'test',0,true);
    data={ ...
      'method','Test method','string','','category',{result.method}; ...
      'statistic','Test statistic','float64','1','derived',result.statistic; ...
      'degrees_of_freedom','Degrees of freedom','float64','1','derived',result.degrees_of_freedom; ...
      'n_input_first','First sample input count','int64','','count',int64(result.n_input_x); ...
      'n_input_second','Second sample input count','int64','','count',int64(result.n_input_y); ...
      'n_valid_first','First sample valid count','int64','','count',int64(result.n_x); ...
      'n_valid_second','Second sample valid count','int64','','count',int64(result.n_y); ...
      'p_value','p-value','float64','1','derived',result.p_value; ...
      'alternative','Alternative hypothesis','string','','category',{result.alternative}; ...
      'confidence','Confidence level','float64','1','derived',result.confidence; ...
      'null_value','Null mean or difference','float64',statistics.quantities.test_estimate.unit,'reference',result.null_value; ...
      'estimate','Mean, mean difference or rank statistic','float64',statistics.quantities.test_estimate.unit,'derived',result.estimate; ...
      'ci_lower','Confidence interval lower bound','float64',statistics.quantities.test_estimate.unit,'derived',result.ci_lower; ...
      'ci_upper','Confidence interval upper bound','float64',statistics.quantities.test_estimate.unit,'derived',result.ci_upper; ...
      'ci_status','Confidence interval status','string','','category',{result.ci_status}; ...
      'effect_size','Effect size','float64','1','derived',result.effect_size; ...
      'effect_name','Effect size name','string','','category',{result.effect_name}; ...
      'nonfinite_policy','NaN / Inf policy','string','','category',{result.nonfinite_policy}; ...
      'approximation','p-value calculation','string','','category',{result.approximation}};
    for i=1:rows(data)
      P=gxtxt_publication_v2_declare_variable(P,data{i,1},struct('dtype',data{i,3},'dimension_ids','test', ...
        'name',data{i,2},'unit',data{i,4},'semantic_role',data{i,5}));
    endfor
    P=gxtxt_publication_v2_append(P,'test',data(:,[1,6]));
    [P,published]=gxtxt_publication_v2_finalize(P);opened=false;
    write_summary(fullfile(outdir,'tests_summary.ini'),source_id,first_id,second_id,first_unit,output_id,selection,result,statistics);
    write_report(fullfile(outdir,'tests_report.txt'),source_id,first_id,second_id,first_unit,output_id,selection,result,statistics);
    fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');if(fid<0),error('%s: cannot write graph manifest',module_id);endif
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\n');fclose(fid);
    gxtxt_progress_complete('done',sprintf('Published %s test: %s',method,gxtxt_statistics_v1('report',statistics,{'p_value'}))); 
    fprintf('[%s] source=%s output=%s method=%s\n%s\n',module_id,source_id,output_id,method,gxtxt_statistics_v1('report',statistics,{'p_value'}));
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Hypothesis test failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function [vid,unit]=resolve_numeric(cfg,source_id,token)
  [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',strtrim(token));
  if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
    error('analysis.statistics.tests: stable source variable could not be resolved');
  endif
  if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
    error('analysis.statistics.tests: sample variable must be numeric');
  endif
  if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
  vid=strtrim(meta.variable_id);if(isempty(vid)),error('analysis.statistics.tests: stable variable ID is missing');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.tests: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.tests: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction

function write_summary(path,source_id,first_id,second_id,unit,output_id,selection,R,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.tests: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.tests\nmodule_version=1.1.0\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nfirst_variable_id=%s\nsecond_variable_id=%s\nunit=%s\nselection_id=%s\n',source_id,first_id,second_id,unit,selection_id(selection));
    fprintf(fid,'\n[test]\nmethod=%s\nalternative=%s\nconfidence=%.12g\nnonfinite_policy=%s\nn_valid_first=%d\nn_valid_second=%d\nci_status=%s\neffect_name=%s\napproximation=%s\n',R.method,R.alternative,R.confidence,R.nonfinite_policy,R.n_x,R.n_y,R.ci_status,R.effect_name,R.approximation);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',statistics,struct('statistic','test_statistic','degrees_of_freedom','test_degrees_of_freedom','p_value','p_value','ci_lower','ci_lower','ci_upper','ci_upper')));
    fprintf(fid,'\n[output]\ndataset_id=%s\n',output_id);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,first_id,second_id,unit,output_id,selection,R,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.tests: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Hypothesis Tests\nSource Dataset: %s\nFirst variable: %s\nSecond variable: %s\nUnit: %s\nSelection: %s\nOutput Dataset: %s\n',source_id,first_id,second_id,unit,selection_id(selection),output_id);
    fprintf(fid,'Method: %s\nAlternative: %s\nConfidence: %.6g\nNaN / Inf: %s\nInput counts: %d, %d\nValid counts: %d, %d\n',R.method,R.alternative,R.confidence,R.nonfinite_policy,R.n_input_x,R.n_input_y,R.n_x,R.n_y);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistics,{'test_statistic','test_degrees_of_freedom','p_value','test_estimate','ci_lower','ci_upper','effect_size'}));
    fprintf(fid,'Conditional assumptions:\n');for assumption=statistics.assumptions(:)',fprintf(fid,'- %s\n',assumption{1});endfor

  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
