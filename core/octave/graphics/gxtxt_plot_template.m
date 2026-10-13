% SPDX-License-Identifier: GPL-3.0-or-later
function s = gxtxt_plot_template(envName,defaultValue,nodeLabel)
  s = gxtxt_getenv_default(envName,defaultValue);
  if (nargin >= 3)
    s = strrep(s,'{NODE}',nodeLabel);
  endif
endfunction
