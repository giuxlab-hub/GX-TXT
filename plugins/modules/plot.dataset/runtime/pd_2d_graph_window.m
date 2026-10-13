function W=pd_2d_graph_window(cfg,graph,V)
% Resolve an optional X preparation window that is safe to map to source rows.
% Only explicit display units are used for pre-read range planning. Automatic
% units depend on data magnitude and therefore cannot safely drive source-range
% selection before the data are read.
% SPDX-License-Identifier: GPL-3.0-or-later
  W=struct('enabled',false,'x_min',NaN,'x_max',NaN,'display_unit','','source','none');
  prefix=['axis.' graph '.'];
  if(core_axis_state_declared(cfg,graph)&&core_axis_state_enabled(cfg,graph))
    xmin=parse_num(gxtxt_ini_get(cfg,[prefix 'x_min'],''));
    xmax=parse_num(gxtxt_ini_get(cfg,[prefix 'x_max'],''));
    unit=clean_unit(gxtxt_ini_get(cfg,[prefix 'x_unit'],'inherit'));
    if((isfinite(xmin)||isfinite(xmax))&&!isempty(unit))
      W=struct('enabled',true,'x_min',xmin,'x_max',xmax,'display_unit',unit,'source','core_axes');return;
    endif
  endif
  if(nargin<3||!isstruct(V)||!isfield(V,'enabled')||!V.enabled||!isfield(V,'axes')||!isfield(V.axes,'x')),return;endif
  A=V.axes.x;xmin=NaN;xmax=NaN;unit='';
  if(isfield(A,'min')),xmin=parse_num(A.min);endif
  if(isfield(A,'max')),xmax=parse_num(A.max);endif
  if(isfield(A,'display_unit')),unit=clean_unit(A.display_unit);endif
  if((isfinite(xmin)||isfinite(xmax))&&!isempty(unit))
    W=struct('enabled',true,'x_min',xmin,'x_max',xmax,'display_unit',unit,'source','plotspec');
  endif
endfunction

function v=parse_num(s),v=str2double(strtrim(s));if(!isfinite(v)),v=NaN;endif;endfunction
function u=clean_unit(s),u=strtrim(s);if(any(strcmpi(u,{'','auto','inherit'}))),u='';endif;endfunction
function tf=core_axis_state_enabled(cfg,graph)
  tf=false;q=str2double(gxtxt_ini_get(cfg,['axis.' graph '.enabled'],'0'));if(isfinite(q)&&q!=0),tf=true;endif
endfunction
function tf=core_axis_state_declared(cfg,graph)
  tf=false;prefix=['axis.' graph '.'];if(!cfg_has_key(cfg,[prefix 'enabled'])),return;endif
  token_fields={'x_unit','y_unit','y2_unit','x_format','y_format','y2_format','xgrid','ygrid','align_ylabels'};
  for i=1:numel(token_fields),key=[prefix token_fields{i}];if(!cfg_has_key(cfg,key)),continue;endif;v=strtrim(gxtxt_ini_get(cfg,key,'inherit'));if(isempty(v)||!strcmpi(v,'inherit')),tf=true;return;endif;endfor
  value_fields={'x_min','x_max','x_step','y_min','y_max','y_step','y2_min','y2_max','y2_step','grid_color','ylabel_x'};
  for i=1:numel(value_fields),key=[prefix value_fields{i}];if(cfg_has_key(cfg,key)&&!isempty(strtrim(gxtxt_ini_get(cfg,key,'')))),tf=true;return;endif;endfor
endfunction
function tf=cfg_has_key(cfg,key)
  k=regexprep(key,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;tf=isstruct(cfg)&&isfield(cfg,k);
endfunction
