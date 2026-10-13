% SPDX-License-Identifier: GPL-3.0-or-later
% Standard Module API v1 -> Scientific Analysis Definition API v1 bridge.
%
% sources = gxtxt_analysis_source_map_from_runtime(runtime_cfg)
%
% Reads the additive multi-source runtime sections:
%   [analysis_sources] ids=primary;uncertainty;...
%   [analysis_source.<id>] path=...
%
% Backward compatibility: when those sections are absent, [dataset].path is
% returned as sources.primary.  This helper performs no join, interpolation,
% resampling or other scientific alignment.
function sources = gxtxt_analysis_source_map_from_runtime(cfg)
  sources=struct();
  ids=parse_list_local(gxtxt_ini_get(cfg,'analysis_sources.ids',''));
  if(isempty(ids))
    p=strtrim(gxtxt_ini_get(cfg,'dataset.path',''));
    if(!isempty(p)),sources.primary=p;endif
    return;
  endif
  for k=1:numel(ids)
    id=strtrim(ids{k});
    if(isempty(regexp(id,'^[A-Za-z][A-Za-z0-9_]*$','once')))
      error('GXTXT:AnalysisSourceMap','Invalid source ID: %s',id);
    endif
    p=strtrim(gxtxt_ini_get(cfg,['analysis_source.' id '.path'],''));
    if(isempty(p)),continue;endif
    sources.(id)=p;
  endfor
endfunction

function out=parse_list_local(s)
  s=strrep(s,';',','); raw=strsplit(s,','); out={};
  for i=1:numel(raw),q=strtrim(raw{i});if(!isempty(q)),out{end+1}=q;endif;endfor
endfunction
