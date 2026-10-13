function out=demo_geospatial_numeric(operation,varargin)
% Resolve the public numerical service for reusable grid statistics.
% SPDX-License-Identifier: GPL-3.0-or-later
  persistent fn;
  if(strcmp(operation,'bind'))
    cfg=varargin{1};prefix='public_api.NUMERIC_API_v1.';
    provider=strtrim(gxtxt_ini_get(cfg,[prefix 'module_id'],''));version=strtrim(gxtxt_ini_get(cfg,[prefix 'api_version'],''));
    entry=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_entrypoint'],''));candidate=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_function'],''));
    caps=strsplit(strrep(gxtxt_ini_get(cfg,[prefix 'capabilities'],''),',',';'),';');caps=cellfun(@strtrim,caps,'UniformOutput',false);
    if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(candidate)||exist(entry,'file')!=2||!any(strcmp(caps,'linear_reductions')))
      error('demo.geospatial.ticino_valley_3d: public NUMERIC_API_v1 reduction binding is unavailable');
    endif
    addpath(fileparts(entry));
    if(exist(candidate,'file')!=2),error('demo.geospatial.ticino_valley_3d: public numeric function is unavailable');endif
    fn=candidate;out=[];return;
  endif
  if(isempty(fn)),error('demo.geospatial.ticino_valley_3d: public numeric binding was not initialized');endif
  out=feval(fn,operation,varargin{:});
endfunction
