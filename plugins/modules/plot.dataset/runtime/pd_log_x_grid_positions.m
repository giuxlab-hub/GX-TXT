% SPDX-License-Identifier: GPL-3.0-or-later
% Common log10 X grid positions for single- and shared-X multi-panel plots.
function [major,minor]=pd_log_x_grid_positions(lim,major_step)
  major=[];minor=[];
  if(numel(lim)!=2||any(!isfinite(lim))||lim(1)<=0||lim(2)<=lim(1)),return;endif
  if(isfinite(major_step)&&major_step>0)
    first=ceil((log10(lim(1))-1e-10)/major_step)*major_step;
    last=floor((log10(lim(2))+1e-10)/major_step)*major_step;
    if(last>=first),major=10.^(first:major_step:last);endif
  endif
  for exponent=floor(log10(lim(1))):ceil(log10(lim(2)))
    for multiplier=2:9
      value=multiplier*10^exponent;
      if(value>lim(1)&&value<lim(2)),minor(end+1)=value;endif %#ok<AGROW>
    endfor
  endfor
endfunction
