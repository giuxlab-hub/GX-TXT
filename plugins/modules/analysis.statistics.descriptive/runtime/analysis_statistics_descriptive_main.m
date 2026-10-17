function analysis_statistics_descriptive_main(args,framework_root)
% Production descriptive-statistics workflow using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.descriptive'; module_version='1.2.0';
  publication_open=false; publication_finalized=false; P=struct();
  sample_publication_open=false; sample_publication_finalized=false; PS=struct();
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(outdir)||isempty(session)||isempty(source_dataset_id)),error('%s: runtime session, output directory and primary Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing descriptive statistics','indeterminate');
  try
    variable_tokens=repeatable_variables(cfg,module_id);
    nonfinite_policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(nonfinite_policy,{'omit','error'}))),error('%s: NaN / Inf policy must be omit or error',module_id);endif
    percentile_probabilities=parse_percentiles(gxtxt_ini_get(cfg,'config.percentiles',''));
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','statistics.descriptive.summary'));
    validate_dataset_id(output_dataset_id,module_id,'Output Dataset ID');
    if(strcmp(output_dataset_id,source_dataset_id)),error('%s: Output Dataset ID must differ from source Dataset ID',module_id);endif

    render_graphs=parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1'),module_id,'Create automatic distribution plots');
    histogram_bins=parse_histogram_bins(gxtxt_ini_get(cfg,'config.histogram_bins','auto'),module_id);
    histogram_normalization=lower(strtrim(gxtxt_ini_get(cfg,'config.histogram_normalization','count')));
    if(!any(strcmp(histogram_normalization,{'count','probability','density'}))),error('%s: histogram normalization must be count, probability or density',module_id);endif
    box_whisker_iqr=str2double(strtrim(gxtxt_ini_get(cfg,'config.box_whisker_iqr','1.5')));
    if(!isfinite(box_whisker_iqr)||box_whisker_iqr<=0),error('%s: box/whisker IQR multiplier must be positive',module_id);endif
    box_show_outliers=parse_bool(gxtxt_ini_get(cfg,'config.box_show_outliers','1'),module_id,'Show box/whisker outliers');

    selection=struct('enabled',false);
    try selection=gxtxt_selection_from_runtime(cfg,'selection'); catch selerr,error('%s: invalid Dataset Selection: %s',module_id,selerr.message); end_try_catch
    if(selection.enabled)
      if(!strcmp(selection.type,'x_range')),error('%s: only x_range Dataset Selection is supported',module_id);endif
      if(!strcmp(strtrim(selection.source_dataset_id),source_dataset_id)),error('%s: Dataset Selection belongs to a different source Dataset',module_id);endif
      if(isempty(strtrim(selection.x_variable_id)))
        [~,~,selection_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
        if(!(isstruct(selection_meta)&&isfield(selection_meta,'found')&&selection_meta.found)),error('%s: Dataset Selection X variable could not be resolved',module_id);endif
        selection.x_variable_id=strtrim(selection_meta.variable_id);
      endif
      if(isempty(selection.x_variable_id)),error('%s: Dataset Selection requires a stable X variable ID',module_id);endif
    endif

    numeric=discover_numeric_api(framework_root,module_id);
    variables=resolve_variables(cfg,variable_tokens,source_dataset_id,module_id);
    gxtxt_progress_stage('statistics','Computing descriptive statistics','determinate',numel(variables));
    rows=empty_rows(); warnings={}; selected_values=cell(1,numel(variables)); statistical_results=struct();
    for i=1:numel(variables)
      V=variables(i);
      values=read_selected_variable(cfg,V.variable_id,selection,source_dataset_id,module_id);
      selected_values{i}=values;
      n_total=numel(values); n_valid=sum(isfinite(values)); n_excluded=n_total-n_valid;
      if(n_total<1),error('%s: variable %s has no observations in the selected data',module_id,V.name);endif
      if(strcmp(nonfinite_policy,'error') && n_excluded>0),error('%s: variable %s contains %d NaN/Inf observation(s); choose omit to exclude them explicitly',module_id,V.name,n_excluded);endif
      if(n_valid<1),error('%s: variable %s has no finite observations',module_id,V.name);endif
      opts=struct('nonfinite',nonfinite_policy);
      S=feval(numeric.function_name,'statistics',values,opts);
      context=struct('y_unit',V.unit,'sampling_model','independent_observations','mean_se_model','sampling', ...
        'assumptions',{{'Sampling standard error is conditional on independent observations with finite variance'}});
      interpreted=gxtxt_statistics_v1('from_numeric','math.numeric.summary','statistics',S,context,struct(), ...
        struct('producer',module_id,'source_dataset_id',source_dataset_id,'source_variable_id',V.variable_id));
      statistical_results.(sprintf('variable_%d',i))=interpreted;
      Q=struct('probabilities',[],'quantiles',[],'definition','');
      if(!isempty(percentile_probabilities))
        Q=feval(numeric.function_name,'quantiles',values,percentile_probabilities,opts);
        quantile_result=gxtxt_statistics_v1('from_numeric','math.numeric.summary','quantiles',Q,context,struct(), ...
          struct('producer',module_id,'source_dataset_id',source_dataset_id,'source_variable_id',V.variable_id));
        statistical_results.(sprintf('quantiles_%d',i))=quantile_result;
        Q.quantiles=quantile_result.quantities.quantiles.value;
      endif
      rows=append_standard_rows(rows,V,interpreted,n_total,n_valid,n_excluded);
      rows=append_percentile_rows(rows,V,Q,n_total,n_valid,n_excluded);
      if(n_valid<2),warnings{end+1}=sprintf('%s (%s): sample variance, sample standard deviation and standard error are undefined for one valid observation.',V.name,V.variable_id);endif
      gxtxt_progress_update(i,numel(variables),'statistics',sprintf('Computed %d / %d variables',i,numel(variables)));
    endfor

    gxtxt_progress_stage('publish','Publishing descriptive summary Dataset','indeterminate');
    source_variable_ids={variables.variable_id};
    if(selection.enabled && !isempty(selection.x_variable_id) && !any(strcmp(source_variable_ids,selection.x_variable_id))),source_variable_ids{end+1}=selection.x_variable_id;endif
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source','GX-TXT descriptive statistics','provenance',sprintf('%s %s via NUMERIC_API_v1',module_id,module_version), ...
      'notes','Long-form descriptive statistics. Row-level unit and unit_power preserve dimensional meaning; source Dataset is unchanged.');
    popts.source_dataset_ids={source_dataset_id};
    popts.source_variable_ids=source_variable_ids;
    popts.statistical_results=statistical_results;
    popts.provenance=sprintf('%s; selection=%s; nonfinite=%s',popts.provenance,selection_id(selection),nonfinite_policy);
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts); publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'result',0,true);
    P=declare_string(P,'variable_id','Source variable ID','identifier','result');
    P=declare_string(P,'variable_name','Source variable name','label','result');
    P=declare_string(P,'statistic','Statistic','category','result');
    P=declare_numeric(P,'value','Statistic value','derived','float64','','result');
    P=declare_numeric(P,'defined','Mathematically defined','flag','bool','','result');
    P=declare_string(P,'unit','Result base unit','unit','result');
    P=declare_numeric(P,'unit_power','Power of source unit','dimension','int8','','result');
    P=declare_numeric(P,'observation_count','Selected observation count','count','int64','','result');
    P=declare_numeric(P,'valid_count','Finite observation count','count','int64','','result');
    P=declare_numeric(P,'excluded_count','Excluded NaN/Inf count','count','int64','','result');
    items={ ...
      'variable_id',{rows.variable_id}'; ...
      'variable_name',{rows.variable_name}'; ...
      'statistic',{rows.statistic}'; ...
      'value',[rows.value]'; ...
      'defined',logical([rows.defined]'); ...
      'unit',{rows.unit}'; ...
      'unit_power',int8([rows.unit_power]'); ...
      'observation_count',int64([rows.observation_count]'); ...
      'valid_count',int64([rows.valid_count]'); ...
      'excluded_count',int64([rows.excluded_count]')};
    P=gxtxt_publication_v2_append(P,'result',items);
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);
    [P,pub_result]=gxtxt_publication_v2_finalize(P); publication_finalized=true; publication_open=false;

    plot_dataset_id='none'; plot_provider='none'; graph_count=0;
    if(render_graphs)
      gxtxt_progress_stage('plot_sample','Publishing selected sample for distribution plots','indeterminate');
      plot_dataset_id=[output_dataset_id '.sample'];
      validate_dataset_id(plot_dataset_id,module_id,'Automatic plot sample Dataset ID');
      if(strcmp(plot_dataset_id,source_dataset_id)||strcmp(plot_dataset_id,output_dataset_id)),error('%s: automatic plot sample Dataset ID conflicts with another Dataset',module_id);endif
      [PS,plot_provider]=publish_plot_sample(session,module_id,module_version,plot_dataset_id,source_dataset_id,source_variable_ids,variables,selected_values,selection); sample_publication_finalized=true; sample_publication_open=false;
    endif

    request_path=fullfile(outdir,'descriptive_plot_request.ini');
    write_plot_request(request_path,module_id,module_version,source_dataset_id,plot_dataset_id,variables,selection,render_graphs,histogram_bins,histogram_normalization,box_whisker_iqr,box_show_outliers);
    if(render_graphs)
      gxtxt_progress_stage('graphs','Creating plot.dataset distribution variants','indeterminate');
      graph_count=create_automatic_graphs(outdir,session,plot_dataset_id,variables,histogram_bins,histogram_normalization,box_whisker_iqr,box_show_outliers,module_id);
    else
      write_empty_graph_manifest(fullfile(outdir,'automatic_graphs.ini'));
    endif

    write_summary_ini(fullfile(outdir,'descriptive_statistics_summary.ini'),module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,variables,selection,nonfinite_policy,percentile_probabilities,rows,warnings,P.provider,plot_provider,graph_count);
    write_report(fullfile(outdir,'descriptive_statistics_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,variables,selection,nonfinite_policy,percentile_probabilities,rows,warnings,P.provider,plot_provider,graph_count,pub_diag,pub_result);
    gxtxt_progress_complete('done',sprintf('Published %s (%d variables, %d result rows, %d automatic graphs)',output_dataset_id,numel(variables),numel(rows),graph_count));
    fprintf('[%s] version=%s source=%s output=%s variables=%d rows=%d graphs=%d provider=%s\n',module_id,module_version,source_dataset_id,output_dataset_id,numel(variables),numel(rows),graph_count,P.provider);
  catch err
    if(sample_publication_open && !sample_publication_finalized),try PS=gxtxt_publication_v2_abort(PS); catch; end_try_catch,endif
    if(publication_open && !publication_finalized),try P=gxtxt_publication_v2_abort(P); catch; end_try_catch,endif
    try gxtxt_progress_fail('failed','Descriptive statistics failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=arg_value(args,key,default)
  value=default; for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction

function tokens=repeatable_variables(cfg,module_id)
  row_text=strtrim(gxtxt_ini_get(cfg,'repeatable_config.variables.rows',''));
  rows=split_list(row_text); tokens={};
  for i=1:numel(rows)
    token=strtrim(gxtxt_ini_get(cfg,sprintf('repeatable_config.variables.%s.variable',rows{i}),''));
    if(isempty(token)),error('%s: Variables row %s has no variable selected',module_id,rows{i});endif
    tokens{end+1}=token;
  endfor
  if(isempty(tokens)),error('%s: select at least one numeric variable',module_id);endif
endfunction

function variables=resolve_variables(cfg,tokens,dataset_id,module_id)
  variables=struct('variable_id',{},'name',{},'unit',{},'value_kind',{}); seen={};
  for i=1:numel(tokens)
    [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',tokens{i});
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('%s: variable could not be resolved: %s',module_id,tokens{i});endif
    if(!strcmp(strtrim(meta.dataset_id),dataset_id)),error('%s: variable %s belongs to a different Dataset',module_id,tokens{i});endif
    vid=strtrim(meta.variable_id); if(isempty(vid)),error('%s: stable variable ID is required for %s',module_id,tokens{i});endif
    if(isfield(meta,'value_kind')&&strcmpi(strtrim(meta.value_kind),'text')),error('%s: variable %s (%s) is not numeric',module_id,meta.name,vid);endif
    if(any(strcmp(seen,vid))),error('%s: variable %s (%s) is selected more than once',module_id,meta.name,vid);endif
    value_kind='number'; if(isfield(meta,'value_kind')&&!isempty(strtrim(meta.value_kind))),value_kind=lower(strtrim(meta.value_kind));endif
    if(!any(strcmp(value_kind,{'number','elapsed_time'}))),error('%s: variable %s (%s) does not expose a numeric value kind',module_id,meta.name,vid);endif
    numeric_unit=strtrim(unit); if(strcmp(value_kind,'elapsed_time')),numeric_unit='s';endif
    seen{end+1}=vid; variables(end+1)=struct('variable_id',vid,'name',strtrim(meta.name),'unit',numeric_unit,'value_kind',value_kind);
  endfor
endfunction

function values=read_selected_variable(cfg,variable_id,selection,dataset_id,module_id)
  ids={variable_id}; x_index=0;
  if(selection.enabled)
    xid=strtrim(selection.x_variable_id);
    if(isempty(xid))
      [~,~,xm]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
      if(!(isstruct(xm)&&isfield(xm,'found')&&xm.found)),error('%s: Dataset Selection X variable could not be resolved',module_id);endif
      xid=strtrim(xm.variable_id);
    endif
    if(isempty(xid)),error('%s: Dataset Selection has no stable X variable ID',module_id);endif
    if(strcmp(xid,variable_id)),x_index=1;else ids={xid,variable_id};x_index=1;endif
  endif
  S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  parts={};
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S); if(C.nrows<1),continue;endif
      v=gxtxt_table_chunk_numeric(C,variable_id);v=double(v(:));
      if(selection.enabled),x=gxtxt_table_chunk_numeric(C,ids{x_index});x=double(x(:));mask=gxtxt_selection_mask(selection,x);v=v(mask);endif
      if(!isempty(v)),parts{end+1}=v;endif
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(isempty(parts)),values=zeros(0,1);else values=vertcat(parts{:});endif
endfunction

function api=discover_numeric_api(framework_root,module_id)
  descriptor=fullfile(framework_root,'plugins','modules','math.numeric','module.ini');
  if(exist(descriptor,'file')!=2),error('%s: required math.numeric module descriptor is missing',module_id);endif
  d=gxtxt_ini_read(descriptor); ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));
  if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: required public NUMERIC_API_v1 is not advertised',module_id);endif
  fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));
  ep=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));
  if(isempty(fn)||isempty(ep)),error('%s: NUMERIC_API_v1 Octave binding is incomplete',module_id);endif
  addpath(fileparts(fullfile(fileparts(descriptor),ep)));
  if(exist(fn,'file')!=2),error('%s: NUMERIC_API_v1 Octave function is unavailable',module_id);endif
  api=struct('function_name',fn);
endfunction

function p=parse_percentiles(text)
  text=strrep(strtrim(text),',',';'); if(isempty(text)),p=[];return;endif
  parts=strsplit(text,';'); p=[];
  for i=1:numel(parts)
    t=strtrim(parts{i}); if(isempty(t)),continue;endif
    v=str2double(t); if(!isfinite(v)||v<0||v>100),error('analysis.statistics.descriptive: percentile must be between 0 and 100: %s',t);endif
    q=v/100; if(!any(abs(p-q)<1e-14)),p(end+1)=q;endif
  endfor
  p=sort(p(:));
endfunction

function value=parse_bool(text,module_id,label)
  q=lower(strtrim(text));
  if(any(strcmp(q,{'1','true','yes','on'}))),value=true;return;endif
  if(any(strcmp(q,{'0','false','no','off'}))),value=false;return;endif
  error('%s: %s must be boolean',module_id,label);
endfunction

function value=parse_histogram_bins(text,module_id)
  q=lower(strtrim(text));
  if(strcmp(q,'auto')),value='auto';return;endif
  n=str2double(q);
  if(!isfinite(n)||round(n)!=n||n<2||n>512),error('%s: Histogram bins must be auto or an integer from 2 to 512',module_id);endif
  value=sprintf('%d',round(n));
endfunction

function validate_dataset_id(id,module_id,label)
  if(isempty(regexp(id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid %s',module_id,label);endif
endfunction

function rows=empty_rows()
  rows=struct('variable_id',{},'variable_name',{},'statistic',{},'value',{},'defined',{},'unit',{},'unit_power',{},'observation_count',{},'valid_count',{},'excluded_count',{});
endfunction

function rows=append_standard_rows(rows,V,S,n_total,n_valid,n_excluded)
  rows=add_row(rows,V,'count',n_total,true,0,n_total,n_valid,n_excluded);
  rows=add_row(rows,V,'valid_count',n_valid,true,0,n_total,n_valid,n_excluded);
  rows=add_row(rows,V,'excluded_nonfinite_count',n_excluded,true,0,n_total,n_valid,n_excluded);
  mapping={'minimum','minimum';'maximum','maximum';'range','range';'mean','mean';'median','median'; ...
    'variance_sample','variance';'standard_deviation_sample','standard_deviation'; ...
    'variance_population','variance_population';'standard_deviation_population','standard_deviation_population'; ...
    'standard_error_mean','standard_error_mean';'q1','quartile_1';'q3','quartile_3';'iqr','interquartile_range';'rms','root_mean_square'};
  for i=1:size(mapping,1)
    item=S.quantities.(mapping{i,2});defined=strcmp(item.status,'value');value=NaN;if(defined),value=item.value;endif
    power=1;if(iscell(item.unit)&&numel(item.unit)==3&&strcmp(item.unit{1},'power')),power=str2double(item.unit{3});endif
    rows=add_row(rows,V,mapping{i,1},value,defined,power,n_total,n_valid,n_excluded);
  endfor
endfunction

function rows=append_percentile_rows(rows,V,Q,n_total,n_valid,n_excluded)
  if(isempty(Q.probabilities)),return;endif
  for i=1:numel(Q.probabilities)
    pct=100*Q.probabilities(i);
    if(any(abs(pct-[25 50 75])<1e-12)),continue;endif
    label=sprintf('percentile_%g',pct);
    rows=add_row(rows,V,label,Q.quantiles(i),true,1,n_total,n_valid,n_excluded);
  endfor
endfunction

function rows=add_row(rows,V,statistic,value,defined,unit_power,n_total,n_valid,n_excluded)
  result_unit=V.unit; if(unit_power==0),result_unit='';endif
  rows(end+1)=struct('variable_id',V.variable_id,'variable_name',V.name,'statistic',statistic,'value',double(value),'defined',logical(defined),'unit',result_unit,'unit_power',unit_power,'observation_count',n_total,'valid_count',n_valid,'excluded_count',n_excluded);
endfunction

function P=declare_string(P,id,name,role,dimension_id)
  P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype','string','dimension_ids',dimension_id,'name',name,'unit','','semantic_role',role));
endfunction
function P=declare_numeric(P,id,name,role,dtype,unit,dimension_id)
  P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype',dtype,'dimension_ids',dimension_id,'name',name,'unit',unit,'semantic_role',role));
endfunction

function [P,provider]=publish_plot_sample(session,module_id,module_version,dataset_id,source_dataset_id,source_variable_ids,variables,selected_values,selection)
  P=struct(); opened=false; finalized=false;
  try
    if(isempty(selected_values)),error('%s: no selected values are available for automatic plots',module_id);endif
    n=numel(selected_values{1});
    for i=2:numel(selected_values),if(numel(selected_values{i})!=n),error('%s: selected variables do not share the same selected row count',module_id);endif,endfor
    opts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source','GX-TXT descriptive statistics selected sample', ...
      'provenance',sprintf('%s %s automatic distribution-plot sample; selection=%s',module_id,module_version,selection_id(selection)), ...
      'notes','Selected source observations used by public plot.dataset histogram and box/whisker variants. NaN/Inf values are preserved; plot.dataset uses its documented finite-sample distribution policy.');
    opts.source_dataset_ids={source_dataset_id}; opts.source_variable_ids=source_variable_ids;
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts); opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'sample',0,true);
    P=declare_numeric(P,'sample_index','Selected observation index','independent','int64','','sample');
    items={'sample_index',int64((1:n)')};
    for i=1:numel(variables)
      key=sprintf('value_%03d',i); V=variables(i);
      P=declare_numeric(P,key,V.name,'measured','float64',V.unit,'sample');
      items(end+1,:)={key,double(selected_values{i}(:))};
    endfor
    P=gxtxt_publication_v2_append(P,'sample',items);
    [P,~]=gxtxt_publication_v2_diagnostics(P);
    [P,~]=gxtxt_publication_v2_finalize(P); finalized=true; opened=false;
    provider=P.provider;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    rethrow(err);
  end_try_catch
endfunction

function write_plot_request(path,module_id,module_version,source_dataset_id,plot_dataset_id,variables,selection,enabled,hist_bins,hist_norm,box_iqr,box_outliers)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write plot request',module_id);endif
  unwind_protect
    fprintf(fid,'[module]\nid=%s\nversion=%s\n\n',module_id,module_version);
    fprintf(fid,'[source]\ndataset_id=%s\nselection_id=%s\n\n',source_dataset_id,selection_id(selection));
    fprintf(fid,'[graph_sample]\nenabled=%d\ndataset_id=%s\nx_variable=sample_index\nvariable_count=%d\n\n',enabled,plot_dataset_id,numel(variables));
    fprintf(fid,'[options]\nhistogram_bins=%s\nhistogram_normalization=%s\nbox_whisker_iqr=%.17g\nbox_show_outliers=%d\n',hist_bins,hist_norm,box_iqr,box_outliers);
    for i=1:numel(variables)
      fprintf(fid,'\n[variable.%d]\nsource_variable_id=%s\nplot_variable=value_%03d\nname=%s\nunit=%s\n',i,sanitize_ini(variables(i).variable_id),i,sanitize_ini(variables(i).name),sanitize_ini(variables(i).unit));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function graph_count=create_automatic_graphs(outdir,session,plot_dataset_id,variables,hist_bins,hist_norm,box_iqr,box_outliers,module_id)
  if(exist('gxtxt_plot_dataset_v2','file')!=2),error('%s: public Plot Dataset Octave Bridge v1 is unavailable; GX-TXT 0.9.7.86 or newer is required',module_id);endif
  groups=group_plot_variables(variables);
  records=struct('key',{},'kind',{},'group',{},'display_unit',{},'title',{},'graph_id',{},'variant_id',{},'png',{},'provider_artifact',{});
  graph_count=0;
  for gi=1:numel(groups)
    group=groups{gi}; display_unit=group.display_unit; indices=group.indices;
    if(isempty(display_unit)),unit_label='unitless values';else unit_label=[display_unit '-compatible values'];endif
    htitle=['Descriptive distribution - histogram - ' unit_label];
    hspec=distribution_plot_spec(plot_dataset_id,variables,indices,display_unit,'histogram',htitle,hist_bins,hist_norm,box_iqr,box_outliers,gi);
    hresult=gxtxt_plot_dataset_v2(session,hspec,struct('action','create','kind','variant','source_variant','','render',true));
    graph_count+=1; hslug=sprintf('%02d_histogram_group_%02d.png',graph_count,gi);
    copy_plot_artifact(hresult.artifact,fullfile(outdir,hslug),module_id);
    records(end+1)=graph_record(sprintf('histogram.group%02d',gi),'histogram',gi,display_unit,htitle,hresult,hslug);

    btitle=['Descriptive distribution - box/whisker - ' unit_label];
    bspec=distribution_plot_spec(plot_dataset_id,variables,indices,display_unit,'box_whisker',btitle,hist_bins,hist_norm,box_iqr,box_outliers,gi);
    bresult=gxtxt_plot_dataset_v2(session,bspec,struct('action','create','kind','variant','source_variant','','render',true));
    graph_count+=1; bslug=sprintf('%02d_box_whisker_group_%02d.png',graph_count,gi);
    copy_plot_artifact(bresult.artifact,fullfile(outdir,bslug),module_id);
    records(end+1)=graph_record(sprintf('box_whisker.group%02d',gi),'box_whisker',gi,display_unit,btitle,bresult,bslug);
  endfor
  write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),records);
endfunction

function groups=group_plot_variables(variables)
  groups={};
  for i=1:numel(variables)
    placed=false;
    for g=1:numel(groups)
      if(plot_units_compatible(variables(i).unit,groups{g}.display_unit))
        groups{g}.indices(end+1)=i; placed=true; break;
      endif
    endfor
    if(!placed),groups{end+1}=struct('display_unit',variables(i).unit,'indices',i);endif
  endfor
endfunction

function tf=plot_units_compatible(a,b)
  a=strtrim(a); b=strtrim(b);
  if(isempty(a)||isempty(b)),tf=isempty(a)&&isempty(b);return;endif
  try tf=logical(gxtxt_unit_compatible(a,b)); catch,tf=strcmp(a,b);end_try_catch
endfunction

function spec=distribution_plot_spec(dataset_id,variables,indices,display_unit,kind,title_text,hist_bins,hist_norm,box_iqr,box_outliers,group_index)
  series=cell(1,numel(indices));
  for j=1:numel(indices)
    i=indices(j); V=variables(i);
    item=struct('id',sprintf('%s_%02d_%02d',kind,group_index,j), ...
      'dataset_id',dataset_id,'x_variable_id','sample_index','y_variable_id',sprintf('value_%03d',i), ...
      'axis','left','kind',kind,'label',V.name);
    if(strcmp(kind,'histogram'))
      item.histogram_bins=hist_bins; item.histogram_normalization=hist_norm;
    else
      item.box_whisker_iqr=box_iqr; item.box_show_outliers=logical(box_outliers);
    endif
    series{j}=item;
  endfor
  axes=struct(); if(!isempty(strtrim(display_unit))),axes.y_left=struct('display_unit',display_unit);endif
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{{}});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy', ...
    'title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
endfunction

function copy_plot_artifact(source,destination,module_id)
  if(isempty(strtrim(source))||exist(source,'file')!=2),error('%s: plot.dataset did not return a readable graph artifact',module_id);endif
  [ok,msg]=copyfile(source,destination,'f');
  if(!ok||exist(destination,'file')!=2),error('%s: cannot copy automatic graph artifact: %s',module_id,msg);endif
endfunction

function R=graph_record(key,kind,group,display_unit,title_text,result,slug)
  R=struct('key',key,'kind',kind,'group',group,'display_unit',display_unit,'title',title_text, ...
    'graph_id',result.graph_id,'variant_id',result.variant_id,'png',slug,'provider_artifact',result.artifact);
endfunction

function write_graph_manifest(path,records)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.descriptive: cannot write automatic graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n',numel(records));
    for i=1:numel(records)
      R=records(i); fprintf(fid,'\n[graph.%02d]\n',i);
      fprintf(fid,'key=%s\nkind=%s\ngroup=%d\ndisplay_unit=%s\ntitle=%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n', ...
        sanitize_ini(R.key),sanitize_ini(R.kind),R.group,sanitize_ini(R.display_unit),sanitize_ini(R.title),sanitize_ini(R.graph_id),sanitize_ini(R.variant_id),sanitize_ini(R.png),sanitize_ini(R.provider_artifact));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_empty_graph_manifest(path)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.descriptive: cannot write automatic graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction


function write_summary_ini(path,module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,variables,selection,policy,percentiles,rows,warnings,provider,plot_provider,graph_count)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write summary INI',module_id);endif
  unwind_protect
    fprintf(fid,'[module]\nid=%s\nversion=%s\n\n',module_id,module_version);
    fprintf(fid,'[source]\ndataset_id=%s\nvariable_count=%d\nselection_id=%s\nnonfinite_policy=%s\n\n',source_dataset_id,numel(variables),selection_id(selection),policy);
    fprintf(fid,'[output]\ndataset_id=%s\nprovider=%s\nresult_rows=%d\nwarning_count=%d\npercentiles=%s\nplot_sample_dataset_id=%s\nplot_sample_provider=%s\nautomatic_graph_count=%d\n',output_dataset_id,provider,numel(rows),numel(warnings),join_percentiles(percentiles),plot_dataset_id,plot_provider,graph_count);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,module_id,module_version,source_dataset_id,output_dataset_id,plot_dataset_id,variables,selection,policy,percentiles,rows,warnings,provider,plot_provider,graph_count,pub_diag,pub_result)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write report',module_id);endif
  unwind_protect
    fprintf(fid,'GX-TXT Descriptive Statistics\n=============================\n\n');
    fprintf(fid,'Producer: %s %s\nInput Dataset: %s\nOutput Dataset: %s\nStorage provider: %s\nSelection: %s\nNaN / Inf policy: %s\nAdditional percentiles: %s\nAutomatic graph count: %d\n',module_id,module_version,source_dataset_id,output_dataset_id,provider,selection_id(selection),policy,join_percentiles(percentiles),graph_count);
    if(!strcmp(plot_dataset_id,'none')),fprintf(fid,'Automatic plot sample Dataset: %s (provider %s)\n',plot_dataset_id,plot_provider);endif
    fprintf(fid,'\n');
    for v=1:numel(variables)
      V=variables(v);fprintf(fid,'%s [%s]',V.name,V.variable_id);if(!isempty(V.unit)),fprintf(fid,' (%s)',V.unit);endif;fprintf(fid,'\n');
      idx=find(strcmp({rows.variable_id},V.variable_id));
      for k=idx
        R=rows(k); fprintf(fid,'  %-32s ',R.statistic);
        if(R.defined),fprintf(fid,'%.17g',R.value);else fprintf(fid,'undefined');endif
        if(R.unit_power==1 && !isempty(R.unit)),fprintf(fid,' %s',R.unit);elseif(R.unit_power==2 && !isempty(R.unit)),fprintf(fid,' (%s)^2',R.unit);endif
        fprintf(fid,'\n');
      endfor
      if(!isempty(idx)),R=rows(idx(1));fprintf(fid,'  observations=%d valid=%d excluded_nonfinite=%d\n\n',R.observation_count,R.valid_count,R.excluded_count);endif
    endfor
    fprintf(fid,'Warnings\n--------\n');if(isempty(warnings)),fprintf(fid,'None.\n');else for i=1:numel(warnings),fprintf(fid,'- %s\n',warnings{i});endfor,endif
    fprintf(fid,'\nGraphics\n--------\n');
    if(graph_count>0),fprintf(fid,'Automatic histograms and box/whisker plots were created as persistent plot.dataset variants. Incompatible unit families were kept in separate plots.\n');else fprintf(fid,'Automatic graphs were disabled.\n');endif
    fprintf(fid,'\nPublication diagnostics/result\n------------------------------\n');
    fprintf(fid,'Publication diagnostics available: %d\nPublication result available: %d\n',isstruct(pub_diag),isstruct(pub_result));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function s=selection_id(selection)
  if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')&&!isempty(selection.id)),s=selection.id;else s='none';endif
endfunction
function s=join_percentiles(p)
  if(isempty(p)),s='none';return;endif
  c=arrayfun(@(x) sprintf('%g',100*x),p,'UniformOutput',false);s=strjoin(c,';');
endfunction
function out=split_list(s)
  s=strrep(strtrim(s),',',';');if(isempty(s)),out={};else out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endif
endfunction
function s=sanitize_ini(s)
  s=strrep(s,char(13),' ');s=strrep(s,char(10),' ');
endfunction
