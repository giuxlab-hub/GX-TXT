function fn=tdfft_numeric_api(cfg)
% Discover the public numerical binding supplied by Standard Module API.
% No provider-private path or local mathematical fallback is permitted.
% SPDX-License-Identifier: GPL-3.0-or-later
  section='public_api.NUMERIC_API_v1';
  provider=strtrim(gxtxt_ini_get(cfg,[section '.module_id'],''));
  version=strtrim(gxtxt_ini_get(cfg,[section '.api_version'],''));
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1'))
    error('analysis.time_dependent_fft: public NUMERIC_API_v1 discovery is missing or incompatible');
  endif
  caps=strsplit(strrep(gxtxt_ini_get(cfg,[section '.capabilities'],''),',',';'),';');
  caps=cellfun(@strtrim,caps,'UniformOutput',false);
  required={'fft','one_sided_transform','detrending','window_generation','frequency_grid','grid_analysis','linear_reductions','fft_backend_threads'};
  for k=1:numel(required)
    if(!any(strcmp(caps,required{k})))
      error('analysis.time_dependent_fft: NUMERIC_API_v1 capability missing: %s',required{k});
    endif
  endfor
  entry=strtrim(gxtxt_ini_get(cfg,[section '.octave_entrypoint'],''));
  fn=strtrim(gxtxt_ini_get(cfg,[section '.octave_function'],''));
  if(isempty(entry)||isempty(fn)||exist(entry,'file')!=2)
    error('analysis.time_dependent_fft: advertised public numerical binding is unavailable');
  endif
  addpath(fileparts(entry));
  if(exist(fn,'file')!=2)
    error('analysis.time_dependent_fft: advertised numerical function is unavailable: %s',fn);
  endif
endfunction
