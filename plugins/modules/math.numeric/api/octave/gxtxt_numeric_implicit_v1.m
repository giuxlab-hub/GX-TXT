% Implicit equations reuse formula units, Ceres, AD and the public root owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_implicit_v1(action,varargin)
  switch(action)
    case 'compose',out=compose(varargin{1});
    case 'validate',out=validate_model(varargin{1});
    case 'fit',out=fit_equation(varargin{:});
    case 'evaluate',out=evaluate_equation(varargin{:});
    case 'query',out=query_branch(varargin{:});
    otherwise,fail('Unknown implicit model action');
  endswitch
endfunction
function model=compose(recipe)
  keys(recipe,{'formula','residual_mode','normalization'},'implicit recipe');
  if(!isfield(recipe,'formula')||!isfield(recipe,'residual_mode')),fail('Declare a physical formula and residual_mode');endif
  mode=recipe.residual_mode;
  if(!ischar(mode)||!any(strcmp(mode,{'algebraic','normalized_algebraic'}))),fail('Implicit residual_mode is algebraic or normalized_algebraic; neither is an ODR distance');endif
  equation=gxtxt_numeric_v1('fit_formula_compose',recipe.formula);
  if(numel(equation.predictor_ids)!=2||numel(equation.parameter_ids)>32),fail('Implicit equations require exactly two coordinate symbols and1..32 parameters');endif
  unit=recipe.formula.response_unit;
  scale=1;objective_unit_rule='square_residual_unit';
  if(strcmp(mode,'normalized_algebraic'))
    if(!isfield(recipe,'normalization')),fail('Normalized algebraic residuals need an explicit physical reference scale');endif
    norm=recipe.normalization;keys(norm,{'value','unit','role'},'implicit normalization');
    if(!isfield(norm,'value')||!isfield(norm,'unit')||!isfield(norm,'role')||!strcmp(norm.role,'reference_scale')||!strcmp(norm.unit,unit)),fail('Normalization must be an explicit reference_scale already in the equation residual unit; it is not a measurement sigma');endif
    scale=positive(norm.value,'normalization value');objective_unit_rule='dimensionless';
    if(!isfinite(1/scale^2)||1/scale^2<=0),fail('Normalization produces an unrepresentable squared objective scale');endif
  elseif(isfield(recipe,'normalization'))
    fail('Algebraic residuals do not accept a hidden normalization');
  endif
  normalization=struct('value',scale,'unit',unit,'role','reference_scale');
  identity=struct('schema','gxtxt.implicit_model.v1','formula',equation.formula_declaration,...
    'residual_mode',mode,'normalization',normalization);
  model=struct('schema','gxtxt.implicit_model.v1','kind','implicit','recipe',recipe,...
    'equation_model',equation,'parameter_ids',{equation.parameter_ids},'parameter_units',{equation.parameter_units},...
    'predictor_ids',{equation.predictor_ids},'predictor_units',{reshape(recipe.formula.predictor_units,1,[])},...
    'parameters',equation.initial_parameters,'initial_parameters',equation.initial_parameters,...
    'residual_mode',mode,'normalization',normalization,'residual_unit',unit,'objective_unit_rule',objective_unit_rule,...
    'declaration_sha256',hash('sha256',jsonencode(identity)),...
    'fit_geometry','implicit_algebraic','residual_definition','zero_minus_equation_value_at_observed_coordinates',...
    'response_branch','not_declared','measurement_error_distance',false);
endfunction
function model=validate_model(model)
  if(!isstruct(model)||numel(model)!=1||!isfield(model,'schema')||!strcmp(model.schema,'gxtxt.implicit_model.v1')||!isfield(model,'recipe')),fail('A versioned immutable implicit declaration is required');endif
  expected=compose(model.recipe);
  for item={'schema','kind','parameter_ids','parameter_units','predictor_ids','predictor_units','initial_parameters','residual_mode','normalization','residual_unit','objective_unit_rule','declaration_sha256','fit_geometry','residual_definition','response_branch','measurement_error_distance'}
    name=item{1};if(!isfield(model,name)||!isequaln(model.(name),expected.(name))),fail(['Implicit model differs from its declaration: ' name]);endif
  endfor
  values=finite_vector(model.parameters,'implicit parameter values',32);
  constraints=expected.equation_model.parameter_constraints;
  if(numel(values)!=numel(expected.parameter_ids)||any(values<constraints.lower_bounds)||any(values>constraints.upper_bounds)||any(values(logical(constraints.fixed_mask))!=constraints.initial_parameters(logical(constraints.fixed_mask))))
    fail('Implicit parameters violate their physical declaration');
  endif
  equation=gxtxt_numeric_fit_formula_v1('validate',model.equation_model);
  if(!isequaln(equation.formula_declaration.recipe,model.recipe.formula)||!isequaln(equation.parameters(:),values)),fail('Implicit equation state and parameter values differ');endif
  model.parameters=values;
endfunction
function [x,y]=coordinates(x,y)
  x=finite_vector(x,'first coordinate',65536);y=finite_vector(y,'second coordinate',65536);
  if(numel(x)!=numel(y)),fail('Implicit coordinates require matched original observations');endif
endfunction
function out=fit_equation(model,x,y,options)
  model=validate_model(model);[x,y]=coordinates(x,y);
  if(numel(x)<2),fail('Implicit fitting requires at least two observations');endif
  allowed={'solver','strategy','max_iterations','max_seconds','function_tolerance','gradient_tolerance','parameter_tolerance','tolerance','loss','loss_scale','lower_bounds','upper_bounds','fixed_mask','parameter_scales','threads'};
  keys(options,allowed,'implicit solver options');
  if(!isfield(options,'max_iterations')),options.max_iterations=400;endif
  if(!isfield(options,'max_seconds')),options.max_seconds=30;endif
  options.nonfinite='error';options.weights=ones(numel(x),1)/model.normalization.value^2;
  options.weight_semantics='relative';options.fit_geometry='vertical_response';
  % The existing solver fits equation outputs to zero. Its internal response
  % geometry is never exposed as a physical Y distance for this model.
  fitted=gxtxt_numeric_v1('nonlinear_fit',model.equation_model,[x y],zeros(numel(x),1),model.parameters,options);
  model.parameters=fitted.parameters;model.equation_model=fitted.model;
  summary=struct('schema','gxtxt.implicit_fit_summary.v1','numeric_api','NUMERIC_API_v1','operation','implicit_fit',...
    'declaration_sha256',model.declaration_sha256,'residual_mode',model.residual_mode,...
    'residual_unit',model.residual_unit,'objective_unit_rule',model.objective_unit_rule,...
    'normalization',model.normalization,'fit_geometry','implicit_algebraic',...
    'residual_definition',model.residual_definition,'measurement_error_distance',false,...
    'observation_count',numel(x),'parameter_ids',{model.parameter_ids},'parameter_units',{model.parameter_units},...
    'predictor_ids',{model.predictor_ids},'predictor_units',{model.predictor_units},...
    'equation_source_sha256',fitted.model.source_sha256,'equation_binding_sha256',fitted.model.binding_sha256,...
    'response_branch','not_declared','uncertainty_scope','conditional_on_observed_coordinates_and_declared_equation_error',...
    'normalization_is_measurement_sigma',false);
  out=fitted;out.model=model;out.equation_model=fitted.model;out.implicit_summary=summary;
  out.fit_geometry='implicit_algebraic';out.operation='implicit_fit';
  out.equation_values=fitted.predicted;out.equation_residuals=fitted.residuals;
  out.predicted_response_available=false;
endfunction
function out=evaluate_equation(model,x,y,options)
  model=validate_model(model);[x,y]=coordinates(x,y);keys(options,{'jacobian'},'implicit evaluation options');
  out=gxtxt_numeric_v1('nonlinear_evaluate',model.equation_model,[x y],options);
  out.equation_values=out.predicted;out.equation_residuals=-out.predicted;
  out.normalized_equation_residuals=out.equation_residuals/model.normalization.value;
  out.residual_unit=model.residual_unit;out.declaration_sha256=model.declaration_sha256;
  out.measurement_error_distance=false;out.fit_performed=false;
endfunction
function out=query_branch(model,queries,branch)
  model=validate_model(model);queries=finite_vector(queries,'implicit branch queries',64);
  keys(branch,{'response_index','bracket','continuous_branch_declared','independent_domain','extrapolation','x_tolerance','response_tolerance','max_iterations','derivative'},'implicit branch');
  for item={'response_index','bracket','continuous_branch_declared','independent_domain'}
    if(!isfield(branch,item{1})),fail(['Implicit branch requires ' item{1}]);endif
  endfor
  response=branch.response_index;
  if(!isnumeric(response)||!isscalar(response)||!any(response==[1 2])||!isscalar(branch.continuous_branch_declared)||!ismember(branch.continuous_branch_declared,[0 1])||!branch.continuous_branch_declared),fail('Declare one continuous response branch and response_index1 or2');endif
  independent=3-response;bracket=interval(branch.bracket,'response bracket');domain=interval(branch.independent_domain,'independent domain');
  extrapolation='reject';if(isfield(branch,'extrapolation')),extrapolation=branch.extrapolation;endif
  if(!ischar(extrapolation)||!any(strcmp(extrapolation,{'reject','allow'}))),fail('Explicit extrapolation policy must be reject or allow');endif
  outside=queries<domain(1)|queries>domain(2);
  if(any(outside)&&strcmp(extrapolation,'reject')),fail('Implicit query lies outside its declared independent domain');endif
  derivative=true;if(isfield(branch,'derivative')),derivative=branch.derivative;endif
  if(!isscalar(derivative)||!ismember(derivative,[0 1])),fail('Derivative must be boolean');endif
  root_options=struct('domain',bracket);
  for item={'x_tolerance','response_tolerance','max_iterations'}
    if(isfield(branch,item{1})),root_options.(item{1})=branch.(item{1});endif
  endfor
  n=numel(queries);values=NaN(n,1);residuals=values;slopes=values;valid=false(n,1);derivative_valid=valid;iterations=zeros(n,1);evaluations=zeros(n,1);reasons=cell(n,1);
  for k=1:n
    curried=curry(model,response,queries(k));
    try
      found=gxtxt_numeric_v1('model_inverse',curried,0,bracket,root_options);
    catch failure
      reasons{k}=['Equation branch evaluation failed: ' failure.message];iterations(k)=NaN;evaluations(k)=NaN;continue;
    end_try_catch
    values(k)=found.roots;valid(k)=found.valid;residuals(k)=found.residual;
    iterations(k)=found.iterations;evaluations(k)=found.function_evaluations;reasons{k}=found.reasons{1};
    if(valid(k)&&derivative)
      dy=gxtxt_numeric_v1('nonlinear_evaluate',curried,values(k),struct('predictor_derivative',true));
      dx=gxtxt_numeric_v1('nonlinear_evaluate',curry(model,independent,values(k)),queries(k),struct('predictor_derivative',true));
      if(dy.derivative_valid&&dx.derivative_valid&&dy.predictor_derivative!=0)
        slope=-dx.predictor_derivative/dy.predictor_derivative;
        if(isfinite(slope)),slopes(k)=slope;derivative_valid(k)=true;endif
      endif
    endif
  endfor
  points=zeros(n,2);points(:,independent)=queries;points(:,response)=values;
  out=struct('schema','gxtxt.implicit_branch_result.v1','queries',queries,'predicted',values,'points',points,...
    'valid',valid,'equation_values',residuals,'derivative',slopes,'derivative_valid',derivative_valid,...
    'response_index',response,'query_unit',model.predictor_units{independent},'response_unit',model.predictor_units{response},...
    'residual_unit',model.residual_unit,'iterations',iterations,'function_evaluations',evaluations,...
    'reasons',{reasons},'bracket',bracket,'independent_domain',domain,'is_extrapolated',outside,...
    'branch_contract','caller_declares_continuous_branch','uniqueness','not_certified',...
    'declaration_sha256',model.declaration_sha256,'fit_performed',false,'uncertainty_available',false,...
    'derivative_method','implicit_ratio_of_existing_two_sided_automatic_partial_derivatives');
endfunction
function equation=curry(model,variable,fixed_value)
  other=3-variable;source=model.equation_model;
  % Use the already unit-normalized expression; changing a coordinate into a
  % fixed evaluation parameter does not change the scientific model identity.
  equation=struct('kind','expression','expression',{source.expression},...
    'parameter_ids',{{source.parameter_ids{:},source.predictor_ids{other}}},...
    'parameter_units',{{source.parameter_units{:},model.predictor_units{other}}},...
    'parameters',[model.parameters(:);fixed_value],'predictor_ids',{{source.predictor_ids{variable}}});
endfunction
function value=finite_vector(value,label,limit)
  if(!isnumeric(value)||!isreal(value)||!isvector(value)||isempty(value)||numel(value)>limit||any(!isfinite(value(:)))),fail([label ' requires a bounded nonempty finite real vector']);endif
  value=gxtxt_numeric_query_double_v1(value);value=value(:);
endfunction
function value=positive(value,label)
  if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)||value<=0),fail([label ' must be finite and positive']);endif
  value=double(value);
endfunction
function value=interval(value,label)
  value=finite_vector(value,label,2);if(numel(value)!=2||value(1)>=value(2)),fail([label ' must have two increasing finite endpoints']);endif
endfunction
function keys(value,allowed,label)
  if(!isstruct(value)||numel(value)!=1),fail([label ' must be one data struct']);endif
  unknown=setdiff(fieldnames(value),allowed);if(!isempty(unknown)),fail(['Unknown ' label ' field: ' unknown{1}]);endif
endfunction
function fail(message),error('GXTXT:Numeric:Implicit','%s',message);endfunction
