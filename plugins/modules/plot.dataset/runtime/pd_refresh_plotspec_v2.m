function P=pd_refresh_plotspec_v2(P,cfg,graph)
% Refresh presentation-only PlotSpec v2 state on a prepared 2D cache.
% Auxiliary binding changes are data-affecting and must already exist in the
% cache; otherwise the caller must run analysis again instead of rerendering.
% SPDX-License-Identifier: GPL-3.0-or-later
  V=pd_plotspec_v2(cfg,graph);P.plotspec_v2=V;
  for k=1:numel(P.series),P.series(k).presentation=struct();endfor
  if(!V.enabled),return;endif
  if(!strcmp(P.mode,'graph_series')),error('plot.dataset: PlotSpec v2 requires Graph Series mode');endif
  for k=1:numel(P.series)
    S=P.series(k);
    for j=1:numel(V.series)
      Q=V.series(j);if(!strcmp(Q.id,S.series_id)),continue;endif
      qx='';qy='';if(isfield(S.x_meta,'variable_id')),qx=S.x_meta.variable_id;endif;if(isfield(S.meta,'variable_id')),qy=S.meta.variable_id;endif
      if(!strcmp(Q.dataset_id,S.dataset_id)||!strcmp(Q.x_variable_id,qx)||!strcmp(Q.y_variable_id,qy)||!strcmp(Q.axis,S.axis))
        error('plot.dataset: PlotSpec v2 series %s is stale relative to prepared Graph Series',S.series_id);
      endif
      need=aux_ids(Q);have={};if(isfield(S.data,'aux_ids')),have=S.data.aux_ids;endif
      for a=1:numel(need),if(isempty(find(strcmp(have,need{a}),1))),error('plot.dataset: PlotSpec v2 auxiliary binding changed for series %s; run the module again before rerendering',S.series_id);endif;endfor
      optional=pd_uncertainty_aux_ids(Q,S.data);
      prepared_optional={};if(isfield(S.data,'uncertainty_variable_ids')),prepared_optional=S.data.uncertainty_variable_ids;endif
      if(!isequal(sort(optional(:)),sort(prepared_optional(:))))
        error('plot.dataset: uncertainty preparation changed for series %s; recalculate before rerendering (the saved cache is preserved)',S.series_id);
      endif
      P.series(k).presentation=Q;break;
    endfor
  endfor
endfunction
function ids=aux_ids(Q)
  ids={};
  for name={'x_error','y_error'}
    f=name{1};if(!isfield(Q,f)),continue;endif;E=Q.(f);mode='none';if(isfield(E,'mode')),mode=lower(strtrim(E.mode));endif
    if(strcmp(mode,'symmetric')&&isfield(E,'variable_id')),ids{end+1}=E.variable_id;elseif(strcmp(mode,'asymmetric')),if(isfield(E,'lower_variable_id')),ids{end+1}=E.lower_variable_id;endif;if(isfield(E,'upper_variable_id')),ids{end+1}=E.upper_variable_id;endif;endif
  endfor
  if(isfield(Q,'band')&&!isempty(fieldnames(Q.band))),if(isfield(Q.band,'lower_variable_id')),ids{end+1}=Q.band.lower_variable_id;endif;if(isfield(Q.band,'upper_variable_id')),ids{end+1}=Q.band.upper_variable_id;endif;endif
  if(isfield(Q,'bar_bounds')&&!isempty(fieldnames(Q.bar_bounds))),if(isfield(Q.bar_bounds,'lower_variable_id')),ids{end+1}=Q.bar_bounds.lower_variable_id;endif;if(isfield(Q.bar_bounds,'upper_variable_id')),ids{end+1}=Q.bar_bounds.upper_variable_id;endif;endif
  ids=unique_ids(ids);
endfunction
function out=unique_ids(ids),out={};for i=1:numel(ids),q=strtrim(ids{i});if(!isempty(q)&&isempty(find(strcmp(out,q),1))),out{end+1}=q;endif;endfor;endfunction
