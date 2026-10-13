% SPDX-License-Identifier: GPL-3.0-or-later
% Load a Render Cache API v1 envelope.  Legacy module-owned MAT files are not
% reinterpreted: modules using those files continue to load them directly.
function cache = gxtxt_render_cache_load(outdir_or_path)
  [~,~,e]=fileparts(outdir_or_path);if(strcmpi(e,'.mat')),path=outdir_or_path;else path=gxtxt_render_cache_path(outdir_or_path);endif
  if(exist(path,'file')!=2),error('GXTXT:RenderCache','render cache not found: %s',path);endif
  S=load(path);
  if(!isfield(S,'cache')||!isstruct(S.cache)),error('GXTXT:RenderCache','not a Render Cache API v1 envelope (legacy/module-owned cache may require its module loader)');endif
  cache=S.cache;
  if(!isfield(cache,'meta')||!isfield(cache.meta,'api_version')||cache.meta.api_version!=1),error('GXTXT:RenderCache','unsupported or missing Render Cache API version');endif
endfunction
