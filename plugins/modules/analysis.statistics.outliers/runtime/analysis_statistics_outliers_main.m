function analysis_statistics_outliers_main(args,framework_root)
% Explicit IQR/MAD outlier workflow through public GX-TXT APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.outliers';version='1.0.1';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing outlier flags','indeterminate');
  P=struct();opened=false;
  try
    token=strtrim(gxtxt_ini_get(cfg,'config.variable',''));
    [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',token);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
      error('%s: stable source variable could not be resolved',module_id);
    endif
    if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
      error('%s: source variable must be numeric',module_id);
    endif
    if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
    vid=strtrim(meta.variable_id);
    if(isempty(vid)),error('%s: stable variable ID is missing',module_id);endif
    method=lower(strtrim(gxtxt_ini_get(cfg,'config.method','iqr')));
    if(!any(strcmp(method,{'iqr','mad'}))),error('%s: method must be iqr or mad',module_id);endif
    multiplier=str2double(gxtxt_ini_get(cfg,'config.multiplier','1.5'));
    if(!isfinite(multiplier)||multiplier<=0),error('%s: multiplier must be positive and finite',module_id);endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    output_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','statistics.outliers.flags'));
    if(isempty(regexp(output_id,'^[A-Za-z0-9_.-]+$','once'))||strcmp(output_id,source_id))
      error('%s: invalid or conflicting output Dataset ID',module_id);
    endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected source rows','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',{vid},selection,65536);
    values=matrix(:,1);n_input=numel(values);finite_mask=isfinite(values);
    if(n_input<1||!any(finite_mask)),error('%s: no finite selected observations',module_id);endif
    if(strcmp(policy,'error')&&any(!finite_mask)),error('%s: selected variable contains NaN or Inf',module_id);endif
    finite_values=values(finite_mask);
    gxtxt_progress_stage('compute','Computing outlier limits and flags','indeterminate');
    q=gxtxt_numeric_v1('quantiles',finite_values,[0.25;0.5;0.75]);
    center=q.quantiles(2);
    if(strcmp(method,'iqr'))
      scale=q.quantiles(3)-q.quantiles(1);
      lower=q.quantiles(1)-multiplier*scale;
      upper=q.quantiles(3)+multiplier*scale;
    else
      mad=gxtxt_numeric_v1('mad',finite_values,struct('scale','normal_consistency'));
      scale=mad.mad;
      lower=center-multiplier*scale;
      upper=center+multiplier*scale;
    endif
    lower_result=gxtxt_numeric_v1('array_compare','less_than',finite_values,lower);
    upper_result=gxtxt_numeric_v1('array_compare','greater_than',finite_values,upper);
    combined=gxtxt_numeric_v1('array_mask','logical_or',lower_result.values,upper_result.values);
    flags=zeros(n_input,1,'int32');flags(finite_mask)=int32(combined.values);
    scores=NaN(n_input,1);
    if(scale>0)
      delta=gxtxt_numeric_v1('array_binary','subtract',finite_values,center);
      standardized=gxtxt_numeric_v1('array_binary','divide',delta.values,scale);
      scores(finite_mask)=standardized.values;
    else
      delta=finite_values-center;temp=zeros(size(delta));temp(delta>0)=Inf;temp(delta<0)=-Inf;
      scores(finite_mask)=temp;
    endif
    n_flags=sum(flags);n_valid=sum(finite_mask);
    gxtxt_progress_stage('publish','Publishing source-aligned outlier flags','indeterminate');
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Outlier Flags', ...
      'provenance',sprintf('%s %s; source=%s; variable=%s; selection=%s; method=%s; multiplier=%.12g; nonfinite=%s',module_id,version,source_id,vid,selection_id(selection),method,multiplier,policy), ...
      'notes','One output row per selected source row; nonfinite rows retained with flag 0.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids={vid};
    P=gxtxt_publication_v2_open(session,module_id,output_id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    P=declare(P,'source_row','Original one-based source row','int64','','index');
    P=declare(P,'value','Selected source value','float64',unit,'measurement');
    P=declare(P,'method','Flagging rule','string','','category');
    P=declare(P,'score','Signed standardized score','float64','1','derived');
    P=declare(P,'lower_limit','Lower limit','float64',unit,'derived');
    P=declare(P,'upper_limit','Upper limit','float64',unit,'derived');
    P=declare(P,'is_outlier','Outlier flag','int32','','flag');
    P=gxtxt_publication_v2_append(P,'row',{ ...
      'source_row',int64(source_rows); ...
      'value',values; ...
      'method',repmat({method},n_input,1); ...
      'score',scores; ...
      'lower_limit',repmat(lower,n_input,1); ...
      'upper_limit',repmat(upper,n_input,1); ...
      'is_outlier',flags});
    [P,result]=gxtxt_publication_v2_finalize(P);opened=false;
    write_summary(fullfile(outdir,'outliers_summary.ini'),source_id,vid,output_id,selection,method,multiplier,policy,n_input,n_valid,n_flags,center,scale,lower,upper);
    write_report(fullfile(outdir,'outliers_report.txt'),source_id,vid,unit,selection,method,multiplier,policy,n_input,n_valid,n_flags,center,scale,lower,upper);
    fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');
    if(fid<0),error('%s: cannot write graph manifest',module_id);endif
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\n');fclose(fid);
    gxtxt_progress_complete('done',sprintf('Published %d source-aligned rows with %d outlier flags',n_input,n_flags));
    fprintf('[%s] source=%s variable=%s rows=%d flags=%d\n',module_id,source_id,vid,n_input,n_flags);
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Outlier flagging failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.outliers: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.outliers: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function P=declare(P,id,name,dtype,unit,role)
  P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype',dtype,'dimension_ids','row','name',name,'unit',unit,'semantic_role',role));
endfunction
function write_summary(path,source_id,vid,output_id,selection,method,multiplier,policy,n_input,n_valid,n_flags,center,scale,lower,upper)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.outliers: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.outliers\nmodule_version=1.0.1\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nvariable_id=%s\nselection_id=%s\n',source_id,vid,selection_id(selection));
    fprintf(fid,'\n[analysis]\nmethod=%s\nmultiplier=%.12g\nnonfinite_policy=%s\nn_input=%d\nn_valid=%d\nn_excluded=%d\nn_outliers=%d\ncenter=%.12g\nscale=%.12g\nlower_limit=%.12g\nupper_limit=%.12g\n',method,multiplier,policy,n_input,n_valid,n_input-n_valid,n_flags,center,scale,lower,upper);
    fprintf(fid,'\n[output]\ndataset_id=%s\nrows=%d\n',output_id,n_input);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,vid,unit,selection,method,multiplier,policy,n_input,n_valid,n_flags,center,scale,lower,upper)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.outliers: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Outlier Flags\nSource Dataset: %s\nVariable: %s (%s)\nSelection: %s\nRule: %s\nMultiplier: %.12g\nNaN / Inf: %s\nSelected rows: %d\nFinite rows: %d\nExcluded nonfinite: %d\nFlagged outliers: %d\nCenter: %.12g\nScale: %.12g\nLimits: [%.12g, %.12g]\n',source_id,vid,unit,selection_id(selection),method,multiplier,policy,n_input,n_valid,n_input-n_valid,n_flags,center,scale,lower,upper);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
