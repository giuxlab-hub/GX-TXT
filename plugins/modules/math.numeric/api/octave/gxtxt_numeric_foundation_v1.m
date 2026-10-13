% Public numerical foundations shared by field and system APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_numeric_foundation_v1(family,action,a,b,c,opts)
  if(nargin!=6||!ischar(family)||!ischar(action)||!isstruct(opts))
    error('GXTXT:Numeric:InvalidArguments','foundation requires family, action, three operands and options');
  endif
  family=lower(strtrim(family));action=lower(strtrim(action));
  switch(family)
    case 'vector',out=vector_action(action,a,b,c,opts);
    case 'tensor',out=tensor_action(action,a,b,c,opts);
    case 'grid',out=grid_action(action,a,b,c,opts);
    case 'scattered',out=scattered_action(action,a,b,c,opts);
    case 'family',out=family_action(action,a,b,c,opts);
    case 'calculus',out=calculus_action(action,a,b,c,opts);
    case 'ode',out=ode_action(a,b,c,opts);
    case 'constrained',out=constrained_action(a,b,c,opts);
    case 'special',out=special_action(action,a,b,opts);
    case {'geometry','sparse','equations','variational','statistics'},out=gxtxt_numeric_advanced_v1(family,action,a,b,c,opts);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown numerical foundation family');
  endswitch
endfunction
function out=family_action(action,x,y,target,opts)
  if(strcmp(action,'parameter_interpolate'))
    finite_numeric(x,'parameter axis');finite_numeric(y,'family matrix');finite_numeric(target,'target parameters');
    if(!isreal(x)||!isvector(x)||any(diff(x(:))<=0)||columns(y)!=numel(x)||!isreal(target))
      error('GXTXT:Numeric:DimensionMismatch','parameter axis must increase and match family columns');
    endif
    policy=option(opts,'extrapolation','error');if(strcmp(policy,'error')&&any(target(:)<x(1)|target(:)>x(end)))
      error('GXTXT:Numeric:Extrapolation','target parameter lies outside family axis');
    endif
    v=interp1(x(:),y.',target(:),option(opts,'method','linear')).';out=split_value(v);out.parameter=target(:);return;
  endif
  if(!iscell(x)||!iscell(y)||numel(x)!=numel(y)||isempty(x)),error('GXTXT:Numeric:DimensionMismatch','family coordinates and values must be matching nonempty cells');endif
  finite_numeric(target,'shared grid');if(!isvector(target)||any(diff(target(:))<=0)),error('GXTXT:Numeric:InvalidGrid','shared grid must strictly increase');endif
  n=numel(x);value=zeros(numel(target),n);policy=option(opts,'extrapolation','error');
  for k=1:n
    xx=x{k}(:);yy=y{k}(:);finite_numeric(xx,'family coordinate');finite_numeric(yy,'family values');
    if(numel(xx)!=numel(yy)||any(diff(xx)<=0)),error('GXTXT:Numeric:InvalidGrid','family coordinates must increase and match values');endif
    if(strcmp(policy,'error')&&any(target(:)<xx(1)|target(:)>xx(end)))
      error('GXTXT:Numeric:Extrapolation','shared grid lies outside a family member');
    endif
    value(:,k)=interp1(xx,yy,target(:),option(opts,'method','linear'));
  endfor
  switch(action)
    case {'align','surface'},out=split_value(value);out.x=target(:);
    case 'derivative',v=zeros(size(value));for k=1:n,v(:,k)=gradient(value(:,k),target(:));endfor;out=split_value(v);out.x=target(:);
    case 'extrema'
      [minimum,index_min]=min(abs(value),[],1);[maximum,index_max]=max(abs(value),[],1);
      out=struct('minimum_magnitude',minimum,'maximum_magnitude',maximum,'minimum_x',target(index_min),'maximum_x',target(index_max));
    case 'envelope',out=struct('minimum_magnitude',min(abs(value),[],2),'maximum_magnitude',max(abs(value),[],2),'x',target(:));
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown family action');
  endswitch
endfunction
function out=tensor_action(action,a,b,c,opts)
  finite_numeric(a,'tensor');if(!ismatrix(a)),error('GXTXT:Numeric:DimensionMismatch','rank-2 tensor must be a matrix');endif
  switch(action)
    case 'transpose',v=a.';
    case 'conjugate_transpose',v=a';
    case 'trace',if(rows(a)!=columns(a)),error('GXTXT:Numeric:DimensionMismatch','trace requires square tensor');endif;v=trace(a);
    case 'symmetric_part',if(rows(a)!=columns(a)),error('GXTXT:Numeric:DimensionMismatch','square tensor required');endif;v=(a+a.')/2;
    case 'antisymmetric_part',if(rows(a)!=columns(a)),error('GXTXT:Numeric:DimensionMismatch','square tensor required');endif;v=(a-a.')/2;
    case 'contract',finite_numeric(b,'second tensor');if(!isequal(size(a),size(b))),error('GXTXT:Numeric:DimensionMismatch','tensor contraction requires matching shapes');endif;v=sum(conj(a(:)).*b(:));
    case 'apply',finite_numeric(b,'vector');if(columns(a)!=numel(b)),error('GXTXT:Numeric:DimensionMismatch','tensor and vector dimensions differ');endif;v=a*b(:);
    case 'outer',finite_numeric(b,'second vector');if(!isvector(a)||!isvector(b)),error('GXTXT:Numeric:DimensionMismatch','outer requires vectors');endif;v=a(:)*conj(b(:)).';
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown tensor action');
  endswitch
  out=split_value(v);
endfunction
function out=scattered_action(action,points,values,query,opts)
  if(!strcmp(action,'interpolate')),error('GXTXT:Numeric:UnknownOperation','unknown scattered action');endif
  finite_numeric(points,'points');finite_numeric(values,'values');finite_numeric(query,'query');
  d=columns(points);if(!ismatrix(points)||!(d==2||d==3)||rows(points)<d+1||numel(values)!=rows(points)||columns(query)!=d)
    error('GXTXT:Numeric:DimensionMismatch','scattered points must be N by 2 or 3 with one value per point');
  endif
  method=option(opts,'method','linear');policy=option(opts,'extrapolation','error');
  if(!any(strcmp(method,{'linear','nearest'}))||!any(strcmp(policy,{'error','nan','nearest'})))
    error('GXTXT:Numeric:InvalidPolicy','unsupported scattered interpolation policy');
  endif
  try
    simplex=tsearchn(points,delaunayn(points),query);outside_hull=isnan(simplex);
  catch err
    error('GXTXT:Numeric:DegeneratePoints','scattered points do not define a reliable interpolation hull: %s',err.message);
  end_try_catch
  if(d==2)
    if(strcmp(method,'nearest')),v=griddata(points(:,1),points(:,2),values(:),query(:,1),query(:,2),'nearest');
    else v=griddata(points(:,1),points(:,2),values(:),query(:,1),query(:,2),'linear');endif
  else
    v=griddata3(points(:,1),points(:,2),points(:,3),values(:),query(:,1),query(:,2),query(:,3),method);
  endif
  outside=outside_hull|isnan(real(v))|isnan(imag(v));
  if(any(outside)&&strcmp(policy,'error')),error('GXTXT:Numeric:Extrapolation','query is outside the scattered interpolation hull');endif
  if(any(outside)&&strcmp(policy,'nearest'))
    for i=find(outside(:)).'
      distances=sum((points-query(i,:)).^2,2);[~,index]=min(distances);v(i)=values(index);
    endfor
  endif
  out=struct('value_real',real(v),'value_imaginary',imag(v),'outside',outside);
endfunction
function finite_numeric(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Numeric:InvalidOperand','%s must be finite and nonempty',name);
  endif
endfunction
function v=option(opts,name,default)
  v=default;if(isfield(opts,name)),v=opts.(name);endif
endfunction
function out=vector_action(action,a,b,c,opts)
  finite_numeric(a,'a');if(!isvector(a)),error('GXTXT:Numeric:DimensionMismatch','a must be a vector');endif
  a=a(:);if(!isempty(b)),finite_numeric(b,'b');b=b(:);endif
  if(!isempty(c)),finite_numeric(c,'c');c=c(:);endif
  if(!isempty(b)&&numel(a)!=numel(b)),error('GXTXT:Numeric:DimensionMismatch','vector lengths differ');endif
  switch(action)
    case 'dot',require_b(b);v=sum(conj(a).*b);
    case 'cross',require_b(b);if(numel(a)!=3),error('GXTXT:Numeric:DimensionMismatch','cross requires three components');endif;v=cross(a,b);
    case 'norm',v=norm(a,option(opts,'p',2));
    case 'normalize',n=norm(a);if(n==0),error('GXTXT:Numeric:ZeroNorm','cannot normalize zero vector');endif;v=a/n;
    case 'outer',require_b(b);v=a*conj(b).';
    case 'projection',require_b(b);d=sum(abs(b).^2);if(d==0),error('GXTXT:Numeric:ZeroNorm','projection basis is zero');endif;v=b*(sum(conj(b).*a)/d);
    case 'angle',require_b(b);if(norm(a)*norm(b)==0),error('GXTXT:Numeric:ZeroNorm','angle requires nonzero vectors');endif;v=acos(max(-1,min(1,real(sum(conj(a).*b)/(norm(a)*norm(b))))));
    case 'triple',require_b(b);if(numel(a)!=3||numel(c)!=3),error('GXTXT:Numeric:DimensionMismatch','triple requires three 3-vectors');endif;v=sum(a.*cross(b,c));
    case 'contract',require_b(b);v=sum(conj(a).*b);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown vector action');
  endswitch
  out=split_value(v);
endfunction
function require_b(b),if(isempty(b)),error('GXTXT:Numeric:InvalidArguments','second operand required');endif,endfunction
function out=split_value(v)
  if(any(!isfinite(real(v(:))))||any(!isfinite(imag(v(:))))),error('GXTXT:Numeric:NonFiniteResult','result is nonfinite');endif
  out=struct('value_real',real(v),'value_imaginary',imag(v));
endfunction
function check_axis(x,n,name)
  finite_numeric(x,name);if(!isreal(x)||!isvector(x)||numel(x)!=n||any(diff(x(:))<=0))
    error('GXTXT:Numeric:InvalidGrid','%s must be a finite strictly increasing coordinate vector matching field size',name);
  endif
endfunction
function out=grid_action(action,axes,values,query,opts)
  if(!iscell(axes)||numel(axes)<2||numel(axes)>3),error('GXTXT:Numeric:InvalidGrid','axes must contain two or three vectors');endif
  finite_numeric(values,'field');d=numel(axes);sz=size(values);
  for k=1:d,check_axis(axes{k},sz(k),sprintf('axis %d',k));endfor
  policy=option(opts,'extrapolation','error');method=option(opts,'method','linear');
  if(!any(strcmp(policy,{'error','nan','nearest'}))||!any(strcmp(method,{'linear','nearest'})))
    error('GXTXT:Numeric:InvalidPolicy','unsupported interpolation method or extrapolation policy');
  endif
  switch(action)
    case {'interpolate','sample'}
      if(!isnumeric(query)||columns(query)!=d||isempty(query)||any(!isfinite(query(:))))
        error('GXTXT:Numeric:DimensionMismatch','query must be an N by dimension finite matrix');
      endif
      q=query;outside=false(rows(q),1);
      for k=1:d
        x=axes{k}(:);outside|=(q(:,k)<x(1)|q(:,k)>x(end));
        if(strcmp(policy,'nearest')),q(:,k)=max(x(1),min(x(end),q(:,k)));endif
      endfor
      if(strcmp(policy,'error')&&any(outside)),error('GXTXT:Numeric:Extrapolation','query is outside the coordinate grid');endif
      if(d==2),v=interpn(axes{1},axes{2},values,q(:,1),q(:,2),method);
      else v=interpn(axes{1},axes{2},axes{3},values,q(:,1),q(:,2),q(:,3),method);endif
      if(strcmp(policy,'nan')),v(outside)=NaN;endif
      out=struct('value_real',real(v),'value_imaginary',imag(v),'outside',outside);
    case 'compatible'
      if(!iscell(query)||numel(query)!=d),error('GXTXT:Numeric:InvalidGrid','comparison axes required');endif
      atol=option(opts,'atol',0);rtol=option(opts,'rtol',1e-12);good=true;
      for k=1:d
        y=query{k};x=axes{k};good&=isnumeric(y)&&isequal(size(x),size(y))&&all(abs(x(:)-y(:))<=atol+rtol*abs(x(:)));
      endfor
      out=struct('compatible',logical(good));
    case 'resample'
      if(!iscell(query)||numel(query)!=d),error('GXTXT:Numeric:InvalidGrid','target axes required');endif
      for k=1:d,check_axis(query{k},numel(query{k}),sprintf('target axis %d',k));endfor
      [Q{1:d}]=ndgrid(query{:});points=zeros(numel(Q{1}),d);
      for k=1:d,points(:,k)=Q{k}(:);endfor
      r=grid_action('interpolate',axes,values,points,opts);v=reshape(complex(r.value_real,r.value_imaginary),cellfun(@numel,query));out=split_value(v);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown grid action');
  endswitch
endfunction
function out=calculus_action(action,axes,values,extra,opts)
  if(iscell(axes))
    finite_numeric(values,'field');d=numel(axes);if(d<2||d>3),error('GXTXT:Numeric:DimensionMismatch','field requires 2D or 3D axes');endif
    sz=size(values);for k=1:d,check_axis(axes{k},sz(k),sprintf('axis %d',k));endfor
  endif
  switch(action)
    case {'integrate2','integrate3','weighted_integral'}
      if(strcmp(action,'integrate2')&&d!=2||strcmp(action,'integrate3')&&d!=3),error('GXTXT:Numeric:DimensionMismatch','integration dimension mismatch');endif
      v=values;if(strcmp(action,'weighted_integral')),finite_numeric(extra,'weights');if(!isequal(size(v),size(extra))),error('GXTXT:Numeric:DimensionMismatch','weights shape mismatch');endif;v=v.*extra;endif
      for k=d:-1:1,v=trapz(axes{k},v,k);endfor
      out=split_value(v);
    case 'gradient_grid'
      boundary=option(opts,'boundary','one_sided');if(!any(strcmp(boundary,{'one_sided','nan'}))),error('GXTXT:Numeric:InvalidPolicy','boundary must be one_sided or nan');endif
      out=struct();for k=1:d
        idx=repmat({':'},1,d);dv=zeros(size(values));x=axes{k}(:);
        for j=1:sz(k)
          if(strcmp(boundary,'nan')&&(j==1||j==sz(k)))
            at=idx;at{k}=j;dv(at{:})=NaN;continue;
          endif
          if(j==1),lo=1;hi=2;elseif(j==sz(k)),lo=sz(k)-1;hi=sz(k);else lo=j-1;hi=j+1;endif
          at=idx;at{k}=j;il=idx;il{k}=lo;ih=idx;ih{k}=hi;
          dv(at{:})=(values(ih{:})-values(il{:}))/(x(hi)-x(lo));
        endfor
        out.(sprintf('axis%d_real',k))=real(dv);out.(sprintf('axis%d_imaginary',k))=imag(dv);
      endfor
    case {'line_integral','line_scalar_integral'}
      p=axes;f=values;finite_numeric(p,'path');finite_numeric(f,'field');
      if(!ismatrix(p)||rows(p)<2),error('GXTXT:Numeric:DimensionMismatch','path requires N by D coordinates');endif
      if(strcmp(action,'line_integral'))
        if(!isequal(size(p),size(f))),error('GXTXT:Numeric:DimensionMismatch','path and vector field must be matching N by D matrices');endif
        v=sum(sum((f(1:end-1,:)+f(2:end,:))/2.*diff(p,1,1),2));
      else
        if(!isvector(f)||numel(f)!=rows(p)),error('GXTXT:Numeric:DimensionMismatch','scalar path values must match point count');endif
        lengths=sqrt(sum(diff(p,1,1).^2,2));v=sum((f(1:end-1)+f(2:end))/2.*lengths);
      endif
      out=split_value(v);
    case {'surface_flux','surface_integral'}
      vertices=axes;faces=extra;field=values;finite_numeric(vertices,'vertices');finite_numeric(faces,'faces');finite_numeric(field,'field');
      if(columns(vertices)!=3||columns(faces)!=3||!isreal(faces)||any(faces(:)!=fix(faces(:)))||any(faces(:)<1)||any(faces(:)>rows(vertices)))
        error('GXTXT:Numeric:DimensionMismatch','surface requires vertices and valid triangular faces');
      endif
      e1=vertices(faces(:,2),:)-vertices(faces(:,1),:);e2=vertices(faces(:,3),:)-vertices(faces(:,1),:);area_vectors=cross(e1,e2,2)/2;
      if(strcmp(action,'surface_flux'))
        if(columns(field)!=3||rows(field)!=rows(faces)),error('GXTXT:Numeric:DimensionMismatch','flux requires one 3-vector per face');endif
        v=sum(sum(field.*area_vectors,2));
      else
        if(!isvector(field)||numel(field)!=rows(faces)),error('GXTXT:Numeric:DimensionMismatch','surface scalar values must match face count');endif
        v=sum(field(:).*sqrt(sum(area_vectors.^2,2)));
      endif
      out=split_value(v);
    case {'gradient','jacobian','hessian','directional'}
      if(!isa(axes,'function_handle')),error('GXTXT:Numeric:InvalidArguments','derivative requires a function handle');endif
      x=values(:);finite_numeric(x,'point');h=option(opts,'step',eps^(1/4)*(1+abs(x)));if(isscalar(h)),h=repmat(h,size(x));endif
      if(numel(h)!=numel(x)||any(!isfinite(h))||any(h<=0)),error('GXTXT:Numeric:InvalidTolerance','invalid finite-difference step');endif
      f0=axes(x);finite_numeric(f0,'function result');J=zeros(numel(f0),numel(x));
      for k=1:numel(x),e=zeros(size(x));e(k)=h(k);J(:,k)=(axes(x+e)(:)-axes(x-e)(:))/(2*h(k));endfor
      if(strcmp(action,'jacobian')),out=split_value(J);return;endif
      if(numel(f0)!=1),error('GXTXT:Numeric:DimensionMismatch','scalar objective required');endif
      if(strcmp(action,'gradient')),out=split_value(J(:));return;endif
      if(strcmp(action,'directional'))
        direction=extra(:);if(numel(direction)!=numel(x)||norm(direction)==0),error('GXTXT:Numeric:DimensionMismatch','nonzero matching direction required');endif
        out=split_value(J*direction/norm(direction));return;
      endif
      H=zeros(numel(x));for i=1:numel(x),for j=1:numel(x)
        ei=zeros(size(x));ej=ei;ei(i)=h(i);ej(j)=h(j);
        H(i,j)=(axes(x+ei+ej)-axes(x+ei-ej)-axes(x-ei+ej)+axes(x-ei-ej))/(4*h(i)*h(j));
      endfor,endfor
      out=split_value((H+H.')/2);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown calculus action');
  endswitch
endfunction
function out=ode_action(rhs,tspan,y0,opts)
  if(!isa(rhs,'function_handle')),error('GXTXT:Numeric:InvalidArguments','ODE RHS must be a function handle');endif
  finite_numeric(tspan,'times');finite_numeric(y0,'initial state');
  if(!isreal(tspan)||!isvector(tspan)||numel(tspan)<2||any(diff(tspan(:))<=0))
    error('GXTXT:Numeric:InvalidGrid','times must be strictly increasing');
  endif
  reltol=option(opts,'reltol',1e-6);abstol=option(opts,'abstol',1e-9);maxstep=option(opts,'max_step',Inf);
  if(!isfinite(reltol)||reltol<=0||!isfinite(abstol)||abstol<=0||isnan(maxstep)||maxstep<=0)
    error('GXTXT:Numeric:InvalidTolerance','ODE tolerances and maximum step must be positive');
  endif
  odeopts=odeset('RelTol',reltol,'AbsTol',abstol,'MaxStep',maxstep);
  if(isfield(opts,'progress')||isfield(opts,'cancel'))
    if(isfield(opts,'progress')&&!isa(opts.progress,'function_handle')||isfield(opts,'cancel')&&!isa(opts.cancel,'function_handle'))
      error('GXTXT:Numeric:InvalidArguments','progress and cancel must be function handles');
    endif
    odeopts=odeset(odeopts,'OutputFcn',@(tt,yy,flag) ode_output(tt,yy,flag,opts,tspan(1),tspan(end)));
  endif
  method=option(opts,'method','ode45');
  if(!any(strcmp(method,{'ode45','ode15s'}))),error('GXTXT:Numeric:InvalidMethod','ODE method must be ode45 or ode15s');endif
  if(isfield(opts,'events'))
    if(!isa(opts.events,'function_handle')),error('GXTXT:Numeric:InvalidArguments','events must be a function handle');endif
    odeopts=odeset(odeopts,'Events',opts.events);
  endif
  if(isfield(opts,'dense_times'))
    dense_times=opts.dense_times(:);finite_numeric(dense_times,'dense times');
    if(any(dense_times<tspan(1))||any(dense_times>tspan(end))),error('GXTXT:Numeric:InvalidGrid','dense times must lie in the integration interval');endif
    solve_times=unique([tspan(:);dense_times]);
  else solve_times=tspan(:);endif
  if(strcmp(method,'ode15s'))
    backend_method='ode15s';
    try
      [t,y,te,ye,ie]=ode15s(@(tt,yy) checked_rhs(rhs,tt,yy),solve_times,y0(:),odeopts);
    catch err
      if(isempty(strfind(err.message,'sundials_ida'))),rethrow(err);endif
      [t,y,te,ye,ie]=ode23s(@(tt,yy) checked_rhs(rhs,tt,yy),solve_times,y0(:),odeopts);
      backend_method='ode23s';
    end_try_catch
  else
    [t,y,te,ye,ie]=ode45(@(tt,yy) checked_rhs(rhs,tt,yy),solve_times,y0(:),odeopts);
    backend_method='ode45';
  endif
  completed=abs(t(end)-tspan(end))<=max(1e-12,eps(tspan(end))*10);
  terminated_by_event=!completed&&!isempty(te);
  out=struct('time',t,'state_real',real(y),'state_imaginary',imag(y),'success',completed||terminated_by_event,'cancelled',!completed&&!terminated_by_event,'terminated_by_event',terminated_by_event,'output_count',numel(t),'method',method,'backend_method',backend_method,'event_time',te,'event_state_real',real(ye),'event_state_imaginary',imag(ye),'event_index',ie);
  if(isfield(opts,'dense_times'))
    [found,loc]=ismember(dense_times,t);
    if(!all(found)&&!terminated_by_event),error('GXTXT:Numeric:DenseOutput','solver did not return requested dense times');endif
    out.dense_time=dense_times(found);out.dense_state_real=real(y(loc(found),:));out.dense_state_imaginary=imag(y(loc(found),:));out.dense_complete=all(found);
  endif
endfunction
function stop=ode_output(tt,yy,flag,opts,tinitial,tfinal)
  stop=false;if(!isempty(flag)),return;endif
  if(isfield(opts,'progress')),opts.progress((tt(end)-tinitial)/(tfinal-tinitial),tt(end),yy(:,end));endif
  if(isfield(opts,'cancel')),stop=logical(opts.cancel(tt(end),yy(:,end)));endif
endfunction
function dy=checked_rhs(rhs,t,y)
  dy=rhs(t,y);if(!isnumeric(dy)||numel(dy)!=numel(y)||any(!isfinite(real(dy(:))))||any(!isfinite(imag(dy(:)))))
    error('GXTXT:Numeric:InvalidRHS','ODE RHS returned invalid state derivative');
  endif
  dy=dy(:);
endfunction
function out=constrained_action(objective,x0,constraints,opts)
  if(!isa(objective,'function_handle')||!isstruct(constraints)),error('GXTXT:Numeric:InvalidArguments','objective handle and constraint struct required');endif
  finite_numeric(x0,'initial point');if(!isreal(x0)),error('GXTXT:Numeric:InvalidOperand','optimization point must be real');endif
  pkg('load','optim');x0=x0(:);n=numel(x0);lb=option(constraints,'lower',-Inf(n,1));ub=option(constraints,'upper',Inf(n,1));
  lb=lb(:);ub=ub(:);if(numel(lb)!=n||numel(ub)!=n||any(lb>ub)),error('GXTXT:Numeric:DimensionMismatch','invalid bounds');endif
  Aeq=option(constraints,'Aeq',zeros(0,n));beq=option(constraints,'beq',zeros(0,1));A=option(constraints,'A',zeros(0,n));b=option(constraints,'b',zeros(0,1));
  if(columns(Aeq)!=n||columns(A)!=n||rows(Aeq)!=numel(beq)||rows(A)!=numel(b)),error('GXTXT:Numeric:DimensionMismatch','invalid linear constraint shape');endif
  if(!isreal(Aeq)||!isreal(A)||!isreal(beq)||!isreal(b)||any(!isfinite(Aeq(:)))||any(!isfinite(A(:)))||any(!isfinite(beq(:)))||any(!isfinite(b(:)))||!isreal(lb)||!isreal(ub)||any(isnan(lb(:)))||any(isnan(ub(:))))
    error('GXTXT:Numeric:InvalidOperand','constraints must be real and finite except infinite box limits');
  endif
  if(isfield(constraints,'nonlinear'))
    if(!isa(constraints.nonlinear,'function_handle')),error('GXTXT:Numeric:InvalidArguments','nonlinear constraint must be a function handle');endif
    nonlin=constraints.nonlinear;
  else nonlin=[];endif
  checked_objective=@(x) checked_scalar(objective,x);
  method=option(opts,'method','sqp');
  if(strcmp(method,'derivative_free'))
    x=x0;iterations=0;evaluations=0;lambda=[];info=0;
    for penalty=[1e2 1e4 1e6 1e8]
      [x,~,exitflag,output]=fminsearch(@(v) constrained_penalty(v,checked_objective,Aeq,beq,A,b,lb,ub,nonlin,penalty),x, ...
        optimset('MaxIter',option(opts,'max_iterations',300),'TolX',option(opts,'tolerance',1e-6),'TolFun',option(opts,'tolerance',1e-6)));
      iterations+=output.iterations;evaluations+=output.funcCount;info=exitflag;
    endfor
    fval=checked_objective(x);if(info>0),info=104;endif
  elseif(strcmp(method,'sqp'))
    if(isempty(nonlin)),[x,fval,info,iterations,evaluations,lambda]=sqp(x0,checked_objective,@(x) Aeq*x-beq,@(x) b-A*x,lb,ub,option(opts,'max_iterations',100),option(opts,'tolerance',1e-6));
    else
      eq=@(x) constraint_part(nonlin,x,1,Aeq,beq,A,b);ineq=@(x) constraint_part(nonlin,x,2,Aeq,beq,A,b);
      [x,fval,info,iterations,evaluations,lambda]=sqp(x0,checked_objective,eq,ineq,lb,ub,option(opts,'max_iterations',100),option(opts,'tolerance',1e-6));
    endif
  else,error('GXTXT:Numeric:InvalidMethod','constrained method must be sqp or derivative_free');endif
  eqres=Aeq*x-beq;ineqres=b-A*x;
  if(!isempty(nonlin)),eqres=[eqres;nonlinear_part(nonlin,x,1)];ineqres=[ineqres;nonlinear_part(nonlin,x,2)];endif
  tolerance=option(opts,'constraint_tolerance',1e-6);
  if(!isfinite(tolerance)||tolerance<=0),error('GXTXT:Numeric:InvalidTolerance','constraint tolerance must be positive');endif
  violation=max([0;abs(eqres(:));-ineqres(:);lb(:)-x;x-ub(:)]);
  if(isfield(opts,'gradient'))
    if(!isa(opts.gradient,'function_handle')),error('GXTXT:Numeric:InvalidArguments','gradient must be a function handle');endif
    grad=opts.gradient(x);grad=grad(:);
  else grad=finite_jacobian(objective,x).';endif
  Je=Aeq;Jh=-A;all_slacks=ineqres(:);
  if(!isempty(nonlin))
    Je=[Je;finite_jacobian(@(v) nonlinear_part(nonlin,v,1),x)];
    Jh=[Jh;finite_jacobian(@(v) nonlinear_part(nonlin,v,2),x)];
  endif
  active_ineq=find(ineqres<=tolerance);active_lower=find(x-lb<=tolerance);active_upper=find(ub-x<=tolerance);
  if(!isempty(active_lower)),Jh=[Jh;eye(n)(active_lower,:)];all_slacks=[all_slacks;x(active_lower)-lb(active_lower)];endif
  if(!isempty(active_upper)),Jh=[Jh;-eye(n)(active_upper,:)];all_slacks=[all_slacks;ub(active_upper)-x(active_upper)];endif
  active=[active_ineq(:);(numel(ineqres)+(1:numel(active_lower)+numel(active_upper)))(:)];
  K=[Je;Jh(active,:)].';kkt_lambda=pinv(K)*grad;stationarity=norm(grad-K*kkt_lambda);
  eq_count=rows(Je);dual=kkt_lambda(eq_count+1:end);dual_violation=max([0;-dual(:)]);
  complementarity=norm(dual.*all_slacks(active));
  converged=(info==101||info==104)&&violation<=tolerance&&stationarity<=10*tolerance&&dual_violation<=10*tolerance;
  out=struct('point',x,'objective',fval,'status',info,'converged',converged,'method',method,'iterations',iterations,'function_evaluations',evaluations,'equality_residual',eqres,'inequality_slack',ineqres,'maximum_violation',violation,'backend_multipliers',lambda,'kkt_multipliers',kkt_lambda,'kkt_stationarity_norm',stationarity,'kkt_complementarity_norm',complementarity,'kkt_dual_violation',dual_violation,'active_inequalities',active_ineq,'active_lower_bounds',active_lower,'active_upper_bounds',active_upper);
endfunction
function total=constrained_penalty(x,objective,Aeq,beq,A,b,lb,ub,nonlin,weight)
  equality=Aeq*x-beq;slack=b-A*x;
  if(!isempty(nonlin)),equality=[equality;nonlinear_part(nonlin,x,1)];slack=[slack;nonlinear_part(nonlin,x,2)];endif
  violations=[equality(:);min(0,slack(:));min(0,x-lb);min(0,ub-x)];
  total=objective(x)+weight*sum(violations.^2);
endfunction
function v=nonlinear_part(fun,x,which)
  [e,h]=fun(x);if(!isreal(e)||!isreal(h)||any(!isfinite(e(:)))||any(!isfinite(h(:)))),error('GXTXT:Numeric:InvalidConstraint','nonlinear constraint returned nonfinite or complex values');endif
  if(which==1),v=e(:);else v=h(:);endif
endfunction
function value=checked_scalar(fun,x)
  value=fun(x);if(!isnumeric(value)||!isscalar(value)||!isreal(value)||!isfinite(value)),error('GXTXT:Numeric:InvalidObjective','objective must return a finite real scalar');endif
endfunction
function J=finite_jacobian(fun,x)
  y=fun(x);y=y(:);J=zeros(numel(y),numel(x));
  for j=1:numel(x),step=sqrt(eps)*(1+abs(x(j)));e=zeros(size(x));e(j)=step;
    plus=fun(x+e);minus=fun(x-e);J(:,j)=(plus(:)-minus(:))/(2*step);
  endfor
endfunction
function v=constraint_part(fun,x,which,Aeq,beq,A,b)
  if(which==1),v=[Aeq*x-beq;nonlinear_part(fun,x,1)];else v=[b-A*x;nonlinear_part(fun,x,2)];endif
endfunction
function out=special_action(action,a,b,opts)
  finite_numeric(a,'argument');if(!isreal(a)),error('GXTXT:Numeric:InvalidOperand','special-function arguments must be real');endif
  switch(action)
    case 'erf',v=erf(a);
    case 'erfc',v=erfc(a);
    case 'gamma',v=gamma(a);
    case 'log_gamma',v=gammaln(a);
    case 'beta',finite_numeric(b,'second argument');v=beta(a,b);
    case 'incomplete_gamma',finite_numeric(b,'shape');v=gammainc(a,b,option(opts,'tail','lower'));
    case 'incomplete_beta',finite_numeric(b,'second shape');p=option(opts,'third_shape',[]);finite_numeric(p,'third shape');v=betainc(a,b,p);
    case 'bessel_j',finite_numeric(b,'order');v=besselj(b,a);
    case 'bessel_y',finite_numeric(b,'order');v=bessely(b,a);
    case 'bessel_i',finite_numeric(b,'order');v=besseli(b,a);
    case 'bessel_k',finite_numeric(b,'order');v=besselk(b,a);
    case 'spherical_bessel_j'
      finite_numeric(b,'order');if(any(a(:)<0)||any(b(:)<0)||any(b(:)!=fix(b(:)))),error('GXTXT:Numeric:InvalidOperand','spherical Bessel requires nonnegative x and integer order');endif
      v=sqrt(pi./(2*a)).*besselj(b+0.5,a);v(a==0)=double(b==0);
    case 'spherical_bessel_y'
      finite_numeric(b,'order');if(any(a(:)<=0)||any(b(:)<0)||any(b(:)!=fix(b(:)))),error('GXTXT:Numeric:InvalidOperand','spherical Bessel Y requires positive x and nonnegative integer order');endif
      v=sqrt(pi./(2*a)).*bessely(b+0.5,a);
    case 'airy',v=airy(option(opts,'kind',0),a);
    case 'exponential_integral',v=expint(a);
    case 'sinc'
      normalization=option(opts,'normalization','normalized');
      if(strcmp(normalization,'normalized')),z=pi*a;elseif(strcmp(normalization,'unnormalized')),z=a;else,error('GXTXT:Numeric:InvalidPolicy','sinc normalization must be normalized or unnormalized');endif
      v=ones(size(z));mask=z!=0;v(mask)=sin(z(mask))./z(mask);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown special function');
  endswitch
  out=split_value(v);
endfunction
