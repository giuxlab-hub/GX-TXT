% SPDX-License-Identifier: GPL-3.0-or-later
% Generic linear interpolation, optionally independently per group.
% query_group is optional; when omitted and query has same length as group,
% group is also used as query_group.
function R = gxtxt_analysis_op_interpolate(x,y,query,group,query_group,extrapolation)
  if(nargin<4),group=[];endif
  if(nargin<5),query_group=[];endif
  if(nargin<6||isempty(extrapolation)),extrapolation='forbid';endif
  if(!isnumeric(x)||!isnumeric(y)||!isnumeric(query)),error('GXTXT:AnalysisInterpolate','x/y/query must be numeric');endif
  x=x(:);y=y(:);q=query(:);if(numel(x)!=numel(y)),error('GXTXT:AnalysisInterpolate','x/y length mismatch');endif
  if(isempty(group))
    A=gxtxt_analysis_op_align(q,x,y,'linear',[],extrapolation);R=A;return;
  endif
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(group,numel(x));
  if(isempty(query_group))
    if(numel(group)==numel(q)),query_group=group;else error('GXTXT:AnalysisInterpolate','query_group is required when query length differs from group length');endif
  endif
  if(numel(query_group)!=numel(q)),error('GXTXT:AnalysisInterpolate','query_group length mismatch');endif
  v=NaN(numel(q),1);st=repmat({'unavailable'},numel(q),1);rs=repmat({'group_not_found'},numel(q),1);si=NaN(numel(q),2);
  for gi=1:numel(gidx)
    if(strcmp(gkind,'string')),qi=strcmp(query_group,gvals{gi});else qi=(query_group(:)==gvals{gi});endif
    if(!any(qi)),continue;endif
    A=gxtxt_analysis_op_align(q(qi),x(gidx{gi}),y(gidx{gi}),'linear',[],extrapolation);
    v(qi)=A.values;st(qi)=A.status;rs(qi)=A.reason;
    local=A.source_indices;map=gidx{gi};
    for r=1:size(local,1),for c=1:2,if(isfinite(local(r,c))),local(r,c)=map(local(r,c));endif;endfor;endfor
    si(qi,:)=local;
  endfor
  R=struct('values',v,'status',{st},'reason',{rs},'source_indices',si,'group_values',{gvals});
endfunction
