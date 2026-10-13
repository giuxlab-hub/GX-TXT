% SPDX-License-Identifier: GPL-3.0-or-later
function idx = gxtxt_plot_selected_indices(names,rawList)
  if (isempty(strtrim(rawList)))
    idx = 1:numel(names);
    return;
  endif
  req = strsplit(strrep(rawList,';',','),',');
  idx = [];
  for r = 1:numel(req)
    n = strtrim(req{r});
    if (isempty(n)), continue; endif
    j = find(strcmp(names,n),1,'first');
    if (!isempty(j)), idx(end+1) = j; endif
  endfor
  idx = unique(idx,'stable');
endfunction
