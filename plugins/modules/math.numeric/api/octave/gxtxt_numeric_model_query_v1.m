% Public retained-model queries; no fitting, finite differences or inference.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_model_query_v1(model,query,options)
  if(ischar(model)),model=gxtxt_numeric_model_state_decode_v1(model);endif
  if(isstruct(model)&&isfield(model,'kind')&&strcmp(model.kind,'complex_projection'))
    out=gxtxt_numeric_complex_retained_v1('query',model,query,options);return;
  endif
  if(isstruct(model)&&isfield(model,'kind')&&strcmp(model.kind,'implicit_branch'))
    out=gxtxt_numeric_implicit_retained_v1('query',model,query,options);return;
  endif
  if(isstruct(options)&&any(isfield(options,{'orientation','translation','polar_frame'})))
    out=physical_query(model,query,options);return;
  endif
  if(isstruct(model)&&isfield(model,'kind')&&strcmp(model.kind,'rational'))
    out=gxtxt_numeric_rational_v1('query',model,query,options);return;
  endif
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),{'domain','extrapolation','derivative','tangent_floors'})))
    error('GXTXT:Numeric:Options','Unknown retained-model query option');
  endif
  if(!isnumeric(query)||!isreal(query)||!isvector(query)||isempty(query)||numel(query)>1000000||any(!isfinite(query(:))))
    error('GXTXT:Numeric:Query','Queries require1..1000000 finite real values');
  endif
  if(!isfield(options,'domain')||!isnumeric(options.domain)||!isreal(options.domain)||numel(options.domain)!=2||any(!isfinite(options.domain(:)))||options.domain(1)>=options.domain(2))
    error('GXTXT:Numeric:Domain','A finite increasing retained training domain is required');
  endif
  domain=gxtxt_numeric_query_double_v1(options.domain(:));query=gxtxt_numeric_query_double_v1(query(:));outside=query<domain(1)|query>domain(2);
  policy='error';if(isfield(options,'extrapolation')),policy=options.extrapolation;endif
  if(!ischar(policy)||!any(strcmp(policy,{'error','allow'}))),error('GXTXT:Numeric:Options','Extrapolation must be error or explicit allow');endif
  if(strcmp(policy,'error')&&any(outside)),error('GXTXT:Numeric:Domain','Query is outside the retained training domain');endif
  derivative=true;if(isfield(options,'derivative')),derivative=options.derivative;endif
  if(!(isnumeric(derivative)||islogical(derivative))||!isscalar(derivative)||!isreal(derivative)||!ismember(derivative,[0,1])),error('GXTXT:Numeric:Options','Derivative must be boolean');endif
  floors=[0;0];if(isfield(options,'tangent_floors')),floors=options.tangent_floors;endif
  if(!isnumeric(floors)||!isreal(floors)||numel(floors)!=2||any(!isfinite(floors(:)))||any(floors(:)<0)),error('GXTXT:Numeric:Options','Two nonnegative finite coordinate-tangent floors are required');endif
  floors=gxtxt_numeric_query_double_v1(floors(:));parametric=false;method='not_requested';n=numel(query);
  tx=NaN(n,1);ty=tx;regular=false(n,1);
  if(isstruct(model)&&isfield(model,'kind')&&strcmp(model.kind,'polynomial_export'))
    evaluated=gxtxt_numeric_v1('polynomial_evaluate',model,query,struct());x=query;y=evaluated.yq;
    if(derivative)
      tx=ones(n,1);ty=gxtxt_numeric_v1('polynomial_evaluate',model,query,struct('derivative_order',1)).yq;
      regular=isfinite(ty);method='analytic_scaled_polynomial';
    endif
  elseif(isstruct(model)&&isfield(model,'model'))
    curve_options=struct('derivative',derivative);
    if(any(strcmp(model.model,{'akima','bspline'})))
      model=gxtxt_numeric_knot_splines_v1('validate',model);
      if(!isequal(domain(:),model.knots([1,end]))),error('GXTXT:Numeric:Domain','Knot query reference bounds must retain the complete captured domain');endif
      curve_options.extrapolation=policy;
    endif
    evaluated=gxtxt_numeric_v1('curve_model_evaluate',model,query,curve_options);
    x=evaluated.x(:);y=evaluated.y(:);
    parametric=any(strcmp(model.model,{'circular_arc','quadratic_bezier','cubic_bezier','parametric_polynomial','parametric_spline'}));
    if(derivative)
      tx=evaluated.tangent_x(:);ty=evaluated.tangent_y(:);regular=isfinite(tx)&isfinite(ty);
      method='analytic_curve_or_piecewise_polynomial';
    endif
  else
    evaluated=gxtxt_numeric_v1('nonlinear_evaluate',model,query,struct('predictor_derivative',derivative));
    if(columns(evaluated.predicted)!=1),error('GXTXT:Numeric:Model','Retained scalar query requires one response');endif
    x=query;y=evaluated.predicted(:);
    if(derivative)
      tx=ones(n,1);ty=evaluated.predictor_derivative(:);regular=logical(evaluated.derivative_valid(:));
      method=evaluated.derivative_method;
    endif
  endif
  if(any(!isfinite(x))||any(!isfinite(y))),error('GXTXT:Numeric:Domain','Model is nonfinite on the requested domain');endif
  valid=regular&abs(tx)>floors(1);inverse_valid=regular&abs(ty)>floors(2);
  slope=NaN(n,1);inverse_slope=slope;
  slope(valid)=ty(valid)./tx(valid);inverse_slope(inverse_valid)=tx(inverse_valid)./ty(inverse_valid);
  valid=valid&isfinite(slope);inverse_valid=inverse_valid&isfinite(inverse_slope);
  slope(!valid)=NaN;inverse_slope(!inverse_valid)=NaN;
  out=struct('schema','gxtxt.model_query.v1','query',query,'points',[x,y],...
    'predicted',y,'parametric',parametric,'domain',domain,'extrapolation',policy,...
    'is_extrapolated',outside,'derivative',slope,'derivative_valid',valid,...
    'inverse_derivative',inverse_slope,'inverse_derivative_valid',inverse_valid,...
    'tangent_x',tx,'tangent_y',ty,'tangent_floors',floors,'derivative_method',method,...
    'fit_performed',false,'uncertainty_available',false);
endfunction

function out=physical_query(model,query,options)
  orientation='y_of_x';if(isfield(options,'orientation')),orientation=options.orientation;endif
  if(!ischar(orientation)||!any(strcmp(orientation,{'y_of_x','x_of_y','r_of_theta','parametric'}))),error('GXTXT:Numeric:Options','Unknown physical query orientation');endif
  delta=[0;0];if(isfield(options,'translation')),delta=options.translation;endif
  if(!isnumeric(delta)||!isreal(delta)||numel(delta)!=2||any(!isfinite(delta(:)))),error('GXTXT:Numeric:Options','Two finite fitted-coordinate translations are required');endif
  if(!isfield(options,'domain')||!isnumeric(options.domain)||numel(options.domain)!=2),error('GXTXT:Numeric:Domain','Physical training domain is required');endif
  if(!isnumeric(query)||!isreal(query)||!isvector(query)||isempty(query)||any(!isfinite(query(:)))),error('GXTXT:Numeric:Query','Finite physical query values are required');endif
  delta=gxtxt_numeric_query_double_v1(delta(:));query=gxtxt_numeric_query_double_v1(query(:));core=options;
  core.domain=gxtxt_numeric_query_double_v1(options.domain);
  for key={'orientation','translation','polar_frame'},if(isfield(core,key{1})),core=rmfield(core,key{1});endif;endfor
  floors=[0;0];if(isfield(core,'tangent_floors')),floors=core.tangent_floors;endif
  if(!isnumeric(floors)||!isreal(floors)||numel(floors)!=2||any(!isfinite(floors(:)))||any(floors(:)<0)),error('GXTXT:Numeric:Options','Two nonnegative finite physical tangent floors are required');endif
  floors=gxtxt_numeric_query_double_v1(floors);core.tangent_floors=[0;0];input=query;
  if(!strcmp(orientation,'parametric')),input=query+delta(1);core.domain=core.domain+delta(1);endif
  out=gxtxt_numeric_model_query_v1(model,input,core);
  if(out.parametric!=strcmp(orientation,'parametric')),error('GXTXT:Numeric:Model','Declared query orientation differs from model geometry');endif
  response=out.predicted-delta(2);tx=out.tangent_x;ty=out.tangent_y;
  if(strcmp(orientation,'parametric'))
    points=[out.points(:,1)-delta(1),out.points(:,2)-delta(2)];
  elseif(strcmp(orientation,'x_of_y'))
    points=[response,query];temp=tx;tx=ty;ty=temp;
  elseif(strcmp(orientation,'r_of_theta'))
    if(!isfield(options,'polar_frame')),error('GXTXT:Numeric:Options','Radial query requires its captured polar frame');endif
    frame=options.polar_frame;
    if(!strcmp(out.derivative_method,'not_requested')),frame.radius_derivative=ty;endif
    mapped=gxtxt_numeric_v1('cartesian_coordinates',query,response,frame);points=mapped.points;
    if(isfield(mapped,'tangent_x')),tx=mapped.tangent_x;ty=mapped.tangent_y;endif
  else,points=[query,response];endif
  regular=isfinite(tx)&isfinite(ty);valid=regular&abs(tx)>floors(1);inverse_valid=regular&abs(ty)>floors(2);
  slope=NaN(size(query));inverse=slope;slope(valid)=ty(valid)./tx(valid);inverse(inverse_valid)=tx(inverse_valid)./ty(inverse_valid);
  valid=valid&isfinite(slope);inverse_valid=inverse_valid&isfinite(inverse);slope(!valid)=NaN;inverse(!inverse_valid)=NaN;
  out.model_response_derivative=out.derivative;
  out.query=query;out.predicted=response;out.points=points;out.domain=double(options.domain(:));out.translation=delta;out.orientation=orientation;
  out.is_extrapolated=query<out.domain(1)|query>out.domain(2);
  out.tangent_x=tx;out.tangent_y=ty;out.derivative=slope;out.derivative_valid=valid;
  out.inverse_derivative=inverse;out.inverse_derivative_valid=inverse_valid;out.tangent_floors=floors(:);
endfunction
