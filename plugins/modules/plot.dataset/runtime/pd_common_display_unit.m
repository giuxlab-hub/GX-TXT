function [target,base_unit]=pd_common_display_unit(value_cells,unit_cells,mode,axis_name)
% Resolve one coherent display unit for all series sharing an axis.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),axis_name='axis';endif
  mode=strtrim(mode);if(isempty(mode)||strcmpi(mode,'inherit')),mode='auto';endif
  base_unit='';known=0;unknown=0;
  for i=1:numel(unit_cells)
    u=strtrim(unit_cells{i});if(isempty(u)),unknown+=1;continue;endif
    if(isempty(base_unit)),base_unit=u;endif;known+=1;
    try ok=gxtxt_unit_compatible(base_unit,u);catch ok=false;end_try_catch
    if(!ok),error('plot.dataset: incompatible units on %s: %s and %s',axis_name,base_unit,u);endif
  endfor
  if(known>0&&unknown>0),error('plot.dataset: cannot mix known and missing units on %s',axis_name);endif
  if(known==0)
    if(!any(strcmpi(mode,{'auto','source','none','inherit'}))),error('plot.dataset: %s display unit %s requested but source unit metadata are missing',axis_name,mode);endif
    target='';return;
  endif
  if(any(strcmpi(mode,{'source','none'}))),target=base_unit;return;endif
  combined=[];
  for i=1:numel(value_cells)
    v=value_cells{i};u=strtrim(unit_cells{i});if(isempty(v)),continue;endif
    try vb=gxtxt_unit_convert(v,u,base_unit);catch err,error('plot.dataset: cannot normalize %s values from %s to %s: %s',axis_name,u,base_unit,err.message);end_try_catch
    combined=[combined;vb(:)]; %#ok<AGROW>
  endfor
  if(isempty(combined)),combined=0;endif
  if(strcmpi(mode,'auto'))
    [~,target]=gxtxt_plot_display_scale(combined,base_unit,'auto');
  else
    try ok=gxtxt_unit_compatible(base_unit,mode);catch ok=false;end_try_catch
    if(!ok),error('plot.dataset: display unit %s is incompatible with %s source unit %s',mode,axis_name,base_unit);endif
    [~,got]=gxtxt_plot_display_scale(combined,base_unit,mode);if(!strcmpi(normunit(got),normunit(mode))),error('plot.dataset: failed to apply requested %s display unit %s',axis_name,mode);endif
    target=got;
  endif
endfunction
function u=normunit(u),u=strrep(strrep(strtrim(u),'µ','u'),'μ','u');endfunction
