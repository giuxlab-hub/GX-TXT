% SPDX-License-Identifier: GPL-3.0-or-later
% Plot Region Selection API v1 runtime reader.
function R = gxtxt_plot_region_from_runtime(cfg,graph_id)
  p=['plot.region.' graph_id '.'];
  R=struct('enabled',false,'space','data','axis','primary','x_min',NaN,'x_max',NaN,'y_min',NaN,'y_max',NaN);
  R.enabled=parse_bool(gxtxt_ini_get(cfg,[p 'enabled'],'0'));
  R.space=strtrim(gxtxt_ini_get(cfg,[p 'space'],'data'));R.axis=strtrim(gxtxt_ini_get(cfg,[p 'axis'],'primary'));
  for k={'x_min','x_max','y_min','y_max'},q=str2double(strtrim(gxtxt_ini_get(cfg,[p k{1}],'NaN')));R.(k{1})=q;endfor
endfunction
function tf=parse_bool(v),s=lower(strtrim(num2str(v)));tf=any(strcmp(s,{'1','true','yes','on'}));endfunction
