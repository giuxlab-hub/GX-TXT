function fn=welch_numeric_api(cfg)
% Resolve the public numerical binding supplied by Standard Module API.
% SPDX-License-Identifier: GPL-3.0-or-later
  prefix='public_api.NUMERIC_API_v1.';
  provider=strtrim(gxtxt_ini_get(cfg,[prefix 'module_id'],''));version=strtrim(gxtxt_ini_get(cfg,[prefix 'api_version'],''));
  entry=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_entrypoint'],''));fn=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_function'],''));
  caps=strsplit(strrep(gxtxt_ini_get(cfg,[prefix 'capabilities'],''),',',';'),';');caps=cellfun(@strtrim,caps,'UniformOutput',false);
  required={'fft','detrending','window_generation','welch_aggregate'};
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(fn)||exist(entry,'file')!=2||!all(ismember(required,caps)))
    error('analysis.welch_spectrum: public NUMERIC_API_v1 transform binding is unavailable');
  endif
  addpath(fileparts(entry));
  if(exist(fn,'file')!=2),error('analysis.welch_spectrum: public numeric Octave function is unavailable');endif
endfunction
