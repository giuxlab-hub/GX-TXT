% SPDX-License-Identifier: GPL-3.0-or-later
% Stable SHA-256 over a scalar string or ordered cell array of scalar values.
function fp = gxtxt_render_cache_fingerprint(parts)
  if(!iscell(parts)),parts={parts};endif
  buf='';
  for i=1:numel(parts)
    q=parts{i}; if(isnumeric(q)||islogical(q)),q=sprintf('%.17g',q);else q=char(q);endif
    buf=[buf sprintf('%d:',length(q)) q ';']; %#ok<AGROW>
  endfor
  try
    fp=hash('sha256',buf);
  catch
    error('GXTXT:RenderCache','Octave hash() with SHA-256 is required for fingerprinting');
  end_try_catch
endfunction
