% SPDX-License-Identifier: GPL-3.0-or-later
% Resolve common colormap/colorbar/CLim state with global/module values already
% inherited into p and plot-specific runtime overrides as the final layer.
function s=gxtxt_plot_color_settings(runtime_cfg,graph_key,p)
  if(nargin<3||isempty(p)),p=gxtxt_plot_config();endif
  s=struct('colormap',fielddef(p,'colormap','viridis'),'colorbar_visible',fielddef(p,'colorbar_visible',false), ...
    'colorbar_label',fielddef(p,'colorbar_label',''),'color_unit',fielddef(p,'color_unit','auto'), ...
    'color_min',fielddef(p,'color_min',NaN),'color_max',fielddef(p,'color_max',NaN));
  if(nargin<2||isempty(graph_key)||isempty(runtime_cfg)),return;endif
  s.colormap=override(runtime_cfg,graph_key,'colormap',s.colormap);
  q=override(runtime_cfg,graph_key,'colorbar_visible','');if(!isempty(q)&&!strcmpi(q,'inherit')),s.colorbar_visible=parse_bool(q,s.colorbar_visible);endif
  q=override(runtime_cfg,graph_key,'colorbar_label','');if(!isempty(q)),s.colorbar_label=q;endif
  q=override(runtime_cfg,graph_key,'color_unit','');if(!isempty(q)&&!strcmpi(q,'inherit')),s.color_unit=q;endif
  q=str2double(override(runtime_cfg,graph_key,'color_min',''));if(isfinite(q)),s.color_min=q;endif
  q=str2double(override(runtime_cfg,graph_key,'color_max',''));if(isfinite(q)),s.color_max=q;endif
endfunction
function v=fielddef(s,k,d),if(isstruct(s)&&isfield(s,k)),v=s.(k);else v=d;endif;endfunction
function v=override(r,g,f,d),v=strtrim(gxtxt_ini_get(r,['axis.' g '.' f],d));endfunction
function b=parse_bool(v,d),q=lower(strtrim(v));if(any(strcmp(q,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(q,{'0','false','no','off'}))),b=false;else b=d;endif;endfunction
