% SPDX-License-Identifier: GPL-3.0-or-later
function key = gxtxt_plot_node_envkey(nodeName)
  key = upper(regexprep(nodeName,'[^A-Za-z0-9_]','_'));
  if (isempty(key)), key = 'NODE'; endif
  if (key(1) >= '0' && key(1) <= '9'), key = ['N_' key]; endif
endfunction
