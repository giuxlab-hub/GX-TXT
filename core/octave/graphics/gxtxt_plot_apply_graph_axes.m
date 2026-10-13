% SPDX-License-Identifier: GPL-3.0-or-later
% Apply common axes style and the final graph/panel override in one API call.
% This is the preferred v0.8.1 entry point for Graph Provider renderers.
function gxtxt_plot_apply_graph_axes(axs,p,graphKey,panelNames,runtimeCfg)
  if (nargin<1 || isempty(axs)), axs=gca(); endif
  if (nargin<2 || isempty(p)), p=gxtxt_plot_config(); endif
  if (nargin<3), graphKey=''; endif
  if (nargin<4 || isempty(panelNames)), panelNames={}; endif
  if (nargin<5), runtimeCfg=struct(); endif
  for k=1:numel(axs), gxtxt_plot_apply_axes(axs(k),p); endfor
  if (!isempty(strtrim(graphKey))), gxtxt_plot_axis_overrides(axs,graphKey,panelNames,p,runtimeCfg); endif
endfunction
