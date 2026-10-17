% Numeric-owned declared-model path. Existing callbacks retain their API.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_declared_fit_v1(model,X,y,initial,opts)
  if(!isstruct(opts)||numel(opts)!=1),error('GXTXT:Numeric:Options','Options must be a scalar struct');endif
  required=field(opts,'required_measurement_input','none');
  if(!ischar(required)||!any(strcmp(required,{'none','sigma','weights','sigma_xy'}))),error('GXTXT:Numeric:Options','Unknown required measurement input');endif
  if(strcmp(required,'sigma_xy'))
    if(!isfield(opts,'sigma_x')||!isfield(opts,'sigma')),error('GXTXT:Numeric:Weights','Saved solver policy requires original sigma_x and sigma inputs from their source or owned resources');endif
  elseif(!strcmp(required,'none')&&!isfield(opts,required)),error('GXTXT:Numeric:Weights','Saved solver policy requires original %s input from its source or owned resource',required);endif
  geometry=field(opts,'fit_geometry','vertical_response');
  if(!ischar(geometry)||rows(geometry)!=1||!any(strcmp(geometry,{'vertical_response','orthogonal_xy'}))),error('GXTXT:Numeric:Geometry','Unknown fit geometry');endif
  odr=strcmp(geometry,'orthogonal_xy');
  if(!odr&&(isfield(opts,'sigma_x')||strcmp(required,'sigma_xy'))),error('GXTXT:Numeric:Geometry','X uncertainties require explicit orthogonal_xy geometry');endif
  mode=field(opts,'multistart_mode','single');
  if(!ischar(mode)||rows(mode)!=1||!any(strcmp(mode,{'single','explicit','uniform'}))),error('GXTXT:Numeric:Multistart','Multistart mode must be single, explicit or uniform text');endif
  predictor_count=1;if(isfield(model,'predictor_ids')),predictor_count=numel(model.predictor_ids);if(ischar(model.predictor_ids)),predictor_count=1;endif;endif
  X=real_array(X,'predictors');if(isvector(X)&&predictor_count==1),X=X(:);endif
  y=real_array(y,'observations');if(isvector(y)&&rows(X)==numel(y)),y=y(:);endif
  initial=real_array(initial,'initial parameters');initial=initial(:);p=numel(initial);
  if(any(!isfinite(initial))||rows(X)!=rows(y)),error('GXTXT:Numeric:Model','Inconsistent rows or nonfinite initial parameters');endif
  [programs,model]=gxtxt_numeric_fit_program_v1(model,columns(X),p);
  regional=isfield(model,'regional_composition');
  if(isfield(model,'composition')||isfield(model,'formula_declaration')||regional)
    constraints=model.parameter_constraints;
    for key={'lower_bounds','upper_bounds','fixed_mask'}
      if(!isfield(opts,key{1})),opts.(key{1})=constraints.(key{1});endif
    endfor
    clb=vector_option(opts,'lower_bounds',p,-Inf);cub=vector_option(opts,'upper_bounds',p,Inf);cfixed=vector_option(opts,'fixed_mask',p,0);
    if(any(clb<constraints.lower_bounds)||any(cub>constraints.upper_bounds)||any(constraints.fixed_mask&!cfixed)|| ...
        any(initial(logical(constraints.fixed_mask))!=constraints.initial_parameters(logical(constraints.fixed_mask))))
      error('GXTXT:Numeric:Bounds','Solver options cannot weaken captured component constraints or change fixed values');
    endif
  endif
  if(!strcmp(mode,'single'))
    out=gxtxt_numeric_multistart_v1(model,X,y,initial,opts);return;
  endif
  if(isfield(model,'kind')&&strcmp(model.kind,'gaussian')&&initial(3)==0),error('GXTXT:Numeric:Model','Gaussian initial width must be nonzero');endif
  if(columns(y)!=numel(programs)),error('GXTXT:Numeric:Model','Response formulas must match observed columns');endif
  solver=field(opts,'solver','ceres');
  if(!any(strcmp(solver,{'auto','ceres'}))),error('GXTXT:Numeric:Solver','Declared expressions require solver ceres or auto');endif
  if(exist('gxtxt_numeric_ceres_native','file')!=3),error('GXTXT:Numeric:Dependency','The compiled Numeric Ceres backend is unavailable for this platform');endif
  if(isfield(opts,'weights')&&isfield(opts,'sigma')),error('GXTXT:Numeric:Weights','Specify weights or sigma, not both');endif
  semantics='unweighted';w=ones(size(y));
  if(odr)
    if(columns(X)!=1||columns(y)!=1||!isfield(opts,'sigma_x')||!isfield(opts,'sigma')||isfield(opts,'weights'))
      error('GXTXT:Numeric:ODR','Orthogonal XY fitting requires one predictor, one response and explicit sigma_x and sigma; response weights are not an XY error model');
    endif
    sx=real_array(opts.sigma_x,'sigma_x');sy=real_array(opts.sigma,'sigma');
    if(!isequal(size(sx),size(X))||!isequal(size(sy),size(y))||any(sx(isfinite(sx))<=0)||any(sy(isfinite(sy))<=0)),error('GXTXT:Numeric:ODR','Both sigma arrays must match their axes and finite sigma must be strictly positive');endif
    semantics='inverse_variance';
  elseif(isfield(opts,'sigma'))
    sig=real_array(opts.sigma,'sigma');
    if(!isequal(size(sig),size(y))||any(sig(:)<=0)||any(!isfinite(sig(:)))),error('GXTXT:Numeric:Weights','Sigma must be positive finite values with the response shape');endif
    w=1./sig.^2;semantics='inverse_variance';
  elseif(isfield(opts,'weights'))
    w=real_array(opts.weights,'weights');semantics=field(opts,'weight_semantics','relative');
    if(!isequal(size(w),size(y))||any(w(:)<0)||!any(strcmp(semantics,{'relative','inverse_variance'}))),error('GXTXT:Numeric:Weights','Invalid weights or semantics');endif
  endif
  if(columns(y)>1)
    if(!strcmp(semantics,'inverse_variance')||!isfield(model,'response_units')||!iscellstr(model.response_units)||numel(model.response_units)!=columns(y))
      error('GXTXT:Numeric:JointWeights','Joint responses require inverse-variance weights/sigma and explicit response_units');
    endif
  endif
  policy=field(opts,'nonfinite','error');
  if(!any(strcmp(policy,{'error','omit'}))),error('GXTXT:Numeric:Nonfinite','Nonfinite policy must be error or omit');endif
  good=all(isfinite(X),2)&all(isfinite(y),2)&all(isfinite(w),2);
  if(odr),good=good&isfinite(sx)&isfinite(sy);endif
  if(any(!good)&&strcmp(policy,'error')),error('GXTXT:Numeric:Nonfinite','Nonfinite observations require explicit omit policy');endif
  selected=true(rows(X),1);
  if(regional)
    region_selection=gxtxt_numeric_fit_regions_v1('selection',model,X);
    selected=region_selection.selected_mask;
  endif
  source_rows=find(good&all(w>0,2)&selected);dropped=find(!good|!all(w>0,2)|!selected);
  if(isempty(source_rows)),error('GXTXT:Numeric:Weights','No positive-weight observation rows remain');endif
  if(numel(source_rows)!=rows(X))
    X=X(source_rows,:);y=y(source_rows,:);w=w(source_rows,:);
    if(odr),sx=sx(source_rows);sy=sy(source_rows);endif
  endif
  % This internal flag is derived from the validated model, never caller options.
  opts.positive_predictor_domain=(isfield(model,'kind')&&strcmp(model.kind,'power_law'))|| ...
    (isfield(model,'composition')&&strcmp(model.input_constraints.domain,'positive_real'));
  if(opts.positive_predictor_domain&&any(X(:)<=0)),error('GXTXT:Numeric:Model','Model requires strictly positive retained predictor values');endif
  lb=vector_option(opts,'lower_bounds',p,-Inf);ub=vector_option(opts,'upper_bounds',p,Inf);
  fixed=vector_option(opts,'fixed_mask',p,0);
  if(any(!ismember(fixed,[0,1]))||any(isnan(lb))||any(isnan(ub))||any(lb>ub)||any(initial<lb)||any(initial>ub))
    error('GXTXT:Numeric:Bounds','Invalid bounds, fixed mask or initial parameters');
  endif
  fixed=logical(fixed)|(lb==ub);
  if(numel(y)<sum(!fixed)),error('GXTXT:Numeric:Observations','Fewer residual components than free parameters');endif
  opts.fixed_mask=double(fixed);opts.lower_bounds=lb;opts.upper_bounds=ub;
  if(!isfield(opts,'parameter_scales')),opts.parameter_scales=abs(initial);opts.parameter_scales(opts.parameter_scales==0)=1;endif
  tolerance=field(opts,'tolerance',1e-12);
  if(!isfield(opts,'function_tolerance')),opts.function_tolerance=tolerance;endif
  if(!isfield(opts,'gradient_tolerance')),opts.gradient_tolerance=tolerance;endif
  if(!isfield(opts,'parameter_tolerance')),opts.parameter_tolerance=tolerance;endif
  if(!isfield(opts,'max_iterations')),opts.max_iterations=400;endif
  if(!isfield(opts,'max_seconds')),opts.max_seconds=3600;endif
  if(!isfield(opts,'strategy')),opts.strategy='levenberg_marquardt';endif
  if(!isfield(opts,'loss')),opts.loss='linear';endif
  if(!isfield(opts,'loss_scale')),opts.loss_scale=1;endif
  if(odr)
    native=gxtxt_numeric_ceres_native('fit_odr',programs,X,y,[sx,sy],initial,opts);
  else
    native=gxtxt_numeric_ceres_native('fit',programs,X,y,sqrt(w),initial,opts);
  endif
  q=native.parameters;
  active=!fixed&((isfinite(lb)&abs(q-lb)<=32*eps.*max(abs(lb),abs(q)))|(isfinite(ub)&abs(q-ub)<=32*eps.*max(abs(ub),abs(q))));
  diagnostic_opts=struct('weight_semantics',semantics,'fixed_mask',fixed,'active_bounds',active,'loss',opts.loss,'multiple_responses',columns(y)>1);
  if(odr),diagnostic_opts.normalized_coordinate_corrections=native.normalized_corrections;endif
  if(!odr&&columns(y)==1),diagnostic_opts.predictor_values=X;endif
  out=gxtxt_numeric_fit_diagnostics_v1(q,y,native.predicted,native.jacobian,w,diagnostic_opts);
  names=fieldnames(native);for k=1:numel(names),if(!any(strcmp(names{k},{'parameters','predicted','jacobian'}))),out.(names{k})=native.(names{k});endif;endfor
  out.predicted=native.predicted;
  if(odr)
    % These are unsigned normalized XY distances. Physical, signed coordinate
    % corrections remain in their explicitly named N-by-2 numerical fields.
    out.residuals=hypot(native.normalized_corrections(:,1),native.normalized_corrections(:,2));
    out.weighted_residuals=out.residuals;
  else
    out.residuals=y-native.predicted;out.weighted_residuals=sqrt(w).*out.residuals;
  endif
  out.fit_geometry=geometry;
  out.exitflag=double(native.converged);out.model=model;out.model.initial_parameters=initial;
  out.model.parameters=q;
  % Model replay needs bounded effective solver policy, never copies of the
  % observations, sigma/weights or Dataset selection arrays. Those inputs remain
  % with the caller's source/owned resources and the returned original-row maps.
  saved_policy=struct();
  for key={'solver','strategy','max_iterations','max_seconds','function_tolerance','gradient_tolerance','parameter_tolerance','tolerance','loss','loss_scale','lower_bounds','upper_bounds','fixed_mask','parameter_scales','threads','nonfinite','weight_semantics','fit_geometry'}
    if(isfield(opts,key{1})),saved_policy.(key{1})=opts.(key{1});endif
  endfor
  out.model.solver_options=saved_policy;out.model.schema_version=1;
  required='none';if(odr),required='sigma_xy';elseif(isfield(opts,'sigma')),required='sigma';elseif(isfield(opts,'weights')),required='weights';endif
  out.model.solver_options.required_measurement_input=required;
  out.model.input_contract=struct('schema','gxtxt.numeric_fit_input_contract.v1', ...
    'original_row_count',numel(good),'retained_row_count',rows(y),'predictor_count',columns(X),'response_count',columns(y), ...
    'weight_semantics',semantics,'measurement_input',required,'fit_geometry',geometry,'nonfinite_policy',policy,'input_values_owner','caller_source_or_owned_resources');
  out.active_bounds=active;out.observation_rows=rows(y);out.response_count=columns(y);
  % Bounded optimization receipt. Observation arrays remain with their owned
  % input resources; this is policy/termination evidence, not another estimate.
  receipt=struct('schema','gxtxt.numeric_solver_receipt.v1','method','ceres', ...
    'requested_solver',solver,'initial_parameters',initial,'lower_bounds',lb, ...
    'upper_bounds',ub,'fixed_mask',double(fixed));
  for key={'backend_version','derivative_method','termination','solver_message','converged', ...
      'iterations','function_evaluations','jacobian_evaluations','solver_seconds','solver_objective', ...
      'threads_used','parameter_scales'}
    receipt.(key{1})=native.(key{1});
  endfor
  for key={'function_tolerance','gradient_tolerance','parameter_tolerance','max_iterations', ...
      'max_seconds','strategy','loss','loss_scale'}
    receipt.(key{1})=opts.(key{1});
  endfor
  receipt.linear_solver='dense_qr';receipt.jacobi_scaling=true;
  if(odr)
    receipt.linear_solver=native.linear_solver;
    receipt.orthogonal_xy=struct('schema','gxtxt.numeric_orthogonal_xy_receipt.v1', ...
      'nuisance_parameter_count',native.nuisance_parameter_count,'residual_component_count',2*rows(y), ...
      'jacobian_convention',native.jacobian_convention,'sigma_semantics','independent_absolute_axis_standard_uncertainties');
  endif
  receipt.iteration_convention='ceres_iteration_records_including_initial_state';
  out.solver_receipt=receipt;
  out.source_row_positions=source_rows;out.dropped_row_positions=dropped;
  inference_x=X;if(odr),inference_x=native.adjusted_x;endif
  regularity=gxtxt_numeric_fit_regularity_v1(model,q,fixed,inference_x);
  if(!isempty(fieldnames(regularity))),out.regional_fit=regularity;endif
  if(regional)
    final_selection=gxtxt_numeric_fit_regions_v1('selection',out.model,X);
    % Bounded facts travel with every scientific consumer; row arrays retain
    % their public binary transport and original positional index contract.
    out.region_indices=final_selection.region_indices;
    out.regional_fit.original_row_count=numel(selected);out.regional_fit.window_selected_count=sum(selected);
    out.regional_fit.retained_row_count=rows(X);out.regional_fit.region_counts=final_selection.region_counts;
    out.regional_fit.boundary_ownership='right_region';out.regional_fit.fit_windows=final_selection.fit_windows;
  endif
  out.jacobian_layout='column-major response components by physical parameters';
  if(odr),out.jacobian_layout='column-major projected normalized XY tangent by physical parameters';endif
  if(columns(y)>1),out.residual_rmse=NaN;out.response_variance=NaN;endif
endfunction
function value=field(s,key,fallback),if(isfield(s,key)),value=s.(key);else value=fallback;endif;endfunction
function value=real_array(value,name)
  if(!isnumeric(value)||!isreal(value)||ndims(value)!=2||isempty(value)),error('GXTXT:Numeric:Type','%s requires a nonempty real numeric array',name);endif
  value=double(value);
endfunction
function value=vector_option(opts,key,n,fallback)
  value=field(opts,key,repmat(fallback,n,1));value=value(:);
  if(!isnumeric(value)&&!islogical(value)||!isreal(value)||numel(value)!=n),error('GXTXT:Numeric:Options','Invalid %s vector',key);endif
  value=double(value);
endfunction
