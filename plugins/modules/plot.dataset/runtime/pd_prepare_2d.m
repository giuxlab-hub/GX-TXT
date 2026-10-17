function P=pd_prepare_2d(info,cfg,opts,graph,oldP)
% Prepare one 2D graph. Active Graph Series are the only scientific binding
% authority. There is no legacy X/Y/Y-right/family fallback.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4||isempty(graph)),graph='plot.dataset.xy';endif
  if(nargin<5),oldP=struct();endif
  variant=pd_variant_for_graph(cfg,graph);V=pd_plotspec_v2(cfg,graph);G=pd_graph_series_defs(cfg,graph);session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('plot.dataset: runtime.session is required for dataset-native 2-D plotting');endif
  if(isempty(G))
    error('plot.dataset: graph %s has no active Graph Series; 2-D plotting requires Graph Series',graph);
  endif
  validate_x_compatibility(G);
  n=numel(G);graph_budget=pd_2d_display_budget(opts.target_points);per_series=max(200,round(graph_budget/max(1,n)));x_window=pd_2d_preparation_window(cfg,graph,V,G);heterogeneous_x=!shared_x_binding(G);
  grouped={};
  if(!(isstruct(oldP)&&isfield(oldP,'series'))&&family_group_batch_eligible(G,V,x_window,heterogeneous_x))
    grouped=pd_prepare_2d_family_grouped(session,G,opts.reduction_mode,per_series,opts.auto_reduce_threshold,opts.chunk_rows);
  endif
  batched=cell(1,n);
  if(isempty(grouped)&&!(isstruct(oldP)&&isfield(oldP,'series'))&&!(isstruct(x_window)&&isfield(x_window,'enabled')&&x_window.enabled))
    visited=false(1,n);
    for seed=1:n
      if(visited(seed)||isempty(G(seed).row_filters)),continue;endif
      members=find(arrayfun(@(item) strcmp(item.dataset_id,G(seed).dataset_id)&&!isempty(item.row_filters),G));
      visited(members)=true;
      if(numel(members)<2),continue;endif
      auxsets=cell(1,numel(members));modes=cell(1,numel(members));optionalsets=cell(1,numel(members));
      for q=1:numel(members)
        item=G(members(q));pres=plotspec_series(V,item);aux=plotspec_aux_ids(pres);
        if(isfield(item,'secondary_variable_id')&&!isempty(strtrim(item.secondary_variable_id))),aux{end+1}=item.secondary_variable_id;endif
        if(isfield(item,'ordering_variable_id')&&!isempty(strtrim(item.ordering_variable_id))),aux{end+1}=item.ordering_variable_id;endif
        auxsets{q}=unique(aux,'stable');mode=opts.reduction_mode;
        optionalsets{q}=pd_uncertainty_aux_ids(pres,item);
        % Exact source adjacency cannot be inferred across decimated rows.
        if(isfield(pres,'source_row_continuity')&&pres.source_row_continuity),mode='none';endif
        if(isfield(item,'source_row_ordinals')&&!isempty(item.source_row_ordinals)),mode='none';endif
        if(isfield(item,'ordering_variable_id')&&!isempty(strtrim(item.ordering_variable_id))),mode='none';endif
        if(isfield(pres,'family_variable_id')&&!isempty(strtrim(pres.family_variable_id))),mode='none';endif
        if(isfield(pres,'kind')&&any(strcmp(lower(strtrim(pres.kind)),{'histogram','box_whisker'}))),mode='none';endif
        modes{q}=mode;
      endfor
      values=pd_prepare_2d_filtered_batch(session,G(members),auxsets,modes,per_series,opts.auto_reduce_threshold,opts.chunk_rows,optionalsets);
      for q=1:numel(members),batched{members(q)}=values{q};endfor
    endfor
  endif
  series=repmat(struct('name','','axis','left','panel_id','main','label','','series_id','','dataset_id','','meta',struct(),'x_name','','x_meta',struct(),'data',struct(),'presentation',struct(),'prep_fingerprint',''),1,n);
  for k=1:n
    pres=plotspec_series(V,G(k));aux=plotspec_aux_ids(pres);
    if(isfield(G,'secondary_variable_id')&&!isempty(strtrim(G(k).secondary_variable_id))),aux{end+1}=G(k).secondary_variable_id;endif
    if(isfield(G,'ordering_variable_id')&&!isempty(strtrim(G(k).ordering_variable_id))),aux{end+1}=G(k).ordering_variable_id;endif
    aux=unique(aux,'stable');
    optional_ids=pd_uncertainty_aux_ids(pres,G(k));
    if(!isempty(G(k).style_color))
      if(!isfield(pres,'style')||isempty(pres.style)),pres.style=struct();endif
      if(!isfield(pres.style,'color')||isempty(pres.style.color)),pres.style.color=G(k).style_color;endif
      if(!isfield(pres.style,'line_style')||isempty(pres.style.line_style)),pres.style.line_style=G(k).style_line_style;endif
    endif
    reduction=opts.reduction_mode;
    if(isfield(pres,'source_row_continuity')&&pres.source_row_continuity),reduction='none';endif
    if(isfield(G,'source_row_ordinals')&&!isempty(G(k).source_row_ordinals)),reduction='none';endif
    if(isfield(G,'ordering_variable_id')&&!isempty(strtrim(G(k).ordering_variable_id))),reduction='none';endif
    if(isfield(pres,'family_variable_id')&&!isempty(strtrim(pres.family_variable_id))),reduction='none';endif
    if(isfield(pres,'kind')&&any(strcmp(lower(strtrim(pres.kind)),{'histogram','box_whisker'})))
      % Distribution plots are statistical transformations of the complete
      % finite sample. Display decimation would change bins or quartiles.
      reduction='none';
    endif
    seriesFp=pd_series_prep_fingerprint(session,G(k),aux,reduction,per_series,opts.auto_reduce_threshold,x_window,pres);
    reused=false;
    if(isstruct(oldP)&&isfield(oldP,'series'))
      for oldIndex=1:numel(oldP.series)
        old=oldP.series(oldIndex);
        if(strcmp(old.series_id,G(k).series_id)&&isfield(old,'prep_fingerprint')&&strcmp(old.prep_fingerprint,seriesFp))
          d=old.data;xm=old.x_meta;reused=true;break;
        endif
      endfor
    endif
    use_path_compat=heterogeneous_x&&explicit_csv_compat_source(G(k))&&isempty(G(k).row_filters);
    if(reused)
      % Prepared coordinates and source-row identities are already normalized.
    elseif(!isempty(grouped))
      d=grouped{k};
    elseif(!isempty(batched{k}))
      d=batched{k};
    elseif(use_path_compat)
      if(isempty(aux))
        d=pd_prepare_2d_series_path_compat(G(k).path,G(k).x_variable_id,G(k).y_variable_id,reduction,per_series,opts.auto_reduce_threshold,opts.chunk_rows,['graph_series_path_' G(k).series_id]);
      else
        d=pd_prepare_2d_series_v2_path_compat(G(k).path,G(k).x_variable_id,G(k).y_variable_id,aux,reduction,per_series,opts.auto_reduce_threshold,opts.chunk_rows,['graph_series_v2_path_' G(k).series_id],optional_ids);
      endif
      d.dataset_id=G(k).dataset_id;
    elseif(isempty(aux))
      d=pd_prepare_2d_series(session,G(k).dataset_id,G(k).x_variable_id,G(k).y_variable_id,reduction,per_series,opts.auto_reduce_threshold,opts.chunk_rows,['graph_series_' G(k).series_id],x_window,G(k).row_filters);
    else
      d=pd_prepare_2d_series_v2(session,G(k).dataset_id,G(k).x_variable_id,G(k).y_variable_id,aux,reduction,per_series,opts.auto_reduce_threshold,opts.chunk_rows,['graph_series_v2_' G(k).series_id],x_window,G(k).row_filters,optional_ids);
    endif
    if(!reused&&isfield(G,'source_row_ordinals')&&!isempty(G(k).source_row_ordinals))
      keep=ismember(d.source_row_indices,G(k).source_row_ordinals);
      d.filter_dropped_rows+=sum(!keep);d.valid_rows=sum(keep);d.display_rows=sum(keep);
      d.x=d.x(keep);d.y=d.y(keep);d.source_row_indices=d.source_row_indices(keep);
      for a=1:numel(d.aux_values),d.aux_values{a}=d.aux_values{a}(keep);endfor
      if(isfield(d,'uncertainty_run_ids')),for a=1:numel(d.uncertainty_run_ids),d.uncertainty_run_ids{a}=d.uncertainty_run_ids{a}(keep);endfor;endif
      if(isempty(d.x)),error('plot.dataset: exact source-row selection has no finite observations');endif
    endif
    if(!reused&&isfield(G,'ordering_variable_id')&&!isempty(strtrim(G(k).ordering_variable_id)))
      order_id=G(k).ordering_variable_id;j=find(strcmp(d.aux_ids,order_id),1);
      if(isempty(j)),error('plot.dataset: ordering variable %s was not prepared',order_id);endif
      order_values=d.aux_values{j};
      if(!isnumeric(order_values)||any(!isfinite(order_values(:))))
        error('plot.dataset: ordering variable %s must contain finite numeric values',order_id);
      endif
      [~,order_index]=sortrows([double(order_values(:)),double(d.source_row_indices(:))],[1 2]);
      d.x=d.x(order_index);d.y=d.y(order_index);d.source_row_indices=d.source_row_indices(order_index);
      for a=1:numel(d.aux_values),d.aux_values{a}=d.aux_values{a}(order_index);endfor
      if(isfield(d,'uncertainty_run_ids')),for a=1:numel(d.uncertainty_run_ids),d.uncertainty_run_ids{a}=d.uncertainty_run_ids{a}(order_index);endfor;endif
      d.ordering_variable_id=order_id;
    endif
    if(isfield(G,'secondary_variable_id')),d.secondary_variable_id=G(k).secondary_variable_id;endif
    if(!reused),xm=series_meta(G(k),'x');[d,xm]=normalize_temporal_x(d,xm,G(k));endif
    ym=series_meta(G(k),'y');
    series(k)=struct('name',G(k).y_name,'axis',G(k).axis,'panel_id',series_panel_id(pres),'label',G(k).label,'series_id',G(k).series_id,'dataset_id',G(k).dataset_id,'meta',ym,'x_name',G(k).x_name,'x_meta',xm,'data',d,'presentation',pres,'prep_fingerprint',seriesFp);
  endfor
  % Physical unit compatibility is resolved at render time from captured CORE
  % Variable relations, including declared source overrides.
  P=struct('mode','graph_series','graph_id',graph,'variant_id',variant,'x_name',common_x_name(series),'x_meta',series(1).x_meta,'series',series,'target_points',graph_budget,'configured_target_points',opts.target_points,'preparation_window',x_window,'plotspec_v2',V);
endfunction

function yes=family_group_batch_eligible(G,V,x_window,heterogeneous_x)
  yes=false;
  if(numel(G)<2||heterogeneous_x||(isstruct(x_window)&&isfield(x_window,'enabled')&&x_window.enabled)),return;endif
  first=G(1);
  if(isfield(G,'source_row_ordinals')&&any(arrayfun(@(s) !isempty(s.source_row_ordinals),G))),return;endif
  if(isfield(G,'ordering_variable_id')&&!isempty(strtrim(first.ordering_variable_id))),return;endif
  if(numel(first.row_filters)!=1||!strcmp(first.row_filters{1}.predicate,'exact_equal')),return;endif
  group_id=first.row_filters{1}.filter_variable_id;dtype=first.row_filters{1}.dtype;
  values=cell(1,numel(G));
  for k=1:numel(G)
    item=G(k);
    if(!strcmp(item.dataset_id,first.dataset_id)||!strcmp(item.x_variable_id,first.x_variable_id)||!strcmp(item.y_variable_id,first.y_variable_id)),return;endif
    if(numel(item.row_filters)!=1||!strcmp(item.row_filters{1}.predicate,'exact_equal')||!strcmp(item.row_filters{1}.filter_variable_id,group_id)||!strcmp(item.row_filters{1}.dtype,dtype)),return;endif
    values{k}=item.row_filters{1}.value;
    pres=plotspec_series(V,item);
    if(isfield(pres,'source_row_continuity')&&pres.source_row_continuity),return;endif
    if(!isempty(plotspec_aux_ids(pres))),return;endif
    if(isfield(pres,'kind')&&any(strcmp(lower(strtrim(pres.kind)),{'histogram','box_whisker'}))),return;endif
  endfor
  if(numel(unique(values))!=numel(values)),return;endif
  yes=true;
endfunction

function pres=plotspec_series(V,G)
  pres=struct();if(!V.enabled),return;endif
  for i=1:numel(V.series)
    if(strcmp(V.series(i).id,G.series_id))
      s=V.series(i);
      % A persisted presentation is safe only while the authoritative Graph
      % Series binding still refers to the same dataset-scoped IDs and axis.
      if(!strcmp(s.dataset_id,G.dataset_id)||!strcmp(s.x_variable_id,G.x_variable_id)||!strcmp(s.y_variable_id,G.y_variable_id)||!strcmp(s.axis,G.axis))
        error('plot.dataset: PlotSpec v2 series %s is stale relative to Graph Series; reapply/sync the PlotSpec before rendering',G.series_id);
      endif
      pres=s;return;
    endif
  endfor
endfunction
function ids=plotspec_aux_ids(pres)
  ids={};if(isempty(fieldnames(pres))),return;endif
  for en={'x_error','y_error'}
    e=en{1};if(!isfield(pres,e)),continue;endif;E=pres.(e);mode=lower(strtrim(E.mode));
    if(strcmp(mode,'symmetric')&&!isempty(strtrim(E.variable_id))),ids{end+1}=E.variable_id;elseif(strcmp(mode,'asymmetric')),if(!isempty(strtrim(E.lower_variable_id))),ids{end+1}=E.lower_variable_id;endif;if(!isempty(strtrim(E.upper_variable_id))),ids{end+1}=E.upper_variable_id;endif;endif
  endfor
  if(isfield(pres,'band')&&!isempty(fieldnames(pres.band)))
    if(isfield(pres.band,'lower_variable_id')),ids{end+1}=pres.band.lower_variable_id;endif
    if(isfield(pres.band,'upper_variable_id')),ids{end+1}=pres.band.upper_variable_id;endif
  endif
  if(isfield(pres,'family_variable_id')&&!isempty(strtrim(pres.family_variable_id))),ids{end+1}=pres.family_variable_id;endif
  if(isfield(pres,'bar_bounds')&&!isempty(fieldnames(pres.bar_bounds)))
    if(isfield(pres.bar_bounds,'lower_variable_id')),ids{end+1}=pres.bar_bounds.lower_variable_id;endif
    if(isfield(pres.bar_bounds,'upper_variable_id')),ids{end+1}=pres.bar_bounds.upper_variable_id;endif
  endif
  out={};for i=1:numel(ids),q=strtrim(ids{i});if(!isempty(q)&&isempty(find(strcmp(out,q),1))),out{end+1}=q;endif;endfor;ids=out;
endfunction
function variant=pd_variant_for_graph(cfg,graph)
  g=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));v=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));
  if(!isempty(g)&&strcmp(g,graph)),variant=v;else variant='';endif
endfunction
function m=series_meta(G,which)
  m=struct('found',true,'source_id','graph_series','dataset_id',G.dataset_id,'variable_id',G.([which '_variable_id']),'name',G.([which '_name']),'unit',G.([which '_unit']),'semantic_role',G.([which '_semantic_role']),'value_kind',G.([which '_value_kind']),'value_format',G.([which '_value_format']),'time_reference',G.([which '_time_reference']),'time_origin',G.([which '_time_origin']));
endfunction

function [d,m]=normalize_temporal_x(d,m,G)
% Keep one prepared-coordinate contract for temporal X data: seconds.
% CORE typed readers normalize value_kind=elapsed_time/value_format=hms to
% seconds even when Graph Series still exposes the original declared source
% unit (for example h). Treat that semantic pair as seconds so presentation
% conversion is applied exactly once.
  role=lower(strtrim(G.x_semantic_role));kind=lower(strtrim(G.x_value_kind));fmt=lower(strtrim(G.x_value_format));
  temporal=any(strcmp(role,{'elapsed_time','absolute_time'}))||strcmp(kind,'elapsed_time');
  if(!temporal),return;endif
  declared=strtrim(G.x_unit);runtime_unit=declared;
  if(strcmp(kind,'elapsed_time')&&strcmp(fmt,'hms'))
    % Canonical Dataset API v2 and legacy typed Table Stream both expose the
    % public elapsed_time numeric base representation in seconds.
    runtime_unit='s';
  endif
  if(isempty(runtime_unit)),error('plot.dataset: temporal X %s has no unit metadata',G.x_name);endif
  try
    if(!strcmpi(runtime_unit,'s')),d.x=gxtxt_unit_convert(d.x,runtime_unit,'s');endif
  catch err
    error('plot.dataset: cannot normalize temporal X %s from %s to s: %s',G.x_name,runtime_unit,err.message);
  end_try_catch
  m.source_unit=declared;m.runtime_unit='s';m.unit='s';
endfunction

function validate_x_compatibility(G)
  if(numel(G)<2),return;endif
  b=G(1);
  for k=2:numel(G)
    q=G(k);
    if(!x_roles_compatible(b.x_semantic_role,q.x_semantic_role)),error('plot.dataset: X semantic roles are incompatible: %s vs %s',b.x_semantic_role,q.x_semantic_role);endif
    if(!pd_x_value_kinds_compatible(b.x_semantic_role,b.x_value_kind,q.x_semantic_role,q.x_value_kind)),error('plot.dataset: X value kinds are incompatible for semantic role %s: %s vs %s',shared_semantic_role(b,q),b.x_value_kind,q.x_value_kind);endif
    bt=strtrim(b.x_time_reference);qt=strtrim(q.x_time_reference);
    if(!isempty(bt)&&!isempty(qt)&&!strcmp(bt,qt)),error('plot.dataset: X time references are incompatible: %s vs %s',bt,qt);endif
    if(strcmp(bt,'absolute')&&strcmp(qt,'absolute')&&!isempty(strtrim(b.x_time_origin))&&!isempty(strtrim(q.x_time_origin))&&!strcmp(b.x_time_origin,q.x_time_origin)),error('plot.dataset: absolute-time series have different origins; align them explicitly before plotting');endif
    if(!strcmpi(strtrim(q.alignment_mode),'none')||!strcmpi(strtrim(b.alignment_mode),'none')),error('plot.dataset: Graph Series alignment_mode is declarative only; materialize/alignment must be performed before plotting');endif
  endfor
endfunction
function tf=x_roles_compatible(a,b)
  a=lower(strtrim(a));b=lower(strtrim(b));tf=isempty(a)||isempty(b)||strcmp(a,b);
  if(tf),return;endif
  % A detected-peak coordinate is a sparse sample of its source's
  % independent coordinate; the unit and value-kind checks still apply.
  coordinate_roles={'independent','peak_position'};
  tf=any(strcmp(coordinate_roles,a))&&any(strcmp(coordinate_roles,b));
endfunction
function role=shared_semantic_role(a,b),ar=strtrim(a.x_semantic_role);br=strtrim(b.x_semantic_role);if(!isempty(ar)&&strcmpi(ar,br)),role=ar;elseif(!isempty(ar)),role=ar;elseif(!isempty(br)),role=br;else role='(unspecified)';endif;endfunction
function n=common_x_name(series),n=series(1).x_name;for k=2:numel(series),if(!strcmp(series(k).x_name,n)),n='X';return;endif;endfor;endfunction
function id=series_panel_id(pres)
  id='main';if(isempty(fieldnames(pres))),return;endif
  if(isfield(pres,'panel_id'))
    q=strtrim(pres.panel_id);if(!isempty(q)),id=q;endif
  endif
endfunction

function tf=shared_x_binding(G)
  tf=true;if(numel(G)<2),return;endif
  ds=strtrim(G(1).dataset_id);xid=strtrim(G(1).x_variable_id);
  for k=2:numel(G),if(!strcmp(strtrim(G(k).dataset_id),ds)||!strcmp(strtrim(G(k).x_variable_id),xid)),tf=false;return;endif;endfor
endfunction
function tf=explicit_csv_compat_source(G)
  tf=false;p=strtrim(G.path);if(isempty(p)||exist(p,'file')!=2),return;endif
  [~,~,ext]=fileparts(p);tf=strcmpi(ext,'.csv');
endfunction
