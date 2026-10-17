function out=demo_environmental_numeric(operation,varargin)
% Use the public numerical binding advertised in the module runtime.
% SPDX-License-Identifier: GPL-3.0-or-later
  persistent fn;
  if(strcmp(operation,'bind'))
    cfg=varargin{1};prefix='public_api.NUMERIC_API_v1.';
    provider=strtrim(gxtxt_ini_get(cfg,[prefix 'module_id'],''));version=strtrim(gxtxt_ini_get(cfg,[prefix 'api_version'],''));
    entry=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_entrypoint'],''));candidate=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_function'],''));
    caps=strsplit(strrep(gxtxt_ini_get(cfg,[prefix 'capabilities'],''),',',';'),';');caps=cellfun(@strtrim,caps,'UniformOutput',false);
    required={'descriptive_statistics','linear_reductions','linear_regression','smoothing','hypothesis_tests','correlation','robust_mad','elementwise_binary'};
    if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(candidate)||exist(entry,'file')!=2||!all(ismember(required,caps)))
      error('demo.environmental.levoglucosan_campaign: public NUMERIC_API_v1 binding is unavailable');
    endif
    addpath(fileparts(entry));
    if(exist(candidate,'file')!=2),error('demo.environmental.levoglucosan_campaign: public numeric function is unavailable');endif
    fn=candidate;out=[];return;
  endif
  if(isempty(fn)),error('demo.environmental.levoglucosan_campaign: public numeric binding was not initialized');endif
  out=feval(fn,operation,varargin{:});
endfunction
