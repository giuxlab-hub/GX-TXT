function demo_numeric_uncertainty_main(args, framework_root)
% Demonstrate public GX-TXT uncertainty and weighting services on Dataset variables.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id = 'demo.numeric.uncertainty';
  module_version = '1.1.0';
  semantics_scope=gxtxt_statistics_scope_v1();
  publication_open = false;
  publication_finalized = false;
  P = struct();
  series_publication_open = false;
  series_publication_finalized = false;
  PS = struct();

  config_path = arg_value(args, '--config', '');
  if (isempty(config_path)), error('%s: --config is required', module_id); endif
  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg, 'runtime.output_dir', ''));
  session = strtrim(gxtxt_ini_get(cfg, 'runtime.session', ''));
  if (isempty(outdir) || isempty(session)), error('%s: runtime.output_dir and runtime.session are required', module_id); endif
  if (exist(outdir, 'dir') != 7), mkdir(outdir); endif

  gxtxt_progress_start('prepare', 'Preparing numerical uncertainty demonstration', 'indeterminate');
  try
    source_dataset_id = strtrim(gxtxt_ini_get(cfg, 'analysis_source.primary.dataset_id', ''));
    if (isempty(source_dataset_id)), source_dataset_id = strtrim(gxtxt_ini_get(cfg, 'dataset.id', '')); endif
    if (isempty(source_dataset_id)), error('%s: primary source Dataset ID is missing', module_id); endif

    value_binding = binding_column(gxtxt_ini_get(cfg, 'bindings.value', ''), 'value');
    aux_binding = binding_column(gxtxt_ini_get(cfg, 'bindings.aux', ''), 'uncertainty / weight');
    if (isempty(value_binding) || isempty(aux_binding)), error('%s: both Measured value and Uncertainty / weight bindings are required', module_id); endif

    [value_unit, ~, value_meta] = gxtxt_analysis_source_variable_meta(cfg, 'primary', value_binding);
    [aux_unit, ~, aux_meta] = gxtxt_analysis_source_variable_meta(cfg, 'primary', aux_binding);
    if (!meta_found(value_meta) || !meta_found(aux_meta)), error('%s: one or more bindings could not be resolved', module_id); endif
    value_id = strtrim(value_meta.variable_id); aux_id = strtrim(aux_meta.variable_id);
    value_name = strtrim(value_meta.name); aux_name = strtrim(aux_meta.name);
    if (isempty(value_id) || isempty(aux_id)), error('%s: stable Dataset variable IDs are required', module_id); endif
    if (strcmp(value_id, aux_id)), error('%s: measured value and uncertainty/weight variables must be different', module_id); endif

    interpretation = lower(strtrim(gxtxt_ini_get(cfg, 'config.input_interpretation', 'standard_uncertainty')));
    if (!any(strcmp(interpretation, {'standard_uncertainty','explicit_weight'}))), error('%s: invalid input interpretation', module_id); endif
    weight_semantics = lower(strtrim(gxtxt_ini_get(cfg, 'config.weight_semantics', 'inverse_variance')));
    if (!any(strcmp(weight_semantics, {'inverse_variance','relative'}))), error('%s: invalid explicit-weight semantics', module_id); endif
    nonfinite_policy = lower(strtrim(gxtxt_ini_get(cfg, 'config.nonfinite_policy', 'omit')));
    if (!any(strcmp(nonfinite_policy, {'omit','error'}))), error('%s: NaN / Inf policy must be omit or error', module_id); endif
    output_dataset_id = strtrim(gxtxt_ini_get(cfg, 'config.output_dataset_id', 'demo.numeric.uncertainty.result'));
    if (isempty(regexp(output_dataset_id, '^[A-Za-z0-9_.-]+$', 'once'))), error('%s: invalid result Dataset ID', module_id); endif
    if (strcmp(output_dataset_id, source_dataset_id)), error('%s: output Dataset ID must differ from source Dataset ID', module_id); endif
    series_dataset_id = [output_dataset_id '.series'];
    if (strcmp(series_dataset_id,source_dataset_id)), error('%s: series Dataset ID must differ from source Dataset ID',module_id); endif

    selection = struct('enabled', false);
    try selection = gxtxt_selection_from_runtime(cfg, 'selection'); catch selerr, error('%s: invalid Dataset Selection: %s', module_id, selerr.message); end_try_catch
    if (selection.enabled), validate_selection(selection, source_dataset_id, module_id); endif
    selection_id = ''; if (selection.enabled && isfield(selection, 'id')), selection_id = strtrim(selection.id); endif

    if (strcmp(interpretation, 'standard_uncertainty') && !strcmp(strtrim(value_unit), strtrim(aux_unit)))
      error('%s: standard-uncertainty mode requires measured value and uncertainty variables to use the same unit string', module_id);
    endif

    numeric = discover_numeric_api(framework_root, module_id);
    noise_model=lower(strtrim(gxtxt_ini_get(cfg,'config.noise_model','unspecified')));
    if(!any(strcmp(noise_model,{'unspecified','independent_gaussian_known_sigma'}))),error('%s: invalid noise model',module_id);endif
    context=struct('y_unit',value_unit,'weight_unit',aux_unit,'sampling_model','independent_observations','noise_model',noise_model);
    provenance_core=struct('producer',module_id,'source_dataset_id',source_dataset_id,'source_variable_ids',[value_id ';' aux_id]);
    metadata = read_optional_metadata(cfg);

    gxtxt_progress_stage('load_dataset', 'Reading selected value and uncertainty/weight variables', 'indeterminate');
    [raw_values, raw_aux, source_provider] = read_selected_inputs(cfg, value_id, aux_id, selection);
    input_count = numel(raw_values);
    if (input_count < 1), error('%s: selected input contains no rows', module_id); endif
    if (numel(raw_aux) != input_count), error('%s: bound variables have inconsistent row counts', module_id); endif

    finite_pair = isfinite(raw_values) & isfinite(raw_aux);
    excluded_nonfinite = input_count - sum(finite_pair);
    if (strcmp(nonfinite_policy, 'error') && excluded_nonfinite > 0)
      % Invoke the public service to preserve its documented non-finite rejection semantics.
      if (strcmp(interpretation, 'explicit_weight'))
        gxtxt_numeric_v1('weighted_statistics', raw_values, raw_aux, struct('nonfinite','error'));
      else
        gxtxt_numeric_v1('statistics', raw_values, struct('nonfinite','error'));
        gxtxt_numeric_v1('propagate_uncertainty', ones(1,input_count)/input_count, raw_aux, struct('input_kind','standard_uncertainty'));
      endif
    endif
    values = raw_values(finite_pair); aux = raw_aux(finite_pair);
    finite_pair_count = numel(values);
    if (finite_pair_count < 1), error('%s: no finite value/auxiliary pairs remain', module_id); endif

    gxtxt_progress_stage('numeric', 'Running public uncertainty-aware numerical operations', 'determinate', 3);
    ordinary = gxtxt_numeric_v1('statistics', values, struct('nonfinite','error'));
    gxtxt_progress_update(1, 3, 'numeric', 'Public descriptive reference complete');

    ordinary_core=gxtxt_statistics_v1('from_numeric','math.numeric.summary','statistics',ordinary,context,struct(),provenance_core);
    records=struct('ordinary',ordinary_core);estimator_core=struct();weighted_core=struct();
    if (strcmp(interpretation, 'standard_uncertainty'))
      % The Jacobian states the arithmetic-mean transformation. Numeric owns
      % propagation; CORE owns its output identities and conditional meaning.
      J = ones(1, finite_pair_count) / finite_pair_count;
      propagated = gxtxt_numeric_v1('propagate_uncertainty', J, aux, struct('input_kind','standard_uncertainty'));
      output_unit=value_unit;if(isempty(output_unit)),output_unit='unspecified';endif
      propagation_context=struct('output_ids',{{'arithmetic_mean'}},'output_units',{{output_unit}},'output_index',1);
      estimator_core=gxtxt_statistics_v1('from_numeric','math.numeric.propagation','propagate_uncertainty',propagated,propagation_context,struct(),provenance_core);
      records.propagation=estimator_core;
      used_values=values;
      operation_text='statistics + propagate_uncertainty';
    else
      weighted=gxtxt_numeric_v1('weighted_statistics',values,aux,struct('nonfinite','error','weight_semantics',weight_semantics));
      weighted_core=gxtxt_statistics_v1('from_numeric','math.numeric.summary','weighted_statistics',weighted,context,struct(),provenance_core);
      records.weighted=weighted_core;estimator_core=weighted_core;
      used_values=values(aux>0);
      operation_text=['weighted_statistics(' weight_semantics ')'];
    endif
    [stat_names,stat_values,stat_units,stat_definitions,stat_statuses,stat_reasons,stat_quantities]=summary_rows(ordinary_core,estimator_core,interpretation,weight_semantics,input_count,finite_pair_count,excluded_nonfinite);
    gxtxt_progress_update(2, 3, 'numeric', 'Public uncertainty/weight operation complete');

    if (isempty(used_values)), error('%s: no observations remain after the public weight policy', module_id); endif
    indices = (1:numel(values))';
    gxtxt_progress_update(3, 3, 'numeric', 'Public numerical results validated');

    source_ids = {value_id, aux_id};
    provenance = sprintf('%s %s via NUMERIC_API_v1; interpretation=%s; weight_semantics=%s; nonfinite=%s; selection=%s', module_id, module_version, interpretation, weight_semantics, nonfinite_policy, selection_id);

    gxtxt_progress_stage('publish', 'Publishing uncertainty result Dataset', 'determinate', 1);
    popts = struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_ids},'source',source_dataset_id, ...
      'provenance',provenance,'notes','Long-form uncertainty/weight summary produced only through public math.numeric operations.');
    popts.statistical_results=records;
    P = gxtxt_publication_v2_open(session, module_id, output_dataset_id, 'table.generic', popts); publication_open = true;
    P = gxtxt_publication_v2_declare_dimension(P, 'result', 0, true);
    P = declare_text(P, 'quantity', 'quantity', 'category');
    P = declare_numeric(P, 'value', 'value', 'derived', '');
    P = declare_text(P, 'unit', 'unit', 'category');
    P = declare_text(P, 'definition', 'definition', 'category');
    for field={'status','reason','quantity_id'},P=declare_text(P,field{1},field{1},'category');endfor
    P = gxtxt_publication_v2_append(P, 'result', {'quantity',stat_names; 'value',stat_values; 'unit',stat_units; 'definition',stat_definitions;'status',stat_statuses;'reason',stat_reasons;'quantity_id',stat_quantities});
    [P, publication_diag] = gxtxt_publication_v2_diagnostics(P);
    [P, publication_result] = gxtxt_publication_v2_finalize(P); publication_finalized = true; publication_open = false;
    gxtxt_progress_update(1, 1, 'publish', 'Published uncertainty result Dataset');

    series_opts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_ids},'source',source_dataset_id, ...
      'provenance',[provenance '; purpose=graph_series'], ...
      'notes','Included measurements and public central estimates for Plot.dataset.');
    series_opts.statistical_results=records;
    PS=gxtxt_publication_v2_open(session,module_id,series_dataset_id,'table.generic',series_opts);series_publication_open=true;
    PS=gxtxt_publication_v2_declare_dimension(PS,'sample',0,true);
    PS=declare_series_numeric(PS,'sample_index','independent','1','');
    PS=declare_series_numeric(PS,'value','measured',value_unit,'sample_index');
    PS=declare_series_numeric(PS,'aux','auxiliary',aux_unit,'sample_index');
    PS=declare_series_numeric(PS,'ordinary_reference','reference',value_unit,'sample_index');
    series_items={'sample_index',indices;'value',values;'aux',aux; ...
      'ordinary_reference',ones(numel(values),1)*ordinary_core.quantities.mean.value};
    if(strcmp(interpretation,'explicit_weight'))
      PS=declare_series_numeric(PS,'weighted_reference','reference',value_unit,'sample_index');
      series_items(end+1,:)={'weighted_reference',ones(numel(values),1)*weighted_core.quantities.mean.value};
    endif
    PS=gxtxt_publication_v2_append(PS,'sample',series_items);
    [PS,series_result]=gxtxt_publication_v2_finalize(PS);series_publication_finalized=true;series_publication_open=false;

    write_metrics(fullfile(outdir,'uncertainty_metrics.ini'), module_id, module_version, source_dataset_id, output_dataset_id, ...
      value_id, aux_id, value_name, aux_name, value_unit, aux_unit, interpretation, weight_semantics, nonfinite_policy, selection_id, ...
      input_count, finite_pair_count, excluded_nonfinite, source_provider, numeric, ordinary_core, estimator_core, metadata, P.provider);
    write_report(fullfile(outdir,'uncertainty_report.txt'), module_id, module_version, source_dataset_id, output_dataset_id, ...
      value_id, aux_id, value_name, aux_name, value_unit, aux_unit, interpretation, weight_semantics, nonfinite_policy, selection_id, ...
      input_count, finite_pair_count, excluded_nonfinite, numeric, operation_text, records, ...
      metadata, stat_names, stat_values, stat_units, publication_diag, publication_result);

    save(fullfile(outdir,'render_cache.mat'), 'series_dataset_id','value_name','value_unit','interpretation','weight_semantics','output_dataset_id');
    demo_numeric_uncertainty_render(outdir,series_dataset_id,value_name,value_unit,interpretation,cfg);

    gxtxt_progress_complete('done', sprintf('Published %s; interpretation=%s', output_dataset_id, interpretation));
    fprintf('[%s] version=%s source=%s result=%s interpretation=%s input=%d finite_pairs=%d excluded_nonfinite=%d validation=PASS\n', ...
      module_id,module_version,source_dataset_id,output_dataset_id,interpretation,input_count,finite_pair_count,excluded_nonfinite);
  catch err
    if (publication_open && !publication_finalized), try P = gxtxt_publication_v2_abort(P); catch; end_try_catch, endif
    if (series_publication_open && !series_publication_finalized), try PS = gxtxt_publication_v2_abort(PS); catch; end_try_catch, endif
    try gxtxt_progress_fail('failed','Uncertainty demonstration failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function tf=meta_found(meta), tf=isstruct(meta)&&isfield(meta,'found')&&meta.found; endfunction

function out=binding_column(value,role)
  value=strtrim(value); if(isempty(value)||strcmp(value,'auto')),out='';return;endif
  dot=find(value=='.',1); if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif
  if(isempty(out)),error('demo.numeric.uncertainty: invalid %s binding',role);endif
endfunction

function validate_selection(S,dataset_id,module_id)
  if(!S.enabled),return;endif
  if(!isfield(S,'source_dataset_id')||!strcmp(strtrim(S.source_dataset_id),dataset_id)),error('%s: Dataset Selection source does not match the bound Dataset',module_id);endif
  if(!isfield(S,'type')||!strcmp(lower(strtrim(S.type)),'x_range')),error('%s: only X-range Dataset Selection is supported',module_id);endif
  if(!isfield(S,'x_variable_id')||isempty(strtrim(S.x_variable_id))),error('%s: Dataset Selection lacks a stable X variable ID',module_id);endif
endfunction

function md=read_optional_metadata(cfg)
  try md=gxtxt_analysis_source_dataset_metadata(cfg,'primary'); catch, md=struct('found',false,'count',0,'keys',{{}},'values',{{}}); end_try_catch
endfunction

function [values,aux,provider]=read_selected_inputs(cfg,value_id,aux_id,selection)
  ids={value_id,aux_id}; value_pos=1; aux_pos=2; x_pos=0;
  if(selection.enabled)
    sx=strtrim(selection.x_variable_id); x_pos=find(strcmp(ids,sx),1);
    if(isempty(x_pos)),ids{end+1}=sx;x_pos=numel(ids);endif
  endif
  S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false));
  provider=S.storage_provider; parts=cell(1,numel(ids)); for j=1:numel(ids),parts{j}={};endfor
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows>0),for j=1:numel(ids),parts{j}{end+1}=double(C.values{j}(:));endfor,endif
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  data=cell(1,numel(ids));
  for j=1:numel(ids),if(isempty(parts{j})),data{j}=zeros(0,1);else,data{j}=vertcat(parts{j}{:});endif,endfor
  values=data{value_pos}; aux=data{aux_pos};
  if(selection.enabled),mask=gxtxt_selection_mask(selection,data{x_pos});values=values(mask);aux=aux(mask);endif
endfunction

function api=discover_numeric_api(root,module_id)
  descriptor=fullfile(root,'plugins','modules','math.numeric','module.ini');
  if(exist(descriptor,'file')!=2),error('%s: math.numeric descriptor missing',module_id);endif
  d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));
  if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: NUMERIC_API_v1 is not advertised',module_id);endif
  ver=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));if(!strcmp(ver,'1')),error('%s: unsupported NUMERIC_API_v1 version: %s',module_id,ver);endif
  caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));
  required={'descriptive_statistics','weighted_statistics','uncertainty_propagation','dataset_selection','stable_variable_identity'};
  for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor
  entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));
  if(isempty(entry)||isempty(fn)),error('%s: incomplete NUMERIC_API_v1 Octave binding',module_id);endif
  entry_path=fullfile(fileparts(descriptor),entry);if(exist(entry_path,'file')!=2),error('%s: advertised NUMERIC_API_v1 entrypoint missing',module_id);endif
  addpath(fileparts(entry_path));if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif
  if(!strcmp(fn,'gxtxt_numeric_v1')),error('%s: unsupported public Numeric binding',module_id);endif
  api=struct('name','NUMERIC_API_v1','api_version',ver,'function_name',fn,'entrypoint',entry);
endfunction

function [names,vals,units,defs,statuses,reasons,quantities]=summary_rows(R,U,mode,semantics,input_count,valid_count,excluded)
  bookkeeping=struct('input_count',input_count,'valid_pair_count',valid_count,'finite_pair_count',valid_count,'excluded_nonfinite_count',excluded);
  notes=struct('input_count','Rows after Dataset Selection','valid_pair_count','Finite value/uncertainty pairs','finite_pair_count','Finite value/weight pairs before zero-weight removal','excluded_nonfinite_count','Pairs omitted by the explicit nonfinite policy');
  if(strcmp(mode,'standard_uncertainty'))
    names={'input_count';'valid_pair_count';'excluded_nonfinite_count';'arithmetic_mean';'standard_uncertainty_of_mean';'std_population';'std_sample'};
    rows=gxtxt_statistics_v1('scalar_rows',R,struct('arithmetic_mean','mean','std_population','standard_deviation_population','std_sample','standard_deviation'));
    extra=gxtxt_statistics_v1('scalar_rows',U,struct('standard_uncertainty_of_mean','standard_uncertainty'));rows=[rows(:);extra(:)];
  else
    names={'input_count';'finite_pair_count';'excluded_nonfinite_count';'positive_weight_count';'sum_weights';'effective_sample_size';'ordinary_mean';'weighted_mean';'weighted_std_population';'weighted_std_unbiased'};
    mapping=struct('positive_weight_count','n','sum_weights','sum_weights','effective_sample_size','effective_n','weighted_mean','mean','weighted_std_population','standard_deviation_population','weighted_std_unbiased','standard_deviation');
    if(strcmp(semantics,'inverse_variance'))
      names=[names;{'weighted_estimate_standard_error';'reduced_chi_squared'}];
      mapping.weighted_estimate_standard_error='measurement_standard_error_mean';mapping.reduced_chi_squared='reduced_chi_squared';
    endif
    rows=gxtxt_statistics_v1('scalar_rows',R,struct('ordinary_mean','mean'));extra=gxtxt_statistics_v1('scalar_rows',U,mapping);rows=[rows(:);extra(:)];
  endif
  indexed=struct();for k=1:numel(rows),row=rows{k};indexed.(row.id)=row;endfor
  vals=zeros(numel(names),1);units=cell(size(names));defs=cell(size(names));statuses=cell(size(names));reasons=cell(size(names));quantities=cell(size(names));
  for k=1:numel(names)
    name=names{k};
    if(isfield(bookkeeping,name)),vals(k)=bookkeeping.(name);units{k}='1';defs{k}=notes.(name);statuses{k}='value';reasons{k}='';quantities{k}='';
    else row=indexed.(name);vals(k)=row.value;units{k}=row.unit_text;defs{k}=row.label;statuses{k}=row.status;reasons{k}=row.reason;quantities{k}=row.quantity;endif
  endfor
endfunction

function P=declare_text(P,id,name,role)
  spec=struct('dtype','string','dimension_ids','result','name',name,'unit','','semantic_role',role,'value_kind','text','coordinate_role','data','axis_kind','none');
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction
function P=declare_numeric(P,id,name,role,unit)
  spec=struct('dtype','float64','dimension_ids','result','name',name,'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction
function P=declare_series_numeric(P,id,role,unit,coordinate_id)
  spec=struct('dtype','float64','dimension_ids','sample','name',id,'unit',unit, ...
    'semantic_role',role,'axis_kind','explicit');
  if(isempty(coordinate_id)),spec.coordinate_role='coordinate';
  else spec.coordinate_role='data';spec.coordinate_variable_ids=coordinate_id;endif
  P=gxtxt_publication_v2_declare_variable(P,id,spec);
endfunction

function write_metrics(path,id,ver,src,outid,vid,aid,vname,aname,vunit,aunit,mode,wsem,policy,selection_id,input_count,valid_count,excluded,provider,api,R,U,md,pub_provider)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write uncertainty_metrics.ini',id);endif
  fprintf(fid,'; GX-TXT demo.numeric.uncertainty metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n',id,ver);
  fprintf(fid,'\n[source]\ndataset_id=%s\nvalue_variable_id=%s\naux_variable_id=%s\nvalue_name=%s\naux_name=%s\nvalue_unit=%s\naux_unit=%s\nstorage_provider=%s\nselection_id=%s\ninput_count=%d\nvalid_pair_count=%d\nexcluded_nonfinite_count=%d\n',src,vid,aid,ini_escape(vname),ini_escape(aname),ini_escape(vunit),ini_escape(aunit),provider,selection_id,input_count,valid_count,excluded);
  fprintf(fid,'\n[analysis]\ninput_interpretation=%s\nweight_semantics=%s\nnonfinite_policy=%s\n',mode,wsem,policy);
  fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',R,struct('ordinary_mean','mean')));
  if(strcmp(mode,'standard_uncertainty'))
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',U,struct('estimator_standard_uncertainty','standard_uncertainty')));
  else
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',U,struct('estimator_standard_uncertainty','measurement_standard_error_mean','weighted_mean','mean','sum_weights','sum_weights','effective_sample_size','effective_n','reduced_chi_squared','reduced_chi_squared')));
  endif
  fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n\n[metadata]\nresource_found=%d\n\n[output]\ndataset_id=%s\nstorage_provider=%s\n',api.name,api.api_version,api.function_name,double(logical(md.found)),outid,pub_provider);
  fclose(fid);
endfunction

function write_report(path,id,ver,src,outid,vid,aid,vname,aname,vunit,aunit,mode,wsem,policy,selection_id,input_count,valid_count,excluded,api,operation_text,records,md,names,vals,units,pub_diag,pub_result)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write uncertainty_report.txt',id);endif
  fprintf(fid,'GX-TXT Numerical Uncertainty Demo\n=================================\n\nPlugin: %s %s\nSource Dataset: %s\nMeasured variable: %s (%s) [%s]\nAuxiliary variable: %s (%s) [%s]\n',id,ver,src,vname,vid,vunit,aname,aid,aunit);
  fprintf(fid,'Input interpretation: %s\nSelection: %s\nNaN / Inf policy: %s\nPublic numerical operation(s): %s\nInput count after Selection: %d\nFinite pair count: %d\nExcluded non-finite pairs: %d\n',mode,selection_text(selection_id),policy,operation_text,input_count,valid_count,excluded);
  if(strcmp(mode,'standard_uncertainty'))
    fprintf(fid,'\nUncertainty semantics\n---------------------\nThe auxiliary variable is interpreted as measurement standard uncertainty and must use the same unit string as the measured value.\nThe arithmetic mean is computed by public statistics. Its uncertainty is computed by public propagate_uncertainty using the Jacobian of the arithmetic mean and independent input standard uncertainties.\nNo conversion from uncertainty to statistical weight is performed by this plugin.\nZero standard uncertainty is accepted by the public propagation API; negative standard uncertainty is rejected.\n');
  else
    fprintf(fid,'\nWeight semantics\n----------------\nThe auxiliary variable is interpreted only as an explicit statistical weight. It is not reinterpreted as measurement uncertainty.\nConfigured weight semantics: %s\nNo sigma-to-weight conversion is performed by this plugin.\nPublic weighted_statistics rejects negative weights, discards zero weights, and requires at least one positive weight.\n',wsem);
    if(strcmp(wsem,'inverse_variance'))
      fprintf(fid,'The known measurement uncertainty of the weighted mean is returned by public weighted_statistics under independent absolute inverse-variance assumptions. CORE exposes reduced chi-squared only when the independent Gaussian known-sigma noise model is explicitly selected.\n');
    else
      fprintf(fid,'Relative weights do not by themselves define absolute measurement uncertainty; this demo therefore does not label a fit-derived standard error as measurement uncertainty in relative mode.\n');
    endif
  endif
  fprintf(fid,'\nCORE interpreted results\n------------------------\n');
  labels=fieldnames(records);for k=1:numel(labels),fprintf(fid,'\n%s\n%s\n',labels{k},gxtxt_statistics_v1('report',records.(labels{k})));endfor
  fprintf(fid,'\nPublished Dataset\n-----------------\nDataset ID: %s\nLong-form schema: quantity, value, unit, definition, status, reason, quantity_id\nProduced through Dataset Publication API v2 with source Dataset and stable source-variable provenance.\n',outid);
  fprintf(fid,'\nGraph\n-----\n01_uncertainty_measurements.png is produced through the normal Graph Provider/shared GX-TXT graphics path.\n');
  if(strcmp(mode,'standard_uncertainty')),fprintf(fid,'Measurement markers use the supplied standard uncertainty as Y error bars, with the ordinary mean reference line.\n');else,fprintf(fid,'The graph compares the ordinary and weighted central estimates; explicit statistical weights are not drawn as uncertainty error bars.\n');endif
  fprintf(fid,'\nMetadata\n--------\nOptional Dataset Metadata resource present: %s\n\nKnown limitations\n-----------------\nThis demo preserves the explicitly selected interpretation of the auxiliary variable; it does not convert supplied uncertainties into weights.\nStandard-uncertainty mode currently requires exactly matching unit strings rather than performing a private uncertainty-unit conversion.\nThis is a reference demo, not a GUM uncertainty-budget application.\n\nValidation: PASS\n',bool_text(md.found));
  fclose(fid);
endfunction

function s=selection_text(id),if(isempty(id)),s='Full Dataset';else,s=id;endif,endfunction
function s=bool_text(v),if(v),s='yes';else,s='no';endif,endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
