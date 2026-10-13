function demo_numeric_statistics_main(args,framework_root)
% Dataset-native statistics demonstration using public GX-TXT APIs only.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='demo.numeric.statistics';module_version='1.0.1';
  publication_open=false;publication_finalized=false;P=struct();
  series_publication_open=false;series_publication_finalized=false;PS=struct();
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing numerical statistics demonstration','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif;if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif
    value_binding=binding_column(gxtxt_ini_get(cfg,'bindings.value',''),'value');weight_binding=binding_column(gxtxt_ini_get(cfg,'bindings.weight',''),'weight');
    if(isempty(value_binding)),error('%s: Value variable binding is required',module_id);endif
    [value_unit,~,value_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',value_binding);if(!meta_found(value_meta)),error('%s: Value binding could not be resolved',module_id);endif
    value_id=strtrim(value_meta.variable_id);value_name=strtrim(value_meta.name);if(isempty(value_id)),error('%s: stable Value variable ID is required',module_id);endif
    [weight_id,weight_name,weight_unit]=optional_meta(cfg,weight_binding,module_id);
    mode=lower(strtrim(gxtxt_ini_get(cfg,'config.mode','descriptive')));if(!any(strcmp(mode,{'descriptive','weighted'}))),error('%s: Statistics mode must be descriptive or weighted',module_id);endif
    if(strcmp(mode,'weighted')&&isempty(weight_id)),error('%s: Weighted mode requires an explicit Weight variable binding',module_id);endif
    if(!isempty(weight_id)&&strcmp(value_id,weight_id)),error('%s: Value and Weight variables must be different',module_id);endif
    nonfinite_policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));if(!any(strcmp(nonfinite_policy,{'omit','error'}))),error('%s: NaN / Inf policy must be omit or error',module_id);endif
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.statistics.result'));if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid Summary Dataset ID',module_id);endif
    series_dataset_id=[output_dataset_id '.series'];if(strcmp(output_dataset_id,source_dataset_id)||strcmp(series_dataset_id,source_dataset_id)),error('%s: output Dataset IDs must differ from source Dataset ID',module_id);endif
    selection=struct('enabled',false);try selection=gxtxt_selection_from_runtime(cfg,'selection');catch selerr,error('%s: invalid Dataset Selection: %s',module_id,selerr.message);end_try_catch
    if(selection.enabled),validate_selection(selection,source_dataset_id,module_id);endif
    metadata=read_optional_metadata(cfg);
    numeric=discover_numeric_api(framework_root,module_id);

    gxtxt_progress_stage('load_dataset','Reading selected source values','indeterminate');
    [raw_values,raw_weights,source_provider]=read_selected_inputs(cfg,value_id,weight_id,selection,strcmp(mode,'weighted'));
    input_count=numel(raw_values);if(input_count<1),error('%s: selected input contains no rows',module_id);endif
    opts=struct('nonfinite',nonfinite_policy);if(selection.enabled),opts.selection=selection;endif

    gxtxt_progress_stage('numeric','Running public statistical operation','determinate',2);
    if(strcmp(mode,'descriptive'))
      result=feval(numeric.function_name,'dataset_statistics',session,source_dataset_id,value_id,opts);
      finite_mask=isfinite(raw_values);valid_count=double(result.n);excluded_nonfinite=input_count-valid_count;
      if(valid_count!=sum(finite_mask)),error('%s: public Dataset statistics count disagrees with selected source values',module_id);endif
      values=raw_values(finite_mask);weights=zeros(0,1);
      q=feval(numeric.function_name,'quantiles',values,[0.25;0.5;0.75],struct('nonfinite','error'));
      if(max(abs(double(q.quantiles(:))-[double(result.q25);double(result.median);double(result.q75)]))>1e-12*max(1,max(abs(double(q.quantiles(:)))))),error('%s: public statistics/quantiles results disagree',module_id);endif
      quantile_definition=strtrim(q.definition);
      [stat_names,stat_values,stat_units,stat_definitions]=descriptive_summary(result,input_count,excluded_nonfinite,value_unit,quantile_definition);
      finite_pair_count=valid_count;positive_weight_count=NaN;zero_weight_count=NaN;
    else
      result=feval(numeric.function_name,'dataset_weighted_statistics',session,source_dataset_id,value_id,weight_id,opts);
      finite_pair_mask=isfinite(raw_values)&isfinite(raw_weights);positive_mask=finite_pair_mask&(raw_weights>0);
      finite_pair_count=double(result.n_total);positive_weight_count=double(result.n_positive);excluded_nonfinite=input_count-finite_pair_count;zero_weight_count=finite_pair_count-positive_weight_count;
      if(finite_pair_count!=sum(finite_pair_mask)||positive_weight_count!=sum(positive_mask)),error('%s: public weighted statistics counts disagree with selected source values/weights',module_id);endif
      values=raw_values(positive_mask);weights=raw_weights(positive_mask);valid_count=positive_weight_count;quantile_definition=strtrim(result.quantile_definition);
      [stat_names,stat_values,stat_units,stat_definitions]=weighted_summary(result,input_count,excluded_nonfinite,zero_weight_count,value_unit,weight_unit,quantile_definition);
    endif
    indices=(1:numel(values))';gxtxt_progress_update(1,2,'numeric','Public statistics complete');
    if(isempty(values)),error('%s: no observations remain after the public non-finite/weight policy',module_id);endif
    gxtxt_progress_update(2,2,'numeric','Public quantile/count semantics validated');

    selection_id='';if(selection.enabled&&isfield(selection,'id')),selection_id=strtrim(selection.id);endif
    source_ids={value_id};if(strcmp(mode,'weighted')),source_ids{end+1}=weight_id;endif
    provenance=sprintf('%s %s via NUMERIC_API_v1; mode=%s; nonfinite=%s; selection=%s',module_id,module_version,mode,nonfinite_policy,selection_id);

    gxtxt_progress_stage('publish','Publishing statistical summary Dataset','determinate',2);
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_ids},'source',source_dataset_id,'provenance',provenance,'notes','Long-form statistical summary produced only by public math.numeric operations.');
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'statistic',0,true);
    P=declare_text(P,'statistic','statistic','category');P=declare_summary_numeric(P,'value','value','derived','');P=declare_text(P,'unit','unit','category');P=declare_text(P,'definition','definition','category');
    P=gxtxt_publication_v2_append(P,'statistic',{'statistic',stat_names;'value',stat_values;'unit',stat_units;'definition',stat_definitions});
    [P,summary_diag]=gxtxt_publication_v2_diagnostics(P);[P,summary_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;

    series_opts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_ids},'source',source_dataset_id,'provenance',[provenance '; purpose=graph_series'],'notes','Included observations plus public mean/median reference values for plotting and reuse.');
    PS=gxtxt_publication_v2_open(session,module_id,series_dataset_id,'table.generic',series_opts);series_publication_open=true;
    PS=gxtxt_publication_v2_declare_dimension(PS,'sample',0,true);PS=declare_series_numeric(PS,'sample_index','sample_index','independent','1','');PS=declare_series_numeric(PS,'value','value','measured',value_unit,'sample_index');PS=declare_series_numeric(PS,'mean_reference','mean_reference','reference',value_unit,'sample_index');PS=declare_series_numeric(PS,'median_reference','median_reference','reference',value_unit,'sample_index');
    items={'sample_index',indices;'value',values;'mean_reference',ones(numel(values),1)*double(result.mean);'median_reference',ones(numel(values),1)*double(result.median)};
    if(strcmp(mode,'weighted')),PS=declare_series_numeric(PS,'weight','weight','weight',weight_unit,'sample_index');items(end+1,:)={'weight',weights};endif
    PS=gxtxt_publication_v2_append(PS,'sample',items);[PS,series_diag]=gxtxt_publication_v2_diagnostics(PS);[PS,series_result]=gxtxt_publication_v2_finalize(PS);series_publication_finalized=true;series_publication_open=false;

    write_metrics(fullfile(outdir,'statistics_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,series_dataset_id,value_id,weight_id,value_name,weight_name,value_unit,weight_unit,mode,nonfinite_policy,selection_id,input_count,valid_count,excluded_nonfinite,finite_pair_count,positive_weight_count,zero_weight_count,source_provider,numeric,result,quantile_definition,metadata,P.provider,PS.provider);
    write_report(fullfile(outdir,'statistics_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,series_dataset_id,value_id,weight_id,value_name,weight_name,value_unit,weight_unit,mode,nonfinite_policy,selection_id,input_count,valid_count,excluded_nonfinite,finite_pair_count,positive_weight_count,zero_weight_count,numeric,result,quantile_definition,metadata,stat_names,stat_values,stat_units,summary_diag,summary_result,series_diag,series_result);
    save(fullfile(outdir,'render_cache.mat'),'value_name','value_unit','mode','output_dataset_id','series_dataset_id');
    demo_numeric_statistics_render(outdir,series_dataset_id,value_name,value_unit,mode,cfg);
    gxtxt_progress_complete('done',sprintf('Published %s and %s; statistics mode=%s',output_dataset_id,series_dataset_id,mode));
    fprintf('[%s] version=%s source=%s summary=%s series=%s mode=%s input=%d valid=%d excluded_nonfinite=%d validation=PASS\n',module_id,module_version,source_dataset_id,output_dataset_id,series_dataset_id,mode,input_count,valid_count,excluded_nonfinite);
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    if(series_publication_open&&!series_publication_finalized),try PS=gxtxt_publication_v2_abort(PS);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Statistics demonstration failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction
function [id,name,unit]=optional_meta(cfg,binding,module_id),id='';name='';unit='';if(isempty(binding)),return;endif;[unit,~,m]=gxtxt_analysis_source_variable_meta(cfg,'primary',binding);if(!meta_found(m)),error('%s: optional Weight binding could not be resolved',module_id);endif;id=strtrim(m.variable_id);name=strtrim(m.name);if(isempty(id)),error('%s: stable Weight variable ID is required',module_id);endif;endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif;if(isempty(out)),error('demo.numeric.statistics: invalid %s binding',role);endif,endfunction
function validate_selection(S,dataset_id,module_id)
  if(!S.enabled)
    return;
  endif
  if(!isfield(S,'source_dataset_id')||!strcmp(strtrim(S.source_dataset_id),dataset_id))
    error('%s: Dataset Selection source does not match the bound Dataset',module_id);
  endif
  if(!isfield(S,'type')||!strcmp(lower(strtrim(S.type)),'x_range'))
    error('%s: only X-range Dataset Selection is supported',module_id);
  endif
  if(!isfield(S,'x_variable_id')||isempty(strtrim(S.x_variable_id)))
    error('%s: Dataset Selection lacks a stable X variable ID',module_id);
  endif
endfunction
function md=read_optional_metadata(cfg),try md=gxtxt_analysis_source_dataset_metadata(cfg,'primary');catch,md=struct('found',false,'count',0,'keys',{{}},'values',{{}});end_try_catch;endfunction
function [values,weights,provider]=read_selected_inputs(cfg,value_id,weight_id,selection,need_weight)
  ids={value_id};value_pos=1;weight_pos=0;if(need_weight),ids{end+1}=weight_id;weight_pos=numel(ids);endif
  x_pos=0;if(selection.enabled),sx=strtrim(selection.x_variable_id);x_pos=find(strcmp(ids,sx),1);if(isempty(x_pos)),ids{end+1}=sx;x_pos=numel(ids);endif,endif
  % Use the value transport because this demonstration intentionally contains
  % provider-converted NaN rows, which the typed-binary bridge cannot encode.
  S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','values'));provider=S.storage_provider;parts=cell(1,numel(ids));for j=1:numel(ids),parts{j}={};endfor
  unwind_protect
    while(!S.eof),[S,C]=gxtxt_table_stream_next(S);if(C.nrows>0),for j=1:numel(ids),parts{j}{end+1}=double(C.values{j}(:));endfor,endif,endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  data=cell(1,numel(ids));for j=1:numel(ids),if(isempty(parts{j})),data{j}=zeros(0,1);else,data{j}=vertcat(parts{j}{:});endif,endfor
  values=data{value_pos};if(need_weight),weights=data{weight_pos};else,weights=zeros(0,1);endif
  if(selection.enabled),mask=gxtxt_selection_mask(selection,data{x_pos});values=values(mask);if(need_weight),weights=weights(mask);endif,endif
endfunction
function api=discover_numeric_api(root,module_id),descriptor=fullfile(root,'plugins','modules','math.numeric','module.ini');if(exist(descriptor,'file')!=2),error('%s: math.numeric descriptor missing',module_id);endif;d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: NUMERIC_API_v1 is not advertised',module_id);endif;ver=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));if(!strcmp(ver,'1')),error('%s: unsupported NUMERIC_API_v1 version: %s',module_id,ver);endif;caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));required={'descriptive_statistics','quantiles','weighted_statistics','dataset_statistics','dataset_selection'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor;entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));if(isempty(entry)||isempty(fn)),error('%s: incomplete NUMERIC_API_v1 Octave binding',module_id);endif;entry_path=fullfile(fileparts(descriptor),entry);if(exist(entry_path,'file')!=2),error('%s: advertised NUMERIC_API_v1 entrypoint missing',module_id);endif;addpath(fileparts(entry_path));if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif;api=struct('name','NUMERIC_API_v1','api_version',ver,'function_name',fn,'entrypoint',entry);endfunction
function [names,values,units,defs]=descriptive_summary(R,input_count,excluded,unit,qdef)
  names={'input_count';'valid_count';'excluded_nonfinite_count';'minimum';'maximum';'range';'sum';'mean';'median';'q25';'q75';'iqr';'variance_population';'std_population';'variance_sample';'std_sample';'rms'};
  values=[input_count;R.n;excluded;R.min;R.max;R.range;R.sum;R.mean;R.median;R.q25;R.q75;R.iqr;R.variance_population;R.std_population;R.variance_sample;R.std_sample;R.rms];
  su=square_unit(unit);units={'1';'1';'1';unit;unit;unit;unit;unit;unit;unit;unit;unit;su;unit;su;unit;unit};
  defs={'Rows after Dataset Selection, before non-finite policy';'Finite observations used by NUMERIC_API_v1';'NaN/+Inf/-Inf observations omitted by explicit policy';'Minimum';'Maximum';'Maximum minus minimum';'Sum';'Arithmetic mean';qdef;qdef;qdef;'Q75 minus Q25';'Population variance (divisor n)';'Population standard deviation';'Sample variance (divisor n-1; NaN for n=1)';'Sample standard deviation';'Root mean square'};
endfunction
function [names,values,units,defs]=weighted_summary(R,input_count,excluded,zero_count,value_unit,weight_unit,qdef)
  names={'input_count';'finite_pair_count';'excluded_nonfinite_count';'positive_weight_count';'zero_weight_count';'sum_weights';'effective_n';'minimum';'maximum';'range';'weighted_sum';'mean';'median';'q25';'q75';'iqr';'variance_population';'std_population';'variance_unbiased';'std_unbiased';'rms'};
  values=[input_count;R.n_total;excluded;R.n_positive;zero_count;R.sum_weights;R.effective_n;R.min;R.max;R.range;R.weighted_sum;R.mean;R.median;R.q25;R.q75;R.iqr;R.variance_population;R.std_population;R.variance_unbiased;R.std_unbiased;R.rms];
  wu=weight_unit;if(isempty(strtrim(wu))),wu='1';endif;su=square_unit(value_unit);wsu=product_unit(value_unit,weight_unit);units={'1';'1';'1';'1';'1';wu;'1';value_unit;value_unit;value_unit;wsu;value_unit;value_unit;value_unit;value_unit;value_unit;su;value_unit;su;value_unit;value_unit};
  defs={'Rows after Dataset Selection, before non-finite policy';'Finite value/weight pairs before zero-weight removal';'Pairs omitted because value or weight was NaN/+Inf/-Inf';'Positive-weight observations used by NUMERIC_API_v1';'Finite zero-weight observations discarded by NUMERIC_API_v1';'Sum of explicit statistical weights';'Kish-style effective sample size reported by NUMERIC_API_v1';'Minimum among positive-weight observations';'Maximum among positive-weight observations';'Maximum minus minimum';'Sum(weight*value)';'Weighted arithmetic mean';qdef;qdef;qdef;'Weighted Q75 minus Q25';'Population weighted variance';'Population weighted standard deviation';'Reliability-weight unbiased variance when defined';'Reliability-weight unbiased standard deviation when defined';'Weighted root mean square'};
endfunction
function u=square_unit(unit),u=strtrim(unit);if(!isempty(u)),u=[u '^2'];endif,endfunction
function u=product_unit(a,b),a=strtrim(a);b=strtrim(b);if(isempty(b)||strcmp(b,'1')),u=a;elseif(isempty(a)),u=b;else,u=[a '*' b];endif,endfunction
function P=declare_text(P,id,name,role),spec=struct('dtype','string','dimension_ids','statistic','name',name,'unit','','semantic_role',role,'value_kind','text','coordinate_role','data','axis_kind','none');P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function P=declare_summary_numeric(P,id,name,role,unit),spec=struct('dtype','float64','dimension_ids','statistic','name',name,'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function P=declare_series_numeric(P,id,name,role,unit,coord),spec=struct('dtype','float64','dimension_ids','sample','name',name,'unit',unit,'semantic_role',role,'axis_kind','explicit');if(isempty(coord)),spec.coordinate_role='coordinate';else,spec.coordinate_role='data';spec.coordinate_variable_ids=coord;endif;P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function write_metrics(path,id,ver,src,outid,seriesid,vid,wid,vname,wname,vunit,wunit,mode,policy,selection_id,input_count,valid_count,excluded,finite_pairs,positive_count,zero_count,provider,api,R,qdef,md,summary_provider,series_provider)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write statistics_metrics.ini',id);endif
  fprintf(fid,'; GX-TXT demo.numeric.statistics metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n\n[source]\ndataset_id=%s\nvalue_variable_id=%s\nweight_variable_id=%s\nvalue_name=%s\nweight_name=%s\nvalue_unit=%s\nweight_unit=%s\nstorage_provider=%s\nselection_id=%s\ninput_count=%d\nvalid_count=%d\nexcluded_nonfinite_count=%d\n',id,ver,src,vid,wid,ini_escape(vname),ini_escape(wname),ini_escape(vunit),ini_escape(wunit),provider,selection_id,input_count,valid_count,excluded);
  fprintf(fid,'\n[statistics]\nmode=%s\nnonfinite_policy=%s\nfinite_pair_count=%.17g\npositive_weight_count=%.17g\nzero_weight_count=%.17g\nmean=%.17g\nmedian=%.17g\nminimum=%.17g\nmaximum=%.17g\nvariance_population=%.17g\nstd_population=%.17g\nrms=%.17g\nquantile_definition=%s\n',mode,policy,finite_pairs,positive_count,zero_count,R.mean,R.median,R.min,R.max,R.variance_population,R.std_population,R.rms,ini_escape(qdef));
  if(strcmp(mode,'descriptive')),fprintf(fid,'variance_sample=%.17g\nstd_sample=%.17g\n',R.variance_sample,R.std_sample);else,fprintf(fid,'sum_weights=%.17g\neffective_n=%.17g\nvariance_unbiased=%.17g\nstd_unbiased=%.17g\n',R.sum_weights,R.effective_n,R.variance_unbiased,R.std_unbiased);endif
  fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n\n[metadata]\nresource_found=%d\n\n[output]\nsummary_dataset_id=%s\nsummary_storage_provider=%s\nseries_dataset_id=%s\nseries_storage_provider=%s\n',api.name,api.api_version,api.function_name,double(logical(md.found)),outid,summary_provider,seriesid,series_provider);fclose(fid);
endfunction
function write_report(path,id,ver,src,outid,seriesid,vid,wid,vname,wname,vunit,wunit,mode,policy,selection_id,input_count,valid_count,excluded,finite_pairs,positive_count,zero_count,api,R,qdef,md,names,values,units,summary_diag,summary_result,series_diag,series_result)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write statistics_report.txt',id);endif
  fprintf(fid,'GX-TXT Numerical Statistics Demo\n================================\n\nPlugin: %s %s\nSource Dataset: %s\nValue variable: %s (%s) [%s]\n',id,ver,src,vname,vid,vunit);if(strcmp(mode,'weighted')),fprintf(fid,'Weight variable: %s (%s) [%s]\n',wname,wid,wunit);endif
  fprintf(fid,'Mode: %s\nSelection: %s\nPublic numerical operation: %s\nNaN / Inf policy: %s\nInput count after Selection: %d\nValid/used count: %d\nExcluded non-finite count: %d\n',mode,selection_text(selection_id),api_operation(mode),policy,input_count,valid_count,excluded);
  if(strcmp(mode,'weighted')),fprintf(fid,'Finite value/weight pairs: %.0f\nPositive-weight count: %.0f\nZero-weight count: %.0f\nWeight semantics: explicit statistical weights; measurement uncertainty is not interpreted as weight.\nWeighted quantiles: %s\nWeighted variance: population and reliability-weight unbiased forms are both reported by NUMERIC_API_v1.\n',finite_pairs,positive_count,zero_count,qdef);else,fprintf(fid,'Variance/std convention: both population (n) and sample (n-1) forms returned by NUMERIC_API_v1 are reported.\nQuantile convention: %s\n',qdef);endif
  fprintf(fid,'Dataset Metadata resource present: %s\n\nComputed statistics\n-------------------\n',bool_text(md.found));for k=1:numel(names),fprintf(fid,'%-28s %.12g  %s\n',names{k},values(k),units{k});endfor
  fprintf(fid,'\nUnits\n-----\nLocation, mean, median, standard deviation, RMS and quantiles retain the source unit. Variance uses the squared-unit expression when a source unit exists. Count/effective-count values are dimensionless.\n');if(strcmp(mode,'weighted')),fprintf(fid,'Weighted sum carries value*weight units when the Weight variable is not dimensionless.\n');endif
  fprintf(fid,'\nPublished Datasets\n------------------\nSummary: %s\nSeries for graph/reuse: %s\nBoth are produced through Dataset Publication API v2 with source Dataset/variable provenance.\n',outid,seriesid);
  fprintf(fid,'\nGraphs\n------\n01_statistics_values.png shows observations actually included by the public operation with its mean and median reference lines.\n\nKnown API scope\n---------------\nGX-TXT 0.9.7.82 NUMERIC_API_v1 does not expose standalone covariance or correlation statistical operations, so this demo does not emulate them privately.\n\nValidation: PASS\n');fclose(fid);
endfunction
function s=api_operation(mode),if(strcmp(mode,'weighted')),s='dataset_weighted_statistics';else,s='dataset_statistics + quantiles';endif,endfunction
function s=selection_text(id),if(isempty(id)),s='Full Dataset';else,s=id;endif,endfunction
function s=bool_text(v),if(v),s='yes';else,s='no';endif,endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
