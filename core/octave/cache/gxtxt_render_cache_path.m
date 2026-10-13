% SPDX-License-Identifier: GPL-3.0-or-later
function path = gxtxt_render_cache_path(outdir)
  if(nargin<1 || isempty(strtrim(outdir))),error('GXTXT:RenderCache','output directory is required');endif
  path=fullfile(outdir,'render_cache.mat');
endfunction
