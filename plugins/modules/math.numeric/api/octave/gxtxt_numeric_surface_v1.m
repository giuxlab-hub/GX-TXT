% Physical two-predictor response models use the existing formula/Ceres owners.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_surface_v1(action,varargin)
  switch(action)
    case 'compose',out=compose(varargin{1});
    case 'validate',out=validate(varargin{1});
    case 'fit',out=fit_surface(varargin{:});
    case 'evaluate',out=evaluate(varargin{:});
    case 'grid',out=grid_surface(varargin{:});
    case 'residuals',out=residuals(varargin{:});
    case 'state',out=state_model(varargin{1});
    case 'restore',out=restore_model(varargin{1});
    otherwise,fail('Unknown surface action');
  endswitch
endfunction
function model=compose(recipe)
  formula=gxtxt_numeric_v1('fit_formula_compose',recipe);
  if(!isequal(formula.predictor_ids,{'x','y'})||numel(formula.parameter_ids)>32||numel(formula.response_units)!=1),fail('A surface requires physical predictors x,y, one response and1..32 parameters');endif
  unit=gxtxt_unit_parse(recipe.response_unit);
  if(!strcmp(unit.kind,'linear')),fail('Surface response requires explicit linear physical units');endif
  model=struct('schema','gxtxt.surface_model.v1','kind','surface','recipe',recipe,...
    'formula_model',formula,'predictor_ids',{formula.predictor_ids},...
    'predictor_units',{reshape(recipe.predictor_units,1,[])},'response_unit',recipe.response_unit,...
    'parameter_ids',{formula.parameter_ids},'parameter_units',{formula.parameter_units},...
    'parameters',formula.initial_parameters,'initial_parameters',formula.initial_parameters,...
    'source_sha256',formula.source_sha256,'binding_sha256',formula.binding_sha256,...
    'declaration_sha256',hash('sha256',jsonencode(formula.formula_declaration)),...
    'fit_geometry','vertical_response_z_at_exact_xy','interpolation_performed',false);
endfunction
function model=validate(model)
  if(!isstruct(model)||!isscalar(model)||!isfield(model,'schema')||!strcmp(model.schema,'gxtxt.surface_model.v1')||!isfield(model,'recipe')),fail('A versioned surface declaration is required');endif
  expected=compose(model.recipe);
  for key={'schema','kind','predictor_ids','predictor_units','response_unit','parameter_ids','parameter_units','initial_parameters','declaration_sha256','fit_geometry','interpolation_performed','source_sha256','binding_sha256'}
    field=key{1};if(!isfield(model,field)||!isequaln(model.(field),expected.(field))),fail(['Surface declaration changed: ' field]);endif
  endfor
  formula=gxtxt_numeric_fit_formula_v1('validate',model.formula_model);
  for key={'expression','parameter_ids','parameter_units','predictor_ids','response_units','parameter_constraints','input_constraints','source_sha256','binding_sha256'}
    field=key{1};if(!isequaln(formula.(field),expected.formula_model.(field))),fail(['Surface formula identity differs: ' field]);endif
  endfor
  if(!isequaln(formula.parameters(:),model.parameters(:))),fail('Surface formula and physical parameter state differ');endif
  % The formula owner already validates its dimensional receipt, including the
  % Bridge representation of an empty inferred-unit list. Keep that normalized
  % declaration rather than comparing its incidental list encoding a second time.
  formula.formula_declaration=expected.formula_model.formula_declaration;model.formula_model=formula;
  model.parameters=real_values(model.parameters,'surface parameters');model.parameters=model.parameters(:);
  if(any(!isfinite(model.parameters))),fail('Surface parameters must be finite');endif
  if(isfield(model,'observation_domain'))
    domain=model.observation_domain;keys(domain,{'bounds','meaning'},'observation domain');bounds(domain.bounds);
    if(!strcmp(domain.meaning,'axis_bounds_not_observation_coverage')),fail('Surface bounds cannot imply interior observation coverage');endif
  endif
endfunction
function a=real_values(a,label)
  if(!isnumeric(a)||!isreal(a)||isempty(a)||ndims(a)>2),fail([label ' must be a nonempty real numeric vector/matrix']);endif
  if((isa(a,'uint64')&&any(a(:)>uint64(flintmax)))||(isa(a,'int64')&&any(a(:)>int64(flintmax)|a(:)<-int64(flintmax)))),fail([label ' contains integers outside exact binary64 range']);endif
  a=double(a);
endfunction
function state=state_model(model)
  model=validate(model);
  if(!isfield(model,'observation_domain')),fail('Retained surface state requires its captured observation bounds');endif
  state=struct('schema','gxtxt.surface_state.v1','recipe',model.recipe,'parameters',model.parameters,...
    'observation_domain',model.observation_domain,'declaration_sha256',model.declaration_sha256,...
    'source_sha256',model.source_sha256,'binding_sha256',model.binding_sha256);
endfunction
function model=restore_model(state)
  fields={'schema','recipe','parameters','observation_domain','declaration_sha256','source_sha256','binding_sha256'};
  keys(state,fields,'retained surface state');
  if(!all(isfield(state,fields))||!strcmp(state.schema,'gxtxt.surface_state.v1')),fail('A complete versioned surface state is required');endif
  model=compose(state.recipe);
  for key={'declaration_sha256','source_sha256','binding_sha256'}
    if(!strcmp(state.(key{1}),model.(key{1}))),fail('Retained surface declaration or formula identity changed');endif
  endfor
  model.parameters=real_values(state.parameters,'retained physical parameters');model.parameters=model.parameters(:);
  model.formula_model.parameters=model.parameters;model.observation_domain=state.observation_domain;
  model=validate(model);
endfunction
function [xy,z,receipt,keep]=observations(x,y,z,options)
  x=real_values(x,'surface X');y=real_values(y,'surface Y');z=real_values(z,'surface Z');
  if(numel(x)>65536||numel(y)>65536||numel(z)>65536),fail('Surface observations are bounded to65536 original values before grid expansion');endif
  layout=required(options,'layout');policy=opt(options,'nonfinite','error');
  if(!ischar(policy)||!any(strcmp(policy,{'error','omit'}))),fail('Choose explicit nonfinite=error or omit');endif
  if(strcmp(layout,'points'))
    if(!isvector(x)||!isvector(y)||!isvector(z)||numel(x)!=numel(z)||numel(y)!=numel(z)),fail('Point observations require three matched vectors');endif
    original_shape=[numel(z),1];xy=[x(:),y(:)];z=z(:);
  elseif(strcmp(layout,'grid_yx'))
    if(!isvector(x)||!isvector(y)||!isequal(size(z),[numel(y),numel(x)])||any(!isfinite(x(:)))||any(!isfinite(y(:)))||numel(unique(x))!=numel(x)||numel(unique(y))!=numel(y)),fail('grid_yx requires unique finite axis vectors and a matching Y-by-X response matrix');endif
    original_shape=size(z);[X,Y]=meshgrid(x(:).',y(:));xy=[X(:),Y(:)];z=z(:);
  else,fail('Declare layout=points or grid_yx; no implicit gridding is performed');endif
  n=numel(z);if(n<1||n>65536),fail('Surface observations are bounded to1..65536 original values');endif
  keep=all(isfinite(xy),2)&isfinite(z);nonfinite=sum(!keep);
  if(nonfinite&&strcmp(policy,'error')),fail('Nonfinite surface observations require explicit omission; no values are interpolated or fabricated');endif
  receipt=struct('schema','gxtxt.surface_observations.v1','layout',layout,'original_shape',original_shape,...
    'original_count',n,'retained_count',sum(keep),'nonfinite_count',nonfinite,'nonfinite_policy',policy,...
    'source_linear_index_base',0,'source_linear_order','column_major','duplicate_policy','preserve_observations',...
    'sorting_performed',false,'interpolation_performed',false,'original_xy_sha256',digest(xy),'original_z_sha256',digest(z));
  xy=xy(keep,:);z=z(keep);
endfunction
function out=fit_surface(model,x,y,z,options)
  model=validate(model);
  keys(options,{'layout','nonfinite','sigma','weights','solver','strategy','max_iterations','max_seconds','function_tolerance','gradient_tolerance','parameter_tolerance','tolerance','parameter_scales','threads'},'surface fit options');
  [xy,z,input,keep]=observations(x,y,z,options);n=rows(xy);
  if(n<2),fail('Surface fitting requires at least two finite observations');endif
  solver=rmfield(options,intersect(fieldnames(options),{'layout','nonfinite'}));
  if(isfield(solver,'sigma')&&isfield(solver,'weights')),fail('Choose response sigma or relative precision, not both');endif
  for key={'sigma','weights'}
    name=key{1};if(!isfield(solver,name)),continue;endif
    value=real_values(solver.(name),['surface ' name]);
    if(numel(value)!=input.original_count||(!isvector(value)&&!isequal(size(value),input.original_shape))),fail('Response uncertainty must match every original observation');endif
    value=value(:);if(any(!isfinite(value(keep)))||any(value(keep)<=0)),fail('Retained response uncertainty must be positive finite; zero weights do not silently remove rows');endif
    solver.(name)=value(keep);
  endfor
  if(!isfield(solver,'max_iterations')),solver.max_iterations=400;endif
  if(!isfield(solver,'max_seconds')),solver.max_seconds=30;endif
  for key={'lower_bounds','upper_bounds','fixed_mask'},solver.(key{1})=model.formula_model.parameter_constraints.(key{1});endfor
  solver.nonfinite='error';solver.loss='linear';
  fit=gxtxt_numeric_v1('nonlinear_fit',model.formula_model,xy,z,model.parameters,solver);
  model.parameters=fit.parameters;model.formula_model=fit.model;
  model.observation_domain=struct('bounds',[min(xy(:,1)),max(xy(:,1));min(xy(:,2)),max(xy(:,2))],'meaning','axis_bounds_not_observation_coverage');
  out=fit;out.operation='surface_fit';out.solver_model=fit.model;out.model=model;
  out.fit_geometry=model.fit_geometry;
  out.source_linear_indices=uint64(find(keep)-1);out.observed_coordinates=xy;out.observed_response=z;
  out.surface_summary=summary(model,input,xy,z,out.source_linear_indices,'surface_fit');
endfunction
function out=summary(model,input,xy,z,indices,operation)
  schema='gxtxt.surface_fit_summary.v1';scope='local_conditional_on_exact_predictors_formula_and_response_noise';
  if(strcmp(operation,'surface_residuals')),schema='gxtxt.surface_residual_summary.v1';scope='descriptive_evaluation_at_captured_parameters_no_parameter_inference';endif
  out=struct('schema',schema,'numeric_api','NUMERIC_API_v1','operation',operation,'declaration_sha256',model.declaration_sha256,...
    'formula_source_sha256',model.formula_model.source_sha256,'formula_binding_sha256',model.formula_model.binding_sha256,...
    'predictor_ids',{model.predictor_ids},'predictor_units',{model.predictor_units},'response_id','z','response_unit',model.response_unit,...
    'parameter_ids',{model.parameter_ids},'parameter_units',{model.parameter_units},'observation_receipt',input,...
    'retained_xy_sha256',digest(xy),'retained_z_sha256',digest(z),'source_indices_sha256',digest(indices),...
    'observation_domain',model.observation_domain,'fit_geometry',model.fit_geometry,...
    'predictor_error_model','exact_predictors','interpolation_performed',false,...
    'uncertainty_scope',scope);
endfunction
function out=residuals(model,x,y,z,options)
  model=validate(model);
  keys(options,{'layout','nonfinite','extrapolation'},'surface residual options');
  [xy,z,input,keep]=observations(x,y,z,options);
  if(isempty(z)),fail('Surface evaluation requires at least one retained observation');endif
  evaluated=evaluate(model,xy,struct('extrapolation',opt(options,'extrapolation','error')));
  out=gxtxt_numeric_v1('residual_metrics',z,evaluated.predicted);
  out.operation='surface_residuals';out.model=model;out.parameters=model.parameters;
  out.predicted=evaluated.predicted;out.residuals=z-evaluated.predicted;
  out.source_linear_indices=uint64(find(keep)-1);out.observed_coordinates=xy;out.observed_response=z;
  out.is_extrapolated=evaluated.is_extrapolated;out.fit_performed=false;out.fit_geometry=model.fit_geometry;
  out.weight_semantics='unweighted';out.loss='linear';
  out.surface_summary=summary(model,input,xy,z,out.source_linear_indices,'surface_residuals');
endfunction
function d=bounds(d)
  d=real_values(d,'surface domain');
  if(!isequal(size(d),[2,2])||any(!isfinite(d(:)))||any(d(:,2)<d(:,1))),fail('Surface domain is a finite2-by-2 matrix [xmin xmax; ymin ymax]');endif
endfunction
function out=evaluate(model,xy,options)
  model=validate(model);xy=real_values(xy,'surface query points');
  if(columns(xy)!=2||rows(xy)>65536||any(!isfinite(xy(:)))),fail('Surface query requires1..65536 finite physical X/Y rows');endif
  keys(options,{'domain','extrapolation','jacobian'},'surface query options');
  if(isfield(options,'domain')),d=bounds(options.domain);elseif(isfield(model,'observation_domain')),d=bounds(model.observation_domain.bounds);else,fail('An unfitted surface query needs an explicit physical domain');endif
  policy=opt(options,'extrapolation','error');if(!ischar(policy)||!any(strcmp(policy,{'error','allow'}))),fail('Surface extrapolation must be error or explicit allow');endif
  outside=any(xy<d(:,1).'|xy>d(:,2).',2);
  if(any(outside)&&strcmp(policy,'error')),fail('Surface query lies outside its explicit coordinate bounds');endif
  evaluated=gxtxt_numeric_v1('nonlinear_evaluate',model.formula_model,xy,struct('jacobian',opt(options,'jacobian',false)));
  out=evaluated;out.coordinates=xy;out.points=[xy,evaluated.predicted];out.is_extrapolated=outside;
  out.coordinate_units={model.predictor_units{1},model.predictor_units{2},model.response_unit};
  out.domain=d;out.domain_meaning='axis_bounds_not_observation_coverage';out.fit_performed=false;out.interpolation_performed=false;
  out.declaration_sha256=model.declaration_sha256;
endfunction
function out=grid_surface(model,x,y,options)
  x=real_values(x,'surface query X axis');y=real_values(y,'surface query Y axis');
  if(!isvector(x)||!isvector(y)||any(!isfinite(x(:)))||any(!isfinite(y(:)))||any(diff(x(:))<=0)||any(diff(y(:))<=0)||numel(x)*numel(y)>65536),fail('Surface query axes must be finite strictly increasing vectors with at most65536 cells');endif
  [X,Y]=meshgrid(x(:).',y(:));out=evaluate(model,[X(:),Y(:)],options);
  out.x=x(:);out.y=y(:);out.z=reshape(out.predicted,numel(y),numel(x));out.shape=[numel(y),numel(x)];
  out.layout='grid_yx';out.is_extrapolated=reshape(out.is_extrapolated,out.shape);
  out.representation='sampled_declared_surface_model';
endfunction
function value=required(s,key),if(!isfield(s,key)),fail(['Explicit ' key ' is required']);endif;value=s.(key);endfunction
function value=opt(s,key,fallback),value=fallback;if(isfield(s,key)),value=s.(key);endif;endfunction
function keys(s,allowed,label),if(!isstruct(s)||!isscalar(s)||!isempty(setdiff(fieldnames(s),allowed))),fail(['Unknown field or invalid ' label]);endif;endfunction
function value=digest(a),bytes=typecast(double(a(:)),'uint8');value=hash('sha256',[jsonencode(size(a)) ':' char(bytes(:).')]);endfunction
function fail(message),error('GXTXT:Numeric:Surface',message);endfunction
