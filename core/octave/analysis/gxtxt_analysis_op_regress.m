% SPDX-License-Identifier: GPL-3.0-or-later
% Linear least-squares regression y = intercept + slope*x, independently per group.
function R = gxtxt_analysis_op_regress(x,y,group,context)
  if(nargin<4),context=struct();endif;context.constraints='none';
  if(nargin<3),group=[];endif;x=x(:);y=y(:);n=numel(x);if(numel(y)!=n),error('GXTXT:AnalysisRegress','x/y length mismatch');endif
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(group,n);ng=numel(gidx);pred=NaN(n,1);slope=NaN(ng,1);intercept=NaN(ng,1);r2=NaN(ng,1);st=cell(ng,1);rs=cell(ng,1);bs=repmat({'unavailable'},n,1);br=repmat({''},n,1);
  semantics=cell(ng,1);r2_status=repmat({'unavailable'},ng,1);r2_reason=repmat({'Fit unavailable'},ng,1);
  for gi=1:ng
    idx=gidx{gi};good=isfinite(x(idx))&isfinite(y(idx));ii=idx(good);xx=x(ii);yy=y(ii);
    if(numel(xx)<2),st{gi}='unavailable';rs{gi}='insufficient_data';
    elseif(all(xx==xx(1))),st{gi}='unavailable';rs{gi}='zero_variance';
    else
      fit=gxtxt_analysis_numeric_call('linear_regression',xx,yy);
      semantics{gi}=gxtxt_statistics_v1('from_numeric','math.numeric.linear','linear_regression',fit,context);
      if(fit.rank<2),st{gi}='unavailable';rs{gi}='rank_deficient';r2_reason{gi}='Numerical linear design is rank deficient';
      else
        intercept(gi)=fit.intercept;slope(gi)=fit.slope;pred(ii)=fit.predicted;
        feature=gxtxt_statistics_v1('feature',semantics{gi},'r_squared');
        r2(gi)=feature.value;r2_status{gi}=feature.status;r2_reason{gi}=feature.reason;
        st{gi}='valid';rs{gi}='';bs(idx)={'valid'};br(idx)={''};
      endif
    endif
    if(!strcmp(st{gi},'valid')),bs(idx)=repmat(st(gi),numel(idx),1);br(idx)=repmat(rs(gi),numel(idx),1);endif
  endfor
  R=struct('predicted',pred,'group_values',{gvals},'group_kind',gkind,'slope',slope,'intercept',intercept,'r2',r2,'status',{st},'reason',{rs},'broadcast_status',{bs},'broadcast_reason',{br});
  R.statistical_results=semantics;R.r2_status=r2_status;R.r2_reason=r2_reason;
endfunction
