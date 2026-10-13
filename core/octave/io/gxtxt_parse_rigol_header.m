% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT pipeline - parser header estratto Rigol a singolo canale.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
% GNU GPL v3 or later.

function [tStart,dt] = gxtxt_parse_rigol_header(h1,h2)
  a = strsplit(h1,',');
  b = strsplit(h2,',');
  idxS = find(strcmp(strtrim(a),'Start'),1);
  idxD = find(strcmp(strtrim(a),'Increment'),1);
  if (isempty(idxS) || isempty(idxD) || idxS > numel(b) || idxD > numel(b))
    error('Start/Increment fields are missing from the Rigol header.');
  endif
  tStart = str2double(strtrim(b{idxS}));
  dt = str2double(strtrim(b{idxD}));
  if (!isfinite(tStart) || !isfinite(dt) || dt <= 0)
    error('Invalid Start/Increment values in the Rigol header.');
  endif
endfunction
