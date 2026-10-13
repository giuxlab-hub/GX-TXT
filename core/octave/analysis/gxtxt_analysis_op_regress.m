% SPDX-License-Identifier: GPL-3.0-or-later
% Linear least-squares regression y = intercept + slope*x, independently per group.
function R = gxtxt_analysis_op_regress(x,y,group)
  if(nargin<3),group=[];endif;x=x(:);y=y(:);n=numel(x);if(numel(y)!=n),error('GXTXT:AnalysisRegress','x/y length mismatch');endif
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(group,n);ng=numel(gidx);pred=NaN(n,1);slope=NaN(ng,1);intercept=NaN(ng,1);r2=NaN(ng,1);st=cell(ng,1);rs=cell(ng,1);bs=repmat({'unavailable'},n,1);br=repmat({''},n,1);
  for gi=1:ng
    idx=gidx{gi};good=isfinite(x(idx))&isfinite(y(idx));ii=idx(good);xx=x(ii);yy=y(ii);
    if(numel(xx)<2),st{gi}='unavailable';rs{gi}='insufficient_data';
    elseif(std(xx)==0),st{gi}='unavailable';rs{gi}='zero_variance';
    else
      A=[ones(numel(xx),1) xx];b=A\yy;intercept(gi)=b(1);slope(gi)=b(2);yp=A*b;pred(ii)=yp;
      ssr=sum((yy-yp).^2);sst=sum((yy-mean(yy)).^2);if(sst==0),r2(gi)=NaN;else r2(gi)=1-ssr/sst;endif
      st{gi}='valid';rs{gi}='';bs(idx)={'valid'};br(idx)={''};
    endif
    if(!strcmp(st{gi},'valid')),bs(idx)=repmat(st(gi),numel(idx),1);br(idx)=repmat(rs(gi),numel(idx),1);endif
  endfor
  R=struct('predicted',pred,'group_values',{gvals},'group_kind',gkind,'slope',slope,'intercept',intercept,'r2',r2,'status',{st},'reason',{rs},'broadcast_status',{bs},'broadcast_reason',{br});
endfunction
