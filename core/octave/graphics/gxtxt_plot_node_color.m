% SPDX-License-Identifier: GPL-3.0-or-later
function spec = gxtxt_plot_node_color(nodeName)
  key = gxtxt_plot_node_envkey(nodeName);
  spec = gxtxt_getenv_default(['GXTXT_PLOT_COLOR_' key],'');
endfunction
