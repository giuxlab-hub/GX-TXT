% Candidate processing sequence only. Never changes coordinate values.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_point_sequence_order_v1(points,options)
  if(nargin<2),options=struct();endif
  if(!isnumeric(points)||!isreal(points)||columns(points)<2||columns(points)>3||rows(points)<2||rows(points)>4096||any(!isfinite(points(:))))
    error('GXTXT:Numeric','Point sequence needs 2..4096 finite XY/XYZ points');
  endif
  n=rows(points);policy='x_monotone';start=1;
  if(isfield(options,'policy')),policy=options.policy;endif
  if(isfield(options,'start_index')),start=options.start_index+1;endif
  if(!isscalar(start)||start!=fix(start)||start<1||start>n),error('GXTXT:Numeric','Invalid explicit starting point');endif
  warnings={};ambiguous=[];segments=1;scale=1;closed_endpoint=false;
  if(strcmp(policy,'x_monotone'))
    [~,order]=sortrows([points(:,1),(1:n)'],[1 2]);
    if(any(diff(points(order,1))<=0)),warnings{end+1}='Duplicate X cannot define a single-valued strictly increasing function';endif
  elseif(strcmp(policy,'geometry_auto'))
    scale=max(abs(points(:)));if(scale==0),scale=1;endif
    metric=points/scale;
    order=zeros(n,1);order(1)=start;available=true(n,1);available(start)=false;
    last=n;
    % An explicitly repeated closing observation is a distinct source identity.
    % Keep it at the end instead of greedily taking its zero-distance duplicate
    % first and introducing an invalid zero-length initial segment.
    if(start==1&&n>2&&all(points(1,:)==points(n,:)))
      closed_endpoint=true;available(n)=false;order(n)=n;last=n-1;
      warnings{end+1}='Explicit repeated closing endpoint retained at the end; interior connectivity still requires review';
    endif
    for k=2:last
      candidates=find(available);delta=metric(candidates,:)-metric(order(k-1),:);
      distance=sum(delta.^2,2);[sorted,rank]=sortrows([distance,candidates],[1 2]);
      if(rows(sorted)>1&&sorted(2,1)<=sorted(1,1)*(1+1e-8)+32*eps(max(1,sorted(2,1))))
        ambiguous(end+1)=k-1;
      endif
      order(k)=candidates(rank(1));available(order(k))=false;
    endfor
    if(!isempty(ambiguous)),warnings{end+1}='Several neighbors have indistinguishable distance; review candidate links';endif
    lengths=sqrt(sum(diff(metric(order,:),1,1).^2,2));positive=lengths(lengths>0);
    if(any(lengths==0)),warnings{end+1}='Coincident coordinates retain distinct original identities';endif
    if(!isempty(positive))
      segments=[1;find(lengths>8*median(positive))+1];
      if(numel(segments)>1),warnings{end+1}='Long gaps may represent disconnected segments; candidate is not one continuous trace';endif
    endif
    if(columns(points)==2||max(points(:,3))-min(points(:,3))<=32*eps(max(1,max(abs(points(:,3))))))
      if(crossings(metric(:,1:2))||crossings(metric(order,1:2)))
        warnings{end+1}='Crossings in original/candidate trace do not determine the physical topology';
      endif
    else
      warnings{end+1}='3D topology cannot be inferred from nearest-neighbor distance alone';
    endif
    warnings{end+1}='Starting endpoint is the explicit selected original ordinal; a shorter route is not experimental ground truth';
  else
    error('GXTXT:Numeric','Point sequence policy must be x_monotone or geometry_auto');
  endif
  inverse=zeros(n,1);inverse(order)=0:n-1;
  out=struct('permutation',order-1,'inverse_permutation',inverse,'points',points(order,:),...
    'policy',policy,'algorithm','stable_x_or_greedy_nearest_v2','changed_count',sum(order!=(1:n)'),...
    'closed_endpoint_preserved',closed_endpoint,...
    'start_index',start-1,'distance_scale',scale,'segment_starts',segments-1,'ambiguous_positions',ambiguous,...
    'warnings',{warnings},'review_required',strcmp(policy,'geometry_auto')||!isempty(warnings));
endfunction
function count=crossings(p)
  count=0;n=rows(p);
  for i=3:n-1
    a=p(i,:);b=p(i+1,:);c=p(1:i-2,:);d=p(2:i-1,:);
    ab=b-a;cd=d-c;
    u=ab(1)*(c(:,2)-a(2))-ab(2)*(c(:,1)-a(1));v=ab(1)*(d(:,2)-a(2))-ab(2)*(d(:,1)-a(1));
    w=cd(:,1).*(a(2)-c(:,2))-cd(:,2).*(a(1)-c(:,1));z=cd(:,1).*(b(2)-c(:,2))-cd(:,2).*(b(1)-c(:,1));
    count+=sum((u.*v<0)&(w.*z<0));
  endfor
endfunction
