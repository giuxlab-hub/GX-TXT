% Reconstructible geometric and functional curve models for NUMERIC_API_v1.
% Public entry point is gxtxt_numeric_v1('curve_model_fit'|'curve_model_evaluate',...).
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_curve_models_v1(operation,varargin)
  if(strcmp(operation,'fit'))
    if(any(strcmp(varargin{1},{'akima','bspline'})))
      opts=struct();if(numel(varargin)>=4),opts=varargin{4};endif
      out=gxtxt_numeric_knot_splines_v1('fit',varargin{1},varargin{2},varargin{3},opts);return;
    endif
    model=varargin{1};x=double(varargin{2}(:));y=double(varargin{3}(:));
    if(numel(varargin)>=4),opts=varargin{4};else opts=struct();endif
    if(!isstruct(opts)||numel(opts)!=1),error('GXTXT:Numeric','curve model options must be a scalar struct');endif
    if(numel(x)!=numel(y)||numel(x)<2||any(!isfinite(x))||any(!isfinite(y)))
      error('GXTXT:Numeric','curve model requires paired finite points');
    endif
    if(any(strcmp(model,{'parametric_polynomial','parametric_spline'})))
      out=gxtxt_numeric_parametric_models_v1('fit',model,x,y,opts);return;
    endif
    switch(model)
      case 'circular_arc'
        if(numel(x)<3),error('GXTXT:Numeric','circular arc needs at least three points');endif
        % Centered algebraic fit avoids forming a poorly scaled X^2+Y^2 RHS.
        mx=mean(x);my=mean(y);u=x-mx;v=y-my;
        A=[2*u,2*v];b=u.^2+v.^2;
        if(rank(A)<2),error('GXTXT:Numeric','circular arc points are collinear');endif
        center=A\b;cx=mx+center(1);cy=my+center(2);
        r=mean(hypot(x-cx,y-cy));
        if(!isfinite(r)||r<=0),error('GXTXT:Numeric','invalid circular arc radius');endif
        theta=unwrap(atan2(y-cy,x-cx));
        if(abs(theta(end)-theta(1))<1e-12),error('GXTXT:Numeric','circular arc has no oriented interval');endif
        out=struct('model','circular_arc','parametric',true,'center_x',cx,'center_y',cy,'radius',r,...
          'angle_start',theta(1),'angle_end',theta(end),'orientation',sign(theta(end)-theta(1)),...
          'parameters',[cx;cy;r;theta(1);theta(end)]);
      case {'quadratic_bezier','cubic_bezier'}
        degree=2;if(strcmp(model,'cubic_bezier')),degree=3;endif
        if(numel(x)<degree+1),error('GXTXT:Numeric','Bézier model has too few points');endif
        t=linspace(0,1,numel(x)).';
        B=zeros(numel(x),degree+1);
        for j=0:degree,B(:,j+1)=nchoosek(degree,j)*(1-t).^(degree-j).*t.^j;endfor
        control=zeros(degree+1,2);control(1,:)=[x(1),y(1)];control(end,:)=[x(end),y(end)];
        rhs=[x,y]-B(:,1)*control(1,:)-B(:,end)*control(end,:);
        inner=B(:,2:end-1);
        if(rank(inner)<degree-1),error('GXTXT:Numeric','Bézier control-point design is rank deficient');endif
        control(2:end-1,:)=inner\rhs;
        out=struct('model',model,'parametric',true,'degree',degree,'control_points',control,...
          'parameter_start',0,'parameter_end',1,'source_parameter',t,'parameters',control(:));
      case 'pchip'
        [x,idx]=sort(x);y=y(idx);
        if(numel(x)<3||any(diff(x)<=0)),error('GXTXT:Numeric','PCHIP requires distinct increasing X values');endif
        out=struct('model','pchip','parametric',false,'source_x',x,'source_y',y,...
          'extrapolation','error','parameters',[],'input_order',idx);
      case 'smoothing_spline'
        [x,idx]=sort(x);y=y(idx);
        if(numel(x)<3||any(diff(x)<=0)),error('GXTXT:Numeric','smoothing spline requires distinct increasing X values');endif
        out=gxtxt_numeric_smoothing_spline_v1(x,y,opts);
        out.input_order=idx;
      case 'fourier'
        if(!isfield(opts,'order')),error('GXTXT:Numeric','Fourier order is required');endif
        order=double(opts.order);
        if(!isscalar(order)||!isfinite(order)||order<1||order!=fix(order)),error('GXTXT:Numeric','Fourier order must be a positive integer');endif
        if(numel(x)<2*order+1),error('GXTXT:Numeric','Fourier order requires at least 2N+1 independent samples');endif
        if(isfield(opts,'period')&&!isempty(opts.period))
          period=double(opts.period);basis='explicit_period';
        else
          sorted_x=sort(x);step=diff(sorted_x);
          if(all(step>0)&&max(abs(step-step(1)))<=1e-9*max(1,abs(step(1))))
            period=numel(x)*step(1);basis='uniform_grid_extent';
          else
            period=max(x)-min(x);basis='training_domain_span';
          endif
        endif
        if(!isscalar(period)||!isfinite(period)||period<=0),error('GXTXT:Numeric','Fourier period must be positive');endif
        origin=min(x);omega=2*pi/period;
        [sorted_x,idx]=sort(x);sorted_y=y(idx);
        step=diff(sorted_x);
        uniform_cycle=all(step>0)&&max(abs(step-step(1)))<=1e-9*max(1,abs(step(1)))&&...
          abs(numel(x)*step(1)-period)<=1e-8*max(1,period);
        if(uniform_cycle)
          % Exact orthogonal Fourier basis on one uniformly sampled period.
          % This also makes high requested orders practical without a dense
          % 2001-column least-squares design for N=1000.
          spectrum=fft(sorted_y)/numel(x);
          coefficients=zeros(2*order+1,1);coefficients(1)=real(spectrum(1));
          for k=1:order
            coefficients(2*k)=2*real(spectrum(k+1));
            coefficients(2*k+1)=-2*imag(spectrum(k+1));
          endfor
          solver='orthogonal_dft';
        else
          A=fourier_design(x,order,origin,omega);
          if(rank(A)<columns(A)),error('GXTXT:Numeric','Fourier design is rank deficient for the requested order');endif
          coefficients=A\y;solver='least_squares';
        endif
        if(any(!isfinite(coefficients))),error('GXTXT:Numeric','Fourier solver returned nonfinite coefficients');endif
        out=struct('model','fourier','parametric',false,'order',order,'period',period,...
          'fundamental_angular_frequency',omega,'origin',origin,'basis',basis,...
          'coefficients',coefficients,'parameters',coefficients,'solver',solver);
        % Only the FFT branch consumes the sorted observation vector. The
        % nonuniform least-squares branch above retains the original row order.
        if(uniform_cycle),out.input_order=idx;endif
      otherwise
        error('GXTXT:Numeric','unsupported curve model %s',model);
    endswitch
    out.source_count=numel(x);
  elseif(strcmp(operation,'residual'))
    model=varargin{1};x=double(varargin{2}(:));y=double(varargin{3}(:));
    if(isempty(x)),error('GXTXT:Numeric','geometric residuals require nonempty paired points');endif
    projection=gxtxt_numeric_curve_models_v1('project',model,x,y);
    tangent=gxtxt_numeric_curve_models_v1('evaluate',model,projection.parameter);
    cross=tangent.tangent_x.*(y-projection.y)-tangent.tangent_y.*(x-projection.x);
    direction=ones(size(cross));direction(cross<0)=-1;
    residual=direction.*projection.distance;
    sse=sum(projection.distance.^2);sst=sum((x-mean(x)).^2+(y-mean(y)).^2);
    r2=NaN;if(sst>0),r2=1-sse/sst;endif
    out=struct('x',projection.x,'y',projection.y,'parameter',projection.parameter,...
      'distance',projection.distance,'signed_residual',residual,'n',numel(x),...
      'sse',sse,'rmse',sqrt(sse/numel(x)),'mae',mean(projection.distance),...
      'max_abs_error',max(projection.distance),'r2',r2,...
      'residual_convention','geometric_distance_signed_left_of_oriented_tangent',...
      'zero_normal_sign_policy','unsigned_distance_at_zero_cross_product',...
      'r2_convention','one_minus_squared_projection_distance_over_xy_centroid_dispersion');
  elseif(strcmp(operation,'project'))
    model=varargin{1};x=double(varargin{2}(:));y=double(varargin{3}(:));
    if(numel(x)!=numel(y)||any(!isfinite(x))||any(!isfinite(y)))
      error('GXTXT:Numeric','curve projection requires paired finite points');
    endif
    if(any(strcmp(model.model,{'parametric_polynomial','parametric_spline'})))
      out=gxtxt_numeric_parametric_models_v1('project',model,x,y);return;
    endif
    t=zeros(size(x));px=t;py=t;
    if(strcmp(model.model,'circular_arc'))
      start=model.angle_start;span=model.angle_end-start;
      for i=1:numel(x)
        angle=atan2(y(i)-model.center_y,x(i)-model.center_x);
        turn=round((start+span/2-angle)/(2*pi));
        candidates=[0;1;min(1,max(0,(angle+2*pi*(turn+(-1:1))-start)/span)).'];
        values=gxtxt_numeric_curve_models_v1('evaluate',model,candidates);
        [~,best]=min((values.x-x(i)).^2+(values.y-y(i)).^2);
        t(i)=candidates(best);px(i)=values.x(best);py(i)=values.y(best);
      endfor
    elseif(any(strcmp(model.model,{'quadratic_bezier','cubic_bezier'})))
      p=model.control_points;
      if(model.degree==2)
        coefficients=[p(1,:)-2*p(2,:)+p(3,:);2*(p(2,:)-p(1,:));p(1,:)];
      else
        coefficients=[-p(1,:)+3*p(2,:)-3*p(3,:)+p(4,:);3*p(1,:)-6*p(2,:)+3*p(3,:);3*(p(2,:)-p(1,:));p(1,:)];
      endif
      for i=1:numel(x)
        cx=coefficients(:,1).';cy=coefficients(:,2).';cx(end)-=x(i);cy(end)-=y(i);
        d=model.degree;
        polynomial=conv(cx,(d:-1:1).*cx(1:end-1))+conv(cy,(d:-1:1).*cy(1:end-1));
        candidates=roots(polynomial);
        candidates=real(candidates(abs(imag(candidates))<1e-9 & real(candidates)>=0 & real(candidates)<=1));
        candidates=[0;1;candidates(:)];
        values=gxtxt_numeric_curve_models_v1('evaluate',model,candidates);
        [~,best]=min((values.x-x(i)).^2+(values.y-y(i)).^2);
        t(i)=candidates(best);px(i)=values.x(best);py(i)=values.y(best);
      endfor
    else
      error('GXTXT:Numeric','curve projection is supported for parametric arc and Bézier models');
    endif
    out=struct('x',px,'y',py,'parameter',t,'distance',hypot(px-x,py-y),'points',[px,py]);
  elseif(strcmp(operation,'evaluate'))
    if(isstruct(varargin{1})&&isfield(varargin{1},'model')&&any(strcmp(varargin{1}.model,{'akima','bspline'})))
      options=struct();if(numel(varargin)>=3),options=varargin{3};endif
      out=gxtxt_numeric_knot_splines_v1('evaluate',varargin{1},varargin{2},options);return;
    endif
    model=varargin{1};q=double(varargin{2}(:));
    options=struct();if(numel(varargin)>=3),options=varargin{3};endif
    if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),{'derivative'}))),error('GXTXT:Numeric','Curve evaluation accepts only the derivative option');endif
    derivative=false;if(isfield(options,'derivative')),derivative=options.derivative;endif
    if(!(isnumeric(derivative)||islogical(derivative))||!isscalar(derivative)||!isreal(derivative)||!ismember(derivative,[0,1])),error('GXTXT:Numeric','Curve derivative must be boolean');endif
    if(!isstruct(model)||!isfield(model,'model')||any(!isfinite(q))),error('GXTXT:Numeric','invalid curve model or query');endif
    if(any(strcmp(model.model,{'parametric_polynomial','parametric_spline'})))
      out=gxtxt_numeric_parametric_models_v1('evaluate',model,q);return;
    endif
    switch(model.model)
      case 'circular_arc'
        if(any(q<0)|any(q>1)),error('GXTXT:Numeric','arc parameter must lie in [0,1]');endif
        angle=model.angle_start+q*(model.angle_end-model.angle_start);
        px=model.center_x+model.radius*cos(angle);py=model.center_y+model.radius*sin(angle);
        tangent_x=-model.radius*(model.angle_end-model.angle_start)*sin(angle);
        tangent_y=model.radius*(model.angle_end-model.angle_start)*cos(angle);
      case {'quadratic_bezier','cubic_bezier'}
        if(any(q<0)|any(q>1)),error('GXTXT:Numeric','Bézier parameter must lie in [0,1]');endif
        p=model.control_points;d=model.degree;px=zeros(size(q));py=px;
        tangent_x=zeros(size(q));tangent_y=tangent_x;
        for j=0:d
          b=nchoosek(d,j)*(1-q).^(d-j).*q.^j;
          px+=b*p(j+1,1);py+=b*p(j+1,2);
        endfor
        for j=0:d-1
          b=d*nchoosek(d-1,j)*(1-q).^(d-1-j).*q.^j;
          tangent_x+=b*(p(j+2,1)-p(j+1,1));tangent_y+=b*(p(j+2,2)-p(j+1,2));
        endfor
      case 'pchip'
        if(any(q<model.source_x(1))||any(q>model.source_x(end))),error('GXTXT:Numeric','PCHIP query is outside training domain');endif
        pp=gxtxt_numeric_v1('spline_create',model.source_x,model.source_y,struct('method','pchip'));
        px=q;py=gxtxt_numeric_v1('spline_evaluate',pp,q,struct('derivative_order',0)).values;
        if(derivative)
          tangent_x=ones(size(q));tangent_y=gxtxt_numeric_v1('spline_evaluate',pp,q,struct('derivative_order',1)).values;
        endif
      case 'smoothing_spline'
        x=model.source_x;y=model.smoothed_y;M=model.second_derivatives;
        if(any(q<x(1))||any(q>x(end))),error('GXTXT:Numeric','smoothing spline query is outside training domain');endif
        px=q;i=min(lookup(x,q),numel(x)-1);
        h=x(i+1)-x(i);a=(x(i+1)-q)./h;b=(q-x(i))./h;
        py=a.*y(i)+b.*y(i+1)+((a.^3-a).*M(i)+(b.^3-b).*M(i+1)).*h.^2/6;
        if(derivative),tangent_x=ones(size(q));tangent_y=(y(i+1)-y(i))./h+((-3*a.^2+1).*M(i)+(3*b.^2-1).*M(i+1)).*h/6;endif
      case 'fourier'
        px=q;py=fourier_design(q,model.order,model.origin,model.fundamental_angular_frequency)*model.coefficients;
        if(derivative)
          tangent_x=ones(size(q));tangent_y=zeros(size(q));
          for k=1:model.order
            frequency=k*model.fundamental_angular_frequency;angle=frequency*(q-model.origin);
            tangent_y+=frequency*(-model.coefficients(2*k)*sin(angle)+model.coefficients(2*k+1)*cos(angle));
          endfor
        endif
      otherwise
        error('GXTXT:Numeric','unsupported curve model');
    endswitch
    out=struct('x',px(:),'y',py(:),'points',[px(:),py(:)]);
    if(derivative||any(strcmp(model.model,{'circular_arc','quadratic_bezier','cubic_bezier'})))
      out.tangent_x=tangent_x(:);out.tangent_y=tangent_y(:);
    endif
  else
    error('GXTXT:Numeric','unknown curve model operation');
  endif
endfunction

function A=fourier_design(x,order,origin,omega)
  phase=(x(:)-origin)*omega;A=zeros(numel(x),2*order+1);A(:,1)=1;
  for k=1:order
    A(:,2*k)=cos(k*phase);A(:,2*k+1)=sin(k*phase);
  endfor
endfunction
