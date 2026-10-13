% SPDX-License-Identifier: GPL-3.0-or-later
function v = gxtxt_ini_get(d,key,def)
  if (nargin < 3), def = ''; endif
  k = regexprep(key,'[^A-Za-z0-9_]','_');
  if (isempty(k) || !isletter(k(1))), k = ['k_' k]; endif
  if (isfield(d,k)), v = d.(k); else v = def; endif
endfunction
