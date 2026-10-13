% SPDX-License-Identifier: GPL-3.0-or-later
% Per-group extrema feature. mode=max|min, return_kind=x|y.
function F = gxtxt_analysis_op_extrema(x,y,group,mode,return_kind)
  if(nargin<3),group=[];endif;if(nargin<4||isempty(mode)),mode='max';endif;if(nargin<5||isempty(return_kind)),return_kind='x';endif
  mode=lower(strtrim(mode));return_kind=lower(strtrim(return_kind));
  if(!any(strcmp(mode,{'max','min'}))),error('GXTXT:AnalysisExtrema','mode must be max|min');endif
  if(!any(strcmp(return_kind,{'x','y'}))),error('GXTXT:AnalysisExtrema','return must be x|y');endif
  x=x(:);y=y(:);n=numel(x);if(numel(y)!=n),error('GXTXT:AnalysisExtrema','x/y length mismatch');endif
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(group,n);ng=numel(gidx);vals=NaN(ng,1);st=cell(ng,1);rs=cell(ng,1);bc=NaN(n,1);bs=cell(n,1);br=cell(n,1);
  for gi=1:ng
    idx=gidx{gi};good=isfinite(x(idx))&isfinite(y(idx));ii=idx(good);
    if(isempty(ii)),st{gi}='unavailable';rs{gi}='invalid_input';
    else
      yy=y(ii);if(strcmp(mode,'max')),v=max(yy);else v=min(yy);endif;hit=ii(yy==v);
      if(numel(hit)!=1),st{gi}='unavailable';rs{gi}='ambiguous_extremum';
      else vals(gi)=x(hit);if(strcmp(return_kind,'y')),vals(gi)=y(hit);endif;st{gi}='valid';rs{gi}='';endif
    endif
    bc(idx)=vals(gi);bs(idx)=repmat(st(gi),numel(idx),1);br(idx)=repmat(rs(gi),numel(idx),1);
  endfor
  F=struct('group_values',{gvals},'group_kind',gkind,'values',vals,'status',{st},'reason',{rs},'broadcast',bc,'broadcast_status',{bs},'broadcast_reason',{br});
endfunction
