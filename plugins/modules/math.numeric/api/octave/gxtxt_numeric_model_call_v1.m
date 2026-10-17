% Declarative, data-only model callbacks for guided NUMERIC_API_v1 clients.
% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_numeric_model_call_v1(operation, mode, operands, model, unused, options)
  if(!strcmp(mode,'model') || !iscell(operands) || !isstruct(model) || !isfield(model,'kind') || !isstruct(options))
    error('GXTXT:Numeric:InvalidArguments','model call requires a declared model, typed operands and options');
  endif
  if(strncmp(operation,'foundation.',11))
    parts=strsplit(operation,'.');
    if(numel(parts)!=3 || numel(operands)!=2),error('GXTXT:Numeric:InvalidArguments','foundation model call requires family, action and two data operands');endif
    family=parts{2};action=parts{3};
    switch(family)
      case 'calculus',callback=@(x) model_value(model,x);
      case 'equations'
        if(strcmp(action,'continuation')),callback=@(x,p) model_value(model,x,p);
        else callback=@(x) model_value(model,x);endif
      case 'ode',callback=@(t,y) model_ode(model,t,y);
      case 'constrained',callback=@(x) model_value(model,x);
      case 'variational'
        if(any(strcmp(action,{'action','functional','legendre','euler_lagrange_residual'})))
          callback=@(t,q,v) model_lagrangian(model,t,q,v);
        else
          callback=@(t,q) model_value(model,q);
        endif
      otherwise,error('GXTXT:Numeric:UnknownOperation','no declarative callback for foundation family');
    endswitch
    out=gxtxt_numeric_v1('foundation',family,action,callback,operands{1},operands{2},options);
  else
    switch(operation)
      case 'nonlinear_fit'
        if(numel(operands)!=3),error('GXTXT:Numeric:InvalidArguments','nonlinear fit needs X, Y and initial parameters');endif
        callback=@(p,x) model_fit(model,x,p);
        if(strcmp(model.kind,'expression')||!isfield(options,'solver')||any(strcmp(options.solver,{'auto','ceres'}))),callback=model;endif
        out=gxtxt_numeric_v1(operation,callback,operands{1},operands{2},operands{3},options);
      case 'dataset_nonlinear_fit'
        if(numel(operands)!=5),error('GXTXT:Numeric:InvalidArguments','Dataset nonlinear fit needs Session, Dataset ID, X/Y variable IDs and initial parameters');endif
        callback=@(p,x) model_fit(model,x,p);
        if(strcmp(model.kind,'expression')||!isfield(options,'solver')||any(strcmp(options.solver,{'auto','ceres'}))),callback=model;endif
        out=gxtxt_numeric_v1(operation,operands{1},operands{2},operands{3},operands{4},callback,operands{5},options);
      case {'root_find','minimize_1d','minimize'}
        if(numel(operands)!=1),error('GXTXT:Numeric:InvalidArguments','root/minimize model call needs one data operand');endif
        callback=@(x) model_value(model,x);
        out=gxtxt_numeric_v1(operation,callback,operands{1},options);
      otherwise,error('GXTXT:Numeric:UnknownOperation','no declarative model binding for operation');
    endswitch
  endif
  if(!isstruct(out)),out=struct('value',out);endif
endfunction

function value=model_value(model,x,parameter)
  if(nargin<3),parameter=1;endif
  switch(model.kind)
    case 'polynomial'
      if(!isfield(model,'coefficients')),error('GXTXT:Numeric:InvalidModel','polynomial model requires coefficients');endif
      value=polyval(model.coefficients(:).',x);
    case 'quadratic_norm'
      center=zeros(size(x));if(isfield(model,'center')),center=model.center;endif
      if(numel(center)!=numel(x)),error('GXTXT:Numeric:DimensionMismatch','quadratic center and point must match');endif
      value=sum((x(:)-center(:)).^2);
    case 'linear_system'
      if(!isfield(model,'matrix') || !isfield(model,'target')),error('GXTXT:Numeric:InvalidModel','linear system requires matrix and target');endif
      value=model.matrix*x(:)-parameter*model.target(:);
    otherwise,error('GXTXT:Numeric:InvalidModel','unsupported scalar/vector model kind');
  endswitch
endfunction

function value=model_fit(model,x,p)
  p=p(:);x=x(:);
  switch(model.kind)
    case 'linear',value=p(1)+p(2)*x;
    case 'polynomial_fit',value=polyval(p(:).',x);
    case 'exponential'
      if(numel(p)!=3),error('GXTXT:Numeric:DimensionMismatch','exponential model needs amplitude, rate and offset');endif
      value=p(1)*exp(p(2)*x)+p(3);
    case 'gaussian'
      if(numel(p)!=4 || p(3)==0),error('GXTXT:Numeric:DimensionMismatch','Gaussian model needs amplitude, center, nonzero width and offset');endif
      value=p(1)*exp(-0.5*((x-p(2))/p(3)).^2)+p(4);
    otherwise,error('GXTXT:Numeric:InvalidModel','unsupported fitting model kind');
  endswitch
endfunction

function value=model_ode(model,t,y)
  if(!strcmp(model.kind,'linear_ode') || !isfield(model,'matrix'))
    error('GXTXT:Numeric:InvalidModel','linear ODE model requires a matrix');
  endif
  offset=zeros(numel(y),1);if(isfield(model,'offset')),offset=model.offset(:);endif
  value=model.matrix*y(:)+offset;
endfunction

function value=model_lagrangian(model,t,q,v)
  if(!strcmp(model.kind,'quadratic_lagrangian'))
    error('GXTXT:Numeric:InvalidModel','variational action requires a quadratic Lagrangian model');
  endif
  if(!isfield(model,'mass') || !isfield(model,'stiffness'))
    error('GXTXT:Numeric:InvalidModel','quadratic Lagrangian needs mass and stiffness vectors');
  endif
  mass=model.mass(:);stiffness=model.stiffness(:);q=q(:);v=v(:);
  if(numel(mass)!=numel(q) || numel(stiffness)!=numel(q) || numel(v)!=numel(q))
    error('GXTXT:Numeric:DimensionMismatch','Lagrangian parameters and coordinates must match');
  endif
  value=0.5*sum(mass.*v.^2)-0.5*sum(stiffness.*q.^2);
endfunction
