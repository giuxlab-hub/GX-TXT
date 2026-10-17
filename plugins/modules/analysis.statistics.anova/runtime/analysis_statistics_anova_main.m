function analysis_statistics_anova_main(args,framework_root)
% One-way and Welch ANOVA workflow through public GX-TXT APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.anova';version='1.1.0';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing one-way ANOVA','indeterminate');
  try
    [value_id,value_unit,value_meta]=resolve_source(cfg,source_id,gxtxt_ini_get(cfg,'config.value_variable',''));
    [group_id,~,group_meta]=resolve_source(cfg,source_id,gxtxt_ini_get(cfg,'config.group_variable',''));
    if(strcmp(value_id,group_id)),error('%s: value and group variables must differ',module_id);endif
    if(!any(strcmp(lower(strtrim(value_meta.value_kind)),{'number','elapsed_time'})))
      error('%s: measurement variable must be numeric',module_id);
    endif
    if(strcmp(lower(strtrim(value_meta.value_kind)),'elapsed_time')),value_unit='s';endif
    if(isempty(value_unit)),error('%s: measurement unit is required; use 1 for dimensionless data',module_id);endif
    method=lower(strtrim(gxtxt_ini_get(cfg,'config.method','ordinary')));
    if(!any(strcmp(method,{'ordinary','welch'}))),error('%s: method must be ordinary or welch',module_id);endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    prefix=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_prefix','statistics.anova'));
    if(isempty(regexp(prefix,'^[A-Za-z0-9_.-]+$','once'))||strcmp(prefix,source_id))
      error('%s: invalid output Dataset prefix',module_id);
    endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected measurements and group labels','indeterminate');
    [values,groups,source_rows]=gxtxt_analysis_grouped_numeric_source(cfg,'primary',value_id,group_id,selection,65536);
    if(isempty(values)),error('%s: no selected observations',module_id);endif
    gxtxt_progress_stage('compute','Computing public one-way ANOVA','indeterminate');
    R=gxtxt_numeric_v1('one_way_anova',values,groups,struct('method',method,'nonfinite',policy));
    provenance=struct('producer',module_id,'source_dataset_id',source_id,'source_variable_id',value_id,'group_variable_id',group_id);
    statistics=gxtxt_statistics_v1('from_numeric','math.numeric.anova','one_way_anova',R,struct('y_unit',value_unit),struct(),provenance);
    statistical_results=struct('anova',statistics);
    for gi=1:R.group_count
      group_result=gxtxt_statistics_v1('from_numeric','math.numeric.summary','one_way_anova',R,struct('y_unit',value_unit,'group_index',gi),struct(),provenance);
      statistical_results.(sprintf('group_%d',gi))=group_result;
      G=gxtxt_statistics_values_v1(group_result);
      R.group_means(gi)=G.mean;R.group_variances(gi)=G.variance;R.group_standard_deviations(gi)=G.standard_deviation;
    endfor
    V=gxtxt_statistics_values_v1(statistics);
    for field={'ss_between','ss_within','ss_total','df_between','df_within','ms_between','ms_within','f_statistic','f_numerator_df','f_denominator_df','p_value','eta_squared','omega_squared'}
      R.(field{1})=V.(field{1});
    endfor
    R.overall_mean=V.grand_mean;
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT One-way ANOVA', ...
      'provenance',sprintf('%s %s; source=%s; value=%s; group=%s; selection=%s; method=%s; nonfinite=%s',module_id,version,source_id,value_id,group_id,selection_id(selection),method,policy), ...
      'notes','Group labels preserve first-seen order; Welch effect sizes are undefined.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids={value_id,group_id};opts.statistical_results=statistical_results;
    group_dataset=[prefix '.groups'];test_dataset=[prefix '.test'];
    gxtxt_progress_stage('publish','Publishing group and ANOVA results','indeterminate');
    publish_table(session,module_id,group_dataset,'group',opts,{ ...
      'group_index','First-seen group index','int64','','index',int64((1:R.group_count)'); ...
      'group_name','Group label','string','','category',R.group_names; ...
      'n','Group observation count','int64','','count',int64(R.group_counts); ...
      'mean','Group mean','float64',value_unit,'derived',R.group_means; ...
      'variance','Group sample variance','float64',squared_unit(value_unit),'derived',R.group_variances; ...
      'std','Group sample standard deviation','float64',value_unit,'derived',R.group_standard_deviations});
    publish_table(session,module_id,test_dataset,'test',opts,{ ...
      'method','ANOVA method','string','','category',{R.method}; ...
      'n_input','Selected observation count','int64','','count',int64(R.n_input); ...
      'n_valid','Valid observation count','int64','','count',int64(R.n_valid); ...
      'n_nonfinite','Excluded observation count','int64','','count',int64(R.n_nonfinite); ...
      'group_count','Group count','int64','','count',int64(R.group_count); ...
      'overall_mean','Overall mean','float64',value_unit,'derived',R.overall_mean; ...
      'ss_between','Between-group sum of squares','float64',squared_unit(value_unit),'derived',R.ss_between; ...
      'ss_within','Within-group sum of squares','float64',squared_unit(value_unit),'derived',R.ss_within; ...
      'ss_total','Total sum of squares','float64',squared_unit(value_unit),'derived',R.ss_total; ...
      'df_between','Between-group degrees of freedom','float64','1','derived',R.df_between; ...
      'df_within','Within-group degrees of freedom','float64','1','derived',R.df_within; ...
      'ms_between','Between-group mean square','float64',squared_unit(value_unit),'derived',R.ms_between; ...
      'ms_within','Within-group mean square','float64',squared_unit(value_unit),'derived',R.ms_within; ...
      'f_statistic','F statistic','float64','1','derived',R.f_statistic; ...
      'f_numerator_df','F numerator degrees of freedom','float64','1','derived',R.f_numerator_df; ...
      'f_denominator_df','F denominator degrees of freedom','float64','1','derived',R.f_denominator_df; ...
      'p_value','p-value','float64','1','derived',R.p_value; ...
      'eta_squared','Eta squared','float64','1','derived',R.eta_squared; ...
      'omega_squared','Omega squared','float64','1','derived',R.omega_squared; ...
      'effect_status','Effect size status','string','','category',{R.effect_status}; ...
      'nonfinite_policy','NaN / Inf policy','string','','category',{R.nonfinite_policy}});
    graph_count=0;graph_id='';variant_id='';artifact='';
    if(parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1')))
      gxtxt_progress_stage('graphs','Creating persistent group-mean graph','indeterminate');
      axis_label=group_axis_label(R.group_names);
      series={struct('id','group_mean','dataset_id',group_dataset,'x_variable_id','group_index','y_variable_id','mean','axis','left','kind','bar','label','Group mean')};
      axes=struct('x',struct('label',axis_label),'y_left',struct('label',['Mean (' value_unit ')']));
      panel=struct('id','main','title','Group means','axes',axes,'series',{series});
      spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title','One-way ANOVA group means','defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
      graph=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
      if(!isfield(graph,'artifact')||exist(graph.artifact,'file')!=2),error('%s: Plot Dataset returned no group graph',module_id);endif
      [ok,msg]=copyfile(graph.artifact,fullfile(outdir,'anova_group_means.png'),'f');
      if(!ok),error('%s: cannot copy group graph: %s',module_id,msg);endif
      graph_count=1;graph_id=graph.graph_id;variant_id=graph.variant_id;artifact=graph.artifact;
    endif
    write_manifest(fullfile(outdir,'automatic_graphs.ini'),graph_count,graph_id,variant_id,artifact);
    write_summary(fullfile(outdir,'anova_summary.ini'),source_id,value_id,group_id,prefix,selection,R,graph_count,statistical_results);
    write_report(fullfile(outdir,'anova_report.txt'),source_id,value_id,group_id,value_unit,selection,R,statistical_results);
    gxtxt_progress_complete('done',sprintf('Published %d groups and %s ANOVA',R.group_count,method));
    fprintf('[%s] source=%s method=%s groups=%d graphs=%d\n%s\n',module_id,source_id,method,R.group_count,graph_count,gxtxt_statistics_v1('report',statistics,{'f_statistic','p_value'}));
  catch err
    try gxtxt_progress_fail('failed','One-way ANOVA failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function [vid,unit,meta]=resolve_source(cfg,source_id,token)
  [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',strtrim(token));
  if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
    error('analysis.statistics.anova: stable source variable could not be resolved');
  endif
  vid=strtrim(meta.variable_id);if(isempty(vid)),error('analysis.statistics.anova: stable variable ID is missing');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.anova: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.anova: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function unit=squared_unit(base)
  if(strcmp(base,'1')),unit='1';else unit=[base '^2'];endif
endfunction
function out=parse_bool(text)
  q=lower(strtrim(text));if(any(strcmp(q,{'1','true','yes','on'}))),out=true;
  elseif(any(strcmp(q,{'0','false','no','off'}))),out=false;
  else error('analysis.statistics.anova: expected a boolean setting');endif
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
function label=group_axis_label(names)
  parts={};for i=1:numel(names),parts{end+1}=sprintf('%d=%s',i,clean(names{i}));endfor
  label=['Group index (' strjoin(parts,', ') ')'];
endfunction
function write_manifest(path,count,graph_id,variant_id,artifact)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.anova: cannot write graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',count);
    if(count),fprintf(fid,'\n[graph.01]\nkey=anova.group_means\ngraph_id=%s\nvariant_id=%s\npng=anova_group_means.png\nprovider_artifact=%s\n',clean(graph_id),clean(variant_id),clean(artifact));endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_summary(path,source_id,value_id,group_id,prefix,selection,R,graphs,statistical_results)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.anova: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.anova\nmodule_version=1.1.0\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nvalue_variable_id=%s\ngroup_variable_id=%s\nselection_id=%s\n',source_id,value_id,group_id,selection_id(selection));
    fprintf(fid,'\n[analysis]\nmethod=%s\nnonfinite_policy=%s\nn_input=%d\nn_valid=%d\ngroup_count=%d\neffect_status=%s\n',R.method,R.nonfinite_policy,R.n_input,R.n_valid,R.group_count,R.effect_status);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',statistical_results.anova,struct('ss_between','ss_between','ss_within','ss_within','df_between','df_between','df_within','df_within','f_statistic','f_statistic','f_denominator_df','f_denominator_df','p_value','p_value')));
    fprintf(fid,'\n[output]\nprefix=%s\nautomatic_graph_count=%d\n',prefix,graphs);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,value_id,group_id,unit,selection,R,statistical_results)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.anova: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT One-way ANOVA\nSource Dataset: %s\nMeasurement: %s (%s)\nGroup variable: %s\nSelection: %s\nMethod: %s\nNaN / Inf: %s\nSelected: %d  Valid: %d\n',source_id,value_id,unit,group_id,selection_id(selection),R.method,R.nonfinite_policy,R.n_input,R.n_valid);
    for i=1:R.group_count
      fprintf(fid,'\nGroup: %s\n',clean(R.group_names{i}));
      fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistical_results.(sprintf('group_%d',i)),{'n','mean','standard_deviation'}));
    endfor
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistical_results.anova,{'ss_between','ss_within','ss_total','f_numerator_df','f_denominator_df','f_statistic','p_value','eta_squared','omega_squared'}));
    fprintf(fid,'Conditional assumptions:\n');for assumption=statistical_results.anova.assumptions(:)',fprintf(fid,'- %s\n',assumption{1});endfor

  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function out=clean(value)
  out=strrep(strrep(char(value),sprintf('\r'),' '),sprintf('\n'),' ');
endfunction
