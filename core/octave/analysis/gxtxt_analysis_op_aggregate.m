% SPDX-License-Identifier: GPL-3.0-or-later
% Aggregate and broadcast the statistic back to each row. Optional group keeps
% the operation row-preserving, which simplifies composition in API v1.
function out = gxtxt_analysis_op_aggregate(value, method, group)
  if (nargin<3), group=[]; endif
  out=NaN(size(value));
  if (isempty(group))
    q=stat(value,method); out(:)=q; return;
  endif
  if (iscell(group))
    keys=unique(group,'stable');
    for i=1:numel(keys), idx=strcmp(group,keys{i}); out(idx)=stat(value(idx),method); endfor
  else
    keys=unique(group(isfinite(group)),'stable');
    for i=1:numel(keys), idx=(group==keys(i)); out(idx)=stat(value(idx),method); endfor
  endif
endfunction

function q=stat(v,method)
  v=v(isfinite(v));
  if (strcmpi(method,'count')), q=numel(v); return; endif
  if (isempty(v)), q=NaN; return; endif
  switch lower(strtrim(method))
    case 'mean', q=mean(v);
    case 'median', q=median(v);
    case 'min', q=min(v);
    case 'max', q=max(v);
    case 'std', q=std(v);
    case 'sum', q=sum(v);
    otherwise, error('GXTXT:AnalysisAggregate','Unknown aggregate method: %s',method);
  endswitch
endfunction
