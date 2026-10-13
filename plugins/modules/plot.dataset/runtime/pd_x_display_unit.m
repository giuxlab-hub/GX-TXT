function xdu=pd_x_display_unit(P,cfg,graph)
% Resolve the exact shared X display unit used by the 2-D renderer.
% SPDX-License-Identifier: GPL-3.0-or-later
  series=P.series;n=numel(series);xvals=cell(1,n);xunits=cell(1,n);
  for k=1:n,xvals{k}=series(k).data.x;xunits{k}=series(k).x_meta.unit;endfor
  mode=gxtxt_plot_axis_unit_mode(cfg,graph,'x','auto');if(isempty(mode)||strcmpi(mode,'inherit')),mode='auto';endif
  declared=core_axis_state_declared_local(cfg,graph);enabled=core_axis_state_enabled_local(cfg,graph);
  if(declared)
    if(!enabled),mode='auto';endif
  elseif(isfield(P,'plotspec_v2')&&isfield(P.plotspec_v2,'enabled')&&P.plotspec_v2.enabled&&isfield(P.plotspec_v2,'axes')&&isfield(P.plotspec_v2.axes,'x'))
    a=P.plotspec_v2.axes.x;if(isfield(a,'display_unit')),q=strtrim(a.display_unit);if(!isempty(q)),mode=q;endif;endif
  endif
  [xdu,~]=pd_common_display_unit(xvals,xunits,mode,'X axis');
endfunction
function tf=core_axis_state_enabled_local(cfg,graph)
  tf=false;q=str2double(gxtxt_ini_get(cfg,['axis.' graph '.enabled'],'0'));if(isfinite(q)&&q!=0),tf=true;endif
endfunction
function tf=core_axis_state_declared_local(cfg,graph)
  tf=false;prefix=['axis.' graph '.'];if(!cfg_has_key_local(cfg,[prefix 'enabled'])),return;endif
  token_fields={'x_unit','y_unit','y2_unit','x_format','y_format','y2_format','xgrid','ygrid','align_ylabels'};
  for i=1:numel(token_fields),key=[prefix token_fields{i}];if(!cfg_has_key_local(cfg,key)),continue;endif;v=strtrim(gxtxt_ini_get(cfg,key,'inherit'));if(isempty(v)||!strcmpi(v,'inherit')),tf=true;return;endif;endfor
  value_fields={'x_min','x_max','x_step','y_min','y_max','y_step','y2_min','y2_max','y2_step','grid_color','ylabel_x'};
  for i=1:numel(value_fields),key=[prefix value_fields{i}];if(cfg_has_key_local(cfg,key)&&!isempty(strtrim(gxtxt_ini_get(cfg,key,'')))),tf=true;return;endif;endfor
endfunction
function tf=cfg_has_key_local(cfg,key)
  k=regexprep(key,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;tf=isstruct(cfg)&&isfield(cfg,k);
endfunction
