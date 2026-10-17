% SPDX-License-Identifier: GPL-3.0-or-later
% Pearson correlation as a per-group feature.
function F = gxtxt_analysis_op_correlate(x,y,group,context)
  if(nargin<4),context=struct();endif
  if(nargin<3),group=[];endif;x=x(:);y=y(:);n=numel(x);if(numel(y)!=n),error('GXTXT:AnalysisCorrelate','x/y length mismatch');endif
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(group,n);ng=numel(gidx);vals=NaN(ng,1);st=cell(ng,1);rs=cell(ng,1);bc=NaN(n,1);bs=cell(n,1);br=cell(n,1);
  semantics=cell(ng,1);
  for gi=1:ng
    idx=gidx{gi};good=isfinite(x(idx))&isfinite(y(idx));xx=x(idx);yy=y(idx);xx=xx(good);yy=yy(good);
    if(numel(xx)<2),st{gi}='unavailable';rs{gi}='insufficient_data';
    else
      numeric=gxtxt_analysis_numeric_call('correlation',xx,yy,struct('method','pearson'));
      semantics{gi}=gxtxt_statistics_v1('from_numeric','math.numeric.summary','correlation',numeric,context);
      feature=gxtxt_statistics_v1('feature',semantics{gi},'correlation');
      vals(gi)=feature.value;st{gi}=feature.status;rs{gi}=feature.reason;
    endif
    bc(idx)=vals(gi);bs(idx)=repmat(st(gi),numel(idx),1);br(idx)=repmat(rs(gi),numel(idx),1);
  endfor
  F=struct('group_values',{gvals},'group_kind',gkind,'values',vals,'status',{st},'reason',{rs},'broadcast',bc,'broadcast_status',{bs},'broadcast_reason',{br});
  F.statistical_results=semantics;
endfunction
