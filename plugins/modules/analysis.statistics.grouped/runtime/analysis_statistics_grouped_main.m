function analysis_statistics_grouped_main(args,framework_root)
% Production grouped-statistics workflow using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.grouped'; module_version='1.1.0';
  P=struct(); publication_open=false; publication_finalized=false;
  PP=struct(); plot_publication_open=false; plot_publication_finalized=false;
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(outdir)||isempty(session)||isempty(source_dataset_id)),error('%s: runtime session, output directory and primary Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing grouped statistics','indeterminate');
  try
    value_tokens=repeatable_variables(cfg,'values',module_id,false);
    group_tokens=repeatable_variables(cfg,'grouping',module_id,true);
    if(numel(group_tokens)!=1),error('%s: exactly one grouping variable is required',module_id);endif
    nonfinite_policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(nonfinite_policy,{'omit','error'}))),error('%s: NaN / Inf value policy must be omit or error',module_id);endif
    missing_group_policy=lower(strtrim(gxtxt_ini_get(cfg,'config.missing_group_policy','omit')));
    if(!any(strcmp(missing_group_policy,{'omit','error'}))),error('%s: missing / invalid group policy must be omit or error',module_id);endif
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','statistics.grouped.summary'));
    validate_dataset_id(output_dataset_id,module_id,'Grouped summary Dataset ID');
    if(strcmp(output_dataset_id,source_dataset_id)),error('%s: Output Dataset ID must differ from source Dataset ID',module_id);endif
    render_graphs=parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1'),module_id,'Create automatic grouped plots');

    selection=resolve_selection(cfg,source_dataset_id,module_id);
    values=resolve_variables(cfg,value_tokens,source_dataset_id,module_id);
    group=resolve_group_variable(cfg,group_tokens{1},source_dataset_id,module_id);
    numeric=discover_numeric_api(framework_root,module_id);

    gxtxt_progress_stage('read','Reading grouped observations','indeterminate');
    [groups,invalid_group_rows,selected_row_count]=read_grouped_data(cfg,group,values,selection,source_dataset_id,missing_group_policy,module_id);
    if(isempty(groups)),error('%s: no valid groups remain after Selection and group policy',module_id);endif

    gxtxt_progress_stage('statistics','Computing grouped statistics','determinate',numel(groups)*numel(values));
    rows=empty_rows(); warnings={}; done=0; statistical_results=struct();
    for gi=1:numel(groups)
      for vi=1:numel(values)
        vals=groups(gi).values{vi}; n_total=numel(vals); n_valid=sum(isfinite(vals)); n_excluded=n_total-n_valid;
        if(strcmp(nonfinite_policy,'error')&&n_excluded>0),error('%s: group %s, variable %s contains %d NaN/Inf observation(s); choose omit to exclude them explicitly',module_id,groups(gi).label,values(vi).name,n_excluded);endif
        S=feval(numeric.function_name,'statistics',vals,struct('nonfinite',nonfinite_policy,'empty_policy','undefined'));
        context=struct('y_unit',values(vi).unit,'sampling_model','independent_observations','mean_se_model','sampling', ...
          'assumptions',{{'Sampling standard error is conditional on independent observations within this group'}});
        interpreted=gxtxt_statistics_v1('from_numeric','math.numeric.summary','statistics',S,context,struct(), ...
          struct('producer',module_id,'source_dataset_id',source_dataset_id,'source_variable_id',values(vi).variable_id, ...
            'group_variable_id',group.variable_id,'group_key',groups(gi).key));
        statistical_results.(sprintf('group_%d_variable_%d',gi,vi))=interpreted;
        R=stat_result_from_core(interpreted);
        rows(end+1)=make_row(groups(gi),group,values(vi),n_total,n_valid,n_excluded,R);
        if(n_valid==0),warnings{end+1}=sprintf('Group %s, %s: no finite observations; location and spread statistics are undefined.',groups(gi).label,values(vi).name);
        elseif(n_valid==1),warnings{end+1}=sprintf('Group %s, %s: sample standard deviation and standard error are undefined for one finite observation.',groups(gi).label,values(vi).name);endif
        done+=1; gxtxt_progress_update(done,numel(groups)*numel(values),'statistics',sprintf('Computed %d / %d group-variable combinations',done,numel(groups)*numel(values)));
      endfor
    endfor

    gxtxt_progress_stage('publish','Publishing grouped summary Dataset','indeterminate');
    source_variable_ids={group.variable_id}; for i=1:numel(values),source_variable_ids{end+1}=values(i).variable_id;endfor
    if(selection.enabled&&!isempty(selection.x_variable_id)&&!any(strcmp(source_variable_ids,selection.x_variable_id))),source_variable_ids{end+1}=selection.x_variable_id;endif
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source','GX-TXT grouped statistics','provenance',sprintf('%s %s via NUMERIC_API_v1',module_id,module_version), ...
      'notes','One row per group x measured variable. Source Dataset remains unchanged. Undefined sample-spread values are explicitly identified by sample_spread_defined.');
    popts.source_dataset_ids={source_dataset_id}; popts.source_variable_ids=source_variable_ids;
    popts.statistical_results=statistical_results;
    popts.provenance=sprintf('%s; selection=%s; nonfinite=%s; missing_group=%s',popts.provenance,selection_id(selection),nonfinite_policy,missing_group_policy);
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts); publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'result',0,true);
    P=declare_numeric(P,'group_index','Group index','independent','int64','','result');
    P=declare_string(P,'group_key','Stable group key','identifier','result');
    P=declare_string(P,'group_label','Group label','category','result');
    P=declare_numeric(P,'group_numeric_value','Numeric group value','group_value','float64',group.unit,'result');
    P=declare_numeric(P,'group_numeric_defined','Numeric group value defined','flag','bool','','result');
    P=declare_string(P,'group_variable_id','Grouping variable ID','identifier','result');
    P=declare_string(P,'group_variable_name','Grouping variable name','label','result');
    P=declare_string(P,'group_unit','Grouping variable unit','unit','result');
    P=declare_string(P,'variable_id','Source value variable ID','identifier','result');
    P=declare_string(P,'variable_name','Source value variable name','label','result');
    P=declare_string(P,'unit','Value unit','unit','result');
    P=declare_numeric(P,'observation_count','Rows in group','count','int64','','result');
    P=declare_numeric(P,'count','Finite value count','count','int64','','result');
    P=declare_numeric(P,'excluded_count','Excluded NaN/Inf count','count','int64','','result');
    P=declare_numeric(P,'location_defined','Location/range statistics defined','flag','bool','','result');
    P=declare_numeric(P,'sample_spread_defined','Sample spread and SEM defined','flag','bool','','result');
    for name={'minimum','maximum','mean','median','standard_deviation','standard_error','q1','q3','iqr'}
      n=name{1}; P=declare_numeric(P,n,strrep(n,'_',' '),'derived','float64','','result');
    endfor
    items={ ...
      'group_index',int64([rows.group_index]'); ...
      'group_key',{rows.group_key}'; ...
      'group_label',{rows.group_label}'; ...
      'group_numeric_value',[rows.group_numeric_value]'; ...
      'group_numeric_defined',logical([rows.group_numeric_defined]'); ...
      'group_variable_id',{rows.group_variable_id}'; ...
      'group_variable_name',{rows.group_variable_name}'; ...
      'group_unit',{rows.group_unit}'; ...
      'variable_id',{rows.variable_id}'; ...
      'variable_name',{rows.variable_name}'; ...
      'unit',{rows.unit}'; ...
      'observation_count',int64([rows.observation_count]'); ...
      'count',int64([rows.count]'); ...
      'excluded_count',int64([rows.excluded_count]'); ...
      'location_defined',logical([rows.location_defined]'); ...
      'sample_spread_defined',logical([rows.sample_spread_defined]'); ...
      'minimum',[rows.minimum]'; 'maximum',[rows.maximum]'; 'mean',[rows.mean]'; 'median',[rows.median]'; ...
      'standard_deviation',[rows.standard_deviation]'; 'standard_error',[rows.standard_error]'; ...
      'q1',[rows.q1]'; 'q3',[rows.q3]'; 'iqr',[rows.iqr]'};
    P=gxtxt_publication_v2_append(P,'result',items);
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P); [P,pub_result]=gxtxt_publication_v2_finalize(P); publication_finalized=true; publication_open=false;

    plot_dataset_id='none'; plot_provider='none'; graph_count=0;
    if(render_graphs)
      gxtxt_progress_stage('plot_data','Publishing grouped plot-support Dataset','indeterminate');
      plot_dataset_id=[output_dataset_id '.plot']; validate_dataset_id(plot_dataset_id,module_id,'Grouped plot Dataset ID');
      if(strcmp(plot_dataset_id,source_dataset_id)||strcmp(plot_dataset_id,output_dataset_id)),error('%s: grouped plot Dataset ID conflicts with another Dataset',module_id);endif
      [PP,plot_provider]=publish_plot_dataset(session,module_id,module_version,plot_dataset_id,source_dataset_id,source_variable_ids,groups,values,rows,selection,statistical_results); plot_publication_finalized=true; plot_publication_open=false;
      gxtxt_progress_stage('graphs','Creating persistent grouped plot variants','indeterminate');
      graph_count=create_automatic_graphs(outdir,session,plot_dataset_id,group,groups,values,module_id);
    else
      write_empty_graph_manifest(fullfile(outdir,'automatic_graphs.ini'));
    endif

    write_summary_ini(fullfile(outdir,'grouped_statistics_summary.ini'),module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,group,values,groups,selection,nonfinite_policy,missing_group_policy,selected_row_count,invalid_group_rows,numel(rows),numel(warnings),P.provider,plot_provider,graph_count);
    write_report(fullfile(outdir,'grouped_statistics_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,group,values,groups,rows,selection,nonfinite_policy,missing_group_policy,selected_row_count,invalid_group_rows,warnings,P.provider,plot_provider,graph_count,pub_diag,pub_result,statistical_results);
    gxtxt_progress_complete('done',sprintf('Published %s (%d groups, %d variables, %d automatic graphs)',output_dataset_id,numel(groups),numel(values),graph_count));
    fprintf('[%s] version=%s source=%s output=%s groups=%d variables=%d graphs=%d provider=%s\n',module_id,module_version,source_dataset_id,output_dataset_id,numel(groups),numel(values),graph_count,P.provider);
  catch err
    if(plot_publication_open&&!plot_publication_finalized),try PP=gxtxt_publication_v2_abort(PP);catch;end_try_catch,endif
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Grouped statistics failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=arg_value(args,key,default)
  value=default; for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction

function tokens=repeatable_variables(cfg,field,module_id,exactly_one)
  rows=split_list(gxtxt_ini_get(cfg,['repeatable_config.' field '.rows'],''));
  if(isempty(rows)),error('%s: %s requires at least one row',module_id,field);endif
  tokens={};
  for i=1:numel(rows)
    p=['repeatable_config.' field '.' rows{i} '.'];
    token=strtrim(gxtxt_ini_get(cfg,[p 'variable_variable'],''));
    if(isempty(token)),token=strtrim(gxtxt_ini_get(cfg,[p 'variable'],''));endif
    if(isempty(token)),error('%s: %s row %s has no variable',module_id,field,rows{i});endif
    ds=strtrim(gxtxt_ini_get(cfg,[p 'variable_dataset_id'],''));
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(!isempty(ds) && !strcmp(ds,source_dataset_id))
      error('%s: %s row %s belongs to a different Dataset',module_id,field,rows{i});
    endif
    tokens{end+1}=token;
  endfor
  if(exactly_one&&numel(tokens)!=1),error('%s: %s requires exactly one variable',module_id,field);endif
endfunction

function vars=resolve_variables(cfg,tokens,dataset_id,module_id)
  vars=struct('name',{},'variable_id',{},'unit',{},'dtype',{},'value_kind',{});
  for i=1:numel(tokens)
    [unit,~,m]=gxtxt_analysis_source_variable_meta(cfg,'primary',tokens{i});
    if(!(isstruct(m)&&isfield(m,'found')&&m.found)),error('%s: value variable could not be resolved: %s',module_id,tokens{i});endif
    if(!strcmp(strtrim(m.dataset_id),dataset_id)),error('%s: value variable %s belongs to a different Dataset',module_id,tokens{i});endif
    id=strtrim(m.variable_id); if(isempty(id)),error('%s: value variable %s has no stable variable_id',module_id,tokens{i});endif
    dtype=source_variable_field(cfg,'primary',id,'dtype',''); kind=source_variable_field(cfg,'primary',id,'value_kind',m.value_kind);
    if(strcmp(dtype,'string')||strcmp(kind,'text')),error('%s: value variable %s is not numeric',module_id,m.name);endif
    if(any(strcmp({vars.variable_id},id))),error('%s: duplicate selected value variable: %s',module_id,m.name);endif
    vars(end+1)=struct('name',m.name,'variable_id',id,'unit',effective_unit(m,unit),'dtype',dtype,'value_kind',kind);
  endfor
endfunction

function group=resolve_group_variable(cfg,token,dataset_id,module_id)
  [unit,~,m]=gxtxt_analysis_source_variable_meta(cfg,'primary',token);
  if(!(isstruct(m)&&isfield(m,'found')&&m.found)),error('%s: grouping variable could not be resolved: %s',module_id,token);endif
  if(!strcmp(strtrim(m.dataset_id),dataset_id)),error('%s: grouping variable belongs to a different Dataset',module_id);endif
  id=strtrim(m.variable_id); if(isempty(id)),error('%s: grouping variable has no stable variable_id',module_id);endif
  dtype=source_variable_field(cfg,'primary',id,'dtype',''); kind=source_variable_field(cfg,'primary',id,'value_kind',m.value_kind);
  if(isempty(dtype)),error('%s: grouping variable %s has no Dataset Schema v3 dtype',module_id,m.name);endif
  group=struct('name',m.name,'variable_id',id,'unit',effective_unit(m,unit),'dtype',dtype,'value_kind',kind,'is_text',strcmp(dtype,'string')||strcmp(kind,'text'));
endfunction

function unit=effective_unit(meta,declared)
  unit=strtrim(declared); kind='';fmt=''; if(isfield(meta,'value_kind')),kind=lower(strtrim(meta.value_kind));endif;if(isfield(meta,'value_format')),fmt=lower(strtrim(meta.value_format));endif
  if(strcmp(kind,'elapsed_time')&&strcmp(fmt,'hms')),unit='s';endif
endfunction

function value=source_variable_field(cfg,source_id,variable_id,field,default)
  value=default; n=str2double(strtrim(gxtxt_ini_get(cfg,['analysis_source.' source_id '.variable_count'],'0'))); if(!isfinite(n)),return;endif
  for i=1:round(n)
    p=sprintf('analysis_source.%s.variable.%d.',source_id,i); id=strtrim(gxtxt_ini_get(cfg,[p 'variable_id'],''));
    if(strcmp(id,variable_id)),value=strtrim(gxtxt_ini_get(cfg,[p field],default));return;endif
  endfor
endfunction

function selection=resolve_selection(cfg,dataset_id,module_id)
  selection=struct('enabled',false);
  try selection=gxtxt_selection_from_runtime(cfg,'selection');catch err,error('%s: invalid Dataset Selection: %s',module_id,err.message);end_try_catch
  if(!selection.enabled),return;endif
  if(!strcmp(selection.type,'x_range')),error('%s: only x_range Dataset Selection is supported',module_id);endif
  if(!strcmp(strtrim(selection.source_dataset_id),dataset_id)),error('%s: Dataset Selection belongs to a different source Dataset',module_id);endif
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,m]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(m)&&isfield(m,'found')&&m.found)),error('%s: Dataset Selection X variable could not be resolved',module_id);endif
    selection.x_variable_id=strtrim(m.variable_id);
  endif
  if(isempty(selection.x_variable_id)),error('%s: Dataset Selection requires a stable X variable ID',module_id);endif
endfunction

function [groups,invalid_group_rows,selected_row_count]=read_grouped_data(cfg,group,values,selection,dataset_id,missing_group_policy,module_id)
  ids={group.variable_id}; for i=1:numel(values),if(!any(strcmp(ids,values(i).variable_id))),ids{end+1}=values(i).variable_id;endif,endfor
  if(selection.enabled&&!any(strcmp(ids,selection.x_variable_id))),ids{end+1}=selection.x_variable_id;endif
  S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  groups=struct('index',{},'key',{},'label',{},'numeric_value',{},'numeric_defined',{},'observation_count',{},'values',{}); invalid_group_rows=0; selected_row_count=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S); if(C.nrows<1),continue;endif
      gcol=gxtxt_table_chunk_column(C,group.variable_id); vcols=cell(1,numel(values)); for vi=1:numel(values),tmpv=gxtxt_table_chunk_numeric(C,values(vi).variable_id);vcols{vi}=double(tmpv(:));endfor
      mask=true(C.nrows,1); if(selection.enabled),x=double(gxtxt_table_chunk_numeric(C,selection.x_variable_id)(:));mask=gxtxt_selection_mask(selection,x);mask=logical(mask(:));endif
      idx=find(mask); selected_row_count+=numel(idx);
      for jj=1:numel(idx)
        r=idx(jj); [ok,key,label,numeric_value,numeric_defined]=group_identity(gcol,r,group);
        if(!ok)
          invalid_group_rows+=1; if(strcmp(missing_group_policy,'error')),error('%s: grouping variable %s contains a missing/invalid value in the selected rows',module_id,group.name);else continue;endif
        endif
        gi=find(strcmp({groups.key},key),1);
        if(isempty(gi))
          gi=numel(groups)+1; vals=cell(1,numel(values)); for vi=1:numel(values),vals{vi}=zeros(0,1);endfor
          groups(gi)=struct('index',gi,'key',key,'label',label,'numeric_value',numeric_value,'numeric_defined',numeric_defined,'observation_count',0,'values',{vals});
        endif
        groups(gi).observation_count+=1;
        for vi=1:numel(values),groups(gi).values{vi}(end+1,1)=vcols{vi}(r);endfor
      endfor
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
endfunction

function [ok,key,label,numeric_value,numeric_defined]=group_identity(column,row,group)
  numeric_value=NaN; numeric_defined=false; ok=true;
  if(group.is_text)
    if(iscell(column)),raw=column{row};else raw=column(row,:);endif
    if(!ischar(raw)),raw=char(raw);endif
    if(isempty(strtrim(raw))),ok=false;key='';label='';return;endif
    label=raw; key=['text:' raw]; return;
  endif
  v=double(column(row)); if(!isfinite(v)),ok=false;key='';label='';return;endif
  if(v==0),v=0;endif; numeric_value=v; numeric_defined=true;
  if(strcmp(group.dtype,'bool')),label=ternary(v!=0,'true','false');key=['bool:' label];
  elseif(any(strcmp(group.dtype,{'int8','int16','int32','int64'}))),label=sprintf('%.0f',v);key=[group.dtype ':' label];
  elseif(any(strcmp(group.dtype,{'uint8','uint16','uint32','uint64'}))),label=sprintf('%.0f',v);key=[group.dtype ':' label];
  else label=sprintf('%.17g',v);key=[group.dtype ':' label];endif
endfunction

function out=ternary(cond,a,b),if(cond),out=a;else out=b;endif,endfunction

function api=discover_numeric_api(framework_root,module_id)
  descriptor=fullfile(framework_root,'plugins','modules','math.numeric','module.ini'); if(exist(descriptor,'file')!=2),error('%s: required math.numeric module descriptor is missing',module_id);endif
  d=gxtxt_ini_read(descriptor); ids=split_list(gxtxt_ini_get(d,'public_apis.ids','')); if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: required public NUMERIC_API_v1 is not advertised',module_id);endif
  fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function','')); ep=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));
  if(isempty(fn)||isempty(ep)),error('%s: NUMERIC_API_v1 Octave binding is incomplete',module_id);endif
  addpath(fileparts(fullfile(fileparts(descriptor),ep))); if(exist(fn,'file')!=2),error('%s: NUMERIC_API_v1 Octave function is unavailable',module_id);endif
  api=struct('function_name',fn);
endfunction

function R=stat_result_from_core(interpreted)
  V=gxtxt_statistics_values_v1(interpreted);
  R=struct('minimum',V.minimum,'maximum',V.maximum,'mean',V.mean,'median',V.median, ...
    'standard_deviation',V.standard_deviation,'standard_error',V.standard_error_mean, ...
    'q1',V.quartile_1,'q3',V.quartile_3,'iqr',V.interquartile_range, ...
    'location_defined',strcmp(interpreted.quantities.mean.status,'value'), ...
    'sample_spread_defined',strcmp(interpreted.quantities.standard_error_mean.status,'value'));
endfunction

function rows=empty_rows()
  rows=struct('group_index',{},'group_key',{},'group_label',{},'group_numeric_value',{},'group_numeric_defined',{},'group_variable_id',{},'group_variable_name',{},'group_unit',{},'variable_id',{},'variable_name',{},'unit',{},'observation_count',{},'count',{},'excluded_count',{},'location_defined',{},'sample_spread_defined',{},'minimum',{},'maximum',{},'mean',{},'median',{},'standard_deviation',{},'standard_error',{},'q1',{},'q3',{},'iqr',{});
endfunction
function row=make_row(G,group,V,n_total,n_valid,n_excluded,R)
  row=struct('group_index',G.index,'group_key',G.key,'group_label',G.label,'group_numeric_value',G.numeric_value,'group_numeric_defined',G.numeric_defined,'group_variable_id',group.variable_id,'group_variable_name',group.name,'group_unit',group.unit,'variable_id',V.variable_id,'variable_name',V.name,'unit',V.unit,'observation_count',n_total,'count',n_valid,'excluded_count',n_excluded,'location_defined',R.location_defined,'sample_spread_defined',R.sample_spread_defined,'minimum',R.minimum,'maximum',R.maximum,'mean',R.mean,'median',R.median,'standard_deviation',R.standard_deviation,'standard_error',R.standard_error,'q1',R.q1,'q3',R.q3,'iqr',R.iqr);
endfunction

function P=declare_string(P,id,name,role,dimension_id),P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype','string','dimension_ids',dimension_id,'name',name,'unit','','semantic_role',role));endfunction
function P=declare_numeric(P,id,name,role,dtype,unit,dimension_id),P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype',dtype,'dimension_ids',dimension_id,'name',name,'unit',unit,'semantic_role',role));endfunction

function [P,provider]=publish_plot_dataset(session,module_id,module_version,dataset_id,source_dataset_id,source_variable_ids,groups,values,rows,selection,statistical_results)
  P=struct(); opened=false; finalized=false;
  try
    opts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source','GX-TXT grouped statistics plot support', ...
      'provenance',sprintf('%s %s automatic grouped-plot support; selection=%s',module_id,module_version,selection_id(selection)), ...
      'notes','One row per group. group_index is the numeric plotting coordinate; group_label preserves the original category. Statistical variables are in each source variable unit.');
    opts.source_dataset_ids={source_dataset_id};opts.source_variable_ids=source_variable_ids;opts.statistical_results=statistical_results;
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts);opened=true;P=gxtxt_publication_v2_declare_dimension(P,'group',0,true);
    P=declare_numeric(P,'group_index','Group index','independent','int64','','group');P=declare_string(P,'group_label','Group label','category','group');P=declare_numeric(P,'group_observation_count','Rows in group','count','int64','','group');
    items={'group_index',int64([groups.index]');'group_label',{groups.label}';'group_observation_count',int64([groups.observation_count]')};
    for vi=1:numel(values)
      V=values(vi); suffix=sprintf('%03d',vi); rr=rows(strcmp({rows.variable_id},V.variable_id)); if(numel(rr)!=numel(groups)),error('%s: internal grouped plot row mismatch',module_id);endif
      meanv=[rr.mean]'; semv=[rr.standard_error]'; med=[rr.median]'; q1=[rr.q1]';q3=[rr.q3]';low=med-q1;high=q3-med;cnt=int64([rr.count]');
      P=declare_numeric(P,['mean_' suffix],[V.name ' mean'],'derived','float64',V.unit,'group');
      P=declare_numeric(P,['sem_' suffix],[V.name ' standard error'],'uncertainty','float64',V.unit,'group');
      P=declare_numeric(P,['median_' suffix],[V.name ' median'],'derived','float64',V.unit,'group');
      P=declare_numeric(P,['iqr_lower_' suffix],[V.name ' median to Q1'],'uncertainty','float64',V.unit,'group');
      P=declare_numeric(P,['iqr_upper_' suffix],[V.name ' Q3 to median'],'uncertainty','float64',V.unit,'group');
      P=declare_numeric(P,['valid_count_' suffix],[V.name ' finite count'],'count','int64','','group');
      items(end+1,:)={['mean_' suffix],meanv};items(end+1,:)={['sem_' suffix],semv};items(end+1,:)={['median_' suffix],med};items(end+1,:)={['iqr_lower_' suffix],low};items(end+1,:)={['iqr_upper_' suffix],high};items(end+1,:)={['valid_count_' suffix],cnt};
    endfor
    P=gxtxt_publication_v2_append(P,'group',items);[P,~]=gxtxt_publication_v2_diagnostics(P);[P,~]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;provider=P.provider;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    rethrow(err);
  end_try_catch
endfunction

function graph_count=create_automatic_graphs(outdir,session,dataset_id,group,groups,values,module_id)
  if(exist('gxtxt_plot_dataset_v2','file')!=2),error('%s: public Plot Dataset Octave Bridge v1 is unavailable; GX-TXT 0.9.7.86 or newer is required',module_id);endif
  unit_groups=group_plot_variables(values);records=struct('key',{},'kind',{},'unit_group',{},'display_unit',{},'title',{},'graph_id',{},'variant_id',{},'png',{},'provider_artifact',{});graph_count=0;
  annotations=group_annotations(groups,group);axis_label=group_axis_label(groups);
  for gi=1:numel(unit_groups)
    U=unit_groups{gi};display_unit=U.display_unit;indices=U.indices;unit_text=unit_group_text(display_unit);
    title_text=['Grouped means +/- SEM - ' unit_text];spec=group_plot_spec(dataset_id,groups,values,indices,display_unit,'mean_sem',title_text,annotations,gi,axis_label);
    result=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));graph_count+=1;slug=sprintf('%02d_mean_sem_group_%02d.png',graph_count,gi);copy_plot_artifact(result.artifact,fullfile(outdir,slug),module_id);records(end+1)=graph_record('mean_sem',gi,display_unit,title_text,result,slug);
    title_text=['Grouped medians + IQR - ' unit_text];spec=group_plot_spec(dataset_id,groups,values,indices,display_unit,'median_iqr',title_text,annotations,gi,axis_label);
    result=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));graph_count+=1;slug=sprintf('%02d_median_iqr_group_%02d.png',graph_count,gi);copy_plot_artifact(result.artifact,fullfile(outdir,slug),module_id);records(end+1)=graph_record('median_iqr',gi,display_unit,title_text,result,slug);
  endfor
  title_text='Grouped observation count';spec=count_plot_spec(dataset_id,title_text,annotations,axis_label,groups);
  result=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));graph_count+=1;slug=sprintf('%02d_group_count.png',graph_count);copy_plot_artifact(result.artifact,fullfile(outdir,slug),module_id);records(end+1)=graph_record('group_count',0,'',title_text,result,slug);
  write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),records,groups,group);
endfunction

function groups_out=group_plot_variables(values)
  groups_out={};
  for i=1:numel(values)
    placed=false;for g=1:numel(groups_out),if(plot_units_compatible(values(i).unit,groups_out{g}.display_unit)),groups_out{g}.indices(end+1)=i;placed=true;break;endif,endfor
    if(!placed),groups_out{end+1}=struct('display_unit',values(i).unit,'indices',i);endif
  endfor
endfunction
function tf=plot_units_compatible(a,b),a=strtrim(a);b=strtrim(b);if(isempty(a)||isempty(b)),tf=isempty(a)&&isempty(b);return;endif;try tf=logical(gxtxt_unit_compatible(a,b));catch,tf=strcmp(a,b);end_try_catch,endfunction
function s=unit_group_text(unit),if(isempty(strtrim(unit))),s='unitless values';else s=[unit '-compatible values'];endif,endfunction

function annotations=group_annotations(groups,group)
  annotations={};if(numel(groups)>10),return;endif
  for i=1:numel(groups)
    label=groups(i).label;if(!isempty(group.unit)&&groups(i).numeric_defined),label=[label ' ' group.unit];endif
    label=strrep(label,char(10),' ');label=strrep(label,char(13),' ');
    annotations{end+1}=struct('type','reference_line','axis','x','value',groups(i).index,'label',label,'line_style','dotted');
  endfor
endfunction

function label=group_axis_label(groups)
  label='Group index';
  if(numel(groups)>6),return;endif
  parts=cell(1,numel(groups));
  for k=1:numel(groups)
    clean=strrep(strrep(groups(k).label,char(10),' '),char(13),' ');
    parts{k}=sprintf('%d=%s',groups(k).index,clean);
  endfor
  label=['Group index (' strjoin(parts,', ') ')'];
endfunction

function spec=group_plot_spec(dataset_id,groups,values,indices,display_unit,mode,title_text,annotations,unit_group_index,axis_label)
  series=cell(1,numel(indices));
  for j=1:numel(indices)
    vi=indices(j);V=values(vi);suffix=sprintf('%03d',vi);
    if(strcmp(mode,'mean_sem'))
      yid=['mean_' suffix];err=struct('mode','symmetric','variable_id',['sem_' suffix]);sid=sprintf('mean_sem_%02d_%02d',unit_group_index,j);
    else
      yid=['median_' suffix];err=struct('mode','asymmetric','lower_variable_id',['iqr_lower_' suffix],'upper_variable_id',['iqr_upper_' suffix]);sid=sprintf('median_iqr_%02d_%02d',unit_group_index,j);
    endif
    series{j}=struct('id',sid,'dataset_id',dataset_id,'x_variable_id','group_index','y_variable_id',yid,'axis','left','kind','errorbar','label',V.name,'y_error',err);
  endfor
  axes=struct('x',struct('label',axis_label,'min',0.5,'max',numel(groups)+0.5));
  yr=group_plot_range(groups,values,indices,display_unit);
  if(!isempty(fieldnames(yr))),axes.y_left=yr;endif
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
endfunction

function yr=group_plot_range(groups,values,indices,display_unit)
  yr=struct();mins=[];maxs=[];
  for g=1:numel(groups)
    for k=1:numel(indices)
      vi=indices(k);v=groups(g).values{vi};v=v(isfinite(v));
      if(isempty(v)),continue;endif
      bounds=[min(v),max(v)];
      if(!strcmp(strtrim(values(vi).unit),strtrim(display_unit)))
        bounds=gxtxt_unit_convert(bounds,values(vi).unit,display_unit);
      endif
      mins(end+1)=min(bounds);maxs(end+1)=max(bounds);
    endfor
  endfor
  if(isempty(mins)),return;endif
  lo=min(mins);hi=max(maxs);pad=max((hi-lo)*0.1,max(abs([lo hi]))*0.02);
  if(pad<=0),pad=1;endif
  yr=struct('min',lo-pad,'max',hi+pad);
  if(!isempty(strtrim(display_unit))),yr.display_unit=display_unit;endif
endfunction

function spec=count_plot_spec(dataset_id,title_text,annotations,axis_label,groups)
  series={struct('id','group_observation_count','dataset_id',dataset_id,'x_variable_id','group_index','y_variable_id','group_observation_count','axis','left','kind','bar','label','Rows per group')};
  count_max=max([groups.observation_count]);
  axes=struct('x',struct('label',axis_label,'min',0.5,'max',numel(groups)+0.5),'y_left',struct('min',0,'max',max(1,count_max*1.1)));
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
endfunction

function copy_plot_artifact(source,destination,module_id),if(isempty(strtrim(source))||exist(source,'file')!=2),error('%s: plot.dataset did not return a readable graph artifact',module_id);endif;[ok,msg]=copyfile(source,destination,'f');if(!ok||exist(destination,'file')!=2),error('%s: cannot copy automatic graph artifact: %s',module_id,msg);endif,endfunction
function R=graph_record(kind,unit_group,display_unit,title_text,result,slug),R=struct('key',sprintf('%s.%02d',kind,max(0,unit_group)),'kind',kind,'unit_group',unit_group,'display_unit',display_unit,'title',title_text,'graph_id',result.graph_id,'variant_id',result.variant_id,'png',slug,'provider_artifact',result.artifact);endfunction

function write_graph_manifest(path,records,groups,group)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.grouped: cannot write automatic graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n',numel(records));
    fprintf(fid,'\n[group_mapping]\nvariable_id=%s\nvariable_name=%s\nunit=%s\ncount=%d\n',sanitize_ini(group.variable_id),sanitize_ini(group.name),sanitize_ini(group.unit),numel(groups));
    for g=1:numel(groups),fprintf(fid,'group.%d=%s\n',groups(g).index,sanitize_ini(groups(g).label));endfor
    for i=1:numel(records),R=records(i);fprintf(fid,'\n[graph.%02d]\nkey=%s\nkind=%s\nunit_group=%d\ndisplay_unit=%s\ntitle=%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n',i,sanitize_ini(R.key),sanitize_ini(R.kind),R.unit_group,sanitize_ini(R.display_unit),sanitize_ini(R.title),sanitize_ini(R.graph_id),sanitize_ini(R.variant_id),sanitize_ini(R.png),sanitize_ini(R.provider_artifact));endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
function write_empty_graph_manifest(path),fid=fopen(path,'w');if(fid<0),error('analysis.statistics.grouped: cannot write automatic graph manifest');endif;unwind_protect,fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n');unwind_protect_cleanup,fclose(fid);end_unwind_protect,endfunction

function write_summary_ini(path,module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,group,values,groups,selection,nonfinite_policy,missing_group_policy,selected_rows,invalid_group_rows,result_rows,warning_count,provider,plot_provider,graph_count)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write summary INI',module_id);endif
  unwind_protect
    fprintf(fid,'[module]\nid=%s\nversion=%s\n\n',module_id,module_version);
    fprintf(fid,'[source]\ndataset_id=%s\ngroup_variable_id=%s\ngroup_variable_name=%s\ngroup_unit=%s\nvalue_variable_count=%d\nselection_id=%s\nnonfinite_policy=%s\nmissing_group_policy=%s\nselected_rows=%d\ninvalid_group_rows=%d\n\n',source_dataset_id,sanitize_ini(group.variable_id),sanitize_ini(group.name),sanitize_ini(group.unit),numel(values),selection_id(selection),nonfinite_policy,missing_group_policy,selected_rows,invalid_group_rows);
    fprintf(fid,'[output]\ndataset_id=%s\nprovider=%s\nresult_rows=%d\ngroup_count=%d\nwarning_count=%d\nplot_dataset_id=%s\nplot_provider=%s\nautomatic_graph_count=%d\n',output_dataset_id,provider,result_rows,numel(groups),warning_count,plot_dataset_id,plot_provider,graph_count);
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function write_report(path,module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,group,values,groups,rows,selection,nonfinite_policy,missing_group_policy,selected_rows,invalid_group_rows,warnings,provider,plot_provider,graph_count,pub_diag,pub_result,statistical_results)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write report',module_id);endif
  unwind_protect
    fprintf(fid,'GX-TXT Grouped Statistics\n=========================\n\nProducer: %s %s\nInput Dataset: %s\nOutput Dataset: %s\nStorage provider: %s\nGrouping variable: %s [%s]',module_id,module_version,source_dataset_id,output_dataset_id,provider,group.name,group.variable_id);if(!isempty(group.unit)),fprintf(fid,' (%s)',group.unit);endif;fprintf(fid,'\nSelection: %s\nNaN / Inf value policy: %s\nMissing / invalid group policy: %s\nSelected rows: %d\nRows excluded for invalid group: %d\nGroups: %d\nValue variables: %d\nAutomatic graph count: %d\n',selection_id(selection),nonfinite_policy,missing_group_policy,selected_rows,invalid_group_rows,numel(groups),numel(values),graph_count);
    if(!strcmp(plot_dataset_id,'none')),fprintf(fid,'Grouped plot Dataset: %s (provider %s)\n',plot_dataset_id,plot_provider);endif
    fprintf(fid,'\nGroup mapping\n-------------\n');for g=1:numel(groups),fprintf(fid,'%d -> %s',groups(g).index,groups(g).label);if(!isempty(group.unit)&&groups(g).numeric_defined),fprintf(fid,' %s',group.unit);endif;fprintf(fid,'  rows=%d\n',groups(g).observation_count);endfor
    fprintf(fid,'\nResults\n-------\n');
    for g=1:numel(groups)
      fprintf(fid,'\nGroup %d: %s\n',groups(g).index,groups(g).label);
      for vi=1:numel(values)
        V=values(vi);idx=find([rows.group_index]==g & strcmp({rows.variable_id},V.variable_id),1);R=rows(idx);fprintf(fid,'  %s [%s]',V.name,V.variable_id);if(!isempty(V.unit)),fprintf(fid,' (%s)',V.unit);endif;fprintf(fid,'\n    rows=%d finite=%d excluded_nonfinite=%d\n',R.observation_count,R.count,R.excluded_count);
        interpreted=statistical_results.(sprintf('group_%d_variable_%d',g,vi));
        fprintf(fid,'%s\n',gxtxt_statistics_v1('report',interpreted,{'minimum','maximum','mean','median','quartile_1','quartile_3','interquartile_range','standard_deviation','standard_error_mean'}));
      endfor
    endfor
    fprintf(fid,'\nWarnings\n--------\n');if(isempty(warnings)),fprintf(fid,'None.\n');else for i=1:numel(warnings),fprintf(fid,'- %s\n',warnings{i});endfor,endif
    fprintf(fid,'\nGraphics\n--------\n');if(graph_count>0),fprintf(fid,'Persistent plot.dataset variants were created for mean +/- SEM, median + IQR, and group observation count. Compatible value units share a plot; incompatible units are separated. The X coordinate is stable group_index; the group mapping above and the plot-support Dataset preserve the original labels. For up to 10 groups, reference-line annotations also label group positions.\n');else fprintf(fid,'Automatic graphs were disabled.\n');endif
    fprintf(fid,'\nPublication diagnostics/result\n------------------------------\nPublication diagnostics available: %d\nPublication result available: %d\n',isstruct(pub_diag),isstruct(pub_result));
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function s=selection_id(selection),if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')&&!isempty(selection.id)),s=selection.id;else s='none';endif,endfunction
function value=parse_bool(text,module_id,label),q=lower(strtrim(text));if(any(strcmp(q,{'1','true','yes','on'}))),value=true;return;endif;if(any(strcmp(q,{'0','false','no','off'}))),value=false;return;endif;error('%s: %s must be boolean',module_id,label);endfunction
function validate_dataset_id(id,module_id,label),if(isempty(regexp(id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid %s',module_id,label);endif,endfunction
function out=split_list(s),s=strrep(strtrim(s),',',';');if(isempty(s)),out={};else out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endif,endfunction
function s=sanitize_ini(s),s=strrep(s,char(13),' ');s=strrep(s,char(10),' ');endfunction
