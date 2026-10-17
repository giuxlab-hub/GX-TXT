function analysis_statistics_resampling_main(args,framework_root)
% Seeded bootstrap and permutation workflows through public NUMERIC_API.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.resampling';version='1.1.0';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing reproducible resampling','indeterminate');
  try
    method=lower(strtrim(gxtxt_ini_get(cfg,'config.method','bootstrap')));
    if(!any(strcmp(method,{'bootstrap','permutation_independent','permutation_paired'})))
      error('%s: invalid resampling method',module_id);
    endif
    statistic=lower(strtrim(gxtxt_ini_get(cfg,'config.statistic','mean')));
    if(!any(strcmp(statistic,{'mean','median','sample_sd'}))),error('%s: invalid bootstrap statistic',module_id);endif
    alternative=lower(strtrim(gxtxt_ini_get(cfg,'config.alternative','two_sided')));
    if(!any(strcmp(alternative,{'two_sided','greater','less'}))),error('%s: invalid alternative',module_id);endif
    confidence=str2double(gxtxt_ini_get(cfg,'config.confidence','0.95'));
    if(!isfinite(confidence)||confidence<=0||confidence>=1),error('%s: confidence must lie in (0,1)',module_id);endif
    reps=str2double(gxtxt_ini_get(cfg,'config.replicates','1000'));
    seed=str2double(gxtxt_ini_get(cfg,'config.seed','1'));
    if(!isfinite(reps)||reps!=fix(reps)||reps<1||reps>100000)
      error('%s: replicates must be an integer from 1 to 100000',module_id);
    endif
    if(!isfinite(seed)||seed!=fix(seed)||seed<1||seed>=2147483647)
      error('%s: seed must be an integer from 1 to 2147483646',module_id);
    endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    prefix=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_prefix','statistics.resampling'));
    if(isempty(regexp(prefix,'^[A-Za-z0-9_.-]+$','once'))||strcmp(prefix,source_id))
      error('%s: invalid output Dataset prefix',module_id);
    endif
    [first_id,first_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.first_variable',''));
    if(isempty(first_unit)),error('%s: first variable unit is required; use 1 for dimensionless data',module_id);endif
    ids={first_id};second_id='';second_unit='';
    if(!strcmp(method,'bootstrap'))
      [second_id,second_unit]=resolve_numeric(cfg,source_id,gxtxt_ini_get(cfg,'config.second_variable',''));
      if(strcmp(first_id,second_id)),error('%s: two distinct sample variables are required',module_id);endif
      if(isempty(second_unit)||!gxtxt_unit_compatible(second_unit,first_unit))
        error('%s: sample units must be compatible',module_id);
      endif
      ids{2}=second_id;
    endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected numeric observations','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',ids,selection,65536);
    if(isempty(matrix)),error('%s: no selected observations',module_id);endif
    x=matrix(:,1);y=[];
    if(numel(ids)>1)
      y=matrix(:,2);
      if(!strcmp(second_unit,first_unit))
        mask=isfinite(y);y(mask)=gxtxt_unit_convert(y(mask),second_unit,first_unit);
      endif
    endif
    if(strcmp(policy,'error')&&any(!isfinite(matrix(:))))
      error('%s: selected variables contain NaN or Inf',module_id);
    endif
    n_input_x=numel(x);n_input_y=numel(y);
    if(strcmp(method,'permutation_paired'))
      good=isfinite(x)&isfinite(y);x=x(good);y=y(good);
    else
      x=x(isfinite(x));if(!isempty(y)),y=y(isfinite(y));endif
    endif
    nx=numel(x);ny=numel(y);
    if(nx<2||(!strcmp(method,'bootstrap')&&ny<2))
      error('%s: each sample needs at least two valid observations',module_id);
    endif
    if(strcmp(method,'bootstrap')),draw=nx;
    elseif(strcmp(method,'permutation_paired')),draw=nx;
    else draw=nx+ny;endif
    if(draw*reps>10000000),error('%s: request exceeds ten million generated indices',module_id);endif
    gxtxt_progress_stage('compute','Generating seeded resampling distribution','determinate',reps);
    distribution=zeros(reps,1);state=seed;batch_size=max(1,min(250,floor(25000/draw)));
    if(strcmp(method,'bootstrap')),observed=scalar_statistic(x,statistic);
    else observed=mean_difference(x,y);endif
    for first=1:batch_size:reps
      last=min(reps,first+batch_size-1);count=last-first+1;
      if(strcmp(method,'bootstrap'))
        generated=gxtxt_numeric_v1('resample_indices',nx,nx,count,state,struct('replace',true));
        for b=1:count
          distribution(first+b-1)=scalar_statistic(x(generated.indices(b,:)),statistic);
        endfor
      elseif(strcmp(method,'permutation_independent'))
        combined=[x(:);y(:)];n=numel(combined);
        generated=gxtxt_numeric_v1('resample_indices',n,n,count,state,struct('replace',false));
        for b=1:count
          draw_values=combined(generated.indices(b,:));
          distribution(first+b-1)=mean_difference(draw_values(1:nx),draw_values(nx+1:end));
        endfor
      else
        differences=gxtxt_numeric_v1('array_binary','subtract',x(:),y(:));
        generated=gxtxt_numeric_v1('resample_indices',2,nx,count,state,struct('replace',true));
        for b=1:count
          signs=2*generated.indices(b,:)'-3;
          flipped=gxtxt_numeric_v1('array_binary','multiply',differences.values,signs);
          distribution(first+b-1)=scalar_statistic(flipped.values,'mean');
        endfor
      endif
      state=generated.next_seed;
      gxtxt_progress_update(last,reps,'compute',sprintf('Completed %d of %d seeded replicates',last,reps));
    endfor
    if(any(!isfinite(distribution))),error('%s: resampled statistic is nonfinite',module_id);endif
    raw=gxtxt_numeric_v1('resampling_summary',distribution,observed,struct('method',method,'alternative',alternative,'confidence',confidence,'n_x',nx,'n_y',ny));
    statistics=gxtxt_statistics_v1('from_numeric','math.numeric.resampling','resampling_summary',raw,struct('y_unit',first_unit),struct(), ...
      struct('producer',module_id,'source_dataset_id',source_id,'first_variable_id',first_id,'second_variable_id',second_id,'seed',seed,'generator','park_miller_16807_v1','statistic',statistic));
    V=gxtxt_statistics_values_v1(statistics);
    lower_bound=V.ci_lower;upper_bound=V.ci_upper;p_value=V.p_value;extreme_count=int64(raw.extreme_count);inference=raw.inference;
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Resampling Inference', ...
      'provenance',sprintf('%s %s; source=%s; first=%s; second=%s; selection=%s; method=%s; statistic=%s; alternative=%s; confidence=%.12g; replicates=%d; seed=%d; nonfinite=%s; generator=park_miller_16807_v1; inference=%s',module_id,version,source_id,first_id,second_id,selection_id(selection),method,statistic,alternative,confidence,reps,seed,policy,inference), ...
      'notes','Public seeded resample_indices batches; complete results published only after all iterations.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids=ids;opts.statistical_results=struct('resampling',statistics);
    gxtxt_progress_stage('publish','Publishing replicate and summary Datasets','indeterminate');
    publish_table(session,module_id,[prefix '.distribution'],'replicate',opts,{ ...
      'replicate','Replicate number','int64','','index',int64((1:reps)'); ...
      'statistic','Resampled statistic','float64',first_unit,'derived',distribution});
    publish_table(session,module_id,[prefix '.summary'],'summary',opts,{ ...
      'method','Resampling method','string','','category',{method}; ...
      'statistic_name','Statistic name','string','','category',{statistic}; ...
      'alternative','Permutation alternative','string','','category',{alternative}; ...
      'inference','Inference method','string','','category',{inference}; ...
      'n_input_first','First sample input count','int64','','count',int64(n_input_x); ...
      'n_input_second','Second sample input count','int64','','count',int64(n_input_y); ...
      'n_valid_first','First sample valid count','int64','','count',int64(nx); ...
      'n_valid_second','Second sample valid count','int64','','count',int64(ny); ...
      'replicates','Replicate count','int64','','count',int64(reps); ...
      'seed','Random seed','int64','','parameter',int64(seed); ...
      'confidence','Confidence level','float64','1','parameter',confidence; ...
      'observed','Observed statistic','float64',first_unit,'derived',observed; ...
      'ci_lower','Percentile interval lower','float64',first_unit,'derived',lower_bound; ...
      'ci_upper','Percentile interval upper','float64',first_unit,'derived',upper_bound; ...
      'p_value','Permutation p-value','float64','1','derived',p_value; ...
      'extreme_count','Extreme permutation count','int64','','count',extreme_count});
    write_summary(fullfile(outdir,'resampling_summary.ini'),source_id,first_id,second_id,selection,method,statistic,alternative,confidence,reps,seed,policy,inference,n_input_x,n_input_y,nx,ny,observed,lower_bound,upper_bound,p_value,extreme_count,prefix,statistics);
    write_report(fullfile(outdir,'resampling_report.txt'),source_id,first_id,second_id,first_unit,method,statistic,alternative,reps,seed,nx,ny,observed,lower_bound,upper_bound,p_value,statistics);
    fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');if(fid<0),error('%s: cannot write graph manifest',module_id);endif
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\n');fclose(fid);
    gxtxt_progress_complete('done',sprintf('Published %d reproducible replicates',reps));
    fprintf('[%s] method=%s source=%s replicates=%d seed=%d\n',module_id,method,source_id,reps,seed);
  catch err
    try gxtxt_progress_fail('failed','Resampling failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function [vid,unit]=resolve_numeric(cfg,source_id,token)
  [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',strtrim(token));
  if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
    error('analysis.statistics.resampling: stable source variable could not be resolved');
  endif
  if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
    error('analysis.statistics.resampling: sample variable must be numeric');
  endif
  if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
  vid=strtrim(meta.variable_id);if(isempty(vid)),error('analysis.statistics.resampling: stable variable ID is missing');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.resampling: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.resampling: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function value=scalar_statistic(x,name)
  stats=gxtxt_numeric_v1('statistics',x);
  if(strcmp(name,'mean')),value=stats.mean;
  elseif(strcmp(name,'median')),value=stats.median;
  else value=stats.std_sample;endif
endfunction
function value=mean_difference(x,y)
  sx=gxtxt_numeric_v1('statistics',x);
  sy=gxtxt_numeric_v1('statistics',y);
  delta=gxtxt_numeric_v1('array_binary','subtract',sx.mean,sy.mean);
  value=delta.values;
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
function write_summary(path,source_id,first_id,second_id,selection,method,statistic,alternative,confidence,reps,seed,policy,inference,n_input_x,n_input_y,nx,ny,observed,lo,hi,p,extreme,prefix,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.resampling: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.resampling\nmodule_version=1.1.0\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nfirst_variable_id=%s\nsecond_variable_id=%s\nselection_id=%s\n',source_id,first_id,second_id,selection_id(selection));
    fprintf(fid,'\n[analysis]\nmethod=%s\nstatistic=%s\nalternative=%s\nconfidence=%.17g\nreplicates=%d\nseed=%d\nnonfinite_policy=%s\ngenerator=park_miller_16807_v1\ninference=%s\nn_input_first=%d\nn_input_second=%d\nn_valid_first=%d\nn_valid_second=%d\nextreme_count=%d\n',method,statistic,alternative,confidence,reps,seed,policy,inference,n_input_x,n_input_y,nx,ny,extreme);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',statistics,struct('observed','test_estimate','ci_lower','ci_lower','ci_upper','ci_upper','p_value','p_value')));
    fprintf(fid,'\n[output]\nprefix=%s\n',prefix);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,first_id,second_id,unit,method,statistic,alternative,reps,seed,nx,ny,observed,lo,hi,p,statistics)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.resampling: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Resampling Inference\nSource Dataset: %s\nFirst variable: %s\nSecond variable: %s\nMethod: %s\nStatistic: %s\nAlternative: %s\nReplicates: %d\nSeed: %d\nValid sample sizes: %d, %d\n',source_id,first_id,second_id,method,statistic,alternative,reps,seed,nx,ny);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistics,{'test_estimate','ci_lower','ci_upper','bootstrap_standard_error','p_value','extreme_count'}));
    fprintf(fid,'Conditional assumptions:\n');for assumption=statistics.assumptions(:)',fprintf(fid,'- %s\n',assumption{1});endfor

  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
