% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT pipeline - visibilita figure richiesta dal runtime.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
% GNU GPL v3 or later.

function v = gxtxt_figure_visibility()
  raw = lower(strtrim(getenv('GXTXT_GRAPHICS_VISIBLE')));
  if (any(strcmp(raw, {'1','true','yes','on'})))
    v = 'on';
  else
    v = 'off';
  endif
endfunction
