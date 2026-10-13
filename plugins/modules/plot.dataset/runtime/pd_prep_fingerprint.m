function fp=pd_prep_fingerprint(info,cfg,opts,kind,graph)
% Fingerprint data-preparation identity. For 2D, Graph Series are graph-scoped.
% SPDX-License-Identifier: GPL-3.0-or-later
  kind=lower(strtrim(kind));if(nargin<5),graph='';endif
  if(strcmp(kind,'2d'))
    if(isempty(graph)),graph='plot.dataset.xy';endif
    variant='';pg=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));if(strcmp(pg,graph)),variant=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));endif
    budget=pd_2d_display_budget(opts.target_points);p={'PLOT_DATASET_PREP_2D_V3_1_COMPAT',graph,variant,opts.reduction_mode,sprintf('%d',budget),sprintf('%d',opts.auto_reduce_threshold)};
    n=str2double(gxtxt_ini_get(cfg,'graph_series.count','0'));matched=0;
    for i=1:round(n)
      key=sprintf('graph_series.%d.',i);if(!strcmp(gxtxt_ini_get(cfg,[key 'graph_id'],''),graph)),continue;endif
      v=gxtxt_ini_get(cfg,[key 'variant_id'],'');if(!(isempty(v)&&isempty(variant))&&!strcmp(v,variant)),continue;endif
      en=strtrim(gxtxt_ini_get(cfg,[key 'enabled'],'1'));if(any(strcmpi(en,{'0','false','no','off'}))),continue;endif
      matched+=1;
      for field={'series_id','dataset_id','x_variable_id','y_variable_id','x_unit','y_unit','x_semantic_role','y_semantic_role','x_value_kind','y_value_kind','x_time_reference','x_time_origin','axis','label','order','alignment_mode','manual_offset_seconds'}
        p{end+1}=gxtxt_ini_get(cfg,[key field{1}],'');
      endfor
      for field={'family_variable_id','secondary_variable_id','ordering_variable_id'}
        p{end+1}=gxtxt_ini_get(cfg,[key field{1}],'');
      endfor
      filters=gxtxt_graph_series_filters_from_runtime(cfg,key);
      p{end+1}=sprintf('filter_count=%d',numel(filters));
      for fi=1:numel(filters)
        f=filters{fi};p{end+1}=f.filter_variable_id;p{end+1}=f.predicate;p{end+1}=f.dtype;
        for field={'value','lower','upper'}
          if(isfield(f,field{1})),p{end+1}=f.(field{1});endif
        endfor
        if(isfield(f,'values'))
          p{end+1}=sprintf('value_count=%d',numel(f.values));
          for vi=1:numel(f.values),p{end+1}=f.values{vi};endfor
        endif
      endfor
    endfor
    % PlotSpec v2 presentation is rerender-only.  The preparation cache key
    % changes only when a series actually requires auxiliary source columns
    % (error bars or uncertainty bands).  Merely creating/saving a PlotSpec
    % for line/marker/opacity presentation must not invalidate prepared data.
    V=pd_plotspec_v2(cfg,graph);G=pd_graph_series_defs(cfg,graph);W=pd_2d_preparation_window(cfg,graph,V,G);
    if(W.enabled),p{end+1}='x_window';p{end+1}=W.source;p{end+1}=sprintf('%.17g',W.x_min);p{end+1}=sprintf('%.17g',W.x_max);p{end+1}=W.display_unit;else p{end+1}='x_window=full';endif
    if(V.enabled)
      for vi=1:numel(V.series)
        Q=V.series(vi);aids=fp_aux_ids(Q);
        if(isfield(Q,'kind')&&any(strcmp(lower(strtrim(Q.kind)),{'histogram','box_whisker'})))
          % Distribution preparation is intentionally unreduced; distinguish
          % it from an ordinary trace cache prepared with display reduction.
          p{end+1}=['distribution_series=' Q.id];p{end+1}=lower(strtrim(Q.kind));
        endif
        if(!isempty(aids))
          p{end+1}=['aux_series=' Q.id];
          for ai=1:numel(aids),p{end+1}=aids{ai};endfor
        endif
      endfor
    endif
    if(matched==0),p{end+1}='NO_ACTIVE_GRAPH_SERIES';endif
  elseif(strcmp(kind,'3d'))
    p={'PLOT_DATASET_PREP_3D_V1',info.dataset_id,info.x,info.y,info.z,info.family,info.color,opts.reduction_mode,sprintf('%d',opts.target_points),sprintf('%d',opts.auto_reduce_threshold),lower(strtrim(gxtxt_ini_get(cfg,'plot.plot.dataset.xyz.plot_type','scatter3')))};
  else error('plot.dataset: invalid preparation fingerprint kind %s',kind);endif
  fp=gxtxt_render_cache_fingerprint(p);
endfunction

function ids=fp_aux_ids(Q)
  ids={};for name={'x_error','y_error'},f=name{1};if(!isfield(Q,f)),continue;endif;E=Q.(f);mode='none';if(isfield(E,'mode')),mode=lower(strtrim(E.mode));endif;if(strcmp(mode,'symmetric')&&isfield(E,'variable_id')),ids{end+1}=E.variable_id;elseif(strcmp(mode,'asymmetric')),if(isfield(E,'lower_variable_id')),ids{end+1}=E.lower_variable_id;endif;if(isfield(E,'upper_variable_id')),ids{end+1}=E.upper_variable_id;endif;endif;endfor
  if(isfield(Q,'band')&&!isempty(fieldnames(Q.band))),if(isfield(Q.band,'lower_variable_id')),ids{end+1}=Q.band.lower_variable_id;endif;if(isfield(Q.band,'upper_variable_id')),ids{end+1}=Q.band.upper_variable_id;endif;endif
  if(isfield(Q,'bar_bounds')&&!isempty(fieldnames(Q.bar_bounds))),if(isfield(Q.bar_bounds,'lower_variable_id')),ids{end+1}=Q.bar_bounds.lower_variable_id;endif;if(isfield(Q.bar_bounds,'upper_variable_id')),ids{end+1}=Q.bar_bounds.upper_variable_id;endif;endif
  out={};for i=1:numel(ids),q=strtrim(ids{i});if(!isempty(q)&&isempty(find(strcmp(out,q),1))),out{end+1}=q;endif;endfor;ids=out;
endfunction
