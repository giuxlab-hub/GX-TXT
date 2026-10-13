function [out,display_unit,factor]=pd_convert_display(values,source_unit,target_unit,axis_name)
% Convert canonical values to a validated display unit.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),axis_name='axis';endif
  source_unit=strtrim(source_unit);target_unit=strtrim(target_unit);out=values;display_unit=source_unit;factor=1;
  if(isempty(source_unit)&&isempty(target_unit)),display_unit='';return;endif
  if(isempty(source_unit)&&!isempty(target_unit)),error('plot.dataset: %s has no source-unit metadata; cannot display as %s',axis_name,target_unit);endif
  if(isempty(target_unit)),display_unit=source_unit;return;endif
  try ok=gxtxt_unit_compatible(source_unit,target_unit);catch ok=false;end_try_catch
  if(!ok),error('plot.dataset: %s source unit %s is incompatible with display unit %s',axis_name,source_unit,target_unit);endif
  [out,display_unit,factor]=gxtxt_plot_display_scale(values,source_unit,target_unit);
  if(!strcmpi(normunit(display_unit),normunit(target_unit))),error('plot.dataset: framework did not apply requested %s unit %s',axis_name,target_unit);endif
endfunction
function u=normunit(u),u=strrep(strrep(strtrim(u),'µ','u'),'μ','u');endfunction
