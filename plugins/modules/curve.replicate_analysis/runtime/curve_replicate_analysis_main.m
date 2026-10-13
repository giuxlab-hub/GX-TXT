function curve_replicate_analysis_main(args)
% GX-TXT Replicate Curve Analysis - scientific implementation.
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% Scientific scope:
%   replicated curves -> common X basis -> statistical characterization
%   -> consensus curve + empirical uncertainty.
% This module deliberately performs no physical-model fitting and no SPICE work.

  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('curve.replicate_analysis: --config is required'); endif
  cfg=read_ini(config_path);
  rep_numeric('bind',cfg);
  outdir=strtrim(ini_get(cfg,'runtime.output_dir',''));
  if(isempty(outdir)), error('curve.replicate_analysis: runtime.output_dir missing'); endif
  if(exist(outdir,'dir')!=7), mkdir(outdir); endif

  progress_start_safe('loading_sources','Preparing replicated curve sources','indeterminate',0);
  try
    x_binding=strtrim(ini_get(cfg,'bindings.x',''));
    y_binding=strtrim(ini_get(cfg,'bindings.y',''));
    family_binding=strtrim(ini_get(cfg,'bindings.family',''));
    replicate_binding=strtrim(ini_get(cfg,'bindings.replicate',''));
    if(isempty(x_binding) || isempty(y_binding))
      error('curve.replicate_analysis: X and Y bindings are required');
    endif

    [x_source,x_name]=binding_source_and_name(cfg,x_binding);
    [y_source,y_name]=binding_source_and_name(cfg,y_binding);
    [family_source,family_name]=binding_source_and_name(cfg,family_binding);
    [~,replicate_name]=binding_source_and_name(cfg,replicate_binding);
    if(strcmpi(strtrim(replicate_name),'auto')),replicate_name='';endif

    binding_warnings={};
    [x_name,w]=normalize_numeric_binding(cfg,x_source,x_name,{'independent'},'X');
    binding_warnings=[binding_warnings w];
    [y_name,w]=normalize_numeric_binding(cfg,y_source,y_name,{'measured','dependent'},'Y');
    binding_warnings=[binding_warnings w];
    if(!isempty(family_name))
      [family_name,w]=normalize_numeric_binding(cfg,family_source,family_name,{'family'},'Family');
      binding_warnings=[binding_warnings w];
    endif
    has_family=!isempty(family_name);

    min_trace_points=parse_positive_int(ini_get(cfg,'config.min_trace_points','5'),5,2);
    reset_step_factor=parse_positive_num(ini_get(cfg,'config.reset_step_factor','5'),5);
    reset_span_fraction=parse_fraction(ini_get(cfg,'config.reset_span_fraction','0.35'),0.35);
    replicate_handling=lower(strtrim(ini_get(cfg,'config.replicate_handling','')));
    old_segmentation=lower(strtrim(ini_get(cfg,'config.segmentation_method','')));
    if(isempty(replicate_handling))
      % Backward compatibility with v1-v3 saved runtime configs.
      if(any(strcmp(old_segmentation,{'x_reset','x_reset_legacy','contiguous_only','contiguous_only_legacy'})))
        replicate_handling='legacy_ordered_rows';
      elseif(strcmp(old_segmentation,'unordered'))
        replicate_handling='one_curve_per_source_family';
      else
        replicate_handling='automatic';
      endif
    endif
    if(!any(strcmp(replicate_handling,{'automatic','one_curve_per_source_family','legacy_ordered_rows'})))
      error('curve.replicate_analysis: unknown replicate_handling: %s',replicate_handling);
    endif
    if(strcmp(replicate_handling,'legacy_ordered_rows'))
      segmentation_method='x_reset_legacy';
    elseif(strcmp(replicate_handling,'one_curve_per_source_family'))
      segmentation_method='unordered_single';
    else
      % Automatic starts order-independent. After the sources are inspected it
      % becomes either explicit-ID grouping or unlabeled statistical inference.
      segmentation_method='unordered_auto';
    endif
    common_grid_method=lower(strtrim(ini_get(cfg,'config.common_grid','pooled_x')));
    if(!any(strcmp(common_grid_method,{'pooled_x','linspace'})))
      error('curve.replicate_analysis: unknown common_grid: %s',common_grid_method);
    endif
    grid_points=parse_positive_int(ini_get(cfg,'config.grid_points','200'),200,2);
    fit_output_grid=lower(strtrim(ini_get(cfg,'config.fit_output_grid','reference_grid')));
    if(!any(strcmp(fit_output_grid,{'reference_grid','uniform_grid'})))
      error('curve.replicate_analysis: fit_output_grid must be reference_grid or uniform_grid');
    endif
    fit_output_grid_points=parse_positive_int(ini_get(cfg,'config.fit_output_grid_points','200'),200,2);
    interpolation_method=lower(strtrim(ini_get(cfg,'config.interpolation','linear')));
    if(!strcmp(interpolation_method,'linear'))
      error('curve.replicate_analysis: only linear interpolation is supported in v1');
    endif
    consensus_center=lower(strtrim(ini_get(cfg,'config.consensus_center','mean')));
    if(!any(strcmp(consensus_center,{'mean','median'})))
      error('curve.replicate_analysis: consensus_center must be mean or median');
    endif

    [source_ids,source_dataset_ids,source_labels,warnings]=resolve_sources(cfg);
    warnings=[binding_warnings warnings];
    n_sources=numel(source_ids);
    if(n_sources<1), error('curve.replicate_analysis: no input sources configured'); endif

    replicate_origin='none';
    if(!isempty(replicate_name))
      replicate_origin='explicit binding';
    elseif(strcmp(replicate_handling,'automatic'))
      [replicate_name,auto_rep_warnings]=auto_detect_replicate_variable(cfg,source_ids);
      warnings=[warnings auto_rep_warnings];
      if(!isempty(replicate_name)), replicate_origin='auto-detected column'; endif
    endif

    progress_stage_safe('loading_sources','Loading canonical Dataset sources','determinate',n_sources);
    sources=struct([]);
    for si=1:n_sources
      [rows,load_warnings]=read_bound_source(cfg,source_ids{si},x_name,y_name,family_name,replicate_name);
      warnings=[warnings load_warnings];
      s=struct(); s.index=si; s.label=source_labels{si}; s.dataset_id=source_dataset_ids{si}; s.path=['dataset:' source_dataset_ids{si}]; s.rows=rows;
      sources=append_struct(sources,s);
      progress_update_safe(si,n_sources,'loading_sources','Loading canonical Dataset sources');
    endfor

    if(strcmp(replicate_handling,'automatic'))
      if(!isempty(replicate_name))
        segmentation_method='unordered_explicit';
      else
        segmentation_method='unlabelled_point_cloud';
        replicate_origin='unlabelled repeated points';
        warnings{end+1}='Automatic input: no replicate/curve ID column found. Using order-independent unlabelled point-cloud statistics; no discrete replicate count is inferred.';
      endif
    endif

    fprintf('[curve.replicate_analysis] input mode=%s replicate_id=%s (%s) row_order=%s\n', ...
            replicate_handling,display_or_none(replicate_name),replicate_origin,row_order_text(replicate_name,segmentation_method));

    progress_stage_safe('detecting_traces','Preparing repeated-data groups','determinate',n_sources);
    traces=struct([]);
    for si=1:n_sources
      [st,tw]=detect_source_traces(sources(si),has_family,!isempty(replicate_name),segmentation_method, ...
                                   min_trace_points,reset_step_factor,reset_span_fraction);
      warnings=[warnings tw];
      for ti=1:numel(st), traces=append_struct(traces,st(ti)); endfor
      progress_update_safe(si,n_sources,'detecting_traces','Preparing repeated-data groups');
    endfor
    traces=assign_replicate_indices(traces,has_family);
    if(isempty(traces)), error('curve.replicate_analysis: no valid traces remain after segmentation'); endif

    [family_values,family_labels]=trace_family_catalog(traces,has_family);
    n_groups=numel(family_values);

    progress_stage_safe('building_common_grids','Building common X grids','determinate',n_groups);
    groups=struct([]);
    for gi=1:n_groups
      [g,gw]=build_group_definition(traces,family_values(gi),family_labels{gi},has_family,common_grid_method,grid_points);
      warnings=[warnings gw];
      if(g.valid), groups=append_struct(groups,g); endif
      progress_update_safe(gi,n_groups,'building_common_grids','Building common X grids');
    endfor
    if(isempty(groups)), error('curve.replicate_analysis: no family/single-curve group has a valid common X domain'); endif

    progress_stage_safe('interpolating','Interpolating traces on common X grids','determinate',numel(groups));
    for gi=1:numel(groups)
      if(group_is_unlabelled_cloud(groups(gi),traces))
        groups(gi).Y=[];
      else
        groups(gi)=interpolate_group(groups(gi),traces,interpolation_method);
      endif
      progress_update_safe(gi,numel(groups),'interpolating','Interpolating traces on common X grids');
    endfor

    progress_stage_safe('computing_statistics','Computing consensus and uncertainty statistics','determinate',numel(groups));
    results=struct([]);
    for gi=1:numel(groups)
      if(group_is_unlabelled_cloud(groups(gi),traces))
        [r,rw]=compute_group_cloud_statistics(groups(gi),traces);
      else
        [r,rw]=compute_group_statistics(groups(gi),traces);
      endif
      warnings=[warnings rw];
      results=append_struct(results,r);
      progress_update_safe(gi,numel(groups),'computing_statistics','Computing consensus and uncertainty statistics');
    endfor

    primary_source_index=NaN;
    if(parse_bool(ini_get(cfg,'config.include_primary_dataset','1'),true)), primary_source_index=1; endif
    primary_dataset_id=strtrim(ini_get(cfg,'dataset.id',ini_get(cfg,'config.dataset_id','primary')));
    fit_outputs=build_fit_outputs(results,traces,fit_output_grid,fit_output_grid_points,consensus_center,primary_source_index);

    progress_stage_safe('writing_outputs','Writing scientific CSV and summary outputs','determinate',5);
    write_consensus(fullfile(outdir,'consensus_for_fitting.csv'),fit_outputs,x_name,family_name,y_name,has_family);
    progress_update_safe(1,5,'writing_outputs','Writing scientific CSV and summary outputs');
    write_uncertainty_profile(fullfile(outdir,'uncertainty_profile.csv'),results,x_name,family_name,has_family);
    progress_update_safe(2,5,'writing_outputs','Writing scientific CSV and summary outputs');
    write_replicate_statistics(fullfile(outdir,'replicate_statistics.csv'),traces,has_family);
    progress_update_safe(3,5,'writing_outputs','Writing scientific CSV and summary outputs');
    write_source_statistics(fullfile(outdir,'source_statistics.csv'),results,traces,has_family);
    progress_update_safe(4,5,'writing_outputs','Writing scientific CSV and summary outputs');
    write_summary(fullfile(outdir,'replicate_analysis_summary.txt'),source_dataset_ids,source_labels,traces,results,warnings, ...
                  x_name,family_name,y_name,replicate_name,has_family,replicate_handling,replicate_origin,segmentation_method,min_trace_points, ...
                  reset_step_factor,reset_span_fraction,common_grid_method,grid_points,interpolation_method,consensus_center, ...
                  fit_output_grid,fit_output_grid_points,fit_outputs,primary_dataset_id);
    progress_update_safe(5,5,'writing_outputs','Writing scientific CSV and summary outputs');

    session=strtrim(ini_get(cfg,'runtime.session',''));D=struct();
    if(!isempty(session))
      progress_stage_safe('publishing_datasets','Publishing canonical curve and uncertainty Datasets','indeterminate',0);
      publication_sources=selected_dataset_ids(cfg,source_ids,primary_dataset_id);
      D=curve_replicate_publish(session,publication_sources,traces,results,rep_numeric('function'));
    endif
    % v15 Plot Dataset delegated graphics: the render cache carries the actual accepted
    % traces and statistical profiles. Plot Dataset is the render backend; producer-visible identity remains module-owned.
    render_traces=traces;render_results=results;
    stale_graph_manifest=fullfile(outdir,'automatic_graphs.ini');
    if(exist(stale_graph_manifest,'file')==2),unlink(stale_graph_manifest);endif
    progress_stage_safe('building_render_cache','Building render cache','indeterminate',0);
    save(fullfile(outdir,'render_cache.mat'),'render_traces','render_results','D','has_family','x_name','family_name','y_name','replicate_name', ...
         'source_dataset_ids','source_labels','replicate_handling','replicate_origin','segmentation_method','min_trace_points','reset_step_factor','reset_span_fraction', ...
         'common_grid_method','grid_points','interpolation_method','consensus_center','fit_output_grid','fit_output_grid_points', ...
         'fit_outputs','primary_dataset_id','warnings');

    if(!isempty(session))
      curve_replicate_render_public(outdir,render_traces,render_results,D,has_family,x_name,family_name,y_name,cfg,config_path,'render');
    endif

    if(strcmp(segmentation_method,'unlabelled_point_cloud'))
      fprintf('[curve.replicate_analysis] version=15.2 mode=unlabelled_point_cloud sources=%d clouds=%d groups=%d warnings=%d\n', ...
              n_sources,numel(traces),numel(results),numel(warnings));
    else
      fprintf('[curve.replicate_analysis] version=15.2 mode=%s sources=%d traces=%d groups=%d warnings=%d\n', ...
              segmentation_method,n_sources,numel(traces),numel(results),numel(warnings));
    endif
    progress_complete_safe('completed','Replicate curve analysis completed');
  catch err
    progress_fail_safe('failed','Replicate curve analysis failed; see log for details');
    rethrow(err);
  end_try_catch
endfunction

function out=trace_render_metadata(traces)
  out=struct('source_label',{},'source_index',{},'replicate_index',{},'family_value',{},'representation',{});
  for i=1:numel(traces)
    t=traces(i);out(i)=struct('source_label',t.source_label,'source_index',t.source_index, ...
      'replicate_index',t.replicate_index,'family_value',t.family_value,'representation',t.representation);
  endfor
endfunction
function out=result_render_metadata(results)
  out=struct('family_value',{},'family_label',{},'variance_components_identifiable',{}, ...
    'std_available',{},'sem_available',{},'sigma_total_available',{});
  for i=1:numel(results)
    r=results(i);out(i)=struct('family_value',r.family_value,'family_label',r.family_label, ...
      'variance_components_identifiable',r.variance_components_identifiable, ...
      'std_available',any(isfinite(r.y_std)),'sem_available',any(isfinite(r.y_sem)), ...
      'sigma_total_available',any(isfinite(r.sigma_total)));
  endfor
endfunction

function [source_id,name]=binding_source_and_name(cfg,binding)
  source_id='primary'; name=strtrim(binding);
  if(isempty(name)), return; endif
  dot=find(name=='.',1);
  if(isempty(dot)), return; endif
  prefix=name(1:dot-1);
  ids=regexp(ini_get(cfg,'analysis_sources.ids','primary'),'[;,]+','split');
  ids=cellfun(@strtrim,ids,'UniformOutput',false);
  if(any(strcmp(ids,prefix)))
    source_id=prefix; name=name(dot+1:end);
  endif
endfunction

function [name,warnings]=normalize_numeric_binding(cfg,source_id,name,expected_roles,label)
  warnings={}; name=strtrim(name);
  if(isempty(name)), return; endif
  n=str2double(ini_get(cfg,['analysis_source.' source_id '.variable_count'],'0'));
  if(!isfinite(n)||n<1), return; endif

  requested=0; candidates={};
  for i=1:floor(n)
    prefix=sprintf('analysis_source.%s.variable.%d.',source_id,i);
    vname=strtrim(ini_get(cfg,[prefix 'name'],''));
    vid=strtrim(ini_get(cfg,[prefix 'variable_id'],vname));
    original=strtrim(ini_get(cfg,[prefix 'original_header'],''));
    role=lower(strtrim(ini_get(cfg,[prefix 'semantic_role'],'')));
    numeric=variable_meta_is_numeric(cfg,prefix);
    if(strcmp(name,vname)||strcmp(name,vid)||(!isempty(original)&&strcmp(name,original))), requested=i; endif
    if(numeric && any(strcmp(expected_roles,role)))
      if(!isempty(vname)), candidates{end+1}=vname; endif
    endif
  endfor

  if(requested>0)
    prefix=sprintf('analysis_source.%s.variable.%d.',source_id,requested);
    if(variable_meta_is_numeric(cfg,prefix)), return; endif
    if(numel(candidates)==1)
      old=name; name=candidates{1};
      warnings{end+1}=sprintf('Binding correction: %s variable "%s" is non-numeric; using Dataset semantic %s variable "%s".', ...
        label,old,expected_roles{1},name);
      return;
    endif
    if(isempty(candidates))
      error('curve.replicate_analysis: %s binding "%s" is non-numeric and Dataset %s exposes no numeric semantic %s variable.', ...
        label,name,source_id,expected_roles{1});
    endif
    error('curve.replicate_analysis: %s binding "%s" is non-numeric. Select one of the numeric semantic %s variables: %s', ...
      label,name,expected_roles{1},join_cells(candidates,', '));
  endif
endfunction

function numeric=variable_meta_is_numeric(cfg,prefix)
  kind=lower(strtrim(ini_get(cfg,[prefix 'value_kind'],'')));
  dtype=lower(strtrim(ini_get(cfg,[prefix 'dtype'],'')));
  numeric=strcmp(kind,'number') || !isempty(regexp(dtype,'^(float|double|single|int|uint|numeric)','once'));
endfunction

function [ids,dataset_ids,labels,warnings]=resolve_sources(cfg)
  ids={};dataset_ids={};labels={};warnings={};
  include_primary=parse_bool(ini_get(cfg,'config.include_primary_dataset','1'),true);
  raw=ini_get(cfg,'analysis_sources.ids','');
  source_ids=regexp(raw,'[;,]+','split');
  for i=1:numel(source_ids)
    sid=strtrim(source_ids{i});
    if(isempty(sid)),continue;endif
    if(strcmp(sid,'primary')&&!include_primary),continue;endif
    ds=strtrim(ini_get(cfg,['analysis_source.' sid '.dataset_id'],''));
    if(isempty(ds)),continue;endif
    if(any(strcmp(dataset_ids,ds)))
      warnings{end+1}=sprintf('Duplicate Dataset source ignored: %s (%s)',ds,sid);
      continue;
    endif
    ids{end+1}=sid;dataset_ids{end+1}=ds;labels{end+1}=ds;
  endfor
  if(isempty(ids))
    error('curve.replicate_analysis: no populated Analysis Source Dataset IDs are configured');
  endif
endfunction

function [name,warnings]=auto_detect_replicate_variable(cfg,source_ids)
  name='';warnings={};candidates={'replicate_id','replicate','curve_id','curve','trace_id','trace','rep_id','rep'};
  for ci=1:numel(candidates)
    candidate=candidates{ci};actual='';all_have=true;
    for si=1:numel(source_ids)
      sid=strtrim(source_ids{si});
      found=source_variable_named(cfg,sid,candidate);
      if(isempty(found)),all_have=false;break;endif
      if(si==1),actual=found;endif
    endfor
    if(all_have)
      name=actual;warnings{end+1}=sprintf('Automatic input: using curve/replicate identifier variable "%s" from Dataset metadata; row order is ignored.',name);return;
    endif
  endfor
  warnings{end+1}='Automatic input: no common curve/replicate identifier variable found in Dataset metadata; using unlabelled repeated-point mode.';
endfunction

function found=source_variable_named(cfg,source_id,target)
  found='';n=str2double(ini_get(cfg,['analysis_source.' source_id '.variable_count'],'0'));
  if(!isfinite(n)||n<1),return;endif
  for i=1:floor(n)
    prefix=sprintf('analysis_source.%s.variable.%d.',source_id,i);
    vname=strtrim(ini_get(cfg,[prefix 'name'],''));vid=strtrim(ini_get(cfg,[prefix 'variable_id'],vname));original=strtrim(ini_get(cfg,[prefix 'original_header'],''));
    if(strcmpi(target,vname)||strcmpi(target,vid)||(!isempty(original)&&strcmpi(target,original))),found=vid;return;endif
  endfor
endfunction

function s=join_cells(cells,sep)
  if(isempty(cells)), s=''; return; endif
  s=cells{1};
  for i=2:numel(cells), s=[s sep cells{i}]; endfor
endfunction

function s=display_or_none(v)
  if(isempty(v)), s='<none>'; else s=v; endif
endfunction

function dataset_ids=selected_dataset_ids(cfg,source_ids,primary_dataset_id)
  dataset_ids={};
  for i=1:numel(source_ids)
    sid=strtrim(source_ids{i}); if(isempty(sid)),continue;endif
    ds=strtrim(ini_get(cfg,['analysis_source.' sid '.dataset_id'],''));
    if(!isempty(ds)&&!any(strcmp(dataset_ids,ds))),dataset_ids{end+1}=ds;endif
  endfor
  if(isempty(dataset_ids)&&!isempty(primary_dataset_id)),dataset_ids={primary_dataset_id};endif
endfunction

function [rows,warnings]=read_bound_source(cfg,source_id,x_name,y_name,family_name,replicate_name)
  if(isempty(source_id)),error('curve.replicate_analysis: Analysis Source ID is required for framework Dataset access');endif
  warnings={};
  xid=source_variable_id(cfg,source_id,x_name,{'independent'},true);
  yid=source_variable_id(cfg,source_id,y_name,{'measured','dependent'},true);
  if(!isempty(family_name)),fid=source_variable_id(cfg,source_id,family_name,{'family'},true);else fid='';endif
  if(!isempty(replicate_name)),rid=source_variable_id(cfg,source_id,replicate_name,{'identifier','replicate'},false);else rid='';endif
  ids={xid,yid};if(!isempty(fid)),ids{end+1}=fid;endif;if(!isempty(rid)),ids{end+1}=rid;endif
  ids=unique(ids,'stable');
  S=gxtxt_table_stream_open_source(cfg,source_id,ids,65536,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  x=[];y=[];fam=[];rep={};rownum=[];ordinal=0;skipped=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);if(C.nrows<1),continue;endif
      xv=gxtxt_table_chunk_numeric(C,xid);xv=double(xv(:));yv=gxtxt_table_chunk_numeric(C,yid);yv=double(yv(:));
      if(!isempty(fid)),fv=gxtxt_table_chunk_numeric(C,fid);fv=double(fv(:));else fv=NaN(C.nrows,1);endif
      if(!isempty(rid)),rv=column_to_strings(gxtxt_table_chunk_column(C,rid));else rv=repmat({''},C.nrows,1);endif
      for j=1:C.nrows
        ordinal++;
        good=isfinite(xv(j))&&isfinite(yv(j));if(!isempty(fid)),good=good&&isfinite(fv(j));endif
        if(!isempty(rid)),good=good&&!isempty(strtrim(rv{j}));endif
        if(!good),skipped++;continue;endif
        x(end+1,1)=xv(j);y(end+1,1)=yv(j);fam(end+1,1)=fv(j);rep{end+1,1}=rv{j};rownum(end+1,1)=ordinal;
      endfor
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(isempty(x)),error('curve.replicate_analysis: no usable Dataset rows in Analysis Source %s',source_id);endif
  rows=struct('x',x,'y',y,'family',fam,'replicate',{rep},'rownum',rownum);
  if(skipped>0),warnings{end+1}=sprintf('Analysis Source %s: skipped %d rows with missing/non-numeric bound values',source_id,skipped);endif
endfunction

function id=source_variable_id(cfg,source_id,name,roles,require_numeric)
  id=''; n=str2double(ini_get(cfg,['analysis_source.' source_id '.variable_count'],'0'));
  if(!isfinite(n)||n<1),error('curve.replicate_analysis: Analysis Source %s has no variable metadata',source_id);endif
  semantic={};
  for i=1:floor(n)
    prefix=sprintf('analysis_source.%s.variable.%d.',source_id,i);
    vname=strtrim(ini_get(cfg,[prefix 'name'],''));vid=strtrim(ini_get(cfg,[prefix 'variable_id'],vname));
    original=strtrim(ini_get(cfg,[prefix 'original_header'],''));role=lower(strtrim(ini_get(cfg,[prefix 'semantic_role'],'')));
    numeric=variable_meta_is_numeric(cfg,prefix);
    if(strcmp(name,vname)||strcmp(name,vid)||(!isempty(original)&&strcmp(name,original)))
      if(require_numeric&&!numeric),error('curve.replicate_analysis: source %s variable %s is not numeric',source_id,name);endif
      id=vid;return;
    endif
    if(any(strcmp(roles,role))&&(!require_numeric||numeric)),semantic{end+1}=vid;endif
  endfor
  semantic=unique(semantic,'stable');
  if(numel(semantic)==1),id=semantic{1};return;endif
  if(isempty(semantic)),error('curve.replicate_analysis: source %s has no variable matching %s',source_id,name);endif
  error('curve.replicate_analysis: source %s variable %s is ambiguous; semantic candidates: %s',source_id,name,join_cells(semantic,', '));
endfunction

function out=column_to_strings(v)
  if(iscell(v)),out=cell(size(v));for i=1:numel(v),out{i}=value_to_string(v{i});endfor
  elseif(isstring(v)),out=cellstr(v(:));
  elseif(ischar(v)),out=cellstr(v);
  elseif(isnumeric(v)||islogical(v)),out=arrayfun(@(z)sprintf('%.17g',double(z)),v(:),'UniformOutput',false);
  else error('curve.replicate_analysis: unsupported identifier column representation');endif
  out=out(:);
endfunction
function s=value_to_string(v)
  if(ischar(v)),s=v;elseif(isstring(v)),s=char(v);elseif(isnumeric(v)||islogical(v)),s=sprintf('%.17g',double(v));else s='';endif
endfunction

function [traces,warnings]=detect_source_traces(source,has_family,has_explicit_replicate,method,min_points,reset_factor,span_fraction)
  warnings={}; traces=struct([]); r=source.rows;

  if(has_explicit_replicate)
    % Exact, permutation-invariant grouping.  Row order is deliberately
    % ignored; replicate identity comes only from the bound identifier.
    keys={}; buckets={};
    for i=1:numel(r.x)
      fk=family_key(r.family(i),has_family); key=[fk '|' r.replicate{i}];
      pos=find(strcmp(keys,key),1);
      if(isempty(pos)), keys{end+1}=key; buckets{end+1}=i; else buckets{pos}(end+1)=i; endif
    endfor
    [keys,ord]=sort(keys); buckets=buckets(ord);
    for bi=1:numel(keys)
      idx=buckets{bi};
      [t,ok,w]=make_trace(source,r.x(idx),r.y(idx),r.family(idx(1)),has_family,r.replicate{idx(1)},min_points);
      if(!isempty(w)), warnings{end+1}=w; endif
      if(ok), traces=append_struct(traces,t); endif
    endfor
    return;
  endif

  if(strcmp(method,'unordered_single'))
    % Explicit override: one trace per source/family. Row order is ignored.
    if(has_family)
      fams=sort(unique(r.family(:)));
      for fi=1:numel(fams)
        idx=find(r.family==fams(fi));
        [t,ok,w]=make_trace(source,r.x(idx),r.y(idx),fams(fi),has_family,'',min_points);
        if(!isempty(w)), warnings{end+1}=w; endif
        if(ok), traces=append_struct(traces,t); endif
      endfor
    else
      idx=(1:numel(r.x))';
      [t,ok,w]=make_trace(source,r.x(idx),r.y(idx),NaN,has_family,'',min_points);
      if(!isempty(w)), warnings{end+1}=w; endif
      if(ok), traces=append_struct(traces,t); endif
    endif
    warnings{end+1}=sprintf('%s: one_curve_per_source_family selected; row order ignored.',source.label);
    return;
  endif

  if(strcmp(method,'unlabelled_point_cloud'))
    % Order-independent statistics for repeated digitizations without an
    % explicit curve/replicate identifier.  Never infer discrete replicate
    % counts from point density: sampling density and repeat count are distinct.
    if(has_family)
      fams=sort(unique(r.family(:)));
      for fi=1:numel(fams)
        idx=find(r.family==fams(fi));
        [t,ok,w]=make_cloud_trace(source,r.x(idx),r.y(idx),fams(fi),has_family,min_points);
        if(!isempty(w)), warnings{end+1}=w; endif
        if(ok), traces=append_struct(traces,t); endif
      endfor
    else
      idx=(1:numel(r.x))';
      [t,ok,w]=make_cloud_trace(source,r.x(idx),r.y(idx),NaN,has_family,min_points);
      if(!isempty(w)), warnings{end+1}=w; endif
      if(ok), traces=append_struct(traces,t); endif
    endif
    warnings{end+1}=sprintf('%s: unlabelled repeated-point mode; row order ignored, every point preserved, discrete replicate count intentionally not inferred.',source.label);
    return;
  endif

  % Legacy compatibility only. These modes intentionally preserve the v1/v2
  % row-sequence heuristic for old projects that know their CSV row order is
  % acquisition order. They are never the v6 default.
  raw=struct([]); cur_x=[]; cur_y=[]; cur_family=NaN;
  for i=1:numel(r.x)
    fv=r.family(i);
    if(isempty(cur_x))
      cur_x=r.x(i); cur_y=r.y(i); cur_family=fv; continue;
    endif
    family_changed=!same_family(cur_family,fv,has_family);
    reset=false;
    if(!family_changed && strcmp(method,'x_reset_legacy'))
      reset=is_significant_reset(cur_x,r.x(i),reset_factor,span_fraction);
    endif
    if(family_changed || reset)
      reason='reset'; if(family_changed), reason='family'; endif
      raw=append_struct(raw,struct('x',cur_x(:),'y',cur_y(:),'family_value',cur_family,'ended_by',reason));
      cur_x=r.x(i); cur_y=r.y(i); cur_family=fv;
    else
      cur_x(end+1,1)=r.x(i); cur_y(end+1,1)=r.y(i);
    endif
  endfor
  if(!isempty(cur_x))
    raw=append_struct(raw,struct('x',cur_x(:),'y',cur_y(:),'family_value',cur_family,'ended_by','end'));
  endif

  [raw,rw]=merge_short_edge_extensions(raw,source,has_family,min_points,reset_factor,span_fraction);
  warnings=[warnings rw];
  warnings{end+1}=sprintf('%s: legacy row-order replicate segmentation is enabled; results depend on CSV row sequence.',source.label);

  for ri=1:numel(raw)
    q=raw(ri);
    [t,ok,w]=make_trace(source,q.x,q.y,q.family_value,has_family,'',min_points);
    if(!isempty(w)), warnings{end+1}=w; endif
    if(ok), traces=append_struct(traces,t); endif
  endfor
endfunction

function [raw,warnings]=merge_short_edge_extensions(raw,source,has_family,min_points,reset_factor,span_fraction)
  warnings={}; i=2;
  while(i<=numel(raw))
    prev=raw(i-1); cand=raw(i);
    if(short_edge_extension_candidate(prev,cand,has_family,min_points,reset_factor,span_fraction))
      n=numel(cand.x);
      raw(i-1).x=[prev.x(:);cand.x(:)];
      raw(i-1).y=[prev.y(:);cand.y(:)];
      raw(i-1).ended_by=cand.ended_by;
      warnings{end+1}=sprintf('%s family %s: merged %d-point post-reset edge extension into preceding trace', ...
                              source.label,family_display(cand.family_value,has_family),n);
      raw(i)=[];
      continue;
    endif
    i++;
  endwhile
endfunction

function ok=short_edge_extension_candidate(prev,cand,has_family,min_points,reset_factor,span_fraction)
  ok=false;
  if(!same_family(prev.family_value,cand.family_value,has_family)), return; endif
  if(!strcmp(prev.ended_by,'reset')), return; endif
  if(!(strcmp(cand.ended_by,'family') || strcmp(cand.ended_by,'end'))), return; endif
  if(numel(unique(cand.x))>=min_points), return; endif
  d=diff(prev.x(:)); d=d(isfinite(d)&(d!=0)); if(numel(d)<2), return; endif
  med=rep_numeric('statistics',d).median; dir=sign(med); if(dir==0), return; endif
  step=rep_numeric('statistics',abs(d)).median; span=max(prev.x)-min(prev.x); cand_span=max(cand.x)-min(cand.x);
  max_edge_span=max(reset_factor*max(step,eps),span_fraction*max(span,eps));
  if(cand_span>max_edge_span), return; endif
  if(dir<0)
    start_edge=max(prev.x); ok=(rep_numeric('statistics',cand.x).median>start_edge);
  else
    start_edge=min(prev.x); ok=(rep_numeric('statistics',cand.x).median<start_edge);
  endif
endfunction

function reset=is_significant_reset(xs,newx,reset_factor,span_fraction)
  reset=false;
  if(numel(xs)<4), return; endif
  d=diff(xs(:)); d=d(isfinite(d)&(d!=0)); if(numel(d)<2), return; endif
  med=rep_numeric('statistics',d).median; dir=sign(med); if(dir==0), return; endif
  step=rep_numeric('statistics',abs(d)).median; span=max(xs)-min(xs); dx=newx-xs(end);
  threshold=max(reset_factor*max(step,eps),span_fraction*max(span,eps));
  reset=(dx*dir<0 && abs(dx)>=threshold);
endfunction

function [t,ok,warning_text]=make_cloud_trace(source,x,y,family_value,has_family,min_points)
  ok=false; warning_text=''; t=struct(); x=x(:); y=y(:); original_points=numel(x);
  if(original_points<min_points)
    warning_text=sprintf('%s family %s: discarded point cloud with %d points (< %d)',source.label,family_display(family_value,has_family),original_points,min_points);
    return;
  endif
  % Canonical sorting is deterministic only; CSV row order is non-semantic.
  % Exact duplicate X values are retained because repeated digitizations can
  % legitimately land on the same coordinate.
  tab=[x y (1:original_points)']; [~,ord]=sortrows(tab,[1 2]); x=x(ord); y=y(ord);
  t=struct('source_index',source.index,'source_label',source.label,'source_path',source.path, ...
           'family_value',family_value,'family_present',has_family,'replicate_index',0,'replicate_id','unlabelled', ...
           'x',x(:),'y',y(:),'original_points',original_points,'duplicates_collapsed',0, ...
           'direction','order_independent_cloud','representation','unlabelled_cloud');
  ok=true;
endfunction

function [t,ok,warning_text]=make_trace(source,x,y,family_value,has_family,replicate_id,min_points)
  ok=false; warning_text=''; t=struct(); x=x(:); y=y(:); original_points=numel(x);
  if(original_points<min_points)
    warning_text=sprintf('%s family %s: discarded short trace with %d points (< %d)',source.label,family_display(family_value,has_family),original_points,min_points);
    return;
  endif
  % Row order is deliberately non-semantic. Normalize every accepted trace to
  % unique ascending X before interpolation. Exact duplicate X values are
  % collapsed by averaging Y.
  [ux,~,ic]=unique(x);
  uy=accumarray(ic,y,[],@mean);
  direction='ascending_normalized';
  duplicates_collapsed=original_points-numel(ux);
  if(numel(ux)<min_points)
    warning_text=sprintf('%s family %s: discarded trace after duplicate-X collapse (%d unique points)',source.label,family_display(family_value,has_family),numel(ux));
    return;
  endif
  t=struct('source_index',source.index,'source_label',source.label,'source_path',source.path, ...
           'family_value',family_value,'family_present',has_family,'replicate_index',0,'replicate_id',replicate_id, ...
           'x',ux(:),'y',uy(:),'original_points',original_points,'duplicates_collapsed',duplicates_collapsed,'direction',direction,'representation','trace');
  ok=true;
endfunction

function traces=assign_replicate_indices(traces,has_family)
  for i=1:numel(traces)
    n=0;
    for j=1:i
      if(traces(j).source_index==traces(i).source_index && same_family(traces(j).family_value,traces(i).family_value,has_family)), n++; endif
    endfor
    traces(i).replicate_index=n;
    if(isempty(traces(i).replicate_id)), traces(i).replicate_id=sprintf('%d',n); endif
  endfor
endfunction

function [values,labels]=trace_family_catalog(traces,has_family)
  if(!has_family), values=NaN; labels={'all'}; return; endif
  values=[];
  for i=1:numel(traces)
    if(isempty(find(values==traces(i).family_value,1))), values(end+1)=traces(i).family_value; endif
  endfor
  values=sort(values); labels=cell(1,numel(values));
  for i=1:numel(values), labels{i}=sprintf('%.17g',values(i)); endfor
endfunction

function [g,warnings]=build_group_definition(traces,family_value,family_label,has_family,method,grid_points)
  warnings={}; idx=[];
  for i=1:numel(traces)
    if(same_family(traces(i).family_value,family_value,has_family)), idx(end+1)=i; endif
  endfor
  mins=zeros(1,numel(idx)); maxs=mins;
  for k=1:numel(idx), mins(k)=min(traces(idx(k)).x); maxs(k)=max(traces(idx(k)).x); endfor
  lo=max(mins); hi=min(maxs);
  g=struct('valid',false,'family_value',family_value,'family_label',family_label,'trace_indices',idx,'x_min',lo,'x_max',hi,'grid',[],'Y',[]);
  if(!(isfinite(lo)&&isfinite(hi)&&hi>lo))
    warnings{end+1}=sprintf('Family %s: no overlapping X domain across %d traces; excluded from consensus',family_label,numel(idx));
    return;
  endif
  if(strcmp(method,'linspace'))
    grid=rep_numeric('uniform_grid',lo,hi,grid_points,struct('mode','count')).x;
  else
    pool=[];
    for k=1:numel(idx)
      xv=traces(idx(k)).x; pool=[pool; xv(xv>=lo & xv<=hi)];
    endfor
    grid=unique(pool);
    grid=sort(grid(:));
    if(isempty(grid) || grid(1)>lo), grid=[lo;grid]; endif
    if(grid(end)<hi), grid=[grid;hi]; endif
  endif
  if(numel(grid)<2)
    warnings{end+1}=sprintf('Family %s: common X grid has fewer than two points; excluded',family_label);
    return;
  endif
  g.grid=grid; g.valid=true;
endfunction

function g=interpolate_group(g,traces,method)
  nt=numel(g.trace_indices); nx=numel(g.grid); Y=NaN(nx,nt);
  for k=1:nt
    t=traces(g.trace_indices(k));
    Y(:,k)=rep_numeric('interpolate',t.x,t.y,g.grid,struct('method',method)).yq;
    if(any(!isfinite(Y(:,k))))
      error('curve.replicate_analysis: interpolation produced non-finite values inside common domain for family %s',g.family_label);
    endif
  endfor
  g.Y=Y;
endfunction

function yes=group_is_unlabelled_cloud(g,traces)
  yes=!isempty(g.trace_indices);
  for ti=g.trace_indices
    if(!isfield(traces(ti),'representation') || !strcmp(traces(ti).representation,'unlabelled_cloud'))
      yes=false; return;
    endif
  endfor
endfunction

function [r,warnings]=compute_group_cloud_statistics(g,traces)
  warnings={}; nx=numel(g.grid); nt=numel(g.trace_indices);
  source_ids=zeros(1,nt); Y=NaN(nx,nt); local_sigma=NaN(nx,nt); local_n=NaN(nx,nt); raw_total=0;
  for k=1:nt
    t=traces(g.trace_indices(k)); source_ids(k)=t.source_index; raw_total+=t.original_points;
    for xi=1:nx
      [Y(xi,k),local_sigma(xi,k),local_n(xi,k)]=local_cloud_estimate(t.x,t.y,g.grid(xi));
    endfor
  endfor
  sources=unique(source_ids); ns=numel(sources);
  if(any(!isfinite(Y(:))))
    error('curve.replicate_analysis: unlabelled point-cloud local regression failed inside common domain for family %s',g.family_label);
  endif
  row=rep_numeric('matrix_statistics',Y,struct('dimension',2));y_mean=row.mean;y_median=row.median;
  sigma_within=NaN(nx,1); sigma_between=NaN(nx,1); sigma_total=NaN(nx,1);
  identifiable=(ns>=2 && all(isfinite(local_sigma(:))));
  if(identifiable)
    sigma_within=sqrt(rep_numeric('reduce_summary',local_sigma.^2,struct('dimension',2)).mean);
    sigma_between=row.std_sample;
    sigma_total=sqrt(sigma_within.^2 + sigma_between.^2);
    y_std=sigma_total;
  else
    if(ns>=2), y_std=row.std_sample; else y_std=zeros(nx,1); endif
    warnings{end+1}=sprintf('Family %s: unlabelled point-cloud variance components are not identifiable (sources=%d)',g.family_label,ns);
  endif
  % Standard error requires a count of statistically independent repeats.
  % The raw cloud does not encode that count, therefore y_sem is unavailable.
  y_sem=NaN(nx,1);
  warnings{end+1}=sprintf('Family %s: using order-independent unlabelled point-cloud estimator; discrete replicate count and y_sem are not inferred.',g.family_label);
  r=struct('family_value',g.family_value,'family_label',g.family_label,'trace_indices',g.trace_indices, ...
           'x',g.grid,'Y',Y,'y_mean',y_mean,'y_median',y_median,'y_std',y_std,'y_sem',y_sem, ...
           'n',nt,'n_sources',ns,'source_ids',source_ids,'sigma_within',sigma_within,'sigma_between',sigma_between,'sigma_total',sigma_total, ...
           'variance_components_identifiable',identifiable,'x_min',g.x_min,'x_max',g.x_max, ...
           'statistics_mode','unlabelled_point_cloud','replicate_count_known',false,'n_raw_points',raw_total,'local_n',local_n);
endfunction

function [mu,sigma,nlocal]=local_cloud_estimate(x,y,x0)
  x=x(:); y=y(:); n=numel(x);
  if(n<4), mu=NaN; sigma=NaN; nlocal=n; return; endif
  % Local quadratic fit removes physical curve slope/curvature before the
  % residual spread is interpreted as digitization repeatability.  The
  % deterministic nearest-neighbour window depends only on the point cloud,
  % never on CSV row order and never on an inferred replicate count.
  k=round(1.5*sqrt(n)); k=max(10,k); k=min(25,k); k=min(n,k); nlocal=k;
  d=abs(x-x0); tab=[d x y (1:n)']; [~,ord]=sortrows(tab,[1 2 3]); idx=ord(1:k);
  xx=x(idx); yy=y(idx); z=xx-x0; dd=abs(z); dmax=max(dd);
  if(!isfinite(dmax) || dmax<=0)
    w=ones(k,1);
  else
    u=min(1,dd./dmax); w=(1-u.^3).^3; w=max(w,1e-6);
  endif
  A=[ones(k,1) z z.^2];
  fit=rep_numeric('least_squares',A,yy,w,struct('rank_policy','minimum_norm'));
  if(fit.rank==3 && fit.condition_number<1e6)
    fitted=fit.predicted; mu=fit.coefficients(1);
    p=3;
  else
    weighted=rep_numeric('weighted_statistics',yy,w,struct());mu=weighted.mean; fitted=mu*ones(k,1); p=1;
  endif
  resid=yy-fitted; sumw=sum(w); sumw2=sum(w.^2); neff=(sumw^2)/max(sumw2,eps);
  dof=max(neff-p,1); v=(sum(w.*(resid.^2))/max(sumw,eps))*(neff/dof);
  sigma=sqrt(max(v,0));
endfunction

function [r,warnings]=compute_group_statistics(g,traces)
  warnings={}; Y=g.Y; n=columns(Y); nx=rows(Y);
  row=rep_numeric('matrix_statistics',Y,struct('dimension',2));y_mean=row.mean;y_median=row.median;
  if(n>=2), y_std=row.std_sample; else y_std=zeros(nx,1); endif
  y_sem=y_std./sqrt(max(1,n));
  source_ids=zeros(1,n);
  for k=1:n, source_ids(k)=traces(g.trace_indices(k)).source_index; endfor
  sources=unique(source_ids); ns=numel(sources);
  sigma_within=NaN(nx,1); sigma_between=NaN(nx,1); sigma_total=NaN(nx,1);
  identifiable=false;
  counts=zeros(1,ns);
  for si=1:ns, counts(si)=sum(source_ids==sources(si)); endfor
  N=sum(counts); dfw=N-ns;
  if(ns>=2 && dfw>0)
    coeff=(N-sum(counts.^2)/N)/(ns-1);
    if(coeff>0)
      identifiable=true;
      for xi=1:nx
        vals=Y(xi,:); grand=y_mean(xi); ssw=0; ssb=0;
        for si=1:ns
          sv=vals(source_ids==sources(si)); sm=rep_numeric('reduce_summary',sv).mean;
          ssw+=sum((sv-sm).^2); ssb+=numel(sv)*(sm-grand)^2;
        endfor
        msw=ssw/dfw; msb=ssb/(ns-1);
        tau2=max(0,(msb-msw)/coeff);
        sigma_within(xi)=sqrt(max(0,msw));
        sigma_between(xi)=sqrt(tau2);
        sigma_total(xi)=sqrt(msw+tau2);
      endfor
    endif
  endif
  if(!identifiable)
    warnings{end+1}=sprintf('Family %s: within-source / between-source variance decomposition is not identifiable (sources=%d, traces=%d, within df=%d)',g.family_label,ns,n,dfw);
  endif
  r=struct('family_value',g.family_value,'family_label',g.family_label,'trace_indices',g.trace_indices, ...
           'x',g.grid,'Y',Y,'y_mean',y_mean,'y_median',y_median,'y_std',y_std,'y_sem',y_sem, ...
           'n',n,'n_sources',ns,'source_ids',source_ids,'sigma_within',sigma_within,'sigma_between',sigma_between,'sigma_total',sigma_total, ...
           'variance_components_identifiable',identifiable,'x_min',g.x_min,'x_max',g.x_max, ...
           'statistics_mode','labelled_traces_anova','replicate_count_known',true,'n_raw_points',sum([traces(g.trace_indices).original_points]),'local_n',[]);
endfunction

function fit_outputs=build_fit_outputs(results,traces,method,grid_points,center,primary_source_index)
  fit_outputs=struct([]);
  for gi=1:numel(results)
    r=results(gi);
    if(strcmp(center,'median')), yc=r.y_median; else yc=r.y_mean; endif
    ref_idx=NaN; ref_label=''; ref_path=''; ref_rep=NaN;
    if(strcmp(method,'uniform_grid') || strcmp(r.statistics_mode,'unlabelled_point_cloud'))
      xout=rep_numeric('uniform_grid',r.x_min,r.x_max,grid_points,struct('mode','count')).x;
      if(strcmp(r.statistics_mode,'unlabelled_point_cloud') && strcmp(method,'reference_grid'))
        ref_label='unlabelled-cloud fallback: fixed uniform grid';
      endif
    else
      candidates=r.trace_indices;
      if(isfinite(primary_source_index))
        primary=[];
        for ti=candidates
          if(traces(ti).source_index==primary_source_index), primary(end+1)=ti; endif
        endfor
        if(!isempty(primary)), candidates=primary; endif
      endif
      % trace_indices are deterministic: source order, then detected replicate order.
      ref_idx=candidates(1);
      rt=traces(ref_idx);
      ref_label=rt.source_label; ref_path=rt.source_path; ref_rep=rt.replicate_index;
      xout=rt.x(rt.x>=r.x_min & rt.x<=r.x_max);
      xout=sort(unique(xout(:)));
      tol=1e-12*max([1,abs(r.x_min),abs(r.x_max)]);
      if(isempty(xout) || abs(xout(1)-r.x_min)>tol), xout=[r.x_min;xout]; endif
      if(abs(xout(end)-r.x_max)>tol), xout=[xout;r.x_max]; endif
    endif
    if(any(xout<r.x_min) || any(xout>r.x_max))
      error('curve.replicate_analysis: fit-output grid escaped valid consensus domain for family %s',r.family_label);
    endif
    yout=rep_numeric('interpolate',r.x,yc,xout,struct('method','linear')).yq;
    if(any(!isfinite(yout)))
      error('curve.replicate_analysis: fit-output interpolation produced non-finite values for family %s',r.family_label);
    endif
    fo=struct('family_value',r.family_value,'family_label',r.family_label,'x',xout(:),'y',yout(:), ...
              'x_min',r.x_min,'x_max',r.x_max,'method',method,'reference_trace_index',ref_idx, ...
              'reference_source_label',ref_label,'reference_source_path',ref_path,'reference_replicate_index',ref_rep);
    fit_outputs=append_struct(fit_outputs,fo);
  endfor
endfunction

function write_consensus(path,fit_outputs,x_name,family_name,y_name,has_family)
  fid=fopen(path,'w'); if(fid<0), error('curve.replicate_analysis: cannot write %s',path); endif
  unwind_protect
    if(has_family), fprintf(fid,'%s,%s,%s\n',csv_escape(x_name),csv_escape(family_name),csv_escape(y_name));
    else fprintf(fid,'%s,%s\n',csv_escape(x_name),csv_escape(y_name)); endif
    for gi=1:numel(fit_outputs)
      f=fit_outputs(gi);
      for i=1:numel(f.x)
        if(has_family), fprintf(fid,'%.17g,%.17g,%.17g\n',f.x(i),f.family_value,f.y(i));
        else fprintf(fid,'%.17g,%.17g\n',f.x(i),f.y(i)); endif
      endfor
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_uncertainty_profile(path,results,x_name,family_name,has_family)
  fid=fopen(path,'w'); if(fid<0), error('curve.replicate_analysis: cannot write %s',path); endif
  unwind_protect
    if(has_family), fprintf(fid,'%s,%s,y_mean,y_median,y_std,y_sem,n,n_sources,sigma_within,sigma_between,sigma_total,statistics_mode,n_raw_points\n',csv_escape(x_name),csv_escape(family_name));
    else fprintf(fid,'%s,y_mean,y_median,y_std,y_sem,n,n_sources,sigma_within,sigma_between,sigma_total,statistics_mode,n_raw_points\n',csv_escape(x_name)); endif
    for gi=1:numel(results)
      r=results(gi);
      for i=1:numel(r.x)
        if(has_family), fprintf(fid,'%.17g,%.17g,',r.x(i),r.family_value); else fprintf(fid,'%.17g,',r.x(i)); endif
        fprintf(fid,'%.17g,%.17g,',r.y_mean(i),r.y_median(i));
        write_csv_number(fid,r.y_std(i)); fprintf(fid,',');
        write_csv_number(fid,r.y_sem(i)); fprintf(fid,',%d,%d,',r.n,r.n_sources);
        write_csv_number(fid,r.sigma_within(i)); fprintf(fid,',');
        write_csv_number(fid,r.sigma_between(i)); fprintf(fid,',');
        write_csv_number(fid,r.sigma_total(i));
        fprintf(fid,',%s,%d\n',csv_escape(r.statistics_mode),r.n_raw_points);
      endfor
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_replicate_statistics(path,traces,has_family)
  fid=fopen(path,'w'); if(fid<0), error('curve.replicate_analysis: cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'source,source_path,family,replicate_id,replicate_index,n_points,x_min,x_max,y_mean,y_std,original_points,duplicates_collapsed,direction,representation\n');
    for i=1:numel(traces)
      t=traces(i); s=rep_numeric('statistics',t.y(:),struct());
      if(numel(t.y)>=2), ys=s.std_sample; else ys=0; endif
      fprintf(fid,'%s,%s,%s,%s,%d,%d,%.17g,%.17g,%.17g,%.17g,%d,%d,%s,%s\n', ...
              csv_escape(t.source_label),csv_escape(t.source_path),csv_escape(family_display(t.family_value,has_family)),csv_escape(t.replicate_id), ...
              t.replicate_index,numel(t.x),min(t.x),max(t.x),s.mean,ys,t.original_points,t.duplicates_collapsed,csv_escape(t.direction),csv_escape(t.representation));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_source_statistics(path,results,traces,has_family)
  fid=fopen(path,'w'); if(fid<0), error('curve.replicate_analysis: cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'source,family,n_replicates,n_points,n_grid,mean_bias,rms_deviation,max_abs_deviation,statistics_mode\n');
    for gi=1:numel(results)
      r=results(gi); srcs=unique(r.source_ids);
      for si=1:numel(srcs)
        sid=srcs(si); cols=find(r.source_ids==sid); sm=rep_numeric('reduce_summary',r.Y(:,cols),struct('dimension',2)).mean; d=sm-r.y_mean;
        label=''; npoints=0;
        for ti=r.trace_indices
          if(traces(ti).source_index==sid), label=traces(ti).source_label; npoints+=traces(ti).original_points; endif
        endfor
        fprintf(fid,'%s,%s,',csv_escape(label),csv_escape(family_display(r.family_value,has_family)));
        if(r.replicate_count_known), fprintf(fid,'%d',numel(cols)); endif
        bias=rep_numeric('reduce_summary',d(:),struct()).mean;deviation=rep_numeric('statistics',d(:),struct()).rms;
        fprintf(fid,',%d,%d,%.17g,%.17g,%.17g,%s\n',npoints,numel(r.x),bias,deviation,max(abs(d)),csv_escape(r.statistics_mode));
      endfor
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_summary(path,source_dataset_ids,source_labels,traces,results,warnings,x_name,family_name,y_name,replicate_name,has_family,replicate_handling,replicate_origin,segmentation_method,min_trace_points,reset_step_factor,reset_span_fraction,common_grid_method,grid_points,interpolation_method,consensus_center,fit_output_grid,fit_output_grid_points,fit_outputs,primary_dataset_id)
  fid=fopen(path,'w'); if(fid<0), error('curve.replicate_analysis: cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'GX-TXT Replicate Curve Analysis\n');
    fprintf(fid,'Module: curve.replicate_analysis\n');
    fprintf(fid,'Module version: 15.2\n');
    fprintf(fid,'Scientific scope: replicated curves -> statistical characterization -> consensus + uncertainty\n');
    fprintf(fid,'Physical-model fitting: not performed\n\n');
    fprintf(fid,'Sources: %d\n',numel(source_dataset_ids));
    for i=1:numel(source_dataset_ids), fprintf(fid,'  %d. %s = Dataset %s\n',i,source_labels{i},source_dataset_ids{i}); endfor
    fprintf(fid,'\nInput interpretation:\n');
    fprintf(fid,'  replicate handling = %s\n',replicate_handling);
    if(!isempty(replicate_name))
      fprintf(fid,'  curve/replicate identifier = %s (%s)\n',replicate_name,replicate_origin);
      fprintf(fid,'  interpretation = explicit repeated curves; CSV row order ignored\n');
    else
      fprintf(fid,'  curve/replicate identifier = <none>\n');
      if(strcmp(replicate_handling,'legacy_ordered_rows'))
        fprintf(fid,'  interpretation = legacy ordered rows; row order is meaningful\n');
      elseif(strcmp(replicate_handling,'automatic'))
        fprintf(fid,'  interpretation = unlabelled repeated-point clouds; CSV row order ignored\n');
        fprintf(fid,'  discrete replicate count = unknown and intentionally NOT inferred from point density\n');
        fprintf(fid,'  rationale = sampling density and number of repeat digitizations are different quantities\n');
      else
        fprintf(fid,'  interpretation = one curve per source/family\n');
      endif
    endif
    fprintf(fid,'\nBindings:\n  x = %s\n  y = %s\n',x_name,y_name);
    if(has_family), fprintf(fid,'  family = %s\n',family_name); else fprintf(fid,'  family = <absent>\n'); endif
    if(strcmp(replicate_origin,'explicit binding')), fprintf(fid,'  replicate = %s\n',replicate_name); else fprintf(fid,'  replicate = <automatic / not required>\n'); endif
    fprintf(fid,'\nMethods:\n');
    fprintf(fid,'  replicate grouping engine = %s\n',segmentation_method);
    fprintf(fid,'  CSV row order = %s\n',row_order_text(replicate_name,segmentation_method));
    fprintf(fid,'  minimum trace/cloud points = %d\n',min_trace_points);
    if(strcmp(segmentation_method,'x_reset_legacy') || strcmp(segmentation_method,'contiguous_only_legacy'))
      fprintf(fid,'  legacy reset threshold = max(%.6g * typical |dX|, %.6g * current X span)\n',reset_step_factor,reset_span_fraction);
    endif
    fprintf(fid,'  statistical common grid = %s\n',common_grid_method);
    if(strcmp(common_grid_method,'linspace')), fprintf(fid,'  statistical grid points = %d\n',grid_points); endif
    fprintf(fid,'  fit-output grid requested = %s\n',fit_output_grid);
    if(strcmp(segmentation_method,'unlabelled_point_cloud') && strcmp(fit_output_grid,'reference_grid'))
      fprintf(fid,'  fit-output grid effective = uniform_grid (%d points); no individual reference trace exists in an unlabelled cloud\n',fit_output_grid_points);
    elseif(strcmp(fit_output_grid,'uniform_grid'))
      fprintf(fid,'  fit-output grid points = %d per family/group\n',fit_output_grid_points);
    else
      fprintf(fid,'  preferred reference source = %s\n',primary_dataset_id);
      fprintf(fid,'  reference fallback = lowest available source index, then lowest replicate index\n');
    endif
    fprintf(fid,'  interpolation = %s; no extrapolation outside the intersection of source/trace domains\n',interpolation_method);
    fprintf(fid,'  consensus center for fit-ready CSV = %s\n',consensus_center);
    fprintf(fid,'  replication count / raw point count does not determine fit-output point count\n');
    if(strcmp(segmentation_method,'unlabelled_point_cloud'))
      fprintf(fid,'  source consensus = local linear regression on each source/family point cloud\n');
      fprintf(fid,'  sigma_within = RMS local residual dispersion across sources\n');
      fprintf(fid,'  sigma_between = sample SD of source consensus predictions\n');
      fprintf(fid,'  sigma_total = sqrt(sigma_within^2 + sigma_between^2)\n');
      fprintf(fid,'  y_std = sigma_total\n');
      fprintf(fid,'  y_sem = unavailable because independent replicate count is not encoded\n');
    else
      fprintf(fid,'  y_std = sample standard deviation across interpolated traces\n');
      fprintf(fid,'  y_sem = y_std / sqrt(n)\n');
      fprintf(fid,'  variance components = one-way random-effects ANOVA by source with unequal-replicate correction\n');
      fprintf(fid,'  sigma_within = sqrt(MS_within) when identifiable\n');
      fprintf(fid,'  sigma_between = sqrt(max(0,(MS_between-MS_within)/n0)) when identifiable\n');
      fprintf(fid,'  sigma_total = sqrt(sigma_within^2 + sigma_between^2) when identifiable\n');
    endif
    fprintf(fid,'  independent sigma_x = not estimated from final CSV coordinates alone\n\n');
    if(strcmp(segmentation_method,'unlabelled_point_cloud'))
      fprintf(fid,'Accepted source/family point clouds: %d\n',numel(traces));
    else
      fprintf(fid,'Accepted traces: %d\n',numel(traces));
    endif
    for gi=1:numel(results)
      r=results(gi); f=fit_outputs(gi);
      fprintf(fid,'\nGroup family=%s\n',r.family_label);
      fprintf(fid,'  statistics mode = %s\n',r.statistics_mode);
      if(r.replicate_count_known), fprintf(fid,'  traces = %d\n',r.n); else fprintf(fid,'  discrete replicate count = unknown\n'); endif
      fprintf(fid,'  raw digitized points = %d\n  sources = %d\n  common X domain = %.17g .. %.17g\n  statistical grid points = %d\n  fit-output points = %d\n', ...
              r.n_raw_points,r.n_sources,r.x_min,r.x_max,numel(r.x),numel(f.x));
      if(strcmp(fit_output_grid,'reference_grid'))
        if(strcmp(r.statistics_mode,'unlabelled_point_cloud'))
          fprintf(fid,'  fit reference = unavailable (unlabelled cloud); fixed uniform fallback used\n');
        else
          fprintf(fid,'  fit reference source = %s\n  fit reference replicate = %d\n',f.reference_source_label,f.reference_replicate_index);
        endif
      endif
      fprintf(fid,'  within/between identifiable = %s\n',bool_text(r.variance_components_identifiable));
      valid_std=r.y_std(isfinite(r.y_std));
      if(isempty(valid_std)),mean_std=NaN;max_std=NaN;
      else mean_std=rep_numeric('reduce_summary',valid_std,struct()).mean;max_std=max(valid_std);endif
      fprintf(fid,'  mean(y_std) = %.12g\n  max(y_std) = %.12g\n',mean_std,max_std);
      if(r.variance_components_identifiable)
        fprintf(fid,'  RMS(sigma_within) = %.12g\n  RMS(sigma_between) = %.12g\n  RMS(sigma_total) = %.12g\n', ...
                finite_rms(r.sigma_within),finite_rms(r.sigma_between),finite_rms(r.sigma_total));
      endif
      srcs=unique(r.source_ids);
      for si=1:numel(srcs)
        sid=srcs(si); label=''; npoints=0; nrep=0;
        for ti=r.trace_indices
          if(traces(ti).source_index==sid), label=traces(ti).source_label; npoints+=traces(ti).original_points; nrep++; endif
        endfor
        if(r.replicate_count_known)
          fprintf(fid,'  source %s replicates = %d; points = %d\n',label,nrep,npoints);
        else
          fprintf(fid,'  source %s replicate count = unknown; points = %d\n',label,npoints);
        endif
      endfor
    endfor
    fprintf(fid,'\nWarnings/notes: %d\n',numel(warnings));
    for i=1:numel(warnings), fprintf(fid,'  - %s\n',warnings{i}); endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function r=finite_rms(v)
  v=v(isfinite(v)); if(isempty(v)), r=NaN; else r=rep_numeric('statistics',v,struct()).rms; endif
endfunction

function write_csv_number(fid,v)
  if(isfinite(v)), fprintf(fid,'%.17g',v); endif
endfunction

function s=family_display(v,has_family)
  if(has_family), s=sprintf('%.17g',v); else s='all'; endif
endfunction

function s=row_order_text(replicate_name,segmentation_method)
  if(!isempty(replicate_name) || any(strcmp(segmentation_method,{'unordered_explicit','unlabelled_point_cloud','unordered_single','unordered_auto'})))
    s='ignored / non-semantic';
  else
    s='significant only because an explicit legacy mode was selected';
  endif
endfunction

function k=family_key(v,has_family)
  if(has_family), k=sprintf('%.17g',v); else k='__all__'; endif
endfunction

function b=same_family(a,bv,has_family)
  if(!has_family), b=true; else b=(a==bv); endif
endfunction

function arr=append_struct(arr,item)
  if(isempty(arr)), arr=item; else arr(end+1)=item; endif
endfunction

function s=csv_escape(s)
  if(!ischar(s)), s=num2str(s); endif
  if(!isempty(strfind(s,',')) || !isempty(strfind(s,'"')) || !isempty(strfind(s,sprintf('\n'))))
    s=strrep(s,'"','""'); s=['"' s '"'];
  endif
endfunction

function v=parse_positive_int(s,def,minv), v=round(str2double(s)); if(!isfinite(v)||v<minv),v=def;endif; endfunction
function v=parse_positive_num(s,def), v=str2double(s); if(!isfinite(v)||v<=0),v=def;endif; endfunction
function v=parse_fraction(s,def), v=str2double(s); if(!isfinite(v)||v<=0||v>1),v=def;endif; endfunction
function b=parse_bool(s,def), s=lower(strtrim(s)); if(any(strcmp(s,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(s,{'0','false','no','off'}))),b=false;else b=def;endif; endfunction
function s=bool_text(b), if(b),s='yes';else s='no';endif; endfunction

function v=arg_value(args,key,def)
  v=def; for k=1:numel(args)-1, if(strcmp(args{k},key)),v=args{k+1};return;endif; endfor
endfunction

function out=rep_numeric(operation,varargin)
  persistent fn;
  if(strcmp(operation,'function')),out=fn;return;endif
  if(strcmp(operation,'bind'))
    cfg=varargin{1};prefix='public_api.NUMERIC_API_v1.';
    provider=strtrim(ini_get(cfg,[prefix 'module_id'],''));version=strtrim(ini_get(cfg,[prefix 'api_version'],''));
    entry=strtrim(ini_get(cfg,[prefix 'octave_entrypoint'],''));candidate=strtrim(ini_get(cfg,[prefix 'octave_function'],''));
    caps=strsplit(strrep(ini_get(cfg,[prefix 'capabilities'],''),',',';'),';');
    if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(entry)||exist(entry,'file')!=2||isempty(candidate))
      error('curve.replicate_analysis: public NUMERIC_API_v1 runtime binding is unavailable');
    endif
    for required={'interpolation','uniform_grid','descriptive_statistics','matrix_statistics','linear_reductions','linear_least_squares'}
      if(!any(strcmp(caps,required{1}))),error('curve.replicate_analysis: numeric capability missing: %s',required{1});endif
    endfor
    addpath(fileparts(entry));if(exist(candidate,'file')!=2),error('curve.replicate_analysis: numeric entrypoint is unavailable');endif
    fn=candidate;out=[];return;
  endif
  if(isempty(fn)),error('curve.replicate_analysis: numeric binding was not initialized');endif
  out=feval(fn,operation,varargin{:});
endfunction

function d=read_ini(path)
  d=struct(); sec=''; fid=fopen(path,'r'); if(fid<0), error('curve.replicate_analysis: cannot open INI: %s',path); endif
  unwind_protect
    while(true)
      line=fgetl(fid); if(!ischar(line)),break;endif
      line=strtrim(line); if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif
      tok=regexp(line,'^\[(.+)\]$','tokens','once'); if(!isempty(tok)),sec=tok{1};continue;endif
      eq=find(line=='=',1); if(isempty(eq)),continue;endif
      key=strtrim(line(1:eq-1)); val=line(eq+1:end); d.(make_key([sec '.' key]))=ini_unescape(val);
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function s=ini_unescape(s),s=strrep(s,'\\n',sprintf('\n'));s=strrep(s,'\\r',sprintf('\r'));s=strrep(s,'\\\\','\\');endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction

function progress_start_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_start','file')!=2),return;endif
  try if(strcmp(mode,'determinate')),gxtxt_progress_start(stage,message,mode,total);else gxtxt_progress_start(stage,message,mode);endif; catch; end_try_catch
endfunction
function progress_stage_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_stage','file')!=2),return;endif
  try if(strcmp(mode,'determinate')),gxtxt_progress_stage(stage,message,mode,total);else gxtxt_progress_stage(stage,message,mode);endif; catch; end_try_catch
endfunction
function progress_update_safe(current,total,stage,message)
  if(exist('gxtxt_progress_update','file')!=2||total<=0),return;endif
  try gxtxt_progress_update(current,total,stage,message); catch; end_try_catch
endfunction
function progress_complete_safe(stage,message)
  if(exist('gxtxt_progress_complete','file')!=2),return;endif
  try gxtxt_progress_complete(stage,message); catch; end_try_catch
endfunction
function progress_fail_safe(stage,message)
  if(exist('gxtxt_progress_fail','file')!=2),return;endif
  try gxtxt_progress_fail(stage,message); catch; end_try_catch
endfunction
