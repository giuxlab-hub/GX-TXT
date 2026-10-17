% Exact retained geometry conversion, never a second fit or sampled inference.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_model_geometry_v1(model,options)
  if(ischar(model)),model=gxtxt_numeric_model_state_decode_v1(model);endif
  allowed={'domain','orientation','translation','polar_frame','extrapolation'};
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),allowed)))
    error('GXTXT:Numeric:Options','Unknown model geometry option');
  endif
  if(!isfield(options,'domain')||!isnumeric(options.domain)||!isreal(options.domain)||numel(options.domain)!=2||any(!isfinite(options.domain(:)))||options.domain(1)>=options.domain(2))
    error('GXTXT:Numeric:Domain','Geometry requires two increasing finite parameter-domain endpoints');
  endif
  domain=gxtxt_numeric_query_double_v1(options.domain(:));
  orientation='y_of_x';if(isfield(options,'orientation')),orientation=options.orientation;endif
  delta=[0;0];if(isfield(options,'translation')),delta=gxtxt_numeric_query_double_v1(options.translation(:));endif
  if(numel(delta)!=2||!isreal(delta)||any(!isfinite(delta))),error('GXTXT:Numeric:Options','Geometry requires two finite translations');endif
  options.orientation=orientation;options.translation=delta;options.derivative=true;
  % Validate the captured frame and intrinsic domain even for an unsupported
  % representation. A malformed model must not become an approximation silently.
  if(isfield(model,'kind')&&strcmp(model.kind,'rational'))
    % Geometry selects an output interval; query bounds retain training meaning.
    options.domain=model.declared_domain;if(isfield(model,'observation_domain')),options.domain=model.observation_domain;endif
  endif
  if(isfield(model,'model')&&any(strcmp(model.model,{'akima','bspline'}))),options.domain=model.knots([1,end])-delta(1);endif
  ends=gxtxt_numeric_v1('model_query',model,domain,options);
  if(isfield(ends,'valid')&&any(!ends.valid)),error('GXTXT:Numeric:Domain','Retained geometry requires available roots at both domain endpoints');endif
  out=struct('schema','gxtxt.model_geometry.v1','status','sampled_required',...
    'reason','no_exact_native2d_primitive','parameter_domain',domain,...
    'parameter_breaks',domain,'parameter_mapping','piecewise_affine',...
    'fit_performed',false,'definition',struct());
  if(strcmp(orientation,'r_of_theta')),out.reason='radial_mapping_requires_sampled_geometry';return;endif
  degree=Inf;knots=[];kind='';
  if(isfield(model,'kind')&&strcmp(model.kind,'polynomial_export'))
    degree=numel(model.coefficients)-1;
  elseif(isfield(model,'kind')&&strcmp(model.kind,'linear'))
    degree=1;
  elseif(isfield(model,'model'))
    kind=model.model;
    switch(kind)
      case {'quadratic_bezier','cubic_bezier','parametric_polynomial'},degree=model.degree;
      case {'pchip','smoothing_spline'},degree=3;knots=model.source_x(:)-delta(1);
      case {'akima','bspline'},degree=model.degree;knots=model.knots(:)-delta(1);
      case 'parametric_spline',degree=3;knots=model.knots(:);
      case 'circular_arc'
        sweep=model.angle_end-model.angle_start;
        start=model.angle_start+domain(1)*sweep;span=diff(domain)*sweep;
        if(abs(span)>2*pi+1e-12),out.reason='arc_sweep_exceeds_one_turn';return;endif
        out.definition=struct('family','arc','controls',[model.center_x-delta(1),model.center_y-delta(2)],...
          'radius_x',model.radius,'radius_y',model.radius,'angle_start',start,'angle_sweep',span);
        out.status='exact';out.reason='retained_circular_arc';return;
    endswitch
  endif
  if(degree>3),return;endif
  breaks=unique([domain(1);knots(knots>domain(1)&knots<domain(2));domain(2)]);
  if(numel(breaks)>257),out.reason='native2d_composition_limit_256_parts';return;endif
  values=gxtxt_numeric_v1('model_query',model,breaks,options);
  if(degree>1&&(any(!isfinite(values.tangent_x))||any(!isfinite(values.tangent_y))))
    error('GXTXT:Numeric:Model','Exact polynomial conversion requires finite analytic tangents');
  endif
  parts=cell(numel(breaks)-1,1);
  for i=1:numel(parts)
    p=values.points(i,:);q=values.points(i+1,:);h=breaks(i+1)-breaks(i);
    if(degree<=1),definition=struct('family','line','controls',[p;q]);
    else
      % Cubic Hermite-to-Bezier identity is exact on each known polynomial
      % span. This is not interpolation of arbitrary fitted functions.
      a=[values.tangent_x(i),values.tangent_y(i)];b=[values.tangent_x(i+1),values.tangent_y(i+1)];
      definition=struct('family','cubic_bezier','controls',[p;p+h*a/3;q-h*b/3;q]);
    endif
    parts{i}=struct('definition',definition,'reversed',false);
  endfor
  if(numel(parts)==1),out.definition=parts{1}.definition;
  else
    closed=isfield(model,'topology')&&strcmp(model.topology,'closed')&&domain(1)==0&&domain(2)==1;
    scale=max(1,max(abs(values.points(:))));
    out.definition=struct('family','composite_path','parts',{parts},'closed',closed,'tolerance',64*eps(scale));
  endif
  out.status='exact';out.reason='retained_piecewise_polynomial';out.parameter_breaks=breaks;
endfunction
