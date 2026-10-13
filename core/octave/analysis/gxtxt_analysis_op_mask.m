% SPDX-License-Identifier: GPL-3.0-or-later
% Row-preserving comparison mask for Scientific Analysis Definition API v1.
% target may be a scalar/string literal or a row-aligned series.
function mask = gxtxt_analysis_op_mask(value, op, target)
  op=lower(strtrim(op));
  n=numel(value);
  if (iscell(value))
    if (iscell(target))
      if (!(isscalar(target) || numel(target)==n)), error('GXTXT:AnalysisMask','String target series length mismatch'); endif
      if (isscalar(target)), target=repmat(target,n,1); endif
      switch op
        case {'eq','=='}, mask=strcmp(value,target);
        case {'ne','!='}, mask=!strcmp(value,target);
        otherwise, error('GXTXT:AnalysisMask','String mask supports only eq/ne');
      endswitch
    else
      q=char(target);
      switch op
        case {'eq','=='}, mask=strcmp(value,q);
        case {'ne','!='}, mask=!strcmp(value,q);
        otherwise, error('GXTXT:AnalysisMask','String mask supports only eq/ne');
      endswitch
    endif
  else
    if (ischar(target) || (iscell(target) && isscalar(target)))
      if (iscell(target)), target=target{1}; endif
      q=str2double(target); if(!isfinite(q)), error('GXTXT:AnalysisMask','Numeric mask target is invalid: %s',char(target)); endif
      target=q;
    endif
    if (!isnumeric(target) && !islogical(target)), error('GXTXT:AnalysisMask','Numeric mask requires numeric target'); endif
    if (!(isscalar(target) || numel(target)==n)), error('GXTXT:AnalysisMask','Target series length mismatch'); endif
    if (isscalar(target)), target=repmat(target,n,1); else target=target(:); endif
    value=value(:);
    switch op
      case {'eq','=='}, mask=(value==target);
      case {'ne','!='}, mask=(value!=target);
      case {'gt','>'}, mask=(value>target);
      case {'ge','>='}, mask=(value>=target);
      case {'lt','<'}, mask=(value<target);
      case {'le','<='}, mask=(value<=target);
      otherwise, error('GXTXT:AnalysisMask','Unknown mask operator: %s',op);
    endswitch
    mask &= isfinite(value) & isfinite(target);
  endif
  mask=logical(mask(:));
endfunction
