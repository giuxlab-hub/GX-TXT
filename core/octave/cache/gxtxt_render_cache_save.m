% SPDX-License-Identifier: GPL-3.0-or-later
% Atomically save the optional framework Render Cache API v1 envelope.
% Existing modules that own legacy render_cache.mat files remain supported.
function path = gxtxt_render_cache_save(outdir_or_path, cache)
  if(!isstruct(cache)),error('GXTXT:RenderCache','cache must be a struct');endif
  if(!isfield(cache,'meta')||!isstruct(cache.meta)),cache.meta=struct();endif
  if(!isfield(cache.meta,'api_version')),cache.meta.api_version=1;endif
  if(cache.meta.api_version!=1),error('GXTXT:RenderCache','unsupported cache API version');endif
  [d,n,e]=fileparts(outdir_or_path);
  if(strcmpi(e,'.mat')),path=outdir_or_path;outdir=d;else outdir=outdir_or_path;path=gxtxt_render_cache_path(outdir);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  tmp=[tempname(outdir) '.mat'];
  unwind_protect
    save('-binary',tmp,'cache');
    [ok,msg]=movefile(tmp,path,'f'); if(!ok),error('GXTXT:RenderCache','cannot install cache: %s',msg);endif
  unwind_protect_cleanup
    if(exist(tmp,'file')==2),unlink(tmp);endif
  end_unwind_protect
endfunction
