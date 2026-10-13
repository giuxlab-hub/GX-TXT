% SPDX-License-Identifier: GPL-3.0-or-later
% Resolve per-graph display-unit mode from runtime.ini.
% axis_name: x, y, y2, z, c/color. default_mode usually source/auto/inherit.
function mode=gxtxt_plot_axis_unit_mode(runtime_cfg,graph_key,axis_name,default_mode)
  if(nargin<4||isempty(default_mode)),default_mode='inherit';endif
  if(nargin<3||isempty(axis_name)),axis_name='x';endif
  mode=default_mode;
  if(isempty(runtime_cfg)||isempty(graph_key)),return;endif
  a=lower(strtrim(axis_name));if(strcmp(a,'c')),field='color_unit';elseif(strcmp(a,'color')),field='color_unit';else field=[a '_unit'];endif
  key=['axis.' graph_key '.' field];
  v=strtrim(gxtxt_ini_get(runtime_cfg,key,''));if(!isempty(v)),mode=v;endif
endfunction
