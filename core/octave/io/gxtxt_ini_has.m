% SPDX-License-Identifier: GPL-3.0-or-later
function tf = gxtxt_ini_has(d,key)
  k = regexprep(key,'[^A-Za-z0-9_]','_');
  if (isempty(k) || !isletter(k(1))), k = ['k_' k]; endif
  tf = isfield(d,k);
endfunction
