% Public nonlinear_evaluate uses the same compiled model as fitting.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_nonlinear_evaluate_v1(model,X,options)
  if(!isstruct(model)||numel(model)!=1||!isfield(model,'parameters')),error('GXTXT:Numeric:Model','Prediction requires a declared model with parameter values');endif
  parameters=model.parameters;
  if(!isnumeric(parameters)||!isreal(parameters)||isempty(parameters)||!isvector(parameters)||any(!isfinite(parameters))),error('GXTXT:Numeric:Model','Prediction parameters must be a finite real vector');endif
  parameters=double(parameters(:));
  if(!isnumeric(X)||!isreal(X)||ndims(X)!=2||isempty(X)),error('GXTXT:Numeric:Model','Prediction requires a nonempty real predictor matrix');endif
  count=1;if(isfield(model,'predictor_ids')),count=numel(model.predictor_ids);if(ischar(model.predictor_ids)),count=1;endif;endif
  X=double(X);if(count==1&&isvector(X)),X=X(:);endif
  [programs,compiled]=gxtxt_numeric_fit_program_v1(model,columns(X),numel(parameters));
  for field={'source_sha256','binding_sha256'}
    key=field{1};if(isfield(model,key)&&!strcmp(model.(key),compiled.(key))),error('GXTXT:Numeric:Model','Persisted model source or bindings changed');endif
  endfor
  native_options=struct('positive_predictor_domain',(isfield(compiled,'kind')&&strcmp(compiled.kind,'power_law'))|| ...
    (isfield(compiled,'composition')&&strcmp(compiled.input_constraints.domain,'positive_real')));
  if(native_options.positive_predictor_domain&&any(X(:)<=0)),error('GXTXT:Numeric:Model','Model prediction requires strictly positive predictor values');endif
  if(isfield(compiled,'kind')&&strcmp(compiled.kind,'gaussian')&&parameters(3)==0),error('GXTXT:Numeric:Model','Gaussian width must be nonzero');endif
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),{'jacobian','predictor_derivative'}))),error('GXTXT:Numeric:Options','Prediction accepts only jacobian and predictor_derivative options');endif
  jacobian=false;
  if(isfield(options,'jacobian'))
    jacobian=options.jacobian;
    if(!(isnumeric(jacobian)||islogical(jacobian))||!isscalar(jacobian)||!isreal(jacobian)||!ismember(jacobian,[0,1])),error('GXTXT:Numeric:Options','jacobian must be boolean');endif
  endif
  derivative=false;
  if(isfield(options,'predictor_derivative'))
    derivative=options.predictor_derivative;
    if(!(isnumeric(derivative)||islogical(derivative))||!isscalar(derivative)||!isreal(derivative)||!ismember(derivative,[0,1])),error('GXTXT:Numeric:Options','predictor_derivative must be boolean');endif
  endif
  if(derivative&&(jacobian||columns(X)!=1)),error('GXTXT:Numeric:Options','Predictor differentiation requires one predictor and a separate parameter-Jacobian request');endif
  if(exist('gxtxt_numeric_ceres_native','file')!=3),error('GXTXT:Numeric:Dependency','Compiled Numeric expression backend is unavailable');endif
  if(derivative)
    out=gxtxt_numeric_ceres_native('differentiate',programs,X,zeros(0,0),zeros(0,0),parameters,native_options);
  elseif(jacobian)
    shape=[rows(X),numel(programs)];
    if(prod(shape)*numel(parameters)*8>512*1024*1024),error('GXTXT:Numeric:Memory','Prediction Jacobian exceeds 512 MiB');endif
    out=gxtxt_numeric_ceres_native('evaluate',programs,X,zeros(shape),ones(shape),parameters,native_options);
    out.evaluation_only=true;
  else
    out=gxtxt_numeric_ceres_native('predict',programs,X,zeros(0,0),zeros(0,0),parameters,native_options);
  endif
  out.source_sha256=compiled.source_sha256;out.binding_sha256=compiled.binding_sha256;
  out.parameter_ids=compiled.parameter_ids;out.predictor_ids=compiled.predictor_ids;
endfunction
