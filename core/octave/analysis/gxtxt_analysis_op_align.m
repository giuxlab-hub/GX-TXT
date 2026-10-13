% SPDX-License-Identifier: GPL-3.0-or-later
% Align values sampled on source_x onto target_x.
% method: exact | nearest | linear
% extrapolation: forbid | linear | nearest
% tolerance: [] means unlimited for nearest and exact numeric equality for exact.
% target_group/source_group are optional and force independent alignment within
% matching groups.  This prevents accidental cross-family interpolation.
function R = gxtxt_analysis_op_align(target_x,source_x,source_y,method,tolerance,extrapolation,target_group,source_group)
  if(nargin<4||isempty(method)),method='exact';endif
  if(nargin<5),tolerance=[];endif
  if(nargin<6||isempty(extrapolation)),extrapolation='forbid';endif
  if(nargin<7),target_group=[];endif;if(nargin<8),source_group=[];endif
  method=lower(strtrim(method));extrapolation=lower(strtrim(extrapolation));
  if(!isnumeric(target_x)||!isnumeric(source_x)||!isnumeric(source_y)),error('GXTXT:AnalysisAlign','target_x/source_x/source_y must be numeric');endif
  tx=target_x(:);sx=source_x(:);sy=source_y(:);
  if(numel(sx)!=numel(sy)),error('GXTXT:AnalysisAlign','source_x/source_y length mismatch');endif
  if(!isempty(tolerance)&&(!isscalar(tolerance)||!isfinite(tolerance)||tolerance<0)),error('GXTXT:AnalysisAlign','tolerance must be empty or finite >=0');endif
  if(!any(strcmp(method,{'exact','nearest','linear'}))),error('GXTXT:AnalysisAlign','unsupported method: %s',method);endif
  if(!any(strcmp(extrapolation,{'forbid','linear','nearest'}))),error('GXTXT:AnalysisAlign','unsupported extrapolation: %s',extrapolation);endif

  if(!isempty(target_group)||!isempty(source_group))
    if(isempty(target_group)||isempty(source_group)),error('GXTXT:AnalysisAlign','target_group and source_group must be supplied together');endif
    if(numel(target_group)!=numel(tx)||numel(source_group)!=numel(sx)),error('GXTXT:AnalysisAlign','group length mismatch');endif
    R=grouped_align(tx,sx,sy,method,tolerance,extrapolation,target_group,source_group);return;
  endif
  R=plain_align(tx,sx,sy,method,tolerance,extrapolation);
endfunction

function R=grouped_align(tx,sx,sy,method,tolerance,extrapolation,tg,sg)
  n=numel(tx);v=NaN(n,1);st=repmat({'unavailable'},n,1);rs=repmat({'group_not_found'},n,1);srcidx=NaN(n,2);
  [gvals,gidx,gkind]=gxtxt_analysis_group_index(tg,n);
  [sgvals,sgidx,sgkind]=gxtxt_analysis_group_index(sg,numel(sx));
  if(!strcmp(gkind,sgkind)&&!(strcmp(gkind,'numeric')&&strcmp(sgkind,'numeric'))),error('GXTXT:AnalysisAlign','target/source group types are incompatible');endif
  for gi=1:numel(gidx)
    sk=find_group(sgvals,sgkind,gvals{gi});if(sk==0),continue;endif
    ti=gidx{gi};si=sgidx{sk};A=plain_align(tx(ti),sx(si),sy(si),method,tolerance,extrapolation);
    v(ti)=A.values;st(ti)=A.status;rs(ti)=A.reason;local=A.source_indices;
    for r=1:size(local,1),for c=1:size(local,2),if(isfinite(local(r,c))),local(r,c)=si(local(r,c));endif;endfor;endfor
    srcidx(ti,:)=local;
  endfor
  R=struct('values',v,'status',{st},'reason',{rs},'source_indices',srcidx,'method',method,'extrapolation',extrapolation,'grouped',true);
endfunction

function k=find_group(vals,kind,q)
  k=0;if(strcmp(kind,'string')),for i=1:numel(vals),if(strcmp(vals{i},q)),k=i;return;endif;endfor;else for i=1:numel(vals),if(vals{i}==q),k=i;return;endif;endfor;endif
endfunction

function R=plain_align(tx,sx,sy,method,tolerance,extrapolation)
  n=numel(tx);v=NaN(n,1);st=repmat({'unavailable'},n,1);rs=repmat({''},n,1);srcidx=NaN(n,2);
  good=isfinite(sx)&isfinite(sy);orig=find(good);sx=sx(good);sy=sy(good);
  if(isempty(sx)),rs(:)={'invalid_input'};R=struct('values',v,'status',{st},'reason',{rs},'source_indices',srcidx,'method',method,'extrapolation',extrapolation,'grouped',false);return;endif
  [ss,ord]=sort(sx);yy=sy(ord);oo=orig(ord);
  for i=1:n
    q=tx(i);if(!isfinite(q)),rs{i}='invalid_input';continue;endif
    switch method
      case 'exact'
        d=abs(ss-q);if(isempty(tolerance)),hit=find(d==0);else hit=find(d<=tolerance);endif
        if(numel(hit)==1),v(i)=yy(hit);st{i}='valid';srcidx(i,1)=oo(hit);
        elseif(numel(hit)>1),rs{i}='ambiguous_match';else rs{i}='unmatched';endif
      case 'nearest'
        [d,k]=min(abs(ss-q));
        if(!isempty(tolerance)&&d>tolerance),rs{i}='no_match_within_tolerance';continue;endif
        v(i)=yy(k);st{i}='valid';srcidx(i,1)=oo(k);
      case 'linear'
        exact=find(ss==q);
        if(numel(exact)==1),v(i)=yy(exact);st{i}='valid';srcidx(i,1)=oo(exact);continue;
        elseif(numel(exact)>1),rs{i}='ambiguous_match';continue;endif
        lo=find(ss<q,1,'last');hi=find(ss>q,1,'first');
        if(isempty(lo)||isempty(hi))
          if(strcmp(extrapolation,'forbid')),rs{i}='outside_domain';continue;endif
          if(strcmp(extrapolation,'nearest')),[~,k]=min(abs(ss-q));v(i)=yy(k);st{i}='warning';rs{i}='extrapolated_nearest';srcidx(i,1)=oo(k);continue;endif
          if(numel(ss)<2),rs{i}='insufficient_data';continue;endif
          if(isempty(lo)),lo=1;hi=2;else lo=numel(ss)-1;hi=numel(ss);endif
          warn='extrapolated_linear';
        else
          warn='';
        endif
        if(ss(hi)==ss(lo)),rs{i}='ambiguous_match';continue;endif
        v(i)=yy(lo)+(q-ss(lo))*(yy(hi)-yy(lo))/(ss(hi)-ss(lo));srcidx(i,:)=[oo(lo) oo(hi)];
        if(isempty(warn)),st{i}='valid';else st{i}='warning';rs{i}=warn;endif
    endswitch
  endfor
  R=struct('values',v,'status',{st},'reason',{rs},'source_indices',srcidx,'method',method,'extrapolation',extrapolation,'grouped',false);
endfunction
