% SPDX-License-Identifier: GPL-3.0-or-later
% Build standard Render Cache API v1 provenance metadata.
% module_id/module_version may be empty for framework-only analysis jobs.
function meta = gxtxt_render_cache_standard_meta(module_id,module_version,definition_path,source_map,parameters)
  if(nargin<1),module_id='';endif;if(nargin<2),module_version='';endif
  if(nargin<3),definition_path='';endif;if(nargin<4),source_map=struct();endif;if(nargin<5),parameters=struct();endif
  meta=struct();meta.api_version=1;meta.module_id=module_id;meta.module_version=module_version;
  meta.definition_id='';meta.definition_version='';
  if(!isempty(strtrim(definition_path)))
    if(exist(definition_path,'file')!=2),error('GXTXT:RenderCache','definition not found: %s',definition_path);endif
    d=gxtxt_ini_read(definition_path);meta.definition_id=strtrim(gxtxt_ini_get(d,'meta.id',''));meta.definition_version=strtrim(gxtxt_ini_get(d,'meta.version',''));
  endif
  meta.source_fingerprint=gxtxt_render_cache_source_fingerprint(source_map);
  meta.parameter_fingerprint=gxtxt_render_cache_parameter_fingerprint(parameters);
  if(!isempty(strtrim(definition_path))),meta.analysis_fingerprint=gxtxt_render_cache_analysis_fingerprint(definition_path,parameters);else meta.analysis_fingerprint=gxtxt_render_cache_fingerprint({'analysis:none',meta.parameter_fingerprint});endif
  meta.created_utc=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time()));
endfunction
