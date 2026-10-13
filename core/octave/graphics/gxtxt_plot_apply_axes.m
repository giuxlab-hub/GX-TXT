% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_plot_apply_axes(ax,p)
  if (nargin < 1 || isempty(ax)), ax = gca(); endif
  if (nargin < 2), p = gxtxt_plot_config(); endif
  try set(ax,'fontunits','points'); catch; end_try_catch
  set(ax,'fontsize',p.font_size);
  mode='inherit'; if (isfield(p,'grid_mode')), mode=lower(strtrim(p.grid_mode)); endif
  try
    switch mode
      case 'both', set(ax,'xgrid','on','ygrid','on');
      case 'vertical', set(ax,'xgrid','on','ygrid','off');
      case 'horizontal', set(ax,'xgrid','off','ygrid','on');
      case 'none', set(ax,'xgrid','off','ygrid','off');
      otherwise, if (p.grid), grid(ax,'on'); else grid(ax,'off'); endif
    endswitch
  catch
    if (p.grid), grid(ax,'on'); else grid(ax,'off'); endif
  end_try_catch
  if (isfield(p,'grid_color') && !isempty(strtrim(p.grid_color)))
    c = gxtxt_plot_color(p.grid_color,[]);
    if (!isempty(c))
      try set(ax,'gridcolor',c); catch; end_try_catch
    endif
  endif
endfunction
