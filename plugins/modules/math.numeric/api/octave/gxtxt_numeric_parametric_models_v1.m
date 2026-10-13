% Ordered parametric models. Public authority: NUMERIC_API_v1 curve_model_*.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_parametric_models_v1(operation,varargin)
  if(strcmp(operation,'fit'))
    name=varargin{1};points=[varargin{2}(:),varargin{3}(:)];opts=varargin{4};
    mode=option(opts,'parameterization','row_order');topology=option(opts,'topology','auto');
    if(!any(strcmp(mode,{'row_order','path_length','user_parameter'}))),error('GXTXT:Numeric','unknown parameterization');endif
    if(!any(strcmp(topology,{'open','closed','auto'}))),error('GXTXT:Numeric','topology must be open, closed or auto');endif
    scale=max(1,norm(max(points)-min(points)));
    tolerance=option(opts,'closure_tolerance',1e-9*scale);
    if(!isscalar(tolerance)||!isfinite(tolerance)||tolerance<0),error('GXTXT:Numeric','closure tolerance must be finite and nonnegative');endif
    endpoint_distance=norm(points(end,:)-points(1,:));repeated=endpoint_distance<=tolerance;
    closed=strcmp(topology,'closed')||(strcmp(topology,'auto')&&repeated);
    if(strcmp(name,'parametric_polynomial')&&closed),error('GXTXT:Numeric','closed polynomial fitting requires a periodic model; choose parametric_spline');endif
    original_count=rows(points);
    if(closed&&repeated),points=points(1:end-1,:);endif
    n=rows(points);
    if(n<3),error('GXTXT:Numeric','parametric curves require at least three independent nodes');endif
    closing=norm(points(1,:)-points(end,:));
    if(strcmp(mode,'row_order'))
      denominator=n-1;if(closed),denominator=n;endif
      t=(0:n-1).'/denominator;
    elseif(strcmp(mode,'path_length'))
      lengths=hypot(diff(points(:,1)),diff(points(:,2)));
      if(any(lengths<=0)),error('GXTXT:Numeric','path parameterization requires nonzero consecutive segments');endif
      total=sum(lengths);if(closed),total+=closing;endif
      if(total<=0),error('GXTXT:Numeric','curve has no path length');endif
      t=[0;cumsum(lengths)]/total;
    else
      if(!isfield(opts,'user_parameter')),error('GXTXT:Numeric','user_parameter is required');endif
      supplied=double(opts.user_parameter(:));
      if(numel(supplied)!=original_count||any(!isfinite(supplied))),error('GXTXT:Numeric','user parameters must be finite and align with every original row');endif
      delta=diff(supplied);
      if(!(all(delta>0)||all(delta<0))),error('GXTXT:Numeric','user parameters must be strictly monotone in source order');endif
      if(closed&&!repeated)
        if(!isfield(opts,'user_period')),error('GXTXT:Numeric','closed user parameters without a repeated endpoint require user_period');endif
        period=double(opts.user_period);
        if(!isscalar(period)||!isfinite(period)||period<=abs(supplied(end)-supplied(1))),error('GXTXT:Numeric','user period must exceed the open parameter span');endif
        denominator=sign(delta(1))*period;
      else,denominator=supplied(end)-supplied(1);endif
      t=(supplied-supplied(1))/denominator;
      if(closed&&repeated),t=t(1:end-1);endif
    endif
    out=struct('model',name,'parametric',true,'topology',ternary(closed,'closed','open'),...
      'requested_topology',topology,'parameterization',mode,'parameter_start',0,'parameter_end',1,...
      'closure_tolerance',tolerance,'source_endpoint_distance',endpoint_distance,...
      'repeated_endpoint_removed',closed&&repeated,'source_count',original_count,'parameters',[]);
    if(strcmp(mode,'user_parameter'))
      out.parameter_source_start=supplied(1);out.parameter_source_end=supplied(end);
      out.parameter_normalization_span=denominator;
      if(closed&&!repeated),out.parameter_source_period=abs(denominator);endif
    elseif(strcmp(mode,'path_length')),out.parameter_path_length=total;endif
    if(strcmp(name,'parametric_polynomial'))
      degree=option(opts,'degree',3);
      if(!isscalar(degree)||!isfinite(degree)||degree<1||degree>12||degree!=fix(degree)||n<=degree),error('GXTXT:Numeric','parametric polynomial degree must be 1..12 with more independent nodes');endif
      fx=gxtxt_numeric_v1('polynomial_fit',t,points(:,1),degree,[],struct());
      fy=gxtxt_numeric_v1('polynomial_fit',t,points(:,2),degree,[],struct());
      out.coefficients=[fx.coefficients(:),fy.coefficients(:)];out.degree=degree;
      out.parameters=out.coefficients(:);
    else
      if(closed)
        knots=[t;1];nodes=[points;points(1,:)];h=diff(knots);i=(1:n).';next=[(2:n).';1];
        R=sparse([i;i;next;next],[i;next;i;next],[h/3;h/6;h/6;h/3],n,n);
        slopes=diff(nodes)./h;previous=[n;(1:n-1).'];
        M=R\(slopes-slopes(previous,:));M=[M;M(1,:)];
      else
        knots=t;nodes=points;M=zeros(n,2);
        for axis=1:2
          state=gxtxt_numeric_v1('curve_model_fit','smoothing_spline',knots,nodes(:,axis),struct('smoothing_lambda',0));
          M(:,axis)=state.second_derivatives;
        endfor
      endif
      h=diff(knots);a=h.^2.*diff(M)/6;b=h.^2.*M(1:end-1,:)/2;
      c=diff(nodes)-h.^2.*(2*M(1:end-1,:)+M(2:end,:))/6;d=nodes(1:end-1,:);
      out.knots=knots;out.coefficients_x=[a(:,1),b(:,1),c(:,1),d(:,1)];
      out.coefficients_y=[a(:,2),b(:,2),c(:,2),d(:,2)];
      out.boundary_condition=ternary(closed,'periodic_value_first_and_second_derivative','natural_zero_endpoint_second_derivative');
    endif
  elseif(strcmp(operation,'evaluate'))
    state=varargin{1};q=double(varargin{2}(:));
    if(any(!isfinite(q))||any(q<0)||any(q>1)),error('GXTXT:Numeric','parametric queries must be finite within [0,1]');endif
    if(strcmp(state.model,'parametric_polynomial'))
      cx=state.coefficients(:,1).';cy=state.coefficients(:,2).';
      x=polyval(cx,q);y=polyval(cy,q);tx=polyval(polyder(cx),q);ty=polyval(polyder(cy),q);
      ax=polyval(polyder(polyder(cx)),q);ay=polyval(polyder(polyder(cy)),q);
    else
      i=min(lookup(state.knots,q),numel(state.knots)-1);h=state.knots(i+1)-state.knots(i);
      u=(q-state.knots(i))./h;cx=state.coefficients_x(i,:);cy=state.coefficients_y(i,:);
      x=((cx(:,1).*u+cx(:,2)).*u+cx(:,3)).*u+cx(:,4);
      y=((cy(:,1).*u+cy(:,2)).*u+cy(:,3)).*u+cy(:,4);
      tx=((3*cx(:,1).*u+2*cx(:,2)).*u+cx(:,3))./h;
      ty=((3*cy(:,1).*u+2*cy(:,2)).*u+cy(:,3))./h;
      ax=(6*cx(:,1).*u+2*cx(:,2))./h.^2;ay=(6*cy(:,1).*u+2*cy(:,2))./h.^2;
    endif
    out=struct('x',x,'y',y,'points',[x,y],'tangent_x',tx,'tangent_y',ty,'second_x',ax,'second_y',ay);
  elseif(strcmp(operation,'project'))
    state=varargin{1};x=double(varargin{2}(:));y=double(varargin{3}(:));
    if(numel(x)!=numel(y)||any(!isfinite(x))||any(!isfinite(y))),error('GXTXT:Numeric','projection requires finite paired coordinates');endif
    if(strcmp(state.model,'parametric_spline')&&exist('gxtxt_numeric_cubic_project_native','file')==3)
      [v,diagnostics]=gxtxt_numeric_cubic_project_native(state.coefficients_x,state.coefficients_y,state.knots,x,y);
      out=struct('x',v(:,1),'y',v(:,2),'parameter',v(:,3),'distance',v(:,4),'points',v(:,1:2),...
        'projection_search','exact_stationary_roots_with_native_control_hull_bvh','projection_diagnostics',diagnostics);
      return;
    endif
    if(strcmp(state.model,'parametric_polynomial'))
      cx=state.coefficients(:,1).';cy=state.coefficients(:,2).';knots=[0;1];
      lower=[-Inf,-Inf];upper=[Inf,Inf];
    else
      cx=state.coefficients_x;cy=state.coefficients_y;knots=state.knots;
      % The cubic Bezier control hull encloses the whole polynomial segment.
      bx=[cx(:,4),cx(:,4)+cx(:,3)/3,cx(:,4)+2*cx(:,3)/3+cx(:,2)/3,sum(cx,2)];
      by=[cy(:,4),cy(:,4)+cy(:,3)/3,cy(:,4)+2*cy(:,3)/3+cy(:,2)/3,sum(cy,2)];
      lower=[min(bx,[],2),min(by,[],2)];upper=[max(bx,[],2),max(by,[],2)];
    endif
    t=zeros(size(x));px=t;py=t;
    for j=1:numel(x)
      best=Inf;
      for segment=1:rows(cx)
        boxdelta=max(0,max(lower(segment,:)-[x(j),y(j)],[x(j),y(j)]-upper(segment,:)));
        if(sum(boxdelta.^2)>best),continue;endif
        a=cx(segment,:);b=cy(segment,:);a(end)-=x(j);b(end)-=y(j);
        degree=columns(cx)-1;
        stationary=conv(a,(degree:-1:1).*a(1:end-1))+conv(b,(degree:-1:1).*b(1:end-1));r=roots(stationary);
        candidates=[0;1;real(r(abs(imag(r))<=1e-9 & real(r)>=0 & real(r)<=1))];
        vx=polyval(cx(segment,:),candidates);vy=polyval(cy(segment,:),candidates);
        [distance,k]=min((vx-x(j)).^2+(vy-y(j)).^2);
        if(distance<best)
          best=distance;px(j)=vx(k);py(j)=vy(k);
          t(j)=knots(segment)+candidates(k)*(knots(segment+1)-knots(segment));
        endif
      endfor
    endfor
    out=struct('x',px,'y',py,'parameter',t,'distance',hypot(px-x,py-y),'points',[px,py],...
      'projection_search','exact_stationary_roots_with_control_hull_pruning');
  else,error('GXTXT:Numeric','unknown parametric operation');endif
endfunction
function value=option(opts,name,fallback)
  value=fallback;if(isfield(opts,name)),value=opts.(name);endif
endfunction
function value=ternary(test,yes,no)
  if(test),value=yes;else,value=no;endif
endfunction
