function fn=curvefit_numeric_api(cfg,required)
% Resolve the public NUMERIC_API_v1 binding advertised by the framework.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<2),required={'residual_metrics'};endif
  prefix='public_api.NUMERIC_API_v1.';
  provider=strtrim(ini_get(cfg,[prefix 'module_id'],''));
  version=strtrim(ini_get(cfg,[prefix 'api_version'],''));
  entry=strtrim(ini_get(cfg,[prefix 'octave_entrypoint'],''));
  fn=strtrim(ini_get(cfg,[prefix 'octave_function'],''));
  caps=strsplit(strrep(ini_get(cfg,[prefix 'capabilities'],''),',',';'),';');caps=cellfun(@strtrim,caps,'UniformOutput',false);
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(fn)||exist(entry,'file')!=2||!all(ismember(required,caps)))
    error('curvefit.family_global: public NUMERIC_API_v1 binding is unavailable');
  endif
  addpath(fileparts(entry));
  if(exist(fn,'file')!=2),error('curvefit.family_global: public numeric Octave function is unavailable');endif
endfunction

function v=ini_get(cfg,key,def)
  k=regexprep(key,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif
  if(isfield(cfg,k)),v=cfg.(k);else v=def;endif
endfunction
