% SPDX-License-Identifier: GPL-3.0-or-later
% Generic target crossing feature extraction for Scientific Analysis API v1.
%
% F = gxtxt_analysis_op_crossing(x,y,target,group,interpolation,extrapolation)
%
% F contains one result per group and a row-aligned broadcast:
%   group_values, values, status, reason, broadcast, broadcast_status,
%   broadcast_reason.  Status values are valid|warning|unavailable|failed.
function F = gxtxt_analysis_op_crossing(x,y,target,group,interpolation,extrapolation)
  if (nargin<4), group=[]; endif
  if (nargin<5 || isempty(interpolation)), interpolation='linear'; endif
  if (nargin<6 || isempty(extrapolation)), extrapolation='forbid'; endif
  interpolation=lower(strtrim(interpolation)); extrapolation=lower(strtrim(extrapolation));
  if (!strcmp(interpolation,'linear')), error('GXTXT:AnalysisCrossing','Only interpolation=linear is supported in API v1'); endif
  if (!any(strcmp(extrapolation,{'forbid','forbidden','false','0','none'})))
    error('GXTXT:AnalysisCrossing','Only extrapolation=forbid is supported in API v1');
  endif
  if (!isnumeric(x) || !isnumeric(y)), error('GXTXT:AnalysisCrossing','x and y must be numeric'); endif
  x=x(:); y=y(:); n=numel(x);
  if (numel(y)!=n), error('GXTXT:AnalysisCrossing','x/y length mismatch'); endif
  if (!isscalar(target) || !isnumeric(target) || !isfinite(target)), error('GXTXT:AnalysisCrossing','target must be one finite numeric scalar'); endif
  [gvals,gidx,gkind]=group_index(group,n);
  ng=numel(gidx);
  vals=NaN(ng,1); status=cell(ng,1); reason=cell(ng,1);
  broadcast=NaN(n,1); bstatus=repmat({'unavailable'},n,1); breason=repmat({''},n,1);
  for gi=1:ng
    idx=gidx{gi}; xx=x(idx); yy=y(idx);
    good=isfinite(xx)&isfinite(yy); xx=xx(good); yy=yy(good);
    if (isempty(xx))
      status{gi}='unavailable'; reason{gi}='invalid_input';
    else
      z=yy-target; cand=[];
      exact=find(z==0);
      if (!isempty(exact)), cand=[cand; xx(exact)]; endif %#ok<AGROW>
      if (numel(xx)>=2)
        for k=1:numel(xx)-1
          if (z(k)==0 || z(k+1)==0), continue; endif
          if (z(k)*z(k+1)<0)
            if (xx(k)==xx(k+1)), continue; endif
            q=xx(k)+(target-yy(k))*(xx(k+1)-xx(k))/(yy(k+1)-yy(k));
            if (isfinite(q)), cand(end+1,1)=q; endif %#ok<AGROW>
          endif
        endfor
      endif
      cand=unique_tol(cand);
      if (numel(cand)==1)
        vals(gi)=cand(1); status{gi}='valid'; reason{gi}='';
      elseif (numel(cand)>1)
        status{gi}='unavailable'; reason{gi}='ambiguous_crossing';
      elseif (numel(xx)<2)
        status{gi}='unavailable'; reason{gi}='insufficient_data';
      else
        status{gi}='unavailable'; reason{gi}='target_not_reached';
      endif
    endif
    broadcast(idx)=vals(gi);
    bstatus(idx)=repmat(status(gi),numel(idx),1);
    breason(idx)=repmat(reason(gi),numel(idx),1);
  endfor
  F=struct('group_values',{gvals},'group_kind',gkind,'values',vals,'status',{status},'reason',{reason}, ...
           'broadcast',broadcast,'broadcast_status',{bstatus},'broadcast_reason',{breason});
endfunction

function [vals,idx,kind]=group_index(group,n)
  if (isempty(group))
    vals={'__global__'}; idx={find(true(n,1))}; kind='global'; return;
  endif
  if (numel(group)!=n), error('GXTXT:AnalysisCrossing','group length mismatch'); endif
  if (iscell(group))
    kind='string'; vals=unique(group,'stable'); idx=cell(numel(vals),1);
    for i=1:numel(vals), idx{i}=find(strcmp(group,vals{i})); endfor
  elseif (isnumeric(group) || islogical(group))
    kind='numeric'; finite=isfinite(group(:)); valsn=unique(group(finite),'stable'); vals=num2cell(valsn(:)); idx=cell(numel(vals),1);
    for i=1:numel(vals), idx{i}=find(group(:)==vals{i}); endfor
  else
    error('GXTXT:AnalysisCrossing','group must be numeric, logical or cell-string');
  endif
endfunction

function out=unique_tol(v)
  v=v(isfinite(v));
  if (isempty(v)), out=[]; return; endif
  out=v(1);
  for i=2:numel(v)
    tol=max(1e-12,1e-10*max(1,abs(v(i))));
    if (all(abs(out-v(i))>tol)), out(end+1,1)=v(i); endif %#ok<AGROW>
  endfor
endfunction
