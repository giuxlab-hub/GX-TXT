% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_analysis_op_normalize(value, method)
  method=lower(strtrim(method));
  finite=value(isfinite(value));
  if (isempty(finite)), out=value; return; endif
  switch method
    case 'maxabs'
      s=max(abs(finite)); if (s==0), s=1; endif; out=value./s;
    case 'max'
      s=max(finite); if (s==0), s=1; endif; out=value./s;
    case 'rms'
      s=sqrt(mean(finite.^2)); if (s==0), s=1; endif; out=value./s;
    case 'minmax'
      lo=min(finite); hi=max(finite); if (hi==lo), out=zeros(size(value)); else out=(value-lo)./(hi-lo); endif
    case 'zscore'
      m=mean(finite); s=std(finite); if (s==0), s=1; endif; out=(value-m)./s;
    otherwise
      error('GXTXT:AnalysisNormalize','Unknown normalization method: %s',method);
  endswitch
endfunction
