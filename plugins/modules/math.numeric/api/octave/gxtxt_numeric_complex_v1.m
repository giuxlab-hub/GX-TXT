% Physical complex responses share the existing real multi-response solver.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_complex_v1(action,varargin)
  here=fileparts(mfilename('fullpath'));addpath(fullfile(here,'..','..','..','..','..','core','octave','units'));
  switch(action)
    case 'compose',out=compose(varargin{1});
    case 'validate',out=validate(varargin{1});
    case 'fit',out=fit_complex(varargin{:});
    case 'residuals',out=residuals_complex(varargin{:});
    case 'evaluate',out=evaluate(varargin{:});
    case 'from_polar',out=from_polar(varargin{:});
    otherwise,fail('Unknown complex response action');
  endswitch
endfunction
function model=compose(recipe)
  keys(recipe,{'predictor_id','predictor_unit','channels','parameters'},'complex recipe');
  for field={'predictor_id','predictor_unit','channels','parameters'}
    if(!isfield(recipe,field{1})),fail(['Missing complex recipe ' field{1}]);endif
  endfor
  channels=recipe.channels;if(isstruct(channels)),channels=num2cell(channels);endif
  if(!iscell(channels)||isempty(channels)||numel(channels)>3),fail('Declare1..3 complex channels with shared physical parameters');endif
  identity(recipe.predictor_id);frequency_unit=gxtxt_unit_parse(recipe.predictor_unit);hz=gxtxt_unit_parse('Hz');
  if(!strcmp(frequency_unit.kind,'linear')||!isequal(frequency_unit.dims,hz.dims)),fail('Complex predictor requires a physical frequency unit');endif
  ids={};units={};expressions={};component_ids={};component_units={};
  for k=1:numel(channels)
    channel=channels{k};keys(channel,{'id','unit','real_expression','imaginary_expression'},'complex channel');
    for field={'id','unit','real_expression','imaginary_expression'},if(!isfield(channel,field{1})),fail('Incomplete complex channel');endif;endfor
    identity(channel.id);ids{end+1}=channel.id;units{end+1}=channel.unit;
    if(numel(unique(ids))!=numel(ids)),fail('Complex channel identities must be unique');endif
    expressions=[expressions,{channel.real_expression,channel.imaginary_expression}];
    component_ids=[component_ids,{[channel.id '_real'],[channel.id '_imaginary']}];component_units=[component_units,{channel.unit,channel.unit}];
  endfor
  formula=struct('expression',{expressions},'response_unit',{component_units},'predictor_ids',{{recipe.predictor_id}},'predictor_units',{{recipe.predictor_unit}},'parameters',{recipe.parameters});
  physical=gxtxt_numeric_v1('fit_formula_compose',formula);
  if(numel(physical.parameter_ids)>32),fail('Complex response models accept1..32 shared parameters');endif
  for k=1:numel(physical.parameter_ids),identity(physical.parameter_ids{k});endfor
  model=struct('schema','gxtxt.complex_model.v1','kind','complex_response','recipe',recipe,...
    'physical_model',physical,'parameters',physical.parameters,'parameter_ids',{physical.parameter_ids},'parameter_units',{physical.parameter_units},...
    'channel_ids',{ids},'channel_units',{units},'component_ids',{component_ids},'component_units',{component_units},...
    'predictor_id',recipe.predictor_id,'predictor_unit',recipe.predictor_unit,'component_order','channel_interleaved_real_imaginary',...
    'declaration_sha256',hash('sha256',jsonencode(physical.formula_declaration)));
endfunction
function model=validate(model)
  if(!isstruct(model)||!isscalar(model)||!isfield(model,'recipe')),fail('A frozen complex declaration is required');endif
  expected=compose(model.recipe);
  for field={'schema','kind','parameter_ids','parameter_units','channel_ids','channel_units','component_ids','component_units','predictor_id','predictor_unit','component_order','declaration_sha256'}
    key=field{1};if(!isfield(model,key)||!same_identity(model.(key),expected.(key))),fail(['Complex declaration changed: ' key]);endif
  endfor
  physical=model.physical_model;
  for field=reshape(fieldnames(expected.physical_model),1,[])
    key=field{1};if(strcmp(key,'parameters')),continue;endif
    if(!isfield(physical,key)||!same_identity(physical.(key),expected.physical_model.(key))),fail(['Complex physical declaration changed: ' key]);endif
  endfor
  if(!isequaln(physical.parameters(:),model.parameters(:))),fail('Complex physical parameters differ from the declaration');endif
  % JSON and managed typed lists have no row/column distinction for identity
  % vectors. After exact ordered comparison, rebuild through the same formula
  % owner and let it enforce the physical bounds/fixed values.
  expected.physical_model.parameters=model.parameters(:);
  model.physical_model=gxtxt_numeric_fit_formula_v1('validate',expected.physical_model);
  model.parameters=model.parameters(:);
endfunction
function x=predictors(x)
  if(!isfloat(x)||!isreal(x)||!isvector(x)||isempty(x)||numel(x)>65536||any(!isfinite(x(:)))||any(x(:)<=0)),fail('Complex frequency predictors require1..65536 positive finite physical values');endif
  x=double(x(:));
endfunction
function [components,z]=observations(z,n,k)
  if(!isfloat(z)||ndims(z)!=2||!isequal(size(z),[n,k])||any(!isfinite(z(:)))),fail('Complex observations must be a finite N-by-channel float matrix');endif
  z=double(z);components=zeros(n,2*k);components(:,1:2:end)=real(z);components(:,2:2:end)=imag(z);
endfunction
function out=evaluate(model,x,options)
  model=validate(model);x=predictors(x);keys(options,{'jacobian','predictor_derivative'},'complex evaluation options');
  numeric=gxtxt_numeric_v1('nonlinear_evaluate',model.physical_model,x,options);
  values=numeric.predicted(:,1:2:end)+1i*numeric.predicted(:,2:2:end);
  out=numeric;out.predicted=values;out.component_values=numeric.predicted;
  out.magnitude=abs(values);out.phase_radians=angle(values);out.phase_valid=abs(values)>0;
  out.phase_radians(!out.phase_valid)=NaN;out.phase_policy='principal_phase_radians_zero_magnitude_unavailable';
  out.component_order=model.component_order;out.channel_units=model.channel_units;out.fit_performed=false;
  out.declaration_sha256=model.declaration_sha256;
endfunction
function out=fit_complex(model,x,z,measurement,options)
  model=validate(model);x=predictors(x);n=numel(x);k=numel(model.channel_ids);m=2*k;
  if(n<2),fail('Complex fitting requires at least two observed frequency rows');endif
  [values,z]=observations(z,n,k);
  [X,target,transformed,receipt]=normalized_problem(model,x,values,measurement);
  keys(options,{'solver','strategy','max_iterations','max_seconds','function_tolerance','gradient_tolerance','parameter_tolerance','tolerance','parameter_scales','threads'},'complex solver options');
  if(!isfield(options,'max_iterations')),options.max_iterations=400;endif
  if(!isfield(options,'max_seconds')),options.max_seconds=30;endif
  % Bounds/fixed values have one authority: the physical declaration. Solver
  % options cannot weaken them or create a different statistical model.
  for field={'lower_bounds','upper_bounds','fixed_mask'},options.(field{1})=model.physical_model.parameter_constraints.(field{1});endfor
  options.nonfinite='error';options.loss='linear';options.sigma=ones(n,m);
  fitted=gxtxt_numeric_v1('nonlinear_fit',transformed,X,target,model.parameters,options);
  model.parameters=fitted.parameters;model.physical_model.parameters=fitted.parameters;
  physical=evaluate(model,x,struct());
  summary=complex_summary('complex_fit',model,x,values,measurement,receipt,fitted.model);
  out=fitted;out.model=model;out.solver_model=fitted.model;out.operation='complex_fit';out.complex_summary=summary;
  out.whitened_predicted=fitted.predicted;out.whitened_residuals=fitted.residuals;
  out=physical_residuals(out,physical,z);
endfunction
function out=residuals_complex(model,x,z,measurement)
  model=validate(model);x=predictors(x);[values,z]=observations(z,numel(x),numel(model.channel_ids));
  [X,target,transformed,receipt]=normalized_problem(model,x,values,measurement);
  transformed.parameters=model.parameters;
  normalized=gxtxt_numeric_v1('nonlinear_evaluate',transformed,X,struct());
  metrics=gxtxt_numeric_v1('residual_metrics',target(:),normalized.predicted(:),struct());
  % These are evaluation diagnostics for captured parameters. In particular,
  % no training DOF, parameter covariance or pooled physical-unit RMSE exists.
  out=struct('operation','complex_residuals','model',model,'parameters',model.parameters,...
    'p',numel(model.parameters),'n',metrics.n,'sse',metrics.sse,'rmse',metrics.rmse,...
    'mae',metrics.mae,'max_abs_error',metrics.max_abs_error,...
    'weight_semantics','inverse_variance','covariance_scale',1,'fit_performed',false,...
    'complex_summary',complex_summary('complex_residuals',model,x,values,measurement,receipt,transformed),...
    'whitened_predicted',normalized.predicted,'whitened_residuals',target-normalized.predicted);
  out=physical_residuals(out,evaluate(model,x,struct()),z);
endfunction
function out=physical_residuals(out,physical,z)
  phase=angle(z.*conj(physical.predicted));valid=abs(z)>0&abs(physical.predicted)>0;phase(!valid)=NaN;
  out.predicted=physical.predicted;out.residuals=z-physical.predicted;out.component_predicted=physical.component_values;
  out.wrapped_phase_residual=phase;out.phase_residual_valid=valid;out.magnitude_predicted=physical.magnitude;
endfunction
function [X,target,transformed,receipt]=normalized_problem(model,x,values,measurement)
  n=numel(x);m=columns(values);
  keys(measurement,{'covariance','layout','component_units','semantics'},'complex covariance');
  for field={'covariance','layout','component_units','semantics'},if(!isfield(measurement,field{1})),fail('Explicit Cartesian component covariance is required');endif;endfor
  if(!strcmp(measurement.semantics,'absolute')||!isequal(reshape(measurement.component_units,1,[]),model.component_units)),fail('Covariance requires absolute physical component units in the declared real/imaginary order');endif
  [W,receipt]=whitening(measurement.covariance,measurement.layout,n,m);
  % Each physical expression is already dimensionally compiled into its
  % declared component unit. W maps those numeric component values to
  % dimensionless innovations; compile this internal linear map at the same VM.
  transformed=struct('kind','expression','predictor_ids',{{model.predictor_id}},...
    'expression',{cell(1,m)},'response_units',{repmat({'1'},1,m)},...
    'parameter_ids',{model.parameter_ids},'parameter_units',{model.parameter_units});
  X=x;target=zeros(n,m);column=0;
  for i=1:m
    terms={};
    for j=1:i
      column+=1;name=sprintf('gxtxt_whiten_%d_%d',i,j);
      transformed.predictor_ids{end+1}=name;
      coefficient=reshape(W(i,j,:),n,1);X(:,end+1)=coefficient;
      terms{end+1}=['(' name ')*(' model.physical_model.expression{j} ')'];
      target(:,i)+=coefficient.*values(:,j);
    endfor
    transformed.expression{i}=strjoin(terms,'+');
  endfor
  [unused,transformed]=gxtxt_numeric_fit_program_v1(transformed,columns(X),numel(model.parameters));
endfunction
function summary=complex_summary(operation,model,x,values,measurement,receipt,normalized_model)
  n=numel(x);m=columns(values);
  summary=struct('schema','gxtxt.complex_fit_summary.v1','numeric_api','NUMERIC_API_v1','operation',operation,...
    'declaration_sha256',model.declaration_sha256,'parameter_ids',{model.parameter_ids},'parameter_units',{model.parameter_units},...
    'channel_ids',{model.channel_ids},'channel_units',{model.channel_units},'component_ids',{model.component_ids},'component_units',{model.component_units},...
    'component_order',model.component_order,'predictor_id',model.predictor_id,'predictor_unit',model.predictor_unit,...
    'observation_rows',n,'response_count',m,'residual_component_count',n*m,'covariance_semantics','absolute',...
    'covariance_layout',measurement.layout,'covariance_sha256',receipt.covariance_sha256,'effective_covariance_sha256',receipt.effective_covariance_sha256,...
    'whitening','lower_cholesky_per_observation','independence','independent_observation_rows_correlated_response_components',...
    'objective','cartesian_mahalanobis','phase_policy','wrapped_principal_radians_diagnostic_only_zero_magnitude_unavailable',...
    'physical_predictor_sha256',digest(x),'physical_observation_sha256',digest(values),...
    'normalized_formula_source_sha256',normalized_model.source_sha256,'normalized_formula_binding_sha256',normalized_model.binding_sha256,...
    'regularization','none','uncertainty_scope','local_conditional_on_predictors_model_and_absolute_cartesian_covariance');
  if(strcmp(operation,'complex_residuals'))
    summary.schema='gxtxt.complex_residual_summary.v1';summary.uncertainty_scope='descriptive_evaluation_at_captured_parameters_no_parameter_inference';
  endif
endfunction
function [W,receipt]=whitening(C,layout,n,m)
  if(!isfloat(C)||!isreal(C)||isempty(C)||any(!isfinite(C(:)))),fail('Cartesian covariance must be a finite real floating-point array');endif
  C=double(C);
  if(strcmp(layout,'shared'))
    if(!isequal(size(C),[m,m])),fail('Shared covariance must be M-by-M');endif
    blocks=1;
  elseif(strcmp(layout,'per_observation'))
    if(ndims(C)>3||size(C,1)!=m||size(C,2)!=m||size(C,3)!=n),fail('Per-observation covariance must be M-by-M-by-N');endif
    blocks=n;
  else,fail('Covariance layout must be shared or per_observation');endif
  original=digest(C);W=zeros(m,m,n);effective=C;
  for row=1:blocks
    block=C(:,:,row);scale=max(abs(block(:)));asymmetry=max(abs((block-block.')(:)));
    if(asymmetry>64*eps*m*scale),fail('Cartesian covariance is not symmetric within its roundoff tolerance');endif
    block=block/2+block.'/2;[L,flag]=chol(block,'lower');
    if(flag),fail('Cartesian covariance must be positive definite; no jitter, null-mode dropping or regularization is performed');endif
    factor=L\eye(m);if(any(!isfinite(factor(:)))),fail('Cartesian covariance whitening overflow');endif
    W(:,:,row)=factor;effective(:,:,row)=block;
  endfor
  if(blocks==1),W=repmat(W(:,:,1),1,1,n);endif
  receipt=struct('covariance_sha256',original,'effective_covariance_sha256',digest(effective));
endfunction
function out=from_polar(magnitude,phase,options)
  keys(options,{'phase_unit','magnitude_scale','reference','channel_units'},'polar observation conversion');
  if(!isfloat(magnitude)||!isreal(magnitude)||ndims(magnitude)!=2||isempty(magnitude)||rows(magnitude)>65536||columns(magnitude)>3||any(!isfinite(magnitude(:)))||!isfloat(phase)||!isreal(phase)||!isequal(size(magnitude),size(phase))||any(!isfinite(phase(:)))),fail('Polar observations require matched finite real N-by-channel arrays');endif
  for field={'phase_unit','magnitude_scale','channel_units'},if(!isfield(options,field{1})),fail('Declare phase units, magnitude scale and physical channel units');endif;endfor
  if(!iscellstr(options.channel_units)||numel(options.channel_units)!=columns(magnitude)),fail('Polar units must match channels');endif
  for k=1:numel(options.channel_units)
    unit=gxtxt_unit_parse(options.channel_units{k});if(!strcmp(unit.kind,'linear')||unit.scale<=0),fail('Polar channels require linear physical units');endif
  endfor
  radians=double(phase);
  if(strcmp(options.phase_unit,'deg')),radians*=pi/180;elseif(!strcmp(options.phase_unit,'rad')),fail('Polar phase_unit must be rad or deg');endif
  if(any(!isfinite(radians(:)))),fail('Polar phase conversion overflow');endif
  linear=double(magnitude);
  if(strcmp(options.magnitude_scale,'db20'))
    if(!isfield(options,'reference')||!isnumeric(options.reference)||!isreal(options.reference)||numel(options.reference)!=columns(magnitude)||any(!isfinite(options.reference(:)))||any(options.reference(:)<=0)),fail('db20 amplitude requires one positive reference value per physical channel');endif
    linear=10.^(linear/20).*reshape(options.reference,1,[]);
  elseif(strcmp(options.magnitude_scale,'linear'))
    if(any(linear(:)<0)||isfield(options,'reference')),fail('Linear amplitudes must be nonnegative and accept no hidden reference');endif
  else,fail('Magnitude scale must be linear or db20 amplitude, never ambiguous power dB');endif
  if(any(!isfinite(linear(:)))),fail('Polar magnitude conversion overflow');endif
  % Trigonometric conversion is invariant under integer phase turns. No phase
  % unwrapping or angle residual is used in the Cartesian fitting objective.
  values=linear.*complex(cos(radians),sin(radians));
  out=struct('schema','gxtxt.complex_observations.v1','values',values,'options',options,...
    'magnitude_sha256',digest(double(magnitude)),'phase_sha256',digest(double(phase)),...
    'conversion','physical_amplitude_times_exp_i_phase','covariance_conversion','none_cartesian_covariance_required',...
    'phase_valid',linear>0);
endfunction
function identity(name)
  if(!ischar(name)||isempty(regexp(name,'^[A-Za-z_][A-Za-z0-9_]{0,63}$','once'))||strncmp(name,'gxtxt_',6)),fail('Invalid complex identity or reserved gxtxt_ prefix');endif
endfunction
function keys(value,allowed,label)
  if(!isstruct(value)||!isscalar(value)||!isempty(setdiff(fieldnames(value),allowed))),fail(['Unknown field or invalid ' label]);endif
endfunction
function value=digest(array)
  bytes=typecast(double(array(:)),'uint8');
  value=hash('sha256',[jsonencode(size(array)) ':' char(bytes(:).')]);
endfunction
function fail(message),error('GXTXT:Numeric:Complex',message);endfunction

function equal=same_identity(a,b)
  if(iscell(a)&&isstruct(b)),b=num2cell(b);elseif(isstruct(a)&&iscell(b)),a=num2cell(a);endif
  if(isstruct(a)&&isstruct(b))
    equal=numel(a)==numel(b)&&isequal(sort(fieldnames(a)),sort(fieldnames(b)));if(!equal),return;endif
    for i=1:numel(a),for field=reshape(fieldnames(a),1,[]),if(!same_identity(a(i).(field{1}),b(i).(field{1}))),equal=false;return;endif;endfor;endfor
  elseif(iscell(a)&&iscell(b))
    equal=numel(a)==numel(b);if(!equal),return;endif
    for i=1:numel(a),if(!same_identity(a{i},b{i})),equal=false;return;endif;endfor
  elseif(isempty(a)&&isempty(b)&&((iscell(a)&&isnumeric(b))||(isnumeric(a)&&iscell(b))))
    equal=true;
  elseif(isnumeric(a)&&isnumeric(b)&&isvector(a)&&isvector(b)),equal=isequaln(a(:),b(:));
  else,equal=isequaln(a,b);endif
endfunction
