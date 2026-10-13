% SPDX-License-Identifier: GPL-3.0-or-later
function label = gxtxt_plot_node_label(nodeName)
  key = gxtxt_plot_node_envkey(nodeName);
  label = gxtxt_getenv_default(['GXTXT_PLOT_LABEL_' key],nodeName);
endfunction
