% SPDX-License-Identifier: GPL-3.0-or-later
function f = gxtxt_plot_new_figure(p)
  f = figure('visible',gxtxt_figure_visibility(), ...
             'units','pixels', ...
             'position',[60 60 p.width_px p.height_px]);
  try
    if(strcmpi(strtrim(p.background),'transparent'))
      set(f,'color','none');
    else
      set(f,'color',gxtxt_plot_color(p.background,[1 1 1]));
    endif
  catch
  end_try_catch
  set(f,'paperunits','inches');
  set(f,'paperposition',[0 0 p.width_px/p.dpi p.height_px/p.dpi]);
  set(f,'papersize',[p.width_px/p.dpi p.height_px/p.dpi]);
  set(f,'paperpositionmode','manual');
endfunction
