% SPDX-License-Identifier: GPL-3.0-or-later
% Row-preserving numeric window mask. Bounds may be scalar or row-aligned.
function mask = gxtxt_analysis_op_window(value,lo,hi,inclusive)
  if(nargin<4||isempty(inclusive)),inclusive=true;endif
  if(!isnumeric(value)),error('GXTXT:AnalysisWindow','value must be numeric');endif
  v=value(:);n=numel(v);lo=expand_bound(lo,n,-Inf);hi=expand_bound(hi,n,Inf);
  if(inclusive),mask=(v>=lo)&(v<=hi);else mask=(v>lo)&(v<hi);endif
  mask &= isfinite(v) & (isfinite(lo)|isinf(lo)) & (isfinite(hi)|isinf(hi));mask=logical(mask);
endfunction
function q=expand_bound(q,n,def)
  if(isempty(q)),q=repmat(def,n,1);return;endif
  if(ischar(q)),q=str2double(q);endif
  if(isscalar(q)),q=repmat(q,n,1);elseif(numel(q)==n),q=q(:);else error('GXTXT:AnalysisWindow','bound length mismatch');endif
endfunction
