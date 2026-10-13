% SPDX-License-Identifier: GPL-3.0-or-later
% Pearson correlation as a per-group feature.
function F = gxtxt_analysis_op_correlate(x,y,group)
  if(nargin<3),group=[];endif;x=x(:);y=y(:);n=numel(x);if(numel(y)!=n),error('GXTXT:AnalysisCorrelate','x/y length mismatch');endif
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(group,n);ng=numel(gidx);vals=NaN(ng,1);st=cell(ng,1);rs=cell(ng,1);bc=NaN(n,1);bs=cell(n,1);br=cell(n,1);
  for gi=1:ng
    idx=gidx{gi};good=isfinite(x(idx))&isfinite(y(idx));xx=x(idx);yy=y(idx);xx=xx(good);yy=yy(good);
    if(numel(xx)<2),st{gi}='unavailable';rs{gi}='insufficient_data';
    elseif(std(xx)==0||std(yy)==0),st{gi}='unavailable';rs{gi}='zero_variance';
    else C=corrcoef(xx,yy);vals(gi)=C(1,2);st{gi}='valid';rs{gi}='';endif
    bc(idx)=vals(gi);bs(idx)=repmat(st(gi),numel(idx),1);br(idx)=repmat(rs(gi),numel(idx),1);
  endfor
  F=struct('group_values',{gvals},'group_kind',gkind,'values',vals,'status',{st},'reason',{rs},'broadcast',bc,'broadcast_status',{bs},'broadcast_reason',{br});
endfunction
