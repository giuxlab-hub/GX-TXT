% Explicit physical knots through the existing curve_model_* public contract.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_knot_splines_v1(operation,varargin)
  switch(operation)
    case 'fit',out=fit_model(varargin{:});
    case 'evaluate',out=evaluate(varargin{:});
    case 'validate',out=validate(varargin{1});
    otherwise,error('GXTXT:Numeric:Knots','Unknown knot model operation');
  endswitch
endfunction
function out=fit_model(name,x,y,options)
  x=vector(x,2,65536,'predictors');y=vector(y,2,65536,'responses');
  if(numel(x)!=numel(y)||any(diff(x)<=0)),error('GXTXT:Numeric:Knots','Knot models require paired strictly increasing predictors; no implicit sorting or averaging');endif
  keys(options,{'knots','degree','boundary','endpoint_slopes','x_unit','y_unit'});
  if(!any(strcmp(name,{'akima','bspline'}))),error('GXTXT:Numeric:Knots','Unknown knot model');endif
  endpoint=[];degree=3;boundary=option(options,'boundary','extrapolated_slopes');
  if(isfield(options,'endpoint_slopes')),endpoint=vector(options.endpoint_slopes,2,2,'endpoint slopes');endif
  if(strcmp(name,'akima'))
    if(numel(x)<5||isfield(options,'knots')||isfield(options,'degree')),error('GXTXT:Numeric:Knots','Akima needs at least five original knots and has fixed cubic degree');endif
    if(!any(strcmp(boundary,{'extrapolated_slopes','clamped'}))),error('GXTXT:Numeric:Knots','Akima boundary must be extrapolated_slopes or clamped');endif
    h=diff(x);secants=diff(y)./h;
    % Akima's local secant-variation weighting; zero weights use the two
    % adjacent slopes' mean. Endpoint extension is declared, not extra data.
    extended=[3*secants(1)-2*secants(2);2*secants(1)-secants(2);secants;2*secants(end)-secants(end-1);3*secants(end)-2*secants(end-1)];
    n=numel(x);left=abs(extended(4:n+3)-extended(3:n+2));right=abs(extended(2:n+1)-extended(1:n));
    scale=max(left,right);slope=.5*extended(2:n+1)+.5*extended(3:n+2);active=scale>0;
    a=left(active)./scale(active);b=right(active)./scale(active);
    slope(active)=(a.*extended(find(active)+1)+b.*extended(find(active)+2))./(a+b);
    if(strcmp(boundary,'clamped'))
      if(numel(endpoint)!=2),error('GXTXT:Numeric:Knots','Clamped Akima requires two physical endpoint slopes');endif
      slope([1,end])=endpoint;
    elseif(!isempty(endpoint)),error('GXTXT:Numeric:Knots','Endpoint slopes apply only to a clamped boundary');endif
    coefs=[(slope(1:end-1)+slope(2:end)-2*secants)./h.^2,(3*secants-2*slope(1:end-1)-slope(2:end))./h,slope(1:end-1),y(1:end-1)];
    knots=x;method='interpolation';continuity=1;construction='akima_local_secant_variation';complexity=numel(x);
  else
    degree=option(options,'degree',3);boundary=option(options,'boundary','free');
    if(!isnumeric(degree)||!isreal(degree)||!isscalar(degree)||!ismember(degree,1:3)),error('GXTXT:Numeric:Knots','B-spline degree must be1,2 or3');endif
    if(!isfield(options,'knots')),error('GXTXT:Numeric:Knots','B-spline requires explicit knots including both domain endpoints');endif
    knots=vector(options.knots,2,257,'knots');
    if(any(diff(knots)<=0)||knots(1)!=x(1)||knots(end)!=x(end)),error('GXTXT:Numeric:Knots','Simple knots must strictly increase and match the observation domain endpoints exactly');endif
    if(!any(strcmp(boundary,{'free','natural','clamped','periodic'}))),error('GXTXT:Numeric:Knots','B-spline boundary must be free, natural, clamped or periodic');endif
    if(any(strcmp(boundary,{'natural','clamped'}))&&degree!=3),error('GXTXT:Numeric:Knots','Natural or clamped boundary requires cubic degree');endif
    if(!strcmp(boundary,'clamped')&&!isempty(endpoint)),error('GXTXT:Numeric:Knots','Endpoint slopes apply only to a clamped boundary');endif
    if(strcmp(boundary,'clamped')&&numel(endpoint)!=2),error('GXTXT:Numeric:Knots','Clamped B-spline requires two physical endpoint slopes');endif
    % A conservative sufficient sampling rule prevents empty/underidentified
    % spans without claiming a numerical rank or inventing parameter inference.
    for k=1:numel(knots)-1
      count=sum(x>=knots(k)&x<=knots(k+1));
      if(count<degree+1),error('GXTXT:Numeric:Knots','Each knot span requires at least degree+1 distinct observations');endif
    endfor
    args={'order',degree};complexity=numel(knots)-1+degree;
    if(strcmp(boundary,'periodic')),args=[args,{'periodic',true}];complexity=numel(knots)-1;
    elseif(any(strcmp(boundary,{'natural','clamped'})))
      cc=zeros(degree+1,2);values=[0,0];
      if(strcmp(boundary,'natural')),cc(3,:)=1;else cc(2,:)=1;values=endpoint(:).';endif
      args=[args,{'constraints',struct('xc',knots([1,end]).','yc',values,'cc',cc)}];complexity-=2;
    endif
    pp=splinefit(x,y,knots.',args{:});
    if(!isequal(pp.breaks(:),knots)||pp.order!=degree+1||pp.dim!=1),error('GXTXT:Numeric:Knots','Existing B-spline backend changed the declared knot geometry');endif
    coefs=[zeros(rows(pp.coefs),3-degree),pp.coefs];method='least_squares_approximation';continuity=degree-1;construction='GNU_Octave_splinefit_bspline_least_squares';
  endif
  if(any(!isfinite(coefs(:)))),error('GXTXT:Numeric:Knots','Knot construction produced nonfinite coefficients');endif
  out=struct('schema','gxtxt.knot_spline.v1','model',name,'parametric',false,'degree',degree,...
    'knots',knots,'coefficients_y',coefs,'boundary_condition',boundary,'endpoint_slopes',endpoint,...
    'continuity_order',continuity,'method_class',method,'construction',construction,...
    'source_count',numel(x),'basis_dimension',complexity,'parameters',[],...
    'x_unit',unit(option(options,'x_unit','1')),'y_unit',unit(option(options,'y_unit','1')),...
    'extrapolation','error','coefficient_coordinate','physical_x_minus_left_knot');
  out.state_sha256=digest(out);out=validate(out);
  predicted=evaluate(out,x,struct());residual=gxtxt_numeric_v1('residual_metrics',y,predicted.y);
  out.knot_summary=summary(out);out.n=numel(x);out.sse=residual.sse;
  out.rmse=residual.rmse;out.mae=residual.mae;out.max_abs_error=residual.max_abs_error;
  out.fit_performed=strcmp(name,'bspline');
endfunction
function out=evaluate(model,q,options)
  model=validate(model);q=vector(q,1,1000000,'query');keys(options,{'derivative','extrapolation'});
  derivative=option(options,'derivative',false);policy=option(options,'extrapolation','error');
  if(!(islogical(derivative)||isnumeric(derivative))||!isscalar(derivative)||!isreal(derivative)||!ismember(derivative,[0,1])||!any(strcmp(policy,{'error','allow'}))),error('GXTXT:Numeric:Knots','Use boolean derivative and error or explicit allow extrapolation');endif
  outside=q<model.knots(1)|q>model.knots(end);
  if(strcmp(policy,'error')&&any(outside)),error('GXTXT:Numeric:Knots','Query lies outside the retained knot domain');endif
  i=max(1,min(lookup(model.knots,q),numel(model.knots)-1));u=q-model.knots(i);c=model.coefficients_y(i,:);
  y=((c(:,1).*u+c(:,2)).*u+c(:,3)).*u+c(:,4);
  if(any(!isfinite(y))),error('GXTXT:Numeric:Knots','Boundary polynomial evaluation is nonfinite');endif
  out=struct('x',q,'y',y,'points',[q,y],'is_extrapolated',outside,'extrapolation_method','boundary_polynomial','fit_performed',false,'state_sha256',model.state_sha256);
  if(derivative)
    out.tangent_x=ones(size(q));out.tangent_y=(3*c(:,1).*u+2*c(:,2)).*u+c(:,3);
    if(model.degree==1)
      interior=i>1&q==model.knots(i);j=find(interior);
      left=model.coefficients_y(i(j)-1,3);right=model.coefficients_y(i(j),3);
      jumps=abs(left-right)>64*eps.*max(1,max(abs(left),abs(right)));out.tangent_y(j(jumps))=NaN;
    endif
  endif
endfunction
function model=validate(model)
  fields={'schema','model','parametric','degree','knots','coefficients_y','boundary_condition','endpoint_slopes','continuity_order','method_class','construction','source_count','basis_dimension','parameters','x_unit','y_unit','extrapolation','coefficient_coordinate','state_sha256'};
  if(!isstruct(model)||numel(model)!=1||!all(isfield(model,fields))),error('GXTXT:Numeric:Knots','Incomplete retained knot state');endif
  if(!strcmp(model.schema,'gxtxt.knot_spline.v1')||!any(strcmp(model.model,{'akima','bspline'}))||model.parametric||!isempty(model.parameters)||!ismember(model.degree,1:3)||!isscalar(model.degree)),error('GXTXT:Numeric:Knots','Invalid retained knot model identity');endif
  k=vector(model.knots,2,65536,'retained knots');c=model.coefficients_y;
  if(any(diff(k)<=0)||!isnumeric(c)||!isreal(c)||!isequal(size(c),[numel(k)-1,4])||any(!isfinite(c(:)))||any(any(c(:,1:3-model.degree)!=0))),error('GXTXT:Numeric:Knots','Invalid retained piecewise polynomial');endif
  for key={'source_count','basis_dimension','continuity_order'}
    value=model.(key{1});if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)||value!=fix(value)||value<0||value>65536),error('GXTXT:Numeric:Knots','Invalid bounded knot complexity');endif
  endfor
  unit(model.x_unit);unit(model.y_unit);
  if(!strcmp(model.extrapolation,'error')||!strcmp(model.coefficient_coordinate,'physical_x_minus_left_knot')),error('GXTXT:Numeric:Knots','Retained coordinate or extrapolation identity changed');endif
  if(!ischar(model.state_sha256)||!strcmp(model.state_sha256,digest(model))),error('GXTXT:Numeric:Knots','Retained knot coefficients, boundary or identity changed');endif
  model.knots=k;
endfunction
function s=summary(m)
  s=struct('schema','gxtxt.knot_spline_summary.v1','numeric_api','NUMERIC_API_v1','model',m.model,...
    'method_class',m.method_class,'degree',m.degree,'continuity_order',m.continuity_order,...
    'boundary_condition',m.boundary_condition,'knot_count',numel(m.knots),'domain',m.knots([1,end]).',...
    'source_count',m.source_count,'basis_dimension',m.basis_dimension,'state_sha256',m.state_sha256,...
    'predictor_unit',m.x_unit,'response_unit',m.y_unit,'inference_scope','descriptive_no_parameter_inference');
endfunction
function value=digest(m)
  strings={m.schema,m.model,m.boundary_condition,m.method_class,m.construction,m.x_unit,m.y_unit,m.extrapolation,m.coefficient_coordinate};
  text='';for k=1:numel(strings),v=strings{k};if(!ischar(v)||rows(v)!=1||numel(v)>256||any(v<32)),error('GXTXT:Numeric:Knots','Invalid knot state text');endif;text=[text,sprintf('%d:',numel(v)),v];endfor
  values=[m.degree;m.continuity_order;m.source_count;m.basis_dimension;numel(m.knots);m.knots(:);m.coefficients_y(:);m.endpoint_slopes(:)];
  value=hash('sha256',[text,sprintf('%.17g,',values)]);
endfunction
function v=vector(v,lo,hi,label)
  if(!isnumeric(v)||!isreal(v)||!isvector(v)||numel(v)<lo||numel(v)>hi||any(!isfinite(v(:)))),error('GXTXT:Numeric:Knots','Invalid bounded finite %s',label);endif
  v=gxtxt_numeric_query_double_v1(v(:));
endfunction
function keys(s,allowed)
  if(!isstruct(s)||numel(s)!=1||!isempty(setdiff(fieldnames(s),allowed))),error('GXTXT:Numeric:Knots','Unknown knot model options');endif
endfunction
function v=unit(v)
  if(!ischar(v)||rows(v)!=1||isempty(v)||numel(v)>256||any(v<32)),error('GXTXT:Numeric:Knots','Explicit coordinate units are required');endif
endfunction
function v=option(s,key,fallback),v=fallback;if(isfield(s,key)),v=s.(key);endif;endfunction
