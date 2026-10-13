% SPDX-License-Identifier: GPL-3.0-or-later
% Stable fingerprint of scalar Analysis Definition parameter overrides.
function fp = gxtxt_render_cache_parameter_fingerprint(parameters)
  if(nargin<1||isempty(parameters)),fp=gxtxt_render_cache_fingerprint({'parameters:none'});return;endif
  if(!isstruct(parameters)),error('GXTXT:RenderCache','parameters must be a struct');endif
  names=sort(fieldnames(parameters));parts={'GXTXT_ANALYSIS_PARAMETERS_V1'};
  for i=1:numel(names)
    k=names{i};v=parameters.(k);parts{end+1}=k; %#ok<AGROW>
    if(islogical(v)&&isscalar(v)),parts{end+1}=sprintf('bool:%d',v); %#ok<AGROW>
    elseif(isnumeric(v)&&isscalar(v)),parts{end+1}=sprintf('num:%.17g',v); %#ok<AGROW>
    elseif(ischar(v)),parts{end+1}=['str:' v]; %#ok<AGROW>
    else,error('GXTXT:RenderCache','parameter %s is not a supported scalar value',k);endif
  endfor
  fp=gxtxt_render_cache_fingerprint(parts);
endfunction
