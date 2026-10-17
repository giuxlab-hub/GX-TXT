% Physical rational functions share the formula compiler and Ceres numerical owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_rational_v1(action,varargin)
  switch(action)
    case 'compose',out=compose(varargin{1});
    case 'validate',out=validate(varargin{1});
    case 'domain'
      if(isstruct(varargin{1})&&isfield(varargin{1},'schema')),model=validate(varargin{1});else,model=compose(varargin{1});endif
      out=domain_receipt(model,varargin{2});
    case 'guard',model=validate(varargin{1});out=guard(model,varargin{2});
    case 'fit',out=fit_rational(varargin{:});
    case 'evaluate',out=evaluate(varargin{:});
    case 'residuals',out=residuals_model(varargin{:});
    case 'query',out=query_model(varargin{:});
    case 'state',out=state_model(varargin{1});
    case 'restore',out=restore_model(varargin{1});
    otherwise,fail('Unknown rational action');
  endswitch
endfunction
function model=compose(recipe)
  fields={'numerator_degree','denominator_degree','x_unit','y_unit','parameters','domain','pole_tolerance'};
  keys(recipe,fields,'rational recipe');
  if(!all(isfield(recipe,fields(1:6)))),fail('Rational recipe requires degrees, physical units, parameters and an explicit domain');endif
  m=degree(recipe.numerator_degree,0);n=degree(recipe.denominator_degree,1);d=domain(recipe.domain);
  tolerance=opt(recipe,'pole_tolerance',1e-10);
  if(!isnumeric(tolerance)||!isreal(tolerance)||!isscalar(tolerance)||!isfinite(tolerance)||tolerance<1e-12||tolerance>1e-2),fail('Pole tolerance must be1e-12..1e-2 relative to the denominator coefficient bound');endif
  params=recipe.parameters;if(isstruct(params)),params=num2cell(params);endif
  if(!iscell(params)||numel(params)!=m+n+1),fail('Rational parameters must be a0..aM followed by b1..bN; denominator constant is exactly one');endif
  numerator={};denominator={'1'};ids={};
  for k=0:m,ids{end+1}=sprintf('a%d',k);numerator{end+1}=term(ids{end},k);endfor
  for k=1:n,ids{end+1}=sprintf('b%d',k);denominator{end+1}=term(ids{end},k);endfor
  for k=1:numel(params)
    if(!isstruct(params{k})||!isfield(params{k},'id')||!strcmp(params{k}.id,ids{k})),fail('Rational coefficient identities and order are fixed by their powers');endif
  endfor
  formula_recipe=struct('expression',['(' strjoin(numerator,'+') ')/(' strjoin(denominator,'+') ')'],...
    'predictor_ids',{{'x'}},'predictor_units',{{recipe.x_unit}},'response_unit',recipe.y_unit,'parameters',{params});
  formula=gxtxt_numeric_v1('fit_formula_compose',formula_recipe);
  unit=gxtxt_unit_parse(recipe.y_unit);if(!strcmp(unit.kind,'linear')),fail('Rational response needs an explicit linear physical unit');endif
  % Normalize optional/default fields and inferred units at their existing owner.
  % Encode infinite bounds as signed text in the identity, never JSON null.
  for k=1:numel(params)
    params{k}=struct('id',ids{k},'unit',formula.parameter_units{k},'initial',formula.initial_parameters(k),...
      'lower',formula.parameter_constraints.lower_bounds(k),'upper',formula.parameter_constraints.upper_bounds(k),...
      'fixed',double(formula.parameter_constraints.fixed_mask(k)));
  endfor
  formula_recipe.parameters=params;formula=gxtxt_numeric_v1('fit_formula_compose',formula_recipe);
  normalized=struct('numerator_degree',m,'denominator_degree',n,'x_unit',recipe.x_unit,'y_unit',recipe.y_unit,...
    'parameters',{params},'domain',d,'pole_tolerance',double(tolerance));
  identity=normalized;
  for k=1:numel(params),identity.parameters{k}.lower=sprintf('%.17g',params{k}.lower);identity.parameters{k}.upper=sprintf('%.17g',params{k}.upper);endfor
  model=struct('schema','gxtxt.rational_model.v1','kind','rational','recipe',normalized,...
    'formula_model',formula,'parameter_ids',{formula.parameter_ids},'parameter_units',{formula.parameter_units},...
    'parameters',formula.initial_parameters,'initial_parameters',formula.initial_parameters,...
    'predictor_ids',{{'x'}},'predictor_unit',recipe.x_unit,'response_unit',recipe.y_unit,...
    'declared_domain',d,'pole_tolerance',double(tolerance),...
    'source_sha256',formula.source_sha256,'binding_sha256',formula.binding_sha256,...
    'declaration_sha256',hash('sha256',jsonencode(identity)));
endfunction
function model=validate(model)
  if(!isstruct(model)||!isscalar(model)||!isfield(model,'schema')||!strcmp(model.schema,'gxtxt.rational_model.v1')||!isfield(model,'recipe')),fail('A versioned rational model is required');endif
  expected=compose(model.recipe);
  for key={'schema','kind','parameter_ids','parameter_units','initial_parameters','predictor_ids','predictor_unit','response_unit','declared_domain','pole_tolerance','source_sha256','binding_sha256','declaration_sha256'}
    name=key{1};if(!isfield(model,name)||!isequaln(model.(name),expected.(name))),fail(['Rational declaration changed: ' name]);endif
  endfor
  formula=gxtxt_numeric_fit_formula_v1('validate',model.formula_model);
  for key={'expression','parameter_ids','parameter_units','predictor_ids','response_units','parameter_constraints','input_constraints','source_sha256','binding_sha256'}
    name=key{1};if(!isequaln(formula.(name),expected.formula_model.(name))),fail(['Rational formula identity differs: ' name]);endif
  endfor
  model.parameters=values(model.parameters,'rational parameters');model.parameters=model.parameters(:);
  if(any(!isfinite(model.parameters))||!isequaln(model.parameters,formula.parameters(:))),fail('Rational physical and formula parameter state differ');endif
  formula.formula_declaration=expected.formula_model.formula_declaration;model.formula_model=formula;
  if(isfield(model,'observation_domain'))
    d=domain(model.observation_domain);
    if(d(1)<model.declared_domain(1)||d(2)>model.declared_domain(2)),fail('Observation domain exceeds the declared rational domain');endif
    model.observation_domain=d;
  endif
endfunction
function out=domain_receipt(model,d)
  d=domain(d);m=model.recipe.numerator_degree;n=model.recipe.denominator_degree;
  scales=model.formula_model.formula_declaration.dimensional_receipt.symbol_scales;
  sx=scales.x;denominator=ones(1,n+1);numerator=zeros(1,m+1);
  for k=1:n,id=sprintf('b%d',k);denominator(n+1-k)=model.parameters(m+1+k)*scales.(id)*sx^k;endfor
  for k=0:m,id=sprintf('a%d',k);numerator(m+1-k)=model.parameters(k+1)*scales.(id)*sx^k;endfor
  if(any(!isfinite([denominator,numerator]))),fail('Physical rational coefficients overflow their coordinate basis');endif
  bound=polyval(abs(denominator),max(abs(d)));
  if(!isfinite(bound)||bound<=0),fail('Denominator scale is not numerically representable on this domain');endif
  % Convert Q(lo + span*t) to Bernstein coefficients on0..1. The convex-hull
  % property gives a whole-interval sign bound; roots are diagnostic only.
  power=denominator(1)/bound;span=d(2)-d(1);
  if(!isfinite(span)||span<=0),fail('Rational domain span is not numerically representable');endif
  for k=2:numel(denominator),power=conv(power,[span,d(1)]);power(end)+=denominator(k)/bound;endfor
  power=fliplr(power);bernstein=zeros(1,n+1);
  for k=0:n,for j=0:k,bernstein(k+1)+=power(j+1)*nchoosek(k,j)/nchoosek(n,j);endfor;endfor
  if(any(!isfinite(bernstein))),fail('Scaled denominator interval basis is not numerically representable');endif
  threshold=max(model.pole_tolerance,1024*eps);queue={bernstein};depths=0;visited=0;lower=Inf;status='safe';reason='Whole declared interval has a bounded nonzero denominator';
  while(!isempty(queue))
    b=queue{end};queue(end)=[];depth=depths(end);depths(end)=[];visited+=1;
    if(all(b>threshold)||all(b<-threshold)),lower=min(lower,min(abs(b)));continue;endif
    if(abs(b(1))<=threshold||abs(b(end))<=threshold||sign(b(1))!=sign(b(end)))
      status='unsafe';reason='Denominator reaches a pole or the declared relative near-zero threshold';lower=0;break;
    endif
    if(depth>=24||visited>=4096),status='unresolved';reason='Bounded interval subdivision could not establish a separated denominator';lower=0;break;endif
    left=zeros(size(b));right=left;left(1)=b(1);right(end)=b(end);
    for level=1:n,b=(b(1:end-1)+b(2:end))/2;left(level+1)=b(1);right(end-level)=b(end);endfor
    queue(end+1:end+2)={left,right};depths(end+1:end+2)=[depth+1,depth+1];
  endwhile
  poles=roots(denominator);zeros_=roots(numerator);common=false;
  for k=1:numel(poles),if(any(abs(zeros_-poles(k))<=1e-7*max(1,abs(poles(k))))),common=true;endif;endfor
  if(any(!isfinite([poles(:);zeros_(:)]))),fail('Polynomial root diagnostics are not numerically representable');endif
  out=struct('schema','gxtxt.rational_domain.v1','status',status,'reason',reason,'domain',d,...
    'coordinate_unit',model.predictor_unit,'denominator_constant',1,'numerator_degree',m,'denominator_degree',n,...
    'denominator_coefficients_descending',denominator,'denominator_coefficient_bound',bound,...
    'relative_margin_lower_bound',lower,'pole_tolerance',model.pole_tolerance,'interval_nodes',visited,...
    'method','bounded_binary64_Bernstein_sign_guard','root_method','Octave_roots_diagnostic_only',...
    'poles_real_imag',[real(poles(:)),imag(poles(:))],'possible_common_factor',common,...
    'cancellation_policy','no_automatic_factor_cancellation','parameters',model.parameters,...
    'declaration_sha256',model.declaration_sha256,'source_sha256',model.source_sha256,'binding_sha256',model.binding_sha256);
endfunction
function receipt=guard(model,d)
  receipt=domain_receipt(model,d);
  if(!strcmp(receipt.status,'safe')),fail(['Unsafe rational domain: ' receipt.reason]);endif
endfunction
function out=fit_rational(model,x,y,options)
  model=validate(model);x=values(x,'rational X');y=values(y,'rational Y');
  keys(options,{'nonfinite','sigma','weights','weight_semantics','solver','strategy','max_iterations','max_seconds','function_tolerance','gradient_tolerance','parameter_tolerance','tolerance','parameter_scales','threads'},'rational fit options');
  if(!isvector(x)||!isvector(y)||numel(x)!=numel(y)||numel(x)<2||numel(x)>1000000),fail('Rational fit needs2..1000000 paired observations');endif
  x=x(:);y=y(:);finite_x=x(isfinite(x));d=model.declared_domain;
  if(isempty(finite_x)||any(finite_x<d(1)|finite_x>d(2))),fail('Rational observations exceed their declared physical domain');endif
  guard(model,d);solver=options;
  if(!isfield(solver,'max_iterations')),solver.max_iterations=400;endif
  if(!isfield(solver,'max_seconds')),solver.max_seconds=30;endif
  solver.loss='linear';
  fit=gxtxt_numeric_v1('nonlinear_fit',model.formula_model,x,y,model.parameters,solver);
  model.parameters=fit.parameters;model.formula_model=fit.model;
  kept=x(fit.source_row_positions);model.observation_domain=domain([min(kept),max(kept)]);
  receipt=guard(model,d);
  out=fit;out.operation='rational_fit';out.solver_model=fit.model;out.model=model;
  out.rational_summary=struct('schema','gxtxt.rational_fit_summary.v1','numeric_api','NUMERIC_API_v1','operation','rational_fit',...
    'domain_receipt',receipt,'observation_domain',model.observation_domain,'parameter_ids',{model.parameter_ids},...
    'parameter_units',{model.parameter_units},'predictor_unit',model.predictor_unit,'response_unit',model.response_unit,...
    'fit_geometry','vertical_response','normalization','denominator_constant_one','approximation','rational_least_squares_not_Taylor_Pade_matching',...
    'inference_scope','local_conditional_on_fixed_degrees_domain_and_response_noise');
endfunction
function out=evaluate(model,x,options)
  model=validate(model);keys(options,{'extrapolation','jacobian','predictor_derivative'},'rational evaluation options');
  x=values(x,'rational query');if(!isvector(x)||numel(x)>1000000||any(!isfinite(x))),fail('Rational query requires1..1000000 finite coordinates');endif;x=x(:);
  d=opt(model,'observation_domain',model.declared_domain);outside=x<d(1)|x>d(2);
  policy=opt(options,'extrapolation','error');if(!ischar(policy)||!any(strcmp(policy,{'error','allow'}))),fail('Extrapolation must be error or explicit allow');endif
  if(any(outside)&&strcmp(policy,'error')),fail('Rational query lies outside its retained domain');endif
  checked=[min([model.declared_domain(1);x]),max([model.declared_domain(2);x])];receipt=guard(model,checked);
  opts=rmfield(options,intersect(fieldnames(options),{'extrapolation'}));
  out=gxtxt_numeric_v1('nonlinear_evaluate',model.formula_model,x,opts);
  % Native evaluate may return zero-response residual fields for Jacobian work.
  % This public retained evaluator exposes predictions/derivatives only.
  keep={'predicted','jacobian','predictor_derivative','derivative_valid','derivative_method','parameter_ids','predictor_ids','source_sha256','binding_sha256'};
  out=rmfield(out,setdiff(fieldnames(out),keep));out.schema='gxtxt.rational_evaluation.v1';
  out.query=x;out.points=[x,out.predicted];out.domain=d;out.is_extrapolated=outside;
  out.coordinate_units={model.predictor_unit,model.response_unit};out.domain_receipt=receipt;out.fit_performed=false;
endfunction
function out=residuals_model(model,x,y,options)
  model=validate(model);keys(options,{'extrapolation'},'rational residual options');
  x=values(x,'rational residual X');y=values(y,'rational residual Y');
  if(!isvector(x)||!isvector(y)||numel(x)!=numel(y)||isempty(x)||numel(x)>1000000||any(!isfinite(x))||any(!isfinite(y))),fail('Rational residuals require1..1000000 finite exact coordinate/response pairs');endif
  x=x(:);y=y(:);evaluated=evaluate(model,x,options);
  out=gxtxt_numeric_v1('residual_metrics',y,evaluated.predicted,struct());
  difference=gxtxt_numeric_v1('array_binary','subtract',y,evaluated.predicted,struct());
  out.operation='rational_residuals';out.parameters=model.parameters;out.model=model;
  out.predicted=evaluated.predicted;out.residuals=difference.values;out.fit_performed=false;
  out.weight_semantics='unweighted';out.is_extrapolated=evaluated.is_extrapolated;
  out.rational_summary=struct('schema','gxtxt.rational_residual_summary.v1','numeric_api','NUMERIC_API_v1','operation','rational_residuals',...
    'domain_receipt',evaluated.domain_receipt,'observation_domain',opt(model,'observation_domain',model.declared_domain),'parameter_ids',{model.parameter_ids},...
    'parameter_units',{model.parameter_units},'predictor_unit',model.predictor_unit,'response_unit',model.response_unit,...
    'fit_geometry','vertical_response','normalization','denominator_constant_one','approximation','rational_least_squares_not_Taylor_Pade_matching',...
    'inference_scope','descriptive_evaluation_at_captured_parameters_no_parameter_inference','evaluation_count',numel(x),'evaluation_domain',[min(x),max(x)]);
endfunction
function out=query_model(model,x,options)
  model=validate(model);d=opt(model,'observation_domain',model.declared_domain);
  if(!isfield(options,'domain')||!isequal(domain(options.domain),d)),fail('Retained rational query must use its captured domain');endif
  checked=evaluate(model,x,struct('extrapolation',opt(options,'extrapolation','error')));
  out=gxtxt_numeric_v1('model_query',model.formula_model,x,options);
  out.rational_domain=checked.domain_receipt;
endfunction
function out=state_model(model)
  model=validate(model);guard(model,model.declared_domain);
  out=struct('schema','gxtxt.rational_state.v1','recipe',model.recipe,'parameters',model.parameters,...
    'declaration_sha256',model.declaration_sha256,'source_sha256',model.source_sha256,'binding_sha256',model.binding_sha256);
  if(isfield(model,'observation_domain')),out.observation_domain=model.observation_domain;endif
endfunction
function model=restore_model(state)
  keys(state,{'schema','recipe','parameters','observation_domain','declaration_sha256','source_sha256','binding_sha256'},'rational state');
  if(!isfield(state,'schema')||!strcmp(state.schema,'gxtxt.rational_state.v1')),fail('Versioned rational state required');endif
  model=compose(state.recipe);
  for key={'declaration_sha256','source_sha256','binding_sha256'},if(!isfield(state,key{1})||!strcmp(state.(key{1}),model.(key{1}))),fail('Retained rational declaration identity changed');endif;endfor
  model.parameters=values(state.parameters,'retained rational parameters');model.parameters=model.parameters(:);model.formula_model.parameters=model.parameters;
  if(isfield(state,'observation_domain')),model.observation_domain=state.observation_domain;endif
  model=validate(model);guard(model,model.declared_domain);
endfunction
function x=values(x,label)
  if(!isnumeric(x)||!isreal(x)||isempty(x)||ndims(x)>2),fail([label ' requires nonempty real values']);endif
  x=gxtxt_numeric_query_double_v1(x);
endfunction
function d=domain(d),d=values(d,'rational domain');d=d(:).';if(numel(d)!=2||any(!isfinite(d))||d(1)>=d(2)),fail('Rational domain must be finite and increasing');endif;endfunction
function d=degree(d,lo),if(!isnumeric(d)||!isreal(d)||!isscalar(d)||!isfinite(d)||d!=fix(d)||d<lo||d>8),fail('Rational numerator degree is0..8 and denominator degree1..8');endif;d=double(d);endfunction
function s=term(id,power),s=id;if(power>0),s=sprintf('%s*x^%d',id,power);endif;endfunction
function v=opt(s,k,fallback),v=fallback;if(isfield(s,k)),v=s.(k);endif;endfunction
function keys(s,allowed,label),if(!isstruct(s)||!isscalar(s)||!isempty(setdiff(fieldnames(s),allowed))),fail(['Unknown field or invalid ' label]);endif;endfunction
function fail(message),error('GXTXT:Numeric:Rational','%s',message);endfunction
