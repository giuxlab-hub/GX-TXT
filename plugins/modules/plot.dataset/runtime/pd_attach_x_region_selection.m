function P=pd_attach_x_region_selection(P,cfg,graph)
% Interpret the framework-owned X range against every prepared active Series.
% This does not create a dataset selection, filter a dataset, or alter points.
% SPDX-License-Identifier: GPL-3.0-or-later
  R=gxtxt_plot_region_from_runtime(cfg,graph);
  info=struct('enabled',false,'x_min',NaN,'x_max',NaN,'display_unit','','series',struct([]));
  if(!R.enabled||!isfinite(R.x_min)||!isfinite(R.x_max)),P.region_selection=info;return;endif
  lo=min(R.x_min,R.x_max);hi=max(R.x_min,R.x_max);xdu=pd_x_display_unit(P,cfg,graph);
  rows=repmat(struct('series_id','','dataset_id','','x_variable_id','','selected_display_points',0,'display_points',0),1,numel(P.series));
  for k=1:numel(P.series)
    S=P.series(k);[xd,~,~]=pd_convert_display(S.data.x,S.x_meta.unit,xdu,'X');mask=isfinite(xd)&xd>=lo&xd<=hi;
    xid='';if(isfield(S.x_meta,'variable_id')),xid=S.x_meta.variable_id;endif
    rows(k)=struct('series_id',S.series_id,'dataset_id',S.dataset_id,'x_variable_id',xid,'selected_display_points',sum(mask),'display_points',numel(xd));
  endfor
  info=struct('enabled',true,'x_min',lo,'x_max',hi,'display_unit',xdu,'series',rows);P.region_selection=info;
endfunction
