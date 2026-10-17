function analysis_statistics_correlation_main(args,framework_root)
% Pairwise covariance/correlation workflow through GX-TXT public APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.correlation';module_version='1.1.0';
  publication_open=false;P=struct();
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
  gxtxt_script_bridge_start(config_path,execution);bridge_cleanup=onCleanup(@() gxtxt_script_bridge_stop());
  gxtxt_progress_start('prepare','Preparing covariance and correlation','indeterminate');
  try
    variable_tokens=repeatable_variables(cfg);
    variables=resolve_variables(cfg,source_id,variable_tokens);
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.missing_policy','pairwise')));
    if(!any(strcmp(policy,{'pairwise','listwise'}))),error('%s: missing-pair policy must be pairwise or listwise',module_id);endif
    nonfinite=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(nonfinite,{'omit','error'}))),error('%s: NaN / Inf policy must be omit or error',module_id);endif
    output_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','statistics.correlation.pairs'));
    if(isempty(regexp(output_id,'^[A-Za-z0-9_.-]+$','once'))||strcmp(output_id,source_id)),error('%s: invalid or conflicting output Dataset ID',module_id);endif
    render_graphs=parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1'));
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Dataset Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    ids={variables.variable_id};
    gxtxt_progress_stage('read','Reading selected numeric Dataset variables','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',ids,selection,65536);
    if(rows(matrix)<1),error('%s: no selected source observations',module_id);endif
    if(strcmp(nonfinite,'error')&&any(!isfinite(matrix(:))))
      error('%s: selected variables contain NaN or Inf; choose omit explicitly',module_id);
    endif
    n_selected=rows(matrix);n_variables=columns(matrix);
    listwise_mask=all(isfinite(matrix),2);
    pair_count=n_variables*n_variables;
    pairs=struct('left_index',cell(pair_count,1),'right_index',cell(pair_count,1), ...
      'left_id',cell(pair_count,1),'right_id',cell(pair_count,1), ...
      'left_name',cell(pair_count,1),'right_name',cell(pair_count,1), ...
      'covariance_unit',cell(pair_count,1),'n_input',cell(pair_count,1), ...
      'n_valid',cell(pair_count,1),'n_excluded',cell(pair_count,1), ...
      'covariance_sample',cell(pair_count,1),'covariance_population',cell(pair_count,1), ...
      'pearson',cell(pair_count,1),'spearman',cell(pair_count,1), ...
      'pearson_status',cell(pair_count,1),'spearman_status',cell(pair_count,1));
    gxtxt_progress_stage('compute','Computing pairwise numerical results','determinate',pair_count);
    row=0;statistical_results=struct();
    for i=1:n_variables
      for j=1:n_variables
        row+=1;x=matrix(:,i);y=matrix(:,j);
        if(strcmp(policy,'listwise')),valid=listwise_mask;
        else valid=isfinite(x)&isfinite(y);endif
        x=x(valid);y=y(valid);n_valid=numel(x);
        cov_sample=NaN;cov_population=NaN;pearson=NaN;spearman=NaN;
        p_status='insufficient_observations';s_status='insufficient_observations';
        cov=struct('n_valid',n_valid);pear=struct('n_valid',n_valid,'method','pearson');spear=struct('n_valid',n_valid,'method','spearman');
        if(n_valid>=2)
          cov=gxtxt_analysis_numeric_call('covariance',x,y,struct('nonfinite','error'));
          pear=gxtxt_analysis_numeric_call('correlation',x,y,struct('method','pearson','nonfinite','error'));
          spear=gxtxt_analysis_numeric_call('correlation',x,y,struct('method','spearman','nonfinite','error'));
          cov_sample=cov.covariance_sample;cov_population=cov.covariance_population;
          pearson=pear.correlation;spearman=spear.correlation;
          p_status=pear.status;s_status=spear.status;
        endif
        context=struct('x_unit',variables(i).unit,'y_unit',variables(j).unit, ...
          'x_variable_id',variables(i).variable_id,'y_variable_id',variables(j).variable_id);
        provenance=struct('producer',module_id,'source_dataset_id',source_id,'missing_policy',policy);
        cs=gxtxt_statistics_v1('from_numeric','math.numeric.summary','covariance',cov,context,struct(),provenance);
        ps=gxtxt_statistics_v1('from_numeric','math.numeric.summary','correlation',pear,context,struct(),provenance);
        ss=gxtxt_statistics_v1('from_numeric','math.numeric.summary','correlation',spear,context,struct(),provenance);
        statistical_results.(sprintf('pair%d_covariance',row))=cs;
        statistical_results.(sprintf('pair%d_pearson',row))=ps;
        statistical_results.(sprintf('pair%d_spearman',row))=ss;
        cv=gxtxt_statistics_values_v1(cs);pv=gxtxt_statistics_values_v1(ps);sv=gxtxt_statistics_values_v1(ss);
        cov_sample=cv.covariance_sample;cov_population=cv.covariance_population;
        pearson=pv.correlation;spearman=sv.correlation;
        pairs(row)=struct('left_index',i,'right_index',j, ...
          'left_id',variables(i).variable_id,'right_id',variables(j).variable_id, ...
          'left_name',variables(i).name,'right_name',variables(j).name, ...
          'covariance_unit',product_unit(variables(i).unit,variables(j).unit), ...
          'n_input',n_selected,'n_valid',n_valid,'n_excluded',n_selected-n_valid, ...
          'covariance_sample',cov_sample,'covariance_population',cov_population, ...
          'pearson',pearson,'spearman',spearman, ...
          'pearson_status',p_status,'spearman_status',s_status);
        gxtxt_progress_update(row,pair_count,'compute',sprintf('Computed %d / %d variable pairs',row,pair_count));
      endfor
    endfor
    gxtxt_progress_stage('publish','Publishing covariance and correlation Dataset','indeterminate');
    opts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source','GX-TXT Covariance and Correlation', ...
      'provenance',sprintf('%s %s; source=%s; missing_policy=%s; nonfinite=%s; selection=%s',module_id,module_version,source_id,policy,nonfinite,selection_id(selection)), ...
      'notes','Ordered variable pairs; covariance in source unit products; correlations dimensionless.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids=ids;
    opts.statistical_results=statistical_results;
    P=gxtxt_publication_v2_open(session,module_id,output_id,'table.generic',opts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'pair',0,true);
    P=declare_num(P,'left_index','Left variable index','index','int32','');
    P=declare_num(P,'right_index','Right variable index','index','int32','');
    P=declare_text(P,'left_variable_id','Left stable variable ID','identifier');
    P=declare_text(P,'right_variable_id','Right stable variable ID','identifier');
    P=declare_text(P,'left_name','Left variable name','label');
    P=declare_text(P,'right_name','Right variable name','label');
    P=declare_text(P,'covariance_unit','Covariance source unit product','unit');
    P=declare_num(P,'n_input','Selected observation count','count','int64','');
    P=declare_num(P,'n_valid','Finite pair count','count','int64','');
    P=declare_num(P,'n_excluded','Excluded pair count','count','int64','');
    P=declare_num(P,'covariance_sample','Sample covariance','derived','float64','');
    P=declare_num(P,'covariance_population','Population covariance','derived','float64','');
    P=declare_num(P,'pearson','Pearson correlation','derived','float64','1');
    P=declare_num(P,'spearman','Spearman correlation','derived','float64','1');
    P=declare_text(P,'pearson_status','Pearson definition status','category');
    P=declare_text(P,'spearman_status','Spearman definition status','category');
    values={ ...
      'left_index',int32([pairs.left_index]'); ...
      'right_index',int32([pairs.right_index]'); ...
      'left_variable_id',{pairs.left_id}'; ...
      'right_variable_id',{pairs.right_id}'; ...
      'left_name',{pairs.left_name}'; ...
      'right_name',{pairs.right_name}'; ...
      'covariance_unit',{pairs.covariance_unit}'; ...
      'n_input',int64([pairs.n_input]'); ...
      'n_valid',int64([pairs.n_valid]'); ...
      'n_excluded',int64([pairs.n_excluded]'); ...
      'covariance_sample',[pairs.covariance_sample]'; ...
      'covariance_population',[pairs.covariance_population]'; ...
      'pearson',[pairs.pearson]'; ...
      'spearman',[pairs.spearman]'; ...
      'pearson_status',{pairs.pearson_status}'; ...
      'spearman_status',{pairs.spearman_status}'};
    P=gxtxt_publication_v2_append(P,'pair',values);
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);
    [P,pub_result]=gxtxt_publication_v2_finalize(P);publication_open=false;
    gxtxt_progress_stage('graphs','Creating persistent correlation heatmap','indeterminate');
    graph_count=0;graph_id='';variant_id='';graph_artifact='';
    if(render_graphs)
      spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_3d', ...
        'graph_id','plot.dataset.xyz','dataset_id',output_id, ...
        'x_variable_id','left_index','y_variable_id','right_index','z_variable_id','pearson', ...
        'title','Pearson correlation matrix', ...
        'config',struct('plot_type','heatmap','reduction_mode','none'));
      graph=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
      graph_count=1;graph_id=graph.graph_id;variant_id=graph.variant_id;graph_artifact=graph.artifact;
      if(isempty(graph_artifact)||exist(graph_artifact,'file')!=2),error('%s: Plot Dataset did not return a heatmap artifact',module_id);endif
      [copied,msg]=copyfile(graph_artifact,fullfile(outdir,'correlation_heatmap.png'),'f');
      if(!copied),error('%s: cannot copy heatmap artifact: %s',module_id,msg);endif
    endif
    write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),graph_count,graph_id,variant_id,graph_artifact);
    write_summary(fullfile(outdir,'correlation_summary.ini'),module_id,module_version,source_id,output_id,selection,policy,nonfinite,variables,n_selected,sum(listwise_mask),pair_count,graph_count,P.provider);
    write_report(fullfile(outdir,'correlation_report.txt'),source_id,output_id,selection,policy,nonfinite,variables,pairs,pub_diag,pub_result,statistical_results);
    gxtxt_progress_complete('done',sprintf('Published %d variable pairs and %d heatmap',pair_count,graph_count));
    fprintf('[%s] source=%s output=%s variables=%d pairs=%d graphs=%d\n',module_id,source_id,output_id,n_variables,pair_count,graph_count);
  catch err
    if(publication_open),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Covariance and correlation failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function value=parse_bool(text)
  q=lower(strtrim(text));
  if(any(strcmp(q,{'1','true','yes','on'}))),value=true;
  elseif(any(strcmp(q,{'0','false','no','off'}))),value=false;
  else error('analysis.statistics.correlation: expected a boolean setting');endif
endfunction
function tokens=repeatable_variables(cfg)
  text=strtrim(gxtxt_ini_get(cfg,'repeatable_config.variables.rows',''));
  rows=strsplit(text,';');tokens={};
  for i=1:numel(rows)
    row=strtrim(rows{i});if(isempty(row)),continue;endif
    token=strtrim(gxtxt_ini_get(cfg,['repeatable_config.variables.' row '.variable'],''));
    if(isempty(token)),error('analysis.statistics.correlation: variable row %s is empty',row);endif
    tokens{end+1}=token;
  endfor
  if(numel(tokens)<2),error('analysis.statistics.correlation: select at least two numeric variables');endif
endfunction
function variables=resolve_variables(cfg,source_id,tokens)
  variables=struct('variable_id',{},'name',{},'unit',{});seen={};
  for i=1:numel(tokens)
    [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',tokens{i});
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.correlation: variable could not be resolved: %s',tokens{i});endif
    if(!strcmp(strtrim(meta.dataset_id),source_id)),error('analysis.statistics.correlation: variable belongs to another Dataset');endif
    vid=strtrim(meta.variable_id);
    if(isempty(vid)||any(strcmp(seen,vid))),error('analysis.statistics.correlation: missing or duplicate stable variable ID');endif
    kind=lower(strtrim(meta.value_kind));
    if(!any(strcmp(kind,{'number','elapsed_time'}))),error('analysis.statistics.correlation: variable %s is not numeric',meta.name);endif
    if(strcmp(kind,'elapsed_time')),unit='s';endif
    variables(end+1)=struct('variable_id',vid,'name',strtrim(meta.name),'unit',strtrim(unit));seen{end+1}=vid;
  endfor
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.correlation: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.correlation: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function unit=product_unit(left,right)
  left=strtrim(left);right=strtrim(right);
  if(isempty(left)||strcmp(left,'1')),unit=right;
  elseif(isempty(right)||strcmp(right,'1')),unit=left;
  else unit=[left '*' right];endif
  if(isempty(unit)),unit='1';endif
endfunction
function P=declare_text(P,id,name,role)
  P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype','string','dimension_ids','pair','name',name,'unit','','semantic_role',role));
endfunction
function P=declare_num(P,id,name,role,dtype,unit)
  P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype',dtype,'dimension_ids','pair','name',name,'unit',unit,'semantic_role',role));
endfunction
function write_graph_manifest(path,count,graph_id,variant_id,artifact)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.correlation: cannot create graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',count);
    if(count),fprintf(fid,'\n[graph.01]\nkey=correlation.pearson\nkind=heatmap\ngraph_id=%s\nvariant_id=%s\npng=correlation_heatmap.png\nprovider_artifact=%s\n',clean_line(graph_id),clean_line(variant_id),clean_line(artifact));endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_summary(path,module_id,version,source_id,output_id,selection,policy,nonfinite,variables,n_selected,n_listwise,n_pairs,n_graphs,provider)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot create summary',module_id);endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=%s\nmodule_version=%s\napi=NUMERIC_API_v1\n',module_id,version);
    fprintf(fid,'\n[source]\ndataset_id=%s\nselection_id=%s\nselected_rows=%d\nlistwise_finite_rows=%d\nvariable_count=%d\n',clean_line(source_id),clean_line(selection_id(selection)),n_selected,n_listwise,numel(variables));
    for i=1:numel(variables),fprintf(fid,'variable_%d_id=%s\nvariable_%d_unit=%s\n',i,clean_line(variables(i).variable_id),i,clean_line(variables(i).unit));endfor
    fprintf(fid,'\n[analysis]\nmissing_policy=%s\nnonfinite_policy=%s\n',policy,nonfinite);
    fprintf(fid,'\n[output]\ndataset_id=%s\nprovider=%s\npair_rows=%d\nautomatic_graph_count=%d\n',clean_line(output_id),clean_line(provider),n_pairs,n_graphs);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,output_id,selection,policy,nonfinite,variables,pairs,pub_diag,pub_result,statistical_results)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.correlation: cannot create report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Covariance and Correlation\nSource Dataset: %s\nResult Dataset: %s\nSelection: %s\nMissing policy: %s\nNaN / Inf: %s\nVariables: %d\nPairs: %d\n',source_id,output_id,selection_id(selection),policy,nonfinite,numel(variables),numel(pairs));
    for i=1:numel(pairs)
      p=pairs(i);fprintf(fid,'\n%s / %s\n',clean_line(p.left_name),clean_line(p.right_name));
      fprintf(fid,'%s\n%s\n%s\n', ...
        gxtxt_statistics_v1('report',statistical_results.(sprintf('pair%d_covariance',i)),{'n','covariance_sample','covariance_population'}), ...
        gxtxt_statistics_v1('report',statistical_results.(sprintf('pair%d_pearson',i)),{'correlation'}), ...
        gxtxt_statistics_v1('report',statistical_results.(sprintf('pair%d_spearman',i)),{'correlation'}));
    endfor
    fprintf(fid,'\nPublication diagnostics available: %d\nFinalized: %d\n',isstruct(pub_diag),isstruct(pub_result));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function text=clean_line(value)
  text=strrep(strrep(char(value),sprintf('\r'),' '),sprintf('\n'),' ');
endfunction
