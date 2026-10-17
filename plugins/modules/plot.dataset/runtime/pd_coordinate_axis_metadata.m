function pd_coordinate_axis_metadata(ax,which,meta,target)
% Preserve truthful inverse source mapping for region-selection consumers.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(isempty(ax)||!isstruct(meta)||!isfield(meta,'coordinate_context')),return;endif
  c=meta.coordinate_context;vid=meta.variable_id;
  plan=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_affine_plan',{c,vid,meta.unit,struct('mode','canonical','unit',target)});
  if(plan.affine)
    setappdata(ax,['gxtxt_' which '_display_to_source_scale'],1/plan.scale);
    setappdata(ax,['gxtxt_' which '_display_to_source_offset'],-plan.offset/plan.scale);
  else
    % Existing region selection stores affine source ranges. Never pretend a
    % nonlinear relation has a valid scalar inverse; display remains available.
    setappdata(ax,['gxtxt_' which '_transform'],'coordinate_nonlinear_v1');
  endif
  settings=c.variables.(vid);
  setappdata(ax,['gxtxt_' which '_coordinate_revision'],c.revision);
  setappdata(ax,['gxtxt_' which '_coordinate_view_factor'],settings.view_factor);
  setappdata(ax,['gxtxt_' which '_coordinate_view_pivot'],settings.view_pivot);
endfunction
