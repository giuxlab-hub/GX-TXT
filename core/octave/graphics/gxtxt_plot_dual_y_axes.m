% SPDX-License-Identifier: GPL-3.0-or-later
% Multi-Y Axis Plot API v1: create synchronized left/right Y axes.
function [ax_left, ax_right] = gxtxt_plot_dual_y_axes(fig,p)
  if(nargin<1||isempty(fig)),fig=gcf();endif
  if(nargin<2),p=gxtxt_plot_config();endif
  ax_left=axes('parent',fig);
  set(ax_left,'tag','gxtxt_primary_axis');
  hold(ax_left,'on');
  try gxtxt_plot_apply_axes(ax_left,p); catch; end_try_catch
  old=get(ax_left,'units');set(ax_left,'units','normalized');pos=get(ax_left,'position');set(ax_left,'units',old);
  ax_right=axes('parent',fig,'units','normalized','position',pos,'color','none','yaxislocation','right','box','off','tag','gxtxt_overlay_yaxis');
  hold(ax_right,'on');
  try gxtxt_plot_apply_axes(ax_right,p); catch; end_try_catch
  try set(ax_right,'xgrid','off','ygrid','off'); catch; end_try_catch
  try set(ax_right,'xtick',[],'xticklabel',{}); catch; end_try_catch
  try linkaxes([ax_left ax_right],'x'); catch; end_try_catch
  % GNUplot interprets equal positions as different data rectangles when
  % each axes is allowed to reserve its own outer margins for ticks/labels.
  gxtxt_plot_sync_overlay_axes(fig);
endfunction
