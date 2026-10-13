function budget=pd_2d_display_budget(configured)
% Bound 2-D display preparation to the configured target and raster width.
% The default 1600 px raster keeps the historical 6000-point graph budget.
% SPDX-License-Identifier: GPL-3.0-or-later
  budget=max(100,round(configured));w=str2double(strtrim(getenv('GXTXT_PLOT_WIDTH_PX')));
  if(isfinite(w)&&w>0),budget=min(budget,max(400,round(4*w)));endif
endfunction
