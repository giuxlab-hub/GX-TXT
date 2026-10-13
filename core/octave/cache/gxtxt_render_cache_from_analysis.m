% SPDX-License-Identifier: GPL-3.0-or-later
% Convert a gxtxt_analysis_run() result to the optional standard Render Cache
% API v1 envelope. This does not change or reinterpret legacy module-owned MAT
% caches; modules opt in by calling this helper.
function cache = gxtxt_render_cache_from_analysis(result,meta)
  if(nargin<2||isempty(meta)),meta=struct('api_version',1);endif
  if(!isstruct(result)||!isfield(result,'context')),error('GXTXT:RenderCache','analysis result with context is required');endif
  if(!isfield(meta,'api_version')),meta.api_version=1;endif
  if(meta.api_version!=1),error('GXTXT:RenderCache','unsupported Render Cache API version');endif
  cache=struct();cache.meta=meta;
  cache.data=struct('definition_id',field_or(result,'definition_id',''), ...
                    'definition_path',field_or(result,'definition_path',''), ...
                    'context',result.context, ...
                    'operation_order',{field_or(result,'operation_order',{})}, ...
                    'exports',{field_or(result,'exports',{})});
  cache.graphics=struct('plots',{field_or(result,'plots',{})});
  cache.module=struct();
endfunction
function v=field_or(s,k,d),if(isfield(s,k)),v=s.(k);else v=d;endif;endfunction
