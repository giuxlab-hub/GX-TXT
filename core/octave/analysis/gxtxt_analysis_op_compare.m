% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_analysis_op_compare(value, group, reference, method, reference_aggregate)
  if (nargin<5 || isempty(reference_aggregate)), reference_aggregate='median'; endif
  idx = group_match(group,reference);
  if (!any(idx)), error('GXTXT:AnalysisCompare','Reference group value not found: %s',reference); endif
  refvals=value(idx); refvals=refvals(isfinite(refvals));
  if (isempty(refvals)), error('GXTXT:AnalysisCompare','Reference group has no finite numeric values'); endif
  switch lower(strtrim(reference_aggregate))
    case 'first', ref=refvals(1);
    case 'mean', ref=mean(refvals);
    case 'median', ref=median(refvals);
    otherwise, error('GXTXT:AnalysisCompare','Unknown reference aggregate: %s',reference_aggregate);
  endswitch
  switch lower(strtrim(method))
    case 'ratio', out=value./ref;
    case 'difference', out=value-ref;
    case {'percent_change','percent'}, out=100*(value-ref)./ref;
    otherwise, error('GXTXT:AnalysisCompare','Unknown compare method: %s',method);
  endswitch
endfunction

function idx = group_match(group,reference)
  if (iscell(group))
    idx=strcmp(strtrim(group),strtrim(reference));
  else
    q=str2double(reference);
    if (!isfinite(q)), error('GXTXT:AnalysisCompare','Numeric group requires numeric reference'); endif
    idx=(group==q);
  endif
endfunction
