% SPDX-License-Identifier: GPL-3.0-or-later
% Row-aligned numerical derivative dy/dx, independently per group.
function R = gxtxt_analysis_op_derivative(x,y,group)
  if(nargin<3),group=[];endif;x=x(:);y=y(:);n=numel(x);if(numel(y)!=n),error('GXTXT:AnalysisDerivative','x/y length mismatch');endif
  [~,gidx,~]=gxtxt_analysis_group_index(group,n);v=NaN(n,1);st=repmat({'unavailable'},n,1);rs=repmat({'insufficient_data'},n,1);
  for gi=1:numel(gidx)
    idx=gidx{gi};xx=x(idx);yy=y(idx);good=isfinite(xx)&isfinite(yy);ig=idx(good);xx=xx(good);yy=yy(good);
    if(numel(xx)<2),continue;endif
    d=NaN(numel(xx),1);
    for k=1:numel(xx)
      if(k==1),a=1;b=2;elseif(k==numel(xx)),a=numel(xx)-1;b=numel(xx);else a=k-1;b=k+1;endif
      dx=xx(b)-xx(a);if(dx!=0),d(k)=(yy(b)-yy(a))/dx;endif
    endfor
    ok=isfinite(d);v(ig(ok))=d(ok);st(ig(ok))={'valid'};rs(ig(ok))={''};bad=!ok;rs(ig(bad))={'duplicate_x'};
  endfor
  R=struct('values',v,'status',{st},'reason',{rs});
endfunction
