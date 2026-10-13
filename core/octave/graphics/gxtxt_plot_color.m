% SPDX-License-Identifier: GPL-3.0-or-later
function c = gxtxt_plot_color(spec,defaultColor)
  if (nargin < 2), defaultColor = []; endif
  if (isempty(spec)), c = defaultColor; return; endif
  s = strtrim(spec);
  if (isempty(s)), c = defaultColor; return; endif
  if (numel(s) == 7 && s(1) == '#')
    vals = sscanf(s(2:end),'%2x%2x%2x');
    if (numel(vals) == 3)
      c = double(vals(:)')/255;
      return;
    endif
  endif
  vals = sscanf(strrep(s,',',' '),'%f');
  if (numel(vals) == 3)
    c = double(vals(:)');
    if (max(c) > 1), c = c/255; endif
    c = min(1,max(0,c));
    return;
  endif
  names = {'black',[0 0 0];'white',[1 1 1];'red',[1 0 0];'green',[0 0.5 0]; ...
           'blue',[0 0 1];'cyan',[0 1 1];'magenta',[1 0 1];'yellow',[1 1 0]};
  for k=1:rows(names)
    if (strcmpi(s,names{k,1})), c = names{k,2}; return; endif
  endfor
  c = defaultColor;
endfunction
